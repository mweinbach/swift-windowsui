import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import WinSDK
import WinSDK.DirectX
import XCTest

@testable import SwiftWindowsRendererD3D11

/// Region safety for the D3D11 backdrop blur: what the blur is allowed to
/// read, what it is allowed to copy, and what happens when it cannot run.
///
/// `D3D11BackdropBlurTests` covers the happy path — that the blur blurs and
/// the tint composites. This suite covers the three boundaries around it:
///
/// - **Stale texels.** The ping-pong targets are grow-only and only the
///   current region is copied into them, so every texel past the region
///   still holds the previous material's blurred output. The sampler's
///   CLAMP address mode stops at the *texture* edge, so without an explicit
///   UV clamp a small material drawn after a large one pulls up to `radius`
///   pixels of the previous panel into its right and bottom edges. It is
///   deterministic and order-dependent, which is exactly why the growth
///   test (small then large) could never see it.
/// - **The copy box.** The region was clamped to the caller's claimed
///   surface size, which `resize` writes before `ResizeBuffers` and never
///   rolls back, so a failed resize could hand `CopySubresourceRegion` a
///   box past the end of the real backbuffer — undefined behaviour with no
///   HRESULT to check.
/// - **Failure containment.** The blur's ping-pong pair is the renderer's
///   largest allocation and is made lazily mid-frame, so it is the one most
///   likely to fail under memory pressure. That must cost the frost, not
///   the frame.
@MainActor
final class BackdropBlurRegionSafetyTests: XCTestCase {

    // MARK: - Fixtures

    private func makeEngine(device: WARPDevice) throws -> D3D11BackdropBlurEngine {
        let d3dDevice = try XCTUnwrap(device.device)
        let engine = D3D11BackdropBlurEngine()
        try engine.attach(device: d3dDevice)
        return engine
    }

    private func pixel(_ pixels: [UInt8], _ width: Int, _ x: Int, _ y: Int) -> (b: Int, g: Int, r: Int, a: Int) {
        let offset = (y * width + x) * 4
        return (Int(pixels[offset]), Int(pixels[offset + 1]), Int(pixels[offset + 2]), Int(pixels[offset + 3]))
    }

    /// A backdrop that is white inside `brightSize` square at the origin and
    /// black everywhere else — so the first material's blur fills the
    /// ping-pong targets with white while the second material sits over
    /// pristine black.
    private func makeCornerHighlight(width: Int, height: Int, brightSize: Int) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let value: UInt8 = (x < brightSize && y < brightSize) ? 255 : 0
                pixels[offset] = value
                pixels[offset + 1] = value
                pixels[offset + 2] = value
                pixels[offset + 3] = 255
            }
        }
        return pixels
    }

    private func makeMaterial(x: Float, y: Float, size: Float, radius: Float) -> QuadPrimitive {
        QuadPrimitive(
            x: x, y: y, width: size, height: size,
            startR: 1, startG: 1, startB: 1, startA: 0.4,
            endR: 1, endG: 1, endB: 1, endA: 0.4,
            blurRadius: radius
        )
    }

    private func makeDedicatedRenderer(size: IntSize) throws -> D3D11BatchRenderer {
        let renderer = D3D11BatchRenderer()
        do {
            try renderer.attachOffscreen(size: size, driver: .warpFirst)
        } catch {
            throw XCTSkip("D3D11 batch renderer unavailable on this machine: \(error)")
        }
        return renderer
    }

    // MARK: - Stale texels (UV clamp)

    func testSmallMaterialAfterLargeMaterialDoesNotPullInStaleTexels() async throws {
        let device = try makeWARPDevice()
        defer { device.release() }
        let width = 256
        let height = 256
        let target = try makeWARPOffscreenTarget(
            device: device, width: width, height: height,
            pixels: makeCornerHighlight(width: width, height: height, brightSize: 200))
        defer { target.release() }

        let engine = try makeEngine(device: device)
        defer { engine.detach() }
        let context = try XCTUnwrap(device.context)
        let backBuffer = try XCTUnwrap(target.texture)
        let rtv = try XCTUnwrap(target.rtv)

        // 1. A 200×200 material over the white corner grows the ping-pong
        //    targets to 200×200 and leaves them holding blurred white.
        try engine.drawBlurredQuad(
            deviceContext: context, backBuffer: backBuffer, backBufferRTV: rtv,
            target: RenderTargetDescriptor(kind: .offscreen, width: width, height: height),
            quad: makeMaterial(x: 0, y: 0, size: 200, radius: 10))
        XCTAssertGreaterThanOrEqual(engine.textureCapacity.width, 200)
        XCTAssertGreaterThanOrEqual(engine.textureCapacity.height, 200)

        // 2. A 40×40 material in the pristine black area reuses those
        //    targets: only texels [0,40)² are refreshed, the rest are still
        //    white. Its taps must not reach them.
        try engine.drawBlurredQuad(
            deviceContext: context, backBuffer: backBuffer, backBufferRTV: rtv,
            target: RenderTargetDescriptor(kind: .offscreen, width: width, height: height),
            quad: makeMaterial(x: 208, y: 208, size: 40, radius: 12))

        let result = try readWARPPixels(device: device, target: target)

        // The backdrop under the small material is uniform black, so a
        // correct blur is uniform too: opposite interior columns and rows
        // must agree, and every one of them must read the analytic
        // white-α0.4-over-black value (102), not something brightened by
        // the previous panel's white.
        let left = pixel(result, width, 210, 228)
        let right = pixel(result, width, 245, 228)
        let top = pixel(result, width, 228, 210)
        let bottom = pixel(result, width, 228, 245)

        XCTAssertLessThanOrEqual(
            abs(left.r - right.r), 4,
            "Blur over a uniform backdrop must be horizontally symmetric — a brighter right edge is the "
                + "previous material's output leaking in past the region")
        XCTAssertLessThanOrEqual(
            abs(top.r - bottom.r), 4,
            "Blur over a uniform backdrop must be vertically symmetric")
        for (label, sample) in [("left", left), ("right", right), ("top", top), ("bottom", bottom)] {
            XCTAssertEqual(
                Double(sample.r), 102, accuracy: 8,
                "\(label) edge: white α0.4 over black is 102; anything brighter is stale-texel pull-in")
        }
    }

    func testBlurShaderClampsEveryTapToTheRegion() async {
        XCTAssertTrue(
            batchBackdropBlurShaderSource.contains("clamp(uv + offset, uvMin, uvMax)"),
            "Forward taps must be clamped to the region, not left to the texture-edge sampler clamp")
        XCTAssertTrue(
            batchBackdropBlurShaderSource.contains("clamp(uv - offset, uvMin, uvMax)"),
            "Backward taps must be clamped to the region")
        XCTAssertTrue(
            batchBackdropBlurShaderSource.contains("float2 uvMin = blurUVScale.zw;"),
            "The clamp bound rides in blurUVScale.zw, which was previously unused padding")
    }

    // MARK: - Copy box vs. the real backbuffer

    func testBlurRegionIsIntersectedWithTheBackbufferNotTheSurfaceArgument() async throws {
        let device = try makeWARPDevice()
        defer { device.release() }
        // The backbuffer is 64×64 but the caller claims a 256×256 surface —
        // the state `resize` leaves behind when `ResizeBuffers` fails.
        let target = try makeWARPOffscreenTarget(
            device: device, width: 64, height: 64,
            pixels: makeCornerHighlight(width: 64, height: 64, brightSize: 64))
        defer { target.release() }
        let context = try XCTUnwrap(device.context)
        let backBuffer = try XCTUnwrap(target.texture)
        let rtv = try XCTUnwrap(target.rtv)

        let oversized = try makeEngine(device: device)
        defer { oversized.detach() }
        try oversized.drawBlurredQuad(
            deviceContext: context, backBuffer: backBuffer, backBufferRTV: rtv,
            target: RenderTargetDescriptor(kind: .offscreen, width: 256, height: 256),
            quad: makeMaterial(x: 0, y: 0, size: 200, radius: 8))
        XCTAssertLessThanOrEqual(
            oversized.textureCapacity.width, 64,
            "The region must be clamped to the backbuffer's own width, not the caller's claim")
        XCTAssertLessThanOrEqual(
            oversized.textureCapacity.height, 64,
            "The region must be clamped to the backbuffer's own height, not the caller's claim")
        XCTAssertGreaterThan(oversized.textureCapacity.width, 0, "The visible part still blurs")

        // A quad entirely past the real backbuffer has nothing to copy, so
        // the engine must decline before allocating anything.
        let outside = try makeEngine(device: device)
        defer { outside.detach() }
        try outside.drawBlurredQuad(
            deviceContext: context, backBuffer: backBuffer, backBufferRTV: rtv,
            target: RenderTargetDescriptor(kind: .offscreen, width: 256, height: 256),
            quad: makeMaterial(x: 128, y: 128, size: 40, radius: 8))
        XCTAssertEqual(
            outside.textureCapacity.width, 0,
            "A region the backbuffer cannot supply must be a no-op, not an out-of-bounds copy")
        XCTAssertEqual(outside.textureCapacity.height, 0)
    }

    // MARK: - Clip intersection (pure)

    func testBlurRegionIntersectsClipRect() async {
        // A tall material inside a short clip must blur the intersection —
        // the same window the CPU rasterizer blurs — not its full height.
        let clipped = QuadPrimitive(
            x: 10, y: 10, width: 100, height: 400,
            clipX: 0, clipY: 0, clipWidth: 60, clipHeight: 80,
            blurRadius: 8)
        let region = D3D11BackdropBlurEngine.blurRegion(
            for: clipped, surfaceWidth: 512, surfaceHeight: 512)
        XCTAssertEqual(region.x0, 10)
        XCTAssertEqual(region.y0, 10)
        XCTAssertEqual(region.x1, 60)
        XCTAssertEqual(region.y1, 80)
    }

    func testBlurRegionIsEmptyWhenTheClipMissesTheQuad() async {
        let disjoint = QuadPrimitive(
            x: 200, y: 200, width: 40, height: 40,
            clipX: 0, clipY: 0, clipWidth: 50, clipHeight: 50,
            blurRadius: 8)
        let region = D3D11BackdropBlurEngine.blurRegion(
            for: disjoint, surfaceWidth: 512, surfaceHeight: 512)
        XCTAssertEqual(region.x1 - region.x0, 0, "A clip that misses the quad leaves nothing to blur")
        XCTAssertEqual(region.y1 - region.y0, 0)
    }

    func testZeroSizedClipStaysTheUnclippedSentinel() async {
        // clipWidth == clipHeight == 0 means "unclipped" in the contract and
        // in both quad pixel shaders; the region must not collapse to it.
        let unclipped = QuadPrimitive(x: 10, y: 10, width: 40, height: 20, blurRadius: 8)
        let region = D3D11BackdropBlurEngine.blurRegion(
            for: unclipped, surfaceWidth: 100, surfaceHeight: 100)
        XCTAssertEqual(region.x0, 10)
        XCTAssertEqual(region.y0, 10)
        XCTAssertEqual(region.x1, 50)
        XCTAssertEqual(region.y1, 30)
    }

    // MARK: - Failure containment

    private func makeMaterialSceneOverContent(size: IntSize) -> GPUIScene {
        var scene = GPUIScene(clearColor: Color(red: 0, green: 0, blue: 0, alpha: 1))
        // Opaque backdrop content, then a material over its left half, then
        // a plain quad on top: the material must not break either neighbour.
        scene.addQuad(
            QuadPrimitive(
                x: 0, y: 0, width: Float(size.width), height: Float(size.height),
                startR: 0, startG: 0, startB: 1, startA: 1,
                endR: 0, endG: 0, endB: 1, endA: 1))
        scene.addQuad(
            QuadPrimitive(
                x: 8, y: 8, width: 32, height: 48,
                startR: 1, startG: 1, startB: 1, startA: 0.4,
                endR: 1, endG: 1, endB: 1, endA: 0.4,
                blurRadius: 10))
        scene.addQuad(
            QuadPrimitive(
                x: 48, y: 8, width: 8, height: 48,
                startR: 1, startG: 0, startB: 0, startA: 1,
                endR: 1, endG: 0, endB: 0, endA: 1))
        return scene
    }

    func testBlurFailureFallsBackToThePlainQuadPathAndStillPresents() async throws {
        let size = IntSize(width: 64, height: 64)
        let renderer = try makeDedicatedRenderer(size: size)
        defer { renderer.detach() }

        let scene = makeMaterialSceneOverContent(size: size)
        renderer.failBlurredQuadsForTesting = true
        renderer.bindResources(for: scene)
        // The whole point: a blur failure must not escape `render`, because
        // escaping means the frame never reaches Present and the next frame
        // retries the same failing allocation forever.
        try renderer.render(scene: scene)
        XCTAssertTrue(
            renderer.blurDegradedForTesting,
            "A contained blur failure must be remembered so every later frame skips straight to the "
                + "plain path")

        let bitmap = try renderer.readOffscreenPixels()
        func sample(_ x: Int, _ y: Int) -> (b: Int, g: Int, r: Int) {
            let offset = y * Int(bitmap.bytesPerRow) + x * 4
            return (Int(bitmap.pixels[offset]), Int(bitmap.pixels[offset + 1]), Int(bitmap.pixels[offset + 2]))
        }

        // The material still drew — through the plain quad shader, whose
        // white α0.4 over the blue backdrop is the same interior colour the
        // composite would have produced over a constant backdrop.
        let inMaterial = sample(24, 32)
        XCTAssertGreaterThan(inMaterial.r, 60, "The degraded material must still tint its rect")
        XCTAssertGreaterThan(inMaterial.g, 60, "The degraded material must still tint its rect")
        // The primitive after it in paint order still drew, so the frame ran
        // to completion rather than aborting at the material.
        let inOverlay = sample(52, 32)
        XCTAssertGreaterThan(inOverlay.r, 200, "The quad painted after the material must still reach the target")
        XCTAssertLessThan(inOverlay.b, 60)

        // A resize changes the allocation that failed, so the real effect
        // gets another chance rather than staying plain for the session.
        try renderer.resize(to: IntSize(width: 80, height: 80))
        XCTAssertFalse(renderer.blurDegradedForTesting, "Resize must clear the degraded-blur latch")
    }

    func testBlurredAndPlainQuadsCoexistInOneFrame() async throws {
        let size = IntSize(width: 64, height: 64)
        let renderer = try makeDedicatedRenderer(size: size)
        defer { renderer.detach() }

        let scene = makeMaterialSceneOverContent(size: size)
        renderer.bindResources(for: scene)
        try renderer.render(scene: scene)
        XCTAssertFalse(renderer.blurDegradedForTesting, "The real blur path must succeed on WARP")

        let bitmap = try renderer.readOffscreenPixels()
        func sample(_ x: Int, _ y: Int) -> (b: Int, g: Int, r: Int, a: Int) {
            let offset = y * Int(bitmap.bytesPerRow) + x * 4
            return (
                Int(bitmap.pixels[offset]), Int(bitmap.pixels[offset + 1]),
                Int(bitmap.pixels[offset + 2]), Int(bitmap.pixels[offset + 3])
            )
        }

        // The quad painted after the material must land in the right place
        // with the right colour: the blur engine replaces the render target,
        // viewport, blend state and VS b0 while it works, and the batch loop
        // only keeps drawing correctly because the renderer re-binds them.
        let overlay = sample(52, 32)
        XCTAssertGreaterThan(overlay.r, 200, "Red overlay after the material must be red")
        XCTAssertLessThan(overlay.b, 60, "Red overlay after the material must not be the blue backdrop")
        XCTAssertEqual(overlay.a, 255)

        // And the backdrop content on the far side is untouched.
        let backdrop = sample(60, 60)
        XCTAssertGreaterThan(backdrop.b, 200)
        XCTAssertLessThan(backdrop.r, 60)
    }
}
