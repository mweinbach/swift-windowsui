import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsGraphics
@testable import SwiftWindowsUI

/// Numerical contracts for a material-dependent content blur. Expected colors
/// come from premultiplied composition or fixed scalar Gaussian coefficients,
/// never from a second render of the effect being tested.
@MainActor
final class MaterialContentBlurTests: XCTestCase {
    private let halfBlue = Color(red: 0, green: 0, blue: 1, alpha: 0.5)
    private let halfGreen = Color(red: 0, green: 1, blue: 0, alpha: 0.5)
    private let opaqueGreen = Color(red: 0, green: 1, blue: 0, alpha: 1)
    private let quarterRed = Color(red: 1, green: 0, blue: 0, alpha: 0.25)

    func testMaterialInAnEdgeTouchingContentBlurSmoothsTheHistoricalStripes() async throws {
        let size = IntSize(width: 100, height: 100)
        let stripes = (0..<25).map {
            ViewNode(
                frame: Rect(x: 0, y: Double($0) * 4, width: 100, height: 2), backgroundColor: .white)
        }
        let material = ViewNode(
            frame: Rect(x: 20, y: 20, width: 60, height: 60),
            backgroundColor: Color(red: 1, green: 1, blue: 1, alpha: 0.35), blurRadius: 12)
        let blurred = ViewNode(
            frame: Rect(x: 0, y: 0, width: 100, height: 100), contentBlurRadius: 3, children: [material])
        let root = ViewNode(frame: bounds(size), children: stripes + [blurred])
        let scene = paint(root, size: size, clearColor: .black)
        let pass = try XCTUnwrap(scene.imageRenderPasses.first)
        XCTAssertEqual(pass.input, .isolatedBackdrop)
        XCTAssertEqual(pass.contentBlurRadius, 3)
        XCTAssertEqual(pass.scene.clearColor, .clear)
        XCTAssertTrue(pass.colorEffects.isEmpty)
        XCTAssertTrue(scene.imageResources.isEmpty, "The enclosing stripes must not become a cached bitmap")
        XCTAssertNil(blurred.cachedCompositingGroupBitmap)
        let pixels = raster(scene, size: size)
        XCTAssertLessThan(maxNeighbourDelta(pixels, rows: 40..<60, columns: 40..<60), 20)
        let center = try XCTUnwrap(pixels.pixelColor(atX: 50, y: 50))
        XCTAssertGreaterThan(center.red, 0.55, "A missing panel is not a smoothed backdrop")
        XCTAssertLessThan(center.red, 0.9, "A flat white replacement also has no stripe contrast")
        XCTAssertEqual(center.alpha, 1, accuracy: 1.0 / 255.0)
    }

    func testUntintedMaterialPreservesAUniformHalfAlphaBackdropIncludingItsHalo() async {
        let size = IntSize(width: 64, height: 64)
        let source = materialSource(
            size: size, frame: Rect(x: 16, y: 16, width: 32, height: 32), tint: .clear)
        let scene = isolatedScene(source, size: size, backdrop: halfBlue)
        let pixels = raster(scene, size: size)
        // F = C * D, so Gaussian(F) + (1 - Gaussian(C)) * D = D.
        // Two UNORM steps can round the separately filtered F and C differently;
        // the allowance is two bytes, not an extra source-over contribution.
        for y in 0..<64 {
            for x in 0..<64 {
                assertPremultiplied(pixels, x: x, y: y, red: 0, green: 0, blue: 0.5, alpha: 0.5)
            }
        }
    }

    func testTintAndGroupOpacityUseReplacementCoverageInsteadOfResultAlpha() async {
        let size = IntSize(width: 64, height: 64)
        let source = materialSource(
            size: size, frame: Rect(x: 16, y: 16, width: 32, height: 32), tint: quarterRed)
        for opacity in [Float(0), 0.4, 1] {
            let pixels = raster(
                isolatedScene(source, size: size, backdrop: halfBlue, opacity: opacity), size: size)
            let p = Double(opacity)
            // Red(.25) over blue(.5) is (.25, 0, .375, .625), premultiplied.
            // Interpolating that replacement by p=.4 gives (.1, 0, .45, .55).
            assertPremultiplied(
                pixels, x: 32, y: 32, red: 0.25 * p, green: 0,
                blue: 0.5 - 0.125 * p, alpha: 0.5 + 0.125 * p)
            assertPremultiplied(pixels, x: 4, y: 4, red: 0, green: 0, blue: 0.5, alpha: 0.5)
        }
    }

    func testRepeatedEmptyIsolationsWithNegativeOriginsPreserveEveryNoiseByte() async {
        let size = IntSize(width: 40, height: 28)
        let noise = noiseBitmap(size: size)
        var scene = bitmapScene(noise)
        let childSize = IntSize(width: 48, height: 36)
        let textureID = scene.registerImageRenderPass(
            GPUIScene(clearColor: .clear), size: childSize, input: .isolatedBackdrop, contentBlurRadius: 5)
        for _ in 0..<2 {
            scene.addImage(image(textureID, size: childSize, x: -4, y: -4))
        }
        scene.finish()
        let pixels = raster(scene, size: size)
        XCTAssertEqual(pixels.width, noise.width)
        XCTAssertEqual(pixels.height, noise.height)
        XCTAssertEqual(pixels.pixels, noise.pixels, "An empty foreground has zero replacement coverage everywhere")

        // The software target also preserves hidden RGB in a transparent clear
        // color. An empty isolation must not normalize those existing bytes.
        var transparent = GPUIScene(clearColor: Color(red: 1, green: 0, blue: 0.5, alpha: 0))
        let emptyID = transparent.registerImageRenderPass(
            GPUIScene(clearColor: .clear), size: childSize, input: .isolatedBackdrop, contentBlurRadius: 5)
        transparent.addImage(image(emptyID, size: childSize, x: -4, y: -4))
        transparent.finish()
        let hiddenRGB = raster(transparent, size: IntSize(width: 5, height: 3))
        XCTAssertEqual(hiddenRGB.pixels, Data((0..<15).flatMap { _ -> [UInt8] in [128, 0, 255, 0] }))
    }

    func testMaterialBlurDoesNotSmearNoiseOutsideItsContentSupport() async {
        let size = IntSize(width: 48, height: 48)
        let noise = noiseBitmap(size: size)
        var scene = bitmapScene(noise)
        let source = materialSource(
            size: size, frame: Rect(x: 16, y: 16, width: 16, height: 16), tint: quarterRed)
        let textureID = scene.registerImageRenderPass(
            source, size: size, input: .isolatedBackdrop, contentBlurRadius: 2)
        scene.addImage(image(textureID, size: size))
        scene.finish()
        let pixels = raster(scene, size: size)
        // The material's own bounds plus radius 2 and one antialiasing pixel
        // cannot contribute here, even though the image occupies all 48x48.
        for y in 0..<48 {
            for x in 0..<48 where x < 13 || x >= 35 || y < 13 || y >= 35 {
                assertSamePixel(pixels, noise, x: x, y: y)
            }
        }
        XCTAssertNotEqual(pixels.pixels, noise.pixels, "The material must still paint inside its support")
    }

    func testRoundedOutputClipScalesFilteredReplacementCoverage() async {
        let size = IntSize(width: 48, height: 48)
        var scene = GPUIScene(clearColor: halfBlue)
        let textureID = scene.registerImageRenderPass(
            materialSource(size: size, tint: quarterRed), size: size,
            input: .isolatedBackdrop, contentBlurRadius: 3)
        scene.addImage(
            ImagePrimitive(
                screenW: 48, screenH: 48,
                clipX: 8.5, clipY: 8, clipWidth: 32, clipHeight: 32, clipCornerRadius: 8,
                textureID: textureID))
        scene.finish()
        let pixels = raster(scene, size: size)
        assertPremultiplied(pixels, x: 24, y: 24, red: 0.25, green: 0, blue: 0.375, alpha: 0.625)
        // The pixel center lies on the straight left edge, so clip coverage is
        // exactly one half. The child result's alpha is not that coverage.
        assertPremultiplied(pixels, x: 8, y: 24, red: 0.125, green: 0, blue: 0.4375, alpha: 0.5625)
        assertPremultiplied(pixels, x: 8, y: 8, red: 0, green: 0, blue: 0.5, alpha: 0.5)
        assertPremultiplied(pixels, x: 44, y: 24, red: 0, green: 0, blue: 0.5, alpha: 0.5)
    }

    func testContentHaloFiltersForegroundAndCoverageWithTheSameGaussian() async {
        let size = IntSize(width: 64, height: 64)
        let source = materialSource(
            size: size, frame: Rect(x: 20, y: 20, width: 24, height: 24), tint: quarterRed, radius: 2)
        let pixels = raster(isolatedScene(source, size: size, radius: 2, backdrop: halfBlue), size: size)
        // Radius 2 has sigma 1. These five coefficients are a scalar analytical
        // oracle, independent of gaussianBlurKernel and PremultipliedImageBlur.
        let tail = exp(-2.0)
        let near = exp(-0.5)
        let normalization = 1 + 2 * near + 2 * tail
        let coverages = [
            0.0, tail / normalization, (near + tail) / normalization,
            (1 + near + tail) / normalization, 1 - tail / normalization, 1.0,
        ]
        let backdrop = 128.0 / 255.0
        for (offset, coverage) in coverages.enumerated() {
            // At this flat vertical edge the horizontal pass is the only
            // changing pass. The vertical pass sees identical byte values.
            // Quantize each channel independently, as required by UNORM targets:
            // the unblurred F bytes are (64, 0, 96, 160), while C is 255.
            let c = (255 * coverage).rounded() / 255
            let red = (64 * coverage).rounded() / 255
            let blue = (96 * coverage).rounded() / 255 + (1 - c) * backdrop
            let alpha = (160 * coverage).rounded() / 255 + (1 - c) * backdrop
            assertPremultiplied(
                pixels, x: 17 + offset, y: 32, red: red, green: 0, blue: blue, alpha: alpha)
        }
    }

    func testNestedPlainAndBlurredGroupsDoNotImportTheirEmptyBoundingRectangles() async {
        let size = IntSize(width: 64, height: 64)
        let childSize = IntSize(width: 48, height: 48)
        let backdrop = noiseBitmap(size: size, halfBlueCenter: true)
        for innerRadius in [Int32(0), 2] {
            let material = materialSource(
                size: childSize, frame: Rect(x: 16, y: 16, width: 16, height: 16), tint: quarterRed)
            var outer = GPUIScene(clearColor: .clear)
            let innerID = outer.registerImageRenderPass(
                material, size: childSize, input: .isolatedBackdrop, contentBlurRadius: innerRadius)
            outer.addImage(image(innerID, size: childSize, x: 8, y: 8))
            outer.finish()
            var scene = bitmapScene(backdrop)
            let outerID = scene.registerImageRenderPass(
                outer, size: size, input: .isolatedBackdrop, contentBlurRadius: 3)
            scene.addImage(image(outerID, size: size))
            scene.finish()
            let pixels = raster(scene, size: size)
            assertPremultiplied(pixels, x: 32, y: 32, red: 0.25, green: 0, blue: 0.375, alpha: 0.625)
            for point in [(12, 12), (12, 32), (52, 32), (52, 52)] {
                assertSamePixel(pixels, backdrop, x: point.0, y: point.1)
            }
        }

        assertOffViewportLocalForegroundCanReturnThroughNestedMaterial()
        assertIndependentAncestorDoesNotExposeTheGrandparentBackdrop()
    }

    func testEachOccurrenceOfAnIsolatedTextureReadsItsCurrentPrefix() async {
        let size = IntSize(width: 128, height: 32)
        let childSize = IntSize(width: 32, height: 32)
        var scene = GPUIScene(clearColor: .clear)
        scene.addQuad(quad(Rect(x: 0, y: 0, width: 64, height: 32), color: halfBlue))
        scene.addQuad(quad(Rect(x: 64, y: 0, width: 64, height: 32), color: halfGreen))
        let textureID = scene.registerImageRenderPass(
            materialSource(size: childSize, tint: quarterRed), size: childSize,
            input: .isolatedBackdrop, contentBlurRadius: 2)
        scene.addImage(image(textureID, size: childSize))
        scene.addImage(image(textureID, size: childSize, x: 64))
        scene.addImage(image(textureID, size: childSize))
        scene.finish()
        let repeated = raster(scene, size: size)
        assertPremultiplied(repeated, x: 16, y: 16, red: 0.4375, green: 0, blue: 0.28125, alpha: 0.71875)
        assertPremultiplied(repeated, x: 80, y: 16, red: 0.25, green: 0.375, blue: 0, alpha: 0.625)
        XCTAssertEqual(scene.imageRenderPasses.count, 1)

        scene.addQuad(quad(Rect(x: 0, y: 0, width: 32, height: 32), color: opaqueGreen))
        scene.addImage(image(textureID, size: childSize))
        scene.finish()
        let afterInterveningDraw = raster(scene, size: size)
        assertPremultiplied(afterInterveningDraw, x: 16, y: 16, red: 0.25, green: 0.75, blue: 0, alpha: 1)
    }

    func testLayerPresentationOrderControlsWhichPixelsTheMaterialCanRead() async {
        let size = IntSize(width: 64, height: 32)
        var scene = GPUIScene(clearColor: .clear)
        let textureID = scene.registerImageRenderPass(
            materialSource(size: size, tint: quarterRed), size: size,
            input: .isolatedBackdrop, contentBlurRadius: 3)
        scene.addImage(image(textureID, size: size), toLayer: 1)
        scene.addQuad(quad(bounds(size), color: halfBlue), toLayer: 0)
        scene.addQuad(quad(Rect(x: 0, y: 0, width: 8, height: 32), color: opaqueGreen), toLayer: 2)
        scene.finish()
        XCTAssertEqual(
            scene.presentationOrder().flatMap { run in run.range.map { "\(run.layerIndex)/\(run.kind)/\($0)" } },
            ["0/quad/0", "1/image/0", "2/quad/0"])
        if case .primitive(let layer, let kind, _)? = scene.paintRecords.first {
            XCTAssertEqual(layer, 1)
            XCTAssertEqual(kind, .image)
        } else {
            XCTFail("The fixture must record the material image before its lower-layer backdrop")
        }
        let pixels = raster(scene, size: size)
        assertPremultiplied(pixels, x: 24, y: 16, red: 0.25, green: 0, blue: 0.375, alpha: 0.625)
        assertPremultiplied(pixels, x: 8, y: 16, red: 0.25, green: 0, blue: 0.375, alpha: 0.625)
        assertPremultiplied(pixels, x: 4, y: 16, red: 0, green: 1, blue: 0, alpha: 1, accuracy: 0)
    }

    func testTranslatedReplayRetainsBlurMetadataAndRebindsThePassNamespace() async throws {
        let size = IntSize(width: 96, height: 32)
        let childSize = IntSize(width: 32, height: 32)
        var original = GPUIScene(clearColor: .clear)
        let originalID = original.registerImageRenderPass(
            materialSource(size: childSize, tint: quarterRed), size: childSize,
            input: .isolatedBackdrop, contentBlurRadius: 3)
        original.addImage(image(originalID, size: childSize))
        original.finish()
        let translated = original.translatedPrimitives(by: Point(x: 32, y: 0))

        var scene = GPUIScene(clearColor: halfBlue)
        scene.addQuad(quad(Rect(x: 32, y: 0, width: 32, height: 32), color: opaqueGreen))
        let occupiedID = scene.registerImageResource(solidBitmap(red: 255, green: 255, blue: 0))
        XCTAssertEqual(occupiedID, originalID, "The fixture must force a texture-ID collision")
        scene.addImage(image(occupiedID, size: IntSize(width: 16, height: 32), x: 80))
        XCTAssertEqual(scene.replay(0..<translated.paintRecordCount, from: translated), .success)
        scene.finish()
        let rebound = try XCTUnwrap(scene.imageRenderPasses.first)
        XCTAssertNotEqual(rebound.textureID, occupiedID)
        XCTAssertEqual(rebound.input, .isolatedBackdrop)
        XCTAssertEqual(rebound.contentBlurRadius, 3)
        XCTAssertEqual(rebound.scene, original.imageRenderPasses[0].scene)
        let consumer = try XCTUnwrap(scene.layers.flatMap(\.images).first { $0.textureID == rebound.textureID })
        XCTAssertEqual(consumer.screenX, 32)
        let pixels = raster(scene, size: size)
        assertPremultiplied(pixels, x: 16, y: 16, red: 0, green: 0, blue: 0.5, alpha: 0.5)
        assertPremultiplied(pixels, x: 48, y: 16, red: 0.25, green: 0.75, blue: 0, alpha: 1)
        assertPremultiplied(pixels, x: 88, y: 16, red: 1, green: 1, blue: 0, alpha: 1, accuracy: 0)
    }

    func testACleanBlurTracksOnlyExternalBackdropChangesWithoutCachingTheirPixels() async throws {
        try assertExternalBackdropChanges(wrappedInAncestor: false)
    }

    func testACleanAncestorsReplayKeepsTheMaterialBackdropLive() async throws {
        try assertExternalBackdropChanges(wrappedInAncestor: true)
    }

    func testTargetResizeReevaluatesAReplayedBlurWithoutDirtyingItsSubtree() async throws {
        let material = ViewNode(
            frame: Rect(x: 8, y: 8, width: 48, height: 48), backgroundColor: quarterRed, blurRadius: 4)
        let blurred = ViewNode(
            frame: Rect(x: 0, y: 0, width: 64, height: 64), contentBlurRadius: 3, children: [material])
        let root = ViewNode(frame: Rect(x: 0, y: 0, width: 80, height: 80), children: [blurred])
        let textSystem = WindowTextSystem()
        var previous: ScenePaintSnapshot?
        var deferred: [DeferredDrawState] = []
        for side in [Int32(32), 80, 32, 80] {
            if previous != nil {
                XCTAssertFalse(blurred.hasDirtySubtree, "Only the consuming target size changes")
            }
            var replayCount = 0
            var deferredReplayCount = 0
            let snapshot = ScenePainter.paintSnapshot(
                root: root, clearColor: halfBlue,
                surfaceSize: Size(width: Double(side), height: Double(side)), displayScale: 1,
                textSystem: textSystem, previousSnapshot: previous, deferredDraws: &deferred,
                replayCount: &replayCount, deferredReplayCount: &deferredReplayCount)
            let pass = try XCTUnwrap(snapshot.scene.imageRenderPasses.first)
            XCTAssertEqual(pass.input, .isolatedBackdrop)
            XCTAssertEqual(pass.contentBlurRadius, 3)
            XCTAssertTrue(snapshot.scene.imageResources.isEmpty)
            XCTAssertNil(blurred.cachedCompositingGroupBitmap)
            let pixels = raster(snapshot.scene, size: IntSize(width: side, height: side))
            assertPremultiplied(pixels, x: 20, y: 20, red: 0.25, green: 0, blue: 0.375, alpha: 0.625)
            if side == 80 {
                assertPremultiplied(pixels, x: 50, y: 20, red: 0.25, green: 0, blue: 0.375, alpha: 0.625)
                assertPremultiplied(pixels, x: 72, y: 20, red: 0, green: 0, blue: 0.5, alpha: 0.5)
            }
            previous = snapshot
        }
    }

    func testNestedBitmapAndGlyphNamespacesSurviveDependentBlurAndReturnToTheParent() async throws {
        let childSize = IntSize(width: 32, height: 32)
        var child = GPUIScene(clearColor: .clear)
        child.bindImageResource(solidBitmap(red: 255, green: 0, blue: 0), for: 0)
        child.glyphAtlas = glyphAtlas(coverage: 64)
        var tiled = image(0, size: IntSize(width: 16, height: 16))
        tiled.sampling = try ImageSamplingPlan.resolve(
            sourceSize: IntSize(width: 2, height: 2), destinationSize: Size(width: 16, height: 16),
            capInsets: .zero, mode: .tile
        ).get()
        child.addImage(tiled)
        child.addGlyph(glyph(x: 16, y: 0, width: 16, height: 16))
        child.addQuad(quad(Rect(x: 0, y: 16, width: 32, height: 16), color: quarterRed, radius: 2))
        child.finish()

        let outerSize = IntSize(width: 64, height: 32)
        var outer = GPUIScene(clearColor: .clear)
        outer.bindImageResource(solidBitmap(red: 0, green: 255, blue: 0), for: 0)
        outer.glyphAtlas = glyphAtlas(coverage: 128)
        outer.addImage(image(0, size: IntSize(width: 12, height: 12)))
        outer.addGlyph(glyph(x: 0, y: 16, width: 12, height: 12))
        let childID = outer.registerImageRenderPass(
            child, size: childSize, input: .isolatedBackdrop, contentBlurRadius: 2)
        outer.addImage(image(childID, size: childSize, x: 16))
        outer.finish()

        let size = IntSize(width: 96, height: 48)
        var scene = GPUIScene(clearColor: .black)
        scene.bindImageResource(solidBitmap(red: 0, green: 0, blue: 255), for: 0)
        scene.glyphAtlas = glyphAtlas(coverage: 255)
        scene.addImage(image(0, size: IntSize(width: 8, height: 8)))
        scene.addGlyph(glyph(x: 0, y: 16, width: 8, height: 8))
        let outerID = scene.registerImageRenderPass(
            outer, size: outerSize, input: .isolatedBackdrop, contentBlurRadius: 2)
        scene.addImage(image(outerID, size: outerSize, x: 16, y: 8))
        scene.addImage(image(0, size: IntSize(width: 8, height: 8), x: 80))
        scene.addGlyph(glyph(x: 88, y: 16, width: 8, height: 8))
        scene.finish()
        let pixels = raster(scene, size: size)
        assertPremultiplied(pixels, x: 4, y: 4, red: 0, green: 0, blue: 1, alpha: 1, accuracy: 0)
        assertPremultiplied(pixels, x: 84, y: 4, red: 0, green: 0, blue: 1, alpha: 1, accuracy: 0)
        assertPremultiplied(pixels, x: 4, y: 20, red: 1, green: 1, blue: 1, alpha: 1, accuracy: 0)
        assertPremultiplied(pixels, x: 92, y: 20, red: 1, green: 1, blue: 1, alpha: 1, accuracy: 0)
        assertPremultiplied(pixels, x: 22, y: 14, red: 0, green: 1, blue: 0, alpha: 1)
        assertPremultiplied(pixels, x: 40, y: 16, red: 1, green: 0, blue: 0, alpha: 1)
        assertPremultiplied(
            pixels, x: 56, y: 16, red: 64.0 / 255, green: 64.0 / 255, blue: 64.0 / 255, alpha: 1)
        assertPremultiplied(
            pixels, x: 22, y: 30, red: 128.0 / 255, green: 128.0 / 255, blue: 128.0 / 255, alpha: 1)
        assertPremultiplied(pixels, x: 40, y: 32, red: 0.25, green: 0, blue: 0, alpha: 1)
    }

    func testMaterialFreeBlurKeepsBitmapReuseAndReleasesItOnBackdropPromotion() async throws {
        let size = IntSize(width: 64, height: 64)
        let child = ViewNode(frame: Rect(x: 16, y: 16, width: 32, height: 32), backgroundColor: quarterRed)
        let blurred = ViewNode(frame: bounds(size), contentBlurRadius: 3, children: [child])
        let first = paint(blurred, size: size, clearColor: halfBlue)
        XCTAssertTrue(first.imageRenderPasses.isEmpty)
        let originalBitmap = try XCTUnwrap(blurred.cachedCompositingGroupBitmap)
        let second = paint(blurred, size: size, clearColor: halfBlue)
        XCTAssertEqual(second.paintMetrics.contentBlurPassesReused, 1)
        XCTAssertEqual(blurred.cachedCompositingGroupBitmap, originalBitmap)

        child.blurRadius = 4
        let promoted = paint(blurred, size: size, clearColor: halfBlue)
        XCTAssertEqual(promoted.imageRenderPasses.first?.input, .isolatedBackdrop)
        XCTAssertTrue(promoted.imageResources.isEmpty)
        XCTAssertNil(blurred.cachedCompositingGroupBitmap)
        XCTAssertEqual(promoted.paintMetrics.contentBlurPassesReused, 0)
        assertPremultiplied(
            raster(promoted, size: size), x: 32, y: 32, red: 0.25, green: 0, blue: 0.375, alpha: 0.625)

        child.blurRadius = 0
        let restored = paint(blurred, size: size, clearColor: halfBlue)
        XCTAssertTrue(restored.imageRenderPasses.isEmpty)
        XCTAssertNotNil(blurred.cachedCompositingGroupBitmap)
        XCTAssertEqual(restored.paintMetrics.contentBlurPassesReused, 0)
        XCTAssertEqual(paint(blurred, size: size, clearColor: halfBlue).paintMetrics.contentBlurPassesReused, 1)
    }

    func testDeferredMaterialStaysInsideBothContentBlursWhenTheSceneReplays() async throws {
        let size = IntSize(width: 80, height: 64)
        let material = ViewNode(
            frame: Rect(x: 24, y: 0, width: 40, height: 48),
            backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1), blurRadius: 1)
        material.paintsInDeferredPhase = true
        let visits = PaintCounter()
        material.canvasDraw = { _, _ in visits.visits += 1 }
        let inner = ViewNode(
            frame: Rect(x: 0, y: 0, width: 64, height: 48), contentBlurRadius: 2, children: [material])
        let outer = ViewNode(
            frame: Rect(x: 8, y: 8, width: 64, height: 48), contentBlurRadius: 2, children: [inner])
        let root = ViewNode(frame: bounds(size), children: [outer])
        var draws = [deferredSubtree(material, parentOrigin: Point(x: 8, y: 8))]
        let textSystem = WindowTextSystem()
        var previous: ScenePaintSnapshot?

        // Two radius-2/sigma-1 Gaussians convolve the material's vertical edge.
        // This fixed scalar coefficient is not obtained by rendering a reference.
        let near = exp(-0.5)
        let tail = exp(-2.0)
        let normalization = 1 + 2 * near + 2 * tail
        let outsideCoverage =
            (near * near + 2 * tail + 2 * near * tail + tail * tail) / (normalization * normalization)
        let backdrop = 128.0 / 255.0
        for frameIndex in 0..<3 {
            var replays = 0
            let snapshot = paintDeferredSnapshot(
                root, size: size, clearColor: halfBlue, draws: &draws, previous: previous,
                textSystem: textSystem, replayCount: &replays)
            XCTAssertEqual(snapshot.scene.imageRenderPasses.count, 1)
            let outerPass = try XCTUnwrap(snapshot.scene.imageRenderPasses.first)
            XCTAssertEqual(outerPass.input, .isolatedBackdrop)
            XCTAssertEqual(outerPass.contentBlurRadius, 2)
            XCTAssertEqual(outerPass.scene.imageRenderPasses.count, 1)
            let innerPass = try XCTUnwrap(outerPass.scene.imageRenderPasses.first)
            XCTAssertEqual(innerPass.input, .isolatedBackdrop)
            XCTAssertEqual(innerPass.contentBlurRadius, 2)
            XCTAssertEqual(innerPass.scene.layers.flatMap(\.quads).filter { $0.blurRadius == 1 }.count, 1)
            XCTAssertFalse(snapshot.scene.layers.flatMap(\.quads).contains { $0.blurRadius > 0 })
            XCTAssertFalse(
                outerPass.scene.layers.flatMap(\.quads).contains { $0.blurRadius > 0 },
                "The outer deferred drain must not flatten the material past its inner blur")
            XCTAssertTrue(draws[0].isDrawnInline)
            XCTAssertNil(draws[0].cachedScenePaintRange)
            XCTAssertNil(draws[0].cachedSceneSnapshotIdentity)
            XCTAssertNil(outer.cachedCompositingGroupBitmap)
            XCTAssertNil(inner.cachedCompositingGroupBitmap)
            XCTAssertEqual(visits.visits, 1, "Replay must not repaint a sharp deferred copy")
            if frameIndex > 0 {
                XCTAssertGreaterThan(replays, 0, "The later frames must actually exercise scene replay")
            }

            let pixels = raster(snapshot.scene, size: size)
            for (x, coverage) in [(30, outsideCoverage), (33, 1 - outsideCoverage)] {
                // The two horizontal UNORM stages and final straight-alpha
                // round trip fit within three bytes. Vertical rows are constant.
                // One blur differs by twenty bytes; a sharp second copy would
                // force the inside probe's red to 1 instead of approximately .867.
                assertPremultiplied(
                    pixels, x: x, y: 32, red: coverage, green: 0, blue: backdrop * (1 - coverage),
                    alpha: coverage + backdrop * (1 - coverage), accuracy: 3.0 / 255.0)
            }
            previous = snapshot
        }
    }

    func testMaterialFreeSiblingGroupsDoNotConsumeTheDependentSourceCount() async throws {
        let size = IntSize(width: 80, height: 80)
        let groups = (0..<1024).map { index in
            let fill = ViewNode(frame: Rect(x: 0, y: 0, width: 2, height: 2), backgroundColor: opaqueGreen)
            let group = ViewNode(
                frame: Rect(x: Double(index % 32) * 2, y: Double(index / 32) * 2, width: 2, height: 2),
                children: [fill])
            group.isCompositingGroup = true
            return group
        }
        let material = ViewNode(
            frame: Rect(x: 68, y: 4, width: 8, height: 8), backgroundColor: quarterRed, blurRadius: 1)
        let outer = ViewNode(frame: bounds(size), contentBlurRadius: 2, children: groups + [material])
        let scene = paint(outer, size: size, clearColor: halfBlue)
        XCTAssertEqual(GPUISceneLimits.maxImageRenderPassCount, 1024, "The source ceiling must not be raised")
        XCTAssertEqual(scene.imageRenderPasses.count, 1)
        let pass = try XCTUnwrap(scene.imageRenderPasses.first)
        XCTAssertEqual(pass.input, .isolatedBackdrop)
        XCTAssertEqual(pass.contentBlurRadius, 2)
        XCTAssertTrue(pass.scene.imageRenderPasses.isEmpty, "Material-free groups remain ordinary bitmap resources")
        let images = pass.scene.layers.flatMap(\.images)
        let bitmapIDs = Set(pass.scene.imageResources.map(\.textureID))
        XCTAssertEqual(images.count, 1024, "All sibling groups must still draw")
        XCTAssertFalse(bitmapIDs.isEmpty)
        XCTAssertTrue(images.allSatisfy { bitmapIDs.contains($0.textureID) })
        // There is only one scene-backed source to reserve. Rejecting this
        // otherwise valid graph charges unrecorded material-free groups as passes.
        let pixels = raster(scene, size: size)
        assertPremultiplied(pixels, x: 32, y: 32, red: 0, green: 1, blue: 0, alpha: 1)
        assertPremultiplied(pixels, x: 72, y: 8, red: 0.25, green: 0, blue: 0.375, alpha: 0.625)
    }

    func testBackdropSelectionUsesTheFloatRadiusThatTheMaterialPrimitiveEmits() async throws {
        let size = IntSize(width: 64, height: 64)
        let stripes = (0..<16).map {
            ViewNode(frame: Rect(x: Double($0) * 4, y: 0, width: 2, height: 64), backgroundColor: .white)
        }
        let material = ViewNode(
            frame: Rect(x: 8, y: 8, width: 48, height: 48), backgroundColor: .clear, blurRadius: 0.99999999)
        let blurred = ViewNode(frame: bounds(size), contentBlurRadius: 2, children: [material])
        let root = ViewNode(frame: bounds(size), children: stripes + [blurred])
        XCTAssertLessThan(material.blurRadius, 1)
        XCTAssertEqual(Float(material.blurRadius), 1, "The primitive executes an integer radius-1 material")
        let scene = paint(root, size: size, clearColor: .black)
        let pass = try XCTUnwrap(scene.imageRenderPasses.first)
        XCTAssertEqual(pass.input, .isolatedBackdrop)
        XCTAssertEqual(pass.contentBlurRadius, 2)
        let quad = try XCTUnwrap(pass.scene.layers.flatMap(\.quads).first { $0.blurRadius > 0 })
        XCTAssertEqual(quad.blurRadius, 1)
        XCTAssertNil(blurred.cachedCompositingGroupBitmap)
        XCTAssertTrue(scene.imageResources.isEmpty)

        // A 2-pixel alternating stripe is a pi/2-frequency eigenvector of each
        // symmetric kernel. Multiplying their two independently derived gains
        // predicts both colors after material radius 1 and content radius 2.
        // Omitting the material stage changes each probe by roughly eight bytes.
        let tail = exp(-2.0)
        let near = exp(-0.5)
        let materialGain = 1 / (1 + 2 * tail)
        let contentGain = (1 - 2 * tail) / (1 + 2 * near + 2 * tail)
        let amplitude = materialGain * contentGain
        let pixels = raster(scene, size: size)
        for (x, sign) in [(32, 1.0), (34, -1.0)] {
            let value = (1 + sign * amplitude) / 2
            assertPremultiplied(pixels, x: x, y: 32, red: value, green: value, blue: value, alpha: 1)
        }
    }

    func testDeferredMaterialBehindOwnOrInheritedColorEffectsKeepsIndependentBlurCaching() async throws {
        let size = IntSize(width: 64, height: 64)
        for effectsOnNode in [true, false] {
            let material = ViewNode(
                frame: Rect(x: 16, y: 16, width: 32, height: 32), backgroundColor: quarterRed, blurRadius: 4)
            material.paintsInDeferredPhase = true
            if effectsOnNode { material.colorEffects = [.brightness(0.125)] }
            let inheritedEffects: [RetainedColorEffect] = effectsOnNode ? [] : [.brightness(0.125)]
            let blurred = ViewNode(frame: bounds(size), contentBlurRadius: 2, children: [material])
            let root = ViewNode(frame: bounds(size), children: [blurred])
            var draws = [deferredSubtree(material, inheritedColorEffects: inheritedEffects)]
            let textSystem = WindowTextSystem()
            var firstBitmap: BitmapSurface?
            for frameIndex in 0..<2 {
                var replays = 0
                // No previous snapshot: frame 2 must prove bitmap-cache reuse,
                // not merely carry a prior image forward through outer replay.
                let snapshot = paintDeferredSnapshot(
                    root, size: size, clearColor: halfBlue, draws: &draws, previous: nil,
                    textSystem: textSystem, replayCount: &replays)
                XCTAssertTrue(
                    snapshot.scene.imageRenderPasses.isEmpty,
                    "An independent color-filter boundary must stop the outer backdrop dependency scan")
                XCTAssertEqual(snapshot.scene.imageResources.count, 1)
                XCTAssertEqual(snapshot.scene.paintMetrics.contentBlurPasses, 1)
                XCTAssertEqual(snapshot.scene.paintMetrics.contentBlurPassesReused, frameIndex)
                XCTAssertTrue(draws[0].isDrawnInline)
                XCTAssertNil(draws[0].cachedScenePaintRange)
                let bitmap = try XCTUnwrap(blurred.cachedCompositingGroupBitmap)
                if let firstBitmap {
                    XCTAssertEqual(bitmap, firstBitmap)
                } else {
                    firstBitmap = bitmap
                }
                // The material sees transparent input within its color filter.
                // Brightening quarter-alpha red gives (1,.125,.125,.25), then
                // source-over on half-blue yields these premultiplied values.
                assertPremultiplied(
                    raster(snapshot.scene, size: size), x: 32, y: 32,
                    red: 0.25, green: 0.03125, blue: 0.40625, alpha: 0.625)
            }
        }
    }

    func testDeferredMaterialPreservesSourceClipsWithoutBakingTheEnclosingViewport() async throws {
        let size = IntSize(width: 64, height: 64)
        func fixture(isDeferred: Bool, originX: Double)
            -> (runtime: RetainedViewRuntime, blurred: ViewNode, material: ViewNode)
        {
            let material = ViewNode(
                frame: Rect(x: -8, y: 0, width: 16, height: 32),
                backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1), blurRadius: 1)
            material.paintsInDeferredPhase = isDeferred
            let blurred = ViewNode(
                frame: Rect(x: originX, y: 16, width: 32, height: 32),
                contentBlurRadius: 2, children: [material])
            blurred.clipsToBounds = true
            let root = ViewNode(frame: bounds(size), children: [blurred])
            root.clipsToBounds = true
            let runtime = RetainedViewRuntime(clearColor: halfBlue, root: root)
            runtime.setRootSize(size)
            return (runtime, blurred, material)
        }

        let near = exp(-0.5)
        let tail = exp(-2.0)
        let normalization = 1 + 2 * near + 2 * tail
        let outsideCoverage = (near + tail) / normalization
        let backdrop = 128.0 / 255.0
        for originX in [16.0, -8.0] {
            let inline = fixture(isDeferred: false, originX: originX)
            let deferred = fixture(isDeferred: true, originX: originX)
            let inlineScene = inline.runtime.renderScene()
            let deferredScene = deferred.runtime.renderScene()
            XCTAssertTrue(inline.runtime.currentPrepaintState.deferredDraws.isEmpty)
            XCTAssertTrue(inline.material.parent === inline.blurred)
            XCTAssertTrue(deferred.material.parent === deferred.blurred)
            let payloads = deferred.runtime.currentPrepaintState.deferredDraws.compactMap {
                draw
                    -> DeferredSubtreePayload? in
                guard case .subtree(let payload) = draw.payload, payload.node === deferred.material else { return nil }
                return payload
            }
            XCTAssertEqual(payloads.count, 1)
            let payload = try XCTUnwrap(payloads.first)
            XCTAssertEqual(payload.parentOrigin, Point(x: originX, y: 16))
            let mergedClip = Rect(x: max(0, originX), y: 16, width: originX < 0 ? 24 : 32, height: 32)
            XCTAssertEqual(payload.inheritedClip?.rect, mergedClip)

            // These are real prepaint payloads, including the off-viewport
            // descendant: deferred candidates are recorded before child culling.
            // The payload's merged clip alone cannot identify which ancestor
            // owns the source clip and which clip belongs on the final image.
            for scene in [inlineScene, deferredScene] {
                XCTAssertEqual(scene.imageRenderPasses.count, 1)
                let pass = try XCTUnwrap(scene.imageRenderPasses.first)
                XCTAssertEqual(pass.input, .isolatedBackdrop)
                XCTAssertEqual(pass.contentBlurRadius, 2)
                XCTAssertEqual(pass.scene.layers.flatMap(\.quads).filter { $0.blurRadius == 1 }.count, 1)
                XCTAssertTrue(scene.imageResources.isEmpty)
            }
            let inlinePixels = raster(inlineScene, size: size)
            let deferredPixels = raster(deferredScene, size: size)
            XCTAssertEqual(
                deferredPixels.pixels, inlinePixels.pixels,
                "Deferring a child must preserve the capture-local clip before the content Gaussian")

            let samples: [(Int, Double)]
            let untouchedX: Int
            if originX > 0 {
                // The material spans [8,24), but the blur root's own source clip
                // admits only [16,24). Red pixels at [8,16) must not enter the
                // Gaussian. Dropping that clip makes the first probe fully red.
                samples = [(16, 1 - outsideCoverage), (17, 1 - tail / normalization), (20, 1)]
                untouchedX = 15
            } else {
                // The own clip admits red at [-8,0), outside the enclosing
                // viewport. Those local pixels must still blur into x0 and x1;
                // preserving the merged [0,24) payload clip would erase them.
                samples = [(0, outsideCoverage), (1, tail / normalization), (2, 0)]
                untouchedX = 26
            }
            for pixels in [inlinePixels, deferredPixels] {
                for (x, coverage) in samples {
                    // The y32 row is constant throughout the radius-2 kernel,
                    // so these are independent one-dimensional step coefficients.
                    assertPremultiplied(
                        pixels, x: x, y: 32, red: coverage, green: 0, blue: backdrop * (1 - coverage),
                        alpha: coverage + backdrop * (1 - coverage))
                }
                assertPremultiplied(
                    pixels, x: untouchedX, y: 32, red: 0, green: 0, blue: backdrop, alpha: backdrop, accuracy: 0)
            }
        }
    }

    func testTransparentMaterialUsesTheEmittedFloatRadiusAtTheExecutionBoundary() async {
        let size = IntSize(width: 32, height: 32)
        let cases: [(radius: Double, expectedRadius: Float?)] = [
            (Double(Float(1).nextDown), nil),
            (0.99999999, 1),
        ]
        for fixture in cases {
            let stripes = (0..<8).map {
                ViewNode(frame: Rect(x: Double($0) * 4, y: 0, width: 2, height: 32), backgroundColor: .white)
            }
            let material = ViewNode(frame: bounds(size), backgroundColor: .clear, blurRadius: fixture.radius)
            let root = ViewNode(frame: bounds(size), children: stripes + [material])
            let scene = paint(root, size: size, clearColor: .black)
            let materialQuads = scene.layers.flatMap(\.quads).filter { $0.blurRadius > 0 }
            XCTAssertEqual(materialQuads.map(\.blurRadius), fixture.expectedRadius.map { [$0] } ?? [])
            XCTAssertTrue(materialQuads.allSatisfy { $0.startA == 0 && $0.endA == 0 })
            XCTAssertTrue(scene.imageResources.isEmpty)
            XCTAssertTrue(scene.imageRenderPasses.isEmpty)

            // A radius that remains below one in Float executes no material.
            // The rounded-up Float executes the radius-1/sigma-.5 kernel even
            // though its authored Double and tint alpha are both below one.
            let gain = fixture.expectedRadius == nil ? 1 : 1 / (1 + 2 * exp(-2.0))
            let pixels = raster(scene, size: size)
            for (x, sign) in [(12, 1.0), (14, -1.0)] {
                let value = (1 + sign * gain) / 2
                assertPremultiplied(pixels, x: x, y: 16, red: value, green: value, blue: value, alpha: 1)
            }
        }
    }

    func testSuppressedContentBlurRootDoesNotAddFallbackInEitherPaintFinishPath() async throws {
        let size = IntSize(width: 32, height: 32)
        for usesCompositingGroup in [false, true] {
            let material = ViewNode(frame: bounds(size), backgroundColor: quarterRed, blurRadius: 1)
            let blurred = ViewNode(frame: bounds(size), contentBlurRadius: 2, children: [material])
            blurred.isCompositingGroup = usesCompositingGroup
            let scene = paint(blurred, size: size, clearColor: halfBlue)
            XCTAssertTrue(scene.validate().isEmpty)
            XCTAssertEqual(scene.imageRenderPasses.count, 1)
            XCTAssertTrue(scene.layers.flatMap(\.quads).isEmpty)
            let contentPass = try XCTUnwrap(scene.imageRenderPasses.first)
            XCTAssertEqual(contentPass.input, .isolatedBackdrop)
            XCTAssertEqual(contentPass.contentBlurRadius, 2)

            let materialScene: GPUIScene
            if usesCompositingGroup {
                XCTAssertTrue(contentPass.scene.layers.flatMap(\.quads).isEmpty)
                XCTAssertEqual(contentPass.scene.imageRenderPasses.count, 1)
                let groupPass = try XCTUnwrap(contentPass.scene.imageRenderPasses.first)
                XCTAssertEqual(groupPass.input, .isolatedBackdrop)
                XCTAssertEqual(groupPass.contentBlurRadius, 0)
                materialScene = groupPass.scene
            } else {
                XCTAssertTrue(contentPass.scene.imageRenderPasses.isEmpty)
                materialScene = contentPass.scene
            }
            XCTAssertEqual(materialScene.layers.flatMap(\.quads).map(\.blurRadius), [1])
            XCTAssertTrue(materialScene.imageRenderPasses.isEmpty)
            XCTAssertNil(blurred.cachedCompositingGroupBitmap)
        }
    }

    func testUnsizedContentBlurStillEmitsItsExistingFallback() async {
        // The radius outset exceeds the existing 16,777,216-pixel bitmap
        // ceiling. This is a scene-only admission test; no large raster runs.
        let size = IntSize(width: 4096, height: 4096)
        let blurred = ViewNode(frame: bounds(size), contentBlurRadius: 2)
        let scene = paint(blurred, size: size, clearColor: halfBlue)
        XCTAssertTrue(scene.validate().isEmpty)
        XCTAssertTrue(scene.imageResources.isEmpty)
        XCTAssertTrue(scene.imageRenderPasses.isEmpty)
        XCTAssertEqual(scene.layers.flatMap(\.quads).map(\.blurRadius), [2])
        XCTAssertNil(blurred.cachedCompositingGroupBitmap)
        XCTAssertFalse(blurred.lastPaintedViaContentBlurIsolation)
    }

    private func deferredSubtree(
        _ node: ViewNode, parentOrigin: Point = .zero, inheritedColorEffects: [RetainedColorEffect] = []
    ) -> DeferredDrawState {
        DeferredDrawState(
            priority: 0, parentDispatchIndex: 0, contentMask: nil,
            payload: .subtree(
                DeferredSubtreePayload(
                    node: node, parentOrigin: parentOrigin, inheritedClip: nil,
                    inheritedOpacity: 1, inheritedInverseTransform: nil,
                    inheritedColorEffects: inheritedColorEffects)))
    }

    private func paintDeferredSnapshot(
        _ root: ViewNode, size: IntSize, clearColor: Color, draws: inout [DeferredDrawState],
        previous: ScenePaintSnapshot?, textSystem: WindowTextSystem, replayCount: inout Int
    ) -> ScenePaintSnapshot {
        var deferredReplays = 0
        return ScenePainter.paintSnapshot(
            root: root, clearColor: clearColor,
            surfaceSize: Size(width: Double(size.width), height: Double(size.height)), displayScale: 1,
            textSystem: textSystem, previousSnapshot: previous, deferredDraws: &draws,
            replayCount: &replayCount, deferredReplayCount: &deferredReplays)
    }

    private final class PaintCounter {
        var visits = 0
    }

    private func assertExternalBackdropChanges(
        wrappedInAncestor: Bool, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let size = IntSize(width: 64, height: 64)
        let wallpaper = ViewNode(frame: bounds(size), backgroundColor: halfBlue)
        let material = ViewNode(
            frame: Rect(x: 16, y: 16, width: 32, height: 32), backgroundColor: quarterRed, blurRadius: 4)
        let blurred = ViewNode(frame: bounds(size), contentBlurRadius: 3, children: [material])
        let counter = PaintCounter()
        let ancestor: ViewNode?
        if wrappedInAncestor {
            let wrapper = ViewNode(frame: bounds(size), children: [blurred])
            wrapper.canvasDraw = { _, _ in counter.visits += 1 }
            ancestor = wrapper
        } else {
            ancestor = nil
        }
        let root = ViewNode(frame: bounds(size), children: [wallpaper, ancestor ?? blurred])
        let runtime = RetainedViewRuntime(clearColor: .clear, root: root)
        runtime.setRootSize(size)
        for index in 0..<3 {
            if index > 0 {
                XCTAssertFalse(blurred.hasDirtySubtree, file: file, line: line)
                wallpaper.backgroundColor = index == 1 ? halfGreen : halfBlue
                XCTAssertFalse(blurred.hasDirtySubtree, "Only the outside sibling changed", file: file, line: line)
                if let ancestor {
                    XCTAssertFalse(ancestor.hasDirtySubtree, file: file, line: line)
                    XCTAssertNotNil(ancestor.cachedScenePaintRange, file: file, line: line)
                }
            }
            let scene = runtime.renderScene()
            let pass = try XCTUnwrap(scene.imageRenderPasses.first, file: file, line: line)
            XCTAssertEqual(pass.input, .isolatedBackdrop, file: file, line: line)
            XCTAssertEqual(pass.contentBlurRadius, 3, file: file, line: line)
            XCTAssertTrue(scene.imageResources.isEmpty, file: file, line: line)
            XCTAssertNil(blurred.cachedCompositingGroupBitmap, file: file, line: line)
            XCTAssertEqual(scene.paintMetrics.contentBlurPassesReused, 0, file: file, line: line)
            if wrappedInAncestor {
                XCTAssertEqual(counter.visits, 1, "A clean ancestor must replay its records", file: file, line: line)
                if index > 0 {
                    XCTAssertEqual(runtime.lastSceneReplayCount, 1, file: file, line: line)
                }
            }
            let pixels = raster(scene, size: size, file: file, line: line)
            assertPremultiplied(
                pixels, x: 32, y: 32, red: 0.25, green: index == 1 ? 0.375 : 0,
                blue: index == 1 ? 0 : 0.375, alpha: 0.625, file: file, line: line)
        }
    }

    private func assertOffViewportLocalForegroundCanReturnThroughNestedMaterial(
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let size = IntSize(width: 32, height: 32)
        let childSize = IntSize(width: 40, height: 40)
        var outer = GPUIScene(clearColor: .clear)
        // At image origin -4, every green pixel is outside the original target.
        outer.addQuad(quad(Rect(x: 0, y: 0, width: 4, height: 40), color: opaqueGreen))
        let innerID = outer.registerImageRenderPass(
            materialSource(size: childSize, tint: .clear, radius: 1), size: childSize,
            input: .isolatedBackdrop, contentBlurRadius: 0)
        outer.addImage(image(innerID, size: childSize))
        outer.finish()
        var scene = GPUIScene(clearColor: halfBlue)
        let outerID = scene.registerImageRenderPass(
            outer, size: childSize, input: .isolatedBackdrop, contentBlurRadius: 2)
        scene.addImage(image(outerID, size: childSize, x: -4, y: -4))
        scene.finish()

        // Convolve the fixed symmetric radius-1/sigma-.5 and radius-2/sigma-1
        // kernels analytically. The first blue-side pixel receives half of the
        // noncentral weight from the green half-plane. Only D is clamped; S
        // includes those earlier local green pixels outside the original copy.
        let tail = exp(-2.0)
        let near = exp(-0.5)
        let normalization = (1 + 2 * tail) * (1 + 2 * near + 2 * tail)
        let centralWeight = (1 + 2 * tail * near) / normalization
        let green = (1 - centralWeight) / 2
        let blue = (128.0 / 255) * (1 - green)
        // Two changing horizontal UNORM passes and final straight-alpha output
        // account for at most three bytes; vertical rows here are constant.
        assertPremultiplied(
            raster(scene, size: size, file: file, line: line), x: 0, y: 16,
            red: 0, green: green, blue: blue, alpha: green + blue,
            accuracy: 3.0 / 255.0, file: file, line: line)
    }

    private func assertIndependentAncestorDoesNotExposeTheGrandparentBackdrop(
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let size = IntSize(width: 32, height: 32)
        var independent = GPUIScene(clearColor: .clear)
        let materialID = independent.registerImageRenderPass(
            materialSource(size: size, tint: quarterRed), size: size,
            input: .isolatedBackdrop, contentBlurRadius: 2)
        independent.addImage(image(materialID, size: size))
        independent.finish()
        var scene = GPUIScene(clearColor: halfBlue)
        let independentID = scene.registerImageRenderPass(independent, size: size)
        scene.addImage(image(independentID, size: size))
        scene.finish()
        // The independent parent is transparent, so its material sees no blue.
        // Its quarter-red result is then source-over on the grandparent blue.
        // Leaking the grandparent into the nested pass would raise alpha to .8125.
        assertPremultiplied(
            raster(scene, size: size, file: file, line: line), x: 16, y: 16,
            red: 0.25, green: 0, blue: 0.375, alpha: 0.625, file: file, line: line)
    }

    private func bounds(_ size: IntSize) -> Rect {
        Rect(x: 0, y: 0, width: Double(size.width), height: Double(size.height))
    }

    private func paint(_ root: ViewNode, size: IntSize, clearColor: Color) -> GPUIScene {
        ScenePainter.paint(
            root: root, clearColor: clearColor,
            surfaceSize: Size(width: Double(size.width), height: Double(size.height)), displayScale: 1)
    }

    private func raster(
        _ scene: GPUIScene, size: IntSize, file: StaticString = #filePath, line: UInt = #line
    ) -> BitmapSurface {
        XCTAssertTrue(
            scene.validate().isEmpty, "The numerical fixture must be an admitted scene", file: file, line: line)
        return GPUIRawSceneRasterizer.rasterize(scene, size: size)
    }

    private func isolatedScene(
        _ source: GPUIScene, size: IntSize, radius: Int32 = 3, backdrop: Color, opacity: Float = 1
    ) -> GPUIScene {
        var scene = GPUIScene(clearColor: backdrop)
        let textureID = scene.registerImageRenderPass(
            source, size: size, input: .isolatedBackdrop, contentBlurRadius: radius)
        scene.addImage(image(textureID, size: size, opacity: opacity))
        scene.finish()
        return scene
    }

    private func materialSource(size: IntSize, frame: Rect? = nil, tint: Color, radius: Float = 4) -> GPUIScene {
        var scene = GPUIScene(clearColor: .clear)
        scene.addQuad(quad(frame ?? bounds(size), color: tint, radius: radius))
        scene.finish()
        return scene
    }

    private func quad(_ frame: Rect, color: Color, radius: Float = 0) -> QuadPrimitive {
        QuadPrimitive(
            x: Float(frame.origin.x), y: Float(frame.origin.y), width: Float(frame.width), height: Float(frame.height),
            startR: color.red, startG: color.green, startB: color.blue, startA: color.alpha,
            endR: color.red, endG: color.green, endB: color.blue, endA: color.alpha, blurRadius: radius)
    }

    private func image(
        _ textureID: Int32, size: IntSize, x: Float = 0, y: Float = 0, opacity: Float = 1
    ) -> ImagePrimitive {
        ImagePrimitive(
            screenX: x, screenY: y, screenW: Float(size.width), screenH: Float(size.height),
            opacity: opacity, textureID: textureID)
    }

    private func bitmapScene(_ bitmap: BitmapSurface) -> GPUIScene {
        var scene = GPUIScene(clearColor: .clear)
        let textureID = scene.registerImageResource(bitmap)
        scene.addImage(image(textureID, size: IntSize(width: bitmap.width, height: bitmap.height)))
        scene.finish()
        return scene
    }

    private func noiseBitmap(size: IntSize, halfBlueCenter: Bool = false) -> BitmapSurface {
        var bytes = [UInt8]()
        for y in 0..<Int(size.height) {
            for x in 0..<Int(size.width) {
                if halfBlueCenter && (16..<48).contains(x) && (16..<48).contains(y) {
                    bytes.append(contentsOf: [255, 0, 0, 128])
                } else {
                    bytes.append(contentsOf: [
                        UInt8((17 * x + 43 * y + 11) % 256),
                        UInt8((29 * x + 7 * y + 53) % 256),
                        UInt8((13 * x + 19 * y + 101) % 256), 255,
                    ])
                }
            }
        }
        return BitmapSurface(width: size.width, height: size.height, bytesPerRow: size.width * 4, pixels: Data(bytes))
    }

    private func solidBitmap(red: UInt8, green: UInt8, blue: UInt8) -> BitmapSurface {
        BitmapSurface(
            width: 2, height: 2, bytesPerRow: 8,
            pixels: Data((0..<4).flatMap { _ in [blue, green, red, 255] }))
    }

    private func glyph(x: Float, y: Float, width: Float, height: Float) -> GlyphPrimitive {
        GlyphPrimitive(
            screenX: x, screenY: y, screenW: width, screenH: height,
            atlasU0: 0, atlasV0: 0, atlasU1: 1, atlasV1: 1, colorR: 1, colorG: 1, colorB: 1, colorA: 1)
    }

    private func glyphAtlas(coverage: UInt8) -> GlyphAtlasSnapshot {
        GlyphAtlasSnapshot(
            width: 2, height: 2, pixels: Data(repeating: coverage, count: 16),
            contentVersion: RenderContentVersion.next(), update: .full)
    }

    private func maxNeighbourDelta(_ bitmap: BitmapSurface, rows: Range<Int>, columns: Range<Int>) -> Int {
        var worst = 0
        let stride = Int(bitmap.bytesPerRow)
        for y in rows {
            for x in columns {
                let offset = y * stride + x * 4
                for neighbor in [offset - 4, offset - stride] {
                    for channel in 0..<3 {
                        worst = max(
                            worst, abs(Int(bitmap.pixels[offset + channel]) - Int(bitmap.pixels[neighbor + channel])))
                    }
                }
            }
        }
        return worst
    }

    private func assertPremultiplied(
        _ bitmap: BitmapSurface, x: Int, y: Int, red: Double, green: Double, blue: Double, alpha: Double,
        accuracy: Double = 2.0 / 255.0, file: StaticString = #filePath, line: UInt = #line
    ) {
        guard x >= 0, y >= 0, x < Int(bitmap.width), y < Int(bitmap.height) else {
            XCTFail("Pixel lies outside the test surface", file: file, line: line)
            return
        }
        // The CPU result is straight-alpha BGRA. Convert the observed bytes
        // directly rather than using the renderer's premultiplication helper.
        // The default allowance covers bounded UNORM rounding plus this final
        // straight/premultiplied round trip, not a guessed visual tolerance.
        let offset = y * Int(bitmap.bytesPerRow) + x * 4
        let observedAlpha = Double(bitmap.pixels[offset + 3]) / 255
        XCTAssertEqual(
            Double(bitmap.pixels[offset + 2]) / 255 * observedAlpha, red, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(
            Double(bitmap.pixels[offset + 1]) / 255 * observedAlpha, green, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(
            Double(bitmap.pixels[offset]) / 255 * observedAlpha, blue, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(observedAlpha, alpha, accuracy: accuracy, file: file, line: line)
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
