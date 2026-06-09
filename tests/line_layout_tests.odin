package tests

import "core:strings"
import "core:testing"
import "core:slice"

import main "../"

// These are pure-function tests for the line/glyph layout fixes. They don't start the
// app or send input: they build a minimal EditableTextContext, install a deterministic
// monospace font into the global, and call the layout procs directly. The test runner
// is single-threaded (see run_tests.bat) so mutating the global font is safe here.

// Give every ASCII glyph the same advance so wrap/offset math is fully predictable.
setupMonospaceFont :: proc(advance: f32 = 10) {
    for i in 0..<128 {
        main.windowData.font.asciiChars[i] = main.FontChar{ xAdvance = advance }
    }
}

makeTestContext :: proc(initText: string) -> main.EditableTextContext {
    ctx: main.EditableTextContext
    ctx.text = strings.builder_make()
    strings.write_string(&ctx.text, initText)
    return ctx
}

destroyTestContext :: proc(ctx: ^main.EditableTextContext) {
    delete(ctx.lines)
    delete(ctx.prevText)
    delete(ctx.glyphsLocations)
    strings.builder_destroy(&ctx.text)
}

// Concatenate every visual line slice. With no newlines in the source this must equal
// the original text, i.e. layout dropped no glyphs.
assembleLines :: proc(ctx: ^main.EditableTextContext) -> string {
    sb := strings.builder_make()
    text := strings.to_string(ctx.text)
    for line in ctx.lines {
        strings.write_string(&sb, text[line.x:line.y])
    }
    return strings.to_string(sb)
}

// --- calculateLines: non-wrapping splits purely on newlines -------------------------

@(test)
calculate_lines_splits_on_newlines :: proc(t: ^testing.T) {
    setupMonospaceFont()
    main.windowData.wordWrapping = false

    // bytes: a0 b1 \n2 c3 d4 e5 \n6 f7  (len 8)
    ctx := makeTestContext("ab\ncde\nf")
    defer destroyTestContext(&ctx)

    main.calculateLines(&ctx)

    testing.expect_value(t, len(ctx.lines), 3)
    testing.expect_value(t, ctx.lines[0], main.int2{0, 2}) // "ab"
    testing.expect_value(t, ctx.lines[1], main.int2{3, 6}) // "cde"
    testing.expect_value(t, ctx.lines[2], main.int2{7, 8}) // "f"
}

// --- calculateLines: word wrapping must not drop the char that triggers the wrap ----
// Regression test for the bug where the line ended at `charIndex - charSize`, which
// dropped the last glyph that fit on each wrapped line (and broke variable-width UTF-8).

@(test)
calculate_lines_wrapping_keeps_all_characters :: proc(t: ^testing.T) {
    setupMonospaceFont(10) // every glyph is 10px wide
    main.windowData.wordWrapping = true

    text := "abcdefgh"
    ctx := makeTestContext(text)
    // 35px wide editor with 10px glyphs -> 3 fit per line, the 4th wraps.
    ctx.rect.left = 0
    ctx.rect.right = 35
    ctx.rect.top = 100
    ctx.rect.bottom = 0
    defer destroyTestContext(&ctx)

    main.calculateLines(&ctx)

    testing.expect_value(t, len(ctx.lines), 3)
    testing.expect_value(t, ctx.lines[0], main.int2{0, 3}) // "abc"
    testing.expect_value(t, ctx.lines[1], main.int2{3, 6}) // "def"
    testing.expect_value(t, ctx.lines[2], main.int2{6, 8}) // "gh"

    // The whole text must be recoverable from the line slices (old code lost 'c' and 'g').
    assembled := assembleLines(&ctx)
    defer delete(assembled)
    testing.expect_value(t, assembled, text)
}

// Word wrapping also reads the rect from the passed ctx, not the active tab. A zero-width
// rect must not crash or wrap into an empty/huge line list; every char goes on its own line.
@(test)
calculate_lines_wrapping_uses_ctx_rect :: proc(t: ^testing.T) {
    setupMonospaceFont(10)
    main.windowData.wordWrapping = true

    text := "abc"
    ctx := makeTestContext(text)
    ctx.rect.left = 0
    ctx.rect.right = 5 // narrower than a single glyph -> each char wraps onto its own line
    ctx.rect.top = 100
    ctx.rect.bottom = 0
    defer destroyTestContext(&ctx)

    main.calculateLines(&ctx)

    assembled := assembleLines(&ctx)
    defer delete(assembled)
    testing.expect_value(t, assembled, text) // still no dropped characters
}

// --- updateCusrorData: binary search resolves the cursor's line ---------------------

@(test)
cursor_line_lookup_finds_correct_line :: proc(t: ^testing.T) {
    setupMonospaceFont()
    main.windowData.wordWrapping = false

    ctx := makeTestContext("ab\ncde\nf") // lines: {0,2}, {3,6}, {7,8}
    defer destroyTestContext(&ctx)
    main.calculateLines(&ctx)

    Case :: struct { cursor: int, line: i32, start, end: int }
    cases := []Case{
        { 0, 0, 0, 2 }, // start of buffer
        { 2, 0, 0, 2 }, // end of line 0 (right before the newline)
        { 3, 1, 3, 6 }, // start of line 1 (right after the newline)
        { 5, 1, 3, 6 }, // middle of line 1
        { 6, 1, 3, 6 }, // end of line 1
        { 7, 2, 7, 8 }, // start of the last line
        { 8, 2, 7, 8 }, // end of buffer
    }

    for c in cases {
        ctx.editorState.selection[0] = c.cursor
        main.updateCusrorData(&ctx)

        testing.expectf(t, ctx.cursorLineIndex == c.line,
            "cursor %d: expected line %d, got %d", c.cursor, c.line, ctx.cursorLineIndex)
        testing.expect_value(t, ctx.editorState.line_start, c.start)
        testing.expect_value(t, ctx.editorState.line_end, c.end)
    }
}

// --- getFontChar: ASCII fast path mirrors the map, non-ASCII falls back -------------

@(test)
get_font_char_matches_map :: proc(t: ^testing.T) {
    main.windowData.font.chars = make(map[rune]main.FontChar)
    defer delete(main.windowData.font.chars)
    main.windowData.font.asciiChars = {}

    // Baking keeps both tables in sync for ASCII; the fast path must return that value.
    main.windowData.font.chars['A'] = main.FontChar{ xAdvance = 11 }
    main.windowData.font.asciiChars['A'] = main.FontChar{ xAdvance = 11 }

    // Non-ASCII glyphs live only in the map, so getFontChar must fall back to it.
    nonAscii := rune(0x00E9) // 'é'
    main.windowData.font.chars[nonAscii] = main.FontChar{ xAdvance = 13 }

    testing.expect_value(t, main.getFontChar(&main.windowData.font, 'A').xAdvance, f32(11))
    testing.expect_value(t, main.getFontChar(&main.windowData.font, nonAscii).xAdvance, f32(13))
    // An unbaked ASCII slot returns the zero glyph, identical to a map miss.
    testing.expect_value(t, main.getFontChar(&main.windowData.font, rune(0x01)).xAdvance, f32(0))
}

// --- incremental relayout must always agree with a full rebuild ---------------------
// Property test: apply thousands of random inserts/deletes and assert that the
// incrementally-maintained ctx.lines is byte-for-byte identical to a from-scratch full
// relayout of the same text. ASCII-only edits keep every byte offset a valid boundary.

@(test)
incremental_matches_full_relayout :: proc(t: ^testing.T) {
    setupMonospaceFont()
    main.windowData.wordWrapping = false

    ctx := makeTestContext("")
    ctx.rect.left = 0
    ctx.rect.right = 100000
    ctx.rect.top = 100
    ctx.rect.bottom = 0
    defer destroyTestContext(&ctx)

    main.calculateLines(&ctx) // first layout is full; seeds the diff snapshot

    nextRand :: proc(s: ^u64) -> u64 {
        s^ = s^ * 6364136223846793005 + 1442695040888963407
        return s^ >> 33
    }
    rng: u64 = 0x2545F4914F6CDD1D

    alphabet := "abc \n\t\nde\nf" // newlines/tab/space exercise line splits and merges

    for iter in 0..<3000 {
        textLen := len(ctx.text.buf)

        if textLen == 0 || nextRand(&rng) % 5 < 3 { // bias towards growth
            pos := int(nextRand(&rng) % u64(textLen + 1))
            ch := alphabet[int(nextRand(&rng) % u64(len(alphabet)))]
            inject_at(&ctx.text.buf, pos, ch)
        } else {
            pos := int(nextRand(&rng) % u64(textLen))
            hi := min(pos + 1 + int(nextRand(&rng) % 3), textLen) // delete 1..3 bytes
            remove_range(&ctx.text.buf, pos, hi)
        }

        main.calculateLines(&ctx) // incremental

        // Reference: full relayout of an independent context holding the same text.
        ref := makeTestContext(strings.to_string(ctx.text))
        main.calculateLines(&ref) // full (fresh context has no snapshot)
        defer destroyTestContext(&ref)

        if !slice.equal(ctx.lines[:], ref.lines[:]) {
            testing.expectf(t, false, "iter %d: lines mismatch for %q\n  incremental=%v\n  full=%v",
                iter, strings.to_string(ctx.text), ctx.lines[:], ref.lines[:])
            return
        }
    }
}

// Undo/redo swaps the whole buffer at once; the prefix/suffix diff must handle a change
// that spans (almost) the entire document, including line-count changes, just as well.
@(test)
incremental_handles_wholesale_replacement :: proc(t: ^testing.T) {
    setupMonospaceFont()
    main.windowData.wordWrapping = false

    ctx := makeTestContext("alpha\nbeta\ngamma")
    ctx.rect.right = 100000
    ctx.rect.top = 100
    defer destroyTestContext(&ctx)
    main.calculateLines(&ctx) // full; snapshot = "alpha\nbeta\ngamma"

    replacements := []string{ "x", "one\ntwo\nthree\nfour", "", "no newlines here", "a\n\n\nb", "alpha\nbeta\ngamma" }
    for repl in replacements {
        strings.builder_reset(&ctx.text)
        strings.write_string(&ctx.text, repl)
        main.calculateLines(&ctx) // incremental, diffed against the previous snapshot

        ref := makeTestContext(repl)
        main.calculateLines(&ref) // full
        defer destroyTestContext(&ref)

        testing.expectf(t, slice.equal(ctx.lines[:], ref.lines[:]),
            "wholesale %q: incremental=%v full=%v", repl, ctx.lines[:], ref.lines[:])
    }
}
