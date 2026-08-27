import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import WinSDK
import WinSDK.DirectX
import XCTest

@testable import SwiftWindowsRendererD3D11

/// WARP-level pixel verification of the D3D11 glyph pipeline
/// (`GlyphPipeline` shaders + linear-clamp sampler + premultiplied blend,
/// wired exactly as `D3D11BatchRenderer.renderGlyphBatch` wires them).
///
/// The glyph-emission contract says a native glyph quad is integer-snapped
/// and exactly as wide as its atlas entry (`screenW == entryWidth`). These
/// tests pin what that contract buys at the shader level:
///
/// 1. An integer-aligned, unstretched quad samples the atlas 1:1 — ink
///    covers exactly the entry's texels, no widening, no shift.
/// 2. A quad stretched even 1px wider than its atlas entry bleeds ink into
///    the extra pixel — the exact widening mechanism suspected behind the
///    fractional-scale fidelity gap.
/// 3. A fractional-origin quad linearly filters the edges (no "doubled"
///    texels) and shifts the ink centroid by the fractional offset.
@MainActor
final class D3D11GlyphShaderPixelTests: XCTestCase {

    // MARK: - Harness

    // The headless WARP device lives in WARPRenderHarness.swift, shared with
    // every other GPU-backed suite in this target.

    /// All GPU objects needed to draw glyph quads the way the batch renderer
    /// does, plus the offscreen target they draw into.
    private struct GlyphDrawHarness {
        var target: UnsafeMutablePointer<ID3D11Texture2D>?
        var rtv: UnsafeMutablePointer<ID3D11RenderTargetView>?
        var atlas: UnsafeMutablePointer<ID3D11Texture2D>?
        var atlasSRV: UnsafeMutablePointer<ID3D11ShaderResourceView>?
        var instanceBuffer: UnsafeMutablePointer<ID3D11Buffer>?
        var instanceSRV: UnsafeMutablePointer<ID3D11ShaderResourceView>?
        var frameUniforms: UnsafeMutablePointer<ID3D11Buffer>?
        var vertexShader: UnsafeMutablePointer<ID3D11VertexShader>?
        var pixelShader: UnsafeMutablePointer<ID3D11PixelShader>?
        var blendState: UnsafeMutablePointer<ID3D11BlendState>?
        var rasterizerState: UnsafeMutablePointer<ID3D11RasterizerState>?
        var samplerState: UnsafeMutablePointer<ID3D11SamplerState>?
        let width: Int
        let height: Int

        func release() {
            var chain: [UnsafeMutableRawPointer?] = [
                rtv.map { UnsafeMutableRawPointer($0) },
                target.map { UnsafeMutableRawPointer($0) },
                atlasSRV.map { UnsafeMutableRawPointer($0) },
                atlas.map { UnsafeMutableRawPointer($0) },
                instanceSRV.map { UnsafeMutableRawPointer($0) },
                instanceBuffer.map { UnsafeMutableRawPointer($0) },
                frameUniforms.map { UnsafeMutableRawPointer($0) },
                vertexShader.map { UnsafeMutableRawPointer($0) },
                pixelShader.map { UnsafeMutableRawPointer($0) },
                blendState.map { UnsafeMutableRawPointer($0) },
                rasterizerState.map { UnsafeMutableRawPointer($0) },
                samplerState.map { UnsafeMutableRawPointer($0) },
            ]
            for index in chain.indices {
                if let pointer = chain[index] {
                    let unknown = pointer.assumingMemoryBound(to: IUnknown.self)
                    _ = unknown.pointee.lpVtbl.pointee.Release(unknown)
                    chain[index] = nil
                }
            }
        }
    }

    /// Synthetic 64x64 atlas: an 8x8 "glyph" entry at texel (8, 8) whose
    /// alpha ramps left-to-right through `Self.ramp`, RGB pinned to white.
    private static let ramp: [UInt8] = [16, 48, 80, 112, 144, 176, 208, 240]
    private static let atlasTexelCount = 64
    private static let entryOrigin = (x: 8, y: 8)
    private static let entrySize = 8

    private static func makeAtlasPixels() -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: atlasTexelCount * atlasTexelCount * 4)
        for y in 0..<entrySize {
            for x in 0..<entrySize {
                let offset = ((entryOrigin.y + y) * atlasTexelCount + entryOrigin.x + x) * 4
                pixels[offset] = 255  // B
                pixels[offset + 1] = 255  // G
                pixels[offset + 2] = 255  // R
                pixels[offset + 3] = ramp[x]  // A (coverage)
            }
        }
        return pixels
    }

    private func makeHarness(device: WARPDevice, width: Int, height: Int) throws -> GlyphDrawHarness {
        guard let d3dDevice = device.device, let context = device.context else {
            throw XCTSkip("Headless device unavailable")
        }
        var harness = GlyphDrawHarness(width: width, height: height)

        // Offscreen render target standing in for the swap-chain backbuffer.
        var targetDesc = D3D11_TEXTURE2D_DESC()
        targetDesc.Width = UINT(width)
        targetDesc.Height = UINT(height)
        targetDesc.MipLevels = 1
        targetDesc.ArraySize = 1
        targetDesc.Format = DXGI_FORMAT_B8G8R8A8_UNORM
        targetDesc.SampleDesc = DXGI_SAMPLE_DESC(Count: 1, Quality: 0)
        targetDesc.Usage = D3D11_USAGE_DEFAULT
        targetDesc.BindFlags = UINT(D3D11_BIND_RENDER_TARGET.rawValue)
        var createHR = d3dDevice.pointee.lpVtbl.pointee.CreateTexture2D(d3dDevice, &targetDesc, nil, &harness.target)
        XCTAssertGreaterThanOrEqual(createHR, 0, "CreateTexture2D(target) failed")
        let targetResource = UnsafeMutableRawPointer(harness.target!).assumingMemoryBound(to: ID3D11Resource.self)
        createHR = d3dDevice.pointee.lpVtbl.pointee.CreateRenderTargetView(
            d3dDevice, targetResource, nil, &harness.rtv)
        XCTAssertGreaterThanOrEqual(createHR, 0, "CreateRenderTargetView failed")

        // Glyph atlas texture (same format/upload shape as the renderer).
        var atlasDesc = D3D11_TEXTURE2D_DESC()
        atlasDesc.Width = UINT(Self.atlasTexelCount)
        atlasDesc.Height = UINT(Self.atlasTexelCount)
        atlasDesc.MipLevels = 1
        atlasDesc.ArraySize = 1
        atlasDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM
        atlasDesc.SampleDesc = DXGI_SAMPLE_DESC(Count: 1, Quality: 0)
        atlasDesc.Usage = D3D11_USAGE_DEFAULT
        atlasDesc.BindFlags = UINT(D3D11_BIND_SHADER_RESOURCE.rawValue)
        var atlasPixels = Self.makeAtlasPixels()
        var initialData = D3D11_SUBRESOURCE_DATA()
        atlasPixels.withUnsafeBytes { bytes in
            initialData.pSysMem = bytes.baseAddress
            initialData.SysMemPitch = UINT(Self.atlasTexelCount * 4)
            createHR = d3dDevice.pointee.lpVtbl.pointee.CreateTexture2D(
                d3dDevice, &atlasDesc, &initialData, &harness.atlas)
        }
        XCTAssertGreaterThanOrEqual(createHR, 0, "CreateTexture2D(atlas) failed")
        var atlasSRVDesc = D3D11_SHADER_RESOURCE_VIEW_DESC()
        atlasSRVDesc.Format = atlasDesc.Format
        atlasSRVDesc.ViewDimension = D3D11_SRV_DIMENSION_TEXTURE2D
        withUnsafeMutablePointer(to: &atlasSRVDesc.Texture2D) { view in
            view.pointee.MostDetailedMip = 0
            view.pointee.MipLevels = 1
        }
        let atlasResource = UnsafeMutableRawPointer(harness.atlas!).assumingMemoryBound(to: ID3D11Resource.self)
        createHR = d3dDevice.pointee.lpVtbl.pointee.CreateShaderResourceView(
            d3dDevice, atlasResource, &atlasSRVDesc, &harness.atlasSRV)
        XCTAssertGreaterThanOrEqual(createHR, 0, "CreateShaderResourceView(atlas) failed")

        // Structured instance buffer holding one GlyphPrimitive.
        let stride = MemoryLayout<GlyphPrimitive>.stride
        XCTAssertEqual(stride, 80, "GlyphInstance layout pin drifted")
        var bufferDesc = D3D11_BUFFER_DESC()
        bufferDesc.ByteWidth = UINT(stride)
        bufferDesc.Usage = D3D11_USAGE_DEFAULT
        bufferDesc.BindFlags = UINT(D3D11_BIND_SHADER_RESOURCE.rawValue)
        bufferDesc.MiscFlags = UINT(D3D11_RESOURCE_MISC_BUFFER_STRUCTURED.rawValue)
        bufferDesc.StructureByteStride = UINT(stride)
        createHR = d3dDevice.pointee.lpVtbl.pointee.CreateBuffer(d3dDevice, &bufferDesc, nil, &harness.instanceBuffer)
        XCTAssertGreaterThanOrEqual(createHR, 0, "CreateBuffer(instances) failed")
        var instanceSRVDesc = D3D11_SHADER_RESOURCE_VIEW_DESC()
        instanceSRVDesc.Format = DXGI_FORMAT_UNKNOWN
        instanceSRVDesc.ViewDimension = D3D11_SRV_DIMENSION_BUFFER
        withUnsafeMutablePointer(to: &instanceSRVDesc.Buffer) { view in
            view.pointee.FirstElement = 0
            view.pointee.NumElements = 1
        }
        let bufferResource = UnsafeMutableRawPointer(harness.instanceBuffer!).assumingMemoryBound(
            to: ID3D11Resource.self)
        createHR = d3dDevice.pointee.lpVtbl.pointee.CreateShaderResourceView(
            d3dDevice, bufferResource, &instanceSRVDesc, &harness.instanceSRV)
        XCTAssertGreaterThanOrEqual(createHR, 0, "CreateShaderResourceView(instances) failed")

        // Frame uniforms (surfaceSize + padding).
        var uniformsDesc = D3D11_BUFFER_DESC()
        uniformsDesc.ByteWidth = 16
        uniformsDesc.Usage = D3D11_USAGE_DYNAMIC
        uniformsDesc.BindFlags = UINT(D3D11_BIND_CONSTANT_BUFFER.rawValue)
        uniformsDesc.CPUAccessFlags = UINT(D3D11_CPU_ACCESS_WRITE.rawValue)
        createHR = d3dDevice.pointee.lpVtbl.pointee.CreateBuffer(
            d3dDevice, &uniformsDesc, nil, &harness.frameUniforms)
        XCTAssertGreaterThanOrEqual(createHR, 0, "CreateBuffer(frameUniforms) failed")
        var uniforms: [Float] = [Float(width), Float(height), 0, 0]
        var mapped = D3D11_MAPPED_SUBRESOURCE()
        let bufferForMap = harness.frameUniforms!
        let mapHR = context.pointee.lpVtbl.pointee.Map(
            context,
            UnsafeMutableRawPointer(bufferForMap).assumingMemoryBound(to: ID3D11Resource.self),
            0,
            D3D11_MAP_WRITE_DISCARD,
            0,
            &mapped
        )
        XCTAssertGreaterThanOrEqual(mapHR, 0, "Map(frameUniforms) failed")
        uniforms.withUnsafeBytes { bytes in
            memcpy(mapped.pData, bytes.baseAddress, 16)
        }
        context.pointee.lpVtbl.pointee.Unmap(
            context, UnsafeMutableRawPointer(bufferForMap).assumingMemoryBound(to: ID3D11Resource.self), 0)

        // Shaders: the real glyph pipeline sources.
        var vsBlob: UnsafeMutablePointer<ID3DBlob>? = try compileShaderSource(
            source: GlyphPipelineResources.vertexShaderSource,
            entryPoint: GlyphPipelineResources.vertexShaderEntryPoint,
            profile: "vs_5_0"
        )
        var psBlob: UnsafeMutablePointer<ID3DBlob>? = try compileShaderSource(
            source: GlyphPipelineResources.vertexShaderSource,
            entryPoint: GlyphPipelineResources.pixelShaderEntryPoint,
            profile: "ps_5_0"
        )
        defer {
            releaseCOM(&vsBlob)
            releaseCOM(&psBlob)
        }
        createHR = d3dDevice.pointee.lpVtbl.pointee.CreateVertexShader(
            d3dDevice,
            vsBlob!.pointee.lpVtbl.pointee.GetBufferPointer(vsBlob),
            SIZE_T(vsBlob!.pointee.lpVtbl.pointee.GetBufferSize(vsBlob)),
            nil,
            &harness.vertexShader
        )
        XCTAssertGreaterThanOrEqual(createHR, 0, "CreateVertexShader failed")
        createHR = d3dDevice.pointee.lpVtbl.pointee.CreatePixelShader(
            d3dDevice,
            psBlob!.pointee.lpVtbl.pointee.GetBufferPointer(psBlob),
            SIZE_T(psBlob!.pointee.lpVtbl.pointee.GetBufferSize(psBlob)),
            nil,
            &harness.pixelShader
        )
        XCTAssertGreaterThanOrEqual(createHR, 0, "CreatePixelShader failed")

        // Blend / rasterizer / sampler states — identical descriptors to the
        // batch renderer's shared state.
        var blendDesc = D3D11_BLEND_DESC()
        blendDesc.AlphaToCoverageEnable = false
        blendDesc.IndependentBlendEnable = false
        blendDesc.RenderTarget.0.BlendEnable = true
        blendDesc.RenderTarget.0.SrcBlend = D3D11_BLEND_ONE
        blendDesc.RenderTarget.0.DestBlend = D3D11_BLEND_INV_SRC_ALPHA
        blendDesc.RenderTarget.0.BlendOp = D3D11_BLEND_OP_ADD
        blendDesc.RenderTarget.0.SrcBlendAlpha = D3D11_BLEND_ONE
        blendDesc.RenderTarget.0.DestBlendAlpha = D3D11_BLEND_INV_SRC_ALPHA
        blendDesc.RenderTarget.0.BlendOpAlpha = D3D11_BLEND_OP_ADD
        blendDesc.RenderTarget.0.RenderTargetWriteMask = UINT8(D3D11_COLOR_WRITE_ENABLE_ALL.rawValue)
        createHR = d3dDevice.pointee.lpVtbl.pointee.CreateBlendState(d3dDevice, &blendDesc, &harness.blendState)
        XCTAssertGreaterThanOrEqual(createHR, 0, "CreateBlendState failed")

        var rasterizerDesc = D3D11_RASTERIZER_DESC()
        rasterizerDesc.FillMode = D3D11_FILL_SOLID
        rasterizerDesc.CullMode = D3D11_CULL_NONE
        rasterizerDesc.ScissorEnable = false
        rasterizerDesc.DepthClipEnable = false
        createHR = d3dDevice.pointee.lpVtbl.pointee.CreateRasterizerState(
            d3dDevice, &rasterizerDesc, &harness.rasterizerState)
        XCTAssertGreaterThanOrEqual(createHR, 0, "CreateRasterizerState failed")

        var samplerDesc = D3D11_SAMPLER_DESC()
        samplerDesc.Filter = D3D11_FILTER_MIN_MAG_MIP_LINEAR
        samplerDesc.AddressU = D3D11_TEXTURE_ADDRESS_CLAMP
        samplerDesc.AddressV = D3D11_TEXTURE_ADDRESS_CLAMP
        samplerDesc.AddressW = D3D11_TEXTURE_ADDRESS_CLAMP
        samplerDesc.MaxLOD = FLOAT(D3D11_FLOAT32_MAX)
        createHR = d3dDevice.pointee.lpVtbl.pointee.CreateSamplerState(d3dDevice, &samplerDesc, &harness.samplerState)
        XCTAssertGreaterThanOrEqual(createHR, 0, "CreateSamplerState failed")

        return harness
    }

    /// Draws one glyph quad over an opaque-black target and reads the pixels
    /// back (BGRA).
    private func drawAndReadBack(
        device: WARPDevice,
        harness: GlyphDrawHarness,
        glyph: GlyphPrimitive
    ) throws -> [UInt8] {
        guard let context = device.context else {
            throw XCTSkip("Headless device unavailable")
        }

        // Upload the instance.
        var instance = glyph
        withUnsafeBytes(of: &instance) { bytes in
            context.pointee.lpVtbl.pointee.UpdateSubresource(
                context,
                UnsafeMutableRawPointer(harness.instanceBuffer!).assumingMemoryBound(to: ID3D11Resource.self),
                0,
                nil,
                bytes.baseAddress,
                0,
                0
            )
        }

        var rtv = harness.rtv
        context.pointee.lpVtbl.pointee.OMSetRenderTargets(context, 1, &rtv, nil)
        var clearColor: [Float] = [0, 0, 0, 1]
        context.pointee.lpVtbl.pointee.ClearRenderTargetView(context, harness.rtv, &clearColor)

        var viewport = D3D11_VIEWPORT(
            TopLeftX: 0,
            TopLeftY: 0,
            Width: FLOAT(harness.width),
            Height: FLOAT(harness.height),
            MinDepth: 0,
            MaxDepth: 1
        )
        context.pointee.lpVtbl.pointee.RSSetViewports(context, 1, &viewport)

        context.pointee.lpVtbl.pointee.IASetPrimitiveTopology(
            context, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST)
        context.pointee.lpVtbl.pointee.IASetInputLayout(context, nil)
        context.pointee.lpVtbl.pointee.VSSetShader(context, harness.vertexShader, nil, 0)
        context.pointee.lpVtbl.pointee.PSSetShader(context, harness.pixelShader, nil, 0)
        var constantBuffer = harness.frameUniforms
        context.pointee.lpVtbl.pointee.VSSetConstantBuffers(context, 0, 1, &constantBuffer)
        var instanceSRV = harness.instanceSRV
        context.pointee.lpVtbl.pointee.VSSetShaderResources(context, 0, 1, &instanceSRV)
        var atlasSRV = harness.atlasSRV
        context.pointee.lpVtbl.pointee.PSSetShaderResources(context, 1, 1, &atlasSRV)
        var sampler = harness.samplerState
        context.pointee.lpVtbl.pointee.PSSetSamplers(context, 0, 1, &sampler)
        let blendFactor: [FLOAT] = [0, 0, 0, 0]
        blendFactor.withUnsafeBufferPointer { buffer in
            context.pointee.lpVtbl.pointee.OMSetBlendState(context, harness.blendState, buffer.baseAddress, UINT.max)
        }
        context.pointee.lpVtbl.pointee.RSSetState(context, harness.rasterizerState)

        context.pointee.lpVtbl.pointee.DrawInstanced(context, 6, 1, 0, 0)

        // Read back through a staging texture.
        var stagingDesc = D3D11_TEXTURE2D_DESC()
        stagingDesc.Width = UINT(harness.width)
        stagingDesc.Height = UINT(harness.height)
        stagingDesc.MipLevels = 1
        stagingDesc.ArraySize = 1
        stagingDesc.Format = DXGI_FORMAT_B8G8R8A8_UNORM
        stagingDesc.SampleDesc = DXGI_SAMPLE_DESC(Count: 1, Quality: 0)
        stagingDesc.Usage = D3D11_USAGE_STAGING
        stagingDesc.CPUAccessFlags = UINT(D3D11_CPU_ACCESS_READ.rawValue)
        var staging: UnsafeMutablePointer<ID3D11Texture2D>?
        let createHR = device.device!.pointee.lpVtbl.pointee.CreateTexture2D(
            device.device!, &stagingDesc, nil, &staging)
        XCTAssertGreaterThanOrEqual(createHR, 0, "CreateTexture2D(staging) failed")
        defer {
            var releasable = staging
            releaseCOM(&releasable)
        }
        let dstResource = UnsafeMutableRawPointer(staging!).assumingMemoryBound(to: ID3D11Resource.self)
        let srcResource = UnsafeMutableRawPointer(harness.target!).assumingMemoryBound(to: ID3D11Resource.self)
        context.pointee.lpVtbl.pointee.CopyResource(context, dstResource, srcResource)

        var mapped = D3D11_MAPPED_SUBRESOURCE()
        let mapHR = context.pointee.lpVtbl.pointee.Map(context, dstResource, 0, D3D11_MAP_READ, 0, &mapped)
        XCTAssertGreaterThanOrEqual(mapHR, 0, "Map(staging) failed")
        var pixels = [UInt8](repeating: 0, count: harness.width * harness.height * 4)
        for row in 0..<harness.height {
            let sourceRow = mapped.pData!.advanced(by: row * Int(mapped.RowPitch))
            let destination = row * harness.width * 4
            pixels.withUnsafeMutableBufferPointer { buffer in
                memcpy(buffer.baseAddress!.advanced(by: destination), sourceRow, harness.width * 4)
            }
        }
        context.pointee.lpVtbl.pointee.Unmap(context, dstResource, 0)
        return pixels
    }

    /// Red channel along row `y` — on the opaque-black target it equals the
    /// blended glyph coverage (white ink, premultiplied source-over).
    private func redRow(_ pixels: [UInt8], width: Int, y: Int) -> [Int] {
        (0..<width).map { x in Int(pixels[(y * width + x) * 4 + 2]) }
    }

    private func makeEntryGlyph(screenX: Float, screenY: Float, screenW: Float) -> GlyphPrimitive {
        let atlasSize = Float(Self.atlasTexelCount)
        return GlyphPrimitive(
            screenX: screenX,
            screenY: screenY,
            screenW: screenW,
            screenH: Float(Self.entrySize),
            atlasU0: Float(Self.entryOrigin.x) / atlasSize,
            atlasV0: Float(Self.entryOrigin.y) / atlasSize,
            atlasU1: Float(Self.entryOrigin.x + Self.entrySize) / atlasSize,
            atlasV1: Float(Self.entryOrigin.y + Self.entrySize) / atlasSize,
            colorR: 1, colorG: 1, colorB: 1, colorA: 1,
            clipX: 0, clipY: 0, clipWidth: 0, clipHeight: 0
        )
    }

    // MARK: - Tests

    /// A scrolling viewport must cut off a glyph at its trailing edge even
    /// when the edge passes exactly through a device-pixel centre.
    func testGlyphDoesNotBleedAcrossFractionalTrailingClipEdges() async throws {
        let device = try makeWARPDevice()
        defer { device.release() }
        let harness = try makeHarness(device: device, width: 64, height: 32)
        defer { harness.release() }

        var glyph = makeEntryGlyph(screenX: 16, screenY: 12, screenW: Float(Self.entrySize))
        glyph.clipX = 16.5
        glyph.clipY = 12.5
        glyph.clipWidth = 4
        glyph.clipHeight = 4
        let pixels = try drawAndReadBack(device: device, harness: harness, glyph: glyph)

        XCTAssertGreaterThan(redRow(pixels, width: harness.width, y: 12)[16], 0, "leading edges remain inclusive")
        XCTAssertGreaterThan(redRow(pixels, width: harness.width, y: 15)[19], 0, "ink inside the clip remains visible")
        XCTAssertEqual(redRow(pixels, width: harness.width, y: 15)[20], 0, "right-edge pixel belongs outside the clip")
        XCTAssertEqual(redRow(pixels, width: harness.width, y: 16)[19], 0, "bottom-edge pixel belongs outside the clip")
    }

    /// The contract the painter relies on: an integer-snapped quad exactly
    /// as wide as its atlas entry samples the atlas 1:1 — every destination
    /// pixel maps to a texel centre, so ink covers precisely the entry's
    /// columns and not one pixel more.
    func testIntegerAlignedUnstretchedGlyphQuadSamplesAtlasOneToOne() async throws {
        let device = try makeWARPDevice()
        defer { device.release() }
        let harness = try makeHarness(device: device, width: 64, height: 32)
        defer { harness.release() }

        let glyph = makeEntryGlyph(screenX: 16, screenY: 12, screenW: Float(Self.entrySize))
        let pixels = try drawAndReadBack(device: device, harness: harness, glyph: glyph)
        let row = redRow(pixels, width: harness.width, y: 16)

        XCTAssertEqual(row[15], 0, "no ink may bleed left of the quad")
        for column in 0..<Self.entrySize {
            XCTAssertEqual(
                row[16 + column], Int(Self.ramp[column]), accuracy: 2,
                "column \(column) must sample atlas texel \(column) verbatim")
        }
        XCTAssertEqual(row[16 + Self.entrySize], 0, "no ink may bleed right of the quad")
    }

    /// Documents the widening mechanism suspected behind the fractional-scale
    /// fidelity gap: if a glyph quad is even 1px wider than its atlas entry,
    /// linear filtering bleeds ink into the extra pixel column. Emission must
    /// keep `screenW == entryWidth`.
    func testStretchedGlyphQuadBleedsInkIntoExtraColumn() async throws {
        let device = try makeWARPDevice()
        defer { device.release() }
        let harness = try makeHarness(device: device, width: 64, height: 32)
        defer { harness.release() }

        let glyph = makeEntryGlyph(
            screenX: 16, screenY: 12, screenW: Float(Self.entrySize + 1))
        let pixels = try drawAndReadBack(device: device, harness: harness, glyph: glyph)
        let row = redRow(pixels, width: harness.width, y: 16)

        XCTAssertGreaterThan(
            row[16 + Self.entrySize], 24,
            "a 1px-stretched quad must bleed visible ink into the 9th column")
    }

    /// A fractional-origin quad (what the painter would emit without integer
    /// snapping) linearly filters both edges instead of doubling texels:
    /// with the origin shifted +0.5px, each destination pixel samples
    /// halfway between adjacent atlas texels.
    func testFractionalOriginGlyphQuadFiltersEdgesAndShiftsCentroid() async throws {
        let device = try makeWARPDevice()
        defer { device.release() }
        let harness = try makeHarness(device: device, width: 64, height: 32)
        defer { harness.release() }

        let fractional = makeEntryGlyph(screenX: 16.5, screenY: 12, screenW: Float(Self.entrySize))
        let fractionalPixels = try drawAndReadBack(device: device, harness: harness, glyph: fractional)
        let row = redRow(fractionalPixels, width: harness.width, y: 16)

        // Quad spans [16.5, 24.5]: pixel 16's centre sits exactly on the
        // left edge (covered, texel-boundary sample), pixel 24's centre on
        // the right edge (excluded by the top-left rule). Pixel 16+i
        // samples halfway between atlas columns i-1 and i.
        let ramp = Self.ramp.map(Int.init)
        let expected = [
            ramp[0] / 2,
            (ramp[0] + ramp[1]) / 2,
            (ramp[1] + ramp[2]) / 2,
            (ramp[2] + ramp[3]) / 2,
            (ramp[3] + ramp[4]) / 2,
            (ramp[4] + ramp[5]) / 2,
            (ramp[5] + ramp[6]) / 2,
            (ramp[6] + ramp[7]) / 2,
        ]
        for column in 0..<Self.entrySize {
            XCTAssertEqual(
                row[16 + column], expected[column], accuracy: 3,
                "fractional column \(column) must blend atlas columns \(column - 1)/\(column)")
        }
        XCTAssertEqual(row[15], 0, "no ink left of the fractional quad")
        XCTAssertEqual(row[16 + Self.entrySize], 0, "right-edge pixel is excluded by the top-left rule")
        XCTAssertGreaterThan(row[16], 0, "fractional origin still touches the leading pixel")
    }

    /// Same-scene parity pin: for the integer-snapped quads the painter
    /// actually emits, the CPU reference rasterizer and the D3D11 shader must
    /// produce the same ink row — any divergence here is a backend bug, not
    /// a scene bug.
    func testCPURasterizerMatchesD3D11ForIntegerSnappedGlyphQuad() async throws {
        let device = try makeWARPDevice()
        defer { device.release() }
        let harness = try makeHarness(device: device, width: 64, height: 32)
        defer { harness.release() }

        let glyph = makeEntryGlyph(screenX: 16, screenY: 12, screenW: Float(Self.entrySize))
        let gpuPixels = try drawAndReadBack(device: device, harness: harness, glyph: glyph)
        let gpuRow = redRow(gpuPixels, width: harness.width, y: 16)

        var scene = GPUIScene(clearColor: .black)
        scene.addGlyph(glyph)
        scene.glyphAtlas = GlyphAtlasSnapshot(
            width: Int32(Self.atlasTexelCount),
            height: Int32(Self.atlasTexelCount),
            pixels: Data(Self.makeAtlasPixels()),
            contentVersion: RenderContentVersion.next(),
            update: .full
        )
        let bitmap = GPUIRawSceneRasterizer.rasterize(
            scene, size: IntSize(width: Int32(harness.width), height: Int32(harness.height)))
        let cpuRow = redRow([UInt8](bitmap.pixels), width: Int(bitmap.width), y: 16)

        for column in 0..<harness.width {
            XCTAssertEqual(
                gpuRow[column], cpuRow[column], accuracy: 2,
                "D3D11 vs CPU diverge at column \(column): gpu=\(gpuRow[column]) cpu=\(cpuRow[column])")
        }
    }
}
