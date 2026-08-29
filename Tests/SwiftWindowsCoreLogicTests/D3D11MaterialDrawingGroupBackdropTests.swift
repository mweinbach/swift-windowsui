import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsRendererD3D11
@testable import SwiftWindowsUI

/// Current-target image passes read their immediate parent's presentation
/// prefix and replace covered premultiplied RGBA without uploading a group bitmap.
@MainActor
final class D3D11MaterialDrawingGroupBackdropTests: XCTestCase {
    func testEnclosingStripeBackdropMatchesCPUThroughARealChildTarget() async throws {
        let size = IntSize(width: 100, height: 100)
        let renderer = try makeRenderer(size: size)
        defer { detachRenderer(renderer) }

        for drawingGroup in [false, true] {
            var siblings: [ViewNode] = []
            for stripe in 0..<25 {
                siblings.append(
                    ViewNode(
                        frame: Rect(x: 0, y: Double(stripe) * 4, width: 100, height: 2),
                        backgroundColor: .white))
            }
            let panel = ViewNode(
                frame: Rect(x: 20, y: 20, width: 60, height: 60),
                backgroundColor: Color(red: 1, green: 1, blue: 1, alpha: 0.35),
                blurRadius: 12)
            let group = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 100),
                isCompositingGroup: !drawingGroup,
                drawingGroup: drawingGroup ? RetainedDrawingGroup() : nil,
                children: [panel])
            siblings.append(group)
            let root = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 100), children: siblings)
            let scene = ScenePainter.paint(
                root: root, clearColor: .black, surfaceSize: Size(width: 100, height: 100))

            XCTAssertEqual(scene.imageRenderPasses.count, 1)
            let pass = try XCTUnwrap(scene.imageRenderPasses.first)
            XCTAssertEqual(pass.input, .currentTarget)
            XCTAssertTrue(scene.imageResources.isEmpty)
            XCTAssertTrue(pass.scene.imageResources.isEmpty)
            XCTAssertNil(group.cachedCompositingGroupBitmap)
            XCTAssertEqual(scene.layers.flatMap(\.quads).count, 25, "Wallpaper stays outside the child")
            let composite = try XCTUnwrap(scene.layers.flatMap(\.images).first)
            XCTAssertNotNil(pass.currentTargetRegion(for: composite, parentSize: size))

            let actual = try render(scene, using: renderer)
            let reference = assertBlurParity(actual, scene: scene, size: size)
            for bitmap in [actual, reference] {
                XCTAssertLessThan(maxNeighbourDelta(bitmap, rows: 40..<60, columns: 40..<60), 20)
                let center = try XCTUnwrap(bitmap.pixelColor(atX: 50, y: 50))
                XCTAssertGreaterThan(center.red, 0.35, "The panel must contain blurred wallpaper, not tint alone")
                XCTAssertLessThan(center.red, 1)
            }
            XCTAssertEqual(renderer.imageTextureUploadsForTesting, 0)
            XCTAssertEqual(renderer.imageTextureCacheCountForTesting, 0)
        }
    }

    func testTranslucentReplacementAndGroupOpacityMatchIndependentValues() async throws {
        let size = IntSize(width: 24, height: 24)
        let renderer = try makeRenderer(size: size)
        defer { detachRenderer(renderer) }
        let red = Color(red: 1, green: 0, blue: 0, alpha: 0.5)
        let parent = GPUIScene(clearColor: red)
        let baseline = try render(parent, using: renderer)

        var empty = GPUIScene(clearColor: .clear)
        empty.finish()
        for opacity in [Float(0), 0.5, 1] {
            var scene = parent
            let sourceID = scene.registerImageRenderPass(empty, size: size, input: .currentTarget)
            scene.addImage(image(sourceID, width: 24, height: 24, opacity: opacity))
            scene.addImage(image(sourceID, width: 24, height: 24, opacity: opacity))
            scene.finish()
            let actual = try render(scene, using: renderer)
            XCTAssertEqual(actual.pixels, baseline.pixels, "An empty seeded pass is an exact identity")
            assertAlphaParity(actual, scene: scene, size: size)
            assertPremultipliedPixel(actual, x: 12, y: 12, red: 0.5, green: 0, blue: 0, alpha: 0.5)
        }

        var untinted = GPUIScene(clearColor: .clear)
        untinted.addQuad(material(.clear, x: 4, y: 4, width: 16, height: 16, radius: 6))
        untinted.finish()
        var untintedScene = parent
        let untintedID = untintedScene.registerImageRenderPass(untinted, size: size, input: .currentTarget)
        for _ in 0..<2 {
            untintedScene.addImage(image(untintedID, width: 24, height: 24))
        }
        untintedScene.finish()
        let untintedPixels = try render(untintedScene, using: renderer)
        XCTAssertEqual(comparePixels(untintedPixels, baseline, tolerance: 2).matchRatio, 1, accuracy: 0.001)
        assertAlphaParity(untintedPixels, scene: untintedScene, size: size)
        assertPremultipliedPixel(untintedPixels, x: 12, y: 12, red: 0.5, green: 0, blue: 0, alpha: 0.5)

        let tint = Color(red: 0, green: 0, blue: 1, alpha: 0.4)
        var panel = GPUIScene(clearColor: .clear)
        panel.addQuad(material(tint, x: 4, y: 4, width: 16, height: 16, radius: 6))
        panel.finish()
        for opacity in [Float(0), 0.5, 1] {
            var scene = parent
            let sourceID = scene.registerImageRenderPass(panel, size: size, input: .currentTarget)
            scene.addImage(image(sourceID, width: 24, height: 24, opacity: opacity))
            // This ordinary draw must restore source-over after replacement.
            scene.addQuad(quad(Color(red: 0, green: 1, blue: 0, alpha: 0.5), width: 4, height: 4))
            scene.finish()
            let actual = try render(scene, using: renderer)
            assertAlphaParity(actual, scene: scene, size: size)
            let coverage = Double(opacity)
            assertPremultipliedPixel(
                actual, x: 12, y: 12, red: 0.5 - 0.2 * coverage, green: 0,
                blue: 0.4 * coverage, alpha: 0.5 + 0.2 * coverage)
            assertPremultipliedPixel(actual, x: 2, y: 2, red: 0.25, green: 0.5, blue: 0, alpha: 0.75)
            assertSamePixel(actual, baseline, x: 22, y: 22)
        }

        var fullPanel = GPUIScene(clearColor: .clear)
        fullPanel.addQuad(material(tint, width: 24, height: 24, radius: 6))
        fullPanel.finish()
        var clipped = parent
        let clippedID = clipped.registerImageRenderPass(fullPanel, size: size, input: .currentTarget)
        clipped.addImage(roundedImage(clippedID, opacity: 0.5))
        clipped.finish()
        let clippedPixels = try render(clipped, using: renderer)
        assertAlphaParity(clippedPixels, scene: clipped, size: size)
        assertPremultipliedPixel(clippedPixels, x: 12, y: 12, red: 0.4, green: 0, blue: 0.2, alpha: 0.6)
        // The rounded clip's straight left edge crosses the pixel center.
        // Geometric coverage 0.5 times group opacity 0.5 gives k = 0.25.
        assertPremultipliedPixel(clippedPixels, x: 4, y: 12, red: 0.45, green: 0, blue: 0.1, alpha: 0.55)
        assertSamePixel(clippedPixels, baseline, x: 0, y: 0)
        assertSamePixel(clippedPixels, baseline, x: 4, y: 4)

        var patternedParent = GPUIScene(clearColor: .clear)
        for column in 0..<6 {
            let color = column.isMultiple(of: 2) ? red : Color(red: 0, green: 1, blue: 0, alpha: 0.5)
            patternedParent.addQuad(quad(color, x: Float(column * 4), width: 4, height: 24))
        }
        patternedParent.finish()
        let patternedBaseline = try render(patternedParent, using: renderer)
        var unmasked = patternedParent
        let unmaskedID = unmasked.registerImageRenderPass(fullPanel, size: size, input: .currentTarget)
        unmasked.addImage(image(unmaskedID, width: 24, height: 24))
        unmasked.finish()
        let unmaskedPixels = try render(unmasked, using: renderer)
        var masked = patternedParent
        let maskedID = masked.registerImageRenderPass(fullPanel, size: size, input: .currentTarget)
        masked.addImage(roundedImage(maskedID))
        masked.finish()
        let maskedPixels = try render(masked, using: renderer)
        assertAlphaParity(maskedPixels, scene: masked, size: size)
        // Output clipping must not remove the wallpaper that the material samples.
        assertSamePixel(maskedPixels, unmaskedPixels, x: 6, y: 12, tolerance: 2)
        assertSamePixel(maskedPixels, patternedBaseline, x: 0, y: 12)
        assertSamePixel(maskedPixels, patternedBaseline, x: 4, y: 4)
        assertSamePixel(maskedPixels, patternedBaseline, x: 22, y: 12)
    }

    func testRepeatedSourceUsesAndLayerOrderReadFreshParentPixels() async throws {
        let size = IntSize(width: 64, height: 32)
        let childSize = IntSize(width: 16, height: 16)
        let renderer = try makeRenderer(size: size)
        defer { detachRenderer(renderer) }
        let red = Color(red: 1, green: 0, blue: 0, alpha: 0.5)
        let green = Color(red: 0, green: 1, blue: 0, alpha: 0.5)
        var child = GPUIScene(clearColor: .clear)
        child.addQuad(material(Color(red: 0, green: 0, blue: 1, alpha: 0.4), width: 16, height: 16, radius: 6))
        child.finish()

        var separate = GPUIScene(clearColor: .clear)
        separate.addQuad(quad(red, x: 4, y: 4, width: 16, height: 16))
        separate.addQuad(quad(green, x: 28, y: 4, width: 16, height: 16))
        let separateID = separate.registerImageRenderPass(child, size: childSize, input: .currentTarget)
        separate.addImage(image(separateID, x: 4, y: 4, width: 16, height: 16))
        separate.addImage(image(separateID, x: 28, y: 4, width: 16, height: 16))
        separate.finish()
        let imageRuns = separate.presentationOrder().filter { $0.kind == .image }
        XCTAssertEqual(imageRuns.count, 1)
        XCTAssertEqual(imageRuns.first?.range, 0..<2, "The same-ID occurrences are contiguous")
        let separatePixels = try render(separate, using: renderer)
        assertAlphaParity(separatePixels, scene: separate, size: size)
        assertPremultipliedPixel(separatePixels, x: 12, y: 12, red: 0.3, green: 0, blue: 0.4, alpha: 0.7)
        assertPremultipliedPixel(separatePixels, x: 36, y: 12, red: 0, green: 0.3, blue: 0.4, alpha: 0.7)

        var overlap = GPUIScene(clearColor: red)
        let overlapID = overlap.registerImageRenderPass(child, size: childSize, input: .currentTarget)
        for _ in 0..<2 {
            overlap.addImage(image(overlapID, x: 4, y: 4, width: 16, height: 16))
        }
        overlap.finish()
        let overlapPixels = try render(overlap, using: renderer)
        assertAlphaParity(overlapPixels, scene: overlap, size: size)
        assertPremultipliedPixel(overlapPixels, x: 12, y: 12, red: 0.18, green: 0, blue: 0.64, alpha: 0.82)

        overlap.addQuad(quad(Color(red: 0, green: 1, blue: 0), x: 4, y: 4, width: 16, height: 16))
        overlap.addImage(image(overlapID, x: 4, y: 4, width: 16, height: 16))
        overlap.finish()
        let afterInterveningDraw = try render(overlap, using: renderer)
        assertAlphaParity(afterInterveningDraw, scene: overlap, size: size)
        assertPremultipliedPixel(afterInterveningDraw, x: 12, y: 12, red: 0, green: 0.6, blue: 0.4, alpha: 1)

        var layered = GPUIScene(clearColor: .clear)
        let layeredID = layered.registerImageRenderPass(child, size: childSize, input: .currentTarget)
        layered.addImage(image(layeredID, x: 4, y: 4, width: 16, height: 16), toLayer: 1)
        layered.addQuad(quad(red, width: 64, height: 32), toLayer: 0)
        layered.addQuad(quad(green, x: 8, y: 8, width: 8, height: 8), toLayer: 2)
        layered.finish()
        XCTAssertEqual(layered.presentationOrder().map(\.layerIndex), [0, 1, 2])
        XCTAssertEqual(layered.presentationOrder().map(\.kind), [.quad, .image, .quad])
        let layeredPixels = try render(layered, using: renderer)
        assertAlphaParity(layeredPixels, scene: layered, size: size)
        assertPremultipliedPixel(layeredPixels, x: 6, y: 12, red: 0.3, green: 0, blue: 0.4, alpha: 0.7)
        assertPremultipliedPixel(layeredPixels, x: 12, y: 12, red: 0.15, green: 0.5, blue: 0.2, alpha: 0.85)
    }

    func testNestedAndReplayedSourcesPreserveTheirParentNamespace() async throws {
        let size = IntSize(width: 80, height: 48)
        let renderer = try makeRenderer(size: size)
        defer { detachRenderer(renderer) }
        let leafID: Int32 = 44_201
        let parentBitmap = bitmap(red: 0, green: 0, blue: 255)
        let parentAtlas = glyphAtlas(coverage: 255)
        var inner = GPUIScene(clearColor: .clear)
        inner.addQuad(material(Color(red: 1, green: 0, blue: 0, alpha: 0.4), width: 8, height: 8, radius: 4))
        inner.bindImageResource(bitmap(red: 255, green: 0, blue: 0), for: leafID)
        inner.addImage(image(leafID, x: 8, width: 8, height: 8))
        inner.addQuad(
            material(Color(red: 1, green: 1, blue: 1, alpha: 0.35), x: 16, width: 8, height: 8, radius: 4))
        inner.finish()
        var child = GPUIScene(clearColor: .clear)
        child.bindImageResource(bitmap(red: 0, green: 255, blue: 0), for: leafID)
        child.addImage(image(leafID, width: 8, height: 8))
        let innerID = child.registerImageRenderPass(inner, size: IntSize(width: 24, height: 8), input: .currentTarget)
        child.addImage(image(innerID, width: 24, height: 8))
        child.addQuad(quad(Color(red: 1, green: 1, blue: 0), width: 4, height: 8))
        child.addImage(image(leafID, x: 28, width: 8, height: 8))
        child.glyphAtlas = glyphAtlas(coverage: 64)
        child.addGlyph(glyph(x: 28, y: 12))
        child.finish()

        func nestedScene(input: GPUISceneImageRenderPassInput) -> GPUIScene {
            var scene = GPUIScene(clearColor: Color(red: 0, green: 0, blue: 1))
            for column in 0..<8 {
                scene.addQuad(
                    quad(
                        column.isMultiple(of: 2) ? .white : .black,
                        x: Float(32 + column), y: 8, width: 1, height: 8))
            }
            scene.bindImageResource(parentBitmap, for: leafID)
            scene.glyphAtlas = parentAtlas
            scene.addImage(image(leafID, width: 8, height: 8))
            let childID = scene.registerImageRenderPass(child, size: IntSize(width: 40, height: 24), input: input)
            scene.addImage(image(childID, x: 16, y: 8, width: 40, height: 24))
            scene.addImage(image(leafID, x: 60, y: 8, width: 8, height: 8))
            scene.addGlyph(glyph(x: 70, y: 12))
            scene.addQuad(quad(Color(red: 0, green: 1, blue: 0, alpha: 0.5), x: 60, y: 28, width: 12, height: 12))
            scene.finish()
            return scene
        }

        let nested = nestedScene(input: .currentTarget)
        let nestedPixels = try render(nested, using: renderer)
        assertBlurParity(nestedPixels, scene: nested, size: size)
        assertPremultipliedPixel(nestedPixels, x: 4, y: 4, red: 0, green: 0, blue: 1, alpha: 1)
        assertPremultipliedPixel(nestedPixels, x: 22, y: 12, red: 0.4, green: 0.6, blue: 0, alpha: 1)
        assertPremultipliedPixel(nestedPixels, x: 18, y: 12, red: 1, green: 1, blue: 0, alpha: 1)
        assertPremultipliedPixel(nestedPixels, x: 28, y: 12, red: 1, green: 0, blue: 0, alpha: 1)
        assertPremultipliedPixel(nestedPixels, x: 48, y: 12, red: 0, green: 1, blue: 0, alpha: 1)
        assertPremultipliedPixel(nestedPixels, x: 46, y: 22, red: 64.0 / 255, green: 64.0 / 255, blue: 1, alpha: 1)
        assertPremultipliedPixel(nestedPixels, x: 64, y: 12, red: 0, green: 0, blue: 1, alpha: 1)
        assertPremultipliedPixel(nestedPixels, x: 72, y: 14, red: 1, green: 1, blue: 1, alpha: 1)
        assertPremultipliedPixel(nestedPixels, x: 66, y: 34, red: 0, green: 0.5, blue: 0.5, alpha: 1)
        XCTAssertLessThan(maxNeighbourDelta(nestedPixels, rows: 10..<14, columns: 34..<38), 20)

        let isolated = nestedScene(input: .independent)
        let isolatedPixels = try render(isolated, using: renderer)
        assertBlurParity(isolatedPixels, scene: isolated, size: size)
        XCTAssertGreaterThan(
            maxNeighbourDelta(isolatedPixels, rows: 10..<14, columns: 34..<38), 100,
            "A dependent descendant must not bypass an independent ancestor to sample grandparent stripes")

        var replayChild = GPUIScene(clearColor: .clear)
        replayChild.addQuad(
            material(Color(red: 0, green: 1, blue: 0, alpha: 0.4), width: 16, height: 16, radius: 6))
        replayChild.finish()
        var source = GPUIScene(clearColor: .clear)
        let originalID = source.registerImageRenderPass(
            replayChild, size: IntSize(width: 16, height: 16), input: .currentTarget)
        source.addImage(image(originalID, x: 4, y: 4, width: 16, height: 16))
        source.finish()
        let translated = source.translatedPrimitives(by: Point(x: 32, y: 8))
        var replayed = GPUIScene(clearColor: Color(red: 1, green: 0, blue: 0))
        replayed.addQuad(quad(Color(red: 0, green: 0, blue: 1), x: 32, width: 32, height: 32))
        replayed.bindImageResource(bitmap(red: 255, green: 0, blue: 255), for: originalID)
        replayed.addImage(image(originalID, y: 32, width: 8, height: 8))
        XCTAssertEqual(replayed.replay(0..<translated.paintRecordCount, from: translated), .success)
        let rebound = try XCTUnwrap(replayed.imageRenderPasses.first)
        XCTAssertNotEqual(rebound.textureID, originalID)
        XCTAssertEqual(rebound.input, .currentTarget)
        XCTAssertEqual(rebound.scene, replayChild)
        let moved = try XCTUnwrap(replayed.layers.flatMap(\.images).last)
        XCTAssertEqual(moved.screenX, 36)
        XCTAssertEqual(moved.screenY, 12)
        XCTAssertNotNil(rebound.currentTargetRegion(for: moved, parentSize: size))
        replayed.addImage(image(originalID, x: 64, y: 32, width: 8, height: 8))
        replayed.glyphAtlas = parentAtlas
        replayed.addGlyph(glyph(x: 74, y: 34))
        replayed.finish()
        let replayedPixels = try render(replayed, using: renderer)
        assertAlphaParity(replayedPixels, scene: replayed, size: size)
        assertPremultipliedPixel(replayedPixels, x: 44, y: 20, red: 0, green: 0.4, blue: 0.6, alpha: 1)
        assertPremultipliedPixel(replayedPixels, x: 12, y: 12, red: 1, green: 0, blue: 0, alpha: 1)
        assertPremultipliedPixel(replayedPixels, x: 68, y: 36, red: 1, green: 0, blue: 1, alpha: 1)
        assertPremultipliedPixel(replayedPixels, x: 76, y: 36, red: 1, green: 1, blue: 1, alpha: 1)
    }

    func testAlternatingOddExtentCropsDoNotReadStaleTexels() async throws {
        let size = IntSize(width: 96, height: 96)
        let renderer = try makeRenderer(size: size)
        defer { detachRenderer(renderer) }
        let extents = [
            IntSize(width: 63, height: 47), IntSize(width: 5, height: 9),
            IntSize(width: 31, height: 17), IntSize(width: 5, height: 9),
        ]
        for (frame, extent) in extents.enumerated() {
            let sentinel =
                frame.isMultiple(of: 2) ? Color(red: 1, green: 0, blue: 1) : Color(red: 0, green: 1, blue: 0)
            var parent = GPUIScene(clearColor: sentinel)
            for column in 0..<Int(extent.width) {
                let level = Float(column % 5) / 4
                parent.addQuad(
                    quad(
                        Color(red: level, green: 1 - level, blue: 0.5),
                        x: Float(8 + column), y: 8, width: 1, height: Float(extent.height)))
            }
            parent.finish()
            let baseline = try render(parent, using: renderer)
            var child = GPUIScene(clearColor: .clear)
            child.addQuad(
                material(
                    Color(red: 1, green: 1, blue: 1, alpha: 0.35),
                    width: Float(extent.width), height: Float(extent.height), radius: 220))
            child.finish()
            let plan = BlurPassPlan(radius: 220, regionWidth: Int(extent.width), regionHeight: Int(extent.height))
            XCTAssertEqual(plan.halvingPassCount, 2)
            var scene = parent
            let sourceID = scene.registerImageRenderPass(child, size: extent, input: .currentTarget)
            let composite = image(sourceID, x: 8, y: 8, width: Float(extent.width), height: Float(extent.height))
            scene.addImage(composite)
            scene.finish()
            let source = try XCTUnwrap(scene.imageRenderPasses.first)
            XCTAssertNotNil(source.currentTargetRegion(for: composite, parentSize: size))
            let actual = try render(scene, using: renderer)
            let reference = assertBlurParity(actual, scene: scene, size: size)
            let roi = (x: 8, y: 8, width: Int(extent.width), height: Int(extent.height))
            // A whole-frame ratio could conceal every wrong texel in a 5x9 crop.
            let regionReport = comparePixels(crop(actual, to: roi), crop(reference, to: roi), tolerance: 4)
            XCTAssertGreaterThan(regionReport.matchRatio, 0.995, "Frame \(frame): odd crop mismatch")
            assertUnchangedOutside(actual, baseline, rect: roi)
            XCTAssertEqual(renderer.imageTextureUploadsForTesting, 0)
            XCTAssertEqual(renderer.imageTextureCacheCountForTesting, 0)
        }
    }

    func testContextualChildFailureRestoresAndReleasesParentState() async throws {
        let size = IntSize(width: 80, height: 48)
        let renderer = try makeRenderer(size: size)
        defer { detachRenderer(renderer) }
        let leafID: Int32 = 44_601
        let leaf = bitmap(red: 0, green: 0, blue: 255)
        let atlas = glyphAtlas(coverage: 255)
        let backdrop = Color(red: 1, green: 0, blue: 0, alpha: 0.5)
        var empty = GPUIScene(clearColor: .clear)
        empty.finish()
        var recovery = GPUIScene(clearColor: backdrop)
        recovery.bindImageResource(leaf, for: leafID)
        recovery.glyphAtlas = atlas
        let recoveryID = recovery.registerImageRenderPass(
            empty, size: IntSize(width: 8, height: 8), input: .currentTarget)
        recovery.addImage(image(recoveryID, x: 16, y: 8, width: 8, height: 8))
        recovery.addImage(image(leafID, width: 8, height: 8))
        recovery.addGlyph(glyph(x: 60, y: 8))
        recovery.addQuad(quad(Color(red: 0, green: 0, blue: 1, alpha: 0.4), x: 64, y: 32, width: 12, height: 12))
        recovery.finish()
        // Warm the replacement shader/blend and every persistent primitive family.
        _ = try render(recovery, using: renderer)
        let warmedObjects = renderer.liveCOMObjectCountForTesting

        var child = GPUIScene(clearColor: .clear)
        child.addImage(image(leafID, width: 8, height: 8))
        child.finish()
        var invalid = GPUIScene(clearColor: backdrop)
        // The parent binding must not satisfy the child's missing binding.
        invalid.bindImageResource(leaf, for: leafID)
        invalid.glyphAtlas = atlas
        let sourceID = invalid.registerImageRenderPass(child, size: IntSize(width: 8, height: 8), input: .currentTarget)
        invalid.addImage(image(sourceID, x: 16, y: 8, width: 8, height: 8))
        invalid.finish()
        XCTAssertTrue(invalid.validate().isEmpty)
        renderer.bindResources(for: invalid)
        XCTAssertNoThrow(
            try D3D11BatchRenderer.makeRenderPlan(for: invalid, cachedResources: renderer.cachedResourcesForTesting))
        XCTAssertThrowsError(try renderer.render(scene: invalid)) { error in
            let failure = error as? BatchRendererError
            XCTAssertEqual(failure?.operation, "Resolve image resources")
            XCTAssertEqual(failure?.presentationFailureKind, .sceneContent)
        }
        XCTAssertEqual(renderer.directlyOwnedImagePassTargetCountForTesting, 0)
        XCTAssertEqual(renderer.liveCOMObjectCountForTesting, warmedObjects)
        let afterFailure = try renderer.readOffscreenPixels()
        XCTAssertEqual(afterFailure.width, size.width)
        XCTAssertEqual(afterFailure.height, size.height)
        assertPremultipliedPixel(afterFailure, x: 70, y: 38, red: 0.5, green: 0, blue: 0, alpha: 0.5)

        let recovered = try render(recovery, using: renderer)
        let reference = GPUIRawSceneRasterizer.rasterize(recovery, size: size).premultipliedAlpha()
        XCTAssertEqual(comparePixels(recovered, reference, tolerance: 2).matchRatio, 1)
        assertPremultipliedPixel(recovered, x: 4, y: 4, red: 0, green: 0, blue: 1, alpha: 1)
        assertPremultipliedPixel(recovered, x: 62, y: 10, red: 1, green: 1, blue: 1, alpha: 1)
        assertPremultipliedPixel(recovered, x: 70, y: 38, red: 0.3, green: 0, blue: 0.4, alpha: 0.7)
        XCTAssertEqual(renderer.liveCOMObjectCountForTesting, warmedObjects)
    }

    func testContextualMaterialDegradationStaysLatchedUntilResize() async throws {
        let size = IntSize(width: 32, height: 32)
        let renderer = try makeRenderer(size: size)
        defer { detachRenderer(renderer) }
        var child = GPUIScene(clearColor: .clear)
        child.addQuad(
            material(Color(red: 1, green: 1, blue: 1, alpha: 0.4), x: 4, y: 4, width: 16, height: 16, radius: 4))
        child.finish()
        var scene = GPUIScene(clearColor: .black)
        for column in 0..<24 {
            scene.addQuad(
                quad(
                    column.isMultiple(of: 2) ? .white : .black,
                    x: Float(4 + column), y: 4, width: 1, height: 24))
        }
        let sourceID = scene.registerImageRenderPass(child, size: IntSize(width: 24, height: 24), input: .currentTarget)
        scene.addImage(image(sourceID, x: 4, y: 4, width: 24, height: 24))
        scene.finish()

        renderer.failBlurredQuadsForTesting = true
        let fallback = try render(scene, using: renderer)
        XCTAssertTrue(renderer.blurDegradedForTesting)
        XCTAssertFalse(renderer.blurEngineOwnsResourcesForTesting)
        let degradedObjects = renderer.liveCOMObjectCountForTesting
        renderer.failBlurredQuadsForTesting = false
        for _ in 0..<3 {
            let repeated = try render(scene, using: renderer)
            XCTAssertTrue(renderer.blurDegradedForTesting)
            XCTAssertFalse(renderer.blurEngineOwnsResourcesForTesting)
            XCTAssertEqual(repeated.pixels, fallback.pixels)
            XCTAssertEqual(renderer.liveCOMObjectCountForTesting, degradedObjects)
        }

        let resized = IntSize(width: 40, height: 32)
        try renderer.resize(to: resized)
        XCTAssertFalse(renderer.blurDegradedForTesting)
        let recovered = try render(scene, using: renderer)
        XCTAssertFalse(renderer.blurDegradedForTesting)
        XCTAssertTrue(renderer.blurEngineOwnsResourcesForTesting)
        let recoveredOriginal = crop(recovered, to: (x: 0, y: 0, width: Int(size.width), height: Int(size.height)))
        XCTAssertEqual(recoveredOriginal.width, fallback.width)
        XCTAssertEqual(recoveredOriginal.height, fallback.height)
        XCTAssertLessThan(comparePixels(recoveredOriginal, fallback, tolerance: 4).matchRatio, 0.98)
        XCTAssertLessThan(maxNeighbourDelta(recovered, rows: 12..<20, columns: 12..<20), 20)
        assertBlurParity(recovered, scene: scene, size: resized)
        XCTAssertEqual(renderer.imageTextureUploadsForTesting, 0)
        XCTAssertEqual(renderer.imageTextureCacheCountForTesting, 0)
    }

    func testRepeatedContextualPassesDoNotUploadBakedGroupBitmaps() async throws {
        let size = IntSize(width: 48, height: 32)
        let renderer = try makeRenderer(size: size)
        defer { detachRenderer(renderer) }
        let leafID: Int32 = 44_801
        let leaf = bitmap(red: 255, green: 200, blue: 0)
        var child = GPUIScene(clearColor: .clear)
        child.addQuad(material(Color(red: 0, green: 0, blue: 1, alpha: 0.4), width: 16, height: 16, radius: 6))
        child.bindImageResource(leaf, for: leafID)
        child.addImage(image(leafID, x: 20, y: 8, width: 8, height: 8))
        child.finish()

        func frame(green: Bool) -> GPUIScene {
            let backdrop = Color(red: green ? 0 : 1, green: green ? 1 : 0, blue: 0, alpha: 0.5)
            var scene = GPUIScene(clearColor: backdrop)
            scene.bindImageResource(leaf, for: leafID)
            let sourceID = scene.registerImageRenderPass(
                child, size: IntSize(width: 32, height: 24), input: .currentTarget)
            scene.addImage(image(sourceID, x: 4, y: 4, width: 32, height: 24))
            scene.addImage(image(leafID, x: 40, y: 4, width: 8, height: 8))
            scene.finish()
            return scene
        }

        let initial = frame(green: false)
        var previous = try render(initial, using: renderer)
        assertAlphaParity(previous, scene: initial, size: size)
        assertPremultipliedPixel(previous, x: 12, y: 12, red: 0.3, green: 0, blue: 0.4, alpha: 0.7)
        let warmedObjects = renderer.liveCOMObjectCountForTesting
        let identity = try XCTUnwrap(renderer.imageTextureIdentityForTesting(for: leafID))
        XCTAssertEqual(renderer.imageTextureUploadsForTesting, 1)
        XCTAssertEqual(renderer.imageTextureCacheCountForTesting, 1)
        for index in 0..<8 {
            let green = index.isMultiple(of: 2)
            let scene = frame(green: green)
            XCTAssertEqual(scene.imageResources.count, 1)
            XCTAssertEqual(scene.imageResources.first?.bitmap.contentKey, leaf.contentKey)
            let pass = try XCTUnwrap(scene.imageRenderPasses.first)
            XCTAssertEqual(pass.input, .currentTarget)
            XCTAssertEqual(pass.scene.imageResources.count, 1)
            XCTAssertEqual(pass.scene.imageResources.first?.bitmap.contentKey, leaf.contentKey)
            let actual = try render(scene, using: renderer)
            assertAlphaParity(actual, scene: scene, size: size)
            assertPremultipliedPixel(
                actual, x: 12, y: 12, red: green ? 0 : 0.3, green: green ? 0.3 : 0, blue: 0.4, alpha: 0.7)
            assertPremultipliedPixel(actual, x: 44, y: 8, red: 1, green: 200.0 / 255, blue: 0, alpha: 1)
            XCTAssertNotEqual(pixelBytes(actual, x: 12, y: 12), pixelBytes(previous, x: 12, y: 12))
            XCTAssertEqual(renderer.imageTextureUploadsForTesting, 1, "Only the immutable leaf is uploaded")
            XCTAssertEqual(renderer.imageTextureCacheCountForTesting, 1)
            let currentIdentity = try XCTUnwrap(renderer.imageTextureIdentityForTesting(for: leafID))
            XCTAssertEqual(currentIdentity.texture, identity.texture)
            XCTAssertEqual(currentIdentity.srv, identity.srv)
            XCTAssertEqual(renderer.liveCOMObjectCountForTesting, warmedObjects)
            previous = actual
        }
    }

    func testReplayedBackdropSourcesRejectCapacityAndRecover() async throws {
        let limit = 1_024
        let occurrenceCount = limit + 1
        XCTAssertEqual(GPUISceneLimits.maxImageRenderPassCount, limit)
        XCTAssertLessThan(occurrenceCount * 4, GPUISceneLimits.maxImageRenderPassTotalPixels)
        let size = IntSize(width: 64, height: 66)
        let childSize = IntSize(width: 2, height: 2)
        let renderer = try makeRenderer(size: size)
        defer { detachRenderer(renderer) }
        let red = Color(red: 1, green: 0, blue: 0)
        var child = GPUIScene(clearColor: .clear)
        child.addQuad(quad(red, width: 2, height: 2))
        child.finish()

        var recorded = GPUIScene(clearColor: .clear)
        let recordedID = recorded.registerImageRenderPass(child, size: childSize, input: .currentTarget)
        for index in 0..<occurrenceCount {
            recorded.addImage(
                image(recordedID, x: Float((index % 32) * 2), y: Float((index / 32) * 2), width: 2, height: 2))
        }
        recorded.finish()
        XCTAssertEqual(recorded.paintRecordCount, occurrenceCount)

        // Warm the replacement pipeline with a reduced replay on the same
        // renderer used by both failures and the final recovery frame.
        var recovery = GPUIScene(clearColor: Color(red: 0, green: 0, blue: 1, alpha: 0.5))
        XCTAssertEqual(recovery.replay(0..<2, from: recorded), .success)
        recovery.addQuad(quad(Color(red: 0, green: 1, blue: 0, alpha: 0.5), x: 32, y: 32, width: 8, height: 8))
        recovery.finish()
        XCTAssertEqual(recovery.imageRenderPasses.count, 1)
        XCTAssertEqual(recovery.layers.flatMap(\.images).count, 2)
        let warmedPixels = try render(recovery, using: renderer)
        let warmedObjects = renderer.liveCOMObjectCountForTesting
        XCTAssertEqual(renderer.lastDrawCallCount, 5)
        XCTAssertEqual(renderer.lastDrawnInstanceCount, 5)

        var declared = GPUIScene(clearColor: .black)
        for index in 0..<occurrenceCount {
            let sourceID = declared.registerImageRenderPass(child, size: childSize, input: .currentTarget)
            declared.addImage(
                image(sourceID, x: Float((index % 32) * 2), y: Float((index / 32) * 2), width: 2, height: 2))
        }
        declared.finish()
        XCTAssertEqual(declared.imageRenderPasses.count, occurrenceCount)
        XCTAssertTrue(declared.imageRenderPasses.allSatisfy { $0.input == .currentTarget && $0.size == childSize })
        XCTAssertThrowsError(try D3D11BatchRenderer.makeRenderPlan(for: declared)) { error in
            let failure = error as? BatchRendererError
            XCTAssertEqual(failure?.operation, "Validate scene")
            XCTAssertEqual(failure?.presentationFailureKind, .sceneContent)
        }
        renderer.bindResources(for: declared)
        XCTAssertThrowsError(try renderer.render(scene: declared)) { error in
            let failure = error as? BatchRendererError
            XCTAssertEqual(failure?.operation, "Validate scene")
            XCTAssertEqual(failure?.presentationFailureKind, .sceneContent)
        }
        XCTAssertEqual(renderer.lastDrawCallCount, 0)
        XCTAssertEqual(renderer.lastDrawnInstanceCount, 0)
        XCTAssertEqual(renderer.directlyOwnedImagePassTargetCountForTesting, 0)
        XCTAssertEqual(renderer.liveCOMObjectCountForTesting, warmedObjects)
        let afterDeclaredFailure = try renderer.readOffscreenPixels()
        XCTAssertEqual(afterDeclaredFailure.width, warmedPixels.width)
        XCTAssertEqual(afterDeclaredFailure.height, warmedPixels.height)
        XCTAssertEqual(
            afterDeclaredFailure.pixels, warmedPixels.pixels, "Structural rejection must precede clear and draw")

        // Replay the whole range once: replaying separate wrappers would
        // remap their IDs into 1,025 declarations and only test the gate above.
        var replayed = GPUIScene(clearColor: .black)
        XCTAssertEqual(replayed.replay(0..<recorded.paintRecordCount, from: recorded), .success)
        replayed.finish()
        XCTAssertEqual(replayed.imageRenderPasses.count, 1)
        let replayedPass = try XCTUnwrap(replayed.imageRenderPasses.first)
        XCTAssertEqual(replayedPass.input, .currentTarget)
        let images = replayed.layers.flatMap(\.images)
        XCTAssertEqual(images.count, occurrenceCount)
        XCTAssertTrue(images.allSatisfy { $0.textureID == replayedPass.textureID })
        let runs = replayed.presentationOrder().filter { $0.kind == .image }
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(try XCTUnwrap(runs.first).range, 0..<occurrenceCount)
        XCTAssertTrue(replayed.validate().isEmpty, "The declared graph has only one four-pixel source")
        XCTAssertNoThrow(try D3D11BatchRenderer.makeRenderPlan(for: replayed))
        renderer.bindResources(for: replayed)
        XCTAssertThrowsError(try renderer.render(scene: replayed)) { error in
            let failure = error as? BatchRendererError
            XCTAssertEqual(failure?.operation, "Execute image render pass")
            XCTAssertEqual(failure?.presentationFailureKind, .sceneContent)
        }
        // The counters advance immediately before each draw, including
        // partial frames: one child quad and one replacement per admitted use.
        XCTAssertEqual(renderer.lastDrawCallCount, limit * 2)
        XCTAssertEqual(renderer.lastDrawnInstanceCount, limit * 2)
        XCTAssertEqual(renderer.directlyOwnedImagePassTargetCountForTesting, 0)
        XCTAssertEqual(renderer.liveCOMObjectCountForTesting, warmedObjects)
        let partial = try renderer.readOffscreenPixels()
        XCTAssertEqual(partial.width, size.width)
        XCTAssertEqual(partial.height, size.height)
        var prefix = GPUIScene(clearColor: .black)
        // Each pass draws its own 2x2 primitive. A merged 64x64 reference
        // changes the signed-distance derivative coverage at its corner.
        for row in 0..<32 {
            for column in 0..<32 {
                prefix.addQuad(quad(red, x: Float(column * 2), y: Float(row * 2), width: 2, height: 2))
            }
        }
        prefix.finish()
        XCTAssertEqual(prefix.paintRecordCount, limit)
        let prefixPixels = GPUIRawSceneRasterizer.rasterize(prefix, size: size).premultipliedAlpha()
        // Independently describe every expected BGRA pixel without another
        // renderer or the replayed scene: opaque red, then two black rows.
        var expectedPrefixPixels = Data()
        expectedPrefixPixels.reserveCapacity(64 * 66 * 4)
        for row in 0..<66 {
            let pixel: [UInt8] = row < 64 ? [0, 0, 255, 255] : [0, 0, 0, 255]
            for _ in 0..<64 { expectedPrefixPixels.append(contentsOf: pixel) }
        }
        XCTAssertEqual(prefixPixels.width, 64)
        XCTAssertEqual(prefixPixels.height, 66)
        XCTAssertEqual(prefixPixels.bytesPerRow, 64 * 4)
        XCTAssertEqual(prefixPixels.pixels, expectedPrefixPixels)
        XCTAssertEqual(comparePixels(partial, prefixPixels, tolerance: 2).matchRatio, 1)
        assertPremultipliedPixel(partial, x: 63, y: 63, red: 1, green: 0, blue: 0, alpha: 1)
        assertPremultipliedPixel(partial, x: 1, y: 65, red: 0, green: 0, blue: 0, alpha: 1)

        let recovered = try render(recovery, using: renderer)
        XCTAssertEqual(recovered.width, warmedPixels.width)
        XCTAssertEqual(recovered.height, warmedPixels.height)
        XCTAssertEqual(recovered.pixels, warmedPixels.pixels)
        assertAlphaParity(recovered, scene: recovery, size: size)
        assertPremultipliedPixel(recovered, x: 1, y: 1, red: 1, green: 0, blue: 0, alpha: 1)
        assertPremultipliedPixel(recovered, x: 3, y: 1, red: 1, green: 0, blue: 0, alpha: 1)
        assertPremultipliedPixel(recovered, x: 10, y: 10, red: 0, green: 0, blue: 0.5, alpha: 0.5)
        assertPremultipliedPixel(recovered, x: 35, y: 35, red: 0, green: 0.5, blue: 0.25, alpha: 0.75)
        XCTAssertEqual(renderer.lastDrawCallCount, 5)
        XCTAssertEqual(renderer.lastDrawnInstanceCount, 5)
        XCTAssertEqual(renderer.liveCOMObjectCountForTesting, warmedObjects)
        XCTAssertEqual(renderer.imageTextureUploadsForTesting, 0)
        XCTAssertEqual(renderer.imageTextureCacheCountForTesting, 0)
        XCTAssertFalse(renderer.blurEngineOwnsResourcesForTesting)
    }

    private func makeRenderer(size: IntSize) throws -> D3D11BatchRenderer {
        let renderer = D3D11BatchRenderer()
        do {
            try renderer.attachOffscreen(size: size, driver: .warpFirst)
        } catch {
            renderer.detach()
            throw XCTSkip("D3D11 batch renderer unavailable on this machine: \(error)")
        }
        return renderer
    }

    private func detachRenderer(
        _ renderer: D3D11BatchRenderer, file: StaticString = #filePath, line: UInt = #line
    ) {
        renderer.detach()
        XCTAssertEqual(renderer.directlyOwnedImagePassTargetCountForTesting, 0, file: file, line: line)
        XCTAssertEqual(renderer.liveCOMObjectCountForTesting, 0, file: file, line: line)
        XCTAssertFalse(renderer.blurEngineOwnsResourcesForTesting, file: file, line: line)
    }

    private func render(
        _ scene: GPUIScene, using renderer: D3D11BatchRenderer,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> BitmapSurface {
        XCTAssertTrue(scene.validate().isEmpty, file: file, line: line)
        renderer.bindResources(for: scene)
        try renderer.render(scene: scene)
        // This counts directly owned scratch targets, not COM reference counts
        // or driver/process lifetime. Readback owns its separate staging texture.
        XCTAssertEqual(renderer.directlyOwnedImagePassTargetCountForTesting, 0, file: file, line: line)
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
        return expected
    }

    private func assertAlphaParity(
        _ actual: BitmapSurface, scene: GPUIScene, size: IntSize,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let expected = GPUIRawSceneRasterizer.rasterize(scene, size: size).premultipliedAlpha()
        XCTAssertEqual(actual.width, expected.width, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, file: file, line: line)
        let report = comparePixels(actual, expected, tolerance: 2)
        XCTAssertEqual(
            report.matchRatio, 1, accuracy: 0.001,
            "Premultiplied mismatch: max delta \(report.maxChannelDelta), first \(String(describing: report.firstFailure))",
            file: file, line: line)
    }

    private func assertPremultipliedPixel(
        _ bitmap: BitmapSurface, x: Int, y: Int,
        red: Double, green: Double, blue: Double, alpha: Double,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(bitmap.format.alphaMode, .premultiplied, file: file, line: line)
        let actual = pixelBytes(bitmap, x: x, y: y)
        XCTAssertEqual(actual.count, 4, file: file, line: line)
        guard actual.count == 4 else { return }
        for (channel, expected) in [blue, green, red, alpha].enumerated() {
            XCTAssertEqual(Double(actual[channel]) / 255, expected, accuracy: 0.01, file: file, line: line)
        }
        if alpha > 0, let straight = bitmap.pixelColor(atX: x, y: y) {
            XCTAssertEqual(Double(straight.red), red / alpha, accuracy: 0.01, file: file, line: line)
            XCTAssertEqual(Double(straight.green), green / alpha, accuracy: 0.01, file: file, line: line)
            XCTAssertEqual(Double(straight.blue), blue / alpha, accuracy: 0.01, file: file, line: line)
            XCTAssertEqual(Double(straight.alpha), alpha, accuracy: 0.01, file: file, line: line)
        }
    }

    private func pixelBytes(_ bitmap: BitmapSurface, x: Int, y: Int) -> [UInt8] {
        guard x >= 0, y >= 0, x < Int(bitmap.width), y < Int(bitmap.height) else { return [] }
        let offset = y * Int(bitmap.bytesPerRow) + x * 4
        guard offset + 4 <= bitmap.pixels.count else { return [] }
        return Array(bitmap.pixels[offset..<(offset + 4)])
    }

    private func assertSamePixel(
        _ actual: BitmapSurface, _ expected: BitmapSurface, x: Int, y: Int, tolerance: Int = 0,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let a = pixelBytes(actual, x: x, y: y)
        let b = pixelBytes(expected, x: x, y: y)
        XCTAssertEqual(a.count, 4, file: file, line: line)
        XCTAssertEqual(b.count, 4, file: file, line: line)
        guard a.count == 4, b.count == 4 else { return }
        for channel in 0..<4 {
            XCTAssertLessThanOrEqual(abs(Int(a[channel]) - Int(b[channel])), tolerance, file: file, line: line)
        }
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

    private func crop(_ bitmap: BitmapSurface, to rect: (x: Int, y: Int, width: Int, height: Int)) -> BitmapSurface {
        var bytes = Data()
        bytes.reserveCapacity(rect.width * rect.height * 4)
        for row in rect.y..<(rect.y + rect.height) {
            let start = row * Int(bitmap.bytesPerRow) + rect.x * 4
            bytes.append(contentsOf: bitmap.pixels[start..<(start + rect.width * 4)])
        }
        return BitmapSurface(
            width: Int32(rect.width), height: Int32(rect.height), bytesPerRow: Int32(rect.width * 4),
            pixels: bytes, format: bitmap.format)
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
            changedPixels, 0, "The copy/composite changed pixels outside its admitted crop", file: file, line: line)
    }

    private func image(
        _ textureID: Int32, x: Float = 0, y: Float = 0, width: Float, height: Float, opacity: Float = 1
    ) -> ImagePrimitive {
        ImagePrimitive(screenX: x, screenY: y, screenW: width, screenH: height, opacity: opacity, textureID: textureID)
    }

    private func roundedImage(_ textureID: Int32, opacity: Float = 1) -> ImagePrimitive {
        ImagePrimitive(
            screenW: 24, screenH: 24, opacity: opacity,
            clipX: 4.5, clipY: 4, clipWidth: 16, clipHeight: 16, clipCornerRadius: 4, textureID: textureID)
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
        var value = quad(tint, x: x, y: y, width: width, height: height)
        value.blurRadius = radius
        return value
    }

    private func glyph(x: Float, y: Float) -> GlyphPrimitive {
        GlyphPrimitive(
            screenX: x, screenY: y, screenW: 4, screenH: 4,
            atlasU0: 0, atlasV0: 0, atlasU1: 1, atlasV1: 1,
            colorR: 1, colorG: 1, colorB: 1, colorA: 1)
    }

    private func glyphAtlas(coverage: UInt8) -> GlyphAtlasSnapshot {
        GlyphAtlasSnapshot(
            width: 4, height: 4, pixels: Data(repeating: coverage, count: 4 * 4 * 4),
            contentVersion: RenderContentVersion.next(), update: .full)
    }

    private func bitmap(red: UInt8, green: UInt8, blue: UInt8) -> BitmapSurface {
        var bytes = [UInt8]()
        for _ in 0..<64 { bytes.append(contentsOf: [blue, green, red, 255]) }
        return BitmapSurface(width: 8, height: 8, bytesPerRow: 32, pixels: Data(bytes))
    }
}
