import SwiftWindowsCore
import SwiftWindowsGraphics
import WinSDK
import WinSDK.DirectX

/// Instanced shadow rendering pipeline for the D3D11 batch renderer.
public enum ShadowPipeline {
    /// The HLSL shader source for instanced shadow rendering.
    public static var shaderSource: String { shadowShaderSource }

    /// Vertex shader entry point name.
    public static let vertexShaderEntryPoint = "vsMain"

    /// Pixel shader entry point name.
    public static let pixelShaderEntryPoint = "psMain"

    /// Validates that shadow shaders compile successfully.
    ///
    /// This compiles both the vertex and pixel shaders using D3DCompile
    /// and releases the resulting blobs. Any compilation failure is thrown
    /// as a ``D3D11RendererError``.
    public static func validateShadersForTesting() throws {
        var vsBlob: UnsafeMutablePointer<ID3DBlob>? = try compileShadowShader(
            entryPoint: vertexShaderEntryPoint, profile: "vs_5_0"
        )
        var psBlob: UnsafeMutablePointer<ID3DBlob>? = try compileShadowShader(
            entryPoint: pixelShaderEntryPoint, profile: "ps_5_0"
        )
        releaseCOM(&psBlob)
        releaseCOM(&vsBlob)
    }

    private static func compileShadowShader(entryPoint: String, profile: String) throws -> UnsafeMutablePointer<ID3DBlob> {
        let sourceBytes = Array(shadowShaderSource.utf8)
        var shaderBlob: UnsafeMutablePointer<ID3DBlob>?
        var errorBlob: UnsafeMutablePointer<ID3DBlob>?

        let hr = sourceBytes.withUnsafeBytes { source in
            entryPoint.withCString { entryPointCString in
                profile.withCString { profileCString in
                    D3DCompile(
                        source.baseAddress,
                        SIZE_T(sourceBytes.count),
                        nil,
                        nil,
                        nil,
                        entryPointCString,
                        profileCString,
                        0,
                        0,
                        &shaderBlob,
                        &errorBlob
                    )
                }
            }
        }

        if hr < 0 {
            let details = shaderCompilerDetails(from: errorBlob)
            releaseCOM(&errorBlob)
            throw D3D11RendererError(operation: "D3DCompile(\(entryPoint))", hresult: hr, details: details)
        }

        releaseCOM(&errorBlob)

        guard let shaderBlob else {
            throw D3D11RendererError(operation: "D3DCompile(\(entryPoint))", hresult: HRESULT(bitPattern: 0x80070006))
        }

        return shaderBlob
    }

    private static func shaderCompilerDetails(from errorBlob: UnsafeMutablePointer<ID3DBlob>?) -> String? {
        guard
            let errorBlob,
            let rawPointer = errorBlob.pointee.lpVtbl.pointee.GetBufferPointer(errorBlob)
        else {
            return nil
        }

        return String(cString: rawPointer.assumingMemoryBound(to: CChar.self))
    }
}

private let shadowShaderSource = #"""
struct ShadowInstance {
    float x, y, width, height;
    float cornerRadius;
    float colorR, colorG, colorB, colorA;
    float blurRadius;
    float offsetX, offsetY;
};

StructuredBuffer<ShadowInstance> instances : register(t0);

cbuffer FrameUniforms : register(b0) {
    float2 surfaceSize;
    float2 padding;
};

struct VSOutput {
    float4 position : SV_Position;
    float2 localPosition : TEXCOORD0;
    float2 size : TEXCOORD1;
    float radius : TEXCOORD2;
    float4 shadowColor : COLOR0;
    float blurRadius : TEXCOORD3;
};

VSOutput vsMain(uint vertexID : SV_VertexID, uint instanceID : SV_InstanceID) {
    const float2 quad[6] = {
        float2(0.0, 0.0), float2(1.0, 0.0), float2(0.0, 1.0),
        float2(0.0, 1.0), float2(1.0, 0.0), float2(1.0, 1.0)
    };

    ShadowInstance inst = instances[instanceID];
    float2 unit = quad[vertexID];

    // Expand the shadow rect by the blur radius on all sides
    // so the soft falloff has room to render
    float expand = inst.blurRadius * 2.0;
    float2 origin = float2(inst.x + inst.offsetX - expand, inst.y + inst.offsetY - expand);
    float2 size = float2(inst.width + expand * 2.0, inst.height + expand * 2.0);

    float2 pixelPos = origin + unit * size;
    float2 clipPos = float2(
        (pixelPos.x / surfaceSize.x) * 2.0 - 1.0,
        1.0 - (pixelPos.y / surfaceSize.y) * 2.0
    );

    // Local position relative to the UNEXPANDED rect center
    // so the SDF operates on the original rect shape
    float2 rectSize = float2(inst.width, inst.height);
    float2 localPos = (unit * size) - float2(expand, expand);

    VSOutput output;
    output.position = float4(clipPos, 0.0, 1.0);
    output.localPosition = localPos;
    output.size = rectSize;
    output.radius = inst.cornerRadius;
    output.shadowColor = float4(inst.colorR, inst.colorG, inst.colorB, inst.colorA);
    output.blurRadius = inst.blurRadius;
    return output;
}

float roundedRectDistance(float2 localPosition, float2 size, float radius) {
    float2 halfSize = size * 0.5;
    float2 localPoint = localPosition - halfSize;
    float clampedRadius = min(radius, min(halfSize.x, halfSize.y));
    float2 corner = max(halfSize - float2(clampedRadius, clampedRadius), float2(0.0, 0.0));
    float2 delta = abs(localPoint) - corner;
    return length(max(delta, float2(0.0, 0.0))) + min(max(delta.x, delta.y), 0.0) - clampedRadius;
}

float4 psMain(VSOutput input) : SV_Target {
    float distance = roundedRectDistance(input.localPosition, input.size, input.radius);

    // Soft shadow falloff using smoothstep
    // When distance < 0 (inside rect), shadow is full strength
    // When distance > 0, shadow falls off over blurRadius
    float blur = max(input.blurRadius, 0.5);
    float shadowAlpha = saturate(1.0 - smoothstep(-blur * 0.5, blur, distance));

    float4 color = input.shadowColor;
    return float4(color.rgb * color.a * shadowAlpha, color.a * shadowAlpha);
}
"""#
