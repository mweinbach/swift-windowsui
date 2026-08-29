import SwiftWindowsCore
import SwiftWindowsUI

/// Construction does not grant presentation authority. The accepted record
/// below contains only native identities and the exact contribution receipt.
@MainActor
final class LazyPresentationActivityProposal {
    let attempt: RetainedLazyListAttemptID
    let component: RetainedLazyListComponentID
    let group: RetainedLazyListGroupID
    let physical: RetainedLazyListPhysicalActivityReceipt
    let admission: LazyListResolutionReceipt

    init(attribution: LazyListViewAttribution, group: RetainedLazyListGroupID) {
        attempt = attribution.native.attempt
        component = attribution.component
        self.group = group
        physical = attribution.native.physical
        admission = attribution.admission
    }

    var canConstruct: Bool {
        // A live logical owner must never revive a physically departed row.
        switch physical.state {
        case .revoked: return false
        case .provisional, .active: return admission.isCurrent
        }
    }

    func isProposed(in preparation: RetainedLazyListAdoptionPreparation) -> Bool {
        preparation.attempt === attempt
            && preparation.groups.contains {
                $0.attempt === attempt && $0.group === group && $0.component === component
                    && $0.physical === physical.id && $0.membership === physical.membership
            }
    }

    func accepted(in selection: LazyListStateAdoptionSelection) -> LazyPresentationActivity? {
        let key = ObjectIdentifier(group)
        guard selection.attempt === attempt, !selection.retiredGroups.contains(key),
            selection.acceptedGroups.contains(key) || selection.acceptedEmptyGroups.contains(key),
            let contribution = selection.contribution(for: group),
            contribution.group === group, contribution.physical === physical
        else { return nil }
        let activity = LazyPresentationActivity(contribution: contribution)
        return activity.isActive ? activity : nil
    }
}

@MainActor
final class LazyPresentationActivity {
    let contribution: RetainedLazyListContributionReceipt
    var group: RetainedLazyListGroupID { contribution.group }
    var physical: RetainedLazyListPhysicalActivityReceipt { contribution.physical }

    init(contribution: RetainedLazyListContributionReceipt) { self.contribution = contribution }

    var isActive: Bool {
        switch physical.state {
        case .active: return contribution.isActive
        case .provisional, .revoked: return false
        }
    }
}

/// Ordinary components in a descriptor build have native field authority but
/// no row membership or lazy physical lifetime. Capture the provisional receipt
/// now so an ordinary commit never needs to rediscover its finished journal.
@MainActor
final class DescriptorPresentationActivityProposal {
    let attribution: RetainedDescriptorComponentAttribution
    let group: RetainedDescriptorGroupID
    let contribution: RetainedDescriptorContributionReceipt

    init?(attribution: RetainedDescriptorComponentAttribution, group: RetainedDescriptorGroupID) {
        guard attribution.canConstruct, let contribution = attribution.contribution(for: group),
            contribution.group === group, attribution.canConstruct
        else { return nil }
        self.attribution = attribution
        self.group = group
        self.contribution = contribution
    }

    var canConstruct: Bool { attribution.canConstruct }

    func isProposed(in preparation: RetainedLazyListAdoptionPreparation) -> Bool {
        // Selected-row journals can differ from their bound descriptor scope.
        // Match the original scope here; commitLazyActivity separately matches
        // the preparation and selection journal attempts.
        preparation.ordinaryComponents.contains {
            $0.attempt === attribution.attempt && $0.component === attribution.component
                && $0.groups.contains {
                    $0.attempt === attribution.attempt && $0.component === attribution.component && $0.group === group
                }
        }
    }

    func accepted(in selection: LazyListStateAdoptionSelection) -> DescriptorPresentationActivity? {
        let key = ObjectIdentifier(group)
        guard !selection.retiredOrdinaryGroups.contains(key),
            selection.acceptedOrdinaryGroups.contains(key) || selection.acceptedEmptyOrdinaryGroups.contains(key),
            selection.ordinaryContribution(for: group) === contribution
        else { return nil }
        return acceptedForOrdinaryAdoption()
    }

    func acceptedForOrdinaryAdoption() -> DescriptorPresentationActivity? {
        let activity = DescriptorPresentationActivity(contribution: contribution)
        return activity.isActive ? activity : nil
    }
}

@MainActor
final class DescriptorPresentationActivity {
    let contribution: RetainedDescriptorContributionReceipt
    var group: RetainedDescriptorGroupID { contribution.group }
    var isActive: Bool { contribution.isActive }

    init(contribution: RetainedDescriptorContributionReceipt) { self.contribution = contribution }
}

@MainActor
enum PresentationAcceptedActivity {
    case lazy(LazyPresentationActivity)
    case descriptor(DescriptorPresentationActivity)

    var lazyActivity: LazyPresentationActivity? {
        if case .lazy(let activity) = self { return activity }
        return nil
    }

    var descriptorActivity: DescriptorPresentationActivity? {
        if case .descriptor(let activity) = self { return activity }
        return nil
    }

    func permitsReplacing(
        lazyActivity previousLazy: LazyPresentationActivity?,
        descriptorActivity previousDescriptor: DescriptorPresentationActivity?,
        in selection: LazyListStateAdoptionSelection
    ) -> Bool {
        if let previousLazy {
            return lazyActivity?.contribution === previousLazy.contribution
                || selection.retiredGroups.contains(ObjectIdentifier(previousLazy.group))
        }
        if let previousDescriptor {
            return descriptorActivity?.contribution === previousDescriptor.contribution
                || selection.retiredOrdinaryGroups.contains(ObjectIdentifier(previousDescriptor.group))
        }
        return false
    }
}

/// Private presentation authority is shorter lived than an inactive State mount.
/// An accepted declaration receipt never follows a path into a later session.
@MainActor
final class PresentationDismissConfiguration {
    typealias Admission = @MainActor () -> Bool
    typealias FocusRollback = @MainActor () -> Void
    typealias FocusPreparation = @MainActor (Admission) -> FocusRollback?

    let validate: @MainActor (Admission) -> Bool
    let writeDismissal: @MainActor () -> Void
    let onDismiss: (@MainActor () -> Void)?
    let invalidate: @MainActor () -> Void
    let prepareInteractiveFocus: FocusPreparation?

    init(
        validate: @escaping @MainActor (Admission) -> Bool,
        writeDismissal: @escaping @MainActor () -> Void,
        onDismiss: (@MainActor () -> Void)?,
        invalidate: @escaping @MainActor () -> Void,
        prepareInteractiveFocus: FocusPreparation? = nil
    ) {
        self.validate = validate
        self.writeDismissal = writeDismissal
        self.onDismiss = onDismiss
        self.invalidate = invalidate
        self.prepareInteractiveFocus = prepareInteractiveFocus
    }

    func materialized(preparingFocus: @escaping FocusPreparation) -> PresentationDismissConfiguration {
        PresentationDismissConfiguration(
            validate: validate, writeDismissal: writeDismissal, onDismiss: onDismiss,
            invalidate: invalidate, prepareInteractiveFocus: preparingFocus)
    }
}

private enum PresentationActivityPhase: Equatable {
    case provisional
    case active
    case suspended(ObjectIdentifier)
    case retired
}

@MainActor
private final class PresentationDismissSession {
    weak var ledger: PresentationActivityLedger?
    let owner: StateMountOwner
    var phase = PresentationActivityPhase.provisional
    var configuration: PresentationDismissConfiguration?
    var lazyActivity: LazyPresentationActivity?
    var descriptorActivity: DescriptorPresentationActivity?
    private var isDismissing = false

    init(ledger: PresentationActivityLedger, owner: StateMountOwner) {
        self.ledger = ledger
        self.owner = owner
    }

    func perform(interactively: Bool) {
        guard admitsPhysicalActivity, phase == .active, !isDismissing, owner.isLive,
            ledger?.admits(self) == true
        else { return }
        isDismissing = true
        defer { isDismissing = false }
        guard let configuration, isCurrent(configuration) else { return }
        let admission: PresentationDismissConfiguration.Admission = { [self] in
            isCurrent(configuration)
        }
        guard configuration.validate(admission), admission() else { return }
        if interactively {
            guard let restoreModalScope = configuration.prepareInteractiveFocus?(admission) else { return }
            guard admission(), configuration.validate(admission), admission() else {
                if admission() { restoreModalScope() }
                return
            }
        }
        configuration.writeDismissal()
        // A successful write may synchronously retire this very presentation.
        // Its admitted callback still belongs to this one dismissal.
        configuration.onDismiss?()
        configuration.invalidate()
    }

    private func isCurrent(_ configuration: PresentationDismissConfiguration) -> Bool {
        admitsPhysicalActivity && phase == .active && owner.isLive && self.configuration === configuration
            && ledger?.admits(self) == true
    }

    private var admitsPhysicalActivity: Bool {
        (lazyActivity?.isActive ?? true) && (descriptorActivity?.isActive ?? true)
    }

    func clearConfiguration() {
        // A released capture may synchronously try to dismiss or close again.
        let outgoing = configuration
        configuration = nil
        withExtendedLifetime(outgoing) {}
    }
}

@MainActor
private final class PresentationDeclarationReceipt {
    weak var session: PresentationDismissSession?
    var isAccepted = false
    var isDiscarded = false
    private let isLazy: Bool
    var lazyActivity: LazyPresentationActivity?
    private let isDescriptor: Bool

    init(session: PresentationDismissSession? = nil, isLazy: Bool = false, isDescriptor: Bool = false) {
        self.session = session
        self.isLazy = isLazy
        self.isDescriptor = isDescriptor
    }

    func perform(interactively: Bool) {
        guard !isLazy || lazyActivity?.isActive == true else { return }
        guard isAccepted, !isDiscarded, let session else { return }
        // Ordinary compatible configuration refreshes keep the same dismissal
        // session. Its current exact receipt preserves that existing policy;
        // lazy declarations instead retain their own shorter group authority.
        guard !isDescriptor || session.descriptorActivity?.isActive == true else { return }
        session.perform(interactively: interactively)
    }
}

/// Core's closures retain only this receipt, never a candidate configuration.
@MainActor
final class PresentationDismissHandle {
    private let receipt: PresentationDeclarationReceipt
    private weak var build: PresentationActivityBuild?

    fileprivate init(receipt: PresentationDeclarationReceipt, build: PresentationActivityBuild) {
        self.receipt = receipt
        self.build = build
    }

    private init() {
        receipt = PresentationDeclarationReceipt()
        receipt.isDiscarded = true
    }

    static func unavailable() -> PresentationDismissHandle { PresentationDismissHandle() }

    func dismiss() { receipt.perform(interactively: false) }
    func dismissInteractively() { receipt.perform(interactively: true) }

    func materialize(preparingFocus: @escaping PresentationDismissConfiguration.FocusPreparation) {
        build?.materialize(receipt, preparingFocus: preparingFocus)
    }
}

/// Each newly authored reader lease receives its own provisional receipt.
/// The old accepted lease stays authoritative until an actual adoption.
@MainActor
final class PresentationActivityAnchor {
    fileprivate weak var ledger: PresentationActivityLedger?
    let owner: StateMountOwner
    let contentPrefix: RetainedViewIdentity
    fileprivate var phase = PresentationActivityPhase.provisional
    fileprivate var isMaterialized = false
    let lazyGroup: RetainedLazyListGroupID?
    let lazyPhysical: RetainedLazyListPhysicalActivityReceipt?
    fileprivate var lazyActivity: LazyPresentationActivity?
    var lazyContribution: RetainedLazyListContributionReceipt? { lazyActivity?.contribution }
    let descriptorGroup: RetainedDescriptorGroupID?
    fileprivate var descriptorActivity: DescriptorPresentationActivity?
    var descriptorContribution: RetainedDescriptorContributionReceipt? { descriptorActivity?.contribution }

    fileprivate init(
        ledger: PresentationActivityLedger?, owner: StateMountOwner, contentPrefix: RetainedViewIdentity,
        lazyProposal: LazyPresentationActivityProposal? = nil,
        descriptorProposal: DescriptorPresentationActivityProposal? = nil
    ) {
        self.ledger = ledger
        self.owner = owner
        self.contentPrefix = contentPrefix
        lazyGroup = lazyProposal?.group
        lazyPhysical = lazyProposal?.physical
        descriptorGroup = descriptorProposal?.group
    }

    static func unavailable(owner: StateMountOwner, contentPrefix: RetainedViewIdentity) -> PresentationActivityAnchor {
        let anchor = PresentationActivityAnchor(ledger: nil, owner: owner, contentPrefix: contentPrefix)
        anchor.phase = .retired
        return anchor
    }

    var isActive: Bool {
        guard lazyGroup == nil || lazyActivity?.isActive == true else { return false }
        guard descriptorGroup == nil || descriptorActivity?.isActive == true else { return false }
        return phase == .active && owner.isLive && ledger?.admits(self) == true
    }
}

@MainActor
final class PresentationActivityLedger {
    var alertSlots: [ObjectIdentifier: RetainedAlertSlot] = [:]
    fileprivate var sessions: [ObjectIdentifier: PresentationDismissSession] = [:]
    fileprivate var anchors: [ObjectIdentifier: PresentationActivityAnchor] = [:]
    fileprivate weak var currentBuild: PresentationActivityBuild?
    private(set) var isClosed = false

    func beginBuild(
        prefix: RetainedViewIdentity? = nil, boundary: PresentationActivityAnchor? = nil
    ) -> PresentationActivityBuild? {
        guard !isClosed, currentBuild == nil else { return nil }
        if prefix != nil, boundary?.isActive != true { return nil }
        let build = PresentationActivityBuild(ledger: self, prefix: prefix, boundary: boundary)
        currentBuild = build
        return build
    }

    fileprivate func admits(_ session: PresentationDismissSession) -> Bool {
        !isClosed && sessions[ObjectIdentifier(session.owner)] === session
    }

    fileprivate func admits(_ anchor: PresentationActivityAnchor) -> Bool {
        !isClosed && anchors[ObjectIdentifier(anchor.owner)] === anchor
    }

    /// Mark all authority before State cleanup can release application payloads.
    func closeAdmissions() {
        guard !isClosed else { return }
        isClosed = true
        for slot in alertSlots.values { slot.closeAdmissions() }
        for session in sessions.values { session.phase = .retired }
        for anchor in anchors.values { anchor.phase = .retired }
        currentBuild?.closeAdmissions()
    }

    /// The coordinator calls this only after State writes have been revoked.
    func releaseClosedPayloads() {
        guard isClosed else { return }
        let oldSessions = Array(sessions.values)
        let oldAnchors = Array(anchors.values)
        let oldBuild = currentBuild
        let oldAlerts = alertSlots
        alertSlots = [:]
        sessions.removeAll()
        anchors.removeAll()
        for session in oldSessions { session.clearConfiguration() }
        oldBuild?.releaseClosedPayloads()
        withExtendedLifetime((oldSessions, oldAnchors, oldBuild, oldAlerts)) {}
    }
}

@MainActor
final class PresentationActivityBuild {
    let alerts: RetainedAlertActivityBuild
    private enum Phase {
        case constructing
        case prepared
        case committed
        case abandoned
        case finished
    }

    private struct Candidate {
        let session: PresentationDismissSession
        let receipt: PresentationDeclarationReceipt
        let configuration: PresentationDismissConfiguration
        var materializedConfiguration: PresentationDismissConfiguration?
        var lazyProposal: LazyPresentationActivityProposal?
        var descriptorProposal: DescriptorPresentationActivityProposal?
    }

    private weak var ledger: PresentationActivityLedger?
    private let prefix: RetainedViewIdentity?
    private let boundary: PresentationActivityAnchor?
    private var phase = Phase.constructing
    private var candidates: [ObjectIdentifier: Candidate] = [:]
    private var candidateAnchors: [ObjectIdentifier: PresentationActivityAnchor] = [:]
    private var suspendedSessions: [PresentationDismissSession] = []
    private var suspendedAnchors: [PresentationActivityAnchor] = []
    private var discardedCandidates: [Candidate] = []
    private var displacedConfigurations: [PresentationDismissConfiguration] = []
    private var lazyAnchorProposals: [ObjectIdentifier: LazyPresentationActivityProposal] = [:]
    private var descriptorAnchorProposals: [ObjectIdentifier: DescriptorPresentationActivityProposal] = [:]
    private var discardedAnchors: [PresentationActivityAnchor] = []
    private var lazyPreparation: RetainedLazyListAdoptionPreparation?
    private var pinnedLazySessions: [PresentationDismissSession] = []
    private var pinnedLazyAnchors: [PresentationActivityAnchor] = []
    private var pinnedDescriptorSessions: [PresentationDismissSession] = []
    private var pinnedDescriptorAnchors: [PresentationActivityAnchor] = []

    fileprivate init(
        ledger: PresentationActivityLedger, prefix: RetainedViewIdentity?, boundary: PresentationActivityAnchor?
    ) {
        self.ledger = ledger
        alerts = RetainedAlertActivityBuild(ledger: ledger)
        self.prefix = prefix
        self.boundary = boundary
    }

    var canConstruct: Bool {
        guard phase == .constructing, let ledger, !ledger.isClosed,
            ledger.currentBuild === self
        else { return false }
        return boundary == nil || boundary?.isActive == true
    }

    func stagePresentation(
        owner: StateMountOwner, configuration: PresentationDismissConfiguration
    ) -> PresentationDismissHandle {
        guard canConstruct, let ledger, includes(owner.identity), canConstruct else { return .unavailable() }
        let key = ObjectIdentifier(owner)
        let session = ledger.sessions[key] ?? PresentationDismissSession(ledger: ledger, owner: owner)
        let receipt = PresentationDeclarationReceipt(session: session)
        if let previous = candidates[key] {
            previous.receipt.isDiscarded = true
            discardedCandidates.append(previous)
        }
        candidates[key] = Candidate(session: session, receipt: receipt, configuration: configuration)
        return PresentationDismissHandle(receipt: receipt, build: self)
    }

    func stagePresentation(
        owner: StateMountOwner, configuration: PresentationDismissConfiguration,
        attribution: LazyListViewAttribution, group: RetainedLazyListGroupID
    ) -> PresentationDismissHandle {
        let proposal = LazyPresentationActivityProposal(attribution: attribution, group: group)
        guard proposal.canConstruct, canConstruct, let ledger else { return .unavailable() }
        let key = ObjectIdentifier(owner)
        let previousSession = ledger.sessions[key]
        let session: PresentationDismissSession
        if let previousSession, let activity = previousSession.lazyActivity,
            activity.physical === proposal.physical, activity.isActive
        {
            session = previousSession
        } else {
            session = PresentationDismissSession(ledger: ledger, owner: owner)
        }
        let receipt = PresentationDeclarationReceipt(session: session, isLazy: true)
        if let previous = candidates[key] {
            previous.receipt.isDiscarded = true
            discardedCandidates.append(previous)
        }
        candidates[key] = Candidate(
            session: session, receipt: receipt, configuration: configuration, lazyProposal: proposal)
        return PresentationDismissHandle(receipt: receipt, build: self)
    }

    func stagePresentation(
        owner: StateMountOwner, configuration: PresentationDismissConfiguration,
        descriptorAttribution: RetainedDescriptorComponentAttribution, group: RetainedDescriptorGroupID
    ) -> PresentationDismissHandle {
        guard let proposal = DescriptorPresentationActivityProposal(attribution: descriptorAttribution, group: group),
            proposal.canConstruct, canConstruct, let ledger
        else { return .unavailable() }
        let key = ObjectIdentifier(owner)
        let previousSession = ledger.sessions[key]
        let session: PresentationDismissSession
        if let previousSession, previousSession.descriptorActivity?.isActive == true {
            session = previousSession
        } else {
            session = PresentationDismissSession(ledger: ledger, owner: owner)
        }
        let receipt = PresentationDeclarationReceipt(session: session, isDescriptor: true)
        if let previous = candidates[key] {
            previous.receipt.isDiscarded = true
            discardedCandidates.append(previous)
        }
        candidates[key] = Candidate(
            session: session, receipt: receipt, configuration: configuration, descriptorProposal: proposal)
        return PresentationDismissHandle(receipt: receipt, build: self)
    }

    func stageAnchor(owner: StateMountOwner, contentPrefix: RetainedViewIdentity) -> PresentationActivityAnchor {
        guard canConstruct, let ledger else { return .unavailable(owner: owner, contentPrefix: contentPrefix) }
        let isBoundary = boundary?.owner === owner && boundary?.contentPrefix == contentPrefix
        guard isBoundary || includes(owner.identity), canConstruct else {
            return .unavailable(owner: owner, contentPrefix: contentPrefix)
        }
        let anchor = PresentationActivityAnchor(ledger: ledger, owner: owner, contentPrefix: contentPrefix)
        let key = ObjectIdentifier(owner)
        candidateAnchors[key]?.phase = .retired
        candidateAnchors[key] = anchor
        return anchor
    }

    func stageAnchor(
        owner: StateMountOwner, contentPrefix: RetainedViewIdentity,
        attribution: LazyListViewAttribution, group: RetainedLazyListGroupID
    ) -> PresentationActivityAnchor {
        let proposal = LazyPresentationActivityProposal(attribution: attribution, group: group)
        guard proposal.canConstruct, canConstruct, let ledger else {
            return .unavailable(owner: owner, contentPrefix: contentPrefix)
        }
        let anchor = PresentationActivityAnchor(
            ledger: ledger, owner: owner, contentPrefix: contentPrefix, lazyProposal: proposal)
        let key = ObjectIdentifier(owner)
        if let previous = candidateAnchors[key] {
            previous.phase = .retired
            discardedAnchors.append(previous)
        }
        lazyAnchorProposals[ObjectIdentifier(anchor)] = proposal
        candidateAnchors[key] = anchor
        return anchor
    }

    func stageAnchor(
        owner: StateMountOwner, contentPrefix: RetainedViewIdentity,
        descriptorAttribution: RetainedDescriptorComponentAttribution, group: RetainedDescriptorGroupID
    ) -> PresentationActivityAnchor {
        guard let proposal = DescriptorPresentationActivityProposal(attribution: descriptorAttribution, group: group),
            proposal.canConstruct, canConstruct, let ledger
        else { return .unavailable(owner: owner, contentPrefix: contentPrefix) }
        let anchor = PresentationActivityAnchor(
            ledger: ledger, owner: owner, contentPrefix: contentPrefix, descriptorProposal: proposal)
        let key = ObjectIdentifier(owner)
        if let previous = candidateAnchors[key] {
            previous.phase = .retired
            discardedAnchors.append(previous)
        }
        descriptorAnchorProposals[ObjectIdentifier(anchor)] = proposal
        candidateAnchors[key] = anchor
        return anchor
    }

    fileprivate func materialize(
        _ receipt: PresentationDeclarationReceipt,
        preparingFocus: @escaping PresentationDismissConfiguration.FocusPreparation
    ) {
        guard canConstruct, let owner = receipt.session?.owner else { return }
        let key = ObjectIdentifier(owner)
        guard var candidate = candidates[key], candidate.receipt === receipt, !receipt.isDiscarded,
            candidate.lazyProposal?.canConstruct ?? true, candidate.descriptorProposal?.canConstruct ?? true
        else { return }
        if let previous = candidate.materializedConfiguration { displacedConfigurations.append(previous) }
        candidate.materializedConfiguration = candidate.configuration.materialized(preparingFocus: preparingFocus)
        candidates[key] = candidate
    }

    func materialize(_ anchor: PresentationActivityAnchor) {
        guard canConstruct, candidateAnchors[ObjectIdentifier(anchor.owner)] === anchor else { return }
        if anchor.lazyGroup != nil {
            guard lazyAnchorProposals[ObjectIdentifier(anchor)]?.canConstruct == true else { return }
        }
        if anchor.descriptorGroup != nil {
            guard descriptorAnchorProposals[ObjectIdentifier(anchor)]?.canConstruct == true else { return }
        }
        anchor.isMaterialized = true
    }

    /// Discard authority before the matching State discard releases payloads.
    func discardSubtree(at prefix: RetainedViewIdentity, isCurrent: () -> Bool) {
        guard isCurrent(), canConstruct else { return }
        alerts.discardSubtree(at: prefix, isCurrent: { isCurrent() && self.canConstruct })
        guard isCurrent(), canConstruct else { return }
        let records = Array(candidates)
        let readers = Array(candidateAnchors)
        var removedRecords: [ObjectIdentifier] = []
        var removedReaders: [ObjectIdentifier] = []
        for (key, candidate) in records {
            guard candidate.lazyProposal?.canConstruct ?? true, candidate.descriptorProposal?.canConstruct ?? true
            else { continue }
            let matches =
                candidate.session.owner.identity.checkedHasPrefix(
                    prefix,
                    isCurrent: {
                        (candidate.lazyProposal?.canConstruct ?? true)
                            && (candidate.descriptorProposal?.canConstruct ?? true) && isCurrent() && self.canConstruct
                    }) == true
            guard candidate.lazyProposal?.canConstruct ?? true, candidate.descriptorProposal?.canConstruct ?? true,
                isCurrent(), canConstruct
            else { return }
            if matches { removedRecords.append(key) }
        }
        for (key, anchor) in readers {
            let proposal = lazyAnchorProposals[ObjectIdentifier(anchor)]
            let descriptorProposal = descriptorAnchorProposals[ObjectIdentifier(anchor)]
            guard proposal?.canConstruct ?? true, descriptorProposal?.canConstruct ?? true else { continue }
            let matches =
                anchor.owner.identity.checkedHasPrefix(
                    prefix,
                    isCurrent: {
                        (proposal?.canConstruct ?? true) && (descriptorProposal?.canConstruct ?? true)
                            && isCurrent() && self.canConstruct
                    }) == true
            guard proposal?.canConstruct ?? true, descriptorProposal?.canConstruct ?? true, isCurrent(), canConstruct
            else { return }
            if matches { removedReaders.append(key) }
        }
        for key in removedRecords {
            if let candidate = candidates.removeValue(forKey: key) {
                candidate.receipt.isDiscarded = true
                discardedCandidates.append(candidate)
            }
        }
        for key in removedReaders {
            if let anchor = candidateAnchors.removeValue(forKey: key) {
                anchor.phase = .retired
                if anchor.lazyGroup != nil || anchor.descriptorGroup != nil { discardedAnchors.append(anchor) }
            }
        }
    }

    /// Cover compatible survivors too: callbacks must not use the old config
    /// while new retained nodes are only partially adopted.
    func prepare(isCurrent: () -> Bool) -> Bool {
        guard isCurrent(), canConstruct, let ledger else { return false }
        let oldSessions = Array(ledger.sessions.values)
        let oldAnchors = Array(ledger.anchors.values)
        var coveredSessions: [PresentationDismissSession] = []
        var coveredAnchors: [PresentationActivityAnchor] = []
        for session in oldSessions {
            let covered = includes(session.owner.identity, isCurrent: isCurrent)
            guard isCurrent(), canConstruct else { return false }
            if covered { coveredSessions.append(session) }
        }
        for anchor in oldAnchors {
            let covered = anchor === boundary || includes(anchor.owner.identity, isCurrent: isCurrent)
            guard isCurrent(), canConstruct else { return false }
            if covered { coveredAnchors.append(anchor) }
        }
        guard isCurrent(), canConstruct else { return false }
        guard
            alerts.prepare(
                includes: { self.includes($0, isCurrent: isCurrent) }, isCurrent: { isCurrent() && self.canConstruct })
        else { return false }
        suspendedSessions = coveredSessions
        suspendedAnchors = coveredAnchors
        let suspension = PresentationActivityPhase.suspended(ObjectIdentifier(self))
        for session in coveredSessions { session.phase = suspension }
        for anchor in coveredAnchors { anchor.phase = suspension }
        phase = .prepared
        return true
    }

    /// The native-only form does not evaluate authored identity equality.
    /// Mixed builds use the guarded overload to reject unmarked legacy scope.
    func prepareLazyActivity(_ preparation: RetainedLazyListAdoptionPreparation) -> Bool {
        prepareLazyActivity(preparation, includingOrdinary: false, isCurrent: { self.canConstruct })
    }

    func prepareLazyActivity(
        _ preparation: RetainedLazyListAdoptionPreparation, isCurrent: () -> Bool
    ) -> Bool {
        prepareLazyActivity(preparation, includingOrdinary: true, isCurrent: isCurrent)
    }

    private func prepareLazyActivity(
        _ preparation: RetainedLazyListAdoptionPreparation,
        includingOrdinary: Bool, isCurrent: () -> Bool
    ) -> Bool {
        guard isCurrent(), canConstruct, let ledger else { return false }
        // A raw/manual build that later gains a descriptor scope has no native
        // facts for its unmarked records. Reject before any suspension or write;
        // ordinary nil-route prepare/commit remains a separate supported path.
        guard candidates.values.allSatisfy({ $0.lazyProposal != nil || $0.descriptorProposal != nil }),
            candidateAnchors.values.allSatisfy({ $0.lazyGroup != nil || $0.descriptorGroup != nil })
        else { return false }
        let expected = Set(preparation.expectedExisting.map { ObjectIdentifier($0.receipt) })
        let expectedDescriptor = Set(preparation.expectedOrdinaryContributions.map { ObjectIdentifier($0.receipt) })
        let oldSessions = Array(ledger.sessions.values)
        let oldAnchors = Array(ledger.anchors.values)
        var lazySessions: [PresentationDismissSession] = []
        var lazyAnchors: [PresentationActivityAnchor] = []
        var descriptorSessions: [PresentationDismissSession] = []
        var descriptorAnchors: [PresentationActivityAnchor] = []
        for session in oldSessions {
            if let activity = session.lazyActivity {
                if expected.contains(ObjectIdentifier(activity.contribution)) { lazySessions.append(session) }
            } else if let activity = session.descriptorActivity {
                if expectedDescriptor.contains(ObjectIdentifier(activity.contribution)) {
                    descriptorSessions.append(session)
                }
            } else if includingOrdinary {
                guard isCurrent(), canConstruct else { return false }
                let covered = includes(session.owner.identity, isCurrent: isCurrent)
                guard isCurrent(), canConstruct else { return false }
                if covered { return false }
            }
        }
        for anchor in oldAnchors {
            if let activity = anchor.lazyActivity {
                if expected.contains(ObjectIdentifier(activity.contribution)) { lazyAnchors.append(anchor) }
            } else if let activity = anchor.descriptorActivity {
                if expectedDescriptor.contains(ObjectIdentifier(activity.contribution)) {
                    descriptorAnchors.append(anchor)
                }
            } else if anchor.lazyGroup == nil, anchor.descriptorGroup == nil, includingOrdinary {
                guard isCurrent(), canConstruct else { return false }
                let covered = anchor === boundary || includes(anchor.owner.identity, isCurrent: isCurrent)
                guard isCurrent(), canConstruct else { return false }
                if covered { return false }
            }
        }
        guard isCurrent(), canConstruct else { return false }
        if includingOrdinary {
            guard
                alerts.prepareLazyActivity(
                    preparation, includes: { self.includes($0, isCurrent: isCurrent) },
                    isCurrent: { isCurrent() && self.canConstruct })
            else { return false }
        } else {
            guard alerts.prepareLazyActivity(preparation) else { return false }
        }
        guard isCurrent(), canConstruct else { return false }
        lazyPreparation = preparation
        pinnedLazySessions = lazySessions
        pinnedLazyAnchors = lazyAnchors
        pinnedDescriptorSessions = descriptorSessions
        pinnedDescriptorAnchors = descriptorAnchors
        // Native contributions retain their old authority until native writes
        // revoke their exact receipt. Preparation alone changes none of them.
        phase = .prepared
        return true
    }

    /// Called only after State adoption and before any observer/payload cleanup.
    func commit() {
        guard lazyPreparation == nil, phase == .prepared, let ledger, !ledger.isClosed,
            ledger.currentBuild === self
        else { return }
        var descriptorActivities: [ObjectIdentifier: DescriptorPresentationActivity] = [:]
        var descriptorAnchorActivities: [ObjectIdentifier: DescriptorPresentationActivity] = [:]
        for (key, candidate) in candidates {
            if let activity = candidate.descriptorProposal?.acceptedForOrdinaryAdoption() {
                descriptorActivities[key] = activity
            }
        }
        for (key, anchor) in candidateAnchors {
            if let activity = descriptorAnchorProposals[ObjectIdentifier(anchor)]?.acceptedForOrdinaryAdoption() {
                descriptorAnchorActivities[key] = activity
            }
        }
        // Native metadata acceptance accompanies ordinary adoption without
        // changing its whole-build selection or choosing the composite route.
        let selected = candidates.filter {
            $0.value.materializedConfiguration != nil && $0.value.lazyProposal == nil
                && ($0.value.descriptorProposal == nil || descriptorActivities[$0.key] != nil)
        }
        let selectedAnchors = candidateAnchors.filter {
            $0.value.isMaterialized && $0.value.lazyGroup == nil
                && ($0.value.descriptorGroup == nil || descriptorAnchorActivities[$0.key] != nil)
        }
        for session in suspendedSessions {
            if let configuration = session.configuration { displacedConfigurations.append(configuration) }
        }
        for session in suspendedSessions {
            ledger.sessions.removeValue(forKey: ObjectIdentifier(session.owner))
            session.phase = .retired
            session.configuration = nil
        }
        for anchor in suspendedAnchors {
            ledger.anchors.removeValue(forKey: ObjectIdentifier(anchor.owner))
            anchor.phase = .retired
        }
        for (key, candidate) in selected {
            candidate.session.configuration = candidate.materializedConfiguration
            candidate.session.lazyActivity = nil
            candidate.session.descriptorActivity = descriptorActivities[key]
            ledger.sessions[key] = candidate.session
        }
        for (key, anchor) in selectedAnchors {
            anchor.descriptorActivity = descriptorAnchorActivities[key]
            ledger.anchors[key] = anchor
        }
        alerts.commit()
        // All membership/configuration is installed before admitting any copy.
        for (key, candidate) in candidates {
            if selected[key]?.receipt === candidate.receipt {
                candidate.receipt.isAccepted = true
                candidate.session.phase = .active
            } else {
                candidate.receipt.isDiscarded = true
            }
        }
        for (key, anchor) in candidateAnchors {
            anchor.phase = selectedAnchors[key] === anchor ? .active : .retired
        }
        phase = .committed
    }

    /// Only native accepted footprints may publish a lazy candidate. An
    /// unchanged receipt preserves the old declaration, never a new proposal.
    func commitLazyActivity(_ selection: LazyListStateAdoptionSelection) {
        guard phase == .prepared, let preparation = lazyPreparation,
            preparation.attempt === selection.attempt,
            let ledger, !ledger.isClosed, ledger.currentBuild === self
        else { return }
        var selected: [ObjectIdentifier: (candidate: Candidate, activity: PresentationAcceptedActivity)] = [:]
        var selectedAnchors:
            [ObjectIdentifier: (anchor: PresentationActivityAnchor, activity: PresentationAcceptedActivity)] = [:]
        for (key, candidate) in candidates {
            guard !candidate.receipt.isDiscarded, candidate.materializedConfiguration != nil else { continue }
            let activity: PresentationAcceptedActivity
            if let proposal = candidate.lazyProposal {
                guard proposal.isProposed(in: preparation), let accepted = proposal.accepted(in: selection) else {
                    continue
                }
                activity = .lazy(accepted)
            } else if let proposal = candidate.descriptorProposal {
                guard proposal.isProposed(in: preparation), let accepted = proposal.accepted(in: selection) else {
                    continue
                }
                activity = .descriptor(accepted)
            } else {
                continue
            }
            guard candidate.session.owner.isLive else { continue }
            if let previous = ledger.sessions[key] {
                guard
                    activity.permitsReplacing(
                        lazyActivity: previous.lazyActivity, descriptorActivity: previous.descriptorActivity,
                        in: selection)
                else { continue }
            }
            selected[key] = (candidate, activity)
        }
        for (key, anchor) in candidateAnchors {
            guard anchor.isMaterialized else { continue }
            let activity: PresentationAcceptedActivity
            if let proposal = lazyAnchorProposals[ObjectIdentifier(anchor)] {
                guard proposal.isProposed(in: preparation), let accepted = proposal.accepted(in: selection) else {
                    continue
                }
                activity = .lazy(accepted)
            } else if let proposal = descriptorAnchorProposals[ObjectIdentifier(anchor)] {
                guard proposal.isProposed(in: preparation), let accepted = proposal.accepted(in: selection) else {
                    continue
                }
                activity = .descriptor(accepted)
            } else {
                continue
            }
            guard anchor.owner.isLive else { continue }
            if let previous = ledger.anchors[key] {
                guard
                    activity.permitsReplacing(
                        lazyActivity: previous.lazyActivity, descriptorActivity: previous.descriptorActivity,
                        in: selection)
                else { continue }
            }
            selectedAnchors[key] = (anchor, activity)
        }
        guard !ledger.isClosed, ledger.currentBuild === self else { return }

        let previousSessions = Array(ledger.sessions.values)
        let previousAnchors = Array(ledger.anchors.values)
        for session in previousSessions {
            let retiresLazy = session.lazyActivity.map { selection.retiredGroups.contains(ObjectIdentifier($0.group)) }
            let retiresDescriptor = session.descriptorActivity.map {
                selection.retiredOrdinaryGroups.contains(ObjectIdentifier($0.group))
            }
            guard retiresLazy == true || retiresDescriptor == true else { continue }
            if retiresLazy == true { pinnedLazySessions.append(session) }
            if retiresDescriptor == true { pinnedDescriptorSessions.append(session) }
            if let configuration = session.configuration { displacedConfigurations.append(configuration) }
            let key = ObjectIdentifier(session.owner)
            if ledger.sessions[key] === session { ledger.sessions.removeValue(forKey: key) }
            session.phase = .retired
            session.configuration = nil
        }
        for anchor in previousAnchors {
            let retiresLazy = anchor.lazyActivity.map { selection.retiredGroups.contains(ObjectIdentifier($0.group)) }
            let retiresDescriptor = anchor.descriptorActivity.map {
                selection.retiredOrdinaryGroups.contains(ObjectIdentifier($0.group))
            }
            guard retiresLazy == true || retiresDescriptor == true else { continue }
            if retiresLazy == true { pinnedLazyAnchors.append(anchor) }
            if retiresDescriptor == true { pinnedDescriptorAnchors.append(anchor) }
            let key = ObjectIdentifier(anchor.owner)
            if ledger.anchors[key] === anchor { ledger.anchors.removeValue(forKey: key) }
            anchor.phase = .retired
        }
        for (key, record) in selected {
            if let previous = ledger.sessions[key], previous !== record.candidate.session {
                if previous.lazyActivity != nil { pinnedLazySessions.append(previous) }
                if previous.descriptorActivity != nil { pinnedDescriptorSessions.append(previous) }
                if let configuration = previous.configuration { displacedConfigurations.append(configuration) }
                previous.phase = .retired
                previous.configuration = nil
            }
            if let configuration = record.candidate.session.configuration {
                displacedConfigurations.append(configuration)
            }
            record.candidate.session.configuration = record.candidate.materializedConfiguration
            record.candidate.session.lazyActivity = record.activity.lazyActivity
            record.candidate.session.descriptorActivity = record.activity.descriptorActivity
            record.candidate.receipt.lazyActivity = record.activity.lazyActivity
            ledger.sessions[key] = record.candidate.session
        }
        for (key, record) in selectedAnchors {
            if let previous = ledger.anchors[key], previous !== record.anchor {
                if previous.lazyActivity != nil { pinnedLazyAnchors.append(previous) }
                if previous.descriptorActivity != nil { pinnedDescriptorAnchors.append(previous) }
                previous.phase = .retired
            }
            record.anchor.lazyActivity = record.activity.lazyActivity
            record.anchor.descriptorActivity = record.activity.descriptorActivity
            ledger.anchors[key] = record.anchor
        }
        alerts.commitLazyActivity(selection)
        guard !ledger.isClosed, ledger.currentBuild === self else { return }
        // Publish every chosen configuration before admitting any new handle.
        for (key, candidate) in candidates where candidate.lazyProposal != nil || candidate.descriptorProposal != nil {
            if selected[key]?.candidate.receipt === candidate.receipt {
                candidate.receipt.isAccepted = true
                candidate.session.phase = .active
            } else {
                candidate.receipt.isDiscarded = true
            }
        }
        for (key, anchor) in candidateAnchors where anchor.lazyGroup != nil || anchor.descriptorGroup != nil {
            anchor.phase = selectedAnchors[key]?.anchor === anchor ? .active : .retired
        }
        phase = .committed
    }

    /// Before State abort releases provisional payloads, restore admission to
    /// the still-accepted tree. A closed coordinator is never reopened.
    func abandon() {
        guard phase == .constructing || phase == .prepared else { return }
        alerts.abandon()
        for candidate in candidates.values { candidate.receipt.isDiscarded = true }
        for anchor in candidateAnchors.values { anchor.phase = .retired }
        if let ledger, !ledger.isClosed, ledger.currentBuild === self, phase == .prepared {
            let suspension = PresentationActivityPhase.suspended(ObjectIdentifier(self))
            for session in suspendedSessions where session.phase == suspension && ledger.admits(session) {
                session.phase = .active
            }
            for anchor in suspendedAnchors where anchor.phase == suspension && ledger.admits(anchor) {
                anchor.phase = .active
            }
        }
        phase = .abandoned
    }

    fileprivate func closeAdmissions() {
        alerts.closeAdmissions()
        for candidate in candidates.values {
            candidate.receipt.isDiscarded = true
            candidate.session.phase = .retired
        }
        for anchor in candidateAnchors.values { anchor.phase = .retired }
        for session in suspendedSessions { session.phase = .retired }
        for anchor in suspendedAnchors { anchor.phase = .retired }
        for session in pinnedLazySessions { session.phase = .retired }
        for anchor in pinnedLazyAnchors { anchor.phase = .retired }
        for session in pinnedDescriptorSessions { session.phase = .retired }
        for anchor in pinnedDescriptorAnchors { anchor.phase = .retired }
    }

    fileprivate func releaseClosedPayloads() {
        alerts.finish()
        releasePayloadCollections(clearingSessions: true)
    }

    func finish() {
        guard phase != .finished else { return }
        phase = .finished
        if ledger?.currentBuild === self { ledger?.currentBuild = nil }
        alerts.finish()
        // Remove publication ownership before any last capture can reenter.
        releasePayloadCollections(clearingSessions: false)
    }

    private func releasePayloadCollections(clearingSessions: Bool) {
        let outgoing = (
            candidates: candidates, anchors: candidateAnchors, discarded: discardedCandidates,
            displaced: displacedConfigurations, sessions: suspendedSessions, suspendedAnchors: suspendedAnchors,
            lazySessions: pinnedLazySessions, lazyAnchors: pinnedLazyAnchors,
            descriptorSessions: pinnedDescriptorSessions, descriptorAnchors: pinnedDescriptorAnchors,
            proposals: lazyAnchorProposals, descriptorProposals: descriptorAnchorProposals,
            discardedAnchors: discardedAnchors, preparation: lazyPreparation
        )
        candidates.removeAll()
        candidateAnchors.removeAll()
        discardedCandidates.removeAll()
        displacedConfigurations.removeAll()
        suspendedSessions.removeAll()
        suspendedAnchors.removeAll()
        pinnedLazySessions.removeAll()
        pinnedLazyAnchors.removeAll()
        pinnedDescriptorSessions.removeAll()
        pinnedDescriptorAnchors.removeAll()
        lazyAnchorProposals.removeAll()
        descriptorAnchorProposals.removeAll()
        discardedAnchors.removeAll()
        lazyPreparation = nil
        if clearingSessions {
            for candidate in outgoing.candidates.values { candidate.session.clearConfiguration() }
            for session in outgoing.sessions { session.clearConfiguration() }
            for session in outgoing.lazySessions { session.clearConfiguration() }
            for session in outgoing.descriptorSessions { session.clearConfiguration() }
        }
        // Publish empty bookkeeping before any captured application value dies.
        withExtendedLifetime(outgoing) {}
    }

    private func includes(_ identity: RetainedViewIdentity) -> Bool {
        includes(identity, isCurrent: { self.canConstruct })
    }

    private func includes(_ identity: RetainedViewIdentity, isCurrent: () -> Bool) -> Bool {
        guard isCurrent(), canConstruct else { return false }
        guard let prefix else { return true }
        return identity.checkedHasPrefix(prefix, isCurrent: { isCurrent() && self.canConstruct }) == true
    }
}
