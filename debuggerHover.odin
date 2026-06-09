package main

import "core:fmt"
import "core:sync"
import "core:strings"

import "ui"

// Visual-Studio-style DataTip: while the debuggee is paused, hovering a variable in the editor shows
// its current value in a small tooltip. The value comes from the locals snapshot taken at the stop
// (windowData.debuggerLocals), matched by the identifier under the mouse. Call this last so the
// tooltip sits above the editor and panels.
renderDebuggerHover :: proc() {
    if windowData.debuggerThread == nil { return }
    if !sync.atomic_load(&windowData.debuggerPaused) { return } // values are only valid while stopped
    if windowData.isFileSearchOpen { return }

    ctx := getActiveTabContext()
    if ctx == nil { return }

    // Only when the mouse is over the editor's text area.
    mouseDX := ui.screenToDirectXCoords(inputState.mousePosition, &windowData.uiContext)
    if mouseDX.x < ctx.rect.left || mouseDX.x > ctx.rect.right ||
        mouseDX.y > ctx.rect.top || mouseDX.y < ctx.rect.bottom { return }

    word := identifierAtMouse(ctx, inputState.mousePosition)
    if word == "" { return }

    value, found := findDebuggerLocalValue(word)
    if !found { return }

    renderDebuggerTooltip(mouseDX, fmt.tprintf("%s = %s", word, value))
}

@(private = "file")
isIdentifierByte :: proc(b: u8) -> bool {
    return b == '_' || (b >= '0' && b <= '9') || (b >= 'a' && b <= 'z') || (b >= 'A' && b <= 'Z')
}

// The C-identifier ([A-Za-z_][A-Za-z0-9_]*) under the mouse in `ctx`, or "" if none.
identifierAtMouse :: proc(ctx: ^EditableTextContext, mouseClient: int2) -> string {
    text := strings.to_string(ctx.text)
    if len(text) == 0 || len(ctx.lines) == 0 { return "" }

    // Reject hovers above the first / below the last text line: getCursorIndexByMousePosition clamps
    // to an edge line, which would match a word that isn't actually under the cursor.
    mouseDX := ui.screenToDirectXCoords(mouseClient, &windowData.uiContext)
    lineF := f32(ctx.rect.top - mouseDX.y) / windowData.font.lineHeight + ctx.lineIndex
    if lineF < 0 || i32(lineF) >= i32(len(ctx.lines)) { return "" }

    idx := getCursorIndexByMousePosition(ctx, mouseClient)
    if idx < 0 { return "" }

    // getCursorIndexByMousePosition returns an insertion point; the hovered glyph is at idx or idx-1.
    if idx >= len(text) || !isIdentifierByte(text[idx]) {
        if idx == 0 || !isIdentifierByte(text[idx - 1]) { return "" }
        idx -= 1
    }

    start := idx
    for start > 0 && isIdentifierByte(text[start - 1]) { start -= 1 }
    end := idx
    for end < len(text) && isIdentifierByte(text[end]) { end += 1 }

    word := text[start:end]
    if len(word) == 0 || (word[0] >= '0' && word[0] <= '9') { return "" } // identifiers don't start with a digit
    return word
}

// Current value of `name` among the locals captured at the last stop. The value is copied into the
// temp allocator so it stays valid for this frame without holding the lock during rendering.
findDebuggerLocalValue :: proc(name: string) -> (string, bool) {
    sync.mutex_lock(&windowData.debuggerLocalsMutex)
    defer sync.mutex_unlock(&windowData.debuggerLocalsMutex)

    for v in windowData.debuggerLocals {
        if v.name == name {
            return strings.clone(v.value, context.temp_allocator), true
        }
    }
    return "", false
}

// Draws the tooltip box + text just below-right of the mouse (directX coords), nudged left to stay
// on screen.
renderDebuggerTooltip :: proc(mouseDX: int2, text: string) {
    padding := int2{ 8, 4 }
    boxW := i32(getTextWidth(text, &windowData.font)) + padding.x * 2
    boxH := i32(getTextHeight(&windowData.font)) + padding.y * 2

    top := mouseDX.y - 10 // a little below the cursor
    left := mouseDX.x + 12
    rect := ui.Rect{ top = top, bottom = top - boxH, left = left, right = left + boxW }

    // keep the tooltip inside the window's right edge
    rightLimit := windowData.size.x / 2 - 5
    if rect.right > rightLimit {
        shift := rect.right - rightLimit
        rect.left -= shift
        rect.right -= shift
    }

    ui.pushCommand(&windowData.uiContext, ui.RectCommand{ rect = rect, bgColor = DARKER_GRAY_COLOR })
    ui.pushCommand(&windowData.uiContext, ui.BorderRectCommand{ rect = rect, color = THEME_COLOR_2, thikness = 1 })
    ui.renderLabel(&windowData.uiContext, ui.Label{
        text = text,
        position = { rect.left + padding.x, rect.bottom + padding.y },
        color = WHITE_COLOR,
    })
}
