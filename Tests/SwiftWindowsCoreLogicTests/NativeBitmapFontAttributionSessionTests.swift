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
