import SwiftWindowsCore

/// Shared by declarations on one physical node, including a replacement made
/// by the action itself. It contains no authored payload and is never copied as
/// source configuration.
@MainActor
final class RetainedButtonActionFlight {
    var isInvoking = false
    var suspensions: Set<ObjectIdentifier> = []
}

/// Construction and adoption carry this native permission weakly. Keeping a
/// rejected source node alive cannot keep its construction operation alive.
@MainActor
final class RetainedButtonActionPermission {
    var isAvailable = true
    var isConstructing = false
    weak var enclosing: RetainedButtonActionPermission?
    let hasEnclosing: Bool
    private weak var candidate: RetainedLazyListRuntimeAdapter.Candidate?
    private var hasCandidate = false

    init(enclosing: RetainedButtonActionPermission? = nil) {
        self.enclosing = enclosing
        hasEnclosing = enclosing != nil
    }

    var isCurrent: Bool {
        isAvailable && (!hasEnclosing || enclosing?.isCurrent == true)
            && (!hasCandidate || candidate?.isCurrent == true)
    }

    func bindCandidate(_ candidate: RetainedLazyListRuntimeAdapter.Candidate) {
        guard !hasCandidate else {
            isAvailable = false
            return
        }
        hasCandidate = true
        self.candidate = candidate
    }
}

/// Owns a Button's action, not arbitrary effects in a modifier wrapping its
/// onActivate closure. A non-nil wrapper may delegate to the previous handler.
/// Declaration replacement, nil activation and physical departure retire the
/// Button payload without pretending that those outer effects are revocable.
@MainActor
final class RetainedButtonActionOwner {
    @MainActor
    private final class Payload {
        let action: (@MainActor () -> Void)?
        let completion: (@MainActor () -> Void)?

        init(action: (@MainActor () -> Void)?, completion: (@MainActor () -> Void)? = nil) {
            self.action = action
            self.completion = completion
        }
    }

    private var payload: Payload?
    private(set) weak var node: ViewNode?
    private(set) weak var constructionRuntime: RetainedViewRuntime?
    private let constructionLifetime: RetainedLazyListLogicalHostLifetime
    private weak var acceptedRuntime: RetainedViewRuntime?
    private weak var permission: RetainedButtonActionPermission?
    private weak var adoptionPermission: RetainedButtonActionPermission?
    private var hasAdoptionClaim = false
    private var requiresPermission = false
    private var isAccepted = false
    private(set) var isRetired = false
    private var permitsRepeat = true
    private var hasPublished = false
    private var hasEnteredPublication = false
    private var flight: RetainedButtonActionFlight
    private var deferredPayloadReleases = 0

    init(action: (() -> Void)?, node: ViewNode, runtime: RetainedViewRuntime) {
        if let action {
            payload = Payload(action: { @MainActor [action] in action() })
        } else {
            payload = Payload(action: nil)
        }
        self.node = node
        constructionRuntime = runtime
        constructionLifetime = runtime.lazyListLogicalHostLifetime
        flight = node.retainedButtonActionFlight
        runtime.buttonActionConstruction?.register(self)
    }

    var canBeAccepted: Bool {
        !isRetired && constructionLifetime.isOpen
            && (!requiresPermission || permission?.isCurrent == true)
            && (!hasAdoptionClaim || adoptionPermission?.isCurrent == true)
    }

    var isPending: Bool { requiresPermission && !isAccepted }

    var isUnacceptedConstructionSource: Bool {
        !isRetired && !isAccepted && !requiresPermission && !hasAdoptionClaim
    }

    func prepareCandidate(using permission: RetainedButtonActionPermission) {
        guard !isRetired, !isAccepted, !requiresPermission else { return }
        requiresPermission = true
        self.permission = permission
    }

    func belongs(to permission: RetainedButtonActionPermission) -> Bool {
        requiresPermission && self.permission === permission && !isAccepted
    }

    /// One pending source cannot be borrowed by a reentrant adoption. Its
    /// construction permission may outlive this claim, but an older adopter
    /// never receives cleanup authority over a newer accepted declaration.
    func claimAdoption(using permission: RetainedButtonActionPermission) -> Bool {
        guard canBeAccepted, !hasAdoptionClaim else { return false }
        hasAdoptionClaim = true
        adoptionPermission = permission
        isAccepted = false
        prepareCandidate(using: permission)
        return true
    }

    func isClaimed(by permission: RetainedButtonActionPermission) -> Bool {
        hasAdoptionClaim && adoptionPermission === permission && !isAccepted
    }

    func setCompletion(_ completion: @escaping @MainActor () -> Void) {
        guard !isRetired, let previous = payload else { return }
        payload = Payload(action: previous.action, completion: completion)
        // Stored access has ended before the outgoing completion can deinit.
        withExtendedLifetime(previous) {}
    }

    func transfer(to node: ViewNode) {
        self.node = node
        flight = node.retainedButtonActionFlight
        isAccepted = false
        hasPublished = false
        acceptedRuntime = nil
        hasEnteredPublication = node.retainedLazyListRuntime != nil
    }

    /// Native assignment is a lifetime observation, never action admission.
    func runtimeWillChange(from previous: RetainedViewRuntime?, to incoming: RetainedViewRuntime?) {
        if previous != nil, previous !== incoming { retire() }
        if incoming != nil { hasEnteredPublication = true }
    }

    func preparePublication() { hasEnteredPublication = true }

    func canAccept(on node: ViewNode, using permission: RetainedButtonActionPermission? = nil) -> Bool {
        guard canBeAccepted, self.node === node, node.buttonActionOwner === self else { return false }
        if hasAdoptionClaim {
            guard adoptionPermission === permission, permission?.isCurrent == true else { return false }
        } else if permission != nil {
            return false
        }
        if let runtime = node.retainedLazyListRuntime {
            return runtime.permitsRetainedActionInvocation && node.isRetainedLazyListAttached(in: runtime)
        }
        return !hasPublished
    }

    func accept(on node: ViewNode, using permission: RetainedButtonActionPermission? = nil) -> Bool {
        guard canAccept(on: node, using: permission) else { return false }
        if let runtime = node.retainedLazyListRuntime {
            acceptedRuntime = runtime
            hasPublished = true
        } else {
            hasEnteredPublication = false
        }
        isAccepted = true
        requiresPermission = false
        self.permission = nil
        hasAdoptionClaim = false
        adoptionPermission = nil
        return true
    }

    func acceptStandalonePublication(on node: ViewNode) {
        guard node.retainedLazyListRuntime != nil, !requiresPermission, !isRetired, !hasPublished else { return }
        _ = accept(on: node)
    }

    func retire() { isRetired = true }

    func retireIfInstalled(on node: ViewNode) {
        if self.node === node { retire() }
    }

    func retireForDeparture() {
        // Moving through detached construction wrappers has never published a
        // physical action. A first attachment interrupted by a callback has.
        if hasPublished || (hasEnteredPublication && node?.retainedLazyListRuntime != nil) { retire() }
    }

    func retireRepeat() { permitsRepeat = false }

    func deferPayloadRelease() { deferredPayloadReleases += 1 }

    func resumePayloadRelease() {
        precondition(deferredPayloadReleases > 0)
        deferredPayloadReleases -= 1
    }

    /// Call only after the entire cohort was marked. This separate helper pins
    /// the old value until its stored-property write has ended.
    @inline(never)
    func releaseRetiredPayload() {
        guard isRetired, deferredPayloadReleases == 0 else { return }
        let previous = payload
        payload = nil
        withExtendedLifetime(previous) {}
    }

    private var ownsCurrentPayload: Bool {
        guard !isRetired, !requiresPermission, let node, node.buttonActionOwner === self,
            node.onActivate != nil, flight.suspensions.isEmpty,
            constructionLifetime.isOpen
        else { return false }
        if hasPublished {
            guard let runtime = acceptedRuntime, runtime.permitsRetainedActionInvocation else { return false }
            return node.isRetainedLazyListAttached(in: runtime)
        }
        // Existing direct, idle Controls.button / Component construction stays
        // usable. Neither a runtime argument nor a half-finished attachment
        // turns an unaccepted candidate into a standalone action.
        return !hasEnteredPublication && node.retainedLazyListRuntime == nil
            && constructionRuntime?.buttonActionConstruction == nil
    }

    func invoke(repeating: Bool) {
        guard ownsCurrentPayload, !flight.isInvoking, !repeating || permitsRepeat else { return }
        let admittedFlight = flight
        admittedFlight.isInvoking = true
        invokePinnedPayload(using: admittedFlight)
        // The helper's payload and destructor have unwound. A new declaration
        // on the same physical node shared this closed gate throughout.
        admittedFlight.isInvoking = false
    }

    @inline(never)
    private func invokePinnedPayload(using admittedFlight: RetainedButtonActionFlight) {
        guard let invoked = payload else { return }
        invoked.action?()
        if flight === admittedFlight, payload === invoked, ownsCurrentPayload {
            invoked.completion?()
        }
        withExtendedLifetime(invoked) {}
    }
}

/// One exact runtime's synchronous construction frame. Nested builds restore
/// their predecessor; they never consume another frame's pending controls.
@MainActor
final class RetainedButtonActionConstruction {
    @MainActor
    private struct Pending {
        weak var owner: RetainedButtonActionOwner?
    }

    let permission: RetainedButtonActionPermission
    private weak var runtime: RetainedViewRuntime?
    private let previous: RetainedButtonActionConstruction?
    private var pending: [Pending] = []
    private var didLeave = false
    private var didFinish = false

    isolated deinit { finish() }

    init(runtime: RetainedViewRuntime?) {
        self.runtime = runtime
        previous = runtime?.buttonActionConstruction
        permission = RetainedButtonActionPermission(enclosing: previous?.permission)
        permission.isConstructing = true
        runtime?.buttonActionConstruction = self
    }

    func register(_ owner: RetainedButtonActionOwner) {
        // A returned tree may contain an already accepted row or a source
        // claimed by another operation. Even a closed cleanup frame owns none
        // of those payloads and must not retire them merely by observing them.
        guard owner.isUnacceptedConstructionSource || owner.belongs(to: permission) else { return }
        guard !didFinish, permission.isCurrent, !owner.isRetired else {
            owner.retire()
            owner.releaseRetiredPayload()
            return
        }
        owner.prepareCandidate(using: permission)
        if owner.belongs(to: permission) { pending.append(Pending(owner: owner)) }
    }

    func registerSources(in roots: [ViewNode]) {
        for node in RetainedButtonActionTree.nodes(in: roots) {
            if let owner = node.buttonActionOwner { register(owner) }
        }
    }

    func leave() {
        guard !didLeave else { return }
        didLeave = true
        permission.isConstructing = false
        if runtime?.buttonActionConstruction === self {
            var predecessor = previous
            while predecessor?.didLeave == true { predecessor = predecessor?.previous }
            runtime?.buttonActionConstruction = predecessor
        }
    }

    /// A yielded lazy Candidate keeps this exact native permission. Everything
    /// not selected for that Candidate is retired before its source captures die.
    func keepPendingSources(in roots: [ViewNode]) {
        let selected = Set(
            RetainedButtonActionTree.nodes(in: roots).compactMap { $0.buttonActionOwner }.map(ObjectIdentifier.init))
        let rejected = pending.compactMap(\.owner).filter {
            $0.belongs(to: permission) && !selected.contains(ObjectIdentifier($0))
        }
        for owner in rejected { owner.retire() }
        releaseDuringClosedConstruction(rejected)
        leave()
    }

    func finish() {
        guard !didFinish else { return }
        didFinish = true
        permission.isAvailable = false
        let rejected = pending.compactMap(\.owner).filter { $0.belongs(to: permission) }
        for owner in rejected { owner.retire() }
        releaseDuringClosedConstruction(rejected)
        leave()
        pending = []
    }

    /// Destructors are still part of this construction. A separate closed
    /// frame can be pushed even when a yielded Candidate has already left its
    /// original frame; its teardown cannot resurrect a deinitializing frame.
    private func releaseDuringClosedConstruction(_ owners: [RetainedButtonActionOwner]) {
        guard !owners.isEmpty else { return }
        let cleanup = closedCleanupFrame()
        for owner in owners { owner.releaseRetiredPayload() }
        cleanup.finish()
    }

    func closedCleanupFrame() -> RetainedButtonActionConstruction {
        let cleanup = RetainedButtonActionConstruction(runtime: runtime)
        cleanup.permission.isAvailable = false
        return cleanup
    }
}

/// A native prepass pins the original cohort and revokes it without releasing
/// application captures. Overlapping removal/close scopes may defer the same
/// owner; only their last safe cleanup boundary can release its payload.
@MainActor
final class RetainedButtonActionRetirement {
    private var owners: [RetainedButtonActionOwner]
    private var didFinish = false

    init(in roots: [ViewNode], includingPending: Bool = false) {
        var seen: Set<ObjectIdentifier> = []
        owners = RetainedButtonActionTree.nodes(in: roots).compactMap(\.buttonActionOwner).filter {
            seen.insert(ObjectIdentifier($0)).inserted
        }
        for owner in owners { owner.deferPayloadRelease() }
        for owner in owners {
            if includingPending { owner.retire() } else { owner.retireForDeparture() }
        }
    }

    isolated deinit { finish() }

    func finish() {
        guard !didFinish else { return }
        didFinish = true
        let retired = owners
        owners = []
        for owner in retired { owner.resumePayloadRelease() }
        for owner in retired { owner.releaseRetiredPayload() }
        withExtendedLifetime(retired) {}
    }
}

@MainActor
enum RetainedButtonActionTree {
    static func nodes(in roots: [ViewNode]) -> [ViewNode] {
        var result: [ViewNode] = []
        var pending = roots
        var seen: Set<ObjectIdentifier> = []
        while let node = pending.popLast() {
            guard seen.insert(ObjectIdentifier(node)).inserted else { continue }
            result.append(node)
            pending.append(contentsOf: node.children)
        }
        return result
    }

    static func publishStandalone(in roots: [ViewNode]) {
        for node in nodes(in: roots) { node.buttonActionOwner?.acceptStandalonePublication(on: node) }
    }
}

extension ViewNode {
    /// Ordinary Button's invalidation belongs to the same admitted payload as
    /// its action. A callback that replaces/removes that declaration cannot
    /// continue by invalidating through the old build context.
    package func setButtonActionCompletion(_ completion: @escaping @MainActor () -> Void) {
        buttonActionOwner?.setCompletion(completion)
    }
}
