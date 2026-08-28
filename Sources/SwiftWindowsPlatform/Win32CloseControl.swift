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
    fileprivate let registrationEpoch: UUID?

    fileprivate init(ticket: Win32CloseTicket?, registrationEpoch: UUID?) {
        self.ticket = ticket
        self.registrationEpoch = registrationEpoch
    }

    /// Explains a false legacy delegate vote. It cannot override that vote.
    package func deferUntilReady(_ reason: Win32CloseBusyReason) {
        if busyReason == nil { busyReason = reason }
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
    }

    /// Replacing a session/participant invalidates its tickets without removing
    /// the host's required final authority or stranding the next close request.
    package func invalidateTickets() {
        ticketEpoch = UUID()
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
final class Win32CloseControl {
    private(set) var lifetime: Win32CloseLifetime?
    private(set) var registration: Win32CloseRegistration?
    private(set) var activeAttempt: Win32CloseAttempt?
    private var requiresAuthority = false
    private var topologyIdentity = UUID()
    var isCloseEnabled = true

    var isHandlingCloseRequest: Bool { activeAttempt != nil }

    @discardableResult
    func installAuthority(_ authority: any Win32CloseAuthority) -> Win32CloseRegistration? {
        guard activeAttempt == nil else { return nil }
        if let lifetime, lifetime.destructionStarted, !lifetime.destructionCompleted { return nil }
        let previous = registration
        previous?.revoke()
        let next = Win32CloseRegistration(control: self, authority: authority)
        if let lifetime, !lifetime.destructionStarted, !lifetime.creationFailed {
            next.lifetime = lifetime
        }
        requiresAuthority = true
        registration = next
        // Do not release the old registration until its tombstone is published
        // and the new registration is visible to reentrant cleanup.
        withExtendedLifetime(previous) {}
        return next
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

        let attempt = Win32CloseAttempt(ticket: ticket, registrationEpoch: selectedRegistration?.ticketEpoch)
        let selectedTopology = topologyIdentity
        activeAttempt = attempt
        defer { activeAttempt = nil }

        return withExtendedLifetime((participants, selectedRegistration, authority, lifetime, attempt)) {
            var lease: (any Win32CloseCommitLease)?
            let outcome: Win32CloseAttemptOutcome = {
                let approved = preflight()
                if lifetime.destructionCompleted { return .closed }
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

    private func isCurrent(
        lifetime: Win32CloseLifetime,
        handle: UInt,
        registration selectedRegistration: Win32CloseRegistration?,
        topology: UUID,
        attempt: Win32CloseAttempt
    ) -> Bool {
        guard self.lifetime === lifetime, lifetime.isAlive, lifetime.handle == handle,
            registration === selectedRegistration, topologyIdentity == topology,
            activeAttempt === attempt
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
