package main

import "core:text/edit"
import "core:time"
import "core:mem"
import "core:thread"
import "core:strings"
import win32 "core:sys/windows"

// Entry point. Two front-ends share the same debugger core: the normal editor (GUI) and a
// headless command-line debugger selected at build time with `-define:CMD_DEBUGGER=true`.
main :: proc() {
    when #config(CMD_DEBUGGER, false) {
        runCmdDebugger()
    } else {
        runEditor()
    }
}

runEditor :: proc() {
    when ODIN_DEBUG {
        tracker: mem.Tracking_Allocator
        mem.tracking_allocator_init(&tracker, context.allocator)
        defer mem.tracking_allocator_destroy(&tracker)
        context.allocator = mem.tracking_allocator(&tracker)
    }

    default_context = context

    createWindow({ 1000, 1000 })

    // append(&windowData.debuggerBrakepoints, SingleBrakepoint{
    //     filePath = "C:\\projects\\cpp_test_cmd\\cpp_test_cmd\\main.cpp", 
    //     line = 32,
    // })

    // testDia()

    // runDebugProcess("C:\\projects\\cpp_test_cmd\\x64\\Debug\\cpp_test_cmd.exe")
    // runDebugProcess("C:\\projects\\odin_cmd_test\\odin_cmd_test.exe")
    // runDebugProcess("C:\\projects\\CppEditor\\CppEditor\\bin\\x64\\Debug\\CppEditor.exe")

    initDirectX()

    initGpuResources()

    // set default editable context
    switchInputContextToEditor()

    msg: win32.MSG
    for msg.message != win32.WM_QUIT {
        defer free_all(context.temp_allocator)

        beforeFrame := time.tick_now()
        if win32.PeekMessageW(&msg, nil, 0, 0, win32.PM_REMOVE) {
            win32.TranslateMessage(&msg)
            win32.DispatchMessageW(&msg)
            continue
        }

        if .F5 in inputState.wasPressedKeys {
            // re-run the last exe configured via the Run dialog
            if windowData.debuggerExePath != "" {
                runDebugThread(windowData.debuggerExePath)
            }
        }

        if .F10 in inputState.wasPressedKeys {
            // Ctrl+F10 = run to the editor cursor's line; plain F10 = step over (matches Visual Studio).
            if isCtrlPressed() && windowData.debuggerThread != nil {
                tab := getActiveTab()
                ctx := getActiveTabContext()
                if tab != nil && ctx != nil && tab.filePath != "" {
                    delete(windowData.debuggerRunToFile)
                    windowData.debuggerRunToFile = strings.clone(tab.filePath)
                    windowData.debuggerRunToLine = ctx.cursorLineIndex + 1 // cursorLineIndex is 0-based
                    windowData.debuggerCommand = .RUN_TO
                }
            } else {
                windowData.debuggerCommand = .STEP_OVER
            }
        }

        if .F11 in inputState.wasPressedKeys {
            // Shift+F11 = step out, plain F11 = step into (matches Visual Studio).
            windowData.debuggerCommand = isShiftPressed() ? .STEP_OUT : .STEP_INTO
        }

        // NOTE: For some reasons if mouse double click on laptop touchpad happened, windows sends WM_LBUTTONDOWN and WM_LBUTTONUP at the same time??!
        // so we remove WM_LBUTTONUP and add DOUBLE_CLICK event
        if .LEFT_WAS_DOWN in inputState.mouse && .LEFT_WAS_UP in inputState.mouse {
            inputState.mouse -= {.LEFT_WAS_UP}
            inputState.mouse += {.LEFT_WAS_DOUBLE_CLICKED, .LEFT_IS_DOWN_AFTER_DOUBLE_CLICKED}
        }

        if windowData.editableTextCtx != nil {
            edit.update_time(&windowData.editableTextCtx.editorState)
        }

        windowData.uiContext.deltaMousePosition = inputState.deltaMousePosition
        windowData.uiContext.mousePosition = inputState.mousePosition
        windowData.uiContext.scrollDelta = inputState.scrollDelta
        windowData.uiContext.mouse = inputState.mouse
        windowData.uiContext.wasPressedKeys = inputState.wasPressedKeys

        render()

        // Stat the active file periodically rather than every frame; at vsync rate the
        // per-frame stat is a pure syscall cost with no benefit.
        if windowData.sinceFileModifiedCheck > windowData.fileModifiedCheckInterval {
            wasFileModifiedExternally(getActiveTab())
            windowData.sinceFileModifiedCheck = 0.0
        }
        windowData.sinceFileModifiedCheck += windowData.delta

        if windowData.sinceExplorerSync > windowData.explorerSyncInterval {
            validateExplorerItems(&windowData.explorer)
            windowData.sinceExplorerSync = 0.0
        }
        windowData.sinceExplorerSync += windowData.delta

        if windowData.sinceAutoSaveState > windowData.autoSaveStateInterval {
            saveEditorState()
            windowData.sinceAutoSaveState = 0.0
        }
        windowData.sinceAutoSaveState += windowData.delta
        
        //> update input state
        inputState.mouse -= {.LEFT_WAS_DOWN, .LEFT_WAS_UP, .LEFT_WAS_DOUBLE_CLICKED, .MIDDLE_WAS_DOWN, .MIDDLE_WAS_UP, .RIGHT_WAS_DOWN, .RIGHT_WAS_UP}
        inputState.wasPressedKeys = {}

        inputState.deltaMousePosition = { 0, 0 }
        
        // NOTE: add scroll smooth movement
        inputState.scrollDelta /= 10

        inputState.timeSinceMouseLeftDown += windowData.delta
        //<

        windowData.delta = time.duration_seconds(time.tick_diff(beforeFrame, time.tick_now()))
        windowData.wasTextContextModified = false

        windowData.shouldJumpToActiveTab = windowData.wasFileTabChanged // specify here the data for next rendering call
        windowData.wasFileTabChanged = false

        if windowData.debuggingFinished {
            stopDebuggerThread()
            windowData.debuggingFinished = false
        }

        // when ODIN_DEBUG {    
        //     // fmt.println("Total allocated", tracker.current_memory_allocated)
        //     // fmt.println("Total freed", tracker.total_memory_freed)
        //     // fmt.println("Total leaked", tracker.total_memory_allocated - tracker.total_memory_freed)
        // }
    } 

    removeWindowData()
    clearDirectX()
   
    when ODIN_DEBUG {
        for _, leak in tracker.allocation_map {
            //fmt.printf("%v leaked %m\n", leak.location, leak.size)
        }
        for bad_free in tracker.bad_free_array {
            fmt.printf("%v allocation %p was freed badly\n", bad_free.location, bad_free.memory)
        }

        if tracker.total_memory_allocated - tracker.total_memory_freed > 0 {        
            fmt.println("Total allocated", tracker.total_memory_allocated)
            fmt.println("Total freed", tracker.total_memory_freed)
            fmt.println("Total leaked", tracker.total_memory_allocated - tracker.total_memory_freed)
        }
    }
}