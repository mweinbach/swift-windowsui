import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsRendererD3D11

/// Execution coverage for `D3D11BatchRenderer`'s public frame loop —
/// `attachOffscreen`, `resize`, `render` and present — on a real device.
///
/// Until the offscreen attach existed, `attach` required an HWND, so every
/// one of these entry points had zero execution coverage: the only things a
/// test could reach were the pure planner and the sub-components that
/// happen to take a bare `ID3D11Device`. These tests drive the whole path
/// headlessly, so the edges that only show up at runtime — a resize storm,
/// a minimize to 1px, a 4K surface, a zero-size frame — are observed rather
/// than assumed.
@MainActor
final class D3D11BatchRendererRenderTests: XCTestCase {

    private func makeSolidQuadScene(size: IntSize) -> GPUIScene {
        var scene = GPUIScene(clearColor: Color(red: 0, green: 0, blue: 0, alpha: 1))
        scene.addQuad(
            QuadPrimitive(
                x: 0, y: 0, width: Float(size.width), height: Float(size.height),
                startR: 0.2, startG: 0.4, startB: 0.8, startA: 1,
                endR: 0.2, endG: 0.4, endB: 0.8, endA: 1
            )
        )
        return scene
    }

    // MARK: - Attach

    func testUnattachedRendererRendersNothingAndStaysDetached() async throws {
        let renderer = D3D11BatchRenderer()
        XCTAssertFalse(renderer.isAttached)
        // No device, no target: render must be a silent no-op rather than a
        // throw, because the host calls it every WM_PAINT before attach.
        try renderer.render(scene: makeSolidQuadScene(size: IntSize(width: 32, height: 32)))
        try renderer.resize(to: IntSize(width: 64, height: 64))
        XCTAssertFalse(renderer.isAttached)
    }

    func testOffscreenAttachRendersAndReadsBack() async throws {
        let size = IntSize(width: 64, height: 48)
        let bitmap = try WARPBatchRenderer.render(makeSolidQuadScene(size: size), size: size)

        XCTAssertEqual(bitmap.width, 64)
        XCTAssertEqual(bitmap.height, 48)
        XCTAssertEqual(Int(bitmap.bytesPerRow), 64 * 4)
        XCTAssertEqual(bitmap.pixels.count, 64 * 48 * 4)

        // BGRA readback of a 0.2/0.4/0.8 quad covering the whole target.
        let centre = (Int(bitmap.height) / 2) * Int(bitmap.bytesPerRow) + (Int(bitmap.width) / 2) * 4
        XCTAssertEqual(Int(bitmap.pixels[centre]), 204, accuracy: 2, "blue channel")
        XCTAssertEqual(Int(bitmap.pixels[centre + 1]), 102, accuracy: 2, "green channel")
        XCTAssertEqual(Int(bitmap.pixels[centre + 2]), 51, accuracy: 2, "red channel")
        XCTAssertEqual(Int(bitmap.pixels[centre + 3]), 255, "opaque clear + opaque quad")
    }

    func testReadOffscreenPixelsRejectsANonOffscreenRenderer() async throws {
        let renderer = D3D11BatchRenderer()
        XCTAssertThrowsError(try renderer.readOffscreenPixels()) { error in
            XCTAssertTrue(
                error is BatchRendererError,
                "Reading back a renderer with no offscreen target must be a typed failure, not a crash")
        }
    }

    // MARK: - Resize

    func testResizeStormFollowsTheRequestedSize() async throws {
        // 64 → 1920 (windowed → maximised), → 1 (minimise clamp), → 4096
        // (4K). Each step must succeed and the readback must follow the new
        // dimensions, which is the only way to observe that the render
        // target was actually recreated.
        let sizes = [
            IntSize(width: 64, height: 64),
            IntSize(width: 1920, height: 1080),
            IntSize(width: 1, height: 1),
            IntSize(width: 4096, height: 64),
        ]

        for size in sizes {
            let bitmap = try WARPBatchRenderer.render(makeSolidQuadScene(size: size), size: size)
            XCTAssertEqual(bitmap.width, size.width, "readback width after resize to \(size)")
            XCTAssertEqual(bitmap.height, size.height, "readback height after resize to \(size)")

            // The scene fills the whole surface, so any pixel proves the
            // viewport and frame uniforms followed the resize too. Skip the
            // colour check on the 1x1 clamp: its single pixel is entirely
            // edge, and the shader's derivative-based antialiasing widens
            // the ramp there, which says nothing about the resize.
            let offset = (Int(size.height) / 2) * Int(bitmap.bytesPerRow) + (Int(size.width) / 2) * 4
            if size.width >= 8 && size.height >= 8 {
                XCTAssertEqual(Int(bitmap.pixels[offset]), 204, accuracy: 2, "blue channel at \(size)")
            }
            XCTAssertEqual(Int(bitmap.pixels[offset + 3]), 255, "alpha at \(size)")
        }

        // Leave the shared renderer at a small size so later tests don't pay
        // for a 4K target.
        _ = try WARPBatchRenderer.shared(size: IntSize(width: 64, height: 64))
    }

    func testZeroSizeResizeAndRenderAreCleanNoOps() async throws {
        let renderer = try WARPBatchRenderer.shared(size: IntSize(width: 32, height: 32))

        // A minimised window reports a zero pixel size. Neither resize nor
        // render may throw, and the previous target must survive so the
        // next non-zero frame has something to draw into.
        try renderer.resize(to: IntSize(width: 0, height: 0))
        try renderer.render(scene: makeSolidQuadScene(size: IntSize(width: 32, height: 32)))

        try renderer.resize(to: IntSize(width: -8, height: 16))
        try renderer.render(scene: makeSolidQuadScene(size: IntSize(width: 32, height: 32)))

        XCTAssertTrue(renderer.isAttached, "A zero-size frame must not detach the renderer")

        let bitmap = try WARPBatchRenderer.render(
            makeSolidQuadScene(size: IntSize(width: 32, height: 32)), size: IntSize(width: 32, height: 32))
        XCTAssertEqual(bitmap.width, 32)
        XCTAssertEqual(bitmap.height, 32)
    }

    // MARK: - Frame loop

    func testRepeatedFramesAreStable() async throws {
        let size = IntSize(width: 48, height: 48)
        let scene = makeSolidQuadScene(size: size)
        let first = try WARPBatchRenderer.render(scene, size: size)
        let second = try WARPBatchRenderer.render(scene, size: size)
        let third = try WARPBatchRenderer.render(scene, size: size)

        XCTAssertEqual(first.pixels, second.pixels, "Frame 2 must reproduce frame 1 exactly")
        XCTAssertEqual(second.pixels, third.pixels, "Frame 3 must reproduce frame 2 exactly")
    }

    func testClearColorReachesTheTargetWhenTheSceneIsEmpty() async throws {
        let size = IntSize(width: 16, height: 16)
        let scene = GPUIScene(clearColor: Color(red: 1, green: 0.5, blue: 0.25, alpha: 1))
        let bitmap = try WARPBatchRenderer.render(scene, size: size)

        // BGRA: an empty scene is nothing but the clear.
        for index in stride(from: 0, to: bitmap.pixels.count, by: 4) {
            XCTAssertEqual(Int(bitmap.pixels[index]), 64, accuracy: 2, "blue at byte \(index)")
            XCTAssertEqual(Int(bitmap.pixels[index + 1]), 128, accuracy: 2, "green at byte \(index)")
            XCTAssertEqual(Int(bitmap.pixels[index + 2]), 255, accuracy: 2, "red at byte \(index)")
            XCTAssertEqual(Int(bitmap.pixels[index + 3]), 255, "alpha at byte \(index)")
        }
    }

    func testSceneWithGlyphsButNoAtlasFailsWithATypedError() async throws {
        let size = IntSize(width: 32, height: 32)
        let renderer = try WARPBatchRenderer.shared(size: size)

        var scene = GPUIScene(clearColor: .black)
        scene.addGlyph(
            GlyphPrimitive(
                screenX: 4, screenY: 4, screenW: 8, screenH: 8,
                atlasU0: 0, atlasV0: 0, atlasU1: 1, atlasV1: 1,
                colorR: 1, colorG: 1, colorB: 1, colorA: 1
            )
        )

        // No atlas snapshot and nothing cached: the planner must reject the
        // frame with a typed error instead of drawing from a stale atlas.
        XCTAssertThrowsError(try renderer.render(scene: scene)) { error in
            XCTAssertTrue(error is BatchRendererError, "Expected BatchRendererError, got \(error)")
        }
    }
}
