import Foundation
import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform

/// Pure actor state-machine tests. Handles and destruction receipts are values;
/// these tests never create a window, call DestroyWindow, or start a native loop.
@MainActor
final class Win32NativeCloseControlTests: XCTestCase {
    func testPreparationPinsExactAttemptWithoutClaimingDestruction() async throws {
        let harness = NativeCloseHarness()
        let reservation = try harness.reserve()

        XCTAssertEqual(reservation.windowKey, harness.key)
        XCTAssertEqual(reservation.expectedHandle, harness.handle)
        XCTAssertEqual(harness.control.activeAttempt?.id, reservation.attemptID)
        XCTAssertTrue(harness.control.isHandlingCloseRequest)
        XCTAssertTrue(harness.lifetime.isAlive)
        XCTAssertFalse(harness.lifetime.destructionStarted)
        XCTAssertEqual(harness.lease.validationCount, 1)
        XCTAssertTrue(harness.lease.finished.isEmpty)
        XCTAssertTrue(Win32DispatchScope.permitsTaggedClose(isOwnedRetry: false))

        XCTAssertEqual(harness.finish(reservation), .closed)
    }

    func testOnlyMatchingDestructionAndUnwindCompletesReservedLease() async throws {
        let harness = NativeCloseHarness()
        let reservation = try harness.reserve()

        XCTAssertNil(
            harness.control.completeNativeClose(
                reservation,
                result: .success(
                    Win32NativeCloseDestruction(
                        nativeResult: .succeeded, didObserveNonClientDestruction: true,
                        didUnwindNativeDispatch: false))))
        XCTAssertTrue(harness.lease.finished.isEmpty)
        XCTAssertTrue(harness.control.isHandlingCloseRequest)
        XCTAssertFalse(harness.lifetime.destructionCompleted)

        XCTAssertEqual(harness.finish(reservation), .closed)
        XCTAssertEqual(harness.lease.finished, [.closed])
        XCTAssertTrue(harness.lifetime.destructionCompleted)
        XCTAssertFalse(harness.control.isHandlingCloseRequest)
        XCTAssertNil(harness.finish(reservation))
        XCTAssertEqual(harness.lease.finished.count, 1)
    }

    func testMismatchedReservationCannotFinishCurrentClose() async throws {
        let harness = NativeCloseHarness()
        let reservation = try harness.reserve()
        let wrong = Win32NativeCloseReservation(
            windowKey: reservation.windowKey, requestID: reservation.requestID,
            attemptID: reservation.attemptID, expectedHandle: reservation.expectedHandle)

        XCTAssertNotEqual(wrong.reservationID, reservation.reservationID)
        XCTAssertNil(harness.finish(wrong))
        XCTAssertTrue(harness.lease.finished.isEmpty)
        XCTAssertEqual(harness.control.activeAttempt?.id, reservation.attemptID)
        XCTAssertEqual(harness.finish(reservation), .closed)
    }

    func testNativeFailurePreservesActualErrorWithoutClaimingDestruction() async throws {
        let harness = NativeCloseHarness()
        let reservation = try harness.reserve()

        XCTAssertEqual(
            harness.control.completeNativeClose(
                reservation,
                result: .success(
                    Win32NativeCloseDestruction(
                        nativeResult: .failed(87), didObserveNonClientDestruction: false,
                        didUnwindNativeDispatch: true))),
            .destructionFailed(.native(87)))
        XCTAssertEqual(harness.lease.finished, [.destructionFailed(.native(87))])
        XCTAssertFalse(harness.lifetime.destructionCompleted)
        XCTAssertFalse(harness.control.isHandlingCloseRequest)
    }

    func testSuccessfulNativeReturnWithoutDestructionIsNotClosed() async throws {
        let harness = NativeCloseHarness()
        let reservation = try harness.reserve()

        XCTAssertEqual(
            harness.control.completeNativeClose(
                reservation,
                result: .success(
                    Win32NativeCloseDestruction(
                        nativeResult: .succeeded, didObserveNonClientDestruction: false,
                        didUnwindNativeDispatch: true))),
            .destructionFailed(.destructionNotObserved))
        XCTAssertFalse(harness.lifetime.destructionCompleted)
    }

    func testObservedDestructionWinsOverFailedNativeReturnAsInLegacyPath() async throws {
        let harness = NativeCloseHarness()
        let reservation = try harness.reserve()

        XCTAssertEqual(
            harness.control.completeNativeClose(
                reservation,
                result: .success(
                    Win32NativeCloseDestruction(
                        nativeResult: .failed(1400), didObserveNonClientDestruction: true,
                        didUnwindNativeDispatch: true))), .closed)
        XCTAssertTrue(harness.lifetime.destructionCompleted)
    }

    func testOwnerFailureRetainsTypedFailureAndFinishesExactlyOnce() async throws {
        let harness = NativeCloseHarness()
        let reservation = try harness.reserve()
        let failure = NativeWindowOwnerFailure.native(operation: "DetachPresenter", code: -2_147_467_259)

        XCTAssertEqual(
            harness.control.completeNativeClose(reservation, result: .failure(failure)),
            .destructionFailed(.owner(failure)))
        XCTAssertNil(harness.control.completeNativeClose(reservation, result: .failure(.ownerStopped)))
        XCTAssertEqual(harness.lease.finished, [.destructionFailed(.owner(failure))])
        XCTAssertFalse(harness.lifetime.destructionCompleted)
    }

    func testSecondNativeOrLegacyAttemptCannotBorrowPendingReservation() async throws {
        let harness = NativeCloseHarness()
        let reservation = try harness.reserve()
        let second = harness.prepare()
        guard case .completed(let outcome) = second else {
            return XCTFail("A second native close received a reservation")
        }
        XCTAssertEqual(outcome, .busy(.closeInProgress))
        var destroyed = false
        XCTAssertEqual(
            harness.control.attemptClose(
                expectedHandle: harness.handle, ticket: nil, participants: [], preflight: { true },
                destroy: { _ in
                    destroyed = true
                    return .succeeded
                }), .busy(.closeInProgress))
        XCTAssertFalse(destroyed)
        XCTAssertEqual(harness.preflightCount, 1)
        XCTAssertEqual(harness.finish(reservation), .closed)
    }

    func testVetoDoesNotReserveOrFinishUnpreparedAuthority() async {
        let harness = NativeCloseHarness()
        guard case .completed(let outcome) = harness.prepare(approved: false) else {
            return XCTFail("A veto received a reservation")
        }

        XCTAssertEqual(outcome, .vetoed)
        XCTAssertEqual(harness.lease.validationCount, 0)
        XCTAssertTrue(harness.lease.finished.isEmpty)
        XCTAssertTrue(harness.lifetime.isAlive)
        XCTAssertNil(harness.control.activeAttempt)
    }

    func testFinalTopologyChangeFinishesPreparedLeaseAndConsumesTicket() async throws {
        let harness = NativeCloseHarness()
        let ticket = try XCTUnwrap(harness.registration.makeTicket(intentID: Foundation.UUID()))
        harness.lease.onValidate = { [weak harness] in harness?.control.noteTopologyChanged() }
        guard case .completed(let outcome) = harness.prepare(ticket: ticket) else {
            return XCTFail("A stale topology received a reservation")
        }

        XCTAssertEqual(outcome, .unavailable)
        XCTAssertEqual(harness.lease.finished, [.unavailable])
        XCTAssertFalse(ticket.isCurrent)
        XCTAssertNil(harness.control.activeAttempt)
        XCTAssertTrue(harness.lifetime.isAlive)
    }

    func testBusyPreflightLeavesTicketReusableButReservationConsumesIt() async throws {
        let harness = NativeCloseHarness()
        let ticket = try XCTUnwrap(harness.registration.makeTicket(intentID: Foundation.UUID()))
        let busy = harness.control.prepareNativeClose(
            windowKey: harness.key, requestID: NativeWindowRequestID(), expectedHandle: harness.handle,
            ticket: ticket, participants: [],
            preflight: {
                harness.control.activeAttempt?.deferUntilReady(.buildsNotSettled)
                return false
            })
        guard case .completed(let outcome) = busy else {
            return XCTFail("A busy preflight received a reservation")
        }
        XCTAssertEqual(outcome, .busy(.buildsNotSettled))
        XCTAssertTrue(ticket.isCurrent)

        let reservation = try harness.reserve(ticket: ticket)
        XCTAssertFalse(ticket.isCurrent)
        XCTAssertEqual(harness.finish(reservation), .closed)
    }

    func testOldLifetimeReceiptCannotDestroyReusedHandleLifetime() async throws {
        let harness = NativeCloseHarness()
        let reservation = try harness.reserve()
        let replacement = harness.control.beginLifetime(generation: 2)
        harness.control.didCreate(replacement, handle: harness.handle)

        XCTAssertEqual(harness.finish(reservation), .closed)
        XCTAssertTrue(harness.lifetime.destructionCompleted)
        XCTAssertTrue(replacement.isAlive)
        XCTAssertFalse(replacement.destructionCompleted)
        XCTAssertTrue(harness.control.lifetime === replacement)
    }

    func testFinishCannotReenterAndConsumeSameReservation() async throws {
        let harness = NativeCloseHarness()
        let reservation = try harness.reserve()
        var duplicate: Win32CloseAttemptOutcome?
        harness.lease.onFinish = { [weak harness] in
            duplicate = harness?.finish(reservation)
        }

        XCTAssertEqual(harness.finish(reservation), .closed)
        XCTAssertNil(duplicate)
        XCTAssertEqual(harness.lease.finished, [.closed])
        XCTAssertTrue(Win32DispatchScope.permitsTaggedClose(isOwnedRetry: false))
    }

    func testWrongNativeLifetimeAndHeadlessWindowDoNotEnterPreflight() async {
        let harness = NativeCloseHarness()
        let wrong = harness.control.prepareNativeClose(
            windowKey: NativeWindowKey(windowID: harness.key.windowID), requestID: NativeWindowRequestID(),
            expectedHandle: harness.handle, ticket: nil, participants: [],
            preflight: {
                XCTFail()
                return true
            })
        guard case .completed(let outcome) = wrong else { return XCTFail("Wrong lifetime was admitted") }
        XCTAssertEqual(outcome, .unavailable)

        let control = Win32CloseControl()
        let headless = control.beginLifetime(generation: 1)
        let result = control.prepareNativeClose(
            windowKey: NativeWindowKey(lifetimeID: headless.id), requestID: NativeWindowRequestID(),
            expectedHandle: 0, ticket: nil, participants: [],
            preflight: {
                XCTFail()
                return true
            })
        guard case .completed(let headlessOutcome) = result else { return XCTFail("Headless window was admitted") }
        XCTAssertEqual(headlessOutcome, .unavailable)
    }

    func testAcceptedDeferredWakeFailureRetiresOnlyMatchingRecordOnce() async throws {
        let harness = NativeCloseHarness()
        var postedNonces: [UInt] = []
        XCTAssertTrue(
            harness.control.installNativeDeferredWake { _, nonce in
                postedNonces.append(nonce)
                return .accepted
            })
        let ticket = try XCTUnwrap(harness.registration.makeTicket(intentID: Foundation.UUID()))
        var failures: [UInt32] = []
        var reentrantSubmission: Win32DeferredCloseSubmission?
        XCTAssertEqual(
            harness.registration.enqueue(
                ticket: ticket, phase: .prompt,
                onPostFailure: { [weak harness] ticket, code in
                    failures.append(code)
                    reentrantSubmission = harness?.registration.enqueue(
                        ticket: ticket, phase: .prompt,
                        onPostFailure: { _, _ in XCTFail("Duplicate failure") },
                        action: { _ in XCTFail("Failure cleanup cannot reuse delivery") })
                }, action: { _ in XCTFail("Failed wake executed its action") }), .queued)
        let nonce = try XCTUnwrap(postedNonces.first)

        harness.control.failDeferredWake(nonce: nonce + 1, code: 7)
        XCTAssertTrue(failures.isEmpty)
        harness.control.failDeferredWake(nonce: nonce, code: 5)
        harness.control.failDeferredWake(nonce: nonce, code: 99)
        harness.control.receiveDeferredWake(nonce: nonce)

        XCTAssertEqual(failures, [5])
        XCTAssertEqual(reentrantSubmission, .busy)
        XCTAssertTrue(ticket.isCurrent)
        XCTAssertEqual(
            harness.registration.enqueue(
                ticket: ticket, phase: .prompt, onPostFailure: { _, code in failures.append(code) },
                action: { _ in XCTFail("Second failed wake executed") }), .queued)
        let replacement = try XCTUnwrap(postedNonces.last)
        XCTAssertNotEqual(replacement, nonce)
        harness.control.failDeferredWake(nonce: nonce, code: 88)
        XCTAssertEqual(failures, [5])
        harness.control.failDeferredWake(nonce: replacement, code: 6)
        XCTAssertEqual(failures, [5, 6])
    }

    func testLogicalDeferredAdmissionFailureDoesNotInventNativeError() async throws {
        let harness = NativeCloseHarness()
        let ticket = try XCTUnwrap(harness.registration.makeTicket(intentID: Foundation.UUID()))
        var typedFailures: [NativeWindowOwnerFailure] = []
        var nativeFailures: [UInt32] = []
        XCTAssertTrue(
            harness.control.installNativeDeferredWake { [weak registration = harness.registration] _, _ in
                typedFailures.append(.ownerStopped)
                registration?.revoke()
                return .rejected(.ownerStopped)
            })

        XCTAssertEqual(
            harness.registration.enqueue(
                ticket: ticket, phase: .prompt, onPostFailure: { _, code in nativeFailures.append(code) },
                action: { _ in XCTFail("Unavailable wake executed") }), .unavailable)
        XCTAssertEqual(typedFailures, [.ownerStopped])
        XCTAssertTrue(nativeFailures.isEmpty)
        XCTAssertFalse(ticket.isCurrent)
    }

    func testImmediateNativePostFailureIsReturnedWithoutSecondNotification() async throws {
        let harness = NativeCloseHarness()
        XCTAssertTrue(harness.control.installNativeDeferredWake { _, _ in .rejected(.postFailed(code: 123)) })
        let ticket = try XCTUnwrap(harness.registration.makeTicket(intentID: Foundation.UUID()))
        var notified = false

        XCTAssertEqual(
            harness.registration.enqueue(
                ticket: ticket, phase: .prompt, onPostFailure: { _, _ in notified = true },
                action: { _ in XCTFail("Rejected wake executed") }), .postFailed(123))
        XCTAssertFalse(notified)
    }

    func testCannotReplaceDeferredPosterAfterWorkWasAdmitted() async throws {
        let harness = NativeCloseHarness()
        var nonce: UInt?
        XCTAssertTrue(
            harness.control.installNativeDeferredWake { _, value in
                nonce = value
                return .accepted
            })
        let ticket = try XCTUnwrap(harness.registration.makeTicket(intentID: Foundation.UUID()))
        XCTAssertEqual(
            harness.registration.enqueue(
                ticket: ticket, phase: .prompt, onPostFailure: { _, _ in }, action: { _ in }), .queued)
        XCTAssertFalse(harness.control.installNativeDeferredWake { _, _ in .accepted })
        harness.control.failDeferredWake(nonce: try XCTUnwrap(nonce), code: 5)
    }
}

@MainActor
private final class NativeCloseHarness {
    let control = Win32CloseControl()
    let key = NativeWindowKey()
    let handle: UInt = 101
    let lease = NativeCloseLease()
    let authority: NativeCloseAuthority
    let lifetime: Win32CloseLifetime
    let registration: Win32CloseRegistration
    var preflightCount = 0

    init() {
        authority = NativeCloseAuthority(lease: lease)
        lifetime = control.beginLifetime(generation: 1, id: key.lifetimeID)
        control.didCreate(lifetime, handle: handle)
        registration = control.installAuthority(authority)!
    }

    func prepare(ticket: Win32CloseTicket? = nil, approved: Bool = true) -> Win32NativeClosePreparation {
        control.prepareNativeClose(
            windowKey: key, requestID: NativeWindowRequestID(), expectedHandle: handle,
            ticket: ticket, participants: [authority],
            preflight: {
                self.preflightCount += 1
                return approved
            })
    }

    func reserve(ticket: Win32CloseTicket? = nil) throws -> Win32NativeCloseReservation {
        guard case .reserved(let reservation) = prepare(ticket: ticket) else {
            XCTFail("Expected a prepared native close")
            throw NativeCloseTestFailure.notReserved
        }
        return reservation
    }

    func finish(_ reservation: Win32NativeCloseReservation) -> Win32CloseAttemptOutcome? {
        control.completeNativeClose(
            reservation,
            result: .success(
                Win32NativeCloseDestruction(
                    nativeResult: .succeeded, didObserveNonClientDestruction: true,
                    didUnwindNativeDispatch: true)))
    }
}

private enum NativeCloseTestFailure: Error { case notReserved }

@MainActor
private final class NativeCloseAuthority: Win32CloseAuthority {
    let lease: NativeCloseLease

    init(lease: NativeCloseLease) { self.lease = lease }

    func prepareCloseCommit(for attempt: Win32CloseAttempt) -> Win32CloseCommitPreparation { .ready(lease) }
}

@MainActor
private final class NativeCloseLease: Win32CloseCommitLease {
    var validationCount = 0
    var finished: [Win32CloseAttemptOutcome] = []
    var onValidate: (@MainActor () -> Void)?
    var onFinish: (@MainActor () -> Void)?

    func validateAndReserve() -> Win32CloseCommitDecision {
        validationCount += 1
        onValidate?()
        return .reserved
    }

    func finish(with outcome: Win32CloseAttemptOutcome) {
        finished.append(outcome)
        onFinish?()
    }
}
