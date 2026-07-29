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

    // The headless WARP device, the offscreen render target and the staging
    // readback live in WARPRenderHarness.swift, shared with every other
    // GPU-backed suite in this target.

    private func makeEngine(device: WARPDevice) throws -> D3D11BackdropBlurEngine {
        let d3dDevice = try XCTUnwrap(device.device)
        let engine = D3D11BackdropBlurEngine()
        try engine.attach(device: d3dDevice)
        return engine
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

    func testSplitterKeepsRadiusZeroBlurQuadsInNormalRunsAndRoutesRotated() async {
        let quads = [
            QuadPrimitive(x: 0, y: 0, width: 10, height: 10, blurRadius: 0),
            // Sub-pixel blur truncates to 0, same as the CPU rasterizer.
            QuadPrimitive(x: 0, y: 0, width: 10, height: 10, blurRadius: 0.9),
            // Rotated blur quads ride the blur path over their rotated AABB,
            // matching the CPU rasterizer.
            QuadPrimitive(x: 0, y: 0, width: 10, height: 10, blurRadius: 22, rotationRadians: 0.5),
        ]
        let segments = D3D11BatchRenderer.splitQuadRangeForBackdropBlur(quads, range: 0..<3)
        XCTAssertEqual(
            segments,
            [.normal(range: 0..<2), .blurred(index: 2)],
            "Radius-0 / sub-pixel blur quads stay batched; rotated blur quads route to the blur path")
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
            batchBackdropBlurShaderSource.contains("float4 blurWeights["),
            "Blur shader must take a symmetric Gaussian weight array")
        XCTAssertTrue(
            batchBackdropBlurShaderSource.contains("blurDirection"),
            "Blur shader must take a per-pass direction (H/V separable)")
    }

    /// The blur cap, the Swift cbuffer size and the HLSL array length are
    /// one ABI in three places. One weight more than the array holds is a
    /// cbuffer overrun on upload; one fewer than the cap allows is the CPU
    /// rasterizer blurring wider than the shader can, which is the silent
    /// backend divergence the shared limit exists to prevent.
    func testBlurWeightBufferHoldsTheSharedBlurCap() async {
        XCTAssertEqual(
            Float(D3D11BackdropBlurEngine.maxBlurRadius), GPUISceneLimits.maxBlurRadius,
            "The backdrop blur engine must clamp at the shared engine limit, not at one of its own")

        // 4 floats of direction + 4 of UV scale, then one weight per tap
        // from the centre outwards (radius + 1), rounded up to float4 rows.
        let weightRows = (D3D11BackdropBlurEngine.maxBlurRadius + 1 + 3) / 4
        XCTAssertEqual(
            D3D11BackdropBlurEngine.blurParamsFloatCount, 8 + weightRows * 4,
            "BlurParams must hold exactly the weights a max-radius kernel uploads")
        XCTAssertTrue(
            batchBackdropBlurShaderSource.contains("float4 blurWeights[\(weightRows)];"),
            "HLSL BlurParams must declare the same weight array the Swift side uploads")
    }

    // MARK: - GPU-level behaviour

    func testBlurredBackdropDiffersFromUnblurredSource() async throws {
        let device = try makeWARPDevice()
        defer { device.release() }
        let width = 64
        let height = 64
        let source = makeStripes(width: width, height: height)
        let target = try makeWARPOffscreenTarget(device: device, width: width, height: height, pixels: source)
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

        let result = try readWARPPixels(device: device, target: target)

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
        let device = try makeWARPDevice()
        defer { device.release() }
        let width = 32
        let height = 32
        // Solid blue backdrop: blur is an identity on constant input, so
        // the readback isolates the tint composite exactly.
        let target = try makeWARPOffscreenTarget(
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

        let result = try readWARPPixels(device: device, target: target)
        let centre = pixel(result, width, 16, 16)
        // red α=0.5 over blue → (r≈127.5, g=0, b≈127.5)
        XCTAssertEqual(Double(centre.r), 127.5, accuracy: 6, "Tint red channel")
        XCTAssertEqual(Double(centre.g), 0, accuracy: 4, "Tint green channel")
        XCTAssertEqual(Double(centre.b), 127.5, accuracy: 6, "Backdrop blue channel preserved under tint")
    }

    func testRadiusZeroSkipsTheWholeBlurPath() async throws {
        let device = try makeWARPDevice()
        defer { device.release() }
        let width = 32
        let height = 32
        let source = makeStripes(width: width, height: height)
        let target = try makeWARPOffscreenTarget(device: device, width: width, height: height, pixels: source)
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

        let result = try readWARPPixels(device: device, target: target)
        XCTAssertEqual(
            result, source,
            "blurRadius 0 must skip the blur path entirely and leave the target untouched")
    }

    func testNestedMaterialsBlurTheCompositedBackdrop() async throws {
        let device = try makeWARPDevice()
        defer { device.release() }
        let width = 64
        let height = 64
        let target = try makeWARPOffscreenTarget(
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

        let result = try readWARPPixels(device: device, target: target)

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
        let device = try makeWARPDevice()
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
            let target = try makeWARPOffscreenTarget(
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
            return try readWARPPixels(device: device, target: target)
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
        let device = try makeWARPDevice()
        defer { device.release() }
        let engine = try makeEngine(device: device)
        defer { engine.detach() }
        let context = try XCTUnwrap(device.context)

        let width = 96
        let height = 96
        let target = try makeWARPOffscreenTarget(
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
        let result = try readWARPPixels(device: device, target: target)
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
        let device = try makeWARPDevice()
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

        let target = try makeWARPOffscreenTarget(device: device, width: width, height: height, pixels: pixels)
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

        let result = try readWARPPixels(device: device, target: target)
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

    // MARK: - Radius past the old cap

    /// The painter emits `radius × displayScale`, so `.blur(radius: 80)` at
    /// 2× is 160 device pixels — above the 128 both backends used to clamp
    /// to, which silently rendered a large decorative blur sharper than the
    /// app asked for, and only on HiDPI.
    ///
    /// A backend still clamping at 128 draws radius 160 and radius 128
    /// identically, so "the two radii produce different pixels" is the
    /// question, asked of each backend on its own. Cross-backend agreement
    /// at that radius is `CrossBackendPixelParityTests`' large-radius
    /// material scene.
    func testBothBackendsHonourABlurRadiusAboveTheOldCap() async throws {
        let size = IntSize(width: 96, height: 96)
        let atOldCap = try WARPBatchRenderer.render(makeLargeBlurScene(radius: 128, size: size), size: size)
        let aboveOldCap = try WARPBatchRenderer.render(makeLargeBlurScene(radius: 160, size: size), size: size)

        let gpuReport = comparePixels(aboveOldCap, atOldCap, tolerance: 2)
        XCTAssertLessThan(
            gpuReport.matchRatio, 0.99,
            "The GPU blur must widen past 128 device pixels rather than clamping; identical output at 128 "
                + "and 160 means the weight cbuffer or the engine cap is back below the shared limit")

        let cpuAtOldCap = GPUIRawSceneRasterizer.rasterize(makeLargeBlurScene(radius: 128, size: size), size: size)
        let cpuAboveOldCap = GPUIRawSceneRasterizer.rasterize(makeLargeBlurScene(radius: 160, size: size), size: size)
        let cpuReport = comparePixels(cpuAboveOldCap, cpuAtOldCap, tolerance: 2)
        XCTAssertLessThan(
            cpuReport.matchRatio, 0.99,
            "The CPU rasterizer must widen past 128 device pixels too, or every screenshot and macOS-parity "
                + "render disagrees with what the GPU shows")
    }

    /// Two flat bands under a translucent material panel: a wide kernel
    /// averages a gradient into near-uniform grey, which would make two
    /// different radii agree for the wrong reason.
    private func makeLargeBlurScene(radius: Float, size: IntSize) -> GPUIScene {
        var scene = GPUIScene(clearColor: Color(red: 0.08, green: 0.10, blue: 0.14, alpha: 1))
        let half = Float(size.height) / 2
        scene.addQuad(
            QuadPrimitive(
                x: 0, y: 0, width: Float(size.width), height: half,
                startR: 0.95, startG: 0.30, startB: 0.15, startA: 1,
                endR: 0.95, endG: 0.30, endB: 0.15, endA: 1))
        scene.addQuad(
            QuadPrimitive(
                x: 0, y: half, width: Float(size.width), height: half,
                startR: 0.10, startG: 0.35, startB: 0.85, startA: 1,
                endR: 0.10, endG: 0.35, endB: 0.85, endA: 1))
        scene.addQuad(
            QuadPrimitive(
                x: 8, y: 8, width: Float(size.width) - 16, height: Float(size.height) - 16,
                startR: 1, startG: 1, startB: 1, startA: 0.2,
                endR: 1, endG: 1, endB: 1, endA: 0.2,
                blurRadius: radius))
        scene.finish()
        return scene
    }
}
