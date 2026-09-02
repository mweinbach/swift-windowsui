import Foundation
@preconcurrency import XCTest

@testable import SwiftWindowsDemo
@testable import WinSwiftUI

@MainActor
final class DemoMediaBrowserModelTests: XCTestCase {
    func testConstructionHasStableEncodedSamplesAndStartsNoRead() async throws {
        let harness = DemoMediaBrowserHarness()
        defer { harness.close() }
        let model = harness.model
        XCTAssertEqual(DemoMediaBrowserModel.maximumRecordCount, 64)
        XCTAssertEqual(DemoMediaBrowserModel.pageSize, 4)
        XCTAssertEqual(DemoMediaBrowserModel.thumbnailPixelDimension, 256)
        XCTAssertEqual(DemoMediaBrowserModel.previewPixelDimension, 1024)
        XCTAssertEqual(model.records, DemoMediaBrowserRecord.samples)
        XCTAssertEqual(
            model.records.map(\.id), ["sample:corners", "sample:tiles", "sample:broken", "sample:unsupported"])
        XCTAssertEqual(
            model.records.map(\.name),
            ["Corner study.png", "Tile study.png", "Truncated image.png", "Unsupported format.gif"])
        XCTAssertEqual(model.selectedID, "sample:corners")
        XCTAssertEqual(model.visibleRecords, model.records)
        XCTAssertEqual(model.snapshot.thumbnails.count, 4)
        XCTAssertEqual(model.preview.phase, .idle)
        XCTAssertFalse(model.isActive)
        XCTAssertEqual(model.activeReadCount, 0)
        XCTAssertTrue(harness.gate.snapshot.starts.isEmpty)
        let encodedCounts = model.records.compactMap { record -> Int? in
            if case .data(let bytes) = record.source { return bytes.count }
            return nil
        }
        XCTAssertEqual(encodedCounts, [184, 101, 3, 43])
        let stats = await harness.service.statistics
        XCTAssertEqual(stats.activeWorkerCount, 0)
        XCTAssertEqual(stats.cachedImageCount, 0)
    }

    func testStagedVisibilityDoesNotReadBeforeTheOwnedLifetimeEnters() async throws {
        let harness = DemoMediaBrowserHarness()
        defer { harness.close() }
        let model = harness.model
        model.appear(mountID: harness.mountID)
        model.setBrowserVisible(true, mountID: harness.mountID)
        model.setPreviewVisible(true, mountID: harness.mountID)
        model.setThumbnailVisible(
            id: "sample:tiles", pageScope: model.pageScope, visible: true, mountID: harness.mountID)
        XCTAssertEqual(model.activeReadCount, 0)
        XCTAssertTrue(model.pendingThumbnailIDs.isEmpty)
        XCTAssertNil(model.pendingPreviewID)
        XCTAssertTrue(harness.gate.snapshot.starts.isEmpty)

        harness.mount(preview: true, thumbnails: ["sample:tiles"])
        try await harness.starts(2)
        XCTAssertEqual(model.activeReadCount, 2)
        XCTAssertEqual(model.pendingThumbnailIDs, ["sample:tiles"])
        XCTAssertEqual(model.pendingPreviewID, "sample:corners")
        XCTAssertFalse(harness.gate.snapshot.starts.contains { $0.wasCancelledAtEntry })
    }

    func testLiveLifetimeWithoutVisibleImageWellsDoesNotDecodeOffscreenRecords() async throws {
        let harness = DemoMediaBrowserHarness()
        defer { harness.close() }
        harness.mount()
        try await harness.waitFor { $0.isActive }
        XCTAssertEqual(harness.model.activeReadCount, 0)
        XCTAssertTrue(harness.gate.snapshot.starts.isEmpty)
        harness.model.setThumbnailVisible(
            id: "not-a-record", pageScope: harness.model.pageScope, visible: true, mountID: harness.mountID)
        harness.model.setThumbnailVisible(
            id: "sample:tiles", pageScope: UUID(), visible: true, mountID: harness.mountID)
        XCTAssertTrue(harness.model.requestedVisibleIDs.isEmpty)

        harness.model.setThumbnailVisible(
            id: "sample:tiles", pageScope: harness.model.pageScope, visible: true, mountID: harness.mountID)
        try await harness.starts(1)
        XCTAssertEqual(harness.gate.snapshot.starts.map(\.source), [harness.model.records[1].source])
        XCTAssertEqual(harness.model.preview.phase, .idle)
        XCTAssertEqual(harness.model.thumbnail(for: "sample:corners").phase, .idle)
        try await harness.finishCurrent([0], data: png([0, 255, 0, 255]))
        XCTAssertEqual(Array(try ready(harness.model.thumbnail(for: "sample:tiles")).pixelData), [0, 255, 0, 255])
        XCTAssertEqual(harness.model.activeReadCount, 0)
    }

    func testTwoLanesHoldPhysicalSlotsAndCoalesceLatestIntentWithoutAServiceQueue() async throws {
        let harness = DemoMediaBrowserHarness()
        defer { harness.close() }
        let model = harness.model
        harness.mount(preview: true, thumbnails: model.records.map(\.id))
        try await harness.starts(2)
        XCTAssertEqual(model.pendingThumbnailIDs.count, 4)
        XCTAssertEqual(model.activeReadCount, 2)
        var stats = await harness.service.statistics
        XCTAssertEqual(stats.activeWorkerCount, 2)

        for id in model.records.map(\.id) { XCTAssertTrue(model.cancel(id: id)) }
        XCTAssertTrue(model.pendingThumbnailIDs.isEmpty)
        XCTAssertNil(model.pendingPreviewID)
        XCTAssertEqual(model.activeReadCount, 2, "Cancelled service calls still own both physical slots.")
        XCTAssertTrue(model.select(id: "sample:tiles"))
        for _ in 0..<40 { XCTAssertTrue(model.retry(id: "sample:tiles")) }
        XCTAssertEqual(model.pendingThumbnailIDs, ["sample:tiles"])
        XCTAssertEqual(model.pendingPreviewID, "sample:tiles")
        XCTAssertTrue(model.isPreviewWaiting)
        XCTAssertEqual(harness.gate.snapshot.starts.count, 2)
        stats = await harness.service.statistics
        XCTAssertEqual(stats.activeWorkerCount, 2)
        XCTAssertEqual(stats.cachedImageCount, 0)

        try await harness.finishCurrent([0, 1], data: png([255, 0, 0, 255]))
        try await harness.starts(4)
        XCTAssertEqual(
            Array(harness.gate.snapshot.starts.suffix(2)).map(\.source),
            Array(repeating: model.records[1].source, count: 2))
        XCTAssertEqual(model.activeReadCount, 2)
        XCTAssertEqual(model.preview.phase, .loading)
        try await harness.finishCurrent([2, 3], data: png([0, 0, 255, 255]))
        XCTAssertEqual(Array(try ready(model.preview).pixelData), [255, 0, 0, 255])
        XCTAssertEqual(Array(try ready(model.thumbnail(for: "sample:tiles")).pixelData), [255, 0, 0, 255])
        XCTAssertEqual(model.thumbnail(for: "sample:corners").phase, .cancelled)
        XCTAssertEqual(harness.gate.snapshot.maximumConcurrent, 2)
        XCTAssertEqual(harness.gate.snapshot.starts.count, 4)
        stats = await harness.service.statistics
        XCTAssertEqual(stats.activeWorkerCount, 0)
    }

    func testRapidSelectionPublishesOnlyTheLatestPreviewAfterCancelledReadReturns() async throws {
        let harness = DemoMediaBrowserHarness()
        defer { harness.close() }
        let model = harness.model
        harness.mount(preview: true)
        try await harness.starts(1)
        XCTAssertTrue(model.select(id: "sample:tiles"))
        XCTAssertTrue(model.select(id: "sample:broken"))
        XCTAssertTrue(model.select(id: "sample:tiles"))
        XCTAssertEqual(model.activeReadCount, 1)
        XCTAssertEqual(model.pendingPreviewID, "sample:tiles")
        XCTAssertEqual(harness.gate.snapshot.starts.count, 1)

        try await harness.finishCurrent([0], data: png([255, 0, 0, 255]))
        try await harness.starts(2)
        XCTAssertEqual(model.preview.phase, .loading)
        XCTAssertEqual(harness.gate.snapshot.starts[1].source, model.records[1].source)
        try await harness.finishCurrent([1], data: png([0, 0, 255, 255]))
        XCTAssertEqual(model.selectedID, "sample:tiles")
        XCTAssertEqual(Array(try ready(model.preview).pixelData), [255, 0, 0, 255])
        XCTAssertEqual(harness.gate.snapshot.maximumConcurrent, 1)
    }

    func testLateReaderFailureCannotOverwriteANewerSelection() async throws {
        let harness = DemoMediaBrowserHarness()
        defer { harness.close() }
        harness.mount(preview: true)
        try await harness.starts(1)
        let old = harness.model.activeReadTasks
        XCTAssertTrue(harness.model.select(id: "sample:tiles"))
        XCTAssertTrue(harness.gate.finish(0, result: .failure(DemoMediaImageError.decodingFailed)))
        try await harness.awaitTasks(old)
        try await harness.starts(2)
        XCTAssertEqual(harness.model.preview.phase, .loading)
        try await harness.finishCurrent([1], data: png([255, 0, 0, 128]))
        XCTAssertEqual(Array(try ready(harness.model.preview).pixelData), [0, 0, 128, 128])
    }

    func testExplicitCancellationPersistsUntilRetryAndDoesNotFreeItsReadSlot() async throws {
        let harness = DemoMediaBrowserHarness()
        defer { harness.close() }
        let model = harness.model
        harness.mount(preview: true)
        try await harness.starts(1)
        XCTAssertTrue(model.cancel(id: "sample:corners"))
        XCTAssertEqual(model.preview.phase, .cancelled)
        XCTAssertNil(model.pendingPreviewID)
        XCTAssertEqual(model.activeReadCount, 1)
        let observed = await harness.gate.waitForCancellation(0)
        XCTAssertTrue(observed)
        try await harness.finishCurrent([0], data: png([255, 0, 0, 255]))
        XCTAssertEqual(model.preview.phase, .cancelled)
        XCTAssertEqual(model.activeReadCount, 0)
        XCTAssertEqual(harness.gate.snapshot.starts.count, 1)

        XCTAssertTrue(model.retry(id: "sample:corners"))
        try await harness.starts(2)
        try await harness.finishCurrent([1], data: png([0, 255, 0, 255]))
        XCTAssertEqual(Array(try ready(model.preview).pixelData), [0, 255, 0, 255])
    }

    func testCloseBeforeQueuedVisibilityTaskEntryPreventsSameTurnReadAdmission() async throws {
        let harness = DemoMediaBrowserHarness()
        defer { harness.close() }
        harness.mount(preview: true, thumbnails: harness.model.records.map(\.id))
        let queued = try XCTUnwrap(harness.visibilityTask)
        harness.model.close()
        await queued.value
        await harness.model.awaitServiceClose()
        XCTAssertTrue(harness.model.isClosed)
        XCTAssertFalse(harness.model.isActive)
        XCTAssertEqual(harness.model.activeReadCount, 0)
        XCTAssertTrue(harness.gate.snapshot.starts.isEmpty)
        XCTAssertFalse(harness.model.retry(id: "sample:corners"))
        XCTAssertFalse(harness.model.select(id: "sample:tiles"))
        XCTAssertFalse(harness.model.dropFiles([fileURL("after-close")]))
        let stats = await harness.service.statistics
        XCTAssertTrue(stats.isClosed)
        XCTAssertEqual(stats.activeWorkerCount, 0)
    }

    func testCancellationBeforeQueuedVisibilityTaskEntryPreventsARead() async throws {
        let harness = DemoMediaBrowserHarness()
        defer { harness.close() }
        harness.mount(preview: true, thumbnails: ["sample:corners"])
        let queued = try XCTUnwrap(harness.visibilityTask)
        queued.cancel()
        await queued.value
        XCTAssertFalse(harness.model.isActive)
        XCTAssertEqual(harness.model.activeReadCount, 0)
        XCTAssertTrue(harness.gate.snapshot.starts.isEmpty)
    }

    func testEnteredLifetimeCancellationRevokesAdmissionBeforeMainActorCleanup() async throws {
        let harness = DemoMediaBrowserHarness()
        defer { harness.close() }
        harness.mount(preview: true, thumbnails: ["sample:tiles"])
        try await harness.starts(2)
        let work = harness.model.activeReadTasks
        let visibility = try XCTUnwrap(harness.visibilityTask)
        visibility.cancel()
        XCTAssertFalse(harness.model.isActive)
        XCTAssertFalse(harness.model.select(id: "sample:broken"))
        XCTAssertFalse(harness.model.retry(id: "sample:tiles"))
        XCTAssertFalse(harness.model.dropFiles([fileURL("cancelled-mount")]))
        harness.model.setBrowserVisible(false, mountID: harness.mountID)
        XCTAssertTrue(harness.model.requestedVisibleIDs.isEmpty)
        XCTAssertEqual(harness.model.activeReadCount, 2)
        XCTAssertEqual(harness.gate.snapshot.starts.count, 2)
        for id in [0, 1] { XCTAssertTrue(harness.gate.finish(id, result: .success(png([255, 0, 0, 255])))) }
        try await harness.awaitTasks(work + [visibility])
        XCTAssertEqual(harness.model.activeReadCount, 0)
        XCTAssertEqual(harness.model.preview.phase, .idle)
        XCTAssertEqual(harness.gate.snapshot.starts.count, 2)
    }

    func testSupersededMountCallbacksAndQueuedTaskCannotRevokeTheReplacement() async throws {
        let harness = DemoMediaBrowserHarness()
        defer { harness.close() }
        let model = harness.model
        harness.mount(preview: true, thumbnails: ["sample:tiles"])
        try await harness.starts(2)
        let oldScope = model.pageScope
        let newMount = UUID()
        model.appear(mountID: newMount)
        model.setBrowserVisible(true, mountID: newMount)
        model.setPreviewVisible(true, mountID: newMount)
        model.setThumbnailVisible(id: "sample:tiles", pageScope: model.pageScope, visible: true, mountID: newMount)
        let replacement = Task { @MainActor in await model.runWhileVisible(mountID: newMount) }
        defer { replacement.cancel() }
        try await harness.waitFor { $0.isActive && $0.mountedViewID == newMount }
        model.setBrowserVisible(false, mountID: harness.mountID)
        model.setPreviewVisible(false, mountID: harness.mountID)
        model.setThumbnailVisible(id: "sample:tiles", pageScope: oldScope, visible: false, mountID: harness.mountID)
        model.disappear(mountID: harness.mountID)
        let staleEntry = Task { @MainActor in await model.runWhileVisible(mountID: harness.mountID) }
        await staleEntry.value
        XCTAssertEqual(model.mountedViewID, newMount)
        XCTAssertTrue(model.isActive)
        XCTAssertEqual(model.requestedVisibleIDs, ["sample:tiles"])
        XCTAssertEqual(model.activeReadCount, 2)
        XCTAssertEqual(harness.gate.snapshot.starts.count, 2)
        try await harness.finishCurrent([0, 1], data: png([255, 0, 0, 255]))
        try await harness.starts(4)
        XCTAssertTrue(model.isActive)
        try await harness.finishCurrent([2, 3], data: png([0, 0, 255, 255]))
        XCTAssertEqual(Array(try ready(model.preview).pixelData), [255, 0, 0, 255])
        XCTAssertEqual(Array(try ready(model.thumbnail(for: "sample:tiles")).pixelData), [255, 0, 0, 255])
        XCTAssertEqual(harness.gate.snapshot.maximumConcurrent, 2)
    }

    func testDisappearanceBeforeQueuedTaskEntryPreventsARead() async throws {
        let harness = DemoMediaBrowserHarness()
        defer { harness.close() }
        harness.mount(preview: true, thumbnails: ["sample:corners"])
        let queued = try XCTUnwrap(harness.visibilityTask)
        harness.model.disappear(mountID: harness.mountID)
        await queued.value
        XCTAssertNil(harness.model.mountedViewID)
        XCTAssertFalse(harness.model.isActive)
        XCTAssertEqual(harness.model.activeReadCount, 0)
        XCTAssertTrue(harness.gate.snapshot.starts.isEmpty)
    }

    func testBrowserVisibilityLossClearsDemandAndRetainsBothSlotsUntilReturn() async throws {
        let harness = DemoMediaBrowserHarness()
        defer { harness.close() }
        let model = harness.model
        harness.mount(preview: true, thumbnails: ["sample:tiles"])
        try await harness.starts(2)
        model.setBrowserVisible(false, mountID: harness.mountID)
        XCTAssertFalse(model.isActive)
        XCTAssertTrue(model.requestedVisibleIDs.isEmpty)
        XCTAssertTrue(model.pendingThumbnailIDs.isEmpty)
        XCTAssertNil(model.pendingPreviewID)
        XCTAssertEqual(model.activeReadCount, 2)
        try await harness.finishCurrent([0, 1], data: png([255, 0, 0, 255]))
        XCTAssertEqual(model.activeReadCount, 0)
        model.setBrowserVisible(true, mountID: harness.mountID)
        XCTAssertEqual(
            model.activeReadCount, 0, "Fresh image-well visibility is required after the browser leaves its clip.")
        model.setPreviewVisible(true, mountID: harness.mountID)
        model.setThumbnailVisible(
            id: "sample:tiles", pageScope: model.pageScope, visible: true, mountID: harness.mountID)
        try await harness.starts(4)
        XCTAssertEqual(harness.gate.snapshot.maximumConcurrent, 2)
        try await harness.finishCurrent([2, 3], data: png([0, 0, 255, 255]))
        XCTAssertEqual(model.preview.phase, .ready)
    }

    func testPreviewVisibilityCancelsOnlyItsLaneWhileThumbnailWorkContinues() async throws {
        let harness = DemoMediaBrowserHarness()
        defer { harness.close() }
        let model = harness.model
        harness.mount(preview: true, thumbnails: ["sample:tiles"])
        try await harness.starts(2)
        let previewRead = try XCTUnwrap(harness.gate.snapshot.starts.first { $0.source == model.records[0].source })
        let thumbnailRead = try XCTUnwrap(harness.gate.snapshot.starts.first { $0.source == model.records[1].source })
        model.setPreviewVisible(false, mountID: harness.mountID)
        XCTAssertEqual(model.preview.phase, .idle)
        XCTAssertEqual(model.thumbnail(for: "sample:tiles").phase, .loading)
        let cancelled = await harness.gate.waitForCancellation(previewRead.id)
        XCTAssertTrue(cancelled)
        XCTAssertFalse(harness.gate.snapshot.cancellations.contains(thumbnailRead.id))
        XCTAssertTrue(harness.gate.finish(previewRead.id, result: .success(png([255, 0, 0, 255]))))
        try await harness.waitFor { $0.activeReadCount == 1 }
        try await harness.finishCurrent([thumbnailRead.id], data: png([0, 255, 0, 255]))
        XCTAssertEqual(model.preview.phase, .idle)
        XCTAssertEqual(Array(try ready(model.thumbnail(for: "sample:tiles")).pixelData), [0, 255, 0, 255])
        XCTAssertEqual(harness.gate.snapshot.starts.count, 2)
    }

    func testPageAtoBtoARejectsOldVisibilityAndCoalescesOnlyTheLatestPage() async throws {
        let harness = DemoMediaBrowserHarness(includesSamples: false)
        defer { harness.close() }
        let model = harness.model
        XCTAssertTrue(model.dropFiles((0..<8).map { fileURL("page-\($0)") }))
        let firstID = model.records[0].id
        let secondPageID = model.records[4].id
        let firstScope = model.pageScope
        harness.mount(thumbnails: [firstID])
        try await harness.starts(1)
        XCTAssertTrue(model.setPage(1))
        let secondScope = model.pageScope
        XCTAssertNotEqual(firstScope, secondScope)
        model.setThumbnailVisible(id: secondPageID, pageScope: secondScope, visible: true, mountID: harness.mountID)
        XCTAssertEqual(model.pendingThumbnailIDs, [secondPageID])
        XCTAssertTrue(model.setPage(0))
        let latestScope = model.pageScope
        XCTAssertNotEqual(firstScope, latestScope)
        model.setThumbnailVisible(id: firstID, pageScope: firstScope, visible: true, mountID: harness.mountID)
        model.setThumbnailVisible(id: secondPageID, pageScope: secondScope, visible: true, mountID: harness.mountID)
        XCTAssertTrue(model.requestedVisibleIDs.isEmpty)
        model.setThumbnailVisible(id: firstID, pageScope: latestScope, visible: true, mountID: harness.mountID)
        model.setThumbnailVisible(id: firstID, pageScope: firstScope, visible: false, mountID: harness.mountID)
        XCTAssertEqual(model.requestedVisibleIDs, [firstID])
        XCTAssertEqual(model.pendingThumbnailIDs, [firstID])
        XCTAssertEqual(model.snapshot.thumbnails.count, 4)
        XCTAssertEqual(model.activeReadCount, 1)
        XCTAssertEqual(model.selectedID, firstID)
        try await harness.finishCurrent([0], data: png([255, 0, 0, 255]))
        try await harness.starts(2)
        XCTAssertEqual(harness.gate.snapshot.starts.map(\.source), Array(repeating: model.records[0].source, count: 2))
        try await harness.finishCurrent([1], data: png([0, 0, 255, 255]))
        XCTAssertEqual(Array(try ready(model.thumbnail(for: firstID)).pixelData), [255, 0, 0, 255])
        XCTAssertEqual(model.thumbnail(for: secondPageID).phase, .idle)
        XCTAssertEqual(harness.gate.snapshot.maximumConcurrent, 1)
    }

    func testLayoutReplacementPreservesSelectionAndReadyPixelsButRequiresFreshVisibility() async throws {
        let harness = DemoMediaBrowserHarness()
        defer { harness.close() }
        let model = harness.model
        harness.mount(thumbnails: ["sample:corners"])
        try await harness.starts(1)
        try await harness.finishCurrent([0], data: png([255, 0, 0, 128]))
        let pixels = try ready(model.thumbnail(for: "sample:corners")).pixelData
        let oldScope = model.pageScope
        model.setLayout(.list)
        XCTAssertEqual(model.layout, .list)
        XCTAssertEqual(model.selectedID, "sample:corners")
        XCTAssertNotEqual(model.pageScope, oldScope)
        XCTAssertTrue(model.requestedVisibleIDs.isEmpty)
        XCTAssertEqual(try ready(model.thumbnail(for: "sample:corners")).pixelData, pixels)
        model.setThumbnailVisible(id: "sample:tiles", pageScope: oldScope, visible: true, mountID: harness.mountID)
        XCTAssertEqual(model.activeReadCount, 0)
        model.setThumbnailVisible(
            id: "sample:corners", pageScope: model.pageScope, visible: true, mountID: harness.mountID)
        XCTAssertEqual(model.activeReadCount, 0, "A retained page image does not need another decode.")
        model.setThumbnailVisible(
            id: "sample:tiles", pageScope: model.pageScope, visible: true, mountID: harness.mountID)
        try await harness.starts(2)
        try await harness.finishCurrent([1], data: png([0, 255, 0, 255]))
        XCTAssertEqual(model.selectedID, "sample:corners")
    }

    func testDropAdmissionDeduplicatesLexicalIdentityAndPreservesTheOriginalURL() async throws {
        let harness = DemoMediaBrowserHarness(includesSamples: false)
        defer { harness.close() }
        let original = try XCTUnwrap(URL(string: "file://localhost/C:/Media/./image.png"))
        let alias = try XCTUnwrap(URL(string: "file:///C:/Media/image.png"))
        let expectedID = "file:\(try DemoFilePreviewService.validateFileURL(original).absoluteString)"
        XCTAssertTrue(harness.model.dropFiles([original, alias, original]))
        XCTAssertEqual(harness.model.records.count, 1)
        XCTAssertEqual(harness.model.selectedID, expectedID)
        XCTAssertEqual(harness.model.records.first?.source, .file(original))
        XCTAssertEqual(harness.model.records.first?.name, "image.png")
        XCTAssertTrue(harness.model.notice?.contains("Skipped 2") == true)
        XCTAssertFalse(harness.model.dropFiles([alias]))
        XCTAssertTrue(harness.gate.snapshot.starts.isEmpty)
        harness.mount(preview: true)
        try await harness.starts(1)
        XCTAssertEqual(harness.gate.snapshot.starts.first?.source, .file(original))
    }

    func testDropRejectsUnsupportedURLsAndBoundsBothScanningAndRecordAdmission() async throws {
        let harness = DemoMediaBrowserHarness(includesSamples: false)
        defer { harness.close() }
        let bad = try XCTUnwrap(URL(string: "https://example.invalid/image.png"))
        let invalid = try [
            "file://remote.invalid/C:/Media/image.png", "file:///C:/Media/image.png?query=1",
            "file:///C:/Media/image.png#fragment", "file:///C:/Media/../image.png",
            "file:///C:/Media/bad%00name.png",
        ].map { try XCTUnwrap(URL(string: $0)) }
        XCTAssertFalse(harness.model.dropFiles(invalid))
        XCTAssertFalse(harness.model.dropFiles(Array(repeating: bad, count: 4096) + [fileURL("not-examined")]))
        XCTAssertTrue(harness.model.records.isEmpty)
        XCTAssertNil(harness.model.selectedID)
        XCTAssertTrue(harness.gate.snapshot.starts.isEmpty)
        XCTAssertTrue(harness.model.dropFiles((0..<128).map { fileURL("bounded-\($0)") }))
        XCTAssertEqual(harness.model.records.count, 64)
        XCTAssertEqual(Set(harness.model.records.map(\.id)).count, 64)
        XCTAssertEqual(harness.model.pageCount, 16)
        XCTAssertEqual(harness.model.visibleRecords.count, 4)
        XCTAssertEqual(harness.model.snapshot.thumbnails.count, 4)
        XCTAssertFalse(harness.model.dropFiles([fileURL("overflow")]))
        XCTAssertEqual(harness.model.records.count, 64)
        XCTAssertFalse(harness.model.setPage(-1))
        XCTAssertFalse(harness.model.setPage(16))
        XCTAssertTrue(harness.gate.snapshot.starts.isEmpty)
    }

    func testRemoveClearAndSamplesKeepSelectionValidWithoutDecoding() async throws {
        let harness = DemoMediaBrowserHarness()
        defer { harness.close() }
        let model = harness.model
        XCTAssertFalse(model.select(id: "missing"))
        XCTAssertFalse(model.select(id: model.selectedID))
        XCTAssertTrue(model.select(id: "sample:broken"))
        XCTAssertTrue(model.removeSelected())
        XCTAssertEqual(model.selectedID, "sample:unsupported")
        XCTAssertTrue(model.removeSelected())
        XCTAssertEqual(model.selectedID, "sample:tiles")
        XCTAssertFalse(model.select(id: "sample:broken"))
        model.clear()
        XCTAssertTrue(model.records.isEmpty)
        XCTAssertTrue(model.snapshot.thumbnails.isEmpty)
        XCTAssertNil(model.selectedID)
        XCTAssertEqual(model.pageCount, 1)
        XCTAssertFalse(model.removeSelected())
        model.restoreSamples()
        XCTAssertEqual(model.records, DemoMediaBrowserRecord.samples)
        XCTAssertEqual(model.selectedID, "sample:corners")
        XCTAssertEqual(model.preview.phase, .idle)
        XCTAssertEqual(model.activeReadCount, 0)
        XCTAssertTrue(harness.gate.snapshot.starts.isEmpty)
    }

    func testRetryChangesBothCachedSizesAndReaddedURLCannotReuseAnOldRevision() async throws {
        let harness = DemoMediaBrowserHarness(includesSamples: false)
        defer { harness.close() }
        let model = harness.model
        let url = fileURL("revision")
        XCTAssertTrue(model.dropFiles([url]))
        let id = try XCTUnwrap(model.selectedID)
        harness.mount(preview: true, thumbnails: [id])
        try await harness.starts(2)
        try await harness.finishCurrent([0, 1], data: png([255, 0, 0, 255]))
        var stats = await harness.service.statistics
        XCTAssertEqual(stats.cachedImageCount, 2)
        XCTAssertEqual(stats.cachedPixelBytes, 8)
        XCTAssertTrue(model.retry(id: id))
        try await harness.starts(4)
        stats = await harness.service.statistics
        XCTAssertEqual(stats.cachedImageCount, 0)
        try await harness.finishCurrent([2, 3], data: png([0, 0, 255, 255]))
        XCTAssertEqual(Array(try ready(model.preview).pixelData), [255, 0, 0, 255])
        XCTAssertEqual(Array(try ready(model.thumbnail(for: id)).pixelData), [255, 0, 0, 255])
        model.clear()
        XCTAssertTrue(model.dropFiles([url]))
        XCTAssertEqual(model.selectedID, id)
        try await harness.starts(5)
        XCTAssertEqual(model.activeReadCount, 1, "Only the still-visible preview can load before new page visibility.")
        try await harness.finishCurrent([4], data: png([0, 255, 0, 255]))
        XCTAssertEqual(Array(try ready(model.preview).pixelData), [0, 255, 0, 255])
        XCTAssertEqual(harness.gate.snapshot.maximumConcurrent, 2)
    }

    func testRealSampleBytesDecodeAndMalformedInputsNeverBecomeReady() async throws {
        let service = DemoMediaImageService()
        let model = DemoMediaBrowserModel(service: service)
        let observation = DemoMediaBrowserObserver(model)
        let mountID = UUID()
        model.appear(mountID: mountID)
        model.setBrowserVisible(true, mountID: mountID)
        model.setPreviewVisible(true, mountID: mountID)
        for record in model.records {
            model.setThumbnailVisible(id: record.id, pageScope: model.pageScope, visible: true, mountID: mountID)
        }
        let visible = Task { @MainActor in await model.runWhileVisible(mountID: mountID) }
        defer {
            model.close()
            visible.cancel()
            observation.close()
        }
        let completed = await observation.waitFor { browser in
            browser.preview.phase == .ready && browser.activeReadCount == 0
                && browser.visibleRecords.allSatisfy { record in
                    [.ready, .failed].contains(browser.thumbnail(for: record.id).phase)
                }
        }
        XCTAssertTrue(completed)
        let first = try ready(model.thumbnail(for: "sample:corners"))
        let second = try ready(model.thumbnail(for: "sample:tiles"))
        XCTAssertEqual(first.pixelWidth, 24)
        XCTAssertEqual(first.pixelHeight, 16)
        XCTAssertEqual(first.byteCount, 24 * 16 * 4)
        XCTAssertEqual(second.pixelWidth, 7)
        XCTAssertEqual(second.pixelHeight, 5)
        XCTAssertEqual(second.byteCount, 7 * 5 * 4)
        XCTAssertEqual(try ready(model.preview).pixelData, first.pixelData)
        XCTAssertEqual(model.thumbnail(for: "sample:broken").phase, .failed)
        XCTAssertEqual(model.thumbnail(for: "sample:unsupported").phase, .failed)
        let stats = await service.statistics
        XCTAssertEqual(stats.cachedImageCount, 0)
        XCTAssertEqual(stats.activeWorkerCount, 0)
    }

    func testRequestedThumbnailAndPreviewDimensionsUseTheRealDecoder() async throws {
        let harness = DemoMediaBrowserHarness(includesSamples: false)
        defer { harness.close() }
        XCTAssertTrue(harness.model.dropFiles([fileURL("dimensions")]))
        let id = try XCTUnwrap(harness.model.selectedID)
        harness.mount(preview: true, thumbnails: [id])
        try await harness.starts(2)
        try await harness.finishCurrent([0, 1], data: MediaImageTestFixtures.bmp(width: 1200, height: 600, gray: 47))
        let preview = try ready(harness.model.preview)
        let thumbnail = try ready(harness.model.thumbnail(for: id))
        XCTAssertEqual(preview.pixelWidth, 1024)
        XCTAssertEqual(preview.pixelHeight, 512)
        XCTAssertEqual(thumbnail.pixelWidth, 256)
        XCTAssertEqual(thumbnail.pixelHeight, 128)
        XCTAssertEqual(preview.sourcePixelWidth, 1200)
        XCTAssertEqual(thumbnail.sourcePixelHeight, 600)
        XCTAssertEqual(Array(thumbnail.pixelData.prefix(4)), [47, 47, 47, 255])
        let stats = await harness.service.statistics
        XCTAssertEqual(stats.cachedPixelBytes, (1024 * 512 + 256 * 128) * 4)
    }

    func testNotificationReentrySelectsNewIntentWithoutRepublishingTheOldImage() async throws {
        let harness = DemoMediaBrowserHarness()
        defer { harness.close() }
        let model = harness.model
        var changedSelection = false
        let subscription = model.objectWillChange.sink { _ in
            guard !changedSelection, model.preview.phase == .ready else { return }
            changedSelection = true
            XCTAssertTrue(model.select(id: "sample:tiles"))
        }
        defer { subscription.cancel() }
        harness.mount(preview: true)
        try await harness.starts(1)
        try await harness.finishCurrent([0], data: png([255, 0, 0, 255]))
        try await harness.starts(2)
        XCTAssertTrue(changedSelection)
        XCTAssertEqual(model.selectedID, "sample:tiles")
        XCTAssertEqual(model.preview.phase, .loading)
        try await harness.finishCurrent([1], data: png([0, 0, 255, 255]))
        XCTAssertEqual(Array(try ready(model.preview).pixelData), [255, 0, 0, 255])
        XCTAssertEqual(harness.gate.snapshot.starts.count, 2)
    }

    func testErrorDescriptionReentryCannotPublishAfterClose() async throws {
        let harness = DemoMediaBrowserHarness()
        defer { harness.close() }
        let model = harness.model
        harness.mount(preview: true)
        try await harness.starts(1)
        let tasks = model.activeReadTasks
        let error = DemoMediaBrowserDescriptionError {
            MainActor.assumeIsolated { model.close() }
        }
        XCTAssertTrue(harness.gate.finish(0, result: .failure(error)))
        try await harness.awaitTasks(tasks)
        await model.awaitServiceClose()
        XCTAssertTrue(model.isClosed)
        XCTAssertEqual(model.preview.phase, .cancelled)
        XCTAssertEqual(model.activeReadCount, 0)
        XCTAssertTrue(model.snapshot.thumbnails.isEmpty)
        XCTAssertEqual(harness.gate.snapshot.starts.count, 1)
    }

    func testIndependentWindowOwnershipClosesOnlyItsOwnServiceAndLifetime() async throws {
        let first = DemoMediaBrowserHarness()
        let second = DemoMediaBrowserHarness()
        defer {
            first.close()
            second.close()
        }
        var firstWindow: DemoWindowState? = DemoWindowState(mediaBrowser: first.model)
        let secondWindow = DemoWindowState(mediaBrowser: second.model)
        defer { withExtendedLifetime(secondWindow) {} }
        XCTAssertTrue(firstWindow?.mediaBrowser === first.model)
        XCTAssertTrue(secondWindow.mediaBrowser === second.model)
        first.mount(preview: true)
        second.mount(preview: true)
        try await first.starts(1)
        try await second.starts(1)
        firstWindow = nil
        XCTAssertTrue(first.model.isClosed)
        XCTAssertFalse(second.model.isClosed)
        XCTAssertEqual(first.model.activeReadCount, 1)
        XCTAssertEqual(second.model.preview.phase, .loading)
        try await first.finishCurrent([0], data: png([255, 0, 0, 255]))
        try await second.finishCurrent([0], data: png([0, 0, 255, 255]))
        XCTAssertEqual(first.model.preview.phase, .cancelled)
        XCTAssertEqual(Array(try ready(second.model.preview).pixelData), [255, 0, 0, 255])
        await first.model.awaitServiceClose()
        let firstStats = await first.service.statistics
        let secondStats = await second.service.statistics
        XCTAssertTrue(firstStats.isClosed)
        XCTAssertFalse(secondStats.isClosed)
    }

    private func fileURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("media-browser-\(name).png", isDirectory: false)
    }

    private func png(_ rgba: [UInt8]) -> Data {
        MediaImageTestFixtures.png(width: 1, height: 1, rgba: rgba)
    }

    private func ready(
        _ state: DemoMediaBrowserLoadState, file: StaticString = #filePath, line: UInt = #line
    ) throws -> DemoMediaImage {
        guard case .ready(let image) = state else {
            XCTFail("Expected decoded owned pixels, got \(state.phase)", file: file, line: line)
            throw DemoMediaBrowserWaitError.missingRead
        }
        return image
    }
}

private struct DemoMediaBrowserDescriptionError: LocalizedError, Sendable {
    let action: @Sendable () -> Void
    var errorDescription: String? {
        action()
        return "This error description must not publish after closing the browser."
    }
}
