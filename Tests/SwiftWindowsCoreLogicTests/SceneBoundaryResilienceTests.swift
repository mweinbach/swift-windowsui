import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

/// Container-level scene inputs are not inserted through `add*`, but they
/// still cross the same CPU/D3D11 trust boundary as sanitized primitives.
final class SceneBoundaryResilienceTests: XCTestCase {
    func testSceneInitializerSanitizesEveryClearColorChannel() {
        let scene = GPUIScene(
            clearColor: Color(red: .nan, green: .infinity, blue: -.infinity, alpha: 2))

        XCTAssertEqual(scene.clearColor, Color(red: 0, green: 1, blue: 0, alpha: 1))
        XCTAssertTrue(scene.validate().isEmpty)
    }

    func testClearColorReassignmentAndChannelMutationRemainSanitized() {
        var scene = GPUIScene()
        scene.clearColor = Color(red: -2, green: 3, blue: .nan, alpha: -.infinity)

        XCTAssertEqual(scene.clearColor, Color(red: 0, green: 1, blue: 0, alpha: 0))

        scene.clearColor.red = .infinity
        scene.clearColor.alpha = 0.25

        XCTAssertEqual(scene.clearColor, Color(red: 1, green: 1, blue: 0, alpha: 0.25))
    }

    func testWellFormedTranslucentClearColorRemainsBitIdentical() {
        let authored = Color(red: 0.125, green: 0.375, blue: 0.625, alpha: 0.25)
        let scene = GPUIScene(clearColor: authored)

        XCTAssertEqual(scene.clearColor.red.bitPattern, authored.red.bitPattern)
        XCTAssertEqual(scene.clearColor.green.bitPattern, authored.green.bitPattern)
        XCTAssertEqual(scene.clearColor.blue.bitPattern, authored.blue.bitPattern)
        XCTAssertEqual(scene.clearColor.alpha.bitPattern, authored.alpha.bitPattern)
    }

    func testMalformedClearColorRasterizesWithoutAFloatConversionTrap() {
        let scene = GPUIScene(
            clearColor: Color(red: .nan, green: .infinity, blue: -3, alpha: .infinity))
        let bitmap = GPUIRawSceneRasterizer.rasterize(scene, size: IntSize(width: 2, height: 2))

        XCTAssertEqual(Array(bitmap.pixels.prefix(4)), [0, 255, 0, 255])
    }

    func testFrameBridgeSanitizesTheFrameClearColor() {
        let frame = RenderFrame(
            clearColor: Color(red: .infinity, green: .nan, blue: 0.5, alpha: -1),
            commands: [])
        let scene = GPUIScene(from: frame, surfaceSize: Size(width: 8, height: 8))

        XCTAssertEqual(scene.clearColor, Color(red: 1, green: 0, blue: 0.5, alpha: 0))
    }

    func testOversizedGlyphAtlasProducesASceneDefectInsteadOfIntegerOverflow() {
        let oversized = GlyphAtlasSnapshot(width: .max, height: .max, pixels: Data())
        let scene = GPUIScene(glyphAtlas: oversized)

        XCTAssertEqual(
            scene.validate(),
            [
                SceneDefect(
                    kind: .glyphAtlasBufferMismatch(
                        width: .max, height: .max, byteCount: 0, requiredByteCount: 0))
            ])
    }

    func testOversizedPixelGlyphAtlasUsesTheSameCheckedValidation() {
        let oversized = GlyphAtlasSnapshot(width: .max, height: .max, pixels: Data([255]))
        let scene = GPUIScene(pixelGlyphAtlas: oversized)

        XCTAssertEqual(
            scene.validate(),
            [
                SceneDefect(
                    kind: .glyphAtlasBufferMismatch(
                        width: .max, height: .max, byteCount: 1, requiredByteCount: 0))
            ])
    }

    func testMalformedPaintRunCannotOverflowWhileTheSceneIsSealed() {
        var scene = GPUIScene()
        scene.installHandBuiltLayer(
            GPUILayer(
                paintOperations: [
                    GPUIPaintOperation(kind: .quad, startIndex: .max, count: 1),
                    GPUIPaintOperation(kind: .quad, startIndex: 0, count: 1),
                ]),
            at: 0)

        scene.finish()

        XCTAssertEqual(scene.layers[0].paintOperations.count, 2)
        XCTAssertEqual(scene.validate().count, 2)
    }

    func testMalformedPaintRunCannotOverflowMergedCountWhileSealing() {
        var scene = GPUIScene()
        scene.installHandBuiltLayer(
            GPUILayer(
                paintOperations: [
                    GPUIPaintOperation(kind: .quad, startIndex: 0, count: .max),
                    GPUIPaintOperation(kind: .quad, startIndex: .max, count: 1),
                ]),
            at: 0)

        scene.finish()

        XCTAssertEqual(scene.layers[0].paintOperations.count, 2)
        XCTAssertEqual(scene.validate().count, 2)
    }

    func testOverflowingPaintRunDefectFormatsWithoutIntegerOverflow() {
        let defect = SceneDefect(
            kind: .paintOperationOutOfRange(
                layerIndex: 0, operationIndex: 0, kind: .quad,
                startIndex: .max, count: .max, familyCount: 0))

        XCTAssertTrue(defect.description.contains("overflow"))
        XCTAssertTrue(defect.description.contains(String(Int.max)))
    }

    func testPushLayerStopsAtTheSharedSceneLimit() {
        var scene = GPUIScene()

        for expectedLayer in 1..<GPUISceneLimits.maxLayers {
            XCTAssertEqual(scene.pushLayer(), expectedLayer)
        }

        XCTAssertEqual(scene.layers.count, GPUISceneLimits.maxLayers)
        XCTAssertTrue(scene.validate().isEmpty)

        for _ in 0..<1_024 {
            XCTAssertEqual(scene.pushLayer(), GPUISceneLimits.maxLayers - 1)
        }

        XCTAssertEqual(scene.layers.count, GPUISceneLimits.maxLayers)
        XCTAssertTrue(scene.validate().isEmpty)
    }

    func testRejectedLayerPushKeepsExistingTopLayerAndScopedMarkersUsable() {
        var scene = GPUIScene()
        XCTAssertTrue(scene.ensureLayer(GPUISceneLimits.maxLayers - 1))
        let topLayer = scene.pushLayer()

        XCTAssertEqual(topLayer, GPUISceneLimits.maxLayers - 1)
        XCTAssertTrue(scene.pushScopedLayer(Rect(x: 0, y: 0, width: 8, height: 8), toLayer: topLayer))
        scene.addQuad(
            QuadPrimitive(
                x: 0, y: 0, width: 8, height: 8,
                startR: 1, startG: 0, startB: 0, startA: 1,
                endR: 1, endG: 0, endB: 0, endA: 1),
            toLayer: topLayer)
        XCTAssertTrue(scene.popScopedLayer(fromLayer: topLayer))
        scene.finish()

        XCTAssertEqual(scene.layers.count, GPUISceneLimits.maxLayers)
        XCTAssertEqual(scene.layers[topLayer].quads.count, 1)
        XCTAssertTrue(scene.validate().isEmpty)

        let bitmap = GPUIRawSceneRasterizer.rasterize(scene, size: IntSize(width: 8, height: 8))
        XCTAssertEqual(Array(bitmap.pixels.prefix(4)), [0, 0, 255, 255])
    }
}
