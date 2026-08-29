/// Identity of one committed task modifier. The observed value and its
/// equality operation remain in the facade's mounted observation cell.
@MainActor
package final class RetainedTaskMountToken {
    private var groupOwners: [ObjectIdentifier: RetainedTaskGroupOwnerReference] = [:]
    package init() {}

    fileprivate func groupLaunchOwner(in runtime: RetainedViewRuntime) -> RetainedTaskGroupLaunchOwner? {
        let reference = groupOwners[ObjectIdentifier(runtime)]
        guard reference?.runtime === runtime else { return nil }
        return reference?.owner
    }

    fileprivate func setGroupLaunchOwner(_ owner: RetainedTaskGroupLaunchOwner, in runtime: RetainedViewRuntime) {
        groupOwners = groupOwners.filter { $0.value.owner != nil && $0.value.runtime != nil }
        groupOwners[ObjectIdentifier(runtime)] = RetainedTaskGroupOwnerReference(owner: owner, runtime: runtime)
    }

    fileprivate func clearGroupLaunchOwner(_ owner: RetainedTaskGroupLaunchOwner, in runtime: RetainedViewRuntime) {
        let key = ObjectIdentifier(runtime)
        if groupOwners[key]?.owner === owner { groupOwners.removeValue(forKey: key) }
    }
}

@MainActor
fileprivate final class RetainedTaskAssociation {}

@MainActor
fileprivate final class RetainedTaskAttachment {}

@MainActor
fileprivate enum RetainedTaskGroupIdentity {
    case lazy(RetainedLazyListGroupID)
    case descriptor(RetainedDescriptorGroupID)

    func matches(_ other: Self) -> Bool {
        switch (self, other) {
        case (.lazy(let lhs), .lazy(let rhs)): return lhs === rhs
        case (.descriptor(let lhs), .descriptor(let rhs)): return lhs === rhs
        default: return false
        }
    }
}

@MainActor
fileprivate enum RetainedTaskTransportMode {
    case ordinary
    case managed(RetainedTaskGroupIdentity)
}

@MainActor
fileprivate enum RetainedTaskGroupConstruction {
    case lazy(RetainedLazyListBuildAttribution, RetainedLazyListGroupID)
    case descriptor(RetainedDescriptorComponentAttribution, RetainedDescriptorGroupID)

    var identity: RetainedTaskGroupIdentity {
        switch self {
        case .lazy(_, let group): return .lazy(group)
        case .descriptor(_, let group): return .descriptor(group)
        }
    }

    func register(_ declaration: RetainedTaskDeclarationID) -> Bool {
        switch self {
        case .lazy(let attribution, let group):
            return attribution.registerTaskDeclaration(declaration, group: group)
        case .descriptor(let attribution, let group):
            return attribution.registerTaskDeclaration(declaration, group: group)
        }
    }

    func record(_ source: ViewNode) -> RetainedLazyListSourcePayloadID? {
        switch self {
        case .lazy(let attribution, let group):
            return attribution.recordSourceOutput(source, group: group)
        case .descriptor(let attribution, let group):
            return attribution.recordTaskSourceOutput(source, group: group)
        }
    }
}

/// These are two native authorities, not a callback validator or a fabricated
/// row for an ordinary descriptor component. A build scope is not durable here.
@MainActor
fileprivate enum RetainedTaskGroupAuthority {
    case lazy(RetainedLazyListContributionReceipt)
    case descriptor(RetainedDescriptorContributionReceipt)

    var identity: RetainedTaskGroupIdentity {
        switch self {
        case .lazy(let receipt): return .lazy(receipt.group)
        case .descriptor(let receipt): return .descriptor(receipt.group)
        }
    }

    var isActive: Bool {
        switch self {
        case .lazy(let receipt): return receipt.isActive
        case .descriptor(let receipt): return receipt.isActive
        }
    }

    func isSameReceipt(as other: Self) -> Bool {
        switch (self, other) {
        case (.lazy(let lhs), .lazy(let rhs)): return lhs === rhs
        case (.descriptor(let lhs), .descriptor(let rhs)): return lhs === rhs
        default: return false
        }
    }

    func permitsPhysicalContinuity(with other: Self) -> Bool {
        switch (self, other) {
        case (.lazy(let lhs), .lazy(let rhs)):
            return lhs.physical.id === rhs.physical.id
        case (.descriptor(let lhs), .descriptor(let rhs)):
            // The owner separately checks the exact mount, runtime, every
            // actual attachment and every original native Task-state token.
            return lhs.hasSameOwnerLifetime(as: rhs)
        default: return false
        }
    }

    var permitsPhysicalLifetime: Bool {
        switch self {
        case .lazy(let receipt):
            if case .active = receipt.physical.state { return true }
            return false
        case .descriptor:
            // Its CURRENT association supplies the durable descriptor receipt;
            // an older compatible contribution may already be superseded.
            return true
        }
    }
}

/// Construction transports a declaration; only managed adoption associates
/// it with a retained target. Neither step changes that target's live slots.
@MainActor
package final class RetainedTaskDeclaration {
    package let declarationID = RetainedTaskDeclarationID()
    private var transportMode = RetainedTaskTransportMode.ordinary
    fileprivate private(set) var groupAssociation: RetainedTaskGroupAssociation?
    fileprivate let mount: RetainedTaskMountToken
    fileprivate let priority: TaskPriority
    fileprivate let action: @Sendable () async -> Void
    fileprivate let isMember: @MainActor () -> Bool
    private let isCurrentProposal: @MainActor () -> Bool
    fileprivate weak var runtime: RetainedViewRuntime?
    private weak var target: ViewNode?
    private var association: RetainedTaskAssociation?
    private var attachment: RetainedTaskAttachment?
    private var wasStaged = false
    private var didDeliver = false

    package init(
        mount: RetainedTaskMountToken, priority: TaskPriority,
        action: @escaping @Sendable () async -> Void,
        isMember: @escaping @MainActor () -> Bool,
        isCurrentProposal: @escaping @MainActor () -> Bool
    ) {
        self.mount = mount
        self.priority = priority
        self.action = action
        self.isMember = isMember
        self.isCurrentProposal = isCurrentProposal
    }

    package func stage(on source: ViewNode, in runtime: RetainedViewRuntime) {
        guard !wasStaged, runtime.permitsRetainedActionInvocation else { return }
        wasStaged = true
        self.runtime = runtime
        source.retainedTaskState().stage(self)
    }

    package func stage(
        on source: ViewNode, in runtime: RetainedViewRuntime,
        lazyAttribution: RetainedLazyListBuildAttribution, group: RetainedLazyListGroupID
    ) -> Bool {
        stage(groupSources: [source], in: runtime, lazyAttribution: lazyAttribution, group: group)
    }

    package func stage(
        groupSources: [ViewNode], in runtime: RetainedViewRuntime,
        lazyAttribution: RetainedLazyListBuildAttribution, group: RetainedLazyListGroupID
    ) -> Bool {
        stageGroup(groupSources, in: runtime, construction: .lazy(lazyAttribution, group))
    }

    package func stage(
        groupSources: [ViewNode], in runtime: RetainedViewRuntime,
        descriptorAttribution: RetainedDescriptorComponentAttribution, group: RetainedDescriptorGroupID
    ) -> Bool {
        stageGroup(groupSources, in: runtime, construction: .descriptor(descriptorAttribution, group))
    }

    @inline(never)
    private func stageGroup(
        _ sources: [ViewNode], in runtime: RetainedViewRuntime, construction: RetainedTaskGroupConstruction
    ) -> Bool {
        guard !wasStaged else { return false }
        wasStaged = true
        transportMode = .managed(construction.identity)
        guard !sources.isEmpty, runtime.permitsRetainedActionInvocation, construction.register(declarationID)
        else { return false }
        var seen = Set<ObjectIdentifier>()
        var outputs: [(RetainedTaskNodeState, RetainedLazyListSourcePayloadID)] = []
        for source in sources where seen.insert(ObjectIdentifier(source)).inserted {
            guard let payload = construction.record(source) else { return false }
            let state = source.retainedTaskState()
            guard state.acceptsTasks else { return false }
            outputs.append((state, payload))
        }
        self.runtime = runtime
        for (state, payload) in outputs {
            state.stageManaged(self, group: construction.identity, payload: payload)
        }
        return true
    }

    /// This is deliberately independent of the proposal token: the Core
    /// update checks this receipt before publishing that token and its value.
    package var canCommit: Bool {
        if isManagedGroup {
            guard let association = groupAssociation, let owner = association.owner else { return false }
            return owner.canCommit(self, association: association)
        }
        guard let target, let runtime, let state = target.existingRetainedTaskState,
            state.acceptsTasks, state.association === association, state.attachment === attachment,
            target.isRetainedTaskTarget(in: runtime)
        else { return false }
        return isMember()
    }

    package func deliver(restart: Bool) {
        if isManagedGroup {
            guard !didDeliver, let association = groupAssociation, let owner = association.owner,
                owner.canCommit(self, association: association), isCurrentProposal(),
                owner.hasAssociation(association)
            else { return }
            didDeliver = true
            owner.deliver(self, association: association, restart: restart)
            return
        }
        guard !didDeliver, canCommit, isCurrentProposal(),
            let target, let state = target.existingRetainedTaskState
        else { return }
        didDeliver = true
        let slot = state.replace(with: self, restarting: restart)
        // The displaced action and Task have left the inner helper before
        // this check. Their cancellation or destruction may have reentered.
        guard canCommit, isCurrentProposal(), state.contains(slot) else { return }
        if target.hasAppeared, !target.hasPendingAppearanceCallbacks {
            state.start(slot)
        }
    }

    package func appear(on node: ViewNode) {
        if isManagedGroup {
            guard isCurrentProposal() else { return }
            groupAssociation?.owner?.requestStart(for: self, from: node)
            return
        }
        guard node === target, isCurrentProposal() else { return }
        node.existingRetainedTaskState?.appear(self)
    }

    package func disappear(from node: ViewNode) {
        if isManagedGroup {
            // The Runtime has already claimed the original group for its
            // post-forest cleanup. A member hook cannot cancel a later slot.
            groupAssociation?.owner?.noteDisappearance(from: node)
            return
        }
        // A retired owner must still cancel its own captured attempt. Never
        // look through the current slot to find a possibly newer attempt.
        node.existingRetainedTaskState?.disappear(mount: mount)
    }

    fileprivate func associate(
        with target: ViewNode, in runtime: RetainedViewRuntime,
        association: RetainedTaskAssociation, attachment: RetainedTaskAttachment
    ) {
        guard self.runtime === runtime, !didDeliver else { return }
        self.target = target
        self.association = association
        self.attachment = attachment
    }

    fileprivate var isManagedGroup: Bool {
        if case .managed = transportMode { return true }
        return false
    }

    fileprivate var hasCurrentProposal: Bool { isCurrentProposal() }

    fileprivate func associateGroup(_ association: RetainedTaskGroupAssociation) -> Bool {
        guard !didDeliver, case .managed(let group) = transportMode,
            group.matches(association.authority.identity), declarationID === association.declarationID
        else { return false }
        groupAssociation = association
        return true
    }
}

/// The staged Core update owns a proposal until finish. An externally retained
/// source node must not extend an abandoned action's lifetime through transport.
@MainActor
private final class RetainedTaskCandidate {
    let declarationID: RetainedTaskDeclarationID
    let group: RetainedTaskGroupIdentity?
    let payload: RetainedLazyListSourcePayloadID?
    weak var declaration: RetainedTaskDeclaration?

    init(
        _ declaration: RetainedTaskDeclaration,
        group: RetainedTaskGroupIdentity? = nil, payload: RetainedLazyListSourcePayloadID? = nil
    ) {
        declarationID = declaration.declarationID
        self.group = group
        self.payload = payload
        self.declaration = declaration
    }
}

@MainActor
fileprivate final class RetainedTaskAttempt {
    var task: Task<Void, Never>?
    private var wasCancelled = false

    func cancel() {
        guard !wasCancelled else { return }
        wasCancelled = true
        task?.cancel()
    }
}

@MainActor
fileprivate final class RetainedTaskSlot {
    let declaration: RetainedTaskDeclaration
    var attempt: RetainedTaskAttempt?

    init(_ declaration: RetainedTaskDeclaration, attempt: RetainedTaskAttempt? = nil) {
        self.declaration = declaration
        self.attempt = attempt
    }

    var key: ObjectIdentifier { ObjectIdentifier(declaration.mount) }
}

@MainActor
final class RetainedTaskAppearance {
    weak var runtime: RetainedViewRuntime?
    let revision: UInt64

    init(runtime: RetainedViewRuntime, revision: UInt64) {
        self.runtime = runtime
        self.revision = revision
    }
}

@MainActor
final class RetainedTaskDisappearance {
    fileprivate let previous: [RetainedTaskSlot]
    fileprivate let pending: [RetainedTaskSlot]

    fileprivate init(previous: [RetainedTaskSlot], pending: [RetainedTaskSlot]) {
        self.previous = previous
        self.pending = pending
    }

    fileprivate func cancel(mount: RetainedTaskMountToken) {
        for slot in previous where slot.declaration.mount === mount {
            slot.attempt?.cancel()
        }
    }

    fileprivate func cancelAll() {
        for slot in previous { slot.attempt?.cancel() }
    }
}

/// Terminal take pins executable records, including pending actions and
/// attempts temporarily claimed by an onDisappear callback, not just handles.
@MainActor
struct RetainedTaskRetirement {
    fileprivate let slots: [RetainedTaskSlot]
    fileprivate let candidates: [RetainedTaskDeclaration]
    fileprivate let disappearances: [RetainedTaskDisappearance]

    func cancel() {
        for slot in slots { slot.attempt?.cancel() }
        for disappearance in disappearances { disappearance.cancelAll() }
    }
}

/// Allocated only on nodes carrying scoped task metadata. All table keys and
/// receipts are framework identities; no authored Hashable value enters here.
@MainActor
final class RetainedTaskNodeState {
    private weak var node: ViewNode?
    private var candidates: [RetainedTaskCandidate] = []
    private var slots: [ObjectIdentifier: RetainedTaskSlot] = [:]
    private var disappearances: [RetainedTaskDisappearance] = []
    private var appearance: RetainedTaskAppearance?
    private var groupLaunchOwners: [ObjectIdentifier: RetainedTaskGroupLaunchOwner] = [:]
    fileprivate var association = RetainedTaskAssociation()
    fileprivate var attachment = RetainedTaskAttachment()
    fileprivate private(set) var acceptsTasks = true

    init(node: ViewNode) {
        self.node = node
    }

    var hasCommittedSlots: Bool { !slots.isEmpty }

    fileprivate func stage(_ declaration: RetainedTaskDeclaration) {
        guard acceptsTasks else { return }
        candidates.removeAll { $0.declaration == nil }
        candidates.append(RetainedTaskCandidate(declaration))
    }

    @inline(never)
    fileprivate func associate(source: ViewNode, target: ViewNode, in runtime: RetainedViewRuntime) {
        if candidates.contains(where: { $0.group != nil })
            || source.existingRetainedTaskState?.candidates.contains(where: { $0.group != nil }) == true
        {
            associateOrdinaryCandidates(source: source, target: target, in: runtime)
            return
        }
        let sourceState = source.existingRetainedTaskState
        let incoming = sourceState?.candidates.compactMap { $0.declaration } ?? []
        let displaced = source === target ? [] : candidates.compactMap { $0.declaration }
        sourceState?.candidates.removeAll()
        if source !== target { candidates.removeAll() }
        let association = RetainedTaskAssociation()
        self.association = association
        if acceptsTasks {
            for declaration in incoming {
                declaration.associate(
                    with: target, in: runtime, association: association, attachment: attachment)
            }
        }
        // Hooks may release other captures during property adoption. Every
        // incoming receipt already names the actual target before that starts.
        withExtendedLifetime((incoming, displaced)) {}
    }

    fileprivate func contains(_ slot: RetainedTaskSlot) -> Bool {
        slots[slot.key] === slot
    }

    @inline(never)
    fileprivate func replace(
        with declaration: RetainedTaskDeclaration, restarting: Bool
    ) -> RetainedTaskSlot {
        let key = ObjectIdentifier(declaration.mount)
        let previous = slots[key]
        let replacement = RetainedTaskSlot(declaration, attempt: restarting ? nil : previous?.attempt)
        // Publishing this exact slot reserves the mount before cancellation.
        // An older continuation can never erase a later same-mount slot.
        slots[key] = replacement
        if restarting { previous?.attempt?.cancel() }
        withExtendedLifetime(previous) {}
        return replacement
    }

    fileprivate func start(_ slot: RetainedTaskSlot, appearanceRevision: UInt64? = nil) {
        guard acceptsTasks, disappearances.isEmpty, contains(slot), slot.attempt == nil,
            let node, let runtime = slot.declaration.runtime,
            node.isRetainedTaskTarget(in: runtime), slot.declaration.isMember()
        else { return }
        if let appearanceRevision {
            guard node.isRetainedTaskAppearanceCurrent(in: runtime, revision: appearanceRevision) else { return }
        } else {
            guard node.hasAppeared, !node.hasPendingAppearanceCallbacks else { return }
        }
        let attempt = RetainedTaskAttempt()
        slot.attempt = attempt
        let action = slot.declaration.action
        attempt.task = Task(priority: slot.declaration.priority) {
            // Cancellation is cooperative. An admitted Task may first execute
            // after it was cancelled; do not turn that into an uncreated run.
            await action()
        }
    }

    func beginAppearance(in runtime: RetainedViewRuntime, revision: UInt64) -> RetainedTaskAppearance {
        let receipt = RetainedTaskAppearance(runtime: runtime, revision: revision)
        appearance = receipt
        return receipt
    }

    func endAppearance(_ receipt: RetainedTaskAppearance) {
        if appearance === receipt { appearance = nil }
    }

    fileprivate func appear(_ declaration: RetainedTaskDeclaration) {
        guard let appearance, let runtime = appearance.runtime,
            runtime === declaration.runtime,
            let slot = slots[ObjectIdentifier(declaration.mount)], slot.declaration === declaration
        else { return }
        start(slot, appearanceRevision: appearance.revision)
    }

    @inline(never)
    func deliverPendingAppearance(in runtime: RetainedViewRuntime, revision: UInt64) {
        let pending = Array(slots.values)
        for slot in pending where slot.declaration.runtime === runtime {
            // Membership, not the newest tentative proposal token, keeps a
            // preserved pending action alive when a candidate was rejected.
            start(slot, appearanceRevision: revision)
        }
    }

    func invalidateAttachment() {
        association = RetainedTaskAssociation()
        attachment = RetainedTaskAttachment()
        appearance = nil
    }

    func beginDisappearance() -> RetainedTaskDisappearance? {
        guard !slots.isEmpty else { return nil }
        let previous = Array(slots.values)
        let pending = previous.map { RetainedTaskSlot($0.declaration) }
        let receipt = RetainedTaskDisappearance(previous: previous, pending: pending)
        disappearances.append(receipt)
        invalidateAttachment()
        // Claim the old attempts before the first application hook. A still
        // live slot can wait for a later physical appearance with no handle.
        slots = Dictionary(uniqueKeysWithValues: pending.map { ($0.key, $0) })
        return receipt
    }

    fileprivate func disappear(mount: RetainedTaskMountToken) {
        disappearances.last?.cancel(mount: mount)
    }

    func finishDisappearance(_ receipt: RetainedTaskDisappearance) {
        receipt.cancelAll()
        for slot in receipt.pending where contains(slot) && !slot.declaration.isMember() {
            slots.removeValue(forKey: slot.key)
        }
        // The caller pins the whole receipt beyond this removal. Its payload
        // cleanup cannot enter an exclusive array or table mutation.
        disappearances.removeAll { $0 === receipt }
    }

    @inline(never)
    fileprivate func sweepRetired(in runtime: RetainedViewRuntime, attachment: RetainedTaskAttachment) {
        guard acceptsTasks, self.attachment === attachment, let node,
            node.isRetainedTaskTarget(in: runtime)
        else { return }
        let retired = slots.values.filter { !$0.declaration.isMember() }
        for slot in retired where contains(slot) { slots.removeValue(forKey: slot.key) }
        // Every expected record was removed before a handler can reenter and
        // install a new declaration at the same mount.
        for slot in retired { slot.attempt?.cancel() }
    }

    func takeForTerminal() -> RetainedTaskRetirement {
        acceptsTasks = false
        invalidateAttachment()
        let retirement = RetainedTaskRetirement(
            slots: Array(slots.values), candidates: candidates.compactMap { $0.declaration },
            disappearances: disappearances)
        slots.removeAll()
        candidates.removeAll()
        disappearances.removeAll()
        return retirement
    }

    fileprivate func stageManaged(
        _ declaration: RetainedTaskDeclaration, group: RetainedTaskGroupIdentity,
        payload: RetainedLazyListSourcePayloadID
    ) {
        guard acceptsTasks else { return }
        candidates.append(RetainedTaskCandidate(declaration, group: group, payload: payload))
    }

    /// These queries read native staged IDs without promoting weak actions.
    func lazyCandidateDeclarations() -> [(group: RetainedLazyListGroupID, declarations: [RetainedTaskDeclarationID])] {
        var result: [(group: RetainedLazyListGroupID, declarations: [RetainedTaskDeclarationID])] = []
        for candidate in candidates {
            guard case .lazy(let group)? = candidate.group else { continue }
            if let index = result.firstIndex(where: { $0.group === group }) {
                result[index].declarations.append(candidate.declarationID)
            } else {
                result.append((group, [candidate.declarationID]))
            }
        }
        return result
    }

    func descriptorCandidateDeclarations()
        -> [(group: RetainedDescriptorGroupID, declarations: [RetainedTaskDeclarationID])]
    {
        var result: [(group: RetainedDescriptorGroupID, declarations: [RetainedTaskDeclarationID])] = []
        for candidate in candidates {
            guard case .descriptor(let group)? = candidate.group else { continue }
            if let index = result.firstIndex(where: { $0.group === group }) {
                result[index].declarations.append(candidate.declarationID)
            } else {
                result.append((group, [candidate.declarationID]))
            }
        }
        return result
    }

    fileprivate func managedCandidate(
        _ identifier: RetainedTaskDeclarationID, group: RetainedTaskGroupIdentity,
        payload: RetainedLazyListSourcePayloadID
    ) -> RetainedTaskDeclaration? {
        candidates.first {
            $0.declarationID === identifier && $0.payload === payload && $0.group?.matches(group) == true
        }?.declaration
    }

    fileprivate func consumeManagedCandidates(
        group: RetainedTaskGroupIdentity, payload: RetainedLazyListSourcePayloadID,
        declarationIDs: Set<ObjectIdentifier>
    ) {
        candidates.removeAll {
            $0.group?.matches(group) == true && $0.payload === payload
                && declarationIDs.contains(ObjectIdentifier($0.declarationID))
        }
    }

    fileprivate func addParticipation(_ owner: RetainedTaskGroupLaunchOwner) {
        groupLaunchOwners[ObjectIdentifier(owner)] = owner
    }

    fileprivate func hasParticipation(_ owner: RetainedTaskGroupLaunchOwner) -> Bool {
        groupLaunchOwners[ObjectIdentifier(owner)] === owner
    }

    fileprivate func removeParticipation(_ owner: RetainedTaskGroupLaunchOwner) {
        let key = ObjectIdentifier(owner)
        if groupLaunchOwners[key] === owner { groupLaunchOwners.removeValue(forKey: key) }
    }

    /// Only the Runtime's checked end-of-render callback calls this method.
    func noteLazyTaskRenderAdmission(in runtime: RetainedViewRuntime, revision: UInt64) {
        guard let node, node.existingRetainedTaskState === self,
            node.isRetainedLazyTaskRenderAdmissionCurrent(in: runtime, revision: revision)
        else { return }
        let owners = Array(groupLaunchOwners.values)
        for owner in owners { owner.noteRenderedMember(self, in: runtime, revision: revision) }
        withExtendedLifetime(owners) {}
    }

    /// All forest states are queried before the first controller/callback.
    /// Group cleanup is a separate post-forest batch, never a per-leaf finish.
    @inline(never)
    func claimLazyGroupTaskDepartures() -> [RetainedLazyListAcceptedTaskCleanup] {
        let owners = Array(groupLaunchOwners.values)
        var result: [RetainedLazyListAcceptedTaskCleanup] = []
        for owner in owners {
            if let cleanup = owner.claimDeparture(cleanupID: RetainedLazyListCleanupID()) {
                result.append(cleanup)
            }
        }
        withExtendedLifetime(owners) {}
        return result
    }

    func claimLazyAcceptedAbsence(
        _ absence: RetainedLazyListAcceptedAbsence, declarationIDs: [RetainedTaskDeclarationID]
    ) -> RetainedLazyListAcceptedTaskCleanup {
        claimGroupAbsence(.lazy(absence.previous), declarationIDs: declarationIDs, cleanupID: absence.cleanup)
    }

    func claimDescriptorAcceptedAbsence(
        _ absence: RetainedDescriptorAcceptedAbsence, declarationIDs: [RetainedTaskDeclarationID]
    ) -> RetainedLazyListAcceptedTaskCleanup {
        claimGroupAbsence(.descriptor(absence.previous), declarationIDs: declarationIDs, cleanupID: absence.cleanup)
    }

    @inline(never)
    private func claimGroupAbsence(
        _ authority: RetainedTaskGroupAuthority, declarationIDs: [RetainedTaskDeclarationID],
        cleanupID: RetainedLazyListCleanupID
    ) -> RetainedLazyListAcceptedTaskCleanup {
        let owners = Array(groupLaunchOwners.values)
        let identifiers = Set(declarationIDs.map { ObjectIdentifier($0) })
        let claims = owners.compactMap {
            $0.claimAbsence(authority, declarationIDs: identifiers, cleanupID: cleanupID)
        }
        return RetainedLazyListAcceptedTaskCleanup(id: cleanupID, children: claims)
    }

    func claimLazyPhysicalDeparture(
        _ departure: RetainedLazyListAcceptedDeparture
    ) -> RetainedLazyListAcceptedTaskCleanup {
        claimNodeDeparture(cleanupID: departure.cleanup)
    }

    /// Raw Stage2 does not fabricate managed row/group acceptance.
    func claimLazyPhysicalDeparture() -> RetainedLazyListAcceptedTaskCleanup {
        claimNodeDeparture(cleanupID: RetainedLazyListCleanupID())
    }

    @inline(never)
    private func claimNodeDeparture(cleanupID: RetainedLazyListCleanupID) -> RetainedLazyListAcceptedTaskCleanup {
        let originalSlots = Array(slots.values)
        let originalCandidates = candidates.compactMap { $0.declaration }
        var captured = disappearances
        if let receipt = beginDisappearance() {
            captured.append(receipt)
        } else {
            // Ordinary beginDisappearance retains its old zero-slot behavior.
            // Physical retirement must revoke an association even with no slot.
            invalidateAttachment()
        }
        for receipt in captured {
            for slot in receipt.pending where contains(slot) { slots.removeValue(forKey: slot.key) }
        }
        candidates.removeAll()
        // Group owners have already been separately claimed by the forest
        // driver. This payload must not finish their cleanup at the first leaf.
        return RetainedLazyListAcceptedTaskCleanup(
            id: cleanupID, originalState: self,
            originalSlots: originalSlots + captured.flatMap(\.previous),
            originalCandidates: originalCandidates, disappearances: captured)
    }

    @inline(never)
    private func associateOrdinaryCandidates(source: ViewNode, target: ViewNode, in runtime: RetainedViewRuntime) {
        let sourceState = source.existingRetainedTaskState
        let incoming = sourceState?.candidates.filter { $0.group == nil }.compactMap { $0.declaration } ?? []
        let displaced = source === target ? [] : candidates.filter { $0.group == nil }.compactMap { $0.declaration }
        sourceState?.candidates.removeAll { $0.group == nil }
        if source !== target { candidates.removeAll { $0.group == nil } }
        let association = RetainedTaskAssociation()
        self.association = association
        if acceptsTasks {
            for declaration in incoming {
                declaration.associate(with: target, in: runtime, association: association, attachment: attachment)
            }
        }
        withExtendedLifetime((incoming, displaced)) {}
    }
}

/// One owner is shared by every actual member of a Task's accepted footprint.
/// It is native metadata, not a render node or an owner of member nodes.
@MainActor
fileprivate final class RetainedTaskGroupOwnerReference {
    weak var owner: RetainedTaskGroupLaunchOwner?
    weak var runtime: RetainedViewRuntime?

    init(owner: RetainedTaskGroupLaunchOwner, runtime: RetainedViewRuntime) {
        self.owner = owner
        self.runtime = runtime
    }
}

@MainActor
fileprivate final class RetainedTaskGroupLaunchMember {
    let actual: RetainedLazyListActualAttachment
    weak var originalState: RetainedTaskNodeState?
    let originalTaskAttachment: RetainedTaskAttachment
    var renderQualified: Bool

    init(actual: RetainedLazyListActualAttachment, state: RetainedTaskNodeState, runtime: RetainedViewRuntime) {
        self.actual = actual
        originalState = state
        originalTaskAttachment = state.attachment
        renderQualified =
            actual.node?.hasCurrentCompletedRetainedTaskAppearance(
                in: runtime, attachment: actual) == true
    }
}

private struct RetainedTaskGroupMemberKey: Hashable {
    let target: ObjectIdentifier
    let attachment: ObjectIdentifier
}

@MainActor
private struct RetainedTaskGroupMemberPin {
    let member: RetainedTaskGroupLaunchMember
    let node: ViewNode
    let state: RetainedTaskNodeState
}

@MainActor
fileprivate final class RetainedTaskGroupAssociation {
    let declarationID: RetainedTaskDeclarationID
    let authority: RetainedTaskGroupAuthority
    weak var owner: RetainedTaskGroupLaunchOwner?
    weak var declaration: RetainedTaskDeclaration?
    private(set) var wasRevoked = false

    init(
        declaration: RetainedTaskDeclaration, authority: RetainedTaskGroupAuthority,
        owner: RetainedTaskGroupLaunchOwner
    ) {
        declarationID = declaration.declarationID
        self.declaration = declaration
        self.authority = authority
        self.owner = owner
    }

    func revoke() { wasRevoked = true }
}

@MainActor
fileprivate final class RetainedTaskGroupLaunchOwner {
    let mount: RetainedTaskMountToken
    private let originalAuthority: RetainedTaskGroupAuthority
    private let members: [RetainedTaskGroupLaunchMember]
    private weak var runtime: RetainedViewRuntime?
    private var associations: [ObjectIdentifier: RetainedTaskGroupAssociation] = [:]
    private var slot: RetainedTaskSlot?
    private var wasRevoked = false
    private var didClaimDeparture = false

    init(
        mount: RetainedTaskMountToken, authority: RetainedTaskGroupAuthority,
        members: [RetainedTaskGroupLaunchMember], runtime: RetainedViewRuntime
    ) {
        self.mount = mount
        originalAuthority = authority
        self.members = members
        self.runtime = runtime
    }

    func matches(
        authority: RetainedTaskGroupAuthority, members incoming: [RetainedTaskGroupLaunchMember],
        runtime: RetainedViewRuntime
    ) -> Bool {
        guard !wasRevoked, self.runtime === runtime, !members.isEmpty, members.count == incoming.count,
            originalAuthority.permitsPhysicalContinuity(with: authority), originalAuthority.permitsPhysicalLifetime
        else { return false }
        for member in members {
            guard
                let other = incoming.first(where: {
                    $0.actual.target === member.actual.target && $0.actual.attachment === member.actual.attachment
                }), let state = member.originalState,
                other.originalState === state, other.originalTaskAttachment === member.originalTaskAttachment,
                state.attachment === member.originalTaskAttachment, member.actual.isAttached,
                state.hasParticipation(self)
            else { return false }
        }
        return true
    }

    func associate(_ declaration: RetainedTaskDeclaration, authority: RetainedTaskGroupAuthority) -> Bool {
        guard let runtime, !wasRevoked, !members.isEmpty,
            declaration.mount === mount, declaration.runtime === runtime
        else {
            return false
        }
        let receipt = RetainedTaskGroupAssociation(declaration: declaration, authority: authority, owner: self)
        guard declaration.associateGroup(receipt) else { return false }
        let previous = associations.updateValue(receipt, forKey: ObjectIdentifier(declaration.declarationID))
        previous?.revoke()
        for member in members { member.originalState?.addParticipation(self) }
        mount.setGroupLaunchOwner(self, in: runtime)
        return true
    }

    func hasAssociation(_ association: RetainedTaskGroupAssociation) -> Bool {
        !wasRevoked && !association.wasRevoked && association.owner === self && association.authority.isActive
            && associations[ObjectIdentifier(association.declarationID)] === association
    }

    func canCommit(_ declaration: RetainedTaskDeclaration, association: RetainedTaskGroupAssociation) -> Bool {
        guard let runtime, let pins = pinMembers(in: runtime) else { return false }
        return withExtendedLifetime(pins) {
            guard declaration.groupAssociation === association, hasAssociation(association),
                membersAreCurrent(pins, in: runtime), declaration.isMember()
            else { return false }
            // Membership may release a weakly promoted facade owner/cell.
            return hasAssociation(association) && membersAreCurrent(pins, in: runtime)
        }
    }

    func deliver(
        _ declaration: RetainedTaskDeclaration, association: RetainedTaskGroupAssociation, restart: Bool
    ) {
        guard let runtime, let pins = pinMembers(in: runtime) else { return }
        withExtendedLifetime(pins) {
            guard canCommit(declaration, association: association), declaration.hasCurrentProposal,
                hasAssociation(association), membersAreCurrent(pins, in: runtime)
            else { return }
            let replacement = replaceSlot(with: declaration, restart: restart)
            // The helper has released the complete displaced record. A cancel
            // handler or destructor may have closed/replaced this owner.
            guard slot === replacement, canCommit(declaration, association: association),
                declaration.hasCurrentProposal, hasAssociation(association),
                membersAreCurrent(pins, in: runtime)
            else { return }
            start(replacement)
        }
    }

    @inline(never)
    private func replaceSlot(with declaration: RetainedTaskDeclaration, restart: Bool) -> RetainedTaskSlot {
        let previous = slot
        let replacement = RetainedTaskSlot(declaration, attempt: restart ? nil : previous?.attempt)
        slot = replacement
        if let previous, previous.declaration !== declaration, let old = previous.declaration.groupAssociation {
            old.revoke()
            let key = ObjectIdentifier(old.declarationID)
            if associations[key] === old { associations.removeValue(forKey: key) }
        }
        if restart { previous?.attempt?.cancel() }
        withExtendedLifetime(previous) {}
        return replacement
    }

    func requestStart(for declaration: RetainedTaskDeclaration, from node: ViewNode) {
        guard members.contains(where: { $0.actual.node === node }), let slot, slot.declaration === declaration else {
            return
        }
        start(slot)
    }

    func noteRenderedMember(_ state: RetainedTaskNodeState, in runtime: RetainedViewRuntime, revision: UInt64) {
        guard !wasRevoked, self.runtime === runtime,
            let member = members.first(where: { $0.originalState === state }),
            let node = member.actual.node, node.existingRetainedTaskState === state,
            state.attachment === member.originalTaskAttachment, member.actual.isAttached,
            node.isRetainedLazyTaskRenderAdmissionCurrent(in: runtime, revision: revision),
            node.hasCurrentCompletedRetainedTaskAppearance(in: runtime, attachment: member.actual)
        else { return }
        member.renderQualified = true
        if let slot { start(slot) }
    }

    func noteDisappearance(from node: ViewNode) {
        for member in members where member.actual.node === node { member.renderQualified = false }
        // Revocation/claim was performed for the full forest before this hook.
        // Cancellation belongs to that original post-forest cleanup record.
    }

    private func start(_ candidate: RetainedTaskSlot) {
        guard slot === candidate, candidate.attempt == nil,
            let association = candidate.declaration.groupAssociation,
            let runtime, let pins = pinMembers(in: runtime)
        else { return }
        withExtendedLifetime(pins) {
            guard hasAssociation(association), membersAreCurrent(pins, in: runtime, requireRendered: true),
                candidate.declaration.isMember(), slot === candidate, candidate.attempt == nil,
                hasAssociation(association), membersAreCurrent(pins, in: runtime, requireRendered: true)
            else { return }
            let attempt = RetainedTaskAttempt()
            candidate.attempt = attempt
            let action = candidate.declaration.action
            attempt.task = Task(priority: candidate.declaration.priority) { await action() }
        }
    }

    private func pinMembers(in runtime: RetainedViewRuntime) -> [RetainedTaskGroupMemberPin]? {
        guard !wasRevoked, self.runtime === runtime, !members.isEmpty else { return nil }
        var pins: [RetainedTaskGroupMemberPin] = []
        for member in members {
            guard let node = member.actual.node, let state = member.originalState else { return nil }
            pins.append(RetainedTaskGroupMemberPin(member: member, node: node, state: state))
        }
        return pins
    }

    private func membersAreCurrent(
        _ pins: [RetainedTaskGroupMemberPin], in runtime: RetainedViewRuntime, requireRendered: Bool = false
    ) -> Bool {
        guard !wasRevoked, originalAuthority.permitsPhysicalLifetime,
            self.runtime === runtime, runtime.permitsRetainedActionInvocation, pins.count == members.count
        else { return false }
        for pin in pins {
            guard pin.member.actual.node === pin.node, pin.member.actual.runtime === runtime,
                pin.member.originalState === pin.state, pin.state.acceptsTasks,
                pin.state.attachment === pin.member.originalTaskAttachment,
                pin.node.existingRetainedTaskState === pin.state, pin.state.hasParticipation(self),
                pin.member.actual.isAttached, pin.node.isRetainedTaskTarget(in: runtime)
            else { return false }
            if requireRendered {
                guard pin.member.renderQualified,
                    pin.node.hasCurrentCompletedRetainedTaskAppearance(in: runtime, attachment: pin.member.actual)
                else { return false }
            }
        }
        return true
    }

    @inline(never)
    func claimDeparture(cleanupID: RetainedLazyListCleanupID) -> RetainedLazyListAcceptedTaskCleanup? {
        guard !didClaimDeparture else { return nil }
        didClaimDeparture = true
        wasRevoked = true
        let original = slot
        let receipts = Array(associations.values)
        let declarations = receipts.compactMap { $0.declaration }
        slot = nil
        for receipt in receipts { receipt.revoke() }
        associations.removeAll()
        let cleanup = RetainedLazyListAcceptedTaskCleanup(
            id: cleanupID, originalOwner: self, originalSlots: original.map { [$0] } ?? [],
            originalDeclarations: declarations, associations: receipts, permitsTransfer: false)
        if let runtime { mount.clearGroupLaunchOwner(self, in: runtime) }
        for member in members {
            member.renderQualified = false
            member.originalState?.removeParticipation(self)
        }
        return cleanup
    }

    @inline(never)
    func claimAbsence(
        _ authority: RetainedTaskGroupAuthority, declarationIDs: Set<ObjectIdentifier>,
        cleanupID: RetainedLazyListCleanupID
    ) -> RetainedLazyListAcceptedTaskCleanup? {
        let selected = associations.values.filter {
            declarationIDs.contains(ObjectIdentifier($0.declarationID)) && $0.authority.isSameReceipt(as: authority)
        }
        guard !selected.isEmpty else { return nil }
        let selectedIDs = Set(selected.map { ObjectIdentifier($0.declarationID) })
        let original = slot.flatMap { selectedIDs.contains(ObjectIdentifier($0.declaration.declarationID)) ? $0 : nil }
        let declarations = selected.compactMap { $0.declaration }
        for receipt in selected {
            receipt.revoke()
            let key = ObjectIdentifier(receipt.declarationID)
            if associations[key] === receipt { associations.removeValue(forKey: key) }
        }
        // The first accepted lifecycle field may precede the rest of a new
        // group's footprint. Revoke the old association and pin its captures
        // now, without predicting that the remainder will be accepted. Only a
        // later complete compatible group can transfer this exact attempt before
        // cleanup. Partial adoption leaves it revoked and mandatory to cancel.
        return RetainedLazyListAcceptedTaskCleanup(
            id: cleanupID, originalOwner: self, originalSlots: original.map { [$0] } ?? [],
            originalDeclarations: declarations, associations: selected, permitsTransfer: true)
    }

    @inline(never)
    func finishClaimedSlots(_ originals: [RetainedTaskSlot], permitsTransfer: Bool) {
        var cancellations: [RetainedTaskSlot] = []
        for original in originals {
            if slot === original {
                slot = nil
                cancellations.append(original)
            } else if permitsTransfer, let attempt = original.attempt, let replacement = slot,
                replacement.attempt === attempt, replacement.declaration.mount === mount, !wasRevoked
            {
                // The exact attempt is now owned by a later accepted slot on
                // this unchanged physical owner. Old cleanup must not cancel it.
            } else {
                cancellations.append(original)
            }
        }
        retireIfEmpty()
        for original in cancellations { original.attempt?.cancel() }
        withExtendedLifetime(originals) {}
    }

    private func retireIfEmpty() {
        guard slot == nil, associations.isEmpty, !wasRevoked else { return }
        wasRevoked = true
        if let runtime { mount.clearGroupLaunchOwner(self, in: runtime) }
        for member in members {
            member.renderQualified = false
            member.originalState?.removeParticipation(self)
        }
    }
}

@MainActor
private struct RetainedTaskNodeCleanupPayload {
    let originalState: RetainedTaskNodeState
    let originalSlots: [RetainedTaskSlot]
    let originalCandidates: [RetainedTaskDeclaration]
    let disappearances: [RetainedTaskDisappearance]
}

@MainActor
private struct RetainedTaskGroupCleanupPayload {
    let originalOwner: RetainedTaskGroupLaunchOwner
    let originalSlots: [RetainedTaskSlot]
    let originalDeclarations: [RetainedTaskDeclaration]
    let associations: [RetainedTaskGroupAssociation]
    let permitsTransfer: Bool
}

@MainActor
private enum RetainedTaskCleanupPayload {
    case node(RetainedTaskNodeCleanupPayload)
    case group(RetainedTaskGroupCleanupPayload)
    case children([RetainedLazyListAcceptedTaskCleanup])
}

/// Executable records leave this object inside finish. Retaining a finished
/// cleanup ID cannot keep an action, old node state or launch owner alive.
@MainActor
final class RetainedLazyListAcceptedTaskCleanup {
    let id: RetainedLazyListCleanupID
    private(set) var isFinished = false
    private var payload: RetainedTaskCleanupPayload?

    fileprivate init(
        id: RetainedLazyListCleanupID, originalState: RetainedTaskNodeState,
        originalSlots: [RetainedTaskSlot], originalCandidates: [RetainedTaskDeclaration],
        disappearances: [RetainedTaskDisappearance]
    ) {
        self.id = id
        payload = .node(
            RetainedTaskNodeCleanupPayload(
                originalState: originalState, originalSlots: originalSlots,
                originalCandidates: originalCandidates, disappearances: disappearances))
    }

    fileprivate init(
        id: RetainedLazyListCleanupID, originalOwner: RetainedTaskGroupLaunchOwner,
        originalSlots: [RetainedTaskSlot], originalDeclarations: [RetainedTaskDeclaration],
        associations: [RetainedTaskGroupAssociation], permitsTransfer: Bool
    ) {
        self.id = id
        payload = .group(
            RetainedTaskGroupCleanupPayload(
                originalOwner: originalOwner, originalSlots: originalSlots,
                originalDeclarations: originalDeclarations, associations: associations, permitsTransfer: permitsTransfer
            ))
    }

    fileprivate init(id: RetainedLazyListCleanupID, children: [RetainedLazyListAcceptedTaskCleanup]) {
        self.id = id
        payload = .children(children)
    }

    @inline(never)
    func finish() {
        guard !isFinished else { return }
        isFinished = true
        let captured = payload
        payload = nil
        if let captured { finishCaptured(captured) }
    }

    @inline(never)
    private func finishCaptured(_ captured: RetainedTaskCleanupPayload) {
        switch captured {
        case .node(let records):
            for slot in records.originalSlots { slot.attempt?.cancel() }
            for disappearance in records.disappearances { records.originalState.finishDisappearance(disappearance) }
        case .group(let records):
            records.originalOwner.finishClaimedSlots(records.originalSlots, permitsTransfer: records.permitsTransfer)
        case .children(let children):
            for cleanup in children { cleanup.finish() }
        }
        withExtendedLifetime(captured) {}
    }
}

@MainActor
final class RetainedLazyListAcceptedTaskCleanupLedger {
    private var claimed: [RetainedLazyListAcceptedTaskCleanup] = []
    private var isFinishing = false

    func appendClaimed(_ cleanup: RetainedLazyListAcceptedTaskCleanup) {
        guard !cleanup.isFinished, !claimed.contains(where: { $0 === cleanup }) else { return }
        claimed.append(cleanup)
    }

    /// The journal/retirement driver owns the captured synchronous transaction.
    /// Different objects may share a forest cleanup ID; do not dedupe by ID.
    @inline(never)
    func finishClaimed() {
        guard !isFinishing else { return }
        isFinishing = true
        defer { isFinishing = false }
        while !claimed.isEmpty { finishBatch(takeClaimed()) }
    }

    private func takeClaimed() -> [RetainedLazyListAcceptedTaskCleanup] {
        let captured = claimed
        claimed.removeAll()
        return captured
    }

    @inline(never)
    private func finishBatch(_ captured: [RetainedLazyListAcceptedTaskCleanup]) {
        for cleanup in captured { cleanup.finish() }
        withExtendedLifetime(captured) {}
    }
}

/// Created only after a managed root/subtree entered actual adoption. The
/// existing retained-callback queue then runs each sweep after epoch commit,
/// before mounted update delivery; it is not a general construction barrier.
/// Managed group cleanup instead belongs to the journal and finishes after
/// mounted updates, so a compatible update can transfer its original attempt.
@MainActor
final class RetainedTaskAdoptionContext {
    private weak var runtime: RetainedViewRuntime?
    private weak var epoch: (any RetainedBuildEpoch)?
    private let transaction: RetainedBuildTransaction

    init(runtime: RetainedViewRuntime, epoch: any RetainedBuildEpoch, transaction: RetainedBuildTransaction) {
        self.runtime = runtime
        self.epoch = epoch
        self.transaction = transaction
    }

    func associate(source: ViewNode, target: ViewNode) {
        guard let runtime, runtime.permitsRetainedActionInvocation,
            source.existingRetainedTaskState != nil || target.existingRetainedTaskState != nil
        else { return }
        let state = target.retainedTaskState()
        state.associate(source: source, target: target, in: runtime)
        guard state.acceptsTasks, state.hasCommittedSlots else { return }
        let attachment = state.attachment
        let transaction = transaction
        let epoch = epoch
        runtime.afterRetainedCallbacks { [weak runtime, weak epoch, weak state] in
            guard let runtime, epoch?.canComplete == true, let state else { return }
            transaction.perform { state.sweepRetired(in: runtime, attachment: attachment) }
        }
    }

    @discardableResult
    func associateLazyAccepted(
        _ group: RetainedLazyListAcceptedTaskGroup, journal: RetainedLazyListAdoptionJournal
    ) -> Bool {
        var associated = false
        transaction.perform {
            guard let runtime, runtime.permitsRetainedActionInvocation,
                let sources = journal.acceptedTaskSources(for: group)
            else { return }
            associated = associateGroup(
                authority: .lazy(group.contribution.receipt), declarationIDs: group.declarationIDs,
                members: group.members, sources: sources, runtime: runtime, journal: journal)
        }
        return associated
    }

    @discardableResult
    func associateDescriptorAccepted(
        _ group: RetainedDescriptorAcceptedTaskGroup, journal: RetainedLazyListAdoptionJournal
    ) -> Bool {
        var associated = false
        transaction.perform {
            guard let runtime, runtime.permitsRetainedActionInvocation,
                let sources = journal.acceptedDescriptorTaskSources(for: group)
            else { return }
            associated = associateGroup(
                authority: .descriptor(group.contribution.receipt), declarationIDs: group.declarationIDs,
                members: group.members, sources: sources, runtime: runtime, journal: journal)
        }
        return associated
    }

    @inline(never)
    private func associateGroup(
        authority: RetainedTaskGroupAuthority, declarationIDs: [RetainedTaskDeclarationID],
        members: [RetainedLazyListAcceptedTaskMember], sources: [RetainedLazyListAcceptedTaskSource],
        runtime: RetainedViewRuntime, journal: RetainedLazyListAdoptionJournal
    ) -> Bool {
        let identifiers = Set(declarationIDs.map { ObjectIdentifier($0) })
        guard !members.isEmpty, !identifiers.isEmpty, identifiers.count == declarationIDs.count,
            sources.count == members.count
        else { return false }
        var seenSources = Set<ObjectIdentifier>()
        var targetPins: [ViewNode] = []
        var launchMembers: [RetainedTaskGroupLaunchMember] = []
        var seenTargets = Set<RetainedTaskGroupMemberKey>()
        for source in sources {
            guard let expected = members.first(where: { $0.sourcePayload === source.member.sourcePayload }),
                expected.actual.target === source.member.actual.target,
                expected.actual.attachment === source.member.actual.attachment,
                seenSources.insert(ObjectIdentifier(source.member.sourcePayload)).inserted,
                let target = source.member.actual.node, source.member.actual.runtime === runtime
            else { return false }
            targetPins.append(target)
            let key = RetainedTaskGroupMemberKey(
                target: ObjectIdentifier(source.member.actual.target),
                attachment: ObjectIdentifier(source.member.actual.attachment))
            // Distinct source leaves cannot both supply the same actual field
            // footprint. Independent groups may still share this target.
            guard seenTargets.insert(key).inserted else { return false }
            launchMembers.append(
                RetainedTaskGroupLaunchMember(
                    actual: source.member.actual, state: target.retainedTaskState(), runtime: runtime))
        }
        var declarations: [RetainedTaskDeclaration] = []
        for identifier in declarationIDs {
            var declaration: RetainedTaskDeclaration?
            var complete = true
            for source in sources {
                guard
                    let staged = source.source.existingRetainedTaskState?.managedCandidate(
                        identifier, group: authority.identity, payload: source.member.sourcePayload)
                else {
                    complete = false
                    break
                }
                if let original = declaration {
                    guard original === staged else {
                        complete = false
                        break
                    }
                } else {
                    declaration = staged
                }
            }
            if complete, let declaration, declaration.runtime === runtime { declarations.append(declaration) }
        }
        // The accepted native source subset is consumed once. No ordinary
        // declaration or independent managed group is drained here.
        for source in sources {
            source.source.existingRetainedTaskState?.consumeManagedCandidates(
                group: authority.identity, payload: source.member.sourcePayload, declarationIDs: identifiers)
        }
        var count = 0
        for declaration in declarations {
            let owner: RetainedTaskGroupLaunchOwner
            if let existing = declaration.mount.groupLaunchOwner(in: runtime),
                existing.matches(authority: authority, members: launchMembers, runtime: runtime)
            {
                owner = existing
            } else {
                if let previous = declaration.mount.groupLaunchOwner(in: runtime),
                    let cleanup = previous.claimDeparture(cleanupID: RetainedLazyListCleanupID())
                {
                    journal.claimTaskCleanup(cleanup)
                }
                owner = RetainedTaskGroupLaunchOwner(
                    mount: declaration.mount, authority: authority, members: launchMembers, runtime: runtime)
            }
            if owner.associate(declaration, authority: authority) { count += 1 }
        }
        withExtendedLifetime((targetPins, sources, declarations)) {}
        return count == declarationIDs.count
    }

}
