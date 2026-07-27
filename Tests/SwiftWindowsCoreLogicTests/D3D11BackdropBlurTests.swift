import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import WinSDK
import WinSDK.DirectX
import XCTest

@testable import SwiftWindowsRendererD3D11

/// End-to-end verification of the D3D11 backdrop blur engine: real
/// device, real shaders, real pixels.
///
/// The engine (`D3D11BackdropBlurEngine`) is self-contained, so these
/// tests drive it against a headless D3D11 device (WARP first — the
/// software rasterizer is always present and deterministic — falling
/// back to hardware) with an offscreen render target standing in for
/// the swap-chain backbuffer. Pixels are read back through a staging
/// texture and asserted directly: the blurred backdrop must differ from
/// the unblurred source, the tint composite must match source-over
/// maths, radius-0 must skip the whole path, and nested materials must
/// blur the already-composited backdrop beneath them.
@MainActor
final class D3D11BackdropBlurTests: XCTestCase {

    // MARK: - Harness

    /// Owns a headless D3D11 device + context and releases them
    /// explicitly (COM teardown stays on the main actor).
    private final class HeadlessDevice {
        var device: UnsafeMutablePointer<ID3D11Device>?
        var context: UnsafeMutablePointer<ID3D11DeviceContext>?

        func release() {
            if let context {
                let unknown = UnsafeMutableRawPointer(context).assumingMemoryBound(to: IUnknown.self)
                _ = unknown.pointee.lpVtbl.pointee.Release(unknown)
                self.context = nil
            }
            if let device {
                let unknown = UnsafeMutableRawPointer(device).assumingMemoryBound(to: IUnknown.self)
                _ = unknown.pointee.lpVtbl.pointee.Release(unknown)
                self.device = nil
            }
        }
    }

    private func makeHeadlessDevice() throws -> HeadlessDevice {
        let result = HeadlessDevice()
        var featureLevel = D3D_FEATURE_LEVEL(0)
        var featureLevels: [D3D_FEATURE_LEVEL] = [D3D_FEATURE_LEVEL_11_0]
        let flags = UINT(bitPattern: D3D11_CREATE_DEVICE_BGRA_SUPPORT.rawValue)

        for driverType in [D3D_DRIVER_TYPE_WARP, D3D_DRIVER_TYPE_HARDWARE] {
            let hr = featureLevels.withUnsafeBufferPointer { buffer in
                D3D11CreateDevice(
                    nil,
                    driverType,
                    nil,
                    flags,
                    buffer.baseAddress,
                    UINT(buffer.count),
                    UINT(D3D11_SDK_VERSION),
                    &result.device,
                    &featureLevel,
                    &result.context
                )
            }
            if hr >= 0, result.device != nil, result.context != nil {
                return result
            }
        }

        throw XCTSkip("No D3D11 device (WARP or hardware) is available on this machine")
    }

    /// An offscreen render target standing in for the swap-chain
    /// backbuffer (same B8G8R8A8 format), pre-filled with caller pixels.
    private struct OffscreenTarget {
        var texture: UnsafeMutablePointer<ID3D11Texture2D>?
        var rtv: UnsafeMutablePointer<ID3D11RenderTargetView>?
        let width: Int
        let height: Int

        func release() {
            if let rtv {
                let unknown = UnsafeMutableRawPointer(rtv).assumingMemoryBound(to: IUnknown.self)
                _ = unknown.pointee.lpVtbl.pointee.Release(unknown)
            }
            if let texture {
                let unknown = UnsafeMutableRawPointer(texture).assumingMemoryBound(to: IUnknown.self)
                _ = unknown.pointee.lpVtbl.pointee.Release(unknown)
            }
        }
    }

    private func makeOffscreenTarget(
        device: HeadlessDevice,
        width: Int,
        height: Int,
        pixels: [UInt8]
    ) throws -> OffscreenTarget {
        guard let d3dDevice = device.device, let context = device.context else {
            throw XCTSkip("Headless device unavailable")
        }
        XCTAssertEqual(pixels.count, width * height * 4, "BGRA pixel buffer size mismatch")

        var descriptor = D3D11_TEXTURE2D_DESC()
        descriptor.Width = UINT(width)
        descriptor.Height = UINT(height)
        descriptor.MipLevels = 1
        descriptor.ArraySize = 1
        descriptor.Format = DXGI_FORMAT_B8G8R8A8_UNORM
        descriptor.SampleDesc = DXGI_SAMPLE_DESC(Count: 1, Quality: 0)
        descriptor.Usage = D3D11_USAGE_DEFAULT
        descriptor.BindFlags = UINT(D3D11_BIND_RENDER_TARGET.rawValue)

        var target = OffscreenTarget(texture: nil, rtv: nil, width: width, height: height)
        let textureHR = d3dDevice.pointee.lpVtbl.pointee.CreateTexture2D(d3dDevice, &descriptor, nil, &target.texture)
        XCTAssertGreaterThanOrEqual(
            textureHR, 0, "CreateTexture2D failed: 0x\(String(UInt32(bitPattern: textureHR), radix: 16))")
        let texture = try XCTUnwrap(target.texture)

        pixels.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            let resource = UnsafeMutableRawPointer(texture).assumingMemoryBound(to: ID3D11Resource.self)
            context.pointee.lpVtbl.pointee.UpdateSubresource(
                context, resource, 0, nil, baseAddress, UINT(width * 4), 0)
        }

        let resource = UnsafeMutableRawPointer(texture).assumingMemoryBound(to: ID3D11Resource.self)
        let rtvHR = d3dDevice.pointee.lpVtbl.pointee.CreateRenderTargetView(d3dDevice, resource, nil, &target.rtv)
        XCTAssertGreaterThanOrEqual(rtvHR, 0, "CreateRenderTargetView failed")
        _ = try XCTUnwrap(target.rtv)
        return target
    }

    /// Reads the target's pixels back through a staging texture.
    private func readPixels(
        device: HeadlessDevice,
        target: OffscreenTarget
    ) throws -> [UInt8] {
        guard let d3dDevice = device.device, let context = device.context, let texture = target.texture else {
            throw XCTSkip("Headless device unavailable")
        }

        var descriptor = D3D11_TEXTURE2D_DESC()
        descriptor.Width = UINT(target.width)
        descriptor.Height = UINT(target.height)
        descriptor.MipLevels = 1
        descriptor.ArraySize = 1
        descriptor.Format = DXGI_FORMAT_B8G8R8A8_UNORM
        descriptor.SampleDesc = DXGI_SAMPLE_DESC(Count: 1, Quality: 0)
        descriptor.Usage = D3D11_USAGE_STAGING
        descriptor.BindFlags = 0
        descriptor.CPUAccessFlags = UINT(D3D11_CPU_ACCESS_READ.rawValue)

        var staging: UnsafeMutablePointer<ID3D11Texture2D>?
        let createHR = d3dDevice.pointee.lpVtbl.pointee.CreateTexture2D(d3dDevice, &descriptor, nil, &staging)
        XCTAssertGreaterThanOrEqual(createHR, 0, "CreateTexture2D(staging) failed")
        let stagingTexture = try XCTUnwrap(staging)
        defer {
            let unknown = UnsafeMutableRawPointer(stagingTexture).assumingMemoryBound(to: IUnknown.self)
            _ = unknown.pointee.lpVtbl.pointee.Release(unknown)
        }

        let dstResource = UnsafeMutableRawPointer(stagingTexture).assumingMemoryBound(to: ID3D11Resource.self)
        let srcResource = UnsafeMutableRawPointer(texture).assumingMemoryBound(to: ID3D11Resource.self)
        context.pointee.lpVtbl.pointee.CopyResource(context, dstResource, srcResource)

        var mapped = D3D11_MAPPED_SUBRESOURCE()
        let mapHR = context.pointee.lpVtbl.pointee.Map(context, dstResource, 0, D3D11_MAP_READ, 0, &mapped)
        XCTAssertGreaterThanOrEqual(mapHR, 0, "Map(staging) failed")
        let pData = try XCTUnwrap(mapped.pData)
        var pixels = [UInt8](repeating: 0, count: target.width * target.height * 4)
        for row in 0..<target.height {
            let sourceRow = pData.advanced(by: row * Int(mapped.RowPitch))
            let destination = row * target.width * 4
            pixels.withUnsafeMutableBufferPointer { buffer in
                memcpy(buffer.baseAddress!.advanced(by: destination), sourceRow, target.width * 4)
            }
        }
        context.pointee.lpVtbl.pointee.Unmap(context, dstResource, 0)
        return pixels
    }

    // MARK: - Pixel Fixtures

    /// BGRA pixel at (x, y) in a fixture buffer.
    private func pixel(_ pixels: [UInt8], _ width: Int, _ x: Int, _ y: Int) -> (b: Int, g: Int, r: Int, a: Int) {
        let offset = (y * width + x) * 4
        return (Int(pixels[offset]), Int(pixels[offset + 1]), Int(pixels[offset + 2]), Int(pixels[offset + 3]))
    }

    /// 1-px vertical black/white stripes — the highest-frequency content
    /// possible, so any real blur is obvious in the readback.
    private func makeStripes(width: Int, height: Int) -> [UInt8] {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let value: UInt8 = x % 2 == 0 ? 255 : 0
                let offset = (y * width + x) * 4
                pixels[offset] = value
                pixels[offset + 1] = value
                pixels[offset + 2] = value
                pixels[offset + 3] = 255
            }
        }
        return pixels
    }

    private func makeSolid(width: Int, height: Int, b: UInt8, g: UInt8, r: UInt8) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            pixels[index] = b
            pixels[index + 1] = g
            pixels[index + 2] = r
            pixels[index + 3] = 255
        }
        return pixels
    }

    private func makeEngine(device: HeadlessDevice) throws -> D3D11BackdropBlurEngine {
        let d3dDevice = try XCTUnwrap(device.device)
        let engine = D3D11BackdropBlurEngine()
        try engine.attach(device: d3dDevice)
        return engine
    }

    // MARK: - Splitter (pure)

    func testSplitterRoutesBlurredQuadsAndMergesNormalRuns() async {
        let quads = [
            QuadPrimitive(x: 0, y: 0, width: 10, height: 10),
            QuadPrimitive(x: 0, y: 0, width: 10, height: 10, blurRadius: 22),
            QuadPrimitive(x: 0, y: 0, width: 10, height: 10),
            QuadPrimitive(x: 0, y: 0, width: 10, height: 10),
            QuadPrimitive(x: 0, y: 0, width: 10, height: 10, blurRadius: 8),
            QuadPrimitive(x: 0, y: 0, width: 10, height: 10),
        ]
        let segments = D3D11BatchRenderer.splitQuadRangeForBackdropBlur(quads, range: 0..<6)
        XCTAssertEqual(
            segments,
            [
                .normal(range: 0..<1),
                .blurred(index: 1),
                .normal(range: 2..<4),
                .blurred(index: 4),
                .normal(range: 5..<6),
            ],
            "Blur quads must break the batch into order-preserving segments")
    }

    func testSplitterKeepsRadiusZeroAndRotatedBlurQuadsInNormalRuns() async {
        let quads = [
            QuadPrimitive(x: 0, y: 0, width: 10, height: 10, blurRadius: 0),
            // Sub-pixel blur truncates to 0, same as the CPU rasterizer.
            QuadPrimitive(x: 0, y: 0, width: 10, height: 10, blurRadius: 0.9),
            // Rotated blur quads keep the historic fallback (the backdrop
            // region mapping is axis-aligned).
            QuadPrimitive(x: 0, y: 0, width: 10, height: 10, blurRadius: 22, rotationRadians: 0.5),
        ]
        let segments = D3D11BatchRenderer.splitQuadRangeForBackdropBlur(quads, range: 0..<3)
        XCTAssertEqual(
            segments,
            [.normal(range: 0..<3)],
            "Radius-0 / sub-pixel / rotated blur quads must stay on the plain batched path")
    }

    // MARK: - Shader contracts

    func testMaterialShaderSamplesBlurredBackdropTexture() async {
        XCTAssertTrue(
            batchMaterialQuadShaderSource.contains("Texture2D backdropTexture : register(t1)"),
            "Material composite shader must bind the blurred backdrop at t1")
        XCTAssertTrue(
            batchMaterialQuadShaderSource.contains("backdropTexture.Sample(backdropSampler, uv)"),
            "Material composite shader must sample the blurred backdrop")
        XCTAssertTrue(
            batchMaterialQuadShaderSource.contains("cbuffer BackdropRegion : register(b1)"),
            "Material composite shader must take the screen-space region mapping")
    }

    func testBlurShaderUsesSymmetricGaussianWeights() async {
        XCTAssertTrue(
            batchBackdropBlurShaderSource.contains("float4 blurWeights[33];"),
            "Blur shader must take a symmetric Gaussian weight array")
        XCTAssertTrue(
            batchBackdropBlurShaderSource.contains("blurDirection"),
            "Blur shader must take a per-pass direction (H/V separable)")
    }

    // MARK: - GPU-level behaviour

    func testBlurredBackdropDiffersFromUnblurredSource() async throws {
        let device = try makeHeadlessDevice()
        defer { device.release() }
        let width = 64
        let height = 64
        let source = makeStripes(width: width, height: height)
        let target = try makeOffscreenTarget(device: device, width: width, height: height, pixels: source)
        defer { target.release() }

        let engine = try makeEngine(device: device)
        defer { engine.detach() }

        let quad = QuadPrimitive(
            x: 16, y: 16, width: 32, height: 32,
            startR: 1, startG: 1, startB: 1, startA: 0.4,
            endR: 1, endG: 1, endB: 1, endA: 0.4,
            blurRadius: 8
        )
        try engine.drawBlurredQuad(
            deviceContext: try XCTUnwrap(device.context),
            backBuffer: try XCTUnwrap(target.texture),
            backBufferRTV: try XCTUnwrap(target.rtv),
            surfaceWidth: width,
            surfaceHeight: height,
            quad: quad
        )

        let result = try readPixels(device: device, target: target)

        // Centre of the material: 1px stripes blurred to their mean
        // (~127.5), then white tint α=0.4 over it → ~178.5 per channel.
        let centre = pixel(result, width, 32, 32)
        XCTAssertEqual(Double(centre.r), 178.5, accuracy: 14, "Blurred+tinted red channel")
        XCTAssertEqual(Double(centre.g), 178.5, accuracy: 14, "Blurred+tinted green channel")
        XCTAssertEqual(Double(centre.b), 178.5, accuracy: 14, "Blurred+tinted blue channel")
        XCTAssertEqual(centre.a, 255, "Backdrop is opaque so the composite must stay opaque")

        // The blurred interior must be smooth — the source's per-column
        // 0/255 alternation must be gone from neighbouring pixels.
        let left = pixel(result, width, 31, 32)
        XCTAssertLessThan(
            abs(left.r - centre.r), 24,
            "Adjacent pixels under the material must not alternate like the unblurred stripes")

        // Pixels outside the quad's rect must be untouched stripes.
        let outside = pixel(result, width, 4, 32)
        XCTAssertEqual(outside.r, 255)
        XCTAssertEqual(outside.g, 255)
        XCTAssertEqual(outside.b, 255)
        let outsideDark = pixel(result, width, 5, 32)
        XCTAssertEqual(outsideDark.r, 0)
    }

    func testTintCompositeMatchesSourceOverMath() async throws {
        let device = try makeHeadlessDevice()
        defer { device.release() }
        let width = 32
        let height = 32
        // Solid blue backdrop: blur is an identity on constant input, so
        // the readback isolates the tint composite exactly.
        let target = try makeOffscreenTarget(
            device: device, width: width, height: height,
            pixels: makeSolid(width: width, height: height, b: 255, g: 0, r: 0))
        defer { target.release() }

        let engine = try makeEngine(device: device)
        defer { engine.detach() }

        let quad = QuadPrimitive(
            x: 4, y: 4, width: 24, height: 24,
            startR: 1, startG: 0, startB: 0, startA: 0.5,
            endR: 1, endG: 0, endB: 0, endA: 0.5,
            blurRadius: 8
        )
        try engine.drawBlurredQuad(
            deviceContext: try XCTUnwrap(device.context),
            backBuffer: try XCTUnwrap(target.texture),
            backBufferRTV: try XCTUnwrap(target.rtv),
            surfaceWidth: width,
            surfaceHeight: height,
            quad: quad
        )

        let result = try readPixels(device: device, target: target)
        let centre = pixel(result, width, 16, 16)
        // red α=0.5 over blue → (r≈127.5, g=0, b≈127.5)
        XCTAssertEqual(Double(centre.r), 127.5, accuracy: 6, "Tint red channel")
        XCTAssertEqual(Double(centre.g), 0, accuracy: 4, "Tint green channel")
        XCTAssertEqual(Double(centre.b), 127.5, accuracy: 6, "Backdrop blue channel preserved under tint")
    }

    func testRadiusZeroSkipsTheWholeBlurPath() async throws {
        let device = try makeHeadlessDevice()
        defer { device.release() }
        let width = 32
        let height = 32
        let source = makeStripes(width: width, height: height)
        let target = try makeOffscreenTarget(device: device, width: width, height: height, pixels: source)
        defer { target.release() }

        let engine = try makeEngine(device: device)
        defer { engine.detach() }

        let quad = QuadPrimitive(
            x: 4, y: 4, width: 24, height: 24,
            startR: 1, startG: 1, startB: 1, startA: 0.4,
            endR: 1, endG: 1, endB: 1, endA: 0.4,
            blurRadius: 0
        )
        try engine.drawBlurredQuad(
            deviceContext: try XCTUnwrap(device.context),
            backBuffer: try XCTUnwrap(target.texture),
            backBufferRTV: try XCTUnwrap(target.rtv),
            surfaceWidth: width,
            surfaceHeight: height,
            quad: quad
        )

        let result = try readPixels(device: device, target: target)
        XCTAssertEqual(
            result, source,
            "blurRadius 0 must skip the blur path entirely and leave the target untouched")
    }

    func testNestedMaterialsBlurTheCompositedBackdrop() async throws {
        let device = try makeHeadlessDevice()
        defer { device.release() }
        let width = 64
        let height = 64
        let target = try makeOffscreenTarget(
            device: device, width: width, height: height, pixels: makeStripes(width: width, height: height))
        defer { target.release() }

        let engine = try makeEngine(device: device)
        defer { engine.detach() }
        let context = try XCTUnwrap(device.context)
        let backBuffer = try XCTUnwrap(target.texture)
        let rtv = try XCTUnwrap(target.rtv)

        // Material A: red tint over the left half.
        let materialA = QuadPrimitive(
            x: 0, y: 0, width: 32, height: 64,
            startR: 1, startG: 0, startB: 0, startA: 0.5,
            endR: 1, endG: 0, endB: 0, endA: 0.5,
            blurRadius: 8
        )
        try engine.drawBlurredQuad(
            deviceContext: context, backBuffer: backBuffer, backBufferRTV: rtv,
            surfaceWidth: width, surfaceHeight: height, quad: materialA)

        // Material B: blue tint overlapping A's right edge. It must blur
        // the scene WITH A's tint already composited — never the pristine
        // stripes (that would mean sampling stale content), and never
        // its own output (double-sampling).
        let materialB = QuadPrimitive(
            x: 16, y: 0, width: 32, height: 64,
            startR: 0, startG: 0, startB: 1, startA: 0.5,
            endR: 0, endG: 0, endB: 1, endA: 0.5,
            blurRadius: 8
        )
        try engine.drawBlurredQuad(
            deviceContext: context, backBuffer: backBuffer, backBufferRTV: rtv,
            surfaceWidth: width, surfaceHeight: height, quad: materialB)

        let result = try readPixels(device: device, target: target)

        // A-only area (x=8): red over blurred gray ≈ (191, 64, 64).
        let aOnly = pixel(result, width, 8, 32)
        XCTAssertGreaterThan(aOnly.r, 170, "Material A area must read red-dominant")
        XCTAssertLessThan(aOnly.b, 90, "Material A area must have little blue")

        // Overlap (x=24, 8px inside B, fully within A's blurred result):
        // B blurs A's composited red ≈ (191, 64, 64), then blue α=0.5
        // over it → r ≈ 95, b ≈ 160.
        let overlap = pixel(result, width, 24, 32)
        XCTAssertGreaterThan(overlap.b, overlap.r, "Overlap must read blue-dominant (B on top)")
        XCTAssertEqual(
            Double(overlap.r), 95, accuracy: 20,
            "Overlap red must come from A's composited tint — pristine stripes would give ~64")
        XCTAssertEqual(
            Double(overlap.b), 160, accuracy: 20,
            "Overlap blue must be B's tint over the blurred composite")

        // B-only area (x=48... use x=44, 12px from the A/B boundary in
        // the other direction): blue over blurred gray ≈ (64, 64, 191).
        let bOnly = pixel(result, width, 44, 32)
        XCTAssertGreaterThan(bOnly.b, 170, "Material B area must read blue-dominant")
        XCTAssertLessThan(bOnly.r, 100, "Material B area must have little red")
    }

    func testEngineDetachAndReattachProducesIdenticalPixels() async throws {
        let device = try makeHeadlessDevice()
        defer { device.release() }
        let width = 48
        let height = 48
        let quad = QuadPrimitive(
            x: 8, y: 8, width: 32, height: 32,
            startR: 1, startG: 1, startB: 1, startA: 0.4,
            endR: 1, endG: 1, endB: 1, endA: 0.4,
            blurRadius: 10
        )

        func renderOnce(engine: D3D11BackdropBlurEngine) async throws -> [UInt8] {
            let target = try makeOffscreenTarget(
                device: device, width: width, height: height, pixels: makeStripes(width: width, height: height))
            defer { target.release() }
            try engine.drawBlurredQuad(
                deviceContext: try XCTUnwrap(device.context),
                backBuffer: try XCTUnwrap(target.texture),
                backBufferRTV: try XCTUnwrap(target.rtv),
                surfaceWidth: width,
                surfaceHeight: height,
                quad: quad
            )
            return try readPixels(device: device, target: target)
        }

        let engine = try makeEngine(device: device)
        let first = try await renderOnce(engine: engine)
        // Simulate device-loss reattach: full teardown, fresh attach on
        // the (possibly recreated) device, then render the same scene.
        engine.detach()
        try engine.attach(device: try XCTUnwrap(device.device))
        let second = try await renderOnce(engine: engine)
        engine.detach()

        XCTAssertEqual(first, second, "Reattached engine must reproduce identical pixels")
    }

    func testPingPongTargetsGrowToFitLargerRegions() async throws {
        let device = try makeHeadlessDevice()
        defer { device.release() }
        let engine = try makeEngine(device: device)
        defer { engine.detach() }
        let context = try XCTUnwrap(device.context)

        let width = 96
        let height = 96
        let target = try makeOffscreenTarget(
            device: device, width: width, height: height, pixels: makeStripes(width: width, height: height))
        defer { target.release() }
        let backBuffer = try XCTUnwrap(target.texture)
        let rtv = try XCTUnwrap(target.rtv)

        let small = QuadPrimitive(
            x: 4, y: 4, width: 16, height: 16,
            startR: 1, startG: 1, startB: 1, startA: 0.4,
            endR: 1, endG: 1, endB: 1, endA: 0.4, blurRadius: 4)
        try engine.drawBlurredQuad(
            deviceContext: context, backBuffer: backBuffer, backBufferRTV: rtv,
            surfaceWidth: width, surfaceHeight: height, quad: small)
        let smallCapacity = engine.textureCapacity
        XCTAssertGreaterThanOrEqual(smallCapacity.width, 16)
        XCTAssertGreaterThanOrEqual(smallCapacity.height, 16)

        let large = QuadPrimitive(
            x: 24, y: 24, width: 64, height: 48,
            startR: 1, startG: 1, startB: 1, startA: 0.4,
            endR: 1, endG: 1, endB: 1, endA: 0.4, blurRadius: 8)
        try engine.drawBlurredQuad(
            deviceContext: context, backBuffer: backBuffer, backBufferRTV: rtv,
            surfaceWidth: width, surfaceHeight: height, quad: large)
        XCTAssertGreaterThanOrEqual(engine.textureCapacity.width, 64)
        XCTAssertGreaterThanOrEqual(engine.textureCapacity.height, 48)

        // Both draws landed: the small panel and the large panel areas
        // must both differ from the pristine stripes.
        let result = try readPixels(device: device, target: target)
        let inSmall = pixel(result, width, 12, 12)
        XCTAssertNotEqual(inSmall.r, 0)
        XCTAssertNotEqual(inSmall.r, 255)
        let inLarge = pixel(result, width, 60, 60)
        XCTAssertNotEqual(inLarge.r, 0)
        XCTAssertNotEqual(inLarge.r, 255)
    }

    // MARK: - Visual dump

    /// Renders a material-over-content scene through the real D3D11 blur
    /// path and writes the readback to a PNG for human inspection. The
    /// PNG path is printed to the test log.
    func testMaterialSceneVisualDump() async throws {
        let device = try makeHeadlessDevice()
        defer { device.release() }
        let width = 256
        let height = 256

        // High-content backdrop: hue-varying vertical bands, a 1px
        // checkerboard block, and a solid block — frost must smooth the
        // checker and soften band edges while leaving solid areas flat.
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                if x >= 24 && x < 104 && y >= 96 && y < 176 {
                    let value: UInt8 = (x + y) % 2 == 0 ? 255 : 0
                    pixels[offset] = value
                    pixels[offset + 1] = value
                    pixels[offset + 2] = value
                } else if x >= 152 && x < 232 && y >= 96 && y < 176 {
                    pixels[offset] = 220
                    pixels[offset + 1] = 160
                    pixels[offset + 2] = 40
                } else {
                    let t = Float(x) / Float(width)
                    pixels[offset] = UInt8(40 + 180 * t)  // B
                    pixels[offset + 1] = UInt8(60 + 120 * (1 - t))  // G
                    pixels[offset + 2] = UInt8(30 + 200 * (1 - t))  // R
                }
                pixels[offset + 3] = 255
            }
        }

        let target = try makeOffscreenTarget(device: device, width: width, height: height, pixels: pixels)
        defer { target.release() }
        let engine = try makeEngine(device: device)
        defer { engine.detach() }
        let context = try XCTUnwrap(device.context)
        let backBuffer = try XCTUnwrap(target.texture)
        let rtv = try XCTUnwrap(target.rtv)

        // .regularMaterial-like: white tint α 0.40, radius 22.
        try engine.drawBlurredQuad(
            deviceContext: context, backBuffer: backBuffer, backBufferRTV: rtv,
            surfaceWidth: width, surfaceHeight: height,
            quad: QuadPrimitive(
                x: 24, y: 32, width: 128, height: 192,
                cornerRadius: 12,
                startR: 1, startG: 1, startB: 1, startA: 0.4,
                endR: 1, endG: 1, endB: 1, endA: 0.4,
                blurRadius: 22))
        // .thickMaterial-like dark panel overlapping the first: black
        // tint α 0.58, radius 30.
        try engine.drawBlurredQuad(
            deviceContext: context, backBuffer: backBuffer, backBufferRTV: rtv,
            surfaceWidth: width, surfaceHeight: height,
            quad: QuadPrimitive(
                x: 104, y: 96, width: 128, height: 128,
                cornerRadius: 12,
                startR: 0, startG: 0, startB: 0, startA: 0.58,
                endR: 0, endG: 0, endB: 0, endA: 0.58,
                blurRadius: 30))

        let result = try readPixels(device: device, target: target)
        let bitmap = BitmapSurface(
            width: Int32(width), height: Int32(height), bytesPerRow: Int32(width * 4), pixels: Data(result))
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("swift-windowsui-gpublur", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("material-backdrop-demo.png")
        try bitmap.writePNG(to: url)
        print("D3D11 backdrop blur visual dump: \(url.path)")

        // Sanity assertions on the rendered scene: inside the white
        // material over the checkerboard, pixels must be light and
        // locally smooth (frosted, not striped).
        let frosted = pixel(result, width, 64, 128)
        XCTAssertGreaterThan(frosted.r, 120, "White material over checkerboard must read light gray")
        let frostedNeighbour = pixel(result, width, 65, 128)
        XCTAssertLessThan(
            abs(frosted.r - frostedNeighbour.r), 24,
            "Frosted area must be locally smooth — checker alternation must be gone")
        // Untouched band area stays sharp and unblurred.
        let bandA = pixel(result, width, 4, 40)
        let bandB = pixel(result, width, 12, 40)
        XCTAssertNotEqual(bandA.r, bandB.r, "Content outside materials must stay unblurred")
    }
}
