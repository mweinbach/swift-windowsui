import Foundation
import SwiftWindowsCore
import SwiftWindowsDemo
import SwiftWindowsPlatform
import SwiftWindowsUI
import XCTest

@testable import WinSwiftUI

private enum SessionFixtureError: Error { case injected }

private final class SessionReferenceDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.utf8PlainText] }
    var text = "reference"

    init() {}
    init(configuration: FileDocumentReadConfiguration) throws {}

    func fileWrapper(configuration: FileDocumentWriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

@MainActor
private final class SessionReleaseProbe {
    let onRelease: () -> Void

    init(onRelease: @escaping () -> Void) { self.onRelease = onRelease }

    isolated deinit { onRelease() }
}

@MainActor
private final class SessionReleaseError: Error {
    let onRelease: @MainActor () -> Void

    init(onRelease: @escaping @MainActor () -> Void) { self.onRelease = onRelease }

    isolated deinit { onRelease() }
}

@MainActor
private func installSessionReleaseProbe(
    _ session: FileDocumentSession<DemoPlainTextDocument>, onRelease: @escaping () -> Void
) {
    let probe = SessionReleaseProbe(onRelease: onRelease)
    session.onChange = { withExtendedLifetime(probe) {} }
}

@MainActor
private final class SessionFileService: DocumentFileService {
    let live = LiveDocumentFileService()
    var selectedSave: FileDialogOutcome<URL> = .cancelled
    var onChoose: (() -> Void)?
    var beforeWrite: (() throws -> Void)?
    var afterWrite: (() -> Void)?
    private(set) var choices = 0
    private(set) var writeAttempts = 0
    private(set) var committedWrites = 0

    func chooseOpenURL(types: [UTType], owner: FileDialogOwner) -> FileDialogOutcome<URL> { .cancelled }

    func chooseSaveURL(
        name: String?, directory: URL?, type: UTType, owner: FileDialogOwner
    ) -> FileDialogOutcome<URL> {
        choices += 1
        onChoose?()
        return selectedSave
    }

    func readRegularFile(at url: URL, maximumBytes: Int) throws -> Data {
        try live.readRegularFile(at: url, maximumBytes: maximumBytes)
    }

    func writeRegularFile(
        to url: URL,
        provideData: @MainActor (URL) throws -> Data,
        validate: @MainActor () throws -> Void
    ) throws -> Data {
        writeAttempts += 1
        try beforeWrite?()
        let bytes = try live.writeRegularFile(to: url, provideData: provideData, validate: validate)
        committedWrites += 1
        afterWrite?()
        return bytes
    }
}

@MainActor
private final class SessionEncodingProbe {
    var calls = 0
    var onEncode: (() throws -> Void)?
}

@MainActor
private final class SessionFixture {
    let directory: URL
    let url: URL
    let owner: DocumentOwnerLease
    let manager: UndoManager
    let files: SessionFileService
    let encoding: SessionEncodingProbe
    let session: FileDocumentSession<DemoPlainTextDocument>

    init(text: String = "A", persisted: Bool = false, editable: Bool = true, manager: UndoManager? = nil) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("swift-windowsui-document-session-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("document.txt")
        let owner = DocumentOwnerLease()
        let files = SessionFileService()
        let encoding = SessionEncodingProbe()
        let manager = manager ?? UndoManager()
        self.directory = directory
        self.url = url
        self.owner = owner
        self.files = files
        self.encoding = encoding
        self.manager = manager
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bytes = Data(text.utf8)
        if persisted { try bytes.write(to: url, options: .atomic) }
        let base = DocumentCodec<DemoPlainTextDocument>.editable(DemoPlainTextDocument.self)
        let codec = DocumentCodec<DemoPlainTextDocument>(
            decode: base.decode,
            encode: { document, contentType in
                encoding.calls += 1
                try encoding.onEncode?()
                guard let encode = base.encode else { throw SessionFixtureError.injected }
                return try encode(document, contentType)
            }
        )
        session = try FileDocumentSession(
            document: DemoPlainTextDocument(text: text),
            fileURL: persisted ? url : nil,
            contentType: .utf8PlainText,
            isEditable: editable,
            owner: owner,
            codec: codec,
            files: files,
            undoManager: manager,
            savedBytes: persisted ? bytes : nil
        )
        files.selectedSave = .selected(url)
    }

    func setText(_ text: String) {
        session.configuration().$document.text.wrappedValue = text
    }

    func cleanup() {
        session.invalidate()
        files.onChoose = nil
        files.beforeWrite = nil
        files.afterWrite = nil
        encoding.onEncode = nil
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private func withSessionFixture(
    text: String = "A", persisted: Bool = false, editable: Bool = true,
    _ body: (SessionFixture) throws -> Void
) throws {
    let fixture = try SessionFixture(text: text, persisted: persisted, editable: editable)
    defer { fixture.cleanup() }
    try body(fixture)
}

@MainActor
private func requireSave(
    _ outcome: DocumentSaveOutcome, isCurrent: Bool = true,
    file: StaticString = #filePath, line: UInt = #line
) throws -> DocumentSaveReceipt {
    guard case .saved(let receipt, let actualCurrent) = outcome else {
        XCTFail("Expected a completed real save", file: file, line: line)
        throw SessionFixtureError.injected
    }
    XCTAssertEqual(actualCurrent, isCurrent, file: file, line: line)
    return receipt
}

@MainActor
private func requireCloseIntent(
    _ session: FileDocumentSession<DemoPlainTextDocument>,
    file: StaticString = #filePath, line: UInt = #line
) throws -> DocumentCloseIntent {
    guard case .needsDecision(let intent) = session.requestClose(isHostSettled: true) else {
        XCTFail("Expected an unsaved-document decision", file: file, line: line)
        throw SessionFixtureError.injected
    }
    return intent
}

@MainActor
private func requireApproval(
    _ resolution: DocumentCloseResolution,
    file: StaticString = #filePath, line: UInt = #line
) throws -> DocumentCloseApproval {
    guard case .approved(let approval) = resolution else {
        XCTFail("Expected an approval, not teardown", file: file, line: line)
        throw SessionFixtureError.injected
    }
    return approval
}

final class FileDocumentSessionTests: XCTestCase {
    func testNewDocumentHasNoPersistedCheckpointAndWritableProjectedConfiguration() async throws {
        try await MainActor.run {
            try withSessionFixture { fixture in
                let configuration = fixture.session.configuration()
                XCTAssertEqual(configuration.document.text, "A")
                XCTAssertNil(configuration.fileURL)
                XCTAssertNil(fixture.session.savedCheckpoint)
                XCTAssertTrue(fixture.session.isDirty)
                configuration.$document.text.wrappedValue = "B"
                XCTAssertEqual(fixture.session.document.text, "B")
                XCTAssertEqual(fixture.session.mutationRevision, 1)
                XCTAssertTrue(fixture.manager.canUndo)
            }
        }
    }

    func testDirectAssignmentsUseOneReciprocalModelHistory() async throws {
        try await MainActor.run {
            try withSessionFixture { fixture in
                fixture.setText("B")
                fixture.setText("C")
                fixture.manager.undo()
                XCTAssertEqual(fixture.session.document.text, "B")
                fixture.manager.undo()
                XCTAssertEqual(fixture.session.document.text, "A")
                XCTAssertFalse(fixture.manager.canUndo)
                fixture.manager.redo()
                XCTAssertEqual(fixture.session.document.text, "B")
                fixture.manager.redo()
                XCTAssertEqual(fixture.session.document.text, "C")
                XCTAssertFalse(fixture.manager.canRedo)
                XCTAssertEqual(fixture.session.mutationRevision, 6)
            }
        }
    }

    func testSaveDoesNotEraseHistoryAndUndoRestoresSavedCheckpoint() async throws {
        try await MainActor.run {
            try withSessionFixture { fixture in
                fixture.setText("B")
                let receipt = try requireSave(fixture.session.save())
                let revisionAtSave = fixture.session.mutationRevision
                XCTAssertEqual(receipt.bytes, Data("B".utf8))
                XCTAssertEqual(try Data(contentsOf: fixture.url), receipt.bytes)
                XCTAssertFalse(fixture.session.isDirty)
                XCTAssertTrue(fixture.manager.canUndo)
                fixture.setText("C")
                XCTAssertTrue(fixture.session.isDirty)
                fixture.manager.undo()
                XCTAssertEqual(fixture.session.document.text, "B")
                XCTAssertEqual(fixture.session.currentCheckpoint, receipt.checkpoint)
                XCTAssertGreaterThan(fixture.session.mutationRevision, revisionAtSave)
                XCTAssertFalse(fixture.session.isDirty)
                fixture.manager.undo()
                XCTAssertEqual(fixture.session.document.text, "A")
                XCTAssertTrue(fixture.session.isDirty)
                fixture.manager.redo()
                XCTAssertFalse(fixture.session.isDirty)
                fixture.manager.redo()
                XCTAssertEqual(fixture.session.document.text, "C")
                XCTAssertTrue(fixture.session.isDirty)
            }
        }
    }

    func testNewHistoryBranchCannotMatchSavedCheckpointByDepth() async throws {
        try await MainActor.run {
            try withSessionFixture { fixture in
                fixture.setText("B")
                let saved = try requireSave(fixture.session.save())
                fixture.manager.undo()
                fixture.setText("another branch")
                XCTAssertNotEqual(fixture.session.currentCheckpoint, saved.checkpoint)
                XCTAssertTrue(fixture.session.isDirty)
                XCTAssertFalse(fixture.manager.canRedo)
                XCTAssertEqual(try Data(contentsOf: fixture.url), Data("B".utf8))
            }
        }
    }

    func testSavedDocumentUsesExistingDestinationAndFreshConfigurationURL() async throws {
        try await MainActor.run {
            try withSessionFixture { fixture in
                _ = try requireSave(fixture.session.save())
                fixture.setText("changed")
                _ = try requireSave(fixture.session.save())
                XCTAssertEqual(fixture.files.choices, 1)
                XCTAssertEqual(fixture.files.committedWrites, 2)
                XCTAssertEqual(fixture.session.configuration().fileURL, fixture.url)
                XCTAssertEqual(try Data(contentsOf: fixture.url), Data("changed".utf8))
            }
        }
    }

    func testSaveAsCommitsRealBytesBeforeUpdatingDestination() async throws {
        try await MainActor.run {
            try withSessionFixture(persisted: true) { fixture in
                let destination = fixture.directory.appendingPathComponent("copy.txt")
                fixture.files.selectedSave = .selected(destination)
                fixture.setText("new destination")
                let receipt = try requireSave(fixture.session.saveAs())
                XCTAssertEqual(receipt.url, destination)
                XCTAssertEqual(fixture.session.fileURL, destination)
                XCTAssertEqual(try Data(contentsOf: destination), receipt.bytes)
                XCTAssertEqual(try Data(contentsOf: fixture.url), Data("A".utf8))
            }
        }
    }

    func testCancellationDoesNotSerializeWriteOrChangePersistence() async throws {
        try await MainActor.run {
            try withSessionFixture { fixture in
                fixture.files.selectedSave = .cancelled
                fixture.setText("B")
                guard case .cancelled = fixture.session.save() else { return XCTFail("Expected cancellation") }
                XCTAssertEqual(fixture.encoding.calls, 0)
                XCTAssertEqual(fixture.files.writeAttempts, 0)
                XCTAssertNil(fixture.session.fileURL)
                XCTAssertNil(fixture.session.savedBytes)
                XCTAssertTrue(fixture.session.isDirty)
                XCTAssertTrue(fixture.manager.canUndo)
                XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.url.path))
            }
        }
    }

    func testDialogFailureIsNotCancellationAndCanRetry() async throws {
        try await MainActor.run {
            try withSessionFixture { fixture in
                fixture.files.selectedSave = .failed(SessionFixtureError.injected)
                guard case .failed = fixture.session.save() else { return XCTFail("Expected dialog failure") }
                XCTAssertNotNil(fixture.session.lastError)
                XCTAssertEqual(fixture.encoding.calls, 0)
                fixture.files.selectedSave = .selected(fixture.url)
                _ = try requireSave(fixture.session.save())
                XCTAssertNil(fixture.session.lastError)
                XCTAssertEqual(try Data(contentsOf: fixture.url), Data("A".utf8))
            }
        }
    }

    func testWriteFailurePreservesOldBytesURLCheckpointAndHistory() async throws {
        try await MainActor.run {
            try withSessionFixture(persisted: true) { fixture in
                let oldCheckpoint = fixture.session.savedCheckpoint
                fixture.setText("unsaved")
                guard case .failed = fixture.session.save(to: fixture.directory) else {
                    return XCTFail("Replacing a directory must fail")
                }
                XCTAssertEqual(try Data(contentsOf: fixture.url), Data("A".utf8))
                XCTAssertEqual(fixture.session.fileURL, fixture.url)
                XCTAssertEqual(fixture.session.savedCheckpoint, oldCheckpoint)
                XCTAssertEqual(fixture.session.savedBytes, Data("A".utf8))
                XCTAssertTrue(fixture.session.isDirty)
                XCTAssertTrue(fixture.manager.canUndo)
            }
        }
    }

    func testOwnerRetirementDuringDialogRejectsBeforeSerialization() async throws {
        try await MainActor.run {
            try withSessionFixture { fixture in
                try Data("old".utf8).write(to: fixture.url)
                fixture.files.onChoose = { fixture.session.invalidate() }
                guard case .superseded(let written) = fixture.session.save() else {
                    return XCTFail("Expected a retired selection")
                }
                XCTAssertNil(written)
                XCTAssertEqual(fixture.encoding.calls, 0)
                XCTAssertEqual(fixture.files.writeAttempts, 0)
                XCTAssertEqual(try Data(contentsOf: fixture.url), Data("old".utf8))
                XCTAssertNil(fixture.session.fileURL)
            }
        }
    }

    func testMutationDuringDialogRejectsBeforeSerialization() async throws {
        try await MainActor.run {
            try withSessionFixture { fixture in
                try Data("old".utf8).write(to: fixture.url)
                fixture.files.onChoose = { fixture.setText("newer") }
                guard case .superseded(let written) = fixture.session.save() else {
                    return XCTFail("Expected a superseded selection")
                }
                XCTAssertNil(written)
                XCTAssertEqual(fixture.session.document.text, "newer")
                XCTAssertEqual(fixture.encoding.calls, 0)
                XCTAssertEqual(fixture.files.writeAttempts, 0)
                XCTAssertEqual(try Data(contentsOf: fixture.url), Data("old".utf8))
            }
        }
    }

    func testEncoderReentryCannotWriteStaleSnapshot() async throws {
        try await MainActor.run {
            try withSessionFixture(persisted: true) { fixture in
                fixture.setText("requested")
                fixture.encoding.onEncode = { fixture.setText("newer") }
                guard case .superseded(let written) = fixture.session.save() else {
                    return XCTFail("Expected superseded serialization")
                }
                XCTAssertNil(written)
                XCTAssertEqual(fixture.encoding.calls, 1)
                XCTAssertEqual(fixture.files.committedWrites, 0)
                XCTAssertEqual(try Data(contentsOf: fixture.url), Data("A".utf8))
                XCTAssertEqual(fixture.session.document.text, "newer")
                XCTAssertEqual(fixture.session.savedBytes, Data("A".utf8))
            }
        }
    }

    func testEncoderRetirementCannotWriteOrSendLateChangeCallback() async throws {
        try await MainActor.run {
            try withSessionFixture(persisted: true) { fixture in
                fixture.setText("requested")
                var changesAfterRetirement = 0
                fixture.session.onChange = { if !fixture.owner.isValid { changesAfterRetirement += 1 } }
                fixture.encoding.onEncode = { fixture.session.invalidate() }
                guard case .superseded = fixture.session.save() else { return XCTFail("Expected retirement") }
                XCTAssertEqual(changesAfterRetirement, 0)
                XCTAssertEqual(fixture.files.committedWrites, 0)
                XCTAssertEqual(try Data(contentsOf: fixture.url), Data("A".utf8))
                XCTAssertFalse(fixture.manager.canUndo)
            }
        }
    }

    func testReentrantSaveIsBusyAndCannotReplaceCurrentTicket() async throws {
        try await MainActor.run {
            try withSessionFixture { fixture in
                var nestedWasBusy = false
                fixture.files.onChoose = {
                    if case .busy = fixture.session.saveAs() { nestedWasBusy = true }
                }
                let receipt = try requireSave(fixture.session.save())
                XCTAssertTrue(nestedWasBusy)
                XCTAssertEqual(fixture.files.choices, 1)
                XCTAssertEqual(fixture.files.committedWrites, 1)
                XCTAssertEqual(receipt.bytes, try Data(contentsOf: fixture.url))
                XCTAssertFalse(fixture.session.hasActiveOperation)
            }
        }
    }

    func testNewerEditAfterActualWriteKeepsReceiptButRemainsDirty() async throws {
        try await MainActor.run {
            try withSessionFixture { fixture in
                fixture.setText("saved snapshot")
                fixture.files.afterWrite = { fixture.setText("newer") }
                let receipt = try requireSave(fixture.session.save(), isCurrent: false)
                XCTAssertEqual(receipt.bytes, Data("saved snapshot".utf8))
                XCTAssertEqual(try Data(contentsOf: fixture.url), receipt.bytes)
                XCTAssertEqual(fixture.session.savedBytes, receipt.bytes)
                XCTAssertEqual(fixture.session.document.text, "newer")
                XCTAssertTrue(fixture.session.isDirty)
                XCTAssertNotEqual(fixture.session.currentCheckpoint, receipt.checkpoint)
            }
        }
    }

    func testOwnerRetirementAfterActualWriteReturnsFactWithoutApplyingMetadata() async throws {
        try await MainActor.run {
            try withSessionFixture { fixture in
                fixture.files.afterWrite = { fixture.session.invalidate() }
                guard case .superseded(let written) = fixture.session.save(), let written else {
                    return XCTFail("Expected the receipt for bytes already written")
                }
                XCTAssertEqual(try Data(contentsOf: fixture.url), written.bytes)
                XCTAssertNil(fixture.session.fileURL)
                XCTAssertNil(fixture.session.savedBytes)
                XCTAssertEqual(fixture.session.closePhase, .closed)
            }
        }
    }

    func testReadOnlyAndRetiredProjectedBindingsCannotMutateModel() async throws {
        try await MainActor.run {
            try withSessionFixture(editable: false) { fixture in
                fixture.setText("rejected")
                XCTAssertEqual(fixture.session.document.text, "A")
                XCTAssertEqual(fixture.session.mutationRevision, 0)
                XCTAssertFalse(fixture.manager.canUndo)
                guard case .failed(let error) = fixture.session.save() else { return XCTFail("Expected read-only") }
                XCTAssertEqual(error as? DocumentSessionError, .readOnly)
                XCTAssertEqual(fixture.files.writeAttempts, 0)
            }
            try withSessionFixture { fixture in
                let escaped = fixture.session.configuration().$document.text
                fixture.session.invalidate()
                escaped.wrappedValue = "late"
                XCTAssertEqual(escaped.wrappedValue, "A")
                XCTAssertFalse(fixture.manager.canUndo)
            }
        }
    }

    func testNestedPublishedAssignmentHasItsOwnInverse() async throws {
        try await MainActor.run {
            try withSessionFixture { fixture in
                var didWriteNested = false
                fixture.session.onChange = {
                    if !didWriteNested {
                        didWriteNested = true
                        fixture.setText("C")
                    }
                }
                fixture.setText("B")
                XCTAssertEqual(fixture.session.document.text, "C")
                fixture.manager.undo()
                XCTAssertEqual(fixture.session.document.text, "B")
                fixture.manager.undo()
                XCTAssertEqual(fixture.session.document.text, "A")
                XCTAssertFalse(fixture.manager.canUndo)
            }
        }
    }

    func testReplayRejectsUnrelatedModelWritesFromChangeCallback() async throws {
        try await MainActor.run {
            try withSessionFixture { fixture in
                fixture.setText("B")
                fixture.session.onChange = { fixture.setText("unrelated replay write") }
                fixture.manager.undo()
                XCTAssertEqual(fixture.session.document.text, "A")
                XCTAssertFalse(fixture.manager.canUndo)
                fixture.manager.redo()
                XCTAssertEqual(fixture.session.document.text, "B")
                XCTAssertFalse(fixture.manager.canRedo)
            }
        }
    }

    func testInvalidationOnlyRemovesThisSessionsActionsFromSharedManager() async throws {
        try await MainActor.run {
            let manager = UndoManager()
            let first = try SessionFixture(text: "first", manager: manager)
            defer { first.cleanup() }
            let second = try SessionFixture(text: "second", manager: manager)
            defer { second.cleanup() }
            first.setText("first edited")
            second.setText("second edited")
            first.session.invalidate()
            XCTAssertTrue(manager.canUndo)
            manager.undo()
            XCTAssertEqual(second.session.document.text, "second")
            XCTAssertEqual(first.session.document.text, "first edited")
            XCTAssertFalse(manager.canUndo)
            manager.redo()
            XCTAssertEqual(second.session.document.text, "second edited")
        }
    }

    func testRepeatedDirtyCloseRequestsReuseOneIntentAndCancelPreservesHistory() async throws {
        try await MainActor.run {
            try withSessionFixture { fixture in
                fixture.setText("B")
                let intent = try requireCloseIntent(fixture.session)
                XCTAssertEqual(fixture.session.requestClose(isHostSettled: true), .awaitingDecision(intent))
                XCTAssertEqual(fixture.session.requestClose(isHostSettled: true), .awaitingDecision(intent))
                guard case .cancelled = fixture.session.resolveCloseIntent(id: intent.id, choice: .cancel) else {
                    return XCTFail("Expected close cancellation")
                }
                XCTAssertTrue(fixture.owner.isValid)
                XCTAssertEqual(fixture.session.document.text, "B")
                XCTAssertTrue(fixture.manager.canUndo)
                XCTAssertEqual(fixture.files.committedWrites, 0)
                XCTAssertNil(fixture.session.pendingCloseIntent)
            }
        }
    }

    func testDiscardApprovalDoesNotWriteOrClearDirtyStateBeforeTeardown() async throws {
        try await MainActor.run {
            try withSessionFixture { fixture in
                let intent = try requireCloseIntent(fixture.session)
                let approval = try requireApproval(fixture.session.resolveCloseIntent(id: intent.id, choice: .discard))
                XCTAssertTrue(fixture.session.isDirty)
                XCTAssertEqual(fixture.files.choices, 0)
                XCTAssertEqual(fixture.files.writeAttempts, 0)
                XCTAssertTrue(fixture.owner.isValid)
                XCTAssertEqual(fixture.session.closePhase, .approved)
                XCTAssertTrue(fixture.session.reserveClose(approval: approval, isHostSettled: true))
                fixture.session.invalidate()
                XCTAssertFalse(fixture.owner.isValid)
                XCTAssertEqual(fixture.session.closePhase, .closed)
            }
        }
    }

    func testCancelledSaveAsForCloseKeepsSameModelAndUndo() async throws {
        try await MainActor.run {
            try withSessionFixture { fixture in
                fixture.setText("B")
                fixture.files.selectedSave = .cancelled
                let intent = try requireCloseIntent(fixture.session)
                guard case .cancelled = fixture.session.resolveCloseIntent(id: intent.id, choice: .save) else {
                    return XCTFail("Expected save-panel cancellation")
                }
                XCTAssertEqual(fixture.session.document.text, "B")
                XCTAssertTrue(fixture.session.isDirty)
                XCTAssertTrue(fixture.manager.canUndo)
                XCTAssertTrue(fixture.owner.isValid)
                XCTAssertEqual(fixture.encoding.calls, 0)
            }
        }
    }

    func testFailedCloseSaveCanRetryWithoutAnotherIntent() async throws {
        try await MainActor.run {
            try withSessionFixture { fixture in
                let intent = try requireCloseIntent(fixture.session)
                fixture.files.beforeWrite = { throw SessionFixtureError.injected }
                guard case .failed = fixture.session.resolveCloseIntent(id: intent.id, choice: .save) else {
                    return XCTFail("Expected write failure")
                }
                XCTAssertEqual(fixture.session.pendingCloseIntent, intent)
                XCTAssertEqual(fixture.session.closePhase, .awaitingDecision)
                XCTAssertTrue(fixture.owner.isValid)
                fixture.files.beforeWrite = nil
                let approval = try requireApproval(fixture.session.resolveCloseIntent(id: intent.id, choice: .save))
                XCTAssertEqual(approval.intent.id, intent.id)
                XCTAssertNotNil(approval.saveReceiptID)
                XCTAssertFalse(fixture.session.hasActiveOperation)
                XCTAssertTrue(fixture.session.reserveClose(approval: approval, isHostSettled: true))
            }
        }
    }

    func testSaveReceiptOutlivesItsIOOperationAndApprovalReservesExactlyOnce() async throws {
        try await MainActor.run {
            try withSessionFixture { fixture in
                fixture.setText("saved")
                let intent = try requireCloseIntent(fixture.session)
                let approval = try requireApproval(fixture.session.resolveCloseIntent(id: intent.id, choice: .save))
                XCTAssertFalse(fixture.session.hasActiveOperation)
                XCTAssertEqual(try Data(contentsOf: fixture.url), Data("saved".utf8))
                XCTAssertFalse(fixture.session.reserveClose(approval: approval, isHostSettled: false))
                XCTAssertTrue(fixture.session.reserveClose(approval: approval, isHostSettled: true))
                XCTAssertFalse(fixture.session.reserveClose(approval: approval, isHostSettled: true))
                XCTAssertEqual(fixture.session.closePhase, .attempting)
                XCTAssertTrue(fixture.owner.hasCloseCommitReservation)
                fixture.setText("focus callback must not dirty")
                fixture.manager.undo()
                guard case .busy = fixture.session.save() else { return XCTFail("Reserved close must block save") }
                XCTAssertEqual(fixture.session.document.text, "saved")
                XCTAssertEqual(fixture.files.committedWrites, 1)
                XCTAssertTrue(fixture.manager.canUndo)
            }
        }
    }

    func testFailedCloseReleasesWriteBarrierButCannotReuseConsumedApproval() async throws {
        try await MainActor.run {
            try withSessionFixture { fixture in
                let intent = try requireCloseIntent(fixture.session)
                let approval = try requireApproval(fixture.session.resolveCloseIntent(id: intent.id, choice: .discard))
                XCTAssertTrue(fixture.session.reserveClose(approval: approval, isHostSettled: true))
                fixture.session.releaseCloseReservation(approval)
                XCTAssertTrue(fixture.owner.isValid)
                XCTAssertFalse(fixture.owner.hasCloseCommitReservation)
                XCTAssertFalse(fixture.session.reserveClose(approval: approval, isHostSettled: true))
                fixture.setText("editable after failed destruction")
                XCTAssertEqual(fixture.session.document.text, "editable after failed destruction")
                XCTAssertEqual(fixture.session.closePhase, .idle)
            }
        }
    }

    func testWrongApprovalCannotReleaseAnAttemptingClose() async throws {
        try await MainActor.run {
            try withSessionFixture { fixture in
                let intent = try requireCloseIntent(fixture.session)
                let approval = try requireApproval(fixture.session.resolveCloseIntent(id: intent.id, choice: .discard))
                XCTAssertTrue(fixture.session.reserveClose(approval: approval, isHostSettled: true))
                let wrongApprovals = [
                    DocumentCloseApproval(
                        id: UUID(), intent: approval.intent, saveReceiptID: approval.saveReceiptID,
                        lastOperationID: approval.lastOperationID),
                    DocumentCloseApproval(
                        id: approval.id, intent: approval.intent, saveReceiptID: UUID(),
                        lastOperationID: approval.lastOperationID),
                    DocumentCloseApproval(
                        id: approval.id, intent: approval.intent, saveReceiptID: approval.saveReceiptID,
                        lastOperationID: UUID()),
                ]
                for wrong in wrongApprovals {
                    fixture.session.releaseCloseReservation(wrong)
                    XCTAssertEqual(fixture.session.closePhase, .attempting)
                    XCTAssertTrue(fixture.owner.hasCloseCommitReservation)
                    fixture.setText("rejected")
                    XCTAssertEqual(fixture.session.document.text, "A")
                }
                fixture.session.releaseCloseReservation(approval)
                XCTAssertFalse(fixture.owner.hasCloseCommitReservation)
            }
        }
    }

    func testMutationOrUnrelatedSaveInvalidatesQueuedApproval() async throws {
        try await MainActor.run {
            try withSessionFixture { fixture in
                let first = try requireCloseIntent(fixture.session)
                let firstApproval = try requireApproval(
                    fixture.session.resolveCloseIntent(id: first.id, choice: .discard))
                fixture.setText("newer")
                XCTAssertFalse(fixture.session.reserveClose(approval: firstApproval, isHostSettled: true))
                let second = try requireCloseIntent(fixture.session)
                let secondApproval = try requireApproval(
                    fixture.session.resolveCloseIntent(id: second.id, choice: .discard))
                _ = try requireSave(fixture.session.save())
                XCTAssertFalse(fixture.session.reserveClose(approval: secondApproval, isHostSettled: true))
                XCTAssertTrue(fixture.owner.isValid)
                XCTAssertEqual(fixture.session.closePhase, .idle)
            }
        }
    }

    func testHostPolicyChangeRevokesApprovalWithoutReleasingAnAlreadyReservedCommit() async throws {
        try await MainActor.run {
            try withSessionFixture { fixture in
                let first = try requireCloseIntent(fixture.session)
                let oldApproval = try requireApproval(
                    fixture.session.resolveCloseIntent(id: first.id, choice: .discard))
                fixture.session.invalidateCloseForHostChange()
                fixture.session.invalidateCloseForHostChange()
                XCTAssertNil(fixture.session.pendingCloseIntent)
                XCTAssertNil(fixture.session.closeApproval)
                XCTAssertFalse(fixture.session.reserveClose(approval: oldApproval, isHostSettled: true))
                XCTAssertEqual(fixture.session.mutationRevision, 0)

                let next = try requireCloseIntent(fixture.session)
                XCTAssertNotEqual(next.id, first.id)
                let current = try requireApproval(
                    fixture.session.resolveCloseIntent(id: next.id, choice: .discard))
                XCTAssertTrue(fixture.session.reserveClose(approval: current, isHostSettled: true))
                fixture.session.invalidateCloseForHostChange()
                XCTAssertEqual(fixture.session.closePhase, .attempting)
                XCTAssertTrue(fixture.owner.hasCloseCommitReservation)
                fixture.setText("blocked until the attempt finishes")
                XCTAssertEqual(fixture.session.document.text, "A")
                fixture.session.releaseCloseReservation(current)
                XCTAssertFalse(fixture.owner.hasCloseCommitReservation)
            }
        }
    }

    func testFailedSavePublicationCannotClearANewerDiscardApproval() async throws {
        try await MainActor.run {
            try withSessionFixture { fixture in
                let intent = try requireCloseIntent(fixture.session)
                fixture.files.beforeWrite = { throw SessionFixtureError.injected }
                var nestedApproval: DocumentCloseApproval?
                fixture.session.onChange = {
                    if fixture.session.closePhase == .awaitingDecision,
                        case .approved(let approval) = fixture.session.resolveCloseIntent(
                            id: intent.id, choice: .discard)
                    {
                        nestedApproval = approval
                    }
                }

                guard case .superseded = fixture.session.resolveCloseIntent(id: intent.id, choice: .save) else {
                    return XCTFail("The older failing save must not return a current decision")
                }

                let approval = try XCTUnwrap(nestedApproval)
                XCTAssertEqual(fixture.session.closeApproval, approval)
                XCTAssertEqual(fixture.session.closePhase, .approved)
                XCTAssertTrue(fixture.session.reserveClose(approval: approval, isHostSettled: true))
                XCTAssertTrue(fixture.session.isDirty)
                XCTAssertEqual(fixture.files.committedWrites, 0)
                XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.url.path))
            }
        }
    }

    func testNewerEditAfterCloseSaveCannotApproveDestruction() async throws {
        try await MainActor.run {
            try withSessionFixture { fixture in
                fixture.setText("written")
                let intent = try requireCloseIntent(fixture.session)
                fixture.files.afterWrite = { fixture.setText("unsaved newer revision") }
                guard case .superseded = fixture.session.resolveCloseIntent(id: intent.id, choice: .save) else {
                    return XCTFail("The newly dirty document cannot close")
                }
                XCTAssertEqual(try Data(contentsOf: fixture.url), Data("written".utf8))
                XCTAssertEqual(fixture.session.document.text, "unsaved newer revision")
                XCTAssertTrue(fixture.session.isDirty)
                XCTAssertNil(fixture.session.closeApproval)
                XCTAssertTrue(fixture.owner.isValid)
            }
        }
    }

    func testCleanLoadedDocumentStillRequiresFinalReservation() async throws {
        try await MainActor.run {
            try withSessionFixture(persisted: true) { fixture in
                guard case .approved(let approval) = fixture.session.requestClose(isHostSettled: true) else {
                    return XCTFail("Expected clean document approval")
                }
                XCTAssertTrue(fixture.owner.isValid)
                XCTAssertEqual(fixture.files.writeAttempts, 0)
                fixture.setText("late delegate edit")
                XCTAssertFalse(fixture.session.reserveClose(approval: approval, isHostSettled: true))
                XCTAssertTrue(fixture.session.isDirty)
                XCTAssertTrue(fixture.owner.isValid)
            }
        }
    }

    func testKnownReferenceDocumentIsRejectedInsteadOfClaimingValueUndo() async throws {
        try await MainActor.run {
            let owner = DocumentOwnerLease()
            let files = SessionFileService()
            XCTAssertThrowsError(
                try FileDocumentSession(
                    document: SessionReferenceDocument(), contentType: .utf8PlainText,
                    owner: owner, codec: .editable(SessionReferenceDocument.self),
                    files: files, undoManager: UndoManager()
                )
            ) { error in
                XCTAssertEqual(error as? DocumentSessionError, .referenceDocumentUnsupported)
            }
            XCTAssertEqual(files.writeAttempts, 0)
            XCTAssertEqual(files.choices, 0)
        }
    }

    func testPersistedInitializationCannotInventMissingURLOrBytes() async throws {
        try await MainActor.run {
            let owner = DocumentOwnerLease()
            let files = SessionFileService()
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("not-read-\(UUID().uuidString).txt")
            let invalidStates: [(URL?, Data?)] = [(url, nil), (nil, Data("A".utf8))]
            for (fileURL, bytes) in invalidStates {
                XCTAssertThrowsError(
                    try FileDocumentSession(
                        document: DemoPlainTextDocument(text: "A"), fileURL: fileURL,
                        contentType: .utf8PlainText, owner: owner,
                        codec: .editable(DemoPlainTextDocument.self), files: files, savedBytes: bytes
                    )
                ) { error in
                    XCTAssertEqual(error as? DocumentSessionError, .inconsistentPersistedState)
                }
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        }
    }

    func testEscapedModelDoesNotRetainOwnerOrKeepUndoEligible() async throws {
        try await MainActor.run {
            var owner: DocumentOwnerLease? = DocumentOwnerLease()
            weak var weakOwner = owner
            let manager = UndoManager()
            let session = try FileDocumentSession(
                document: DemoPlainTextDocument(text: "A"), contentType: .utf8PlainText,
                owner: try XCTUnwrap(owner), codec: .editable(DemoPlainTextDocument.self),
                files: SessionFileService(), undoManager: manager
            )
            let escaped = session.configuration().$document.text
            escaped.wrappedValue = "B"
            owner = nil
            XCTAssertNil(weakOwner)
            escaped.wrappedValue = "late"
            manager.undo()
            XCTAssertEqual(escaped.wrappedValue, "B")
            XCTAssertFalse(manager.canUndo)
            XCTAssertEqual(session.closePhase, .closed)
        }
    }

    func testTeardownRevokesBeforeReentrantCallbackPayloadReleaseExactlyOnce() async throws {
        try await MainActor.run {
            try withSessionFixture { fixture in
                fixture.setText("B")
                let escaped = fixture.session.configuration().$document.text
                var releases = 0
                installSessionReleaseProbe(fixture.session) {
                    releases += 1
                    escaped.wrappedValue = "cleanup write"
                    fixture.manager.undo()
                }
                fixture.session.invalidate()
                fixture.session.invalidate()
                XCTAssertEqual(releases, 1)
                XCTAssertEqual(fixture.session.document.text, "B")
                XCTAssertFalse(fixture.manager.canUndo)
                XCTAssertFalse(fixture.owner.isValid)
            }
        }
    }

    func testReadOnlySaveAndErrorClearDoNotPublishInsideCloseReservation() async throws {
        try await MainActor.run {
            try withSessionFixture(persisted: true, editable: false) { fixture in
                guard case .failed = fixture.session.save() else { return XCTFail("Expected read-only") }
                guard case .approved(let approval) = fixture.session.requestClose(isHostSettled: true) else {
                    return XCTFail("Expected the persisted document's approval")
                }
                var changes = 0
                fixture.session.onChange = { changes += 1 }
                XCTAssertTrue(fixture.session.reserveClose(approval: approval, isHostSettled: true))
                guard case .busy = fixture.session.save() else { return XCTFail("Reservation must win") }
                fixture.session.clearError()
                XCTAssertEqual(changes, 0)
                XCTAssertNotNil(fixture.session.lastError)
                XCTAssertEqual(fixture.files.writeAttempts, 0)
            }
        }
    }

    func testErrorPayloadReleaseCannotPublishAfterItReservesClose() async throws {
        try await MainActor.run {
            try withSessionFixture(persisted: true) { fixture in
                var approval: DocumentCloseApproval?
                var didReserve = false
                var releases = 0
                weak var releasedError: SessionReleaseError?
                fixture.files.beforeWrite = {
                    let error = SessionReleaseError {
                        releases += 1
                        if case .approved(let current) = fixture.session.requestClose(isHostSettled: true) {
                            approval = current
                            didReserve = fixture.session.reserveClose(approval: current, isHostSettled: true)
                        }
                    }
                    releasedError = error
                    throw error
                }
                guard case .failed = fixture.session.save() else { return XCTFail("Expected an injected error") }
                fixture.files.beforeWrite = nil
                XCTAssertNotNil(releasedError)
                XCTAssertFalse(fixture.session.isDirty)
                var changes = 0
                fixture.session.onChange = { changes += 1 }

                fixture.session.clearError()

                XCTAssertNil(releasedError)
                XCTAssertEqual(releases, 1)
                XCTAssertTrue(didReserve)
                XCTAssertEqual(fixture.session.closePhase, .attempting)
                XCTAssertEqual(changes, 0)
                XCTAssertNil(fixture.session.lastError)
                fixture.session.releaseCloseReservation(try XCTUnwrap(approval))
                XCTAssertEqual(changes, 1)
                XCTAssertEqual(fixture.session.closePhase, .idle)
            }
        }
    }

    func testInvalidationReleasesErrorPayloadAfterRevokingModelAndHistoryWrites() async throws {
        try await MainActor.run {
            try withSessionFixture(persisted: true) { fixture in
                fixture.setText("B")
                let escaped = fixture.session.configuration().$document.text
                var releases = 0
                weak var releasedError: SessionReleaseError?
                fixture.files.beforeWrite = {
                    let error = SessionReleaseError {
                        releases += 1
                        escaped.wrappedValue = "cleanup must not write"
                        fixture.manager.undo()
                        XCTAssertEqual(fixture.session.requestClose(isHostSettled: true), .unavailable)
                    }
                    releasedError = error
                    throw error
                }
                guard case .failed = fixture.session.save() else { return XCTFail("Expected an injected error") }
                fixture.files.beforeWrite = nil
                XCTAssertNotNil(releasedError)
                var changes = 0
                fixture.session.onChange = { changes += 1 }

                fixture.session.invalidate()
                fixture.session.invalidate()

                XCTAssertNil(releasedError)
                XCTAssertEqual(releases, 1)
                XCTAssertEqual(changes, 0)
                XCTAssertEqual(fixture.session.document.text, "B")
                XCTAssertFalse(fixture.manager.canUndo)
                XCTAssertFalse(fixture.owner.isValid)
                XCTAssertNil(fixture.session.lastError)
                XCTAssertEqual(fixture.session.closePhase, .closed)
                XCTAssertEqual(try Data(contentsOf: fixture.url), Data("A".utf8))
            }
        }
    }

    func testClosePublicationCannotReturnAnIntentCancelledByItsCallback() async throws {
        try await MainActor.run {
            try withSessionFixture { fixture in
                fixture.session.onChange = {
                    if let intent = fixture.session.pendingCloseIntent {
                        _ = fixture.session.resolveCloseIntent(id: intent.id, choice: .cancel)
                    }
                }
                XCTAssertEqual(fixture.session.requestClose(isHostSettled: true), .unavailable)
                XCTAssertNil(fixture.session.pendingCloseIntent)
                XCTAssertEqual(fixture.session.closePhase, .idle)
                XCTAssertTrue(fixture.owner.isValid)
            }
        }
    }

    func testClosePublicationReturnsTheApprovalCreatedByItsCallback() async throws {
        try await MainActor.run {
            try withSessionFixture { fixture in
                var callbackApproval: DocumentCloseApproval?
                fixture.session.onChange = {
                    if let intent = fixture.session.pendingCloseIntent,
                        case .approved(let approval) = fixture.session.resolveCloseIntent(
                            id: intent.id, choice: .discard)
                    {
                        callbackApproval = approval
                    }
                }
                let result = fixture.session.requestClose(isHostSettled: true)
                let expected = try XCTUnwrap(callbackApproval)
                XCTAssertEqual(result, .approved(expected))
                XCTAssertEqual(fixture.session.closePhase, .approved)
                XCTAssertEqual(fixture.files.committedWrites, 0)
            }
        }
    }

    func testClosePublicationCannotReturnAnOlderReplacedIntentAtSameRevision() async throws {
        try await MainActor.run {
            try withSessionFixture { fixture in
                var didReplace = false
                var replacement: DocumentCloseIntent?
                fixture.session.onChange = {
                    if !didReplace, let intent = fixture.session.pendingCloseIntent {
                        didReplace = true
                        _ = fixture.session.resolveCloseIntent(id: intent.id, choice: .cancel)
                        if case .needsDecision(let next) = fixture.session.requestClose(isHostSettled: true) {
                            replacement = next
                        }
                    }
                }
                XCTAssertEqual(fixture.session.requestClose(isHostSettled: true), .unavailable)
                let expected = try XCTUnwrap(replacement)
                XCTAssertEqual(fixture.session.pendingCloseIntent, expected)
                XCTAssertEqual(fixture.session.requestClose(isHostSettled: true), .awaitingDecision(expected))
                XCTAssertEqual(fixture.session.mutationRevision, 0)
            }
        }
    }

    func testUnsettledHostCreatesNoCloseIntentOrApplicationCallback() async throws {
        try await MainActor.run {
            try withSessionFixture { fixture in
                var changes = 0
                fixture.session.onChange = { changes += 1 }
                XCTAssertEqual(fixture.session.requestClose(isHostSettled: false), .busy)
                XCTAssertNil(fixture.session.pendingCloseIntent)
                XCTAssertEqual(changes, 0)
                XCTAssertTrue(fixture.owner.isValid)
            }
        }
    }
}

extension FileDocumentSessionTests {
    func testRecursiveErrorClearDuringPayloadReleasePublishesOnlyAfterTheNestedCallReturns() async throws {
        try await MainActor.run {
            try withSessionFixture(persisted: true) { fixture in
                let session = fixture.session
                var releases = 0
                var nestedReturns = 0
                var changes = 0
                var events: [String] = []
                weak var releasedError: SessionReleaseError?
                fixture.files.beforeWrite = { [weak session] in
                    let error = SessionReleaseError { [weak session] in
                        releases += 1
                        events.append("release")
                        guard let session else { return XCTFail("The caller still owns the live session.") }
                        session.clearError()
                        nestedReturns += 1
                        events.append("nested returned")
                        XCTAssertNil(session.lastError)
                        XCTAssertEqual(changes, 0, "The recursive clear of nil must not publish.")
                    }
                    releasedError = error
                    throw error
                }
                defer {
                    fixture.files.beforeWrite = nil
                    session.onChange = nil
                }
                // Do not bind or retain the failed outcome's associated error.
                // After this statement only lastError owns the thrown payload.
                guard case .failed = session.save() else { return XCTFail("Expected the injected save failure") }
                fixture.files.beforeWrite = nil
                XCTAssertNotNil(releasedError)
                XCTAssertNotNil(session.lastError)
                XCTAssertEqual(releases, 0)
                XCTAssertFalse(session.hasActiveOperation)
                XCTAssertFalse(fixture.owner.hasCloseCommitReservation)
                session.onChange = {
                    changes += 1
                    events.append("change")
                }

                events.append("outer call")
                session.clearError()
                events.append("outer returned")

                XCTAssertNil(releasedError)
                XCTAssertNil(session.lastError)
                XCTAssertEqual(releases, 1)
                XCTAssertEqual(nestedReturns, 1)
                XCTAssertEqual(changes, 1)
                XCTAssertEqual(events, ["outer call", "release", "nested returned", "change", "outer returned"])
                XCTAssertTrue(fixture.owner.isValid)
                XCTAssertEqual(fixture.owner.generation, 0)
                XCTAssertTrue(session.documentUndoIsValid)
                XCTAssertFalse(fixture.owner.hasCloseCommitReservation)
                XCTAssertFalse(session.hasActiveOperation)
                XCTAssertEqual(session.closePhase, .idle)
                XCTAssertNil(session.pendingCloseIntent)
                XCTAssertNil(session.closeApproval)
                XCTAssertEqual(fixture.files.writeAttempts, 1)
                XCTAssertEqual(fixture.files.committedWrites, 0)

                session.clearError()
                XCTAssertEqual(changes, 1)
                XCTAssertEqual(releases, 1)
            }
        }
    }
}

@MainActor
private final class SessionErrorRetryFiles: DocumentFileService {
    var storedBytes: [URL: Data] = [:]
    var beforeWrite: (() throws -> Void)?
    private(set) var openChoices = 0
    private(set) var saveChoices = 0
    private(set) var reads = 0
    private(set) var writeAttempts = 0
    private(set) var serializations = 0
    private(set) var validations = 0
    private(set) var committedWrites = 0

    func chooseOpenURL(types: [UTType], owner: FileDialogOwner) -> FileDialogOutcome<URL> {
        openChoices += 1
        return .cancelled
    }

    func chooseSaveURL(
        name: String?, directory: URL?, type: UTType, owner: FileDialogOwner
    ) -> FileDialogOutcome<URL> {
        saveChoices += 1
        return .cancelled
    }

    func readRegularFile(at url: URL, maximumBytes: Int) throws -> Data {
        reads += 1
        throw SessionFixtureError.injected
    }

    func writeRegularFile(
        to url: URL, provideData: @MainActor (URL) throws -> Data,
        validate: @MainActor () throws -> Void
    ) throws -> Data {
        writeAttempts += 1
        try beforeWrite?()
        validations += 1
        try validate()
        serializations += 1
        let bytes = try provideData(url)
        validations += 1
        try validate()
        // Only this dictionary is committed; no filesystem or native dialog
        // participates in the session's error-release/retry regression.
        storedBytes[url] = bytes
        committedWrites += 1
        return bytes
    }
}

extension FileDocumentSessionTests {
    func testSaveRetryCanRecursivelyClearTheReleasedErrorBeforePublishingItsOperation() async throws {
        try await MainActor.run {
            let owner = DocumentOwnerLease()
            let files = SessionErrorRetryFiles()
            let url = URL(fileURLWithPath: "C:/in-memory-document-retry.txt", isDirectory: false)
            let originalBytes = Data("A".utf8)
            files.storedBytes[url] = originalBytes
            let base = DocumentCodec<DemoPlainTextDocument>.editable(DemoPlainTextDocument.self)
            let encode = try XCTUnwrap(base.encode)
            var encodings = 0
            let codec = DocumentCodec<DemoPlainTextDocument>(
                decode: base.decode,
                encode: { document, type in
                    encodings += 1
                    return try encode(document, type)
                }
            )
            let session = try FileDocumentSession(
                document: DemoPlainTextDocument(text: "A"), fileURL: url, contentType: .utf8PlainText,
                owner: owner, codec: codec, files: files, savedBytes: originalBytes
            )
            defer {
                files.beforeWrite = nil
                session.onChange = nil
                session.invalidate()
            }
            session.configuration().$document.text.wrappedValue = "B"
            let checkpoint = session.currentCheckpoint
            let savedBefore = session.savedCheckpoint
            let revision = session.mutationRevision
            var releases = 0
            var nestedReturns = 0
            var publicationStates: [Bool] = []
            var events: [String] = []
            weak var releasedError: SessionReleaseError?
            files.beforeWrite = { [weak session] in
                let error = SessionReleaseError { [weak session] in
                    releases += 1
                    events.append("release")
                    guard let session else { return XCTFail("The retry still owns its live session.") }
                    XCTAssertTrue(session.hasActiveOperation)
                    session.clearError()
                    nestedReturns += 1
                    events.append("nested returned")
                    XCTAssertNil(session.lastError)
                    XCTAssertTrue(publicationStates.isEmpty, "Clearing the already-nil error cannot publish.")
                    XCTAssertEqual(encodings, 0)
                }
                releasedError = error
                throw error
            }
            // Discard the failed outcome, leaving only the session's lastError
            // as an owner of the payload that the next save must release.
            guard case .failed = session.save(to: url) else { return XCTFail("Expected the initial save failure") }
            files.beforeWrite = nil
            XCTAssertNotNil(releasedError)
            XCTAssertNotNil(session.lastError)
            XCTAssertEqual(releases, 0)
            XCTAssertTrue(session.isDirty)
            XCTAssertFalse(session.hasActiveOperation)
            XCTAssertEqual(session.savedCheckpoint, savedBefore)
            XCTAssertEqual(files.storedBytes[url], originalBytes)
            XCTAssertEqual(files.writeAttempts, 1)
            XCTAssertEqual(files.committedWrites, 0)
            XCTAssertEqual(files.serializations, 0)
            XCTAssertEqual(files.validations, 0)
            XCTAssertEqual(encodings, 0)
            session.onChange = { [weak session] in
                guard let session else { return XCTFail("The save owns its session during publication.") }
                publicationStates.append(session.hasActiveOperation)
                events.append(session.hasActiveOperation ? "active change" : "settled change")
            }

            events.append("retry")
            let receipt = try requireSave(session.save(to: url))
            events.append("retry returned")

            XCTAssertNil(releasedError)
            XCTAssertNil(session.lastError)
            XCTAssertEqual(releases, 1)
            XCTAssertEqual(nestedReturns, 1)
            XCTAssertEqual(publicationStates, [true, false])
            XCTAssertEqual(
                events, ["retry", "release", "nested returned", "active change", "settled change", "retry returned"])
            XCTAssertEqual(receipt.url, url)
            XCTAssertEqual(receipt.bytes, Data("B".utf8))
            XCTAssertEqual(receipt.checkpoint, checkpoint)
            XCTAssertEqual(receipt.ticket.sessionID, session.sessionID)
            XCTAssertEqual(receipt.ticket.mutationRevision, revision)
            XCTAssertEqual(session.mutationRevision, revision)
            XCTAssertEqual(session.savedCheckpoint, checkpoint)
            XCTAssertEqual(session.savedBytes, receipt.bytes)
            XCTAssertEqual(files.storedBytes[url], receipt.bytes)
            XCTAssertEqual(files.writeAttempts, 2)
            XCTAssertEqual(files.committedWrites, 1)
            XCTAssertEqual(files.serializations, 1)
            XCTAssertEqual(files.validations, 2)
            XCTAssertEqual(encodings, 1)
            XCTAssertEqual(files.openChoices, 0)
            XCTAssertEqual(files.saveChoices, 0)
            XCTAssertEqual(files.reads, 0)
            XCTAssertFalse(session.isDirty)
            XCTAssertFalse(session.hasActiveOperation)
            XCTAssertEqual(session.closePhase, .idle)
            XCTAssertNil(session.pendingCloseIntent)
            XCTAssertNil(session.closeApproval)
            XCTAssertTrue(owner.isValid)
            XCTAssertTrue(session.documentUndoIsValid)
            XCTAssertFalse(owner.hasCloseCommitReservation)
        }
    }
}
