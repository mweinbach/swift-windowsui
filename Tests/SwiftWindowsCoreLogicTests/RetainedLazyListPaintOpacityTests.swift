import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI

@MainActor
final class RetainedLazyListPaintOpacityTests: XCTestCase {
    private let surfaceSize = IntSize(width: 32, height: 24)

    private enum CaptureFailure: Error {
        case expectedSource
    }

    private func captured(
        _ scene: GPUIScene, file: StaticString = #filePath, line: UInt = #line
    ) throws -> RetainedLazyListPaintSource {
        guard
            case .captured(let source) = RetainedLazyListPaintSource.capture(
                scene: scene, ranges: [0..<scene.paintRecordCount], surfaceSize: surfaceSize)
        else {
            XCTFail("Expected captured paint", file: file, line: line)
            throw CaptureFailure.expectedSource
        }
        return source
    }

    private func overlappingChildren(opacity: Double, grouped: Bool) -> GPUIScene {
        let root = ViewNode(
            frame: Rect(x: 0, y: 0, width: 32, height: 24), opacity: opacity, isCompositingGroup: grouped,
            children: [
                ViewNode(
                    frame: Rect(x: 0, y: 0, width: 24, height: 24),
                    backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1)),
                ViewNode(
                    frame: Rect(x: 8, y: 0, width: 24, height: 24),
                    backgroundColor: Color(red: 0, green: 0, blue: 1, alpha: 1)),
            ])
        return ScenePainter.paint(root: root, clearColor: .clear, surfaceSize: Size(width: 32, height: 24))
    }

    private func materialRow(opacity: Double) -> ViewNode {
        ViewNode(
            frame: Rect(x: 0, y: 0, width: 32, height: 24),
            backgroundColor: Color(red: 0, green: 0, blue: 1, alpha: 0.4), blurRadius: 3, opacity: opacity,
            children: [
                ViewNode(
                    frame: Rect(x: 8, y: 4, width: 16, height: 16),
                    backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1))
            ])
    }

    private func stripedBackdrop(appending children: [ViewNode] = []) -> ViewNode {
        let stripes = (0..<16).map { index in
            ViewNode(
                frame: Rect(x: Double(index * 2), y: 0, width: 1, height: 24), backgroundColor: .white)
        }
        return ViewNode(
            frame: Rect(x: 0, y: 0, width: 32, height: 24), backgroundColor: .black, children: stripes + children)
    }

    private func quad(alpha: Float = 0.8) -> QuadPrimitive {
        QuadPrimitive(
            x: 0, y: 0, width: 8, height: 8,
            startR: 0.8, startG: 0.4, startB: 0.2, startA: alpha,
            endR: 0.2, endG: 0.4, endB: 0.8, endA: 0.4)
    }

    private func allFamilies() -> GPUIScene {
        let atlas = GlyphAtlasSnapshot(
            width: 2, height: 2, pixels: Data(repeating: 255, count: 16), contentVersion: 81)
        let pixelAtlas = GlyphAtlasSnapshot(
            width: 2, height: 2, pixels: Data(repeating: 127, count: 16), contentVersion: 82)
        var scene = GPUIScene(clearColor: .clear, glyphAtlas: atlas, pixelGlyphAtlas: pixelAtlas)
        scene.bindImageResource(
            BitmapSurface(width: 2, height: 2, bytesPerRow: 8, pixels: Data(repeating: 63, count: 16)), for: 7)
        // Deliberately record a higher layer first and interleave families in
        // the lower layer. Projection must follow presentation, not batching.
        scene.addQuad(quad(), toLayer: 2)
        scene.addGlyph(
            GlyphPrimitive(screenW: 2, screenH: 2, atlasU1: 1, atlasV1: 1, colorR: 0.3, colorA: 0.6), toLayer: 0)
        scene.addImage(ImagePrimitive(screenX: 2, screenW: 2, screenH: 2, opacity: 0.7, textureID: 7), toLayer: 0)
        scene.addPixelGlyph(
            GlyphPrimitive(screenX: 4, screenW: 2, screenH: 2, atlasU1: 1, atlasV1: 1, colorB: 0.4, colorA: 0.2),
            toLayer: 0)
        var path = PathPrimitive(
            elements: [.moveTo(.zero), .lineTo(Point(x: 6, y: 0)), .lineTo(Point(x: 3, y: 6)), .close],
            bounds: Rect(x: 0, y: 0, width: 6, height: 6),
            fillColor: Color(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.8),
            fillGradient: LinearGradient(
                stops: [
                    GradientStop(color: Color(red: 1, green: 0, blue: 0, alpha: 0.2), position: 0.1),
                    GradientStop(color: Color(red: 0, green: 0, blue: 1, alpha: 0.8), position: 0.9),
                ], axis: .horizontal, reversesAuthoredStops: true),
            strokeColor: Color(red: 0.6, green: 0.4, blue: 0.2, alpha: 0.6),
            strokeGradient: LinearGradient(
                startColor: Color(red: 0, green: 1, blue: 0, alpha: 0.6),
                endColor: Color(red: 1, green: 0, blue: 1, alpha: 0.4)),
            lineWidth: 1, lineCap: .round, lineJoin: .bevel,
            clipBounds: Rect(x: 0, y: 0, width: 10, height: 10), clipCornerRadius: 2)
        path.setGradientEndpoints(start: Point(x: 1, y: 2), end: Point(x: 5, y: 4))
        scene.addPath(path, toLayer: 0)
        scene.addShadow(
            ShadowPrimitive(width: 8, height: 8, colorR: 0.2, colorG: 0.3, colorB: 0.4, colorA: 0.5, blurRadius: 2),
            toLayer: 0)
        return scene
    }

    /// Exercise defensive projection checks which a normal capture already
    /// rejects, without weakening the capture contract to reach those checks.
    private func uncheckedSource(
        _ scene: GPUIScene, input: GPUISceneImageRenderPassInput = .independent
    ) -> RetainedLazyListPaintSource {
        RetainedLazyListPaintSource(
            scene: scene, bounds: Rect(x: 0, y: 0, width: 32, height: 24), size: surfaceSize, input: input,
            resourceBytes: 0, recordCount: scene.primitiveCount,
            executionPassCount: 0, executionPixelCount: 0, wasClipped: false)
    }

    func testInheritedOpacityMatchesOrdinaryPaintingOfOverlappingChildren() async throws {
        let source = try captured(overlappingChildren(opacity: 1, grouped: false))
        let projected = try XCTUnwrap(source.sceneApplyingInheritedOpacity(0.5))
        let actual = GPUIRawSceneRasterizer.rasterize(projected, size: surfaceSize)
        let expected = GPUIRawSceneRasterizer.rasterize(
            overlappingChildren(opacity: 0.5, grouped: false), size: surfaceSize)

        XCTAssertEqual(actual.pixels, expected.pixels)
        let overlap = try XCTUnwrap(actual.pixelColor(atX: 16, y: 12))
        XCTAssertEqual(overlap.alpha, 0.75, accuracy: 1.0 / 255)
        XCTAssertEqual(overlap.red, 1.0 / 3, accuracy: 1.0 / 255)
        XCTAssertEqual(overlap.blue, 2.0 / 3, accuracy: 1.0 / 255)
        XCTAssertEqual(source.scene.layers[0].quads.map(\.startA), [1, 1])
    }

    func testExplicitGroupFadesOnceAndKeepsItsChildNamespaceOpaque() async throws {
        let source = try captured(overlappingChildren(opacity: 1, grouped: true))
        let projected = try XCTUnwrap(source.sceneApplyingInheritedOpacity(0.5))
        let expected = GPUIRawSceneRasterizer.rasterize(
            overlappingChildren(opacity: 0.5, grouped: true), size: surfaceSize)
        let actual = GPUIRawSceneRasterizer.rasterize(projected, size: surfaceSize)

        XCTAssertEqual(actual.pixels, expected.pixels)
        XCTAssertEqual(projected.layers[0].images.first?.opacity, 0.5)
        XCTAssertEqual(projected.imageResources, source.scene.imageResources)
        let overlap = try XCTUnwrap(actual.pixelColor(atX: 16, y: 12))
        XCTAssertEqual(overlap.red, 0)
        XCTAssertEqual(overlap.blue, 1)
        XCTAssertEqual(overlap.alpha, 0.5, accuracy: 1.0 / 255)

        // The scene-backed version of the same explicit boundary must not
        // fade its children again while fading the enclosing image.
        var grouped = GPUIScene(clearColor: .clear)
        let id = grouped.registerImageRenderPass(
            overlappingChildren(opacity: 1, grouped: false), size: surfaceSize)
        grouped.addImage(ImagePrimitive(screenW: 32, screenH: 24, textureID: id))
        let passSource = try captured(grouped)
        let passProjection = try XCTUnwrap(passSource.sceneApplyingInheritedOpacity(0.5))
        XCTAssertEqual(passProjection.imageRenderPasses, passSource.scene.imageRenderPasses)
        XCTAssertEqual(GPUIRawSceneRasterizer.rasterize(passProjection, size: surfaceSize).pixels, expected.pixels)
    }

    func testMaterialMidpointRevealsBlurBehindFadingOpaqueForeground() async throws {
        let logicalSize = Size(width: 32, height: 24)
        let backdrop = ScenePainter.paint(root: stripedBackdrop(), clearColor: .clear, surfaceSize: logicalSize)
        let original = ScenePainter.paint(root: materialRow(opacity: 1), clearColor: .clear, surfaceSize: logicalSize)
        let source = try captured(original)
        XCTAssertEqual(source.input, .isolatedBackdrop)
        XCTAssertEqual(source.bounds, Rect(x: 0, y: 0, width: 32, height: 24))
        XCTAssertEqual(source.size, surfaceSize)
        XCTAssertEqual(source.scene.layers[0].quads.map(\.startA), [0.4, 1])
        let projected = try XCTUnwrap(
            source.sceneApplyingInheritedOpacity(
                0.5, permitsInheritedEffectOpacity: true, permitsInheritedBackdropOpacity: true))
        XCTAssertEqual(projected.layers[0].quads.map(\.startA), [0.2, 0.5])
        XCTAssertEqual(projected.layers[0].quads[0].blurRadius, 3)

        func wrapped(_ content: GPUIScene, opacity: Float) -> GPUIScene {
            var result = backdrop
            let id = result.registerImageRenderPass(content, size: source.size, input: source.input)
            result.addImage(
                ImagePrimitive(
                    screenX: Float(source.bounds.minX), screenY: Float(source.bounds.minY),
                    screenW: Float(source.size.width), screenH: Float(source.size.height),
                    opacity: opacity, textureID: id))
            result.finish()
            return result
        }

        let actualScene = wrapped(projected, opacity: 1)
        XCTAssertTrue(actualScene.validate().isEmpty)
        let actual = GPUIRawSceneRasterizer.rasterize(actualScene, size: surfaceSize)
        let ordinary = ScenePainter.paint(
            root: stripedBackdrop(appending: [materialRow(opacity: 0.5)]), clearColor: .clear, surfaceSize: logicalSize)
        let expected = GPUIRawSceneRasterizer.rasterize(ordinary, size: surfaceSize)
        XCTAssertEqual(actual.width, expected.width)
        XCTAssertEqual(actual.height, expected.height)
        XCTAssertEqual(actual.pixels.count, expected.pixels.count)
        let maximumDifference = zip(actual.pixels, expected.pixels).reduce(0) {
            max($0, abs(Int($1.0) - Int($1.1)))
        }
        XCTAssertLessThanOrEqual(
            maximumDifference, 2,
            "The isolated path adds foreground/coverage UNORM conversions; allow at most two channel bytes")

        // At opacity 1 the red foreground hides the material. Fading the
        // finished group exposes the unblurred stripes, not that material.
        let incorrect = GPUIRawSceneRasterizer.rasterize(wrapped(source.scene, opacity: 0.5), size: surfaceSize)
        for x in [12, 13] {
            let reference = try XCTUnwrap(expected.pixelColor(atX: x, y: 12))
            let wrong = try XCTUnwrap(incorrect.pixelColor(atX: x, y: 12))
            XCTAssertGreaterThan(abs(wrong.green - reference.green), 32.0 / 255)
        }

        // Root visibility belongs to the runtime. Alpha zero on a material
        // quad itself still means an untinted backdrop read, not absent paint.
        let zero = try XCTUnwrap(
            source.sceneApplyingInheritedOpacity(
                0, permitsInheritedEffectOpacity: true, permitsInheritedBackdropOpacity: true))
        XCTAssertEqual(zero.layers[0].quads.map(\.startA), [0, 0])
        XCTAssertEqual(zero.layers[0].quads[0].blurRadius, 3)
        XCTAssertEqual(zero.primitiveCount, source.scene.primitiveCount)
        XCTAssertNotEqual(
            GPUIRawSceneRasterizer.rasterize(wrapped(zero, opacity: 1), size: surfaceSize).pixels,
            GPUIRawSceneRasterizer.rasterize(backdrop, size: surfaceSize).pixels)
    }

    func testDependentImageOpacityRequiresBothWitnessesAndPreservesItsOwnedPass() async throws {
        var child = GPUIScene(clearColor: .clear)
        var material = quad()
        material.blurRadius = 2
        child.addQuad(material)
        let cases: [(GPUISceneImageRenderPassInput, Int32)] = [(.currentTarget, 0), (.isolatedBackdrop, 2)]
        for (input, blurRadius) in cases {
            var scene = GPUIScene(clearColor: .clear)
            let id = scene.registerImageRenderPass(
                child, size: IntSize(width: 8, height: 8), input: input, contentBlurRadius: blurRadius)
            scene.addImage(ImagePrimitive(screenX: 4, screenY: 6, screenW: 8, screenH: 8, opacity: 0.8, textureID: id))
            let source = try captured(scene)
            XCTAssertEqual(source.input, .isolatedBackdrop)
            XCTAssertNil(source.sceneApplyingInheritedOpacity(0.5))
            XCTAssertNil(source.sceneApplyingInheritedOpacity(0.5, permitsInheritedEffectOpacity: true))
            XCTAssertNil(source.sceneApplyingInheritedOpacity(0.5, permitsInheritedBackdropOpacity: true))
            let projected = try XCTUnwrap(
                source.sceneApplyingInheritedOpacity(
                    0.5, permitsInheritedEffectOpacity: true, permitsInheritedBackdropOpacity: true))
            var expectedImage = source.scene.layers[0].images[0]
            expectedImage.opacity = 0.4
            XCTAssertEqual(projected.layers[0].images[0], expectedImage)
            XCTAssertEqual(projected.imageRenderPasses, source.scene.imageRenderPasses)
            XCTAssertEqual(projected.imageRenderPasses[0].input, input)
            XCTAssertEqual(projected.imageRenderPasses[0].contentBlurRadius, blurRadius)
            XCTAssertEqual(projected.imageRenderPasses[0].scene.layers[0].quads[0].startA, 0.8)
            XCTAssertEqual(projected.imageRenderPasses[0].scene.layers[0].quads[0].blurRadius, 2)
            XCTAssertEqual(projected.paintRecords, source.scene.paintRecords)
            XCTAssertEqual(source.scene.layers[0].images[0].opacity, 0.8)
            XCTAssertNil(
                uncheckedSource(source.scene, input: .currentTarget).sceneApplyingInheritedOpacity(
                    0.5, permitsInheritedEffectOpacity: true, permitsInheritedBackdropOpacity: true))
        }
    }

    func testProjectionChangesOnlyEachFamilyAlphaAndPreservesResourcesAndOrder() async throws {
        let source = try captured(allFamilies())
        let projected = try XCTUnwrap(source.sceneApplyingInheritedOpacity(0.5))
        XCTAssertEqual(projected.paintRecords, source.scene.paintRecords)
        XCTAssertEqual(projected.layers.map(\.paintOperations), source.scene.layers.map(\.paintOperations))
        XCTAssertEqual(projected.glyphAtlas, source.scene.glyphAtlas)
        XCTAssertEqual(projected.pixelGlyphAtlas, source.scene.pixelGlyphAtlas)
        XCTAssertEqual(projected.imageResources, source.scene.imageResources)
        XCTAssertEqual(
            projected.imageResources.map { $0.bitmap.contentKey },
            source.scene.imageResources.map { $0.bitmap.contentKey })
        XCTAssertEqual(projected.imageRenderPasses, source.scene.imageRenderPasses)
        XCTAssertEqual(projected.clearColor, .clear)

        var expectedQuad = source.scene.layers[2].quads[0]
        expectedQuad.startA = 0.4
        expectedQuad.endA = 0.2
        XCTAssertEqual(projected.layers[2].quads[0], expectedQuad)
        var expectedGlyph = source.scene.layers[0].glyphs[0]
        expectedGlyph.colorA = 0.3
        XCTAssertEqual(projected.layers[0].glyphs[0], expectedGlyph)
        var expectedPixelGlyph = source.scene.layers[0].pixelGlyphs[0]
        expectedPixelGlyph.colorA = 0.1
        XCTAssertEqual(projected.layers[0].pixelGlyphs[0], expectedPixelGlyph)
        var expectedImage = source.scene.layers[0].images[0]
        expectedImage.opacity = 0.35
        XCTAssertEqual(projected.layers[0].images[0], expectedImage)
        var expectedShadow = source.scene.layers[0].shadows[0]
        expectedShadow.colorA = 0.25
        XCTAssertEqual(projected.layers[0].shadows[0], expectedShadow)
        var expectedPath = source.scene.layers[0].paths[0]
        expectedPath.fillColor.alpha = 0.4
        expectedPath.strokeColor.alpha = 0.3
        var fill = try XCTUnwrap(expectedPath.fillGradient)
        fill.stops[0].color.alpha = 0.1
        fill.stops[1].color.alpha = 0.4
        expectedPath.fillGradient = fill
        var stroke = try XCTUnwrap(expectedPath.strokeGradient)
        stroke.stops[0].color.alpha = 0.3
        stroke.stops[1].color.alpha = 0.2
        expectedPath.strokeGradient = stroke
        XCTAssertEqual(projected.layers[0].paths[0], expectedPath)
        XCTAssertEqual(source.scene.layers[2].quads[0].startA, 0.8)
        XCTAssertEqual(source.scene.layers[0].paths[0].fillGradient?.stops[0].color.alpha, 0.2)
    }

    func testOpacityFactorsValidateIdentityZeroAndClampEveryFamilyAfterMultiplication() async throws {
        let source = try captured(allFamilies())
        for invalid: Float in [.nan, .infinity, -.infinity, -0.5] {
            XCTAssertNil(source.sceneApplyingInheritedOpacity(invalid))
        }
        XCTAssertEqual(try XCTUnwrap(source.sceneApplyingInheritedOpacity(1)), source.scene)
        let zero = try XCTUnwrap(source.sceneApplyingInheritedOpacity(0))
        XCTAssertEqual(zero.primitiveCount, source.scene.primitiveCount)
        XCTAssertEqual(zero.layers[2].quads[0].startA, 0)
        XCTAssertEqual(zero.layers[2].quads[0].endA, 0)
        XCTAssertEqual(zero.layers[0].glyphs[0].colorA, 0)
        XCTAssertEqual(zero.layers[0].pixelGlyphs[0].colorA, 0)
        XCTAssertEqual(zero.layers[0].images[0].opacity, 0)
        XCTAssertEqual(zero.layers[0].shadows[0].colorA, 0)
        XCTAssertEqual(zero.layers[0].paths[0].fillColor.alpha, 0)
        XCTAssertEqual(zero.layers[0].paths[0].strokeColor.alpha, 0)
        XCTAssertEqual(zero.layers[0].paths[0].fillGradient?.stops.map(\.color.alpha), [0, 0])
        XCTAssertEqual(zero.layers[0].paths[0].strokeGradient?.stops.map(\.color.alpha), [0, 0])

        let doubled = try XCTUnwrap(source.sceneApplyingInheritedOpacity(2))
        XCTAssertEqual(doubled.layers[2].quads[0].startA, 1)
        XCTAssertEqual(doubled.layers[2].quads[0].endA, 0.8)
        XCTAssertEqual(doubled.layers[0].glyphs[0].colorA, 1)
        XCTAssertEqual(doubled.layers[0].pixelGlyphs[0].colorA, 0.4)
        XCTAssertEqual(doubled.layers[0].images[0].opacity, 1)
        XCTAssertEqual(doubled.layers[0].shadows[0].colorA, 1)
        XCTAssertEqual(doubled.layers[0].paths[0].fillColor.alpha, 1)
        XCTAssertEqual(doubled.layers[0].paths[0].strokeColor.alpha, 1)
        XCTAssertEqual(doubled.layers[0].paths[0].fillGradient?.stops.map(\.color.alpha), [0.4, 1])
        XCTAssertEqual(doubled.layers[0].paths[0].strokeGradient?.stops.map(\.color.alpha), [1, 0.8])
    }

    func testDirectMaterialBlendAndDependentInputsRejectProjection() async throws {
        for radius: Float in [0.5, 2] {
            var scene = GPUIScene(clearColor: .clear)
            var material = quad()
            material.blurRadius = radius
            scene.addQuad(material)
            let source = try captured(scene)
            if radius == 0.5 {
                XCTAssertEqual(source.input, .independent)
                let projected = try XCTUnwrap(source.sceneApplyingInheritedOpacity(0.5))
                var expected = source.scene.layers[0].quads[0]
                expected.startA = 0.4
                expected.endA = 0.2
                XCTAssertEqual(projected.layers[0].quads[0], expected)
                XCTAssertEqual(projected.layers[0].quads[0].blurRadius, 0.5)
            } else {
                XCTAssertNil(source.sceneApplyingInheritedOpacity(0.5))
                XCTAssertNil(source.sceneApplyingInheritedOpacity(0.5, permitsInheritedEffectOpacity: true))
            }
        }
        var blendScene = GPUIScene(clearColor: .clear)
        var blended = quad()
        blended.blendMode = 1
        blendScene.addQuad(blended)
        XCTAssertNil(uncheckedSource(blendScene).sceneApplyingInheritedOpacity(0.5))
        XCTAssertNil(
            uncheckedSource(blendScene).sceneApplyingInheritedOpacity(0.5, permitsInheritedEffectOpacity: true))
        XCTAssertNil(
            uncheckedSource(blendScene).sceneApplyingInheritedOpacity(
                0.5, permitsInheritedEffectOpacity: true, permitsInheritedBackdropOpacity: true))

        var child = GPUIScene(clearColor: .clear)
        child.addQuad(quad())
        for input in [GPUISceneImageRenderPassInput.currentTarget, .isolatedBackdrop] {
            XCTAssertNil(uncheckedSource(child, input: input).sceneApplyingInheritedOpacity(0.5))
            XCTAssertNil(
                uncheckedSource(child, input: input).sceneApplyingInheritedOpacity(
                    0.5, permitsInheritedEffectOpacity: true))
            var scene = GPUIScene(clearColor: .clear)
            let id = scene.registerImageRenderPass(child, size: IntSize(width: 8, height: 8), input: input)
            scene.addImage(ImagePrimitive(screenW: 8, screenH: 8, textureID: id))
            XCTAssertNil(try captured(scene).sceneApplyingInheritedOpacity(0.5))
            XCTAssertNil(uncheckedSource(scene).sceneApplyingInheritedOpacity(0.5))
            XCTAssertNil(uncheckedSource(scene).sceneApplyingInheritedOpacity(0.5, permitsInheritedEffectOpacity: true))
        }
    }

    func testDirectColorEffectAndContentBlurPassesRejectAmbiguousOpacity() async throws {
        var child = GPUIScene(clearColor: .clear)
        child.addQuad(quad())
        let effectCases: [[SceneColorEffect]] = [[.brightness(0.2)], [.luminanceToAlpha]]
        for effects in effectCases {
            var scene = GPUIScene(clearColor: .clear)
            let id = scene.registerImageRenderPass(
                child, size: IntSize(width: 8, height: 8), colorEffects: effects)
            scene.addImage(ImagePrimitive(screenW: 8, screenH: 8, textureID: id))
            let source = try captured(scene)
            XCTAssertEqual(source.input, .independent)
            XCTAssertNil(source.sceneApplyingInheritedOpacity(0.5))
            XCTAssertNil(source.sceneApplyingInheritedOpacity(0.5, permitsInheritedBackdropOpacity: true))
            let projected = try XCTUnwrap(
                source.sceneApplyingInheritedOpacity(0.5, permitsInheritedEffectOpacity: true))
            XCTAssertEqual(projected.layers[0].images[0].opacity, 0.5)
            XCTAssertEqual(projected.imageRenderPasses, source.scene.imageRenderPasses)
            XCTAssertEqual(projected.imageRenderPasses.first?.scene.layers[0].quads[0].startA, 0.8)
        }

        var blurred = GPUIScene(clearColor: .clear)
        let blurID = blurred.registerImageRenderPass(
            child, size: IntSize(width: 8, height: 8), input: .isolatedBackdrop, contentBlurRadius: 2)
        blurred.addImage(ImagePrimitive(screenW: 8, screenH: 8, textureID: blurID))
        let blurSource = try captured(blurred)
        XCTAssertNil(blurSource.sceneApplyingInheritedOpacity(0.5))
        XCTAssertNil(blurSource.sceneApplyingInheritedOpacity(0.5, permitsInheritedEffectOpacity: true))

        // The scene contract never permits a typed independent content blur.
        // Provenance cannot turn this invalid pass into supported paint.
        blurred.imageRenderPasses[0].input = .independent
        XCTAssertNil(uncheckedSource(blurred).sceneApplyingInheritedOpacity(0.5))
        XCTAssertNil(uncheckedSource(blurred).sceneApplyingInheritedOpacity(0.5, permitsInheritedEffectOpacity: true))
        XCTAssertNil(
            uncheckedSource(blurred).sceneApplyingInheritedOpacity(
                0.5, permitsInheritedEffectOpacity: true, permitsInheritedBackdropOpacity: true))
        guard
            case .unsupported = RetainedLazyListPaintSource.capture(
                scene: blurred, ranges: [0..<blurred.paintRecordCount], surfaceSize: surfaceSize)
        else {
            XCTFail("An independent content-blur source must fail capture validation")
            return
        }
    }

    func testIndependentGroupPreservesNestedBackdropAndEffectPassesWithoutRecursing() async throws {
        var leaf = GPUIScene(clearColor: .clear)
        leaf.addQuad(quad())
        var child = GPUIScene(clearColor: .clear)
        var material = quad()
        material.blurRadius = 2
        child.addQuad(material)
        let dependentID = child.registerImageRenderPass(
            leaf, size: IntSize(width: 8, height: 8), input: .currentTarget)
        child.addImage(ImagePrimitive(screenW: 8, screenH: 8, textureID: dependentID))
        let effectID = child.registerImageRenderPass(
            leaf, size: IntSize(width: 8, height: 8), colorEffects: [.luminanceToAlpha])
        child.addImage(ImagePrimitive(screenW: 8, screenH: 8, textureID: effectID))
        let blurID = child.registerImageRenderPass(
            leaf, size: IntSize(width: 8, height: 8), input: .isolatedBackdrop, contentBlurRadius: 2)
        child.addImage(ImagePrimitive(screenW: 8, screenH: 8, textureID: blurID))
        var scene = GPUIScene(clearColor: .clear)
        let groupID = scene.registerImageRenderPass(child, size: IntSize(width: 8, height: 8))
        scene.addImage(ImagePrimitive(screenW: 8, screenH: 8, opacity: 0.8, textureID: groupID))

        let source = try captured(scene)
        XCTAssertEqual(source.input, .independent)
        let projected = try XCTUnwrap(source.sceneApplyingInheritedOpacity(0.5))
        XCTAssertEqual(projected.layers[0].images[0].opacity, 0.4)
        XCTAssertEqual(projected.imageRenderPasses, source.scene.imageRenderPasses)
        let frozenChild = try XCTUnwrap(projected.imageRenderPasses.first?.scene)
        XCTAssertEqual(frozenChild.layers[0].quads[0].startA, 0.8)
        XCTAssertEqual(frozenChild.layers[0].quads[0].blurRadius, 2)
        XCTAssertEqual(frozenChild.imageRenderPasses.map(\.input), [.currentTarget, .independent, .isolatedBackdrop])
        XCTAssertEqual(frozenChild.imageRenderPasses[1].colorEffects, [.luminanceToAlpha])
        XCTAssertEqual(frozenChild.imageRenderPasses.last?.contentBlurRadius, 2)
    }

    func testNativeLuminanceQuadMultipliesAlphaWithoutChangingEffectOrCoverage() async throws {
        var scene = GPUIScene(clearColor: .clear)
        let value = QuadPrimitive(
            width: 16, height: 16, cornerRadius: 3,
            startR: 0.8, startG: 0.4, startB: 0.2, startA: 0.8,
            endR: 0.8, endG: 0.4, endB: 0.2, endA: 0.8,
            clipX: 0, clipY: 0, clipWidth: 16, clipHeight: 16, clipCornerRadius: 5,
            effectType: 8, effectIntensity: 0.7,
            effectParam1: 0.2, effectParam2: 0.3, effectParam3: 0.4, effectParam4: 0.5)
        scene.addQuad(value)
        let source = try captured(scene)
        let projected = try XCTUnwrap(source.sceneApplyingInheritedOpacity(0.5))
        var expectedQuad = value
        expectedQuad.startA = 0.4
        expectedQuad.endA = 0.4
        XCTAssertEqual(projected.layers[0].quads[0], expectedQuad)
        var expectedScene = GPUIScene(clearColor: .clear)
        expectedScene.addQuad(expectedQuad)
        let actual = GPUIRawSceneRasterizer.rasterize(projected, size: surfaceSize)
        XCTAssertEqual(actual.pixels, GPUIRawSceneRasterizer.rasterize(expectedScene, size: surfaceSize).pixels)
        let center = try XCTUnwrap(actual.pixelColor(atX: 8, y: 8))
        let luminance: Float = 0.2126 * 0.8 + 0.7152 * 0.4 + 0.0722 * 0.2
        XCTAssertEqual(center.alpha, 0.4 * luminance, accuracy: 1.0 / 255)
        XCTAssertEqual(center.red, 0)
        XCTAssertEqual(center.green, 0)
        XCTAssertEqual(center.blue, 0)
        XCTAssertEqual(actual.pixelColor(atX: 0, y: 0)?.alpha, 0)
    }
}
