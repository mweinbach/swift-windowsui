import XCTest
@testable import SwiftWindowsCore
@testable import SwiftWindowsGraphics

final class GPUISceneTests: XCTestCase {

    // MARK: - Primitive alignment tests

    func testQuadPrimitiveSizeIsDivisibleBy16() {
        XCTAssertEqual(QuadPrimitive.byteSize % 16, 0,
                       "QuadPrimitive size (\(QuadPrimitive.byteSize)) must be divisible by 16")
    }

    func testGlyphPrimitiveSizeIsDivisibleBy16() {
        XCTAssertEqual(GlyphPrimitive.byteSize % 16, 0,
                       "GlyphPrimitive size (\(GlyphPrimitive.byteSize)) must be divisible by 16")
    }

    func testImagePrimitiveSizeIsDivisibleBy16() {
        XCTAssertEqual(ImagePrimitive.byteSize % 16, 0,
                       "ImagePrimitive size (\(ImagePrimitive.byteSize)) must be divisible by 16")
    }

    func testShadowPrimitiveSizeIsDivisibleBy16() {
        XCTAssertEqual(ShadowPrimitive.byteSize % 16, 0,
                       "ShadowPrimitive size (\(ShadowPrimitive.byteSize)) must be divisible by 16")
    }

    // MARK: - GPUIScene initializer

    func testSceneDefaultClearColor() {
        let scene = GPUIScene()
        XCTAssertEqual(scene.clearColor, .black)
    }

    func testSceneCustomClearColor() {
        let scene = GPUIScene(clearColor: Color(red: 0.2, green: 0.3, blue: 0.4, alpha: 1.0))
        XCTAssertEqual(scene.clearColor.red, 0.2, accuracy: 0.0001)
        XCTAssertEqual(scene.clearColor.green, 0.3, accuracy: 0.0001)
        XCTAssertEqual(scene.clearColor.blue, 0.4, accuracy: 0.0001)
    }

    func testSceneStartsWithOneEmptyLayer() {
        let scene = GPUIScene()
        XCTAssertEqual(scene.layers.count, 1)
        XCTAssertTrue(scene.layers[0].quads.isEmpty)
        XCTAssertTrue(scene.layers[0].glyphs.isEmpty)
        XCTAssertTrue(scene.layers[0].images.isEmpty)
        XCTAssertTrue(scene.layers[0].shadows.isEmpty)
        XCTAssertTrue(scene.layers[0].paintOperations.isEmpty)
    }

    // MARK: - pushLayer

    func testPushLayerCreatesNewEmptyLayers() {
        var scene = GPUIScene()
        scene.pushLayer()
        scene.pushLayer()
        XCTAssertEqual(scene.layers.count, 3)
        for layer in scene.layers {
            XCTAssertTrue(layer.quads.isEmpty)
            XCTAssertTrue(layer.glyphs.isEmpty)
            XCTAssertTrue(layer.images.isEmpty)
            XCTAssertTrue(layer.shadows.isEmpty)
        }
    }

    // MARK: - Primitive insertion

    func testAddQuadAppendsToLastLayer() {
        var scene = GPUIScene()
        scene.addQuad(QuadPrimitive(x: 10, y: 20, width: 100, height: 50))
        scene.addQuad(QuadPrimitive(x: 30, y: 40, width: 200, height: 60))

        XCTAssertEqual(scene.layers[0].quads.count, 2)
        XCTAssertEqual(scene.layers[0].quads[0].x, 10)
        XCTAssertEqual(scene.layers[0].quads[1].x, 30)
        XCTAssertEqual(scene.layers[0].paintOperations, [
            GPUIPaintOperation(kind: .quad, startIndex: 0, count: 2)
        ])
    }

    func testAddGlyphAppendsToLastLayer() {
        var scene = GPUIScene()
        scene.addGlyph(GlyphPrimitive(screenX: 5, screenY: 10, screenW: 8, screenH: 12))

        XCTAssertEqual(scene.layers[0].glyphs.count, 1)
        XCTAssertEqual(scene.layers[0].glyphs[0].screenX, 5)
    }

    func testAddImageAppendsToLastLayer() {
        var scene = GPUIScene()
        scene.addImage(ImagePrimitive(screenX: 0, screenY: 0, screenW: 64, screenH: 64, textureID: 7))

        XCTAssertEqual(scene.layers[0].images.count, 1)
        XCTAssertEqual(scene.layers[0].images[0].textureID, 7)
    }

    func testAddShadowAppendsToLastLayer() {
        var scene = GPUIScene()
        scene.addShadow(ShadowPrimitive(x: 5, y: 5, width: 100, height: 100, blurRadius: 8))

        XCTAssertEqual(scene.layers[0].shadows.count, 1)
        XCTAssertEqual(scene.layers[0].shadows[0].blurRadius, 8)
    }

    func testPaintOperationsPreservePrimitiveFamilyOrderWithinLayer() {
        var scene = GPUIScene()
        scene.addQuad(QuadPrimitive(x: 0, y: 0, width: 10, height: 10))
        scene.addGlyph(GlyphPrimitive(screenX: 2, screenY: 2, screenW: 4, screenH: 8))
        scene.addQuad(QuadPrimitive(x: 12, y: 0, width: 10, height: 10))

        XCTAssertEqual(scene.layers[0].paintOperations, [
            GPUIPaintOperation(kind: .quad, startIndex: 0, count: 1),
            GPUIPaintOperation(kind: .glyph, startIndex: 0, count: 1),
            GPUIPaintOperation(kind: .quad, startIndex: 1, count: 1),
        ])
    }

    // MARK: - Multi-layer scene

    func testMultiLayerScenePrimitiveCounts() {
        var scene = GPUIScene(clearColor: .white)

        // Layer 0: 2 quads, 1 shadow
        scene.addQuad(QuadPrimitive(x: 0, y: 0, width: 100, height: 100))
        scene.addQuad(QuadPrimitive(x: 50, y: 50, width: 80, height: 80))
        scene.addShadow(ShadowPrimitive(x: 0, y: 0, width: 100, height: 100))

        // Layer 1: 3 glyphs, 1 image
        scene.pushLayer()
        scene.addGlyph(GlyphPrimitive(screenX: 10, screenY: 10))
        scene.addGlyph(GlyphPrimitive(screenX: 20, screenY: 10))
        scene.addGlyph(GlyphPrimitive(screenX: 30, screenY: 10))
        scene.addImage(ImagePrimitive(screenX: 0, screenY: 0, screenW: 256, screenH: 256))

        // Layer 2: 1 quad
        scene.pushLayer()
        scene.addQuad(QuadPrimitive(x: 200, y: 200, width: 50, height: 50))

        XCTAssertEqual(scene.layers.count, 3)

        // Layer 0
        XCTAssertEqual(scene.layers[0].quads.count, 2)
        XCTAssertEqual(scene.layers[0].shadows.count, 1)
        XCTAssertEqual(scene.layers[0].glyphs.count, 0)
        XCTAssertEqual(scene.layers[0].images.count, 0)

        // Layer 1
        XCTAssertEqual(scene.layers[1].quads.count, 0)
        XCTAssertEqual(scene.layers[1].shadows.count, 0)
        XCTAssertEqual(scene.layers[1].glyphs.count, 3)
        XCTAssertEqual(scene.layers[1].images.count, 1)

        // Layer 2
        XCTAssertEqual(scene.layers[2].quads.count, 1)
        XCTAssertEqual(scene.layers[2].shadows.count, 0)
        XCTAssertEqual(scene.layers[2].glyphs.count, 0)
        XCTAssertEqual(scene.layers[2].images.count, 0)
    }

    func testPushLayerReturnsLayerIndex() {
        var scene = GPUIScene()
        let idx1 = scene.pushLayer()
        let idx2 = scene.pushLayer()
        XCTAssertEqual(idx1, 1)
        XCTAssertEqual(idx2, 2)
    }

    func testAddQuadToExplicitHigherLayerExpandsScene() {
        var scene = GPUIScene()

        scene.addQuad(
            QuadPrimitive(x: 10, y: 20, width: 100, height: 50),
            toLayer: 2
        )

        XCTAssertEqual(scene.layers.count, 3)
        XCTAssertTrue(scene.layers[0].isEmpty)
        XCTAssertTrue(scene.layers[1].isEmpty)
        XCTAssertEqual(scene.layers[2].quads.count, 1)
        XCTAssertEqual(scene.layers[2].quads[0].x, 10)
    }

    func testFinishProducesOrderedBatchesForOverlappingPrimitives() {
        var scene = GPUIScene()
        scene.addQuad(QuadPrimitive(x: 0, y: 0, width: 120, height: 120))
        scene.addGlyph(GlyphPrimitive(screenX: 12, screenY: 12, screenW: 24, screenH: 24))
        scene.addQuad(QuadPrimitive(x: 8, y: 8, width: 80, height: 80))

        scene.finish()

        var iterator = scene.layers[0].orderedBatches()
        XCTAssertEqual(iterator.next(), .quads(0..<1))
        XCTAssertEqual(iterator.next(), .glyphs(0..<1))
        XCTAssertEqual(iterator.next(), .quads(1..<2))
        XCTAssertNil(iterator.next())
    }

    func testFinishCoalescesNonOverlappingFamilyRanges() {
        var scene = GPUIScene()
        scene.addQuad(QuadPrimitive(x: 0, y: 0, width: 20, height: 20))
        scene.addGlyph(GlyphPrimitive(screenX: 100, screenY: 0, screenW: 12, screenH: 12))
        scene.addQuad(QuadPrimitive(x: 200, y: 0, width: 20, height: 20))

        scene.finish()

        var iterator = scene.layers[0].orderedBatches()
        XCTAssertEqual(iterator.next(), .quads(0..<2))
        XCTAssertEqual(iterator.next(), .glyphs(0..<1))
        XCTAssertNil(iterator.next())
    }

    func testScopedLayerKeepsPrimitivesOnTheSameDrawOrder() {
        var scene = GPUIScene()
        scene.pushScopedLayer(Rect(x: 0, y: 0, width: 100, height: 100), toLayer: 0)
        scene.addQuad(QuadPrimitive(x: 0, y: 0, width: 100, height: 100))
        scene.addGlyph(GlyphPrimitive(screenX: 10, screenY: 10, screenW: 20, screenH: 20))
        scene.popScopedLayer(fromLayer: 0)

        scene.finish()

        var iterator = scene.layers[0].orderedBatches()
        XCTAssertEqual(iterator.next(), .quads(0..<1))
        XCTAssertEqual(iterator.next(), .glyphs(0..<1))
        XCTAssertNil(iterator.next())
    }
}
