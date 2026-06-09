package main

import "core:os"
import "core:fmt"
import "core:sync"
import "core:strings"
import "core:text/edit"
import "core:path/filepath"
import "core:slice"
import win32 "core:sys/windows"

import "ui"

renderTopMenu :: proc() {
    // top menu background
    fileMenuHeight: i32 = 25
    
    ui.pushCommand(&windowData.uiContext, ui.RectCommand{
        rect = ui.Rect{
            top = windowData.size.y / 2,
            bottom = windowData.size.y / 2 - fileMenuHeight,
            left = -windowData.size.x / 2,
            right = windowData.size.x / 2,
        },
        bgColor = DARKER_GRAY_COLOR,
    })

    topItemPosition: int2 = { -windowData.size.x / 2, windowData.size.y / 2 - fileMenuHeight }

    { // File menu
        fileItems := []ui.DropdownItem{
            { text = "New File", rightText = "Ctrl+N" },
            { text = "Open Folder" },
            { text = "Open...", rightText = "Ctrl+O" },
            { text = "Save", rightText = "Ctrl+S" },
            { text = "Save as..." },
            { isSeparator = true },
            { text = "Exit", rightText = "Alt+F4" },
        }

        @(static)
        isOpen: bool = false

        if actions, selected := ui.renderDropdown(&windowData.uiContext, ui.Dropdown{
            text = "File",
            position = topItemPosition, size = { 60, fileMenuHeight },
            items = fileItems,
            bgColor = DARKER_GRAY_COLOR,
            selectedItemIndex = -1,
            maxItemShow = i32(len(fileItems)),
            isOpen = &isOpen,
            itemStyles = {
                size = { 250, 0 },
                padding = ui.Rect{ top = 2, bottom = 3, left = 20, right = 10, },
            },
        }); .SUBMIT in actions {
            switch selected {
            case 0: addEmptyTab()
            case 1:
                folderPath, ok := showOpenFileDialog(true)
                if ok { showExplorer(strings.clone(folderPath)) }
            case 2: loadFileFromExplorerIntoNewTab()
            case 3: saveToOpenedFile(getActiveTab())            
            case 4: showSaveAsFileDialog(getActiveTab())
            case 6: tryCloseEditor()
            }
        }
        topItemPosition.x += 60
    }

    { // Edit
        // TODO: add disabling of items that do nothing at the moment
        editItems := []ui.DropdownItem{
            { text = "Undo", rightText = "Ctrl+Z" },
            { text = "Redo", rightText = "Ctrl+Shift+Z" },
            { isSeparator = true },
            { text = "Cut", rightText = "Ctrl+X" },
            { text = "Copy", rightText = "Ctrl+C" },
            { text = "Paste", rightText = "Ctrl+V" },
            { isSeparator = true },
            { text = "Find in current file", rightText = "Ctrl+F" },
            { text = "Replace in current file", rightText = "Ctrl+H" },
            { isSeparator = true },
            { text = "Find in files", rightText = "Ctrl+Shift+F" },
            { text = "Replace in files", rightText = "Ctrl+Shift+H" },
        }

        @(static)
        isOpen: bool = false

        if actions, selected := ui.renderDropdown(&windowData.uiContext, ui.Dropdown{
            text = "Edit",
            position = topItemPosition, size = { 60, fileMenuHeight },
            items = editItems,
            bgColor = DARKER_GRAY_COLOR,
            selectedItemIndex = -1,
            maxItemShow = i32(len(editItems)),
            isOpen = &isOpen,
            itemStyles = {
                size = { 300, 0 },
                padding = ui.Rect{ top = 2, bottom = 3, left = 20, right = 10, },
            },
        }); .SUBMIT in actions {
            editorCtx := getActiveTabContext()
            editorState := &editorCtx.editorState
            canModify := !editorCtx.isReadOnly // read-only tabs allow Copy only
            switch selected {
            case 0: if canModify { edit.perform_command(editorState, edit.Command.Undo) }
            case 1: if canModify { edit.perform_command(editorState, edit.Command.Redo) }
            case 3: if canModify { edit.perform_command(editorState, edit.Command.Cut) }
            case 4:
                if edit.has_selection(editorState) {
                    edit.perform_command(editorState, edit.Command.Copy)
                }
            case 5: if canModify { edit.perform_command(editorState, edit.Command.Paste) }
            }
        }
        topItemPosition.x += 60
    }

    { // Settings menu
        @(static)
        showSettings := false
        if actions, _ := ui.renderButton(&windowData.uiContext, ui.TextButton{
            text = "Settings",
            position = topItemPosition, size = { 100, fileMenuHeight },
            bgColor = DARKER_GRAY_COLOR,
            noBorder = true,
        }); .SUBMIT in actions {
            showSettings = !showSettings
        }

        if showSettings {
            @(static)
            panelPosition: int2 = { -250, -100 } 

            @(static)
            panelSize: int2 = { 250, 300 }

            ui.beginPanel(&windowData.uiContext, ui.Panel{
                title = "Settings",
                position = &panelPosition,
                size = &panelSize,
                bgColor = GRAY_COLOR,
                borderColor = BLACK_COLOR,
                // hoverBgColor = THEME_COLOR_5,
            }, &showSettings)

            ui.renderLabel(&windowData.uiContext, ui.Label{
                text = "Custom Font",
                position = { 0, 250 },
                color = WHITE_COLOR,
            })

            renderTextField(&windowData.uiContext, ui.TextField{
                text = "YEAH",
                position = { 0, 220 },
                size = { 200, 30 },
                bgColor = LIGHT_GRAY_COLOR,
            })

            if actions, _ := ui.renderButton(&windowData.uiContext, ui.TextButton{
                text = "Load Font",
                position = { 0, 190 },
                size = { 100, 30 },
                bgColor = THEME_COLOR_1,
                disabled = strings.builder_len(windowData.uiTextInputCtx.text) == 0,
            }); .SUBMIT in actions {
                // try load font
                fontPath := strings.to_string(windowData.uiTextInputCtx.text)

                if os.exists(fontPath) {
                    directXState.textures[.FONT], windowData.font = loadFont(fontPath)
                } else {
                    ui.pushAlert(&windowData.uiContext, ui.Alert{
                        text = strings.clone("Specified file does not exist!"),
                        bgColor = RED_COLOR,
                    })
                }
            }
            
            @(static)
            checked := false
            if .SUBMIT in ui.renderCheckbox(&windowData.uiContext, ui.Checkbox{
                text = "word wrapping",
                checked = &windowData.wordWrapping,
                position = { 0, 40 },
                color = WHITE_COLOR,
                bgColor = GREEN_COLOR,
                hoverBgColor = BLACK_COLOR,
            }) {
                //TODO: looks a bit hacky
                ctx := getActiveTabContext()
                if ctx != nil {
                    if windowData.wordWrapping {
                        ctx.leftOffset = 0
                    }
                    calculateLines(ctx)
                    updateCusrorData(ctx)
                    validateTopLine(ctx)
                    
                }
                // jumpToCursor(&windowData.editorCtx)
            }

            //testingButtons()
            
            ui.endPanel(&windowData.uiContext)
        }
        topItemPosition.x += 100
    }

    { // Run menu
        items := []ui.DropdownItem{
            { text = "Start new process" },
        }

        @(static)
        isOpen: bool = false
        
        @(static)
        showRunProcessPanel := false

        if actions, selected := ui.renderDropdown(&windowData.uiContext, ui.Dropdown{
            text = "Run",
            position = topItemPosition, size = { 60, fileMenuHeight },
            items = items,
            bgColor = DARKER_GRAY_COLOR,
            selectedItemIndex = -1,
            maxItemShow = i32(len(items)),
            isOpen = &isOpen,
            itemStyles = {
                size = { 200, 0 },
                padding = ui.Rect{ top = 2, bottom = 3, left = 20, right = 10, },
            },
        }); .SUBMIT in actions {
            switch selected {
            case 0: {
                showRunProcessPanel = true
            }
            }
        }

        @(static)
        panelPosition: int2 = { -250, -100 } 

        @(static)
        panelSize: int2 = { 500, 150 }

        if showRunProcessPanel {
            ui.beginPanel(&windowData.uiContext, ui.Panel{
                title = "Settings",
                position = &panelPosition,
                size = &panelSize,
                bgColor = GRAY_COLOR,
                borderColor = BLACK_COLOR,
                // hoverBgColor = THEME_COLOR_5,
            }, &showRunProcessPanel)

            ui.renderLabel(&windowData.uiContext, ui.Label{
                text = "Exe file path",
                position = { 0, 100 },
                color = WHITE_COLOR,
            })

            renderTextField(&windowData.uiContext, ui.TextField{
                text = windowData.debuggerExePath,
                // text = "C:\\projects\\CppEditor\\CppEditor\\bin\\x64\\Debug\\CppEditor.exe",
                position = { 0, 70 },
                size = { 450, 30 },
                bgColor = LIGHT_GRAY_COLOR,
            })

            if actions, _ := ui.renderButton(&windowData.uiContext, ui.TextButton{
                text = "Run",
                position = { 0, 10 },
                size = { 100, 30 },
                bgColor = THEME_COLOR_1,
                //disabled = strings.builder_len(windowData.uiTextInputCtx.text) == 0,
            }); .SUBMIT in actions {
                exePath := strings.to_string(windowData.uiTextInputCtx.text)

                if os.exists(exePath) {
                    runDebugThread(exePath)
                } else {
                    ui.pushAlert(&windowData.uiContext, ui.Alert{
                        text = strings.clone("Specified file does not exist!"),
                        bgColor = RED_COLOR,
                    })
                }
            }

            ui.endPanel(&windowData.uiContext)
        }

        topItemPosition.x += 60
    }

    { // Read-only indicator (right side of the menu bar) for big files opened in preview mode
        activeCtx := getActiveTabContext()
        if activeCtx != nil && activeCtx.isReadOnly {
            indicatorText := "READ ONLY"
            textWidth := getTextWidth(indicatorText, &windowData.font)
            textHeight := windowData.font.lineHeight
            padX: i32 = 8

            right := windowData.size.x / 2 - 10
            left := right - i32(textWidth) - 2 * padX
            top := windowData.size.y / 2
            bottom := top - fileMenuHeight

            ui.pushCommand(&windowData.uiContext, ui.RectCommand{
                rect = ui.Rect{ top = top, bottom = bottom, left = left, right = right },
                bgColor = float4{ 0.85, 0.4, 0.1, 1.0 },
            })

            ui.renderLabel(&windowData.uiContext, ui.Label{
                text = indicatorText,
                position = { left + padX, bottom + i32((f32(fileMenuHeight) - textHeight) / 2.0) },
                color = WHITE_COLOR,
            })
        }
    }
}

DEBUG_PANEL_HEIGHT :: 260 // height of the docked bottom debug panel (also reserved as editor padding)
DEBUG_CONTROL_BUTTON_SIZE :: int2{ 90, 24 }

// Bottom-left position (centered UI coords, +y up) of debug control button `index` (0 = Continue ..
// 3 = Step out). Shared with the UI tests so they can locate the buttons without duplicating layout.
debugControlButtonPosition :: proc(index: i32) -> int2 {
    pad: i32 = 10
    gap: i32 = 6
    panelTop := -windowData.size.y / 2 + DEBUG_PANEL_HEIGHT
    return {
        -windowData.size.x / 2 + pad + index * (DEBUG_CONTROL_BUTTON_SIZE.x + gap),
        panelTop - 8 - DEBUG_CONTROL_BUTTON_SIZE.y,
    }
}

// The docked debug panel at the bottom of the window, shown only while a debug session is active.
// Hosts the run controls, the current stop location, the call stack, locals, and a live view of the
// debuggee's process memory (RAM).
renderDebugger :: proc() {
    panelHeight := windowData.debugPanelHeight
    if panelHeight <= 0 { panelHeight = DEBUG_PANEL_HEIGHT }

    panelBottom := -windowData.size.y / 2
    panelLeft := -windowData.size.x / 2
    panelRight := windowData.size.x / 2
    panelTop := panelBottom + panelHeight

    pad: i32 = 10
    rowH := i32(windowData.font.lineHeight)

    panelRect := ui.Rect{ top = panelTop, bottom = panelBottom, left = panelLeft, right = panelRight }
    // Swallow mouse input over the panel so clicks/scroll don't reach the editor behind it.
    ui.putEmptyElement(&windowData.uiContext, panelRect)
    ui.pushCommand(&windowData.uiContext, ui.RectCommand{ rect = panelRect, bgColor = DARKER_GRAY_COLOR })
    ui.pushCommand(&windowData.uiContext, ui.BorderRectCommand{ rect = panelRect, color = BLACK_COLOR, thikness = 1 })

    //> run controls
    // Distinct customIds: all four share a call site, so they'd otherwise share a
    // #caller_location-derived id and hover/highlight (and submit) as one.
    renderDebugControlButton("Continue",  debugControlButtonPosition(0), DEBUG_CONTROL_BUTTON_SIZE, .CONTINUE, 1)
    renderDebugControlButton("Step over", debugControlButtonPosition(1), DEBUG_CONTROL_BUTTON_SIZE, .STEP_OVER, 2)
    renderDebugControlButton("Step into", debugControlButtonPosition(2), DEBUG_CONTROL_BUTTON_SIZE, .STEP_INTO, 3)
    renderDebugControlButton("Step out",  debugControlButtonPosition(3), DEBUG_CONTROL_BUTTON_SIZE, .STEP_OUT, 4)
    renderDebugControlButton("Step inst", debugControlButtonPosition(4), DEBUG_CONTROL_BUTTON_SIZE, .STEP_INSTRUCTION, 5)
    //<

    //> status line
    statusY := debugControlButtonPosition(0).y - 8 - rowH
    statusText: string
    if sync.atomic_load(&windowData.debuggerPaused) {
        instr := windowData.currentDebuggerInstruction
        if instr.filePath != "" {
            statusText = fmt.tprintf("Paused at %s:%d", filepath.base(instr.filePath), instr.line)
        } else {
            statusText = "Paused"
        }
    } else {
        statusText = "Running..."
    }
    ui.renderLabel(&windowData.uiContext, ui.Label{ text = statusText, position = { panelLeft + pad, statusY }, color = WHITE_COLOR })

    // compact registers line (the full register set is in the cmd debugger's `reg` command)
    regs := windowData.debuggerRegisters
    registersY := statusY - rowH - 2
    ui.renderLabel(&windowData.uiContext, ui.Label{
        text = fmt.tprintf("rip=%X  rsp=%X  rbp=%X  rax=%X  rbx=%X", regs.rip, regs.rsp, regs.rbp, regs.rax, regs.rbx),
        position = { panelLeft + pad, registersY },
        color = LIGHT_GRAY_COLOR,
    })
    //<

    columnsTop := registersY - 10 - rowH
    columnBottom := panelBottom + pad

    // Right-anchor the memory column (its rows are wide); split the remaining left space between the
    // call stack and the locals.
    memoryWidth: i32 = 440
    memoryLeft := panelRight - pad - memoryWidth
    leftRegionRight := memoryLeft - pad
    callStackLeft := panelLeft + pad
    localsLeft := callStackLeft + max(160, (leftRegionRight - callStackLeft) / 2)

    //> call stack
    {
        sync.mutex_lock(&windowData.debuggerCallStackMutex)
        defer sync.mutex_unlock(&windowData.debuggerCallStackMutex)

        y := columnsTop
        ui.renderLabel(&windowData.uiContext, ui.Label{ text = "Call stack", position = { callStackLeft, y }, color = THEME_COLOR_2 })
        y -= rowH + 2
        for frame in windowData.debuggerCallStack {
            if y < columnBottom { break }
            label: string
            if frame.filePath != "" {
                label = fmt.tprintf("%s  (%s:%d)", frame.function, filepath.base(frame.filePath), frame.line)
            } else {
                label = frame.function
            }
            ui.renderLabel(&windowData.uiContext, ui.Label{ text = label, position = { callStackLeft, y }, color = WHITE_COLOR })
            y -= rowH
        }
    }
    //<

    //> locals
    {
        sync.mutex_lock(&windowData.debuggerLocalsMutex)
        defer sync.mutex_unlock(&windowData.debuggerLocalsMutex)

        y := columnsTop
        ui.renderLabel(&windowData.uiContext, ui.Label{ text = "Locals", position = { localsLeft, y }, color = THEME_COLOR_2 })
        y -= rowH + 2
        for local in windowData.debuggerLocals {
            if y < columnBottom { break }
            ui.renderLabel(&windowData.uiContext, ui.Label{
                text = fmt.tprintf("%s = %s", local.name, local.value),
                position = { localsLeft, y },
                color = WHITE_COLOR,
            })
            y -= rowH
        }
    }
    //<

    renderDebuggerMemoryView(memoryLeft, columnsTop, columnBottom, rowH)
}

// One of the docked panel's run-control buttons; clicking it queues the given command for the debug
// loop. `customId` must be unique per button: they share a call site, so the id is otherwise identical.
renderDebugControlButton :: proc(text: string, position: int2, size: int2, command: DebuggerCommand, customId: i32) {
    if actions, _ := ui.renderButton(&windowData.uiContext, ui.TextButton{
        text = text,
        position = position,
        size = size,
        noBorder = true,
        bgColor = THEME_COLOR_2,
        hoverBgColor = THEME_COLOR_1,
    }, customId); .SUBMIT in actions {
        windowData.debuggerCommand = command
    }
}

// The memory (RAM) viewer column: an editable hex address field over a live hex+ascii dump of the
// debuggee's memory. An empty/invalid address follows the current stack pointer (RSP at the last stop).
renderDebuggerMemoryView :: proc(left, top, bottom, rowH: i32) {
    y := top

    rsp := sync.atomic_load(&windowData.debuggerStackPointer)
    effectiveAddress := windowData.debuggerMemoryAddress != 0 ? windowData.debuggerMemoryAddress : rsp

    headerText: string
    if windowData.debuggerMemoryAddress != 0 {
        headerText = fmt.tprintf("Memory @ %012X", effectiveAddress)
    } else {
        headerText = fmt.tprintf("Memory @ %012X (rsp)", effectiveAddress)
    }
    ui.renderLabel(&windowData.uiContext, ui.Label{ text = headerText, position = { left, y }, color = THEME_COLOR_2 })
    y -= rowH + 2

    // Editable address field (own row, so it never collides with the header). Mirrors the file-search
    // pattern: read the live edit back out of the shared input context while focused.
    fieldActions, _ := renderTextField(&windowData.uiContext, ui.TextField{
        text = strings.to_string(windowData.debuggerMemoryAddressInput),
        position = { left, y - 4 },
        size = { 220, rowH + 6 },
        bgColor = LIGHT_GRAY_COLOR,
    })
    if .FOCUSED in fieldActions && windowData.wasTextContextModified {
        strings.builder_reset(&windowData.debuggerMemoryAddressInput)
        strings.write_string(&windowData.debuggerMemoryAddressInput, strings.to_string(windowData.uiTextInputCtx.text))
        windowData.debuggerMemoryAddress = parseHexAddress(strings.to_string(windowData.debuggerMemoryAddressInput))
    }

    y -= rowH + 14

    buf: [80]u8 // 10 rows of 8 bytes
    bytesRead: uint
    readOk := false
    if effectiveAddress != 0 && windowData.debuggerProcessHandler != nil {
        if win32.ReadProcessMemory(windowData.debuggerProcessHandler, win32.LPCVOID(uintptr(effectiveAddress)),
            raw_data(buf[:]), uint(len(buf)), &bytesRead) && bytesRead > 0 {
            readOk = true
        }
    }

    if !readOk {
        ui.renderLabel(&windowData.uiContext, ui.Label{ text = "<unreadable>", position = { left, y }, color = LIGHT_GRAY_COLOR })
        return
    }

    BYTES_PER_ROW :: 8
    rows := int(bytesRead) / BYTES_PER_ROW
    for r in 0 ..< rows {
        if y < bottom { break }
        rowAddress := effectiveAddress + u64(r * BYTES_PER_ROW)
        ui.renderLabel(&windowData.uiContext, ui.Label{
            text = formatMemoryRow(rowAddress, buf[r * BYTES_PER_ROW:(r + 1) * BYTES_PER_ROW]),
            position = { left, y },
            color = WHITE_COLOR,
        })
        y -= rowH
    }
}

// "<addr>  HH HH .. HH  <ascii>" for one row of a memory dump (temp-allocated, valid for this frame).
formatMemoryRow :: proc(rowAddress: u64, bytes: []u8) -> string {
    b := strings.builder_make(context.temp_allocator)
    fmt.sbprintf(&b, "%012X  ", rowAddress)
    for v in bytes { fmt.sbprintf(&b, "%02X ", v) }
    strings.write_byte(&b, ' ')
    for v in bytes { strings.write_byte(&b, (v >= 32 && v < 127) ? v : byte('.')) }
    return strings.to_string(b)
}

// Parses a hex string (optional "0x"/"0X" prefix, ignores spaces/underscores). Returns 0 for empty or
// invalid input, which the memory viewer treats as "follow the stack pointer".
parseHexAddress :: proc(s: string) -> u64 {
    t := strings.trim_space(s)
    if strings.has_prefix(t, "0x") || strings.has_prefix(t, "0X") { t = t[2:] }

    value: u64 = 0
    seenDigit := false
    for ch in t {
        digit: u64
        switch ch {
        case '0' ..= '9': digit = u64(ch - '0')
        case 'a' ..= 'f': digit = u64(ch - 'a') + 10
        case 'A' ..= 'F': digit = u64(ch - 'A') + 10
        case ' ', '_':    continue
        case:             return seenDigit ? value : 0 // stop at the first invalid character
        }
        value = value * 16 + digit
        seenDigit = true
    }
    return value
}

recalculateFileTabsContextRects :: proc() {
    for fileTab in windowData.fileTabs {
        fileTab.ctx.rect = ui.Rect{
            top = windowData.size.y / 2 - windowData.editorPadding.top,
            // debugPanelHeight lifts the editor's bottom edge above the docked debug panel (0 when idle)
            bottom = -windowData.size.y / 2 + windowData.editorPadding.bottom + windowData.debugPanelHeight,
            left = -windowData.size.x / 2 + windowData.editorPadding.left,
            right = windowData.size.x / 2 - windowData.editorPadding.right,
        }
    }
}

getIconByFilePath :: proc(filePath: string) -> TextureId {
    if len(filePath) == 0 { return .NONE }

    fileExtension := filepath.ext(filePath)

    switch fileExtension {
    case ".txt": return .TXT_FILE_ICON
    case ".c": return .C_FILE_ICON
    case ".cpp": return .C_PLUS_PLUS_FILE_ICON
    case ".cs": return .C_SHARP_FILE_ICON
    case ".js": return .JS_FILE_ICON
    }

    return .TXT_FILE_ICON // by default treat unknown types as txt files
}

// TODO: move it from here
renderEditorContent :: proc() {
    editorCtx := getActiveTabContext()
    if editorCtx == nil { return }

    maxLinesOnScreen := getEditorSize().y / i32(windowData.font.lineHeight)
    totalLines := i32(len(editorCtx.lines))

    editorRectSize := ui.getRectSize(editorCtx.rect)

    MAX_SCROLL_SIZE :: 30
    @(static)
    verticalOffset: i32 = 0

    verticalScrollWidth := windowData.editorPadding.right
    verticalScrollSize := i32(f32(editorRectSize.y * maxLinesOnScreen) / f32(maxLinesOnScreen + (totalLines - 1)))
    //TODO: it shouldn't be some hardcoded value (probably)
    verticalScrollSize = max(MAX_SCROLL_SIZE, verticalScrollSize)

    @(static)
    horizontalOffset: i32 = 0

    horizontalScrollHeight := windowData.editorPadding.bottom
    actualHorizontalScrollSize := editorRectSize.x
    visibleHorizontalScrollSize := editorRectSize.x

    hasHorizontalScroll := editorCtx.maxLineWidth > f32(editorRectSize.x)

    if hasHorizontalScroll {
        actualHorizontalScrollSize = i32(f32(editorRectSize.x * editorRectSize.x) / editorCtx.maxLineWidth)
        visibleHorizontalScrollSize = max(MAX_SCROLL_SIZE, actualHorizontalScrollSize)
    }

    ui.beginScroll(&windowData.uiContext)

    editorContentActions, editorContentId := ui.putEmptyElement(&windowData.uiContext, editorCtx.rect)

    if windowData.wasFileTabChanged {
        windowData.uiContext.tmpFocusedId = editorContentId
    }

    handleTextInputActions(editorCtx, editorContentActions)

    fillGlyphsLocations(editorCtx)
    //calculateLines(editorCtx)
    // updateCusrorData(editorCtx)

    // setClipRect(editorCtx.rect)
    glyphsCount, selectionsCount := fillTextBuffer(editorCtx, WHITE_COLOR, windowData.maxZIndex)
    
    renderText(glyphsCount, selectionsCount, TEXT_SELECTION_BG_COLOR)
    // resetClipRect()

    verticalScrollActions, horizontalScrollActions := ui.endScroll(&windowData.uiContext, ui.Scroll{
        bgRect = {
            top = editorCtx.rect.top,
            bottom = editorCtx.rect.bottom,
            left = editorCtx.rect.right,
            right = editorCtx.rect.right + verticalScrollWidth,
        },
        size = verticalScrollSize,
        offset = &verticalOffset,
        color = float4{ 0.7, 0.7, 0.7, 1.0 },
        hoverColor = float4{ 1.0, 1.0, 1.0, 1.0 },
        bgColor = float4{ 0.2, 0.2, 0.2, 1.0 },
        preventAutomaticScroll = true,
    }, ui.Scroll{
        bgRect = {
            top = editorCtx.rect.bottom,
            bottom = editorCtx.rect.bottom - horizontalScrollHeight,
            left = editorCtx.rect.left,
            right = editorCtx.rect.right,
        },
        size = visibleHorizontalScrollSize,
        offset = &horizontalOffset,
        color = float4{ 0.7, 0.7, 0.7, 1.0 },
        hoverColor = float4{ 1.0, 1.0, 1.0, 1.0 },
        bgColor = float4{ 0.2, 0.2, 0.2, 1.0 },
    })

    if .MOUSE_WHEEL_SCROLL in verticalScrollActions {
        editorCtx.lineIndex -= f32(inputState.scrollDelta) / 30.0
        validateTopLine(editorCtx)
    }

    if .ACTIVE in verticalScrollActions {
        editorCtx.lineIndex = f32((totalLines - 1) * verticalOffset) / f32(editorRectSize.y - verticalScrollSize)
    } else {
        lineSizeForScroll := f32(editorRectSize.y - verticalScrollSize) / f32(totalLines - 1)
        verticalOffset = i32(lineSizeForScroll * editorCtx.lineIndex)
    }

    // what a weird formulas!
    if .ACTIVE in horizontalScrollActions {
        editorCtx.leftOffset = i32(f32(horizontalOffset) * (editorCtx.maxLineWidth - f32(editorRectSize.x)) / f32(editorRectSize.x - visibleHorizontalScrollSize))
    } else {
        horizontalOffset = i32(f32(editorRectSize.x - visibleHorizontalScrollSize) * f32(editorCtx.leftOffset) / (editorCtx.maxLineWidth - f32(editorRectSize.x)))
    }
}

renderTextField :: proc(ctx: ^ui.Context, textField: ui.TextField, customId: i32 = 0, loc := #caller_location) -> (ui.Actions, ui.Id) {
    actions, id := ui.renderTextField(&windowData.uiContext, textField, customId, loc)

    // TODO: it's better to return rect from  renderTextField
    position := textField.position + ui.getAbsolutePosition(ctx)
    uiRect := ui.toRect(position, textField.size)

    textHeight := ctx.getTextHeight(ctx.font)

    inputContextRect := ui.Rect{
        top = uiRect.top - textField.size.y / 2 + i32(textHeight / 2),
        bottom = uiRect.bottom + textField.size.y / 2 - i32(textHeight / 2),
        left = uiRect.left + 5,
        right = uiRect.right - 5,
    }
    
    if .GOT_FOCUS in actions {
        switchInputContextToUiElement(textField.text, inputContextRect, true)

        // pre-select text
        windowData.uiTextInputCtx.editorState.selection = { int(textField.initSelection[0]), int(textField.initSelection[1]) }
        
        calculateLines(&windowData.uiTextInputCtx)
        updateCusrorData(&windowData.uiTextInputCtx)
    }

    if .LOST_FOCUS in actions {
        switchInputContextToEditor()
    }

    if .FOCUSED in actions {
        windowData.uiTextInputCtx.rect = inputContextRect
        handleTextInputActions(&windowData.uiTextInputCtx, actions)
    }

    return actions, id
}

handleTextInputActions :: proc(ctx: ^EditableTextContext, actions: ui.Actions) {
    // NOTE: that looks kinda werid,
    // but I can't find any place where it might be used else where, so I just created a local var
    @(static)
    originalCurosorIndex: i32 = -1

    if .GOT_ACTIVE in actions {
        pos := getCursorIndexByMousePosition(ctx, inputState.mousePosition)
        ctx.editorState.selection = { pos, pos }

        originalCurosorIndex = i32(pos)
    }

    if .LOST_ACTIVE in actions {
        originalCurosorIndex = -1
    }

    if .ACTIVE in actions {
        if .LEFT_IS_DOWN_AFTER_DOUBLE_CLICKED in inputState.mouse {
            currentCursorIndex := getCursorIndexByMousePosition(ctx, inputState.mousePosition)

            selectWholeWord(ctx, i32(originalCurosorIndex))

            originalSelectedWordSelection := ctx.editorState.selection

            selectWholeWord(ctx, i32(currentCursorIndex))

            ctx.editorState.selection = {
                max(originalSelectedWordSelection[0], ctx.editorState.selection[0]),
                min(originalSelectedWordSelection[1], ctx.editorState.selection[1]),
            }

            // NOTE: If after words selection, user moves cursor moves before originally selected word, 
            // set cursor at the beginning of the whole selection.
            if currentCursorIndex < min(originalSelectedWordSelection[0], originalSelectedWordSelection[1]) {
                slice.reverse(ctx.editorState.selection[:])
            }
        } else {
            ctx.editorState.selection[0] = getCursorIndexByMousePosition(ctx, inputState.mousePosition)
        }
 
        mousePosition := ui.screenToDirectXCoords(inputState.mousePosition, &windowData.uiContext)

        // NOTE: handle dragging of text selection above/below visible lines rect
        if mousePosition.y > ctx.rect.top {
            ctx.lineIndex -= f32(max(1, (mousePosition.y - ctx.rect.top) / 10))
            validateTopLine(ctx)
        } else if mousePosition.y < ctx.rect.bottom {
            ctx.lineIndex += f32(max(1, (ctx.rect.bottom - mousePosition.y) / 10))
            validateTopLine(ctx)
        }
        
        // NOTE: handle dragging of text selection left/right visible lines rect
        if mousePosition.x > ctx.rect.right {
            ctx.leftOffset += max(5, (mousePosition.x - ctx.rect.right) / 5)
            validateLeftOffset(ctx)
        } else if mousePosition.x < ctx.rect.left {
            ctx.leftOffset -= max(5, (ctx.rect.left - mousePosition.x) / 5)
            validateLeftOffset(ctx)
        }
        updateCusrorData(ctx)
    }
}
