import XCTest

@testable import SwiftWindowsCore

@testable import SwiftWindowsGraphics

final class GPUISceneTests: XCTestCase {

    // MARK: - Primitive alignment tests

    func testQuadPrimitiveSizeIsDivisibleBy16() {
        XCTAssertEqual(
            QuadPrimitive.byteSize % 16, 0,
            "QuadPrimitive size (\(QuadPrimitive.byteSize)) must be divisible by 16")
    }

    func testGlyphPrimitiveSizeIsDivisibleBy16() {
        XCTAssertEqual(
            GlyphPrimitive.byteSize % 16, 0,
            "GlyphPrimitive size (\(GlyphPrimitive.byteSize)) must be divisible by 16")
    }

    func testImagePrimitiveSizeIsDivisibleBy16() {
        XCTAssertEqual(
            ImagePrimitive.byteSize % 16, 0,
            "ImagePrimitive size (\(ImagePrimitive.byteSize)) must be divisible by 16")
    }

    func testShadowPrimitiveSizeIsDivisibleBy16() {
        XCTAssertEqual(
            ShadowPrimitive.byteSize % 16, 0,
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
        XCTAssertEqual(
            scene.layers[0].paintOperations,
            [
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

        XCTAssertEqual(
            scene.layers[0].paintOperations,
            [
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
        scene.addGlyph(GlyphPrimitive(screenX: 10, screenY: 10, screenW: 8, screenH: 12))
        scene.addGlyph(GlyphPrimitive(screenX: 20, screenY: 10, screenW: 8, screenH: 12))
        scene.addGlyph(GlyphPrimitive(screenX: 30, screenY: 10, screenW: 8, screenH: 12))
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

    // MARK: - VAL-SCENE-003: Deterministic draw ordering with family tie precedence

    func testDeterministicDrawOrderingIsStable() {
        var scene = GPUIScene()

        // Add primitives in overlapping positions
        scene.addQuad(QuadPrimitive(x: 0, y: 0, width: 100, height: 100))
        scene.addGlyph(GlyphPrimitive(screenX: 50, screenY: 50, screenW: 20, screenH: 20))

        scene.finish()

        var iterator = scene.layers[0].orderedBatches()
        let firstBatch = iterator.next()
        let secondBatch = iterator.next()

        // Run the same setup twice and verify identical output
        var scene2 = GPUIScene()
        scene2.addQuad(QuadPrimitive(x: 0, y: 0, width: 100, height: 100))
        scene2.addGlyph(GlyphPrimitive(screenX: 50, screenY: 50, screenW: 20, screenH: 20))
        scene2.finish()

        var iterator2 = scene2.layers[0].orderedBatches()
        let firstBatch2 = iterator2.next()
        let secondBatch2 = iterator2.next()

        XCTAssertEqual(firstBatch, firstBatch2)
        XCTAssertEqual(secondBatch, secondBatch2)
    }

    func testFamilyTiePrecedenceShadowBeforeQuad() {
        // Use scoped layer so both primitives share the same draw order
        // Family precedence: shadow (0) < quad (1)
        var scene = GPUIScene()

        scene.pushScopedLayer(Rect(x: 0, y: 0, width: 100, height: 100), toLayer: 0)
        // Add quad first, then shadow - shadow should come first due to precedence
        scene.addQuad(QuadPrimitive(x: 0, y: 0, width: 50, height: 50))
        scene.addShadow(ShadowPrimitive(x: 0, y: 0, width: 50, height: 50))
        scene.popScopedLayer(fromLayer: 0)

        scene.finish()

        var iterator = scene.layers[0].orderedBatches()
        // Shadow should be drawn before quad (lower sort rank)
        XCTAssertEqual(iterator.next(), .shadows(0..<1))
        XCTAssertEqual(iterator.next(), .quads(0..<1))
    }

    func testFamilyTiePrecedenceQuadBeforeGlyph() {
        var scene = GPUIScene()

        scene.pushScopedLayer(Rect(x: 0, y: 0, width: 100, height: 100), toLayer: 0)
        scene.addGlyph(GlyphPrimitive(screenX: 0, screenY: 0, screenW: 50, screenH: 50))
        scene.addQuad(QuadPrimitive(x: 0, y: 0, width: 50, height: 50))
        scene.popScopedLayer(fromLayer: 0)

        scene.finish()

        var iterator = scene.layers[0].orderedBatches()
        // Quad (sort rank 1) should come before glyph (sort rank 2)
        XCTAssertEqual(iterator.next(), .quads(0..<1))
        XCTAssertEqual(iterator.next(), .glyphs(0..<1))
    }

    func testFamilyTiePrecedenceGlyphBeforePixelGlyph() {
        var scene = GPUIScene()

        scene.pushScopedLayer(Rect(x: 0, y: 0, width: 100, height: 100), toLayer: 0)
        scene.addPixelGlyph(GlyphPrimitive(screenX: 0, screenY: 0, screenW: 12, screenH: 12))
        scene.addGlyph(GlyphPrimitive(screenX: 0, screenY: 0, screenW: 12, screenH: 12))
        scene.popScopedLayer(fromLayer: 0)

        scene.finish()

        var iterator = scene.layers[0].orderedBatches()
        // Glyph (sort rank 2) should come before pixelGlyph (sort rank 3)
        XCTAssertEqual(iterator.next(), .glyphs(0..<1))
        XCTAssertEqual(iterator.next(), .pixelGlyphs(0..<1))
    }

    func testFamilyTiePrecedencePixelGlyphBeforeImage() {
        var scene = GPUIScene()

        scene.pushScopedLayer(Rect(x: 0, y: 0, width: 100, height: 100), toLayer: 0)
        scene.addImage(ImagePrimitive(screenX: 0, screenY: 0, screenW: 64, screenH: 64))
        scene.addPixelGlyph(GlyphPrimitive(screenX: 0, screenY: 0, screenW: 12, screenH: 12))
        scene.popScopedLayer(fromLayer: 0)

        scene.finish()

        var iterator = scene.layers[0].orderedBatches()
        // pixelGlyph (sort rank 3) should come before image (sort rank 4)
        XCTAssertEqual(iterator.next(), .pixelGlyphs(0..<1))
        XCTAssertEqual(iterator.next(), .images(0..<1))
    }

    func testFullFamilyTiePrecedenceOrder() {
        var scene = GPUIScene()

        scene.pushScopedLayer(Rect(x: 0, y: 0, width: 100, height: 100), toLayer: 0)
        // Add all families in reverse order
        scene.addImage(ImagePrimitive(screenX: 10, screenY: 10, screenW: 32, screenH: 32))
        scene.addPixelGlyph(GlyphPrimitive(screenX: 10, screenY: 10, screenW: 8, screenH: 8))
        scene.addGlyph(GlyphPrimitive(screenX: 10, screenY: 10, screenW: 12, screenH: 12))
        scene.addQuad(QuadPrimitive(x: 10, y: 10, width: 40, height: 40))
        scene.addShadow(ShadowPrimitive(x: 10, y: 10, width: 50, height: 50))
        scene.popScopedLayer(fromLayer: 0)

        scene.finish()

        var iterator = scene.layers[0].orderedBatches()
        // All at same draw order, family precedence should be:
        // shadow -> quad -> glyph -> pixelGlyph -> image
        XCTAssertEqual(iterator.next(), .shadows(0..<1))
        XCTAssertEqual(iterator.next(), .quads(0..<1))
        XCTAssertEqual(iterator.next(), .glyphs(0..<1))
        XCTAssertEqual(iterator.next(), .pixelGlyphs(0..<1))
        XCTAssertEqual(iterator.next(), .images(0..<1))
        XCTAssertNil(iterator.next())
    }

    func testReverseInsertionPreservesDeterministicOrder() {
        // When primitives have different draw orders based on bounds, insertion order matters
        // When they share the same draw order (scoped layer), family precedence matters
        var scene1 = GPUIScene()
        scene1.pushScopedLayer(Rect(x: 0, y: 0, width: 200, height: 200), toLayer: 0)
        scene1.addQuad(QuadPrimitive(x: 0, y: 0, width: 50, height: 50))
        scene1.addGlyph(GlyphPrimitive(screenX: 25, screenY: 25, screenW: 20, screenH: 20))
        scene1.popScopedLayer(fromLayer: 0)
        scene1.finish()

        var scene2 = GPUIScene()
        scene2.pushScopedLayer(Rect(x: 0, y: 0, width: 200, height: 200), toLayer: 0)
        scene2.addGlyph(GlyphPrimitive(screenX: 25, screenY: 25, screenW: 20, screenH: 20))
        scene2.addQuad(QuadPrimitive(x: 0, y: 0, width: 50, height: 50))
        scene2.popScopedLayer(fromLayer: 0)
        scene2.finish()

        var iter1 = scene1.layers[0].orderedBatches()
        var iter2 = scene2.layers[0].orderedBatches()

        // Both should have identical batch ordering due to scoped layer making both primitives share draw order
        // Family precedence (quad before glyph) should determine the order
        XCTAssertEqual(iter1.next(), iter2.next())
        XCTAssertEqual(iter1.next(), iter2.next())
        XCTAssertEqual(iter1.next(), iter2.next())
    }

    // MARK: - VAL-SCENE-004: Non-overlapping work coalesces without changing overlap semantics

    func testNonOverlappingSameFamilyPrimitivesCoalesce() {
        var scene = GPUIScene()

        // Non-overlapping quads at x=0, x=100, x=200
        scene.addQuad(QuadPrimitive(x: 0, y: 0, width: 50, height: 50))
        scene.addQuad(QuadPrimitive(x: 100, y: 0, width: 50, height: 50))
        scene.addQuad(QuadPrimitive(x: 200, y: 0, width: 50, height: 50))

        scene.finish()

        var iterator = scene.layers[0].orderedBatches()
        // All non-overlapping quads should coalesce into one range
        let batch = iterator.next()
        XCTAssertEqual(batch, .quads(0..<3))
        XCTAssertNil(iterator.next())
    }

    func testOverlappingPrimitivesDoNotCoalesce() {
        var scene = GPUIScene()

        // Overlapping quads - first at (0,0) size (100,100), second at (50,50) size (100,100)
        scene.addQuad(QuadPrimitive(x: 0, y: 0, width: 100, height: 100))
        scene.addQuad(QuadPrimitive(x: 50, y: 50, width: 100, height: 100))

        scene.finish()

        var iterator = scene.layers[0].orderedBatches()
        // Overlapping quads should NOT coalesce into a single range
        let batch1 = iterator.next()
        let batch2 = iterator.next()
        XCTAssertNotNil(batch1)
        XCTAssertNotNil(batch2)

        // The two batches should be separate ranges
        if case .quads(let range1) = batch1, case .quads(let range2) = batch2 {
            XCTAssertEqual(range1.count + range2.count, 2)
            XCTAssertNotEqual(range1, range2)
        } else {
            XCTFail("Expected two quad batches for overlapping primitives")
        }
    }

    func testCoalescingDoesNotChangeVisibleOverlapSemantics() {
        var scene = GPUIScene()

        // Quad 1 at bottom-left
        scene.addQuad(QuadPrimitive(x: 0, y: 0, width: 100, height: 100))
        // Glyph overlapping quad 1 (should be drawn on top)
        scene.addGlyph(GlyphPrimitive(screenX: 50, screenY: 50, screenW: 30, screenH: 30))
        // Non-overlapping quad 2 (can coalesce with quad 1 in same-family batching)
        scene.addQuad(QuadPrimitive(x: 200, y: 200, width: 50, height: 50))

        scene.finish()

        var iterator = scene.layers[0].orderedBatches()

        // First batch should be quads (0..<2) - both quads coalesced despite glyph between
        let batch1 = iterator.next()
        XCTAssertEqual(batch1, .quads(0..<2))

        // Second batch should be the glyph
        let batch2 = iterator.next()
        XCTAssertEqual(batch2, .glyphs(0..<1))

        // Glyph comes after the quads in draw order (correct z-order)
        XCTAssertNil(iterator.next())
    }

    func testDeterministicCoalescingForMultipleNonOverlappingPrimitives() {
        var scene = GPUIScene()

        // Create pattern: quad, glyph, quad, glyph, quad (non-overlapping)
        scene.addQuad(QuadPrimitive(x: 0, y: 0, width: 50, height: 50))
        scene.addGlyph(GlyphPrimitive(screenX: 100, screenY: 0, screenW: 20, screenH: 20))
        scene.addQuad(QuadPrimitive(x: 200, y: 0, width: 50, height: 50))
        scene.addGlyph(GlyphPrimitive(screenX: 300, screenY: 0, screenW: 20, screenH: 20))
        scene.addQuad(QuadPrimitive(x: 400, y: 0, width: 50, height: 50))

        scene.finish()

        var iterator = scene.layers[0].orderedBatches()

        // All 3 quads should coalesce (non-overlapping)
        let quadBatch = iterator.next()
        XCTAssertEqual(quadBatch, .quads(0..<3))

        // All 2 glyphs should coalesce (non-overlapping)
        let glyphBatch = iterator.next()
        XCTAssertEqual(glyphBatch, .glyphs(0..<2))

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

    func testMaskedPrimitiveOutsideContentMaskIsDropped() {
        var scene = GPUIScene()
        scene.addQuad(
            QuadPrimitive(
                x: 0,
                y: 0,
                width: 40,
                height: 40,
                clipX: 100,
                clipY: 100,
                clipWidth: 20,
                clipHeight: 20
            ))

        XCTAssertTrue(scene.layers[0].quads.isEmpty)
        XCTAssertEqual(scene.paintRecordCount, 0)
    }

    // MARK: - VAL-SCENE-001: Accepted primitive-family sequence preservation

    func testAllPrimitiveFamiliesPreserveAcceptedSequence() {
        var scene = GPUIScene()

        // Add primitives in a specific interleaved order
        scene.addShadow(ShadowPrimitive(x: 0, y: 0, width: 100, height: 100))
        scene.addQuad(QuadPrimitive(x: 10, y: 10, width: 80, height: 80))
        scene.addGlyph(GlyphPrimitive(screenX: 20, screenY: 20, screenW: 12, screenH: 12))
        scene.addPixelGlyph(GlyphPrimitive(screenX: 22, screenY: 22, screenW: 8, screenH: 8))
        scene.addImage(ImagePrimitive(screenX: 30, screenY: 30, screenW: 40, screenH: 40))

        // Verify paint operations preserve the exact family sequence
        let operations = scene.layers[0].paintOperations
        XCTAssertEqual(operations.count, 5)
        XCTAssertEqual(operations[0].kind, .shadow)
        XCTAssertEqual(operations[1].kind, .quad)
        XCTAssertEqual(operations[2].kind, .glyph)
        XCTAssertEqual(operations[3].kind, .pixelGlyph)
        XCTAssertEqual(operations[4].kind, .image)
    }

    func testFinishPreservesAcceptedPaintOperationSequence() {
        var scene = GPUIScene()
        scene.addQuad(QuadPrimitive(x: 0, y: 0, width: 24, height: 24))
        scene.addGlyph(GlyphPrimitive(screenX: 4, screenY: 4, screenW: 8, screenH: 8))
        scene.addQuad(QuadPrimitive(x: 48, y: 0, width: 24, height: 24))

        scene.finish()

        XCTAssertEqual(
            scene.layers[0].paintOperations,
            [
                GPUIPaintOperation(kind: .quad, startIndex: 0, count: 1),
                GPUIPaintOperation(kind: .glyph, startIndex: 0, count: 1),
                GPUIPaintOperation(kind: .quad, startIndex: 1, count: 1),
            ])
    }

    func testAdjacentSameFamilyPrimitivesCoalesce() {
        var scene = GPUIScene()

        // Add 3 consecutive quads
        scene.addQuad(QuadPrimitive(x: 0, y: 0, width: 10, height: 10))
        scene.addQuad(QuadPrimitive(x: 20, y: 0, width: 10, height: 10))
        scene.addQuad(QuadPrimitive(x: 40, y: 0, width: 10, height: 10))

        // Should coalesce into a single paint operation
        let operations = scene.layers[0].paintOperations
        XCTAssertEqual(operations.count, 1)
        XCTAssertEqual(operations[0].kind, .quad)
        XCTAssertEqual(operations[0].startIndex, 0)
        XCTAssertEqual(operations[0].count, 3)
    }

    func testRejectedPrimitivesDoNotSplitAdjacentSameFamilyOperations() {
        var scene = GPUIScene()

        // Add two quads that should coalesce
        scene.addQuad(QuadPrimitive(x: 0, y: 0, width: 10, height: 10))
        scene.addQuad(QuadPrimitive(x: 20, y: 0, width: 10, height: 10))

        // Add a fully clipped quad that should be rejected
        scene.addQuad(
            QuadPrimitive(
                x: 100, y: 100, width: 10, height: 10,
                clipX: 0, clipY: 0, clipWidth: 5, clipHeight: 5  // clip outside the quad
            ))

        // Add another quad that should coalesce with the first two
        scene.addQuad(QuadPrimitive(x: 40, y: 0, width: 10, height: 10))

        // All three accepted quads should be in a single operation
        let operations = scene.layers[0].paintOperations
        XCTAssertEqual(operations.count, 1)
        XCTAssertEqual(operations[0].kind, .quad)
        XCTAssertEqual(operations[0].count, 3)
    }

    func testRejectedPrimitivesDoNotConsumeIndices() {
        var scene = GPUIScene()

        // Add a valid quad at index 0
        scene.addQuad(QuadPrimitive(x: 0, y: 0, width: 10, height: 10))

        // Add a fully masked/empty quad that should be rejected
        let rejectedQuad = QuadPrimitive(
            x: 0, y: 0, width: 0, height: 10  // zero width
        )
        scene.addQuad(rejectedQuad)

        // Add another valid quad - should be at index 1, not 2
        scene.addQuad(QuadPrimitive(x: 20, y: 0, width: 10, height: 10))

        // Verify primitives array has exactly 2 quads
        XCTAssertEqual(scene.layers[0].quads.count, 2)
        XCTAssertEqual(scene.layers[0].quads[0].x, 0)
        XCTAssertEqual(scene.layers[0].quads[1].x, 20)

        // Paint record count reflects paint operations (not raw primitives)
        // The two valid quads should coalesce into one operation
        XCTAssertEqual(scene.layers[0].paintOperations.count, 1)
    }

    func testRejectedPrimitivesDoNotCreatePaintRecords() {
        var scene = GPUIScene()

        // Add a fully masked quad that should be rejected
        scene.addQuad(
            QuadPrimitive(
                x: 0, y: 0, width: 40, height: 40,
                clipX: 100, clipY: 100, clipWidth: 20, clipHeight: 20
            ))

        // No paint records should be created for rejected primitives
        XCTAssertEqual(scene.layers[0].paintOperations.count, 0)
        XCTAssertEqual(scene.paintRecordCount, 0)
    }

    // MARK: - VAL-SCENE-002: Empty effective clips and fully masked primitives omission

    func testZeroWidthClipOmitsPrimitive() {
        var scene = GPUIScene()
        scene.addQuad(
            QuadPrimitive(
                x: 0, y: 0, width: 100, height: 100,
                clipX: 0, clipY: 0, clipWidth: 0, clipHeight: 100  // zero width
            ))

        XCTAssertTrue(scene.layers[0].quads.isEmpty)
        XCTAssertEqual(scene.layers[0].paintOperations.count, 0)
    }

    func testZeroHeightClipOmitsPrimitive() {
        var scene = GPUIScene()
        scene.addQuad(
            QuadPrimitive(
                x: 0, y: 0, width: 100, height: 100,
                clipX: 0, clipY: 0, clipWidth: 100, clipHeight: 0  // zero height
            ))

        XCTAssertTrue(scene.layers[0].quads.isEmpty)
        XCTAssertEqual(scene.layers[0].paintOperations.count, 0)
    }

    func testFullyClippedPrimitiveOutsideContentMaskIsOmitted() {
        var scene = GPUIScene()

        // Quad at (0,0) with size (100,100)
        // Clip at (200,200) with size (50,50) - no overlap
        scene.addQuad(
            QuadPrimitive(
                x: 0, y: 0, width: 100, height: 100,
                clipX: 200, clipY: 200, clipWidth: 50, clipHeight: 50
            ))

        XCTAssertTrue(scene.layers[0].quads.isEmpty)
        XCTAssertEqual(scene.paintRecordCount, 0)
    }

    func testMaskedBoundsDriveDrawOrderAssignment() {
        var scene = GPUIScene()
        scene.addQuad(
            QuadPrimitive(
                x: 0,
                y: 0,
                width: 300,
                height: 20,
                clipX: 0,
                clipY: 0,
                clipWidth: 40,
                clipHeight: 20
            ))
        scene.addQuad(
            QuadPrimitive(
                x: 200,
                y: 0,
                width: 20,
                height: 20
            ))

        scene.finish()

        var iterator = scene.layers[0].orderedBatches()
        XCTAssertEqual(iterator.next(), .quads(0..<2))
        XCTAssertNil(iterator.next())
    }

    func testReplayCopiesScenePaintRecords() {
        var original = GPUIScene(clearColor: .white)
        original.pushScopedLayer(Rect(x: 0, y: 0, width: 120, height: 120), toLayer: 0)
        original.addQuad(QuadPrimitive(x: 0, y: 0, width: 80, height: 80))
        original.addGlyph(GlyphPrimitive(screenX: 8, screenY: 8, screenW: 12, screenH: 12))
        original.popScopedLayer(fromLayer: 0)

        var replayed = GPUIScene(clearColor: .white)
        let result = replayed.replay(0..<original.paintRecordCount, from: original)

        XCTAssertEqual(result, .success)
        XCTAssertEqual(replayed, original)
    }

    // MARK: - VAL-SCENE-005: Scoped layers create stable shared ordering regions

    func testSingleScopedLayerCreatesSharedOrderingRegion() {
        var scene = GPUIScene()

        // Push scoped layer - this creates a shared draw-order region
        scene.pushScopedLayer(Rect(x: 0, y: 0, width: 200, height: 200), toLayer: 0)
        scene.addQuad(QuadPrimitive(x: 10, y: 10, width: 80, height: 80))
        scene.addGlyph(GlyphPrimitive(screenX: 20, screenY: 20, screenW: 20, screenH: 20))
        scene.popScopedLayer(fromLayer: 0)

        // Add content outside the scoped layer
        scene.addQuad(QuadPrimitive(x: 250, y: 250, width: 50, height: 50))

        scene.finish()

        // Verify paint records show scoped layer markers
        let records = scene.paintRecords
        XCTAssertTrue(records.contains { if case .startLayer = $0 { return true } else { return false } })
        XCTAssertTrue(records.contains { if case .endLayer = $0 { return true } else { return false } })

        // Content inside scoped layer should share same draw order
        var iterator = scene.layers[0].orderedBatches()
        // Both scoped layer quads should be coalesced
        let batch1 = iterator.next()
        XCTAssertNotNil(batch1)
        // Then the glyph
        let batch2 = iterator.next()
        XCTAssertNotNil(batch2)
    }

    func testNestedScopedLayersPreserveDeterministicOrdering() {
        var scene = GPUIScene()

        // Outer scoped layer
        scene.pushScopedLayer(Rect(x: 0, y: 0, width: 300, height: 300), toLayer: 0)
        scene.addQuad(QuadPrimitive(x: 10, y: 10, width: 100, height: 100))

        // Inner scoped layer
        scene.pushScopedLayer(Rect(x: 50, y: 50, width: 200, height: 200), toLayer: 0)
        scene.addGlyph(GlyphPrimitive(screenX: 60, screenY: 60, screenW: 30, screenH: 30))
        scene.popScopedLayer(fromLayer: 0)

        // Back to outer layer
        scene.addShadow(ShadowPrimitive(x: 120, y: 120, width: 50, height: 50))
        scene.popScopedLayer(fromLayer: 0)

        // Content outside all scopes
        scene.addImage(ImagePrimitive(screenX: 350, screenY: 350, screenW: 64, screenH: 64))

        scene.finish()

        // Verify paint records contain balanced start/end layer pairs
        var scopeDepth = 0
        var maxDepth = 0
        for record in scene.paintRecords {
            switch record {
            case .startLayer:
                scopeDepth += 1
                maxDepth = max(maxDepth, scopeDepth)
            case .endLayer:
                scopeDepth -= 1
            default:
                break
            }
        }
        XCTAssertEqual(scopeDepth, 0, "Scopes should be balanced")
        XCTAssertEqual(maxDepth, 2, "Should have 2 nested scope levels")

        // All scoped content should be grouped together
        var iterator = scene.layers[0].orderedBatches()
        // Outer scoped layer items
        let batch1 = iterator.next()
        XCTAssertNotNil(batch1)

        // Image outside scope comes after
        let batch2 = iterator.next()
        XCTAssertNotNil(batch2)
    }

    func testScopedLayerEmptyBoundsIsRejected() {
        var scene = GPUIScene()

        // Try to push empty scoped layer
        let emptyRect = Rect(x: 0, y: 0, width: 0, height: 100)
        scene.pushScopedLayer(emptyRect, toLayer: 0)

        // Should not create a startLayer record
        let hasStartLayer = scene.paintRecords.contains {
            if case .startLayer = $0 { return true } else { return false }
        }
        XCTAssertFalse(hasStartLayer, "Empty scoped layer should be rejected")
    }

    func testScopedLayerPrimitivesShareSameDrawOrder() {
        // Without scoped layer, overlapping primitives get different draw orders
        var scene1 = GPUIScene()
        scene1.addQuad(QuadPrimitive(x: 0, y: 0, width: 100, height: 100))
        // Glyph overlaps the quad, so it gets a higher draw order
        scene1.addGlyph(GlyphPrimitive(screenX: 50, screenY: 50, screenW: 30, screenH: 30))
        scene1.finish()

        // With scoped layer, both primitives share the scoped layer's draw order
        var scene2 = GPUIScene()
        scene2.pushScopedLayer(Rect(x: 0, y: 0, width: 200, height: 200), toLayer: 0)
        scene2.addQuad(QuadPrimitive(x: 0, y: 0, width: 100, height: 100))
        scene2.addGlyph(GlyphPrimitive(screenX: 50, screenY: 50, screenW: 30, screenH: 30))
        scene2.popScopedLayer(fromLayer: 0)
        scene2.finish()

        var iter1 = scene1.layers[0].orderedBatches()
        var iter2 = scene2.layers[0].orderedBatches()

        // scene1: quad and glyph have different draw orders due to overlap
        // They should be in separate batches
        let batch1Quad = iter1.next()
        let batch1Glyph = iter1.next()
        XCTAssertNotNil(batch1Quad)
        XCTAssertNotNil(batch1Glyph)
        XCTAssertNil(iter1.next())  // Iterator should be exhausted after 2 batches

        // scene2: quad and glyph share the same draw order from scoped layer
        // Family precedence (quad before glyph) applies, but within same order they coalesce by family
        // So we expect one quad batch and one glyph batch (both at same draw order value)
        let batch2Quad = iter2.next()
        let batch2Glyph = iter2.next()
        XCTAssertNotNil(batch2Quad)
        XCTAssertNotNil(batch2Glyph)
        XCTAssertNil(iter2.next())  // Iterator should be exhausted after 2 batches
    }

    // MARK: - VAL-SCENE-006: Balanced replay ranges reconstruct equivalent scene

    func testBalancedReplayRangeReconstructsEquivalentScene() {
        var original = GPUIScene(clearColor: .white)
        original.pushScopedLayer(Rect(x: 0, y: 0, width: 120, height: 120), toLayer: 0)
        original.addQuad(QuadPrimitive(x: 0, y: 0, width: 80, height: 80))
        original.addGlyph(GlyphPrimitive(screenX: 8, screenY: 8, screenW: 12, screenH: 12))
        original.popScopedLayer(fromLayer: 0)

        var replayed = GPUIScene(clearColor: .white)
        let result = replayed.replay(0..<original.paintRecordCount, from: original)

        // Should succeed and reconstruct equivalent scene
        XCTAssertEqual(result, .success)
        XCTAssertEqual(replayed.layers[0].quads.count, original.layers[0].quads.count)
        XCTAssertEqual(replayed.layers[0].glyphs.count, original.layers[0].glyphs.count)
        XCTAssertEqual(replayed.paintRecords.count, original.paintRecords.count)
    }

    func testPartialBalancedReplayReconstructsPartialScene() {
        var original = GPUIScene(clearColor: .white)
        original.addQuad(QuadPrimitive(x: 0, y: 0, width: 50, height: 50))
        original.addGlyph(GlyphPrimitive(screenX: 10, screenY: 10, screenW: 12, screenH: 12))
        original.addImage(ImagePrimitive(screenX: 20, screenY: 20, screenW: 32, screenH: 32))

        // Replay just the first two records (quad and glyph)
        var replayed = GPUIScene(clearColor: .white)
        let result = replayed.replay(0..<2, from: original)

        XCTAssertEqual(result, .success)
        XCTAssertEqual(replayed.layers[0].quads.count, 1)
        XCTAssertEqual(replayed.layers[0].glyphs.count, 1)
        XCTAssertEqual(replayed.layers[0].images.count, 0)
    }

    // MARK: - VAL-SCENE-007: Boundary-depth validation for interior subranges

    func testInteriorPrimitiveSubrangeWithoutMarkersReplaysSafelyWhenAtRootDepth() {
        // Scenario: primitive between markers at indices 0..<3
        // startLayer(0), primitive(1), endLayer(2)
        // Replaying 1..<2 (just the primitive) should succeed if primitive was at root depth
        // This test verifies primitives at depth 0 can be replayed without markers
        var original = GPUIScene(clearColor: .white)
        original.addQuad(QuadPrimitive(x: 0, y: 0, width: 50, height: 50))
        original.addGlyph(GlyphPrimitive(screenX: 10, screenY: 10, screenW: 12, screenH: 12))

        // Replay just the glyph (which was at root depth)
        var replayed = GPUIScene(clearColor: .white)
        let result = replayed.replay(1..<2, from: original)

        // Should succeed - primitive was at depth 0
        XCTAssertEqual(result, .success)
        XCTAssertEqual(replayed.layers[0].glyphs.count, 1)
    }

    func testInteriorSubrangeInsideScopedLayerFailsWithoutEnclosingMarkers() {
        // Scenario: startLayer(0), primitive(1), endLayer(2)
        // Replaying 1..<2 (just the primitive) should fail because
        // the primitive at index 1 was emitted at depth 1, but the range
        // doesn't include the enclosing startLayer marker
        var original = GPUIScene(clearColor: .white)
        original.pushScopedLayer(Rect(x: 0, y: 0, width: 100, height: 100), toLayer: 0)
        original.addQuad(QuadPrimitive(x: 0, y: 0, width: 50, height: 50))
        original.popScopedLayer(fromLayer: 0)

        // Record indices: 0=startLayer, 1=quad, 2=endLayer
        // Try to replay just the quad (1..<2) without its enclosing markers
        var replayed = GPUIScene(clearColor: .white)
        let result = replayed.replay(1..<2, from: original)

        // Should fail - the primitive at index 1 requires depth 1 but
        // the range doesn't include the startLayer marker
        XCTAssertEqual(result, .unbalanced(layerIndex: 0, depth: 1, reason: .startsInsideScope))
        XCTAssertTrue(replayed.layers[0].quads.isEmpty)
    }

    func testInteriorSubrangeInsideNestedScopedLayerFailsWithoutEnclosingMarkers() {
        // Scenario: startLayer(0), startLayer(1), primitive(2), endLayer(3), endLayer(4)
        // Replaying 2..<3 should fail - primitive was at depth 2
        var original = GPUIScene(clearColor: .white)
        original.pushScopedLayer(Rect(x: 0, y: 0, width: 200, height: 200), toLayer: 0)
        original.pushScopedLayer(Rect(x: 50, y: 50, width: 100, height: 100), toLayer: 0)
        original.addQuad(QuadPrimitive(x: 60, y: 60, width: 40, height: 40))
        original.popScopedLayer(fromLayer: 0)
        original.popScopedLayer(fromLayer: 0)

        // Record indices: 0=outer startLayer, 1=inner startLayer, 2=quad, 3=inner endLayer, 4=outer endLayer
        // Try to replay just the quad (2..<3)
        var replayed = GPUIScene(clearColor: .white)
        let result = replayed.replay(2..<3, from: original)

        // Should fail - the primitive at index 2 requires depth 2
        XCTAssertEqual(result, .unbalanced(layerIndex: 0, depth: 2, reason: .startsInsideScope))
        XCTAssertTrue(replayed.layers[0].quads.isEmpty)
    }

    func testInteriorSubrangeWithPartialMarkersStillFails() {
        // Scenario: startLayer(0), primitive(1), endLayer(2)
        // Replaying 0..<2 includes startLayer but not endLayer - should fail
        var original = GPUIScene(clearColor: .white)
        original.pushScopedLayer(Rect(x: 0, y: 0, width: 100, height: 100), toLayer: 0)
        original.addQuad(QuadPrimitive(x: 0, y: 0, width: 50, height: 50))
        original.popScopedLayer(fromLayer: 0)

        // Try to replay 0..<2 (startLayer + quad, missing endLayer)
        var replayed = GPUIScene(clearColor: .white)
        let result = replayed.replay(0..<2, from: original)

        // Should fail - ends inside scope
        XCTAssertEqual(result, .unbalanced(layerIndex: 0, depth: 1, reason: .endsInsideScope))
        XCTAssertTrue(replayed.layers[0].quads.isEmpty)
    }

    func testBalancedReplayOfCompleteScopedLayerContentSucceeds() {
        // Scenario: startLayer(0), primitive(1), endLayer(2)
        // Replaying 0..<3 (complete with markers) should succeed
        var original = GPUIScene(clearColor: .white)
        original.pushScopedLayer(Rect(x: 0, y: 0, width: 100, height: 100), toLayer: 0)
        original.addQuad(QuadPrimitive(x: 0, y: 0, width: 50, height: 50))
        original.popScopedLayer(fromLayer: 0)

        // Replay the complete scoped layer content
        var replayed = GPUIScene(clearColor: .white)
        let result = replayed.replay(0..<3, from: original)

        XCTAssertEqual(result, .success)
        XCTAssertEqual(replayed.layers[0].quads.count, 1)

        // Verify scoped layer markers were replayed
        XCTAssertEqual(replayed.paintRecords.count, 3)
        if case .startLayer = replayed.paintRecords[0] {
            // expected
        } else {
            XCTFail("Expected startLayer record")
        }
        if case .endLayer = replayed.paintRecords[2] {
            // expected
        } else {
            XCTFail("Expected endLayer record")
        }
    }

    func testMultipleInteriorSubrangesFailWithCorrectDepthReporting() {
        // Scenario with multiple scoped layers:
        // 0: startLayer(0), 1: quad1, 2: endLayer(0)
        // 3: startLayer(0), 4: quad2, 5: endLayer(0)
        var original = GPUIScene(clearColor: .white)
        original.pushScopedLayer(Rect(x: 0, y: 0, width: 100, height: 100), toLayer: 0)
        original.addQuad(QuadPrimitive(x: 0, y: 0, width: 50, height: 50))  // index 1
        original.popScopedLayer(fromLayer: 0)
        original.pushScopedLayer(Rect(x: 200, y: 200, width: 100, height: 100), toLayer: 0)
        original.addQuad(QuadPrimitive(x: 210, y: 210, width: 40, height: 40))  // index 4
        original.popScopedLayer(fromLayer: 0)

        // Try to replay just the first quad (1..<2) - should fail with depth 1
        var replayed1 = GPUIScene(clearColor: .white)
        let result1 = replayed1.replay(1..<2, from: original)
        XCTAssertEqual(result1, .unbalanced(layerIndex: 0, depth: 1, reason: .startsInsideScope))

        // Try to replay just the second quad (4..<5) - should fail with depth 1
        var replayed2 = GPUIScene(clearColor: .white)
        let result2 = replayed2.replay(4..<5, from: original)
        XCTAssertEqual(result2, .unbalanced(layerIndex: 0, depth: 1, reason: .startsInsideScope))
    }

    // MARK: - VAL-SCENE-007 (original): Unbalanced replay ranges fail safely

    func testUnbalancedReplayStartingInsideScopedLayer() {
        var original = GPUIScene(clearColor: .white)
        original.pushScopedLayer(Rect(x: 0, y: 0, width: 100, height: 100), toLayer: 0)
        original.addQuad(QuadPrimitive(x: 0, y: 0, width: 50, height: 50))
        original.popScopedLayer(fromLayer: 0)

        // Skip the first record (startLayer), only replay the quad and endLayer
        var replayed = GPUIScene(clearColor: .white)
        let result = replayed.replay(1..<original.paintRecordCount, from: original)

        // Should reject the unbalanced range - starts inside a scope at depth 1
        // (depth 1 represents the scoped layer that was opened at record 0)
        XCTAssertEqual(result, .unbalanced(layerIndex: 0, depth: 1, reason: .startsInsideScope))

        // Scene should remain empty since replay was rejected
        XCTAssertTrue(replayed.layers[0].quads.isEmpty)
    }

    func testUnbalancedReplayEndingInsideScopedLayer() {
        var original = GPUIScene(clearColor: .white)
        original.pushScopedLayer(Rect(x: 0, y: 0, width: 100, height: 100), toLayer: 0)
        original.addQuad(QuadPrimitive(x: 0, y: 0, width: 50, height: 50))
        original.addGlyph(GlyphPrimitive(screenX: 10, screenY: 10, screenW: 12, screenH: 12))
        // Note: missing popScopedLayer - incomplete in original

        // Replay the range which ends inside the scoped layer
        var replayed = GPUIScene(clearColor: .white)
        let result = replayed.replay(0..<original.paintRecordCount, from: original)

        // Should reject the unbalanced range - ends inside a scope
        XCTAssertEqual(result, .unbalanced(layerIndex: 0, depth: 1, reason: .endsInsideScope))

        // Scene should remain empty since replay was rejected
        XCTAssertTrue(replayed.layers[0].quads.isEmpty)
    }

    func testUnbalancedReplayWithExplicitStartLayerButMissingEndLayer() {
        var original = GPUIScene(clearColor: .white)
        original.pushScopedLayer(Rect(x: 0, y: 0, width: 100, height: 100), toLayer: 0)
        original.addQuad(QuadPrimitive(x: 0, y: 0, width: 50, height: 50))
        original.popScopedLayer(fromLayer: 0)
        original.addGlyph(GlyphPrimitive(screenX: 10, screenY: 10, screenW: 12, screenH: 12))

        // Replay only from startLayer through the quad (missing endLayer)
        var replayed = GPUIScene(clearColor: .white)
        // Record 0: startLayer, Record 1: quad, Record 2: endLayer, Record 3: glyph
        // Replay just 0..<2 (startLayer and quad, but not the matching endLayer)
        let result = replayed.replay(0..<2, from: original)

        // Should reject - ends inside scope
        XCTAssertEqual(result, .unbalanced(layerIndex: 0, depth: 1, reason: .endsInsideScope))
    }

    func testNestedScopedLayerReplay() {
        // Test balanced nested scopes
        var original = GPUIScene(clearColor: .white)
        original.pushScopedLayer(Rect(x: 0, y: 0, width: 200, height: 200), toLayer: 0)
        original.addQuad(QuadPrimitive(x: 0, y: 0, width: 50, height: 50))
        original.pushScopedLayer(Rect(x: 50, y: 50, width: 100, height: 100), toLayer: 0)
        original.addGlyph(GlyphPrimitive(screenX: 60, screenY: 60, screenW: 20, screenH: 20))
        original.popScopedLayer(fromLayer: 0)
        original.addShadow(ShadowPrimitive(x: 10, y: 10, width: 30, height: 30))
        original.popScopedLayer(fromLayer: 0)

        var replayed = GPUIScene(clearColor: .white)
        let result = replayed.replay(0..<original.paintRecordCount, from: original)

        XCTAssertEqual(result, .success)
        XCTAssertEqual(replayed.layers[0].quads.count, 1)
        XCTAssertEqual(replayed.layers[0].glyphs.count, 1)
        XCTAssertEqual(replayed.layers[0].shadows.count, 1)
    }

    func testNestedScopedLayerReplayPartialUnbalanced() {
        // Test partial replay that starts inside a nested scope
        var original = GPUIScene(clearColor: .white)
        original.pushScopedLayer(Rect(x: 0, y: 0, width: 200, height: 200), toLayer: 0)  // record 0
        original.addQuad(QuadPrimitive(x: 0, y: 0, width: 50, height: 50))  // record 1
        original.pushScopedLayer(Rect(x: 50, y: 50, width: 100, height: 100), toLayer: 0)  // record 2
        original.addGlyph(GlyphPrimitive(screenX: 60, screenY: 60, screenW: 20, screenH: 20))  // record 3
        original.popScopedLayer(fromLayer: 0)  // record 4
        original.popScopedLayer(fromLayer: 0)  // record 5

        // Start replay from record 2 (inside both scopes) - should reject
        var replayed = GPUIScene(clearColor: .white)
        let result = replayed.replay(2..<original.paintRecordCount, from: original)

        // At record 2, we have depth 1 from the outer scope at record 0.
        // The inner scope starts at record 2 but the outer scope from record 0
        // is unmatched in this range, so depth is 1.
        XCTAssertEqual(result, .unbalanced(layerIndex: 0, depth: 1, reason: .startsInsideScope))
    }

    func testEmptyReplayRangeIsBalanced() {
        var original = GPUIScene(clearColor: .white)
        original.addQuad(QuadPrimitive(x: 0, y: 0, width: 50, height: 50))

        var replayed = GPUIScene(clearColor: .white)
        let result = replayed.replay(0..<0, from: original)

        XCTAssertEqual(result, .success)
        XCTAssertTrue(replayed.layers[0].quads.isEmpty)
    }

    func testReplayPreservesPrimitiveValues() {
        var original = GPUIScene(clearColor: .white)
        let quad = QuadPrimitive(x: 10, y: 20, width: 100, height: 200, cornerRadius: 5)
        original.addQuad(quad)

        let glyph = GlyphPrimitive(
            screenX: 5, screenY: 10, screenW: 8, screenH: 12,
            atlasU0: 0.1, atlasV0: 0.2, atlasU1: 0.3, atlasV1: 0.4,
            colorR: 0.5, colorG: 0.6, colorB: 0.7, colorA: 0.8)
        original.addGlyph(glyph)

        var replayed = GPUIScene(clearColor: .white)
        let result = replayed.replay(0..<original.paintRecordCount, from: original)

        XCTAssertEqual(result, .success)
        XCTAssertEqual(replayed.layers[0].quads.first, quad)
        XCTAssertEqual(replayed.layers[0].glyphs.first, glyph)
    }
}
