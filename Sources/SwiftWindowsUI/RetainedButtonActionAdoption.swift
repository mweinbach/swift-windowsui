import SwiftWindowsCore

/// Button-specific native witnesses supplement ordinary reconciliation, whose
/// historical admission intentionally has no physical attachment receipts.
/// Matching may call application Hashable code; suspend the whole affected
/// cohort before the first such call, without retiring unchanged declarations.
@MainActor
final class RetainedButtonActionAdoption {
    /// Scalar evidence only. A snapshot retains no node, action owner, or
    /// executable payload and never authorizes a later operation.
    struct ValidationSnapshot: Sendable {
        let checkCount: UInt64
        let witnessVisitCount: UInt64
        let witnessCount: Int
        let didOverflow: Bool
    }

    struct ValidationCounters {
        private var checkCount: UInt64
        private var witnessVisitCount: UInt64
        private let witnessCount: Int
        private var didOverflow = false

        init(witnessCount: Int, checkCount: UInt64 = 0, witnessVisitCount: UInt64 = 0) {
            self.witnessCount = witnessCount
            self.checkCount = checkCount
            self.witnessVisitCount = witnessVisitCount
        }

        mutating func recordCheck() {
            if checkCount == .max {
                didOverflow = true
            } else {
                checkCount += 1
            }
        }

        mutating func recordVisit() {
            if witnessVisitCount == .max {
                didOverflow = true
            } else {
                witnessVisitCount += 1
            }
        }

        var snapshot: ValidationSnapshot {
            ValidationSnapshot(
                checkCount: checkCount, witnessVisitCount: witnessVisitCount,
                witnessCount: witnessCount, didOverflow: didOverflow)
        }
    }

    private enum Phase {
        case stable
        case departureScheduled
        case transferring
        case departed
        case consumedSource
    }

    /// Captured child IDs only; this value never owns nodes or caches validity.
    private enum ChildTable {
        case empty
        case single(ObjectIdentifier)
        case multiple([ObjectIdentifier])

        init(capturing children: [ViewNode]) {
            switch children.count {
            case 0:
                self = .empty
            case 1:
                self = .single(ObjectIdentifier(children[0]))
            default:
                self = .multiple(children.map(ObjectIdentifier.init))
            }
        }

        var count: Int {
            switch self {
            case .empty: return 0
            case .single: return 1
            case .multiple(let identities): return identities.count
            }
        }

        /// The caller keeps its original count guard before this array read.
        func matchesChildrenHavingSameCount(_ children: [ViewNode]) -> Bool {
            switch self {
            case .empty:
                return true
            case .single(let identity):
                return ObjectIdentifier(children[0]) == identity
            case .multiple(let identities):
                return zip(children, identities).allSatisfy { pair in ObjectIdentifier(pair.0) == pair.1 }
            }
        }

        /// Preserve the identity-write guard's existing mapped-array boundary.
        static func == (lhs: ChildTable, rhs: [ObjectIdentifier]) -> Bool {
            switch lhs {
            case .empty:
                return rhs.isEmpty
            case .single(let identity):
                return rhs.count == 1 && rhs[0] == identity
            case .multiple(let identities):
                return identities == rhs
            }
        }
    }

    @MainActor
    private final class Witness {
        weak var node: ViewNode?
        let participatesInPayloadCohort: Bool
        private weak var observedOwner: RetainedButtonActionOwner?
        private var retainedOwner: RetainedButtonActionOwner?
        private var hadOwner: Bool
        var owner: RetainedButtonActionOwner? {
            get { participatesInPayloadCohort ? retainedOwner : observedOwner }
            set {
                observedOwner = newValue
                hadOwner = newValue != nil
                retainedOwner = participatesInPayloadCohort ? newValue : nil
            }
        }
        var ownerWasRetired: Bool
        var attachment: RetainedLazyListAttachmentProof
        var identity: RetainedLazyListViewIdentityProof
        var children: ChildTable
        var phase = Phase.stable

        init(_ node: ViewNode, participatesInPayloadCohort: Bool = true) {
            self.node = node
            self.participatesInPayloadCohort = participatesInPayloadCohort
            observedOwner = node.buttonActionOwner
            retainedOwner = participatesInPayloadCohort ? node.buttonActionOwner : nil
            hadOwner = node.buttonActionOwner != nil
            ownerWasRetired = node.buttonActionOwner?.isRetired == true
            attachment = node.captureLazyListAttachmentProof()
            identity = node.captureLazyListIdentityProof()
            children = ChildTable(capturing: node.children)
        }

        func matchesCurrent(exceptAttachment: Bool = false, exceptChildren: Bool = false) -> Bool {
            switch phase {
            case .departed, .consumedSource:
                return true
            case .stable, .departureScheduled, .transferring:
                guard let node, hadOwner == (owner != nil) else { return false }
                return (exceptAttachment || attachment.isCurrent) && identity.isCurrent
                    && (exceptChildren
                        || (children.count == node.children.count
                            && children.matchesChildrenHavingSameCount(node.children)))
                    && node.buttonActionOwner === owner
                    && (owner?.isRetired == true) == ownerWasRetired
            }
        }

        var isCurrent: Bool { matchesCurrent() }
    }

    @MainActor
    private struct Publication {
        let owner: RetainedButtonActionOwner
        weak var node: ViewNode?
    }

    @MainActor
    private struct RuntimeReference {
        weak var runtime: RetainedViewRuntime?
    }

    private let permission = RetainedButtonActionPermission()
    private var witnesses: [ObjectIdentifier: Witness] = [:]
    private let retained: Set<ObjectIdentifier>
    private var sources: [RetainedButtonActionOwner] = []
    private var publications: [ObjectIdentifier: Publication] = [:]
    private var flights: [RetainedButtonActionFlight] = []
    private var runtimes: [RuntimeReference] = []
    private var constructions: [RetainedButtonActionConstruction] = []
    private var isFinished = false
    private var isValid = true
    private var validationCounters: ValidationCounters?

    init?(
        retainedRoots: [ViewNode], sourceRoots: [ViewNode],
        collectValidationDiagnostics: Bool = false
    ) {
        let oldNodes = RetainedButtonActionTree.nodes(in: retainedRoots)
        let newNodes = RetainedButtonActionTree.nodes(in: sourceRoots)
        guard
            oldNodes.contains(where: { $0.buttonActionOwner != nil })
                || newNodes.contains(where: { $0.buttonActionOwner != nil })
        else { return nil }
        retained = Set(oldNodes.map(ObjectIdentifier.init))
        // Roots can belong to detached construction wrappers that are not
        // themselves source declarations. Witness their complete ancestry
        // before any matching callback; discovering it during removal would
        // bless a parent or child table installed by that callback.
        var ancestors: [ViewNode] = []
        var seenAncestors = Set((oldNodes + newNodes).map(ObjectIdentifier.init))
        for root in retainedRoots + sourceRoots {
            var ancestor = root.parent
            while let node = ancestor, seenAncestors.insert(ObjectIdentifier(node)).inserted {
                ancestors.append(node)
                ancestor = node.parent
            }
        }
        for node in ancestors {
            witnesses[ObjectIdentifier(node)] = Witness(node, participatesInPayloadCohort: false)
        }
        for node in oldNodes + newNodes {
            let identity = ObjectIdentifier(node)
            if witnesses[identity] == nil { witnesses[identity] = Witness(node) }
            for runtime in [node.retainedLazyListRuntime, node.buttonActionOwner?.constructionRuntime].compactMap({ $0 }
            ) {
                if !runtimes.contains(where: { $0.runtime === runtime }) {
                    runtimes.append(RuntimeReference(runtime: runtime))
                    constructions.append(RetainedButtonActionConstruction(runtime: runtime))
                }
            }
            if let flight = node.existingRetainedButtonActionFlight { suspend(flight) }
        }
        for node in newNodes where !retained.contains(ObjectIdentifier(node)) {
            guard let owner = node.buttonActionOwner else { continue }
            // A live node from another tree is not a fresh source declaration.
            guard node.retainedLazyListRuntime == nil, owner.node === node, owner.canBeAccepted else {
                isValid = false
                continue
            }
            guard owner.claimAdoption(using: permission) else {
                isValid = false
                continue
            }
            sources.append(owner)
        }
        if collectValidationDiagnostics {
            validationCounters = ValidationCounters(witnessCount: witnesses.count)
        }
    }

    private func suspend(_ flight: RetainedButtonActionFlight) {
        guard !flights.contains(where: { $0 === flight }) else { return }
        flight.suspensions.insert(ObjectIdentifier(self))
        flights.append(flight)
    }

    private var operationIsCurrent: Bool {
        !isFinished && isValid && permission.isCurrent
            && runtimes.allSatisfy { $0.runtime?.permitsRetainedActionInvocation == true }
    }

    var validationSnapshot: ValidationSnapshot? { validationCounters?.snapshot }

    var isCurrent: Bool {
        validationCounters?.recordCheck()
        guard operationIsCurrent else { return false }
        for witness in witnesses.values {
            validationCounters?.recordVisit()
            guard witness.matchesCurrent() else { return false }
        }
        return true
    }

    /// A source departure may still owe cleanup after insertion is refused.
    /// Keep that refusal permanent while its old native cleanup continues.
    func observeDepartureContinuation() {
        if !isCurrent { isValid = false }
    }

    /// The original cohort remains suspended until native removal has either
    /// happened or failed. Merely matching an outgoing node does not retire it.
    func prepareDepartures(in roots: [ViewNode]) -> Bool {
        guard isCurrent else { return false }
        for node in RetainedButtonActionTree.nodes(in: roots) {
            guard let witness = witnesses[ObjectIdentifier(node)] else { return false }
            switch witness.phase {
            case .stable, .departureScheduled: witness.phase = .departureScheduled
            case .transferring, .departed, .consumedSource: return false
            }
        }
        return true
    }

    /// Only the actual native departure boundary consumes the scheduled
    /// cohort. Until then its attachment and child table remain live checks.
    func beginDeparture(in roots: [ViewNode]) -> Bool {
        guard isCurrent else {
            isValid = false
            return false
        }
        let departing = RetainedButtonActionTree.nodes(in: roots)
        for node in departing {
            guard let witness = witnesses[ObjectIdentifier(node)], case .departureScheduled = witness.phase else {
                isValid = false
                return false
            }
        }
        for node in departing { witnesses[ObjectIdentifier(node)]?.phase = .departed }
        return true
    }

    /// The caller has just made one deliberate native child-table write,
    /// immediately after a successful check and without an authored callout.
    @discardableResult
    func recordChildrenWrite(on node: ViewNode) -> Bool {
        guard operationIsCurrent, let changed = witnesses[ObjectIdentifier(node)],
            witnesses.values.allSatisfy({ $0.matchesCurrent(exceptChildren: $0 === changed) })
        else {
            isValid = false
            return false
        }
        changed.children = ChildTable(capturing: node.children)
        if !isCurrent { isValid = false }
        return isValid
    }

    /// Advance only the exact attachment facet changed by the adjacent native
    /// write. A paired parent table can advance in the same no-callout write
    /// sequence. Every other node and every unchanged facet stays witnessed.
    @discardableResult
    func recordAttachmentWrite(on node: ViewNode, afterChildrenWriteOf parent: ViewNode? = nil) -> Bool {
        let parentWitness = parent.flatMap { witnesses[ObjectIdentifier($0)] }
        guard operationIsCurrent, let changed = witnesses[ObjectIdentifier(node)],
            parent == nil || parentWitness != nil,
            witnesses.values.allSatisfy({
                $0.matchesCurrent(exceptAttachment: $0 === changed, exceptChildren: $0 === parentWitness)
            })
        else {
            isValid = false
            return false
        }
        changed.attachment = node.captureLazyListAttachmentProof()
        if let parent, let parentWitness { parentWitness.children = ChildTable(capturing: parent.children) }
        if !isCurrent { isValid = false }
        return isValid
    }

    /// Called after tracked property-copy admission and before its native write.
    /// The caller pins both owners until the journal records the accepted field.
    func prepareOwnerCopy(from source: ViewNode, to target: ViewNode) -> Bool {
        guard isCurrent else { return false }
        guard source !== target else { return true }
        if let incoming = source.buttonActionOwner {
            guard incoming.node === source, incoming.canBeAccepted, incoming.isClaimed(by: permission),
                source.retainedLazyListRuntime == nil
            else {
                return false
            }
            suspend(target.retainedButtonActionFlight)
            incoming.transfer(to: target)
        }
        target.buttonActionOwner?.retire()
        return true
    }

    /// No authored call occurs between the field write and this receipt update.
    /// Refresh only the owner slot; never recapture a retained attachment after
    /// a callback has had the opportunity to detach and restore it.
    func recordOwnerCopy(from source: ViewNode, to target: ViewNode) -> Bool {
        guard let targetWitness = witnesses[ObjectIdentifier(target)], targetWitness.attachment.isCurrent,
            targetWitness.identity.isCurrent,
            target.buttonActionOwner === source.buttonActionOwner,
            source.buttonActionOwner?.node === target || source.buttonActionOwner == nil
        else { return false }
        targetWitness.owner = target.buttonActionOwner
        targetWitness.ownerWasRetired = target.buttonActionOwner?.isRetired == true
        if let owner = target.buttonActionOwner {
            publications[ObjectIdentifier(owner)] = Publication(owner: owner, node: target)
        }
        return true
    }

    /// The old key is still pinned by the property-copy helper. Refresh beside
    /// its deliberate native assignment, before any old key can be destroyed.
    func recordIdentityWrite(on node: ViewNode) {
        guard let witness = witnesses[ObjectIdentifier(node)], witness.attachment.isCurrent,
            witness.children == node.children.map(ObjectIdentifier.init),
            node.buttonActionOwner === witness.owner,
            (witness.owner?.isRetired == true) == witness.ownerWasRetired,
            witnesses.values.allSatisfy({ $0 === witness || $0.isCurrent })
        else {
            isValid = false
            return
        }
        witness.identity = node.captureLazyListIdentityProof()
    }

    func consumeSourceOwner(on source: ViewNode, copiedTo target: ViewNode) -> Bool {
        guard isCurrent, source !== target, source.buttonActionOwner === target.buttonActionOwner else {
            return source === target && isCurrent
        }
        // The transferred owner points at target now. Clearing source cannot
        // revoke that accepted destination when the throwaway node is released.
        source.buttonActionOwner = nil
        witnesses[ObjectIdentifier(source)]?.owner = nil
        witnesses[ObjectIdentifier(source)]?.ownerWasRetired = false
        return isCurrent
    }

    func beginInsertion(in roots: [ViewNode]) -> Bool {
        guard isCurrent else { return false }
        for node in RetainedButtonActionTree.nodes(in: roots) where !retained.contains(ObjectIdentifier(node)) {
            guard let witness = witnesses[ObjectIdentifier(node)], witness.isCurrent else { return false }
            witness.phase = .transferring
            witness.owner?.preparePublication()
        }
        return true
    }

    /// Records publication from still-current native receipts. It never
    /// recaptures an attachment after a controller or dismantling callout.
    /// Pending owners cannot invoke until the complete operation is accepted.
    func recordInsertion(in roots: [ViewNode]) -> Bool {
        guard isCurrent else { return false }
        for node in RetainedButtonActionTree.nodes(in: roots) {
            guard let witness = witnesses[ObjectIdentifier(node)] else { continue }
            guard case .transferring = witness.phase else { continue }
            guard witness.isCurrent else { return false }
            witness.phase = .stable
            if let owner = node.buttonActionOwner {
                publications[ObjectIdentifier(owner)] = Publication(owner: owner, node: node)
            }
        }
        return isCurrent
    }

    /// Release rejected/retired payloads with every affected flight still
    /// suspended, then perform a fresh native proof check before enabling any
    /// new declaration. Failed untouched old controls simply lose suspension.
    @discardableResult
    func finish(
        completed: Bool, check: ComponentHost.NodeReconcileAdmission,
        completion: RetainedLazyListAdoptionCompletion?
    ) -> Bool {
        guard !isFinished else { return false }
        var accepted = completed && isCurrent && check.isCurrent && completion?.isCurrent == true
        let proposed = accepted ? Array(publications.values) : []
        let proposedIDs = Set(proposed.map { ObjectIdentifier($0.owner) })
        for owner in sources where owner.isClaimed(by: permission) && !proposedIDs.contains(ObjectIdentifier(owner)) {
            owner.retire()
            if let node = owner.node, let witness = witnesses[ObjectIdentifier(node)], witness.owner === owner {
                witness.phase = .consumedSource
            }
        }
        let owned = witnesses.values.filter(\.participatesInPayloadCohort).compactMap(\.owner) + sources
        for owner in owned { owner.releaseRetiredPayload() }
        for construction in constructions.reversed() { construction.finish() }
        // These concrete native operation witnesses include provider, journal,
        // and complete subtree authority. Destruction above may revoke any of
        // them without changing an owner field or a physical attachment.
        accepted = accepted && isCurrent && check.isCurrent && completion?.isCurrent == true
        accepted =
            accepted
            && proposed.allSatisfy { publication in
                guard let node = publication.node else { return false }
                return publication.owner.canAccept(on: node, using: permission)
            }
        if accepted {
            // All checks and writes in this phase are native. No application
            // payload can unwind between the preflight and these acceptances.
            for publication in proposed {
                guard let node = publication.node, publication.owner.accept(on: node, using: permission) else {
                    accepted = false
                    break
                }
            }
        }
        if !accepted {
            let rejected = sources.filter { $0.isClaimed(by: permission) }
            for owner in rejected { owner.retire() }
            // An already-left construction still installs a closed cleanup
            // frame if its pending payloads must be destroyed on this failure.
            let cleanup = runtimes.compactMap(\.runtime).map { RetainedButtonActionConstruction(runtime: $0) }
            for construction in cleanup { construction.permission.isAvailable = false }
            for owner in rejected { owner.releaseRetiredPayload() }
            for construction in cleanup.reversed() { construction.finish() }
        }
        permission.isAvailable = false
        isFinished = true
        for flight in flights { flight.suspensions.remove(ObjectIdentifier(self)) }
        return accepted
    }
}
