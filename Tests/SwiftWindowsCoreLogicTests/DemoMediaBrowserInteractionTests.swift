import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsDemo
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Public shared views, real retained inputs/visibility, and real decoded
/// pixels. These are not native window, Explorer, Narrator, or macOS evidence.
@MainActor
final class DemoMediaBrowserInteractionTests: XCTestCase {
    func testTypedURLDropSelectsAFileAndComposesActualPremultipliedPixels() async throws {
        let harness = DemoMediaBrowserHarness(includesSamples: false)
        let fixture = DemoMediaBrowserFixture(model: harness.model)
        defer {
            fixture.close()
            harness.close()
        }
        try await harness.waitFor { $0.isActive }
        let url = fileURL("dropped")
        XCTAssertTrue(fixture.runtime.performFileDrop([url], at: Point(x: 80, y: 220)))
        fixture.rebuild()
        try await harness.starts(2)
        try await harness.finishCurrent([0, 1], data: png([255, 0, 0, 128]))
        fixture.rebuild()
        let id = try XCTUnwrap(harness.model.selectedID)
        XCTAssertEqual(harness.model.records.count, 1)
        XCTAssertEqual(harness.model.selectedRecord?.source, .file(url))
        XCTAssertNotNil(try fixture.node("media.browser.thumbnail.\(id).ready"))
        XCTAssertNotNil(try fixture.node("media.browser.preview.ready"))
        XCTAssertEqual(fixture.bitmaps.count, 2)
        for bitmap in fixture.bitmaps {
            XCTAssertEqual(bitmap.width, 1)
            XCTAssertEqual(bitmap.height, 1)
            XCTAssertEqual(bitmap.format, .bgra8Premultiplied)
            XCTAssertEqual(Array(bitmap.pixels), [0, 0, 128, 128])
            XCTAssertNoThrow(try bitmap.validate())
        }
        XCTAssertTrue(fixture.texts.contains("1 × 1 source · 1 × 1 preview"))
    }

    func testTypedDropRejectsNonFileURLsWithoutReportingSuccessfulImages() async throws {
        let harness = DemoMediaBrowserHarness(includesSamples: false)
        let fixture = DemoMediaBrowserFixture(model: harness.model)
        defer {
            fixture.close()
            harness.close()
        }
        try await harness.waitFor { $0.isActive }
        let url = try XCTUnwrap(URL(string: "https://example.invalid/image.png"))
        XCTAssertFalse(fixture.runtime.performFileDrop([url], at: Point(x: 80, y: 220)))
        fixture.rebuild()
        XCTAssertTrue(harness.model.records.isEmpty)
        XCTAssertNil(harness.model.selectedID)
        XCTAssertEqual(harness.model.activeReadCount, 0)
        XCTAssertTrue(harness.gate.snapshot.starts.isEmpty)
        XCTAssertTrue(fixture.bitmaps.isEmpty)
        XCTAssertNotNil(try fixture.node("media.browser.empty"))
        XCTAssertNotNil(try fixture.node("media.browser.notice"))
    }

    func testGridButtonsAndListArrowSelectionUseStableRecordIdentity() async throws {
        let harness = DemoMediaBrowserHarness()
        let fixture = DemoMediaBrowserFixture(model: harness.model)
        defer {
            fixture.close()
            harness.close()
        }
        try await harness.starts(2)
        fixture.rebuild()
        let mounted = harness.model.mountedViewID
        try fixture.activate("media.browser.select.sample:tiles")
        XCTAssertEqual(harness.model.selectedID, "sample:tiles")
        try fixture.activate("media.browser.list")
        fixture.rebuild()
        XCTAssertEqual(harness.model.layout, .list)
        XCTAssertEqual(harness.model.selectedID, "sample:tiles")
        XCTAssertEqual(fixture.selectableRows.count, 4)
        let second = try fixture.row("sample:tiles")
        XCTAssertTrue(second.accessibilityTraits.contains(.isSelected))
        fixture.runtime.requestFocus(second)
        fixture.runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.downArrow.rawValue))
        fixture.rebuild()
        XCTAssertEqual(harness.model.selectedID, "sample:broken")
        XCTAssertTrue(try fixture.row("sample:broken").accessibilityTraits.contains(.isSelected))
        XCTAssertTrue(try fixture.row("sample:broken").isFocused)
        XCTAssertEqual(harness.model.mountedViewID, mounted)
        XCTAssertEqual(harness.model.pendingPreviewID, "sample:broken")
        XCTAssertEqual(harness.gate.snapshot.starts.count, 2)
        XCTAssertEqual(harness.model.activeReadCount, 2)
        XCTAssertTrue(fixture.bitmaps.isEmpty)
    }

    func testPublicCancelAndRetryButtonsShowRealFailureThenDecodedSuccess() async throws {
        let harness = DemoMediaBrowserHarness(includesSamples: false)
        XCTAssertTrue(harness.model.dropFiles([fileURL("retry")]))
        let fixture = DemoMediaBrowserFixture(model: harness.model)
        defer {
            fixture.close()
            harness.close()
        }
        try await harness.starts(2)
        fixture.rebuild()
        try fixture.activate("media.browser.preview.cancel")
        fixture.rebuild()
        XCTAssertEqual(harness.model.preview.phase, .cancelled)
        XCTAssertEqual(harness.model.activeReadCount, 2)
        XCTAssertNotNil(try fixture.node("media.browser.preview.cancelled"))
        try await harness.finishCurrent([0, 1], data: png([255, 0, 0, 255]))
        fixture.rebuild()
        XCTAssertTrue(fixture.bitmaps.isEmpty)

        try fixture.activate("media.browser.preview.retry")
        try await harness.starts(4)
        fixture.rebuild()
        XCTAssertNotNil(try fixture.node("media.browser.preview.loading"))
        try await harness.finishCurrent([2, 3], data: Data([137, 80, 78]))
        fixture.rebuild()
        XCTAssertEqual(harness.model.preview.phase, .failed)
        XCTAssertNotNil(try fixture.node("media.browser.preview.failed"))
        XCTAssertTrue(fixture.texts.contains("The image data is empty, malformed, or incomplete."))
        XCTAssertTrue(fixture.bitmaps.isEmpty)

        try fixture.activate("media.browser.preview.retry")
        try await harness.starts(6)
        try await harness.finishCurrent([4, 5], data: png([0, 255, 0, 255]))
        fixture.rebuild()
        XCTAssertEqual(harness.model.preview.phase, .ready)
        XCTAssertEqual(fixture.bitmaps.count, 2)
        XCTAssertTrue(fixture.bitmaps.allSatisfy { Array($0.pixels) == [0, 255, 0, 255] })
        XCTAssertEqual(harness.gate.snapshot.maximumConcurrent, 2)
    }

    func testClearSamplesAndRemoveButtonsChangeTheRealFiniteCollection() async throws {
        let harness = DemoMediaBrowserHarness()
        let fixture = DemoMediaBrowserFixture(model: harness.model)
        defer {
            fixture.close()
            harness.close()
        }
        try await harness.starts(2)
        fixture.rebuild()
        try fixture.activate("media.browser.clear")
        fixture.rebuild()
        XCTAssertTrue(harness.model.records.isEmpty)
        XCTAssertNil(harness.model.selectedID)
        XCTAssertNotNil(try fixture.node("media.browser.empty"))
        try await harness.finishCurrent([0, 1], data: png([255, 0, 0, 255]))
        XCTAssertEqual(harness.model.activeReadCount, 0)
        try fixture.activate("media.browser.samples")
        fixture.rebuild()
        try await harness.starts(4)
        XCTAssertEqual(harness.model.records, DemoMediaBrowserRecord.samples)
        XCTAssertEqual(harness.model.visibleRecords.count, 4)
        try fixture.activate("media.browser.remove")
        fixture.rebuild()
        XCTAssertEqual(harness.model.records.count, 3)
        XCTAssertEqual(harness.model.selectedID, "sample:tiles")
        XCTAssertFalse(fixture.nodes.contains { $0.accessibilityIdentifier == "media.browser.record.sample:corners" })
        XCTAssertEqual(harness.gate.snapshot.starts.count, 4)
        XCTAssertEqual(harness.model.activeReadCount, 2)
    }

    func testSameGeometryPageAtoBtoARecreatesVisibilityWithoutLoadingOffPageImages() async throws {
        let harness = DemoMediaBrowserHarness(includesSamples: false)
        XCTAssertTrue(harness.model.dropFiles((0..<8).map { fileURL("page-\($0)") }))
        let fixture = DemoMediaBrowserFixture(model: harness.model)
        defer {
            fixture.close()
            harness.close()
        }
        try await harness.starts(2)
        fixture.rebuild()
        let selected = try XCTUnwrap(harness.model.selectedID)
        let mounted = harness.model.mountedViewID
        let firstScope = harness.model.pageScope
        try fixture.activate("media.browser.next")
        fixture.rebuild()
        XCTAssertEqual(harness.model.pageIndex, 1)
        XCTAssertEqual(harness.model.selectedID, selected)
        XCTAssertEqual(harness.model.requestedVisibleIDs, Set(harness.model.visibleRecords.map(\.id)))
        try fixture.activate("media.browser.previous")
        fixture.rebuild()
        XCTAssertEqual(harness.model.pageIndex, 0)
        XCTAssertNotEqual(harness.model.pageScope, firstScope)
        XCTAssertEqual(harness.model.mountedViewID, mounted)
        XCTAssertEqual(harness.model.requestedVisibleIDs, Set(harness.model.visibleRecords.map(\.id)))
        XCTAssertEqual(harness.model.snapshot.thumbnails.count, 4)
        XCTAssertEqual(harness.gate.snapshot.starts.count, 2)
        try await harness.finishCurrent([0, 1], data: png([255, 0, 0, 255]))
        try await harness.starts(3)
        XCTAssertEqual(harness.gate.snapshot.starts[2].source, harness.model.records[0].source)
        try await harness.finishCurrent([2], data: png([0, 0, 255, 255]))
        fixture.rebuild()
        XCTAssertEqual(Array(try image(harness.model.thumbnail(for: selected)).pixelData), [255, 0, 0, 255])
        let offPage = Set(harness.model.records.suffix(4).map(\.id))
        XCTAssertFalse(harness.model.pendingThumbnailIDs.contains { offPage.contains($0) })
        XCTAssertTrue(
            harness.gate.snapshot.starts.allSatisfy { start in
                harness.model.visibleRecords.contains { $0.source == start.source }
            })
        XCTAssertEqual(harness.model.selectedID, selected)
    }

    func testInnerScrollVisibilityCancelsOffscreenThumbnailsAndLoadsTheVisiblePreview() async throws {
        let harness = DemoMediaBrowserHarness()
        let fixture = DemoMediaBrowserFixture(model: harness.model, size: IntSize(width: 360, height: 560))
        defer {
            fixture.close()
            harness.close()
        }
        try await harness.starts(1)
        XCTAssertEqual(harness.model.preview.phase, .idle)
        XCTAssertNil(harness.model.pendingPreviewID)
        XCTAssertEqual(harness.model.activeReadCount, 1)
        XCTAssertFalse(harness.model.requestedVisibleIDs.isEmpty)
        try fixture.scroll(to: 10_000)
        try await harness.starts(2)
        XCTAssertTrue(harness.model.requestedVisibleIDs.isEmpty)
        XCTAssertTrue(harness.model.pendingThumbnailIDs.isEmpty)
        XCTAssertEqual(harness.model.preview.phase, .loading)
        let cancelled = await harness.gate.waitForCancellation(0)
        XCTAssertTrue(cancelled)
        XCTAssertEqual(
            harness.model.activeReadCount, 2, "The invisible thumbnail still owns its cancelled physical read.")
        try await harness.finishCurrent([0, 1], data: png([0, 0, 255, 255]))
        XCTAssertEqual(harness.model.preview.phase, .ready)
        XCTAssertEqual(harness.model.activeReadCount, 0)
        try fixture.scroll(to: 0)
        try await harness.starts(3)
        XCTAssertFalse(harness.model.requestedVisibleIDs.isEmpty)
        XCTAssertLessThanOrEqual(harness.model.pendingThumbnailIDs.count, 4)
        XCTAssertEqual(harness.model.preview.phase, .ready)
        XCTAssertEqual(harness.gate.snapshot.maximumConcurrent, 2)
    }

    func testOuterScrollClipPreventsEagerWorkAndReentryUsesTheSameLiveMount() async throws {
        let harness = DemoMediaBrowserHarness()
        let fixture = DemoMediaBrowserFixture(model: harness.model, outerScroll: true)
        defer {
            fixture.close()
            harness.close()
        }
        let offscreen = try fixture.node("media.browser")
        XCTAssertGreaterThanOrEqual(fixture.bounds(of: offscreen).origin.y, 680)
        XCTAssertGreaterThan(fixture.bounds(of: offscreen).size.height, 0)
        XCTAssertFalse(offscreen.hasAppeared, "The actual retained paint must not admit this offscreen root.")
        XCTAssertNil(harness.model.mountedViewID)
        XCTAssertFalse(harness.model.isClosed)
        XCTAssertFalse(harness.model.isActive)
        XCTAssertTrue(harness.model.requestedVisibleIDs.isEmpty)
        XCTAssertTrue(harness.model.pendingThumbnailIDs.isEmpty)
        XCTAssertNil(harness.model.pendingPreviewID)
        XCTAssertTrue(harness.gate.snapshot.starts.isEmpty)
        XCTAssertEqual(harness.model.activeReadCount, 0)
        try fixture.scroll("media.test.outer.scroll", to: 800)
        try await harness.starts(2)
        let mounted = try XCTUnwrap(harness.model.mountedViewID)
        XCTAssertTrue(harness.model.isActive)
        try fixture.scroll("media.test.outer.scroll", to: 0)
        XCTAssertFalse(harness.model.isActive)
        XCTAssertTrue(harness.model.requestedVisibleIDs.isEmpty)
        XCTAssertEqual(harness.model.activeReadCount, 2)
        try await harness.finishCurrent([0, 1], data: png([255, 0, 0, 255]))
        XCTAssertEqual(harness.gate.snapshot.starts.count, 2)
        XCTAssertEqual(harness.model.activeReadCount, 0)
        try fixture.scroll("media.test.outer.scroll", to: 800)
        try await harness.starts(4)
        XCTAssertEqual(harness.model.mountedViewID, mounted)
        XCTAssertTrue(harness.model.isActive)
        XCTAssertEqual(harness.gate.snapshot.maximumConcurrent, 2)
    }

    func testActualRemovalAndRemountCreateNewAuthorityWhileOldWorkersDrain() async throws {
        let harness = DemoMediaBrowserHarness()
        let fixture = DemoMediaBrowserFixture(model: harness.model)
        defer {
            fixture.close()
            harness.close()
        }
        try await harness.starts(2)
        let original = try XCTUnwrap(harness.model.mountedViewID)
        fixture.setVisible(false)
        XCTAssertNil(harness.model.mountedViewID)
        XCTAssertFalse(harness.model.isActive)
        XCTAssertEqual(harness.model.activeReadCount, 2)
        fixture.setVisible(true)
        let replacement = try XCTUnwrap(harness.model.mountedViewID)
        XCTAssertNotEqual(original, replacement)
        try await harness.waitFor { $0.isActive }
        XCTAssertEqual(harness.gate.snapshot.starts.count, 2)
        try await harness.finishCurrent([0, 1], data: png([255, 0, 0, 255]))
        try await harness.starts(4)
        XCTAssertEqual(harness.model.mountedViewID, replacement)
        XCTAssertEqual(harness.model.preview.phase, .loading)
        XCTAssertEqual(harness.gate.snapshot.maximumConcurrent, 2)
    }

    func testDelayedOldRemovalTransitionCannotDisableTheReplacementMount() async throws {
        let harness = DemoMediaBrowserHarness()
        let fixture = DemoMediaBrowserFixture(model: harness.model, transitionRemoval: true)
        defer {
            fixture.close()
            harness.close()
        }
        try await harness.starts(2)
        let original = try XCTUnwrap(harness.model.mountedViewID)
        fixture.setVisible(false)
        XCTAssertFalse(fixture.runtime.transitionOverlays.isEmpty)
        fixture.setVisible(true)
        let replacement = try XCTUnwrap(harness.model.mountedViewID)
        XCTAssertNotEqual(
            original, replacement,
            "Reusing the authored template must not reuse its retired StateObject factory result.")
        try await harness.waitFor { $0.isActive }
        try await harness.finishCurrent([0, 1], data: png([255, 0, 0, 255]))
        try await harness.starts(4)
        fixture.advance(to: 20)
        XCTAssertTrue(fixture.runtime.transitionOverlays.isEmpty)
        XCTAssertEqual(harness.model.mountedViewID, replacement)
        XCTAssertTrue(harness.model.isActive)
        XCTAssertFalse(harness.model.requestedVisibleIDs.isEmpty)
        XCTAssertEqual(harness.model.preview.phase, .loading)
        XCTAssertFalse(harness.gate.snapshot.cancellations.contains(2))
        XCTAssertFalse(harness.gate.snapshot.cancellations.contains(3))
        try await harness.finishCurrent([2, 3], data: png([0, 0, 255, 255]))
        fixture.rebuild()
        XCTAssertEqual(Array(try image(harness.model.preview).pixelData), [255, 0, 0, 255])
        XCTAssertTrue(harness.model.isActive)
        XCTAssertEqual(harness.model.mountedViewID, replacement)
        XCTAssertNotNil(try fixture.node("media.browser.preview.ready"))
    }

    func testOrdinaryRebuildsKeepTheInstalledMountAndDoNotRestartReads() async throws {
        let harness = DemoMediaBrowserHarness()
        let fixture = DemoMediaBrowserFixture(model: harness.model)
        defer {
            fixture.close()
            harness.close()
        }
        try await harness.starts(2)
        let mounted = try XCTUnwrap(harness.model.mountedViewID)
        let page = harness.model.pageScope
        for _ in 0..<20 { fixture.rebuild() }
        XCTAssertEqual(harness.model.mountedViewID, mounted)
        XCTAssertEqual(harness.model.pageScope, page)
        XCTAssertEqual(harness.gate.snapshot.starts.count, 2)
        XCTAssertTrue(harness.gate.snapshot.cancellations.isEmpty)
        XCTAssertEqual(harness.model.activeReadCount, 2)
        XCTAssertEqual(harness.model.pendingThumbnailIDs.count, 4)
    }

    func testLightScaledNarrowCompositionKeepsTheSelectedDecodedImageWithinItsViewport() async throws {
        let harness = DemoMediaBrowserHarness(includesSamples: false)
        XCTAssertTrue(harness.model.dropFiles([fileURL("scaled")]))
        let fixture = DemoMediaBrowserFixture(model: harness.model, scheme: .light, scale: 1.25)
        defer {
            fixture.close()
            harness.close()
        }
        try await harness.starts(2)
        try await harness.finishCurrent([0, 1], data: MediaImageTestFixtures.bmp(width: 30, height: 20, gray: 47))
        fixture.rebuild()
        let selected = harness.model.selectedID
        let mounted = harness.model.mountedViewID
        fixture.resize(IntSize(width: 360, height: 720))
        try fixture.scroll(to: 10_000)
        fixture.rebuild()
        XCTAssertEqual(harness.model.selectedID, selected)
        XCTAssertEqual(harness.model.mountedViewID, mounted)
        XCTAssertEqual(harness.model.preview.phase, .ready)
        let preview = try fixture.node("media.browser.preview.ready")
        let bounds = fixture.bounds(of: preview)
        XCTAssertGreaterThan(bounds.size.width, 0)
        XCTAssertGreaterThan(bounds.size.height, 0)
        XCTAssertGreaterThanOrEqual(bounds.origin.x, 0)
        XCTAssertLessThanOrEqual(bounds.origin.x + bounds.size.width, 360)
        let bitmap = try XCTUnwrap(DemoMediaBrowserFixture.descendants(preview).compactMap(\.bitmapSurface).first)
        XCTAssertEqual(bitmap.width, 30)
        XCTAssertEqual(bitmap.height, 20)
        XCTAssertEqual(Array(bitmap.pixels.prefix(4)), [47, 47, 47, 255])
        XCTAssertEqual(harness.gate.snapshot.starts.count, 2)
    }

    func testGalleryRegistersTheWindowOwnedWorkflowWithoutChangingFilePreviewSearch() async throws {
        let harness = DemoMediaBrowserHarness()
        let dashboard = DemoDashboardModel()
        dashboard.galleryQuery = "media thumbnail"
        let window = DemoWindowState(mediaBrowser: harness.model)
        let fixture = DemoMediaBrowserFixture(model: harness.model, gallery: (dashboard, window))
        defer {
            fixture.close()
            window.fileBrowser.close()
            harness.close()
        }
        XCTAssertEqual(DemoGalleryCategory.collections.filter { $0.matches(query: "media thumbnail") }, [.controls])
        XCTAssertEqual(DemoGalleryCategory.collections.filter { $0.matches(query: "file preview") }, [.controls])
        XCTAssertTrue(window.mediaBrowser === harness.model)
        let offscreen = try fixture.node("media.browser")
        XCTAssertGreaterThanOrEqual(fixture.bounds(of: offscreen).origin.y, 680)
        XCTAssertGreaterThan(fixture.bounds(of: offscreen).size.height, 0)
        XCTAssertFalse(offscreen.hasAppeared)
        XCTAssertNil(harness.model.mountedViewID)
        XCTAssertFalse(harness.model.isClosed)
        XCTAssertTrue(harness.model.requestedVisibleIDs.isEmpty)
        XCTAssertTrue(harness.model.pendingThumbnailIDs.isEmpty)
        XCTAssertNil(harness.model.pendingPreviewID)
        XCTAssertNotNil(try fixture.node("file.browser"))
        XCTAssertTrue(harness.gate.snapshot.starts.isEmpty, "The media section begins outside the gallery clip.")
    }

    func testClosingTheModelBeforeThePublicViewTaskEntersNeverStartsARead() async throws {
        let harness = DemoMediaBrowserHarness()
        let fixture = DemoMediaBrowserFixture(model: harness.model)
        defer {
            fixture.close()
            harness.close()
        }
        harness.model.close()
        await harness.model.awaitServiceClose()
        fixture.rebuild()
        XCTAssertTrue(harness.model.isClosed)
        XCTAssertFalse(harness.model.isActive)
        XCTAssertNil(harness.model.mountedViewID)
        XCTAssertEqual(harness.model.activeReadCount, 0)
        XCTAssertTrue(harness.gate.snapshot.starts.isEmpty)
        XCTAssertTrue(fixture.bitmaps.isEmpty)
        let stats = await harness.service.statistics
        XCTAssertTrue(stats.isClosed)
        XCTAssertEqual(stats.activeWorkerCount, 0)
    }

    private func fileURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "media-browser-ui-\(name).png", isDirectory: false)
    }

    private func png(_ rgba: [UInt8]) -> Data {
        MediaImageTestFixtures.png(width: 1, height: 1, rgba: rgba)
    }

    private func image(_ state: DemoMediaBrowserLoadState) throws -> DemoMediaImage {
        guard case .ready(let image) = state else {
            XCTFail("Expected an actual decoded image, got \(state.phase)")
            throw DemoMediaBrowserWaitError.missingRead
        }
        return image
    }
}
