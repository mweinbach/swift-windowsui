import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsRendererD3D11

/// The batch target uses premultiplied source-over, including its clear.
/// Opaque-only parity fixtures cannot catch a straight-alpha clear because
/// both representations happen to have identical bytes when alpha is one.
@MainActor
final class D3D11TransparentCompositingTests: XCTestCase {
    private static let surfaceSize = IntSize(width: 24, height: 24)

    func testTranslucentClearStoresPremultipliedColor() async throws {
        let scene = GPUIScene(clearColor: Color(red: 0.8, green: 0.4, blue: 0.2, alpha: 0.5))
        let bitmap = try WARPBatchRenderer.render(scene, size: Self.surfaceSize)

        XCTAssertEqual(bitmap.format.alphaMode, .premultiplied)
        XCTAssertEqual(Int(bitmap.pixels[0]), 26, accuracy: 1, "premultiplied blue")
        XCTAssertEqual(Int(bitmap.pixels[1]), 51, accuracy: 1, "premultiplied green")
        XCTAssertEqual(Int(bitmap.pixels[2]), 102, accuracy: 1, "premultiplied red")
        XCTAssertEqual(Int(bitmap.pixels[3]), 128, accuracy: 1, "alpha")

        let color = try XCTUnwrap(bitmap.pixelColor(atX: 12, y: 12))
        XCTAssertEqual(color.red, 0.8, accuracy: 0.01)
        XCTAssertEqual(color.green, 0.4, accuracy: 0.01)
        XCTAssertEqual(color.blue, 0.2, accuracy: 0.01)
        XCTAssertEqual(color.alpha, 0.5, accuracy: 0.01)
    }

    func testFullyTransparentColoredClearStoresNoHiddenColor() async throws {
        let scene = GPUIScene(clearColor: Color(red: 1, green: 0.75, blue: 0.5, alpha: 0))
        let bitmap = try WARPBatchRenderer.render(scene, size: Self.surfaceSize)

        XCTAssertEqual(Array(bitmap.pixels.prefix(4)), [0, 0, 0, 0])
        XCTAssertTrue(bitmap.pixels.allSatisfy { $0 == 0 })
    }

    func testTranslucentQuadOverTranslucentClearMatchesCPUReference() async throws {
        var scene = GPUIScene(clearColor: Color(red: 0.9, green: 0.2, blue: 0.1, alpha: 0.4))
        scene.addQuad(
            QuadPrimitive(
                x: 4, y: 4, width: 16, height: 16,
                startR: 0.15, startG: 0.85, startB: 0.3, startA: 0.6,
                endR: 0.15, endG: 0.85, endB: 0.3, endA: 0.6
            )
        )
        scene.finish()

        let gpu = try WARPBatchRenderer.render(scene, size: Self.surfaceSize).straightAlpha()
        let cpu = GPUIRawSceneRasterizer.rasterize(scene, size: Self.surfaceSize)
        let report = comparePixels(gpu, cpu, tolerance: 2)

        XCTAssertEqual(
            report.matchRatio, 1, accuracy: 0.001,
            "Translucent source-over diverged from the CPU reference; maximum channel delta: "
                + "\(report.maxChannelDelta)"
        )
    }

    func testTransparentColoredClearDoesNotBleedIntoTranslucentQuad() async throws {
        var scene = GPUIScene(clearColor: Color(red: 1, green: 0, blue: 0, alpha: 0))
        scene.addQuad(
            QuadPrimitive(
                x: 0, y: 0, width: 24, height: 24,
                startR: 0, startG: 0, startB: 1, startA: 0.5,
                endR: 0, endG: 0, endB: 1, endA: 0.5
            )
        )
        scene.finish()

        let bitmap = try WARPBatchRenderer.render(scene, size: Self.surfaceSize)
        let color = try XCTUnwrap(bitmap.pixelColor(atX: 12, y: 12))

        XCTAssertEqual(color.red, 0, accuracy: 0.01, "transparent red clear bled into the visible quad")
        XCTAssertEqual(color.green, 0, accuracy: 0.01)
        XCTAssertEqual(color.blue, 1, accuracy: 0.01)
        XCTAssertEqual(color.alpha, 0.5, accuracy: 0.01)
    }

    /// At fractional DPI an adjacent viewport boundary can pass through a
    /// pixel centre. That pixel belongs to the later clip; accepting both
    /// far and near edges composites two translucent rows into a dark seam.
    func testAdjacentFractionalClipsDoNotDoubleCompositeTheirSharedPixel() async throws {
        for vertical in [false, true] {
            var scene = GPUIScene(clearColor: .white)
            scene.addQuad(
                QuadPrimitive(
                    x: 0, y: 0, width: 24, height: 24,
                    startR: 1, startG: 0, startB: 0, startA: 0.5,
                    endR: 1, endG: 0, endB: 0, endA: 0.5,
                    clipX: 0, clipY: 0,
                    clipWidth: vertical ? 24 : 8.5,
                    clipHeight: vertical ? 8.5 : 24
                )
            )
            scene.addQuad(
                QuadPrimitive(
                    x: 0, y: 0, width: 24, height: 24,
                    startR: 0, startG: 0, startB: 1, startA: 0.5,
                    endR: 0, endG: 0, endB: 1, endA: 0.5,
                    clipX: vertical ? 0 : 8.5,
                    clipY: vertical ? 8.5 : 0,
                    clipWidth: vertical ? 24 : 15.5,
                    clipHeight: vertical ? 15.5 : 24
                )
            )
            scene.finish()

            let gpu = try WARPBatchRenderer.render(scene, size: Self.surfaceSize)
            let cpu = GPUIRawSceneRasterizer.rasterize(scene, size: Self.surfaceSize)
            for bitmap in [gpu, cpu] {
                let seam = try XCTUnwrap(bitmap.pixelColor(atX: vertical ? 12 : 8, y: vertical ? 8 : 12))
                XCTAssertEqual(seam.red, 0.5, accuracy: 0.01)
                XCTAssertEqual(seam.green, 0.5, accuracy: 0.01, "the earlier red clip must not darken the blue row")
                XCTAssertEqual(seam.blue, 1, accuracy: 0.01)
            }
            let report = comparePixels(gpu, cpu, tolerance: 2)
            XCTAssertEqual(report.matchRatio, 1, accuracy: 0.001)
        }
    }

    /// Blurring a uniform backdrop without tint is a no-op, including its
    /// alpha. Source-over of the complete material pixel over that backdrop
    /// used to turn 50% opacity into 75%, then 87.5% under a second material.
    func testTransparentMaterialsPreserveUniformTranslucentBackdrop() async throws {
        let clear = Color(red: 0.8, green: 0.4, blue: 0.2, alpha: 0.5)
        var scene = GPUIScene(clearColor: clear)
        let beforeGPU = try WARPBatchRenderer.render(scene, size: Self.surfaceSize)
        let beforeCPU = GPUIRawSceneRasterizer.rasterize(scene, size: Self.surfaceSize)
        for _ in 0..<2 {
            scene.addQuad(
                QuadPrimitive(
                    x: 4.5, y: 4.5, width: 15, height: 15, cornerRadius: 4,
                    startR: 0, startG: 0, startB: 0, startA: 0,
                    endR: 0, endG: 0, endB: 0, endA: 0,
                    blurRadius: 6
                )
            )
        }
        scene.finish()

        let gpu = try WARPBatchRenderer.render(scene, size: Self.surfaceSize)
        let cpu = GPUIRawSceneRasterizer.rasterize(scene, size: Self.surfaceSize)
        for (before, after) in [(beforeGPU, gpu), (beforeCPU, cpu)] {
            let report = comparePixels(before, after, tolerance: 2)
            XCTAssertEqual(report.matchRatio, 1, accuracy: 0.001, "untinted uniform material changed its backdrop")
            let center = try XCTUnwrap(after.pixelColor(atX: 12, y: 12))
            XCTAssertEqual(center.alpha, 0.5, accuracy: 0.01)
        }
        let parity = comparePixels(gpu, cpu.premultipliedAlpha(), tolerance: 2)
        XCTAssertEqual(parity.matchRatio, 1, accuracy: 0.001)
    }

    /// The target keeps (1 - geometric coverage), independently of the
    /// material's alpha. This pins the fully covered interior, a half-covered
    /// geometry or rounded-clip edge, and blurOpaque.
    func testTranslucentMaterialReplacesBackdropByCoverage() async throws {
        for (forceOpaque, clipped) in [(false, false), (true, false), (false, true), (true, true)] {
            var scene = GPUIScene(clearColor: Color(red: 1, green: 0, blue: 0, alpha: 0.5))
            scene.addQuad(
                QuadPrimitive(
                    x: clipped ? 0 : 4.5, y: clipped ? 0 : 4,
                    width: clipped ? 24 : 16, height: clipped ? 24 : 16,
                    startR: 0, startG: 0, startB: 1, startA: 0.4,
                    endR: 0, endG: 0, endB: 1, endA: 0.4,
                    clipX: clipped ? 4.5 : 0, clipY: clipped ? 4 : 0,
                    clipWidth: clipped ? 16 : 0, clipHeight: clipped ? 16 : 0,
                    clipCornerRadius: clipped ? 4 : 0,
                    blurRadius: 6, blurOpaque: forceOpaque ? 1 : 0
                )
            )
            scene.finish()
            let materialAlpha: Float = forceOpaque ? 1 : 0.7
            let edgeAlpha = (materialAlpha + 0.5) / 2
            let gpu = try WARPBatchRenderer.render(scene, size: Self.surfaceSize)
            let cpu = GPUIRawSceneRasterizer.rasterize(scene, size: Self.surfaceSize)

            for bitmap in [gpu, cpu] {
                let center = try XCTUnwrap(bitmap.pixelColor(atX: 12, y: 12))
                XCTAssertEqual(center.alpha, materialAlpha, accuracy: 0.01)
                XCTAssertEqual(center.red, 0.3 / materialAlpha, accuracy: 0.01)
                XCTAssertEqual(center.blue, 0.4 / materialAlpha, accuracy: 0.01)

                let edge = try XCTUnwrap(bitmap.pixelColor(atX: 4, y: 12))
                XCTAssertEqual(edge.alpha, edgeAlpha, accuracy: 0.01)
                XCTAssertEqual(edge.red, 0.4 / edgeAlpha, accuracy: 0.01)
                XCTAssertEqual(edge.blue, 0.2 / edgeAlpha, accuracy: 0.01)
            }
            let report = comparePixels(gpu, cpu.premultipliedAlpha(), tolerance: 2)
            XCTAssertEqual(report.matchRatio, 1, accuracy: 0.001)
        }
    }
}
