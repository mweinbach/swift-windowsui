import Foundation

/// Internal reasons are retained so a build wait is not mistaken for a policy
/// veto and retried continuously on the native message queue.
package enum Win32CloseBusyReason: Equatable, Sendable {
    case closeInProgress
    case buildsNotSettled
    case ownerOperation
    case nativeDispatch
}

package enum Win32CloseDestructionFailure: Equatable, Sendable {
    case native(UInt32)
    case destructionNotObserved
}

package enum Win32CloseAttemptOutcome: Equatable, Sendable {
    case closed
    case vetoed
    case busy(Win32CloseBusyReason)
    case unavailable
    case destructionFailed(Win32CloseDestructionFailure)
}

package enum Win32CloseCommitDecision: Equatable, Sendable {
    case reserved
    case vetoed
    case busy(Win32CloseBusyReason)
    case unavailable
}

package enum Win32DeferredClosePhase: Equatable, Sendable {
    case prompt
    case retry
}

package enum Win32DeferredCloseSubmission: Equatable, Sendable {
    case queued
    case coalesced
    case busy
    case unavailable
    case postFailed(UInt32)
}

/// Scalars posted to an HWND are never reused, including after handle reuse.
/// Tests can inject a separate sequence without changing the process source.
@MainActor
final class Win32CloseWakeSequence {
    static let process = Win32CloseWakeSequence()
    private var lastValue: UInt?

    init(startingAfter value: UInt? = 0) { lastValue = value }

    func takeNext() -> UInt? {
        guard let lastValue, lastValue < UInt.max else {
            self.lastValue = nil
            return nil
        }
        let next = lastValue + 1
        self.lastValue = next
        return next
    }
}

/// Teardown holds this pin until editor/model capabilities have been revoked.
/// Revoking a registration can then remove work without releasing its captures
/// before the ordinary window cleanup has reached that boundary.
@MainActor
package final class Win32CloseWorkPin {
    private let records: [AnyObject]

    fileprivate init(records: [AnyObject]) { self.records = records }
}

/// Only package-owned code implements this lease. Validation must read owned
/// state and publish a primitive reservation without application callbacks,
/// notifications, payload release, rebuilding, IO, or native message pumping.
/// Its actual owner/session references must remain strong until finish returns.
@MainActor
package protocol Win32CloseCommitLease: AnyObject {
    func validateAndReserve() -> Win32CloseCommitDecision

    /// Called exactly once for every prepared lease, including a failed final
    /// guard before DestroyWindow. A live owner's temporary reservation must be
    /// released on failure; a consumed approval is never made reusable.
    func finish(with outcome: Win32CloseAttemptOutcome)
}

@MainActor
package enum Win32CloseCommitPreparation {
    case ready(any Win32CloseCommitLease)
    case vetoed
    case busy(Win32CloseBusyReason)
    case unavailable
}

@MainActor
package protocol Win32CloseAuthority: AnyObject {
    /// Runs after every ordinary delegate vote. Return a lease that pins the
    /// concrete owner/session, not merely a closure containing weak captures.
    func prepareCloseCommit(for attempt: Win32CloseAttempt) -> Win32CloseCommitPreparation
}

/// One full native veto/commit evaluation. An ordinary request has no ticket;
/// a deferred request keeps its exact intent through the entire evaluation.
@MainActor
package final class Win32CloseAttempt {
    package let id = UUID()
    package let ticket: Win32CloseTicket?
    package var intentID: UUID? { ticket?.intentID }
    package private(set) var busyReason: Win32CloseBusyReason?
    package private(set) var isUnavailable = false
    fileprivate let registrationEpoch: UUID?
    private weak var control: Win32CloseControl?

    fileprivate init(ticket: Win32CloseTicket?, registrationEpoch: UUID?, control: Win32CloseControl) {
        self.ticket = ticket
        self.registrationEpoch = registrationEpoch
        self.control = control
    }

    /// Explains a false legacy delegate vote. It cannot override that vote.
    package func deferUntilReady(_ reason: Win32CloseBusyReason) {
        if busyReason == nil { busyReason = reason }
    }

    /// Strengthens only this still-active evaluation. An exhausted or
    /// unprovable receipt is unavailable, not a policy veto or a retry signal.
    /// Holding an old attempt cannot affect the next native evaluation.
    package func rejectAsUnavailable() {
        guard control?.activeAttempt === self else { return }
        isUnavailable = true
    }
}

/// An object identity, not an HWND value. A held old lifetime remains completed
/// after another native window reuses its handle or its Swift window object.
@MainActor
final class Win32CloseLifetime {
    let id = UUID()
    let generation: UInt64
    var handle: UInt?
    private(set) var destructionStarted = false
    private(set) var destructionCompleted = false
    private(set) var creationFailed = false

    init(generation: UInt64) {
        self.generation = generation
    }

    var isAlive: Bool {
        handle != nil && !destructionStarted && !destructionCompleted && !creationFailed
    }

    func beginDestruction() { destructionStarted = true }

    func completeDestruction() {
        destructionStarted = true
        destructionCompleted = true
    }

    func failCreation() { creationFailed = true }
}

/// An intent ticket contains no document value or strong host reference.
/// Cancellation is permanent, and terminal native attempts consume it once.
@MainActor
package final class Win32CloseTicket {
    package let id = UUID()
    package let intentID: UUID
    fileprivate weak var registration: Win32CloseRegistration?
    fileprivate let lifetime: Win32CloseLifetime
    fileprivate let registrationEpoch: UUID
    fileprivate private(set) var isCancelled = false
    fileprivate var consumedByAttempt: UUID?
    fileprivate var latestDeferredNonce: UInt?

    fileprivate init(
        intentID: UUID, registration: Win32CloseRegistration, lifetime: Win32CloseLifetime
    ) {
        self.intentID = intentID
        self.registration = registration
        self.lifetime = lifetime
        registrationEpoch = registration.ticketEpoch
    }

    package var isCurrent: Bool {
        guard !isCancelled, consumedByAttempt == nil, let registration else { return false }
        return registration.accepts(self)
    }

    package func cancel() {
        isCancelled = true
        registration?.control?.cancelDeferredWork(ticket: self)
    }
}

/// The window owns the registration, and the registration owns no host. Losing
/// a previously required authority is a veto, never restoration of default true.
@MainActor
package final class Win32CloseRegistration {
    package let id = UUID()
    fileprivate weak var control: Win32CloseControl?
    fileprivate weak var authority: (any Win32CloseAuthority)?
    fileprivate var lifetime: Win32CloseLifetime?
    fileprivate var ticketEpoch = UUID()
    package private(set) var isRevoked = false

    fileprivate init(control: Win32CloseControl, authority: any Win32CloseAuthority) {
        self.control = control
        self.authority = authority
    }

    package var isCurrent: Bool {
        guard !isRevoked, authority != nil, let control else { return false }
        return control.registration === self
    }

    package func makeTicket(intentID: UUID) -> Win32CloseTicket? {
        guard isCurrent, let lifetime, lifetime.isAlive else { return nil }
        return Win32CloseTicket(intentID: intentID, registration: self, lifetime: lifetime)
    }

    package func revoke() {
        // Publish the tombstone before any caller releases an application owner.
        isRevoked = true
        control?.cancelDeferredWork(registration: self)
    }

    /// Replacing a session/participant invalidates its tickets without removing
    /// the host's required final authority or stranding the next close request.
    package func invalidateTickets() {
        ticketEpoch = UUID()
        control?.cancelDeferredWork(registration: self)
    }

    /// Callers capture their host/session weakly and revalidate the intent in
    /// the action. Coalescing retains the first action for the same ticket and
    /// phase. A post failure does not close the owner or retry automatically.
    package func enqueue(
        ticket: Win32CloseTicket,
        phase: Win32DeferredClosePhase,
        onPostFailure: @escaping @MainActor (Win32CloseTicket, UInt32) -> Void,
        action: @escaping @MainActor (Win32CloseTicket) -> Void
    ) -> Win32DeferredCloseSubmission {
        guard let control, control.registration === self else { return .unavailable }
        return control.enqueue(
            ticket: ticket, phase: phase, onPostFailure: onPostFailure, action: action)
    }

    package func pinDeferredWork() -> Win32CloseWorkPin? {
        control?.pinDeferredWork(for: self)
    }

    fileprivate func accepts(_ ticket: Win32CloseTicket) -> Bool {
        isCurrent && ticket.registration === self && ticket.lifetime === lifetime
            && ticket.registrationEpoch == ticketEpoch
            && ticket.lifetime.isAlive && control?.lifetime === lifetime
    }
}

enum Win32CloseNativeResult: Equatable {
    case succeeded
    case failed(UInt32)
}

/// MainActor state behind one Win32Window. Native calls are supplied per
/// attempt, allowing deterministic tests without a global native override.
@MainActor
final class Win32CloseControl: Win32DispatchWakeClient {
    private final class DeferredWork {
        let ticket: Win32CloseTicket
        let phase: Win32DeferredClosePhase
        let nonce: UInt
        let action: @MainActor (Win32CloseTicket) -> Void
        let onPostFailure: @MainActor (Win32CloseTicket, UInt32) -> Void
        var hasOutstandingWake = false

        init(
            ticket: Win32CloseTicket, phase: Win32DeferredClosePhase, nonce: UInt,
            onPostFailure: @escaping @MainActor (Win32CloseTicket, UInt32) -> Void,
            action: @escaping @MainActor (Win32CloseTicket) -> Void
        ) {
            self.ticket = ticket
            self.phase = phase
            self.nonce = nonce
            self.onPostFailure = onPostFailure
            self.action = action
        }
    }

    private(set) var lifetime: Win32CloseLifetime?
    private(set) var registration: Win32CloseRegistration?
    private(set) var activeAttempt: Win32CloseAttempt?
    private var requiresAuthority = false
    private var topologyIdentity = UUID()
    private let postWake: (@MainActor (UInt, UInt) -> Win32CloseNativeResult)?
    private let wakeSequence: Win32CloseWakeSequence
    private var pendingWork: DeferredWork?
    private var executingWork: DeferredWork?
    var isCloseEnabled = true

    init(
        postWake: (@MainActor (UInt, UInt) -> Win32CloseNativeResult)? = nil,
        wakeSequence: Win32CloseWakeSequence = .process
    ) {
        self.postWake = postWake
        self.wakeSequence = wakeSequence
    }

    var isHandlingCloseRequest: Bool { activeAttempt != nil }

    @discardableResult
    func installAuthority(_ authority: any Win32CloseAuthority) -> Win32CloseRegistration? {
        Win32DispatchScope.withMailboxWork {
            guard activeAttempt == nil else { return nil }
            if let lifetime, lifetime.destructionStarted, !lifetime.destructionCompleted { return nil }
            let previous = registration
            let workPin = pinDeferredWork()
            let next = Win32CloseRegistration(control: self, authority: authority)
            if let lifetime, !lifetime.destructionStarted, !lifetime.creationFailed {
                next.lifetime = lifetime
            }
            requiresAuthority = true
            registration = next
            previous?.revoke()
            // Do not release the old registration until its tombstone is published
            // and the new registration is visible to reentrant cleanup.
            withExtendedLifetime((previous, workPin)) {}
            return next
        }
    }

    func noteTopologyChanged() { topologyIdentity = UUID() }

    @discardableResult
    func beginLifetime(generation: UInt64) -> Win32CloseLifetime {
        let next = Win32CloseLifetime(generation: generation)
        if let registration {
            if registration.lifetime == nil, !registration.isRevoked {
                registration.lifetime = next
            } else {
                registration.revoke()
            }
        }
        lifetime = next
        return next
    }

    func didCreate(_ lifetime: Win32CloseLifetime, handle: UInt) {
        guard self.lifetime === lifetime, !lifetime.destructionStarted, !lifetime.creationFailed else { return }
        lifetime.handle = handle
    }

    func creationFailed(_ lifetime: Win32CloseLifetime) {
        lifetime.failCreation()
        if self.lifetime === lifetime { registration?.revoke() }
    }

    func beginDestruction(_ lifetime: Win32CloseLifetime) {
        lifetime.beginDestruction()
        if self.lifetime === lifetime { registration?.revoke() }
    }

    func completeDestruction(_ lifetime: Win32CloseLifetime) {
        lifetime.completeDestruction()
        if self.lifetime === lifetime { registration?.revoke() }
    }

    func revokeForForcedTeardown() { registration?.revoke() }

    func attemptClose(
        expectedHandle: UInt,
        ticket: Win32CloseTicket?,
        participants: [AnyObject],
        preflight: () -> Bool,
        destroy: (UInt) -> Win32CloseNativeResult
    ) -> Win32CloseAttemptOutcome {
        guard activeAttempt == nil else { return .busy(.closeInProgress) }
        if let ticket {
            let isOwnedRetry = executingWork?.ticket === ticket && executingWork?.phase == .retry
            guard Win32DispatchScope.permitsTaggedClose(isOwnedRetry: isOwnedRetry) else {
                return .busy(.nativeDispatch)
            }
        }
        guard let lifetime, lifetime.isAlive, lifetime.handle == expectedHandle else { return .unavailable }
        let selectedRegistration = registration
        let authority = selectedRegistration?.authority
        if requiresAuthority {
            guard let selectedRegistration, selectedRegistration.isCurrent, authority != nil,
                selectedRegistration.lifetime === lifetime
            else { return .unavailable }
        }
        if let ticket {
            guard ticket.isCurrent, ticket.registration === selectedRegistration,
                ticket.lifetime === lifetime
            else { return .unavailable }
        }

        let attempt = Win32CloseAttempt(
            ticket: ticket, registrationEpoch: selectedRegistration?.ticketEpoch, control: self)
        let selectedTopology = topologyIdentity
        activeAttempt = attempt
        Win32DispatchScope.beginCloseAttempt()
        defer {
            activeAttempt = nil
            Win32DispatchScope.endCloseAttempt()
        }

        return withExtendedLifetime((participants, selectedRegistration, authority, lifetime, attempt)) {
            var lease: (any Win32CloseCommitLease)?
            let outcome: Win32CloseAttemptOutcome = {
                let approved = preflight()
                if lifetime.destructionCompleted { return .closed }
                if attempt.isUnavailable { return .unavailable }
                guard approved else {
                    if let reason = attempt.busyReason { return .busy(reason) }
                    return .vetoed
                }
                guard
                    isCurrent(
                        lifetime: lifetime, handle: expectedHandle, registration: selectedRegistration,
                        topology: selectedTopology, attempt: attempt)
                else { return .unavailable }
                guard isCloseEnabled else { return .vetoed }

                if let authority {
                    let preparation = authority.prepareCloseCommit(for: attempt)
                    if case .ready(let prepared) = preparation { lease = prepared }
                    if lifetime.destructionCompleted { return .closed }
                    if attempt.isUnavailable { return .unavailable }
                    switch preparation {
                    case .ready: break
                    case .vetoed: return .vetoed
                    case .busy(let reason): return .busy(reason)
                    case .unavailable: return .unavailable
                    }
                }

                if lifetime.destructionCompleted { return .closed }
                guard
                    isCurrent(
                        lifetime: lifetime, handle: expectedHandle, registration: selectedRegistration,
                        topology: selectedTopology, attempt: attempt)
                else { return .unavailable }
                guard isCloseEnabled else { return .vetoed }

                if let lease {
                    let decision = lease.validateAndReserve()
                    if lifetime.destructionCompleted { return .closed }
                    if attempt.isUnavailable { return .unavailable }
                    switch decision {
                    case .reserved: break
                    case .vetoed: return .vetoed
                    case .busy(let reason): return .busy(reason)
                    case .unavailable: return .unavailable
                    }
                }
                ticket?.consumedByAttempt = attempt.id

                // Only primitive owned state is read from final validation to
                // the native call. Every owner and participant remains pinned.
                guard
                    isCurrent(
                        lifetime: lifetime, handle: expectedHandle, registration: selectedRegistration,
                        topology: selectedTopology, attempt: attempt)
                else { return .unavailable }
                guard isCloseEnabled else { return .vetoed }
                let result = destroy(expectedHandle)
                if lifetime.destructionCompleted { return .closed }
                switch result {
                case .failed(let code): return .destructionFailed(.native(code))
                case .succeeded: return .destructionFailed(.destructionNotObserved)
                }
            }()

            if case .busy = outcome {
                // A build/native wait can reuse an unconsumed ticket.
            } else {
                ticket?.consumedByAttempt = attempt.id
            }
            // Publish terminal ticket consumption before cleanup can release
            // application payloads or reenter. A prepared lease finishes on
            // every exit, including a failed post-reservation native guard.
            lease?.finish(with: outcome)
            return withExtendedLifetime(lease) { outcome }
        }
    }

    func pinDeferredWork(for selectedRegistration: Win32CloseRegistration? = nil) -> Win32CloseWorkPin {
        var records: [AnyObject] = []
        for work in [pendingWork, executingWork] {
            if let work,
                selectedRegistration == nil || work.ticket.registration === selectedRegistration
            {
                records.append(work)
            }
        }
        return Win32CloseWorkPin(records: records)
    }

    fileprivate func cancelDeferredWork(registration: Win32CloseRegistration) {
        Win32DispatchScope.withMailboxWork {
            guard let work = pendingWork, work.ticket.registration === registration else { return }
            pendingWork = nil
            work.hasOutstandingWake = false
            withExtendedLifetime(work) {}
        }
    }

    fileprivate func cancelDeferredWork(ticket: Win32CloseTicket) {
        Win32DispatchScope.withMailboxWork {
            guard let work = pendingWork, work.ticket === ticket else { return }
            pendingWork = nil
            work.hasOutstandingWake = false
            withExtendedLifetime(work) {}
        }
    }

    fileprivate func enqueue(
        ticket: Win32CloseTicket,
        phase: Win32DeferredClosePhase,
        onPostFailure: @escaping @MainActor (Win32CloseTicket, UInt32) -> Void,
        action: @escaping @MainActor (Win32CloseTicket) -> Void
    ) -> Win32DeferredCloseSubmission {
        Win32DispatchScope.withMailboxWork {
            guard let postWake, let registration, let authority = registration.authority,
                ticket.isCurrent, ticket.registration === registration,
                ticket.lifetime === lifetime, let handle = ticket.lifetime.handle
            else { return .unavailable }
            if let pendingWork {
                return pendingWork.ticket === ticket && pendingWork.phase == phase ? .coalesced : .busy
            }
            if let executingWork {
                if executingWork.ticket === ticket, executingWork.phase == phase { return .coalesced }
                guard executingWork.ticket === ticket, executingWork.phase == .prompt, phase == .retry else {
                    return .busy
                }
            }
            guard let nonce = wakeSequence.takeNext() else { return .unavailable }
            let work = DeferredWork(
                ticket: ticket, phase: phase, nonce: nonce,
                onPostFailure: onPostFailure, action: action)
            ticket.latestDeferredNonce = nonce
            pendingWork = work
            return withExtendedLifetime((registration, authority, work)) {
                if executingWork != nil {
                    // A prompt can queue its approved retry, but cannot start
                    // another close while its own callback/modal stack is live.
                    Win32DispatchScope.requestWakeWhenIdle(self)
                    return .queued
                }
                work.hasOutstandingWake = true
                let result = postWake(handle, nonce)
                guard pendingWork === work, isCurrent(work) else {
                    if pendingWork === work { pendingWork = nil }
                    work.hasOutstandingWake = false
                    return .unavailable
                }
                switch result {
                case .succeeded:
                    return .queued
                case .failed(let code):
                    pendingWork = nil
                    work.hasOutstandingWake = false
                    // The synchronous caller owns this failure; notifying its
                    // observer too would deliver the same failure twice.
                    return .postFailed(code)
                }
            }
        }
    }

    /// Only the private scalar wake reaches here. A consumed nested wake keeps
    /// the record, then rearms once at the outer owned scope exit. Duplicates
    /// cannot clear or execute newer work, even after an HWND value is reused.
    func receiveDeferredWake(nonce: UInt) {
        let canDeliver = Win32DispatchScope.canDeliverWindowWake && activeAttempt == nil && executingWork == nil
        Win32DispatchScope.withMailboxWork {
            guard pendingWork?.nonce == nonce, pendingWork?.hasOutstandingWake == true else { return }
            let selectedRegistration = registration
            let authority = selectedRegistration?.authority
            // The helper owns the work local, so its final payload release
            // occurs before these promoted weak owners can be released.
            withExtendedLifetime((selectedRegistration, authority)) {
                consumeDeferredWake(nonce: nonce, canDeliver: canDeliver)
            }
        }
    }

    private func consumeDeferredWake(nonce: UInt, canDeliver: Bool) {
        guard let work = pendingWork, work.nonce == nonce, work.hasOutstandingWake else { return }
        work.hasOutstandingWake = false
        guard isCurrent(work) else {
            pendingWork = nil
            return
        }
        guard canDeliver else {
            Win32DispatchScope.requestWakeWhenIdle(self)
            return
        }
        // Delivery is consumed before callbacks. The intent ticket remains
        // current for a later retry until a terminal native attempt uses it.
        pendingWork = nil
        executingWork = work
        Win32DispatchScope.withMailboxDelivery {
            work.action(work.ticket)
        }
        executingWork = nil
        if let pendingWork, !pendingWork.hasOutstandingWake {
            Win32DispatchScope.requestWakeWhenIdle(self)
        }
    }

    func dispatchScopeDidBecomeIdle() -> (@MainActor () -> Void)? {
        guard let work = pendingWork, !work.hasOutstandingWake else { return nil }
        let selectedRegistration = registration
        let authority = selectedRegistration?.authority
        guard let postWake, authority != nil, isCurrent(work), let handle = work.ticket.lifetime.handle else {
            pendingWork = nil
            return retirement(of: work, registration: selectedRegistration, authority: authority)
        }
        work.hasOutstandingWake = true
        let result = postWake(handle, work.nonce)
        guard pendingWork === work, isCurrent(work) else {
            if pendingWork === work { pendingWork = nil }
            work.hasOutstandingWake = false
            return retirement(of: work, registration: selectedRegistration, authority: authority)
        }
        switch result {
        case .succeeded:
            return retirement(of: work, registration: selectedRegistration, authority: authority)
        case .failed(let code):
            pendingWork = nil
            work.hasOutstandingWake = false
            return retirement(of: work, registration: selectedRegistration, authority: authority, failure: code)
        }
    }

    private func retirement(
        of work: DeferredWork,
        registration: Win32CloseRegistration?,
        authority: (any Win32CloseAuthority)?,
        failure: UInt32? = nil
    ) -> @MainActor () -> Void {
        // Keep promoted weak owners and every retired payload until the scope
        // has cleared its posting guard. ARC or failure delivery can then pump
        // messages only under the scope's protected mailbox cleanup phase.
        { [self, work, registration, authority] in
            withExtendedLifetime((work, registration, authority)) {
                if let failure, isCurrent(work), work.ticket.latestDeferredNonce == work.nonce {
                    work.onPostFailure(work.ticket, failure)
                }
            }
        }
    }

    private func isCurrent(_ work: DeferredWork) -> Bool {
        work.ticket.isCurrent && work.ticket.registration === registration
            && work.ticket.lifetime === lifetime && work.ticket.lifetime.isAlive
    }

    private func isCurrent(
        lifetime: Win32CloseLifetime,
        handle: UInt,
        registration selectedRegistration: Win32CloseRegistration?,
        topology: UUID,
        attempt: Win32CloseAttempt
    ) -> Bool {
        guard self.lifetime === lifetime, lifetime.isAlive, lifetime.handle == handle,
            registration === selectedRegistration, topologyIdentity == topology,
            activeAttempt === attempt, !attempt.isUnavailable
        else { return false }
        if requiresAuthority {
            guard let selectedRegistration, !selectedRegistration.isRevoked,
                selectedRegistration.lifetime === lifetime,
                selectedRegistration.ticketEpoch == attempt.registrationEpoch
            else { return false }
        }
        if let ticket = attempt.ticket {
            guard !ticket.isCancelled, ticket.registration === selectedRegistration,
                ticket.lifetime === lifetime,
                ticket.consumedByAttempt == nil || ticket.consumedByAttempt == attempt.id
            else { return false }
        }
        return true
    }
}
