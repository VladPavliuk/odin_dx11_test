package main

// A headless, command-line front-end for the debugger core that the editor GUI also uses.
// Built with `-define:CMD_DEBUGGER=true` (see the `main` dispatcher in main.odin). Both
// front-ends drive the same debug loop (runDebugProcess_Function) through the shared
// `windowData.debugger*` fields, so this is just a stdin REPL over that interface.

import "core:fmt"
import "core:os"
import "core:strings"
import "core:strconv"
import "core:sync"
import win32 "core:sys/windows"

runCmdDebugger :: proc() {
    default_context = context // the debug thread is spawned with this context (see runDebugThread)

    exePath: string
    defer delete(exePath)
    if len(os.args) > 1 {
        exePath = strings.clone(os.args[1])
    }

    printCmdDebuggerHelp()
    if exePath != "" {
        fmt.printfln("target: %s", exePath)
    }

    lineBuf: [1024]u8
    for {
        fmt.print("(dbg) ")

        line, ok := cmdReadLine(lineBuf[:])
        if !ok { break } // stdin closed (EOF)
        if line == "" { continue }

        cmd := line
        rest := ""
        if spaceIdx := strings.index_byte(line, ' '); spaceIdx >= 0 {
            cmd = line[:spaceIdx]
            rest = strings.trim_space(line[spaceIdx + 1:])
        }

        switch cmd {
        case "help", "h", "?":
            printCmdDebuggerHelp()
        case "exe":
            if rest == "" {
                fmt.println("usage: exe <path>")
                break
            }
            delete(exePath)
            exePath = strings.clone(rest)
            fmt.printfln("target: %s", exePath)
        case "b", "break":
            if !cmdToggleBreakpoint(rest) {
                fmt.println("usage: b <file>:<line>")
            }
        case "bl":
            if len(windowData.debuggerBrakepoints) == 0 {
                fmt.println("no breakpoints")
            } else {
                for bp, i in windowData.debuggerBrakepoints {
                    fmt.printfln("  [%d] %s:%d", i, bp.filePath, bp.line)
                }
            }
        case "run", "r":
            if exePath == "" {
                fmt.println("no target set (use: exe <path>)")
                break
            }
            if !os.exists(exePath) {
                fmt.printfln("not found: %s", exePath)
                break
            }
            if windowData.debuggerThread != nil {
                fmt.println("a session is already running (use: stop)")
                break
            }
            sync.atomic_store(&windowData.debuggerPaused, false)
            fmt.printfln("launching %s ...", exePath)
            runDebugThread(exePath)
            cmdWaitForStopOrExit()
        case "c", "continue":
            if !cmdEnsureRunning() { break }
            cmdResume(.CONTINUE)
        case "s", "step", "n", "next":
            if !cmdEnsureRunning() { break }
            cmdResume(.STEP_OVER)
        case "si", "stepi":
            if !cmdEnsureRunning() { break }
            cmdResume(.STEP_INTO)
        case "p", "locals":
            cmdPrintLocals()
        case "bt", "k", "stack":
            cmdPrintCallStack()
        case "w", "where":
            cmdPrintLocation()
        case "stop":
            if windowData.debuggerThread == nil {
                fmt.println("not running")
                break
            }
            stopDebuggerThread()
            windowData.debuggingFinished = false
            fmt.println("debuggee stopped")
        case "q", "quit", "exit":
            if windowData.debuggerThread != nil {
                stopDebuggerThread()
            }
            return
        case:
            fmt.printfln("unknown command: %s (try: help)", cmd)
        }
    }

    if windowData.debuggerThread != nil {
        stopDebuggerThread()
    }
}

printCmdDebuggerHelp :: proc() {
    fmt.println("=== cmd debugger ===")
    fmt.println("  exe <path>        set the target exe to debug")
    fmt.println("  b <file>:<line>   toggle a breakpoint (set before/while running)")
    fmt.println("  bl                list breakpoints")
    fmt.println("  run | r           launch the target under the debugger")
    fmt.println("  c                 continue to the next breakpoint")
    fmt.println("  s | n             step over (run the line, including calls)")
    fmt.println("  si                step into (descend into a called function)")
    fmt.println("  p                 print locals at the current stop")
    fmt.println("  bt | k            print the call stack at the current stop")
    fmt.println("  w | where         print the current stop location")
    fmt.println("  stop              kill the debuggee")
    fmt.println("  q | quit          exit")
}

// Reads a single line from stdin (one byte at a time so it behaves the same for an interactive
// console and for piped input). Returns ok=false only on EOF with nothing buffered.
cmdReadLine :: proc(buf: []u8) -> (string, bool) {
    i := 0
    for i < len(buf) {
        b: [1]u8
        n, err := os.read(os.stdin, b[:])
        if n <= 0 || err != nil {
            if i == 0 { return "", false } // EOF at the start of a line
            break                          // EOF after a final line with no newline
        }
        if b[0] == '\n' { break }
        buf[i] = b[0]
        i += 1
    }
    return strings.trim_space(string(buf[:i])), true
}

// Splits "<file>:<line>" on the LAST ':' so a Windows drive letter (C:\...) is preserved.
cmdToggleBreakpoint :: proc(arg: string) -> bool {
    colonIdx := strings.last_index_byte(arg, ':')
    if colonIdx <= 0 { return false }

    filePath := strings.trim_space(arg[:colonIdx])
    line, lineOk := strconv.parse_int(strings.trim_space(arg[colonIdx + 1:]))
    if !lineOk || filePath == "" { return false }

    if existBrakepointInManager(filePath, i32(line)) != -1 {
        toggleBrakepointForLine(filePath, i32(line)) // removes the existing (owned) entry
        fmt.printfln("breakpoint removed: %s:%d", filePath, line)
    } else {
        // store an owned copy; `filePath` here aliases the stdin read buffer
        toggleBrakepointForLine(strings.clone(filePath), i32(line))
        fmt.printfln("breakpoint set: %s:%d", filePath, line)
    }
    return true
}

cmdEnsureRunning :: proc() -> bool {
    if windowData.debuggerThread == nil {
        fmt.println("not running (use: run)")
        return false
    }
    if windowData.debuggingFinished {
        fmt.println("debuggee has exited")
        return false
    }
    return true
}

// Issues a resume command and blocks until the debuggee stops again or exits. We clear the
// paused flag ourselves first so we don't observe the stale "paused" from the current stop.
cmdResume :: proc(command: DebuggerCommand) {
    sync.atomic_store(&windowData.debuggerPaused, false)
    sync.atomic_store(&windowData.debuggerCommand, command)
    cmdWaitForStopOrExit()
}

cmdWaitForStopOrExit :: proc() {
    for {
        if windowData.debuggingFinished {
            fmt.println("debuggee exited")
            stopDebuggerThread() // mirror the GUI's cleanup so a fresh `run` can start
            windowData.debuggingFinished = false
            return
        }
        if sync.atomic_load(&windowData.debuggerPaused) {
            cmdPrintLocation()
            return
        }
        win32.Sleep(2)
    }
}

cmdPrintLocation :: proc() {
    instr := windowData.currentDebuggerInstruction
    if instr.filePath == "" {
        fmt.println("stopped (no source mapping)")
    } else {
        fmt.printfln("stopped at %s:%d", instr.filePath, instr.line)
    }
}

cmdPrintLocals :: proc() {
    sync.mutex_lock(&windowData.debuggerLocalsMutex)
    defer sync.mutex_unlock(&windowData.debuggerLocalsMutex)

    if len(windowData.debuggerLocals) == 0 {
        fmt.println("no locals")
        return
    }
    for v in windowData.debuggerLocals {
        fmt.printfln("  %s = %s", v.name, v.value)
    }
}

cmdPrintCallStack :: proc() {
    sync.mutex_lock(&windowData.debuggerCallStackMutex)
    defer sync.mutex_unlock(&windowData.debuggerCallStackMutex)

    if len(windowData.debuggerCallStack) == 0 {
        fmt.println("no call stack")
        return
    }
    for frame, i in windowData.debuggerCallStack {
        if frame.filePath != "" {
            fmt.printfln("  #%d %s  (%s:%d)", i, frame.function, frame.filePath, frame.line)
        } else {
            fmt.printfln("  #%d %s", i, frame.function)
        }
    }
}
