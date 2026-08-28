import Foundation
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform

/// Exercises the actual close state machine with per-attempt native closures.
/// Fake handles never enter Win32, and destruction is acknowledged explicitly.
@MainActor
final class Win32CloseControlTests: XCTestCase {
    func testLegacyApprovalClosesOnlyAfterCapturedDestructionCompletes() async {
        let harness = CloseControlHarness()

        XCTAssertEqual(harness.attempt(), .closed)
        XCTAssertEqual(harness.preflightCount, 1)
        XCTAssertEqual(harness.destroyedHandles, [harness.handle])
        XCTAssertTrue(harness.originalLifetime.destructionCompleted)
        XCTAssertFalse(harness.control.isHandlingCloseRequest)
        XCTAssertNil(harness.control.activeAttempt)
    }

    func testLegacyVetoDoesNotDestroyOrCreateAnAuthorityRequirement() async {
        let harness = CloseControlHarness()

        XCTAssertEqual(harness.attempt(preflight: { false }), .vetoed)
        XCTAssertTrue(harness.originalLifetime.isAlive)
        XCTAssertTrue(harness.destroyedHandles.isEmpty)
        XCTAssertNil(harness.control.registration)
        XCTAssertEqual(harness.attempt(), .closed)
    }

    func testDisabledCloseCannotBeApprovedByLegacyDelegate() async {
        let harness = CloseControlHarness()
        harness.control.isCloseEnabled = false

        XCTAssertEqual(harness.attempt(), .vetoed)
        XCTAssertEqual(harness.preflightCount, 1)
        XCTAssertTrue(harness.destroyedHandles.isEmpty)
        XCTAssertTrue(harness.originalLifetime.isAlive)
    }

    func testMissingFailedAndWrongHandleLifetimesDoNotEnterPreflight() async {
        let control = Win32CloseControl()
        var preflightCount = 0
        var destroyCount = 0
        @MainActor func attempt(_ handle: UInt) -> Win32CloseAttemptOutcome {
            control.attemptClose(
                expectedHandle: handle, ticket: nil, participants: [],
                preflight: {
                    preflightCount += 1
                    return true
                },
                destroy: { _ in
                    destroyCount += 1
                    return .succeeded
                })
        }

        XCTAssertEqual(attempt(101), .unavailable)
        let failed = control.beginLifetime(generation: 1)
        control.creationFailed(failed)
        control.didCreate(failed, handle: 101)
        XCTAssertNil(failed.handle)
        XCTAssertEqual(attempt(101), .unavailable)
        let live = control.beginLifetime(generation: 2)
        control.didCreate(live, handle: 101)
        XCTAssertEqual(attempt(202), .unavailable)
        XCTAssertEqual(preflightCount, 0)
        XCTAssertEqual(destroyCount, 0)
        XCTAssertTrue(live.isAlive)
    }

    func testAuthorityInstalledBeforeCreationBindsOnlyItsFirstLifetime() async throws {
        let control = Win32CloseControl()
        let authority = CloseControlAuthority { _ in .vetoed }
        let registration = try XCTUnwrap(control.installAuthority(authority))
        XCTAssertNil(registration.makeTicket(intentID: UUID()))
        let first = control.beginLifetime(generation: 1)
        control.didCreate(first, handle: 101)
        let ticket = try XCTUnwrap(registration.makeTicket(intentID: UUID()))
        XCTAssertTrue(ticket.isCurrent)

        control.beginDestruction(first)
        control.completeDestruction(first)
        let second = control.beginLifetime(generation: 2)
        control.didCreate(second, handle: 101)

        XCTAssertTrue(registration.isRevoked)
        XCTAssertFalse(ticket.isCurrent)
        XCTAssertNil(registration.makeTicket(intentID: UUID()))
        XCTAssertTrue(second.isAlive)
        withExtendedLifetime(authority) {}
    }

    func testLosingWeakAuthorityDoesNotRestoreLegacyDefaultApproval() async throws {
        let harness = CloseControlHarness()
        var owner: CloseControlAuthority? = CloseControlAuthority { _ in .vetoed }
        weak var weakOwner = owner
        @MainActor func installOwner() throws -> Win32CloseRegistration {
            try XCTUnwrap(harness.control.installAuthority(try XCTUnwrap(owner)))
        }
        let registration = try installOwner()
        let ticket = try XCTUnwrap(registration.makeTicket(intentID: UUID()))
        owner = nil

        XCTAssertNil(weakOwner)
        XCTAssertFalse(registration.isCurrent)
        XCTAssertFalse(ticket.isCurrent)
        XCTAssertEqual(harness.attempt(), .unavailable)
        XCTAssertEqual(harness.attempt(ticket: ticket), .unavailable)
        XCTAssertEqual(harness.preflightCount, 0)
        XCTAssertTrue(harness.destroyedHandles.isEmpty)
    }

    func testRevokedRegistrationRejectsBothTaggedAndOrdinaryRequests() async throws {
        let harness = CloseControlHarness()
        let lease = CloseControlLease()
        let registration = try harness.install(lease)
        let ticket = try XCTUnwrap(registration.makeTicket(intentID: UUID()))
        registration.revoke()

        XCTAssertEqual(harness.attempt(ticket: ticket), .unavailable)
        XCTAssertEqual(harness.attempt(), .unavailable)
        XCTAssertFalse(ticket.isCurrent)
        XCTAssertEqual(harness.preflightCount, 0)
        XCTAssertEqual(harness.authority?.preparationCount, 0)
        XCTAssertEqual(lease.validationCount, 0)
        XCTAssertTrue(lease.finishedOutcomes.isEmpty)
        XCTAssertTrue(harness.destroyedHandles.isEmpty)
    }

    func testInvalidatingTicketsPreservesAuthorityAndAllowsFreshTicketForSameIntent() async throws {
        let harness = CloseControlHarness()
        let lease = CloseControlLease()
        let registration = try harness.install(lease)
        let intentID = UUID()
        let stale = try XCTUnwrap(registration.makeTicket(intentID: intentID))
        registration.invalidateTickets()
        let fresh = try XCTUnwrap(registration.makeTicket(intentID: intentID))

        XCTAssertTrue(registration.isCurrent)
        XCTAssertFalse(registration.isRevoked)
        XCTAssertTrue(harness.control.registration === registration)
        XCTAssertEqual(stale.intentID, fresh.intentID)
        XCTAssertNotEqual(stale.id, fresh.id)
        XCTAssertFalse(stale.isCurrent)
        XCTAssertTrue(fresh.isCurrent)
        XCTAssertEqual(harness.attempt(ticket: stale), .unavailable)
        XCTAssertEqual(harness.preflightCount, 0)
        XCTAssertTrue(fresh.isCurrent)
        XCTAssertEqual(harness.attempt(ticket: fresh), .closed)
        XCTAssertEqual(harness.authority?.preparationCount, 1)
        XCTAssertEqual(lease.validationCount, 1)
        XCTAssertEqual(lease.finishedOutcomes, [.closed])
        XCTAssertEqual(harness.destroyedHandles, [harness.handle])
    }

    func testTicketEpochChangeInvalidatesOrdinaryAndTaggedAttemptsAtEveryCommitStage() async throws {
        for tagged in [false, true] {
            for stage in CloseControlCallbackStage.allCases {
                let harness = CloseControlHarness()
                defer { harness.authority = nil }
                let session = CloseControlSession(lifetime: harness.originalLifetime)
                let lease = CloseControlLease(session: session)
                let registration = try harness.install(preparation: { _ in
                    if stage == .preparation { harness.control.registration?.invalidateTickets() }
                    return .ready(lease)
                })
                let oldTicket = try XCTUnwrap(registration.makeTicket(intentID: UUID()))
                if stage == .validation {
                    lease.afterReservation = {
                        XCTAssertTrue(session.reservationIsActive)
                        registration.invalidateTickets()
                    }
                }

                XCTAssertEqual(
                    harness.attempt(
                        ticket: tagged ? oldTicket : nil,
                        preflight: {
                            XCTAssertEqual(harness.control.activeAttempt?.ticket == nil, !tagged)
                            if stage == .preflight { registration.invalidateTickets() }
                            return true
                        }), .unavailable)
                XCTAssertTrue(registration.isCurrent)
                XCTAssertFalse(registration.isRevoked)
                XCTAssertTrue(harness.originalLifetime.isAlive)
                XCTAssertFalse(oldTicket.isCurrent)
                XCTAssertTrue(harness.destroyedHandles.isEmpty)
                XCTAssertEqual(harness.authority?.preparationCount, stage == .preflight ? 0 : 1)
                XCTAssertEqual(lease.validationCount, stage == .validation ? 1 : 0)
                XCTAssertEqual(lease.finishedOutcomes, stage == .preflight ? [] : [.unavailable])
                XCTAssertEqual(session.finishCount, stage == .preflight ? 0 : 1)
                XCTAssertFalse(session.reservationIsActive)
                XCTAssertEqual(session.approvalConsumed, stage == .validation)
                let fresh = try XCTUnwrap(registration.makeTicket(intentID: UUID()))
                XCTAssertTrue(fresh.isCurrent)
                XCTAssertNil(harness.control.activeAttempt)
            }
        }
    }

    func testReplacingAuthorityRevokesOldRegistrationAndItsTicket() async throws {
        let harness = CloseControlHarness()
        let oldLease = CloseControlLease()
        let oldRegistration = try harness.install(oldLease)
        let oldTicket = try XCTUnwrap(oldRegistration.makeTicket(intentID: UUID()))
        let newLease = CloseControlLease()
        let newRegistration = try harness.install(newLease)
        let newTicket = try XCTUnwrap(newRegistration.makeTicket(intentID: UUID()))

        XCTAssertTrue(oldRegistration.isRevoked)
        XCTAssertFalse(oldTicket.isCurrent)
        XCTAssertTrue(newTicket.isCurrent)
        XCTAssertEqual(harness.attempt(ticket: oldTicket), .unavailable)
        XCTAssertTrue(newTicket.isCurrent)
        XCTAssertEqual(harness.attempt(ticket: newTicket), .closed)
        XCTAssertEqual(oldLease.validationCount, 0)
        XCTAssertEqual(newLease.validationCount, 1)
        XCTAssertEqual(newLease.finishedOutcomes, [.closed])
    }

    func testAuthorityInstallationWaitsUntilDestructionCompletesThenBindsNextCreation() async throws {
        let harness = CloseControlHarness()
        harness.control.beginDestruction(harness.originalLifetime)
        let replacement = CloseControlAuthority { _ in .vetoed }

        XCTAssertNil(harness.control.installAuthority(replacement))
        XCTAssertNil(harness.control.registration)
        harness.control.completeDestruction(harness.originalLifetime)
        let registration = try XCTUnwrap(harness.control.installAuthority(replacement))
        XCTAssertNil(registration.makeTicket(intentID: UUID()))
        let next = harness.control.beginLifetime(generation: 2)
        harness.control.didCreate(next, handle: harness.handle)
        let ticket = try XCTUnwrap(registration.makeTicket(intentID: UUID()))

        XCTAssertTrue(ticket.isCurrent)
        XCTAssertTrue(next.isAlive)
        XCTAssertEqual(harness.attempt(ticket: ticket), .vetoed)
        XCTAssertEqual(replacement.preparationCount, 1)
        XCTAssertTrue(harness.destroyedHandles.isEmpty)
        withExtendedLifetime(replacement) {}
    }

    func testTicketCancellationIsPermanentAndDoesNotCancelAnotherIntent() async throws {
        let harness = CloseControlHarness()
        let registration = try harness.install(CloseControlLease())
        let cancelled = try XCTUnwrap(registration.makeTicket(intentID: UUID()))
        let current = try XCTUnwrap(registration.makeTicket(intentID: UUID()))
        cancelled.cancel()
        cancelled.cancel()

        XCTAssertFalse(cancelled.isCurrent)
        XCTAssertEqual(harness.attempt(ticket: cancelled), .unavailable)
        XCTAssertTrue(current.isCurrent)
        XCTAssertEqual(harness.preflightCount, 0)
        XCTAssertEqual(harness.attempt(ticket: current), .closed)
        XCTAssertFalse(current.isCurrent)
    }

    func testWrongWindowCannotConsumeTheOtherWindowsTicketEvenWithSameHandle() async throws {
        let first = CloseControlHarness(handle: 101)
        let second = CloseControlHarness(handle: 101)
        let registration = try first.install(CloseControlLease())
        let ticket = try XCTUnwrap(registration.makeTicket(intentID: UUID()))
        _ = try second.install(CloseControlLease())

        XCTAssertEqual(second.attempt(ticket: ticket), .unavailable)
        XCTAssertEqual(second.preflightCount, 0)
        XCTAssertTrue(second.destroyedHandles.isEmpty)
        XCTAssertTrue(ticket.isCurrent)
        XCTAssertEqual(first.attempt(ticket: ticket), .closed)
        XCTAssertTrue(second.originalLifetime.isAlive)
    }

    func testConcretePreflightVetoCannotBeOverriddenByFinalAuthority() async throws {
        let harness = CloseControlHarness()
        let lease = CloseControlLease()
        let registration = try harness.install(lease)
        let ticket = try XCTUnwrap(registration.makeTicket(intentID: UUID()))

        XCTAssertEqual(harness.attempt(ticket: ticket, preflight: { false }), .vetoed)
        XCTAssertFalse(ticket.isCurrent)
        XCTAssertEqual(harness.authority?.preparationCount, 0)
        XCTAssertEqual(lease.validationCount, 0)
        XCTAssertTrue(lease.finishedOutcomes.isEmpty)
        XCTAssertTrue(harness.destroyedHandles.isEmpty)
    }

    func testBusyPreflightRetainsExactTicketAndFirstReportedReason() async throws {
        let harness = CloseControlHarness()
        let registration = try harness.install(CloseControlLease())
        let intentID = UUID()
        let ticket = try XCTUnwrap(registration.makeTicket(intentID: intentID))
        var firstAttemptID: UUID?

        XCTAssertEqual(
            harness.attempt(
                ticket: ticket,
                preflight: {
                    let attempt = harness.control.activeAttempt
                    XCTAssertTrue(attempt?.ticket === ticket)
                    XCTAssertEqual(attempt?.intentID, intentID)
                    firstAttemptID = attempt?.id
                    attempt?.deferUntilReady(.buildsNotSettled)
                    attempt?.deferUntilReady(.ownerOperation)
                    return false
                }), .busy(.buildsNotSettled))
        XCTAssertTrue(ticket.isCurrent)
        XCTAssertNil(harness.control.activeAttempt)
        XCTAssertEqual(harness.authority?.preparationCount, 0)
        XCTAssertEqual(
            harness.attempt(
                ticket: ticket,
                preflight: {
                    XCTAssertTrue(harness.control.activeAttempt?.ticket === ticket)
                    XCTAssertNotEqual(harness.control.activeAttempt?.id, firstAttemptID)
                    XCTAssertNil(harness.control.activeAttempt?.busyReason)
                    return true
                }), .closed)
    }

    func testBusyAnnotationDoesNotOverrideAnAffirmativeDelegateVote() async {
        let harness = CloseControlHarness()

        XCTAssertEqual(
            harness.attempt(preflight: {
                harness.control.activeAttempt?.deferUntilReady(.nativeDispatch)
                return true
            }), .closed)
        XCTAssertEqual(harness.destroyedHandles, [harness.handle])
    }

    func testPreflightStateChangesCannotReachFinalAuthorityDespiteApproval() async throws {
        let cases: [(Win32CloseAttemptOutcome, @MainActor (CloseControlHarness, Win32CloseTicket) -> Void)] = [
            (.unavailable, { harness, _ in harness.control.noteTopologyChanged() }),
            (.unavailable, { harness, _ in harness.control.registration?.revoke() }),
            (
                .unavailable,
                { harness, _ in
                    harness.control.didCreate(harness.originalLifetime, handle: harness.handle + 1)
                }
            ),
            (.vetoed, { harness, _ in harness.control.isCloseEnabled = false }),
            (.unavailable, { _, ticket in ticket.cancel() }),
        ]
        for (expected, mutate) in cases {
            let harness = CloseControlHarness()
            let lease = CloseControlLease()
            let registration = try harness.install(lease)
            let ticket = try XCTUnwrap(registration.makeTicket(intentID: UUID()))

            XCTAssertEqual(
                harness.attempt(
                    ticket: ticket,
                    preflight: {
                        mutate(harness, ticket)
                        return true
                    }), expected)
            XCTAssertEqual(harness.preflightCount, 1)
            XCTAssertEqual(harness.authority?.preparationCount, 0)
            XCTAssertEqual(lease.validationCount, 0)
            XCTAssertTrue(lease.finishedOutcomes.isEmpty)
            XCTAssertTrue(harness.destroyedHandles.isEmpty)
            XCTAssertFalse(ticket.isCurrent)
            XCTAssertFalse(harness.originalLifetime.destructionStarted)
        }
    }

    func testPreparationRejectionsDoNotValidateOrDestroyAndBusyKeepsTicket() async throws {
        let cases: [(Win32CloseCommitPreparation, Win32CloseAttemptOutcome, Bool)] = [
            (.vetoed, .vetoed, false),
            (.busy(.ownerOperation), .busy(.ownerOperation), true),
            (.unavailable, .unavailable, false),
        ]
        for (preparation, expected, ticketRemainsCurrent) in cases {
            let harness = CloseControlHarness()
            let registration = try harness.install(preparation: { _ in preparation })
            let ticket = try XCTUnwrap(registration.makeTicket(intentID: UUID()))

            XCTAssertEqual(harness.attempt(ticket: ticket), expected)
            XCTAssertEqual(harness.preflightCount, 1)
            XCTAssertEqual(harness.authority?.preparationCount, 1)
            XCTAssertEqual(ticket.isCurrent, ticketRemainsCurrent)
            XCTAssertTrue(harness.destroyedHandles.isEmpty)
            XCTAssertTrue(harness.originalLifetime.isAlive)
        }
    }

    func testValidationRejectionsFinishExactlyOnceAfterTerminalTicketConsumption() async throws {
        let cases: [(Win32CloseCommitDecision, Win32CloseAttemptOutcome, Bool)] = [
            (.vetoed, .vetoed, false),
            (.busy(.buildsNotSettled), .busy(.buildsNotSettled), true),
            (.unavailable, .unavailable, false),
        ]
        for (decision, expected, ticketRemainsCurrent) in cases {
            let harness = CloseControlHarness()
            defer { harness.authority = nil }
            let lease = CloseControlLease(validation: { decision })
            let registration = try harness.install(lease)
            let ticket = try XCTUnwrap(registration.makeTicket(intentID: UUID()))
            lease.onFinish = { outcome in
                XCTAssertEqual(outcome, expected)
                XCTAssertEqual(ticket.isCurrent, ticketRemainsCurrent)
                XCTAssertTrue(harness.control.isHandlingCloseRequest)
                XCTAssertTrue(harness.control.activeAttempt?.ticket === ticket)
            }

            XCTAssertEqual(harness.attempt(ticket: ticket), expected)
            XCTAssertEqual(lease.validationCount, 1)
            XCTAssertEqual(lease.finishedOutcomes, [expected])
            XCTAssertEqual(ticket.isCurrent, ticketRemainsCurrent)
            XCTAssertTrue(harness.destroyedHandles.isEmpty)
            XCTAssertNil(harness.control.activeAttempt)
        }
    }

    func testFinalHandleChangeRollsBackReservationWithoutReusingApproval() async throws {
        try assertFinalReservationGuardRejects(.unavailable) { harness, _ in
            harness.control.didCreate(harness.originalLifetime, handle: harness.handle + 1)
        }
    }

    func testFinalTopologyChangeRollsBackReservationWithoutDestroying() async throws {
        try assertFinalReservationGuardRejects(.unavailable) { harness, _ in
            harness.control.noteTopologyChanged()
        }
    }

    func testFinalRegistrationRevocationRollsBackReservationWithoutDestroying() async throws {
        try assertFinalReservationGuardRejects(.unavailable) { harness, _ in
            harness.control.registration?.revoke()
        }
    }

    func testFinalCloseDisablementRollsBackReservationAndReportsVeto() async throws {
        try assertFinalReservationGuardRejects(.vetoed) { harness, _ in
            harness.control.isCloseEnabled = false
        }
    }

    func testFinalTicketCancellationRollsBackReservationWithoutReusingApproval() async throws {
        try assertFinalReservationGuardRejects(.unavailable) { _, ticket in
            ticket.cancel()
        }
    }

    func testNativeStateChangesDuringPreparationFinishLeaseWithoutValidation() async throws {
        let cases: [(Win32CloseAttemptOutcome, @MainActor (CloseControlHarness) -> Void)] = [
            (.unavailable, { $0.control.noteTopologyChanged() }),
            (.unavailable, { $0.control.registration?.revoke() }),
            (.unavailable, { $0.control.didCreate($0.originalLifetime, handle: $0.handle + 1) }),
            (.vetoed, { $0.control.isCloseEnabled = false }),
        ]
        for (expected, mutate) in cases {
            let harness = CloseControlHarness()
            defer { harness.authority = nil }
            let lease = CloseControlLease()
            let registration = try harness.install(preparation: { _ in
                mutate(harness)
                return .ready(lease)
            })
            let ticket = try XCTUnwrap(registration.makeTicket(intentID: UUID()))

            XCTAssertEqual(harness.attempt(ticket: ticket), expected)
            XCTAssertEqual(lease.validationCount, 0)
            XCTAssertEqual(lease.finishedOutcomes, [expected])
            XCTAssertFalse(ticket.isCurrent)
            XCTAssertTrue(harness.destroyedHandles.isEmpty)
        }
    }

    func testNativeFailureReleasesLiveReservationAndPermanentlyConsumesApproval() async throws {
        let harness = CloseControlHarness()
        let session = CloseControlSession(lifetime: harness.originalLifetime)
        let lease = CloseControlLease(session: session)
        let registration = try harness.install(lease)
        let ticket = try XCTUnwrap(registration.makeTicket(intentID: UUID()))
        lease.onFinish = { _ in XCTAssertFalse(ticket.isCurrent) }

        XCTAssertEqual(
            harness.attempt(ticket: ticket, destroy: { _ in .failed(1400) }),
            .destructionFailed(.native(1400)))
        XCTAssertEqual(lease.finishedOutcomes, [.destructionFailed(.native(1400))])
        XCTAssertTrue(harness.originalLifetime.isAlive)
        XCTAssertFalse(session.reservationIsActive)
        XCTAssertTrue(session.approvalConsumed)
        XCTAssertEqual(session.finishCount, 1)
        XCTAssertEqual(harness.attempt(ticket: ticket), .unavailable)
        XCTAssertEqual(harness.destroyedHandles.count, 1)

        let freshTicket = try XCTUnwrap(registration.makeTicket(intentID: UUID()))
        XCTAssertEqual(harness.attempt(ticket: freshTicket), .unavailable)
        XCTAssertEqual(lease.validationCount, 2)
        XCTAssertEqual(lease.finishedOutcomes.count, 2)
        XCTAssertEqual(harness.destroyedHandles.count, 1)
    }

    func testNativeSuccessWithoutCompletedDestructionIsNotReportedClosed() async throws {
        let harness = CloseControlHarness()
        let session = CloseControlSession(lifetime: harness.originalLifetime)
        let lease = CloseControlLease(session: session)
        let registration = try harness.install(lease)
        let ticket = try XCTUnwrap(registration.makeTicket(intentID: UUID()))

        XCTAssertEqual(
            harness.attempt(ticket: ticket, destroy: { _ in .succeeded }),
            .destructionFailed(.destructionNotObserved))
        XCTAssertEqual(lease.finishedOutcomes, [.destructionFailed(.destructionNotObserved)])
        XCTAssertTrue(harness.originalLifetime.isAlive)
        XCTAssertFalse(session.reservationIsActive)
        XCTAssertTrue(session.approvalConsumed)
        XCTAssertFalse(ticket.isCurrent)
    }

    func testStartedButUncompletedNativeDestructionKeepsBarrierWithoutClaimingClosed() async throws {
        let cases: [(Win32CloseNativeResult, Win32CloseAttemptOutcome)] = [
            (.succeeded, .destructionFailed(.destructionNotObserved)),
            (.failed(5), .destructionFailed(.native(5))),
        ]
        for (nativeResult, expected) in cases {
            let harness = CloseControlHarness()
            let session = CloseControlSession(lifetime: harness.originalLifetime)
            let lease = CloseControlLease(session: session)
            _ = try harness.install(lease)

            XCTAssertEqual(
                harness.attempt(destroy: { _ in
                    harness.control.beginDestruction(harness.originalLifetime)
                    return nativeResult
                }), expected)
            XCTAssertTrue(harness.originalLifetime.destructionStarted)
            XCTAssertFalse(harness.originalLifetime.destructionCompleted)
            XCTAssertTrue(session.reservationIsActive)
            XCTAssertTrue(session.approvalConsumed)
            XCTAssertEqual(session.finishCount, 1)
            XCTAssertEqual(lease.finishedOutcomes, [expected])
            XCTAssertEqual(harness.attempt(), .unavailable)
            XCTAssertEqual(harness.destroyedHandles.count, 1)
        }
    }

    func testPreflightCompletedOldLifetimeWinsOverVoteAndSameHandleRecreation() async throws {
        for vote in [false, true] {
            let harness = CloseControlHarness()
            let lease = CloseControlLease()
            let registration = try harness.install(lease)
            let ticket = try XCTUnwrap(registration.makeTicket(intentID: UUID()))
            var replacement: Win32CloseLifetime?

            XCTAssertEqual(
                harness.attempt(
                    ticket: ticket,
                    preflight: {
                        replacement = harness.completeOldAndRecreate()
                        return vote
                    }), .closed)
            XCTAssertTrue(harness.originalLifetime.destructionCompleted)
            XCTAssertTrue(replacement?.isAlive == true)
            XCTAssertEqual(replacement?.handle, harness.handle)
            XCTAssertFalse(ticket.isCurrent)
            XCTAssertEqual(harness.authority?.preparationCount, 0)
            XCTAssertEqual(lease.validationCount, 0)
            XCTAssertTrue(lease.finishedOutcomes.isEmpty)
            XCTAssertTrue(harness.destroyedHandles.isEmpty)
        }
    }

    func testPreparationCompletedOldLifetimeWinsOverEveryTypedRejection() async throws {
        for preparationKind in CloseControlPreparationKind.allCases {
            let harness = CloseControlHarness()
            defer { harness.authority = nil }
            let lease = CloseControlLease()
            var replacement: Win32CloseLifetime?
            let registration = try harness.install(preparation: { _ in
                replacement = harness.completeOldAndRecreate()
                return preparationKind.preparation(lease: lease)
            })
            let ticket = try XCTUnwrap(registration.makeTicket(intentID: UUID()))

            XCTAssertEqual(harness.attempt(ticket: ticket), .closed)
            XCTAssertTrue(harness.originalLifetime.destructionCompleted)
            XCTAssertTrue(replacement?.isAlive == true)
            XCTAssertFalse(ticket.isCurrent)
            XCTAssertEqual(lease.validationCount, 0)
            XCTAssertEqual(lease.finishedOutcomes, preparationKind == .ready ? [.closed] : [])
            XCTAssertTrue(harness.destroyedHandles.isEmpty)
        }
    }

    func testValidationCompletedOldLifetimeWinsOverEveryTypedRejection() async throws {
        let decisions: [Win32CloseCommitDecision] = [
            .reserved, .vetoed, .busy(.ownerOperation), .unavailable,
        ]
        for decision in decisions {
            let harness = CloseControlHarness()
            defer { harness.authority = nil }
            var replacement: Win32CloseLifetime?
            let lease = CloseControlLease(validation: {
                replacement = harness.completeOldAndRecreate()
                return decision
            })
            let registration = try harness.install(lease)
            let ticket = try XCTUnwrap(registration.makeTicket(intentID: UUID()))

            XCTAssertEqual(harness.attempt(ticket: ticket), .closed)
            XCTAssertTrue(harness.originalLifetime.destructionCompleted)
            XCTAssertTrue(replacement?.isAlive == true)
            XCTAssertFalse(ticket.isCurrent)
            XCTAssertEqual(lease.validationCount, 1)
            XCTAssertEqual(lease.finishedOutcomes, [.closed])
            XCTAssertTrue(harness.destroyedHandles.isEmpty)
        }
    }

    func testCompletedDestructionWinsOverNativeFailureWithoutTouchingReplacement() async throws {
        let harness = CloseControlHarness()
        let lease = CloseControlLease()
        _ = try harness.install(lease)
        var replacement: Win32CloseLifetime?

        XCTAssertEqual(
            harness.attempt(destroy: { _ in
                replacement = harness.completeOldAndRecreate()
                return .failed(5)
            }), .closed)
        XCTAssertEqual(lease.finishedOutcomes, [.closed])
        XCTAssertTrue(replacement?.isAlive == true)
        XCTAssertTrue(harness.control.lifetime === replacement)
        XCTAssertEqual(harness.destroyedHandles, [harness.handle])
    }

    func testDestructionStartedDuringCommitCannotAuthorizeAnotherNativeDestroy() async throws {
        for stage in CloseControlCallbackStage.allCases {
            let harness = CloseControlHarness()
            defer { harness.authority = nil }
            let session = CloseControlSession(lifetime: harness.originalLifetime)
            let lease = CloseControlLease(session: session)
            let registration = try harness.install(preparation: { _ in
                if stage == .preparation { harness.control.beginDestruction(harness.originalLifetime) }
                return .ready(lease)
            })
            if stage == .validation {
                lease.afterReservation = { harness.control.beginDestruction(harness.originalLifetime) }
            }
            let ticket = try XCTUnwrap(registration.makeTicket(intentID: UUID()))

            XCTAssertEqual(
                harness.attempt(
                    ticket: ticket,
                    preflight: {
                        if stage == .preflight { harness.control.beginDestruction(harness.originalLifetime) }
                        return true
                    }), .unavailable)
            XCTAssertTrue(harness.originalLifetime.destructionStarted)
            XCTAssertFalse(harness.originalLifetime.destructionCompleted)
            XCTAssertTrue(harness.destroyedHandles.isEmpty)
            XCTAssertEqual(lease.validationCount, stage == .validation ? 1 : 0)
            XCTAssertEqual(lease.finishedOutcomes, stage == .preflight ? [] : [.unavailable])
            XCTAssertEqual(session.reservationIsActive, stage == .validation)
            XCTAssertFalse(ticket.isCurrent)
        }
    }

    func testReplacingLifetimeWithSameHandleCannotCloseUncompletedOldLifetime() async throws {
        for stage in CloseControlCallbackStage.allCases {
            let harness = CloseControlHarness()
            defer { harness.authority = nil }
            let lease = CloseControlLease()
            var replacement: Win32CloseLifetime?
            let replace: @MainActor () -> Void = {
                replacement = harness.control.beginLifetime(generation: 2)
                if let replacement { harness.control.didCreate(replacement, handle: harness.handle) }
            }
            let registration = try harness.install(preparation: { _ in
                if stage == .preparation { replace() }
                return .ready(lease)
            })
            if stage == .validation { lease.afterReservation = replace }
            let ticket = try XCTUnwrap(registration.makeTicket(intentID: UUID()))

            XCTAssertEqual(
                harness.attempt(
                    ticket: ticket,
                    preflight: {
                        if stage == .preflight { replace() }
                        return true
                    }), .unavailable)
            XCTAssertFalse(harness.originalLifetime.destructionCompleted)
            XCTAssertTrue(replacement?.isAlive == true)
            XCTAssertEqual(replacement?.handle, harness.handle)
            XCTAssertTrue(harness.destroyedHandles.isEmpty)
            XCTAssertFalse(ticket.isCurrent)
            XCTAssertEqual(lease.finishedOutcomes, stage == .preflight ? [] : [.unavailable])
        }
    }

    func testReentrantAttemptsAreBusyAndCannotConsumeIntentOrReplaceAuthority() async throws {
        let harness = CloseControlHarness()
        defer { harness.authority = nil }
        let lease = CloseControlLease()
        let replacement = CloseControlAuthority { _ in .unavailable }
        var nestedOutcomes: [Win32CloseAttemptOutcome] = []
        var ticket: Win32CloseTicket?
        let nestedAttempt = {
            nestedOutcomes.append(harness.attempt(ticket: ticket))
            XCTAssertNil(harness.control.installAuthority(replacement))
        }
        let registration = try harness.install(preparation: { _ in
            nestedAttempt()
            return .ready(lease)
        })
        ticket = try XCTUnwrap(registration.makeTicket(intentID: UUID()))
        lease.afterReservation = { nestedAttempt() }
        lease.onFinish = { _ in
            XCTAssertFalse(ticket?.isCurrent == true)
            nestedAttempt()
        }

        XCTAssertEqual(
            harness.attempt(
                ticket: ticket,
                preflight: {
                    nestedAttempt()
                    XCTAssertTrue(ticket?.isCurrent == true)
                    return true
                },
                destroy: { _ in
                    nestedAttempt()
                    harness.control.beginDestruction(harness.originalLifetime)
                    harness.control.completeDestruction(harness.originalLifetime)
                    return .succeeded
                }), .closed)
        XCTAssertEqual(nestedOutcomes, Array(repeating: .busy(.closeInProgress), count: 5))
        XCTAssertEqual(harness.preflightCount, 1)
        XCTAssertEqual(harness.authority?.preparationCount, 1)
        XCTAssertEqual(replacement.preparationCount, 0)
        XCTAssertEqual(lease.validationCount, 1)
        XCTAssertEqual(lease.finishedOutcomes, [.closed])
        XCTAssertEqual(harness.destroyedHandles, [harness.handle])
        XCTAssertTrue(harness.control.registration === registration)
        XCTAssertNil(harness.control.activeAttempt)
    }

    func testActualWeakPreflightParticipantStaysAliveThroughDestroyAndLeaseFinish() async throws {
        let harness = CloseControlHarness()
        let lease = CloseControlLease()
        _ = try harness.install(lease)
        var participantOwner: CloseControlParticipant? = CloseControlParticipant()
        weak var participant = participantOwner
        lease.onFinish = { _ in
            XCTAssertNotNil(participant)
            XCTAssertEqual(participant?.voteCount, 1)
        }

        @MainActor func runAttempt() throws -> Win32CloseAttemptOutcome {
            harness.control.attemptClose(
                expectedHandle: harness.handle, ticket: nil,
                participants: [try XCTUnwrap(participantOwner)],
                preflight: {
                    participantOwner = nil
                    // The participant is invoked through the same weak reference
                    // that would disappear if the actual vote chain were not pinned.
                    XCTAssertNotNil(participant)
                    return participant?.vote() ?? false
                },
                destroy: { _ in
                    XCTAssertNotNil(participant)
                    XCTAssertEqual(participant?.voteCount, 1)
                    harness.control.beginDestruction(harness.originalLifetime)
                    harness.control.completeDestruction(harness.originalLifetime)
                    return .succeeded
                })
        }
        let outcome = try runAttempt()

        XCTAssertEqual(outcome, .closed)
        XCTAssertEqual(lease.finishedOutcomes, [.closed])
        XCTAssertNil(participantOwner)
        XCTAssertNil(participant)
    }

    func testAuthorityAndPreparedLeasePinTheirActualSessionThroughFinishOnly() async throws {
        let harness = CloseControlHarness()
        weak var authority: CloseControlAuthority?
        weak var preparedLease: CloseControlLease?
        weak var session: CloseControlSession?
        var owner: CloseControlAuthority? = CloseControlAuthority { _ in
            XCTAssertNotNil(authority)
            let ownedSession = CloseControlSession(lifetime: harness.originalLifetime)
            session = ownedSession
            let lease = CloseControlLease(session: ownedSession)
            preparedLease = lease
            lease.onFinish = { outcome in
                XCTAssertEqual(outcome, .closed)
                XCTAssertNotNil(authority)
                XCTAssertNotNil(preparedLease)
                XCTAssertNotNil(session)
                XCTAssertTrue(preparedLease?.session === session)
                XCTAssertEqual(session?.finishCount, 1)
            }
            return .ready(lease)
        }
        authority = owner
        @MainActor func installOwner() throws {
            _ = try XCTUnwrap(harness.control.installAuthority(try XCTUnwrap(owner)))
        }
        try installOwner()

        let outcome = harness.attempt(
            preflight: {
                owner = nil
                XCTAssertNotNil(authority)
                return true
            },
            destroy: { _ in
                XCTAssertNotNil(authority)
                XCTAssertNotNil(preparedLease)
                XCTAssertNotNil(session)
                XCTAssertTrue(preparedLease?.session === session)
                XCTAssertTrue(session?.reservationIsActive == true)
                harness.control.beginDestruction(harness.originalLifetime)
                harness.control.completeDestruction(harness.originalLifetime)
                return .succeeded
            })

        XCTAssertEqual(outcome, .closed)
        XCTAssertNil(owner)
        XCTAssertNil(authority)
        XCTAssertNil(preparedLease)
        XCTAssertNil(session)
        XCTAssertNil(harness.control.activeAttempt)
    }

    private func assertFinalReservationGuardRejects(
        _ expected: Win32CloseAttemptOutcome,
        mutation: @escaping @MainActor (CloseControlHarness, Win32CloseTicket) -> Void,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let harness = CloseControlHarness()
        defer { harness.authority = nil }
        let session = CloseControlSession(lifetime: harness.originalLifetime)
        let lease = CloseControlLease(session: session)
        let registration = try harness.install(lease)
        let ticket = try XCTUnwrap(registration.makeTicket(intentID: UUID()), file: file, line: line)
        lease.afterReservation = {
            XCTAssertTrue(session.reservationIsActive, file: file, line: line)
            XCTAssertTrue(session.approvalConsumed, file: file, line: line)
            mutation(harness, ticket)
        }
        lease.onFinish = { _ in
            XCTAssertFalse(ticket.isCurrent, file: file, line: line)
            XCTAssertFalse(session.reservationIsActive, file: file, line: line)
            XCTAssertTrue(session.approvalConsumed, file: file, line: line)
        }

        XCTAssertEqual(harness.attempt(ticket: ticket), expected, file: file, line: line)
        XCTAssertEqual(lease.validationCount, 1, file: file, line: line)
        XCTAssertEqual(lease.finishedOutcomes, [expected], file: file, line: line)
        XCTAssertEqual(session.finishCount, 1, file: file, line: line)
        XCTAssertFalse(session.reservationIsActive, file: file, line: line)
        XCTAssertTrue(session.approvalConsumed, file: file, line: line)
        XCTAssertFalse(session.reserve(), file: file, line: line)
        XCTAssertTrue(harness.destroyedHandles.isEmpty, file: file, line: line)
        XCTAssertFalse(harness.originalLifetime.destructionStarted, file: file, line: line)
        XCTAssertNil(harness.control.activeAttempt, file: file, line: line)
    }
}

@MainActor
private final class CloseControlHarness {
    let control: Win32CloseControl
    let handle: UInt
    let originalLifetime: Win32CloseLifetime
    var authority: CloseControlAuthority?
    private(set) var preflightCount = 0
    private(set) var destroyedHandles: [UInt] = []

    init(handle: UInt = 101) {
        let control = Win32CloseControl()
        self.control = control
        self.handle = handle
        originalLifetime = control.beginLifetime(generation: 1)
        control.didCreate(originalLifetime, handle: handle)
    }

    func install(_ lease: CloseControlLease) throws -> Win32CloseRegistration {
        try install(preparation: { _ in .ready(lease) })
    }

    func install(
        preparation: @escaping @MainActor (Win32CloseAttempt) -> Win32CloseCommitPreparation
    ) throws -> Win32CloseRegistration {
        let authority = CloseControlAuthority(preparation)
        self.authority = authority
        return try XCTUnwrap(control.installAuthority(authority))
    }

    func attempt(
        ticket: Win32CloseTicket? = nil,
        participants: [AnyObject] = [],
        preflight: @MainActor () -> Bool = { true },
        destroy: (@MainActor (UInt) -> Win32CloseNativeResult)? = nil
    ) -> Win32CloseAttemptOutcome {
        control.attemptClose(
            expectedHandle: handle, ticket: ticket, participants: participants,
            preflight: {
                preflightCount += 1
                return preflight()
            },
            destroy: { rawHandle in
                destroyedHandles.append(rawHandle)
                if let destroy { return destroy(rawHandle) }
                control.beginDestruction(originalLifetime)
                control.completeDestruction(originalLifetime)
                return .succeeded
            })
    }

    func completeOldAndRecreate() -> Win32CloseLifetime {
        control.beginDestruction(originalLifetime)
        control.completeDestruction(originalLifetime)
        let replacement = control.beginLifetime(generation: 2)
        control.didCreate(replacement, handle: handle)
        return replacement
    }
}

@MainActor
private final class CloseControlAuthority: Win32CloseAuthority {
    private let prepare: @MainActor (Win32CloseAttempt) -> Win32CloseCommitPreparation
    private(set) var preparationCount = 0

    init(_ prepare: @escaping @MainActor (Win32CloseAttempt) -> Win32CloseCommitPreparation) {
        self.prepare = prepare
    }

    func prepareCloseCommit(for attempt: Win32CloseAttempt) -> Win32CloseCommitPreparation {
        preparationCount += 1
        return prepare(attempt)
    }
}

/// This framework-only test double deliberately mutates primitive native state
/// at validation boundaries. Production validation must not call app code.
@MainActor
private final class CloseControlLease: Win32CloseCommitLease {
    let session: CloseControlSession?
    private let validation: @MainActor () -> Win32CloseCommitDecision
    var afterReservation: (@MainActor () -> Void)?
    var onFinish: (@MainActor (Win32CloseAttemptOutcome) -> Void)?
    private(set) var validationCount = 0
    private(set) var finishedOutcomes: [Win32CloseAttemptOutcome] = []

    init(
        session: CloseControlSession? = nil,
        validation: @escaping @MainActor () -> Win32CloseCommitDecision = { .reserved }
    ) {
        self.session = session
        self.validation = validation
    }

    func validateAndReserve() -> Win32CloseCommitDecision {
        validationCount += 1
        let decision = validation()
        if decision == .reserved {
            if let session, !session.reserve() { return .unavailable }
            afterReservation?()
        }
        return decision
    }

    func finish(with outcome: Win32CloseAttemptOutcome) {
        finishedOutcomes.append(outcome)
        session?.finish()
        onFinish?(outcome)
    }
}

/// A reservation models the temporary document write barrier independently of
/// approval consumption. Failure only releases a still-live owner's barrier;
/// actual destruction never makes its old approval reusable.
@MainActor
private final class CloseControlSession {
    let lifetime: Win32CloseLifetime
    private(set) var reservationIsActive = false
    private(set) var approvalConsumed = false
    private(set) var finishCount = 0

    init(lifetime: Win32CloseLifetime) { self.lifetime = lifetime }

    @discardableResult
    func reserve() -> Bool {
        guard !approvalConsumed else { return false }
        approvalConsumed = true
        reservationIsActive = true
        return true
    }

    func finish() {
        finishCount += 1
        if !lifetime.destructionStarted { reservationIsActive = false }
    }
}

@MainActor
private final class CloseControlParticipant {
    private(set) var voteCount = 0

    func vote() -> Bool {
        voteCount += 1
        return true
    }
}

private enum CloseControlCallbackStage: CaseIterable, Equatable {
    case preflight, preparation, validation
}

private enum CloseControlPreparationKind: CaseIterable, Equatable {
    case ready, vetoed, busy, unavailable

    @MainActor
    func preparation(lease: CloseControlLease) -> Win32CloseCommitPreparation {
        switch self {
        case .ready: return .ready(lease)
        case .vetoed: return .vetoed
        case .busy: return .busy(.ownerOperation)
        case .unavailable: return .unavailable
        }
    }
}
