import SwiftWindowsCore

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
    private var isDismissing = false

    init(ledger: PresentationActivityLedger, owner: StateMountOwner) {
        self.ledger = ledger
        self.owner = owner
    }

    func perform(interactively: Bool) {
        guard phase == .active, !isDismissing, owner.isLive, ledger?.admits(self) == true else { return }
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
        phase == .active && owner.isLive && self.configuration === configuration
            && ledger?.admits(self) == true
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

    init(session: PresentationDismissSession? = nil) {
        self.session = session
    }

    func perform(interactively: Bool) {
        guard isAccepted, !isDiscarded else { return }
        session?.perform(interactively: interactively)
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

    fileprivate init(
        ledger: PresentationActivityLedger?, owner: StateMountOwner, contentPrefix: RetainedViewIdentity
    ) {
        self.ledger = ledger
        self.owner = owner
        self.contentPrefix = contentPrefix
    }

    static func unavailable(owner: StateMountOwner, contentPrefix: RetainedViewIdentity) -> PresentationActivityAnchor {
        let anchor = PresentationActivityAnchor(ledger: nil, owner: owner, contentPrefix: contentPrefix)
        anchor.phase = .retired
        return anchor
    }

    var isActive: Bool {
        phase == .active && owner.isLive && ledger?.admits(self) == true
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

    fileprivate func materialize(
        _ receipt: PresentationDeclarationReceipt,
        preparingFocus: @escaping PresentationDismissConfiguration.FocusPreparation
    ) {
        guard canConstruct, let owner = receipt.session?.owner else { return }
        let key = ObjectIdentifier(owner)
        guard var candidate = candidates[key], candidate.receipt === receipt, !receipt.isDiscarded else { return }
        if let previous = candidate.materializedConfiguration { displacedConfigurations.append(previous) }
        candidate.materializedConfiguration = candidate.configuration.materialized(preparingFocus: preparingFocus)
        candidates[key] = candidate
    }

    func materialize(_ anchor: PresentationActivityAnchor) {
        guard canConstruct, candidateAnchors[ObjectIdentifier(anchor.owner)] === anchor else { return }
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
            let matches = candidate.session.owner.identity.segments.starts(with: prefix.segments)
            guard isCurrent(), canConstruct else { return }
            if matches { removedRecords.append(key) }
        }
        for (key, anchor) in readers {
            let matches = anchor.owner.identity.segments.starts(with: prefix.segments)
            guard isCurrent(), canConstruct else { return }
            if matches { removedReaders.append(key) }
        }
        for key in removedRecords {
            if let candidate = candidates.removeValue(forKey: key) {
                candidate.receipt.isDiscarded = true
                discardedCandidates.append(candidate)
            }
        }
        for key in removedReaders { candidateAnchors.removeValue(forKey: key)?.phase = .retired }
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
            let covered = includes(session.owner.identity)
            guard isCurrent(), canConstruct else { return false }
            if covered { coveredSessions.append(session) }
        }
        for anchor in oldAnchors {
            let covered = anchor === boundary || includes(anchor.owner.identity)
            guard isCurrent(), canConstruct else { return false }
            if covered { coveredAnchors.append(anchor) }
        }
        guard isCurrent(), canConstruct else { return false }
        guard alerts.prepare(includes: includes, isCurrent: { isCurrent() && self.canConstruct }) else { return false }
        suspendedSessions = coveredSessions
        suspendedAnchors = coveredAnchors
        let suspension = PresentationActivityPhase.suspended(ObjectIdentifier(self))
        for session in coveredSessions { session.phase = suspension }
        for anchor in coveredAnchors { anchor.phase = suspension }
        phase = .prepared
        return true
    }

    /// Called only after State adoption and before any observer/payload cleanup.
    func commit() {
        guard phase == .prepared, let ledger, !ledger.isClosed, ledger.currentBuild === self else { return }
        let selected = candidates.filter { $0.value.materializedConfiguration != nil }
        let selectedAnchors = candidateAnchors.filter { $0.value.isMaterialized }
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
            ledger.sessions[key] = candidate.session
        }
        for (key, anchor) in selectedAnchors { ledger.anchors[key] = anchor }
        alerts.commit()
        // All membership/configuration is installed before admitting any copy.
        for candidate in candidates.values {
            if candidate.materializedConfiguration != nil {
                candidate.receipt.isAccepted = true
                candidate.session.phase = .active
            } else {
                candidate.receipt.isDiscarded = true
            }
        }
        for anchor in candidateAnchors.values { anchor.phase = anchor.isMaterialized ? .active : .retired }
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
            displaced: displacedConfigurations, sessions: suspendedSessions, suspendedAnchors: suspendedAnchors
        )
        candidates.removeAll()
        candidateAnchors.removeAll()
        discardedCandidates.removeAll()
        displacedConfigurations.removeAll()
        suspendedSessions.removeAll()
        suspendedAnchors.removeAll()
        if clearingSessions {
            for candidate in outgoing.candidates.values { candidate.session.clearConfiguration() }
            for session in outgoing.sessions { session.clearConfiguration() }
        }
        // Publish empty bookkeeping before any captured application value dies.
        withExtendedLifetime(outgoing) {}
    }

    private func includes(_ identity: RetainedViewIdentity) -> Bool {
        guard let prefix else { return true }
        return identity.segments.starts(with: prefix.segments)
    }
}
