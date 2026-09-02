import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsPlatform
@testable import WinSwiftUI

/// Scalar recorder/parser controls only; these never create a window or call SetForegroundWindow.
@MainActor
final class Win32NativeSmokeForegroundActivationTests: XCTestCase {
    private let runID = Foundation.UUID(uuidString: "01234567-89ab-cdef-0123-456789abcdef")!
    private let windowKey = NativeWindowKey(
        windowID: Foundation.UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
        lifetimeID: Foundation.UUID(uuidString: "abcdef01-2345-6789-abcd-ef0123456789")!)

    func testActivationKindIsAppendedWithoutRenumberingExistingKinds() async {
        let previous: [Win32NativeSmokeEventKind] = [
            .fixtureStarted, .fixtureFailure, .hostReady,
            .modelStarted, .modelFirstAwait, .modelFirstReleased,
            .modelFirstResumed, .modelSecondAwait, .idleBegan,
            .idleEnded, .modelSecondReleased, .modelSecondResumed,
            .modelFinished, .ownedWorkloadSubmitted, .ownedCommandReply,
            .nativeQueryStarted, .nativeQueryCompleted, .actorQueryEntered,
            .nestedQueryCompleted, .externalQueryStarted, .publicationGateEntered,
            .publicationGateOpened, .externalQueryCompleted, .staleCommandRejected,
            .fixtureFinished, .providerAcquired, .publicationGateArmed,
            .coordinatorReturned, .externalResourcesReleased, .actorIdleBoundary,
            .framePrepared, .frameReplyReceived, .frameReplyConsumed,
            .frameSubmitted, .uiARevoked, .presentationDetached,
            .actorCloseConsumed, .actorStopConsumed, .nativeThreadEntered,
            .nativeCOMInitialized, .nativeOwnerReady, .nativeWakePostAttempt,
            .nativeWakePostSucceeded, .nativeWakePostFailed, .nativeWakeReceived,
            .nativeWakeDeferred, .nativeTurnBegan, .nativeTurnEnded,
            .nativeWorkDequeued, .nativeQueueSnapshot, .nativeMessageDispatched,
            .nativeDispatchReturned, .nativeWindowCreated, .nativeWindowNonClientDestroyed,
            .nativeAttachmentDetached, .nativeCloseDispatchUnwound, .nativeCloseAwaitingAttachments,
            .nativeCloseReplyReady, .nativeCloseReplyReturned, .nativeOwnerFailure,
            .nativeThreadTerminated, .nativeThreadJoined, .nativeJoinFailed,
            .nativeTimerState, .nativeTimerAPIResult, .nativeAnimationCallback,
            .nativeAnimationPost, .nativeAnimationMessage, .ingressQueued,
            .ingressCoalesced, .ingressRejected, .ingressTurnScheduled,
            .ingressTurnBegan, .ingressTurnEnded, .ingressTurnObsolete,
            .ingressTurnDeferred, .ingressFlushBegan, .ingressFlushEnded,
            .ingressReceiveBegan, .ingressReceiveReturned, .ingressFailurePublished,
            .ingressFailureReturned, .ingressSnapshot, .smokeProbeEmitted,
            .publicationGateReleaseRequested,
        ]
        XCTAssertEqual(previous.map(\.rawValue), Array(UInt16(0)...UInt16(84)))
        XCTAssertEqual(Win32NativeSmokeEventKind.nativeForegroundActivationResult.rawValue, 85)
        XCTAssertEqual(Win32NativeSmokeEventKind.allCases, previous + [.nativeForegroundActivationResult])
        XCTAssertNil(Win32NativeSmokeEventKind(rawValue: 86))
        XCTAssertNil(Win32NativeSmokeEventKind(rawValue: .max))
    }

    func testTrueResultPreservesWindowGenerationSequenceAndExactWireShape() async throws {
        let observation = Win32NativeSmokeObservation(runID: runID)
        XCTAssertTrue(
            observation.recordForegroundActivationResult(
                true, windowKey: windowKey, generation: 7, nativeSequence: 11))
        let capture = observation.capture()
        let row = try XCTUnwrap(capture.snapshot.last(.nativeForegroundActivationResult))
        XCTAssertEqual(row.windowKey, windowKey)
        XCTAssertEqual(row.generation, 7)
        XCTAssertEqual(row.nativeSequence, 11)
        XCTAssertEqual(row.value, 1)
        XCTAssertEqual(row.flags, 0)
        XCTAssertNil(row.auxiliary)
        XCTAssertNil(row.requestID)
        XCTAssertEqual(capture.snapshot.count(.nativeForegroundActivationResult), 1)
        let expected =
            "{\"runID\":\"01234567-89AB-CDEF-0123-456789ABCDEF\",\"ordinal\":1,\"kind\":85,"
            + "\"uptimeNanoseconds\":\(row.uptimeNanoseconds),\"threadID\":\(row.threadID),"
            + "\"windowID\":\"11111111-2222-3333-4444-555555555555\","
            + "\"lifetimeID\":\"ABCDEF01-2345-6789-ABCD-EF0123456789\","
            + "\"generation\":7,\"nativeSequence\":11,\"value\":1,\"flags\":0}\n"
        XCTAssertEqual(capture.trace, Data(expected.utf8))
        XCTAssertEqual(capture.snapshot.encodedBytes, capture.trace.count)
        XCTAssertFalse(capture.snapshot.isInvalid)
    }

    func testFalseResultIsRecordedAsZeroWithoutInventingMissingSurfaceMetadata() async throws {
        let observation = Win32NativeSmokeObservation(runID: runID)
        XCTAssertTrue(
            observation.recordForegroundActivationResult(
                false, windowKey: windowKey, generation: nil, nativeSequence: nil))
        let capture = observation.capture()
        let row = try XCTUnwrap(capture.snapshot.last(.nativeForegroundActivationResult))
        XCTAssertEqual(row.value, 0)
        XCTAssertEqual(row.windowKey, windowKey)
        XCTAssertNil(row.generation)
        XCTAssertNil(row.nativeSequence)
        XCTAssertNil(row.auxiliary)
        XCTAssertEqual(row.flags, 0)
        let encoded = try XCTUnwrap(String(data: capture.trace, encoding: .utf8))
        XCTAssertTrue(encoded.contains(",\"value\":0,"))
        XCTAssertFalse(encoded.contains("\"generation\""))
        XCTAssertFalse(encoded.contains("\"nativeSequence\""))
        XCTAssertEqual(capture.snapshot.recordCount, 1)
    }

    func testUnrecordedActivationRemainsAbsentWithNoActivity() async {
        let observation = Win32NativeSmokeObservation(runID: runID)
        let capture = observation.capture()
        XCTAssertEqual(capture.snapshot.count(.nativeForegroundActivationResult), 0)
        XCTAssertNil(capture.snapshot.last(.nativeForegroundActivationResult))
        XCTAssertEqual(capture.snapshot.recordCount, 0)
        XCTAssertEqual(capture.trace, Data())
        XCTAssertFalse(observation.waitForActivity(until: .now()))
    }

    func testFirstResultWinsAcrossWindowIdentitiesAndEachFixtureHasItsOwnBudget() async throws {
        let otherWindow = NativeWindowKey(
            windowID: Foundation.UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!,
            lifetimeID: Foundation.UUID(uuidString: "99999999-8888-7777-6666-555555555555")!)
        for first in [false, true] {
            let observation = Win32NativeSmokeObservation(runID: runID)
            XCTAssertTrue(observation.record(.fixtureStarted))
            XCTAssertTrue(observation.waitForActivity(until: .now()))
            XCTAssertTrue(
                observation.recordForegroundActivationResult(
                    first, windowKey: windowKey, generation: 7, nativeSequence: 11))
            let original = observation.capture()
            XCTAssertTrue(observation.waitForActivity(until: .now()))
            XCTAssertFalse(
                observation.recordForegroundActivationResult(
                    !first, windowKey: otherWindow, generation: 99, nativeSequence: 100))
            XCTAssertFalse(
                observation.recordForegroundActivationResult(
                    first, windowKey: windowKey, generation: 8, nativeSequence: 12))
            let later = observation.capture()
            XCTAssertEqual(later.trace, original.trace)
            XCTAssertEqual(later.snapshot.encodedBytes, original.snapshot.encodedBytes)
            XCTAssertEqual(later.snapshot.count(.nativeForegroundActivationResult), 1)
            let row = try XCTUnwrap(later.snapshot.last(.nativeForegroundActivationResult))
            XCTAssertEqual(row.value, first ? 1 : 0)
            XCTAssertEqual(row.windowKey, windowKey)
            XCTAssertEqual(row.generation, 7)
            XCTAssertEqual(row.nativeSequence, 11)
            XCTAssertFalse(observation.waitForActivity(until: .now()))
            XCTAssertTrue(observation.record(.hostReady))
            XCTAssertEqual(observation.snapshot().recordCount, 3)
            XCTAssertEqual(observation.snapshot().count(.hostReady), 1)
        }
    }

    func testNormalApplicationWithoutObserverDoesNotEvaluateDiagnosticArguments() async {
        let observation: Win32NativeSmokeObservation? = nil
        var evaluations = 0
        func result() -> Bool {
            evaluations += 1
            return true
        }
        let recorded = observation?.recordForegroundActivationResult(
            result(), windowKey: windowKey, generation: 7, nativeSequence: 11)
        XCTAssertNil(recorded)
        XCTAssertEqual(evaluations, 0)
    }

    func testInvalidRecorderRejectsActivationWithoutNewRowsOrActivity() async {
        let observation = Win32NativeSmokeObservation(runID: runID)
        XCTAssertFalse(observation.record(.fixtureStarted, nativeStartedAtSeconds: .nan))
        XCTAssertTrue(observation.waitForActivity(until: .now()))
        XCTAssertFalse(
            observation.recordForegroundActivationResult(
                true, windowKey: windowKey, generation: 7, nativeSequence: 11))
        XCTAssertFalse(
            observation.recordForegroundActivationResult(
                false, windowKey: windowKey, generation: 7, nativeSequence: 11))
        let capture = observation.capture()
        XCTAssertTrue(capture.snapshot.isInvalid)
        XCTAssertEqual(capture.snapshot.recordCount, 0)
        XCTAssertEqual(capture.snapshot.count(.nativeForegroundActivationResult), 0)
        XCTAssertEqual(capture.trace, Data())
        XCTAssertFalse(observation.waitForActivity(until: .now()))
    }

    func testParserAcceptsBothDiagnosticValuesWithoutSupplyingQualificationEvidence() async throws {
        for didActivate in [false, true] {
            let observation = Win32NativeSmokeObservation(runID: runID)
            var state = NativeOwnedSmokeSharedState.Snapshot()
            state.windowKey = windowKey
            let before = NativeOwnedSmokeValidation.evaluate(
                [], observation: observation.snapshot(), state: state)
            XCTAssertTrue(
                observation.recordForegroundActivationResult(
                    didActivate, windowKey: windowKey, generation: 7, nativeSequence: 11))
            let capture = observation.capture()
            let rows = try NativeOwnedSmokeValidation.decode(capture.trace)
            XCTAssertEqual(rows.count, 1)
            let row = try XCTUnwrap(rows.first)
            XCTAssertTrue(row.isKind(.nativeForegroundActivationResult))
            XCTAssertEqual(row.value, didActivate ? 1 : 0)
            XCTAssertEqual(row.windowID, windowKey.windowID.uuidString)
            XCTAssertEqual(row.lifetimeID, windowKey.lifetimeID.uuidString)
            XCTAssertEqual(row.generation, 7)
            XCTAssertEqual(row.nativeSequence, 11)
            let after = NativeOwnedSmokeValidation.evaluate(rows, observation: capture.snapshot, state: state)
            XCTAssertEqual(after.predicates.count, 27)
            XCTAssertEqual(after.predicates, before.predicates)
            XCTAssertEqual(after.insufficientFairnessExercise, before.insufficientFairnessExercise)
            XCTAssertFalse(after.qualifyingPredicatesSatisfied)
        }
    }
}
