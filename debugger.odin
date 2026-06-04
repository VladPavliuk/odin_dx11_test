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
    READ,
    STOP,
    STEP,
}

SingleBrakepoint :: struct {
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
    for !thread.is_done(windowData.debuggerThread) { }

    thread.join(windowData.debuggerThread)
    thread.destroy(windowData.debuggerThread)
    
    windowData.debuggerThread = nil
    win32.CloseHandle(windowData.debuggerProcessHandler)
}

runDebugThread :: proc(exePath: string) {
    windowData.debuggerThread = thread.create_and_start_with_poly_data(exePath, runDebugProcess_Function, default_context)
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

    Module :: struct {
        name: string,
        address: uintptr,
        size: i32,
        pdbFiles: [dynamic]PdbData,
        exportFunctions: [dynamic]ExportFunction,
    }
    // PdbFile :: struct {
    //     filePath: string,
    //     content: []u8,
    // }
    ExportFunction :: struct {
        name: string,
        address: uintptr,
    }
    modules := make([dynamic]Module)
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

    pdbData := initPdbData("C:\\projects\\cpp_test_cmd\\x64\\Debug\\cpp_test_cmd.pdb")
    //functionsWithRVA := getFunctionsWithRVA(pdbData)

    //testFunctionRVA := functionsWithRVA["main"]
    // testFunctionRVA := testDia()
    exeBaseAddress: uintptr = 0
    steppingToNextLine := false
    originalStepFilePath: string
    originalStepLine: u32 = 0

    for WaitForDebugEvent(&debugEvent, WIN32_INFINITE) {
        continueStatus: u32 = WIN32_DBG_EXCEPTION_NOT_HANDLED // why should it be always that and not WIN32_DBG_CONTINUE???
        exitDebugger := false

        // if sync.atomic_load(&windowData.windowCloseRequested) { 
        //     break 
        // }

        switch debugEvent.dwDebugEventCode {
        case 3: {
            fmt.println("CREATE_PROCESS_DEBUG_EVENT")
            exe: Module
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
                    pdbFileContent, err := os.read_entire_file_from_filename_or_err(pdbFilePath)

                    pdbData := initPdbData(pdbFilePath)

                    append(&exe.pdbFiles, pdbData)
                    // fmt.println("Process pdb file:", strings.truncate_to_byte(string(pdbNameBuffer[:]), 0))
                }
            } 

            // TODO: for now just set breakpoints that where defined before program run
            //>
            if len(windowData.debuggerBrakepoints) > 0 {           
                testBreakpoint := windowData.debuggerBrakepoints[0]
                brakepointRVA := getRVABySourcePosition(pdbData.session, testBreakpoint.filePath, testBreakpoint.line)

                assert(brakepointRVA != 0)
                applyBreakpoint(processInfo.hProcess, exeBaseAddress + uintptr(brakepointRVA), &appliedBreakpoints)
                // setBreakpointForThread(debugEvent.dwThreadId, exeBaseAddress + uintptr(brakepointRVA))
                // brakepointRVA
            }
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
                
                rva := uintptr(ctx.Rip) - exeBaseAddress
                fileName, line, _, _ := getSourcePositionByRVA(pdbData.session, u32(rva))

                fmt.println("HIT!!!!!! ", fileName, line)

                windowData.currentDebuggerInstruction = SingleBrakepoint{
                    filePath = fileName, line = i32(line)
                }

                if uintptr(ctx.Rip) - 1 in tmpBreakpoints {
                    ctx.Rip = ctx.Rip - 1

                    if !win32.SetThreadContext(threadHandler, &ctx) {
                        fmt.println(win32.GetLastError())
                        panic("ERROR SAVING THREAD CTX")
                    }
                }

                for breakpointAddress, originalInstruction in tmpBreakpoints {
                    removeBreakpoint(processInfo.hProcess, breakpointAddress, &tmpBreakpoints)   
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

                    removeBreakpoint(processInfo.hProcess, uintptr(ctx.Rip), &appliedBreakpoints)   
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
            append(&modules, Module{
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

                // check is the function is pdb file
                for pdbFile in module.pdbFiles {
                    rva := uintptr(ctx.Rip) - module.address
                    functionName, _ = getFunctionNameByRVA(pdbData.session, u32(rva))
                    fileName, line, column, _ := getSourcePositionByRVA(pdbData.session, u32(rva))
        
                    //test := getRVABySourcePosition(pdbData.session, "C:\\projects\\cpp_test_cmd\\cpp_test_cmd\\main.cpp", 11)
                    // test := getRVABySourcePosition(pdbData.session, "C:\\projects\\DirectXTemplate\\DirectXTemplate\\gpuShaders.cpp", 11)

                    stopDebugger = true
                    fmt.printfln("source %s %i %i", fileName, line, column)
                }
                fmt.printfln("match %s %s %i", module.name, functionName, addressToCheck)
            }
        }
        // ctx.Rip

        //> testing
        for stopDebugger {
            if !isProcessRunning(windowData.debuggerProcessHandler) { return }

            if steppingToNextLine {
                rva := uintptr(ctx.Rip) - exeBaseAddress
                fileName, line, column, length := getSourcePositionByRVA(pdbData.session, u32(rva))

                // TODO: ADD NORMAL FILE FILTERING!!!
                if fileName == "" || !strings.starts_with(fileName, "C:\\projects\\cpp_test_cmd") || (originalStepFilePath == fileName && originalStepLine == line) {
                    expectStepException = true
                    continueStatus = WIN32_DBG_CONTINUE
                    ctx.EFlags |= 0x100
                    assert(win32.SetThreadContext(threadHandler, &ctx) == true)

                    // if there's a function call don't use trap flag, but instead set breakpoint on the next instruction
                    
                } else {
                    applyBreakpoint(processInfo.hProcess, uintptr(ctx.Rip), &tmpBreakpoints)

                    steppingToNextLine = false
                }
                break
            }

            if sync.atomic_load(&windowData.debuggerCommand) == .CONTINUE {
                sync.atomic_store(&windowData.debuggerCommand, .NONE)
                break
            }

            if sync.atomic_load(&windowData.debuggerCommand) == .STEP {
                sync.atomic_store(&windowData.debuggerCommand, .NONE)

                //> advancing to the next line line
                rva := uintptr(ctx.Rip) - exeBaseAddress
                fileName, line, column, length := getSourcePositionByRVA(pdbData.session, u32(rva))

                rva += uintptr(length)

                applyBreakpoint(processInfo.hProcess, exeBaseAddress + rva, &tmpBreakpoints)
                //<

                instructions: [1024]u8
                res := win32.ReadProcessMemory(processInfo.hProcess, rawptr(uintptr(ctx.Rip)), raw_data(instructions[:]), uint(length), nil)
                assert(res == true, "Could not read the debugged process memory")

                zydisInstruction: ZydisDisassembledInstruction

                offset: u64 = 0
                runtimeAddress := uintptr(ctx.Rip)

                for ZydisDisassembleIntel(0, rawptr(runtimeAddress), rawptr(uintptr(raw_data(instructions[:])) + uintptr(offset)), u64(length) - offset, &zydisInstruction) & 0x80000000 == 0 {
                    offset += u64(zydisInstruction.info.length)
                    runtimeAddress += uintptr(zydisInstruction.info.length)

                    switch zydisInstruction.info.opcode {
                    case
                        0xE8, // call
                        0x74, // je
                        0x7E, // jle
                        0xEB, // jmp
                        0x7D: // jnl
                        address := i128(runtimeAddress) + i128(zydisInstruction.operands[0].value.imm.value.s)
                        applyBreakpoint(processInfo.hProcess, uintptr(address), &tmpBreakpoints)
                        // append(&potentialAddresses, uintptr(address))

                        //fmt.printfln("YEAH(%#X)", address)
                    }
                   
                    // fmt.printfln("opcode(%#X) %s", zydisInstruction.info.opcode, cstring(raw_data(zydisInstruction.text[:])))
                    fmt.println(cstring(raw_data(zydisInstruction.text[:])))
                    // setBreakpointForThread(debugEvent.dwThreadId, exeBaseAddress + rva)
                }

                continueStatus = WIN32_DBG_CONTINUE
                break
            }

            if sync.atomic_load(&windowData.debuggerCommand) == .READ {
                sync.atomic_store(&windowData.debuggerCommand, .NONE)

                expectStepException = true
                continueStatus = WIN32_DBG_CONTINUE
                ctx.EFlags |= 0x100
                assert(win32.SetThreadContext(threadHandler, &ctx) == true)

                //fmt.printfln("CURRENT RIP: %#X", ctx.Rip)

                rva := uintptr(ctx.Rip) - exeBaseAddress
                fileName, line, column, length := getSourcePositionByRVA(pdbData.session, u32(rva))

                originalStepFilePath = fileName
                originalStepLine = line

                steppingToNextLine = true

                break
                // instructionAddress := uintptr(ctx.Rip) - exeBaseAddress
                
                // rva := uintptr(ctx.Rip) - exeBaseAddress
                // _, _, _, length := getSourcePositionByRVA(pdbData.session, u32(rva))

                // instructions: [1024]u8
                // read: uint
                // res := win32.ReadProcessMemory(processInfo.hProcess, rawptr(uintptr(ctx.Rip)), raw_data(instructions[:]), uint(length), &read)
                // assert(res == true, "Could not read the debugged process memory")

                // zydisInstruction: ZydisDisassembledInstruction

                // offset: u64 = 0
                // runtimeAddress := uintptr(ctx.Rip)
                // potentialAddresses := make([dynamic]uintptr)
                // defer delete(potentialAddresses)

                // for ZydisDisassembleIntel(0, rawptr(runtimeAddress), rawptr(uintptr(raw_data(instructions[:])) + uintptr(offset)), u64(length) - offset, &zydisInstruction) & 0x80000000 == 0 {
                //     offset += u64(zydisInstruction.info.length)
                //     runtimeAddress += uintptr(zydisInstruction.info.length)

                //     switch zydisInstruction.info.opcode {
                //     case
                //         0xE8, // call
                //         0x74, // je
                //         0x7E, // jle
                //         0xEB, // jmp
                //         0x7D: // jnl
                //         address := i128(runtimeAddress) + i128(zydisInstruction.operands[0].value.imm.value.s)
                //         append(&potentialAddresses, uintptr(address))

                //         //fmt.printfln("YEAH(%#X)", address)
                //     }
                   
                //     // fmt.printfln("opcode(%#X) %s", zydisInstruction.info.opcode, cstring(raw_data(zydisInstruction.text[:])))
                //     fmt.println(cstring(raw_data(zydisInstruction.text[:])))
                //     // setBreakpointForThread(debugEvent.dwThreadId, exeBaseAddress + rva)
                // }

                // fmt.println("POTENTIAL ADDRESSES:")
                // for address in potentialAddresses {
                //     fmt.println(address)
                // }

                // fmt.printf("line has %i bytes, machine code: ", length)
                // for i in 0..=length {
                //     fmt.print(strings.right_justify(fmt.tprintf("%X", instructions[i]), 2, "0"))
                // }
                // fmt.println("")
            }
        }
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