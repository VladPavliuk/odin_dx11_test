package main

import "vendor:glfw"

windowMaximizeProc :: proc "c" (window: glfw.WindowHandle, iconified: i32) {
    test := iconified
    // /assert(true)
} 

main :: proc() {
    window, hwnd, windowData := createWindow({ 800, 800 })
    defer glfw.DestroyWindow(window)

    directXState := initDirectX(hwnd)
    windowData.directXState = &directXState
    defer clearDirectX(&directXState)

    glfw.SetWindowMaximizeCallback(window, windowMaximizeProc)
    glfw.SetKeyCallback(window, keyboardHandler)
    glfw.SetCharCallback(window, keychardCharInputHandler)
    glfw.SetWindowSizeCallback(window, windowSizeChangedHandler)
    glfw.SetCursorPosCallback(window, mousePositionHandler)
    glfw.SetMouseButtonCallback(window, mouseClickHandler)
    
    initGpuResources(&directXState)
    
    angle: f32 = 0.0
    beforeFrameTime := f32(glfw.GetTime())
    afterFrameTime := beforeFrameTime
    delta := afterFrameTime - beforeFrameTime

    for !glfw.WindowShouldClose(window) {
        beforeFrameTime = f32(glfw.GetTime())

        render(&directXState, windowData)

        glfw.PollEvents()

        afterFrameTime = f32(glfw.GetTime())
        delta = afterFrameTime - beforeFrameTime
    }

    // edit.destroy(&editState)
}