import Foundation
import SwiftWindowsCore
import SwiftWindowsPlatform
import SwiftWindowsUI

/// The owner is separate from the readable model. An escaped binding may keep
/// its model alive, but it cannot keep a window or its write authority alive.
@MainActor
final class DocumentOwnerLease {
    let ownerID = UUID()
    private(set) var generation: UInt64 = 0
    private(set) var isValid = true
    private(set) weak var runtime: RetainedViewRuntime?
    private var closeReservation: UUID?
    private var dialogOwnerProvider: @MainActor () -> FileDialogOwner = { .hosted(nil) }

    var hasCloseCommitReservation: Bool { closeReservation != nil }

    func bind(
        runtime: RetainedViewRuntime,
        dialogOwner: @escaping @MainActor () -> FileDialogOwner
    ) {
        guard isValid else { return }
        self.runtime = runtime
        dialogOwnerProvider = dialogOwner
    }

    func dialogOwner() -> FileDialogOwner {
        guard isValid, closeReservation == nil else { return .hosted(nil) }
        return dialogOwnerProvider()
    }

    /// Capability revocation must precede releasing callbacks or model/history
    /// payloads. In particular this phase does not invoke the owner provider.
    func revoke() {
        guard isValid else { return }
        isValid = false
        generation += 1
        closeReservation = nil
    }

    fileprivate func reserveClose(_ approvalID: UUID) -> Bool {
        guard isValid, closeReservation == nil else { return false }
        closeReservation = approvalID
        return true
    }

    fileprivate func releaseClose(_ approvalID: UUID) {
        guard isValid, closeReservation == approvalID else { return }
        closeReservation = nil
    }
}

enum DocumentSessionError: Error, LocalizedError, Equatable {
    case referenceDocumentUnsupported
    case ownerUnavailable
    case readOnly
    case inconsistentPersistedState
    case supersededOperation
    case revisionExhausted

    var errorDescription: String? {
        switch self {
        case .referenceDocumentUnsupported:
            return "This document stage requires a value-semantic regular-file document."
        case .ownerUnavailable:
            return "The document's owning window is no longer available."
        case .readOnly:
            return "This document is not editable."
        case .inconsistentPersistedState:
            return "A persisted document requires both its file URL and the bytes that were read."
        case .supersededOperation:
            return "The document changed before this file operation could finish."
        case .revisionExhausted:
            return "The document can no longer allocate a safe mutation revision."
        }
    }
}

struct DocumentCheckpoint: Equatable, Sendable {
    let id: UUID

    init(id: UUID = UUID()) {
        self.id = id
    }
}

struct DocumentIOTicket: Equatable, Sendable {
    let ownerID: UUID
    let ownerGeneration: UInt64
    let sessionID: UUID
    let operationID: UUID
    let mutationRevision: UInt64
}

struct DocumentSaveReceipt: Sendable {
    let id: UUID
    let ticket: DocumentIOTicket
    let checkpoint: DocumentCheckpoint
    let url: URL
    let bytes: Data
}

enum DocumentSaveOutcome {
    case saved(DocumentSaveReceipt, isCurrentRevision: Bool)
    case cancelled
    case failed(Error)
    case superseded(written: DocumentSaveReceipt?)
    case busy
}

struct DocumentCloseIntent: Equatable, Sendable {
    let id: UUID
    let ownerID: UUID
    let ownerGeneration: UInt64
    let sessionID: UUID
    let mutationRevision: UInt64
    let checkpoint: DocumentCheckpoint
}

struct DocumentCloseApproval: Equatable, Sendable {
    let id: UUID
    let intent: DocumentCloseIntent
    let saveReceiptID: UUID?
    let lastOperationID: UUID?
}

enum DocumentCloseChoice: Sendable {
    case save
    case discard
    case cancel
}

enum DocumentClosePhase: Equatable, Sendable {
    case idle
    case awaitingDecision
    case saving
    case approved
    case attempting
    case closed
}

enum DocumentCloseRequest: Equatable, Sendable {
    case needsDecision(DocumentCloseIntent)
    case awaitingDecision(DocumentCloseIntent)
    case approved(DocumentCloseApproval)
    case busy
    case unavailable
}

enum DocumentCloseResolution {
    case approved(DocumentCloseApproval)
    case cancelled
    case failed(Error)
    case superseded
    case busy
}

/// This synchronous stage owns value inverses for one regular-file model.
/// Known class documents are rejected; a struct containing mutable reference
/// aliases still requires an independently established value-semantics contract.
@MainActor
final class FileDocumentSession<Document: FileDocument>: DocumentTextUndoOwner {
    private enum SaveDestination {
        case current
        case choose
        case explicit(URL)
    }

    private enum OperationPhase {
        case choosing
        case serializing
        case writing
    }

    private struct Operation {
        let ticket: DocumentIOTicket
        let checkpoint: DocumentCheckpoint
        var phase: OperationPhase
    }

    let sessionID = UUID()
    private(set) var document: Document
    private(set) var fileURL: URL?
    let contentType: UTType
    let isEditable: Bool
    private(set) var mutationRevision: UInt64 = 0
    private(set) var currentCheckpoint = DocumentCheckpoint()
    private(set) var savedCheckpoint: DocumentCheckpoint?
    private(set) var savedBytes: Data?
    private(set) var lastError: Error?
    private(set) var pendingCloseIntent: DocumentCloseIntent?
    private(set) var closeApproval: DocumentCloseApproval?
    private(set) var closePhase: DocumentClosePhase = .idle
    var onChange: (@MainActor () -> Void)?

    private weak var owner: DocumentOwnerLease?
    private let ownerID: UUID
    private let ownerGeneration: UInt64
    private let codec: DocumentCodec<Document>
    private let files: any DocumentFileService
    private let undoManager: UndoManager?
    private var undoGeneration: UInt64 = 0
    private var isInvalidated = false
    private var isApplyingMutation = false
    private var isReplaying = false
    private var operation: Operation?
    private var attemptingApproval: DocumentCloseApproval?
    private var lastOperationID: UUID?
    private var lastSaveReceiptID: UUID?
    private lazy var bindingSource = DocumentBindingSource(owner: self)

    init(
        document: Document,
        fileURL: URL? = nil,
        contentType: UTType,
        isEditable: Bool = true,
        owner: DocumentOwnerLease,
        codec: DocumentCodec<Document>,
        files: any DocumentFileService,
        undoManager: UndoManager? = nil,
        savedBytes: Data? = nil
    ) throws {
        guard !(Document.self is AnyClass) else {
            throw DocumentSessionError.referenceDocumentUnsupported
        }
        guard owner.isValid else { throw DocumentSessionError.ownerUnavailable }
        guard (fileURL == nil) == (savedBytes == nil) else {
            throw DocumentSessionError.inconsistentPersistedState
        }
        if let fileURL, !fileURL.isFileURL {
            throw DocumentFileServiceError.invalidFileURL
        }
        guard !isEditable || codec.encode != nil else { throw DocumentSessionError.readOnly }
        self.document = document
        self.fileURL = fileURL
        self.contentType = contentType
        self.isEditable = isEditable
        self.owner = owner
        self.ownerID = owner.ownerID
        self.ownerGeneration = owner.generation
        self.codec = codec
        self.files = files
        self.undoManager = undoManager
        self.savedBytes = savedBytes
        if savedBytes != nil { savedCheckpoint = currentCheckpoint }
    }

    var isDirty: Bool { savedCheckpoint != currentCheckpoint }
    var hasActiveOperation: Bool { operation != nil }
    var documentUndoManager: UndoManager? { undoManager }
    var documentUndoGeneration: UInt64 { undoGeneration }
    var documentMutationRevision: UInt64 { mutationRevision }
    var documentUndoIsValid: Bool { ownerIsCurrent && !isInvalidated }
    var documentAllowsTextMutation: Bool {
        documentUndoIsValid && isEditable && !isApplyingMutation && !isReplaying
            && owner?.hasCloseCommitReservation == false
    }

    func documentUndoBelongs(to runtime: RetainedViewRuntime) -> Bool {
        documentUndoIsValid && owner?.runtime === runtime
    }

    func configuration() -> FileDocumentConfiguration<Document> {
        let binding = Binding<Document>(
            get: { self.document },
            set: { value, _, mutation in self.accept(value, mutation: mutation) },
            isValidForWrite: { self.documentAllowsTextMutation },
            mutationSource: bindingSource
        )
        return FileDocumentConfiguration(document: binding, fileURL: fileURL, isEditable: isEditable)
    }

    func prepareForUndoReplay() -> Bool {
        guard documentUndoIsValid else {
            invalidate()
            return false
        }
        return documentAllowsTextMutation && bindingSource.permitsReplay
    }

    func save() -> DocumentSaveOutcome {
        performSave(destination: .current, forCloseIntent: nil)
    }

    func saveAs() -> DocumentSaveOutcome {
        performSave(destination: .choose, forCloseIntent: nil)
    }

    func save(to url: URL) -> DocumentSaveOutcome {
        performSave(destination: .explicit(url), forCloseIntent: nil)
    }

    func clearError() {
        guard ownerIsCurrent, owner?.hasCloseCommitReservation == false, lastError != nil else { return }
        releaseLastError()
        publishChange()
    }

    private func releaseLastError() {
        // An error's destructor can call clearError or reserve a close. Keep
        // it alive until the stored mutation ends, then release it before
        // publishChange rechecks the current owner's reservation.
        var displacedError = lastError
        lastError = nil
        withExtendedLifetime(displacedError) {}
        displacedError = nil
    }

    /// A settled host policy change revokes a queued decision even if the
    /// document bytes did not change. Toggling a veto off again must not revive
    /// the former approval. A final commit reservation has already linearized
    /// acceptance and remains in force until teardown or failed-attempt release.
    func invalidateCloseForHostChange() {
        guard !isInvalidated, closePhase != .closed, closePhase != .attempting,
            owner?.hasCloseCommitReservation != true
        else { return }
        clearCloseIntent()
    }

    func requestClose(isHostSettled: Bool) -> DocumentCloseRequest {
        guard ownerIsCurrent, !isInvalidated else { return .unavailable }
        guard isHostSettled, !isApplyingMutation, !isReplaying,
            owner?.hasCloseCommitReservation == false
        else { return .busy }

        if let approval = closeApproval, isCurrent(approval) {
            return .approved(approval)
        }
        if let intent = pendingCloseIntent, isCurrent(intent) {
            return .awaitingDecision(intent)
        }
        guard operation == nil else { return .busy }
        let intent = DocumentCloseIntent(
            id: UUID(), ownerID: ownerID, ownerGeneration: ownerGeneration,
            sessionID: sessionID, mutationRevision: mutationRevision,
            checkpoint: currentCheckpoint
        )
        pendingCloseIntent = intent
        if !isDirty {
            let approval = approve(intent, saveReceiptID: nil)
            return .approved(approval)
        }
        closePhase = .awaitingDecision
        publishChange()
        guard isCurrent(intent), pendingCloseIntent == intent else { return .unavailable }
        if let approval = closeApproval, closePhase == .approved, isCurrent(approval) {
            return .approved(approval)
        }
        guard closePhase == .awaitingDecision else { return .busy }
        return .needsDecision(intent)
    }

    func resolveCloseIntent(id: UUID, choice: DocumentCloseChoice) -> DocumentCloseResolution {
        guard let intent = pendingCloseIntent, intent.id == id, isCurrent(intent) else {
            return .superseded
        }
        guard closePhase == .awaitingDecision, operation == nil,
            !isApplyingMutation, !isReplaying, owner?.hasCloseCommitReservation == false
        else { return .busy }
        switch choice {
        case .cancel:
            clearCloseIntent()
            publishChange()
            return .cancelled
        case .discard:
            return .approved(approve(intent, saveReceiptID: nil))
        case .save:
            closePhase = .saving
            let outcome = performSave(destination: .current, forCloseIntent: id)
            guard isCurrent(intent), pendingCloseIntent?.id == id else { return .superseded }
            switch outcome {
            case .saved(let receipt, let isCurrentRevision):
                guard isCurrentRevision, receipt.ticket.mutationRevision == mutationRevision,
                    receipt.checkpoint == currentCheckpoint, savedCheckpoint == currentCheckpoint,
                    lastSaveReceiptID == receipt.id
                else {
                    clearCloseIntent()
                    publishChange()
                    return .superseded
                }
                return .approved(approve(intent, saveReceiptID: receipt.id))
            case .cancelled:
                clearCloseIntent()
                publishChange()
                return .cancelled
            case .failed(let error):
                closePhase = .awaitingDecision
                publishChange()
                guard isCurrent(intent), pendingCloseIntent == intent, closePhase == .awaitingDecision else {
                    return .superseded
                }
                return .failed(error)
            case .superseded:
                clearCloseIntent()
                publishChange()
                return .superseded
            case .busy:
                closePhase = .awaitingDecision
                return .busy
            }
        }
    }

    /// The caller must supply the final owned host/build/policy check AFTER
    /// every delegate vote. This method runs no application callback. The
    /// reservation also rejects writes from synchronous DestroyWindow focus
    /// callbacks; merely reading a clean checkpoint is insufficient.
    func reserveClose(approval: DocumentCloseApproval, isHostSettled: Bool) -> Bool {
        guard isHostSettled, closePhase == .approved, closeApproval == approval,
            isCurrent(approval), operation == nil, !isApplyingMutation, !isReplaying,
            let owner, owner.reserveClose(approval.id)
        else { return false }
        closePhase = .attempting
        attemptingApproval = approval
        closeApproval = nil
        return true
    }

    /// Failed destruction restores editing, but never restores the consumed
    /// approval. Actual teardown is recorded only by invalidate().
    func releaseCloseReservation(_ approval: DocumentCloseApproval) {
        guard ownerIsCurrent, closePhase == .attempting, attemptingApproval == approval,
            pendingCloseIntent?.id == approval.intent.id
        else { return }
        owner?.releaseClose(approval.id)
        attemptingApproval = nil
        clearCloseIntent()
        publishChange()
    }

    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        undoGeneration += 1
        owner?.revoke()
        closePhase = .closed
        pendingCloseIntent = nil
        closeApproval = nil
        attemptingApproval = nil
        operation = nil
        // Releasing a callback or history payload may execute application code;
        // every model capability is already revoked before those releases.
        onChange = nil
        lastError = nil
        undoManager?.removeAllActions(withTarget: self)
    }

    private var ownerIsCurrent: Bool {
        guard let owner else { return false }
        return owner.isValid && owner.ownerID == ownerID && owner.generation == ownerGeneration
    }

    private func accept(_ value: Document, mutation: (any BindingMutationContext)?) {
        guard documentAllowsTextMutation else { return }
        let ticket: DocumentTextEditTicket?
        if let mutation {
            guard let candidate = mutation as? DocumentTextEditTicket, candidate.consume(for: self) else { return }
            ticket = candidate
        } else {
            ticket = nil
        }
        guard mutationRevision < UInt64.max else {
            invalidate()
            lastError = DocumentSessionError.revisionExhausted
            return
        }

        isApplyingMutation = true
        let previous = document
        let previousCheckpoint = currentCheckpoint
        document = value
        mutationRevision += 1
        currentCheckpoint = DocumentCheckpoint()
        clearCloseIntent()
        let receipt = ticket?.didCommit(for: self, revision: mutationRevision)
        recordInverse(document: previous, checkpoint: previousCheckpoint, receipt: receipt)
        isApplyingMutation = false
        publishChange()
    }

    private func recordInverse(
        document previous: Document,
        checkpoint: DocumentCheckpoint,
        receipt: DocumentTextUndoReceipt?
    ) {
        guard documentUndoIsValid, let undoManager else { return }
        let generation = undoGeneration
        _ = undoManager.registerUndo(withTarget: self, actionName: "Edit Document") { session in
            session.replay(document: previous, checkpoint: checkpoint, receipt: receipt)
        }
        // Pruning old targets or releasing redo payloads can retire this owner.
        // Never clear another document's or a manual application's actions.
        if !documentUndoIsValid || undoGeneration != generation {
            undoManager.removeAllActions(withTarget: self)
        }
    }

    private func replay(
        document previous: Document,
        checkpoint: DocumentCheckpoint,
        receipt: DocumentTextUndoReceipt?
    ) {
        guard documentAllowsTextMutation, bindingSource.permitsReplay,
            mutationRevision < UInt64.max
        else { return }
        isReplaying = true
        defer { isReplaying = false }
        let generation = undoGeneration
        let revisionBeforePreparation = mutationRevision
        let selection = receipt?.prepareSelectionReplay(for: self, undoing: undoManager?.isUndoing ?? true)
        guard documentUndoIsValid, undoGeneration == generation,
            mutationRevision == revisionBeforePreparation, bindingSource.permitsReplay
        else { return }
        let inverse = document
        let inverseCheckpoint = currentCheckpoint
        document = previous
        currentCheckpoint = checkpoint
        mutationRevision += 1
        clearCloseIntent()
        let acceptedRevision = mutationRevision
        recordInverse(document: inverse, checkpoint: inverseCheckpoint, receipt: receipt)
        guard documentUndoIsValid, undoGeneration == generation, mutationRevision == acceptedRevision else { return }
        publishChange()
        guard documentUndoIsValid, undoGeneration == generation, mutationRevision == acceptedRevision else { return }
        selection?.restore(for: self, revision: acceptedRevision)
    }

    private func performSave(destination: SaveDestination, forCloseIntent closeIntentID: UUID?) -> DocumentSaveOutcome {
        guard ownerIsCurrent, !isInvalidated else { return .superseded(written: nil) }
        guard operation == nil, !isApplyingMutation, !isReplaying,
            owner?.hasCloseCommitReservation == false
        else { return .busy }
        guard isEditable, let encode = codec.encode else {
            return reportFailure(DocumentSessionError.readOnly)
        }

        let ticket = DocumentIOTicket(
            ownerID: ownerID, ownerGeneration: ownerGeneration, sessionID: sessionID,
            operationID: UUID(), mutationRevision: mutationRevision
        )
        let checkpoint = currentCheckpoint
        let snapshot = document
        operation = Operation(ticket: ticket, checkpoint: checkpoint, phase: .choosing)
        lastOperationID = ticket.operationID
        if closeIntentID == nil || pendingCloseIntent?.id != closeIntentID { clearCloseIntent() }
        releaseLastError()
        publishChange()

        let destinationURL: URL
        do {
            try validate(ticket)
            switch destination {
            case .explicit(let url):
                destinationURL = url
            case .current, .choose:
                if case .current = destination, let fileURL {
                    destinationURL = fileURL
                    break
                }
                guard let owner else { throw DocumentSessionError.ownerUnavailable }
                let dialogOwner = owner.dialogOwner()
                try validate(ticket)
                let result = files.chooseSaveURL(
                    name: fileURL?.lastPathComponent,
                    directory: fileURL?.deletingLastPathComponent(),
                    type: contentType, owner: dialogOwner
                )
                try validate(ticket)
                switch result {
                case .selected(let url): destinationURL = url
                case .cancelled:
                    endOperation(ticket)
                    publishChange()
                    return ownerIsCurrent && lastOperationID == ticket.operationID
                        ? .cancelled : .superseded(written: nil)
                case .failed(let error): throw error
                }
            }
            try validate(ticket)
            guard destinationURL.isFileURL else { throw DocumentFileServiceError.invalidFileURL }
        } catch {
            return finishFailedOperation(ticket, error: error)
        }

        let bytes: Data
        do {
            bytes = try files.writeRegularFile(
                to: destinationURL,
                provideData: { [weak self] _ in
                    guard let self else { throw DocumentSessionError.ownerUnavailable }
                    try self.validate(ticket)
                    self.operation?.phase = .serializing
                    let data = try encode(snapshot, self.contentType)
                    try self.validate(ticket)
                    self.operation?.phase = .writing
                    return data
                },
                validate: { [weak self] in
                    guard let self else { throw DocumentSessionError.ownerUnavailable }
                    try self.validate(ticket)
                }
            )
        } catch {
            return finishFailedOperation(ticket, error: error)
        }

        let receipt = DocumentSaveReceipt(
            id: UUID(), ticket: ticket, checkpoint: checkpoint, url: destinationURL, bytes: bytes
        )
        guard ownerIsCurrent, !isInvalidated, operation?.ticket == ticket else {
            endOperation(ticket)
            return .superseded(written: receipt)
        }
        // These bytes have already been written. A newer model revision stays
        // dirty, but it does not erase the fact or destination of that save.
        fileURL = destinationURL
        savedCheckpoint = checkpoint
        savedBytes = bytes
        lastSaveReceiptID = receipt.id
        lastError = nil
        endOperation(ticket)
        publishChange()
        guard ownerIsCurrent, !isInvalidated, lastOperationID == ticket.operationID else {
            return .superseded(written: receipt)
        }
        return .saved(
            receipt,
            isCurrentRevision: mutationRevision == ticket.mutationRevision && currentCheckpoint == checkpoint
        )
    }

    private func validate(_ ticket: DocumentIOTicket) throws {
        guard ownerIsCurrent, !isInvalidated, operation?.ticket == ticket,
            ticket.ownerID == ownerID, ticket.ownerGeneration == ownerGeneration,
            ticket.sessionID == sessionID, ticket.mutationRevision == mutationRevision,
            owner?.hasCloseCommitReservation == false
        else { throw DocumentSessionError.supersededOperation }
    }

    private func endOperation(_ ticket: DocumentIOTicket) {
        if operation?.ticket == ticket { operation = nil }
    }

    private func finishFailedOperation(_ ticket: DocumentIOTicket, error: Error) -> DocumentSaveOutcome {
        let isCurrentOperation = ownerIsCurrent && !isInvalidated && operation?.ticket == ticket
        let isCurrentRevision = mutationRevision == ticket.mutationRevision
        endOperation(ticket)
        guard isCurrentOperation, isCurrentRevision else { return .superseded(written: nil) }
        lastError = error
        publishChange()
        guard ownerIsCurrent, !isInvalidated, lastOperationID == ticket.operationID,
            mutationRevision == ticket.mutationRevision
        else {
            return .superseded(written: nil)
        }
        return .failed(error)
    }

    private func reportFailure(_ error: Error) -> DocumentSaveOutcome {
        lastError = error
        publishChange()
        guard ownerIsCurrent, !isInvalidated else { return .superseded(written: nil) }
        return .failed(error)
    }

    private func isCurrent(_ intent: DocumentCloseIntent) -> Bool {
        ownerIsCurrent && !isInvalidated && intent.ownerID == ownerID
            && intent.ownerGeneration == ownerGeneration && intent.sessionID == sessionID
            && intent.mutationRevision == mutationRevision && intent.checkpoint == currentCheckpoint
    }

    private func isCurrent(_ approval: DocumentCloseApproval) -> Bool {
        guard isCurrent(approval.intent), pendingCloseIntent == approval.intent,
            approval.lastOperationID == lastOperationID
        else { return false }
        if let receiptID = approval.saveReceiptID {
            return lastSaveReceiptID == receiptID && savedCheckpoint == currentCheckpoint
        }
        return true
    }

    private func approve(_ intent: DocumentCloseIntent, saveReceiptID: UUID?) -> DocumentCloseApproval {
        let approval = DocumentCloseApproval(
            id: UUID(), intent: intent, saveReceiptID: saveReceiptID, lastOperationID: lastOperationID
        )
        closeApproval = approval
        closePhase = .approved
        return approval
    }

    private func clearCloseIntent() {
        guard closePhase != .closed else { return }
        pendingCloseIntent = nil
        closeApproval = nil
        closePhase = .idle
    }

    private func publishChange() {
        guard ownerIsCurrent, !isInvalidated, owner?.hasCloseCommitReservation == false else { return }
        onChange?()
    }
}
