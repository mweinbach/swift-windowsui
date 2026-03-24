import WinSDK
import WinSDK.DirectX

private let glyphShaderSource = #"""
struct GlyphInstance {
    float screenX, screenY, screenW, screenH;
    float atlasU0, atlasV0, atlasU1, atlasV1;
    float colorR, colorG, colorB, colorA;
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
    float2 uv : TEXCOORD0;
    float4 color : COLOR0;
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
    float2 pixelPos = origin + unit * size;

    float2 clipPos = float2(
        (pixelPos.x / surfaceSize.x) * 2.0 - 1.0,
        1.0 - (pixelPos.y / surfaceSize.y) * 2.0
    );

    float2 uv0 = float2(inst.atlasU0, inst.atlasV0);
    float2 uv1 = float2(inst.atlasU1, inst.atlasV1);
    float2 uv = lerp(uv0, uv1, unit);

    VSOutput output;
    output.position = float4(clipPos, 0.0, 1.0);
    output.uv = uv;
    output.color = float4(inst.colorR, inst.colorG, inst.colorB, inst.colorA);
    return output;
}

float4 psMain(VSOutput input) : SV_Target {
    float glyphAlpha = glyphAtlas.Sample(glyphSampler, input.uv).a;
    return float4(input.color.rgb * input.color.a * glyphAlpha, input.color.a * glyphAlpha);
}
"""#

@MainActor
public struct GlyphPipelineResources: Sendable {
    public static let vertexShaderSource: String = glyphShaderSource
    public static let vertexShaderEntryPoint = "vsMain"
    public static let pixelShaderEntryPoint = "psMain"
}

public enum GlyphPipeline {
    /// Validates that glyph shaders compile successfully.
    /// Called from unit tests to verify shader correctness without a GPU device.
    @MainActor
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
