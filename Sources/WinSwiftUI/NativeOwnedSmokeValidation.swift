import Foundation
import SwiftWindowsPlatform

/// The validator reads only the fixed scalar trace schema. It does not query
/// a window, repair a missing record, or infer execution from a source plan.
struct NativeOwnedSmokeTraceRow: Decodable, Sendable {
    let runID: String
    let ordinal: UInt64
    let kind: UInt16
    let uptimeNanoseconds: UInt64
    let threadID: UInt32
    let windowID: String?
    let lifetimeID: String?
    let requestID: String?
    let attachmentID: String?
    let generation: UInt64?
    let deviceGeneration: UInt64?
    let frameNumber: UInt64?
    let nativeStartedAtSeconds: Double?
    let nativeCompletedAtSeconds: Double?
    let nativeSequence: UInt64?
    let revision: UInt64?
    let queueDepth: UInt64?
    let turnID: UInt64?
    let value: Int64?
    let auxiliary: UInt64?
    let flags: UInt32

    func isKind(_ value: Win32NativeSmokeEventKind) -> Bool { kind == value.rawValue }
}

struct NativeOwnedSmokeVerdict: Sendable, Encodable {
    let predicates: [String: Bool]
    let insufficientFairnessExercise: Bool

    var qualifyingPredicatesSatisfied: Bool { predicates.values.allSatisfy { $0 } }
}

enum NativeOwnedSmokeValidation {
    static let idleQuietKinds: [Win32NativeSmokeEventKind] = [
        .nativeWakePostAttempt, .nativeWakeReceived, .nativeTurnBegan, .nativeWorkDequeued,
        .nativeMessageDispatched, .nativeAnimationCallback, .nativeAnimationPost, .nativeAnimationMessage,
        .nativeTimerAPIResult, .ingressQueued, .ingressCoalesced, .ingressRejected,
        .ingressTurnBegan, .ingressFlushBegan, .framePrepared, .frameReplyReceived, .frameReplyConsumed,
    ]

    static func decode(_ data: Data) throws -> [NativeOwnedSmokeTraceRow] {
        guard data.count <= Win32NativeSmokeObservation.maximumEncodedBytes else {
            throw NativeOwnedSmokeFailure("trace-byte-cap-exceeded")
        }
        let lines = data.split(separator: 10)
        guard lines.count <= Win32NativeSmokeObservation.maximumRecords else {
            throw NativeOwnedSmokeFailure("trace-record-cap-exceeded")
        }
        let decoder = JSONDecoder()
        return try lines.map { try decoder.decode(NativeOwnedSmokeTraceRow.self, from: Data($0)) }
    }

    static func evaluate(
        _ rows: [NativeOwnedSmokeTraceRow], observation: Win32NativeSmokeObservationSnapshot,
        state: NativeOwnedSmokeSharedState.Snapshot
    ) -> NativeOwnedSmokeVerdict {
        func all(_ kind: Win32NativeSmokeEventKind) -> [NativeOwnedSmokeTraceRow] { rows.filter { $0.isKind(kind) } }
        func one(_ kind: Win32NativeSmokeEventKind) -> NativeOwnedSmokeTraceRow? {
            let values = all(kind)
            return values.count == 1 ? values.first : nil
        }
        func one(_ kind: Win32NativeSmokeEventKind, requestID: String) -> NativeOwnedSmokeTraceRow? {
            let values = all(kind).filter { $0.requestID == requestID }
            return values.count == 1 ? values.first : nil
        }
        func belongsToWindow(_ row: NativeOwnedSmokeTraceRow) -> Bool {
            guard let key = state.windowKey else { return false }
            return row.windowID == key.windowID.uuidString && row.lifetimeID == key.lifetimeID.uuidString
        }
        func ordered(_ kinds: [Win32NativeSmokeEventKind]) -> Bool {
            var previous: UInt64 = 0
            for kind in kinds {
                guard let record = one(kind), record.ordinal > previous else { return false }
                previous = record.ordinal
            }
            return true
        }
        var checks: [String: Bool] = [:]
        checks["bounded-valid-observation"] =
            !observation.isInvalid
            && rows.count == observation.recordCount && rows.count <= 4_096 && observation.encodedBytes <= 1_048_576
        checks["single-run-contiguous-trace"] = rows.enumerated().allSatisfy {
            $0.element.ordinal == UInt64($0.offset + 1) && $0.element.runID == observation.runID.uuidString
                && $0.element.threadID != 0
        }
        checks["one-owned-window-lifetime"] =
            state.windowKey != nil
            && one(.hostReady).map(belongsToWindow) == true
            && one(.nativeWindowCreated).map(belongsToWindow) == true
            && one(.nativeWindowNonClientDestroyed).map(belongsToWindow) == true
            && rows.allSatisfy { ($0.windowID == nil && $0.lifetimeID == nil) || belongsToWindow($0) }
        checks["no-fixture-or-owner-failure"] =
            state.failures.isEmpty
            && all(.fixtureFailure).isEmpty && all(.nativeOwnerFailure).isEmpty && all(.nativeJoinFailed).isEmpty
            && all(.nativeWakePostFailed).isEmpty && all(.ingressRejected).isEmpty
            && all(.ingressFailurePublished).isEmpty
        checks["two-mounted-task-awaits"] = ordered([
            .modelStarted, .modelFirstAwait, .modelFirstReleased, .modelFirstResumed,
            .modelSecondAwait, .idleBegan, .idleEnded, .modelSecondReleased, .modelSecondResumed, .modelFinished,
        ])

        let replies = all(.ownedCommandReply)
        let emitted = all(.smokeProbeEmitted)
        let received = all(.ingressReceiveReturned).filter { $0.requestID != nil && $0.value != nil }
        let ordinals = Set((0..<64).map(Int64.init))
        checks["64-actual-command-replies"] =
            one(.ownedWorkloadSubmitted)?.auxiliary == 64
            && replies.count == 64 && Set(replies.compactMap(\.value)) == ordinals
            && Set(replies.compactMap(\.requestID)).count == 64
            && replies.allSatisfy {
                $0.flags == 1 && belongsToWindow($0) && $0.generation != nil && $0.nativeSequence != nil
            }
            && state.replyMask == UInt64.max
        checks["64-accepted-and-delivered-probes"] =
            emitted.count == 64 && received.count == 64
            && Set(emitted.compactMap(\.value)) == ordinals && Set(received.compactMap(\.value)) == ordinals
            && Set(emitted.compactMap(\.requestID)).count == 64 && Set(received.compactMap(\.requestID)).count == 64
            && Set(emitted.compactMap(\.nativeSequence)).count == 64
            && emitted.allSatisfy { sent in
                guard let id = sent.requestID, let sequence = sent.nativeSequence,
                    sent.generation != nil, belongsToWindow(sent)
                else { return false }
                return received.contains {
                    $0.requestID == id && $0.value == sent.value && $0.nativeSequence == sequence
                        && $0.generation == sent.generation && $0.windowID == sent.windowID
                        && $0.lifetimeID == sent.lifetimeID
                }
                    && replies.contains {
                        $0.requestID == id && $0.nativeSequence == sequence && $0.value == sent.value
                            && $0.generation == sent.generation && belongsToWindow($0)
                    }
            }
        let deliveredOrdinals = received.compactMap(\.value)
        checks["accepted-probe-FIFO"] = deliveredOrdinals == (0..<64).map(Int64.init)

        let nativeTurns = all(.nativeTurnEnded)
        let actorTurns = all(.ingressTurnEnded)
        checks["native-and-actor-turn-bounds"] =
            !nativeTurns.isEmpty && !actorTurns.isEmpty
            && nativeTurns.allSatisfy { ($0.value ?? -1) >= 0 && ($0.value ?? 17) <= 16 }
            && actorTurns.allSatisfy { $0.flags == 1 && ($0.value ?? -1) >= 0 && ($0.value ?? 33) <= 32 }
        let fullTurns = actorTurns.filter { $0.value == 32 && ($0.queueDepth ?? 0) > 0 }
        let hadBacklog = all(.ingressTurnBegan).contains { ($0.queueDepth ?? 0) > 32 }
        let progressBetweenTurns = fullTurns.contains { end in
            guard let next = all(.ingressTurnBegan).first(where: { $0.ordinal > end.ordinal }) else { return false }
            return rows.contains {
                $0.ordinal > end.ordinal && $0.ordinal < next.ordinal
                    && ($0.isKind(.modelFirstResumed) || $0.isKind(.actorQueryEntered)
                        || $0.isKind(.frameReplyConsumed))
            }
        }
        checks["backlogged-32-record-turn-and-continuation"] = hadBacklog && !fullTurns.isEmpty
        checks["actor-progress-between-backlogged-turns"] = progressBetweenTurns

        let owner = one(.nativeThreadEntered)
        // Executor identity is not entry-thread identity. Each known actor
        // callback must nevertheless run off the still-live, blocking N owner;
        // it need not share one physical thread with other actor callbacks.
        let actorKinds: [Win32NativeSmokeEventKind] = [
            .hostReady, .modelStarted, .modelFirstAwait, .modelFirstReleased, .modelFirstResumed,
            .modelSecondAwait, .modelSecondReleased, .modelSecondResumed, .modelFinished,
            .ownedWorkloadSubmitted, .providerAcquired, .actorQueryEntered, .nestedQueryCompleted,
            .framePrepared, .frameReplyConsumed, .frameSubmitted, .uiARevoked, .presentationDetached,
            .actorCloseConsumed, .actorStopConsumed, .coordinatorReturned, .actorIdleBoundary,
            .idleBegan, .idleEnded, .staleCommandRejected, .ingressTurnBegan, .ingressTurnEnded,
            .ingressFlushBegan, .ingressFlushEnded, .ingressReceiveBegan, .ingressReceiveReturned,
        ]
        let nativeKinds: [Win32NativeSmokeEventKind] = [
            .nativeCOMInitialized, .nativeOwnerReady, .nativeWakeReceived, .nativeTurnBegan, .nativeTurnEnded,
            .nativeWorkDequeued, .nativeMessageDispatched, .nativeDispatchReturned, .nativeWindowCreated,
            .nativeWindowNonClientDestroyed, .nativeAttachmentDetached, .nativeCloseDispatchUnwound,
            .nativeCloseAwaitingAttachments, .nativeCloseReplyReady, .nativeCloseReplyReturned,
            .nativeQueryStarted, .nativeQueryCompleted,
            .ownedCommandReply, .smokeProbeEmitted, .frameReplyReceived,
        ]
        let actorRows = rows.filter { row in actorKinds.contains { row.isKind($0) } }
        let nativeRows = rows.filter { row in nativeKinds.contains { row.isKind($0) } }
        let joinedOrdinal = one(.nativeThreadJoined).flatMap { $0.flags == 1 ? $0.ordinal : nil }
        let terminated = one(.nativeThreadTerminated)
        let terminationObservedByJoiner: Bool
        if let owner, let terminated, let joined = one(.nativeThreadJoined),
            let closeReturned = one(.nativeCloseReplyReturned)
        {
            // This is the worker that observed the original thread handle
            // become signaled, not N recording an early intent to return.
            // Count all receipts before checking success so an extra failed
            // join cannot be hidden beside an otherwise successful one.
            terminationObservedByJoiner =
                owner.threadID != 0 && terminated.threadID != 0
                && terminated.value == 0
                && terminated.auxiliary == UInt64(owner.threadID)
                && joined.auxiliary == UInt64(owner.threadID)
                && terminated.threadID == joined.threadID
                && closeReturned.threadID == owner.threadID && closeReturned.flags == 15 && closeReturned.value == 0
                && joined.flags == 1 && joined.value == 0
                && owner.ordinal < closeReturned.ordinal && closeReturned.ordinal < terminated.ordinal
                && terminated.ordinal < joined.ordinal
                && nativeRows.allSatisfy {
                    $0.threadID == owner.threadID && $0.ordinal < terminated.ordinal && $0.ordinal < joined.ordinal
                }
        } else {
            terminationObservedByJoiner = false
        }
        let overlappingActorRows = actorRows.filter {
            $0.ordinal > (owner?.ordinal ?? .max) && $0.ordinal < (joinedOrdinal ?? .max)
        }
        // Numeric thread IDs can be reused after termination. Do not reject a
        // later actor callback merely because it carries the retired N ID.
        checks["actor-and-native-owner-thread-separation"] =
            owner != nil && !overlappingActorRows.isEmpty && !nativeRows.isEmpty
            && overlappingActorRows.allSatisfy { $0.threadID != owner?.threadID }
            && nativeRows.allSatisfy { $0.threadID == owner?.threadID && $0.ordinal < (joinedOrdinal ?? .max) }
            && (all(.nativeThreadTerminated).isEmpty || terminationObservedByJoiner)
        let queryStart = one(.nativeQueryStarted)
        let queryEnd = one(.nativeQueryCompleted)
        let querySpan: Bool
        if let owner, let queryStart, let queryEnd {
            querySpan =
                queryStart.threadID == owner.threadID && queryEnd.threadID == owner.threadID
                && queryEnd.value == 0 && (queryEnd.auxiliary ?? 0) != 0
                && belongsToWindow(queryStart) && belongsToWindow(queryEnd)
                && queryStart.requestID != nil && queryStart.requestID == queryEnd.requestID
                && queryStart.generation != nil && queryStart.generation == queryEnd.generation
                && queryStart.nativeSequence != nil && queryStart.nativeSequence == queryEnd.nativeSequence
                && queryStart.ordinal < queryEnd.ordinal
                && all(.actorQueryEntered).contains {
                    $0.ordinal > queryStart.ordinal && $0.ordinal < queryEnd.ordinal
                        && $0.threadID != owner.threadID
                        && $0.windowID == queryStart.windowID && $0.lifetimeID == queryStart.lifetimeID
                        && $0.generation == queryStart.generation && $0.nativeSequence == queryStart.nativeSequence
                }
                && !rows.contains {
                    $0.ordinal > queryStart.ordinal && $0.ordinal < queryEnd.ordinal
                        && ($0.isKind(.nativeWorkDequeued) || $0.isKind(.nativeMessageDispatched))
                }
        } else {
            querySpan = false
        }
        checks["native-query-finished-without-native-progress"] = querySpan
        checks["nested-query-keeps-actual-E_FAIL-and-empty-output"] =
            one(.nestedQueryCompleted)?.value == Int64(Int32(bitPattern: 0x8000_4005))
            && one(.nestedQueryCompleted)?.auxiliary == 0

        let requiredFrameFlags =
            NativeOwnedSmokeFrameFlags.transportSucceeded
            | NativeOwnedSmokeFrameFlags.presentationSucceeded | NativeOwnedSmokeFrameFlags.submitted
            | NativeOwnedSmokeFrameFlags.attached | NativeOwnedSmokeFrameFlags.hasFrameID
            | NativeOwnedSmokeFrameFlags.hardwareAdapter | NativeOwnedSmokeFrameFlags.expectedBackend
            | NativeOwnedSmokeFrameFlags.currentContent
        var phaseFrames: [NativeOwnedSmokeTraceRow] = []
        for phase in UInt64(0)..<UInt64(3) {
            let lower = phase == 0 ? 0 : one(phase == 1 ? .modelFirstResumed : .modelSecondResumed)?.ordinal ?? .max
            let upper = one(phase == 0 ? .modelFirstReleased : phase == 1 ? .idleBegan : .uiARevoked)?.ordinal ?? 0
            let frame = all(.frameSubmitted).last {
                $0.auxiliary == phase && $0.ordinal > lower && $0.ordinal < upper
                    && $0.flags & requiredFrameFlags == requiredFrameFlags
            }
            let match =
                frame.map { frame in
                    guard let id = frame.requestID, let owner,
                        let attachmentID = frame.attachmentID, let generation = frame.generation,
                        let revision = frame.revision, let deviceGeneration = frame.deviceGeneration,
                        let frameNumber = frame.frameNumber, let nativeSequence = frame.nativeSequence,
                        let detached = one(.presentationDetached), detached.attachmentID == attachmentID,
                        let prepared = one(.framePrepared, requestID: id),
                        let native = one(.frameReplyReceived, requestID: id),
                        let consumed = one(.frameReplyConsumed, requestID: id),
                        one(.frameSubmitted, requestID: id) != nil,
                        let startedAt = native.nativeStartedAtSeconds, let completedAt = native.nativeCompletedAtSeconds
                    else { return false }
                    return prepared.ordinal < native.ordinal && native.ordinal < consumed.ordinal
                        && consumed.ordinal < frame.ordinal
                        && native.threadID == owner.threadID
                        && [prepared, consumed, frame].allSatisfy { $0.threadID != owner.threadID }
                        && startedAt.isFinite && completedAt.isFinite && completedAt >= startedAt
                        && [prepared, native, consumed, frame].allSatisfy {
                            belongsToWindow($0) && $0.attachmentID == attachmentID
                                && $0.generation == generation && $0.revision == revision && $0.auxiliary == phase
                        }
                        && [native, consumed].allSatisfy {
                            $0.deviceGeneration == deviceGeneration && $0.frameNumber == frameNumber
                                && $0.nativeSequence == nativeSequence
                                && $0.nativeStartedAtSeconds == frame.nativeStartedAtSeconds
                                && $0.nativeCompletedAtSeconds == frame.nativeCompletedAtSeconds
                                && $0.flags & NativeOwnedSmokeFrameFlags.submitted != 0
                                && $0.flags & NativeOwnedSmokeFrameFlags.presentationSucceeded != 0
                        }
                } ?? false
            checks["phase-\(phase)-actual-frame-receipt"] = match
            if match, let frame { phaseFrames.append(frame) }
        }
        checks["three-distinct-retained-updates"] =
            phaseFrames.count == 3 && state.framePhaseMask == 7
            && phaseFrames[0].revision != nil && phaseFrames[1].revision != nil && phaseFrames[2].revision != nil
            && phaseFrames[0].revision! < phaseFrames[1].revision!
            && phaseFrames[1].revision! < phaseFrames[2].revision!
            && Set(phaseFrames.map { "\($0.deviceGeneration!)/\($0.frameNumber!)" }).count == 3

        if let start = one(.idleBegan), let end = one(.idleEnded) {
            checks["three-second-unforced-settled-idle"] =
                start.flags == 1 && end.flags == 1
                && state.idleStart?.isSettled == true && state.idleEnd?.isSettled == true
                && state.idleStart?.phase == 1 && state.idleEnd?.phase == 1
                && end.uptimeNanoseconds >= start.uptimeNanoseconds
                && end.uptimeNanoseconds - start.uptimeNanoseconds >= 3_000_000_000
                && start.revision == end.revision && start.generation == end.generation
                && start.nativeSequence == end.nativeSequence
                && !rows.contains { row in
                    row.ordinal > start.ordinal && row.ordinal < end.ordinal
                        && idleQuietKinds.contains { row.isKind($0) }
                }
            let timer = all(.nativeTimerState).last { $0.ordinal < start.ordinal }
            checks["actual-native-timers-absent-at-idle"] = timer?.flags == 0
        } else {
            checks["three-second-unforced-settled-idle"] = false
            checks["actual-native-timers-absent-at-idle"] = false
        }

        let gateEntered = one(.publicationGateEntered)
        let releaseRequested = one(.publicationGateReleaseRequested)
        let gateOpened = one(.publicationGateOpened)
        let worker = one(.externalQueryStarted)
        checks["gate-held-by-the-owned-external-worker"] =
            owner != nil && worker != nil && gateEntered?.auxiliary != nil
            && gateEntered?.auxiliary == worker.map { UInt64($0.threadID) }
            && worker?.threadID != owner?.threadID && gateEntered?.value == 0
        if let gateEntered, let releaseRequested, let gateOpened,
            let revoked = one(.uiARevoked), let destroyed = one(.nativeWindowNonClientDestroyed)
        {
            checks["full-C-lease-prevented-native-destruction"] =
                gateEntered.ordinal < revoked.ordinal
                && revoked.ordinal < releaseRequested.ordinal && releaseRequested.ordinal < destroyed.ordinal
                && releaseRequested.ordinal < gateOpened.ordinal
                && all(.nativeCloseAwaitingAttachments).contains {
                    $0.ordinal > revoked.ordinal && $0.ordinal < releaseRequested.ordinal
                        && $0.threadID == owner?.threadID
                }
                && gateOpened.value == 0
        } else {
            checks["full-C-lease-prevented-native-destruction"] = false
        }
        checks["revoked-C-call-keeps-unavailable-and-empty-output"] =
            one(.externalQueryCompleted)?.value == Int64(Int32(bitPattern: 0x8004_0201))
            && one(.externalQueryCompleted)?.auxiliary == 0
            && state.externalResult?.status == Int32(bitPattern: 0x8004_0201) && state.externalResult?.value == 0

        if let consumed = one(.presentationDetached), let destroyed = one(.nativeWindowNonClientDestroyed) {
            checks["actual-renderer-detach-before-NCDESTROY"] =
                consumed.flags == 1 && consumed.value == 0
                && consumed.attachmentID != nil
                && all(.nativeAttachmentDetached).contains {
                    $0.attachmentID == consumed.attachmentID && $0.ordinal < destroyed.ordinal
                        && $0.flags == 1 && $0.value == 0
                } && destroyed.ordinal < consumed.ordinal
        } else {
            checks["actual-renderer-detach-before-NCDESTROY"] = false
        }
        checks["native-close-unwind-before-actor-close"] = ordered([
            .nativeWindowNonClientDestroyed, .nativeCloseDispatchUnwound, .nativeCloseReplyReady, .actorCloseConsumed,
        ])
        checks["actual-owner-join-and-actor-stop-consumption"] =
            ordered([
                .nativeCloseReplyReturned, .nativeThreadJoined, .actorStopConsumed, .coordinatorReturned,
            ]) && one(.nativeThreadJoined)?.flags == 1 && one(.nativeThreadJoined)?.value == 0
            && one(.nativeCloseReplyReturned)?.flags == 15 && one(.nativeCloseReplyReturned)?.value == 0
            && one(.nativeThreadJoined)?.auxiliary == owner.map { UInt64($0.threadID) }
            && one(.actorStopConsumed)?.value == 0 && one(.coordinatorReturned)?.value == 0 && state.ownerExitCode == 0
            && terminationObservedByJoiner
        checks["closed-owner-rejection-is-one-shot"] =
            state.lateReplyCount == 1 && state.lateReplyWasOwnerStopped
            && one(.staleCommandRejected)?.flags == 1 && replies.count == 64 && emitted.count == 64
        return NativeOwnedSmokeVerdict(
            predicates: checks, insufficientFairnessExercise: !hadBacklog || fullTurns.isEmpty || !progressBetweenTurns)
    }
}
