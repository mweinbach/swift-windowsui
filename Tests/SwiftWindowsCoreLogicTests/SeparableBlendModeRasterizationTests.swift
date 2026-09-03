import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsGraphics

/// Raw-scene obligations, independent of WinSwiftUI/Runtime and frozen before production edits.
@MainActor
final class SeparableBlendModeRasterizationTests: XCTestCase {
    private let size = IntSize(width: 32, height: 32)
    private let modes: [BlendMode] = [.multiply, .screen, .overlay]
    private let source = Color(red: 0.8, green: 0.2, blue: 0.4, alpha: 0.5)
    private let backdrop = Color(red: 0.3, green: 0.6, blue: 0.1, alpha: 0.5)

    func testTranslucentResultsMatchFixedPremultipliedReferenceVectors() async {
        let cases: [(BlendMode, [Float])] = [
            (.multiply, [0.335, 0.23, 0.135, 0.75]),
            (.screen, [0.49, 0.37, 0.24, 0.75]),
            (.overlay, [0.395, 0.29, 0.145, 0.75]),
        ]
        for (mode, expected) in cases {
            var scene = GPUIScene(clearColor: backdrop)
            scene.addQuad(quad(source, mode: mode))
            assertPixel(raster(scene), x: 16, y: 16, premultiplied: expected)
        }
    }

    func testCoverageClipAndRotationDoNotReplaceSourceAlphaWithTheBlendResult() async {
        let tint = Color(red: 0.8, green: 0.3, blue: 0.6, alpha: 0.55)
        let destination = Color(red: 0.18, green: 0.65, blue: 0.37, alpha: 0.6)
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
        var fractionalPixels = 0
        for mode in modes {
            var scene = GPUIScene(clearColor: destination)
            shape.blendMode = Float(mode.rawValue)
            scene.addQuad(shape)
            let actual = raster(scene)
            for y in 0..<Int(size.height) {
                for x in 0..<Int(size.width) {
                    let alpha = Float(coverage.pixels[y * Int(coverage.bytesPerRow) + x * 4 + 3]) / 255
                    if alpha > 0 && alpha < 1 { fractionalPixels += 1 }
                    let covered = Color(red: tint.red, green: tint.green, blue: tint.blue, alpha: tint.alpha * alpha)
                    assertPixel(
                        actual, x: x, y: y,
                        premultiplied: reference(source: covered, destination: premultiplied(destination), mode: mode))
                }
            }
        }
        XCTAssertGreaterThan(fractionalPixels, 0, "The fixture must exercise partial antialiasing coverage")
    }

    func testLayerOrderAndAnInterveningImageUseTheLatestDestination() async {
        let earlier = Color(red: 0.4, green: 0.8, blue: 0.1, alpha: 0.4)
        let imageColor = Color(red: 32.0 / 255, green: 64.0 / 255, blue: 128.0 / 255, alpha: 64.0 / 255)
        let later = Color(red: 0.2, green: 0.8, blue: 0.2, alpha: 0.3)
        var scene = GPUIScene(clearColor: backdrop)
        // Insertion order intentionally differs from layer presentation order.
        scene.addQuad(quad(source, mode: .multiply), toLayer: 1)
        scene.addQuad(quad(earlier), toLayer: 0)
        let bitmap = BitmapSurface(width: 1, height: 1, bytesPerRow: 4, pixels: Data([128, 64, 32, 64]))
        let texture = scene.registerImageResource(bitmap)
        scene.addImage(image(texture), toLayer: 1)
        scene.addQuad(quad(source, mode: .screen), toLayer: 1)
        scene.addQuad(quad(source, mode: .overlay), toLayer: 1)
        var finalNormal = quad(later)
        finalNormal.x = 16
        finalNormal.width = 16
        scene.addQuad(finalNormal, toLayer: 1)
        var expected = reference(source: earlier, destination: premultiplied(backdrop), mode: .normal)
        expected = reference(source: source, destination: expected, mode: .multiply)
        expected = reference(source: imageColor, destination: expected, mode: .normal)
        expected = reference(source: source, destination: expected, mode: .screen)
        expected = reference(source: source, destination: expected, mode: .overlay)
        let result = raster(scene)
        assertPixel(result, x: 8, y: 16, premultiplied: expected)
        assertPixel(
            result, x: 24, y: 16,
            premultiplied: reference(source: later, destination: expected, mode: .normal))
    }

    func testRepeatedCurrentTargetOccurrencesReadTheirOwnPrefix() async {
        let changed = Color(red: 0.2, green: 0.7, blue: 0.5, alpha: 0.6)
        for mode in modes {
            var child = GPUIScene(clearColor: .clear)
            child.addQuad(quad(source, mode: mode))
            child.finish()
            var scene = GPUIScene(clearColor: backdrop)
            let texture = scene.registerImageRenderPass(child, size: size, input: .currentTarget)
            scene.addImage(image(texture))
            scene.addQuad(quad(changed))
            scene.addImage(image(texture))
            var expected = reference(source: source, destination: premultiplied(backdrop), mode: mode)
            expected = reference(source: changed, destination: expected, mode: .normal)
            expected = reference(source: source, destination: expected, mode: mode)
            assertPixel(raster(scene), x: 16, y: 16, premultiplied: expected)
        }
    }

    func testNestedIsolationReadsVirtualDestinationAndKeepsCoverageSeparate() async {
        let foreground = Color(red: 0.8, green: 0.1, blue: 0.4, alpha: 0.35)
        for mode in modes {
            var inner = GPUIScene(clearColor: .clear)
            inner.addQuad(quad(source, mode: mode))
            inner.finish()
            var outer = GPUIScene(clearColor: .clear)
            outer.addQuad(quad(foreground))
            let innerID = outer.registerImageRenderPass(inner, size: size, input: .currentTarget)
            outer.addImage(image(innerID))
            outer.finish()
            var scene = GPUIScene(clearColor: backdrop)
            let outerID = scene.registerImageRenderPass(
                outer, size: size, input: .isolatedBackdrop, contentBlurRadius: 2)
            scene.addImage(image(outerID))
            let afterForeground = reference(source: foreground, destination: premultiplied(backdrop), mode: .normal)
            let expected = reference(source: source, destination: afterForeground, mode: mode)
            // Uniform interior is unchanged by the normalized content blur. Edge
            // pixels are covered separately by the batch/isolation regression.
            assertPixel(raster(scene), x: 16, y: 16, premultiplied: expected)
        }
    }

    func testAdditiveUsesTheIndependentSaturatedSumInsteadOfSourceOver() async {
        var normal = GPUIScene(clearColor: backdrop)
        normal.addQuad(quad(source))
        var additive = GPUIScene(clearColor: backdrop)
        additive.addQuad(quad(source, mode: .additive))
        let added = raster(additive)
        assertPixel(added, x: 16, y: 16, premultiplied: [0.55, 0.4, 0.25, 1])
        XCTAssertNotEqual(raster(normal).pixels, added.pixels)
        for mode in modes {
            var scene = GPUIScene(clearColor: backdrop)
            scene.addQuad(quad(source, mode: mode))
            XCTAssertNotEqual(raster(scene).pixels, raster(normal).pixels)
        }
    }

    func testMaterialQuadModesRetainTheirSeparateUnchangedReplacementSemantics() async {
        var material = quad(source)
        material.blurRadius = 2
        var referenceScene = GPUIScene(clearColor: backdrop)
        referenceScene.addQuad(material)
        let expected = raster(referenceScene)
        for mode in modes + [.additive] {
            var scene = GPUIScene(clearColor: backdrop)
            material.blendMode = Float(mode.rawValue)
            scene.addQuad(material)
            XCTAssertEqual(raster(scene).pixels, expected.pixels)
        }
    }

    private func quad(_ color: Color, mode: BlendMode = .normal) -> QuadPrimitive {
        QuadPrimitive(
            x: 0, y: 0, width: 32, height: 32,
            startR: color.red, startG: color.green, startB: color.blue, startA: color.alpha,
            endR: color.red, endG: color.green, endB: color.blue, endA: color.alpha,
            blendMode: Float(mode.rawValue))
    }

    private func image(_ texture: Int32) -> ImagePrimitive {
        ImagePrimitive(screenX: 0, screenY: 0, screenW: 32, screenH: 32, textureID: texture)
    }

    private func raster(_ scene: GPUIScene) -> BitmapSurface {
        var finished = scene
        finished.finish()
        return GPUIRawSceneRasterizer.rasterize(finished, size: size)
    }

    private func premultiplied(_ color: Color) -> [Float] {
        [color.red * color.alpha, color.green * color.alpha, color.blue * color.alpha, color.alpha]
    }

    /// Test oracle expressed as the three Porter-Duff overlap regions, not the
    /// adjusted-source helper used by production. Fixed literal vectors above
    /// independently anchor the oracle's alpha and channel convention.
    private func reference(source: Color, destination: [Float], mode: BlendMode) -> [Float] {
        let sourceChannels = [source.red, source.green, source.blue]
        let sa = source.alpha
        let da = destination[3]
        var result = [Float](repeating: 0, count: 4)
        for channel in 0..<3 {
            let cs = sourceChannels[channel]
            let cd = da > 0 ? destination[channel] / da : 0
            let overlap: Float
            switch mode {
            case .multiply:
                overlap = cs * cd
            case .screen:
                overlap = 1 - (1 - cs) * (1 - cd)
            case .overlay:
                overlap = cd <= 0.5 ? 2 * cs * cd : 1 - 2 * (1 - cs) * (1 - cd)
            case .normal, .additive:
                overlap = cs
            }
            result[channel] = sa * (1 - da) * cs + (1 - sa) * destination[channel] + sa * da * overlap
        }
        result[3] = sa + da * (1 - sa)
        return result
    }

    private func assertPixel(
        _ bitmap: BitmapSurface, x: Int, y: Int, premultiplied expected: [Float],
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let offset = y * Int(bitmap.bytesPerRow) + x * 4
        let alpha = Float(bitmap.pixels[offset + 3]) / 255
        let channels = [
            Float(bitmap.pixels[offset + 2]) / 255 * alpha,
            Float(bitmap.pixels[offset + 1]) / 255 * alpha,
            Float(bitmap.pixels[offset]) / 255 * alpha,
            alpha,
        ]
        for index in 0..<4 {
            XCTAssertEqual(channels[index], expected[index], accuracy: 4.0 / 255, file: file, line: line)
        }
    }
}
