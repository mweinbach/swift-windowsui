import Foundation
@preconcurrency import XCTest

@testable import SwiftWindowsDemo
@testable import WinSwiftUI

/// These tests inject byte readers. They never open a URL, create a window, or
/// use sleep/yield loops to infer that asynchronous work probably finished.
@MainActor
final class DemoFileBrowserModelTests: XCTestCase {
    func testInitialFourSamplesHaveStableIdentityAndConstructionDoesNotRead() async throws {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service)
        let empty = DemoFileBrowserModel(service: gate.service, includesSamples: false)
        defer {
            model.close()
            empty.close()
            gate.close()
        }

        let samples = DemoFileBrowserRecord.samples
        XCTAssertEqual(samples, DemoFileBrowserRecord.samples)
        XCTAssertEqual(model.records, samples)
        XCTAssertEqual(
            model.records.map(\.id), ["sample:welcome", "sample:unicode", "sample:empty", "sample:invalid"])
        XCTAssertEqual(
            model.records.map(\.name), ["Welcome.txt", "Unicode.txt", "Empty.txt", "Invalid UTF-8.txt"])
        XCTAssertTrue(model.records.allSatisfy { $0.sourceDescription == "Built-in sample" })
        XCTAssertEqual(model.selectedID, "sample:welcome")
        XCTAssertEqual(model.selectedRecord, model.records.first)
        XCTAssertEqual(model.preview, .idle)
        XCTAssertNil(model.importNotice)
        XCTAssertFalse(model.isImporterPresented)
        XCTAssertFalse(model.isReading)
        XCTAssertEqual(model.activeReadCount, 0)
        XCTAssertNil(model.activeReadTask)
        XCTAssertNil(model.pendingReadID)
        XCTAssertTrue(empty.records.isEmpty)
        XCTAssertNil(empty.selectedID)
        XCTAssertNil(empty.selectedRecord)
        XCTAssertEqual(empty.preview, .idle)
        XCTAssertTrue(gate.snapshot.starts.isEmpty)

        let unicode = try XCTUnwrap(model.records.first { $0.id == "sample:unicode" })
        XCTAssertEqual(unicode.source, .sample(Data("Café · cafe\u{301} · 日本語 · 👩🏽‍💻\r\nSecond line\n".utf8)))
        XCTAssertEqual(model.records[2].source, .sample(Data()))
        XCTAssertEqual(model.records[3].source, .sample(Data([0xC3, 0x28])))
    }

    func testLexicalAliasesDeduplicateWithoutReplacingTheOriginalSourceURL() async throws {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service, includesSamples: false)
        defer {
            model.close()
            gate.close()
        }
        let original = try XCTUnwrap(URL(string: "file://localhost/C:/Preview/./alpha.txt"))
        let canonical = try localURL("alpha.txt")
        let repeatedSeparator = try XCTUnwrap(URL(string: "file:///C:/Preview//alpha.txt"))
        let identity = "file:\(try DemoFilePreviewService.validateFileURL(original).absoluteString)"
        model.resume()

        XCTAssertTrue(model.importFiles([original, canonical, repeatedSeparator]))

        XCTAssertEqual(model.records.count, 1)
        XCTAssertEqual(model.records.first?.id, identity)
        XCTAssertEqual(model.records.first?.name, "alpha.txt")
        XCTAssertEqual(model.records.first?.source, .file(original))
        XCTAssertEqual(model.records.first?.sourceDescription, "Local file")
        XCTAssertEqual(model.selectedID, identity)
        XCTAssertEqual(model.preview, .loading)
        XCTAssertEqual(model.activeReadCount, 1)
        XCTAssertTrue(try XCTUnwrap(model.importNotice).contains("Skipped 2"))

        XCTAssertFalse(model.importFiles([canonical]))
        XCTAssertEqual(model.records.count, 1)
        XCTAssertEqual(model.selectedID, identity)
        try await assertStarts(1, gate: gate)
        XCTAssertEqual(gate.snapshot.starts.map(\.source), [.file(original)])
        XCTAssertTrue(gate.snapshot.cancellations.isEmpty)
    }

    func testUnsupportedURLsAreRejectedBeforeAnyReaderOrSelectionIsCreated() async throws {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service, includesSamples: false)
        defer {
            model.close()
            gate.close()
        }
        let spellings = [
            "https://example.invalid/A.txt",
            "data:text/plain,hello",
            "file://remote.invalid/C:/Preview/A.txt",
            "file://user:secret@localhost/C:/Preview/A.txt",
            "file:///C:/Preview/A.txt?download=1",
            "file:///C:/Preview/A.txt#fragment",
            "file:///C:/Preview/../A.txt",
            "file:///C:/Preview/%2E%2E/A.txt",
            "file:///C:/Preview/A%00.txt",
            "file:///C:/Preview/" + String(repeating: "a", count: DemoFilePreviewService.maximumFileURLBytes),
        ]
        var urls = try spellings.map { try XCTUnwrap(URL(string: $0)) }
        urls.append(try XCTUnwrap(URL(string: "relative.txt", relativeTo: localURL("base.txt"))))

        XCTAssertFalse(model.importFiles(urls))

        XCTAssertTrue(model.records.isEmpty)
        XCTAssertNil(model.selectedID)
        XCTAssertEqual(model.preview, .idle)
        XCTAssertEqual(model.activeReadCount, 0)
        XCTAssertNil(model.pendingReadID)
        XCTAssertTrue(try XCTUnwrap(model.importNotice).hasPrefix("No files were added."))
        XCTAssertTrue(gate.snapshot.starts.isEmpty)
    }

    func testAdmissionCapsBothRecordCountAndTheExaminedPrefixOfALargeDrop() async throws {
        let gate = DemoFilePreviewGate()
        let full = DemoFileBrowserModel(service: gate.service, includesSamples: false)
        let prefixed = DemoFileBrowserModel(service: gate.service, includesSamples: false)
        let withSamples = DemoFileBrowserModel(service: gate.service)
        defer {
            full.close()
            prefixed.close()
            withSamples.close()
            gate.close()
        }
        let files = try (0..<128).map { try localURL("item-\($0).txt") }
        XCTAssertEqual(DemoFileBrowserModel.maximumFileCount, 64)

        XCTAssertTrue(full.importFiles(files))
        XCTAssertEqual(full.records.count, 64)
        XCTAssertEqual(Set(full.records.map(\.id)).count, 64)
        XCTAssertEqual(full.records.last?.name, "item-63.txt")
        XCTAssertFalse(full.importFiles([try localURL("overflow.txt")]))
        XCTAssertEqual(full.records.count, 64)

        XCTAssertTrue(withSamples.importFiles(files))
        XCTAssertEqual(withSamples.records.count, 64)
        XCTAssertEqual(Array(withSamples.records.prefix(4)), DemoFileBrowserRecord.samples)
        XCTAssertEqual(withSamples.records.last?.name, "item-59.txt")

        let unsupported = try XCTUnwrap(URL(string: "https://example.invalid/not-a-file"))
        let hugeDrop = Array(repeating: unsupported, count: 4_096) + [try localURL("beyond-prefix.txt")]
        XCTAssertFalse(prefixed.importFiles(hugeDrop))
        XCTAssertTrue(prefixed.records.isEmpty)
        XCTAssertNil(prefixed.selectedID)
        XCTAssertEqual(prefixed.activeReadCount, 0)
        XCTAssertNil(prefixed.pendingReadID)
        // The late valid URL is deliberately not scanned to fill unused slots.
        XCTAssertFalse(prefixed.records.contains { $0.name == "beyond-prefix.txt" })
    }

    func testInvalidRepeatedAndRemovedSelectionIDsCannotStartARead() async {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service)
        defer {
            model.close()
            gate.close()
        }
        model.suspend()
        let before = model.snapshot

        XCTAssertFalse(model.select(id: "missing-record"))
        XCTAssertFalse(model.select(id: model.selectedID))
        XCTAssertEqual(model.snapshot, before)
        XCTAssertTrue(model.removeSelectedFile())
        XCTAssertEqual(model.selectedID, "sample:unicode")
        XCTAssertFalse(model.select(id: "sample:welcome"))
        XCTAssertEqual(model.selectedID, "sample:unicode")
        XCTAssertTrue(model.select(id: nil))
        XCTAssertNil(model.selectedRecord)
        XCTAssertEqual(model.preview, .idle)
        XCTAssertFalse(model.select(id: nil))
        XCTAssertFalse(model.retryPreview())
        XCTAssertFalse(model.cancelPreview())
        XCTAssertFalse(model.removeSelectedFile())
        XCTAssertEqual(model.activeReadCount, 0)
        XCTAssertTrue(gate.snapshot.starts.isEmpty)
    }

    func testRemoveClearAndRestoreKeepSelectionWithinTheCurrentRecords() async {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service)
        defer {
            model.close()
            gate.close()
        }
        model.suspend()
        XCTAssertTrue(model.select(id: "sample:empty"))
        XCTAssertTrue(model.removeSelectedFile())
        XCTAssertEqual(model.selectedID, "sample:invalid")
        XCTAssertTrue(model.removeSelectedFile())
        XCTAssertEqual(model.selectedID, "sample:unicode")
        XCTAssertEqual(model.records.map(\.id), ["sample:welcome", "sample:unicode"])

        model.clearFiles()

        XCTAssertTrue(model.records.isEmpty)
        XCTAssertNil(model.selectedID)
        XCTAssertNil(model.importNotice)
        XCTAssertFalse(model.isImporterPresented)
        XCTAssertEqual(model.preview, .idle)
        XCTAssertFalse(model.removeSelectedFile())

        model.restoreSamples()
        model.restoreSamples()

        XCTAssertEqual(model.records, DemoFileBrowserRecord.samples)
        XCTAssertEqual(model.selectedID, "sample:welcome")
        XCTAssertEqual(model.preview, .idle)
        XCTAssertEqual(model.activeReadCount, 0)
        XCTAssertNil(model.pendingReadID)
        XCTAssertEqual(model.importNotice, "Restored the four built-in samples. No files were changed.")
        XCTAssertTrue(gate.snapshot.starts.isEmpty)
    }

    func testImporterFailurePreservesReadyContentAndUsesANeutralNotice() async throws {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service)
        defer {
            model.close()
            gate.close()
        }
        model.resume()
        try await assertStarts(1, gate: gate)
        try await complete(0, text: "Existing preview", model: model, gate: gate)
        let records = model.records
        let selected = model.selectedID
        let preview = model.preview
        model.setImporterPresented(true)
        let error = NSError(
            domain: "DemoFileBrowserTests.Dialog", code: 7,
            userInfo: [NSLocalizedDescriptionKey: "The dialog did not return files."])

        model.receiveImportResult(.failure(error))

        XCTAssertFalse(model.isImporterPresented)
        XCTAssertEqual(model.records, records)
        XCTAssertEqual(model.selectedID, selected)
        XCTAssertEqual(model.preview, preview)
        XCTAssertEqual(model.importNotice, "Import was not completed: The dialog did not return files.")
        XCTAssertEqual(gate.snapshot.starts.count, 1)
        XCTAssertEqual(model.activeReadCount, 0)
    }

    func testEmptyImporterSuccessDoesNotClearExistingSelectionOrContent() async throws {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service)
        defer {
            model.close()
            gate.close()
        }
        model.resume()
        try await assertStarts(1, gate: gate)
        try await complete(0, text: "Retained preview", model: model, gate: gate)
        let before = model.snapshot
        model.setImporterPresented(true)

        model.receiveImportResult(.success([]))

        XCTAssertEqual(model.records, before.records)
        XCTAssertEqual(model.selectedID, before.selectedID)
        XCTAssertEqual(model.preview, before.preview)
        XCTAssertFalse(model.isImporterPresented)
        XCTAssertTrue(try XCTUnwrap(model.importNotice).hasPrefix("No files were added."))
        XCTAssertEqual(gate.snapshot.starts.count, 1)
    }

    func testRapidSelectionRetainsOnePhysicalReadAndOnlyTheLatestPendingRequest() async throws {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service)
        let observation = DemoFileBrowserObservation(model)
        defer {
            observation.close()
            model.close()
            gate.close()
        }
        model.resume()
        try await assertStarts(1, gate: gate)
        let firstTask = try XCTUnwrap(model.activeReadTask)

        XCTAssertTrue(model.select(id: "sample:unicode"))
        XCTAssertTrue(model.select(id: "sample:empty"))

        XCTAssertEqual(model.selectedID, "sample:empty")
        XCTAssertEqual(model.preview, .loading)
        XCTAssertEqual(model.activeReadCount, 1)
        XCTAssertEqual(model.pendingReadID, "sample:empty")
        XCTAssertTrue(model.isWaitingForPreviousRead)
        XCTAssertEqual(gate.snapshot.starts.count, 1)
        XCTAssertEqual(gate.snapshot.active, [0])
        XCTAssertEqual(gate.snapshot.maximumConcurrent, 1)
        try await assertCancellation(0, gate: gate)

        XCTAssertTrue(gate.succeed(0, text: "Stale A must never become visible"))
        try await assertTaskFinished(
            firstTask, model: model, gate: gate, description: "owned preview read")
        try await assertStarts(2, gate: gate)

        XCTAssertEqual(
            gate.snapshot.starts.map(\.source), [DemoFileBrowserRecord.samples[0].source, .sample(Data())])
        XCTAssertEqual(gate.snapshot.returns, [0])
        XCTAssertEqual(gate.snapshot.active, [1])
        XCTAssertEqual(gate.snapshot.maximumConcurrent, 1)
        XCTAssertEqual(model.selectedID, "sample:empty")
        XCTAssertEqual(model.preview, .loading)
        XCTAssertNil(model.pendingReadID)
        XCTAssertFalse(model.isWaitingForPreviousRead)

        try await complete(1, text: "Latest C", model: model, gate: gate)

        XCTAssertEqual(gate.snapshot.returns, [0, 1])
        XCTAssertTrue(gate.snapshot.active.isEmpty)
        XCTAssertFalse(observation.snapshots.contains { $0.preview == ready("Stale A must never become visible") })
        XCTAssertFalse(gate.snapshot.starts.contains { $0.source == DemoFileBrowserRecord.samples[1].source })
    }

    func testStaleFailureCannotOverwriteOrPreventTheLatestPendingSuccess() async throws {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service)
        let observation = DemoFileBrowserObservation(model)
        defer {
            observation.close()
            model.close()
            gate.close()
        }
        model.resume()
        try await assertStarts(1, gate: gate)
        let firstTask = try XCTUnwrap(model.activeReadTask)
        XCTAssertTrue(model.select(id: "sample:unicode"))
        XCTAssertTrue(gate.finish(0, result: .failure(DemoFileBrowserInjectedError.readFailed)))
        try await assertTaskFinished(
            firstTask, model: model, gate: gate, description: "owned preview read")
        try await assertStarts(2, gate: gate)

        XCTAssertEqual(model.selectedID, "sample:unicode")
        XCTAssertEqual(model.preview, .loading)
        XCTAssertEqual(gate.snapshot.maximumConcurrent, 1)
        try await complete(1, text: "Current Unicode source", model: model, gate: gate)
        XCTAssertFalse(observation.snapshots.contains { $0.preview == .failed("Injected preview failure.") })
    }

    func testCancelBeforeTheWorkerRegistersPreventsTheInjectedReaderFromStarting() async throws {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service)
        defer {
            model.close()
            gate.close()
        }
        // No suspension occurs between scheduling and cancelling this MainActor
        // task, so the service's entry cancellation check runs before the gate.
        model.resume()
        let task = try XCTUnwrap(model.activeReadTask)
        XCTAssertTrue(model.cancelPreview())
        XCTAssertEqual(model.activeReadCount, 1)
        XCTAssertEqual(model.preview, .cancelled)

        try await assertTaskFinished(
            task, model: model, gate: gate, description: "owned preview read")
        model.resume()
        model.resume()

        XCTAssertTrue(gate.snapshot.starts.isEmpty)
        XCTAssertEqual(model.activeReadCount, 0)
        XCTAssertNil(model.pendingReadID)
        XCTAssertEqual(model.preview, .cancelled)
        XCTAssertFalse(model.cancelPreview())
    }

    func testCancellationBeforeDataContinuationRegistrationDoesNotReleaseTheReadSlot() async throws {
        let gate = DemoFilePreviewGate(holdsRegistrations: true)
        let model = DemoFileBrowserModel(service: gate.service)
        defer {
            model.close()
            gate.close()
        }
        model.resume()
        try await assertStarts(1, gate: gate)
        let task = try XCTUnwrap(model.activeReadTask)
        XCTAssertTrue(gate.snapshot.registrations.isEmpty)

        XCTAssertTrue(model.cancelPreview())
        try await assertCancellation(0, gate: gate)

        XCTAssertEqual(model.preview, .cancelled)
        XCTAssertEqual(model.activeReadCount, 1)
        XCTAssertEqual(gate.snapshot.active, [0])
        XCTAssertTrue(gate.snapshot.returns.isEmpty)
        gate.allowRegistration(0)
        try await assertRegistrations(1, gate: gate)
        XCTAssertEqual(Array(gate.snapshot.events.prefix(3)), [.started(0), .cancelled(0), .registered(0)])
        XCTAssertEqual(model.activeReadCount, 1)
        XCTAssertTrue(gate.succeed(0, text: "Too late"))

        try await assertTaskFinished(
            task, model: model, gate: gate, description: "owned preview read")

        XCTAssertEqual(model.preview, .cancelled)
        XCTAssertEqual(model.activeReadCount, 0)
        XCTAssertEqual(gate.snapshot.returns, [0])
        XCTAssertEqual(gate.snapshot.maximumConcurrent, 1)
    }

    func testRepeatedResumeDoesNotCancelAnActiveReadOrReloadReadyContent() async throws {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service)
        defer {
            model.close()
            gate.close()
        }
        model.resume()
        try await assertStarts(1, gate: gate)
        model.resume()
        model.resume()

        XCTAssertEqual(model.activeReadCount, 1)
        XCTAssertNil(model.pendingReadID)
        XCTAssertTrue(gate.snapshot.cancellations.isEmpty)
        try await complete(0, text: "One successful read", model: model, gate: gate)
        let before = model.snapshot
        model.resume()
        model.resume()

        XCTAssertEqual(model.snapshot, before)
        XCTAssertEqual(model.activeReadCount, 0)
        XCTAssertEqual(gate.snapshot.starts.count, 1)
        XCTAssertTrue(gate.snapshot.cancellations.isEmpty)
    }

    func testFailureRequiresExplicitRetryAndRetryReadsTheSameSourceAgain() async throws {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service)
        defer {
            model.close()
            gate.close()
        }
        model.resume()
        try await assertStarts(1, gate: gate)
        let task = try XCTUnwrap(model.activeReadTask)
        XCTAssertTrue(gate.finish(0, result: .failure(DemoFileBrowserInjectedError.readFailed)))
        try await assertTaskFinished(
            task, model: model, gate: gate, description: "owned preview read")

        XCTAssertEqual(model.preview, .failed("Injected preview failure."))
        XCTAssertEqual(model.activeReadCount, 0)
        XCTAssertFalse(model.cancelPreview())
        model.resume()
        model.suspend()
        model.resume()
        XCTAssertEqual(model.preview, .failed("Injected preview failure."))
        XCTAssertEqual(gate.snapshot.starts.count, 1)
        XCTAssertEqual(model.activeReadCount, 0)

        XCTAssertTrue(model.retryPreview())
        XCTAssertEqual(model.preview, .loading)
        try await assertStarts(2, gate: gate)
        XCTAssertEqual(gate.snapshot.starts[0].source, gate.snapshot.starts[1].source)
        try await complete(1, text: "Repaired file bytes", model: model, gate: gate)
        XCTAssertEqual(model.selectedID, "sample:welcome")
        XCTAssertEqual(gate.snapshot.maximumConcurrent, 1)
    }

    func testExplicitCancelKeepsPhysicalReadAliveAndOnlyRetryCanQueueAReplacement() async throws {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service)
        defer {
            model.close()
            gate.close()
        }
        model.resume()
        try await assertStarts(1, gate: gate)
        let firstTask = try XCTUnwrap(model.activeReadTask)
        XCTAssertTrue(model.cancelPreview())
        try await assertCancellation(0, gate: gate)
        model.resume()
        model.suspend()
        model.resume()

        XCTAssertEqual(model.preview, .cancelled)
        XCTAssertEqual(model.activeReadCount, 1)
        XCTAssertNil(model.pendingReadID)
        XCTAssertEqual(gate.snapshot.starts.count, 1)
        XCTAssertTrue(gate.snapshot.returns.isEmpty)

        XCTAssertTrue(model.retryPreview())
        XCTAssertEqual(model.preview, .loading)
        XCTAssertEqual(model.pendingReadID, "sample:welcome")
        XCTAssertEqual(model.activeReadCount, 1)
        XCTAssertTrue(gate.succeed(0, text: "Cancelled read"))
        try await assertTaskFinished(
            firstTask, model: model, gate: gate, description: "owned preview read")
        try await assertStarts(2, gate: gate)
        try await complete(1, text: "Explicit retry", model: model, gate: gate)
        XCTAssertEqual(gate.snapshot.maximumConcurrent, 1)
    }

    func testSuspendResumeRetainsTheOldReadSlotAndResumesOnlyTheCurrentSelection() async throws {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service)
        defer {
            model.close()
            gate.close()
        }
        model.resume()
        try await assertStarts(1, gate: gate)
        let firstTask = try XCTUnwrap(model.activeReadTask)
        XCTAssertTrue(model.select(id: "sample:unicode"))
        model.setImporterPresented(true)
        model.suspend()

        XCTAssertEqual(model.preview, .cancelled)
        XCTAssertFalse(model.isImporterPresented)
        XCTAssertNil(model.pendingReadID)
        XCTAssertEqual(model.activeReadCount, 1)
        model.resume()

        XCTAssertEqual(model.preview, .loading)
        XCTAssertEqual(model.pendingReadID, "sample:unicode")
        XCTAssertEqual(gate.snapshot.starts.count, 1)
        XCTAssertTrue(gate.succeed(0, text: "Old appearance"))
        try await assertTaskFinished(
            firstTask, model: model, gate: gate, description: "owned preview read")
        try await assertStarts(2, gate: gate)
        XCTAssertEqual(gate.snapshot.starts[1].source, DemoFileBrowserRecord.samples[1].source)
        try await complete(1, text: "Resumed selection", model: model, gate: gate)
        XCTAssertEqual(gate.snapshot.maximumConcurrent, 1)
    }

    func testSelectionsMadeWhileSuspendedWaitForResumeAndCoalesceToTheLatestID() async throws {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service)
        defer {
            model.close()
            gate.close()
        }
        model.suspend()
        XCTAssertTrue(model.select(id: "sample:unicode"))
        XCTAssertTrue(model.select(id: "sample:empty"))
        model.setImporterPresented(true)

        XCTAssertEqual(model.preview, .idle)
        XCTAssertFalse(model.isImporterPresented)
        XCTAssertEqual(model.activeReadCount, 0)
        XCTAssertNil(model.pendingReadID)
        XCTAssertTrue(gate.snapshot.starts.isEmpty)

        model.resume()
        try await assertStarts(1, gate: gate)
        XCTAssertEqual(gate.snapshot.starts[0].source, .sample(Data()))
        try await complete(0, text: "", model: model, gate: gate)
        XCTAssertEqual(model.preview, .ready(DemoFilePreview(text: "", byteCount: 0)))
    }

    func testCancelClearsDeferredResumeIntentBeforeAnyReaderStarts() async {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service)
        defer {
            model.close()
            gate.close()
        }
        model.suspend()
        XCTAssertTrue(model.cancelPreview())
        model.resume()
        XCTAssertEqual(model.preview, .cancelled)
        XCTAssertEqual(model.activeReadCount, 0)
        XCTAssertTrue(gate.snapshot.starts.isEmpty)

        model.suspend()
        XCTAssertTrue(model.retryPreview())
        XCTAssertEqual(model.preview, .idle)
        XCTAssertTrue(model.cancelPreview())
        XCTAssertFalse(model.cancelPreview())
        model.resume()

        XCTAssertEqual(model.preview, .cancelled)
        XCTAssertEqual(model.activeReadCount, 0)
        XCTAssertNil(model.pendingReadID)
        XCTAssertTrue(gate.snapshot.starts.isEmpty)
    }

    func testCancelAfterSuspendingAnActiveReadPreventsAutomaticResume() async throws {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service)
        defer {
            model.close()
            gate.close()
        }
        model.resume()
        try await assertStarts(1, gate: gate)
        let task = try XCTUnwrap(model.activeReadTask)
        model.suspend()
        XCTAssertTrue(model.cancelPreview())
        model.resume()

        XCTAssertEqual(model.preview, .cancelled)
        XCTAssertNil(model.pendingReadID)
        XCTAssertTrue(gate.succeed(0, text: "Suspended old read"))
        try await assertTaskFinished(
            task, model: model, gate: gate, description: "owned preview read")
        model.resume()

        XCTAssertEqual(model.preview, .cancelled)
        XCTAssertEqual(model.activeReadCount, 0)
        XCTAssertEqual(gate.snapshot.starts.count, 1)
    }

    func testReadyContentSurvivesSuspensionWithoutAnAutomaticReload() async throws {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service)
        defer {
            model.close()
            gate.close()
        }
        model.resume()
        try await assertStarts(1, gate: gate)
        try await complete(0, text: "Keep this preview", model: model, gate: gate)
        let before = model.snapshot

        model.suspend()
        model.resume()

        XCTAssertEqual(model.snapshot, before)
        XCTAssertEqual(model.activeReadCount, 0)
        XCTAssertEqual(gate.snapshot.starts.count, 1)
    }

    func testTerminalCloseRejectsEveryLaterActionAndDrainsWithoutPublishingOldContent() async throws {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service)
        let observation = DemoFileBrowserObservation(model)
        defer {
            observation.close()
            model.close()
            gate.close()
        }
        model.resume()
        try await assertStarts(1, gate: gate)
        let task = try XCTUnwrap(model.activeReadTask)
        XCTAssertTrue(model.select(id: "sample:unicode"))
        model.close()
        let closed = model.snapshot
        let notifications = observation.snapshots.count

        XCTAssertTrue(model.isClosed)
        XCTAssertEqual(model.preview, .cancelled)
        XCTAssertEqual(model.activeReadCount, 1)
        XCTAssertNil(model.pendingReadID)
        XCTAssertFalse(model.select(id: "sample:empty"))
        XCTAssertFalse(model.select(id: nil))
        XCTAssertFalse(model.retryPreview())
        XCTAssertFalse(model.cancelPreview())
        XCTAssertFalse(model.removeSelectedFile())
        XCTAssertFalse(model.importFiles([try localURL("closed.txt")]))
        model.receiveImportResult(.success([try localURL("late-dialog.txt")]))
        model.receiveImportResult(.failure(DemoFileBrowserInjectedError.readFailed))
        model.setImporterPresented(true)
        model.clearFiles()
        model.restoreSamples()
        model.resume()
        model.suspend()
        model.close()

        XCTAssertEqual(model.snapshot, closed)
        XCTAssertEqual(observation.snapshots.count, notifications)
        XCTAssertTrue(gate.succeed(0, text: "Must not publish after close"))
        // Await the actual owned worker, not just the gate's earlier return.
        try await assertTaskFinished(
            task, model: model, gate: gate, description: "owned preview read")

        XCTAssertEqual(model.activeReadCount, 0)
        XCTAssertNil(model.pendingReadID)
        XCTAssertEqual(model.snapshot, closed)
        XCTAssertEqual(observation.snapshots.count, notifications)
        XCTAssertEqual(gate.snapshot.starts.count, 1)
        XCTAssertEqual(gate.snapshot.returns, [0])
    }

    func testDeinitializationCancelsWithoutAWorkerToModelRetainCycle() async throws {
        let gate = DemoFilePreviewGate()
        var model: DemoFileBrowserModel? = DemoFileBrowserModel(service: gate.service)
        weak var weakModel = model
        defer {
            model?.close()
            gate.close()
        }
        model?.resume()
        try await assertStarts(1, gate: gate)
        let task = try XCTUnwrap(model?.activeReadTask)

        model = nil

        XCTAssertNil(weakModel, "The suspended worker must not hold its model across the byte read")
        try await assertCancellation(0, gate: gate)
        XCTAssertEqual(gate.snapshot.active, [0])
        XCTAssertTrue(gate.succeed(0, text: "Owner no longer exists"))
        try await assertTaskFinished(
            task, model: model, gate: gate, description: "owned preview read")
        XCTAssertNil(weakModel)
        XCTAssertEqual(gate.snapshot.returns, [0])
        XCTAssertTrue(gate.snapshot.active.isEmpty)
    }

    func testSeparateWindowModelsKeepSelectionReadAndCancellationOwnershipIndependent() async throws {
        let firstGate = DemoFilePreviewGate()
        let secondGate = DemoFilePreviewGate()
        let first = DemoFileBrowserModel(service: firstGate.service)
        let second = DemoFileBrowserModel(service: secondGate.service)
        defer {
            first.close()
            second.close()
            firstGate.close()
            secondGate.close()
        }
        first.resume()
        second.resume()
        try await assertStarts(1, gate: firstGate)
        try await assertStarts(1, gate: secondGate)
        XCTAssertTrue(first.select(id: "sample:unicode"))
        let firstTask = try XCTUnwrap(first.activeReadTask)

        first.close()
        try await complete(0, text: "Second window content", model: second, gate: secondGate)

        XCTAssertEqual(second.selectedID, "sample:welcome")
        XCTAssertFalse(second.isClosed)
        XCTAssertTrue(secondGate.snapshot.cancellations.isEmpty)
        XCTAssertEqual(first.selectedID, "sample:unicode")
        XCTAssertEqual(first.preview, .cancelled)
        XCTAssertTrue(firstGate.succeed(0, text: "Closed first window"))
        try await assertTaskFinished(
            firstTask, model: first, gate: firstGate, description: "owned preview read")
        XCTAssertEqual(firstGate.snapshot.starts.count, 1)
        XCTAssertEqual(firstGate.snapshot.maximumConcurrent, 1)
        XCTAssertEqual(secondGate.snapshot.maximumConcurrent, 1)
        assertReady(second, text: "Second window content")
    }

    func testNotificationSeesCommittedSelectionAndCannotRollBackAReentrantSelection() async throws {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service)
        model.resume()
        var observed: [DemoFileBrowserSnapshot] = []
        var reentered = false
        let subscription = model.objectWillChange.sink { _ in
            observed.append(model.snapshot)
            if !reentered, model.selectedID == "sample:unicode" {
                reentered = true
                XCTAssertTrue(model.select(id: "sample:empty"))
            }
        }
        defer {
            subscription.cancel()
            model.close()
            gate.close()
        }

        XCTAssertTrue(model.select(id: "sample:unicode"))
        let supersededTask = try XCTUnwrap(model.activeReadTask)

        XCTAssertTrue(reentered)
        XCTAssertEqual(Array(observed.prefix(2)).map(\.selectedID), ["sample:unicode", "sample:empty"])
        XCTAssertTrue(observed.prefix(2).allSatisfy { $0.preview == .loading })
        XCTAssertEqual(model.selectedID, "sample:empty")
        XCTAssertEqual(model.pendingReadID, "sample:empty")
        try await assertTaskFinished(
            supersededTask, model: model, gate: gate, description: "owned preview read")
        try await assertStarts(1, gate: gate)

        XCTAssertEqual(gate.snapshot.starts.map(\.source), [.sample(Data())])
        try await complete(0, text: "Nested selection won", model: model, gate: gate)
        XCTAssertEqual(model.selectedID, "sample:empty")
    }

    func testNotificationReentryCanClearFilesWithoutAnOuterSelectionRestoringThem() async throws {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service)
        model.resume()
        var reentered = false
        var observed: [DemoFileBrowserSnapshot] = []
        let subscription = model.objectWillChange.sink { _ in
            observed.append(model.snapshot)
            if !reentered, model.preview == .loading {
                reentered = true
                model.clearFiles()
            }
        }
        defer {
            subscription.cancel()
            model.close()
            gate.close()
        }

        XCTAssertTrue(model.select(id: "sample:unicode"))
        let cancelledTask = try XCTUnwrap(model.activeReadTask)
        try await assertTaskFinished(
            cancelledTask, model: model, gate: gate, description: "owned preview read")

        XCTAssertTrue(reentered)
        XCTAssertEqual(observed.first?.selectedID, "sample:unicode")
        XCTAssertTrue(observed.dropFirst().allSatisfy { $0.records.isEmpty && $0.selectedID == nil })
        XCTAssertTrue(model.records.isEmpty)
        XCTAssertNil(model.selectedID)
        XCTAssertEqual(model.preview, .idle)
        XCTAssertEqual(model.activeReadCount, 0)
        XCTAssertNil(model.pendingReadID)
        XCTAssertTrue(gate.snapshot.starts.isEmpty)
    }

    func testNotificationReentryCanCloseWithoutStartingTheScheduledReader() async throws {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service)
        var reentered = false
        var notifications = 0
        let subscription = model.objectWillChange.sink { _ in
            notifications += 1
            if !reentered, model.preview == .loading {
                reentered = true
                model.close()
            }
        }
        defer {
            subscription.cancel()
            model.close()
            gate.close()
        }

        model.resume()
        let cancelledTask = try XCTUnwrap(model.activeReadTask)
        let closed = model.snapshot
        let notificationsAtClose = notifications
        try await assertTaskFinished(
            cancelledTask, model: model, gate: gate, description: "owned preview read")

        XCTAssertTrue(reentered)
        XCTAssertTrue(model.isClosed)
        XCTAssertEqual(model.preview, .cancelled)
        XCTAssertEqual(model.snapshot, closed)
        XCTAssertEqual(notifications, notificationsAtClose)
        XCTAssertEqual(model.activeReadCount, 0)
        XCTAssertTrue(gate.snapshot.starts.isEmpty)
    }

    func testSynchronousCancellationReentryKeepsTheNestedLatestSelection() async throws {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service)
        let probe = DemoFileBrowserReentryProbe()
        defer {
            gate.setCancellationHook(nil)
            model.close()
            gate.close()
        }
        model.resume()
        try await assertStarts(1, gate: gate)
        try await assertRegistrations(1, gate: gate)
        let firstTask = try XCTUnwrap(model.activeReadTask)
        // The handler is already installed. This test invokes its cancellation
        // synchronously from MainActor, and disarms it before any teardown.
        gate.setCancellationHook { id in
            MainActor.assumeIsolated {
                XCTAssertEqual(id, 0)
                probe.calls += 1
                probe.accepted = model.select(id: "sample:empty")
            }
        }

        XCTAssertTrue(model.select(id: "sample:unicode"))
        gate.setCancellationHook(nil)

        XCTAssertEqual(probe.calls, 1)
        XCTAssertTrue(probe.accepted)
        XCTAssertEqual(model.selectedID, "sample:empty")
        XCTAssertEqual(model.pendingReadID, "sample:empty")
        XCTAssertEqual(model.preview, .loading)
        XCTAssertEqual(model.activeReadCount, 1)
        XCTAssertTrue(gate.succeed(0, text: "Superseded A"))
        try await assertTaskFinished(
            firstTask, model: model, gate: gate, description: "owned preview read")
        try await assertStarts(2, gate: gate)
        XCTAssertEqual(gate.snapshot.starts[1].source, .sample(Data()))
        XCTAssertFalse(gate.snapshot.starts.contains { $0.source == DemoFileBrowserRecord.samples[1].source })
        try await complete(1, text: "Nested cancellation selection", model: model, gate: gate)
        XCTAssertEqual(gate.snapshot.maximumConcurrent, 1)
    }

    func testSynchronousCancellationReentryCanClearThePendingSelection() async throws {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service)
        let probe = DemoFileBrowserReentryProbe()
        defer {
            gate.setCancellationHook(nil)
            model.close()
            gate.close()
        }
        model.resume()
        try await assertStarts(1, gate: gate)
        try await assertRegistrations(1, gate: gate)
        let task = try XCTUnwrap(model.activeReadTask)
        gate.setCancellationHook { _ in
            MainActor.assumeIsolated {
                probe.calls += 1
                model.clearFiles()
            }
        }

        XCTAssertTrue(model.select(id: "sample:unicode"))
        gate.setCancellationHook(nil)

        XCTAssertEqual(probe.calls, 1)
        XCTAssertTrue(model.records.isEmpty)
        XCTAssertNil(model.selectedID)
        XCTAssertNil(model.pendingReadID)
        XCTAssertEqual(model.preview, .idle)
        XCTAssertEqual(model.activeReadCount, 1)
        XCTAssertTrue(gate.succeed(0, text: "Cleared owner"))
        try await assertTaskFinished(
            task, model: model, gate: gate, description: "owned preview read")
        XCTAssertEqual(model.activeReadCount, 0)
        XCTAssertEqual(gate.snapshot.starts.count, 1)
        XCTAssertEqual(model.preview, .idle)
    }

    func testCancelCommitsItsAuthorityBeforeACancellationHandlerStartsAnotherSelection() async throws {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service)
        let probe = DemoFileBrowserReentryProbe()
        defer {
            gate.setCancellationHook(nil)
            model.close()
            gate.close()
        }
        model.resume()
        try await assertStarts(1, gate: gate)
        try await assertRegistrations(1, gate: gate)
        let task = try XCTUnwrap(model.activeReadTask)
        gate.setCancellationHook { _ in
            MainActor.assumeIsolated {
                probe.calls += 1
                probe.accepted = model.select(id: "sample:unicode")
            }
        }

        XCTAssertTrue(model.cancelPreview())
        gate.setCancellationHook(nil)

        XCTAssertEqual(probe.calls, 1)
        XCTAssertTrue(probe.accepted)
        XCTAssertEqual(model.selectedID, "sample:unicode")
        XCTAssertEqual(model.preview, .loading)
        XCTAssertEqual(model.pendingReadID, "sample:unicode")
        XCTAssertTrue(gate.succeed(0, text: "Cancelled outer request"))
        try await assertTaskFinished(
            task, model: model, gate: gate, description: "owned preview read")
        try await assertStarts(2, gate: gate)
        try await complete(1, text: "Handler chose this", model: model, gate: gate)
        XCTAssertEqual(gate.snapshot.maximumConcurrent, 1)
    }

    func testClosedAndSuspendedImportCallbacksDoNotEvenEvaluateAnErrorFormatter() async {
        let gate = DemoFilePreviewGate()
        let closed = DemoFileBrowserModel(service: gate.service)
        let suspended = DemoFileBrowserModel(service: gate.service)
        let probe = DemoFileBrowserReentryProbe()
        defer {
            closed.close()
            suspended.close()
            gate.close()
        }
        closed.close()
        suspended.suspend()
        let closedSnapshot = closed.snapshot
        let suspendedSnapshot = suspended.snapshot
        let error = DemoFileBrowserReentrantError { probe.calls += 1 }

        closed.receiveImportResult(.failure(error))
        suspended.receiveImportResult(.failure(error))

        XCTAssertEqual(probe.calls, 0)
        XCTAssertEqual(closed.snapshot, closedSnapshot)
        XCTAssertEqual(suspended.snapshot, suspendedSnapshot)
        XCTAssertTrue(gate.snapshot.starts.isEmpty)
    }

    func testImporterErrorFormattingCannotOverwriteAReentrantSelection() async {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service)
        let probe = DemoFileBrowserReentryProbe()
        defer {
            model.close()
            gate.close()
        }
        model.resume()
        model.setImporterPresented(true)
        let error = DemoFileBrowserReentrantError {
            probe.calls += 1
            if probe.calls == 1 { probe.accepted = model.select(id: "sample:unicode") }
        }

        model.receiveImportResult(.failure(error))

        XCTAssertGreaterThanOrEqual(probe.calls, 1)
        XCTAssertTrue(probe.accepted)
        XCTAssertEqual(model.selectedID, "sample:unicode")
        XCTAssertEqual(model.preview, .loading)
        XCTAssertTrue(model.isImporterPresented)
        XCTAssertNil(model.importNotice)
        XCTAssertEqual(model.activeReadCount, 1)
    }

    func testImporterErrorFormattingCannotReplaceRestoredSampleStateWithAnOldNotice() async {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service, includesSamples: false)
        let probe = DemoFileBrowserReentryProbe()
        defer {
            model.close()
            gate.close()
        }
        model.resume()
        model.setImporterPresented(true)
        let error = DemoFileBrowserReentrantError {
            probe.calls += 1
            if probe.calls == 1 { model.restoreSamples() }
        }

        model.receiveImportResult(.failure(error))

        XCTAssertGreaterThanOrEqual(probe.calls, 1)
        XCTAssertEqual(model.records, DemoFileBrowserRecord.samples)
        XCTAssertEqual(model.selectedID, "sample:welcome")
        XCTAssertEqual(model.preview, .loading)
        XCTAssertEqual(model.importNotice, "Restored the four built-in samples. No files were changed.")
        XCTAssertFalse(model.isImporterPresented)
    }

    func testImporterErrorFormattingCannotDismissANewImporterPresentation() async {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service, includesSamples: false)
        let probe = DemoFileBrowserReentryProbe()
        defer {
            model.close()
            gate.close()
        }
        model.resume()
        model.setImporterPresented(true)
        let error = DemoFileBrowserReentrantError {
            probe.calls += 1
            if probe.calls == 1 {
                model.setImporterPresented(false)
                model.setImporterPresented(true)
            }
        }

        model.receiveImportResult(.failure(error))

        XCTAssertGreaterThanOrEqual(probe.calls, 1)
        XCTAssertTrue(model.isImporterPresented)
        XCTAssertNil(model.importNotice)
        XCTAssertTrue(model.records.isEmpty)
        XCTAssertEqual(model.activeReadCount, 0)
    }

    func testImporterErrorFormattingCannotOverwriteANestedSuccessfulImport() async throws {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service, includesSamples: false)
        let probe = DemoFileBrowserReentryProbe()
        let url = try localURL("new-import.txt")
        defer {
            model.close()
            gate.close()
        }
        model.resume()
        model.setImporterPresented(true)
        let error = DemoFileBrowserReentrantError {
            probe.calls += 1
            if probe.calls == 1 { model.receiveImportResult(.success([url])) }
        }

        model.receiveImportResult(.failure(error))

        XCTAssertGreaterThanOrEqual(probe.calls, 1)
        XCTAssertEqual(model.records.count, 1)
        XCTAssertEqual(model.selectedRecord?.source, .file(url))
        XCTAssertEqual(model.selectedRecord?.name, "new-import.txt")
        XCTAssertEqual(model.importNotice, "Added 1 file to the list.")
        XCTAssertFalse(model.isImporterPresented)
        XCTAssertEqual(model.preview, .loading)
        try await assertStarts(1, gate: gate)
        XCTAssertEqual(gate.snapshot.starts[0].source, .file(url))
        try await complete(0, text: "Nested import content", model: model, gate: gate)
    }

    func testImporterErrorFormattingCannotUndoAReentrantClearOrClose() async throws {
        for shouldClose in [false, true] {
            let gate = DemoFilePreviewGate()
            let model = DemoFileBrowserModel(service: gate.service)
            let probe = DemoFileBrowserReentryProbe()
            defer {
                model.close()
                gate.close()
            }
            model.resume()
            let initialRead = try XCTUnwrap(model.activeReadTask)
            model.setImporterPresented(true)
            let error = DemoFileBrowserReentrantError {
                probe.calls += 1
                if probe.calls == 1 {
                    if shouldClose { model.close() } else { model.clearFiles() }
                }
            }

            model.receiveImportResult(.failure(error))
            try await assertTaskFinished(initialRead, model: model, gate: gate, description: "formatter-revoked read")

            XCTAssertGreaterThanOrEqual(probe.calls, 1)
            XCTAssertEqual(model.isClosed, shouldClose)
            XCTAssertFalse(model.isImporterPresented)
            XCTAssertNil(model.importNotice)
            XCTAssertEqual(model.activeReadCount, 0)
            XCTAssertTrue(gate.snapshot.starts.isEmpty)
            if shouldClose {
                XCTAssertEqual(model.records, DemoFileBrowserRecord.samples)
                XCTAssertEqual(model.selectedID, "sample:welcome")
            } else {
                XCTAssertTrue(model.records.isEmpty)
                XCTAssertNil(model.selectedID)
            }
        }
    }

    func testPreviewErrorFormattingCannotPublishAnOldFailureAfterSelectingAnotherRecord() async throws {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service)
        let probe = DemoFileBrowserReentryProbe()
        let observation = DemoFileBrowserObservation(model)
        defer {
            observation.close()
            model.close()
            gate.close()
        }
        model.resume()
        try await assertStarts(1, gate: gate)
        let oldTask = try XCTUnwrap(model.activeReadTask)
        let error = DemoFileBrowserReentrantError {
            probe.calls += 1
            if probe.calls == 1 { probe.accepted = model.select(id: "sample:unicode") }
        }

        XCTAssertTrue(gate.finish(0, result: .failure(error)))
        try await assertTaskFinished(
            oldTask, model: model, gate: gate, description: "owned preview read")
        try await assertStarts(2, gate: gate)

        XCTAssertGreaterThanOrEqual(probe.calls, 1)
        XCTAssertTrue(probe.accepted)
        XCTAssertEqual(model.selectedID, "sample:unicode")
        XCTAssertEqual(model.preview, .loading)
        XCTAssertEqual(model.activeReadCount, 1)
        XCTAssertNil(model.pendingReadID)
        XCTAssertEqual(gate.snapshot.maximumConcurrent, 1)
        try await complete(1, text: "Formatter selected a new source", model: model, gate: gate)
        XCTAssertFalse(observation.snapshots.contains { $0.preview == .failed("Reentrant formatter failure.") })
    }

    func testRestoringTheSameSampleIDUsesANewReadAndRejectsTheOldGeneration() async throws {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service)
        let observation = DemoFileBrowserObservation(model)
        defer {
            observation.close()
            model.close()
            gate.close()
        }
        model.resume()
        try await assertStarts(1, gate: gate)
        let oldTask = try XCTUnwrap(model.activeReadTask)

        model.restoreSamples()

        XCTAssertEqual(model.selectedID, "sample:welcome")
        XCTAssertEqual(model.pendingReadID, "sample:welcome")
        XCTAssertEqual(model.activeReadCount, 1)
        XCTAssertTrue(gate.succeed(0, text: "Old generation with equal record ID"))
        try await assertTaskFinished(
            oldTask, model: model, gate: gate, description: "owned preview read")
        try await assertStarts(2, gate: gate)
        XCTAssertEqual(gate.snapshot.starts[0].source, gate.snapshot.starts[1].source)
        try await complete(1, text: "Restored sample was actually reloaded", model: model, gate: gate)

        XCTAssertFalse(
            observation.snapshots.contains { $0.preview == ready("Old generation with equal record ID") })
        XCTAssertEqual(gate.snapshot.maximumConcurrent, 1)
    }

    func testMalformedSampleBytesBecomeARealDecodeFailureAndCanBeRetried() async throws {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service)
        defer {
            model.close()
            gate.close()
        }
        XCTAssertTrue(model.select(id: "sample:invalid"))
        model.resume()
        try await assertStarts(1, gate: gate)
        let task = try XCTUnwrap(model.activeReadTask)
        XCTAssertEqual(gate.snapshot.starts[0].source, .sample(Data([0xC3, 0x28])))

        XCTAssertTrue(gate.finish(0, result: .success(Data([0xC3, 0x28]))))
        try await assertTaskFinished(
            task, model: model, gate: gate, description: "owned preview read")

        XCTAssertEqual(model.selectedID, "sample:invalid")
        XCTAssertEqual(model.preview, .failed("This file is not valid UTF-8 text."))
        XCTAssertEqual(model.activeReadCount, 0)
        XCTAssertTrue(model.retryPreview())
        try await assertStarts(2, gate: gate)
        try await complete(1, text: "Repaired UTF-8 · 文書", model: model, gate: gate)
        XCTAssertEqual(model.selectedID, "sample:invalid")
    }

    func testObservationPredicateCanCloseItselfBeforeWaitRegistration() async {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service)
        let observation = DemoFileBrowserObservation(model)
        defer {
            observation.close()
            model.close()
            gate.close()
        }

        let reached = await observation.waitFor { _ in
            observation.close()
            return false
        }

        XCTAssertFalse(reached)
        XCTAssertTrue(gate.snapshot.starts.isEmpty)
    }

    func testObservationPredicateCanCloseDuringNotificationWithoutLeavingAWaiter() async {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service)
        let observation = DemoFileBrowserObservation(model)
        let predicateEntered = XCTestExpectation(description: "observation predicate entered before suspension")
        let probe = DemoFileBrowserReentryProbe()
        defer {
            observation.close()
            model.close()
            gate.close()
        }
        let waiter = Task { @MainActor in
            await observation.waitFor { _ in
                probe.calls += 1
                if probe.calls == 1 {
                    predicateEntered.fulfill()
                } else {
                    observation.close()
                }
                return false
            }
        }
        let entered = await XCTWaiter.fulfillment(of: [predicateEntered], timeout: 5)
        guard entered == .completed else {
            XCTFail("Observation predicate did not register")
            observation.close()
            _ = await waiter.value
            return
        }

        model.clearFiles()
        let reached = await waiter.value

        XCTAssertFalse(reached)
        XCTAssertEqual(probe.calls, 2)
        XCTAssertTrue(model.records.isEmpty)
        XCTAssertTrue(gate.snapshot.starts.isEmpty)
    }

    func testPreCancelledVisibleTaskDoesNotAttachResumeOrStartAReader() async throws {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service)
        let before = model.snapshot
        let visibility = Task { @MainActor in await model.runWhileVisible() }
        defer {
            visibility.cancel()
            model.close()
            gate.close()
        }
        // Both operations occur in this actor turn, before the new task enters.
        visibility.cancel()
        try await assertTaskFinished(visibility, model: model, gate: gate, description: "pre-cancelled visibility")

        XCTAssertEqual(model.snapshot, before)
        XCTAssertFalse(model.isClosed)
        XCTAssertEqual(model.activeReadCount, 0)
        XCTAssertNil(model.pendingReadID)
        XCTAssertTrue(gate.snapshot.starts.isEmpty)
        XCTAssertTrue(gate.snapshot.cancellations.isEmpty)
    }

    func testVisibleTaskCancellationRevokesActionsAndCancelsItsReadBeforeMainActorCleanup() async throws {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service)
        let observation = DemoFileBrowserObservation(model)
        let probe = DemoFileBrowserReentryProbe()
        let visibility = Task { @MainActor in await model.runWhileVisible() }
        defer {
            observation.close()
            visibility.cancel()
            model.close()
            gate.close()
        }
        try await assertStarts(1, gate: gate)
        try await assertRegistrations(1, gate: gate)
        let read = try XCTUnwrap(model.activeReadTask)
        let beforeCancellation = model.snapshot
        let lateURL = try localURL("after-visibility-cancel.txt")
        let lateError = DemoFileBrowserReentrantError { probe.calls += 1 }

        visibility.cancel()

        // Do not await a cleanup task before these checks. The installed reader
        // cancellation and admission revocation must happen in cancel() itself.
        XCTAssertEqual(gate.snapshot.cancellations, [0])
        XCTAssertEqual(gate.snapshot.active, [0])
        XCTAssertTrue(gate.snapshot.returns.isEmpty)
        XCTAssertEqual(model.activeReadCount, 1)
        XCTAssertFalse(model.retryPreview())
        XCTAssertFalse(model.select(id: "sample:unicode"))
        XCTAssertFalse(model.importFiles([lateURL]))
        model.receiveImportResult(.failure(lateError))
        model.receiveImportResult(.success([lateURL]))
        model.clearFiles()
        model.restoreSamples()
        model.setImporterPresented(true)
        model.resume()
        XCTAssertEqual(probe.calls, 0)
        XCTAssertEqual(model.snapshot, beforeCancellation)
        XCTAssertNil(model.pendingReadID)
        XCTAssertEqual(gate.snapshot.starts.count, 1)

        XCTAssertTrue(gate.succeed(0, text: "Late bytes after visibility cancellation"))
        try await assertTaskFinished(read, model: model, gate: gate, description: "cancelled visible read")
        try await assertTaskFinished(
            visibility, model: model, gate: gate, description: "visibility cancellation cleanup")

        XCTAssertEqual(model.preview, .cancelled)
        XCTAssertEqual(model.activeReadCount, 0)
        XCTAssertFalse(model.isClosed)
        XCTAssertEqual(gate.snapshot.starts.count, 1)
        XCTAssertEqual(gate.snapshot.returns, [0])
        XCTAssertFalse(
            observation.snapshots.contains { $0.preview == ready("Late bytes after visibility cancellation") })
    }

    func testCancellingVisibilityPreventsAnAlreadyQueuedSelectionFromStarting() async throws {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service)
        let observation = DemoFileBrowserObservation(model)
        let visibility = Task { @MainActor in await model.runWhileVisible() }
        defer {
            observation.close()
            visibility.cancel()
            model.close()
            gate.close()
        }
        try await assertStarts(1, gate: gate)
        try await assertRegistrations(1, gate: gate)
        let firstRead = try XCTUnwrap(model.activeReadTask)
        XCTAssertTrue(model.select(id: "sample:unicode"))
        XCTAssertEqual(model.pendingReadID, "sample:unicode")

        visibility.cancel()

        XCTAssertEqual(gate.snapshot.cancellations, [0])
        XCTAssertEqual(gate.snapshot.starts.count, 1)
        XCTAssertEqual(gate.snapshot.active, [0])
        XCTAssertEqual(model.activeReadCount, 1)
        // The pending request still exists until actor cleanup; its revoked
        // visibility authority must already prevent further admission.
        XCTAssertEqual(model.pendingReadID, "sample:unicode")
        XCTAssertFalse(model.retryPreview())
        XCTAssertFalse(model.select(id: "sample:empty"))
        XCTAssertFalse(model.importFiles([try localURL("blocked-pending.txt")]))
        XCTAssertTrue(gate.succeed(0, text: "Old A returned after its view was removed"))

        // Join the reader before explicitly joining visibility cleanup. The
        // scheduler may complete cleanup first; B must not start in either case.
        try await assertTaskFinished(firstRead, model: model, gate: gate, description: "revoked pending predecessor")
        try await assertTaskFinished(visibility, model: model, gate: gate, description: "revoked pending visibility")

        XCTAssertEqual(model.selectedID, "sample:unicode")
        XCTAssertEqual(model.preview, .cancelled)
        XCTAssertNil(model.pendingReadID)
        XCTAssertEqual(model.activeReadCount, 0)
        XCTAssertEqual(gate.snapshot.starts.map(\.source), [DemoFileBrowserRecord.samples[0].source])
        XCTAssertEqual(gate.snapshot.maximumConcurrent, 1)
        XCTAssertFalse(
            observation.snapshots.contains { $0.preview == ready("Old A returned after its view was removed") })
    }

    func testReplacingVisibilityDoesNotLetOldCleanupCancelTheNewPendingOrActiveRead() async throws {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service)
        let oldVisibility = Task { @MainActor in await model.runWhileVisible() }
        var newVisibility: Task<Void, Never>?
        let adoption = XCTestExpectation(description: "replacement visibility suspended the preceding request")
        var isAwaitingAdoption = true
        let subscription = model.objectWillChange.sink { _ in
            if isAwaitingAdoption, model.preview == .cancelled {
                isAwaitingAdoption = false
                adoption.fulfill()
            }
        }
        defer {
            subscription.cancel()
            oldVisibility.cancel()
            newVisibility?.cancel()
            model.close()
            gate.close()
        }
        try await assertStarts(1, gate: gate)
        try await assertRegistrations(1, gate: gate)
        let firstRead = try XCTUnwrap(model.activeReadTask)
        XCTAssertTrue(model.select(id: "sample:unicode"))
        XCTAssertEqual(model.pendingReadID, "sample:unicode")

        let replacement = Task { @MainActor in await model.runWhileVisible() }
        newVisibility = replacement
        try await assertEvent(adoption, model: model, gate: gate)
        oldVisibility.cancel()
        try await assertTaskFinished(oldVisibility, model: model, gate: gate, description: "retired visibility")

        XCTAssertEqual(model.selectedID, "sample:unicode")
        XCTAssertEqual(model.preview, .loading)
        XCTAssertEqual(model.pendingReadID, "sample:unicode")
        XCTAssertEqual(model.activeReadCount, 1)
        XCTAssertEqual(gate.snapshot.starts.count, 1)
        XCTAssertTrue(gate.succeed(0, text: "Retired mount A"))
        try await assertTaskFinished(firstRead, model: model, gate: gate, description: "retired mount read")
        try await assertStarts(2, gate: gate)
        try await assertRegistrations(2, gate: gate)
        let currentRead = try XCTUnwrap(model.activeReadTask)

        oldVisibility.cancel()

        XCTAssertEqual(gate.snapshot.cancellations, [0])
        XCTAssertEqual(gate.snapshot.starts[1].source, DemoFileBrowserRecord.samples[1].source)
        XCTAssertEqual(model.preview, .loading)
        XCTAssertNil(model.pendingReadID)
        XCTAssertTrue(gate.succeed(1, text: "Replacement mount B"))
        try await assertTaskFinished(currentRead, model: model, gate: gate, description: "replacement mount read")
        assertReady(model, text: "Replacement mount B")
        XCTAssertEqual(gate.snapshot.maximumConcurrent, 1)

        replacement.cancel()
        try await assertTaskFinished(
            replacement, model: model, gate: gate, description: "replacement visibility cleanup")
        assertReady(model, text: "Replacement mount B")
    }

    func testClosingTheModelEndsVisibilityWithoutWaitingForOrReopeningThePhysicalRead() async throws {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service)
        let visibility = Task { @MainActor in await model.runWhileVisible() }
        var lateVisibility: Task<Void, Never>?
        defer {
            visibility.cancel()
            lateVisibility?.cancel()
            model.close()
            gate.close()
        }
        try await assertStarts(1, gate: gate)
        try await assertRegistrations(1, gate: gate)
        let read = try XCTUnwrap(model.activeReadTask)
        XCTAssertFalse(visibility.isCancelled)

        model.close()
        let closed = model.snapshot
        try await assertTaskFinished(visibility, model: model, gate: gate, description: "model-closed visibility")

        XCTAssertFalse(visibility.isCancelled, "Model close resumes the lease without cancelling its caller")
        XCTAssertTrue(model.isClosed)
        XCTAssertEqual(model.snapshot, closed)
        XCTAssertEqual(model.activeReadCount, 1)
        XCTAssertEqual(gate.snapshot.cancellations, [0])
        XCTAssertEqual(gate.snapshot.active, [0])
        XCTAssertTrue(gate.snapshot.returns.isEmpty)

        let attemptedReopen = Task { @MainActor in await model.runWhileVisible() }
        lateVisibility = attemptedReopen
        try await assertTaskFinished(
            attemptedReopen, model: model, gate: gate, description: "closed visibility admission")
        model.resume()
        model.restoreSamples()
        XCTAssertEqual(model.snapshot, closed)
        XCTAssertEqual(gate.snapshot.starts.count, 1)
        XCTAssertTrue(gate.succeed(0, text: "A read after terminal close"))
        try await assertTaskFinished(read, model: model, gate: gate, description: "terminally closed read")

        XCTAssertEqual(model.snapshot, closed)
        XCTAssertEqual(model.activeReadCount, 0)
        XCTAssertNil(model.pendingReadID)
        XCTAssertEqual(gate.snapshot.starts.count, 1)
    }

    func testPreCancelledReplacementCannotRetireTheCurrentlyVisibleOwner() async throws {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service)
        let visibility = Task { @MainActor in await model.runWhileVisible() }
        var rejectedVisibility: Task<Void, Never>?
        defer {
            visibility.cancel()
            rejectedVisibility?.cancel()
            model.close()
            gate.close()
        }
        try await assertStarts(1, gate: gate)
        try await assertRegistrations(1, gate: gate)
        let read = try XCTUnwrap(model.activeReadTask)
        let before = model.snapshot
        let rejected = Task { @MainActor in await model.runWhileVisible() }
        rejectedVisibility = rejected

        rejected.cancel()
        try await assertTaskFinished(rejected, model: model, gate: gate, description: "pre-cancelled replacement")

        XCTAssertEqual(model.snapshot, before)
        XCTAssertTrue(gate.snapshot.cancellations.isEmpty)
        XCTAssertEqual(model.activeReadCount, 1)
        XCTAssertNil(model.pendingReadID)
        XCTAssertEqual(gate.snapshot.starts.count, 1)
        XCTAssertTrue(gate.succeed(0, text: "Original visible owner"))
        try await assertTaskFinished(read, model: model, gate: gate, description: "original visible read")
        assertReady(model, text: "Original visible owner")
        visibility.cancel()
        try await assertTaskFinished(visibility, model: model, gate: gate, description: "original visibility cleanup")
        assertReady(model, text: "Original visible owner")
    }

    func testFreshImportSelectionAndRetryDoNotReadUntilExplicitResume() async throws {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service, includesSamples: false)
        defer {
            model.close()
            gate.close()
        }
        let firstURL = try localURL("queued-first.txt")
        let latestURL = try localURL("queued-latest.txt")

        XCTAssertTrue(model.importFiles([firstURL, latestURL]))

        XCTAssertEqual(model.selectedRecord?.source, .file(firstURL))
        XCTAssertEqual(model.preview, .idle)
        XCTAssertEqual(model.activeReadCount, 0)
        XCTAssertTrue(gate.snapshot.starts.isEmpty)
        let latest = try XCTUnwrap(model.records.last)
        XCTAssertTrue(model.select(id: latest.id))
        XCTAssertEqual(model.preview, .idle)
        XCTAssertEqual(model.activeReadCount, 0)
        XCTAssertTrue(model.retryPreview())
        XCTAssertEqual(model.preview, .idle)
        XCTAssertEqual(model.activeReadCount, 0)
        XCTAssertNil(model.pendingReadID)
        XCTAssertFalse(model.isWaitingForPreviousRead)
        model.setImporterPresented(true)
        XCTAssertFalse(model.isImporterPresented)
        XCTAssertTrue(gate.snapshot.starts.isEmpty)

        model.resume()
        try await assertStarts(1, gate: gate)

        XCTAssertEqual(gate.snapshot.starts.map(\.source), [.file(latestURL)])
        try await complete(0, text: "Only the queued latest file was read", model: model, gate: gate)
        XCTAssertEqual(model.selectedID, latest.id)
        XCTAssertEqual(gate.snapshot.maximumConcurrent, 1)
    }

    func testPreCancelledVisibilityWithQueuedIntentDoesNotStartUntilANewOwnerAppears() async throws {
        let gate = DemoFilePreviewGate()
        let model = DemoFileBrowserModel(service: gate.service, includesSamples: false)
        let url = try localURL("pre-visible-intent.txt")
        XCTAssertTrue(model.importFiles([url]))
        XCTAssertTrue(model.retryPreview())
        let queued = model.snapshot
        let cancelled = Task { @MainActor in await model.runWhileVisible() }
        var nextVisibility: Task<Void, Never>?
        defer {
            cancelled.cancel()
            nextVisibility?.cancel()
            model.close()
            gate.close()
        }

        cancelled.cancel()
        try await assertTaskFinished(
            cancelled, model: model, gate: gate, description: "pre-visible queued cancellation")

        XCTAssertEqual(model.snapshot, queued)
        XCTAssertEqual(model.preview, .idle)
        XCTAssertEqual(model.selectedRecord?.source, .file(url))
        XCTAssertEqual(model.activeReadCount, 0)
        XCTAssertNil(model.pendingReadID)
        XCTAssertTrue(gate.snapshot.starts.isEmpty)

        let replacement = Task { @MainActor in await model.runWhileVisible() }
        nextVisibility = replacement
        try await assertStarts(1, gate: gate)
        let read = try XCTUnwrap(model.activeReadTask)
        XCTAssertEqual(gate.snapshot.starts.map(\.source), [.file(url)])
        XCTAssertTrue(gate.succeed(0, text: "A later visible owner admitted the queued file"))
        try await assertTaskFinished(read, model: model, gate: gate, description: "queued visible read")
        assertReady(model, text: "A later visible owner admitted the queued file")
        replacement.cancel()
        try await assertTaskFinished(replacement, model: model, gate: gate, description: "queued replacement cleanup")
        assertReady(model, text: "A later visible owner admitted the queued file")
    }

    private func localURL(_ name: String) throws -> URL {
        try XCTUnwrap(URL(string: "file:///C:/Preview/\(name)"))
    }

    private func ready(_ text: String) -> DemoFileBrowserPreviewState {
        .ready(DemoFilePreview(text: text, byteCount: text.utf8.count))
    }

    private func assertReady(
        _ model: DemoFileBrowserModel, text: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(model.preview, ready(text), file: file, line: line)
        XCTAssertEqual(model.activeReadCount, 0, file: file, line: line)
        XCTAssertNil(model.pendingReadID, file: file, line: line)
    }

    private func assertStarts(
        _ count: Int, gate: DemoFilePreviewGate,
        file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        let reached = await gate.waitForStarts(count)
        XCTAssertTrue(reached, "Reader start barrier closed before reaching \(count)", file: file, line: line)
        guard reached else { throw DemoFileBrowserWaitError.missingStart }
    }

    private func assertCancellation(
        _ id: Int, gate: DemoFilePreviewGate,
        file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        let reached = await gate.waitForCancellation(of: id)
        XCTAssertTrue(reached, "Cancellation barrier closed before read \(id) was cancelled", file: file, line: line)
        guard reached else { throw DemoFileBrowserWaitError.missingCancellation }
    }

    private func assertRegistrations(
        _ count: Int, gate: DemoFilePreviewGate,
        file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        let reached = await gate.waitForRegistrations(count)
        XCTAssertTrue(reached, "Reader registration barrier closed before reaching \(count)", file: file, line: line)
        guard reached else { throw DemoFileBrowserWaitError.missingRegistration }
    }

    private func assertEvent(
        _ expectation: XCTestExpectation, model: DemoFileBrowserModel?, gate: DemoFilePreviewGate,
        file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        let result = await XCTWaiter.fulfillment(of: [expectation], timeout: 5)
        guard result == .completed else {
            model?.close()
            gate.close()
            XCTFail("Expected event did not arrive: \(expectation.expectationDescription)", file: file, line: line)
            throw DemoFileBrowserWaitError.missingEvent
        }
    }

    private func assertTaskFinished(
        _ task: Task<Void, Never>, model: DemoFileBrowserModel?, gate: DemoFilePreviewGate, description: String,
        file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        // Bound the assertion and revoke test-owned work on failure. Task
        // cancellation remains cooperative; the test runner still needs its
        // process deadline for an implementation that never returns at all.
        let finished = XCTestExpectation(description: description)
        let completion = Task { @MainActor in
            await task.value
            finished.fulfill()
        }
        defer { completion.cancel() }
        do {
            try await assertEvent(finished, model: model, gate: gate, file: file, line: line)
        } catch {
            task.cancel()
            throw error
        }
    }

    private func complete(
        _ id: Int, text: String, model: DemoFileBrowserModel, gate: DemoFilePreviewGate,
        file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        let task = try XCTUnwrap(model.activeReadTask, file: file, line: line)
        XCTAssertTrue(gate.succeed(id, text: text), file: file, line: line)
        try await assertTaskFinished(
            task, model: model, gate: gate, description: "completed preview read \(id)", file: file, line: line)
        assertReady(model, text: text, file: file, line: line)
    }
}

private enum DemoFileBrowserInjectedError: Error, LocalizedError {
    case readFailed

    var errorDescription: String? { "Injected preview failure." }
}

private enum DemoFileBrowserWaitError: Error {
    case missingStart
    case missingCancellation
    case missingRegistration
    case missingEvent
}

@MainActor
private final class DemoFileBrowserReentryProbe {
    var calls = 0
    var accepted = false
}

private struct DemoFileBrowserReentrantError: Error, LocalizedError {
    let descriptionAction: @MainActor @Sendable () -> Void

    var errorDescription: String? {
        // The model deliberately formats errors on MainActor. The gate and
        // injected service merely carry this value without inspecting it.
        MainActor.assumeIsolated { descriptionAction() }
        return "Reentrant formatter failure."
    }
}
