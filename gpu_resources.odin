#+feature dynamic-literals
package main

import "vendor:directx/d3d11"
import "vendor:directx/dxgi"
import "vendor:directx/d3d_compiler"

import "base:runtime"

import "core:mem"
import "core:image"
import "core:image/png" // since png module has autoload function, don't remove it!

_ :: png._MAX_IDAT

import "core:bytes"

TextureId :: enum {
    NONE,
    FONT,
    CIRCLE,
    PIN,
    ICONS_ARRAY,
    
    CLOSE_ICON,
    CHECK_ICON,

    // file extensions icons
    TXT_FILE_ICON,
    C_FILE_ICON,
    C_PLUS_PLUS_FILE_ICON,
    C_SHARP_FILE_ICON,
    JS_FILE_ICON,
    ARROW_DOWN_ICON,
    ARROW_RIGHT_ICON,
    BRAKEPOINT_ICON,

    // explorer actions buttons icons
    COLLAPSE_FILES_ICON,
    JUMP_TO_CURRENT_FILE_ICON,
}

GpuTexture :: struct {
    buffer: ^d3d11.ITexture2D,    
    srv: ^d3d11.IShaderResourceView,
    size: int2,  
}

GpuBufferType :: enum {
    QUAD,
}

RectWithColor :: struct #packed {
    transformation: mat4,
    color: float4,   
}

RectWithImage :: struct #packed {
    transformation: mat4,
    imageIndex: i32,
    textureOffset: float2,
    textureScale: float2,
}

GpuStructuredBufferType :: enum {
    GLYPHS_LIST,
    RECTS_LIST,
    RECTS_WITH_COLOR_LIST,
    RECTS_WITH_IMAGE_LIST,
}

GpuBuffer :: struct {
	gpuBuffer: ^d3d11.IBuffer,
    srv: ^d3d11.IShaderResourceView,
	cpuBuffer: rawptr,
    length: u32,
    strideSize: u32,
	itemType: typeid,
}

VertexShaderType :: enum {
    BASIC,
    MULTIPLE_RECTS,
    RECTS_WITH_COLOR,
    RECTS_WITH_IMAGE,
    FONT,
}

PixelShaderType :: enum {
    SOLID_COLOR,
    TEXTURE,
    FONT,
    RECTS_WITH_COLOR,
    RECTS_WITH_IMAGE,
}

InputLayoutType :: enum {
    POSITION_AND_TEXCOORD,
}

GpuConstantBufferType :: enum {
    FONT_GLYPH_LOCATION,
    PROJECTION,
    MODEL_TRANSFORMATION,
    COLOR,
}

initGpuResources :: proc() {
    loadTextures()

    vertexShader, blob := compileVertexShader(#load("./shaders/basic_vs.hlsl"))
    defer blob->Release()

    inputLayoutDesc := [?]d3d11.INPUT_ELEMENT_DESC{
        { "POSITION", 0, dxgi.FORMAT.R32G32B32_FLOAT, 0, 0, d3d11.INPUT_CLASSIFICATION.VERTEX_DATA, 0 },
        { "TEXCOORD", 0, dxgi.FORMAT.R32G32_FLOAT, 0, d3d11.APPEND_ALIGNED_ELEMENT, d3d11.INPUT_CLASSIFICATION.VERTEX_DATA, 0 },
    }

    inputLayout: ^d3d11.IInputLayout
    hr := directXState.device->CreateInputLayout(raw_data(inputLayoutDesc[:]), len(inputLayoutDesc), blob->GetBufferPointer(), blob->GetBufferSize(), &inputLayout)
    assert(hr == 0)

    directXState.vertexShaders[.BASIC] = vertexShader 
    directXState.vertexShaders[.FONT], _ = compileVertexShader(#load("./shaders/font_vs.hlsl"))
    directXState.vertexShaders[.MULTIPLE_RECTS], _ = compileVertexShader(#load("./shaders/multiple_rects_vs.hlsl"))
    directXState.vertexShaders[.RECTS_WITH_COLOR], _ = compileVertexShader(#load("./shaders/rects_with_color/vs.hlsl"))
    directXState.vertexShaders[.RECTS_WITH_IMAGE], _ = compileVertexShader(#load("./shaders/rects_with_image/vs.hlsl"))
    directXState.pixelShaders[.FONT] = compilePixelShader(#load("./shaders/font_ps.hlsl"))
    directXState.pixelShaders[.SOLID_COLOR] = compilePixelShader(#load("./shaders/solid_color_ps.hlsl"))
    directXState.pixelShaders[.TEXTURE] = compilePixelShader(#load("./shaders/texture_ps.hlsl"))
    directXState.pixelShaders[.RECTS_WITH_COLOR] = compilePixelShader(#load("./shaders/rects_with_color/ps.hlsl"))
    directXState.pixelShaders[.RECTS_WITH_IMAGE] = compilePixelShader(#load("./shaders/rects_with_image/ps.hlsl"))
    directXState.inputLayouts[.POSITION_AND_TEXCOORD] = inputLayout
    
    VertexItem :: struct {
        position: float3,
        texcoord: float2,
    }

    quadVertices := make([]VertexItem, 4)
    quadVertices[0] = VertexItem{ {0.0, 0.0, 0.0}, {0.0, 1.0} } 
    quadVertices[1] = VertexItem{ {0.0, 1.0, 0.0}, {0.0, 0.0} } 
    quadVertices[2] = VertexItem{ {1.0, 1.0, 0.0}, {1.0, 0.0} } 
    quadVertices[3] = VertexItem{ {1.0, 0.0, 0.0}, {1.0, 1.0} }

    directXState.vertexBuffers[.QUAD] = createVertexBuffer(quadVertices[:])
    
    indices := make([]u32, 6)
    indices[0] = 0 
    indices[1] = 1 
    indices[2] = 2
    indices[3] = 0
    indices[4] = 2
    indices[5] = 3
    // indices := []u32{
    //     0,1,2,
    //     0,2,3,
    // }
    directXState.indexBuffers[.QUAD] = createIndexBuffer(indices[:])

    directXState.constantBuffers[.FONT_GLYPH_LOCATION] = createConstantBuffer(FontChar, nil)

    // camera
    viewMatrix := getOrthoraphicsMatrix(f32(windowData.size.x), f32(windowData.size.y), 0.1, windowData.maxZIndex + 1.0)
    directXState.constantBuffers[.PROJECTION] = createConstantBuffer(mat4, &viewMatrix)

    directXState.constantBuffers[.MODEL_TRANSFORMATION] = createConstantBuffer(mat4, nil)
    directXState.constantBuffers[.COLOR] = createConstantBuffer(float4, &float4{ 0.0, 0.0, 0.0, 1.0 })

    fontGlyphs := make([]FontGlyphGpu, 15000)
    directXState.structuredBuffers[.GLYPHS_LIST] = createStructuredBuffer(fontGlyphs)

    rectsList := make([]mat4, 15000)
    directXState.structuredBuffers[.RECTS_LIST] = createStructuredBuffer(rectsList)
    
    rectsWithColorList := make([]RectWithColor, 300)
    directXState.structuredBuffers[.RECTS_WITH_COLOR_LIST] = createStructuredBuffer(rectsWithColorList)
    
    rectsWithImageList := make([]RectWithImage, 300)
    directXState.structuredBuffers[.RECTS_WITH_IMAGE_LIST] = createStructuredBuffer(rectsWithImageList)
}

memoryAsSlice :: proc($T: typeid, pointer: rawptr, #any_int length: int) -> []T {
    return transmute([]T)runtime.Raw_Slice{pointer, length}
}

loadTextures :: proc() {
    textures := map[TextureId]string{
        .CLOSE_ICON = #load("./resources/images/close_icon.png"),
        .CHECK_ICON = #load("./resources/images/check_icon.png"),
        .CIRCLE = #load("./resources/images/circle.png"),
        .PIN = #load("./resources/images/pin_icon.png"),
        .TXT_FILE_ICON = #load("./resources/images/txt_file_icon.png"),
        .C_FILE_ICON = #load("./resources/images/c_file_icon.png"),
        .C_PLUS_PLUS_FILE_ICON = #load("./resources/images/c_plus_plus_file_icon.png"),
        .C_SHARP_FILE_ICON = #load("./resources/images/c_sharp_file_icon.png"),
        .JS_FILE_ICON = #load("./resources/images/js_file_icon.png"),
        .ARROW_DOWN_ICON = #load("./resources/images/arrow_down.png"),
        .ARROW_RIGHT_ICON = #load("./resources/images/arrow_right.png"),
        .BRAKEPOINT_ICON = #load("./resources/images/brakepoint_icon.png"),
        .COLLAPSE_FILES_ICON = #load("./resources/images/collapse_files_icon.png"),
        .JUMP_TO_CURRENT_FILE_ICON = #load("./resources/images/jump_current_file_icon.png"),
    }
    defer delete(textures)

    for texture, data in textures {
        directXState.textures[texture] = loadTextureFromImage(transmute([]u8)data)
    }

    directXState.textures[.FONT], windowData.font = loadFont("c:/windows/fonts/arial.TTF")

    directXState.textures[.ICONS_ARRAY] = initIcons2DTexture({ // 702 microseconds
        .CLOSE_ICON,
        .CHECK_ICON,
        .CIRCLE,
        .PIN,
        .TXT_FILE_ICON,
        .C_FILE_ICON,
        .C_PLUS_PLUS_FILE_ICON,
        .C_SHARP_FILE_ICON,
        .JS_FILE_ICON,
        .ARROW_DOWN_ICON,
        .ARROW_RIGHT_ICON,
        .BRAKEPOINT_ICON,
        .COLLAPSE_FILES_ICON,
        .JUMP_TO_CURRENT_FILE_ICON,
    })
}

compileVertexShader :: proc(fileContent: string) -> (^d3d11.IVertexShader, ^d3d11.IBlob) {
    blob: ^d3d11.IBlob
    errMessageBlob: ^d3d11.IBlob = nil
    defer if errMessageBlob != nil { errMessageBlob->Release() }

	hr := d3d_compiler.Compile(raw_data(fileContent), len(fileContent), nil, nil, nil, 
        "main", "vs_5_0", 0, 0, &blob, &errMessageBlob)
    if errMessageBlob != nil {
        panic(string(cstring(errMessageBlob->GetBufferPointer())))
    } 
    assert(hr == 0)

    shader: ^d3d11.IVertexShader
    hr = directXState.device->CreateVertexShader(blob->GetBufferPointer(), blob->GetBufferSize(), nil, &shader)
    assert(hr == 0)
    return shader, blob
}

compilePixelShader :: proc(fileContent: string) -> ^d3d11.IPixelShader {
    blob: ^d3d11.IBlob
    defer blob->Release()

    errMessageBlob: ^d3d11.IBlob = nil
    defer if errMessageBlob != nil { errMessageBlob->Release() }

    hr := d3d_compiler.Compile(raw_data(fileContent), len(fileContent), nil, nil, nil, 
        "main", "ps_5_0", 0, 0, &blob, &errMessageBlob)
    if errMessageBlob != nil {
        panic(string(cstring(errMessageBlob->GetBufferPointer())))
    }
    assert(hr == 0)

    shader: ^d3d11.IPixelShader
    hr = directXState.device->CreatePixelShader(blob->GetBufferPointer(), blob->GetBufferSize(), nil, &shader)
    assert(hr == 0)
    return shader   
}

createVertexBuffer :: proc(items: []$T) -> GpuBuffer {
    bufferDesc := d3d11.BUFFER_DESC{
        ByteWidth = u32(len(items) * size_of(T)),
        Usage = d3d11.USAGE.DEFAULT,
        BindFlags = {d3d11.BIND_FLAG.VERTEX_BUFFER},
        CPUAccessFlags = {},
        MiscFlags = {},
        StructureByteStride = size_of(T),
    }

    data := d3d11.SUBRESOURCE_DATA{
        pSysMem = raw_data(items[:]),
    }

    buffer: ^d3d11.IBuffer
    hr := directXState.device->CreateBuffer(&bufferDesc, &data, &buffer)
    assert(hr == 0)

    return GpuBuffer{
        cpuBuffer = raw_data(items[:]),
        gpuBuffer = buffer,
        length = u32(len(items)),
        strideSize = size_of(T),
        itemType = typeid_of(T),
    }
}

createIndexBuffer :: proc(indices: []u32) -> GpuBuffer {
    bufferDesc := d3d11.BUFFER_DESC{
        ByteWidth = u32(len(indices) * size_of(u32)),
        Usage = d3d11.USAGE.DEFAULT,
        BindFlags = {d3d11.BIND_FLAG.INDEX_BUFFER},
        CPUAccessFlags = {},
        MiscFlags = {},
        StructureByteStride = size_of(u32),
    }

    data := d3d11.SUBRESOURCE_DATA{
        pSysMem = raw_data(indices[:]),
    }

    buffer: ^d3d11.IBuffer
    hr := directXState.device->CreateBuffer(&bufferDesc, &data, &buffer)
    assert(hr == 0)

    return GpuBuffer{
        cpuBuffer = raw_data(indices[:]),
        gpuBuffer = buffer,
        length = u32(len(indices)),
        strideSize = size_of(u32),
        itemType = typeid_of(u32),
    }
}

createConstantBuffer :: proc($T: typeid, initialData: ^T) -> GpuBuffer {
    bufferSize: u32 = size_of(T)

    desc := d3d11.BUFFER_DESC{
        ByteWidth = bufferSize + (16 - bufferSize % 16),
        Usage = d3d11.USAGE.DYNAMIC,
        BindFlags = {d3d11.BIND_FLAG.CONSTANT_BUFFER},
        CPUAccessFlags = {.WRITE},
        MiscFlags = {},
    }
    
    data := d3d11.SUBRESOURCE_DATA{}

    hr: d3d11.HRESULT
    buffer: ^d3d11.IBuffer
    if (initialData != nil) {
        data.pSysMem = initialData
        hr = directXState.device->CreateBuffer(&desc, &data, &buffer)
    } else {
        hr = directXState.device->CreateBuffer(&desc, nil, &buffer)
    }
    assert(hr == 0)

    return GpuBuffer {
        gpuBuffer = buffer,
        cpuBuffer = nil,
        length = 1,
        strideSize = desc.ByteWidth,
        itemType = T,
    }
}

updateGpuBuffer :: proc{updateGpuBuffer_SingleItem, updateGpuBuffer_ArrayItems}

updateGpuBuffer_SingleItem :: proc(data: ^$T, buffer: GpuBuffer) {
    sb: d3d11.MAPPED_SUBRESOURCE
    hr := directXState.ctx->Map(buffer.gpuBuffer, 0, d3d11.MAP.WRITE_DISCARD, {}, &sb)
    defer directXState.ctx->Unmap(buffer.gpuBuffer, 0)

    assert(hr == 0)
    mem.copy(sb.pData, data, size_of(data^))
}

updateGpuBuffer_ArrayItems :: proc(data: []$T, buffer: GpuBuffer) {
    sb: d3d11.MAPPED_SUBRESOURCE
    hr := directXState.ctx->Map(buffer.gpuBuffer, 0, d3d11.MAP.WRITE_DISCARD, {}, &sb)
    defer directXState.ctx->Unmap(buffer.gpuBuffer, 0)

    assert(hr == 0)
    mem.copy(sb.pData, raw_data(data[:]), len(data) * size_of(T))
}

createStructuredBuffer :: proc{createStructuredBuffer_InitData, createStructuredBuffer_NoInitData}

createStructuredBuffer_InitData :: proc(items: []$T) -> GpuBuffer {
    bufferDesc := d3d11.BUFFER_DESC{
        ByteWidth = u32(len(items) * size_of(T)),
        Usage = d3d11.USAGE.DYNAMIC,
        BindFlags = {d3d11.BIND_FLAG.SHADER_RESOURCE},
        CPUAccessFlags = {.WRITE},
        MiscFlags = {.BUFFER_STRUCTURED},
        StructureByteStride = size_of(T),
    }

    data := d3d11.SUBRESOURCE_DATA{
        pSysMem = raw_data(items[:]),
    }

    buffer: ^d3d11.IBuffer
    hr := directXState.device->CreateBuffer(&bufferDesc, &data, &buffer)
    assert(hr == 0)

    srvDesc := d3d11.SHADER_RESOURCE_VIEW_DESC{
        Format = .UNKNOWN,
        ViewDimension = .BUFFER,
        Buffer = {
            FirstElement = 0,
            NumElements = u32(len(items)),
        },
    }

    srv: ^d3d11.IShaderResourceView
    hr = directXState->device->CreateShaderResourceView(buffer, &srvDesc, &srv)
    assert(hr == 0)

    return GpuBuffer{
        cpuBuffer = raw_data(items),
        gpuBuffer = buffer,
        srv = srv,
        length = u32(len(items)),
        strideSize = size_of(T),
        itemType = typeid_of(T),
    }
}

createStructuredBuffer_NoInitData :: proc(length: u32, $T: typeid) -> GpuBuffer {
    bufferDesc := d3d11.BUFFER_DESC{
        ByteWidth = length * size_of(T),
        Usage = d3d11.USAGE.DYNAMIC,
        BindFlags = {d3d11.BIND_FLAG.SHADER_RESOURCE},
        CPUAccessFlags = {.WRITE},
        MiscFlags = {.BUFFER_STRUCTURED},
        StructureByteStride = size_of(T),
    }

    buffer: ^d3d11.IBuffer
    hr := directXState.device->CreateBuffer(&bufferDesc, nil, &buffer)
    assert(hr == 0)

    srvDesc := d3d11.SHADER_RESOURCE_VIEW_DESC{
        Format = .UNKNOWN,
        ViewDimension = .BUFFER,
        Buffer = {
            FirstElement = 0,
            NumElements = length,
        },
    }

    srv: ^d3d11.IShaderResourceView
    hr = directXState->device->CreateShaderResourceView(buffer, &srvDesc, &srv)
    assert(hr == 0)

    return GpuBuffer{
        cpuBuffer = nil,
        gpuBuffer = buffer,
        srv = srv,
        length = length,
        strideSize = size_of(T),
        itemType = typeid_of(T),
    }
}

initIcons2DTexture :: proc(icons: []TextureId) -> GpuTexture {
    for icon, index in icons {
        directXState.iconsIndexesMapping[icon] = i32(index)
    }

    return createTexture2DArray(icons)
}

createTexture2DArray :: proc(textures: []TextureId) -> GpuTexture {
    assert(len(textures) > 0)
    arrayTexture: GpuTexture
    texturesCount := u32(len(textures))
    textureDesc: d3d11.TEXTURE2D_DESC
    
    // NOTE: this approach assumes that all images the same format
    directXState.textures[textures[0]].buffer->GetDesc(&textureDesc)

    textureDesc.ArraySize = texturesCount

    hr := directXState.device->CreateTexture2D(&textureDesc, nil, &arrayTexture.buffer)
    assert(hr == 0)

    srvDesc := d3d11.SHADER_RESOURCE_VIEW_DESC {
        Format = textureDesc.Format,
        ViewDimension = .TEXTURE2DARRAY,
        Texture2DArray = {
            MostDetailedMip = 0,
            MipLevels = 1,
            ArraySize = texturesCount,
            FirstArraySlice = 0,
        },
    }

	hr = directXState.device->CreateShaderResourceView(arrayTexture.buffer, &srvDesc, &arrayTexture.srv)
	assert(hr == 0)

    // copy data into textures array
    for textureId, index in textures {
		directXState.ctx->CopySubresourceRegion(arrayTexture.buffer, u32(index), 0, 0, 0,
            directXState.textures[textureId].buffer, 0, nil)
    }

    return arrayTexture
}

loadTextureFromImage :: proc(imageFileContent: []u8) -> GpuTexture {
    parsedImage, imageErr := image.load_from_bytes(imageFileContent)
    assert(imageErr == nil, "Couldn't parse image")
    defer image.destroy(parsedImage)

    image.alpha_add_if_missing(parsedImage)

    bitmap := bytes.buffer_to_bytes(&parsedImage.pixels)

    textureDesc := d3d11.TEXTURE2D_DESC{
        Width = u32(parsedImage.width), 
        Height = u32(parsedImage.height),
        MipLevels = 1,
        ArraySize = 1,
        Format = dxgi.FORMAT.R8G8B8A8_UNORM,
        SampleDesc = {
            Count = 1,
            Quality = 0,
        },
        Usage = d3d11.USAGE.DEFAULT,
        BindFlags = { d3d11.BIND_FLAG.SHADER_RESOURCE },
        CPUAccessFlags = {},
        MiscFlags = {},
    }

    data := d3d11.SUBRESOURCE_DATA{
        pSysMem = raw_data(bitmap),
        SysMemPitch = u32(parsedImage.width * parsedImage.channels), // TODO: remove hardcoded 4 and actually compute it
        SysMemSlicePitch = u32(parsedImage.width * parsedImage.height * parsedImage.channels),
    }

    texture: ^d3d11.ITexture2D
    hr := directXState.device->CreateTexture2D(&textureDesc, &data, &texture)
    assert(hr == 0)
    
    srvDesc := d3d11.SHADER_RESOURCE_VIEW_DESC{
        Format = textureDesc.Format,
        ViewDimension = d3d11.SRV_DIMENSION.TEXTURE2D,
        Texture2D = {
            MipLevels = 1,
        },
    }

    srv: ^d3d11.IShaderResourceView
    hr = directXState.device->CreateShaderResourceView(texture, &srvDesc, &srv)
    assert(hr == 0)

    return GpuTexture{ texture, srv, { i32(parsedImage.width), i32(parsedImage.height) } }
}