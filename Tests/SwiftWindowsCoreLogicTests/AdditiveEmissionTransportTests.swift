import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsGraphics

/// Review-discovered obligations frozen after the first additive implementation,
/// before correcting emission transport out of isolated targets.
@MainActor
final class AdditiveEmissionTransportTests: XCTestCase {
    private let size = IntSize(width: 32, height: 32)

    func testBlurredEmissionEscapesOntoTransparentParentAndSurvivesALaterNormalDraw() async {
        var scene = emissionScene()
        let emitted = raster(scene)
        // A straight-alpha byte cannot encode nonzero premultiplied RGB at
        // alpha zero. Preserve the existing format tag that can represent it.
        XCTAssertEqual(emitted.format, .bgra8Premultiplied)
        assertPixel(emitted, x: 15, y: 16, premultiplied: [0.05325349, 0, 0, 0])
        assertPixel(emitted, x: 16, y: 16, premultiplied: [0.39349302, 1, 0, 1])
        assertBytes(emitted, x: 14, y: 16, bgra: [0, 0, 0, 0])

        // This final result is representable even in straight alpha, so the
        // missing color is observable without relying on output format alone.
        scene.addQuad(quad(Color(red: 0, green: 0, blue: 0, alpha: 0.5)))
        let actual = raster(scene)
        assertPixel(actual, x: 15, y: 16, premultiplied: [0.026626745, 0, 0, 0.5])
        assertPixel(actual, x: 16, y: 16, premultiplied: [0.19674651, 0.5, 0, 1])
        XCTAssertGreaterThan(actual.pixels[16 * Int(actual.bytesPerRow) + 15 * 4 + 2], 0)
    }

    func testCurrentTargetCropAndPartialReplacementKeepEscapedEmission() async {
        var child = GPUIScene(clearColor: .clear)
        child.addQuad(quad(Color(red: 0, green: 0, blue: 0, alpha: 0.5)))
        child.finish()
        var scene = emissionScene()
        let texture = scene.registerImageRenderPass(child, size: size, input: .currentTarget)
        scene.addImage(image(texture, opacity: 0.5))
        // Child normal drawing retains .5E. Replacement at opacity .5 gives
        // .5*(.5E)+.5E=.75E, while output alpha is .5*.5=.25.
        let actual = raster(scene)
        assertPixel(actual, x: 15, y: 16, premultiplied: [0.03994012, 0, 0, 0.25])
        XCTAssertGreaterThan(actual.pixels[16 * Int(actual.bytesPerRow) + 15 * 4 + 2], 0)
    }

    func testNestedIndependentImagesTransportEmissionBeforeNormalComposition() async {
        var child = emissionScene()
        child.finish()
        var middle = GPUIScene(clearColor: .clear)
        let innerID = middle.registerImageRenderPass(child, size: size, input: .independent)
        middle.addImage(image(innerID, opacity: 0.5))
        middle.finish()
        var scene = GPUIScene(clearColor: .clear)
        let outerID = scene.registerImageRenderPass(middle, size: size, input: .independent)
        scene.addImage(image(outerID))
        scene.addQuad(quad(Color(red: 0, green: 0, blue: 0, alpha: 0.5)))
        let actual = raster(scene)
        // The first image's opacity halves E; normal black halves it again.
        assertPixel(actual, x: 15, y: 16, premultiplied: [0.013313373, 0, 0, 0.5])
        XCTAssertGreaterThan(actual.pixels[16 * Int(actual.bytesPerRow) + 15 * 4 + 2], 0)
    }

    func testSeparableModesClampImportedBackdropColorWhileRetainingEmission() async {
        // Review-discovered after the additive handoff, frozen before the
        // shared shader correction. D is imported premultiplied RGBA, with
        // source Cs=(.5,.5,.5), as=.5. Only Cd=clamp(D.rgb/ad) is normalized;
        // the retained destination term (1-as)*D keeps its emitted RGB.
        let cases: [(pixel: [UInt8], mode: BlendMode, expected: [Float])] = [
            ([0, 0, 153, 51], .multiply, [0.55, 0.2, 0.2, 0.6]),
            ([0, 0, 153, 51], .screen, [0.6, 0.25, 0.25, 0.6]),
            ([0, 0, 153, 51], .overlay, [0.6, 0.2, 0.2, 0.6]),
            ([0, 0, 153, 0], .multiply, [0.55, 0.25, 0.25, 0.5]),
            ([0, 0, 153, 0], .screen, [0.55, 0.25, 0.25, 0.5]),
            ([0, 0, 153, 0], .overlay, [0.55, 0.25, 0.25, 0.5]),
            ([0, 0, 51, 102], .multiply, [0.3, 0.15, 0.15, 0.7]),
            ([0, 0, 51, 102], .screen, [0.4, 0.25, 0.25, 0.7]),
            ([0, 0, 51, 102], .overlay, [0.35, 0.15, 0.15, 0.7]),
        ]
        for vector in cases {
            let bitmap = BitmapSurface(
                width: 1, height: 1, bytesPerRow: 4,
                pixels: Data(vector.pixel), format: .bgra8Premultiplied)
            var scene = GPUIScene(clearColor: .clear)
            let texture: Int32 = 88_403
            scene.bindImageResource(bitmap, for: texture)
            scene.addImage(image(texture))
            var foreground = quad(Color(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.5), mode: vector.mode)
            foreground.x = 8
            foreground.y = 8
            foreground.width = 16
            foreground.height = 16
            scene.addQuad(foreground)
            let actual = raster(scene)
            assertPixel(actual, x: 16, y: 16, premultiplied: vector.expected)
            // The blend must not alter the imported emission outside its quad.
            assertBytes(actual.premultipliedAlpha(), x: 0, y: 0, bgra: vector.pixel)
            if vector.pixel[2] > vector.pixel[3] {
                XCTAssertEqual(actual.format, .bgra8Premultiplied)
            }
        }
    }

    private func emissionScene() -> GPUIScene {
        var child = GPUIScene(clearColor: .clear)
        var red = quad(Color(red: 1, green: 0, blue: 0, alpha: 0.5), mode: .additive)
        red.x = 16
        red.width = 1
        child.addQuad(red)
        child.finish()
        var scene = GPUIScene(clearColor: .clear)
        var green = quad(Color(red: 0, green: 1, blue: 0, alpha: 1))
        green.x = 16
        green.width = 1
        scene.addQuad(green)
        let texture = scene.registerImageRenderPass(child, size: size, input: .isolatedBackdrop, contentBlurRadius: 1)
        scene.addImage(image(texture))
        // B is opaque only in column 16. Its additive red contribution is
        // (.5,0,0,0), K=0. Radius1/sigma.5 blur weights are fixed independently:
        // [.106506979,.786986042,.106506979]. At column15, B remains clear,
        // giving red E=.05325349 and alpha0, without importing green.
        return scene
    }

    private func quad(_ color: Color, mode: BlendMode = .normal) -> QuadPrimitive {
        QuadPrimitive(
            x: 0, y: 0, width: 32, height: 32,
            startR: color.red, startG: color.green, startB: color.blue, startA: color.alpha,
            endR: color.red, endG: color.green, endB: color.blue, endA: color.alpha,
            blendMode: Float(mode.rawValue))
    }

    private func image(_ texture: Int32, opacity: Float = 1) -> ImagePrimitive {
        ImagePrimitive(screenX: 0, screenY: 0, screenW: 32, screenH: 32, opacity: opacity, textureID: texture)
    }

    private func raster(_ scene: GPUIScene) -> BitmapSurface {
        var finished = scene
        finished.finish()
        return GPUIRawSceneRasterizer.rasterize(finished, size: size)
    }

    private func assertPixel(
        _ bitmap: BitmapSurface, x: Int, y: Int, premultiplied expected: [Float],
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let offset = y * Int(bitmap.bytesPerRow) + x * 4
        let alpha = Float(bitmap.pixels[offset + 3]) / 255
        let scale: Float = bitmap.format.alphaMode == .premultiplied ? 1 : alpha
        let actual = [
            Float(bitmap.pixels[offset + 2]) / 255 * scale,
            Float(bitmap.pixels[offset + 1]) / 255 * scale,
            Float(bitmap.pixels[offset]) / 255 * scale,
            alpha,
        ]
        for channel in 0..<4 {
            XCTAssertEqual(actual[channel], expected[channel], accuracy: 2.0 / 255, file: file, line: line)
        }
    }

    private func assertBytes(
        _ bitmap: BitmapSurface, x: Int, y: Int, bgra expected: [UInt8],
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let offset = y * Int(bitmap.bytesPerRow) + x * 4
        XCTAssertEqual(Array(bitmap.pixels[offset..<(offset + 4)]), expected, file: file, line: line)
    }
}
