package tests

import "base:intrinsics"
import "core:testing"
import "core:strings"
import "core:os"
import "core:time"
import "core:sync"

import win32 "core:sys/windows"

import main "../"

// @(test)
// type_and_save :: proc(t: ^testing.T) {
//     appThread, windowData := startApp(proc(windowData: ^main.WindowData) -> bool {
//         return windowData.windowCreated
//     })
    
//     time.sleep(1_000_0000000)
//     defer stopApp(appThread, windowData.parentHwnd)
// }

@(test)
just_run_and_close :: proc(t: ^testing.T) {
    os.remove(main.editorStateFilePath)

    appThread, windowData := startApp(proc(windowData: ^main.WindowData) -> bool {
        return windowData.windowCreated
    })
    defer stopApp(appThread, windowData.parentHwnd)

    text := "all work and no play makes jack a dull boy yeah"

    typeStringOnKeyboard(windowData.parentHwnd, text)

    testing.expect_value(t, strings.to_string(main.getActiveTabContext().text), text)
}

// Clicking each debug-panel control button dispatches its own command. This is also the regression
// test for the id-collision bug: when the four buttons shared a #caller_location-derived id they all
// reported `hot`/SUBMIT together, so every click set the last button's command (Step out).
@(test)
debug_panel_buttons_dispatch_commands :: proc(t: ^testing.T) {
    os.remove(main.editorStateFilePath)

    appThread, windowData := startApp(proc(windowData: ^main.WindowData) -> bool {
        return windowData.windowCreated
    })
    defer stopApp(appThread, windowData.parentHwnd)

    // Show the docked panel without launching a real debuggee: the buttons render and stay clickable,
    // and with no debug loop running nothing consumes the command we're asserting.
    sync.atomic_store(&windowData.debugPanelForceVisible, true)
    time.sleep(200_000_000) // let a few frames render and lay the panel out

    Case :: struct { index: i32, expected: main.DebuggerCommand }
    cases := []Case{
        { 0, .CONTINUE },
        { 1, .STEP_OVER },
        { 2, .STEP_INTO },
        { 3, .STEP_OUT },
        { 4, .STEP_INSTRUCTION },
    }

    for c in cases {
        sync.atomic_store(&windowData.debuggerCommand, .NONE)

        clickDebugButton(windowData.parentHwnd, c.index)

        testing.expect_value(t, sync.atomic_load(&windowData.debuggerCommand), c.expected)
    }
}

@(test)
basic_file_search :: proc(t: ^testing.T) {
    os.remove(main.editorStateFilePath)

    appThread, windowData := startApp(proc(windowData: ^main.WindowData) -> bool {
        return windowData.windowCreated
    })
    defer stopApp(appThread, windowData.parentHwnd)

    time.sleep(200_000_000)

    text := "all work and no play makes jack a dull boy. work"

    typeStringOnKeyboard(windowData.parentHwnd, text)

    clickCtrlF()

    time.sleep(100_000_000)
    testing.expect(t, sync.atomic_load(&windowData.isFileSearchOpen))

    typeStringOnKeyboard(windowData.parentHwnd, "work")

    clickEnter()
    testing.expect_value(t, 1, int(sync.atomic_load(&windowData.currentFileSearchTermIndex)))

    clickEnter()
    testing.expect_value(t, 0, int(sync.atomic_load(&windowData.currentFileSearchTermIndex)))

    clickEsc()
    testing.expect(t, !sync.atomic_load(&windowData.isFileSearchOpen))
}

// save file, open it again, should be only one tab

@(test)
type_and_save :: proc(t: ^testing.T) {
    os.remove(main.editorStateFilePath)

    fileToSave :: "test1.txt"

    appThread, windowData := startApp(proc(windowData: ^main.WindowData) -> bool {
        return windowData.windowCreated
    })
    defer stopApp(appThread, windowData.parentHwnd)

    text := "all work and no play makes jack a dull boy"

    typeStringOnKeyboard(windowData.parentHwnd, text)

    // time.sleep(1_00_000_000)
    windowRect: win32.RECT
    win32.GetWindowRect(windowData.parentHwnd, &windowRect)

    clickMouse({
        { windowRect.left + 30, windowRect.top + 50 },
        { windowRect.left + 30, windowRect.top + 150 },
    })

    time.sleep(2_000_000_000)

    typeStringOnKeyboard(windowData.parentHwnd, fileToSave)
    clickEnter()
    time.sleep(1_000_000_000)

    tab := main.getActiveTab()

    testing.expect(t, os.is_file(tab.filePath), "file was not created")
    
    saveFileContent, err := os.read_entire_file_from_filename_or_err(tab.filePath)
    testing.expect(t, err == nil, "could not read saved file")
    defer delete(saveFileContent)

    testing.expect_value(t, string(saveFileContent), text)

    os.remove(tab.filePath)
}

// @(test)
just_run_wait_and_close :: proc(t: ^testing.T) {
    os.remove(main.editorStateFilePath)

    appThread, windowData := startApp(proc(windowData: ^main.WindowData) -> bool {
        return windowData.windowCreated
    })
    defer stopApp(appThread, windowData.parentHwnd)

    time.sleep(5_000_000_000)
}

@(test)
type_and_backspace :: proc(t: ^testing.T) {
    os.remove(main.editorStateFilePath)

    appThread, windowData := startApp(proc(windowData: ^main.WindowData) -> bool {
        return windowData.windowCreated
    })
    defer stopApp(appThread, windowData.parentHwnd)

    typeStringOnKeyboard(windowData.parentHwnd, "hello world")

    // remove the trailing "world" (5 characters)
    clickKeyTimes(win32.VK_BACK, 5)
    time.sleep(100_000_000)

    testing.expect_value(t, strings.to_string(main.getActiveTabContext().text), "hello ")
}

@(test)
type_multiple_lines :: proc(t: ^testing.T) {
    os.remove(main.editorStateFilePath)

    appThread, windowData := startApp(proc(windowData: ^main.WindowData) -> bool {
        return windowData.windowCreated
    })
    defer stopApp(appThread, windowData.parentHwnd)

    typeStringOnKeyboard(windowData.parentHwnd, "line one")
    clickEnter()
    typeStringOnKeyboard(windowData.parentHwnd, "line two")
    time.sleep(100_000_000)

    ctx := main.getActiveTabContext()
    testing.expect_value(t, strings.to_string(ctx.text), "line one\nline two")
    testing.expect_value(t, len(ctx.lines), 2)
}

@(test)
select_all_and_delete :: proc(t: ^testing.T) {
    os.remove(main.editorStateFilePath)

    appThread, windowData := startApp(proc(windowData: ^main.WindowData) -> bool {
        return windowData.windowCreated
    })
    defer stopApp(appThread, windowData.parentHwnd)

    typeStringOnKeyboard(windowData.parentHwnd, "delete me please")

    clickCtrlKey(win32.VK_A) // select all
    clickKey(win32.VK_BACK)  // delete the whole selection
    time.sleep(100_000_000)

    testing.expect_value(t, strings.to_string(main.getActiveTabContext().text), "")
}

@(test)
cursor_home_and_end :: proc(t: ^testing.T) {
    os.remove(main.editorStateFilePath)

    appThread, windowData := startApp(proc(windowData: ^main.WindowData) -> bool {
        return windowData.windowCreated
    })
    defer stopApp(appThread, windowData.parentHwnd)

    typeStringOnKeyboard(windowData.parentHwnd, "abcdef")

    clickKey(win32.VK_HOME)
    time.sleep(50_000_000)
    testing.expect_value(t, main.getActiveTabContext().editorState.selection[0], 0)

    clickKey(win32.VK_END)
    time.sleep(50_000_000)
    testing.expect_value(t, main.getActiveTabContext().editorState.selection[0], 6)
}

@(test)
arrow_left_right_navigation :: proc(t: ^testing.T) {
    os.remove(main.editorStateFilePath)

    appThread, windowData := startApp(proc(windowData: ^main.WindowData) -> bool {
        return windowData.windowCreated
    })
    defer stopApp(appThread, windowData.parentHwnd)

    typeStringOnKeyboard(windowData.parentHwnd, "abc") // cursor ends at index 3

    clickKey(win32.VK_LEFT)
    time.sleep(50_000_000)
    testing.expect_value(t, main.getActiveTabContext().editorState.selection[0], 2)

    clickKey(win32.VK_LEFT)
    time.sleep(50_000_000)
    testing.expect_value(t, main.getActiveTabContext().editorState.selection[0], 1)

    clickKey(win32.VK_RIGHT)
    time.sleep(50_000_000)
    testing.expect_value(t, main.getActiveTabContext().editorState.selection[0], 2)
}

@(test)
word_navigation :: proc(t: ^testing.T) {
    os.remove(main.editorStateFilePath)

    appThread, windowData := startApp(proc(windowData: ^main.WindowData) -> bool {
        return windowData.windowCreated
    })
    defer stopApp(appThread, windowData.parentHwnd)

    typeStringOnKeyboard(windowData.parentHwnd, "hello world foo") // cursor ends at index 15

    clickCtrlKey(win32.VK_LEFT) // jump to start of "foo" (index 12)
    time.sleep(50_000_000)
    testing.expect_value(t, main.getActiveTabContext().editorState.selection[0], 12)

    clickCtrlKey(win32.VK_LEFT) // jump to start of "world" (index 6)
    time.sleep(50_000_000)
    testing.expect_value(t, main.getActiveTabContext().editorState.selection[0], 6)
}

@(test)
delete_word_left :: proc(t: ^testing.T) {
    os.remove(main.editorStateFilePath)

    appThread, windowData := startApp(proc(windowData: ^main.WindowData) -> bool {
        return windowData.windowCreated
    })
    defer stopApp(appThread, windowData.parentHwnd)

    typeStringOnKeyboard(windowData.parentHwnd, "hello world")

    clickCtrlKey(win32.VK_BACK) // delete the word to the left of the cursor ("world")
    time.sleep(100_000_000)

    testing.expect_value(t, strings.to_string(main.getActiveTabContext().text), "hello ")
}

@(test)
delete_word_right :: proc(t: ^testing.T) {
    os.remove(main.editorStateFilePath)

    appThread, windowData := startApp(proc(windowData: ^main.WindowData) -> bool {
        return windowData.windowCreated
    })
    defer stopApp(appThread, windowData.parentHwnd)

    typeStringOnKeyboard(windowData.parentHwnd, "hello world")

    clickKey(win32.VK_HOME)       // move the cursor to the start of the line
    clickCtrlKey(win32.VK_DELETE) // delete the word to the right ("hello ")
    time.sleep(100_000_000)

    testing.expect_value(t, strings.to_string(main.getActiveTabContext().text), "world")
}

@(test)
select_to_line_start_and_delete :: proc(t: ^testing.T) {
    os.remove(main.editorStateFilePath)

    appThread, windowData := startApp(proc(windowData: ^main.WindowData) -> bool {
        return windowData.windowCreated
    })
    defer stopApp(appThread, windowData.parentHwnd)

    typeStringOnKeyboard(windowData.parentHwnd, "first")
    clickEnter()
    typeStringOnKeyboard(windowData.parentHwnd, "second")

    clickShiftKey(win32.VK_HOME) // select "second" (from cursor back to line start)
    clickKey(win32.VK_BACK)      // delete the selected text
    time.sleep(100_000_000)

    testing.expect_value(t, strings.to_string(main.getActiveTabContext().text), "first\n")
}

@(test)
select_left_and_replace :: proc(t: ^testing.T) {
    os.remove(main.editorStateFilePath)

    appThread, windowData := startApp(proc(windowData: ^main.WindowData) -> bool {
        return windowData.windowCreated
    })
    defer stopApp(appThread, windowData.parentHwnd)

    typeStringOnKeyboard(windowData.parentHwnd, "abcd")

    clickShiftKey(win32.VK_LEFT) // select "d"
    clickShiftKey(win32.VK_LEFT) // extend selection to "cd"

    typeStringOnKeyboard(windowData.parentHwnd, "z") // typing replaces the selection
    time.sleep(100_000_000)

    testing.expect_value(t, strings.to_string(main.getActiveTabContext().text), "abz")
}

@(test)
tab_inserts_tab_character :: proc(t: ^testing.T) {
    os.remove(main.editorStateFilePath)

    appThread, windowData := startApp(proc(windowData: ^main.WindowData) -> bool {
        return windowData.windowCreated
    })
    defer stopApp(appThread, windowData.parentHwnd)

    typeStringOnKeyboard(windowData.parentHwnd, "ab")
    clickKey(win32.VK_TAB)
    typeStringOnKeyboard(windowData.parentHwnd, "cd")
    time.sleep(100_000_000)

    testing.expect_value(t, strings.to_string(main.getActiveTabContext().text), "ab\tcd")
}

@(test)
new_line_preserves_indentation :: proc(t: ^testing.T) {
    os.remove(main.editorStateFilePath)

    appThread, windowData := startApp(proc(windowData: ^main.WindowData) -> bool {
        return windowData.windowCreated
    })
    defer stopApp(appThread, windowData.parentHwnd)

    // leading whitespace on the current line should be copied to the new line
    typeStringOnKeyboard(windowData.parentHwnd, "  hi")
    clickEnter()
    typeStringOnKeyboard(windowData.parentHwnd, "x")
    time.sleep(100_000_000)

    testing.expect_value(t, strings.to_string(main.getActiveTabContext().text), "  hi\n  x")
}

@(test)
undo_and_redo :: proc(t: ^testing.T) {
    os.remove(main.editorStateFilePath)

    appThread, windowData := startApp(proc(windowData: ^main.WindowData) -> bool {
        return windowData.windowCreated
    })
    defer stopApp(appThread, windowData.parentHwnd)

    typeStringOnKeyboard(windowData.parentHwnd, "abc")

    // wait longer than the undo grouping timeout (300ms) so the next edit starts a fresh undo step
    time.sleep(400_000_000)

    typeStringOnKeyboard(windowData.parentHwnd, "def")

    clickCtrlKey(win32.VK_Z) // undo "def"
    time.sleep(100_000_000)
    testing.expect_value(t, strings.to_string(main.getActiveTabContext().text), "abc")

    clickCtrlShiftKey(win32.VK_Z) // redo "def"
    time.sleep(100_000_000)
    testing.expect_value(t, strings.to_string(main.getActiveTabContext().text), "abcdef")
}

@(test)
new_empty_tab_increases_count :: proc(t: ^testing.T) {
    os.remove(main.editorStateFilePath)

    appThread, windowData := startApp(proc(windowData: ^main.WindowData) -> bool {
        return windowData.windowCreated
    })
    defer stopApp(appThread, windowData.parentHwnd)

    initialCount := len(windowData.fileTabs)

    clickCtrlKey(win32.VK_N) // open a new empty tab
    time.sleep(100_000_000)

    testing.expect_value(t, len(windowData.fileTabs), initialCount + 1)
}

@(test)
switch_between_tabs :: proc(t: ^testing.T) {
    os.remove(main.editorStateFilePath)

    appThread, windowData := startApp(proc(windowData: ^main.WindowData) -> bool {
        return windowData.windowCreated
    })
    defer stopApp(appThread, windowData.parentHwnd)

    clickCtrlKey(win32.VK_N) // add a second tab, which becomes the active one
    time.sleep(100_000_000)
    secondTabIndex := windowData.activeTabIndex

    clickCtrlKey(win32.VK_TAB) // cycle to the next tab
    time.sleep(100_000_000)

    testing.expect(t, windowData.activeTabIndex != secondTabIndex, "active tab should change after Ctrl+Tab")
}
