import SwiftWindowsCore
import SwiftWindowsUI

@MainActor
final class RetainedAlertConfiguration {
    typealias Admission = @MainActor () -> Bool
    let itemIdentity: RetainedViewIdentity.Key?
    let payload: Any?
    let validate: @MainActor (Admission) -> Bool
    let reset: @MainActor () -> Void
    let invalidate: @MainActor () -> Void

    init(
        itemIdentity: RetainedViewIdentity.Key? = nil, payload: Any? = nil,
        validate: @escaping @MainActor (Admission) -> Bool,
        reset: @escaping @MainActor () -> Void, invalidate: @escaping @MainActor () -> Void
    ) {
        self.itemIdentity = itemIdentity
        self.payload = payload
        self.validate = validate
        self.reset = reset
        self.invalidate = invalidate
    }
}

private enum RetainedAlertPhase: Equatable {
    case provisional
    case active
    case suspended(ObjectIdentifier)
    case retired
}

private final class RetainedAlertGeneration {}
private final class RetainedAlertFocusOwner {}
private enum RetainedAlertHostMarkerKey {}
private enum RetainedAlertActionMarkerKey {}
private final class RetainedAlertKeyMarker {}

@MainActor
final class RetainedAlertActionScope {
    let declaration: RetainedAlertDeclaration
    private let presentationDepth: Int

    init(declaration: RetainedAlertDeclaration, context: ViewBuildContext) {
        self.declaration = declaration
        presentationDepth = Self.depth(context.retainedViewIdentity)
    }

    func contains(_ context: ViewBuildContext) -> Bool {
        Self.depth(context.retainedViewIdentity) == presentationDepth
    }

    private static func depth(_ identity: RetainedViewIdentity) -> Int {
        identity.segments.reduce(0) { count, segment in
            if case .role(.presentation) = segment { return count + 1 }
            return count
        }
    }
}

/// No action, binding, runtime, or node is retained by an escaped receipt.
@MainActor
private final class RetainedAlertReceipt {
    weak var slot: RetainedAlertSlot?
    weak var runtime: RetainedViewRuntime?
    weak var constructionNode: ViewNode?
    var accepted = false
    var discarded = false

    init(slot: RetainedAlertSlot? = nil) { self.slot = slot }

    var isCurrent: Bool {
        accepted && !discarded && slot?.isActive == true && slot?.receipt === self
    }

    func host() -> ViewNode? {
        guard let runtime else { return nil }
        return find(in: runtime.root) { node in
            (node.retainedPreferenceValues[ObjectIdentifier(RetainedAlertHostMarkerKey.self)]
                as? RetainedAlertHostMarker)?.receipt === self
        }
    }

    func find(in root: ViewNode, matching: (ViewNode) -> Bool) -> ViewNode? {
        var work = [root]
        var visited: Set<ObjectIdentifier> = []
        while let node = work.popLast() {
            guard visited.insert(ObjectIdentifier(node)).inserted else { continue }
            if matching(node) { return node }
            work.append(contentsOf: node.children.reversed())
        }
        return nil
    }
}

@MainActor
private final class RetainedAlertHostMarker {
    let receipt: RetainedAlertReceipt
    // Raw Component clients have no State coordinator. The actual host node
    // owns their session; receipts still keep only a weak reference to it.
    let rawOwner: RetainedAlertSlot?

    init(receipt: RetainedAlertReceipt, rawOwner: RetainedAlertSlot?) {
        self.receipt = receipt
        self.rawOwner = rawOwner
    }
}

@MainActor
final class RetainedAlertActionReceipt {
    fileprivate let declaration: RetainedAlertReceipt

    fileprivate init(declaration: RetainedAlertReceipt) { self.declaration = declaration }

    func install(on node: ViewNode) {
        node.retainedPreferenceValues[ObjectIdentifier(RetainedAlertActionMarkerKey.self)] = self
    }

    fileprivate func node(in host: ViewNode) -> ViewNode? {
        declaration.find(in: host) {
            ($0.retainedPreferenceValues[ObjectIdentifier(RetainedAlertActionMarkerKey.self)]
                as? RetainedAlertActionReceipt) === self
        }
    }

    func activate() { declaration.slot?.perform(declaration: declaration, action: self) }
}

@MainActor
private struct RetainedAlertAction {
    let receipt: RetainedAlertActionReceipt
    let role: ButtonRole?
    let invoke: @MainActor () -> Void
}

@MainActor
private final class RetainedAlertSession {
    let generation = RetainedAlertGeneration()
    let itemIdentity: RetainedViewIdentity.Key?
    let payload: Any?
    var configuration: RetainedAlertConfiguration?
    var actions: [ObjectIdentifier: RetainedAlertAction] = [:]
    var retired = false
    var isPerforming = false
    var didCaptureFocus = false
    weak var previousFocus: ViewNode?
    weak var underlyingModal: ViewNode?
    var resetTicket: RetainedAlertRemovalTicket?

    init(configuration: RetainedAlertConfiguration) {
        itemIdentity = configuration.itemIdentity
        payload = configuration.payload
    }
}

@MainActor
final class RetainedAlertSlot {
    private weak var ledger: PresentationActivityLedger?
    let owner: StateMountOwner?
    private let raw: Bool
    fileprivate let focusOwner = RetainedAlertFocusOwner()
    fileprivate var phase = RetainedAlertPhase.provisional
    fileprivate var receipt: RetainedAlertReceipt?
    fileprivate var session: RetainedAlertSession?
    fileprivate var restoration: RetainedAlertRemovalTicket?

    init(ledger: PresentationActivityLedger?, owner: StateMountOwner?) {
        self.ledger = ledger
        self.owner = owner
        raw = owner == nil
    }

    fileprivate var isActive: Bool {
        guard phase == .active else { return false }
        if raw { return true }
        guard let owner, owner.isLive, let ledger, !ledger.isClosed else { return false }
        return ledger.alertSlots[ObjectIdentifier(owner)] === self
    }

    fileprivate func admits(_ session: RetainedAlertSession) -> Bool {
        isActive && self.session === session && !session.retired
    }

    fileprivate func perform(declaration: RetainedAlertReceipt, action: RetainedAlertActionReceipt?) {
        guard declaration.isCurrent, let session, !session.isPerforming,
            let configuration = session.configuration, let runtime = declaration.runtime,
            runtime.presentationActionsAreAvailable
        else { return }
        let entry = action.flatMap { session.actions[ObjectIdentifier($0)] }
        guard action == nil || entry?.receipt === action else { return }
        session.isPerforming = true
        var admittedTicket: RetainedAlertRemovalTicket?
        defer {
            session.isPerforming = false
            admittedTicket?.finishFlight()
        }
        let startingAdmission: RetainedAlertConfiguration.Admission = { [self] in
            declaration.isCurrent && admits(session) && runtime.presentationActionsAreAvailable
        }
        guard let host = declaration.host(), let overlay = host.children.dropFirst().first,
            let target = action?.node(in: host) ?? (action == nil ? overlay : nil),
            runtime.permitsPresentationAction(on: target, within: overlay), startingAdmission(),
            declaration.host() === host,
            configuration.validate(startingAdmission), startingAdmission(),
            runtime.permitsPresentationAction(on: target, within: overlay), startingAdmission(),
            declaration.host() === host
        else { return }

        // The flight pins the admitted action and reset. Ordinary authored
        // State writes can replace its materialization, but not its generation.
        // The action can also dismiss itself. Arm removal before invoking it
        // so that accepted absence still owns restoration, without a second reset.
        let ticket = RetainedAlertRemovalTicket(slot: self, session: session)
        admittedTicket = ticket
        session.resetTicket = ticket
        entry?.invoke()
        let flightAdmission: RetainedAlertConfiguration.Admission = { [self] in
            admits(session) && runtime.presentationActionsAreAvailable
        }
        if flightAdmission(), configuration.validate(flightAdmission), flightAdmission() {
            configuration.reset()
        }
        // A plain reference replacement still needs this invalidation even
        // when the old reset was rejected. The closed host already ignores it.
        configuration.invalidate()
        if flightAdmission(), configuration.validate(flightAdmission), flightAdmission() {
            // A custom setter may refuse dismissal. Do not strand that alert;
            // another separate dispatch may try again after this stack returns.
            session.resetTicket?.cancelled = true
            session.resetTicket = nil
        }
    }

    fileprivate func retire() {
        phase = .retired
        receipt?.discarded = true
        session?.retired = true
        session?.resetTicket?.cancelled = true
        restoration?.cancelled = true
    }

    func closeAdmissions() { retire() }
}

@MainActor
private final class RetainedAlertRemovalTicket {
    private weak var slot: RetainedAlertSlot?
    private let generation: RetainedAlertGeneration
    private weak var previousFocus: ViewNode?
    private weak var underlyingModal: ViewNode?
    var cancelled = false
    private var acceptedAbsence = false
    private var flightFinished = false
    private var enqueued = false
    private var expectedFocusRevision: UInt64 = 0

    init(slot: RetainedAlertSlot, session: RetainedAlertSession) {
        self.slot = slot
        generation = session.generation
        previousFocus = session.previousFocus
        underlyingModal = session.underlyingModal
    }

    func acceptAbsence(runtime: RetainedViewRuntime?) {
        guard !cancelled, let runtime else { return }
        acceptedAbsence = true
        expectedFocusRevision = runtime.presentationFocusRevision
    }

    var isCurrent: Bool {
        !cancelled && acceptedAbsence && slot?.isActive == true
            && slot?.session == nil && slot?.restoration === self
    }

    func finishFlight() {
        flightFinished = true
        enqueue()
    }

    func enqueue() {
        guard !enqueued, flightFinished, isCurrent, let slot, let runtime = slot.receipt?.runtime else { return }
        enqueued = true
        let request = RetainedPresentationFocusRequest(
            owner: slot.focusOwner, preferred: previousFocus, underlyingModal: underlyingModal,
            expectedFocusRevision: expectedFocusRevision,
            isCurrent: { [weak self] in self?.isCurrent == true },
            resolveBase: { [weak slot] in slot?.receipt?.host()?.children.first },
            didFinish: { [weak self] in self?.cancelled = true }
        )
        runtime.schedulePresentationFocusRestoration(request)
    }
}

@MainActor
private final class RetainedAlertCandidate {
    let slot: RetainedAlertSlot
    let receipt: RetainedAlertReceipt
    let session: RetainedAlertSession?
    let configuration: RetainedAlertConfiguration?
    var actions: [ObjectIdentifier: RetainedAlertAction] = [:]
    var materialized = false
    weak var previousFocus: ViewNode?
    weak var underlyingModal: ViewNode?

    init(slot: RetainedAlertSlot, session: RetainedAlertSession?, configuration: RetainedAlertConfiguration?) {
        self.slot = slot
        receipt = RetainedAlertReceipt(slot: slot)
        self.session = session
        self.configuration = configuration
    }
}

@MainActor
final class RetainedAlertDeclaration {
    private let receipt: RetainedAlertReceipt
    private weak var build: RetainedAlertActivityBuild?
    private var rawCandidate: RetainedAlertCandidate?

    fileprivate init(candidate: RetainedAlertCandidate, build: RetainedAlertActivityBuild?) {
        receipt = candidate.receipt
        self.build = build
        if build == nil { rawCandidate = candidate }
    }

    private init() {
        receipt = RetainedAlertReceipt()
        receipt.discarded = true
    }

    static func unavailable() -> RetainedAlertDeclaration { RetainedAlertDeclaration() }

    static func raw(configuration: RetainedAlertConfiguration?) -> RetainedAlertDeclaration {
        let slot = RetainedAlertSlot(ledger: nil, owner: nil)
        return RetainedAlertDeclaration(
            candidate: RetainedAlertCandidate(
                slot: slot, session: configuration.map(RetainedAlertSession.init), configuration: configuration),
            build: nil)
    }

    private var candidate: RetainedAlertCandidate? {
        rawCandidate ?? build?.candidate(for: receipt)
    }

    func presentationPayload<Value>(or proposed: Value?) -> Value? {
        (candidate?.session?.payload as? Value) ?? proposed
    }

    func presentationContext(_ context: ViewBuildContext) -> ViewBuildContext {
        let presentation = context.withViewIdentityRole(.presentation)
        guard let key = candidate?.session?.itemIdentity else { return presentation }
        return presentation.withViewIdentityPrefix([.keyed(key)])
    }

    func registerButton(role: ButtonRole?, action: @escaping @MainActor () -> Void) -> RetainedAlertActionReceipt {
        let actionReceipt = RetainedAlertActionReceipt(declaration: receipt)
        if let candidate, !receipt.discarded {
            candidate.actions[ObjectIdentifier(actionReceipt)] = RetainedAlertAction(
                receipt: actionReceipt, role: role, invoke: action)
        }
        return actionReceipt
    }

    func materialize(on node: ViewNode, runtime: RetainedViewRuntime) {
        guard let candidate, !receipt.discarded else { return }
        receipt.runtime = runtime
        receipt.constructionNode = node
        candidate.materialized = true
        candidate.previousFocus = runtime.focusedNode
        candidate.underlyingModal = runtime.presentationModalSnapshot
        node.retainedPreferenceValues[ObjectIdentifier(RetainedAlertHostMarkerKey.self)] = RetainedAlertHostMarker(
            receipt: receipt, rawOwner: rawCandidate?.slot)
        if rawCandidate != nil {
            RetainedAlertActivityBuild.publish(candidate)
            rawCandidate = nil
        }
    }

    /// Layout resolves the marker copied to the actual retained host. It does
    /// not capture a discarded construction root or invoke arbitrary ID equality.
    func layoutHost() -> ViewNode? {
        if receipt.isCurrent { return receipt.host() }
        guard !receipt.discarded, let node = receipt.constructionNode, receipt.host() === node else { return nil }
        return node
    }

    func dismiss() { receipt.slot?.perform(declaration: receipt, action: nil) }

    func installEscape(on node: ViewNode) {
        let marker = RetainedAlertKeyMarker()
        // A nested alert keeps both wrappers. Each declaration has its own key
        // so the outer installation cannot erase the inner node's receipt.
        let key = ObjectIdentifier(receipt)
        node.retainedPreferenceValues[key] = marker
        let previous = node.onKeyDown
        let receipt = receipt
        node.onKeyDown = { event in
            guard receipt.isCurrent, let host = receipt.host(),
                let actual = receipt.find(
                    in: host,
                    matching: {
                        ($0.retainedPreferenceValues[key] as? RetainedAlertKeyMarker) === marker
                    })
            else { return }
            let modal = host.children.dropFirst().first
            var ancestor: ViewNode? = actual
            while let current = ancestor, !current.isModalPresentationScope { ancestor = current.parent }
            let ownsEscape = modal != nil && ancestor === modal
            previous?(event)
            if event.key == .escape, ownsEscape { receipt.slot?.perform(declaration: receipt, action: nil) }
        }
    }
}

/// Typed alert records participate in the existing activity build. They do not
/// create a second build scheduler or broaden the shorter sheet-dismiss policy.
@MainActor
final class RetainedAlertActivityBuild {
    private weak var ledger: PresentationActivityLedger?
    private var candidates: [ObjectIdentifier: RetainedAlertCandidate] = [:]
    private var covered: [RetainedAlertSlot] = []
    private var discarded: [RetainedAlertCandidate] = []
    private var displacedSessions: [RetainedAlertSession] = []
    private var displacedActions: [[ObjectIdentifier: RetainedAlertAction]] = []
    private var displacedConfigurations: [RetainedAlertConfiguration] = []
    private var completedRemovals: [RetainedAlertRemovalTicket] = []
    private var constructing = true
    private var prepared = false
    private var finished = false

    init(ledger: PresentationActivityLedger) { self.ledger = ledger }

    func stage(
        owner: StateMountOwner, configuration: RetainedAlertConfiguration?, isCurrent: () -> Bool
    ) -> RetainedAlertDeclaration {
        guard constructing, isCurrent(), let ledger, !ledger.isClosed else { return .unavailable() }
        let key = ObjectIdentifier(owner)
        let slot = ledger.alertSlots[key] ?? RetainedAlertSlot(ledger: ledger, owner: owner)
        let session: RetainedAlertSession?
        if let configuration {
            let existing = slot.session
            let matches = existing?.itemIdentity == configuration.itemIdentity
            guard constructing, isCurrent(), !ledger.isClosed else { return .unavailable() }
            session =
                matches && existing?.retired == false ? existing : RetainedAlertSession(configuration: configuration)
        } else {
            session = nil
        }
        let candidate = RetainedAlertCandidate(slot: slot, session: session, configuration: configuration)
        if let previous = candidates[key] {
            previous.receipt.discarded = true
            discarded.append(previous)
        }
        candidates[key] = candidate
        return RetainedAlertDeclaration(candidate: candidate, build: self)
    }

    fileprivate func candidate(for receipt: RetainedAlertReceipt) -> RetainedAlertCandidate? {
        guard constructing, let owner = receipt.slot?.owner,
            let candidate = candidates[ObjectIdentifier(owner)], candidate.receipt === receipt,
            ledger?.isClosed == false
        else { return nil }
        return candidate
    }

    func discardSubtree(at prefix: RetainedViewIdentity, isCurrent: () -> Bool) {
        let pending = Array(candidates)
        var keys: [ObjectIdentifier] = []
        for (key, candidate) in pending {
            let matches = candidate.slot.owner?.identity.segments.starts(with: prefix.segments) == true
            guard constructing, isCurrent(), ledger?.isClosed == false else { return }
            if matches { keys.append(key) }
        }
        for key in keys {
            if let candidate = candidates.removeValue(forKey: key) {
                candidate.receipt.discarded = true
                discarded.append(candidate)
            }
        }
    }

    func prepare(includes: (RetainedViewIdentity) -> Bool, isCurrent: () -> Bool) -> Bool {
        guard constructing, isCurrent(), let ledger, !ledger.isClosed else { return false }
        let slots = Array(ledger.alertSlots.values)
        var selected: [RetainedAlertSlot] = []
        for slot in slots {
            guard let owner = slot.owner else { continue }
            let matches = includes(owner.identity)
            guard constructing, isCurrent(), !ledger.isClosed else { return false }
            if matches { selected.append(slot) }
        }
        covered = selected
        for slot in selected { slot.phase = .suspended(ObjectIdentifier(self)) }
        constructing = false
        prepared = true
        return true
    }

    func commit() {
        guard prepared, let ledger, !ledger.isClosed else { return }
        for slot in covered {
            if let session = slot.session { displacedSessions.append(session) }
            let selected = slot.owner.flatMap { candidates[ObjectIdentifier($0)] }
            if selected?.materialized != true {
                slot.retire()
                if let owner = slot.owner { ledger.alertSlots.removeValue(forKey: ObjectIdentifier(owner)) }
            }
        }
        for (key, candidate) in candidates where candidate.materialized {
            let slot = candidate.slot
            let previous = slot.session
            if let oldConfiguration = previous?.configuration { displacedConfigurations.append(oldConfiguration) }
            if let oldActions = previous?.actions { displacedActions.append(oldActions) }
            if previous !== candidate.session {
                if let previous, let next = candidate.session, previous.didCaptureFocus {
                    // Replacing A by B does not make A's focused button or
                    // reconciled overlay B's underlying presentation.
                    next.previousFocus = previous.previousFocus
                    next.underlyingModal = previous.underlyingModal
                    next.didCaptureFocus = true
                }
                previous?.retired = true
                if candidate.session == nil, let ticket = previous?.resetTicket {
                    slot.restoration?.cancelled = true
                    slot.restoration = ticket
                    ticket.acceptAbsence(runtime: candidate.receipt.runtime)
                    completedRemovals.append(ticket)
                } else {
                    previous?.resetTicket?.cancelled = true
                    slot.restoration?.cancelled = true
                    slot.restoration = nil
                }
            }
            slot.receipt?.discarded = true
            Self.publish(candidate, admitsActions: false)
            ledger.alertSlots[key] = slot
        }
        for candidate in candidates.values where !candidate.materialized { candidate.receipt.discarded = true }
        // Every accepted configuration is installed before any receipt can
        // invoke one, including when distinct slots share application captures.
        for candidate in candidates.values where candidate.materialized {
            candidate.slot.phase = .active
            candidate.receipt.accepted = true
        }
        prepared = false
    }

    fileprivate static func publish(_ candidate: RetainedAlertCandidate, admitsActions: Bool = true) {
        let slot = candidate.slot
        slot.receipt = candidate.receipt
        slot.session = candidate.session
        if let session = candidate.session {
            session.configuration = candidate.configuration
            session.actions = candidate.actions
            if !session.didCaptureFocus {
                session.didCaptureFocus = true
                session.previousFocus = candidate.previousFocus
                session.underlyingModal = candidate.underlyingModal
            }
        }
        if admitsActions {
            slot.phase = .active
            candidate.receipt.accepted = true
        }
    }

    func abandon() {
        for candidate in candidates.values { candidate.receipt.discarded = true }
        if ledger?.isClosed == false, prepared {
            for slot in covered where slot.phase == .suspended(ObjectIdentifier(self)) {
                slot.phase = .active
            }
        }
        constructing = false
        prepared = false
    }

    func closeAdmissions() {
        for candidate in candidates.values {
            candidate.receipt.discarded = true
            candidate.slot.retire()
        }
        for slot in covered { slot.retire() }
        for ticket in completedRemovals { ticket.cancelled = true }
    }

    func finish() {
        guard !finished else { return }
        finished = true
        constructing = false
        prepared = false
        let tickets = completedRemovals
        // Detach all bookkeeping before any application capture is released;
        // a payload destructor may close the coordinator during this cleanup.
        let retained = (candidates, discarded, covered, displacedSessions, displacedActions, displacedConfigurations)
        completedRemovals = []
        candidates = [:]
        discarded = []
        covered = []
        displacedSessions = []
        displacedActions = []
        displacedConfigurations = []
        withExtendedLifetime(retained) {}
        for ticket in tickets { ticket.enqueue() }
    }
}
