package main

import "vendor:directx/dxgi"
import "vendor:directx/d3d11"

DirectXState :: struct {
    device: ^d3d11.IDevice,
    ctx: ^d3d11.IDeviceContext,
    swapchain: ^dxgi.ISwapChain1,
    backBuffer: ^d3d11.ITexture2D,
    backBufferView: ^d3d11.IRenderTargetView,
    depthBuffer: ^d3d11.ITexture2D,
    depthBufferView: ^d3d11.IDepthStencilView,
    rasterizerState: ^d3d11.IRasterizerState,
    depthStencilState: ^d3d11.IDepthStencilState,
    blendState: ^d3d11.IBlendState,
	samplerState: ^d3d11.ISamplerState,
	fontSamplerState: ^d3d11.ISamplerState,

    textures: [TextureId]GpuTexture,
    vertexBuffers: [GpuBufferType]GpuBuffer,
    indexBuffers: [GpuBufferType]GpuBuffer,
    constantBuffers: [GpuConstantBufferType]GpuBuffer,
    structuredBuffers: [GpuStructuredBufferType]GpuBuffer,

    inputLayouts: [InputLayoutType]^d3d11.IInputLayout,

    vertexShaders: [VertexShaderType]^d3d11.IVertexShader,
    pixelShaders: [PixelShaderType]^d3d11.IPixelShader,

    // NOTE: mapps enum value of texutre id to it's index in 2d texture for icons
    iconsIndexesMapping: map[TextureId]i32,
}

directXState: DirectXState

initDirectX :: proc() {
    baseDevice: ^d3d11.IDevice
	baseDeviceContext: ^d3d11.IDeviceContext

    featureLevels := [?]d3d11.FEATURE_LEVEL{._11_0}
    deviceFlags: d3d11.CREATE_DEVICE_FLAGS

    when ODIN_DEBUG {
        deviceFlags += {.DEBUG}
    }
	res := d3d11.CreateDevice(nil, .HARDWARE, nil, deviceFlags, &featureLevels[0], len(featureLevels), d3d11.SDK_VERSION, &baseDevice, nil, &baseDeviceContext)
    assert(res == 0)
    defer baseDevice->Release()
    defer baseDeviceContext->Release()

	res = baseDevice->QueryInterface(d3d11.IDevice_UUID, (^rawptr)(&directXState.device))
    assert(res == 0)

	res = baseDeviceContext->QueryInterface(d3d11.IDeviceContext_UUID, (^rawptr)(&directXState.ctx))
    assert(res == 0)

	dxgiDevice: ^dxgi.IDevice
	res = directXState.device->QueryInterface(dxgi.IDevice_UUID, (^rawptr)(&dxgiDevice))
    assert(res == 0)
    defer dxgiDevice->Release()

    dxgiAdapter: ^dxgi.IAdapter
	res = dxgiDevice->GetAdapter(&dxgiAdapter)
    assert(res == 0)
    defer dxgiAdapter->Release()

	dxgiFactory: ^dxgi.IFactory2
	res = dxgiAdapter->GetParent(dxgi.IFactory2_UUID, (^rawptr)(&dxgiFactory))
    assert(res == 0)
    defer dxgiFactory->Release()

    swapchainDesc := dxgi.SWAP_CHAIN_DESC1{
		Width  = 0,
		Height = 0,
		Format = .R8G8B8A8_UNORM,
		Stereo = false,
		SampleDesc = {
			Count = 1,
			Quality = 0,
		},
		BufferUsage = { .RENDER_TARGET_OUTPUT },
		BufferCount = 2,
		Scaling = .NONE, // previouslly it was STRETCH
		SwapEffect = .FLIP_DISCARD,
		AlphaMode = .UNSPECIFIED,
		Flags = { },
	}

    assert(windowData.parentHwnd != nil)
	res = dxgiFactory->CreateSwapChainForHwnd(directXState.device, windowData.parentHwnd, &swapchainDesc, nil, nil, &directXState.swapchain)
    assert(res == 0)

	res = directXState.swapchain->GetBuffer(0, d3d11.ITexture2D_UUID, (^rawptr)(&directXState.backBuffer))
    assert(res == 0)

	res = directXState.device->CreateRenderTargetView(directXState.backBuffer, nil, &directXState.backBufferView)
    assert(res == 0)

    depthBufferDesc: d3d11.TEXTURE2D_DESC
	directXState.backBuffer->GetDesc(&depthBufferDesc)
    depthBufferDesc.Format = .D24_UNORM_S8_UINT
	depthBufferDesc.BindFlags = {.DEPTH_STENCIL}

	res = directXState.device->CreateTexture2D(&depthBufferDesc, nil, &directXState.depthBuffer)
    assert(res == 0)

	res = directXState.device->CreateDepthStencilView(directXState.depthBuffer, nil, &directXState.depthBufferView)
    assert(res == 0)

    rasterizerDesc := d3d11.RASTERIZER_DESC{
		FillMode = .SOLID,
		CullMode = .BACK,
        // ScissorEnable = true,
	}
	res = directXState.device->CreateRasterizerState(&rasterizerDesc, &directXState.rasterizerState)
    assert(res == 0)

    samplerDesc := d3d11.SAMPLER_DESC{
        Filter = .MIN_POINT_MAG_LINEAR_MIP_POINT, // originally it was MIN_MAG_MIP_LINEAR, but for some reasons, it crops image???
        AddressU = .WRAP,
        AddressV = .WRAP,
        AddressW = .WRAP,
        ComparisonFunc = .NEVER,
        MinLOD = 0,
        MaxLOD = d3d11.FLOAT32_MAX,
    }
    res = directXState.device->CreateSamplerState(&samplerDesc, &directXState.samplerState)
    assert(res == 0)

    // Dedicated sampler for the glyph atlas: linear filtering so fractional glyph
    // positions are smoothly interpolated, and CLAMP addressing so sampling at a
    // glyph's edge never wraps into a neighbouring glyph on the opposite side.
    fontSamplerDesc := d3d11.SAMPLER_DESC{
        Filter = .MIN_MAG_MIP_LINEAR,
        AddressU = .CLAMP,
        AddressV = .CLAMP,
        AddressW = .CLAMP,
        ComparisonFunc = .NEVER,
        MinLOD = 0,
        MaxLOD = d3d11.FLOAT32_MAX,
    }
    res = directXState.device->CreateSamplerState(&fontSamplerDesc, &directXState.fontSamplerState)
    assert(res == 0)

    viewport := d3d11.VIEWPORT{
        0, 0,
        f32(depthBufferDesc.Width), f32(depthBufferDesc.Height),
        0, 1,
    }

    directXState.ctx->RSSetViewports(1, &viewport)

    depthStencilDesc := d3d11.DEPTH_STENCIL_DESC{
		DepthEnable    = true,
		DepthWriteMask = .ALL,
		DepthFunc      = .LESS,
	}
	directXState.device->CreateDepthStencilState(&depthStencilDesc, &directXState.depthStencilState)

    // blending
    blendTargetDesc := d3d11.RENDER_TARGET_BLEND_DESC{
        BlendEnable = true,
        SrcBlend = d3d11.BLEND.SRC_ALPHA,
        DestBlend = d3d11.BLEND.INV_SRC_ALPHA,
        BlendOp = d3d11.BLEND_OP.ADD,
        SrcBlendAlpha = d3d11.BLEND.SRC_ALPHA,
        DestBlendAlpha = d3d11.BLEND.INV_SRC_ALPHA,
        BlendOpAlpha = d3d11.BLEND_OP.ADD,
        RenderTargetWriteMask = u8(d3d11.COLOR_WRITE_ENABLE_ALL),
    }

    blendDesc := d3d11.BLEND_DESC{
        IndependentBlendEnable = true,
    }
    blendDesc.RenderTarget[0] = blendTargetDesc

	res = directXState->device->CreateBlendState(&blendDesc, &directXState.blendState)
    assert(res == 0)
}

clearDirectX :: proc() {
	directXState.swapchain->SetFullscreenState(false, nil)

    directXState.device->Release()
    directXState.ctx->Release()
    directXState.swapchain->Release()
    directXState.backBuffer->Release()
    directXState.backBufferView->Release()
    directXState.depthBuffer->Release()
    directXState.depthBufferView->Release()
    directXState.rasterizerState->Release()
    directXState.depthStencilState->Release()
    directXState.samplerState->Release()
    directXState.fontSamplerState->Release()
    directXState.blendState->Release()

    delete(directXState.iconsIndexesMapping)

    for texture in directXState.textures {
        if texture.buffer != nil { texture.buffer->Release() }
        if texture.srv != nil { texture.srv->Release() }
    }

    for buffer in directXState.vertexBuffers {
        buffer.gpuBuffer->Release()
        free(buffer.cpuBuffer)
    }

    for buffer in directXState.indexBuffers {
        buffer.gpuBuffer->Release()
        free(buffer.cpuBuffer)
    }

    for buffer in directXState.constantBuffers {
        buffer.gpuBuffer->Release()
        if buffer.cpuBuffer != nil { free(buffer.cpuBuffer) }
    }

    for buffer in directXState.structuredBuffers {
        buffer.gpuBuffer->Release()
        buffer.srv->Release()
        if buffer.cpuBuffer != nil { free(buffer.cpuBuffer) }
    }

    for inputLayout in directXState.inputLayouts {
        inputLayout->Release()
    }

    for vertexShader in directXState.vertexShaders {
        vertexShader->Release()
    }

    for pixelShader in directXState.pixelShaders {
        pixelShader->Release()
    }

    directXState = {}
}