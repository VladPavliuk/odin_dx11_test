package main

import "ui"

import "core:strings"
import "core:thread"
import "core:text/edit"

import win32 "core:sys/windows"

DOUBLE_CLICK_TIME_TRESHOLD :: 0.3

InputState :: struct {
    deltaMousePosition: int2,
    mousePosition: int2,
    lastClickMousePosition: int2,

    mouse: ui.MouseStates,

    timeSinceMouseLeftDown: f64,

    wasPressedKeys: ui.Keys,

    scrollDelta: i32,
}

inputState: InputState

GlyphsLocation :: struct {
    char: rune,
    position, size: float2,
    lineStart: i32,
}

EditableTextContext :: struct {
    text: strings.Builder,
    rect: ui.Rect,
    leftOffset: i32,

    editorState: edit.State,
    disableNewLines: bool,
    maxLineWidth: f32,

    lineIndex: f32, // top line index from which text is rendered, it's float since we want to have behaviour when only part of a line is visible (for smooth scrolling)
    cursorLineIndex: i32,
    cursorLeftOffset: f32, // offset from line start
    lines: [dynamic]int2,

    glyphsLocations: map[i32]GlyphsLocation,

    //TODO: probabyly put word wrapping property here
}

FileTab :: struct {
    name: string,
    ctx: ^EditableTextContext,
    filePath: string, // path to actual file that mapped to the tab
    isSaved: bool,
    isPinned: bool,
    lastUpdatedAt: i64, // UTC time
}

WindowData :: struct {
    windowCreated: bool,
    // windowCloseRequested: bool,
    parentHwnd: win32.HWND,

    delta: f64,
    size: int2,

    uiContext: ui.Context,
    uiTextInputCtx: EditableTextContext,

    isFileSearchOpen: bool,
    foundTermsIndexes: [dynamic]int,
    foundTermsCount: int,
    fileSearchJustOpened: bool,
    fileSearchStr: strings.Builder,
    currentFileSearchTermIndex: i32,

    wasInputSymbolTyped: bool, // distingushed between symbols on keyboard and control keys like backspace, delete, etc.
    wasTextContextModified: bool,

    maxZIndex: f32,

    font: FontData,

    isInputMode: bool,

    editorPadding: ui.Rect,

    editableTextCtx: ^EditableTextContext,

    fileTabs: [dynamic]FileTab,
    shouldJumpToActiveTab: bool,
    activeTabIndex: int,
    wasFileTabChanged: bool,

    explorer: ^Explorer,
    explorerWidth: i32,

    //> customizable settings
    wordWrapping: bool,
    //<

    //> static settings
    explorerSyncInterval: f64, // time interval to validte files in explorer
    sinceExplorerSync: f64,

    autoSaveStateInterval: f64,
    sinceAutoSaveState: f64,
    //<

    //> debugger
    debuggingFinished: bool,
    debuggerThread: ^thread.Thread,
    debuggerProcessHandler: win32.HANDLE,
    debuggerCommand: DebuggerCommand,
    debuggerBrakepoints: [dynamic]SingleBrakepoint,
    currentDebuggerInstruction: SingleBrakepoint,
    //<
}

windowData: WindowData

defaultCursor: win32.HCURSOR
horizontalSizeCursor: win32.HCURSOR
verticalSizeCursor: win32.HCURSOR

createWindow :: proc(size: int2) {
    hInstance := win32.HINSTANCE(win32.GetModuleHandleA(nil))
    
    wndClassName := win32.utf8_to_wstring("class")

    resourceIcon := win32.LoadImageW(hInstance, win32.LPCWSTR(win32.MAKEINTRESOURCEW(IDI_ICON)),
        win32.IMAGE_ICON, 256, 256, win32.LR_DEFAULTCOLOR)

    defaultCursor = win32.LoadCursorA(nil, win32.IDC_ARROW)
    horizontalSizeCursor = win32.LoadCursorA(nil, win32.IDC_SIZEWE)
    verticalSizeCursor = win32.LoadCursorA(nil, win32.IDC_SIZENS)
    
    wndClass: win32.WNDCLASSEXW = {
        cbSize = size_of(win32.WNDCLASSEXW),
        hInstance = hInstance,
        lpszClassName = wndClassName,
        lpfnWndProc = winProc,
        // style = win32.CS_DBLCLKS,
        hCursor = defaultCursor,
        hIcon = (win32.HICON)(resourceIcon),
    }
    res := win32.RegisterClassExW(&wndClass)
   
    assert(res != 0, fmt.tprintfln("Error: %i", win32.GetLastError()))
    // defer win32.UnregisterClassW(wndClassName, hInstance)

    // TODO: is it good approach?
    win32.SetProcessDpiAwarenessContext(win32.DPI_AWARENESS_CONTEXT_SYSTEM_AWARE)
    
    windowTitle := "Editor"
    
    // rect: win32.RECT = {0, 0, size.x, size.y}
    // win32.AdjustWindowRect(&rect, win32.WS_OVERLAPPEDWINDOW, true)

    hwnd := win32.CreateWindowExW(
        0,
        wndClassName,
        win32.utf8_to_wstring(windowTitle),
        win32.WS_OVERLAPPEDWINDOW | win32.CS_DBLCLKS,
        win32.CW_USEDEFAULT, win32.CW_USEDEFAULT, 
        size.x, size.y,
        nil, nil,
        hInstance,
        nil,
    )

    assert(hwnd != nil)

    //> set instance window show without fade in transition
    attrib: u32 = 1
    win32.DwmSetWindowAttribute(hwnd, u32(win32.DWMWINDOWATTRIBUTE.DWMWA_TRANSITIONS_FORCEDISABLED), &attrib, size_of(u32))
    //<

    //> set window dark mode
    attrib = 1
    win32.DwmSetWindowAttribute(hwnd, u32(win32.DWMWINDOWATTRIBUTE.DWMWA_USE_IMMERSIVE_DARK_MODE), &attrib, size_of(u32))
    darkColor: win32.COLORREF = 0x00505050
    win32.DwmSetWindowAttribute(hwnd, u32(win32.DWMWINDOWATTRIBUTE.DWMWA_BORDER_COLOR), &darkColor, size_of(win32.COLORREF))
    //<

    win32.ShowWindow(hwnd, win32.SW_SHOWDEFAULT)

    clientRect: win32.RECT
    win32.GetClientRect(hwnd, &clientRect)

    //win32.AdjustWindowRect(&clientRect)

    windowData.size = { clientRect.right - clientRect.left, clientRect.bottom - clientRect.top }
    windowData.parentHwnd = hwnd

    windowData.editorPadding = { top = 50, bottom = 15, left = 50, right = 15 }

    if !applyEditorState() {
        addEmptyTab() // if no previous editor state found, create an empty tab
    }

    windowData.isInputMode = true

    windowData.maxZIndex = 100.0

    //> default settings
    windowData.explorerWidth = 200
    windowData.wordWrapping = false

    windowData.explorerSyncInterval = 0.3
    windowData.autoSaveStateInterval = 5.0
    //<

    windowData.uiContext.getTextWidth = getTextWidth
    windowData.uiContext.getTextHeight = getTextHeight
    windowData.uiContext.font = &windowData.font
    windowData.uiContext.clientSize = windowData.size
    windowData.uiContext.closeIconId = i32(TextureId.CLOSE_ICON)
    windowData.uiContext.checkIconId = i32(TextureId.CHECK_ICON)

    windowData.uiContext.setCursor = proc(cursor: ui.CursorType) {
        switch cursor {
        case .DEFAULT: win32.SetCursor(defaultCursor)
        case .HORIZONTAL_SIZE: win32.SetCursor(horizontalSizeCursor)
        case .VERTICAL_SIZE: win32.SetCursor(verticalSizeCursor)
        }
    }

    windowData.fileSearchStr = strings.builder_make()

    // TODO: testing
    windowData.uiTextInputCtx.text = strings.builder_make()
    // strings.write_string(&windowData.uiContext.textInputCtx.text, "HYI")
    //<

    windowData.windowCreated = true
}

removeWindowData :: proc() {
    stopDebuggerThread()

    for _, kerning in windowData.font.kerningTable {
        delete(kerning)
    }
    delete(windowData.font.kerningTable)
    delete(windowData.font.chars)

    for tab in windowData.fileTabs {
        delete(tab.filePath)
        delete(tab.name)
        freeTextContext(tab.ctx)
    }
    delete(windowData.fileTabs)
    delete(windowData.foundTermsIndexes)
    
    freeTextContext(&windowData.uiTextInputCtx, false)
    strings.builder_destroy(&windowData.fileSearchStr)
    
    ui.clearContext(&windowData.uiContext)
    delete(windowData.uiTextInputCtx.lines)

    edit.destroy(&windowData.uiTextInputCtx.editorState)
    strings.builder_destroy(&windowData.uiTextInputCtx.text)
    clearExplorer(windowData.explorer)

    // TODO: investigate, is this code block is needed
    //>
    win32.DestroyWindow(windowData.parentHwnd)

    res := win32.UnregisterClassW(win32.utf8_to_wstring("class"), win32.HINSTANCE(win32.GetModuleHandleA(nil)))
    assert(bool(res), fmt.tprintfln("Error: %i", win32.GetLastError()))
    //<

    windowData = {}
}

getEditorSize :: proc() -> int2 {
    return {
        windowData.size.x - windowData.editorPadding.left - windowData.editorPadding.right,
        windowData.size.y - windowData.editorPadding.top - windowData.editorPadding.bottom,
    }
}

switchInputContextToUiElement :: proc(text: string, rect: ui.Rect, disableNewLines: bool) {
    strings.builder_reset(&windowData.uiTextInputCtx.text)
    strings.write_string(&windowData.uiTextInputCtx.text, text)

    windowData.editableTextCtx = &windowData.uiTextInputCtx

    windowData.editableTextCtx.disableNewLines = disableNewLines
    windowData.editableTextCtx.rect = rect
    ctx := windowData.editableTextCtx

    edit.init(&ctx.editorState, context.allocator, context.allocator)
    edit.setup_once(&ctx.editorState, &ctx.text)
    ctx.editorState.selection = { 0, 0 }

    ctx.editorState.set_clipboard = putTextIntoClipboard
    ctx.editorState.get_clipboard = getTextFromClipboard
    ctx.editorState.clipboard_user_data = &windowData.parentHwnd
}

switchInputContextToEditor :: proc() {
    windowData.editableTextCtx = getActiveTabContext()
    calculateLines(windowData.editableTextCtx)
    updateCusrorData(windowData.editableTextCtx)
}

tryCloseEditor :: proc() {
    // is any tab that has unsaved changes
    // hasUnsavedChanges := false
    // for tab in windowData.fileTabs {
    //     if !tab.isSaved { 
    //         hasUnsavedChanges = true
    //         break
    //     }
    // }

    win32.DestroyWindow(windowData.parentHwnd)
}