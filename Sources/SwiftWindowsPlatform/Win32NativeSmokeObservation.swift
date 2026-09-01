import Dispatch
import Foundation
import SwiftWindowsCore
import Synchronization
import WinSDK

/// Fixed vocabulary for the one-window native qualification executable.
/// These observations never schedule work, drive a window, or substitute a
/// result. Normal application instances have no observation owner.
package enum Win32NativeSmokeEventKind: UInt16, CaseIterable, Sendable {
    case fixtureStarted
    case fixtureFailure
    case hostReady
    case modelStarted
    case modelFirstAwait
    case modelFirstReleased
    case modelFirstResumed
    case modelSecondAwait
    case idleBegan
    case idleEnded
    case modelSecondReleased
    case modelSecondResumed
    case modelFinished
    case ownedWorkloadSubmitted
    case ownedCommandReply
    case nativeQueryStarted
    case nativeQueryCompleted
    case actorQueryEntered
    case nestedQueryCompleted
    case externalQueryStarted
    case publicationGateEntered
    case publicationGateOpened
    case externalQueryCompleted
    case staleCommandRejected
    case fixtureFinished
    case providerAcquired
    case publicationGateArmed
    case coordinatorReturned
    case externalResourcesReleased
    case actorIdleBoundary
    case framePrepared
    case frameReplyReceived
    case frameReplyConsumed
    case frameSubmitted
    case uiARevoked
    case presentationDetached
    case actorCloseConsumed
    case actorStopConsumed
    case nativeThreadEntered
    case nativeCOMInitialized
    case nativeOwnerReady
    case nativeWakePostAttempt
    case nativeWakePostSucceeded
    case nativeWakePostFailed
    case nativeWakeReceived
    case nativeWakeDeferred
    case nativeTurnBegan
    case nativeTurnEnded
    case nativeWorkDequeued
    case nativeQueueSnapshot
    case nativeMessageDispatched
    case nativeDispatchReturned
    case nativeWindowCreated
    case nativeWindowNonClientDestroyed
    case nativeAttachmentDetached
    case nativeCloseDispatchUnwound
    case nativeCloseAwaitingAttachments
    case nativeCloseReplyReady
    case nativeCloseReplyReturned
    case nativeOwnerFailure
    case nativeThreadTerminated
    case nativeThreadJoined
    case nativeJoinFailed
    case nativeTimerState
    case nativeTimerAPIResult
    case nativeAnimationCallback
    case nativeAnimationPost
    case nativeAnimationMessage
    case ingressQueued
    case ingressCoalesced
    case ingressRejected
    case ingressTurnScheduled
    case ingressTurnBegan
    case ingressTurnEnded
    case ingressTurnObsolete
    case ingressTurnDeferred
    case ingressFlushBegan
    case ingressFlushEnded
    case ingressReceiveBegan
    case ingressReceiveReturned
    case ingressFailurePublished
    case ingressFailureReturned
    case ingressSnapshot
    case smokeProbeEmitted
    case publicationGateReleaseRequested
}

package enum Win32NativeSmokeTimerFlags {
    package static let highResolutionInstalled: UInt32 = 1 << 0
    package static let windowTimerInstalled: UInt32 = 1 << 1
    package static let resolutionOwned: UInt32 = 1 << 2
    package static let closeWatchdogInstalled: UInt32 = 1 << 3
    /// A failed native timer operation prevents interpreting cached absence
    /// as proof that every operating-system timer was removed.
    package static let stateUncertain: UInt32 = 1 << 4
}

package enum Win32NativeSmokeTimerOperation: UInt64, Sendable {
    case createHighResolution
    case deleteHighResolution
    case setWindowTimer
    case killWindowTimer
    case beginResolution
    case endResolution
    case setCloseWatchdog
    case killCloseWatchdog
}

package struct Win32NativeSmokeRecord: Equatable, Sendable {
    package let ordinal: UInt64
    package let kind: Win32NativeSmokeEventKind
    package let uptimeNanoseconds: UInt64
    package let threadID: UInt32
    package let windowKey: NativeWindowKey?
    package let requestID: NativeWindowRequestID?
    package let attachmentID: NativeWindowAttachmentID?
    package let generation: UInt64?
    package let deviceGeneration: UInt64?
    package let frameNumber: UInt64?
    package let nativeStartedAtSeconds: Double?
    package let nativeCompletedAtSeconds: Double?
    package let queueDepth: UInt64?
    package let turnID: UInt64?
    package let nativeSequence: UInt64?
    package let revision: UInt64?
    package let value: Int64?
    package let auxiliary: UInt64?
    package let flags: UInt32

    /// Only fixed keys, finite number spellings and UUIDs enter this encoding.
    /// Native receipt times keep their original epoch; they are never compared
    /// with this recorder's uptime clock. There is no arbitrary payload.
    fileprivate func jsonLine(runID: Foundation.UUID) -> String {
        var fields = [
            "\"runID\":\"\(runID.uuidString)\"",
            "\"ordinal\":\(ordinal)",
            "\"kind\":\(kind.rawValue)",
            "\"uptimeNanoseconds\":\(uptimeNanoseconds)",
            "\"threadID\":\(threadID)",
        ]
        if let windowKey {
            fields.append("\"windowID\":\"\(windowKey.windowID.uuidString)\"")
            fields.append("\"lifetimeID\":\"\(windowKey.lifetimeID.uuidString)\"")
        }
        if let requestID { fields.append("\"requestID\":\"\(requestID.rawValue.uuidString)\"") }
        if let attachmentID { fields.append("\"attachmentID\":\"\(attachmentID.rawValue.uuidString)\"") }
        if let generation { fields.append("\"generation\":\(generation)") }
        if let deviceGeneration { fields.append("\"deviceGeneration\":\(deviceGeneration)") }
        if let frameNumber { fields.append("\"frameNumber\":\(frameNumber)") }
        if let nativeStartedAtSeconds { fields.append("\"nativeStartedAtSeconds\":\(nativeStartedAtSeconds)") }
        if let nativeCompletedAtSeconds { fields.append("\"nativeCompletedAtSeconds\":\(nativeCompletedAtSeconds)") }
        if let queueDepth { fields.append("\"queueDepth\":\(queueDepth)") }
        if let turnID { fields.append("\"turnID\":\(turnID)") }
        if let nativeSequence { fields.append("\"nativeSequence\":\(nativeSequence)") }
        if let revision { fields.append("\"revision\":\(revision)") }
        if let value { fields.append("\"value\":\(value)") }
        if let auxiliary { fields.append("\"auxiliary\":\(auxiliary)") }
        fields.append("\"flags\":\(flags)")
        return "{" + fields.joined(separator: ",") + "}\n"
    }
}

package struct Win32NativeSmokeObservationSnapshot: Sendable {
    package let runID: Foundation.UUID
    package let recordCount: Int
    package let encodedBytes: Int
    package let overflowed: Bool
    package let hasNonfiniteTiming: Bool
    /// Recorded probe returns, not a claim that their identities are unique.
    /// The final validator separately checks exactly 64 distinct FIFO probes.
    package let deliveredProbeCount: UInt64
    fileprivate let counts: [UInt64]
    fileprivate let latest: [Win32NativeSmokeRecord?]

    package var isInvalid: Bool { overflowed || hasNonfiniteTiming }

    package func count(_ kind: Win32NativeSmokeEventKind) -> UInt64 {
        counts[Int(kind.rawValue)]
    }

    package func last(_ kind: Win32NativeSmokeEventKind) -> Win32NativeSmokeRecord? {
        latest[Int(kind.rawValue)]
    }
}

package struct Win32NativeSmokeCapture: Sendable {
    package let snapshot: Win32NativeSmokeObservationSnapshot
    package let trace: Data
}

/// One bounded per-instance record buffer. Counters and last-per-kind values
/// have a fixed size determined by the enum, not an observer registry.
package final class Win32NativeSmokeObservation: Sendable {
    package static let maximumRecords = 4_096
    package static let maximumEncodedBytes = 1_024 * 1_024

    private struct State: Sendable {
        var records: [Win32NativeSmokeRecord] = []
        var encodedBytes = 0
        var overflowed = false
        var hasNonfiniteTiming = false
        var deliveredProbeCount: UInt64 = 0
        var counts = Array(repeating: UInt64(0), count: Win32NativeSmokeEventKind.allCases.count)
        var latest = [Win32NativeSmokeRecord?](
            repeating: nil, count: Win32NativeSmokeEventKind.allCases.count)
    }

    package let runID: Foundation.UUID
    /// Only the independent fixture controller may block on this semaphore.
    /// A and N only signal it, after the observation lock has been released.
    /// There are at most maximumRecords successful-record signals plus one
    /// invalidity signal. No task, periodic timer or callback is installed.
    package let activity = DispatchSemaphore(value: 0)
    private let state = Mutex(State())

    package init(runID: Foundation.UUID) { self.runID = runID }

    @discardableResult
    package func record(
        _ kind: Win32NativeSmokeEventKind,
        windowKey: NativeWindowKey? = nil,
        requestID: NativeWindowRequestID? = nil,
        attachmentID: NativeWindowAttachmentID? = nil,
        generation: UInt64? = nil,
        deviceGeneration: UInt64? = nil,
        frameNumber: UInt64? = nil,
        nativeStartedAtSeconds: Double? = nil,
        nativeCompletedAtSeconds: Double? = nil,
        queueDepth: UInt64? = nil,
        turnID: UInt64? = nil,
        nativeSequence: UInt64? = nil,
        revision: UInt64? = nil,
        value: Int64? = nil,
        auxiliary: UInt64? = nil,
        flags: UInt32 = 0
    ) -> Bool {
        let timestamp = DispatchTime.now().uptimeNanoseconds
        let threadID = GetCurrentThreadId()
        let outcome = state.withLock { stored -> (recorded: Bool, signal: Bool) in
            guard !stored.overflowed && !stored.hasNonfiniteTiming else { return (false, false) }
            guard nativeStartedAtSeconds?.isFinite ?? true,
                nativeCompletedAtSeconds?.isFinite ?? true
            else {
                stored.hasNonfiniteTiming = true
                return (false, true)
            }
            let record = Win32NativeSmokeRecord(
                ordinal: UInt64(stored.records.count) + 1, kind: kind,
                uptimeNanoseconds: timestamp, threadID: threadID,
                windowKey: windowKey, requestID: requestID, attachmentID: attachmentID, generation: generation,
                deviceGeneration: deviceGeneration, frameNumber: frameNumber,
                nativeStartedAtSeconds: nativeStartedAtSeconds, nativeCompletedAtSeconds: nativeCompletedAtSeconds,
                queueDepth: queueDepth, turnID: turnID,
                nativeSequence: nativeSequence, revision: revision, value: value,
                auxiliary: auxiliary, flags: flags)
            let bytes = record.jsonLine(runID: runID).utf8.count
            guard stored.records.count < Self.maximumRecords,
                bytes <= Self.maximumEncodedBytes - stored.encodedBytes
            else {
                stored.overflowed = true
                return (false, true)
            }
            stored.records.append(record)
            stored.encodedBytes += bytes
            stored.counts[Int(kind.rawValue)] += 1
            if kind == .ingressReceiveReturned, requestID != nil { stored.deliveredProbeCount += 1 }
            stored.latest[Int(kind.rawValue)] = record
            return (true, true)
        }
        if outcome.signal { activity.signal() }
        return outcome.recorded
    }

    package func snapshot() -> Win32NativeSmokeObservationSnapshot {
        state.withLock { stored in
            Win32NativeSmokeObservationSnapshot(
                runID: runID, recordCount: stored.records.count, encodedBytes: stored.encodedBytes,
                overflowed: stored.overflowed, hasNonfiniteTiming: stored.hasNonfiniteTiming,
                deliveredProbeCount: stored.deliveredProbeCount,
                counts: stored.counts, latest: stored.latest)
        }
    }

    /// Event-driven controller wait, never an actor or native-owner wait.
    package func waitForActivity(until deadline: DispatchTime) -> Bool {
        activity.wait(timeout: deadline) == .success
    }

    /// Serialization and eventual file I/O occur outside all transport locks.
    /// This immutable capture has the exact byte count charged on admission.
    package func capture() -> Win32NativeSmokeCapture {
        let captured = state.withLock { stored in
            (
                Win32NativeSmokeObservationSnapshot(
                    runID: runID, recordCount: stored.records.count, encodedBytes: stored.encodedBytes,
                    overflowed: stored.overflowed, hasNonfiniteTiming: stored.hasNonfiniteTiming,
                    deliveredProbeCount: stored.deliveredProbeCount,
                    counts: stored.counts, latest: stored.latest),
                stored.records
            )
        }
        var trace = Data()
        trace.reserveCapacity(captured.0.encodedBytes)
        for record in captured.1 { trace.append(contentsOf: record.jsonLine(runID: runID).utf8) }
        return Win32NativeSmokeCapture(snapshot: captured.0, trace: trace)
    }
}

package struct Win32NativeSmokePumpSnapshot: Equatable, Sendable {
    package let queuedWork: Int
    package let queuedCommands: Int
    package let queuedCloseRequests: Int
    package let queuedDeferredCloseWakes: Int
    package let storageCapacity: Int
    package let ownedWindows: Int
    package let reservedCloses: Int
    package let startWaiters: Int
    package let stopWaiters: Int
    package let hasStopReservation: Bool
    package let observationEnabled: Bool
    package let nativeTurnActive: Bool
    package let nativeWorkInFlight: Bool
    /// The mailbox intentionally keeps this identity until its next dequeue;
    /// it is not proof that the associated native operation is still running.
    package let hasExecutingReplyPin: Bool
}

package struct Win32NativeSmokeIngressSnapshot: Equatable, Sendable {
    package let queuedRecords: Int
    package let accountedPayloadBytes: Int
    package let backingSlots: Int
    package let hasScheduledTurn: Bool
    package let lastAcceptedSequence: UInt64
    package let committedSequence: UInt64
    package let hasInFlightRecord: Bool
    package let hasTerminalFailure: Bool
}

/// This is fixture traffic, not an operating-system input event.
package struct Win32NativeSmokeProbe: Equatable, Sendable {
    package let requestID: NativeWindowRequestID
    package let ordinal: UInt32
}

/// Only a supplied native numeric error is recorded as a native error code.
/// Logical failures keep a nil code rather than inventing a Win32 success or
/// mapping an arbitrary message onto an unrelated operating-system error.
func win32NativeSmokeFailureValue(_ failure: NativeWindowOwnerFailure) -> Int64? {
    switch failure {
    case .postFailed(let code): return Int64(code)
    case .native(_, let code): return code
    default: return nil
    }
}
