package main

import "core:sync"
import "core:thread"
import "core:strings"
import "core:os"
import win32 "core:sys/windows"
import "base:intrinsics"

foreign import kernel32 "system:Kernel32.lib"
foreign import psapi "system:Psapi.lib"
foreign import zycore "libs/Zycore.lib"
foreign import zydis "libs/Zydis.lib"

@(default_calling_convention = "std")
foreign kernel32 {
    DebugActiveProcess :: proc(dwProcessId: win32.DWORD) -> win32.BOOL ---
    WaitForDebugEvent :: proc(lpDebugEvent: ^WIN32_DEBUG_EVENT, dwMilliseconds: win32.DWORD) -> win32.BOOL ---
    ContinueDebugEvent :: proc(dwProcessId: win32.DWORD, dwThreadId: win32.DWORD, dwContinueStatus: win32.DWORD) -> win32.BOOL ---
    GetThreadId :: proc(Thread: win32.HANDLE) -> win32.DWORD ---
    FlushInstructionCache :: proc(hProcess: win32.HANDLE, lpBaseAddress: win32.LPCVOID, dwSize: win32.SIZE_T) -> win32.BOOL ---
}

@(default_calling_convention = "std")
foreign psapi {
    EnumProcesses :: proc(lpidProcess: ^win32.DWORD, cb: win32.DWORD, lpcbNeeded: win32.LPDWORD) -> win32.BOOL ---
    EnumProcessModules :: proc(hProcess: win32.HANDLE, lphModule: ^win32.HMODULE, cb: win32.DWORD, lpcbNeeded: win32.LPDWORD) -> win32.BOOL ---
    GetModuleBaseNameW :: proc(hProcess: win32.HANDLE, hModule: win32.HMODULE, lpBaseName: win32.LPWSTR, nSize: win32.DWORD) -> win32.DWORD ---
}

@(default_calling_convention = "std")
foreign zydis {
    //@(link_name = "ZydisDisassembleIntel")
    ZydisDisassembleIntel :: proc(machine_mode: u32, runtime_address: rawptr, buffer: rawptr, length: u64, instruction: rawptr) -> u32 ---
    // ZydisRegisterGetId :: proc(machine_mode: u32) -> i8 ---
}

TRAP_FLAG :: 1 << 8;

DebuggerCommand :: enum {
    NONE,
    CONTINUE,
    STEP_OVER, // run the current source line, stepping over calls
    STEP_INTO, // advance one source line, descending into calls that have source info
    STEP_OUT,  // run until the current function returns to its caller
    STEP_INSTRUCTION, // execute exactly one machine instruction
    RUN_TO,    // run until debuggerRunToFile:debuggerRunToLine (or an earlier breakpoint)
}

// How a source-level step is currently progressing on the debug thread (driven by the stepping
// engine in the debug loop). None means we're not stepping.
StepMode :: enum {
    None,
    Over,
    Into,
    Out,
    Instruction, // single-step exactly one machine instruction, then stop
}

// Snapshot of the paused thread's x64 general-purpose registers, captured at each stop.
DebuggerRegisters :: struct {
    rax, rbx, rcx, rdx, rsi, rdi, rbp, rsp:   u64,
    r8, r9, r10, r11, r12, r13, r14, r15:     u64,
    rip, rflags:                              u64,
}

SingleBrakepoint :: struct {
    filePath: string,
    line: i32,
}

// A local variable / parameter snapshot taken while the debuggee is paused.
DebuggerVariable :: struct {
    name: string,
    value: string,
    address: uintptr, // where it lives in the debuggee (for read/write); 0 if not frame-relative
    size: u32,        // byte size from its type (for set-variable writes)
}

ExportFunction :: struct {
    name: string,
    address: uintptr,
}

// A module (the exe or a loaded DLL) discovered while debugging, together with whatever symbol
// sources we found for it. Used for address->symbol resolution, e.g. building a call stack.
DebuggerModule :: struct {
    name: string,
    address: uintptr,
    size: i32,
    pdbFiles: [dynamic]PdbData,
    exportFunctions: [dynamic]ExportFunction,
}

// A single resolved call-stack frame captured while the debuggee is paused. Both strings are
// owned (freed by freeDebuggerCallStackContents); filePath is "" when there's no source mapping.
DebuggerStackFrame :: struct {
    function: string,
    filePath: string,
    line: i32,
}

existBrakepointInManager :: proc(filePath: string, line: i32) -> i32 {
    for brakepoint, index in windowData.debuggerBrakepoints {
        if brakepoint.filePath == filePath && brakepoint.line == line {
            return i32(index)
        }
    }
    return -1
}

toggleBrakepointForLine :: proc(filePath: string, line: i32) {
    index := existBrakepointInManager(filePath, line)

    if index == -1 {
        append(&windowData.debuggerBrakepoints, SingleBrakepoint{ filePath, line })
    } else {
        ordered_remove(&windowData.debuggerBrakepoints, index)
    }
}

applyBreakpoint :: proc(process: win32.HANDLE, address: uintptr, appliedBreakpoints: ^map[uintptr]u8) {
    originalByte: u8

    bytesRead, bytesWritten: uint

    res := win32.ReadProcessMemory(process, win32.LPCVOID(address), &originalByte, 1, &bytesRead)
    assert(res == true && bytesRead == 1)

    breakpointInstruction: u8 = 0xCC
    res = win32.WriteProcessMemory(process, win32.LPCVOID(address), &breakpointInstruction, 1, &bytesWritten)
    assert(res == true && bytesWritten == 1)

    // res = win32.FlushInstructionCache(process, win32.LPCVOID(address), 1);
    // assert(res == true)

    appliedBreakpoints[address] = originalByte
}

removeBreakpoint :: proc(process: win32.HANDLE, breakpointAddress: uintptr, appliedBreakpoints: ^map[uintptr]u8) {
    originalByte, ok := appliedBreakpoints[breakpointAddress]
    assert(ok)

    bytesWritten: uint
    res := win32.WriteProcessMemory(process, win32.LPCVOID(breakpointAddress), &originalByte, 1, &bytesWritten)
    assert(res == true && bytesWritten == 1)

    res = FlushInstructionCache(process, win32.LPCVOID(breakpointAddress), 1);
    assert(res == true)

    delete_key(appliedBreakpoints, breakpointAddress)
}

// Writes the original instruction byte back without unregistering the breakpoint, so it
// can be re-armed after we single-step over it (lets a breakpoint fire more than once).
restoreOriginalInstruction :: proc(process: win32.HANDLE, address: uintptr, originalByte: u8) {
    original := originalByte
    bytesWritten: uint
    res := win32.WriteProcessMemory(process, win32.LPCVOID(address), &original, 1, &bytesWritten)
    assert(res == true && bytesWritten == 1)

    res = FlushInstructionCache(process, win32.LPCVOID(address), 1)
    assert(res == true)
}

setHardwareBreakpointForThread :: proc(threadId: u32, address: uintptr) {  
    threadHandler := win32.OpenThread(
        win32.THREAD_GET_CONTEXT | win32.THREAD_SET_CONTEXT,
        false,
        threadId,
    )
    defer win32.CloseHandle(threadHandler)
    
    ctx: win32.CONTEXT
    ctx.ContextFlags = win32.WOW64_CONTEXT_ALL
    win32.GetThreadContext(threadHandler, &ctx)

    if uintptr(ctx.Rip) == address {
        ctx.Dr0 = 0
    } else {
        ctx.Dr0 = win32.DWORD64(address)
    }
    ctx.Dr7 |= 0x1

    ctx.EFlags |= (1 << 16) // set resume flag
    // ctx.Dr7 |= (1 << 16)
    
    if !win32.SetThreadContext(threadHandler, &ctx) {
        fmt.println(win32.GetLastError())
        //panic("ERROR ")
    }
}

stopDebuggerThread :: proc() {
    if windowData.debuggerThread == nil { return }

    win32.TerminateProcess(windowData.debuggerProcessHandler, 0)
    for !thread.is_done(windowData.debuggerThread) { win32.Sleep(1) }

    thread.join(windowData.debuggerThread)
    thread.destroy(windowData.debuggerThread)

    windowData.debuggerThread = nil
    win32.CloseHandle(windowData.debuggerProcessHandler)

    clearDebuggerLocals()
    clearDebuggerCallStack()
}

runDebugThread :: proc(exePath: string) {
    if windowData.debuggerThread != nil { return } // a session is already running

    // Own the path so it stays alive for the worker thread (it outlives the caller's buffer).
    // Clone first: exePath may alias windowData.debuggerExePath (e.g. the F5 re-run path), so
    // deleting before cloning would read freed memory.
    newExePath := strings.clone(exePath)
    delete(windowData.debuggerExePath)
    windowData.debuggerExePath = newExePath

    windowData.debuggerThread = thread.create_and_start_with_poly_data(windowData.debuggerExePath, runDebugProcess_Function, default_context)
}

// ThreadContext :: struct #align(16) {
//     ctx: win32.CONTEXT,
// }

runDebugProcess_Function :: proc(exePath: string) {
    // working_dir_w := (win32_utf8_to_wstring(desc.working_dir, temp_allocator()) or_else nil) if len(desc.working_dir) > 0 else nil
	processInfo: win32.PROCESS_INFORMATION
	ok := win32.CreateProcessW(
		win32.utf8_to_wstring(exePath),
		nil,
		nil,
		nil,
		false,
		win32.DEBUG_PROCESS | win32.DEBUG_ONLY_THIS_PROCESS | win32.CREATE_UNICODE_ENVIRONMENT | win32.HIGH_PRIORITY_CLASS | win32.CREATE_NEW_CONSOLE,
		// win32.DEBUG_ONLY_THIS_PROCESS | win32.CREATE_NEW_CONSOLE,
		nil, // it's for passing env data???
        nil, // win32.utf8_to_wstring("C:\\projects\\mandelbrot_set_odin\\bin"),
		&win32.STARTUPINFOW{
			cb = size_of(win32.STARTUPINFOW),
            dwFlags = 0x00000001 | win32.STARTF_USESTDHANDLES, //STARTF_USESHOWWINDOW
            wShowWindow = 5, // SW_SHOW
			// hStdError  = stderr_handle,
			// hStdOutput = stdout_handle,
			// hStdInput  = stdin_handle,
			// dwFlags = win32.STARTF_USESTDHANDLES,
		},
		&processInfo,
	)

	if !ok {
		panic("FAILED")
	}
    windowData.debuggingFinished = false

    defer windowData.currentDebuggerInstruction = SingleBrakepoint {
        filePath = "", line = 0
    }
    
    defer windowData.debuggingFinished = true

    modules := make([dynamic]DebuggerModule)
    defer delete(modules)

    PdbInfo :: struct {
        signature: u32,
        guid: win32.GUID,
        age: u32,
    }

    win32.CloseHandle(processInfo.hThread)
    // defer win32.CloseHandle(processInfo.hThread)
    
    sync.atomic_store(&windowData.debuggerProcessHandler, processInfo.hProcess)

    debugEvent: WIN32_DEBUG_EVENT
    expectStepException := false

    appliedBreakpoints := make(map[uintptr]u8)
    tmpBreakpoints := make(map[uintptr]u8)
    defer delete(appliedBreakpoints)
    defer delete(tmpBreakpoints)

    threadsIds := make([dynamic]u32)

    // The debuggee's own pdb, discovered from its debug directory once the process is created.
    // All source<->address mapping uses this instead of a hardcoded path, so any exe with a pdb works.
    exePdbData: PdbData
    exePdbValid := false
    defer if exePdbValid {
        exePdbData.globalSymbol->Release()
        exePdbData.session->Release()
    }

    exeBaseAddress: uintptr = 0
    exeImageSize: u32 = 0

    stepMode := StepMode.None
    stepStartFile: string // owned clone of the source file a step began from
    stepStartLine: u32 = 0
    stepStartSp: u64 = 0  // RSP when the step began; keeps step-over from stopping inside a callee
    stepOutTarget: uintptr = 0 // for step-out: the caller's return address we're running to

    rearmAddress: uintptr = 0  // a hit breakpoint waiting to be single-stepped over and re-armed
    suppressPauseOnce := false // skip the source-line pause for the upcoming re-arm single-step

    for WaitForDebugEvent(&debugEvent, WIN32_INFINITE) {
        continueStatus: u32 = WIN32_DBG_EXCEPTION_NOT_HANDLED // why should it be always that and not WIN32_DBG_CONTINUE???
        exitDebugger := false

        // if sync.atomic_load(&windowData.windowCloseRequested) { 
        //     break 
        // }

        switch debugEvent.dwDebugEventCode {
        case 3: {
            fmt.println("CREATE_PROCESS_DEBUG_EVENT")
            exe: DebuggerModule
            read: uint

            threadId := GetThreadId(debugEvent.u.CreateProcessInfo.hThread)
            append(&threadsIds, threadId)
            // fmt.println(threadId)

            exeNameBufferLength :: 255
            exeNameBuffer: [exeNameBufferLength]u16
            exeBasePointer := uintptr(debugEvent.u.CreateProcessInfo.lpBaseOfImage)
            exe.address = exeBasePointer

            exeBaseAddress = exeBasePointer 
            nameLength := win32.GetFinalPathNameByHandleW(debugEvent.u.CreateProcessInfo.hFile, win32.wstring(raw_data(exeNameBuffer[:])), exeNameBufferLength, 0)
            exeName, err := win32.wstring_to_utf8(win32.wstring(raw_data(exeNameBuffer[:])), int(nameLength))
            exe.name = strings.clone(exeName)

            fmt.printfln("Load Process: %s (%#X)", exeName, exeBasePointer)

            // read dos header
            dosHeader: win32.IMAGE_DOS_HEADER
            win32.ReadProcessMemory(processInfo.hProcess, rawptr(exeBasePointer), &dosHeader, size_of(dosHeader), &read)

            peHeader: win32.IMAGE_NT_HEADERS64
            win32.ReadProcessMemory(processInfo.hProcess, rawptr(exeBasePointer + uintptr(dosHeader.e_lfanew)), &peHeader, size_of(peHeader), &read)
            
            exe.size = i32(peHeader.OptionalHeader.SizeOfImage)
            exeImageSize = peHeader.OptionalHeader.SizeOfImage

            // exportDirectory: win32.IMAGE_EXPORT_DIRECTORY
            // win32.ReadProcessMemory(processInfo.hProcess, rawptr(dllBasePointer + uintptr(peHeader.OptionalHeader.ExportTable.VirtualAddress)), 
            //     &exportDirectory, size_of(exportDirectory), &read)

            // get name of module through IMAGE_EXPORT_DIRECTORY
            // win32.ReadProcessMemory(processInfo.hProcess, rawptr(dllBasePointer + uintptr(exportDirectory.Name)), 
            //     raw_data(dllNameBuffer[:]), dllNameBufferLength, &read)

            // fmt.printfln("Load DLL 2: %s", strings.truncate_to_byte(string(dllNameBuffer[:]), 0))
            
            // private symbols
            debugDirectoriesCount := peHeader.OptionalHeader.Debug.Size / size_of(win32.IMAGE_DEBUG_DIRECTORY)
            
            // pdbFiles := make([dynamic]PdbFile)

            for debugDirectoryIndex in 0..<debugDirectoriesCount {      
                debugDirectory: win32.IMAGE_DEBUG_DIRECTORY
                offset := debugDirectoryIndex * size_of(win32.IMAGE_DEBUG_DIRECTORY)
                debugDirectoryAddress := rawptr(exeBasePointer + uintptr(peHeader.OptionalHeader.Debug.VirtualAddress) + uintptr(offset))
                win32.ReadProcessMemory(processInfo.hProcess, debugDirectoryAddress, 
                    &debugDirectory, size_of(debugDirectory), &read)

                if debugDirectory.Type == win32.IMAGE_DEBUG_TYPE_CODEVIEW {
                    pdbInfo: PdbInfo
                    win32.ReadProcessMemory(processInfo.hProcess, rawptr(exeBasePointer + uintptr(debugDirectory.AddressOfRawData)), 
                        &pdbInfo, size_of(pdbInfo), &read)
        
                    pdbNameBuffer: [260]byte
                    win32.ReadProcessMemory(processInfo.hProcess, rawptr(exeBasePointer + uintptr(debugDirectory.AddressOfRawData) + size_of(pdbInfo)),
                        raw_data(pdbNameBuffer[:]), 260, &read)

                    pdbFilePath := strings.truncate_to_byte(string(pdbNameBuffer[:]), 0)

                    if os.exists(pdbFilePath) {
                        modulePdb, pdbOk := initPdbData(pdbFilePath)
                        if pdbOk {
                            append(&exe.pdbFiles, modulePdb)

                            if !exePdbValid {
                                exePdbData = modulePdb
                                exePdbValid = true
                            }
                        } else {
                            fmt.println("Failed to load pdb:", pdbFilePath)
                        }
                    }
                    // fmt.println("Process pdb file:", strings.truncate_to_byte(string(pdbNameBuffer[:]), 0))
                }
            }

            // Fallback: if the debug directory didn't give us a usable pdb, look for one sitting
            // next to the exe (the normal MSVC layout, e.g. foo.exe -> foo.pdb).
            if !exePdbValid {
                pdbGuess := fmt.tprintf("%s.pdb", strings.trim_suffix(exePath, ".exe"))
                if os.exists(pdbGuess) {
                    modulePdb, pdbOk := initPdbData(pdbGuess)
                    if pdbOk {
                        append(&exe.pdbFiles, modulePdb)
                        exePdbData = modulePdb
                        exePdbValid = true
                    } else {
                        fmt.println("Failed to load pdb:", pdbGuess)
                    }
                }
            }

            if !exePdbValid {
                fmt.println("WARNING: no pdb loaded for the debuggee - breakpoints and source stepping won't work")
            }

            // Apply every breakpoint that was set before the program was launched.
            //>
            appliedCount := 0
            if exePdbValid {
                for bp in windowData.debuggerBrakepoints {
                    brakepointRVA := getRVABySourcePosition(exePdbData.session, bp.filePath, bp.line)
                    fmt.printfln("Breakpoint %s:%i -> RVA %#X", bp.filePath, bp.line, brakepointRVA)
                    if brakepointRVA == 0 { continue } // line isn't in this exe's pdb, skip it

                    applyBreakpoint(processInfo.hProcess, exeBaseAddress + uintptr(brakepointRVA), &appliedBreakpoints)
                    appliedCount += 1
                }
            }
            fmt.printfln("Applied %i of %i breakpoint(s)", appliedCount, len(windowData.debuggerBrakepoints))
            //<

            //test := getRVABySourcePosition(pdbData.session, "C:\\projects\\cpp_test_cmd\\cpp_test_cmd\\main.cpp", 11)
            append(&modules, exe)
        }
        case 2: {
            threadId := GetThreadId(debugEvent.u.CreateThread.hThread)
            append(&threadsIds, threadId)
            fmt.println("CREATE_THREAD_DEBUG_EVENT ", threadId)
        }
        case 1: {
            continueStatus = WIN32_DBG_EXCEPTION_NOT_HANDLED

            firstChance := debugEvent.u.Exception.dwFirstChance
            
            //> was breakpoint hit
            // threadHandler := win32.OpenThread(
            //     win32.THREAD_GET_CONTEXT | win32.THREAD_SET_CONTEXT,
            //     false,
            //     debugEvent.dwThreadId,
            // )
            // defer win32.CloseHandle(threadHandler)
            
            // ctx: win32.CONTEXT
            // ctx.ContextFlags = win32.WOW64_CONTEXT_ALL
            // win32.GetThreadContext(threadHandler, &ctx)
            // if ctx.Dr6 & 0x1 == 1 {
            //     continueStatus = WIN32_DBG_CONTINUE

            //     // instruction: u64 = 0
            //     // read: uint
            //     // test1 := win32.ReadProcessMemory(processInfo.hProcess, rawptr(uintptr(ctx.Rip)), &instruction, size_of(u64), &read)

            //     // mbi: win32.MEMORY_BASIC_INFORMATION
            //     // res := win32.VirtualQueryEx(processInfo.hProcess, rawptr(debugEvent.u.Exception.ExceptionRecord.ExceptionAddress), &mbi, size_of(mbi))
            //     // test2 := win32.GetLastError()

            //     // fmt.println("test ", read)

            //     fmt.println("HIT!!!!!! ", firstChance)

            //     rva := uintptr(ctx.Rip) - exeBaseAddress
            //     fileName, line, _, _ := getSourcePositionByRVA(pdbData.session, u32(rva))

            //     windowData.currentDebuggerInstruction = SingleBrakepoint{
            //         filePath = fileName, line = i32(line)
            //     } 
            // }
            //<

            if expectStepException && debugEvent.u.Exception.ExceptionRecord.ExceptionCode == win32.EXCEPTION_SINGLE_STEP {
                continueStatus = WIN32_DBG_CONTINUE
                expectStepException = false

                // We've now executed the original instruction at a hit breakpoint, so put the
                // 0xCC back to keep the breakpoint active for subsequent hits (e.g. inside loops).
                if rearmAddress != 0 {
                    applyBreakpoint(processInfo.hProcess, rearmAddress, &appliedBreakpoints)
                    rearmAddress = 0
                }
            }

            switch debugEvent.u.Exception.ExceptionRecord.ExceptionCode {
            case win32.EXCEPTION_ACCESS_VIOLATION: fmt.println("EXCEPTION_ACCESS_VIOLATION")     
            case win32.EXCEPTION_ARRAY_BOUNDS_EXCEEDED: fmt.println("EXCEPTION_ARRAY_BOUNDS_EXCEEDED")     
            case win32.EXCEPTION_BREAKPOINT: // software breakpoint
                threadHandler := win32.OpenThread(
                    win32.THREAD_GET_CONTEXT | win32.THREAD_SET_CONTEXT,
                    false,
                    debugEvent.dwThreadId,
                )
                defer win32.CloseHandle(threadHandler)
                
                ctx: win32.CONTEXT
                ctx.ContextFlags = win32.WOW64_CONTEXT_ALL
                win32.GetThreadContext(threadHandler, &ctx)

                fileName: string
                line: u32
                if exePdbValid {
                    rva := uintptr(ctx.Rip) - exeBaseAddress
                    fileName, line, _, _ = getSourcePositionByRVA(exePdbData.session, u32(rva))
                }

                windowData.currentDebuggerInstruction = SingleBrakepoint{
                    filePath = fileName, line = i32(line)
                }

                if uintptr(ctx.Rip) - 1 in tmpBreakpoints {
                    ctx.Rip = ctx.Rip - 1

                    if !win32.SetThreadContext(threadHandler, &ctx) {
                        fmt.println(win32.GetLastError())
                        panic("ERROR SAVING THREAD CTX")
                    }

                    // We planted this temp breakpoint (e.g. step-over's run-to-return), so it's
                    // handled - don't pass the exception on to the debuggee.
                    continueStatus = WIN32_DBG_CONTINUE
                }

                // temporary (step) breakpoints are one-shot: restore the original bytes and drop them
                for breakpointAddress, originalInstruction in tmpBreakpoints {
                    restoreOriginalInstruction(processInfo.hProcess, breakpointAddress, originalInstruction)
                }
                clear(&tmpBreakpoints)

                if uintptr(ctx.Rip) - 1 in appliedBreakpoints {
                    // since RIP regisgter points to the next instruction
                    // in order to correctly resote original instruction in which the first byte was replaced by software breakpoint
                    // we have to move RIP 1 byte back and restore the original instruction
                    ctx.Rip = ctx.Rip - 1

                    if !win32.SetThreadContext(threadHandler, &ctx) {
                        fmt.println(win32.GetLastError())
                        panic("ERROR SAVING THREAD CTX")
                    }

                    // Restore the original instruction so it can run, but keep the breakpoint
                    // registered. It will be re-armed once we single-step over it on continue.
                    restoreOriginalInstruction(processInfo.hProcess, uintptr(ctx.Rip), appliedBreakpoints[uintptr(ctx.Rip)])
                    rearmAddress = uintptr(ctx.Rip)
                    continueStatus = WIN32_DBG_CONTINUE // we handled our own breakpoint
                }
            case win32.EXCEPTION_DATATYPE_MISALIGNMENT: fmt.println("EXCEPTION_DATATYPE_MISALIGNMENT")     
            case win32.EXCEPTION_FLT_DENORMAL_OPERAND: fmt.println("EXCEPTION_FLT_DENORMAL_OPERAND")     
            case win32.EXCEPTION_FLT_DIVIDE_BY_ZERO: fmt.println("EXCEPTION_FLT_DIVIDE_BY_ZERO")     
            case win32.EXCEPTION_FLT_INEXACT_RESULT: fmt.println("EXCEPTION_FLT_INEXACT_RESULT")     
            case win32.EXCEPTION_FLT_INVALID_OPERATION: fmt.println("EXCEPTION_FLT_INVALID_OPERATION")     
            case win32.EXCEPTION_FLT_OVERFLOW: fmt.println("EXCEPTION_FLT_OVERFLOW")     
            case win32.EXCEPTION_FLT_STACK_CHECK: fmt.println("EXCEPTION_FLT_STACK_CHECK")     
            case win32.EXCEPTION_FLT_UNDERFLOW: fmt.println("EXCEPTION_FLT_UNDERFLOW")     
            case win32.EXCEPTION_ILLEGAL_INSTRUCTION: fmt.println("EXCEPTION_ILLEGAL_INSTRUCTION")     
            case win32.EXCEPTION_IN_PAGE_ERROR: fmt.println("EXCEPTION_IN_PAGE_ERROR")     
            case win32.EXCEPTION_INT_DIVIDE_BY_ZERO: fmt.println("EXCEPTION_INT_DIVIDE_BY_ZERO")     
            case win32.EXCEPTION_INT_OVERFLOW: fmt.println("EXCEPTION_INT_OVERFLOW")     
            case win32.EXCEPTION_INVALID_DISPOSITION: fmt.println("EXCEPTION_INVALID_DISPOSITION")     
            case win32.EXCEPTION_NONCONTINUABLE_EXCEPTION: fmt.println("EXCEPTION_NONCONTINUABLE_EXCEPTION")     
            case win32.EXCEPTION_PRIV_INSTRUCTION: fmt.println("EXCEPTION_PRIV_INSTRUCTION")     
            case win32.EXCEPTION_SINGLE_STEP: fmt.println("EXCEPTION_SINGLE_STEP")     
            case win32.EXCEPTION_STACK_OVERFLOW: fmt.println("EXCEPTION_STACK_OVERFLOW")     
            }

            // fmt.println("EXCEPTION_DEBUG_EVENT", debugEvent.u.Exception.ExceptionRecord.ExceptionCode)
        }
        case 5: {
            fmt.println("EXIT_PROCESS_DEBUG_EVENT")
            exitDebugger = true
        }
        case 4: fmt.println("EXIT_THREAD_DEBUG_EVENT")
        case 6: { // LOAD_DLL_DEBUG_EVENT
            read: uint
            imageNamePointer: uintptr
            win32.ReadProcessMemory(processInfo.hProcess, debugEvent.u.LoadDll.lpImageName, &imageNamePointer, size_of(uintptr), &read)

            dllNameBufferLength :: 255
            dllNameBuffer: [dllNameBufferLength]byte
            dllName: string
            win32.ReadProcessMemory(processInfo.hProcess, rawptr(imageNamePointer), raw_data(dllNameBuffer[:]), dllNameBufferLength, &read)

            if read != 0 {           
                isWide := debugEvent.u.LoadDll.fUnicode != 0
                
                if isWide {
                    dllName, _ = win32.wstring_to_utf8(transmute(win32.wstring)raw_data(dllNameBuffer[:]), int(read))
                    // fmt.printfln("Load DLL: %s (%#X)", dllName, debugEvent.u.LoadDll.lpBaseOfDll)
                } else {
                    dllName = string(dllNameBuffer[:])
                    // fmt.printfln("Load DLL: %s (%#X)", string(dllNameBuffer[:]), debugEvent.u.LoadDll.lpBaseOfDll)
                }
            }

            // read dos header
            dllBasePointer := uintptr(debugEvent.u.LoadDll.lpBaseOfDll)
            dosHeader: win32.IMAGE_DOS_HEADER
            win32.ReadProcessMemory(processInfo.hProcess, rawptr(dllBasePointer), &dosHeader, size_of(dosHeader), &read)

            peHeader: win32.IMAGE_NT_HEADERS64
            win32.ReadProcessMemory(processInfo.hProcess, rawptr(dllBasePointer + uintptr(dosHeader.e_lfanew)), &peHeader, size_of(peHeader), &read)
            
            exportDirectory: win32.IMAGE_EXPORT_DIRECTORY
            win32.ReadProcessMemory(processInfo.hProcess, rawptr(dllBasePointer + uintptr(peHeader.OptionalHeader.ExportTable.VirtualAddress)), 
                &exportDirectory, size_of(exportDirectory), &read)

            // get name of module through IMAGE_EXPORT_DIRECTORY
            win32.ReadProcessMemory(processInfo.hProcess, rawptr(dllBasePointer + uintptr(exportDirectory.Name)), 
                raw_data(dllNameBuffer[:]), dllNameBufferLength, &read)

            dllName = strings.clone(strings.truncate_to_byte(string(dllNameBuffer[:]), 0))

            // get list of functions
            functionsAddressesSize := exportDirectory.NumberOfFunctions * size_of(u32)
            functionsAddresses := make([]u32, exportDirectory.NumberOfFunctions)
            defer delete(functionsAddresses)
            win32.ReadProcessMemory(processInfo.hProcess, rawptr(dllBasePointer + uintptr(exportDirectory.AddressOfFunctions)),
                raw_data(functionsAddresses[:]), uint(functionsAddressesSize), &read)
            
            functionsNamesSize := exportDirectory.NumberOfNames * size_of(u32)
            functionsNames := make([]u32, exportDirectory.NumberOfNames)
            defer delete(functionsNames)
            win32.ReadProcessMemory(processInfo.hProcess, rawptr(dllBasePointer + uintptr(exportDirectory.AddressOfNames)),
                raw_data(functionsNames[:]), uint(functionsNamesSize), &read)
            
            functionsOrdinalsSize := exportDirectory.NumberOfNames * size_of(u16)
            functionsOrdinals := make([]u16, exportDirectory.NumberOfNames)
            defer delete(functionsOrdinals)
            win32.ReadProcessMemory(processInfo.hProcess, rawptr(dllBasePointer + uintptr(exportDirectory.AddressOfNameOrdinals)),
                raw_data(functionsOrdinals[:]), uint(functionsOrdinalsSize), &read)

            exportFunctions := make([dynamic]ExportFunction)
            for functionAddress, index in functionsAddresses {
                ordinalIndex := exportDirectory.Base + u32(index)
                // test := functionsAddresses[i * size_of(u32)]

                nameIndex: u32
                for ordinal, oIndex in functionsOrdinals {
                    if ordinal == u16(ordinalIndex) {
                        nameIndex = u32(oIndex)
                        break
                    }
                }

                if nameIndex != 0 {
                    nameAddress := dllBasePointer + uintptr(functionsNames[nameIndex])

                    functionNameBufferLength :: 255
                    functionNameBuffer: [functionNameBufferLength]byte
                    win32.ReadProcessMemory(processInfo.hProcess, rawptr(nameAddress), raw_data(functionNameBuffer[:]), functionNameBufferLength, &read)

                    functionName := strings.clone(strings.truncate_to_byte(string(functionNameBuffer[:]), 0))
                    append(&exportFunctions, ExportFunction{
                        name = functionName,
                        address = dllBasePointer + uintptr(functionAddress),
                    })
                    //fmt.println(functionName)
                }

                //fmt.println(functionAddress, ordinalIndex)
                test32 := functionAddress
            }
            
            // // private symbols
            // debugDirectory: win32.IMAGE_DEBUG_DIRECTORY
            // win32.ReadProcessMemory(processInfo.hProcess, rawptr(dllBasePointer + uintptr(peHeader.OptionalHeader.Debug.VirtualAddress)), 
            //     &debugDirectory, size_of(debugDirectory), &read)

            // debugDirectoriesCount := peHeader.OptionalHeader.Debug.Size / size_of(debugDirectory)
            
            // if debugDirectory.Type == win32.IMAGE_DEBUG_TYPE_CODEVIEW {
            //     pdbInfo: PdbInfo
            //     win32.ReadProcessMemory(processInfo.hProcess, rawptr(dllBasePointer + uintptr(debugDirectory.AddressOfRawData)), 
            //         &pdbInfo, size_of(pdbInfo), &read)
      
            //     pdbNameBuffer: [260]byte
            //     win32.ReadProcessMemory(processInfo.hProcess, rawptr(dllBasePointer + uintptr(debugDirectory.AddressOfRawData) + size_of(pdbInfo)), 
            //         raw_data(pdbNameBuffer[:]), 260, &read)
      
            //     test32 := string(pdbNameBuffer[:])
            //     test := 2
            // }

            fmt.printfln("Load DLL: %s (%#X)", dllName, dllBasePointer)
            append(&modules, DebuggerModule{
                name = dllName,
                address = dllBasePointer,
                size = i32(peHeader.OptionalHeader.SizeOfImage),
                exportFunctions = exportFunctions,
            })
        }
        case 8: {
            fmt.println("OUTPUT_DEBUG_STRING_EVENT")

            length := uint(debugEvent.u.DebugString.nDebugStringLength) - 1
            isWide := debugEvent.u.DebugString.fUnicode != 0
            // strings.
            // test := cstring(debugEvent.u.DebugString.lpDebugStringData)

            test := make([]byte, length)
            defer delete(test)
            read: uint
            win32.ReadProcessMemory(processInfo.hProcess, debugEvent.u.DebugString.lpDebugStringData, raw_data(test[:]), length, &read)
            
            if isWide {
                fmt.println(win32.wstring_to_utf8(transmute(win32.wstring)raw_data(test[:]), int(length)))
            } else {
                fmt.println(string(test))
            }
        }
        case 9: fmt.println("RIP_EVENT")
        case 7: fmt.println("UNLOAD_DLL_DEBUG_EVENT")
        }

        if exitDebugger { break }

        stopDebugger := false

        // if sync.atomic_load(&windowData.debuggerCommand) == .STOP {
        //     sync.atomic_store(&windowData.debuggerCommand, .NONE)

        //     for {

        //     }
        // }

        // switch sync.atomic_load(&windowData.debuggerCommand) {
        // case .NONE:
        // case .CONTINUE:
        // case .STOP:
        // }

        //> set break testing breakpoint for all threads
        // for threadId in threadsIds {
        //setBreakpointForThread(debugEvent.dwThreadId, exeBaseAddress + uintptr(testFunctionRVA))
        // }
        //<

        threadHandler := win32.OpenThread(
            win32.THREAD_GET_CONTEXT | win32.THREAD_SET_CONTEXT,
            false,
            debugEvent.dwThreadId,
        )
        defer win32.CloseHandle(threadHandler)
        
        ctx: win32.CONTEXT
        ctx.ContextFlags = win32.WOW64_CONTEXT_ALL
        win32.GetThreadContext(threadHandler, &ctx)

        // addressToCheck := exeBaseAddress + uintptr(testFunctionRVA)
        addressToCheck := uintptr(ctx.Rip)

        // The source-level stepping engine. While a step is in progress we drive it ourselves,
        // independent of the breakpoint/module-match path below, so we stay in control even
        // through library code that has no source info.
        if stepMode == .Out {
            // Step-out runs (at native speed) to the current function's return address, where we
            // planted a one-shot breakpoint. We arrive here when it fired: the EXCEPTION_BREAKPOINT
            // handler put RIP back onto stepOutTarget. RSP > stepStartSp confirms our own frame was
            // actually popped, distinguishing the real return from a *nested* return to the same
            // address when the function is recursive.
            if addressToCheck == stepOutTarget && ctx.Rsp > stepStartSp {
                inExe := exePdbValid && addressToCheck >= exeBaseAddress && addressToCheck < exeBaseAddress + uintptr(exeImageSize)
                file: string
                line: u32
                if inExe {
                    file, line, _, _ = getSourcePositionByRVA(exePdbData.session, u32(addressToCheck - exeBaseAddress))
                }

                windowData.currentDebuggerInstruction = SingleBrakepoint{ filePath = file, line = i32(line) }
                if len(stepStartFile) > 0 { delete(stepStartFile) }
                stepStartFile = ""
                stepOutTarget = 0
                stepMode = .None
                stopDebugger = true
            } else {
                // Either we're starting the step-out, or a nested recursive return hit our breakpoint
                // before our own frame returned. (Re)arm the return-address breakpoint and keep running.
                armStepOut(processInfo.hProcess, threadHandler, &ctx, stepOutTarget, &tmpBreakpoints, &expectStepException, &continueStatus)
                stopDebugger = false
            }
        } else if stepMode == .Instruction {
            // We single-stepped exactly one machine instruction; stop here regardless of source line.
            inExe := exePdbValid && addressToCheck >= exeBaseAddress && addressToCheck < exeBaseAddress + uintptr(exeImageSize)
            file: string
            line: u32
            if inExe {
                file, line, _, _ = getSourcePositionByRVA(exePdbData.session, u32(addressToCheck - exeBaseAddress))
            }
            windowData.currentDebuggerInstruction = SingleBrakepoint{ filePath = file, line = i32(line) }
            stepMode = .None
            stopDebugger = true
        } else if stepMode != .None {
            // Only the exe carries source info, so only ask DIA when RIP is inside it (and avoid a
            // bogus RVA lookup while stepping through library code).
            inExe := exePdbValid && addressToCheck >= exeBaseAddress && addressToCheck < exeBaseAddress + uintptr(exeImageSize)

            // `file` is temp-allocated by DIA (wstring_to_utf8) and must not be freed here.
            file: string
            line: u32
            if inExe {
                file, line, _, _ = getSourcePositionByRVA(exePdbData.session, u32(uintptr(ctx.Rip) - exeBaseAddress))
            }

            atNewSourceLine := inExe && file != "" && (file != stepStartFile || u32(line) != stepStartLine)

            // step-over also requires we're not inside a deeper call frame (a smaller RSP)
            shouldStop := atNewSourceLine && (stepMode == .Into || ctx.Rsp >= stepStartSp)

            if shouldStop {
                windowData.currentDebuggerInstruction = SingleBrakepoint{ filePath = file, line = i32(line) }
                if len(stepStartFile) > 0 { delete(stepStartFile) }
                stepStartFile = ""
                stepMode = .None
                stopDebugger = true
            } else {
                armStepMove(processInfo.hProcess, threadHandler, &ctx, stepMode, &tmpBreakpoints, &expectStepException, &continueStatus)
                stopDebugger = false
            }
        } else if suppressPauseOnce {
            suppressPauseOnce = false
        } else {
            for module in modules {
                startAddress := module.address
                endAddress := module.address + uintptr(module.size)

                if addressToCheck >= startAddress && addressToCheck < endAddress {
                    // check is the function in exports table
                    functionName: string
                    minFunctionStartOffset := uintptr((1 << 64) - 1)
                    for exportFunction in module.exportFunctions {
                        if addressToCheck >= exportFunction.address {
                            startOffset := addressToCheck - exportFunction.address

                            if minFunctionStartOffset > startOffset {
                                minFunctionStartOffset = startOffset
                                functionName = exportFunction.name
                            }
                        }
                    }

                    // check is the function is in a pdb file (use that module's own pdb)
                    for pdbFile in module.pdbFiles {
                        rva := uintptr(ctx.Rip) - module.address
                        functionName, _ = getFunctionNameByRVA(pdbFile.session, u32(rva))
                        fileName, line, column, _ := getSourcePositionByRVA(pdbFile.session, u32(rva))

                        stopDebugger = true
                        fmt.printfln("source %s %i %i", fileName, line, column)
                    }
                    fmt.printfln("match %s %s %i", module.name, functionName, addressToCheck)
                }
            }
        }

        if stopDebugger && exePdbValid {
            collectDebuggerLocals(processInfo.hProcess, exePdbData, exeBaseAddress, ctx)
        }
        if stopDebugger {
            collectDebuggerCallStack(processInfo.hProcess, threadHandler, ctx, modules[:])
            sync.atomic_store(&windowData.debuggerStackPointer, u64(ctx.Rsp)) // default address for the memory viewer
            windowData.debuggerRegisters = registersFromContext(ctx) // published before debuggerPaused below
        }
        // ctx.Rip

        // Tell any front-end (e.g. the cmd debugger) that we're parked at a stop waiting for a
        // command. The GUI ignores this; the cmd debugger waits on it to know when to print/prompt.
        if stopDebugger {
            sync.atomic_store(&windowData.debuggerPaused, true)
        }

        //> testing
        for stopDebugger {
            if !isProcessRunning(windowData.debuggerProcessHandler) { return }

            if sync.atomic_load(&windowData.debuggerCommand) == .CONTINUE {
                sync.atomic_store(&windowData.debuggerCommand, .NONE)

                // If we're sitting on a breakpoint, step over the restored instruction first so the
                // breakpoint can be re-armed (handled on the resulting single-step event) before running.
                if rearmAddress != 0 {
                    expectStepException = true
                    suppressPauseOnce = true
                    ctx.EFlags |= 0x100 // trap flag -> single step
                    assert(win32.SetThreadContext(threadHandler, &ctx) == true)
                    continueStatus = WIN32_DBG_CONTINUE
                }
                break
            }

            stepCommand := sync.atomic_load(&windowData.debuggerCommand)
            if stepCommand == .STEP_OVER || stepCommand == .STEP_INTO {
                sync.atomic_store(&windowData.debuggerCommand, .NONE)

                // Record where the step began; the engine (above) compares against this on each
                // single-step / run-over event to decide when we've reached a new source line.
                // `file` is temp-allocated by DIA (don't free it); we keep a heap clone instead.
                rva := uintptr(ctx.Rip) - exeBaseAddress
                file, line, _, _ := getSourcePositionByRVA(exePdbData.session, u32(rva))

                if len(stepStartFile) > 0 { delete(stepStartFile) }
                stepStartFile = strings.clone(file) if len(file) > 0 else ""
                stepStartLine = line
                stepStartSp = ctx.Rsp
                stepMode = stepCommand == .STEP_OVER ? .Over : .Into

                armStepMove(processInfo.hProcess, threadHandler, &ctx, stepMode, &tmpBreakpoints, &expectStepException, &continueStatus)
                break
            }

            if stepCommand == .STEP_OUT {
                sync.atomic_store(&windowData.debuggerCommand, .NONE)

                // Find the caller's resume point (one unwind step) and run there at native speed via a
                // one-shot breakpoint. The .Out branch of the stepping engine stops us when it fires.
                target, targetOk := returnAddressOf(processInfo.hProcess, threadHandler, ctx, modules[:])
                if targetOk {
                    if len(stepStartFile) > 0 { delete(stepStartFile) }
                    stepStartFile = "" // step-out stops on RSP, not a source-line compare
                    stepStartSp = ctx.Rsp
                    stepOutTarget = target
                    stepMode = .Out
                    armStepOut(processInfo.hProcess, threadHandler, &ctx, stepOutTarget, &tmpBreakpoints, &expectStepException, &continueStatus)
                } else {
                    // No caller to return to (outermost frame / no unwind info): fall back to continue.
                    if rearmAddress != 0 {
                        expectStepException = true
                        suppressPauseOnce = true
                        ctx.EFlags |= 0x100 // trap flag -> single step
                        assert(win32.SetThreadContext(threadHandler, &ctx) == true)
                        continueStatus = WIN32_DBG_CONTINUE
                    }
                }
                break
            }

            if stepCommand == .STEP_INSTRUCTION {
                sync.atomic_store(&windowData.debuggerCommand, .NONE)

                // Single-step exactly one machine instruction. The .Instruction engine branch stops us
                // on the resulting step event; the same event re-arms a hit breakpoint (rearmAddress).
                stepMode = .Instruction
                expectStepException = true
                ctx.EFlags |= 0x100 // trap flag -> single step
                assert(win32.SetThreadContext(threadHandler, &ctx) == true)
                continueStatus = WIN32_DBG_CONTINUE
                break
            }

            if stepCommand == .RUN_TO {
                sync.atomic_store(&windowData.debuggerCommand, .NONE)

                // Plant a one-shot breakpoint at the target line and run to it (or to an earlier user
                // breakpoint). When it fires, RIP is in the exe so the module-match path below stops us.
                if exePdbValid {
                    rva := getRVABySourcePosition(exePdbData.session, windowData.debuggerRunToFile, windowData.debuggerRunToLine)
                    if rva != 0 {
                        target := exeBaseAddress + uintptr(rva)
                        if target not_in tmpBreakpoints && target not_in appliedBreakpoints {
                            applyBreakpoint(processInfo.hProcess, target, &tmpBreakpoints)
                        }
                    }
                }
                // Leave the current breakpoint by single-stepping off it first (re-arm), like CONTINUE.
                if rearmAddress != 0 {
                    expectStepException = true
                    suppressPauseOnce = true
                    ctx.EFlags |= 0x100 // trap flag -> single step
                    assert(win32.SetThreadContext(threadHandler, &ctx) == true)
                }
                continueStatus = WIN32_DBG_CONTINUE
                break
            }

            win32.Sleep(1) // we're paused waiting for a user command; don't busy-spin a core
        }
        sync.atomic_store(&windowData.debuggerPaused, false) // resuming
        //<

        //> render registers
        //fmt.println("rax: %i", ctx.Rax)
        //<

        ContinueDebugEvent(debugEvent.dwProcessId, debugEvent.dwThreadId, continueStatus)
    }

    // ok = DebugActiveProcess(processInfo.dwProcessId)

	// if !ok {
	// 	panic("FAILED")
	// }

    // win32.CloseHandle(processInfo.hProcess)
}

isProcessRunning :: proc(handle: win32.HANDLE) -> bool {
    exitCode: win32.DWORD
    win32.GetExitCodeProcess(handle, &exitCode)

    return exitCode == 259 // STILL_ACTIVE
}

// If the instruction at `address` is a CALL, returns its byte length and true. Used by step-over
// to run the whole call at native speed (by breakpointing the return address) instead of
// single-stepping through it. Detection uses Zydis's rendered mnemonic, covering direct and
// indirect (e.g. imported-function) calls alike.
callInstructionAt :: proc(process: win32.HANDLE, address: uintptr) -> (length: u32, isCall: bool) {
    buf: [16]u8 // x86-64 instructions are at most 15 bytes
    read: uint
    if !win32.ReadProcessMemory(process, win32.LPCVOID(address), raw_data(buf[:]), uint(len(buf)), &read) || read == 0 {
        return 0, false
    }

    inst: ZydisDisassembledInstruction
    if ZydisDisassembleIntel(0, rawptr(address), raw_data(buf[:]), u64(read), &inst) & 0x80000000 != 0 {
        return 0, false
    }

    text := string(cstring(raw_data(inst.text[:])))
    return u32(inst.info.length), strings.has_prefix(text, "call")
}

// Arms the next move of an in-progress step: for step-over, if we're sitting on a CALL, set a
// one-shot breakpoint at the return address so the call runs at full speed; otherwise single-step
// one instruction with the trap flag. Called both when a step starts and after each step event.
armStepMove :: proc(process: win32.HANDLE, threadHandler: win32.HANDLE, ctx: ^win32.CONTEXT,
    mode: StepMode, tmpBreakpoints: ^map[uintptr]u8, expectStepException: ^bool, continueStatus: ^u32) {

    if mode == .Over {
        if insLen, isCall := callInstructionAt(process, uintptr(ctx.Rip)); isCall {
            applyBreakpoint(process, uintptr(ctx.Rip) + uintptr(insLen), tmpBreakpoints)
            continueStatus^ = WIN32_DBG_CONTINUE
            return
        }
    }

    expectStepException^ = true
    ctx.EFlags |= 0x100 // trap flag -> single step
    assert(win32.SetThreadContext(threadHandler, ctx) == true)
    continueStatus^ = WIN32_DBG_CONTINUE
}

// Drives an in-progress step-out: we run at native speed to the current function's return address by
// planting a one-shot breakpoint there. If a *nested* (recursive) return has left us sitting on that
// address, single-step off it first so re-planting the breakpoint in place won't immediately retrigger
// it. Called when the step-out starts and again after each return-address hit we decide to skip.
armStepOut :: proc(process: win32.HANDLE, threadHandler: win32.HANDLE, ctx: ^win32.CONTEXT,
    target: uintptr, tmpBreakpoints: ^map[uintptr]u8, expectStepException: ^bool, continueStatus: ^u32) {

    if uintptr(ctx.Rip) == target {
        // Sitting on the target (a skipped nested return): step one instruction off it; the engine
        // re-plants the breakpoint on the resulting step event, when RIP no longer equals target.
        expectStepException^ = true
        ctx.EFlags |= 0x100 // trap flag -> single step
        assert(win32.SetThreadContext(threadHandler, ctx) == true)
    } else if target not_in tmpBreakpoints^ {
        applyBreakpoint(process, target, tmpBreakpoints)
    }
    continueStatus^ = WIN32_DBG_CONTINUE
}

// Maps a CodeView (cvconst.h) AMD64 register id to the matching value in the thread context.
registerValueById :: proc(ctx: win32.CONTEXT, registerId: win32.DWORD) -> u64 {
    // NOTE: cvconst.h CV_AMD64_* order is RAX,RBX,RCX,RDX,RSI,RDI,RBP,RSP — NOT the x86
    // ModRM order. Frame-relative locals are usually RBP(334)/RSP(335)-based, so getting
    // these wrong makes them resolve to garbage addresses.
    switch registerId {
    case 328: return u64(ctx.Rax)
    case 329: return u64(ctx.Rbx)
    case 330: return u64(ctx.Rcx)
    case 331: return u64(ctx.Rdx)
    case 332: return u64(ctx.Rsi)
    case 333: return u64(ctx.Rdi)
    case 334: return u64(ctx.Rbp)
    case 335: return u64(ctx.Rsp)
    case 336: return u64(ctx.R8)
    case 337: return u64(ctx.R9)
    case 338: return u64(ctx.R10)
    case 339: return u64(ctx.R11)
    case 340: return u64(ctx.R12)
    case 341: return u64(ctx.R13)
    case 342: return u64(ctx.R14)
    case 343: return u64(ctx.R15)
    }
    return 0
}

freeDebuggerLocalsContents :: proc(locals: ^[dynamic]DebuggerVariable) {
    for local in locals {
        delete(local.name)
        delete(local.value)
    }
}

clearDebuggerLocals :: proc() {
    sync.mutex_lock(&windowData.debuggerLocalsMutex)
    defer sync.mutex_unlock(&windowData.debuggerLocalsMutex)

    freeDebuggerLocalsContents(&windowData.debuggerLocals)
    clear(&windowData.debuggerLocals)
}

// Snapshots the locals/parameters of the function we're currently stopped in by reading their
// frame-relative (LocIsRegRel) values from the debuggee's memory. This covers typical /Zi /Od
// debug builds; variables scoped to nested blocks aren't enumerated yet.
collectDebuggerLocals :: proc(process: win32.HANDLE, pdb: PdbData, baseAddress: uintptr, ctx: win32.CONTEXT) {
    LocIsRegRel :: 3 // cvconst.h LocationType

    newLocals := make([dynamic]DebuggerVariable)

    if pdb.session != nil {
        rva := u32(uintptr(ctx.Rip) - baseAddress)

        funcSym: ^IDiaSymbol
        if pdb.session->findSymbolByRVA(rva, .SymTagFunction, &funcSym) == 0 && funcSym != nil {
            defer funcSym->Release()

            // findChildren (non-Ex) returns E_INVALIDARG here, same as on the global scope, leaving the
            // enum nil -> "no locals". findChildrenEx is the one that actually enumerates the children.
            enumSymbols: ^IDiaEnumSymbols
            if funcSym->findChildrenEx(.SymTagData, nil, 0, &enumSymbols) == 0 && enumSymbols != nil {
                defer enumSymbols->Release()

                sym: ^IDiaSymbol
                celt: win32.ULONG
                for enumSymbols->Next(1, &sym, &celt) == 0 && celt == 1 {
                    defer sym->Release()

                    locationType: win32.DWORD
                    sym->get_locationType(&locationType)
                    if locationType != LocIsRegRel { continue }

                    registerId: win32.DWORD
                    sym->get_registerId(&registerId)

                    offset: win32.LONG
                    sym->get_offset(&offset)

                    nameBstr: win32.BSTR
                    if sym->get_name(&nameBstr) != 0 { continue }
                    // wstring_to_utf8 allocates via context.temp_allocator by default, so clone to the
                    // heap. freeDebuggerLocalsContents delete()s this on the next collection; deleting a
                    // temp pointer through the heap allocator is a bad free -> crash (see [[dia-helpers]]).
                    nameTemp, _ := win32.wstring_to_utf8(win32.wstring(nameBstr), -1)
                    name := strings.clone(nameTemp)

                    // The variable's byte size comes from its type; without it we'd read 8 bytes and
                    // show whatever adjacent stack bytes happen to follow a smaller variable.
                    varSize: u64 = 0
                    typeSym: ^IDiaSymbol
                    if sym->get_type(&typeSym) == 0 && typeSym != nil {
                        length: win32.ULONGLONG
                        if typeSym->get_length(&length) == 0 { varSize = u64(length) }
                        typeSym->Release()
                    }

                    address := uintptr(i64(registerValueById(ctx, registerId)) + i64(offset))

                    append(&newLocals, DebuggerVariable{
                        name = name,
                        value = readDebuggerValue(process, address, varSize),
                        address = address,
                        size = u32(varSize),
                    })
                }
            }
        }
    }

    sync.mutex_lock(&windowData.debuggerLocalsMutex)
    freeDebuggerLocalsContents(&windowData.debuggerLocals)
    delete(windowData.debuggerLocals)
    windowData.debuggerLocals = newLocals
    sync.mutex_unlock(&windowData.debuggerLocalsMutex)
}

// Reads `byteSize` bytes (1..8) at `address` in the debuggee and formats them as "<dec> (0x<hex>)".
// Using the real size avoids showing adjacent stack bytes, and lets small signed ints sign-extend.
// Returns an owned (heap) string, freed later by freeDebuggerLocalsContents.
readDebuggerValue :: proc(process: win32.HANDLE, address: uintptr, byteSize: u64) -> string {
    size := byteSize
    if size == 0 || size > 8 { size = 8 }

    rawValue: u64
    read: uint
    if !win32.ReadProcessMemory(process, win32.LPCVOID(address), &rawValue, uint(size), &read) || read == 0 {
        return strings.clone("<unreadable>")
    }

    effective := size
    if u64(read) < effective { effective = u64(read) }

    masked := rawValue
    signed := i64(rawValue)
    if effective < 8 {
        bits := uint(effective) * 8
        masked = rawValue & ((u64(1) << bits) - 1)
        signed = i64(masked)
        if masked & (u64(1) << (bits - 1)) != 0 { // sign bit set -> sign-extend
            signed = i64(masked | ~((u64(1) << bits) - 1))
        }
    }

    return fmt.aprintf("%d (0x%X)", signed, masked)
}

// Reads up to len(buffer) bytes from the debuggee at `address`. Returns how many were read and whether
// any were (false if there's no live process or the region is unreadable). Used by the memory viewer,
// the `x` command, and tests.
readDebuggerMemory :: proc(address: uintptr, buffer: []u8) -> (uint, bool) {
    process := windowData.debuggerProcessHandler
    if process == nil || len(buffer) == 0 { return 0, false }

    read: uint
    if !win32.ReadProcessMemory(process, win32.LPCVOID(address), raw_data(buffer), uint(len(buffer)), &read) {
        return 0, false
    }
    return read, read > 0
}

// Writes `data` into the debuggee at `address` (and flushes the instruction cache, in case it's code).
// Returns true only if all bytes were written.
writeDebuggerMemory :: proc(address: uintptr, data: []u8) -> bool {
    process := windowData.debuggerProcessHandler
    if process == nil || len(data) == 0 { return false }

    written: uint
    if !win32.WriteProcessMemory(process, win32.LPVOID(address), raw_data(data), uint(len(data)), &written) {
        return false
    }
    FlushInstructionCache(process, win32.LPCVOID(address), uint(len(data)))
    return written == uint(len(data))
}

// Writes the low `size` (1..8) bytes of `value` to `address` - i.e. sets an integer variable.
writeDebuggerInt :: proc(address: uintptr, value: i64, size: int) -> bool {
    n := size
    if n <= 0 || n > 8 { n = 8 }
    v := value
    return writeDebuggerMemory(address, (cast([^]u8)&v)[:n])
}

// Snapshots the x64 general-purpose registers from a thread context.
registersFromContext :: proc(ctx: win32.CONTEXT) -> DebuggerRegisters {
    return {
        rax = u64(ctx.Rax), rbx = u64(ctx.Rbx), rcx = u64(ctx.Rcx), rdx = u64(ctx.Rdx),
        rsi = u64(ctx.Rsi), rdi = u64(ctx.Rdi), rbp = u64(ctx.Rbp), rsp = u64(ctx.Rsp),
        r8 = u64(ctx.R8), r9 = u64(ctx.R9), r10 = u64(ctx.R10), r11 = u64(ctx.R11),
        r12 = u64(ctx.R12), r13 = u64(ctx.R13), r14 = u64(ctx.R14), r15 = u64(ctx.R15),
        rip = u64(ctx.Rip), rflags = u64(ctx.EFlags),
    }
}

test :: proc() {
    MAX_PROCESSES_COUNT :: 1024
    //DebugActiveProcess(0)

    processesIds: [MAX_PROCESSES_COUNT]win32.DWORD
    processesCount: win32.DWORD

    if !EnumProcesses(raw_data(processesIds[:]), 4 * MAX_PROCESSES_COUNT, &processesCount) {
        panic("YEAH>???!!!")
    }

    processesCount /= 4 // because of windows

    for processId in processesIds {
        test: [255]win32.WCHAR
        processHandle := win32.OpenProcess(win32.PROCESS_QUERY_INFORMATION | win32.PROCESS_VM_READ, false, processId)
        defer win32.CloseHandle(processHandle)

        if processHandle == nil { continue }
        
        hMod: win32.HMODULE // to get the first one
        modulesCount: win32.DWORD
        if !EnumProcessModules(processHandle, &hMod, size_of(hMod), &modulesCount) {
            // panic("YEAH>???!!!")
            continue
        }
        modulesCount /= 4 // because of windows

        GetModuleBaseNameW(processHandle, hMod, raw_data(test[:]), 255)

        fmt.println(win32.wstring_to_utf8(win32.wstring(raw_data(test[:])), 255))
    }
    
    // win32.Deb
}