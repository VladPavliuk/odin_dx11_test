package main

import "ui"
import "core:os"
import "vendor:directx/d3d11"
import "vendor:directx/dxgi"
import stbtt "vendor:stb/truetype"

// Atlas oversampling: each glyph is rasterised at this multiple of its display
// size and downsampled by the linear sampler, which sharpens small text and
// improves sub-pixel positioning. 2x2 is stb's recommended high-quality default
// (costs ~4x the atlas area, hence the larger bitmap below).
FONT_OVERSAMPLE_X :: 2
FONT_OVERSAMPLE_Y :: 2

// NOTE: struct is packed, because for GPU no padding allowed
FontGlyphGpu :: struct #packed {
    sourceRect: ui.Rect,
    targetTransformation: mat4,
    color: float4,

    textureOffset: float2,
    textureScale: float2,
}

FontChar :: struct {
    rect: ui.Rect,    // glyph region in the atlas, in (oversampled) texels
    offset: float2,   // screen-space offset from the pen position to the glyph's top-left
    size: float2,     // screen-space size of the glyph quad
    xAdvance: f32,
}

FontData :: struct {
    //ttfFile: []byte,
	ascent: f32,
	descent: f32,
	lineGap: f32,
    lineHeight: f32,
	scale: f32,

    chars: map[rune]FontChar,
    asciiChars: [128]FontChar, // fast-path mirror of `chars` for ASCII runes (see getFontChar)
    kerningTable: map[rune]map[rune]f32,
}

loadFont :: proc(fontPath: string) -> (GpuTexture, FontData) {
    // "SourceCodePro-Medium"
    fileContent, success := os.read_entire_file_from_filename(fontPath)
    // fileContent, success := os.read_entire_file_from_filename("SourceCodePro-Medium.TTF")
    assert(success)
    defer delete(fileContent)
    // defer delete(fontData.ttfFile)

    bitmapSize: int2 = { 1024, 1024 } // larger atlas to fit oversampled glyphs

    // fontChars := make(map[u16]FontChar)
    // charsData: [95]stbtt.bakedchar
    tmpFontBitmap := make([]byte, bitmapSize.x * bitmapSize.y)
    defer delete(tmpFontBitmap)
    // overflow := stbtt.BakeFontBitmap(raw_data(fileContent), 0, 28.0, raw_data(tmpFontBitmap), bitmapSize.x, bitmapSize.y, 32, 95, raw_data(charsData[:]))

    alphabet := "АБВГҐДЕЄЖЗИІЇЙКЛМНОПРСТУФХЦЧШЩЬЮЯабвгґдеєжзиіїйклмнопрстуфхцчшщьюя\t !\"#$%&'()*+,-./0123456789:;<=>?@[\\]^_`{|}~ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
    fontData := BakeFontBitmapCustomChars(fileContent, 20.0, tmpFontBitmap, bitmapSize, alphabet)

    textureDesc := d3d11.TEXTURE2D_DESC{
        Width = u32(bitmapSize.x),
        Height = u32(bitmapSize.y),
        MipLevels = 1,
        ArraySize = 1,
        // NOTE: R8_UNORM (not R8_UINT) so the atlas can be hardware-filtered.
        // UINT textures can only be point-fetched via .Load; UNORM allows linear
        // sampling, which gives us smooth, sub-pixel-correct glyph edges.
        Format = dxgi.FORMAT.R8_UNORM,
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
        pSysMem = raw_data(tmpFontBitmap),
        SysMemPitch = u32(bitmapSize.x),
        SysMemSlicePitch = u32(bitmapSize.x * bitmapSize.y),
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

    return GpuTexture{ texture, srv, bitmapSize }, fontData
    // font: stbtt.fontinfo
    // res := stbtt.InitFont(&font, raw_data(fileContent[:]), 0)
    // assert(res == true)

    // lineHeight: f32 = 80.0
    // fontScale := stbtt.ScaleForPixelHeight(&font, lineHeight)

    // ascent: i32
    // descent: i32
    // lineGap: i32
	// stbtt.GetFontVMetrics(&font, &ascent, &descent, &lineGap)

    // ascent = i32(f32(ascent) * fontScale)
    // descent = i32(f32(descent) * fontScale)
    // lineGap = i32(f32(lineGap) * fontScale)
}

BakeFontBitmapCustomChars :: proc(data: []byte, pixelHeight: f32, bitmap: []byte, bitmapSize: int2, charsList: string) -> FontData {
    font: stbtt.fontinfo

    if !stbtt.InitFont(&font, raw_data(data), 0) {
        panic("Error font parsing")
    }

    ascent, descent, lineGap: i32
    stbtt.GetFontVMetrics(&font, &ascent, &descent, &lineGap)

    scale := stbtt.ScaleForPixelHeight(&font, pixelHeight)
    fontData := FontData{
        ascent = f32(ascent) * scale,
        descent = f32(descent) * scale,
        lineGap = f32(lineGap) * scale,
        scale = scale,
    }
    fontData.lineHeight = fontData.ascent - fontData.descent

    // Collect the codepoints to bake (charsList is UTF-8, so decode to runes).
    runesList := make([dynamic]rune, 0, len(charsList))
    defer delete(runesList)
    for char in charsList {
        append(&runesList, char)
    }

    // Let stb pack + rasterise every glyph with oversampling. PackFontRanges
    // fills packedchar with atlas coords plus sub-pixel-correct screen offsets.
    chardata := make([]stbtt.packedchar, len(runesList))
    defer delete(chardata)

    ranges := []stbtt.pack_range{
        {
            font_size = pixelHeight,
            array_of_unicode_codepoints = raw_data(runesList[:]),
            num_chars = i32(len(runesList)),
            chardata_for_range = &chardata[0],
        },
    }

    spc: stbtt.pack_context
    if stbtt.PackBegin(&spc, raw_data(bitmap), bitmapSize.x, bitmapSize.y, 0, 1, nil) == 0 {
        panic("Failed to initialise font atlas packing")
    }
    stbtt.PackSetOversampling(&spc, FONT_OVERSAMPLE_X, FONT_OVERSAMPLE_Y)
    if stbtt.PackFontRanges(&spc, raw_data(data), 0, raw_data(ranges), 1) == 0 {
        panic("Font atlas is not big enough to fit all glyphs")
    }
    stbtt.PackEnd(&spc)

    for char, i in runesList {
        pc := chardata[i]

        // NOTE: y0 is the glyph's top row in the atlas (smaller texel-y) and y1
        // the bottom row; the shader treats rect.bottom as the top row, rect.top
        // as the bottom row, so map them accordingly.
        fontChar := FontChar{
            rect = ui.Rect{
                left = i32(pc.x0),
                right = i32(pc.x1),
                bottom = i32(pc.y0),
                top = i32(pc.y1),
            },
            offset = { pc.xoff, pc.yoff },
            size = { pc.xoff2 - pc.xoff, pc.yoff2 - pc.yoff },
            xAdvance = pc.xadvance,
        }

        fontData.chars[char] = fontChar
        if char >= 0 && char < 128 { // keep the ASCII fast-path table in sync
            fontData.asciiChars[char] = fontChar
        }
    }

    for aChar in fontData.chars {
        glyphKernings := make(map[rune]f32)

        for bChar in fontData.chars {
            glyphKernings[bChar] = f32(stbtt.GetCodepointKernAdvance(&font, aChar, bChar))
        }

        fontData.kerningTable[aChar] = glyphKernings
    }

    // TODO: make this behaviour configurable
    // NOTE: Since tab symbol has a weird glyph sometimes, just rewrite visual part of it by space glyph
    tabGlyph := fontData.chars['\t']
    spaceGlyph := fontData.chars[' ']

    tabGlyph.offset = spaceGlyph.offset
    tabGlyph.rect = spaceGlyph.rect
    tabGlyph.size = spaceGlyph.size

    fontData.chars['\t'] = tabGlyph
    fontData.asciiChars['\t'] = tabGlyph // '\t' (9) lives in the ASCII fast-path table too

    return fontData
}

getTextHeight :: proc(font: rawptr) -> f32 {
    assert(font != nil)

    return (^FontData)(font).lineHeight
}

// Fast-path glyph lookup: editor text is overwhelmingly ASCII, so index a flat
// array for those runes instead of hashing the map on every character. Non-ASCII
// falls back to the map. Behaviour matches the map (zero value for unbaked glyphs).
getFontChar :: #force_inline proc(font: ^FontData, char: rune) -> FontChar {
    if char >= 0 && char < 128 {
        return font.asciiChars[char]
    }
    return font.chars[char]
}

getTextWidth :: proc(text: string, font: rawptr) -> f32 {
    assert(font != nil)
    fontData := (^FontData)(font)
    width: f32 = 0.0

    for char in text {
        width += getFontChar(fontData, char).xAdvance
    }

    return width
}
