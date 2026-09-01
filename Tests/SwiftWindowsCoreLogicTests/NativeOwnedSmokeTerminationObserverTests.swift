import Foundation
import XCTest

@testable import SwiftWindowsPlatform
@testable import WinSwiftUI

/// Synthetic scalar traces only. These tests do not join a thread or claim a
/// native run; the production recorder still samples its real calling thread.
@MainActor
final class NativeOwnedSmokeTerminationObserverTests: XCTestCase {
    func testSuccessfulPostWaitObservationBelongsToTheJoinWorker() async throws {
        let fixture = TerminationObserverFixture()
        let verdict = try fixture.expect(separation: true, joined: true)
        XCTAssertEqual(verdict.predicates.count, 27)
    }

    func testPostTerminationObserverMayReuseTheNativeNumericThreadID() async throws {
        let fixture = TerminationObserverFixture(observerThread: 10)
        try fixture.expect(separation: true, joined: true)
    }

    func testActorCallbackMayReuseTheNativeNumericIDAfterActualJoin() async throws {
        let fixture = TerminationObserverFixture()
        fixture.insert(.modelFirstResumed, thread: 10, before: .actorStopConsumed)
        try fixture.expect(separation: true, joined: true)
    }

    func testAbsentTerminationPermitsOnlyTheExistingPartialSeparation() async throws {
        for omitJoin in [false, true] {
            let fixture = TerminationObserverFixture()
            fixture.remove(.nativeThreadTerminated)
            if omitJoin { fixture.remove(.nativeThreadJoined) }
            try fixture.expect(separation: true, joined: false)
        }
    }

    func testPresentTerminationCannotQualifyWithoutTheActualJoin() async throws {
        let fixture = TerminationObserverFixture()
        fixture.remove(.nativeThreadJoined)
        try fixture.expect(separation: false, joined: false)
    }

    func testOnlyTheActualSuccessfulWaitResultCanQualifyTermination() async throws {
        let invalidResults: [Int64?] = [nil, -1, 1, 0x80, 0x102, 0xFFFF_FFFF]
        for value in invalidResults {
            let fixture = TerminationObserverFixture()
            fixture.update(.nativeThreadTerminated) { $0.value = value }
            try fixture.expect(separation: false, joined: false)
        }
    }

    func testEachObserverReceiptMustNameTheExactOriginalOwner() async throws {
        let invalidOwners: [UInt64?] = [nil, 0, 11, UInt64.max]
        for kind in [Win32NativeSmokeEventKind.nativeThreadTerminated, .nativeThreadJoined] {
            for auxiliary in invalidOwners {
                let fixture = TerminationObserverFixture()
                fixture.update(kind) { $0.auxiliary = auxiliary }
                try fixture.expect(separation: false, joined: false)
            }
        }
    }

    func testMatchingWrongOwnerClaimsCannotReplaceTheOriginalOwner() async throws {
        let fixture = TerminationObserverFixture()
        fixture.update(.nativeThreadTerminated) { $0.auxiliary = 99 }
        fixture.update(.nativeThreadJoined) { $0.auxiliary = 99 }
        try fixture.expect(separation: false, joined: false)
    }

    func testTerminationAndJoinMustUseTheSameActualObserver() async throws {
        for kind in [Win32NativeSmokeEventKind.nativeThreadTerminated, .nativeThreadJoined] {
            let fixture = TerminationObserverFixture()
            fixture.update(kind) { $0.thread = 41 }
            try fixture.expect(separation: false, joined: false)
        }
    }

    func testAZeroObserverIDCannotQualifyEvenWhenBothReceiptsAgree() async throws {
        let fixture = TerminationObserverFixture(observerThread: 0)
        try fixture.expect(separation: false, joined: false, contiguous: false)
    }

    func testEveryLifecycleReceiptMustBeUniqueBeforeSuccessIsChecked() async throws {
        for kind in [
            Win32NativeSmokeEventKind.nativeThreadEntered, .nativeCloseReplyReturned,
            .nativeThreadTerminated, .nativeThreadJoined,
        ] {
            let fixture = TerminationObserverFixture()
            fixture.duplicate(kind)
            try fixture.expect(separation: false, joined: false)
        }
    }

    func testMissingOwnerOrCloseReturnCannotBeInferredFromFinalState() async throws {
        for kind in [Win32NativeSmokeEventKind.nativeThreadEntered, .nativeCloseReplyReturned] {
            let fixture = TerminationObserverFixture()
            fixture.remove(kind)
            try fixture.expect(separation: false, joined: false)
        }
    }

    func testAnExtraFailedJoinCannotHideBesideASuccessfulJoin() async throws {
        for failedFirst in [false, true] {
            for invalidFlags in [true, false] {
                let fixture = TerminationObserverFixture()
                fixture.duplicate(.nativeThreadJoined)
                fixture.update(.nativeThreadJoined, occurrence: failedFirst ? 0 : 1) {
                    if invalidFlags {
                        $0.flags = 0
                    } else {
                        $0.value = 5
                    }
                }
                try fixture.expect(separation: false, joined: false)
            }
        }
    }

    func testTerminationMustFollowOwnerEntryAndCloseReturn() async throws {
        for predecessor in [
            Win32NativeSmokeEventKind.nativeThreadEntered, .nativeCloseReplyReturned,
        ] {
            let fixture = TerminationObserverFixture()
            fixture.move(.nativeThreadTerminated, before: predecessor)
            try fixture.expect(separation: false, joined: false)
        }
    }

    func testJoinMustFollowTheTerminationObservation() async throws {
        let fixture = TerminationObserverFixture()
        fixture.move(.nativeThreadJoined, before: .nativeThreadTerminated)
        try fixture.expect(separation: false, joined: false)
    }

    func testCloseReturnMustFollowTheOriginalOwnerEntry() async throws {
        let fixture = TerminationObserverFixture()
        fixture.move(.nativeCloseReplyReturned, before: .nativeThreadEntered)
        try fixture.expect(separation: false, joined: false)
    }

    func testCloseReturnMustStillBeProducedByTheOriginalOwner() async throws {
        let fixture = TerminationObserverFixture()
        fixture.update(.nativeCloseReplyReturned) { $0.thread = 40 }
        try fixture.expect(separation: false, joined: false)
    }

    func testNativeOwnerWorkAfterTerminationCannotHideBeforeJoin() async throws {
        for kind in [
            Win32NativeSmokeEventKind.nativeWorkDequeued, .nativeMessageDispatched, .nativeTurnEnded,
        ] {
            let fixture = TerminationObserverFixture()
            fixture.insert(kind, thread: 10, before: .nativeThreadJoined)
            try fixture.expect(separation: false, joined: false)
        }
    }

    func testNativeOwnerWorkCannotUseTheRetiredIDAfterJoin() async throws {
        let fixture = TerminationObserverFixture()
        fixture.append(.nativeWorkDequeued, thread: 10)
        try fixture.expect(separation: false, joined: false)
    }

    func testActorSeparationStillCoversTheTerminationToJoinInterval() async throws {
        for successor in [
            Win32NativeSmokeEventKind.nativeThreadTerminated, .nativeThreadJoined,
        ] {
            let fixture = TerminationObserverFixture()
            fixture.insert(.modelFirstResumed, thread: 10, before: successor)
            // The actual join receipt remains valid. It cannot authorize this
            // actor callback to run on N before the observed join.
            try fixture.expect(separation: false, joined: true)
        }
    }

    func testOtherNativeRecordsStillMustBeProducedByTheOwner() async throws {
        let fixture = TerminationObserverFixture()
        fixture.update(.nativeOwnerReady) { $0.thread = 40 }
        try fixture.expect(separation: false, joined: false)
    }

    func testPreparedOrFailedCloseReturnCannotQualifyTermination() async throws {
        for flags in [UInt32(0), 7, 14, .max] {
            let fixture = TerminationObserverFixture()
            fixture.update(.nativeCloseReplyReturned) { $0.flags = flags }
            try fixture.expect(separation: false, joined: false)
        }
        let invalidResults: [Int64?] = [nil, -1, 1]
        for value in invalidResults {
            let fixture = TerminationObserverFixture()
            fixture.update(.nativeCloseReplyReturned) { $0.value = value }
            try fixture.expect(separation: false, joined: false)
        }
    }

    func testUnsuccessfulJoinReceiptCannotQualifyTermination() async throws {
        for flags in [UInt32(0), 2, .max] {
            let fixture = TerminationObserverFixture()
            fixture.update(.nativeThreadJoined) { $0.flags = flags }
            try fixture.expect(separation: false, joined: false)
        }
        let invalidResults: [Int64?] = [nil, -1, 1, 259]
        for value in invalidResults {
            let fixture = TerminationObserverFixture()
            fixture.update(.nativeThreadJoined) { $0.value = value }
            try fixture.expect(separation: false, joined: false)
        }
    }

    func testNativeJoinAPIFailureCannotBeReplacedByClaimedZeroExit() async throws {
        for phase in [UInt64(0), 1, 2] {
            let fixture = TerminationObserverFixture()
            fixture.remove(.nativeThreadJoined)
            // Wait failure records no termination observation. Get-exit and
            // close-handle failures occur after the successful wait.
            if phase == 0 { fixture.remove(.nativeThreadTerminated) }
            fixture.insert(.nativeJoinFailed, thread: 40, value: 5, auxiliary: phase, before: .actorStopConsumed)
            try fixture.expect(separation: phase == 0, joined: false, noFailure: false)
        }
    }

    func testMissingActorStopOrCoordinatorCannotBeReplacedByClaimedExit() async throws {
        for kind in [Win32NativeSmokeEventKind.actorStopConsumed, .coordinatorReturned] {
            let fixture = TerminationObserverFixture()
            fixture.remove(kind)
            try fixture.expect(separation: true, joined: false)
        }
    }

    func testDuplicateActorStopOrCoordinatorCannotQualifyTheJoin() async throws {
        for kind in [Win32NativeSmokeEventKind.actorStopConsumed, .coordinatorReturned] {
            let fixture = TerminationObserverFixture()
            fixture.duplicate(kind)
            try fixture.expect(separation: true, joined: false)
        }
    }

    func testActorStopAndCoordinatorMustFollowTheActualJoinInOrder() async throws {
        for kind in [Win32NativeSmokeEventKind.actorStopConsumed, .coordinatorReturned] {
            let fixture = TerminationObserverFixture()
            fixture.move(kind, before: .nativeThreadJoined)
            try fixture.expect(separation: true, joined: false)
        }
    }

    func testFailureObservationsRemainAnIndependentRequiredConjunction() async throws {
        for kind in [
            Win32NativeSmokeEventKind.fixtureFailure, .nativeOwnerFailure, .nativeJoinFailed,
        ] {
            let fixture = TerminationObserverFixture()
            fixture.append(kind, thread: 40, value: -1)
            try fixture.expect(separation: true, joined: true, noFailure: false)
        }
        let fixture = TerminationObserverFixture()
        fixture.state.failures.append(NativeOwnedSmokeFailure("synthetic-termination-regression"))
        try fixture.expect(separation: true, joined: true, noFailure: false)
    }

    func testActorAndOwnerExitConditionsRemainRequiredAfterTheJoin() async throws {
        let invalidResults: [Int64?] = [nil, -1, 1]
        for kind in [Win32NativeSmokeEventKind.actorStopConsumed, .coordinatorReturned] {
            for value in invalidResults {
                let fixture = TerminationObserverFixture()
                fixture.update(kind) { $0.value = value }
                try fixture.expect(separation: true, joined: false)
            }
        }
        let invalidExits: [Int32?] = [nil, -1, 1]
        for exitCode in invalidExits {
            let fixture = TerminationObserverFixture()
            fixture.state.ownerExitCode = exitCode
            try fixture.expect(separation: true, joined: false)
        }
    }
}

private struct TerminationObserverTestRow {
    var kind: Win32NativeSmokeEventKind
    var thread: UInt32
    var value: Int64?
    var auxiliary: UInt64?
    var flags: UInt32
}

@MainActor
private final class TerminationObserverFixture {
    private let runID = Foundation.UUID()
    private var rows: [TerminationObserverTestRow] = []
    var state = NativeOwnedSmokeSharedState.Snapshot()

    init(observerThread: UInt32 = 40) {
        state.ownerExitCode = 0
        append(.nativeThreadEntered, thread: 10)
        append(.nativeOwnerReady, thread: 10)
        append(.nativeTurnEnded, thread: 10, value: 1)
        append(.modelFirstAwait, thread: 20)
        append(.nativeCloseReplyReturned, thread: 10, value: 0, flags: 15)
        append(.nativeThreadTerminated, thread: observerThread, value: 0, auxiliary: 10)
        append(.nativeThreadJoined, thread: observerThread, value: 0, auxiliary: 10, flags: 1)
        append(.actorStopConsumed, thread: 20, value: 0)
        append(.coordinatorReturned, thread: 20, value: 0)
    }

    func append(
        _ kind: Win32NativeSmokeEventKind, thread: UInt32,
        value: Int64? = nil, auxiliary: UInt64? = nil, flags: UInt32 = 0
    ) {
        rows.append(
            TerminationObserverTestRow(kind: kind, thread: thread, value: value, auxiliary: auxiliary, flags: flags))
    }

    func insert(
        _ kind: Win32NativeSmokeEventKind, thread: UInt32,
        value: Int64? = nil, auxiliary: UInt64? = nil, flags: UInt32 = 0,
        before successor: Win32NativeSmokeEventKind
    ) {
        let index = rows.firstIndex { $0.kind == successor }!
        rows.insert(
            TerminationObserverTestRow(kind: kind, thread: thread, value: value, auxiliary: auxiliary, flags: flags),
            at: index)
    }

    func update(
        _ kind: Win32NativeSmokeEventKind, occurrence: Int = 0,
        _ change: (inout TerminationObserverTestRow) -> Void
    ) {
        let indices = rows.indices.filter { rows[$0].kind == kind }
        change(&rows[indices[occurrence]])
    }

    func remove(_ kind: Win32NativeSmokeEventKind) { rows.removeAll { $0.kind == kind } }

    func duplicate(_ kind: Win32NativeSmokeEventKind) {
        let index = rows.firstIndex { $0.kind == kind }!
        let original = rows[index]
        rows.insert(original, at: index + 1)
    }

    func move(_ kind: Win32NativeSmokeEventKind, before successor: Win32NativeSmokeEventKind) {
        let original = rows.remove(at: rows.firstIndex { $0.kind == kind }!)
        rows.insert(original, at: rows.firstIndex { $0.kind == successor }!)
    }

    @discardableResult
    func expect(
        separation: Bool, joined: Bool, noFailure: Bool = true, contiguous: Bool = true,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> NativeOwnedSmokeVerdict {
        let verdict = try evaluate()
        // Every mutation is re-encoded with a matching observation count and
        // contiguous ordinals. Only the explicit zero-thread case is invalid.
        XCTAssertEqual(verdict.predicates["bounded-valid-observation"], true, file: file, line: line)
        XCTAssertEqual(verdict.predicates["single-run-contiguous-trace"], contiguous, file: file, line: line)
        XCTAssertEqual(
            verdict.predicates["actor-and-native-owner-thread-separation"], separation, file: file, line: line)
        XCTAssertEqual(
            verdict.predicates["actual-owner-join-and-actor-stop-consumption"], joined, file: file, line: line)
        XCTAssertEqual(verdict.predicates["no-fixture-or-owner-failure"], noFailure, file: file, line: line)
        return verdict
    }

    private func evaluate() throws -> NativeOwnedSmokeVerdict {
        let observation = Win32NativeSmokeObservation(runID: runID)
        for row in rows {
            precondition(
                observation.record(
                    row.kind, value: row.value, auxiliary: row.auxiliary, flags: row.flags))
        }
        let recorded = observation.capture().trace.split(separator: 10)
        var data = Data()
        for (index, row) in rows.enumerated() {
            var encoded = try JSONSerialization.jsonObject(with: Data(recorded[index])) as! [String: Any]
            // Only this synthetic input substitutes thread identities. The
            // production recorder remains unchanged and has no override API.
            encoded["threadID"] = row.thread
            data.append(try JSONSerialization.data(withJSONObject: encoded, options: [.sortedKeys]))
            data.append(10)
        }
        return try NativeOwnedSmokeValidation.evaluate(
            NativeOwnedSmokeValidation.decode(data), observation: observation.snapshot(), state: state)
    }
}
