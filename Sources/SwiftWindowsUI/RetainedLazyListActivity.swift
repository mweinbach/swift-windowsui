import SwiftWindowsCore

// These allocation identities carry no application payload. Tables retain the
// corresponding identity while using ObjectIdentifier as their native key.
@MainActor
package final class RetainedLazyListMembershipID: Sendable {
    fileprivate var wasRevoked = false
    package init() {}
}
package final class RetainedLazyListLogicalDeclarationID: Sendable { package init() {} }
package final class RetainedLazyListLogicalProposalID: Sendable { package init() {} }
package final class RetainedLazyListAttemptID: Sendable { init() {} }
package final class RetainedLazyListPhysicalActivityID: Sendable { init() {} }
package final class RetainedLazyListComponentID: Sendable { init() {} }
package final class RetainedLazyListGroupID: Sendable { init() {} }
package final class RetainedLazyListSourcePayloadID: Sendable { init() {} }
package final class RetainedLazyListSourceFacetID: Sendable { init() {} }
package final class RetainedLazyListTargetID: Sendable { init() {} }
package final class RetainedLazyListAttachmentID: Sendable { init() {} }
package final class RetainedLazyListContributionID: Sendable { init() {} }
package final class RetainedLazyListCleanupID: Sendable { init() {} }
package final class RetainedLazyListLogicalScopeID: Sendable { init() {} }
package final class RetainedLazyListRowResolutionID: Sendable { init() {} }
package final class RetainedTaskDeclarationID: Sendable { init() {} }
private final class RetainedLazyListLogicalRosterRevision: Sendable {}

package enum RetainedLazyListContributionKind: Equatable, Sendable {
    case structure, ownedState, observation, preferenceObservation, scopedTask
    case objectDependency, deferredSubtree, presentation, alert
    // A list lease owns its descriptor, not a GeometryReader child region.
    case lazyList
}

package enum RetainedLazyListConstructionState: Equatable, Sendable {
    case admittedForConstruction, rejected
}

package enum RetainedLazyListPhysicalActivityState: Equatable, Sendable {
    case provisional, active, revoked
}

package enum RetainedLazyListGroupConstruction: Equatable, Sendable {
    case open, closedWithFacets, closedEmpty
}

package enum RetainedLazyListLogicalMembershipPhase: Equatable, Sendable {
    case proposed, declared, revoked
}

package enum RetainedLazyListDescriptorBuildOrigin: Equatable, Sendable {
    case componentHostRoot, managedSubtree
}

@MainActor
final class RetainedLazyListLogicalHostLifetime {
    /// Navigation may outlive a plain weak runtime without keeping descriptor
    /// scopes alive. This scalar witness records only an explicit host close.
    @MainActor
    final class CloseWitness {
        private var wasRevoked: Bool

        init(wasRevoked: Bool) { self.wasRevoked = wasRevoked }
        var isOpen: Bool { !wasRevoked }
        func revoke() { wasRevoked = true }
    }

    private var wasRevoked = false
    private var navigationCloseWitness: CloseWitness?
    var isOpen: Bool { !wasRevoked }

    func captureNavigationCloseWitness() -> CloseWitness {
        if let navigationCloseWitness { return navigationCloseWitness }
        let witness = CloseWitness(wasRevoked: wasRevoked)
        navigationCloseWitness = witness
        return witness
    }

    func revoke() {
        wasRevoked = true
        navigationCloseWitness?.revoke()
    }
}

@MainActor
final class RetainedLazyListDescriptorOwnerLifetime {
    let target: RetainedLazyListTargetID
    let attachment: RetainedLazyListAttachmentID
    private var wasRevoked = false

    init(target: RetainedLazyListTargetID, attachment: RetainedLazyListAttachmentID) {
        self.target = target
        self.attachment = attachment
    }

    var isCurrent: Bool { !wasRevoked }
    func revoke() { wasRevoked = true }
}

@MainActor
private final class RetainedLazyListDescriptorBuildState {
    enum Phase { case constructing, prepared, adopting, finishing, finished }
    let attempt = RetainedLazyListAttemptID()
    var phase: Phase = .constructing
    var wasSupersededBeforeAdoption = false
    var wasRevoked = false
    var didAcceptDescriptor = false
    var acceptedOriginalRetirements: Set<ObjectIdentifier> = []
}

@MainActor
private enum RetainedLazyListDescriptorContainingAdmission {
    case topLevel
    case selectedRow(RetainedLazyListBuildAttribution)
    case deferred(RetainedLazyListContributionReceipt, RetainedLazyListActualAttachment)
    case ordinaryDeferred(RetainedDescriptorContributionReceipt, RetainedLazyListActualAttachment)

    func canConstruct(using query: inout RetainedLazyListAttachmentQuery) -> Bool {
        switch self {
        case .topLevel: true
        case .selectedRow(let attribution): attribution.canConstructNestedDescriptor
        case .deferred(let contribution, let actual): contribution.isActive && actual.isAttached(using: &query)
        case .ordinaryDeferred(let contribution, let actual):
            contribution.isActive(using: &query) && actual.isAttached(using: &query)
        }
    }

    var canPublish: Bool {
        switch self {
        case .topLevel: true
        case .selectedRow(let attribution): attribution.canPublishNestedDescriptor
        case .deferred(let contribution, let actual): contribution.isActive && actual.isAttached
        case .ordinaryDeferred(let contribution, let actual): contribution.isActive && actual.isAttached
        }
    }

    var canComplete: Bool {
        switch self {
        case .topLevel: true
        case .selectedRow(let attribution):
            attribution.logicalMembership.isDeclared && attribution.physical.state == .active
        case .deferred(let contribution, let actual): contribution.isActive && actual.isAttached
        case .ordinaryDeferred(let contribution, let actual): contribution.isActive && actual.isAttached
        }
    }

    func accepts(parent: RetainedLazyListLogicalMembershipReceipt?) -> Bool {
        switch self {
        case .topLevel: parent == nil
        case .selectedRow(let attribution): parent === attribution.logicalMembership
        case .deferred(let contribution, _): parent?.id === contribution.physical.membership
        case .ordinaryDeferred: parent == nil
        }
    }
}

/// Native phase and lifetime only. Queued requests cannot undo an adoption that
/// started; owner close denies every phase without discarding accepted cleanup.
@MainActor
package final class RetainedLazyListDescriptorBuildScope {
    package let attempt: RetainedLazyListAttemptID
    package let origin: RetainedLazyListDescriptorBuildOrigin
    private weak var hostLifetime: RetainedLazyListLogicalHostLifetime?
    private let ownerLifetime: RetainedLazyListDescriptorOwnerLifetime
    private let state: RetainedLazyListDescriptorBuildState
    private let enclosing: RetainedLazyListDescriptorBuildScope?
    private let containing: RetainedLazyListDescriptorContainingAdmission
    fileprivate let ordinaryLedger: RetainedDescriptorConstructionLedger
    fileprivate let ownedLedger: RetainedOwnedComponentConstructionLedger

    init(
        origin: RetainedLazyListDescriptorBuildOrigin,
        hostLifetime: RetainedLazyListLogicalHostLifetime,
        ownerLifetime: RetainedLazyListDescriptorOwnerLifetime
    ) {
        let state = RetainedLazyListDescriptorBuildState()
        self.state = state
        attempt = state.attempt
        self.origin = origin
        self.hostLifetime = hostLifetime
        self.ownerLifetime = ownerLifetime
        enclosing = nil
        containing = .topLevel
        ordinaryLedger = RetainedDescriptorConstructionLedger(
            attempt: state.attempt, hostLifetime: hostLifetime, ownerLifetime: ownerLifetime)
        ownedLedger = RetainedOwnedComponentConstructionLedger(attempt: state.attempt)
    }

    private init(
        enclosing: RetainedLazyListDescriptorBuildScope,
        containing: RetainedLazyListDescriptorContainingAdmission,
        originalOwner: RetainedLazyListDescriptorOwnerLifetime? = nil
    ) {
        state = enclosing.state
        attempt = enclosing.attempt
        origin = enclosing.origin
        hostLifetime = enclosing.hostLifetime
        ownerLifetime = originalOwner ?? enclosing.ownerLifetime
        self.enclosing = enclosing
        self.containing = containing
        ordinaryLedger = enclosing.ordinaryLedger
        ownedLedger = enclosing.ownedLedger
    }

    private var ownerIsCurrent: Bool {
        !state.wasRevoked && hostLifetime?.isOpen == true && ownerLifetime.isCurrent
    }

    package var canConstructDescriptors: Bool {
        var query = RetainedLazyListAttachmentQuery()
        return canConstructDescriptors(using: &query)
    }

    func canConstructDescriptors(using query: inout RetainedLazyListAttachmentQuery) -> Bool {
        ownerIsCurrent && state.phase == .constructing && !state.wasSupersededBeforeAdoption
            && enclosing?.canConstructDescriptors(using: &query) != false && containing.canConstruct(using: &query)
    }

    package var canPublishDescriptors: Bool {
        guard ownerIsCurrent, enclosing?.canPublishDescriptors != false,
            containing.canPublish || canFinishOriginalRetirement
        else { return false }
        switch state.phase {
        case .prepared: return !state.wasSupersededBeforeAdoption
        case .adopting: return true
        case .constructing, .finishing, .finished: return false
        }
    }

    package var canCompleteAcceptedDescriptors: Bool {
        guard ownerIsCurrent, state.didAcceptDescriptor,
            enclosing?.canCompleteAcceptedDescriptors != false,
            containing.canComplete || canFinishOriginalRetirement
        else { return false }
        return state.phase == .adopting || state.phase == .finishing
    }

    private var canFinishOriginalRetirement: Bool {
        guard state.phase == .adopting || state.phase == .finishing else { return false }
        switch containing {
        case .deferred(let contribution, let actual):
            return state.acceptedOriginalRetirements.contains(ObjectIdentifier(contribution))
                && contribution.permitsOriginalCompletion && actual.isAttached
        case .ordinaryDeferred(let contribution, let actual):
            return state.acceptedOriginalRetirements.contains(ObjectIdentifier(contribution))
                && contribution.nativeHostLifetime?.isOpen == true
                && contribution.nativeOwnerLifetime.isCurrent && actual.isAttached
        case .topLevel, .selectedRow: return false
        }
    }

    func recordAcceptedOriginalRetirement(_ contribution: RetainedLazyListContributionReceipt) {
        guard ownerIsCurrent, state.phase == .adopting else { return }
        if case .deferred(let original, _) = containing, original === contribution {
            state.acceptedOriginalRetirements.insert(ObjectIdentifier(contribution))
        }
        enclosing?.recordAcceptedOriginalRetirement(contribution)
    }

    func recordAcceptedOriginalRetirement(_ contribution: RetainedDescriptorContributionReceipt) {
        guard ownerIsCurrent, state.phase == .adopting else { return }
        if case .ordinaryDeferred(let original, _) = containing, original === contribution {
            state.acceptedOriginalRetirements.insert(ObjectIdentifier(contribution))
        }
        enclosing?.recordAcceptedOriginalRetirement(contribution)
    }

    package func withContainingRow(
        _ attribution: RetainedLazyListBuildAttribution
    ) -> RetainedLazyListDescriptorBuildScope? {
        guard canConstructDescriptors, attribution.canConstructNestedDescriptor else { return nil }
        return RetainedLazyListDescriptorBuildScope(enclosing: self, containing: .selectedRow(attribution))
    }

    package func registerOrdinaryComponent() -> RetainedDescriptorComponentAttribution? {
        ordinaryLedger.registerRoot(in: self)
    }

    package func withAdmittedDeferredSubtree(
        originalActivity: RetainedLazyListContributionReceipt,
        originalAttachment: RetainedLazyListActualAttachment
    ) -> RetainedLazyListDescriptorBuildScope? {
        guard origin == .managedSubtree, canConstructDescriptors,
            originalActivity.isActive, originalAttachment.isAttached
        else { return nil }
        return RetainedLazyListDescriptorBuildScope(
            enclosing: self, containing: .deferred(originalActivity, originalAttachment))
    }

    package func withAdmittedOrdinaryDeferredSubtree(
        originalActivity: RetainedDescriptorContributionReceipt,
        originalAttachment: RetainedLazyListActualAttachment
    ) -> RetainedLazyListDescriptorBuildScope? {
        guard origin == .managedSubtree, canConstructDescriptors,
            originalActivity.isActive, originalAttachment.isAttached,
            originalActivity.nativeHostLifetime === hostLifetime
        else { return nil }
        return RetainedLazyListDescriptorBuildScope(
            enclosing: self, containing: .ordinaryDeferred(originalActivity, originalAttachment),
            originalOwner: originalActivity.nativeOwnerLifetime)
    }

    var logicalHostLifetimeForScopeConstruction: RetainedLazyListLogicalHostLifetime? {
        canConstructDescriptors ? hostLifetime : nil
    }

    fileprivate var nativeHostLifetime: RetainedLazyListLogicalHostLifetime? { hostLifetime }
    fileprivate var nativeOwnerLifetime: RetainedLazyListDescriptorOwnerLifetime { ownerLifetime }

    func acceptsLogicalParent(_ parent: RetainedLazyListLogicalMembershipReceipt?) -> Bool {
        containing.accepts(parent: parent)
    }

    func preparationDidSucceed() {
        if state.phase == .constructing, canConstructDescriptors { state.phase = .prepared }
    }

    @discardableResult
    func beginAdoption() -> Bool {
        guard canPublishDescriptors else { return false }
        state.phase = .adopting
        return true
    }

    func observeOrdinaryAdoption() -> Bool {
        guard ownerIsCurrent, state.phase == .constructing || state.phase == .prepared else { return false }
        // The legacy epoch has already accepted. This does not reopen any
        // managed construction: phase advances directly to observation/adoption.
        state.phase = .adopting
        return true
    }

    func recordAcceptedDescriptor() { state.didAcceptDescriptor = true }

    func noteSupersedingRequest() {
        if state.phase == .constructing || state.phase == .prepared {
            state.wasSupersededBeforeAdoption = true
        }
    }

    /// Facade failure/supersession may occur without scheduling a root request.
    /// It denies pending construction only; accepted adoption still completes.
    package func stopConstruction() { noteSupersedingRequest() }

    func revoke() { state.wasRevoked = true }

    package func revokeForOwnerClose() {
        state.wasRevoked = true
        ownerLifetime.revoke()
    }

    func beginFinishing() {
        if state.phase != .finished { state.phase = .finishing }
    }

    func finish() { state.phase = .finished }
}

@MainActor
private final class RetainedLazyListWeakLogicalMembership {
    let id: RetainedLazyListMembershipID
    weak var receipt: RetainedLazyListLogicalMembershipReceipt?
    init(_ receipt: RetainedLazyListLogicalMembershipReceipt) {
        id = receipt.id
        self.receipt = receipt
    }
}

/// Logical scopes retain no provider, view context, node, owned cell or callback.
@MainActor
package final class RetainedLazyListLogicalMembershipScope {
    package let id = RetainedLazyListLogicalScopeID()
    private weak var hostLifetime: RetainedLazyListLogicalHostLifetime?
    fileprivate let parentRow: RetainedLazyListLogicalMembershipReceipt?
    private var wasRevoked = false
    private var acceptedDescriptor: RetainedLazyListLogicalDeclarationID?
    private var rosterRevision = RetainedLazyListLogicalRosterRevision()
    private var sparse: [ObjectIdentifier: RetainedLazyListWeakLogicalMembership] = [:]

    package init(in runtime: RetainedViewRuntime, parentRow: RetainedLazyListLogicalMembershipReceipt?) {
        hostLifetime = runtime.lazyListLogicalHostLifetime
        self.parentRow = parentRow
    }

    package init?(
        in buildScope: RetainedLazyListDescriptorBuildScope,
        parentRow: RetainedLazyListLogicalMembershipReceipt?
    ) {
        guard buildScope.canConstructDescriptors, buildScope.acceptsLogicalParent(parentRow),
            let lifetime = buildScope.logicalHostLifetimeForScopeConstruction
        else { return nil }
        hostLifetime = lifetime
        self.parentRow = parentRow
    }

    fileprivate var canStage: Bool {
        !wasRevoked && hostLifetime?.isOpen == true && parentRow?.permitsConstruction != false
    }

    package var isLogicallyLive: Bool {
        canStage && parentRow?.isDeclared != false
    }

    package func snapshot() -> RetainedLazyListLogicalMembershipSnapshot {
        pruneSparseMemberships()
        return RetainedLazyListLogicalMembershipSnapshot(
            scope: self, acceptedDescriptor: acceptedDescriptor,
            declared: sparse.values.compactMap(\.receipt).filter { $0.phase == .declared },
            rosterRevision: rosterRevision)
    }

    package func proposeMembership(id: RetainedLazyListMembershipID) -> RetainedLazyListLogicalMembershipReceipt? {
        guard canStage, !id.wasRevoked else { return nil }
        pruneSparseMemberships()
        if let existing = sparse[ObjectIdentifier(id)]?.receipt {
            return existing.phase == .revoked ? nil : existing
        }
        let receipt = RetainedLazyListLogicalMembershipReceipt(id: id, scope: self)
        sparse[ObjectIdentifier(id)] = RetainedLazyListWeakLogicalMembership(receipt)
        rosterRevision = RetainedLazyListLogicalRosterRevision()
        return receipt
    }

    package func admitSparseMembership(
        _ proof: RetainedLazyListPriorLogicalMembershipProof
    ) -> RetainedLazyListLogicalMembershipReceipt? {
        guard proof.scope === self, proof.isCurrent, isLogicallyLive,
            acceptedDescriptor === proof.acceptedDescriptor,
            let receipt = proposeMembership(id: proof.membership)
        else { return nil }
        guard proof.consume() else { return nil }
        if receipt.phase == .proposed {
            receipt.activate()
            rosterRevision = RetainedLazyListLogicalRosterRevision()
        }
        return receipt.isDeclared ? receipt : nil
    }

    package func revokeLogicalMembership() {
        wasRevoked = true
        sparse.removeAll()
        rosterRevision = RetainedLazyListLogicalRosterRevision()
    }
    func revoke() { revokeLogicalMembership() }

    private func pruneSparseMemberships() {
        let expired = sparse.filter { $0.value.receipt == nil || $0.value.receipt?.phase == .revoked }.map(\.key)
        guard !expired.isEmpty else { return }
        for key in expired { sparse.removeValue(forKey: key) }
        rosterRevision = RetainedLazyListLogicalRosterRevision()
    }

    package func isCurrent(_ snapshot: RetainedLazyListLogicalMembershipSnapshot) -> Bool {
        canStage && snapshot.scope === self && snapshot.rosterRevision === rosterRevision
            && snapshot.acceptedDescriptor === acceptedDescriptor
    }

    package func containsDeclaredDescriptor(_ descriptor: RetainedLazyListLogicalDeclarationID) -> Bool {
        isLogicallyLive && acceptedDescriptor === descriptor
    }

    fileprivate func publish(_ plan: RetainedLazyListLogicalMembershipPlan) {
        // These records have no application payload; publish scalar revocation
        // before any caller releases the displaced descriptor/provider.
        for receipt in plan.deleted { receipt.revoke() }
        for receipt in plan.introduced { receipt.activate() }
        acceptedDescriptor = plan.descriptor
        pruneSparseMemberships()
        rosterRevision = RetainedLazyListLogicalRosterRevision()
    }
}

@MainActor
package final class RetainedLazyListLogicalMembershipReceipt {
    package let id: RetainedLazyListMembershipID
    package let scope: RetainedLazyListLogicalMembershipScope
    package private(set) var phase: RetainedLazyListLogicalMembershipPhase = .proposed
    fileprivate var ownedDeclaredSlots: [ObjectIdentifier: RetainedOwnedWeakSlotPermission] = [:]
    fileprivate var ownedDeclaredComponents: [ObjectIdentifier: RetainedOwnedWeakComponentPresence] = [:]

    init(id: RetainedLazyListMembershipID, scope: RetainedLazyListLogicalMembershipScope) {
        self.id = id
        self.scope = scope
    }

    package var isDeclared: Bool { phase == .declared && scope.isLogicallyLive }
    var permitsConstruction: Bool { phase != .revoked && scope.canStage }
    fileprivate func activate() { if phase == .proposed { phase = .declared } }
    func revoke() {
        phase = .revoked
        id.wasRevoked = true
    }
}

@MainActor
package struct RetainedLazyListLogicalMembershipSnapshot {
    package let scope: RetainedLazyListLogicalMembershipScope
    package let acceptedDescriptor: RetainedLazyListLogicalDeclarationID?
    package let declared: [RetainedLazyListLogicalMembershipReceipt]
    fileprivate let rosterRevision: RetainedLazyListLogicalRosterRevision
}

@MainActor
package final class RetainedLazyListLogicalMembershipPlan {
    package let descriptor: RetainedLazyListLogicalDeclarationID
    package let facadeProposal: RetainedLazyListLogicalProposalID
    package let expected: RetainedLazyListLogicalMembershipSnapshot
    package let introduced: [RetainedLazyListLogicalMembershipReceipt]
    package let retained: [RetainedLazyListLogicalMembershipReceipt]
    package let deleted: [RetainedLazyListLogicalMembershipReceipt]
    let sourceGeneration: RetainedLazyListGeneration
    private var wasPublished = false

    package init?(
        descriptor: RetainedLazyListLogicalDeclarationID,
        facadeProposal: RetainedLazyListLogicalProposalID,
        expected: RetainedLazyListLogicalMembershipSnapshot,
        sourceGeneration: RetainedLazyListGeneration,
        introduced: [RetainedLazyListLogicalMembershipReceipt],
        retained: [RetainedLazyListLogicalMembershipReceipt],
        deleted: [RetainedLazyListLogicalMembershipReceipt]
    ) {
        let originalIDs = Set(expected.declared.map { ObjectIdentifier($0) })
        let retainedIDs = Set(retained.map { ObjectIdentifier($0) })
        let deletedIDs = Set(deleted.map { ObjectIdentifier($0) })
        let introducedIDs = Set(introduced.map { ObjectIdentifier($0) })
        guard sourceGeneration.isCurrent, expected.scope.isCurrent(expected),
            retainedIDs.count == retained.count, deletedIDs.count == deleted.count,
            introducedIDs.count == introduced.count,
            retainedIDs.isDisjoint(with: deletedIDs),
            introducedIDs.isDisjoint(with: originalIDs),
            retainedIDs.union(deletedIDs) == originalIDs,
            (introduced + retained + deleted).allSatisfy({ $0.scope === expected.scope }),
            introduced.allSatisfy({ $0.phase == .proposed }),
            (retained + deleted).allSatisfy({ $0.phase == .declared })
        else { return nil }
        self.descriptor = descriptor
        self.facadeProposal = facadeProposal
        self.expected = expected
        self.sourceGeneration = sourceGeneration
        self.introduced = introduced
        self.retained = retained
        self.deleted = deleted
    }

    var isCurrent: Bool {
        !wasPublished && sourceGeneration.isCurrent && expected.scope.isCurrent(expected)
            && introduced.allSatisfy { $0.phase == .proposed }
            && (retained + deleted).allSatisfy { $0.phase == .declared }
    }

    @discardableResult
    fileprivate func publishAccepted() -> Bool {
        guard !wasPublished else { return false }
        wasPublished = true
        expected.scope.publish(self)
        return true
    }
}

@MainActor
package final class RetainedLazyListManagedLogicalDescriptorBinding {
    package let descriptor: RetainedLazyListLogicalDeclarationID
    package let facadeProposal: RetainedLazyListLogicalProposalID
    package let scope: RetainedLazyListLogicalMembershipScope
    package let sourceGeneration: RetainedLazyListGeneration
    package let declaredRecordCount: Int
    private var wasRevoked = false

    package init(
        descriptor: RetainedLazyListLogicalDeclarationID,
        facadeProposal: RetainedLazyListLogicalProposalID,
        scope: RetainedLazyListLogicalMembershipScope,
        metadata: RetainedLazyListMetadata
    ) {
        self.descriptor = descriptor
        self.facadeProposal = facadeProposal
        self.scope = scope
        sourceGeneration = metadata.generation
        declaredRecordCount = metadata.rows.count
    }

    package var isCurrent: Bool {
        !wasRevoked && sourceGeneration.isCurrent && scope.canStage
    }

    func revoke() { wasRevoked = true }
}

@MainActor
package final class RetainedLazyListPriorLogicalMembershipProof {
    package let scope: RetainedLazyListLogicalMembershipScope
    package let acceptedDescriptor: RetainedLazyListLogicalDeclarationID
    package let facadeProposal: RetainedLazyListLogicalProposalID
    package let membership: RetainedLazyListMembershipID
    package let request: RetainedLazyListRowRequest
    private let sourceGeneration: RetainedLazyListGeneration
    private weak var admission: RetainedLazyListAdoptionAdmission?
    private var wasConsumed = false

    init(
        scope: RetainedLazyListLogicalMembershipScope,
        acceptedDescriptor: RetainedLazyListLogicalDeclarationID,
        facadeProposal: RetainedLazyListLogicalProposalID,
        membership: RetainedLazyListMembershipID,
        request: RetainedLazyListRowRequest,
        sourceGeneration: RetainedLazyListGeneration,
        admission: RetainedLazyListAdoptionAdmission
    ) {
        self.scope = scope
        self.acceptedDescriptor = acceptedDescriptor
        self.facadeProposal = facadeProposal
        self.membership = membership
        self.request = request
        self.sourceGeneration = sourceGeneration
        self.admission = admission
    }

    package var isCurrent: Bool {
        !wasConsumed && admission?.isBuildCurrent == true && request.isGenerationCurrent
            && sourceGeneration.isCurrent && scope.containsDeclaredDescriptor(acceptedDescriptor)
    }

    fileprivate func consume() -> Bool {
        guard isCurrent else { return false }
        wasConsumed = true
        return true
    }
}

@MainActor
package final class RetainedLazyListActualAttachment {
    package let target: RetainedLazyListTargetID
    package let attachment: RetainedLazyListAttachmentID
    private let proof: RetainedLazyListAttachmentProof
    private let identity: RetainedLazyListViewIdentityProof
    weak var node: ViewNode?
    weak var runtime: RetainedViewRuntime?

    init(
        node: ViewNode, runtime: RetainedViewRuntime,
        target: RetainedLazyListTargetID, attachment: RetainedLazyListAttachmentID
    ) {
        self.node = node
        self.runtime = runtime
        self.target = target
        self.attachment = attachment
        proof = node.captureLazyListAttachmentProof()
        identity = node.captureLazyListIdentityProof()
    }

    package var isAttached: Bool {
        guard let node, let runtime, node.isRetainedLazyListAttached(in: runtime) else { return false }
        return matchesCurrentAttachment(on: node)
    }

    func isAttached(using query: inout RetainedLazyListAttachmentQuery) -> Bool {
        guard let node, let runtime, query.isAttached(node, in: runtime) else { return false }
        return matchesCurrentAttachment(on: node)
    }

    /// A returned standalone tree may keep using its existing physical rows
    /// after an otherwise open runtime expires. This is not build, attachment,
    /// focus, or descriptor authority, and never captures replacement tokens.
    var hasCurrentStandaloneNavigationIdentity: Bool {
        guard let node, let storage = node.retainedLazyListActivityStorage,
            storage.targetID === target, storage.attachmentID === attachment, identity.isCurrent
        else { return false }
        if runtime != nil { return proof.isCurrent }
        return proof.isCurrentForStandaloneNavigationAfterRuntimeRelease
    }

    private func matchesCurrentAttachment(on node: ViewNode) -> Bool {
        guard let storage = node.retainedLazyListActivityStorage else { return false }
        return storage.targetID === target && storage.attachmentID === attachment
            && proof.isCurrent && identity.isCurrent
    }
}

@MainActor
final class RetainedLazyListPhysicalLifetime {
    var phase: RetainedLazyListPhysicalActivityState = .provisional
}

private final class RetainedLazyListRowReplacementHandoffID: Sendable {}

@MainActor
private final class RetainedLazyListWeakContribution {
    weak var receipt: RetainedLazyListContributionReceipt?
    init(_ receipt: RetainedLazyListContributionReceipt) { self.receipt = receipt }
}

/// Retirement authority for an accepted physical attachment, including chrome
/// with no logical contribution. Neither endpoint owns a view or a runtime.
@MainActor
private struct RetainedLazyListPhysicalAttachmentRetirement {
    weak var physical: RetainedLazyListPhysicalActivityReceipt?
    let actual: RetainedLazyListActualAttachment
}

@MainActor
package final class RetainedLazyListPhysicalActivityReceipt {
    package let id = RetainedLazyListPhysicalActivityID()
    package let membership: RetainedLazyListMembershipID
    private let lifetime: RetainedLazyListPhysicalLifetime
    private var attachments: [RetainedLazyListActualAttachment] = []
    private var contributions: [RetainedLazyListWeakContribution] = []
    private var rowReplacementHandoffs: [ObjectIdentifier: RetainedLazyListRowReplacementHandoffID] = [:]
    var actualAttachments: [RetainedLazyListActualAttachment] { attachments }
    var acceptedContributions: [RetainedLazyListContributionReceipt] {
        contributions.compactMap(\.receipt).filter(\.hasAcceptedFootprint)
    }

    fileprivate func register(_ receipt: RetainedLazyListContributionReceipt) {
        contributions.removeAll { $0.receipt == nil }
        contributions.append(RetainedLazyListWeakContribution(receipt))
    }

    init(membership: RetainedLazyListMembershipID) {
        self.membership = membership
        lifetime = RetainedLazyListPhysicalLifetime()
    }

    init(membership: RetainedLazyListMembershipID, lifetime: RetainedLazyListPhysicalLifetime) {
        self.membership = membership
        self.lifetime = lifetime
    }

    package var state: RetainedLazyListPhysicalActivityState {
        if lifetime.phase == .active && rowReplacementHandoffs.isEmpty && !attachments.contains(where: \.isAttached) {
            return .revoked
        }
        return lifetime.phase
    }

    @discardableResult
    func activate(on actual: RetainedLazyListActualAttachment) -> Bool {
        guard state != .revoked, actual.isAttached else { return false }
        if !attachments.contains(where: { $0.target === actual.target && $0.attachment === actual.attachment }) {
            attachments.append(actual)
            actual.node?.retainedLazyListActivityStorage?.registerPhysicalAttachment(actual, physical: self)
        }
        lifetime.phase = .active
        return true
    }

    func removeAttachment(target: RetainedLazyListTargetID, attachment: RetainedLazyListAttachmentID) {
        for actual in attachments where actual.target === target && actual.attachment === attachment {
            actual.node?.retainedLazyListActivityStorage?.removePhysicalAttachment(actual, physical: self)
        }
        attachments.removeAll { $0.target === target && $0.attachment === attachment }
        if lifetime.phase == .active && rowReplacementHandoffs.isEmpty && !attachments.contains(where: \.isAttached) {
            revoke()
        }
    }

    fileprivate func retireAttachment(_ original: RetainedLazyListActualAttachment) {
        // An owed departure consumes its accepted witness even after identity
        // invalidation. It cannot consume a later activation of the same node.
        guard attachments.contains(where: { $0 === original }) else { return }
        removeAttachment(target: original.target, attachment: original.attachment)
    }

    fileprivate var canBeginRowReplacementHandoff: Bool {
        state == .active && rowReplacementHandoffs.isEmpty && attachments.contains(where: \.isAttached)
    }

    fileprivate func beginRowReplacementHandoff(_ id: RetainedLazyListRowReplacementHandoffID) -> Bool {
        guard canBeginRowReplacementHandoff else { return false }
        rowReplacementHandoffs[ObjectIdentifier(id)] = id
        return true
    }

    fileprivate func finishRowReplacementHandoff(_ id: RetainedLazyListRowReplacementHandoffID) {
        guard rowReplacementHandoffs.removeValue(forKey: ObjectIdentifier(id)) === id else { return }
        if lifetime.phase == .active && rowReplacementHandoffs.isEmpty && !attachments.contains(where: \.isAttached) {
            revoke()
        }
    }

    func revoke() {
        lifetime.phase = .revoked
        rowReplacementHandoffs.removeAll()
        for actual in attachments {
            actual.node?.retainedLazyListActivityStorage?.removePhysicalAttachment(actual, physical: self)
        }
    }
}

@MainActor
package final class RetainedLazyListContributionReceipt {
    package let id = RetainedLazyListContributionID()
    package let group: RetainedLazyListGroupID
    package let physical: RetainedLazyListPhysicalActivityReceipt
    private let logicalMembership: RetainedLazyListLogicalMembershipReceipt
    private var wasRevoked = false
    private var didAccept = false
    fileprivate var hasAcceptedFootprint: Bool { didAccept }
    fileprivate var acceptedNativeFacets: [RetainedLazyListAcceptedFacet] = []
    fileprivate var taskDeclarations: [RetainedTaskDeclarationID] = []
    private var attachments: [RetainedLazyListActualAttachment] = []
    fileprivate var actualAttachments: [RetainedLazyListActualAttachment] { attachments }
    fileprivate var permitsOriginalCompletion: Bool {
        didAccept && logicalMembership.isDeclared && physical.state == .active
    }

    init(
        group: RetainedLazyListGroupID, physical: RetainedLazyListPhysicalActivityReceipt,
        logicalMembership: RetainedLazyListLogicalMembershipReceipt
    ) {
        self.group = group
        self.physical = physical
        self.logicalMembership = logicalMembership
        physical.register(self)
    }

    package var isActive: Bool {
        !wasRevoked && didAccept && logicalMembership.isDeclared && physical.state == .active
            && !attachments.isEmpty && attachments.allSatisfy(\.isAttached)
    }

    @discardableResult
    func activate(on actual: [RetainedLazyListActualAttachment]) -> Bool {
        guard !wasRevoked, !actual.isEmpty, actual.allSatisfy(\.isAttached) else { return false }
        for attachment in actual {
            guard physical.activate(on: attachment) else { return false }
        }
        attachments = actual
        didAccept = true
        return true
    }

    func revoke() { wasRevoked = true }
}

@MainActor
enum RetainedLazyListNativeFacet {
    case nodeProperty(PartialKeyPath<ViewNode>)
    case childAttachment
    case nodeCompletion
    case scopedTaskDeclaration(RetainedTaskDeclarationID)
    case listDescriptor(RetainedLazyListLogicalDeclarationID)

    fileprivate var key: RetainedLazyListFacetKey {
        switch self {
        case .nodeProperty(let keyPath): .property(keyPath)
        case .childAttachment: .attachment
        case .nodeCompletion: .completion
        case .scopedTaskDeclaration(let id): .task(ObjectIdentifier(id))
        case .listDescriptor(let id): .descriptor(ObjectIdentifier(id))
        }
    }
}

private enum RetainedLazyListFacetKey: Hashable {
    case property(AnyKeyPath)
    case attachment, completion
    case task(ObjectIdentifier)
    case descriptor(ObjectIdentifier)
}

@MainActor
package struct RetainedLazyListSourceFacet {
    package let id: RetainedLazyListSourceFacetID
    package let source: RetainedLazyListSourcePayloadID
    package let component: RetainedLazyListComponentID
    package let group: RetainedLazyListGroupID
    let nativeField: RetainedLazyListNativeFacet

    init(
        source: RetainedLazyListSourcePayloadID, component: RetainedLazyListComponentID,
        group: RetainedLazyListGroupID, nativeField: RetainedLazyListNativeFacet
    ) {
        id = RetainedLazyListSourceFacetID()
        self.source = source
        self.component = component
        self.group = group
        self.nativeField = nativeField
    }
}

@MainActor
package struct RetainedLazyListGroupProposal {
    package let attempt: RetainedLazyListAttemptID
    package let membership: RetainedLazyListMembershipID
    package let physical: RetainedLazyListPhysicalActivityID
    package let component: RetainedLazyListComponentID
    package let group: RetainedLazyListGroupID
    package let kind: RetainedLazyListContributionKind
    package let construction: RetainedLazyListGroupConstruction
    package let requiredFacets: [RetainedLazyListSourceFacetID]
    package let declarations: [RetainedTaskDeclarationID]
}

@MainActor
package struct RetainedLazyListComponentProposal {
    package let component: RetainedLazyListComponentID
    package let parent: RetainedLazyListComponentID?
}

@MainActor
package struct RetainedLazyListAcceptedFacet {
    package let source: RetainedLazyListSourceFacet
    package let actual: RetainedLazyListActualAttachment
}

@MainActor
package struct RetainedLazyListAcceptedGroup {
    package let proposal: RetainedLazyListGroupProposal
    package let acceptedFacets: [RetainedLazyListAcceptedFacet]
    package let receipt: RetainedLazyListContributionReceipt
}

@MainActor
package struct RetainedLazyListPartialGroup {
    package let proposal: RetainedLazyListGroupProposal
    package let acceptedFacets: [RetainedLazyListAcceptedFacet]
    package let unacceptedFacets: [RetainedLazyListSourceFacetID]
}

@MainActor
package struct RetainedLazyListAcceptedEmptyGroup {
    package let proposal: RetainedLazyListGroupProposal
    package let structuralAnchor: RetainedLazyListActualAttachment
    package let receipt: RetainedLazyListContributionReceipt
}

@MainActor
package struct RetainedLazyListUnchangedContribution {
    package let receipt: RetainedLazyListContributionReceipt
    package let actualAttachments: [RetainedLazyListActualAttachment]
}

@MainActor
package struct RetainedLazyListAcceptedAbsence {
    package let previous: RetainedLazyListContributionReceipt
    package let actual: RetainedLazyListActualAttachment
    package let removalFacets: [RetainedLazyListAcceptedFacet]
    package let cleanup: RetainedLazyListCleanupID
}

package enum RetainedLazyListDepartureCause: Equatable, Sendable {
    case viewportEviction, acceptedReplacement, logicalDeletion, hostClose
}

@MainActor
package struct RetainedLazyListAcceptedDeparture {
    package let physical: RetainedLazyListPhysicalActivityReceipt
    package let formerAttachments: [RetainedLazyListActualAttachment]
    package let contributions: [RetainedLazyListContributionReceipt]
    package let cause: RetainedLazyListDepartureCause
    package let cleanup: RetainedLazyListCleanupID
}

@MainActor
package struct RetainedLazyListAcceptedLogicalDeclaration {
    package let declaration: RetainedLazyListLogicalDeclarationID
    package let installedList: RetainedLazyListActualAttachment
    package let membershipPlan: RetainedLazyListLogicalMembershipPlan
}

@MainActor
package struct RetainedLazyListAcceptedLogicalScopeRemoval {
    package let previous: RetainedLazyListLogicalDeclarationID
    package let scope: RetainedLazyListLogicalMembershipScope
    package let formerList: RetainedLazyListActualAttachment
    package let cleanup: RetainedLazyListCleanupID
}

@MainActor
struct RetainedLazyListAcceptedTaskMember {
    let sourcePayload: RetainedLazyListSourcePayloadID
    let requiredFacets: [RetainedLazyListSourceFacetID]
    let actual: RetainedLazyListActualAttachment
}

@MainActor
struct RetainedLazyListAcceptedTaskGroup {
    let contribution: RetainedLazyListAcceptedGroup
    let declarationIDs: [RetainedTaskDeclarationID]
    let members: [RetainedLazyListAcceptedTaskMember]
}

/// Short-lived pins for the caller that associates an already accepted group.
/// These are never stored in a contribution receipt or sealed disposition.
@MainActor
struct RetainedLazyListAcceptedTaskSource {
    let member: RetainedLazyListAcceptedTaskMember
    let source: ViewNode
}

@MainActor
struct RetainedLazyListDeferredSubtreeAnchor {
    let contribution: RetainedLazyListContributionReceipt
    let actual: RetainedLazyListActualAttachment
    let request: RetainedLazyListRowRequest
    let logicalMembership: RetainedLazyListLogicalMembershipReceipt
    fileprivate let ownedRegion: RetainedOwnedStructuralRegion?

    init(
        contribution: RetainedLazyListContributionReceipt, actual: RetainedLazyListActualAttachment,
        request: RetainedLazyListRowRequest, logicalMembership: RetainedLazyListLogicalMembershipReceipt
    ) {
        self.init(
            contribution: contribution, actual: actual, request: request,
            logicalMembership: logicalMembership, ownedRegion: nil)
    }

    fileprivate init(
        contribution: RetainedLazyListContributionReceipt, actual: RetainedLazyListActualAttachment,
        request: RetainedLazyListRowRequest, logicalMembership: RetainedLazyListLogicalMembershipReceipt,
        ownedRegion: RetainedOwnedStructuralRegion?
    ) {
        self.contribution = contribution
        self.actual = actual
        self.request = request
        self.logicalMembership = logicalMembership
        self.ownedRegion = ownedRegion
    }

    var isCurrent: Bool {
        contribution.isActive && actual.isAttached && logicalMembership.isDeclared
    }
}

@MainActor
struct RetainedDescriptorDeferredSubtreeAnchor {
    let contribution: RetainedDescriptorContributionReceipt
    let actual: RetainedLazyListActualAttachment
    var isCurrent: Bool { contribution.isActive && actual.isAttached }
}

@MainActor
private struct RetainedOwnedEmptyRowMarker {
    let actual: RetainedLazyListActualAttachment
    let membership: RetainedLazyListMembershipID
    let revision: UInt64
    let permissions: [ObjectIdentifier: [RetainedOwnedSlotPermission]]
    let components: [ObjectIdentifier: RetainedOwnedComponentPresence]
    let namespaces: [ObjectIdentifier: RetainedOwnedMarkerNamespaces]
}

@MainActor
private struct RetainedOwnedEmptyRowRevision {
    let membership: RetainedLazyListMembershipID
    var value: UInt64
}

/// A one-use native snapshot of an old empty row's footprint. Successor state
/// is declared separately; this transport can retire only the captured effects
/// and markers without revoking the shared row's physical activity.
@MainActor
final class RetainedLazyListEmptyRowContinuation {
    fileprivate weak var journal: RetainedLazyListAdoptionJournal?
    fileprivate let previous: RetainedLazyListMaterializedRowActivity
    fileprivate let successor: RetainedLazyListMaterializedRowActivity
    fileprivate let contributions: [RetainedLazyListContributionReceipt]
    fileprivate let anchors: [RetainedLazyListActualAttachment]
    fileprivate let markers: [RetainedOwnedEmptyRowMarker]
    fileprivate var wasConsumed = false

    fileprivate init(
        journal: RetainedLazyListAdoptionJournal, previous: RetainedLazyListMaterializedRowActivity,
        successor: RetainedLazyListMaterializedRowActivity,
        contributions: [RetainedLazyListContributionReceipt], anchors: [RetainedLazyListActualAttachment],
        markers: [RetainedOwnedEmptyRowMarker]
    ) {
        self.journal = journal
        self.previous = previous
        self.successor = successor
        self.contributions = contributions
        self.anchors = anchors
        self.markers = markers
    }
}

@MainActor
private final class RetainedLazyListRowReplacementHandoff {
    let id = RetainedLazyListRowReplacementHandoffID()
    let previous: RetainedLazyListMaterializedRowActivity
    let successor: RetainedLazyListMaterializedRowActivity
    let attachments: [RetainedLazyListActualAttachment]
    var isActive = false
    var wasFinished = false

    init(previous: RetainedLazyListMaterializedRowActivity, successor: RetainedLazyListMaterializedRowActivity) {
        self.previous = previous
        self.successor = successor
        attachments = previous.physical.actualAttachments
    }

    func finish() {
        guard !wasFinished else { return }
        wasFinished = true
        if isActive { successor.physical.finishRowReplacementHandoff(id) }
        isActive = false
    }
}

package enum RetainedLazyListAdoptionStop: Equatable, Sendable {
    case noAcceptance, stoppedAfterAcceptance, completedCheckedAdoption
}

@MainActor
package final class RetainedLazyListAdoptionPreparation {
    package let attempt: RetainedLazyListAttemptID
    package let groups: [RetainedLazyListGroupProposal]
    package let components: [RetainedLazyListComponentProposal]
    package let expectedExisting: [RetainedLazyListUnchangedContribution]
    package let logicalSnapshots: [RetainedLazyListLogicalMembershipSnapshot]
    package let logicalDescriptors: [RetainedLazyListManagedLogicalDescriptorBinding]
    package let ordinaryComponents: [RetainedDescriptorComponentProposal]
    package let expectedOrdinaryContributions: [RetainedDescriptorExistingContribution]
    package let ownedComponentDeclarations: [RetainedOwnedComponentDeclarationPlan]

    init(
        attempt: RetainedLazyListAttemptID, groups: [RetainedLazyListGroupProposal],
        components: [RetainedLazyListComponentProposal],
        expectedExisting: [RetainedLazyListUnchangedContribution],
        logicalSnapshots: [RetainedLazyListLogicalMembershipSnapshot],
        logicalDescriptors: [RetainedLazyListManagedLogicalDescriptorBinding],
        ordinaryComponents: [RetainedDescriptorComponentProposal],
        expectedOrdinaryContributions: [RetainedDescriptorExistingContribution],
        ownedComponentDeclarations: [RetainedOwnedComponentDeclarationPlan]
    ) {
        self.attempt = attempt
        self.groups = groups
        self.components = components
        self.expectedExisting = expectedExisting
        self.logicalSnapshots = logicalSnapshots
        self.logicalDescriptors = logicalDescriptors
        self.ordinaryComponents = ordinaryComponents
        self.expectedOrdinaryContributions = expectedOrdinaryContributions
        self.ownedComponentDeclarations = ownedComponentDeclarations
    }
}

@MainActor
package final class RetainedLazyListPreparedActivity {
    package let preparation: RetainedLazyListAdoptionPreparation
    package let logicalMembershipPlans: [RetainedLazyListLogicalMembershipPlan]
    package let ownedComponentPlans: [RetainedOwnedComponentDeclarationPlan]

    package init(
        preparation: RetainedLazyListAdoptionPreparation,
        logicalMembershipPlans: [RetainedLazyListLogicalMembershipPlan],
        ownedComponentPlans: [RetainedOwnedComponentDeclarationPlan] = []
    ) {
        self.preparation = preparation
        self.logicalMembershipPlans = logicalMembershipPlans
        self.ownedComponentPlans = ownedComponentPlans
    }
}

@MainActor
package final class RetainedLazyListAdoptionDisposition {
    package let attempt: RetainedLazyListAttemptID
    package let stop: RetainedLazyListAdoptionStop
    /// Logical row retention follows an accepted native table even when its
    /// factory declares no owned component, effect group, or physical leaf.
    package let acceptedRowMemberships: [RetainedLazyListMembershipID]
    package let acceptedLogicalDeclarations: [RetainedLazyListAcceptedLogicalDeclaration]
    package let acceptedLogicalRemovals: [RetainedLazyListAcceptedLogicalScopeRemoval]
    package let acceptedFacets: [RetainedLazyListAcceptedFacet]
    package let acceptedGroups: [RetainedLazyListAcceptedGroup]
    package let partialGroups: [RetainedLazyListPartialGroup]
    package let acceptedEmptyGroups: [RetainedLazyListAcceptedEmptyGroup]
    package let unchanged: [RetainedLazyListUnchangedContribution]
    package let acceptedAbsences: [RetainedLazyListAcceptedAbsence]
    package let acceptedDepartures: [RetainedLazyListAcceptedDeparture]
    package let unadoptedGroups: [RetainedLazyListGroupID]
    package let acceptedCleanup: [RetainedLazyListCleanupID]
    package let acceptedOrdinaryFacets: [RetainedDescriptorAcceptedFacet]
    package let acceptedOrdinaryGroups: [RetainedDescriptorAcceptedGroup]
    package let partialOrdinaryGroups: [RetainedDescriptorPartialGroup]
    package let acceptedEmptyOrdinaryGroups: [RetainedDescriptorAcceptedEmptyGroup]
    package let unchangedOrdinary: [RetainedDescriptorExistingContribution]
    package let absentOrdinary: [RetainedDescriptorAcceptedAbsence]
    package let acceptedOwnedComponents: [RetainedOwnedComponentDeclarationFact]
    package let retiredOwnedSlots: [RetainedOwnedSlotGenerationID]
    package let retiredOwnedComponents: [RetainedOwnedComponentID]

    fileprivate init(
        attempt: RetainedLazyListAttemptID, stop: RetainedLazyListAdoptionStop,
        acceptedRowMemberships: [RetainedLazyListMembershipID],
        acceptedLogicalDeclarations: [RetainedLazyListAcceptedLogicalDeclaration],
        acceptedLogicalRemovals: [RetainedLazyListAcceptedLogicalScopeRemoval],
        acceptedFacets: [RetainedLazyListAcceptedFacet], acceptedGroups: [RetainedLazyListAcceptedGroup],
        partialGroups: [RetainedLazyListPartialGroup], acceptedEmptyGroups: [RetainedLazyListAcceptedEmptyGroup],
        unchanged: [RetainedLazyListUnchangedContribution], acceptedAbsences: [RetainedLazyListAcceptedAbsence],
        acceptedDepartures: [RetainedLazyListAcceptedDeparture], unadoptedGroups: [RetainedLazyListGroupID],
        acceptedCleanup: [RetainedLazyListCleanupID],
        ordinary: RetainedDescriptorSealedActivity?,
        owned: RetainedOwnedComponentConstructionLedger?
    ) {
        self.attempt = attempt
        self.stop = stop
        self.acceptedRowMemberships = acceptedRowMemberships
        self.acceptedLogicalDeclarations = acceptedLogicalDeclarations
        self.acceptedLogicalRemovals = acceptedLogicalRemovals
        self.acceptedFacets = acceptedFacets
        self.acceptedGroups = acceptedGroups
        self.partialGroups = partialGroups
        self.acceptedEmptyGroups = acceptedEmptyGroups
        self.unchanged = unchanged
        self.acceptedAbsences = acceptedAbsences
        self.acceptedDepartures = acceptedDepartures
        self.unadoptedGroups = unadoptedGroups
        self.acceptedCleanup = acceptedCleanup
        acceptedOrdinaryFacets = ordinary?.acceptedFacets ?? []
        acceptedOrdinaryGroups = ordinary?.acceptedGroups ?? []
        partialOrdinaryGroups = ordinary?.partialGroups ?? []
        acceptedEmptyOrdinaryGroups = ordinary?.acceptedEmptyGroups ?? []
        unchangedOrdinary = ordinary?.unchanged ?? []
        absentOrdinary = ordinary?.absences ?? []
        acceptedOwnedComponents = owned?.acceptedDeclarations ?? []
        retiredOwnedSlots = owned?.retiredSlots ?? []
        retiredOwnedComponents = owned?.retiredComponents ?? []
    }

    package func contribution(for group: RetainedLazyListGroupID) -> RetainedLazyListContributionReceipt? {
        acceptedGroups.first { $0.proposal.group === group }?.receipt
            ?? acceptedEmptyGroups.first { $0.proposal.group === group }?.receipt
            ?? unchanged.first { $0.receipt.group === group }?.receipt
    }

    package func contribution(for group: RetainedDescriptorGroupID) -> RetainedDescriptorContributionReceipt? {
        acceptedOrdinaryGroups.first { $0.proposal.group === group }?.receipt
            ?? acceptedEmptyOrdinaryGroups.first { $0.proposal.group === group }?.receipt
            ?? unchangedOrdinary.first { $0.receipt.group === group }?.receipt
    }
}

@MainActor
package enum RetainedLazyListBuildAttributionOrigin {
    case selectedRow
    case deferredSubtree(originalContribution: RetainedLazyListContributionReceipt)
}

@MainActor
package final class RetainedLazyListBuildAttribution {
    package let attempt: RetainedLazyListAttemptID
    package let descriptorBuildAttempt: RetainedLazyListAttemptID?
    package var descriptorBuildAttemptID: RetainedLazyListAttemptID? { descriptorBuildAttempt }
    package let membership: RetainedLazyListMembershipID
    package let logicalMembership: RetainedLazyListLogicalMembershipReceipt
    package let physical: RetainedLazyListPhysicalActivityReceipt
    package let rowRequest: RetainedLazyListRowRequest
    package let component: RetainedLazyListComponentID
    package let resolutionID: RetainedLazyListRowResolutionID
    package let origin: RetainedLazyListBuildAttributionOrigin
    fileprivate weak var journal: RetainedLazyListAdoptionJournal?

    init(
        journal: RetainedLazyListAdoptionJournal, rowRequest: RetainedLazyListRowRequest,
        logicalMembership: RetainedLazyListLogicalMembershipReceipt,
        physical: RetainedLazyListPhysicalActivityReceipt,
        component: RetainedLazyListComponentID, resolutionID: RetainedLazyListRowResolutionID,
        origin: RetainedLazyListBuildAttributionOrigin
    ) {
        self.journal = journal
        attempt = journal.attempt
        descriptorBuildAttempt = journal.descriptorBuildAttempt
        membership = logicalMembership.id
        self.logicalMembership = logicalMembership
        self.physical = physical
        self.rowRequest = rowRequest
        self.component = component
        self.resolutionID = resolutionID
        self.origin = origin
    }

    package var constructionState: RetainedLazyListConstructionState {
        guard journal?.canConstructComponent(component) == true, physical.state != .revoked,
            logicalMembership.permitsConstruction
        else { return .rejected }
        switch origin {
        case .selectedRow:
            return rowRequest.isGenerationCurrent ? .admittedForConstruction : .rejected
        case .deferredSubtree(let original):
            return original.isActive ? .admittedForConstruction : .rejected
        }
    }

    var canConstructNestedDescriptor: Bool { constructionState == .admittedForConstruction }
    var canPublishNestedDescriptor: Bool {
        journal?.canContinueAdoption == true && physical.state != .revoked && logicalMembership.permitsConstruction
    }

    package func registerChildComponent() -> RetainedLazyListBuildAttribution? {
        journal?.registerChildComponent(from: self)
    }

    package func rejectConstruction() { journal?.rejectComponent(self) }
    package func rejectComponent() { rejectConstruction() }

    package func registerGroup(kind: RetainedLazyListContributionKind) -> RetainedLazyListGroupID? {
        journal?.registerGroup(attribution: self, kind: kind)
    }

    package func recordSourceOutput(_ source: ViewNode, group: RetainedLazyListGroupID)
        -> RetainedLazyListSourcePayloadID?
    {
        journal?.recordSourceOutput(source, attribution: self, group: group)
    }

    package func closeGroup(_ group: RetainedLazyListGroupID) -> RetainedLazyListGroupProposal? {
        journal?.closeGroup(group, attribution: self)
    }

    package func registerTaskDeclaration(_ id: RetainedTaskDeclarationID, group: RetainedLazyListGroupID) -> Bool {
        journal?.registerTaskDeclaration(id, group: group, attribution: self) == true
    }
}

@MainActor
package final class RetainedLazyListSelectedRowPreparation {
    package let resolutionID = RetainedLazyListRowResolutionID()
    package let descriptor: RetainedLazyListManagedLogicalDescriptorBinding
    package let request: RetainedLazyListRowRequest
    package let descriptorBuildAttempt: RetainedLazyListAttemptID?
    package var descriptorBuildAttemptID: RetainedLazyListAttemptID? { descriptorBuildAttempt }
    package let attempt: RetainedLazyListAttemptID
    fileprivate weak var admission: RetainedLazyListAdoptionAdmission?
    fileprivate var wasConsumed = false
    private var wasRevoked = false

    init(
        attempt: RetainedLazyListAttemptID, descriptor: RetainedLazyListManagedLogicalDescriptorBinding,
        request: RetainedLazyListRowRequest, admission: RetainedLazyListAdoptionAdmission,
        descriptorBuildAttempt: RetainedLazyListAttemptID?
    ) {
        self.attempt = attempt
        self.descriptor = descriptor
        self.request = request
        self.admission = admission
        self.descriptorBuildAttempt = descriptorBuildAttempt
    }

    package var isCurrent: Bool {
        !wasRevoked && admission?.isBuildCurrent == true
            && descriptor.isCurrent && request.isGenerationCurrent
    }

    package func admits(_ attribution: RetainedLazyListBuildAttribution) -> Bool {
        wasConsumed && isCurrent && attribution.resolutionID === resolutionID
            && attribution.descriptorBuildAttempt === descriptorBuildAttempt
            && attribution.attempt === attempt && attribution.rowRequest == request
            && attribution.constructionState == .admittedForConstruction
    }

    func revoke() { wasRevoked = true }
}

package enum RetainedLazyListSelectedRowSource {
    case proposed(descriptor: RetainedLazyListLogicalDeclarationID, facadeProposal: RetainedLazyListLogicalProposalID)
    case committed(descriptor: RetainedLazyListLogicalDeclarationID)
}

@MainActor
package final class RetainedLazyListSelectedRowResolution {
    package let resolutionID: RetainedLazyListRowResolutionID
    package let descriptor: RetainedLazyListManagedLogicalDescriptorBinding
    package let membership: RetainedLazyListMembershipID
    package let source: RetainedLazyListSelectedRowSource

    package init(
        preparation: RetainedLazyListSelectedRowPreparation,
        membership: RetainedLazyListMembershipID, source: RetainedLazyListSelectedRowSource
    ) {
        resolutionID = preparation.resolutionID
        descriptor = preparation.descriptor
        self.membership = membership
        self.source = source
    }
}

@MainActor
private final class RetainedLazyListSourceOutput {
    weak var node: ViewNode?
    let payload = RetainedLazyListSourcePayloadID()
    let component: RetainedLazyListComponentID
    let group: RetainedLazyListGroupID
    let constructionComponent: RetainedLazyListComponentID
    var facets: [RetainedLazyListFacetKey: RetainedLazyListSourceFacet] = [:]
    var retirementProperties: Set<RetainedLazyListFacetKey> = []

    init(
        node: ViewNode, component: RetainedLazyListComponentID, group: RetainedLazyListGroupID,
        constructionComponent: RetainedLazyListComponentID
    ) {
        self.node = node
        self.component = component
        self.group = group
        self.constructionComponent = constructionComponent
    }

    func facet(_ field: RetainedLazyListNativeFacet) -> RetainedLazyListSourceFacet {
        if let existing = facets[field.key] { return existing }
        let result = RetainedLazyListSourceFacet(
            source: payload, component: component, group: group, nativeField: field)
        facets[field.key] = result
        return result
    }
}

@MainActor
private final class RetainedLazyListGroupRecord {
    let attribution: RetainedLazyListBuildAttribution
    let id = RetainedLazyListGroupID()
    let kind: RetainedLazyListContributionKind
    let receipt: RetainedLazyListContributionReceipt
    var outputs: [RetainedLazyListSourceOutput] = []
    var required: [RetainedLazyListSourceFacet] = []
    var declarations: [RetainedTaskDeclarationID] = []
    var isClosed = false

    init(attribution: RetainedLazyListBuildAttribution, kind: RetainedLazyListContributionKind) {
        self.attribution = attribution
        self.kind = kind
        receipt = RetainedLazyListContributionReceipt(
            group: id, physical: attribution.physical, logicalMembership: attribution.logicalMembership)
    }

    var proposal: RetainedLazyListGroupProposal {
        RetainedLazyListGroupProposal(
            attempt: attribution.attempt, membership: attribution.membership, physical: attribution.physical.id,
            component: attribution.component, group: id, kind: kind,
            construction: isClosed ? (outputs.isEmpty ? .closedEmpty : .closedWithFacets) : .open,
            requiredFacets: required.map(\.id), declarations: declarations)
    }

    func require(_ facet: RetainedLazyListSourceFacet) {
        if !required.contains(where: { $0.id === facet.id }) { required.append(facet) }
    }
}

private struct RetainedLazyListPropertyCopyKey: Hashable {
    let source: ObjectIdentifier
    let target: ObjectIdentifier
    let field: AnyKeyPath
}

@MainActor
private struct RetainedLazyListPendingPropertyCopy {
    weak var source: ViewNode?
    weak var target: ViewNode?
    let targetID: RetainedLazyListTargetID
    let attachmentID: RetainedLazyListAttachmentID
    let previous: [RetainedLazyListContributionReceipt]
}

@MainActor
struct RetainedLazyListDescriptorSourceFacet {
    weak var sourceNode: ViewNode?
    let descriptor: RetainedLazyListManagedLogicalDescriptorBinding
    let source: RetainedLazyListSourcePayloadID
    let facet: RetainedLazyListSourceFacetID
    let component: RetainedLazyListComponentID
    let group: RetainedLazyListGroupID
    let scope: RetainedLazyListDescriptorBuildScope
}

@MainActor
enum RetainedLazyListLogicalDescriptorSource {
    case descriptorBuild(RetainedLazyListDescriptorSourceFacet)
    case selectedRow(RetainedLazyListSourceFacet)
}

@MainActor
final class RetainedLazyListLogicalDescriptorPublication {
    let attempt: RetainedLazyListAttemptID
    let plan: RetainedLazyListLogicalMembershipPlan
    let source: RetainedLazyListLogicalDescriptorSource
    let actual: RetainedLazyListActualAttachment
    fileprivate var publishedFact: RetainedLazyListAcceptedLogicalDeclaration?

    init(
        attempt: RetainedLazyListAttemptID, plan: RetainedLazyListLogicalMembershipPlan,
        source: RetainedLazyListLogicalDescriptorSource,
        actual: RetainedLazyListActualAttachment
    ) {
        self.attempt = attempt
        self.plan = plan
        self.source = source
        self.actual = actual
    }
}

@MainActor
final class RetainedLazyListLogicalScopeRemovalPublication {
    let attempt: RetainedLazyListAttemptID
    let expected: RetainedLazyListLogicalMembershipSnapshot
    let actual: RetainedLazyListActualAttachment
    let expectedDescriptor: RetainedLazyListLogicalDeclarationID
    fileprivate var wasPublished = false

    init(
        attempt: RetainedLazyListAttemptID, expected: RetainedLazyListLogicalMembershipSnapshot,
        actual: RetainedLazyListActualAttachment,
        expectedDescriptor: RetainedLazyListLogicalDeclarationID
    ) {
        self.attempt = attempt
        self.expected = expected
        self.actual = actual
        self.expectedDescriptor = expectedDescriptor
    }
}

@MainActor
enum RetainedLazyListDescriptorCopyPreparation {
    case unmanaged
    case unchanged
    case ready(RetainedLazyListLogicalDescriptorPublication)
    case removal(RetainedLazyListLogicalScopeRemovalPublication)
    case rejected
}

/// Sparse native metadata only. Source stamps never retain source nodes or
/// executable declarations. Committed payloads remain owned by existing nodes.
@MainActor
final class RetainedLazyListNodeActivityStorage {
    let targetID = RetainedLazyListTargetID()
    private(set) var attachmentID: RetainedLazyListAttachmentID
    private(set) var descriptorOwnerLifetime: RetainedLazyListDescriptorOwnerLifetime
    fileprivate var sourceOutputs: [RetainedLazyListSourceOutput] = []
    fileprivate var sourceDescriptor: RetainedLazyListDescriptorSourceFacet?
    fileprivate var descriptorOutputs: [RetainedDescriptorSourceOutput] = []
    var committedDescriptorContributions: [ObjectIdentifier: RetainedDescriptorContributionReceipt] = [:]
    fileprivate var wasRejectedSource = false
    fileprivate var ownedPayloadPermissions: [AnyKeyPath: [RetainedOwnedSlotPermission]] = [:]
    fileprivate var ownedStructuralPermissions: [RetainedOwnedSlotPermission] = []
    fileprivate var ownedEmptyStructuralPermissions: [ObjectIdentifier: [RetainedOwnedSlotPermission]] = [:]
    fileprivate var ownedEmptyStructuralNamespaces: [ObjectIdentifier: RetainedOwnedMarkerNamespaces] = [:]
    fileprivate var ownedDeclaredStructuralPermissions: [ObjectIdentifier: [RetainedOwnedSlotPermission]] = [:]
    fileprivate var ownedDeclaredStructuralNamespaces: [ObjectIdentifier: RetainedOwnedMarkerNamespaces] = [:]
    fileprivate var ownedPayloadComponents: [AnyKeyPath: [RetainedOwnedComponentPresence]] = [:]
    fileprivate var ownedStructuralComponents: [RetainedOwnedComponentPresence] = []
    fileprivate var ownedEmptyStructuralComponents: [ObjectIdentifier: RetainedOwnedComponentPresence] = [:]
    fileprivate var ownedEmptyRowRevisions: [ObjectIdentifier: RetainedOwnedEmptyRowRevision] = [:]
    fileprivate var ownedDeclaredStructuralComponents: [ObjectIdentifier: RetainedOwnedComponentPresence] = [:]
    fileprivate var ownedDeclaredStructuralRevision: UInt64 = 0
    fileprivate var ownedRegionStructuralPermissions: [ObjectIdentifier: [RetainedOwnedSlotPermission]] = [:]
    fileprivate var ownedRegionStructuralComponents: [ObjectIdentifier: [RetainedOwnedComponentPresence]] = [:]
    fileprivate var ownedDeferredRegions: [ObjectIdentifier: RetainedOwnedStructuralRegion] = [:]
    fileprivate var ownedScopeDeclaredSlots: [ObjectIdentifier: RetainedOwnedWeakSlotPermission] = [:]
    fileprivate var ownedScopeDeclaredComponents: [ObjectIdentifier: RetainedOwnedWeakComponentPresence] = [:]
    var acceptedLogicalDeclaration: RetainedLazyListAcceptedLogicalDeclaration?
    var committedContributions: [ObjectIdentifier: RetainedLazyListContributionReceipt] = [:]
    private var physicalAttachmentRetirements: [RetainedLazyListPhysicalAttachmentRetirement] = []
    var deferredSubtreeAnchor: RetainedLazyListDeferredSubtreeAnchor?
    var descriptorDeferredSubtreeAnchor: RetainedDescriptorDeferredSubtreeAnchor?

    init() {
        let attachment = RetainedLazyListAttachmentID()
        attachmentID = attachment
        descriptorOwnerLifetime = RetainedLazyListDescriptorOwnerLifetime(target: targetID, attachment: attachment)
    }

    func captureActualAttachment(of node: ViewNode, in runtime: RetainedViewRuntime) -> RetainedLazyListActualAttachment
    {
        RetainedLazyListActualAttachment(
            node: node, runtime: runtime, target: targetID, attachment: attachmentID)
    }

    fileprivate func registerPhysicalAttachment(
        _ actual: RetainedLazyListActualAttachment, physical: RetainedLazyListPhysicalActivityReceipt
    ) {
        physicalAttachmentRetirements.removeAll { $0.physical == nil }
        physicalAttachmentRetirements.append(
            RetainedLazyListPhysicalAttachmentRetirement(physical: physical, actual: actual))
    }

    fileprivate func removePhysicalAttachment(
        _ original: RetainedLazyListActualAttachment, physical: RetainedLazyListPhysicalActivityReceipt
    ) {
        physicalAttachmentRetirements.removeAll { $0.physical === physical && $0.actual === original }
    }

    private func retirePhysicalAttachments(_ originalAttachment: RetainedLazyListAttachmentID) {
        let departures = physicalAttachmentRetirements.filter {
            $0.actual.target === targetID && $0.actual.attachment === originalAttachment
        }
        // Consume the native associations before changing a receipt or rotating
        // the attachment. The original proof need not still be current here.
        physicalAttachmentRetirements.removeAll {
            $0.actual.target === targetID && $0.actual.attachment === originalAttachment
        }
        for departure in departures {
            departure.physical?.retireAttachment(departure.actual)
        }
    }

    func revokeAttachment() {
        let previousAttachment = attachmentID
        descriptorOwnerLifetime.revoke()
        for receipt in committedContributions.values {
            receipt.revoke()
            receipt.physical.removeAttachment(target: targetID, attachment: previousAttachment)
        }
        for receipt in committedDescriptorContributions.values { receipt.revoke() }
        committedDescriptorContributions.removeAll()
        retirePhysicalAttachments(previousAttachment)
        let replacement = RetainedLazyListAttachmentID()
        attachmentID = replacement
        descriptorOwnerLifetime = RetainedLazyListDescriptorOwnerLifetime(target: targetID, attachment: replacement)
        deferredSubtreeAnchor = nil
        descriptorDeferredSubtreeAnchor = nil
        // Native receipts only: logical membership survives physical eviction.
        committedContributions.removeAll()
    }
}

extension ViewNode {
    func lazyListActivityStorage() -> RetainedLazyListNodeActivityStorage {
        if let retainedLazyListActivityStorage { return retainedLazyListActivityStorage }
        let storage = RetainedLazyListNodeActivityStorage()
        retainedLazyListActivityStorage = storage
        return storage
    }

    package func markRejectedRetainedSource() { lazyListActivityStorage().wasRejectedSource = true }

    package var containsRejectedRetainedSource: Bool { Self.containsRejectedRetainedSource(in: [self]) }

    package static func containsRejectedRetainedSource(in nodes: [ViewNode]) -> Bool {
        var pending: [(ViewNode, Int)] = nodes.map { ($0, 0) }
        var seen: Set<ObjectIdentifier> = []
        while let (node, depth) = pending.popLast() {
            guard depth < maximumTraversalDepth, seen.insert(ObjectIdentifier(node)).inserted else { return true }
            if node.retainedLazyListActivityStorage?.wasRejectedSource == true { return true }
            pending.append(contentsOf: node.children.map { ($0, depth + 1) })
        }
        return false
    }
}

@MainActor
private enum RetainedLazyListJournalOrigin {
    case descriptorBuild(RetainedLazyListDescriptorBuildScope)
    case selectedRows(RetainedLazyListAdoptionAdmission)
}

@MainActor
private struct RetainedLazyListPendingInsertedDescriptor {
    weak var node: ViewNode?
    let target: RetainedLazyListTargetID
    let attachment: RetainedLazyListAttachmentID
    let source: RetainedLazyListDescriptorSourceFacet
    let plan: RetainedLazyListLogicalMembershipPlan
}

@MainActor
private struct RetainedLazyListPendingInsertedNode {
    weak var node: ViewNode?
    let target: RetainedLazyListTargetID
    let attachment: RetainedLazyListAttachmentID
    let nativeFacets: [RetainedLazyListSourceFacet]
}

/// Cleanup for one original ordinary departure. It owns native metadata only;
/// the snapshot's storage and every actual attachment keep their weak links.
@MainActor
struct RetainedOrdinaryOwnedDeparture {
    fileprivate let attempt: RetainedLazyListAttemptID
    fileprivate let node: ObjectIdentifier
    fileprivate let snapshot: RetainedOwnedPhysicalDepartureSnapshot
}

/// Native accepted-write ledger. Its sealed disposition has no source node,
/// callback, factory, facade owner or executable task payload.
@MainActor
final class RetainedLazyListAdoptionJournal {
    let attempt: RetainedLazyListAttemptID
    let uiaContinuationAuthority: RetainedLazyListUIAContinuationAuthority?
    private let origin: RetainedLazyListJournalOrigin
    private let transaction: RetainedBuildTransaction
    private var boundDescriptorScope: RetainedLazyListDescriptorBuildScope?
    private let taskCleanup = RetainedLazyListAcceptedTaskCleanupLedger()
    private enum Phase { case constructing, prepared, adopting, sealed, finished }
    private var phase: Phase = .constructing
    private var wasRevoked = false
    private var didMutate = false
    private var acceptedRowTables: [ObjectIdentifier: RetainedLazyListMembershipID] = [:]
    private(set) var isOrdinaryAdoption = false
    private var beganRegionlessOrdinaryOwnedAdoption = false
    private var preparedInput: RetainedLazyListAdoptionPreparation?
    private var preparedActivity: RetainedLazyListPreparedActivity?
    private var groups: [ObjectIdentifier: RetainedLazyListGroupRecord] = [:]
    private var groupOrder: [RetainedLazyListGroupID] = []
    private var componentParents: [ObjectIdentifier: RetainedLazyListComponentID] = [:]
    private var componentOrder: [RetainedLazyListComponentID] = []
    private var materializedRoots: [RetainedLazyListBuildAttribution] = []
    private var rowReplacementHandoffs: [ObjectIdentifier: RetainedLazyListRowReplacementHandoff] = [:]
    private var pendingOwnedDepartures: [ObjectIdentifier: [RetainedOwnedPhysicalDepartureSnapshot]] = [:]
    private var preparations: [ObjectIdentifier: RetainedLazyListSelectedRowPreparation] = [:]
    private var physicalByMembership: [ObjectIdentifier: RetainedLazyListPhysicalActivityReceipt] = [:]
    private var descriptorSources: [ObjectIdentifier: RetainedLazyListDescriptorSourceFacet] = [:]
    private var existingLogicalDeclarations: [ObjectIdentifier: RetainedLazyListAcceptedLogicalDeclaration] = [:]
    private var insertedDescriptors: [ObjectIdentifier: RetainedLazyListPendingInsertedDescriptor] = [:]
    private var insertedNodes: [ObjectIdentifier: RetainedLazyListPendingInsertedNode] = [:]
    private var propertyCopies: [RetainedLazyListPropertyCopyKey: RetainedLazyListPendingPropertyCopy] = [:]
    private var acceptedFacetByID: [ObjectIdentifier: RetainedLazyListAcceptedFacet] = [:]
    private var acceptedFacetFacts: [RetainedLazyListAcceptedFacet] = []
    private var completedGroups: [RetainedLazyListAcceptedGroup] = []
    private var completedGroupIDs: Set<ObjectIdentifier> = []
    private var invalidGroups: Set<ObjectIdentifier> = []
    private var rejectedComponents: Set<ObjectIdentifier> = []
    private var emptyGroups: [RetainedLazyListAcceptedEmptyGroup] = []
    private var unchanged: [RetainedLazyListUnchangedContribution] = []
    private var logicalDeclarations: [RetainedLazyListAcceptedLogicalDeclaration] = []
    private var logicalRemovals: [RetainedLazyListAcceptedLogicalScopeRemoval] = []
    private var absences: [RetainedLazyListAcceptedAbsence] = []
    private var departures: [RetainedLazyListAcceptedDeparture] = []
    private var cleanupIDs: [RetainedLazyListCleanupID] = []
    private var sealedDisposition: RetainedLazyListAdoptionDisposition?
    private var ordinaryLedger: RetainedDescriptorConstructionLedger? { boundDescriptorScope?.ordinaryLedger }
    fileprivate var ownedLedger: RetainedOwnedComponentConstructionLedger? { boundDescriptorScope?.ownedLedger }
    var descriptorBuildAttempt: RetainedLazyListAttemptID? { boundDescriptorScope?.attempt }

    init(
        descriptorScope: RetainedLazyListDescriptorBuildScope, transaction: RetainedBuildTransaction,
        uiaContinuationAuthority: RetainedLazyListUIAContinuationAuthority? = nil
    ) {
        attempt = descriptorScope.attempt
        self.uiaContinuationAuthority = uiaContinuationAuthority
        origin = .descriptorBuild(descriptorScope)
        boundDescriptorScope = descriptorScope
        self.transaction = transaction
    }

    init(admission: RetainedLazyListAdoptionAdmission, transaction: RetainedBuildTransaction) {
        attempt = RetainedLazyListAttemptID()
        uiaContinuationAuthority = nil
        origin = .selectedRows(admission)
        self.transaction = transaction
    }

    var canContinueConstruction: Bool {
        guard phase == .constructing, !wasRevoked, uiaContinuationAuthority?.isCurrent != false,
            boundDescriptorScope?.canConstructDescriptors != false
        else {
            return false
        }
        switch origin {
        case .descriptorBuild(let scope): return scope.canConstructDescriptors
        case .selectedRows(let admission): return admission.isBuildCurrent
        }
    }

    var canContinueAdoption: Bool {
        guard !wasRevoked, phase == .prepared || phase == .adopting,
            uiaContinuationAuthority?.isCurrent != false,
            boundDescriptorScope?.canPublishDescriptors != false
        else { return false }
        switch origin {
        case .descriptorBuild(let scope): return scope.canPublishDescriptors
        case .selectedRows(let admission): return admission.isCurrent
        }
    }

    // This is publication routing, not write authority. Owner close must still
    // reach the accepted field's outgoing cleanup.
    private var usesRegionlessOrdinaryOwnedPublication: Bool {
        beganRegionlessOrdinaryOwnedAdoption && phase == .adopting
            && !hasManagedContributions && componentOrder.isEmpty && materializedRoots.isEmpty
            && physicalByMembership.isEmpty && acceptedRowTables.isEmpty
    }

    var hasDescriptorWork: Bool { !descriptorSources.isEmpty || !existingLogicalDeclarations.isEmpty }
    var hasManagedContributions: Bool { hasDescriptorWork || !groups.isEmpty || !unchanged.isEmpty }
    var hasAcceptedContributions: Bool {
        !acceptedFacetFacts.isEmpty || !logicalDeclarations.isEmpty || !emptyGroups.isEmpty
            || !logicalRemovals.isEmpty || !absences.isEmpty || !departures.isEmpty
            || ordinaryLedger?.hasAcceptedContributions == true
            || !acceptedRowTables.isEmpty
    }

    private var canRegisterSource: Bool { canContinueConstruction && preparedInput == nil }

    @discardableResult
    func bindDescriptorScope(_ scope: RetainedLazyListDescriptorBuildScope) -> Bool {
        guard canRegisterSource, scope.canConstructDescriptors else { return false }
        if let boundDescriptorScope { return boundDescriptorScope === scope }
        boundDescriptorScope = scope
        return true
    }

    private func isDescendant(_ component: RetainedLazyListComponentID, of ancestor: RetainedLazyListComponentID)
        -> Bool
    {
        var current: RetainedLazyListComponentID? = component
        var remaining = ViewNode.maximumTraversalDepth
        while let value = current, remaining > 0 {
            if value === ancestor { return true }
            current = componentParents[ObjectIdentifier(value)]
            remaining -= 1
        }
        return false
    }

    fileprivate func canConstructComponent(_ component: RetainedLazyListComponentID) -> Bool {
        canContinueConstruction && !componentIsRejected(component)
    }

    private func componentIsRejected(_ component: RetainedLazyListComponentID) -> Bool {
        var current: RetainedLazyListComponentID? = component
        var remaining = ViewNode.maximumTraversalDepth
        while let value = current, remaining > 0 {
            if rejectedComponents.contains(ObjectIdentifier(value)) { return true }
            current = componentParents[ObjectIdentifier(value)]
            remaining -= 1
        }
        return remaining == 0
    }

    fileprivate func rejectComponent(_ attribution: RetainedLazyListBuildAttribution) {
        guard phase == .constructing, attribution.journal === self else { return }
        rejectedComponents.insert(ObjectIdentifier(attribution.component))
        for record in groups.values {
            let rejected = record.outputs.filter { componentIsRejected($0.constructionComponent) }
            for output in rejected { output.node?.markRejectedRetainedSource() }
            guard preparedInput == nil else { continue }
            let payloads = Set(rejected.map { ObjectIdentifier($0.payload) })
            record.outputs.removeAll { payloads.contains(ObjectIdentifier($0.payload)) }
            record.required.removeAll { payloads.contains(ObjectIdentifier($0.source)) }
        }
    }

    fileprivate func registerChildComponent(
        from parent: RetainedLazyListBuildAttribution
    ) -> RetainedLazyListBuildAttribution? {
        guard canRegisterSource, parent.journal === self,
            parent.constructionState == .admittedForConstruction
        else { return nil }
        let component = RetainedLazyListComponentID()
        componentOrder.append(component)
        componentParents[ObjectIdentifier(component)] = parent.component
        return RetainedLazyListBuildAttribution(
            journal: self, rowRequest: parent.rowRequest, logicalMembership: parent.logicalMembership,
            physical: parent.physical, component: component, resolutionID: parent.resolutionID, origin: parent.origin)
    }

    fileprivate func registerGroup(
        attribution: RetainedLazyListBuildAttribution, kind: RetainedLazyListContributionKind
    ) -> RetainedLazyListGroupID? {
        guard canRegisterSource, attribution.journal === self,
            attribution.constructionState == .admittedForConstruction
        else { return nil }
        let record = RetainedLazyListGroupRecord(attribution: attribution, kind: kind)
        groups[ObjectIdentifier(record.id)] = record
        groupOrder.append(record.id)
        return record.id
    }

    private func addOutput(
        _ source: ViewNode, to record: RetainedLazyListGroupRecord,
        constructedBy component: RetainedLazyListComponentID
    ) -> RetainedLazyListSourceOutput? {
        if let existing = record.outputs.first(where: { $0.node === source }) { return existing }
        guard !record.isClosed else { return nil }
        let output = RetainedLazyListSourceOutput(
            node: source, component: record.attribution.component, group: record.id,
            constructionComponent: component)
        record.outputs.append(output)
        source.lazyListActivityStorage().sourceOutputs.append(output)
        record.require(output.facet(.childAttachment))
        if record.kind == .scopedTask {
            record.require(output.facet(.nodeProperty(\ViewNode.onAppearWithNode)))
            record.require(output.facet(.nodeProperty(\ViewNode.onDisappearWithNode)))
        } else {
            record.require(output.facet(.nodeCompletion))
        }
        return output
    }

    private func assignPendingDeclarations(
        in record: RetainedLazyListGroupRecord, to output: RetainedLazyListSourceOutput
    ) {
        for declaration in record.declarations {
            record.require(output.facet(.scopedTaskDeclaration(declaration)))
        }
    }

    fileprivate func recordSourceOutput(
        _ source: ViewNode, attribution: RetainedLazyListBuildAttribution, group: RetainedLazyListGroupID
    ) -> RetainedLazyListSourcePayloadID? {
        guard canRegisterSource, !source.containsRejectedRetainedSource,
            attribution.journal === self, attribution.constructionState == .admittedForConstruction,
            let requested = groups[ObjectIdentifier(group)],
            isDescendant(attribution.component, of: requested.attribution.component),
            let result = addOutput(source, to: requested, constructedBy: attribution.component)
        else { return nil }
        assignPendingDeclarations(in: requested, to: result)
        for id in groupOrder {
            guard let inherited = groups[ObjectIdentifier(id)], inherited !== requested, !inherited.isClosed,
                inherited.kind != .scopedTask,
                isDescendant(attribution.component, of: inherited.attribution.component)
            else { continue }
            _ = addOutput(source, to: inherited, constructedBy: attribution.component)
        }
        return result.payload
    }

    fileprivate func closeGroup(
        _ group: RetainedLazyListGroupID, attribution: RetainedLazyListBuildAttribution
    ) -> RetainedLazyListGroupProposal? {
        guard canRegisterSource, attribution.journal === self,
            let record = groups[ObjectIdentifier(group)],
            isDescendant(attribution.component, of: record.attribution.component)
        else { return nil }
        record.isClosed = true
        return record.proposal
    }

    fileprivate func registerTaskDeclaration(
        _ id: RetainedTaskDeclarationID, group: RetainedLazyListGroupID,
        attribution: RetainedLazyListBuildAttribution
    ) -> Bool {
        guard canRegisterSource, attribution.journal === self,
            attribution.constructionState == .admittedForConstruction,
            let record = groups[ObjectIdentifier(group)], record.kind == .scopedTask, !record.isClosed,
            isDescendant(attribution.component, of: record.attribution.component)
        else { return false }
        if !record.declarations.contains(where: { $0 === id }) { record.declarations.append(id) }
        for output in record.outputs { assignPendingDeclarations(in: record, to: output) }
        return true
    }

    func seedExistingContributions(from nodes: [ViewNode]) {
        ordinaryLedger?.seedExisting(from: nodes)
        var pending = nodes
        var seen: Set<ObjectIdentifier> = []
        while let node = pending.popLast() {
            guard seen.insert(ObjectIdentifier(node)).inserted else { continue }
            if let storage = node.retainedLazyListActivityStorage {
                if let declaration = storage.acceptedLogicalDeclaration {
                    existingLogicalDeclarations[ObjectIdentifier(storage.targetID)] = declaration
                }
                for receipt in storage.committedContributions.values where receipt.isActive {
                    physicalByMembership[ObjectIdentifier(receipt.physical.membership)] = receipt.physical
                }
            }
            pending.append(contentsOf: node.children)
        }
    }

    func prepareSelectedRow(
        request: RetainedLazyListRowRequest, descriptor: RetainedLazyListManagedLogicalDescriptorBinding
    ) -> RetainedLazyListSelectedRowPreparation? {
        guard canRegisterSource, descriptor.isCurrent, request.isGenerationCurrent,
            case .selectedRows(let admission) = origin
        else { return nil }
        let preparation = RetainedLazyListSelectedRowPreparation(
            attempt: attempt, descriptor: descriptor, request: request, admission: admission,
            descriptorBuildAttempt: descriptorBuildAttempt)
        preparations[ObjectIdentifier(preparation.resolutionID)] = preparation
        return preparation
    }

    func consumeSelectedRowResolution(
        _ response: RetainedLazyListSelectedRowResolution,
        for preparation: RetainedLazyListSelectedRowPreparation
    ) -> RetainedLazyListBuildAttribution? {
        guard canRegisterSource, preparation.isCurrent, !preparation.wasConsumed,
            preparation.attempt === attempt, response.resolutionID === preparation.resolutionID,
            preparations[ObjectIdentifier(preparation.resolutionID)] === preparation,
            response.descriptor === preparation.descriptor,
            case .selectedRows(let admission) = origin
        else { return nil }
        let binding = preparation.descriptor
        let logical: RetainedLazyListLogicalMembershipReceipt?
        switch response.source {
        case .proposed(let descriptor, let proposal):
            guard descriptor === binding.descriptor, proposal === binding.facadeProposal else { return nil }
            logical = binding.scope.proposeMembership(id: response.membership)
        case .committed(let descriptor):
            guard descriptor === binding.descriptor else { return nil }
            let proof = RetainedLazyListPriorLogicalMembershipProof(
                scope: binding.scope, acceptedDescriptor: descriptor, facadeProposal: binding.facadeProposal,
                membership: response.membership, request: preparation.request,
                sourceGeneration: binding.sourceGeneration, admission: admission)
            logical = binding.scope.admitSparseMembership(proof)
        }
        guard let logical, preparation.isCurrent, canContinueConstruction else { return nil }
        preparation.wasConsumed = true
        let physical: RetainedLazyListPhysicalActivityReceipt
        if let existing = physicalByMembership[ObjectIdentifier(logical.id)], existing.state == .active {
            physical = existing
        } else {
            physical = RetainedLazyListPhysicalActivityReceipt(membership: logical.id)
        }
        let component = RetainedLazyListComponentID()
        componentOrder.append(component)
        let attribution = RetainedLazyListBuildAttribution(
            journal: self, rowRequest: preparation.request, logicalMembership: logical, physical: physical,
            component: component, resolutionID: preparation.resolutionID, origin: .selectedRow)
        materializedRoots.append(attribution)
        return attribution
    }

    func abandonSelectedRowPreparation(_ preparation: RetainedLazyListSelectedRowPreparation) {
        guard preparations[ObjectIdentifier(preparation.resolutionID)] === preparation else { return }
        preparation.revoke()
    }

    func beginDeferredSubtree(
        originalAnchor: RetainedLazyListDeferredSubtreeAnchor
    ) -> RetainedLazyListBuildAttribution? {
        guard canRegisterSource, originalAnchor.isCurrent,
            case .descriptorBuild(let scope) = origin, scope.origin == .managedSubtree
        else { return nil }
        let component = RetainedLazyListComponentID()
        guard ownedLedger?.stageDeferredRegion(originalAnchor, component: component) != false else { return nil }
        componentOrder.append(component)
        let attribution = RetainedLazyListBuildAttribution(
            journal: self, rowRequest: originalAnchor.request,
            logicalMembership: originalAnchor.logicalMembership, physical: originalAnchor.contribution.physical,
            component: component, resolutionID: RetainedLazyListRowResolutionID(),
            origin: .deferredSubtree(originalContribution: originalAnchor.contribution))
        materializedRoots.append(attribution)
        return attribution
    }

    func registerSourceDescriptor(
        _ descriptor: RetainedLazyListManagedLogicalDescriptorBinding, on source: ViewNode
    ) -> RetainedLazyListDescriptorSourceFacet? {
        guard canRegisterSource, descriptor.isCurrent,
            let scope = descriptorScope(for: descriptor, on: source, inherited: nil)
        else { return nil }
        return registerSourceDescriptor(descriptor, on: source, scope: scope)
    }

    private func descriptorScope(
        for descriptor: RetainedLazyListManagedLogicalDescriptorBinding, on source: ViewNode,
        inherited: RetainedLazyListBuildAttribution?
    ) -> RetainedLazyListDescriptorBuildScope? {
        guard let boundDescriptorScope, boundDescriptorScope.canConstructDescriptors else { return nil }
        let parent = descriptor.scope.parentRow
        if boundDescriptorScope.acceptsLogicalParent(parent) { return boundDescriptorScope }
        let own = ownedOutputs(of: source).compactMap { groups[ObjectIdentifier($0.group)]?.attribution }
        let possible = own + (inherited.map { [$0] } ?? [])
        guard let attribution = possible.first(where: { $0.logicalMembership === parent }) else { return nil }
        return boundDescriptorScope.withContainingRow(attribution)
    }

    func registerSourceDescriptor(
        _ descriptor: RetainedLazyListManagedLogicalDescriptorBinding, on source: ViewNode,
        scope: RetainedLazyListDescriptorBuildScope
    ) -> RetainedLazyListDescriptorSourceFacet? {
        guard canRegisterSource, descriptor.isCurrent, scope.canConstructDescriptors,
            scope.acceptsLogicalParent(descriptor.scope.parentRow)
        else { return nil }
        if let previous = descriptorSources[ObjectIdentifier(descriptor.descriptor)] {
            guard previous.descriptor === descriptor, previous.sourceNode === source else { return nil }
            source.lazyListActivityStorage().sourceDescriptor = previous
            return previous
        }
        let record = RetainedLazyListDescriptorSourceFacet(
            sourceNode: source, descriptor: descriptor,
            source: RetainedLazyListSourcePayloadID(), facet: RetainedLazyListSourceFacetID(),
            component: RetainedLazyListComponentID(), group: RetainedLazyListGroupID(), scope: scope)
        descriptorSources[ObjectIdentifier(descriptor.descriptor)] = record
        source.lazyListActivityStorage().sourceDescriptor = record
        return record
    }

    @discardableResult
    func registerSourceDescriptors(in nodes: [ViewNode]) -> Bool {
        guard canRegisterSource, !ViewNode.containsRejectedRetainedSource(in: nodes) else {
            wasRevoked = true
            return false
        }
        var pending: [(ViewNode, RetainedLazyListBuildAttribution?)] = nodes.map { ($0, nil) }
        var seen: Set<ObjectIdentifier> = []
        while let (node, inherited) = pending.popLast() {
            guard seen.insert(ObjectIdentifier(node)).inserted else { continue }
            let local = ownedOutputs(of: node).compactMap { groups[ObjectIdentifier($0.group)]?.attribution }.first
            let containing = local ?? inherited
            if let descriptor = node.retainedLazyListAdapter?.managedLogicalDescriptorBinding {
                guard descriptor.isCurrent,
                    let scope = descriptorScope(for: descriptor, on: node, inherited: containing),
                    registerSourceDescriptor(descriptor, on: node, scope: scope) != nil
                else {
                    // A present managed binding never becomes the raw provider path.
                    wasRevoked = true
                    return false
                }
            }
            pending.append(contentsOf: node.children.map { ($0, containing) })
        }
        return true
    }

    func preparation() -> RetainedLazyListAdoptionPreparation? {
        guard canContinueConstruction else { return nil }
        return freezePreparation()
    }

    private func freezePreparation() -> RetainedLazyListAdoptionPreparation {
        if let preparedInput { return preparedInput }
        for record in groups.values { record.isClosed = true }
        var scopes: [RetainedLazyListLogicalMembershipScope] = []
        for source in descriptorSources.values {
            if !scopes.contains(where: { $0 === source.descriptor.scope }) { scopes.append(source.descriptor.scope) }
        }
        for previous in existingLogicalDeclarations.values {
            let scope = previous.membershipPlan.expected.scope
            if !scopes.contains(where: { $0 === scope }) { scopes.append(scope) }
        }
        let ordinaryComponents = ordinaryLedger?.freeze() ?? []
        var rejectedOwnedComponents: Set<RetainedOwnedComponentKey> = []
        for id in componentOrder where componentIsRejected(id) {
            rejectedOwnedComponents.insert(.lazy(ObjectIdentifier(id)))
        }
        for component in ordinaryComponents where ordinaryLedger?.isRejected(component.component) == true {
            rejectedOwnedComponents.insert(.descriptor(ObjectIdentifier(component.component)))
        }
        let ownedPlans =
            ownedLedger?.freeze(
                sources: ownedSourceRecords(ordinaryComponents: ordinaryComponents),
                componentParents: ownedComponentParents(ordinaryComponents: ordinaryComponents),
                excluding: rejectedOwnedComponents) ?? []
        let preparation = RetainedLazyListAdoptionPreparation(
            attempt: attempt, groups: groupOrder.compactMap { groups[ObjectIdentifier($0)]?.proposal },
            components: componentOrder.map {
                RetainedLazyListComponentProposal(component: $0, parent: componentParents[ObjectIdentifier($0)])
            },
            expectedExisting: unchanged, logicalSnapshots: scopes.map { $0.snapshot() },
            logicalDescriptors: descriptorSources.values.map(\.descriptor),
            ordinaryComponents: ordinaryComponents,
            expectedOrdinaryContributions: ordinaryLedger?.expectedExisting ?? [],
            ownedComponentDeclarations: ownedPlans)
        preparedInput = preparation
        return preparation
    }

    private func ownedSourceRecords(
        ordinaryComponents: [RetainedDescriptorComponentProposal]
    ) -> [RetainedOwnedComponentSource] {
        var result: [RetainedOwnedComponentSource] = []
        for record in groups.values {
            for output in record.outputs {
                var ancestry: [RetainedOwnedComponentDeclarationOrigin] = []
                var current: RetainedLazyListComponentID? = output.constructionComponent
                while let id = current, ancestry.count < ViewNode.maximumTraversalDepth {
                    ancestry.append(.lazy(component: id))
                    current = componentParents[ObjectIdentifier(id)]
                }
                result.append(
                    RetainedOwnedComponentSource(
                        node: output.node, payload: output.payload,
                        facets: output.facets.values.map(\.id), components: ancestry,
                        deferredRoot: record.kind == .deferredSubtree ? record.attribution.component : nil))
            }
        }
        for component in ordinaryComponents {
            for output in ordinaryLedger?.sourceOutputs(for: component.component) ?? [] {
                var ancestry: [RetainedOwnedComponentDeclarationOrigin] = []
                var current: RetainedDescriptorComponentID? = output.constructionComponent
                while let id = current, ancestry.count < ViewNode.maximumTraversalDepth {
                    ancestry.append(.descriptor(component: id))
                    current = ordinaryLedger?.parentComponent(of: id)
                }
                result.append(
                    RetainedOwnedComponentSource(
                        node: output.node, payload: output.payload,
                        facets: output.facets.values.map(\.id), components: ancestry, deferredRoot: nil))
            }
        }
        return result
    }

    private func ownedComponentParents(
        ordinaryComponents: [RetainedDescriptorComponentProposal]
    ) -> [RetainedOwnedComponentKey: RetainedOwnedComponentKey] {
        var parents: [RetainedOwnedComponentKey: RetainedOwnedComponentKey] = [:]
        for (child, parent) in componentParents {
            parents[.lazy(child)] = .lazy(ObjectIdentifier(parent))
        }
        for component in ordinaryComponents {
            if let parent = component.parent {
                parents[.descriptor(ObjectIdentifier(component.component))] = .descriptor(ObjectIdentifier(parent))
            }
        }
        return parents
    }

    func beginAdoption(
        _ preparation: RetainedLazyListAdoptionPreparation,
        preparedActivity: RetainedLazyListPreparedActivity
    ) -> Bool {
        guard canContinueConstruction, self.preparedInput === preparation,
            preparedActivity.preparation === preparation, preparation.attempt === attempt,
            ordinaryLedger?.hasUnsupportedTaskDeclarations != true
        else { return false }
        var plans: Set<ObjectIdentifier> = []
        for plan in preparedActivity.logicalMembershipPlans {
            guard plan.isCurrent, plans.insert(ObjectIdentifier(plan.descriptor)).inserted,
                let source = descriptorSources[ObjectIdentifier(plan.descriptor)],
                source.descriptor.scope === plan.expected.scope,
                source.descriptor.facadeProposal === plan.facadeProposal,
                source.descriptor.sourceGeneration == plan.sourceGeneration,
                preparation.logicalSnapshots.contains(where: {
                    $0.scope === plan.expected.scope && $0.rosterRevision === plan.expected.rosterRevision
                })
            else { return false }
        }
        // Every new descriptor has its own exact plan. Already accepted unchanged
        // descriptors may be preserved without a new membership proposal.
        for source in descriptorSources.values {
            if source.descriptor.scope.containsDeclaredDescriptor(source.descriptor.descriptor) { continue }
            guard plans.contains(ObjectIdentifier(source.descriptor.descriptor)) else { return false }
        }
        guard
            ownedLedger?.admitsPreparedRows(
                materializedRoots, plans: preparedActivity.ownedComponentPlans) != false,
            ownedLedger?.prepare(preparedActivity.ownedComponentPlans) != false
        else { return false }
        self.preparedActivity = preparedActivity
        phase = .prepared
        boundDescriptorScope?.preparationDidSucceed()
        return canContinueAdoption
    }

    /// Records metadata beside the existing ordinary epoch boundary. It does
    /// not change the legacy facade publication or its matching-time policy.
    func beginOrdinaryAdoption() -> Bool {
        guard uiaContinuationAuthority?.isCurrent != false else { return false }
        isOrdinaryAdoption = true
        guard !hasDescriptorWork, phase == .constructing, !wasRevoked else { return false }
        let preparation = freezePreparation()
        let response = RetainedLazyListPreparedActivity(
            preparation: preparation, logicalMembershipPlans: [],
            ownedComponentPlans: preparation.ownedComponentDeclarations)
        guard ownedLedger?.prepare(response.ownedComponentPlans) != false else { return false }
        if let boundDescriptorScope, !boundDescriptorScope.observeOrdinaryAdoption() { return false }
        preparedActivity = response
        phase = .adopting
        // The earlier ordinary flag also marks failed attempts. Only a fully
        // prepared descriptor attempt can select the regionless owned path.
        if case .descriptorBuild = origin,
            !hasManagedContributions, componentOrder.isEmpty, materializedRoots.isEmpty,
            physicalByMembership.isEmpty, acceptedRowTables.isEmpty,
            ownedLedger?.hasRegionlessOrdinaryProvenance == true
        {
            beganRegionlessOrdinaryOwnedAdoption = true
        }
        return true
    }

    @discardableResult
    func markMutationStarted() -> Bool {
        guard canContinueAdoption else { return false }
        if phase == .prepared {
            if let boundDescriptorScope, !boundDescriptorScope.beginAdoption() { return false }
            phase = .adopting
        }
        guard activateRowReplacementHandoffs() else { return false }
        didMutate = true
        return true
    }

    private func activateRowReplacementHandoffs() -> Bool {
        let pending = rowReplacementHandoffs.values.filter { !$0.wasFinished && !$0.isActive }
        guard
            pending.allSatisfy({ handoff in
                handoff.successor.attempt === attempt && handoff.successor.isCurrent
                    && handoff.successor.logicalMembership === handoff.previous.logicalMembership
                    && handoff.successor.physical === handoff.previous.physical
                    && handoff.successor.physical.canBeginRowReplacementHandoff
                    && handoff.attachments.allSatisfy(\.isAttached)
                    && handoff.successor.physical.actualAttachments.count == handoff.attachments.count
                    && handoff.successor.physical.actualAttachments.allSatisfy { actual in
                        handoff.attachments.contains {
                            $0.target === actual.target && $0.attachment === actual.attachment
                        }
                    }
                    && groups.values.allSatisfy { record in
                        !isDescendant(record.attribution.component, of: handoff.successor.component)
                            || record.isClosed
                    }
            })
        else { return false }
        for handoff in pending {
            guard handoff.successor.physical.beginRowReplacementHandoff(handoff.id) else {
                for activated in pending where activated.isActive { activated.finish() }
                return false
            }
            handoff.isActive = true
        }
        return true
    }

    private func finishRowReplacementHandoffs() {
        for handoff in rowReplacementHandoffs.values { handoff.finish() }
        rowReplacementHandoffs.removeAll()
    }

    private func actualAttachment(for node: ViewNode) -> RetainedLazyListActualAttachment? {
        guard let runtime = node.retainedLazyListRuntime else { return nil }
        return node.lazyListActivityStorage().captureActualAttachment(of: node, in: runtime)
    }

    private func ownedOutputs(of source: ViewNode) -> [RetainedLazyListSourceOutput] {
        source.retainedLazyListActivityStorage?.sourceOutputs.filter { output in
            output.node === source
                && groups[ObjectIdentifier(output.group)]?.outputs.contains(where: { $0 === output }) == true
        } ?? []
    }

    private func recordInsertionPublication(
        from source: ViewNode, to target: ViewNode, actual: RetainedLazyListActualAttachment,
        copiedConfiguration: Bool = false, inserted: Bool = false
    ) {
        guard case .selectedRows(let admission) = origin else { return }
        admission.recordAcceptedInsertionPublication(
            from: source, to: target, actual: actual,
            copiedConfiguration: copiedConfiguration, inserted: inserted)
    }

    func preparePropertyCopy(
        from source: ViewNode, to target: ViewNode, keyPath: PartialKeyPath<ViewNode>
    ) -> Bool {
        guard canContinueAdoption, !source.containsRejectedRetainedSource,
            ordinaryLedger?.preparePropertyCopy(from: source, to: target, keyPath: keyPath) != false,
            ownedLedger?.preparePropertyCopy(from: source, to: target, keyPath: keyPath) != false,
            let actual = actualAttachment(for: target)
        else { return false }
        // Bind key-path facets to already registered source/group identity before
        // the field write. No application field getter or final-child scan occurs.
        let field = RetainedLazyListNativeFacet.nodeProperty(keyPath)
        let outputs = ownedOutputs(of: source)
        let hasPayload = source.retainedSourcePayloadFields.contains(keyPath)
        for output in outputs {
            _ = output.facet(field)
            if hasPayload { output.retirementProperties.insert(field.key) }
        }
        let incoming = outputs.compactMap { groups[ObjectIdentifier($0.group)]?.receipt }
        let previous =
            target.retainedLazyListActivityStorage?.committedContributions.values.filter { receipt in
                !incoming.contains(where: { $0 === receipt })
                    && receipt.acceptedNativeFacets.contains {
                        $0.source.nativeField.key == field.key && $0.actual.target === actual.target
                            && $0.actual.attachment === actual.attachment
                    }
            } ?? []
        let key = RetainedLazyListPropertyCopyKey(
            source: ObjectIdentifier(source), target: ObjectIdentifier(target), field: keyPath)
        propertyCopies[key] = RetainedLazyListPendingPropertyCopy(
            source: source, target: target, targetID: actual.target, attachmentID: actual.attachment,
            previous: Array(previous))
        return true
    }

    @discardableResult
    func recordAcceptedProperty(
        from source: ViewNode, to target: ViewNode, keyPath: PartialKeyPath<ViewNode>
    ) -> [RetainedLazyListAcceptedTaskGroup] {
        let key = RetainedLazyListPropertyCopyKey(
            source: ObjectIdentifier(source), target: ObjectIdentifier(target), field: keyPath)
        guard let pending = propertyCopies.removeValue(forKey: key),
            pending.source === source, pending.target === target,
            let actual = actualAttachment(for: target),
            actual.target === pending.targetID, actual.attachment === pending.attachmentID
        else { return [] }
        recordInsertionPublication(
            from: source, to: target, actual: actual,
            copiedConfiguration: keyPath == \ViewNode.transition || keyPath == \ViewNode.implicitReconcileAnimation
                || keyPath == \ViewNode.reconcileAnimationModifiers)
        boundDescriptorScope?.recordAcceptedDescriptor()
        ownedLedger?.recordAcceptedProperty(
            from: source, to: target, keyPath: keyPath,
            ordinaryPublication: { self.usesRegionlessOrdinaryOwnedPublication })
        _ = ordinaryLedger?.recordAcceptedProperty(from: source, to: target, keyPath: keyPath)
        for absence in ordinaryLedger?.takePropertyAbsences() ?? [] {
            boundDescriptorScope?.recordAcceptedOriginalRetirement(absence.previous)
            claimDescriptorTaskAbsence(absence)
        }
        for previous in pending.previous {
            let removed = previous.acceptedNativeFacets.filter {
                $0.source.nativeField.key == RetainedLazyListNativeFacet.nodeProperty(keyPath).key
                    && $0.actual.target === actual.target && $0.actual.attachment === actual.attachment
            }
            guard !removed.isEmpty else { continue }
            recordAcceptedAbsence(
                RetainedLazyListAcceptedAbsence(
                    previous: previous, actual: actual, removalFacets: removed, cleanup: RetainedLazyListCleanupID()),
                permitsOriginalCompletion: true)
        }
        for output in ownedOutputs(of: source) {
            guard let facet = output.facets[RetainedLazyListNativeFacet.nodeProperty(keyPath).key] else { continue }
            recordAcceptedFacet(facet, actual: actual)
        }
        return completeGroups()
    }

    @discardableResult
    func recordAcceptedAttachment(from source: ViewNode, to target: ViewNode) -> [RetainedLazyListAcceptedTaskGroup] {
        guard let actual = actualAttachment(for: target) else { return [] }
        recordInsertionPublication(from: source, to: target, actual: actual)
        boundDescriptorScope?.recordAcceptedDescriptor()
        _ = ordinaryLedger?.recordAcceptedAttachment(from: source, to: target)
        for output in ownedOutputs(of: source) {
            if let facet = output.facets[.attachment] { recordAcceptedFacet(facet, actual: actual) }
        }
        return completeGroups()
    }

    @discardableResult
    func recordCompletedNode(from source: ViewNode, to target: ViewNode) -> [RetainedLazyListAcceptedTaskGroup] {
        guard let actual = actualAttachment(for: target) else { return [] }
        let outputs = ownedOutputs(of: source)
        let incoming = outputs.compactMap { groups[ObjectIdentifier($0.group)]?.receipt }
        let previous = target.retainedLazyListActivityStorage?.committedContributions.values.map { $0 } ?? []
        for receipt in previous where !incoming.contains(where: { $0 === receipt }) {
            // Another accepted output in this journal can share completion on
            // this attachment without replacing its peer's contribution.
            guard groups[ObjectIdentifier(receipt.group)]?.receipt !== receipt else { continue }
            let removed = receipt.acceptedNativeFacets.filter {
                $0.source.nativeField.key == .completion && $0.actual.target === actual.target
                    && $0.actual.attachment === actual.attachment
            }
            if !removed.isEmpty {
                recordAcceptedAbsence(
                    RetainedLazyListAcceptedAbsence(
                        previous: receipt, actual: actual, removalFacets: removed,
                        cleanup: RetainedLazyListCleanupID()),
                    permitsOriginalCompletion: true)
            }
        }
        ownedLedger?.recordCompletedNode(
            from: source, to: target,
            ordinaryPublication: { self.usesRegionlessOrdinaryOwnedPublication })
        _ = ordinaryLedger?.recordCompletedNode(from: source, to: target)
        for absence in ordinaryLedger?.takePropertyAbsences() ?? [] {
            boundDescriptorScope?.recordAcceptedOriginalRetirement(absence.previous)
            claimDescriptorTaskAbsence(absence)
        }
        for output in outputs {
            if let facet = output.facets[.completion] { recordAcceptedFacet(facet, actual: actual) }
        }
        return completeGroups()
    }

    func prepareOwnedStructuralDeclaration(from source: ViewNode, to target: ViewNode) -> Bool {
        guard canContinueAdoption, !source.containsRejectedRetainedSource else { return false }
        return ownedLedger?.prepareStructuralDeclaration(from: source, to: target) != false
    }

    /// Consumes the native-only preflight immediately beside the exact final
    /// children-field publication. It never evaluates application code.
    func recordAcceptedOwnedStructuralDeclaration(from source: ViewNode, to target: ViewNode) {
        if let actual = ownedLedger?.recordAcceptedStructuralDeclaration(
            from: source, to: target,
            ordinaryPublication: { self.usesRegionlessOrdinaryOwnedPublication })
        {
            recordInsertionPublication(from: source, to: target, actual: actual)
        }
    }

    @discardableResult
    func recordCompletedOwnedDescriptorScope(structuralAnchor: RetainedLazyListActualAttachment) -> Bool {
        guard canContinueAdoption, structuralAnchor.isAttached else { return false }
        guard ownedLedger?.hasAcceptedDeferredRegion(at: structuralAnchor) != false else { return false }
        guard ownedLedger?.recordCompletedDescriptorScope(anchor: structuralAnchor) != false else { return false }
        boundDescriptorScope?.recordAcceptedDescriptor()
        return true
    }

    @discardableResult
    func recordAcceptedTaskDeclarationTransport(
        from source: ViewNode, to target: ViewNode, declarationIDs: [RetainedTaskDeclarationID]
    ) -> [RetainedLazyListAcceptedTaskGroup] {
        guard let actual = actualAttachment(for: target) else { return [] }
        let acceptedIDs = Set(declarationIDs.map { ObjectIdentifier($0) })
        for output in ownedOutputs(of: source) {
            for facet in output.facets.values {
                guard case .scopedTaskDeclaration(let id) = facet.nativeField,
                    acceptedIDs.contains(ObjectIdentifier(id))
                else { continue }
                recordAcceptedFacet(facet, actual: actual)
            }
        }
        return completeGroups()
    }

    func recordAcceptedDescriptorTaskDeclarationTransport(
        from source: ViewNode, to target: ViewNode, declarationIDs: [RetainedTaskDeclarationID]
    ) {
        _ = ordinaryLedger?.recordAcceptedTaskDeclarationTransport(
            from: source, to: target, declarationIDs: declarationIDs)
    }

    func takeAcceptedDescriptorTaskGroups() -> [RetainedDescriptorAcceptedTaskGroup] {
        ordinaryLedger?.takeAcceptedTaskGroups() ?? []
    }

    func acceptedDescriptorTaskSources(
        for group: RetainedDescriptorAcceptedTaskGroup
    ) -> [RetainedLazyListAcceptedTaskSource]? {
        ordinaryLedger?.acceptedTaskSources(for: group)
    }

    @discardableResult
    func recordAcceptedOrdinaryEmptyGroups(
        structuralAnchor: RetainedLazyListActualAttachment, groups: [RetainedDescriptorGroupID]
    ) -> [RetainedDescriptorAcceptedEmptyGroup] {
        let accepted = ordinaryLedger?.recordAcceptedEmptyGroups(anchor: structuralAnchor, groups: groups) ?? []
        for fact in accepted {
            ownedLedger?.recordAcceptedEmpty(
                origin: .descriptor(component: fact.proposal.component), anchor: structuralAnchor)
        }
        return accepted
    }

    @discardableResult
    func recordAcceptedFacet(
        _ source: RetainedLazyListSourceFacet, actual: RetainedLazyListActualAttachment
    ) -> RetainedLazyListAcceptedFacet {
        let fact = RetainedLazyListAcceptedFacet(source: source, actual: actual)
        let key = ObjectIdentifier(source.id)
        if let prior = acceptedFacetByID[key] {
            if prior.actual.target !== actual.target || prior.actual.attachment !== actual.attachment {
                invalidGroups.insert(ObjectIdentifier(source.group))
                acceptedFacetFacts.append(fact)
            }
            return fact
        }
        acceptedFacetByID[key] = fact
        acceptedFacetFacts.append(fact)
        if let group = groups[ObjectIdentifier(source.group)] { _ = group.attribution.physical.activate(on: actual) }
        return fact
    }

    private func completeGroups() -> [RetainedLazyListAcceptedTaskGroup] {
        var taskGroups: [RetainedLazyListAcceptedTaskGroup] = []
        for id in groupOrder {
            let key = ObjectIdentifier(id)
            guard !completedGroupIDs.contains(key), !invalidGroups.contains(key),
                let record = groups[key], record.isClosed, !record.required.isEmpty,
                !componentIsRejected(record.attribution.component),
                record.required.allSatisfy({ acceptedFacetByID[ObjectIdentifier($0.id)] != nil })
            else { continue }
            let facts = record.required.compactMap { acceptedFacetByID[ObjectIdentifier($0.id)] }
            var actuals: [RetainedLazyListActualAttachment] = []
            var coherent = true
            for output in record.outputs {
                let outputFacts = facts.filter { $0.source.source === output.payload }
                guard let first = outputFacts.first,
                    outputFacts.allSatisfy({
                        $0.actual.target === first.actual.target && $0.actual.attachment === first.actual.attachment
                    })
                else {
                    coherent = false
                    break
                }
                if record.kind == .scopedTask
                    && actuals.contains(where: {
                        $0.target === first.actual.target && $0.attachment === first.actual.attachment
                    })
                {
                    coherent = false
                    break
                }
                actuals.append(first.actual)
            }
            guard coherent, record.receipt.activate(on: actuals) else { continue }
            let accepted = RetainedLazyListAcceptedGroup(
                proposal: record.proposal, acceptedFacets: facts, receipt: record.receipt)
            record.receipt.acceptedNativeFacets =
                record.kind == .scopedTask
                ? facts
                : acceptedFacetFacts.filter { fact in
                    guard fact.source.group === record.id,
                        let output = record.outputs.first(where: { $0.payload === fact.source.source })
                    else { return false }
                    switch fact.source.nativeField {
                    case .nodeProperty: return output.retirementProperties.contains(fact.source.nativeField.key)
                    case .childAttachment, .nodeCompletion: return true
                    case .scopedTaskDeclaration, .listDescriptor: return false
                    }
                }
            record.receipt.taskDeclarations = record.declarations
            completedGroupIDs.insert(key)
            completedGroups.append(accepted)
            for actual in actuals {
                actual.node?.lazyListActivityStorage().committedContributions[key] = record.receipt
                if record.kind == .deferredSubtree {
                    let region = ownedLedger?.acceptedDeferredRegion(
                        component: record.attribution.component, actual: actual)
                    // Inherited output facets can include a nested reader.
                    // Only the namespace's own accepted source may replace its
                    // anchor; an enclosing group's completion cannot claim it.
                    if region != nil
                        || ownedLedger?.hasDeferredRegionSource(component: record.attribution.component) != true
                    {
                        actual.node?.lazyListActivityStorage().deferredSubtreeAnchor =
                            RetainedLazyListDeferredSubtreeAnchor(
                                contribution: record.receipt, actual: actual, request: record.attribution.rowRequest,
                                logicalMembership: record.attribution.logicalMembership, ownedRegion: region)
                    }
                }
            }
            if record.kind == .scopedTask {
                let members = record.outputs.compactMap { output -> RetainedLazyListAcceptedTaskMember? in
                    let outputFacts = facts.filter { $0.source.source === output.payload }
                    guard let actual = outputFacts.first?.actual else { return nil }
                    return RetainedLazyListAcceptedTaskMember(
                        sourcePayload: output.payload, requiredFacets: outputFacts.map { $0.source.id }, actual: actual)
                }
                guard !record.declarations.isEmpty, members.count == record.outputs.count else { continue }
                taskGroups.append(
                    RetainedLazyListAcceptedTaskGroup(
                        contribution: accepted, declarationIDs: record.declarations, members: members))
            }
        }
        return taskGroups
    }

    func acceptedTaskSources(
        for group: RetainedLazyListAcceptedTaskGroup
    ) -> [RetainedLazyListAcceptedTaskSource]? {
        let key = ObjectIdentifier(group.contribution.proposal.group)
        guard let record = groups[key], record.kind == .scopedTask,
            group.contribution.proposal.attempt === attempt,
            completedGroupIDs.contains(key), !invalidGroups.contains(key),
            group.contribution.receipt === record.receipt, record.receipt.isActive,
            !group.members.isEmpty,
            group.members.count == record.outputs.count,
            group.declarationIDs.count == record.declarations.count,
            zip(group.declarationIDs, record.declarations).allSatisfy({ $0.0 === $0.1 })
        else { return nil }
        var pins: [RetainedLazyListAcceptedTaskSource] = []
        var seen: Set<ObjectIdentifier> = []
        for member in group.members {
            guard seen.insert(ObjectIdentifier(member.sourcePayload)).inserted,
                let output = record.outputs.first(where: { $0.payload === member.sourcePayload }),
                let source = output.node, member.actual.isAttached
            else { return nil }
            let required = record.required.filter { $0.source === output.payload }.map(\.id)
            guard required.count == member.requiredFacets.count,
                zip(required, member.requiredFacets).allSatisfy({ $0.0 === $0.1 }),
                required.allSatisfy({ id in
                    guard let fact = acceptedFacetByID[ObjectIdentifier(id)] else { return false }
                    return fact.source.source === member.sourcePayload
                        && fact.actual.target === member.actual.target
                        && fact.actual.attachment === member.actual.attachment
                })
            else { return nil }
            pins.append(RetainedLazyListAcceptedTaskSource(member: member, source: source))
        }
        return pins
    }

    func recordAcceptedGroup(_ proposal: RetainedLazyListGroupProposal) -> RetainedLazyListAcceptedGroup? {
        _ = completeGroups()
        return completedGroups.first { $0.proposal.group === proposal.group }
    }

    @discardableResult
    func recordAcceptedEmpty(
        _ proposal: RetainedLazyListGroupProposal, structuralAnchor: RetainedLazyListActualAttachment
    ) -> RetainedLazyListAcceptedEmptyGroup? {
        guard canContinueAdoption, let record = groups[ObjectIdentifier(proposal.group)],
            record.isClosed, record.outputs.isEmpty, proposal.attempt === attempt,
            !componentIsRejected(record.attribution.component),
            !completedGroupIDs.contains(ObjectIdentifier(proposal.group)),
            record.kind != .scopedTask, structuralAnchor.isAttached,
            markMutationStarted(), record.receipt.activate(on: [structuralAnchor])
        else { return nil }
        let fact = RetainedLazyListAcceptedEmptyGroup(
            proposal: record.proposal, structuralAnchor: structuralAnchor, receipt: record.receipt)
        completedGroupIDs.insert(ObjectIdentifier(proposal.group))
        emptyGroups.append(fact)
        ownedLedger?.recordAcceptedEmpty(
            origin: .lazy(component: record.attribution.component), anchor: structuralAnchor)
        structuralAnchor.node?.lazyListActivityStorage().committedContributions[ObjectIdentifier(proposal.group)] =
            record.receipt
        return fact
    }

    func recordUnchanged(_ contribution: RetainedLazyListUnchangedContribution) {
        guard contribution.receipt.isActive, contribution.actualAttachments.allSatisfy(\.isAttached) else { return }
        if !unchanged.contains(where: { $0.receipt === contribution.receipt }) { unchanged.append(contribution) }
    }

    func recordUnchangedNode(_ node: ViewNode) {
        ordinaryLedger?.recordExisting(node)
        guard let storage = node.retainedLazyListActivityStorage, let actual = actualAttachment(for: node) else {
            return
        }
        for receipt in storage.committedContributions.values where receipt.isActive {
            recordUnchanged(RetainedLazyListUnchangedContribution(receipt: receipt, actualAttachments: [actual]))
        }
    }

    private func plan(for descriptor: RetainedLazyListLogicalDeclarationID) -> RetainedLazyListLogicalMembershipPlan? {
        preparedActivity?.logicalMembershipPlans.first { $0.descriptor === descriptor }
    }

    func prepareLogicalDescriptorPublication(
        source: RetainedLazyListDescriptorSourceFacet, actual: RetainedLazyListActualAttachment
    ) -> RetainedLazyListLogicalDescriptorPublication? {
        guard canContinueAdoption, source.scope.canPublishDescriptors, source.descriptor.isCurrent,
            descriptorSources[ObjectIdentifier(source.descriptor.descriptor)]?.source === source.source,
            actual.isAttached, let plan = plan(for: source.descriptor.descriptor), plan.isCurrent
        else { return nil }
        return RetainedLazyListLogicalDescriptorPublication(
            attempt: attempt, plan: plan, source: .descriptorBuild(source), actual: actual)
    }

    func prepareLogicalDescriptorPublication(
        descriptor: RetainedLazyListLogicalDeclarationID,
        sourceFacet: RetainedLazyListSourceFacet,
        actual: RetainedLazyListActualAttachment
    ) -> RetainedLazyListLogicalDescriptorPublication? {
        guard canContinueAdoption, actual.isAttached, let plan = plan(for: descriptor), plan.isCurrent,
            case .listDescriptor(let id) = sourceFacet.nativeField, id === descriptor
        else { return nil }
        return RetainedLazyListLogicalDescriptorPublication(
            attempt: attempt, plan: plan, source: .selectedRow(sourceFacet), actual: actual)
    }

    func prepareDescriptorCopy(from source: ViewNode, to target: ViewNode) -> RetainedLazyListDescriptorCopyPreparation
    {
        let binding = source.retainedLazyListAdapter?.managedLogicalDescriptorBinding
        guard let binding else {
            guard let previous = target.retainedLazyListActivityStorage?.acceptedLogicalDeclaration else {
                return .unmanaged
            }
            guard let actual = actualAttachment(for: target),
                let removal = prepareLogicalScopeRemoval(
                    expected: previous.membershipPlan.expected.scope.snapshot(), actual: actual)
            else { return .rejected }
            return .removal(removal)
        }
        guard let descriptor = source.retainedLazyListActivityStorage?.sourceDescriptor,
            descriptor.descriptor === binding, descriptor.sourceNode === source,
            descriptorSources[ObjectIdentifier(binding.descriptor)]?.source === descriptor.source,
            descriptor.descriptor.isCurrent, canContinueAdoption
        else { return .rejected }
        if let existing = target.retainedLazyListActivityStorage?.acceptedLogicalDeclaration,
            existing.declaration === descriptor.descriptor.descriptor
        {
            return .unchanged
        }
        guard let actual = actualAttachment(for: target),
            let ticket = prepareLogicalDescriptorPublication(source: descriptor, actual: actual)
        else { return .rejected }
        return .ready(ticket)
    }

    @discardableResult
    func recordAcceptedLogicalDeclaration(
        _ publication: RetainedLazyListLogicalDescriptorPublication
    ) -> RetainedLazyListAcceptedLogicalDeclaration? {
        guard publication.attempt === attempt else { return nil }
        if let fact = publication.publishedFact { return fact }
        guard publication.plan.publishAccepted() else { return nil }
        let fact = RetainedLazyListAcceptedLogicalDeclaration(
            declaration: publication.plan.descriptor, installedList: publication.actual,
            membershipPlan: publication.plan)
        publication.publishedFact = fact
        logicalDeclarations.append(fact)
        publication.actual.node?.lazyListActivityStorage().acceptedLogicalDeclaration = fact
        if let node = publication.actual.node {
            node.retainedLazyListAdapter?.activateInsertionBuildTransaction(in: node)
        }
        switch publication.source {
        case .descriptorBuild(let source): source.scope.recordAcceptedDescriptor()
        case .selectedRow: break
        }
        return fact
    }

    func prepareInsertedDescriptor(on source: ViewNode) -> Bool {
        guard let binding = source.retainedLazyListAdapter?.managedLogicalDescriptorBinding else { return true }
        guard let record = source.retainedLazyListActivityStorage?.sourceDescriptor,
            record.descriptor === binding, record.sourceNode === source,
            descriptorSources[ObjectIdentifier(binding.descriptor)]?.source === record.source,
            canContinueAdoption, record.descriptor.isCurrent, record.scope.canPublishDescriptors
        else { return false }
        if record.descriptor.scope.containsDeclaredDescriptor(record.descriptor.descriptor) { return true }
        guard let plan = plan(for: record.descriptor.descriptor), plan.isCurrent else { return false }
        let storage = source.lazyListActivityStorage()
        insertedDescriptors[ObjectIdentifier(storage.targetID)] = RetainedLazyListPendingInsertedDescriptor(
            node: source, target: storage.targetID, attachment: storage.attachmentID, source: record, plan: plan)
        return true
    }

    @discardableResult
    func recordAcceptedInsertedDescriptor(on node: ViewNode) -> RetainedLazyListAcceptedLogicalDeclaration? {
        let storage = node.lazyListActivityStorage()
        guard let pending = insertedDescriptors.removeValue(forKey: ObjectIdentifier(storage.targetID)),
            pending.node === node, pending.target === storage.targetID,
            pending.attachment === storage.attachmentID, let actual = actualAttachment(for: node)
        else { return nil }
        let publication = RetainedLazyListLogicalDescriptorPublication(
            attempt: attempt, plan: pending.plan, source: .descriptorBuild(pending.source), actual: actual)
        return recordAcceptedLogicalDeclaration(publication)
    }

    func prepareInsertedNode(from source: ViewNode) -> Bool {
        guard canContinueAdoption, !source.containsRejectedRetainedSource,
            prepareInsertedDescriptor(on: source), ordinaryLedger?.prepareInsertedNode(from: source) != false,
            ownedLedger?.prepareInsertedNode(from: source) != false
        else { return false }
        let storage = source.lazyListActivityStorage()
        let candidates = source.existingRetainedTaskState?.lazyCandidateDeclarations() ?? []
        var facets: [RetainedLazyListSourceFacet] = []
        for output in ownedOutputs(of: source) {
            guard let record = groups[ObjectIdentifier(output.group)] else { return false }
            if record.kind != .scopedTask {
                for keyPath in source.retainedSourcePayloadFields {
                    let facet = output.facet(.nodeProperty(keyPath))
                    output.retirementProperties.insert(facet.nativeField.key)
                }
            }
            for facet in output.facets.values {
                switch facet.nativeField {
                case .childAttachment:
                    facets.append(facet)
                case .nodeProperty:
                    if record.kind == .scopedTask || output.retirementProperties.contains(facet.nativeField.key) {
                        facets.append(facet)
                    }
                case .scopedTaskDeclaration(let declaration):
                    guard
                        candidates.contains(where: {
                            $0.group === output.group && $0.declarations.contains(where: { $0 === declaration })
                        })
                    else { return false }
                    facets.append(facet)
                case .nodeCompletion, .listDescriptor:
                    break
                }
            }
        }
        insertedNodes[ObjectIdentifier(storage.targetID)] = RetainedLazyListPendingInsertedNode(
            node: source, target: storage.targetID, attachment: storage.attachmentID, nativeFacets: facets)
        return true
    }

    @discardableResult
    func recordAcceptedInsertedNode(on node: ViewNode) -> [RetainedLazyListAcceptedTaskGroup] {
        let storage = node.lazyListActivityStorage()
        guard let pending = insertedNodes.removeValue(forKey: ObjectIdentifier(storage.targetID)),
            pending.node === node, pending.target === storage.targetID,
            pending.attachment === storage.attachmentID, let actual = actualAttachment(for: node)
        else { return [] }
        _ = recordAcceptedInsertedDescriptor(on: node)
        recordInsertionPublication(from: node, to: node, actual: actual, inserted: true)
        ownedLedger?.recordAcceptedInsertedNode(
            on: node, ordinaryPublication: { self.usesRegionlessOrdinaryOwnedPublication })
        _ = ordinaryLedger?.recordAcceptedInsertedNode(on: node)
        for facet in pending.nativeFacets { recordAcceptedFacet(facet, actual: actual) }
        // Completion is a separate checked-subtree fact, after attach callbacks.
        return completeGroups()
    }

    func prepareLogicalScopeRemoval(
        expected: RetainedLazyListLogicalMembershipSnapshot,
        actual: RetainedLazyListActualAttachment
    ) -> RetainedLazyListLogicalScopeRemovalPublication? {
        guard canContinueAdoption, actual.isAttached, expected.scope.isCurrent(expected),
            let descriptor = expected.acceptedDescriptor,
            actual.node?.retainedLazyListActivityStorage?.acceptedLogicalDeclaration?.declaration === descriptor
        else { return nil }
        return RetainedLazyListLogicalScopeRemovalPublication(
            attempt: attempt, expected: expected, actual: actual, expectedDescriptor: descriptor)
    }

    @discardableResult
    func recordAcceptedLogicalScopeRemoval(
        _ publication: RetainedLazyListLogicalScopeRemovalPublication
    ) -> RetainedLazyListAcceptedLogicalScopeRemoval? {
        guard publication.attempt === attempt, !publication.wasPublished else { return nil }
        publication.wasPublished = true
        publication.expected.scope.revoke()
        let fact = RetainedLazyListAcceptedLogicalScopeRemoval(
            previous: publication.expectedDescriptor, scope: publication.expected.scope,
            formerList: publication.actual, cleanup: RetainedLazyListCleanupID())
        logicalRemovals.append(fact)
        if let storage = publication.actual.node?.retainedLazyListActivityStorage,
            storage.acceptedLogicalDeclaration?.declaration === publication.expectedDescriptor
        {
            storage.acceptedLogicalDeclaration = nil
        }
        recordCleanupID(fact.cleanup)
        return fact
    }

    func recordAcceptedLogicalScopeRemoval(
        _ publication: RetainedLazyListLogicalScopeRemovalPublication,
        acceptedAbsence: RetainedLazyListAcceptedAbsence
    ) {
        guard recordAcceptedLogicalScopeRemoval(publication) != nil else { return }
        recordAcceptedAbsence(acceptedAbsence)
    }

    func recordAcceptedAbsence(
        _ absence: RetainedLazyListAcceptedAbsence, permitsOriginalCompletion: Bool = false
    ) {
        guard !absences.contains(where: { $0.previous === absence.previous }),
            absence.previous.actualAttachments.contains(where: {
                $0.target === absence.actual.target && $0.attachment === absence.actual.attachment
            })
        else { return }
        if permitsOriginalCompletion { boundDescriptorScope?.recordAcceptedOriginalRetirement(absence.previous) }
        absence.previous.revoke()
        removeRetiredContribution(absence.previous)
        absences.append(absence)
        recordCleanupID(absence.cleanup)
        guard !absence.previous.taskDeclarations.isEmpty else { return }
        var seen: Set<ObjectIdentifier> = []
        for actual in absence.previous.actualAttachments {
            guard let state = actual.node?.existingRetainedTaskState,
                seen.insert(ObjectIdentifier(state)).inserted
            else { continue }
            claimTaskCleanup(
                state.claimLazyAcceptedAbsence(
                    absence, declarationIDs: absence.previous.taskDeclarations))
        }
    }

    private func claimDescriptorTaskAbsence(_ absence: RetainedDescriptorAcceptedAbsence) {
        var declarations: [RetainedTaskDeclarationID] = []
        for facet in absence.previous.acceptedFacets {
            if case .scopedTaskDeclaration(let id) = facet.nativeField,
                !declarations.contains(where: { $0 === id })
            {
                declarations.append(id)
            }
        }
        guard !declarations.isEmpty else { return }
        var seen: Set<ObjectIdentifier> = []
        for actual in absence.previous.actualAttachments {
            guard let state = actual.node?.existingRetainedTaskState,
                seen.insert(ObjectIdentifier(state)).inserted
            else { continue }
            claimTaskCleanup(state.claimDescriptorAcceptedAbsence(absence, declarationIDs: declarations))
        }
    }

    func recordAcceptedDeparture(_ departure: RetainedLazyListAcceptedDeparture) {
        guard !departures.contains(where: { $0.cleanup === departure.cleanup }) else { return }
        for contribution in departure.contributions {
            contribution.revoke()
            removeRetiredContribution(contribution)
        }
        for actual in departure.formerAttachments {
            departure.physical.removeAttachment(target: actual.target, attachment: actual.attachment)
        }
        departures.append(departure)
        recordCleanupID(departure.cleanup)
    }

    func recordPhysicalDeparture(
        of node: ViewNode, cause: RetainedLazyListDepartureCause, retireOwned: Bool = true
    ) -> RetainedLazyListAcceptedDeparture? {
        _ = recordLogicalDescriptorDeparture(of: node, cause: cause)
        if retireOwned {
            ownedLedger?.recordPhysicalDeparture(of: node, cause: cause)
        } else if let snapshot = ownedLedger?.capturePhysicalDeparture(of: node, cause: cause) {
            let key = ObjectIdentifier(node)
            if pendingOwnedDepartures[key]?.contains(where: {
                $0.targetID === snapshot.targetID && $0.attachmentID === snapshot.attachmentID && !$0.wasConsumed
            }) != true {
                snapshot.suspendOwnedWrites()
                pendingOwnedDepartures[key, default: []].append(snapshot)
            }
        }
        return recordNonOwnedPhysicalDeparture(of: node, cause: cause)
    }

    /// The ordinary setter removes old physical output before it publishes
    /// incoming output. Only exact selected normal plans can bridge that gap;
    /// unrelated owners and dropped slots still retire at this boundary.
    func recordOrdinaryPhysicalDeparture(
        of node: ViewNode, cause: RetainedLazyListDepartureCause
    ) -> RetainedOrdinaryOwnedDeparture? {
        guard isOrdinaryAdoption else {
            _ = recordPhysicalDeparture(of: node, cause: cause)
            return nil
        }
        _ = recordLogicalDescriptorDeparture(of: node, cause: cause)
        var ticket: RetainedOrdinaryOwnedDeparture?
        if let ledger = ownedLedger, let original = ledger.capturePhysicalDeparture(of: node, cause: cause) {
            let key = ObjectIdentifier(node)
            let alreadyPending =
                pendingOwnedDepartures[key]?.contains {
                    $0.targetID === original.targetID && $0.attachmentID === original.attachmentID && !$0.wasConsumed
                } == true
            if !alreadyPending {
                if canContinueAdoption, let partition = ledger.partitionOrdinaryDeparture(original) {
                    partition.pending.suspendOwnedWrites()
                    pendingOwnedDepartures[key, default: []].append(partition.pending)
                    ticket = RetainedOrdinaryOwnedDeparture(attempt: attempt, node: key, snapshot: partition.pending)
                    ledger.recordPhysicalDeparture(partition.immediate)
                } else {
                    ledger.recordPhysicalDeparture(original)
                }
            }
        }
        _ = recordNonOwnedPhysicalDeparture(of: node, cause: cause)
        return ticket
    }

    func finishOrdinaryOwnedDeparture(_ ticket: RetainedOrdinaryOwnedDeparture) {
        guard ticket.attempt === attempt, !ticket.snapshot.wasConsumed,
            pendingOwnedDepartures[ticket.node]?.contains(where: { $0 === ticket.snapshot }) == true
        else { return }
        if ownedLedger?.awaitsReplacementDeclaration(ticket.snapshot) == true { return }
        ownedLedger?.recordPhysicalDeparture(ticket.snapshot)
        // Read only the native queue after consumption: another original
        // operation's ticket must not be removed by this operation's cleanup.
        if let current = pendingOwnedDepartures[ticket.node] {
            let remaining = current.filter { $0 !== ticket.snapshot || !$0.wasConsumed }
            pendingOwnedDepartures[ticket.node] = remaining.isEmpty ? nil : remaining
        }
    }

    private func recordNonOwnedPhysicalDeparture(
        of node: ViewNode, cause: RetainedLazyListDepartureCause
    ) -> RetainedLazyListAcceptedDeparture? {
        _ = ordinaryLedger?.recordPhysicalDeparture(of: node)
        guard let storage = node.retainedLazyListActivityStorage, let actual = actualAttachment(for: node) else {
            return nil
        }
        let previous = Array(storage.committedContributions.values)
        var seen: Set<ObjectIdentifier> = []
        var firstDeparture: RetainedLazyListAcceptedDeparture?
        for contribution in previous where seen.insert(ObjectIdentifier(contribution.physical)).inserted {
            let samePhysical = previous.filter { $0.physical === contribution.physical }
            let departure = RetainedLazyListAcceptedDeparture(
                physical: contribution.physical, formerAttachments: [actual], contributions: samePhysical,
                cause: cause, cleanup: RetainedLazyListCleanupID())
            recordAcceptedDeparture(departure)
            if firstDeparture == nil { firstDeparture = departure }
        }
        return firstDeparture
    }

    /// The runtime calls this after the accepted parent declaration table.
    /// Departed writes remain suspended if outgoing callbacks precede that
    /// table. Only the captured old attachment is consumed, never a new one.
    func recordOwnedPhysicalDeparture(of node: ViewNode, cause: RetainedLazyListDepartureCause) {
        let key = ObjectIdentifier(node)
        guard let snapshots = pendingOwnedDepartures[key] else { return }
        for snapshot in snapshots where snapshot.cause == cause && !snapshot.wasConsumed {
            // A final parent table can precede the incoming native attachment
            // publication. Keep the exact continued generation suspended until
            // its new footprint is accepted, or until the journal seals.
            if ownedLedger?.awaitsReplacementDeclaration(snapshot) == true { continue }
            ownedLedger?.recordPhysicalDeparture(snapshot)
        }
        let remaining = snapshots.filter { !$0.wasConsumed }
        pendingOwnedDepartures[key] = remaining.isEmpty ? nil : remaining
    }

    private func finishPendingOwnedDepartures() {
        for snapshots in pendingOwnedDepartures.values {
            for snapshot in snapshots where !snapshot.wasConsumed { ownedLedger?.recordPhysicalDeparture(snapshot) }
        }
        pendingOwnedDepartures.removeAll()
    }

    @discardableResult
    func recordLogicalDescriptorDeparture(
        of node: ViewNode, cause: RetainedLazyListDepartureCause
    ) -> RetainedLazyListAcceptedLogicalScopeRemoval? {
        guard cause != .viewportEviction,
            let previous = node.retainedLazyListActivityStorage?.acceptedLogicalDeclaration,
            let actual = actualAttachment(for: node)
        else { return nil }
        // The caller has accepted this exact structural removal. Its old
        // attachment may already have left parent.children, but native storage
        // and outgoing captures remain pinned until this notification returns.
        let publication = RetainedLazyListLogicalScopeRemovalPublication(
            attempt: attempt, expected: previous.membershipPlan.expected.scope.snapshot(),
            actual: actual, expectedDescriptor: previous.declaration)
        return recordAcceptedLogicalScopeRemoval(publication)
    }

    private func recordCleanupID(_ id: RetainedLazyListCleanupID) {
        if !cleanupIDs.contains(where: { $0 === id }) { cleanupIDs.append(id) }
    }

    func seedExistingRowActivities(_ activities: [RetainedLazyListMaterializedRowActivity]) {
        guard canContinueConstruction else { return }
        for activity in activities where activity.physical.state == .active {
            physicalByMembership[ObjectIdentifier(activity.logicalMembership.id)] = activity.physical
        }
    }

    func prepareEmptyRowContinuation(
        from previous: RetainedLazyListMaterializedRowActivity, to successor: RetainedLazyListMaterializedRowActivity
    ) -> RetainedLazyListEmptyRowContinuation? {
        guard canContinueConstruction, previous !== successor, successor.attempt === attempt,
            previous.request.token == successor.request.token,
            previous.logicalMembership === successor.logicalMembership,
            previous.physical === successor.physical, previous.logicalMembership.isDeclared,
            previous.physical.state == .active, successor.isCurrent,
            componentOrder.contains(where: { $0 === successor.component }), !componentIsRejected(successor.component)
        else { return nil }
        let anchors = previous.physical.actualAttachments
        let contributions = previous.physical.acceptedContributions.filter(\.isActive)
        guard !anchors.isEmpty, anchors.allSatisfy(\.isAttached),
            contributions.allSatisfy({
                $0.acceptedNativeFacets.isEmpty && $0.taskDeclarations.isEmpty
                    && $0.actualAttachments.allSatisfy { actual in
                        anchors.contains { $0.target === actual.target && $0.attachment === actual.attachment }
                    }
            })
        else { return nil }
        var markers: [RetainedOwnedEmptyRowMarker] = []
        for actual in anchors {
            guard let storage = actual.node?.retainedLazyListActivityStorage else { return nil }
            let membership = previous.logicalMembership.id
            let revision = storage.ownedEmptyRowRevisions[ObjectIdentifier(membership)]?.value ?? 0
            guard revision < .max else { return nil }
            let components = storage.ownedEmptyStructuralComponents.filter { _, presence in
                if case .lazy(let logical) = presence.lifetime { return logical === previous.logicalMembership }
                return false
            }
            let permissions = storage.ownedEmptyStructuralPermissions.filter { owner, _ in components[owner] != nil }
            markers.append(
                RetainedOwnedEmptyRowMarker(
                    actual: actual, membership: membership, revision: revision,
                    permissions: permissions, components: components,
                    namespaces: storage.ownedEmptyStructuralNamespaces.filter { owner, _ in components[owner] != nil }))
        }
        return RetainedLazyListEmptyRowContinuation(
            journal: self, previous: previous, successor: successor,
            contributions: contributions, anchors: anchors, markers: markers)
    }

    func prepareEmptyRowHandoff(
        from previous: RetainedLazyListMaterializedRowActivity, to successor: RetainedLazyListMaterializedRowActivity
    ) -> Bool {
        prepareRowReplacementHandoff(from: previous, to: successor)
    }

    /// Reserves the physical lifetime during an accepted attachment exchange.
    /// It grants no node, contribution or task authority while the old and new
    /// actual footprints are disjoint, including a successor with no leaves.
    func prepareRowReplacementHandoff(
        from previous: RetainedLazyListMaterializedRowActivity, to successor: RetainedLazyListMaterializedRowActivity
    ) -> Bool {
        guard canContinueConstruction, previous !== successor, successor.attempt === attempt, successor.isCurrent,
            previous.request.token == successor.request.token,
            previous.logicalMembership === successor.logicalMembership, previous.logicalMembership.isDeclared,
            previous.physical === successor.physical, previous.physical.canBeginRowReplacementHandoff,
            componentOrder.contains(where: { $0 === successor.component }), !componentIsRejected(successor.component)
        else { return false }
        let key = ObjectIdentifier(successor.component)
        if let existing = rowReplacementHandoffs[key] {
            return existing.previous === previous && existing.successor === successor && !existing.wasFinished
        }
        // Implicit dependency and deferred-subtree groups remain open while
        // source outputs are collected. freezePreparation closes them before
        // activation; reserving this handoff grants no mutation permission.
        guard !rowReplacementHandoffs.values.contains(where: { $0.successor.physical === successor.physical })
        else { return false }
        let handoff = RetainedLazyListRowReplacementHandoff(previous: previous, successor: successor)
        guard !handoff.attachments.isEmpty, handoff.attachments.allSatisfy(\.isAttached) else { return false }
        rowReplacementHandoffs[key] = handoff
        return true
    }

    @discardableResult
    func recordAcceptedEmptyRowContinuation(
        _ continuation: RetainedLazyListEmptyRowContinuation, actualNodes: [ViewNode],
        structuralAnchor: RetainedLazyListActualAttachment
    ) -> Bool {
        let activity = continuation.successor
        guard canContinueAdoption, continuation.journal === self, !continuation.wasConsumed,
            activity.attempt === attempt, activity.isCurrent,
            acceptedRowTables[ObjectIdentifier(activity.component)] != nil,
            continuation.previous.logicalMembership === activity.logicalMembership,
            continuation.previous.physical === activity.physical, structuralAnchor.isAttached,
            continuation.anchors.allSatisfy({
                $0.isAttached && $0.target === structuralAnchor.target && $0.attachment === structuralAnchor.attachment
            }),
            continuation.contributions.allSatisfy({
                $0.isActive && $0.physical === activity.physical && $0.acceptedNativeFacets.isEmpty
            }),
            continuation.markers.allSatisfy({ marker in
                guard let storage = marker.actual.node?.retainedLazyListActivityStorage,
                    storage.targetID === marker.actual.target, storage.attachmentID === marker.actual.attachment,
                    (storage.ownedEmptyRowRevisions[ObjectIdentifier(marker.membership)]?.value ?? 0)
                        == marker.revision,
                    marker.revision < .max
                else { return false }
                return marker.components.allSatisfy { owner, presence in
                    storage.ownedEmptyStructuralComponents[owner] === presence
                }
                    && marker.permissions.allSatisfy { owner, permissions in
                        guard let current = storage.ownedEmptyStructuralPermissions[owner] else { return false }
                        return current.count == permissions.count
                            && zip(current, permissions).allSatisfy { $0.0 === $0.1 }
                    }
                    && marker.namespaces.allSatisfy { owner, namespaces in
                        storage.ownedEmptyStructuralNamespaces[owner]?.isSame(as: namespaces) == true
                    }
            })
        else { return false }
        for node in actualNodes {
            guard node.parent === structuralAnchor.node, let actual = actualAttachment(for: node), actual.isAttached,
                activity.physical.actualAttachments.contains(where: {
                    $0.target === actual.target && $0.attachment === actual.attachment
                })
            else { return false }
        }
        continuation.wasConsumed = true
        ownedLedger?.recordAcceptedEmptyRowMarkers(continuation.markers)
        let hasNewEmptyDeclaration = groups.values.contains { record in
            record.attribution.physical === activity.physical && record.isClosed && record.outputs.isEmpty
                && record.kind != .scopedTask && !componentIsRejected(record.attribution.component)
        }
        let hasOtherAnchorContribution = activity.physical.acceptedContributions.contains { receipt in
            receipt.isActive && !continuation.contributions.contains(where: { $0 === receipt })
                && receipt.actualAttachments.contains(where: {
                    $0.target === structuralAnchor.target && $0.attachment === structuralAnchor.attachment
                })
        }
        let dropAnchors = !actualNodes.isEmpty && !hasNewEmptyDeclaration && !hasOtherAnchorContribution
        // The completed row already activated every incoming leaf. Empty rows
        // and pending empty effects retain the container attachment; otherwise
        // dropping that old anchor cannot revoke the shared physical activity.
        recordAcceptedDeparture(
            RetainedLazyListAcceptedDeparture(
                physical: activity.physical, formerAttachments: dropAnchors ? continuation.anchors : [],
                contributions: continuation.contributions, cause: .acceptedReplacement,
                cleanup: RetainedLazyListCleanupID()))
        return activity.physical.state == .active
    }

    @discardableResult
    func recordCompletedOwnedRow(
        _ activity: RetainedLazyListMaterializedRowActivity,
        sources: [ViewNode], actualNodes: [ViewNode],
        structuralAnchor: RetainedLazyListActualAttachment
    ) -> Bool {
        guard canContinueAdoption, activity.attempt === attempt, sources.count == actualNodes.count,
            componentOrder.contains(where: { $0 === activity.component }),
            !componentIsRejected(activity.component), structuralAnchor.isAttached,
            activity.logicalMembership.isDeclared
        else { return false }
        let components = Set(
            componentOrder.filter {
                !componentIsRejected($0) && isDescendant($0, of: activity.component)
            }.map { ObjectIdentifier($0) })
        guard ownedLedger?.canCompleteRow(activity, components: components, anchor: structuralAnchor) != false else {
            return false
        }
        let actuals = actualNodes.isEmpty ? [structuralAnchor] : actualNodes.compactMap { actualAttachment(for: $0) }
        guard actuals.count == (actualNodes.isEmpty ? 1 : actualNodes.count), actuals.allSatisfy(\.isAttached) else {
            return false
        }
        let previousAttachments = activity.physical.actualAttachments
        for actual in actuals {
            guard activity.physical.activate(on: actual) else { return false }
        }
        guard
            ownedLedger?.recordCompletedRow(
                activity, components: components, anchor: structuralAnchor) != false
        else {
            for actual in activity.physical.actualAttachments
            where !previousAttachments.contains(where: {
                $0.target === actual.target && $0.attachment === actual.attachment
            }) {
                activity.physical.removeAttachment(target: actual.target, attachment: actual.attachment)
            }
            return false
        }
        acceptedRowTables[ObjectIdentifier(activity.component)] = activity.logicalMembership.id
        if case .selectedRows(let admission) = origin { admission.recordCompletedInsertionRow(activity) }
        rowReplacementHandoffs[ObjectIdentifier(activity.component)]?.finish()
        boundDescriptorScope?.recordAcceptedDescriptor()
        return true
    }

    @discardableResult
    func recordAcceptedEmptyRowDeparture(
        _ activity: RetainedLazyListMaterializedRowActivity,
        cause: RetainedLazyListDepartureCause
    ) -> RetainedLazyListAcceptedDeparture {
        let contributions = activity.physical.acceptedContributions
        let actuals = activity.physical.actualAttachments
        let departure = RetainedLazyListAcceptedDeparture(
            physical: activity.physical, formerAttachments: actuals, contributions: contributions,
            cause: cause, cleanup: RetainedLazyListCleanupID())
        recordAcceptedDeparture(departure)
        activity.physical.revoke()
        ownedLedger?.recordEmptyRowDeparture(activity, anchors: actuals)
        return departure
    }

    private func removeRetiredContribution(_ receipt: RetainedLazyListContributionReceipt) {
        for actual in receipt.actualAttachments {
            guard let storage = actual.node?.retainedLazyListActivityStorage,
                storage.committedContributions[ObjectIdentifier(receipt.group)] === receipt
            else { continue }
            storage.committedContributions.removeValue(forKey: ObjectIdentifier(receipt.group))
            if storage.deferredSubtreeAnchor?.contribution === receipt { storage.deferredSubtreeAnchor = nil }
        }
    }

    func claimTaskCleanup(_ cleanup: RetainedLazyListAcceptedTaskCleanup) {
        recordCleanupID(cleanup.id)
        taskCleanup.appendClaimed(cleanup)
    }

    func finishAcceptedTaskCleanup() {
        transaction.perform { taskCleanup.finishClaimed() }
    }

    func revokeBeforeAbandon() {
        finishPendingOwnedDepartures()
        ownedLedger?.finishPendingDeclaredMarkerRetirements()
        finishRowReplacementHandoffs()
        guard !hasAcceptedContributions, !didMutate else { return }
        wasRevoked = true
        boundDescriptorScope?.revoke()
        for preparation in preparations.values { preparation.revoke() }
    }

    func seal(completedCheckedAdoption: Bool = false) -> RetainedLazyListAdoptionDisposition {
        if let sealedDisposition { return sealedDisposition }
        let complete = completedCheckedAdoption && canContinueAdoption
        finishPendingOwnedDepartures()
        ownedLedger?.finishPendingDeclaredMarkerRetirements()
        finishRowReplacementHandoffs()
        let ordinary = ordinaryLedger?.seal()
        for cleanup in ordinary?.cleanup ?? [] { recordCleanupID(cleanup) }
        var partial: [RetainedLazyListPartialGroup] = []
        var unadopted: [RetainedLazyListGroupID] = []
        for id in groupOrder where !completedGroupIDs.contains(ObjectIdentifier(id)) {
            guard let record = groups[ObjectIdentifier(id)] else { continue }
            let accepted = acceptedFacetFacts.filter { $0.source.group === id }
            if accepted.isEmpty {
                unadopted.append(id)
            } else {
                partial.append(
                    RetainedLazyListPartialGroup(
                        proposal: record.proposal, acceptedFacets: accepted,
                        unacceptedFacets: record.required.filter { acceptedFacetByID[ObjectIdentifier($0.id)] == nil }
                            .map(\.id)))
            }
        }
        let stop: RetainedLazyListAdoptionStop =
            !hasAcceptedContributions ? .noAcceptance : (complete ? .completedCheckedAdoption : .stoppedAfterAcceptance)
        let disposition = RetainedLazyListAdoptionDisposition(
            attempt: attempt, stop: stop, acceptedRowMemberships: Array(acceptedRowTables.values),
            acceptedLogicalDeclarations: logicalDeclarations,
            acceptedLogicalRemovals: logicalRemovals,
            acceptedFacets: acceptedFacetFacts, acceptedGroups: completedGroups,
            partialGroups: partial, acceptedEmptyGroups: emptyGroups, unchanged: unchanged,
            acceptedAbsences: absences, acceptedDepartures: departures, unadoptedGroups: unadopted,
            acceptedCleanup: cleanupIDs, ordinary: ordinary, owned: ownedLedger)
        phase = .sealed
        boundDescriptorScope?.beginFinishing()
        sealedDisposition = disposition
        return disposition
    }

    @inline(never)
    func releaseUnadoptedTransport() {
        // Only native metadata is owned here; source nodes and task declarations
        // stay weak. Revoke construction before the caller releases its candidate.
        if phase != .sealed { _ = seal() }
        transaction.perform {
            for preparation in preparations.values { preparation.revoke() }
            preparations.removeAll()
            insertedDescriptors.removeAll()
            insertedNodes.removeAll()
            for record in groups.values {
                for output in record.outputs {
                    output.node?.retainedLazyListActivityStorage?.sourceOutputs.removeAll { $0 === output }
                }
            }
            for descriptor in descriptorSources.values {
                if let storage = descriptor.sourceNode?.retainedLazyListActivityStorage,
                    storage.sourceDescriptor?.facet === descriptor.facet
                {
                    storage.sourceDescriptor = nil
                }
            }
            groups.removeAll()
            componentParents.removeAll()
            componentOrder.removeAll()
            materializedRoots.removeAll()
            propertyCopies.removeAll()
            rejectedComponents.removeAll()
            descriptorSources.removeAll()
            existingLogicalDeclarations.removeAll()
            ordinaryLedger?.releaseUnadoptedTransport()
            ownedLedger?.finish()
            phase = .finished
        }
    }
}

package final class RetainedDescriptorComponentID: Sendable { init() {} }
package final class RetainedDescriptorGroupID: Sendable { init() {} }

@MainActor
package struct RetainedDescriptorComponentProposal {
    package let attempt: RetainedLazyListAttemptID
    package let component: RetainedDescriptorComponentID
    package let parent: RetainedDescriptorComponentID?
    package let groups: [RetainedDescriptorGroupProposal]
}

@MainActor
package struct RetainedDescriptorGroupProposal {
    package let attempt: RetainedLazyListAttemptID
    package let component: RetainedDescriptorComponentID
    package let group: RetainedDescriptorGroupID
    package let kind: RetainedLazyListContributionKind
    package let construction: RetainedLazyListGroupConstruction
    package let requiredFacets: [RetainedLazyListSourceFacetID]
}

@MainActor
package struct RetainedDescriptorAcceptedFacet {
    package let component: RetainedDescriptorComponentID
    package let group: RetainedDescriptorGroupID
    package let source: RetainedLazyListSourcePayloadID
    package let facet: RetainedLazyListSourceFacetID
    package let actual: RetainedLazyListActualAttachment
    let nativeField: RetainedLazyListNativeFacet
}

@MainActor
package struct RetainedDescriptorAcceptedGroup {
    package let proposal: RetainedDescriptorGroupProposal
    package let acceptedFacets: [RetainedDescriptorAcceptedFacet]
    package let receipt: RetainedDescriptorContributionReceipt
}

@MainActor
package struct RetainedDescriptorPartialGroup {
    package let proposal: RetainedDescriptorGroupProposal
    package let acceptedFacets: [RetainedDescriptorAcceptedFacet]
    package let unacceptedFacets: [RetainedLazyListSourceFacetID]
}

@MainActor
package struct RetainedDescriptorAcceptedEmptyGroup {
    package let proposal: RetainedDescriptorGroupProposal
    package let structuralAnchor: RetainedLazyListActualAttachment
    package let receipt: RetainedDescriptorContributionReceipt
}

@MainActor
package struct RetainedDescriptorExistingContribution {
    package let receipt: RetainedDescriptorContributionReceipt
    package let actualAttachments: [RetainedLazyListActualAttachment]
}

@MainActor
package struct RetainedDescriptorAcceptedAbsence {
    package let previous: RetainedDescriptorContributionReceipt
    package let actual: RetainedLazyListActualAttachment
    package let removalFacets: [RetainedLazyListSourceFacetID]
    package let cleanup: RetainedLazyListCleanupID
}

/// Ordinary activity has no row or logical membership. Build completion does not
/// revoke a contribution; owner closure and exact footprint removal do.
@MainActor
package final class RetainedDescriptorContributionReceipt {
    package let id = RetainedLazyListContributionID()
    package let group: RetainedDescriptorGroupID
    private weak var hostLifetime: RetainedLazyListLogicalHostLifetime?
    private let ownerLifetime: RetainedLazyListDescriptorOwnerLifetime
    private var wasRevoked = false
    private var didAccept = false
    fileprivate var nativeHostLifetime: RetainedLazyListLogicalHostLifetime? { hostLifetime }
    fileprivate var nativeOwnerLifetime: RetainedLazyListDescriptorOwnerLifetime { ownerLifetime }
    fileprivate private(set) var actualAttachments: [RetainedLazyListActualAttachment] = []
    fileprivate private(set) var acceptedFacets: [RetainedDescriptorAcceptedFacet] = []

    init(
        group: RetainedDescriptorGroupID,
        hostLifetime: RetainedLazyListLogicalHostLifetime,
        ownerLifetime: RetainedLazyListDescriptorOwnerLifetime
    ) {
        self.group = group
        self.hostLifetime = hostLifetime
        self.ownerLifetime = ownerLifetime
    }

    package var isActive: Bool {
        var query = RetainedLazyListAttachmentQuery()
        return isActive(using: &query)
    }

    func isActive(using query: inout RetainedLazyListAttachmentQuery) -> Bool {
        !wasRevoked && didAccept && hostLifetime?.isOpen == true && ownerLifetime.isCurrent
            && !actualAttachments.isEmpty && actualAttachments.allSatisfy { $0.isAttached(using: &query) }
    }

    @discardableResult
    fileprivate func activate(
        on actual: [RetainedLazyListActualAttachment],
        facets: [RetainedDescriptorAcceptedFacet]
    ) -> Bool {
        guard !wasRevoked, hostLifetime?.isOpen == true, ownerLifetime.isCurrent,
            !actual.isEmpty, actual.allSatisfy(\.isAttached)
        else { return false }
        actualAttachments = actual
        acceptedFacets = facets
        didAccept = true
        return true
    }

    func hasSameOwnerLifetime(as other: RetainedDescriptorContributionReceipt) -> Bool {
        guard let hostLifetime, let otherHost = other.hostLifetime else { return false }
        return hostLifetime === otherHost && ownerLifetime === other.ownerLifetime
    }

    func revoke() { wasRevoked = true }
}

/// Shares native ancestry work only within one synchronous, callback-free
/// authorization. No permission result is cached. The query must end before
/// a callback, registration, publication, cleanup, or subsequent operation.
@MainActor
package struct RetainedDescriptorAttachmentQuery {
    fileprivate var attachments = RetainedLazyListAttachmentQuery()
    package private(set) var authorizationChecks = 0

    package init() {}

    package var ancestorVisits: Int { attachments.ancestorVisits }
    package var childLinkVisits: Int { attachments.childLinkVisits }

    fileprivate mutating func recordAuthorizationCheck() { authorizationChecks += 1 }
}

@MainActor
package final class RetainedDescriptorComponentAttribution {
    package let attempt: RetainedLazyListAttemptID
    package let descriptorBuildAttempt: RetainedLazyListAttemptID
    package var descriptorBuildAttemptID: RetainedLazyListAttemptID { descriptorBuildAttempt }
    package let component: RetainedDescriptorComponentID
    fileprivate weak var ledger: RetainedDescriptorConstructionLedger?
    fileprivate weak var scope: RetainedLazyListDescriptorBuildScope?
    fileprivate var descriptorScope: RetainedLazyListDescriptorBuildScope? { scope }

    fileprivate init(
        attempt: RetainedLazyListAttemptID,
        component: RetainedDescriptorComponentID,
        ledger: RetainedDescriptorConstructionLedger,
        scope: RetainedLazyListDescriptorBuildScope
    ) {
        self.attempt = attempt
        descriptorBuildAttempt = scope.attempt
        self.component = component
        self.ledger = ledger
        self.scope = scope
    }

    package var canConstruct: Bool { ledger?.canConstruct(self) == true }

    package func canConstruct(using query: inout RetainedDescriptorAttachmentQuery) -> Bool {
        query.recordAuthorizationCheck()
        return ledger?.canConstruct(self, using: &query) == true
    }

    package func rejectComponent() { ledger?.rejectComponent(self) }
    package func rejectConstruction() { rejectComponent() }

    package func registerChildComponent() -> RetainedDescriptorComponentAttribution? {
        ledger?.registerChild(from: self)
    }

    package func registerGroup(kind: RetainedLazyListContributionKind) -> RetainedDescriptorGroupID? {
        ledger?.registerGroup(in: self, kind: kind)
    }

    @discardableResult
    package func recordSourceOutput(_ source: ViewNode, group: RetainedDescriptorGroupID) -> Bool {
        ledger?.recordSourceOutput(source, attribution: self, group: group) == true
    }

    @discardableResult
    package func closeGroup(_ group: RetainedDescriptorGroupID) -> RetainedDescriptorGroupProposal? {
        ledger?.closeGroup(group, attribution: self)
    }

    package func contribution(for group: RetainedDescriptorGroupID) -> RetainedDescriptorContributionReceipt? {
        ledger?.contribution(for: group, attribution: self)
    }

    @discardableResult
    package func registerTaskDeclaration(_ declaration: RetainedTaskDeclarationID, group: RetainedDescriptorGroupID)
        -> Bool
    {
        ledger?.registerTaskDeclaration(declaration, group: group, attribution: self) == true
    }

    package func recordTaskSourceOutput(
        _ source: ViewNode, group: RetainedDescriptorGroupID
    ) -> RetainedLazyListSourcePayloadID? {
        ledger?.recordTaskSourceOutput(source, attribution: self, group: group)
    }
}

@MainActor
struct RetainedDescriptorAcceptedTaskGroup {
    let contribution: RetainedDescriptorAcceptedGroup
    let declarationIDs: [RetainedTaskDeclarationID]
    let members: [RetainedLazyListAcceptedTaskMember]
}

@MainActor
private struct RetainedDescriptorSourceFacet {
    let id = RetainedLazyListSourceFacetID()
    let component: RetainedDescriptorComponentID
    let group: RetainedDescriptorGroupID
    let source: RetainedLazyListSourcePayloadID
    let nativeField: RetainedLazyListNativeFacet
}

@MainActor
fileprivate final class RetainedDescriptorSourceOutput {
    weak var node: ViewNode?
    let component: RetainedDescriptorComponentID
    let group: RetainedDescriptorGroupID
    let constructionComponent: RetainedDescriptorComponentID
    let payload = RetainedLazyListSourcePayloadID()
    fileprivate var facets: [RetainedLazyListFacetKey: RetainedDescriptorSourceFacet] = [:]
    fileprivate var retirementProperties: Set<RetainedLazyListFacetKey> = []

    init(
        node: ViewNode, component: RetainedDescriptorComponentID, group: RetainedDescriptorGroupID,
        constructionComponent: RetainedDescriptorComponentID
    ) {
        self.node = node
        self.component = component
        self.group = group
        self.constructionComponent = constructionComponent
    }

    fileprivate func facet(_ field: RetainedLazyListNativeFacet) -> RetainedDescriptorSourceFacet {
        if let facet = facets[field.key] { return facet }
        let facet = RetainedDescriptorSourceFacet(
            component: component, group: group, source: payload, nativeField: field)
        facets[field.key] = facet
        return facet
    }
}

@MainActor
private final class RetainedDescriptorComponentRecord {
    let id: RetainedDescriptorComponentID
    let parent: RetainedDescriptorComponentID?
    weak var scope: RetainedLazyListDescriptorBuildScope?
    var groups: [RetainedDescriptorGroupID] = []

    init(
        id: RetainedDescriptorComponentID, parent: RetainedDescriptorComponentID?,
        scope: RetainedLazyListDescriptorBuildScope
    ) {
        self.id = id
        self.parent = parent
        self.scope = scope
    }
}

@MainActor
private final class RetainedDescriptorGroupRecord {
    let attempt: RetainedLazyListAttemptID
    let component: RetainedDescriptorComponentID
    let id: RetainedDescriptorGroupID
    let kind: RetainedLazyListContributionKind
    let receipt: RetainedDescriptorContributionReceipt
    var outputs: [RetainedDescriptorSourceOutput] = []
    var required: [RetainedDescriptorSourceFacet] = []
    var declarations: [RetainedTaskDeclarationID] = []
    var isClosed = false

    init(
        attempt: RetainedLazyListAttemptID, component: RetainedDescriptorComponentID,
        kind: RetainedLazyListContributionKind,
        hostLifetime: RetainedLazyListLogicalHostLifetime,
        ownerLifetime: RetainedLazyListDescriptorOwnerLifetime
    ) {
        let group = RetainedDescriptorGroupID()
        self.attempt = attempt
        self.component = component
        id = group
        self.kind = kind
        receipt = RetainedDescriptorContributionReceipt(
            group: group, hostLifetime: hostLifetime, ownerLifetime: ownerLifetime)
    }

    var proposal: RetainedDescriptorGroupProposal {
        RetainedDescriptorGroupProposal(
            attempt: attempt, component: component, group: id, kind: kind,
            construction: isClosed ? (outputs.isEmpty ? .closedEmpty : .closedWithFacets) : .open,
            requiredFacets: required.map(\.id))
    }

    func require(_ facet: RetainedDescriptorSourceFacet) {
        if !required.contains(where: { $0.id === facet.id }) { required.append(facet) }
    }
}

private struct RetainedDescriptorPropertyCopyKey: Hashable {
    let source: ObjectIdentifier
    let target: ObjectIdentifier
    let field: AnyKeyPath
}

@MainActor
private struct RetainedDescriptorPendingPropertyCopy {
    weak var source: ViewNode?
    weak var target: ViewNode?
    let targetID: RetainedLazyListTargetID
    let attachmentID: RetainedLazyListAttachmentID
    let facets: [RetainedDescriptorSourceFacet]
    let previous: [RetainedDescriptorContributionReceipt]
}

@MainActor
private struct RetainedDescriptorPendingInsertion {
    weak var node: ViewNode?
    let target: RetainedLazyListTargetID
    let attachment: RetainedLazyListAttachmentID
    let facets: [RetainedDescriptorSourceFacet]
}

@MainActor
struct RetainedDescriptorSealedActivity {
    let acceptedFacets: [RetainedDescriptorAcceptedFacet]
    let acceptedGroups: [RetainedDescriptorAcceptedGroup]
    let partialGroups: [RetainedDescriptorPartialGroup]
    let acceptedEmptyGroups: [RetainedDescriptorAcceptedEmptyGroup]
    let unchanged: [RetainedDescriptorExistingContribution]
    let absences: [RetainedDescriptorAcceptedAbsence]
    let cleanup: [RetainedLazyListCleanupID]
}

/// Scope-owned during construction, journal-owned during adoption. All retained
/// source references are weak; lookup keys are native allocation identities.
@MainActor
final class RetainedDescriptorConstructionLedger {
    let attempt: RetainedLazyListAttemptID
    private weak var hostLifetime: RetainedLazyListLogicalHostLifetime?
    private let ownerLifetime: RetainedLazyListDescriptorOwnerLifetime
    private var componentOrder: [RetainedDescriptorComponentID] = []
    private var components: [ObjectIdentifier: RetainedDescriptorComponentRecord] = [:]
    private var groupOrder: [RetainedDescriptorGroupID] = []
    private var groups: [ObjectIdentifier: RetainedDescriptorGroupRecord] = [:]
    private var isFrozen = false
    private var sealed: RetainedDescriptorSealedActivity?
    private var preparedComponents: [RetainedDescriptorComponentProposal]?
    private var propertyCopies: [RetainedDescriptorPropertyCopyKey: RetainedDescriptorPendingPropertyCopy] = [:]
    private var insertions: [ObjectIdentifier: RetainedDescriptorPendingInsertion] = [:]
    private var acceptedByFacet: [ObjectIdentifier: RetainedDescriptorAcceptedFacet] = [:]
    private var completedIDs: Set<ObjectIdentifier> = []
    private var invalidIDs: Set<ObjectIdentifier> = []
    private var rejectedComponentIDs: Set<ObjectIdentifier> = []
    private var absentIDs: Set<ObjectIdentifier> = []
    private var acceptedTaskGroups: [RetainedDescriptorAcceptedTaskGroup] = []
    private var propertyAbsences: [RetainedDescriptorAcceptedAbsence] = []
    private(set) var hasUnsupportedTaskDeclarations = false
    private(set) var expectedExisting: [RetainedDescriptorExistingContribution] = []
    private(set) var acceptedFacets: [RetainedDescriptorAcceptedFacet] = []
    private(set) var acceptedGroups: [RetainedDescriptorAcceptedGroup] = []
    private(set) var acceptedEmptyGroups: [RetainedDescriptorAcceptedEmptyGroup] = []
    private(set) var unchanged: [RetainedDescriptorExistingContribution] = []
    private(set) var absences: [RetainedDescriptorAcceptedAbsence] = []
    private(set) var cleanup: [RetainedLazyListCleanupID] = []

    init(
        attempt: RetainedLazyListAttemptID,
        hostLifetime: RetainedLazyListLogicalHostLifetime,
        ownerLifetime: RetainedLazyListDescriptorOwnerLifetime
    ) {
        self.attempt = attempt
        self.hostLifetime = hostLifetime
        self.ownerLifetime = ownerLifetime
    }

    var hasContributions: Bool { !groupOrder.isEmpty || !expectedExisting.isEmpty }
    var hasAcceptedContributions: Bool {
        !acceptedFacets.isEmpty || !acceptedEmptyGroups.isEmpty || !absences.isEmpty
    }

    fileprivate func canConstruct(_ attribution: RetainedDescriptorComponentAttribution) -> Bool {
        var query = RetainedDescriptorAttachmentQuery()
        return canConstruct(attribution, using: &query)
    }

    fileprivate func canConstruct(
        _ attribution: RetainedDescriptorComponentAttribution, using query: inout RetainedDescriptorAttachmentQuery
    ) -> Bool {
        guard sealed == nil, attribution.ledger === self,
            attribution.attempt === attempt, !rejectedComponentIDs.contains(ObjectIdentifier(attribution.component)),
            let scope = attribution.scope,
            let record = components[ObjectIdentifier(attribution.component)]
        else { return false }
        return record.id === attribution.component && record.scope === scope
            && scope.attempt === attempt && scope.canConstructDescriptors(using: &query.attachments)
    }

    fileprivate func parentComponent(of id: RetainedDescriptorComponentID) -> RetainedDescriptorComponentID? {
        components[ObjectIdentifier(id)]?.parent
    }

    fileprivate func isRejected(_ component: RetainedDescriptorComponentID) -> Bool {
        rejectedComponentIDs.contains(ObjectIdentifier(component))
    }

    fileprivate func sourceOutputs(for component: RetainedDescriptorComponentID) -> [RetainedDescriptorSourceOutput] {
        guard let record = components[ObjectIdentifier(component)] else { return [] }
        return record.groups.flatMap { groups[ObjectIdentifier($0)]?.outputs ?? [] }
    }

    fileprivate func rejectComponent(_ attribution: RetainedDescriptorComponentAttribution) {
        guard sealed == nil, attribution.scope?.canConstructDescriptors == true,
            attribution.ledger === self, attribution.attempt === attempt,
            components[ObjectIdentifier(attribution.component)] != nil
        else { return }
        rejectedComponentIDs.insert(ObjectIdentifier(attribution.component))
        // Components are registered in parent-before-child order. A single
        // scalar pass rejects the already declared descendants without callbacks.
        for id in componentOrder {
            guard let parent = components[ObjectIdentifier(id)]?.parent,
                rejectedComponentIDs.contains(ObjectIdentifier(parent))
            else { continue }
            rejectedComponentIDs.insert(ObjectIdentifier(id))
        }
        for record in groups.values {
            let rejected = record.outputs.filter {
                rejectedComponentIDs.contains(ObjectIdentifier($0.constructionComponent))
            }
            for output in rejected { output.node?.markRejectedRetainedSource() }
            guard !isFrozen else { continue }
            let payloads = Set(rejected.map { ObjectIdentifier($0.payload) })
            record.outputs.removeAll { payloads.contains(ObjectIdentifier($0.payload)) }
            record.required.removeAll { payloads.contains(ObjectIdentifier($0.source)) }
        }
    }

    func registerRoot(in scope: RetainedLazyListDescriptorBuildScope) -> RetainedDescriptorComponentAttribution? {
        guard !isFrozen, sealed == nil, scope.attempt === attempt, scope.canConstructDescriptors,
            hostLifetime?.isOpen == true, ownerLifetime.isCurrent
        else { return nil }
        return registerComponent(parent: nil, scope: scope)
    }

    func registerChild(from parent: RetainedDescriptorComponentAttribution) -> RetainedDescriptorComponentAttribution? {
        guard !isFrozen, canConstruct(parent), let scope = parent.scope else { return nil }
        return registerComponent(parent: parent.component, scope: scope)
    }

    private func registerComponent(
        parent: RetainedDescriptorComponentID?, scope: RetainedLazyListDescriptorBuildScope
    ) -> RetainedDescriptorComponentAttribution {
        let component = RetainedDescriptorComponentID()
        components[ObjectIdentifier(component)] = RetainedDescriptorComponentRecord(
            id: component, parent: parent, scope: scope)
        componentOrder.append(component)
        return RetainedDescriptorComponentAttribution(
            attempt: attempt, component: component, ledger: self, scope: scope)
    }

    fileprivate func registerGroup(
        in attribution: RetainedDescriptorComponentAttribution, kind: RetainedLazyListContributionKind
    ) -> RetainedDescriptorGroupID? {
        guard !isFrozen, canConstruct(attribution), let scope = attribution.descriptorScope,
            let hostLifetime = scope.nativeHostLifetime
        else { return nil }
        let record = RetainedDescriptorGroupRecord(
            attempt: attempt, component: attribution.component, kind: kind,
            hostLifetime: hostLifetime, ownerLifetime: scope.nativeOwnerLifetime)
        groups[ObjectIdentifier(record.id)] = record
        groupOrder.append(record.id)
        components[ObjectIdentifier(attribution.component)]?.groups.append(record.id)
        return record.id
    }

    fileprivate func registerTaskDeclaration(
        _ declaration: RetainedTaskDeclarationID, group: RetainedDescriptorGroupID,
        attribution: RetainedDescriptorComponentAttribution
    ) -> Bool {
        guard !isFrozen, canConstruct(attribution), let record = groups[ObjectIdentifier(group)],
            record.component === attribution.component, record.kind == .scopedTask, !record.isClosed
        else { return false }
        if !record.declarations.contains(where: { $0 === declaration }) {
            record.declarations.append(declaration)
            for output in record.outputs { record.require(output.facet(.scopedTaskDeclaration(declaration))) }
        }
        return true
    }

    fileprivate func recordTaskSourceOutput(
        _ source: ViewNode, attribution: RetainedDescriptorComponentAttribution,
        group: RetainedDescriptorGroupID
    ) -> RetainedLazyListSourcePayloadID? {
        guard let record = groups[ObjectIdentifier(group)], record.kind == .scopedTask,
            recordSourceOutput(source, attribution: attribution, group: group)
        else { return nil }
        return record.outputs.first(where: { $0.node === source })?.payload
    }

    fileprivate func contribution(
        for group: RetainedDescriptorGroupID, attribution: RetainedDescriptorComponentAttribution
    ) -> RetainedDescriptorContributionReceipt? {
        guard attribution.ledger === self, attribution.attempt === attempt,
            let record = groups[ObjectIdentifier(group)], record.component === attribution.component
        else { return nil }
        return record.receipt
    }

    fileprivate func recordSourceOutput(
        _ source: ViewNode, attribution: RetainedDescriptorComponentAttribution,
        group: RetainedDescriptorGroupID
    ) -> Bool {
        guard !isFrozen, canConstruct(attribution), !source.containsRejectedRetainedSource,
            let record = groups[ObjectIdentifier(group)],
            record.component === attribution.component, !record.isClosed
        else { return false }
        addOutput(source, to: record, constructedBy: attribution.component)
        // The component ancestry is already declared. Propagate the same native
        // source to open enclosing groups, never by authored identity or prefix.
        var ancestor: RetainedDescriptorComponentID? = attribution.component
        while let id = ancestor, let component = components[ObjectIdentifier(id)] {
            for ancestorGroup in component.groups {
                guard let enclosing = groups[ObjectIdentifier(ancestorGroup)], !enclosing.isClosed,
                    enclosing.id !== group, enclosing.kind != .scopedTask
                else { continue }
                addOutput(source, to: enclosing, constructedBy: attribution.component)
            }
            ancestor = component.parent
        }
        return true
    }

    private func addOutput(
        _ source: ViewNode, to record: RetainedDescriptorGroupRecord,
        constructedBy component: RetainedDescriptorComponentID
    ) {
        guard !record.outputs.contains(where: { $0.node === source }) else { return }
        let output = RetainedDescriptorSourceOutput(
            node: source, component: record.component, group: record.id, constructionComponent: component)
        record.outputs.append(output)
        record.require(output.facet(.childAttachment))
        if record.kind == .scopedTask {
            // Only explicitly staged task members enter a cohort. Descendant
            // source propagation must not invent additional task leaves.
            record.require(output.facet(.nodeProperty(\ViewNode.onAppearWithNode)))
            record.require(output.facet(.nodeProperty(\ViewNode.onDisappearWithNode)))
            for declaration in record.declarations {
                record.require(output.facet(.scopedTaskDeclaration(declaration)))
            }
        } else {
            record.require(output.facet(.nodeCompletion))
        }
        source.lazyListActivityStorage().descriptorOutputs.append(output)
    }

    fileprivate func closeGroup(
        _ group: RetainedDescriptorGroupID, attribution: RetainedDescriptorComponentAttribution
    ) -> RetainedDescriptorGroupProposal? {
        guard attribution.ledger === self, attribution.attempt === attempt,
            let record = groups[ObjectIdentifier(group)], record.component === attribution.component
        else { return nil }
        if !isFrozen { record.isClosed = true }
        return record.proposal
    }

    func freeze() -> [RetainedDescriptorComponentProposal] {
        if let preparedComponents { return preparedComponents }
        for record in groups.values {
            record.isClosed = true
            if record.kind == .scopedTask, !record.outputs.isEmpty, record.declarations.isEmpty {
                hasUnsupportedTaskDeclarations = true
            }
        }
        isFrozen = true
        let result = componentOrder.compactMap { id -> RetainedDescriptorComponentProposal? in
            guard let component = components[ObjectIdentifier(id)] else { return nil }
            return RetainedDescriptorComponentProposal(
                attempt: attempt, component: component.id, parent: component.parent,
                groups: component.groups.compactMap { groups[ObjectIdentifier($0)]?.proposal })
        }
        preparedComponents = result
        return result
    }

    private func actualAttachment(for node: ViewNode) -> RetainedLazyListActualAttachment? {
        guard let runtime = node.retainedLazyListRuntime else { return nil }
        let actual = node.lazyListActivityStorage().captureActualAttachment(of: node, in: runtime)
        return actual.isAttached ? actual : nil
    }

    private func ownedOutputs(of source: ViewNode) -> [RetainedDescriptorSourceOutput]? {
        guard !source.containsRejectedRetainedSource else { return nil }
        let outputs =
            source.retainedLazyListActivityStorage?.descriptorOutputs.filter { output in
                output.node === source
                    && groups[ObjectIdentifier(output.group)]?.outputs.contains(where: { $0 === output }) == true
            } ?? []
        guard
            outputs.allSatisfy({ output in
                output.node === source && !rejectedComponentIDs.contains(ObjectIdentifier(output.component))
                    && groups[ObjectIdentifier(output.group)]?.outputs.contains(where: { $0 === output }) == true
            })
        else { return nil }
        return outputs
    }

    private func canPrepare(_ outputs: [RetainedDescriptorSourceOutput]) -> Bool {
        guard isFrozen, sealed == nil, !hasUnsupportedTaskDeclarations,
            hostLifetime?.isOpen == true, ownerLifetime.isCurrent
        else { return false }
        return outputs.allSatisfy {
            !rejectedComponentIDs.contains(ObjectIdentifier($0.component))
                && components[ObjectIdentifier($0.component)]?.scope?.canPublishDescriptors == true
        }
    }

    func preparePropertyCopy(from source: ViewNode, to target: ViewNode, keyPath: PartialKeyPath<ViewNode>) -> Bool {
        guard let outputs = ownedOutputs(of: source), canPrepare(outputs),
            let actual = actualAttachment(for: target)
        else { return false }
        let key = RetainedDescriptorPropertyCopyKey(
            source: ObjectIdentifier(source), target: ObjectIdentifier(target), field: keyPath)
        guard propertyCopies[key] == nil else { return false }
        let nativeKey = RetainedLazyListNativeFacet.nodeProperty(keyPath).key
        let incoming = outputs.compactMap { groups[ObjectIdentifier($0.group)]?.receipt }
        let hasPayload = source.retainedSourcePayloadFields.contains(keyPath)
        for output in outputs where hasPayload { output.retirementProperties.insert(nativeKey) }
        let previous =
            target.retainedLazyListActivityStorage?.committedDescriptorContributions.values.filter { receipt in
                !incoming.contains(where: { $0 === receipt })
                    && receipt.acceptedFacets.contains {
                        $0.nativeField.key == nativeKey && $0.actual.target === actual.target
                            && $0.actual.attachment === actual.attachment
                    }
            } ?? []
        propertyCopies[key] = RetainedDescriptorPendingPropertyCopy(
            source: source, target: target, targetID: actual.target, attachmentID: actual.attachment,
            facets: outputs.map { $0.facet(.nodeProperty(keyPath)) }, previous: Array(previous))
        return true
    }

    @discardableResult
    func recordAcceptedProperty(
        from source: ViewNode, to target: ViewNode, keyPath: PartialKeyPath<ViewNode>
    ) -> [RetainedDescriptorAcceptedGroup] {
        let key = RetainedDescriptorPropertyCopyKey(
            source: ObjectIdentifier(source), target: ObjectIdentifier(target), field: keyPath)
        guard let pending = propertyCopies.removeValue(forKey: key),
            pending.source === source, pending.target === target,
            let storage = target.retainedLazyListActivityStorage,
            storage.targetID === pending.targetID, storage.attachmentID === pending.attachmentID,
            let actual = actualAttachment(for: target)
        else { return [] }
        let nativeKey = RetainedLazyListNativeFacet.nodeProperty(keyPath).key
        for previous in pending.previous {
            let removed = previous.acceptedFacets.filter {
                $0.nativeField.key == nativeKey && $0.actual.target === actual.target
                    && $0.actual.attachment === actual.attachment
            }.map(\.facet)
            if let fact = recordAcceptedAbsence(previous: previous, actual: actual, removalFacets: removed) {
                propertyAbsences.append(fact)
            }
        }
        for facet in pending.facets { recordAcceptedFacet(facet, actual: actual) }
        return completeGroups()
    }

    @discardableResult
    func recordAcceptedAttachment(from source: ViewNode, to target: ViewNode) -> [RetainedDescriptorAcceptedGroup] {
        guard let outputs = ownedOutputs(of: source), let actual = actualAttachment(for: target) else { return [] }
        for output in outputs {
            if let facet = output.facets[.attachment] { recordAcceptedFacet(facet, actual: actual) }
        }
        return completeGroups()
    }

    @discardableResult
    func recordCompletedNode(from source: ViewNode, to target: ViewNode) -> [RetainedDescriptorAcceptedGroup] {
        guard let outputs = ownedOutputs(of: source), let actual = actualAttachment(for: target) else { return [] }
        let incoming = outputs.compactMap { groups[ObjectIdentifier($0.group)]?.receipt }
        let previous = target.retainedLazyListActivityStorage?.committedDescriptorContributions.values.map { $0 } ?? []
        for receipt in previous where !incoming.contains(where: { $0 === receipt }) {
            let removed = receipt.acceptedFacets.filter {
                $0.nativeField.key == .completion && $0.actual.target === actual.target
                    && $0.actual.attachment === actual.attachment
            }.map(\.facet)
            if !removed.isEmpty,
                let fact = recordAcceptedAbsence(previous: receipt, actual: actual, removalFacets: removed)
            {
                propertyAbsences.append(fact)
            }
        }
        for output in outputs {
            if let facet = output.facets[.completion] { recordAcceptedFacet(facet, actual: actual) }
        }
        return completeGroups()
    }

    func takePropertyAbsences() -> [RetainedDescriptorAcceptedAbsence] {
        let result = propertyAbsences
        propertyAbsences.removeAll()
        return result
    }

    @discardableResult
    func recordAcceptedTaskDeclarationTransport(
        from source: ViewNode, to target: ViewNode, declarationIDs: [RetainedTaskDeclarationID]
    ) -> [RetainedDescriptorAcceptedGroup] {
        guard let outputs = ownedOutputs(of: source), let actual = actualAttachment(for: target) else { return [] }
        let transported = Set(declarationIDs.map { ObjectIdentifier($0) })
        for output in outputs {
            guard groups[ObjectIdentifier(output.group)]?.kind == .scopedTask else { continue }
            for facet in output.facets.values {
                guard case .scopedTaskDeclaration(let declaration) = facet.nativeField,
                    transported.contains(ObjectIdentifier(declaration))
                else { continue }
                recordAcceptedFacet(facet, actual: actual)
            }
        }
        return completeGroups()
    }

    func prepareInsertedNode(from source: ViewNode) -> Bool {
        guard let outputs = ownedOutputs(of: source), canPrepare(outputs) else { return false }
        let storage = source.lazyListActivityStorage()
        let key = ObjectIdentifier(storage.targetID)
        guard insertions[key] == nil else { return false }
        let candidates = source.existingRetainedTaskState?.descriptorCandidateDeclarations() ?? []
        var facets: [RetainedDescriptorSourceFacet] = []
        for output in outputs {
            guard let record = groups[ObjectIdentifier(output.group)] else { return false }
            if record.kind != .scopedTask {
                for keyPath in source.retainedSourcePayloadFields {
                    let facet = output.facet(.nodeProperty(keyPath))
                    output.retirementProperties.insert(facet.nativeField.key)
                }
            }
            for facet in output.facets.values {
                switch facet.nativeField {
                case .childAttachment:
                    facets.append(facet)
                case .nodeProperty:
                    if record.kind == .scopedTask || output.retirementProperties.contains(facet.nativeField.key) {
                        facets.append(facet)
                    }
                case .scopedTaskDeclaration(let declaration):
                    guard
                        candidates.contains(where: {
                            $0.group === record.id && $0.declarations.contains(where: { $0 === declaration })
                        })
                    else { return false }
                    facets.append(facet)
                case .nodeCompletion, .listDescriptor:
                    break
                }
            }
        }
        insertions[key] = RetainedDescriptorPendingInsertion(
            node: source, target: storage.targetID, attachment: storage.attachmentID, facets: facets)
        return true
    }

    @discardableResult
    func recordAcceptedInsertedNode(on node: ViewNode) -> [RetainedDescriptorAcceptedGroup] {
        guard let storage = node.retainedLazyListActivityStorage,
            let pending = insertions.removeValue(forKey: ObjectIdentifier(storage.targetID)),
            pending.node === node, pending.target === storage.targetID,
            pending.attachment === storage.attachmentID, let actual = actualAttachment(for: node)
        else { return [] }
        for facet in pending.facets { recordAcceptedFacet(facet, actual: actual) }
        // Checked node/subtree completion remains a separate post-callback fact.
        return completeGroups()
    }

    private func recordAcceptedFacet(
        _ facet: RetainedDescriptorSourceFacet, actual: RetainedLazyListActualAttachment
    ) {
        let fact = RetainedDescriptorAcceptedFacet(
            component: facet.component, group: facet.group, source: facet.source,
            facet: facet.id, actual: actual, nativeField: facet.nativeField)
        let key = ObjectIdentifier(facet.id)
        if let old = acceptedByFacet[key] {
            if old.actual.target !== actual.target || old.actual.attachment !== actual.attachment {
                invalidIDs.insert(ObjectIdentifier(facet.group))
                acceptedFacets.append(fact)
                if let receipt = groups[ObjectIdentifier(facet.group)]?.receipt {
                    receipt.revoke()
                    removeRetiredContribution(receipt)
                }
            }
            return
        }
        acceptedByFacet[key] = fact
        acceptedFacets.append(fact)
    }

    private func completeGroups() -> [RetainedDescriptorAcceptedGroup] {
        var newlyAccepted: [RetainedDescriptorAcceptedGroup] = []
        for id in groupOrder {
            let key = ObjectIdentifier(id)
            guard !completedIDs.contains(key), !invalidIDs.contains(key),
                let record = groups[key], record.isClosed, !record.required.isEmpty,
                !rejectedComponentIDs.contains(ObjectIdentifier(record.component)),
                record.kind != .scopedTask || !record.declarations.isEmpty,
                record.required.allSatisfy({ acceptedByFacet[ObjectIdentifier($0.id)] != nil })
            else { continue }
            let facts = acceptedFacets.filter { $0.group === id }
            var actuals: [RetainedLazyListActualAttachment] = []
            var coherent = true
            for output in record.outputs {
                let outputFacts = facts.filter { $0.source === output.payload }
                guard let first = outputFacts.first,
                    outputFacts.allSatisfy({
                        $0.actual.target === first.actual.target && $0.actual.attachment === first.actual.attachment
                    })
                else {
                    coherent = false
                    break
                }
                if record.kind == .scopedTask
                    && actuals.contains(where: {
                        $0.target === first.actual.target && $0.attachment === first.actual.attachment
                    })
                {
                    coherent = false
                    break
                }
                if !actuals.contains(where: {
                    $0.target === first.actual.target && $0.attachment === first.actual.attachment
                }) {
                    actuals.append(first.actual)
                }
            }
            let durableFacts =
                record.kind == .scopedTask
                ? record.required.compactMap { acceptedByFacet[ObjectIdentifier($0.id)] }
                : facts.filter { fact in
                    guard let output = record.outputs.first(where: { $0.payload === fact.source }) else { return false }
                    switch fact.nativeField {
                    case .nodeProperty: return output.retirementProperties.contains(fact.nativeField.key)
                    case .childAttachment, .nodeCompletion: return true
                    case .scopedTaskDeclaration, .listDescriptor: return false
                    }
                }
            guard coherent, record.receipt.activate(on: actuals, facets: durableFacts) else { continue }
            let accepted = RetainedDescriptorAcceptedGroup(
                proposal: record.proposal, acceptedFacets: facts, receipt: record.receipt)
            completedIDs.insert(key)
            acceptedGroups.append(accepted)
            newlyAccepted.append(accepted)
            for actual in actuals {
                actual.node?.lazyListActivityStorage().committedDescriptorContributions[key] = record.receipt
                if record.kind == .deferredSubtree {
                    actual.node?.lazyListActivityStorage().descriptorDeferredSubtreeAnchor =
                        RetainedDescriptorDeferredSubtreeAnchor(contribution: record.receipt, actual: actual)
                }
            }
            if record.kind == .scopedTask {
                let members = record.outputs.compactMap { output -> RetainedLazyListAcceptedTaskMember? in
                    guard let actual = facts.first(where: { $0.source === output.payload })?.actual else { return nil }
                    return RetainedLazyListAcceptedTaskMember(
                        sourcePayload: output.payload,
                        requiredFacets: record.required.filter { $0.source === output.payload }.map(\.id),
                        actual: actual)
                }
                acceptedTaskGroups.append(
                    RetainedDescriptorAcceptedTaskGroup(
                        contribution: accepted, declarationIDs: record.declarations, members: members))
            }
        }
        return newlyAccepted
    }

    func takeAcceptedTaskGroups() -> [RetainedDescriptorAcceptedTaskGroup] {
        let result = acceptedTaskGroups
        acceptedTaskGroups.removeAll()
        return result
    }

    func acceptedTaskSources(
        for group: RetainedDescriptorAcceptedTaskGroup
    ) -> [RetainedLazyListAcceptedTaskSource]? {
        let key = ObjectIdentifier(group.contribution.proposal.group)
        guard let record = groups[key], record.kind == .scopedTask,
            group.contribution.proposal.attempt === attempt,
            completedIDs.contains(key), !invalidIDs.contains(key),
            group.contribution.receipt === record.receipt, record.receipt.isActive,
            !group.members.isEmpty, group.members.count == record.outputs.count,
            group.declarationIDs.count == record.declarations.count,
            zip(group.declarationIDs, record.declarations).allSatisfy({ $0.0 === $0.1 })
        else { return nil }
        var pins: [RetainedLazyListAcceptedTaskSource] = []
        var seen: Set<ObjectIdentifier> = []
        for member in group.members {
            guard seen.insert(ObjectIdentifier(member.sourcePayload)).inserted,
                let output = record.outputs.first(where: { $0.payload === member.sourcePayload }),
                let source = output.node, member.actual.isAttached
            else { return nil }
            let required = record.required.filter { $0.source === output.payload }.map(\.id)
            guard required.count == member.requiredFacets.count,
                zip(required, member.requiredFacets).allSatisfy({ $0.0 === $0.1 }),
                required.allSatisfy({ id in
                    guard let fact = acceptedByFacet[ObjectIdentifier(id)] else { return false }
                    return fact.source === member.sourcePayload
                        && fact.actual.target === member.actual.target
                        && fact.actual.attachment === member.actual.attachment
                })
            else { return nil }
            pins.append(RetainedLazyListAcceptedTaskSource(member: member, source: source))
        }
        return pins
    }

    // The caller names exactly which empty groups its accepted structural anchor
    // represents. No empty group is accepted merely because it emitted no node.
    @discardableResult
    func recordAcceptedEmptyGroups(
        anchor: RetainedLazyListActualAttachment, groups requested: [RetainedDescriptorGroupID]
    ) -> [RetainedDescriptorAcceptedEmptyGroup] {
        guard anchor.isAttached else { return [] }
        var newlyAccepted: [RetainedDescriptorAcceptedEmptyGroup] = []
        for id in requested {
            let key = ObjectIdentifier(id)
            guard !completedIDs.contains(key), !invalidIDs.contains(key),
                let record = groups[key], record.isClosed, record.outputs.isEmpty,
                !rejectedComponentIDs.contains(ObjectIdentifier(record.component)),
                record.kind != .scopedTask,
                components[ObjectIdentifier(record.component)]?.scope?.canPublishDescriptors == true,
                record.receipt.activate(on: [anchor], facets: [])
            else { continue }
            let fact = RetainedDescriptorAcceptedEmptyGroup(
                proposal: record.proposal, structuralAnchor: anchor, receipt: record.receipt)
            completedIDs.insert(key)
            acceptedEmptyGroups.append(fact)
            newlyAccepted.append(fact)
            anchor.node?.lazyListActivityStorage().committedDescriptorContributions[key] = record.receipt
        }
        return newlyAccepted
    }

    func seedExisting(from nodes: [ViewNode]) {
        guard !isFrozen else { return }
        var pending = nodes
        var visited: Set<ObjectIdentifier> = []
        while let node = pending.popLast() {
            guard visited.insert(ObjectIdentifier(node)).inserted else { continue }
            pending.append(contentsOf: node.children)
            guard let storage = node.retainedLazyListActivityStorage else { continue }
            for receipt in storage.committedDescriptorContributions.values where receipt.isActive {
                guard !expectedExisting.contains(where: { $0.receipt === receipt }) else { continue }
                expectedExisting.append(
                    RetainedDescriptorExistingContribution(
                        receipt: receipt, actualAttachments: receipt.actualAttachments))
            }
        }
    }

    // Explicit unchanged acceptance by the native reconciler; never an inference
    // from a final-tree walk or the absence of a candidate source stamp.
    func recordExisting(_ node: ViewNode) {
        guard let storage = node.retainedLazyListActivityStorage,
            let actual = actualAttachment(for: node)
        else { return }
        for receipt in storage.committedDescriptorContributions.values where receipt.isActive {
            guard
                receipt.actualAttachments.contains(where: {
                    $0.target === actual.target && $0.attachment === actual.attachment
                }), !unchanged.contains(where: { $0.receipt === receipt })
            else { continue }
            unchanged.append(
                RetainedDescriptorExistingContribution(
                    receipt: receipt, actualAttachments: receipt.actualAttachments))
        }
    }

    @discardableResult
    func recordAcceptedAbsence(
        previous: RetainedDescriptorContributionReceipt,
        actual: RetainedLazyListActualAttachment,
        removalFacets: [RetainedLazyListSourceFacetID]
    ) -> RetainedDescriptorAcceptedAbsence? {
        let key = ObjectIdentifier(previous)
        guard !absentIDs.contains(key),
            previous.actualAttachments.contains(where: {
                $0.target === actual.target && $0.attachment === actual.attachment
            }),
            removalFacets.allSatisfy({ id in
                previous.acceptedFacets.contains(where: {
                    $0.facet === id && $0.actual.target === actual.target
                        && $0.actual.attachment === actual.attachment
                })
            })
        else { return nil }
        let fact = RetainedDescriptorAcceptedAbsence(
            previous: previous, actual: actual, removalFacets: removalFacets,
            cleanup: RetainedLazyListCleanupID())
        previous.revoke()
        removeRetiredContribution(previous)
        absentIDs.insert(key)
        absences.append(fact)
        cleanup.append(fact.cleanup)
        return fact
    }

    @discardableResult
    func recordPhysicalDeparture(of node: ViewNode) -> [RetainedDescriptorAcceptedAbsence] {
        guard let storage = node.retainedLazyListActivityStorage else { return [] }
        let previous = Array(storage.committedDescriptorContributions.values)
        var facts: [RetainedDescriptorAcceptedAbsence] = []
        for receipt in previous {
            guard
                let actual = receipt.actualAttachments.first(where: {
                    $0.target === storage.targetID && $0.attachment === storage.attachmentID
                })
            else { continue }
            let facets = receipt.acceptedFacets.filter {
                $0.actual.target === actual.target && $0.actual.attachment === actual.attachment
            }.map(\.facet)
            if let fact = recordAcceptedAbsence(previous: receipt, actual: actual, removalFacets: facets) {
                facts.append(fact)
            }
        }
        return facts
    }

    private func removeRetiredContribution(_ receipt: RetainedDescriptorContributionReceipt) {
        for actual in receipt.actualAttachments {
            guard let storage = actual.node?.retainedLazyListActivityStorage,
                storage.committedDescriptorContributions[ObjectIdentifier(receipt.group)] === receipt
            else { continue }
            storage.committedDescriptorContributions.removeValue(forKey: ObjectIdentifier(receipt.group))
            if storage.descriptorDeferredSubtreeAnchor?.contribution === receipt {
                storage.descriptorDeferredSubtreeAnchor = nil
            }
        }
    }

    func seal() -> RetainedDescriptorSealedActivity {
        if let sealed { return sealed }
        _ = freeze()
        let partial = groupOrder.compactMap { id -> RetainedDescriptorPartialGroup? in
            guard !completedIDs.contains(ObjectIdentifier(id)), let record = groups[ObjectIdentifier(id)] else {
                return nil
            }
            let facts = acceptedFacets.filter { $0.group === id }
            guard !facts.isEmpty else { return nil }
            return RetainedDescriptorPartialGroup(
                proposal: record.proposal, acceptedFacets: facts,
                unacceptedFacets: record.required.filter {
                    acceptedByFacet[ObjectIdentifier($0.id)] == nil
                }.map(\.id))
        }
        let result = RetainedDescriptorSealedActivity(
            acceptedFacets: acceptedFacets, acceptedGroups: acceptedGroups, partialGroups: partial,
            acceptedEmptyGroups: acceptedEmptyGroups,
            unchanged: unchanged.filter { $0.receipt.isActive && $0.actualAttachments.allSatisfy(\.isAttached) },
            absences: absences, cleanup: cleanup)
        sealed = result
        return result
    }

    func releaseUnadoptedTransport() {
        _ = seal()
        propertyCopies.removeAll()
        insertions.removeAll()
        acceptedTaskGroups.removeAll()
        // Only weak source references and native identities are released here.
        // Accepted receipts live on actual nodes independently of this ledger.
        for record in groups.values {
            for output in record.outputs {
                output.node?.retainedLazyListActivityStorage?.descriptorOutputs.removeAll { $0 === output }
            }
        }
        groups.removeAll()
        components.removeAll()
    }
}

@MainActor
package final class RetainedOwnedComponentID: Sendable {
    fileprivate weak var nativePresence: RetainedOwnedComponentPresence?
    fileprivate var wasRevoked = false
    package init() {}
}

/// A slot generation is allocated once. Reusing its spelling or the owning
/// component's structural position cannot allocate fresh authority for it.
@MainActor
package final class RetainedOwnedSlotGenerationID: Sendable {
    fileprivate var wasRegistered = false
    fileprivate var wasRevoked = false

    package init() {}
}

@MainActor
fileprivate final class RetainedOwnedDescriptorLifetime {
    weak var host: RetainedLazyListLogicalHostLifetime?
    let owner: RetainedLazyListDescriptorOwnerLifetime

    init(
        host: RetainedLazyListLogicalHostLifetime,
        owner: RetainedLazyListDescriptorOwnerLifetime
    ) {
        self.host = host
        self.owner = owner
    }

    var isCurrent: Bool { host?.isOpen == true && owner.isCurrent }

    func isSame(as other: RetainedOwnedDescriptorLifetime) -> Bool {
        guard let host, let otherHost = other.host else { return false }
        return host === otherHost && owner === other.owner
    }
}

/// These are native lifetime records, never the facade owner or an owned cell.
/// Lazy ownership deliberately has no physical attachment requirement.
@MainActor
fileprivate enum RetainedOwnedNativeLifetime {
    case lazy(RetainedLazyListLogicalMembershipReceipt)
    case descriptor(RetainedOwnedDescriptorLifetime)

    var permitsConstruction: Bool {
        switch self {
        case .lazy(let logical):
            return logical.permitsConstruction
        case .descriptor(let lifetime):
            return lifetime.isCurrent
        }
    }

    var permitsDeclaredWrite: Bool {
        switch self {
        case .lazy(let logical):
            return logical.isDeclared
        case .descriptor(let lifetime):
            return lifetime.isCurrent
        }
    }

    func isSame(as other: RetainedOwnedNativeLifetime) -> Bool {
        switch (self, other) {
        case (.lazy(let lhs), .lazy(let rhs)):
            return lhs === rhs
        case (.descriptor(let lhs), .descriptor(let rhs)):
            return lhs.isSame(as: rhs)
        case (.lazy, .descriptor), (.descriptor, .lazy):
            return false
        }
    }
}

/// The original construction is the only authority for a proposed slot. The
/// attribution is weak so an escaped cell cannot keep a build frame alive.
@MainActor
fileprivate final class RetainedOwnedConstructionGate {
    private enum Kind { case lazy, descriptor }

    private let kind: Kind
    private weak var lazyAttribution: RetainedLazyListBuildAttribution?
    private weak var descriptorAttribution: RetainedDescriptorComponentAttribution?

    init(lazyAttribution: RetainedLazyListBuildAttribution) {
        kind = .lazy
        self.lazyAttribution = lazyAttribution
    }

    init(descriptorAttribution: RetainedDescriptorComponentAttribution) {
        kind = .descriptor
        self.descriptorAttribution = descriptorAttribution
    }

    var isCurrent: Bool {
        switch kind {
        case .lazy:
            return lazyAttribution?.constructionState == .admittedForConstruction
        case .descriptor:
            return descriptorAttribution?.canConstruct == true
        }
    }
}

@MainActor
fileprivate final class RetainedOwnedComponentPresence {
    let owner: RetainedOwnedComponentID
    let lifetime: RetainedOwnedNativeLifetime
    private let construction: RetainedOwnedConstructionGate
    private var didDeclare = false
    private(set) var wasRevoked = false
    var payloadFacets: [RetainedOwnedPhysicalFacetKey: RetainedLazyListActualAttachment] = [:]
    var structuralFacets: [RetainedOwnedPhysicalFacetKey: RetainedLazyListActualAttachment] = [:]
    var deferredRegion: RetainedOwnedStructuralRegion?
    var declaredRegions: [ObjectIdentifier: RetainedOwnedStructuralRegion] = [:]

    init(
        owner: RetainedOwnedComponentID, lifetime: RetainedOwnedNativeLifetime,
        construction: RetainedOwnedConstructionGate
    ) {
        self.owner = owner
        self.lifetime = lifetime
        self.construction = construction
    }

    var hasDeclaredComponent: Bool {
        didDeclare && !wasRevoked && !owner.wasRevoked && lifetime.permitsDeclaredWrite
    }

    func canContinue(in lifetime: RetainedOwnedNativeLifetime) -> Bool {
        !wasRevoked && !owner.wasRevoked && self.lifetime.isSame(as: lifetime)
            && (didDeclare || construction.isCurrent)
    }

    @discardableResult
    func activate() -> Bool {
        guard !wasRevoked, !owner.wasRevoked, lifetime.permitsConstruction else { return false }
        didDeclare = true
        return true
    }

    func revoke() {
        wasRevoked = true
        owner.wasRevoked = true
    }
}

@MainActor
fileprivate final class RetainedOwnedWeakComponentPresence {
    let owner: RetainedOwnedComponentID
    weak var presence: RetainedOwnedComponentPresence?
    init(_ presence: RetainedOwnedComponentPresence) {
        owner = presence.owner
        self.presence = presence
    }
}

/// A deferred namespace belongs to an exact owned boundary, not its current
/// physical node. Only native IDs and weak declaration entries survive eviction.
/// The current attachment and revision still gate every table replacement.
@MainActor
fileprivate final class RetainedOwnedStructuralRegion {
    let owner: RetainedOwnedComponentID
    weak var boundary: RetainedOwnedComponentPresence?
    let logicalMembership: RetainedLazyListLogicalMembershipReceipt
    var revision: UInt64 = 0
    var actual: RetainedLazyListActualAttachment?
    var slots: [ObjectIdentifier: RetainedOwnedWeakSlotPermission] = [:]
    var components: [ObjectIdentifier: RetainedOwnedWeakComponentPresence] = [:]
    var wasRevoked = false

    init(boundary: RetainedOwnedComponentPresence, logicalMembership: RetainedLazyListLogicalMembershipReceipt) {
        owner = boundary.owner
        self.boundary = boundary
        self.logicalMembership = logicalMembership
    }

    var isDeclared: Bool {
        !wasRevoked && !owner.wasRevoked && boundary?.hasDeclaredComponent == true
            && logicalMembership.isDeclared && actual != nil
    }
}

@MainActor
private struct RetainedOwnedMarkerNamespaces {
    var regions: [ObjectIdentifier: RetainedOwnedStructuralRegion] = [:]
    var hasUnscopedDeclaration = false

    func isSame(as other: RetainedOwnedMarkerNamespaces) -> Bool {
        hasUnscopedDeclaration == other.hasUnscopedDeclaration && regions.count == other.regions.count
            && regions.allSatisfy { identifier, region in other.regions[identifier] === region }
    }

    mutating func include(_ incoming: [RetainedOwnedStructuralRegion]) {
        if incoming.isEmpty { hasUnscopedDeclaration = true }
        for region in incoming { regions[ObjectIdentifier(region)] = region }
    }

    func holds(_ permission: RetainedOwnedSlotPermission, outside region: RetainedOwnedStructuralRegion) -> Bool {
        hasUnscopedDeclaration
            || regions.values.contains {
                $0 !== region && $0.isDeclared && $0.slots[ObjectIdentifier(permission.slot)]?.permission === permission
            }
    }

    func holds(_ presence: RetainedOwnedComponentPresence, outside region: RetainedOwnedStructuralRegion) -> Bool {
        hasUnscopedDeclaration
            || regions.values.contains {
                $0 !== region && $0.isDeclared && $0.components[ObjectIdentifier(presence.owner)]?.presence === presence
            }
    }
}

/// All continuing receipts for this exact owner and slot generation share this
/// scalar. Revoking it changes permissions observed through every older receipt.
@MainActor
fileprivate final class RetainedOwnedSlotPermission {
    private enum Phase { case proposed, declared, revoked }

    let owner: RetainedOwnedComponentID
    let slot: RetainedOwnedSlotGenerationID
    let lifetime: RetainedOwnedNativeLifetime
    private let construction: RetainedOwnedConstructionGate
    private var phase: Phase = .proposed
    fileprivate var payloadFacets: [RetainedOwnedPhysicalFacetKey: RetainedLazyListActualAttachment] = [:]
    fileprivate var structuralFacets: [RetainedOwnedPhysicalFacetKey: RetainedLazyListActualAttachment] = [:]
    fileprivate var pendingDepartures: [ObjectIdentifier: RetainedOwnedPhysicalFacetKey] = [:]

    init(
        owner: RetainedOwnedComponentID,
        slot: RetainedOwnedSlotGenerationID,
        lifetime: RetainedOwnedNativeLifetime,
        construction: RetainedOwnedConstructionGate
    ) {
        self.owner = owner
        self.slot = slot
        self.lifetime = lifetime
        self.construction = construction
        slot.wasRegistered = true
    }

    var wasRevoked: Bool { phase == .revoked || slot.wasRevoked }
    var isDeclared: Bool { phase == .declared && !slot.wasRevoked }

    var permitsOwnedWrite: Bool {
        guard !slot.wasRevoked, !owner.wasRevoked else { return false }
        switch phase {
        case .proposed:
            return lifetime.permitsConstruction && construction.isCurrent
        case .declared:
            return lifetime.permitsDeclaredWrite && hasUnsuspendedDeclaration
        case .revoked:
            return false
        }
    }

    private var hasUnsuspendedDeclaration: Bool {
        guard !pendingDepartures.isEmpty else { return true }
        func isUnaffected(_ key: RetainedOwnedPhysicalFacetKey, _ actual: RetainedLazyListActualAttachment) -> Bool {
            actual.isAttached
                && !pendingDepartures.values.contains {
                    $0.target == key.target && $0.attachment == key.attachment
                }
        }
        return payloadFacets.contains { isUnaffected($0.key, $0.value) }
            || structuralFacets.contains { isUnaffected($0.key, $0.value) }
    }

    func canContinue(
        owner: RetainedOwnedComponentID,
        slot: RetainedOwnedSlotGenerationID,
        lifetime: RetainedOwnedNativeLifetime
    ) -> Bool {
        guard self.owner === owner, self.slot === slot, !wasRevoked,
            self.lifetime.isSame(as: lifetime)
        else { return false }
        // A later build cannot adopt the failed construction authority of an
        // unaccepted generation. Declared generations no longer use that gate.
        return phase == .declared || construction.isCurrent
    }

    /// Only an exact accepted native publication may call this. Construction
    /// is already closed during adoption, so it is not an activation predicate.
    @discardableResult
    func activate() -> Bool {
        guard !wasRevoked, !owner.wasRevoked, lifetime.permitsConstruction else { return false }
        phase = .declared
        return true
    }

    func revoke() {
        phase = .revoked
        slot.wasRevoked = true
    }
}

/// The roster is immutable, but permissions are per slot and shared with exact
/// continuing generations. A live sibling slot never authorizes a departed one.
@MainActor
package final class RetainedOwnedComponentReceipt {
    package let owner: RetainedOwnedComponentID
    package let slots: [RetainedOwnedSlotGenerationID]

    fileprivate let slotPermissions: [RetainedOwnedSlotPermission]
    fileprivate let nativeLifetime: RetainedOwnedNativeLifetime
    fileprivate let componentPresence: RetainedOwnedComponentPresence
    private let permissionsBySlot: [ObjectIdentifier: RetainedOwnedSlotPermission]
    package private(set) var hasAcceptedDeclaration = false

    private init(
        owner: RetainedOwnedComponentID,
        slots: [RetainedOwnedSlotGenerationID],
        permissions: [RetainedOwnedSlotPermission],
        lifetime: RetainedOwnedNativeLifetime,
        componentPresence: RetainedOwnedComponentPresence
    ) {
        self.owner = owner
        self.slots = slots
        slotPermissions = permissions
        nativeLifetime = lifetime
        self.componentPresence = componentPresence
        permissionsBySlot = Dictionary(
            uniqueKeysWithValues: permissions.map { (ObjectIdentifier($0.slot), $0) })
    }

    package func permitsOwnedWrite(for slot: RetainedOwnedSlotGenerationID) -> Bool {
        permission(for: slot)?.permitsOwnedWrite == true
    }

    package func hasAcceptedOwnership(for slot: RetainedOwnedSlotGenerationID) -> Bool {
        guard let permission = permission(for: slot) else { return false }
        return permission.isDeclared && permission.permitsOwnedWrite
    }

    package var hasDeclaredComponent: Bool { componentPresence.hasDeclaredComponent }

    package func belongs(to logicalMembership: RetainedLazyListLogicalMembershipReceipt) -> Bool {
        if case .lazy(let logical) = nativeLifetime { return logical === logicalMembership }
        return false
    }

    package var isDescriptorOwnership: Bool {
        if case .descriptor = nativeLifetime { return true }
        return false
    }

    fileprivate func recordAcceptedDeclaration() { hasAcceptedDeclaration = true }

    fileprivate func permission(
        for slot: RetainedOwnedSlotGenerationID
    ) -> RetainedOwnedSlotPermission? {
        guard let permission = permissionsBySlot[ObjectIdentifier(slot)],
            permission.owner === owner, permission.slot === slot
        else { return nil }
        return permission
    }

    fileprivate func hasSameNativeLifetime(as other: RetainedOwnedComponentReceipt) -> Bool {
        nativeLifetime.isSame(as: other.nativeLifetime)
    }

    @discardableResult
    fileprivate func activate(slot: RetainedOwnedSlotGenerationID) -> Bool {
        permission(for: slot)?.activate() == true
    }

    @discardableResult
    fileprivate func revoke(slot: RetainedOwnedSlotGenerationID) -> Bool {
        guard let permission = permission(for: slot) else { return false }
        permission.revoke()
        return true
    }

    fileprivate static func register(
        owner: RetainedOwnedComponentID,
        slots: [RetainedOwnedSlotGenerationID],
        continuing: [RetainedOwnedComponentReceipt],
        lazyAttribution: RetainedLazyListBuildAttribution
    ) -> RetainedOwnedComponentReceipt? {
        guard lazyAttribution.constructionState == .admittedForConstruction else { return nil }
        return register(
            owner: owner, slots: slots, continuing: continuing,
            lifetime: .lazy(lazyAttribution.logicalMembership),
            construction: RetainedOwnedConstructionGate(lazyAttribution: lazyAttribution))
    }

    fileprivate static func register(
        owner: RetainedOwnedComponentID,
        slots: [RetainedOwnedSlotGenerationID],
        continuing: [RetainedOwnedComponentReceipt],
        descriptorAttribution: RetainedDescriptorComponentAttribution
    ) -> RetainedOwnedComponentReceipt? {
        guard descriptorAttribution.canConstruct,
            let scope = descriptorAttribution.descriptorScope,
            let host = scope.nativeHostLifetime
        else { return nil }
        let lifetime = RetainedOwnedDescriptorLifetime(
            host: host, owner: scope.nativeOwnerLifetime)
        return register(
            owner: owner, slots: slots, continuing: continuing,
            lifetime: .descriptor(lifetime),
            construction: RetainedOwnedConstructionGate(descriptorAttribution: descriptorAttribution))
    }

    private static func register(
        owner: RetainedOwnedComponentID,
        slots: [RetainedOwnedSlotGenerationID],
        continuing: [RetainedOwnedComponentReceipt],
        lifetime: RetainedOwnedNativeLifetime,
        construction: RetainedOwnedConstructionGate
    ) -> RetainedOwnedComponentReceipt? {
        guard lifetime.permitsConstruction, construction.isCurrent,
            !owner.wasRevoked,
            Set(slots.map { ObjectIdentifier($0) }).count == slots.count
        else { return nil }
        guard continuing.allSatisfy({ $0.owner === owner && $0.nativeLifetime.isSame(as: lifetime) }) else {
            return nil
        }
        let presence: RetainedOwnedComponentPresence
        if let existing = owner.nativePresence {
            guard existing.canContinue(in: lifetime),
                continuing.allSatisfy({ $0.componentPresence === existing })
            else { return nil }
            presence = existing
        } else {
            guard continuing.isEmpty else { return nil }
            presence = RetainedOwnedComponentPresence(owner: owner, lifetime: lifetime, construction: construction)
        }

        // Validate the whole roster before consuming any fresh generation.
        // A changed slot set is valid: dropped slots are deliberately untouched.
        var reused: [ObjectIdentifier: RetainedOwnedSlotPermission] = [:]
        for slot in slots {
            guard !slot.wasRevoked else { return nil }
            let candidates = continuing.compactMap { $0.permission(for: slot) }
            if let permission = candidates.first {
                guard candidates.allSatisfy({ $0 === permission }),
                    permission.canContinue(owner: owner, slot: slot, lifetime: lifetime)
                else { return nil }
                reused[ObjectIdentifier(slot)] = permission
            } else {
                // Requiring exact continuation prevents a second independent
                // permission object from being forged for an existing generation.
                guard !slot.wasRegistered else { return nil }
            }
        }

        var permissions: [RetainedOwnedSlotPermission] = []
        permissions.reserveCapacity(slots.count)
        for slot in slots {
            if let permission = reused[ObjectIdentifier(slot)] {
                permissions.append(permission)
            } else {
                permissions.append(
                    RetainedOwnedSlotPermission(
                        owner: owner, slot: slot, lifetime: lifetime, construction: construction))
            }
        }
        owner.nativePresence = presence
        return RetainedOwnedComponentReceipt(
            owner: owner, slots: slots, permissions: permissions, lifetime: lifetime, componentPresence: presence)
    }
}

@MainActor
package enum RetainedOwnedComponentDeclarationOrigin {
    case lazy(component: RetainedLazyListComponentID)
    case descriptor(component: RetainedDescriptorComponentID)
}

/// Prepared source data only. The journal must supply exact native publication,
/// prior-revision and physical-facet occupancy proofs; this DTO grants none.
@MainActor
package final class RetainedOwnedComponentDeclarationPlan {
    package let origin: RetainedOwnedComponentDeclarationOrigin
    package let receipt: RetainedOwnedComponentReceipt
    package let retained: [RetainedOwnedSlotGenerationID]
    package let introduced: [RetainedOwnedSlotGenerationID]
    package let departed: [RetainedOwnedSlotGenerationID]
    package let sourcePayloads: [RetainedLazyListSourcePayloadID]
    package let sourceFacets: [RetainedLazyListSourceFacetID]
    package let declarationOnly: Bool
    fileprivate let isDeferredConstruction: Bool
    fileprivate let structuralRegions: [RetainedOwnedStructuralRegion]

    convenience init?(
        origin: RetainedOwnedComponentDeclarationOrigin,
        receipt: RetainedOwnedComponentReceipt,
        retained: [RetainedOwnedSlotGenerationID],
        introduced: [RetainedOwnedSlotGenerationID],
        departed: [RetainedOwnedSlotGenerationID],
        sourcePayloads: [RetainedLazyListSourcePayloadID],
        sourceFacets: [RetainedLazyListSourceFacetID], declarationOnly: Bool = false,
        isDeferredConstruction: Bool = false
    ) {
        self.init(
            origin: origin, receipt: receipt, retained: retained, introduced: introduced, departed: departed,
            sourcePayloads: sourcePayloads, sourceFacets: sourceFacets, declarationOnly: declarationOnly,
            isDeferredConstruction: isDeferredConstruction, structuralRegions: [])
    }

    fileprivate init?(
        origin: RetainedOwnedComponentDeclarationOrigin,
        receipt: RetainedOwnedComponentReceipt,
        retained: [RetainedOwnedSlotGenerationID],
        introduced: [RetainedOwnedSlotGenerationID],
        departed: [RetainedOwnedSlotGenerationID],
        sourcePayloads: [RetainedLazyListSourcePayloadID],
        sourceFacets: [RetainedLazyListSourceFacetID], declarationOnly: Bool = false,
        isDeferredConstruction: Bool = false,
        structuralRegions: [RetainedOwnedStructuralRegion]
    ) {
        let retainedIDs = Set(retained.map { ObjectIdentifier($0) })
        let introducedIDs = Set(introduced.map { ObjectIdentifier($0) })
        let departedIDs = Set(departed.map { ObjectIdentifier($0) })
        let rosterIDs = Set(receipt.slots.map { ObjectIdentifier($0) })
        let payloadIDs = Set(sourcePayloads.map { ObjectIdentifier($0) })
        let facetIDs = Set(sourceFacets.map { ObjectIdentifier($0) })
        guard retainedIDs.count == retained.count,
            introducedIDs.count == introduced.count,
            departedIDs.count == departed.count,
            payloadIDs.count == sourcePayloads.count,
            facetIDs.count == sourceFacets.count,
            sourceFacets.isEmpty || !sourcePayloads.isEmpty,
            retainedIDs.isDisjoint(with: introducedIDs),
            departedIDs.isDisjoint(with: rosterIDs),
            retainedIDs.union(introducedIDs) == rosterIDs,
            !declarationOnly
                || (introduced.isEmpty && receipt.hasDeclaredComponent
                    && receipt.slots.allSatisfy { receipt.hasAcceptedOwnership(for: $0) }),
            receipt.slots.allSatisfy({ receipt.permission(for: $0)?.wasRevoked == false })
        else { return nil }
        switch (origin, receipt.nativeLifetime) {
        case (.lazy, .lazy), (.descriptor, .descriptor):
            break
        case (.lazy, .descriptor), (.descriptor, .lazy):
            return nil
        }
        self.origin = origin
        self.receipt = receipt
        self.retained = retained
        self.introduced = introduced
        self.departed = departed
        self.sourcePayloads = sourcePayloads
        self.sourceFacets = sourceFacets
        self.declarationOnly = declarationOnly
        self.isDeferredConstruction = isDeferredConstruction
        self.structuralRegions = structuralRegions
    }
}

package enum RetainedOwnedComponentPublicationKind: Sendable {
    case sourceField, structuralEntry, emptyStructuralEntry, rowDeclarationTable, descriptorDeclarationTable
}

@MainActor
package struct RetainedOwnedComponentDeclarationFact {
    package let plan: RetainedOwnedComponentDeclarationPlan
    package let slots: [RetainedOwnedSlotGenerationID]
    package var acceptedSlots: [RetainedOwnedSlotGenerationID] { slots }
    package let sourcePayload: RetainedLazyListSourcePayloadID?
    package let sourceFacet: RetainedLazyListSourceFacetID?
    package let actual: RetainedLazyListActualAttachment
    package let kind: RetainedOwnedComponentPublicationKind
}

@MainActor
private final class RetainedOwnedComponentRegistration {
    let origin: RetainedOwnedComponentDeclarationOrigin
    let receipt: RetainedOwnedComponentReceipt
    let previous: [RetainedOwnedComponentReceipt]
    let declarationOnly: Bool
    let isDeferredConstruction: Bool

    init(
        origin: RetainedOwnedComponentDeclarationOrigin, receipt: RetainedOwnedComponentReceipt,
        previous: [RetainedOwnedComponentReceipt], declarationOnly: Bool,
        isDeferredConstruction: Bool
    ) {
        self.origin = origin
        self.receipt = receipt
        self.previous = previous
        self.declarationOnly = declarationOnly
        self.isDeferredConstruction = isDeferredConstruction
    }
}

private enum RetainedOwnedComponentKey: Hashable {
    case lazy(ObjectIdentifier)
    case descriptor(ObjectIdentifier)
}

extension RetainedOwnedComponentDeclarationOrigin {
    fileprivate var key: RetainedOwnedComponentKey {
        switch self {
        case .lazy(let component): .lazy(ObjectIdentifier(component))
        case .descriptor(let component): .descriptor(ObjectIdentifier(component))
        }
    }
}

@MainActor
struct RetainedOwnedComponentSource {
    weak var node: ViewNode?
    let payload: RetainedLazyListSourcePayloadID
    let facets: [RetainedLazyListSourceFacetID]
    let components: [RetainedOwnedComponentDeclarationOrigin]
    let deferredRoot: RetainedLazyListComponentID?
}

/// Native source metadata in first-encounter order, never a publication permit.
/// Counts describe this membership work, not all preparation or ownership work.
@MainActor
struct RetainedOwnedComponentSourceRoster {
    let payloads: [RetainedLazyListSourcePayloadID]
    let facets: [RetainedLazyListSourceFacetID]
    let sourceVisits: Int
    let payloadMembershipChecks: Int
    let facetMembershipChecks: Int
}

/// One freeze-local index into its original immutable source array. It contains
/// only tagged native component identities and integer source positions; no
/// node, permission, currentness result, or authored identity is indexed.
@MainActor
struct RetainedOwnedComponentSourceIndex {
    private let sourceIndices: [RetainedOwnedComponentKey: [Int]]
    let componentVisits: Int
    let sourceMembershipCount: Int

    init(sources: [RetainedOwnedComponentSource]) {
        var sourceIndices: [RetainedOwnedComponentKey: [Int]] = [:]
        var componentVisits = 0
        var sourceMembershipCount = 0
        for (position, source) in sources.enumerated() {
            var seen: Set<RetainedOwnedComponentKey> = []
            for component in source.components {
                componentVisits += 1
                let key = component.key
                // The original contains predicate matched a source only once,
                // even when its ancestry contained a repeated component key.
                guard seen.insert(key).inserted else { continue }
                sourceIndices[key, default: []].append(position)
                sourceMembershipCount += 1
            }
        }
        self.sourceIndices = sourceIndices
        self.componentVisits = componentVisits
        self.sourceMembershipCount = sourceMembershipCount
    }

    func roster(
        for component: RetainedOwnedComponentDeclarationOrigin, in sources: [RetainedOwnedComponentSource]
    ) -> RetainedOwnedComponentSourceRoster {
        roster(for: component.key, in: sources)
    }

    fileprivate func roster(
        for key: RetainedOwnedComponentKey, in sources: [RetainedOwnedComponentSource]
    ) -> RetainedOwnedComponentSourceRoster {
        let matching = sourceIndices[key] ?? []
        var payloads: [RetainedLazyListSourcePayloadID] = []
        var facets: [RetainedLazyListSourceFacetID] = []
        var seenPayloads: Set<ObjectIdentifier> = []
        var seenFacets: Set<ObjectIdentifier> = []
        var facetMembershipChecks = 0
        for position in matching {
            let source = sources[position]
            if seenPayloads.insert(ObjectIdentifier(source.payload)).inserted { payloads.append(source.payload) }
            // A repeated payload can still introduce distinct required facets.
            for facet in source.facets {
                facetMembershipChecks += 1
                if seenFacets.insert(ObjectIdentifier(facet)).inserted { facets.append(facet) }
            }
        }
        return RetainedOwnedComponentSourceRoster(
            payloads: payloads, facets: facets, sourceVisits: matching.count,
            payloadMembershipChecks: matching.count, facetMembershipChecks: facetMembershipChecks)
    }
}

private struct RetainedOwnedPhysicalFacetKey: Hashable {
    let target: ObjectIdentifier
    let attachment: ObjectIdentifier
    let field: AnyKeyPath?
    var region: ObjectIdentifier? = nil
}

@MainActor
fileprivate final class RetainedOwnedWeakSlotPermission {
    let slot: RetainedOwnedSlotGenerationID
    weak var permission: RetainedOwnedSlotPermission?

    init(_ permission: RetainedOwnedSlotPermission) {
        slot = permission.slot
        self.permission = permission
    }
}

private struct RetainedOwnedPropertyKey: Hashable {
    let source: ObjectIdentifier
    let target: ObjectIdentifier
    let field: AnyKeyPath
}

@MainActor
private struct RetainedOwnedPropertyPublication {
    weak var source: ViewNode?
    weak var target: ViewNode?
    let targetID: RetainedLazyListTargetID
    let attachmentID: RetainedLazyListAttachmentID
    let permissions: [RetainedOwnedSlotPermission]
    let hasPayload: Bool
    let declarations: [RetainedOwnedComponentDeclarationPlan]
    var expectedStructuralRevision: UInt64? = nil
    var regions: [RetainedOwnedRegionPublication] = []
    let facet = RetainedLazyListSourceFacetID()
}

@MainActor
private struct RetainedOwnedInsertionPublication {
    weak var source: ViewNode?
    let targetID: RetainedLazyListTargetID
    let attachmentID: RetainedLazyListAttachmentID
    let permissions: [RetainedOwnedSlotPermission]
    let declarations: [RetainedOwnedComponentDeclarationPlan]
    let regions: [RetainedOwnedRegionPublication]
    let expectedStructuralRevision: UInt64
}

@MainActor
private struct RetainedOwnedRegionSource {
    let component: RetainedOwnedComponentKey
    let region: RetainedOwnedStructuralRegion
    weak var source: ViewNode?
}

@MainActor
private struct RetainedOwnedRegionPublication {
    let region: RetainedOwnedStructuralRegion
    let expectedRevision: UInt64
    let declarations: [RetainedOwnedComponentDeclarationPlan]
}

@MainActor
private struct RetainedOwnedDeferredRegionBuild {
    let component: RetainedOwnedComponentKey
    let original: RetainedLazyListDeferredSubtreeAnchor
    let expectedRevision: UInt64?
}

/// Partitioned retirement still removes the original physical maps once.
/// Later consumption must not erase metadata published on the same storage.
@MainActor
final class RetainedOwnedPhysicalDepartureRemoval {
    private weak var originalStorage: RetainedLazyListNodeActivityStorage?
    private let targetID: RetainedLazyListTargetID
    private let attachmentID: RetainedLazyListAttachmentID
    private var wasClaimed = false
    private var didClearOriginalMaps = false

    init(
        storage: RetainedLazyListNodeActivityStorage?, targetID: RetainedLazyListTargetID,
        attachmentID: RetainedLazyListAttachmentID
    ) {
        originalStorage = storage
        self.targetID = targetID
        self.attachmentID = attachmentID
    }

    func removeOriginalMapsOnce() {
        guard !wasClaimed else { return }
        wasClaimed = true
        guard let storage = originalStorage, storage.targetID === targetID, storage.attachmentID === attachmentID else {
            return
        }
        Self.removePhysicalMaps(from: storage)
        // This is evidence of a completed native clear, not a permission cache.
        // A refused clear never establishes absence and cannot be retried.
        didClearOriginalMaps =
            storage.targetID === targetID && storage.attachmentID === attachmentID
            && storage.ownedPayloadPermissions.isEmpty && storage.ownedStructuralPermissions.isEmpty
            && storage.ownedEmptyStructuralPermissions.isEmpty && storage.ownedEmptyStructuralNamespaces.isEmpty
            && storage.ownedDeclaredStructuralPermissions.isEmpty && storage.ownedDeclaredStructuralNamespaces.isEmpty
            && storage.ownedPayloadComponents.isEmpty && storage.ownedStructuralComponents.isEmpty
            && storage.ownedEmptyStructuralComponents.isEmpty && storage.ownedEmptyRowRevisions.isEmpty
            && storage.ownedDeclaredStructuralComponents.isEmpty && storage.ownedDeferredRegions.isEmpty
            && storage.ownedRegionStructuralPermissions.isEmpty && storage.ownedRegionStructuralComponents.isEmpty
    }

    var successfullyClearedOriginalStorage: RetainedLazyListNodeActivityStorage? {
        guard didClearOriginalMaps, let storage = originalStorage,
            storage.targetID === targetID, storage.attachmentID === attachmentID
        else { return nil }
        return storage
    }

    fileprivate static func removePhysicalMaps(from storage: RetainedLazyListNodeActivityStorage) {
        storage.ownedPayloadPermissions.removeAll()
        storage.ownedStructuralPermissions.removeAll()
        storage.ownedEmptyStructuralPermissions.removeAll()
        storage.ownedEmptyStructuralNamespaces.removeAll()
        storage.ownedDeclaredStructuralPermissions.removeAll()
        storage.ownedDeclaredStructuralNamespaces.removeAll()
        storage.ownedPayloadComponents.removeAll()
        storage.ownedStructuralComponents.removeAll()
        storage.ownedEmptyStructuralComponents.removeAll()
        storage.ownedEmptyRowRevisions.removeAll()
        storage.ownedDeclaredStructuralComponents.removeAll()
        storage.ownedDeferredRegions.removeAll()
        storage.ownedRegionStructuralPermissions.removeAll()
        storage.ownedRegionStructuralComponents.removeAll()
    }
}

@MainActor
fileprivate final class RetainedOwnedPhysicalDepartureSnapshot {
    weak var storage: RetainedLazyListNodeActivityStorage?
    let targetID: RetainedLazyListTargetID
    let attachmentID: RetainedLazyListAttachmentID
    let cause: RetainedLazyListDepartureCause
    let payloads: [AnyKeyPath: [RetainedOwnedSlotPermission]]
    let structural: [RetainedOwnedSlotPermission]
    let emptyStructural: [RetainedOwnedSlotPermission]
    let componentPayloads: [AnyKeyPath: [RetainedOwnedComponentPresence]]
    let componentStructural: [RetainedOwnedComponentPresence]
    let regions: [ObjectIdentifier: RetainedOwnedStructuralRegion]
    let regionSlots: [ObjectIdentifier: [RetainedOwnedSlotPermission]]
    let regionComponents: [ObjectIdentifier: [RetainedOwnedComponentPresence]]
    var wasConsumed = false
    private var sharedRemoval: RetainedOwnedPhysicalDepartureRemoval?
    private var isPendingPartition = false

    var permissions: [RetainedOwnedSlotPermission] {
        payloads.values.flatMap { $0 } + structural + emptyStructural + regionSlots.values.flatMap { $0 }
    }

    var components: [RetainedOwnedComponentPresence] {
        componentPayloads.values.flatMap { $0 } + componentStructural + regionComponents.values.flatMap { $0 }
    }

    init(storage: RetainedLazyListNodeActivityStorage, cause: RetainedLazyListDepartureCause) {
        self.storage = storage
        targetID = storage.targetID
        attachmentID = storage.attachmentID
        self.cause = cause
        payloads = storage.ownedPayloadPermissions
        structural = storage.ownedStructuralPermissions
        emptyStructural =
            storage.ownedEmptyStructuralPermissions.values.flatMap { $0 }
            + storage.ownedDeclaredStructuralPermissions.values.flatMap { $0 }
        componentPayloads = storage.ownedPayloadComponents
        componentStructural =
            storage.ownedStructuralComponents + Array(storage.ownedEmptyStructuralComponents.values)
            + Array(storage.ownedDeclaredStructuralComponents.values)
        regions = storage.ownedDeferredRegions
        regionSlots = storage.ownedRegionStructuralPermissions
        regionComponents = storage.ownedRegionStructuralComponents
    }

    private init(
        original: RetainedOwnedPhysicalDepartureSnapshot, permissions: Set<ObjectIdentifier>,
        components: Set<ObjectIdentifier>, keepingMembers: Bool, removal: RetainedOwnedPhysicalDepartureRemoval
    ) {
        storage = original.storage
        targetID = original.targetID
        attachmentID = original.attachmentID
        cause = original.cause
        sharedRemoval = removal
        isPendingPartition = keepingMembers
        payloads = original.payloads.mapValues {
            $0.filter { permissions.contains(ObjectIdentifier($0)) == keepingMembers }
        }
        structural = original.structural.filter { permissions.contains(ObjectIdentifier($0)) == keepingMembers }
        emptyStructural = original.emptyStructural.filter {
            permissions.contains(ObjectIdentifier($0)) == keepingMembers
        }
        componentPayloads = original.componentPayloads.mapValues {
            $0.filter { components.contains(ObjectIdentifier($0)) == keepingMembers }
        }
        componentStructural = original.componentStructural.filter {
            components.contains(ObjectIdentifier($0)) == keepingMembers
        }
        // The ordinary partition admits only snapshots without region records.
        regions = [:]
        regionSlots = [:]
        regionComponents = [:]
    }

    func partition(
        permissions: Set<ObjectIdentifier>, components: Set<ObjectIdentifier>
    ) -> (immediate: RetainedOwnedPhysicalDepartureSnapshot, pending: RetainedOwnedPhysicalDepartureSnapshot)? {
        guard !wasConsumed, regions.isEmpty, regionSlots.isEmpty, regionComponents.isEmpty,
            !permissions.isEmpty || !components.isEmpty
        else { return nil }
        let removal = RetainedOwnedPhysicalDepartureRemoval(
            storage: storage, targetID: targetID, attachmentID: attachmentID)
        let immediate = RetainedOwnedPhysicalDepartureSnapshot(
            original: self, permissions: permissions, components: components, keepingMembers: false, removal: removal)
        let pending = RetainedOwnedPhysicalDepartureSnapshot(
            original: self, permissions: permissions, components: components, keepingMembers: true, removal: removal)
        // Transfer this one capture, without recapturing either physical maps
        // or authored payloads when the second cohort eventually retires.
        wasConsumed = true
        return (immediate, pending)
    }

    func removePhysicalMaps() {
        if let sharedRemoval {
            sharedRemoval.removeOriginalMapsOnce()
        } else if let storage, storage.targetID === targetID, storage.attachmentID === attachmentID {
            RetainedOwnedPhysicalDepartureRemoval.removePhysicalMaps(from: storage)
        }
    }

    var laterPublicationStorage: RetainedLazyListNodeActivityStorage? {
        guard isPendingPartition else { return nil }
        return sharedRemoval?.successfullyClearedOriginalStorage
    }

    func suspendOwnedWrites() {
        guard cause != .viewportEviction, !wasConsumed else { return }
        let key = RetainedOwnedPhysicalFacetKey(
            target: ObjectIdentifier(targetID), attachment: ObjectIdentifier(attachmentID), field: nil)
        for permission in permissions { permission.pendingDepartures[ObjectIdentifier(self)] = key }
    }

    func finishOwnedWriteSuspension() {
        for permission in permissions { permission.pendingDepartures.removeValue(forKey: ObjectIdentifier(self)) }
    }
}

/// Removing a dormant marker can precede the original source's normal owned
/// publication. This ticket postpones retirement, never grants write authority,
/// and contains only original native plans, members, and weak attachment proof.
@MainActor
private final class RetainedOwnedDeclaredMarkerRetirement {
    @MainActor
    enum Member {
        case slot(RetainedOwnedSlotPermission)
        case component(RetainedOwnedComponentPresence)

        var identity: ObjectIdentifier {
            switch self {
            case .slot(let permission): return ObjectIdentifier(permission)
            case .component(let presence): return ObjectIdentifier(presence)
            }
        }

        var hasAttachedFootprint: Bool {
            switch self {
            case .slot(let permission):
                return permission.payloadFacets.values.contains(where: \.isAttached)
                    || permission.structuralFacets.values.contains(where: \.isAttached)
            case .component(let presence):
                return presence.payloadFacets.values.contains(where: \.isAttached)
                    || presence.structuralFacets.values.contains(where: \.isAttached)
            }
        }

        var canContinue: Bool {
            switch self {
            case .slot(let permission):
                return permission.isDeclared && !permission.owner.wasRevoked
                    && permission.lifetime.permitsDeclaredWrite
            case .component(let presence): return presence.hasDeclaredComponent
            }
        }

        func isNamed(by plan: RetainedOwnedComponentDeclarationPlan) -> Bool {
            switch self {
            case .slot(let permission):
                return plan.receipt.permission(for: permission.slot) === permission
                    && plan.receipt.nativeLifetime.isSame(as: permission.lifetime)
            case .component(let presence): return plan.receipt.componentPresence === presence
            }
        }

        func hasNormalMarker(on storage: RetainedLazyListNodeActivityStorage) -> Bool {
            switch self {
            case .slot(let permission): return storage.ownedStructuralPermissions.contains { $0 === permission }
            case .component(let presence): return storage.ownedStructuralComponents.contains { $0 === presence }
            }
        }
    }

    let attempt: RetainedLazyListAttemptID
    let member: Member
    let plans: [RetainedOwnedComponentDeclarationPlan]
    let formerActual: RetainedLazyListActualAttachment
    let removalFacet: RetainedLazyListSourceFacetID
    var wasConsumed = false

    init(
        attempt: RetainedLazyListAttemptID, member: Member, plans: [RetainedOwnedComponentDeclarationPlan],
        formerActual: RetainedLazyListActualAttachment, removalFacet: RetainedLazyListSourceFacetID
    ) {
        self.attempt = attempt
        self.member = member
        self.plans = plans
        self.formerActual = formerActual
        self.removalFacet = removalFacet
    }

    func suspendOwnedWrite() {
        guard case .slot(let permission) = member else { return }
        permission.pendingDepartures[ObjectIdentifier(self)] = RetainedOwnedPhysicalFacetKey(
            target: ObjectIdentifier(formerActual.target), attachment: ObjectIdentifier(formerActual.attachment),
            field: nil)
    }

    func finishOwnedWriteSuspension() {
        guard case .slot(let permission) = member else { return }
        permission.pendingDepartures.removeValue(forKey: ObjectIdentifier(self))
    }
}

/// Native owned-slot metadata is independent of effect-group completion. Its
/// exact field records survive partial adoption, with no application payload.
@MainActor
fileprivate final class RetainedOwnedComponentConstructionLedger {
    let attempt: RetainedLazyListAttemptID
    private var registrations: [RetainedOwnedComponentKey: [RetainedOwnedComponentRegistration]] = [:]
    private var sources: [RetainedOwnedComponentSource] = []
    private var componentParents: [RetainedOwnedComponentKey: RetainedOwnedComponentKey] = [:]
    private var regionSources: [RetainedOwnedComponentKey: RetainedOwnedRegionSource] = [:]
    private var deferredRegionBuilds: [RetainedOwnedDeferredRegionBuild] = []
    private var acceptedRegions: Set<ObjectIdentifier> = []
    private var hasAmbiguousDeferredRegion = false
    private var frozenPlans: [RetainedOwnedComponentDeclarationPlan]?
    private var planRegistrations: [ObjectIdentifier: RetainedOwnedComponentRegistration] = [:]
    private var selectedPlans: Set<ObjectIdentifier> = []
    private var didPrepare = false
    private var propertyPublications: [RetainedOwnedPropertyKey: RetainedOwnedPropertyPublication] = [:]
    private var insertions: [ObjectIdentifier: RetainedOwnedInsertionPublication] = [:]
    private var structuralPublications: [RetainedOwnedPropertyKey: RetainedOwnedPropertyPublication] = [:]
    private var insertedRegionPublications: [ObjectIdentifier: RetainedOwnedInsertionPublication] = [:]
    private var completedRegionPublications: [RetainedOwnedPropertyKey: RetainedOwnedPropertyPublication] = [:]
    private var declaredMarkerRetirements: [ObjectIdentifier: RetainedOwnedDeclaredMarkerRetirement] = [:]
    private var acceptedPermissions: Set<ObjectIdentifier> = []
    private var acceptedPresences: Set<ObjectIdentifier> = []
    private(set) var acceptedDeclarations: [RetainedOwnedComponentDeclarationFact] = []
    private(set) var retiredSlots: [RetainedOwnedSlotGenerationID] = []
    private(set) var retiredComponents: [RetainedOwnedComponentID] = []
    private var wasFinished = false

    init(attempt: RetainedLazyListAttemptID) { self.attempt = attempt }

    private enum PublicationResult {
        case domainChanged
        case published([RetainedOwnedComponentDeclarationPlan])
    }

    // Freeze fixes this provenance. Current permission/presence namespaces are
    // checked separately for every original candidate and outgoing target member.
    var hasRegionlessOrdinaryProvenance: Bool {
        guard didPrepare, !wasFinished, let frozenPlans,
            regionSources.isEmpty, deferredRegionBuilds.isEmpty,
            registrations.values.allSatisfy({ entries in
                entries.allSatisfy { registration in
                    if case .descriptor = registration.origin,
                        case .descriptor = registration.receipt.nativeLifetime
                    {
                        return !registration.isDeferredConstruction
                    }
                    return false
                }
            }),
            sources.allSatisfy({ source in
                source.deferredRoot == nil
                    && source.components.allSatisfy { component in
                        if case .descriptor = component { return true }
                        return false
                    }
            }),
            frozenPlans.allSatisfy({ plan in
                if case .descriptor = plan.origin, case .descriptor = plan.receipt.nativeLifetime {
                    return !plan.isDeferredConstruction && plan.structuralRegions.isEmpty
                }
                return false
            })
        else { return false }
        return true
    }

    private func isRegionlessOrdinaryPermission(_ permission: RetainedOwnedSlotPermission) -> Bool {
        guard case .descriptor = permission.lifetime else { return false }
        return permission.structuralFacets.keys.allSatisfy { $0.region == nil }
    }

    private func isRegionlessOrdinaryPresence(_ presence: RetainedOwnedComponentPresence) -> Bool {
        guard case .descriptor = presence.lifetime else { return false }
        return presence.deferredRegion == nil && presence.declaredRegions.isEmpty
            && presence.structuralFacets.keys.allSatisfy { $0.region == nil }
    }

    private func isRegionlessOrdinaryPublication(
        _ declarations: [RetainedOwnedComponentDeclarationPlan],
        on target: ViewNode, storage: RetainedLazyListNodeActivityStorage
    ) -> Bool {
        guard didPrepare, !wasFinished, regionSources.isEmpty, deferredRegionBuilds.isEmpty,
            declarations.allSatisfy({ plan in
                if case .descriptor = plan.origin, case .descriptor = plan.receipt.nativeLifetime {
                    return plan.structuralRegions.isEmpty && !plan.isDeferredConstruction
                        && isRegionlessOrdinaryPresence(plan.receipt.componentPresence)
                        && plan.receipt.slotPermissions.allSatisfy { isRegionlessOrdinaryPermission($0) }
                }
                return false
            }),
            target.retainedLazyListActivityStorage === storage,
            target.retainedLazyListAdapter == nil, target.retainedLazyListGap == nil,
            target.retainedLazyListRowChrome == nil,
            storage.sourceOutputs.isEmpty, storage.sourceDescriptor == nil,
            storage.acceptedLogicalDeclaration == nil, storage.committedContributions.isEmpty,
            storage.deferredSubtreeAnchor == nil, storage.ownedEmptyRowRevisions.isEmpty,
            storage.ownedDeferredRegions.isEmpty, storage.ownedRegionStructuralPermissions.isEmpty,
            storage.ownedRegionStructuralComponents.isEmpty,
            storage.ownedEmptyStructuralNamespaces.values.allSatisfy({ $0.regions.isEmpty }),
            storage.ownedDeclaredStructuralNamespaces.values.allSatisfy({ $0.regions.isEmpty })
        else { return false }
        let permissions =
            Array(storage.ownedPayloadPermissions.values) + [storage.ownedStructuralPermissions]
            + Array(storage.ownedEmptyStructuralPermissions.values)
            + Array(storage.ownedDeclaredStructuralPermissions.values)
        guard permissions.allSatisfy({ $0.allSatisfy { isRegionlessOrdinaryPermission($0) } }),
            storage.ownedScopeDeclaredSlots.values.allSatisfy({ entry in
                guard let permission = entry.permission else { return false }
                return isRegionlessOrdinaryPermission(permission)
            })
        else { return false }
        let presences =
            Array(storage.ownedPayloadComponents.values) + [storage.ownedStructuralComponents]
            + [Array(storage.ownedEmptyStructuralComponents.values)]
            + [Array(storage.ownedDeclaredStructuralComponents.values)]
        return presences.allSatisfy({ $0.allSatisfy { isRegionlessOrdinaryPresence($0) } })
            && storage.ownedScopeDeclaredComponents.values.allSatisfy { entry in
                guard let presence = entry.presence else { return false }
                return isRegionlessOrdinaryPresence(presence)
            }
    }

    private func successfulPermissions(
        _ original: [RetainedOwnedSlotPermission],
        declarations: [RetainedOwnedComponentDeclarationPlan]
    ) -> [RetainedOwnedSlotPermission] {
        let accepted = Set(
            declarations.flatMap { $0.receipt.slotPermissions.map { ObjectIdentifier($0) } })
        // The set supplies membership only. Keep original order and duplicates.
        return original.filter { accepted.contains(ObjectIdentifier($0)) }
    }

    private func selectedOrdinaryPlans(for source: ViewNode) -> [RetainedOwnedComponentDeclarationPlan]? {
        guard didPrepare, !wasFinished, !source.containsRejectedRetainedSource else { return nil }
        let payloads = Set(sources.filter { $0.node === source }.map { ObjectIdentifier($0.payload) })
        let needed =
            frozenPlans?.filter { plan in
                plan.sourcePayloads.contains { payloads.contains(ObjectIdentifier($0)) }
            } ?? []
        guard
            needed.allSatisfy({
                selectedPlans.contains(ObjectIdentifier($0))
                    && planRegistrations[ObjectIdentifier($0)]?.receipt === $0.receipt
            })
        else { return nil }
        return needed
    }

    private func ordinaryPermissions(
        in plans: [RetainedOwnedComponentDeclarationPlan]
    ) -> [RetainedOwnedSlotPermission] {
        var result: [RetainedOwnedSlotPermission] = []
        var seen: Set<ObjectIdentifier> = []
        for plan in plans where !plan.declarationOnly {
            for permission in plan.receipt.slotPermissions where seen.insert(ObjectIdentifier(permission)).inserted {
                result.append(permission)
            }
        }
        return result
    }

    func stageDeferredRegion(
        _ anchor: RetainedLazyListDeferredSubtreeAnchor, component: RetainedLazyListComponentID
    ) -> Bool {
        guard frozenPlans == nil, !wasFinished, anchor.isCurrent else { return false }
        if let region = anchor.ownedRegion {
            guard region.isDeclared, region.logicalMembership === anchor.logicalMembership,
                region.actual?.target === anchor.actual.target,
                region.actual?.attachment === anchor.actual.attachment,
                let stored = anchor.actual.node?.retainedLazyListActivityStorage?.ownedDeferredRegions[
                    ObjectIdentifier(region)], stored === region
            else { return false }
        } else {
            // Native-only rows without owned declarations need no facade region.
            // An existing owned row cannot substitute an attachment for one.
            guard
                !anchor.logicalMembership.ownedDeclaredComponents.values.contains(where: {
                    $0.presence?.hasDeclaredComponent == true
                })
            else { return false }
        }
        deferredRegionBuilds.append(
            RetainedOwnedDeferredRegionBuild(
                component: .lazy(ObjectIdentifier(component)), original: anchor,
                expectedRevision: anchor.ownedRegion?.revision))
        return true
    }

    func register(
        owner: RetainedOwnedComponentID, slots: [RetainedOwnedSlotGenerationID],
        continuing: [RetainedOwnedComponentReceipt], attribution: RetainedLazyListBuildAttribution,
        declarationOnly: Bool
    ) -> RetainedOwnedComponentReceipt? {
        let origin = RetainedOwnedComponentDeclarationOrigin.lazy(component: attribution.component)
        guard frozenPlans == nil, !wasFinished,
            attribution.descriptorBuildAttempt === attempt,
            registrations[origin.key]?.contains(where: { $0.receipt.owner === owner }) != true,
            !declarationOnly || admitsDeclaredContinuation(owner: owner, slots: slots, continuing: continuing),
            let receipt = RetainedOwnedComponentReceipt.register(
                owner: owner, slots: slots, continuing: continuing, lazyAttribution: attribution)
        else { return nil }
        let isDeferred: Bool
        switch attribution.origin {
        case .selectedRow: isDeferred = false
        case .deferredSubtree: isDeferred = true
        }
        return record(
            origin: origin, receipt: receipt, previous: continuing,
            declarationOnly: declarationOnly, isDeferredConstruction: isDeferred)
    }

    func register(
        owner: RetainedOwnedComponentID, slots: [RetainedOwnedSlotGenerationID],
        continuing: [RetainedOwnedComponentReceipt], attribution: RetainedDescriptorComponentAttribution,
        declarationOnly: Bool
    ) -> RetainedOwnedComponentReceipt? {
        let origin = RetainedOwnedComponentDeclarationOrigin.descriptor(component: attribution.component)
        guard frozenPlans == nil, !wasFinished, attribution.descriptorBuildAttempt === attempt,
            registrations[origin.key]?.contains(where: { $0.receipt.owner === owner }) != true,
            !declarationOnly || admitsDeclaredContinuation(owner: owner, slots: slots, continuing: continuing),
            let receipt = RetainedOwnedComponentReceipt.register(
                owner: owner, slots: slots, continuing: continuing, descriptorAttribution: attribution)
        else { return nil }
        return record(
            origin: origin, receipt: receipt, previous: continuing,
            declarationOnly: declarationOnly, isDeferredConstruction: false)
    }

    private func admitsDeclaredContinuation(
        owner: RetainedOwnedComponentID, slots: [RetainedOwnedSlotGenerationID],
        continuing: [RetainedOwnedComponentReceipt]
    ) -> Bool {
        guard !continuing.isEmpty,
            continuing.allSatisfy({ $0.owner === owner && $0.hasDeclaredComponent })
        else { return false }
        return slots.allSatisfy { slot in continuing.contains { $0.hasAcceptedOwnership(for: slot) } }
    }

    private func record(
        origin: RetainedOwnedComponentDeclarationOrigin, receipt: RetainedOwnedComponentReceipt,
        previous: [RetainedOwnedComponentReceipt], declarationOnly: Bool, isDeferredConstruction: Bool
    ) -> RetainedOwnedComponentReceipt? {
        guard registrations[origin.key]?.contains(where: { $0.receipt.owner === receipt.owner }) != true else {
            return nil
        }
        registrations[origin.key, default: []].append(
            RetainedOwnedComponentRegistration(
                origin: origin, receipt: receipt, previous: previous, declarationOnly: declarationOnly,
                isDeferredConstruction: isDeferredConstruction))
        return receipt
    }

    func freeze(
        sources: [RetainedOwnedComponentSource],
        componentParents: [RetainedOwnedComponentKey: RetainedOwnedComponentKey],
        excluding rejected: Set<RetainedOwnedComponentKey>
    ) -> [RetainedOwnedComponentDeclarationPlan] {
        if let frozenPlans { return frozenPlans }
        self.sources = sources
        self.componentParents = componentParents
        prepareRegionSources(excluding: rejected)
        var sourceIndex: RetainedOwnedComponentSourceIndex?
        var result: [RetainedOwnedComponentDeclarationPlan] = []
        for (key, values) in registrations where !rejected.contains(key) {
            let index: RetainedOwnedComponentSourceIndex
            if let existing = sourceIndex {
                index = existing
            } else {
                // Empty or wholly rejected registrations need no source index.
                index = RetainedOwnedComponentSourceIndex(sources: sources)
                sourceIndex = index
            }
            let sourceRoster = index.roster(for: key, in: sources)
            for registration in values {
                let previous = registration.previous
                let retained = registration.receipt.slots.filter { slot in
                    previous.contains { $0.permission(for: slot) != nil }
                }
                let introduced = registration.receipt.slots.filter { slot in
                    !previous.contains { $0.permission(for: slot) != nil }
                }
                var departed: [RetainedOwnedSlotGenerationID] = []
                for old in previous {
                    for slot in old.slots
                    where registration.receipt.permission(for: slot) == nil
                        && !departed.contains(where: { $0 === slot })
                    { departed.append(slot) }
                }
                guard
                    let plan = RetainedOwnedComponentDeclarationPlan(
                        origin: registration.origin, receipt: registration.receipt,
                        retained: retained, introduced: introduced, departed: departed,
                        sourcePayloads: sourceRoster.payloads, sourceFacets: sourceRoster.facets,
                        declarationOnly: registration.declarationOnly,
                        isDeferredConstruction: registration.isDeferredConstruction,
                        structuralRegions: structuralRegions(for: registration))
                else { continue }
                result.append(plan)
                planRegistrations[ObjectIdentifier(plan)] = registration
            }
        }
        frozenPlans = result
        return result
    }

    private func prepareRegionSources(excluding rejected: Set<RetainedOwnedComponentKey>) {
        let roots = Set(
            sources.compactMap { $0.deferredRoot.map { RetainedOwnedComponentKey.lazy(ObjectIdentifier($0)) } })
        var pendingRegions: [ObjectIdentifier: RetainedOwnedStructuralRegion] = [:]
        for root in roots where !rejected.contains(root) {
            let primary = registrations[root]?.filter { !$0.declarationOnly } ?? []
            guard primary.count <= 1 else {
                hasAmbiguousDeferredRegion = true
                continue
            }
            guard let registration = primary.first,
                case .lazy(let logical) = registration.receipt.nativeLifetime
            else { continue }
            let nodes = deferredSources(for: root)
            guard nodes.count == 1, let source = nodes.first else {
                hasAmbiguousDeferredRegion = true
                continue
            }
            let presence = registration.receipt.componentPresence
            let region =
                presence.deferredRegion
                ?? pendingRegions[ObjectIdentifier(presence.owner)]
                ?? RetainedOwnedStructuralRegion(boundary: presence, logicalMembership: logical)
            guard !region.wasRevoked, region.boundary === presence, region.logicalMembership === logical else {
                hasAmbiguousDeferredRegion = true
                continue
            }
            pendingRegions[ObjectIdentifier(presence.owner)] = region
            regionSources[root] = RetainedOwnedRegionSource(component: root, region: region, source: source)
        }
        for build in deferredRegionBuilds {
            guard let region = build.original.ownedRegion else { continue }
            let existing = regionSources.values.filter { $0.region.owner === region.owner }
            var nodes = existing.isEmpty ? deferredSources(for: build.component) : []
            for binding in existing {
                if let source = binding.source, !nodes.contains(where: { $0 === source }) { nodes.append(source) }
            }
            guard !rejected.contains(build.component), nodes.count == 1, let source = nodes.first,
                regionSources[build.component].map({ $0.region.owner === region.owner }) != false
            else {
                hasAmbiguousDeferredRegion = true
                continue
            }
            regionSources[build.component] =
                RetainedOwnedRegionSource(component: build.component, region: region, source: source)
        }
        // A single owner has one deferred child namespace. Multiple native
        // readers for that owner require a separate explicit namespace API.
        var owners: [ObjectIdentifier: ViewNode] = [:]
        for binding in regionSources.values {
            guard let source = binding.source else { continue }
            let owner = ObjectIdentifier(binding.region.owner)
            if let previous = owners[owner], previous !== source { hasAmbiguousDeferredRegion = true }
            owners[owner] = source
        }
    }

    private func deferredSources(for component: RetainedOwnedComponentKey) -> [ViewNode] {
        var nodes: [ViewNode] = []
        for source in sources where source.components.first?.key == component {
            guard let node = source.node, node.geometryReaderBuild != nil,
                !nodes.contains(where: { $0 === node })
            else { continue }
            nodes.append(node)
        }
        return nodes
    }

    private func structuralRegions(
        for registration: RetainedOwnedComponentRegistration
    ) -> [RetainedOwnedStructuralRegion] {
        let presence = registration.receipt.componentPresence
        if registration.declarationOnly {
            let existing = presence.declaredRegions.values.filter(\.isDeclared)
            if !existing.isEmpty { return existing }
        }
        var component: RetainedOwnedComponentKey? = registration.origin.key
        var visited: Set<RetainedOwnedComponentKey> = []
        while let current = component, visited.count < ViewNode.maximumTraversalDepth {
            guard visited.insert(current).inserted else {
                hasAmbiguousDeferredRegion = true
                return []
            }
            if let binding = regionSources[current], binding.region.owner !== presence.owner {
                return [binding.region]
            }
            component = componentParents[current]
        }
        if component != nil { hasAmbiguousDeferredRegion = true }
        if deferredRegionBuilds.contains(where: { $0.original.ownedRegion?.owner === presence.owner }) {
            return presence.declaredRegions.values.filter(\.isDeclared)
        }
        return []
    }

    private func prepareRegionPublications(
        from source: ViewNode, to target: ViewNode
    ) -> [RetainedOwnedRegionPublication]? {
        var publications: [RetainedOwnedRegionPublication] = []
        var seen: Set<ObjectIdentifier> = []
        for binding in regionSources.values where binding.source === source {
            let region = binding.region
            guard seen.insert(ObjectIdentifier(region)).inserted else { continue }
            guard !region.wasRevoked, !region.owner.wasRevoked, region.revision < .max else { return nil }
            if let current = region.actual, current.isAttached, current.node !== target { return nil }
            let declarations =
                frozenPlans?.filter {
                    $0.structuralRegions.contains(where: { $0 === region })
                } ?? []
            guard
                declarations.allSatisfy({
                    selectedPlans.contains(ObjectIdentifier($0)) && !$0.receipt.owner.wasRevoked
                        && $0.receipt.slotPermissions.allSatisfy { !$0.wasRevoked }
                })
            else { return nil }
            var rosters: [ObjectIdentifier: Set<ObjectIdentifier>] = [:]
            for plan in declarations {
                let owner = ObjectIdentifier(plan.receipt.owner)
                let slots = Set(plan.receipt.slotPermissions.map { ObjectIdentifier($0) })
                if let previous = rosters[owner], previous != slots { return nil }
                rosters[owner] = slots
            }
            publications.append(
                RetainedOwnedRegionPublication(
                    region: region, expectedRevision: region.revision, declarations: declarations))
        }
        for build in deferredRegionBuilds where build.original.actual.node === target {
            if let region = build.original.ownedRegion,
                !publications.contains(where: { $0.region === region })
            {
                return nil
            }
        }
        return publications
    }

    func acceptedDeferredRegion(
        component: RetainedLazyListComponentID, actual: RetainedLazyListActualAttachment
    ) -> RetainedOwnedStructuralRegion? {
        guard let binding = regionSources[.lazy(ObjectIdentifier(component))], binding.region.isDeclared,
            binding.region.actual?.target === actual.target,
            binding.region.actual?.attachment === actual.attachment,
            let stored = actual.node?.retainedLazyListActivityStorage?.ownedDeferredRegions[
                ObjectIdentifier(binding.region)],
            stored === binding.region
        else { return nil }
        return binding.region
    }

    func hasDeferredRegionSource(component: RetainedLazyListComponentID) -> Bool {
        regionSources[.lazy(ObjectIdentifier(component))] != nil
    }

    func hasAcceptedDeferredRegion(at actual: RetainedLazyListActualAttachment) -> Bool {
        for build in deferredRegionBuilds where build.original.actual.node === actual.node {
            guard build.original.actual.target === actual.target,
                build.original.actual.attachment === actual.attachment
            else { return false }
            if let region = build.original.ownedRegion {
                guard acceptedRegions.contains(ObjectIdentifier(region)), region.isDeclared,
                    region.actual?.target === actual.target, region.actual?.attachment === actual.attachment
                else { return false }
            }
        }
        return true
    }

    /// A deferred build replaces its exact native namespace, never the entire
    /// logical row. Eager row replacement still needs checked completion of all
    /// its source roots before recordCompletedRow may replace the row table.
    func admitsPreparedRows(
        _ rows: [RetainedLazyListBuildAttribution], plans: [RetainedOwnedComponentDeclarationPlan]
    ) -> Bool {
        for row in rows {
            switch row.origin {
            case .selectedRow: continue
            case .deferredSubtree(let original):
                guard
                    let build = deferredRegionBuilds.first(where: {
                        $0.component == .lazy(ObjectIdentifier(row.component))
                    }), build.original.contribution === original, build.original.isCurrent
                else { return false }
                if let region = build.original.ownedRegion {
                    guard region.isDeclared, region.revision == build.expectedRevision,
                        let source = regionSources[build.component], source.region === region, source.source != nil
                    else { return false }
                } else if plans.contains(where: { $0.receipt.belongs(to: row.logicalMembership) }) {
                    return false
                }
            }
        }
        return !hasAmbiguousDeferredRegion
    }

    func prepare(_ plans: [RetainedOwnedComponentDeclarationPlan]) -> Bool {
        guard !didPrepare, !wasFinished, !hasAmbiguousDeferredRegion, let frozenPlans else { return false }
        let known = Set(frozenPlans.map { ObjectIdentifier($0) })
        let proposed = Set(plans.map { ObjectIdentifier($0) })
        guard proposed.count == plans.count, proposed.isSubset(of: known),
            plans.allSatisfy({ plan in
                planRegistrations[ObjectIdentifier(plan)]?.receipt === plan.receipt
                    && plan.receipt.slotPermissions.allSatisfy { !$0.wasRevoked }
            })
        else { return false }
        selectedPlans = proposed
        didPrepare = true
        return true
    }

    private func plans(for source: ViewNode) -> [RetainedOwnedComponentDeclarationPlan]? {
        guard didPrepare, !wasFinished, !source.containsRejectedRetainedSource else { return nil }
        let payloads = Set(sources.filter { $0.node === source }.map { ObjectIdentifier($0.payload) })
        let needed =
            frozenPlans?.filter { plan in
                plan.sourcePayloads.contains { payloads.contains(ObjectIdentifier($0)) }
            } ?? []
        guard
            needed.allSatisfy({
                selectedPlans.contains(ObjectIdentifier($0)) && !$0.receipt.owner.wasRevoked
                    && $0.receipt.slotPermissions.allSatisfy { !$0.wasRevoked }
            })
        else { return nil }
        return needed
    }

    private func permissions(for source: ViewNode, includingDeclarations: Bool = true) -> [RetainedOwnedSlotPermission]?
    {
        guard let plans = plans(for: source) else { return nil }
        var result: [RetainedOwnedSlotPermission] = []
        var seen: Set<ObjectIdentifier> = []
        for plan in plans where includingDeclarations || !plan.declarationOnly {
            for permission in plan.receipt.slotPermissions where seen.insert(ObjectIdentifier(permission)).inserted {
                result.append(permission)
            }
        }
        return result
    }

    func preparePropertyCopy(from source: ViewNode, to target: ViewNode, keyPath: PartialKeyPath<ViewNode>) -> Bool {
        guard let allDeclarations = plans(for: source),
            let permissions = permissions(for: source, includingDeclarations: false),
            let runtime = target.retainedLazyListRuntime,
            target.isRetainedLazyListAttached(in: runtime)
        else { return false }
        let storage = target.lazyListActivityStorage()
        guard
            sources.contains(where: { $0.node === source })
                || (storage.ownedPayloadPermissions.isEmpty && storage.ownedStructuralPermissions.isEmpty)
        else { return false }
        let key = RetainedOwnedPropertyKey(
            source: ObjectIdentifier(source), target: ObjectIdentifier(target), field: keyPath)
        let declarations = allDeclarations.filter { !$0.declarationOnly }
        propertyPublications[key] = RetainedOwnedPropertyPublication(
            source: source, target: target, targetID: storage.targetID, attachmentID: storage.attachmentID,
            permissions: permissions, hasPayload: source.retainedSourcePayloadFields.contains(keyPath),
            declarations: declarations)
        return true
    }

    func recordAcceptedProperty(
        from source: ViewNode, to target: ViewNode, keyPath: PartialKeyPath<ViewNode>,
        ordinaryPublication: () -> Bool = { false }
    ) {
        let key = RetainedOwnedPropertyKey(
            source: ObjectIdentifier(source), target: ObjectIdentifier(target), field: keyPath)
        guard let publication = propertyPublications.removeValue(forKey: key),
            publication.source === source, publication.target === target,
            let storage = target.retainedLazyListActivityStorage,
            storage.targetID === publication.targetID, storage.attachmentID === publication.attachmentID,
            let runtime = target.retainedLazyListRuntime
        else { return }
        let actual = storage.captureActualAttachment(of: target, in: runtime)
        if ordinaryPublication(),
            isRegionlessOrdinaryPublication(publication.declarations, on: target, storage: storage)
        {
            func originalTargetMatches() -> Bool {
                publication.source === source && publication.target === target
                    && target.retainedLazyListActivityStorage === storage
                    && storage.targetID === publication.targetID && storage.attachmentID === publication.attachmentID
                    && target.retainedLazyListRuntime === runtime
            }
            let result = publish(
                publication.declarations, actual: actual, source: source,
                facet: publication.facet, kind: .sourceField,
                ordinaryDomainStillMatches: {
                    ordinaryPublication() && originalTargetMatches()
                        && self.isRegionlessOrdinaryPublication(
                            publication.declarations, on: target, storage: storage)
                })
            switch result {
            case .domainChanged:
                // No plan was published. Fall through with the same consumed
                // preparation only if its original physical binding still holds.
                guard originalTargetMatches() else { return }
            case .published(let declarations):
                let permissions = successfulPermissions(publication.permissions, declarations: declarations)
                replaceStructural(on: storage, actual: actual, with: permissions)
                replacePayload(
                    on: storage, actual: actual, field: keyPath,
                    with: publication.hasPayload ? permissions : [])
                replaceComponents(
                    on: storage, actual: actual, field: keyPath,
                    with: declarations.map { $0.receipt.componentPresence }, hasPayload: publication.hasPayload)
                fulfillDeclaredMarkerRetirements(declarations, source: source, storage: storage, actual: actual)
                return
            }
        }
        // Incoming exact generations become authoritative before retiring the
        // last outgoing payload reference and before its capture can deinit.
        publish(
            publication.declarations, actual: actual, source: source, facet: publication.facet, kind: .sourceField)
        // Publish only this accepted source/target declaration marker. Other
        // outputs retain their own structural references through a partial stop.
        replaceStructural(on: storage, actual: actual, with: publication.permissions)
        replacePayload(
            on: storage, actual: actual, field: keyPath,
            with: publication.hasPayload ? publication.permissions : [])
        replaceComponents(
            on: storage, actual: actual, field: keyPath,
            with: publication.declarations.map { $0.receipt.componentPresence },
            hasPayload: publication.hasPayload)
        fulfillDeclaredMarkerRetirements(
            publication.declarations, source: source, storage: storage, actual: actual)
    }

    func prepareInsertedNode(from source: ViewNode) -> Bool {
        guard let allDeclarations = plans(for: source),
            let permissions = permissions(for: source, includingDeclarations: false),
            let regions = prepareRegionPublications(from: source, to: source)
        else { return false }
        let declarations = allDeclarations.filter { !$0.declarationOnly }
        let storage = source.lazyListActivityStorage()
        insertions[ObjectIdentifier(storage.targetID)] = RetainedOwnedInsertionPublication(
            source: source, targetID: storage.targetID, attachmentID: storage.attachmentID,
            permissions: permissions, declarations: declarations, regions: regions,
            expectedStructuralRevision: storage.ownedDeclaredStructuralRevision)
        return true
    }

    func recordAcceptedInsertedNode(on node: ViewNode, ordinaryPublication: () -> Bool = { false }) {
        let storage = node.lazyListActivityStorage()
        guard let publication = insertions.removeValue(forKey: ObjectIdentifier(storage.targetID)),
            publication.source === node, publication.targetID === storage.targetID,
            publication.attachmentID === storage.attachmentID,
            let runtime = node.retainedLazyListRuntime
        else { return }
        let actual = storage.captureActualAttachment(of: node, in: runtime)
        if ordinaryPublication(),
            isRegionlessOrdinaryPublication(publication.declarations, on: node, storage: storage)
        {
            func originalTargetMatches() -> Bool {
                publication.source === node && node.retainedLazyListActivityStorage === storage
                    && publication.targetID === storage.targetID && publication.attachmentID === storage.attachmentID
                    && node.retainedLazyListRuntime === runtime
            }
            let result = publish(
                publication.declarations, actual: actual, source: node, facet: nil, kind: .structuralEntry,
                ordinaryDomainStillMatches: {
                    ordinaryPublication() && originalTargetMatches()
                        && self.isRegionlessOrdinaryPublication(
                            publication.declarations, on: node, storage: storage)
                })
            switch result {
            case .domainChanged:
                guard originalTargetMatches() else { return }
            case .published(let declarations):
                let permissions = successfulPermissions(publication.permissions, declarations: declarations)
                for field in node.retainedSourcePayloadFields {
                    replacePayload(on: storage, actual: actual, field: field, with: permissions)
                    replaceComponents(
                        on: storage, actual: actual, field: field,
                        with: declarations.map { $0.receipt.componentPresence }, hasPayload: true)
                }
                replaceStructural(on: storage, actual: actual, with: permissions)
                replaceComponentStructural(
                    on: storage, actual: actual, with: declarations.map { $0.receipt.componentPresence })
                fulfillDeclaredMarkerRetirements(declarations, source: node, storage: storage, actual: actual)
                // Original regionless provenance makes the region queue empty.
                return
            }
        }
        publish(publication.declarations, actual: actual, source: node, facet: nil, kind: .structuralEntry)
        // Refused activation cannot supply a physical owned footprint. Recheck
        // after publish's weak-source scan before assigning the prepared members.
        guard
            publication.declarations.allSatisfy({
                !$0.receipt.owner.wasRevoked && $0.receipt.nativeLifetime.permitsConstruction
                    && $0.receipt.slotPermissions.allSatisfy { !$0.wasRevoked }
            })
        else { return }
        // Presence inspection reads native stored fields only, immediately after
        // the exact object attachment and before controller/appear callbacks.
        for field in node.retainedSourcePayloadFields {
            replacePayload(on: storage, actual: actual, field: field, with: publication.permissions)
            replaceComponents(
                on: storage, actual: actual, field: field,
                with: publication.declarations.map { $0.receipt.componentPresence }, hasPayload: true)
        }
        replaceStructural(on: storage, actual: actual, with: publication.permissions)
        replaceComponentStructural(
            on: storage, actual: actual, with: publication.declarations.map { $0.receipt.componentPresence })
        fulfillDeclaredMarkerRetirements(
            publication.declarations, source: node, storage: storage, actual: actual)
        if !publication.regions.isEmpty {
            insertedRegionPublications[ObjectIdentifier(storage.targetID)] = publication
        }
    }

    func recordCompletedNode(
        from source: ViewNode, to target: ViewNode, ordinaryPublication: () -> Bool = { false }
    ) {
        if recordRegionlessOrdinaryCompletion(
            from: source, to: target, ordinaryPublication: ordinaryPublication)
        {
            return
        }
        guard let allDeclarations = plans(for: source),
            let permissions = permissions(for: source, includingDeclarations: false),
            let runtime = target.retainedLazyListRuntime
        else { return }
        let storage = target.lazyListActivityStorage()
        let actual = storage.captureActualAttachment(of: target, in: runtime)
        let declarations = allDeclarations.filter { !$0.declarationOnly }
        publish(declarations, actual: actual, source: source, facet: nil, kind: .structuralEntry)
        guard
            declarations.allSatisfy({
                !$0.receipt.owner.wasRevoked && $0.receipt.nativeLifetime.permitsConstruction
                    && $0.receipt.slotPermissions.allSatisfy { !$0.wasRevoked }
            })
        else { return }
        replaceStructural(on: storage, actual: actual, with: permissions)
        replaceComponentStructural(
            on: storage, actual: actual, with: declarations.map { $0.receipt.componentPresence })
        fulfillDeclaredMarkerRetirements(declarations, source: source, storage: storage, actual: actual)
        publishCompletedRegions(from: source, to: target, storage: storage, actual: actual)
    }

    // False means the caller must run the untouched legacy lookup, never reuse
    // this path's relaxed candidates after a domain change.
    private func recordRegionlessOrdinaryCompletion(
        from source: ViewNode, to target: ViewNode, ordinaryPublication: () -> Bool
    ) -> Bool {
        guard ordinaryPublication(), let storage = target.retainedLazyListActivityStorage,
            isRegionlessOrdinaryPublication([], on: target, storage: storage)
        else { return false }
        guard let allDeclarations = selectedOrdinaryPlans(for: source),
            let runtime = target.retainedLazyListRuntime
        else { return true }
        guard isRegionlessOrdinaryPublication(allDeclarations, on: target, storage: storage) else { return false }
        let originalPermissions = ordinaryPermissions(in: allDeclarations)
        let declarations = allDeclarations.filter { !$0.declarationOnly }
        let actual = storage.captureActualAttachment(of: target, in: runtime)
        let result = publish(
            declarations, actual: actual, source: source, facet: nil, kind: .structuralEntry,
            ordinaryDomainStillMatches: {
                ordinaryPublication() && target.retainedLazyListActivityStorage === storage
                    && storage.targetID === actual.target && storage.attachmentID === actual.attachment
                    && target.retainedLazyListRuntime === runtime
                    && self.isRegionlessOrdinaryPublication(allDeclarations, on: target, storage: storage)
            })
        switch result {
        case .domainChanged:
            return false
        case .published(let accepted):
            let permissions = successfulPermissions(originalPermissions, declarations: accepted)
            replaceStructural(on: storage, actual: actual, with: permissions)
            replaceComponentStructural(
                on: storage, actual: actual, with: accepted.map { $0.receipt.componentPresence })
            fulfillDeclaredMarkerRetirements(accepted, source: source, storage: storage, actual: actual)
            publishCompletedRegions(from: source, to: target, storage: storage, actual: actual)
            return true
        }
    }

    func prepareStructuralDeclaration(from source: ViewNode, to target: ViewNode) -> Bool {
        guard let plans = plans(for: source), let runtime = target.retainedLazyListRuntime,
            target.isRetainedLazyListAttached(in: runtime),
            let regions = prepareRegionPublications(from: source, to: target)
        else { return false }
        let storage = target.lazyListActivityStorage()
        let declarations = plans.filter(\.declarationOnly)
        guard storage.ownedDeclaredStructuralRevision < .max else { return false }
        var rosters: [ObjectIdentifier: [RetainedOwnedSlotPermission]] = [:]
        for plan in declarations {
            let owner = ObjectIdentifier(plan.receipt.owner)
            let incoming = plan.receipt.slotPermissions
            if let previous = rosters[owner] {
                guard Set(previous.map { ObjectIdentifier($0) }) == Set(incoming.map { ObjectIdentifier($0) }) else {
                    return false
                }
            } else {
                rosters[owner] = incoming
            }
        }
        let key = RetainedOwnedPropertyKey(
            source: ObjectIdentifier(source), target: ObjectIdentifier(target), field: \ViewNode.children)
        structuralPublications[key] = RetainedOwnedPropertyPublication(
            source: source, target: target, targetID: storage.targetID, attachmentID: storage.attachmentID,
            permissions: declarations.flatMap { $0.receipt.slotPermissions }, hasPayload: false,
            declarations: declarations, expectedStructuralRevision: storage.ownedDeclaredStructuralRevision,
            regions: regions)
        return true
    }

    /// The caller has published the complete checked children field for this
    /// source parent, including an exact unchanged field. Intermediate child
    /// arrays and scalar-property copies are not declaration publications.
    func recordAcceptedStructuralDeclaration(
        from source: ViewNode, to target: ViewNode, ordinaryPublication: () -> Bool = { false }
    ) -> RetainedLazyListActualAttachment? {
        let key = RetainedOwnedPropertyKey(
            source: ObjectIdentifier(source), target: ObjectIdentifier(target), field: \ViewNode.children)
        guard let publication = structuralPublications.removeValue(forKey: key),
            publication.source === source, publication.target === target,
            let storage = target.retainedLazyListActivityStorage,
            storage.targetID === publication.targetID, storage.attachmentID === publication.attachmentID,
            let expectedRevision = publication.expectedStructuralRevision,
            storage.ownedDeclaredStructuralRevision == expectedRevision, expectedRevision < .max,
            let runtime = target.retainedLazyListRuntime
        else { return nil }
        let actual = storage.captureActualAttachment(of: target, in: runtime)
        if ordinaryPublication(),
            isRegionlessOrdinaryPublication(publication.declarations, on: target, storage: storage)
        {
            func originalTargetMatches() -> Bool {
                publication.source === source && publication.target === target
                    && target.retainedLazyListActivityStorage === storage
                    && storage.targetID === publication.targetID && storage.attachmentID === publication.attachmentID
                    && storage.ownedDeclaredStructuralRevision == expectedRevision && expectedRevision < .max
                    && target.retainedLazyListRuntime === runtime
            }
            let result = publish(
                publication.declarations, actual: actual, source: source,
                facet: publication.facet, kind: .structuralEntry,
                ordinaryDomainStillMatches: {
                    ordinaryPublication() && originalTargetMatches()
                        && self.isRegionlessOrdinaryPublication(
                            publication.declarations, on: target, storage: storage)
                })
            switch result {
            case .domainChanged:
                guard originalTargetMatches() else { return nil }
            case .published(let declarations):
                let permissions = successfulPermissions(publication.permissions, declarations: declarations)
                let oldPermissions = storage.ownedDeclaredStructuralPermissions.values.flatMap { $0 }
                let oldPresences = Array(storage.ownedDeclaredStructuralComponents.values)
                storage.ownedDeclaredStructuralPermissions.removeAll()
                storage.ownedDeclaredStructuralComponents.removeAll()
                storage.ownedDeclaredStructuralNamespaces.removeAll()
                for plan in declarations {
                    let owner = ObjectIdentifier(plan.receipt.owner)
                    storage.ownedDeclaredStructuralPermissions[owner] = plan.receipt.slotPermissions
                    storage.ownedDeclaredStructuralComponents[owner] = plan.receipt.componentPresence
                    storage.ownedDeclaredStructuralNamespaces[owner, default: RetainedOwnedMarkerNamespaces()].include(
                        plan.structuralRegions)
                }
                storage.ownedDeclaredStructuralRevision = expectedRevision + 1
                let facetKey = RetainedOwnedPhysicalFacetKey(
                    target: ObjectIdentifier(storage.targetID), attachment: ObjectIdentifier(storage.attachmentID),
                    field: nil)
                for permission in permissions { permission.structuralFacets[facetKey] = actual }
                for presence in storage.ownedDeclaredStructuralComponents.values {
                    presence.structuralFacets[facetKey] = actual
                }
                for old in oldPermissions where !permissions.contains(where: { $0 === old }) {
                    removeStructuralReference(old, storage: storage, key: facetKey)
                    deferDeclaredMarkerRetirement(.slot(old), formerActual: actual, removalFacet: publication.facet)
                    retireIfUnreferenced(old, preservingCold: false)
                }
                for old in oldPresences
                where storage.ownedDeclaredStructuralComponents[ObjectIdentifier(old.owner)] !== old {
                    removeComponentStructuralReference(old, storage: storage, key: facetKey)
                    deferDeclaredMarkerRetirement(
                        .component(old), formerActual: actual, removalFacet: publication.facet)
                    retireIfUnreferenced(old, preservingCold: false)
                }
                return actual
            }
        }
        publish(
            publication.declarations, actual: actual, source: source,
            facet: publication.facet, kind: .structuralEntry)
        let oldPermissions = storage.ownedDeclaredStructuralPermissions.values.flatMap { $0 }
        let oldPresences = Array(storage.ownedDeclaredStructuralComponents.values)
        storage.ownedDeclaredStructuralPermissions.removeAll()
        storage.ownedDeclaredStructuralComponents.removeAll()
        storage.ownedDeclaredStructuralNamespaces.removeAll()
        for plan in publication.declarations {
            let owner = ObjectIdentifier(plan.receipt.owner)
            storage.ownedDeclaredStructuralPermissions[owner] = plan.receipt.slotPermissions
            storage.ownedDeclaredStructuralComponents[owner] = plan.receipt.componentPresence
            storage.ownedDeclaredStructuralNamespaces[owner, default: RetainedOwnedMarkerNamespaces()].include(
                plan.structuralRegions)
        }
        storage.ownedDeclaredStructuralRevision = expectedRevision + 1
        let facetKey = RetainedOwnedPhysicalFacetKey(
            target: ObjectIdentifier(storage.targetID), attachment: ObjectIdentifier(storage.attachmentID), field: nil)
        for permission in publication.permissions { permission.structuralFacets[facetKey] = actual }
        for presence in storage.ownedDeclaredStructuralComponents.values {
            presence.structuralFacets[facetKey] = actual
        }
        for old in oldPermissions where !publication.permissions.contains(where: { $0 === old }) {
            removeStructuralReference(old, storage: storage, key: facetKey)
            deferDeclaredMarkerRetirement(.slot(old), formerActual: actual, removalFacet: publication.facet)
            retireIfUnreferenced(old, preservingCold: false)
        }
        for old in oldPresences where storage.ownedDeclaredStructuralComponents[ObjectIdentifier(old.owner)] !== old {
            removeComponentStructuralReference(old, storage: storage, key: facetKey)
            deferDeclaredMarkerRetirement(.component(old), formerActual: actual, removalFacet: publication.facet)
            retireIfUnreferenced(old, preservingCold: false)
        }
        if !publication.regions.isEmpty { completedRegionPublications[key] = publication }
        return actual
    }

    private func isSelectedNormalContinuation(_ plan: RetainedOwnedComponentDeclarationPlan) -> Bool {
        didPrepare && !wasFinished && !plan.declarationOnly && !plan.sourcePayloads.isEmpty
            && selectedPlans.contains(ObjectIdentifier(plan))
            && planRegistrations[ObjectIdentifier(plan)]?.receipt === plan.receipt
            && plan.receipt.componentPresence.hasDeclaredComponent
            && plan.receipt.nativeLifetime.permitsDeclaredWrite
            && plan.receipt.slotPermissions.allSatisfy { !$0.wasRevoked }
    }

    private func deferDeclaredMarkerRetirement(
        _ member: RetainedOwnedDeclaredMarkerRetirement.Member,
        formerActual: RetainedLazyListActualAttachment, removalFacet: RetainedLazyListSourceFacetID
    ) {
        guard formerActual.isAttached, member.canContinue, !member.hasAttachedFootprint,
            declaredMarkerRetirements[member.identity] == nil
        else { return }
        let witnesses = (frozenPlans ?? []).filter { member.isNamed(by: $0) && isSelectedNormalContinuation($0) }
        guard !witnesses.isEmpty else { return }
        let ticket = RetainedOwnedDeclaredMarkerRetirement(
            attempt: attempt, member: member, plans: witnesses, formerActual: formerActual,
            removalFacet: removalFacet)
        declaredMarkerRetirements[member.identity] = ticket
        ticket.suspendOwnedWrite()
    }

    private func awaitsDeclaredMarkerReplacement(_ member: ObjectIdentifier) -> Bool {
        guard let ticket = declaredMarkerRetirements[member], !ticket.wasConsumed,
            ticket.attempt === attempt, ticket.member.canContinue
        else { return false }
        return ticket.plans.contains { isSelectedNormalContinuation($0) }
    }

    /// Only the original accepted normal publication can finish its ticket.
    /// Row tables, dormant declarations, and a later source with the same owner
    /// do not substitute for the frozen source and exact stored member marker.
    private func fulfillDeclaredMarkerRetirements(
        _ declarations: [RetainedOwnedComponentDeclarationPlan], source: ViewNode,
        storage: RetainedLazyListNodeActivityStorage, actual: RetainedLazyListActualAttachment
    ) {
        guard actual.isAttached, actual.node?.retainedLazyListActivityStorage === storage,
            actual.target === storage.targetID, actual.attachment === storage.attachmentID,
            !source.containsRejectedRetainedSource
        else { return }
        let payloads = sources.filter { $0.node === source }.map(\.payload)
        for ticket in declaredMarkerRetirements.values
        where awaitsDeclaredMarkerReplacement(ticket.member.identity) && ticket.member.hasNormalMarker(on: storage) {
            guard
                ticket.plans.contains(where: { plan in
                    isSelectedNormalContinuation(plan) && declarations.contains(where: { $0 === plan })
                        && plan.sourcePayloads.contains { expected in payloads.contains { $0 === expected } }
                })
            else { continue }
            ticket.wasConsumed = true
            ticket.finishOwnedWriteSuspension()
        }
    }

    func finishPendingDeclaredMarkerRetirements() {
        for ticket in declaredMarkerRetirements.values where !ticket.wasConsumed {
            // Mark it spent before retirement so no helper can defer it again.
            // Keep the original member entry until finish; reentry cannot rearm
            // this journal's already claimed handoff after an accepted prefix.
            ticket.wasConsumed = true
            switch ticket.member {
            case .slot(let permission): retireIfUnreferenced(permission, preservingCold: false)
            case .component(let presence): retireIfUnreferenced(presence, preservingCold: false)
            }
            ticket.finishOwnedWriteSuspension()
        }
    }

    private func publishCompletedRegions(
        from source: ViewNode, to target: ViewNode, storage: RetainedLazyListNodeActivityStorage,
        actual: RetainedLazyListActualAttachment
    ) {
        let key = RetainedOwnedPropertyKey(
            source: ObjectIdentifier(source), target: ObjectIdentifier(target), field: \ViewNode.children)
        let inserted = insertedRegionPublications.removeValue(forKey: ObjectIdentifier(storage.targetID))
        if let publication = completedRegionPublications.removeValue(forKey: key) {
            guard publication.source === source, publication.target === target,
                publication.targetID === storage.targetID, publication.attachmentID === storage.attachmentID,
                let revision = publication.expectedStructuralRevision, revision < .max,
                storage.ownedDeclaredStructuralRevision == revision + 1
            else { return }
            publishRegions(publication.regions, on: storage, actual: actual, source: source)
        } else if let publication = inserted,
            publication.source === source, source === target,
            publication.targetID === storage.targetID, publication.attachmentID === storage.attachmentID,
            publication.expectedStructuralRevision == storage.ownedDeclaredStructuralRevision
        {
            publishRegions(publication.regions, on: storage, actual: actual, source: source)
        }
        // A final children field is necessary but not sufficient to prune a
        // deferred namespace: completion also proves every source descendant
        // was visited. An interrupted insertion leaves the old table intact.
    }

    func recordAcceptedEmpty(
        origin: RetainedOwnedComponentDeclarationOrigin, anchor: RetainedLazyListActualAttachment
    ) {
        guard didPrepare, !wasFinished, anchor.isAttached,
            let storage = anchor.node?.lazyListActivityStorage()
        else { return }
        let exact = frozenPlans?.filter { $0.origin.key == origin.key && $0.sourcePayloads.isEmpty } ?? []
        guard exact.allSatisfy({ selectedPlans.contains(ObjectIdentifier($0)) }) else { return }
        var memberships: [ObjectIdentifier: RetainedLazyListMembershipID] = [:]
        for plan in exact {
            if case .lazy(let logical) = plan.receipt.nativeLifetime {
                let identifier = ObjectIdentifier(logical.id)
                guard (storage.ownedEmptyRowRevisions[identifier]?.value ?? 0) < .max else { return }
                memberships[identifier] = logical.id
            }
        }
        publish(exact, actual: anchor, source: nil, facet: nil, kind: .emptyStructuralEntry)
        for plan in exact {
            let owner = ObjectIdentifier(plan.receipt.owner)
            let previous = storage.ownedEmptyStructuralPermissions[owner] ?? []
            let next = plan.receipt.slotPermissions
            storage.ownedEmptyStructuralPermissions[owner] = next
            let key = RetainedOwnedPhysicalFacetKey(
                target: ObjectIdentifier(storage.targetID), attachment: ObjectIdentifier(storage.attachmentID),
                field: nil)
            for permission in next { permission.structuralFacets[key] = anchor }
            for permission in previous where !next.contains(where: { $0 === permission }) {
                removeStructuralReference(permission, storage: storage, key: key)
                retireIfUnreferenced(permission, preservingCold: false)
            }
            let presence = plan.receipt.componentPresence
            storage.ownedEmptyStructuralComponents[owner] = presence
            storage.ownedEmptyStructuralNamespaces[owner, default: RetainedOwnedMarkerNamespaces()].include(
                plan.structuralRegions)
            presence.structuralFacets[key] = anchor
        }
        for membership in memberships.values { advanceEmptyRowRevision(on: storage, membership: membership) }
    }

    private func advanceEmptyRowRevision(
        on storage: RetainedLazyListNodeActivityStorage, membership: RetainedLazyListMembershipID
    ) {
        let identifier = ObjectIdentifier(membership)
        let value = storage.ownedEmptyRowRevisions[identifier]?.value ?? 0
        guard value < .max else { return }
        storage.ownedEmptyRowRevisions[identifier] =
            RetainedOwnedEmptyRowRevision(membership: membership, value: value + 1)
    }

    func recordAcceptedEmptyRowMarkers(_ markers: [RetainedOwnedEmptyRowMarker]) {
        for marker in markers {
            guard let storage = marker.actual.node?.retainedLazyListActivityStorage,
                storage.targetID === marker.actual.target, storage.attachmentID === marker.actual.attachment,
                (storage.ownedEmptyRowRevisions[ObjectIdentifier(marker.membership)]?.value ?? 0) == marker.revision
            else { continue }
            let key = RetainedOwnedPhysicalFacetKey(
                target: ObjectIdentifier(marker.actual.target), attachment: ObjectIdentifier(marker.actual.attachment),
                field: nil)
            for (owner, permissions) in marker.permissions {
                storage.ownedEmptyStructuralPermissions.removeValue(forKey: owner)
                for permission in permissions { removeStructuralReference(permission, storage: storage, key: key) }
            }
            for (owner, presence) in marker.components {
                storage.ownedEmptyStructuralComponents.removeValue(forKey: owner)
                storage.ownedEmptyStructuralNamespaces.removeValue(forKey: owner)
                removeComponentStructuralReference(presence, storage: storage, key: key)
            }
            advanceEmptyRowRevision(on: storage, membership: marker.membership)
            // recordCompletedRow already declared the successor's exact roster
            // and retired its departed generations. Removing old physical
            // markers must not revoke a surviving empty generation in this gap.
        }
    }

    private func publishRegions(
        _ publications: [RetainedOwnedRegionPublication], on storage: RetainedLazyListNodeActivityStorage,
        actual: RetainedLazyListActualAttachment, source: ViewNode
    ) {
        for publication in publications {
            let region = publication.region
            guard actual.isAttached, !region.wasRevoked, region.revision == publication.expectedRevision,
                region.revision < .max, let boundary = region.boundary,
                region.owner.nativePresence === boundary, boundary.hasDeclaredComponent,
                publication.declarations.allSatisfy({
                    !$0.receipt.owner.wasRevoked && $0.receipt.slotPermissions.allSatisfy { !$0.wasRevoked }
                })
            else { continue }
            let identifier = ObjectIdentifier(region)
            let oldSlots = region.slots.values.compactMap(\.permission)
            let oldComponents = region.components.values.compactMap(\.presence)
            if let previous = region.actual,
                previous.target !== actual.target || previous.attachment !== actual.attachment
            {
                removeRegionStructuralMarker(region, at: previous)
            }
            var slots: [ObjectIdentifier: RetainedOwnedSlotPermission] = [:]
            var components: [ObjectIdentifier: RetainedOwnedComponentPresence] = [:]
            for plan in publication.declarations {
                let presence = plan.receipt.componentPresence
                components[ObjectIdentifier(presence.owner)] = presence
                presence.declaredRegions[identifier] = region
                for permission in plan.receipt.slotPermissions {
                    slots[ObjectIdentifier(permission.slot)] = permission
                }
            }
            region.slots = slots.mapValues { RetainedOwnedWeakSlotPermission($0) }
            region.components = components.mapValues { RetainedOwnedWeakComponentPresence($0) }
            region.actual = actual
            region.revision += 1
            boundary.deferredRegion = region
            storage.ownedDeferredRegions[identifier] = region
            storage.ownedRegionStructuralPermissions[identifier] = Array(slots.values)
            storage.ownedRegionStructuralComponents[identifier] = Array(components.values)
            let key = RetainedOwnedPhysicalFacetKey(
                target: ObjectIdentifier(actual.target), attachment: ObjectIdentifier(actual.attachment),
                field: nil, region: identifier)
            for permission in slots.values { permission.structuralFacets[key] = actual }
            for presence in components.values { presence.structuralFacets[key] = actual }
            // No output is required for an explicitly accepted empty declaration.
            // Nonempty descendants keep their own exact source-field admission.
            publish(
                publication.declarations.filter { $0.declarationOnly || $0.sourcePayloads.isEmpty },
                actual: actual, source: source, facet: nil, kind: .structuralEntry)
            acceptedRegions.insert(identifier)
            for permission in oldSlots where slots[ObjectIdentifier(permission.slot)] !== permission {
                permission.structuralFacets.removeValue(forKey: key)
                removeObsoleteDeclarationReferences(to: permission, in: region)
                retireIfUnreferenced(permission, preservingCold: false)
            }
            for presence in oldComponents where components[ObjectIdentifier(presence.owner)] !== presence {
                presence.structuralFacets.removeValue(forKey: key)
                presence.declaredRegions.removeValue(forKey: identifier)
                removeObsoleteDeclarationReferences(to: presence, in: region)
                retireIfUnreferenced(presence, preservingCold: false)
            }
        }
    }

    private func removeRegionStructuralMarker(
        _ region: RetainedOwnedStructuralRegion, at actual: RetainedLazyListActualAttachment
    ) {
        guard let storage = actual.node?.retainedLazyListActivityStorage,
            storage.targetID === actual.target, storage.attachmentID === actual.attachment
        else { return }
        let identifier = ObjectIdentifier(region)
        let slots = storage.ownedRegionStructuralPermissions.removeValue(forKey: identifier) ?? []
        let components = storage.ownedRegionStructuralComponents.removeValue(forKey: identifier) ?? []
        storage.ownedDeferredRegions.removeValue(forKey: identifier)
        let key = RetainedOwnedPhysicalFacetKey(
            target: ObjectIdentifier(actual.target), attachment: ObjectIdentifier(actual.attachment),
            field: nil, region: identifier)
        for permission in slots { permission.structuralFacets.removeValue(forKey: key) }
        for presence in components { presence.structuralFacets.removeValue(forKey: key) }
    }

    private func removeObsoleteDeclarationReferences(
        to permission: RetainedOwnedSlotPermission, in region: RetainedOwnedStructuralRegion
    ) {
        let references = permission.structuralFacets
        for (key, actual) in references where key.field == nil && key.region == nil {
            guard let storage = actual.node?.retainedLazyListActivityStorage,
                storage.targetID === actual.target, storage.attachmentID === actual.attachment
            else { continue }
            let owner = ObjectIdentifier(permission.owner)
            if let namespaces = storage.ownedEmptyStructuralNamespaces[owner],
                namespaces.regions[ObjectIdentifier(region)] === region,
                !namespaces.holds(permission, outside: region),
                let previous = storage.ownedEmptyStructuralPermissions[owner]
            {
                let next = previous.filter { $0 !== permission }
                storage.ownedEmptyStructuralPermissions[owner] = next.isEmpty ? nil : next
                if next.count != previous.count, case .lazy(let logical) = permission.lifetime {
                    advanceEmptyRowRevision(on: storage, membership: logical.id)
                }
            }
            if let namespaces = storage.ownedDeclaredStructuralNamespaces[owner],
                namespaces.regions[ObjectIdentifier(region)] === region,
                !namespaces.holds(permission, outside: region),
                let previous = storage.ownedDeclaredStructuralPermissions[owner]
            {
                let next = previous.filter { $0 !== permission }
                storage.ownedDeclaredStructuralPermissions[owner] = next.isEmpty ? nil : next
            }
            removeStructuralReference(permission, storage: storage, key: key)
        }
    }

    private func removeObsoleteDeclarationReferences(
        to presence: RetainedOwnedComponentPresence, in region: RetainedOwnedStructuralRegion
    ) {
        let references = presence.structuralFacets
        for (key, actual) in references where key.field == nil && key.region == nil {
            guard let storage = actual.node?.retainedLazyListActivityStorage,
                storage.targetID === actual.target, storage.attachmentID === actual.attachment
            else { continue }
            let owner = ObjectIdentifier(presence.owner)
            if var namespaces = storage.ownedEmptyStructuralNamespaces[owner],
                namespaces.regions[ObjectIdentifier(region)] === region,
                storage.ownedEmptyStructuralComponents[owner] === presence
            {
                namespaces.regions.removeValue(forKey: ObjectIdentifier(region))
                if namespaces.holds(presence, outside: region) {
                    storage.ownedEmptyStructuralNamespaces[owner] = namespaces
                } else {
                    storage.ownedEmptyStructuralComponents.removeValue(forKey: owner)
                    storage.ownedEmptyStructuralNamespaces.removeValue(forKey: owner)
                }
                if case .lazy(let logical) = presence.lifetime {
                    advanceEmptyRowRevision(on: storage, membership: logical.id)
                }
            }
            if var namespaces = storage.ownedDeclaredStructuralNamespaces[owner],
                namespaces.regions[ObjectIdentifier(region)] === region,
                storage.ownedDeclaredStructuralComponents[owner] === presence
            {
                namespaces.regions.removeValue(forKey: ObjectIdentifier(region))
                if namespaces.holds(presence, outside: region) {
                    storage.ownedDeclaredStructuralNamespaces[owner] = namespaces
                } else {
                    storage.ownedDeclaredStructuralComponents.removeValue(forKey: owner)
                    storage.ownedDeclaredStructuralNamespaces.removeValue(forKey: owner)
                }
            }
            removeComponentStructuralReference(presence, storage: storage, key: key)
        }
    }

    func canCompleteRow(
        _ activity: RetainedLazyListMaterializedRowActivity,
        components: Set<ObjectIdentifier>, anchor: RetainedLazyListActualAttachment
    ) -> Bool {
        guard didPrepare, !wasFinished, anchor.isAttached,
            activity.logicalMembership.isDeclared, activity.physical.state != .revoked
        else { return false }
        let desired =
            frozenPlans?.filter { plan in
                guard case .lazy(let component) = plan.origin, components.contains(ObjectIdentifier(component)),
                    case .lazy(let logical) = plan.receipt.nativeLifetime
                else { return false }
                return logical === activity.logicalMembership
            } ?? []
        return desired.allSatisfy {
            selectedPlans.contains(ObjectIdentifier($0)) && !$0.receipt.owner.wasRevoked
                && $0.receipt.slotPermissions.allSatisfy { !$0.wasRevoked }
        }
    }

    func recordCompletedRow(
        _ activity: RetainedLazyListMaterializedRowActivity,
        components: Set<ObjectIdentifier>, anchor: RetainedLazyListActualAttachment
    ) -> Bool {
        guard canCompleteRow(activity, components: components, anchor: anchor), activity.physical.state == .active
        else { return false }
        let desiredPlans =
            frozenPlans?.filter { plan in
                guard case .lazy(let component) = plan.origin,
                    components.contains(ObjectIdentifier(component)),
                    case .lazy(let logical) = plan.receipt.nativeLifetime
                else { return false }
                return logical === activity.logicalMembership
            } ?? []
        guard desiredPlans.allSatisfy({ selectedPlans.contains(ObjectIdentifier($0)) }) else { return false }
        var permissions: [RetainedOwnedSlotPermission] = []
        var seen: Set<ObjectIdentifier> = []
        for plan in desiredPlans {
            publish([plan], actual: anchor, source: nil, facet: nil, kind: .rowDeclarationTable)
            for permission in plan.receipt.slotPermissions where seen.insert(ObjectIdentifier(permission)).inserted {
                // A complete row is the explicit structural declaration-table
                // write, including components that intentionally have no leaf.
                accept(permission)
                permissions.append(permission)
            }
        }
        let next = Set(permissions.map { ObjectIdentifier($0.slot) })
        let previous = activity.logicalMembership.ownedDeclaredSlots.values.compactMap(\.permission)
        for permission in previous where !next.contains(ObjectIdentifier(permission.slot)) { retire(permission) }
        activity.logicalMembership.ownedDeclaredSlots = Dictionary(
            uniqueKeysWithValues: permissions.map { (ObjectIdentifier($0.slot), RetainedOwnedWeakSlotPermission($0)) })
        activity.logicalMembership.ownedDeclaredComponents = replacingComponentTable(
            desiredPlans, previous: activity.logicalMembership.ownedDeclaredComponents)
        return true
    }

    func recordCompletedDescriptorScope(anchor: RetainedLazyListActualAttachment) -> Bool {
        guard didPrepare, !wasFinished, anchor.isAttached,
            let storage = anchor.node?.lazyListActivityStorage()
        else { return false }
        let plans =
            frozenPlans?.filter {
                if case .descriptor = $0.origin { return true }
                return false
            } ?? []
        guard plans.allSatisfy({ selectedPlans.contains(ObjectIdentifier($0)) }) else { return false }
        var permissions: [ObjectIdentifier: RetainedOwnedSlotPermission] = [:]
        for plan in plans {
            publish([plan], actual: anchor, source: nil, facet: nil, kind: .descriptorDeclarationTable)
            for permission in plan.receipt.slotPermissions {
                permissions[ObjectIdentifier(permission.slot)] = permission
            }
        }
        let previous = storage.ownedScopeDeclaredSlots
        storage.ownedScopeDeclaredSlots = permissions.mapValues { RetainedOwnedWeakSlotPermission($0) }
        for (id, old) in previous where permissions[id] == nil {
            if let permission = old.permission { retire(permission) }
        }
        storage.ownedScopeDeclaredComponents = replacingComponentTable(
            plans, previous: storage.ownedScopeDeclaredComponents)
        return true
    }

    func recordEmptyRowDeparture(
        _ activity: RetainedLazyListMaterializedRowActivity,
        anchors: [RetainedLazyListActualAttachment]
    ) {
        for anchor in anchors {
            guard let storage = anchor.node?.retainedLazyListActivityStorage else { continue }
            let facetKey = RetainedOwnedPhysicalFacetKey(
                target: ObjectIdentifier(anchor.target), attachment: ObjectIdentifier(anchor.attachment), field: nil)
            let removedOwners = storage.ownedEmptyStructuralComponents.compactMap { key, presence in
                if case .lazy(let logical) = presence.lifetime, logical === activity.logicalMembership { return key }
                return nil
            }
            for owner in removedOwners {
                let permissions = storage.ownedEmptyStructuralPermissions.removeValue(forKey: owner) ?? []
                let presence = storage.ownedEmptyStructuralComponents.removeValue(forKey: owner)
                storage.ownedEmptyStructuralNamespaces.removeValue(forKey: owner)
                for permission in permissions { removeStructuralReference(permission, storage: storage, key: facetKey) }
                if let presence { removeComponentStructuralReference(presence, storage: storage, key: facetKey) }
            }
            storage.ownedEmptyRowRevisions.removeValue(forKey: ObjectIdentifier(activity.logicalMembership.id))
        }
        // Leaving the bounded mounted table is physical eviction. Native
        // logical receipts/slots stay declared until an explicit declaration
        // replacement or logical-scope revocation says otherwise.
    }

    func recordPhysicalDeparture(of node: ViewNode, cause: RetainedLazyListDepartureCause) {
        guard let snapshot = capturePhysicalDeparture(of: node, cause: cause) else { return }
        recordPhysicalDeparture(snapshot)
    }

    func capturePhysicalDeparture(
        of node: ViewNode, cause: RetainedLazyListDepartureCause
    ) -> RetainedOwnedPhysicalDepartureSnapshot? {
        guard let storage = node.retainedLazyListActivityStorage else { return nil }
        return RetainedOwnedPhysicalDepartureSnapshot(storage: storage, cause: cause)
    }

    func partitionOrdinaryDeparture(
        _ snapshot: RetainedOwnedPhysicalDepartureSnapshot
    ) -> (immediate: RetainedOwnedPhysicalDepartureSnapshot, pending: RetainedOwnedPhysicalDepartureSnapshot)? {
        guard snapshot.cause != .viewportEviction, !snapshot.wasConsumed,
            snapshot.regions.isEmpty, snapshot.regionSlots.isEmpty, snapshot.regionComponents.isEmpty
        else { return nil }
        let permissions = Set(snapshot.permissions.map { ObjectIdentifier($0) })
        let components = Set(snapshot.components.map { ObjectIdentifier($0) })
        var continuingPermissions: Set<ObjectIdentifier> = []
        var continuingComponents: Set<ObjectIdentifier> = []
        func hasOtherActual(
            _ facets: [RetainedOwnedPhysicalFacetKey: RetainedLazyListActualAttachment]
        ) -> Bool {
            facets.contains { key, actual in
                actual.isAttached
                    && (key.target != ObjectIdentifier(snapshot.targetID)
                        || key.attachment != ObjectIdentifier(snapshot.attachmentID))
            }
        }
        for plan in frozenPlans ?? [] where selectedPlans.contains(ObjectIdentifier(plan)) {
            guard !plan.declarationOnly, !plan.sourcePayloads.isEmpty,
                !plan.receipt.owner.wasRevoked, plan.receipt.nativeLifetime.permitsDeclaredWrite
            else { continue }
            let presence = plan.receipt.componentPresence
            if components.contains(ObjectIdentifier(presence)),
                !hasOtherActual(presence.payloadFacets), !hasOtherActual(presence.structuralFacets)
            {
                continuingComponents.insert(ObjectIdentifier(presence))
            }
            for permission in plan.receipt.slotPermissions where permissions.contains(ObjectIdentifier(permission)) {
                if !permission.wasRevoked, !hasOtherActual(permission.payloadFacets),
                    !hasOtherActual(permission.structuralFacets)
                {
                    continuingPermissions.insert(ObjectIdentifier(permission))
                }
            }
        }
        return snapshot.partition(permissions: continuingPermissions, components: continuingComponents)
    }

    func awaitsReplacementDeclaration(_ snapshot: RetainedOwnedPhysicalDepartureSnapshot) -> Bool {
        guard snapshot.cause != .viewportEviction, !snapshot.wasConsumed else { return false }
        let permissions = Set(snapshot.permissions.map { ObjectIdentifier($0) })
        let components = Set(snapshot.components.map { ObjectIdentifier($0) })
        func hasOtherActual(
            _ facets: [RetainedOwnedPhysicalFacetKey: RetainedLazyListActualAttachment]
        ) -> Bool {
            facets.contains { key, actual in
                actual.isAttached
                    && (key.target != ObjectIdentifier(snapshot.targetID)
                        || key.attachment != ObjectIdentifier(snapshot.attachmentID))
            }
        }
        for plan in frozenPlans ?? [] where selectedPlans.contains(ObjectIdentifier(plan)) {
            guard !plan.receipt.owner.wasRevoked, plan.receipt.nativeLifetime.permitsDeclaredWrite else { continue }
            let presence = plan.receipt.componentPresence
            if components.contains(ObjectIdentifier(presence)),
                !hasOtherActual(presence.payloadFacets), !hasOtherActual(presence.structuralFacets)
            {
                return true
            }
            for permission in plan.receipt.slotPermissions where permissions.contains(ObjectIdentifier(permission)) {
                if !permission.wasRevoked, !hasOtherActual(permission.payloadFacets),
                    !hasOtherActual(permission.structuralFacets)
                {
                    return true
                }
            }
        }
        // Candidate identity can postpone a destructive decision, but cannot
        // make an outgoing slot writable. Only a new accepted native footprint
        // bypasses its suspension; seal/abandon consumes unresolved snapshots.
        return false
    }

    func recordPhysicalDeparture(_ snapshot: RetainedOwnedPhysicalDepartureSnapshot) {
        guard !snapshot.wasConsumed else { return }
        snapshot.wasConsumed = true
        defer { snapshot.finishOwnedWriteSuspension() }
        let cause = snapshot.cause
        snapshot.removePhysicalMaps()
        // Only a pending partition whose shared clear actually succeeded may
        // preserve a matching local member. All such tables were empty at that
        // boundary, so this membership proves a later native publication even
        // when it reused the same permission, presence, or empty anchor object.
        // Recheck the original weak storage/IDs per member, after any preceding
        // retirement query's weak loads and releases; do not cache that match.
        for (field, permissions) in snapshot.payloads {
            let key = RetainedOwnedPhysicalFacetKey(
                target: ObjectIdentifier(snapshot.targetID), attachment: ObjectIdentifier(snapshot.attachmentID),
                field: field)
            for permission in permissions {
                if snapshot.laterPublicationStorage?.ownedPayloadPermissions[field]?.contains(where: {
                    $0 === permission
                }) != true {
                    permission.payloadFacets.removeValue(forKey: key)
                }
                retireIfUnreferenced(permission, preservingCold: cause == .viewportEviction)
            }
        }
        let key = RetainedOwnedPhysicalFacetKey(
            target: ObjectIdentifier(snapshot.targetID), attachment: ObjectIdentifier(snapshot.attachmentID),
            field: nil)
        for permission in snapshot.structural + snapshot.emptyStructural {
            if let laterPublicationStorage = snapshot.laterPublicationStorage {
                removeStructuralReference(permission, storage: laterPublicationStorage, key: key)
            } else {
                permission.structuralFacets.removeValue(forKey: key)
            }
            retireIfUnreferenced(permission, preservingCold: cause == .viewportEviction)
        }
        for (field, presences) in snapshot.componentPayloads {
            let key = RetainedOwnedPhysicalFacetKey(
                target: ObjectIdentifier(snapshot.targetID), attachment: ObjectIdentifier(snapshot.attachmentID),
                field: field)
            for presence in presences {
                if snapshot.laterPublicationStorage?.ownedPayloadComponents[field]?.contains(where: {
                    $0 === presence
                }) != true {
                    presence.payloadFacets.removeValue(forKey: key)
                }
                retireIfUnreferenced(presence, preservingCold: cause == .viewportEviction)
            }
        }
        for presence in snapshot.componentStructural {
            if let laterPublicationStorage = snapshot.laterPublicationStorage {
                removeComponentStructuralReference(presence, storage: laterPublicationStorage, key: key)
            } else {
                presence.structuralFacets.removeValue(forKey: key)
            }
            retireIfUnreferenced(presence, preservingCold: cause == .viewportEviction)
        }
        for (identifier, region) in snapshot.regions {
            let regionKey = RetainedOwnedPhysicalFacetKey(
                target: ObjectIdentifier(snapshot.targetID), attachment: ObjectIdentifier(snapshot.attachmentID),
                field: nil, region: identifier)
            for permission in snapshot.regionSlots[identifier] ?? [] {
                permission.structuralFacets.removeValue(forKey: regionKey)
                retireIfUnreferenced(permission, preservingCold: cause == .viewportEviction)
            }
            for presence in snapshot.regionComponents[identifier] ?? [] {
                presence.structuralFacets.removeValue(forKey: regionKey)
                retireIfUnreferenced(presence, preservingCold: cause == .viewportEviction)
            }
            if cause != .viewportEviction, region.owner.nativePresence?.hasDeclaredComponent != true {
                retireRegion(region)
            }
        }
    }

    private func accept(_ permission: RetainedOwnedSlotPermission) {
        _ = permission.activate()
        acceptedPermissions.insert(ObjectIdentifier(permission))
        if case .lazy(let logical) = permission.lifetime {
            logical.ownedDeclaredSlots[ObjectIdentifier(permission.slot)] = RetainedOwnedWeakSlotPermission(permission)
        }
    }

    @discardableResult
    private func publish(
        _ plans: [RetainedOwnedComponentDeclarationPlan], actual: RetainedLazyListActualAttachment,
        source: ViewNode?, facet: RetainedLazyListSourceFacetID?, kind: RetainedOwnedComponentPublicationKind,
        ordinaryDomainStillMatches: () -> Bool = { true }
    ) -> PublicationResult {
        let sourcePayloads =
            source.map { source in
                sources.filter { $0.node === source }.map(\.payload)
            } ?? []
        // Weak source materialization precedes the domain check. A rejected
        // domain has not activated or recorded any plan in this invocation.
        guard ordinaryDomainStillMatches() else { return .domainChanged }
        var successful: [RetainedOwnedComponentDeclarationPlan] = []
        for plan in plans {
            let presence = plan.receipt.componentPresence
            guard plan.receipt.slotPermissions.allSatisfy({ !$0.wasRevoked }), presence.activate() else { continue }
            acceptedPresences.insert(ObjectIdentifier(presence))
            for region in plan.structuralRegions where !region.wasRevoked {
                presence.declaredRegions[ObjectIdentifier(region)] = region
            }
            if case .lazy(let logical) = presence.lifetime {
                logical.ownedDeclaredComponents[ObjectIdentifier(presence.owner)] =
                    RetainedOwnedWeakComponentPresence(presence)
            }
            for permission in plan.receipt.slotPermissions { accept(permission) }
            plan.receipt.recordAcceptedDeclaration()
            let payload = sourcePayloads.first { candidate in plan.sourcePayloads.contains { $0 === candidate } }
            acceptedDeclarations.append(
                RetainedOwnedComponentDeclarationFact(
                    plan: plan, slots: plan.receipt.slots, sourcePayload: payload,
                    sourceFacet: facet, actual: actual, kind: kind))
            successful.append(plan)
        }
        return .published(successful)
    }

    private func replacingComponentTable(
        _ plans: [RetainedOwnedComponentDeclarationPlan],
        previous: [ObjectIdentifier: RetainedOwnedWeakComponentPresence]
    ) -> [ObjectIdentifier: RetainedOwnedWeakComponentPresence] {
        var next: [ObjectIdentifier: RetainedOwnedWeakComponentPresence] = [:]
        for plan in plans {
            let presence = plan.receipt.componentPresence
            next[ObjectIdentifier(presence.owner)] = RetainedOwnedWeakComponentPresence(presence)
        }
        for (id, old) in previous where next[id] == nil {
            if let presence = old.presence { retire(presence) }
        }
        return next
    }

    private func replacePayload(
        on storage: RetainedLazyListNodeActivityStorage, actual: RetainedLazyListActualAttachment,
        field: AnyKeyPath, with incoming: [RetainedOwnedSlotPermission]
    ) {
        let previous = storage.ownedPayloadPermissions[field] ?? []
        let key = RetainedOwnedPhysicalFacetKey(
            target: ObjectIdentifier(storage.targetID), attachment: ObjectIdentifier(storage.attachmentID), field: field
        )
        storage.ownedPayloadPermissions[field] = incoming.isEmpty ? nil : incoming
        for permission in incoming { permission.payloadFacets[key] = actual }
        for permission in previous where !incoming.contains(where: { $0 === permission }) {
            permission.payloadFacets.removeValue(forKey: key)
            retireIfUnreferenced(permission, preservingCold: false)
        }
    }

    private func replaceStructural(
        on storage: RetainedLazyListNodeActivityStorage, actual: RetainedLazyListActualAttachment,
        with incoming: [RetainedOwnedSlotPermission]
    ) {
        let previous = storage.ownedStructuralPermissions
        let key = RetainedOwnedPhysicalFacetKey(
            target: ObjectIdentifier(storage.targetID), attachment: ObjectIdentifier(storage.attachmentID), field: nil)
        storage.ownedStructuralPermissions = incoming
        for permission in incoming { permission.structuralFacets[key] = actual }
        for permission in previous where !incoming.contains(where: { $0 === permission }) {
            removeStructuralReference(permission, storage: storage, key: key)
            retireIfUnreferenced(permission, preservingCold: false)
        }
    }

    private func retireIfUnreferenced(_ permission: RetainedOwnedSlotPermission, preservingCold: Bool) {
        if preservingCold, case .lazy = permission.lifetime { return }
        guard !permission.payloadFacets.values.contains(where: \.isAttached),
            !permission.structuralFacets.values.contains(where: \.isAttached)
        else { return }
        guard !awaitsDeclaredMarkerReplacement(ObjectIdentifier(permission)) else { return }
        retire(permission)
    }

    private func removeStructuralReference(
        _ permission: RetainedOwnedSlotPermission,
        storage: RetainedLazyListNodeActivityStorage, key: RetainedOwnedPhysicalFacetKey
    ) {
        guard !storage.ownedStructuralPermissions.contains(where: { $0 === permission }),
            !storage.ownedEmptyStructuralPermissions.values.contains(where: {
                $0.contains(where: { $0 === permission })
            }),
            !storage.ownedDeclaredStructuralPermissions.values.contains(where: {
                $0.contains(where: { $0 === permission })
            })
        else { return }
        permission.structuralFacets.removeValue(forKey: key)
    }

    private func removeComponentStructuralReference(
        _ presence: RetainedOwnedComponentPresence, storage: RetainedLazyListNodeActivityStorage,
        key: RetainedOwnedPhysicalFacetKey
    ) {
        guard !storage.ownedStructuralComponents.contains(where: { $0 === presence }),
            storage.ownedEmptyStructuralComponents[ObjectIdentifier(presence.owner)] !== presence,
            storage.ownedDeclaredStructuralComponents[ObjectIdentifier(presence.owner)] !== presence
        else { return }
        presence.structuralFacets.removeValue(forKey: key)
    }

    private func replaceComponents(
        on storage: RetainedLazyListNodeActivityStorage, actual: RetainedLazyListActualAttachment,
        field: AnyKeyPath, with incoming: [RetainedOwnedComponentPresence], hasPayload: Bool
    ) {
        replaceComponentStructural(on: storage, actual: actual, with: incoming)
        let key = RetainedOwnedPhysicalFacetKey(
            target: ObjectIdentifier(storage.targetID), attachment: ObjectIdentifier(storage.attachmentID), field: field
        )
        let previous = storage.ownedPayloadComponents[field] ?? []
        let next = hasPayload ? incoming : []
        storage.ownedPayloadComponents[field] = next.isEmpty ? nil : next
        for presence in next { presence.payloadFacets[key] = actual }
        for presence in previous where !next.contains(where: { $0 === presence }) {
            presence.payloadFacets.removeValue(forKey: key)
            retireIfUnreferenced(presence, preservingCold: false)
        }
    }

    private func replaceComponentStructural(
        on storage: RetainedLazyListNodeActivityStorage, actual: RetainedLazyListActualAttachment,
        with incoming: [RetainedOwnedComponentPresence]
    ) {
        let previous = storage.ownedStructuralComponents
        let key = RetainedOwnedPhysicalFacetKey(
            target: ObjectIdentifier(storage.targetID), attachment: ObjectIdentifier(storage.attachmentID), field: nil)
        storage.ownedStructuralComponents = incoming
        for presence in incoming { presence.structuralFacets[key] = actual }
        for presence in previous where !incoming.contains(where: { $0 === presence }) {
            removeComponentStructuralReference(presence, storage: storage, key: key)
            retireIfUnreferenced(presence, preservingCold: false)
        }
    }

    private func retireIfUnreferenced(_ presence: RetainedOwnedComponentPresence, preservingCold: Bool) {
        if preservingCold, case .lazy = presence.lifetime { return }
        guard !presence.payloadFacets.values.contains(where: \.isAttached),
            !presence.structuralFacets.values.contains(where: \.isAttached)
        else { return }
        guard !awaitsDeclaredMarkerReplacement(ObjectIdentifier(presence)) else { return }
        retire(presence)
    }

    private func retire(_ permission: RetainedOwnedSlotPermission) {
        guard !permission.wasRevoked else { return }
        permission.revoke()
        retiredSlots.append(permission.slot)
    }

    private func retire(_ presence: RetainedOwnedComponentPresence) {
        guard !presence.wasRevoked else { return }
        presence.revoke()
        retiredComponents.append(presence.owner)
        if let region = presence.deferredRegion { retireRegion(region) }
    }

    private func retireRegion(_ region: RetainedOwnedStructuralRegion) {
        guard !region.wasRevoked else { return }
        region.wasRevoked = true
        let identifier = ObjectIdentifier(region)
        let slots = region.slots.values.compactMap(\.permission)
        let components = region.components.values.compactMap(\.presence)
        if let actual = region.actual { removeRegionStructuralMarker(region, at: actual) }
        region.slots.removeAll()
        region.components.removeAll()
        for permission in slots {
            removeObsoleteDeclarationReferences(to: permission, in: region)
            retireIfUnreferenced(permission, preservingCold: false)
        }
        for presence in components {
            presence.declaredRegions.removeValue(forKey: identifier)
            removeObsoleteDeclarationReferences(to: presence, in: region)
            retireIfUnreferenced(presence, preservingCold: false)
        }
    }

    func finish() {
        finishPendingDeclaredMarkerRetirements()
        wasFinished = true
        propertyPublications.removeAll()
        insertions.removeAll()
        structuralPublications.removeAll()
        insertedRegionPublications.removeAll()
        completedRegionPublications.removeAll()
        declaredMarkerRetirements.removeAll()
        registrations.removeAll()
        sources.removeAll()
        componentParents.removeAll()
        regionSources.removeAll()
        deferredRegionBuilds.removeAll()
        planRegistrations.removeAll()
    }
}

extension RetainedLazyListBuildAttribution {
    package func registerOwnedComponent(
        owner: RetainedOwnedComponentID, slots: [RetainedOwnedSlotGenerationID],
        continuing: RetainedOwnedComponentReceipt? = nil, declarationOnly: Bool = false
    ) -> RetainedOwnedComponentReceipt? {
        registerOwnedComponent(
            owner: owner, slots: slots, continuing: continuing.map { [$0] } ?? [], declarationOnly: declarationOnly)
    }

    package func registerOwnedComponent(
        owner: RetainedOwnedComponentID, slots: [RetainedOwnedSlotGenerationID],
        continuing: [RetainedOwnedComponentReceipt], declarationOnly: Bool = false
    ) -> RetainedOwnedComponentReceipt? {
        journal?.ownedLedger?.register(
            owner: owner, slots: slots, continuing: continuing, attribution: self, declarationOnly: declarationOnly)
    }
}

extension RetainedDescriptorComponentAttribution {
    package func registerOwnedComponent(
        owner: RetainedOwnedComponentID, slots: [RetainedOwnedSlotGenerationID],
        continuing: RetainedOwnedComponentReceipt? = nil, declarationOnly: Bool = false
    ) -> RetainedOwnedComponentReceipt? {
        registerOwnedComponent(
            owner: owner, slots: slots, continuing: continuing.map { [$0] } ?? [], declarationOnly: declarationOnly)
    }

    package func registerOwnedComponent(
        owner: RetainedOwnedComponentID, slots: [RetainedOwnedSlotGenerationID],
        continuing: [RetainedOwnedComponentReceipt], declarationOnly: Bool = false
    ) -> RetainedOwnedComponentReceipt? {
        descriptorScope?.ownedLedger.register(
            owner: owner, slots: slots, continuing: continuing, attribution: self, declarationOnly: declarationOnly)
    }
}
