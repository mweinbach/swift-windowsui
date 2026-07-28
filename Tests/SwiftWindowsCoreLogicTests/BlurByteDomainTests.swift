import SwiftWindowsCore
import SwiftWindowsGraphics

@preconcurrency import XCTest

/// Regression: `GPUIRawSceneRasterizer.applyBoxBlur` accumulated byte-domain
/// (0-255) samples but wrote them through a normalized [0,1] clamp, so every
/// blurred pixel with an average >= 1 clamped to 255 — material backdrops
/// dilated to white instead of blurring. Blur quads must preserve the
/// neighborhood's actual average.
@MainActor
final class BlurByteDomainTests: XCTestCase {
    private func rasterizeBackdropBlur(background: (UInt8, UInt8, UInt8)) -> BitmapSurface {
        var scene = GPUIScene(clearColor: .black)
        scene.addQuad(
            QuadPrimitive(
                x: 0, y: 0, width: 64, height: 64,
                startR: Float(background.0) / 255,
                startG: Float(background.1) / 255,
                startB: Float(background.2) / 255,
                startA: 1,
                endR: Float(background.0) / 255,
                endG: Float(background.1) / 255,
                endB: Float(background.2) / 255,
                endA: 1
            )
        )
        scene.addQuad(
            QuadPrimitive(
                x: 8, y: 8, width: 48, height: 48,
                startR: 1, startG: 1, startB: 1, startA: 0.4,
                endR: 1, endG: 1, endB: 1, endA: 0.4,
                blurRadius: 6
            )
        )
        return GPUIRawSceneRasterizer.rasterize(scene, size: IntSize(width: 64, height: 64))
    }

    func testMidGreyBackdropBlursToMidGreyNotWhite() async {
        let bitmap = rasterizeBackdropBlur(background: (100, 100, 100))
        let bytes = [UInt8](bitmap.pixels)
        let center = (32 * 64 + 32) * 4
        // Source-over of a 0.4 white tint over true mid-grey blur ≈ 162.
        // With the byte-domain bug the backdrop read as 255, yielding ≈ 255.
        let blue = Int(bytes[center])
        XCTAssertEqual(blue, 162, accuracy: 12, "blurred mid-grey backdrop must stay mid-grey, got \(blue)")
    }

    func testBlackBackdropBlurStaysDark() async {
        let bitmap = rasterizeBackdropBlur(background: (0, 0, 0))
        let bytes = [UInt8](bitmap.pixels)
        let center = (32 * 64 + 32) * 4
        // Source-over of a 0.4 white tint over black blur ≈ 102, not 255.
        let blue = Int(bytes[center])
        XCTAssertEqual(blue, 102, accuracy: 12, "blurred black backdrop must stay dark, got \(blue)")
    }
}
