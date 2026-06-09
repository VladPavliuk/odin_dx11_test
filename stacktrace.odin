package main

// Call-stack unwinding for the debugger. On x64 you can't reliably chase RBP (MSVC /Od frames
// use positive RBP offsets), so we use StackWalk64 to unwind via the real .pdata unwind info,
// then symbolize each frame with the DIA helpers already used elsewhere.
//
// We deliberately do NOT use DbgHelp's symbol handler (SymInitialize/SymFunctionTableAccess64):
// reusing it across stops while the debuggee is frozen made the 2nd+ StackWalk64 hang inside
// DbgHelp. Instead we feed StackWalk64 our own callbacks that read the module list and each
// module's .pdata straight from the debuggee, so there is no DbgHelp state to corrupt.

import "core:fmt"
import "core:strings"
import "core:sync"
import win32 "core:sys/windows"

foreign import dbghelp "system:Dbghelp.lib"

// StackWalk64's callback parameter types (typed so our callbacks pass without a cast).
ReadMemoryProc64 :: #type proc "std" (hProcess: win32.HANDLE, qwBaseAddress: win32.DWORD64, lpBuffer: rawptr, nSize: win32.DWORD, lpNumberOfBytesRead: ^win32.DWORD) -> win32.BOOL
FunctionTableAccessProc64 :: #type proc "std" (hProcess: win32.HANDLE, AddrBase: win32.DWORD64) -> rawptr
GetModuleBaseProc64 :: #type proc "std" (hProcess: win32.HANDLE, Address: win32.DWORD64) -> win32.DWORD64
TranslateAddressProc64 :: #type proc "std" (hProcess: win32.HANDLE, hThread: win32.HANDLE, lpaddr: ^ADDRESS64) -> win32.DWORD64

@(default_calling_convention = "std")
foreign dbghelp {
    StackWalk64 :: proc(
        MachineType: win32.DWORD,
        hProcess: win32.HANDLE,
        hThread: win32.HANDLE,
        StackFrame: ^STACKFRAME64,
        ContextRecord: rawptr,
        ReadMemoryRoutine: ReadMemoryProc64,
        FunctionTableAccessRoutine: FunctionTableAccessProc64,
        GetModuleBaseRoutine: GetModuleBaseProc64,
        TranslateAddress: TranslateAddressProc64,
    ) -> win32.BOOL ---
}

IMAGE_FILE_MACHINE_AMD64 :: 0x8664
ADDR_MODE_FLAT :: 3 // ADDRESS_MODE.AddrModeFlat

ADDRESS64 :: struct {
    Offset:  win32.DWORD64,
    Segment: win32.WORD,
    Mode:    win32.DWORD, // ADDRESS_MODE
}

STACKFRAME64 :: struct {
    AddrPC:        ADDRESS64,
    AddrReturn:    ADDRESS64,
    AddrFrame:     ADDRESS64,
    AddrStack:     ADDRESS64,
    AddrBStore:    ADDRESS64,
    FuncTableEntry: rawptr,
    Params:        [4]win32.DWORD64,
    Far:           win32.BOOL,
    Virtual:       win32.BOOL,
    Reserved:      [3]win32.DWORD64,
    KdHelp:        [14]win32.DWORD64, // KDHELP64 (we never read it; sized so StackWalk64 won't overrun)
}

// An x64 .pdata entry (IMAGE_RUNTIME_FUNCTION_ENTRY): the unwind table StackWalk64 needs per frame.
RUNTIME_FUNCTION :: struct {
    BeginAddress:      u32,
    EndAddress:        u32,
    UnwindInfoAddress: u32,
}

// Set for the duration of a walk so the "std" callbacks (which can't take extra args) can see the
// debuggee's modules. Only ever used on the debug thread, one walk at a time.
@(private="file") walkProcess: win32.HANDLE
@(private="file") walkModules: []DebuggerModule
@(private="file") walkRuntimeFunction: RUNTIME_FUNCTION // backing storage returned to StackWalk64

walkModuleBaseAt :: proc "contextless" (addr: uintptr) -> (base: uintptr, size: i32) {
    for module in walkModules {
        if addr >= module.address && addr < module.address + uintptr(module.size) {
            return module.address, module.size
        }
    }
    return 0, 0
}

// StackWalk64 callback: base address of the module containing `addr`.
walkGetModuleBase :: proc "std" (hProcess: win32.HANDLE, addr: win32.DWORD64) -> win32.DWORD64 {
    base, _ := walkModuleBaseAt(uintptr(addr))
    return win32.DWORD64(base)
}

// StackWalk64 callback: the .pdata RUNTIME_FUNCTION covering `addrBase`, read from the debuggee.
// Returns nil for leaf functions / addresses with no unwind entry (StackWalk64 handles that).
walkFunctionTableAccess :: proc "std" (hProcess: win32.HANDLE, addrBase: win32.DWORD64) -> rawptr {
    base, _ := walkModuleBaseAt(uintptr(addrBase))
    if base == 0 { return nil }
    rva := u32(uintptr(addrBase) - base)

    read: uint
    dos: win32.IMAGE_DOS_HEADER
    if !win32.ReadProcessMemory(hProcess, rawptr(base), &dos, size_of(dos), &read) { return nil }
    nt: win32.IMAGE_NT_HEADERS64
    if !win32.ReadProcessMemory(hProcess, rawptr(base + uintptr(dos.e_lfanew)), &nt, size_of(nt), &read) { return nil }

    pdataRva := nt.OptionalHeader.ExceptionTable.VirtualAddress
    pdataSize := nt.OptionalHeader.ExceptionTable.Size
    if pdataRva == 0 || pdataSize == 0 { return nil }

    // .pdata is sorted by BeginAddress, so binary search it (reading one entry per probe).
    lo := 0
    hi := int(pdataSize / size_of(RUNTIME_FUNCTION)) - 1
    for lo <= hi {
        mid := (lo + hi) / 2
        entryAddr := base + uintptr(pdataRva) + uintptr(mid * size_of(RUNTIME_FUNCTION))
        rf: RUNTIME_FUNCTION
        if !win32.ReadProcessMemory(hProcess, rawptr(entryAddr), &rf, size_of(rf), &read) { return nil }

        if rva < rf.BeginAddress {
            hi = mid - 1
        } else if rva >= rf.EndAddress {
            lo = mid + 1
        } else {
            walkRuntimeFunction = rf
            return &walkRuntimeFunction
        }
    }
    return nil
}

// Returns the address the current function will return to (its caller's resume point), via a single
// StackWalk64 unwind step using the same .pdata-driven logic as the full call-stack walk. Step-out
// plants a breakpoint there to run out of the current frame. ok=false when there's no caller to return
// to (outermost frame) or the unwind produced no return address.
returnAddressOf :: proc(process: win32.HANDLE, hThread: win32.HANDLE, threadCtx: win32.CONTEXT, modules: []DebuggerModule) -> (returnAddress: uintptr, ok: bool) {
    walkProcess = process
    walkModules = modules

    ctx := threadCtx

    frame: STACKFRAME64
    frame.AddrPC.Offset = u64(ctx.Rip)
    frame.AddrPC.Mode = ADDR_MODE_FLAT
    frame.AddrFrame.Offset = u64(ctx.Rbp)
    frame.AddrFrame.Mode = ADDR_MODE_FLAT
    frame.AddrStack.Offset = u64(ctx.Rsp)
    frame.AddrStack.Mode = ADDR_MODE_FLAT

    // The first StackWalk64 step describes the current frame and fills in AddrReturn (the caller's PC).
    if !StackWalk64(IMAGE_FILE_MACHINE_AMD64, process, hThread, &frame, &ctx,
        nil, walkFunctionTableAccess, walkGetModuleBase, nil) {
        return 0, false
    }

    ret := uintptr(frame.AddrReturn.Offset)
    return ret, ret != 0
}

// Walks the paused thread's stack and publishes a resolved snapshot to windowData.debuggerCallStack.
// Runs on the debug thread while the debuggee is stopped (memory is read via ReadProcessMemory).
// `threadCtx` is copied because StackWalk64 mutates it as it unwinds.
collectDebuggerCallStack :: proc(process: win32.HANDLE, hThread: win32.HANDLE, threadCtx: win32.CONTEXT, modules: []DebuggerModule) {
    walkProcess = process
    walkModules = modules

    ctx := threadCtx

    frame: STACKFRAME64
    frame.AddrPC.Offset = u64(ctx.Rip)
    frame.AddrPC.Mode = ADDR_MODE_FLAT
    frame.AddrFrame.Offset = u64(ctx.Rbp)
    frame.AddrFrame.Mode = ADDR_MODE_FLAT
    frame.AddrStack.Offset = u64(ctx.Rsp)
    frame.AddrStack.Mode = ADDR_MODE_FLAT

    newStack := make([dynamic]DebuggerStackFrame)

    MAX_FRAMES :: 256
    for _ in 0 ..< MAX_FRAMES {
        if !StackWalk64(IMAGE_FILE_MACHINE_AMD64, process, hThread, &frame, &ctx,
            nil, walkFunctionTableAccess, walkGetModuleBase, nil) {
            break
        }

        pc := uintptr(frame.AddrPC.Offset)
        if pc == 0 { break } // reached the bottom of the stack

        append(&newStack, resolveStackFrame(pc, modules))
    }

    sync.mutex_lock(&windowData.debuggerCallStackMutex)
    freeDebuggerCallStackContents(&windowData.debuggerCallStack)
    delete(windowData.debuggerCallStack)
    windowData.debuggerCallStack = newStack
    sync.mutex_unlock(&windowData.debuggerCallStackMutex)
}

// Maps an absolute instruction address to a frame label. Modules with a pdb get a function name
// and source line; others fall back to nearest-export or module+offset. All returned strings are
// owned by the frame (so freeDebuggerCallStackContents can release them).
resolveStackFrame :: proc(pc: uintptr, modules: []DebuggerModule) -> DebuggerStackFrame {
    for module in modules {
        if pc < module.address || pc >= module.address + uintptr(module.size) { continue }

        rva := u32(pc - module.address)

        if len(module.pdbFiles) > 0 {
            session := module.pdbFiles[0].session
            name, nameOk := getFunctionNameByRVA(session, rva)
            file, line, _, _ := getSourcePositionByRVA(session, rva)

            // DIA returns these via temp_allocator; clone to the heap so freeDebuggerCallStackContents
            // can delete() them safely (otherwise the next collection's free is a bad free).
            ownedFile := strings.clone(file) if len(file) > 0 else ""

            if nameOk {
                return { function = strings.clone(name), filePath = ownedFile, line = i32(line) }
            }
            // No function symbol here; `name` is a non-owned literal, so synthesize an owned label.
            return { function = fmt.aprintf("%s+0x%X", module.name, u64(rva)), filePath = ownedFile, line = i32(line) }
        }

        if exportName, off, found := nearestExportName(module, pc); found {
            return { function = fmt.aprintf("%s!%s+0x%X", module.name, exportName, u64(off)) }
        }
        return { function = fmt.aprintf("%s+0x%X", module.name, u64(rva)) }
    }

    return { function = fmt.aprintf("0x%X", u64(pc)) }
}

// Closest exported function at or before `pc` (a coarse name for modules without a pdb).
nearestExportName :: proc(module: DebuggerModule, pc: uintptr) -> (string, uintptr, bool) {
    bestName: string
    bestOffset := uintptr(max(u64) >> 1)
    found := false
    for fn in module.exportFunctions {
        if pc >= fn.address {
            off := pc - fn.address
            if off < bestOffset {
                bestOffset = off
                bestName = fn.name
                found = true
            }
        }
    }
    return bestName, bestOffset, found
}

freeDebuggerCallStackContents :: proc(stack: ^[dynamic]DebuggerStackFrame) {
    for frame in stack {
        delete(frame.function)
        delete(frame.filePath)
    }
}

clearDebuggerCallStack :: proc() {
    sync.mutex_lock(&windowData.debuggerCallStackMutex)
    defer sync.mutex_unlock(&windowData.debuggerCallStackMutex)

    freeDebuggerCallStackContents(&windowData.debuggerCallStack)
    clear(&windowData.debuggerCallStack)
}
