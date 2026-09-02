import Foundation
import SwiftWindowsCore

/// Renderer-neutral geometry sampled from the scroll position that is painted,
/// including the presentation lag of a keyboard scroll and edge overshoot.
public struct RetainedScrollGeometry: Sendable, Equatable {
    public var contentOffset: Point
    public var contentSize: Size
    public var contentInsets: EdgeInsets
    public var containerSize: Size

    public init(contentOffset: Point, contentSize: Size, contentInsets: EdgeInsets, containerSize: Size) {
        self.contentOffset = contentOffset
        self.contentSize = contentSize
        self.contentInsets = contentInsets
        self.containerSize = containerSize
    }
}

public enum RetainedScrollPhase: Sendable, Equatable {
    case idle
    case tracking
    case interacting
    case decelerating
    case animating
}

public struct RetainedScrollPhaseChangeContext: Sendable, Equatable {
    public var geometry: RetainedScrollGeometry
    /// Points per second, in content-offset coordinates, when known.
    public var velocity: Point?

    public init(geometry: RetainedScrollGeometry, velocity: Point? = nil) {
        self.geometry = geometry
        self.velocity = velocity
    }
}

/// Scroll layout needs an unfloored content extent for observation even when
/// its clamping/painting extent is at least as large as the viewport. The
/// declared axis survives disabling input; a disabled ScrollView is still a
/// scroll container whose geometry can be observed.
@MainActor
final class RetainedScrollContainerState {
    var axis: ScrollAxis
    var contentSize: Size?
    var attachmentGeneration: UInt64 = 0
    var isInputEnabled = true

    init(axis: ScrollAxis) {
        self.axis = axis
    }
}

struct RetainedScrollSourceEpoch: Equatable {
    // Keep the tiny container state alive while comparing epochs. A bare
    // ObjectIdentifier could be reused after an axis is removed and restored
    // in the same callback. This state does not retain a node or runtime.
    var container: RetainedScrollContainerState
    var attachmentGeneration: UInt64

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.container === rhs.container && lhs.attachmentGeneration == rhs.attachmentGeneration
    }
}

@MainActor
final class RetainedScrollGeometryObserver {
    let valueType: ObjectIdentifier
    let transform: (RetainedScrollGeometry) -> Any
    let valuesEqual: (Any, Any) -> Bool
    let action: (Any, Any) -> Void
    var previousValue: Any?

    init<Value: Equatable>(
        transform: @escaping (RetainedScrollGeometry) -> Value,
        action: @escaping (Value, Value) -> Void
    ) {
        valueType = ObjectIdentifier(Value.self)
        self.transform = { transform($0) as Any }
        // The type identity above is checked before transferring history.
        // Boxing as Any also preserves an Optional.none derived value.
        valuesEqual = { ($0 as! Value) == ($1 as! Value) }
        self.action = { action($0 as! Value, $1 as! Value) }
    }

    func sample(_ geometry: RetainedScrollGeometry) -> (() -> Void)? {
        let value = transform(geometry)
        let oldValue = previousValue ?? value
        let changed = previousValue == nil || !valuesEqual(oldValue, value)
        guard changed else { return nil }
        let action = action
        return { [self] in
            // A prepared callback can be invalidated by an earlier callback's
            // rebuild. Commit only delivered values, before app code can copy
            // that history into the rebuilt registration.
            previousValue = value
            action(oldValue, value)
        }
    }
}

@MainActor
final class RetainedScrollVisibilityObserver {
    let threshold: Double
    let action: (Bool) -> Void
    var previousValue: Bool?

    init(threshold: Double, action: @escaping (Bool) -> Void) {
        self.threshold = threshold.isFinite ? min(1, max(0, threshold)) : 0.5
        self.action = action
    }

    func sample(_ fraction: Double) -> (() -> Void)? {
        // At zero, touching a viewport edge is not visibility. At one, small
        // transform roundoff must not make a fully contained view invisible.
        let visible = fraction > 0 && fraction + 1e-10 >= threshold
        guard previousValue != visible else { return nil }
        let action = action
        return { [self] in
            previousValue = visible
            action(visible)
        }
    }
}

@MainActor
final class RetainedScrollPhaseObserver {
    typealias Action = (RetainedScrollPhase, RetainedScrollPhase, RetainedScrollPhaseChangeContext) -> Void

    struct Change {
        var id: UInt64
        var oldPhase: RetainedScrollPhase
        var newPhase: RetainedScrollPhase
        var context: RetainedScrollPhaseChangeContext
    }

    let action: Action
    var changes: [Change] = []
    private var nextChangeID: UInt64 = 0

    init(action: @escaping Action) {
        self.action = action
    }

    func reconcile(from previous: RetainedScrollPhaseObserver) {
        changes = previous.changes
        nextChangeID = previous.nextChangeID
    }

    func record(
        from oldPhase: RetainedScrollPhase, to newPhase: RetainedScrollPhase,
        context: RetainedScrollPhaseChangeContext
    ) {
        nextChangeID &+= 1
        var change = Change(id: nextChangeID, oldPhase: oldPhase, newPhase: newPhase, context: context)
        // A burst can revisit a phase repeatedly before painting. Coalesce
        // each registration's unpresented path independently; a callback that
        // rebuilds the owner must not consume another registration's events.
        if let repeated = changes.firstIndex(where: { $0.newPhase == newPhase }) {
            change.oldPhase = changes[repeated].oldPhase
            changes.removeSubrange(repeated..<changes.count)
        }
        changes.append(change)
    }

    func pendingActions() -> [() -> Void] {
        changes.map { change in
            { [self] in
                guard let index = changes.firstIndex(where: { $0.id == change.id }) else { return }
                changes.remove(at: index)
                action(change.oldPhase, change.newPhase, change.context)
            }
        }
    }
}

/// A finite native source-to-target boundary. These supplemental property
/// facts never stand in for checked node completion or a Task declaration.
@MainActor
private final class RetainedScrollObserverPublication {
    static let fields: [PartialKeyPath<ViewNode>] = [
        \ViewNode.retainedScrollGeometryPayloads,
        \ViewNode.retainedScrollPhasePayloads,
        \ViewNode.retainedScrollVisibilityPayloads,
    ]

    let admission: RetainedLazyListAdoptionAdmission?
    let journal: RetainedLazyListAdoptionJournal?
    let taskAdoption: RetainedTaskAdoptionContext?
    let uiaAuthority: RetainedLazyListUIAContinuationAuthority?
    weak var sourceNode: ViewNode?
    weak var targetNode: ViewNode?
    let sourceAttachment: RetainedLazyListAttachmentProof
    let targetAttachment: RetainedLazyListAttachmentProof
    let sourceIdentity: RetainedLazyListViewIdentityProof
    let targetIdentity: RetainedLazyListViewIdentityProof
    private let checksContinuation: Bool
    private var preparedFields: Set<AnyKeyPath> = []

    init(
        from source: ViewNode, to target: ViewNode,
        admission: RetainedLazyListAdoptionAdmission?, journal: RetainedLazyListAdoptionJournal?,
        taskAdoption: RetainedTaskAdoptionContext?, uiaAuthority: RetainedLazyListUIAContinuationAuthority?
    ) {
        self.admission = admission
        self.journal = journal
        self.taskAdoption = taskAdoption
        self.uiaAuthority = uiaAuthority
        sourceNode = source
        targetNode = target
        sourceAttachment = source.captureLazyListAttachmentProof()
        targetAttachment = target.captureLazyListAttachmentProof()
        sourceIdentity = source.captureLazyListIdentityProof()
        targetIdentity = target.captureLazyListIdentityProof()
        checksContinuation = admission != nil || journal?.isOrdinaryAdoption == false || uiaAuthority != nil
    }

    // An ordinary journal observes descriptor facts; missing facts do not
    // authorize skipping the separate request and native lifetime checks.
    private var usesOrdinaryUIAContinuation: Bool {
        uiaAuthority != nil && journal?.isOrdinaryAdoption == true
    }

    var isCurrent: Bool {
        guard sourceNode != nil, targetNode != nil, sourceAttachment.isCurrent, targetAttachment.isCurrent,
            sourceIdentity.isCurrent, targetIdentity.isCurrent
        else {
            uiaAuthority?.revoke()
            return false
        }
        return admission?.isCurrent != false && uiaAuthority?.isCurrent != false
            && (usesOrdinaryUIAContinuation || journal?.canContinueAdoption != false)
    }

    var canContinue: Bool { !checksContinuation || isCurrent }

    func hasCurrentStorageBindings(
        source expectedSource: RetainedScrollObserverStorage?, target expectedTarget: RetainedScrollObserverStorage?
    ) -> Bool {
        guard checksContinuation else { return true }
        guard let sourceNode, let targetNode,
            sourceNode.scrollObserverStorage === expectedSource, targetNode.scrollObserverStorage === expectedTarget
        else {
            uiaAuthority?.revoke()
            return false
        }
        return true
    }

    func prepare(_ field: PartialKeyPath<ViewNode>) -> Bool {
        guard isCurrent, let sourceNode, let targetNode else { return false }
        let prepared = journal?.preparePropertyCopy(from: sourceNode, to: targetNode, keyPath: field) != false
        if prepared { preparedFields.insert(field) }
        return (usesOrdinaryUIAContinuation || prepared) && (uiaAuthority == nil || isCurrent)
    }

    func prepareAllFields() -> Bool {
        for field in Self.fields {
            let prepared = prepare(field)
            if checksContinuation && !prepared { return false }
        }
        return canContinue
    }

    func markMutationStarted() -> Bool {
        guard isCurrent else { return false }
        let started = journal?.markMutationStarted() != false
        guard usesOrdinaryUIAContinuation || started else { return false }
        admission?.markMutationStarted()
        uiaAuthority?.markMutationStarted()
        return isCurrent
    }

    func record(_ field: PartialKeyPath<ViewNode>) {
        guard preparedFields.remove(field) != nil, isCurrent,
            let journal, let sourceNode, let targetNode
        else { return }
        for group in journal.recordAcceptedProperty(from: sourceNode, to: targetNode, keyPath: field) {
            taskAdoption?.associateLazyAccepted(group, journal: journal)
        }
        for group in journal.takeAcceptedDescriptorTaskGroups() {
            taskAdoption?.associateDescriptorAccepted(group, journal: journal)
        }
    }

    func recordAllFields() {
        for field in Self.fields { record(field) }
    }
}

@MainActor
final class RetainedScrollObserverStorage {
    fileprivate final class MutationIdentity {}

    /// An opaque history value can run cleanup when replaced. A nested
    /// reconcile/reset/source change revokes this operation before that cleanup
    /// returns, independently of whether it also changed the list's provider.
    @MainActor
    private final class CheckedOperation {
        let admission: RetainedLazyListAdoptionAdmission?
        let publication: RetainedScrollObserverPublication?
        let nativeCheck: ComponentHost.NodeReconcileAdmission?
        let uiaAuthority: RetainedLazyListUIAContinuationAuthority?
        let targetAttachment: RetainedLazyListAttachmentProof?
        let sourceAttachment: RetainedLazyListAttachmentProof?
        private weak var storage: RetainedScrollObserverStorage?
        private weak var owner: ViewNode?
        private let ownerIdentity: RetainedLazyListViewIdentityProof?
        private let checksOwnerBinding: Bool
        fileprivate var expectedMutation: MutationIdentity
        private weak var incoming: RetainedScrollObserverStorage?
        private let incomingMutation: MutationIdentity?
        private weak var sourceStorage: RetainedScrollObserverStorage?
        private let checksSourceStorage: Bool
        private weak var selectedSourceNode: ViewNode?
        private let hadSelectedSourceNode: Bool
        private let selectedSourceEpoch: RetainedScrollSourceEpoch?
        var isValid = true

        init(
            admission: RetainedLazyListAdoptionAdmission?,
            targetAttachment: RetainedLazyListAttachmentProof?,
            sourceAttachment: RetainedLazyListAttachmentProof?, storage: RetainedScrollObserverStorage,
            incoming: RetainedScrollObserverStorage?, selectedSourceNode: ViewNode?,
            publication: RetainedScrollObserverPublication?, nativeCheck: ComponentHost.NodeReconcileAdmission?,
            uiaAuthority: RetainedLazyListUIAContinuationAuthority?,
            owner: ViewNode?, ownerIdentity: RetainedLazyListViewIdentityProof?
        ) {
            self.admission = admission
            self.publication = publication
            self.nativeCheck = nativeCheck
            self.uiaAuthority = uiaAuthority ?? publication?.uiaAuthority ?? nativeCheck?.uiaAuthority
            self.targetAttachment = targetAttachment
            self.sourceAttachment = sourceAttachment
            self.storage = storage
            self.owner = owner
            self.ownerIdentity = ownerIdentity
            self.checksOwnerBinding = owner != nil || ownerIdentity != nil
            self.expectedMutation = storage.captureMutationIdentity()
            self.incoming = incoming === storage ? nil : incoming
            self.incomingMutation = incoming === storage ? nil : incoming?.captureMutationIdentity()
            self.sourceStorage = incoming
            self.checksSourceStorage = incoming != nil
            self.selectedSourceNode = selectedSourceNode
            self.hadSelectedSourceNode = selectedSourceNode != nil
            self.selectedSourceEpoch = selectedSourceNode?.scrollSourceEpoch
        }

        var isCurrent: Bool {
            guard isValid, targetAttachment?.isCurrent != false,
                sourceAttachment?.isCurrent != false, let storage, storage.mutationIdentity === expectedMutation
            else {
                uiaAuthority?.revoke()
                return false
            }
            if checksOwnerBinding {
                guard let owner, let ownerIdentity, ownerIdentity.isCurrent,
                    owner.scrollObserverStorage === storage
                else {
                    uiaAuthority?.revoke()
                    return false
                }
            }
            if let incomingMutation {
                guard let incoming, incoming.mutationIdentity === incomingMutation else {
                    uiaAuthority?.revoke()
                    return false
                }
            }
            if let publication {
                guard publication.targetNode?.scrollObserverStorage === storage else {
                    uiaAuthority?.revoke()
                    return false
                }
                if checksSourceStorage {
                    guard let sourceStorage, publication.sourceNode?.scrollObserverStorage === sourceStorage else {
                        uiaAuthority?.revoke()
                        return false
                    }
                }
            }
            if hadSelectedSourceNode {
                guard let selectedSourceNode, selectedSourceNode.scrollSourceEpoch == selectedSourceEpoch else {
                    uiaAuthority?.revoke()
                    return false
                }
            }
            return admission?.isCurrent != false && publication?.isCurrent != false
                && nativeCheck?.isCurrent != false && uiaAuthority?.isCurrent != false
        }

        func markMutationStarted() -> Bool {
            guard isCurrent, publication?.markMutationStarted() != false,
                nativeCheck?.markMutationStarted() != false
            else { return false }
            if publication == nil && nativeCheck == nil { admission?.markMutationStarted() }
            uiaAuthority?.markMutationStarted()
            return isCurrent
        }
    }

    private var checkedOperation: CheckedOperation?
    private var mutationIdentity: MutationIdentity?
    var geometry: [RetainedScrollGeometryObserver] = [] {
        didSet { invalidateMutationIdentity() }
    }
    var phase: [RetainedScrollPhaseObserver] = [] {
        didSet { invalidateMutationIdentity() }
    }
    var visibility: [RetainedScrollVisibilityObserver] = [] {
        didSet { invalidateMutationIdentity() }
    }
    weak var source: ViewNode?
    private var selectedSourceIdentifier: ObjectIdentifier?
    private var selectedSourceEpoch: RetainedScrollSourceEpoch?
    private(set) var generation: UInt64 = 0
    var currentPhase: RetainedScrollPhase = .idle
    var phaseChanges: [RetainedScrollPhaseObserver.Change] { phase.flatMap(\.changes) }
    var reportedMultipleSources = false

    @discardableResult
    func reconcile(
        from incoming: RetainedScrollObserverStorage, admission: RetainedLazyListAdoptionAdmission? = nil,
        targetAttachment: RetainedLazyListAttachmentProof? = nil,
        sourceAttachment: RetainedLazyListAttachmentProof? = nil,
        sourceNode: ViewNode? = nil, targetNode: ViewNode? = nil,
        lazyJournal: RetainedLazyListAdoptionJournal? = nil,
        taskAdoption: RetainedTaskAdoptionContext? = nil,
        uiaAuthority: RetainedLazyListUIAContinuationAuthority? = nil
    ) -> Bool {
        if let uiaAuthority, let journalAuthority = lazyJournal?.uiaContinuationAuthority,
            uiaAuthority !== journalAuthority
        {
            return false
        }
        let uiaAuthority = uiaAuthority ?? lazyJournal?.uiaContinuationAuthority
        let publication: RetainedScrollObserverPublication?
        if lazyJournal != nil || uiaAuthority != nil, let sourceNode, let targetNode {
            publication = RetainedScrollObserverPublication(
                from: sourceNode, to: targetNode, admission: admission, journal: lazyJournal,
                taskAdoption: taskAdoption, uiaAuthority: uiaAuthority)
        } else {
            // Present managed authority never becomes an ordinary transfer just
            // because its original native source or target was not supplied.
            guard lazyJournal?.isOrdinaryAdoption != false, uiaAuthority == nil else { return false }
            publication = nil
        }
        if admission == nil && lazyJournal?.isOrdinaryAdoption != false && uiaAuthority == nil {
            let operation = beginCheckedOperation(
                admission: nil, targetAttachment: nil, sourceAttachment: nil,
                incoming: incoming, publication: publication)
            reconcileOrdinaryPayloads(from: incoming, operation: operation)
            finishCheckedOperation(operation)
            return true
        }
        guard admission?.isCurrent != false, uiaAuthority?.isCurrent != false, publication?.isCurrent != false
        else { return false }
        guard targetAttachment?.isCurrent != false, sourceAttachment?.isCurrent != false else {
            uiaAuthority?.revoke()
            return false
        }
        let operation = beginCheckedOperation(
            admission: admission, targetAttachment: targetAttachment, sourceAttachment: sourceAttachment,
            incoming: incoming, publication: publication, uiaAuthority: uiaAuthority)
        let completed = reconcilePayloads(from: incoming, operation: operation)
        // All old array/history payloads in reconcilePayloads have unwound.
        let remainsCurrent = operation?.isCurrent != false
        finishCheckedOperation(operation)
        return completed && remainsCurrent
    }

    /// Keep the existing nil-admission transfer and its cleanup order intact.
    /// Native witness invalidation above does not invoke application code.
    private func reconcileOrdinaryPayloads(
        from incoming: RetainedScrollObserverStorage, operation: CheckedOperation? = nil
    ) {
        if let operation, operation.isCurrent { _ = operation.markMutationStarted() }
        generation &+= 1
        for index in incoming.geometry.indices where geometry.indices.contains(index) {
            if incoming.geometry[index].valueType == geometry[index].valueType {
                incoming.geometry[index].previousValue = geometry[index].previousValue
            }
        }
        for index in incoming.visibility.indices where visibility.indices.contains(index) {
            incoming.visibility[index].previousValue = visibility[index].previousValue
        }
        for index in incoming.phase.indices where phase.indices.contains(index) {
            incoming.phase[index].reconcile(from: phase[index])
        }
        if let operation {
            replaceOwnedPayload(
                \.geometry, with: incoming.geometry, operation: operation,
                field: \ViewNode.retainedScrollGeometryPayloads, preservesOrdinaryContinuation: true)
            replaceOwnedPayload(
                \.visibility, with: incoming.visibility, operation: operation,
                field: \ViewNode.retainedScrollVisibilityPayloads, preservesOrdinaryContinuation: true)
        } else {
            geometry = incoming.geometry
            visibility = incoming.visibility
        }
        if phase.isEmpty || incoming.phase.isEmpty {
            currentPhase = .idle
        }
        if let operation {
            replaceOwnedPayload(
                \.phase, with: incoming.phase, operation: operation,
                field: \ViewNode.retainedScrollPhasePayloads, preservesOrdinaryContinuation: true)
        } else {
            phase = incoming.phase
        }
    }

    private func reconcilePayloads(from incoming: RetainedScrollObserverStorage, operation: CheckedOperation?) -> Bool {
        guard operation?.isCurrent != false else { return false }
        // Fresh closures may remove registrations or change their transforms.
        // Pending actions from the old declaration must not run afterward.
        guard operation?.markMutationStarted() != false else { return false }
        generation &+= 1
        let previousGeometry = geometry
        let previousVisibility = visibility
        let previousPhase = phase
        let incomingGeometry = incoming.geometry
        let incomingVisibility = incoming.visibility
        let incomingPhase = incoming.phase
        for index in incomingGeometry.indices where previousGeometry.indices.contains(index) {
            guard operation?.isCurrent != false else { return false }
            if incomingGeometry[index].valueType == previousGeometry[index].valueType {
                Self.replacePinnedPayload(
                    \.previousValue, on: incomingGeometry[index], with: previousGeometry[index].previousValue)
                guard operation?.isCurrent != false else { return false }
            }
        }
        for index in incomingVisibility.indices where previousVisibility.indices.contains(index) {
            guard operation?.isCurrent != false else { return false }
            incomingVisibility[index].previousValue = previousVisibility[index].previousValue
        }
        for index in incomingPhase.indices where previousPhase.indices.contains(index) {
            guard operation?.isCurrent != false else { return false }
            incomingPhase[index].reconcile(from: previousPhase[index])
        }
        guard operation?.isCurrent != false else { return false }
        guard
            replaceOwnedPayload(
                \.geometry, with: incomingGeometry, operation: operation,
                field: \ViewNode.retainedScrollGeometryPayloads)
        else { return false }
        guard operation?.isCurrent != false else { return false }
        guard
            replaceOwnedPayload(
                \.visibility, with: incomingVisibility, operation: operation,
                field: \ViewNode.retainedScrollVisibilityPayloads)
        else { return false }
        guard operation?.isCurrent != false else { return false }
        if previousPhase.isEmpty || incomingPhase.isEmpty {
            currentPhase = .idle
        }
        guard
            replaceOwnedPayload(
                \.phase, with: incomingPhase, operation: operation,
                field: \ViewNode.retainedScrollPhasePayloads)
        else { return false }
        return operation?.isCurrent != false
    }

    @discardableResult
    func reset(
        admission: RetainedLazyListAdoptionAdmission? = nil, attachment: RetainedLazyListAttachmentProof? = nil
    ) -> Bool {
        if admission == nil {
            beginCheckedOperation(admission: nil, targetAttachment: nil, sourceAttachment: nil)
            generation &+= 1
            source = nil
            selectedSourceIdentifier = nil
            selectedSourceEpoch = nil
            currentPhase = .idle
            for observer in phase { observer.changes.removeAll(keepingCapacity: false) }
            for observer in geometry { observer.previousValue = nil }
            for observer in visibility { observer.previousValue = nil }
            return true
        }
        guard admission?.isCurrent != false, attachment?.isCurrent != false else { return false }
        let operation = beginCheckedOperation(admission: admission, targetAttachment: attachment, sourceAttachment: nil)
        let completed = resetPayloads(operation: operation)
        let remainsCurrent = operation?.isCurrent != false
        finishCheckedOperation(operation)
        return completed && remainsCurrent
    }

    private func resetPayloads(operation: CheckedOperation?) -> Bool {
        guard operation?.isCurrent != false else { return false }
        guard operation?.markMutationStarted() != false else { return false }
        generation &+= 1
        source = nil
        selectedSourceIdentifier = nil
        selectedSourceEpoch = nil
        currentPhase = .idle
        return clearHistory(operation: operation, keepingPhaseCapacity: false)
    }

    @discardableResult
    func selectSource(
        _ node: ViewNode?, admission: RetainedLazyListAdoptionAdmission? = nil,
        attachment: RetainedLazyListAttachmentProof? = nil,
        nativeCheck: ComponentHost.NodeReconcileAdmission? = nil,
        owner: ViewNode? = nil, ownerIdentity: RetainedLazyListViewIdentityProof? = nil
    ) -> Bool {
        if let nativeCheck, nativeCheck.lazyJournal?.isOrdinaryAdoption == false || nativeCheck.uiaAuthority != nil {
            guard nativeCheck.isCurrent, admission?.isCurrent != false, let owner, let ownerIdentity
            else { return false }
            guard attachment?.isCurrent != false, ownerIdentity.isCurrent, owner.scrollObserverStorage === self else {
                nativeCheck.uiaAuthority?.revoke()
                return false
            }
            guard
                source !== node || selectedSourceIdentifier != node.map(ObjectIdentifier.init)
                    || selectedSourceEpoch != node?.scrollSourceEpoch
            else { return true }
            let operation = beginCheckedOperation(
                admission: admission, targetAttachment: attachment,
                sourceAttachment: node?.captureLazyListAttachmentProof(),
                selectedSourceNode: node, nativeCheck: nativeCheck, owner: owner, ownerIdentity: ownerIdentity)
            let completed = selectSourcePayloads(node, operation: operation)
            let remainsCurrent = operation?.isCurrent != false
            finishCheckedOperation(operation)
            return completed && remainsCurrent
        }
        guard admission?.isCurrent != false, attachment?.isCurrent != false else { return false }
        // A weak source may already have become nil after removal. Its last
        // identity still tells us to release derived values and pending phases.
        guard
            source !== node || selectedSourceIdentifier != node.map(ObjectIdentifier.init)
                || selectedSourceEpoch != node?.scrollSourceEpoch
        else { return true }
        if admission == nil {
            beginCheckedOperation(admission: nil, targetAttachment: nil, sourceAttachment: nil)
            generation &+= 1
            source = node
            selectedSourceIdentifier = node.map(ObjectIdentifier.init)
            selectedSourceEpoch = node?.scrollSourceEpoch
            currentPhase = .idle
            for observer in phase { observer.changes.removeAll(keepingCapacity: true) }
            for observer in geometry { observer.previousValue = nil }
            return true
        }
        let sourceAttachment = admission == nil ? nil : node?.captureLazyListAttachmentProof()
        let operation = beginCheckedOperation(
            admission: admission, targetAttachment: attachment, sourceAttachment: sourceAttachment,
            selectedSourceNode: node)
        let completed = selectSourcePayloads(node, operation: operation)
        let remainsCurrent = operation?.isCurrent != false
        finishCheckedOperation(operation)
        return completed && remainsCurrent
    }

    private func selectSourcePayloads(_ node: ViewNode?, operation: CheckedOperation?) -> Bool {
        guard operation?.isCurrent != false else { return false }
        guard operation?.markMutationStarted() != false else { return false }
        generation &+= 1
        source = node
        selectedSourceIdentifier = node.map(ObjectIdentifier.init)
        selectedSourceEpoch = node?.scrollSourceEpoch
        currentPhase = .idle
        return clearHistory(operation: operation, keepingPhaseCapacity: true, clearsVisibility: false)
    }

    private func clearHistory(
        operation: CheckedOperation?, keepingPhaseCapacity: Bool, clearsVisibility: Bool = true
    ) -> Bool {
        let phaseObservers = phase
        let geometryObservers = geometry
        let visibilityObservers = visibility
        for observer in phaseObservers {
            guard operation?.isCurrent != false else { return false }
            observer.changes.removeAll(keepingCapacity: keepingPhaseCapacity)
        }
        for observer in geometryObservers {
            guard operation?.isCurrent != false else { return false }
            Self.replacePinnedPayload(\.previousValue, on: observer, with: nil)
            guard operation?.isCurrent != false else { return false }
        }
        if clearsVisibility {
            for observer in visibilityObservers {
                guard operation?.isCurrent != false else { return false }
                observer.previousValue = nil
            }
        }
        return operation?.isCurrent != false
    }

    @discardableResult
    private func beginCheckedOperation(
        admission: RetainedLazyListAdoptionAdmission?, targetAttachment: RetainedLazyListAttachmentProof?,
        sourceAttachment: RetainedLazyListAttachmentProof?, incoming: RetainedScrollObserverStorage? = nil,
        selectedSourceNode: ViewNode? = nil, publication: RetainedScrollObserverPublication? = nil,
        nativeCheck: ComponentHost.NodeReconcileAdmission? = nil,
        uiaAuthority: RetainedLazyListUIAContinuationAuthority? = nil,
        owner: ViewNode? = nil, ownerIdentity: RetainedLazyListViewIdentityProof? = nil
    ) -> CheckedOperation? {
        checkedOperation?.isValid = false
        invalidateMutationIdentity()
        let operation: CheckedOperation?
        if admission != nil || publication != nil || nativeCheck != nil || uiaAuthority != nil {
            operation = CheckedOperation(
                admission: admission, targetAttachment: targetAttachment, sourceAttachment: sourceAttachment,
                storage: self, incoming: incoming, selectedSourceNode: selectedSourceNode, publication: publication,
                nativeCheck: nativeCheck, uiaAuthority: uiaAuthority, owner: owner, ownerIdentity: ownerIdentity)
        } else {
            operation = nil
        }
        checkedOperation = operation
        return operation
    }

    private func finishCheckedOperation(_ operation: CheckedOperation?) {
        if checkedOperation === operation { checkedOperation = nil }
    }

    private func captureMutationIdentity() -> MutationIdentity {
        if let mutationIdentity { return mutationIdentity }
        let identity = MutationIdentity()
        mutationIdentity = identity
        return identity
    }

    private func invalidateMutationIdentity() {
        if mutationIdentity != nil { mutationIdentity = MutationIdentity() }
    }

    private static func replacePinnedPayload<Owner: AnyObject, Value>(
        _ keyPath: ReferenceWritableKeyPath<Owner, Value>, on owner: Owner, with incoming: Value
    ) {
        let previous = owner[keyPath: keyPath]
        owner[keyPath: keyPath] = incoming
        withExtendedLifetime(previous) {}
    }

    @discardableResult
    private func replaceOwnedPayload<Value>(
        _ keyPath: ReferenceWritableKeyPath<RetainedScrollObserverStorage, Value>, with incoming: Value,
        operation: CheckedOperation?, field: PartialKeyPath<ViewNode>, preservesOrdinaryContinuation: Bool = false
    ) -> Bool {
        let preservesOrdinaryContinuation = preservesOrdinaryContinuation && operation?.uiaAuthority == nil
        let mayRecord = operation?.isCurrent != false && operation?.publication?.prepare(field) != false
        guard preservesOrdinaryContinuation || mayRecord else { return false }
        let previous = self[keyPath: keyPath]
        self[keyPath: keyPath] = incoming
        // This setter contains only native bookkeeping. Accept its own new
        // witness before releasing old registrations; a registration installed
        // by their cleanup must produce a different, unaccepted witness.
        if let operation, mayRecord {
            operation.expectedMutation = captureMutationIdentity()
            operation.publication?.record(field)
        }
        withExtendedLifetime(previous) {}
        return preservesOrdinaryContinuation || operation?.isCurrent != false
    }

    /// Checked retirement first revokes every old attachment in the batch.
    /// Move opaque history into the caller's cleanup record so no application
    /// destructor runs while later departing owners still retain permissions.
    /// Admission is deliberately not consulted: admitted cleanup must finish.
    func takeLazyListRetiredHistory() -> [Any] {
        var retired: [Any] = []
        if let operation = checkedOperation {
            operation.isValid = false
            retired.append(operation)
        }
        checkedOperation = nil
        invalidateMutationIdentity()
        generation &+= 1
        source = nil
        selectedSourceIdentifier = nil
        selectedSourceEpoch = nil
        currentPhase = .idle
        for observer in phase { observer.changes.removeAll(keepingCapacity: false) }
        for observer in geometry {
            if let value = observer.previousValue { retired.append(value) }
            observer.previousValue = nil
        }
        for observer in visibility { observer.previousValue = nil }
        return retired
    }

    func recordPhase(_ nextPhase: RetainedScrollPhase, context: RetainedScrollPhaseChangeContext) {
        guard !phase.isEmpty, currentPhase != nextPhase else { return }
        invalidateMutationIdentity()
        for observer in phase {
            observer.record(from: currentPhase, to: nextPhase, context: context)
        }
        currentPhase = nextPhase
    }
}

@MainActor
enum RetainedScrollRegistrationResult {
    case inserted(RetainedScrollRegistrationReceipt)
    case alreadyRegistered
    case unavailable
}

/// A native insertion identity, not an observer payload or history claim.
/// Neither the registry, its runtime, nor any node is retained by this handle.
@MainActor
final class RetainedScrollRegistrationReceipt {
    private enum State {
        case available
        case revoked
        case consumed
    }

    private(set) weak var runtime: RetainedViewRuntime?
    private(set) weak var registry: RetainedScrollObserverRegistry?
    fileprivate let identifier: ObjectIdentifier
    private var state = State.available

    fileprivate init(
        runtime: RetainedViewRuntime, registry: RetainedScrollObserverRegistry, identifier: ObjectIdentifier
    ) {
        self.runtime = runtime
        self.registry = registry
        self.identifier = identifier
    }

    fileprivate var isConsumed: Bool { state == .consumed }

    fileprivate func revoke() {
        if state == .available { state = .revoked }
    }

    /// Called before the runtime checks its current registry. Failed origin
    /// checks also consume the original handle, so a later alias cannot retry.
    private func consume() -> RetainedNativeRegistrationRemovalResult? {
        let previous = state
        state = .consumed
        switch previous {
        case .available: return nil
        case .revoked: return .notCurrent
        case .consumed: return .alreadyConsumed
        }
    }

    func removeOriginal(in runtime: RetainedViewRuntime) -> RetainedNativeRegistrationRemovalResult {
        if let result = consume() { return result }
        guard self.runtime === runtime, let registry,
            runtime.isCurrentScrollObserverRegistry(registry), registry.removeConsumedInsertion(self)
        else { return .notCurrent }
        runtime.discardEmptyScrollObserverRegistry(registry)
        return .removed
    }
}

@MainActor
final class RetainedScrollObserverRegistry {
    struct NodeRef {
        weak var node: ViewNode?
        let sourceEpoch: RetainedScrollSourceEpoch?

        @MainActor
        init(node: ViewNode) {
            self.node = node
            sourceEpoch = node.scrollSourceEpoch
        }
    }

    private(set) var nodes: [NodeRef] = []
    private var indices: [ObjectIdentifier: Int] = [:]
    private var recordedInsertions: [ObjectIdentifier: RetainedScrollRegistrationReceipt] = [:]
    private var emptySlots = 0
    var isDelivering = false
    var renderedDuringDelivery = false

    var isEmpty: Bool { indices.isEmpty }
    var registrationCount: Int { indices.count }
    var recordedInsertionCount: Int { recordedInsertions.count }

    func register(_ node: ViewNode) {
        let identifier = ObjectIdentifier(node)
        guard indices[identifier] == nil else { return }
        insert(node, identifier: identifier)
    }

    func registerRecordingInsertion(
        _ node: ViewNode, runtime: RetainedViewRuntime
    ) -> RetainedScrollRegistrationResult {
        guard runtime.isNativeRegistrationOrigin(of: node), runtime.isCurrentScrollObserverRegistry(self) else {
            return .unavailable
        }
        let identifier = ObjectIdentifier(node)
        guard indices[identifier] == nil else { return .alreadyRegistered }
        let receipt = RetainedScrollRegistrationReceipt(runtime: runtime, registry: self, identifier: identifier)
        insert(node, identifier: identifier, recording: receipt)
        return .inserted(receipt)
    }

    private func insert(
        _ node: ViewNode, identifier: ObjectIdentifier, recording receipt: RetainedScrollRegistrationReceipt? = nil
    ) {
        revokeRecordedInsertion(identifier: identifier)
        indices[identifier] = nodes.count
        nodes.append(NodeRef(node: node))
        if let receipt { recordedInsertions[identifier] = receipt }
    }

    func revokeRecordedInsertion(for node: ViewNode) {
        guard !recordedInsertions.isEmpty else { return }
        revokeRecordedInsertion(identifier: ObjectIdentifier(node))
    }

    private func revokeRecordedInsertion(identifier: ObjectIdentifier) {
        recordedInsertions.removeValue(forKey: identifier)?.revoke()
    }

    func revokeRecordedInsertions() {
        for receipt in recordedInsertions.values { receipt.revoke() }
        recordedInsertions.removeAll(keepingCapacity: false)
    }

    func unregister(_ node: ViewNode) {
        let identifier = ObjectIdentifier(node)
        guard let index = indices[identifier] else { return }
        remove(identifier: identifier, index: index)
    }

    /// The runtime has already consumed the handle and checked the exact
    /// registry instance. An index is only a location, never entry identity.
    fileprivate func removeConsumedInsertion(_ receipt: RetainedScrollRegistrationReceipt) -> Bool {
        guard receipt.isConsumed, receipt.registry === self,
            recordedInsertions[receipt.identifier] === receipt,
            let index = indices[receipt.identifier]
        else { return false }
        remove(identifier: receipt.identifier, index: index)
        return true
    }

    private func remove(identifier: ObjectIdentifier, index: Int) {
        revokeRecordedInsertion(identifier: identifier)
        indices.removeValue(forKey: identifier)
        nodes[index].node = nil
        emptySlots += 1
        if emptySlots > 64, emptySlots > indices.count { compact() }
    }

    private func revokeMissingRecordedInsertions() {
        for (identifier, receipt) in recordedInsertions {
            if let index = indices[identifier], nodes[index].node != nil { continue }
            receipt.revoke()
            recordedInsertions.removeValue(forKey: identifier)
        }
    }

    func compact() {
        revokeMissingRecordedInsertions()
        nodes.removeAll { $0.node == nil }
        indices.removeAll(keepingCapacity: true)
        for (index, reference) in nodes.enumerated() {
            if let node = reference.node { indices[ObjectIdentifier(node)] = index }
        }
        // A weak node may also expire while the index is rebuilt. No surviving
        // insertion gets a new identity merely because its position moved.
        revokeMissingRecordedInsertions()
        emptySlots = 0
    }
}

extension ViewNode {
    /// Native payload families have separate write boundaries. A partial
    /// geometry transfer must not replace the owners of untouched families.
    var retainedScrollGeometryPayloads: [RetainedScrollGeometryObserver] {
        scrollObserverStorage?.geometry ?? []
    }

    var retainedScrollPhasePayloads: [RetainedScrollPhaseObserver] {
        scrollObserverStorage?.phase ?? []
    }

    var retainedScrollVisibilityPayloads: [RetainedScrollVisibilityObserver] {
        scrollObserverStorage?.visibility ?? []
    }

    var scrollSourceEpoch: RetainedScrollSourceEpoch? {
        scrollContainerState.map {
            RetainedScrollSourceEpoch(container: $0, attachmentGeneration: $0.attachmentGeneration)
        }
    }
    /// Observes the first enclosed scroll container. The first complete render
    /// establishes the value with an old == new callback; later renders invoke
    /// the action only when the transformed Equatable value changes.
    public func observeScrollGeometry<Value: Equatable>(
        of transform: @escaping (RetainedScrollGeometry) -> Value,
        action: @escaping (Value, Value) -> Void
    ) {
        let storage = scrollObserverStorage ?? RetainedScrollObserverStorage()
        storage.geometry.append(RetainedScrollGeometryObserver(transform: transform, action: action))
        scrollObserverStorage = storage
    }

    public func observeScrollPhase(
        _ action:
            @escaping (
                RetainedScrollPhase, RetainedScrollPhase, RetainedScrollPhaseChangeContext
            ) -> Void
    ) {
        let storage = scrollObserverStorage ?? RetainedScrollObserverStorage()
        storage.phase.append(RetainedScrollPhaseObserver(action: action))
        scrollObserverStorage = storage
    }

    /// Observes this view's area within its ancestor viewports. This is a
    /// geometry observation, not an opacity or sibling-occlusion query.
    public func observeScrollVisibility(threshold: Double = 0.5, _ action: @escaping (Bool) -> Void) {
        let storage = scrollObserverStorage ?? RetainedScrollObserverStorage()
        storage.visibility.append(RetainedScrollVisibilityObserver(threshold: threshold, action: action))
        scrollObserverStorage = storage
    }

    @discardableResult
    func reconcileScrollObservers(
        from source: ViewNode, admission: RetainedLazyListAdoptionAdmission? = nil,
        lazyJournal: RetainedLazyListAdoptionJournal? = nil,
        taskAdoption: RetainedTaskAdoptionContext? = nil,
        uiaAuthority: RetainedLazyListUIAContinuationAuthority? = nil
    ) -> Bool {
        if let uiaAuthority, let journalAuthority = lazyJournal?.uiaContinuationAuthority,
            uiaAuthority !== journalAuthority
        {
            return false
        }
        let uiaAuthority = uiaAuthority ?? lazyJournal?.uiaContinuationAuthority
        if lazyJournal == nil {
            return reconcileScrollObserversWithoutJournal(
                from: source, admission: admission, uiaAuthority: uiaAuthority)
        }
        return reconcileScrollObserversWithPublication(
            from: source, admission: admission, lazyJournal: lazyJournal,
            taskAdoption: taskAdoption, uiaAuthority: uiaAuthority)
    }

    private func reconcileScrollObserversWithPublication(
        from source: ViewNode, admission: RetainedLazyListAdoptionAdmission?,
        lazyJournal: RetainedLazyListAdoptionJournal?, taskAdoption: RetainedTaskAdoptionContext?,
        uiaAuthority: RetainedLazyListUIAContinuationAuthority?
    ) -> Bool {
        let publication = RetainedScrollObserverPublication(
            from: source, to: self, admission: admission, journal: lazyJournal,
            taskAdoption: taskAdoption, uiaAuthority: uiaAuthority)
        let checksContinuation = admission != nil || lazyJournal?.isOrdinaryAdoption == false || uiaAuthority != nil
        guard publication.canContinue else { return false }
        guard let incoming = source.scrollObserverStorage else {
            if scrollObserverStorage != nil {
                guard publication.prepareAllFields() else { return false }
                let started = publication.markMutationStarted()
                guard !checksContinuation || started else { return false }
                replaceScrollObserverStorage(with: nil, publication: publication)
            }
            return publication.canContinue
                && publication.hasCurrentStorageBindings(source: nil, target: nil)
        }
        if let storage = scrollObserverStorage {
            guard
                storage.reconcile(
                    from: incoming, admission: admission,
                    targetAttachment: publication.targetAttachment, sourceAttachment: publication.sourceAttachment,
                    sourceNode: source, targetNode: self, lazyJournal: lazyJournal,
                    taskAdoption: taskAdoption, uiaAuthority: uiaAuthority),
                publication.canContinue,
                publication.hasCurrentStorageBindings(source: incoming, target: storage)
            else { return false }
            // A transform may capture changed application state even while
            // the scroll geometry itself is unchanged. The individual family
            // writes already recorded their facts; this setter adds no facts.
            replaceScrollObserverStorage(with: storage)
            return publication.canContinue
                && publication.hasCurrentStorageBindings(source: incoming, target: storage)
        } else {
            guard publication.prepareAllFields() else { return false }
            let started = publication.markMutationStarted()
            guard !checksContinuation || started else { return false }
            replaceScrollObserverStorage(with: incoming, publication: publication)
            return publication.canContinue
                && publication.hasCurrentStorageBindings(source: incoming, target: incoming)
        }
    }

    /// Preserve both original nil-journal routes when no request guard is
    /// present. UIA uses the same checked native publication as journal adoption.
    private func reconcileScrollObserversWithoutJournal(
        from source: ViewNode, admission: RetainedLazyListAdoptionAdmission? = nil,
        uiaAuthority: RetainedLazyListUIAContinuationAuthority? = nil
    ) -> Bool {
        if let uiaAuthority {
            return reconcileScrollObserversWithPublication(
                from: source, admission: admission, lazyJournal: nil,
                taskAdoption: nil, uiaAuthority: uiaAuthority)
        }
        if admission == nil {
            guard let incoming = source.scrollObserverStorage else {
                if scrollObserverStorage != nil { scrollObserverStorage = nil }
                return true
            }
            if let storage = scrollObserverStorage {
                storage.reconcile(from: incoming)
                scrollObserverStorage = storage
            } else {
                scrollObserverStorage = incoming
            }
            return true
        }
        guard admission?.isCurrent != false else { return false }
        let targetAttachment = admission == nil ? nil : captureLazyListAttachmentProof()
        let sourceAttachment = admission == nil ? nil : source.captureLazyListAttachmentProof()
        guard let incoming = source.scrollObserverStorage else {
            if scrollObserverStorage != nil {
                admission?.markMutationStarted()
                replaceScrollObserverStorage(with: nil)
            }
            return admission?.isCurrent != false && targetAttachment?.isCurrent != false
                && sourceAttachment?.isCurrent != false
        }
        if let storage = scrollObserverStorage {
            guard
                storage.reconcile(
                    from: incoming, admission: admission,
                    targetAttachment: targetAttachment, sourceAttachment: sourceAttachment),
                admission?.isCurrent != false, targetAttachment?.isCurrent != false,
                sourceAttachment?.isCurrent != false, scrollObserverStorage === storage,
                source.scrollObserverStorage === incoming
            else { return false }
            // A transform may capture changed application state even while
            // the scroll geometry itself is unchanged.
            replaceScrollObserverStorage(with: storage)
        } else {
            admission?.markMutationStarted()
            replaceScrollObserverStorage(with: incoming)
        }
        return admission?.isCurrent != false && targetAttachment?.isCurrent != false
            && sourceAttachment?.isCurrent != false
    }

    private func replaceScrollObserverStorage(
        with incoming: RetainedScrollObserverStorage?, publication: RetainedScrollObserverPublication? = nil
    ) {
        let previous = scrollObserverStorage
        scrollObserverStorage = incoming
        publication?.recordAllFields()
        withExtendedLifetime(previous) {}
    }

    @discardableResult
    func reconcileScrollContainer(
        from source: ViewNode, admission: RetainedLazyListAdoptionAdmission? = nil,
        nativeCheck: ComponentHost.NodeReconcileAdmission? = nil
    ) -> Bool {
        if let nativeCheck, nativeCheck.lazyJournal?.isOrdinaryAdoption == false || nativeCheck.uiaAuthority != nil {
            guard nativeCheck.isCurrent, admission?.isCurrent != false, nativeCheck.markMutationStarted() else {
                return false
            }
            guard let incoming = source.scrollContainerState else {
                scrollContainerState = nil
                return nativeCheck.isCurrent && admission?.isCurrent != false
            }
            if let state = scrollContainerState {
                state.axis = incoming.axis
            } else {
                scrollContainerState = RetainedScrollContainerState(axis: incoming.axis)
            }
            guard nativeCheck.isCurrent, admission?.isCurrent != false,
                reconcileScrollInputEnabled(incoming.isInputEnabled, admission: admission, nativeCheck: nativeCheck)
            else { return false }
            return nativeCheck.isCurrent && admission?.isCurrent != false
        }
        if admission == nil {
            guard let incoming = source.scrollContainerState else {
                scrollContainerState = nil
                return true
            }
            if let state = scrollContainerState {
                state.axis = incoming.axis
            } else {
                scrollContainerState = RetainedScrollContainerState(axis: incoming.axis)
            }
            isScrollInputEnabled = incoming.isInputEnabled
            return true
        }
        guard admission?.isCurrent != false else { return false }
        let targetAttachment = admission == nil ? nil : captureLazyListAttachmentProof()
        let sourceAttachment = admission == nil ? nil : source.captureLazyListAttachmentProof()
        guard let incoming = source.scrollContainerState else {
            scrollContainerState = nil
            return admission?.isCurrent != false && targetAttachment?.isCurrent != false
                && sourceAttachment?.isCurrent != false
        }
        if let state = scrollContainerState {
            state.axis = incoming.axis
        } else {
            scrollContainerState = RetainedScrollContainerState(axis: incoming.axis)
        }
        guard reconcileScrollInputEnabled(incoming.isInputEnabled, admission: admission) else { return false }
        return admission?.isCurrent != false && targetAttachment?.isCurrent != false
            && sourceAttachment?.isCurrent != false
    }
}

/// Convex polygon intersection keeps visibility correct under rotation and
/// scale, where intersecting axis-aligned bounding boxes overcounts area.
enum RetainedScrollVisibilityGeometry {
    static func corners(of rect: Rect, transform: Transform2D) -> [Point] {
        [
            Point(x: rect.minX, y: rect.minY),
            Point(x: rect.maxX, y: rect.minY),
            Point(x: rect.maxX, y: rect.maxY),
            Point(x: rect.minX, y: rect.maxY),
        ].map { transform.applying(to: $0) }
    }

    static func area(of points: [Point]) -> Double {
        abs(signedArea(of: points))
    }

    private static func signedArea(of points: [Point]) -> Double {
        guard points.count >= 3 else { return 0 }
        var sum = 0.0
        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            sum += current.x * next.y - next.x * current.y
        }
        return sum * 0.5
    }

    static func intersect(_ subject: [Point], with clip: [Point]) -> [Point] {
        guard subject.count >= 3, clip.count >= 3 else { return [] }
        let orientation = signedArea(of: clip) >= 0 ? 1.0 : -1.0
        var output = subject
        for index in clip.indices {
            guard !output.isEmpty else { return [] }
            let edgeStart = clip[index]
            let edgeEnd = clip[(index + 1) % clip.count]
            func distance(_ point: Point) -> Double {
                orientation
                    * ((edgeEnd.x - edgeStart.x) * (point.y - edgeStart.y)
                        - (edgeEnd.y - edgeStart.y) * (point.x - edgeStart.x))
            }
            let input = output
            output = []
            var previous = input[input.count - 1]
            var previousDistance = distance(previous)
            for current in input {
                let currentDistance = distance(current)
                if (currentDistance >= 0) != (previousDistance >= 0) {
                    let progress = previousDistance / (previousDistance - currentDistance)
                    output.append(
                        Point(
                            x: previous.x + (current.x - previous.x) * progress,
                            y: previous.y + (current.y - previous.y) * progress))
                }
                if currentDistance >= 0 { output.append(current) }
                previous = current
                previousDistance = currentDistance
            }
        }
        return output
    }
}
