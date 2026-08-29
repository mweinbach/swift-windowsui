import SwiftWindowsCore
import SwiftWindowsUI

/// The native dictionary hashes only framework Int buckets. Authored identity
/// operations happen individually, with a receipt check before another key,
/// collision, resize, publication, or cleanup can be visited.
protocol ManagedKeyedIdentity: Hashable {
    func checkedHash(into hasher: inout Hasher, isCurrent: () -> Bool) -> Bool
    func checkedEquals(_ other: Self, isCurrent: () -> Bool) -> Bool?
}

extension RetainedViewIdentity: ManagedKeyedIdentity {}
extension RetainedViewIdentity.Key: ManagedKeyedIdentity {}

struct ManagedKeyedMap<Key: ManagedKeyedIdentity, Value>: Sequence, ExpressibleByDictionaryLiteral {
    typealias Element = (key: Key, value: Value)
    private var buckets: [Int: [Element]] = [:]
    private(set) var count = 0

    init() {}

    init(dictionaryLiteral elements: (Key, Value)...) {
        for (key, value) in elements { self[key] = value }
    }

    var isEmpty: Bool { count == 0 }
    var keys: [Key] { buckets.values.flatMap { $0.map(\.key) } }
    var values: [Value] { buckets.values.flatMap { $0.map(\.value) } }

    func makeIterator() -> IndexingIterator<[Element]> {
        buckets.values.flatMap { $0 }.makeIterator()
    }

    subscript(key: Key) -> Value? {
        get { value(for: key, isCurrent: { true }) }
        set { _ = setValue(newValue, for: key, isCurrent: { true }) }
    }

    subscript(key: Key, while isCurrent: () -> Bool) -> Value? {
        get { value(for: key, isCurrent: isCurrent) }
        set { _ = setValue(newValue, for: key, isCurrent: isCurrent) }
    }

    subscript(key: Key, default defaultValue: @autoclosure () -> Value) -> Value {
        get { self[key] ?? defaultValue() }
        set { self[key] = newValue }
    }

    @inline(never)
    func value(for key: Key, isCurrent: () -> Bool) -> Value? {
        guard let hash = hash(key, isCurrent: isCurrent) else { return nil }
        let entries = buckets[hash] ?? []
        defer { withExtendedLifetime(entries) {} }
        for entry in entries {
            guard let equal = entry.key.checkedEquals(key, isCurrent: isCurrent), isCurrent() else { return nil }
            if equal { return entry.value }
        }
        return nil
    }

    /// Callers mutate a local snapshot and recheck after this scope releases
    /// its bucket pins. COW and collision cleanup never rehash an authored key.
    @discardableResult
    @inline(never)
    mutating func setValue(_ value: Value?, for key: Key, isCurrent: () -> Bool) -> Bool {
        guard let hash = hash(key, isCurrent: isCurrent) else { return false }
        // Pin departing keys and values through the final admission check.
        // Keeping the whole dictionary here would force a full copy on every
        // write. Other buckets remain owned by this map, and copies held by
        // callers still receive ordinary dictionary value semantics.
        let entries = buckets[hash] ?? []
        defer { withExtendedLifetime(entries) {} }
        var match: Int?
        for index in entries.indices {
            guard let equal = entries[index].key.checkedEquals(key, isCurrent: isCurrent), isCurrent() else {
                return false
            }
            if equal {
                match = index
                break
            }
        }
        guard isCurrent() else { return false }
        var next = entries
        if let match {
            if let value {
                next[match] = (entries[match].key, value)
            } else {
                next.remove(at: match)
                count -= 1
            }
        } else if let value {
            next.append((key, value))
            count += 1
        }
        if next.isEmpty {
            buckets.removeValue(forKey: hash)
        } else {
            buckets[hash] = next
        }
        return isCurrent()
    }

    @discardableResult
    mutating func removeValue(forKey key: Key) -> Value? {
        removeValue(forKey: key, while: { true })
    }

    @discardableResult
    mutating func removeValue(forKey key: Key, while isCurrent: () -> Bool) -> Value? {
        let old = value(for: key, isCurrent: isCurrent)
        guard isCurrent(), setValue(nil, for: key, isCurrent: isCurrent), isCurrent() else { return nil }
        return old
    }

    mutating func removeAll(keepingCapacity: Bool = false) {
        let previous = buckets
        buckets.removeAll(keepingCapacity: keepingCapacity)
        count = 0
        withExtendedLifetime(previous) {}
    }

    func filter(_ isIncluded: (Element) throws -> Bool) rethrows -> Self {
        var result = Self()
        for (hash, entries) in buckets {
            let selected = try entries.filter(isIncluded)
            if !selected.isEmpty {
                result.buckets[hash] = selected
                result.count += selected.count
            }
        }
        return result
    }

    private func hash(_ key: Key, isCurrent: () -> Bool) -> Int? {
        guard isCurrent() else { return nil }
        var hasher = Hasher()
        guard key.checkedHash(into: &hasher, isCurrent: isCurrent), isCurrent() else { return nil }
        return hasher.finalize()
    }
}

/// The data source has already assigned occurrence numbers within this List.
/// Native row tokens are a mapping for one descriptor, never State identity.
struct LazyListQualifiedKey: ManagedKeyedIdentity {
    let key: RetainedViewIdentity.Key
    let occurrence: Int

    init(_ metadata: RetainedLazyListRowMetadata) {
        key = metadata.key
        occurrence = metadata.occurrence
    }

    func checkedHash(into hasher: inout Hasher, isCurrent: () -> Bool) -> Bool {
        guard key.checkedHash(into: &hasher, isCurrent: isCurrent), isCurrent() else { return false }
        hasher.combine(occurrence)
        return isCurrent()
    }

    func checkedEquals(_ other: Self, isCurrent: () -> Bool) -> Bool? {
        guard isCurrent() else { return nil }
        guard occurrence == other.occurrence else { return false }
        return key.checkedEquals(other.key, isCurrent: isCurrent)
    }
}

/// Receipt checks retain only framework scalars. In particular, checking a
/// receipt cannot release the last strong reference to a registry or build.
@MainActor
final class LazyListRegistryLifetime {
    private(set) var isOpen = true

    func close() { isOpen = false }
}

@MainActor
final class LazyListEpochLifetime {
    let registry: LazyListRegistryLifetime
    private(set) var isConstructing = true
    private(set) var isFinished = false
    private(set) var nativeAttempt: RetainedLazyListAttemptID?

    init(registry: LazyListRegistryLifetime) { self.registry = registry }

    var canConstruct: Bool { registry.isOpen && isConstructing && !isFinished }
    func bind(_ scope: RetainedLazyListDescriptorBuildScope) -> Bool {
        guard canConstruct, scope.canConstructDescriptors else { return false }
        if let nativeAttempt { return nativeAttempt === scope.attempt }
        nativeAttempt = scope.attempt
        return true
    }
    func stopConstruction() { isConstructing = false }
    func finish() {
        isConstructing = false
        isFinished = true
    }
}

@MainActor
final class LazyListOwnerLifetime {
    let registry: LazyListRegistryLifetime
    private(set) var canInstall = true

    init(registry: LazyListRegistryLifetime) { self.registry = registry }
    var isAvailable: Bool { registry.isOpen && canInstall }
    func retire() { canInstall = false }
    func cancelRetirement() { canInstall = true }
}

/// Only a visited logical row allocates this facade record. Owned storage does
/// not keep its previous physical nodes, providers, callbacks or subscriptions.
@MainActor
final class LazyListLogicalRow {
    let id: RetainedLazyListMembershipID
    let key: LazyListQualifiedKey
    let logicalReceipt: RetainedLazyListLogicalMembershipReceipt
    weak var parentRow: LazyListLogicalRow?
    private(set) var ownedSlots: [ObjectIdentifier: LazyListOwnedSlotRecord] = [:]
    private(set) var nestedDeclarations: ManagedKeyedMap<RetainedViewIdentity, LazyListCommittedDeclaration> = [:]

    init(
        key: LazyListQualifiedKey, receipt: RetainedLazyListLogicalMembershipReceipt,
        parentRow: LazyListLogicalRow?
    ) {
        id = receipt.id
        self.key = key
        logicalReceipt = receipt
        self.parentRow = parentRow
    }

    var isDeclared: Bool { logicalReceipt.isDeclared }

    // Callers publish complete, checked snapshots while retaining the outgoing
    // maps. These assignments themselves perform no authored key lookup.
    func publishOwnedSlots(_ slots: [ObjectIdentifier: LazyListOwnedSlotRecord]) { ownedSlots = slots }
    func publishNestedDeclarations(_ declarations: ManagedKeyedMap<RetainedViewIdentity, LazyListCommittedDeclaration>)
    {
        nestedDeclarations = declarations
    }
}

@MainActor
final class LazyListCommittedDeclaration {
    let id: RetainedLazyListLogicalDeclarationID
    let listIdentity: RetainedViewIdentity
    let logicalScope: RetainedLazyListLogicalMembershipScope
    weak var parentRow: LazyListLogicalRow?
    let completeMetadata: [RetainedLazyListRowMetadata]
    private(set) var sparseRows: ManagedKeyedMap<LazyListQualifiedKey, LazyListLogicalRow>

    init(
        id: RetainedLazyListLogicalDeclarationID, listIdentity: RetainedViewIdentity,
        metadata: [RetainedLazyListRowMetadata], scope: RetainedLazyListLogicalMembershipScope,
        parentRow: LazyListLogicalRow?, sparseRows: ManagedKeyedMap<LazyListQualifiedKey, LazyListLogicalRow>
    ) {
        self.id = id
        self.listIdentity = listIdentity
        completeMetadata = metadata
        logicalScope = scope
        self.parentRow = parentRow
        self.sparseRows = sparseRows
    }

    func publishSparseRows(_ rows: ManagedKeyedMap<LazyListQualifiedKey, LazyListLogicalRow>) { sparseRows = rows }
}

@MainActor
final class LazyListMembershipProposal {
    let id = RetainedLazyListLogicalDeclarationID()
    let facadeProposal = RetainedLazyListLogicalProposalID()
    let listIdentity: RetainedViewIdentity
    private let metadata: RetainedLazyListMetadata
    let logicalScope: RetainedLazyListLogicalMembershipScope
    let receipt: LazyListDescriptorResolutionReceipt
    weak var parentRow: LazyListLogicalRow?
    let retainedRows: ManagedKeyedMap<LazyListQualifiedKey, LazyListLogicalRow>
    let removedRows: [LazyListLogicalRow]
    private(set) var proposedRows: ManagedKeyedMap<LazyListQualifiedKey, LazyListLogicalRow> = [:]
    private(set) var sealedNativePlan: RetainedLazyListLogicalMembershipPlan?

    init(
        listIdentity: RetainedViewIdentity, metadata: RetainedLazyListMetadata,
        scope: RetainedLazyListLogicalMembershipScope, parentRow: LazyListLogicalRow?,
        retainedRows: ManagedKeyedMap<LazyListQualifiedKey, LazyListLogicalRow>, removedRows: [LazyListLogicalRow],
        receipt: LazyListDescriptorResolutionReceipt
    ) {
        self.listIdentity = listIdentity
        self.metadata = metadata
        logicalScope = scope
        self.parentRow = parentRow
        self.retainedRows = retainedRows
        self.removedRows = removedRows
        self.receipt = receipt
    }

    var completeMetadata: [RetainedLazyListRowMetadata] { metadata.rows }
    var sourceGeneration: RetainedLazyListGeneration { metadata.generation }

    var nativeBinding: RetainedLazyListManagedLogicalDescriptorBinding {
        RetainedLazyListManagedLogicalDescriptorBinding(
            descriptor: id, facadeProposal: facadeProposal, scope: logicalScope,
            metadata: metadata)
    }

    func publishProposedRows(_ rows: ManagedKeyedMap<LazyListQualifiedKey, LazyListLogicalRow>) { proposedRows = rows }

    func sealNativePlan(
        from snapshot: RetainedLazyListLogicalMembershipSnapshot,
        sourceGeneration: RetainedLazyListGeneration,
        receipt: LazyListDescriptorResolutionReceipt
    ) -> RetainedLazyListLogicalMembershipPlan? {
        guard self.receipt === receipt, receipt.isCurrent, snapshot.scope === logicalScope,
            self.sourceGeneration == sourceGeneration
        else { return nil }
        if let sealedNativePlan { return sealedNativePlan }
        let retained = retainedRows.values.map(\.logicalReceipt)
        let retainedIDs = Set(retained.map { ObjectIdentifier($0) })
        let deleted = snapshot.declared.filter { !retainedIDs.contains(ObjectIdentifier($0)) }
        let introduced = proposedRows.values.map(\.logicalReceipt).filter { $0.phase == .proposed }
        guard receipt.isCurrent,
            let plan = RetainedLazyListLogicalMembershipPlan(
                descriptor: id, facadeProposal: facadeProposal, expected: snapshot,
                sourceGeneration: sourceGeneration, introduced: introduced, retained: retained, deleted: deleted)
        else { return nil }
        sealedNativePlan = plan
        return receipt.isCurrent ? plan : nil
    }
}

@MainActor
enum LazyListDeclarationSource {
    case proposed(LazyListMembershipProposal)
    case committed(LazyListCommittedDeclaration)

    var nativeSource: RetainedLazyListSelectedRowSource {
        switch self {
        case .proposed(let proposal):
            return .proposed(descriptor: proposal.id, facadeProposal: proposal.facadeProposal)
        case .committed(let declaration):
            return .committed(descriptor: declaration.id)
        }
    }

    var parentRow: LazyListLogicalRow? {
        switch self {
        case .proposed(let proposal): return proposal.parentRow
        case .committed(let declaration): return declaration.parentRow
        }
    }
}

@MainActor
final class LazyListSelectedRowReservation {
    let resolutionID: RetainedLazyListRowResolutionID
    let preparation: RetainedLazyListSelectedRowPreparation
    let source: LazyListDeclarationSource
    let key: LazyListQualifiedKey
    let membership: RetainedLazyListMembershipID
    let existingRow: LazyListLogicalRow?
    let receipt: LazyListSelectionResolutionReceipt
    private(set) var boundRow: LazyListLogicalRow?
    private var entered = false
    private var rejected = false

    init(
        preparation: RetainedLazyListSelectedRowPreparation, source: LazyListDeclarationSource,
        key: LazyListQualifiedKey, existingRow: LazyListLogicalRow?, receipt: LazyListSelectionResolutionReceipt
    ) {
        resolutionID = preparation.resolutionID
        self.preparation = preparation
        self.source = source
        self.key = key
        self.existingRow = existingRow
        membership = existingRow?.id ?? RetainedLazyListMembershipID()
        self.receipt = receipt
    }

    var nativeResolution: RetainedLazyListSelectedRowResolution? {
        guard !rejected, !entered, receipt.isCurrent else { return nil }
        return RetainedLazyListSelectedRowResolution(
            preparation: preparation, membership: membership, source: source.nativeSource)
    }

    func bindEnteredAttribution(_ attribution: RetainedLazyListBuildAttribution) -> LazyListViewAttribution? {
        guard !rejected, !entered, receipt.isCurrent, attribution.resolutionID === resolutionID,
            attribution.membership === membership, let epoch = receipt.epoch,
            let admission = LazyListResolutionReceipt(epoch: epoch, native: attribution)
        else {
            reject()
            return nil
        }
        if let existingRow, existingRow.logicalReceipt !== attribution.logicalMembership {
            reject()
            return nil
        }
        let row =
            existingRow
            ?? LazyListLogicalRow(
                key: key, receipt: attribution.logicalMembership, parentRow: source.parentRow)
        let result = LazyListViewAttribution(
            native: attribution, logicalRow: row, component: attribution.component, admission: admission)
        guard epoch.recordEnteredLazyReservation(self, row: row, attribution: result), result.isCurrent else {
            reject()
            return nil
        }
        boundRow = row
        entered = true
        return result
    }

    func reject() {
        rejected = true
        receipt.reject()
    }
}

@MainActor
final class LazyListDescriptorResolutionReceipt {
    let nativeScope: RetainedLazyListDescriptorBuildScope
    weak var epoch: StateMountEpoch?
    let owner: StateMountOwner
    private let lifetime: LazyListEpochLifetime
    private let ownerLifetime: LazyListOwnerLifetime
    private let containingAttribution: LazyListViewAttribution?
    private let containingDescriptor: RetainedDescriptorComponentAttribution?
    private var rejected = false

    init?(
        epoch: StateMountEpoch, owner: StateMountOwner,
        nativeScope: RetainedLazyListDescriptorBuildScope,
        containingAttribution: LazyListViewAttribution?,
        containingDescriptor: RetainedDescriptorComponentAttribution? = nil
    ) {
        self.epoch = epoch
        self.owner = owner
        self.nativeScope = nativeScope
        lifetime = epoch.lazyLifetime
        ownerLifetime = owner.lazyLifetime
        self.containingAttribution = containingAttribution
        self.containingDescriptor = containingDescriptor
        if let descriptor = epoch.descriptorAttribution(for: owner) {
            guard descriptor === containingDescriptor else { return nil }
        }
        if let containingDescriptor {
            guard containingAttribution == nil,
                epoch.descriptorOwnerIsCurrent(owner, attribution: containingDescriptor)
            else { return nil }
        }
        if let containingAttribution {
            guard epoch.lazyOwnerIsCurrent(owner, attribution: containingAttribution) else { return nil }
        }
        guard isCurrent else { return nil }
    }

    var isCurrent: Bool {
        guard !rejected, lifetime.canConstruct, ownerLifetime.isAvailable,
            lifetime.nativeAttempt === nativeScope.attempt,
            nativeScope.canConstructDescriptors, containingAttribution?.isCurrent != false,
            containingDescriptor?.canConstruct != false
        else {
            rejected = true
            return false
        }
        return true
    }

    func beginLookup() -> LazyListLookupReceipt? {
        guard isCurrent, let epoch else { return nil }
        return epoch.beginLazyLookup(lifetime: .descriptor(self))
    }

    func reject() { rejected = true }
}

@MainActor
final class LazyListSelectionResolutionReceipt {
    let nativePreparation: RetainedLazyListSelectedRowPreparation
    weak var epoch: StateMountEpoch?
    private let lifetime: LazyListEpochLifetime
    private var rejected = false

    init?(epoch: StateMountEpoch, nativePreparation: RetainedLazyListSelectedRowPreparation) {
        self.epoch = epoch
        self.nativePreparation = nativePreparation
        lifetime = epoch.lazyLifetime
        guard isCurrent else { return nil }
    }

    var isCurrent: Bool {
        guard !rejected, lifetime.canConstruct, nativePreparation.isCurrent,
            lifetime.nativeAttempt === nativePreparation.descriptorBuildAttemptID
        else {
            rejected = true
            return false
        }
        return true
    }

    func beginLookup() -> LazyListLookupReceipt? {
        guard isCurrent, let epoch else { return nil }
        return epoch.beginLazyLookup(lifetime: .selectedRow(self))
    }

    func reject() { rejected = true }
}

@MainActor
final class LazyListResolutionReceipt {
    weak var epoch: StateMountEpoch?
    private let lifetime: LazyListEpochLifetime
    private let native: RetainedLazyListBuildAttribution
    private let parent: LazyListResolutionReceipt?
    private var rejected = false

    init?(
        epoch: StateMountEpoch, native: RetainedLazyListBuildAttribution,
        parent: LazyListResolutionReceipt? = nil
    ) {
        self.epoch = epoch
        self.native = native
        self.parent = parent
        lifetime = epoch.lazyLifetime
        guard isCurrent else { return nil }
    }

    var isCurrent: Bool {
        guard !rejected, lifetime.canConstruct, parent?.isCurrent != false,
            lifetime.nativeAttempt === native.descriptorBuildAttemptID,
            native.constructionState == .admittedForConstruction
        else {
            rejected = true
            return false
        }
        return true
    }

    func beginLookup() -> LazyListLookupReceipt? {
        guard isCurrent, let epoch else { return nil }
        return epoch.beginLazyLookup(lifetime: .enteredRow(self))
    }

    func reject() {
        rejected = true
        native.rejectConstruction()
    }
}

@MainActor
enum LazyListLookupLifetime {
    case descriptor(LazyListDescriptorResolutionReceipt)
    case selectedRow(LazyListSelectionResolutionReceipt)
    case enteredRow(LazyListResolutionReceipt)
    case descriptorComponent(DescriptorResolutionReceipt)

    var isCurrent: Bool {
        switch self {
        case .descriptor(let receipt): return receipt.isCurrent
        case .selectedRow(let receipt): return receipt.isCurrent
        case .enteredRow(let receipt): return receipt.isCurrent
        case .descriptorComponent(let receipt): return receipt.isCurrent
        }
    }
}

@MainActor
final class DescriptorResolutionReceipt {
    weak var epoch: StateMountEpoch?
    let native: RetainedDescriptorComponentAttribution
    private let lifetime: LazyListEpochLifetime
    private var rejected = false

    init?(epoch: StateMountEpoch, native: RetainedDescriptorComponentAttribution) {
        self.epoch = epoch
        self.native = native
        lifetime = epoch.lazyLifetime
        guard isCurrent else { return nil }
    }

    var isCurrent: Bool {
        guard !rejected, lifetime.canConstruct, lifetime.nativeAttempt === native.attempt, native.canConstruct else {
            rejected = true
            return false
        }
        return true
    }

    func beginLookup() -> LazyListLookupReceipt? {
        guard isCurrent, let epoch else { return nil }
        return epoch.beginLazyLookup(lifetime: .descriptorComponent(self))
    }

    func reject() {
        rejected = true
        native.rejectConstruction()
    }
}

@MainActor
struct LazyListViewAttribution {
    let native: RetainedLazyListBuildAttribution
    let logicalRow: LazyListLogicalRow
    let component: RetainedLazyListComponentID
    let admission: LazyListResolutionReceipt

    var isCurrent: Bool {
        admission.isCurrent && native.component === component
            && native.logicalMembership === logicalRow.logicalReceipt
            && native.constructionState == .admittedForConstruction
    }
}

enum LazyListSyntheticKind {
    case onChange, onPreferenceChange, taskID, presentation, alert, deferredAnchor

    var contributionKind: RetainedLazyListContributionKind {
        switch self {
        case .onChange: return .observation
        case .onPreferenceChange: return .preferenceObservation
        case .taskID: return .scopedTask
        case .presentation: return .presentation
        case .alert: return .alert
        case .deferredAnchor: return .deferredSubtree
        }
    }
}

@MainActor
enum LazyListCellOwnership {
    case owned(membership: RetainedLazyListLogicalMembershipReceipt, component: RetainedLazyListComponentID)
    case synthetic(
        kind: LazyListSyntheticKind, physical: RetainedLazyListPhysicalActivityReceipt,
        group: RetainedLazyListGroupID)
}

@MainActor
enum DescriptorCellOwnership {
    case owned(component: RetainedDescriptorComponentID)
    case synthetic(kind: LazyListSyntheticKind, group: RetainedDescriptorGroupID)
}

final class LazyListOwnedSlotID: Sendable {}

@MainActor
final class LazyListOwnedSlotRecord {
    let id = LazyListOwnedSlotID()
    let owner: StateMountOwner
    let ownerGeneration: UInt64
    let slot: StatePropertySlot
    let cellIdentifier: ObjectIdentifier

    init(owner: StateMountOwner, slot: StatePropertySlot, cellIdentifier: ObjectIdentifier) {
        self.owner = owner
        ownerGeneration = owner.generation
        self.slot = slot
        self.cellIdentifier = cellIdentifier
    }
}
