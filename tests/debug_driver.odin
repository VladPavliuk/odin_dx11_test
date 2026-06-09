package tests

// Headless driver for the debugger core (no editor window, no synthetic input). It drives the same
// debug thread the GUI/CLI use, purely through the shared windowData.debugger* fields, so these tests
// are safe to run on their own (unlike the SendInput integration tests). Run them filtered, e.g.:
//   odin test . -debug -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_NAMES=tests.arithmetic_step_and_locals,...
// (or just run the whole suite). The C++ fixtures under tests/cpp are built by tests/cpp/compile.bat.

import "base:runtime"
import "core:os"
import "core:sync"
import "core:time"
import "core:fmt"
import "core:strings"
import "core:strconv"
import "core:path/filepath"

import main "../"

// The debugger core allocates/frees persistent state (debuggerExePath, locals, call stack) on the
// debug thread and frees it later on the test thread. `odin test` gives each test its own tracking
// allocator, so using it would (a) be touched concurrently from the debug thread (not thread-safe) and
// (b) free test-1's allocations with test-2's allocator -> bad free / segfault. Pin everything that
// crosses those boundaries to the process heap instead.
@(private = "file")
heapContext :: proc() -> runtime.Context {
    c := runtime.default_context()
    return c
}

// Absolute path of the tests/cpp fixtures folder (backslashes, to match the paths baked into the pdbs),
// discovered relative to wherever `odin test` is run from.
fixtureDir :: proc() -> string {
    for candidate in ([]string{ "tests/cpp", "cpp", "../tests/cpp" }) {
        if os.is_dir(candidate) {
            if abs, ok := filepath.abs(candidate); ok {
                back, _ := strings.replace_all(abs, "/", "\\", context.temp_allocator)
                return strings.trim_suffix(back, "\\")
            }
        }
    }
    return ""
}

// (exe path, source path) for a fixture name, e.g. "arithmetic" -> tests/cpp/arithmetic/arithmetic.*
fixturePaths :: proc(name: string) -> (exe: string, src: string) {
    dir := fixtureDir()
    exe = fmt.tprintf("%s\\%s\\%s.exe", dir, name, name)
    src = fmt.tprintf("%s\\%s\\%s.cpp", dir, name, name)
    return
}

dbgSetBreakpoint :: proc(src: string, line: i32) {
    context = heapContext()
    main.toggleBrakepointForLine(strings.clone(src), line) // stored directly, so hand it an owned copy
}

dbgClearBreakpoints :: proc() {
    clear(&main.windowData.debuggerBrakepoints) // leaks the cloned paths; fine for a short test run
}

// Launches the debuggee (breakpoints must be set first) on the debug thread.
dbgStart :: proc(exe: string) {
    context = heapContext()
    main.default_context = context // the debug thread inherits this; keep it on the process heap
    main.windowData.debuggingFinished = false
    sync.atomic_store(&main.windowData.debuggerPaused, false)
    main.runDebugThread(exe)
}

// Blocks until the debuggee pauses at a stop (true) or exits / times out (false).
dbgWaitStop :: proc(timeoutMs := 15000) -> bool {
    start := time.tick_now()
    for {
        if main.windowData.debuggingFinished { return false }
        if sync.atomic_load(&main.windowData.debuggerPaused) { return true }
        if time.duration_milliseconds(time.tick_since(start)) > f64(timeoutMs) { return false }
        time.sleep(2 * time.Millisecond)
    }
}

// Issues a resume command (CONTINUE / STEP_OVER / STEP_INTO / STEP_OUT) and waits for the next stop.
dbgResume :: proc(cmd: main.DebuggerCommand, timeoutMs := 15000) -> bool {
    sync.atomic_store(&main.windowData.debuggerPaused, false)
    sync.atomic_store(&main.windowData.debuggerCommand, cmd)
    return dbgWaitStop(timeoutMs)
}

dbgLine :: proc() -> i32 {
    return main.windowData.currentDebuggerInstruction.line
}

// Value of an integer local by name at the current stop (parses readDebuggerValue's "<dec> (0x..)").
dbgLocalInt :: proc(name: string) -> (i64, bool) {
    sync.mutex_lock(&main.windowData.debuggerLocalsMutex)
    defer sync.mutex_unlock(&main.windowData.debuggerLocalsMutex)

    for v in main.windowData.debuggerLocals {
        if v.name == name {
            text := v.value
            if idx := strings.index(text, " ("); idx >= 0 { text = text[:idx] }
            return strconv.parse_i64(text)
        }
    }
    return 0, false
}

dbgRegisters :: proc() -> main.DebuggerRegisters {
    return main.windowData.debuggerRegisters
}

// Address and byte size of a frame-relative local by name (for read/write/set tests).
dbgLocalAddress :: proc(name: string) -> (uintptr, u32, bool) {
    sync.mutex_lock(&main.windowData.debuggerLocalsMutex)
    defer sync.mutex_unlock(&main.windowData.debuggerLocalsMutex)

    for v in main.windowData.debuggerLocals {
        if v.name == name { return v.address, v.size, v.address != 0 }
    }
    return 0, 0, false
}

// Runs to `line` in `src` (one-shot breakpoint), waiting for the stop. False if it exited/timed out.
dbgRunTo :: proc(src: string, line: i32, timeoutMs := 15000) -> bool {
    context = heapContext()
    delete(main.windowData.debuggerRunToFile)
    main.windowData.debuggerRunToFile = strings.clone(src)
    main.windowData.debuggerRunToLine = line
    return dbgResume(.RUN_TO, timeoutMs)
}

// Function name of the innermost (top) call-stack frame at the current stop.
dbgTopFrame :: proc() -> string {
    sync.mutex_lock(&main.windowData.debuggerCallStackMutex)
    defer sync.mutex_unlock(&main.windowData.debuggerCallStackMutex)

    if len(main.windowData.debuggerCallStack) == 0 { return "" }
    return strings.clone(main.windowData.debuggerCallStack[0].function, context.temp_allocator)
}

dbgCallStackDepth :: proc() -> int {
    sync.mutex_lock(&main.windowData.debuggerCallStackMutex)
    defer sync.mutex_unlock(&main.windowData.debuggerCallStackMutex)
    return len(main.windowData.debuggerCallStack)
}

// Number of top frames whose function name equals `fn` (for measuring recursion depth).
dbgFramesNamed :: proc(fn: string) -> int {
    sync.mutex_lock(&main.windowData.debuggerCallStackMutex)
    defer sync.mutex_unlock(&main.windowData.debuggerCallStackMutex)

    count := 0
    for frame in main.windowData.debuggerCallStack {
        if frame.function == fn { count += 1 }
    }
    return count
}

// Kills the debuggee, joins the debug thread and clears breakpoints. Safe to call when nothing runs.
dbgStop :: proc() {
    context = heapContext() // free locals/call-stack with the same allocator the debug thread used
    if main.windowData.debuggerThread != nil {
        main.stopDebuggerThread()
    }
    main.windowData.debuggingFinished = false
    dbgClearBreakpoints()
}
