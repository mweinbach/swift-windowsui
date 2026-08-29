import SwiftWindowsCore
import SwiftWindowsUI

/// A known declaration can replace its primary child while retaining auxiliary
/// modifier branches. Membership never requires evaluating an inactive body.
struct StateMountDeclarationScope {
    enum ExcludedChildren {
        case none
        case modifierContent
        case conditionalBranches
        case arrayOccurrences
        case typedContent
    }

    let prefix: RetainedViewIdentity
    var excluding: ExcludedChildren = .none

    func contains(_ identity: RetainedViewIdentity) -> Bool {
        contains(identity, isCurrent: { true }) == true
    }

    func contains(_ identity: RetainedViewIdentity, isCurrent: () -> Bool) -> Bool? {
        guard let containsPrefix = identity.checkedHasPrefix(prefix, isCurrent: isCurrent) else { return nil }
        guard containsPrefix else { return false }
        guard identity.segments.count > prefix.segments.count else { return true }
        let child = identity.segments[prefix.segments.count]
        switch (excluding, child) {
        case (.modifierContent, .role(.content)), (.modifierContent, .explicit),
            (.conditionalBranches, .branch), (.arrayOccurrences, .occurrence):
            return false
        case (.typedContent, .role):
            return true
        case (.typedContent, _):
            return false
        default:
            return true
        }
    }
}

@MainActor
fileprivate protocol AnyMountedStateCell: AnyObject {
    var ownedSlotGeneration: RetainedOwnedSlotGenerationID? { get }
    var ownedComponentReceipt: RetainedOwnedComponentReceipt? { get }
    var hasLiveManagedPermission: Bool { get }
    func bindOwnedLocation(_ receipt: RetainedOwnedComponentReceipt, slot: RetainedOwnedSlotGenerationID)
    var lazyOwnership: LazyListCellOwnership? { get }
    var lazyContribution: RetainedLazyListContributionReceipt? { get }
    func setLazyOwnership(_ ownership: LazyListCellOwnership, contribution: RetainedLazyListContributionReceipt?)
    var descriptorOwnership: DescriptorCellOwnership? { get }
    var descriptorContribution: RetainedDescriptorContributionReceipt? { get }
    func setDescriptorOwnership(
        _ ownership: DescriptorCellOwnership, contribution: RetainedDescriptorContributionReceipt?)
    func activate()
    func beginRetirement()
    func cancelRetirement()
    func finishRetirement()
}

/// A captured location never resolves another mount at the same structural path.
/// A retired read handle retains its last Value with normal reference semantics;
/// it cannot write, invalidate, or keep the host's ownership registry alive.
@MainActor
final class MountedStateCell<Value>: AnyMountedStateCell {
    private var value: Value
    private weak var owner: StateMountOwner?
    private var phase = StateMountPhase.provisional
    fileprivate private(set) var ownedSlotGeneration: RetainedOwnedSlotGenerationID?
    fileprivate private(set) var ownedComponentReceipt: RetainedOwnedComponentReceipt?
    fileprivate private(set) var lazyOwnership: LazyListCellOwnership?
    fileprivate private(set) var lazyContribution: RetainedLazyListContributionReceipt?
    fileprivate private(set) var descriptorOwnership: DescriptorCellOwnership?
    fileprivate private(set) var descriptorContribution: RetainedDescriptorContributionReceipt?

    fileprivate init(value: Value, owner: StateMountOwner) {
        self.value = value
        self.owner = owner
    }

    var isWritable: Bool {
        switch phase {
        case .provisional:
            if let slot = ownedSlotGeneration, ownedComponentReceipt?.hasAcceptedOwnership(for: slot) == true {
                return owner?.canWriteAcceptedManagedCell == true
            }
            guard owner?.isInstallationActive == true else { return false }
            if let slot = ownedSlotGeneration { return ownedComponentReceipt?.permitsOwnedWrite(for: slot) == true }
            return true
        case .live:
            guard owner?.isLive == true else { return false }
            if let slot = ownedSlotGeneration, ownedComponentReceipt?.permitsOwnedWrite(for: slot) != true {
                return false
            }
            if case .synthetic = descriptorOwnership { return descriptorContribution?.isActive == true }
            switch lazyOwnership {
            case .none: return true
            case .owned(let membership, _): return membership.isDeclared
            case .synthetic(_, let physical, _):
                return lazyContribution?.isActive == true && lazyContribution?.physical === physical
            }
        case .retiring, .retired:
            return false
        }
    }

    /// Only native scalar records are read here. An adopted declaration or
    /// physical contribution, never a row-key lookup, permits this generation.
    fileprivate var hasLiveManagedPermission: Bool {
        guard phase != .retiring, phase != .retired, owner?.lazyLifetime.isAvailable == true else { return false }
        if let slot = ownedSlotGeneration { return ownedComponentReceipt?.permitsOwnedWrite(for: slot) == true }
        if case .synthetic = descriptorOwnership { return descriptorContribution?.isActive == true }
        if case .synthetic(_, let physical, _) = lazyOwnership {
            return lazyContribution?.isActive == true && lazyContribution?.physical === physical
        }
        return false
    }

    fileprivate func bindOwnedLocation(
        _ receipt: RetainedOwnedComponentReceipt, slot: RetainedOwnedSlotGenerationID
    ) {
        // A cell is never redirected to another slot generation. Continuing
        // rosters share the exact original permission object in the native layer.
        guard ownedSlotGeneration == nil || ownedSlotGeneration === slot else { return }
        ownedSlotGeneration = slot
        ownedComponentReceipt = receipt
    }

    /// Preservation only admits an already-live cell of this exact owner.
    /// It must not enter the ordinary provisional installation lookup.
    fileprivate func isLiveObservation(of owner: StateMountOwner) -> Bool {
        phase == .live && self.owner === owner && owner.isLive && isWritable
    }

    fileprivate func setLazyOwnership(
        _ ownership: LazyListCellOwnership, contribution: RetainedLazyListContributionReceipt?
    ) {
        lazyOwnership = ownership
        lazyContribution = contribution
    }

    fileprivate func setDescriptorOwnership(
        _ ownership: DescriptorCellOwnership, contribution: RetainedDescriptorContributionReceipt?
    ) {
        descriptorOwnership = ownership
        descriptorContribution = contribution
    }

    func readValue() -> Value {
        value
    }

    @discardableResult
    func write(_ value: Value) -> Bool {
        guard isWritable else { return false }
        // Releasing the outgoing Value can run application code. Mark the
        // accepted mutation before that release or any invalidation callback.
        let acceptedManaged =
            ownedSlotGeneration.map { ownedComponentReceipt?.hasAcceptedOwnership(for: $0) == true }
            == true
        let revision =
            acceptedManaged ? owner?.willWriteAcceptedManagedCell() : (phase == .live ? owner?.willWrite() : nil)
        self.value = value
        if let revision {
            if acceptedManaged {
                owner?.didWriteAcceptedManagedCell(revision: revision)
            } else {
                owner?.didWrite(revision: revision)
            }
        }
        return true
    }

    fileprivate func activate() {
        guard phase == .provisional else { return }
        phase = .live
    }

    fileprivate func beginRetirement() {
        guard phase != .retired else { return }
        phase = .retiring
    }

    fileprivate func finishRetirement() {
        phase = .retired
        owner = nil
    }

    fileprivate func cancelRetirement() {
        guard phase == .retiring else { return }
        phase = .live
    }
}

private enum StateMountPhase {
    case provisional
    case live
    case retiring
    case retired
}

/// A rejected materialization may retain only this already-committed cell.
/// The initializer is confined to the checked lookup below; a bare identity
/// lookup or an owner from another host cannot manufacture this receipt.
@MainActor
final class MountedObservationPreservation<Observation> {
    let owner: StateMountOwner
    private let cell: MountedStateCell<Observation>
    private weak var epoch: StateMountEpoch?

    fileprivate init(owner: StateMountOwner, cell: MountedStateCell<Observation>, epoch: StateMountEpoch) {
        self.owner = owner
        self.cell = cell
        self.epoch = epoch
    }

    func prepare(in epoch: StateMountEpoch) -> Bool {
        guard self.epoch === epoch else { return false }
        return epoch.preserveSyntheticObservation(owner: owner, cell: cell)
    }
}

/// One generation of a concrete view occurrence. Property slots, rather than
/// getter order or a mutable source box, choose the locations within this owner.
@MainActor
final class StateMountOwner {
    let identity: RetainedViewIdentity
    let generation: UInt64
    let lazyLifetime: LazyListOwnerLifetime
    fileprivate let ownedComponentID = RetainedOwnedComponentID()
    fileprivate var ownedComponentReceipt: RetainedOwnedComponentReceipt?
    private weak var registry: StateMountRegistry?
    fileprivate var cells: [StatePropertySlot: any AnyMountedStateCell] = [:]
    private var phase = StateMountPhase.provisional

    fileprivate init(identity: RetainedViewIdentity, generation: UInt64, registry: StateMountRegistry) {
        self.identity = identity
        self.generation = generation
        self.registry = registry
        lazyLifetime = LazyListOwnerLifetime(registry: registry.lazyLifetime)
    }

    var isInstallationActive: Bool {
        guard let registry, !registry.isClosed, phase != .retired else { return false }
        return registry.activeEpoch?.isInstalling(self) == true
    }

    var installationEpoch: StateMountEpoch? {
        guard isInstallationActive else { return nil }
        return registry?.activeEpoch
    }

    var isLive: Bool { phase == .live && registry?.isClosed == false }

    fileprivate var canWriteAcceptedManagedCell: Bool {
        (phase == .provisional || phase == .live) && lazyLifetime.isAvailable && registry?.isClosed == false
    }

    fileprivate func willWriteAcceptedManagedCell() -> UInt64? {
        guard canWriteAcceptedManagedCell else { return nil }
        return registry?.willWrite()
    }

    fileprivate func didWriteAcceptedManagedCell(revision: UInt64) {
        guard canWriteAcceptedManagedCell else { return }
        registry?.didWrite(revision: revision)
    }

    /// Observer snapshot validation checks map membership separately. This
    /// scalar half must not invoke the ordinary live-dictionary resolver.
    fileprivate func hasObservationInstallationAuthority(in registry: StateMountRegistry) -> Bool {
        self.registry === registry && phase != .retired
    }

    func resolve<Value>(at slot: StatePropertySlot, seed: () -> Value) -> MountedStateCell<Value> {
        guard let epoch = registry?.activeEpoch, epoch.isInstalling(self) else {
            preconditionFailure("State properties must resolve within their active mount build")
        }
        return epoch.resolve(owner: self, slot: slot, seed: seed)
    }

    /// DynamicProperty installation already has a throwing failure channel.
    /// Lazy admission uses it instead of seeding after a rejected key lookup.
    func resolveForInstallation<Value>(at slot: StatePropertySlot, seed: () -> Value) throws -> MountedStateCell<Value>
    {
        if let epoch = registry?.activeEpoch, epoch.lazyAttribution(for: self) != nil {
            return try epoch.resolveLazyOwnedCell(owner: self, slot: slot, seed: seed)
        }
        if let epoch = registry?.activeEpoch, epoch.descriptorAttribution(for: self) != nil {
            return try epoch.resolveDescriptorOwnedCell(owner: self, slot: slot, isObjectFactory: false, seed: seed)
        }
        return resolve(at: slot, seed: seed)
    }

    func resolveObject<ObjectType: ObservableObject>(
        at slot: StatePropertySlot, seed: () -> ObjectType
    ) throws -> MountedStateCell<ObjectType> {
        guard let epoch = installationEpoch else {
            throw DynamicPropertyInstaller.failure(
                .ownerUnavailable, type: StateObject<ObjectType>.self, at: slot,
                "StateObject creation requires its original active mount build")
        }
        return try epoch.resolveObject(owner: self, slot: slot, seed: seed)
    }

    func isInstalled<Value>(cell: MountedStateCell<Value>, at slot: StatePropertySlot) -> Bool {
        installationEpoch?.isInstalled(cell: cell, owner: self, slot: slot) == true
    }

    fileprivate func willWrite() -> UInt64? {
        guard isLive else { return nil }
        return registry?.willWrite()
    }

    fileprivate func didWrite(revision: UInt64) {
        guard isLive else { return }
        registry?.didWrite(revision: revision)
    }

    fileprivate func activate() {
        guard phase == .provisional || phase == .live else { return }
        phase = .live
        for cell in cells.values { cell.activate() }
    }

    fileprivate func beginRetirement() {
        guard phase != .retired else { return }
        lazyLifetime.retire()
        phase = .retiring
        for cell in cells.values { cell.beginRetirement() }
    }

    fileprivate func finishRetirement() {
        lazyLifetime.retire()
        phase = .retired
        for cell in cells.values { cell.finishRetirement() }
        cells.removeAll()
        registry = nil
    }

    fileprivate func cancelRetirement() {
        guard phase == .retiring else { return }
        lazyLifetime.cancelRetirement()
        phase = .live
        for cell in cells.values { cell.cancelRetirement() }
    }
}

/// Main-actor storage owned by one host. This has no ambient singleton and does
/// not infer membership from painting, appearance, or an omitted body visit.
@MainActor
final class StateMountRegistry {
    let lazyLifetime = LazyListRegistryLifetime()
    fileprivate var lazyDeclarations: ManagedKeyedMap<RetainedViewIdentity, LazyListCommittedDeclaration> = [:] {
        didSet { lazyDeclarationMapsDidChange() }
    }
    fileprivate var lazyLogicalScopes: [ObjectIdentifier: RetainedLazyListLogicalMembershipScope] = [:]
    fileprivate var lazyDeclarationRevision: UInt64? = 0
    fileprivate var lastManagedAdoption: RetainedLazyListAttemptID?
    private let invalidate: @MainActor () -> Void
    fileprivate var owners: ManagedKeyedMap<RetainedViewIdentity, StateMountOwner> = [:]
    fileprivate var activeEpoch: StateMountEpoch?
    fileprivate var retiringOwners: [UInt64: StateMountOwner] = [:]
    fileprivate var retiringCells: [ObjectIdentifier: any AnyMountedStateCell] = [:]
    private var nextGeneration: UInt64 = 0
    private(set) var isClosed = false
    private(set) var mutationRevision: UInt64 = 0

    init(invalidate: @escaping @MainActor () -> Void = {}) {
        self.invalidate = invalidate
    }

    isolated deinit {
        close()
        activeEpoch?.finishAbandonedBuild(in: self)
        finishPendingRetirements()
    }

    var liveOwnerCount: Int { owners.count }
    var retiringOwnerCount: Int { retiringOwners.count }

    func beginRootBuild() -> StateMountEpoch? {
        beginBuild(prefix: nil, anchor: nil)
    }

    func beginSubtreeBuild(
        owner: StateMountOwner, contentPrefix: RetainedViewIdentity
    ) -> StateMountEpoch? {
        guard owners[owner.identity] === owner, owner.isLive,
            contentPrefix.segments.count > owner.identity.segments.count,
            contentPrefix.segments.starts(with: owner.identity.segments)
        else { return nil }
        return beginBuild(prefix: contentPrefix, anchor: owner)
    }

    private func beginBuild(prefix: RetainedViewIdentity?, anchor: StateMountOwner?) -> StateMountEpoch? {
        guard !isClosed, activeEpoch == nil else { return nil }
        let epoch = StateMountEpoch(registry: self, prefix: prefix, anchor: anchor)
        activeEpoch = epoch
        return epoch
    }

    func owner(at identity: RetainedViewIdentity) -> StateMountOwner? {
        owners[identity]
    }

    fileprivate func makeOwner(at identity: RetainedViewIdentity) -> StateMountOwner {
        precondition(nextGeneration != .max, "State mount generation space exhausted")
        nextGeneration += 1
        return StateMountOwner(identity: identity, generation: nextGeneration, registry: self)
    }

    fileprivate func willWrite() -> UInt64? {
        guard !isClosed else { return nil }
        precondition(mutationRevision != .max, "State mutation revision space exhausted")
        mutationRevision += 1
        return mutationRevision
    }

    fileprivate func didWrite(revision: UInt64) {
        // A payload's release may already have performed a newer mutation
        // and scheduled its transaction. Do not replace that request here.
        guard !isClosed, mutationRevision == revision else { return }
        invalidate()
    }

    /// Called after the corresponding outgoing cleanup has finished. The
    /// generation belongs to the old owner, never a replacement path lookup.
    func finishRetirement(of generation: UInt64) {
        retiringOwners.removeValue(forKey: generation)?.finishRetirement()
    }

    func finishPendingRetirements() {
        let owners = Array(retiringOwners.values)
        let cells = Array(retiringCells.values)
        retiringOwners.removeAll()
        retiringCells.removeAll()
        for owner in owners { owner.finishRetirement() }
        for cell in cells { cell.finishRetirement() }
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        lastManagedAdoption = nil
        lazyLifetime.close()
        // The roster contains only native scalar scopes, including empty,
        // pending and cold declarations. Revoke before any authored cleanup.
        for scope in lazyLogicalScopes.values { scope.revokeLogicalMembership() }
        let previousDeclarations = lazyDeclarations
        let previousScopes = lazyLogicalScopes
        lazyDeclarations.removeAll()
        lazyLogicalScopes.removeAll()
        defer { withExtendedLifetime((previousDeclarations, previousScopes)) {} }
        for owner in owners.values {
            owner.beginRetirement()
            retiringOwners[owner.generation] = owner
        }
        owners.removeAll()
        activeEpoch?.revokeWrites()
        // An active user builder may still need cleanup reads while unwinding.
        // Its abort/commit exit releases registry ownership once it returns.
        if activeEpoch == nil { finishPendingRetirements() }
    }
}

/// A provisional membership update spanning composition and node construction.
/// The caller decides which declared scopes were adopted or kept inactive.
@MainActor
final class StateMountEpoch {
    let lazyLifetime: LazyListEpochLifetime
    private enum Phase {
        case constructing
        case adopting
        case finished
    }

    private weak var registry: StateMountRegistry?
    private let prefix: RetainedViewIdentity?
    private weak var anchor: StateMountOwner?
    private let anchorGeneration: UInt64?
    private var phase = Phase.constructing
    private var superseded = false
    private var candidates: ManagedKeyedMap<RetainedViewIdentity, StateMountOwner> = [:] {
        didSet { observationMapsDidChange() }
    }
    private var claimedSlots: ManagedKeyedMap<RetainedViewIdentity, Set<StatePropertySlot>> = [:] {
        didSet { observationMapsDidChange() }
    }
    private var provisionalCells: ManagedKeyedMap<RetainedViewIdentity, [StatePropertySlot: any AnyMountedStateCell]> =
        [:]
    {
        didSet { observationMapsDidChange() }
    }
    private var observationMapRevision: UInt64? = 0
    private var lazyActivityRevision: UInt64? = 0
    private var lazyConstructionAttempts: [ObjectIdentifier: LazyListComponentConstructionAttempt] = [:]
    private var lazyDiscardScopes: [ObjectIdentifier: LazyListDiscardReceipt] = [:]
    private var lazyPreservedScopes: [LazyListPreservedDeclarationScope] = []
    private var descriptorConstructionAttempts: [ObjectIdentifier: DescriptorComponentConstructionAttempt] = [:]
    private var descriptorOwners: [UInt64: DescriptorOwnerAcquisition] = [:]
    private var descriptorCellProposals: [ObjectIdentifier: DescriptorCellProposal] = [:]
    private var descriptorPreservedScopes: [DescriptorPreservedDeclarationScope] = []
    private var managedPreservedOwners: [ManagedPreservedOwnerKey: ManagedPreservedOwner] = [:]
    fileprivate var lazyBoundaryActivity: RetainedLazyListContributionReceipt?
    fileprivate var descriptorBoundaryActivity: RetainedDescriptorContributionReceipt?
    private var lazyOwners: [UInt64: LazyListOwnerAcquisition] = [:] {
        didSet { lazyActivityMapsDidChange() }
    }
    private var lazyCellProposals: [ObjectIdentifier: LazyListCellProposal] = [:] {
        didSet { lazyActivityMapsDidChange() }
    }
    fileprivate var lazyMemberships: [ObjectIdentifier: LazyListMembershipProposal] = [:] {
        didSet { lazyActivityMapsDidChange() }
    }
    fileprivate var lazyReservations: [ObjectIdentifier: LazyListSelectedRowReservation] = [:] {
        didSet { lazyActivityMapsDidChange() }
    }
    private var lazyPreparation: RetainedLazyListAdoptionPreparation?
    private var lazyPreparedPins: LazyListStateSelectionPins?
    private var didFinishManagedTransport = false
    fileprivate var lazyCreatedScopes: [ObjectIdentifier: RetainedLazyListLogicalMembershipScope] = [:]
    private var lazyRetiredScopes: [ObjectIdentifier: RetainedLazyListLogicalMembershipScope] = [:]
    private var preservedObservationOwners: [UInt64: StateMountOwner] = [:]
    private var preservedObservationCells: Set<ObjectIdentifier> = []
    private var pendingObjectCreations: [UInt64: Set<StatePropertySlot>] = [:]
    private var preservedScopes: [StateMountDeclarationScope] = []
    private var preparedOwnerGenerations: Set<UInt64> = []
    private var preparedCellIdentifiers: Set<ObjectIdentifier> = []
    private(set) var didCommit = false

    fileprivate init(registry: StateMountRegistry, prefix: RetainedViewIdentity?, anchor: StateMountOwner?) {
        lazyLifetime = LazyListEpochLifetime(registry: registry.lazyLifetime)
        self.registry = registry
        self.prefix = prefix
        self.anchor = anchor
        self.anchorGeneration = anchor?.generation
    }

    var canAdopt: Bool {
        guard phase == .constructing, !superseded, let registry,
            !registry.isClosed, registry.activeEpoch === self
        else { return false }
        guard let anchorGeneration else { return true }
        guard let anchor, anchor.generation == anchorGeneration else { return false }
        if lazyLifetime.nativeAttempt != nil {
            // This predicate is used as an authored-operation guard. It cannot
            // itself invoke another authored identity callback on managed work.
            return anchor.isLive && registry.owners.values.contains(where: { $0 === anchor })
        }
        return registry.owners[anchor.identity] === anchor && anchor.isLive
    }

    var isAdopting: Bool { phase == .adopting }
    var visitedOwnerIdentities: Set<RetainedViewIdentity> { Set(candidates.keys) }

    func supersede() {
        guard phase == .constructing else { return }
        superseded = true
        lazyLifetime.stopConstruction()
    }

    func owner(at identity: RetainedViewIdentity) -> StateMountOwner? {
        guard canAdopt, includes(identity), let registry else { return nil }
        if let owner = candidates[identity] { return owner }
        let owner = registry.owners[identity] ?? registry.makeOwner(at: identity)
        candidates[identity] = owner
        claimedSlots[identity] = []
        return owner
    }

    fileprivate func isInstalling(_ owner: StateMountOwner) -> Bool {
        if let acquisition = lazyOwners[owner.generation] {
            return lazyOwnerIsCurrent(owner, attribution: acquisition.attribution)
        }
        if let acquisition = descriptorOwners[owner.generation] {
            return descriptorOwnerIsCurrent(owner, attribution: acquisition.attribution)
        }
        return canAdopt && candidates[owner.identity] === owner
    }

    /// A callback-free receipt, unlike canAdopt's authored anchor lookup.
    /// During construction, anchor membership can leave this registry only
    /// through adoption, retirement, or close, all checked here by scalars.
    var observationConstructionRevision: UInt64? {
        guard phase == .constructing, !superseded, let registry,
            !registry.isClosed, registry.activeEpoch === self
        else { return nil }
        if let anchorGeneration {
            guard let anchor, anchor.generation == anchorGeneration, anchor.isLive else { return nil }
        }
        return observationMapRevision
    }

    private func observationMapsDidChange() {
        guard let revision = observationMapRevision, revision < .max else {
            // Exhaustion rejects new observer admission, without changing an
            // ordinary State/StateObject resolver or introducing a new trap.
            observationMapRevision = nil
            return
        }
        observationMapRevision = revision + 1
    }

    private struct ObservationMaps {
        var candidates: ManagedKeyedMap<RetainedViewIdentity, StateMountOwner>
        var claimedSlots: ManagedKeyedMap<RetainedViewIdentity, Set<StatePropertySlot>>
        var provisionalCells: ManagedKeyedMap<RetainedViewIdentity, [StatePropertySlot: any AnyMountedStateCell]>
        var createdOwner: StateMountOwner?
        var createdCells: [any AnyMountedStateCell] = []
    }

    /// This compatibility entry does not create a synthetic property slot.
    /// Its owner lookup shares the checked publication path used below.
    func syntheticObservationOwner(
        at identity: RetainedViewIdentity, isMaterializationCurrent: () -> Bool = { true }
    ) -> StateMountOwner? {
        let result = acquireObservation(at: identity, isMaterializationCurrent: isMaterializationCurrent) {
            owner, _, _ in owner
        }
        // The inner call has released its dictionaries and displaced keys.
        // Their cleanup may close, supersede, or mutate this same epoch.
        guard let result, observationConstructionRevision == result.revision, isMaterializationCurrent() else {
            return nil
        }
        return result.value
    }

    /// Observer bookkeeping is conditional: a canceled construction must not
    /// reach the ordinary property resolver's installation precondition.
    func resolveSyntheticObservation<Observation>(
        at identity: RetainedViewIdentity, isMaterializationCurrent: () -> Bool = { true }, seed: () -> Observation
    ) -> (owner: StateMountOwner, cell: MountedStateCell<Observation>)? {
        let slot = StatePropertySlot(concreteTypes: [ObjectIdentifier(Observation.self)])
        let result = acquireObservation(at: identity, isMaterializationCurrent: isMaterializationCurrent) {
            (owner, maps, revision) -> (owner: StateMountOwner, cell: MountedStateCell<Observation>)? in
            let committedCells = owner.cells
            defer { withExtendedLifetime(committedCells) {} }
            var claimed =
                maps.claimedSlots[
                    owner.identity,
                    while: { self.observationConstructionRevision == revision && isMaterializationCurrent() }
                ] ?? []
            guard observationConstructionRevision == revision, isMaterializationCurrent() else { return nil }
            claimed.insert(slot)
            maps.claimedSlots[
                owner.identity,
                while: { self.observationConstructionRevision == revision && isMaterializationCurrent() }
            ] = claimed
            guard observationConstructionRevision == revision, isMaterializationCurrent() else { return nil }
            var cells =
                maps.provisionalCells[
                    owner.identity,
                    while: { self.observationConstructionRevision == revision && isMaterializationCurrent() }
                ] ?? [:]
            guard observationConstructionRevision == revision, isMaterializationCurrent() else { return nil }
            if let existing = cells[slot] ?? committedCells[slot] {
                guard let cell = existing as? MountedStateCell<Observation> else { return nil }
                return (owner: owner, cell: cell)
            }
            let cell = MountedStateCell(value: seed(), owner: owner)
            maps.createdCells.append(cell)
            guard observationConstructionRevision == revision, isMaterializationCurrent() else { return nil }
            cells[slot] = cell
            maps.provisionalCells[
                owner.identity,
                while: { self.observationConstructionRevision == revision && isMaterializationCurrent() }
            ] = cells
            guard observationConstructionRevision == revision, isMaterializationCurrent() else { return nil }
            return (owner: owner, cell: cell)
        }
        guard let result, observationConstructionRevision == result.revision, isMaterializationCurrent() else {
            return nil
        }
        return result.value
    }

    @inline(never)
    private func acquireObservation<Result>(
        at identity: RetainedViewIdentity, isMaterializationCurrent: () -> Bool,
        lookup: LazyListLookupReceipt? = nil,
        resolve: (StateMountOwner, inout ObservationMaps, UInt64) -> Result?
    ) -> (value: Result, revision: UInt64)? {
        guard let revision = observationConstructionRevision, isMaterializationCurrent(), let registry else {
            return nil
        }
        // Snapshot before even the anchor's authored hash. The ordinary
        // canAdopt path reads live membership and is not an observer guard.
        // All authored key operations run on local snapshots. In particular,
        // closing from hash(into:) must not read a dictionary held inout by
        // this operation. The committed snapshot pins outgoing owners too.
        let committed = registry.owners
        let previous = ObservationMaps(
            candidates: candidates, claimedSlots: claimedSlots, provisionalCells: provisionalCells)
        var maps = previous
        var didPublish = false
        defer {
            if !didPublish {
                retireRejectedObservation(in: maps, registry: registry)
            }
            withExtendedLifetime((committed, previous, maps)) {}
        }

        guard
            observationAnchorIsCurrent(
                in: committed,
                isCurrent: {
                    self.observationConstructionRevision == revision && isMaterializationCurrent()
                }),
            observationConstructionRevision == revision, isMaterializationCurrent(),
            includes(
                identity, isCurrent: { self.observationConstructionRevision == revision && isMaterializationCurrent() }),
            observationConstructionRevision == revision, isMaterializationCurrent()
        else { return nil }
        let candidate = maps.candidates[
            identity, while: { self.observationConstructionRevision == revision && isMaterializationCurrent() }
        ]
        guard observationConstructionRevision == revision, isMaterializationCurrent() else { return nil }
        let owner: StateMountOwner
        if let candidate {
            owner = candidate
        } else {
            let existing = committed[
                identity, while: { self.observationConstructionRevision == revision && isMaterializationCurrent() }
            ]
            guard observationConstructionRevision == revision, isMaterializationCurrent() else { return nil }
            if let existing {
                owner = existing
            } else {
                owner = registry.makeOwner(at: identity)
                maps.createdOwner = owner
            }
            maps.candidates[
                owner.identity,
                while: { self.observationConstructionRevision == revision && isMaterializationCurrent() }
            ] = owner
            guard observationConstructionRevision == revision, isMaterializationCurrent() else { return nil }
            maps.claimedSlots[
                owner.identity,
                while: { self.observationConstructionRevision == revision && isMaterializationCurrent() }
            ] = []
            guard observationConstructionRevision == revision, isMaterializationCurrent() else { return nil }
        }
        guard let value = resolve(owner, &maps, revision),
            observationConstructionRevision == revision, isMaterializationCurrent(), revision <= UInt64.max - 3
        else { return nil }

        // No key operation or application callback occurs between these
        // assignments. The three didSet receipts must advance exactly once
        // each, and previous keeps every displaced dictionary alive.
        guard lookup?.allowPublication(observations: 3) != false else { return nil }
        let publishedRevision = revision + 3
        candidates = maps.candidates
        claimedSlots = maps.claimedSlots
        provisionalCells = maps.provisionalCells
        didPublish = true
        return (value, publishedRevision)
    }

    /// Both admission overloads validate their owner through snapshots.
    /// A failed final check must not borrow canAdopt/isInstalling, whose
    /// dictionary access can overlap a reentrant authored hash.
    func observationOwnerIsCurrent(
        owner: StateMountOwner, revision: UInt64, isMaterializationCurrent: () -> Bool = { true }
    ) -> Bool {
        let result = lookupObservationOwner(
            owner: owner, revision: revision, isMaterializationCurrent: isMaterializationCurrent)
        // The inner call releases all pinned dictionaries before this check.
        return result && observationConstructionRevision == revision && isMaterializationCurrent()
    }

    @inline(never)
    private func lookupObservationOwner(
        owner: StateMountOwner, revision: UInt64, isMaterializationCurrent: () -> Bool
    ) -> Bool {
        guard observationConstructionRevision == revision, isMaterializationCurrent(), let registry,
            owner.hasObservationInstallationAuthority(in: registry)
        else { return false }
        let committed = registry.owners
        let candidates = self.candidates
        defer { withExtendedLifetime((committed, candidates)) {} }
        guard
            observationAnchorIsCurrent(
                in: committed,
                isCurrent: {
                    self.observationConstructionRevision == revision && isMaterializationCurrent()
                }),
            observationConstructionRevision == revision, isMaterializationCurrent()
        else { return false }
        let candidate = candidates[
            owner.identity, while: { self.observationConstructionRevision == revision && isMaterializationCurrent() }
        ]
        guard observationConstructionRevision == revision, isMaterializationCurrent() else { return false }
        return candidate === owner && owner.hasObservationInstallationAuthority(in: registry)
    }

    /// The typed slot check pins every map it reads, including the owner's
    /// committed cells. An outgoing payload's cleanup cannot authorize a
    /// publication after the inner scope returns.
    func observationCellIsInstalled<Observation>(
        cell: MountedStateCell<Observation>, owner: StateMountOwner, at slot: StatePropertySlot,
        revision: UInt64, isMaterializationCurrent: () -> Bool = { true }
    ) -> Bool {
        let result = lookupObservationCell(
            cellIdentifier: ObjectIdentifier(cell), owner: owner, slot: slot, revision: revision,
            isMaterializationCurrent: isMaterializationCurrent)
        return result && observationConstructionRevision == revision && isMaterializationCurrent()
    }

    @inline(never)
    private func lookupObservationCell(
        cellIdentifier: ObjectIdentifier, owner: StateMountOwner, slot: StatePropertySlot,
        revision: UInt64, isMaterializationCurrent: () -> Bool
    ) -> Bool {
        guard observationConstructionRevision == revision, isMaterializationCurrent(), let registry,
            owner.hasObservationInstallationAuthority(in: registry)
        else { return false }
        let committed = registry.owners
        let maps = ObservationMaps(
            candidates: candidates, claimedSlots: claimedSlots, provisionalCells: provisionalCells)
        let committedCells = owner.cells
        defer { withExtendedLifetime((committed, maps, committedCells)) {} }
        guard
            observationAnchorIsCurrent(
                in: committed,
                isCurrent: {
                    self.observationConstructionRevision == revision && isMaterializationCurrent()
                }),
            observationConstructionRevision == revision, isMaterializationCurrent()
        else { return false }
        let candidate = maps.candidates[
            owner.identity, while: { self.observationConstructionRevision == revision && isMaterializationCurrent() }
        ]
        guard observationConstructionRevision == revision, isMaterializationCurrent(), candidate === owner else {
            return false
        }
        let claimed =
            maps.claimedSlots[
                owner.identity,
                while: { self.observationConstructionRevision == revision && isMaterializationCurrent() }
            ]?.contains(slot) == true
        guard observationConstructionRevision == revision, isMaterializationCurrent(), claimed else { return false }
        let resolved =
            maps.provisionalCells[
                owner.identity,
                while: { self.observationConstructionRevision == revision && isMaterializationCurrent() }
            ]?[slot] ?? committedCells[slot]
        guard observationConstructionRevision == revision, isMaterializationCurrent(), let resolved else {
            return false
        }
        return ObjectIdentifier(resolved) == cellIdentifier && owner.hasObservationInstallationAuthority(in: registry)
    }

    /// Callers supply only scalar epoch/materialization checks and a pinned
    /// membership snapshot. No live authored-key dictionary is read here.
    private func observationAnchorIsCurrent(
        in committed: ManagedKeyedMap<RetainedViewIdentity, StateMountOwner>, isCurrent: () -> Bool
    ) -> Bool {
        guard isCurrent() else { return false }
        guard let anchorGeneration else { return true }
        guard let anchor, anchor.generation == anchorGeneration, anchor.isLive else { return false }
        let isMember = committed[anchor.identity, while: isCurrent] === anchor
        return isCurrent() && isMember && anchor.isLive
    }

    private func retireRejectedObservation(in maps: ObservationMaps, registry: StateMountRegistry) {
        let canDeferCleanup = phase != .finished && registry.activeEpoch === self
        for cell in maps.createdCells {
            cell.beginRetirement()
            if canDeferCleanup {
                registry.retiringCells[ObjectIdentifier(cell)] = cell
            } else {
                cell.finishRetirement()
            }
        }
        if let owner = maps.createdOwner {
            owner.beginRetirement()
            if canDeferCleanup {
                registry.retiringOwners[owner.generation] = owner
            } else {
                owner.finishRetirement()
            }
        }
    }

    /// Read-only fallback for a materialized adapter whose snapshot was
    /// rejected. Candidate-map changes do not change committed membership;
    /// closing or leaving this epoch still rejects after every lookup.
    func committedSyntheticObservation<Observation>(
        at identity: RetainedViewIdentity, as type: Observation.Type, isMaterializationCurrent: () -> Bool = { true }
    ) -> MountedObservationPreservation<Observation>? {
        let result = lookupCommittedObservation(
            at: identity, as: type, isMaterializationCurrent: isMaterializationCurrent)
        guard observationConstructionRevision != nil, isMaterializationCurrent() else { return nil }
        return result
    }

    @inline(never)
    private func lookupCommittedObservation<Observation>(
        at identity: RetainedViewIdentity, as _: Observation.Type, isMaterializationCurrent: () -> Bool
    ) -> MountedObservationPreservation<Observation>? {
        guard observationConstructionRevision != nil, isMaterializationCurrent(), let registry else { return nil }
        let committed = registry.owners
        defer { withExtendedLifetime(committed) {} }
        guard
            observationAnchorIsCurrent(
                in: committed,
                isCurrent: {
                    self.observationConstructionRevision != nil && isMaterializationCurrent()
                }),
            observationConstructionRevision != nil, isMaterializationCurrent(),
            includes(
                identity, isCurrent: { self.observationConstructionRevision != nil && isMaterializationCurrent() }),
            observationConstructionRevision != nil, isMaterializationCurrent()
        else { return nil }
        let owner = committed[
            identity, while: { self.observationConstructionRevision != nil && isMaterializationCurrent() }
        ]
        guard observationConstructionRevision != nil, isMaterializationCurrent(), let owner, owner.isLive else {
            return nil
        }
        let slot = StatePropertySlot(concreteTypes: [ObjectIdentifier(Observation.self)])
        let committedCells = owner.cells
        defer { withExtendedLifetime(committedCells) {} }
        guard let cell = committedCells[slot] as? MountedStateCell<Observation>, cell.isLiveObservation(of: owner),
            observationConstructionRevision != nil, isMaterializationCurrent()
        else { return nil }
        return MountedObservationPreservation(owner: owner, cell: cell, epoch: self)
    }

    /// Surviving materialization markers enter here immediately before
    /// adoption. Membership and typed-cell validation invoke no authored
    /// Hashable, equality, seed, reducer, or observer action.
    fileprivate func preserveSyntheticObservation<Observation>(
        owner: StateMountOwner, cell: MountedStateCell<Observation>
    ) -> Bool {
        guard observationConstructionRevision != nil, let registry, owner.isLive,
            registry.owners.values.contains(where: { $0 === owner })
        else { return false }
        let slot = StatePropertySlot(concreteTypes: [ObjectIdentifier(Observation.self)])
        guard let current = owner.cells[slot] as? MountedStateCell<Observation>, current === cell,
            cell.isLiveObservation(of: owner), observationConstructionRevision != nil
        else { return false }
        preservedObservationOwners[owner.generation] = owner
        preservedObservationCells.insert(ObjectIdentifier(cell))
        return true
    }

    private func candidatesWithPreservedObservations() -> [(identity: RetainedViewIdentity, owner: StateMountOwner)] {
        let candidates = self.candidates.map { (identity: $0.key, owner: $0.value) }
        let identifiers = Set(candidates.map { ObjectIdentifier($0.owner) })
        let preserved = preservedObservationOwners.values.filter { !identifiers.contains(ObjectIdentifier($0)) }
        return candidates + preserved.map { (identity: $0.identity, owner: $0) }
    }

    fileprivate func resolve<Value>(
        owner: StateMountOwner, slot: StatePropertySlot, seed: () -> Value
    ) -> MountedStateCell<Value> {
        precondition(isInstalling(owner), "State owner is not part of this build")
        claimedSlots[owner.identity, default: []].insert(slot)
        if let cell = provisionalCells[owner.identity]?[slot] ?? owner.cells[slot] {
            guard let typed = cell as? MountedStateCell<Value> else {
                preconditionFailure("State property declaration changed its value type without a new slot")
            }
            return typed
        }
        let value = seed()
        guard isInstalling(owner) else {
            // A future leaf's initializer can reenter or close the host. Do
            // not append ownership to an epoch that already finished.
            let cell = MountedStateCell(value: value, owner: owner)
            cell.finishRetirement()
            return cell
        }
        // An initializer can resolve this declaration recursively. Reuse its
        // result rather than leaving an untracked writable provisional cell.
        if let existing = provisionalCells[owner.identity]?[slot] ?? owner.cells[slot] {
            guard let typed = existing as? MountedStateCell<Value> else {
                preconditionFailure("Reentrant State initialization changed a declaration's value type")
            }
            return typed
        }
        let cell = MountedStateCell(value: value, owner: owner)
        provisionalCells[owner.identity, default: [:]][slot] = cell
        return cell
    }

    /// Object factories execute application code, unlike an ordinary State
    /// seed read. Reserve this declaration before calling the factory so a
    /// recursive build cannot initialize its unfinished object again.
    fileprivate func resolveObject<ObjectType: ObservableObject>(
        owner: StateMountOwner, slot: StatePropertySlot, seed: () -> ObjectType
    ) throws -> MountedStateCell<ObjectType> {
        if lazyOwners[owner.generation] != nil {
            return try resolveLazyOwnedObject(owner: owner, slot: slot, seed: seed)
        }
        if descriptorOwners[owner.generation] != nil {
            return try resolveDescriptorOwnedCell(owner: owner, slot: slot, isObjectFactory: true, seed: seed)
        }
        guard isInstalling(owner) else {
            throw DynamicPropertyInstaller.failure(
                .ownerUnavailable, type: StateObject<ObjectType>.self, at: slot,
                "The StateObject owner left its build before resolution")
        }
        claimedSlots[owner.identity, default: []].insert(slot)
        if let existing = provisionalCells[owner.identity]?[slot] ?? owner.cells[slot] {
            return try objectCell(existing, at: slot, as: ObjectType.self)
        }
        guard pendingObjectCreations[owner.generation, default: []].insert(slot).inserted else {
            // The initializer cannot manufacture the unfinished object. Even
            // if application code catches this diagnostic, do not adopt the
            // candidate that attempted the recursive declaration.
            supersede()
            throw DynamicPropertyInstaller.failure(
                .recursiveInitialization, type: StateObject<ObjectType>.self, at: slot,
                "The same mounted StateObject declaration is already running its factory")
        }
        defer {
            pendingObjectCreations[owner.generation]?.remove(slot)
            if pendingObjectCreations[owner.generation]?.isEmpty == true {
                pendingObjectCreations.removeValue(forKey: owner.generation)
            }
        }

        let object = seed()
        guard isInstalling(owner) else {
            throw DynamicPropertyInstaller.failure(
                .ownerUnavailable, type: StateObject<ObjectType>.self, at: slot,
                "The StateObject factory closed, superseded, or abandoned its original build")
        }
        if let existing = provisionalCells[owner.identity]?[slot] ?? owner.cells[slot] {
            return try objectCell(existing, at: slot, as: ObjectType.self)
        }
        let cell = MountedStateCell(value: object, owner: owner)
        provisionalCells[owner.identity, default: [:]][slot] = cell
        return cell
    }

    private func objectCell<ObjectType: ObservableObject>(
        _ cell: any AnyMountedStateCell, at slot: StatePropertySlot, as type: ObjectType.Type
    ) throws -> MountedStateCell<ObjectType> {
        guard let typed = cell as? MountedStateCell<ObjectType> else {
            throw DynamicPropertyInstaller.failure(
                .changedPropertyType, type: StateObject<ObjectType>.self, at: slot,
                "The StateObject declaration changed its stored object type without a new slot")
        }
        return typed
    }

    fileprivate func isInstalled<Value>(
        cell: MountedStateCell<Value>, owner: StateMountOwner, slot: StatePropertySlot
    ) -> Bool {
        if let acquisition = lazyOwners[owner.generation] {
            return acquisition.owner === owner && acquisition.isCurrent
                && acquisition.cells[slot].map { ObjectIdentifier($0) == ObjectIdentifier(cell) } == true
        }
        if let acquisition = descriptorOwners[owner.generation] {
            return acquisition.owner === owner && acquisition.isCurrent
                && acquisition.cells[slot].map { ObjectIdentifier($0) == ObjectIdentifier(cell) } == true
        }
        guard isInstalling(owner), claimedSlots[owner.identity]?.contains(slot) == true,
            let resolved = provisionalCells[owner.identity]?[slot] ?? owner.cells[slot]
        else { return false }
        return ObjectIdentifier(resolved) == ObjectIdentifier(cell)
    }

    /// An omitted evaluation does not remove a still-declared subtree.
    func preserveDeclaredSubtree(at prefix: RetainedViewIdentity) {
        preserveDeclaredScope(StateMountDeclarationScope(prefix: prefix))
    }

    func preserveDeclaredScope(_ scope: StateMountDeclarationScope) {
        guard phase == .constructing, includes(scope.prefix) else { return }
        preservedScopes.append(scope)
    }

    /// Measurement can build values that are not selected for adoption. Drop
    /// their new cells while optionally keeping a previously declared mount.
    func discardUnadoptedSubtree(at prefix: RetainedViewIdentity, preserveCommitted: Bool) {
        guard phase == .constructing, includes(prefix), let registry else { return }
        let identities = candidates.keys.filter { $0.segments.starts(with: prefix.segments) }
        for identity in identities {
            for cell in (provisionalCells.removeValue(forKey: identity) ?? [:]).values {
                cell.finishRetirement()
            }
            if let owner = candidates.removeValue(forKey: identity), registry.owners[identity] !== owner {
                owner.finishRetirement()
            }
            claimedSlots.removeValue(forKey: identity)
        }
        if preserveCommitted { preserveDeclaredSubtree(at: prefix) }
    }

    /// Must precede in-place reconciliation, so departing callbacks cannot
    /// write either the outgoing generation or a new owner at the same path.
    @discardableResult
    func prepareForAdoption() -> Bool {
        if !descriptorOwners.isEmpty, !prepareDescriptorClaimsForOrdinaryAdoption() { return false }
        guard canAdopt, pendingObjectCreations.isEmpty, let registry else { return false }
        phase = .adopting
        lazyLifetime.stopConstruction()
        for (identity, owner) in registry.owners where includes(identity) && !keeps(identity, owner: owner) {
            owner.beginRetirement()
            registry.retiringOwners[owner.generation] = owner
            preparedOwnerGenerations.insert(owner.generation)
        }
        for (identity, owner) in candidatesWithPreservedObservations() {
            let claimed = claimedSlots[identity] ?? []
            for (slot, cell) in owner.cells
            where !claimed.contains(slot) && !preservedObservationCells.contains(ObjectIdentifier(cell)) {
                cell.beginRetirement()
                registry.retiringCells[ObjectIdentifier(cell)] = cell
                preparedCellIdentifiers.insert(ObjectIdentifier(cell))
            }
        }
        return true
    }

    /// Once adoption begins, callers serialize reentry rather than attempting
    /// to roll back an already-mutated retained tree.
    func commitAdoption() {
        guard phase == .adopting, let registry, registry.activeEpoch === self else { return }
        guard !registry.isClosed else {
            finishAbandonedBuild(in: registry)
            return
        }
        registry.lastManagedAdoption = nil
        publishDescriptorCellsForOrdinaryAdoption()
        let removed = registry.owners.compactMap { identity, owner in
            includes(identity) && !keeps(identity, owner: owner) ? identity : nil
        }
        for identity in removed { registry.owners.removeValue(forKey: identity) }
        for (identity, owner) in candidatesWithPreservedObservations() {
            let claimed = claimedSlots[identity] ?? []
            owner.cells = owner.cells.filter {
                claimed.contains($0.key) || preservedObservationCells.contains(ObjectIdentifier($0.value))
            }
            for (slot, cell) in provisionalCells[identity] ?? [:] { owner.cells[slot] = cell }
            owner.activate()
            registry.owners[identity] = owner
        }
        didCommit = true
        phase = .finished
        lazyLifetime.finish()
        registry.activeEpoch = nil
        candidates.removeAll()
        provisionalCells.removeAll()
        preservedObservationOwners.removeAll()
        preservedObservationCells.removeAll()
        pendingObjectCreations.removeAll()
    }

    /// The caller may abandon a prepared membership before mutating any
    /// retained node. Restore revoked permissions, never application Values.
    /// After node adoption starts, only explicit host teardown can abandon.
    func abort() {
        guard phase != .finished, let registry, registry.activeEpoch === self else { return }
        if phase == .adopting, !registry.isClosed {
            for generation in preparedOwnerGenerations {
                registry.retiringOwners.removeValue(forKey: generation)?.cancelRetirement()
            }
            for identifier in preparedCellIdentifiers {
                registry.retiringCells.removeValue(forKey: identifier)?.cancelRetirement()
            }
        }
        finishAbandonedBuild(in: registry)
    }

    fileprivate func revokeWrites() {
        superseded = true
        lazyLifetime.stopConstruction()
        for owner in candidates.values { owner.beginRetirement() }
        for cells in provisionalCells.values {
            for cell in cells.values { cell.beginRetirement() }
        }
        for proposal in lazyCellProposals.values where proposal.cell.ownedSlotGeneration != nil {
            if proposal.owner.isLive { continue }
            proposal.cell.beginRetirement()
        }
    }

    fileprivate func finishAbandonedBuild(in registry: StateMountRegistry) {
        retireAbandonedManagedCells(in: registry)
        // A stopped managed build must not enter authored Hashable again while
        // unwinding. Owner reference identity is sufficient for this cleanup.
        let committedOwners = Array(registry.owners.values)
        for owner in candidates.values where !committedOwners.contains(where: { $0 === owner }) {
            owner.finishRetirement()
        }
        for cells in provisionalCells.values {
            for cell in cells.values { cell.finishRetirement() }
        }
        phase = .finished
        lazyLifetime.finish()
        registry.activeEpoch = nil
        candidates.removeAll()
        provisionalCells.removeAll()
        preservedObservationOwners.removeAll()
        preservedObservationCells.removeAll()
        pendingObjectCreations.removeAll()
        if registry.isClosed { registry.finishPendingRetirements() }
    }

    private func includes(_ identity: RetainedViewIdentity) -> Bool {
        guard let prefix else { return true }
        return identity.segments.starts(with: prefix.segments)
    }

    private func includes(_ identity: RetainedViewIdentity, isCurrent: () -> Bool) -> Bool {
        guard isCurrent() else { return false }
        guard let prefix else { return true }
        return identity.checkedHasPrefix(prefix, isCurrent: isCurrent) == true
    }

    private func keeps(_ identity: RetainedViewIdentity, owner: StateMountOwner) -> Bool {
        candidates[identity] != nil || preservedObservationOwners[owner.generation] === owner
            || preservedScopes.contains { $0.contains(identity) }
    }
}

/// One lookup may advance only by its own explicitly counted publications.
/// The long-lived admission remains independent of legitimate earlier writes.
@MainActor
final class LazyListLookupReceipt {
    private let lifetime: LazyListLookupLifetime
    private let epoch: StateMountEpoch
    private var expected: LazyListLookupRevision
    private var rejected = false

    fileprivate init(lifetime: LazyListLookupLifetime, epoch: StateMountEpoch, revision: LazyListLookupRevision) {
        self.lifetime = lifetime
        self.epoch = epoch
        expected = revision
    }

    var isCurrent: Bool {
        guard !rejected, lifetime.isCurrent, epoch.lazyLookupRevision == expected else {
            rejected = true
            return false
        }
        return true
    }

    /// Called immediately before callback-free assignments with every old map
    /// pinned. The caller must release those pins before its final isCurrent.
    fileprivate func allowPublication(observations: UInt64 = 0, activity: UInt64 = 0, declarations: UInt64 = 0) -> Bool
    {
        guard isCurrent, expected.observations <= UInt64.max - observations,
            expected.activity <= UInt64.max - activity, expected.declarations <= UInt64.max - declarations
        else {
            rejected = true
            return false
        }
        expected = LazyListLookupRevision(
            observations: expected.observations + observations, activity: expected.activity + activity,
            declarations: expected.declarations + declarations)
        return true
    }
}

fileprivate struct LazyListLookupRevision: Equatable {
    let observations: UInt64
    let activity: UInt64
    let declarations: UInt64
}

@MainActor
private final class LazyListOwnerAcquisition {
    let owner: StateMountOwner
    let attribution: LazyListViewAttribution
    var owningSlots: Set<StatePropertySlot>?
    var ownedInstallation: ManagedOwnedInstallation?
    var cells: [StatePropertySlot: any AnyMountedStateCell] = [:]
    var isRejected = false

    init(owner: StateMountOwner, attribution: LazyListViewAttribution) {
        self.owner = owner
        self.attribution = attribution
    }

    var isCurrent: Bool { !isRejected && owner.lazyLifetime.isAvailable && attribution.isCurrent }
}

@MainActor
private final class LazyListComponentConstructionAttempt {
    let identity: RetainedViewIdentity
    let attribution: LazyListViewAttribution
    private(set) var isRejected = false

    init(identity: RetainedViewIdentity, attribution: LazyListViewAttribution) {
        self.identity = identity
        self.attribution = attribution
    }

    var isCurrent: Bool { !isRejected && attribution.isCurrent }
    func reject() {
        isRejected = true
        attribution.admission.reject()
    }
}

@MainActor
final class LazyListDiscardReceipt {
    fileprivate let scope: StateMountDeclarationScope
    fileprivate let lifetime: LazyListEpochLifetime
    fileprivate private(set) var isActive = true

    fileprivate init(prefix: RetainedViewIdentity, lifetime: LazyListEpochLifetime) {
        scope = StateMountDeclarationScope(prefix: prefix)
        self.lifetime = lifetime
    }

    fileprivate func finish() { isActive = false }
}

@MainActor
private struct LazyListPreservedDeclarationScope {
    let scope: StateMountDeclarationScope
    let attribution: LazyListViewAttribution
}

@MainActor
private final class LazyListCellProposal {
    let owner: StateMountOwner
    let slot: StatePropertySlot
    let cell: any AnyMountedStateCell
    let attribution: LazyListViewAttribution
    let ownership: LazyListCellOwnership

    init(
        owner: StateMountOwner, slot: StatePropertySlot, cell: any AnyMountedStateCell,
        attribution: LazyListViewAttribution, ownership: LazyListCellOwnership
    ) {
        self.owner = owner
        self.slot = slot
        self.cell = cell
        self.attribution = attribution
        self.ownership = ownership
    }
}

@MainActor
private final class DescriptorComponentConstructionAttempt {
    let identity: RetainedViewIdentity
    let receipt: DescriptorResolutionReceipt

    init(identity: RetainedViewIdentity, receipt: DescriptorResolutionReceipt) {
        self.identity = identity
        self.receipt = receipt
    }
}

@MainActor
private final class DescriptorOwnerAcquisition {
    let owner: StateMountOwner
    let attribution: RetainedDescriptorComponentAttribution
    let receipt: DescriptorResolutionReceipt
    var owningSlots: Set<StatePropertySlot>?
    var ownedInstallation: ManagedOwnedInstallation?
    var cells: [StatePropertySlot: any AnyMountedStateCell] = [:]

    init(owner: StateMountOwner, receipt: DescriptorResolutionReceipt) {
        self.owner = owner
        self.receipt = receipt
        attribution = receipt.native
    }

    var isCurrent: Bool { owner.lazyLifetime.isAvailable && receipt.isCurrent }
}

@MainActor
private final class ManagedOwnedInstallation {
    let receipt: RetainedOwnedComponentReceipt
    let slots: [StatePropertySlot: RetainedOwnedSlotGenerationID]

    init(receipt: RetainedOwnedComponentReceipt, slots: [StatePropertySlot: RetainedOwnedSlotGenerationID]) {
        self.receipt = receipt
        self.slots = slots
    }
}

private struct ManagedPreservedOwnerKey: Hashable {
    let ownerGeneration: UInt64
    let containingComponent: ObjectIdentifier
}

@MainActor
private final class ManagedPreservedOwner {
    let owner: StateMountOwner
    let cells: [StatePropertySlot: any AnyMountedStateCell]
    let installation: ManagedOwnedInstallation
    let logicalRow: LazyListLogicalRow?

    init(
        owner: StateMountOwner, cells: [StatePropertySlot: any AnyMountedStateCell],
        installation: ManagedOwnedInstallation, logicalRow: LazyListLogicalRow?
    ) {
        self.owner = owner
        self.cells = cells
        self.installation = installation
        self.logicalRow = logicalRow
    }
}

@MainActor
private final class DescriptorCellProposal {
    let owner: StateMountOwner
    let slot: StatePropertySlot
    let cell: any AnyMountedStateCell
    let acquisition: DescriptorOwnerAcquisition
    let ownership: DescriptorCellOwnership

    init(
        owner: StateMountOwner, slot: StatePropertySlot, cell: any AnyMountedStateCell,
        acquisition: DescriptorOwnerAcquisition, ownership: DescriptorCellOwnership
    ) {
        self.owner = owner
        self.slot = slot
        self.cell = cell
        self.acquisition = acquisition
        self.ownership = ownership
    }
}

@MainActor
private struct DescriptorPreservedDeclarationScope {
    let scope: StateMountDeclarationScope
    let receipt: DescriptorResolutionReceipt
}

@MainActor
final class LazyListStateSelectionPins {
    fileprivate let owners: ManagedKeyedMap<RetainedViewIdentity, StateMountOwner>
    fileprivate let cells: [ObjectIdentifier: any AnyMountedStateCell]
    fileprivate let declarations: ManagedKeyedMap<RetainedViewIdentity, LazyListCommittedDeclaration>
    fileprivate let candidates: ManagedKeyedMap<RetainedViewIdentity, StateMountOwner>
    fileprivate let provisionalCells:
        ManagedKeyedMap<RetainedViewIdentity, [StatePropertySlot: any AnyMountedStateCell]>
    fileprivate let slotMaps: [UInt64: [StatePropertySlot: any AnyMountedStateCell]]
    fileprivate var coveredOwnerGenerations: Set<UInt64> = []

    fileprivate init(
        owners: ManagedKeyedMap<RetainedViewIdentity, StateMountOwner>,
        declarations: ManagedKeyedMap<RetainedViewIdentity, LazyListCommittedDeclaration>,
        candidates: ManagedKeyedMap<RetainedViewIdentity, StateMountOwner>,
        provisionalCells: ManagedKeyedMap<RetainedViewIdentity, [StatePropertySlot: any AnyMountedStateCell]>,
        extraCells: [any AnyMountedStateCell] = []
    ) {
        self.owners = owners
        self.declarations = declarations
        self.candidates = candidates
        self.provisionalCells = provisionalCells
        var cells: [ObjectIdentifier: any AnyMountedStateCell] = [:]
        var slotMaps: [UInt64: [StatePropertySlot: any AnyMountedStateCell]] = [:]
        for owner in owners.values {
            slotMaps[owner.generation] = owner.cells
            for cell in owner.cells.values { cells[ObjectIdentifier(cell)] = cell }
        }
        for slots in provisionalCells.values {
            for cell in slots.values { cells[ObjectIdentifier(cell)] = cell }
        }
        for cell in extraCells { cells[ObjectIdentifier(cell)] = cell }
        self.cells = cells
        self.slotMaps = slotMaps
    }
}

@MainActor
private final class ManagedCellSelection {
    let owner: StateMountOwner
    let slot: StatePropertySlot
    let cell: any AnyMountedStateCell
    let lazyOwnership: LazyListCellOwnership?
    let descriptorOwnership: DescriptorCellOwnership?
    let ownedInstallation: ManagedOwnedInstallation?
    let ownedGeneration: RetainedOwnedSlotGenerationID?
    let lazyContribution: RetainedLazyListContributionReceipt?
    let descriptorContribution: RetainedDescriptorContributionReceipt?

    init(
        owner: StateMountOwner, slot: StatePropertySlot, cell: any AnyMountedStateCell,
        lazyOwnership: LazyListCellOwnership? = nil, descriptorOwnership: DescriptorCellOwnership? = nil,
        ownedInstallation: ManagedOwnedInstallation? = nil, ownedGeneration: RetainedOwnedSlotGenerationID? = nil,
        lazyContribution: RetainedLazyListContributionReceipt? = nil,
        descriptorContribution: RetainedDescriptorContributionReceipt? = nil
    ) {
        self.owner = owner
        self.slot = slot
        self.cell = cell
        self.lazyOwnership = lazyOwnership
        self.descriptorOwnership = descriptorOwnership
        self.ownedInstallation = ownedInstallation
        self.ownedGeneration = ownedGeneration
        self.lazyContribution = lazyContribution
        self.descriptorContribution = descriptorContribution
    }

    var isCurrent: Bool {
        guard owner.lazyLifetime.isAvailable else { return false }
        if let ownedGeneration {
            return ownedInstallation?.receipt.hasAcceptedOwnership(for: ownedGeneration) == true
        }
        if let lazyContribution { return lazyContribution.isActive }
        return descriptorContribution?.isActive == true
    }

    func publish() {
        if let ownedInstallation, let ownedGeneration {
            cell.bindOwnedLocation(ownedInstallation.receipt, slot: ownedGeneration)
        }
        if let lazyOwnership { cell.setLazyOwnership(lazyOwnership, contribution: lazyContribution) }
        if let descriptorOwnership {
            cell.setDescriptorOwnership(descriptorOwnership, contribution: descriptorContribution)
        }
    }
}

@MainActor
private final class ManagedStatePublication {
    let disposition: RetainedLazyListAdoptionDisposition
    let pins: LazyListStateSelectionPins
    let owners: ManagedKeyedMap<RetainedViewIdentity, StateMountOwner>
    let slots: [UInt64: [StatePropertySlot: any AnyMountedStateCell]]
    let selectedCells: [ObjectIdentifier: ManagedCellSelection]
    let declaredOwners: [UInt64: RetainedOwnedComponentReceipt]
    let declarations: ManagedKeyedMap<RetainedViewIdentity, LazyListCommittedDeclaration>
    let acceptedOwned: Set<ObjectIdentifier>
    let acceptedSynthetic: Set<ObjectIdentifier>
    let unchangedOwned: Set<ObjectIdentifier>
    let unchangedSynthetic: Set<ObjectIdentifier>
    let retired: Set<ObjectIdentifier>
    let acceptedMemberships: Set<ObjectIdentifier>

    init(
        disposition: RetainedLazyListAdoptionDisposition, pins: LazyListStateSelectionPins,
        owners: ManagedKeyedMap<RetainedViewIdentity, StateMountOwner>,
        slots: [UInt64: [StatePropertySlot: any AnyMountedStateCell]],
        selectedCells: [ObjectIdentifier: ManagedCellSelection],
        declaredOwners: [UInt64: RetainedOwnedComponentReceipt],
        declarations: ManagedKeyedMap<RetainedViewIdentity, LazyListCommittedDeclaration>,
        acceptedOwned: Set<ObjectIdentifier>, acceptedSynthetic: Set<ObjectIdentifier>,
        unchangedOwned: Set<ObjectIdentifier>, unchangedSynthetic: Set<ObjectIdentifier>,
        retired: Set<ObjectIdentifier>, acceptedMemberships: Set<ObjectIdentifier>
    ) {
        self.disposition = disposition
        self.pins = pins
        self.owners = owners
        self.slots = slots
        self.selectedCells = selectedCells
        self.declaredOwners = declaredOwners
        self.declarations = declarations
        self.acceptedOwned = acceptedOwned
        self.acceptedSynthetic = acceptedSynthetic
        self.unchangedOwned = unchangedOwned
        self.unchangedSynthetic = unchangedSynthetic
        self.retired = retired
        self.acceptedMemberships = acceptedMemberships
    }
}

@MainActor
final class LazyListStateAdoptionSelection {
    let attempt: RetainedLazyListAttemptID
    let acceptedOwnedSlots: Set<ObjectIdentifier>
    let acceptedSyntheticCells: Set<ObjectIdentifier>
    let unchangedOwnedSlots: Set<ObjectIdentifier>
    let unchangedSyntheticCells: Set<ObjectIdentifier>
    let retiredCells: Set<ObjectIdentifier>
    let acceptedGroups: Set<ObjectIdentifier>
    let acceptedEmptyGroups: Set<ObjectIdentifier>
    let unchangedGroups: Set<ObjectIdentifier>
    let retiredGroups: Set<ObjectIdentifier>
    let acceptedOrdinaryGroups: Set<ObjectIdentifier>
    let acceptedEmptyOrdinaryGroups: Set<ObjectIdentifier>
    let retiredOrdinaryGroups: Set<ObjectIdentifier>
    fileprivate let acceptedMemberships: Set<ObjectIdentifier>
    private let disposition: RetainedLazyListAdoptionDisposition
    private let pins: LazyListStateSelectionPins

    fileprivate init(
        disposition: RetainedLazyListAdoptionDisposition, pins: LazyListStateSelectionPins,
        acceptedOwnedSlots: Set<ObjectIdentifier>, acceptedSyntheticCells: Set<ObjectIdentifier>,
        unchangedOwnedSlots: Set<ObjectIdentifier>, unchangedSyntheticCells: Set<ObjectIdentifier>,
        retiredCells: Set<ObjectIdentifier>, acceptedMemberships: Set<ObjectIdentifier>
    ) {
        attempt = disposition.attempt
        self.disposition = disposition
        self.pins = pins
        self.acceptedOwnedSlots = acceptedOwnedSlots
        self.acceptedSyntheticCells = acceptedSyntheticCells
        self.unchangedOwnedSlots = unchangedOwnedSlots
        self.unchangedSyntheticCells = unchangedSyntheticCells
        self.retiredCells = retiredCells
        self.acceptedMemberships = acceptedMemberships
        acceptedGroups = Set(disposition.acceptedGroups.map { ObjectIdentifier($0.proposal.group) })
        acceptedEmptyGroups = Set(disposition.acceptedEmptyGroups.map { ObjectIdentifier($0.proposal.group) })
        unchangedGroups = Set(disposition.unchanged.map { ObjectIdentifier($0.receipt.group) })
        retiredGroups = Set(
            disposition.acceptedAbsences.map { ObjectIdentifier($0.previous.group) }
                + disposition.acceptedDepartures.flatMap { $0.contributions.map { ObjectIdentifier($0.group) } })
        acceptedOrdinaryGroups = Set(disposition.acceptedOrdinaryGroups.map { ObjectIdentifier($0.proposal.group) })
        acceptedEmptyOrdinaryGroups = Set(
            disposition.acceptedEmptyOrdinaryGroups.map { ObjectIdentifier($0.proposal.group) })
        retiredOrdinaryGroups = Set(disposition.absentOrdinary.map { ObjectIdentifier($0.previous.group) })
    }

    func contribution(for group: RetainedLazyListGroupID) -> RetainedLazyListContributionReceipt? {
        disposition.contribution(for: group)
    }

    func ordinaryContribution(for group: RetainedDescriptorGroupID) -> RetainedDescriptorContributionReceipt? {
        disposition.contribution(for: group)
    }
}

extension StateMountRegistry {
    fileprivate func lazyDeclarationMapsDidChange() {
        guard let revision = lazyDeclarationRevision, revision < .max else {
            lazyDeclarationRevision = nil
            return
        }
        lazyDeclarationRevision = revision + 1
    }

    func commitLazySparseRow(
        _ reservation: LazyListSelectedRowReservation, selection: LazyListStateAdoptionSelection
    ) -> Bool {
        guard !isClosed, activeEpoch == nil, lastManagedAdoption === selection.attempt,
            let row = reservation.boundRow, row.id === reservation.membership, row.isDeclared,
            reservation.preparation.descriptor.scope.containsDeclaredDescriptor(
                reservation.preparation.descriptor.descriptor),
            selection.acceptedMemberships.contains(ObjectIdentifier(row.id))
        else { return false }
        guard let published = publishLazySparseRow(reservation, row: row, selection: selection) else { return false }
        return !isClosed && activeEpoch == nil && lastManagedAdoption === selection.attempt
            && lazyDeclarationRevision == published && row.isDeclared
            && reservation.preparation.descriptor.scope.containsDeclaredDescriptor(
                reservation.preparation.descriptor.descriptor)
    }

    @inline(never)
    private func publishLazySparseRow(
        _ reservation: LazyListSelectedRowReservation, row: LazyListLogicalRow,
        selection: LazyListStateAdoptionSelection
    ) -> UInt64? {
        guard let revision = lazyDeclarationRevision, revision < .max else { return nil }
        let declarations = lazyDeclarations
        let owners = self.owners
        let oldSlots = row.ownedSlots
        defer { withExtendedLifetime((declarations, owners, oldSlots)) {} }
        let descriptorID: RetainedLazyListLogicalDeclarationID
        switch reservation.source {
        case .proposed(let proposal): descriptorID = proposal.id
        case .committed(let declaration): descriptorID = declaration.id
        }
        guard !isClosed, activeEpoch == nil, lastManagedAdoption === selection.attempt,
            lazyDeclarationRevision == revision, row.isDeclared,
            let declaration = declarations.values.first(where: { $0.id === descriptorID }),
            declaration.logicalScope === reservation.preparation.descriptor.scope,
            declaration.logicalScope.isLogicallyLive
        else { return nil }
        let oldRows = declaration.sparseRows
        var rows = oldRows
        defer { withExtendedLifetime((oldRows, rows)) {} }
        func isCurrent() -> Bool {
            !self.isClosed && self.activeEpoch == nil && self.lastManagedAdoption === selection.attempt
                && self.lazyDeclarationRevision == revision && row.isDeclared
                && declaration.logicalScope.containsDeclaredDescriptor(declaration.id)
        }
        let previous = rows[reservation.key, while: isCurrent]
        guard isCurrent(), previous == nil || previous === row
        else { return nil }
        rows[reservation.key, while: isCurrent] = row
        guard isCurrent() else { return nil }
        var owned: [ObjectIdentifier: LazyListOwnedSlotRecord] = [:]
        for owner in owners.values {
            for (slot, cell) in owner.cells {
                guard case .owned(let logical, _) = cell.lazyOwnership,
                    logical === row.logicalReceipt, cell.hasLiveManagedPermission
                else { continue }
                let identifier = ObjectIdentifier(cell)
                owned[identifier] =
                    oldSlots[identifier]
                    ?? LazyListOwnedSlotRecord(owner: owner, slot: slot, cellIdentifier: identifier)
            }
        }
        guard isCurrent() else { return nil }
        declaration.publishSparseRows(rows)
        row.publishOwnedSlots(owned)
        lazyDeclarationMapsDidChange()
        return revision + 1
    }

    func stageLazyMembership(
        at listIdentity: RetainedViewIdentity, metadata: RetainedLazyListMetadata,
        parent: LazyListLogicalRow?, in epoch: StateMountEpoch, receipt: LazyListDescriptorResolutionReceipt
    ) -> LazyListMembershipProposal? {
        guard activeEpoch === epoch, receipt.epoch === epoch, receipt.isCurrent,
            metadata.generation.isCurrent, let lookup = receipt.beginLookup()
        else { return nil }
        let proposal = makeLazyMembershipProposal(
            at: listIdentity, metadata: metadata, parent: parent, in: epoch, receipt: receipt, lookup: lookup)
        guard lookup.isCurrent, metadata.generation.isCurrent, let proposal else { return nil }
        return proposal
    }

    func beginLazySubtreeBuild(
        owner: StateMountOwner, contentPrefix: RetainedViewIdentity,
        originalActivity: RetainedLazyListContributionReceipt
    ) -> StateMountEpoch? {
        guard !isClosed, activeEpoch == nil, owner.isLive, originalActivity.isActive else { return nil }
        let accepted = validateLazySubtreeOwner(owner, prefix: contentPrefix, activity: originalActivity)
        guard accepted, !isClosed, activeEpoch == nil, owner.isLive, originalActivity.isActive,
            let epoch = beginBuild(prefix: contentPrefix, anchor: owner)
        else { return nil }
        epoch.lazyBoundaryActivity = originalActivity
        return epoch
    }

    @inline(never)
    private func validateLazySubtreeOwner(
        _ owner: StateMountOwner, prefix: RetainedViewIdentity, activity: RetainedLazyListContributionReceipt
    ) -> Bool {
        let original = owners
        defer { withExtendedLifetime(original) {} }
        guard !isClosed, activeEpoch == nil, activity.isActive else { return false }
        let current = original[
            owner.identity, while: { !self.isClosed && self.activeEpoch == nil && activity.isActive && owner.isLive }
        ]
        guard !isClosed, activeEpoch == nil, activity.isActive, current === owner, owner.isLive else { return false }
        guard prefix.segments.count > owner.identity.segments.count else { return false }
        let included =
            prefix.checkedHasPrefix(
                owner.identity,
                isCurrent: { !self.isClosed && self.activeEpoch == nil && activity.isActive && owner.isLive }
            ) == true
        return included && !isClosed && activeEpoch == nil && activity.isActive && owner.isLive
    }

    func beginDescriptorSubtreeBuild(
        owner: StateMountOwner, contentPrefix: RetainedViewIdentity,
        originalActivity: RetainedDescriptorContributionReceipt
    ) -> StateMountEpoch? {
        guard !isClosed, activeEpoch == nil, owner.isLive, originalActivity.isActive else { return nil }
        let accepted = validateDescriptorSubtreeOwner(owner, prefix: contentPrefix, activity: originalActivity)
        guard accepted, !isClosed, activeEpoch == nil, owner.isLive, originalActivity.isActive,
            let epoch = beginBuild(prefix: contentPrefix, anchor: owner)
        else { return nil }
        epoch.descriptorBoundaryActivity = originalActivity
        return epoch
    }

    @inline(never)
    private func validateDescriptorSubtreeOwner(
        _ owner: StateMountOwner, prefix: RetainedViewIdentity, activity: RetainedDescriptorContributionReceipt
    ) -> Bool {
        let original = owners
        defer { withExtendedLifetime(original) {} }
        guard !isClosed, activeEpoch == nil, activity.isActive else { return false }
        let current = original[
            owner.identity, while: { !self.isClosed && self.activeEpoch == nil && activity.isActive && owner.isLive }
        ]
        guard !isClosed, activeEpoch == nil, activity.isActive, current === owner, owner.isLive else { return false }
        guard prefix.segments.count > owner.identity.segments.count else { return false }
        let included =
            prefix.checkedHasPrefix(
                owner.identity,
                isCurrent: { !self.isClosed && self.activeEpoch == nil && activity.isActive && owner.isLive }
            ) == true
        return included && !isClosed && activeEpoch == nil && activity.isActive && owner.isLive
    }

    @inline(never)
    private func makeLazyMembershipProposal(
        at identity: RetainedViewIdentity, metadata: RetainedLazyListMetadata,
        parent: LazyListLogicalRow?, in epoch: StateMountEpoch,
        receipt: LazyListDescriptorResolutionReceipt, lookup: LazyListLookupReceipt
    ) -> LazyListMembershipProposal? {
        guard lookup.isCurrent, metadata.generation.isCurrent else { return nil }
        let declarations = lazyDeclarations
        defer { withExtendedLifetime(declarations) {} }
        let previous = declarations[identity, while: { lookup.isCurrent && metadata.generation.isCurrent }]
        guard lookup.isCurrent, metadata.generation.isCurrent else { return nil }
        let reusable = previous.flatMap {
            $0.logicalScope.isLogicallyLive && $0.parentRow === parent ? $0 : nil
        }
        let scope: RetainedLazyListLogicalMembershipScope
        if let reusable {
            scope = reusable.logicalScope
        } else {
            guard lookup.isCurrent,
                let created = RetainedLazyListLogicalMembershipScope(
                    in: receipt.nativeScope, parentRow: parent?.logicalReceipt)
            else { return nil }
            // Register before the first following authored key operation.
            // Both dictionaries use native identities and native-only values.
            lazyLogicalScopes[ObjectIdentifier(created)] = created
            epoch.lazyCreatedScopes[ObjectIdentifier(created)] = created
            scope = created
        }
        let oldRows = reusable?.sparseRows ?? [:]
        var retained: ManagedKeyedMap<LazyListQualifiedKey, LazyListLogicalRow> = [:]
        defer { withExtendedLifetime((oldRows, retained)) {} }
        for rowMetadata in metadata.rows {
            guard lookup.isCurrent, metadata.generation.isCurrent else { return nil }
            let key = LazyListQualifiedKey(rowMetadata)
            let old = oldRows[key, while: { lookup.isCurrent && metadata.generation.isCurrent }]
            guard lookup.isCurrent, metadata.generation.isCurrent else { return nil }
            if let old, old.isDeclared {
                retained[key, while: { lookup.isCurrent && metadata.generation.isCurrent && old.isDeclared }] = old
                guard lookup.isCurrent, metadata.generation.isCurrent else { return nil }
            }
        }
        let retainedIDs = Set(retained.values.map { ObjectIdentifier($0) })
        let removed = oldRows.values.filter { !retainedIDs.contains(ObjectIdentifier($0)) }
        guard lookup.isCurrent, metadata.generation.isCurrent else { return nil }
        let proposal = LazyListMembershipProposal(
            listIdentity: identity, metadata: metadata, scope: scope, parentRow: parent,
            retainedRows: retained, removedRows: removed, receipt: receipt)
        let oldMemberships = epoch.lazyMemberships
        var next = oldMemberships
        defer { withExtendedLifetime((oldMemberships, next)) {} }
        next[ObjectIdentifier(proposal.id)] = proposal
        guard metadata.generation.isCurrent, lookup.allowPublication(activity: 1) else { return nil }
        epoch.lazyMemberships = next
        return proposal
    }

    func resolveSelectedLazyRow(
        _ preparation: RetainedLazyListSelectedRowPreparation, in epoch: StateMountEpoch,
        receipt: LazyListSelectionResolutionReceipt, lookup suppliedLookup: LazyListLookupReceipt? = nil
    ) -> LazyListSelectedRowReservation? {
        guard activeEpoch === epoch, receipt.epoch === epoch,
            receipt.nativePreparation === preparation, receipt.isCurrent,
            let lookup = suppliedLookup ?? receipt.beginLookup(), lookup.isCurrent
        else { return nil }
        let reservation = resolveSelectedLazyRowSnapshot(preparation, in: epoch, receipt: receipt, lookup: lookup)
        guard lookup.isCurrent, let reservation else { return nil }
        return reservation
    }

    @inline(never)
    private func resolveSelectedLazyRowSnapshot(
        _ preparation: RetainedLazyListSelectedRowPreparation, in epoch: StateMountEpoch,
        receipt: LazyListSelectionResolutionReceipt, lookup: LazyListLookupReceipt
    ) -> LazyListSelectedRowReservation? {
        guard lookup.isCurrent else { return nil }
        let declarations = lazyDeclarations
        let memberships = epoch.lazyMemberships
        defer { withExtendedLifetime((declarations, memberships)) {} }
        let source: LazyListDeclarationSource
        let metadata: [RetainedLazyListRowMetadata]
        let proposedRows: ManagedKeyedMap<LazyListQualifiedKey, LazyListLogicalRow>
        let retainedRows: ManagedKeyedMap<LazyListQualifiedKey, LazyListLogicalRow>
        if let proposal = memberships[ObjectIdentifier(preparation.descriptor.descriptor)] {
            guard proposal.facadeProposal === preparation.descriptor.facadeProposal,
                proposal.logicalScope === preparation.descriptor.scope, proposal.receipt.isCurrent
            else { return nil }
            source = .proposed(proposal)
            metadata = proposal.completeMetadata
            proposedRows = proposal.proposedRows
            retainedRows = proposal.retainedRows
        } else {
            guard
                let committed = declarations.values.first(where: { $0.id === preparation.descriptor.descriptor }),
                committed.logicalScope === preparation.descriptor.scope, committed.logicalScope.isLogicallyLive
            else { return nil }
            source = .committed(committed)
            metadata = committed.completeMetadata
            proposedRows = [:]
            retainedRows = committed.sparseRows
        }
        defer { withExtendedLifetime((source, metadata, proposedRows, retainedRows)) {} }
        let index = preparation.request.sourceIndex
        guard lookup.isCurrent, metadata.indices.contains(index), metadata[index].sourceIndex == index,
            metadata[index].token == preparation.request.token
        else { return nil }
        let key = LazyListQualifiedKey(metadata[index])
        let proposed = proposedRows[key, while: { lookup.isCurrent }]
        guard lookup.isCurrent else { return nil }
        let existing = proposed ?? retainedRows[key, while: { lookup.isCurrent }]
        guard lookup.isCurrent else { return nil }
        let reservation = LazyListSelectedRowReservation(
            preparation: preparation, source: source, key: key, existingRow: existing, receipt: receipt)
        let old = epoch.lazyReservations
        var next = old
        defer { withExtendedLifetime((old, next)) {} }
        let identifier = ObjectIdentifier(preparation.resolutionID)
        guard next[identifier] == nil else { return nil }
        next[identifier] = reservation
        guard lookup.allowPublication(activity: 1) else { return nil }
        epoch.lazyReservations = next
        return reservation
    }
}

extension StateMountEpoch {
    /// The ordinary full-adoption route still uses its original membership
    /// algorithm. Only explicitly rejected descriptor candidates are removed
    /// from its provisional maps before that existing algorithm runs.
    @inline(never)
    private func prepareDescriptorClaimsForOrdinaryAdoption() -> Bool {
        guard let revision = observationConstructionRevision else { return false }
        let oldCandidates = candidates
        let oldClaims = claimedSlots
        let oldCells = provisionalCells
        let oldScopes = preservedScopes
        let acquisitions = Array(descriptorOwners.values)
        let declared = descriptorPreservedScopes
        var nextCandidates = oldCandidates
        var nextClaims = oldClaims
        var nextCells = oldCells
        var nextScopes = oldScopes
        defer { withExtendedLifetime((oldCandidates, oldClaims, oldCells, oldScopes, acquisitions, declared)) {} }
        for acquisition in acquisitions where !acquisition.isCurrent {
            guard observationConstructionRevision == revision else { return false }
            let identity = acquisition.owner.identity
            if nextCandidates[identity, while: { self.observationConstructionRevision == revision }]
                === acquisition.owner
            {
                nextCandidates.removeValue(
                    forKey: identity, while: { self.observationConstructionRevision == revision })
            }
            guard observationConstructionRevision == revision else { return false }
            nextClaims.removeValue(forKey: identity, while: { self.observationConstructionRevision == revision })
            guard observationConstructionRevision == revision else { return false }
            nextCells.removeValue(forKey: identity, while: { self.observationConstructionRevision == revision })
            guard observationConstructionRevision == revision else { return false }
        }
        for declaration in declared where declaration.receipt.isCurrent {
            guard observationConstructionRevision == revision else { return false }
            let included = includes(
                declaration.scope.prefix,
                isCurrent: { self.observationConstructionRevision == revision && declaration.receipt.isCurrent })
            guard observationConstructionRevision == revision, declaration.receipt.isCurrent else { return false }
            if included { nextScopes.append(declaration.scope) }
        }
        guard observationConstructionRevision == revision, revision <= UInt64.max - 3 else { return false }
        candidates = nextCandidates
        claimedSlots = nextClaims
        provisionalCells = nextCells
        preservedScopes = nextScopes
        return observationConstructionRevision == revision + 3
    }

    private func publishDescriptorCellsForOrdinaryAdoption() {
        for proposal in descriptorCellProposals.values {
            switch proposal.ownership {
            case .owned:
                guard let installation = proposal.acquisition.ownedInstallation,
                    let slot = installation.slots[proposal.slot],
                    installation.receipt.hasAcceptedDeclaration, installation.receipt.hasAcceptedOwnership(for: slot)
                else { continue }
                proposal.cell.bindOwnedLocation(installation.receipt, slot: slot)
                proposal.cell.setDescriptorOwnership(proposal.ownership, contribution: nil)
            case .synthetic(_, let group):
                guard let contribution = proposal.acquisition.attribution.contribution(for: group),
                    contribution.isActive
                else { continue }
                proposal.cell.setDescriptorOwnership(proposal.ownership, contribution: contribution)
            }
        }
        for acquisition in descriptorOwners.values {
            if let receipt = acquisition.ownedInstallation?.receipt, receipt.hasAcceptedDeclaration {
                acquisition.owner.ownedComponentReceipt = receipt
            }
        }
        for preserved in managedPreservedOwners.values where preserved.installation.receipt.hasAcceptedDeclaration {
            for (slot, cell) in preserved.cells {
                guard let generation = preserved.installation.slots[slot],
                    preserved.installation.receipt.hasAcceptedOwnership(for: generation)
                else { continue }
                cell.bindOwnedLocation(preserved.installation.receipt, slot: generation)
            }
            preserved.owner.ownedComponentReceipt = preserved.installation.receipt
        }
    }

    /// The snapshot pins existing values before the first retained mutation.
    /// There is deliberately no membership sweep or early revocation here:
    /// native accepted-field/declaration records supply those facts later.
    func prepareLazyAdoption(
        _ preparation: RetainedLazyListAdoptionPreparation, isCurrent: () -> Bool = { true }
    ) -> Bool {
        guard phase == .constructing, !superseded, lazyPreparation == nil,
            pendingObjectCreations.isEmpty, isCurrent(), let revision = lazyLookupRevision,
            let pins = prepareLazySelectionPins(preparation, revision: revision, isCurrent: isCurrent),
            lazyLookupRevision == revision, isCurrent()
        else { return false }
        lazyPreparation = preparation
        lazyPreparedPins = pins
        phase = .adopting
        lazyLifetime.stopConstruction()
        return true
    }

    @inline(never)
    private func prepareLazySelectionPins(
        _ preparation: RetainedLazyListAdoptionPreparation, revision: LazyListLookupRevision,
        isCurrent: () -> Bool
    ) -> LazyListStateSelectionPins? {
        guard lazyLookupRevision == revision, isCurrent(), let registry else { return nil }
        let pins = LazyListStateSelectionPins(
            owners: registry.owners, declarations: registry.lazyDeclarations,
            candidates: candidates, provisionalCells: provisionalCells,
            extraCells: lazyCellProposals.values.map(\.cell) + descriptorCellProposals.values.map(\.cell))
        for (identity, owner) in pins.owners {
            guard lazyLookupRevision == revision, isCurrent() else { return nil }
            let covered = includes(identity, isCurrent: { self.lazyLookupRevision == revision && isCurrent() })
            guard lazyLookupRevision == revision, isCurrent() else { return nil }
            if !covered { continue }
            pins.coveredOwnerGenerations.insert(owner.generation)
            // A raw legacy location has no exact native declaration proof.
            // Reject this composite route before mutation instead of guessing
            // that it belongs to a row or adopting the entire old epoch.
            for cell in owner.cells.values
            where cell.ownedSlotGeneration == nil && cell.lazyOwnership == nil && cell.descriptorOwnership == nil {
                _ = cell
                return nil
            }
        }
        let receipts =
            lazyOwners.values.compactMap { $0.ownedInstallation?.receipt }
            + descriptorOwners.values.compactMap { $0.ownedInstallation?.receipt }
            + managedPreservedOwners.values.map { $0.installation.receipt }
        for plan in preparation.ownedComponentDeclarations {
            guard lazyLookupRevision == revision, isCurrent(),
                receipts.contains(where: { $0 === plan.receipt })
            else { return nil }
        }
        return lazyLookupRevision == revision && isCurrent() ? pins : nil
    }

    private var canPublishLazySelection: Bool {
        phase == .adopting && registry?.isClosed == false && registry?.activeEpoch === self
    }

    func commitLazyAdoption(_ disposition: RetainedLazyListAdoptionDisposition) -> LazyListStateAdoptionSelection? {
        guard phase == .adopting, let registry, registry.activeEpoch === self,
            let preparation = lazyPreparation, preparation.attempt === disposition.attempt,
            let pins = lazyPreparedPins
        else { return nil }
        guard !registry.isClosed else {
            finishAbandonedBuild(in: registry)
            return nil
        }
        guard let publication = makeLazyPublication(disposition, pins: pins), canPublishLazySelection else {
            if registry.isClosed { finishAbandonedBuild(in: registry) }
            return nil
        }
        let keptOwners = Set(publication.owners.values.map(\.generation))
        for owner in pins.owners.values where !keptOwners.contains(owner.generation) {
            owner.beginRetirement()
            registry.retiringOwners[owner.generation] = owner
        }
        for identifier in publication.retired {
            guard let cell = pins.cells[identifier] else { continue }
            cell.beginRetirement()
            registry.retiringCells[identifier] = cell
        }
        // All displaced maps and values are pinned by publication/pins. These
        // assignments and native permission reads execute no application code.
        for selected in publication.selectedCells.values { selected.publish() }
        for owner in publication.owners.values {
            owner.cells = publication.slots[owner.generation] ?? [:]
            if let receipt = publication.declaredOwners[owner.generation] { owner.ownedComponentReceipt = receipt }
            owner.activate()
        }
        registry.owners = publication.owners
        registry.lazyDeclarations = publication.declarations
        registry.lastManagedAdoption = disposition.attempt
        refreshAffectedLazyRows(publication)
        for removal in disposition.acceptedLogicalRemovals {
            lazyRetiredScopes[ObjectIdentifier(removal.scope)] = removal.scope
        }
        for declaration in pins.declarations.values where !declaration.logicalScope.isLogicallyLive {
            lazyRetiredScopes[ObjectIdentifier(declaration.logicalScope)] = declaration.logicalScope
        }
        let selection = LazyListStateAdoptionSelection(
            disposition: disposition, pins: pins,
            acceptedOwnedSlots: publication.acceptedOwned, acceptedSyntheticCells: publication.acceptedSynthetic,
            unchangedOwnedSlots: publication.unchangedOwned, unchangedSyntheticCells: publication.unchangedSynthetic,
            retiredCells: publication.retired, acceptedMemberships: publication.acceptedMemberships)
        didCommit = true
        phase = .finished
        lazyLifetime.finish()
        registry.activeEpoch = nil
        // The normal finish still owns all rejected proposals and slot/key
        // snapshots. Do not release them while publishing accepted membership.
        return selection
    }

    @inline(never)
    private func makeLazyPublication(
        _ disposition: RetainedLazyListAdoptionDisposition, pins: LazyListStateSelectionPins
    ) -> ManagedStatePublication? {
        guard canPublishLazySelection else { return nil }
        let selected = selectAcceptedManagedCells(disposition)
        var nextOwners = pins.owners
        var slots: [UInt64: [StatePropertySlot: any AnyMountedStateCell]] = [:]
        var untouched: Set<UInt64> = []
        var declaredOwners: [UInt64: RetainedOwnedComponentReceipt] = [:]
        let incomingOwnedFacts = disposition.acceptedOwnedComponents
        for acquisition in lazyOwners.values {
            guard let installation = acquisition.ownedInstallation,
                incomingOwnedFacts.contains(where: { $0.plan.receipt === installation.receipt }),
                installation.receipt.hasDeclaredComponent
            else { continue }
            declaredOwners[acquisition.owner.generation] = installation.receipt
        }
        for acquisition in descriptorOwners.values {
            guard let installation = acquisition.ownedInstallation,
                incomingOwnedFacts.contains(where: { $0.plan.receipt === installation.receipt }),
                installation.receipt.hasDeclaredComponent
            else { continue }
            declaredOwners[acquisition.owner.generation] = installation.receipt
        }
        for preserved in managedPreservedOwners.values {
            let receipt = preserved.installation.receipt
            guard incomingOwnedFacts.contains(where: { $0.plan.receipt === receipt }), receipt.hasDeclaredComponent
            else {
                continue
            }
            declaredOwners[preserved.owner.generation] = receipt
        }
        for owner in pins.owners.values {
            guard canPublishLazySelection else { return nil }
            // Namespace coverage was checked before any retained mutation. The
            // accepted publication must not reenter old authored keys to learn
            // which unrelated cells lie outside this exact subtree.
            let covered = pins.coveredOwnerGenerations.contains(owner.generation)
            let originalSlots = pins.slotMaps[owner.generation] ?? [:]
            if !covered {
                untouched.insert(owner.generation)
                slots[owner.generation] = originalSlots
            } else {
                slots[owner.generation] = originalSlots.filter { $0.value.hasLiveManagedPermission }
            }
        }
        for proposal in selected.values where proposal.isCurrent {
            guard canPublishLazySelection else { return nil }
            nextOwners[proposal.owner.identity, while: { self.canPublishLazySelection && proposal.isCurrent }] =
                proposal.owner
            guard canPublishLazySelection else { return nil }
            guard proposal.isCurrent else { continue }
            slots[proposal.owner.generation, default: [:]][proposal.slot] = proposal.cell
        }
        for owner in candidates.values where declaredOwners[owner.generation] != nil {
            guard canPublishLazySelection else { return nil }
            guard let presence = declaredOwners[owner.generation], presence.hasDeclaredComponent else { continue }
            nextOwners[
                owner.identity,
                while: {
                    self.canPublishLazySelection && owner.lazyLifetime.isAvailable && presence.hasDeclaredComponent
                }
            ] = owner
            guard canPublishLazySelection else { return nil }
        }
        let acceptedMemberships = acceptedLazyMemberships(disposition)
        guard var declarations = makeAcceptedLazyDeclarations(disposition, pins: pins, accepted: acceptedMemberships),
            canPublishLazySelection
        else { return nil }

        // An authored identity hash may revoke another already-installed
        // physical contribution. Revoke-only native receipts are monotonic:
        // each additional pass must remove an owner/declaration, so this loop
        // is bounded by the original finite snapshots, never by app callbacks.
        let limit = nextOwners.count + declarations.count + 1
        var settled = false
        for _ in 0..<limit {
            guard canPublishLazySelection else { return nil }
            for (generation, current) in slots where !untouched.contains(generation) {
                slots[generation] = current.filter { identifier, cell in
                    if let proposal = selected[ObjectIdentifier(cell)], proposal.slot == identifier {
                        return proposal.isCurrent
                    }
                    return cell.hasLiveManagedPermission
                }
            }
            let departing = nextOwners.values.filter { owner in
                !untouched.contains(owner.generation) && (slots[owner.generation]?.isEmpty ?? true)
                    && declaredOwners[owner.generation]?.hasDeclaredComponent != true
                    && owner.ownedComponentReceipt?.hasDeclaredComponent != true
            }
            let removedDeclarations = declarations.values.filter {
                !$0.logicalScope.containsDeclaredDescriptor($0.id)
            }
            if departing.isEmpty && removedDeclarations.isEmpty {
                settled = true
                break
            }
            let departingGenerations = Set(departing.map(\.generation))
            let departingDeclarations = Set(removedDeclarations.map { ObjectIdentifier($0) })
            // Retirement already has exact native owner/declaration identities.
            // Never reenter an expired authored key just to remove its bucket.
            nextOwners = nextOwners.filter { !departingGenerations.contains($0.value.generation) }
            declarations = declarations.filter { !departingDeclarations.contains(ObjectIdentifier($0.value)) }
            for owner in departing {
                guard canPublishLazySelection else { return nil }
                slots.removeValue(forKey: owner.generation)
                declaredOwners.removeValue(forKey: owner.generation)
            }
        }
        guard settled, canPublishLazySelection else { return nil }
        let kept = Set(slots.values.flatMap { $0.values.map { ObjectIdentifier($0) } })
        let accepted = selected.filter { kept.contains($0.key) && $0.value.isCurrent }
        let acceptedOwned = Set(accepted.filter { $0.value.ownedGeneration != nil }.keys)
        let acceptedSynthetic = Set(accepted.filter { $0.value.ownedGeneration == nil }.keys)
        let unchanged = kept.subtracting(accepted.keys)
        let unchangedOwned = Set(unchanged.filter { pins.cells[$0]?.ownedSlotGeneration != nil })
        let unchangedSynthetic = unchanged.subtracting(unchangedOwned)
        return ManagedStatePublication(
            disposition: disposition, pins: pins, owners: nextOwners, slots: slots,
            selectedCells: accepted, declaredOwners: declaredOwners, declarations: declarations,
            acceptedOwned: acceptedOwned, acceptedSynthetic: acceptedSynthetic,
            unchangedOwned: unchangedOwned, unchangedSynthetic: unchangedSynthetic,
            retired: Set(pins.cells.keys).subtracting(kept), acceptedMemberships: acceptedMemberships)
    }

    private func selectAcceptedManagedCells(
        _ disposition: RetainedLazyListAdoptionDisposition
    ) -> [ObjectIdentifier: ManagedCellSelection] {
        var selected: [ObjectIdentifier: ManagedCellSelection] = [:]
        for proposal in lazyCellProposals.values {
            let cell = ObjectIdentifier(proposal.cell)
            switch proposal.ownership {
            case .owned:
                guard let installation = lazyOwners[proposal.owner.generation]?.ownedInstallation,
                    let generation = installation.slots[proposal.slot],
                    disposition.acceptedOwnedComponents.contains(where: {
                        $0.plan.receipt === installation.receipt
                            && $0.acceptedSlots.contains(where: { $0 === generation })
                    }), installation.receipt.hasAcceptedOwnership(for: generation)
                else { continue }
                selected[cell] = ManagedCellSelection(
                    owner: proposal.owner, slot: proposal.slot, cell: proposal.cell, lazyOwnership: proposal.ownership,
                    ownedInstallation: installation, ownedGeneration: generation)
            case .synthetic(_, let physical, let group):
                let accepted =
                    disposition.acceptedGroups.contains { $0.proposal.group === group }
                    || disposition.acceptedEmptyGroups.contains { $0.proposal.group === group }
                guard accepted, let receipt = disposition.contribution(for: group), receipt.isActive,
                    receipt.physical === physical
                else { continue }
                selected[cell] = ManagedCellSelection(
                    owner: proposal.owner, slot: proposal.slot, cell: proposal.cell,
                    lazyOwnership: proposal.ownership, lazyContribution: receipt)
            }
        }
        for proposal in descriptorCellProposals.values {
            let cell = ObjectIdentifier(proposal.cell)
            switch proposal.ownership {
            case .owned:
                guard let installation = proposal.acquisition.ownedInstallation,
                    let generation = installation.slots[proposal.slot],
                    disposition.acceptedOwnedComponents.contains(where: {
                        $0.plan.receipt === installation.receipt
                            && $0.acceptedSlots.contains(where: { $0 === generation })
                    }), installation.receipt.hasAcceptedOwnership(for: generation)
                else { continue }
                selected[cell] = ManagedCellSelection(
                    owner: proposal.owner, slot: proposal.slot, cell: proposal.cell,
                    descriptorOwnership: proposal.ownership, ownedInstallation: installation,
                    ownedGeneration: generation)
            case .synthetic(_, let group):
                let accepted =
                    disposition.acceptedOrdinaryGroups.contains { $0.proposal.group === group }
                    || disposition.acceptedEmptyOrdinaryGroups.contains { $0.proposal.group === group }
                guard accepted, let receipt = disposition.contribution(for: group), receipt.isActive else { continue }
                selected[cell] = ManagedCellSelection(
                    owner: proposal.owner, slot: proposal.slot, cell: proposal.cell,
                    descriptorOwnership: proposal.ownership, descriptorContribution: receipt)
            }
        }
        for preserved in managedPreservedOwners.values {
            let installation = preserved.installation
            for (slot, cell) in preserved.cells {
                guard selected[ObjectIdentifier(cell)] == nil, let generation = installation.slots[slot],
                    disposition.acceptedOwnedComponents.contains(where: {
                        $0.plan.receipt === installation.receipt
                            && $0.acceptedSlots.contains(where: { $0 === generation })
                    }), installation.receipt.hasAcceptedOwnership(for: generation)
                else { continue }
                selected[ObjectIdentifier(cell)] = ManagedCellSelection(
                    owner: preserved.owner, slot: slot, cell: cell,
                    lazyOwnership: cell.lazyOwnership, descriptorOwnership: cell.descriptorOwnership,
                    ownedInstallation: installation, ownedGeneration: generation)
            }
        }
        return selected
    }

    private func refreshAffectedLazyRows(_ publication: ManagedStatePublication) {
        var rows: [ObjectIdentifier: LazyListLogicalRow] = [:]
        for proposal in lazyCellProposals.values
        where publication.selectedCells[ObjectIdentifier(proposal.cell)] != nil {
            rows[ObjectIdentifier(proposal.attribution.logicalRow.id)] = proposal.attribution.logicalRow
        }
        for preserved in managedPreservedOwners.values {
            guard let row = preserved.logicalRow,
                preserved.cells.values.contains(where: { publication.selectedCells[ObjectIdentifier($0)] != nil })
            else { continue }
            rows[ObjectIdentifier(row.id)] = row
        }
        var retiredMemberships: Set<ObjectIdentifier> = []
        for identifier in publication.retired {
            guard case .owned(let membership, _) = publication.pins.cells[identifier]?.lazyOwnership else { continue }
            retiredMemberships.insert(ObjectIdentifier(membership.id))
        }
        for declaration in publication.pins.declarations.values {
            for row in declaration.sparseRows.values where retiredMemberships.contains(ObjectIdentifier(row.id)) {
                rows[ObjectIdentifier(row.id)] = row
            }
        }
        for row in rows.values {
            let previous = row.ownedSlots
            var next: [ObjectIdentifier: LazyListOwnedSlotRecord] = [:]
            for owner in publication.owners.values {
                for (slot, cell) in publication.slots[owner.generation] ?? [:] {
                    guard case .owned(let membership, _) = cell.lazyOwnership,
                        membership === row.logicalReceipt, cell.hasLiveManagedPermission
                    else { continue }
                    let identifier = ObjectIdentifier(cell)
                    next[identifier] =
                        previous[identifier]
                        ?? LazyListOwnedSlotRecord(owner: owner, slot: slot, cellIdentifier: identifier)
                }
            }
            row.publishOwnedSlots(next)
            withExtendedLifetime(previous) {}
        }
    }

    private func acceptedLazyMemberships(_ disposition: RetainedLazyListAdoptionDisposition) -> Set<ObjectIdentifier> {
        let groups =
            disposition.acceptedGroups.map(\.proposal) + disposition.partialGroups.map(\.proposal)
            + disposition.acceptedEmptyGroups.map(\.proposal)
        var result = Set(groups.map { ObjectIdentifier($0.membership) })
        for fact in disposition.acceptedOwnedComponents {
            guard case .lazy(let component) = fact.plan.origin,
                let acquired = lazyOwners.values.first(where: { $0.attribution.component === component })
            else { continue }
            result.insert(ObjectIdentifier(acquired.attribution.logicalRow.id))
        }
        return result
    }

    private func makeAcceptedLazyDeclarations(
        _ disposition: RetainedLazyListAdoptionDisposition, pins: LazyListStateSelectionPins,
        accepted: Set<ObjectIdentifier>
    ) -> ManagedKeyedMap<RetainedViewIdentity, LazyListCommittedDeclaration>? {
        var declarations = pins.declarations
        for fact in disposition.acceptedLogicalDeclarations {
            guard canPublishLazySelection,
                let proposal = lazyMemberships[ObjectIdentifier(fact.declaration)],
                proposal.facadeProposal === fact.membershipPlan.facadeProposal,
                proposal.logicalScope === fact.membershipPlan.expected.scope,
                proposal.logicalScope.containsDeclaredDescriptor(proposal.id)
            else { continue }
            var rows = proposal.retainedRows.filter { $0.value.isDeclared }
            for (key, row) in proposal.proposedRows where row.isDeclared && accepted.contains(ObjectIdentifier(row.id))
            {
                guard canPublishLazySelection else { return nil }
                rows[
                    key,
                    while: {
                        self.canPublishLazySelection && row.isDeclared
                            && proposal.logicalScope.containsDeclaredDescriptor(proposal.id)
                    }
                ] = row
                guard canPublishLazySelection else { return nil }
            }
            let declaration = LazyListCommittedDeclaration(
                id: proposal.id, listIdentity: proposal.listIdentity, metadata: proposal.completeMetadata,
                scope: proposal.logicalScope, parentRow: proposal.parentRow, sparseRows: rows)
            guard canPublishLazySelection else { return nil }
            declarations[
                proposal.listIdentity,
                while: { self.canPublishLazySelection && proposal.logicalScope.containsDeclaredDescriptor(proposal.id) }
            ] = declaration
            guard canPublishLazySelection else { return nil }
        }
        return canPublishLazySelection ? declarations : nil
    }

    private func retireAbandonedManagedCells(in registry: StateMountRegistry) {
        let retained = Set(registry.owners.values.flatMap { $0.cells.values.map { ObjectIdentifier($0) } })
        for proposal in lazyCellProposals.values where !retained.contains(ObjectIdentifier(proposal.cell)) {
            proposal.cell.finishRetirement()
        }
        for proposal in descriptorCellProposals.values where !retained.contains(ObjectIdentifier(proposal.cell)) {
            proposal.cell.finishRetirement()
        }
    }

    /// Called at the existing captured-transaction finish boundary, after
    /// accepted updates and discarded captures have received their cleanup.
    /// All fields are detached before their values can run authored deinit.
    func finishManagedTransport() {
        guard !didFinishManagedTransport, phase == .finished else { return }
        didFinishManagedTransport = true
        guard lazyLifetime.nativeAttempt != nil else { return }
        let retained = (
            lazyOwners, lazyCellProposals, lazyMemberships, lazyReservations, lazyConstructionAttempts,
            descriptorOwners, descriptorCellProposals, descriptorConstructionAttempts,
            lazyPreparedPins, lazyPreparation, lazyPreservedScopes, descriptorPreservedScopes, managedPreservedOwners,
            lazyCreatedScopes, lazyRetiredScopes, lazyDiscardScopes, candidates, claimedSlots, provisionalCells,
            preservedObservationOwners, preservedObservationCells, preservedScopes, pendingObjectCreations
        )
        let declaredScopes =
            registry.map { registry in
                Set(registry.lazyDeclarations.values.map { ObjectIdentifier($0.logicalScope) })
            } ?? []
        for (key, scope) in lazyCreatedScopes where !declaredScopes.contains(key) {
            scope.revokeLogicalMembership()
            registry?.lazyLogicalScopes.removeValue(forKey: key)
        }
        for (key, scope) in lazyRetiredScopes where !scope.isLogicallyLive {
            if registry?.lazyLogicalScopes[key] === scope { registry?.lazyLogicalScopes.removeValue(forKey: key) }
        }
        lazyOwners = [:]
        lazyCellProposals = [:]
        lazyMemberships = [:]
        lazyReservations = [:]
        lazyConstructionAttempts = [:]
        descriptorOwners = [:]
        descriptorCellProposals = [:]
        descriptorConstructionAttempts = [:]
        lazyPreparedPins = nil
        lazyPreparation = nil
        lazyPreservedScopes = []
        descriptorPreservedScopes = []
        managedPreservedOwners = [:]
        lazyCreatedScopes = [:]
        lazyRetiredScopes = [:]
        lazyDiscardScopes = [:]
        lazyBoundaryActivity = nil
        descriptorBoundaryActivity = nil
        candidates = [:]
        claimedSlots = [:]
        provisionalCells = [:]
        preservedObservationOwners = [:]
        preservedObservationCells = []
        preservedScopes = []
        pendingObjectCreations = [:]
        withExtendedLifetime(retained) {}
    }

    func bindNativeDescriptorScope(_ scope: RetainedLazyListDescriptorBuildScope) -> Bool {
        lazyLifetime.bind(scope)
    }

    func lazyAttribution(for owner: StateMountOwner) -> LazyListViewAttribution? {
        lazyOwners[owner.generation]?.attribution
    }

    func descriptorAttribution(for owner: StateMountOwner) -> RetainedDescriptorComponentAttribution? {
        descriptorOwners[owner.generation]?.attribution
    }

    func descriptorOwnerIsCurrent(
        _ owner: StateMountOwner, attribution: RetainedDescriptorComponentAttribution
    ) -> Bool {
        guard lazyLifetime.canConstruct, lazyLifetime.nativeAttempt === attribution.attempt, attribution.canConstruct,
            let acquisition = descriptorOwners[owner.generation], acquisition.owner === owner,
            acquisition.attribution === attribution, acquisition.isCurrent
        else { return false }
        return true
    }

    func descriptorOwner(
        at identity: RetainedViewIdentity, attribution: RetainedDescriptorComponentAttribution
    ) -> StateMountOwner? {
        guard let operation = DescriptorResolutionReceipt(epoch: self, native: attribution),
            let lookup = operation.beginLookup(),
            let attempt = registerDescriptorConstructionAttempt(at: identity, attribution: attribution, lookup: lookup),
            let registry, let declarationRevision = registry.lazyDeclarationRevision
        else { return nil }
        let receipt = attempt.receipt
        if let boundary = descriptorBoundaryOwner(at: identity, receipt: receipt, lookup: lookup), lookup.isCurrent {
            let result = installDescriptorOwner(boundary, receipt: receipt, lookup: lookup)
            return lookup.isCurrent && receipt.isCurrent ? result : nil
        }
        guard receipt.isCurrent, lookup.isCurrent else { return nil }
        let result = acquireObservation(
            at: identity, isMaterializationCurrent: { receipt.isCurrent && lookup.isCurrent }, lookup: lookup,
            resolve: { owner, _, _ in owner })
        guard let result, observationConstructionRevision == result.revision, receipt.isCurrent,
            registry.lazyDeclarationRevision == declarationRevision, lookup.isCurrent
        else { return nil }
        let owner = installDescriptorOwner(result.value, receipt: receipt, lookup: lookup)
        guard lookup.isCurrent, let owner, descriptorOwnerIsCurrent(owner, attribution: attribution) else { return nil }
        return owner
    }

    private func registerDescriptorConstructionAttempt(
        at identity: RetainedViewIdentity, attribution: RetainedDescriptorComponentAttribution,
        lookup: LazyListLookupReceipt
    ) -> DescriptorComponentConstructionAttempt? {
        guard let receipt = DescriptorResolutionReceipt(epoch: self, native: attribution) else { return nil }
        let key = ObjectIdentifier(attribution.component)
        if let current = descriptorConstructionAttempts[key] { return current.receipt.isCurrent ? current : nil }
        let attempt = DescriptorComponentConstructionAttempt(identity: identity, receipt: receipt)
        descriptorConstructionAttempts[key] = attempt
        let scopes = Array(lazyDiscardScopes.values)
        for scope in scopes where scope.isActive {
            guard receipt.isCurrent, lookup.isCurrent else { return nil }
            let matches = scope.scope.contains(identity, isCurrent: { receipt.isCurrent && lookup.isCurrent }) == true
            if matches { receipt.reject() }
            guard receipt.isCurrent, lookup.isCurrent else { return nil }
        }
        withExtendedLifetime(scopes) {}
        return receipt.isCurrent && lookup.isCurrent ? attempt : nil
    }

    private func descriptorBoundaryOwner(
        at identity: RetainedViewIdentity, receipt: DescriptorResolutionReceipt, lookup: LazyListLookupReceipt
    ) -> StateMountOwner? {
        guard let anchor, let activity = descriptorBoundaryActivity, activity.isActive,
            anchor.generation == anchorGeneration, anchor.isLive, receipt.isCurrent, lookup.isCurrent
        else { return nil }
        let matches =
            identity.checkedEquals(
                anchor.identity,
                isCurrent: { receipt.isCurrent && lookup.isCurrent && activity.isActive && anchor.isLive }) == true
        return matches && receipt.isCurrent && lookup.isCurrent && activity.isActive && anchor.isLive ? anchor : nil
    }

    @inline(never)
    private func installDescriptorOwner(
        _ owner: StateMountOwner, receipt: DescriptorResolutionReceipt, lookup: LazyListLookupReceipt
    ) -> StateMountOwner? {
        guard lookup.isCurrent else { return nil }
        let old = descriptorOwners
        var next = old
        defer { withExtendedLifetime((old, next)) {} }
        if let existing = next[owner.generation] {
            return existing.owner === owner && existing.attribution === receipt.native && existing.isCurrent
                ? owner : nil
        }
        next[owner.generation] = DescriptorOwnerAcquisition(owner: owner, receipt: receipt)
        guard lookup.allowPublication(activity: 1) else { return nil }
        descriptorOwners = next
        lazyActivityMapsDidChange()
        return owner
    }

    func recordDescriptorOwnedSlots(
        _ slots: Set<StatePropertySlot>, owner: StateMountOwner, attribution: RetainedDescriptorComponentAttribution
    ) -> Bool {
        guard descriptorOwnerIsCurrent(owner, attribution: attribution),
            let acquired = descriptorOwners[owner.generation]
        else { return false }
        if let previous = acquired.owningSlots { return previous == slots && acquired.isCurrent }
        guard let lookup = acquired.receipt.beginLookup(),
            let installation = prepareManagedOwnedInstallation(
                owner: owner, slots: slots, lookup: lookup,
                register: {
                    attribution.registerOwnedComponent(owner: owner.ownedComponentID, slots: $0, continuing: $1)
                }), lookup.isCurrent, acquired.isCurrent, lookup.allowPublication(activity: 1)
        else { return false }
        acquired.owningSlots = slots
        acquired.ownedInstallation = installation
        lazyActivityMapsDidChange()
        return lookup.isCurrent && acquired.isCurrent
    }

    fileprivate func resolveDescriptorOwnedCell<Value>(
        owner: StateMountOwner, slot: StatePropertySlot, isObjectFactory: Bool, seed: () -> Value
    ) throws -> MountedStateCell<Value> {
        guard let acquisition = descriptorOwners[owner.generation], acquisition.owner === owner,
            acquisition.isCurrent, acquisition.owningSlots?.contains(slot) == true
        else { throw unavailableLazyProperty(Value.self, slot: slot) }
        if let existing = acquisition.cells[slot] as? MountedStateCell<Value> { return existing }
        if isObjectFactory, pendingObjectCreations[owner.generation]?.contains(slot) == true {
            supersede()
            throw DynamicPropertyInstaller.failure(
                .recursiveInitialization, type: Value.self, at: slot,
                "The same descriptor-owned object declaration is already running its original factory")
        }
        let result: MountedStateCell<Value>? = resolveDescriptorCell(
            acquisition, slot: slot, isObjectFactory: isObjectFactory,
            ownership: .owned(component: acquisition.attribution.component), seed: seed)
        guard let result, acquisition.isCurrent else { throw unavailableLazyProperty(Value.self, slot: slot) }
        return result
    }

    private func resolveDescriptorCell<Value>(
        _ acquisition: DescriptorOwnerAcquisition, slot: StatePropertySlot,
        isObjectFactory: Bool, ownership: DescriptorCellOwnership, seed: () -> Value
    ) -> MountedStateCell<Value>? {
        guard acquisition.isCurrent, let lookup = acquisition.receipt.beginLookup() else { return nil }
        let owner = acquisition.owner
        let result = acquireObservation(
            at: owner.identity, isMaterializationCurrent: { acquisition.isCurrent && lookup.isCurrent }, lookup: lookup,
            resolve: { currentOwner, maps, revision -> MountedStateCell<Value>? in
                guard currentOwner === owner, acquisition.isCurrent && lookup.isCurrent else { return nil }
                let committed = owner.cells
                defer { withExtendedLifetime(committed) {} }
                var claimed =
                    maps.claimedSlots[
                        owner.identity,
                        while: {
                            self.observationConstructionRevision == revision
                                && (acquisition.isCurrent && lookup.isCurrent)
                        }
                    ] ?? []
                guard self.observationConstructionRevision == revision, acquisition.isCurrent && lookup.isCurrent else {
                    return nil
                }
                claimed.insert(slot)
                maps.claimedSlots[
                    owner.identity,
                    while: {
                        self.observationConstructionRevision == revision && (acquisition.isCurrent && lookup.isCurrent)
                    }
                ] = claimed
                guard self.observationConstructionRevision == revision, acquisition.isCurrent && lookup.isCurrent else {
                    return nil
                }
                var cells =
                    maps.provisionalCells[
                        owner.identity,
                        while: {
                            self.observationConstructionRevision == revision
                                && (acquisition.isCurrent && lookup.isCurrent)
                        }
                    ] ?? [:]
                guard self.observationConstructionRevision == revision, acquisition.isCurrent && lookup.isCurrent else {
                    return nil
                }
                if let existing = cells[slot] ?? committed[slot], let typed = existing as? MountedStateCell<Value> {
                    switch ownership {
                    case .owned:
                        if cells[slot] != nil || typed.isWritable { return typed }
                    case .synthetic:
                        if cells[slot] != nil || typed.isWritable { return typed }
                    }
                }
                if isObjectFactory {
                    guard self.pendingObjectCreations[owner.generation, default: []].insert(slot).inserted else {
                        self.supersede()
                        return nil
                    }
                }
                defer {
                    if isObjectFactory {
                        self.pendingObjectCreations[owner.generation]?.remove(slot)
                        if self.pendingObjectCreations[owner.generation]?.isEmpty == true {
                            self.pendingObjectCreations.removeValue(forKey: owner.generation)
                        }
                    }
                }
                let value = seed()
                let cell = MountedStateCell(value: value, owner: owner)
                if case .owned = ownership, let installation = acquisition.ownedInstallation,
                    let generation = installation.slots[slot]
                {
                    cell.bindOwnedLocation(installation.receipt, slot: generation)
                }
                maps.createdCells.append(cell)
                guard self.observationConstructionRevision == revision, acquisition.isCurrent && lookup.isCurrent else {
                    return nil
                }
                cells[slot] = cell
                maps.provisionalCells[
                    owner.identity,
                    while: {
                        self.observationConstructionRevision == revision && (acquisition.isCurrent && lookup.isCurrent)
                    }
                ] = cells
                guard self.observationConstructionRevision == revision, acquisition.isCurrent && lookup.isCurrent else {
                    return nil
                }
                return cell
            })
        guard let result, observationConstructionRevision == result.revision, acquisition.isCurrent, lookup.isCurrent
        else { return nil }
        let registered = registerDescriptorCell(
            result.value, acquisition: acquisition, slot: slot, ownership: ownership, lookup: lookup)
        return registered && lookup.isCurrent && acquisition.isCurrent ? result.value : nil
    }

    @inline(never)
    private func registerDescriptorCell(
        _ cell: any AnyMountedStateCell, acquisition: DescriptorOwnerAcquisition,
        slot: StatePropertySlot, ownership: DescriptorCellOwnership, lookup: LazyListLookupReceipt
    ) -> Bool {
        guard lookup.isCurrent, acquisition.isCurrent else { return false }
        let oldCells = acquisition.cells
        let oldProposals = descriptorCellProposals
        var cells = oldCells
        var proposals = oldProposals
        defer { withExtendedLifetime((oldCells, oldProposals, cells, proposals)) {} }
        cells[slot] = cell
        proposals[ObjectIdentifier(cell)] = DescriptorCellProposal(
            owner: acquisition.owner, slot: slot, cell: cell, acquisition: acquisition, ownership: ownership)
        guard lookup.allowPublication(activity: 1) else { return false }
        acquisition.cells = cells
        descriptorCellProposals = proposals
        lazyActivityMapsDidChange()
        return true
    }

    func resolveDescriptorSyntheticObservation<Observation>(
        at identity: RetainedViewIdentity, attribution: RetainedDescriptorComponentAttribution,
        kind: LazyListSyntheticKind, group: RetainedDescriptorGroupID, seed: () -> Observation
    ) -> (owner: StateMountOwner, cell: MountedStateCell<Observation>)? {
        guard let owner = descriptorOwner(at: identity, attribution: attribution),
            let acquisition = descriptorOwners[owner.generation], acquisition.isCurrent
        else { return nil }
        let slot = StatePropertySlot(concreteTypes: [ObjectIdentifier(Observation.self)])
        guard
            let cell = resolveDescriptorCell(
                acquisition, slot: slot, isObjectFactory: false, ownership: .synthetic(kind: kind, group: group),
                seed: seed),
            descriptorSyntheticCellIsCurrent(cell: cell, owner: owner, at: slot, attribution: attribution, group: group)
        else { return nil }
        return (owner, cell)
    }

    func descriptorSyntheticCellIsCurrent<Value>(
        cell: MountedStateCell<Value>, owner: StateMountOwner, at slot: StatePropertySlot,
        attribution: RetainedDescriptorComponentAttribution, group: RetainedDescriptorGroupID
    ) -> Bool {
        guard descriptorOwnerIsCurrent(owner, attribution: attribution),
            let record = descriptorCellProposals[ObjectIdentifier(cell)], record.owner === owner,
            record.slot == slot, record.acquisition.attribution === attribution,
            case .synthetic(_, let originalGroup) = record.ownership
        else { return false }
        return originalGroup === group && attribution.canConstruct
    }

    func discardDescriptorSubtree(
        at prefix: RetainedViewIdentity, preserveCommitted: Bool, attribution: RetainedDescriptorComponentAttribution,
        isCurrent: () -> Bool = { true }
    ) -> LazyListDiscardReceipt? {
        guard lazyLifetime.canConstruct, attribution.canConstruct, attribution.attempt === lazyLifetime.nativeAttempt,
            isCurrent()
        else {
            return nil
        }
        let receipt = LazyListDiscardReceipt(prefix: prefix, lifetime: lazyLifetime)
        lazyDiscardScopes[ObjectIdentifier(receipt)] = receipt
        let attempts = Array(descriptorConstructionAttempts.values)
        for attempt in attempts {
            guard lazyLifetime.canConstruct, receipt.isActive, isCurrent() else { break }
            let matches =
                receipt.scope.contains(
                    attempt.identity, isCurrent: { self.lazyLifetime.canConstruct && receipt.isActive && isCurrent() })
                == true
            if matches { attempt.receipt.reject() }
        }
        withExtendedLifetime(attempts) {}
        _ = preserveCommitted
        return receipt
    }

    func preserveDescriptorDeclaredScopes(
        _ scopes: [StateMountDeclarationScope], attribution: RetainedDescriptorComponentAttribution
    ) {
        guard let receipt = DescriptorResolutionReceipt(epoch: self, native: attribution) else { return }
        let previous = descriptorPreservedScopes
        descriptorPreservedScopes.append(
            contentsOf: scopes.map {
                DescriptorPreservedDeclarationScope(scope: $0, receipt: receipt)
            })
        withExtendedLifetime(previous) {}
        guard let lookup = receipt.beginLookup() else {
            receipt.reject()
            return
        }
        let preserved = registerKnownOwnedPreservations(
            scopes, containingComponent: ObjectIdentifier(attribution.component), row: nil, lookup: lookup,
            register: { owner, slots, continuing in
                attribution.registerOwnedComponent(
                    owner: owner, slots: slots, continuing: continuing, declarationOnly: true)
            })
        if !preserved || !lookup.isCurrent || !receipt.isCurrent { receipt.reject() }
    }

    /// Native descriptor selection precedes the frame's first authored row key.
    /// The returned typed prefix is a payload pin, not a lookup permission.
    func lazySelectionDeclarationIdentity(
        for preparation: RetainedLazyListSelectedRowPreparation
    ) -> RetainedViewIdentity? {
        guard lazyLifetime.canConstruct, preparation.isCurrent, let registry else { return nil }
        let result = lazySelectionDeclarationIdentitySnapshot(preparation, in: registry)
        guard lazyLifetime.canConstruct, preparation.isCurrent else { return nil }
        return result
    }

    @inline(never)
    private func lazySelectionDeclarationIdentitySnapshot(
        _ preparation: RetainedLazyListSelectedRowPreparation, in registry: StateMountRegistry
    ) -> RetainedViewIdentity? {
        let proposals = lazyMemberships
        let declarations = registry.lazyDeclarations
        defer { withExtendedLifetime((proposals, declarations)) {} }
        if let proposal = proposals[ObjectIdentifier(preparation.descriptor.descriptor)] {
            guard proposal.facadeProposal === preparation.descriptor.facadeProposal,
                proposal.logicalScope === preparation.descriptor.scope
            else { return nil }
            return proposal.listIdentity
        }
        return declarations.values.first {
            $0.id === preparation.descriptor.descriptor && $0.logicalScope === preparation.descriptor.scope
        }?.listIdentity
    }

    func recordEnteredLazyReservation(
        _ reservation: LazyListSelectedRowReservation, row: LazyListLogicalRow, attribution: LazyListViewAttribution
    ) -> Bool {
        guard attribution.isCurrent, row.id === reservation.membership,
            lazyReservations[ObjectIdentifier(reservation.resolutionID)] === reservation,
            let lookup = attribution.admission.beginLookup()
        else { return false }
        let accepted = recordEnteredLazyReservationSnapshot(reservation, row: row, lookup: lookup)
        return accepted && lookup.isCurrent && attribution.isCurrent
    }

    @inline(never)
    private func recordEnteredLazyReservationSnapshot(
        _ reservation: LazyListSelectedRowReservation, row: LazyListLogicalRow, lookup: LazyListLookupReceipt
    ) -> Bool {
        guard lookup.isCurrent else { return false }
        guard case .proposed(let proposal) = reservation.source else { return true }
        let old = proposal.proposedRows
        var next = old
        defer { withExtendedLifetime((old, next)) {} }
        next[reservation.key, while: { lookup.isCurrent }] = row
        guard lookup.isCurrent, lookup.allowPublication(activity: 1) else { return false }
        proposal.publishProposedRows(next)
        lazyActivityMapsDidChange()
        return true
    }

    func prepareLazyMembershipPlans(
        _ preparation: RetainedLazyListAdoptionPreparation
    ) -> [RetainedLazyListLogicalMembershipPlan]? {
        guard lazyLifetime.canConstruct else { return nil }
        var plans: [RetainedLazyListLogicalMembershipPlan] = []
        let memberships = lazyMemberships
        for descriptor in preparation.logicalDescriptors {
            guard lazyLifetime.canConstruct,
                let proposal = memberships[ObjectIdentifier(descriptor.descriptor)],
                proposal.facadeProposal === descriptor.facadeProposal,
                proposal.logicalScope === descriptor.scope, proposal.receipt.isCurrent,
                let snapshot = preparation.logicalSnapshots.first(where: { $0.scope === proposal.logicalScope }),
                let plan = proposal.sealNativePlan(
                    from: snapshot, sourceGeneration: proposal.sourceGeneration, receipt: proposal.receipt)
            else { return nil }
            plans.append(plan)
        }
        withExtendedLifetime(memberships) {}
        return lazyLifetime.canConstruct ? plans : nil
    }

    fileprivate var lazyLookupRevision: LazyListLookupRevision? {
        guard lazyLifetime.canConstruct, let registry, registry.activeEpoch === self,
            let observations = observationMapRevision, let activity = lazyActivityRevision,
            let declarations = registry.lazyDeclarationRevision
        else { return nil }
        return LazyListLookupRevision(observations: observations, activity: activity, declarations: declarations)
    }

    fileprivate func lazyActivityMapsDidChange() {
        guard let revision = lazyActivityRevision, revision < .max else {
            lazyActivityRevision = nil
            return
        }
        lazyActivityRevision = revision + 1
    }

    func beginLazyLookup(lifetime: LazyListLookupLifetime) -> LazyListLookupReceipt? {
        guard lifetime.isCurrent, let revision = lazyLookupRevision else { return nil }
        return LazyListLookupReceipt(lifetime: lifetime, epoch: self, revision: revision)
    }

    func lazyOwnerIsCurrent(_ owner: StateMountOwner, attribution: LazyListViewAttribution) -> Bool {
        guard lazyLifetime.canConstruct, attribution.isCurrent,
            let acquired = lazyOwners[owner.generation], acquired.owner === owner, acquired.isCurrent,
            acquired.attribution.native.component === attribution.native.component,
            acquired.attribution.logicalRow === attribution.logicalRow
        else { return false }
        return true
    }

    func lazyOwner(at identity: RetainedViewIdentity, attribution: LazyListViewAttribution) -> StateMountOwner? {
        guard attribution.isCurrent, let lookup = attribution.admission.beginLookup(),
            let attempt = registerLazyConstructionAttempt(at: identity, attribution: attribution, lookup: lookup),
            attempt.isCurrent, let registry, let declarations = registry.lazyDeclarationRevision
        else { return nil }
        if let boundary = lazyBoundaryOwner(at: identity, attribution: attribution, lookup: lookup), lookup.isCurrent {
            let installed = installLazyOwner(boundary, attribution: attribution, lookup: lookup)
            return lookup.isCurrent && attempt.isCurrent ? installed : nil
        }
        guard attempt.isCurrent, lookup.isCurrent else { return nil }
        let result = acquireObservation(
            at: identity, isMaterializationCurrent: { attempt.isCurrent && lookup.isCurrent }, lookup: lookup,
            resolve: { owner, _, _ in owner })
        guard let result, observationConstructionRevision == result.revision, attempt.isCurrent,
            registry.lazyDeclarationRevision == declarations, lookup.isCurrent
        else { return nil }
        let owner = installLazyOwner(result.value, attribution: attribution, lookup: lookup)
        guard lookup.isCurrent, let owner, lazyOwnerIsCurrent(owner, attribution: attribution) else { return nil }
        return owner
    }

    private func lazyBoundaryOwner(
        at identity: RetainedViewIdentity, attribution: LazyListViewAttribution, lookup: LazyListLookupReceipt
    ) -> StateMountOwner? {
        guard let anchor, let original = lazyBoundaryActivity, original.isActive,
            anchor.generation == anchorGeneration, anchor.isLive, attribution.isCurrent, lookup.isCurrent,
            case .deferredSubtree(let current) = attribution.native.origin, current === original
        else { return nil }
        let matches =
            identity.checkedEquals(
                anchor.identity,
                isCurrent: { attribution.isCurrent && lookup.isCurrent && original.isActive && anchor.isLive }) == true
        guard matches, attribution.isCurrent, lookup.isCurrent, original.isActive, anchor.isLive else { return nil }
        return anchor
    }

    private func registerLazyConstructionAttempt(
        at identity: RetainedViewIdentity, attribution: LazyListViewAttribution, lookup: LazyListLookupReceipt
    ) -> LazyListComponentConstructionAttempt? {
        guard attribution.isCurrent else { return nil }
        let key = ObjectIdentifier(attribution.component)
        if let current = lazyConstructionAttempts[key] { return current.isCurrent ? current : nil }
        let attempt = LazyListComponentConstructionAttempt(identity: identity, attribution: attribution)
        // The unkeyed record exists before the first authored identity operation.
        lazyConstructionAttempts[key] = attempt
        let scopes = Array(lazyDiscardScopes.values)
        for scope in scopes where scope.isActive {
            guard attempt.isCurrent, lazyLifetime.canConstruct, lookup.isCurrent else { return nil }
            let matches =
                scope.scope.contains(
                    identity, isCurrent: { attempt.isCurrent && self.lazyLifetime.canConstruct && lookup.isCurrent })
                == true
            if matches { attempt.reject() }
            guard attempt.isCurrent, lazyLifetime.canConstruct, lookup.isCurrent else { return nil }
        }
        withExtendedLifetime(scopes) {}
        return attempt.isCurrent && lookup.isCurrent ? attempt : nil
    }

    func discardLazySubtree(
        at prefix: RetainedViewIdentity, preserveCommitted: Bool, isCurrent: () -> Bool = { true }
    ) -> LazyListDiscardReceipt? {
        guard lazyLifetime.canConstruct, isCurrent() else { return nil }
        let scope = LazyListDiscardReceipt(prefix: prefix, lifetime: lazyLifetime)
        lazyDiscardScopes[ObjectIdentifier(scope)] = scope
        let attempts = Array(lazyConstructionAttempts.values)
        // This pass only revokes pinned original attempts. It never publishes
        // an authored-key dictionary snapshot over reentrant ordinary work.
        for attempt in attempts {
            guard lazyLifetime.canConstruct, scope.isActive, isCurrent() else { break }
            let matches =
                scope.scope.contains(
                    attempt.identity, isCurrent: { self.lazyLifetime.canConstruct && scope.isActive && isCurrent() })
                == true
            if matches { attempt.reject() }
        }
        withExtendedLifetime(attempts) {}
        // The caller keeps scope active through activity/update/capture cleanup.
        // Committed preservation still requires actual native unchanged facts.
        _ = preserveCommitted
        return scope
    }

    func finishLazyDiscardScope(_ receipt: LazyListDiscardReceipt) {
        guard receipt.lifetime === lazyLifetime else { return }
        receipt.finish()
        let previous = lazyDiscardScopes.removeValue(forKey: ObjectIdentifier(receipt))
        withExtendedLifetime(previous) {}
    }

    func preserveLazyDeclaredScopes(_ scopes: [StateMountDeclarationScope], attribution: LazyListViewAttribution) {
        guard attribution.isCurrent else { return }
        let previous = lazyPreservedScopes
        let additions = scopes.map { LazyListPreservedDeclarationScope(scope: $0, attribution: attribution) }
        lazyPreservedScopes.append(contentsOf: additions)
        withExtendedLifetime(previous) {}
        guard let lookup = attribution.admission.beginLookup() else {
            attribution.admission.reject()
            return
        }
        let preserved = registerKnownOwnedPreservations(
            scopes, containingComponent: ObjectIdentifier(attribution.component), row: attribution.logicalRow,
            lookup: lookup,
            register: { owner, slots, continuing in
                attribution.native.registerOwnedComponent(
                    owner: owner, slots: slots, continuing: continuing, declarationOnly: true)
            })
        if !preserved || !lookup.isCurrent || !attribution.isCurrent { attribution.admission.reject() }
    }

    @inline(never)
    private func registerKnownOwnedPreservations(
        _ scopes: [StateMountDeclarationScope], containingComponent: ObjectIdentifier,
        row: LazyListLogicalRow?, lookup: LazyListLookupReceipt,
        register: (
            RetainedOwnedComponentID, [RetainedOwnedSlotGenerationID], [RetainedOwnedComponentReceipt]
        ) -> RetainedOwnedComponentReceipt?
    ) -> Bool {
        guard lookup.isCurrent, let registry else { return false }
        let originalOwners = registry.owners
        let previous = managedPreservedOwners
        defer { withExtendedLifetime((originalOwners, previous)) {} }
        for owner in originalOwners.values where owner.isLive {
            guard lookup.isCurrent else { return false }
            // A measured and then rejected candidate is not an active
            // declaration. Its old committed cells may still be preserved.
            if lazyOwners[owner.generation]?.isCurrent == true || descriptorOwners[owner.generation]?.isCurrent == true
            {
                continue
            }
            var matches = false
            for scope in scopes {
                guard lookup.isCurrent else { return false }
                let contained = scope.contains(owner.identity, isCurrent: { lookup.isCurrent }) == true
                guard lookup.isCurrent else { return false }
                if contained {
                    matches = true
                    break
                }
            }
            if !matches { continue }
            let key = ManagedPreservedOwnerKey(
                ownerGeneration: owner.generation, containingComponent: containingComponent)
            if managedPreservedOwners[key] != nil { continue }
            let cells = owner.cells.filter { _, cell in
                guard cell.ownedSlotGeneration != nil, cell.hasLiveManagedPermission else { return false }
                if let row {
                    guard case .owned(let logical, _) = cell.lazyOwnership else { return false }
                    return logical === row.logicalReceipt
                }
                if case .owned = cell.descriptorOwnership { return true }
                return false
            }
            var generations: [StatePropertySlot: RetainedOwnedSlotGenerationID] = [:]
            var continuing: [RetainedOwnedComponentReceipt] = []
            // A declared component with no State wrappers still defines a
            // region. Its own presence may survive without a per-slot receipt.
            if let receipt = owner.ownedComponentReceipt, receipt.hasDeclaredComponent {
                let sameLifetime = row.map { receipt.belongs(to: $0.logicalReceipt) } ?? receipt.isDescriptorOwnership
                if sameLifetime { continuing.append(receipt) }
            }
            for (slot, cell) in cells {
                guard let generation = cell.ownedSlotGeneration, let receipt = cell.ownedComponentReceipt,
                    receipt.hasAcceptedOwnership(for: generation)
                else { return false }
                generations[slot] = generation
                if !continuing.contains(where: { $0 === receipt }) { continuing.append(receipt) }
            }
            if generations.isEmpty && continuing.isEmpty { continue }
            guard lookup.isCurrent,
                let receipt = register(owner.ownedComponentID, Array(generations.values), continuing), lookup.isCurrent
            else { return false }
            let preserved = ManagedPreservedOwner(
                owner: owner, cells: cells,
                installation: ManagedOwnedInstallation(receipt: receipt, slots: generations), logicalRow: row)
            guard lookup.allowPublication(activity: 1) else { return false }
            managedPreservedOwners[key] = preserved
            lazyActivityMapsDidChange()
        }
        return lookup.isCurrent
    }

    @inline(never)
    private func installLazyOwner(
        _ owner: StateMountOwner, attribution: LazyListViewAttribution, lookup: LazyListLookupReceipt
    ) -> StateMountOwner? {
        guard lookup.isCurrent else { return nil }
        let old = lazyOwners
        var next = old
        defer { withExtendedLifetime((old, next)) {} }
        if let existing = next[owner.generation] {
            return existing.owner === owner && existing.isCurrent
                && existing.attribution.native.component === attribution.native.component ? owner : nil
        }
        next[owner.generation] = LazyListOwnerAcquisition(owner: owner, attribution: attribution)
        guard lookup.allowPublication(activity: 1) else { return nil }
        lazyOwners = next
        return owner
    }

    /// The exact plan is recorded before any owning wrapper factory or update.
    func recordLazyOwnedSlots(
        _ slots: Set<StatePropertySlot>, owner: StateMountOwner, attribution: LazyListViewAttribution
    ) -> Bool {
        guard lazyOwnerIsCurrent(owner, attribution: attribution), let acquired = lazyOwners[owner.generation] else {
            return false
        }
        if let previous = acquired.owningSlots { return previous == slots && acquired.isCurrent }
        guard let lookup = attribution.admission.beginLookup(),
            let installation = prepareManagedOwnedInstallation(
                owner: owner, slots: slots, lookup: lookup,
                register: {
                    attribution.native.registerOwnedComponent(owner: owner.ownedComponentID, slots: $0, continuing: $1)
                }), lookup.isCurrent, acquired.isCurrent, lookup.allowPublication(activity: 1)
        else { return false }
        acquired.owningSlots = slots
        acquired.ownedInstallation = installation
        lazyActivityMapsDidChange()
        return lookup.isCurrent && acquired.isCurrent
    }

    @inline(never)
    private func prepareManagedOwnedInstallation(
        owner: StateMountOwner, slots: Set<StatePropertySlot>, lookup: LazyListLookupReceipt,
        register: ([RetainedOwnedSlotGenerationID], [RetainedOwnedComponentReceipt]) -> RetainedOwnedComponentReceipt?
    ) -> ManagedOwnedInstallation? {
        guard lookup.isCurrent else { return nil }
        let previous = owner.cells
        var continuing: [RetainedOwnedComponentReceipt] = []
        defer { withExtendedLifetime((previous, continuing)) {} }
        if let presence = owner.ownedComponentReceipt, presence.hasDeclaredComponent {
            // The native registration below checks the exact owner and logical
            // lifetime. Keep this presence even when the property roster is empty.
            continuing.append(presence)
        }
        var generations: [StatePropertySlot: RetainedOwnedSlotGenerationID] = [:]
        for slot in slots {
            guard lookup.isCurrent else { return nil }
            if let cell = previous[slot], cell.hasLiveManagedPermission, let generation = cell.ownedSlotGeneration {
                generations[slot] = generation
                if let receipt = cell.ownedComponentReceipt, !continuing.contains(where: { $0 === receipt }) {
                    continuing.append(receipt)
                }
            } else {
                generations[slot] = RetainedOwnedSlotGenerationID()
            }
        }
        guard lookup.isCurrent,
            let receipt = register(Array(generations.values), continuing), lookup.isCurrent
        else { return nil }
        return ManagedOwnedInstallation(receipt: receipt, slots: generations)
    }

    fileprivate func resolveLazyOwnedCell<Value>(
        owner: StateMountOwner, slot: StatePropertySlot, seed: () -> Value
    ) throws -> MountedStateCell<Value> {
        guard let acquisition = lazyOwners[owner.generation], acquisition.owner === owner,
            acquisition.isCurrent, acquisition.owningSlots?.contains(slot) == true
        else { throw unavailableLazyProperty(Value.self, slot: slot) }
        if let cached: MountedStateCell<Value> = try cachedLazyOwnedCell(acquisition, slot: slot) { return cached }
        guard let lookup = acquisition.attribution.admission.beginLookup() else {
            throw unavailableLazyProperty(Value.self, slot: slot)
        }
        let result = try createLazyOwnedCell(acquisition, slot: slot, lookup: lookup, seed: seed)
        guard lookup.isCurrent, acquisition.isCurrent else { throw unavailableLazyProperty(Value.self, slot: slot) }
        return result
    }

    private func resolveLazyOwnedObject<ObjectType: ObservableObject>(
        owner: StateMountOwner, slot: StatePropertySlot, seed: () -> ObjectType
    ) throws -> MountedStateCell<ObjectType> {
        guard let acquisition = lazyOwners[owner.generation], acquisition.owner === owner,
            acquisition.isCurrent, acquisition.owningSlots?.contains(slot) == true
        else { throw unavailableLazyProperty(ObjectType.self, slot: slot) }
        if let cached: MountedStateCell<ObjectType> = try cachedLazyOwnedCell(acquisition, slot: slot) { return cached }
        guard pendingObjectCreations[owner.generation, default: []].insert(slot).inserted else {
            supersede()
            throw DynamicPropertyInstaller.failure(
                .recursiveInitialization, type: StateObject<ObjectType>.self, at: slot,
                "The same lazy mounted object declaration is already running its original factory")
        }
        defer {
            pendingObjectCreations[owner.generation]?.remove(slot)
            if pendingObjectCreations[owner.generation]?.isEmpty == true {
                pendingObjectCreations.removeValue(forKey: owner.generation)
            }
        }
        guard let lookup = acquisition.attribution.admission.beginLookup() else {
            throw unavailableLazyProperty(ObjectType.self, slot: slot)
        }
        let result = try createLazyOwnedCell(acquisition, slot: slot, lookup: lookup, seed: seed)
        guard lookup.isCurrent, acquisition.isCurrent else {
            throw unavailableLazyProperty(ObjectType.self, slot: slot)
        }
        return result
    }

    private func unavailableLazyProperty<Value>(
        _ type: Value.Type, slot: StatePropertySlot
    ) -> DynamicPropertyInstallationError {
        DynamicPropertyInstaller.failure(
            .ownerUnavailable, type: type, at: slot,
            "The original lazy component no longer admits this owning property declaration")
    }

    private func cachedLazyOwnedCell<Value>(
        _ acquisition: LazyListOwnerAcquisition, slot: StatePropertySlot
    ) throws -> MountedStateCell<Value>? {
        guard acquisition.isCurrent else { throw unavailableLazyProperty(Value.self, slot: slot) }
        if let cached = acquisition.cells[slot] {
            guard let result = cached as? MountedStateCell<Value> else {
                throw DynamicPropertyInstaller.failure(
                    .changedPropertyType, type: Value.self, at: slot, "An owning lazy property changed its slot type")
            }
            return result
        }
        guard let previous = acquisition.owner.cells[slot],
            case .owned(let membership, _) = previous.lazyOwnership,
            membership === acquisition.attribution.logicalRow.logicalReceipt,
            let result = previous as? MountedStateCell<Value>, result.isWritable
        else { return nil }
        guard let lookup = acquisition.attribution.admission.beginLookup() else {
            throw unavailableLazyProperty(Value.self, slot: slot)
        }
        let registered = registerLazyCell(
            result, owner: acquisition.owner, slot: slot, attribution: acquisition.attribution,
            ownership: .owned(membership: membership, component: acquisition.attribution.component), lookup: lookup)
        guard registered, lookup.isCurrent, acquisition.isCurrent else {
            throw unavailableLazyProperty(Value.self, slot: slot)
        }
        return result
    }

    @inline(never)
    private func createLazyOwnedCell<Value>(
        _ acquisition: LazyListOwnerAcquisition, slot: StatePropertySlot,
        lookup: LazyListLookupReceipt, seed: () -> Value
    ) throws -> MountedStateCell<Value> {
        guard lookup.isCurrent, acquisition.isCurrent else { throw unavailableLazyProperty(Value.self, slot: slot) }
        let value = seed()
        guard lookup.isCurrent, acquisition.isCurrent else { throw unavailableLazyProperty(Value.self, slot: slot) }
        let cell = MountedStateCell(value: value, owner: acquisition.owner)
        guard let installation = acquisition.ownedInstallation, let generation = installation.slots[slot] else {
            cell.finishRetirement()
            throw unavailableLazyProperty(Value.self, slot: slot)
        }
        cell.bindOwnedLocation(installation.receipt, slot: generation)
        let registered = registerLazyCell(
            cell, owner: acquisition.owner, slot: slot, attribution: acquisition.attribution,
            ownership: .owned(
                membership: acquisition.attribution.logicalRow.logicalReceipt,
                component: acquisition.attribution.component), lookup: lookup)
        guard registered, lookup.isCurrent, acquisition.isCurrent else {
            cell.finishRetirement()
            throw unavailableLazyProperty(Value.self, slot: slot)
        }
        return cell
    }

    @inline(never)
    private func registerLazyCell(
        _ cell: any AnyMountedStateCell, owner: StateMountOwner, slot: StatePropertySlot,
        attribution: LazyListViewAttribution, ownership: LazyListCellOwnership, lookup: LazyListLookupReceipt
    ) -> Bool {
        guard lookup.isCurrent, lazyOwnerIsCurrent(owner, attribution: attribution),
            let acquisition = lazyOwners[owner.generation]
        else { return false }
        let oldCells = acquisition.cells
        let oldProposals = lazyCellProposals
        var cells = oldCells
        var proposals = oldProposals
        defer { withExtendedLifetime((oldCells, oldProposals, cells, proposals)) {} }
        cells[slot] = cell
        proposals[ObjectIdentifier(cell)] = LazyListCellProposal(
            owner: owner, slot: slot, cell: cell, attribution: attribution, ownership: ownership)
        guard lookup.allowPublication(activity: 2) else { return false }
        acquisition.cells = cells
        lazyActivityMapsDidChange()
        lazyCellProposals = proposals
        return true
    }

    func resolveLazySyntheticObservation<Observation>(
        at identity: RetainedViewIdentity, attribution: LazyListViewAttribution, kind: LazyListSyntheticKind,
        group: RetainedLazyListGroupID, seed: () -> Observation
    ) -> (owner: StateMountOwner, cell: MountedStateCell<Observation>)? {
        guard attribution.isCurrent, let owner = lazyOwner(at: identity, attribution: attribution),
            let acquisition = lazyOwners[owner.generation], let lookup = attribution.admission.beginLookup()
        else { return nil }
        let slot = StatePropertySlot(concreteTypes: [ObjectIdentifier(Observation.self)])
        let result = resolveLazySyntheticSnapshot(
            owner: owner, acquisition: acquisition, slot: slot, kind: kind, group: group, lookup: lookup, seed: seed)
        guard lookup.isCurrent, acquisition.isCurrent, let result,
            lazySyntheticCellIsCurrent(
                cell: result, owner: owner, at: slot, attribution: attribution, group: group)
        else { return nil }
        return (owner, result)
    }

    @inline(never)
    private func resolveLazySyntheticSnapshot<Observation>(
        owner: StateMountOwner, acquisition: LazyListOwnerAcquisition, slot: StatePropertySlot,
        kind: LazyListSyntheticKind, group: RetainedLazyListGroupID,
        lookup: LazyListLookupReceipt, seed: () -> Observation
    ) -> MountedStateCell<Observation>? {
        guard lookup.isCurrent, acquisition.isCurrent else { return nil }
        let previous = owner.cells
        defer { withExtendedLifetime(previous) {} }
        let cell: MountedStateCell<Observation>
        if let current = acquisition.cells[slot] as? MountedStateCell<Observation> {
            cell = current
        } else if let current = previous[slot] as? MountedStateCell<Observation>, current.isWritable,
            case .synthetic(_, let physical, _) = current.lazyOwnership,
            physical === acquisition.attribution.native.physical
        {
            cell = current
        } else {
            let value = seed()
            guard lookup.isCurrent, acquisition.isCurrent else { return nil }
            cell = MountedStateCell(value: value, owner: owner)
        }
        let result = registerLazyCell(
            cell, owner: owner, slot: slot, attribution: acquisition.attribution,
            ownership: .synthetic(kind: kind, physical: acquisition.attribution.native.physical, group: group),
            lookup: lookup)
        return result ? cell : nil
    }

    func recordLazySyntheticCell<Value>(
        _ cell: MountedStateCell<Value>, slot: StatePropertySlot, owner: StateMountOwner,
        kind: LazyListSyntheticKind, attribution: LazyListViewAttribution, group: RetainedLazyListGroupID
    ) -> Bool {
        guard let lookup = attribution.admission.beginLookup() else { return false }
        let result = registerLazyCell(
            cell, owner: owner, slot: slot, attribution: attribution,
            ownership: .synthetic(kind: kind, physical: attribution.native.physical, group: group), lookup: lookup)
        return result && lookup.isCurrent
    }

    func lazySyntheticCellIsCurrent<Value>(
        cell: MountedStateCell<Value>, owner: StateMountOwner, at slot: StatePropertySlot,
        attribution: LazyListViewAttribution, group: RetainedLazyListGroupID
    ) -> Bool {
        guard lazyOwnerIsCurrent(owner, attribution: attribution),
            let proposal = lazyCellProposals[ObjectIdentifier(cell)], proposal.owner === owner,
            proposal.slot == slot, proposal.attribution.component === attribution.component,
            case .synthetic(_, let physical, let storedGroup) = proposal.ownership
        else { return false }
        return physical === attribution.native.physical && storedGroup === group && attribution.isCurrent
    }
}
