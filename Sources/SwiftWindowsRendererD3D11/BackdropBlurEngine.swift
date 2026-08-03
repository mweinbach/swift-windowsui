import Foundation

import SwiftWindowsCore

import SwiftWindowsGraphics

import WinSDK

import WinSDK.DirectX

// MARK: - D3D11BackdropBlurEngine

/// True GPU backdrop blur for Material quads on the D3D11 batch path.
///
/// The CPU rasterizer (`GPUIRawSceneRasterizer.applyBoxBlur`) blurs the
/// already-composited pixels under a quad's bounds with a separable
/// Gaussian and is the visual target; the plain quad pixel shader's old
/// behaviour (widening the edge falloff) only produced a soft tint. This
/// engine closes that gap:
///
/// 1. Copy the quad's rect out of the current backbuffer ("scene so
///    far") into an offscreen ping-pong target. Because the batch
///    renderer processes `paintOperations` in presentation order and the
///    blur runs at the moment the material quad is drawn, the copy
///    contains everything painted BEFORE the material and nothing
///    painted after it — nested/overlapping materials therefore blur the
///    already-tinted result of the material beneath them, never their
///    own contents.
/// 2. Blur it with a two-pass separable Gaussian (H into target B, V
///    back into target A) using the exact `gaussianBlurKernel(radius:)`
///    weights the CPU rasterizer uses.
/// 3. Draw the material quad with the composite pixel shader
///    (`batchMaterialQuadShaderSource`), which samples the blurred
///    backdrop at screen-space UVs and composites the tint over it
///    (source-over), then modulates by the rounded-rect coverage so the
///    edges anti-alias against the untouched backdrop.
///
/// Performance shape: `BlurPassPlan` — the renderer-neutral cost model
/// the CPU rasterizer shares — decides how the blur is executed. Ordinary
/// radii (everything at or below `fullResolutionRadiusLimit`, which covers
/// every built-in material and every pinned baseline) run at full
/// resolution: `2 * (2r + 1)` texture samples per region pixel, e.g. a
/// 400×300 panel at r=22 ≈ 11M samples. Past that the plan inserts 2×
/// halving passes and blurs the reduced image with a reduced radius, so
/// the cost of a wide `.blur(radius:)` stops scaling cubically with
/// display scale (one halving is 8× cheaper, two are 64×). The halving
/// pass is the ordinary blur shader with a zero radius: a single bilinear
/// tap placed on a texel boundary *is* an exact 2×2 box average, so the
/// reduction needs no shader of its own and the CPU can transcribe it
/// exactly.
///
/// The engine is self-contained (own shaders, constant buffers, sampler,
/// blend/rasterizer state and a 1-instance quad buffer) so headless
/// tests can drive it against a WARP device without an HWND or swap
/// chain. `D3D11BatchRenderer` owns one instance and recreates it
/// whenever its device generation changes (re-attach, device-loss
/// rebuild).
@MainActor
final class D3D11BackdropBlurEngine {
    /// Kernel radius cap. Tracks `GPUISceneLimits.maxBlurRadius` — the
    /// shared engine limit both backends honour — and the blur cbuffer
    /// below is sized to hold exactly that many weights. Built-in
    /// materials top out at 40; the cap exists for app-supplied
    /// `.blur(radius:)` at 2× scale.
    static let maxBlurRadius = Int(GPUISceneLimits.maxBlurRadius)

    /// Float count of the blur-params cbuffer:
    /// 4 (direction) + 4 (UV scale) + 260 (weights, `blurWeights[65]` in
    /// HLSL). Must match `batchBackdropBlurShaderSource`'s `BlurParams`
    /// exactly — `D3D11BackdropBlurTests` pins the two together.
    static let blurParamsFloatCount = 268

    /// Float count of the composite draw's `BackdropRegion` cbuffer:
    /// 4 (region origin + scaled texture size) + 4 (UV clamp bounds).
    /// Must match `batchMaterialQuadShaderSource`'s cbuffer exactly.
    static let regionParamsFloatCount = 8

    private var device: UnsafeMutablePointer<ID3D11Device>?

    /// The owning renderer's device generation these resources belong to.
    /// `0` means "not keyed to any generation", which never matches.
    private var deviceGeneration: UInt64 = 0

    private var blurVS: UnsafeMutablePointer<ID3D11VertexShader>?
    private var blurPS: UnsafeMutablePointer<ID3D11PixelShader>?
    private var materialVS: UnsafeMutablePointer<ID3D11VertexShader>?
    private var materialPS: UnsafeMutablePointer<ID3D11PixelShader>?

    private var blurParamsBuffer: UnsafeMutablePointer<ID3D11Buffer>?
    private var frameUniformBuffer: UnsafeMutablePointer<ID3D11Buffer>?
    private var regionBuffer: UnsafeMutablePointer<ID3D11Buffer>?
    private var quadInstanceBuffer: UnsafeMutablePointer<ID3D11Buffer>?
    private var quadInstanceSRV: UnsafeMutablePointer<ID3D11ShaderResourceView>?

    private var samplerState: UnsafeMutablePointer<ID3D11SamplerState>?
    private var blendState: UnsafeMutablePointer<ID3D11BlendState>?
    private var rasterizerState: UnsafeMutablePointer<ID3D11RasterizerState>?

    private var textureA: UnsafeMutablePointer<ID3D11Texture2D>?
    private var rtvA: UnsafeMutablePointer<ID3D11RenderTargetView>?
    private var srvA: UnsafeMutablePointer<ID3D11ShaderResourceView>?
    private var textureB: UnsafeMutablePointer<ID3D11Texture2D>?
    private var rtvB: UnsafeMutablePointer<ID3D11RenderTargetView>?
    private var srvB: UnsafeMutablePointer<ID3D11ShaderResourceView>?

    /// Grow-only ping-pong target size; regions always render into the
    /// textures' top-left corner.
    private(set) var textureCapacity: (width: Int, height: Int) = (0, 0)

    init() {}

    /// True when this engine's resources belong to the caller's current
    /// device.
    ///
    /// Keyed on the renderer's monotonic device generation, not on the raw
    /// pointer: after a device-loss rebuild the allocator is free to hand
    /// the new `ID3D11Device` the address the removed one just released, and
    /// pointer equality would then report a match for resources created on a
    /// device that no longer exists.
    func matches(deviceGeneration generation: UInt64) -> Bool {
        generation != 0 && deviceGeneration == generation
    }

    /// Creates every device-dependent resource. Releases any resources
    /// from a previous device first.
    ///
    /// `generation` is the owning renderer's device generation; pass `0`
    /// (the default) when attaching directly to a device the renderer does
    /// not track, which leaves the engine permanently unmatched so callers
    /// cannot accidentally reuse it across devices.
    func attach(device: UnsafeMutablePointer<ID3D11Device>, generation: UInt64 = 0) throws {
        detach()
        self.device = device
        self.deviceGeneration = generation

        blurVS = try Self.compileVertexShader(device: device, source: batchBackdropBlurShaderSource, label: "blur")
        blurPS = try Self.compilePixelShader(device: device, source: batchBackdropBlurShaderSource, label: "blur")
        materialVS = try Self.compileVertexShader(
            device: device, source: batchMaterialQuadShaderSource, label: "material")
        materialPS = try Self.compilePixelShader(
            device: device, source: batchMaterialQuadShaderSource, label: "material")

        blurParamsBuffer = try Self.createConstantBuffer(
            device: device, byteWidth: UINT(Self.blurParamsFloatCount * 4), label: "blurParams")
        frameUniformBuffer = try Self.createConstantBuffer(device: device, byteWidth: 16, label: "frameUniforms")
        // 32 bytes: `backdropRegion` plus the `backdropUVBounds` float4 the
        // composite shader clamps its backdrop sample into.
        regionBuffer = try Self.createConstantBuffer(
            device: device, byteWidth: UINT(Self.regionParamsFloatCount * 4), label: "region")
        try createQuadInstanceBuffer(device: device)

        var samplerDescriptor = D3D11_SAMPLER_DESC()
        samplerDescriptor.Filter = D3D11_FILTER_MIN_MAG_MIP_LINEAR
        samplerDescriptor.AddressU = D3D11_TEXTURE_ADDRESS_CLAMP
        samplerDescriptor.AddressV = D3D11_TEXTURE_ADDRESS_CLAMP
        samplerDescriptor.AddressW = D3D11_TEXTURE_ADDRESS_CLAMP
        samplerDescriptor.MaxLOD = FLOAT(D3D11_FLOAT32_MAX)
        let samplerHR = device.pointee.lpVtbl.pointee.CreateSamplerState(device, &samplerDescriptor, &samplerState)
        try Self.throwIfFailed(samplerHR, operation: "ID3D11Device.CreateSamplerState(backdropBlur)")

        // Same premultiplied source-over blend the batch pipeline uses:
        // the composite draw must blend its coverage-weighted result over
        // the untouched backdrop at the quad's anti-aliased edges.
        var blendDescriptor = D3D11_BLEND_DESC()
        blendDescriptor.AlphaToCoverageEnable = false
        blendDescriptor.IndependentBlendEnable = false
        blendDescriptor.RenderTarget.0.BlendEnable = true
        blendDescriptor.RenderTarget.0.SrcBlend = D3D11_BLEND_ONE
        blendDescriptor.RenderTarget.0.DestBlend = D3D11_BLEND_INV_SRC_ALPHA
        blendDescriptor.RenderTarget.0.BlendOp = D3D11_BLEND_OP_ADD
        blendDescriptor.RenderTarget.0.SrcBlendAlpha = D3D11_BLEND_ONE
        blendDescriptor.RenderTarget.0.DestBlendAlpha = D3D11_BLEND_INV_SRC_ALPHA
        blendDescriptor.RenderTarget.0.BlendOpAlpha = D3D11_BLEND_OP_ADD
        blendDescriptor.RenderTarget.0.RenderTargetWriteMask = UINT8(D3D11_COLOR_WRITE_ENABLE_ALL.rawValue)
        let blendHR = device.pointee.lpVtbl.pointee.CreateBlendState(device, &blendDescriptor, &blendState)
        try Self.throwIfFailed(blendHR, operation: "ID3D11Device.CreateBlendState(backdropBlur)")

        var rasterizerDescriptor = D3D11_RASTERIZER_DESC()
        rasterizerDescriptor.FillMode = D3D11_FILL_SOLID
        rasterizerDescriptor.CullMode = D3D11_CULL_NONE
        rasterizerDescriptor.ScissorEnable = false
        rasterizerDescriptor.DepthClipEnable = true
        let rasterizerHR = device.pointee.lpVtbl.pointee.CreateRasterizerState(
            device, &rasterizerDescriptor, &rasterizerState)
        try Self.throwIfFailed(rasterizerHR, operation: "ID3D11Device.CreateRasterizerState(backdropBlur)")
    }

    /// Releases every device-dependent resource. Called on device
    /// reattach and by the renderer's own teardown paths.
    func detach() {
        releaseCOM(&srvB)
        releaseCOM(&rtvB)
        releaseCOM(&textureB)
        releaseCOM(&srvA)
        releaseCOM(&rtvA)
        releaseCOM(&textureA)
        textureCapacity = (0, 0)

        releaseCOM(&rasterizerState)
        releaseCOM(&blendState)
        releaseCOM(&samplerState)
        releaseCOM(&quadInstanceSRV)
        releaseCOM(&quadInstanceBuffer)
        releaseCOM(&regionBuffer)
        releaseCOM(&frameUniformBuffer)
        releaseCOM(&blurParamsBuffer)
        releaseCOM(&materialPS)
        releaseCOM(&materialVS)
        releaseCOM(&blurPS)
        releaseCOM(&blurVS)
        device = nil
        deviceGeneration = 0
    }

    // No deinit-based release: COM teardown must happen on the main
    // actor, matching D3D11BatchRenderer's own explicit-teardown style.
    // The owning renderer calls detach() when its device changes.

    // MARK: - Blur + Composite

    /// Pixel-space backdrop region blurred for `quad`, clamped to the
    /// surface and to the quad's clip rect. Axis-aligned quads blur their
    /// own rect. Rotated quads blur the axis-aligned bounding box of the
    /// rotated footprint — the same window the CPU rasterizer blurs (its
    /// scan bounds for rotated blur quads). This is a deliberate
    /// approximation: the backdrop region mapping stays axis-aligned, and
    /// the composite draw only samples the blurred backdrop where the
    /// rotated quad's coverage is non-zero, so the blur is only visible
    /// under the quad itself.
    ///
    /// The clip intersection matters for more than fill rate: the CPU
    /// rasterizer blurs the *clipped* bounds, so blurring the unclipped
    /// rect here would diverge at the clip boundary — and a tall material
    /// in a short scroll clip would grow the ping-pong targets to its full
    /// height to produce pixels the composite shader then discards.
    /// `clipWidth == clipHeight == 0` is the contract's "unclipped"
    /// sentinel (the same test both quad pixel shaders make).
    static func blurRegion(
        for quad: QuadPrimitive,
        surfaceWidth: Int,
        surfaceHeight: Int
    ) -> (x0: Int, y0: Int, x1: Int, y1: Int) {
        let surfaceW = max(surfaceWidth, 1)
        let surfaceH = max(surfaceHeight, 1)
        var minX = Double(quad.x)
        var minY = Double(quad.y)
        var maxX = Double(quad.x + quad.width)
        var maxY = Double(quad.y + quad.height)
        if quad.rotationRadians != 0 {
            let rotation = Double(quad.rotationRadians)
            let centreX = Double(quad.x) + Double(quad.width) * 0.5
            let centreY = Double(quad.y) + Double(quad.height) * 0.5
            let halfW = Double(quad.width) * 0.5
            let halfH = Double(quad.height) * 0.5
            let cosR = cos(rotation)
            let sinR = sin(rotation)
            var rotatedMinX = Double.infinity
            var rotatedMinY = Double.infinity
            var rotatedMaxX = -Double.infinity
            var rotatedMaxY = -Double.infinity
            for (dx, dy) in [(-halfW, -halfH), (halfW, -halfH), (halfW, halfH), (-halfW, halfH)] {
                let cornerX = centreX + dx * cosR - dy * sinR
                let cornerY = centreY + dx * sinR + dy * cosR
                rotatedMinX = min(rotatedMinX, cornerX)
                rotatedMinY = min(rotatedMinY, cornerY)
                rotatedMaxX = max(rotatedMaxX, cornerX)
                rotatedMaxY = max(rotatedMaxY, cornerY)
            }
            minX = rotatedMinX
            minY = rotatedMinY
            maxX = rotatedMaxX
            maxY = rotatedMaxY
        }
        if quad.clipWidth > 0, quad.clipHeight > 0 {
            minX = max(minX, Double(quad.clipX))
            minY = max(minY, Double(quad.clipY))
            maxX = min(maxX, Double(quad.clipX + quad.clipWidth))
            maxY = min(maxY, Double(quad.clipY + quad.clipHeight))
        }
        // Saturating conversions, and they happen *before* the clamp:
        // `Int(floor(.nan))` traps, so a non-finite quad rect would kill
        // the process on the way to being clamped into the surface.
        // NaN converts to 0, which collapses the region and the caller
        // no-ops.
        let x0 = max(0, min(GPUISceneValue.int(floor(minX)), surfaceW))
        let y0 = max(0, min(GPUISceneValue.int(floor(minY)), surfaceH))
        // `max(x0, …)`: a clip that misses the quad entirely leaves
        // maxX < minX, and callers read the result as a half-open range.
        let x1 = max(x0, min(GPUISceneValue.int(ceil(maxX)), surfaceW))
        let y1 = max(y0, min(GPUISceneValue.int(ceil(maxY)), surfaceH))
        return (x0, y0, x1, y1)
    }

    /// Blurs the region of `backBuffer` under `quad`'s rect and draws
    /// the quad's tint composited over the blurred backdrop into
    /// `backBufferRTV`.
    ///
    /// No-ops (leaving the target untouched) when the quad's blur radius
    /// rounds to zero or its rect doesn't intersect the surface — the
    /// batch renderer's splitter never routes such quads here, and the
    /// tests pin the no-op behaviour for direct callers.
    ///
    /// Post-condition: the OM render target is `backBufferRTV` with a
    /// full-surface viewport. The engine also replaces the caller's
    /// rasterizer state, blend state, shaders, VS `b0` and PS `b0`/`b1`
    /// and does *not* put them back — `D3D11BatchRenderer` re-binds its
    /// frame pipeline state after every blurred quad instead, which is
    /// the only place that knows what the caller's state was.
    func drawBlurredQuad(
        deviceContext: UnsafeMutablePointer<ID3D11DeviceContext>,
        backBuffer: UnsafeMutablePointer<ID3D11Texture2D>,
        backBufferRTV: UnsafeMutablePointer<ID3D11RenderTargetView>,
        target: RenderTargetDescriptor,
        quad: QuadPrimitive
    ) throws {
        let surfaceWidth = target.width
        let surfaceHeight = target.height
        // Same truncation as the CPU rasterizer, and saturating for the
        // same reason it is there: a non-finite radius must round to no
        // blur, not trap.
        let radius = min(GPUISceneValue.int(quad.blurRadius), Self.maxBlurRadius)
        guard radius > 0 else { return }

        let surfaceW = max(surfaceWidth, 1)
        let surfaceH = max(surfaceHeight, 1)
        // The copy box is bounded by what the backbuffer actually is, not
        // by what the caller believes the surface to be: `resize` writes
        // the new pixel size before `ResizeBuffers` and never rolls it
        // back, so a failed resize leaves the renderer asking for a region
        // past the end of a smaller swap-chain buffer.
        // `CopySubresourceRegion` returns void and an out-of-bounds source
        // box is undefined behaviour — the call is typically dropped,
        // leaving the ping-pong target holding the previous material's
        // pixels over the whole panel.
        var backBufferDesc = D3D11_TEXTURE2D_DESC()
        backBuffer.pointee.lpVtbl.pointee.GetDesc(backBuffer, &backBufferDesc)
        let copyW = min(surfaceW, Int(backBufferDesc.Width))
        let copyH = min(surfaceH, Int(backBufferDesc.Height))
        guard copyW > 0, copyH > 0 else { return }

        let (x0, y0, x1, y1) = Self.blurRegion(
            for: quad, surfaceWidth: copyW, surfaceHeight: copyH)
        let regionW = x1 - x0
        let regionH = y1 - y0
        guard regionW > 0, regionH > 0 else { return }

        guard
            let device,
            let blurVS, let blurPS, let materialVS, let materialPS,
            let blurParamsBuffer, let frameUniformBuffer, let regionBuffer,
            let quadInstanceBuffer, let quadInstanceSRV,
            let samplerState, let blendState, let rasterizerState
        else {
            throw BatchRendererError(
                operation: "Draw blurred material quad",
                hresult: blurHresultHandle,
                details: "Backdrop blur engine is not attached to a device.")
        }

        try ensurePingPongTargets(device: device, width: regionW, height: regionH)
        guard let textureA, let rtvA, let srvA, let rtvB, let srvB else {
            throw BatchRendererError(
                operation: "Draw blurred material quad",
                hresult: blurHresultHandle,
                details: "Ping-pong blur targets are unavailable.")
        }

        // 1. Snapshot the scene-so-far region out of the backbuffer.
        var copyBox = D3D11_BOX(
            left: UINT(x0), top: UINT(y0), front: 0,
            right: UINT(x1), bottom: UINT(y1), back: 1)
        let dstResource = UnsafeMutableRawPointer(textureA).assumingMemoryBound(to: ID3D11Resource.self)
        let srcResource = UnsafeMutableRawPointer(backBuffer).assumingMemoryBound(to: ID3D11Resource.self)
        deviceContext.pointee.lpVtbl.pointee.CopySubresourceRegion(
            deviceContext, dstResource, 0, 0, 0, 0, srcResource, 0, &copyBox)

        // Shared input-assembler state for all three draws.
        deviceContext.pointee.lpVtbl.pointee.IASetInputLayout(deviceContext, nil)
        deviceContext.pointee.lpVtbl.pointee.IASetPrimitiveTopology(
            deviceContext, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST)
        deviceContext.pointee.lpVtbl.pointee.RSSetState(deviceContext, rasterizerState)

        // The shared cost model decides the schedule. It is keyed on the
        // radius alone, so the CPU rasterizer runs exactly the same number
        // of halvings over exactly the same reduced sizes.
        let plan = BlurPassPlan(radius: radius, regionWidth: regionW, regionHeight: regionH)

        // The region always sits at the ping-pong textures' origin; what
        // changes across the chain is how much of the texture the current
        // image occupies. Every UV the passes use comes out of this value,
        // so a tap can never reach the stale texels a larger previous
        // region left behind.
        var currentRegion = SubTextureRegion(
            originX: 0, originY: 0, width: regionW, height: regionH,
            textureWidth: textureCapacity.width, textureHeight: textureCapacity.height)
        // `true` while the live image is in texture A. The copy landed in A.
        var sourceIsA = true
        var nullSRV: UnsafeMutablePointer<ID3D11ShaderResourceView>?

        // 2a. Halving passes. A zero-radius blur is one bilinear tap, and
        // the viewport-to-UV mapping puts that tap exactly on the boundary
        // between texels 2i and 2i+1 — an exact 2×2 box average, with no
        // downsample shader to keep in sync.
        //
        // The UV scale comes from `halvingSource`, not from the region: the
        // shader maps a [0,1] viewport coordinate through `uv = input.uv *
        // blurUVScale.xy`, so the tap for output texel `i` lands at
        // `(i + 0.5) · span / halvedWidth`. That is `2i + 1` — the texel
        // boundary — only when the span is exactly twice the output width.
        // Deriving it from the full region instead made an odd extent drift
        // by up to a whole texel across the pass and pick up the trailing
        // column the CPU's block average drops, in both cases while the two
        // backends documented each other as exact transcriptions.
        for _ in 0..<plan.halvingPassCount {
            let halved = currentRegion.halved
            try uploadBlurParams(
                deviceContext: deviceContext,
                buffer: blurParamsBuffer,
                direction: (0, 0),
                region: currentRegion.halvingSource,
                radius: 0,
                kernel: [1]
            )
            var halvedViewport = D3D11_VIEWPORT(
                TopLeftX: 0, TopLeftY: 0,
                Width: FLOAT(halved.width), Height: FLOAT(halved.height),
                MinDepth: 0, MaxDepth: 1)
            try runBlurPass(
                deviceContext: deviceContext,
                target: sourceIsA ? rtvB : rtvA, source: sourceIsA ? srvA : srvB,
                blurVS: blurVS, blurPS: blurPS,
                paramsBuffer: blurParamsBuffer, sampler: samplerState,
                viewport: &halvedViewport
            )
            deviceContext.pointee.lpVtbl.pointee.PSSetShaderResources(deviceContext, 0, 1, &nullSRV)
            sourceIsA.toggle()
            currentRegion = halved
        }

        let kernel = gaussianBlurKernel(radius: plan.reducedRadius)
        var regionViewport = D3D11_VIEWPORT(
            TopLeftX: 0, TopLeftY: 0,
            Width: FLOAT(currentRegion.width), Height: FLOAT(currentRegion.height),
            MinDepth: 0, MaxDepth: 1)

        // 2b. Horizontal pass, then vertical. The source texture's SRV is
        // unbound after each pass because the next one makes it the render
        // target.
        for direction in [
            (1 / Float(textureCapacity.width), Float(0)),
            (Float(0), 1 / Float(textureCapacity.height)),
        ] {
            try uploadBlurParams(
                deviceContext: deviceContext,
                buffer: blurParamsBuffer,
                direction: direction,
                region: currentRegion,
                radius: plan.reducedRadius,
                kernel: kernel
            )
            try runBlurPass(
                deviceContext: deviceContext,
                target: sourceIsA ? rtvB : rtvA, source: sourceIsA ? srvA : srvB,
                blurVS: blurVS, blurPS: blurPS,
                paramsBuffer: blurParamsBuffer, sampler: samplerState,
                viewport: &regionViewport
            )
            deviceContext.pointee.lpVtbl.pointee.PSSetShaderResources(deviceContext, 0, 1, &nullSRV)
            sourceIsA.toggle()
        }

        // 3. Composite the tinted quad over the blurred backdrop.
        try uploadQuadInstance(deviceContext: deviceContext, buffer: quadInstanceBuffer, quad: quad)

        var uniforms: [Float] = [Float(surfaceW), Float(surfaceH), 0, 0]
        try uniforms.withUnsafeBytes { bytes in
            try updateSubresource(deviceContext: deviceContext, buffer: frameUniformBuffer, bytes: bytes)
        }
        // zw carries the TEXTURE size scaled by the downsample factor, not
        // the region size (see the BackdropRegion cbuffer comment in
        // BatchShaders.swift): one divide does the region mapping and the
        // bilinear upsample together. The second float4 is the clamp range
        // that keeps the upsample's bilinear footprint inside the reduced
        // region.
        var region: [Float] = [
            Float(x0), Float(y0),
            Float(textureCapacity.width * plan.downsampleFactor),
            Float(textureCapacity.height * plan.downsampleFactor),
            currentRegion.uvMinU, currentRegion.uvMinV,
            currentRegion.uvMaxU, currentRegion.uvMaxV,
        ]
        try region.withUnsafeBytes { bytes in
            try updateSubresource(deviceContext: deviceContext, buffer: regionBuffer, bytes: bytes)
        }

        var targetView: UnsafeMutablePointer<ID3D11RenderTargetView>? = backBufferRTV
        deviceContext.pointee.lpVtbl.pointee.OMSetRenderTargets(deviceContext, 1, &targetView, nil)
        var surfaceViewport = D3D11_VIEWPORT(
            TopLeftX: 0, TopLeftY: 0,
            Width: FLOAT(surfaceW), Height: FLOAT(surfaceH),
            MinDepth: 0, MaxDepth: 1)
        deviceContext.pointee.lpVtbl.pointee.RSSetViewports(deviceContext, 1, &surfaceViewport)

        let blendFactor: [FLOAT] = [0, 0, 0, 0]
        blendFactor.withUnsafeBufferPointer { factor in
            deviceContext.pointee.lpVtbl.pointee.OMSetBlendState(
                deviceContext, blendState, factor.baseAddress, UINT.max)
        }

        deviceContext.pointee.lpVtbl.pointee.VSSetShader(deviceContext, materialVS, nil, 0)
        deviceContext.pointee.lpVtbl.pointee.PSSetShader(deviceContext, materialPS, nil, 0)

        var frameCBuffer: UnsafeMutablePointer<ID3D11Buffer>? = frameUniformBuffer
        deviceContext.pointee.lpVtbl.pointee.VSSetConstantBuffers(deviceContext, 0, 1, &frameCBuffer)
        var regionCBuffer: UnsafeMutablePointer<ID3D11Buffer>? = regionBuffer
        deviceContext.pointee.lpVtbl.pointee.PSSetConstantBuffers(deviceContext, 1, 1, &regionCBuffer)

        var instanceSRV: UnsafeMutablePointer<ID3D11ShaderResourceView>? = quadInstanceSRV
        deviceContext.pointee.lpVtbl.pointee.VSSetShaderResources(deviceContext, 0, 1, &instanceSRV)
        // The chain's parity decides which side holds the blurred result;
        // an odd pass count leaves it in B.
        var backdropSRV: UnsafeMutablePointer<ID3D11ShaderResourceView>? = sourceIsA ? srvA : srvB
        deviceContext.pointee.lpVtbl.pointee.PSSetShaderResources(deviceContext, 1, 1, &backdropSRV)
        var sampler: UnsafeMutablePointer<ID3D11SamplerState>? = samplerState
        deviceContext.pointee.lpVtbl.pointee.PSSetSamplers(deviceContext, 0, 1, &sampler)

        deviceContext.pointee.lpVtbl.pointee.DrawInstanced(deviceContext, 6, 1, 0, 0)

        deviceContext.pointee.lpVtbl.pointee.VSSetShaderResources(deviceContext, 0, 1, &nullSRV)
        deviceContext.pointee.lpVtbl.pointee.PSSetShaderResources(deviceContext, 1, 1, &nullSRV)
    }

    // MARK: - Resource Management

    private func ensurePingPongTargets(
        device: UnsafeMutablePointer<ID3D11Device>,
        width: Int,
        height: Int
    ) throws {
        if textureCapacity.width >= width, textureCapacity.height >= height, textureA != nil, textureB != nil {
            return
        }

        let newWidth = max(textureCapacity.width, width)
        let newHeight = max(textureCapacity.height, height)

        releaseCOM(&srvB)
        releaseCOM(&rtvB)
        releaseCOM(&textureB)
        releaseCOM(&srvA)
        releaseCOM(&rtvA)
        releaseCOM(&textureA)

        textureA = try Self.createPingPongTexture(device: device, width: newWidth, height: newHeight)
        rtvA = try Self.createRenderTargetView(device: device, texture: textureA, label: "blur A")
        srvA = try Self.createShaderResourceView(device: device, texture: textureA, label: "blur A")
        textureB = try Self.createPingPongTexture(device: device, width: newWidth, height: newHeight)
        rtvB = try Self.createRenderTargetView(device: device, texture: textureB, label: "blur B")
        srvB = try Self.createShaderResourceView(device: device, texture: textureB, label: "blur B")
        textureCapacity = (newWidth, newHeight)
    }

    private static func createPingPongTexture(
        device: UnsafeMutablePointer<ID3D11Device>,
        width: Int,
        height: Int
    ) throws -> UnsafeMutablePointer<ID3D11Texture2D> {
        var descriptor = D3D11_TEXTURE2D_DESC()
        descriptor.Width = UINT(max(width, 1))
        descriptor.Height = UINT(max(height, 1))
        descriptor.MipLevels = 1
        descriptor.ArraySize = 1
        // Matches the swap-chain backbuffer format so CopySubresourceRegion
        // is a straight copy.
        descriptor.Format = DXGI_FORMAT_B8G8R8A8_UNORM
        descriptor.SampleDesc = DXGI_SAMPLE_DESC(Count: 1, Quality: 0)
        descriptor.Usage = D3D11_USAGE_DEFAULT
        descriptor.BindFlags = UINT(D3D11_BIND_RENDER_TARGET.rawValue | D3D11_BIND_SHADER_RESOURCE.rawValue)

        var texture: UnsafeMutablePointer<ID3D11Texture2D>?
        let hr = device.pointee.lpVtbl.pointee.CreateTexture2D(device, &descriptor, nil, &texture)
        try Self.throwIfFailed(hr, operation: "ID3D11Device.CreateTexture2D(backdropBlur)")
        guard let texture else {
            throw BatchRendererError(operation: "CreateTexture2D(backdropBlur)", hresult: blurHresultHandle)
        }
        return texture
    }

    private static func createRenderTargetView(
        device: UnsafeMutablePointer<ID3D11Device>,
        texture: UnsafeMutablePointer<ID3D11Texture2D>?,
        label: String
    ) throws -> UnsafeMutablePointer<ID3D11RenderTargetView> {
        guard let texture else {
            throw BatchRendererError(operation: "CreateRenderTargetView(\(label))", hresult: blurHresultHandle)
        }
        let resource = UnsafeMutableRawPointer(texture).assumingMemoryBound(to: ID3D11Resource.self)
        var rtv: UnsafeMutablePointer<ID3D11RenderTargetView>?
        let hr = device.pointee.lpVtbl.pointee.CreateRenderTargetView(device, resource, nil, &rtv)
        try Self.throwIfFailed(hr, operation: "ID3D11Device.CreateRenderTargetView(\(label))")
        guard let rtv else {
            throw BatchRendererError(operation: "CreateRenderTargetView(\(label))", hresult: blurHresultHandle)
        }
        return rtv
    }

    private static func createShaderResourceView(
        device: UnsafeMutablePointer<ID3D11Device>,
        texture: UnsafeMutablePointer<ID3D11Texture2D>?,
        label: String
    ) throws -> UnsafeMutablePointer<ID3D11ShaderResourceView> {
        guard let texture else {
            throw BatchRendererError(operation: "CreateShaderResourceView(\(label))", hresult: blurHresultHandle)
        }
        var srvDesc = D3D11_SHADER_RESOURCE_VIEW_DESC()
        srvDesc.Format = DXGI_FORMAT_B8G8R8A8_UNORM
        srvDesc.ViewDimension = D3D11_SRV_DIMENSION_TEXTURE2D
        withUnsafeMutablePointer(to: &srvDesc.Texture2D) { textureView in
            textureView.pointee.MostDetailedMip = 0
            textureView.pointee.MipLevels = 1
        }
        let resource = UnsafeMutableRawPointer(texture).assumingMemoryBound(to: ID3D11Resource.self)
        var srv: UnsafeMutablePointer<ID3D11ShaderResourceView>?
        let hr = device.pointee.lpVtbl.pointee.CreateShaderResourceView(device, resource, &srvDesc, &srv)
        try Self.throwIfFailed(hr, operation: "ID3D11Device.CreateShaderResourceView(\(label))")
        guard let srv else {
            throw BatchRendererError(operation: "CreateShaderResourceView(\(label))", hresult: blurHresultHandle)
        }
        return srv
    }

    private func createQuadInstanceBuffer(device: UnsafeMutablePointer<ID3D11Device>) throws {
        let strideBytes = MemoryLayout<QuadPrimitive>.stride

        var bufferDesc = D3D11_BUFFER_DESC()
        bufferDesc.ByteWidth = UINT(strideBytes)
        bufferDesc.Usage = D3D11_USAGE_DYNAMIC
        bufferDesc.BindFlags = UINT(D3D11_BIND_SHADER_RESOURCE.rawValue)
        bufferDesc.CPUAccessFlags = UINT(D3D11_CPU_ACCESS_WRITE.rawValue)
        bufferDesc.MiscFlags = UINT(D3D11_RESOURCE_MISC_BUFFER_STRUCTURED.rawValue)
        bufferDesc.StructureByteStride = UINT(strideBytes)

        let bufferHR = device.pointee.lpVtbl.pointee.CreateBuffer(device, &bufferDesc, nil, &quadInstanceBuffer)
        try Self.throwIfFailed(bufferHR, operation: "ID3D11Device.CreateBuffer(backdropBlur quad)")
        guard let quadInstanceBuffer else {
            throw BatchRendererError(operation: "CreateBuffer(backdropBlur quad)", hresult: blurHresultHandle)
        }

        var srvDesc = D3D11_SHADER_RESOURCE_VIEW_DESC()
        srvDesc.Format = DXGI_FORMAT_UNKNOWN
        srvDesc.ViewDimension = D3D11_SRV_DIMENSION_BUFFER
        withUnsafeMutablePointer(to: &srvDesc.Buffer) { bufferView in
            bufferView.pointee.FirstElement = 0
            bufferView.pointee.NumElements = 1
        }
        let resource = UnsafeMutableRawPointer(quadInstanceBuffer).assumingMemoryBound(to: ID3D11Resource.self)
        let srvHR = device.pointee.lpVtbl.pointee.CreateShaderResourceView(device, resource, &srvDesc, &quadInstanceSRV)
        try Self.throwIfFailed(srvHR, operation: "ID3D11Device.CreateShaderResourceView(backdropBlur quad)")
    }

    // MARK: - Uploads & Passes

    private func uploadBlurParams(
        deviceContext: UnsafeMutablePointer<ID3D11DeviceContext>,
        buffer: UnsafeMutablePointer<ID3D11Buffer>,
        direction: (x: Float, y: Float),
        region: SubTextureRegion,
        radius: Int,
        kernel: [Float]
    ) throws {
        var params = [Float](repeating: 0, count: Self.blurParamsFloatCount)
        params[0] = direction.x
        params[1] = direction.y
        params[2] = Float(radius)
        params[4] = region.uvWidth
        params[5] = region.uvHeight
        // Half-texel inset: the shader clamps every tap to
        // [inset, uvScale - inset], the region's outermost texel centres,
        // so taps never reach the stale texels a larger previous region
        // left in the grow-only targets. `SubTextureRegion` is where that
        // inset is defined, for this and for the composite draw.
        params[6] = region.halfTexelU
        params[7] = region.halfTexelV
        // Symmetric kernel: entry i serves taps ±i, entry 0 the centre.
        for i in 0...radius {
            params[8 + i] = kernel[radius + i]
        }
        try params.withUnsafeBytes { bytes in
            try updateSubresource(deviceContext: deviceContext, buffer: buffer, bytes: bytes)
        }
    }

    private func runBlurPass(
        deviceContext: UnsafeMutablePointer<ID3D11DeviceContext>,
        target: UnsafeMutablePointer<ID3D11RenderTargetView>,
        source: UnsafeMutablePointer<ID3D11ShaderResourceView>,
        blurVS: UnsafeMutablePointer<ID3D11VertexShader>,
        blurPS: UnsafeMutablePointer<ID3D11PixelShader>,
        paramsBuffer: UnsafeMutablePointer<ID3D11Buffer>,
        sampler: UnsafeMutablePointer<ID3D11SamplerState>,
        viewport: inout D3D11_VIEWPORT
    ) throws {
        var targetView: UnsafeMutablePointer<ID3D11RenderTargetView>? = target
        deviceContext.pointee.lpVtbl.pointee.OMSetRenderTargets(deviceContext, 1, &targetView, nil)
        deviceContext.pointee.lpVtbl.pointee.RSSetViewports(deviceContext, 1, &viewport)

        // Blur passes write the full texel value; disable blending so the
        // destination's previous contents don't leak in.
        var nullBlend: UnsafeMutablePointer<ID3D11BlendState>?
        let blendFactor: [FLOAT] = [0, 0, 0, 0]
        blendFactor.withUnsafeBufferPointer { factor in
            deviceContext.pointee.lpVtbl.pointee.OMSetBlendState(
                deviceContext, nullBlend, factor.baseAddress, UINT.max)
        }

        deviceContext.pointee.lpVtbl.pointee.VSSetShader(deviceContext, blurVS, nil, 0)
        deviceContext.pointee.lpVtbl.pointee.PSSetShader(deviceContext, blurPS, nil, 0)

        var cbuffer: UnsafeMutablePointer<ID3D11Buffer>? = paramsBuffer
        deviceContext.pointee.lpVtbl.pointee.PSSetConstantBuffers(deviceContext, 0, 1, &cbuffer)
        var sourceSRV: UnsafeMutablePointer<ID3D11ShaderResourceView>? = source
        deviceContext.pointee.lpVtbl.pointee.PSSetShaderResources(deviceContext, 0, 1, &sourceSRV)
        var samplerState: UnsafeMutablePointer<ID3D11SamplerState>? = sampler
        deviceContext.pointee.lpVtbl.pointee.PSSetSamplers(deviceContext, 0, 1, &samplerState)

        deviceContext.pointee.lpVtbl.pointee.Draw(deviceContext, 3, 0)
    }

    private func uploadQuadInstance(
        deviceContext: UnsafeMutablePointer<ID3D11DeviceContext>,
        buffer: UnsafeMutablePointer<ID3D11Buffer>,
        quad: QuadPrimitive
    ) throws {
        let resource = UnsafeMutableRawPointer(buffer).assumingMemoryBound(to: ID3D11Resource.self)
        var mapped = D3D11_MAPPED_SUBRESOURCE()
        let mapHR = deviceContext.pointee.lpVtbl.pointee.Map(
            deviceContext, resource, 0, D3D11_MAP_WRITE_DISCARD, 0, &mapped)
        try Self.throwIfFailed(mapHR, operation: "ID3D11DeviceContext.Map(backdropBlur quad)")
        guard let pData = mapped.pData else {
            deviceContext.pointee.lpVtbl.pointee.Unmap(deviceContext, resource, 0)
            throw BatchRendererError(operation: "Map(backdropBlur quad) returned nil", hresult: blurHresultHandle)
        }
        var mutableQuad = quad
        withUnsafeBytes(of: &mutableQuad) { bytes in
            if let baseAddress = bytes.baseAddress {
                memcpy(pData, baseAddress, MemoryLayout<QuadPrimitive>.stride)
            }
        }
        deviceContext.pointee.lpVtbl.pointee.Unmap(deviceContext, resource, 0)
    }

    private func updateSubresource(
        deviceContext: UnsafeMutablePointer<ID3D11DeviceContext>,
        buffer: UnsafeMutablePointer<ID3D11Buffer>,
        bytes: UnsafeRawBufferPointer
    ) throws {
        guard let baseAddress = bytes.baseAddress else { return }
        let resource = UnsafeMutableRawPointer(buffer).assumingMemoryBound(to: ID3D11Resource.self)
        deviceContext.pointee.lpVtbl.pointee.UpdateSubresource(
            deviceContext, resource, 0, nil, baseAddress, 0, 0)
    }

    // MARK: - Shader Compilation

    private static func compileVertexShader(
        device: UnsafeMutablePointer<ID3D11Device>,
        source: String,
        label: String
    ) throws -> UnsafeMutablePointer<ID3D11VertexShader> {
        var blob: UnsafeMutablePointer<ID3DBlob>? = try compileShaderSource(
            source: source, entryPoint: "vsMain", profile: "vs_5_0", label: label)
        defer { releaseCOM(&blob) }
        guard let blob else {
            throw BatchRendererError(operation: "Compile \(label) vertex shader", hresult: blurHresultHandle)
        }
        var shader: UnsafeMutablePointer<ID3D11VertexShader>?
        let hr = device.pointee.lpVtbl.pointee.CreateVertexShader(
            device,
            blob.pointee.lpVtbl.pointee.GetBufferPointer(blob),
            SIZE_T(blob.pointee.lpVtbl.pointee.GetBufferSize(blob)),
            nil,
            &shader
        )
        try Self.throwIfFailed(hr, operation: "ID3D11Device.CreateVertexShader(\(label))")
        guard let shader else {
            throw BatchRendererError(operation: "CreateVertexShader(\(label))", hresult: blurHresultHandle)
        }
        return shader
    }

    private static func compilePixelShader(
        device: UnsafeMutablePointer<ID3D11Device>,
        source: String,
        label: String
    ) throws -> UnsafeMutablePointer<ID3D11PixelShader> {
        var blob: UnsafeMutablePointer<ID3DBlob>? = try compileShaderSource(
            source: source, entryPoint: "psMain", profile: "ps_5_0", label: label)
        defer { releaseCOM(&blob) }
        guard let blob else {
            throw BatchRendererError(operation: "Compile \(label) pixel shader", hresult: blurHresultHandle)
        }
        var shader: UnsafeMutablePointer<ID3D11PixelShader>?
        let hr = device.pointee.lpVtbl.pointee.CreatePixelShader(
            device,
            blob.pointee.lpVtbl.pointee.GetBufferPointer(blob),
            SIZE_T(blob.pointee.lpVtbl.pointee.GetBufferSize(blob)),
            nil,
            &shader
        )
        try Self.throwIfFailed(hr, operation: "ID3D11Device.CreatePixelShader(\(label))")
        guard let shader else {
            throw BatchRendererError(operation: "CreatePixelShader(\(label))", hresult: blurHresultHandle)
        }
        return shader
    }

    private static func compileShaderSource(
        source: String,
        entryPoint: String,
        profile: String,
        label: String
    ) throws -> UnsafeMutablePointer<ID3DBlob> {
        let sourceBytes = Array(source.utf8)
        var shaderBlob: UnsafeMutablePointer<ID3DBlob>?
        var errorBlob: UnsafeMutablePointer<ID3DBlob>?

        let hr = sourceBytes.withUnsafeBytes { sourceBuffer in
            entryPoint.withCString { entryPointCString in
                profile.withCString { profileCString in
                    D3DCompile(
                        sourceBuffer.baseAddress,
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
            var details: String?
            if let errorBlob,
                let rawPointer = errorBlob.pointee.lpVtbl.pointee.GetBufferPointer(errorBlob)
            {
                details = String(cString: rawPointer.assumingMemoryBound(to: CChar.self))
            }
            releaseCOM(&errorBlob)
            throw BatchRendererError(operation: "D3DCompile(\(label).\(entryPoint))", hresult: hr, details: details)
        }

        releaseCOM(&errorBlob)
        guard let shaderBlob else {
            throw BatchRendererError(operation: "D3DCompile(\(label).\(entryPoint))", hresult: blurHresultHandle)
        }
        return shaderBlob
    }

    private static func createConstantBuffer(
        device: UnsafeMutablePointer<ID3D11Device>,
        byteWidth: UINT,
        label: String
    ) throws -> UnsafeMutablePointer<ID3D11Buffer> {
        var descriptor = D3D11_BUFFER_DESC()
        descriptor.ByteWidth = byteWidth
        descriptor.Usage = D3D11_USAGE_DEFAULT
        descriptor.BindFlags = UINT(D3D11_BIND_CONSTANT_BUFFER.rawValue)
        var buffer: UnsafeMutablePointer<ID3D11Buffer>?
        let hr = device.pointee.lpVtbl.pointee.CreateBuffer(device, &descriptor, nil, &buffer)
        try Self.throwIfFailed(hr, operation: "ID3D11Device.CreateBuffer(\(label))")
        guard let buffer else {
            throw BatchRendererError(operation: "CreateBuffer(\(label))", hresult: blurHresultHandle)
        }
        return buffer
    }

    private static func throwIfFailed(_ hr: HRESULT, operation: String) throws {
        if hr < 0 {
            throw BatchRendererError(operation: operation, hresult: hr)
        }
    }
}

private let blurHresultHandle: HRESULT = HRESULT(bitPattern: 0x8007_0006)
