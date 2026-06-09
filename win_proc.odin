package main

import "base:runtime"
import "core:text/edit"
import "vendor:directx/d3d11"

import win32 "core:sys/windows"

default_context: runtime.Context

winProc :: proc "system" (hwnd: win32.HWND, msg: win32.UINT, wParam: win32.WPARAM, lParam: win32.LPARAM) -> win32.LRESULT {
    // NOTE: it's a hack to override some context data like allocators, that might be redefined in other code 
    context = default_context
    
    switch msg {
    case win32.WM_NCCREATE:
        // context = runtime.default_context()
        // windowData := (^WindowData)(((^win32.CREATESTRUCTW)(uintptr(lParam))).lpCreateParams)

        // win32.SetWindowLongPtrW(hwnd, win32.GWLP_USERDATA, win32.LONG_PTR(uintptr(&windowData)))
    case win32.WM_CREATE:
        win32.DragAcceptFiles(hwnd, true)
    case win32.WM_MOUSELEAVE:
        //TODO: Doesn't look like the best solution...
        inputState.mousePosition = {-1,-1}
    case win32.WM_MOUSEMOVE:
        // TODO: Is it efficient to call TrackMouseEvent all the time?
        track := win32.TRACKMOUSEEVENT{
            cbSize = size_of(win32.TRACKMOUSEEVENT),
            dwFlags = win32.TME_LEAVE,
            hwndTrack = hwnd,
        }
        win32.TrackMouseEvent(&track)

	    xMouse := win32.GET_X_LPARAM(lParam)
		yMouse := win32.GET_Y_LPARAM(lParam)

        prevMousePosition := inputState.mousePosition
        inputState.mousePosition = { xMouse, yMouse }

        inputState.deltaMousePosition = inputState.mousePosition - prevMousePosition

        // inputState.mousePosition.x = max(0, inputState.mousePosition.x)
        // inputState.mousePosition.y = max(0, inputState.mousePosition.y)

        // inputState.mousePosition.x = min(windowData.size.x, inputState.mousePosition.x)
        // inputState.mousePosition.y = min(windowData.size.y, inputState.mousePosition.y)
    case win32.WM_LBUTTONDOWN:
        inputState.mouse += { .LEFT_IS_DOWN, .LEFT_WAS_DOWN }

        // NOTE: Apply double click only if cursor in the same position
        if inputState.timeSinceMouseLeftDown < DOUBLE_CLICK_TIME_TRESHOLD && 
            inputState.lastClickMousePosition == getCurrentMousePosition() {
            inputState.mouse += {.LEFT_WAS_DOUBLE_CLICKED, .LEFT_IS_DOWN_AFTER_DOUBLE_CLICKED}
        }

        inputState.timeSinceMouseLeftDown = 0.0
		win32.SetCapture(hwnd)
    case win32.WM_LBUTTONUP:
        inputState.mouse += { .LEFT_WAS_UP }
        inputState.mouse -= { .LEFT_IS_DOWN, .LEFT_IS_DOWN_AFTER_DOUBLE_CLICKED }

        inputState.lastClickMousePosition = getCurrentMousePosition()

        // NOTE: We have to release previous capture, because we won't be able to use windws default buttons on the window
        win32.ReleaseCapture()
    // case win32.WM_LBUTTONDBLCLK:
    //     // NOTE: for simplicity just pretend that WM_LBUTTONDBLCLK message is just WM_LBUTTONDOWN
        
    //     // inputState.mouse += { .LEFT_IS_DOWN, .LEFT_WAS_DOWN, .LEFT_WAS_DOUBLE_CLICKED }
    //     inputState.mouse += { .LEFT_WAS_DOUBLE_CLICKED }
        
	// 	win32.SetCapture(hwnd)
    case win32.WM_RBUTTONDOWN:
        inputState.mouse += { .RIGHT_IS_DOWN, .RIGHT_WAS_DOWN }

		win32.SetCapture(hwnd)
    case win32.WM_RBUTTONUP:
        inputState.mouse += { .RIGHT_WAS_UP }
        inputState.mouse -= { .RIGHT_IS_DOWN }

        // NOTE: We have to release previous capture, because we won't be able to use windws default buttons on the window
        win32.ReleaseCapture()
    case win32.WM_MBUTTONDOWN:
        inputState.mouse += { .MIDDLE_IS_DOWN, .MIDDLE_WAS_DOWN }

        win32.SetCapture(hwnd)
    case win32.WM_MBUTTONUP:
        inputState.mouse += { .MIDDLE_WAS_UP }
        inputState.mouse -= { .MIDDLE_IS_DOWN }

        // NOTE: We have to release previous capture, because we won't be able to use windws default buttons on the window
        win32.ReleaseCapture()
    case win32.WM_SIZE:
        if !windowData.windowCreated { break }

        if wParam == win32.SIZE_MINIMIZED { break }

        clientRect: win32.RECT
        win32.GetClientRect(hwnd, &clientRect)

        windowSizeChangedHandler(clientRect.right - clientRect.left, clientRect.bottom - clientRect.top)

        editorCtx := getActiveTabContext()
        calculateLines(editorCtx)
        updateCusrorData(editorCtx)
        validateTopLine(editorCtx)

        // NOTE: while resizing we only get resize message, so we can't redraw from main loop, so we do it explicitlly
        render()
    case win32.WM_DROPFILES:
        MAX_PATH :: 512
        hDrop := win32.HDROP(wParam)
        fileCount := win32.DragQueryFileW(hDrop, 0xFFFFFFFF, nil, 0)
        filePathBuffer: [MAX_PATH]win32.WCHAR

        for i in 0..<fileCount {
            // Get the path of the file
            win32.DragQueryFileW(hDrop, i, raw_data(filePathBuffer[:]), MAX_PATH);
            filePath, err := win32.wstring_to_utf8(win32.wstring(raw_data(filePathBuffer[:])), MAX_PATH)
            assert(err == nil)
            loadFileIntoNewTab(filePath)
        }

        win32.DragFinish(hDrop)
    case win32.WM_KEYDOWN:
        handle_WM_KEYDOWN(lParam, wParam)
    case win32.WM_SYSKEYDOWN:
        // F10 is the Windows "menu" key and arrives here, NOT as WM_KEYDOWN. If it reaches
        // DefWindowProc it activates the (non-existent) window menu and the app appears frozen in a
        // modal menu loop. Capture F10 ourselves and swallow it. Other system keys (e.g. Alt+F4 ->
        // SC_CLOSE) still fall through to DefWindowProc below.
        if wParam == win32.VK_F10 {
            handle_WM_KEYDOWN(lParam, wParam)
            return 0
        }
    case win32.WM_CHAR:
        if windowData.wasInputSymbolTyped && windowData.isInputMode &&
           windowData.editableTextCtx != nil && !windowData.editableTextCtx.isReadOnly {
            edit.input_rune(&windowData.editableTextCtx.editorState, rune(wParam))
            if isActiveTabContext() { getActiveTab().isSaved = false }
            windowData.wasTextContextModified = true

            calculateLines(windowData.editableTextCtx)
            updateCusrorData(windowData.editableTextCtx)
            jumpToCursor(windowData.editableTextCtx)
        }
    case win32.WM_MOUSEWHEEL:
        yoffset := win32.GET_WHEEL_DELTA_WPARAM(wParam)

        inputState.scrollDelta = i32(yoffset)
    case win32.WM_SYSCOMMAND:
        // Handle top-right close icon click and ALT + F4
        if (wParam & 0xFFF0) == win32.SC_CLOSE {
            tryCloseEditor()
            return 0
        }
        // The editor has no native menu, so swallow Alt/F10 menu activation - otherwise the window
        // enters a modal menu loop and looks frozen until Esc/Alt is pressed.
        if (wParam & 0xFFF0) == 0xF100 { // SC_KEYMENU
            return 0
        }
    case win32.WM_SETFOCUS:
        // check all tabs, where any file changed

    case win32.WM_DESTROY:
        saveEditorState()
        // windowData.windowCloseRequested = true
        win32.PostQuitMessage(0)
    }

    // NOTE: must be the W (Unicode) variant — the window is created via
    // RegisterClassExW/CreateWindowExW. Using DefWindowProcA made the default
    // WM_NCCREATE/WM_SETTEXT handling read the wide title L"Editor" as an ANSI
    // string, which stops at the first 0x00 byte -> the title became just "E".
    return win32.DefWindowProcW(hwnd, msg, wParam, lParam)
}

// @(private="file") 
isShiftPressed :: proc() -> bool {
    return uint(win32.GetKeyState(win32.VK_SHIFT)) & 0x8000 == 0x8000
}

// @(private="file") 
isCtrlPressed :: proc() -> bool {
    return uint(win32.GetKeyState(win32.VK_LCONTROL)) & 0x8000 == 0x8000
}

handle_WM_KEYDOWN :: proc(lParam: win32.LPARAM, wParam: win32.WPARAM) {
    switch wParam {
    case win32.VK_ESCAPE: inputState.wasPressedKeys += {.ESC}
    case win32.VK_RETURN: inputState.wasPressedKeys += {.ENTER}
    case win32.VK_F1: inputState.wasPressedKeys += {.F1}
    case win32.VK_F2: inputState.wasPressedKeys += {.F2}
    case win32.VK_F3: inputState.wasPressedKeys += {.F3}
    case win32.VK_F4: inputState.wasPressedKeys += {.F4}
    case win32.VK_F5: inputState.wasPressedKeys += {.F5}
    case win32.VK_F6: inputState.wasPressedKeys += {.F6}
    case win32.VK_F7: inputState.wasPressedKeys += {.F7}
    case win32.VK_F8: inputState.wasPressedKeys += {.F8}
    case win32.VK_F9: inputState.wasPressedKeys += {.F9}
    case win32.VK_F10: inputState.wasPressedKeys += {.F10}
    case win32.VK_F11: inputState.wasPressedKeys += {.F11}
    }

    windowData.wasInputSymbolTyped = false

    if !windowData.isInputMode { return }
    
    if !isCtrlPressed() {
        isValidSymbol := false

        validInputSymbols := []int{
            win32.VK_SPACE,
            win32.VK_OEM_PLUS,
            win32.VK_OEM_COMMA,
            win32.VK_OEM_MINUS,
            win32.VK_OEM_PERIOD,
            win32.VK_OEM_1, // ;:
            win32.VK_OEM_2, // /?
            win32.VK_OEM_3, // `~
            win32.VK_OEM_4, // [{
            win32.VK_OEM_5, // \|
            win32.VK_OEM_6, // ]}
            win32.VK_OEM_7, // '"
            win32.VK_ADD,
            win32.VK_SUBTRACT,
            win32.VK_MULTIPLY,
            win32.VK_DIVIDE,
            win32.VK_DECIMAL,
        }
        
        for symbol in validInputSymbols {
            if symbol == int(wParam) {
                isValidSymbol = true
                break
            }
        }

        isValidSymbol = isValidSymbol || wParam >= 0x60 && wParam <= 0x69 // numpad
        isValidSymbol = isValidSymbol || wParam >= 0x41 && wParam <= 0x5A || wParam >= 0x30 && wParam <= 0x39

        windowData.wasInputSymbolTyped = isValidSymbol

        if isValidSymbol { return }
    }

    editorCtx := windowData.editableTextCtx
    // Read-only tabs (big files in preview mode) allow navigation/selection/copy but
    // block anything that mutates the buffer.
    canModify := editorCtx != nil && !editorCtx.isReadOnly
    switch wParam {
    case win32.VK_RETURN:
        if editorCtx == nil || editorCtx.disableNewLines || !canModify { break }
        
        // NOTE: if there's any whitespace at the beginning of the line, copy it to the new line
        lineStart := editorCtx.editorState.line_start
        whiteSpacesCount := 0
        for i in lineStart..<editorCtx.editorState.line_end {
            char := editorCtx.text.buf[i]

            if char != ' ' && char != '\t' {
                break
            }
            whiteSpacesCount += 1
        }

        edit.perform_command(&editorCtx.editorState, edit.Command.New_Line)

        if whiteSpacesCount > 0 {
            edit.input_text(&editorCtx.editorState, string(editorCtx.text.buf[lineStart:][:whiteSpacesCount]))
        }
        if isActiveTabContext() { getActiveTab().isSaved = false }
        windowData.wasTextContextModified = true
    case win32.VK_TAB:
        if isCtrlPressed() {
            if isShiftPressed() {
                moveToPrevTab()
            } else {
                moveToNextTab()
            }
        } else if canModify {
            edit.input_rune(&editorCtx.editorState, rune('\t'))
            if isActiveTabContext() { getActiveTab().isSaved = false }
            windowData.wasTextContextModified = true
        }
    case win32.VK_LEFT:
        if isCtrlPressed() {
            if isShiftPressed() {
                edit.perform_command(&editorCtx.editorState, edit.Command.Select_Word_Left)
            } else {
                edit.move_to(&editorCtx.editorState, edit.Translation.Word_Left)
            }
        } else {
            if isShiftPressed() {
                edit.perform_command(&editorCtx.editorState, edit.Command.Select_Left)
            } else {
                edit.move_to(&editorCtx.editorState, edit.Translation.Left)
            }
        }
    case win32.VK_RIGHT:
        if isCtrlPressed() {
            if isShiftPressed() {
                edit.perform_command(&editorCtx.editorState, edit.Command.Select_Word_Right)
            } else {
                edit.move_to(&editorCtx.editorState, edit.Translation.Word_Right)
            }
        } else {
            if isShiftPressed() {
                edit.perform_command(&editorCtx.editorState, edit.Command.Select_Right)
            } else {
                edit.move_to(&editorCtx.editorState, edit.Translation.Right)
            }
        }
    case win32.VK_UP:
        if isShiftPressed() {
            edit.perform_command(&editorCtx.editorState, edit.Command.Select_Up)
        } else {
            edit.move_to(&editorCtx.editorState, edit.Translation.Up)
        }
    case win32.VK_DOWN:
        if isShiftPressed() {
            edit.perform_command(&editorCtx.editorState, edit.Command.Select_Down)
        } else {
            edit.move_to(&editorCtx.editorState, edit.Translation.Down)
        }
    case win32.VK_BACK:
        if !canModify { break }
        if isCtrlPressed() {
            edit.perform_command(&editorCtx.editorState, edit.Command.Delete_Word_Left)
        } else {
            edit.perform_command(&editorCtx.editorState, edit.Command.Backspace)
        }
        if isActiveTabContext() { getActiveTab().isSaved = false }
        windowData.wasTextContextModified = true
    case win32.VK_DELETE:
        if !canModify { break }
        if isCtrlPressed() {
            edit.perform_command(&editorCtx.editorState, edit.Command.Delete_Word_Right)
        } else {
            edit.perform_command(&editorCtx.editorState, edit.Command.Delete)
        }
        if isActiveTabContext() { getActiveTab().isSaved = false }
        windowData.wasTextContextModified = true
    case win32.VK_HOME:
        jumpToCursor(editorCtx)

        if isShiftPressed() {
            edit.perform_command(&editorCtx.editorState, edit.Command.Select_Line_Start)
        } else {
            edit.move_to(&editorCtx.editorState, edit.Translation.Soft_Line_Start)
        }
    case win32.VK_END:
        jumpToCursor(editorCtx)

        if isShiftPressed() {
            edit.perform_command(&editorCtx.editorState, edit.Command.Select_Line_End)
        } else {
            edit.move_to(&editorCtx.editorState, edit.Translation.Soft_Line_End)
        }
    case win32.VK_A:
        edit.perform_command(&editorCtx.editorState, edit.Command.Select_All)
    case win32.VK_C:
        if edit.has_selection(&editorCtx.editorState) {
            edit.perform_command(&editorCtx.editorState, edit.Command.Copy)
        }
    case win32.VK_V:
        if !canModify { break }
        edit.perform_command(&editorCtx.editorState, edit.Command.Paste)

        if isActiveTabContext() { getActiveTab().isSaved = false }
        windowData.wasTextContextModified = true
    case win32.VK_X:
        if !canModify { break }
        // NOTE: if no text selection, copy current line
        if !edit.has_selection(&editorCtx.editorState) {
            line := editorCtx.lines[editorCtx.cursorLineIndex]

            if editorCtx.cursorLineIndex == i32(len(editorCtx.lines) - 1) {
                editorCtx.editorState.selection = { int(line[0] - 1), int(line[1]) }
            } else {
                editorCtx.editorState.selection = { int(line[0]), int(line[1] + 1) }
            }
        }
        edit.perform_command(&editorCtx.editorState, edit.Command.Cut)

        if isActiveTabContext() { getActiveTab().isSaved = false }
        windowData.wasTextContextModified = true
    case win32.VK_Z:
        if !canModify { break }
        if isShiftPressed() {
            edit.perform_command(&editorCtx.editorState, edit.Command.Redo)
        } else {
            edit.perform_command(&editorCtx.editorState, edit.Command.Undo)
        }
    case win32.VK_S:
        saveToOpenedFile(getActiveTab())
    case win32.VK_O:
        loadFileFromExplorerIntoNewTab()
    case win32.VK_N:
        addEmptyTab()
    case win32.VK_W:
        tryCloseFileTab(windowData.activeTabIndex)
    case win32.VK_F:
        windowData.isFileSearchOpen = true
        windowData.fileSearchJustOpened = true
    }

    switch wParam {
    case win32.VK_RETURN, win32.VK_TAB,
        win32.VK_LEFT, win32.VK_RIGHT, win32.VK_UP, win32.VK_DOWN,
        win32.VK_BACK, win32.VK_DELETE,
        win32.VK_HOME, win32.VK_END,
        win32.VK_V, win32.VK_X, win32.VK_Z:
            calculateLines(editorCtx)
            updateCusrorData(editorCtx)
            jumpToCursor(editorCtx)
    }
}

windowSizeChangedHandler :: proc "c" (width, height: i32) {
    context = runtime.default_context()

    windowData.size = { width, height }
    windowData.uiContext.clientSize = windowData.size 
    recalculateFileTabsContextRects()
    // resetClipRect()

    directXState.ctx->OMSetRenderTargets(0, nil, nil)
    directXState.backBufferView->Release()
    directXState.backBuffer->Release()
    directXState.depthBufferView->Release()
    directXState.depthBuffer->Release()

    directXState.ctx->Flush()
    directXState.swapchain->ResizeBuffers(2, u32(width), u32(height), .R8G8B8A8_UNORM, {})

	res := directXState.swapchain->GetBuffer(0, d3d11.ITexture2D_UUID, (^rawptr)(&directXState.backBuffer))
    assert(res == 0)

	res = directXState.device->CreateRenderTargetView(directXState.backBuffer, nil, &directXState.backBufferView)
    assert(res == 0)

    depthBufferDesc: d3d11.TEXTURE2D_DESC
	directXState.backBuffer->GetDesc(&depthBufferDesc)
    depthBufferDesc.Format = .D24_UNORM_S8_UINT
	depthBufferDesc.BindFlags = {.DEPTH_STENCIL}

	res = directXState.device->CreateTexture2D(&depthBufferDesc, nil, &directXState.depthBuffer)
    assert(res == 0)

	res = directXState.device->CreateDepthStencilView(directXState.depthBuffer, nil, &directXState.depthBufferView)
    assert(res == 0)

    viewport := d3d11.VIEWPORT{
        0, 0,
        f32(depthBufferDesc.Width), f32(depthBufferDesc.Height),
        0, 1,
    }

    directXState.ctx->RSSetViewports(1, &viewport)

    viewMatrix := getOrthoraphicsMatrix(f32(width), f32(height), 0.1, windowData.maxZIndex + 1.0)

    updateGpuBuffer(&viewMatrix, directXState.constantBuffers[.PROJECTION])
}
