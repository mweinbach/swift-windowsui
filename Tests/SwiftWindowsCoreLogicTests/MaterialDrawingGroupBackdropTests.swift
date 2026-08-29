import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsGraphics
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// A material in an admitted group reads the enclosing target at its image's
/// presentation position. These tests keep numerical and visible-blur oracles
/// separate from agreement between two ways of constructing the same scene.
@MainActor
final class MaterialDrawingGroupBackdropTests: XCTestCase {
    private enum GroupKind: CaseIterable {
        case inline
        case compositing
        case drawing
    }

    private let stripeSize = IntSize(width: 100, height: 100)
    private let halfRed = Color(red: 1, green: 0, blue: 0, alpha: 0.5)
    private let blueTint = Color(red: 0, green: 0, blue: 1, alpha: 0.4)

    // C01: Keep the historical manual fixture literally 100x100 at scale 1.
    func testPlainGroupsBlurTheEnclosingStripeBackdrop() async throws {
        for scale in [1.0, 2.0] {
            let size = IntSize(width: Int32(100 * scale), height: Int32(100 * scale))
            let interior = Int(40 * scale)..<Int(60 * scale)
            let inline = paint(stripeFixture(kind: .inline).root, size: size, displayScale: scale)
            let inlinePixels = raster(inline, size: size)
            XCTAssertLessThan(maxNeighbourDelta(inlinePixels, rows: interior, columns: interior), 20)

            let publicInline = publicStripeScene(kind: .inline, displayScale: scale)
            let publicInlinePixels = raster(publicInline, size: size)
            XCTAssertLessThan(maxNeighbourDelta(publicInlinePixels, rows: interior, columns: interior), 20)
            for kind in [GroupKind.compositing, .drawing] {
                let fixture = stripeFixture(kind: kind)
                let scene = paint(fixture.root, size: size, displayScale: scale)
                let pass = try XCTUnwrap(scene.imageRenderPasses.first)
                XCTAssertEqual(scene.imageRenderPasses.count, 1)
                XCTAssertEqual(pass.input, .currentTarget)
                XCTAssertEqual(pass.size, size)
                XCTAssertTrue(scene.imageResources.isEmpty, "The parent backdrop must not become a cached bitmap")
                XCTAssertNil(fixture.group.cachedCompositingGroupBitmap)
                XCTAssertTrue(scene.validate().isEmpty)
                XCTAssertEqual(pass.scene.layers.flatMap(\.quads).count, 1, "The stripes belong only to the parent")
                let pixels = raster(scene, size: size)
                XCTAssertLessThan(maxNeighbourDelta(pixels, rows: interior, columns: interior), 20)
                assertMatchingPixels(pixels, inlinePixels)
                let center = try XCTUnwrap(pixels.pixelColor(atX: Int(50 * scale), y: Int(50 * scale)))
                XCTAssertGreaterThan(center.red, 0.55, "A missing or flat-tint panel is not a blurred backdrop")
                XCTAssertLessThan(center.red, 0.9, "A blank white result also has zero stripe contrast")
                XCTAssertEqual(center.alpha, 1, accuracy: 0.01)

                // Material.regular has its own light tint and radius. Compare
                // it with its public inline producer, not with the manual tint.
                let publicScene = publicStripeScene(kind: kind, displayScale: scale)
                let publicPass = try XCTUnwrap(publicScene.imageRenderPasses.first)
                XCTAssertEqual(publicPass.input, .currentTarget)
                XCTAssertEqual(publicPass.size, size)
                XCTAssertTrue(publicScene.imageResources.isEmpty)
                XCTAssertTrue(publicScene.validate().isEmpty)
                XCTAssertTrue(publicPass.scene.layers.flatMap(\.quads).contains { $0.blurRadius == Float(22 * scale) })
                let publicPixels = raster(publicScene, size: size)
                XCTAssertLessThan(maxNeighbourDelta(publicPixels, rows: interior, columns: interior), 20)
                assertMatchingPixels(publicPixels, publicInlinePixels)
                let publicCenter = try XCTUnwrap(publicPixels.pixelColor(atX: Int(50 * scale), y: Int(50 * scale)))
                XCTAssertGreaterThan(publicCenter.red, 0.55)
                XCTAssertLessThan(publicCenter.red, 0.9)
                XCTAssertEqual(publicCenter.alpha, 1, accuracy: 0.01)
            }
        }
    }

    // C02: An inherited backdrop is input, not an additional source-over layer.
    func testUntouchedPixelsAndUntintedHalfAlphaBackdropStayUnchanged() async {
        let size = IntSize(width: 32, height: 32)
        var parent = GPUIScene(clearColor: .clear)
        parent.addQuad(quad(Rect(x: 4, y: 4, width: 24, height: 24), color: halfRed))
        parent.finish()
        let before = raster(parent, size: size)

        var empty = parent
        let emptyID = empty.registerImageRenderPass(GPUIScene(clearColor: .clear), size: size, input: .currentTarget)
        for _ in 0..<2 {
            empty.addImage(ImagePrimitive(screenW: 32, screenH: 32, textureID: emptyID))
        }
        empty.finish()
        XCTAssertTrue(empty.validate().isEmpty)
        XCTAssertEqual(raster(empty, size: size), before, "Even repeated empty passes must preserve every byte")

        var untinted = parent
        let child = materialSource(
            size: size, frame: Rect(x: 8, y: 8, width: 16, height: 16), tint: .clear, radius: 3)
        let textureID = untinted.registerImageRenderPass(child, size: size, input: .currentTarget)
        untinted.addImage(ImagePrimitive(screenW: 32, screenH: 32, textureID: textureID))
        untinted.finish()
        XCTAssertTrue(untinted.validate().isEmpty)
        let after = raster(untinted, size: size)
        assertMatchingPixels(after, before)
        assertPremultiplied(after, x: 16, y: 16, red: 0.5, green: 0, blue: 0, alpha: 0.5)
        assertPremultiplied(after, x: 0, y: 0, red: 0, green: 0, blue: 0, alpha: 0, accuracy: 0)
        assertPremultiplied(after, x: 6, y: 6, red: 0.5, green: 0, blue: 0, alpha: 0.5)
    }

    // C03: Values below are premultiplied Porter-Duff arithmetic, not a render.
    func testGroupOpacityInterpolatesPremultipliedReplacement() async {
        let size = IntSize(width: 24, height: 24)
        for opacity in [0.0, 0.5, 1.0] {
            for kind in [GroupKind.compositing, .drawing] {
                let panel = ViewNode(
                    frame: Rect(x: 0, y: 0, width: 24, height: 24), backgroundColor: blueTint, blurRadius: 6)
                let group = makeGroup(kind, frame: Rect(x: 0, y: 0, width: 24, height: 24), children: [panel])
                group.opacity = opacity
                let scene = paint(group, size: size, clearColor: halfRed)
                XCTAssertTrue(scene.validate().isEmpty)
                if opacity > 0 {
                    XCTAssertEqual(scene.imageRenderPasses.first?.input, .currentTarget)
                }
                let amount = Float(opacity)
                let pixels = raster(scene, size: size)
                assertPremultiplied(
                    pixels, x: 12, y: 12, red: 0.5 - 0.2 * amount, green: 0,
                    blue: 0.4 * amount, alpha: 0.5 + 0.2 * amount)
                if opacity == 0.5 {
                    assertPremultiplied(pixels, x: 12, y: 12, red: 0.4, green: 0, blue: 0.2, alpha: 0.6)
                }
            }
        }
    }

    // C04: Copy the whole admitted seed; the rounded clip controls only output.
    func testRoundedOutputClipRetainsUncoveredBackdrop() async {
        let size = IntSize(width: 24, height: 24)
        var scene = GPUIScene(clearColor: halfRed)
        let source = materialSource(size: size, tint: blueTint, radius: 6)
        let textureID = scene.registerImageRenderPass(source, size: size, input: .currentTarget)
        scene.addImage(
            ImagePrimitive(
                screenW: 24, screenH: 24,
                clipX: 4.5, clipY: 4, clipWidth: 16, clipHeight: 16, clipCornerRadius: 4,
                textureID: textureID))
        scene.finish()
        XCTAssertTrue(scene.validate().isEmpty)
        let pixels = raster(scene, size: size)
        assertPremultiplied(pixels, x: 12, y: 12, red: 0.3, green: 0, blue: 0.4, alpha: 0.7)
        // The pixel centre is exactly on the straight portion of the rounded
        // clip's left boundary, giving half coverage independently of alpha.
        assertPremultiplied(pixels, x: 4, y: 12, red: 0.4, green: 0, blue: 0.2, alpha: 0.6)
        assertPremultiplied(pixels, x: 4, y: 4, red: 0.5, green: 0, blue: 0, alpha: 0.5)
        assertPremultiplied(pixels, x: 22, y: 12, red: 0.5, green: 0, blue: 0, alpha: 0.5)

        let patternedSize = IntSize(width: 64, height: 32)
        let parent = stripeScene(size: patternedSize)
        let before = raster(parent, size: patternedSize)
        let frame = Rect(x: 8, y: 0, width: 48, height: 32)
        var inline = parent
        inline.addQuad(quad(frame, color: blueTint, radius: 6))
        inline.finish()
        var clipped = parent
        let clippedID = clipped.registerImageRenderPass(
            materialSource(size: patternedSize, frame: frame, tint: blueTint, radius: 6),
            size: patternedSize, input: .currentTarget)
        clipped.addImage(
            ImagePrimitive(
                screenW: 64, screenH: 32,
                clipX: 4.5, clipY: 4, clipWidth: 56, clipHeight: 24, clipCornerRadius: 8,
                textureID: clippedID))
        clipped.finish()
        let clippedPixels = raster(clipped, size: patternedSize)
        let inlinePixels = raster(inline, size: patternedSize)
        assertSamePixel(clippedPixels, before, x: 0, y: 12)
        assertSamePixel(clippedPixels, before, x: 4, y: 4)
        assertSamePixel(clippedPixels, before, x: 32, y: 30)
        // This material pixel reads stripe taps above the output clip. Clearing
        // those seed pixels would change it despite full output coverage here.
        assertSamePixel(clippedPixels, inlinePixels, x: 32, y: 4)
        assertSamePixel(clippedPixels, inlinePixels, x: 32, y: 12)
    }

    // C05: Same-ID neighbours cannot share a resolved parent-dependent bitmap.
    func testEveryUseOfAContextualTextureReadsItsCurrentPrefix() async {
        let size = IntSize(width: 64, height: 16)
        let childSize = IntSize(width: 16, height: 16)
        var scene = GPUIScene(clearColor: .clear)
        scene.addQuad(quad(Rect(x: 0, y: 0, width: 32, height: 16), color: halfRed))
        scene.addQuad(
            quad(Rect(x: 32, y: 0, width: 32, height: 16), color: Color(red: 0, green: 1, blue: 0, alpha: 0.5)))
        let textureID = scene.registerImageRenderPass(
            materialSource(size: childSize, tint: blueTint), size: childSize, input: .currentTarget)
        scene.addImage(ImagePrimitive(screenW: 16, screenH: 16, textureID: textureID))
        scene.addImage(ImagePrimitive(screenX: 32, screenW: 16, screenH: 16, textureID: textureID))
        scene.finish()
        let distinct = raster(scene, size: size)
        assertPremultiplied(distinct, x: 8, y: 8, red: 0.3, green: 0, blue: 0.4, alpha: 0.7)
        assertPremultiplied(distinct, x: 40, y: 8, red: 0, green: 0.3, blue: 0.4, alpha: 0.7)

        scene.addImage(ImagePrimitive(screenW: 16, screenH: 16, textureID: textureID))
        scene.finish()
        let repeated = raster(scene, size: size)
        assertPremultiplied(repeated, x: 8, y: 8, red: 0.18, green: 0, blue: 0.64, alpha: 0.82)
        assertPremultiplied(repeated, x: 40, y: 8, red: 0, green: 0.3, blue: 0.4, alpha: 0.7)
        XCTAssertEqual(scene.imageRenderPasses.count, 1)
        XCTAssertEqual(scene.layers[0].images.map(\.textureID), [textureID, textureID, textureID])

        scene.addQuad(quad(Rect(x: 0, y: 0, width: 16, height: 16), color: Color(red: 1, green: 1, blue: 0, alpha: 1)))
        scene.addImage(ImagePrimitive(screenW: 16, screenH: 16, textureID: textureID))
        scene.finish()
        XCTAssertTrue(scene.validate().isEmpty)
        let afterInterveningDraw = raster(scene, size: size)
        assertPremultiplied(afterInterveningDraw, x: 8, y: 8, red: 0.6, green: 0.6, blue: 0.4, alpha: 1)
    }

    // C06: Earlier paint records in a higher layer are not earlier pixels.
    func testBackdropSamplingFollowsLayerPresentationOrder() async {
        let size = IntSize(width: 32, height: 32)
        var scene = GPUIScene(clearColor: .clear)
        let textureID = scene.registerImageRenderPass(
            materialSource(size: size, tint: blueTint), size: size, input: .currentTarget)
        scene.addImage(ImagePrimitive(screenW: 32, screenH: 32, textureID: textureID), toLayer: 1)
        scene.addQuad(quad(Rect(x: 0, y: 0, width: 32, height: 32), color: halfRed), toLayer: 0)
        scene.addQuad(
            quad(Rect(x: 0, y: 0, width: 8, height: 32), color: Color(red: 0, green: 1, blue: 0, alpha: 1)),
            toLayer: 2)
        scene.finish()
        XCTAssertEqual(presentationSequence(scene), ["0/quad/0", "1/image/0", "2/quad/0"])
        if case .primitive(let layer, let kind, _)? = scene.paintRecords.first {
            XCTAssertEqual(layer, 1)
            XCTAssertEqual(kind, .image)
        } else {
            XCTFail("The fixture must record the group before the lower-layer background")
        }
        XCTAssertTrue(scene.validate().isEmpty)
        let pixels = raster(scene, size: size)
        assertPremultiplied(pixels, x: 16, y: 16, red: 0.3, green: 0, blue: 0.4, alpha: 0.7)
        // A future foreground must not leak through blur at its uncovered edge.
        assertPremultiplied(pixels, x: 8, y: 16, red: 0.3, green: 0, blue: 0.4, alpha: 0.7)
        assertPremultiplied(pixels, x: 4, y: 16, red: 0, green: 1, blue: 0, alpha: 1, accuracy: 0)
    }

    // C07: The crop is derived from the current consuming image after replay.
    func testReplayAndTranslationKeepContextualSourcePlacement() async throws {
        let childSize = IntSize(width: 16, height: 16)
        let size = IntSize(width: 64, height: 16)
        var original = GPUIScene(clearColor: .clear)
        let originalID = original.registerImageRenderPass(
            materialSource(size: childSize, tint: blueTint), size: childSize, input: .currentTarget)
        original.addImage(ImagePrimitive(screenW: 16, screenH: 16, textureID: originalID))
        original.finish()
        let translated = original.translatedPrimitives(by: Point(x: 32, y: 0))
        XCTAssertEqual(translated.imageRenderPasses, original.imageRenderPasses)

        var replay = GPUIScene(clearColor: .clear)
        replay.addQuad(quad(Rect(x: 0, y: 0, width: 32, height: 16), color: halfRed))
        replay.addQuad(
            quad(Rect(x: 32, y: 0, width: 32, height: 16), color: Color(red: 0, green: 1, blue: 0, alpha: 0.5)))
        let sentinel = BitmapSurface(width: 1, height: 1, bytesPerRow: 4, pixels: Data([0, 255, 255, 255]))
        let occupiedID = replay.registerImageResource(sentinel)
        XCTAssertEqual(occupiedID, originalID, "The fixture must force namespace rebinding")
        replay.addImage(ImagePrimitive(screenX: 56, screenW: 8, screenH: 16, textureID: occupiedID))
        XCTAssertEqual(replay.replay(0..<translated.paintRecordCount, from: translated), .success)
        replay.finish()
        let rebound = try XCTUnwrap(replay.imageRenderPasses.first)
        let consumingImage = try XCTUnwrap(replay.layers.flatMap(\.images).first { $0.textureID == rebound.textureID })
        XCTAssertNotEqual(rebound.textureID, occupiedID)
        XCTAssertEqual(rebound.input, .currentTarget)
        XCTAssertEqual(rebound.scene, original.imageRenderPasses[0].scene)
        XCTAssertEqual(consumingImage.screenX, 32)
        let region = try XCTUnwrap(rebound.currentTargetRegion(for: consumingImage, parentSize: size))
        XCTAssertEqual(region.originX, 32)
        XCTAssertEqual(region.originY, 0)
        XCTAssertEqual(region.width, 16)
        XCTAssertTrue(replay.validate().isEmpty)
        let pixels = raster(replay, size: size)
        assertPremultiplied(pixels, x: 8, y: 8, red: 0.5, green: 0, blue: 0, alpha: 0.5)
        assertPremultiplied(pixels, x: 40, y: 8, red: 0, green: 0.3, blue: 0.4, alpha: 0.7)
        assertPremultiplied(pixels, x: 60, y: 8, red: 1, green: 1, blue: 0, alpha: 1, accuracy: 0)
    }

    // C08: Only wallpaper changes; the material node remains clean and still blurs.
    func testCleanGroupReplayTracksOnlyExternalBackdropChanges() async throws {
        try assertExternalBackdropMotion(wrappedInCleanAncestor: false)
    }

    // C09: Replaying a clean ancestor must retain the dependent source, not pixels.
    func testCleanAncestorReplayTracksAnExternalBackdropChange() async throws {
        try assertExternalBackdropMotion(wrappedInCleanAncestor: true)
    }

    // C10: A nested source sees its immediate target's earlier local drawing.
    func testNestedDependentSourceSamplesItsImmediateParent() async {
        let size = IntSize(width: 32, height: 32)
        var outer = GPUIScene(clearColor: .clear)
        outer.addQuad(
            quad(Rect(x: 0, y: 0, width: 32, height: 32), color: Color(red: 0, green: 1, blue: 0, alpha: 0.5)))
        let innerID = outer.registerImageRenderPass(
            materialSource(size: size, tint: blueTint), size: size, input: .currentTarget)
        outer.addImage(ImagePrimitive(screenW: 32, screenH: 32, textureID: innerID))
        outer.addQuad(quad(Rect(x: 0, y: 0, width: 8, height: 32), color: .white))
        outer.finish()
        var parent = GPUIScene(clearColor: halfRed)
        let outerID = parent.registerImageRenderPass(outer, size: size, input: .currentTarget)
        parent.addImage(ImagePrimitive(screenW: 32, screenH: 32, textureID: outerID))
        parent.finish()
        XCTAssertTrue(parent.validate().isEmpty)
        let pixels = raster(parent, size: size)
        // Green over the seed gives (.25, .5, 0, .75). Blue material then
        // gives (.15, .3, .4, .85); the later white sibling is not in the seed.
        assertPremultiplied(pixels, x: 16, y: 16, red: 0.15, green: 0.3, blue: 0.4, alpha: 0.85)
        // Probe within the kernel's reach of that future sibling as well.
        assertPremultiplied(pixels, x: 8, y: 16, red: 0.15, green: 0.3, blue: 0.4, alpha: 0.85)
        assertPremultiplied(pixels, x: 4, y: 16, red: 1, green: 1, blue: 1, alpha: 1, accuracy: 0)

        // An independent ancestor starts transparent. Its nested material
        // must not jump through that boundary to blur the grandparent stripes.
        let panel = materialSource(
            size: stripeSize, frame: Rect(x: 20, y: 20, width: 60, height: 60),
            tint: Color(red: 1, green: 1, blue: 1, alpha: 0.35), radius: 12)
        var middle = GPUIScene(clearColor: .clear)
        let nestedID = middle.registerImageRenderPass(panel, size: stripeSize, input: .currentTarget)
        middle.addImage(ImagePrimitive(screenW: 100, screenH: 100, textureID: nestedID))
        middle.finish()
        for input in [GPUISceneImageRenderPassInput.independent, .currentTarget] {
            var stripes = stripeScene(size: stripeSize)
            let boundaryID = stripes.registerImageRenderPass(middle, size: stripeSize, input: input)
            stripes.addImage(ImagePrimitive(screenW: 100, screenH: 100, textureID: boundaryID))
            stripes.finish()
            XCTAssertTrue(stripes.validate().isEmpty)
            let result = raster(stripes)
            let contrast = maxNeighbourDelta(result, rows: 40..<60, columns: 40..<60)
            if input == .currentTarget {
                XCTAssertLessThan(contrast, 20)
            } else {
                XCTAssertGreaterThan(contrast, 100, "An independent target must keep its own transparent backdrop")
                assertPremultiplied(result, x: 50, y: 43, red: 0.35, green: 0.35, blue: 0.35, alpha: 1)
            }
        }
    }

    // C11: Large extents are declarations only; rendered budget fixtures are 4x2.
    func testContextualMappingAndBudgetsAreValidatedBeforeAllocation() async {
        let tiny = IntSize(width: 2, height: 2)
        let parentSize = IntSize(width: 8, height: 8)
        let pass = GPUISceneImageRenderPass(
            textureID: 7, scene: GPUIScene(clearColor: .clear), size: tiny, input: .currentTarget)
        let image = ImagePrimitive(screenX: 2, screenY: 2, screenW: 2, screenH: 2, textureID: 7)

        // Raw layers preserve hostile values that addImage would sanitize or
        // drop. Validation must see the actual malformed consumer being tested.
        func defects(_ source: GPUISceneImageRenderPass, _ consumer: ImagePrimitive) -> [SceneDefect] {
            var scene = GPUIScene(clearColor: .clear, imageRenderPasses: [source])
            scene.installHandBuiltLayers([
                GPUILayer(images: [consumer], paintOperations: [GPUIPaintOperation(kind: .image, startIndex: 0)])
            ])
            return scene.validate()
        }
        func hasPassDefect(_ issues: [SceneDefect]) -> Bool {
            issues.contains {
                if case .invalidImageRenderPass = $0.kind { return true }
                return false
            }
        }

        XCTAssertTrue(defects(pass, image).isEmpty)
        XCTAssertEqual(
            pass.currentTargetRegion(for: image, parentSize: parentSize),
            SubTextureRegion(originX: 2, originY: 2, width: 2, height: 2, textureWidth: 8, textureHeight: 8))
        let origins: [WritableKeyPath<ImagePrimitive, Float>] = [\.screenX, \.screenY]
        for field in origins {
            for value in [Float.nan, .infinity, -.infinity, -2, 0.5, 1, Float.greatestFiniteMagnitude] {
                var malformed = image
                malformed[keyPath: field] = value
                XCTAssertNil(pass.currentTargetRegion(for: malformed, parentSize: parentSize))
                XCTAssertTrue(hasPassDefect(defects(pass, malformed)))
            }
        }
        let mappings: [(WritableKeyPath<ImagePrimitive, Float>, Float)] = [
            (\.screenW, 3), (\.screenH, 3),
            (\.uvX, 0.25), (\.uvY, 0.25), (\.uvW, 0.5), (\.uvH, 0.5),
            (\.rotationRadians, 0.25), (\.affineA, 2), (\.affineB, 0.25),
            (\.affineC, 0.25), (\.affineD, 2), (\.screenX, -2), (\.screenY, 0.5), (\.screenX, 1),
        ]
        for (field, value) in mappings {
            var malformed = image
            malformed[keyPath: field] = value
            XCTAssertNil(pass.currentTargetRegion(for: malformed, parentSize: parentSize))
            XCTAssertTrue(hasPassDefect(defects(pass, malformed)))
            var independent = pass
            independent.input = .independent
            XCTAssertTrue(defects(independent, malformed).isEmpty, "Existing independent image mappings remain valid")
        }
        let otherFields: [WritableKeyPath<ImagePrimitive, Float>] = [
            \.screenW, \.screenH, \.uvX, \.uvY, \.uvW, \.uvH,
            \.affineA, \.affineB, \.affineC, \.affineD, \.rotationRadians,
        ]
        for field in otherFields {
            var malformed = image
            malformed[keyPath: field] = .nan
            XCTAssertNil(pass.currentTargetRegion(for: malformed, parentSize: parentSize))
            XCTAssertTrue(hasPassDefect(defects(pass, malformed)))
        }

        for position in [Float(8), 6] {
            var outside = image
            outside.screenX = position
            // The x=6 consumer is contained at width 8, but not at width 7.
            let actualParent = IntSize(width: position == 6 ? 7 : 8, height: 8)
            XCTAssertTrue(defects(pass, outside).isEmpty, "Structural validation does not invent a target extent")
            XCTAssertNil(pass.currentTargetRegion(for: outside, parentSize: actualParent))
        }
        for invalidParent in [
            IntSize(width: 0, height: 8), IntSize(width: 8, height: 0),
            IntSize(width: -1, height: 8), IntSize(width: 8, height: -1),
            IntSize(width: Int32(GPUISceneLimits.maxSurfaceDimension + 1), height: 8),
            IntSize(width: 8, height: Int32(GPUISceneLimits.maxSurfaceDimension + 1)),
        ] {
            XCTAssertNil(pass.currentTargetRegion(for: image, parentSize: invalidParent))
        }
        var wrongID = image
        wrongID.textureID = 8
        XCTAssertNil(pass.currentTargetRegion(for: wrongID, parentSize: parentSize))
        var negativeID = pass
        negativeID.textureID = -1
        var negativeConsumer = image
        negativeConsumer.textureID = -1
        XCTAssertTrue(hasPassDefect(defects(negativeID, negativeConsumer)))

        var oddExtent = pass
        oddExtent.size = IntSize(width: 3, height: 3)
        var oddImage = image
        oddImage.screenW = 3
        oddImage.screenH = 3
        XCTAssertTrue(defects(oddExtent, oddImage).isEmpty)
        XCTAssertEqual(
            oddExtent.currentTargetRegion(for: oddImage, parentSize: parentSize),
            SubTextureRegion(originX: 2, originY: 2, width: 3, height: 3, textureWidth: 8, textureHeight: 8))
        let originImage = ImagePrimitive(screenW: 2, screenH: 2, textureID: 7)
        XCTAssertNotNil(pass.currentTargetRegion(for: originImage, parentSize: IntSize(width: 3, height: 3)))

        for clear in [Color.black, Color(red: 1, green: 0, blue: 0, alpha: 0)] {
            var altered = pass
            altered.scene.clearColor = clear
            XCTAssertTrue(hasPassDefect(defects(altered, image)))
            XCTAssertNil(altered.currentTargetRegion(for: image, parentSize: parentSize))
            altered.input = .independent
            XCTAssertTrue(defects(altered, image).isEmpty)
        }
        var filtered = pass
        filtered.colorEffects = [.brightness(0)]
        XCTAssertTrue(hasPassDefect(defects(filtered, image)), "Even identity post-filters are outside this contract")
        XCTAssertNil(filtered.currentTargetRegion(for: image, parentSize: parentSize))
        filtered.input = .independent
        XCTAssertTrue(defects(filtered, image).isEmpty)

        for invalidSize in [
            IntSize(width: 0, height: 2), IntSize(width: -1, height: 2),
            IntSize(width: 2, height: 0), IntSize(width: 2, height: -1),
            IntSize(width: 2049, height: 2048),
            IntSize(width: Int32(GPUISceneLimits.maxSurfaceDimension + 1), height: 1),
            IntSize(width: .max, height: .max),
        ] {
            var invalid = pass
            invalid.size = invalidSize
            var consumer = originImage
            consumer.screenW = Float(invalidSize.width)
            consumer.screenH = Float(invalidSize.height)
            XCTAssertFalse(invalid.hasValidExtent)
            XCTAssertNil(invalid.currentTargetRegion(for: consumer, parentSize: parentSize))
            XCTAssertTrue(defects(invalid, consumer).contains { $0.description.contains("extent") })
            invalid.input = .independent
            XCTAssertFalse(defects(invalid, consumer).isEmpty)
        }

        func wrap(_ child: GPUIScene) -> GPUIScene {
            var parent = GPUIScene(clearColor: .clear)
            let id = parent.registerImageRenderPass(child, size: tiny, input: .currentTarget)
            parent.addImage(ImagePrimitive(screenW: 2, screenH: 2, textureID: id))
            parent.finish()
            return parent
        }
        var nested = GPUIScene(clearColor: .clear)
        for _ in 0..<GPUISceneLimits.maxImageRenderPassDepth { nested = wrap(nested) }
        XCTAssertTrue(nested.validate().isEmpty)
        XCTAssertTrue(wrap(nested).validate().contains { $0.description.contains("nesting exceeds 32 passes") })

        func declared(_ count: Int, size: IntSize) -> GPUIScene {
            var scene = GPUIScene(clearColor: .clear)
            for _ in 0..<count {
                let id = scene.registerImageRenderPass(GPUIScene(clearColor: .clear), size: size, input: .currentTarget)
                scene.addImage(ImagePrimitive(screenW: Float(size.width), screenH: Float(size.height), textureID: id))
            }
            scene.finish()
            return scene
        }
        XCTAssertTrue(declared(GPUISceneLimits.maxImageRenderPassCount, size: tiny).validate().isEmpty)
        XCTAssertTrue(
            declared(GPUISceneLimits.maxImageRenderPassCount + 1, size: tiny).validate().contains {
                $0.description.contains("image-pass count exceeds 1024")
            })
        let largest = IntSize(width: 2048, height: 2048)
        XCTAssertTrue(declared(4, size: largest).validate().isEmpty)
        XCTAssertTrue(
            declared(5, size: largest).validate().contains { $0.description.contains("cumulative source pixels") })

        var pixelBudget = GPUISceneImageRenderPassBudget(maxPasses: 2, maxPixels: 4)
        XCTAssertFalse(pixelBudget.consume(size: IntSize(width: .max, height: .max)))
        XCTAssertEqual(pixelBudget.remainingPasses, 2)
        XCTAssertEqual(pixelBudget.remainingPixels, 4)
        XCTAssertTrue(pixelBudget.consume(size: tiny))
        XCTAssertFalse(pixelBudget.consume(size: tiny))
        XCTAssertEqual(pixelBudget.remainingPasses, 1)
        XCTAssertEqual(pixelBudget.remainingPixels, 0)
        var countBudget = GPUISceneImageRenderPassBudget(maxPasses: 1, maxPixels: 8)
        XCTAssertTrue(countBudget.consume(size: tiny))
        XCTAssertFalse(countBudget.consume(size: tiny))
        XCTAssertEqual(countBudget.remainingPasses, 0)
        XCTAssertEqual(countBudget.remainingPixels, 4)

        // Independent images still pay once when the CPU reuses one resolved
        // source. No limit was raised to admit the new per-occurrence path.
        var independent = GPUIScene(clearColor: .clear)
        let independentID = independent.registerImageRenderPass(
            GPUIScene(clearColor: Color(red: 0, green: 0, blue: 1, alpha: 1)), size: tiny)
        independent.addImage(ImagePrimitive(screenW: 2, screenH: 2, textureID: independentID))
        independent.addImage(ImagePrimitive(screenX: 2, screenW: 2, screenH: 2, textureID: independentID))
        independent.finish()
        let cached = GPUIRawSceneRasterizer.rasterize(
            independent, size: IntSize(width: 4, height: 2),
            imageRenderPassBudget: GPUISceneImageRenderPassBudget(maxPasses: 1, maxPixels: 4))
        assertPremultiplied(cached, x: 0, y: 0, red: 0, green: 0, blue: 1, alpha: 1, accuracy: 0)
        assertPremultiplied(cached, x: 2, y: 0, red: 0, green: 0, blue: 1, alpha: 1, accuracy: 0)
    }

    // C12: Promotion releases old baked pixels; removing material restores reuse.
    func testMaterialFreeBitmapCachingAndPromotionLifetimeStaySeparate() async throws {
        for kind in [GroupKind.compositing, .drawing] {
            let fixture = stripeFixture(kind: kind, tint: blueTint, radius: 0)
            let first = paint(fixture.root)
            let firstPixels = raster(first)
            let cached = try XCTUnwrap(fixture.group.cachedCompositingGroupBitmap)
            XCTAssertEqual(first.paintMetrics.compositingGroupsRasterized, 1)
            XCTAssertTrue(first.imageRenderPasses.isEmpty)
            XCTAssertNil(
                fixture.group.cachedCompositingGroupAtlasGeneration, "Pure-color bitmaps have no atlas dependency")
            XCTAssertGreaterThan(maxNeighbourDelta(firstPixels, rows: 40..<60, columns: 40..<60), 100)
            assertPremultiplied(firstPixels, x: 50, y: 43, red: 0, green: 0, blue: 0.4, alpha: 1)
            assertPremultiplied(firstPixels, x: 50, y: 41, red: 0.6, green: 0.6, blue: 1, alpha: 1)

            let reused = paint(fixture.root)
            XCTAssertEqual(reused.paintMetrics.compositingGroupsRasterized, 0)
            XCTAssertEqual(reused.paintMetrics.compositingGroupsReused, 1)
            XCTAssertEqual(fixture.group.cachedCompositingGroupBitmap, cached)
            XCTAssertEqual(raster(reused), firstPixels)

            // Deliberately stale metadata exercises the existing generation-key
            // rejection. This is not a real atlas recycle or glyph-UV test.
            fixture.group.cachedCompositingGroupAtlasGeneration = NativeGlyphAtlas.shared.atlasGeneration &+ 1
            let rejectedStaleStamp = paint(fixture.root)
            XCTAssertEqual(rejectedStaleStamp.paintMetrics.compositingGroupsRasterized, 1)
            XCTAssertEqual(rejectedStaleStamp.paintMetrics.compositingGroupsReused, 0)
            XCTAssertNil(fixture.group.cachedCompositingGroupAtlasGeneration)
            XCTAssertEqual(raster(rejectedStaleStamp), firstPixels)

            fixture.panel.blurRadius = 12
            let promoted = paint(fixture.root)
            XCTAssertEqual(promoted.imageRenderPasses.first?.input, .currentTarget)
            XCTAssertTrue(promoted.imageResources.isEmpty)
            XCTAssertNil(fixture.group.cachedCompositingGroupBitmap)
            XCTAssertNil(fixture.group.cachedCompositingGroupKey)
            XCTAssertNil(fixture.group.cachedCompositingGroupAtlasGeneration)
            XCTAssertEqual(promoted.paintMetrics.compositingGroupsRasterized, 0)
            XCTAssertLessThan(maxNeighbourDelta(raster(promoted), rows: 40..<60, columns: 40..<60), 20)

            fixture.panel.blurRadius = 0
            let restored = paint(fixture.root)
            XCTAssertTrue(restored.imageRenderPasses.isEmpty)
            XCTAssertEqual(restored.paintMetrics.compositingGroupsRasterized, 1)
            XCTAssertNotNil(fixture.group.cachedCompositingGroupBitmap)
            XCTAssertEqual(raster(restored), firstPixels)
            let restoredReuse = paint(fixture.root)
            XCTAssertEqual(restoredReuse.paintMetrics.compositingGroupsReused, 1)
            XCTAssertEqual(raster(restoredReuse), firstPixels)

            let publicSolid = publicStripeScene(kind: kind, solid: true)
            XCTAssertTrue(publicSolid.imageRenderPasses.isEmpty)
            XCTAssertFalse(publicSolid.imageResources.isEmpty)
            XCTAssertTrue(publicSolid.validate().isEmpty)
            XCTAssertFalse(publicSolid.layers.flatMap(\.quads).contains { $0.blurRadius > 0 })
            let solidPixels = raster(publicSolid)
            XCTAssertGreaterThan(maxNeighbourDelta(solidPixels, rows: 40..<60, columns: 40..<60), 100)
            assertPremultiplied(solidPixels, x: 50, y: 43, red: 0, green: 0, blue: 0.4, alpha: 1)
            assertMatchingPixels(solidPixels, raster(publicStripeScene(kind: .inline, solid: true)))
        }
    }

    // C13: Capacity rejection must not bake an incorrect bitmap into replay.
    func testReplayedBackdropSourcesRejectCapacityAndRecoverAfterOutsideSiblingsLeave() async throws {
        let tiny = IntSize(width: 2, height: 2)
        var previous = GPUIScene(clearColor: .clear)
        let textureID = previous.registerImageRenderPass(
            materialSource(size: tiny, tint: blueTint), size: tiny, input: .currentTarget)
        previous.addImage(ImagePrimitive(screenW: 2, screenH: 2, textureID: textureID))
        previous.addImage(ImagePrimitive(screenX: 2, screenW: 2, screenH: 2, textureID: textureID))
        previous.finish()
        var replay = GPUIScene(clearColor: halfRed)
        XCTAssertEqual(replay.replay(0..<previous.paintRecordCount, from: previous), .success)
        replay.finish()
        XCTAssertTrue(replay.validate().isEmpty)
        XCTAssertEqual(replay.imageRenderPasses.count, 1)
        XCTAssertEqual(replay.layers[0].images.map(\.textureID), [textureID, textureID])
        let limited = GPUIRawSceneRasterizer.rasterize(
            replay, size: IntSize(width: 4, height: 2),
            imageRenderPassBudget: GPUISceneImageRenderPassBudget(maxPasses: 1, maxPixels: 8))
        assertPremultiplied(limited, x: 0, y: 0, red: 0.3, green: 0, blue: 0.4, alpha: 0.7)
        assertPremultiplied(limited, x: 2, y: 0, red: 1, green: 0, blue: 1, alpha: 1, accuracy: 0)
        assertPremultiplied(limited, x: 3, y: 0, red: 0, green: 0, blue: 0, alpha: 1, accuracy: 0)
        let admitted = raster(replay, size: IntSize(width: 4, height: 2))
        assertPremultiplied(admitted, x: 2, y: 0, red: 0.3, green: 0, blue: 0.4, alpha: 0.7)

        let hero = stripeFixture(kind: .drawing)
        let wallpaper = Array(hero.root.children.dropLast())
        let visits = PaintCounter()
        let ancestor = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 100), children: [hero.group])
        ancestor.canvasDraw = { _, _ in visits.visits += 1 }
        let pressure = (0..<GPUISceneLimits.maxImageRenderPassCount).map { _ in
            makeGroup(
                .drawing, frame: Rect(x: 0, y: 0, width: 2, height: 2),
                children: [
                    ViewNode(
                        frame: Rect(x: 0, y: 0, width: 2, height: 2), backgroundColor: blueTint, blurRadius: 1)
                ])
        }
        let root = ViewNode(
            frame: Rect(x: 0, y: 0, width: 100, height: 100), children: pressure + wallpaper + [ancestor])
        let textSystem = WindowTextSystem()
        var deferred: [DeferredDrawState] = []
        var replayCount = 0
        var deferredReplayCount = 0
        let full = ScenePainter.paintSnapshot(
            root: root, clearColor: .black, surfaceSize: Size(width: 100, height: 100),
            textSystem: textSystem, previousSnapshot: nil, deferredDraws: &deferred,
            replayCount: &replayCount, deferredReplayCount: &deferredReplayCount)
        XCTAssertEqual(full.scene.imageRenderPasses.count, GPUISceneLimits.maxImageRenderPassCount + 1)
        XCTAssertTrue(full.scene.imageRenderPasses.allSatisfy { $0.input == .currentTarget })
        XCTAssertTrue(full.scene.validate().contains { $0.description.contains("image-pass count exceeds 1024") })
        XCTAssertTrue(
            full.scene.imageResources.isEmpty, "Exhaustion must stay explicit, not cache the old broken output")
        XCTAssertNil(hero.group.cachedCompositingGroupBitmap)
        XCTAssertEqual(visits.visits, 1)
        XCTAssertFalse(ancestor.hasDirtySubtree)
        XCTAssertNotNil(ancestor.cachedScenePaintRange)
        // Do not rasterize the over-capacity retained scene. Its explicit
        // structural rejection is the result under test for this frame.
        root.setChildren(wallpaper + [ancestor])
        XCTAssertTrue(root.children.last === ancestor)
        XCTAssertTrue(ancestor.children.first === hero.group)
        XCTAssertFalse(ancestor.hasDirtySubtree)
        XCTAssertFalse(hero.group.hasDirtySubtree)
        replayCount = 0
        deferredReplayCount = 0
        let recovered = ScenePainter.paintSnapshot(
            root: root, clearColor: .black, surfaceSize: Size(width: 100, height: 100),
            textSystem: textSystem, previousSnapshot: full, deferredDraws: &deferred,
            replayCount: &replayCount, deferredReplayCount: &deferredReplayCount)
        XCTAssertGreaterThan(replayCount, 0)
        XCTAssertEqual(visits.visits, 1, "The same clean ancestor must replay after its outside siblings leave")
        XCTAssertEqual(recovered.scene.imageRenderPasses.count, 1)
        XCTAssertEqual(recovered.scene.imageRenderPasses.first?.input, .currentTarget)
        XCTAssertTrue(recovered.scene.validate().isEmpty)
        XCTAssertTrue(recovered.scene.imageResources.isEmpty)
        XCTAssertNil(hero.group.cachedCompositingGroupBitmap)
        let pixels = raster(recovered.scene)
        XCTAssertLessThan(maxNeighbourDelta(pixels, rows: 40..<60, columns: 40..<60), 20)
        assertMatchingPixels(pixels, raster(paint(stripeFixture(kind: .drawing).root)))
        let center = try XCTUnwrap(pixels.pixelColor(atX: 50, y: 50))
        XCTAssertGreaterThan(center.red, 0.55)
        XCTAssertLessThan(center.red, 0.9)
    }

    // C14: Deferred entry replay must reconsider a crop after only its target changes.
    func testDeferredGroupReplayReevaluatesBackdropAdmissionWhenOnlyTargetSizeChanges() async throws {
        let sides: [Int32] = [64, 64, 100, 100, 64, 64]
        let expectedVisits = [1, 1, 2, 2, 3, 3]
        let expectedRasterized = [1, 0, 0, 0, 1, 0]
        for kind in [GroupKind.compositing, .drawing] {
            var fixture = makeDeferredTargetFixture(kind: kind)
            var previous: ScenePaintSnapshot?
            let rejectedBefore = ScenePainter.rejectedReplayCount
            for (index, side) in sides.enumerated() {
                if let previous {
                    try assertDeferredTargetCacheState(fixture, snapshot: previous, side: sides[index - 1])
                }
                let result = paintDeferredTarget(&fixture, side: side, previous: previous)
                let steady = index > 0 && side == sides[index - 1]
                XCTAssertEqual(result.deferredReplays, steady ? 1 : 0)
                if steady {
                    // The root replay is the sole node visit. Falling through
                    // to the deferred node would count another visit even if
                    // that node immediately replayed its own cached range.
                    XCTAssertEqual(result.ordinaryReplays, 1)
                    XCTAssertEqual(result.snapshot.scene.paintMetrics.nodesVisited, 1)
                } else {
                    XCTAssertGreaterThan(result.snapshot.scene.paintMetrics.nodesVisited, 1)
                }
                XCTAssertEqual(fixture.groupVisits.visits, expectedVisits[index])
                XCTAssertEqual(fixture.materialVisits.visits, expectedVisits[index])
                XCTAssertEqual(
                    result.snapshot.scene.paintMetrics.compositingGroupsRasterized, expectedRasterized[index])
                XCTAssertEqual(result.snapshot.scene.paintMetrics.compositingGroupsReused, 0)
                try assertDeferredTargetCacheState(fixture, snapshot: result.snapshot, side: side)
                let pixels = try assertDeferredTargetPixels(result.snapshot.scene, fixture: fixture, side: side)
                var fresh = makeDeferredTargetFixture(kind: kind)
                let reference = paintDeferredTarget(&fresh, side: side, previous: nil)
                let size = IntSize(width: side, height: side)
                assertMatchingPixels(pixels, raster(reference.snapshot.scene, size: size))
                XCTAssertEqual(ScenePainter.rejectedReplayCount, rejectedBefore)
                previous = result.snapshot
            }
        }
    }

    // C15: No previous scene is supplied, so steady fallback reuse is the bitmap cache.
    func testDeferredGroupBitmapReuseReevaluatesBackdropAdmissionWithoutPreviousSnapshot() async throws {
        let sides: [Int32] = [64, 64, 100, 100, 64, 64]
        let expectedMaterialVisits = [1, 1, 2, 3, 4, 4]
        let expectedRasterized = [1, 0, 0, 0, 1, 0]
        let expectedReused = [0, 1, 0, 0, 0, 1]
        for kind in [GroupKind.compositing, .drawing] {
            var fixture = makeDeferredTargetFixture(kind: kind)
            var lastSnapshot: ScenePaintSnapshot?
            let rejectedBefore = ScenePainter.rejectedReplayCount
            for (index, side) in sides.enumerated() {
                if let lastSnapshot {
                    try assertDeferredTargetCacheState(fixture, snapshot: lastSnapshot, side: sides[index - 1])
                }
                let priorBitmap = fixture.group.cachedCompositingGroupBitmap
                let priorBitmapKey = fixture.group.cachedCompositingGroupKey
                let result = paintDeferredTarget(&fixture, side: side, previous: nil)
                XCTAssertEqual(result.ordinaryReplays, 0)
                XCTAssertEqual(result.deferredReplays, 0)
                XCTAssertEqual(fixture.groupVisits.visits, index + 1, "Every group body must be visited")
                XCTAssertEqual(fixture.materialVisits.visits, expectedMaterialVisits[index])
                XCTAssertEqual(
                    result.snapshot.scene.paintMetrics.compositingGroupsRasterized, expectedRasterized[index])
                XCTAssertEqual(
                    result.snapshot.scene.paintMetrics.compositingGroupsReused, expectedReused[index])
                if expectedReused[index] == 1 {
                    XCTAssertNotNil(priorBitmap)
                    XCTAssertNotNil(priorBitmapKey)
                    XCTAssertEqual(fixture.group.cachedCompositingGroupBitmap, priorBitmap)
                    XCTAssertEqual(fixture.group.cachedCompositingGroupKey, priorBitmapKey)
                }
                try assertDeferredTargetCacheState(fixture, snapshot: result.snapshot, side: side)
                let pixels = try assertDeferredTargetPixels(result.snapshot.scene, fixture: fixture, side: side)
                var fresh = makeDeferredTargetFixture(kind: kind)
                let reference = paintDeferredTarget(&fresh, side: side, previous: nil)
                let size = IntSize(width: side, height: side)
                assertMatchingPixels(pixels, raster(reference.snapshot.scene, size: size))
                XCTAssertEqual(ScenePainter.rejectedReplayCount, rejectedBefore)
                // Retain this only to check the real cache state before the
                // next call; it is never passed as previousSnapshot above.
                lastSnapshot = result.snapshot
            }
        }
    }

    // C16: A live node key cannot qualify a deferred range from a different snapshot.
    func testDeferredGroupReplayRejectsAKeyFromAnInterveningPublicPaint() async throws {
        for kind in [GroupKind.compositing, .drawing] {
            var fixture = makeDeferredTargetFixture(kind: kind)
            let rejectedBefore = ScenePainter.rejectedReplayCount

            let first = paintDeferredTarget(&fixture, side: 64, previous: nil)
            XCTAssertEqual(first.ordinaryReplays, 0)
            XCTAssertEqual(first.deferredReplays, 0)
            XCTAssertEqual(fixture.groupVisits.visits, 1)
            XCTAssertEqual(fixture.materialVisits.visits, 1)
            XCTAssertEqual(first.snapshot.scene.paintMetrics.compositingGroupsRasterized, 1)
            XCTAssertEqual(first.snapshot.scene.paintMetrics.compositingGroupsReused, 0)
            try assertDeferredTargetCacheState(fixture, snapshot: first.snapshot, side: 64)
            _ = try assertDeferredTargetPixels(first.snapshot.scene, fixture: fixture, side: 64)
            let entryBefore = try XCTUnwrap(fixture.draws.first)
            let rangeBefore = try XCTUnwrap(entryBefore.cachedScenePaintRange)
            let identityBefore = try XCTUnwrap(entryBefore.cachedSceneSnapshotIdentity)
            XCTAssertFalse(rangeBefore.isEmpty)
            XCTAssertEqual(identityBefore, first.snapshot.identity)

            // This real public paint updates the same clean node's cache using
            // its own deferred array. The retained entry above must still name A.
            // Only inspect B's source records; its pixels are not rasterized here.
            let intervening = ScenePainter.paint(
                root: fixture.group, clearColor: .black,
                surfaceSize: Size(width: 100, height: 100), displayScale: 1)
            XCTAssertTrue(intervening.validate().isEmpty)
            XCTAssertEqual(intervening.imageRenderPasses.count, 1)
            let interveningPass = try XCTUnwrap(intervening.imageRenderPasses.first)
            XCTAssertEqual(interveningPass.input, .currentTarget)
            XCTAssertEqual(interveningPass.size, IntSize(width: 60, height: 60))
            XCTAssertTrue(intervening.imageResources.isEmpty)
            XCTAssertEqual(intervening.paintMetrics.compositingGroupsRasterized, 0)
            XCTAssertEqual(intervening.paintMetrics.compositingGroupsReused, 0)
            XCTAssertEqual(fixture.groupVisits.visits, 2)
            XCTAssertEqual(fixture.materialVisits.visits, 2)
            XCTAssertNil(fixture.group.cachedCompositingGroupBitmap)
            XCTAssertNil(fixture.group.cachedCompositingGroupKey)
            let interveningKey = try XCTUnwrap(fixture.group.cachedSceneKey)
            let interveningIdentity = try XCTUnwrap(fixture.group.cachedSceneSnapshotIdentity)
            XCTAssertEqual(interveningKey.surfaceSize, Size(width: 100, height: 100))
            XCTAssertNotEqual(interveningIdentity, identityBefore)
            XCTAssertEqual(fixture.root.cachedSceneSnapshotIdentity, first.snapshot.identity)
            XCTAssertEqual(fixture.root.cachedSceneKey?.surfaceSize, Size(width: 64, height: 64))
            XCTAssertFalse(fixture.root.hasDirtySubtree)
            XCTAssertFalse(fixture.group.hasDirtySubtree)
            XCTAssertEqual(fixture.root.frame, Rect(x: 0, y: 0, width: 64, height: 64))
            XCTAssertEqual(fixture.group.frame, Rect(x: 20, y: 20, width: 60, height: 60))
            XCTAssertEqual(fixture.group.resolvedFrame, fixture.group.frame)
            XCTAssertTrue(fixture.group.paintsInDeferredPhase)
            XCTAssertEqual(fixture.draws.count, 1)
            let retainedEntry = try XCTUnwrap(fixture.draws.first)
            XCTAssertEqual(retainedEntry.cachedScenePaintRange, rangeBefore)
            XCTAssertEqual(retainedEntry.cachedSceneSnapshotIdentity, identityBefore)
            XCTAssertEqual(retainedEntry.priority, entryBefore.priority)
            XCTAssertEqual(retainedEntry.parentDispatchIndex, entryBefore.parentDispatchIndex)
            XCTAssertFalse(retainedEntry.isDrawnInline)
            XCTAssertNil(retainedEntry.contentMask)
            if case .subtree(let payload) = retainedEntry.payload {
                XCTAssertTrue(payload.node === fixture.group)
                XCTAssertEqual(payload.parentOrigin, .zero)
                XCTAssertNil(payload.inheritedClip)
                XCTAssertEqual(payload.inheritedOpacity, 1)
            } else {
                XCTFail("The public paint must leave the retained deferred subtree entry intact")
            }

            // B's target matches C, but B's key does not describe A's fallback.
            // Repaint instead of borrowing that key to replay A's 64-pixel clip.
            let resumed = paintDeferredTarget(&fixture, side: 100, previous: first.snapshot)
            XCTAssertEqual(resumed.deferredReplays, 0)
            XCTAssertGreaterThan(resumed.snapshot.scene.paintMetrics.nodesVisited, 1)
            XCTAssertEqual(resumed.snapshot.scene.paintMetrics.compositingGroupsRasterized, 0)
            XCTAssertEqual(resumed.snapshot.scene.paintMetrics.compositingGroupsReused, 0)
            XCTAssertEqual(fixture.groupVisits.visits, 3)
            XCTAssertEqual(fixture.materialVisits.visits, 3)
            try assertDeferredTargetCacheState(fixture, snapshot: resumed.snapshot, side: 100)
            let resumedPixels = try assertDeferredTargetPixels(resumed.snapshot.scene, fixture: fixture, side: 100)
            var fresh = makeDeferredTargetFixture(kind: kind)
            let reference = paintDeferredTarget(&fresh, side: 100, previous: nil)
            let referencePixels = raster(reference.snapshot.scene, size: stripeSize)
            assertMatchingPixels(resumedPixels, referencePixels)
            XCTAssertEqual(ScenePainter.rejectedReplayCount, rejectedBefore)

            let steady = paintDeferredTarget(&fixture, side: 100, previous: resumed.snapshot)
            XCTAssertEqual(steady.ordinaryReplays, 1)
            XCTAssertEqual(steady.deferredReplays, 1)
            XCTAssertEqual(steady.snapshot.scene.paintMetrics.nodesVisited, 1)
            XCTAssertEqual(steady.snapshot.scene.paintMetrics.compositingGroupsRasterized, 0)
            XCTAssertEqual(steady.snapshot.scene.paintMetrics.compositingGroupsReused, 0)
            XCTAssertEqual(fixture.groupVisits.visits, 3)
            XCTAssertEqual(fixture.materialVisits.visits, 3)
            try assertDeferredTargetCacheState(fixture, snapshot: steady.snapshot, side: 100)
            let steadyPixels = try assertDeferredTargetPixels(steady.snapshot.scene, fixture: fixture, side: 100)
            assertMatchingPixels(steadyPixels, referencePixels)
            XCTAssertEqual(ScenePainter.rejectedReplayCount, rejectedBefore)
        }
    }

    @MainActor
    private struct DeferredTargetFixture {
        let root: ViewNode
        let group: ViewNode
        let groupVisits: PaintCounter
        let materialVisits: PaintCounter
        let textSystem: WindowTextSystem
        var draws: [DeferredDrawState]
    }

    private func makeDeferredTargetFixture(kind: GroupKind) -> DeferredTargetFixture {
        let groupVisits = PaintCounter()
        let materialVisits = PaintCounter()
        let panel = ViewNode(
            frame: Rect(x: 0, y: 0, width: 60, height: 60),
            backgroundColor: Color(red: 1, green: 1, blue: 1, alpha: 0.35), blurRadius: 12)
        panel.canvasDraw = { _, _ in materialVisits.visits += 1 }
        let group = makeGroup(kind, frame: Rect(x: 20, y: 20, width: 60, height: 60), children: [panel])
        group.canvasDraw = { _, _ in groupVisits.visits += 1 }
        // Assign once before painting. Reassigning even this same value would
        // dirty the fixture and hide the cache invalidation being tested.
        group.paintsInDeferredPhase = true
        let wallpaper = (0..<25).map { stripe in
            ViewNode(
                frame: Rect(x: 0, y: Double(stripe) * 4, width: 100, height: 2),
                backgroundColor: Color(red: 1, green: 1, blue: 1, alpha: 1))
        }
        // The root frame stays 64 points even when the target grows. These
        // unclipped wallpaper children can paint their overflow on that target.
        let root = ViewNode(
            frame: Rect(x: 0, y: 0, width: 64, height: 64), children: wallpaper + [group])
        let draws = [
            DeferredDrawState(
                priority: 0, parentDispatchIndex: 0, contentMask: nil,
                payload: .subtree(
                    DeferredSubtreePayload(
                        node: group, parentOrigin: .zero, inheritedClip: nil,
                        inheritedOpacity: 1, inheritedInverseTransform: nil,
                        inheritedColorEffects: [])))
        ]
        return DeferredTargetFixture(
            root: root, group: group, groupVisits: groupVisits, materialVisits: materialVisits,
            textSystem: WindowTextSystem(), draws: draws)
    }

    private func paintDeferredTarget(
        _ fixture: inout DeferredTargetFixture, side: Int32, previous: ScenePaintSnapshot?
    ) -> (snapshot: ScenePaintSnapshot, ordinaryReplays: Int, deferredReplays: Int) {
        let root = fixture.root
        let textSystem = fixture.textSystem
        var ordinary = 0
        var deferred = 0
        let snapshot = ScenePainter.paintSnapshot(
            root: root, clearColor: .black,
            surfaceSize: Size(width: Double(side), height: Double(side)), displayScale: 1,
            textSystem: textSystem, previousSnapshot: previous,
            deferredDraws: &fixture.draws, replayCount: &ordinary, deferredReplayCount: &deferred)
        return (snapshot, ordinary, deferred)
    }

    private func assertDeferredTargetCacheState(
        _ fixture: DeferredTargetFixture, snapshot: ScenePaintSnapshot, side: Int32,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let extent = Size(width: Double(side), height: Double(side))
        XCTAssertEqual(fixture.root.frame, Rect(x: 0, y: 0, width: 64, height: 64), file: file, line: line)
        XCTAssertEqual(fixture.group.frame, Rect(x: 20, y: 20, width: 60, height: 60), file: file, line: line)
        XCTAssertEqual(fixture.group.resolvedFrame, fixture.group.frame, file: file, line: line)
        XCTAssertTrue(fixture.group.paintsInDeferredPhase, file: file, line: line)
        XCTAssertFalse(fixture.root.hasDirtySubtree, file: file, line: line)
        XCTAssertFalse(fixture.group.hasDirtySubtree, file: file, line: line)
        let rootKey = try XCTUnwrap(fixture.root.cachedSceneKey, file: file, line: line)
        let groupKey = try XCTUnwrap(fixture.group.cachedSceneKey, file: file, line: line)
        XCTAssertEqual(rootKey.surfaceSize, extent, file: file, line: line)
        XCTAssertEqual(groupKey.surfaceSize, extent, file: file, line: line)
        XCTAssertNil(groupKey.contentMask, "The payload has no inherited target clip", file: file, line: line)
        XCTAssertEqual(fixture.root.cachedSceneSnapshotIdentity, snapshot.identity, file: file, line: line)
        XCTAssertEqual(fixture.group.cachedSceneSnapshotIdentity, snapshot.identity, file: file, line: line)
        let rootRange = try XCTUnwrap(fixture.root.cachedScenePaintRange, file: file, line: line)
        let groupRange = try XCTUnwrap(fixture.group.cachedScenePaintRange, file: file, line: line)
        XCTAssertFalse(rootRange.isEmpty, file: file, line: line)
        XCTAssertEqual(groupRange.count, 1, "The deferred group contributes exactly one image", file: file, line: line)
        XCTAssertGreaterThanOrEqual(groupRange.lowerBound, 0, file: file, line: line)
        XCTAssertLessThanOrEqual(groupRange.upperBound, snapshot.scene.paintRecordCount, file: file, line: line)
        XCTAssertEqual(fixture.draws.count, 1, file: file, line: line)
        let entry = try XCTUnwrap(fixture.draws.first, file: file, line: line)
        XCTAssertFalse(entry.isDrawnInline, file: file, line: line)
        XCTAssertNil(entry.contentMask, file: file, line: line)
        XCTAssertEqual(entry.cachedSceneSnapshotIdentity, snapshot.identity, file: file, line: line)
        XCTAssertEqual(entry.cachedScenePaintRange, groupRange, file: file, line: line)
        if case .subtree(let payload) = entry.payload {
            XCTAssertTrue(payload.node === fixture.group, file: file, line: line)
            XCTAssertEqual(payload.parentOrigin, .zero, file: file, line: line)
            XCTAssertNil(payload.inheritedClip, file: file, line: line)
            XCTAssertEqual(payload.inheritedOpacity, 1, file: file, line: line)
        } else {
            XCTFail("The same retained deferred subtree entry must survive every target change", file: file, line: line)
        }
    }

    private func assertDeferredTargetPixels(
        _ scene: GPUIScene, fixture: DeferredTargetFixture, side: Int32,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> BitmapSurface {
        XCTAssertTrue(scene.validate().isEmpty, file: file, line: line)
        let images = scene.layers.flatMap(\.images)
        XCTAssertEqual(images.count, 1, file: file, line: line)
        let image = try XCTUnwrap(images.first, file: file, line: line)
        XCTAssertEqual(image.screenX, 20, file: file, line: line)
        XCTAssertEqual(image.screenY, 20, file: file, line: line)
        XCTAssertEqual(image.screenW, 60, file: file, line: line)
        XCTAssertEqual(image.screenH, 60, file: file, line: line)
        XCTAssertEqual(image.clipWidth, Float(side), file: file, line: line)
        XCTAssertEqual(image.clipHeight, Float(side), file: file, line: line)
        let size = IntSize(width: side, height: side)
        let pixels = raster(scene, size: size)
        let contrast = maxNeighbourDelta(pixels, rows: 40..<60, columns: 40..<60)
        if side == 64 {
            XCTAssertTrue(scene.imageRenderPasses.isEmpty, file: file, line: line)
            XCTAssertEqual(scene.imageResources.count, 1, file: file, line: line)
            let bitmap = try XCTUnwrap(fixture.group.cachedCompositingGroupBitmap, file: file, line: line)
            let bitmapKey = try XCTUnwrap(fixture.group.cachedCompositingGroupKey, file: file, line: line)
            XCTAssertEqual(bitmap.width, 60, file: file, line: line)
            XCTAssertEqual(bitmap.height, 60, file: file, line: line)
            XCTAssertEqual(bitmapKey.surfaceSize, Size(width: 64, height: 64), file: file, line: line)
            XCTAssertEqual(scene.imageResources.first?.bitmap, bitmap, file: file, line: line)
            XCTAssertGreaterThan(
                contrast, 100, "The off-surface crop keeps the existing fallback", file: file, line: line)
            assertPremultiplied(
                pixels, x: 50, y: 50, red: 0.35, green: 0.35, blue: 0.35, alpha: 1, file: file, line: line)
            assertPremultiplied(
                pixels, x: 50, y: 49, red: 1, green: 1, blue: 1, alpha: 1, accuracy: 0, file: file, line: line)
        } else {
            XCTAssertEqual(side, 100, file: file, line: line)
            XCTAssertTrue(scene.imageResources.isEmpty, file: file, line: line)
            XCTAssertEqual(scene.imageRenderPasses.count, 1, file: file, line: line)
            let pass = try XCTUnwrap(scene.imageRenderPasses.first, file: file, line: line)
            XCTAssertEqual(pass.input, .currentTarget, file: file, line: line)
            XCTAssertEqual(pass.size, IntSize(width: 60, height: 60), file: file, line: line)
            XCTAssertEqual(pass.textureID, image.textureID, file: file, line: line)
            let region = try XCTUnwrap(pass.currentTargetRegion(for: image, parentSize: size), file: file, line: line)
            XCTAssertEqual(region.originX, 20, file: file, line: line)
            XCTAssertEqual(region.originY, 20, file: file, line: line)
            XCTAssertEqual(region.width, 60, file: file, line: line)
            XCTAssertEqual(region.height, 60, file: file, line: line)
            XCTAssertNil(fixture.group.cachedCompositingGroupBitmap, file: file, line: line)
            XCTAssertNil(fixture.group.cachedCompositingGroupKey, file: file, line: line)
            XCTAssertLessThan(contrast, 20, "The now-contained material must blur its backdrop", file: file, line: line)
            for x in [50, 70] {
                // x=70 also catches a stale 64-pixel image clip after growing.
                let color = try XCTUnwrap(pixels.pixelColor(atX: x, y: 50), file: file, line: line)
                XCTAssertGreaterThan(color.red, 0.55, file: file, line: line)
                XCTAssertLessThan(color.red, 0.9, file: file, line: line)
                XCTAssertEqual(color.alpha, 1, accuracy: 0.01, file: file, line: line)
            }
        }
        assertPremultiplied(
            pixels, x: 0, y: 0, red: 1, green: 1, blue: 1, alpha: 1, accuracy: 0, file: file, line: line)
        assertPremultiplied(
            pixels, x: 0, y: 3, red: 0, green: 0, blue: 0, alpha: 1, accuracy: 0, file: file, line: line)
        return pixels
    }

    private func stripeFixture(
        kind: GroupKind, tint: Color = Color(red: 1, green: 1, blue: 1, alpha: 0.35), radius: Double = 12
    ) -> (root: ViewNode, group: ViewNode, panel: ViewNode) {
        var children: [ViewNode] = []
        for stripe in 0..<25 {
            children.append(
                ViewNode(
                    frame: Rect(x: 0, y: Double(stripe) * 4, width: 100, height: 2),
                    backgroundColor: Color(red: 1, green: 1, blue: 1, alpha: 1)))
        }
        let panel = ViewNode(
            frame: Rect(x: 20, y: 20, width: 60, height: 60), backgroundColor: tint, blurRadius: radius)
        let group = makeGroup(kind, frame: Rect(x: 0, y: 0, width: 100, height: 100), children: [panel])
        children.append(group)
        let root = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 100), children: children)
        return (root, group, panel)
    }

    private func makeGroup(_ kind: GroupKind, frame: Rect, children: [ViewNode]) -> ViewNode {
        let group = ViewNode(frame: frame, children: children)
        switch kind {
        case .inline: break
        case .compositing: group.isCompositingGroup = true
        case .drawing: group.drawingGroup = RetainedDrawingGroup()
        }
        return group
    }

    private func publicStripeScene(kind: GroupKind, solid: Bool = false, displayScale: Double = 1) -> GPUIScene {
        let panel: AnyView
        if solid {
            panel = AnyView(Color.clear.frame(width: 60, height: 60).background(blueTint))
        } else {
            panel = AnyView(Color.clear.frame(width: 60, height: 60).background(Material.regular))
        }
        // The modifier isolates children, so the 100-point container owns the
        // panel and the wallpaper remains a sibling outside that container.
        let container = ZStack { panel }.frame(width: 100, height: 100)
        let isolated: AnyView
        switch kind {
        case .inline: isolated = AnyView(container)
        case .compositing: isolated = AnyView(container.compositingGroup())
        case .drawing: isolated = AnyView(container.drawingGroup())
        }
        let view = ZStack(alignment: .topLeading) {
            ForEach(0..<25) { stripe in
                Color.white.frame(width: 100, height: 2).offset(y: Double(stripe) * 4)
            }
            isolated
        }
        .frame(width: 100, height: 100)
        // The snapshotter passes size to the retained root in logical points;
        // the caller rasterizes the resulting scene at 100 * displayScale.
        return WinSwiftUIRendererSnapshotter.snapshot(
            of: view, size: stripeSize, displayScale: displayScale, colorScheme: .light, clearColor: .black
        ).scene
    }

    private func paint(
        _ root: ViewNode, size: IntSize = IntSize(width: 100, height: 100),
        displayScale: Double = 1, clearColor: Color = .black
    ) -> GPUIScene {
        ScenePainter.paint(
            root: root, clearColor: clearColor,
            surfaceSize: Size(width: Double(size.width) / displayScale, height: Double(size.height) / displayScale),
            displayScale: displayScale)
    }

    private func raster(_ scene: GPUIScene, size: IntSize = IntSize(width: 100, height: 100)) -> BitmapSurface {
        GPUIRawSceneRasterizer.rasterize(scene, size: size)
    }

    private func quad(_ frame: Rect, color: Color, radius: Float = 0) -> QuadPrimitive {
        QuadPrimitive(
            x: Float(frame.origin.x), y: Float(frame.origin.y), width: Float(frame.width), height: Float(frame.height),
            startR: color.red, startG: color.green, startB: color.blue, startA: color.alpha,
            endR: color.red, endG: color.green, endB: color.blue, endA: color.alpha, blurRadius: radius)
    }

    private func materialSource(size: IntSize, frame: Rect? = nil, tint: Color, radius: Float = 4) -> GPUIScene {
        var source = GPUIScene(clearColor: .clear)
        source.addQuad(
            quad(
                frame ?? Rect(x: 0, y: 0, width: Double(size.width), height: Double(size.height)),
                color: tint, radius: radius))
        source.finish()
        return source
    }

    private func stripeScene(size: IntSize) -> GPUIScene {
        var scene = GPUIScene(clearColor: .black)
        for y in stride(from: 0, to: Int(size.height), by: 4) {
            scene.addQuad(quad(Rect(x: 0, y: Double(y), width: Double(size.width), height: 2), color: .white))
        }
        scene.finish()
        return scene
    }

    private final class PaintCounter {
        var visits = 0
    }

    private func motionFixture(wrappedInCleanAncestor: Bool, blockX: Double)
        -> (
            runtime: RetainedViewRuntime, wallpaper: ViewNode, group: ViewNode,
            ancestor: ViewNode?, visits: PaintCounter
        )
    {
        let wallpaper = ViewNode(
            frame: Rect(x: 0, y: 0, width: 100, height: 100),
            backgroundColor: Color(red: 0, green: 0, blue: 1, alpha: 1))
        setMotionBackdrop(wallpaper, blockX: blockX)
        let panel = ViewNode(
            frame: Rect(x: 20, y: 20, width: 60, height: 60),
            backgroundColor: Color(red: 1, green: 1, blue: 1, alpha: 0.35), blurRadius: 12)
        let group = makeGroup(.drawing, frame: Rect(x: 0, y: 0, width: 100, height: 100), children: [panel])
        let visits = PaintCounter()
        let ancestor: ViewNode?
        let visible: ViewNode
        if wrappedInCleanAncestor {
            let wrapper = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 100), children: [group])
            wrapper.canvasDraw = { _, _ in visits.visits += 1 }
            ancestor = wrapper
            visible = wrapper
        } else {
            ancestor = nil
            visible = group
        }
        let root = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 100), children: [wallpaper, visible])
        let runtime = RetainedViewRuntime(clearColor: .black, root: root)
        runtime.setRootSize(stripeSize)
        return (runtime, wallpaper, group, ancestor, visits)
    }

    private func setMotionBackdrop(_ node: ViewNode, blockX: Double) {
        let block = rectanglePath(Rect(x: blockX, y: 0, width: 60, height: 100))
        let stripes = (0..<25).map { rectanglePath(Rect(x: 0, y: Double($0) * 4, width: 100, height: 2)) }
        node.canvasDraw = { context, _ in
            context.fill(block, with: .color(Color(red: 1, green: 0, blue: 0, alpha: 1)))
            for stripe in stripes { context.fill(stripe, with: .color(.white)) }
        }
    }

    private func rectanglePath(_ rect: Rect) -> SwiftWindowsCore.Path {
        var path = SwiftWindowsCore.Path()
        path.moveTo(Point(x: rect.minX, y: rect.minY))
        path.lineTo(Point(x: rect.maxX, y: rect.minY))
        path.lineTo(Point(x: rect.maxX, y: rect.maxY))
        path.lineTo(Point(x: rect.minX, y: rect.maxY))
        path.close()
        return path
    }

    private func assertExternalBackdropMotion(
        wrappedInCleanAncestor: Bool, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let positions = [-80.0, 20.0, 100.0]
        let fixture = motionFixture(wrappedInCleanAncestor: wrappedInCleanAncestor, blockX: positions[0])
        var frames: [BitmapSurface] = []
        for (frameIndex, position) in positions.enumerated() {
            if frameIndex > 0 {
                XCTAssertFalse(fixture.group.hasDirtySubtree, file: file, line: line)
                XCTAssertNotNil(fixture.group.cachedScenePaintRange, file: file, line: line)
                if let ancestor = fixture.ancestor {
                    XCTAssertFalse(ancestor.hasDirtySubtree, file: file, line: line)
                    XCTAssertNotNil(ancestor.cachedScenePaintRange, file: file, line: line)
                }
                setMotionBackdrop(fixture.wallpaper, blockX: position)
                XCTAssertFalse(fixture.group.hasDirtySubtree, "Only an outside sibling changed", file: file, line: line)
                if let ancestor = fixture.ancestor {
                    XCTAssertFalse(ancestor.hasDirtySubtree, file: file, line: line)
                }
            }
            let scene = fixture.runtime.renderScene()
            XCTAssertTrue(scene.validate().isEmpty, file: file, line: line)
            XCTAssertEqual(scene.imageRenderPasses.count, 1, file: file, line: line)
            XCTAssertEqual(scene.imageRenderPasses.first?.input, .currentTarget, file: file, line: line)
            XCTAssertTrue(scene.imageResources.isEmpty, file: file, line: line)
            XCTAssertNil(fixture.group.cachedCompositingGroupBitmap, file: file, line: line)
            if frameIndex > 0 {
                // The changed wallpaper is one leaf; the group or its ancestor
                // is the only other replay candidate in this retained tree.
                XCTAssertEqual(fixture.runtime.lastSceneReplayCount, 1, file: file, line: line)
            }
            if wrappedInCleanAncestor {
                XCTAssertEqual(
                    fixture.visits.visits, 1, "Ancestor replay must bypass its canvas callback", file: file, line: line)
            }
            let pixels = raster(scene)
            XCTAssertLessThan(maxNeighbourDelta(pixels, rows: 40..<60, columns: 40..<60), 20, file: file, line: line)
            let center = try XCTUnwrap(pixels.pixelColor(atX: 50, y: 50), file: file, line: line)
            if frameIndex == 1 {
                XCTAssertGreaterThan(
                    center.red - center.blue, 0.2, "The red block is now under the material", file: file, line: line)
            } else {
                XCTAssertGreaterThan(
                    center.blue - center.red, 0.2, "Only blue wallpaper remains under the material",
                    file: file, line: line)
            }
            let fresh = motionFixture(wrappedInCleanAncestor: wrappedInCleanAncestor, blockX: position)
            XCTAssertEqual(
                pixels, raster(fresh.runtime.renderScene()), "Replay must match a fresh paint of this frame",
                file: file, line: line)
            frames.append(pixels)
        }
        XCTAssertNotEqual(frames[0], frames[1], file: file, line: line)
        XCTAssertEqual(frames[0], frames[2], file: file, line: line)
    }

    private func presentationSequence(_ scene: GPUIScene) -> [String] {
        scene.presentationOrder().flatMap { run in run.range.map { "\(run.layerIndex)/\(run.kind)/\($0)" } }
    }

    private func maxNeighbourDelta(_ surface: BitmapSurface, rows: Range<Int>, columns: Range<Int>) -> Int {
        var worst = 0
        let stride = Int(surface.bytesPerRow)
        for y in rows where y >= 1 && y < Int(surface.height) {
            for x in columns where x >= 1 && x < Int(surface.width) {
                let offset = y * stride + x * 4
                guard offset + 3 < surface.pixels.count else { continue }
                for neighbour in [offset - 4, offset - stride] where neighbour >= 0 {
                    for channel in 0..<3 {
                        worst = max(
                            worst,
                            abs(Int(surface.pixels[offset + channel]) - Int(surface.pixels[neighbour + channel])))
                    }
                }
            }
        }
        return worst
    }

    private func assertMatchingPixels(
        _ actual: BitmapSurface, _ expected: BitmapSurface, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(actual.width, expected.width, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, file: file, line: line)
        XCTAssertEqual(comparePixels(actual, expected, tolerance: 2).matchRatio, 1, file: file, line: line)
    }

    private func assertPremultiplied(
        _ bitmap: BitmapSurface, x: Int, y: Int, red: Float, green: Float, blue: Float, alpha: Float,
        accuracy: Float = 0.01, file: StaticString = #filePath, line: UInt = #line
    ) {
        guard x >= 0, y >= 0, x < Int(bitmap.width), y < Int(bitmap.height) else {
            XCTFail("Pixel lies outside the test surface", file: file, line: line)
            return
        }
        let pixels = bitmap.premultipliedAlpha()
        let offset = y * Int(pixels.bytesPerRow) + x * 4
        XCTAssertEqual(Float(pixels.pixels[offset + 2]) / 255, red, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(Float(pixels.pixels[offset + 1]) / 255, green, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(Float(pixels.pixels[offset]) / 255, blue, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(Float(pixels.pixels[offset + 3]) / 255, alpha, accuracy: accuracy, file: file, line: line)
    }

    private func assertSamePixel(
        _ actual: BitmapSurface, _ expected: BitmapSurface, x: Int, y: Int,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let a = y * Int(actual.bytesPerRow) + x * 4
        let b = y * Int(expected.bytesPerRow) + x * 4
        for channel in 0..<4 {
            XCTAssertEqual(actual.pixels[a + channel], expected.pixels[b + channel], file: file, line: line)
        }
    }
}
