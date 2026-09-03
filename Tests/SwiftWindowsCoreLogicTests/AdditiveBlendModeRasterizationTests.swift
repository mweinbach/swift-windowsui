import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsGraphics

/// Raw-scene additive obligations, independent of the production blend helper.
@MainActor
final class AdditiveBlendModeRasterizationTests: XCTestCase {
    private let size = IntSize(width: 32, height: 32)
    private let backdrop = Color(red: 0.25, green: 0.5, blue: 0.75, alpha: 0.5)
    private let source = Color(red: 0.75, green: 0.25, blue: 0.5, alpha: 0.25)

    func testLiteralPremultipliedResultsIncludeIndependentRGBAndAlphaSaturation() async {
        let cases: [(Color, Color, [Float])] = [
            (
                Color(red: 1, green: 0, blue: 0, alpha: 1),
                Color(red: 0, green: 1, blue: 0, alpha: 1), [1, 1, 0, 1]
            ),
            (source, backdrop, [0.3125, 0.3125, 0.5, 0.75]),
            (
                Color(red: 1, green: 0.25, blue: 0.5, alpha: 0.75),
                Color(red: 0.75, green: 0.5, blue: 1, alpha: 0.75), [1, 0.5625, 1, 1]
            ),
            (
                Color(red: 0.5, green: 0.25, blue: 0.75, alpha: 0.75),
                Color(red: 0.25, green: 0.5, blue: 0, alpha: 0.5), [0.5, 0.4375, 0.5625, 1]
            ),
            (source, .clear, [0.1875, 0.0625, 0.125, 0.25]),
        ]
        for (foreground, background, expected) in cases {
            var scene = GPUIScene(clearColor: background)
            scene.addQuad(quad(foreground))
            assertPixel(raster(scene), x: 16, y: 16, premultiplied: expected)
        }
    }

    func testZeroAlphaHiddenRGBAndClippedPixelsRemainExactlyUnchanged() async {
        let green = Color(red: 0, green: 1, blue: 0, alpha: 1)
        var scene = GPUIScene(clearColor: green)
        scene.addQuad(quad(Color(red: 1, green: 0.125, blue: 0.75, alpha: 0)))
        let transparent = raster(scene)
        for y in 0..<32 {
            for x in 0..<32 { assertBytes(transparent, x: x, y: y, bgra: [0, 255, 0, 255]) }
        }
        var clipped = quad(Color(red: 1, green: 0, blue: 0, alpha: 0.5))
        clipped.clipX = 8
        clipped.clipY = 8
        clipped.clipWidth = 16
        clipped.clipHeight = 16
        scene.addQuad(clipped)
        let actual = raster(scene)
        assertPixel(actual, x: 16, y: 16, premultiplied: [0.5, 1, 0, 1])
        for y in 0..<32 {
            for x in 0..<32 where x < 8 || x >= 24 || y < 8 || y >= 24 {
                assertBytes(actual, x: x, y: y, bgra: [0, 255, 0, 255])
            }
        }
    }

    func testFractionalCoverageMultipliesAuthoredAlphaOnlyOnce() async {
        let tint = Color(red: 0.75, green: 0.25, blue: 0.5, alpha: 0.5)
        var shape = quad(tint)
        shape.x = 3.25
        shape.y = 4.5
        shape.width = 23.5
        shape.height = 18.75
        shape.cornerRadius = 6
        shape.rotationRadians = 0.31
        shape.clipX = 6
        shape.clipY = 2
        shape.clipWidth = 22
        shape.clipHeight = 25
        shape.clipCornerRadius = 3
        var mask = shape
        mask.blendMode = Float(BlendMode.normal.rawValue)
        mask.startR = 1
        mask.startG = 1
        mask.startB = 1
        mask.startA = 1
        mask.endR = 1
        mask.endG = 1
        mask.endB = 1
        mask.endA = 1
        var maskScene = GPUIScene(clearColor: .clear)
        maskScene.addQuad(mask)
        let coverage = raster(maskScene)
        var scene = GPUIScene(clearColor: backdrop)
        scene.addQuad(shape)
        let actual = raster(scene)
        var fractionalPixels = 0
        for y in 0..<32 {
            for x in 0..<32 {
                let k = Float(coverage.pixels[y * Int(coverage.bytesPerRow) + x * 4 + 3]) / 255
                if k > 0 && k < 1 { fractionalPixels += 1 }
                // D=(.125,.25,.375,.5); S=k*(.375,.125,.25,.5).
                assertPixel(
                    actual, x: x, y: y,
                    premultiplied: [0.125 + 0.375 * k, 0.25 + 0.125 * k, 0.375 + 0.25 * k, 0.5 + 0.5 * k])
            }
        }
        XCTAssertGreaterThan(fractionalPixels, 0)
    }

    func testLayerOrderAndInterveningNormalDrawReadTheLatestDestination() async {
        var scene = GPUIScene(clearColor: backdrop)
        // Insert the later layer first; presentationOrder must still lead.
        scene.addQuad(quad(Color(red: 0.5, green: 0.25, blue: 0.75, alpha: 0.25)), toLayer: 1)
        scene.addQuad(quad(source), toLayer: 0)
        scene.addQuad(quad(Color(red: 0.25, green: 0.75, blue: 0.5, alpha: 0.5), mode: .normal), toLayer: 0)
        assertPixel(raster(scene), x: 16, y: 16, premultiplied: [0.40625, 0.59375, 0.6875, 1])
    }

    func testRepeatedCurrentTargetPassReadsEachOccurrenceAfterAnInterveningNormalDraw() async {
        var child = GPUIScene(clearColor: .clear)
        child.addQuad(quad(source))
        child.finish()
        var scene = GPUIScene(clearColor: backdrop)
        let texture = scene.registerImageRenderPass(child, size: size, input: .currentTarget)
        scene.addImage(image(texture))
        scene.addQuad(quad(Color(red: 0.25, green: 0.75, blue: 0.5, alpha: 0.5), mode: .normal))
        scene.addImage(image(texture))
        assertPixel(raster(scene), x: 16, y: 16, premultiplied: [0.46875, 0.59375, 0.625, 1])
    }

    func testIndependentPassAddsLocallyBeforeItsImageOpacity() async {
        var child = GPUIScene(clearColor: .clear)
        child.addQuad(quad(Color(red: 1, green: 0, blue: 0, alpha: 0.5)))
        child.addQuad(quad(Color(red: 0, green: 0, blue: 1, alpha: 0.5)))
        child.finish()
        var scene = GPUIScene(clearColor: Color(red: 0, green: 1, blue: 0, alpha: 1))
        let texture = scene.registerImageRenderPass(child, size: size, input: .independent)
        scene.addImage(image(texture, opacity: 0.5))
        assertPixel(raster(scene), x: 16, y: 16, premultiplied: [0.25, 0.5, 0.25, 1])
    }

    func testIsolatedOpacityPreservesTheOpaqueBackdropAndSaturatesBeforeOpacity() async {
        let cases: [(Color, Float, [Float])] = [
            (Color(red: 0, green: 1, blue: 0, alpha: 1), 0.5, [0.25, 1, 0, 1]),
            (Color(red: 0.9, green: 0, blue: 0, alpha: 1), 0.2, [0.95, 0, 0, 1]),
        ]
        for (background, alpha, expected) in cases {
            var child = GPUIScene(clearColor: .clear)
            child.addQuad(quad(Color(red: 1, green: 0, blue: 0, alpha: alpha)))
            child.finish()
            var scene = GPUIScene(clearColor: background)
            let texture = scene.registerImageRenderPass(child, size: size, input: .isolatedBackdrop)
            scene.addImage(image(texture, opacity: 0.5))
            assertPixel(raster(scene), x: 16, y: 16, premultiplied: expected)
        }
    }

    func testNestedCurrentTargetPreservesAlphaZeroEmissionAndLaterNormalAttenuation() async {
        var inner = GPUIScene(clearColor: .clear)
        inner.addQuad(quad(Color(red: 1, green: 0, blue: 0, alpha: 0.5)))
        inner.finish()
        var outer = GPUIScene(clearColor: .clear)
        let innerID = outer.registerImageRenderPass(inner, size: size, input: .currentTarget)
        outer.addImage(image(innerID))
        var later = quad(Color(red: 0, green: 0, blue: 1, alpha: 0.5), mode: .normal)
        later.x = 16
        later.width = 16
        outer.addQuad(later)
        outer.finish()
        var scene = GPUIScene(clearColor: Color(red: 0, green: 1, blue: 0, alpha: 1))
        let outerID = scene.registerImageRenderPass(outer, size: size, input: .isolatedBackdrop)
        scene.addImage(image(outerID))
        let actual = raster(scene)
        assertPixel(actual, x: 8, y: 16, premultiplied: [0.5, 1, 0, 1])
        assertPixel(actual, x: 24, y: 16, premultiplied: [0.25, 0.5, 0.5, 1])
    }

    func testContentBlurSpreadsOnlyEmissionWithoutImportingTheNonuniformBackdrop() async {
        var child = GPUIScene(clearColor: .clear)
        var stripe = quad(Color(red: 1, green: 0, blue: 0, alpha: 0.5))
        stripe.x = 16
        stripe.width = 1
        child.addQuad(stripe)
        child.finish()
        var scene = GPUIScene(clearColor: Color(red: 0, green: 1, blue: 0, alpha: 1))
        var blue = quad(Color(red: 0, green: 0, blue: 1, alpha: 1), mode: .normal)
        blue.x = 16
        blue.width = 16
        scene.addQuad(blue)
        let texture = scene.registerImageRenderPass(child, size: size, input: .isolatedBackdrop, contentBlurRadius: 1)
        scene.addImage(image(texture))
        let actual = raster(scene)
        // Radius 1, sigma .5: normalized weights are
        // [.106506979, .786986042, .106506979]. The stripe is uniform
        // vertically, so the vertical pass preserves the horizontal values.
        // These literals do not call the production kernel.
        assertPixel(actual, x: 15, y: 16, premultiplied: [0.05325349, 1, 0, 1])
        assertPixel(actual, x: 16, y: 16, premultiplied: [0.39349302, 0, 1, 1])
        assertPixel(actual, x: 17, y: 16, premultiplied: [0.05325349, 0, 1, 1])
        assertBytes(actual, x: 14, y: 16, bgra: [0, 255, 0, 255])
        assertBytes(actual, x: 18, y: 16, bgra: [255, 0, 0, 255])
    }

    func testMaterialModesKeepReplacementBehaviorWhileSubpixelBlurRemainsOrdinary() async {
        var material = quad(source, mode: .normal)
        material.blurRadius = 2
        var normal = GPUIScene(clearColor: backdrop)
        normal.addQuad(material)
        let expected = raster(normal)
        for mode in [BlendMode.multiply, .screen, .overlay, .additive] {
            var scene = GPUIScene(clearColor: backdrop)
            material.blendMode = Float(mode.rawValue)
            scene.addQuad(material)
            XCTAssertEqual(raster(scene).pixels, expected.pixels)
        }
        var ordinary = quad(source)
        ordinary.blurRadius = 0.5
        var scene = GPUIScene(clearColor: backdrop)
        scene.addQuad(ordinary)
        assertPixel(raster(scene), x: 16, y: 16, premultiplied: [0.3125, 0.3125, 0.5, 0.75])
    }

    private func quad(_ color: Color, mode: BlendMode = .additive) -> QuadPrimitive {
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
        let actual = [
            Float(bitmap.pixels[offset + 2]) / 255 * alpha,
            Float(bitmap.pixels[offset + 1]) / 255 * alpha,
            Float(bitmap.pixels[offset]) / 255 * alpha,
            alpha,
        ]
        for index in 0..<4 {
            XCTAssertEqual(actual[index], expected[index], accuracy: 4.0 / 255, file: file, line: line)
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
