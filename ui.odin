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
            editorState := &getActiveTabContext().editorState
            switch selected {
            case 0: edit.perform_command(editorState, edit.Command.Undo)
            case 1: edit.perform_command(editorState, edit.Command.Redo)
            case 3: edit.perform_command(editorState, edit.Command.Cut)
            case 4:
                if edit.has_selection(editorState) {
                    edit.perform_command(editorState, edit.Command.Copy)
                }
            case 5: edit.perform_command(editorState, edit.Command.Paste)
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
}

renderDebugger :: proc() {
    if actions, _ := ui.renderButton(&windowData.uiContext, ui.TextButton{
        text = "Continue",
        position = { 0, 300 },
        size = { 100, 25 },
        noBorder = true,
        bgColor = THEME_COLOR_2,
        hoverBgColor = THEME_COLOR_1,
    }); .SUBMIT in actions {
        windowData.debuggerCommand = .CONTINUE
    }

    if actions, _ := ui.renderButton(&windowData.uiContext, ui.TextButton{
        text = "Step over",
        position = { 130, 300 },
        size = { 100, 25 },
        noBorder = true,
        bgColor = THEME_COLOR_2,
        hoverBgColor = THEME_COLOR_1,
    }); .SUBMIT in actions {
        windowData.debuggerCommand = .STEP_OVER
    }

    if actions, _ := ui.renderButton(&windowData.uiContext, ui.TextButton{
        text = "Step into",
        position = { 260, 300 },
        size = { 100, 25 },
        noBorder = true,
        bgColor = THEME_COLOR_2,
        hoverBgColor = THEME_COLOR_1,
    }) ; .SUBMIT in actions {
        windowData.debuggerCommand = .STEP_INTO
    }

    //> locals / watch values at the current stop
    {
        sync.mutex_lock(&windowData.debuggerLocalsMutex)
        defer sync.mutex_unlock(&windowData.debuggerLocalsMutex)

        localY: i32 = 270
        for local in windowData.debuggerLocals {
            ui.renderLabel(&windowData.uiContext, ui.Label{
                text = fmt.tprintf("%s = %s", local.name, local.value),
                position = { 0, localY },
                color = WHITE_COLOR,
            })
            localY -= 20
        }
    }
    //<
}

recalculateFileTabsContextRects :: proc() {
    for fileTab in windowData.fileTabs {
        fileTab.ctx.rect = ui.Rect{
            top = windowData.size.y / 2 - windowData.editorPadding.top,
            bottom = -windowData.size.y / 2 + windowData.editorPadding.bottom,
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
