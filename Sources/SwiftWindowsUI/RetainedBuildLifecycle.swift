import SwiftWindowsCore

/// An optional owner for state installed while a component tree is built.
/// Returning nil rejects construction without changing the retained tree.
@MainActor
public protocol RetainedBuildLifecycle: AnyObject {
    func captureBuildRequest() -> (any RetainedBuildRequest)?
    func beginBuild() -> (any RetainedBuildEpoch)?
}

extension RetainedBuildLifecycle {
    public func captureBuildRequest() -> (any RetainedBuildRequest)? { nil }
}

/// Optional validity of the model revision captured by one root request.
/// This distinguishes a newer state mutation from a control's fallback
/// invalidation for the same mutation, without exposing binding provenance.
@MainActor
public protocol RetainedBuildRequest: AnyObject {
    var isCurrent: Bool { get }
}

/// One candidate build, from composition through node adoption and cleanup.
/// The owner decides membership before adoption; node disappearance does not
/// decide which state survives. Abandonment never rolls back application code.
@MainActor
public protocol RetainedBuildEpoch: AnyObject {
    /// Whether construction may still enter preparation. A successful
    /// willAdopt() can move the epoch out of this construction phase.
    var canAdopt: Bool { get }

    /// Whether a successfully adopted request may deliver completion. Closing
    /// the owner revokes this; a later model revision after adoption does not.
    var canComplete: Bool { get }

    /// A newer root request supersedes construction. Once adoption starts,
    /// this must leave the current adoption intact and only queue the request.
    func supersede()

    /// Revokes writes to outgoing owners while retaining their cleanup reads.
    /// False rejects the candidate before any retained node is modified.
    /// A request can become obsolete during preparation, so true may still
    /// be followed by abandon() before the first retained node is changed.
    func willAdopt() -> Bool

    /// Publishes the adopted ownership before deferred input callbacks run.
    func commit()

    /// Discards an unadopted candidate, including reversible preparation.
    /// This must not roll back accepted application mutations or reopen a
    /// closed owner. It is never used to undo an adoption already in progress.
    func abandon()

    /// Ends the build scope after deferred terminal callbacks have drained.
    /// Called exactly once after either commit or abandon.
    func finishAfterCallbacks()
}

extension RetainedBuildEpoch {
    public var canComplete: Bool { true }
}

/// The captured generation of a deferred subtree, such as GeometryReader.
/// A removed generation must remain invalid after the same path is remounted.
@MainActor
public protocol RetainedSubtreeBuildLease: AnyObject {
    var canBuild: Bool { get }
    func beginBuild() -> (any RetainedBuildEpoch)?
}

/// A queued rebuild must distinguish no transaction from an explicit
/// transaction whose animation is nil, and retain the legacy scope verbatim.
@MainActor
struct RetainedBuildTransaction {
    let transaction: Transaction?
    let animation: (duration: Double, easing: AnimationEasing)?

    init() {
        transaction = currentTransaction
        animation = currentAnimationTransaction
    }

    func perform(_ body: () -> Void) {
        let previousTransaction = currentTransaction
        let previousAnimation = currentAnimationTransaction
        currentTransaction = transaction
        currentAnimationTransaction = animation
        defer {
            currentTransaction = previousTransaction
            currentAnimationTransaction = previousAnimation
        }
        body()
    }
}

/// Shared by whole-root and deferred-subtree builds in one runtime. The
/// guard is independent of gesture reconciliation: authored callbacks may
/// enqueue a new root while either kind of candidate is under construction.
@MainActor
final class RetainedBuildCoordinator {
    private struct PendingWork {
        let deferredKey: ObjectIdentifier?
        let action: @MainActor () -> Void
    }

    private struct SettlementCallback {
        // Keep the registration alive: an identifier alone could refer to a
        // different object after the original registration is deallocated.
        let owner: AnyObject
        let action: @MainActor () -> Void
    }

    private(set) var isBuilding = false
    private var currentEpoch: (any RetainedBuildEpoch)?
    private var requestSequence: UInt64 = 0
    private var pendingWork: [PendingWork] = []
    private var isDrainingReloads = false
    private var settlementCallbacks: [SettlementCallback] = []
    private var isProcessingSettlementCallbacks = false
    private let retainedCallbacksAreSettled: @MainActor () -> Bool

    init(retainedCallbacksAreSettled: @escaping @MainActor () -> Bool = { true }) {
        self.retainedCallbacksAreSettled = retainedCallbacksAreSettled
    }

    /// Notification delivery is not build work. This can remain true while
    /// newly appended observers wait for another independent drain opportunity.
    var isBuildSettled: Bool {
        !isBuilding && pendingWork.isEmpty && !isDrainingReloads && retainedCallbacksAreSettled()
    }

    /// A completion can enqueue another terminal callback after finishBuild.
    /// The runtime announces its actual callback drain exit without changing
    /// the order of those callbacks or any queued rebuilds.
    func retainedCallbacksDidDrain() {
        drainSettlementCallbacks()
    }

    /// Observe settlement without adding a rebuild or changing its transaction.
    /// The owner is a retained registration token, not the host it observes;
    /// actions must capture that host weakly and recheck their current intent.
    /// Re-registering a pending owner replaces its action in the same FIFO slot.
    /// An idle registration may run synchronously. New records appended during
    /// notification delivery wait for a later independent drain opportunity;
    /// this observer creates no wakeup or immediate follow-up pass.
    func scheduleAfterBuildsSettled(owner: AnyObject, action: @escaping @MainActor () -> Void) {
        let wasProcessingCallbacks = isProcessingSettlementCallbacks
        isProcessingSettlementCallbacks = true
        replaceSettlementCallback(owner: owner, action: action)
        isProcessingSettlementCallbacks = wasProcessingCallbacks
        drainSettlementCallbacks()
    }

    private func replaceSettlementCallback(owner: AnyObject, action: @escaping @MainActor () -> Void) {
        let callback = SettlementCallback(owner: owner, action: action)
        if let index = settlementCallbacks.firstIndex(where: { $0.owner === owner }) {
            let previous = settlementCallbacks[index]
            settlementCallbacks[index] = callback
            // Releasing captures can reenter. Publish the replacement and end
            // the array's exclusive access before the old payload is released.
            withExtendedLifetime(previous) {}
        } else {
            settlementCallbacks.append(callback)
        }
    }

    /// Preserve request order and transaction context. A receipt can discard
    /// a request made obsolete by a later model write; a plain control
    /// invalidation must not overwrite the binding transaction before it.
    func scheduleReload(_ reload: @escaping @MainActor () -> Void) {
        requestSequence &+= 1
        currentEpoch?.supersede()
        pendingWork.append(PendingWork(deferredKey: nil, action: reload))
        drainReloads()
    }

    /// Layout can encounter a deferred reader while a completion still owns
    /// the guard. Retrying its layout must not supersede that root request.
    func scheduleWhenIdle(for owner: AnyObject, _ action: @escaping @MainActor () -> Void) {
        let identifier = ObjectIdentifier(owner)
        let work = PendingWork(deferredKey: identifier, action: action)
        if let index = pendingWork.firstIndex(where: { $0.deferredKey == identifier }) {
            pendingWork[index] = work
        } else {
            pendingWork.append(work)
        }
        drainReloads()
    }

    func beginBuild() -> UInt64? {
        guard !isBuilding else { return nil }
        isBuilding = true
        return requestSequence
    }

    func install(_ epoch: (any RetainedBuildEpoch)?, startedAt sequence: UInt64) {
        currentEpoch = epoch
        if sequence != requestSequence { epoch?.supersede() }
    }

    func wasSuperseded(since sequence: UInt64) -> Bool {
        sequence != requestSequence
    }

    func finishBuild() {
        currentEpoch = nil
        isBuilding = false
        drainReloads()
    }

    private func drainReloads() {
        guard !isBuilding, !isDrainingReloads else { return }
        isDrainingReloads = true
        defer {
            isDrainingReloads = false
            drainSettlementCallbacks()
        }
        while !isBuilding, !pendingWork.isEmpty {
            let work = pendingWork.removeFirst()
            work.action()
        }
    }

    private func drainSettlementCallbacks() {
        guard !settlementCallbacks.isEmpty, !isProcessingSettlementCallbacks, isBuildSettled else { return }
        isProcessingSettlementCallbacks = true
        defer { isProcessingSettlementCallbacks = false }
        // A callback can register itself without doing any build work. Limit
        // this pass to its original slots so that cannot spin inline. Pending
        // replacements keep their slot and still use the latest action.
        var remainingCallbacks = settlementCallbacks.count
        while remainingCallbacks > 0, !settlementCallbacks.isEmpty, isBuildSettled {
            remainingCallbacks -= 1
            deliverNextSettlementCallback()
        }
    }

    private func deliverNextSettlementCallback() {
        // Remove before invoking so a callback can register the same owner for
        // later settlement. Retire this coordinator-owned notification before
        // the next readiness check; callers' aliases may outlive its delivery.
        let callback = settlementCallbacks.removeFirst()
        withExtendedLifetime(callback) { callback.action() }
    }
}
