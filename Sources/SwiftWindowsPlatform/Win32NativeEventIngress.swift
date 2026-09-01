import Foundation
import SwiftWindowsCore
import Synchronization

/// These limits bound retained transport entries and accounted value payload,
/// not Swift/Foundation allocation capacity or an operating-system memory cap.
/// A native producer constructs its input before attempting this admission.
struct Win32NativeIngressLimits: Equatable, Sendable {
    let maximumRecords: Int
    let maximumPayloadBytes: Int
    let maximumRecordsPerTurn: Int

    init(maximumRecords: Int = 1_024, maximumPayloadBytes: Int = 16 * 1_024 * 1_024, maximumRecordsPerTurn: Int = 32) {
        precondition(maximumRecords > 0 && maximumPayloadBytes > 0 && maximumRecordsPerTurn > 0)
        self.maximumRecords = maximumRecords
        self.maximumPayloadBytes = maximumPayloadBytes
        self.maximumRecordsPerTurn = maximumRecordsPerTurn
    }
}

/// Terminal notification has its own reserved slot. It is not an input record
/// and cannot advance the accepted or committed native input sequence.
struct Win32NativeIngressFailure: Equatable, Sendable {
    let windowKey: NativeWindowKey
    let lastAcceptedSequence: UInt64
    let failure: NativeWindowOwnerFailure
}

struct Win32NativeIngressSnapshot: Equatable, Sendable {
    let queuedRecords: Int
    let accountedPayloadBytes: Int
    let backingSlots: Int
    let hasScheduledTurn: Bool
    let lastAcceptedSequence: UInt64
    let terminalFailure: Win32NativeIngressFailure?
}

/// Only copied input crosses this queue. Automatic actor turns are finite;
/// synchronous queries drain only the already accepted captured boundary.
/// Neither operation asks the native owner for more progress or holds a lock
/// while invoking actor code.
final class Win32NativeEventIngress: Sendable {
    typealias Operation = @MainActor @Sendable () -> Void
    typealias Scheduler = @Sendable (@escaping Operation) -> Void

    private struct QueuedRecord: Sendable {
        let record: Win32NativeWindowEventRecord
        let payloadBytes: Int
    }

    private struct Terminal: Sendable {
        let value: Win32NativeIngressFailure
        var isPublished = false
        var wasDelivered = false
    }

    private struct SmokeQueueState: Sendable {
        let queueDepth: Int
        let lastAcceptedSequence: UInt64
        let automaticTurnID: UInt64?
    }

    private struct State: Sendable {
        var records: [QueuedRecord?]
        var head = 0
        var count = 0
        var payloadBytes = 0
        var automaticToken: Foundation.UUID?
        var animationOutstanding = false
        var paintOutstanding = false
        var lastAcceptedSequence: UInt64 = 0
        var terminal: Terminal?
        let smokeObservationEnabled: Bool
        var smokeTurnCounter: UInt64 = 0
        var smokeAutomaticTurnID: UInt64?

        init(capacity: Int, smokeObservationEnabled: Bool) {
            records = Array(repeating: nil, count: capacity)
            self.smokeObservationEnabled = smokeObservationEnabled
        }

        var hasWork: Bool { count > 0 || (terminal?.isPublished == true && terminal?.wasDelivered == false) }

        var smokeQueue: SmokeQueueState {
            SmokeQueueState(
                queueDepth: count, lastAcceptedSequence: lastAcceptedSequence,
                automaticTurnID: smokeAutomaticTurnID)
        }

        mutating func reserveSmokeTurnID() -> UInt64? {
            guard smokeObservationEnabled else { return nil }
            // This saturated observational label never participates in the
            // UUID reservation or in a decision to schedule or deliver work.
            if smokeTurnCounter < .max { smokeTurnCounter += 1 }
            return smokeTurnCounter
        }

        mutating func reserveTurnIfNeeded() -> Foundation.UUID? {
            guard automaticToken == nil, hasWork else { return nil }
            let token = Foundation.UUID()
            automaticToken = token
            smokeAutomaticTurnID = reserveSmokeTurnID()
            return token
        }
    }

    private let limits: Win32NativeIngressLimits
    private let state: Mutex<State>
    private let schedule: Scheduler
    private let receive: @MainActor @Sendable (Win32NativeWindowEventRecord) -> Void
    private let receiveFailure: @MainActor @Sendable (Win32NativeIngressFailure) -> Void
    let smokeObservation: Win32NativeSmokeObservation?
    @MainActor private var committedSequence: UInt64 = 0
    @MainActor private var inFlightSequence: UInt64?
    @MainActor private static var activeDeliveryCount = 0

    init(
        limits: Win32NativeIngressLimits = Win32NativeIngressLimits(),
        observation: Win32NativeSmokeObservation? = nil,
        schedule: @escaping Scheduler = { operation in Task { @MainActor in operation() } },
        receiveFailure: @escaping @MainActor @Sendable (Win32NativeIngressFailure) -> Void = { _ in },
        receive: @escaping @MainActor @Sendable (Win32NativeWindowEventRecord) -> Void
    ) {
        self.limits = limits
        state = Mutex(State(capacity: limits.maximumRecords, smokeObservationEnabled: observation != nil))
        self.schedule = schedule
        self.receiveFailure = receiveFailure
        self.receive = receive
        smokeObservation = observation
    }

    @discardableResult
    func enqueue(_ record: Win32NativeWindowEventRecord) -> Result<Void, NativeWindowOwnerFailure> {
        let payloadBytes = record.accountedPayloadBytes(upTo: limits.maximumPayloadBytes)
        let decision = state.withLock {
            stored -> (
                result: Result<Void, NativeWindowOwnerFailure>, token: Foundation.UUID?,
                kind: Win32NativeSmokeEventKind, smoke: SmokeQueueState
            ) in
            if let terminal = stored.terminal {
                return (.failure(terminal.value.failure), nil, .ingressRejected, stored.smokeQueue)
            }

            // Coalesced paint/timer gaps contain no dropped input. Only these
            // already-supported event kinds bypass another entry reservation.
            let coalesces: Bool
            switch record.event {
            case .animationFrame: coalesces = stored.animationOutstanding
            case .needsDisplay: coalesces = stored.paintOutstanding
            default: coalesces = false
            }
            if coalesces {
                stored.lastAcceptedSequence = max(
                    stored.lastAcceptedSequence, record.observation.surface.geometry.nativeSequence)
                let token = stored.reserveTurnIfNeeded()
                return (.success(()), token, .ingressCoalesced, stored.smokeQueue)
            }

            let failure: NativeWindowOwnerFailure?
            if stored.count >= limits.maximumRecords {
                failure = .capacityExceeded(resource: "nativeInputRecords", limit: limits.maximumRecords)
            } else if payloadBytes == nil || payloadBytes! > limits.maximumPayloadBytes - stored.payloadBytes {
                failure = .capacityExceeded(resource: "nativeInputPayloadBytes", limit: limits.maximumPayloadBytes)
            } else {
                failure = nil
            }
            if let failure {
                stored.terminal = Terminal(
                    value: Win32NativeIngressFailure(
                        windowKey: record.observation.surface.key,
                        lastAcceptedSequence: stored.lastAcceptedSequence, failure: failure))
                // Native code revokes its surface and publishes this reserved
                // failure after observing rejection. Never publish the rejected
                // sequence or recurse by trying to enqueue an error record.
                let token = stored.reserveTurnIfNeeded()
                return (.failure(failure), token, .ingressRejected, stored.smokeQueue)
            }

            let index = (stored.head + stored.count) % stored.records.count
            stored.records[index] = QueuedRecord(record: record, payloadBytes: payloadBytes ?? 0)
            stored.count += 1
            stored.payloadBytes += payloadBytes ?? 0
            stored.lastAcceptedSequence = max(
                stored.lastAcceptedSequence, record.observation.surface.geometry.nativeSequence)
            switch record.event {
            case .animationFrame: stored.animationOutstanding = true
            case .needsDisplay: stored.paintOutstanding = true
            default: break
            }
            let token = stored.reserveTurnIfNeeded()
            return (.success(()), token, .ingressQueued, stored.smokeQueue)
        }
        recordSmokeEvent(decision.kind, record: record, queueDepth: decision.smoke.queueDepth)
        if let token = decision.token { scheduleTurn(token, smoke: decision.smoke) }
        return decision.result
    }

    /// Revoke admission immediately and publish one terminal notification even
    /// at full capacity. Repeated failures preserve the first actual failure.
    /// Already accepted input remains FIFO; queries fail without projecting a
    /// now-revoked lifetime, including queries for an older committed sequence.
    func fail(_ failure: NativeWindowOwnerFailure, windowKey: NativeWindowKey) {
        let publication = state.withLock { stored in
            if stored.terminal == nil {
                stored.terminal = Terminal(
                    value: Win32NativeIngressFailure(
                        windowKey: windowKey, lastAcceptedSequence: stored.lastAcceptedSequence, failure: failure))
            }
            let newlyPublished = stored.terminal?.isPublished != true
            stored.terminal?.isPublished = true
            let token = stored.reserveTurnIfNeeded()
            return (failure: newlyPublished ? stored.terminal?.value : nil, token: token, smoke: stored.smokeQueue)
        }
        if let failure = publication.failure {
            smokeObservation?.record(
                .ingressFailurePublished, windowKey: failure.windowKey,
                queueDepth: UInt64(publication.smoke.queueDepth),
                nativeSequence: failure.lastAcceptedSequence,
                value: win32NativeSmokeFailureValue(failure.failure))
        }
        if let token = publication.token { scheduleTurn(token, smoke: publication.smoke) }
    }

    var snapshot: Win32NativeIngressSnapshot {
        state.withLock { stored in
            Win32NativeIngressSnapshot(
                queuedRecords: stored.count, accountedPayloadBytes: stored.payloadBytes,
                backingSlots: stored.records.count, hasScheduledTurn: stored.automaticToken != nil,
                lastAcceptedSequence: stored.lastAcceptedSequence, terminalFailure: stored.terminal?.value)
        }
    }

    @MainActor
    var smokeSnapshot: Win32NativeSmokeIngressSnapshot {
        let committed = committedSequence
        let hasInFlightRecord = inFlightSequence != nil
        return state.withLock { stored in
            Win32NativeSmokeIngressSnapshot(
                queuedRecords: stored.count, accountedPayloadBytes: stored.payloadBytes,
                backingSlots: stored.records.count, hasScheduledTurn: stored.automaticToken != nil,
                lastAcceptedSequence: stored.lastAcceptedSequence, committedSequence: committed,
                hasInFlightRecord: hasInFlightRecord, hasTerminalFailure: stored.terminal != nil)
        }
    }

    @MainActor
    func flush(through sequence: UInt64 = .max) -> Result<Void, NativeWindowOwnerFailure> {
        let beginning = state.withLock { stored in
            (
                failure: stored.terminal?.value.failure, turnID: stored.reserveSmokeTurnID(),
                smoke: stored.smokeQueue
            )
        }
        smokeObservation?.record(
            .ingressFlushBegan, queueDepth: UInt64(beginning.smoke.queueDepth), turnID: beginning.turnID,
            nativeSequence: beginning.smoke.lastAcceptedSequence, flags: 2)
        var consumed = 0
        defer {
            if let smokeObservation {
                let ending = state.withLock { $0.smokeQueue }
                smokeObservation.record(
                    .ingressFlushEnded, queueDepth: UInt64(ending.queueDepth), turnID: beginning.turnID,
                    nativeSequence: committedSequence, value: Int64(consumed), flags: 2)
            }
        }
        if let failure = beginning.failure { return .failure(failure) }
        guard inFlightSequence == nil, Self.activeDeliveryCount == 0 else {
            return .failure(.execution("Native input delivery is still in progress on MainActor"))
        }
        if sequence <= committedSequence { return .success(()) }
        let captured = state.withLock { ($0.lastAcceptedSequence, $0.count) }
        let target = sequence == .max ? captured.0 : sequence
        consumed = drain(
            through: target, maximumRecords: captured.1, smokeTurnID: beginning.turnID, smokeFlags: 2)
        if let failure = state.withLock({ $0.terminal?.value.failure }) { return .failure(failure) }
        guard committedSequence >= target else { return .failure(.unavailable) }
        return .success(())
    }

    private func scheduleTurn(_ token: Foundation.UUID, smoke: SmokeQueueState) {
        smokeObservation?.record(
            .ingressTurnScheduled, queueDepth: UInt64(smoke.queueDepth), turnID: smoke.automaticTurnID,
            nativeSequence: smoke.lastAcceptedSequence, flags: 1)
        schedule { [self] in automaticTurn(token, smokeTurnID: smoke.automaticTurnID) }
    }

    @MainActor
    private func automaticTurn(_ token: Foundation.UUID, smokeTurnID: UInt64?) {
        let beginning = state.withLock { stored -> (boundary: UInt64?, smoke: SmokeQueueState) in
            guard stored.automaticToken == token else { return (nil, stored.smokeQueue) }
            return (stored.lastAcceptedSequence, stored.smokeQueue)
        }
        guard let boundary = beginning.boundary else {
            smokeObservation?.record(
                .ingressTurnObsolete, queueDepth: UInt64(beginning.smoke.queueDepth), turnID: smokeTurnID,
                nativeSequence: beginning.smoke.lastAcceptedSequence, flags: 1)
            return
        }
        smokeObservation?.record(
            .ingressTurnBegan, queueDepth: UInt64(beginning.smoke.queueDepth), turnID: smokeTurnID,
            nativeSequence: boundary, flags: 1)
        let mayDeliver = inFlightSequence == nil && Self.activeDeliveryCount == 0
        var consumed = 0
        if mayDeliver {
            consumed = drain(
                through: boundary, maximumRecords: limits.maximumRecordsPerTurn,
                smokeTurnID: smokeTurnID, smokeFlags: 1)
        } else {
            smokeObservation?.record(
                .ingressTurnDeferred, queueDepth: UInt64(beginning.smoke.queueDepth), turnID: smokeTurnID,
                nativeSequence: boundary, flags: 1)
        }

        let continuation = state.withLock {
            stored -> (
                failure: Win32NativeIngressFailure?, next: Foundation.UUID?, valid: Bool, smoke: SmokeQueueState
            ) in
            guard stored.automaticToken == token else { return (nil, nil, false, stored.smokeQueue) }
            var terminal: Win32NativeIngressFailure?
            if mayDeliver, stored.count == 0, stored.terminal?.isPublished == true,
                stored.terminal?.wasDelivered == false
            {
                terminal = stored.terminal?.value
                stored.terminal?.wasDelivered = true
            }
            // Only an automatic task retires its reservation. A synchronous
            // flush may empty/refill the queue while that task is still queued.
            // Rotating the token also makes an obsolete task harmless.
            stored.automaticToken = nil
            stored.smokeAutomaticTurnID = nil
            let next = stored.reserveTurnIfNeeded()
            return (terminal, next, true, stored.smokeQueue)
        }
        if let failure = continuation.failure {
            Self.activeDeliveryCount += 1
            receiveFailure(failure)
            Self.activeDeliveryCount -= 1
            if let smokeObservation {
                let returned = state.withLock { $0.smokeQueue }
                smokeObservation.record(
                    .ingressFailureReturned, windowKey: failure.windowKey,
                    queueDepth: UInt64(returned.queueDepth), turnID: smokeTurnID,
                    nativeSequence: failure.lastAcceptedSequence,
                    value: win32NativeSmokeFailureValue(failure.failure), flags: 1)
            }
        }
        if let smokeObservation {
            let ending = state.withLock { $0.smokeQueue }
            if !continuation.valid {
                smokeObservation.record(
                    .ingressTurnObsolete, queueDepth: UInt64(ending.queueDepth), turnID: smokeTurnID,
                    nativeSequence: ending.lastAcceptedSequence, flags: 1)
            }
            smokeObservation.record(
                .ingressTurnEnded, queueDepth: UInt64(ending.queueDepth), turnID: smokeTurnID,
                nativeSequence: committedSequence, value: Int64(consumed), flags: 1)
        }
        if let next = continuation.next { scheduleTurn(next, smoke: continuation.smoke) }
    }

    @MainActor
    @discardableResult
    private func drain(
        through sequence: UInt64, maximumRecords: Int, smokeTurnID: UInt64?, smokeFlags: UInt32
    ) -> Int {
        var consumed = 0
        while consumed < maximumRecords, let record = takeNext(through: sequence) {
            inFlightSequence = record.observation.surface.geometry.nativeSequence
            Self.activeDeliveryCount += 1
            recordSmokeEvent(.ingressReceiveBegan, record: record, turnID: smokeTurnID, flags: smokeFlags)
            receive(record)
            recordSmokeEvent(.ingressReceiveReturned, record: record, turnID: smokeTurnID, flags: smokeFlags)
            Self.activeDeliveryCount -= 1
            committedSequence = max(committedSequence, record.observation.surface.geometry.nativeSequence)
            inFlightSequence = nil
            consumed += 1
        }
        let boundary = state.withLock { stored in
            let next = stored.count > 0 ? stored.records[stored.head]?.record : nil
            return min(
                stored.lastAcceptedSequence,
                next.map {
                    $0.observation.surface.geometry.nativeSequence == 0
                        ? 0 : $0.observation.surface.geometry.nativeSequence - 1
                } ?? UInt64.max)
        }
        committedSequence = max(committedSequence, min(sequence, boundary))
        return consumed
    }

    private func recordSmokeEvent(
        _ kind: Win32NativeSmokeEventKind, record: Win32NativeWindowEventRecord,
        queueDepth: Int? = nil, turnID: UInt64? = nil, flags: UInt32 = 0
    ) {
        guard let smokeObservation else { return }
        let probe: Win32NativeSmokeProbe?
        if case .smokeProbe(let value) = record.event {
            probe = value
        } else {
            probe = nil
        }
        let surface = record.observation.surface
        smokeObservation.record(
            kind, windowKey: surface.key, requestID: probe?.requestID, generation: surface.generation,
            queueDepth: queueDepth.map { UInt64($0) }, turnID: turnID,
            nativeSequence: surface.geometry.nativeSequence, value: probe.map { Int64($0.ordinal) }, flags: flags)
    }

    private func takeNext(through sequence: UInt64) -> Win32NativeWindowEventRecord? {
        state.withLock { stored in
            guard stored.count > 0, let first = stored.records[stored.head] else { return nil }
            guard first.record.observation.surface.geometry.nativeSequence <= sequence else { return nil }
            stored.records[stored.head] = nil
            stored.head = (stored.head + 1) % stored.records.count
            stored.count -= 1
            stored.payloadBytes -= first.payloadBytes
            switch first.record.event {
            case .animationFrame: stored.animationOutstanding = false
            case .needsDisplay: stored.paintOutstanding = false
            default: break
            }
            return first.record
        }
    }
}

extension Win32NativeWindowEventRecord {
    /// Accounts copied strings, URL spellings/array entries and touch points.
    /// Fixed record storage is independently bounded by the slot limit; this
    /// is not a measurement of Foundation caches, COW backing or OS buffers.
    fileprivate func accountedPayloadBytes(upTo limit: Int) -> Int? {
        var count = 0
        func add(_ amount: Int) -> Bool {
            guard amount >= 0, amount <= limit - count else { return false }
            count += amount
            return true
        }
        func addString(_ value: String) -> Bool { add(value.utf8.count) }
        guard addString(observation.displayIdentity) else { return nil }
        switch event {
        case .textInput(let value):
            guard addString(value) else { return nil }
        case .imeComposition(let event):
            switch event.phase {
            case .updated(let value), .committed(let value):
                guard addString(value) else { return nil }
            case .started, .ended: break
            }
        case .touch(_, let points):
            let bytes = points.count.multipliedReportingOverflow(by: MemoryLayout<Point>.stride)
            guard !bytes.overflow, add(bytes.partialValue) else { return nil }
        case .filesDropped(let payload):
            let bytes = payload.fileURLs.count.multipliedReportingOverflow(by: MemoryLayout<URL>.stride)
            guard !bytes.overflow, add(bytes.partialValue) else { return nil }
            for url in payload.fileURLs {
                guard addString(url.absoluteString) else { return nil }
            }
        case .ownerFailure(let failure):
            switch failure {
            case .execution(let value), .native(let value, _), .capacityExceeded(let value, _):
                guard addString(value) else { return nil }
            default: break
            }
        default: break
        }
        return count
    }
}
