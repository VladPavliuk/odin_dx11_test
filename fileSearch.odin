package main

import "ui"
import "base:intrinsics"
import "core:strings"
import "core:unicode/utf8"

renderFileSearch :: proc() {
    size := int2{ 200, 80 }
    position := int2{ windowData.size.x / 2 - size.x - 15, windowData.size.y / 2 - size.y - 60 }

    bgRect := ui.toRect(position, size)
    ui.putEmptyElement(&windowData.uiContext, bgRect)
    ui.pushCommand(&windowData.uiContext, ui.RectCommand{
        rect = bgRect,
        bgColor = GRAY_COLOR,
    })
    ui.pushCommand(&windowData.uiContext, ui.BorderRectCommand{
        rect = bgRect,
        color = BLACK_COLOR,
        thikness = 1,
    })

    ui.renderLabel(&windowData.uiContext, ui.Label{
        text = "File search",
        position = { position.x + 5, position.y + 55 },
        color = BLACK_COLOR,
    })

    iconWidth: i32 = 25
    if closeButtonActions, _ := ui.renderButton(&windowData.uiContext, ui.ImageButton{
        position = { position.x + size.x - iconWidth - 5, position.y + size.y - iconWidth - 2, },
        size = { iconWidth, iconWidth },
        textureId = i32(TextureId.CLOSE_ICON),
        texturePadding = 2,
        bgColor = EMPTY_COLOR,
        noBorder = true,
    }); .SUBMIT in closeButtonActions {
        windowData.isFileSearchOpen = false
    }

    actions, fieldId := renderTextField(&windowData.uiContext, ui.TextField{
        text = strings.to_string(windowData.fileSearchStr),
        position = { position.x + 5, position.y + 25 },
        size = { size.x - 10, 25 },
    })

    if windowData.fileSearchJustOpened {
        windowData.uiContext.tmpFocusedId = fieldId
        windowData.fileSearchJustOpened = false
    }

    if windowData.uiContext.focusedId == fieldId && .ESC in inputState.wasPressedKeys {
        windowData.currentFileSearchTermIndex = 0
        windowData.foundTermsCount = 0
        windowData.isFileSearchOpen = false
        windowData.uiContext.tmpFocusedId = 0
        strings.builder_reset(&windowData.fileSearchStr)
        clear(&windowData.foundTermsIndexes)
        switchInputContextToEditor()
    }

    ui.renderLabel(&windowData.uiContext, ui.Label{
        text = windowData.foundTermsCount > 0 ? fmt.tprintf("%i of %i", windowData.currentFileSearchTermIndex + 1, windowData.foundTermsCount) : fmt.tprintf("no matches"),
        position = { position.x + 5, position.y + 5 },
        color = BLACK_COLOR,
    })

    if windowData.wasTextContextModified || windowData.wasFileTabChanged {
        windowData.foundTermsCount = count_with_indexes(strings.to_string(getActiveTab().ctx.text), strings.to_string(windowData.uiTextInputCtx.text), &windowData.foundTermsIndexes)
    }

    if .FOCUSED in actions {
        if windowData.wasTextContextModified {
            windowData.currentFileSearchTermIndex = 0
            strings.builder_reset(&windowData.fileSearchStr)

            strings.write_string(&windowData.fileSearchStr, strings.to_string(windowData.uiTextInputCtx.text))
        }

        if windowData.foundTermsCount > 0 && .ENTER in inputState.wasPressedKeys {
            if isShiftPressed() {
                windowData.currentFileSearchTermIndex -= 1
                if windowData.currentFileSearchTermIndex <= -1 {
                    windowData.currentFileSearchTermIndex = i32(len(windowData.foundTermsIndexes)) - 1
                }
            } else {
                windowData.currentFileSearchTermIndex = (windowData.currentFileSearchTermIndex + 1) % i32(len(windowData.foundTermsIndexes))
            }

            tabTextCtx := getActiveTabContext() 

            tabTextCtx.editorState.selection = {
                windowData.foundTermsIndexes[windowData.currentFileSearchTermIndex],
                windowData.foundTermsIndexes[windowData.currentFileSearchTermIndex],
            }
            updateCusrorData(tabTextCtx)
            jumpToCursor(tabTextCtx)
        }
    }

    renderFoundSearchTerms(windowData.foundTermsIndexes[:], strings.to_string(windowData.fileSearchStr))
}

renderFoundSearchTerms :: proc(indexes: []int, serchTerm: string) {
    ctx := getActiveTab().ctx
    textToSearch := strings.to_string(ctx.text)

    serchTermLength := i32(len(serchTerm))

    editableRectSize := ui.getRectSize(ctx.rect)
    maxLinesOnScreen := editableRectSize.y / i32(windowData.font.lineHeight)

    topLine := i32(ctx.lineIndex)
    bottomLine := min(topLine + maxLinesOnScreen, i32(len(ctx.lines)) - 1)

    firstFoundIndex: i32 = -1
    lastFoundIndex: i32 = -1

    for i, index in indexes {
        if i32(i) >= ctx.lines[topLine].x {
            firstFoundIndex = i32(index)
            break
        }
    }

    #reverse for i, index in indexes {
        if i32(i) < ctx.lines[bottomLine].y {
            lastFoundIndex = i32(index)
            break
        }
    }

    if firstFoundIndex == -1 || lastFoundIndex == -1 { return }

    for byteIndex in ctx.glyphsLocations {
        if has, index := any_of_with_index(indexes[firstFoundIndex:lastFoundIndex + 1], int(byteIndex)); has {
            initLocation := ctx.glyphsLocations[byteIndex]

            size: f32 = 0.0
            byteIndex := byteIndex
            for _ in 0..<serchTermLength {
                char, charSize := utf8.decode_rune(textToSearch[byteIndex:])
                defer byteIndex += i32(charSize)
                fontChar := getFontChar(&windowData.font, char)

                size += fontChar.xAdvance
            }

            if int(firstFoundIndex) + index == int(windowData.currentFileSearchTermIndex) {
                renderRectBorder(ui.toRect(int2{ i32(initLocation.position.x), initLocation.lineStart }, 
                    int2{ i32(size), i32(windowData.font.lineHeight) }), 1, windowData.uiContext.zIndex, RED_COLOR)
            } else {
                renderRectBorder(ui.toRect(int2{ i32(initLocation.position.x), initLocation.lineStart }, 
                    int2{ i32(size), i32(windowData.font.lineHeight) }), 1, windowData.uiContext.zIndex, BLACK_COLOR)
            }
        }
    }
}

@(require_results)
any_of_with_index :: proc(s: $S/[]$T, value: T) -> (bool, int) where intrinsics.type_is_comparable(T) {
	for v, i in s {
		if v == value {
			return true, i
		}
	}
	return false, -1
}

count_with_indexes :: proc(s, substr: string, indexes_list: ^[dynamic]int) -> (res: int) {
    clear(indexes_list)
    // indexes_list := make([dynamic]int, allocator)

	if len(substr) == 0 { // special case
		return 0
	}

	if len(substr) == 1 {
		c := substr[0]
		switch len(s) {
		case 0:
			return 0
		case 1:
			return int(s[0] == c)
		}
		n := 0
		for i := 0; i < len(s); i += 1 {
			if s[i] == c {
				n += 1
                append(indexes_list, i)
			}
		}
		return n
	}

	// TODO(bill): Use a non-brute for approach
	n := 0
	str := s
    c := 0
	for {
		i := strings.index(str, substr)
		if i == -1 {
			return n
		}
		n += 1
        append(indexes_list, i + c)
		str = str[i+len(substr):]
        c += i+len(substr)
	}
	return n
}