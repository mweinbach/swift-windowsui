// swift-format-ignore-file
// Embedded HLSL shader source uses raw string literals; opting out so
// swift-format does not mangle their indentation.

import WinSDK
import WinSDK.DirectX

private let glyphShaderSource = batchClipShaderSource + "\n" + #"""
struct GlyphInstance {
    float screenX, screenY, screenW, screenH;
    float atlasU0, atlasV0, atlasU1, atlasV1;
    float colorR, colorG, colorB, colorA;
    float clipX, clipY, clipWidth, clipHeight;
    float clipCornerRadius;
    // Rotation about the glyph cell's centre; preserve the original padding.
    float rotationRadians;
    float pad1, pad2;
    // Original clip geometry, appended for a 112-byte stride. Mirrors
    // GlyphPrimitive, pinned by GPUIPrimitiveLayoutCoherenceTests.
    float clipCornerRadiusTopLeft, clipCornerRadiusTopRight;
    float clipCornerRadiusBottomRight, clipCornerRadiusBottomLeft;
    float clipShapeX, clipShapeY, clipShapeWidth, clipShapeHeight;
};

StructuredBuffer<GlyphInstance> instances : register(t0);
Texture2D glyphAtlas : register(t1);
SamplerState glyphSampler : register(s0);

cbuffer FrameUniforms : register(b0) {
    float2 surfaceSize;
    float2 padding;
};

struct VSOutput {
    float4 position : SV_Position;
    // The rasterized world position of this fragment. It used to be
    // recomputed in the pixel stage as `screenPosition + unit * screenSize`,
    // which is only the drawn position while the cell is upright; a rotated
    // glyph would have been clipped against where it *would* have been.
    float2 pixelPosition : TEXCOORD0;
    float4 clipRect : TEXCOORD3;
    float2 uv : TEXCOORD4;
    float4 color : COLOR0;
    nointerpolation float4 clipRadii : TEXCOORD5;
    nointerpolation float4 clipShapeRect : TEXCOORD6;
};

VSOutput vsMain(uint vertexID : SV_VertexID, uint instanceID : SV_InstanceID) {
    const float2 quad[6] = {
        float2(0.0, 0.0), float2(1.0, 0.0), float2(0.0, 1.0),
        float2(0.0, 1.0), float2(1.0, 0.0), float2(1.0, 1.0)
    };

    GlyphInstance inst = instances[instanceID];
    float2 unit = quad[vertexID];
    float2 origin = float2(inst.screenX, inst.screenY);
    float2 size = float2(inst.screenW, inst.screenH);
    // Rotation about the cell's centre, matching the quad shader. The UV
    // lerp is driven by `unit`, so the atlas cell turns with the vertices
    // and the sampler is untouched.
    float2 pixelPos;
    if (inst.rotationRadians == 0.0)
    {
        pixelPos = origin + unit * size;
    }
    else
    {
        float2 centre = origin + size * 0.5;
        float2 fromCentre = unit * size - size * 0.5;
        float cosR = cos(inst.rotationRadians);
        float sinR = sin(inst.rotationRadians);
        pixelPos = centre + float2(
            cosR * fromCentre.x - sinR * fromCentre.y,
            sinR * fromCentre.x + cosR * fromCentre.y
        );
    }

    float2 clipPos = float2(
        (pixelPos.x / surfaceSize.x) * 2.0 - 1.0,
        1.0 - (pixelPos.y / surfaceSize.y) * 2.0
    );

    float2 uv0 = float2(inst.atlasU0, inst.atlasV0);
    float2 uv1 = float2(inst.atlasU1, inst.atlasV1);
    float2 uv = lerp(uv0, uv1, unit);

    VSOutput output;
    output.position = float4(clipPos, 0.0, 1.0);
    output.pixelPosition = pixelPos;
    output.clipRect = float4(inst.clipX, inst.clipY, inst.clipWidth, inst.clipHeight);
    output.uv = uv;
    output.color = float4(inst.colorR, inst.colorG, inst.colorB, inst.colorA);
    output.clipRadii = resolvedClipRadii(inst.clipCornerRadius, float4(
        inst.clipCornerRadiusTopLeft, inst.clipCornerRadiusTopRight,
        inst.clipCornerRadiusBottomRight, inst.clipCornerRadiusBottomLeft));
    output.clipShapeRect = resolvedClipShapeRect(output.clipRect, float4(
        inst.clipShapeX, inst.clipShapeY, inst.clipShapeWidth, inst.clipShapeHeight));
    return output;
}

float4 psMain(VSOutput input) : SV_Target {
    float clipAlpha = originalClipCoverage(
        input.pixelPosition, input.clipRect, input.clipShapeRect, input.clipRadii);
    if (clipAlpha <= 0.0)
    {
        discard;
    }

    float glyphAlpha = glyphAtlas.Sample(glyphSampler, input.uv).a * clipAlpha;
    return float4(input.color.rgb * input.color.a * glyphAlpha, input.color.a * glyphAlpha);
}
"""#

public struct GlyphPipelineResources: Sendable {
    public static let vertexShaderSource: String = glyphShaderSource
    public static let vertexShaderEntryPoint = "vsMain"
    public static let pixelShaderEntryPoint = "psMain"
}

public enum GlyphPipeline {
    /// Validates that glyph shaders compile successfully.
    /// Called from unit tests to verify shader correctness without a GPU device.
    public static func validateShadersForTesting() throws {
        var vertexShaderBlob: UnsafeMutablePointer<ID3DBlob>? = try compileShaderSource(
            source: glyphShaderSource, entryPoint: "vsMain", profile: "vs_5_0"
        )
        var pixelShaderBlob: UnsafeMutablePointer<ID3DBlob>? = try compileShaderSource(
            source: glyphShaderSource, entryPoint: "psMain", profile: "ps_5_0"
        )
        releaseCOM(&pixelShaderBlob)
        releaseCOM(&vertexShaderBlob)
    }
}
