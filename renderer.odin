package main

import "ui"

import "base:intrinsics"

import "vendor:directx/d3d11"
import "vendor:directx/dxgi"

import "core:math"
import "core:strconv"

// TODO: make all them configurable
EMPTY_COLOR := float4{ 0.0, 0.0, 0.0, 0.0 }
RED_COLOR := float4{ 1.0, 0.0, 0.0, 1.0 }
GREEN_COLOR := float4{ 0.0, 1.0, 0.0, 1.0 }
BLUE_COLOR := float4{ 0.0, 0.0, 1.0, 1.0 }
YELLOW_COLOR := float4{ 1.0, 1.0, 0.0, 1.0 }
WHITE_COLOR := float4{ 1.0, 1.0, 1.0, 1.0 }
BLACK_COLOR := float4{ 0.0, 0.0, 0.0, 1.0 }
LIGHT_GRAY_COLOR := float4{ 0.5, 0.5, 0.5, 1.0 }
GRAY_COLOR := float4{ 0.3, 0.3, 0.3, 1.0 }
DARKER_GRAY_COLOR := float4{ 0.2, 0.2, 0.2, 1.0 }
DARK_GRAY_COLOR := float4{ 0.1, 0.1, 0.1, 1.0 }

EDITOR_BG_COLOR := float4{ 0.0, 0.25, 0.5, 1.0 }
CURSOR_COLOR := float4{ 0.0, 0.0, 0.0, 1.0 }
CURSOR_LINE_BG_COLOR := float4{ 1.0, 1.0, 1.0, 0.1 }
LINE_NUMBERS_BG_COLOR := float4{ 0.0, 0.0, 0.0, 0.3 }
TEXT_SELECTION_BG_COLOR := float4{ 1.0, 0.5, 1.0, 0.3 }

THEME_COLOR_1 := float4{ 251 / 255.0, 133 / 255.0, 0 / 255.0, 1.0 }
THEME_COLOR_2 := float4{ 251 / 255.0, 183 / 255.0, 0 / 255.0, 1.0 }
THEME_COLOR_3 := float4{ 2 / 255.0, 48 / 255.0, 71 / 255.0, 1.0 }
THEME_COLOR_4 := float4{ 33 / 255.0, 158 / 255.0, 188 / 255.0, 1.0 }
THEME_COLOR_5 := float4{ 142 / 255.0, 202 / 255.0, 230 / 255.0, 1.0 }

render :: proc() {
    ctx := directXState.ctx

    // ctx->DiscardView(directXState.backBufferView)
    ctx->ClearRenderTargetView(directXState.backBufferView, &EDITOR_BG_COLOR)
    ctx->ClearDepthStencilView(directXState.depthBufferView, { .DEPTH, .STENCIL }, 1.0, 0)
    
    ctx->OMSetRenderTargets(1, &directXState.backBufferView, directXState.depthBufferView)
    ctx->OMSetDepthStencilState(directXState.depthStencilState, 0)
    ctx->RSSetState(directXState.rasterizerState)
	ctx->PSSetSamplers(0, 1, &directXState->samplerState)

    ctx->OMSetBlendState(directXState.blendState, nil, 0xFFFFFFFF)

	ctx->IASetPrimitiveTopology(d3d11.PRIMITIVE_TOPOLOGY.TRIANGLELIST)
    ctx->IASetInputLayout(directXState.inputLayouts[.POSITION_AND_TEXCOORD])

    offsets := [?]u32{ 0 }
    strideSize := [?]u32{directXState.vertexBuffers[.QUAD].strideSize}
	ctx->IASetVertexBuffers(0, 1, &directXState.vertexBuffers[.QUAD].gpuBuffer, raw_data(strideSize[:]), raw_data(offsets[:]))
	ctx->IASetIndexBuffer(directXState.indexBuffers[.QUAD].gpuBuffer, dxgi.FORMAT.R32_UINT, 0)

    // startTimer()
    ui.setClipRect(&windowData.uiContext, ui.Rect{
        top = windowData.size.y / 2,
        bottom = -windowData.size.y / 2,
        left = -windowData.size.x / 2,
        right = windowData.size.x / 2,
    })
    uiStaff() // 5702.110 ms
    ui.resetClipRect(&windowData.uiContext)
    // stopTimer()

    // renderLineNumbers()

    // d3d11.VIEWPORT_AND_SCISSORRECT_OBJECT_COUNT_PER_PIPELINE

    hr := directXState.swapchain->Present(1, {})
    assert(hr == 0, fmt.tprintfln("DirectX presentation error: %i", hr))
    //TODO: if pc went to sleep mode hr variable might be not 0, investigate why is that
}

// resetClipRect :: proc() {
//     scissorRect := d3d11.RECT{
//         top = 0,
//         bottom = windowData.size.y,
//         left = 0,
//         right = windowData.size.x,
//     }

//     directXState.ctx->RSSetScissorRects(1, &scissorRect)
// }

// setClipRect :: proc(rect: ui.Rect) {
//     rect := rect
//     rect = ui.directXToScreenRect(rect, &windowData.uiContext)

//     scissorRect := d3d11.RECT{
//         top = rect.top,
//         bottom = rect.bottom,
//         left = rect.left,
//         right = rect.right,
//     }

//     directXState.ctx->RSSetScissorRects(1, &scissorRect)
// }

testingButtons :: proc() {
    if action, _ := ui.renderButton(&windowData.uiContext, ui.TextButton{
        text = "Test 1",
        position = { 0, 0 },
        size = { 100, 30 },
        // color = WHITE_COLOR,
        bgColor = THEME_COLOR_3,
        // hoverBgColor = BLACK_COLOR,
    }); action != nil {
        fmt.print("Test 1 - ")

        if .SUBMIT in action { fmt.print("SUBMIT ") }
        if .HOT in action { fmt.print("HOT ") }
        if .ACTIVE in action { fmt.print("ACTIVE ") }
        if .GOT_ACTIVE in action { fmt.print("GOT_ACTIVE ") }
        if .LOST_ACTIVE in action { fmt.print("LOST_ACTIVE ") }
        if .MOUSE_ENTER in action { fmt.print("MOUSE_ENTER ") }
        if .MOUSE_LEAVE in action { fmt.print("MOUSE_LEAVE ") }
        if .GOT_FOCUS in action { fmt.print("GOT_FOCUS ") }
        if .LOST_FOCUS in action { fmt.print("LOST_FOCUS ") }

        fmt.print('\n')
    }

    if action, _ := ui.renderButton(&windowData.uiContext, ui.TextButton{
        text = "Test 2",
        position = { 40, 10 },
        size = { 100, 30 },
        // color = WHITE_COLOR,
        bgColor = THEME_COLOR_1,
        // hoverBgColor = BLACK_COLOR,
    }); action != nil {
        fmt.print("Test 2 - ")

        if .SUBMIT in action { fmt.print("SUBMIT ") }
        if .HOT in action { fmt.print("HOT ") }
        if .ACTIVE in action { fmt.print("ACTIVE ") }
        if .GOT_ACTIVE in action { fmt.print("GOT_ACTIVE ") }
        if .LOST_ACTIVE in action { fmt.print("LOST_ACTIVE ") }
        if .MOUSE_ENTER in action { fmt.print("MOUSE_ENTER ") }
        if .MOUSE_LEAVE in action { fmt.print("MOUSE_LEAVE ") }
        if .GOT_FOCUS in action { fmt.print("GOT_FOCUS ") }
        if .LOST_FOCUS in action { fmt.print("LOST_FOCUS ") }

        fmt.print('\n')
    }
}

renderUi :: proc() {
    uiCtx := &windowData.uiContext
    gpuCtx := directXState.ctx

    // TODO: that does not look good!
    // try to attach some kind of index to a command
    initZIndex := windowData.maxZIndex / 2.0
    zIndexStep: f32 = 0.1

    //TODO: it's better to split up commands list by Rects, Image, Lines

    // render all rectangle objects in commands list
    {
        rectsWithColorListBuffer := directXState.structuredBuffers[.RECTS_WITH_COLOR_LIST]
        rectsWithColorList := memoryAsSlice(RectWithColor, rectsWithColorListBuffer.cpuBuffer, rectsWithColorListBuffer.length)
        rectsWithColorIndex: i32 = 0

        pushToRectsWithColor :: proc(rect: ui.Rect, clipRect: ui.Rect, color: float4, zIndex: f32, index: ^i32, list: []RectWithColor) {
            rect := rect
            rect = ui.clipRect(rect, clipRect)

            // NOTE: if after clipping rect has incorrect side, that means it was outside of clip rect, so don't draw it 
            if !ui.isValidRect(rect) {
                return
            }

            position, size := ui.fromRect(rect)
            rectGpu := RectWithColor{
                transformation = getTransformationMatrix(
                    { f32(position.x), f32(position.y), zIndex }, 
                    { 0.0, 0.0, 0.0 }, { f32(size.x), f32(size.y), 1.0 }),
                color = color,
            }
            list[index^] = rectGpu

            index^ += 1
        }

        // NOTE: draw non-transparect objects first, otherwise there will be weird artifacts (bacause of blending???)
        for cmd, index in uiCtx.commands {
            zIndex := initZIndex - f32(index) * zIndexStep

            #partial switch command in cmd {
            case ui.RectCommand:
                pushToRectsWithColor(command.rect, command.clipRect, command.bgColor, zIndex, &rectsWithColorIndex, rectsWithColorList)

                // ui.advanceZIndex(uiCtx)
            case ui.BorderRectCommand:
                pushToRectsWithColor(ui.Rect{ // top border
                    top = command.rect.top, bottom = command.rect.top - command.thikness,
                    left = command.rect.left, right = command.rect.right,
                }, command.clipRect, command.color, zIndex, &rectsWithColorIndex, rectsWithColorList)

                pushToRectsWithColor(ui.Rect{ // bottom border
                    top = command.rect.bottom + command.thikness, bottom = command.rect.bottom,
                    left = command.rect.left, right = command.rect.right,
                }, command.clipRect, command.color, zIndex, &rectsWithColorIndex, rectsWithColorList)

                pushToRectsWithColor(ui.Rect{ // left border
                    top = command.rect.top, bottom = command.rect.bottom,
                    left = command.rect.left, right = command.rect.left + command.thikness,
                }, command.clipRect, command.color, zIndex, &rectsWithColorIndex, rectsWithColorList)

                pushToRectsWithColor(ui.Rect{ // right border
                    top = command.rect.top, bottom = command.rect.bottom,
                    left = command.rect.right - command.thikness, right = command.rect.right,
                }, command.clipRect, command.color, zIndex, &rectsWithColorIndex, rectsWithColorList)

                // ui.advanceZIndex(uiCtx)
            }
        }
        
        gpuCtx->VSSetShader(directXState.vertexShaders[.RECTS_WITH_COLOR], nil, 0)
        gpuCtx->VSSetConstantBuffers(0, 1, &directXState.constantBuffers[.PROJECTION].gpuBuffer)
        gpuCtx->VSSetShaderResources(0, 1, &rectsWithColorListBuffer.srv)

        gpuCtx->PSSetShader(directXState.pixelShaders[.RECTS_WITH_COLOR], nil, 0)

        updateGpuBuffer(rectsWithColorList, rectsWithColorListBuffer)
        directXState.ctx->DrawIndexedInstanced(directXState.indexBuffers[.QUAD].length, u32(rectsWithColorIndex), 0, 0, 0)
    }

    // render image commands
    {
        rectsWithImageListBuffer := directXState.structuredBuffers[.RECTS_WITH_IMAGE_LIST]
        rectsWithImageList := memoryAsSlice(RectWithImage, rectsWithImageListBuffer.cpuBuffer, rectsWithImageListBuffer.length)
        rectsWithImageIndex: i32 = 0

        for cmd, index in uiCtx.commands {
            zIndex := initZIndex - f32(index) * zIndexStep

            #partial switch command in cmd {
            case ui.ImageCommand:
                rect := ui.clipRect(command.rect, command.clipRect)

                if !ui.isValidRect(rect) { break }

                offset, scale := ui.normalizeClippedToOriginal(rect, command.rect)
// todo: HERE IS FLICKRING PROBLEM??????????
                position, size := ui.fromRect(rect)
                image := RectWithImage{
                    transformation = getTransformationMatrix(
                        { f32(position.x), f32(position.y), zIndex }, 
                        { 0.0, 0.0, 0.0 }, { f32(size.x), f32(size.y), 1.0 }),
                    imageIndex = directXState.iconsIndexesMapping[TextureId(command.textureId)],
                    textureOffset = offset,
                    textureScale =  scale,
                }
                rectsWithImageList[rectsWithImageIndex] = image
                
                rectsWithImageIndex += 1
                // renderImageRect(command.rect, uiCtx.zIndex, TextureId(command.textureId))
                // ui.advanceZIndex(uiCtx)
            }
        }

        gpuCtx->VSSetShader(directXState.vertexShaders[.RECTS_WITH_IMAGE], nil, 0)
        gpuCtx->VSSetConstantBuffers(0, 1, &directXState.constantBuffers[.PROJECTION].gpuBuffer)
        gpuCtx->VSSetShaderResources(0, 1, &rectsWithImageListBuffer.srv)

        gpuCtx->PSSetShader(directXState.pixelShaders[.RECTS_WITH_IMAGE], nil, 0)
        gpuCtx->PSSetShaderResources(0, 1, &directXState.textures[.ICONS_ARRAY].srv)

        updateGpuBuffer(rectsWithImageList, rectsWithImageListBuffer)
        directXState.ctx->DrawIndexedInstanced(directXState.indexBuffers[.QUAD].length, u32(rectsWithImageIndex), 0, 0, 0)
    }

    // render text
    {
        fontListBuffer := directXState.structuredBuffers[.GLYPHS_LIST]
        fontsList := memoryAsSlice(FontGlyphGpu, fontListBuffer.cpuBuffer, fontListBuffer.length)
        charIndex: i32 = 0

        for cmd, comandIndex in uiCtx.commands {
            zIndex := initZIndex - f32(comandIndex) * zIndexStep

            // populate clip rects
            // comandIndex

            #partial switch command in cmd {
            case ui.TextCommand:
                // renderLine(command.text, &windowData.font, command.position, command.color, uiCtx.zIndex)
                // ui.advanceZIndex(uiCtx)
                position := command.position
                font := &windowData.font

                leftOffset := f32(position.x)
                topOffset := f32(position.y) - font.descent

                // if containerHeight > 0 {
                //     textHeight := getTextHeight(&windowData.font)

                //     topOffset += f32(containerHeight) / 2.0 - textHeight / 2.0
                // }

                for char, lineCharIndex in command.text {
                    fontChar := font.chars[char]

                    glyphSize: int2 = { fontChar.rect.right - fontChar.rect.left, fontChar.rect.top - fontChar.rect.bottom }
                    glyphPosition: int2 = { i32(leftOffset) + fontChar.offset.x, i32(topOffset) - glyphSize.y - fontChar.offset.y }

                    leftOffset += fontChar.xAdvance

                    //> validate clipping
                    originalGlyphRect := ui.toRect(glyphPosition, glyphSize)
                    glyphRect := ui.clipRect(command.clipRect, originalGlyphRect)
                    if !ui.isValidRect(glyphRect) {
                        continue
                    }
                    
                    offset, scale := ui.normalizeClippedToOriginal(glyphRect, originalGlyphRect)

                    glyphPosition, glyphSize = ui.fromRect(glyphRect)
                    //<

                    modelMatrix := getTransformationMatrix(
                        { f32(glyphPosition.x), f32(glyphPosition.y), zIndex }, 
                        { 0.0, 0.0, 0.0 }, 
                        { f32(glyphSize.x), f32(glyphSize.y), 1.0 },
                    )

                    fontsList[charIndex] = FontGlyphGpu{
                        sourceRect = fontChar.rect,
                        targetTransformation = modelMatrix,
                        color = command.color,
                        textureOffset = offset,
                        textureScale = scale,
                    }
                    
                    // if text width is exceeded the max width value, replace last 3 symbols in text by ...
                    if command.maxWidth > 0 && i32(leftOffset) > position.x + command.maxWidth {
                        if lineCharIndex >= 4 {
                            // replace3SymbolsByDots(fontsList, charIndex - 1, topOffset, zIndex, command.color, font)
                        }
                        break
                    }

                    charIndex += 1
                }
            }
            // ui.advanceZIndex(uiCtx)
        }
        
        gpuCtx->VSSetShader(directXState.vertexShaders[.FONT], nil, 0)
        gpuCtx->VSSetShaderResources(0, 1, &directXState.structuredBuffers[.GLYPHS_LIST].srv)
        gpuCtx->VSSetConstantBuffers(0, 1, &directXState.constantBuffers[.PROJECTION].gpuBuffer)

        gpuCtx->PSSetShader(directXState.pixelShaders[.FONT], nil, 0)
        gpuCtx->PSSetShaderResources(0, 1, &directXState.textures[.FONT].srv)

        updateGpuBuffer(fontsList, directXState.structuredBuffers[.GLYPHS_LIST])
        directXState.ctx->DrawIndexedInstanced(directXState.indexBuffers[.QUAD].length, u32(charIndex), 0, 0, 0)
    }

    // render rest of ui commands
    {
        for cmd, index in uiCtx.commands {
            zIndex := initZIndex - f32(index) * zIndexStep

            #partial switch command in cmd {
            case ui.EditableTextCommand:
                fillGlyphsLocations(&windowData.uiTextInputCtx)
                glyphsCount, selectionsCount := fillTextBuffer(&windowData.uiTextInputCtx, BLACK_COLOR, zIndex)
                
                renderText(glyphsCount, selectionsCount, TEXT_SELECTION_BG_COLOR)
            // case ui.ClipCommand:
            //     // setClipRect(command.rect)
            // case ui.ResetClipCommand:
            //     // resetClipRect()
            }
        }
    }
}

@(private="file")
replace3SymbolsByDots :: proc(fontsList: []FontGlyphGpu, lastIndexToReplace: i32, yPosition: f32, zIndex: f32, color: float4, font: ^FontData) {
    fontChar := font.chars['.']
    lastIndexToReplace := lastIndexToReplace
    lastIndexToReplace -= 2

    // TODO: improve it, right it just removes last 3 symbols and replace it by 3 dots
    // instead, try to find minimum amount of symbols that should be removed in order to fit 3 dots.
    startPosition := fontsList[lastIndexToReplace].targetTransformation[3][0]
    glyphSize: int2 = { fontChar.rect.right - fontChar.rect.left, fontChar.rect.top - fontChar.rect.bottom }

    for i: i32 = 0; i < 3; i += 1 {
        glyphPosition: int2 = { i32(startPosition) + fontChar.offset.x, i32(yPosition) - glyphSize.y - fontChar.offset.y }
        startPosition += fontChar.xAdvance

        modelMatrix := getTransformationMatrix(
            { f32(glyphPosition.x), f32(glyphPosition.y), zIndex }, 
            { 0.0, 0.0, 0.0 }, 
            { f32(glyphSize.x), f32(glyphSize.y), 1.0 },
        )

        fontsList[lastIndexToReplace + i] = FontGlyphGpu{
            sourceRect = fontChar.rect,
            targetTransformation = modelMatrix,
            color = color,
        }
    }
}

uiStaff :: proc() {
    ui.beginUi(&windowData.uiContext, windowData.maxZIndex / 2.0)
    // stopTimer()
    renderEditorContent() // 2620.899 ms
    // startTimer()

    renderLineNumbers()

    //> 63.444 ms
    renderEditorFileTabs()
    renderFolderExplorer()

    if windowData.debuggerThread != nil {
        renderDebugger()
    }

    if windowData.isFileSearchOpen {
        renderFileSearch()
    }

    renderTopMenu()
    //<

    ui.endUi(&windowData.uiContext, windowData.delta)

    renderUi() // 532 ms

    windowData.isInputMode = windowData.uiContext.activeId == {}
}

renderRect :: proc{renderRectVec_Float, renderRectVec_Int, renderRect_Int}

renderRect_Int :: proc(rect: ui.Rect, zValue: f32, color: float4) {
    renderRectVec_Float({ f32(rect.left), f32(rect.bottom) }, 
        { f32(rect.right - rect.left), f32(rect.top - rect.bottom) }, zValue, color)
}

renderRectVec_Int :: proc(position, size: int2, zValue: f32, color: float4) {
    renderRectVec_Float({ f32(position.x), f32(position.y) }, { f32(size.x), f32(size.y) }, zValue, color)
}

renderRectVec_Float :: proc(position, size: float2, zValue: f32, color: float4) {
    color := color
    ctx := directXState.ctx

    ctx->VSSetShader(directXState.vertexShaders[.BASIC], nil, 0)
    ctx->VSSetConstantBuffers(0, 1, &directXState.constantBuffers[.PROJECTION].gpuBuffer)
    ctx->VSSetConstantBuffers(1, 1, &directXState.constantBuffers[.MODEL_TRANSFORMATION].gpuBuffer)

    ctx->PSSetShader(directXState.pixelShaders[.SOLID_COLOR], nil, 0)
    ctx->PSSetConstantBuffers(0, 1, &directXState.constantBuffers[.COLOR].gpuBuffer)

    modelMatrix := intrinsics.transpose(getTransformationMatrix(
        { position.x, position.y, zValue }, 
        { 0.0, 0.0, 0.0 }, { size.x, size.y, 1.0 }))

    updateGpuBuffer(&modelMatrix, directXState.constantBuffers[.MODEL_TRANSFORMATION])
    updateGpuBuffer(&color, directXState.constantBuffers[.COLOR])

    directXState.ctx->DrawIndexed(directXState.indexBuffers[.QUAD].length, 0, 0)
}

renderImageRect :: proc{renderImageRectVec_Float, renderImageRectVec_Int, renderImageRect_Int}

renderImageRect_Int :: proc(rect: ui.Rect, zValue: f32, texture: TextureId) {
    renderImageRectVec_Float({ f32(rect.left), f32(rect.bottom) }, 
        { f32(rect.right - rect.left), f32(rect.top - rect.bottom) }, zValue, texture)
}

renderImageRectVec_Int :: proc(position, size: int2, zValue: f32, texture: TextureId) {
    renderImageRectVec_Float({ f32(position.x), f32(position.y) }, { f32(size.x), f32(size.y) }, zValue, texture)
}

renderImageRectVec_Float :: proc(position, size: float2, zValue: f32, texture: TextureId) {
    ctx := directXState.ctx

    ctx->VSSetShader(directXState.vertexShaders[.BASIC], nil, 0)
    ctx->VSSetConstantBuffers(0, 1, &directXState.constantBuffers[.PROJECTION].gpuBuffer)
    ctx->VSSetConstantBuffers(1, 1, &directXState.constantBuffers[.MODEL_TRANSFORMATION].gpuBuffer)

    ctx->PSSetShader(directXState.pixelShaders[.TEXTURE], nil, 0)
    ctx->PSSetShaderResources(0, 1, &directXState.textures[texture].srv)

    modelMatrix := intrinsics.transpose(getTransformationMatrix(
        { position.x, position.y, zValue }, 
        { 0.0, 0.0, 0.0 }, { size.x, size.y, 1.0 }))

    updateGpuBuffer(&modelMatrix, directXState.constantBuffers[.MODEL_TRANSFORMATION])

    directXState.ctx->DrawIndexed(directXState.indexBuffers[.QUAD].length, 0, 0)
}

renderRectBorder :: proc{renderRectBorderVec_Float, renderRectBorderVec_Int, renderRectBorder_Int}

renderRectBorder_Int :: proc(rect: ui.Rect, thickness, zValue: f32, color: float4) {
    renderRectBorderVec_Float({ f32(rect.left), f32(rect.bottom) }, 
        { f32(rect.right - rect.left), f32(rect.top - rect.bottom) }, thickness, zValue, color)
}

renderRectBorderVec_Int :: proc(position, size: int2, thickness, zValue: f32, color: float4) {
    renderRectBorderVec_Float({ f32(position.x), f32(position.y) }, { f32(size.x), f32(size.y) }, thickness, zValue, color)
}

renderRectBorderVec_Float :: proc(position, size: float2, thickness, zValue: f32, color: float4) {
    renderRect(float2{ position.x, position.y + size.y - thickness }, float2{ size.x, thickness }, zValue, color) // top border
    renderRect(position, float2{ size.x, thickness }, zValue, color) // bottom border
    renderRect(position, float2{ thickness, size.y }, zValue, color) // left border
    renderRect(float2{ position.x + size.x - thickness, position.y }, float2{ thickness, size.y }, zValue, color) // right border
}

renderLine :: proc(text: string, font: ^FontData, position: int2, color: float4, zIndex: f32, containerHeight: i32 = 0) {
    fontListBuffer := directXState.structuredBuffers[.GLYPHS_LIST]
    fontsList := memoryAsSlice(FontGlyphGpu, fontListBuffer.cpuBuffer, fontListBuffer.length)
    
    leftOffset := f32(position.x)
    topOffset := f32(position.y) - font.descent

    if containerHeight > 0 {
        textHeight := getTextHeight(&windowData.font)

        topOffset += f32(containerHeight) / 2.0 - textHeight / 2.0
    }

    for char, index in text {
        fontChar := font.chars[char]

        glyphSize: int2 = { fontChar.rect.right - fontChar.rect.left, fontChar.rect.top - fontChar.rect.bottom }
        glyphPosition: int2 = { i32(leftOffset) + fontChar.offset.x, i32(topOffset) - glyphSize.y - fontChar.offset.y }

        modelMatrix := getTransformationMatrix(
            { f32(glyphPosition.x), f32(glyphPosition.y), zIndex }, 
            { 0.0, 0.0, 0.0 }, 
            { f32(glyphSize.x), f32(glyphSize.y), 1.0 },
        )
        
        fontsList[index] = FontGlyphGpu{
            sourceRect = fontChar.rect,
            targetTransformation = modelMatrix, 
        }
        leftOffset += fontChar.xAdvance
    }

    ctx := directXState.ctx

    ctx->VSSetShader(directXState.vertexShaders[.FONT], nil, 0)
    ctx->VSSetShaderResources(0, 1, &directXState.structuredBuffers[.GLYPHS_LIST].srv)
    ctx->VSSetConstantBuffers(0, 1, &directXState.constantBuffers[.PROJECTION].gpuBuffer)

    ctx->PSSetShader(directXState.pixelShaders[.FONT], nil, 0)
    ctx->PSSetShaderResources(0, 1, &directXState.textures[.FONT].srv)
    ctx->PSSetConstantBuffers(0, 1, &directXState.constantBuffers[.COLOR].gpuBuffer)

    updateGpuBuffer(fontsList, directXState.structuredBuffers[.GLYPHS_LIST])
    color := color // whithout it we won't be able to pass color as a pointer
    updateGpuBuffer(&color, directXState.constantBuffers[.COLOR])
    directXState.ctx->DrawIndexedInstanced(directXState.indexBuffers[.QUAD].length, u32(len(text)), 0, 0, 0)
}

renderCursor :: proc(ctx: ^EditableTextContext, zIndex: f32) {
    cursorWidth :: 3.0

    // if cursor above top line, don't render it
    if ctx.cursorLineIndex < i32(ctx.lineIndex) { return }
    
    // TODO: move it into a separate function
    editorRectSize := ui.getRectSize(ctx.rect)
    maxLinesOnScreen := editorRectSize.y / i32(windowData.font.lineHeight)

    // if cursor bellow bottom line, don't render it
    if ctx.cursorLineIndex > maxLinesOnScreen + i32(ctx.lineIndex) { return }

    topOffset := f32(ctx.rect.top) - f32(ctx.cursorLineIndex - i32(ctx.lineIndex)) * windowData.font.lineHeight
    topOffset += getDecimalPart(ctx.lineIndex) * windowData.font.lineHeight
    topOffset -= windowData.font.lineHeight
    
    // render highlighted cursor line
    renderRect(float2{ f32(ctx.rect.left), topOffset }, 
        float2{ f32(editorRectSize.x), windowData.font.lineHeight }, zIndex + 3, CURSOR_LINE_BG_COLOR)

    leftOffset := f32(ctx.rect.left) + ctx.cursorLeftOffset - f32(ctx.leftOffset)

    if leftOffset < f32(ctx.rect.left) || leftOffset > f32(ctx.rect.right) { return }

    leftOffset = min(f32(ctx.rect.right) - cursorWidth, leftOffset)
    renderRect(float2{ leftOffset, topOffset }, float2{ cursorWidth, windowData.font.lineHeight }, 
        zIndex, CURSOR_COLOR)
}

fillTextBuffer :: proc(ctx: ^EditableTextContext, color: float4, zIndex: f32) -> (i32, i32) {
    //TODO: this looks f*ing stupid!
    shouldRenderCursor := windowData.editableTextCtx == ctx

    fontListBuffer := directXState.structuredBuffers[.GLYPHS_LIST]
    fontsList := memoryAsSlice(FontGlyphGpu, fontListBuffer.cpuBuffer, fontListBuffer.length)

    rectsListBuffer := directXState.structuredBuffers[.RECTS_LIST]
    rectsList := memoryAsSlice(mat4, rectsListBuffer.cpuBuffer, rectsListBuffer.length)

    glyphsCount := 0
    selectionsCount := 0
    hasSelection := ctx.editorState.selection[0] != ctx.editorState.selection[1]
    selectionRange: int2 = {
        i32(min(ctx.editorState.selection[0], ctx.editorState.selection[1])),
        i32(max(ctx.editorState.selection[0], ctx.editorState.selection[1])),
    }
    
    if shouldRenderCursor {
        renderCursor(ctx, zIndex - 3.0)
    }
    
    for glyphIndex, glyph in ctx.glyphsLocations {
        fontChar := windowData.font.chars[glyph.char]

        if hasSelection && glyphIndex >= selectionRange.x && glyphIndex < selectionRange.y {
            //> validate clipping
            originalSelectionRect := ui.toRect(
                float2{ glyph.position.x, f32(glyph.lineStart) }, 
                float2{ fontChar.xAdvance + 2.0, windowData.font.lineHeight + 1.0 })
            // TODO: right now I add 2 to x and 1 to y just to make sure that there's no spaces between selection rects
            // it's better to investigate why it's needed (maybe something with texture filtering????)
            selectionRect := ui.clipRect(ui.toFloatRect(ctx.rect), originalSelectionRect)
            if ui.isValidRect(selectionRect) {
                selectionPosition, selectionSize := ui.fromRect(selectionRect)
                //<

                rectsList[selectionsCount] = getTransformationMatrix(
                    { selectionPosition.x, selectionPosition.y, zIndex - 1.0 }, 
                    { 0.0, 0.0, 0.0 }, 
                    { selectionSize.x, selectionSize.y, 1.0 },
                )
                selectionsCount += 1
            }
        }

        //> validate clipping
        originalGlyphRect := ui.toRect(glyph.position, glyph.size)
        glyphRect := ui.clipRect(ui.toFloatRect(ctx.rect), originalGlyphRect)
        if !ui.isValidRect(glyphRect) {
            continue
        }
        
        offset, scale := ui.normalizeClippedToOriginal(ui.toIntRect(glyphRect), ui.toIntRect(originalGlyphRect))

        glyphPosition, glyphSize := ui.fromRect(glyphRect)
        //<

        modelMatrix := getTransformationMatrix(
            { f32(glyphPosition.x), f32(glyphPosition.y), zIndex - 2.0 }, 
            { 0.0, 0.0, 0.0 }, 
            { f32(glyphSize.x), f32(glyphSize.y), 1.0 },
        )
        
        fontsList[glyphsCount] = FontGlyphGpu{
            sourceRect = fontChar.rect,
            targetTransformation = modelMatrix,
            color = color,
            textureOffset = offset,
            textureScale = scale,
        }
        glyphsCount += 1
    }

    return i32(glyphsCount), i32(selectionsCount)
}

renderLineNumbers :: proc() {
    fileTab := getActiveTab()
    if fileTab == nil { return }

    lineNumbersLeftOffset: i32 = windowData.explorer == nil ? 0 : windowData.explorerWidth // TODO: make it configurable

    maxLinesOnScreen := i32(f32(getEditorSize().y) / windowData.font.lineHeight)
    
    // draw background
    ui.pushCommand(&windowData.uiContext, ui.RectCommand{
        rect = ui.toRect(int2{ -windowData.size.x / 2 + lineNumbersLeftOffset, -windowData.size.y / 2. },
            int2{ windowData.editorPadding.left - lineNumbersLeftOffset, windowData.size.y }),
        bgColor = LINE_NUMBERS_BG_COLOR,
    })
    editorCtx := fileTab.ctx
    topOffset := math.round(f32(windowData.size.y) / 2.0 - windowData.font.lineHeight) - f32(windowData.editorPadding.top)
    topOffset += getDecimalPart(editorCtx.lineIndex) * windowData.font.lineHeight
    
    bgActoins, _ := ui.putEmptyElement(&windowData.uiContext, ui.toRect(int2{ -windowData.size.x / 2 + lineNumbersLeftOffset, -windowData.size.y / 2 },
        int2{ windowData.editorPadding.left - lineNumbersLeftOffset, windowData.size.y }))
    bgClickPosition := int2{ -1, -1 }
    if .SUBMIT in bgActoins {
        bgClickPosition = ui.screenToDirectXCoords(inputState.mousePosition, &windowData.uiContext)
    }

    firstNumber := i32(editorCtx.lineIndex) + 1
    lastNumber := min(i32(len(editorCtx.lines)), i32(editorCtx.lineIndex) + maxLinesOnScreen + 3)

    //debuggerBrakepoints
    for lineNumber in firstNumber..=lastNumber {
        lineNumberStrBuffer := new([255]byte, context.temp_allocator)

        lineNumberStr := strconv.write_int(lineNumberStrBuffer[:], i64(lineNumber), 10)

        leftOffset := -f32(windowData.size.x) / 2.0 + f32(lineNumbersLeftOffset)

        lineRect := ui.Rect{
            top = i32(topOffset + windowData.font.lineHeight),
            bottom = i32(topOffset),
            left = i32(leftOffset),
            right = i32(leftOffset) + windowData.editorPadding.left - lineNumbersLeftOffset,
        }
        if .SUBMIT in bgActoins {
            if ui.isInRect(lineRect, bgClickPosition) {
                toggleBrakepointForLine(fileTab.filePath, lineNumber)
            }
        }

        // TODO: this is slow AF
        for brakepoint in windowData.debuggerBrakepoints {
            if existBrakepointInManager(fileTab.filePath, lineNumber) != -1 {
                ui.pushCommand(&windowData.uiContext, ui.RectCommand{
                    rect = lineRect,
                    bgColor = RED_COLOR,
                })
            }
        }

        if windowData.currentDebuggerInstruction.line == lineNumber && 
            windowData.currentDebuggerInstruction.filePath == fileTab.filePath {
                ui.pushCommand(&windowData.uiContext, ui.RectCommand{
                    rect = lineRect,
                    bgColor = GREEN_COLOR,
                })
        }
        
        ui.pushCommand(&windowData.uiContext, ui.TextCommand{
            text = lineNumberStr,
            position = { i32(leftOffset), i32(topOffset) },
            color = WHITE_COLOR,
        })

        topOffset -= windowData.font.lineHeight
    }
}

// BENCHMARKS:
// +-20000 microseconds with -speed build option without instancing
// +-750 microseconds with -speed build option with instancing
renderText :: proc(glyphsCount: i32, selectionsCount: i32, selectionColor: float4) {
    ctx := directXState.ctx

    //> draw selection
    if selectionsCount > 0 {
        rectsListBuffer := directXState.structuredBuffers[.RECTS_LIST]
        rectsList := memoryAsSlice(mat4, rectsListBuffer.cpuBuffer, rectsListBuffer.length)

        ctx->VSSetShader(directXState.vertexShaders[.MULTIPLE_RECTS], nil, 0)
        ctx->VSSetShaderResources(0, 1, &directXState.structuredBuffers[.RECTS_LIST].srv)
        ctx->VSSetConstantBuffers(0, 1, &directXState.constantBuffers[.PROJECTION].gpuBuffer)

        ctx->PSSetShader(directXState.pixelShaders[.SOLID_COLOR], nil, 0)
        ctx->PSSetConstantBuffers(0, 1, &directXState.constantBuffers[.COLOR].gpuBuffer)

        updateGpuBuffer(rectsList, directXState.structuredBuffers[.RECTS_LIST])
        selectionColor := selectionColor
        updateGpuBuffer(&selectionColor, directXState.constantBuffers[.COLOR])

        directXState.ctx->DrawIndexedInstanced(directXState.indexBuffers[.QUAD].length, u32(selectionsCount), 0, 0, 0)
    }
    //<
    
    //> draw text
    if glyphsCount > 0 {       
        fontListBuffer := directXState.structuredBuffers[.GLYPHS_LIST]
        fontsList := memoryAsSlice(FontGlyphGpu, fontListBuffer.cpuBuffer, fontListBuffer.length)
        
        ctx->VSSetShader(directXState.vertexShaders[.FONT], nil, 0)
        ctx->VSSetShaderResources(0, 1, &directXState.structuredBuffers[.GLYPHS_LIST].srv)
        ctx->VSSetConstantBuffers(0, 1, &directXState.constantBuffers[.PROJECTION].gpuBuffer)

        ctx->PSSetShader(directXState.pixelShaders[.FONT], nil, 0)
        ctx->PSSetShaderResources(0, 1, &directXState.textures[.FONT].srv)
        ctx->PSSetConstantBuffers(0, 1, &directXState.constantBuffers[.COLOR].gpuBuffer)

        updateGpuBuffer(fontsList, directXState.structuredBuffers[.GLYPHS_LIST])
        directXState.ctx->DrawIndexedInstanced(directXState.indexBuffers[.QUAD].length, u32(glyphsCount), 0, 0, 0)
    }
    //<
}