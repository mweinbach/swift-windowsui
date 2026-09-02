import Foundation
import SwiftWindowsCore
import Synchronization

/// Actor-owned lifetime values only. The caller also supplies the actual
/// ingress identities; a copied key cannot validate an old retained operation.
struct Win32NativeSmokeIngressBindingState: Sendable {
    var windowKey: NativeWindowKey?
    var surfaceKey: NativeWindowKey?
    var closeLifetimeID: Foundation.UUID?
    var hasNativeOwner = false
    var startInProgress = false
    var closeInProgress = false
    var closePrepared = false
    var willCloseDelivered = false
    var destructionObserved = false
    var terminalCloseDelivered = false
    var ownerFailed = false
    var creationFailed = false
    var destructionStarted = false
    var destructionCompleted = false
}

@MainActor
func win32NativeSmokeCurrentIngressSnapshot(
    expectedIngress: Win32NativeEventIngress, currentIngress: Win32NativeEventIngress?,
    expectedKey: NativeWindowKey, state: Win32NativeSmokeIngressBindingState
) -> Win32NativeSmokeIngressSnapshot? {
    guard currentIngress === expectedIngress, state.windowKey == expectedKey, state.surfaceKey == expectedKey,
        state.closeLifetimeID == expectedKey.lifetimeID, state.hasNativeOwner,
        !state.startInProgress, !state.closeInProgress, !state.closePrepared, !state.willCloseDelivered,
        !state.destructionObserved, !state.terminalCloseDelivered, !state.ownerFailed,
        !state.creationFailed, !state.destructionStarted, !state.destructionCompleted
    else { return nil }
    return expectedIngress.smokeSnapshot
}

/// Only the fixed owned smoke fixture installs this setup. It can retain one
/// original automatic operation before measurement; explicit flush is never
/// routed here. Once opened, every successor keeps the original one-Task hop.
package final class Win32NativeSmokeIngressSetup: Sendable {
    package enum Failure: String, Equatable, Sendable {
        case duplicateReporter = "duplicate-reporter"
        case invalidBinding = "invalid-binding"
        case invalidArm = "invalid-arm"
        case invalidRequest = "invalid-request"
        case duplicateRequest = "duplicate-request"
        case invalidReceipt = "invalid-receipt"
        case duplicateReceipt = "duplicate-receipt"
        case unorderedReceipt = "unordered-receipt"
        case duplicateFirstRelease = "duplicate-first-release"
        case multipleOperations = "multiple-operations"
        case modelUnavailable = "model-unavailable"
        case currentBindingUnavailable = "current-binding-unavailable"
        case ingressUnavailable = "ingress-unavailable"
    }

    /// Invoked is not a claim that the mounted task ran or beat a successor.
    package enum FirstReleaseResult: Equatable, Sendable {
        case invoked
        case unavailable
    }

    package typealias FirstRelease = @MainActor @Sendable () -> FirstReleaseResult
    package typealias FailureReporter = @Sendable (Failure) -> Void
    typealias Operation = Win32NativeEventIngress.Operation
    typealias Scheduler = Win32NativeEventIngress.Scheduler
    typealias CurrentSnapshot = @MainActor @Sendable () -> Win32NativeSmokeIngressSnapshot?

    enum Phase: Equatable, Sendable {
        case dormant
        case collecting
        case selected
        case open
        case aborted
    }

    struct Snapshot: Sendable {
        let phase: Phase
        let registeredCount: Int
        let suffixReceiptCount: Int
        let hasHeldOperation: Bool
        let candidatePending: Bool
        let firstReleaseRequested: Bool
        let firstReleaseClaimed: Bool
        let firstReleaseFinished: Bool
        let prepared: Bool
        let firstFailure: Failure?

        var isIdleReady: Bool {
            (phase == .open || phase == .aborted) && !hasHeldOperation && !candidatePending
                && (!firstReleaseRequested || firstReleaseFinished)
        }
    }

    private struct Receipt: Sendable {
        let generation: UInt64
        let sequence: UInt64
    }

    private struct Entry: Sendable {
        let requestID: NativeWindowRequestID
        var receipt: Receipt? = nil
    }

    /// The task, not the gate, owns these values after selection. Taking them
    /// once also keeps an abort or repeated invocation from duplicating delivery.
    private final class Candidate: Sendable {
        struct Payload: Sendable {
            let operation: Operation
            let firstRelease: FirstRelease
            let firstSequence: UInt64
            let lastSequence: UInt64
        }

        private let payload: Mutex<Payload?>

        init(_ value: Payload) { payload = Mutex<Payload?>(value) }

        func take() -> Payload? {
            payload.withLock { stored in
                let previous = stored
                stored = nil
                return previous
            }
        }
    }

    private struct State: Sendable {
        var phase = Phase.dormant
        var windowKey: NativeWindowKey?
        var entries = [Entry?](repeating: nil, count: 64)
        var registeredCount = 0
        var suffixReceiptCount = 0
        var heldOperation: Operation?
        var firstRelease: FirstRelease?
        var firstReleaseRequested = false
        var firstReleaseClaimed = false
        var firstReleaseFinished = false
        var candidatePending = false
        var prepared = false
        var failureReporter: FailureReporter?
        var firstFailure: Failure?

        mutating func takeCandidate() -> Candidate? {
            guard phase == .collecting, registeredCount == 64, suffixReceiptCount == 33,
                firstReleaseRequested, !firstReleaseClaimed,
                let operation = heldOperation, let release = firstRelease,
                let first = entries[31]?.receipt, let last = entries[63]?.receipt
            else { return nil }
            heldOperation = nil
            firstRelease = nil
            firstReleaseClaimed = true
            candidatePending = true
            phase = .selected
            return Candidate(
                Candidate.Payload(
                    operation: operation, firstRelease: release,
                    firstSequence: first.sequence, lastSequence: last.sequence))
        }
    }

    private let state = Mutex(State())
    private let scheduleActor: Scheduler
    @MainActor private var currentSnapshot: CurrentSnapshot?

    package convenience init() {
        self.init(scheduleActor: { operation in Task { @MainActor in operation() } })
    }

    /// A copied-operation driver lets pure tests choose either next actor job.
    /// The fixture always uses the package initializer's original Task route.
    init(scheduleActor: @escaping Scheduler) { self.scheduleActor = scheduleActor }

    deinit {
        let detached = takeAbortWork()
        let reporter = state.withLock { $0.failureReporter }
        if let operation = detached.operation { scheduleActor(operation) }
        if let release = detached.release {
            // No self escapes destruction. Preserve only the original pending
            // release and report an unavailable target through the weak reporter.
            scheduleActor {
                if case .unavailable = release() { reporter?(.modelUnavailable) }
            }
        }
        withExtendedLifetime(detached) {}
    }

    package func installFailureReporter(_ reporter: @escaping FailureReporter) {
        let result = state.withLock { stored -> (installed: Bool, previousFailure: Failure?) in
            guard stored.failureReporter == nil else { return (false, nil) }
            stored.failureReporter = reporter
            return (true, stored.firstFailure)
        }
        if !result.installed {
            fail(.duplicateReporter)
        } else if let failure = result.previousFailure {
            reporter(failure)
        }
        withExtendedLifetime(reporter) {}
    }

    @MainActor
    func bind(windowKey: NativeWindowKey, currentSnapshot: @escaping CurrentSnapshot) {
        let accepted = state.withLock { stored in
            guard stored.phase == .dormant, stored.windowKey == nil else { return false }
            stored.windowKey = windowKey
            return true
        }
        if accepted {
            self.currentSnapshot = currentSnapshot
        } else {
            fail(.invalidBinding)
        }
        withExtendedLifetime(currentSnapshot) {}
    }

    @MainActor
    package func arm(windowKey: NativeWindowKey) -> Bool {
        let hasSnapshotReader = currentSnapshot != nil
        let accepted = state.withLock { stored in
            guard stored.phase == .dormant, stored.windowKey == windowKey, hasSnapshotReader,
                stored.failureReporter != nil, !stored.firstReleaseRequested
            else { return false }
            stored.phase = .collecting
            return true
        }
        if !accepted { fail(.invalidArm) }
        return accepted
    }

    package func register(ordinal: UInt32, requestID: NativeWindowRequestID, windowKey: NativeWindowKey) {
        let failure = state.withLock { stored -> Failure? in
            if stored.phase == .aborted { return nil }
            guard stored.phase == .collecting, ordinal < 64, stored.windowKey == windowKey else {
                return .invalidRequest
            }
            guard stored.entries[Int(ordinal)] == nil,
                !stored.entries.contains(where: { $0?.requestID == requestID })
            else { return .duplicateRequest }
            stored.entries[Int(ordinal)] = Entry(requestID: requestID)
            stored.registeredCount += 1
            return nil
        }
        if let failure { fail(failure) }
    }

    /// The caller invokes this only after its unchanged successful reply
    /// observation. That success follows real emit/enqueue, not mailbox admission.
    package func noteSuccessfulReply(
        ordinal: UInt32, requestID: NativeWindowRequestID, surface: NativeWindowSurface
    ) {
        let result = state.withLock { stored -> (failure: Failure?, candidate: Candidate?) in
            if stored.phase == .aborted { return (nil, nil) }
            guard ordinal < 64, stored.windowKey == surface.key,
                var entry = stored.entries[Int(ordinal)], entry.requestID == requestID
            else { return (.invalidReceipt, nil) }
            guard entry.receipt == nil else { return (.duplicateReceipt, nil) }
            let sequence = surface.geometry.nativeSequence
            for index in stored.entries.indices {
                guard let receipt = stored.entries[index]?.receipt else { continue }
                if index < Int(ordinal) ? receipt.sequence >= sequence : receipt.sequence <= sequence {
                    return (.unorderedReceipt, nil)
                }
            }
            entry.receipt = Receipt(generation: surface.generation, sequence: sequence)
            stored.entries[Int(ordinal)] = entry
            if ordinal >= 31 { stored.suffixReceiptCount += 1 }
            return (nil, stored.takeCandidate())
        }
        if let failure = result.failure { fail(failure) }
        if let candidate = result.candidate { dispatchCandidate(candidate) }
    }

    @MainActor
    package func requestFirstRelease(_ release: @escaping FirstRelease) {
        let result = state.withLock { stored -> (failure: Failure?, direct: Bool, candidate: Candidate?) in
            guard !stored.firstReleaseRequested else { return (.duplicateFirstRelease, false, nil) }
            stored.firstReleaseRequested = true
            switch stored.phase {
            case .dormant, .open, .aborted:
                stored.firstReleaseClaimed = true
                return (nil, true, nil)
            case .collecting, .selected:
                stored.firstRelease = release
                return (nil, false, stored.takeCandidate())
            }
        }
        if let failure = result.failure { fail(failure) }
        if result.direct { _ = forwardFirstRelease(release) }
        if let candidate = result.candidate { dispatchCandidate(candidate) }
        withExtendedLifetime(release) {}
    }

    func makeScheduler() -> Scheduler {
        let scheduleActor = self.scheduleActor
        return { [weak self] operation in
            guard let self else {
                scheduleActor(operation)
                return
            }
            self.schedule(operation)
        }
    }

    private func schedule(_ operation: @escaping Operation) {
        let open = state.withLock { $0.phase == .open || $0.phase == .aborted }
        if open {
            scheduleActor(operation)
        } else {
            scheduleActor { [weak self] in
                // An earlier posted task may execute after arm or open. Nil
                // setup and open both deliver directly, without a second hop.
                guard let self else {
                    operation()
                    return
                }
                self.invokeOrHold(operation)
            }
        }
    }

    @MainActor
    private func invokeOrHold(_ operation: @escaping Operation) {
        let result = state.withLock { stored -> (direct: Bool, failure: Failure?, candidate: Candidate?) in
            switch stored.phase {
            case .dormant, .open, .aborted:
                return (true, nil, nil)
            case .selected:
                return (true, .multipleOperations, nil)
            case .collecting:
                guard stored.heldOperation == nil else { return (true, .multipleOperations, nil) }
                stored.heldOperation = operation
                return (false, nil, stored.takeCandidate())
            }
        }
        if let failure = result.failure { fail(failure) }
        if let candidate = result.candidate { runCandidate(candidate) }
        if result.direct { operation() }
        withExtendedLifetime(operation) {}
    }

    private func dispatchCandidate(_ candidate: Candidate) {
        scheduleActor { [weak self] in
            if let self {
                self.runCandidate(candidate)
            } else if let payload = candidate.take() {
                // Preserve an already claimed original release, but no setup
                // exists to claim preparation or model progress.
                _ = payload.firstRelease()
                payload.operation()
            }
        }
    }

    @MainActor
    private func runCandidate(_ candidate: Candidate) {
        guard let payload = candidate.take() else { return }
        defer {
            // Every path delivers the same original operation exactly once.
            payload.operation()
            state.withLock { $0.candidatePending = false }
        }
        guard forwardFirstRelease(payload.firstRelease) else { return }
        guard state.withLock({ $0.phase == .selected && $0.firstFailure == nil }) else { return }
        guard let snapshot = currentSnapshot?() else {
            fail(.currentBindingUnavailable)
            return
        }
        guard !snapshot.hasInFlightRecord, !snapshot.hasTerminalFailure, snapshot.hasScheduledTurn else {
            fail(.ingressUnavailable)
            return
        }
        guard snapshot.queuedRecords >= 33, snapshot.lastAcceptedSequence >= payload.lastSequence,
            snapshot.committedSequence < payload.firstSequence
        else {
            // A legitimate intervening flush invalidates preparation. Open
            // permanently; never refill, rearm, or manufacture a full turn.
            abort()
            return
        }
        // No callback or await separates the current actor snapshot, this
        // transition, and the raw operation in defer. Native producers only add.
        state.withLock { stored in
            if stored.phase == .selected && stored.firstFailure == nil {
                stored.phase = .open
                stored.prepared = true
            }
        }
    }

    @MainActor
    private func forwardFirstRelease(_ release: FirstRelease) -> Bool {
        let result = release()
        state.withLock { $0.firstReleaseFinished = true }
        switch result {
        case .invoked: return true
        case .unavailable:
            fail(.modelUnavailable)
            return false
        }
    }

    package func abort() {
        let detached = takeAbortWork()
        // No operation, relay, callback, or captured value is released while
        // holding the mutex. A selected candidate already owns its own values.
        if let operation = detached.operation { scheduleActor(operation) }
        if let release = detached.release {
            scheduleActor { [weak self] in
                if let self {
                    _ = self.forwardFirstRelease(release)
                } else {
                    _ = release()
                }
            }
        }
        withExtendedLifetime(detached) {}
    }

    private func takeAbortWork() -> (operation: Operation?, release: FirstRelease?) {
        state.withLock { stored in
            stored.phase = .aborted
            let operation = stored.heldOperation
            stored.heldOperation = nil
            var release: FirstRelease?
            if stored.firstReleaseRequested, !stored.firstReleaseClaimed {
                release = stored.firstRelease
                stored.firstRelease = nil
                stored.firstReleaseClaimed = true
            }
            return (operation, release)
        }
    }

    private func fail(_ failure: Failure) {
        let reporter = state.withLock { stored -> FailureReporter? in
            guard stored.firstFailure == nil else { return nil }
            stored.firstFailure = failure
            return stored.failureReporter
        }
        abort()
        reporter?(failure)
    }

    var snapshot: Snapshot {
        state.withLock { stored in
            Snapshot(
                phase: stored.phase, registeredCount: stored.registeredCount,
                suffixReceiptCount: stored.suffixReceiptCount, hasHeldOperation: stored.heldOperation != nil,
                candidatePending: stored.candidatePending, firstReleaseRequested: stored.firstReleaseRequested,
                firstReleaseClaimed: stored.firstReleaseClaimed, firstReleaseFinished: stored.firstReleaseFinished,
                prepared: stored.prepared, firstFailure: stored.firstFailure)
        }
    }

    package var isIdleReady: Bool { snapshot.isIdleReady }
}
