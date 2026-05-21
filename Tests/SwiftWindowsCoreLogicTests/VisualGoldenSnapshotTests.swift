import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Byte-level visual lock-in tests.
///
/// `CrossViewRenderingParityTests` proves the scene graph emits the right
/// primitive families; this suite goes one layer deeper and rasterizes the
/// scene through the CPU pipeline, asserting that specific pixel coordinates
/// resolve to the colors we expect. Any silent change in compositor order,
/// blend equations, or primitive interpretation flips one of these
/// assertions immediately.
@MainActor
final class VisualGoldenSnapshotTests: XCTestCase {

    /// Composes a scene with a single shape per color so each pixel
    /// assertion targets one primitive in isolation.
    private func solidColorGridScene() -> (GPUIScene, IntSize) {
        let view = ZStack {
            // Background is the clear color (black). The shapes sit on top.
            Rectangle()
                .fill(Color(red: 1, green: 0, blue: 0, alpha: 1))
                .frame(width: 40, height: 40)
                .offset(x: -60, y: -40)

            Rectangle()
                .fill(Color(red: 0, green: 1, blue: 0, alpha: 1))
                .frame(width: 40, height: 40)
                .offset(x: 0, y: -40)

            Rectangle()
                .fill(Color(red: 0, green: 0, blue: 1, alpha: 1))
                .frame(width: 40, height: 40)
                .offset(x: 60, y: -40)

            Rectangle()
                .fill(Color(red: 1, green: 1, blue: 1, alpha: 1))
                .frame(width: 40, height: 40)
                .offset(x: 0, y: 40)
        }
        .frame(width: 200, height: 200)

        let size = IntSize(width: 200, height: 200)
        let scene = WinSwiftUIRendererSnapshotter.snapshot(
            of: view,
            size: size,
            displayScale: 1,
            clearColor: Color(red: 0, green: 0, blue: 0, alpha: 1)
        ).scene
        return (scene, size)
    }

    /// Approximate-equality helper: rasterizer/anti-aliasing can shift a few
    /// LSBs per channel even for solid fills near a primitive's edge. We
    /// sample at the center where the fill is guaranteed solid.
    private func assertColor(
        _ actual: Color?, expected: Color, tolerance: Float = 1.0 / 255.0,
        message: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        guard let actual else {
            XCTFail("\(message): pixel out of range", file: file, line: line)
            return
        }
        XCTAssertEqual(actual.red, expected.red, accuracy: tolerance, message, file: file, line: line)
        XCTAssertEqual(actual.green, expected.green, accuracy: tolerance, message, file: file, line: line)
        XCTAssertEqual(actual.blue, expected.blue, accuracy: tolerance, message, file: file, line: line)
    }

    func testRasterizedBackgroundIsClearColor() async {
        let (scene, size) = solidColorGridScene()
        let bitmap = GPUIRawSceneRasterizer.rasterize(scene, size: size)
        XCTAssertEqual(Int32(bitmap.width), size.width)
        XCTAssertEqual(Int32(bitmap.height), size.height)
        // Top-left corner is well outside any shape — must be the clear black.
        assertColor(
            bitmap.pixelColor(atX: 2, y: 2),
            expected: Color(red: 0, green: 0, blue: 0, alpha: 1),
            message: "Clear color should fill background pixels"
        )
        assertColor(
            bitmap.pixelColor(atX: Int(size.width) - 3, y: Int(size.height) - 3),
            expected: Color(red: 0, green: 0, blue: 0, alpha: 1),
            message: "Bottom-right corner should also be clear color"
        )
    }

    func testRasterizedShapesProduceExpectedFillColors() async {
        let (scene, size) = solidColorGridScene()
        let bitmap = GPUIRawSceneRasterizer.rasterize(scene, size: size)
        // Each shape sits at (centerX + offset, centerY + offset) with size
        // 40×40. Sampling a few px in from the rect's center gives a solid
        // fill pixel.
        let cx = Int(size.width) / 2
        let cy = Int(size.height) / 2

        assertColor(
            bitmap.pixelColor(atX: cx - 60, y: cy - 40),
            expected: Color(red: 1, green: 0, blue: 0, alpha: 1),
            message: "Red rectangle center should be red"
        )
        assertColor(
            bitmap.pixelColor(atX: cx, y: cy - 40),
            expected: Color(red: 0, green: 1, blue: 0, alpha: 1),
            message: "Green rectangle center should be green"
        )
        assertColor(
            bitmap.pixelColor(atX: cx + 60, y: cy - 40),
            expected: Color(red: 0, green: 0, blue: 1, alpha: 1),
            message: "Blue rectangle center should be blue"
        )
        assertColor(
            bitmap.pixelColor(atX: cx, y: cy + 40),
            expected: Color(red: 1, green: 1, blue: 1, alpha: 1),
            message: "White rectangle center should be white"
        )
    }

    func testRasterizedShapesProduceConsistentPixelsAcrossRepeatedRenders() async {
        // Render twice and compare byte-for-byte. Determinism is a
        // precondition for any future GPU vs CPU consistency or golden-image
        // CI strategy.
        let (sceneA, sizeA) = solidColorGridScene()
        let bitmapA = GPUIRawSceneRasterizer.rasterize(sceneA, size: sizeA)
        let (sceneB, sizeB) = solidColorGridScene()
        let bitmapB = GPUIRawSceneRasterizer.rasterize(sceneB, size: sizeB)
        XCTAssertEqual(bitmapA.width, bitmapB.width)
        XCTAssertEqual(bitmapA.height, bitmapB.height)
        XCTAssertEqual(
            bitmapA.pixels, bitmapB.pixels,
            "CPU rasterizer must be deterministic — same scene must produce identical pixels"
        )
    }
}
