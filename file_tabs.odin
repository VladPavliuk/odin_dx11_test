package main

import "core:strings"
import "core:os"
import "core:path/filepath"
import "ui"

renderEditorFileTabs :: proc() {
    tabsHeight: i32 = 25
    topOffset: i32 = 25 // TODO: calcualte it
    leftOffset: i32 = windowData.explorer == nil ? 0 : windowData.explorerWidth // TODO: make it configurable

    @(static)
    showTabContextMenu := false

    @(static)
    tabIndexContextMenu: int = -1

    @(static)
    leftSkip := 0

    @(static)
    tabContextMenuPosition := int2{ 0, 0 }

    tabContextMenuSize := int2{ 130, 125 }

    ui.pushCommand(&windowData.uiContext, ui.RectCommand{
        rect = ui.toRect(
            int2{ -windowData.size.x / 2 + leftOffset, windowData.size.y / 2 - topOffset - tabsHeight }, 
            int2{ windowData.size.x - leftOffset, tabsHeight }),
        bgColor = GRAY_COLOR,
    })

    tabItems := make([dynamic]ui.TabsItem)
    defer delete(tabItems)

    for &fileTab in windowData.fileTabs {
        rightIcon: TextureId = .CLOSE_ICON
        
        if !fileTab.isSaved { rightIcon = .CIRCLE }
        if fileTab.isPinned { rightIcon = .PIN }

        tab := ui.TabsItem{
            text = fileTab.name,
            isPinned = fileTab.isPinned,
            leftIconId = i32(getIconByFilePath(fileTab.filePath)),
            leftIconSize = { 16, 16 },
            rightIconId = i32(rightIcon),
        }

        append(&tabItems, tab)
    }

    tabActions := ui.renderTabs(&windowData.uiContext, ui.Tabs{
        position = { -windowData.size.x / 2 + leftOffset, windowData.size.y / 2 - topOffset - tabsHeight },
        width = int(windowData.size.x - leftOffset),
        activeTabIndex = &windowData.activeTabIndex,
        jumpToActive = windowData.shouldJumpToActiveTab,
        items = tabItems[:],
        itemStyles = {
            padding = { top = 2, bottom = 2, left = 2, right = 5 },
            size = { 120, tabsHeight },
        },
        leftSkipOffset = &leftSkip,
        bgColor = GRAY_COLOR,
    })

    switch action in tabActions {
    case ui.TabsSwitched:
        windowData.wasFileTabChanged = true
        switchInputContextToEditor()
    case ui.TabsActionClose:
        tab := &windowData.fileTabs[action.itemIndex]

        if tab.isPinned {
            toggleTabPin(action.itemIndex)
        } else {
            tryCloseFileTab(action.itemIndex)
        }
    case ui.TabsHot:
        switch inputState.mouse {
        case { .MIDDLE_WAS_UP }: tryCloseFileTab(action.itemIndex)
        case { .RIGHT_WAS_UP }:
            tabContextMenuPosition = ui.screenToDirectXCoords(inputState.mousePosition, &windowData.uiContext)
            tabIndexContextMenu = action.itemIndex
            showTabContextMenu = true
        }
        case ui.TabsSwapTabs: swapTabs(action.aIndex, action.bIndex)
    }

    if ui.beginPopup(&windowData.uiContext, ui.Popup{
        position = tabContextMenuPosition, size = tabContextMenuSize,
        bgColor = DARKER_GRAY_COLOR,
        isOpen = &showTabContextMenu,
        clipRect = ui.Rect{
            top = windowData.size.y / 2 - 25, // TODO: remove hardcoded value
            bottom = -windowData.size.y / 2,
            right = windowData.size.x / 2,
            left = -windowData.size.x / 2,
        },
    }) {
        defer ui.endPopup(&windowData.uiContext)

        tabToPin := &windowData.fileTabs[tabIndexContextMenu]

        if actions, _ := ui.renderButton(&windowData.uiContext, ui.TextButton{
            text = tabToPin.isPinned ? "Unpin tab" : "Pin tab",
            position = { 0, 0 },
            size = { 130, 25 },
            noBorder = true,
            hoverBgColor = THEME_COLOR_1,
        }); .SUBMIT in actions {
            showTabContextMenu = false

            toggleTabPin(tabIndexContextMenu)
        }

        if actions, _ := ui.renderButton(&windowData.uiContext, ui.TextButton{
            text = "Close all",
            position = { 0, 25 },
            size = { 130, 25 },
            noBorder = true,
            hoverBgColor = THEME_COLOR_1,
        }); .SUBMIT in actions {
            #reverse for fileTab, index in windowData.fileTabs {
                if !tryCloseFileTab(index) { break }
            }
            showTabContextMenu = false
        }

        if actions, _ := ui.renderButton(&windowData.uiContext, ui.TextButton{
            text = "Close to the right",
            position = { 0, 50 },
            size = { 130, 25 },
            noBorder = true,
            hoverBgColor = THEME_COLOR_1,
        }); .SUBMIT in actions {
            #reverse for fileTab, index in windowData.fileTabs {
                if tabIndexContextMenu >= index { break }
                if !tryCloseFileTab(index) { break }
            }

            showTabContextMenu = false
        }

        if actions, _ := ui.renderButton(&windowData.uiContext, ui.TextButton{
            text = "Close others",
            position = { 0, 75 },
            size = { 130, 25 },
            noBorder = true,
            hoverBgColor = THEME_COLOR_1,
        }); .SUBMIT in actions {
            // do it in reverse to keep indices
            #reverse for fileTab, index in windowData.fileTabs {
                if tabIndexContextMenu != index {
                    if !tryCloseFileTab(index) {
                        break
                    }
                }
            }
            showTabContextMenu = false
        }

        if actions, _ := ui.renderButton(&windowData.uiContext, ui.TextButton{
            text = "Close",
            position = { 0, 100 },
            size = { 130, 25 },
            noBorder = true,
            hoverBgColor = THEME_COLOR_1,
        }); .SUBMIT in actions {
            tryCloseFileTab(tabIndexContextMenu)
            showTabContextMenu = false
        }
    }
}

swapTabs :: proc(fromIndex, toIndex: int) {
    assert(fromIndex >= 0)
    assert(toIndex >= 0)
    assert(fromIndex < len(windowData.fileTabs) )
    assert(toIndex < len(windowData.fileTabs))

    if fromIndex == toIndex { return }

    //if windowData.fileTabs[fromIndex].isPinned != windowData.fileTabs[toIndex].isPinned { return }

    tmpTab := windowData.fileTabs[fromIndex]

    windowData.fileTabs[fromIndex] = windowData.fileTabs[toIndex]
    windowData.fileTabs[toIndex] = tmpTab

    if windowData.activeTabIndex == fromIndex { windowData.activeTabIndex = toIndex } 
    else if windowData.activeTabIndex == toIndex { windowData.activeTabIndex = fromIndex }
}

toggleTabPin :: proc(tabIndex: int) {
    // todo: what if that tab is gone??
    tmpTab := windowData.fileTabs[tabIndex]
    tmpTab.isPinned = !tmpTab.isPinned

    ordered_remove(&windowData.fileTabs, tabIndex)

    // find last pinned tab index
    lastPinnedIndex := -1
    for tab, index in windowData.fileTabs {
        if !tab.isPinned { break }
        lastPinnedIndex = index
    }
    lastPinnedIndex += 1 // we should insert right after the last pinned tab

    inject_at(&windowData.fileTabs, lastPinnedIndex, tmpTab)

    //adjust active tab index
    if windowData.activeTabIndex == tabIndex {
        windowData.activeTabIndex = lastPinnedIndex
    } else {
        if windowData.activeTabIndex >= lastPinnedIndex && tabIndex > windowData.activeTabIndex {
            windowData.activeTabIndex += 1
        } else if windowData.activeTabIndex <= lastPinnedIndex && tabIndex < windowData.activeTabIndex {
            windowData.activeTabIndex -= 1
        }
    }
}

getActiveTab :: proc() -> ^FileTab {
    if len(windowData.fileTabs) == 0 { return nil }

    return &windowData.fileTabs[windowData.activeTabIndex]
}

getActiveTabContext :: proc() -> ^EditableTextContext {
    tab := getActiveTab()
    if tab == nil { return nil }

    return getActiveTab().ctx
}

isActiveTabContext :: proc() -> bool {
    if windowData.editableTextCtx == nil { return false }
    
    return windowData.editableTextCtx == getActiveTab().ctx
}

addEmptyTab :: proc() {
    addTab(strings.clone("(empty)"))
}

addTab :: proc(title: string, filePath := "", text := "", lastUpdatedAt: i64 = 0, isReadOnly := false) {
    ctx := createEmptyTextContext(text)
    ctx.isReadOnly = isReadOnly

    tab := FileTab{
        name = title,
        filePath = filePath,
        ctx = ctx,
        isSaved = true,
        lastUpdatedAt = lastUpdatedAt,
    }
    append(&windowData.fileTabs, tab)

    windowData.activeTabIndex = len(windowData.fileTabs) - 1 // switch to new tab
    windowData.wasFileTabChanged = true

    switchInputContextToEditor()
}

loadFileFromExplorerIntoNewTab :: proc() {
    filePath, ok := showOpenFileDialog()
    if !ok { return }

    loadFileIntoNewTab(filePath)
}

loadFileIntoNewTab :: proc(filePath: string) {
    fileText, isReadOnly := loadFileForTab(filePath)

    // find if any tab is already associated with opened file
    tabIndex := -1
    for tab, index in windowData.fileTabs {
        if tab.filePath == filePath {
            tabIndex = index
            break
        }
    }

    if tabIndex != -1 {
        windowData.activeTabIndex = tabIndex
        windowData.wasFileTabChanged = true
        switchInputContextToEditor()
        return
    }

    //activeTab := getActiveTab()

    // if len(windowData.fileTabs) == 1 && 
    //     len(activeTab.filePath) == 0 && activeTab.isSaved {
    //     replaceTabInfoByIndex(FileTab{
    //         name = strings.clone(filepath.base(filePath)),
    //         ctx = createEmptyTextContext(fileText),
    //         filePath = strings.clone(filePath),
    //         isSaved = true,
    //         lastUpdatedAt = getCurrentUnixTime(),
    //     }, windowData.activeTabIndex)
    //     return
    // }

    addTab(strings.clone(filepath.base(filePath)), strings.clone(filePath), fileText, getCurrentUnixTime(), isReadOnly)
}

getFileTabIndex :: proc(tabs: []FileTab, filePath: string) -> int {
    for tab, index in tabs {
        if tab.filePath == filePath { return index }
    }

    return -1
}

replaceTabInfoByIndex :: proc(tab: FileTab, index: i32) {
    oldTab := &windowData.fileTabs[index]
    
    freeTextContext(oldTab.ctx)
    delete(oldTab.name)
    delete(oldTab.filePath)

    oldTab.ctx = tab.ctx
    oldTab.filePath = tab.filePath
    oldTab.isSaved = tab.isSaved
    oldTab.lastUpdatedAt = tab.lastUpdatedAt
    oldTab.name = tab.name

    switchInputContextToEditor()
}

moveToNextTab :: proc() {
    windowData.activeTabIndex = (windowData.activeTabIndex + 1) % len(windowData.fileTabs)
    windowData.wasFileTabChanged = true
    switchInputContextToEditor()
}

moveToPrevTab :: proc() {
    windowData.activeTabIndex = windowData.activeTabIndex == 0 ? len(windowData.fileTabs) - 1 : windowData.activeTabIndex - 1
    windowData.wasFileTabChanged = true

    switchInputContextToEditor()
}

wasFileModifiedExternally :: proc(tab: ^FileTab) {
    // if no real file association, just skip the validation
    if tab == nil || tab.filePath == "" {
        return 
    }

    lastModified, exists := getFileLastMidifiedUnixTime(tab.filePath)

    if !exists {
         // if file does not exist anymore, just mark tab as unsafed and remove old file association
         ui.pushAlert(&windowData.uiContext, ui.Alert{
            text = strings.clone(fmt.tprintfln("%q was removed!", tab.name)),
            timeout = 5.0,
            bgColor = RED_COLOR,
        })

        tab.isSaved = false
        delete(tab.filePath)
        tab.filePath = ""
        return
    }

    if tab.lastUpdatedAt > lastModified { // no changes, ignore
        return
    }

    switch showOsConfirmMessage("Edi the editor", "File was modified outside the editor, override your version?") {
    case .YES:
        newText, isReadOnly := loadFileForTab(tab.filePath)

        freeTextContext(tab.ctx)
        tab.ctx = createEmptyTextContext(newText)
        tab.ctx.isReadOnly = isReadOnly
        tab.lastUpdatedAt = getCurrentUnixTime()

        switchInputContextToEditor()
    case .NO, .CANCEL, .CLOSE_WINDOW:
        tab.isSaved = false
        delete(tab.filePath)
        tab.filePath = ""        
    }
}

tryCloseFileTab :: proc(index: int, force := false) -> (wasClosed: bool) {
    tab := &windowData.fileTabs[index]

    // if there's any unsaved changes, show confirmation box
    if !tab.isSaved && !force {
        switch showOsConfirmMessage("Edi the editor", "Do you want to save the changes?") {
        case .YES: saveToOpenedFile(tab)
        case .NO:
        case .CANCEL, .CLOSE_WINDOW: return false
        }
    }

    freeTextContext(tab.ctx)
    delete(tab.name)
    delete(tab.filePath)
    
    ordered_remove(&windowData.fileTabs, index)
    if index <= windowData.activeTabIndex {
        windowData.activeTabIndex -= 1
        windowData.activeTabIndex = max(0, windowData.activeTabIndex) // if active tab if on the left it will be -1 without it
    }
    windowData.wasFileTabChanged = true

    // if len(windowData.fileTabs) == 0 {
    //     addEmptyTab()
    // }

    switchInputContextToEditor()

    return true
}