import Foundation
import SwiftWindowsCore
import SwiftWindowsUI

/// The model session owns history. The text bridge only transports an edit's
/// identity and, when available, restores selection on its current editor.
@MainActor
protocol DocumentTextUndoOwner: UndoManagerReplayTarget {
    var documentUndoManager: UndoManager? { get }
    var documentUndoGeneration: UInt64 { get }
    var documentMutationRevision: UInt64 { get }
    var documentUndoIsValid: Bool { get }
    var documentAllowsTextMutation: Bool { get }
    func documentUndoBelongs(to runtime: RetainedViewRuntime) -> Bool
}

@MainActor
protocol DocumentTextUndoClient: TextInputUndoClient {
    var documentSelectionIsCurrent: Bool { get }
    var documentSelectionIsComposing: Bool { get }
    var documentHasSelectionBinding: Bool { get }
    /// Last observed binding value. This accessor must not call application
    /// code: a replay handler has already consumed its model action.
    var documentBoundSelection: TextSelection? { get }
    func restoreDocumentSelection(
        _ selection: TextInputUndoSelection,
        expectedText: String,
        expectedBoundSelection: TextSelection?,
        validate: @escaping @MainActor () -> Bool
    )
}

@MainActor
struct DocumentTextSelectionRestoration {
    let selection: TextInputUndoSelection
    let expectedText: String
    let expectedBoundSelection: TextSelection?
    let validate: @MainActor () -> Bool
}

@MainActor
final class DocumentBindingSource: BindingMutationSource {
    private final class WeakEndpoint {
        weak var value: DocumentTextSelectionEndpoint?
        init(_ value: DocumentTextSelectionEndpoint) { self.value = value }
    }

    private(set) weak var owner: (any DocumentTextUndoOwner)?
    let generation: UInt64
    private var endpoints: [WeakEndpoint] = []

    init(owner: any DocumentTextUndoOwner) {
        self.owner = owner
        generation = owner.documentUndoGeneration
    }

    var isLive: Bool {
        guard let owner else { return false }
        return owner.documentUndoIsValid && owner.documentUndoGeneration == generation
    }

    /// An absent editor does not invalidate model history. An active IME does
    /// temporarily block model replay, including commit-before-end composition.
    var permitsReplay: Bool {
        guard isLive else { return false }
        endpoints.removeAll { $0.value?.isValid != true }
        return !endpoints.contains { $0.value?.blocksReplay == true }
    }

    func belongs(to runtime: RetainedViewRuntime) -> Bool {
        isLive && owner?.documentUndoBelongs(to: runtime) == true
    }

    func endpoint(
        for client: any DocumentTextUndoClient,
        projection: [AnyKeyPath]?,
        previous: DocumentTextSelectionEndpoint?
    ) -> DocumentTextSelectionEndpoint {
        if let previous, previous.matches(source: self, projection: projection) {
            previous.adopt(client)
            return previous
        }
        previous?.invalidate()
        let endpoint = DocumentTextSelectionEndpoint(source: self, projection: projection, client: client)
        endpoints.removeAll { $0.value?.isValid != true }
        endpoints.append(WeakEndpoint(endpoint))
        return endpoint
    }

    func beginEdit(
        before: String,
        proposed: String,
        selection: TextInputUndoSelection,
        endpoint: DocumentTextSelectionEndpoint?
    ) -> DocumentTextEditTicket? {
        guard isLive, let owner, owner.documentAllowsTextMutation,
            endpoint == nil || endpoint?.source === self
        else { return nil }
        if let endpoint, !endpoint.permitsMutation(for: owner, generation: endpoint.generation) { return nil }
        return DocumentTextEditTicket(
            source: self, revision: owner.documentMutationRevision,
            before: before, proposed: proposed, selection: selection, endpoint: endpoint)
    }
}

@MainActor
final class DocumentTextSelectionEndpoint {
    let source: DocumentBindingSource
    let projection: [AnyKeyPath]?
    private(set) weak var client: (any DocumentTextUndoClient)?
    private(set) var generation: UInt64 = 0
    private(set) var isValid = true

    init(source: DocumentBindingSource, projection: [AnyKeyPath]?, client: any DocumentTextUndoClient) {
        self.source = source
        self.projection = projection
        self.client = client
    }

    func matches(source: DocumentBindingSource, projection: [AnyKeyPath]?) -> Bool {
        isValid && self.source === source && self.projection != nil && self.projection == projection
    }

    func adopt(_ client: any DocumentTextUndoClient) { self.client = client }

    func invalidate() {
        isValid = false
        generation &+= 1
        client = nil
    }

    var blocksReplay: Bool {
        isValid && client?.documentSelectionIsCurrent == true && client?.documentSelectionIsComposing == true
    }

    func permitsMutation(for owner: any DocumentTextUndoOwner, generation: UInt64) -> Bool {
        guard isValid, self.generation == generation, source.owner === owner, source.isLive,
            let client, client.documentSelectionIsCurrent, let runtime = client.undoRuntime,
            owner.documentUndoBelongs(to: runtime)
        else { return false }
        return true
    }

    func currentClient(
        for owner: any DocumentTextUndoOwner, generation: UInt64, allowComposing: Bool = false
    ) -> (any DocumentTextUndoClient)? {
        guard isValid, self.generation == generation, projection != nil,
            source.owner === owner, source.isLive,
            let client, client.documentSelectionIsCurrent,
            allowComposing || !client.documentSelectionIsComposing,
            let runtime = client.undoRuntime, owner.documentUndoBelongs(to: runtime)
        else { return nil }
        return client
    }
}

/// Only the root document setter may consume a ticket and supply its receipt.
/// Copies of generated bindings forward this exact object, never an ambient
/// "currently editing" flag that a nested ordinary assignment could claim.
@MainActor
final class DocumentTextEditTicket: BindingMutationContext {
    private enum Phase { case pending, consumed, committed, finished, cancelled }
    private let source: DocumentBindingSource
    private let generation: UInt64
    private let baseRevision: UInt64
    private let before: String
    let proposed: String
    private let beforeSelection: TextInputUndoSelection
    private weak var endpoint: DocumentTextSelectionEndpoint?
    private let endpointGeneration: UInt64?
    private var phase = Phase.pending
    private(set) var receipt: DocumentTextUndoReceipt?

    var permitsWrite: Bool {
        guard phase == .pending, let owner = source.owner, source.isLive else { return false }
        return owner.documentUndoGeneration == generation && owner.documentAllowsTextMutation
            && owner.documentMutationRevision == baseRevision && endpointPermitsMutation(for: owner)
    }

    var permitsCompletion: Bool {
        guard phase == .committed, let receipt, let owner = source.owner, source.isLive else { return false }
        return owner.documentUndoGeneration == generation && owner.documentMutationRevision == receipt.revision
            && endpointPermitsMutation(for: owner)
    }

    private func endpointPermitsMutation(for owner: any DocumentTextUndoOwner) -> Bool {
        guard let endpointGeneration else { return true }
        return endpoint?.permitsMutation(for: owner, generation: endpointGeneration) == true
    }

    fileprivate init(
        source: DocumentBindingSource, revision: UInt64,
        before: String, proposed: String, selection: TextInputUndoSelection,
        endpoint: DocumentTextSelectionEndpoint?
    ) {
        self.source = source
        generation = source.generation
        baseRevision = revision
        self.before = before
        self.proposed = proposed
        beforeSelection = selection
        self.endpoint = endpoint
        endpointGeneration = endpoint?.generation
    }

    func consume(for owner: any DocumentTextUndoOwner) -> Bool {
        guard phase == .pending else { return false }
        phase = .cancelled
        guard source.owner === owner, source.isLive,
            owner.documentUndoGeneration == generation, owner.documentAllowsTextMutation,
            owner.documentMutationRevision == baseRevision, endpointPermitsMutation(for: owner)
        else { return false }
        phase = .consumed
        return true
    }

    func didCommit(for owner: any DocumentTextUndoOwner, revision: UInt64) -> DocumentTextUndoReceipt? {
        guard phase == .consumed, source.owner === owner, source.isLive,
            owner.documentUndoGeneration == generation,
            owner.documentMutationRevision == revision, revision == baseRevision &+ 1
        else { return nil }
        let receipt = DocumentTextUndoReceipt(
            source: source, revision: revision, before: before, beforeSelection: beforeSelection,
            endpoint: endpoint, endpointGeneration: endpointGeneration)
        self.receipt = receipt
        phase = .committed
        return receipt
    }

    func finish(text: String, selection: TextInputUndoSelection?) {
        guard phase == .committed, let receipt else { return }
        phase = .finished
        receipt.finish(text: text, selection: selection)
    }

    func cancel() {
        switch phase {
        case .pending, .consumed: phase = .cancelled
        case .committed: phase = .finished
        case .finished, .cancelled: break
        }
    }
}

/// An action retains its own sidecar. Completing a text edit cannot attach
/// selection to a newer direct assignment that happens to be atop the stack.
@MainActor
final class DocumentTextUndoReceipt {
    let id = UUID()
    private let source: DocumentBindingSource
    fileprivate let revision: UInt64
    private let before: String
    private let beforeSelection: TextInputUndoSelection
    private var after: String?
    private var afterSelection: TextInputUndoSelection?
    private weak var endpoint: DocumentTextSelectionEndpoint?
    private let endpointGeneration: UInt64?

    fileprivate init(
        source: DocumentBindingSource, revision: UInt64, before: String,
        beforeSelection: TextInputUndoSelection, endpoint: DocumentTextSelectionEndpoint?,
        endpointGeneration: UInt64?
    ) {
        self.source = source
        self.revision = revision
        self.before = before
        self.beforeSelection = beforeSelection
        self.endpoint = endpoint
        self.endpointGeneration = endpointGeneration
    }

    fileprivate func finish(text: String, selection: TextInputUndoSelection?) {
        guard let owner = source.owner, source.isLive, owner.documentMutationRevision == revision,
            let endpoint, let endpointGeneration,
            endpoint.currentClient(for: owner, generation: endpointGeneration, allowComposing: true) != nil
        else { return }
        after = text
        afterSelection = selection
    }

    func prepareSelectionReplay(
        for owner: any DocumentTextUndoOwner, undoing: Bool
    ) -> DocumentTextSelectionReplay? {
        guard source.owner === owner, source.isLive,
            let endpoint, let endpointGeneration,
            let client = endpoint.currentClient(for: owner, generation: endpointGeneration),
            let expectedText = undoing ? before : after,
            let selection = undoing ? beforeSelection : afterSelection
        else { return nil }
        let revision = owner.documentMutationRevision
        let hasBinding = client.documentHasSelectionBinding
        let boundSelection = hasBinding ? client.documentBoundSelection : nil
        guard owner.documentMutationRevision == revision,
            endpoint.currentClient(for: owner, generation: endpointGeneration) === client
        else { return nil }
        return DocumentTextSelectionReplay(
            source: source, endpoint: endpoint, endpointGeneration: endpointGeneration,
            revision: revision, expectedText: expectedText, selection: selection,
            hasBinding: hasBinding, expectedBoundSelection: boundSelection)
    }
}

@MainActor
final class DocumentTextSelectionReplay {
    private let source: DocumentBindingSource
    private weak var endpoint: DocumentTextSelectionEndpoint?
    private let endpointGeneration: UInt64
    private let previousRevision: UInt64
    private let expectedText: String
    private let selection: TextInputUndoSelection
    private let hasBinding: Bool
    private let expectedBoundSelection: TextSelection?
    private var didAttemptRestore = false

    fileprivate init(
        source: DocumentBindingSource, endpoint: DocumentTextSelectionEndpoint, endpointGeneration: UInt64,
        revision: UInt64, expectedText: String, selection: TextInputUndoSelection,
        hasBinding: Bool, expectedBoundSelection: TextSelection?
    ) {
        self.source = source
        self.endpoint = endpoint
        self.endpointGeneration = endpointGeneration
        previousRevision = revision
        self.expectedText = expectedText
        self.selection = selection
        self.hasBinding = hasBinding
        self.expectedBoundSelection = expectedBoundSelection
    }

    func restore(for owner: any DocumentTextUndoOwner, revision: UInt64) {
        guard !didAttemptRestore else { return }
        didAttemptRestore = true
        guard revision == previousRevision &+ 1, owner.documentMutationRevision == revision,
            source.owner === owner, source.isLive, let endpoint,
            let client = endpoint.currentClient(for: owner, generation: endpointGeneration),
            client.documentHasSelectionBinding == hasBinding
        else { return }
        let endpointGeneration = endpointGeneration
        let hasBinding = hasBinding
        let validate: @MainActor () -> Bool = { [weak owner, weak endpoint, weak client, weak source] in
            guard let owner, let endpoint, let client, let source else { return false }
            return source.owner === owner && source.isLive && owner.documentMutationRevision == revision
                && endpoint.currentClient(for: owner, generation: endpointGeneration) === client
                && client.documentHasSelectionBinding == hasBinding
        }
        client.restoreDocumentSelection(
            selection, expectedText: expectedText,
            expectedBoundSelection: expectedBoundSelection, validate: validate)
    }
}
