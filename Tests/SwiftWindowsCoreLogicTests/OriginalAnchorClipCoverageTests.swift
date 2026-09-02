import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsGraphics

/// The expected clip values below come from fixed circle distances, not from
/// another render of the candidate. CPU pixels do not qualify shader execution.
final class OriginalAnchorClipCoverageTests: XCTestCase {
    private typealias Radii = GPUIQuadCoverage.CornerRadii
    private let canvas = Rect(x: 0, y: 0, width: 100, height: 100)
    private let canvasSize = IntSize(width: 100, height: 100)
    private let uneven = Radii(topLeft: 40, topRight: 4, bottomRight: 8, bottomLeft: 0)

    func testPartialCropDistinguishesAllFourModels() {
        let rejection = Rect(x: 0, y: 4, width: 100, height: 96)
        let models: [(GPUIClipRegion, [Double])] = [
            (region(rejection, scalar: 40), [0, 0]),
            (region(rejection, scalar: 8), [1, 0]),
            (region(rejection, radii: Radii(topLeft: 0, topRight: 0, bottomRight: 8, bottomLeft: 0)), [1, 1]),
            (region(rejection, radii: uneven, shape: canvas), [0, 1]),
        ]
        // Original TL: 35.5^2 + 31.5^2 = 2252.5 > 40^2.
        // Original BL is square; scalar 8 instead gives 6.5^2+6.5^2 > 8^2.
        for (clip, expected) in models {
            XCTAssertEqual([clip.alpha(atPixelX: 4, y: 8), clip.alpha(atPixelX: 1, y: 98)], expected)
        }
    }

    func testThinCropPreservesOriginalRadiusCap() {
        let rejection = Rect(x: 0, y: 0, width: 100, height: 4)
        let radii = Radii(topLeft: 40, topRight: 0, bottomRight: 0, bottomLeft: 0)
        let anchored = region(rejection, radii: radii, shape: canvas)
        let cropAnchored = region(rejection, radii: radii)
        // Original circle distance squared is 37.5^2 + 38.5^2 = 2888.5.
        // The wrong crop anchor caps 40 to 2, with distance -1.5.
        XCTAssertEqual(anchored.alpha(atPixelX: 2, y: 1), 0)
        XCTAssertEqual(cropAnchored.alpha(atPixelX: 2, y: 1), 1)
        XCTAssertEqual(anchored.alpha(atPixelX: 60, y: 1), 1)
        XCTAssertEqual(cropAnchored.alpha(atPixelX: 60, y: 1), 1)
    }

    func testOnePixelCropPreservesOriginalUniformAndUngatedHelpers() {
        let rejection = Rect(x: 1, y: 1, width: 1, height: 1)
        let shape = Rect(x: 0, y: 0, width: 20, height: 20)
        let anchored = region(rejection, radii: Radii(uniform: 5), shape: shape)
        // Helper centers (.5,.5), (1.5,.5), (.5,1.5) are outside R.
        let expected = onePixelCoverage
        XCTAssertEqual(anchored.alpha(atPixelX: 1, y: 1), expected, accuracy: 1e-12)
        XCTAssertGreaterThan(expected, 0.53)
        XCTAssertLessThan(expected, 0.55)
        XCTAssertEqual(region(rejection).alpha(atPixelX: 1, y: 1), 1)
        XCTAssertEqual(region(rejection, scalar: 5).alpha(atPixelX: 1, y: 1), 1)
    }

    func testExplicitShapeGateUsesHalfOpenEdgesEvenWithoutRounding() {
        let shape = Rect(x: 20.75, y: 20, width: 60, height: 60)
        for radii in [Radii(uniform: 0), Radii(topLeft: 0, topRight: 0, bottomRight: 8, bottomLeft: 0)] {
            let clip = region(canvas, radii: radii, shape: shape)
            XCTAssertEqual(clip.alpha(atPixelX: 20, y: 50), 0)
            XCTAssertEqual(clip.alpha(atPixelX: 50, y: 50), 1)
        }
        let sharedEdge = region(canvas, shape: Rect(x: 20.5, y: 20.5, width: 60, height: 60))
        XCTAssertEqual(sharedEdge.alpha(atPixelX: 20, y: 50), 1)
        XCTAssertEqual(sharedEdge.alpha(atPixelX: 80, y: 50), 0)
        XCTAssertEqual(sharedEdge.alpha(atPixelX: 50, y: 20), 1)
        XCTAssertEqual(sharedEdge.alpha(atPixelX: 50, y: 80), 0)
    }

    func testLegacyClipDefaultsResolveAfterMutation() {
        var clip = region(Rect(x: 0, y: 0, width: 20, height: 20), scalar: 5)
        XCTAssertEqual(clip.alpha(atPixelX: 1, y: 1), onePixelCoverage, accuracy: 1e-12)
        clip.cornerRadius = 0
        XCTAssertEqual(clip.alpha(atPixelX: 1, y: 1), 1)
        clip.x = 10
        clip.y = 10
        clip.width = 40
        clip.height = 40
        XCTAssertNil(clip.shapeBounds)
        XCTAssertNil(clip.cornerRadii)
        XCTAssertEqual(clip.alpha(atPixelX: 1, y: 1), 0)
        XCTAssertEqual(clip.alpha(atPixelX: 11, y: 11), 1)
        clip.cornerRadii = Radii(uniform: 5)
        XCTAssertEqual(clip.alpha(atPixelX: 11, y: 11), onePixelCoverage, accuracy: 1e-12)
        clip.cornerRadii = Radii(uniform: 0)
        clip.cornerRadius = 5
        XCTAssertEqual(clip.alpha(atPixelX: 11, y: 11), onePixelCoverage, accuracy: 1e-12)
    }

    func testPartialCropAcrossAllCPUConsumers() {
        for family in Family.allCases {
            let pixels = raster(
                family, rejection: Rect(x: 0, y: 4, width: 100, height: 96),
                shape: canvas, radii: uneven)
            assertWhiteCoverage(pixels, x: 4, y: 8, expected: 0, family: family)
            assertWhiteCoverage(pixels, x: 1, y: 98, expected: 1, family: family)
        }
    }

    func testThinCropAcrossAllCPUConsumers() {
        for family in Family.allCases {
            let pixels = raster(
                family, rejection: Rect(x: 0, y: 0, width: 100, height: 4), shape: canvas,
                radii: Radii(topLeft: 40, topRight: 0, bottomRight: 0, bottomLeft: 0))
            assertWhiteCoverage(pixels, x: 2, y: 1, expected: 0, family: family)
            assertWhiteCoverage(pixels, x: 60, y: 1, expected: 1, family: family)
        }
    }

    func testOnePixelCropAcrossAllCPUConsumers() {
        for family in Family.allCases {
            let pixels = raster(
                family, rejection: Rect(x: 1, y: 1, width: 1, height: 1),
                shape: Rect(x: 0, y: 0, width: 20, height: 20), radii: Radii(uniform: 5))
            assertWhiteCoverage(pixels, x: 1, y: 1, expected: onePixelCoverage, family: family)
            assertWhiteCoverage(pixels, x: 2, y: 1, expected: 0, family: family)
        }
    }

    func testExplicitAnchorZeroAndMixedRadiusGatesAcrossCPUConsumers() {
        for family in Family.allCases {
            for radii in [Radii(uniform: 0), Radii(topLeft: 0, topRight: 0, bottomRight: 8, bottomLeft: 0)] {
                let pixels = raster(
                    family, rejection: canvas, shape: Rect(x: 20.75, y: 20, width: 60, height: 60), radii: radii)
                assertWhiteCoverage(pixels, x: 20, y: 50, expected: 0, family: family)
                assertWhiteCoverage(pixels, x: 50, y: 50, expected: 1, family: family)
            }
        }
    }

    func testInactivePackedRejectionIgnoresValidExplicitAnchor() {
        let shape = Rect(x: 20.75, y: 20, width: 60, height: 60)
        for family in Family.allCases where family != .path {
            let pixels = raster(family, rejection: nil, shape: shape, radii: uneven)
            assertWhiteCoverage(pixels, x: 4, y: 8, expected: 1, family: family)
        }
        let clip = GPUIClipRegion(
            x: Double(0), y: 0, width: 0, height: 0, cornerRadius: 40,
            cornerRadii: uneven, shapeBounds: shape)
        XCTAssertFalse(clip.isActive)
        XCTAssertEqual(clip.alpha(atPixelX: 4, y: 8), 1)
    }

    func testNilPathClipKeepsTargetRoundingAndExplicitAnchor() {
        let legacy = raster(.path, rejection: nil, shape: nil, radii: Radii(uniform: 0), scalar: 40)
        assertWhiteCoverage(legacy, x: 4, y: 8, expected: 0, family: .path)
        assertWhiteCoverage(legacy, x: 50, y: 50, expected: 1, family: .path)
        let explicit = raster(
            .path, rejection: nil, shape: Rect(x: 20.75, y: 20, width: 60, height: 60),
            radii: Radii(uniform: 0))
        assertWhiteCoverage(explicit, x: 20, y: 50, expected: 0, family: .path)
        assertWhiteCoverage(explicit, x: 50, y: 50, expected: 1, family: .path)
    }

    func testSceneTranslationPreservesAnchorsRadiiAndOrder() throws {
        let offset = Point(x: 8, y: 10)
        let crop = Rect(x: 0, y: 4, width: 100, height: 96)
        let movedCrop = Rect(x: 8, y: 14, width: 100, height: 96)
        let movedShape = Rect(x: 8, y: 10, width: 100, height: 100)
        for family in [Family.quad, .glyph, .pixelGlyph, .image, .shadow, .path] {
            for shape in [Optional(canvas), nil] {
                for rejection in [Optional(crop), nil] {
                    let original = scene(family, rejection: rejection, shape: shape, radii: uneven)
                    let moved = original.translatedPrimitives(by: offset)
                    XCTAssertEqual(Array(moved.presentationOrder()), Array(original.presentationOrder()))
                    XCTAssertEqual(moved.paintRecordCount, original.paintRecordCount)
                    XCTAssertEqual(moved.imageResources, original.imageResources)
                    XCTAssertEqual(moved.glyphAtlas, original.glyphAtlas)
                    XCTAssertEqual(moved.pixelGlyphAtlas, original.pixelGlyphAtlas)
                    let states = clipStates(moved)
                    XCTAssertEqual(states.count, 1, family.rawValue)
                    let state = try XCTUnwrap(states.first)
                    XCTAssertEqual(state.shape, shape == nil ? nil : movedShape, family.rawValue)
                    XCTAssertEqual(state.rejection, rejection == nil ? nil : movedCrop, family.rawValue)
                    XCTAssertEqual(state.radii, [40, 4, 8, 0], family.rawValue)
                }
            }
        }
    }

    func testSceneTranslationLeavesNestedImageNamespacesUnchanged() throws {
        let child = scene(
            .quad, rejection: Rect(x: 0, y: 4, width: 100, height: 96), shape: canvas, radii: uneven)
        var outer = GPUIScene(clearColor: .black)
        let textureID = outer.registerImageRenderPass(child, size: canvasSize)
        outer.addImage(
            ImagePrimitive(
                screenW: 100, screenH: 100, clipWidth: 100, clipHeight: 100, textureID: textureID,
                clipCornerRadiusTopLeft: 40, clipCornerRadiusBottomRight: 8, clipShapeBounds: canvas))
        outer.finish()
        let moved = outer.translatedPrimitives(by: Point(x: 8, y: 10))
        XCTAssertEqual(Array(moved.presentationOrder()), Array(outer.presentationOrder()))
        XCTAssertEqual(moved.imageRenderPasses, outer.imageRenderPasses)
        XCTAssertEqual(
            moved.layers[0].images[0].clipShapeBounds, Rect(x: 8, y: 10, width: 100, height: 100))
        let pass = try XCTUnwrap(moved.imageRenderPasses.first)
        XCTAssertEqual(pass.scene.layers[0].quads[0].clipShapeBounds, canvas)
        XCTAssertEqual(pass.scene.layers[0].quads[0].clipY, 4)
    }

    func testPathTransformsCarryAnchorAndRadiiWithoutRotatingTheClip() {
        let path = self.path(
            rejection: Rect(x: 0, y: 4, width: 100, height: 96), shape: canvas, radii: uneven, scalar: 3)
        let translated = path.translated(by: Point(x: 8, y: 10))
        XCTAssertEqual(translated.clipBounds, Rect(x: 8, y: 14, width: 100, height: 96))
        XCTAssertEqual(translated.clipShapeBounds, Rect(x: 8, y: 10, width: 100, height: 100))
        XCTAssertEqual(pathRadii(translated), [40, 4, 8, 0])
        XCTAssertEqual(translated.clipCornerRadius, 3)
        let scaled = path.scaled(by: 1.5)
        XCTAssertEqual(scaled.clipBounds, Rect(x: 0, y: 6, width: 150, height: 144))
        XCTAssertEqual(scaled.clipShapeBounds, Rect(x: 0, y: 0, width: 150, height: 150))
        XCTAssertEqual(pathRadii(scaled), [60, 6, 12, 0])
        XCTAssertEqual(scaled.clipCornerRadius, 4.5)
        let rotated = path.rotated(by: .pi / 4, about: Point(x: 50, y: 50))
        XCTAssertEqual(rotated.clipBounds, path.clipBounds)
        XCTAssertEqual(rotated.clipShapeBounds, path.clipShapeBounds)
        XCTAssertEqual(pathRadii(rotated), pathRadii(path))
        XCTAssertEqual(rotated.clipCornerRadius, path.clipCornerRadius)
        let absent = self.path(rejection: nil, shape: nil, radii: Radii(uniform: 0))
        XCTAssertNil(absent.translated(by: Point(x: 8, y: 10)).clipShapeBounds)
        XCTAssertNil(absent.scaled(by: 1.5).clipShapeBounds)
    }

    func testPathShapeIdentityIgnoresAllClipMetadata() {
        let original = path(rejection: nil, shape: nil, radii: Radii(uniform: 0))
        var clipped = original
        clipped.clipBounds = Rect(x: 0, y: 4, width: 100, height: 96)
        clipped.clipShapeBounds = canvas
        clipped.clipCornerRadius = 8
        clipped.clipCornerRadiusTopLeft = 40
        clipped.clipCornerRadiusTopRight = 4
        clipped.clipCornerRadiusBottomRight = 8
        clipped.clipCornerRadiusBottomLeft = 2
        XCTAssertNotEqual(clipped, original)
        XCTAssertEqual(clipped.shapeHash, original.shapeHash)
        XCTAssertTrue(clipped.matchesShapeAndPaint(of: original, translatedBy: Point(x: 0, y: 0)))
    }

    private var onePixelCoverage: Double {
        0.5 - (sqrt(24.5) - 5) / (2 * (sqrt(40.5) - sqrt(32.5)))
    }

    private func region(
        _ rejection: Rect, scalar: Double = 0, radii: Radii? = nil, shape: Rect? = nil
    ) -> GPUIClipRegion {
        GPUIClipRegion(
            x: rejection.minX, y: rejection.minY, width: rejection.width, height: rejection.height,
            cornerRadius: scalar, cornerRadii: radii, shapeBounds: shape)
    }

    private enum Family: String, CaseIterable {
        case quad, glyph, pixelGlyph, image, shadow, path, material
        case currentTargetImage, isolatedBackdropImage, isolatedMaterial
    }

    private func raster(
        _ family: Family, rejection: Rect?, shape: Rect?, radii: Radii, scalar: Float = 0
    ) -> BitmapSurface {
        let scene = self.scene(family, rejection: rejection, shape: shape, radii: radii, scalar: scalar)
        XCTAssertTrue(scene.validate().isEmpty, family.rawValue)
        return GPUIRawSceneRasterizer.rasterize(scene, size: canvasSize)
    }

    private func scene(
        _ family: Family, rejection: Rect?, shape: Rect?, radii: Radii, scalar: Float = 0
    ) -> GPUIScene {
        let atlas = GlyphAtlasSnapshot(width: 2, height: 2, pixels: Data(repeating: 255, count: 16))
        var scene = GPUIScene(clearColor: .black, glyphAtlas: atlas, pixelGlyphAtlas: atlas)
        let r = rejection ?? Rect(x: 0, y: 0, width: 0, height: 0)
        func quad(clipped: Bool, material: Bool = false) -> QuadPrimitive {
            QuadPrimitive(
                width: 100, height: 100,
                startR: 1, startG: 1, startB: 1, endR: 1, endG: 1, endB: 1,
                clipX: clipped ? Float(r.minX) : 0, clipY: clipped ? Float(r.minY) : 0,
                clipWidth: clipped ? Float(r.width) : 0, clipHeight: clipped ? Float(r.height) : 0,
                clipCornerRadius: clipped ? scalar : 0, blurRadius: material ? 1 : 0,
                clipCornerRadiusTopLeft: clipped ? Float(radii.topLeft) : 0,
                clipCornerRadiusTopRight: clipped ? Float(radii.topRight) : 0,
                clipCornerRadiusBottomRight: clipped ? Float(radii.bottomRight) : 0,
                clipCornerRadiusBottomLeft: clipped ? Float(radii.bottomLeft) : 0,
                clipShapeBounds: clipped ? shape : nil)
        }
        func image(_ textureID: Int32, clipped: Bool = true) -> ImagePrimitive {
            ImagePrimitive(
                screenW: 100, screenH: 100,
                clipX: clipped ? Float(r.minX) : 0, clipY: clipped ? Float(r.minY) : 0,
                clipWidth: clipped ? Float(r.width) : 0, clipHeight: clipped ? Float(r.height) : 0,
                clipCornerRadius: clipped ? scalar : 0, textureID: textureID,
                clipCornerRadiusTopLeft: clipped ? Float(radii.topLeft) : 0,
                clipCornerRadiusTopRight: clipped ? Float(radii.topRight) : 0,
                clipCornerRadiusBottomRight: clipped ? Float(radii.bottomRight) : 0,
                clipCornerRadiusBottomLeft: clipped ? Float(radii.bottomLeft) : 0,
                clipShapeBounds: clipped ? shape : nil)
        }
        switch family {
        case .quad, .material:
            scene.addQuad(quad(clipped: true, material: family == .material))
        case .glyph, .pixelGlyph:
            let glyph = GlyphPrimitive(
                screenW: 100, screenH: 100, atlasU1: 1, atlasV1: 1,
                clipX: Float(r.minX), clipY: Float(r.minY), clipWidth: Float(r.width), clipHeight: Float(r.height),
                clipCornerRadius: scalar,
                clipCornerRadiusTopLeft: Float(radii.topLeft), clipCornerRadiusTopRight: Float(radii.topRight),
                clipCornerRadiusBottomRight: Float(radii.bottomRight),
                clipCornerRadiusBottomLeft: Float(radii.bottomLeft),
                clipShapeBounds: shape)
            if family == .glyph { scene.addGlyph(glyph) } else { scene.addPixelGlyph(glyph) }
        case .image:
            let bitmap = BitmapSurface(
                width: 2, height: 2, bytesPerRow: 8, pixels: Data(repeating: 255, count: 16))
            let textureID = scene.registerImageResource(bitmap)
            scene.addImage(image(textureID))
        case .shadow:
            scene.addShadow(
                ShadowPrimitive(
                    width: 100, height: 100, colorR: 1, colorG: 1, colorB: 1, colorA: 1, blurRadius: 0,
                    clipX: Float(r.minX), clipY: Float(r.minY), clipWidth: Float(r.width), clipHeight: Float(r.height),
                    clipCornerRadius: scalar,
                    clipCornerRadiusTopLeft: Float(radii.topLeft), clipCornerRadiusTopRight: Float(radii.topRight),
                    clipCornerRadiusBottomRight: Float(radii.bottomRight),
                    clipCornerRadiusBottomLeft: Float(radii.bottomLeft), clipShapeBounds: shape))
        case .path:
            scene.addPath(path(rejection: rejection, shape: shape, radii: radii, scalar: Double(scalar)), toLayer: 0)
        case .currentTargetImage, .isolatedBackdropImage, .isolatedMaterial:
            var source = GPUIScene(clearColor: .clear)
            source.addQuad(quad(clipped: family == .isolatedMaterial, material: family == .isolatedMaterial))
            source.finish()
            let input: GPUISceneImageRenderPassInput =
                family == .currentTargetImage ? .currentTarget : .isolatedBackdrop
            let textureID = scene.registerImageRenderPass(source, size: canvasSize, input: input)
            scene.addImage(image(textureID, clipped: family != .isolatedMaterial))
        }
        scene.finish()
        return scene
    }

    private func path(rejection: Rect?, shape: Rect?, radii: Radii, scalar: Double = 0) -> PathPrimitive {
        PathPrimitive(
            elements: [
                .moveTo(Point(x: 0, y: 0)), .lineTo(Point(x: 100, y: 0)),
                .lineTo(Point(x: 100, y: 100)), .lineTo(Point(x: 0, y: 100)), .close,
            ],
            bounds: canvas, fillColor: .white, clipBounds: rejection, clipCornerRadius: scalar,
            clipCornerRadiusTopLeft: radii.topLeft, clipCornerRadiusTopRight: radii.topRight,
            clipCornerRadiusBottomRight: radii.bottomRight, clipCornerRadiusBottomLeft: radii.bottomLeft,
            clipShapeBounds: shape)
    }

    private func pathRadii(_ path: PathPrimitive) -> [Double] {
        [
            path.clipCornerRadiusTopLeft, path.clipCornerRadiusTopRight,
            path.clipCornerRadiusBottomRight, path.clipCornerRadiusBottomLeft,
        ]
    }

    private struct ClipState {
        var rejection: Rect?
        var shape: Rect?
        var radii: [Double]
    }

    private func clipStates(_ scene: GPUIScene) -> [ClipState] {
        var states: [ClipState] = []
        for layer in scene.layers {
            for q in layer.quads {
                states.append(
                    ClipState(
                        rejection: q.contentMask.bounds, shape: q.clipShapeBounds,
                        radii: [
                            Double(q.clipCornerRadiusTopLeft), Double(q.clipCornerRadiusTopRight),
                            Double(q.clipCornerRadiusBottomRight), Double(q.clipCornerRadiusBottomLeft),
                        ]))
            }
            for g in layer.glyphs + layer.pixelGlyphs {
                states.append(
                    ClipState(
                        rejection: g.contentMask.bounds, shape: g.clipShapeBounds,
                        radii: [
                            Double(g.clipCornerRadiusTopLeft), Double(g.clipCornerRadiusTopRight),
                            Double(g.clipCornerRadiusBottomRight), Double(g.clipCornerRadiusBottomLeft),
                        ]))
            }
            for i in layer.images {
                states.append(
                    ClipState(
                        rejection: i.contentMask.bounds, shape: i.clipShapeBounds,
                        radii: [
                            Double(i.clipCornerRadiusTopLeft), Double(i.clipCornerRadiusTopRight),
                            Double(i.clipCornerRadiusBottomRight), Double(i.clipCornerRadiusBottomLeft),
                        ]))
            }
            for s in layer.shadows {
                states.append(
                    ClipState(
                        rejection: s.contentMask.bounds, shape: s.clipShapeBounds,
                        radii: [
                            Double(s.clipCornerRadiusTopLeft), Double(s.clipCornerRadiusTopRight),
                            Double(s.clipCornerRadiusBottomRight), Double(s.clipCornerRadiusBottomLeft),
                        ]))
            }
            for p in layer.paths {
                states.append(ClipState(rejection: p.clipBounds, shape: p.clipShapeBounds, radii: pathRadii(p)))
            }
        }
        return states
    }

    private func assertWhiteCoverage(
        _ bitmap: BitmapSurface, x: Int, y: Int, expected: Double, family: Family,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let offset = y * Int(bitmap.bytesPerRow) + x * 4
        // White over opaque black makes each color channel the clip coverage.
        // Two UNORM steps cover isolated foreground/coverage conversion too.
        for channel in 0..<3 {
            XCTAssertEqual(
                Double(bitmap.pixels[offset + channel]) / 255, expected, accuracy: 2.0 / 255,
                family.rawValue, file: file, line: line)
        }
        XCTAssertEqual(bitmap.pixels[offset + 3], 255, family.rawValue, file: file, line: line)
    }
}
