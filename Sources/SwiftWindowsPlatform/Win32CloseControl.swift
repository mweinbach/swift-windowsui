import Foundation
import SwiftWindowsCore

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
    case owner(NativeWindowOwnerFailure)
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
    package let id = Foundation.UUID()
    package let ticket: Win32CloseTicket?
    package var intentID: Foundation.UUID? { ticket?.intentID }
    package private(set) var busyReason: Win32CloseBusyReason?
    package private(set) var isUnavailable = false
    fileprivate let registrationEpoch: Foundation.UUID?
    private weak var control: Win32CloseControl?

    fileprivate init(ticket: Win32CloseTicket?, registrationEpoch: Foundation.UUID?, control: Win32CloseControl) {
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
    let id: Foundation.UUID
    let generation: UInt64
    var handle: UInt?
    private(set) var destructionStarted = false
    private(set) var destructionCompleted = false
    private(set) var creationFailed = false

    init(generation: UInt64, id: Foundation.UUID = Foundation.UUID()) {
        self.id = id
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
    package let id = Foundation.UUID()
    package let intentID: Foundation.UUID
    fileprivate weak var registration: Win32CloseRegistration?
    fileprivate let lifetime: Win32CloseLifetime
    fileprivate let registrationEpoch: Foundation.UUID
    fileprivate private(set) var isCancelled = false
    fileprivate var consumedByAttempt: Foundation.UUID?
    fileprivate var latestDeferredNonce: UInt?

    fileprivate init(
        intentID: Foundation.UUID, registration: Win32CloseRegistration, lifetime: Win32CloseLifetime
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
    package let id = Foundation.UUID()
    fileprivate weak var control: Win32CloseControl?
    fileprivate weak var authority: (any Win32CloseAuthority)?
    fileprivate var lifetime: Win32CloseLifetime?
    fileprivate var ticketEpoch = Foundation.UUID()
    package private(set) var isRevoked = false

    fileprivate init(control: Win32CloseControl, authority: any Win32CloseAuthority) {
        self.control = control
        self.authority = authority
    }

    package var isCurrent: Bool {
        guard !isRevoked, authority != nil, let control else { return false }
        return control.registration === self
    }

    package func makeTicket(intentID: Foundation.UUID) -> Win32CloseTicket? {
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
        ticketEpoch = Foundation.UUID()
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

package enum Win32CloseNativeResult: Equatable, Sendable {
    case succeeded
    case failed(UInt32)
}

/// MainActor state behind one Win32Window. Native calls are supplied per
/// attempt, allowing deterministic tests without a global native override.
@MainActor
final class Win32CloseControl: Win32DispatchWakeClient {
    private final class DeferredWork {
        enum RetryState {
            case notAttempted
            case attempting(Win32CloseAttempt)
            case continuation(Win32CloseAttempt, topology: Foundation.UUID, handle: UInt)
            case retired
        }

        let ticket: Win32CloseTicket
        let phase: Win32DeferredClosePhase
        let nonce: UInt
        let action: @MainActor (Win32CloseTicket) -> Void
        let onPostFailure: @MainActor (Win32CloseTicket, UInt32) -> Void
        var hasOutstandingWake = false
        var retryState = RetryState.notAttempted

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

    private struct DeferredCleanupIdentity {
        let ticket: Win32CloseTicket
        let phase: Win32DeferredClosePhase
    }

    /// Actor-owned pins survive submission, native quiescence and full native
    /// unwind. Only the reservation value is sent to the HWND owner.
    private final class PreparedNativeClose {
        let reservation: Win32NativeCloseReservation
        let lifetime: Win32CloseLifetime
        let attempt: Win32CloseAttempt
        let participants: [AnyObject]
        let registration: Win32CloseRegistration?
        let authority: (any Win32CloseAuthority)?
        let lease: (any Win32CloseCommitLease)?

        init(
            reservation: Win32NativeCloseReservation, lifetime: Win32CloseLifetime,
            attempt: Win32CloseAttempt, participants: [AnyObject],
            registration: Win32CloseRegistration?, authority: (any Win32CloseAuthority)?,
            lease: (any Win32CloseCommitLease)?
        ) {
            self.reservation = reservation
            self.lifetime = lifetime
            self.attempt = attempt
            self.participants = participants
            self.registration = registration
            self.authority = authority
            self.lease = lease
        }
    }

    private(set) var lifetime: Win32CloseLifetime?
    private(set) var registration: Win32CloseRegistration?
    private(set) var activeAttempt: Win32CloseAttempt?
    private var requiresAuthority = false
    private var topologyIdentity = Foundation.UUID()
    private let postWake: (@MainActor (UInt, UInt) -> Win32CloseNativeResult)?
    private var nativePostWake: (@MainActor (UInt, UInt) -> NativeWindowSubmission)?
    private let wakeSequence: Win32CloseWakeSequence
    private var pendingWork: DeferredWork?
    private var executingWork: DeferredWork?
    private var preparedNativeClose: PreparedNativeClose?
    private var deferredCleanupIdentities: [DeferredCleanupIdentity] = []
    var isCloseEnabled = true

    init(
        postWake: (@MainActor (UInt, UInt) -> Win32CloseNativeResult)? = nil,
        wakeSequence: Win32CloseWakeSequence = .process
    ) {
        self.postWake = postWake
        self.wakeSequence = wakeSequence
    }

    var isHandlingCloseRequest: Bool { activeAttempt != nil }

    /// Installs the split owner's typed submission boundary before any work is
    /// admitted. A logical rejection is unavailable, never an invented Win32
    /// error. The poster retains that typed failure and revokes its registration.
    @discardableResult
    func installNativeDeferredWake(
        _ post: @escaping @MainActor (UInt, UInt) -> NativeWindowSubmission
    ) -> Bool {
        guard activeAttempt == nil, pendingWork == nil, executingWork == nil,
            deferredCleanupIdentities.isEmpty
        else { return false }
        nativePostWake = post
        return true
    }

    private var hasDeferredWakePoster: Bool { nativePostWake != nil || postWake != nil }

    private func postDeferredWake(handle: UInt, nonce: UInt) -> NativeWindowSubmission {
        if let nativePostWake { return nativePostWake(handle, nonce) }
        guard let postWake else { return .rejected(.unavailable) }
        switch postWake(handle, nonce) {
        case .succeeded: return .accepted
        case .failed(let code): return .rejected(.postFailed(code: code))
        }
    }

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

    func noteTopologyChanged() { topologyIdentity = Foundation.UUID() }

    @discardableResult
    func beginLifetime(generation: UInt64, id: Foundation.UUID = Foundation.UUID()) -> Win32CloseLifetime {
        let next = Win32CloseLifetime(generation: generation, id: id)
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

    /// Evaluates and reserves on the actor without calling or waiting for the
    /// native owner. The caller must publish its closing guard and prepare its
    /// retained state before submitting the reservation for native teardown.
    /// Queue acceptance is not a close outcome; only completeNativeClose may
    /// finish the retained authority after a terminal native acknowledgement.
    func prepareNativeClose(
        windowKey: NativeWindowKey,
        requestID: NativeWindowRequestID,
        expectedHandle: UInt,
        ticket: Win32CloseTicket?,
        participants: [AnyObject],
        preflight: () -> Bool
    ) -> Win32NativeClosePreparation {
        var selectedRetry: DeferredWork?
        if let executingWork, executingWork.phase == .retry {
            switch executingWork.retryState {
            case .notAttempted:
                if executingWork.ticket === ticket { selectedRetry = executingWork }
            case .attempting, .continuation, .retired:
                executingWork.retryState = .retired
            }
        }
        guard activeAttempt == nil, preparedNativeClose == nil else {
            return .completed(.busy(.closeInProgress))
        }
        if ticket != nil {
            guard Win32DispatchScope.permitsTaggedClose(isOwnedRetry: selectedRetry != nil) else {
                return .completed(.busy(.nativeDispatch))
            }
        }
        guard let lifetime, lifetime.isAlive, lifetime.handle == expectedHandle,
            lifetime.id == windowKey.lifetimeID
        else { return .completed(.unavailable) }
        let selectedRegistration = registration
        let authority = selectedRegistration?.authority
        if requiresAuthority {
            guard let selectedRegistration, selectedRegistration.isCurrent, authority != nil,
                selectedRegistration.lifetime === lifetime
            else { return .completed(.unavailable) }
        }
        if let ticket {
            guard ticket.isCurrent, ticket.registration === selectedRegistration,
                ticket.lifetime === lifetime
            else { return .completed(.unavailable) }
        }

        let attempt = Win32CloseAttempt(
            ticket: ticket, registrationEpoch: selectedRegistration?.ticketEpoch, control: self)
        // Allocate the value identity before user code and final validation.
        let reservation = Win32NativeCloseReservation(
            windowKey: windowKey, requestID: requestID, attemptID: attempt.id,
            expectedHandle: expectedHandle)
        let selectedTopology = topologyIdentity
        selectedRetry?.retryState = .attempting(attempt)
        activeAttempt = attempt
        var keepsReservation = false
        Win32DispatchScope.beginCloseAttempt()
        defer {
            if !keepsReservation { activeAttempt = nil }
            // Native lifetime state, not this synchronous actor scope, protects
            // the interval until the matching completion. Never span an await.
            Win32DispatchScope.endCloseAttempt()
        }

        return withExtendedLifetime((participants, selectedRegistration, authority, lifetime, attempt)) {
            var lease: (any Win32CloseCommitLease)?
            let rejection: Win32CloseAttemptOutcome? = {
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
                guard
                    isCurrent(
                        lifetime: lifetime, handle: expectedHandle, registration: selectedRegistration,
                        topology: selectedTopology, attempt: attempt)
                else { return .unavailable }
                guard isCloseEnabled else { return .vetoed }
                return nil
            }()

            if let outcome = rejection {
                if case .busy = outcome {
                    // A busy evaluation has not consumed its deferred ticket.
                } else {
                    ticket?.consumedByAttempt = attempt.id
                }
                lease?.finish(with: outcome)
                if let selectedRetry, executingWork === selectedRetry,
                    case .attempting(let selectedAttempt) = selectedRetry.retryState,
                    selectedAttempt === attempt
                {
                    if outcome == .busy(.buildsNotSettled), let ticket, ticket.isCurrent,
                        ticket.latestDeferredNonce == selectedRetry.nonce,
                        isCurrent(
                            lifetime: lifetime, handle: expectedHandle, registration: selectedRegistration,
                            topology: selectedTopology, attempt: attempt)
                    {
                        selectedRetry.retryState = .continuation(
                            attempt, topology: selectedTopology, handle: expectedHandle)
                    } else {
                        selectedRetry.retryState = .retired
                    }
                }
                return withExtendedLifetime(lease) { .completed(outcome) }
            }

            preparedNativeClose = PreparedNativeClose(
                reservation: reservation, lifetime: lifetime, attempt: attempt,
                participants: participants, registration: selectedRegistration,
                authority: authority, lease: lease)
            keepsReservation = true
            selectedRetry?.retryState = .retired
            return .reserved(reservation)
        }
    }

    /// Returns nil for a duplicate/mismatched reply or an acknowledgement that
    /// has not unwound native dispatch. A completed old lifetime never mutates
    /// a newer lifetime, even if its HWND value has been reused.
    func completeNativeClose(
        _ reservation: Win32NativeCloseReservation,
        result: Result<Win32NativeCloseDestruction, NativeWindowOwnerFailure>
    ) -> Win32CloseAttemptOutcome? {
        guard let prepared = preparedNativeClose, prepared.reservation == reservation,
            activeAttempt === prepared.attempt
        else { return nil }
        if case .success(let destruction) = result, !destruction.didUnwindNativeDispatch {
            return nil
        }

        return Win32DispatchScope.withMailboxWork {
            preparedNativeClose = nil
            Win32DispatchScope.beginCloseAttempt()
            defer {
                if activeAttempt === prepared.attempt { activeAttempt = nil }
                Win32DispatchScope.endCloseAttempt()
            }
            let outcome: Win32CloseAttemptOutcome
            switch result {
            case .failure(let failure):
                outcome = .destructionFailed(.owner(failure))
            case .success(let destruction):
                if destruction.didObserveNonClientDestruction {
                    beginDestruction(prepared.lifetime)
                    completeDestruction(prepared.lifetime)
                    outcome = .closed
                } else {
                    switch destruction.nativeResult {
                    case .failed(let code): outcome = .destructionFailed(.native(code))
                    case .succeeded: outcome = .destructionFailed(.destructionNotObserved)
                    }
                }
            }
            // Publish removal before finish can reenter. The local record pins
            // every owner through finish and synchronous cleanup, exactly once.
            prepared.lease?.finish(with: outcome)
            return withExtendedLifetime(prepared) { outcome }
        }
    }

    func attemptClose(
        expectedHandle: UInt,
        ticket: Win32CloseTicket?,
        participants: [AnyObject],
        preflight: () -> Bool,
        destroy: (UInt) -> Win32CloseNativeResult
    ) -> Win32CloseAttemptOutcome {
        var selectedRetry: DeferredWork?
        if let executingWork, executingWork.phase == .retry {
            switch executingWork.retryState {
            case .notAttempted:
                if executingWork.ticket === ticket { selectedRetry = executingWork }
            case .attempting, .continuation, .retired:
                // A second request cannot reuse a completed evaluation's
                // permission, including one rejected by the dispatch guard.
                executingWork.retryState = .retired
            }
        }
        guard activeAttempt == nil else { return .busy(.closeInProgress) }
        if ticket != nil {
            guard Win32DispatchScope.permitsTaggedClose(isOwnedRetry: selectedRetry != nil) else {
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
        selectedRetry?.retryState = .attempting(attempt)
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
            if let selectedRetry, executingWork === selectedRetry,
                case .attempting(let selectedAttempt) = selectedRetry.retryState,
                selectedAttempt === attempt
            {
                if outcome == .busy(.buildsNotSettled), let ticket, ticket.isCurrent,
                    ticket.latestDeferredNonce == selectedRetry.nonce,
                    isCurrent(
                        lifetime: lifetime, handle: expectedHandle, registration: selectedRegistration,
                        topology: selectedTopology, attempt: attempt)
                {
                    // This permit only replaces the exact executing retry.
                    // It is not document approval and never schedules itself.
                    selectedRetry.retryState = .continuation(
                        attempt, topology: selectedTopology, handle: expectedHandle)
                } else {
                    selectedRetry.retryState = .retired
                }
            }
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
            guard hasDeferredWakePoster, let registration, let authority = registration.authority,
                ticket.isCurrent, ticket.registration === registration,
                ticket.lifetime === lifetime, let handle = ticket.lifetime.handle
            else { return .unavailable }
            if let pendingWork {
                return pendingWork.ticket === ticket && pendingWork.phase == phase ? .coalesced : .busy
            }
            var continuingRetry: DeferredWork?
            if let executingWork {
                guard executingWork.ticket === ticket else { return .busy }
                if executingWork.phase == phase {
                    if phase == .prompt { return .coalesced }
                    switch executingWork.retryState {
                    case .notAttempted:
                        return .coalesced
                    case .continuation(let attempt, let topology, let expectedHandle):
                        guard activeAttempt == nil, attempt.ticket === ticket, !attempt.isUnavailable,
                            attempt.registrationEpoch == registration.ticketEpoch,
                            topologyIdentity == topology, handle == expectedHandle,
                            ticket.latestDeferredNonce == executingWork.nonce, isCurrent(executingWork)
                        else {
                            executingWork.retryState = .retired
                            return .busy
                        }
                        continuingRetry = executingWork
                    case .attempting, .retired:
                        return .busy
                    }
                } else {
                    guard executingWork.phase == .prompt, phase == .retry else { return .busy }
                }
            } else if deferredCleanupIdentities.contains(where: { $0.ticket === ticket && $0.phase == phase }) {
                // The action has returned, but its captures or promoted owner
                // are still retiring. Cleanup cannot borrow its old permit.
                return .busy
            }
            guard let nonce = wakeSequence.takeNext() else {
                continuingRetry?.retryState = .retired
                return .unavailable
            }
            let work = DeferredWork(
                ticket: ticket, phase: phase, nonce: nonce,
                onPostFailure: onPostFailure, action: action)
            // Consume before publishing the replacement. There are no callbacks
            // between the exact-record checks above and these owned mutations.
            continuingRetry?.retryState = .retired
            ticket.latestDeferredNonce = nonce
            pendingWork = work
            return withExtendedLifetime((registration, authority, work)) {
                if executingWork != nil || !deferredCleanupIdentities.isEmpty {
                    // Prompt-to-retry and an earned busy continuation both
                    // wait for the old action and its captures to unwind.
                    Win32DispatchScope.requestWakeWhenIdle(self)
                    return .queued
                }
                work.hasOutstandingWake = true
                let result = postDeferredWake(handle: handle, nonce: nonce)
                guard pendingWork === work, isCurrent(work) else {
                    if pendingWork === work { pendingWork = nil }
                    work.hasOutstandingWake = false
                    return .unavailable
                }
                switch result {
                case .accepted:
                    return .queued
                case .rejected(.postFailed(let code)):
                    pendingWork = nil
                    work.hasOutstandingWake = false
                    // The synchronous caller owns this failure; notifying its
                    // observer too would deliver the same failure twice.
                    return .postFailed(code)
                case .rejected:
                    pendingWork = nil
                    work.hasOutstandingWake = false
                    return .unavailable
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
            guard pendingWork?.nonce == nonce, pendingWork?.hasOutstandingWake == true,
                let ticket = pendingWork?.ticket, let phase = pendingWork?.phase
            else { return }
            // Keep only metadata here: retaining the record in this wrapper
            // would postpone its capture cleanup until after the marker ended.
            deferredCleanupIdentities.append(DeferredCleanupIdentity(ticket: ticket, phase: phase))
            defer {
                deferredCleanupIdentities.removeLast()
                if let pendingWork, !pendingWork.hasOutstandingWake {
                    Win32DispatchScope.requestWakeWhenIdle(self)
                }
            }
            receiveDeferredWakeWithOwners(nonce: nonce, canDeliver: canDeliver)
        }
    }

    /// An accepted owner command can later fail its real native PostMessage.
    /// Retire only that exact outstanding record. Callback captures and promoted
    /// owners finish releasing before the outer cleanup identity is removed.
    func failDeferredWake(nonce: UInt, code: UInt32) {
        Win32DispatchScope.withMailboxWork {
            guard pendingWork?.nonce == nonce, pendingWork?.hasOutstandingWake == true,
                let ticket = pendingWork?.ticket, let phase = pendingWork?.phase
            else { return }
            deferredCleanupIdentities.append(DeferredCleanupIdentity(ticket: ticket, phase: phase))
            defer {
                deferredCleanupIdentities.removeLast()
                if let pendingWork, !pendingWork.hasOutstandingWake {
                    Win32DispatchScope.requestWakeWhenIdle(self)
                }
            }
            failDeferredWakeWithOwners(nonce: nonce, code: code)
        }
    }

    private func failDeferredWakeWithOwners(nonce: UInt, code: UInt32) {
        guard let work = pendingWork, work.nonce == nonce, work.hasOutstandingWake else { return }
        let selectedRegistration = registration
        let authority = selectedRegistration?.authority
        pendingWork = nil
        work.hasOutstandingWake = false
        withExtendedLifetime((work, selectedRegistration, authority)) {
            if isCurrent(work), work.ticket.latestDeferredNonce == nonce {
                work.onPostFailure(work.ticket, code)
            }
        }
    }

    private func receiveDeferredWakeWithOwners(nonce: UInt, canDeliver: Bool) {
        let selectedRegistration = registration
        let authority = selectedRegistration?.authority
        // Both the work's captures and these promoted owners finish releasing
        // before the caller removes its cleanup identity. Nested wakes stack
        // their own identity without replacing this outer retirement boundary.
        withExtendedLifetime((selectedRegistration, authority)) {
            consumeDeferredWake(nonce: nonce, canDeliver: canDeliver)
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
        guard hasDeferredWakePoster, authority != nil, isCurrent(work), let handle = work.ticket.lifetime.handle else {
            pendingWork = nil
            return retirement(of: work, registration: selectedRegistration, authority: authority)
        }
        work.hasOutstandingWake = true
        let result = postDeferredWake(handle: handle, nonce: work.nonce)
        guard pendingWork === work, isCurrent(work) else {
            if pendingWork === work { pendingWork = nil }
            work.hasOutstandingWake = false
            return retirement(of: work, registration: selectedRegistration, authority: authority)
        }
        switch result {
        case .accepted:
            return retirement(of: work, registration: selectedRegistration, authority: authority)
        case .rejected(.postFailed(let code)):
            pendingWork = nil
            work.hasOutstandingWake = false
            return retirement(of: work, registration: selectedRegistration, authority: authority, failure: code)
        case .rejected:
            pendingWork = nil
            work.hasOutstandingWake = false
            return retirement(of: work, registration: selectedRegistration, authority: authority)
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
        topology: Foundation.UUID,
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
