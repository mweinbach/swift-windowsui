import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI

/// These fixtures contain only completed scene values. Capturing never creates
/// a ViewNode, invokes Canvas, or renders pixels to establish its result.
@MainActor
final class RetainedLazyListPaintSourceTests: XCTestCase {
    private let surfaceSize = IntSize(width: 64, height: 64)

    private enum CaptureFailure: Error {
        case expectedSource
    }

    private func captured(
        _ scene: GPUIScene, ranges: [Range<Int>]? = nil, size: IntSize? = nil,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> RetainedLazyListPaintSource {
        guard
            case .captured(let source) = RetainedLazyListPaintSource.capture(
                scene: scene, ranges: ranges ?? [0..<scene.paintRecordCount], surfaceSize: size ?? surfaceSize)
        else {
            XCTFail("Expected immutable captured paint", file: file, line: line)
            throw CaptureFailure.expectedSource
        }
        return source
    }

    private func unsupported(
        _ scene: GPUIScene, ranges: [Range<Int>]? = nil, size: IntSize? = nil,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        guard
            case .unsupported = RetainedLazyListPaintSource.capture(
                scene: scene, ranges: ranges ?? [0..<scene.paintRecordCount], surfaceSize: size ?? surfaceSize)
        else {
            XCTFail("Expected an explicit unsupported capture", file: file, line: line)
            return
        }
    }

    private func quad(x: Float = 4, y: Float = 6, width: Float = 8, height: Float = 10) -> QuadPrimitive {
        QuadPrimitive(x: x, y: y, width: width, height: height, startR: 1, endR: 1)
    }

    private func atlas(version: UInt64 = 71, extent: Int32 = 2, value: UInt8 = 255) -> GlyphAtlasSnapshot {
        GlyphAtlasSnapshot(
            width: extent, height: extent, pixels: Data(repeating: value, count: Int(extent * extent * 4)),
            contentVersion: version, update: .region(GlyphAtlasRegion(x: 0, y: 0, width: 1, height: 1), since: 70))
    }

    private func bitmap(_ value: UInt8 = 255) -> BitmapSurface {
        BitmapSurface(width: 2, height: 2, bytesPerRow: 8, pixels: Data(repeating: value, count: 16))
    }

    func testIndependentCropKeepsFractionalPlacementClipsAndEvenPixelOrigin() async throws {
        var scene = GPUIScene(clearColor: .black)
        var value = quad(x: 11.5, y: 9.25, width: 7, height: 3.5)
        value.contentMask = GPUIContentMask(bounds: Rect(x: 10, y: 0, width: 40, height: 50))
        scene.addQuad(value)

        let source = try captured(scene)
        XCTAssertEqual(source.input, .independent)
        XCTAssertEqual(source.bounds, Rect(x: 10, y: 8, width: 9, height: 5))
        XCTAssertEqual(source.size, IntSize(width: 9, height: 5))
        XCTAssertEqual(source.scene.clearColor, .clear)
        XCTAssertEqual(source.scene.layers[0].quads[0].x, 1.5)
        XCTAssertEqual(source.scene.layers[0].quads[0].y, 1.25)
        XCTAssertEqual(
            source.scene.layers[0].quads[0].contentMask.bounds, Rect(x: 0, y: -8, width: 40, height: 50))
        XCTAssertEqual(source.recordCount, 1)
        XCTAssertGreaterThan(source.resourceBytes, MemoryLayout<QuadPrimitive>.stride)
        XCTAssertEqual(source.executionPassCount, 1)
        XCTAssertEqual(source.executionPixelCount, 45)
        XCTAssertFalse(source.wasClipped)
    }

    func testOverlappingRangesKeepLayerMajorPresentationInsteadOfReplayLogOrder() async throws {
        var scene = GPUIScene(clearColor: .clear)
        scene.addQuad(quad(x: 6), toLayer: 1)
        scene.addQuad(quad(x: 4), toLayer: 0)
        scene.addQuad(quad(x: 8), toLayer: 1)
        let source = try captured(scene, ranges: [2..<3, 0..<2, 1..<3])

        XCTAssertEqual(source.recordCount, 3)
        XCTAssertEqual(
            source.scene.paintRecords,
            [
                .primitive(layerIndex: 0, kind: .quad, index: 0),
                .primitive(layerIndex: 1, kind: .quad, index: 0),
                .primitive(layerIndex: 1, kind: .quad, index: 1),
            ])
        XCTAssertEqual(source.scene.layers[0].quads.map(\.x), [0])
        XCTAssertEqual(source.scene.layers[1].quads.map(\.x), [2, 4])
    }

    func testInteriorScopedRangesNormalizeWithoutIncludingUnselectedSiblings() async throws {
        var scene = GPUIScene(clearColor: .clear)
        scene.addQuad(quad(x: 0))
        scene.pushScopedLayer(Rect(x: 0, y: 0, width: 64, height: 64), toLayer: 0)
        scene.addQuad(quad(x: 4))
        scene.pushScopedLayer(Rect(x: 2, y: 2, width: 30, height: 30), toLayer: 0)
        scene.addQuad(quad(x: 8))
        scene.popScopedLayer(fromLayer: 0)
        scene.addQuad(quad(x: 24))
        scene.popScopedLayer(fromLayer: 0)

        let source = try captured(scene, ranges: [2..<3, 4..<5])
        XCTAssertEqual(source.scene.layers[0].quads.map(\.x), [0, 4])
        XCTAssertEqual(source.scene.paintRecordCount, 2)
        var replay = GPUIScene(clearColor: .clear)
        XCTAssertEqual(replay.replay(0..<2, from: source.scene), .success)
    }

    func testEmptyAndMarkerOnlySelectionsAreExplicitButInvalidRangesAreNotEmpty() async {
        var scene = GPUIScene(clearColor: .clear)
        scene.pushScopedLayer(Rect(x: 0, y: 0, width: 8, height: 8), toLayer: 0)
        scene.addQuad(quad())
        scene.popScopedLayer(fromLayer: 0)
        for ranges in [[Range<Int>](), [0..<0], [0..<1, 2..<3]] {
            guard
                case .empty = RetainedLazyListPaintSource.capture(
                    scene: scene, ranges: ranges, surfaceSize: surfaceSize)
            else {
                XCTFail("A proven selection with no primitive records is empty")
                continue
            }
        }
        unsupported(scene, ranges: [-1..<0])
        unsupported(scene, ranges: [0..<Int.max])
        unsupported(scene, ranges: [4..<4])
    }

    func testIncompleteScopeIsRejectedRatherThanPublishedAsNormalizedPaint() async {
        var scene = GPUIScene(clearColor: .clear)
        scene.pushScopedLayer(Rect(x: 0, y: 0, width: 8, height: 8), toLayer: 0)
        scene.addQuad(quad())
        unsupported(scene)
    }

    func testNativeAndPixelAtlasBytesAreFrozenWithoutAnyLiveAtlasLookup() async throws {
        var scene = GPUIScene(clearColor: .clear, glyphAtlas: atlas(), pixelGlyphAtlas: atlas(version: 72, value: 128))
        scene.addGlyph(GlyphPrimitive(screenX: 4, screenY: 6, screenW: 2, screenH: 2))
        scene.addPixelGlyph(GlyphPrimitive(screenX: 8, screenY: 6, screenW: 2, screenH: 2))
        let source = try captured(scene)

        scene.glyphAtlas?.pixels[0] = 0
        scene.pixelGlyphAtlas?.pixels[0] = 0
        XCTAssertEqual(source.scene.glyphAtlas?.pixels.first, 255)
        XCTAssertEqual(source.scene.pixelGlyphAtlas?.pixels.first, 128)
        XCTAssertEqual(source.scene.glyphAtlas?.contentVersion, 71)
        XCTAssertEqual(source.scene.pixelGlyphAtlas?.contentVersion, 72)
        XCTAssertEqual(source.scene.glyphAtlas?.update, .unchanged)
        XCTAssertEqual(source.scene.glyphAtlas?.uploadDecision(for: .uninitialized), .full)
        XCTAssertEqual(source.recordCount, 2)
    }

    func testOnlySelectedImageResourcesAndReferencedChildResourcesSurvive() async throws {
        var child = GPUIScene(clearColor: .black, glyphAtlas: atlas())
        child.bindImageResource(bitmap(31), for: 4)
        child.bindImageResource(bitmap(92), for: 5)
        child.addImage(ImagePrimitive(screenW: 8, screenH: 8, textureID: 4))
        var scene = GPUIScene(clearColor: .clear, glyphAtlas: atlas())
        scene.bindImageResource(bitmap(64), for: 9)
        let id = scene.registerImageRenderPass(child, size: IntSize(width: 8, height: 8))
        _ = scene.registerImageRenderPass(GPUIScene(clearColor: .black), size: IntSize(width: 2, height: 2))
        scene.addImage(ImagePrimitive(screenX: 4, screenY: 6, screenW: 8, screenH: 8, textureID: id))

        let source = try captured(scene)
        XCTAssertTrue(source.scene.imageResources.isEmpty)
        XCTAssertNil(source.scene.glyphAtlas)
        XCTAssertEqual(source.scene.imageRenderPasses.count, 1)
        let pass = try XCTUnwrap(source.scene.imageRenderPasses.first)
        XCTAssertEqual(pass.textureID, id)
        XCTAssertEqual(pass.scene.clearColor, .black)
        XCTAssertEqual(pass.scene.imageResources.map(\.textureID), [4])
        XCTAssertEqual(pass.scene.imageResources.first?.bitmap.pixels.first, 31)
        XCTAssertNil(pass.scene.glyphAtlas)
        XCTAssertEqual(source.recordCount, 2)
    }

    func testDependentSourcesRetainOriginalSurfaceAndNestedInputDescriptors() async throws {
        var material = GPUIScene(clearColor: .clear)
        var panel = quad(x: 0, y: 0, width: 8, height: 8)
        panel.blurRadius = 2
        material.addQuad(panel)
        var middle = GPUIScene(clearColor: .clear)
        let innerID = middle.registerImageRenderPass(
            material, size: IntSize(width: 8, height: 8), input: .currentTarget)
        middle.addImage(ImagePrimitive(screenX: 2, screenY: 2, screenW: 8, screenH: 8, textureID: innerID))
        var scene = GPUIScene(clearColor: .black)
        let outerID = scene.registerImageRenderPass(
            middle, size: IntSize(width: 16, height: 16), input: .isolatedBackdrop, contentBlurRadius: 3)
        scene.addImage(ImagePrimitive(screenX: 4, screenY: 6, screenW: 16, screenH: 16, textureID: outerID))

        let source = try captured(scene)
        XCTAssertEqual(source.input, .isolatedBackdrop)
        XCTAssertEqual(source.bounds, Rect(x: 0, y: 0, width: 64, height: 64))
        XCTAssertEqual(source.size, surfaceSize)
        XCTAssertEqual(source.scene.layers[0].images[0].screenX, 4)
        let outer = try XCTUnwrap(source.scene.imageRenderPasses.first)
        XCTAssertEqual(outer.input, .isolatedBackdrop)
        XCTAssertEqual(outer.contentBlurRadius, 3)
        XCTAssertEqual(outer.scene.imageRenderPasses.first?.input, .currentTarget)
        XCTAssertEqual(outer.scene.imageRenderPasses.first?.scene.layers[0].quads[0].blurRadius, 2)
        XCTAssertEqual(source.recordCount, 3)
    }

    func testIndependentChildDoesNotAcquireTheEnclosingWindowsBackdrop() async throws {
        var child = GPUIScene(clearColor: .clear)
        var value = quad(x: 0, y: 0, width: 8, height: 8)
        value.blurRadius = 2
        child.addQuad(value)
        var scene = GPUIScene(clearColor: .clear)
        let id = scene.registerImageRenderPass(child, size: IntSize(width: 8, height: 8), input: .independent)
        scene.addImage(ImagePrimitive(screenX: 20, screenY: 22, screenW: 8, screenH: 8, textureID: id))

        let source = try captured(scene)
        XCTAssertEqual(source.input, .independent)
        XCTAssertEqual(source.bounds, Rect(x: 20, y: 22, width: 8, height: 8))
        XCTAssertEqual(source.scene.imageRenderPasses.first?.input, .independent)
    }

    func testDirectMaterialKeepsFullTargetWhileSubpixelRadiusRemainsIndependent() async throws {
        var scene = GPUIScene(clearColor: .clear)
        var value = quad()
        value.blurRadius = 1
        scene.addQuad(value)
        let dependent = try captured(scene)
        XCTAssertEqual(dependent.input, .isolatedBackdrop)
        XCTAssertEqual(dependent.size, surfaceSize)

        var subpixel = GPUIScene(clearColor: .clear)
        value.blurRadius = 0.5
        subpixel.addQuad(value)
        XCTAssertEqual(try captured(subpixel).input, .independent)
    }

    func testDependentPlacementCannotBeReinterpretedAsIndependentPaint() async {
        var child = GPUIScene(clearColor: .clear)
        child.addQuad(quad(x: 0, y: 0, width: 8, height: 8))
        for input in [GPUISceneImageRenderPassInput.currentTarget, .isolatedBackdrop] {
            var scene = GPUIScene(clearColor: .clear)
            let id = scene.registerImageRenderPass(child, size: IntSize(width: 8, height: 8), input: input)
            scene.addImage(ImagePrimitive(screenX: 1.5, screenY: 2, screenW: 8, screenH: 8, textureID: id))
            unsupported(scene)
        }
    }

    func testMissingAndMalformedOwnedResourcesAreUnsupported() async {
        var missingAtlas = GPUIScene(clearColor: .clear)
        missingAtlas.addGlyph(GlyphPrimitive(screenW: 2, screenH: 2))
        unsupported(missingAtlas)
        missingAtlas.glyphAtlas = GlyphAtlasSnapshot(width: .max, height: .max, pixels: Data())
        unsupported(missingAtlas)

        var missingImage = GPUIScene(clearColor: .clear)
        missingImage.addImage(ImagePrimitive(screenW: 2, screenH: 2, textureID: 7))
        unsupported(missingImage)
        missingImage.bindImageResource(BitmapSurface(width: 2, height: 2, bytesPerRow: 8, pixels: Data([1])), for: 7)
        unsupported(missingImage)
    }

    func testUnusedMalformedResourcesAreNotRetainedOrResolved() async throws {
        var scene = GPUIScene(clearColor: .clear)
        scene.bindImageResource(BitmapSurface(width: -1, height: 2, bytesPerRow: 8, pixels: Data()), for: 7)
        scene.addQuad(quad())
        XCTAssertTrue(try captured(scene).scene.imageResources.isEmpty)
    }

    func testCapturedBitmapOwnsBytesInsteadOfBorrowingExternalStorage() async throws {
        let storage = UnsafeMutableRawPointer.allocate(byteCount: 1_024, alignment: 1)
        defer { storage.deallocate() }
        storage.initializeMemory(as: UInt8.self, repeating: 37, count: 1_024)
        let borrowed = Data(bytesNoCopy: storage, count: 1_024, deallocator: .none)
        var scene = GPUIScene(clearColor: .clear)
        scene.bindImageResource(BitmapSurface(width: 16, height: 16, bytesPerRow: 64, pixels: borrowed), for: 3)
        scene.addImage(ImagePrimitive(screenW: 16, screenH: 16, textureID: 3))
        let source = try captured(scene)

        storage.storeBytes(of: UInt8(0), as: UInt8.self)
        XCTAssertEqual(scene.imageResources.first?.bitmap.pixels.first, 0)
        XCTAssertEqual(source.scene.imageResources.first?.bitmap.pixels.first, 37)
    }

    func testBitmapBindingUsesLastOwnedValueButConflictingPassIsUnsupported() async throws {
        var scene = GPUIScene(clearColor: .clear)
        scene.imageResources = [
            ImageResourceBinding(textureID: 3, bitmap: bitmap(17)),
            ImageResourceBinding(textureID: 3, bitmap: bitmap(28)),
        ]
        scene.addImage(ImagePrimitive(screenW: 2, screenH: 2, textureID: 3))
        XCTAssertEqual(try captured(scene).scene.imageResources.first?.bitmap.pixels.first, 28)
        scene.imageRenderPasses = [
            GPUISceneImageRenderPass(
                textureID: 3, scene: GPUIScene(clearColor: .clear), size: IntSize(width: 2, height: 2))
        ]
        unsupported(scene)
    }

    func testNonzeroReservedBlendModeIsNotClaimedAsSupportedDestinationBlending() async {
        var scene = GPUIScene(clearColor: .clear)
        var value = quad()
        value.blendMode = 1
        scene.addQuad(value)
        unsupported(scene)
    }

    func testMalformedNestedPresentationAndSanitationChangesAreRejected() async {
        for operation in [
            GPUIPaintOperation(kind: .quad, startIndex: 0, count: 0),
            GPUIPaintOperation(kind: .quad, startIndex: .max, count: 1),
        ] {
            var child = GPUIScene(clearColor: .clear)
            child.installHandBuiltLayers([GPUILayer(quads: [quad()], paintOperations: [operation])])
            var scene = GPUIScene(clearColor: .clear)
            let id = scene.registerImageRenderPass(child, size: IntSize(width: 16, height: 16))
            scene.addImage(ImagePrimitive(screenW: 16, screenH: 16, textureID: id))
            unsupported(scene)
        }
        var child = GPUIScene(clearColor: .clear)
        var invalid = quad()
        invalid.startR = .nan
        child.installHandBuiltLayers(
            [GPUILayer(quads: [invalid], paintOperations: [GPUIPaintOperation(kind: .quad, startIndex: 0)])])
        var scene = GPUIScene(clearColor: .clear)
        let id = scene.registerImageRenderPass(child, size: IntSize(width: 16, height: 16))
        scene.addImage(ImagePrimitive(screenW: 16, screenH: 16, textureID: id))
        unsupported(scene)
    }

    func testAddedWrapperConsumesDepthAndSourcePixels() async {
        var deep = GPUIScene(clearColor: .clear)
        deep.addQuad(quad(x: 0, y: 0, width: 2, height: 2))
        for _ in 0..<GPUISceneLimits.maxImageRenderPassDepth {
            var parent = GPUIScene(clearColor: .clear)
            let id = parent.registerImageRenderPass(deep, size: IntSize(width: 2, height: 2))
            parent.addImage(ImagePrimitive(screenW: 2, screenH: 2, textureID: id))
            deep = parent
        }
        XCTAssertTrue(deep.validate().isEmpty)
        XCTAssertNotNil(RetainedLazyListPaintSource.freezingResources(in: deep))
        XCTAssertEqual(
            RetainedLazyListPaintSource.executionCost(scene: deep, surfaceSize: surfaceSize)?.passCount,
            GPUISceneLimits.maxImageRenderPassDepth)
        unsupported(deep)

        var material = GPUIScene(clearColor: .clear)
        var value = quad()
        value.blurRadius = 2
        material.addQuad(value)
        // The declared source fits four million pixels, but its eight-plane
        // isolation wrapper does not fit the cumulative execution reservation.
        unsupported(material, size: IntSize(width: 2_048, height: 2_048))
    }

    func testRepeatedDependentOccurrencesSpendExecutionBudgetAgain() async {
        var child = GPUIScene(clearColor: .clear)
        child.addQuad(quad(x: 0, y: 0, width: 2, height: 2))
        var scene = GPUIScene(clearColor: .clear)
        let id = scene.registerImageRenderPass(
            child, size: IntSize(width: 1_024, height: 1_024), input: .isolatedBackdrop)
        scene.addImage(ImagePrimitive(screenW: 1_024, screenH: 1_024, textureID: id))
        scene.addImage(ImagePrimitive(screenX: 2, screenW: 1_024, screenH: 1_024, textureID: id))

        XCTAssertTrue(scene.validate().isEmpty, "Structural validation charges the declared source once")
        unsupported(scene)
    }

    func testRecordRangeAndExtentLimitsRejectWithoutInventingEmptyPaint() async {
        var scene = GPUIScene(clearColor: .clear)
        scene.addQuad(quad())
        unsupported(scene, ranges: Array(repeating: 0..<1, count: RetainedLazyListPaintSource.maximumRangeCount + 1))
        unsupported(scene, size: .zero)
        unsupported(scene, size: IntSize(width: .max, height: .max))
        var oversized = GPUIScene(clearColor: .clear)
        oversized.addQuad(quad(x: 0, y: 0, width: 4_096, height: 4_096))
        unsupported(oversized)

        var records = GPUIScene(clearColor: .clear)
        for _ in 0...RetainedLazyListPaintSource.maximumRecordCount { records.addQuad(quad()) }
        unsupported(records)
    }

    func testKnownAtlasVersionsRetainOneCanonicalBufferAcrossChildNamespaces() async throws {
        func scene(version: UInt64) -> GPUIScene {
            var child = GPUIScene(clearColor: .clear, glyphAtlas: atlas(version: version, extent: 16))
            child.addGlyph(GlyphPrimitive(screenW: 2, screenH: 2))
            var scene = GPUIScene(clearColor: .clear)
            for x: Float in [0, 4] {
                let id = scene.registerImageRenderPass(child, size: IntSize(width: 2, height: 2))
                scene.addImage(ImagePrimitive(screenX: x, screenW: 2, screenH: 2, textureID: id))
            }
            return scene
        }
        let shared = try captured(scene(version: 71))
        let anonymous = try captured(scene(version: 0))
        XCTAssertEqual(shared.recordCount, 4)
        XCTAssertEqual(
            anonymous.resourceBytes - shared.resourceBytes,
            16 * 16 * 4 + MemoryLayout<GlyphAtlasSnapshot>.stride)
    }

    func testResourceAccountingIncludesSparseLayerContainers() async throws {
        var compact = GPUIScene(clearColor: .clear)
        compact.addQuad(quad())
        var sparse = GPUIScene(clearColor: .clear)
        sparse.addQuad(quad(), toLayer: GPUISceneLimits.maxLayers - 1)
        let compactSource = try captured(compact)
        let sparseSource = try captured(sparse)
        XCTAssertEqual(
            sparseSource.resourceBytes - compactSource.resourceBytes,
            (sparseSource.scene.layers.capacity - compactSource.scene.layers.capacity) * MemoryLayout<GPUILayer>.stride)
    }

    func testNormalPaintFreezePreservesNamespacesAndFreezesBeforeDeparture() async throws {
        let storage = UnsafeMutableRawPointer.allocate(byteCount: 1_024, alignment: 1)
        defer { storage.deallocate() }
        storage.initializeMemory(as: UInt8.self, repeating: 37, count: 1_024)
        let borrowed = Data(bytesNoCopy: storage, count: 1_024, deallocator: .none)
        let bitmap = BitmapSurface(width: 16, height: 16, bytesPerRow: 64, pixels: borrowed)
        var borrowedAtlas = atlas(version: 87, extent: 16)
        borrowedAtlas.pixels = borrowed
        var child = GPUIScene(clearColor: .clear, glyphAtlas: borrowedAtlas)
        child.bindImageResource(bitmap, for: 2)
        child.pushScopedLayer(Rect(x: 0, y: 0, width: 8, height: 8), toLayer: 0)
        child.addImage(ImagePrimitive(screenW: 4, screenH: 4, textureID: 2))
        child.addGlyph(GlyphPrimitive(screenX: 4, screenW: 2, screenH: 2))
        child.popScopedLayer(fromLayer: 0)

        var scene = GPUIScene(clearColor: .black, glyphAtlas: borrowedAtlas, pixelGlyphAtlas: borrowedAtlas)
        scene.imageResources = [
            ImageResourceBinding(textureID: 7, bitmap: bitmap),
            ImageResourceBinding(textureID: 7, bitmap: bitmap),
        ]
        let id = scene.registerImageRenderPass(child, size: IntSize(width: 8, height: 8))
        scene.addQuad(quad(), toLayer: 1)
        scene.pushScopedLayer(Rect(x: 0, y: 0, width: 64, height: 64), toLayer: 0)
        scene.addImage(ImagePrimitive(screenW: 4, screenH: 4, textureID: 7), toLayer: 0)
        scene.addImage(ImagePrimitive(screenX: 8, screenW: 8, screenH: 8, textureID: id), toLayer: 0)
        scene.popScopedLayer(fromLayer: 0)

        let frozen = try XCTUnwrap(RetainedLazyListPaintSource.freezingResources(in: scene))
        XCTAssertEqual(frozen, scene)
        XCTAssertEqual(frozen.paintRecords, scene.paintRecords)
        XCTAssertEqual(frozen.layers, scene.layers)
        XCTAssertEqual(frozen.imageResources.map(\.textureID), [7, 7])
        XCTAssertEqual(frozen.imageRenderPasses[0].scene.paintRecords, child.paintRecords)
        XCTAssertEqual(frozen.glyphAtlas?.update, borrowedAtlas.update)
        XCTAssertEqual(
            frozen.imageResources[0].bitmap.contentToken,
            frozen.imageRenderPasses[0].scene.imageResources[0].bitmap.contentToken)

        storage.storeBytes(of: UInt8(0), as: UInt8.self)
        XCTAssertEqual(scene.imageResources[0].bitmap.pixels.first, 0)
        XCTAssertEqual(frozen.imageResources[0].bitmap.pixels.first, 37)
        XCTAssertEqual(frozen.glyphAtlas?.pixels.first, 37)
        XCTAssertEqual(frozen.pixelGlyphAtlas?.pixels.first, 37)
        XCTAssertEqual(frozen.imageRenderPasses[0].scene.glyphAtlas?.pixels.first, 37)
        XCTAssertEqual(try captured(frozen).scene.imageResources[0].bitmap.pixels.first, 37)
    }

    func testFrameFreezeKeepsCommandIndexesAndCanonicalBitmapBytes() async throws {
        let storage = UnsafeMutableRawPointer.allocate(byteCount: 1_024, alignment: 1)
        defer { storage.deallocate() }
        storage.initializeMemory(as: UInt8.self, repeating: 29, count: 1_024)
        let bitmap = BitmapSurface(
            width: 16, height: 16, bytesPerRow: 64,
            pixels: Data(bytesNoCopy: storage, count: 1_024, deallocator: .none))
        let command = DrawBitmapCommand(
            rect: Rect(x: 4, y: 6, width: 8, height: 10), bitmap: bitmap, opacity: 0.25,
            clipRect: Rect(x: 2, y: 2, width: 40, height: 40), blendMode: .multiply)
        let frame = RenderFrame(
            clearColor: .black,
            commands: [
                .fillRect(FillRectCommand(rect: Rect(x: 0, y: 0, width: 64, height: 64), color: .white)),
                .drawBitmap(command), .drawText(DrawTextCommand(text: "Frozen frame", position: .zero)),
                .drawBitmap(command), .applyBlur(BlurCommand(region: Rect(x: 0, y: 0, width: 8, height: 8), radius: 1)),
            ])
        let frozen = try XCTUnwrap(RetainedLazyListPaintSource.freezingResources(in: frame))
        XCTAssertEqual(frozen, frame)
        guard case .drawBitmap(let first) = frozen.commands[1], case .drawBitmap(let second) = frozen.commands[3]
        else { return XCTFail("Bitmap command positions must stay unchanged") }
        XCTAssertEqual(first.bitmap.contentToken, second.bitmap.contentToken)
        XCTAssertEqual(first.rect, command.rect)
        XCTAssertEqual(first.opacity, command.opacity)
        XCTAssertEqual(first.clipRect, command.clipRect)
        XCTAssertEqual(first.blendMode, command.blendMode)
        XCTAssertEqual(first.sampling, command.sampling)
        XCTAssertEqual(first.placement, command.placement)

        storage.storeBytes(of: UInt8(0), as: UInt8.self)
        XCTAssertEqual(bitmap.pixels.first, 0)
        XCTAssertEqual(first.bitmap.pixels.first, 29)
    }

    func testNormalFreezeRefusesMalformedOrUnboundedStorageWithoutCallingItEmpty() async {
        var scene = GPUIScene(clearColor: .clear)
        scene.addQuad(quad())
        scene.bindImageResource(BitmapSurface(width: 2, height: 2, bytesPerRow: 8, pixels: Data()), for: 7)
        XCTAssertNil(RetainedLazyListPaintSource.freezingResources(in: scene))

        var malformed = GPUIScene(clearColor: .clear)
        malformed.installHandBuiltLayers(
            [GPUILayer(quads: [quad()], paintOperations: [GPUIPaintOperation(kind: .quad, startIndex: 0, count: 0)])])
        XCTAssertNil(RetainedLazyListPaintSource.freezingResources(in: malformed))
        XCTAssertNil(RetainedLazyListPaintSource.executionCost(scene: malformed, surfaceSize: surfaceSize))
        XCTAssertNil(
            RetainedLazyListPaintSource.freezingResources(
                in: RenderFrame(
                    commands: Array(repeating: .popClip, count: RetainedLazyListPaintSource.maximumRecordCount + 1))))
    }

    func testNormalFreezeBudgetsReservedPrimitiveStorageNotOnlyItsElementCount() async {
        var quads = [quad()]
        quads.reserveCapacity(RetainedLazyListPaintSource.maximumResourceBytes / MemoryLayout<QuadPrimitive>.stride + 1)
        var scene = GPUIScene(clearColor: .clear)
        scene.installHandBuiltLayers(
            [GPUILayer(quads: quads, paintOperations: [GPUIPaintOperation(kind: .quad, startIndex: 0)])])
        XCTAssertNil(RetainedLazyListPaintSource.freezingResources(in: scene))
    }

    func testLiveExecutionCostHasNoWrapperAndCountsRepeatedIndependentOccurrences() async throws {
        var child = GPUIScene(clearColor: .clear)
        child.addQuad(quad(x: 0, y: 0, width: 4, height: 4))
        XCTAssertEqual(
            RetainedLazyListPaintSource.executionCost(scene: child, surfaceSize: surfaceSize),
            RetainedLazyListPaintSource.ExecutionCost(passCount: 0, pixelCount: 0))
        var scene = GPUIScene(clearColor: .clear)
        let id = scene.registerImageRenderPass(child, size: IntSize(width: 4, height: 4))
        scene.addImage(ImagePrimitive(screenW: 4, screenH: 4, textureID: id))
        scene.addImage(ImagePrimitive(screenX: 8, screenW: 4, screenH: 4, textureID: id))
        XCTAssertEqual(
            RetainedLazyListPaintSource.executionCost(scene: scene, surfaceSize: surfaceSize),
            RetainedLazyListPaintSource.ExecutionCost(passCount: 2, pixelCount: 32))
        let source = try captured(scene)
        XCTAssertEqual(source.executionPassCount, 3)
        XCTAssertEqual(source.executionPixelCount, 80)
    }

    func testLiveExecutionReservationAlsoAccountsUnpresentedDeclarations() async throws {
        var child = GPUIScene(clearColor: .clear)
        child.addQuad(quad(x: 0, y: 0, width: 4, height: 4))
        var scene = GPUIScene(clearColor: .clear)
        _ = scene.registerImageRenderPass(child, size: IntSize(width: 4, height: 4))
        scene.addQuad(quad())
        XCTAssertEqual(
            RetainedLazyListPaintSource.executionCost(scene: scene, surfaceSize: surfaceSize),
            RetainedLazyListPaintSource.ExecutionCost(passCount: 1, pixelCount: 16))
        let source = try captured(scene)
        XCTAssertTrue(source.scene.imageRenderPasses.isEmpty)
        XCTAssertEqual(source.executionPassCount, 1)
        XCTAssertEqual(source.executionPixelCount, 80)
    }

    func testLiveExecutionCostResetsIsolationAtIndependentChildren() async {
        var leaf = GPUIScene(clearColor: .clear)
        leaf.addQuad(quad(x: 0, y: 0, width: 2, height: 2))
        var current = GPUIScene(clearColor: .clear)
        let currentID = current.registerImageRenderPass(
            leaf, size: IntSize(width: 2, height: 2), input: .currentTarget)
        current.addImage(ImagePrimitive(screenW: 2, screenH: 2, textureID: currentID))
        var independent = GPUIScene(clearColor: .clear)
        let independentID = independent.registerImageRenderPass(current, size: IntSize(width: 4, height: 4))
        independent.addImage(ImagePrimitive(screenW: 4, screenH: 4, textureID: independentID))

        func enclosing(_ child: GPUIScene) -> GPUIScene {
            var result = GPUIScene(clearColor: .clear)
            let id = result.registerImageRenderPass(
                child, size: IntSize(width: 8, height: 8), input: .isolatedBackdrop)
            result.addImage(ImagePrimitive(screenW: 8, screenH: 8, textureID: id))
            return result
        }
        XCTAssertEqual(
            RetainedLazyListPaintSource.executionCost(scene: enclosing(independent), surfaceSize: surfaceSize),
            RetainedLazyListPaintSource.ExecutionCost(passCount: 3, pixelCount: 532))
        XCTAssertEqual(
            RetainedLazyListPaintSource.executionCost(scene: enclosing(current), surfaceSize: surfaceSize),
            RetainedLazyListPaintSource.ExecutionCost(passCount: 2, pixelCount: 544))
    }

    func testLiveExecutionCostRejectsRepeatedBudgetExhaustionAndUnavailableTargetPixels() async {
        var child = GPUIScene(clearColor: .clear)
        child.addQuad(quad(x: 0, y: 0, width: 2, height: 2))
        var scene = GPUIScene(clearColor: .clear)
        let id = scene.registerImageRenderPass(
            child, size: IntSize(width: 1_024, height: 1_024), input: .isolatedBackdrop)
        scene.addImage(ImagePrimitive(screenW: 1_024, screenH: 1_024, textureID: id))
        scene.addImage(ImagePrimitive(screenW: 1_024, screenH: 1_024, textureID: id))
        let target = IntSize(width: 1_024, height: 1_024)
        XCTAssertEqual(
            RetainedLazyListPaintSource.executionCost(scene: scene, surfaceSize: target),
            RetainedLazyListPaintSource.ExecutionCost(
                passCount: 2, pixelCount: Int64(GPUISceneLimits.maxImageRenderPassTotalPixels)))
        scene.addImage(ImagePrimitive(screenW: 1_024, screenH: 1_024, textureID: id))
        XCTAssertNil(RetainedLazyListPaintSource.executionCost(scene: scene, surfaceSize: target))

        var outside = GPUIScene(clearColor: .clear)
        let outsideID = outside.registerImageRenderPass(
            child, size: IntSize(width: 4, height: 4), input: .currentTarget)
        outside.addImage(ImagePrimitive(screenW: 4, screenH: 4, textureID: outsideID))
        XCTAssertTrue(outside.validate().isEmpty)
        XCTAssertNil(
            RetainedLazyListPaintSource.executionCost(scene: outside, surfaceSize: IntSize(width: 2, height: 2)))
    }

    func testClippingFlagUsesIndividualRootFootprintsAndFractionalCoverageCells() async throws {
        var value = quad()
        value.contentMask = GPUIContentMask(bounds: Rect(x: 0, y: 0, width: 64, height: 64))
        var scene = GPUIScene(clearColor: .clear)
        scene.addQuad(value)
        XCTAssertFalse(try captured(scene).wasClipped)

        value.contentMask = GPUIContentMask(bounds: Rect(x: 5, y: 0, width: 40, height: 64))
        scene = GPUIScene(clearColor: .clear)
        scene.addQuad(value)
        XCTAssertTrue(try captured(scene).wasClipped)

        value = quad(x: 4.25, y: 6.25, width: 7.5, height: 9.5)
        value.contentMask = GPUIContentMask(bounds: Rect(x: 4.25, y: 6.25, width: 7.5, height: 9.5))
        scene = GPUIScene(clearColor: .clear)
        scene.addQuad(value)
        XCTAssertTrue(try captured(scene).wasClipped)

        value.contentMask = GPUIContentMask(bounds: Rect(x: 0, y: 0, width: 64, height: 64))
        value.clipCornerRadius = 1
        scene = GPUIScene(clearColor: .clear)
        scene.addQuad(value)
        XCTAssertTrue(try captured(scene).wasClipped)
    }

    func testClippingFlagIncludesShadowFalloffButNotChildNamespaceMasks() async throws {
        var shadow = ShadowPrimitive(x: 4, y: 4, width: 4, height: 4)
        shadow.offsetX = 8
        shadow.blurRadius = 2
        shadow.contentMask = GPUIContentMask(bounds: Rect(x: 0, y: 0, width: 12, height: 64))
        var scene = GPUIScene(clearColor: .clear)
        scene.addShadow(shadow)
        XCTAssertTrue(try captured(scene).wasClipped)

        var child = GPUIScene(clearColor: .clear)
        var clipped = quad(x: 0, y: 0, width: 8, height: 8)
        clipped.contentMask = GPUIContentMask(bounds: Rect(x: 1, y: 0, width: 7, height: 8))
        child.addQuad(clipped)
        scene = GPUIScene(clearColor: .clear)
        let id = scene.registerImageRenderPass(child, size: IntSize(width: 8, height: 8))
        scene.addImage(ImagePrimitive(screenW: 8, screenH: 8, textureID: id))
        XCTAssertFalse(try captured(scene).wasClipped)
    }

    func testPathTargetRoundingWithoutExplicitMaskIsConservativelyClipped() async throws {
        var scene = GPUIScene(clearColor: .clear)
        scene.addPath(
            PathPrimitive(
                elements: [.moveTo(.zero), .lineTo(Point(x: 8, y: 0)), .lineTo(Point(x: 8, y: 8)), .close],
                bounds: Rect(x: 0, y: 0, width: 8, height: 8), fillColor: .white, clipCornerRadius: 1))
        let source = try captured(scene)
        XCTAssertTrue(source.wasClipped)
        XCTAssertEqual(source.input, .independent)
        XCTAssertEqual(source.size, surfaceSize)
        XCTAssertEqual(source.bounds, Rect(x: 0, y: 0, width: 64, height: 64))
    }
}
