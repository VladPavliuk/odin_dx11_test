Texture2D<float> rasterizedGlyphsTexture : TEXTURE : register(t0);
SamplerState fontSampler : register(s1);

// cbuffer solidColorCB : register(b0)
// {
//     float4 color;
// }

struct PSInput
{
    float4 positionSV : SV_POSITION;
    float2 texcoord : TEXCOORD;
    float4 glyphLocation : GLYPH_LOCATION;
    float4 color: COLOR;

    float2 textureOffset : TEX_OFFSET;
    float2 textureScale : TEX_SCALE;
};

struct PSOutput
{
    float4 pixelColor : SV_TARGET0;
    // float objectItemId : SV_TARGET1;
};

PSOutput main(PSInput input)
{
    float4 glyphLocation = input.glyphLocation;
    PSOutput output;

    float2 textureCoords = input.textureOffset + input.texcoord * input.textureScale;

    // Position (in texels) of this fragment inside the glyph's atlas rect.
    // glyphLocation = sourceRect = (top, bottom, left, right).
    // Inset by half a texel on every edge so bilinear sampling maps [0,1] across
    // the glyph's texel *centres* ([left+0.5 .. right-0.5]) rather than its cell
    // *edges*. Without this the filter reaches across the cell boundary into the
    // neighbouring glyph, which showed up as faint edge bleed once the atlas was
    // oversampled.
    float2 glyphTexels = float2(glyphLocation.w - glyphLocation.z, glyphLocation.x - glyphLocation.y);
    float2 texelCoord = float2(
        glyphLocation.z + 0.5 + (glyphTexels.x - 1.0) * textureCoords.x,
        glyphLocation.y + 0.5 + (glyphTexels.y - 1.0) * textureCoords.y);

    // Convert to normalised UVs and linearly sample the coverage. Because the
    // running advance produces fractional glyph positions, this interpolates
    // between texels (sub-pixel anti-aliasing) instead of snapping like .Load did.
    float2 atlasSize;
    rasterizedGlyphsTexture.GetDimensions(atlasSize.x, atlasSize.y);
    float coverage = rasterizedGlyphsTexture.SampleLevel(fontSampler, texelCoord / atlasSize, 0);

    // Gamma-correct the coverage so anti-aliased edges keep their perceived
    // stroke weight (the back buffer is plain UNORM, so blending happens in
    // gamma space). 1.0 == off; raise GAMMA to make text appear a touch bolder.
    // abs() is a no-op here (coverage is always in [0,1] from the UNORM atlas) but
    // silences compiler warning X3571 about pow() with a possibly-negative base.
    const float GAMMA = 0.9;
    coverage = pow(abs(coverage), 1.0 / GAMMA);

    float4 color = input.color;
    output.pixelColor = float4(color.x, color.y, color.z, color.w * coverage);

    // output.pixelColor = float4(1.0, 0.0, 1.0, 1.0);
    // output.objectItemId = (float) input.objectItemId;

    return output;
}
