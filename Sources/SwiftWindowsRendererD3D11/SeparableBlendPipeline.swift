// swift-format-ignore-file
// Shared HLSL uses raw string indentation, as in BatchShaders.swift.

import SwiftWindowsGraphics
import WinSDK
import WinSDK.DirectX

/// Destination storage confined to one renderer owner. The allocation can
/// survive draws, but its pixels are recaptured for every occurrence. Callers
/// clear the SRV binding before capture and after drawing, and release this
/// owner on detach or a real resize. No immediate context is stored here.
final class D3D11BlendDestinationSnapshot {
    private(set) var texture: UnsafeMutablePointer<ID3D11Texture2D>?
    private(set) var srv: UnsafeMutablePointer<ID3D11ShaderResourceView>?
    private(set) var region: SubTextureRegion
    let capacityWidth: Int
    let capacityHeight: Int

    init(
        device: UnsafeMutablePointer<ID3D11Device>, context: UnsafeMutablePointer<ID3D11DeviceContext>,
        source: UnsafeMutablePointer<ID3D11Texture2D>, region: SubTextureRegion
    ) throws {
        self.region = region
        capacityWidth = region.width
        capacityHeight = region.height
        try Self.validateSource(source, region: region)

        var descriptor = D3D11_TEXTURE2D_DESC()
        descriptor.Width = UINT(region.width)
        descriptor.Height = UINT(region.height)
        descriptor.MipLevels = 1
        descriptor.ArraySize = 1
        descriptor.Format = DXGI_FORMAT_B8G8R8A8_UNORM
        descriptor.SampleDesc = DXGI_SAMPLE_DESC(Count: 1, Quality: 0)
        descriptor.Usage = D3D11_USAGE_DEFAULT
        descriptor.BindFlags = UINT(D3D11_BIND_SHADER_RESOURCE.rawValue)

        var createdTexture: UnsafeMutablePointer<ID3D11Texture2D>?
        var createdSRV: UnsafeMutablePointer<ID3D11ShaderResourceView>?
        defer {
            releaseCOM(&createdSRV)
            releaseCOM(&createdTexture)
        }
        let textureResult = makeCOM(into: &createdTexture) { value in
            device.pointee.lpVtbl.pointee.CreateTexture2D(device, &descriptor, nil, &value)
        }
        guard textureResult >= 0, let copiedTexture = createdTexture else {
            throw BatchRendererError(
                operation: "Create separable blend destination texture",
                hresult: textureResult < 0 ? textureResult : HRESULT(bitPattern: 0x80070006))
        }
        let destinationResource = UnsafeMutableRawPointer(copiedTexture).assumingMemoryBound(to: ID3D11Resource.self)
        let viewResult = makeCOM(into: &createdSRV) { value in
            device.pointee.lpVtbl.pointee.CreateShaderResourceView(device, destinationResource, nil, &value)
        }
        guard viewResult >= 0, createdSRV != nil else {
            throw BatchRendererError(
                operation: "Create separable blend destination view",
                hresult: viewResult < 0 ? viewResult : HRESULT(bitPattern: 0x80070006))
        }
        var box = D3D11_BOX(
            left: UINT(region.originX), top: UINT(region.originY), front: 0,
            right: UINT(region.maxX), bottom: UINT(region.maxY), back: 1)
        let sourceResource = UnsafeMutableRawPointer(source).assumingMemoryBound(to: ID3D11Resource.self)
        context.pointee.lpVtbl.pointee.CopySubresourceRegion(
            context, destinationResource, 0, 0, 0, 0, sourceResource, 0, &box)
        texture = createdTexture
        srv = createdSRV
        createdTexture = nil
        createdSRV = nil
    }

    /// Also used when an isolated group already owns a composed read texture
    /// and needs descriptor validation without an additional copy.
    static func validateSource(
        _ source: UnsafeMutablePointer<ID3D11Texture2D>, region: SubTextureRegion
    ) throws {
        var descriptor = D3D11_TEXTURE2D_DESC()
        source.pointee.lpVtbl.pointee.GetDesc(source, &descriptor)
        guard descriptor.Width > 0, descriptor.Height > 0,
            descriptor.Width <= UINT(GPUISceneLimits.maxSurfaceDimension),
            descriptor.Height <= UINT(GPUISceneLimits.maxSurfaceDimension),
            descriptor.Format == DXGI_FORMAT_B8G8R8A8_UNORM,
            descriptor.SampleDesc.Count == 1, descriptor.SampleDesc.Quality == 0,
            descriptor.MipLevels == 1, descriptor.ArraySize == 1,
            region.textureWidth == Int(descriptor.Width), region.textureHeight == Int(descriptor.Height),
            !region.isEmpty, region.originX >= 0, region.originY >= 0,
            region.maxX <= Int(descriptor.Width), region.maxY <= Int(descriptor.Height)
        else {
            throw BatchRendererError(
                operation: "Validate separable blend destination", hresult: HRESULT(bitPattern: 0x80070057),
                details: "The snapshot must be a nonempty region of the actual bounded single-sample BGRA8 target.",
                failureKind: .sceneContent)
        }
    }

    /// Reuses only the allocation. Even an unchanged region is copied again,
    /// after all earlier draws in this immediate context. The renderer must
    /// unbind this texture's SRV before calling; the source and destination
    /// subresources must differ. Failure leaves the prior region and pixels.
    func capture(
        context: UnsafeMutablePointer<ID3D11DeviceContext>,
        source: UnsafeMutablePointer<ID3D11Texture2D>, region: SubTextureRegion
    ) throws {
        guard let texture, srv != nil else {
            throw BatchRendererError(
                operation: "Recapture separable blend destination", hresult: HRESULT(bitPattern: 0x80070006),
                details: "The destination allocation has been released.")
        }
        try Self.validateSource(source, region: region)
        guard source != texture, region.width <= capacityWidth, region.height <= capacityHeight else {
            throw BatchRendererError(
                operation: "Recapture separable blend destination", hresult: HRESULT(bitPattern: 0x80070057),
                details: "The source must differ from the destination and the copy must fit its fixed capacity.",
                failureKind: .sceneContent)
        }
        var box = D3D11_BOX(
            left: UINT(region.originX), top: UINT(region.originY), front: 0,
            right: UINT(region.maxX), bottom: UINT(region.maxY), back: 1)
        let sourceResource = UnsafeMutableRawPointer(source).assumingMemoryBound(to: ID3D11Resource.self)
        let destinationResource = UnsafeMutableRawPointer(texture).assumingMemoryBound(to: ID3D11Resource.self)
        context.pointee.lpVtbl.pointee.CopySubresourceRegion(
            context, destinationResource, 0, 0, 0, 0, sourceResource, 0, &box)
        self.region = region
    }

    func release() {
        releaseCOM(&srv)
        releaseCOM(&texture)
    }

    deinit {
        releaseCOM(&srv)
        releaseCOM(&texture)
    }
}

/// The pixel shader's b2 layout, shared by batch quads and legacy frame fills.
/// Copy coordinates stay in physical pixels; no filtering or UV conversion is
/// involved. For an isolated virtual destination, origin is zero.
struct D3D11SeparableBlendUniforms {
    var originX: Int32
    var originY: Int32
    var width: Int32
    var height: Int32
    var mode: Float
    var padding0: Float = 0
    var padding1: Float = 0
    var padding2: Float = 0

    init(region: SubTextureRegion, mode: BlendMode) {
        originX = Int32(region.originX)
        originY = Int32(region.originY)
        width = Int32(region.width)
        height = Int32(region.height)
        self.mode = Float(mode.rawValue)
    }
}

/// Additive draws write a destination-aware increment with ONE / ONE. The
/// caller owns the returned state and must release it with its device resources.
func makeD3D11AdditiveBlendState(
    device: UnsafeMutablePointer<ID3D11Device>
) throws -> UnsafeMutablePointer<ID3D11BlendState> {
    var descriptor = D3D11_BLEND_DESC()
    descriptor.AlphaToCoverageEnable = false
    descriptor.IndependentBlendEnable = false
    descriptor.RenderTarget.0.BlendEnable = true
    descriptor.RenderTarget.0.SrcBlend = D3D11_BLEND_ONE
    descriptor.RenderTarget.0.DestBlend = D3D11_BLEND_ONE
    descriptor.RenderTarget.0.BlendOp = D3D11_BLEND_OP_ADD
    descriptor.RenderTarget.0.SrcBlendAlpha = D3D11_BLEND_ONE
    descriptor.RenderTarget.0.DestBlendAlpha = D3D11_BLEND_ONE
    descriptor.RenderTarget.0.BlendOpAlpha = D3D11_BLEND_OP_ADD
    descriptor.RenderTarget.0.RenderTargetWriteMask = UINT8(D3D11_COLOR_WRITE_ENABLE_ALL.rawValue)
    var state: UnsafeMutablePointer<ID3D11BlendState>?
    var transfersState = false
    defer { if !transfersState { releaseCOM(&state) } }
    let result = device.pointee.lpVtbl.pointee.CreateBlendState(device, &descriptor, &state)
    guard result >= 0, let state else {
        throw BatchRendererError(
            operation: "Create additive blend state",
            hresult: result < 0 ? result : HRESULT(bitPattern: 0x80004005))
    }
    transfersState = true
    return state
}

/// Modes 1...3 return adjusted source Q for ONE / INV_SRC_ALPHA. Mode 4
/// returns only the clamped additive increment for ONE / ONE, with no isolated
/// coverage update. Both sample the visible destination, including F + (1-K)B.
let separableBlendShaderSource = #"""
Texture2D blendDestination : register(t1);
cbuffer SeparableBlendUniforms : register(b2)
{
    int2 blendOrigin;
    int2 blendExtent;
    float blendMode;
    float3 blendPadding;
};

float4 applySeparableBlend(float4 source, float2 pixelPosition)
{
    if (source.a <= 0.0)
    {
        return float4(0.0, 0.0, 0.0, 0.0);
    }
    int2 pixel = (int2)pixelPosition - blendOrigin;
    if (any(pixel < int2(0, 0)) || any(pixel >= blendExtent))
    {
        discard;
    }
    float4 destination = blendDestination.Load(int3(pixel, 0));
    if (blendMode == 4.0)
    {
        // Equivalent to saturate(source + destination) - destination for
        // normalized channels, without cancellation of a small source value.
        // Source already includes geometry/clip coverage. In an isolated
        // target add this delta to F and leave K unchanged; it may carry RGB
        // with zero alpha when the visible destination is already opaque.
        return min(source, saturate(1.0 - destination));
    }
    float3 sourceColor = source.rgb / source.a;
    // Match the CPU's normalized straight-color blend domain. The original
    // premultiplied destination still contributes through source-over.
    float3 destinationColor = destination.a > 0.0 ? saturate(destination.rgb / destination.a) : float3(0.0, 0.0, 0.0);
    float3 blended;
    if (blendMode == 1.0)
    {
        blended = sourceColor * destinationColor;
    }
    else if (blendMode == 2.0)
    {
        blended = sourceColor + destinationColor - sourceColor * destinationColor;
    }
    else if (blendMode == 3.0)
    {
        float3 low = 2.0 * sourceColor * destinationColor;
        float3 high = 1.0 - 2.0 * (1.0 - sourceColor) * (1.0 - destinationColor);
        blended = float3(
            destinationColor.r <= 0.5 ? low.r : high.r,
            destinationColor.g <= 0.5 ? low.g : high.g,
            destinationColor.b <= 0.5 ? low.b : high.b);
    }
    else
    {
        return source;
    }
    return float4(source.a * ((1.0 - destination.a) * sourceColor + destination.a * blended), source.a);
}
"""#
