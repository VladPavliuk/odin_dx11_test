package main

import "core:strings"
import "core:unicode/utf8"
import "core:os"
import "core:path/filepath"
import "core:encoding/json"

import win32 "core:sys/windows"

editorStateFilePath :: "./edi_state.json"

// showOpenFolderDialog :: proc() -> (res: string, success: bool) {
//     BROWSEINFO bi = {0};
//     OpenFolderDialog
// }

getFileLastMidifiedUnixTime :: proc(filePath: string) -> (unixTime: i64, exists: bool) {
    if !os.exists(filePath) {
        return 0, false
    }

    hFile := win32.CreateFileW(win32.utf8_to_wstring(filePath), win32.GENERIC_READ, win32.FILE_SHARE_READ, nil, win32.OPEN_EXISTING, win32.FILE_ATTRIBUTE_NORMAL, nil)
    assert(hFile != win32.INVALID_HANDLE_VALUE)
    defer win32.CloseHandle(hFile)

    lpLastWriteTime: win32.FILETIME
    res := win32.GetFileTime(hFile, nil, nil, &lpLastWriteTime)
    assert(res != false)

    return win32.FILETIME_as_unix_nanoseconds(lpLastWriteTime), true
}

showOpenFileDialog :: proc(showOnlyFolders := false) -> (res: string, success: bool) {
    hr := win32.CoInitializeEx(nil, win32.COINIT(0x2 | 0x4))
    assert(hr == 0)
    defer win32.CoUninitialize()

    pFileOpen: ^win32.IFileOpenDialog
    hr = win32.CoCreateInstance(win32.CLSID_FileOpenDialog, nil, 
        win32.CLSCTX_INPROC_SERVER, //| win32.CLSCTX_INPROC_HANDLER | win32.CLSCTX_LOCAL_SERVER | win32.CLSCTX_REMOTE_SERVER, 
        win32.IID_IFileOpenDialog, 
        cast(^win32.LPVOID)(&pFileOpen))
    assert(hr == 0)
    defer pFileOpen->Release()

    fileTypes: []win32.COMDLG_FILTERSPEC = {
        { win32.utf8_to_wstring("All Files"), win32.utf8_to_wstring("*") },
        { win32.utf8_to_wstring("Text files (*.txt | *.odin)"), win32.utf8_to_wstring("*.txt;*.odin") },
    }

    hr = pFileOpen->SetFileTypes(u32(len(fileTypes)), raw_data(fileTypes[:]))
    assert(hr == 0)

    if showOnlyFolders {    
        dwOptions: win32.DWORD
        hr = pFileOpen->GetOptions(&dwOptions)
        assert(hr == 0)
        dwOptions = dwOptions | win32.FOS_PICKFOLDERS | win32.FOS_PATHMUSTEXIST | win32.FOS_FILEMUSTEXIST | win32.FOS_FORCEFILESYSTEM 
        pFileOpen->SetOptions(dwOptions)
    }

    // show window
    hr = pFileOpen->Show(windowData.parentHwnd)
    if hr != 0 { return }

    // get path name
    pItem: ^win32.IShellItem
    hr = pFileOpen->GetResult(&pItem)
    assert(hr == 0)
    defer pItem->Release()

    pszFilePath: ^u16
    hr = pItem->GetDisplayName(win32.SIGDN.FILESYSPATH, &pszFilePath)
    assert(hr == 0)
    defer win32.CoTaskMemFree(pszFilePath)
    
    resStr, err := win32.wstring_to_utf8(win32.wstring(pszFilePath), -1, context.temp_allocator)

    return resStr, err == nil
}

loadTextFile :: proc(filePath: string) -> string {
    fileContent := os.read_entire_file_from_filename(filePath, context.temp_allocator) or_else panic("Failed to read file")
    originalFileText := string(fileContent[:])

    fileText, _ := strings.remove_all(originalFileText, "\r", context.temp_allocator)
    
    return fileText
}

saveToOpenedFile :: proc(tab: ^FileTab) -> (success: bool) {
    if len(tab.filePath) == 0 {
        showSaveAsFileDialog(tab)
    }

    err := os.write_entire_file_or_err(tab.filePath, tab.ctx.text.buf[:])
    if err == os.General_Error.Not_Exist { // if user clicked cancel
        return false
    }
    assert(err == nil, fmt.tprintfln("File save error: %s", err))
    tab.isSaved = true
    tab.lastUpdatedAt = getCurrentUnixTime()

    return true
}

showSaveAsFileDialog :: proc(tab: ^FileTab) -> (success: bool) {
    hr := win32.CoInitializeEx(nil, win32.COINIT(0x2 | 0x4))
    assert(hr == 0)
    defer win32.CoUninitialize()

    pFileSave: ^win32.IFileSaveDialog
    hr = win32.CoCreateInstance(win32.CLSID_FileSaveDialog, nil, 
        win32.CLSCTX_INPROC_SERVER | win32.CLSCTX_INPROC_HANDLER | win32.CLSCTX_LOCAL_SERVER | win32.CLSCTX_REMOTE_SERVER, 
        win32.IID_IFileSaveDialog, 
        cast(^win32.LPVOID)(&pFileSave))
    assert(hr == 0)
    defer pFileSave->Release()
    
    // set file types
    fileTypes: []win32.COMDLG_FILTERSPEC = {
        // { win32.utf8_to_wstring("All Files"), win32.utf8_to_wstring("*") },
        { win32.utf8_to_wstring("Text file (*.txt)"), win32.utf8_to_wstring("*.txt") },
    }

    hr = pFileSave->SetFileTypes(u32(len(fileTypes)), raw_data(fileTypes[:]))
    assert(hr == 0)

    // set default file name
    defaultFileName := "New Text File.txt"
    
    text := strings.to_string(tab.ctx.text)

    defaultFileNameBuilder, ok := tryGetDefaultFileName(text)
    defer strings.builder_destroy(&defaultFileNameBuilder)

    if ok {
        defaultFileName = strings.to_string(defaultFileNameBuilder)
    }

    hr = pFileSave->SetFileName(win32.utf8_to_wstring(defaultFileName))
    assert(hr == 0)

    // set default path, if no recent
    IID_IShellItem := &win32.GUID{0x43826d1e, 0xe718, 0x42ee, {0xbc, 0x55, 0xa1, 0xe2, 0x61, 0xc3, 0x7b, 0xfe}}

    defaultPath := "C:\\"
    if os.is_dir(defaultPath) {
        defaultFolder: ^win32.IShellItem
        hr = SHCreateItemFromParsingName(win32.utf8_to_wstring(defaultPath), nil, IID_IShellItem, &defaultFolder)
        if hr == 0 {
            pFileSave->SetDefaultFolder(defaultFolder) 
            // pFileSave->SetFolder(defaultFolder) 
        }
        defaultFolder->Release()
    }

    // show window
    hr = pFileSave->Show(windowData.parentHwnd)
    if hr != 0 { return false }

    // get path
    shellItem: ^win32.IShellItem
    pFileSave->GetResult(&shellItem)
    defer shellItem->Release()

    filePathW: win32.LPWSTR
    shellItem->GetDisplayName(win32.SIGDN.FILESYSPATH, &filePathW)
    defer win32.CoTaskMemFree(filePathW)

    filePath, _ := win32.wstring_to_utf8(win32.wstring(filePathW), -1)

    delete(tab.name)
    delete(tab.filePath)
    tab.filePath = strings.clone(filePath)
    tab.name = strings.clone(filepath.base(tab.filePath))

    return true
}

SavedFileTab :: struct {
    name: string,
    filePath: string,
    isSaved: bool,
    isPinned: bool,
    lastUpdatedAt: i64,
    text: string,
    textSelection: [2]int,
    lineIndex: f32,
}

EditorState :: struct {
    fileTabs: [dynamic]SavedFileTab,
    activeTabIndex: int,
    openedFolder: string,
}

saveEditorState :: proc() {
    state := EditorState{}
    defer delete(state.fileTabs)

    if windowData.explorer != nil {
        state.openedFolder = windowData.explorer.rootPath
    }

    state.activeTabIndex = windowData.activeTabIndex

    // TODO: save only text copies of files that are relativelly small (less then 2k symbols)
    for tab in windowData.fileTabs {
        append(&state.fileTabs, SavedFileTab{
            name = tab.name,
            filePath = tab.filePath,
            isSaved = tab.isSaved,
            isPinned = tab.isPinned,
            lastUpdatedAt = tab.lastUpdatedAt,
            text = strings.to_string(tab.ctx.text),
            textSelection = tab.ctx.editorState.selection,
            lineIndex = tab.ctx.lineIndex,
        })
    }

    serializedState, err := json.marshal(state)
    assert(err == nil)
    defer delete(serializedState)

    saveErr := os.write_entire_file_or_err(editorStateFilePath, serializedState)
    assert(saveErr == nil)
}

applyEditorState :: proc() -> bool {
    fileContent, err := os.read_entire_file_or_err(editorStateFilePath)
    defer delete(fileContent)

    if err == os.General_Error.Not_Exist {
        return false
    }
    assert(err == nil)

    state: EditorState
    unmarshalErr := json.unmarshal(fileContent, &state, allocator = context.temp_allocator)

    assert(unmarshalErr == nil)

    for tab in state.fileTabs {
        ctx := createEmptyTextContext(tab.text)
        ctx.editorState.selection = tab.textSelection
        ctx.lineIndex = tab.lineIndex
        
        append(&windowData.fileTabs, FileTab{
            name = strings.clone(tab.name),
            ctx = ctx,
            filePath = strings.clone(tab.filePath),
            isSaved = tab.isSaved,
            isPinned = tab.isPinned,
            lastUpdatedAt = tab.lastUpdatedAt,
        })
        // delete(tab.text)
    }
    defer delete(state.fileTabs)

    if len(state.openedFolder) > 0 {
        showExplorer(strings.clone(state.openedFolder))
    }

    windowData.activeTabIndex = state.activeTabIndex

    return true
}

@(private="file")
tryGetDefaultFileName :: proc(text: string) -> (strings.Builder, bool)  {
    maxFileLength :: 10

    defaultFileNameBuilder := strings.builder_make()

    if len(text) == 0 {
        return defaultFileNameBuilder, false
    }

    invalidSymbols := "<>:\"/\\|?*" // invalid as a part of file name

    threshold := 100
    startIndex := -1

    // skip all whitespaces
    for symbol, i in text {
        if i > threshold {
            break
        }

        if !strings.is_space(symbol) {
            startIndex = i 
            break 
        }
    }

    if startIndex == -1 {
        return defaultFileNameBuilder, false
    }

    for symbol, i in text[startIndex:] {
        if i > threshold { break }

        if strings.builder_len(defaultFileNameBuilder) > maxFileLength { break }

        if symbol == '\n' { break }

        if !strings.contains_rune(invalidSymbols, symbol) {
            if strings.is_space(symbol) {
                strings.write_rune(&defaultFileNameBuilder, ' ')
            }  else {
                strings.write_rune(&defaultFileNameBuilder, symbol)
            }
        }
    }

    if strings.builder_len(defaultFileNameBuilder) == 0 {
        return defaultFileNameBuilder, false
    }

    // remove all whitespaces at the end
    hasWhitespaceAtEnd := true
    for hasWhitespaceAtEnd {           
        lastSymbol, width := utf8.decode_last_rune(defaultFileNameBuilder.buf[:])

        if width == utf8.RUNE_ERROR { break }

        hasWhitespaceAtEnd = strings.is_space(lastSymbol) 
        
        if hasWhitespaceAtEnd {
            strings.pop_rune(&defaultFileNameBuilder) 
        }
    }

    strings.write_string(&defaultFileNameBuilder, ".txt")

    return defaultFileNameBuilder, true
}
