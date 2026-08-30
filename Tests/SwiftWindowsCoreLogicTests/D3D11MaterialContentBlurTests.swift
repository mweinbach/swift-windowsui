import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsRendererD3D11
@testable import SwiftWindowsUI

/// Exercises real WARP foreground/coverage targets and the immediate-parent
/// backdrop contract. Independent pixel oracles supplement CPU/GPU parity;
/// these Windows tests do not establish native SwiftUI modifier semantics.
@MainActor
final class D3D11MaterialContentBlurTests: XCTestCase {
    func testRetainedMaterialContentBlurSmoothsTheHistoricalStripeFixture() async throws {
        let size = IntSize(width: 100, height: 100)
        let renderer = try makeRenderer(size: size)
        defer { detachRenderer(renderer) }
        var siblings: [ViewNode] = []
        for stripe in 0..<25 {
            siblings.append(
                ViewNode(
                    frame: Rect(x: 0, y: Double(stripe) * 4, width: 100, height: 2),
                    backgroundColor: .white))
        }
        let panel = ViewNode(
            frame: Rect(x: 20, y: 20, width: 60, height: 60),
            backgroundColor: Color(red: 1, green: 1, blue: 1, alpha: 0.35), blurRadius: 12)
        let group = ViewNode(
            frame: Rect(x: 0, y: 0, width: 100, height: 100), contentBlurRadius: 3, children: [panel])
        siblings.append(group)
        let root = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 100), children: siblings)
        let scene = ScenePainter.paint(
            root: root, clearColor: .black, surfaceSize: Size(width: 100, height: 100))

        let pass = try XCTUnwrap(scene.imageRenderPasses.first)
        XCTAssertEqual(scene.imageRenderPasses.count, 1)
        XCTAssertEqual(pass.input, .isolatedBackdrop)
        XCTAssertEqual(pass.contentBlurRadius, 3)
        XCTAssertTrue(scene.imageResources.isEmpty)
        XCTAssertTrue(pass.scene.imageResources.isEmpty)
        XCTAssertNil(group.cachedCompositingGroupBitmap)
        XCTAssertEqual(scene.layers.flatMap(\.quads).count, 25, "Wallpaper remains outside the isolation")
        let actual = try render(scene, using: renderer)
        let reference = assertBlurParity(actual, scene: scene, size: size)
        for pixels in [actual, reference] {
            XCTAssertLessThan(maxNeighbourDelta(pixels, rows: 40..<60, columns: 40..<60), 20)
            let center = try XCTUnwrap(pixels.pixelColor(atX: 50, y: 50))
            XCTAssertGreaterThan(center.red, 0.35, "The material contains wallpaper, not tint alone")
            XCTAssertLessThan(center.red, 1)
        }
        XCTAssertEqual(renderer.imageTextureUploadsForTesting, 0)
        XCTAssertEqual(renderer.imageTextureCacheCountForTesting, 0)
    }

    func testTranslucentBackdropTintAndOpacityMatchIndependentValues() async throws {
        let size = IntSize(width: 48, height: 48)
        let renderer = try makeRenderer(size: size)
        defer { detachRenderer(renderer) }
        let backdrop = Color(red: 1, green: 0, blue: 0, alpha: 0.5)
        let baseline = try render(GPUIScene(clearColor: backdrop), using: renderer)
        var child = GPUIScene(clearColor: .clear)
        child.addQuad(material(blueTint, x: 8, y: 8, width: 32, height: 32, radius: 6))
        child.finish()
        for opacity in [Float(0), 0.5, 1] {
            var scene = GPUIScene(clearColor: backdrop)
            let sourceID = scene.registerImageRenderPass(
                child, size: size, input: .isolatedBackdrop, contentBlurRadius: 3)
            scene.addImage(image(sourceID, width: 48, height: 48, opacity: opacity))
            scene.addQuad(quad(Color(red: 0, green: 1, blue: 0, alpha: 0.5), width: 4, height: 4))
            scene.finish()
            let actual = try render(scene, using: renderer)
            assertBlurParity(actual, scene: scene, size: size)
            let p = Double(opacity)
            // Tint source-over produces (.3, 0, .4, .7). Replacement coverage
            // is one here, not the result's .7 alpha; opacity mixes with D once.
            assertPremultipliedPixel(
                actual, x: 24, y: 24, red: 0.5 - 0.2 * p, green: 0,
                blue: 0.4 * p, alpha: 0.5 + 0.2 * p)
            assertPremultipliedPixel(actual, x: 2, y: 2, red: 0.25, green: 0.5, blue: 0, alpha: 0.75)
            assertSamePixel(actual, baseline, x: 46, y: 46)
        }
        XCTAssertEqual(renderer.imageTextureUploadsForTesting, 0)
    }

    func testEmptyFilteredOffsurfacePassPreservesEveryParentPixel() async throws {
        let size = IntSize(width: 40, height: 32)
        let renderer = try makeRenderer(size: size)
        defer { detachRenderer(renderer) }
        let parent = stripeScene(size: size, clearColor: Color(red: 1, green: 0, blue: 0, alpha: 0.5))
        let baseline = try render(parent, using: renderer)
        var empty = GPUIScene(clearColor: .clear)
        empty.finish()
        for origin in [Point(x: -8, y: -6), Point(x: 36, y: 28), Point(x: -80, y: -80)] {
            var scene = parent
            let sourceID = scene.registerImageRenderPass(
                empty, size: IntSize(width: 49, height: 41), input: .isolatedBackdrop, contentBlurRadius: 6)
            scene.addImage(image(sourceID, x: Float(origin.x), y: Float(origin.y), width: 49, height: 41))
            scene.finish()
            let actual = try render(scene, using: renderer)
            XCTAssertEqual(actual.pixels, baseline.pixels, "Zero foreground and coverage must be an exact identity")
            assertBlurParity(actual, scene: scene, size: size)
        }
        XCTAssertEqual(renderer.imageTextureUploadsForTesting, 0)
    }

    func testContentBlurChangesOnlyForegroundAndItsTransparentHalo() async throws {
        let size = IntSize(width: 64, height: 64)
        let renderer = try makeRenderer(size: size)
        defer { detachRenderer(renderer) }
        let parent = stripeScene(size: size)
        let baseline = try render(parent, using: renderer)
        var child = GPUIScene(clearColor: .clear)
        child.addQuad(material(whiteTint, x: 24, y: 24, width: 16, height: 16, radius: 6))
        child.finish()
        var scene = parent
        let sourceID = scene.registerImageRenderPass(
            child, size: size, input: .isolatedBackdrop, contentBlurRadius: 3)
        scene.addImage(image(sourceID, width: 64, height: 64))
        scene.finish()
        let actual = try render(scene, using: renderer)
        let reference = assertBlurParity(actual, scene: scene, size: size)
        for pixels in [actual, reference] {
            XCTAssertNotEqual(pixelBytes(pixels, x: 23, y: 34), pixelBytes(baseline, x: 23, y: 34))
            XCTAssertLessThan(maxNeighbourDelta(pixels, rows: 29..<35, columns: 29..<35), 20)
        }
        assertUnchangedOutside(actual, baseline, rect: (x: 21, y: 21, width: 22, height: 22))
        XCTAssertGreaterThan(maxNeighbourDelta(actual, rows: 8..<20, columns: 8..<20), 100)
        XCTAssertEqual(renderer.imageTextureUploadsForTesting, 0)
    }

    func testRoundedOutputClipIsAppliedAfterContentBlur() async throws {
        let size = IntSize(width: 48, height: 48)
        let renderer = try makeRenderer(size: size)
        defer { detachRenderer(renderer) }
        let backdrop = Color(red: 1, green: 0, blue: 0, alpha: 0.5)
        let baseline = try render(GPUIScene(clearColor: backdrop), using: renderer)
        var child = GPUIScene(clearColor: .clear)
        child.addQuad(material(blueTint, width: 48, height: 48, radius: 6))
        child.finish()
        var scene = GPUIScene(clearColor: backdrop)
        let sourceID = scene.registerImageRenderPass(
            child, size: size, input: .isolatedBackdrop, contentBlurRadius: 3)
        scene.addImage(
            ImagePrimitive(
                screenW: 48, screenH: 48, opacity: 0.5,
                clipX: 12.5, clipY: 12, clipWidth: 24, clipHeight: 24,
                clipCornerRadius: 8, textureID: sourceID))
        scene.finish()
        let actual = try render(scene, using: renderer)
        assertBlurParity(actual, scene: scene, size: size)
        assertPremultipliedPixel(actual, x: 24, y: 24, red: 0.4, green: 0, blue: 0.2, alpha: 0.6)
        // At the straight edge, geometric coverage .5 times opacity .5 is .25.
        assertPremultipliedPixel(actual, x: 12, y: 24, red: 0.45, green: 0, blue: 0.1, alpha: 0.55)
        // This pixel lies within the Gaussian's radius of the output clip. It
        // must retain full foreground coverage because clipping happens last.
        assertPremultipliedPixel(actual, x: 14, y: 24, red: 0.4, green: 0, blue: 0.2, alpha: 0.6)
        assertSamePixel(actual, baseline, x: 11, y: 24)
        assertSamePixel(actual, baseline, x: 12, y: 12)
        assertSamePixel(actual, baseline, x: 36, y: 12)
    }

    func testRepeatedSourceOccurrencesObserveInterveningAndLayeredDraws() async throws {
        let size = IntSize(width: 96, height: 40)
        let extent = IntSize(width: 24, height: 24)
        let renderer = try makeRenderer(size: size)
        defer { detachRenderer(renderer) }
        let red = Color(red: 1, green: 0, blue: 0, alpha: 0.5)
        let green = Color(red: 0, green: 1, blue: 0, alpha: 0.5)
        var child = GPUIScene(clearColor: .clear)
        child.addQuad(material(blueTint, width: 24, height: 24, radius: 4))
        child.finish()

        var separate = GPUIScene(clearColor: .clear)
        separate.addQuad(quad(red, x: 4, y: 4, width: 24, height: 24))
        separate.addQuad(quad(green, x: 36, y: 4, width: 24, height: 24))
        let separateID = separate.registerImageRenderPass(
            child, size: extent, input: .isolatedBackdrop, contentBlurRadius: 3)
        separate.addImage(image(separateID, x: 4, y: 4, width: 24, height: 24))
        separate.addImage(image(separateID, x: 36, y: 4, width: 24, height: 24))
        separate.finish()
        XCTAssertEqual(separate.presentationOrder().filter { $0.kind == .image }.count, 1)
        let separatePixels = try render(separate, using: renderer)
        assertBlurParity(separatePixels, scene: separate, size: size)
        assertPremultipliedPixel(separatePixels, x: 16, y: 16, red: 0.3, green: 0, blue: 0.4, alpha: 0.7)
        assertPremultipliedPixel(separatePixels, x: 48, y: 16, red: 0, green: 0.3, blue: 0.4, alpha: 0.7)

        var overlap = GPUIScene(clearColor: red)
        let overlapID = overlap.registerImageRenderPass(
            child, size: extent, input: .isolatedBackdrop, contentBlurRadius: 3)
        overlap.addImage(image(overlapID, x: 4, y: 4, width: 24, height: 24))
        overlap.addImage(image(overlapID, x: 4, y: 4, width: 24, height: 24))
        overlap.finish()
        let overlapPixels = try render(overlap, using: renderer)
        assertBlurParity(overlapPixels, scene: overlap, size: size)
        assertPremultipliedPixel(overlapPixels, x: 16, y: 16, red: 0.18, green: 0, blue: 0.64, alpha: 0.82)
        overlap.addQuad(quad(Color(red: 0, green: 1, blue: 0), x: 4, y: 4, width: 24, height: 24))
        overlap.addImage(image(overlapID, x: 4, y: 4, width: 24, height: 24))
        overlap.finish()
        let intervening = try render(overlap, using: renderer)
        assertBlurParity(intervening, scene: overlap, size: size)
        assertPremultipliedPixel(intervening, x: 16, y: 16, red: 0, green: 0.6, blue: 0.4, alpha: 1)

        var layered = GPUIScene(clearColor: red)
        let upper = layered.pushLayer()
        let layeredID = layered.registerImageRenderPass(
            child, size: extent, input: .isolatedBackdrop, contentBlurRadius: 3)
        // Record the higher layer first, then append the lower-layer backdrop.
        layered.addImage(image(layeredID, x: 4, y: 4, width: 24, height: 24), toLayer: upper)
        layered.addQuad(quad(Color(red: 0, green: 1, blue: 0), x: 4, y: 4, width: 24, height: 24), toLayer: 0)
        layered.addQuad(quad(.white, x: 68, y: 4, width: 16, height: 24), toLayer: upper)
        layered.finish()
        let layeredPixels = try render(layered, using: renderer)
        assertBlurParity(layeredPixels, scene: layered, size: size)
        assertPremultipliedPixel(layeredPixels, x: 16, y: 16, red: 0, green: 0.6, blue: 0.4, alpha: 1)
        assertPremultipliedPixel(layeredPixels, x: 76, y: 16, red: 1, green: 1, blue: 1, alpha: 1)
        XCTAssertEqual(renderer.imageTextureUploadsForTesting, 0)
    }

    func testEarlierLocalForegroundParticipatesInTheMaterialBackdrop() async throws {
        let size = IntSize(width: 48, height: 48)
        let renderer = try makeRenderer(size: size)
        defer { detachRenderer(renderer) }
        var child = GPUIScene(clearColor: .clear)
        child.addQuad(quad(Color(red: 0, green: 1, blue: 0, alpha: 0.5), width: 48, height: 48))
        child.addQuad(material(blueTint, x: 8, y: 8, width: 32, height: 32, radius: 4))
        child.finish()
        var scene = GPUIScene(clearColor: Color(red: 1, green: 0, blue: 0, alpha: 0.5))
        let sourceID = scene.registerImageRenderPass(
            child, size: size, input: .isolatedBackdrop, contentBlurRadius: 3)
        scene.addImage(image(sourceID, width: 48, height: 48))
        scene.finish()
        let actual = try render(scene, using: renderer)
        assertBlurParity(actual, scene: scene, size: size)
        // S before the material is (.25, .5, 0, .75); a blue .4 tint gives
        // .6*S + (0, 0, .4, .4), not a new read of the original red parent.
        assertPremultipliedPixel(actual, x: 24, y: 24, red: 0.15, green: 0.3, blue: 0.4, alpha: 0.85)
        assertPremultipliedPixel(actual, x: 3, y: 24, red: 0.25, green: 0.5, blue: 0, alpha: 0.75)
    }

    func testNestedGroupsReturnCoverageWithoutImportingTransparentBounds() async throws {
        let size = IntSize(width: 64, height: 64)
        let renderer = try makeRenderer(size: size)
        defer { detachRenderer(renderer) }
        let parent = stripeScene(size: size)
        let baseline = try render(parent, using: renderer)
        var inner = GPUIScene(clearColor: .clear)
        inner.addQuad(material(whiteTint, x: 16, y: 16, width: 16, height: 16, radius: 6))
        inner.finish()
        for input in [GPUISceneImageRenderPassInput.currentTarget, .isolatedBackdrop] {
            var child = GPUIScene(clearColor: .clear)
            let innerID = child.registerImageRenderPass(
                inner, size: IntSize(width: 48, height: 48), input: input)
            let nestedImage = image(innerID, x: 8, y: 8, width: 48, height: 48)
            child.addImage(nestedImage)
            child.finish()
            if input == .currentTarget {
                let pass = try XCTUnwrap(child.imageRenderPasses.first)
                XCTAssertNotNil(pass.currentTargetRegion(for: nestedImage, parentSize: size))
            }
            var scene = parent
            let sourceID = scene.registerImageRenderPass(
                child, size: size, input: .isolatedBackdrop, contentBlurRadius: 3)
            scene.addImage(image(sourceID, width: 64, height: 64))
            scene.finish()
            let actual = try render(scene, using: renderer)
            assertBlurParity(actual, scene: scene, size: size)
            XCTAssertLessThan(maxNeighbourDelta(actual, rows: 29..<35, columns: 29..<35), 20)
            assertUnchangedOutside(actual, baseline, rect: (x: 21, y: 21, width: 22, height: 22))
            // This is inside the nested image's transparent rectangle, well
            // outside its material halo. Importing that rectangle would blur it.
            XCTAssertGreaterThan(maxNeighbourDelta(actual, rows: 12..<20, columns: 12..<20), 100)
        }
        XCTAssertEqual(renderer.imageTextureUploadsForTesting, 0)
    }

    func testIndependentChildCannotReadTheEnclosingBackdrop() async throws {
        let size = IntSize(width: 48, height: 48)
        let renderer = try makeRenderer(size: size)
        defer { detachRenderer(renderer) }
        let parent = stripeScene(size: size)
        let baseline = try render(parent, using: renderer)
        var leaf = GPUIScene(clearColor: .clear)
        leaf.addQuad(material(.clear, width: 24, height: 24, radius: 6))
        leaf.finish()
        var independent = GPUIScene(clearColor: .clear)
        let dependentID = independent.registerImageRenderPass(
            leaf, size: IntSize(width: 24, height: 24), input: .isolatedBackdrop, contentBlurRadius: 3)
        independent.addImage(image(dependentID, x: 4, y: 4, width: 24, height: 24))
        independent.finish()
        var child = GPUIScene(clearColor: .clear)
        let independentID = child.registerImageRenderPass(independent, size: IntSize(width: 32, height: 32))
        child.addImage(image(independentID, x: 8, y: 8, width: 32, height: 32))
        child.finish()
        var scene = parent
        let sourceID = scene.registerImageRenderPass(
            child, size: size, input: .isolatedBackdrop, contentBlurRadius: 3)
        scene.addImage(image(sourceID, width: 48, height: 48))
        scene.finish()
        let actual = try render(scene, using: renderer)
        assertBlurParity(actual, scene: scene, size: size)
        XCTAssertEqual(actual.pixels, baseline.pixels, "An untinted material reads transparent independent input")
        XCTAssertGreaterThan(maxNeighbourDelta(actual, rows: 20..<28, columns: 20..<28), 100)
        XCTAssertEqual(renderer.imageTextureUploadsForTesting, 0)
    }

    func testOrdinaryFamiliesPreserveCoverageAndRestoreParentNamespaces() async throws {
        let size = IntSize(width: 144, height: 72)
        let renderer = try makeRenderer(size: size)
        defer { detachRenderer(renderer) }
        let leafID: Int32 = 88_801
        let green = Color(red: 0, green: 1, blue: 0, alpha: 0.5)
        let childBitmap = bitmap(red: 0, green: 255, blue: 0, alpha: 128)
        let parentBitmap = bitmap(red: 255, green: 0, blue: 0)
        var child = GPUIScene(clearColor: .clear)
        child.addShadow(
            ShadowPrimitive(
                x: 4, y: 8, width: 12, height: 24,
                colorR: 0, colorG: 1, colorB: 0, colorA: 0.5, blurRadius: 0))
        child.addQuad(quad(green, x: 20, y: 8, width: 12, height: 24))
        child.bindImageResource(childBitmap, for: leafID)
        child.addImage(image(leafID, x: 36, y: 8, width: 12, height: 24))
        child.addPath(rectangularPath(x: 52, y: 8, width: 12, height: 24, color: green), toLayer: 0)
        child.glyphAtlas = glyphAtlas(coverage: 255)
        child.pixelGlyphAtlas = glyphAtlas(coverage: 255)
        child.addGlyph(glyph(x: 68, y: 8, width: 12, height: 24, color: green))
        child.addPixelGlyph(glyph(x: 84, y: 8, width: 12, height: 24, color: green))
        child.addQuad(material(whiteTint, x: 100, y: 8, width: 8, height: 24, radius: 2))
        child.finish()
        var scene = GPUIScene(clearColor: Color(red: 1, green: 0, blue: 0, alpha: 0.5))
        scene.bindImageResource(parentBitmap, for: leafID)
        scene.glyphAtlas = glyphAtlas(coverage: 128)
        scene.pixelGlyphAtlas = glyphAtlas(coverage: 64)
        let sourceID = scene.registerImageRenderPass(
            child, size: IntSize(width: 112, height: 48), input: .isolatedBackdrop, contentBlurRadius: 3)
        scene.addImage(image(sourceID, x: 8, y: 8, width: 112, height: 48))
        scene.addImage(image(leafID, x: 128, y: 8, width: 8, height: 8))
        scene.addGlyph(glyph(x: 128, y: 24, width: 8, height: 8, color: Color(red: 0, green: 0, blue: 1)))
        scene.addPixelGlyph(glyph(x: 128, y: 40, width: 8, height: 8, color: Color(red: 0, green: 0, blue: 1)))
        scene.addQuad(quad(Color(red: 0, green: 0, blue: 1, alpha: 0.5), x: 128, y: 56, width: 8, height: 8))
        scene.finish()
        let actual = try render(scene, using: renderer)
        assertBlurParity(actual, scene: scene, size: size)
        for localX in [10, 26, 42, 58, 74, 90] {
            assertPremultipliedPixel(actual, x: localX + 8, y: 28, red: 0.25, green: 0.5, blue: 0, alpha: 0.75)
        }
        assertPremultipliedPixel(actual, x: 132, y: 12, red: 1, green: 0, blue: 0, alpha: 1)
        let glyphCoverage = 128.0 / 255
        assertPremultipliedPixel(
            actual, x: 132, y: 28, red: 0.5 * (1 - glyphCoverage), green: 0,
            blue: glyphCoverage, alpha: 0.5 + 0.5 * glyphCoverage)
        let pixelCoverage = 64.0 / 255
        assertPremultipliedPixel(
            actual, x: 132, y: 44, red: 0.5 * (1 - pixelCoverage), green: 0,
            blue: pixelCoverage, alpha: 0.5 + 0.5 * pixelCoverage)
        assertPremultipliedPixel(actual, x: 132, y: 60, red: 0.25, green: 0, blue: 0.5, alpha: 0.75)
        let warmedObjects = renderer.liveCOMObjectCountForTesting
        let repeated = try render(scene, using: renderer)
        XCTAssertEqual(repeated.pixels, actual.pixels)
        XCTAssertEqual(renderer.liveCOMObjectCountForTesting, warmedObjects)
    }

    func testNegativeOriginsOddExtentsAndReducedGaussianMatchCPU() async throws {
        let size = IntSize(width: 72, height: 64)
        let renderer = try makeRenderer(size: size)
        defer { detachRenderer(renderer) }
        let cases: [(extent: IntSize, x: Float, y: Float, radius: Int32)] = [
            (IntSize(width: 63, height: 47), -8, -6, 3),
            (IntSize(width: 17, height: 9), -4, 60, 6),
            (IntSize(width: 31, height: 17), 64, -4, 220),
            (IntSize(width: 5, height: 9), -2, -4, 220),
        ]
        for (index, fixture) in cases.enumerated() {
            let sentinel = index.isMultiple(of: 2) ? Color(red: 1, green: 0, blue: 1) : Color(red: 0, green: 1, blue: 0)
            let parent = stripeScene(size: size, clearColor: sentinel)
            let baseline = try render(parent, using: renderer)
            var child = GPUIScene(clearColor: .clear)
            child.addQuad(
                material(
                    whiteTint, width: Float(fixture.extent.width), height: Float(fixture.extent.height), radius: 220))
            child.finish()
            if fixture.radius == 220 {
                let plan = BlurPassPlan(
                    radius: 220, regionWidth: Int(fixture.extent.width), regionHeight: Int(fixture.extent.height))
                XCTAssertTrue(plan.isReduced)
                XCTAssertEqual(plan.halvingPassCount, 2)
            }
            var scene = parent
            let sourceID = scene.registerImageRenderPass(
                child, size: fixture.extent, input: .isolatedBackdrop, contentBlurRadius: fixture.radius)
            let composite = image(
                sourceID, x: fixture.x, y: fixture.y,
                width: Float(fixture.extent.width), height: Float(fixture.extent.height))
            scene.addImage(composite)
            scene.finish()
            let pass = try XCTUnwrap(scene.imageRenderPasses.first)
            let mapping = try XCTUnwrap(pass.isolatedBackdropMapping(for: composite, parentSize: size))
            let visible = try XCTUnwrap(mapping.parentCopyRegion)
            let actual = try render(scene, using: renderer)
            let reference = assertBlurParity(actual, scene: scene, size: size)
            let roi = (x: visible.originX, y: visible.originY, width: visible.width, height: visible.height)
            // Tiny visible crops must meet the same bound as the whole frame.
            XCTAssertGreaterThan(
                comparePixels(crop(actual, to: roi), crop(reference, to: roi), tolerance: 4).matchRatio, 0.995)
            assertUnchangedOutside(actual, baseline, rect: roi)
        }
        XCTAssertEqual(renderer.imageTextureUploadsForTesting, 0)
    }

    func testEightPlaneBudgetRejectsBeforeAllocationAndPreservesThePrefix() async throws {
        let size = IntSize(width: 24, height: 16)
        let renderer = try makeRenderer(size: size)
        defer { detachRenderer(renderer) }
        let backdrop = Color(red: 1, green: 0, blue: 0, alpha: 0.5)
        var prefix = GPUIScene(clearColor: backdrop)
        prefix.addQuad(quad(Color(red: 0, green: 1, blue: 0, alpha: 0.5), width: 4, height: 4))
        prefix.finish()
        let prefixPixels = try render(prefix, using: renderer)
        let warmedObjects = renderer.liveCOMObjectCountForTesting
        var child = GPUIScene(clearColor: .clear)
        child.addQuad(material(blueTint, width: 8, height: 8, radius: 2))
        child.finish()
        var scene = prefix
        let sourceID = scene.registerImageRenderPass(
            child, size: IntSize(width: 8, height: 8), input: .isolatedBackdrop, contentBlurRadius: 1)
        scene.addImage(image(sourceID, x: 8, y: 4, width: 8, height: 8))
        scene.addQuad(quad(Color(red: 0, green: 0, blue: 1), x: 20, width: 4, height: 4))
        scene.finish()
        XCTAssertEqual(GPUISceneBackdropIsolationLimits.scratchPlaneCount, 8)
        XCTAssertTrue(scene.validate().isEmpty)
        renderer.imageRenderPassExecutionBudgetOverrideForTesting = GPUISceneImageRenderPassBudget(
            maxPasses: 4, maxPixels: 511)
        renderer.bindResources(for: scene)
        XCTAssertThrowsError(try renderer.render(scene: scene)) { error in
            let failure = error as? BatchRendererError
            XCTAssertEqual(failure?.operation, "Execute isolated-backdrop image pass")
            XCTAssertEqual(failure?.presentationFailureKind, .sceneContent)
        }
        XCTAssertEqual(renderer.directlyOwnedImagePassTargetCountForTesting, 0)
        XCTAssertEqual(renderer.liveCOMObjectCountForTesting, warmedObjects)
        XCTAssertEqual(renderer.isolatedBlurPipelineCreationCountForTesting, 0)
        XCTAssertFalse(renderer.isolatedBlurPipelineOwnsResourcesForTesting)
        XCTAssertEqual(try renderer.readOffscreenPixels().pixels, prefixPixels.pixels)

        renderer.imageRenderPassExecutionBudgetOverrideForTesting = GPUISceneImageRenderPassBudget(
            maxPasses: 4, maxPixels: 512)
        let recovered = try render(scene, using: renderer)
        assertPremultipliedPixel(recovered, x: 12, y: 8, red: 0.3, green: 0, blue: 0.4, alpha: 0.7)
        assertPremultipliedPixel(recovered, x: 22, y: 2, red: 0, green: 0, blue: 1, alpha: 1)
        XCTAssertEqual(renderer.imageTextureUploadsForTesting, 0)
    }

    func testRepeatedOccurrencesSpendTheBudgetAgainAndRecoverNextFrame() async throws {
        let size = IntSize(width: 32, height: 16)
        let renderer = try makeRenderer(size: size)
        defer { detachRenderer(renderer) }
        var child = GPUIScene(clearColor: .clear)
        child.addQuad(material(blueTint, width: 8, height: 8, radius: 2))
        child.finish()
        var single = GPUIScene(clearColor: Color(red: 1, green: 0, blue: 0, alpha: 0.5))
        single.addQuad(quad(.white, y: 12, width: 2, height: 2))
        let sourceID = single.registerImageRenderPass(
            child, size: IntSize(width: 8, height: 8), input: .isolatedBackdrop, contentBlurRadius: 1)
        single.addImage(image(sourceID, x: 4, y: 4, width: 8, height: 8))
        single.finish()
        let expected = try render(single, using: renderer)
        let warmedObjects = renderer.liveCOMObjectCountForTesting
        var repeated = single
        repeated.addImage(image(sourceID, x: 16, y: 4, width: 8, height: 8))
        repeated.addQuad(quad(Color(red: 0, green: 1, blue: 0), x: 28, width: 4, height: 4))
        repeated.finish()
        XCTAssertEqual(repeated.imageRenderPasses.count, 1, "Structural validation charges one declaration")
        XCTAssertTrue(repeated.validate().isEmpty)
        let imageRuns = repeated.presentationOrder().filter { $0.kind == .image }
        XCTAssertEqual(imageRuns.count, 1)
        XCTAssertEqual(imageRuns.first?.range, 0..<2, "Contiguous same-ID images still realize independently")
        let budgets = [
            GPUISceneImageRenderPassBudget(maxPasses: 4, maxPixels: 512),
            GPUISceneImageRenderPassBudget(maxPasses: 1, maxPixels: 1024),
        ]
        for budget in budgets {
            renderer.imageRenderPassExecutionBudgetOverrideForTesting = budget
            renderer.bindResources(for: repeated)
            XCTAssertThrowsError(try renderer.render(scene: repeated)) { error in
                let failure = error as? BatchRendererError
                XCTAssertEqual(failure?.operation, "Execute isolated-backdrop image pass")
                XCTAssertEqual(failure?.presentationFailureKind, .sceneContent)
            }
            let partial = try renderer.readOffscreenPixels()
            XCTAssertEqual(
                partial.pixels, expected.pixels, "The first occurrence survives; the second and later draw do not")
            XCTAssertEqual(renderer.directlyOwnedImagePassTargetCountForTesting, 0)
            XCTAssertEqual(renderer.liveCOMObjectCountForTesting, warmedObjects)
            let recovered = try render(single, using: renderer)
            XCTAssertEqual(
                recovered.pixels, expected.pixels, "Each enclosing frame starts with a fresh execution budget")
        }
        XCTAssertEqual(renderer.imageTextureUploadsForTesting, 0)
    }

    func testIsolatedMaterialFailuresRestoreStateWithoutLatchingDegradation() async throws {
        let size = IntSize(width: 64, height: 48)
        let renderer = try makeRenderer(size: size)
        defer {
            renderer.failBlurredQuadsForTesting = false
            renderer.failIsolatedCoverageForTesting = false
            detachRenderer(renderer)
        }
        func fixture(hasMaterial: Bool) -> GPUIScene {
            var child = GPUIScene(clearColor: .clear)
            child.addQuad(
                hasMaterial
                    ? material(blueTint, x: 4, y: 4, width: 24, height: 24, radius: 4)
                    : quad(blueTint, x: 4, y: 4, width: 24, height: 24))
            child.finish()
            var scene = GPUIScene(clearColor: Color(red: 1, green: 0, blue: 0, alpha: 0.5))
            scene.addQuad(quad(Color(red: 0, green: 1, blue: 0, alpha: 0.5), width: 4, height: 4))
            let sourceID = scene.registerImageRenderPass(
                child, size: IntSize(width: 32, height: 32), input: .isolatedBackdrop, contentBlurRadius: 3)
            scene.addImage(image(sourceID, x: 8, y: 8, width: 32, height: 32))
            scene.addQuad(quad(Color(red: 0, green: 1, blue: 0), x: 52, y: 32, width: 8, height: 8))
            scene.finish()
            return scene
        }
        let materialScene = fixture(hasMaterial: true)
        let ordinaryScene = fixture(hasMaterial: false)
        let materialExpected = try render(materialScene, using: renderer)
        let ordinaryExpected = try render(ordinaryScene, using: renderer)
        let warmedObjects = renderer.liveCOMObjectCountForTesting
        let failures: [(scene: GPUIScene, expected: BitmapSurface, early: Bool, operation: String)] = [
            (materialScene, materialExpected, true, "Draw isolated material quad"),
            (materialScene, materialExpected, false, "Draw isolated material coverage"),
            (ordinaryScene, ordinaryExpected, false, "Filter isolated coverage"),
        ]
        for failure in failures {
            renderer.failBlurredQuadsForTesting = failure.early
            renderer.failIsolatedCoverageForTesting = !failure.early
            renderer.bindResources(for: failure.scene)
            XCTAssertThrowsError(try renderer.render(scene: failure.scene)) { error in
                XCTAssertEqual((error as? BatchRendererError)?.operation, failure.operation)
            }
            XCTAssertFalse(renderer.blurDegradedForTesting)
            XCTAssertEqual(renderer.directlyOwnedImagePassTargetCountForTesting, 0)
            XCTAssertFalse(renderer.isolatedBlurPipelineHasTargetsForTesting)
            XCTAssertEqual(renderer.liveCOMObjectCountForTesting, warmedObjects)
            let partial = try renderer.readOffscreenPixels()
            assertPremultipliedPixel(partial, x: 2, y: 2, red: 0.25, green: 0.5, blue: 0, alpha: 0.75)
            assertPremultipliedPixel(partial, x: 24, y: 24, red: 0.5, green: 0, blue: 0, alpha: 0.5)
            assertPremultipliedPixel(partial, x: 56, y: 36, red: 0.5, green: 0, blue: 0, alpha: 0.5)
            renderer.failBlurredQuadsForTesting = false
            renderer.failIsolatedCoverageForTesting = false
            let recovered = try render(failure.scene, using: renderer)
            XCTAssertEqual(recovered.pixels, failure.expected.pixels)
            XCTAssertEqual(renderer.liveCOMObjectCountForTesting, warmedObjects)
            XCTAssertFalse(renderer.blurDegradedForTesting)
        }
        XCTAssertEqual(renderer.imageTextureUploadsForTesting, 0)
    }

    func testReplayedRecordsReadFreshClearColorsWithoutBitmapUploads() async throws {
        let size = IntSize(width: 64, height: 48)
        let renderer = try makeRenderer(size: size)
        defer { detachRenderer(renderer) }
        var child = GPUIScene(clearColor: .clear)
        child.addQuad(material(blueTint, x: 4, y: 4, width: 24, height: 24, radius: 4))
        child.finish()
        var recorded = GPUIScene(clearColor: .clear)
        let sourceID = recorded.registerImageRenderPass(
            child, size: IntSize(width: 32, height: 32), input: .isolatedBackdrop, contentBlurRadius: 3)
        recorded.addImage(image(sourceID, x: 8, y: 8, width: 32, height: 32))
        recorded.finish()
        var previous: BitmapSurface?
        var warmedObjects: Int?
        for index in 0..<8 {
            let green = index.isMultiple(of: 2)
            var scene = GPUIScene(
                clearColor: Color(red: green ? 0 : 1, green: green ? 1 : 0, blue: 0, alpha: 0.5))
            XCTAssertEqual(scene.replay(0..<recorded.paintRecordCount, from: recorded), .success)
            scene.finish()
            let pass = try XCTUnwrap(scene.imageRenderPasses.first)
            XCTAssertEqual(pass.input, .isolatedBackdrop)
            XCTAssertEqual(pass.contentBlurRadius, 3)
            XCTAssertEqual(pass.scene, child)
            XCTAssertTrue(scene.imageResources.isEmpty)
            XCTAssertTrue(pass.scene.imageResources.isEmpty)
            let actual = try render(scene, using: renderer)
            assertBlurParity(actual, scene: scene, size: size)
            assertPremultipliedPixel(
                actual, x: 24, y: 24, red: green ? 0 : 0.3, green: green ? 0.3 : 0, blue: 0.4, alpha: 0.7)
            if let previous {
                XCTAssertNotEqual(pixelBytes(actual, x: 24, y: 24), pixelBytes(previous, x: 24, y: 24))
            }
            if let warmedObjects {
                XCTAssertEqual(renderer.liveCOMObjectCountForTesting, warmedObjects)
            } else {
                warmedObjects = renderer.liveCOMObjectCountForTesting
            }
            previous = actual
            XCTAssertEqual(renderer.imageTextureUploadsForTesting, 0, "No parent-dependent CPU bitmap is uploaded")
            XCTAssertEqual(renderer.imageTextureCacheCountForTesting, 0)
        }
    }

    func testBlurPipelineReusesShadersWithoutRetainingTargetsAcrossAttachment() async throws {
        let size = IntSize(width: 32, height: 32)
        let renderer = try makeRenderer(size: size)
        defer { detachRenderer(renderer) }
        var child = GPUIScene(clearColor: .clear)
        child.addQuad(material(blueTint, x: 4, y: 4, width: 24, height: 24, radius: 4))
        child.finish()
        var scene = GPUIScene(clearColor: Color(red: 1, green: 0, blue: 0, alpha: 0.5))
        let sourceID = scene.registerImageRenderPass(
            child, size: size, input: .isolatedBackdrop, contentBlurRadius: 3)
        scene.addImage(image(sourceID, width: 32, height: 32))
        scene.finish()
        XCTAssertEqual(renderer.isolatedBlurPipelineCreationCountForTesting, 0)
        XCTAssertFalse(renderer.isolatedBlurPipelineOwnsResourcesForTesting)
        let initial = try render(scene, using: renderer)
        assertBlurParity(initial, scene: scene, size: size)
        XCTAssertEqual(renderer.isolatedBlurPipelineCreationCountForTesting, 1)
        XCTAssertTrue(renderer.isolatedBlurPipelineOwnsResourcesForTesting)
        let warmedObjects = renderer.liveCOMObjectCountForTesting
        for _ in 0..<4 {
            XCTAssertEqual(try render(scene, using: renderer).pixels, initial.pixels)
            XCTAssertEqual(renderer.isolatedBlurPipelineCreationCountForTesting, 1)
            XCTAssertFalse(renderer.isolatedBlurPipelineHasTargetsForTesting)
            XCTAssertEqual(renderer.liveCOMObjectCountForTesting, warmedObjects)
        }
        detachRenderer(renderer)
        XCTAssertEqual(renderer.isolatedBlurPipelineCreationCountForTesting, 1, "The instance counter is cumulative")
        try renderer.attachOffscreen(size: size, driver: .warpFirst)
        XCTAssertEqual(renderer.backendDiagnostics?.adapterIsSoftware, true)
        XCTAssertFalse(renderer.isolatedBlurPipelineOwnsResourcesForTesting)
        let reattached = try render(scene, using: renderer)
        XCTAssertEqual(reattached.pixels, initial.pixels)
        XCTAssertEqual(renderer.isolatedBlurPipelineCreationCountForTesting, 2)
        XCTAssertTrue(renderer.isolatedBlurPipelineOwnsResourcesForTesting)
        XCTAssertFalse(renderer.isolatedBlurPipelineHasTargetsForTesting)
        XCTAssertEqual(renderer.imageTextureUploadsForTesting, 0)
    }

    private var blueTint: Color { Color(red: 0, green: 0, blue: 1, alpha: 0.4) }
    private var whiteTint: Color { Color(red: 1, green: 1, blue: 1, alpha: 0.35) }

    private func makeRenderer(
        size: IntSize, file: StaticString = #filePath, line: UInt = #line
    ) throws -> D3D11BatchRenderer {
        // Only device absence may skip. After the probe, shader, target and
        // renderer setup failures propagate as failures, including reattach.
        let probe = try makeWARPDevice()
        probe.release()
        let renderer = D3D11BatchRenderer()
        var attached = false
        defer { if !attached { detachRenderer(renderer, file: file, line: line) } }
        try renderer.attachOffscreen(size: size, driver: .warpFirst)
        XCTAssertEqual(renderer.backendDiagnostics?.adapterIsSoftware, true, file: file, line: line)
        attached = true
        return renderer
    }

    private func detachRenderer(
        _ renderer: D3D11BatchRenderer, file: StaticString = #filePath, line: UInt = #line
    ) {
        renderer.detach()
        XCTAssertEqual(renderer.directlyOwnedImagePassTargetCountForTesting, 0, file: file, line: line)
        XCTAssertEqual(renderer.liveCOMObjectCountForTesting, 0, file: file, line: line)
        XCTAssertFalse(renderer.blurEngineOwnsResourcesForTesting, file: file, line: line)
        XCTAssertFalse(renderer.isolatedBlurPipelineHasTargetsForTesting, file: file, line: line)
        XCTAssertFalse(renderer.isolatedBlurPipelineOwnsResourcesForTesting, file: file, line: line)
    }

    private func render(
        _ scene: GPUIScene, using renderer: D3D11BatchRenderer,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> BitmapSurface {
        XCTAssertTrue(scene.validate().isEmpty, file: file, line: line)
        renderer.bindResources(for: scene)
        try renderer.render(scene: scene)
        XCTAssertEqual(renderer.directlyOwnedImagePassTargetCountForTesting, 0, file: file, line: line)
        XCTAssertFalse(renderer.isolatedBlurPipelineHasTargetsForTesting, file: file, line: line)
        return try renderer.readOffscreenPixels()
    }

    @discardableResult
    private func assertBlurParity(
        _ actual: BitmapSurface, scene: GPUIScene, size: IntSize,
        file: StaticString = #filePath, line: UInt = #line
    ) -> BitmapSurface {
        let expected = GPUIRawSceneRasterizer.rasterize(scene, size: size).premultipliedAlpha()
        XCTAssertEqual(actual.width, expected.width, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, file: file, line: line)
        let report = comparePixels(actual, expected, tolerance: 4)
        XCTAssertGreaterThan(
            report.matchRatio, 0.995,
            "CPU/GPU mismatch: max delta \(report.maxChannelDelta), first \(String(describing: report.firstFailure))",
            file: file, line: line)
        var maxAlphaDelta = 0
        if actual.width == expected.width, actual.height == expected.height {
            for y in 0..<Int(expected.height) {
                for x in 0..<Int(expected.width) {
                    let a = pixelBytes(actual, x: x, y: y)
                    let b = pixelBytes(expected, x: x, y: y)
                    if a.count == 4, b.count == 4 {
                        maxAlphaDelta = max(maxAlphaDelta, abs(Int(a[3]) - Int(b[3])))
                    }
                }
            }
        }
        XCTAssertLessThanOrEqual(maxAlphaDelta, 2, "Foreground coverage must preserve alpha", file: file, line: line)
        return expected
    }

    private func assertPremultipliedPixel(
        _ bitmap: BitmapSurface, x: Int, y: Int,
        red: Double, green: Double, blue: Double, alpha: Double,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(bitmap.format.alphaMode, .premultiplied, file: file, line: line)
        let bytes = pixelBytes(bitmap, x: x, y: y)
        XCTAssertEqual(bytes.count, 4, file: file, line: line)
        guard bytes.count == 4 else { return }
        for (channel, expected) in [blue, green, red, alpha].enumerated() {
            XCTAssertEqual(Double(bytes[channel]) / 255, expected, accuracy: 0.01, file: file, line: line)
        }
    }

    private func pixelBytes(_ bitmap: BitmapSurface, x: Int, y: Int) -> [UInt8] {
        guard x >= 0, y >= 0, x < Int(bitmap.width), y < Int(bitmap.height) else { return [] }
        let offset = y * Int(bitmap.bytesPerRow) + x * 4
        guard offset + 4 <= bitmap.pixels.count else { return [] }
        return Array(bitmap.pixels[offset..<(offset + 4)])
    }

    private func assertSamePixel(
        _ actual: BitmapSurface, _ expected: BitmapSurface, x: Int, y: Int,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let actualBytes = pixelBytes(actual, x: x, y: y)
        let expectedBytes = pixelBytes(expected, x: x, y: y)
        XCTAssertEqual(actualBytes.count, 4, file: file, line: line)
        XCTAssertEqual(expectedBytes.count, 4, file: file, line: line)
        XCTAssertEqual(actualBytes, expectedBytes, file: file, line: line)
    }

    private func maxNeighbourDelta(_ bitmap: BitmapSurface, rows: Range<Int>, columns: Range<Int>) -> Int {
        var worst = 0
        let rowStride = Int(bitmap.bytesPerRow)
        for y in rows where y >= 1 && y < Int(bitmap.height) {
            for x in columns where x >= 1 && x < Int(bitmap.width) {
                let offset = y * rowStride + x * 4
                for neighbour in [offset - 4, offset - rowStride] {
                    for channel in 0..<3 {
                        worst = max(
                            worst, abs(Int(bitmap.pixels[offset + channel]) - Int(bitmap.pixels[neighbour + channel])))
                    }
                }
            }
        }
        return worst
    }

    private func assertUnchangedOutside(
        _ actual: BitmapSurface, _ expected: BitmapSurface,
        rect: (x: Int, y: Int, width: Int, height: Int),
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(actual.width, expected.width, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, file: file, line: line)
        var changedPixels = 0
        for y in 0..<Int(expected.height) {
            for x in 0..<Int(expected.width) {
                if x >= rect.x, x < rect.x + rect.width, y >= rect.y, y < rect.y + rect.height { continue }
                if pixelBytes(actual, x: x, y: y) != pixelBytes(expected, x: x, y: y) { changedPixels += 1 }
            }
        }
        XCTAssertEqual(
            changedPixels, 0, "Pixels outside foreground support must remain untouched", file: file, line: line)
    }

    private func crop(_ bitmap: BitmapSurface, to rect: (x: Int, y: Int, width: Int, height: Int)) -> BitmapSurface {
        var bytes = Data()
        bytes.reserveCapacity(rect.width * rect.height * 4)
        for y in rect.y..<(rect.y + rect.height) {
            let offset = y * Int(bitmap.bytesPerRow) + rect.x * 4
            bytes.append(contentsOf: bitmap.pixels[offset..<(offset + rect.width * 4)])
        }
        return BitmapSurface(
            width: Int32(rect.width), height: Int32(rect.height), bytesPerRow: Int32(rect.width * 4),
            pixels: bytes, format: bitmap.format)
    }

    private func stripeScene(size: IntSize, clearColor: Color = .black) -> GPUIScene {
        var scene = GPUIScene(clearColor: clearColor)
        for y in stride(from: 0, to: Int(size.height), by: 4) {
            scene.addQuad(quad(.white, y: Float(y), width: Float(size.width), height: 2))
        }
        scene.finish()
        return scene
    }

    private func image(
        _ textureID: Int32, x: Float = 0, y: Float = 0, width: Float, height: Float, opacity: Float = 1
    ) -> ImagePrimitive {
        ImagePrimitive(screenX: x, screenY: y, screenW: width, screenH: height, opacity: opacity, textureID: textureID)
    }

    private func quad(
        _ color: Color, x: Float = 0, y: Float = 0, width: Float, height: Float
    ) -> QuadPrimitive {
        QuadPrimitive(
            x: x, y: y, width: width, height: height,
            startR: color.red, startG: color.green, startB: color.blue, startA: color.alpha,
            endR: color.red, endG: color.green, endB: color.blue, endA: color.alpha)
    }

    private func material(
        _ tint: Color, x: Float = 0, y: Float = 0, width: Float, height: Float, radius: Float
    ) -> QuadPrimitive {
        var result = quad(tint, x: x, y: y, width: width, height: height)
        result.blurRadius = radius
        return result
    }

    private func glyph(x: Float, y: Float, width: Float, height: Float, color: Color) -> GlyphPrimitive {
        GlyphPrimitive(
            screenX: x, screenY: y, screenW: width, screenH: height,
            atlasU0: 0, atlasV0: 0, atlasU1: 1, atlasV1: 1,
            colorR: color.red, colorG: color.green, colorB: color.blue, colorA: color.alpha)
    }

    private func glyphAtlas(coverage: UInt8) -> GlyphAtlasSnapshot {
        GlyphAtlasSnapshot(
            width: 4, height: 4, pixels: Data(repeating: coverage, count: 4 * 4 * 4),
            contentVersion: RenderContentVersion.next(), update: .full)
    }

    private func bitmap(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) -> BitmapSurface {
        var bytes = [UInt8]()
        for _ in 0..<64 { bytes.append(contentsOf: [blue, green, red, alpha]) }
        return BitmapSurface(width: 8, height: 8, bytesPerRow: 32, pixels: Data(bytes))
    }

    private func rectangularPath(x: Double, y: Double, width: Double, height: Double, color: Color) -> PathPrimitive {
        PathPrimitive(
            elements: [
                .moveTo(Point(x: x, y: y)), .lineTo(Point(x: x + width, y: y)),
                .lineTo(Point(x: x + width, y: y + height)), .lineTo(Point(x: x, y: y + height)), .close,
            ],
            bounds: Rect(x: x, y: y, width: width, height: height), fillColor: color)
    }
}
