import SwiftWindowsCore

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
        guard identity.segments.starts(with: prefix.segments) else { return false }
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

    fileprivate init(value: Value, owner: StateMountOwner) {
        self.value = value
        self.owner = owner
    }

    var isWritable: Bool {
        switch phase {
        case .provisional:
            return owner?.isInstallationActive == true
        case .live:
            return owner?.isLive == true
        case .retiring, .retired:
            return false
        }
    }

    /// Preservation only admits an already-live cell of this exact owner.
    /// It must not enter the ordinary provisional installation lookup.
    fileprivate func isLiveObservation(of owner: StateMountOwner) -> Bool {
        phase == .live && self.owner === owner && owner.isLive
    }

    func readValue() -> Value {
        value
    }

    @discardableResult
    func write(_ value: Value) -> Bool {
        guard isWritable else { return false }
        // Releasing the outgoing Value can run application code. Mark the
        // accepted mutation before that release or any invalidation callback.
        let revision = phase == .live ? owner?.willWrite() : nil
        self.value = value
        if let revision { owner?.didWrite(revision: revision) }
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
    private weak var registry: StateMountRegistry?
    fileprivate var cells: [StatePropertySlot: any AnyMountedStateCell] = [:]
    private var phase = StateMountPhase.provisional

    fileprivate init(identity: RetainedViewIdentity, generation: UInt64, registry: StateMountRegistry) {
        self.identity = identity
        self.generation = generation
        self.registry = registry
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
        phase = .retiring
        for cell in cells.values { cell.beginRetirement() }
    }

    fileprivate func finishRetirement() {
        phase = .retired
        for cell in cells.values { cell.finishRetirement() }
        cells.removeAll()
        registry = nil
    }

    fileprivate func cancelRetirement() {
        guard phase == .retiring else { return }
        phase = .live
        for cell in cells.values { cell.cancelRetirement() }
    }
}

/// Main-actor storage owned by one host. This has no ambient singleton and does
/// not infer membership from painting, appearance, or an omitted body visit.
@MainActor
final class StateMountRegistry {
    private let invalidate: @MainActor () -> Void
    fileprivate var owners: [RetainedViewIdentity: StateMountOwner] = [:]
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
    private var candidates: [RetainedViewIdentity: StateMountOwner] = [:] {
        didSet { observationMapsDidChange() }
    }
    private var claimedSlots: [RetainedViewIdentity: Set<StatePropertySlot>] = [:] {
        didSet { observationMapsDidChange() }
    }
    private var provisionalCells: [RetainedViewIdentity: [StatePropertySlot: any AnyMountedStateCell]] = [:] {
        didSet { observationMapsDidChange() }
    }
    private var observationMapRevision: UInt64? = 0
    private var preservedObservationOwners: [UInt64: StateMountOwner] = [:]
    private var preservedObservationCells: Set<ObjectIdentifier> = []
    private var pendingObjectCreations: [UInt64: Set<StatePropertySlot>] = [:]
    private var preservedScopes: [StateMountDeclarationScope] = []
    private var preparedOwnerGenerations: Set<UInt64> = []
    private var preparedCellIdentifiers: Set<ObjectIdentifier> = []
    private(set) var didCommit = false

    fileprivate init(registry: StateMountRegistry, prefix: RetainedViewIdentity?, anchor: StateMountOwner?) {
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
        return registry.owners[anchor.identity] === anchor && anchor.isLive
    }

    var isAdopting: Bool { phase == .adopting }
    var visitedOwnerIdentities: Set<RetainedViewIdentity> { Set(candidates.keys) }

    func supersede() {
        guard phase == .constructing else { return }
        superseded = true
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
        canAdopt && candidates[owner.identity] === owner
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
        var candidates: [RetainedViewIdentity: StateMountOwner]
        var claimedSlots: [RetainedViewIdentity: Set<StatePropertySlot>]
        var provisionalCells: [RetainedViewIdentity: [StatePropertySlot: any AnyMountedStateCell]]
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
            var claimed = maps.claimedSlots[owner.identity] ?? []
            guard observationConstructionRevision == revision, isMaterializationCurrent() else { return nil }
            claimed.insert(slot)
            maps.claimedSlots[owner.identity] = claimed
            guard observationConstructionRevision == revision, isMaterializationCurrent() else { return nil }
            var cells = maps.provisionalCells[owner.identity] ?? [:]
            guard observationConstructionRevision == revision, isMaterializationCurrent() else { return nil }
            if let existing = cells[slot] ?? committedCells[slot] {
                guard let cell = existing as? MountedStateCell<Observation> else { return nil }
                return (owner: owner, cell: cell)
            }
            let cell = MountedStateCell(value: seed(), owner: owner)
            maps.createdCells.append(cell)
            guard observationConstructionRevision == revision, isMaterializationCurrent() else { return nil }
            cells[slot] = cell
            maps.provisionalCells[owner.identity] = cells
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
            includes(identity), observationConstructionRevision == revision, isMaterializationCurrent()
        else { return nil }
        let candidate = maps.candidates[identity]
        guard observationConstructionRevision == revision, isMaterializationCurrent() else { return nil }
        let owner: StateMountOwner
        if let candidate {
            owner = candidate
        } else {
            let existing = committed[identity]
            guard observationConstructionRevision == revision, isMaterializationCurrent() else { return nil }
            if let existing {
                owner = existing
            } else {
                owner = registry.makeOwner(at: identity)
                maps.createdOwner = owner
            }
            maps.candidates[owner.identity] = owner
            guard observationConstructionRevision == revision, isMaterializationCurrent() else { return nil }
            maps.claimedSlots[owner.identity] = []
            guard observationConstructionRevision == revision, isMaterializationCurrent() else { return nil }
        }
        guard let value = resolve(owner, &maps, revision),
            observationConstructionRevision == revision, isMaterializationCurrent(), revision <= UInt64.max - 3
        else { return nil }

        // No key operation or application callback occurs between these
        // assignments. The three didSet receipts must advance exactly once
        // each, and previous keeps every displaced dictionary alive.
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
        let candidate = candidates[owner.identity]
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
        let candidate = maps.candidates[owner.identity]
        guard observationConstructionRevision == revision, isMaterializationCurrent(), candidate === owner else {
            return false
        }
        let claimed = maps.claimedSlots[owner.identity]?.contains(slot) == true
        guard observationConstructionRevision == revision, isMaterializationCurrent(), claimed else { return false }
        let resolved = maps.provisionalCells[owner.identity]?[slot] ?? committedCells[slot]
        guard observationConstructionRevision == revision, isMaterializationCurrent(), let resolved else {
            return false
        }
        return ObjectIdentifier(resolved) == cellIdentifier && owner.hasObservationInstallationAuthority(in: registry)
    }

    /// Callers supply only scalar epoch/materialization checks and a pinned
    /// membership snapshot. No live authored-key dictionary is read here.
    private func observationAnchorIsCurrent(
        in committed: [RetainedViewIdentity: StateMountOwner], isCurrent: () -> Bool
    ) -> Bool {
        guard isCurrent() else { return false }
        guard let anchorGeneration else { return true }
        guard let anchor, anchor.generation == anchorGeneration, anchor.isLive else { return false }
        let isMember = committed[anchor.identity] === anchor
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
            includes(identity), observationConstructionRevision != nil, isMaterializationCurrent()
        else { return nil }
        let owner = committed[identity]
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
        guard canAdopt, pendingObjectCreations.isEmpty, let registry else { return false }
        phase = .adopting
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
        for owner in candidates.values { owner.beginRetirement() }
        for cells in provisionalCells.values {
            for cell in cells.values { cell.beginRetirement() }
        }
    }

    fileprivate func finishAbandonedBuild(in registry: StateMountRegistry) {
        for (identity, owner) in candidates where registry.owners[identity] !== owner {
            owner.finishRetirement()
        }
        for cells in provisionalCells.values {
            for cell in cells.values { cell.finishRetirement() }
        }
        phase = .finished
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

    private func keeps(_ identity: RetainedViewIdentity, owner: StateMountOwner) -> Bool {
        candidates[identity] != nil || preservedObservationOwners[owner.generation] === owner
            || preservedScopes.contains { $0.contains(identity) }
    }
}
