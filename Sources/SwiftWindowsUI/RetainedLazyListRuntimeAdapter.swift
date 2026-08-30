import SwiftWindowsCore

/// Native identities used only for synchronous adapter admission. They carry
/// no provider, application payload, node, or callback.
fileprivate final class RetainedLazyListAdapterIdentity {}

/// Stable native metadata namespace across an accepted provider continuation.
/// It grants no physical/action authority and owns no predecessor or payload.
final class RetainedLazyListMembershipIdentity: Sendable {}

/// The item owns this payload-free marker. A dropped item ends its request
/// without an actor-isolated deinitializer or a captured runtime callback.
package final class RetainedLazyListLogicalRealizationOwner: Sendable {
    package init() {}
}

/// One explicit, bounded request to keep a logical row materialized. It owns
/// no node, provider, callback, or runtime and can cross an accepted descriptor
/// replacement only when the provider preserved the same native row token.
@MainActor
package final class RetainedLazyListLogicalRealization {
    package let token: RetainedLazyListRowToken
    private weak var owner: RetainedLazyListLogicalRealizationOwner?
    private var wasRevoked = false

    fileprivate init(token: RetainedLazyListRowToken, owner: RetainedLazyListLogicalRealizationOwner) {
        self.token = token
        self.owner = owner
    }

    package var isActive: Bool { !wasRevoked && owner != nil }

    package func revoke() { wasRevoked = true }
}

/// A selected row's native lifetime. Empty rows keep this bounded record even
/// though they have no ViewNode; the List container is only their anchor.
@MainActor
final class RetainedLazyListMaterializedRowActivity {
    let request: RetainedLazyListRowRequest
    let attempt: RetainedLazyListAttemptID
    let logicalMembership: RetainedLazyListLogicalMembershipReceipt
    let physical: RetainedLazyListPhysicalActivityReceipt
    let component: RetainedLazyListComponentID

    init(_ attribution: RetainedLazyListBuildAttribution) {
        request = attribution.rowRequest
        attempt = attribution.attempt
        logicalMembership = attribution.logicalMembership
        physical = attribution.physical
        component = attribution.component
    }

    var isCurrent: Bool {
        request.isGenerationCurrent && logicalMembership.permitsConstruction && physical.state != .revoked
    }
}

/// A vertical-list adapter. Runtime owns attachment, the retained
/// build lease/coordinator, checked reconciliation, actual layout, and input.
/// This object never calls a factory from layoutPlan or adopts a ViewNode.
///
/// Metadata is O(data count). Mounted and candidate groups obey explicit
/// record/leaf caps; a factory can itself create arbitrarily complex content
/// before returning, so those caps are not a bound on arbitrary authored work.
@MainActor
package final class RetainedLazyListRuntimeAdapter {
    package struct Viewport: Equatable, Sendable {
        package let context: RetainedLazyListMeasurementContext
        package let offset: Double
        package let extent: Double

        package init?(
            context: RetainedLazyListMeasurementContext, offset: Double, extent: Double
        ) {
            guard offset.isFinite, extent.isFinite, extent >= 0 else { return nil }
            self.context = context
            self.offset = offset
            self.extent = extent
        }
    }

    /// Native freshness for an already admitted scalar geometry correction.
    /// It keeps no adapter, provider, or node alive and does not authorize
    /// construction, node adoption, focus, or accessibility operations.
    @MainActor
    final class LayoutProof {
        private weak var adapter: RetainedLazyListRuntimeAdapter?
        private let configuration: RetainedLazyListAdapterIdentity
        private let generation: RetainedLazyListGeneration

        fileprivate init(
            adapter: RetainedLazyListRuntimeAdapter,
            configuration: RetainedLazyListAdapterIdentity,
            generation: RetainedLazyListGeneration
        ) {
            self.adapter = adapter
            self.configuration = configuration
            self.generation = generation
        }

        var isCurrent: Bool {
            guard let adapter else { return false }
            return !adapter.isReleasing && adapter.configuration === configuration
                && adapter.generation == generation && generation.isCurrent
        }
    }

    package struct Placement {
        package let token: RetainedLazyListRowToken
        package let leafIndex: Int
        package let node: ViewNode
        /// Unmeasured leaves share their record's prefix. Runtime measures
        /// their natural heights and accumulates them, then lays them out.
        package let originY: Double
        /// Nil is unknown, not an invented equal share of the record estimate.
        package let extent: Double?
    }

    package struct LayoutPlan {
        package let contentExtent: Double
        package let placements: [Placement]
        package let hasLogicalOmissions: Bool
        package let requiresResolution: Bool
    }

    package struct Measurement {
        package let token: RetainedLazyListRowToken
        package let leafIndex: Int
        package let node: ViewNode
        package let extent: Double
    }

    package struct MeasurementUpdate {
        package let extentChanged: Bool
        package let requiresLayout: Bool
        package let anchorAdjustedOffset: Double?
    }

    package enum Preparation {
        case ready(Candidate)
        case unchanged
        case workRemaining
        case obsolete
        case unsupported
    }

    fileprivate struct Record {
        let request: RetainedLazyListRowRequest
        let nodes: [ViewNode]
        var extents: [Double]?
        let configuration: RetainedLazyListAdapterIdentity
        let identityProofs: [RetainedLazyListViewIdentityProof]
        let activity: RetainedLazyListMaterializedRowActivity?

        init(
            request: RetainedLazyListRowRequest, nodes: [ViewNode], extents: [Double]?,
            configuration: RetainedLazyListAdapterIdentity,
            identityProofs: [RetainedLazyListViewIdentityProof] = [],
            activity: RetainedLazyListMaterializedRowActivity? = nil
        ) {
            self.request = request
            self.nodes = nodes
            self.extents = extents
            self.configuration = configuration
            self.identityProofs = identityProofs
            self.activity = activity
        }
    }

    /// Permission to preserve an already attached actual row while another
    /// bounded slice refreshes the descriptor. It grants no source-generation,
    /// measurement, contribution, task, or property-copy authority to that row.
    @MainActor
    fileprivate final class CarriedRecordProof {
        let token: RetainedLazyListRowToken
        let container: RetainedLazyListActualAttachment
        let roots: [RetainedLazyListActualAttachment]
        let activity: RetainedLazyListMaterializedRowActivity
        let identities: [RetainedLazyListViewIdentityProof]

        init(
            record: Record, container: RetainedLazyListActualAttachment,
            roots: [RetainedLazyListActualAttachment], activity: RetainedLazyListMaterializedRowActivity
        ) {
            token = record.request.token
            self.container = container
            self.roots = roots
            self.activity = activity
            identities = record.identityProofs
        }

        var isCurrent: Bool {
            guard container.isAttached, let owner = container.node,
                activity.request.token == token, activity.logicalMembership.isDeclared,
                activity.physical.state == .active, identities.allSatisfy(\.isCurrent)
            else { return false }
            let physicalAttachments = activity.physical.actualAttachments
            if roots.isEmpty {
                return physicalAttachments.contains {
                    $0.target === container.target && $0.attachment === container.attachment && $0.isAttached
                }
            }
            return roots.allSatisfy { actual in
                actual.isAttached && actual.node?.parent === owner
                    && owner.children.contains(where: { $0 === actual.node })
                    && physicalAttachments.contains {
                        $0.target === actual.target && $0.attachment === actual.attachment && $0.isAttached
                    }
            }
        }
    }

    private enum RecordPreparation {
        case record(Record)
        case skippedOptional
        case deferredForCapacity
        case workRemaining
        case obsolete
        case unsupported
    }

    private struct PreparationAuthority {
        let attempt: RetainedLazyListAdapterIdentity
        let configuration: RetainedLazyListAdapterIdentity
        let generation: RetainedLazyListGeneration
        let admission: RetainedLazyListAdoptionAdmission?
        let previousIdentityProofs: [RetainedLazyListViewIdentityProof]
        let managed: ManagedPreparation?
        var carriedRecordProofs: [CarriedRecordProof] = []
        // Only synchronous probe authority carries this additional request
        // gate. Nothing stores it after the adapter method returns.
        var probeRequestIsCurrent: (@MainActor () -> Bool)? = nil
    }

    /// Per-attempt transport, never a provider capture. The descriptor remains
    /// present on the adapter after rejection, so failure cannot select raw work.
    private struct ManagedPreparation {
        let descriptor: RetainedLazyListManagedLogicalDescriptorBinding
        let activity: any RetainedLazyListBuildActivity
        let journal: RetainedLazyListAdoptionJournal
    }

    @MainActor
    private final class StagedPredecessor {
        weak var adapter: RetainedLazyListRuntimeAdapter?
        let attachment: RetainedLazyListActualAttachment
        let configuration: RetainedLazyListAdapterIdentity
        let descriptor: RetainedLazyListManagedLogicalDescriptorBinding
        let continuation: RetainedLazyListProviderContinuation

        init(
            adapter: RetainedLazyListRuntimeAdapter, attachment: RetainedLazyListActualAttachment,
            descriptor: RetainedLazyListManagedLogicalDescriptorBinding,
            continuation: RetainedLazyListProviderContinuation
        ) {
            self.adapter = adapter
            self.attachment = attachment
            configuration = adapter.configuration
            self.descriptor = descriptor
            self.continuation = continuation
        }
    }

    /// A candidate is not an adoption authorization. Runtime wraps this native
    /// proof with its physical attachment, lease identity, and coordinator
    /// admission. No provider/protocol getter is called by isCurrent.
    @MainActor
    package final class Candidate {
        package private(set) var children: [ViewNode]
        package let viewport: Viewport
        /// Only surviving logical rows omitted by this candidate are viewport
        /// evictions. Deletion and same-row leaf replacement keep structural
        /// teardown/transition semantics in Runtime.
        package let virtualizedDepartureRoots: Set<ObjectIdentifier>
        fileprivate private(set) var records: [Record]
        fileprivate let requestProofs: [RetainedLazyListRowRequest]
        fileprivate let identityProofs: [RetainedLazyListViewIdentityProof]
        fileprivate let generation: RetainedLazyListGeneration
        fileprivate let configuration: RetainedLazyListAdapterIdentity
        fileprivate let attempt: RetainedLazyListAdapterIdentity
        fileprivate let protectedTokens: Set<RetainedLazyListRowToken>
        fileprivate let carriedRecordProofs: [RetainedLazyListRowToken: CarriedRecordProof]
        fileprivate weak var adapter: RetainedLazyListRuntimeAdapter?
        fileprivate var wasCompleted = false
        fileprivate var wasConsumed = false
        fileprivate let departingEmptyRows: [(RetainedLazyListMaterializedRowActivity, RetainedLazyListDepartureCause)]
        fileprivate var didClaimEmptyDepartures = false
        private var emptyRowContinuations: [ObjectIdentifier: RetainedLazyListEmptyRowContinuation]
        private var managedPreparation: RetainedLazyListAdoptionPreparation?
        private var completedSourceRoots: [ObjectIdentifier: (ViewNode, RetainedLazyListAdoptionCompletion)] = [:]
        private var completedRows: Set<ObjectIdentifier> = []

        fileprivate init(
            adapter: RetainedLazyListRuntimeAdapter, viewport: Viewport, records: [Record],
            generation: RetainedLazyListGeneration,
            configuration: RetainedLazyListAdapterIdentity,
            attempt: RetainedLazyListAdapterIdentity,
            protectedTokens: Set<RetainedLazyListRowToken>,
            virtualizedDepartureRoots: Set<ObjectIdentifier>,
            departingEmptyRows: [(RetainedLazyListMaterializedRowActivity, RetainedLazyListDepartureCause)] = [],
            emptyRowContinuations: [ObjectIdentifier: RetainedLazyListEmptyRowContinuation] = [:],
            carriedRecordProofs: [RetainedLazyListRowToken: CarriedRecordProof] = [:]
        ) {
            self.adapter = adapter
            self.viewport = viewport
            self.records = records
            self.children = records.flatMap(\.nodes)
            self.requestProofs = records.filter { carriedRecordProofs[$0.request.token] == nil }.map(\.request)
            self.identityProofs = records.flatMap(\.identityProofs)
            self.generation = generation
            self.configuration = configuration
            self.attempt = attempt
            self.protectedTokens = protectedTokens
            self.carriedRecordProofs = carriedRecordProofs
            self.virtualizedDepartureRoots = virtualizedDepartureRoots
            self.departingEmptyRows = departingEmptyRows
            self.emptyRowContinuations = emptyRowContinuations
        }

        package var isCurrent: Bool { adapter?.isCurrent(self) == true }

        package var recordLeafCounts: [Int] { records.map { $0.nodes.count } }

        func configureManagedPublication(_ preparation: RetainedLazyListAdoptionPreparation) -> Bool {
            guard isCurrent, managedPreparation == nil else { return false }
            managedPreparation = preparation
            return true
        }

        /// Each notification follows checked completion of this exact source
        /// root, including its descendants. Other rows may still fail later.
        func recordCompletedSource(
            from source: ViewNode, to actual: ViewNode, in container: ViewNode,
            journal: RetainedLazyListAdoptionJournal
        ) {
            guard isCurrent, journal.canContinueAdoption,
                let record = records.first(where: { record in record.nodes.contains(where: { $0 === source }) }),
                let activity = record.activity, activity.attempt === journal.attempt,
                !completedRows.contains(ObjectIdentifier(activity)), actual.parent === container,
                let completion = RetainedLazyListAdoptionCompletion(of: actual), completion.isCurrent
            else { return }
            completedSourceRoots[ObjectIdentifier(source)] = (actual, completion)
            var actualNodes: [ViewNode] = []
            for sourceRoot in record.nodes {
                guard let (retained, proof) = completedSourceRoots[ObjectIdentifier(sourceRoot)],
                    proof.isCurrent, retained.parent === container
                else { return }
                actualNodes.append(retained)
            }
            guard let runtime = container.retainedLazyListRuntime else { return }
            let anchor = container.lazyListActivityStorage().captureActualAttachment(of: container, in: runtime)
            guard
                journal.recordCompletedOwnedRow(
                    activity, sources: record.nodes, actualNodes: actualNodes, structuralAnchor: anchor)
            else { return }
            guard
                recordAcceptedEmptyContinuation(
                    for: activity, actualNodes: actualNodes, anchor: anchor, journal: journal)
            else { return }
            recordAcceptedEmptyEffects(for: activity, anchor: anchor, journal: journal)
            completedRows.insert(ObjectIdentifier(activity))
        }

        fileprivate func recordAcceptedEmptyRow(
            _ record: Record, anchor: RetainedLazyListActualAttachment, journal: RetainedLazyListAdoptionJournal
        ) -> Bool {
            guard record.nodes.isEmpty, let activity = record.activity else { return false }
            // A reused empty row already owns its accepted table entry.
            if activity.attempt !== journal.attempt || completedRows.contains(ObjectIdentifier(activity)) {
                return true
            }
            guard journal.recordCompletedOwnedRow(activity, sources: [], actualNodes: [], structuralAnchor: anchor)
            else {
                // The table write remains a partial native publication, but
                // this failed new receipt cannot be reused on the next pass.
                activity.physical.revoke()
                return false
            }
            guard recordAcceptedEmptyContinuation(for: activity, actualNodes: [], anchor: anchor, journal: journal)
            else { return false }
            recordAcceptedEmptyEffects(for: activity, anchor: anchor, journal: journal)
            completedRows.insert(ObjectIdentifier(activity))
            return true
        }

        fileprivate func completedNonemptyRows(in journal: RetainedLazyListAdoptionJournal) -> Bool {
            records.allSatisfy { record in
                guard !record.nodes.isEmpty, let activity = record.activity, activity.attempt === journal.attempt else {
                    return true
                }
                return completedRows.contains(ObjectIdentifier(activity))
            }
        }

        private func recordAcceptedEmptyEffects(
            for activity: RetainedLazyListMaterializedRowActivity, anchor: RetainedLazyListActualAttachment,
            journal: RetainedLazyListAdoptionJournal
        ) {
            for proposal in managedPreparation?.groups ?? []
            where proposal.membership === activity.logicalMembership.id && proposal.physical === activity.physical.id
                && proposal.construction == .closedEmpty
            {
                _ = journal.recordAcceptedEmpty(proposal, structuralAnchor: anchor)
            }
        }

        private func recordAcceptedEmptyContinuation(
            for activity: RetainedLazyListMaterializedRowActivity, actualNodes: [ViewNode],
            anchor: RetainedLazyListActualAttachment, journal: RetainedLazyListAdoptionJournal
        ) -> Bool {
            guard let continuation = emptyRowContinuations[ObjectIdentifier(activity)] else { return true }
            return journal.recordAcceptedEmptyRowContinuation(
                continuation, actualNodes: actualNodes, structuralAnchor: anchor)
        }

        /// Terminal cleanup still needs native operation evidence after source
        /// nodes are released. This never authorizes further node mutation or
        /// adoption and does not inspect the consumed nodes' identity proofs.
        var isOperationCurrent: Bool { adapter?.isOperationCurrent(self) == true }

        /// Runtime calls this under the still-active build coordinator for
        /// successful and abandoned candidates. Consume before dropping any
        /// payload so a destructor cannot reuse this candidate for adoption.
        /// The separate native operation proof survives for the final check.
        func discardBuiltContent() {
            guard !wasConsumed else { return }
            wasConsumed = true
            releaseBuiltContent()
        }

        private func releaseBuiltContent() {
            var previousChildren = children
            var previousRecords = records
            var previousCompletedRoots = completedSourceRoots
            children = []
            records = []
            completedSourceRoots = [:]
            managedPreparation = nil
            emptyRowContinuations = [:]
            // Release outside the stored-property accesses. Authored cleanup
            // may reenter; the candidate is already consumed and empty.
            withExtendedLifetime(previousChildren) {}
            withExtendedLifetime(previousRecords) {}
            previousChildren = []
            previousRecords = []
            withExtendedLifetime(previousCompletedRoots) {}
            previousCompletedRoots = [:]
        }
    }

    private struct Snapshot {
        let generation: RetainedLazyListGeneration
        let tokens: [RetainedLazyListRowToken]
        let positions: [RetainedLazyListRowToken: Int]
    }

    private struct WindowSelection {
        /// Required visible records, then optional nearest prefetch records.
        /// Final children are independently sorted into logical source order.
        let tokens: [RetainedLazyListRowToken]
        let requiredTokens: Set<RetainedLazyListRowToken>
        /// Optional prefetch outside the fixed allowance is not unresolved.
        let exceedsRecordLimit: Bool
    }

    private struct CoordinateRecord {
        let token: RetainedLazyListRowToken
        let position: Int
        let start: Double
        let end: Double
    }

    private struct ExtentUpdate {
        let token: RetainedLazyListRowToken
        let previous: RetainedLazyListExtent
        let next: RetainedLazyListExtent
    }

    private struct GapRowBoundary: Equatable, Sendable {
        let isSelected: Bool
        let isGrouped: Bool

        static let ordinary = Self(isSelected: false, isGrouped: false)

        init(isSelected: Bool, isGrouped: Bool) {
            self.isSelected = isSelected
            self.isGrouped = isGrouped
        }

        init(_ gap: RetainedLazyListGap) {
            isSelected = gap.nextRowIsSelected
            isGrouped = gap.nextRowIsGrouped
        }
    }

    private struct GapBoundarySummary: Equatable, Sendable {
        let first: GapRowBoundary?
        let last: GapRowBoundary?
        let projectedRowParity: Bool

        static let empty = Self(first: nil, last: nil, projectedRowParity: false)
    }

    private enum GapPredecessor {
        case beginning
        case row(GapRowBoundary)
        case unknown(position: Int)
    }

    /// Unknown and known nonempty records remain candidates. Known empty
    /// records leave this ordinal tree, so an arbitrary empty chain is skipped
    /// in O(log N), independently of zero or collapsed floating-point heights.
    /// These summaries never retain a row, authored key, callback, or payload.
    private struct GapBoundaryIndex {
        private let leafBase: Int
        private var summaries: [GapBoundarySummary?]
        private var lastCandidates: [Int]
        private var projectedParity: [Bool]
        private var unknownPrefix: [Bool]

        init?(recordCount: Int) {
            guard recordCount >= 0 else { return nil }
            var base = 1
            while base < recordCount {
                guard base <= Int.max / 2 else { return nil }
                base *= 2
            }
            guard base <= Int.max / 2 else { return nil }
            leafBase = base
            summaries = Array(repeating: nil, count: recordCount)
            lastCandidates = Array(repeating: -1, count: base * 2)
            projectedParity = Array(repeating: false, count: base * 2)
            unknownPrefix = Array(repeating: false, count: base * 2)
            for index in 0..<recordCount {
                lastCandidates[base + index] = index
                // Unknown cardinality contributes one provisional row, without
                // constructing its content or treating the estimate as known.
                projectedParity[base + index] = true
                unknownPrefix[base + index] = true
            }
            var node = base - 1
            while node > 0 {
                lastCandidates[node] = max(lastCandidates[node * 2], lastCandidates[node * 2 + 1])
                projectedParity[node] = projectedParity[node * 2] != projectedParity[node * 2 + 1]
                unknownPrefix[node] = unknownPrefix[node * 2] || unknownPrefix[node * 2 + 1]
                node -= 1
            }
        }

        mutating func update(at position: Int, to summary: GapBoundarySummary?) {
            precondition(summaries.indices.contains(position))
            guard summaries[position] != summary else { return }
            summaries[position] = summary
            var node = leafBase + position
            if let summary {
                lastCandidates[node] = summary.last == nil ? -1 : position
                projectedParity[node] = summary.projectedRowParity
                unknownPrefix[node] = false
            } else {
                lastCandidates[node] = position
                projectedParity[node] = true
                unknownPrefix[node] = true
            }
            node /= 2
            while node > 0 {
                lastCandidates[node] = max(lastCandidates[node * 2], lastCandidates[node * 2 + 1])
                projectedParity[node] = projectedParity[node * 2] != projectedParity[node * 2 + 1]
                unknownPrefix[node] = unknownPrefix[node * 2] || unknownPrefix[node * 2 + 1]
                node /= 2
            }
        }

        func matches(_ summary: GapBoundarySummary, at position: Int) -> Bool {
            summaries.indices.contains(position) && summaries[position] == summary
        }

        func predecessor(before position: Int) -> GapPredecessor {
            precondition(position >= 0 && position <= summaries.count)
            var lower = leafBase
            var upper = leafBase + position
            var candidate = -1
            while lower < upper {
                if !lower.isMultiple(of: 2) {
                    candidate = max(candidate, lastCandidates[lower])
                    lower += 1
                }
                if !upper.isMultiple(of: 2) {
                    upper -= 1
                    candidate = max(candidate, lastCandidates[upper])
                }
                lower /= 2
                upper /= 2
            }
            guard candidate >= 0 else { return .beginning }
            guard let summary = summaries[candidate], let boundary = summary.last else {
                return .unknown(position: candidate)
            }
            return .row(boundary)
        }

        func ordinalBefore(_ position: Int) -> (parity: Bool, hasUnknownPrefix: Bool) {
            precondition(position >= 0 && position <= summaries.count)
            var lower = leafBase
            var upper = leafBase + position
            var parity = false
            var hasUnknown = false
            while lower < upper {
                if !lower.isMultiple(of: 2) {
                    parity = parity != projectedParity[lower]
                    hasUnknown = hasUnknown || unknownPrefix[lower]
                    lower += 1
                }
                if !upper.isMultiple(of: 2) {
                    upper -= 1
                    parity = parity != projectedParity[upper]
                    hasUnknown = hasUnknown || unknownPrefix[upper]
                }
                lower /= 2
                upper /= 2
            }
            return (parity, hasUnknown)
        }
    }

    private let provider: any RetainedLazyListProvider<[ViewNode]>
    private var managedLogicalDescriptor: RetainedLazyListManagedLogicalDescriptorBinding?
    private let estimatedExtent: Double
    private let prefetchExtent: Double
    /// Count a gap after each projected leaf in the prefix index, then remove
    /// the one final gap from the content extent. Empty records add no gap.
    package let interLeafSpacing: Double
    private let maximumMountedRecords: Int
    private let maximumMountedLeaves: Int
    private let maximumProtectedRecords: Int
    private var configuration = RetainedLazyListAdapterIdentity()
    private var attempt = RetainedLazyListAdapterIdentity()
    private var generation: RetainedLazyListGeneration?
    private var tokens: [RetainedLazyListRowToken] = []
    private var positions: [RetainedLazyListRowToken: Int] = [:]
    // Do not retain value copies of this index in plans, candidates, or batches.
    // Its Array storage must remain unique during ordinary point updates.
    private var extentIndex: RetainedLazyListExtentIndex?
    private var gapBoundaryIndex: GapBoundaryIndex?
    // A moved index is old scalar geometry for the next anchor capture only.
    // generation stays nil until fresh metadata replaces all of its estimates.
    private var inheritedExtentSpacing: Double?
    private var mounted: [RetainedLazyListRowToken: Record] = [:]
    private var protectedTokens: Set<RetainedLazyListRowToken> = []
    // Only native tokens survive a descriptor exchange. During refresh every
    // previous visible actual root stays attached until the cohort has accepted
    // successor measurements, including when one element is admitted per pass.
    private var lastRequiredTokens: Set<RetainedLazyListRowToken> = []
    private var transitionRequiredTokens: Set<RetainedLazyListRowToken> = []
    private var transitionAwaitingMeasurements: Set<RetainedLazyListRowToken> = []
    private var transitionCapacityDeferred: Set<RetainedLazyListRowToken> = []
    private var logicalRealization: RetainedLazyListLogicalRealization?
    private(set) var logicalMembershipIdentity = RetainedLazyListMembershipIdentity()
    private var stagedPredecessor: StagedPredecessor?
    private weak var attachmentOwner: ViewNode?
    private var isPreparing = false
    private var isReleasing = false
    private var pendingCandidate = false
    private var preparationIncomplete = true
    private var acceptedSnapshot = false
    private var unresolvedWork = true

    package init?(
        provider: any RetainedLazyListProvider<[ViewNode]>,
        estimatedExtent: Double, prefetchExtent: Double,
        maximumMountedRecords: Int, maximumMountedLeaves: Int, maximumProtectedRecords: Int,
        interLeafSpacing: Double = 0
    ) {
        guard estimatedExtent.isFinite, estimatedExtent > 0,
            prefetchExtent.isFinite, prefetchExtent >= 0,
            interLeafSpacing.isFinite, interLeafSpacing >= 0,
            (estimatedExtent + interLeafSpacing).isFinite,
            maximumMountedRecords > 0, maximumMountedLeaves > 0, maximumProtectedRecords > 0
        else { return nil }
        self.provider = provider
        self.estimatedExtent = estimatedExtent
        self.prefetchExtent = prefetchExtent
        self.interLeafSpacing = interLeafSpacing
        self.maximumMountedRecords = maximumMountedRecords
        self.maximumMountedLeaves = maximumMountedLeaves
        self.maximumProtectedRecords = maximumProtectedRecords
    }

    /// Settlement reads only native cached evidence, never provider metadata.
    /// A present managed binding never becomes an ordinary provider merely
    /// because its receipt expired. Only fresh detached adapters can opt in.
    package func installManagedLogicalDescriptor(
        _ binding: RetainedLazyListManagedLogicalDescriptorBinding
    ) -> Bool {
        guard managedLogicalDescriptor == nil, attachmentOwner == nil,
            generation == nil, mounted.isEmpty, !isPreparing, !isReleasing,
            !pendingCandidate, binding.isCurrent
        else { return false }
        managedLogicalDescriptor = binding
        return true
    }

    internal var managedLogicalDescriptorBinding: RetainedLazyListManagedLogicalDescriptorBinding? {
        managedLogicalDescriptor
    }

    var hasStagedPredecessor: Bool { stagedPredecessor != nil }

    /// Runtime first identifies the accepted actual container using its
    /// canonical identity and descriptor scope. This cast invokes no provider.
    package func dataSource<Element>(for type: Element.Type) -> RetainedLazyListDataSource<Element, [ViewNode]>? {
        guard !isPreparing, !isReleasing, attachmentOwner != nil,
            managedLogicalDescriptor?.isCurrent == true
        else { return nil }
        return provider as? RetainedLazyListDataSource<Element, [ViewNode]>
    }

    /// Only a fresh detached adapter can propose continuation. Staging captures
    /// weak physical provenance but neither moves rows nor touches the source.
    package func stagePredecessor(
        _ predecessor: RetainedLazyListRuntimeAdapter,
        continuation: RetainedLazyListProviderContinuation
    ) -> Bool {
        guard stagedPredecessor == nil, predecessor !== self,
            attachmentOwner == nil, generation == nil, mounted.isEmpty, extentIndex == nil,
            !isPreparing, !isReleasing, !pendingCandidate,
            !predecessor.isPreparing, !predecessor.isReleasing,
            let owner = predecessor.attachmentOwner, let runtime = owner.retainedLazyListRuntime,
            owner.retainedLazyListAdapter === predecessor,
            let descriptor = managedLogicalDescriptor,
            let previousDescriptor = predecessor.managedLogicalDescriptor,
            descriptor.isCurrent, previousDescriptor.isCurrent,
            descriptor.scope === previousDescriptor.scope,
            descriptor.sourceGeneration == continuation.successorGeneration,
            previousDescriptor.sourceGeneration == continuation.predecessorGeneration,
            continuation.matches(predecessor: predecessor.provider, successor: provider)
        else { return false }
        let attachment = owner.lazyListActivityStorage().captureActualAttachment(of: owner, in: runtime)
        guard attachment.isAttached else { return false }
        stagedPredecessor = StagedPredecessor(
            adapter: predecessor, attachment: attachment,
            descriptor: previousDescriptor, continuation: continuation)
        return true
    }

    /// Used during native child-plan preflight and again at the accepted
    /// property exchange. No typed key, provider getter, or factory runs here.
    func canInheritMountedRecords(from predecessor: RetainedLazyListRuntimeAdapter, in container: ViewNode) -> Bool {
        guard let stagedPredecessor, stagedPredecessor.adapter === predecessor,
            stagedPredecessor.attachment.node === container, stagedPredecessor.attachment.isAttached,
            predecessor.attachmentOwner === container,
            container.retainedLazyListAdapter === predecessor || container.retainedLazyListAdapter === self,
            predecessor.configuration === stagedPredecessor.configuration,
            predecessor.managedLogicalDescriptor === stagedPredecessor.descriptor,
            let descriptor = managedLogicalDescriptor, descriptor.isCurrent,
            stagedPredecessor.descriptor.isCurrent,
            descriptor.scope === stagedPredecessor.descriptor.scope,
            descriptor.sourceGeneration == stagedPredecessor.continuation.successorGeneration,
            stagedPredecessor.descriptor.sourceGeneration == stagedPredecessor.continuation.predecessorGeneration,
            stagedPredecessor.continuation.matches(predecessor: predecessor.provider, successor: provider),
            attachmentOwner == nil, generation == nil, mounted.isEmpty, extentIndex == nil,
            !isPreparing, !isReleasing, !pendingCandidate,
            !predecessor.isPreparing, !predecessor.isReleasing,
            predecessor.mounted.count <= maximumMountedRecords
        else { return false }
        let leaves = predecessor.mounted.values.flatMap(\.nodes)
        guard leaves.count <= maximumMountedLeaves, leaves.count == container.children.count else { return false }
        let identities = Set(leaves.map(ObjectIdentifier.init))
        return identities.count == leaves.count
            && container.children.allSatisfy { $0.parent === container && identities.contains(ObjectIdentifier($0)) }
    }

    /// Runtime calls after publishing this adapter and its logical declaration,
    /// before releasing the predecessor. Unregister must not revoke the old
    /// configuration before this exact transfer has consumed its proof.
    @discardableResult
    func inheritMountedRecords(from predecessor: RetainedLazyListRuntimeAdapter, in container: ViewNode) -> Bool {
        guard container.retainedLazyListAdapter === self,
            canInheritMountedRecords(from: predecessor, in: container)
        else { return false }
        predecessor.revokePendingCandidate()
        revokePendingCandidate()
        // Move, rather than copy-and-release: the old release path must not
        // revoke empty-row physical receipts now owned by this adapter.
        mounted = predecessor.mounted
        predecessor.mounted = [:]
        extentIndex = predecessor.extentIndex
        predecessor.extentIndex = nil
        inheritedExtentSpacing = predecessor.inheritedExtentSpacing ?? predecessor.interLeafSpacing
        predecessor.inheritedExtentSpacing = nil
        tokens = predecessor.tokens
        predecessor.tokens = []
        positions = predecessor.positions
        predecessor.positions = [:]
        predecessor.generation = nil
        predecessor.protectedTokens = []
        lastRequiredTokens = predecessor.lastRequiredTokens
        predecessor.lastRequiredTokens = []
        transitionRequiredTokens = predecessor.transitionRequiredTokens
        predecessor.transitionRequiredTokens = []
        transitionAwaitingMeasurements = predecessor.transitionAwaitingMeasurements
        predecessor.transitionAwaitingMeasurements = []
        logicalRealization = predecessor.logicalRealization
        predecessor.logicalRealization = nil
        logicalMembershipIdentity = predecessor.logicalMembershipIdentity
        stagedPredecessor = nil
        // The old records' configuration and requests are intentionally stale.
        // Their nodes/physical receipts can reconcile, but every new row output
        // must pass this source's factory and current checked admission.
        generation = nil
        return true
    }

    package var hasUnresolvedWork: Bool {
        unresolvedWork || isPreparing || isReleasing || generation?.isCurrent != true
    }

    package var hasCurrentLogicalSnapshot: Bool {
        acceptedSnapshot && !isPreparing && !isReleasing && generation?.isCurrent == true
            && managedLogicalDescriptor?.isCurrent != false && extentIndex != nil
    }

    package var currentLogicalGeneration: RetainedLazyListGeneration? {
        hasCurrentLogicalSnapshot ? generation : nil
    }

    /// Accepted logical metadata is available before the first viewport visit.
    /// This count neither prepares a physical snapshot nor consults a provider.
    package var logicalRecordCount: Int {
        guard let descriptor = managedLogicalDescriptor else { return tokens.count }
        guard descriptor.isCurrent, descriptor.scope.containsDeclaredDescriptor(descriptor.descriptor) else { return 0 }
        return descriptor.declaredRecordCount
    }
    package var contentExtent: Double {
        max(0, (extentIndex?.totalExtent ?? 0) - (inheritedExtentSpacing ?? interLeafSpacing))
    }
    package var mountedRecordCount: Int { mounted.count }
    package var mountedLeafCount: Int { mounted.values.reduce(0) { $0 + $1.nodes.count } }

    /// Logical lookup may call authored Hashable code; the runtime adds its
    /// original attachment proof around this provider boundary. No row factory
    /// participates, and a superseded configuration cannot publish a token.
    package func token(for key: RetainedViewIdentity.Key, occurrence: Int = 0) -> RetainedLazyListRowToken? {
        guard occurrence >= 0, acceptedSnapshot, !isPreparing, !isReleasing,
            let generation, generation.isCurrent
        else { return nil }
        let originalConfiguration = configuration
        let result = provider.token(for: key, occurrence: occurrence)
        guard acceptedSnapshot, !isPreparing, !isReleasing,
            self.generation == generation, generation.isCurrent,
            configuration === originalConfiguration, let result, positions[result] != nil
        else { return nil }
        return result
    }

    /// Cached native metadata is suitable for enumeration, never permission
    /// to construct or invoke a row. Logical records have no ViewNode slot.
    package func containsLogicalToken(_ token: RetainedLazyListRowToken) -> Bool {
        hasCurrentLogicalSnapshot && positions[token] != nil
    }

    /// Accepted logical presence survives the interval before a successor's
    /// first prepared snapshot. Moved predecessor positions are not evidence
    /// for that interval, and this check never grants physical row authority.
    func containsAcceptedLogicalToken(_ token: RetainedLazyListRowToken) -> Bool {
        guard !isPreparing, !isReleasing, let owner = attachmentOwner,
            owner.retainedLazyListAdapter === self
        else { return false }
        guard let descriptor = managedLogicalDescriptor else { return containsLogicalToken(token) }
        guard descriptor.isCurrent, descriptor.scope.containsDeclaredDescriptor(descriptor.descriptor) else {
            return false
        }
        if hasCurrentLogicalSnapshot {
            return generation == descriptor.sourceGeneration && positions[token] != nil
        }
        guard let nativeProvider = provider as? any RetainedLazyListNativeTokenMembershipProvider else {
            return false
        }
        return nativeProvider.containsCommittedToken(token, in: descriptor.sourceGeneration)
    }

    /// Runtime supplies current native focus/interaction roots at each layout
    /// opportunity. Expired weak owners must not leave an old physical pin in
    /// the cache merely because no provider or viewport work is otherwise due.
    @discardableResult
    package func updateProtectedRoots(_ roots: Set<ObjectIdentifier>) -> Bool {
        guard !isPreparing, !isReleasing, roots.count <= maximumMountedLeaves else { return false }
        var rootsToTokens: [ObjectIdentifier: RetainedLazyListRowToken] = [:]
        if !roots.isEmpty {
            guard let owner = attachmentOwner, let runtime = owner.retainedLazyListRuntime else { return false }
            for (token, record) in mounted {
                for node in record.nodes
                where node.parent === owner && node.retainedLazyListRuntime === runtime
                    && owner.children.contains(where: { $0 === node })
                {
                    rootsToTokens[ObjectIdentifier(node)] = token
                }
            }
        }
        var next: Set<RetainedLazyListRowToken> = []
        for root in roots {
            guard let token = rootsToTokens[root], let record = mounted[token] else { return false }
            if positions[token] != nil, record.activity?.logicalMembership.isDeclared != false { next.insert(token) }
        }
        guard next.count <= maximumProtectedRecords, next.count <= maximumMountedRecords else { return false }
        if next != protectedTokens {
            protectedTokens = next
            unresolvedWork = true
        }
        return true
    }

    package func beginLogicalRealization(
        of token: RetainedLazyListRowToken, owner: RetainedLazyListLogicalRealizationOwner
    ) -> RetainedLazyListLogicalRealization? {
        discardRevokedLogicalRealization()
        let required = protectedTokens.union([token])
        guard containsLogicalToken(token), !pendingCandidate, logicalRealization == nil,
            required.count <= maximumProtectedRecords,
            required.union(transitionRequiredTokens).count <= maximumMountedRecords,
            transitionRequiredTokens.isEmpty || transitionRequiredTokens.contains(token) || mounted[token] != nil
        else { return nil }
        let realization = RetainedLazyListLogicalRealization(token: token, owner: owner)
        logicalRealization = realization
        unresolvedWork = true
        return realization
    }

    /// Runtime owns invalidation. Clearing a successful in-viewport UIA lease
    /// must not synchronously invalidate the projection it just established.
    package func endLogicalRealization(_ realization: RetainedLazyListLogicalRealization) {
        realization.revoke()
        guard logicalRealization === realization else { return }
        logicalRealization = nil
    }

    private func discardRevokedLogicalRealization() {
        guard let logicalRealization, !logicalRealization.isActive else { return }
        self.logicalRealization = nil
    }

    private var logicalRealizationTokenForSelection: RetainedLazyListRowToken? {
        guard let logicalRealization, logicalRealization.isActive, positions[logicalRealization.token] != nil else {
            return nil
        }
        // A request transferred before its first materialization can wait for
        // the original actual cohort to refresh. No existing requested row is
        // dropped, and an unbuilt demand cannot exhaust the transition's cap.
        if !transitionRequiredTokens.isEmpty, !transitionRequiredTokens.contains(logicalRealization.token),
            mounted[logicalRealization.token] == nil
        {
            return nil
        }
        return logicalRealization.token
    }

    package func logicalToken(after previous: RetainedLazyListRowToken?) -> RetainedLazyListRowToken? {
        guard acceptedSnapshot, !isPreparing, !isReleasing, generation?.isCurrent == true else { return nil }
        let position: Int
        if let previous {
            guard let preceding = positions[previous], preceding < tokens.count - 1 else { return nil }
            position = preceding + 1
        } else {
            position = 0
        }
        return tokens.indices.contains(position) ? tokens[position] : nil
    }

    package func logicalBounds(for token: RetainedLazyListRowToken) -> (origin: Double, extent: Double)? {
        guard containsLogicalToken(token), let position = positions[token],
            let prefix = extentIndex?.prefixOffset(before: position),
            let end = extentIndex?.prefixOffset(before: position + 1)
        else { return nil }
        return (prefix, max(0, end - prefix - interLeafSpacing))
    }

    package func knownLeafCount(for token: RetainedLazyListRowToken) -> Int? {
        guard containsLogicalToken(token) else { return nil }
        return extentIndex?.extent(for: token)?.measuredLeafCount
    }

    package func mountedNodes(for token: RetainedLazyListRowToken) -> [ViewNode]? {
        guard containsLogicalToken(token), let record = mounted[token], recordIsCurrent(record) else { return nil }
        return record.nodes
    }

    /// Native prefix parity for an accepted measured target record. Unknown
    /// earlier cardinality contributes one provisional row and remains flagged;
    /// it never requests factories or creates measurement/ownership authority.
    package func projectedRowOrdinalBefore(
        _ token: RetainedLazyListRowToken
    ) -> (parity: Bool, hasUnknownPrefix: Bool)? {
        guard hasCurrentLogicalSnapshot, refreshAcceptedGapBoundarySummaries(),
            let position = positions[token], let record = mounted[token], recordIsCurrent(record),
            record.extents != nil, !hasUnresolvedLeadingGap(record)
        else { return nil }
        return gapBoundaryIndex?.ordinalBefore(position)
    }

    package func mountedToken(containing node: ViewNode) -> RetainedLazyListRowToken? {
        guard let owner = attachmentOwner else { return nil }
        var root = node
        var depth = 0
        while let parent = root.parent, parent !== owner, depth < ViewNode.maximumTraversalDepth {
            root = parent
            depth += 1
        }
        guard root.parent === owner, owner.children.contains(where: { $0 === root }) else { return nil }
        for (token, record) in mounted where recordIsCurrent(record) {
            if record.nodes.contains(where: { $0 === root }) { return token }
        }
        return nil
    }
    var materializedRowActivities: [RetainedLazyListMaterializedRowActivity] {
        mounted.values.compactMap(\.activity)
    }

    /// Runtime separately validates the physical owner and geometry context.
    /// Provider freshness alone cannot detect a same-provider invalidation.
    func captureLayoutProof() -> LayoutProof? {
        guard acceptedSnapshot, !isReleasing, extentIndex != nil,
            let generation, generation.isCurrent
        else { return nil }
        return LayoutProof(adapter: self, configuration: configuration, generation: generation)
    }

    /// Claim only an actual retained container, never a build descriptor. One
    /// weak claim also excludes a second container in a different Runtime.
    /// Runtime still checks its own live attachment and lease before adoption.
    package func claimAttachment(to node: ViewNode) -> Bool {
        guard !isReleasing else { return false }
        if let attachmentOwner { return attachmentOwner === node }
        revokePendingCandidate()
        attachmentOwner = node
        return true
    }

    package func ownsAttachment(_ node: ViewNode) -> Bool { attachmentOwner === node }

    /// A foreign or stale owner cannot revoke another container's claim.
    /// Dropping mounted payloads remains a separate post-teardown operation.
    @discardableResult
    package func releaseAttachment(from node: ViewNode) -> Bool {
        guard attachmentOwner === node else { return false }
        revokePendingCandidate()
        attachmentOwner = nil
        return true
    }

    /// These wrappers let Runtime preserve one keyed anchor across metadata
    /// replacement, zero-leaf adoption, and subsequent measured-height updates.
    /// They do not implement authored scroll anchors or interaction policy.
    package func captureAnchor(at offset: Double) -> RetainedLazyListAnchor? {
        extentIndex?.captureAnchor(at: offset)
    }

    package func resolveAnchor(
        _ anchor: RetainedLazyListAnchor, viewportExtent: Double
    ) -> Double? {
        guard let offset = extentIndex?.resolveAnchor(anchor, viewportExtent: viewportExtent) else { return nil }
        return min(offset, max(0, contentExtent - viewportExtent))
    }

    /// Cached scalar/native reads only. Runtime validates the vertical axis,
    /// finite viewport, matching leaf spacing, and supported alignment here.
    /// Unknown offscreen extents do not prevent a settled current window.
    package func layoutPlan(viewport: Viewport) -> LayoutPlan {
        discardRevokedLogicalRealization()
        guard snapshotIsCurrent(for: viewport),
            refreshAcceptedGapBoundarySummaries(),
            let selection = windowSelection(viewport, protecting: protectedTokens)
        else {
            unresolvedWork = true
            return LayoutPlan(
                contentExtent: contentExtent, placements: [],
                hasLogicalOmissions: !tokens.isEmpty, requiresResolution: true)
        }
        var placements: [Placement] = []
        for token in mounted.keys.sorted(by: { positions[$0, default: Int.max] < positions[$1, default: Int.max] }) {
            guard let record = mounted[token], recordIsCurrent(record),
                let position = positions[token], let prefix = extentIndex?.prefixOffset(before: position),
                let end = extentIndex?.prefixOffset(before: position + 1)
            else { continue }
            var localOffset = 0.0
            var predecessor = gapPredecessor(before: position)
            var declaredNext: GapRowBoundary?
            for (leafIndex, node) in record.nodes.enumerated() {
                let height: Double?
                if let gap = node.retainedLazyListGap {
                    height = gapExtent(gap, after: predecessor)
                    declaredNext = GapRowBoundary(gap)
                } else {
                    height = record.extents?[leafIndex]
                    predecessor = .row(declaredNext ?? .ordinary)
                    declaredNext = nil
                }
                placements.append(
                    Placement(
                        token: token, leafIndex: leafIndex, node: node,
                        originY: min(end, prefix + localOffset), extent: height))
                if let height {
                    // Accumulate locally before adding a large global prefix:
                    // adding each tiny leaf directly to 2^53 would lose every
                    // increment. The represented record end is still a clamp.
                    localOffset += height + interLeafSpacing
                }
            }
        }
        unresolvedWork = needsResolution(selection: selection)
        rememberRequiredActualRows(selection)
        return LayoutPlan(
            contentExtent: contentExtent, placements: placements,
            hasLogicalOmissions: tokens.count > mounted.count,
            requiresResolution: unresolvedWork)
    }

    /// Call only after layout traversal and within Runtime's existing retained
    /// build scope. Every protocol call can reenter; the native attempt is
    /// checked after it returns and after temporary metadata has been released.
    /// Runtime consumes shared convergence rounds; materialize consumes elements.
    package func prepare(
        viewport: Viewport, protectedRoots: Set<ObjectIdentifier>,
        budget: RetainedLazyListWorkBudget
    ) -> Preparation {
        prepare(
            viewport: viewport, protectedRoots: protectedRoots, budget: budget,
            checkedAdmission: nil, managed: nil)
    }

    /// Runtime's concrete physical admission is deliberately internal; the
    /// package planning entry above keeps its raw-node model contract.
    func prepare(
        viewport: Viewport, protectedRoots: Set<ObjectIdentifier>,
        budget: RetainedLazyListWorkBudget, admission: RetainedLazyListAdoptionAdmission,
        activity: (any RetainedLazyListBuildActivity)? = nil,
        journal: RetainedLazyListAdoptionJournal? = nil,
        preserving anchor: RetainedLazyListAnchor? = nil
    ) -> Preparation {
        guard admission.isBuildCurrent(for: self) else { return .obsolete }
        let managed: ManagedPreparation?
        if let descriptor = managedLogicalDescriptor {
            guard descriptor.isCurrent, let activity, let journal, journal.canContinueConstruction else {
                return .obsolete
            }
            managed = ManagedPreparation(descriptor: descriptor, activity: activity, journal: journal)
        } else {
            managed = nil
        }
        let result = prepare(
            viewport: viewport, protectedRoots: protectedRoots, budget: budget,
            checkedAdmission: admission, managed: managed, preserving: anchor)
        // The shared helper's temporary payloads have finished unwinding.
        guard admission.isBuildCurrent(for: self), managedPreparationIsCurrent(managed) else { return .obsolete }
        return result
    }

    func ownsCandidate(_ candidate: Candidate) -> Bool { isCurrent(candidate) }

    private func prepare(
        viewport: Viewport, protectedRoots: Set<ObjectIdentifier>,
        budget: RetainedLazyListWorkBudget, checkedAdmission: RetainedLazyListAdoptionAdmission?,
        managed: ManagedPreparation?, preserving anchor: RetainedLazyListAnchor? = nil
    ) -> Preparation {
        discardRevokedLogicalRealization()
        guard checkedAdmission?.isBuildCurrent(for: self) != false, managedPreparationIsCurrent(managed) else {
            return .obsolete
        }
        guard !isPreparing, !isReleasing else {
            revokePendingCandidate()
            return .obsolete
        }
        isPreparing = true
        defer { isPreparing = false }
        let wasIncomplete = preparationIncomplete
        preparationIncomplete = true
        unresolvedWork = true
        pendingCandidate = false
        attempt = RetainedLazyListAdapterIdentity()
        let expectedAttempt = attempt
        var expectedConfiguration = configuration
        var selectionViewport = viewport

        if !snapshotIsCurrent(for: viewport) {
            let widthSnapshot = cachedSnapshotForManagedWidthChange(
                viewport, wasIncomplete: wasIncomplete, managed: managed)
            let remeasuredRecords =
                widthSnapshot == nil
                ? [:]
                : mounted.filter { recordIsCurrent($0.value) && carriedRecordProof(for: $0.value) != nil }
            var previousRequired = transitionRequiredTokens.union(lastRequiredTokens)
            if managed != nil, let anchor, mounted[anchor.token] != nil {
                previousRequired.insert(anchor.token)
            }
            if managed != nil, let realization = logicalRealization, realization.isActive,
                mounted[realization.token] != nil
            {
                previousRequired.insert(realization.token)
            }
            guard
                let snapshot = widthSnapshot
                    ?? readSnapshot(
                        expectedAttempt: expectedAttempt, expectedConfiguration: expectedConfiguration,
                        admission: checkedAdmission),
                operationIsCurrent(
                    expectedAttempt, configuration: expectedConfiguration, admission: checkedAdmission),
                snapshot.generation.isCurrent
            else { return .obsolete }
            guard let estimate = RetainedLazyListExtent.estimated(estimatedExtent + interLeafSpacing),
                let nextIndex = RetainedLazyListExtentIndex(
                    tokens: snapshot.tokens,
                    extents: Array(repeating: estimate, count: snapshot.tokens.count),
                    context: viewport.context),
                let nextBoundaryIndex = GapBoundaryIndex(recordCount: snapshot.tokens.count)
            else { return .unsupported }
            generation = snapshot.generation
            tokens = snapshot.tokens
            positions = snapshot.positions
            extentIndex = nextIndex
            gapBoundaryIndex = nextBoundaryIndex
            inheritedExtentSpacing = nil
            transitionRequiredTokens =
                managed == nil
                ? [] : Set(previousRequired.filter { snapshot.positions[$0] != nil && mounted[$0] != nil })
            transitionAwaitingMeasurements = transitionRequiredTokens
            transitionCapacityDeferred = []
            lastRequiredTokens = Set(lastRequiredTokens.filter { snapshot.positions[$0] != nil })
            configuration = RetainedLazyListAdapterIdentity()
            expectedConfiguration = configuration
            // A width-only change invalidates geometry, not an accepted
            // managed row's declaration. Keep its exact physical activity and
            // identity witnesses, but discard all old leaf measurements. The
            // new configuration still revokes every earlier layout proof.
            for (token, record) in remeasuredRecords {
                mounted[token] = Record(
                    request: record.request, nodes: record.nodes, extents: nil,
                    configuration: configuration, identityProofs: record.identityProofs, activity: record.activity)
            }
            acceptedSnapshot = false
            // Runtime owns whether this anchor may control scrolling. Select
            // the future anchored window before adopting any row departures;
            // selecting the old numeric offset would evict the very keyed rows
            // that the post-adoption anchor correction is meant to preserve.
            if let anchor, let offset = extentIndex?.resolveAnchor(anchor, viewportExtent: 0) {
                var selectionOffset = offset
                if let position = positions[anchor.token],
                    let start = extentIndex?.prefixOffset(before: position),
                    let end = extentIndex?.prefixOffset(before: position + 1), start < end
                {
                    // An old intra-row offset can clamp exactly to the fresh
                    // estimate's end. Select inside that record; Runtime still
                    // publishes the unmodified anchor after actual measurement.
                    selectionOffset = max(start, min(selectionOffset, end.nextDown))
                }
                if let adjusted = Viewport(
                    context: viewport.context, offset: selectionOffset, extent: viewport.extent)
                {
                    selectionViewport = adjusted
                }
            }
        }
        guard let generation, generation.isCurrent,
            operationIsCurrent(
                expectedAttempt, configuration: expectedConfiguration, admission: checkedAdmission)
        else { return .obsolete }
        guard refreshAcceptedGapBoundarySummaries() else { return .unsupported }
        guard protectedRoots.count <= maximumMountedLeaves else { return .workRemaining }

        var rootsToTokens: [ObjectIdentifier: RetainedLazyListRowToken] = [:]
        for (token, record) in mounted {
            for node in record.nodes { rootsToTokens[ObjectIdentifier(node)] = token }
        }
        var nextProtected: Set<RetainedLazyListRowToken> = []
        for root in protectedRoots {
            guard let token = rootsToTokens[root] else { return .unsupported }
            // Logical deletion is not an offscreen eviction exemption. Runtime
            // still performs complete departure and interaction-owner cleanup.
            if positions[token] != nil { nextProtected.insert(token) }
        }
        // Persist only physical focus/interaction protection. The explicit
        // realization is unioned for this selection, never frozen into a
        // candidate that could restore it after a callback ended its lease.
        let nextPhysicalProtected = nextProtected
        if let logicalRealization, logicalRealization.isActive {
            if positions[logicalRealization.token] == nil {
                logicalRealization.revoke()
                self.logicalRealization = nil
            }
        }
        if let token = logicalRealizationTokenForSelection { nextProtected.insert(token) }
        guard nextProtected.count <= maximumProtectedRecords else { return .workRemaining }
        guard nextProtected.count <= maximumMountedRecords else { return .workRemaining }
        guard let selection = windowSelection(selectionViewport, protecting: nextProtected) else {
            return transitionRequiredTokens.isEmpty ? .unsupported : .workRemaining
        }
        let boundaryProbe = nextGapBoundaryProbe(required: selection.requiredTokens)
        var selectedTokens = nextProtected
        var orderedTokens = nextProtected.sorted {
            positions[$0, default: Int.max] < positions[$1, default: Int.max]
        }
        for token in selection.tokens where selection.requiredTokens.contains(token) {
            if selectedTokens.insert(token).inserted { orderedTokens.append(token) }
        }
        // Boundary discovery uses only spare capacity after every protected
        // and visible row. It can displace prefetch, never a required lease or
        // the current viewport's retained state. An exhausted cap stays dirty.
        if let boundaryProbe, !selectedTokens.contains(boundaryProbe),
            orderedTokens.count < maximumMountedRecords
        {
            selectedTokens.insert(boundaryProbe)
            orderedTokens.append(boundaryProbe)
        }
        for token in selection.tokens where !selectedTokens.contains(token) {
            guard orderedTokens.count < maximumMountedRecords else { break }
            selectedTokens.insert(token)
            orderedTokens.append(token)
        }
        // A capped estimated window must still get a chance to measure its
        // prefix. Large actual rows can make that bounded prefix sufficient.
        // Protected cohorts build first for lease safety, then visible rows,
        // then nearest prefetch. A large prefetch must never consume the cap
        // or a small shared element budget before required visible rows.
        var originalProofs: [RetainedLazyListRowToken: CarriedRecordProof] = [:]
        var remainingReservedLeaves = 0
        if managed != nil, !transitionRequiredTokens.isEmpty {
            for token in selection.requiredTokens {
                guard let original = mounted[token] else { continue }
                guard let proof = carriedRecordProof(for: original),
                    original.nodes.count <= maximumMountedLeaves - remainingReservedLeaves
                else { return .obsolete }
                originalProofs[token] = proof
                remainingReservedLeaves += original.nodes.count
            }
        }
        let originalActualProofs = Array(originalProofs.values)
        var carriedRecordProofs: [RetainedLazyListRowToken: CarriedRecordProof] = [:]
        var records: [Record] = []
        var preparedRecordIndices: [Int: Int] = [:]
        var acceptedIdentityProofs: [RetainedLazyListViewIdentityProof] = []
        var acceptedRoots: [ViewNode] = []
        var leafCount = 0
        var leafIdentities: Set<ObjectIdentifier> = []
        var stoppedForBudget = false
        for token in orderedTokens {
            guard
                operationIsCurrent(
                    expectedAttempt, configuration: expectedConfiguration, admission: checkedAdmission,
                    identityProofs: acceptedIdentityProofs),
                generation.isCurrent, originalActualProofs.allSatisfy(\.isCurrent)
            else { return .obsolete }
            let isRequired = selection.requiredTokens.contains(token)
            if originalProofs[token] != nil, let original = mounted[token] {
                remainingReservedLeaves -= original.nodes.count
            }
            let remainingLeaves = maximumMountedLeaves - leafCount - remainingReservedLeaves
            guard remainingLeaves >= 0 else { return .workRemaining }
            if !isRequired, leafCount == maximumMountedLeaves { continue }
            let record: Record
            var carriesOriginal = false
            let existing = mounted[token].flatMap { recordIsCurrent($0) ? $0 : nil }
            if let existing, checkedAdmission == nil {
                record = existing
            } else if existing == nil,
                transitionCapacityDeferred.contains(token) || stoppedForBudget || budget.remainingElements == 0
            {
                if !transitionCapacityDeferred.contains(token) { stoppedForBudget = true }
                guard originalProofs[token] != nil, let original = mounted[token] else { continue }
                record = original
                carriesOriginal = true
            } else {
                // Keep a bounded completed prefix instead of discarding every
                // successful factory when the shared budget runs out. Actual
                // transition rows not refreshed in this slice remain attached
                // under their original proof, with no fresh row declaration.
                let result = materializeRecord(
                    for: token, reusing: existing, generation: generation,
                    expectedAttempt: expectedAttempt, expectedConfiguration: expectedConfiguration,
                    remainingLeaves: remainingLeaves, isRequired: isRequired,
                    previousRoots: acceptedRoots, previousProofs: acceptedIdentityProofs,
                    budget: budget, admission: checkedAdmission, managed: managed,
                    carriedRecordProofs: originalActualProofs,
                    mayDeferForCapacity: originalProofs[token] != nil && !transitionRequiredTokens.isEmpty)
                // In particular, optional oversized outputs and typed identity
                // temporaries have been destroyed before another provider call.
                guard
                    operationIsCurrent(
                        expectedAttempt, configuration: expectedConfiguration, admission: checkedAdmission,
                        identityProofs: acceptedIdentityProofs),
                    generation.isCurrent, originalActualProofs.allSatisfy(\.isCurrent)
                else { return .obsolete }
                switch result {
                case .record(let prepared):
                    record = prepared
                case .skippedOptional:
                    continue
                case .deferredForCapacity:
                    transitionCapacityDeferred.insert(token)
                    guard originalProofs[token] != nil, let original = mounted[token] else { return .unsupported }
                    record = original
                    carriesOriginal = true
                case .workRemaining:
                    stoppedForBudget = true
                    guard originalProofs[token] != nil, let original = mounted[token] else { continue }
                    record = original
                    carriesOriginal = true
                case .obsolete:
                    return .obsolete
                case .unsupported:
                    return .unsupported
                }
            }
            if carriesOriginal {
                guard let proof = originalProofs[token], proof.isCurrent else { return .obsolete }
                var authority = PreparationAuthority(
                    attempt: expectedAttempt, configuration: expectedConfiguration, generation: generation,
                    admission: checkedAdmission, previousIdentityProofs: acceptedIdentityProofs,
                    managed: managed)
                authority.carriedRecordProofs = originalActualProofs
                guard carriedIdentitiesAreDistinct(record, from: acceptedRoots, authority: authority) else {
                    return authorityIsCurrent(authority) ? .unsupported : .obsolete
                }
                carriedRecordProofs[token] = proof
            } else {
                guard recordIsCurrent(record) else { return .obsolete }
            }
            if !isRequired, token != boundaryProbe, hasUnresolvedLeadingGap(record),
                !hasPreparedGapPredecessor(for: record, records: records, indices: preparedRecordIndices)
            {
                continue
            }
            if record.nodes.count > remainingLeaves {
                if isRequired { return .unsupported }
                continue
            }
            leafCount += record.nodes.count
            for node in record.nodes {
                guard leafIdentities.insert(ObjectIdentifier(node)).inserted else { return .unsupported }
            }
            records.append(record)
            if !carriesOriginal, let position = positions[token] {
                preparedRecordIndices[position] = records.count - 1
            }
            acceptedRoots.append(contentsOf: record.nodes)
            acceptedIdentityProofs.append(contentsOf: record.identityProofs)
        }
        guard
            operationIsCurrent(
                expectedAttempt, configuration: expectedConfiguration, admission: checkedAdmission,
                identityProofs: acceptedIdentityProofs),
            generation.isCurrent, originalActualProofs.allSatisfy(\.isCurrent),
            records.allSatisfy({ carriedRecordProofs[$0.request.token] != nil || $0.request.isGenerationCurrent })
        else { return .obsolete }
        let preparedTokens = Set(records.map { $0.request.token })
        guard nextProtected.isSubset(of: preparedTokens),
            Set(originalProofs.keys).isSubset(of: preparedTokens)
        else { return .workRemaining }
        if !carriedRecordProofs.isEmpty, recordsMatchMounted(records) {
            // No new table was proposed. Keep measurement available to the
            // previously accepted current subset; the stale cohort itself
            // continues to make settlement impossible until it is refreshed.
            if acceptedSnapshot { preparationIncomplete = false }
            // Previously blocked expansions are skipped without another
            // factory debit, so later shrinking rows can free capacity first.
            // If every outstanding row is blocked, this cohort cannot advance
            // within the configured cap while retaining its actual roots.
            return !transitionAwaitingMeasurements.isEmpty
                && transitionAwaitingMeasurements.isSubset(of: transitionCapacityDeferred)
                ? .unsupported : .workRemaining
        }
        if stoppedForBudget, !selection.requiredTokens.isSubset(of: preparedTokens),
            records.isEmpty || recordsMatchMounted(records)
        {
            return .workRemaining
        }
        records.sort { positions[$0.request.token, default: Int.max] < positions[$1.request.token, default: Int.max] }
        if acceptedSnapshot, !wasIncomplete, recordsMatchMounted(records) {
            protectedTokens = nextPhysicalProtected
            preparationIncomplete = false
            unresolvedWork = needsResolution(selection: selection)
            return .unchanged
        }
        var departingEmptyRows: [(RetainedLazyListMaterializedRowActivity, RetainedLazyListDepartureCause)] = []
        var emptyRowContinuations: [ObjectIdentifier: RetainedLazyListEmptyRowContinuation] = [:]
        for (token, record) in mounted where !record.nodes.isEmpty {
            guard let previousActivity = record.activity,
                let successor = records.first(where: { $0.request.token == token }),
                let successorActivity = successor.activity, successorActivity !== previousActivity,
                successorActivity.physical === previousActivity.physical,
                successorActivity.logicalMembership === previousActivity.logicalMembership
            else { continue }
            // The journal reserves only native provenance here. It activates
            // the finite handoff at accepted mutation, before the last actual
            // old leaf detaches, then ends at the successor's accepted row table.
            guard let managed,
                managed.journal.prepareRowReplacementHandoff(from: previousActivity, to: successorActivity),
                operationIsCurrent(
                    expectedAttempt, configuration: expectedConfiguration, admission: checkedAdmission,
                    identityProofs: acceptedIdentityProofs), generation.isCurrent
            else { return .obsolete }
        }
        for (token, record) in mounted where record.nodes.isEmpty {
            guard let previousActivity = record.activity else { continue }
            let successor = records.first { $0.request.token == token }
            if successor?.activity === previousActivity { continue }
            if let successorActivity = successor?.activity,
                successorActivity.physical === previousActivity.physical,
                successorActivity.logicalMembership === previousActivity.logicalMembership
            {
                guard let managed,
                    let continuation = managed.journal.prepareEmptyRowContinuation(
                        from: previousActivity, to: successorActivity),
                    operationIsCurrent(
                        expectedAttempt, configuration: expectedConfiguration, admission: checkedAdmission,
                        identityProofs: acceptedIdentityProofs), generation.isCurrent
                else { return .obsolete }
                emptyRowContinuations[ObjectIdentifier(successorActivity)] = continuation
            } else {
                let cause: RetainedLazyListDepartureCause =
                    positions[token] == nil
                    ? .logicalDeletion
                    : successor == nil ? .viewportEviction : .acceptedReplacement
                departingEmptyRows.append((previousActivity, cause))
            }
        }
        let candidate = Candidate(
            adapter: self, viewport: viewport, records: records, generation: generation,
            configuration: expectedConfiguration, attempt: expectedAttempt,
            protectedTokens: nextPhysicalProtected,
            virtualizedDepartureRoots: Set(
                mounted.flatMap { token, record -> [ObjectIdentifier] in
                    guard positions[token] != nil, !preparedTokens.contains(token) else { return [] }
                    return record.nodes.map(ObjectIdentifier.init)
                }),
            departingEmptyRows: departingEmptyRows, emptyRowContinuations: emptyRowContinuations,
            carriedRecordProofs: carriedRecordProofs)
        pendingCandidate = true
        return .ready(candidate)
    }

    /// Runtime calls this only for a fully completed, still-authorized checked
    /// reconciliation. Its actual retained child order can differ in identity
    /// from the throwaway factory nodes. Partial adoption must not call complete.
    @discardableResult
    package func complete(candidate: Candidate, adoptedChildren: [ViewNode]) -> Bool {
        complete(candidate: candidate, adoptedChildren: adoptedChildren, journal: nil, structuralAnchor: nil)
    }

    /// The managed route records its actual bounded row-table publication
    /// before selective commit and before old mounted captures are released.
    @discardableResult
    func complete(
        candidate: Candidate, adoptedChildren: [ViewNode], journal: RetainedLazyListAdoptionJournal?,
        structuralAnchor: RetainedLazyListActualAttachment?
    ) -> Bool {
        guard !isPreparing, !isReleasing, isCurrent(candidate), !candidate.wasCompleted,
            adoptedChildren.count == candidate.children.count,
            Set(adoptedChildren.map(ObjectIdentifier.init)).count == adoptedChildren.count
        else { return false }
        if managedLogicalDescriptor != nil {
            guard let journal, journal.canContinueAdoption, let structuralAnchor, structuralAnchor.isAttached,
                candidate.didClaimEmptyDepartures, candidate.completedNonemptyRows(in: journal)
            else { return false }
        }
        var nextMounted: [RetainedLazyListRowToken: Record] = [:]
        var emptyUpdates: [ExtentUpdate] = []
        var completedEmptyPositions: [Int] = []
        var freedTransitionCapacity = false
        var cursor = 0
        for record in candidate.records {
            let token = record.request.token
            let end = cursor + record.nodes.count
            let retained = Array(adoptedChildren[cursor..<end])
            cursor = end
            if let proof = candidate.carriedRecordProofs[token] {
                guard proof.isCurrent, zip(record.nodes, retained).allSatisfy({ $0 === $1 }) else { return false }
                // This is an unchanged actual child table entry, not acceptance
                // of the successor descriptor's row output. Keep its original
                // request/configuration and withhold all new measurements.
                nextMounted[token] = record
                continue
            }
            if let previous = mounted[token], retained.count < previous.nodes.count {
                freedTransitionCapacity = true
            }
            if retained.isEmpty {
                completedEmptyPositions.append(record.request.sourceIndex)
                guard let previous = extentIndex?.extent(for: token),
                    let empty = RetainedLazyListExtent.measured([])
                else { return false }
                emptyUpdates.append(ExtentUpdate(token: token, previous: previous, next: empty))
                // Raw Stage 2 keeps its original zero-node cache behavior.
                if record.activity == nil { continue }
            }
            let sameLeaves = zip(record.nodes, retained).allSatisfy { $0 === $1 }
            nextMounted[token] = Record(
                request: record.request, nodes: retained,
                extents: retained.isEmpty ? [] : (sameLeaves ? record.extents : nil),
                configuration: candidate.configuration,
                identityProofs: record.identityProofs.isEmpty ? [] : retained.map { $0.captureLazyListIdentityProof() },
                activity: record.activity)
        }
        guard journal?.markMutationStarted() != false else { return false }
        guard applyExtentUpdates(emptyUpdates, context: candidate.viewport.context) else { return false }
        var previous = mounted
        mounted = nextMounted
        protectedTokens = candidate.protectedTokens
        acceptedSnapshot = true
        preparationIncomplete = false
        pendingCandidate = false
        candidate.wasCompleted = true
        var completedEmptyRows = true
        if let journal, let structuralAnchor {
            // This is an accepted structural table write, not a zero-length
            // factory observation or a fabricated child attachment.
            for record in candidate.records
            where record.nodes.isEmpty && candidate.carriedRecordProofs[record.request.token] == nil {
                if !candidate.recordAcceptedEmptyRow(record, anchor: structuralAnchor, journal: journal) {
                    completedEmptyRows = false
                }
            }
        }
        // Departing nodes can own authored cleanup. Do not release those
        // payloads inside the dictionary's stored-property write access.
        withExtendedLifetime(previous) {}
        previous = [:]
        guard isCurrent(candidate), completedEmptyRows else {
            preparationIncomplete = true
            unresolvedWork = true
            return false
        }
        // Accepted child counts already prove that a shrinking row freed
        // capacity. Its gap may still await another carried row's boundary, so
        // waiting for measurement here could prevent that row's retry forever.
        if freedTransitionCapacity { transitionCapacityDeferred = [] }
        guard refreshAcceptedGapBoundarySummaries() else {
            preparationIncomplete = true
            unresolvedWork = true
            return false
        }
        // Raw empty records do not remain mounted, but their accepted native
        // table still proves that ordinal position has no preceding row root.
        for position in completedEmptyPositions {
            gapBoundaryIndex?.update(at: position, to: .empty)
        }
        finishTransitionMeasurements(for: Set(completedEmptyPositions.map { tokens[$0] }))
        if let selection = windowSelection(candidate.viewport, protecting: protectedTokens) {
            unresolvedWork = needsResolution(selection: selection)
            rememberRequiredActualRows(selection)
        } else {
            unresolvedWork = true
        }
        return true
    }

    /// Called once after the complete native child plan passes preflight.
    /// Removing an exact old zero-node entry is itself an accepted mutation;
    /// later failure of another row cannot restore its physical lifetime.
    func claimDepartingEmptyRows(
        in candidate: Candidate, journal: RetainedLazyListAdoptionJournal
    ) -> Bool {
        guard managedLogicalDescriptor != nil, isCurrent(candidate), journal.canContinueAdoption else { return false }
        if candidate.didClaimEmptyDepartures { return true }
        for (activity, _) in candidate.departingEmptyRows {
            guard let original = mounted[activity.request.token], original.nodes.isEmpty,
                original.activity === activity
            else { return false }
        }
        if !candidate.departingEmptyRows.isEmpty {
            guard journal.markMutationStarted() else { return false }
        }
        candidate.didClaimEmptyDepartures = true
        for (activity, cause) in candidate.departingEmptyRows {
            let original = mounted.removeValue(forKey: activity.request.token)
            _ = journal.recordAcceptedEmptyRowDeparture(activity, cause: cause)
            withExtendedLifetime(original) {}
        }
        return isCurrent(candidate) && journal.canContinueAdoption
    }

    /// Measurements must come from actual adopted leaves after their layout,
    /// with Runtime's attachment/context/pass checks still valid. A context is
    /// a cache tag, not proof of current layout or permission to accept input.
    /// Each touched record must provide every leaf exactly once.
    package func recordMeasurements(
        _ measurements: [Measurement], viewport: Viewport
    ) -> MeasurementUpdate? {
        guard !isPreparing, !isReleasing, !pendingCandidate, !preparationIncomplete,
            snapshotIsCurrent(for: viewport), refreshAcceptedGapBoundarySummaries(),
            measurements.count <= maximumMountedLeaves
        else { return nil }
        var measured: [RetainedLazyListRowToken: [Double?]] = [:]
        for measurement in measurements {
            guard measurement.extent.isFinite, measurement.extent >= 0,
                let record = mounted[measurement.token], recordIsCurrent(record),
                record.nodes.indices.contains(measurement.leafIndex),
                record.nodes[measurement.leafIndex] === measurement.node
            else { return nil }
            if measured[measurement.token] == nil {
                measured[measurement.token] = Array(repeating: nil, count: record.nodes.count)
            }
            guard measured[measurement.token]?[measurement.leafIndex] == nil else { return nil }
            measured[measurement.token]?[measurement.leafIndex] = measurement.extent
        }
        var updates: [ExtentUpdate] = []
        var heights: [RetainedLazyListRowToken: [Double]] = [:]
        var changed = false
        var requiresLayout = false
        for (token, values) in measured {
            guard values.allSatisfy({ $0 != nil }) else { return nil }
            guard let record = mounted[token], recordIsCurrent(record) else { return nil }
            if hasUnresolvedLeadingGap(record) { continue }
            let complete = values.compactMap { $0 }
            guard let next = RetainedLazyListExtent.measured(complete.map { $0 + interLeafSpacing }),
                let previous = extentIndex?.extent(for: token)
            else { return nil }
            heights[token] = complete
            updates.append(ExtentUpdate(token: token, previous: previous, next: next))
            let recordChanged = previous != next || record.extents != complete
            changed = changed || recordChanged
            // Runtime already placed this first actual leaf batch using its
            // measured local heights. Publishing confidence alone does not
            // move a record boundary. Compare each record exactly: opposing
            // changes to two records still move their intervening boundary.
            let firstMeasurementPreservesGeometry =
                previous.measuredLeafCount == nil && record.extents == nil
                && previous.totalExtent == next.totalExtent
            requiresLayout = requiresLayout || (recordChanged && !firstMeasurementPreservesGeometry)
        }
        let anchor = extentIndex?.captureAnchor(at: viewport.offset)
        guard applyExtentUpdates(updates, context: viewport.context) else { return nil }
        for (token, values) in heights { mounted[token]?.extents = values }
        finishTransitionMeasurements(for: Set(heights.keys))
        let adjustedOffset = anchor.flatMap {
            resolveAnchor($0, viewportExtent: viewport.extent)
        }
        if let selection = windowSelection(viewport, protecting: protectedTokens) {
            unresolvedWork = needsResolution(selection: selection)
            rememberRequiredActualRows(selection)
        } else {
            unresolvedWork = true
        }
        return MeasurementUpdate(
            extentChanged: changed, requiresLayout: requiresLayout, anchorAdjustedOffset: adjustedOffset)
    }

    /// A pure terminal comparison for Runtime's already completed layout pass.
    /// It cannot accept first measurements, update selection/gap/chrome caches,
    /// or call a provider. Runtime separately proves every physical attachment,
    /// the exact pass and viewport, and the absence of pending callback work.
    func matchesAcceptedMeasurements(_ measurements: [Measurement], viewport: Viewport) -> Bool {
        guard hasCurrentLogicalSnapshot, snapshotIsCurrent(for: viewport), !unresolvedWork,
            !pendingCandidate, !preparationIncomplete, stagedPredecessor == nil, inheritedExtentSpacing == nil,
            transitionRequiredTokens.isEmpty, transitionAwaitingMeasurements.isEmpty,
            transitionCapacityDeferred.isEmpty,
            managedLogicalDescriptor.map({ generation == $0.sourceGeneration }) != false,
            measurements.count <= maximumMountedLeaves, measurements.count == mountedLeafCount,
            mounted.count <= maximumMountedRecords, gapBoundaryIndex != nil
        else { return false }
        if let logicalRealization {
            guard logicalRealization.isActive, positions[logicalRealization.token] != nil else { return false }
        }

        var measured: [RetainedLazyListRowToken: [Double?]] = [:]
        for measurement in measurements {
            guard measurement.extent.isFinite, measurement.extent >= 0,
                let record = mounted[measurement.token], recordIsCurrent(record),
                record.nodes.indices.contains(measurement.leafIndex),
                record.nodes[measurement.leafIndex] === measurement.node
            else { return false }
            if measured[measurement.token] == nil {
                measured[measurement.token] = Array(repeating: nil, count: record.nodes.count)
            }
            guard measured[measurement.token]?[measurement.leafIndex] == nil else { return false }
            measured[measurement.token]?[measurement.leafIndex] = measurement.extent
        }

        // Verify the entire bounded mounted cache before consulting a prefix.
        // A changed accepted neighbor must not leave an old boundary summary
        // available to another row merely because its pixel height is equal.
        for (token, record) in mounted {
            guard recordIsCurrent(record), let position = positions[token], let extents = record.extents,
                extents.count == record.nodes.count,
                let summary = gapSummary(of: record.nodes), gapBoundaryIndex?.matches(summary, at: position) == true,
                let extent = RetainedLazyListExtent.measured(extents.map { $0 + interLeafSpacing }),
                extentIndex?.extent(for: token) == extent
            else { return false }
            if record.nodes.isEmpty {
                guard measured[token] == nil else { return false }
            } else {
                guard let actual = measured[token], actual.count == extents.count,
                    zip(actual, extents).allSatisfy({ $0.0 == $0.1 })
                else { return false }
            }
        }

        for (token, record) in mounted {
            guard let position = positions[token], let extents = record.extents,
                let ordinal = gapBoundaryIndex?.ordinalBefore(position)
            else { return false }
            var predecessor = gapPredecessor(before: position)
            var declaredNext: GapRowBoundary?
            var isOdd = ordinal.parity
            for (index, node) in record.nodes.enumerated() {
                if let gap = node.retainedLazyListGap {
                    guard let height = gapExtent(gap, after: predecessor),
                        extents[index] == (node.isHidden ? 0 : height)
                    else { return false }
                    declaredNext = GapRowBoundary(gap)
                } else {
                    guard
                        node.hasCurrentRetainedLazyListRowChrome(
                            isOdd: isOdd, hasUnknownPrefix: ordinal.hasUnknownPrefix)
                    else { return false }
                    isOdd.toggle()
                    predecessor = .row(declaredNext ?? .ordinary)
                    declaredNext = nil
                }
            }
        }

        guard let selection = windowSelection(viewport, protecting: protectedTokens),
            !needsResolution(selection: selection), lastRequiredTokens == selection.requiredTokens
        else { return false }
        return true
    }

    /// Revoke before an external structural mutation or attachment change.
    /// This operation drops no authored payload and invokes no application code.
    package func revokePendingCandidate() {
        configuration = RetainedLazyListAdapterIdentity()
        attempt = RetainedLazyListAdapterIdentity()
        // Preserve old scalar coordinates for Runtime's next anchor capture,
        // but rebuild estimates before selecting from a changed configuration.
        // Retaining measured zero extents could hide newly nonempty records.
        generation = nil
        gapBoundaryIndex = nil
        transitionCapacityDeferred = []
        pendingCandidate = false
        preparationIncomplete = true
        acceptedSnapshot = false
        unresolvedWork = true
    }

    /// Runtime first owns physical teardown. An externally retained adapter
    /// must not keep evicted/closed-runtime nodes alive through its cache.
    package func releaseMountedRecords() {
        releaseMountedRecords(journal: nil)
    }

    func releaseMountedRecords(journal: RetainedLazyListAdoptionJournal?) {
        revokePendingCandidate()
        guard !isReleasing else { return }
        isReleasing = true
        logicalRealization?.revoke()
        logicalRealization = nil
        stagedPredecessor = nil
        var previous = mounted
        mounted = [:]
        protectedTokens = []
        lastRequiredTokens = []
        transitionRequiredTokens = []
        transitionAwaitingMeasurements = []
        transitionCapacityDeferred = []
        // Empty rows have no departing ViewNode to revoke their physical
        // receipt. Deny them before any old mounted capture can be released.
        for record in previous.values where record.nodes.isEmpty {
            guard let activity = record.activity else { continue }
            if let journal {
                _ = journal.recordAcceptedEmptyRowDeparture(activity, cause: .acceptedReplacement)
            } else {
                activity.physical.revoke()
            }
        }
        withExtendedLifetime(previous) {}
        previous = [:]
        isReleasing = false
    }

    package func invalidate() { releaseMountedRecords() }

    private func readSnapshot(
        expectedAttempt: RetainedLazyListAdapterIdentity,
        expectedConfiguration: RetainedLazyListAdapterIdentity,
        admission: RetainedLazyListAdoptionAdmission?
    ) -> Snapshot? {
        guard operationIsCurrent(expectedAttempt, configuration: expectedConfiguration, admission: admission) else {
            return nil
        }
        let reply = provider.metadata
        guard operationIsCurrent(expectedAttempt, configuration: expectedConfiguration, admission: admission),
            let metadata = reply, metadata.generation.isCurrent
        else { return nil }
        var nextTokens: [RetainedLazyListRowToken] = []
        var nextPositions: [RetainedLazyListRowToken: Int] = [:]
        for (position, row) in metadata.rows.enumerated() {
            guard row.sourceIndex == position, nextPositions[row.token] == nil else { return nil }
            nextTokens.append(row.token)
            nextPositions[row.token] = position
        }
        // Typed keys in metadata die in this helper, before the caller's final
        // primitive attempt/generation check. Plans retain only native tokens.
        return Snapshot(
            generation: metadata.generation, tokens: nextTokens, positions: nextPositions)
    }

    /// One scoped provider operation. All typed prefixes and temporary output
    /// payloads end here; the caller then checks native admission again before
    /// retaining a record or invoking another row's provider operation.
    private func materializeRecord(
        for token: RetainedLazyListRowToken, reusing existing: Record?,
        generation: RetainedLazyListGeneration,
        expectedAttempt: RetainedLazyListAdapterIdentity,
        expectedConfiguration: RetainedLazyListAdapterIdentity,
        remainingLeaves: Int, isRequired: Bool,
        previousRoots: [ViewNode], previousProofs: [RetainedLazyListViewIdentityProof],
        budget: RetainedLazyListWorkBudget, admission: RetainedLazyListAdoptionAdmission?,
        managed: ManagedPreparation?,
        carriedRecordProofs: [CarriedRecordProof] = [],
        mayDeferForCapacity: Bool = false,
        probeRequestIsCurrent: (@MainActor () -> Bool)? = nil
    ) -> RecordPreparation {
        var existingProofs = previousProofs
        if admission != nil, let existing {
            // Preserve the reused cohort's original identity witnesses across
            // provider calls. Recapturing only after a getter could accept an
            // equal-value identity reassignment and keep obsolete measurements.
            // A raw planning record has no witnesses yet; capture them before
            // its first checked getter, not after identity validation.
            existingProofs.append(
                contentsOf: existing.identityProofs.isEmpty
                    ? existing.nodes.map { $0.captureLazyListIdentityProof() }
                    : existing.identityProofs)
        }
        var authority = PreparationAuthority(
            attempt: expectedAttempt, configuration: expectedConfiguration, generation: generation,
            admission: admission, previousIdentityProofs: existingProofs, managed: managed)
        authority.probeRequestIsCurrent = probeRequestIsCurrent
        authority.carriedRecordProofs = carriedRecordProofs
        guard authorityIsCurrent(authority) else { return .obsolete }
        let request: RetainedLazyListRowRequest
        if let existing {
            request = existing.request
        } else {
            // A protocol getter is an opaque authored callout even when the
            // concrete data source currently implements it with native lookup.
            guard authorityIsCurrent(authority) else { return .obsolete }
            let reply = provider.request(for: token)
            guard authorityIsCurrent(authority), let reply else { return .obsolete }
            request = reply
        }
        guard request.isGenerationCurrent, request.token == token,
            request.sourceIndex == positions[token], authorityIsCurrent(authority)
        else { return .obsolete }
        let initiallyCurrent = provider.isCurrent(request)
        guard authorityIsCurrent(authority), request.isGenerationCurrent, initiallyCurrent else { return .obsolete }

        let expectedPrefix: RetainedViewIdentity?
        if admission != nil {
            guard authorityIsCurrent(authority), request.isGenerationCurrent else { return .obsolete }
            let reply = provider.identityPrefix(for: request)
            guard authorityIsCurrent(authority), request.isGenerationCurrent else { return .obsolete }
            guard let reply else { return .unsupported }
            expectedPrefix = reply
        } else {
            expectedPrefix = nil
        }

        let nodes: [ViewNode]
        let previousExtents: [Double]?
        var rowActivity: RetainedLazyListMaterializedRowActivity?
        if let existing {
            nodes = existing.nodes
            previousExtents = existing.extents
            rowActivity = existing.activity
        } else {
            guard authorityIsCurrent(authority), request.isGenerationCurrent else { return .obsolete }
            let result = materializeSelectedRecord(
                request, budget: budget, authority: authority, rowActivity: &rowActivity)
            guard authorityIsCurrent(authority), request.isGenerationCurrent else { return .obsolete }
            switch result {
            case .built(let built):
                guard built.request == request else { return .obsolete }
                nodes = built.content
                previousExtents = nil
                guard managed == nil || !ViewNode.containsRejectedRetainedSource(in: nodes) else { return .obsolete }
            case .obsolete:
                return .obsolete
            case .budgetExhausted, .reentrant:
                return .workRemaining
            }
            guard authorityIsCurrent(authority), request.isGenerationCurrent else { return .obsolete }
            let finallyCurrent = provider.isCurrent(request)
            guard authorityIsCurrent(authority), request.isGenerationCurrent, finallyCurrent else { return .obsolete }
        }
        guard nodes.count <= remainingLeaves else {
            // Optional content is not truncated and does not poison a valid
            // visible cohort. Its payload dies before the caller's next guard.
            if isRequired, mayDeferForCapacity, nodes.count <= maximumMountedLeaves { return .deferredForCapacity }
            return isRequired ? .unsupported : .skippedOptional
        }

        let proofs: [RetainedLazyListViewIdentityProof]
        if let expectedPrefix {
            guard authorityIsCurrent(authority) else { return .obsolete }
            let reply = validatedIdentityProofs(
                for: nodes, prefix: expectedPrefix, previousRoots: previousRoots, authority: authority)
            guard authorityIsCurrent(authority) else { return .obsolete }
            guard let reply else { return .unsupported }
            guard authorityIsCurrent(authority, additionalProofs: reply) else { return .obsolete }
            proofs = reply
        } else {
            proofs = []
        }
        guard gapSummary(of: nodes) != nil else { return .unsupported }
        return .record(
            Record(
                request: request, nodes: nodes, extents: previousExtents,
                configuration: expectedConfiguration, identityProofs: proofs, activity: rowActivity))
    }

    private func authorityIsCurrent(
        _ authority: PreparationAuthority, additionalProofs: [RetainedLazyListViewIdentityProof] = []
    ) -> Bool {
        guard
            operationIsCurrent(
                authority.attempt, configuration: authority.configuration, admission: authority.admission,
                identityProofs: authority.previousIdentityProofs)
                && authority.generation.isCurrent && additionalProofs.allSatisfy(\.isCurrent)
                && authority.carriedRecordProofs.allSatisfy(\.isCurrent)
                && managedPreparationIsCurrent(authority.managed)
        else { return false }
        guard let probeRequestIsCurrent = authority.probeRequestIsCurrent else { return true }
        let current = probeRequestIsCurrent()
        return current
            && operationIsCurrent(
                authority.attempt, configuration: authority.configuration, admission: authority.admission,
                identityProofs: authority.previousIdentityProofs)
            && authority.generation.isCurrent && additionalProofs.allSatisfy(\.isCurrent)
            && authority.carriedRecordProofs.allSatisfy(\.isCurrent)
            && managedPreparationIsCurrent(authority.managed)
    }

    private func managedPreparationIsCurrent(_ managed: ManagedPreparation?) -> Bool {
        guard let descriptor = managedLogicalDescriptor else { return managed == nil }
        guard let managed, managed.descriptor === descriptor else { return false }
        return descriptor.isCurrent && managed.journal.canContinueConstruction
    }

    /// A probe never publishes a Candidate, changes the viewport, records a
    /// measurement, or keeps detached output. Runtime owns its doomed epoch.
    enum ScrollProbeResult {
        case found(RetainedLazyListRowToken)
        case more(RetainedLazyListRowToken?)
        case notFound
        case obsolete
    }

    private enum ScrollProbeRecordResult {
        case found
        case notFound
        case workRemaining
        case obsolete
    }

    func probeScrollTarget(
        after previous: RetainedLazyListRowToken?,
        budget: RetainedLazyListWorkBudget, admission: RetainedLazyListAdoptionAdmission,
        activity: (any RetainedLazyListBuildActivity)?,
        journal: RetainedLazyListAdoptionJournal?,
        requestIsCurrent: @escaping @MainActor () -> Bool,
        matches: @MainActor ([ViewNode]) -> Bool
    ) -> ScrollProbeResult {
        guard admission.isBuildCurrent(for: self), !isPreparing, !isReleasing,
            !pendingCandidate, acceptedSnapshot, let generation, generation.isCurrent
        else { return .obsolete }
        let managed: ManagedPreparation?
        if let descriptor = managedLogicalDescriptor {
            guard descriptor.isCurrent, let activity, let journal, journal.canContinueConstruction else {
                return .obsolete
            }
            managed = ManagedPreparation(descriptor: descriptor, activity: activity, journal: journal)
        } else {
            managed = nil
        }
        isPreparing = true
        defer { isPreparing = false }
        var authority = PreparationAuthority(
            attempt: attempt, configuration: configuration, generation: generation,
            admission: admission, previousIdentityProofs: [], managed: managed)
        authority.probeRequestIsCurrent = requestIsCurrent
        guard authorityIsCurrent(authority) else { return .obsolete }
        var index: Int
        if let previous {
            guard let preceding = positions[previous] else { return .obsolete }
            index = preceding + 1
        } else {
            index = 0
        }
        var lastExamined = previous
        while index < tokens.count {
            guard authorityIsCurrent(authority) else { return .obsolete }
            guard budget.remainingElements > 0 else { return .more(lastExamined) }
            let token = tokens[index]
            let result = probeScrollRecord(
                token, budget: budget, authority: authority, matches: matches)
            // In particular, rejected/oversized nodes and temporary keys have
            // died in the noninlined helper before we advance to another row.
            guard authorityIsCurrent(authority) else { return .obsolete }
            switch result {
            case .found:
                return .found(token)
            case .notFound:
                lastExamined = token
                index += 1
            case .workRemaining:
                return .more(lastExamined)
            case .obsolete:
                return .obsolete
            }
        }
        return authorityIsCurrent(authority) ? .notFound : .obsolete
    }

    @inline(never)
    private func probeScrollRecord(
        _ token: RetainedLazyListRowToken,
        budget: RetainedLazyListWorkBudget, authority: PreparationAuthority,
        matches: @MainActor ([ViewNode]) -> Bool
    ) -> ScrollProbeRecordResult {
        guard authorityIsCurrent(authority) else { return .obsolete }
        if let existing = mounted[token], recordIsCurrent(existing) {
            // The facade searched the attached reader tree before entering its
            // opaque fallback. Do not hand its live roots to this matcher.
            // Even this cached skip consumes one element, bounding metadata
            // enumeration when all selected outputs are empty or mounted.
            return budget.consumeElement() ? .notFound : .workRemaining
        }
        let materialized = materializeRecord(
            for: token, reusing: nil, generation: authority.generation,
            expectedAttempt: authority.attempt, expectedConfiguration: authority.configuration,
            remainingLeaves: maximumMountedLeaves, isRequired: true,
            previousRoots: [], previousProofs: [], budget: budget,
            admission: authority.admission, managed: authority.managed,
            probeRequestIsCurrent: authority.probeRequestIsCurrent)
        guard authorityIsCurrent(authority) else { return .obsolete }
        switch materialized {
        case .record(let record):
            guard record.request.token == token, recordIsCurrent(record),
                record.nodes.allSatisfy({ $0.parent == nil && $0.retainedLazyListRuntime == nil }),
                authorityIsCurrent(authority, additionalProofs: record.identityProofs)
            else { return .obsolete }
            // Empty output has already consumed its prepaid element. It is not
            // an adopted empty row and receives no lifetime or callback receipt.
            guard !record.nodes.isEmpty else { return .notFound }
            let found = matches(record.nodes)
            guard authorityIsCurrent(authority, additionalProofs: record.identityProofs),
                recordIsCurrent(record),
                record.nodes.allSatisfy({ $0.parent == nil && $0.retainedLazyListRuntime == nil })
            else { return .obsolete }
            return found ? .found : .notFound
        case .workRemaining:
            return .workRemaining
        case .skippedOptional, .deferredForCapacity, .unsupported, .obsolete:
            // A rejected factory remains charged, but it cannot prove absence
            // of an explicit ID or permit an implicit fallback to win.
            return .obsolete
        }
    }

    /// Resolve the selected typed row before entering its existing factory.
    /// Reused records never enter this path or invent a new row contribution.
    private func materializeSelectedRecord(
        _ request: RetainedLazyListRowRequest, budget: RetainedLazyListWorkBudget,
        authority: PreparationAuthority, rowActivity: inout RetainedLazyListMaterializedRowActivity?
    ) -> RetainedLazyListMaterialization<[ViewNode]> {
        guard authorityIsCurrent(authority), request.isGenerationCurrent else { return .obsolete }
        guard let managed = authority.managed else {
            // The guard above proves absence, not merely an expired binding.
            return provider.materialize(request, budget: budget)
        }
        guard budget.remainingElements > 0 else { return .budgetExhausted }
        guard let prepaidProvider = provider as? any RetainedLazyListPrepaidProvider<[ViewNode]> else {
            return .obsolete
        }
        // The same shared element is debited before the facade can execute
        // authored typed hash/equality. A rejected attempt is never refunded.
        guard let prepaid = prepaidProvider.prepay(request, budget: budget) else { return .obsolete }
        defer { prepaid.abandon() }
        guard authorityIsCurrent(authority), prepaid.isCurrent else { return .obsolete }
        guard let preparation = managed.journal.prepareSelectedRow(request: request, descriptor: managed.descriptor)
        else { return .obsolete }
        let response = managed.activity.resolveSelectedLazyListRow(preparation)
        guard authorityIsCurrent(authority), prepaid.isCurrent, preparation.isCurrent, let response else {
            managed.journal.abandonSelectedRowPreparation(preparation)
            return .obsolete
        }
        guard let attribution = managed.journal.consumeSelectedRowResolution(response, for: preparation),
            authorityIsCurrent(authority), prepaid.isCurrent
        else {
            managed.journal.abandonSelectedRowPreparation(preparation)
            return .obsolete
        }
        let result = materializeEnteredRecord(
            request, budget: budget, authority: authority, attribution: attribution, activity: managed.activity,
            provider: prepaidProvider, prepaid: prepaid)
        // Leave and its temporary captures have unwound before this proof.
        guard authorityIsCurrent(authority), request.isGenerationCurrent else { return .obsolete }
        if case .built(let built) = result, built.request == request,
            !ViewNode.containsRejectedRetainedSource(in: built.content)
        {
            rowActivity = RetainedLazyListMaterializedRowActivity(attribution)
        }
        return result
    }

    @inline(never)
    private func materializeEnteredRecord(
        _ request: RetainedLazyListRowRequest, budget: RetainedLazyListWorkBudget,
        authority: PreparationAuthority, attribution: RetainedLazyListBuildAttribution,
        activity: any RetainedLazyListBuildActivity,
        provider: any RetainedLazyListPrepaidProvider<[ViewNode]>, prepaid: RetainedLazyListPrepaidElement
    ) -> RetainedLazyListMaterialization<[ViewNode]> {
        guard authorityIsCurrent(authority), prepaid.isCurrent,
            case .admittedForConstruction = attribution.constructionState
        else {
            return .obsolete
        }
        let entered = activity.enterLazyListMaterialization(attribution)
        let result: RetainedLazyListMaterialization<[ViewNode]>
        if entered, authorityIsCurrent(authority), prepaid.isCurrent,
            case .admittedForConstruction = attribution.constructionState
        {
            result = provider.materialize(request, budget: budget, prepaid: prepaid)
        } else {
            result = .obsolete
        }
        // Exact frame cleanup is obligatory even if enter or content reentered
        // and revoked the operation. It cannot pop a newer entered frame.
        activity.leaveLazyListMaterialization(attribution)
        return result
    }

    /// Prefixes authenticate the captured row namespace, not the canonical
    /// shape of a facade's builder path. The factory must append that path.
    /// Full typed identities are compared pairwise within the bounded candidate
    /// forest; no Set invokes a whole identity's authored hashes unchecked.
    private func validatedIdentityProofs(
        for nodes: [ViewNode], prefix: RetainedViewIdentity,
        previousRoots: [ViewNode], authority: PreparationAuthority
    ) -> [RetainedLazyListViewIdentityProof]? {
        guard authorityIsCurrent(authority) else { return nil }
        let proofs = nodes.map { $0.captureLazyListIdentityProof() }
        guard authorityIsCurrent(authority, additionalProofs: proofs) else { return nil }
        for index in nodes.indices {
            let matches = identityMatchesPrefix(
                of: nodes[index], prefix: prefix, authority: authority, proofs: proofs)
            guard authorityIsCurrent(authority, additionalProofs: proofs), matches else { return nil }
            for previous in previousRoots {
                let equal = identitiesEqual(
                    nodes[index], previous, authority: authority, proofs: proofs)
                guard authorityIsCurrent(authority, additionalProofs: proofs), equal == false else { return nil }
            }
            for earlier in nodes[..<index] {
                let equal = identitiesEqual(
                    nodes[index], earlier, authority: authority, proofs: proofs)
                guard authorityIsCurrent(authority, additionalProofs: proofs), equal == false else { return nil }
            }
        }
        return proofs
    }

    private func identityMatchesPrefix(
        of node: ViewNode, prefix: RetainedViewIdentity,
        authority: PreparationAuthority, proofs: [RetainedLazyListViewIdentityProof]
    ) -> Bool {
        guard authorityIsCurrent(authority, additionalProofs: proofs) else { return false }
        let value = node.retainedViewIdentity
        guard authorityIsCurrent(authority, additionalProofs: proofs),
            let value, value.segments.count > prefix.segments.count
        else { return false }
        for index in prefix.segments.indices {
            guard authorityIsCurrent(authority, additionalProofs: proofs) else { return false }
            let equal = value.segments[index] == prefix.segments[index]
            guard authorityIsCurrent(authority, additionalProofs: proofs), equal else { return false }
        }
        // Presence is checked; canonical branch/leaf numbering remains the
        // identified factory's contract. Never invent a flattened leaf slot.
        return value.segments.dropFirst(prefix.segments.count).contains { segment in
            switch segment {
            case .view, .role, .slot, .branch, .iteration, .occurrence:
                return true
            case .keyed, .explicit:
                return false
            }
        }
    }

    /// Each segment equality is one explicit callout boundary. Identity values
    /// and their typed keys die in this helper before its caller checks again.
    private func identitiesEqual(
        _ lhs: ViewNode, _ rhs: ViewNode,
        authority: PreparationAuthority, proofs: [RetainedLazyListViewIdentityProof]
    ) -> Bool? {
        guard authorityIsCurrent(authority, additionalProofs: proofs) else { return nil }
        let left = lhs.retainedViewIdentity
        guard authorityIsCurrent(authority, additionalProofs: proofs) else { return nil }
        let right = rhs.retainedViewIdentity
        guard authorityIsCurrent(authority, additionalProofs: proofs), let left, let right else { return nil }
        guard left.segments.count == right.segments.count else { return false }
        for index in left.segments.indices {
            guard authorityIsCurrent(authority, additionalProofs: proofs) else { return nil }
            let equal = left.segments[index] == right.segments[index]
            guard authorityIsCurrent(authority, additionalProofs: proofs) else { return nil }
            if !equal { return false }
        }
        return true
    }

    private func snapshotIsCurrent(for viewport: Viewport) -> Bool {
        generation?.isCurrent == true && extentIndex?.context == viewport.context
    }

    private func cachedSnapshotForManagedWidthChange(
        _ viewport: Viewport, wasIncomplete: Bool, managed: ManagedPreparation?
    ) -> Snapshot? {
        // Raw providers may consume the changed context while constructing
        // rows. Their existing refresh path, and every content/environment or
        // scale revision, must continue to evaluate the current row window.
        guard let managed, acceptedSnapshot, !wasIncomplete,
            let generation, generation.isCurrent, generation == managed.descriptor.sourceGeneration,
            let previous = extentIndex?.context, previous.width != viewport.context.width,
            previous.displayScale == viewport.context.displayScale,
            previous.contentRevision == viewport.context.contentRevision,
            previous.environmentRevision == viewport.context.environmentRevision
        else { return nil }
        return Snapshot(generation: generation, tokens: tokens, positions: positions)
    }

    private func operationIsCurrent(
        _ expectedAttempt: RetainedLazyListAdapterIdentity,
        configuration expectedConfiguration: RetainedLazyListAdapterIdentity,
        admission: RetainedLazyListAdoptionAdmission? = nil,
        identityProofs: [RetainedLazyListViewIdentityProof] = []
    ) -> Bool {
        !isReleasing && attempt === expectedAttempt && configuration === expectedConfiguration
            && admission?.isBuildCurrent(for: self) != false && identityProofs.allSatisfy(\.isCurrent)
            && managedLogicalDescriptor?.isCurrent != false
    }

    private func recordIsCurrent(_ record: Record) -> Bool {
        record.configuration === configuration && record.request.isGenerationCurrent
            && positions[record.request.token] == record.request.sourceIndex
            && record.identityProofs.allSatisfy(\.isCurrent)
            && record.activity?.isCurrent != false
    }

    fileprivate func isOperationCurrent(_ candidate: Candidate) -> Bool {
        candidate.adapter === self
            && operationIsCurrent(candidate.attempt, configuration: candidate.configuration)
            && generation == candidate.generation && candidate.generation.isCurrent
            && extentIndex?.context == candidate.viewport.context
            && candidate.requestProofs.allSatisfy(\.isGenerationCurrent)
    }

    fileprivate func isCurrent(_ candidate: Candidate) -> Bool {
        !candidate.wasConsumed && isOperationCurrent(candidate)
            && candidate.identityProofs.allSatisfy(\.isCurrent)
            && candidate.carriedRecordProofs.values.allSatisfy(\.isCurrent)
    }

    /// Required viewport records get capacity before optional prefetch. The
    /// protected allowance uses that same capacity, including overlap with the
    /// viewport. Each cursor jumps over zero-coordinate runs in O(log N).
    /// No plan scans all IDs or copies the extent index.
    private func windowSelection(
        _ viewport: Viewport, protecting requestedProtected: Set<RetainedLazyListRowToken>
    ) -> WindowSelection? {
        guard
            let expanded = extentIndex?.window(
                offset: viewport.offset, viewportExtent: viewport.extent, prefetchExtent: prefetchExtent),
            let visible = extentIndex?.window(offset: viewport.offset, viewportExtent: viewport.extent)
        else { return nil }
        var protected = Set(requestedProtected.filter { positions[$0] != nil })
        if let token = logicalRealizationTokenForSelection { protected.insert(token) }
        guard protected.count <= maximumProtectedRecords else { return nil }
        guard protected.count <= maximumMountedRecords else { return nil }
        if !transitionRequiredTokens.isEmpty {
            let required = protected.union(transitionRequiredTokens.filter { positions[$0] != nil })
            guard required.count <= maximumMountedRecords else { return nil }
            // Refresh the previous actual viewport before selecting a second
            // estimated window. Two disjoint windows must not demand twice the
            // record capacity during a source, width, or environment change.
            return WindowSelection(
                tokens: required.sorted { positions[$0, default: Int.max] < positions[$1, default: Int.max] },
                requiredTokens: required, exceedsRecordLimit: false)
        }
        var selected = protected
        var priority: [RetainedLazyListRowToken] = []
        if !visible.isEmpty {
            guard let visibleEnd = extentIndex?.prefixOffset(before: visible.upperBound) else { return nil }
            var position = visible.lowerBound
            while position < visible.upperBound {
                guard let record = coordinateRecord(at: position) else { return nil }
                if !selected.contains(record.token) {
                    guard selected.count < maximumMountedRecords else {
                        return WindowSelection(tokens: priority, requiredTokens: selected, exceedsRecordLimit: true)
                    }
                    selected.insert(record.token)
                }
                priority.append(record.token)
                if record.end >= visibleEnd { break }
                guard let next = followingRecord(from: record.end, through: visibleEnd),
                    next.position > position
                else { return nil }
                position = next.position
            }
        }
        let required = selected
        guard prefetchExtent > 0, !expanded.isEmpty, selected.count < maximumMountedRecords else {
            return WindowSelection(tokens: priority, requiredTokens: required, exceedsRecordLimit: false)
        }
        let total = extentIndex?.totalExtent ?? 0
        let viewportEnd = viewport.offset + viewport.extent
        let lower = max(0, viewport.offset - prefetchExtent)
        let upper = min(total, viewportEnd + prefetchExtent)
        let leadingBoundary: Double
        let trailingBoundary: Double
        if visible.isEmpty {
            leadingBoundary = min(max(0, viewport.offset), total)
            trailingBoundary = min(max(0, viewportEnd), total)
        } else {
            guard let first = extentIndex?.prefixOffset(before: visible.lowerBound),
                let last = extentIndex?.prefixOffset(before: visible.upperBound)
            else { return nil }
            leadingBoundary = first
            trailingBoundary = last
        }
        var leading = precedingRecord(before: leadingBoundary, after: lower)
        var trailing = followingRecord(from: trailingBoundary, through: upper)
        // A step either fills a spare slot, skips a protected record, or skips
        // the one possible shared record around an empty viewport point. The
        // explicit counter bounds even an unexpected duplicate cursor result.
        let spare = maximumMountedRecords - selected.count
        let (withProtected, overflow) = spare.addingReportingOverflow(protected.count)
        var remainingAdvances = overflow ? Int.max : withProtected
        if remainingAdvances < Int.max { remainingAdvances += 1 }
        while selected.count < maximumMountedRecords, remainingAdvances > 0 {
            guard leading != nil || trailing != nil else { break }
            remainingAdvances -= 1
            let chooseLeading: Bool
            if let leading, let trailing {
                let leadingGap = max(0, viewport.offset - leading.end)
                let trailingGap = max(0, trailing.start - viewportEnd)
                chooseLeading = leadingGap <= trailingGap
            } else {
                chooseLeading = leading != nil
            }
            let next: CoordinateRecord
            if chooseLeading, let record = leading {
                next = record
                leading = precedingRecord(before: record.start, after: lower)
            } else if let record = trailing {
                next = record
                trailing = followingRecord(from: record.end, through: upper)
            } else {
                break
            }
            if selected.insert(next.token).inserted { priority.append(next.token) }
        }
        return WindowSelection(tokens: priority, requiredTokens: required, exceedsRecordLimit: false)
    }

    private func coordinateRecord(at position: Int) -> CoordinateRecord? {
        guard tokens.indices.contains(position),
            let start = extentIndex?.prefixOffset(before: position),
            let end = extentIndex?.prefixOffset(before: position + 1), start < end
        else { return nil }
        return CoordinateRecord(token: tokens[position], position: position, start: start, end: end)
    }

    private func followingRecord(from boundary: Double, through upper: Double) -> CoordinateRecord? {
        guard boundary < upper,
            let range = extentIndex?.window(offset: boundary, viewportExtent: upper - boundary),
            !range.isEmpty
        else { return nil }
        return coordinateRecord(at: range.lowerBound)
    }

    private func precedingRecord(before boundary: Double, after lower: Double) -> CoordinateRecord? {
        guard boundary > lower, boundary > 0,
            let anchor = extentIndex?.captureAnchor(at: boundary.nextDown),
            let position = positions[anchor.token], let record = coordinateRecord(at: position),
            record.start < boundary, record.end > lower
        else { return nil }
        return record
    }

    private func recordsMatchMounted(_ records: [Record]) -> Bool {
        guard records.count == mounted.count else { return false }
        return records.allSatisfy { record in
            guard let existing = mounted[record.request.token],
                existing.request == record.request, existing.configuration === record.configuration,
                existing.activity === record.activity, existing.nodes.count == record.nodes.count
            else { return false }
            return zip(existing.nodes, record.nodes).allSatisfy { $0 === $1 }
        }
    }

    private func carriedRecordProof(for record: Record) -> CarriedRecordProof? {
        guard managedLogicalDescriptor != nil, let owner = attachmentOwner,
            let runtime = owner.retainedLazyListRuntime, owner.retainedLazyListAdapter === self,
            positions[record.request.token] != nil, let activity = record.activity,
            record.identityProofs.count == record.nodes.count, record.identityProofs.allSatisfy(\.isCurrent),
            record.nodes.allSatisfy({ node in
                node.parent === owner && node.retainedLazyListRuntime === runtime
                    && owner.children.contains(where: { $0 === node })
            })
        else { return nil }
        let container = owner.lazyListActivityStorage().captureActualAttachment(of: owner, in: runtime)
        let roots = record.nodes.map { $0.lazyListActivityStorage().captureActualAttachment(of: $0, in: runtime) }
        let proof = CarriedRecordProof(record: record, container: container, roots: roots, activity: activity)
        return proof.isCurrent ? proof : nil
    }

    private func carriedIdentitiesAreDistinct(
        _ record: Record, from previousRoots: [ViewNode], authority: PreparationAuthority
    ) -> Bool {
        guard authorityIsCurrent(authority, additionalProofs: record.identityProofs) else { return false }
        for node in record.nodes {
            for previous in previousRoots {
                let equal = identitiesEqual(node, previous, authority: authority, proofs: record.identityProofs)
                guard authorityIsCurrent(authority, additionalProofs: record.identityProofs), equal == false else {
                    return false
                }
            }
        }
        return authorityIsCurrent(authority, additionalProofs: record.identityProofs)
    }

    private func rememberRequiredActualRows(_ selection: WindowSelection) {
        guard transitionRequiredTokens.isEmpty else { return }
        lastRequiredTokens = Set(
            selection.requiredTokens.filter { token in
                guard let record = mounted[token] else { return false }
                return recordIsCurrent(record) && record.extents != nil
            })
    }

    private func finishTransitionMeasurements(for tokens: Set<RetainedLazyListRowToken>) {
        if !transitionAwaitingMeasurements.isDisjoint(with: tokens) { transitionCapacityDeferred = [] }
        transitionAwaitingMeasurements.subtract(tokens)
        if transitionAwaitingMeasurements.isEmpty { transitionRequiredTokens = [] }
    }

    private func gapSummary(of nodes: [ViewNode]) -> GapBoundarySummary? {
        var first: GapRowBoundary?
        var last: GapRowBoundary?
        var projectedRowParity = false
        var declaredNext: GapRowBoundary?
        for node in nodes {
            if let gap = node.retainedLazyListGap {
                // Every framework gap precedes exactly one actual row root.
                // Consecutive or trailing markers are not facade row output.
                guard declaredNext == nil else { return nil }
                declaredNext = GapRowBoundary(gap)
            } else {
                let boundary = declaredNext ?? .ordinary
                declaredNext = nil
                if first == nil { first = boundary }
                last = boundary
                projectedRowParity.toggle()
            }
        }
        guard declaredNext == nil else { return nil }
        return GapBoundarySummary(first: first, last: last, projectedRowParity: projectedRowParity)
    }

    /// Refresh from actual accepted bounded nodes only. Stale identity or
    /// activity evidence withdraws a summary; a candidate never publishes one.
    private func refreshAcceptedGapBoundarySummaries() -> Bool {
        guard gapBoundaryIndex != nil else { return false }
        for (token, record) in mounted {
            guard let position = positions[token] else { continue }
            guard recordIsCurrent(record) else {
                gapBoundaryIndex?.update(at: position, to: nil)
                continue
            }
            guard let summary = gapSummary(of: record.nodes) else { return false }
            gapBoundaryIndex?.update(at: position, to: summary)
        }
        return true
    }

    private func gapPredecessor(before position: Int) -> GapPredecessor {
        if position == 0 { return .beginning }
        return gapBoundaryIndex?.predecessor(before: position) ?? .unknown(position: position - 1)
    }

    private func gapExtent(_ gap: RetainedLazyListGap, after predecessor: GapPredecessor) -> Double? {
        switch predecessor {
        case .beginning:
            return 0
        case .unknown:
            return nil
        case .row(let previous):
            if gap.separatorThickness == 0 || gap.nextRowIsSelected || gap.nextRowIsGrouped
                || previous.isSelected || previous.isGrouped
            {
                return gap.spacing
            }
            return 2 * gap.spacing + gap.separatorThickness
        }
    }

    private func hasUnresolvedLeadingGap(_ record: Record) -> Bool {
        guard record.nodes.first?.retainedLazyListGap != nil,
            let position = positions[record.request.token]
        else { return false }
        if case .unknown = gapPredecessor(before: position) { return true }
        return false
    }

    /// A preceding row in this checked candidate can retain later prefetch
    /// output, but cannot publish a boundary or measurement before adoption.
    /// Inspect its current nodes again after later factories; a cached summary
    /// could outlive authored changes to an earlier candidate. Empty records
    /// advance only through exact prepared entries, never unknown source rows.
    private func hasPreparedGapPredecessor(
        for record: Record, records: [Record], indices: [Int: Int]
    ) -> Bool {
        guard var position = positions[record.request.token] else { return false }
        while position > 0 {
            switch gapPredecessor(before: position) {
            case .beginning, .row:
                return true
            case .unknown(let previous):
                guard previous >= 0, previous < position,
                    let index = indices[previous], records.indices.contains(index)
                else { return false }
                let prepared = records[index]
                guard recordIsCurrent(prepared), let summary = gapSummary(of: prepared.nodes) else { return false }
                if summary.last != nil { return true }
                // Each step consumes a distinct earlier candidate entry, so
                // this scan is bounded by the physical record allowance.
                position = previous
            }
        }
        return true
    }

    /// One unknown predecessor per pass, using ordinary caps and factory
    /// admission. Its own predecessor is not recursively resolved. Once its
    /// summary is accepted, its nodes can leave the next bounded candidate.
    private func nextGapBoundaryProbe(required: Set<RetainedLazyListRowToken>) -> RetainedLazyListRowToken? {
        let ordered = required.sorted { positions[$0, default: Int.max] < positions[$1, default: Int.max] }
        for token in ordered {
            guard let record = mounted[token], recordIsCurrent(record),
                record.nodes.first?.retainedLazyListGap != nil,
                let position = positions[token]
            else { continue }
            if case .unknown(let previous) = gapPredecessor(before: position), tokens.indices.contains(previous) {
                return tokens[previous]
            }
        }
        return nil
    }

    private func needsResolution(selection: WindowSelection) -> Bool {
        if preparationIncomplete || pendingCandidate || !acceptedSnapshot || selection.exceedsRecordLimit
            || !transitionAwaitingMeasurements.isEmpty
        {
            return true
        }
        let allowed = Set(selection.tokens).union(selection.requiredTokens)
        guard selection.requiredTokens.isSubset(of: Set(mounted.keys)) else { return true }
        for (token, record) in mounted {
            guard allowed.contains(token), recordIsCurrent(record), record.extents != nil,
                !hasUnresolvedLeadingGap(record)
            else { return true }
        }
        // Missing optional prefetch cannot block otherwise current visible
        // geometry. Every actually mounted leaf still needs current layout.
        return false
    }

    /// No callback or reader can interleave with this MainActor native batch.
    /// Apply decreases first; on failure undo successful writes in reverse.
    /// This keeps the index unique instead of copying all O(N) tree storage.
    private func applyExtentUpdates(
        _ updates: [ExtentUpdate], context: RetainedLazyListMeasurementContext
    ) -> Bool {
        let ordered = updates.sorted {
            let leftDecreases = $0.next.totalExtent <= $0.previous.totalExtent
            let rightDecreases = $1.next.totalExtent <= $1.previous.totalExtent
            return leftDecreases && !rightDecreases
        }
        var applied: [ExtentUpdate] = []
        for update in ordered where update.previous != update.next {
            guard extentIndex?.updateExtent(for: update.token, to: update.next, context: context) == true else {
                for old in applied.reversed() {
                    let restored = extentIndex?.updateExtent(
                        for: old.token, to: old.previous, context: context)
                    precondition(restored == true, "A native extent batch must restore its previously valid values")
                }
                return false
            }
            applied.append(update)
        }
        return true
    }
}
