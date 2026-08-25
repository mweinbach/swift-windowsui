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
}
