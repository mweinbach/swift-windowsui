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
    fileprivate var ownedCandidateQualification: RetainedOwnedCandidateScopeQualification?

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
        let admitted = RetainedLazyListDescriptorBuildScope(
            enclosing: self, containing: .ordinaryDeferred(originalActivity, originalAttachment),
            originalOwner: originalActivity.nativeOwnerLifetime)
        guard
            ownedLedger.qualifyOwnedCandidateSubtree(
                scope: admitted, contribution: originalActivity, actual: originalAttachment)
        else { return nil }
        return admitted
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
    fileprivate weak var ownedPhysicalReferences: RetainedOwnedPhysicalReferenceHolder?

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

    fileprivate var originalOwnedReferenceStorage: RetainedLazyListNodeActivityStorage? {
        guard let holder = ownedPhysicalReferences, let storage = holder.storage,
            holder.matches(storage), holder.targetID === target, holder.attachmentID === attachment
        else { return nil }
        return storage
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
    let physicalActual: RetainedLazyListActualAttachment?
    let selectedContentPath: RetainedSelectedContentPath?

    init(
        sourcePayload: RetainedLazyListSourcePayloadID, requiredFacets: [RetainedLazyListSourceFacetID],
        actual: RetainedLazyListActualAttachment, physicalActual: RetainedLazyListActualAttachment? = nil,
        selectedContentPath: RetainedSelectedContentPath? = nil
    ) {
        self.sourcePayload = sourcePayload
        self.requiredFacets = requiredFacets
        self.actual = actual
        self.physicalActual = physicalActual
        self.selectedContentPath = selectedContentPath
    }
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
    let activitySource: ViewNode

    init(member: RetainedLazyListAcceptedTaskMember, source: ViewNode, activitySource: ViewNode? = nil) {
        self.member = member
        self.source = source
        self.activitySource = activitySource ?? source
    }
}

@MainActor
fileprivate struct RetainedTaskRouteNativeFact {
    let id: RetainedLazyListSourceFacetID
    let field: RetainedLazyListNativeFacet
    let actual: RetainedLazyListActualAttachment
}

@MainActor
fileprivate final class RetainedTaskRouteSourceSlot {
    weak var source: ViewNode?
    let attachmentFacet: RetainedLazyListSourceFacetID?
    var mapping: RetainedSelectedContentTaskMapping?

    init(source: ViewNode, attachmentFacet: RetainedLazyListSourceFacetID?) {
        self.source = source
        self.attachmentFacet = attachmentFacet
    }
}

/// The physical output remains the source of its contribution. These separate
/// links name only its originally selected Task fields and native mappings.
@MainActor
fileprivate final class RetainedTaskSelectedContentRoute {
    let original: RetainedSelectedContentTaskSource
    private let qualification: RetainedOwnedCandidateTaskQualification
    private let physicalFacet: RetainedLazyListSourceFacetID
    private let slots: [RetainedTaskRouteSourceSlot]
    private var wasRefused = false
    private(set) var acceptedPath: RetainedSelectedContentPath?

    init?(
        physicalSource: ViewNode, path: RetainedSelectedContentPath,
        physicalFacet: RetainedLazyListSourceFacetID, middleFacets: [RetainedLazyListSourceFacetID],
        qualification: RetainedOwnedCandidateTaskQualification
    ) {
        guard path.physicalRoot === physicalSource, let selected = path.selectedNode,
            let boundaries = path.boundaryNodes,
            middleFacets.count == max(0, boundaries.count - 1),
            boundaries.first === physicalSource || (boundaries.isEmpty && selected === physicalSource),
            let selection = path.captureConstructionSelection(),
            let original = selection.captureTaskSource(canPublish: {
                qualification.canObserveOriginalConstruction || qualification.canPublish
            })
        else { return nil }
        self.original = original
        self.qualification = qualification
        self.physicalFacet = physicalFacet
        var slots: [RetainedTaskRouteSourceSlot] = []
        for (index, boundary) in boundaries.enumerated() {
            slots.append(
                RetainedTaskRouteSourceSlot(
                    source: boundary, attachmentFacet: index == 0 ? physicalFacet : middleFacets[index - 1]))
        }
        slots.append(
            RetainedTaskRouteSourceSlot(
                source: selected, attachmentFacet: boundaries.isEmpty ? physicalFacet : nil))
        self.slots = slots
    }

    var physicalSource: ViewNode? { slots.first?.source }
    var activitySource: ViewNode? { slots.last?.source }

    var sourcePins: [ViewNode]? {
        let result = slots.compactMap(\.source)
        return result.count == slots.count ? result : nil
    }

    func contains(_ source: ViewNode) -> Bool { slots.contains { $0.source === source } }

    @discardableResult
    func prepareMapping(
        from source: ViewNode, to target: ViewNode,
        targetID: RetainedLazyListTargetID, attachmentID: RetainedLazyListAttachmentID
    ) -> Bool {
        guard !wasRefused, acceptedPath == nil, let slot = slots.first(where: { $0.source === source }),
            let mapping = original.prepareMapping(
                from: source, to: target, targetID: targetID, attachmentID: attachmentID)
        else {
            wasRefused = true
            return false
        }
        if let previous = slot.mapping, previous !== mapping {
            wasRefused = true
            return false
        }
        slot.mapping = mapping
        return true
    }

    private func slot(
        for id: RetainedLazyListSourceFacetID, field: RetainedLazyListNativeFacet
    ) -> RetainedTaskRouteSourceSlot? {
        switch field {
        case .childAttachment:
            return slots.first { $0.attachmentFacet === id }
        case .nodeProperty(let keyPath):
            guard keyPath == \ViewNode.onAppearWithNode || keyPath == \ViewNode.onDisappearWithNode else { return nil }
            return slots.last
        case .scopedTaskDeclaration:
            return slots.last
        case .nodeCompletion, .listDescriptor:
            return nil
        }
    }

    func owns(_ id: RetainedLazyListSourceFacetID, field: RetainedLazyListNativeFacet, on source: ViewNode) -> Bool {
        slot(for: id, field: field)?.source === source
    }

    func permitsNativeFacet(
        _ id: RetainedLazyListSourceFacetID, field: RetainedLazyListNativeFacet,
        on actual: RetainedLazyListActualAttachment
    ) -> Bool {
        guard !wasRefused, acceptedPath == nil, qualification.canPublish, let slot = slot(for: id, field: field),
            slot.source != nil, let mapping = slot.mapping
        else { return false }
        return mapping.permitsNativeFacet(on: actual)
    }

    private func matchesOriginalMapping(
        _ id: RetainedLazyListSourceFacetID, field: RetainedLazyListNativeFacet,
        actual: RetainedLazyListActualAttachment
    ) -> Bool {
        guard let slot = slot(for: id, field: field), let source = slot.source, let mapping = slot.mapping else {
            return false
        }
        return mapping.source === source && mapping.target === actual.node
            && mapping.targetID === actual.target && mapping.attachmentID === actual.attachment && actual.isAttached
    }

    func prepareAcceptance(facts: [RetainedTaskRouteNativeFact]) -> RetainedSelectedContentTaskNativeAcceptance? {
        guard !wasRefused, acceptedPath == nil, qualification.canPublish, original.canPublish,
            sourcePins != nil, let physical = facts.first(where: { $0.id === physicalFacet })?.actual,
            let selected = facts.first(where: { slot(for: $0.id, field: $0.field) === slots.last })?.actual,
            facts.allSatisfy({ permitsNativeFacet($0.id, field: $0.field, on: $0.actual) })
        else { return nil }
        let mappings = slots.compactMap(\.mapping)
        guard mappings.count == slots.count else { return nil }
        var boundaries: [RetainedLazyListActualAttachment] = []
        for slot in slots.dropLast() {
            guard let source = slot.source, let facet = slot.attachmentFacet,
                let actual = facts.first(where: { $0.id === facet })?.actual,
                qualification.permitsBoundary(source: source, actual: actual)
            else { return nil }
            boundaries.append(actual)
        }
        guard let runtime = physical.runtime, selected.runtime === runtime,
            boundaries.allSatisfy({ $0.runtime === runtime })
        else { return nil }
        return RetainedSelectedContentTaskNativeAcceptance(
            source: original, mappings: mappings, physical: physical, boundaries: boundaries, selected: selected)
    }

    func permitsInitialPath(
        _ path: RetainedSelectedContentPath, acceptance: RetainedSelectedContentTaskNativeAcceptance,
        facts: [RetainedTaskRouteNativeFact]
    ) -> Bool {
        guard !wasRefused, acceptedPath == nil, qualification.canPublish,
            acceptance.source === original, let runtime = acceptance.physical.runtime,
            path.physicalRoot === acceptance.physical.node, path.selectedNode === acceptance.selected.node,
            path.isInstalled(in: runtime), let actualBoundaries = path.boundaryNodes,
            actualBoundaries.count == acceptance.boundaries.count,
            zip(actualBoundaries, acceptance.boundaries).allSatisfy({ $0.0 === $0.1.node }),
            facts.allSatisfy({ matchesOriginalMapping($0.id, field: $0.field, actual: $0.actual) })
        else { return false }
        for (slot, actual) in zip(slots.dropLast(), acceptance.boundaries) {
            guard let source = slot.source, qualification.permitsBoundary(source: source, actual: actual) else {
                return false
            }
        }
        return true
    }

    func retainInitialPath(_ path: RetainedSelectedContentPath) -> Bool {
        guard !wasRefused, acceptedPath == nil else { return false }
        acceptedPath = path
        return true
    }

    func permitsAcceptedMember(_ member: RetainedLazyListAcceptedTaskMember) -> Bool {
        guard let physical = member.physicalActual, let path = member.selectedContentPath,
            path === acceptedPath, let runtime = physical.runtime,
            path.physicalRoot === physical.node, path.selectedNode === member.actual.node,
            physical.isAttached, member.actual.isAttached, member.actual.runtime === runtime,
            path.isInstalled(in: runtime), let boundaries = path.boundaryNodes,
            boundaries.count == slots.count - 1,
            zip(boundaries, slots.dropLast()).allSatisfy({ $0.0 === $0.1.mapping?.target }),
            let first = slots.first?.mapping, let last = slots.last?.mapping
        else { return false }
        return first.target === physical.node && first.targetID === physical.target
            && first.attachmentID === physical.attachment && last.target === member.actual.node
            && last.targetID === member.actual.target && last.attachmentID === member.actual.attachment
    }

    func matchesAcceptedFact(_ fact: RetainedTaskRouteNativeFact, member: RetainedLazyListAcceptedTaskMember) -> Bool {
        permitsAcceptedMember(member) && matchesOriginalMapping(fact.id, field: fact.field, actual: fact.actual)
    }
}

@MainActor
fileprivate struct RetainedTaskRouteJoinInput {
    let payload: RetainedLazyListSourcePayloadID
    let source: ViewNode
    let route: RetainedTaskSelectedContentRoute?
    let requiredFacets: [RetainedLazyListSourceFacetID]
    let facts: [RetainedTaskRouteNativeFact]
}

@MainActor
fileprivate struct RetainedTaskRouteJoinedMembers {
    let members: [RetainedLazyListAcceptedTaskMember]
    let actuals: [RetainedLazyListActualAttachment]
}

/// All outputs, including ordinary members of a mixed group, are checked before
/// Runtime consumes any original route. A pending edge or namespace fact can
/// retry; Runtime makes a consumed or refused original permanently unusable.
@MainActor
fileprivate func joinRetainedTaskRoutes(_ inputs: [RetainedTaskRouteJoinInput]) -> RetainedTaskRouteJoinedMembers? {
    var acceptances: [RetainedSelectedContentTaskNativeAcceptance] = []
    var routeIndices: [Int] = []
    var selectedActuals: [RetainedLazyListActualAttachment] = []
    var pins = inputs.map(\.source)
    for (index, input) in inputs.enumerated() {
        guard !input.requiredFacets.isEmpty,
            input.requiredFacets.allSatisfy({ id in input.facts.contains { $0.id === id } })
        else { return nil }
        let selected: RetainedLazyListActualAttachment
        if let route = input.route {
            guard route.physicalSource === input.source, let sources = route.sourcePins,
                let acceptance = route.prepareAcceptance(facts: input.facts)
            else { return nil }
            pins.append(contentsOf: sources)
            acceptances.append(acceptance)
            routeIndices.append(index)
            selected = acceptance.selected
        } else {
            guard let first = input.facts.first,
                input.facts.allSatisfy({
                    $0.actual.isAttached && $0.actual.target === first.actual.target
                        && $0.actual.attachment === first.actual.attachment
                })
            else { return nil }
            selected = first.actual
        }
        guard
            !selectedActuals.contains(where: {
                $0.target === selected.target && $0.attachment === selected.attachment
            })
        else { return nil }
        selectedActuals.append(selected)
        for fact in input.facts {
            guard let node = fact.actual.node else { return nil }
            pins.append(node)
        }
    }
    guard !acceptances.isEmpty else { return nil }
    return withExtendedLifetime(pins) {
        // Repeat every strict native qualification before the all-route consume.
        for index in routeIndices {
            guard inputs[index].route?.prepareAcceptance(facts: inputs[index].facts) != nil else { return nil }
        }
        guard inputs.allSatisfy({ $0.facts.allSatisfy { $0.actual.isAttached } }),
            let paths = RetainedSelectedContentTaskSource.consumeInitialPaths(for: acceptances),
            paths.count == routeIndices.count
        else { return nil }
        for (offset, index) in routeIndices.enumerated() {
            guard
                inputs[index].route?.permitsInitialPath(
                    paths[offset], acceptance: acceptances[offset], facts: inputs[index].facts) == true
            else { return nil }
        }
        guard inputs.allSatisfy({ $0.facts.allSatisfy { $0.actual.isAttached } }) else { return nil }
        var members: [RetainedLazyListAcceptedTaskMember] = []
        var actuals: [RetainedLazyListActualAttachment] = []
        for (index, input) in inputs.enumerated() {
            let offset = routeIndices.firstIndex(of: index)
            members.append(
                RetainedLazyListAcceptedTaskMember(
                    sourcePayload: input.payload, requiredFacets: input.requiredFacets, actual: selectedActuals[index],
                    physicalActual: offset.map { acceptances[$0].physical },
                    selectedContentPath: offset.map { paths[$0] }))
            for fact in input.facts
            where !actuals.contains(where: {
                $0.target === fact.actual.target && $0.attachment === fact.actual.attachment
            }) {
                actuals.append(fact.actual)
            }
        }
        for (offset, index) in routeIndices.enumerated() {
            guard inputs[index].route?.retainInitialPath(paths[offset]) == true else { return nil }
        }
        return RetainedTaskRouteJoinedMembers(members: members, actuals: actuals)
    }
}

@MainActor
fileprivate func prepareRetainedTaskSourceChildren(
    routes: [RetainedTaskSelectedContentRoute], sourceParent: ViewNode?, targetParent: ViewNode,
    proposedChildren: [ViewNode], incomingNodes: [ViewNode]
) -> RetainedSelectedContentSourceAdoption? {
    var seen: Set<ObjectIdentifier> = []
    let routes = routes.filter { $0.acceptedPath == nil && seen.insert(ObjectIdentifier($0)).inserted }
    guard !routes.isEmpty else { return nil }
    for route in routes {
        if let sourceParent, route.contains(sourceParent) {
            let storage = targetParent.lazyListActivityStorage()
            route.prepareMapping(
                from: sourceParent, to: targetParent, targetID: storage.targetID, attachmentID: storage.attachmentID)
        }
        // Only the original native incoming forest supplies source == target.
        // Retained survivors never enter this list.
        for node in incomingNodes where route.contains(node) {
            let storage = node.lazyListActivityStorage()
            route.prepareMapping(from: node, to: node, targetID: storage.targetID, attachmentID: storage.attachmentID)
        }
    }
    return RetainedSelectedContentSourceAdoption(
        sourceParent: sourceParent, targetParent: targetParent, proposedChildren: proposedChildren,
        incomingNodes: incomingNodes, sources: routes.map(\.original))
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

    package func recordSourceOutput(
        _ source: ViewNode, group: RetainedLazyListGroupID,
        selectedContentPath: RetainedSelectedContentPath? = nil,
        candidateConstruction: RetainedOwnedCandidateConstruction? = nil
    )
        -> RetainedLazyListSourcePayloadID?
    {
        journal?.recordSourceOutput(
            source, attribution: self, group: group, selectedContentPath: selectedContentPath,
            candidateConstruction: candidateConstruction)
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
    var selectedTaskRouteWasRequested = false
    var selectedTaskRoute: RetainedTaskSelectedContentRoute?
    var selectedTaskMiddleFacets: [RetainedLazyListSourceFacet] = []

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
    let taskFacets: [RetainedLazyListSourceFacet]
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

// These records describe completed native metadata writes. They never admit
// construction, continuation, a field copy, or an owned write.
@MainActor
fileprivate final class RetainedOwnedPhysicalMapObservation {}

@MainActor
fileprivate final class RetainedOwnedPhysicalBindingID {}

fileprivate enum RetainedOwnedPhysicalReferenceField: Hashable {
    case payload(AnyKeyPath)
    case structural
    case empty(ObjectIdentifier)
    case declaration(ObjectIdentifier)
    case region(ObjectIdentifier)

    func facet(target: RetainedLazyListTargetID, attachment: RetainedLazyListAttachmentID)
        -> RetainedOwnedPhysicalFacetKey
    {
        switch self {
        case .payload(let field):
            return RetainedOwnedPhysicalFacetKey(
                target: ObjectIdentifier(target), attachment: ObjectIdentifier(attachment), field: field)
        case .region(let region):
            return RetainedOwnedPhysicalFacetKey(
                target: ObjectIdentifier(target), attachment: ObjectIdentifier(attachment), field: nil, region: region)
        case .structural, .empty, .declaration:
            return RetainedOwnedPhysicalFacetKey(
                target: ObjectIdentifier(target), attachment: ObjectIdentifier(attachment), field: nil)
        }
    }
}

@MainActor
fileprivate enum RetainedOwnedPhysicalReferenceMember {
    case slot(RetainedOwnedSlotPermission)
    case component(RetainedOwnedComponentPresence)

    var identity: ObjectIdentifier {
        switch self {
        case .slot(let permission): return ObjectIdentifier(permission)
        case .component(let presence): return ObjectIdentifier(presence)
        }
    }

    var isSlot: Bool {
        if case .slot = self { return true }
        return false
    }

    var index: RetainedOwnedPhysicalReferenceIndex {
        switch self {
        case .slot(let permission):
            if let index = permission.ownedReferenceIndex { return index }
            let index = RetainedOwnedPhysicalReferenceIndex()
            permission.ownedReferenceIndex = index
            return index
        case .component(let presence):
            if let index = presence.ownedReferenceIndex { return index }
            let index = RetainedOwnedPhysicalReferenceIndex()
            presence.ownedReferenceIndex = index
            return index
        }
    }

    func retireAfterRawWithdrawalIfUnreferenced() {
        guard !index.hasCurrentReference, !index.hasPendingRetirement else { return }
        switch self {
        case .slot(let permission):
            guard case .descriptor = permission.lifetime,
                permission.owner.nativePresence?.deferredRegion == nil,
                permission.owner.nativePresence?.declaredRegions.isEmpty != false
            else { return }
            permission.revoke()
        case .component(let presence):
            guard case .descriptor = presence.lifetime,
                presence.deferredRegion == nil, presence.declaredRegions.isEmpty
            else { return }
            presence.revoke()
        }
    }
}

@MainActor
fileprivate final class RetainedOwnedWeakPhysicalReference {
    weak var reference: RetainedOwnedPhysicalReference?
    init(_ reference: RetainedOwnedPhysicalReference) { self.reference = reference }
}

@MainActor
fileprivate final class RetainedOwnedWeakRetirementDebt {
    weak var debt: RetainedOwnedRetirementDebt?
    init(_ debt: RetainedOwnedRetirementDebt) { self.debt = debt }
}

@MainActor
fileprivate final class RetainedOwnedPhysicalReferenceIndex {
    var references: [ObjectIdentifier: RetainedOwnedWeakPhysicalReference] = [:]
    var debts: [ObjectIdentifier: RetainedOwnedWeakRetirementDebt] = [:]
    var candidateReferences: [ObjectIdentifier: RetainedOwnedWeakCandidateReference] = [:]

    var hasCurrentReference: Bool {
        references.values.contains { $0.reference?.isCurrent == true } || hasCurrentCandidateReference
    }

    var hasCurrentCandidateReference: Bool {
        candidateReferences.values.contains { $0.reference?.isCurrent == true }
    }

    var hasPendingRetirement: Bool {
        debts.values.contains { $0.debt?.wasSpent == false }
    }

    func contains(_ facet: RetainedOwnedPhysicalFacetKey) -> Bool {
        references.values.contains {
            guard let reference = $0.reference else { return false }
            return reference.isCurrent && reference.facet == facet
        }
    }

    func insert(_ reference: RetainedOwnedPhysicalReference) {
        // Prune only expired weak bookkeeping, not an outstanding obligation.
        references = references.filter { $0.value.reference != nil }
        references[ObjectIdentifier(reference)] = RetainedOwnedWeakPhysicalReference(reference)
    }
}

@MainActor
fileprivate final class RetainedOwnedRetirementDebt {
    private let index: RetainedOwnedPhysicalReferenceIndex
    private(set) var wasSpent = false

    init(member: RetainedOwnedPhysicalReferenceMember) {
        index = member.index
        index.debts[ObjectIdentifier(self)] = RetainedOwnedWeakRetirementDebt(self)
    }

    func spend() {
        guard !wasSpent else { return }
        wasSpent = true
        index.debts.removeValue(forKey: ObjectIdentifier(self))
    }
}

@MainActor
fileprivate final class RetainedOwnedPhysicalReference {
    let member: RetainedOwnedPhysicalReferenceMember
    let field: RetainedOwnedPhysicalReferenceField
    let facet: RetainedOwnedPhysicalFacetKey
    let actual: RetainedLazyListActualAttachment
    private weak var holder: RetainedOwnedPhysicalReferenceHolder?
    private var wasWithdrawn = false

    init(
        member: RetainedOwnedPhysicalReferenceMember, field: RetainedOwnedPhysicalReferenceField,
        actual: RetainedLazyListActualAttachment, holder: RetainedOwnedPhysicalReferenceHolder
    ) {
        self.member = member
        self.field = field
        self.actual = actual
        self.holder = holder
        facet = field.facet(target: holder.targetID, attachment: holder.attachmentID)
        member.index.insert(self)
    }

    var isCurrent: Bool { !wasWithdrawn && holder?.contains(self) == true }

    func withdraw() {
        guard !wasWithdrawn else { return }
        wasWithdrawn = true
        member.index.references.removeValue(forKey: ObjectIdentifier(self))
    }
}

/// The node owns this sparse native holder; neither it nor its aliases retain a
/// node, runtime, storage, journal, or application payload. A parent temporarily
/// publishing [] does not withdraw an unchanged child's accepted reference.
@MainActor
final class RetainedOwnedPhysicalReferenceHolder {
    fileprivate let identity = RetainedOwnedPhysicalBindingID()
    fileprivate let targetID: RetainedLazyListTargetID
    fileprivate let attachmentID: RetainedLazyListAttachmentID
    fileprivate weak var storage: RetainedLazyListNodeActivityStorage?
    private var fields: [RetainedOwnedPhysicalReferenceField: [RetainedOwnedPhysicalReference]] = [:]

    init(storage: RetainedLazyListNodeActivityStorage) {
        self.storage = storage
        targetID = storage.targetID
        attachmentID = storage.attachmentID
        storage.ownedPhysicalReferences = self
    }

    func matches(_ storage: RetainedLazyListNodeActivityStorage) -> Bool {
        self.storage === storage && targetID === storage.targetID && attachmentID === storage.attachmentID
    }

    fileprivate func contains(_ reference: RetainedOwnedPhysicalReference) -> Bool {
        guard let storage, matches(storage) else { return false }
        return fields[reference.field]?.contains(where: { $0 === reference }) == true
    }

    fileprivate var originalReferences: [RetainedOwnedPhysicalReference] {
        fields.values.flatMap { $0 }
    }

    fileprivate func replace(
        _ members: [RetainedOwnedPhysicalReferenceMember], slots: Bool,
        field: RetainedOwnedPhysicalReferenceField, actual: RetainedLazyListActualAttachment
    ) {
        guard let storage, matches(storage), actual.target === targetID, actual.attachment === attachmentID,
            actual.ownedPhysicalReferences === self
        else { return }
        let previous = fields[field] ?? []
        for reference in previous where reference.member.isSlot == slots { reference.withdraw() }
        var next = previous.filter { $0.member.isSlot != slots }
        var seen: Set<ObjectIdentifier> = []
        for member in members where seen.insert(member.identity).inserted {
            next.append(RetainedOwnedPhysicalReference(member: member, field: field, actual: actual, holder: self))
        }
        fields[field] = next.isEmpty ? nil : next
    }

    fileprivate func remove(
        field: RetainedOwnedPhysicalReferenceField, slots: Bool? = nil,
        member: ObjectIdentifier? = nil
    ) {
        let previous = fields[field] ?? []
        var retained: [RetainedOwnedPhysicalReference] = []
        for reference in previous {
            if (slots == nil || reference.member.isSlot == slots)
                && (member == nil || reference.member.identity == member)
            {
                reference.withdraw()
            } else {
                retained.append(reference)
            }
        }
        fields[field] = retained.isEmpty ? nil : retained
    }

    fileprivate func removeAllFields() {
        let original = originalReferences
        for reference in original { reference.withdraw() }
        fields.removeAll()
    }

    fileprivate func removeDeclarationFields() {
        for field in Array(fields.keys) {
            if case .declaration = field { remove(field: field) }
        }
    }

    /// Proof-only rotation invalidates aliases without deciding root-owned
    /// declaration lifetime. An actual native withdrawal additionally settles
    /// only this original cohort's regionless descriptor members.
    func invalidateBinding(retiringOwnedReferences: Bool) {
        let original = originalReferences
        storage = nil
        for reference in original { reference.withdraw() }
        fields.removeAll()
        if retiringOwnedReferences {
            var seen: Set<ObjectIdentifier> = []
            for reference in original where seen.insert(reference.member.identity).inserted {
                reference.member.retireAfterRawWithdrawalIfUnreferenced()
            }
        }
    }
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
    fileprivate weak var ownedPhysicalReferences: RetainedOwnedPhysicalReferenceHolder?
    fileprivate var ownedCandidateField: RetainedOwnedCandidateField?
    fileprivate var ownedCandidateBoundarySource: RetainedOwnedCandidateConstruction?
    fileprivate var ownedCandidateDeferredSource: RetainedOwnedCandidateConstruction?
    fileprivate var ownedCandidateDeferredAnchor: RetainedOwnedCandidateDeferredAnchor?
    private weak var ownedMapObservation: RetainedOwnedPhysicalMapObservation?
    private weak var ownedBindingObservation: RetainedOwnedPhysicalMapObservation?
    fileprivate var ownedPayloadPermissions: [AnyKeyPath: [RetainedOwnedSlotPermission]] = [:] {
        willSet { ownedMapObservation = nil }
    }
    fileprivate var ownedStructuralPermissions: [RetainedOwnedSlotPermission] = [] {
        willSet { ownedMapObservation = nil }
    }
    fileprivate var ownedEmptyStructuralPermissions: [ObjectIdentifier: [RetainedOwnedSlotPermission]] = [:] {
        willSet { ownedMapObservation = nil }
    }
    fileprivate var ownedEmptyStructuralNamespaces: [ObjectIdentifier: RetainedOwnedMarkerNamespaces] = [:] {
        willSet { ownedMapObservation = nil }
    }
    fileprivate var ownedDeclaredStructuralPermissions: [ObjectIdentifier: [RetainedOwnedSlotPermission]] = [:] {
        willSet { ownedMapObservation = nil }
    }
    fileprivate var ownedDeclaredStructuralNamespaces: [ObjectIdentifier: RetainedOwnedMarkerNamespaces] = [:] {
        willSet { ownedMapObservation = nil }
    }
    fileprivate var ownedPayloadComponents: [AnyKeyPath: [RetainedOwnedComponentPresence]] = [:] {
        willSet { ownedMapObservation = nil }
    }
    fileprivate var ownedStructuralComponents: [RetainedOwnedComponentPresence] = [] {
        willSet { ownedMapObservation = nil }
    }
    fileprivate var ownedEmptyStructuralComponents: [ObjectIdentifier: RetainedOwnedComponentPresence] = [:] {
        willSet { ownedMapObservation = nil }
    }
    fileprivate var ownedEmptyRowRevisions: [ObjectIdentifier: RetainedOwnedEmptyRowRevision] = [:] {
        willSet { ownedMapObservation = nil }
    }
    fileprivate var ownedDeclaredStructuralComponents: [ObjectIdentifier: RetainedOwnedComponentPresence] = [:] {
        willSet { ownedMapObservation = nil }
    }
    fileprivate var ownedDeclaredStructuralRevision: UInt64 = 0 {
        willSet { ownedMapObservation = nil }
    }
    fileprivate var ownedRegionStructuralPermissions: [ObjectIdentifier: [RetainedOwnedSlotPermission]] = [:] {
        willSet { ownedMapObservation = nil }
    }
    fileprivate var ownedRegionStructuralComponents: [ObjectIdentifier: [RetainedOwnedComponentPresence]] = [:] {
        willSet { ownedMapObservation = nil }
    }
    fileprivate var ownedDeferredRegions: [ObjectIdentifier: RetainedOwnedStructuralRegion] = [:] {
        willSet { ownedMapObservation = nil }
    }
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
        let actual = RetainedLazyListActualAttachment(
            node: node, runtime: runtime, target: targetID, attachment: attachmentID)
        actual.ownedPhysicalReferences = node.captureOwnedPhysicalReferences(for: self)
        return actual
    }

    func captureOwnedPhysicalReferenceHolder() -> RetainedOwnedPhysicalReferenceHolder {
        if let holder = ownedPhysicalReferences, holder.matches(self) { return holder }
        return RetainedOwnedPhysicalReferenceHolder(storage: self)
    }

    fileprivate func captureOwnedMapObservation() -> RetainedOwnedPhysicalMapObservation {
        if let observation = ownedMapObservation { return observation }
        let observation = RetainedOwnedPhysicalMapObservation()
        ownedMapObservation = observation
        return observation
    }

    fileprivate func matchesOwnedMapObservation(_ observation: RetainedOwnedPhysicalMapObservation) -> Bool {
        ownedMapObservation === observation
    }

    fileprivate func captureOwnedBindingObservation() -> RetainedOwnedPhysicalMapObservation {
        if let observation = ownedBindingObservation { return observation }
        let observation = RetainedOwnedPhysicalMapObservation()
        ownedBindingObservation = observation
        return observation
    }

    fileprivate func matchesOwnedBindingObservation(_ observation: RetainedOwnedPhysicalMapObservation) -> Bool {
        ownedBindingObservation === observation
    }

    fileprivate func publishOwnedReferences(
        _ permissions: [RetainedOwnedSlotPermission], field: RetainedOwnedPhysicalReferenceField,
        actual: RetainedLazyListActualAttachment
    ) {
        guard let holder = actual.ownedPhysicalReferences, holder.matches(self) else { return }
        holder.replace(permissions.map { .slot($0) }, slots: true, field: field, actual: actual)
    }

    fileprivate func publishOwnedReferences(
        components: [RetainedOwnedComponentPresence], field: RetainedOwnedPhysicalReferenceField,
        actual: RetainedLazyListActualAttachment
    ) {
        guard let holder = actual.ownedPhysicalReferences, holder.matches(self) else { return }
        holder.replace(components.map { .component($0) }, slots: false, field: field, actual: actual)
    }

    func withdrawOwnedPhysicalReferences() {
        withdrawOwnedCandidateField()
        ownedMapObservation = nil
        ownedBindingObservation = nil
        ownedPhysicalReferences?.invalidateBinding(retiringOwnedReferences: true)
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
        ownedPhysicalReferences?.invalidateBinding(retiringOwnedReferences: false)
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
        ownedCandidateDeferredAnchor = nil
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
    private var selectedTaskOutputs: [ObjectIdentifier: [RetainedLazyListSourceOutput]] = [:]
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
        _ source: ViewNode, attribution: RetainedLazyListBuildAttribution, group: RetainedLazyListGroupID,
        selectedContentPath: RetainedSelectedContentPath? = nil,
        candidateConstruction: RetainedOwnedCandidateConstruction? = nil
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
        if selectedContentPath != nil || candidateConstruction != nil {
            guard requested.kind == .scopedTask, !result.selectedTaskRouteWasRequested else { return nil }
            result.selectedTaskRouteWasRequested = true
            guard let path = selectedContentPath, let boundaries = path.boundaryNodes,
                let qualification = captureOwnedCandidateTaskQualification(
                    context: candidateConstruction, sourceBoundaries: boundaries, attribution: attribution)
            else { return nil }
            let middleFacets = boundaries.dropFirst().map { _ in
                RetainedLazyListSourceFacet(
                    source: result.payload, component: result.component, group: result.group,
                    nativeField: .childAttachment)
            }
            guard
                let route = RetainedTaskSelectedContentRoute(
                    physicalSource: source, path: path, physicalFacet: result.facet(.childAttachment).id,
                    middleFacets: middleFacets.map(\.id), qualification: qualification), let sources = route.sourcePins
            else { return nil }
            result.selectedTaskRoute = route
            result.selectedTaskMiddleFacets = middleFacets
            for facet in middleFacets { requested.require(facet) }
            for node in sources { selectedTaskOutputs[ObjectIdentifier(node), default: []].append(result) }
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

    private func selectedTaskOutputs(of source: ViewNode) -> [RetainedLazyListSourceOutput] {
        selectedTaskOutputs[ObjectIdentifier(source)]?.filter { output in
            output.selectedTaskRoute?.contains(source) == true
                && groups[ObjectIdentifier(output.group)]?.outputs.contains(where: { $0 === output }) == true
        } ?? []
    }

    private func prepareSelectedTaskMappings(
        from source: ViewNode, to target: ViewNode,
        targetID: RetainedLazyListTargetID, attachmentID: RetainedLazyListAttachmentID
    ) {
        for output in selectedTaskOutputs(of: source) {
            output.selectedTaskRoute?.prepareMapping(
                from: source, to: target, targetID: targetID, attachmentID: attachmentID)
        }
    }

    private func selectedTaskFacets(
        of source: ViewNode, field: RetainedLazyListNativeFacet? = nil
    ) -> [RetainedLazyListSourceFacet] {
        selectedTaskOutputs(of: source).flatMap { output in
            (Array(output.facets.values) + output.selectedTaskMiddleFacets).filter { facet in
                (field == nil || facet.nativeField.key == field?.key)
                    && output.selectedTaskRoute?.owns(facet.id, field: facet.nativeField, on: source) == true
            }
        }
    }

    private func permitsSelectedTaskFacet(
        _ facet: RetainedLazyListSourceFacet, actual: RetainedLazyListActualAttachment
    ) -> Bool {
        guard let output = groups[ObjectIdentifier(facet.group)]?.outputs.first(where: { $0.payload === facet.source }),
            output.selectedTaskRouteWasRequested
        else { return true }
        return output.selectedTaskRoute?.permitsNativeFacet(facet.id, field: facet.nativeField, on: actual) == true
    }

    func prepareSelectedTaskSourceChildren(
        from sourceParent: ViewNode?, to targetParent: ViewNode,
        proposedChildren: [ViewNode], incomingNodes: [ViewNode]
    ) -> RetainedSelectedContentSourceAdoption? {
        guard canContinueAdoption else { return nil }
        var routes: [RetainedTaskSelectedContentRoute] = []
        if let sourceParent {
            routes.append(contentsOf: selectedTaskOutputs(of: sourceParent).compactMap(\.selectedTaskRoute))
        }
        for node in incomingNodes {
            routes.append(contentsOf: selectedTaskOutputs(of: node).compactMap(\.selectedTaskRoute))
        }
        routes.append(
            contentsOf: ordinaryLedger?.selectedTaskRoutes(
                from: sourceParent, incomingNodes: incomingNodes) ?? [])
        return prepareRetainedTaskSourceChildren(
            routes: routes, sourceParent: sourceParent, targetParent: targetParent,
            proposedChildren: proposedChildren, incomingNodes: incomingNodes)
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
        prepareSelectedTaskMappings(
            from: source, to: target, targetID: actual.target, attachmentID: actual.attachment)
        let taskFacets = selectedTaskFacets(of: source, field: field)
        let hasPayload = source.retainedSourcePayloadFields.contains(keyPath)
        for output in outputs where !output.selectedTaskRouteWasRequested {
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
            previous: Array(previous), taskFacets: taskFacets)
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
        let selfPublication = ownedLedger?.preparedCandidateSelfPublication(from: source, to: target)
        _ = ordinaryLedger?.recordAcceptedProperty(
            from: source, to: target, keyPath: keyPath, selfPublication: selfPublication)
        for absence in ordinaryLedger?.takePropertyAbsences() ?? [] {
            boundDescriptorScope?.recordAcceptedOriginalRetirement(absence.previous)
            claimDescriptorTaskAbsence(absence)
            selfPublication?.recordDrainedOwnAbsence(absence)
        }
        if let selfPublication { ownedLedger?.finishCandidateSelfPublication(selfPublication) }
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
        for output in ownedOutputs(of: source) where !output.selectedTaskRouteWasRequested {
            guard let facet = output.facets[RetainedLazyListNativeFacet.nodeProperty(keyPath).key] else { continue }
            recordAcceptedFacet(facet, actual: actual)
        }
        for facet in pending.taskFacets where permitsSelectedTaskFacet(facet, actual: actual) {
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
        if let selfPublication = ownedLedger?.preparedCandidateSelfPublication(from: source, to: target) {
            ownedLedger?.finishCandidateSelfPublication(selfPublication)
        }
        for output in ownedOutputs(of: source) where !output.selectedTaskRouteWasRequested {
            if let facet = output.facets[.attachment] { recordAcceptedFacet(facet, actual: actual) }
        }
        for facet in selectedTaskFacets(of: source, field: .childAttachment)
        where permitsSelectedTaskFacet(facet, actual: actual) {
            recordAcceptedFacet(facet, actual: actual)
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
        let selfPublication = ownedLedger?.preparedCandidateSelfPublication(from: source, to: target)
        _ = ordinaryLedger?.recordCompletedNode(from: source, to: target, selfPublication: selfPublication)
        for absence in ordinaryLedger?.takePropertyAbsences() ?? [] {
            boundDescriptorScope?.recordAcceptedOriginalRetirement(absence.previous)
            claimDescriptorTaskAbsence(absence)
            selfPublication?.recordDrainedOwnAbsence(absence)
        }
        if let selfPublication { ownedLedger?.finishCandidateSelfPublication(selfPublication) }
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
        prepareSelectedTaskMappings(
            from: source, to: target, targetID: actual.target, attachmentID: actual.attachment)
        let acceptedIDs = Set(declarationIDs.map { ObjectIdentifier($0) })
        for output in ownedOutputs(of: source) where !output.selectedTaskRouteWasRequested {
            for facet in output.facets.values {
                guard case .scopedTaskDeclaration(let id) = facet.nativeField,
                    acceptedIDs.contains(ObjectIdentifier(id))
                else { continue }
                recordAcceptedFacet(facet, actual: actual)
            }
        }
        for facet in selectedTaskFacets(of: source) {
            guard case .scopedTaskDeclaration(let id) = facet.nativeField,
                acceptedIDs.contains(ObjectIdentifier(id)), permitsSelectedTaskFacet(facet, actual: actual)
            else { continue }
            recordAcceptedFacet(facet, actual: actual)
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
                origin: .descriptor(component: fact.proposal.component), anchor: structuralAnchor,
                acceptedDescriptorEmpty: fact)
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
            var routedTaskMembers: [RetainedLazyListAcceptedTaskMember]?
            if record.kind == .scopedTask, record.outputs.contains(where: \.selectedTaskRouteWasRequested) {
                guard !record.declarations.isEmpty else { continue }
                let inputs = record.outputs.compactMap { output -> RetainedTaskRouteJoinInput? in
                    guard let source = output.node,
                        !output.selectedTaskRouteWasRequested || output.selectedTaskRoute != nil
                    else { return nil }
                    let outputFacts = facts.filter { $0.source.source === output.payload }
                    return RetainedTaskRouteJoinInput(
                        payload: output.payload, source: source, route: output.selectedTaskRoute,
                        requiredFacets: outputFacts.map { $0.source.id },
                        facts: outputFacts.map {
                            RetainedTaskRouteNativeFact(
                                id: $0.source.id, field: $0.source.nativeField, actual: $0.actual)
                        })
                }
                guard inputs.count == record.outputs.count, let joined = joinRetainedTaskRoutes(inputs) else {
                    continue
                }
                actuals = joined.actuals
                routedTaskMembers = joined.members
            } else {
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
                let members =
                    routedTaskMembers
                    ?? record.outputs.compactMap { output -> RetainedLazyListAcceptedTaskMember? in
                        let outputFacts = facts.filter { $0.source.source === output.payload }
                        guard let actual = outputFacts.first?.actual else { return nil }
                        return RetainedLazyListAcceptedTaskMember(
                            sourcePayload: output.payload, requiredFacets: outputFacts.map { $0.source.id },
                            actual: actual)
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
                    guard fact.source.source === member.sourcePayload else { return false }
                    if let route = output.selectedTaskRoute {
                        return route.matchesAcceptedFact(
                            RetainedTaskRouteNativeFact(id: id, field: fact.source.nativeField, actual: fact.actual),
                            member: member)
                    }
                    return !output.selectedTaskRouteWasRequested && member.physicalActual == nil
                        && member.selectedContentPath == nil && fact.actual.target === member.actual.target
                        && fact.actual.attachment === member.actual.attachment
                })
            else { return nil }
            if let route = output.selectedTaskRoute {
                guard route.physicalSource === source, let activitySource = route.activitySource else { return nil }
                pins.append(
                    RetainedLazyListAcceptedTaskSource(member: member, source: source, activitySource: activitySource))
            } else {
                pins.append(RetainedLazyListAcceptedTaskSource(member: member, source: source))
            }
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
        prepareSelectedTaskMappings(
            from: source, to: source, targetID: storage.targetID, attachmentID: storage.attachmentID)
        var facets: [RetainedLazyListSourceFacet] = []
        for output in ownedOutputs(of: source) where !output.selectedTaskRouteWasRequested {
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
        for facet in selectedTaskFacets(of: source) {
            if case .scopedTaskDeclaration(let declaration) = facet.nativeField,
                !candidates.contains(where: {
                    $0.group === facet.group && $0.declarations.contains(where: { $0 === declaration })
                })
            {
                continue
            }
            facets.append(facet)
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
        for facet in pending.nativeFacets where permitsSelectedTaskFacet(facet, actual: actual) {
            recordAcceptedFacet(facet, actual: actual)
        }
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
        node.retainedLazyListActivityStorage?.withdrawOwnedCandidateField()
        _ = recordLogicalDescriptorDeparture(of: node, cause: cause)
        if retireOwned {
            ownedLedger?.recordPhysicalDeparture(of: node, cause: cause)
        } else if let snapshot = ownedLedger?.capturePhysicalDeparture(of: node, cause: cause) {
            let key = ObjectIdentifier(node)
            if pendingOwnedDepartures[key]?.contains(where: {
                $0.targetID === snapshot.targetID && $0.attachmentID === snapshot.attachmentID && !$0.wasConsumed
            }) != true {
                snapshot.admitOriginalRetirementDebts()
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
        node.retainedLazyListActivityStorage?.withdrawOwnedCandidateField()
        _ = recordLogicalDescriptorDeparture(of: node, cause: cause)
        var ticket: RetainedOrdinaryOwnedDeparture?
        if let ledger = ownedLedger, let original = ledger.capturePhysicalDeparture(of: node, cause: cause) {
            let key = ObjectIdentifier(node)
            let alreadyPending =
                pendingOwnedDepartures[key]?.contains {
                    $0.targetID === original.targetID && $0.attachmentID === original.attachmentID && !$0.wasConsumed
                } == true
            if !alreadyPending {
                original.admitOriginalRetirementDebts()
                // Publish custody before weak continuation queries. A nested
                // seal/release must be able to consume this same original.
                pendingOwnedDepartures[key, default: []].append(original)
                if canContinueAdoption, let partition = ledger.partitionOrdinaryDeparture(original) {
                    if var current = pendingOwnedDepartures[key],
                        let position = current.firstIndex(where: { $0 === original })
                    {
                        partition.pending.suspendOwnedWrites()
                        current[position] = partition.pending
                        pendingOwnedDepartures[key] = current
                        ticket = RetainedOrdinaryOwnedDeparture(
                            attempt: attempt, node: key, snapshot: partition.pending)
                        ledger.recordPhysicalDeparture(partition.immediate)
                    } else {
                        // No new queue entry or write permission may be created
                        // after loss of the original custody association.
                        ledger.recordPhysicalDeparture(partition.immediate)
                        ledger.recordPhysicalDeparture(partition.pending)
                    }
                } else {
                    ledger.recordPhysicalDeparture(original)
                    removeSpentOwnedDepartures([original], at: key)
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
        removeSpentOwnedDepartures(snapshots, at: key)
    }

    private func finishPendingOwnedDepartures() {
        let original = pendingOwnedDepartures
        for snapshots in original.values {
            for snapshot in snapshots where !snapshot.wasConsumed { ownedLedger?.recordPhysicalDeparture(snapshot) }
        }
        for (key, snapshots) in original { removeSpentOwnedDepartures(snapshots, at: key) }
    }

    private func removeSpentOwnedDepartures(
        _ original: [RetainedOwnedPhysicalDepartureSnapshot], at key: ObjectIdentifier
    ) {
        let spent = Set(original.filter(\.wasConsumed).map { ObjectIdentifier($0) })
        guard !spent.isEmpty, let current = pendingOwnedDepartures[key] else { return }
        let remaining = current.filter { !spent.contains(ObjectIdentifier($0)) }
        pendingOwnedDepartures[key] = remaining.isEmpty ? nil : remaining
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
        finishPendingOwnedDepartures()
        ownedLedger?.finishPendingDeclaredMarkerRetirements()
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
        finishPendingOwnedDepartures()
        ownedLedger?.finishPendingDeclaredMarkerRetirements()
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
            finishPendingOwnedDepartures()
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
        _ source: ViewNode, group: RetainedDescriptorGroupID,
        selectedContentPath: RetainedSelectedContentPath? = nil,
        candidateConstruction: RetainedOwnedCandidateConstruction? = nil
    ) -> RetainedLazyListSourcePayloadID? {
        ledger?.recordTaskSourceOutput(
            source, attribution: self, group: group, selectedContentPath: selectedContentPath,
            candidateConstruction: candidateConstruction)
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
    let nodeIdentity: ObjectIdentifier
    let component: RetainedDescriptorComponentID
    let group: RetainedDescriptorGroupID
    let constructionComponent: RetainedDescriptorComponentID
    let payload = RetainedLazyListSourcePayloadID()
    fileprivate var facets: [RetainedLazyListFacetKey: RetainedDescriptorSourceFacet] = [:]
    fileprivate var retirementProperties: Set<RetainedLazyListFacetKey> = []
    fileprivate var selectedTaskRouteWasRequested = false
    fileprivate var selectedTaskRoute: RetainedTaskSelectedContentRoute?
    fileprivate var selectedTaskMiddleFacets: [RetainedDescriptorSourceFacet] = []

    init(
        node: ViewNode, component: RetainedDescriptorComponentID, group: RetainedDescriptorGroupID,
        constructionComponent: RetainedDescriptorComponentID
    ) {
        self.node = node
        nodeIdentity = ObjectIdentifier(node)
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
    private(set) var outputs: [RetainedDescriptorSourceOutput] = []
    private(set) var required: [RetainedDescriptorSourceFacet] = []
    private var outputIndices: [ObjectIdentifier: Int] = [:]
    private var requiredIDs: Set<ObjectIdentifier> = []
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

    func output(for node: ViewNode) -> RetainedDescriptorSourceOutput? {
        // The index covers every append and removal, but cannot keep nodes alive.
        // An expired node's reused address must still match the weak reference.
        guard let index = outputIndices[ObjectIdentifier(node)], outputs.indices.contains(index),
            outputs[index].node === node
        else { return nil }
        return outputs[index]
    }

    func appendOutput(_ output: RetainedDescriptorSourceOutput) {
        outputIndices[output.nodeIdentity] = outputs.count
        outputs.append(output)
    }

    func require(_ facet: RetainedDescriptorSourceFacet) {
        if requiredIDs.insert(ObjectIdentifier(facet.id)).inserted { required.append(facet) }
    }

    func removeOutputs(with payloads: Set<ObjectIdentifier>) {
        // Preserve both array orders and the existing release order. Rebuild
        // only native metadata, without loading any surviving weak node.
        outputs.removeAll { payloads.contains(ObjectIdentifier($0.payload)) }
        required.removeAll { payloads.contains(ObjectIdentifier($0.source)) }
        outputIndices.removeAll(keepingCapacity: true)
        for (index, output) in outputs.enumerated() { outputIndices[output.nodeIdentity] = index }
        requiredIDs = Set(required.map { ObjectIdentifier($0.id) })
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
    private var selectedTaskOutputs: [ObjectIdentifier: [RetainedDescriptorSourceOutput]] = [:]
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
            record.removeOutputs(with: payloads)
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
        group: RetainedDescriptorGroupID, selectedContentPath: RetainedSelectedContentPath? = nil,
        candidateConstruction: RetainedOwnedCandidateConstruction? = nil
    ) -> RetainedLazyListSourcePayloadID? {
        guard let record = groups[ObjectIdentifier(group)], record.kind == .scopedTask,
            recordSourceOutput(source, attribution: attribution, group: group),
            let output = record.output(for: source)
        else { return nil }
        if selectedContentPath != nil || candidateConstruction != nil {
            guard !output.selectedTaskRouteWasRequested else { return nil }
            output.selectedTaskRouteWasRequested = true
            guard let path = selectedContentPath, let boundaries = path.boundaryNodes,
                let qualification = captureOwnedCandidateTaskQualification(
                    context: candidateConstruction, sourceBoundaries: boundaries, attribution: attribution)
            else { return nil }
            let middleFacets = boundaries.dropFirst().map { _ in
                RetainedDescriptorSourceFacet(
                    component: output.component, group: output.group, source: output.payload,
                    nativeField: .childAttachment)
            }
            guard
                let route = RetainedTaskSelectedContentRoute(
                    physicalSource: source, path: path, physicalFacet: output.facet(.childAttachment).id,
                    middleFacets: middleFacets.map(\.id), qualification: qualification), let sources = route.sourcePins
            else { return nil }
            output.selectedTaskRoute = route
            output.selectedTaskMiddleFacets = middleFacets
            for facet in middleFacets { record.require(facet) }
            for node in sources { selectedTaskOutputs[ObjectIdentifier(node), default: []].append(output) }
        }
        return output.payload
    }

    fileprivate func contribution(
        for group: RetainedDescriptorGroupID, attribution: RetainedDescriptorComponentAttribution
    ) -> RetainedDescriptorContributionReceipt? {
        guard attribution.ledger === self, attribution.attempt === attempt,
            let record = groups[ObjectIdentifier(group)], record.component === attribution.component
        else { return nil }
        return record.receipt
    }

    fileprivate func frozenOwnedCandidateDeferredGroup(
        component: RetainedDescriptorComponentID, source: ViewNode
    ) -> RetainedDescriptorContributionReceipt? {
        guard isFrozen, !rejectedComponentIDs.contains(ObjectIdentifier(component)),
            let outputs = ownedOutputs(of: source)
        else { return nil }
        let matches = groups.values.filter { record in
            record.component === component && record.kind == .deferredSubtree && record.isClosed
                && !invalidIDs.contains(ObjectIdentifier(record.id)) && !record.required.isEmpty
                && record.outputs.contains(where: { output in
                    output.node === source && outputs.contains(where: { $0 === output })
                })
        }
        guard matches.count == 1 else { return nil }
        return matches.first?.receipt
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
        guard record.output(for: source) == nil else { return }
        let output = RetainedDescriptorSourceOutput(
            node: source, component: record.component, group: record.id, constructionComponent: component)
        record.appendOutput(output)
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

    private func selectedTaskOutputs(of source: ViewNode) -> [RetainedDescriptorSourceOutput] {
        selectedTaskOutputs[ObjectIdentifier(source)]?.filter { output in
            output.selectedTaskRoute?.contains(source) == true
                && groups[ObjectIdentifier(output.group)]?.outputs.contains(where: { $0 === output }) == true
        } ?? []
    }

    fileprivate func selectedTaskRoutes(
        from sourceParent: ViewNode?, incomingNodes: [ViewNode]
    ) -> [RetainedTaskSelectedContentRoute] {
        var result: [RetainedTaskSelectedContentRoute] = []
        if let sourceParent {
            result.append(contentsOf: selectedTaskOutputs(of: sourceParent).compactMap(\.selectedTaskRoute))
        }
        for node in incomingNodes {
            result.append(contentsOf: selectedTaskOutputs(of: node).compactMap(\.selectedTaskRoute))
        }
        return result
    }

    private func prepareSelectedTaskMappings(
        from source: ViewNode, to target: ViewNode,
        targetID: RetainedLazyListTargetID, attachmentID: RetainedLazyListAttachmentID
    ) {
        for output in selectedTaskOutputs(of: source) {
            output.selectedTaskRoute?.prepareMapping(
                from: source, to: target, targetID: targetID, attachmentID: attachmentID)
        }
    }

    private func selectedTaskFacets(
        of source: ViewNode, field: RetainedLazyListNativeFacet? = nil
    ) -> [RetainedDescriptorSourceFacet] {
        selectedTaskOutputs(of: source).flatMap { output in
            (Array(output.facets.values) + output.selectedTaskMiddleFacets).filter { facet in
                (field == nil || facet.nativeField.key == field?.key)
                    && output.selectedTaskRoute?.owns(facet.id, field: facet.nativeField, on: source) == true
            }
        }
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
        prepareSelectedTaskMappings(
            from: source, to: target, targetID: actual.target, attachmentID: actual.attachment)
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
            facets: outputs.filter { !$0.selectedTaskRouteWasRequested }.map { $0.facet(.nodeProperty(keyPath)) }
                + selectedTaskFacets(of: source, field: .nodeProperty(keyPath)), previous: Array(previous))
        return true
    }

    @discardableResult
    func recordAcceptedProperty(
        from source: ViewNode, to target: ViewNode, keyPath: PartialKeyPath<ViewNode>
    ) -> [RetainedDescriptorAcceptedGroup] {
        recordAcceptedProperty(from: source, to: target, keyPath: keyPath, selfPublication: nil)
    }

    @discardableResult
    fileprivate func recordAcceptedProperty(
        from source: ViewNode, to target: ViewNode, keyPath: PartialKeyPath<ViewNode>,
        selfPublication: RetainedOwnedCandidateSelfPublication?
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
            if let fact = recordAcceptedAbsence(
                previous: previous, actual: actual, removalFacets: removed, selfPublication: selfPublication)
            {
                propertyAbsences.append(fact)
            }
        }
        for facet in pending.facets { recordAcceptedFacet(facet, actual: actual) }
        return completeGroups()
    }

    @discardableResult
    func recordAcceptedAttachment(from source: ViewNode, to target: ViewNode) -> [RetainedDescriptorAcceptedGroup] {
        guard let outputs = ownedOutputs(of: source), let actual = actualAttachment(for: target) else { return [] }
        for output in outputs where !output.selectedTaskRouteWasRequested {
            if let facet = output.facets[.attachment] { recordAcceptedFacet(facet, actual: actual) }
        }
        for facet in selectedTaskFacets(of: source, field: .childAttachment) {
            recordAcceptedFacet(facet, actual: actual)
        }
        return completeGroups()
    }

    @discardableResult
    func recordCompletedNode(from source: ViewNode, to target: ViewNode) -> [RetainedDescriptorAcceptedGroup] {
        recordCompletedNode(from: source, to: target, selfPublication: nil)
    }

    @discardableResult
    fileprivate func recordCompletedNode(
        from source: ViewNode, to target: ViewNode, selfPublication: RetainedOwnedCandidateSelfPublication?
    ) -> [RetainedDescriptorAcceptedGroup] {
        guard let outputs = ownedOutputs(of: source), let actual = actualAttachment(for: target) else { return [] }
        let incoming = outputs.compactMap { groups[ObjectIdentifier($0.group)]?.receipt }
        let previous = target.retainedLazyListActivityStorage?.committedDescriptorContributions.values.map { $0 } ?? []
        for receipt in previous where !incoming.contains(where: { $0 === receipt }) {
            let removed = receipt.acceptedFacets.filter {
                $0.nativeField.key == .completion && $0.actual.target === actual.target
                    && $0.actual.attachment === actual.attachment
            }.map(\.facet)
            if !removed.isEmpty,
                let fact = recordAcceptedAbsence(
                    previous: receipt, actual: actual, removalFacets: removed, selfPublication: selfPublication)
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
        prepareSelectedTaskMappings(
            from: source, to: target, targetID: actual.target, attachmentID: actual.attachment)
        let transported = Set(declarationIDs.map { ObjectIdentifier($0) })
        for output in outputs where !output.selectedTaskRouteWasRequested {
            guard groups[ObjectIdentifier(output.group)]?.kind == .scopedTask else { continue }
            for facet in output.facets.values {
                guard case .scopedTaskDeclaration(let declaration) = facet.nativeField,
                    transported.contains(ObjectIdentifier(declaration))
                else { continue }
                recordAcceptedFacet(facet, actual: actual)
            }
        }
        for facet in selectedTaskFacets(of: source) {
            guard case .scopedTaskDeclaration(let declaration) = facet.nativeField,
                transported.contains(ObjectIdentifier(declaration))
            else { continue }
            recordAcceptedFacet(facet, actual: actual)
        }
        return completeGroups()
    }

    func prepareInsertedNode(from source: ViewNode) -> Bool {
        guard let outputs = ownedOutputs(of: source), canPrepare(outputs) else { return false }
        let storage = source.lazyListActivityStorage()
        let key = ObjectIdentifier(storage.targetID)
        guard insertions[key] == nil else { return false }
        prepareSelectedTaskMappings(
            from: source, to: source, targetID: storage.targetID, attachmentID: storage.attachmentID)
        let candidates = source.existingRetainedTaskState?.descriptorCandidateDeclarations() ?? []
        var facets: [RetainedDescriptorSourceFacet] = []
        for output in outputs where !output.selectedTaskRouteWasRequested {
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
        for facet in selectedTaskFacets(of: source) {
            if case .scopedTaskDeclaration(let declaration) = facet.nativeField,
                !candidates.contains(where: {
                    $0.group === facet.group && $0.declarations.contains(where: { $0 === declaration })
                })
            {
                continue
            }
            facets.append(facet)
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
        if let output = groups[ObjectIdentifier(facet.group)]?.outputs.first(where: { $0.payload === facet.source }),
            output.selectedTaskRouteWasRequested,
            output.selectedTaskRoute?.permitsNativeFacet(facet.id, field: facet.nativeField, on: actual) != true
        {
            return
        }
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
            var routedTaskMembers: [RetainedLazyListAcceptedTaskMember]?
            if record.kind == .scopedTask, record.outputs.contains(where: \.selectedTaskRouteWasRequested) {
                let inputs = record.outputs.compactMap { output -> RetainedTaskRouteJoinInput? in
                    guard let source = output.node,
                        !output.selectedTaskRouteWasRequested || output.selectedTaskRoute != nil
                    else { return nil }
                    return RetainedTaskRouteJoinInput(
                        payload: output.payload, source: source, route: output.selectedTaskRoute,
                        requiredFacets: record.required.filter { $0.source === output.payload }.map(\.id),
                        facts: facts.filter { $0.source === output.payload }.map {
                            RetainedTaskRouteNativeFact(id: $0.facet, field: $0.nativeField, actual: $0.actual)
                        })
                }
                guard inputs.count == record.outputs.count, let joined = joinRetainedTaskRoutes(inputs) else {
                    continue
                }
                actuals = joined.actuals
                routedTaskMembers = joined.members
            } else {
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
                    for output in record.outputs {
                        guard let source = output.node,
                            facts.contains(where: {
                                $0.source === output.payload && $0.actual.target === actual.target
                                    && $0.actual.attachment === actual.attachment
                            })
                        else { continue }
                        components[ObjectIdentifier(record.component)]?.scope?.ownedLedger
                            .recordCandidateDeferredAcceptance(
                                source: source, actual: actual, contribution: record.receipt)
                    }
                }
            }
            if record.kind == .scopedTask {
                let members =
                    routedTaskMembers
                    ?? record.outputs.compactMap { output -> RetainedLazyListAcceptedTaskMember? in
                        guard let actual = facts.first(where: { $0.source === output.payload })?.actual else {
                            return nil
                        }
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
                    guard fact.source === member.sourcePayload else { return false }
                    if let route = output.selectedTaskRoute {
                        return route.matchesAcceptedFact(
                            RetainedTaskRouteNativeFact(id: id, field: fact.nativeField, actual: fact.actual),
                            member: member)
                    }
                    return !output.selectedTaskRouteWasRequested && member.physicalActual == nil
                        && member.selectedContentPath == nil && fact.actual.target === member.actual.target
                        && fact.actual.attachment === member.actual.attachment
                })
            else { return nil }
            if let route = output.selectedTaskRoute {
                guard route.physicalSource === source, let activitySource = route.activitySource else { return nil }
                pins.append(
                    RetainedLazyListAcceptedTaskSource(member: member, source: source, activitySource: activitySource))
            } else {
                pins.append(RetainedLazyListAcceptedTaskSource(member: member, source: source))
            }
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
        recordAcceptedAbsence(previous: previous, actual: actual, removalFacets: removalFacets, selfPublication: nil)
    }

    @discardableResult
    fileprivate func recordAcceptedAbsence(
        previous: RetainedDescriptorContributionReceipt, actual: RetainedLazyListActualAttachment,
        removalFacets: [RetainedLazyListSourceFacetID], selfPublication: RetainedOwnedCandidateSelfPublication?
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
        selfPublication?.recordFirstOwnAbsence(fact)
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

    /// Permanent revocation of this original native generation.
    package var isRevoked: Bool { wasRevoked }
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
    var ownedReferenceIndex: RetainedOwnedPhysicalReferenceIndex?
    var deferredRegion: RetainedOwnedStructuralRegion?
    var declaredRegions: [ObjectIdentifier: RetainedOwnedStructuralRegion] = [:]
    fileprivate weak var ownedCandidateField: RetainedOwnedCandidateField?

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
        ownedCandidateField?.withdraw()
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
    fileprivate var ownedReferenceIndex: RetainedOwnedPhysicalReferenceIndex?

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
    let candidateConstruction: RetainedOwnedCandidateConstruction?

    init(
        origin: RetainedOwnedComponentDeclarationOrigin, receipt: RetainedOwnedComponentReceipt,
        previous: [RetainedOwnedComponentReceipt], declarationOnly: Bool,
        isDeferredConstruction: Bool, candidateConstruction: RetainedOwnedCandidateConstruction? = nil
    ) {
        self.origin = origin
        self.receipt = receipt
        self.previous = previous
        self.declarationOnly = declarationOnly
        self.isDeferredConstruction = isDeferredConstruction
        self.candidateConstruction = candidateConstruction
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
    let candidateReader: RetainedOwnedCandidateChildSource?
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
    private let originalObservation: RetainedOwnedPhysicalMapObservation?
    private let originalBindingObservation: RetainedOwnedPhysicalMapObservation?
    private let originalBinding: RetainedOwnedPhysicalBindingID?
    private let originalReferences: [RetainedOwnedPhysicalReference]
    private var wasClaimed = false
    private var didClearOriginalMaps = false

    init(
        storage: RetainedLazyListNodeActivityStorage?, targetID: RetainedLazyListTargetID,
        attachmentID: RetainedLazyListAttachmentID
    ) {
        originalStorage = storage
        self.targetID = targetID
        self.attachmentID = attachmentID
        originalObservation = storage?.captureOwnedMapObservation()
        originalBindingObservation = storage?.captureOwnedBindingObservation()
        originalBinding = storage?.ownedPhysicalReferences?.identity
        originalReferences = storage?.ownedPhysicalReferences?.originalReferences ?? []
    }

    func removeOriginalMapsOnce() {
        guard !wasClaimed else { return }
        wasClaimed = true
        guard let storage = originalStorage, storage.targetID === targetID, storage.attachmentID === attachmentID,
            let originalObservation, storage.matchesOwnedMapObservation(originalObservation),
            matchesOriginalBinding(on: storage)
        else {
            return
        }
        for reference in originalReferences { reference.withdraw() }
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
            storage.targetID === targetID, storage.attachmentID === attachmentID,
            matchesOriginalBinding(on: storage)
        else { return nil }
        return storage
    }

    private func matchesOriginalBinding(on storage: RetainedLazyListNodeActivityStorage) -> Bool {
        // Arming an empty holder is a read, not a native field mutation. The
        // binding observation remains original even after a successful map
        // clear; actual storage withdrawal invalidates it before release.
        guard let originalBindingObservation, storage.matchesOwnedBindingObservation(originalBindingObservation) else {
            return false
        }
        guard let originalBinding else { return true }
        guard let holder = storage.ownedPhysicalReferences, holder.identity === originalBinding else { return false }
        return holder.matches(storage)
    }

    fileprivate static func removePhysicalMaps(from storage: RetainedLazyListNodeActivityStorage) {
        storage.ownedPhysicalReferences?.removeAllFields()
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
    private let sharedRemoval: RetainedOwnedPhysicalDepartureRemoval
    private var retirementDebts: [ObjectIdentifier: RetainedOwnedRetirementDebt] = [:]
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
        sharedRemoval = RetainedOwnedPhysicalDepartureRemoval(
            storage: storage, targetID: targetID, attachmentID: attachmentID)
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
        retirementDebts = original.retirementDebts.filter { identifier, _ in
            (permissions.contains(identifier) || components.contains(identifier)) == keepingMembers
        }
    }

    func partition(
        permissions: Set<ObjectIdentifier>, components: Set<ObjectIdentifier>
    ) -> (immediate: RetainedOwnedPhysicalDepartureSnapshot, pending: RetainedOwnedPhysicalDepartureSnapshot)? {
        guard !wasConsumed, regions.isEmpty, regionSlots.isEmpty, regionComponents.isEmpty,
            !permissions.isEmpty || !components.isEmpty
        else { return nil }
        let removal = sharedRemoval
        let immediate = RetainedOwnedPhysicalDepartureSnapshot(
            original: self, permissions: permissions, components: components, keepingMembers: false, removal: removal)
        let pending = RetainedOwnedPhysicalDepartureSnapshot(
            original: self, permissions: permissions, components: components, keepingMembers: true, removal: removal)
        // Transfer this one capture, without recapturing either physical maps
        // or authored payloads when the second cohort eventually retires.
        wasConsumed = true
        retirementDebts.removeAll()
        return (immediate, pending)
    }

    func removePhysicalMaps() {
        sharedRemoval.removeOriginalMapsOnce()
    }

    var laterPublicationStorage: RetainedLazyListNodeActivityStorage? {
        guard isPendingPartition else { return nil }
        return sharedRemoval.successfullyClearedOriginalStorage
    }

    /// Admission happens after the queue's duplicate check and before any
    /// weak-UI continuation selection. Partitioning transfers these same debts.
    func admitOriginalRetirementDebts() {
        guard !wasConsumed else { return }
        for permission in permissions {
            let identifier = ObjectIdentifier(permission)
            if retirementDebts[identifier] == nil {
                retirementDebts[identifier] = RetainedOwnedRetirementDebt(member: .slot(permission))
            }
        }
        for presence in components {
            let identifier = ObjectIdentifier(presence)
            if retirementDebts[identifier] == nil {
                retirementDebts[identifier] = RetainedOwnedRetirementDebt(member: .component(presence))
            }
        }
    }

    func spendOriginalRetirementDebts() {
        for debt in retirementDebts.values { debt.spend() }
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
    let retirementDebt: RetainedOwnedRetirementDebt

    init(
        attempt: RetainedLazyListAttemptID, member: Member, plans: [RetainedOwnedComponentDeclarationPlan],
        formerActual: RetainedLazyListActualAttachment, removalFacet: RetainedLazyListSourceFacetID
    ) {
        self.attempt = attempt
        self.member = member
        self.plans = plans
        self.formerActual = formerActual
        self.removalFacet = removalFacet
        switch member {
        case .slot(let permission): retirementDebt = RetainedOwnedRetirementDebt(member: .slot(permission))
        case .component(let presence): retirementDebt = RetainedOwnedRetirementDebt(member: .component(presence))
        }
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
    private var didSeedOwnedCandidateRoot = false
    private var candidateQualifications: [ObjectIdentifier: RetainedOwnedCandidateScopeQualification] = [:]
    private var candidateBoundaries: [ObjectIdentifier: RetainedOwnedCandidateConstruction] = [:]
    private var candidateSegments: [RetainedOwnedCandidateSegmentKey: RetainedOwnedCandidateConstruction] = [:]
    private var candidateAcceptedFacts: [RetainedOwnedCandidateAcceptedFact] = []
    private var candidateDeferredFacts: [RetainedOwnedCandidateDeferredFact] = []
    private var candidateAcceptedSegments: [ObjectIdentifier: RetainedOwnedCandidateSegmentAcceptance] = [:]
    private var isDrainingCandidateFacts = false
    // Child catalog records can only refuse or remove. They are deliberately
    // absent from the general field, reference, task and construction maps.
    private var candidateChildCatalogSources: [ObjectIdentifier: RetainedOwnedCandidateChildSource] = [:]
    private var candidateChildCatalogOriginalTargets: [ObjectIdentifier: RetainedOwnedCandidateCatalogNode] = [:]
    private var candidateChildCatalogPublications: [ObjectIdentifier: RetainedOwnedCandidateChildPublication] = [:]
    private var candidateChildCatalogSuccessors: [ObjectIdentifier: RetainedOwnedCandidateChildSuccessor] = [:]
    private var candidateSelfSources: [ObjectIdentifier: RetainedOwnedCandidateSelfSource] = [:]
    private var candidateSelfRegistrations: [ObjectIdentifier: RetainedOwnedCandidateSelfSource] = [:]
    private var candidateSelfPublications: [ObjectIdentifier: RetainedOwnedCandidateSelfPublication] = [:]
    private var candidateSelfBodyAcceptances: [ObjectIdentifier: RetainedOwnedCandidateSelfBodyAcceptance] = [:]
    private var candidatePublications: [RetainedOwnedCandidateWriteKey: RetainedOwnedCandidateCatalogPublication] = [:]
    private var candidatePreparedWrites: Set<RetainedOwnedCandidateWriteKey> = []
    private var candidateDepartureCustody: [RetainedOwnedCandidateDepartureCustody] = []
    private var candidateAcceptedCustody: [RetainedOwnedCandidateAcceptedCustody] = []
    private var candidateReferenceSuccessors: [ObjectIdentifier: RetainedOwnedCandidateReferenceSuccessor] = [:]
    private var candidateFieldSuccessors: [ObjectIdentifier: RetainedOwnedCandidateFieldSuccessor] = [:]
    private var candidateBoundaryActivationAttempts: Set<ObjectIdentifier> = []

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
        declarationOnly: Bool, candidateConstruction: RetainedOwnedCandidateConstruction? = nil
    ) -> RetainedOwnedComponentReceipt? {
        let origin = RetainedOwnedComponentDeclarationOrigin.descriptor(component: attribution.component)
        guard frozenPlans == nil, !wasFinished, attribution.descriptorBuildAttempt === attempt,
            candidateConstruction.map({ acceptsOwnedCandidateConstruction($0, attribution: attribution) }) != false,
            registrations[origin.key]?.contains(where: { $0.receipt.owner === owner }) != true,
            !declarationOnly || admitsDeclaredContinuation(owner: owner, slots: slots, continuing: continuing),
            let receipt = RetainedOwnedComponentReceipt.register(
                owner: owner, slots: slots, continuing: continuing, descriptorAttribution: attribution)
        else { return nil }
        return record(
            origin: origin, receipt: receipt, previous: continuing,
            declarationOnly: declarationOnly, isDeferredConstruction: false,
            candidateConstruction: candidateConstruction)
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
        previous: [RetainedOwnedComponentReceipt], declarationOnly: Bool, isDeferredConstruction: Bool,
        candidateConstruction: RetainedOwnedCandidateConstruction? = nil
    ) -> RetainedOwnedComponentReceipt? {
        guard registrations[origin.key]?.contains(where: { $0.receipt.owner === receipt.owner }) != true else {
            return nil
        }
        registrations[origin.key, default: []].append(
            RetainedOwnedComponentRegistration(
                origin: origin, receipt: receipt, previous: previous, declarationOnly: declarationOnly,
                isDeferredConstruction: isDeferredConstruction, candidateConstruction: candidateConstruction))
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
        return freezeCandidateChildCatalogSources() && freezeCandidateSelfSources()
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
                recordCandidateAcceptedFacts(declarations, source: source, actual: actual)
                fulfillDeclaredMarkerRetirements(declarations, source: source, storage: storage, actual: actual)
                return
            }
        }
        // Incoming exact generations become authoritative before retiring the
        // last outgoing payload reference and before its capture can deinit.
        let accepted = publish(
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
        if case .published(let successful) = accepted {
            recordCandidateAcceptedFacts(successful, source: source, actual: actual)
        }
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
            expectedStructuralRevision: storage.ownedDeclaredStructuralRevision,
            candidateReader: prepareCandidateReaderInsertion(from: source))
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
                recordCandidateAcceptedFacts(
                    declarations, source: node, actual: actual, insertedReader: publication.candidateReader)
                fulfillDeclaredMarkerRetirements(declarations, source: node, storage: storage, actual: actual)
                // Original regionless provenance makes the region queue empty.
                return
            }
        }
        let accepted = publish(
            publication.declarations, actual: actual, source: node, facet: nil, kind: .structuralEntry)
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
        if case .published(let successful) = accepted {
            recordCandidateAcceptedFacts(
                successful, source: node, actual: actual, insertedReader: publication.candidateReader)
        }
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
        let accepted = publish(declarations, actual: actual, source: source, facet: nil, kind: .structuralEntry)
        guard
            declarations.allSatisfy({
                !$0.receipt.owner.wasRevoked && $0.receipt.nativeLifetime.permitsConstruction
                    && $0.receipt.slotPermissions.allSatisfy { !$0.wasRevoked }
            })
        else { return }
        replaceStructural(on: storage, actual: actual, with: permissions)
        replaceComponentStructural(
            on: storage, actual: actual, with: declarations.map { $0.receipt.componentPresence })
        if case .published(let successful) = accepted {
            recordCandidateAcceptedFacts(successful, source: source, actual: actual)
        }
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
            recordCandidateAcceptedFacts(accepted, source: source, actual: actual)
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
                storage.ownedPhysicalReferences?.removeDeclarationFields()
                storage.ownedDeclaredStructuralPermissions.removeAll()
                storage.ownedDeclaredStructuralComponents.removeAll()
                storage.ownedDeclaredStructuralNamespaces.removeAll()
                for plan in declarations {
                    let owner = ObjectIdentifier(plan.receipt.owner)
                    storage.publishOwnedReferences(
                        plan.receipt.slotPermissions, field: .declaration(owner), actual: actual)
                    storage.ownedDeclaredStructuralPermissions[owner] = plan.receipt.slotPermissions
                    storage.publishOwnedReferences(
                        components: [plan.receipt.componentPresence], field: .declaration(owner), actual: actual)
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
        storage.ownedPhysicalReferences?.removeDeclarationFields()
        storage.ownedDeclaredStructuralPermissions.removeAll()
        storage.ownedDeclaredStructuralComponents.removeAll()
        storage.ownedDeclaredStructuralNamespaces.removeAll()
        for plan in publication.declarations {
            let owner = ObjectIdentifier(plan.receipt.owner)
            storage.publishOwnedReferences(plan.receipt.slotPermissions, field: .declaration(owner), actual: actual)
            storage.ownedDeclaredStructuralPermissions[owner] = plan.receipt.slotPermissions
            storage.publishOwnedReferences(
                components: [plan.receipt.componentPresence], field: .declaration(owner), actual: actual)
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
            ticket.retirementDebt.spend()
            ticket.finishOwnedWriteSuspension()
        }
    }

    func finishPendingDeclaredMarkerRetirements() {
        let original = Array(declaredMarkerRetirements.values)
        for ticket in original where !ticket.wasConsumed {
            // Mark it spent before retirement so no helper can defer it again.
            // Keep the original member entry until finish; reentry cannot rearm
            // this journal's already claimed handoff after an accepted prefix.
            ticket.wasConsumed = true
            ticket.retirementDebt.spend()
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
        origin: RetainedOwnedComponentDeclarationOrigin, anchor: RetainedLazyListActualAttachment,
        acceptedDescriptorEmpty: RetainedDescriptorAcceptedEmptyGroup? = nil
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
        let accepted = publish(exact, actual: anchor, source: nil, facet: nil, kind: .emptyStructuralEntry)
        for plan in exact {
            let owner = ObjectIdentifier(plan.receipt.owner)
            let previous = storage.ownedEmptyStructuralPermissions[owner] ?? []
            let next = plan.receipt.slotPermissions
            storage.publishOwnedReferences(next, field: .empty(owner), actual: anchor)
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
            storage.publishOwnedReferences(components: [presence], field: .empty(owner), actual: anchor)
            storage.ownedEmptyStructuralComponents[owner] = presence
            storage.ownedEmptyStructuralNamespaces[owner, default: RetainedOwnedMarkerNamespaces()].include(
                plan.structuralRegions)
            presence.structuralFacets[key] = anchor
        }
        if let acceptedDescriptorEmpty, case .published(let successful) = accepted {
            recordCandidateAcceptedFacts(
                successful, source: nil, actual: anchor, acceptedEmpty: acceptedDescriptorEmpty)
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
                storage.ownedPhysicalReferences?.remove(field: .empty(owner), slots: true)
                storage.ownedEmptyStructuralPermissions.removeValue(forKey: owner)
                for permission in permissions { removeStructuralReference(permission, storage: storage, key: key) }
            }
            for (owner, presence) in marker.components {
                storage.ownedPhysicalReferences?.remove(field: .empty(owner), slots: false)
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
            storage.publishOwnedReferences(Array(slots.values), field: .region(identifier), actual: actual)
            storage.ownedRegionStructuralPermissions[identifier] = Array(slots.values)
            storage.publishOwnedReferences(
                components: Array(components.values), field: .region(identifier), actual: actual)
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
        guard let storage = actual.originalOwnedReferenceStorage,
            storage.targetID === actual.target, storage.attachmentID === actual.attachment
        else { return }
        let identifier = ObjectIdentifier(region)
        storage.ownedPhysicalReferences?.remove(field: .region(identifier))
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
            guard let storage = actual.originalOwnedReferenceStorage,
                storage.targetID === actual.target, storage.attachmentID === actual.attachment
            else { continue }
            let owner = ObjectIdentifier(permission.owner)
            if let namespaces = storage.ownedEmptyStructuralNamespaces[owner],
                namespaces.regions[ObjectIdentifier(region)] === region,
                !namespaces.holds(permission, outside: region),
                let previous = storage.ownedEmptyStructuralPermissions[owner]
            {
                let next = previous.filter { $0 !== permission }
                storage.ownedPhysicalReferences?.remove(
                    field: .empty(owner), slots: true, member: ObjectIdentifier(permission))
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
                storage.ownedPhysicalReferences?.remove(
                    field: .declaration(owner), slots: true, member: ObjectIdentifier(permission))
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
            guard let storage = actual.originalOwnedReferenceStorage,
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
                    storage.ownedPhysicalReferences?.remove(
                        field: .empty(owner), slots: false, member: ObjectIdentifier(presence))
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
                    storage.ownedPhysicalReferences?.remove(
                        field: .declaration(owner), slots: false, member: ObjectIdentifier(presence))
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
            if let permission = old.permission, permission.ownedReferenceIndex?.hasCurrentCandidateReference != true {
                retire(permission)
            }
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
                storage.ownedPhysicalReferences?.remove(field: .empty(owner))
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
        snapshot.admitOriginalRetirementDebts()
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
        snapshot.spendOriginalRetirementDebts()
        defer { snapshot.finishOwnedWriteSuspension() }
        let cause = snapshot.cause
        snapshot.removePhysicalMaps()
        // A refused clear leaves its original aliases intact. A successful
        // clear withdraws them before map release; any remaining alias names a
        // separate accepted field publication. Neither case needs a weak UI
        // lookup or treats duplicate facts as independent physical references.
        for (field, permissions) in snapshot.payloads {
            let key = RetainedOwnedPhysicalFacetKey(
                target: ObjectIdentifier(snapshot.targetID), attachment: ObjectIdentifier(snapshot.attachmentID),
                field: field)
            for permission in permissions {
                if permission.ownedReferenceIndex?.contains(key) != true {
                    permission.payloadFacets.removeValue(forKey: key)
                }
                retireIfUnreferenced(permission, preservingCold: cause == .viewportEviction)
            }
        }
        let key = RetainedOwnedPhysicalFacetKey(
            target: ObjectIdentifier(snapshot.targetID), attachment: ObjectIdentifier(snapshot.attachmentID),
            field: nil)
        for permission in snapshot.structural + snapshot.emptyStructural {
            if permission.ownedReferenceIndex?.contains(key) != true {
                permission.structuralFacets.removeValue(forKey: key)
            }
            retireIfUnreferenced(permission, preservingCold: cause == .viewportEviction)
        }
        for (field, presences) in snapshot.componentPayloads {
            let key = RetainedOwnedPhysicalFacetKey(
                target: ObjectIdentifier(snapshot.targetID), attachment: ObjectIdentifier(snapshot.attachmentID),
                field: field)
            for presence in presences {
                if presence.ownedReferenceIndex?.contains(key) != true {
                    presence.payloadFacets.removeValue(forKey: key)
                }
                retireIfUnreferenced(presence, preservingCold: cause == .viewportEviction)
            }
        }
        for presence in snapshot.componentStructural {
            if presence.ownedReferenceIndex?.contains(key) != true {
                presence.structuralFacets.removeValue(forKey: key)
            }
            retireIfUnreferenced(presence, preservingCold: cause == .viewportEviction)
        }
        for (identifier, region) in snapshot.regions {
            let regionKey = RetainedOwnedPhysicalFacetKey(
                target: ObjectIdentifier(snapshot.targetID), attachment: ObjectIdentifier(snapshot.attachmentID),
                field: nil, region: identifier)
            for permission in snapshot.regionSlots[identifier] ?? [] {
                if permission.ownedReferenceIndex?.contains(regionKey) != true {
                    permission.structuralFacets.removeValue(forKey: regionKey)
                }
                retireIfUnreferenced(permission, preservingCold: cause == .viewportEviction)
            }
            for presence in snapshot.regionComponents[identifier] ?? [] {
                if presence.ownedReferenceIndex?.contains(regionKey) != true {
                    presence.structuralFacets.removeValue(forKey: regionKey)
                }
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
        let sourcePayloads: [RetainedLazyListSourcePayloadID] =
            source.map { source in
                var payloads: [RetainedLazyListSourcePayloadID] = []
                for record in sources {
                    if record.node === source { payloads.append(record.payload) }
                }
                return payloads
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
            if let presence = old.presence, presence.ownedReferenceIndex?.hasCurrentCandidateReference != true {
                retire(presence)
            }
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
        storage.publishOwnedReferences(incoming, field: .payload(field), actual: actual)
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
        storage.publishOwnedReferences(incoming, field: .structural, actual: actual)
        storage.ownedStructuralPermissions = incoming
        for permission in incoming { permission.structuralFacets[key] = actual }
        for permission in previous where !incoming.contains(where: { $0 === permission }) {
            removeStructuralReference(permission, storage: storage, key: key)
            retireIfUnreferenced(permission, preservingCold: false)
        }
    }

    private func retireIfUnreferenced(_ permission: RetainedOwnedSlotPermission, preservingCold: Bool) {
        if preservingCold, case .lazy = permission.lifetime { return }
        guard permission.ownedReferenceIndex?.hasCurrentReference != true,
            permission.ownedReferenceIndex?.hasPendingRetirement != true
        else { return }
        guard !awaitsDeclaredMarkerReplacement(ObjectIdentifier(permission)) else { return }
        retire(permission)
    }

    private func removeStructuralReference(
        _ permission: RetainedOwnedSlotPermission,
        storage _: RetainedLazyListNodeActivityStorage, key: RetainedOwnedPhysicalFacetKey
    ) {
        guard permission.ownedReferenceIndex?.contains(key) != true else { return }
        permission.structuralFacets.removeValue(forKey: key)
    }

    private func removeComponentStructuralReference(
        _ presence: RetainedOwnedComponentPresence, storage _: RetainedLazyListNodeActivityStorage,
        key: RetainedOwnedPhysicalFacetKey
    ) {
        guard presence.ownedReferenceIndex?.contains(key) != true else { return }
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
        storage.publishOwnedReferences(components: next, field: .payload(field), actual: actual)
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
        storage.publishOwnedReferences(components: incoming, field: .structural, actual: actual)
        storage.ownedStructuralComponents = incoming
        for presence in incoming { presence.structuralFacets[key] = actual }
        for presence in previous where !incoming.contains(where: { $0 === presence }) {
            removeComponentStructuralReference(presence, storage: storage, key: key)
            retireIfUnreferenced(presence, preservingCold: false)
        }
    }

    private func retireIfUnreferenced(_ presence: RetainedOwnedComponentPresence, preservingCold: Bool) {
        if preservingCold, case .lazy = presence.lifetime { return }
        guard presence.ownedReferenceIndex?.hasCurrentReference != true,
            presence.ownedReferenceIndex?.hasPendingRetirement != true
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
        let originalRetirements = declaredMarkerRetirements
        finishPendingDeclaredMarkerRetirements()
        wasFinished = true
        propertyPublications.removeAll()
        insertions.removeAll()
        structuralPublications.removeAll()
        insertedRegionPublications.removeAll()
        completedRegionPublications.removeAll()
        for (member, ticket) in originalRetirements
        where ticket.wasConsumed && declaredMarkerRetirements[member] === ticket {
            declaredMarkerRetirements.removeValue(forKey: member)
        }
        registrations.removeAll()
        sources.removeAll()
        componentParents.removeAll()
        regionSources.removeAll()
        deferredRegionBuilds.removeAll()
        planRegistrations.removeAll()
        candidateAcceptedFacts.removeAll()
        candidateDeferredFacts.removeAll()
        candidateAcceptedSegments.removeAll()
        candidateChildCatalogSources.removeAll()
        candidateChildCatalogOriginalTargets.removeAll()
        candidateChildCatalogPublications.removeAll()
        candidateChildCatalogSuccessors.removeAll()
        candidateSelfSources.removeAll()
        candidateSelfRegistrations.removeAll()
        candidateSelfPublications.removeAll()
        candidateSelfBodyAcceptances.removeAll()
        candidatePreparedWrites.removeAll()
        candidateDepartureCustody.removeAll()
        candidateAcceptedCustody.removeAll()
        candidateReferenceSuccessors.removeAll()
        candidateFieldSuccessors.removeAll()
        candidateBoundaryActivationAttempts.removeAll()
        candidatePublications.removeAll()
        candidateBoundaries.removeAll()
        candidateSegments.removeAll()
        candidateQualifications.removeAll()
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
        continuing: RetainedOwnedComponentReceipt? = nil, declarationOnly: Bool = false,
        candidateConstruction: RetainedOwnedCandidateConstruction? = nil
    ) -> RetainedOwnedComponentReceipt? {
        registerOwnedComponent(
            owner: owner, slots: slots, continuing: continuing.map { [$0] } ?? [], declarationOnly: declarationOnly,
            candidateConstruction: candidateConstruction)
    }

    package func registerOwnedComponent(
        owner: RetainedOwnedComponentID, slots: [RetainedOwnedSlotGenerationID],
        continuing: [RetainedOwnedComponentReceipt], declarationOnly: Bool = false,
        candidateConstruction: RetainedOwnedCandidateConstruction? = nil
    ) -> RetainedOwnedComponentReceipt? {
        descriptorScope?.ownedLedger.register(
            owner: owner, slots: slots, continuing: continuing, attribution: self, declarationOnly: declarationOnly,
            candidateConstruction: candidateConstruction)
    }

    package func beginOwnedCandidateConstruction(
        owner: RetainedOwnedComponentReceipt
    ) -> RetainedOwnedCandidateConstruction? {
        descriptorScope?.ownedLedger.beginOwnedCandidateConstruction(owner: owner, attribution: self)
    }

    package func ownedCandidateContinuation() -> RetainedOwnedCandidateContinuation {
        guard canConstruct, let scope = descriptorScope else { return .rejected }
        return scope.ownedLedger.ownedCandidateContinuation(attribution: self)
    }
}

// These records implement an explicit preserving container. They never enter
// physical facet maps, lazy row regions, task admission, or action admission.
@MainActor
package enum RetainedOwnedCandidateContinuation {
    case unscoped
    case admitted(RetainedOwnedCandidateConstruction)
    case rejected
}

@MainActor
package final class RetainedOwnedCandidateConstruction {
    fileprivate weak var ledger: RetainedOwnedComponentConstructionLedger?
    fileprivate weak var attribution: RetainedDescriptorComponentAttribution?
    fileprivate let qualification: RetainedOwnedCandidateScopeQualification
    fileprivate let owner: RetainedOwnedComponentReceipt
    fileprivate let segmentOwner: RetainedOwnedComponentReceipt
    fileprivate let parent: RetainedOwnedCandidateConstruction?
    fileprivate let isDeferredSegment: Bool
    fileprivate weak var boundarySource: ViewNode?
    fileprivate weak var deferredSource: ViewNode?
    fileprivate var segmentConstruction: RetainedOwnedCandidateSegmentConstruction?
    fileprivate var selfConstruction: RetainedOwnedCandidateSelfConstruction?

    fileprivate init(
        ledger: RetainedOwnedComponentConstructionLedger, attribution: RetainedDescriptorComponentAttribution,
        qualification: RetainedOwnedCandidateScopeQualification, owner: RetainedOwnedComponentReceipt,
        segmentOwner: RetainedOwnedComponentReceipt, parent: RetainedOwnedCandidateConstruction?,
        isDeferredSegment: Bool
    ) {
        self.ledger = ledger
        self.attribution = attribution
        self.qualification = qualification
        self.owner = owner
        self.segmentOwner = segmentOwner
        self.parent = parent
        self.isDeferredSegment = isDeferredSegment
    }

    package var canConstruct: Bool {
        guard let ledger, let attribution, attribution.canConstruct,
            attribution.descriptorScope?.ownedLedger === ledger, qualification.canConstruct,
            owner.nativeLifetime.permitsConstruction, !owner.owner.wasRevoked,
            segmentOwner.nativeLifetime.permitsConstruction, !segmentOwner.owner.wasRevoked
        else { return false }
        return ledger.ownsCandidateConstruction(self)
            && qualification.fields[ObjectIdentifier(owner.owner)]?.isCurrent != false
            && parent?.canConstruct != false
    }

    package func stageBoundary(on node: ViewNode) -> Bool {
        guard canConstruct, !isDeferredSegment, node.selectedContentRole == .viewThatFits,
            !node.containsRejectedRetainedSource, boundarySource == nil,
            node.retainedLazyListActivityStorage?.ownedCandidateBoundarySource == nil
        else { return false }
        boundarySource = node
        node.lazyListActivityStorage().ownedCandidateBoundarySource = self
        return true
    }

    package func deferredSegment(
        owner: RetainedOwnedComponentReceipt, attribution: RetainedDescriptorComponentAttribution
    ) -> RetainedOwnedCandidateConstruction? {
        guard canConstruct else { return nil }
        return ledger?.beginOwnedCandidateSegment(owner: owner, attribution: attribution, parent: self)
    }

    package func stageDeferredAnchor(on node: ViewNode) -> Bool {
        guard canConstruct, isDeferredSegment, node.geometryReaderBuild != nil,
            !node.containsRejectedRetainedSource, deferredSource == nil,
            node.retainedLazyListActivityStorage?.ownedCandidateDeferredSource == nil
        else { return false }
        deferredSource = node
        node.lazyListActivityStorage().ownedCandidateDeferredSource = self
        return true
    }

    fileprivate var segmentKey: RetainedOwnedCandidateSegmentKey {
        RetainedOwnedCandidateSegmentKey(namespace: owner.owner, segment: segmentOwner.owner)
    }

    fileprivate func belongs(to namespace: RetainedOwnedComponentID) -> Bool {
        var current: RetainedOwnedCandidateConstruction? = self
        var seen: Set<ObjectIdentifier> = []
        while let value = current, seen.count < ViewNode.maximumTraversalDepth {
            guard seen.insert(ObjectIdentifier(value)).inserted else { return false }
            if value.owner.owner === namespace { return true }
            current = value.parent
        }
        return false
    }
}

fileprivate struct RetainedOwnedCandidateSegmentKey: Hashable {
    let namespace: ObjectIdentifier
    let segment: ObjectIdentifier

    init(namespace: RetainedOwnedComponentID, segment: RetainedOwnedComponentID) {
        self.namespace = ObjectIdentifier(namespace)
        self.segment = ObjectIdentifier(segment)
    }
}

/// Arithmetic only: this helper neither reads nor mutates a native field.
enum RetainedOwnedCandidateRevisionCapacity {
    static func permits(current: UInt64, additional: UInt64) -> Bool {
        !current.addingReportingOverflow(additional).overflow
    }
}

fileprivate struct RetainedOwnedCandidateReferenceKey: Hashable {
    let holder: RetainedOwnedCandidateSegmentKey
    let member: ObjectIdentifier
}

@MainActor
fileprivate struct RetainedOwnedCandidateReferenceIntent {
    let member: RetainedOwnedPhysicalReferenceMember
    let holder: RetainedOwnedCandidateSegmentKey
    let destination: RetainedOwnedCandidateSegmentKey
    let original: RetainedOwnedCandidateReference?
    let lineage: [RetainedOwnedCandidateDeclarationEdge]
    let returnPath: [RetainedOwnedCandidateSegmentKey]

    init(
        member: RetainedOwnedPhysicalReferenceMember, holder: RetainedOwnedCandidateSegmentKey,
        destination: RetainedOwnedCandidateSegmentKey, original: RetainedOwnedCandidateReference? = nil,
        lineage: [RetainedOwnedCandidateDeclarationEdge] = [], returnPath: [RetainedOwnedCandidateSegmentKey]? = nil
    ) {
        self.member = member
        self.holder = holder
        self.destination = destination
        self.original = original
        self.lineage = lineage
        self.returnPath = returnPath ?? [holder]
    }

    var key: RetainedOwnedCandidateReferenceKey { .init(holder: holder, member: member.identity) }
}

@MainActor
fileprivate struct RetainedOwnedCandidateReferenceBatch {
    let field: RetainedOwnedCandidateField
    let entries: [RetainedOwnedCandidateReferenceKey: RetainedOwnedCandidateReferenceIntent]
    let existing: [RetainedOwnedCandidateReferenceKey: RetainedOwnedCandidateReference]
}

@MainActor
fileprivate struct RetainedOwnedCandidateReferenceBatchResult {
    let replacements: [(original: RetainedOwnedCandidateReference, accepted: RetainedOwnedCandidateReference)]
    let accepted: [RetainedOwnedCandidateReferenceKey: RetainedOwnedCandidateReference]
}

@MainActor
fileprivate final class RetainedOwnedCandidateIncarnation {}

@MainActor
fileprivate final class RetainedOwnedWeakCandidateReference {
    weak var reference: RetainedOwnedCandidateReference?
    init(_ reference: RetainedOwnedCandidateReference) { self.reference = reference }
}

/// Membership lineage is not a mutation permit. Only a completed native batch
/// may continue this exact edge; an earlier operation uses its own recorded
/// reference-successor receipt rather than reading currentReference to renew.
@MainActor
fileprivate final class RetainedOwnedCandidateDeclarationEdge {
    let declaringSegment: RetainedOwnedCandidateSegmentKey
    weak var currentReference: RetainedOwnedCandidateReference?
    var dependents: [ObjectIdentifier: RetainedOwnedWeakCandidateReference] = [:]
    var isClosed = false
    weak var acceptedReader: RetainedOwnedCandidateAcceptedReader?

    init(declaringSegment: RetainedOwnedCandidateSegmentKey) { self.declaringSegment = declaringSegment }
}

@MainActor
fileprivate final class RetainedOwnedCandidateReference {
    let member: RetainedOwnedPhysicalReferenceMember
    let holderSegment: RetainedOwnedCandidateSegmentKey
    let destination: RetainedOwnedCandidateSegmentKey
    let declarationEdge: RetainedOwnedCandidateDeclarationEdge
    let lineage: [RetainedOwnedCandidateDeclarationEdge]
    let returnPath: [RetainedOwnedCandidateSegmentKey]
    let fieldIncarnation: RetainedOwnedCandidateIncarnation
    weak var field: RetainedOwnedCandidateField?
    var wasWithdrawn = false

    init(
        member: RetainedOwnedPhysicalReferenceMember, destination: RetainedOwnedCandidateSegmentKey,
        holderSegment: RetainedOwnedCandidateSegmentKey, field: RetainedOwnedCandidateField,
        original: RetainedOwnedCandidateReference?, lineage: [RetainedOwnedCandidateDeclarationEdge],
        returnPath: [RetainedOwnedCandidateSegmentKey]
    ) {
        self.member = member
        self.holderSegment = holderSegment
        self.destination = destination
        self.field = field
        fieldIncarnation = field.incarnation
        declarationEdge =
            original?.declarationEdge ?? RetainedOwnedCandidateDeclarationEdge(declaringSegment: holderSegment)
        self.lineage = lineage
        self.returnPath = returnPath
    }

    private var isStoredCurrent: Bool {
        !wasWithdrawn && !declarationEdge.isClosed && declarationEdge.currentReference === self
            && member.isCurrentCandidateMember && field?.incarnation === fieldIncarnation
            && field?.contains(self) == true
    }

    var isCurrent: Bool { hasCurrentLineage(excluding: nil) }

    func hasCurrentLineage(excluding forbidden: RetainedOwnedCandidateDeclarationEdge?) -> Bool {
        var pending: [(reference: RetainedOwnedCandidateReference, leaving: Bool)] = [(self, false)]
        var active: Set<ObjectIdentifier> = []
        var complete: Set<ObjectIdentifier> = []
        while let step = pending.popLast() {
            let identity = ObjectIdentifier(step.reference)
            if step.leaving {
                active.remove(identity)
                complete.insert(identity)
                continue
            }
            if complete.contains(identity) { continue }
            guard complete.count + active.count < ViewNode.maximumTraversalDepth,
                step.reference.isStoredCurrent, step.reference.declarationEdge !== forbidden,
                active.insert(identity).inserted
            else { return false }
            pending.append((step.reference, true))
            for edge in step.reference.lineage {
                guard !edge.isClosed, edge !== forbidden, let current = edge.currentReference,
                    !active.contains(ObjectIdentifier(current))
                else { return false }
                pending.append((current, false))
            }
        }
        return true
    }
}

/// Pins the entire original dependency wave. Every table, index, edge and
/// revision is withdrawn before the caller may retire any member. A continued
/// edge belongs to its accepted replacement, never to the departing donor.
@MainActor
fileprivate struct RetainedOwnedCandidateWithdrawal {
    let references: [RetainedOwnedCandidateReference]
    let fields: [RetainedOwnedCandidateField]

    init(_ originals: [RetainedOwnedCandidateReference]) {
        var pending = originals
        var captured: [RetainedOwnedCandidateReference] = []
        var capturedFields: [ObjectIdentifier: RetainedOwnedCandidateField] = [:]
        var seen: Set<ObjectIdentifier> = []
        while let reference = pending.popLast() {
            guard !reference.wasWithdrawn, seen.insert(ObjectIdentifier(reference)).inserted else { continue }
            captured.append(reference)
            if let field = reference.field { capturedFields[ObjectIdentifier(field)] = field }
            if reference.declarationEdge.currentReference === reference {
                for dependent in reference.declarationEdge.dependents.values {
                    if let exact = dependent.reference,
                        exact.lineage.contains(where: { $0 === reference.declarationEdge })
                    {
                        pending.append(exact)
                    }
                }
            }
        }
        references = captured
        fields = Array(capturedFields.values)
    }

    func withdraw() {
        var changed: [ObjectIdentifier: RetainedOwnedCandidateSegment] = [:]
        for reference in references where !reference.wasWithdrawn {
            reference.wasWithdrawn = true
            reference.member.index.candidateReferences.removeValue(forKey: ObjectIdentifier(reference))
            for edge in reference.lineage { edge.dependents.removeValue(forKey: ObjectIdentifier(reference)) }
            if let field = reference.field, field.incarnation === reference.fieldIncarnation,
                let segment = field.segments[reference.holderSegment],
                segment.references[reference.member.identity] === reference
            {
                segment.references.removeValue(forKey: reference.member.identity)
                changed[ObjectIdentifier(segment)] = segment
            }
            if reference.declarationEdge.currentReference === reference {
                reference.declarationEdge.acceptedReader?.removeOriginalDeclaration(reference)
                reference.declarationEdge.isClosed = true
                reference.declarationEdge.currentReference = nil
                reference.declarationEdge.dependents.removeAll()
            }
        }
        for segment in changed.values {
            // Exhaustion denies every later addition. Mandatory removal still
            // removes exact entries; a prior snapshot cannot survive that loss.
            if segment.revision < .max { segment.revision += 1 }
        }
    }

    func retireUnreferencedMembers() {
        for reference in references { reference.member.retireAfterRawWithdrawalIfUnreferenced() }
    }
}

extension RetainedOwnedPhysicalReferenceMember {
    fileprivate var candidateOwner: RetainedOwnedComponentID {
        switch self {
        case .slot(let permission): return permission.owner
        case .component(let presence): return presence.owner
        }
    }

    fileprivate var isCurrentCandidateMember: Bool {
        switch self {
        case .slot(let permission):
            return permission.isDeclared && !permission.wasRevoked && !permission.owner.wasRevoked
                && permission.lifetime.permitsDeclaredWrite
        case .component(let presence):
            return presence.owner.nativePresence === presence && presence.hasDeclaredComponent
        }
    }
}

@MainActor
fileprivate final class RetainedOwnedCandidateSegment {
    let key: RetainedOwnedCandidateSegmentKey
    var revision: UInt64 = 0
    var references: [ObjectIdentifier: RetainedOwnedCandidateReference] = [:]
    var acceptedReader: RetainedOwnedCandidateAcceptedReader?
    init(key: RetainedOwnedCandidateSegmentKey) { self.key = key }
}

/// Accepted field identity survives a proof-only attachment rotation. Its
/// currentness is deliberately nonrecursive: no reference index is consulted.
@MainActor
fileprivate final class RetainedOwnedCandidateField {
    let incarnation = RetainedOwnedCandidateIncarnation()
    let owner: RetainedOwnedComponentPresence
    weak var node: ViewNode?
    weak var storage: RetainedLazyListNodeActivityStorage?
    weak var runtime: RetainedViewRuntime?
    var catalogRevision: UInt64 = 0
    var segments: [RetainedOwnedCandidateSegmentKey: RetainedOwnedCandidateSegment] = [:]
    var readerRoots: [ObjectIdentifier: RetainedOwnedWeakCandidateReader] = [:]
    weak var departureCustody: RetainedOwnedCandidateDepartureCustody?
    private(set) var wasWithdrawn = false

    init(owner: RetainedOwnedComponentPresence, actual: RetainedLazyListActualAttachment) {
        self.owner = owner
        node = actual.node
        storage = actual.node?.retainedLazyListActivityStorage
        runtime = actual.runtime
    }

    var isCurrent: Bool {
        guard !wasWithdrawn, owner.owner.nativePresence === owner, owner.hasDeclaredComponent,
            owner.ownedCandidateField === self, let node, let storage, let runtime,
            node.retainedLazyListActivityStorage === storage, storage.ownedCandidateField === self,
            node.retainedLazyListRuntime === runtime
        else { return false }
        return node.isRetainedLazyListAttached(in: runtime)
    }

    func contains(_ reference: RetainedOwnedCandidateReference) -> Bool {
        isCurrent && segments[reference.holderSegment]?.references[reference.member.identity] === reference
    }

    func takeOriginalReferencesForWithdrawal() -> [RetainedOwnedCandidateReference] {
        guard !wasWithdrawn else { return [] }
        wasWithdrawn = true
        departureCustody = nil
        let original = segments.values.flatMap { Array($0.references.values) }
        segments.removeAll()
        readerRoots.removeAll()
        if storage?.ownedCandidateField === self { storage?.ownedCandidateField = nil }
        if owner.ownedCandidateField === self { owner.ownedCandidateField = nil }
        return original
    }

    func withdraw() {
        let withdrawal = RetainedOwnedCandidateWithdrawal(takeOriginalReferencesForWithdrawal())
        withdrawal.withdraw()
        withdrawal.retireUnreferencedMembers()
    }
}

@MainActor
fileprivate final class RetainedOwnedCandidateSegmentSnapshot {
    let segment: RetainedOwnedCandidateSegment
    let revision: UInt64
    let references: [ObjectIdentifier: RetainedOwnedCandidateReference]

    init(_ segment: RetainedOwnedCandidateSegment) {
        self.segment = segment
        revision = segment.revision
        references = segment.references
    }

    var isCurrent: Bool {
        segment.revision == revision && segment.references.count == references.count
            && references.allSatisfy { segment.references[$0.key] === $0.value && !$0.value.wasWithdrawn }
    }
}

/// Construction provenance only. The parent and normal reader registration are
/// fixed before the child reader evaluates authored content.
@MainActor
fileprivate final class RetainedOwnedCandidateSegmentConstruction {
    let parent: RetainedOwnedCandidateConstruction
    let registration: RetainedOwnedComponentRegistration
    weak var token: RetainedOwnedCandidateConstruction?

    init(
        parent: RetainedOwnedCandidateConstruction, registration: RetainedOwnedComponentRegistration,
        token: RetainedOwnedCandidateConstruction
    ) {
        self.parent = parent
        self.registration = registration
        self.token = token
    }
}

@MainActor
fileprivate final class RetainedOwnedWeakCandidateReader {
    weak var reader: RetainedOwnedCandidateAcceptedReader?
    init(_ reader: RetainedOwnedCandidateAcceptedReader) { self.reader = reader }
}

/// A successful normal reader and its successful descriptor group establish
/// this native graph edge. Neither a slot nor a planned segment creates one.
@MainActor
fileprivate final class RetainedOwnedCandidateReaderPublication {
    let reader: RetainedOwnedComponentReceipt
    let contribution: RetainedDescriptorContributionReceipt
    let actual: RetainedLazyListActualAttachment

    init(
        reader: RetainedOwnedComponentReceipt, contribution: RetainedDescriptorContributionReceipt,
        actual: RetainedLazyListActualAttachment
    ) {
        self.reader = reader
        self.contribution = contribution
        self.actual = actual
    }
}

@MainActor
fileprivate final class RetainedOwnedCandidateAcceptedReader {
    weak var field: RetainedOwnedCandidateField?
    let incarnation: RetainedOwnedCandidateIncarnation
    weak var segment: RetainedOwnedCandidateSegment?
    let normalReference: RetainedOwnedCandidateReference
    weak var parent: RetainedOwnedCandidateAcceptedReader?
    let isRoot: Bool
    var publication: RetainedOwnedCandidateReaderPublication
    var children: [ObjectIdentifier: RetainedOwnedWeakCandidateReader] = [:]
    private(set) var wasRemoved = false

    init(
        field: RetainedOwnedCandidateField, segment: RetainedOwnedCandidateSegment,
        normalReference: RetainedOwnedCandidateReference, parent: RetainedOwnedCandidateAcceptedReader?,
        publication: RetainedOwnedCandidateReaderPublication
    ) {
        self.field = field
        incarnation = field.incarnation
        self.segment = segment
        self.normalReference = normalReference
        self.parent = parent
        isRoot = parent == nil
        self.publication = publication
    }

    var isDeclared: Bool {
        guard !wasRemoved, let field, let segment, field.isCurrent, field.incarnation === incarnation,
            field.segments[segment.key] === segment, segment.acceptedReader === self,
            normalReference.isCurrent, normalReference.declarationEdge.acceptedReader === self
        else { return false }
        if isRoot {
            return field.readerRoots[ObjectIdentifier(self)]?.reader === self
        }
        guard let parent, parent.children[ObjectIdentifier(self)]?.reader === self,
            parent.normalReference.isCurrent,
            normalReference.lineage.contains(where: { $0 === parent.normalReference.declarationEdge })
        else { return false }
        return true
    }

    func removeOriginalDeclaration(_ reference: RetainedOwnedCandidateReference) {
        guard !wasRemoved, normalReference === reference else { return }
        wasRemoved = true
        if reference.declarationEdge.acceptedReader === self { reference.declarationEdge.acceptedReader = nil }
        if let segment, segment.acceptedReader === self { segment.acceptedReader = nil }
        if isRoot {
            if field?.readerRoots[ObjectIdentifier(self)]?.reader === self {
                field?.readerRoots.removeValue(forKey: ObjectIdentifier(self))
            }
        } else if parent?.children[ObjectIdentifier(self)]?.reader === self {
            parent?.children.removeValue(forKey: ObjectIdentifier(self))
        }
    }
}

/// Original per-reader catalog evidence, never a field mutation or construction
/// qualification. The optional actual is captured now; a cold reader cannot
/// obtain one by a later lookup of the same owner or authored identity.
@MainActor
fileprivate final class RetainedOwnedCandidateCatalogNode {
    let reader: RetainedOwnedCandidateAcceptedReader
    let publication: RetainedOwnedCandidateReaderPublication
    let field: RetainedOwnedCandidateFieldSnapshot
    let normalReference: RetainedOwnedCandidateReference
    let actual: RetainedLazyListActualAttachment?
    let dependencies: RetainedOwnedCandidateCatalogDependencies
    var children: [RetainedOwnedCandidateCatalogNode] = []

    init?(reader: RetainedOwnedCandidateAcceptedReader, fieldActual: RetainedLazyListActualAttachment) {
        guard reader.isDeclared, let owner = reader.field, let segment = reader.segment,
            owner.segments[segment.key] === segment,
            let snapshot = RetainedOwnedCandidateFieldSnapshot(
                field: owner, actual: fieldActual, selectedSegment: segment.key)
        else { return nil }
        self.reader = reader
        publication = reader.publication
        field = snapshot
        normalReference = reader.normalReference
        guard let dependencies = RetainedOwnedCandidateCatalogDependencies(snapshot.references) else { return nil }
        self.dependencies = dependencies
        let original = reader.publication.actual
        if original.isAttached, reader.publication.contribution.isActive,
            let installed = original.node?.retainedLazyListActivityStorage?.ownedCandidateDeferredAnchor,
            installed.readerRecord === reader, installed.readerPublication === reader.publication,
            installed.isCurrent
        {
            actual = original
        } else {
            actual = nil
        }
    }

    var isCurrent: Bool {
        reader.isDeclared && reader.publication === publication && reader.normalReference === normalReference
            && normalReference.isCurrent && field.isCurrent && dependencies.isCurrent
    }

    /// The caller has performed this ledger's callback-free removal. Copy its
    /// original physical/reader binding; do not capture a replacement anchor.
    init?(afterOwnWrite original: RetainedOwnedCandidateCatalogNode) {
        guard original.reader.isDeclared, original.reader.publication === original.publication,
            original.reader.normalReference === original.normalReference, original.normalReference.isCurrent,
            let segment = original.reader.segment, original.field.field.segments[segment.key] === segment,
            let snapshot = RetainedOwnedCandidateFieldSnapshot(
                field: original.field.field, actual: original.field.actual,
                selectedSegment: segment.key),
            let dependencies = RetainedOwnedCandidateCatalogDependencies(snapshot.references),
            dependencies.references.allSatisfy({ current in
                original.dependencies.references.contains(where: { $0 === current })
            })
        else { return nil }
        reader = original.reader
        publication = original.publication
        normalReference = original.normalReference
        actual = original.actual
        field = snapshot
        self.dependencies = dependencies
        children = original.children
    }
}

@MainActor
fileprivate final class RetainedOwnedCandidateCatalogDependencies {
    struct Segment {
        let field: RetainedOwnedCandidateField
        let incarnation: RetainedOwnedCandidateIncarnation
        let catalogRevision: UInt64
        let snapshot: RetainedOwnedCandidateSegmentSnapshot
    }

    struct Edge {
        let original: RetainedOwnedCandidateReference
        let dependents: [ObjectIdentifier: RetainedOwnedCandidateReference]
    }

    let references: [RetainedOwnedCandidateReference]
    let segments: [Segment]
    let edges: [Edge]

    init?(_ originals: [RetainedOwnedCandidateReference]) {
        references = RetainedOwnedCandidateWithdrawal(originals).references
        var segments: [Segment] = []
        var edges: [Edge] = []
        var seen: Set<ObjectIdentifier> = []
        for reference in references {
            guard reference.isCurrent, let field = reference.field,
                let segment = field.segments[reference.holderSegment],
                segment.references[reference.member.identity] === reference
            else { return nil }
            if seen.insert(ObjectIdentifier(segment)).inserted {
                segments.append(
                    Segment(
                        field: field, incarnation: field.incarnation, catalogRevision: field.catalogRevision,
                        snapshot: RetainedOwnedCandidateSegmentSnapshot(segment)))
            }
            var dependents: [ObjectIdentifier: RetainedOwnedCandidateReference] = [:]
            for (id, weakDependent) in reference.declarationEdge.dependents {
                guard let dependent = weakDependent.reference else { continue }
                guard dependent.lineage.contains(where: { $0 === reference.declarationEdge }) else { return nil }
                dependents[id] = dependent
            }
            edges.append(Edge(original: reference, dependents: dependents))
        }
        self.segments = segments
        self.edges = edges
    }

    var isCurrent: Bool {
        guard references.allSatisfy(\.isCurrent),
            segments.allSatisfy({ item in
                item.field.isCurrent && item.field.incarnation === item.incarnation
                    && item.field.catalogRevision == item.catalogRevision
                    && item.field.segments[item.snapshot.segment.key] === item.snapshot.segment
                    && item.snapshot.isCurrent
            })
        else { return false }
        for edge in edges {
            guard edge.original.declarationEdge.currentReference === edge.original,
                !edge.original.declarationEdge.isClosed
            else { return false }
            let current = edge.original.declarationEdge.dependents.compactMapValues(\.reference)
            guard current.count == edge.dependents.count,
                edge.dependents.allSatisfy({ current[$0.key] === $0.value })
            else { return false }
        }
        return true
    }
}

@MainActor
fileprivate final class RetainedOwnedCandidateCatalogGraph {
    let field: RetainedOwnedCandidateField
    let nodes: [RetainedOwnedCandidateCatalogNode]

    init?(
        original: RetainedOwnedCandidateFieldSnapshot, root: RetainedOwnedCandidateAcceptedReader? = nil
    ) {
        guard original.isCurrent else { return nil }
        field = original.field
        let roots: [RetainedOwnedCandidateAcceptedReader]
        if let root {
            guard root.field === field, root.isDeclared else { return nil }
            roots = [root]
        } else {
            roots = field.readerRoots.values.compactMap(\.reader)
        }
        var pending = roots.map { (reader: $0, parent: Optional<RetainedOwnedCandidateCatalogNode>.none, depth: 0) }
        var captured: [RetainedOwnedCandidateCatalogNode] = []
        var seen: Set<ObjectIdentifier> = []
        while let step = pending.popLast() {
            guard step.depth < ViewNode.maximumTraversalDepth,
                seen.insert(ObjectIdentifier(step.reader)).inserted,
                let node = RetainedOwnedCandidateCatalogNode(reader: step.reader, fieldActual: original.actual)
            else { return nil }
            step.parent?.children.append(node)
            captured.append(node)
            for weakChild in step.reader.children.values {
                guard let child = weakChild.reader else { continue }
                guard child.parent === step.reader, child.field === field,
                    child.normalReference.lineage.contains(where: { $0 === step.reader.normalReference.declarationEdge }
                    )
                else { return nil }
                pending.append((child, node, step.depth + 1))
            }
        }
        nodes = captured
    }
}

@MainActor
fileprivate final class RetainedOwnedCandidateChildSource {
    enum Origin {
        case fresh
        case existing(RetainedOwnedCandidateCatalogNode)
        case refused
    }

    let construction: RetainedOwnedCandidateSegmentConstruction
    weak var source: ViewNode?
    let sourceAttachment: RetainedLazyListAttachmentProof
    let sourceIdentity: RetainedLazyListViewIdentityProof
    let normalPlan: RetainedOwnedComponentDeclarationPlan
    let expectedGroup: RetainedDescriptorContributionReceipt
    let plans: [RetainedOwnedComponentDeclarationPlan]
    let origin: Origin
    var wasConsumed = false
    var wasRefused = false

    init(
        construction: RetainedOwnedCandidateSegmentConstruction, source: ViewNode,
        normalPlan: RetainedOwnedComponentDeclarationPlan, expectedGroup: RetainedDescriptorContributionReceipt,
        plans: [RetainedOwnedComponentDeclarationPlan], origin: Origin
    ) {
        self.construction = construction
        self.source = source
        sourceAttachment = source.captureLazyListAttachmentProof()
        sourceIdentity = source.captureLazyListIdentityProof()
        self.normalPlan = normalPlan
        self.expectedGroup = expectedGroup
        self.plans = plans
        self.origin = origin
    }

    var sourceBindingsAreCurrent: Bool {
        guard !wasRefused, let source, let token = construction.token,
            token.segmentConstruction === construction, token.deferredSource === source,
            source.retainedLazyListActivityStorage?.ownedCandidateDeferredSource === token,
            !source.containsRejectedRetainedSource, sourceIdentity.isCurrent,
            construction.registration.receipt === normalPlan.receipt,
            !normalPlan.receipt.owner.wasRevoked, normalPlan.receipt.nativeLifetime.permitsDeclaredWrite
        else { return false }
        return normalPlan.receipt.slotPermissions.allSatisfy { !$0.wasRevoked }
    }

    var sourceIsCurrent: Bool {
        sourceBindingsAreCurrent && sourceAttachment.isCurrent && construction.token?.qualification.canPublish == true
    }
}

/// A child afterimage is catalog history only. No general publication or
/// continuation accepts this type, even when the write kept every member.
@MainActor
fileprivate final class RetainedOwnedCandidateChildPublication {
    let source: RetainedOwnedCandidateChildSource
    let original: RetainedOwnedCandidateCatalogNode
    let afterimage: RetainedOwnedCandidateCatalogNode
    let affected: [RetainedOwnedCandidateCatalogNode]
    let wasWrite: Bool

    init(
        source: RetainedOwnedCandidateChildSource, original: RetainedOwnedCandidateCatalogNode,
        afterimage: RetainedOwnedCandidateCatalogNode, affected: [RetainedOwnedCandidateCatalogNode], wasWrite: Bool
    ) {
        self.source = source
        self.original = original
        self.afterimage = afterimage
        self.affected = affected
        self.wasWrite = wasWrite
    }
}

@MainActor
fileprivate final class RetainedOwnedCandidateChildSuccessor {
    let original: RetainedOwnedCandidateCatalogNode
    let publication: RetainedOwnedCandidateChildPublication
    let afterimage: RetainedOwnedCandidateCatalogNode?
    let wasOmitted: Bool

    init(
        original: RetainedOwnedCandidateCatalogNode, publication: RetainedOwnedCandidateChildPublication,
        afterimage: RetainedOwnedCandidateCatalogNode?, wasOmitted: Bool
    ) {
        self.original = original
        self.publication = publication
        self.afterimage = afterimage
        self.wasOmitted = wasOmitted
    }
}

/// Unlike a catalog receipt, this joins two successful native writers. It is
/// scoped to this original construction and can only publish its actual facts.
@MainActor
fileprivate final class RetainedOwnedCandidateSegmentAcceptance {
    let construction: RetainedOwnedCandidateSegmentConstruction
    let normal: RetainedOwnedCandidateAcceptedFact
    let descriptor: RetainedOwnedCandidateDeferredFact
    let reader: RetainedOwnedCandidateAcceptedReader
    let publication: RetainedOwnedCandidateReaderPublication
    var field: RetainedOwnedCandidateFieldSnapshot
    var anchor: RetainedOwnedCandidateDeferredAnchor
    let selfParent: RetainedOwnedCandidateSelfBodyAcceptance?
    var selfWasRefused = false

    init(
        construction: RetainedOwnedCandidateSegmentConstruction, normal: RetainedOwnedCandidateAcceptedFact,
        descriptor: RetainedOwnedCandidateDeferredFact, reader: RetainedOwnedCandidateAcceptedReader,
        publication: RetainedOwnedCandidateReaderPublication, field: RetainedOwnedCandidateFieldSnapshot,
        anchor: RetainedOwnedCandidateDeferredAnchor, selfParent: RetainedOwnedCandidateSelfBodyAcceptance? = nil
    ) {
        self.construction = construction
        self.normal = normal
        self.descriptor = descriptor
        self.reader = reader
        self.publication = publication
        self.field = field
        self.anchor = anchor
        self.selfParent = selfParent
    }

    var isCurrent: Bool {
        if let selfParent {
            return selfParent.ledger?.canPublishSelfAcceptedChild(self) == true
        }
        return construction.token?.qualification.canPublish == true && normal.actual.isAttached
            && descriptor.descriptorFactIsCurrent && reader.isDeclared && reader.publication === publication
            && field.isCurrent && anchor.isCurrent
    }
}

/// Permission for one successful normal member fact. Catalog-only child
/// observations cannot construct this proof or supply either authority arm.
@MainActor
fileprivate struct RetainedOwnedCandidateNormalMemberProof {
    let fact: RetainedOwnedCandidateAcceptedFact
    let token: RetainedOwnedCandidateConstruction
    let field: RetainedOwnedCandidateFieldSnapshot
    let publication: RetainedOwnedCandidateCatalogPublication?
    let acceptance: RetainedOwnedCandidateSegmentAcceptance?
    let selfAcceptance: RetainedOwnedCandidateSelfBodyAcceptance?
    let reader: RetainedOwnedCandidateAcceptedReader?

    var isCurrent: Bool {
        guard fact.actual.isAttached, !fact.plan.declarationOnly, field.isCurrent,
            token.owner.hasDeclaredComponent,
            fact.plan.receipt.hasDeclaredComponent,
            fact.plan.receipt.slotPermissions.allSatisfy({ $0.isDeclared && !$0.wasRevoked })
        else { return false }
        if let selfAcceptance {
            return publication == nil && acceptance == nil && selfAcceptance.field === field
                && selfAcceptance.token === token && reader === selfAcceptance.reader
                && selfAcceptance.ledger?.permitsSelfAcceptedNormal(fact, with: selfAcceptance) == true
        }
        if let acceptance {
            guard publication == nil, acceptance.isCurrent, acceptance.field === field,
                acceptance.construction.token === token, reader === acceptance.reader
            else { return false }
            if let selfParent = acceptance.selfParent {
                return selfParent.ledger?.permitsSelfAcceptedChildNormal(fact, with: acceptance) == true
            }
            return token.qualification.canPublish
        }
        guard token.qualification.canPublish, let publication, publication.afterimage === field,
            publication.write.token?.qualification === token.qualification,
            publication.write.plans.contains(where: { $0 === fact.plan })
        else { return false }
        if token.isDeferredSegment {
            guard token.segmentConstruction == nil, let continuation = token.qualification.currentContinuation,
                continuation.isCurrent, continuation.segment == token.segmentKey,
                reader === continuation.readerRecord, field.selectedSegment == token.segmentKey
            else { return false }
        } else if reader != nil {
            return false
        }
        return true
    }
}

@MainActor
fileprivate final class RetainedOwnedCandidateFieldSnapshot {
    let field: RetainedOwnedCandidateField
    let incarnation: RetainedOwnedCandidateIncarnation
    let actual: RetainedLazyListActualAttachment
    let catalogRevision: UInt64
    let segments: [RetainedOwnedCandidateSegmentKey: RetainedOwnedCandidateSegmentSnapshot]
    let selectedSegment: RetainedOwnedCandidateSegmentKey?

    init?(
        field: RetainedOwnedCandidateField, actual: RetainedLazyListActualAttachment,
        selectedSegment: RetainedOwnedCandidateSegmentKey? = nil
    ) {
        guard field.isCurrent, actual.isAttached, actual.node === field.node,
            let storage = field.storage, storage.targetID === actual.target,
            storage.attachmentID === actual.attachment
        else { return nil }
        self.field = field
        incarnation = field.incarnation
        self.actual = actual
        catalogRevision = field.catalogRevision
        self.selectedSegment = selectedSegment
        var result: [RetainedOwnedCandidateSegmentKey: RetainedOwnedCandidateSegmentSnapshot] = [:]
        for (key, segment) in field.segments where selectedSegment == nil || selectedSegment == key {
            result[key] = RetainedOwnedCandidateSegmentSnapshot(segment)
        }
        segments = result
    }

    var isCurrent: Bool {
        guard field.isCurrent, field.incarnation === incarnation, actual.isAttached,
            field.catalogRevision == catalogRevision
        else { return false }
        if let selectedSegment {
            guard (field.segments[selectedSegment] == nil) == (segments[selectedSegment] == nil) else { return false }
        } else if field.segments.count != segments.count {
            return false
        }
        return segments.allSatisfy { field.segments[$0.key] === $0.value.segment && $0.value.isCurrent }
    }

    var references: [RetainedOwnedCandidateReference] {
        segments.values.flatMap { Array($0.references.values) }
    }
}

/// Original operation qualification is separate from membership. It is captured
/// once before construction and cannot be recreated by an earlier attempt.
@MainActor
fileprivate final class RetainedOwnedCandidateScopeQualification {
    weak var scope: RetainedLazyListDescriptorBuildScope?
    let actual: RetainedLazyListActualAttachment
    let contribution: RetainedDescriptorContributionReceipt?
    let continuation: RetainedOwnedCandidateDeferredAnchor?
    var continuationAfterimage: RetainedOwnedCandidateDeferredAnchor?
    let fields: [ObjectIdentifier: RetainedOwnedCandidateFieldSnapshot]
    let childCatalogGraphs: [RetainedOwnedCandidateCatalogGraph]

    init(
        scope: RetainedLazyListDescriptorBuildScope, actual: RetainedLazyListActualAttachment,
        contribution: RetainedDescriptorContributionReceipt?, continuation: RetainedOwnedCandidateDeferredAnchor?,
        fields: [ObjectIdentifier: RetainedOwnedCandidateFieldSnapshot],
        childCatalogGraphs: [RetainedOwnedCandidateCatalogGraph]
    ) {
        self.scope = scope
        self.actual = actual
        self.contribution = contribution
        self.continuation = continuation
        self.fields = fields
        self.childCatalogGraphs = childCatalogGraphs
    }

    var canConstruct: Bool {
        guard scope?.canConstructDescriptors == true, actual.isAttached,
            contribution?.isActive != false, continuation?.isCurrent != false
        else { return false }
        return true
    }

    var canPublish: Bool {
        scope?.canPublishDescriptors == true && actual.isAttached
            && contribution?.isActive != false && currentContinuation?.isCurrent != false
    }

    var currentContinuation: RetainedOwnedCandidateDeferredAnchor? { continuationAfterimage ?? continuation }
}

fileprivate enum RetainedOwnedCandidateDirectOriginal {
    case absent
    case unique(RetainedOwnedCandidateScopeQualification)
    case ambiguous
}

@MainActor
fileprivate final class RetainedOwnedCandidateSelfConstruction {
    weak var token: RetainedOwnedCandidateConstruction?
    weak var registration: RetainedOwnedComponentRegistration?
    let original: RetainedOwnedCandidateDeferredAnchor

    init(
        token: RetainedOwnedCandidateConstruction, registration: RetainedOwnedComponentRegistration,
        original: RetainedOwnedCandidateDeferredAnchor
    ) {
        self.token = token
        self.registration = registration
        self.original = original
    }
}

@MainActor
fileprivate final class RetainedOwnedCandidateSelfSource {
    let construction: RetainedOwnedCandidateSelfConstruction
    weak var source: ViewNode?
    let sourceAttachment: RetainedLazyListAttachmentProof
    let sourceIdentity: RetainedLazyListViewIdentityProof
    let plan: RetainedOwnedComponentDeclarationPlan
    let expectedGroup: RetainedDescriptorContributionReceipt

    init(
        construction: RetainedOwnedCandidateSelfConstruction, source: ViewNode,
        plan: RetainedOwnedComponentDeclarationPlan, expectedGroup: RetainedDescriptorContributionReceipt
    ) {
        self.construction = construction
        self.source = source
        sourceAttachment = source.captureLazyListAttachmentProof()
        sourceIdentity = source.captureLazyListIdentityProof()
        self.plan = plan
        self.expectedGroup = expectedGroup
    }
}

/// This attempt is bound while its original contribution is still active. The
/// exact first own absence may discharge only that contribution's activity test.
@MainActor
fileprivate final class RetainedOwnedCandidateSelfPublication {
    weak var ledger: RetainedOwnedComponentConstructionLedger?
    let input: RetainedOwnedCandidateSelfSource
    let originalAnchor: RetainedOwnedCandidateDeferredAnchor
    let originalField: RetainedOwnedCandidateFieldSnapshot
    var ownAbsence: RetainedDescriptorAcceptedAbsence?
    var didDrainOwnAbsence = false
    var normal: RetainedOwnedCandidateAcceptedFact?
    var descriptor: RetainedOwnedCandidateDeferredFact?
    var didFinish = false
    var wasRefused = false

    init(
        ledger: RetainedOwnedComponentConstructionLedger, input: RetainedOwnedCandidateSelfSource,
        originalAnchor: RetainedOwnedCandidateDeferredAnchor, originalField: RetainedOwnedCandidateFieldSnapshot
    ) {
        self.ledger = ledger
        self.input = input
        self.originalAnchor = originalAnchor
        self.originalField = originalField
    }

    func recordFirstOwnAbsence(_ absence: RetainedDescriptorAcceptedAbsence) {
        guard !didFinish, !wasRefused, ownAbsence == nil, !absence.removalFacets.isEmpty,
            absence.previous === input.construction.original.contribution, absence.previous.isActive,
            absence.actual.node === originalAnchor.actual.node,
            absence.actual.target === originalAnchor.actual.target,
            absence.actual.attachment === originalAnchor.actual.attachment,
            ledger?.canFinishCandidateSelf(self, requireActiveOriginal: true) == true
        else { return }
        ownAbsence = absence
    }

    func recordDrainedOwnAbsence(_ absence: RetainedDescriptorAcceptedAbsence) {
        guard let original = ownAbsence, original.cleanup === absence.cleanup,
            original.previous === absence.previous, original.actual === absence.actual
        else { return }
        didDrainOwnAbsence = true
    }
}

/// Actual SELF completion permits only the original successful body facts. It
/// never changes the original construction qualification or general receipts.
@MainActor
fileprivate final class RetainedOwnedCandidateSelfBodyAcceptance {
    weak var ledger: RetainedOwnedComponentConstructionLedger?
    let publication: RetainedOwnedCandidateSelfPublication
    let token: RetainedOwnedCandidateConstruction
    let normal: RetainedOwnedCandidateAcceptedFact
    let descriptor: RetainedOwnedCandidateDeferredFact
    let reader: RetainedOwnedCandidateAcceptedReader
    let normalReference: RetainedOwnedCandidateReference
    let readerPublication: RetainedOwnedCandidateReaderPublication
    var field: RetainedOwnedCandidateFieldSnapshot
    var anchor: RetainedOwnedCandidateDeferredAnchor
    var wasRefused = false

    init(
        ledger: RetainedOwnedComponentConstructionLedger, publication: RetainedOwnedCandidateSelfPublication,
        token: RetainedOwnedCandidateConstruction, normal: RetainedOwnedCandidateAcceptedFact,
        descriptor: RetainedOwnedCandidateDeferredFact, reader: RetainedOwnedCandidateAcceptedReader,
        readerPublication: RetainedOwnedCandidateReaderPublication, field: RetainedOwnedCandidateFieldSnapshot,
        anchor: RetainedOwnedCandidateDeferredAnchor
    ) {
        self.ledger = ledger
        self.publication = publication
        self.token = token
        self.normal = normal
        self.descriptor = descriptor
        self.reader = reader
        normalReference = reader.normalReference
        self.readerPublication = readerPublication
        self.field = field
        self.anchor = anchor
    }
}

@MainActor
fileprivate final class RetainedOwnedCandidateDeferredAnchor {
    let owner: RetainedOwnedComponentReceipt
    let reader: RetainedOwnedComponentReceipt
    let contribution: RetainedDescriptorContributionReceipt
    let actual: RetainedLazyListActualAttachment
    let field: RetainedOwnedCandidateFieldSnapshot
    let segment: RetainedOwnedCandidateSegmentKey
    let readerRecord: RetainedOwnedCandidateAcceptedReader
    let readerPublication: RetainedOwnedCandidateReaderPublication

    init(
        owner: RetainedOwnedComponentReceipt, reader: RetainedOwnedComponentReceipt,
        contribution: RetainedDescriptorContributionReceipt, actual: RetainedLazyListActualAttachment,
        field: RetainedOwnedCandidateFieldSnapshot, segment: RetainedOwnedCandidateSegmentKey,
        readerRecord: RetainedOwnedCandidateAcceptedReader,
        readerPublication: RetainedOwnedCandidateReaderPublication
    ) {
        self.owner = owner
        self.reader = reader
        self.contribution = contribution
        self.actual = actual
        self.field = field
        self.segment = segment
        self.readerRecord = readerRecord
        self.readerPublication = readerPublication
    }

    var isCurrent: Bool {
        actual.isAttached && contribution.isActive && field.isCurrent
            && owner.hasDeclaredComponent && reader.hasDeclaredComponent
            && readerRecord.isDeclared && readerRecord.publication === readerPublication
            && readerPublication.reader === reader && readerPublication.contribution === contribution
            && actual.node?.retainedLazyListActivityStorage?.ownedCandidateDeferredAnchor === self
    }
}

@MainActor
fileprivate final class RetainedOwnedCandidateAcceptedFact {
    let plan: RetainedOwnedComponentDeclarationPlan
    let actual: RetainedLazyListActualAttachment
    weak var source: ViewNode?
    let wasAcceptedEmpty: Bool
    let insertedReader: RetainedOwnedCandidateChildSource?
    var acceptedReferences: [ObjectIdentifier: RetainedOwnedCandidateReference]?
    weak var acceptedParentReader: RetainedOwnedCandidateAcceptedReader?

    init(
        plan: RetainedOwnedComponentDeclarationPlan, actual: RetainedLazyListActualAttachment,
        source: ViewNode?, wasAcceptedEmpty: Bool, insertedReader: RetainedOwnedCandidateChildSource?
    ) {
        self.plan = plan
        self.actual = actual
        self.source = source
        self.wasAcceptedEmpty = wasAcceptedEmpty
        self.insertedReader = insertedReader
    }
}

/// This fact is recorded only by the successful descriptor-group writer. A
/// later lookup of the node's descriptor anchor cannot manufacture it.
@MainActor
fileprivate final class RetainedOwnedCandidateDeferredFact {
    weak var source: ViewNode?
    let token: RetainedOwnedCandidateConstruction
    let actual: RetainedLazyListActualAttachment
    let contribution: RetainedDescriptorContributionReceipt
    let previousAnchor: RetainedOwnedCandidateDeferredAnchor?
    var acceptedAnchor: RetainedOwnedCandidateDeferredAnchor?

    init(
        source: ViewNode, token: RetainedOwnedCandidateConstruction, actual: RetainedLazyListActualAttachment,
        contribution: RetainedDescriptorContributionReceipt, previousAnchor: RetainedOwnedCandidateDeferredAnchor?
    ) {
        self.source = source
        self.token = token
        self.actual = actual
        self.contribution = contribution
        self.previousAnchor = previousAnchor
    }

    var descriptorFactIsCurrent: Bool {
        guard actual.isAttached, contribution.isActive,
            let installed = actual.node?.retainedLazyListActivityStorage?.descriptorDeferredSubtreeAnchor
        else { return false }
        return installed.contribution === contribution && installed.actual === actual
    }
}

fileprivate struct RetainedOwnedCandidateWriteKey: Hashable {
    let source: ObjectIdentifier
    let target: ObjectIdentifier
    let segment: RetainedOwnedCandidateSegmentKey?
}

@MainActor
final class RetainedOwnedCandidateCatalogWrite {
    fileprivate weak var ledger: RetainedOwnedComponentConstructionLedger?
    fileprivate weak var source: ViewNode?
    fileprivate weak var target: ViewNode?
    fileprivate let sourceAttachment: RetainedLazyListAttachmentProof
    fileprivate let sourceIdentity: RetainedLazyListViewIdentityProof
    fileprivate let targetActual: RetainedLazyListActualAttachment
    fileprivate let token: RetainedOwnedCandidateConstruction?
    fileprivate let original: RetainedOwnedCandidateFieldSnapshot?
    fileprivate let plans: [RetainedOwnedComponentDeclarationPlan]
    fileprivate let key: RetainedOwnedCandidateWriteKey
    fileprivate var wasConsumed = false

    fileprivate init(
        ledger: RetainedOwnedComponentConstructionLedger, source: ViewNode, target: ViewNode,
        targetActual: RetainedLazyListActualAttachment, token: RetainedOwnedCandidateConstruction?,
        original: RetainedOwnedCandidateFieldSnapshot?, plans: [RetainedOwnedComponentDeclarationPlan],
        segment: RetainedOwnedCandidateSegmentKey? = nil
    ) {
        self.ledger = ledger
        self.source = source
        self.target = target
        sourceAttachment = source.captureLazyListAttachmentProof()
        sourceIdentity = source.captureLazyListIdentityProof()
        self.targetActual = targetActual
        self.token = token
        self.original = original
        self.plans = plans
        key = RetainedOwnedCandidateWriteKey(
            source: ObjectIdentifier(source), target: ObjectIdentifier(target), segment: segment)
    }
}

/// Only this attempt's completed native field writes may advance this afterimage.
/// It is not a way to refresh a source, attachment, or deferred proof.
@MainActor
fileprivate final class RetainedOwnedCandidateCatalogPublication {
    let write: RetainedOwnedCandidateCatalogWrite
    var afterimage: RetainedOwnedCandidateFieldSnapshot

    init(write: RetainedOwnedCandidateCatalogWrite, afterimage: RetainedOwnedCandidateFieldSnapshot) {
        self.write = write
        self.afterimage = afterimage
    }
}

@MainActor
fileprivate struct RetainedOwnedCandidateCustodySource {
    let original: RetainedOwnedCandidateFieldSnapshot
    let holder: RetainedOwnedCandidateSegmentKey
    let references: [RetainedOwnedCandidateReference]
    let links: [RetainedOwnedCandidateReference]
    let linkFields: [RetainedOwnedCandidateFieldSnapshot]
}

/// Pending data has no reference-index entry. Only the original true native
/// withdrawal cut may consume it, after both accepted endpoints are checked.
@MainActor
fileprivate final class RetainedOwnedCandidateDepartureCustody {
    weak var ledger: RetainedOwnedComponentConstructionLedger?
    let source: RetainedOwnedCandidateCustodySource
    let receiver: RetainedOwnedCandidateCatalogPublication
    var wasConsumed = false

    init(
        ledger: RetainedOwnedComponentConstructionLedger, source: RetainedOwnedCandidateCustodySource,
        receiver: RetainedOwnedCandidateCatalogPublication
    ) {
        self.ledger = ledger
        self.source = source
        self.receiver = receiver
    }
}

@MainActor
fileprivate final class RetainedOwnedCandidateAcceptedCustody {
    let source: RetainedOwnedCandidateFieldSnapshot
    let receiver: RetainedOwnedCandidateCatalogPublication
    let mapping: [(original: RetainedOwnedCandidateReference, accepted: RetainedOwnedCandidateReference)]
    var returnWasConsumed = false

    init(
        source: RetainedOwnedCandidateFieldSnapshot, receiver: RetainedOwnedCandidateCatalogPublication,
        mapping: [(original: RetainedOwnedCandidateReference, accepted: RetainedOwnedCandidateReference)]
    ) {
        self.source = source
        self.receiver = receiver
        self.mapping = mapping
    }
}

/// This is the accepted native afterimage of one exact reference transfer. It
/// may qualify a later step of this ledger, but never a foreign attempt.
@MainActor
fileprivate final class RetainedOwnedCandidateReferenceSuccessor {
    let original: RetainedOwnedCandidateReference
    let accepted: RetainedOwnedCandidateReference
    let publication: RetainedOwnedCandidateCatalogPublication

    init(
        original: RetainedOwnedCandidateReference, accepted: RetainedOwnedCandidateReference,
        publication: RetainedOwnedCandidateCatalogPublication
    ) {
        self.original = original
        self.accepted = accepted
        self.publication = publication
    }
}

@MainActor
fileprivate final class RetainedOwnedCandidateFieldSuccessor {
    let original: RetainedOwnedCandidateFieldSnapshot
    let publication: RetainedOwnedCandidateCatalogPublication

    init(original: RetainedOwnedCandidateFieldSnapshot, publication: RetainedOwnedCandidateCatalogPublication) {
        self.original = original
        self.publication = publication
    }
}

@MainActor
fileprivate final class RetainedOwnedCandidateTaskBoundary {
    weak var source: ViewNode?
    let construction: RetainedOwnedCandidateConstruction?

    init(source: ViewNode, construction: RetainedOwnedCandidateConstruction?) {
        self.source = source
        self.construction = construction
    }
}

/// Initial task-route qualification is captured with the original construction
/// path. A live namespace field, role, or later owner lookup cannot create it.
@MainActor
fileprivate final class RetainedOwnedCandidateTaskQualification {
    private let descriptor: RetainedDescriptorComponentAttribution?
    private let lazy: RetainedLazyListBuildAttribution?
    private let constructions: [RetainedOwnedCandidateConstruction]
    private let boundaries: [RetainedOwnedCandidateTaskBoundary]

    init(
        descriptor: RetainedDescriptorComponentAttribution?, lazy: RetainedLazyListBuildAttribution?,
        constructions: [RetainedOwnedCandidateConstruction], boundaries: [RetainedOwnedCandidateTaskBoundary]
    ) {
        self.descriptor = descriptor
        self.lazy = lazy
        self.constructions = constructions
        self.boundaries = boundaries
    }

    var canObserveOriginalConstruction: Bool {
        let admitted: Bool
        if let descriptor {
            admitted = descriptor.canConstruct
        } else {
            admitted = lazy?.constructionState == .admittedForConstruction
        }
        return admitted && constructions.allSatisfy { $0.canConstruct }
    }

    var canPublish: Bool {
        if let descriptor {
            guard descriptor.descriptorScope?.canPublishDescriptors == true else { return false }
        } else {
            guard lazy?.canPublishNestedDescriptor == true else { return false }
        }
        return constructions.allSatisfy { $0.ledger?.canPublishCandidateTaskConstruction($0) == true }
    }

    func permitsBoundary(source: ViewNode, actual: RetainedLazyListActualAttachment) -> Bool {
        guard canPublish, actual.isAttached,
            let original = boundaries.first(where: { $0.source === source }),
            source.selectedContentRole == .viewThatFits, actual.node?.selectedContentRole == .viewThatFits
        else { return false }
        guard let construction = original.construction else {
            // A purely structural wrapper has no namespace authority. It must
            // not be adopted as a namespace-bearing boundary by this route.
            return actual.node?.retainedLazyListActivityStorage?.ownedCandidateField == nil
        }
        return construction.ledger?.hasAcceptedCandidateTaskBoundary(
            construction, source: source, actual: actual) == true
    }
}

@MainActor
fileprivate func captureOwnedCandidateTaskQualification(
    context: RetainedOwnedCandidateConstruction?, sourceBoundaries: [ViewNode],
    attribution: RetainedDescriptorComponentAttribution
) -> RetainedOwnedCandidateTaskQualification? {
    guard attribution.canConstruct, let scope = attribution.descriptorScope else { return nil }
    var constructions: [RetainedOwnedCandidateConstruction] = []
    var seen: Set<ObjectIdentifier> = []
    func capture(_ construction: RetainedOwnedCandidateConstruction) -> Bool {
        var next: RetainedOwnedCandidateConstruction? = construction
        while let value = next {
            guard value.canConstruct, value.qualification.scope === scope else { return false }
            if !seen.insert(ObjectIdentifier(value)).inserted { return true }
            guard seen.count <= ViewNode.maximumTraversalDepth else { return false }
            constructions.append(value)
            next = value.parent
        }
        return true
    }
    if let context {
        guard scope.ownedLedger.acceptsOwnedCandidateConstruction(context, attribution: attribution), capture(context)
        else { return nil }
    }
    var boundaries: [RetainedOwnedCandidateTaskBoundary] = []
    for source in sourceBoundaries {
        guard source.selectedContentRole == .viewThatFits else { return nil }
        let construction = source.retainedLazyListActivityStorage?.ownedCandidateBoundarySource
        if let construction {
            guard let original = construction.attribution, construction.boundarySource === source,
                original.ledger === attribution.ledger,
                attribution.ledger?.candidateComponent(original.component, descendsFrom: attribution.component) == true,
                capture(construction)
            else { return nil }
        }
        boundaries.append(RetainedOwnedCandidateTaskBoundary(source: source, construction: construction))
    }
    return RetainedOwnedCandidateTaskQualification(
        descriptor: attribution, lazy: nil, constructions: constructions, boundaries: boundaries)
}

@MainActor
fileprivate func captureOwnedCandidateTaskQualification(
    context: RetainedOwnedCandidateConstruction?, sourceBoundaries: [ViewNode],
    attribution: RetainedLazyListBuildAttribution
) -> RetainedOwnedCandidateTaskQualification? {
    guard attribution.constructionState == .admittedForConstruction, context == nil else { return nil }
    var boundaries: [RetainedOwnedCandidateTaskBoundary] = []
    for source in sourceBoundaries {
        guard source.selectedContentRole == .viewThatFits,
            source.retainedLazyListActivityStorage?.ownedCandidateBoundarySource == nil
        else { return nil }
        boundaries.append(RetainedOwnedCandidateTaskBoundary(source: source, construction: nil))
    }
    return RetainedOwnedCandidateTaskQualification(
        descriptor: nil, lazy: attribution, constructions: [], boundaries: boundaries)
}

extension RetainedLazyListNodeActivityStorage {
    fileprivate func withdrawOwnedCandidateField() {
        // Called at an actual native withdrawal cut. Capturing the current
        // incarnation here cannot make a stale earlier receipt current again.
        let originalField = ownedCandidateField
        let originalAnchor = ownedCandidateDeferredAnchor
        if let originalField, let pending = originalField.departureCustody {
            pending.ledger?.consumeCandidateDepartureCustody(pending, from: originalField)
        }
        // Failure to preserve custody never suppresses the actual O withdrawal.
        originalField?.withdraw()
        if ownedCandidateDeferredAnchor === originalAnchor { ownedCandidateDeferredAnchor = nil }
    }
}

extension RetainedDescriptorConstructionLedger {
    fileprivate var canSeedOwnedCandidateOrigins: Bool {
        !isFrozen && sealed == nil && componentOrder.isEmpty
    }

    fileprivate func candidateComponent(
        _ component: RetainedDescriptorComponentID, descendsFrom ancestor: RetainedDescriptorComponentID
    ) -> Bool {
        var current: RetainedDescriptorComponentID? = component
        var visited: Set<ObjectIdentifier> = []
        while let id = current, visited.count < ViewNode.maximumTraversalDepth {
            guard visited.insert(ObjectIdentifier(id)).inserted, let record = components[ObjectIdentifier(id)],
                !rejectedComponentIDs.contains(ObjectIdentifier(id))
            else { return false }
            if id === ancestor { return true }
            current = record.parent
        }
        return false
    }
}

extension RetainedOwnedComponentConstructionLedger {
    fileprivate func canPublishCandidateTaskConstruction(_ token: RetainedOwnedCandidateConstruction) -> Bool {
        guard ownsCandidateConstruction(token), token.qualification.canPublish,
            !token.owner.owner.wasRevoked, token.owner.nativeLifetime.permitsDeclaredWrite,
            token.owner.owner.nativePresence === token.owner.componentPresence,
            !token.segmentOwner.owner.wasRevoked, token.segmentOwner.nativeLifetime.permitsDeclaredWrite
        else { return false }
        if let original = token.qualification.fields[ObjectIdentifier(token.owner.owner)],
            resolvedCandidateOriginal(original) != nil
        {
            return true
        }
        return candidatePublications.values.contains {
            $0.write.token === token && $0.afterimage.isCurrent
                && $0.afterimage.field.owner === token.owner.componentPresence
        }
    }

    fileprivate func hasAcceptedCandidateTaskBoundary(
        _ token: RetainedOwnedCandidateConstruction, source: ViewNode, actual: RetainedLazyListActualAttachment
    ) -> Bool {
        guard canPublishCandidateTaskConstruction(token), token.boundarySource === source,
            let field = actual.node?.retainedLazyListActivityStorage?.ownedCandidateField,
            field.isCurrent, field.owner === token.owner.componentPresence
        else { return false }
        return candidateAcceptedFacts.contains {
            !$0.wasAcceptedEmpty && !$0.plan.declarationOnly && $0.plan.receipt === token.owner && $0.source === source
                && $0.actual.target === actual.target && $0.actual.attachment === actual.attachment
                && $0.actual.isAttached
        }
    }

    fileprivate func captureCandidateFields(
        below root: ViewNode, in runtime: RetainedViewRuntime
    ) -> [ObjectIdentifier: RetainedOwnedCandidateFieldSnapshot]? {
        var result: [ObjectIdentifier: RetainedOwnedCandidateFieldSnapshot] = [:]
        var pending: [(ViewNode, Int)] = [(root, 0)]
        var seen: Set<ObjectIdentifier> = []
        while let (node, depth) = pending.popLast() {
            guard depth < ViewNode.maximumTraversalDepth, seen.insert(ObjectIdentifier(node)).inserted,
                node.retainedLazyListRuntime === runtime
            else { return nil }
            if let storage = node.retainedLazyListActivityStorage, let field = storage.ownedCandidateField {
                let actual = storage.captureActualAttachment(of: node, in: runtime)
                guard let snapshot = RetainedOwnedCandidateFieldSnapshot(field: field, actual: actual),
                    result[ObjectIdentifier(field.owner.owner)] == nil
                else { return nil }
                result[ObjectIdentifier(field.owner.owner)] = snapshot
            }
            for child in node.children {
                guard child.parent === node else { return nil }
                pending.append((child, depth + 1))
            }
        }
        return result
    }

    private func captureCandidateCatalogGraphs(
        fields: [ObjectIdentifier: RetainedOwnedCandidateFieldSnapshot],
        continuation: RetainedOwnedCandidateDeferredAnchor?
    ) -> [RetainedOwnedCandidateCatalogGraph]? {
        var graphs: [RetainedOwnedCandidateCatalogGraph] = []
        for original in fields.values {
            let root = continuation?.field.field === original.field ? continuation?.readerRecord : nil
            guard let graph = RetainedOwnedCandidateCatalogGraph(original: original, root: root) else { return nil }
            graphs.append(graph)
        }
        return graphs
    }

    fileprivate func seedOwnedCandidateOrigins(
        at root: ViewNode, scope: RetainedLazyListDescriptorBuildScope
    ) -> Bool {
        guard !didSeedOwnedCandidateRoot else { return false }
        didSeedOwnedCandidateRoot = true
        guard scope.origin == .componentHostRoot, scope.ownedLedger === self, scope.canConstructDescriptors,
            scope.ordinaryLedger.canSeedOwnedCandidateOrigins, registrations.isEmpty, frozenPlans == nil,
            let runtime = root.retainedLazyListRuntime, runtime.root === root,
            runtime.lazyListLogicalHostLifetime === scope.nativeHostLifetime,
            let storage = root.retainedLazyListActivityStorage,
            storage.descriptorOwnerLifetime === scope.nativeOwnerLifetime,
            let fields = captureCandidateFields(below: root, in: runtime)
        else { return false }
        let actual = storage.captureActualAttachment(of: root, in: runtime)
        guard actual.isAttached,
            let graphs = captureCandidateCatalogGraphs(fields: fields, continuation: nil)
        else { return false }
        let qualification = RetainedOwnedCandidateScopeQualification(
            scope: scope, actual: actual, contribution: nil, continuation: nil, fields: fields,
            childCatalogGraphs: graphs)
        scope.ownedCandidateQualification = qualification
        candidateQualifications[ObjectIdentifier(scope)] = qualification
        return true
    }

    fileprivate func qualifyOwnedCandidateSubtree(
        scope: RetainedLazyListDescriptorBuildScope, contribution: RetainedDescriptorContributionReceipt,
        actual: RetainedLazyListActualAttachment
    ) -> Bool {
        guard scope.ownedLedger === self, scope.canConstructDescriptors, scope.origin == .managedSubtree,
            candidateQualifications[ObjectIdentifier(scope)] == nil, contribution.isActive, actual.isAttached,
            let root = actual.node, let runtime = actual.runtime,
            contribution.nativeHostLifetime === scope.nativeHostLifetime,
            let fields = captureCandidateFields(below: root, in: runtime)
        else { return false }
        let continuation = root.retainedLazyListActivityStorage?.ownedCandidateDeferredAnchor
        if let continuation {
            guard continuation.contribution === contribution, continuation.actual.target === actual.target,
                continuation.actual.attachment === actual.attachment, continuation.isCurrent
            else { return false }
        }
        var originals = fields
        if let continuation {
            // This field may be above the reader. Its exact admitted segment is
            // independent of other reader segments in the same namespace.
            originals[ObjectIdentifier(continuation.owner.owner)] = continuation.field
        }
        guard let graphs = captureCandidateCatalogGraphs(fields: originals, continuation: continuation) else {
            return false
        }
        let qualification = RetainedOwnedCandidateScopeQualification(
            scope: scope, actual: actual, contribution: contribution, continuation: continuation, fields: originals,
            childCatalogGraphs: graphs)
        scope.ownedCandidateQualification = qualification
        candidateQualifications[ObjectIdentifier(scope)] = qualification
        return true
    }

    fileprivate func candidateRegistration(
        receipt: RetainedOwnedComponentReceipt, attribution: RetainedDescriptorComponentAttribution
    ) -> RetainedOwnedComponentRegistration? {
        guard attribution.descriptorScope?.ownedLedger === self, attribution.descriptorBuildAttempt === attempt,
            let entries = registrations[.descriptor(ObjectIdentifier(attribution.component))]
        else { return nil }
        return entries.first { $0.receipt === receipt }
    }

    fileprivate func ownsCandidateConstruction(_ token: RetainedOwnedCandidateConstruction) -> Bool {
        guard token.ledger === self, !wasFinished else { return false }
        if token.isDeferredSegment { return candidateSegments[token.segmentKey] === token }
        return candidateBoundaries[ObjectIdentifier(token.owner.owner)] === token
    }

    fileprivate func acceptsOwnedCandidateConstruction(
        _ token: RetainedOwnedCandidateConstruction, attribution: RetainedDescriptorComponentAttribution
    ) -> Bool {
        guard token.canConstruct, token.ledger === self, attribution.canConstruct,
            let original = token.attribution, original.ledger === attribution.ledger,
            original.descriptorScope === attribution.descriptorScope,
            token.qualification === attribution.descriptorScope?.ownedCandidateQualification
        else { return false }
        return attribution.ledger?.candidateComponent(
            attribution.component, descendsFrom: original.component) == true
    }

    fileprivate func beginOwnedCandidateConstruction(
        owner: RetainedOwnedComponentReceipt, attribution: RetainedDescriptorComponentAttribution
    ) -> RetainedOwnedCandidateConstruction? {
        guard frozenPlans == nil, !wasFinished, attribution.canConstruct,
            let registration = candidateRegistration(receipt: owner, attribution: attribution),
            !registration.declarationOnly,
            let scope = attribution.descriptorScope, let qualification = scope.ownedCandidateQualification,
            candidateQualifications[ObjectIdentifier(scope)] === qualification,
            qualification.canConstruct, candidateBoundaries[ObjectIdentifier(owner.owner)] == nil
        else { return nil }
        let token = RetainedOwnedCandidateConstruction(
            ledger: self, attribution: attribution, qualification: qualification, owner: owner,
            segmentOwner: owner, parent: registration.candidateConstruction, isDeferredSegment: false)
        candidateBoundaries[ObjectIdentifier(owner.owner)] = token
        return token
    }

    fileprivate func beginOwnedCandidateSegment(
        owner: RetainedOwnedComponentReceipt, attribution: RetainedDescriptorComponentAttribution,
        parent: RetainedOwnedCandidateConstruction
    ) -> RetainedOwnedCandidateConstruction? {
        guard acceptsOwnedCandidateConstruction(parent, attribution: attribution),
            let registration = candidateRegistration(receipt: owner, attribution: attribution),
            !registration.declarationOnly, registration.candidateConstruction === parent
        else { return nil }
        let key = RetainedOwnedCandidateSegmentKey(namespace: parent.owner.owner, segment: owner.owner)
        if let existing = candidateSegments[key] {
            guard existing === parent, parent.parent == nil, parent.isDeferredSegment,
                parent.segmentConstruction == nil, parent.selfConstruction == nil,
                let original = parent.qualification.continuation, original.isCurrent,
                parent.segmentOwner === original.reader, owner !== original.reader,
                owner.owner === original.reader.owner,
                owner.componentPresence === original.reader.componentPresence,
                registration.previous.contains(where: { $0 === original.reader }),
                original.readerRecord.isDeclared,
                original.readerRecord.normalReference.member.identity == ObjectIdentifier(owner.componentPresence)
            else { return nil }
            parent.selfConstruction = RetainedOwnedCandidateSelfConstruction(
                token: parent, registration: registration, original: original)
            return parent
        }
        guard candidateSegments[key] == nil else { return nil }
        let token = RetainedOwnedCandidateConstruction(
            ledger: self, attribution: attribution, qualification: parent.qualification, owner: parent.owner,
            segmentOwner: owner, parent: parent, isDeferredSegment: true)
        token.segmentConstruction = RetainedOwnedCandidateSegmentConstruction(
            parent: parent, registration: registration, token: token)
        candidateSegments[key] = token
        return token
    }

    fileprivate func ownedCandidateContinuation(
        attribution: RetainedDescriptorComponentAttribution
    ) -> RetainedOwnedCandidateContinuation {
        guard attribution.canConstruct, let scope = attribution.descriptorScope,
            let qualification = scope.ownedCandidateQualification,
            candidateQualifications[ObjectIdentifier(scope)] === qualification, qualification.canConstruct
        else { return .rejected }
        guard let continuation = qualification.continuation else { return .unscoped }
        guard continuation.isCurrent else { return .rejected }
        if let existing = candidateSegments[continuation.segment] {
            return existing.attribution === attribution && existing.canConstruct ? .admitted(existing) : .rejected
        }
        let token = RetainedOwnedCandidateConstruction(
            ledger: self, attribution: attribution, qualification: qualification, owner: continuation.owner,
            segmentOwner: continuation.reader, parent: nil, isDeferredSegment: true)
        candidateSegments[continuation.segment] = token
        return .admitted(token)
    }

    private func freezeCandidateSelfSources() -> Bool {
        guard candidateSelfSources.isEmpty, candidateSelfRegistrations.isEmpty else { return false }
        for token in candidateSegments.values {
            guard let construction = token.selfConstruction else { continue }
            guard let registration = construction.registration,
                construction.token === token, token.segmentConstruction == nil,
                registration.candidateConstruction === token,
                registrations[registration.origin.key]?.contains(where: { $0 === registration }) == true,
                let scope = token.qualification.scope, let source = token.deferredSource,
                source.retainedLazyListActivityStorage?.ownedCandidateDeferredSource === token,
                case .descriptor(let component) = registration.origin,
                let expected = scope.ordinaryLedger.frozenOwnedCandidateDeferredGroup(
                    component: component, source: source),
                let plan = selectedOrdinaryPlans(for: source)?.first(where: {
                    !$0.declarationOnly && $0.receipt === registration.receipt
                        && planRegistrations[ObjectIdentifier($0)] === registration
                }), candidateSelfSources[ObjectIdentifier(source)] == nil
            else { return false }
            let input = RetainedOwnedCandidateSelfSource(
                construction: construction, source: source, plan: plan, expectedGroup: expected)
            candidateSelfSources[ObjectIdentifier(source)] = input
            candidateSelfRegistrations[ObjectIdentifier(registration)] = input
        }
        return true
    }

    fileprivate func hasOwnedCandidateSelfSource(_ source: ViewNode) -> Bool {
        candidateSelfSources[ObjectIdentifier(source)] != nil
            || source.retainedLazyListActivityStorage?.ownedCandidateDeferredSource?.selfConstruction != nil
    }

    fileprivate func applyOwnedCandidateSelfSource(from source: ViewNode, to target: ViewNode) -> Bool {
        guard didPrepare, !wasFinished, let input = candidateSelfSources[ObjectIdentifier(source)],
            input.source === source, let token = input.construction.token,
            let scope = token.qualification.scope,
            candidateQualifications[ObjectIdentifier(scope)] === token.qualification,
            input.construction.original.actual.node === target
        else { return false }
        if let existing = candidateSelfPublications[ObjectIdentifier(input)] {
            return canFinishCandidateSelf(existing, requireActiveOriginal: true)
        }
        guard token.qualification.canPublish,
            let current = token.qualification.currentContinuation,
            current.readerRecord === input.construction.original.readerRecord,
            current.readerPublication === input.construction.original.readerPublication,
            let field = resolvedCandidateOriginal(input.construction.original.field),
            field === current.field, field.selectedSegment == token.segmentKey
        else { return false }
        let publication = RetainedOwnedCandidateSelfPublication(
            ledger: self, input: input, originalAnchor: current, originalField: field)
        guard canFinishCandidateSelf(publication, requireActiveOriginal: true) else { return false }
        candidateSelfPublications[ObjectIdentifier(input)] = publication
        return true
    }

    fileprivate func preparedCandidateSelfPublication(
        from source: ViewNode, to target: ViewNode
    ) -> RetainedOwnedCandidateSelfPublication? {
        guard let input = candidateSelfSources[ObjectIdentifier(source)], input.source === source,
            let publication = candidateSelfPublications[ObjectIdentifier(input)],
            publication.input === input, publication.originalAnchor.actual.node === target
        else { return nil }
        return publication
    }

    fileprivate func canFinishCandidateSelf(
        _ publication: RetainedOwnedCandidateSelfPublication, requireActiveOriginal: Bool = false
    ) -> Bool {
        let input = publication.input
        let original = input.construction.original
        guard !wasFinished, !publication.wasRefused, !publication.didFinish,
            let token = input.construction.token, token.selfConstruction === input.construction,
            let registration = input.construction.registration,
            registration.candidateConstruction === token,
            registrations[registration.origin.key]?.contains(where: { $0 === registration }) == true,
            planRegistrations[ObjectIdentifier(input.plan)] === registration,
            input.plan.receipt === registration.receipt, !input.plan.declarationOnly,
            ownsCandidateConstruction(token), let scope = token.qualification.scope,
            candidateQualifications[ObjectIdentifier(scope)] === token.qualification,
            scope.canPublishDescriptors, token.qualification.actual.isAttached,
            token.qualification.contribution === original.contribution,
            token.qualification.continuation === original,
            let source = input.source, input.sourceAttachment.isCurrent, input.sourceIdentity.isCurrent,
            candidateSelfSources[ObjectIdentifier(source)] === input,
            candidateSelfRegistrations[ObjectIdentifier(registration)] === input,
            token.deferredSource === source,
            source.retainedLazyListActivityStorage?.ownedCandidateDeferredSource === token,
            !source.containsRejectedRetainedSource, original.actual.isAttached,
            original.owner.hasDeclaredComponent, original.reader.hasDeclaredComponent,
            registration.receipt.hasDeclaredComponent,
            registration.receipt.slotPermissions.allSatisfy({ !$0.wasRevoked }),
            original.readerRecord.isDeclared, original.readerRecord.publication === original.readerPublication,
            original.readerRecord.normalReference.isCurrent,
            let field = resolvedCandidateOriginal(original.field), field.isCurrent,
            let cutField = resolvedCandidateOriginal(publication.originalField), cutField === field,
            field.field === original.field.field, field.incarnation === original.field.incarnation,
            field.actual === original.field.actual, field.selectedSegment == original.segment,
            let anchor = token.qualification.currentContinuation,
            anchor === original || anchor === token.qualification.continuationAfterimage,
            anchor.readerRecord === original.readerRecord, anchor.readerPublication === original.readerPublication,
            anchor.field === field, anchor.actual.node === original.actual.node,
            anchor.actual.target === original.actual.target, anchor.actual.attachment === original.actual.attachment,
            original.actual.node?.retainedLazyListActivityStorage?.ownedCandidateDeferredAnchor === anchor
        else { return false }
        if original.contribution.isActive { return true }
        guard !requireActiveOriginal, publication.didDrainOwnAbsence,
            let absence = publication.ownAbsence, absence.previous === original.contribution,
            absence.actual.target === original.actual.target, absence.actual.attachment === original.actual.attachment
        else { return false }
        return true
    }

    fileprivate func finishCandidateSelfPublication(_ publication: RetainedOwnedCandidateSelfPublication) {
        guard canFinishCandidateSelf(publication), let normal = publication.normal,
            let descriptor = publication.descriptor, descriptor.descriptorFactIsCurrent,
            descriptor.contribution === publication.input.expectedGroup,
            let registration = publication.input.construction.registration,
            let token = publication.input.construction.token,
            let source = publication.input.source, normal.source === source, descriptor.source === source,
            normal.plan === publication.input.plan,
            normal.plan.receipt === registration.receipt,
            normal.actual.isAttached, normal.actual.node === publication.originalAnchor.actual.node,
            normal.actual.target === descriptor.actual.target,
            normal.actual.attachment === descriptor.actual.attachment,
            let field = resolvedCandidateOriginal(publication.input.construction.original.field), field.isCurrent,
            let target = descriptor.actual.node
        else { return }
        let reader = publication.input.construction.original.readerRecord
        guard reader.isDeclared, reader.normalReference.isCurrent,
            case .component(let presence) = reader.normalReference.member,
            presence === normal.plan.receipt.componentPresence
        else { return }
        let nextPublication = RetainedOwnedCandidateReaderPublication(
            reader: normal.plan.receipt, contribution: descriptor.contribution, actual: descriptor.actual)
        let next = RetainedOwnedCandidateDeferredAnchor(
            owner: token.owner, reader: normal.plan.receipt, contribution: descriptor.contribution,
            actual: descriptor.actual, field: field, segment: token.segmentKey,
            readerRecord: reader, readerPublication: nextPublication)
        // Only the next independent admission sees this new receipt. The old
        // qualification, construction token and general publications stay stale.
        publication.didFinish = true
        reader.publication = nextPublication
        target.lazyListActivityStorage().ownedCandidateDeferredAnchor = next
        descriptor.acceptedAnchor = next
        if publication.didDrainOwnAbsence, let absence = publication.ownAbsence,
            absence.previous === publication.input.construction.original.contribution,
            absence.actual.target === publication.originalAnchor.actual.target,
            absence.actual.attachment === publication.originalAnchor.actual.attachment,
            candidateSelfBodyAcceptances[ObjectIdentifier(token)] == nil
        {
            candidateSelfBodyAcceptances[ObjectIdentifier(token)] = RetainedOwnedCandidateSelfBodyAcceptance(
                ledger: self, publication: publication, token: token, normal: normal, descriptor: descriptor,
                reader: reader, readerPublication: nextPublication, field: field, anchor: next)
            flushCandidateAcceptedFacts()
        }
    }

    /// This checks the original operation and both actual facts. The selected
    /// field revision is checked separately so only an adjacent native batch can
    /// validate its own result without renewing the original qualification.
    private func selfAcceptedLifetimeAndFactsAreCurrent(
        _ accepted: RetainedOwnedCandidateSelfBodyAcceptance
    ) -> Bool {
        let publication = accepted.publication
        let input = publication.input
        let original = input.construction.original
        let token = accepted.token
        guard !wasFinished, !accepted.wasRefused, accepted.ledger === self,
            publication.ledger === self, publication.didFinish, !publication.wasRefused,
            publication.didDrainOwnAbsence, let absence = publication.ownAbsence,
            absence.previous === original.contribution,
            absence.actual.target === original.actual.target, absence.actual.attachment === original.actual.attachment,
            input.construction.token === token, token.selfConstruction === input.construction,
            let registration = input.construction.registration,
            registration.candidateConstruction === token,
            registrations[registration.origin.key]?.contains(where: { $0 === registration }) == true,
            planRegistrations[ObjectIdentifier(input.plan)] === registration,
            input.plan.receipt === registration.receipt, !input.plan.declarationOnly,
            candidateSelfBodyAcceptances[ObjectIdentifier(token)] === accepted,
            candidateSelfPublications[ObjectIdentifier(input)] === publication,
            candidateSelfRegistrations[ObjectIdentifier(registration)] === input,
            ownsCandidateConstruction(token), let scope = token.qualification.scope,
            candidateQualifications[ObjectIdentifier(scope)] === token.qualification,
            scope.canPublishDescriptors, token.qualification.actual.isAttached,
            token.qualification.contribution === original.contribution,
            token.qualification.continuation === original,
            let source = input.source, input.sourceAttachment.isCurrent, input.sourceIdentity.isCurrent,
            candidateSelfSources[ObjectIdentifier(source)] === input,
            token.deferredSource === source,
            source.retainedLazyListActivityStorage?.ownedCandidateDeferredSource === token,
            !source.containsRejectedRetainedSource, original.actual.isAttached,
            original.owner.hasDeclaredComponent, original.reader.hasDeclaredComponent,
            registration.receipt.hasDeclaredComponent,
            registration.receipt.slotPermissions.allSatisfy({ !$0.wasRevoked }),
            publication.normal === accepted.normal, publication.descriptor === accepted.descriptor,
            accepted.normal.plan === input.plan, accepted.normal.source === source,
            accepted.normal.actual.isAttached, accepted.descriptor.source === source,
            accepted.descriptor.contribution === input.expectedGroup, accepted.descriptor.descriptorFactIsCurrent,
            accepted.normal.actual.target === accepted.descriptor.actual.target,
            accepted.normal.actual.attachment === accepted.descriptor.actual.attachment,
            accepted.normal.actual.target === publication.originalAnchor.actual.target,
            accepted.normal.actual.attachment === publication.originalAnchor.actual.attachment,
            accepted.reader === original.readerRecord, accepted.reader.isDeclared,
            accepted.reader.normalReference === accepted.normalReference, accepted.normalReference.isCurrent,
            accepted.reader.publication === accepted.readerPublication,
            accepted.readerPublication.reader === registration.receipt,
            accepted.readerPublication.contribution === input.expectedGroup,
            accepted.readerPublication.actual === accepted.descriptor.actual,
            accepted.field.field === publication.originalField.field,
            accepted.field.field === original.field.field, accepted.field.incarnation === original.field.incarnation,
            accepted.field.actual === original.field.actual, accepted.field.actual.isAttached,
            accepted.field.field.isCurrent, accepted.field.selectedSegment == token.segmentKey,
            accepted.anchor.field === accepted.field, accepted.anchor.owner === token.owner,
            accepted.anchor.reader === registration.receipt, accepted.anchor.readerRecord === accepted.reader,
            accepted.anchor.readerPublication === accepted.readerPublication,
            accepted.anchor.contribution === input.expectedGroup, accepted.anchor.actual === accepted.descriptor.actual,
            accepted.descriptor.acceptedAnchor === accepted.anchor,
            accepted.anchor.actual.node?.retainedLazyListActivityStorage?.ownedCandidateDeferredAnchor
                === accepted.anchor
        else { return false }
        return true
    }

    private func candidateSelfBodyAcceptance(
        for token: RetainedOwnedCandidateConstruction
    ) -> RetainedOwnedCandidateSelfBodyAcceptance? {
        guard let accepted = candidateSelfBodyAcceptances[ObjectIdentifier(token)], accepted.token === token,
            selfAcceptedLifetimeAndFactsAreCurrent(accepted), accepted.field.isCurrent, accepted.anchor.isCurrent
        else { return nil }
        return accepted
    }

    fileprivate func permitsSelfAcceptedNormal(
        _ fact: RetainedOwnedCandidateAcceptedFact, with accepted: RetainedOwnedCandidateSelfBodyAcceptance
    ) -> Bool {
        guard candidateSelfBodyAcceptance(for: accepted.token) === accepted,
            candidateAcceptedFacts.contains(where: { $0 === fact }), fact.actual.isAttached,
            !fact.plan.declarationOnly, selectedPlans.contains(ObjectIdentifier(fact.plan)),
            let registration = planRegistrations[ObjectIdentifier(fact.plan)],
            registration.receipt === fact.plan.receipt, registration.candidateConstruction === accepted.token,
            registrations[registration.origin.key]?.contains(where: { $0 === registration }) == true,
            registration !== accepted.publication.input.construction.registration,
            fact.plan.receipt.hasDeclaredComponent,
            fact.plan.receipt.slotPermissions.allSatisfy({ $0.isDeclared && !$0.wasRevoked })
        else { return false }
        if let source = fact.source {
            return selectedOrdinaryPlans(for: source)?.contains(where: { $0 === fact.plan }) == true
        }
        return fact.wasAcceptedEmpty && fact.plan.sourcePayloads.isEmpty
    }

    /// A fresh child's original construction input may wait for its parent's
    /// actual SELF group. This transports data only; no reference is created.
    private func originalSelfParent(
        of input: RetainedOwnedCandidateChildSource
    ) -> RetainedOwnedCandidateConstruction? {
        let construction = input.construction
        let parent = construction.parent
        let registration = construction.registration
        guard !wasFinished, didPrepare, case .fresh = input.origin, input.sourceBindingsAreCurrent,
            let source = input.source, candidateChildCatalogSources[ObjectIdentifier(source)] === input,
            let token = construction.token, ownsCandidateConstruction(token), ownsCandidateConstruction(parent),
            token.parent === parent, token.qualification === parent.qualification,
            parent.selfConstruction != nil, registration.candidateConstruction === parent,
            registration.receipt === input.normalPlan.receipt, !input.normalPlan.declarationOnly,
            selectedPlans.contains(ObjectIdentifier(input.normalPlan)),
            planRegistrations[ObjectIdentifier(input.normalPlan)] === registration,
            registrations[registration.origin.key]?.contains(where: { $0 === registration }) == true
        else { return nil }
        return parent
    }

    private func canHoldPendingSelfChild(_ input: RetainedOwnedCandidateChildSource) -> Bool {
        guard let parent = originalSelfParent(of: input) else { return false }
        if candidateSelfBodyAcceptance(for: parent) != nil { return true }
        guard let source = parent.deferredSource, let selfInput = candidateSelfSources[ObjectIdentifier(source)],
            selfInput.construction === parent.selfConstruction,
            let publication = candidateSelfPublications[ObjectIdentifier(selfInput)], publication.input === selfInput
        else { return false }
        // canFinish requires the complete drained own absence once the original
        // contribution is inactive. A pre-revoke witness alone is insufficient.
        return canFinishCandidateSelf(publication)
    }

    private func selfAcceptedChildLifetimeAndFactsAreCurrent(
        _ accepted: RetainedOwnedCandidateSegmentAcceptance
    ) -> Bool {
        guard !accepted.selfWasRefused, let selfParent = accepted.selfParent,
            candidateSelfBodyAcceptance(for: selfParent.token) === selfParent,
            let token = accepted.construction.token, ownsCandidateConstruction(token),
            candidateAcceptedSegments[ObjectIdentifier(token)] === accepted,
            let source = accepted.descriptor.source,
            let input = candidateChildCatalogSources[ObjectIdentifier(source)],
            input.construction === accepted.construction, originalSelfParent(of: input) === selfParent.token,
            accepted.normal.insertedReader === input, accepted.normal.plan === input.normalPlan,
            accepted.normal.source === source, accepted.normal.actual.node === source,
            accepted.normal.actual.isAttached, accepted.descriptor.descriptorFactIsCurrent,
            accepted.descriptor.contribution === input.expectedGroup,
            candidateAcceptedFacts.contains(where: { $0 === accepted.normal }),
            candidateDeferredFacts.contains(where: { $0 === accepted.descriptor }),
            accepted.normal.actual.target === accepted.descriptor.actual.target,
            accepted.normal.actual.attachment === accepted.descriptor.actual.attachment,
            accepted.normal.acceptedParentReader === selfParent.reader,
            let normal = accepted.normal.acceptedReferences?[
                ObjectIdentifier(input.normalPlan.receipt.componentPresence)],
            normal === accepted.reader.normalReference, normal.isCurrent,
            normal.lineage.contains(where: { $0 === selfParent.normalReference.declarationEdge }),
            accepted.reader.isDeclared, accepted.reader.parent === selfParent.reader,
            accepted.reader.publication === accepted.publication,
            accepted.publication.reader === input.normalPlan.receipt,
            accepted.publication.contribution === input.expectedGroup,
            accepted.publication.actual === accepted.descriptor.actual,
            input.normalPlan.receipt.hasDeclaredComponent,
            input.normalPlan.receipt.slotPermissions.allSatisfy({ $0.isDeclared && !$0.wasRevoked }),
            accepted.field.field === selfParent.field.field,
            accepted.field.incarnation === selfParent.field.incarnation,
            accepted.field.actual === selfParent.field.actual, accepted.field.actual.isAttached,
            accepted.field.field.isCurrent, accepted.field.selectedSegment == token.segmentKey,
            accepted.anchor.field === accepted.field, accepted.anchor.readerRecord === accepted.reader,
            accepted.anchor.readerPublication === accepted.publication,
            accepted.anchor.actual === accepted.descriptor.actual,
            accepted.descriptor.acceptedAnchor === accepted.anchor,
            accepted.anchor.actual.node?.retainedLazyListActivityStorage?.ownedCandidateDeferredAnchor
                === accepted.anchor
        else { return false }
        return true
    }

    fileprivate func canPublishSelfAcceptedChild(_ accepted: RetainedOwnedCandidateSegmentAcceptance) -> Bool {
        selfAcceptedChildLifetimeAndFactsAreCurrent(accepted) && accepted.field.isCurrent && accepted.anchor.isCurrent
    }

    fileprivate func permitsSelfAcceptedChildNormal(
        _ fact: RetainedOwnedCandidateAcceptedFact, with accepted: RetainedOwnedCandidateSegmentAcceptance
    ) -> Bool {
        guard canPublishSelfAcceptedChild(accepted), let token = accepted.construction.token,
            candidateAcceptedFacts.contains(where: { $0 === fact }), fact.actual.isAttached,
            !fact.plan.declarationOnly, selectedPlans.contains(ObjectIdentifier(fact.plan)),
            let registration = planRegistrations[ObjectIdentifier(fact.plan)],
            registration.receipt === fact.plan.receipt, registration.candidateConstruction === token,
            registrations[registration.origin.key]?.contains(where: { $0 === registration }) == true,
            fact.plan.receipt.hasDeclaredComponent,
            fact.plan.receipt.slotPermissions.allSatisfy({ $0.isDeclared && !$0.wasRevoked })
        else { return false }
        if let source = fact.source {
            // This arm covers B's ordinary body members, not a further reader C.
            if candidateChildCatalogSources[ObjectIdentifier(source)]?.normalPlan === fact.plan { return false }
            return selectedOrdinaryPlans(for: source)?.contains(where: { $0 === fact.plan }) == true
        }
        return fact.wasAcceptedEmpty && fact.plan.sourcePayloads.isEmpty
    }

    /// Validate only the stores made by the immediately preceding normal batch.
    /// The original snapshot and exact prepared/result maps are never replaced
    /// by a lookup of a later current field.
    private func selfFieldAfterNormalBatch(
        from original: RetainedOwnedCandidateFieldSnapshot,
        prepared batch: RetainedOwnedCandidateReferenceBatch,
        result: RetainedOwnedCandidateReferenceBatchResult
    ) -> RetainedOwnedCandidateFieldSnapshot? {
        guard let holder = original.selectedSegment, let previous = original.segments[holder],
            batch.field === original.field, batch.field.isCurrent,
            batch.field.incarnation === original.incarnation, original.actual.isAttached,
            batch.field.catalogRevision == original.catalogRevision,
            batch.field.segments[holder] === previous.segment, result.replacements.isEmpty,
            Set(result.accepted.keys) == Set(batch.entries.keys),
            Set(batch.existing.keys).isSubset(of: Set(batch.entries.keys)),
            batch.entries.allSatisfy({ key, intent in
                key.holder == holder && intent.holder == holder && intent.destination == holder
                    && intent.original == nil
            }),
            batch.existing.allSatisfy({ key, reference in previous.references[key.member] === reference }),
            previous.references.allSatisfy({ key, reference in
                previous.segment.references[key] === reference && reference.isCurrent
            }),
            result.accepted.allSatisfy({ key, reference in
                previous.segment.references[key.member] === reference && reference.isCurrent
                    && reference.holderSegment == holder && reference.destination == holder
                    && reference.member.identity == key.member && reference.field === batch.field
                    && (batch.existing[key] == nil || batch.existing[key] === reference)
            })
        else { return nil }
        let additions = batch.entries.keys.filter { batch.existing[$0] == nil }
        guard additions.allSatisfy({ previous.references[$0.member] == nil }),
            previous.segment.references.count == previous.references.count + additions.count
        else { return nil }
        if additions.isEmpty {
            return original.isCurrent ? original : nil
        }
        let (revision, overflow) = previous.revision.addingReportingOverflow(1)
        guard !overflow, previous.segment.revision == revision else { return nil }
        return RetainedOwnedCandidateFieldSnapshot(
            field: batch.field, actual: original.actual, selectedSegment: holder)
    }

    private func advanceSelfAcceptedBody(
        _ accepted: RetainedOwnedCandidateSelfBodyAcceptance, from original: RetainedOwnedCandidateFieldSnapshot,
        prepared batch: RetainedOwnedCandidateReferenceBatch, result: RetainedOwnedCandidateReferenceBatchResult
    ) -> Bool {
        guard accepted.field === original, selfAcceptedLifetimeAndFactsAreCurrent(accepted),
            let snapshot = selfFieldAfterNormalBatch(from: original, prepared: batch, result: result)
        else { return false }
        if snapshot === original { return true }
        let previous = accepted.anchor
        let next = RetainedOwnedCandidateDeferredAnchor(
            owner: previous.owner, reader: previous.reader, contribution: previous.contribution,
            actual: previous.actual, field: snapshot, segment: previous.segment,
            readerRecord: accepted.reader, readerPublication: accepted.readerPublication)
        previous.actual.node?.lazyListActivityStorage().ownedCandidateDeferredAnchor = next
        accepted.field = snapshot
        accepted.anchor = next
        accepted.descriptor.acceptedAnchor = next
        return true
    }

    private func advanceSelfAcceptedChildBody(
        _ accepted: RetainedOwnedCandidateSegmentAcceptance, from original: RetainedOwnedCandidateFieldSnapshot,
        prepared batch: RetainedOwnedCandidateReferenceBatch, result: RetainedOwnedCandidateReferenceBatchResult
    ) -> Bool {
        guard accepted.field === original, selfAcceptedChildLifetimeAndFactsAreCurrent(accepted),
            let snapshot = selfFieldAfterNormalBatch(from: original, prepared: batch, result: result)
        else { return false }
        if snapshot === original { return true }
        let previous = accepted.anchor
        let next = RetainedOwnedCandidateDeferredAnchor(
            owner: previous.owner, reader: previous.reader, contribution: previous.contribution,
            actual: previous.actual, field: snapshot, segment: previous.segment,
            readerRecord: accepted.reader, readerPublication: accepted.publication)
        previous.actual.node?.lazyListActivityStorage().ownedCandidateDeferredAnchor = next
        accepted.field = snapshot
        accepted.anchor = next
        accepted.descriptor.acceptedAnchor = next
        return true
    }

    private func candidateConstruction(
        _ construction: RetainedOwnedCandidateConstruction, isWithin root: RetainedOwnedCandidateConstruction
    ) -> Bool {
        var current: RetainedOwnedCandidateConstruction? = construction
        var seen: Set<ObjectIdentifier> = []
        while let token = current, seen.count < ViewNode.maximumTraversalDepth {
            guard token.owner.owner === root.owner.owner, token.qualification === root.qualification,
                seen.insert(ObjectIdentifier(token)).inserted
            else { return false }
            if token === root { return true }
            current = token.parent
        }
        return false
    }

    private func candidateChildPlans(
        for token: RetainedOwnedCandidateConstruction
    ) -> [RetainedOwnedComponentDeclarationPlan]? {
        let plans = (frozenPlans ?? []).filter { plan in
            guard selectedPlans.contains(ObjectIdentifier(plan)),
                let registration = planRegistrations[ObjectIdentifier(plan)],
                registration.receipt === plan.receipt, let construction = registration.candidateConstruction
            else { return false }
            return candidateConstruction(construction, isWithin: token)
        }
        guard
            plans.allSatisfy({ plan in
                !plan.receipt.owner.wasRevoked && plan.receipt.nativeLifetime.permitsDeclaredWrite
                    && plan.receipt.slotPermissions.allSatisfy { !$0.wasRevoked }
            })
        else { return nil }
        return plans
    }

    private func freezeCandidateChildCatalogSources() -> Bool {
        guard candidateChildCatalogSources.isEmpty, candidateChildCatalogOriginalTargets.isEmpty else { return false }
        let originals = candidateQualifications.values.flatMap { $0.childCatalogGraphs.flatMap(\.nodes) }
        for node in originals {
            guard let actual = node.actual, let target = actual.node else { continue }
            let key = ObjectIdentifier(target)
            if let previous = candidateChildCatalogOriginalTargets[key], previous !== node { return false }
            candidateChildCatalogOriginalTargets[key] = node
        }
        var frozen: [ObjectIdentifier: RetainedOwnedCandidateChildSource] = [:]
        var active: Set<ObjectIdentifier> = []
        func freeze(_ token: RetainedOwnedCandidateConstruction) -> RetainedOwnedCandidateChildSource? {
            let key = ObjectIdentifier(token)
            if let previous = frozen[key] { return previous }
            guard active.count < ViewNode.maximumTraversalDepth, active.insert(key).inserted,
                let construction = token.segmentConstruction, construction.token === token,
                let source = token.deferredSource, source.geometryReaderBuild != nil,
                source.retainedLazyListActivityStorage?.ownedCandidateDeferredSource === token,
                let plans = candidateChildPlans(for: token),
                let normalPlan = selectedOrdinaryPlans(for: source)?.first(where: {
                    !$0.declarationOnly && $0.receipt === construction.registration.receipt
                        && planRegistrations[ObjectIdentifier($0)] === construction.registration
                }), case .descriptor(let component) = normalPlan.origin,
                let scope = token.qualification.scope,
                let expectedGroup = scope.ordinaryLedger.frozenOwnedCandidateDeferredGroup(
                    component: component, source: source)
            else { return nil }
            defer { active.remove(key) }
            let known = token.qualification.childCatalogGraphs.flatMap(\.nodes).filter {
                $0.reader.field?.owner === token.owner.componentPresence
                    && $0.normalReference.member.identity == ObjectIdentifier(normalPlan.receipt.componentPresence)
            }
            var parentOriginal: RetainedOwnedCandidateAcceptedReader?
            var parentWasRefused = false
            if construction.parent.isDeferredSegment {
                if construction.parent.segmentConstruction != nil {
                    guard let parentSource = freeze(construction.parent) else { return nil }
                    switch parentSource.origin {
                    case .existing(let original): parentOriginal = original.reader
                    case .fresh: break
                    case .refused: parentWasRefused = true
                    }
                } else if let original = construction.parent.qualification.continuation,
                    construction.parent.parent == nil,
                    construction.parent.segmentOwner === original.reader
                {
                    parentOriginal = original.readerRecord
                } else {
                    parentWasRefused = true
                }
            }
            let origin: RetainedOwnedCandidateChildSource.Origin
            if parentWasRefused || known.count > 1 {
                origin = .refused
            } else if let original = known.first {
                let hasOriginalReceipt = construction.registration.previous.contains {
                    $0 === original.publication.reader
                }
                let hasOriginalParent =
                    original.reader.isRoot
                    ? !construction.parent.isDeferredSegment && parentOriginal == nil
                    : original.reader.parent === parentOriginal && parentOriginal != nil
                origin = hasOriginalReceipt && hasOriginalParent ? .existing(original) : .refused
            } else if construction.registration.previous.contains(where: { $0.hasAcceptedDeclaration }) {
                // An already accepted reader without this original graph edge is
                // not a fresh reader. In particular, cold insertion is held.
                origin = .refused
            } else {
                origin = .fresh
            }
            let result = RetainedOwnedCandidateChildSource(
                construction: construction, source: source, normalPlan: normalPlan,
                expectedGroup: expectedGroup, plans: plans, origin: origin)
            frozen[key] = result
            return result
        }
        for token in candidateSegments.values where token.segmentConstruction != nil {
            guard freeze(token) != nil else { return false }
        }
        for source in frozen.values {
            guard let node = source.source, candidateChildCatalogSources[ObjectIdentifier(node)] == nil else {
                return false
            }
            candidateChildCatalogSources[ObjectIdentifier(node)] = source
        }
        return true
    }

    fileprivate func hasOwnedCandidateChildCatalogInput(from source: ViewNode, to target: ViewNode) -> Bool {
        candidateChildCatalogSources[ObjectIdentifier(source)] != nil
            || candidateChildCatalogOriginalTargets[ObjectIdentifier(target)] != nil
            || source.retainedLazyListActivityStorage?.ownedCandidateDeferredSource?.segmentConstruction != nil
    }

    private func currentCandidateChildNode(
        _ original: RetainedOwnedCandidateCatalogNode
    ) -> RetainedOwnedCandidateCatalogNode? {
        var current = original
        var seen: Set<ObjectIdentifier> = []
        while seen.count < ViewNode.maximumTraversalDepth {
            guard seen.insert(ObjectIdentifier(current)).inserted else { return nil }
            if current.isCurrent { return current }
            guard let successor = candidateChildCatalogSuccessors[ObjectIdentifier(current)],
                successor.original === current, !successor.wasOmitted, let accepted = successor.afterimage,
                candidateChildCatalogPublications[ObjectIdentifier(successor.publication.source)]
                    === successor.publication
            else { return nil }
            current = accepted
        }
        return nil
    }

    private func candidateChildOriginalSubtree(
        _ root: RetainedOwnedCandidateCatalogNode
    ) -> [RetainedOwnedCandidateCatalogNode]? {
        var pending = [root]
        var result: [RetainedOwnedCandidateCatalogNode] = []
        var seen: Set<ObjectIdentifier> = []
        while let original = pending.popLast() {
            guard seen.count < ViewNode.maximumTraversalDepth,
                seen.insert(ObjectIdentifier(original)).inserted,
                let current = currentCandidateChildNode(original)
            else { return nil }
            result.append(current)
            pending.append(contentsOf: original.children)
        }
        return result
    }

    private func candidateChildPublicationIsCurrent(_ publication: RetainedOwnedCandidateChildPublication) -> Bool {
        guard publication.source.sourceIsCurrent, let actual = publication.original.actual,
            actual.isAttached,
            currentCandidateChildNode(publication.afterimage) != nil
        else { return false }
        for original in publication.affected {
            if let successor = candidateChildCatalogSuccessors[ObjectIdentifier(original)],
                successor.publication === publication, successor.wasOmitted
            {
                // An omission has no live afterimage and cannot make an anchor.
                guard original.normalReference.wasWithdrawn else { return false }
                continue
            }
            guard currentCandidateChildNode(original) != nil else { return false }
        }
        return true
    }

    private func prepareCandidateReaderInsertion(from source: ViewNode) -> RetainedOwnedCandidateChildSource? {
        guard let input = candidateChildCatalogSources[ObjectIdentifier(source)], input.source === source,
            case .fresh = input.origin,
            candidateChildCatalogOriginalTargets[ObjectIdentifier(source)] == nil
        else { return nil }
        guard
            input.sourceIsCurrent
                || (input.sourceAttachment.isCurrent && canHoldPendingSelfChild(input))
        else { return nil }
        // This value carries provenance inside the already prepared insertion.
        // Only that insertion's successful normal writer may deliver it.
        return input
    }

    fileprivate func applyOwnedCandidateChildCatalog(from source: ViewNode, to target: ViewNode) -> Bool {
        guard didPrepare, !wasFinished, let input = candidateChildCatalogSources[ObjectIdentifier(source)],
            input.source === source, input.sourceIsCurrent
        else { return false }
        switch input.origin {
        case .refused:
            input.wasRefused = true
            return false
        case .fresh:
            // This route is pending construction, not an accepted no-op. Its
            // first actual insertion still owes normal and descriptor facts.
            guard source === target, candidateChildCatalogOriginalTargets[ObjectIdentifier(target)] == nil else {
                input.wasRefused = true
                return false
            }
            return true
        case .existing(let original):
            guard let actual = original.actual, actual.node === target, actual.isAttached,
                candidateChildCatalogOriginalTargets[ObjectIdentifier(target)] === original
            else {
                input.wasRefused = true
                return false
            }
            if let accepted = candidateChildCatalogPublications[ObjectIdentifier(input)] {
                return accepted.source === input && accepted.original === original
                    && candidateChildPublicationIsCurrent(accepted)
            }
            guard !input.wasConsumed else { return false }
            input.wasConsumed = true
            guard original.publication.contribution.isActive,
                let affected = candidateChildOriginalSubtree(original),
                let current = currentCandidateChildNode(original),
                current.field.field === original.field.field, current.field.actual === original.field.actual,
                let readerSegment = current.reader.segment,
                current.field.field.segments[readerSegment.key] === readerSegment
            else { return false }
            // Validate every original descendant, including an empty C, before
            // observing the dependency wave that this write is allowed to remove.
            let wanted = candidateMembers(in: input.plans)
            let retired = current.field.references.filter { wanted[$0.member.identity] == nil }
            let withdrawal = RetainedOwnedCandidateWithdrawal(retired)
            guard
                withdrawal.references.allSatisfy({ reference in
                    current.dependencies.references.contains(where: { $0 === reference })
                })
            else { return false }
            let willChange = !retired.isEmpty
            guard
                !willChange
                    || RetainedOwnedCandidateRevisionCapacity.permits(
                        current: readerSegment.revision, additional: 1)
            else { return false }
            guard
                withdrawal.references.allSatisfy({ reference in
                    guard let holder = reference.field, let segment = holder.segments[reference.holderSegment],
                        segment.references[reference.member.identity] === reference
                    else { return false }
                    return RetainedOwnedCandidateRevisionCapacity.permits(current: segment.revision, additional: 1)
                })
            else { return false }
            // Pin other catalog observations affected by this exact own wave.
            // Never refresh an already stale/foreign observation.
            var observations = affected
            var observed = Set(affected.map(ObjectIdentifier.init))
            for graph in input.construction.parent.qualification.childCatalogGraphs {
                for node in graph.nodes {
                    guard let currentNode = currentCandidateChildNode(node),
                        currentNode.dependencies.references.contains(where: { reference in
                            withdrawal.references.contains(where: { $0 === reference })
                        }), observed.insert(ObjectIdentifier(currentNode)).inserted
                    else { continue }
                    observations.append(currentNode)
                }
            }
            if willChange { withdrawal.withdraw() }
            // Removal changes all original tables/edges/revisions before any
            // retirement or caller callback can observe another dependency.
            guard let afterimage = willChange ? RetainedOwnedCandidateCatalogNode(afterOwnWrite: current) : current
            else {
                withdrawal.retireUnreferencedMembers()
                return false
            }
            let publication = RetainedOwnedCandidateChildPublication(
                source: input, original: original, afterimage: afterimage, affected: affected, wasWrite: willChange)
            candidateChildCatalogPublications[ObjectIdentifier(input)] = publication
            if willChange {
                candidateChildCatalogSuccessors[ObjectIdentifier(current)] = RetainedOwnedCandidateChildSuccessor(
                    original: current, publication: publication, afterimage: afterimage, wasOmitted: false)
                for node in observations where node !== current {
                    let omitted = node.normalReference.wasWithdrawn
                    let next = omitted ? nil : RetainedOwnedCandidateCatalogNode(afterOwnWrite: node)
                    candidateChildCatalogSuccessors[ObjectIdentifier(node)] = RetainedOwnedCandidateChildSuccessor(
                        original: node, publication: publication, afterimage: next, wasOmitted: omitted)
                }
            }
            withdrawal.retireUnreferencedMembers()
            return true
        }
    }

    private func candidatePlans(for token: RetainedOwnedCandidateConstruction)
        -> [RetainedOwnedComponentDeclarationPlan]?
    {
        guard didPrepare, !wasFinished, ownsCandidateConstruction(token), token.qualification.canPublish else {
            return nil
        }
        let plans = (frozenPlans ?? []).filter { plan in
            guard selectedPlans.contains(ObjectIdentifier(plan)),
                let registration = planRegistrations[ObjectIdentifier(plan)], registration.receipt === plan.receipt,
                candidateSelfRegistrations[ObjectIdentifier(registration)] == nil,
                let construction = registration.candidateConstruction
            else { return false }
            if token.isDeferredSegment, token.qualification.continuation != nil {
                return construction.segmentKey == token.segmentKey
                    || construction.belongs(to: token.owner.owner)
                        && construction.qualification === token.qualification
            }
            return construction.belongs(to: token.owner.owner)
        }
        guard
            plans.allSatisfy({ plan in
                !plan.receipt.owner.wasRevoked && plan.receipt.nativeLifetime.permitsDeclaredWrite
                    && plan.receipt.slotPermissions.allSatisfy { !$0.wasRevoked }
            })
        else { return nil }
        return plans
    }

    private func candidateBoundaryPlan(
        for token: RetainedOwnedCandidateConstruction, source: ViewNode
    ) -> RetainedOwnedComponentDeclarationPlan? {
        guard token.boundarySource === source, source.selectedContentRole == .viewThatFits,
            source.retainedLazyListActivityStorage?.ownedCandidateBoundarySource === token,
            let exact = selectedOrdinaryPlans(for: source)
        else { return nil }
        return exact.first { !$0.declarationOnly && $0.receipt === token.owner }
    }

    private func resolvedCandidateOriginal(
        _ original: RetainedOwnedCandidateFieldSnapshot
    ) -> RetainedOwnedCandidateFieldSnapshot? {
        if original.isCurrent { return original }
        // Only a native publication that consumed THIS original in this same
        // ledger can supply its afterimage. No current-field lookup is a retry.
        guard let successor = candidateFieldSuccessors[ObjectIdentifier(original)],
            successor.original === original, successor.publication.afterimage.isCurrent,
            candidatePublications[successor.publication.write.key] === successor.publication
        else { return nil }
        return successor.publication.afterimage
    }

    private func resolvedCandidateReference(
        _ original: RetainedOwnedCandidateReference
    ) -> RetainedOwnedCandidateReference? {
        var current = original
        var seen: Set<ObjectIdentifier> = []
        while seen.count < ViewNode.maximumTraversalDepth {
            guard seen.insert(ObjectIdentifier(current)).inserted else { return nil }
            if current.isCurrent { return current }
            guard let successor = candidateReferenceSuccessors[ObjectIdentifier(current)],
                successor.original === current, successor.publication.afterimage.isCurrent,
                candidatePublications[successor.publication.write.key] === successor.publication,
                successor.accepted.declarationEdge === current.declarationEdge
            else { return nil }
            current = successor.accepted
        }
        return nil
    }

    private func incomingCandidateBoundary(
        for owner: RetainedOwnedComponentID
    ) -> RetainedOwnedCandidateConstruction? {
        guard let token = candidateBoundaries[ObjectIdentifier(owner)], let source = token.boundarySource,
            candidateBoundaryPlan(for: token, source: source) != nil
        else { return nil }
        return token
    }

    private func candidateColdSources(
        for token: RetainedOwnedCandidateConstruction, plans: [RetainedOwnedComponentDeclarationPlan]
    ) -> [RetainedOwnedCandidateCustodySource]? {
        let wanted = candidateMembers(in: plans)
        guard let originalRecipient = token.qualification.fields[ObjectIdentifier(token.owner.owner)] else { return [] }
        guard let recipient = resolvedCandidateOriginal(originalRecipient) else { return nil }
        var result: [RetainedOwnedCandidateCustodySource] = []
        var seen: Set<ObjectIdentifier> = [ObjectIdentifier(recipient.field)]
        var pending:
            [(
                field: RetainedOwnedCandidateFieldSnapshot, links: [RetainedOwnedCandidateReference],
                linkFields: [RetainedOwnedCandidateFieldSnapshot]
            )] = [
                (recipient, [], [])
            ]
        // Every hop is an original accepted component-reference object. The
        // outermost accepted receiver retains the complete intermediate lineage;
        // finding a namespace ID or a physical descendant does not supply a hop.
        while let frame = pending.popLast() {
            guard frame.links.count < ViewNode.maximumTraversalDepth else { return nil }
            for link in frame.field.references {
                guard wanted[link.member.identity] != nil, case .component(let owner) = link.member,
                    owner.owner !== token.owner.owner,
                    let original = token.qualification.fields[ObjectIdentifier(owner.owner)]
                else { continue }
                guard link.isCurrent, original.field.owner === owner,
                    seen.insert(ObjectIdentifier(original.field)).inserted,
                    let current = resolvedCandidateOriginal(original), current.selectedSegment == nil
                else { return nil }
                let links = frame.links + [link]
                let linkFields = frame.linkFields + [frame.field]
                let references = current.references.filter { wanted[$0.member.identity] != nil }
                guard references.allSatisfy(\.isCurrent) else { return nil }
                if !references.isEmpty {
                    result.append(
                        RetainedOwnedCandidateCustodySource(
                            original: current, holder: links[0].holderSegment, references: references, links: links,
                            linkFields: linkFields))
                }
                pending.append((current, links, linkFields))
            }
        }
        return result
    }

    fileprivate func prepareOwnedCandidateCatalog(
        from source: ViewNode, to target: ViewNode
    ) -> RetainedOwnedCandidateCatalogWrite? {
        guard didPrepare, !wasFinished, !source.containsRejectedRetainedSource,
            let runtime = target.retainedLazyListRuntime,
            target.isRetainedLazyListAttached(in: runtime)
        else { return nil }
        let storage = target.lazyListActivityStorage()
        let actual = storage.captureActualAttachment(of: target, in: runtime)
        let token = source.retainedLazyListActivityStorage?.ownedCandidateBoundarySource
        let key = RetainedOwnedCandidateWriteKey(
            source: ObjectIdentifier(source), target: ObjectIdentifier(target), segment: nil)
        guard !candidatePreparedWrites.contains(key), candidatePublications[key] == nil else { return nil }
        guard let token else {
            guard storage.ownedCandidateField == nil else { return nil }
            return RetainedOwnedCandidateCatalogWrite(
                ledger: self, source: source, target: target, targetActual: actual,
                token: nil, original: nil, plans: [])
        }
        guard ownsCandidateConstruction(token), token.qualification.canPublish,
            candidateBoundaryPlan(for: token, source: source) != nil,
            source.selectedContentRole == target.selectedContentRole,
            let plans = candidatePlans(for: token), candidateColdSources(for: token, plans: plans) != nil
        else { return nil }
        let original = token.qualification.fields[ObjectIdentifier(token.owner.owner)]
        if let field = storage.ownedCandidateField {
            guard let original, original.field === field, original.actual.node === target, original.isCurrent,
                original.selectedSegment == nil, field.owner === token.owner.componentPresence,
                token.owner.hasDeclaredComponent
            else { return nil }
        } else {
            // A fresh boundary acquires its field at its actual normal owner
            // publication, never merely because this preparation can name it.
            guard original == nil || original?.field.node !== target else { return nil }
        }
        if storage.ownedCandidateField != nil { candidatePreparedWrites.insert(key) }
        return RetainedOwnedCandidateCatalogWrite(
            ledger: self, source: source, target: target, targetActual: actual,
            token: token, original: original, plans: plans)
    }

    private func candidateWriteIsCurrent(_ write: RetainedOwnedCandidateCatalogWrite) -> Bool {
        guard write.ledger === self, !wasFinished, didPrepare, write.targetActual.isAttached,
            write.sourceAttachment.isCurrent, write.sourceIdentity.isCurrent,
            let source = write.source, let target = write.target, !source.containsRejectedRetainedSource,
            write.targetActual.node === target
        else { return false }
        guard let token = write.token else { return target.retainedLazyListActivityStorage?.ownedCandidateField == nil }
        guard ownsCandidateConstruction(token), token.qualification.canPublish,
            token.owner.nativeLifetime.permitsDeclaredWrite, !token.owner.owner.wasRevoked,
            write.plans.allSatisfy({
                selectedPlans.contains(ObjectIdentifier($0))
                    && planRegistrations[ObjectIdentifier($0)]?.receipt === $0.receipt
                    && !$0.receipt.owner.wasRevoked && $0.receipt.nativeLifetime.permitsDeclaredWrite
                    && $0.receipt.slotPermissions.allSatisfy { !$0.wasRevoked }
            })
        else { return false }
        if write.key.segment == nil {
            guard candidateBoundaryPlan(for: token, source: source) != nil,
                source.selectedContentRole == target.selectedContentRole
            else { return false }
        }
        if let original = write.original {
            return original.isCurrent && original.field.owner === token.owner.componentPresence
        }
        return target.retainedLazyListActivityStorage?.ownedCandidateField == nil
    }

    private func candidateMembers(
        in plans: [RetainedOwnedComponentDeclarationPlan]
    ) -> [ObjectIdentifier: RetainedOwnedPhysicalReferenceMember] {
        var result: [ObjectIdentifier: RetainedOwnedPhysicalReferenceMember] = [:]
        for plan in plans {
            let presence = RetainedOwnedPhysicalReferenceMember.component(plan.receipt.componentPresence)
            result[presence.identity] = presence
            for permission in plan.receipt.slotPermissions {
                let member = RetainedOwnedPhysicalReferenceMember.slot(permission)
                result[member.identity] = member
            }
        }
        return result
    }

    @discardableResult
    fileprivate func publishOwnedCandidateCatalog(_ write: RetainedOwnedCandidateCatalogWrite) -> Bool {
        guard !write.wasConsumed else { return false }
        write.wasConsumed = true
        guard candidateWriteIsCurrent(write) else { return false }
        guard let token = write.token else { return true }
        guard write.target?.retainedLazyListActivityStorage?.ownedCandidateField != nil,
            let original = write.original
        else {
            // No field has been accepted yet. The normal boundary publication
            // will consume exact successful member facts, including earlier ones.
            return true
        }
        let field = original.field
        guard original.actual.node === write.target, field.isCurrent else { return false }
        let selectedSegment = write.key.segment
        if selectedSegment == nil {
            guard field.catalogRevision < .max else { return false }
        }
        let oldSegments = original.segments
        guard oldSegments.values.allSatisfy({ $0.segment.revision < .max }) else { return false }
        guard let coldSources = candidateColdSources(for: token, plans: write.plans) else { return false }
        let wanted = candidateMembers(in: write.plans)
        let retired = oldSegments.values.flatMap { $0.references.values }.filter {
            wanted[$0.member.identity] == nil || !$0.isCurrent
        }
        let withdrawal = RetainedOwnedCandidateWithdrawal(retired)
        let affected = withdrawal.fields.flatMap { currentCandidatePublications(for: $0) }
        // This actual field write may only retain original accepted references.
        // New normal declarations have no authority until their own publication.
        if selectedSegment == nil { field.catalogRevision += 1 }
        for (key, snapshot) in oldSegments {
            var next: [ObjectIdentifier: RetainedOwnedCandidateReference] = [:]
            for (id, reference) in snapshot.references {
                if wanted[id] != nil, reference.isCurrent { next[id] = reference }
            }
            snapshot.segment.references = next
            snapshot.segment.revision += 1
            field.segments[key] = snapshot.segment
        }
        withdrawal.withdraw()
        guard
            let afterimage = RetainedOwnedCandidateFieldSnapshot(
                field: field, actual: write.targetActual, selectedSegment: selectedSegment)
        else {
            withdrawal.retireUnreferencedMembers()
            return false
        }
        let publication = RetainedOwnedCandidateCatalogPublication(write: write, afterimage: afterimage)
        candidatePublications[write.key] = publication
        candidateFieldSuccessors[ObjectIdentifier(original)] = RetainedOwnedCandidateFieldSuccessor(
            original: original, publication: publication)
        advanceCandidateContinuation(for: publication, replacing: original)
        for previous in affected where candidatePublications[previous.write.key] === previous {
            refreshCandidateAfterimage(previous)
        }
        stageCandidateDepartureCustody(for: publication, sources: coldSources)
        withdrawal.retireUnreferencedMembers()
        flushCandidateAcceptedFacts()
        refreshCandidateDeferredAnchors()
        return true
    }

    fileprivate func applyOwnedCandidateCatalog(from source: ViewNode, to target: ViewNode) -> Bool {
        let key = RetainedOwnedCandidateWriteKey(
            source: ObjectIdentifier(source), target: ObjectIdentifier(target), segment: nil)
        if let completed = candidatePublications[key] {
            // A recursive reconciliation pass observes the same accepted write.
            // It does not obtain or consume another field mutation permit.
            return completed.write.source === source && completed.write.target === target
                && completed.afterimage.isCurrent && completed.write.targetActual.isAttached
                && completed.write.sourceAttachment.isCurrent && completed.write.sourceIdentity.isCurrent
                && !source.containsRejectedRetainedSource
                && completed.write.token?.qualification.canPublish == true
        }
        guard let write = prepareOwnedCandidateCatalog(from: source, to: target) else { return false }
        return publishOwnedCandidateCatalog(write)
    }

    fileprivate func applyOwnedCandidateDeferredCatalog(at parent: ViewNode) -> Bool {
        guard let qualification = candidateQualifications.values.first(where: { $0.actual.node === parent }),
            let continuation = qualification.continuation, let fieldNode = continuation.field.field.node
        else { return true }
        return applyOwnedCandidateDeferredCatalog(
            qualification: qualification, continuation: continuation, fieldNode: fieldNode, at: parent)
    }

    fileprivate func originalOwnedCandidateForDirectAdoption(at parent: ViewNode)
        -> RetainedOwnedCandidateDirectOriginal
    {
        // Identity is read even after proof loss. A stale captured original must
        // never turn into the ordinary unscoped path.
        let originals = candidateQualifications.values.filter {
            $0.actual.node === parent && $0.continuation != nil
        }
        if originals.isEmpty { return .absent }
        guard originals.count == 1, let original = originals.first else { return .ambiguous }
        return .unique(original)
    }

    fileprivate func applyOriginalOwnedCandidateDeferredCatalog(
        _ qualification: RetainedOwnedCandidateScopeQualification, at parent: ViewNode
    ) -> Bool {
        guard let scope = qualification.scope, candidateQualifications[ObjectIdentifier(scope)] === qualification,
            qualification.actual.node === parent, let continuation = qualification.continuation,
            let fieldNode = continuation.field.field.node
        else { return false }
        return applyOwnedCandidateDeferredCatalog(
            qualification: qualification, continuation: continuation, fieldNode: fieldNode, at: parent)
    }

    private func applyOwnedCandidateDeferredCatalog(
        qualification: RetainedOwnedCandidateScopeQualification, continuation: RetainedOwnedCandidateDeferredAnchor,
        fieldNode: ViewNode, at parent: ViewNode
    ) -> Bool {
        let key = RetainedOwnedCandidateWriteKey(
            source: ObjectIdentifier(parent), target: ObjectIdentifier(fieldNode), segment: continuation.segment)
        if let completed = candidatePublications[key] {
            return completed.afterimage.isCurrent && completed.write.targetActual.isAttached && qualification.canPublish
        }
        guard qualification.canPublish, let token = candidateSegments[continuation.segment],
            let plans = candidatePlans(for: token), continuation.field.isCurrent
        else { return false }
        let write = RetainedOwnedCandidateCatalogWrite(
            ledger: self, source: parent, target: fieldNode, targetActual: continuation.field.actual,
            token: token, original: continuation.field, plans: plans, segment: continuation.segment)
        guard !candidatePreparedWrites.contains(write.key) else { return false }
        candidatePreparedWrites.insert(write.key)
        return publishOwnedCandidateCatalog(write)
    }

    private func refreshCandidateAfterimage(_ publication: RetainedOwnedCandidateCatalogPublication) {
        let previous = publication.afterimage
        guard
            let next = RetainedOwnedCandidateFieldSnapshot(
                field: previous.field, actual: previous.actual, selectedSegment: previous.selectedSegment)
        else { return }
        publication.afterimage = next
        candidateFieldSuccessors[ObjectIdentifier(previous)] = RetainedOwnedCandidateFieldSuccessor(
            original: previous, publication: publication)
        advanceCandidateContinuation(for: publication, replacing: previous)
    }

    private func advanceCandidateContinuation(
        for publication: RetainedOwnedCandidateCatalogPublication,
        replacing previous: RetainedOwnedCandidateFieldSnapshot
    ) {
        guard let qualification = publication.write.token?.qualification,
            let original = qualification.currentContinuation, original.field === previous,
            publication.afterimage.selectedSegment == original.segment, publication.afterimage.isCurrent,
            original.actual.isAttached, original.contribution.isActive,
            original.owner.hasDeclaredComponent, original.reader.hasDeclaredComponent,
            let node = original.actual.node,
            node.retainedLazyListActivityStorage?.ownedCandidateDeferredAnchor === original
        else { return }
        let successor = RetainedOwnedCandidateDeferredAnchor(
            owner: original.owner, reader: original.reader, contribution: original.contribution,
            actual: original.actual, field: publication.afterimage, segment: original.segment,
            readerRecord: original.readerRecord, readerPublication: original.readerPublication)
        node.lazyListActivityStorage().ownedCandidateDeferredAnchor = successor
        qualification.continuationAfterimage = successor
    }

    private func currentCandidatePublications(
        for field: RetainedOwnedCandidateField
    ) -> [RetainedOwnedCandidateCatalogPublication] {
        candidatePublications.values.filter { $0.afterimage.field === field && $0.afterimage.isCurrent }
    }

    private func prepareCandidateReferenceBatch(
        _ intents: [RetainedOwnedCandidateReferenceIntent], on field: RetainedOwnedCandidateField,
        normal: RetainedOwnedCandidateNormalMemberProof? = nil
    ) -> RetainedOwnedCandidateReferenceBatch? {
        if let normal {
            guard normal.isCurrent, normal.field.field === field,
                planRegistrations[ObjectIdentifier(normal.fact.plan)]?.candidateConstruction === normal.token,
                selectedPlans.contains(ObjectIdentifier(normal.fact.plan)), ownsCandidateConstruction(normal.token)
            else { return nil }
        }
        var entries: [RetainedOwnedCandidateReferenceKey: RetainedOwnedCandidateReferenceIntent] = [:]
        var existing: [RetainedOwnedCandidateReferenceKey: RetainedOwnedCandidateReference] = [:]
        var changedSegments: Set<RetainedOwnedCandidateSegmentKey> = []
        var memberHolders: [ObjectIdentifier: RetainedOwnedCandidateSegmentKey] = [:]
        for intent in intents {
            guard intent.member.isCurrentCandidateMember, intent.returnPath.first == intent.holder,
                intent.returnPath.last == intent.destination,
                Set(intent.returnPath.map(\.namespace)).count == intent.returnPath.count,
                Set(intent.lineage.map(ObjectIdentifier.init)).count == intent.lineage.count
            else { return nil }
            if let original = intent.original {
                guard original.member.identity == intent.member.identity, original.isCurrent,
                    intent.lineage.allSatisfy({ edge in
                        !edge.isClosed && edge !== original.declarationEdge
                            && edge.currentReference?.hasCurrentLineage(excluding: original.declarationEdge) == true
                    })
                else { return nil }
            } else {
                guard intent.returnPath == [intent.holder] else { return nil }
                if !intent.lineage.isEmpty {
                    guard let normal, let reader = normal.reader, reader.isDeclared,
                        intent.holder == normal.token.segmentKey, intent.destination == intent.holder,
                        intent.lineage.count == 1, intent.lineage[0] === reader.normalReference.declarationEdge,
                        intent.member.identity != reader.normalReference.member.identity,
                        candidateMembers(in: [normal.fact.plan])[intent.member.identity] != nil
                    else { return nil }
                }
            }
            if let previous = entries[intent.key] {
                guard previous.destination == intent.destination, previous.original === intent.original,
                    previous.returnPath == intent.returnPath,
                    previous.lineage.elementsEqual(intent.lineage, by: { $0 === $1 })
                else { return nil }
            }
            if let holder = memberHolders[intent.member.identity], holder != intent.holder { return nil }
            memberHolders[intent.member.identity] = intent.holder
            for (key, segment) in field.segments where key != intent.holder {
                if segment.references[intent.member.identity] != nil { return nil }
            }
            entries[intent.key] = intent
            if let reference = field.segments[intent.holder]?.references[intent.member.identity] {
                guard reference.isCurrent, reference.destination == intent.destination,
                    reference.returnPath == intent.returnPath,
                    reference.lineage.elementsEqual(intent.lineage, by: { $0 === $1 }),
                    intent.original == nil || intent.original === reference
                else { return nil }
                existing[intent.key] = reference
            } else {
                changedSegments.insert(intent.holder)
            }
        }
        var proposedLineage: [ObjectIdentifier: [RetainedOwnedCandidateDeclarationEdge]] = [:]
        for intent in entries.values {
            if let original = intent.original {
                proposedLineage[ObjectIdentifier(original.declarationEdge)] = intent.lineage
            }
        }
        for intent in entries.values {
            guard let original = intent.original else { continue }
            var pending: [(edge: RetainedOwnedCandidateDeclarationEdge, leaving: Bool)] = [
                (original.declarationEdge, false)
            ]
            var active: Set<ObjectIdentifier> = []
            var complete: Set<ObjectIdentifier> = []
            while let step = pending.popLast() {
                let identity = ObjectIdentifier(step.edge)
                if step.leaving {
                    active.remove(identity)
                    complete.insert(identity)
                    continue
                }
                if complete.contains(identity) { continue }
                guard !step.edge.isClosed, complete.count + active.count < ViewNode.maximumTraversalDepth,
                    active.insert(identity).inserted, let current = step.edge.currentReference
                else { return nil }
                pending.append((step.edge, true))
                for edge in proposedLineage[identity] ?? current.lineage {
                    guard !active.contains(ObjectIdentifier(edge)) else { return nil }
                    pending.append((edge, false))
                }
            }
        }
        guard
            changedSegments.allSatisfy({
                RetainedOwnedCandidateRevisionCapacity.permits(
                    current: field.segments[$0]?.revision ?? 0, additional: 1)
            })
        else { return nil }
        return RetainedOwnedCandidateReferenceBatch(field: field, entries: entries, existing: existing)
    }

    /// Called immediately after full native preflight, with no intervening
    /// callback. Every reference is installed before any donor is withdrawn.
    private func publishCandidateReferenceBatch(
        _ batch: RetainedOwnedCandidateReferenceBatch
    ) -> RetainedOwnedCandidateReferenceBatchResult {
        var accepted: [(intent: RetainedOwnedCandidateReferenceIntent, reference: RetainedOwnedCandidateReference)] = []
        var changed: [RetainedOwnedCandidateSegmentKey: RetainedOwnedCandidateSegment] = [:]
        for (key, intent) in batch.entries where batch.existing[key] == nil {
            let segment =
                changed[intent.holder] ?? batch.field.segments[intent.holder]
                ?? RetainedOwnedCandidateSegment(key: intent.holder)
            let reference = RetainedOwnedCandidateReference(
                member: intent.member, destination: intent.destination, holderSegment: intent.holder,
                field: batch.field,
                original: intent.original, lineage: intent.lineage, returnPath: intent.returnPath)
            segment.references[intent.member.identity] = reference
            changed[intent.holder] = segment
            accepted.append((intent, reference))
        }
        for (key, segment) in changed {
            segment.revision += 1
            batch.field.segments[key] = segment
        }
        var replacements: [(original: RetainedOwnedCandidateReference, accepted: RetainedOwnedCandidateReference)] = []
        for entry in accepted {
            if let original = entry.intent.original,
                entry.reference.declarationEdge === original.declarationEdge,
                original.declarationEdge.currentReference === original
            {
                // The continued edge survives, but its original reader record
                // cannot follow a different reference into a new custodian.
                original.declarationEdge.acceptedReader?.removeOriginalDeclaration(original)
            }
            entry.reference.declarationEdge.currentReference = entry.reference
            entry.reference.member.index.candidateReferences[ObjectIdentifier(entry.reference)] =
                RetainedOwnedWeakCandidateReference(entry.reference)
            for edge in entry.reference.lineage {
                edge.dependents[ObjectIdentifier(entry.reference)] = RetainedOwnedWeakCandidateReference(
                    entry.reference)
            }
            if let original = entry.intent.original { replacements.append((original, entry.reference)) }
        }
        var references = batch.existing
        for entry in accepted { references[entry.intent.key] = entry.reference }
        return RetainedOwnedCandidateReferenceBatchResult(replacements: replacements, accepted: references)
    }

    private func recordCandidateReferenceSuccessors(
        _ result: RetainedOwnedCandidateReferenceBatchResult, publication: RetainedOwnedCandidateCatalogPublication
    ) {
        for pair in result.replacements {
            candidateReferenceSuccessors[ObjectIdentifier(pair.original)] = RetainedOwnedCandidateReferenceSuccessor(
                original: pair.original, accepted: pair.accepted, publication: publication)
        }
    }

    private func candidateCustodyIntent(
        for reference: RetainedOwnedCandidateReference, source: RetainedOwnedCandidateCustodySource,
        links: [RetainedOwnedCandidateReference]
    ) -> RetainedOwnedCandidateReferenceIntent {
        var lineage: [RetainedOwnedCandidateDeclarationEdge] = []
        var seen: Set<ObjectIdentifier> = []
        for edge in links.flatMap({ $0.lineage + [$0.declarationEdge] }) + reference.lineage
        where seen.insert(ObjectIdentifier(edge)).inserted { lineage.append(edge) }
        return RetainedOwnedCandidateReferenceIntent(
            member: reference.member, holder: source.holder, destination: reference.destination, original: reference,
            lineage: lineage, returnPath: source.links.flatMap(\.returnPath) + reference.returnPath)
    }

    private func candidateReturnIntent(
        for reference: RetainedOwnedCandidateReference, namespace: RetainedOwnedComponentID
    ) -> RetainedOwnedCandidateReferenceIntent? {
        guard let index = reference.returnPath.firstIndex(where: { $0.namespace == ObjectIdentifier(namespace) })
        else { return nil }
        let path = Array(reference.returnPath[index...])
        let namespaces = Set(path.map(\.namespace))
        return RetainedOwnedCandidateReferenceIntent(
            member: reference.member, holder: path[0], destination: reference.destination, original: reference,
            lineage: reference.lineage.filter { namespaces.contains($0.declaringSegment.namespace) }, returnPath: path)
    }

    private func stageCandidateDepartureCustody(
        for publication: RetainedOwnedCandidateCatalogPublication, sources: [RetainedOwnedCandidateCustodySource]
    ) {
        for source in sources {
            guard source.original.isCurrent, source.links.allSatisfy(\.isCurrent),
                publication.afterimage.isCurrent, source.original.field !== publication.afterimage.field
            else { continue }
            // This attempt cannot replace its earlier captured receiver. A new
            // independently qualified catalog may replace an older attempt.
            if source.original.field.departureCustody?.ledger === self { continue }
            let pending = RetainedOwnedCandidateDepartureCustody(ledger: self, source: source, receiver: publication)
            candidateDepartureCustody.append(pending)
            source.original.field.departureCustody = pending
        }
    }

    fileprivate func consumeCandidateDepartureCustody(
        _ pending: RetainedOwnedCandidateDepartureCustody, from originalField: RetainedOwnedCandidateField
    ) {
        guard !pending.wasConsumed else { return }
        pending.wasConsumed = true
        guard originalField.departureCustody === pending else { return }
        originalField.departureCustody = nil
        let receiver = pending.receiver
        let source = pending.source
        guard pending.ledger === self, !wasFinished, didPrepare,
            candidateDepartureCustody.contains(where: { $0 === pending }),
            source.original.field === originalField,
            resolvedCandidateOriginal(source.original)?.field === originalField,
            source.references.allSatisfy(\.isCurrent),
            receiver.afterimage.isCurrent, receiver.afterimage.field !== originalField,
            let token = receiver.write.token, ownsCandidateConstruction(token), token.qualification.canPublish,
            candidatePublications[receiver.write.key] === receiver
        else { return }
        guard source.links.count == source.linkFields.count else { return }
        var links: [RetainedOwnedCandidateReference] = []
        for (link, original) in zip(source.links, source.linkFields) {
            if candidateReferenceSuccessors[ObjectIdentifier(link)] == nil {
                guard let current = resolvedCandidateOriginal(original),
                    current.references.contains(where: { $0 === link })
                else { return }
            }
            guard let current = resolvedCandidateReference(link) else { return }
            links.append(current)
        }
        let intents = source.references.map { candidateCustodyIntent(for: $0, source: source, links: links) }
        guard let batch = prepareCandidateReferenceBatch(intents, on: receiver.afterimage.field) else { return }
        let accepted = publishCandidateReferenceBatch(batch)
        refreshCandidateAfterimage(receiver)
        recordCandidateReferenceSuccessors(accepted, publication: receiver)
        candidateAcceptedCustody.append(
            RetainedOwnedCandidateAcceptedCustody(
                source: source.original, receiver: receiver, mapping: accepted.replacements))
    }

    private func establishCandidateField(
        token: RetainedOwnedCandidateConstruction, plan: RetainedOwnedComponentDeclarationPlan,
        source: ViewNode, actual: RetainedLazyListActualAttachment
    ) {
        guard plan.receipt === token.owner, !plan.declarationOnly, token.boundarySource === source,
            candidateBoundaryPlan(for: token, source: source) === plan, token.qualification.canPublish,
            actual.isAttached, let target = actual.node, let storage = target.retainedLazyListActivityStorage,
            target.selectedContentRole == .viewThatFits, token.owner.hasDeclaredComponent,
            token.owner.owner.nativePresence === token.owner.componentPresence,
            let plans = candidatePlans(for: token)
        else { return }
        if let current = storage.ownedCandidateField {
            guard current.owner === token.owner.componentPresence, current.isCurrent else { return }
            return
        }
        guard candidateBoundaryActivationAttempts.insert(ObjectIdentifier(token)).inserted else { return }

        var donor: RetainedOwnedCandidateFieldSnapshot?
        if let previous = token.owner.componentPresence.ownedCandidateField {
            guard let original = token.qualification.fields[ObjectIdentifier(token.owner.owner)],
                let current = resolvedCandidateOriginal(original), current.field === previous,
                current.selectedSegment == nil
            else { return }
            donor = current
        }
        // Returning from cold custody has no live old inner field. Retain the
        // exact accepted outer references until this actual inner publication.
        let wanted = candidateMembers(in: plans)
        var custody: [RetainedOwnedCandidateReference] = []
        var seenCustody: Set<ObjectIdentifier> = []
        for original in token.qualification.fields.values where original.field.owner.owner !== token.owner.owner {
            let captured = original.references.filter {
                $0.returnPath.contains(where: { $0.namespace == ObjectIdentifier(token.owner.owner) })
            }
            guard !captured.isEmpty else { continue }
            let current = resolvedCandidateOriginal(original)
            for old in captured {
                if candidateReferenceSuccessors[ObjectIdentifier(old)] == nil {
                    guard let current else { return }
                    // Only this original or its own native field successor can
                    // prove an omission. No matching member ID is rediscovered.
                    if !current.references.contains(where: { $0 === old }) { continue }
                }
                guard let reference = resolvedCandidateReference(old),
                    reference.returnPath.contains(where: { $0.namespace == ObjectIdentifier(token.owner.owner) })
                else { return }
                if seenCustody.insert(ObjectIdentifier(reference)).inserted { custody.append(reference) }
            }
        }
        let returned = candidateAcceptedCustody.filter {
            !$0.returnWasConsumed && $0.source.field.owner === token.owner.componentPresence
                && $0.receiver.write.token?.qualification === token.qualification
        }
        for receipt in returned { receipt.returnWasConsumed = true }
        guard donor?.isCurrent != false, returned.allSatisfy({ $0.receiver.afterimage.isCurrent })
        else { return }
        for receipt in returned {
            for mapping in receipt.mapping {
                if candidateReferenceSuccessors[ObjectIdentifier(mapping.accepted)] == nil,
                    !receipt.receiver.afterimage.references.contains(where: { $0 === mapping.accepted })
                {
                    continue
                }
                guard let reference = resolvedCandidateReference(mapping.accepted),
                    reference.returnPath.contains(where: { $0.namespace == ObjectIdentifier(token.owner.owner) })
                else { return }
                if seenCustody.insert(ObjectIdentifier(reference)).inserted { custody.append(reference) }
            }
        }

        let field = RetainedOwnedCandidateField(owner: token.owner.componentPresence, actual: actual)
        var intents: [RetainedOwnedCandidateReferenceIntent] = []
        if let donor {
            for reference in donor.references where wanted[reference.member.identity] != nil {
                intents.append(
                    RetainedOwnedCandidateReferenceIntent(
                        member: reference.member, holder: reference.holderSegment, destination: reference.destination,
                        original: reference, lineage: reference.lineage, returnPath: reference.returnPath))
            }
        }
        var removals: [(field: RetainedOwnedCandidateField, reference: RetainedOwnedCandidateReference)] = []
        for reference in custody {
            guard let holder = reference.field, reference.isCurrent else { return }
            if wanted[reference.member.identity] != nil {
                guard let intent = candidateReturnIntent(for: reference, namespace: token.owner.owner) else { return }
                intents.append(intent)
            }
            removals.append((holder, reference))
        }
        guard let batch = prepareCandidateReferenceBatch(intents, on: field) else { return }
        for (holder, reference) in removals {
            guard holder.isCurrent, reference.isCurrent,
                let segment = holder.segments[reference.holderSegment],
                segment.references[reference.member.identity] === reference,
                RetainedOwnedCandidateRevisionCapacity.permits(current: segment.revision, additional: 1)
            else { return }
        }

        // Both receiver additions and every captured donor removal passed
        // preflight. No callback or fallible member installation intervenes.
        storage.ownedCandidateField = field
        token.owner.componentPresence.ownedCandidateField = field
        field.segments[token.segmentKey] = RetainedOwnedCandidateSegment(key: token.segmentKey)
        let accepted = publishCandidateReferenceBatch(batch)
        let departing = (donor?.field.takeOriginalReferencesForWithdrawal() ?? []) + removals.map(\.reference)
        let withdrawal = RetainedOwnedCandidateWithdrawal(departing)
        let affected = withdrawal.fields.flatMap { currentCandidatePublications(for: $0) }
        withdrawal.withdraw()
        let write = RetainedOwnedCandidateCatalogWrite(
            ledger: self, source: source, target: target, targetActual: actual,
            token: token, original: donor, plans: plans)
        write.wasConsumed = true
        guard let afterimage = RetainedOwnedCandidateFieldSnapshot(field: field, actual: actual) else {
            withdrawal.retireUnreferencedMembers()
            return
        }
        let publication = RetainedOwnedCandidateCatalogPublication(write: write, afterimage: afterimage)
        candidatePublications[write.key] = publication
        if let donor {
            candidateFieldSuccessors[ObjectIdentifier(donor)] = RetainedOwnedCandidateFieldSuccessor(
                original: donor, publication: publication)
        }
        recordCandidateReferenceSuccessors(accepted, publication: publication)
        for existing in affected where candidatePublications[existing.write.key] === existing {
            refreshCandidateAfterimage(existing)
        }
        withdrawal.retireUnreferencedMembers()
    }

    fileprivate func recordCandidateAcceptedFacts(
        _ plans: [RetainedOwnedComponentDeclarationPlan], source: ViewNode?,
        actual: RetainedLazyListActualAttachment, acceptedEmpty: RetainedDescriptorAcceptedEmptyGroup? = nil,
        insertedReader: RetainedOwnedCandidateChildSource? = nil
    ) {
        guard !wasFinished, didPrepare, actual.isAttached else { return }
        for plan in plans where !plan.declarationOnly && selectedPlans.contains(ObjectIdentifier(plan)) {
            guard let registration = planRegistrations[ObjectIdentifier(plan)], registration.receipt === plan.receipt,
                plan.receipt.hasDeclaredComponent,
                plan.receipt.slotPermissions.allSatisfy({ $0.isDeclared && !$0.wasRevoked })
            else { continue }
            if let acceptedEmpty {
                guard case .descriptor(let component) = plan.origin,
                    component === acceptedEmpty.proposal.component,
                    acceptedEmpty.structuralAnchor === actual, plan.sourcePayloads.isEmpty,
                    registration.candidateConstruction != nil
                else { continue }
            } else {
                guard let source, !source.containsRejectedRetainedSource,
                    let sourcePlans = selectedOrdinaryPlans(for: source), sourcePlans.contains(where: { $0 === plan })
                else { continue }
            }
            if let input = candidateSelfRegistrations[ObjectIdentifier(registration)] {
                // The reader's own normal receipt belongs to its original parent
                // segment. Never insert an A component reference into A's body.
                guard let source, let target = actual.node, input.source === source, input.plan === plan,
                    let publication = preparedCandidateSelfPublication(from: source, to: target),
                    publication.input === input, canFinishCandidateSelf(publication),
                    actual.target === publication.originalAnchor.actual.target,
                    actual.attachment === publication.originalAnchor.actual.attachment
                else { continue }
                if publication.normal == nil {
                    publication.normal = RetainedOwnedCandidateAcceptedFact(
                        plan: plan, actual: actual, source: source, wasAcceptedEmpty: false, insertedReader: nil)
                }
                continue
            }
            if candidateAcceptedFacts.contains(where: {
                $0.plan === plan && $0.source === source && $0.actual.target === actual.target
                    && $0.actual.attachment === actual.attachment && $0.wasAcceptedEmpty == (acceptedEmpty != nil)
            }) {
                continue
            }
            if let source, let child = candidateChildCatalogSources[ObjectIdentifier(source)],
                child.normalPlan === plan
            {
                guard !candidateChildCatalogDenies(child, actual: actual) else { continue }
                if case .fresh = child.origin {
                    guard insertedReader === child, actual.node === source else { continue }
                }
            }
            candidateAcceptedFacts.append(
                RetainedOwnedCandidateAcceptedFact(
                    plan: plan, actual: actual, source: source, wasAcceptedEmpty: acceptedEmpty != nil,
                    insertedReader: insertedReader?.normalPlan === plan ? insertedReader : nil))
            if let source, let token = source.retainedLazyListActivityStorage?.ownedCandidateBoundarySource,
                token.owner === plan.receipt
            {
                establishCandidateField(token: token, plan: plan, source: source, actual: actual)
            }
        }
        flushCandidateAcceptedFacts()
        refreshCandidateDeferredAnchors()
    }

    private func flushCandidateAcceptedFacts() {
        guard !isDrainingCandidateFacts, !wasFinished else { return }
        isDrainingCandidateFacts = true
        defer { isDrainingCandidateFacts = false }
        // Native facts may arrive children-first. Every successful pass consumes
        // a normal fact or joins a reader once; no polling or callback is used.
        var progressed = true
        var remaining = candidateAcceptedFacts.count + candidateDeferredFacts.count + 1
        while progressed && remaining > 0 {
            progressed = false
            remaining -= 1
            for fact in candidateAcceptedFacts where fact.acceptedReferences == nil {
                guard let proof = candidateNormalMemberProof(for: fact) else { continue }
                let field = proof.field.field
                let members = candidateMembers(in: [fact.plan])
                let lineage = proof.reader.map { [$0.normalReference.declarationEdge] } ?? []
                let intents = members.values.map {
                    RetainedOwnedCandidateReferenceIntent(
                        member: $0, holder: proof.token.segmentKey, destination: proof.token.segmentKey,
                        lineage: lineage)
                }
                guard let batch = prepareCandidateReferenceBatch(intents, on: field, normal: proof) else { continue }
                let usesSelfAcceptance = proof.selfAcceptance != nil || proof.acceptance?.selfParent != nil
                let publications = usesSelfAcceptance ? [] : currentCandidatePublications(for: field)
                let readers =
                    usesSelfAcceptance
                    ? [] : candidateAcceptedSegments.values.filter { $0.field.field === field && $0.isCurrent }
                let accepted = publishCandidateReferenceBatch(batch)
                fact.acceptedReferences = Dictionary(
                    uniqueKeysWithValues: accepted.accepted.map { ($0.key.member, $0.value) })
                fact.acceptedParentReader = proof.reader
                if let selfAcceptance = proof.selfAcceptance {
                    if !advanceSelfAcceptedBody(selfAcceptance, from: proof.field, prepared: batch, result: accepted) {
                        // The actual accepted references remain accepted. Only
                        // this narrow record is refused; no retry or repair.
                        selfAcceptance.wasRefused = true
                    }
                } else if let reader = proof.acceptance, reader.selfParent != nil {
                    if !advanceSelfAcceptedChildBody(reader, from: proof.field, prepared: batch, result: accepted) {
                        reader.selfWasRefused = true
                    }
                } else {
                    for publication in publications where !publication.afterimage.isCurrent {
                        refreshCandidateAfterimage(publication)
                    }
                    for reader in readers where !reader.field.isCurrent { advanceAcceptedCandidateReader(reader) }
                }
                progressed = true
            }
            for fact in candidateDeferredFacts where fact.acceptedAnchor == nil {
                if acceptCandidateDeferredFact(fact) { progressed = true }
            }
        }
    }

    private func candidateNormalMemberProof(
        for fact: RetainedOwnedCandidateAcceptedFact
    ) -> RetainedOwnedCandidateNormalMemberProof? {
        let plan = fact.plan
        guard fact.actual.isAttached, let registration = planRegistrations[ObjectIdentifier(plan)],
            registration.receipt === plan.receipt, let token = registration.candidateConstruction,
            ownsCandidateConstruction(token),
            let field = token.owner.componentPresence.ownedCandidateField,
            field.isCurrent, field.owner === token.owner.componentPresence
        else { return nil }
        if let source = fact.source, let child = candidateChildCatalogSources[ObjectIdentifier(source)],
            child.normalPlan === plan, candidateChildCatalogDenies(child, actual: fact.actual)
        {
            return nil
        }
        if let accepted = candidateSelfBodyAcceptance(for: token) {
            let proof = RetainedOwnedCandidateNormalMemberProof(
                fact: fact, token: token, field: accepted.field, publication: nil,
                acceptance: nil, selfAcceptance: accepted, reader: accepted.reader)
            return proof.isCurrent ? proof : nil
        }
        if let accepted = candidateAcceptedSegments[ObjectIdentifier(token)] {
            let proof = RetainedOwnedCandidateNormalMemberProof(
                fact: fact, token: token, field: accepted.field, publication: nil,
                acceptance: accepted, selfAcceptance: nil, reader: accepted.reader)
            return proof.isCurrent ? proof : nil
        }
        // Body members of a newly constructed B wait for B's independent normal
        // component-reference and descriptor-group facts. Child catalog history
        // never makes this branch eligible.
        guard token.qualification.canPublish, token.segmentConstruction == nil, token.selfConstruction == nil else {
            return nil
        }
        let publications = currentCandidatePublications(for: field)
        guard
            let publication = publications.first(where: {
                $0.write.token?.qualification === token.qualification
                    && $0.write.plans.contains(where: { $0 === plan })
                    && ($0.afterimage.selectedSegment == nil || $0.afterimage.selectedSegment == token.segmentKey)
            })
        else { return nil }
        let reader = token.isDeferredSegment ? token.qualification.currentContinuation?.readerRecord : nil
        let proof = RetainedOwnedCandidateNormalMemberProof(
            fact: fact, token: token, field: publication.afterimage, publication: publication,
            acceptance: nil, selfAcceptance: nil, reader: reader)
        return proof.isCurrent ? proof : nil
    }

    /// This is solely a negative check. It neither returns a child afterimage nor
    /// supplies a normal reference, group, field-birth or task permission.
    private func candidateChildCatalogDenies(
        _ input: RetainedOwnedCandidateChildSource, actual: RetainedLazyListActualAttachment
    ) -> Bool {
        guard input.sourceBindingsAreCurrent, let source = input.source, actual.isAttached,
            let token = input.construction.token, ownsCandidateConstruction(token)
        else {
            input.wasRefused = true
            return true
        }
        guard token.qualification.canPublish || canHoldPendingSelfChild(input) else {
            input.wasRefused = true
            return true
        }
        switch input.origin {
        case .refused:
            input.wasRefused = true
            return true
        case .fresh:
            // The successful insertion fact, checked separately, is mandatory.
            // A missing original detached proof cannot be recaptured here.
            guard actual.node === source else {
                input.wasRefused = true
                return true
            }
            return false
        case .existing(let original):
            guard let originalActual = original.actual, actual.node === originalActual.node,
                actual.target === originalActual.target, actual.attachment === originalActual.attachment,
                let publication = candidateChildCatalogPublications[ObjectIdentifier(input)],
                publication.source === input, publication.original === original,
                candidateChildPublicationIsCurrent(publication)
            else {
                input.wasRefused = true
                return true
            }
            return false
        }
    }

    fileprivate func recordCandidateDeferredAcceptance(
        source: ViewNode, actual: RetainedLazyListActualAttachment,
        contribution: RetainedDescriptorContributionReceipt
    ) {
        if let input = candidateSelfSources[ObjectIdentifier(source)] {
            guard input.source === source, contribution === input.expectedGroup,
                let target = actual.node,
                let publication = preparedCandidateSelfPublication(from: source, to: target),
                publication.input === input, actual.isAttached,
                actual.target === publication.originalAnchor.actual.target,
                actual.attachment === publication.originalAnchor.actual.attachment,
                let token = input.construction.token, contribution.isActive,
                let installed = target.retainedLazyListActivityStorage?.descriptorDeferredSubtreeAnchor,
                installed.contribution === contribution, installed.actual === actual
            else { return }
            if publication.descriptor == nil {
                publication.descriptor = RetainedOwnedCandidateDeferredFact(
                    source: source, token: token, actual: actual, contribution: contribution,
                    previousAnchor: target.retainedLazyListActivityStorage?.ownedCandidateDeferredAnchor)
            }
            // The ordinary group writer may run before this journal drains the
            // original absence. Only the later fixed drain tail may finish SELF.
            return
        }
        if source.retainedLazyListActivityStorage?.ownedCandidateDeferredSource?.selfConstruction != nil { return }
        if let input = candidateChildCatalogSources[ObjectIdentifier(source)] {
            guard input.source === source, input.expectedGroup === contribution else { return }
        }
        guard let token = source.retainedLazyListActivityStorage?.ownedCandidateDeferredSource,
            ownsCandidateConstruction(token), token.deferredSource === source,
            actual.isAttached, contribution.isActive, let target = actual.node,
            let descriptorAnchor = target.retainedLazyListActivityStorage?.descriptorDeferredSubtreeAnchor,
            descriptorAnchor.contribution === contribution, descriptorAnchor.actual === actual
        else { return }
        if candidateDeferredFacts.contains(where: {
            $0.source === source && $0.actual === actual && $0.contribution === contribution
        }) {
            return
        }
        let fact = RetainedOwnedCandidateDeferredFact(
            source: source, token: token, actual: actual, contribution: contribution,
            previousAnchor: target.retainedLazyListActivityStorage?.ownedCandidateDeferredAnchor)
        candidateDeferredFacts.append(fact)
        if let input = candidateChildCatalogSources[ObjectIdentifier(source)],
            candidateChildCatalogDenies(input, actual: actual)
        {
            return
        }
        flushCandidateAcceptedFacts()
    }

    @discardableResult
    private func acceptCandidateDeferredFact(_ fact: RetainedOwnedCandidateDeferredFact) -> Bool {
        let token = fact.token
        guard fact.acceptedAnchor == nil, fact.descriptorFactIsCurrent,
            let source = fact.source, ownsCandidateConstruction(token), token.deferredSource === source,
            let construction = token.segmentConstruction,
            let input = candidateChildCatalogSources[ObjectIdentifier(source)], input.construction === construction,
            fact.contribution === input.expectedGroup,
            let target = fact.actual.node,
            target.retainedLazyListActivityStorage?.ownedCandidateDeferredAnchor === fact.previousAnchor,
            let field = token.owner.componentPresence.ownedCandidateField,
            field.isCurrent, token.segmentOwner.hasDeclaredComponent,
            let normal = candidateAcceptedFacts.first(where: {
                $0.plan === input.normalPlan && $0.plan.receipt === construction.registration.receipt
                    && $0.source === source
                    && $0.actual.target === fact.actual.target && $0.actual.attachment === fact.actual.attachment
                    && $0.actual.isAttached && $0.acceptedReferences != nil
            }),
            let normalReference = normal.acceptedReferences?[
                ObjectIdentifier(construction.registration.receipt.componentPresence)],
            case .component(let presence) = normalReference.member,
            presence === construction.registration.receipt.componentPresence, normalReference.isCurrent,
            !candidateChildCatalogDenies(input, actual: fact.actual)
        else { return false }
        let selfParent: RetainedOwnedCandidateSelfBodyAcceptance?
        if construction.parent.selfConstruction != nil {
            guard originalSelfParent(of: input) === construction.parent,
                let accepted = candidateSelfBodyAcceptance(for: construction.parent)
            else { return false }
            selfParent = accepted
        } else {
            guard token.qualification.canPublish else { return false }
            selfParent = nil
        }
        let parent = normal.acceptedParentReader
        if construction.parent.isDeferredSegment {
            guard let parent, parent.isDeclared, parent.field === field,
                let parentSegment = parent.segment, field.segments[parentSegment.key] === parentSegment,
                parentSegment.key == construction.parent.segmentKey,
                normalReference.lineage.contains(where: { $0 === parent.normalReference.declarationEdge })
            else { return false }
        } else if parent != nil || !normalReference.lineage.isEmpty {
            return false
        }
        let originalReader: RetainedOwnedCandidateAcceptedReader?
        switch input.origin {
        case .fresh:
            guard normal.insertedReader === input, normal.actual.node === source,
                normalReference.declarationEdge.acceptedReader == nil,
                field.segments[token.segmentKey]?.acceptedReader == nil
            else { return false }
            originalReader = nil
        case .existing(let original):
            guard original.reader.isDeclared, original.reader.normalReference === normalReference,
                original.reader.parent === parent, original.reader.field === field,
                original.reader.publication === original.publication,
                construction.registration.previous.contains(where: { $0 === original.publication.reader })
            else { return false }
            originalReader = original.reader
        case .refused:
            return false
        }
        // Revalidate after pending facts have been joined. None of the following
        // callback-free stores can turn a catalog-only result into permission.
        guard !candidateChildCatalogDenies(input, actual: fact.actual), fact.descriptorFactIsCurrent,
            normal.actual.isAttached, normalReference.isCurrent
        else { return false }
        if let selfParent {
            guard candidateSelfBodyAcceptance(for: construction.parent) === selfParent,
                parent === selfParent.reader
            else { return false }
        } else if !token.qualification.canPublish {
            return false
        }
        let key = token.segmentKey
        let publications = selfParent == nil ? currentCandidatePublications(for: field) : []
        let segment = field.segments[key] ?? RetainedOwnedCandidateSegment(key: key)
        let fieldActual: RetainedLazyListActualAttachment
        if let selfParent {
            fieldActual = selfParent.field.actual
        } else if let acceptedParent = candidateAcceptedSegments[ObjectIdentifier(construction.parent)],
            acceptedParent.isCurrent
        {
            fieldActual = acceptedParent.field.actual
        } else if let original = construction.parent.qualification.currentContinuation,
            construction.parent.isDeferredSegment, original.isCurrent
        {
            fieldActual = original.field.actual
        } else if let publication = publications.first(where: {
            $0.write.token?.qualification === token.qualification
                && $0.write.plans.contains(where: { $0 === normal.plan })
        }) {
            fieldActual = publication.afterimage.actual
        } else {
            return false
        }
        field.segments[key] = segment
        let publication = RetainedOwnedCandidateReaderPublication(
            reader: construction.registration.receipt, contribution: fact.contribution, actual: fact.actual)
        let reader =
            originalReader
            ?? RetainedOwnedCandidateAcceptedReader(
                field: field, segment: segment, normalReference: normalReference, parent: parent,
                publication: publication)
        reader.publication = publication
        segment.acceptedReader = reader
        normalReference.declarationEdge.acceptedReader = reader
        if let parent {
            parent.children[ObjectIdentifier(reader)] = RetainedOwnedWeakCandidateReader(reader)
        } else {
            field.readerRoots[ObjectIdentifier(reader)] = RetainedOwnedWeakCandidateReader(reader)
        }
        guard
            let snapshot = RetainedOwnedCandidateFieldSnapshot(
                field: field, actual: fieldActual, selectedSegment: key)
        else { return false }
        let accepted = RetainedOwnedCandidateDeferredAnchor(
            owner: token.owner, reader: construction.registration.receipt, contribution: fact.contribution,
            actual: fact.actual, field: snapshot, segment: key, readerRecord: reader, readerPublication: publication)
        target.lazyListActivityStorage().ownedCandidateDeferredAnchor = accepted
        fact.acceptedAnchor = accepted
        candidateAcceptedSegments[ObjectIdentifier(token)] = RetainedOwnedCandidateSegmentAcceptance(
            construction: construction, normal: normal, descriptor: fact, reader: reader,
            publication: publication, field: snapshot, anchor: accepted, selfParent: selfParent)
        for previous in publications where !previous.afterimage.isCurrent { refreshCandidateAfterimage(previous) }
        return true
    }

    private func advanceAcceptedCandidateReader(_ accepted: RetainedOwnedCandidateSegmentAcceptance) {
        let previous = accepted.anchor
        guard accepted.reader.isDeclared, accepted.reader.publication === accepted.publication,
            accepted.descriptor.descriptorFactIsCurrent, accepted.normal.actual.isAttached,
            accepted.construction.token?.qualification.canPublish == true,
            previous.actual.node?.retainedLazyListActivityStorage?.ownedCandidateDeferredAnchor === previous,
            let snapshot = RetainedOwnedCandidateFieldSnapshot(
                field: accepted.field.field, actual: accepted.field.actual, selectedSegment: previous.segment)
        else { return }
        let next = RetainedOwnedCandidateDeferredAnchor(
            owner: previous.owner, reader: previous.reader, contribution: previous.contribution,
            actual: previous.actual, field: snapshot, segment: previous.segment,
            readerRecord: accepted.reader, readerPublication: accepted.publication)
        previous.actual.node?.lazyListActivityStorage().ownedCandidateDeferredAnchor = next
        accepted.field = snapshot
        accepted.anchor = next
        accepted.descriptor.acceptedAnchor = next
    }

    private func refreshCandidateDeferredAnchors() {
        // Initial readers may publish before their enclosing boundary. Only
        // exact accepted reader facts and the actual accepted descriptor anchor
        // may complete that pending association.
        flushCandidateAcceptedFacts()
    }
}

extension RetainedLazyListAdoptionJournal {
    @discardableResult
    func seedOwnedCandidateOrigins(at root: ViewNode) -> Bool {
        guard canContinueConstruction, let scope = boundDescriptorScope else { return false }
        return scope.ownedLedger.seedOwnedCandidateOrigins(at: root, scope: scope)
    }

    func prepareOwnedCandidateCatalog(from source: ViewNode, to target: ViewNode) -> RetainedOwnedCandidateCatalogWrite?
    {
        guard canContinueAdoption else { return nil }
        return ownedLedger?.prepareOwnedCandidateCatalog(from: source, to: target)
    }

    @discardableResult
    func publishOwnedCandidateCatalog(_ write: RetainedOwnedCandidateCatalogWrite) -> Bool {
        guard canContinueAdoption else { return false }
        return ownedLedger?.publishOwnedCandidateCatalog(write) == true
    }

    func applyOwnedCandidateCatalog(from source: ViewNode, to target: ViewNode) -> Bool {
        if source.retainedLazyListActivityStorage?.ownedCandidateDeferredSource?.selfConstruction != nil
            || ownedLedger?.hasOwnedCandidateSelfSource(source) == true
        {
            guard canContinueAdoption, let ownedLedger else { return false }
            return ownedLedger.applyOwnedCandidateSelfSource(from: source, to: target)
        }
        if source.retainedLazyListActivityStorage?.ownedCandidateDeferredSource?.segmentConstruction != nil
            || ownedLedger?.hasOwnedCandidateChildCatalogInput(from: source, to: target) == true
        {
            guard canContinueAdoption, let ownedLedger else { return false }
            return ownedLedger.applyOwnedCandidateChildCatalog(from: source, to: target)
        }
        guard
            source.retainedLazyListActivityStorage?.ownedCandidateBoundarySource != nil
                || target.retainedLazyListActivityStorage?.ownedCandidateField != nil
        else { return true }
        guard let ownedLedger else { return true }
        guard canContinueAdoption else { return false }
        return ownedLedger.applyOwnedCandidateCatalog(from: source, to: target)
    }

    func applyOwnedCandidateDeferredCatalog(at parent: ViewNode) -> Bool {
        guard let ownedLedger else { return true }
        guard canContinueAdoption else { return false }
        return ownedLedger.applyOwnedCandidateDeferredCatalog(at: parent)
    }

    func applyOriginalOwnedCandidateDeferredCatalogForDirectAdoption(at parent: ViewNode) -> Bool {
        guard let ownedLedger else { return true }
        switch ownedLedger.originalOwnedCandidateForDirectAdoption(at: parent) {
        case .absent:
            return true
        case .ambiguous:
            return false
        case .unique(let original):
            guard canContinueAdoption else { return false }
            return ownedLedger.applyOriginalOwnedCandidateDeferredCatalog(original, at: parent)
        }
    }
}
