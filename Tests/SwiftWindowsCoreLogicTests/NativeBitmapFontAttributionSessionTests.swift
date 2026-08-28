import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import WinSDK
import XCTest

@testable import SwiftWindowsUI

@MainActor
final class NativeBitmapFontAttributionSessionTests: XCTestCase {
    func testSessionRetainsOneHandleAndResolvesDuplicatePointerOnceUntilClose() async throws {
        let face = AttributionSessionFakeFace()
        var resolutions = 0
        let session = makeSession { _ in
            resolutions += 1
            return attributionSessionMetadata()
        }
        let observation = try XCTUnwrap(session.observation(for: .folder))
        var first: NativeBitmapFontDrawCapture? = try XCTUnwrap(observation.beginDirectWriteCapture())
        first?.recordDraw(fontFace: face.rawPointer, result: 0)
        first?.recordDraw(fontFace: face.rawPointer, result: 0)
        observation.completeDirectWriteCapture(first, bitmap: bitmap())
        first = nil

        XCTAssertEqual(resolutions, 1)
        XCTAssertEqual(session.retainedFaceCountForTesting, 1)
        XCTAssertEqual(face.state.addRefCalls, 1)
        XCTAssertEqual(face.state.releaseCalls, 0)
        XCTAssertEqual(face.state.references, 2)

        var second: NativeBitmapFontDrawCapture? = try XCTUnwrap(observation.beginDirectWriteCapture())
        second?.recordDraw(fontFace: face.rawPointer, result: 0)
        observation.completeDirectWriteCapture(second, bitmap: bitmap())
        second = nil
        XCTAssertEqual(resolutions, 1)
        XCTAssertEqual(session.retainedFaceCountForTesting, 1)
        XCTAssertEqual(face.state.addRefCalls, 2)
        XCTAssertEqual(face.state.releaseCalls, 1)

        session.close()
        session.close()
        XCTAssertEqual(session.retainedFaceCountForTesting, 0)
        XCTAssertEqual(session.receiptCountForTesting, 0)
        XCTAssertEqual(face.state.releaseCalls, 2)
        XCTAssertEqual(face.state.references, 1)
        XCTAssertNil(observation.beginDirectWriteCapture())
    }

    func testEquivalentMetadataDeduplicatesOutputWithoutDroppingDistinctFaceLifetimes() async throws {
        let first = AttributionSessionFakeFace()
        let second = AttributionSessionFakeFace()
        var resolutions = 0
        let session = makeSession { _ in
            resolutions += 1
            return attributionSessionMetadata()
        }
        let observation = try XCTUnwrap(session.observation(for: .folder))
        let surface = bitmap()
        try completeRaster(observation, faces: [first, second], bitmap: surface)
        observation.accept(surface, cacheHit: false)

        XCTAssertEqual(resolutions, 2)
        XCTAssertEqual(session.retainedFaceCountForTesting, 2)
        let report = session.finish(scene: scene(referencing: [surface]))
        XCTAssertEqual(report.faces.count, 1)
        XCTAssertEqual(matching(report, outcome: .sceneReferenced).first?.faceIDs.count, 1)
        XCTAssertEqual(first.state.references, 1)
        XCTAssertEqual(second.state.references, 1)
        XCTAssertEqual(session.retainedFaceCountForTesting, 0)
    }

    func testCaptureAndSessionFaceCapsNeverResolveOrRetainOverflow() async throws {
        let first = AttributionSessionFakeFace()
        let overflow = AttributionSessionFakeFace()
        var bounds = NativeBitmapFontAttributionSession.Bounds()
        bounds.faces = 1
        var resolutions = 0
        let session = makeSession(bounds: bounds) { _ in
            resolutions += 1
            return attributionSessionMetadata()
        }
        let observation = try XCTUnwrap(session.observation(for: .folder))
        try completeRaster(observation, faces: [first, overflow], bitmap: bitmap())
        XCTAssertEqual(overflow.state.addRefCalls, 0, "The per-raster cap must precede AddRef")
        try completeRaster(observation, faces: [overflow], bitmap: bitmap())
        XCTAssertEqual(overflow.state.addRefCalls, 1)
        XCTAssertEqual(overflow.state.releaseCalls, 1, "The full session must not retain another face")
        XCTAssertEqual(resolutions, 1)
        XCTAssertEqual(session.retainedFaceCountForTesting, 1)

        let report = session.finish(scene: GPUIScene())
        XCTAssertEqual(report.faces.count, 1)
        XCTAssertEqual(report.limits.maxFaces, 1)
        XCTAssertGreaterThan(report.limits.dropped, 0)
        XCTAssertEqual(report.status, "partial")
        XCTAssertEqual(first.state.references, 1)
    }

    func testRasterAttemptCapReturnsNoFurtherCaptureAndKeepsReportPartial() async throws {
        var bounds = NativeBitmapFontAttributionSession.Bounds()
        bounds.rasterAttempts = 1
        let session = makeSession(bounds: bounds)
        let observation = try XCTUnwrap(session.observation(for: .folder))
        let face = AttributionSessionFakeFace()
        try completeRaster(observation, faces: [face], bitmap: bitmap())
        XCTAssertNil(observation.beginDirectWriteCapture())
        observation.completeDirectWriteCapture(nil, bitmap: nil)

        let report = session.finish(scene: GPUIScene())
        XCTAssertEqual(report.status, "partial")
        XCTAssertGreaterThan(report.limits.dropped, 0)
        XCTAssertEqual(report.faces.count, 1)
        XCTAssertTrue(matching(report, outcome: .drawUnavailable).contains { $0.faceIDs.isEmpty })
    }

    func testCopiedReceiptIsKnownButMutationAndIndependentEqualBytesAreUnknown() async throws {
        let session = makeSession()
        let observation = try XCTUnwrap(session.observation(for: .folder))
        let face = AttributionSessionFakeFace()
        let original = bitmap()
        try completeRaster(observation, faces: [face], bitmap: original)
        observation.accept(original, cacheHit: false)
        let copy = original
        observation.accept(copy, cacheHit: true)
        XCTAssertEqual(copy.contentKey, original.contentKey)
        XCTAssertEqual(session.receiptCountForTesting, 1)

        var mutated = original
        mutated.pixels = Data([9, 2, 3, 255])
        let independent = BitmapSurface(
            width: original.width, height: original.height, bytesPerRow: original.bytesPerRow,
            pixels: original.pixels)
        XCTAssertNotEqual(mutated.contentKey, original.contentKey)
        XCTAssertEqual(independent, original)
        XCTAssertNotEqual(independent.contentKey, original.contentKey)
        observation.accept(mutated, cacheHit: true)
        observation.accept(independent, cacheHit: true)

        let report = session.finish(scene: scene(referencing: [copy, mutated, independent]))
        let known = try XCTUnwrap(matching(report, outcome: .bitmapCacheHitKnown).first)
        XCTAssertEqual(known.backend, NativeBitmapFontBackend.directWrite.rawValue)
        XCTAssertEqual(known.faceIDs.count, 1)
        let unknown = try XCTUnwrap(matching(report, outcome: .bitmapCacheHitUnobserved).first)
        XCTAssertEqual(unknown.count, 2)
        XCTAssertTrue(unknown.faceIDs.isEmpty)
        XCTAssertEqual(unknown.backend, NativeBitmapFontBackend.unknown.rawValue)
        XCTAssertEqual(matching(report, backend: .unknown, outcome: .sceneReferenced).first?.count, 2)
        XCTAssertEqual(report.status, "partial")
    }

    func testPreexistingCacheHitHasNoInventedNativeFace() async throws {
        let session = makeSession()
        let observation = try XCTUnwrap(session.observation(for: .folder))
        let oldSurface = bitmap()
        observation.accept(oldSurface, cacheHit: true)
        let report = session.finish(scene: scene(referencing: [oldSurface]))

        XCTAssertTrue(report.faces.isEmpty)
        XCTAssertEqual(matching(report, outcome: .bitmapCacheHitUnobserved).count, 1)
        let referenced = try XCTUnwrap(matching(report, outcome: .sceneReferenced).first)
        XCTAssertEqual(referenced.backend, NativeBitmapFontBackend.unknown.rawValue)
        XCTAssertTrue(referenced.faceIDs.isEmpty)
        XCTAssertEqual(report.status, "partial")
    }

    func testCandidateAndSentinelFacesCannotOwnDisplayBitmapReceipts() async throws {
        let candidateFace = AttributionSessionFakeFace()
        let sentinelFace = AttributionSessionFakeFace()
        let displayFace = AttributionSessionFakeFace()
        let names = [
            UInt(bitPattern: candidateFace.rawPointer): "Candidate",
            UInt(bitPattern: sentinelFace.rawPointer): "Sentinel",
            UInt(bitPattern: displayFace.rawPointer): "Display",
        ]
        let session = makeSession { face in
            attributionSessionMetadata(name: names[UInt(bitPattern: face.rawPointer)] ?? "Unexpected")
        }
        let display = try XCTUnwrap(session.observation(for: .folder))
        let probeBitmap = bitmap()
        try completeRaster(display.withPurpose(.candidateProbe), faces: [candidateFace], bitmap: probeBitmap)
        try completeRaster(display.withPurpose(.sentinelProbe), faces: [sentinelFace], bitmap: bitmap())
        XCTAssertEqual(session.receiptCountForTesting, 0)
        display.withPurpose(.candidateProbe).noteProbeCacheHit()
        display.accept(probeBitmap, cacheHit: true)

        let finalBitmap = bitmap()
        try completeRaster(display, faces: [displayFace], bitmap: finalBitmap)
        display.accept(finalBitmap, cacheHit: false)
        let report = session.finish(scene: scene(referencing: [probeBitmap, finalBitmap]))
        let displayID = try XCTUnwrap(report.faces.first { $0.metadata.familyName == "Display" }?.id)
        XCTAssertEqual(matching(report, purpose: .candidateProbe, outcome: .drawProduced).count, 1)
        XCTAssertEqual(matching(report, purpose: .sentinelProbe, outcome: .drawProduced).count, 1)
        XCTAssertTrue(matching(report, outcome: .probeCacheHit).allSatisfy { $0.faceIDs.isEmpty })
        XCTAssertEqual(matching(report, outcome: .bitmapCacheHitUnobserved).count, 1)
        let acceptedFaces = Set(matching(report, purpose: .displayBitmap, outcome: .sceneReferenced).flatMap(\.faceIDs))
        XCTAssertEqual(acceptedFaces, Set([displayID]))
        XCTAssertTrue(matching(report, purpose: .candidateProbe, outcome: .sceneReferenced).isEmpty)
        XCTAssertTrue(matching(report, purpose: .sentinelProbe, outcome: .sceneReferenced).isEmpty)
    }

    func testGDIAndTestingOverrideDoNotInheritFailedDirectWriteFaces() async throws {
        let session = makeSession()
        let observation = try XCTUnwrap(session.observation(for: .folder))
        let failedFace = AttributionSessionFakeFace()
        try completeRaster(observation, faces: [failedFace], bitmap: nil, result: -1)
        let gdiBitmap = bitmap()
        observation.recordGDIResult(bitmap: gdiBitmap)
        observation.accept(gdiBitmap, cacheHit: false)
        let overrideBitmap = bitmap()
        observation.recordTestingOverrideResult(bitmap: overrideBitmap)
        observation.accept(overrideBitmap, cacheHit: false)
        observation.withPurpose(.candidateProbe).recordTestingOverrideResult(bitmap: nil)
        observation.recordGDIResult(bitmap: nil)

        let report = session.finish(scene: scene(referencing: [gdiBitmap, overrideBitmap]))
        XCTAssertEqual(report.faces.count, 1, "The failed attempted face remains diagnostic evidence only")
        for backend in [NativeBitmapFontBackend.gdi, .testingOverride] {
            let used = try XCTUnwrap(matching(report, backend: backend, outcome: .sceneReferenced).first)
            XCTAssertTrue(used.faceIDs.isEmpty)
        }
        XCTAssertTrue(matching(report, backend: .directWrite, outcome: .sceneReferenced).isEmpty)
        XCTAssertEqual(matching(report, backend: .gdi, outcome: .drawUnavailable).count, 1)
        XCTAssertEqual(matching(report, purpose: .candidateProbe, outcome: .testingOverride).count, 1)
        XCTAssertEqual(report.status, "partial")
    }

    func testVectorSelectionHasNoDirectWriteOwnerOrClaimOfPixelContribution() async throws {
        let session = makeSession()
        let observation = try XCTUnwrap(session.observation(for: .sparkle))
        observation.selectVector()
        let report = session.finish(scene: GPUIScene())

        XCTAssertEqual(matching(report, backend: .vector, outcome: .vectorSelected).count, 1)
        XCTAssertTrue(report.faces.isEmpty)
        XCTAssertTrue(matching(report, outcome: .sceneReferenced).isEmpty)
        XCTAssertEqual(report.coverage.sceneReferences, "partial")
        XCTAssertEqual(report.coverage.atlasGlyphs, "not-instrumented")
        XCTAssertEqual(report.coverage.textLayouts, "not-instrumented")
        XCTAssertEqual(report.qualification, "unqualified")
    }

    func testObservationsAndPurposeCopiesDoNotRetainClosedOrReleasedSession() async throws {
        let face = AttributionSessionFakeFace()
        var session: NativeBitmapFontAttributionSession? = makeSession()
        weak var weakSession = session
        let observation = try XCTUnwrap(session?.observation(for: .folder))
        let candidate = observation.withPurpose(.candidateProbe)
        try completeRaster(observation, faces: [face], bitmap: bitmap())
        session?.close()
        XCTAssertEqual(face.state.references, 1)
        XCTAssertNil(observation.beginDirectWriteCapture())
        observation.recordGDIResult(bitmap: bitmap())
        XCTAssertEqual(session?.receiptCountForTesting, 0)

        session = nil
        XCTAssertNil(weakSession)
        XCTAssertNil(observation.owner)
        XCTAssertNil(candidate.owner)
        XCTAssertNil(candidate.beginDirectWriteCapture())
        candidate.recordTestingOverrideResult(bitmap: nil)
        candidate.noteProbeCacheHit()
        XCTAssertEqual(face.state.references, 1)
    }

    func testIndependentSessionsDoNotShareFaceOrBitmapOwnership() async throws {
        let outerFace = AttributionSessionFakeFace()
        let innerFace = AttributionSessionFakeFace()
        let outer = makeSession { _ in attributionSessionMetadata(name: "Outer") }
        let inner = makeSession { _ in attributionSessionMetadata(name: "Inner") }
        let outerObservation = try XCTUnwrap(outer.observation(for: .folder))
        let innerObservation = try XCTUnwrap(inner.observation(for: .folder))
        let outerBitmap = bitmap()
        let innerBitmap = bitmap()
        try completeRaster(outerObservation, faces: [outerFace], bitmap: outerBitmap)
        outerObservation.accept(outerBitmap, cacheHit: false)
        try completeRaster(innerObservation, faces: [innerFace], bitmap: innerBitmap)
        innerObservation.accept(innerBitmap, cacheHit: false)
        outerObservation.accept(innerBitmap, cacheHit: true)

        let innerReport = inner.finish(scene: scene(referencing: [innerBitmap]))
        XCTAssertEqual(innerReport.faces.map(\.metadata.familyName), ["Inner"])
        XCTAssertEqual(innerFace.state.references, 1)
        XCTAssertEqual(outerFace.state.references, 2)
        let outerReport = outer.finish(scene: scene(referencing: [outerBitmap, innerBitmap]))
        XCTAssertEqual(outerReport.faces.map(\.metadata.familyName), ["Outer"])
        XCTAssertEqual(matching(outerReport, outcome: .bitmapCacheHitUnobserved).count, 1)
        XCTAssertTrue(
            matching(outerReport, backend: .unknown, outcome: .sceneReferenced).allSatisfy {
                $0.faceIDs.isEmpty
            })
        XCTAssertEqual(outerFace.state.references, 1)
    }

    func testStopRecordingAndRepeatedFinishCannotCollectAuxiliaryWork() async throws {
        let session = makeSession()
        let observation = try XCTUnwrap(session.observation(for: .folder))
        let face = AttributionSessionFakeFace()
        let surface = bitmap()
        try completeRaster(observation, faces: [face], bitmap: surface)
        observation.accept(surface, cacheHit: false)
        session.stopRecording()
        XCTAssertNil(session.observation(for: .folder))
        XCTAssertNil(observation.beginDirectWriteCapture())
        observation.completeDirectWriteCapture(nil, bitmap: bitmap())
        observation.recordGDIResult(bitmap: bitmap())
        observation.recordTestingOverrideResult(bitmap: bitmap())
        observation.accept(bitmap(), cacheHit: true)
        observation.selectVector()
        XCTAssertEqual(session.receiptCountForTesting, 1)

        let first = session.finish(scene: scene(referencing: [surface]))
        XCTAssertTrue(matching(first, backend: .gdi).isEmpty)
        XCTAssertTrue(matching(first, backend: .testingOverride).isEmpty)
        XCTAssertTrue(matching(first, backend: .vector).isEmpty)
        XCTAssertEqual(matching(first, outcome: .sceneReferenced).count, 1)
        XCTAssertEqual(face.state.references, 1)
        session.close()
        let repeated = session.finish(scene: GPUIScene())
        XCTAssertEqual(try encoded(first), try encoded(repeated))
    }

    func testResolverClosingSessionCannotResurrectHandlesOrReceipts() async throws {
        weak var weakSession: NativeBitmapFontAttributionSession?
        let session = makeSession { _ in
            weakSession?.close()
            return attributionSessionMetadata()
        }
        weakSession = session
        let observation = try XCTUnwrap(session.observation(for: .folder))
        let face = AttributionSessionFakeFace()
        try completeRaster(observation, faces: [face], bitmap: bitmap())

        XCTAssertEqual(session.retainedFaceCountForTesting, 0)
        XCTAssertEqual(session.receiptCountForTesting, 0)
        XCTAssertEqual(face.state.references, 1)
        let report = session.finish(scene: GPUIScene())
        XCTAssertTrue(report.faces.isEmpty)
        XCTAssertTrue(report.observations.isEmpty)
        XCTAssertEqual(report.status, "partial")
    }

    func testRepeatedProductionReceiptPreservesEveryAcceptedRole() async throws {
        let session = makeSession()
        let folder = try XCTUnwrap(session.observation(for: .folder))
        let star = try XCTUnwrap(session.observation(for: .star))
        let shared = bitmap()
        folder.recordTestingOverrideResult(bitmap: shared)
        folder.accept(shared, cacheHit: false)
        star.recordTestingOverrideResult(bitmap: shared)
        star.accept(shared, cacheHit: false)

        let report = session.finish(scene: scene(referencing: [shared]))
        let references = matching(report, backend: .testingOverride, outcome: .sceneReferenced)
        XCTAssertEqual(Set(references.map(\.role)), Set(["folder", "star"]))
        XCTAssertTrue(references.allSatisfy { $0.faceIDs.isEmpty })
    }

    func testConflictingReceiptDowngradesOwnershipButPreservesAcceptedRoles() async throws {
        let session = makeSession()
        let folder = try XCTUnwrap(session.observation(for: .folder))
        let star = try XCTUnwrap(session.observation(for: .star))
        let shared = bitmap()
        let face = AttributionSessionFakeFace()
        try completeRaster(folder, faces: [face], bitmap: shared)
        folder.accept(shared, cacheHit: false)
        star.recordGDIResult(bitmap: shared)
        star.accept(shared, cacheHit: false)

        let report = session.finish(scene: scene(referencing: [shared]))
        let references = matching(report, outcome: .sceneReferenced)
        XCTAssertEqual(Set(references.map(\.role)), Set(["folder", "star"]))
        XCTAssertTrue(
            references.allSatisfy {
                $0.backend == NativeBitmapFontBackend.unknown.rawValue && $0.faceIDs.isEmpty
            })
        XCTAssertEqual(report.status, "partial")
    }

    func testResourceRegistrationAloneIsNotScenePresentation() async throws {
        let session = makeSession()
        let folder = try XCTUnwrap(session.observation(for: .folder))
        let star = try XCTUnwrap(session.observation(for: .star))
        let shown = bitmap()
        let registeredOnly = bitmap()
        let face = AttributionSessionFakeFace()
        try completeRaster(folder, faces: [face], bitmap: shown)
        folder.accept(shown, cacheHit: false)
        try completeRaster(star, faces: [face], bitmap: registeredOnly)
        star.accept(registeredOnly, cacheHit: false)

        let report = session.finish(scene: scene(referencing: [shown], registeringOnly: [registeredOnly]))
        XCTAssertEqual(matching(report, role: .folder, outcome: .sceneReferenced).count, 1)
        XCTAssertEqual(matching(report, role: .star, outcome: .notReferenced).count, 1)
        XCTAssertTrue(matching(report, role: .star, outcome: .sceneReferenced).isEmpty)
        XCTAssertEqual(report.coverage.sceneReferences, "observed")
    }

    func testTraversalPreflightCapsReportUnknownRatherThanAbsent() async throws {
        typealias Bounds = NativeBitmapFontAttributionSession.Bounds
        let cases: [(String, (inout Bounds) -> Void)] = [
            ("resources", { $0.sceneResources = 0 }),
            ("primitives", { $0.scenePrimitives = 0 }),
            ("layers", { $0.sceneLayers = 0 }),
            ("operations", { $0.sceneOperations = 0 }),
        ]
        for (name, configure) in cases {
            var bounds = Bounds()
            configure(&bounds)
            let session = makeSession(bounds: bounds)
            let observation = try XCTUnwrap(session.observation(for: .folder))
            let surface = bitmap()
            let face = AttributionSessionFakeFace()
            try completeRaster(observation, faces: [face], bitmap: surface)
            observation.accept(surface, cacheHit: false)
            let report = session.finish(scene: scene(referencing: [surface]))

            XCTAssertEqual(matching(report, outcome: .sceneAssociationUnobserved).count, 1, name)
            XCTAssertTrue(matching(report, outcome: .notReferenced).isEmpty, name)
            XCTAssertTrue(matching(report, outcome: .sceneReferenced).isEmpty, name)
            XCTAssertEqual(report.coverage.sceneReferences, "partial", name)
            XCTAssertEqual(report.status, "partial", name)
            XCTAssertGreaterThan(report.limits.dropped, 0, name)
        }
    }

    func testPrimitiveCapKeepsKnownPrefixAndMarksUnvisitedReceiptUnknown() async throws {
        var bounds = NativeBitmapFontAttributionSession.Bounds()
        bounds.scenePrimitives = 1
        let session = makeSession(bounds: bounds)
        let folder = try XCTUnwrap(session.observation(for: .folder))
        let star = try XCTUnwrap(session.observation(for: .star))
        let first = bitmap()
        let second = bitmap()
        let face = AttributionSessionFakeFace()
        try completeRaster(folder, faces: [face], bitmap: first)
        folder.accept(first, cacheHit: false)
        try completeRaster(star, faces: [face], bitmap: second)
        star.accept(second, cacheHit: false)
        let report = session.finish(scene: scene(referencing: [first, second]))

        XCTAssertEqual(matching(report, role: .folder, outcome: .sceneReferenced).count, 1)
        XCTAssertEqual(matching(report, role: .star, outcome: .sceneAssociationUnobserved).count, 1)
        XCTAssertTrue(matching(report, outcome: .notReferenced).isEmpty)
    }

    func testEmptyLayerAndSkippedOperationCapsApplyBeforeIteratorYield() async throws {
        for layersCase in [true, false] {
            var bounds = NativeBitmapFontAttributionSession.Bounds()
            if layersCase { bounds.sceneLayers = 1 } else { bounds.sceneOperations = 1 }
            let session = makeSession(bounds: bounds)
            let observation = try XCTUnwrap(session.observation(for: .folder))
            let surface = bitmap()
            observation.recordTestingOverrideResult(bitmap: surface)
            observation.accept(surface, cacheHit: false)
            var preparedScene = scene(referencing: [surface])
            if layersCase {
                preparedScene.pushLayer()
                XCTAssertEqual(preparedScene.layers.count, 2)
            } else {
                preparedScene.installHandBuiltLayer(
                    GPUILayer(paintOperations: [
                        GPUIPaintOperation(kind: .image, startIndex: 0),
                        GPUIPaintOperation(kind: .image, startIndex: 1),
                    ]), at: 0)
                XCTAssertEqual(preparedScene.layers[0].paintOperationCount, 2)
            }
            let report = session.finish(scene: preparedScene)
            XCTAssertEqual(matching(report, outcome: .sceneAssociationUnobserved).count, 1)
            XCTAssertTrue(matching(report, outcome: .notReferenced).isEmpty)
            XCTAssertGreaterThan(report.limits.dropped, 0)
        }
    }

    func testNestedRenderPassIsUnobservedAndCannotBorrowTopLevelReceipt() async throws {
        let session = makeSession()
        let observation = try XCTUnwrap(session.observation(for: .folder))
        let surface = bitmap()
        let face = AttributionSessionFakeFace()
        try completeRaster(observation, faces: [face], bitmap: surface)
        observation.accept(surface, cacheHit: false)
        var outer = GPUIScene()
        let passID = outer.registerImageRenderPass(
            scene(referencing: [surface]), size: IntSize(width: 1, height: 1))
        outer.addImage(image(textureID: passID))
        let report = session.finish(scene: outer)

        XCTAssertEqual(matching(report, outcome: .sceneAssociationUnobserved).count, 1)
        XCTAssertTrue(matching(report, outcome: .notReferenced).isEmpty)
        XCTAssertTrue(matching(report, outcome: .sceneReferenced).isEmpty)
        XCTAssertEqual(report.coverage.sceneReferences, "partial")
    }

    func testDuplicateStaticBindingsUseLastBindingRatherThanFirstReceipt() async throws {
        let session = makeSession()
        let folder = try XCTUnwrap(session.observation(for: .folder))
        let star = try XCTUnwrap(session.observation(for: .star))
        let first = bitmap()
        let last = bitmap()
        let face = AttributionSessionFakeFace()
        try completeRaster(folder, faces: [face], bitmap: first)
        folder.accept(first, cacheHit: false)
        try completeRaster(star, faces: [face], bitmap: last)
        star.accept(last, cacheHit: false)
        var preparedScene = GPUIScene(imageResources: [
            ImageResourceBinding(textureID: 7, bitmap: first),
            ImageResourceBinding(textureID: 7, bitmap: last),
        ])
        preparedScene.addImage(image(textureID: 7))
        let report = session.finish(scene: preparedScene)

        XCTAssertEqual(matching(report, role: .folder, outcome: .notReferenced).count, 1)
        XCTAssertTrue(matching(report, role: .folder, outcome: .sceneReferenced).isEmpty)
        XCTAssertEqual(matching(report, role: .star, outcome: .sceneReferenced).count, 1)
        XCTAssertEqual(report.coverage.sceneReferences, "observed")
    }

    func testMatchingRenderPassCannotBorrowSameNumberedStaticBinding() async throws {
        let session = makeSession()
        let observation = try XCTUnwrap(session.observation(for: .folder))
        let surface = bitmap()
        let face = AttributionSessionFakeFace()
        try completeRaster(observation, faces: [face], bitmap: surface)
        observation.accept(surface, cacheHit: false)
        var preparedScene = GPUIScene(
            imageResources: [ImageResourceBinding(textureID: 7, bitmap: surface)],
            imageRenderPasses: [
                GPUISceneImageRenderPass(
                    textureID: 7, scene: scene(referencing: [surface]),
                    size: IntSize(width: 1, height: 1), colorEffects: [])
            ])
        preparedScene.addImage(image(textureID: 7))
        let report = session.finish(scene: preparedScene)

        XCTAssertEqual(matching(report, outcome: .sceneAssociationUnobserved).count, 1)
        XCTAssertTrue(matching(report, outcome: .sceneReferenced).isEmpty)
        XCTAssertTrue(matching(report, outcome: .notReferenced).isEmpty)
        XCTAssertEqual(report.coverage.sceneReferences, "partial")
    }

    func testRenderPassCountIsBoundedEvenWhenOnlyStaticBitmapIsPresented() async throws {
        var bounds = NativeBitmapFontAttributionSession.Bounds()
        bounds.sceneResources = 1
        let session = makeSession(bounds: bounds)
        let observation = try XCTUnwrap(session.observation(for: .folder))
        let surface = bitmap()
        let face = AttributionSessionFakeFace()
        try completeRaster(observation, faces: [face], bitmap: surface)
        observation.accept(surface, cacheHit: false)
        var preparedScene = scene(referencing: [surface])
        for _ in 0..<2 {
            preparedScene.registerImageRenderPass(GPUIScene(), size: IntSize(width: 1, height: 1))
        }
        let report = session.finish(scene: preparedScene)

        XCTAssertEqual(matching(report, outcome: .sceneAssociationUnobserved).count, 1)
        XCTAssertTrue(matching(report, outcome: .sceneReferenced).isEmpty)
        XCTAssertTrue(matching(report, outcome: .notReferenced).isEmpty)
        XCTAssertGreaterThan(report.limits.dropped, 0)
    }

    func testReceiptAndObservationMapsStopAtConfiguredCaps() async throws {
        var bounds = NativeBitmapFontAttributionSession.Bounds()
        bounds.receipts = 1
        bounds.observations = 1
        let session = makeSession(bounds: bounds)
        let observation = try XCTUnwrap(session.observation(for: .folder))
        let first = bitmap()
        let second = bitmap()
        observation.recordTestingOverrideResult(bitmap: first)
        observation.accept(first, cacheHit: false)
        observation.recordTestingOverrideResult(bitmap: second)
        observation.accept(second, cacheHit: false)
        XCTAssertEqual(session.receiptCountForTesting, 1)
        let report = session.finish(scene: scene(referencing: [first, second]))

        XCTAssertEqual(report.observations.count, 1)
        XCTAssertEqual(report.limits.maxReceipts, 1)
        XCTAssertEqual(report.limits.maxObservations, 1)
        XCTAssertGreaterThan(report.limits.dropped, 0)
        XCTAssertEqual(report.status, "partial")
    }

    func testNegativeBoundsClampToZeroAndLargeBoundsToHardLimits() async throws {
        for requested in [Int.min, Int.max] {
            let bounds = NativeBitmapFontAttributionSession.Bounds(
                faces: requested, receipts: requested, observations: requested, rasterAttempts: requested,
                scenePrimitives: requested, sceneResources: requested, sceneLayers: requested,
                sceneOperations: requested)
            let session = makeSession(bounds: bounds)
            let observation = try XCTUnwrap(session.observation(for: .folder))
            let surface = bitmap()
            if requested < 0 {
                XCTAssertNil(observation.beginDirectWriteCapture())
            }
            observation.recordTestingOverrideResult(bitmap: surface)
            observation.accept(surface, cacheHit: false)
            let report = session.finish(scene: scene(referencing: [surface]))
            XCTAssertEqual(report.limits.maxFaces, requested < 0 ? 0 : 64)
            XCTAssertEqual(report.limits.maxReceipts, requested < 0 ? 0 : 256)
            XCTAssertEqual(report.limits.maxObservations, requested < 0 ? 0 : 256)
            if requested < 0 {
                XCTAssertTrue(report.faces.isEmpty)
                XCTAssertTrue(report.observations.isEmpty)
                XCTAssertEqual(report.coverage.sceneReferences, "partial")
            } else {
                XCTAssertEqual(matching(report, outcome: .sceneReferenced).count, 1)
                XCTAssertEqual(report.coverage.sceneReferences, "observed")
            }
        }
    }

    func testNoDrawOrFailedDrawCannotProduceAcceptedOwnership() async throws {
        let session = makeSession()
        let observation = try XCTUnwrap(session.observation(for: .folder))
        let empty = try XCTUnwrap(observation.beginDirectWriteCapture())
        observation.completeDirectWriteCapture(empty, bitmap: nil)
        let face = AttributionSessionFakeFace()
        try completeRaster(observation, faces: [face], bitmap: nil, result: -1)
        observation.reject(nil)
        XCTAssertEqual(session.receiptCountForTesting, 0)
        let report = session.finish(scene: GPUIScene())

        XCTAssertEqual(report.status, "partial")
        XCTAssertFalse(matching(report, outcome: .drawUnavailable).isEmpty)
        XCTAssertEqual(matching(report, outcome: .bitmapRejected).count, 1)
        XCTAssertTrue(matching(report, outcome: .bitmapAccepted).isEmpty)
        XCTAssertTrue(matching(report, outcome: .sceneReferenced).isEmpty)
    }

    func testFixtureRoleAllowlistDoesNotAuthorizeOtherSymbols() async throws {
        let palette = makeSession()
        let stepper = makeSession(fixture: .stepper)
        XCTAssertNil(palette.observation(for: .chevronUp))
        XCTAssertNil(stepper.observation(for: .folder))
        XCTAssertEqual(stepper.observation(for: .chevronUp)?.role, .increment)
        XCTAssertEqual(stepper.observation(for: .chevronDown)?.role, .decrement)
        XCTAssertEqual(palette.observation(for: .heartFill)?.role, .heart)
        palette.close()
        stepper.close()
        XCTAssertNil(stepper.observation(for: .chevronUp))
    }

    func testEncodedReportIsOrderIndependentAndContainsOnlyBoundedSchemaFields() async throws {
        let first = AttributionSessionFakeFace()
        let second = AttributionSessionFakeFace()
        let names = [
            UInt(bitPattern: first.rawPointer): "Alpha",
            UInt(bitPattern: second.rawPointer): "Zulu",
        ]
        var reports: [NativeBitmapFontAttributionReport] = []
        for faces in [[first, second], [second, first]] {
            let session = makeSession { face in
                attributionSessionMetadata(name: names[UInt(bitPattern: face.rawPointer)] ?? "Unexpected")
            }
            let observation = try XCTUnwrap(session.observation(for: .folder))
            let surface = bitmap()
            try completeRaster(observation, faces: faces, bitmap: surface)
            observation.accept(surface, cacheHit: false)
            reports.append(session.finish(scene: scene(referencing: [surface])))
        }
        let data = try encoded(reports[0])
        XCTAssertEqual(data, try encoded(reports[1]))
        let object = try JSONSerialization.jsonObject(with: data)
        let allowed: Set<String> = [
            "schemaVersion", "kind", "scope", "fixtureID", "status", "qualification", "coverage",
            "bitmapIcons", "atlasGlyphs", "textLayouts", "sceneReferences", "faces", "id", "metadata",
            "familyName", "faceName", "namesStatus", "faceIndex", "simulations", "files", "filesStatus",
            "basename", "axes", "axesStatus", "tag", "value", "observations", "role", "purpose", "backend",
            "outcome", "faceIDs", "count", "limits", "maxFaces", "maxReceipts", "maxObservations", "dropped",
        ]
        assertJSONKeys(object, allowed: allowed)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        for forbidden in [
            "drawCount", "drawFailures", "glyphIDs", "glyphIndices", "glyphCount", "text", "textHash",
            "source", "sourceText", "secureLength", "contentKey", "contentToken", "cacheKey", "timestamp",
            "eventOrder", "rawPointer", "referenceKey", "absolutePath",
        ] {
            XCTAssertFalse(text.contains("\"\(forbidden)\""), forbidden)
        }
        XCTAssertFalse(text.contains(String(describing: first.rawPointer)))
        XCTAssertFalse(text.contains(String(describing: second.rawPointer)))
        XCTAssertTrue(reports[0].observations.allSatisfy { $0.count == 1 })
        XCTAssertEqual(reports[0].qualification, "unqualified")
    }

    private func makeSession(
        fixture: NativeBitmapFontFixture = .symbolPalette,
        bounds: NativeBitmapFontAttributionSession.Bounds = .init(),
        resolveMetadata: @escaping @MainActor (NativeFontFaceHandle) -> NativeBitmapFontFaceMetadata = { _ in
            attributionSessionMetadata()
        }
    ) -> NativeBitmapFontAttributionSession {
        NativeBitmapFontAttributionSession(fixture: fixture, bounds: bounds, resolveMetadata: resolveMetadata)
    }

    private func completeRaster(
        _ observation: NativeBitmapFontObservation, faces: [AttributionSessionFakeFace],
        bitmap: BitmapSurface?, result: HRESULT = 0
    ) throws {
        let capture = try XCTUnwrap(observation.beginDirectWriteCapture())
        for face in faces {
            capture.recordDraw(fontFace: face.rawPointer, result: result)
        }
        observation.completeDirectWriteCapture(capture, bitmap: bitmap)
    }

    private func bitmap() -> BitmapSurface {
        BitmapSurface(width: 1, height: 1, bytesPerRow: 4, pixels: Data([1, 2, 3, 255]))
    }

    private func image(textureID: Int32) -> ImagePrimitive {
        ImagePrimitive(screenX: 0, screenY: 0, screenW: 1, screenH: 1, textureID: textureID)
    }

    private func scene(
        referencing bitmaps: [BitmapSurface], registeringOnly unused: [BitmapSurface] = []
    ) -> GPUIScene {
        var result = GPUIScene()
        for bitmap in unused {
            _ = result.registerImageResource(bitmap)
        }
        for bitmap in bitmaps {
            let textureID = result.registerImageResource(bitmap)
            result.addImage(image(textureID: textureID))
        }
        result.finish()
        return result
    }

    private func matching(
        _ report: NativeBitmapFontAttributionReport, role: NativeBitmapFontRole? = nil,
        purpose: NativeBitmapFontPurpose? = nil, backend: NativeBitmapFontBackend? = nil,
        outcome: NativeBitmapFontOutcome? = nil
    ) -> [NativeBitmapFontAttributionReport.Observation] {
        report.observations.filter { entry in
            (role == nil || entry.role == role?.rawValue)
                && (purpose == nil || entry.purpose == purpose?.rawValue)
                && (backend == nil || entry.backend == backend?.rawValue)
                && (outcome == nil || entry.outcome == outcome?.rawValue)
        }
    }

    private func encoded(_ report: NativeBitmapFontAttributionReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(report)
    }

    private func assertJSONKeys(
        _ value: Any, allowed: Set<String>, file: StaticString = #filePath, line: UInt = #line
    ) {
        if let object = value as? [String: Any] {
            XCTAssertTrue(
                Set(object.keys).isSubset(of: allowed), "Unexpected serialized fields", file: file, line: line)
            for child in object.values { assertJSONKeys(child, allowed: allowed, file: file, line: line) }
        } else if let array = value as? [Any] {
            for child in array { assertJSONKeys(child, allowed: allowed, file: file, line: line) }
        }
    }
}

private func attributionSessionMetadata(name: String = "Fixture Face") -> NativeBitmapFontFaceMetadata {
    NativeBitmapFontFaceMetadata(
        status: .observed, familyName: name, faceName: "Regular", namesStatus: .observed,
        faceIndex: 0, simulations: 0,
        files: [NativeBitmapFontFileReference(status: .observed, scope: .systemFonts, basename: "fixture.ttf")],
        filesStatus: .observed, axes: [], axesStatus: .observed)
}

// This IUnknown prefix only services the existing handle's AddRef/Release.
// Every metadata resolver above is injected; no real font or DirectWrite call occurs.
private struct AttributionSessionFakeVTable {
    var queryInterface: DWQueryInterfaceProc
    var addRef: DWAddRefProc
    var release: DWReleaseProc
}

private struct AttributionSessionFakeObject {
    var vtable: UnsafeMutablePointer<AttributionSessionFakeVTable>
    var state: UnsafeMutableRawPointer
}

private final class AttributionSessionFakeState {
    var references: ULONG = 1
    var addRefCalls = 0
    var releaseCalls = 0
}

private final class AttributionSessionFakeFace {
    let state: AttributionSessionFakeState
    private let object: UnsafeMutablePointer<AttributionSessionFakeObject>

    init() {
        let state = AttributionSessionFakeState()
        let vtable = UnsafeMutablePointer<AttributionSessionFakeVTable>.allocate(capacity: 1)
        vtable.initialize(
            to: AttributionSessionFakeVTable(
                queryInterface: attributionSessionFakeQueryInterface,
                addRef: attributionSessionFakeAddRef,
                release: attributionSessionFakeRelease))
        let object = UnsafeMutablePointer<AttributionSessionFakeObject>.allocate(capacity: 1)
        object.initialize(
            to: AttributionSessionFakeObject(vtable: vtable, state: Unmanaged.passRetained(state).toOpaque()))
        self.state = state
        self.object = object
    }

    var rawPointer: UnsafeMutableRawPointer { UnsafeMutableRawPointer(object) }

    deinit {
        _ = attributionSessionFakeRelease(UnsafeMutableRawPointer(object))
    }
}

private func attributionSessionFakeQueryInterface(
    _ object: UnsafeMutableRawPointer?, _ iid: UnsafePointer<GUID>?,
    _ result: UnsafeMutablePointer<UnsafeMutableRawPointer?>?
) -> HRESULT {
    result?.pointee = nil
    return HRESULT(bitPattern: 0x8000_4002)
}

private func attributionSessionFakeAddRef(_ rawObject: UnsafeMutableRawPointer?) -> ULONG {
    guard let rawObject else { return 0 }
    let object = rawObject.assumingMemoryBound(to: AttributionSessionFakeObject.self)
    let state = Unmanaged<AttributionSessionFakeState>.fromOpaque(object.pointee.state).takeUnretainedValue()
    state.addRefCalls += 1
    state.references += 1
    return state.references
}

private func attributionSessionFakeRelease(_ rawObject: UnsafeMutableRawPointer?) -> ULONG {
    guard let rawObject else { return 0 }
    let object = rawObject.assumingMemoryBound(to: AttributionSessionFakeObject.self)
    let statePointer = object.pointee.state
    let state = Unmanaged<AttributionSessionFakeState>.fromOpaque(statePointer).takeUnretainedValue()
    state.releaseCalls += 1
    state.references -= 1
    let remaining = state.references
    if remaining == 0 {
        let vtable = object.pointee.vtable
        object.deinitialize(count: 1)
        object.deallocate()
        vtable.deinitialize(count: 1)
        vtable.deallocate()
        Unmanaged<AttributionSessionFakeState>.fromOpaque(statePointer).release()
    }
    return remaining
}

// V2 tests are additive. All resolvers below are injected; the fake face only
// services the existing handle's IUnknown lifetime operations.
extension NativeBitmapFontAttributionSessionTests {
    func testV2EvidenceIsExplicitAndLeavesTheDefaultVersionUnchanged() async throws {
        let legacy = makeSession()
        XCTAssertEqual(legacy.version.rawValue, 1)
        let legacyObservation = try XCTUnwrap(legacy.observation(for: .folder))
        let legacyCapture = try XCTUnwrap(legacyObservation.beginDirectWriteCapture())
        XCTAssertFalse(legacyCapture.capturesGlyphs)
        legacyCapture.recordGlyphRun(nil, result: 0)
        XCTAssertEqual(legacyCapture.drawCount, 0)
        XCTAssertTrue(legacyCapture.glyphRuns.isEmpty)
        XCTAssertNil(legacy.finishV2(scene: GPUIScene()))
        legacy.close()

        let diagnostic = makeV2Session()
        XCTAssertEqual(diagnostic.version.rawValue, 2)
        let report = try XCTUnwrap(diagnostic.finishV2(scene: GPUIScene()))
        XCTAssertEqual(report.schemaVersion, 2)
        XCTAssertEqual(report.kind, "native-bitmap-font-attribution-v2")
        XCTAssertEqual(report.attributionV1.schemaVersion, 1)
        XCTAssertEqual(report.qualification, "unqualified")
        XCTAssertEqual(report.status, "partial")
        XCTAssertTrue(report.glyphRuns.isEmpty)
        XCTAssertEqual(report.coverage.atlasGlyphs, "not-instrumented")
        XCTAssertEqual(report.coverage.textLayouts, "not-instrumented")
        XCTAssertEqual(report.coverage.visiblePixels, "not-observed")
        XCTAssertEqual(report.coverage.loadedBytesDigest, "not-observed")
    }

    func testV2CollectingTheSameDrawDoesNotChangeV1Encoding() async throws {
        let face = AttributionSessionFakeFace()
        var evidenceResolutions = 0
        let glyphEvidence = NativeBitmapGlyphEvidenceSession { _, _ in
            evidenceResolutions += 1
            return NativeBitmapFontFaceEvidenceV2()
        }
        var legacyReports: [NativeBitmapFontAttributionReport] = []
        for enabled in [false, true] {
            let session = enabled ? makeV2Session(glyphEvidence: glyphEvidence) : makeSession()
            let observation = try XCTUnwrap(session.observation(for: .folder))
            let surface = bitmap()
            try completeV2Raster(
                observation, draws: [V2Draw(face: face, glyphs: [14, 0, 9])], bitmap: surface)
            observation.accept(surface, cacheHit: false)
            let legacy = session.finish(scene: scene(referencing: [surface]))
            legacyReports.append(legacy)
            if enabled {
                let report = try XCTUnwrap(session.finishV2(scene: GPUIScene()))
                XCTAssertEqual(try encoded(report.attributionV1), try encoded(legacy))
                XCTAssertEqual(report.glyphRuns.first?.glyphIndices, [14, 0, 9])
            }
        }

        XCTAssertEqual(try encoded(legacyReports[0]), try encoded(legacyReports[1]))
        XCTAssertEqual(evidenceResolutions, 1)
        XCTAssertEqual(face.state.references, 1)
        let legacyText = try XCTUnwrap(String(data: encoded(legacyReports[1]), encoding: .utf8))
        for forbidden in ["glyphIndices", "glyphCount", "drawResult", "runIDs", "runCounts"] {
            XCTAssertFalse(legacyText.contains("\"\(forbidden)\""), forbidden)
        }
    }

    func testV2ProbesAndPreexistingCacheCannotBorrowDisplayGlyphEvidence() async throws {
        let probeFace = AttributionSessionFakeFace()
        let displayFace = AttributionSessionFakeFace()
        var evidenceResolutions = 0
        let glyphEvidence = NativeBitmapGlyphEvidenceSession { _, _ in
            evidenceResolutions += 1
            return NativeBitmapFontFaceEvidenceV2()
        }
        let session = makeV2Session(glyphEvidence: glyphEvidence)
        let display = try XCTUnwrap(session.observation(for: .folder))
        var surfaces: [BitmapSurface] = []
        for purpose in [NativeBitmapFontPurpose.candidateProbe, .sentinelProbe] {
            let probe = display.withPurpose(purpose)
            let capture = try XCTUnwrap(probe.beginDirectWriteCapture())
            XCTAssertFalse(capture.capturesGlyphs)
            recordV2Draw(V2Draw(face: probeFace, glyphs: [65_535]), into: capture)
            capture.recordGlyphRun(nil, result: 0)
            XCTAssertEqual(capture.drawCount, 1)
            XCTAssertTrue(capture.glyphRuns.isEmpty)
            let surface = bitmap()
            probe.completeDirectWriteCapture(capture, bitmap: surface)
            probe.noteProbeCacheHit()
            display.accept(surface, cacheHit: true)
            surfaces.append(surface)
        }
        XCTAssertEqual(glyphEvidence.captureBudget.copiedRuns, 0)
        XCTAssertEqual(glyphEvidence.captureBudget.copiedGlyphs, 0)
        XCTAssertEqual(evidenceResolutions, 0)

        let preexisting = bitmap()
        display.accept(preexisting, cacheHit: true)
        surfaces.append(preexisting)
        let actual = bitmap()
        try completeV2Raster(display, draws: [V2Draw(face: displayFace, glyphs: [77])], bitmap: actual)
        display.accept(actual, cacheHit: false)
        surfaces.append(actual)
        let report = try XCTUnwrap(session.finishV2(scene: scene(referencing: surfaces)))
        XCTAssertEqual(evidenceResolutions, 1)
        XCTAssertEqual(report.faces.count, 1)
        XCTAssertEqual(report.glyphRuns.map(\.glyphIndices), [[77]])
        XCTAssertEqual(report.limits.copiedRuns, 1)
        XCTAssertTrue(report.observations.allSatisfy { $0.purpose == "display-bitmap" })
        let unobserved = try XCTUnwrap(
            matchingV2(report, backend: .unknown, outcome: .sceneReferenced, status: "not-observed").first)
        XCTAssertEqual(unobserved.count, 3)
        XCTAssertTrue(unobserved.runIDs.isEmpty)
        XCTAssertTrue(unobserved.runCounts.isEmpty)
        let actualReference = try XCTUnwrap(
            matchingV2(report, backend: .directWrite, outcome: .sceneReferenced, status: "observed").first)
        XCTAssertEqual(actualReference.runIDs, report.glyphRuns.map(\.id))
    }

    func testV2PreservesGlyphOrderZeroAndPerBitmapRunMultiplicity() async throws {
        let face = AttributionSessionFakeFace()
        let session = makeV2Session(fixture: .stepper)
        let increment = try XCTUnwrap(session.observation(for: .chevronUp))
        let decrement = try XCTUnwrap(session.observation(for: .chevronDown))
        let first = bitmap()
        let second = bitmap()
        let glyphs: [UInt16] = [31, 0, 65_535, 31]
        let draw = V2Draw(face: face, glyphs: glyphs)
        try completeV2Raster(increment, draws: [draw, draw], bitmap: first)
        increment.accept(first, cacheHit: false)
        increment.accept(first, cacheHit: true)
        try completeV2Raster(decrement, draws: [draw], bitmap: second)
        decrement.accept(second, cacheHit: false)

        let report = try XCTUnwrap(session.finishV2(scene: scene(referencing: [first, second])))
        let run = try XCTUnwrap(report.glyphRuns.first)
        XCTAssertEqual(report.glyphRuns.count, 1)
        XCTAssertEqual(run.glyphIndices, glyphs)
        XCTAssertEqual(run.glyphCount, 4)
        XCTAssertEqual(run.count, 3)
        XCTAssertEqual(run.drawResult, 0)
        XCTAssertEqual(run.drawStatus, "succeeded")
        XCTAssertEqual(report.limits.copiedRuns, 3)
        XCTAssertEqual(report.limits.copiedGlyphs, 12)
        XCTAssertEqual(report.coverage.bitmapDrawGlyphRuns, "observed")
        XCTAssertEqual(report.coverage.faceFileStreams, "partial")
        XCTAssertEqual(report.status, "partial", "Injected unavailable file evidence does not qualify the report")
        for (role, multiplicity) in [(NativeBitmapFontRole.increment, 2), (.decrement, 1)] {
            for outcome in [NativeBitmapFontOutcome.drawProduced, .bitmapAccepted, .sceneReferenced] {
                let entry = try XCTUnwrap(matchingV2(report, role: role, outcome: outcome).first)
                XCTAssertEqual(entry.status, "observed")
                XCTAssertEqual(entry.runIDs, [run.id])
                XCTAssertEqual(entry.runCounts, [multiplicity])
                XCTAssertEqual(entry.count, 1)
            }
        }
        let cache = try XCTUnwrap(matchingV2(report, role: .increment, outcome: .bitmapCacheHitKnown).first)
        XCTAssertEqual(cache.runIDs, [run.id])
        XCTAssertEqual(cache.runCounts, [2])
    }

    func testV2FailedEmptyAndAbsentGlyphRunsRemainPartial() async throws {
        let cases: [(String, [UInt16]?, HRESULT, String)] = [
            ("failed", [0, 7], HRESULT(bitPattern: 0x8000_4005), "partial"),
            ("empty", [], 0, "partial"),
            ("absent", nil, 0, "not-observed"),
        ]
        for (name, glyphs, result, expectedStatus) in cases {
            let face = AttributionSessionFakeFace()
            let session = makeV2Session()
            let observation = try XCTUnwrap(session.observation(for: .folder))
            let draws = glyphs.map { [V2Draw(face: face, glyphs: $0, result: result)] } ?? []
            try completeV2Raster(observation, draws: draws, bitmap: nil)
            let report = try XCTUnwrap(session.finishV2(scene: GPUIScene()))
            let entry = try XCTUnwrap(matchingV2(report, outcome: .drawUnavailable).first)
            XCTAssertEqual(entry.status, expectedStatus, name)
            XCTAssertEqual(report.status, "partial", name)
            XCTAssertEqual(report.coverage.bitmapDrawGlyphRuns, "partial", name)
            if let glyphs {
                let run = try XCTUnwrap(report.glyphRuns.first)
                XCTAssertEqual(run.glyphIndices, glyphs, name)
                XCTAssertEqual(run.glyphCount, glyphs.count, name)
                XCTAssertEqual(run.drawResult, result, name)
                XCTAssertEqual(run.drawStatus, result < 0 ? "failed" : "succeeded", name)
                XCTAssertEqual(run.count, 1, name)
                XCTAssertEqual(entry.runIDs, [run.id], name)
                XCTAssertEqual(report.limits.copiedRuns, 1, name)
            } else {
                XCTAssertTrue(report.glyphRuns.isEmpty, name)
                XCTAssertTrue(entry.runIDs.isEmpty, name)
                XCTAssertEqual(report.limits.copiedRuns, 0, name)
            }
            XCTAssertTrue(matchingV2(report, outcome: .bitmapAccepted).isEmpty, name)
            XCTAssertTrue(matchingV2(report, outcome: .sceneReferenced).isEmpty, name)
        }
    }

    func testV2DistinctActualFacePointersDoNotDeduplicateOnEqualMetadata() async throws {
        let first = AttributionSessionFakeFace()
        let second = AttributionSessionFakeFace()
        var evidenceResolutions = 0
        let glyphEvidence = NativeBitmapGlyphEvidenceSession { _, _ in
            evidenceResolutions += 1
            return NativeBitmapFontFaceEvidenceV2()
        }
        let session = makeV2Session(glyphEvidence: glyphEvidence) { _ in
            NativeBitmapFontFaceMetadata(status: .unavailable)
        }
        let observation = try XCTUnwrap(session.observation(for: .folder))
        let surface = bitmap()
        try completeV2Raster(
            observation,
            draws: [V2Draw(face: first, glyphs: [9]), V2Draw(face: second, glyphs: [9])],
            bitmap: surface)
        observation.accept(surface, cacheHit: false)
        XCTAssertEqual(session.retainedFaceCountForTesting, 2)
        let report = try XCTUnwrap(session.finishV2(scene: scene(referencing: [surface])))

        XCTAssertEqual(evidenceResolutions, 2)
        XCTAssertEqual(report.attributionV1.faces.count, 1)
        XCTAssertEqual(report.faces.count, 2)
        XCTAssertEqual(Set(report.faces.map(\.id)).count, 2)
        XCTAssertEqual(report.faces[0].metadata, report.faces[1].metadata)
        XCTAssertEqual(report.glyphRuns.count, 2)
        XCTAssertEqual(Set(report.glyphRuns.map(\.faceID)).count, 2)
        XCTAssertTrue(report.glyphRuns.allSatisfy { $0.glyphIndices == [9] && $0.count == 1 })
        XCTAssertEqual(first.state.references, 1)
        XCTAssertEqual(second.state.references, 1)
    }

    func testV2BitmapReceiptsKeepDifferentGlyphRunsAndSceneReferencesSeparate() async throws {
        let face = AttributionSessionFakeFace()
        let session = makeV2Session()
        let folder = try XCTUnwrap(session.observation(for: .folder))
        let star = try XCTUnwrap(session.observation(for: .star))
        let shown = bitmap()
        let registeredOnly = bitmap()
        try completeV2Raster(folder, draws: [V2Draw(face: face, glyphs: [11])], bitmap: shown)
        folder.accept(shown, cacheHit: false)
        try completeV2Raster(star, draws: [V2Draw(face: face, glyphs: [22])], bitmap: registeredOnly)
        star.accept(registeredOnly, cacheHit: false)

        let report = try XCTUnwrap(
            session.finishV2(scene: scene(referencing: [shown], registeringOnly: [registeredOnly])))
        let shownRun = try XCTUnwrap(report.glyphRuns.first { $0.glyphIndices == [11] })
        let unusedRun = try XCTUnwrap(report.glyphRuns.first { $0.glyphIndices == [22] })
        XCTAssertNotEqual(shownRun.id, unusedRun.id)
        let shownReference = try XCTUnwrap(matchingV2(report, role: .folder, outcome: .sceneReferenced).first)
        XCTAssertEqual(shownReference.runIDs, [shownRun.id])
        XCTAssertEqual(shownReference.runCounts, [1])
        let unusedReference = try XCTUnwrap(matchingV2(report, role: .star, outcome: .notReferenced).first)
        XCTAssertEqual(unusedReference.runIDs, [unusedRun.id])
        XCTAssertEqual(unusedReference.runCounts, [1])
        XCTAssertTrue(matchingV2(report, role: .star, outcome: .sceneReferenced).isEmpty)
        XCTAssertEqual(report.coverage.visiblePixels, "not-observed")
    }

    func testV2GDIOverrideAndVectorCannotBorrowFailedDirectWriteGlyphs() async throws {
        let face = AttributionSessionFakeFace()
        let session = makeV2Session()
        let observation = try XCTUnwrap(session.observation(for: .folder))
        try completeV2Raster(
            observation, draws: [V2Draw(face: face, glyphs: [4], result: -1)], bitmap: nil)
        let gdi = bitmap()
        observation.recordGDIResult(bitmap: gdi)
        observation.accept(gdi, cacheHit: false)
        let overridden = bitmap()
        observation.recordTestingOverrideResult(bitmap: overridden)
        observation.accept(overridden, cacheHit: false)
        try XCTUnwrap(session.observation(for: .sparkle)).selectVector()

        let report = try XCTUnwrap(session.finishV2(scene: scene(referencing: [gdi, overridden])))
        XCTAssertEqual(report.glyphRuns.count, 1)
        XCTAssertEqual(report.glyphRuns.first?.drawStatus, "failed")
        for backend in [NativeBitmapFontBackend.gdi, .testingOverride] {
            let entry = try XCTUnwrap(matchingV2(report, backend: backend, outcome: .sceneReferenced).first)
            XCTAssertEqual(entry.status, "not-observed")
            XCTAssertTrue(entry.runIDs.isEmpty)
            XCTAssertTrue(entry.runCounts.isEmpty)
        }
        let vector = try XCTUnwrap(matchingV2(report, backend: .vector, outcome: .vectorSelected).first)
        XCTAssertEqual(vector.status, "not-observed")
        XCTAssertTrue(vector.runIDs.isEmpty)
        XCTAssertTrue(matchingV2(report, backend: .directWrite, outcome: .sceneReferenced).isEmpty)
        XCTAssertEqual(report.qualification, "unqualified")
    }

    func testV2MutatedAndIndependentEqualBitmapsHaveUnobservedGlyphReceipts() async throws {
        let face = AttributionSessionFakeFace()
        let session = makeV2Session()
        let observation = try XCTUnwrap(session.observation(for: .folder))
        let original = bitmap()
        try completeV2Raster(observation, draws: [V2Draw(face: face, glyphs: [14])], bitmap: original)
        observation.accept(original, cacheHit: false)
        let copy = original
        observation.accept(copy, cacheHit: true)
        var mutated = original
        mutated.pixels = Data([9, 2, 3, 255])
        let independent = BitmapSurface(
            width: original.width, height: original.height, bytesPerRow: original.bytesPerRow,
            pixels: original.pixels)
        XCTAssertEqual(independent, original)
        XCTAssertNotEqual(independent.contentKey, original.contentKey)
        XCTAssertNotEqual(mutated.contentKey, original.contentKey)
        observation.accept(mutated, cacheHit: true)
        observation.accept(independent, cacheHit: true)

        let report = try XCTUnwrap(session.finishV2(scene: scene(referencing: [copy, mutated, independent])))
        let known = try XCTUnwrap(matchingV2(report, outcome: .bitmapCacheHitKnown).first)
        XCTAssertEqual(known.status, "observed")
        XCTAssertEqual(known.runIDs, report.glyphRuns.map(\.id))
        let unknown = try XCTUnwrap(matchingV2(report, outcome: .bitmapCacheHitUnobserved).first)
        XCTAssertEqual(unknown.count, 2)
        XCTAssertEqual(unknown.status, "not-observed")
        XCTAssertTrue(unknown.runIDs.isEmpty)
        let references = try XCTUnwrap(matchingV2(report, backend: .unknown, outcome: .sceneReferenced).first)
        XCTAssertEqual(references.count, 2)
        XCTAssertTrue(references.runIDs.isEmpty)
        XCTAssertTrue(references.runCounts.isEmpty)
    }

    func testV2ConflictingGlyphsOrMultiplicityDowngradeFutureReceiptAssociations() async throws {
        for differentGlyphs in [true, false] {
            let face = AttributionSessionFakeFace()
            let session = makeV2Session()
            let folder = try XCTUnwrap(session.observation(for: .folder))
            let star = try XCTUnwrap(session.observation(for: .star))
            let shared = bitmap()
            let firstDraw = V2Draw(face: face, glyphs: [7])
            try completeV2Raster(folder, draws: [firstDraw], bitmap: shared)
            folder.accept(shared, cacheHit: false)
            let conflictingDraws =
                differentGlyphs
                ? [V2Draw(face: face, glyphs: [8])] : [firstDraw, firstDraw]
            try completeV2Raster(star, draws: conflictingDraws, bitmap: shared)
            star.accept(shared, cacheHit: false)
            folder.accept(shared, cacheHit: true)

            let report = try XCTUnwrap(session.finishV2(scene: scene(referencing: [shared])))
            let historical = try XCTUnwrap(
                matchingV2(report, role: .folder, outcome: .bitmapAccepted, status: "observed").first)
            XCTAssertEqual(historical.runCounts, [1])
            XCTAssertFalse(historical.runIDs.isEmpty)
            let future = try XCTUnwrap(matchingV2(report, role: .folder, outcome: .bitmapCacheHitKnown).first)
            XCTAssertEqual(future.backend, NativeBitmapFontBackend.unknown.rawValue)
            XCTAssertEqual(future.status, "not-observed")
            XCTAssertTrue(future.runIDs.isEmpty)
            XCTAssertTrue(future.runCounts.isEmpty)
            let references = matchingV2(report, outcome: .sceneReferenced)
            XCTAssertEqual(Set(references.map(\.role)), Set(["folder", "star"]))
            XCTAssertTrue(
                references.allSatisfy {
                    $0.backend == NativeBitmapFontBackend.unknown.rawValue
                        && $0.status == "not-observed" && $0.runIDs.isEmpty && $0.runCounts.isEmpty
                })
            XCTAssertEqual(report.glyphRuns.count, differentGlyphs ? 2 : 1)
            XCTAssertEqual(report.glyphRuns.map(\.count).reduce(0, +), differentGlyphs ? 2 : 3)
        }
    }

    func testV2SharesTheSixtyFourFaceBoundWithProbeMetadata() async throws {
        let probeFaces = (0..<64).map { _ in AttributionSessionFakeFace() }
        let overflow = AttributionSessionFakeFace()
        var metadataResolutions = 0
        var evidenceResolutions = 0
        let glyphEvidence = NativeBitmapGlyphEvidenceSession { _, _ in
            evidenceResolutions += 1
            return NativeBitmapFontFaceEvidenceV2()
        }
        let session = makeV2Session(glyphEvidence: glyphEvidence) { _ in
            metadataResolutions += 1
            return attributionSessionMetadata()
        }
        let display = try XCTUnwrap(session.observation(for: .folder))
        let probe = display.withPurpose(.candidateProbe)
        for offset in stride(from: 0, to: probeFaces.count, by: 8) {
            let draws = probeFaces[offset..<(offset + 8)].map { V2Draw(face: $0, glyphs: [1]) }
            try completeV2Raster(probe, draws: draws, bitmap: bitmap())
        }
        XCTAssertEqual(session.retainedFaceCountForTesting, 64)
        XCTAssertEqual(metadataResolutions, 64)
        XCTAssertEqual(evidenceResolutions, 0)
        XCTAssertEqual(glyphEvidence.captureBudget.copiedRuns, 0)

        let surface = bitmap()
        try completeV2Raster(display, draws: [V2Draw(face: overflow, glyphs: [2])], bitmap: surface)
        display.accept(surface, cacheHit: false)
        XCTAssertEqual(metadataResolutions, 64)
        XCTAssertEqual(evidenceResolutions, 0)
        XCTAssertEqual(overflow.state.addRefCalls, 1)
        XCTAssertEqual(overflow.state.releaseCalls, 1)
        XCTAssertEqual(overflow.state.references, 1)
        let report = try XCTUnwrap(session.finishV2(scene: scene(referencing: [surface])))
        XCTAssertEqual(report.limits.maxFaces, 64)
        XCTAssertEqual(report.attributionV1.faces.count, 1)
        XCTAssertTrue(report.faces.isEmpty)
        XCTAssertTrue(report.glyphRuns.isEmpty)
        XCTAssertEqual(report.limits.copiedRuns, 1, "Copied callback work still consumes the session budget")
        XCTAssertEqual(report.limits.copiedGlyphs, 1)
        XCTAssertGreaterThan(report.limits.dropped, 0)
        XCTAssertTrue(matchingV2(report, outcome: .sceneReferenced).allSatisfy { $0.runIDs.isEmpty })
        XCTAssertTrue(probeFaces.allSatisfy { $0.state.references == 1 })
    }

    func testV2RunCopyBudgetIsGlobalAcrossRasterAttempts() async throws {
        let face = AttributionSessionFakeFace()
        let session = makeV2Session()
        let observation = try XCTUnwrap(session.observation(for: .folder))
        let draw = V2Draw(face: face, glyphs: [17])
        for _ in 0..<16 {
            try completeV2Raster(observation, draws: Array(repeating: draw, count: 16), bitmap: bitmap())
        }
        try completeV2Raster(observation, draws: [draw], bitmap: bitmap())
        let report = try XCTUnwrap(session.finishV2(scene: GPUIScene()))

        XCTAssertEqual(report.limits.maxRunsPerRaster, 16)
        XCTAssertEqual(report.limits.maxRuns, 256)
        XCTAssertEqual(report.limits.copiedRuns, 256)
        XCTAssertEqual(report.limits.copiedGlyphs, 256)
        XCTAssertEqual(report.glyphRuns.map(\.count).reduce(0, +), 256)
        XCTAssertGreaterThan(report.limits.dropped, 0)
        XCTAssertEqual(report.coverage.bitmapDrawGlyphRuns, "partial")
        XCTAssertFalse(matchingV2(report, outcome: .drawProduced, status: "not-observed").isEmpty)
        XCTAssertEqual(report.limits.requestedStreamBytes, 0)
        XCTAssertEqual(report.limits.readStreamBytes, 0)
    }

    func testV2GlyphCopyBudgetIsGlobalAndSeparateFromRunCount() async throws {
        let face = AttributionSessionFakeFace()
        let session = makeV2Session()
        let observation = try XCTUnwrap(session.observation(for: .folder))
        let draw = V2Draw(face: face, glyphs: Array(repeating: 9, count: 128))
        for _ in 0..<2 {
            try completeV2Raster(observation, draws: Array(repeating: draw, count: 16), bitmap: bitmap())
        }
        try completeV2Raster(observation, draws: [V2Draw(face: face, glyphs: [10])], bitmap: bitmap())
        let report = try XCTUnwrap(session.finishV2(scene: GPUIScene()))

        XCTAssertEqual(report.limits.maxGlyphsPerRun, 128)
        XCTAssertEqual(report.limits.maxGlyphs, 4_096)
        XCTAssertEqual(report.limits.copiedGlyphs, 4_096)
        XCTAssertEqual(report.limits.copiedRuns, 32)
        XCTAssertLessThan(report.limits.copiedRuns, report.limits.maxRuns)
        XCTAssertEqual(report.glyphRuns.map(\.count).reduce(0, +), 32)
        XCTAssertEqual(report.glyphRuns.first?.glyphIndices, draw.glyphs)
        XCTAssertGreaterThan(report.limits.dropped, 0)
        XCTAssertFalse(matchingV2(report, outcome: .drawProduced, status: "not-observed").isEmpty)
    }

    func testV2FinishReleasesHandlesClosesLateCopyingAndIsStableWhenRepeated() async throws {
        let face = AttributionSessionFakeFace()
        let glyphEvidence = NativeBitmapGlyphEvidenceSession { _, _ in NativeBitmapFontFaceEvidenceV2() }
        let session = makeV2Session(glyphEvidence: glyphEvidence)
        let observation = try XCTUnwrap(session.observation(for: .folder))
        let surface = bitmap()
        try completeV2Raster(observation, draws: [V2Draw(face: face, glyphs: [3, 0, 4])], bitmap: surface)
        observation.accept(surface, cacheHit: false)
        let lateCapture = try XCTUnwrap(observation.beginDirectWriteCapture())
        XCTAssertEqual(face.state.references, 2)
        let first = try XCTUnwrap(session.finishV2(scene: scene(referencing: [surface])))
        XCTAssertEqual(face.state.references, 1)
        XCTAssertEqual(face.state.addRefCalls, 1)
        XCTAssertEqual(face.state.releaseCalls, 1)
        XCTAssertEqual(session.retainedFaceCountForTesting, 0)
        XCTAssertEqual(session.receiptCountForTesting, 0)
        XCTAssertFalse(glyphEvidence.captureBudget.isOpen)

        recordV2Draw(V2Draw(face: face, glyphs: [99]), into: lateCapture)
        observation.completeDirectWriteCapture(lateCapture, bitmap: bitmap())
        observation.accept(bitmap(), cacheHit: true)
        XCTAssertEqual(lateCapture.drawCount, 0)
        XCTAssertTrue(lateCapture.glyphRuns.isEmpty)
        XCTAssertEqual(glyphEvidence.captureBudget.copiedRuns, 1)
        XCTAssertEqual(glyphEvidence.captureBudget.copiedGlyphs, 3)
        XCTAssertEqual(face.state.references, 1)
        XCTAssertEqual(face.state.addRefCalls, 1)
        XCTAssertNil(observation.beginDirectWriteCapture())
        session.close()
        session.close()
        let repeated = try XCTUnwrap(session.finishV2(scene: GPUIScene()))
        XCTAssertEqual(try encodedV2(first), try encodedV2(repeated))
        XCTAssertEqual(try encoded(first.attributionV1), try encoded(session.finish(scene: GPUIScene())))
    }

    func testV2EvidenceResolverClosingOwnerCannotResurrectEitherReport() async throws {
        weak var weakSession: NativeBitmapFontAttributionSession?
        let glyphEvidence = NativeBitmapGlyphEvidenceSession { _, _ in
            weakSession?.close()
            return NativeBitmapFontFaceEvidenceV2()
        }
        let session = makeV2Session(glyphEvidence: glyphEvidence)
        weakSession = session
        let observation = try XCTUnwrap(session.observation(for: .folder))
        let face = AttributionSessionFakeFace()
        try completeV2Raster(observation, draws: [V2Draw(face: face, glyphs: [5])], bitmap: bitmap())

        XCTAssertEqual(session.retainedFaceCountForTesting, 0)
        XCTAssertEqual(session.receiptCountForTesting, 0)
        XCTAssertEqual(face.state.references, 1)
        XCTAssertFalse(glyphEvidence.captureBudget.isOpen)
        let report = try XCTUnwrap(session.finishV2(scene: GPUIScene()))
        XCTAssertTrue(report.attributionV1.faces.isEmpty)
        XCTAssertTrue(report.attributionV1.observations.isEmpty)
        XCTAssertTrue(report.faces.isEmpty)
        XCTAssertTrue(report.glyphRuns.isEmpty)
        XCTAssertTrue(report.observations.isEmpty)
        XCTAssertEqual(report.status, "partial")
    }

    func testV2TwoHopEquivalentFaceContextsSortDeterministicallyWithoutPrivateFields() async throws {
        let faceA = AttributionSessionFakeFace()
        let faceB = AttributionSessionFakeFace()
        let faceC = AttributionSessionFakeFace()
        let faceD = AttributionSessionFakeFace()
        let faceX = AttributionSessionFakeFace()
        let faceY = AttributionSessionFakeFace()
        let faces = [faceA, faceB, faceC, faceD, faceX, faceY]
        // A and B need their companions' contexts to become distinguishable.
        // All six faces intentionally have identical metadata and evidence.
        let attempts = [
            [V2Draw(face: faceA, glyphs: [1]), V2Draw(face: faceC, glyphs: [2])],
            [V2Draw(face: faceB, glyphs: [1]), V2Draw(face: faceD, glyphs: [2])],
            [V2Draw(face: faceC, glyphs: [2]), V2Draw(face: faceX, glyphs: [3])],
            [V2Draw(face: faceD, glyphs: [2]), V2Draw(face: faceY, glyphs: [4])],
        ]
        var reports: [NativeBitmapFontAttributionReportV2] = []
        for reversed in [false, true] {
            let session = makeV2Session()
            let observation = try XCTUnwrap(session.observation(for: .folder))
            let orderedAttempts = reversed ? attempts.reversed().map { Array($0.reversed()) } : attempts
            var surfaces: [BitmapSurface] = []
            for draws in orderedAttempts {
                let surface = bitmap()
                try completeV2Raster(observation, draws: draws, bitmap: surface)
                observation.accept(surface, cacheHit: false)
                surfaces.append(surface)
            }
            reports.append(try XCTUnwrap(session.finishV2(scene: scene(referencing: surfaces))))
        }

        let data = try encodedV2(reports[0])
        XCTAssertEqual(data, try encodedV2(reports[1]))
        XCTAssertEqual(reports[0].faces.count, 6)
        XCTAssertEqual(reports[0].faces.filter { $0.metadata.familyName == "Fixture Face" }.count, 6)
        XCTAssertEqual(reports[0].glyphRuns.count, 6)
        XCTAssertEqual(Set(reports[0].glyphRuns.map(\.faceID)).count, 6)
        XCTAssertEqual(reports[0].glyphRuns.filter { $0.glyphIndices == [1] }.map(\.count), [1, 1])
        XCTAssertEqual(reports[0].glyphRuns.filter { $0.glyphIndices == [2] }.map(\.count), [2, 2])
        XCTAssertEqual(reports[0].limits.copiedRuns, 8)
        XCTAssertEqual(reports[0].limits.copiedGlyphs, 8)
        XCTAssertEqual(reports[0].attributionV1.faces.count, 1)
        XCTAssertTrue(faces.allSatisfy { $0.state.references == 1 })
        let allowed: Set<String> = [
            "schemaVersion", "kind", "scope", "fixtureID", "status", "qualification", "coverage",
            "bitmapIcons", "atlasGlyphs", "textLayouts", "sceneReferences", "faces", "id", "metadata",
            "familyName", "faceName", "namesStatus", "faceIndex", "simulations", "files", "filesStatus",
            "basename", "axes", "axesStatus", "tag", "value", "observations", "role", "purpose", "backend",
            "outcome", "faceIDs", "count", "limits", "maxFaces", "maxReceipts", "maxObservations", "dropped",
            "attributionV1", "bitmapDrawGlyphRuns", "faceFileStreams", "visiblePixels", "loadedBytesDigest",
            "evidence", "faceType", "hasVariations", "glyphRuns", "faceID", "glyphCount", "glyphIndices",
            "drawResult", "drawStatus", "runIDs", "runCounts", "maxGlyphsPerRun", "maxRunsPerRaster",
            "maxRuns", "maxGlyphs", "maxFilesPerFace", "maxAxesPerFace", "maxStreamBytesPerFile",
            "maxStreamBytesSession", "streamFragmentBytes", "copiedRuns", "copiedGlyphs",
            "requestedStreamBytes", "readStreamBytes", "index", "reference", "operation", "codeDomain",
            "code", "streamLength", "requestedBytes", "readBytes", "sha256", "observationKind",
        ]
        assertJSONKeys(try JSONSerialization.jsonObject(with: data), allowed: allowed)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        for forbidden in [
            "text", "textHash", "source", "sourceText", "secureLength", "contentKey", "contentToken",
            "cacheKey", "timestamp", "eventOrder", "globalEventOrder", "callbackOrder", "rawPointer",
            "referenceKey", "absolutePath", "glyphAdvances", "advances", "glyphOffsets", "offsets",
            "baselineX", "baselineY", "fontEmSize", "bidiLevel", "stringLength",
        ] {
            XCTAssertFalse(text.contains("\"\(forbidden)\""), forbidden)
        }
        for face in faces {
            XCTAssertFalse(text.contains(String(describing: face.rawPointer)))
            XCTAssertFalse(text.contains(String(UInt(bitPattern: face.rawPointer))))
        }
        XCTAssertEqual(reports[0].qualification, "unqualified")
        XCTAssertEqual(reports[0].coverage.visiblePixels, "not-observed")
        XCTAssertEqual(reports[0].coverage.loadedBytesDigest, "not-observed")
    }

    func testV2CaptureReplayAndWrongRoleCannotSupplyAnotherReceipt() async throws {
        for replay in [true, false] {
            let face = AttributionSessionFakeFace()
            let session = makeV2Session()
            let folder = try XCTUnwrap(session.observation(for: .folder))
            let star = try XCTUnwrap(session.observation(for: .star))
            let capture = try XCTUnwrap(folder.beginDirectWriteCapture())
            recordV2Draw(V2Draw(face: face, glyphs: [11]), into: capture)
            let actual = bitmap()
            let rejected = bitmap()
            if replay {
                folder.completeDirectWriteCapture(capture, bitmap: actual)
                folder.accept(actual, cacheHit: false)
                folder.completeDirectWriteCapture(capture, bitmap: rejected)
                folder.accept(rejected, cacheHit: false)
            } else {
                star.completeDirectWriteCapture(capture, bitmap: rejected)
                star.accept(rejected, cacheHit: false)
                folder.completeDirectWriteCapture(capture, bitmap: actual)
                folder.accept(actual, cacheHit: false)
            }
            let report = try XCTUnwrap(session.finishV2(scene: scene(referencing: [actual, rejected])))
            XCTAssertEqual(report.limits.copiedRuns, 1)
            XCTAssertEqual(report.limits.copiedGlyphs, 1)
            XCTAssertEqual(report.glyphRuns.count, 1)
            XCTAssertEqual(report.glyphRuns.first?.count, 1)
            XCTAssertGreaterThan(report.limits.dropped, 0)
            let invalidRole: NativeBitmapFontRole = replay ? .folder : .star
            let invalid = try XCTUnwrap(
                matchingV2(report, role: invalidRole, outcome: .sceneReferenced, status: "not-observed").first)
            XCTAssertTrue(invalid.runIDs.isEmpty)
            XCTAssertTrue(invalid.runCounts.isEmpty)
            let valid = try XCTUnwrap(
                matchingV2(report, role: .folder, outcome: .sceneReferenced, status: "observed").first)
            XCTAssertEqual(valid.runIDs, report.glyphRuns.map(\.id))
            XCTAssertEqual(valid.runCounts, [1])
        }
    }

    func testV2ForeignSessionCannotConsumeTheOwningSessionsCapture() async throws {
        let face = AttributionSessionFakeFace()
        let owner = makeV2Session()
        var foreignEvidenceResolutions = 0
        let foreignEvidence = NativeBitmapGlyphEvidenceSession { _, _ in
            foreignEvidenceResolutions += 1
            return NativeBitmapFontFaceEvidenceV2()
        }
        let foreign = makeV2Session(glyphEvidence: foreignEvidence)
        let ownerObservation = try XCTUnwrap(owner.observation(for: .folder))
        let foreignObservation = try XCTUnwrap(foreign.observation(for: .folder))
        let capture = try XCTUnwrap(ownerObservation.beginDirectWriteCapture())
        recordV2Draw(V2Draw(face: face, glyphs: [4, 0]), into: capture)
        let rejected = bitmap()
        foreignObservation.completeDirectWriteCapture(capture, bitmap: rejected)
        foreignObservation.accept(rejected, cacheHit: false)
        let foreignReport = try XCTUnwrap(foreign.finishV2(scene: scene(referencing: [rejected])))

        XCTAssertEqual(foreignEvidenceResolutions, 0)
        XCTAssertEqual(foreignReport.limits.copiedRuns, 0)
        XCTAssertEqual(foreignReport.limits.copiedGlyphs, 0)
        XCTAssertTrue(foreignReport.faces.isEmpty)
        XCTAssertTrue(foreignReport.glyphRuns.isEmpty)
        XCTAssertGreaterThan(foreignReport.limits.dropped, 0)
        let foreignReference = try XCTUnwrap(matchingV2(foreignReport, outcome: .sceneReferenced).first)
        XCTAssertEqual(foreignReference.status, "not-observed")
        XCTAssertTrue(foreignReference.runIDs.isEmpty)

        let actual = bitmap()
        ownerObservation.completeDirectWriteCapture(capture, bitmap: actual)
        ownerObservation.accept(actual, cacheHit: false)
        let ownerReport = try XCTUnwrap(owner.finishV2(scene: scene(referencing: [actual])))
        XCTAssertEqual(ownerReport.limits.copiedRuns, 1)
        XCTAssertEqual(ownerReport.limits.copiedGlyphs, 2)
        XCTAssertEqual(ownerReport.glyphRuns.map(\.glyphIndices), [[4, 0]])
        XCTAssertEqual(matchingV2(ownerReport, outcome: .sceneReferenced).first?.status, "observed")
    }

    func testV2PartialSceneCannotExportAnUnprovenGlyphAssociation() async throws {
        let roles: [NativeBitmapFontRole] = [.increment, .decrement]
        for capTraversal in [true, false] {
            var bounds = NativeBitmapFontAttributionSession.Bounds()
            if capTraversal { bounds.scenePrimitives = 0 }
            let session = makeV2Session(fixture: .stepper, bounds: bounds)
            let observations = [
                try XCTUnwrap(session.observation(for: .chevronUp)),
                try XCTUnwrap(session.observation(for: .chevronDown)),
            ]
            let face = AttributionSessionFakeFace()
            let surfaces = [bitmap(), bitmap()]
            for (index, observation) in observations.enumerated() {
                try completeV2Raster(
                    observation, draws: [V2Draw(face: face, glyphs: [UInt16(12 + index)])], bitmap: surfaces[index])
                observation.accept(surfaces[index], cacheHit: false)
            }
            var preparedScene = GPUIScene()
            if capTraversal {
                preparedScene = scene(referencing: surfaces)
            } else {
                // An unresolved image makes only scene coverage partial in V1.
                preparedScene.addImage(image(textureID: 77))
                preparedScene.finish()
            }
            let report = try XCTUnwrap(session.finishV2(scene: preparedScene))

            XCTAssertEqual(report.glyphRuns.count, 2)
            XCTAssertEqual(report.limits.copiedRuns, 2)
            XCTAssertEqual(report.limits.copiedGlyphs, 2)
            for (index, role) in roles.enumerated() {
                let run = try XCTUnwrap(report.glyphRuns.first { $0.glyphIndices == [UInt16(12 + index)] })
                let accepted = try XCTUnwrap(matchingV2(report, role: role, outcome: .bitmapAccepted).first)
                XCTAssertEqual(accepted.status, "observed")
                XCTAssertEqual(accepted.runIDs, [run.id])
                XCTAssertEqual(accepted.runCounts, [1])
                let unobserved = try XCTUnwrap(
                    matchingV2(report, role: role, outcome: .sceneAssociationUnobserved).first)
                XCTAssertEqual(unobserved.status, "not-observed")
                XCTAssertTrue(unobserved.runIDs.isEmpty)
                XCTAssertTrue(unobserved.runCounts.isEmpty)
            }
            XCTAssertTrue(matchingV2(report, outcome: .sceneReferenced).isEmpty)
            XCTAssertTrue(matchingV2(report, outcome: .notReferenced).isEmpty)
            XCTAssertEqual(report.attributionV1.coverage.bitmapIcons, capTraversal ? "partial" : "observed")
            XCTAssertEqual(report.coverage.bitmapDrawGlyphRuns, "partial")
            XCTAssertEqual(report.coverage.sceneReferences, "partial")
            XCTAssertEqual(report.status, "partial")
        }
    }

    func testV2AbandonedCaptureKeepsCopyAccountingButCannotBecomeObserved() async throws {
        let face = AttributionSessionFakeFace()
        var metadataResolutions = 0
        var evidenceResolutions = 0
        let glyphEvidence = NativeBitmapGlyphEvidenceSession { _, _ in
            evidenceResolutions += 1
            return NativeBitmapFontFaceEvidenceV2()
        }
        let session = makeV2Session(glyphEvidence: glyphEvidence) { _ in
            metadataResolutions += 1
            return attributionSessionMetadata()
        }
        let observation = try XCTUnwrap(session.observation(for: .folder))
        var abandoned = observation.beginDirectWriteCapture()
        if let capture = abandoned {
            recordV2Draw(V2Draw(face: face, glyphs: [2, 0, 3]), into: capture)
        } else {
            XCTFail("Expected one owned capture")
        }
        let report = try XCTUnwrap(session.finishV2(scene: GPUIScene()))
        XCTAssertEqual(metadataResolutions, 0)
        XCTAssertEqual(evidenceResolutions, 0)
        XCTAssertEqual(report.limits.copiedRuns, 1)
        XCTAssertEqual(report.limits.copiedGlyphs, 3)
        XCTAssertGreaterThan(report.limits.dropped, 0)
        XCTAssertTrue(report.faces.isEmpty)
        XCTAssertTrue(report.glyphRuns.isEmpty)
        XCTAssertEqual(report.coverage.bitmapDrawGlyphRuns, "partial")
        XCTAssertEqual(report.status, "partial")
        XCTAssertFalse(glyphEvidence.captureBudget.isOpen)
        withExtendedLifetime(abandoned) {
            XCTAssertEqual(face.state.references, 2, "The abandoned buffer still owns its temporary reference")
        }
        abandoned = nil
        XCTAssertEqual(face.state.references, 1)
        XCTAssertEqual(face.state.addRefCalls, 1)
        XCTAssertEqual(face.state.releaseCalls, 1)
    }

    private struct V2Draw {
        let face: AttributionSessionFakeFace
        let glyphs: [UInt16]
        let result: HRESULT

        init(face: AttributionSessionFakeFace, glyphs: [UInt16], result: HRESULT = 0) {
            self.face = face
            self.glyphs = glyphs
            self.result = result
        }
    }

    private func makeV2Session(
        fixture: NativeBitmapFontFixture = .symbolPalette,
        bounds: NativeBitmapFontAttributionSession.Bounds = .init(),
        glyphEvidence: NativeBitmapGlyphEvidenceSession? = nil,
        resolveMetadata: @escaping @MainActor (NativeFontFaceHandle) -> NativeBitmapFontFaceMetadata = { _ in
            attributionSessionMetadata()
        }
    ) -> NativeBitmapFontAttributionSession {
        let evidence =
            glyphEvidence
            ?? NativeBitmapGlyphEvidenceSession { _, _ in
                NativeBitmapFontFaceEvidenceV2()
            }
        return NativeBitmapFontAttributionSession(
            fixture: fixture, bounds: bounds, resolveMetadata: resolveMetadata, glyphEvidence: evidence)
    }

    private func completeV2Raster(
        _ observation: NativeBitmapFontObservation, draws: [V2Draw], bitmap: BitmapSurface?
    ) throws {
        let capture = try XCTUnwrap(observation.beginDirectWriteCapture())
        for draw in draws {
            recordV2Draw(draw, into: capture)
        }
        observation.completeDirectWriteCapture(capture, bitmap: bitmap)
    }

    private func recordV2Draw(_ draw: V2Draw, into capture: NativeBitmapFontDrawCapture) {
        // Match the renderer's version/purpose branch. No font or raster API is
        // called: only the fake face and stack-owned glyph array reach capture.
        guard capture.capturesGlyphs else {
            capture.recordDraw(fontFace: draw.face.rawPointer, result: draw.result)
            return
        }
        draw.glyphs.withUnsafeBufferPointer { indices in
            var run = DWRITE_GLYPH_RUN(
                fontFace: draw.face.rawPointer, fontEmSize: 12, glyphCount: UInt32(indices.count),
                glyphIndices: indices.baseAddress, glyphAdvances: nil, glyphOffsets: nil,
                isSideways: WindowsBool(false), bidiLevel: 0)
            withUnsafeMutablePointer(to: &run) { pointer in
                capture.recordGlyphRun(UnsafeMutableRawPointer(pointer), result: draw.result)
            }
        }
    }

    private func matchingV2(
        _ report: NativeBitmapFontAttributionReportV2, role: NativeBitmapFontRole? = nil,
        backend: NativeBitmapFontBackend? = nil, outcome: NativeBitmapFontOutcome? = nil,
        status: String? = nil
    ) -> [NativeBitmapFontAttributionReportV2.Observation] {
        report.observations.filter { entry in
            (role == nil || entry.role == role?.rawValue)
                && (backend == nil || entry.backend == backend?.rawValue)
                && (outcome == nil || entry.outcome == outcome?.rawValue)
                && (status == nil || entry.status == status)
        }
    }

    private func encodedV2(_ report: NativeBitmapFontAttributionReportV2) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(report)
    }
}
