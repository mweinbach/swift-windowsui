import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsDemo
@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// These sources exercise the actual shared template. No test is a native
/// dialog, Explorer/OLE, Narrator, macOS or frame-time qualification.
@MainActor
final class DemoFileBrowserInteractionTests: XCTestCase {
    // XCTest invokes these synchronous class hooks before/after its cases.
    // They touch only the nonactor diagnostic observer, with no actor hop.
    nonisolated override class func setUp() {
        super.setUp()
        if let observer = FileBrowserConstructionTraceObserver.configured {
            XCTestObservationCenter.shared.addTestObserver(observer)
            observer.recordRegistered()
        }
    }

    nonisolated override class func tearDown() {
        if let observer = FileBrowserConstructionTraceObserver.configured {
            XCTestObservationCenter.shared.removeTestObserver(observer)
            observer.recordRemoved()
        }
        super.tearDown()
    }

    func testPublicTypedURLDropSelectsAFileAndDisplaysDecodedText() async throws {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service, includesSamples: false)
        let fixture = FileBrowserFixture(model: model)
        defer {
            fixture.close()
            model.close()
            gate.close()
        }
        let url = URL(fileURLWithPath: "C:/file-preview/notes.txt")

        XCTAssertTrue(fixture.runtime.performFileDrop([url], at: Point(x: 80, y: 220)))
        let started = await gate.waitForStarts(1)
        XCTAssertTrue(started)
        let work = try XCTUnwrap(model.activeReadTask)
        let text = "Actual UTF-8 bytes: café 👩🏽‍💻\nSecond line"
        try finish(gate, id: 0, text: text)
        await work.value
        fixture.rebuild()

        XCTAssertEqual(model.records.count, 1)
        XCTAssertEqual(model.selectedRecord?.name, "notes.txt")
        XCTAssertEqual(model.selectedRecord?.source, .file(url))
        XCTAssertTrue(fixture.texts.contains(text))
        XCTAssertTrue(fixture.texts.contains("\(text.utf8.count) UTF-8 bytes"))
        XCTAssertEqual(fixture.selectableRows.count, 1)
        XCTAssertTrue(try fixture.row(model.records[0].id).accessibilityTraits.contains(.isSelected))
    }

    func testTypedDropRejectsNonFileURLsWithoutStartingARead() async throws {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service, includesSamples: false)
        let fixture = FileBrowserFixture(model: model)
        defer {
            fixture.close()
            model.close()
            gate.close()
        }

        XCTAssertFalse(
            fixture.runtime.performFileDrop(
                [try XCTUnwrap(URL(string: "https://example.invalid/private.txt"))], at: Point(x: 80, y: 220)))
        fixture.rebuild()
        XCTAssertTrue(model.records.isEmpty)
        XCTAssertTrue(gate.snapshot.starts.isEmpty)
        XCTAssertEqual(model.activeReadCount, 0)
        XCTAssertNotNil(try fixture.node("file.browser.empty"))
        XCTAssertNotNil(model.importNotice)
    }

    func testPointerThenArrowSelectionKeepsOneRetainedFocusOwnerAfterRebuild() async throws {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service)
        let fixture = FileBrowserFixture(model: model, size: IntSize(width: 900, height: 560))
        defer {
            fixture.close()
            model.close()
            gate.close()
        }
        let started = await gate.waitForStarts(1)
        XCTAssertTrue(started)
        let firstWork = try XCTUnwrap(model.activeReadTask)
        XCTAssertEqual(fixture.selectableRows.count, model.records.count)
        for record in model.records {
            let row = try fixture.row(record.id)
            XCTAssertEqual(row.accessibilityLabel, "\(record.name), \(record.sourceDescription)")
            XCTAssertEqual(FileBrowserFixture.descendants(row).filter { $0.isFocusable }.count, 1)
            XCTAssertEqual(FileBrowserFixture.descendants(row).filter { $0.onActivate != nil }.count, 1)
        }

        let second = try fixture.row("sample:unicode")
        let frame = fixture.bounds(of: second)
        let point = Point(x: frame.origin.x + frame.size.width / 2, y: frame.origin.y + frame.size.height / 2)
        fixture.runtime.pointerDown(at: point)
        fixture.runtime.pointerUp(at: point)
        XCTAssertEqual(model.selectedID, "sample:unicode")
        fixture.rebuild()
        fixture.runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.downArrow.rawValue))

        XCTAssertEqual(model.selectedID, "sample:empty")
        XCTAssertTrue(try fixture.row("sample:empty").isFocused)
        XCTAssertEqual(model.pendingReadID, "sample:empty")
        XCTAssertEqual(gate.snapshot.starts.count, 1)
        try finish(gate, id: 0, text: "Discarded first preview")
        await firstWork.value
        let latestStarted = await gate.waitForStarts(2)
        XCTAssertTrue(latestStarted)
        let latestWork = try XCTUnwrap(model.activeReadTask)
        try finish(gate, id: 1, text: "")
        await latestWork.value
        fixture.rebuild()
        XCTAssertTrue(try fixture.row("sample:empty").isFocused)
        XCTAssertTrue(fixture.texts.contains("This file is empty."))
        XCTAssertFalse(fixture.texts.contains("Discarded first preview"))
    }

    func testCancelRetryFailureAndSuccessfulRetryUseRealButtonsAndDecode() async throws {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service)
        let fixture = FileBrowserFixture(model: model)
        defer {
            fixture.close()
            model.close()
            gate.close()
        }
        let started = await gate.waitForStarts(1)
        XCTAssertTrue(started)
        let firstWork = try XCTUnwrap(model.activeReadTask)
        fixture.rebuild()
        try fixture.activate("file.browser.cancel")
        fixture.rebuild()
        XCTAssertEqual(model.preview, .cancelled)
        XCTAssertTrue(fixture.texts.contains("Cancelling preview…"))
        try finish(gate, id: 0, text: "Must not appear")
        await firstWork.value
        fixture.rebuild()
        XCTAssertTrue(fixture.texts.contains("Preview cancelled"))
        XCTAssertFalse(fixture.texts.contains("Must not appear"))

        try fixture.activate("file.browser.retry")
        let retryStarted = await gate.waitForStarts(2)
        XCTAssertTrue(retryStarted)
        let failedWork = try XCTUnwrap(model.activeReadTask)
        try finish(gate, id: 1, result: .success(Data([0xC3, 0x28])))
        await failedWork.value
        fixture.rebuild()
        XCTAssertNotNil(try fixture.node("file.browser.preview.failure"))
        XCTAssertTrue(fixture.texts.contains("Preview unavailable"))

        try fixture.activate("file.browser.retry")
        let repairedStarted = await gate.waitForStarts(3)
        XCTAssertTrue(repairedStarted)
        let repairedWork = try XCTUnwrap(model.activeReadTask)
        try finish(gate, id: 2, text: "Repaired UTF-8 source")
        await repairedWork.value
        fixture.rebuild()
        XCTAssertTrue(fixture.texts.contains("Repaired UTF-8 source"))
        XCTAssertEqual(model.selectedID, "sample:welcome")
        XCTAssertEqual(gate.snapshot.maximumConcurrent, 1)
    }

    func testImporterUsesInjectedDialogAndOpaqueFailurePreservesThePreview() async throws {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service, includesSamples: false)
        let fixture = FileBrowserFixture(model: model)
        let provider = FileBrowserDialogProvider()
        let observation = DemoFileBrowserObservation(model)
        let previousProvider = FileDialogManager.provider
        FileDialogManager.provider = provider
        defer {
            FileDialogManager.provider = previousProvider
            observation.close()
            fixture.close()
            model.close()
            gate.close()
        }
        provider.urls = [
            URL(fileURLWithPath: "C:/file-preview/first.txt"),
            URL(fileURLWithPath: "C:/file-preview/second.txt"),
        ]
        let active = await observation.waitFor { $0.isActive }
        XCTAssertTrue(active)
        fixture.rebuild()

        try fixture.activate("file.browser.import")
        XCTAssertTrue(model.isImporterPresented)
        fixture.host.processPendingFileDialogs()
        XCTAssertEqual(provider.openRequests.count, 1)
        XCTAssertEqual(provider.openRequests.first?.extensions, ["txt"])
        XCTAssertEqual(provider.openRequests.first?.allowsMultipleSelection, true)
        XCTAssertEqual(model.records.map(\.name), ["first.txt", "second.txt"])
        XCTAssertFalse(model.isImporterPresented)
        let started = await gate.waitForStarts(1)
        XCTAssertTrue(started)
        let work = try XCTUnwrap(model.activeReadTask)
        try finish(gate, id: 0, text: "Existing preview")
        await work.value
        fixture.rebuild()
        let selectedID = model.selectedID
        let preview = model.preview

        provider.urls = []
        try fixture.activate("file.browser.import")
        fixture.host.processPendingFileDialogs()
        fixture.rebuild()
        XCTAssertEqual(provider.openRequests.count, 2)
        XCTAssertFalse(model.isImporterPresented)
        XCTAssertEqual(model.selectedID, selectedID)
        XCTAssertEqual(model.preview, preview)
        XCTAssertTrue(model.importNotice?.hasPrefix("Import was not completed:") == true)
        XCTAssertTrue(fixture.texts.contains("Existing preview"))
        XCTAssertEqual(gate.snapshot.starts.count, 1)
        XCTAssertEqual(provider.saveRequests, 0)
    }

    func testClearAndSamplesButtonsChangeTheActualCollection() async throws {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service)
        let fixture = FileBrowserFixture(model: model)
        defer {
            fixture.close()
            model.close()
            gate.close()
        }
        let started = await gate.waitForStarts(1)
        XCTAssertTrue(started)
        let firstWork = try XCTUnwrap(model.activeReadTask)

        try fixture.activate("file.browser.clear")
        fixture.rebuild()
        XCTAssertTrue(model.records.isEmpty)
        XCTAssertNil(model.selectedID)
        XCTAssertNotNil(try fixture.node("file.browser.empty"))
        try fixture.activate("file.browser.samples")
        XCTAssertEqual(model.records, DemoFileBrowserRecord.samples)
        try finish(gate, id: 0, text: "Discarded")
        await firstWork.value
        let restoredStarted = await gate.waitForStarts(2)
        XCTAssertTrue(restoredStarted)
        let restoredWork = try XCTUnwrap(model.activeReadTask)
        guard case .sample(let bytes) = model.records[0].source else { return XCTFail("expected built-in bytes") }
        try finish(gate, id: 1, result: .success(bytes))
        await restoredWork.value
        fixture.rebuild()
        XCTAssertTrue(fixture.texts.contains(String(decoding: bytes, as: UTF8.self)))
        XCTAssertEqual(fixture.selectableRows.count, 4)
    }

    func testRemoveButtonSelectsTheNextStableRecordAndDiscardsTheRemovedRead() async throws {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service)
        let fixture = FileBrowserFixture(model: model)
        defer {
            fixture.close()
            model.close()
            gate.close()
        }
        let registered = await gate.waitForRegistrations(1)
        XCTAssertTrue(registered)
        let removedRead = try XCTUnwrap(model.activeReadTask)

        try fixture.activate("file.browser.remove")
        fixture.rebuild()
        XCTAssertEqual(model.records.map(\.id), ["sample:unicode", "sample:empty", "sample:invalid"])
        XCTAssertEqual(model.selectedID, "sample:unicode")
        XCTAssertEqual(model.pendingReadID, "sample:unicode")
        XCTAssertTrue(gate.snapshot.cancellations.contains(0))
        XCTAssertEqual(model.activeReadCount, 1)
        XCTAssertFalse(fixture.nodes.contains { $0.accessibilityIdentifier == "file.browser.record.sample:welcome" })

        try finish(gate, id: 0, text: "Removed file must not reappear")
        await removedRead.value
        let replacementStarted = await gate.waitForStarts(2)
        XCTAssertTrue(replacementStarted)
        let replacementRead = try XCTUnwrap(model.activeReadTask)
        guard case .sample(let bytes) = DemoFileBrowserRecord.samples[1].source else {
            return XCTFail("expected the next record's actual Unicode sample bytes")
        }
        try finish(gate, id: 1, result: .success(bytes))
        await replacementRead.value
        fixture.rebuild()
        XCTAssertTrue(fixture.texts.contains(String(decoding: bytes, as: UTF8.self)))
        XCTAssertFalse(fixture.texts.contains("Removed file must not reappear"))
        XCTAssertEqual(fixture.selectableRows.count, 3)
        XCTAssertTrue(try fixture.row("sample:unicode").accessibilityTraits.contains(.isSelected))
        XCTAssertEqual(gate.snapshot.maximumConcurrent, 1)
    }

    func testDisappearanceCancelsAndRemountResumesWithoutAffectingAnotherWindow() async throws {
        let firstGate = DemoFilePreviewGate()
        let secondGate = DemoFilePreviewGate()
        let first = DemoFileBrowserModel(service: firstGate.service)
        let second = DemoFileBrowserModel(service: secondGate.service)
        let firstWindow = DemoWindowState(fileBrowser: first)
        let secondWindow = DemoWindowState(fileBrowser: second)
        let firstFixture = FileBrowserFixture(model: firstWindow.fileBrowser)
        let secondFixture = FileBrowserFixture(model: secondWindow.fileBrowser)
        defer {
            firstFixture.close()
            secondFixture.close()
            first.close()
            second.close()
            firstGate.close()
            secondGate.close()
        }
        let firstStarted = await firstGate.waitForStarts(1)
        let secondStarted = await secondGate.waitForStarts(1)
        XCTAssertTrue(firstStarted && secondStarted)
        XCTAssertFalse(firstWindow.fileBrowser === secondWindow.fileBrowser)
        let firstWork = try XCTUnwrap(first.activeReadTask)
        firstFixture.setVisible(false)
        let cancelled = await firstGate.waitForCancellation(of: 0)
        XCTAssertTrue(cancelled)
        XCTAssertTrue(secondGate.snapshot.cancellations.isEmpty)
        XCTAssertEqual(second.preview, .loading)
        try finish(firstGate, id: 0, text: "Hidden completion")
        await firstWork.value
        firstFixture.setVisible(true)
        let resumed = await firstGate.waitForStarts(2)
        XCTAssertTrue(resumed)
        XCTAssertEqual(first.selectedID, "sample:welcome")
        XCTAssertEqual(secondGate.snapshot.starts.count, 1)
        XCTAssertEqual(firstGate.snapshot.maximumConcurrent, 1)
    }

    func testRealTemporaryFileDropReadsBytesIntoTheActualPreview() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "swift-windowsui-file-preview-integration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Read me.txt")
        let bytes = Data("\u{FEFF}Local bytes\r\nUnicode: 日本語 👩🏽‍💻\n".utf8)
        try bytes.write(to: url)
        let model = DemoFileBrowserModel(includesSamples: false)
        let observation = DemoFileBrowserObservation(model)
        let fixture = FileBrowserFixture(model: model)
        defer {
            observation.close()
            fixture.close()
            model.close()
        }

        XCTAssertTrue(fixture.runtime.performFileDrop([url], at: Point(x: 80, y: 220)))
        let completed = await observation.waitFor {
            switch $0.preview {
            case .ready, .failed: true
            default: false
            }
        }
        XCTAssertTrue(completed)
        guard completed else { throw FileBrowserFixtureError.missingCompletion }
        XCTAssertEqual(
            model.preview,
            .ready(
                DemoFilePreview(
                    text: String(decoding: bytes, as: UTF8.self), byteCount: bytes.count)))
        fixture.rebuild()
        XCTAssertTrue(fixture.texts.contains(String(decoding: bytes, as: UTF8.self)))
        XCTAssertEqual(try Data(contentsOf: url), bytes, "preview must not write or normalize the source")
        XCTAssertEqual(model.selectedRecord?.name, "Read me.txt")
    }

    func testObservedCompletionRebuildsTheRealHostWithoutManualReload() async throws {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service)
        let size = IntSize(width: 900, height: 560)
        let surface = SurfaceDescriptor(
            windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
            pixelSize: size, scaleFactor: 1)
        let host = WinSwiftUIWindowHost(
            configuration: WindowGroupConfiguration(
                title: "File preview observation", size: size, clearColor: .black,
                content: [AnyView(DemoFileBrowserTemplate(model: model))]),
            renderer: FakeRenderBackend(), batchRenderer: nil,
            surfaceDescriptorProvider: { _ in surface })
        let window = Win32Window(title: "File preview observation", clientSize: size)
        host.windowDidCreate(window)
        defer {
            host.onReloadContentCompleted = nil
            host.windowWillClose(window)
            model.close()
            gate.close()
        }
        let started = await gate.waitForStarts(1)
        XCTAssertTrue(started)
        let expected = "Observed model completion reached the template"
        let reloaded = expectation(description: "file preview publication rebuilt the actual window host")
        host.onReloadContentCompleted = { [weak host] in
            guard let host,
                FileBrowserFixture.descendants(host.hostedRuntime.root).contains(where: { $0.text == expected })
            else { return }
            host.onReloadContentCompleted = nil
            reloaded.fulfill()
        }
        try finish(gate, id: 0, text: expected)
        await fulfillment(of: [reloaded], timeout: 5)
        XCTAssertTrue(FileBrowserFixture.descendants(host.hostedRuntime.root).contains { $0.text == expected })
    }

    func testPublicTemplateControlsFitNarrowAndWideAppearancesAndScales() async throws {
        for size in [IntSize(width: 320, height: 560), IntSize(width: 900, height: 560)] {
            for scheme in [ColorScheme.light, .dark] {
                for scale in [1.0, 1.5, 2.0] {
                    let gate = DemoFilePreviewGate()
                    let model = DemoFileBrowserModel(service: gate.service, includesSamples: false)
                    let fixture = FileBrowserFixture(model: model, size: size, scheme: scheme, scale: scale)
                    defer {
                        fixture.close()
                        model.close()
                        gate.close()
                    }
                    XCTAssertEqual(fixture.runtime.displayScale, scale)
                    for identifier in ["import", "samples", "clear", "remove", "retry", "cancel"] {
                        let node = try fixture.node("file.browser.\(identifier)")
                        let bounds = fixture.bounds(of: node)
                        XCTAssertGreaterThan(bounds.size.width, 0)
                        XCTAssertGreaterThan(bounds.size.height, 0)
                        XCTAssertGreaterThanOrEqual(bounds.origin.x, -0.01)
                        XCTAssertGreaterThanOrEqual(bounds.origin.y, -0.01)
                        XCTAssertLessThanOrEqual(bounds.origin.x + bounds.size.width, Double(size.width) + 0.01)
                        XCTAssertLessThanOrEqual(bounds.origin.y + bounds.size.height, Double(size.height) + 0.01)
                    }
                    XCTAssertLessThanOrEqual(fixture.nodes.count, 800)
                    XCTAssertTrue(
                        fixture.nodes.allSatisfy {
                            let frame = $0.resolvedFrame
                            return frame.origin.x.isFinite && frame.origin.y.isFinite
                                && frame.size.width.isFinite && frame.size.height.isFinite
                                && frame.size.width >= 0 && frame.size.height >= 0
                        })
                    XCTAssertTrue(gate.snapshot.starts.isEmpty)
                }
            }
        }
    }

    func testClosingTheActualHostCancelsItsReadWhileHostAndModelRemainRetained() async throws {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service)
        let size = IntSize(width: 900, height: 560)
        let surface = SurfaceDescriptor(
            windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
            pixelSize: size, scaleFactor: 1)
        let host = WinSwiftUIWindowHost(
            configuration: WindowGroupConfiguration(
                title: "File preview close", size: size, clearColor: .black,
                content: [AnyView(DemoFileBrowserTemplate(model: model))]),
            renderer: FakeRenderBackend(), batchRenderer: nil,
            surfaceDescriptorProvider: { _ in surface })
        let window = Win32Window(title: "File preview close", clientSize: size)
        host.windowDidCreate(window)
        defer {
            host.windowWillClose(window)
            model.close()
            gate.close()
        }
        let registered = await gate.waitForRegistrations(1)
        XCTAssertTrue(registered)
        let work = try XCTUnwrap(model.activeReadTask)

        host.windowWillClose(window)
        XCTAssertTrue(gate.snapshot.cancellations.contains(0), "teardown must synchronously relay cancellation")
        XCTAssertFalse(model.retryPreview(), "the cancelled view lease must refuse admission before queued cleanup")
        XCTAssertEqual(model.activeReadCount, 1, "cancellation does not release a still-blocked reader slot")
        try finish(gate, id: 0, text: "Late result after window close")
        await work.value
        XCTAssertEqual(gate.snapshot.starts.count, 1)
        XCTAssertEqual(model.activeReadCount, 0)
        if case .ready = model.preview { XCTFail("closed host must not admit a late preview") }
        withExtendedLifetime((host, window, model)) {}
    }

    func testActualHostCloseBeforeVisibilityEntryKeepsQueuedDropUnstartedInTheSameTurn() async throws {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service, includesSamples: false)
        let size = IntSize(width: 900, height: 560)
        let surface = SurfaceDescriptor(
            windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
            pixelSize: size, scaleFactor: 1)
        let host = WinSwiftUIWindowHost(
            configuration: WindowGroupConfiguration(
                title: "File preview pre-entry close", size: size, clearColor: .black,
                content: [AnyView(DemoFileBrowserTemplate(model: model))]),
            renderer: FakeRenderBackend(), batchRenderer: nil,
            surfaceDescriptorProvider: { _ in surface })
        let window = Win32Window(title: "File preview pre-entry close", clientSize: size)
        host.windowDidCreate(window)
        defer {
            host.windowWillClose(window)
            model.close()
            gate.close()
        }
        let url = try XCTUnwrap(URL(string: "file:///C:/Preview/queued-before-appearance.txt"))

        // Do not yield MainActor: the actual lifecycle task has been enqueued,
        // but no view session has attached. A drop may only prepare intent.
        XCTAssertTrue(host.hostedRuntime.performFileDrop([url], at: Point(x: 80, y: 220)))
        XCTAssertEqual(model.selectedRecord?.source, .file(url))
        XCTAssertEqual(model.preview, .idle)
        XCTAssertNil(model.activeReadTask)
        XCTAssertNil(model.pendingReadID)
        XCTAssertTrue(gate.snapshot.starts.isEmpty)
        host.windowWillClose(window)
        XCTAssertEqual(model.activeReadCount, 0)
        XCTAssertTrue(gate.snapshot.starts.isEmpty)

        // This is a same-turn admission witness, not an await of the runtime's
        // private task. Direct pre-cancelled-visibility tests await that model
        // entry, and the preceding host test covers an already-entered session.
        withExtendedLifetime((host, window, model)) {}
    }

    func testGallerySearchExposesTheWindowOwnedReusableBrowser() async throws {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service, includesSamples: false)
        let dashboard = DemoDashboardModel()
        dashboard.galleryQuery = "file preview"
        let windowState = DemoWindowState(fileBrowser: model)
        let gallery = DemoGalleryScreen(model: dashboard)
        XCTAssertEqual(gallery.visibleCategories, [.controls])
        let fixture = FileBrowserFixture(model: model, gallery: (dashboard, windowState))
        defer {
            fixture.close()
            model.close()
            gate.close()
        }
        XCTAssertNotNil(try fixture.node("file.browser"))
        XCTAssertTrue(fixture.texts.contains("Local file browser"))
        XCTAssertEqual(DemoGalleryCategory.collections, [.controls, .visuals, .presentations])
        XCTAssertTrue(gate.snapshot.starts.isEmpty)
    }

    private func finish(_ gate: DemoFilePreviewGate, id: Int, text: String) throws {
        try finish(gate, id: id, result: .success(Data(text.utf8)))
    }

    private func finish(_ gate: DemoFilePreviewGate, id: Int, result: Result<Data, Error>) throws {
        guard gate.finish(id, result: result) else {
            gate.close()
            XCTFail("missing gate read \(id); released every owned read before returning")
            throw FileBrowserFixtureError.missingRead
        }
    }
}

/// The immutable observer owns only the locked diagnostic writer. It stores no
/// case, current-case slot, runtime, fixture, or application callback.
private final class FileBrowserConstructionTraceObserver: XCTestObservation, Sendable {
    static let configured: FileBrowserConstructionTraceObserver? = {
        guard let writer = RetainedConstructionDiagnostics.writer else { return nil }
        return FileBrowserConstructionTraceObserver(writer: writer)
    }()

    private let writer: RetainedConstructionTraceWriter

    private init(writer: RetainedConstructionTraceWriter) { self.writer = writer }

    func recordRegistered() { writer.record("observer.registered") }
    func recordRemoved() { writer.record("observer.removed") }

    func testCaseWillStart(_ testCase: XCTestCase) {
        guard testCase is DemoFileBrowserInteractionTests else { return }
        writer.record("case.enter", caseID: UInt(bitPattern: ObjectIdentifier(testCase)), caseName: testCase.name)
    }

    func testCaseDidFinish(_ testCase: XCTestCase) {
        guard testCase is DemoFileBrowserInteractionTests else { return }
        // A callback exit is not a passing assertion or a successful body.
        writer.record("case.exit", caseID: UInt(bitPattern: ObjectIdentifier(testCase)), caseName: testCase.name)
    }
}

private enum FileBrowserFixtureError: Error { case missingRead, missingCompletion }

@MainActor
private final class FileBrowserVisibility {
    var isVisible = true
}

@MainActor
private final class FileBrowserFixture {
    let runtime: RetainedViewRuntime
    let host: ComponentHost
    private let coordinator: StateMountCoordinator
    private let visibility: FileBrowserVisibility

    init(
        model: DemoFileBrowserModel, size: IntSize = IntSize(width: 640, height: 560),
        scheme: ColorScheme = .dark, scale: Double = 1,
        gallery: (DemoDashboardModel, DemoWindowState)? = nil
    ) {
        let writer = RetainedConstructionDiagnostics.writer
        let fixtureSpan = writer?.record("fixture.init.enter")
        let visibility = FileBrowserVisibility()
        self.visibility = visibility
        let runtime = RetainedViewRuntime(root: ViewNode(), displayScale: scale)
        runtime.clock = { 1 }
        runtime.setRootSize(size)
        self.runtime = runtime
        let host = ComponentHost(runtime: runtime)
        self.host = host
        let coordinator = StateMountCoordinator(
            invalidate: { [weak host] in host?.reload() }, observeObject: { _ in },
            updateObservedObjects: { _, _, _ in })
        self.coordinator = coordinator
        host.buildLifecycle = coordinator
        let trace = runtime.constructionTrace
        trace?.record("fixture.runtime", span: fixtureSpan)
        let context = ViewBuildContext(
            stateMountCoordinator: coordinator,
            canvasSizeProvider: { Size(width: Double(size.width), height: Double(size.height)) },
            invalidateHandler: { [weak host] in host?.reload() },
            environmentValuesProvider: {
                EnvironmentValues(colorScheme: scheme, displayScale: scale, pixelLength: 1 / scale)
            })
        host.setComponents {
            guard visibility.isVisible else { return [makeViewComponent(Text("Hidden"), context: context)] }
            if let (dashboard, state) = gallery {
                return [
                    makeViewComponent(
                        DemoGalleryScreen(model: dashboard).environmentObject(state), context: context)
                ]
            }
            return [makeViewComponent(DemoFileBrowserTemplate(model: model), context: context)]
        }
        settle()
        trace?.record("fixture.init.returnBoundary", span: fixtureSpan)
    }

    var nodes: [ViewNode] { Self.descendants(runtime.root) }
    var texts: [String] { nodes.compactMap(\.text) }
    var selectableRows: [ViewNode] { nodes.filter { $0.accessibilityTraits.contains(.isSelectable) } }

    func rebuild() {
        let trace = runtime.constructionTrace
        let span = trace?.record("fixture.rebuild.enter")
        host.reload()
        settle()
        trace?.record("fixture.rebuild.returnBoundary", span: span)
    }
    func close() {
        let trace = runtime.constructionTrace
        let span = trace?.record("fixture.close.enter")
        coordinator.close()
        trace?.record("fixture.close.returnBoundary", span: span)
    }
    func setVisible(_ visible: Bool) {
        visibility.isVisible = visible
        rebuild()
    }

    func node(_ identifier: String) throws -> ViewNode {
        let matches = nodes.filter { $0.accessibilityIdentifier == identifier }
        XCTAssertEqual(matches.count, 1, "expected one node for \(identifier)")
        return try XCTUnwrap(matches.first)
    }

    func row(_ id: String) throws -> ViewNode {
        var candidate: ViewNode? = try node("file.browser.record.\(id)")
        while let node = candidate {
            if node.accessibilityTraits.contains(.isSelectable) { return node }
            candidate = node.parent
        }
        return try XCTUnwrap(nil as ViewNode?, "missing selectable owner")
    }

    func activate(_ identifier: String) throws {
        let trace = runtime.constructionTrace
        let span = trace?.record("fixture.activate.enter")
        defer { trace?.record("fixture.activate.returnBoundary", span: span) }
        let identified = try node(identifier)
        var candidate: ViewNode? = Self.descendants(identified).first { $0.onActivate != nil && $0.isFocusable }
        if candidate == nil {
            candidate = identified.parent
            while let node = candidate, node.onActivate == nil { candidate = node.parent }
        }
        let control = try XCTUnwrap(candidate, "missing enabled action for \(identifier)")
        runtime.requestFocus(control)
        runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.space.rawValue))
    }

    func bounds(of node: ViewNode) -> Rect {
        var frame = node.resolvedFrame
        var ancestor = node.parent
        while let parent = ancestor {
            frame.origin.x += parent.resolvedFrame.origin.x
            frame.origin.y += parent.resolvedFrame.origin.y
            if parent.scrollAxis == .vertical { frame.origin.y -= parent.scrollOffset }
            if parent.scrollAxis == .horizontal { frame.origin.x -= parent.scrollOffset }
            ancestor = parent.parent
        }
        return frame
    }

    private func settle() {
        let trace = runtime.constructionTrace
        let firstSpan = trace?.record("render.first.enter")
        _ = runtime.renderScene(at: 1)
        trace?.record("render.first.returned", span: firstSpan)
        let secondSpan = trace?.record("render.second.enter")
        _ = runtime.renderScene(at: 1)
        trace?.record("render.second.returned", span: secondSpan)
        XCTAssertNil(coordinator.latestInstallationError)
    }

    static func descendants(_ root: ViewNode) -> [ViewNode] {
        var result: [ViewNode] = []
        var pending = [root]
        while let node = pending.popLast() {
            result.append(node)
            pending.append(contentsOf: node.children.reversed())
        }
        return result
    }
}

@MainActor
private final class FileBrowserDialogProvider: FileDialogProvider {
    struct OpenRequest {
        let extensions: [String]?
        let allowsMultipleSelection: Bool
    }

    var urls: [URL] = []
    private(set) var openRequests: [OpenRequest] = []
    private(set) var saveRequests = 0

    func showOpenFileDialog(
        allowedExtensions: [String]?, allowsMultipleSelection: Bool,
        defaultDirectory: URL?, title: String?
    ) -> [URL] {
        openRequests.append(
            OpenRequest(extensions: allowedExtensions, allowsMultipleSelection: allowsMultipleSelection))
        return urls
    }

    func showSaveFileDialog(
        defaultFilename: String?, allowedExtensions: [String]?, defaultDirectory: URL?, title: String?
    ) -> URL? {
        saveRequests += 1
        return nil
    }
}
