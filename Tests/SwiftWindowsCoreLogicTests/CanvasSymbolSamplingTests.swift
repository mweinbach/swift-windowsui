import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsRendererD3D11
import XCTest

@testable import SwiftWindowsUI

/// A retained symbol preserves its source antialiasing when an affine draw
/// magnifies it. Source density is independent of the destination rectangle.
@MainActor
final class CanvasSymbolSamplingTests: XCTestCase {
    func testMagnifiedSquareSymbolPreservesSourceCoverageAcrossCPUFrameAndWARP() async throws {
        let blue = Color(red: 0, green: 0, blue: 1, alpha: 1)
        let symbol = try XCTUnwrap(
            CanvasSymbolSource(displayScale: 1) { _ in
                ViewNode(frame: Rect(x: 0, y: 0, width: 8, height: 8), backgroundColor: blue)
            })
        let size = IntSize(width: 40, height: 40)
        let runtime = RetainedViewRuntime(clearColor: .clear, displayScale: 1)
        runtime.setRootSize(size)
        let canvas = UI.canvas(frame: Rect(x: 0, y: 0, width: 40, height: 40)) { context, _ in
            context.draw(
                symbol, in: Rect(x: 10, y: 10, width: 8, height: 8),
                transform: CGAffineTransform(scaleX: 2, y: 2))
        }
        runtime.root.addChild(canvas.makeNode(runtime: runtime))
        let scene = runtime.renderScene()
        XCTAssertTrue(scene.validate().isEmpty)
        XCTAssertEqual(scene.imageRenderPasses.count, 1)
        let source = try XCTUnwrap(scene.imageRenderPasses.first)
        XCTAssertEqual(source.size, IntSize(width: 8, height: 8))
        XCTAssertFalse(source.scene.layers.flatMap(\.quads).isEmpty)
        XCTAssertTrue(source.scene.imageResources.isEmpty)

        // The box SDF has fwidth 2 in this derivative quad: its three far
        // texels have 75% coverage, quantized to 191/255 before sampling.
        // SharedCoverageKernelTests pins this existing primitive contract.
        let cornerByte = Int((0.75 * 255).rounded())
        XCTAssertEqual(cornerByte, 191)
        let sourcePixels = GPUIRawSceneRasterizer.rasterize(source.scene, size: source.size).premultipliedAlpha()
        assertBlueCoverage(sourcePixels, x: 6, y: 6, coverage: 1)
        for (x, y) in [(7, 6), (6, 7), (7, 7)] {
            assertBlueCoverage(sourcePixels, x: x, y: y, coverage: Float(cornerByte) / 255)
        }

        // World pixel center 34.5 maps to UV 0.90625, or source texel 6.75.
        // The four in-bounds taps weigh 1/16, 3/16, 3/16 and 9/16.
        // (255 + 15 * 191) / 16 is exactly 195; no exterior texel is sampled.
        let filteredByte = (255 + 15 * cornerByte) / 16
        XCTAssertEqual(filteredByte, 195)
        let expectedCoverage = Float(filteredByte) / 255
        let scenePixels = GPUIRawSceneRasterizer.rasterize(scene, size: size).premultipliedAlpha()
        let framePixels = GPUIRawSceneRasterizer.rasterize(runtime.renderFrame(), size: size).premultipliedAlpha()
        let warpPixels: BitmapSurface
        do {
            warpPixels = try WARPBatchRenderer.render(scene, size: size).premultipliedAlpha()
        } catch {
            // The shared harness can throw XCTSkip when no device attaches.
            // This regression requires WARP, so report an explicit failure.
            XCTFail("WARP rendering is required for Canvas source sampling: \(error)")
            return
        }
        for (pixels, tolerance) in [(scenePixels, 0), (framePixels, 0), (warpPixels, 3)] {
            assertBlueCoverage(pixels, x: 22, y: 22, coverage: 1, tolerance: tolerance)
            assertBlueCoverage(pixels, x: 34, y: 34, coverage: expectedCoverage, tolerance: tolerance)
            assertBlueCoverage(pixels, x: 18, y: 26, coverage: 0, tolerance: tolerance)
            assertBlueCoverage(pixels, x: 38, y: 26, coverage: 0, tolerance: tolerance)
        }
        XCTAssertEqual(comparePixels(framePixels, scenePixels, tolerance: 3).matchRatio, 1)
        let report = comparePixels(warpPixels, scenePixels, tolerance: 3)
        XCTAssertEqual(
            report.matchRatio, 1,
            "Magnified source coverage differs across CPU and WARP: max delta \(report.maxChannelDelta)")
    }

    private func assertBlueCoverage(
        _ bitmap: BitmapSurface, x: Int, y: Int, coverage: Float, tolerance: Int = 0,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let pixels = bitmap.premultipliedAlpha()
        let offset = y * Int(pixels.bytesPerRow) + x * 4
        XCTAssertEqual(
            Float(pixels.pixels[offset]) / 255, coverage, accuracy: Float(tolerance) / 255, file: file, line: line)
        XCTAssertEqual(pixels.pixels[offset + 1], 0, file: file, line: line)
        XCTAssertEqual(pixels.pixels[offset + 2], 0, file: file, line: line)
        XCTAssertEqual(
            Float(pixels.pixels[offset + 3]) / 255, coverage, accuracy: Float(tolerance) / 255, file: file, line: line)
    }
}
