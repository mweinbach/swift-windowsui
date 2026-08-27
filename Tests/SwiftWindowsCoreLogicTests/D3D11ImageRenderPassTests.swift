import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsUI
import XCTest

@testable import SwiftWindowsRendererD3D11

/// Recursive scene passes must preserve their own resources and return the
/// parent renderer to the same target, viewport and bindings after each pass.
@MainActor
final class D3D11ImageRenderPassTests: XCTestCase {
    func testRenderPlanResolvesVirtualImageWithoutABitmapBinding() async throws {
        let size = IntSize(width: 16, height: 16)
        var child = GPUIScene(clearColor: .red)
        child.finish()
        var scene = GPUIScene()
        let textureID = scene.registerImageRenderPass(child, size: size, colorEffects: [.contrast(1.2)])
        scene.addImage(image(textureID, width: 16, height: 16))
        scene.finish()

        XCTAssertTrue(scene.imageResources.isEmpty, "A render pass must not need a CPU bitmap binding")
        let plan = try D3D11BatchRenderer.makeRenderPlan(for: scene)
        XCTAssertEqual(
            plan.steps,
            [.images(layerIndex: 0, range: 0..<1, textureID: textureID)])
    }

    func testOrderedEffectsOperateOnTheCompositedChild() async throws {
        let childSize = IntSize(width: 16, height: 16)
        var child = GPUIScene(clearColor: .clear)
        child.addQuad(quad(Color(red: 0.2, green: 0.4, blue: 0.6), width: 16, height: 16))
        child.addQuad(quad(Color(red: 0.8, green: 0.2, blue: 0.1, alpha: 0.5), width: 16, height: 16))
        child.finish()

        var scene = GPUIScene(clearColor: .black)
        let brightnessFirst = scene.registerImageRenderPass(
            child, size: childSize, colorEffects: [.brightness(0.3), .contrast(2)])
        let contrastFirst = scene.registerImageRenderPass(
            child, size: childSize, colorEffects: [.contrast(2), .brightness(0.3)])
        XCTAssertNotEqual(brightnessFirst, contrastFirst)
        scene.addImage(image(brightnessFirst, width: 16, height: 16))
        scene.addImage(image(contrastFirst, x: 24, width: 16, height: 16))
        scene.finish()

        let pixels = try assertParity(scene, size: IntSize(width: 40, height: 16))
        // Source-over yields (0.5, 0.3, 0.35). Saturation at each filter
        // boundary makes this differ from filtering the two quads first.
        assertPixel(pixels, x: 8, y: 8, red: 255, green: 178.5, blue: 204)
        assertPixel(pixels, x: 32, y: 8, red: 204, green: 102, blue: 127.5)
        assertPixel(pixels, x: 20, y: 8, red: 0, green: 0, blue: 0)
    }

    func testFilterChainIncludesGlyphPathImageAndShadowContent() async throws {
        let childSize = IntSize(width: 64, height: 64)
        var child = GPUIScene(clearColor: Color(red: 0.12, green: 0.16, blue: 0.2))
        child.addShadow(
            ShadowPrimitive(
                x: 8, y: 8, width: 16, height: 16,
                colorR: 0.6, colorG: 0.2, colorB: 0.1, colorA: 0.8,
                blurRadius: 3, offsetX: 2, offsetY: 2))
        child.addQuad(quad(Color(red: 0.8, green: 0.2, blue: 0.4), x: 8, y: 8, width: 16, height: 16))
        child.glyphAtlas = glyphAtlas(coverage: 255)
        child.addGlyph(glyph(x: 40, y: 8))
        child.addPath(
            PathPrimitive(
                elements: [
                    .moveTo(Point(x: 8, y: 56)),
                    .lineTo(Point(x: 16, y: 36)),
                    .lineTo(Point(x: 24, y: 56)),
                    .close,
                ],
                bounds: Rect(x: 8, y: 36, width: 16, height: 20),
                fillColor: Color(red: 0.2, green: 0.6, blue: 0.9)),
            toLayer: 0)
        let sourceID: Int32 = 42_101
        child.bindImageResource(bitmap(red: 64, green: 128, blue: 192), for: sourceID)
        child.addImage(image(sourceID, x: 40, y: 40, width: 8, height: 8))
        child.finish()

        var scene = GPUIScene(clearColor: .black)
        let textureID = scene.registerImageRenderPass(
            child, size: childSize,
            colorEffects: [.saturation(0.6), .hueRotation(.pi / 5), .grayscale(1), .colorInvert, .brightness(0.05)])
        scene.addImage(image(textureID, x: 8, y: 8, width: 64, height: 64))
        scene.finish()

        let pixels = try assertParity(scene, size: IntSize(width: 80, height: 80))
        // Samples cover the quad, glyph, path, image and exposed shadow.
        // Grayscale near the end of the chain makes every family neutral.
        for (x, y) in [(24, 24), (50, 18), (24, 58), (52, 52), (34, 24)] {
            let offset = y * Int(pixels.bytesPerRow) + x * 4
            let red = Double(pixels.pixels[offset + 2])
            XCTAssertEqual(Double(pixels.pixels[offset]), red, accuracy: 2)
            XCTAssertEqual(Double(pixels.pixels[offset + 1]), red, accuracy: 2)
        }
        assertPixel(pixels, x: 50, y: 18, red: 12.75, green: 12.75, blue: 12.75)
    }

    func testNestedPassesScopeTextureIDsAndRestoreParentTargetAndViewport() async throws {
        let sourceID: Int32 = 42_201
        var grandchild = GPUIScene(clearColor: .clear)
        grandchild.bindImageResource(bitmap(red: 255, green: 0, blue: 0), for: sourceID)
        grandchild.addImage(image(sourceID, width: 8, height: 8))
        grandchild.finish()

        var child = GPUIScene(clearColor: .black)
        child.bindImageResource(bitmap(red: 0, green: 255, blue: 0), for: sourceID)
        child.addImage(image(sourceID, width: 8, height: 8))
        let grandchildID = child.registerImageRenderPass(grandchild, size: IntSize(width: 8, height: 8))
        child.addImage(image(grandchildID, x: 12, y: 4, width: 8, height: 8))
        child.finish()

        var scene = GPUIScene(clearColor: .black)
        scene.bindImageResource(bitmap(red: 0, green: 0, blue: 255), for: sourceID)
        scene.addImage(image(sourceID, width: 8, height: 8))
        let childID = scene.registerImageRenderPass(child, size: IntSize(width: 24, height: 16))
        scene.addImage(image(childID, x: 16, y: 8, width: 24, height: 16))
        scene.addImage(image(sourceID, x: 48, width: 8, height: 8))
        scene.addQuad(quad(Color(red: 1, green: 1, blue: 0, alpha: 1), x: 64, y: 24, width: 12, height: 12))
        scene.finish()

        let pixels = try assertParity(scene, size: IntSize(width: 80, height: 40))
        assertPixel(pixels, x: 4, y: 4, red: 0, green: 0, blue: 255)
        assertPixel(pixels, x: 20, y: 12, red: 0, green: 255, blue: 0)
        assertPixel(pixels, x: 32, y: 16, red: 255, green: 0, blue: 0)
        assertPixel(pixels, x: 52, y: 4, red: 0, green: 0, blue: 255)
        assertPixel(pixels, x: 70, y: 30, red: 255, green: 255, blue: 0)
    }

    func testChildAtlasDoesNotReplaceTheParentAtlas() async throws {
        var child = GPUIScene(clearColor: .black)
        child.glyphAtlas = glyphAtlas(coverage: 64)
        child.addGlyph(glyph(x: 2, y: 2))
        child.finish()

        var scene = GPUIScene(clearColor: .black)
        scene.glyphAtlas = glyphAtlas(coverage: 255)
        scene.addGlyph(glyph(x: 4, y: 4))
        let textureID = scene.registerImageRenderPass(child, size: IntSize(width: 8, height: 8))
        scene.addImage(image(textureID, x: 16, y: 4, width: 8, height: 8))
        scene.addGlyph(glyph(x: 40, y: 16))
        scene.finish()

        let pixels = try assertParity(scene, size: IntSize(width: 64, height: 32))
        assertPixel(pixels, x: 6, y: 6, red: 255, green: 255, blue: 255)
        assertPixel(pixels, x: 20, y: 8, red: 64, green: 64, blue: 64)
        assertPixel(pixels, x: 42, y: 18, red: 255, green: 255, blue: 255)
    }

    func testLuminanceAndColorMultiplyPreserveTheirAlphaSemantics() async throws {
        let childSize = IntSize(width: 16, height: 16)
        var child = GPUIScene(clearColor: .clear)
        child.addQuad(quad(Color(red: 0.8, green: 0.4, blue: 0.2, alpha: 0.6), width: 16, height: 16))
        child.finish()

        var scene = GPUIScene(clearColor: .clear)
        let luminanceID = scene.registerImageRenderPass(child, size: childSize, colorEffects: [.luminanceToAlpha])
        let multiplyID = scene.registerImageRenderPass(
            child, size: childSize,
            colorEffects: [.colorMultiply(Color(red: 0.25, green: 0.5, blue: 0.75, alpha: 0.5))])
        scene.addImage(image(luminanceID, width: 16, height: 16))
        scene.addImage(image(multiplyID, x: 24, width: 16, height: 16))
        scene.finish()

        let pixels = try assertParity(scene, size: IntSize(width: 40, height: 16))
        let luminanceAlpha = 0.6 * (0.8 * 0.2126 + 0.4 * 0.7152 + 0.2 * 0.0722)
        assertPixel(pixels, x: 8, y: 8, red: 0, green: 0, blue: 0, alpha: luminanceAlpha * 255)
        // WARP returns premultiplied bytes: RGB is multiplied by both the
        // requested RGB multiplier and the resulting alpha (0.6 * 0.5).
        assertPixel(
            pixels, x: 32, y: 8,
            red: 0.8 * 0.25 * 0.3 * 255,
            green: 0.4 * 0.5 * 0.3 * 255,
            blue: 0.2 * 0.75 * 0.3 * 255,
            alpha: 0.3 * 255)
        assertPixel(pixels, x: 20, y: 8, red: 0, green: 0, blue: 0, alpha: 0)
    }

    func testFailedChildPassReleasesTemporaryTargetAndAllowsAnotherFrame() async throws {
        let size = IntSize(width: 48, height: 32)
        let renderer = D3D11BatchRenderer()
        do {
            try renderer.attachOffscreen(size: size, driver: .warpFirst)
        } catch {
            throw XCTSkip("D3D11 batch renderer unavailable on this machine: \(error)")
        }
        defer { renderer.detach() }

        var child = GPUIScene(clearColor: .clear)
        child.addImage(image(999_001, width: 8, height: 8))
        child.finish()
        var invalidScene = GPUIScene(clearColor: .black)
        let textureID = invalidScene.registerImageRenderPass(child, size: IntSize(width: 8, height: 8))
        invalidScene.addImage(image(textureID, width: 8, height: 8))
        invalidScene.finish()

        let objectCount = renderer.liveCOMObjectCountForTesting
        renderer.bindResources(for: invalidScene)
        XCTAssertThrowsError(try renderer.render(scene: invalidScene))
        XCTAssertEqual(renderer.liveCOMObjectCountForTesting, objectCount)

        var validScene = GPUIScene(clearColor: .black)
        validScene.addQuad(quad(Color(red: 1, green: 1, blue: 0, alpha: 1), x: 32, y: 16, width: 12, height: 12))
        validScene.finish()
        renderer.bindResources(for: validScene)
        try renderer.render(scene: validScene)
        let pixels = try renderer.readOffscreenPixels()
        let expected = GPUIRawSceneRasterizer.rasterize(validScene, size: size).premultipliedAlpha()
        XCTAssertEqual(comparePixels(pixels, expected, tolerance: 2).matchRatio, 1)
        assertPixel(pixels, x: 38, y: 22, red: 255, green: 255, blue: 0)
    }

    func testChildMaterialFailureStaysDegradedUntilResize() async throws {
        let size = IntSize(width: 32, height: 32)
        let renderer = try makeDedicatedRenderer(size: size)
        defer { renderer.detach() }

        var child = GPUIScene(clearColor: .black)
        for column in 0..<24 {
            let color =
                column.isMultiple(of: 2)
                ? Color(red: 1, green: 1, blue: 1, alpha: 1)
                : Color(red: 0, green: 0, blue: 0, alpha: 1)
            child.addQuad(quad(color, x: Float(column), width: 1, height: 24))
        }
        child.addQuad(
            QuadPrimitive(
                x: 4, y: 4, width: 16, height: 16,
                startR: 1, startG: 1, startB: 1, startA: 0.4,
                endR: 1, endG: 1, endB: 1, endA: 0.4,
                blurRadius: 4))
        child.finish()

        var scene = GPUIScene(clearColor: .black)
        let textureID = scene.registerImageRenderPass(child, size: IntSize(width: 24, height: 24))
        scene.addImage(image(textureID, x: 4, y: 4, width: 24, height: 24))
        scene.finish()

        renderer.failBlurredQuadsForTesting = true
        renderer.bindResources(for: scene)
        try renderer.render(scene: scene)
        XCTAssertTrue(renderer.blurDegradedForTesting, "A child blur failure must retain the degradation latch")
        XCTAssertFalse(renderer.blurEngineOwnsResourcesForTesting)
        let fallback = try renderer.readOffscreenPixels()

        // Removing the injection must not retry before resize. Creating the
        // blur engine here would mean a child had discarded the failure latch.
        renderer.failBlurredQuadsForTesting = false
        for _ in 0..<3 {
            renderer.bindResources(for: scene)
            try renderer.render(scene: scene)
            XCTAssertTrue(renderer.blurDegradedForTesting)
            XCTAssertFalse(renderer.blurEngineOwnsResourcesForTesting)
        }
        let repeated = try renderer.readOffscreenPixels()
        XCTAssertEqual(repeated.pixels, fallback.pixels)

        try renderer.resize(to: IntSize(width: 40, height: 32))
        XCTAssertFalse(renderer.blurDegradedForTesting)
        renderer.bindResources(for: scene)
        try renderer.render(scene: scene)
        XCTAssertFalse(renderer.blurDegradedForTesting)
        XCTAssertTrue(renderer.blurEngineOwnsResourcesForTesting, "The child blur must recover after resize")
        let recovered = try renderer.readOffscreenPixels()
        // comparePixels compares the common 32x32 area of these surfaces.
        XCTAssertLessThan(
            comparePixels(recovered, fallback, tolerance: 4).matchRatio, 0.98,
            "Recovered blur must smooth the stripes instead of retaining the plain fallback")
    }

    func testRepeatedFilteredPassDoesNotUploadBitmapsOrRetainTemporaryTargets() async throws {
        let size = IntSize(width: 32, height: 24)
        let renderer = try makeDedicatedRenderer(size: size)
        defer { renderer.detach() }

        var child = GPUIScene(clearColor: .clear)
        child.addQuad(quad(Color(red: 0.2, green: 0.4, blue: 0.6, alpha: 1), width: 16, height: 12))
        child.finish()
        var scene = GPUIScene(clearColor: .black)
        let textureID = scene.registerImageRenderPass(
            child, size: IntSize(width: 16, height: 12),
            colorEffects: [.brightness(0.1), .contrast(0.75)])
        scene.addImage(image(textureID, x: 4, y: 4, width: 16, height: 12))
        scene.finish()

        renderer.bindResources(for: scene)
        try renderer.render(scene: scene)
        let warmedObjectCount = renderer.liveCOMObjectCountForTesting
        XCTAssertEqual(renderer.imageTextureUploadsForTesting, 0)
        XCTAssertEqual(renderer.imageTextureCacheCountForTesting, 0)
        for frame in 0..<8 {
            renderer.bindResources(for: scene)
            try renderer.render(scene: scene)
            XCTAssertEqual(
                renderer.imageTextureUploadsForTesting, 0,
                "Frame \(frame): a quad-only pass must not upload a CPU bitmap")
            XCTAssertEqual(
                renderer.imageTextureCacheCountForTesting, 0,
                "Frame \(frame): temporary targets must not enter the bitmap cache")
            XCTAssertEqual(
                renderer.liveCOMObjectCountForTesting, warmedObjectCount,
                "Frame \(frame): temporary targets must be released after composition")
        }
        let pixels = try renderer.readOffscreenPixels()
        assertPixel(pixels, x: 12, y: 10, red: 89.25, green: 127.5, blue: 165.75)
    }

    func testPainterEffectPassPreservesFractionalScaleDerivativeCoverage() async throws {
        for scale in [1.25, 1.5, 1.75] {
            let red = Color(red: 1, green: 0, blue: 0, alpha: 1)
            let affected = ViewNode(
                frame: Rect(x: 12, y: 12, width: 16, height: 16), backgroundColor: red,
                shadowColor: red, shadowOffset: Point(x: 4, y: 0), shadowSpread: 2,
                children: [ViewNode(frame: Rect(x: 18, y: 0, width: 8, height: 8), backgroundColor: red)])
            let root = ViewNode(frame: Rect(x: 0, y: 0, width: 64, height: 64), children: [affected])
            let size = IntSize(width: Int32(64 * scale), height: Int32(64 * scale))
            let plainScene = ScenePainter.paint(
                root: root, clearColor: .clear, surfaceSize: Size(width: 64, height: 64), displayScale: scale)
            let plain = try WARPBatchRenderer.render(plainScene, size: size)
            affected.colorEffects = [.colorInvert]
            let filteredScene = ScenePainter.paint(
                root: root, clearColor: .clear, surfaceSize: Size(width: 64, height: 64), displayScale: scale)
            let filtered = try assertParity(filteredScene, size: size)
            let composite = try XCTUnwrap(filteredScene.layers.first?.images.first)
            XCTAssertTrue(Int(composite.screenX).isMultiple(of: 2))
            XCTAssertTrue(Int(composite.screenY).isMultiple(of: 2))
            var maxAlphaDifference = 0
            for offset in stride(from: 3, to: plain.pixels.count, by: 4) {
                maxAlphaDifference = max(
                    maxAlphaDifference, abs(Int(plain.pixels[offset]) - Int(filtered.pixels[offset])))
            }
            XCTAssertLessThanOrEqual(
                maxAlphaDifference, 2,
                "A GPU color pass must preserve geometry coverage at \(scale)x, including shadow and overflow")
        }
    }

    func testRepeatedSourceRunsSpendTheExecutionBudgetBeforeAllocatingAgain() async throws {
        let size = IntSize(width: 12, height: 4)
        let sourceSize = IntSize(width: 2, height: 2)
        let renderer = try makeDedicatedRenderer(size: size)
        defer { renderer.detach() }
        var source = GPUIScene(clearColor: Color(red: 1, green: 0, blue: 0, alpha: 1))
        source.finish()

        var scene = GPUIScene(clearColor: .black)
        let sourceID = scene.registerImageRenderPass(source, size: sourceSize, colorEffects: [.brightness(0.1)])
        for index in 0..<3 {
            let x = Float(index * 4)
            scene.addImage(image(sourceID, x: x, width: 2, height: 2))
            // Separate image runs resolve the same GPU source again. Without
            // this quad the renderer batches them into one source realization.
            scene.addQuad(quad(Color(red: 1, green: 1, blue: 1, alpha: 1), x: x + 2, y: 3, width: 1, height: 1))
        }
        scene.finish()
        XCTAssertTrue(scene.validate().isEmpty)
        XCTAssertNoThrow(try D3D11BatchRenderer.makeRenderPlan(for: scene))

        // Structural validation charges the declared source once. The CPU
        // reference also resolves it once and keeps the result in its local
        // cache, so all three references succeed under the production budget.
        let reference = GPUIRawSceneRasterizer.rasterize(scene, size: size).premultipliedAlpha()
        assertPixel(reference, x: 9, y: 1, red: 255, green: 25.5, blue: 25.5)

        var oneSourceScene = GPUIScene(clearColor: .black)
        let oneSourceID = oneSourceScene.registerImageRenderPass(
            source, size: sourceSize, colorEffects: [.brightness(0.1)])
        oneSourceScene.addImage(image(oneSourceID, width: 2, height: 2))
        oneSourceScene.finish()

        let cases: [(name: String, budget: GPUISceneImageRenderPassBudget)] = [
            ("pixels", GPUISceneImageRenderPassBudget(maxPasses: 32, maxPixels: 8)),
            ("count", GPUISceneImageRenderPassBudget(maxPasses: 2, maxPixels: 128)),
        ]
        for testCase in cases {
            renderer.imageRenderPassExecutionBudgetOverrideForTesting = testCase.budget
            renderer.bindResources(for: scene)
            XCTAssertThrowsError(try renderer.render(scene: scene)) { error in
                let failure = error as? BatchRendererError
                XCTAssertEqual(failure?.operation, "Execute image render pass", testCase.name)
                XCTAssertEqual(failure?.presentationFailureKind, .sceneContent, testCase.name)
            }

            // Two 2x2 source realizations consume eight source pixels. Their
            // filter targets are deliberately not separate source charges;
            // rejection happens before the third source can paint anything.
            let partial = try renderer.readOffscreenPixels()
            assertPixel(partial, x: 1, y: 1, red: 255, green: 25.5, blue: 25.5)
            assertPixel(partial, x: 5, y: 1, red: 255, green: 25.5, blue: 25.5)
            assertPixel(partial, x: 9, y: 1, red: 0, green: 0, blue: 0)

            // A new outer frame resets the same reduced budget, and the
            // rejected child must have restored the original target first.
            renderer.bindResources(for: oneSourceScene)
            try renderer.render(scene: oneSourceScene)
            assertPixel(try renderer.readOffscreenPixels(), x: 1, y: 1, red: 255, green: 25.5, blue: 25.5)
        }
    }

    func testRenderPlanRejectsCumulativeSourcePixelsWithoutAllocatingTargets() async throws {
        let maximumSourceSize = IntSize(width: 2048, height: 2048)
        var source = GPUIScene(clearColor: .red)
        source.finish()
        var scene = GPUIScene(clearColor: .black)
        for index in 0..<4 {
            let textureID = scene.registerImageRenderPass(source, size: maximumSourceSize)
            scene.addImage(image(textureID, x: Float(index * 2), width: 2, height: 2))
        }
        scene.finish()
        // Only metadata reaches the planner. No renderer is attached and no
        // large CPU bitmap or GPU render target is allocated by this test.
        XCTAssertTrue(scene.validate().isEmpty)
        XCTAssertEqual(try D3D11BatchRenderer.makeRenderPlan(for: scene).steps.count, 4)

        let excessSourceID = scene.registerImageRenderPass(source, size: maximumSourceSize)
        scene.addImage(image(excessSourceID, x: 8, width: 2, height: 2))
        scene.finish()
        XCTAssertFalse(scene.validate().isEmpty)
        XCTAssertThrowsError(try D3D11BatchRenderer.makeRenderPlan(for: scene)) { error in
            XCTAssertEqual((error as? BatchRendererError)?.presentationFailureKind, .sceneContent)
        }
    }

    private func makeDedicatedRenderer(size: IntSize) throws -> D3D11BatchRenderer {
        let renderer = D3D11BatchRenderer()
        do {
            try renderer.attachOffscreen(size: size, driver: .warpFirst)
        } catch {
            renderer.detach()
            throw XCTSkip("D3D11 batch renderer unavailable on this machine: \(error)")
        }
        return renderer
    }

    private func assertParity(
        _ scene: GPUIScene, size: IntSize,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> BitmapSurface {
        let actual = try WARPBatchRenderer.render(scene, size: size)
        let expected = GPUIRawSceneRasterizer.rasterize(scene, size: size).premultipliedAlpha()
        XCTAssertEqual(actual.width, expected.width, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, file: file, line: line)
        let report = comparePixels(actual, expected, tolerance: 4)
        XCTAssertGreaterThanOrEqual(
            report.matchRatio, 0.995,
            "CPU/WARP pass mismatch: max delta \(report.maxChannelDelta), first \(String(describing: report.firstFailure))",
            file: file, line: line)
        return actual
    }

    private func assertPixel(
        _ bitmap: BitmapSurface, x: Int, y: Int,
        red: Double, green: Double, blue: Double, alpha: Double = 255,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let offset = y * Int(bitmap.bytesPerRow) + x * 4
        XCTAssertEqual(Double(bitmap.pixels[offset]), blue, accuracy: 3, "Blue at (\(x), \(y))", file: file, line: line)
        XCTAssertEqual(
            Double(bitmap.pixels[offset + 1]), green, accuracy: 3, "Green at (\(x), \(y))", file: file, line: line)
        XCTAssertEqual(
            Double(bitmap.pixels[offset + 2]), red, accuracy: 3, "Red at (\(x), \(y))", file: file, line: line)
        XCTAssertEqual(
            Double(bitmap.pixels[offset + 3]), alpha, accuracy: 3, "Alpha at (\(x), \(y))", file: file, line: line)
    }

    private func image(
        _ textureID: Int32, x: Float = 0, y: Float = 0, width: Float, height: Float
    ) -> ImagePrimitive {
        ImagePrimitive(
            screenX: x, screenY: y, screenW: width, screenH: height,
            uvX: 0, uvY: 0, uvW: 1, uvH: 1, opacity: 1, textureID: textureID)
    }

    private func quad(
        _ color: Color, x: Float = 0, y: Float = 0, width: Float, height: Float
    ) -> QuadPrimitive {
        QuadPrimitive(
            x: x, y: y, width: width, height: height,
            startR: Float(color.red), startG: Float(color.green), startB: Float(color.blue), startA: Float(color.alpha),
            endR: Float(color.red), endG: Float(color.green), endB: Float(color.blue), endA: Float(color.alpha))
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
        var pixels = [UInt8]()
        for _ in 0..<64 {
            pixels.append(contentsOf: [blue, green, red, 255])
        }
        return BitmapSurface(width: 8, height: 8, bytesPerRow: 32, pixels: Data(pixels))
    }
}
