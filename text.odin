package main

import "ui"
import "core:strings"
import "core:unicode/utf8"
import "core:text/edit"

/*
    It seeems that for wrapping and non wrapping there should be 2 different algorithms
    Each algorithm consits of 2 parts:
    1. Aproximate vertical and horizontal scrolls size and current position
    2. Draw text based on the position in the file (position should be calculated based on scrolls positions)

    First, let's implement non-wrapping algorithm.

    NON-WRAPPING
    SCROLL

    It seems there are 2 options
    heuristic vs precise approaches (and their combination)

    heuristic algorithm:
    1. Calculate average length of any n lines
    2. 

    1. Pick any char by index

*/

createEmptyTextContext :: proc(initText := "") -> ^EditableTextContext {
    ctx := new(EditableTextContext)
    ctx.text = strings.builder_make(0)
    ctx.rect = ui.Rect{
        top = windowData.size.y / 2 - windowData.editorPadding.top,
        bottom = -windowData.size.y / 2 + windowData.editorPadding.bottom + windowData.debugPanelHeight,
        left = -windowData.size.x / 2 + windowData.editorPadding.left,
        right = windowData.size.x / 2 - windowData.editorPadding.right,
    }

    edit.init(&ctx.editorState, context.allocator, context.allocator)
    edit.setup_once(&ctx.editorState, &ctx.text)
    ctx.editorState.selection = { 0, 0 }

    ctx.editorState.set_clipboard = putTextIntoClipboard
    ctx.editorState.get_clipboard = getTextFromClipboard
    ctx.editorState.clipboard_user_data = &windowData.parentHwnd

    if len(initText) > 0 {
        strings.write_string(&ctx.text, initText)
    }

    return ctx
}

freeTextContext :: proc(ctx: ^EditableTextContext, freeContext := true) {
    delete(ctx.lines)
    delete(ctx.prevText)
    delete(ctx.glyphsLocations)
    edit.destroy(&ctx.editorState)
    strings.builder_destroy(&ctx.text)
    if freeContext {
        free(ctx)
    }
}

getCursorIndexByMousePosition :: proc(ctx: ^EditableTextContext, clientPosition: int2) -> int {
    stringToRender := strings.to_string(ctx.text)

    mousePosition := ui.screenToDirectXCoords(clientPosition, &windowData.uiContext)

    mousePosition = {
        mousePosition.x - ctx.rect.left + ctx.leftOffset,
        ctx.rect.top - mousePosition.y,
    }

    lineIndex := i32(f32(mousePosition.y) / windowData.font.lineHeight + ctx.lineIndex)
    
    // if user clicks lower on the screen where text was rendered take last line
    lineIndex = min(i32(len(ctx.lines) - 1), lineIndex)
    
    //TODO: it's a tmp fix, find something better
    if lineIndex <= -1 { return 0 }

    fromByte := ctx.lines[lineIndex].x
    toByte := ctx.lines[lineIndex].y
    
    cursor: f32 = 0.0
    for byteIndex := fromByte; byteIndex < toByte; {
        char, charSize := utf8.decode_rune(stringToRender[byteIndex:])
        defer byteIndex += i32(charSize)
        
        fontChar := getFontChar(&windowData.font, char)
        
        if f32(mousePosition.x) < cursor {
            return int(byteIndex)
        }

        cursor += fontChar.xAdvance
    }

    // if no glyph found move the cursor to the last glyph
    return int(toByte)
}

updateCusrorData :: proc(ctx: ^EditableTextContext) {
    if ctx == nil { return }

    // find cursor line
    ctx.cursorLineIndex = 0
    cursorLine: int2 = { 0, 0 }
    cursorIndex := i32(ctx.editorState.selection[0])

    // find current cursor line index (binary search, lines are byte-sorted and contiguous)
    if len(ctx.lines) > 0 {
        lineIndex := findLineByByteOffset(ctx.lines[:], cursorIndex)
        line := ctx.lines[lineIndex]
        ctx.cursorLineIndex = lineIndex
        cursorLine = line
        ctx.editorState.line_start = int(line.x)
        ctx.editorState.line_end = int(line.y)
    }

    // find cursor left offset
    ctx.cursorLeftOffset = 0.0
    stringToRender := strings.to_string(ctx.text)
    charIndex := cursorLine.x
    for charIndex < cursorLine.y {
        char, charSize := utf8.decode_rune(stringToRender[charIndex:])
        defer charIndex += i32(charSize)
        
        if cursorIndex == charIndex { break }

        fontChar := getFontChar(&windowData.font, char)
        ctx.cursorLeftOffset += fontChar.xAdvance
    }

    cursorLineIndex := ctx.cursorLineIndex

    // calculate line above cursor position if user clicks UP
    if cursorLineIndex > 0 {
        previousLine := ctx.lines[cursorLineIndex - 1]

        ctx.editorState.up_index = int(previousLine.y)

        charIndex = previousLine.x
        leftOffset: f32 = 0.0
        for charIndex < previousLine.y {
            char, charSize := utf8.decode_rune(stringToRender[charIndex:])
            defer charIndex += i32(charSize)
            
            fontChar := getFontChar(&windowData.font, char)
            leftOffset += fontChar.xAdvance
            if leftOffset > ctx.cursorLeftOffset {
                ctx.editorState.up_index = int(charIndex)
                break
            }
        }
    } else {
        ctx.editorState.up_index = ctx.editorState.selection[0]
    }

    // calculate line below cursor position if user clicks DOWN
    if cursorLineIndex < i32(len(ctx.lines) - 1) {
        nextLine := ctx.lines[cursorLineIndex + 1]

        ctx.editorState.down_index = int(nextLine.y)

        charIndex = nextLine.x
        leftOffset: f32 = 0.0
        for charIndex < nextLine.y {
            char, charSize := utf8.decode_rune(stringToRender[charIndex:])
            defer charIndex += i32(charSize)
            
            fontChar := getFontChar(&windowData.font, char)
            leftOffset += fontChar.xAdvance
            if leftOffset > ctx.cursorLeftOffset {
                ctx.editorState.down_index = int(charIndex)
                break
            }
        }
    } else {
        ctx.editorState.down_index = ctx.editorState.selection[0]
    }
}

validateTopLine :: proc(ctx: ^EditableTextContext) {
    if ctx == nil { return }

    ctx.lineIndex = max(0.0, ctx.lineIndex)
    ctx.lineIndex = min(f32(len(ctx.lines) - 1), ctx.lineIndex)
}

validateLeftOffset :: proc(ctx: ^EditableTextContext) {
    if ctx == nil { return }

    if ctx.leftOffset < 0.0 {
        ctx.leftOffset = 0.0
    } else if ctx.leftOffset + ui.getRectSize(ctx.rect).x > i32(ctx.maxLineWidth) {
        ctx.leftOffset = i32(ctx.maxLineWidth) - ui.getRectSize(ctx.rect).x
    }
}

jumpToCursor :: proc(ctx: ^EditableTextContext) {
    if ctx == nil { return }
    
    maxLinesOnScreen := i32(f32(getEditorSize().y) / windowData.font.lineHeight)

    if ctx.cursorLineIndex < i32(ctx.lineIndex) {
        ctx.lineIndex = f32(ctx.cursorLineIndex)
    } else if ctx.cursorLineIndex >= i32(ctx.lineIndex) + maxLinesOnScreen {
        ctx.lineIndex = f32(ctx.cursorLineIndex - maxLinesOnScreen + 1)
    }

    if ctx.leftOffset > i32(ctx.cursorLeftOffset) {
        ctx.leftOffset = i32(ctx.cursorLeftOffset)
    } else if ctx.leftOffset < i32(ctx.cursorLeftOffset) - ui.getRectSize(ctx.rect).x {
        ctx.leftOffset = i32(ctx.cursorLeftOffset) - ui.getRectSize(ctx.rect).x
    }
}

selectWholeWord :: proc(ctx: ^EditableTextContext, cursorIndex: i32) {
    ctx.editorState.selection[0] = int(cursorIndex)

    ctx.editorState.selection = {
        edit.translate_position(&ctx.editorState, .Word_End),
        edit.translate_position(&ctx.editorState, .Word_Start),
    }
}

fillGlyphsLocations :: proc(ctx: ^EditableTextContext) {
    clear(&ctx.glyphsLocations)
    
    screenPosition := float2{ f32(ctx.rect.left), f32(ctx.rect.top) - windowData.font.ascent }
    screenPosition.y += getDecimalPart(ctx.lineIndex) * windowData.font.lineHeight

    editableRectSize := ui.getRectSize(ctx.rect)
    maxLinesOnScreen := editableRectSize.y / i32(windowData.font.lineHeight)

    topLine := i32(ctx.lineIndex)
    bottomLine := min(topLine + maxLinesOnScreen + 2, i32(len(ctx.lines)))
    text := strings.to_string(ctx.text)

    for lineIndex in topLine..<bottomLine {
        line := ctx.lines[lineIndex]

        lineLeftOffset: f32 = 0.0
        charIndex := line.x
        for char, index in text[line.x : line.y] {
            charIndex = i32(index) + line.x
            fontChar := getFontChar(&windowData.font, char)

            screenPosition.x = f32(ctx.rect.left) + lineLeftOffset - f32(ctx.leftOffset)
            
            lineLeftOffset += fontChar.xAdvance

            if lineLeftOffset < f32(ctx.leftOffset) { // don't render glyphs until their position is inside visible region 
                continue 
            }

            glyphSize := fontChar.size
            glyphPosition: float2 = { screenPosition.x + fontChar.offset.x, screenPosition.y - glyphSize.y - fontChar.offset.y }

            ctx.glyphsLocations[charIndex] = GlyphsLocation{
                position = glyphPosition,
                lineStart = i32(screenPosition.y + windowData.font.descent),
                size = glyphSize,
                char = char,
            }
            
            if lineLeftOffset > f32(ctx.leftOffset + editableRectSize.x) { // stop line rendering if outside of line rigth boundary
                break 
            }
        }
        screenPosition.y -= windowData.font.lineHeight
    }
}

// Locate the line containing byte `offset`: the first line whose end byte is >= offset.
// Lines are sorted by byte offset and contiguous, so this resolves the line exactly.
findLineByByteOffset :: proc(lines: []int2, offset: i32) -> i32 {
    if len(lines) == 0 { return 0 }
    lo, hi := 0, len(lines) - 1
    for lo < hi {
        mid := (lo + hi) / 2
        if lines[mid].y < offset {
            lo = mid + 1
        } else {
            hi = mid
        }
    }
    return i32(lo)
}

measureLineWidth :: proc(text: string, line: int2) -> f32 {
    width: f32 = 0.0
    for char in text[line.x:line.y] {
        width += getFontChar(&windowData.font, char).xAdvance
    }
    return width
}

// Recompute line boundaries after an edit. In the common case (no word-wrapping) only the
// region that actually changed is re-split: lines before it are untouched and lines after it
// only have their byte offsets shifted, so a keystroke no longer rescans the whole document
// (with a glyph-width lookup per character). Falls back to a full rebuild for word-wrapping,
// the first layout, or a rect resize.
calculateLines :: proc(ctx: ^EditableTextContext) {
    if ctx == nil { return }

    text := strings.to_string(ctx.text)
    newLen := i32(len(text))
    rectWidth := ui.getRectSize(ctx.rect).x

    if !windowData.wordWrapping &&
       len(ctx.lines) > 0 &&
       len(ctx.prevText) > 0 &&
       ctx.prevRectWidth == rectWidth {
        calculateLinesIncremental(ctx, text, newLen)
    } else {
        calculateLinesFull(ctx)
    }

    // Snapshot the text/rect so the next edit can be diffed against it.
    resize(&ctx.prevText, int(newLen))
    if newLen > 0 {
        copy(ctx.prevText[:], text)
    }
    ctx.prevRectWidth = rectWidth
}

@(private="file")
calculateLinesIncremental :: proc(ctx: ^EditableTextContext, text: string, newLen: i32) {
    old := string(ctx.prevText[:])
    oldLen := i32(len(old))

    // Minimal changed span: skip the common prefix and suffix. Any diff that reproduces
    // `text` yields the same layout, so the editor's exact edit need not be known.
    minLen := min(oldLen, newLen)
    p: i32 = 0
    for p < minLen && old[p] == text[p] { p += 1 }
    sfx: i32 = 0
    for sfx < minLen - p && old[oldLen - 1 - sfx] == text[newLen - 1 - sfx] { sfx += 1 }

    delta := newLen - oldLen
    oldChangedEnd := oldLen - sfx

    // The old lines [firstLine, lastLine] cover the change; only these get rebuilt.
    firstLine := findLineByByteOffset(ctx.lines[:], p)
    lastLine := findLineByByteOffset(ctx.lines[:], oldChangedEnd)

    scanStart := ctx.lines[firstLine].x
    scanEnd := ctx.lines[lastLine].y + delta // end of the rebuilt region, in NEW coordinates

    // Re-split the changed region of the new text on '\n'.
    middle: [dynamic]int2
    defer delete(middle)
    lineStart := scanStart
    for lineStart <= scanEnd {
        rel := strings.index_byte(text[lineStart:scanEnd], '\n')
        if rel < 0 {
            append(&middle, int2{ lineStart, scanEnd })
            break
        }
        nlPos := lineStart + i32(rel)
        append(&middle, int2{ lineStart, nlPos })
        lineStart = nlPos + 1
    }

    // Splice ctx.lines = [0, firstLine) ++ middle ++ shift(ctx.lines[lastLine+1:], delta).
    tailStart := lastLine + 1
    tailCount := i32(len(ctx.lines)) - tailStart
    newMiddleCount := i32(len(middle))
    newTailStart := firstLine + newMiddleCount
    newTotal := newTailStart + tailCount

    if newTotal > i32(len(ctx.lines)) {
        resize(&ctx.lines, int(newTotal))
    }
    if newTailStart > tailStart { // tail moves right: copy backwards to avoid clobbering
        for k := tailCount - 1; k >= 0; k -= 1 {
            ctx.lines[newTailStart + k] = ctx.lines[tailStart + k]
        }
    } else if newTailStart < tailStart { // tail moves left: copy forwards
        for k: i32 = 0; k < tailCount; k += 1 {
            ctx.lines[newTailStart + k] = ctx.lines[tailStart + k]
        }
    }
    for k: i32 = 0; k < tailCount; k += 1 {
        ctx.lines[newTailStart + k].x += delta
        ctx.lines[newTailStart + k].y += delta
    }
    for k: i32 = 0; k < newMiddleCount; k += 1 {
        ctx.lines[firstLine + k] = middle[k]
    }
    if newTotal < i32(len(ctx.lines)) {
        resize(&ctx.lines, int(newTotal))
    }

    // maxLineWidth is grow-only here (re-measuring every line would reintroduce the
    // per-character cost). The exact value is restored by the full rebuild on resize.
    for line in middle {
        width := measureLineWidth(text, line)
        if width > ctx.maxLineWidth { ctx.maxLineWidth = width }
    }
}

@(private="file")
calculateLinesFull :: proc(ctx: ^EditableTextContext) {
    if ctx == nil { return }

    clear(&ctx.lines)
    stringToRender := strings.to_string(ctx.text)
    stringLength := len(stringToRender)
 
    cursor: f32 = 0.0

    lineWidth := f32(ui.getRectSize(ctx.rect).x)
    lineBoundaryIndexes: int2 = { 0, 0 }
    ctx.maxLineWidth = -1.0
    
    for charIndex := 0; charIndex < stringLength; {
        char, charSize := utf8.decode_rune(stringToRender[charIndex:])
        defer charIndex += charSize

        if char == '\n' {
            cursor = 0.0
            
            lineBoundaryIndexes.y = i32(charIndex)
            append(&ctx.lines, lineBoundaryIndexes)
            lineBoundaryIndexes.x = lineBoundaryIndexes.y + i32(charSize)
            continue 
        }

        fontChar := getFontChar(&windowData.font, char)
        cursor += fontChar.xAdvance

        // text wrapping
        // TODO: make two functions, 1 - with wrapping, 2 - no wrapping, to avoid additional check
        if windowData.wordWrapping {
            if cursor >= lineWidth {
                // The current char overflows, so it starts the next visual line:
                // end this line right before it (exclusive end == its start byte) and
                // carry its width over. The old code stepped back by the *current*
                // char's size, which dropped the last fitting char and broke on
                // variable-width UTF-8.
                lineBoundaryIndexes.y = i32(charIndex)
                append(&ctx.lines, lineBoundaryIndexes)
                lineBoundaryIndexes.x = i32(charIndex)
                cursor = fontChar.xAdvance
            }
        } else {
            // TODO: make two functions, 1 - with wrapping, 2 - no wrapping, to avoid additional check
            // maxLineWidth makes sense only if in word wrapping is off
            if cursor >= ctx.maxLineWidth {
                ctx.maxLineWidth = cursor
            }
        }
    }
    
    lineBoundaryIndexes.y = i32(stringLength)
    append(&ctx.lines, lineBoundaryIndexes)
}
