import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsRendererD3D11

/// Coherence pin for rotated Material (blur) quads across the two
/// backends. Both apply their backdrop-blur post-process to rotated blur
/// quads over the same window — the axis-aligned bounding box of the
/// rotated footprint:
///   - CPU rasterizer: `drawQuad` blurs its scan window for any quad
///     with `Int(blurRadius) > 0`; for rotated quads that window is the
///     rotated AABB.
///   - D3D11: `splitQuadRangeForBackdropBlur` routes rotated blur quads
///     through `D3D11BackdropBlurEngine`, which blurs the same AABB
///     (`blurRegion(for:...)`).
///
/// Documented residual differences (pre-existing, not changed here):
///   - the CPU rasterizer blurs in place AFTER drawing the quad, so it
///     also softens the AABB corners outside the rotated footprint;
///     D3D11 composites only through the quad's coverage, confining
///     visible blur to the footprint;
///   - the CPU rasterizer's `applyBoxBlur` converts its byte-domain
///     averages through a normalized-[0,1] byte helper, quantizing
///     blurred output far more harshly than a true Gaussian (affects
///     axis-aligned material quads identically — reported as a
///     follow-up, not pinned here).
final class RotatedBackdropBlurCoherenceTests: XCTestCase {

    // MARK: - D3D11 routing

    func testSplitRoutesRotatedBlurQuadsToBackdropBlurEngine() async {
        await MainActor.run {
            let plain = QuadPrimitive(x: 0, y: 0, width: 10, height: 10)
            let rotatedBlur = QuadPrimitive(
                x: 20, y: 20, width: 30, height: 30,
                blurRadius: 8, rotationRadians: Float.pi / 4)
            let axisAlignedBlur = QuadPrimitive(
                x: 60, y: 20, width: 30, height: 30,
                blurRadius: 8)
            let rotatedZeroBlur = QuadPrimitive(
                x: 100, y: 20, width: 30, height: 30,
                blurRadius: 0, rotationRadians: Float.pi / 4)
            let quads = [plain, rotatedBlur, axisAlignedBlur, rotatedZeroBlur]

            let segments = D3D11BatchRenderer.splitQuadRangeForBackdropBlur(quads, range: 0..<quads.count)

            XCTAssertEqual(
                segments,
                [
                    .normal(range: 0..<1),
                    .blurred(index: 1),
                    .blurred(index: 2),
                    .normal(range: 3..<4),
                ],
                "rotated blur quads must take the real backdrop-blur path like axis-aligned ones")
        }
    }

    // MARK: - D3D11 blur region

    func testBlurRegionMatchesQuadRectWhenAxisAligned() async {
        await MainActor.run {
            let quad = QuadPrimitive(x: 10, y: 10, width: 40, height: 20, blurRadius: 8)
            let region = D3D11BackdropBlurEngine.blurRegion(
                for: quad, surfaceWidth: 100, surfaceHeight: 100)
            XCTAssertEqual(region.x0, 10)
            XCTAssertEqual(region.y0, 10)
            XCTAssertEqual(region.x1, 50)
            XCTAssertEqual(region.y1, 30)
        }
    }

    func testBlurRegionIsRotatedBoundingBoxForRotatedQuads() async {
        await MainActor.run {
            // 40×20 rect centred at (30, 20), rotated 90°: the AABB swaps
            // the half-extents — (30∓10, 20∓20) → (20, 0)-(40, 40). The
            // rotation is not exact in Float, so allow ±1 px.
            let quad = QuadPrimitive(
                x: 10, y: 10, width: 40, height: 20,
                blurRadius: 8, rotationRadians: Float.pi / 2)
            let region = D3D11BackdropBlurEngine.blurRegion(
                for: quad, surfaceWidth: 100, surfaceHeight: 100)
            XCTAssertLessThanOrEqual(abs(region.x0 - 20), 1)
            XCTAssertLessThanOrEqual(abs(region.y0 - 0), 1)
            XCTAssertLessThanOrEqual(abs(region.x1 - 40), 1)
            XCTAssertLessThanOrEqual(abs(region.y1 - 40), 1)
            XCTAssertFalse(
                region.x0 == 10 && region.y0 == 10 && region.x1 == 50 && region.y1 == 30,
                "rotated quads must blur the rotated AABB, not the unrotated rect")
        }
    }

    func testBlurRegionClampsToSurface() async {
        await MainActor.run {
            let quad = QuadPrimitive(
                x: -20, y: -20, width: 40, height: 40,
                blurRadius: 8, rotationRadians: Float.pi / 4)
            let region = D3D11BackdropBlurEngine.blurRegion(
                for: quad, surfaceWidth: 100, surfaceHeight: 100)
            XCTAssertEqual(region.x0, 0)
            XCTAssertEqual(region.y0, 0)
            XCTAssertGreaterThan(region.x1, 0)
            XCTAssertGreaterThan(region.y1, 0)
            XCTAssertLessThanOrEqual(region.x1, 100)
            XCTAssertLessThanOrEqual(region.y1, 100)
        }
    }

    // MARK: - CPU rasterizer behaviour

    func testCPURasterizerAppliesBlurPassForRotatedBlurQuad() async {
        await MainActor.run {
            // Sharp black/white vertical boundary at x = 50; a rotated
            // blur quad straddles it with a fully transparent tint so
            // only the blur post-process is visible. The blur must run
            // (pixels change) and its effect must stay inside the rotated
            // quad's AABB — the same window the D3D11 engine blurs.
            func render(blurRadius: Float) -> BitmapSurface {
                var scene = GPUIScene(clearColor: .white)
                scene.addQuad(
                    QuadPrimitive(
                        x: 0, y: 0, width: 50, height: 100,
                        startR: 0, startG: 0, startB: 0, startA: 1,
                        endR: 0, endG: 0, endB: 0, endA: 1,
                        clipWidth: 100, clipHeight: 100),
                    toLayer: 0)
                scene.addQuad(
                    QuadPrimitive(
                        x: 30, y: 30, width: 40, height: 40,
                        startR: 0, startG: 0, startB: 0, startA: 0,
                        endR: 0, endG: 0, endB: 0, endA: 0,
                        clipWidth: 100, clipHeight: 100,
                        blurRadius: blurRadius,
                        rotationRadians: Float.pi / 4),
                    toLayer: 0)
                scene.finish()
                return GPUIRawSceneRasterizer.rasterize(scene, size: IntSize(width: 100, height: 100))
            }

            let sharp = render(blurRadius: 0)
            let blurred = render(blurRadius: 8)

            XCTAssertNotEqual(
                blurred.pixels, sharp.pixels,
                "the CPU rasterizer must apply its blur pass to rotated blur quads")

            // 40×40 rect centred at (50, 50), rotated 45°: AABB is
            // (50∓20·√2) → roughly (21.7, 21.7)-(78.3, 78.3). Every
            // changed pixel must lie inside that window (±1 px).
            var minX = Int.max
            var minY = Int.max
            var maxX = Int.min
            var maxY = Int.min
            var differences = 0
            for y in 0..<100 {
                for x in 0..<100 {
                    let offset = y * Int(blurred.bytesPerRow) + x * 4
                    if blurred.pixels[offset] != sharp.pixels[offset] {
                        differences += 1
                        minX = min(minX, x)
                        minY = min(minY, y)
                        maxX = max(maxX, x)
                        maxY = max(maxY, y)
                    }
                }
            }
            XCTAssertGreaterThan(differences, 0)
            XCTAssertGreaterThanOrEqual(minX, 20)
            XCTAssertGreaterThanOrEqual(minY, 20)
            XCTAssertLessThanOrEqual(maxX, 80)
            XCTAssertLessThanOrEqual(maxY, 80)
        }
    }

    func testCPUAndD3D11AgreeOnBlurredQuadPredicate() async {
        await MainActor.run {
            // The single predicate both backends share: a quad blurs iff
            // Int(blurRadius) > 0 — rotation no longer opts out on D3D11.
            for rotation in [Float(0), Float.pi / 6, Float.pi / 2] {
                for radius in [Float(0), Float(0.4), Float(1), Float(22)] {
                    let quad = QuadPrimitive(
                        x: 0, y: 0, width: 20, height: 20,
                        blurRadius: radius, rotationRadians: rotation)
                    let segments = D3D11BatchRenderer.splitQuadRangeForBackdropBlur([quad], range: 0..<1)
                    let cpuBlurs = Int(quad.blurRadius) > 0
                    let d3d11Blurs = segments.contains {
                        if case .blurred = $0 { return true }
                        return false
                    }
                    XCTAssertEqual(
                        d3d11Blurs, cpuBlurs,
                        "backend blur predicates diverge for radius \(radius), rotation \(rotation)")
                }
            }
        }
    }
}
