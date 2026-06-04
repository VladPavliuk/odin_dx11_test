package main

import win32 "core:sys/windows"

foreign import user32 "system:user32.lib"
foreign import shell32 "system:shell32.lib"

@(default_calling_convention = "std")
foreign user32 {
	@(link_name="CreateMenu") CreateMenu :: proc() -> win32.HMENU ---
	@(link_name="DrawMenuBar") DrawMenuBar :: proc(win32.HWND) ---
    @(link_name="GlobalLock") GlobalLock :: proc(win32.HGLOBAL) -> win32.LPVOID ---
    @(link_name="GetMenuBarInfo") GetMenuBarInfo :: proc(win32.HWND, u64, win32.LONG, ^WIN32_MENUBARINFO) -> bool ---
}

@(default_calling_convention = "std")
foreign shell32 {
    SHCreateItemFromParsingName :: proc(win32.PCWSTR, ^win32.IBindCtx, win32.REFIID, rawptr) -> win32.HRESULT ---
    ILCreateFromPathW :: proc(pszPath: win32.PCWSTR) -> rawptr ---
    SHOpenFolderAndSelectItems :: proc(pidlFolder: rawptr, cidl: win32.UINT, apidl: ^rawptr, dwFlags: win32.DWORD) -> win32.HRESULT ---
}

WIN32_OBJID_MENU :: 0xFFFFFFFD

WIN32_MENUBARINFO :: struct #packed {
    cbSize: win32.DWORD,
    rcBar: win32.RECT,
    hMenu: win32.HMENU,
    hwndMenu: win32.HWND,
    fBarFocused: i32,
    fFocused: i32,
    fUnused: i32,
} 

get_WIN32_MENUBARINFO :: proc() -> WIN32_MENUBARINFO {
    return WIN32_MENUBARINFO{
        cbSize = size_of(WIN32_MENUBARINFO),
        fBarFocused = 1,
        fFocused = 1,
        fUnused = 30,
    }
}

WIN32_CF_TEXT :: 1
WIN32_CF_UNICODETEXT :: 13

IDI_ICON :: 101 // copied from resources/resource.rc file

WinConfirmMessageAction :: enum {
    CLOSE_WINDOW,
    CANCEL,
    YES,
    NO,
}

WIN32_INFINITE :: 0xFFFFFFFF

WIN32_DEBUG_EVENT :: struct {
    dwDebugEventCode: win32.DWORD,
    dwProcessId: win32.DWORD,
    dwThreadId: win32.DWORD,
    u: struct #raw_union {
        Exception: WIN32_EXCEPTION_DEBUG_INFO,
        CreateThread: WIN32_CREATE_THREAD_DEBUG_INFO,
        CreateProcessInfo: WIN32_CREATE_PROCESS_DEBUG_INFO,
        ExitThread: WIN32_EXIT_THREAD_DEBUG_INFO,
        ExitProcess: WIN32_EXIT_PROCESS_DEBUG_INFO,
        LoadDll: WIN32_LOAD_DLL_DEBUG_INFO,
        UnloadDll: WIN32_UNLOAD_DLL_DEBUG_INFO,
        DebugString: WIN32_OUTPUT_DEBUG_STRING_INFO,
        RipInfo: WIN32_RIP_INFO,
    }
}

WIN32_EXCEPTION_MAXIMUM_PARAMETERS :: 15

WIN32_DBG_CONTINUE :: 0x00010002
WIN32_DBG_EXCEPTION_NOT_HANDLED :: 0x80010001

WIN32_EXCEPTION_RECORD :: struct {
    ExceptionCode: win32.DWORD,
    ExceptionFlags: win32.DWORD,
    ExceptionRecord: ^WIN32_EXCEPTION_RECORD,
    ExceptionAddress: win32.PVOID,
    NumberParameters: win32.DWORD,
    ExceptionInformation: [WIN32_EXCEPTION_MAXIMUM_PARAMETERS]win32.ULONG_PTR,
}

WIN32_EXCEPTION_DEBUG_INFO :: struct {
    ExceptionRecord: WIN32_EXCEPTION_RECORD, 
    dwFirstChance: win32.DWORD,
}

WIN32_CREATE_THREAD_DEBUG_INFO :: struct {
    hThread: win32.HANDLE,
    lpThreadLocalBase: win32.LPVOID,
    lpStartAddress: win32.LPVOID, //  LPTHREAD_START_ROUTINE
}

WIN32_CREATE_PROCESS_DEBUG_INFO :: struct {
    hFile: win32.HANDLE,
    hProcess: win32.HANDLE,
    hThread: win32.HANDLE,
    lpBaseOfImage: win32.LPVOID,
    dwDebugInfoFileOffset: win32.DWORD,
    nDebugInfoSize: win32.DWORD,
    lpThreadLocalBase: win32.LPVOID,
    lpStartAddress: win32.LPVOID, // LPTHREAD_START_ROUTINE
    lpImageName: win32.LPVOID,
    fUnicode: win32.WORD,
}

WIN32_EXIT_THREAD_DEBUG_INFO :: struct {
    dwExitCode: win32.DWORD,
}

WIN32_EXIT_PROCESS_DEBUG_INFO :: struct {
    dwExitCode: win32.DWORD, 
}

WIN32_LOAD_DLL_DEBUG_INFO :: struct {
    hFile: win32.HANDLE,
    lpBaseOfDll: win32.LPVOID,
    dwDebugInfoFileOffset: win32.DWORD,
    nDebugInfoSize: win32.DWORD,
    lpImageName: win32.LPVOID,
    fUnicode: win32.WORD,
}

WIN32_UNLOAD_DLL_DEBUG_INFO :: struct {
    lpBaseOfDll: win32.LPVOID,
}

WIN32_OUTPUT_DEBUG_STRING_INFO :: struct {
    lpDebugStringData: win32.LPSTR,
    fUnicode: win32.WORD,
    nDebugStringLength: win32.WORD,
}

WIN32_RIP_INFO :: struct {
    dwError: win32.DWORD,
    dwType: win32.DWORD,
}

showOsConfirmMessage :: proc(title, message: string) -> WinConfirmMessageAction {
    result := win32.MessageBoxW(
        windowData.parentHwnd,
        win32.utf8_to_wstring(message),
        win32.utf8_to_wstring(title),
        win32.MB_YESNOCANCEL | win32.MB_ICONWARNING,
    )

    switch result {
    case win32.IDYES: return .YES
    case win32.IDNO: return .NO
    case win32.IDCANCEL: return .CANCEL
    case win32.IDCLOSE: return .CLOSE_WINDOW
    }

    return .CLOSE_WINDOW
}

getCurrentMousePosition :: proc() -> int2 {
    point: win32.POINT
    win32.GetCursorPos(&point)
    win32.ScreenToClient(windowData.parentHwnd, &point)

    return { i32(point.x), i32(point.y) }
}