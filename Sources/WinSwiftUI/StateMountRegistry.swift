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
    private var candidates: [RetainedViewIdentity: StateMountOwner] = [:]
    private var claimedSlots: [RetainedViewIdentity: Set<StatePropertySlot>] = [:]
    private var provisionalCells: [RetainedViewIdentity: [StatePropertySlot: any AnyMountedStateCell]] = [:]
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
        for (identity, owner) in registry.owners where includes(identity) && !keeps(identity) {
            owner.beginRetirement()
            registry.retiringOwners[owner.generation] = owner
            preparedOwnerGenerations.insert(owner.generation)
        }
        for (identity, owner) in candidates {
            let claimed = claimedSlots[identity] ?? []
            for (slot, cell) in owner.cells where !claimed.contains(slot) {
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
        let removed = registry.owners.keys.filter { includes($0) && !keeps($0) }
        for identity in removed { registry.owners.removeValue(forKey: identity) }
        for (identity, owner) in candidates {
            let claimed = claimedSlots[identity] ?? []
            owner.cells = owner.cells.filter { claimed.contains($0.key) }
            for (slot, cell) in provisionalCells[identity] ?? [:] { owner.cells[slot] = cell }
            owner.activate()
            registry.owners[identity] = owner
        }
        didCommit = true
        phase = .finished
        registry.activeEpoch = nil
        candidates.removeAll()
        provisionalCells.removeAll()
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
        pendingObjectCreations.removeAll()
        if registry.isClosed { registry.finishPendingRetirements() }
    }

    private func includes(_ identity: RetainedViewIdentity) -> Bool {
        guard let prefix else { return true }
        return identity.segments.starts(with: prefix.segments)
    }

    private func keeps(_ identity: RetainedViewIdentity) -> Bool {
        candidates[identity] != nil || preservedScopes.contains { $0.contains(identity) }
    }
}
