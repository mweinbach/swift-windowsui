import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsPlatform
@testable import WinSwiftUI

/// Synthetic value tests of individual acceptance predicates. These records
/// are deliberately not native evidence and never create an HWND or renderer.
@MainActor
final class NativeOwnedSmokeValidationTests: XCTestCase {
    func testEmptyObservationCannotQualifyTheExecutable() async throws {
        let fixture = SmokePredicateFixture()
        let verdict = try fixture.evaluate()
        XCTAssertFalse(verdict.qualifyingPredicatesSatisfied)
        XCTAssertEqual(verdict.predicates["two-mounted-task-awaits"], false)
        XCTAssertEqual(verdict.predicates["actual-owner-join-and-actor-stop-consumption"], false)
    }

    func testCompleteSyntheticTraceCanSatisfyTheFullConjunction() async throws {
        let fixture = SmokePredicateFixture()
        let state = fixture.completeTrace()
        let verdict = try fixture.evaluate(state: state)
        XCTAssertEqual(verdict.predicates.filter { !$0.value }.map(\.key).sorted(), [])
        XCTAssertTrue(verdict.qualifyingPredicatesSatisfied)
        XCTAssertFalse(verdict.insufficientFairnessExercise)
    }

    func testRetiredNativeThreadIDCanBeReusedAfterActualJoinButNotDuringAFrame() async throws {
        let fixture = SmokePredicateFixture()
        let state = fixture.completeTrace()
        for kind in [
            Win32NativeSmokeEventKind.actorStopConsumed, .coordinatorReturned, .staleCommandRejected,
        ] {
            fixture.replace(kind: kind, key: "threadID", with: 10)
        }
        XCTAssertTrue(try fixture.evaluate(state: state).qualifyingPredicatesSatisfied)
        fixture.replace(kind: .frameReplyConsumed, key: "threadID", with: 10)
        let liveOwnerCollision = try fixture.evaluate(state: state)
        XCTAssertEqual(liveOwnerCollision.predicates["actor-and-native-owner-thread-separation"], false)
        XCTAssertEqual(liveOwnerCollision.predicates["phase-0-actual-frame-receipt"], false)
    }

    func testCommandAdmissionWithoutActualRepliesDoesNotPass() async throws {
        let fixture = SmokePredicateFixture()
        fixture.add(.ownedWorkloadSubmitted, auxiliary: 64)
        XCTAssertEqual(try fixture.evaluate().predicates["64-actual-command-replies"], false)
    }

    func testEveryActualReplyAndEveryOrdinalIsRequired() async throws {
        let fixture = SmokePredicateFixture()
        fixture.add(.ownedWorkloadSubmitted, auxiliary: 64)
        for value in 0..<64 {
            fixture.add(
                .ownedCommandReply, request: fixture.requests[value], sequence: UInt64(value + 1), value: Int64(value),
                flags: 1)
        }
        var state = NativeOwnedSmokeSharedState.Snapshot()
        state.replyMask = .max
        XCTAssertEqual(try fixture.evaluate(state: state).predicates["64-actual-command-replies"], true)
        fixture.replaceLast("flags", with: 0)
        XCTAssertEqual(try fixture.evaluate(state: state).predicates["64-actual-command-replies"], false)
        fixture.replaceLast("flags", with: 1)
        fixture.replaceLast("value", with: 62)
        XCTAssertEqual(try fixture.evaluate(state: state).predicates["64-actual-command-replies"], false)
        fixture.replaceLast("value", with: 63)
        fixture.replaceLast("requestID", with: fixture.requests[62].rawValue.uuidString)
        XCTAssertEqual(try fixture.evaluate(state: state).predicates["64-actual-command-replies"], false)
    }

    func testAcceptedProbeCanBeDeliveredBeforeItsProducerObservation() async throws {
        let fixture = SmokePredicateFixture()
        fixture.probes(deliveryFirst: true)
        let verdict = try fixture.evaluate()
        XCTAssertEqual(verdict.predicates["64-accepted-and-delivered-probes"], true)
        XCTAssertEqual(verdict.predicates["accepted-probe-FIFO"], true)
        XCTAssertEqual(fixture.observation.snapshot().deliveredProbeCount, 64)
    }

    func testWrongProbeSequenceOrDuplicateDeliveryDoesNotPass() async throws {
        let fixture = SmokePredicateFixture()
        fixture.probes(deliveryFirst: false)
        XCTAssertEqual(try fixture.evaluate().predicates["64-accepted-and-delivered-probes"], true)
        fixture.replaceLast("nativeSequence", with: 9_999)
        XCTAssertEqual(try fixture.evaluate().predicates["64-accepted-and-delivered-probes"], false)
        fixture.add(.ingressReceiveReturned, request: fixture.requests[63], sequence: 64, value: 63, flags: 1)
        XCTAssertEqual(try fixture.evaluate().predicates["accepted-probe-FIFO"], false)
    }

    func testFrameRequiresMatchingNativeReplyConsumptionAndCurrentHardwareFlags() async throws {
        let fixture = SmokePredicateFixture()
        fixture.frameZero()
        XCTAssertEqual(try fixture.evaluate().predicates["phase-0-actual-frame-receipt"], true)
        fixture.replace(
            kind: .frameSubmitted, key: "flags",
            with: SmokePredicateFixture.frameFlags & ~NativeOwnedSmokeFrameFlags.currentContent)
        XCTAssertEqual(try fixture.evaluate().predicates["phase-0-actual-frame-receipt"], false)
        fixture.replace(
            kind: .frameSubmitted, key: "flags",
            with: SmokePredicateFixture.frameFlags & ~NativeOwnedSmokeFrameFlags.hardwareAdapter)
        XCTAssertEqual(try fixture.evaluate().predicates["phase-0-actual-frame-receipt"], false)
    }

    func testWindowIdentityMustMatchEveryKeyedRecord() async throws {
        let fixture = SmokePredicateFixture()
        fixture.add(.hostReady)
        fixture.add(.nativeWindowCreated, thread: 10)
        fixture.add(.nativeWindowNonClientDestroyed, thread: 10)
        XCTAssertEqual(try fixture.evaluate().predicates["one-owned-window-lifetime"], true)
        fixture.replace(kind: .nativeWindowNonClientDestroyed, key: "lifetimeID", with: Foundation.UUID().uuidString)
        XCTAssertEqual(try fixture.evaluate().predicates["one-owned-window-lifetime"], false)
    }

    func testStaleRevisionDeviceIdentityOrMissingReceiptTimingCannotQualifyFrame() async throws {
        let fixture = SmokePredicateFixture()
        fixture.frameZero()
        fixture.replace(kind: .frameReplyConsumed, key: "revision", with: 8)
        XCTAssertEqual(try fixture.evaluate().predicates["phase-0-actual-frame-receipt"], false)
        fixture.replace(kind: .frameReplyConsumed, key: "revision", with: 1)
        fixture.replace(kind: .frameReplyReceived, key: "deviceGeneration", with: 8)
        XCTAssertEqual(try fixture.evaluate().predicates["phase-0-actual-frame-receipt"], false)
        fixture.replace(kind: .frameReplyReceived, key: "deviceGeneration", with: 5)
        fixture.remove(kind: .frameReplyReceived, key: "nativeStartedAtSeconds")
        XCTAssertEqual(try fixture.evaluate().predicates["phase-0-actual-frame-receipt"], false)
    }

    func testFrameRequiresOwnedWindowLifetimeAndRendererAttachment() async throws {
        let fixture = SmokePredicateFixture()
        fixture.frameZero()
        let other = NativeWindowKey()
        var state = NativeOwnedSmokeSharedState.Snapshot()
        state.windowKey = other
        XCTAssertEqual(try fixture.evaluate(state: state).predicates["phase-0-actual-frame-receipt"], false)
        fixture.replace(kind: .frameReplyConsumed, key: "attachmentID", with: Foundation.UUID().uuidString)
        XCTAssertEqual(try fixture.evaluate().predicates["phase-0-actual-frame-receipt"], false)
        fixture.replace(kind: .frameReplyConsumed, key: "attachmentID", with: fixture.attachment.rawValue.uuidString)
        fixture.replace(kind: .presentationDetached, key: "attachmentID", with: Foundation.UUID().uuidString)
        XCTAssertEqual(try fixture.evaluate().predicates["phase-0-actual-frame-receipt"], false)
    }

    func testMissingFrameMetadataCannotBeReplacedByClaimedFlags() async throws {
        for key in ["attachmentID", "generation", "revision", "deviceGeneration", "frameNumber", "nativeSequence"] {
            let fixture = SmokePredicateFixture()
            fixture.frameZero()
            fixture.remove(kind: .frameSubmitted, key: key)
            XCTAssertEqual(try fixture.evaluate().predicates["phase-0-actual-frame-receipt"], false, key)
        }
    }

    func testDuplicateRecordForAFrameRequestCannotPass() async throws {
        for kind in [
            Win32NativeSmokeEventKind.framePrepared, .frameReplyReceived, .frameReplyConsumed, .frameSubmitted,
        ] {
            let fixture = SmokePredicateFixture()
            fixture.frameZero()
            fixture.add(
                kind, request: fixture.requests[0], sequence: 1, revision: 1, auxiliary: 0,
                flags: SmokePredicateFixture.frameFlags, thread: kind == .frameReplyReceived ? 10 : 20, frame: true)
            XCTAssertEqual(
                try fixture.evaluate().predicates["phase-0-actual-frame-receipt"], false, String(describing: kind))
        }
    }

    func testActorMarkersMustDifferFromNativeOwnerWithoutOneActorThreadAssumption() async throws {
        let fixture = SmokePredicateFixture()
        fixture.add(.nativeThreadEntered, thread: 10)
        fixture.add(.nativeTurnEnded, value: 1, thread: 10)
        fixture.add(.modelFirstAwait, thread: 20)
        fixture.add(.modelFirstResumed, thread: 21)
        XCTAssertEqual(try fixture.evaluate().predicates["actor-and-native-owner-thread-separation"], true)
        fixture.replace(kind: .modelFirstResumed, key: "threadID", with: 10)
        XCTAssertEqual(try fixture.evaluate().predicates["actor-and-native-owner-thread-separation"], false)
        fixture.replace(kind: .modelFirstResumed, key: "threadID", with: 21)
        fixture.replace(kind: .nativeTurnEnded, key: "threadID", with: 20)
        XCTAssertEqual(try fixture.evaluate().predicates["actor-and-native-owner-thread-separation"], false)
    }

    func testAFrameConsumedOnNativeOwnerCannotPass() async throws {
        let fixture = SmokePredicateFixture()
        fixture.frameZero()
        fixture.replace(kind: .frameReplyConsumed, key: "threadID", with: 10)
        XCTAssertEqual(try fixture.evaluate().predicates["phase-0-actual-frame-receipt"], false)
    }

    func testNativeQueryMustContainActorWorkWithoutMoreNativeWork() async throws {
        let fixture = SmokePredicateFixture()
        fixture.add(.nativeThreadEntered, thread: 10)
        fixture.add(.nativeQueryStarted, request: fixture.requests[31], sequence: 31, thread: 10)
        fixture.add(.actorQueryEntered, sequence: 31, thread: 20)
        fixture.add(
            .nativeQueryCompleted, request: fixture.requests[31], sequence: 31, value: 0, auxiliary: 50_026, thread: 10)
        XCTAssertEqual(try fixture.evaluate().predicates["native-query-finished-without-native-progress"], true)
        fixture.replace(kind: .actorQueryEntered, key: "threadID", with: 10)
        XCTAssertEqual(try fixture.evaluate().predicates["native-query-finished-without-native-progress"], false)
        fixture.replace(kind: .actorQueryEntered, key: "threadID", with: 20)
        fixture.replace(
            kind: .actorQueryEntered, key: "kind", with: Win32NativeSmokeEventKind.nativeWorkDequeued.rawValue)
        XCTAssertEqual(try fixture.evaluate().predicates["native-query-finished-without-native-progress"], false)
    }

    func testPublicationGateRequiresTheActualExternalClaimantAndNativeBlockedClose() async throws {
        let fixture = SmokePredicateFixture()
        fixture.add(.nativeThreadEntered, thread: 10)
        fixture.add(.externalQueryStarted, thread: 30)
        fixture.add(.publicationGateEntered, value: 0, auxiliary: 30, thread: 40)
        fixture.add(.uiARevoked, thread: 20)
        fixture.add(.nativeCloseAwaitingAttachments, thread: 10)
        fixture.add(.publicationGateReleaseRequested, thread: 40)
        fixture.add(.publicationGateOpened, value: 0, thread: 40)
        fixture.add(.nativeWindowNonClientDestroyed, thread: 10)
        XCTAssertEqual(try fixture.evaluate().predicates["gate-held-by-the-owned-external-worker"], true)
        XCTAssertEqual(try fixture.evaluate().predicates["full-C-lease-prevented-native-destruction"], true)
        fixture.replace(kind: .publicationGateEntered, key: "auxiliary", with: 31)
        XCTAssertEqual(try fixture.evaluate().predicates["gate-held-by-the-owned-external-worker"], false)
        fixture.replace(
            kind: .nativeCloseAwaitingAttachments, key: "kind",
            with: Win32NativeSmokeEventKind.actorQueryEntered.rawValue)
        XCTAssertEqual(try fixture.evaluate().predicates["full-C-lease-prevented-native-destruction"], false)
    }

    func testNativeDestructionMayPrecedeLoggingActualGateOpenResult() async throws {
        let fixture = SmokePredicateFixture()
        fixture.add(.nativeThreadEntered, thread: 10)
        fixture.add(.externalQueryStarted, thread: 30)
        fixture.add(.publicationGateEntered, value: 0, auxiliary: 30, thread: 40)
        fixture.add(.uiARevoked, thread: 20)
        fixture.add(.nativeCloseAwaitingAttachments, thread: 10)
        fixture.add(.publicationGateReleaseRequested, thread: 40)
        fixture.add(.nativeWindowNonClientDestroyed, thread: 10)
        fixture.add(.publicationGateOpened, value: 0, thread: 40)
        XCTAssertEqual(try fixture.evaluate().predicates["full-C-lease-prevented-native-destruction"], true)
        fixture.replace(kind: .publicationGateOpened, key: "value", with: Int32(bitPattern: 0x8000_4005))
        XCTAssertEqual(try fixture.evaluate().predicates["full-C-lease-prevented-native-destruction"], false)
    }

    func testPreparedCloseAndPostedQuitCannotReplaceActualJoinAndActorConsumption() async throws {
        let fixture = SmokePredicateFixture()
        fixture.add(.nativeThreadEntered, thread: 10)
        fixture.add(.nativeCloseReplyReady, value: 0, flags: 7, thread: 10)
        fixture.add(.nativeCloseReplyReturned, value: 0, flags: 15, thread: 10)
        fixture.add(.nativeThreadJoined, value: 0, auxiliary: 10, flags: 1, thread: 40)
        fixture.add(.actorStopConsumed, value: 0, thread: 20)
        fixture.add(.coordinatorReturned, value: 0, thread: 20)
        var state = NativeOwnedSmokeSharedState.Snapshot()
        state.ownerExitCode = 0
        XCTAssertEqual(
            try fixture.evaluate(state: state).predicates["actual-owner-join-and-actor-stop-consumption"], true)
        fixture.replace(kind: .nativeThreadJoined, key: "flags", with: 0)
        XCTAssertEqual(
            try fixture.evaluate(state: state).predicates["actual-owner-join-and-actor-stop-consumption"], false)
        fixture.replace(kind: .nativeThreadJoined, key: "flags", with: 1)
        fixture.replace(kind: .nativeCloseReplyReturned, key: "flags", with: 7)
        XCTAssertEqual(
            try fixture.evaluate(state: state).predicates["actual-owner-join-and-actor-stop-consumption"], false)
    }

    func testIdleRequiresThreeSecondsAndNoUnforcedNativeActivity() async throws {
        let fixture = SmokePredicateFixture()
        fixture.add(.nativeTimerState, flags: 0)
        fixture.add(.idleBegan, sequence: 64, revision: 2, flags: 1, time: 1_000_000_000)
        fixture.add(.actorIdleBoundary, time: 2_000_000_000)
        fixture.add(.idleEnded, sequence: 64, revision: 2, flags: 1, time: 4_000_000_000)
        var state = NativeOwnedSmokeSharedState.Snapshot()
        state.idleStart = SmokePredicateFixture.settledHost
        state.idleEnd = SmokePredicateFixture.settledHost
        XCTAssertEqual(try fixture.evaluate(state: state).predicates["three-second-unforced-settled-idle"], true)
        fixture.replace(
            kind: .actorIdleBoundary, key: "kind", with: Win32NativeSmokeEventKind.nativeAnimationCallback.rawValue)
        XCTAssertEqual(try fixture.evaluate(state: state).predicates["three-second-unforced-settled-idle"], false)
        fixture.replace(
            kind: .nativeAnimationCallback, key: "kind", with: Win32NativeSmokeEventKind.actorIdleBoundary.rawValue)
        fixture.replace(kind: .idleEnded, key: "uptimeNanoseconds", with: UInt64(3_999_999_999))
        XCTAssertEqual(try fixture.evaluate(state: state).predicates["three-second-unforced-settled-idle"], false)
    }

    func testDuplicateClosedOwnerReplyAndInvalidObservationCannotPass() async throws {
        let fixture = SmokePredicateFixture()
        var state = NativeOwnedSmokeSharedState.Snapshot()
        state.lateReplyCount = 2
        state.lateReplyWasOwnerStopped = true
        fixture.add(.staleCommandRejected, flags: 1)
        XCTAssertEqual(try fixture.evaluate(state: state).predicates["closed-owner-rejection-is-one-shot"], false)
        XCTAssertFalse(fixture.observation.record(.frameReplyReceived, nativeStartedAtSeconds: .nan))
        XCTAssertEqual(try fixture.evaluate(state: state).predicates["bounded-valid-observation"], false)
    }

    func testIncompleteFairnessExerciseIsExplicitlyInconclusive() async throws {
        let fixture = SmokePredicateFixture()
        fixture.add(.nativeTurnEnded, value: 16, flags: 0)
        fixture.add(.ingressTurnEnded, value: 8, flags: 1)
        let verdict = try fixture.evaluate()
        XCTAssertEqual(verdict.predicates["native-and-actor-turn-bounds"], true)
        XCTAssertTrue(verdict.insufficientFairnessExercise)
        XCTAssertFalse(verdict.qualifyingPredicatesSatisfied)
    }
}

@MainActor
private final class SmokePredicateFixture {
    let observation = Win32NativeSmokeObservation(runID: Foundation.UUID())
    let key = NativeWindowKey()
    let attachment = NativeWindowAttachmentID()
    let requests = (0..<64).map { _ in NativeWindowRequestID() }
    let frameRequests = (0..<3).map { _ in NativeWindowRequestID() }
    private var rows: [[String: Any]] = []
    private var nextTime: UInt64 = 1

    static let frameFlags: UInt32 =
        NativeOwnedSmokeFrameFlags.transportSucceeded | NativeOwnedSmokeFrameFlags.presentationSucceeded
        | NativeOwnedSmokeFrameFlags.submitted | NativeOwnedSmokeFrameFlags.attached
        | NativeOwnedSmokeFrameFlags.hasFrameID | NativeOwnedSmokeFrameFlags.hardwareAdapter
        | NativeOwnedSmokeFrameFlags.expectedBackend | NativeOwnedSmokeFrameFlags.currentContent

    static var settledHost: NativeOwnedSmokeHostSnapshot {
        NativeOwnedSmokeHostSnapshot(
            phase: 1, isClosed: false, hasNativeSurface: true, framePending: false, presentationPending: false,
            queuedPresentationRequests: 0, contentIsDirty: false, hasActiveAnimations: false, reloadScheduled: false,
            contentRevision: 2, lastPresentedRevision: 2, surfaceGeneration: 1, ingressQueued: 0,
            ingressTurnScheduled: false, receivedNativeSequence: 64, mailboxQueued: 0,
            nativeTurnActive: false, nativeWorkInFlight: false)
    }

    func add(
        _ kind: Win32NativeSmokeEventKind, request: NativeWindowRequestID? = nil, sequence: UInt64? = nil,
        revision: UInt64? = nil, value: Int64? = nil, auxiliary: UInt64? = nil, flags: UInt32 = 0,
        thread: UInt32 = 20, time: UInt64? = nil, frame: Bool = false,
        frameNumber: UInt64 = 1, queueDepth: UInt64? = nil, turnID: UInt64? = nil
    ) {
        let accepted = observation.record(
            kind, windowKey: key, requestID: request,
            attachmentID: frame || kind == .framePrepared || kind == .presentationDetached
                || kind == .nativeAttachmentDetached
                ? attachment : nil,
            generation: 1,
            deviceGeneration: frame ? 5 : nil, frameNumber: frame ? frameNumber : nil,
            nativeStartedAtSeconds: frame ? 11.25 : nil, nativeCompletedAtSeconds: frame ? 11.5 : nil,
            queueDepth: queueDepth, turnID: turnID,
            nativeSequence: sequence, revision: revision, value: value, auxiliary: auxiliary, flags: flags)
        precondition(accepted)
        // Thread/time replacements are confined to synthetic predicate input.
        // The real recorder intentionally has no injected clock/thread API.
        let line = observation.capture().trace.split(separator: 10).last!
        var row = try! JSONSerialization.jsonObject(with: Data(line)) as! [String: Any]
        row["threadID"] = thread
        let timestamp = time ?? nextTime
        row["uptimeNanoseconds"] = timestamp
        nextTime = max(nextTime, timestamp == .max ? .max : timestamp + 1)
        rows.append(row)
    }

    func probes(deliveryFirst: Bool) {
        for ordinal in 0..<64 {
            let id = requests[ordinal]
            if deliveryFirst {
                add(
                    .ingressReceiveReturned, request: id, sequence: UInt64(ordinal + 1), value: Int64(ordinal), flags: 1
                )
            }
            add(.smokeProbeEmitted, request: id, sequence: UInt64(ordinal + 1), value: Int64(ordinal), thread: 10)
            add(
                .ownedCommandReply, request: id, sequence: UInt64(ordinal + 1), value: Int64(ordinal), flags: 1,
                thread: 10)
            if !deliveryFirst {
                add(
                    .ingressReceiveReturned, request: id, sequence: UInt64(ordinal + 1), value: Int64(ordinal), flags: 1
                )
            }
        }
    }

    func frameZero() {
        add(.nativeThreadEntered, thread: 10)
        add(.framePrepared, request: requests[0], sequence: 1, revision: 1, auxiliary: 0)
        add(
            .frameReplyReceived, request: requests[0], sequence: 1, revision: 1, auxiliary: 0, flags: Self.frameFlags,
            thread: 10, frame: true)
        add(
            .frameReplyConsumed, request: requests[0], sequence: 1, revision: 1, auxiliary: 0, flags: Self.frameFlags,
            frame: true)
        add(
            .frameSubmitted, request: requests[0], sequence: 1, revision: 1, auxiliary: 0, flags: Self.frameFlags,
            frame: true)
        add(.modelFirstReleased)
        add(.presentationDetached, value: 0, flags: 1)
    }

    /// A synthetic, self-consistent whole trace checks conjunction wiring. It
    /// does not assert that an actual scheduler will produce this interleaving.
    func completeTrace() -> NativeOwnedSmokeSharedState.Snapshot {
        add(.fixtureStarted)
        add(.nativeThreadEntered, thread: 10)
        add(.nativeCOMInitialized, value: 0, thread: 10)
        add(.nativeOwnerReady, thread: 10)
        add(.nativeWindowCreated, thread: 10)
        add(.hostReady)
        add(.modelStarted)
        add(.modelFirstAwait)
        completeFrame(phase: 0, sequence: 0)
        add(.providerAcquired)
        add(.ownedWorkloadSubmitted, auxiliary: 64)

        for ordinal in 0..<64 {
            if ordinal % 16 == 0 { add(.nativeTurnBegan, thread: 10, turnID: UInt64(ordinal / 16 + 1)) }
            if ordinal == 31 {
                add(.nativeQueryStarted, request: requests[ordinal], sequence: 31, thread: 10)
                add(.ingressFlushBegan, flags: 2)
                for delivered in 0..<31 {
                    add(
                        .ingressReceiveReturned, request: requests[delivered], sequence: UInt64(delivered + 1),
                        value: Int64(delivered), flags: 2)
                }
                add(.ingressFlushEnded, value: 31, flags: 2)
                add(.actorQueryEntered, sequence: 31)
                add(.nestedQueryCompleted, value: Int64(Int32(bitPattern: 0x8000_4005)), auxiliary: 0)
                add(
                    .nativeQueryCompleted, request: requests[ordinal], sequence: 31, value: 0, auxiliary: 50_026,
                    thread: 10)
            }
            add(
                .smokeProbeEmitted, request: requests[ordinal], sequence: UInt64(ordinal + 1), value: Int64(ordinal),
                thread: 10)
            add(
                .ownedCommandReply, request: requests[ordinal], sequence: UInt64(ordinal + 1), value: Int64(ordinal),
                flags: 1, thread: 10)
            if ordinal % 16 == 15 { add(.nativeTurnEnded, value: 16, thread: 10, turnID: UInt64(ordinal / 16 + 1)) }
        }
        add(.modelFirstReleased)
        add(.ingressTurnBegan, flags: 1, queueDepth: 33, turnID: 1)
        for delivered in 31..<63 {
            add(
                .ingressReceiveReturned, request: requests[delivered], sequence: UInt64(delivered + 1),
                value: Int64(delivered), flags: 1, turnID: 1)
        }
        add(.ingressTurnEnded, value: 32, flags: 1, queueDepth: 1, turnID: 1)
        add(.modelFirstResumed)
        add(.modelSecondAwait)
        add(.ingressTurnBegan, flags: 1, queueDepth: 1, turnID: 2)
        add(.ingressReceiveReturned, request: requests[63], sequence: 64, value: 63, flags: 1, turnID: 2)
        add(.ingressTurnEnded, value: 1, flags: 1, queueDepth: 0, turnID: 2)
        completeFrame(phase: 1, sequence: 64)
        add(.nativeTimerState, flags: 0, thread: 10)
        add(.idleBegan, sequence: 64, revision: 2, flags: 1, time: 1_000_000_000)
        add(.idleEnded, sequence: 64, revision: 2, flags: 1, time: 4_000_000_000)
        add(.modelSecondReleased)
        add(.modelSecondResumed)
        add(.modelFinished)
        completeFrame(phase: 2, sequence: 64)

        add(.publicationGateArmed, thread: 40)
        add(.externalQueryStarted, thread: 30)
        add(.actorQueryEntered, sequence: 64)
        add(.publicationGateEntered, value: 0, auxiliary: 30, thread: 40)
        add(.uiARevoked)
        add(.nativeCloseAwaitingAttachments, thread: 10)
        add(.publicationGateReleaseRequested, thread: 40)
        add(.nativeAttachmentDetached, value: 0, flags: 1, thread: 10)
        add(.nativeWindowNonClientDestroyed, thread: 10)
        // The real released threads may beat this controller's result log.
        add(.publicationGateOpened, value: 0, thread: 40)
        add(.externalQueryCompleted, value: Int64(Int32(bitPattern: 0x8004_0201)), auxiliary: 0, thread: 30)
        add(.nativeCloseDispatchUnwound, thread: 10)
        add(.nativeCloseReplyReady, value: 0, flags: 7, thread: 10)
        add(.presentationDetached, value: 0, flags: 1)
        // A may consume the reply before N logs callback return.
        add(.actorCloseConsumed)
        add(.nativeCloseReplyReturned, value: 0, flags: 15, thread: 10)
        add(.nativeThreadTerminated, thread: 10)
        add(.nativeThreadJoined, value: 0, auxiliary: 10, flags: 1, thread: 40)
        add(.actorStopConsumed, value: 0)
        add(.coordinatorReturned, value: 0)
        add(.staleCommandRejected, flags: 1)
        add(.externalResourcesReleased, thread: 40)
        add(.fixtureFinished, flags: 1, thread: 40)

        var state = NativeOwnedSmokeSharedState.Snapshot()
        state.windowKey = key
        state.replyMask = .max
        state.framePhaseMask = 7
        state.idleStart = Self.settledHost
        state.idleEnd = Self.settledHost
        state.externalResult = Win32NativeSmokeControlTypeResult(
            status: Int32(bitPattern: 0x8004_0201), value: 0, threadID: 30, startedAt: 15, completedAt: 16)
        state.ownerExitCode = 0
        state.lateReplyCount = 1
        state.lateReplyWasOwnerStopped = true
        return state
    }

    private func completeFrame(phase: UInt64, sequence: UInt64) {
        let id = frameRequests[Int(phase)]
        add(.framePrepared, request: id, sequence: sequence, revision: phase + 1, auxiliary: phase)
        add(
            .frameReplyReceived, request: id, sequence: sequence, revision: phase + 1, auxiliary: phase,
            flags: Self.frameFlags, thread: 10, frame: true, frameNumber: phase + 1)
        add(
            .frameReplyConsumed, request: id, sequence: sequence, revision: phase + 1, auxiliary: phase,
            flags: Self.frameFlags, frame: true, frameNumber: phase + 1)
        add(
            .frameSubmitted, request: id, sequence: sequence, revision: phase + 1, auxiliary: phase,
            flags: Self.frameFlags, frame: true, frameNumber: phase + 1)
    }

    func replaceLast(_ key: String, with value: Any) { rows[rows.count - 1][key] = value }

    func replace(kind: Win32NativeSmokeEventKind, key: String, with value: Any) {
        let index = rows.firstIndex { ($0["kind"] as? NSNumber)?.uint16Value == kind.rawValue }!
        rows[index][key] = value
    }

    func remove(kind: Win32NativeSmokeEventKind, key: String) {
        let index = rows.firstIndex { ($0["kind"] as? NSNumber)?.uint16Value == kind.rawValue }!
        rows[index].removeValue(forKey: key)
    }

    func evaluate(state: NativeOwnedSmokeSharedState.Snapshot = NativeOwnedSmokeSharedState.Snapshot()) throws
        -> NativeOwnedSmokeVerdict
    {
        var boundState = state
        if boundState.windowKey == nil { boundState.windowKey = key }
        var data = Data()
        for row in rows {
            data.append(try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]))
            data.append(10)
        }
        return try NativeOwnedSmokeValidation.evaluate(
            NativeOwnedSmokeValidation.decode(data), observation: observation.snapshot(), state: boundState)
    }
}
