import Foundation
import SwiftWindowsCore
import WinSDK
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform

/// Deterministic cases inject only a per-control scalar poster. The final
/// integration cases own hidden HWNDs and never show a window or consume quit.
@MainActor
final class Win32DeferredCloseTests: XCTestCase {
    func testDispatchEligibilityRestoresAfterNestedAndThrowingScopes() async {
        XCTAssertFalse(Win32DispatchScope.canDeliverWindowWake)
        Win32DispatchScope.withWindowDispatch {
            XCTAssertTrue(Win32DispatchScope.canDeliverWindowWake)
            Win32DispatchScope.withWindowDispatch {
                XCTAssertFalse(Win32DispatchScope.canDeliverWindowWake)
            }
            XCTAssertTrue(Win32DispatchScope.canDeliverWindowWake)
            Win32DispatchScope.withNativeModal {
                XCTAssertFalse(Win32DispatchScope.canDeliverWindowWake)
                Win32DispatchScope.withNativeModal {
                    XCTAssertFalse(Win32DispatchScope.canDeliverWindowWake)
                }
            }
            XCTAssertTrue(Win32DispatchScope.canDeliverWindowWake)
            Win32DispatchScope.withMailboxWork {
                XCTAssertFalse(Win32DispatchScope.canDeliverWindowWake)
            }
            Win32DispatchScope.beginCloseAttempt()
            XCTAssertFalse(Win32DispatchScope.canDeliverWindowWake)
            Win32DispatchScope.endCloseAttempt()
            XCTAssertTrue(Win32DispatchScope.canDeliverWindowWake)
        }

        XCTAssertThrowsError(
            try Win32DispatchScope.withWindowDispatch {
                try Win32DispatchScope.withNativeModal {
                    try Win32DispatchScope.withMailboxWork {
                        Win32DispatchScope.beginCloseAttempt()
                        defer { Win32DispatchScope.endCloseAttempt() }
                        throw DeferredTestError.expected
                    }
                }
            })
        Win32DispatchScope.withWindowDispatch {
            XCTAssertTrue(Win32DispatchScope.canDeliverWindowWake)
        }
        XCTAssertThrowsError(
            try Win32DispatchScope.withWindowDispatch {
                try Win32DispatchScope.withMailboxWork {
                    try Win32DispatchScope.withMailboxDelivery { throw DeferredTestError.expected }
                }
            })
        Win32DispatchScope.withWindowDispatch {
            Win32DispatchScope.withMailboxWork {
                XCTAssertFalse(Win32DispatchScope.permitsTaggedClose(isOwnedRetry: true))
                Win32DispatchScope.withMailboxDelivery {
                    XCTAssertTrue(Win32DispatchScope.permitsTaggedClose(isOwnedRetry: true))
                    XCTAssertFalse(Win32DispatchScope.permitsTaggedClose(isOwnedRetry: false))
                    Win32DispatchScope.withMailboxDelivery {
                        XCTAssertFalse(Win32DispatchScope.permitsTaggedClose(isOwnedRetry: true))
                    }
                    XCTAssertTrue(Win32DispatchScope.permitsTaggedClose(isOwnedRetry: true))
                }
                XCTAssertFalse(Win32DispatchScope.permitsTaggedClose(isOwnedRetry: true))
            }
            XCTAssertTrue(Win32DispatchScope.canDeliverWindowWake)
        }
    }

    func testWeakWakeClientDiesWhileModalScopeDelaysItsRearm() async throws {
        var rearmCount = 0
        var owner: DeferredTestWakeClient? = DeferredTestWakeClient {
            rearmCount += 1
            return nil
        }
        weak var client = owner
        @MainActor func queueOwnedClient() throws {
            Win32DispatchScope.requestWakeWhenIdle(try XCTUnwrap(owner))
        }

        try Win32DispatchScope.withNativeModal {
            try queueOwnedClient()
            owner = nil
            XCTAssertNil(client)
            XCTAssertEqual(rearmCount, 0)
        }
        XCTAssertNil(client)
        XCTAssertEqual(rearmCount, 0)
        Win32DispatchScope.withWindowDispatch {
            XCTAssertTrue(Win32DispatchScope.canDeliverWindowWake)
        }
    }

    func testWakeClientCyclesVisitEachClientOnlyOncePerIdlePass() async throws {
        var firstCount = 0
        var secondCount = 0
        weak var first: DeferredTestWakeClient?
        weak var second: DeferredTestWakeClient?
        let firstOwner = DeferredTestWakeClient {
            firstCount += 1
            if let first { Win32DispatchScope.requestWakeWhenIdle(first) }
            if let second { Win32DispatchScope.requestWakeWhenIdle(second) }
            return nil
        }
        let secondOwner = DeferredTestWakeClient {
            secondCount += 1
            if let first { Win32DispatchScope.requestWakeWhenIdle(first) }
            return nil
        }
        first = firstOwner
        second = secondOwner

        Win32DispatchScope.requestWakeWhenIdle(firstOwner)
        XCTAssertEqual(firstCount, 1)
        XCTAssertEqual(secondCount, 1)
        Win32DispatchScope.requestWakeWhenIdle(firstOwner)
        XCTAssertEqual(firstCount, 2)
        XCTAssertEqual(secondCount, 2)
        withExtendedLifetime((firstOwner, secondOwner)) {}
    }

    func testNewlyRegisteredClientIsPinnedUntilProtectedCleanupReleasesIt() async throws {
        var events: [String] = []
        let finalClient = DeferredTestWakeClient {
            events.append("final.rearm")
            XCTAssertEqual(events.filter { $0 == "child.rearm" }.count, 1)
            XCTAssertTrue(events.contains("child.release"))
            return nil
        }
        var childOwner: DeferredTestWakeClient? = DeferredTestWakeClient(
            rearm: {
                events.append("child.rearm")
                return nil
            },
            onRelease: {
                events.append("child.release")
                Win32DispatchScope.requestWakeWhenIdle(finalClient)
                Win32DispatchScope.withWindowDispatch {
                    XCTAssertFalse(Win32DispatchScope.canDeliverWindowWake)
                }
                XCTAssertFalse(events.contains("final.rearm"))
            })
        weak var child = childOwner
        @MainActor func registerChild() throws {
            Win32DispatchScope.requestWakeWhenIdle(try XCTUnwrap(childOwner))
        }
        let firstClient = DeferredTestWakeClient {
            events.append("first.rearm")
            do { try registerChild() } catch { XCTFail("Missing owned child: \(error)") }
            childOwner = nil
            XCTAssertNotNil(child)
            return nil
        }

        Win32DispatchScope.requestWakeWhenIdle(firstClient)

        XCTAssertEqual(events, ["first.rearm", "child.rearm", "child.release", "final.rearm"])
        XCTAssertNil(child)
        withExtendedLifetime((firstClient, finalClient)) {}
    }

    func testCompletionCaptureDeinitDefersWakeUntilAllCleanupReturns() async {
        var events: [String] = []
        let target = DeferredTestWakeClient {
            events.append("target.rearm")
            return nil
        }
        let client = DeferredTestWakeClient {
            let capture = DeferredTestReleaseProbe {
                events.append("capture.release")
                Win32DispatchScope.requestWakeWhenIdle(target)
                Win32DispatchScope.withWindowDispatch {
                    XCTAssertFalse(Win32DispatchScope.canDeliverWindowWake)
                }
                XCTAssertFalse(events.contains("target.rearm"))
            }
            return { [capture] in
                events.append("completion")
                withExtendedLifetime(capture) {}
            }
        }

        Win32DispatchScope.requestWakeWhenIdle(client)

        XCTAssertEqual(events, ["completion", "capture.release", "target.rearm"])
        withExtendedLifetime((client, target)) {}
    }

    func testMultipleFailureCompletionsFinishAndReleaseBeforeTheirSharedRearm() async {
        var completed: Set<String> = []
        var released: Set<String> = []
        var targetCount = 0
        let target = DeferredTestWakeClient {
            targetCount += 1
            XCTAssertEqual(completed, Set(["first", "second"]))
            XCTAssertEqual(released, Set(["first", "second"]))
            return nil
        }
        @MainActor func makeClient(_ name: String) -> DeferredTestWakeClient {
            DeferredTestWakeClient {
                let capture = DeferredTestReleaseProbe { released.insert(name) }
                return { [capture] in
                    completed.insert(name)
                    Win32DispatchScope.requestWakeWhenIdle(target)
                    Win32DispatchScope.withWindowDispatch {
                        XCTAssertFalse(Win32DispatchScope.canDeliverWindowWake)
                    }
                    XCTAssertEqual(targetCount, 0)
                    withExtendedLifetime(capture) {}
                }
            }
        }
        let first = makeClient("first")
        let second = makeClient("second")

        Win32DispatchScope.withNativeModal {
            Win32DispatchScope.requestWakeWhenIdle(first)
            Win32DispatchScope.requestWakeWhenIdle(second)
            XCTAssertEqual(targetCount, 0)
        }

        XCTAssertEqual(targetCount, 1)
        XCTAssertEqual(completed, Set(["first", "second"]))
        XCTAssertEqual(released, Set(["first", "second"]))
        withExtendedLifetime((first, second, target)) {}
    }

    func testCheckedWakeSequenceNeverWrapsOrRestartsAfterExhaustion() async {
        let ordinary = Win32CloseWakeSequence()
        XCTAssertEqual(ordinary.takeNext(), 1)
        XCTAssertEqual(ordinary.takeNext(), 2)
        let terminal = Win32CloseWakeSequence(startingAfter: UInt.max - 1)
        XCTAssertEqual(terminal.takeNext(), UInt.max)
        XCTAssertNil(terminal.takeNext())
        XCTAssertNil(terminal.takeNext())
        let exhausted = Win32CloseWakeSequence(startingAfter: UInt.max)
        XCTAssertNil(exhausted.takeNext())
        XCTAssertNil(exhausted.takeNext())
        let unavailable = Win32CloseWakeSequence(startingAfter: nil)
        XCTAssertNil(unavailable.takeNext())
        XCTAssertNil(unavailable.takeNext())
    }

    func testInitialPostCarriesOnlyOwnedHandleAndNonceAndPromptDeliversOnce() async throws {
        let harness = try DeferredTestHarness()
        defer { harness.registration.revoke() }
        let ticket = try harness.ticket()
        var deliveries: [Foundation.UUID] = []

        XCTAssertEqual(harness.enqueue(ticket) { deliveries.append($0.id) }, .queued)
        XCTAssertEqual(harness.posts.messages, [.init(handle: harness.handle, nonce: 1)])
        XCTAssertTrue(deliveries.isEmpty)
        harness.deliver(999)
        XCTAssertTrue(deliveries.isEmpty)
        XCTAssertEqual(harness.posts.messages.count, 1)
        harness.deliver(1)
        XCTAssertEqual(deliveries, [ticket.id])
        XCTAssertTrue(ticket.isCurrent, "Presenting a prompt does not consume its close intent.")
        harness.deliver(1)
        XCTAssertEqual(deliveries, [ticket.id])
        XCTAssertEqual(harness.posts.messages.count, 1)
    }

    func testPendingCoalescingKeepsOriginalPayloadAndRejectsConflictingPhaseOrTicket() async throws {
        let harness = try DeferredTestHarness()
        defer { harness.registration.revoke() }
        let ticket = try harness.ticket()
        let sameIntentOtherTicket = try harness.ticket(intentID: ticket.intentID)
        var deliveries: [String] = []

        XCTAssertEqual(harness.enqueue(ticket) { _ in deliveries.append("original") }, .queued)
        XCTAssertEqual(harness.enqueue(ticket) { _ in deliveries.append("replacement") }, .coalesced)
        XCTAssertEqual(harness.enqueue(ticket, phase: .retry) { _ in deliveries.append("wrong-phase") }, .busy)
        XCTAssertEqual(harness.enqueue(sameIntentOtherTicket) { _ in deliveries.append("other-ticket") }, .busy)
        XCTAssertEqual(harness.posts.messages.count, 1)
        harness.deliver(try harness.lastNonce())
        XCTAssertEqual(deliveries, ["original"])
        XCTAssertTrue(ticket.isCurrent)
        XCTAssertTrue(sameIntentOtherTicket.isCurrent)
    }

    func testExecutingPromptQueuesOneRetryWithoutInlinePostOrReplacingEitherAction() async throws {
        let harness = try DeferredTestHarness()
        defer { harness.registration.revoke() }
        let ticket = try harness.ticket()
        let otherTicket = try harness.ticket()
        var events: [String] = []
        var closeOutcome: Win32CloseAttemptOutcome?
        XCTAssertEqual(
            harness.enqueue(ticket) { delivered in
                XCTAssertTrue(delivered === ticket)
                events.append("prompt.begin")
                XCTAssertEqual(harness.enqueue(ticket) { _ in events.append("duplicate-prompt") }, .coalesced)
                XCTAssertEqual(harness.enqueue(otherTicket) { _ in events.append("other-intent") }, .busy)
                XCTAssertEqual(
                    harness.enqueue(ticket, phase: .retry) { retry in
                        events.append("retry")
                        XCTAssertTrue(retry === ticket)
                        closeOutcome = harness.control.attemptClose(
                            expectedHandle: harness.handle, ticket: retry, participants: [],
                            preflight: { true },
                            destroy: { _ in
                                harness.control.beginDestruction(harness.lifetime)
                                harness.control.completeDestruction(harness.lifetime)
                                return .succeeded
                            })
                    }, .queued)
                XCTAssertEqual(
                    harness.enqueue(ticket, phase: .retry) { _ in events.append("duplicate-retry") }, .coalesced)
                XCTAssertEqual(harness.posts.messages.count, 1)
                XCTAssertTrue(ticket.isCurrent)
                events.append("prompt.end")
            }, .queued)

        harness.deliver(try harness.lastNonce())
        XCTAssertEqual(events, ["prompt.begin", "prompt.end"])
        XCTAssertEqual(harness.posts.messages.count, 2)
        XCTAssertNotEqual(harness.posts.messages[0].nonce, harness.posts.messages[1].nonce)
        harness.deliver(harness.posts.messages[0].nonce)
        XCTAssertEqual(events, ["prompt.begin", "prompt.end"])
        harness.deliver(harness.posts.messages[1].nonce)
        XCTAssertEqual(events, ["prompt.begin", "prompt.end", "retry"])
        XCTAssertEqual(closeOutcome, .closed)
        XCTAssertFalse(ticket.isCurrent)
    }

    func testPromptActionCannotDirectlySpendItsOwnTicketOnATaggedClose() async throws {
        let harness = try DeferredTestHarness()
        defer { harness.registration.revoke() }
        let ticket = try harness.ticket()
        var outcome: Win32CloseAttemptOutcome?
        var preflightCount = 0
        XCTAssertEqual(
            harness.enqueue(ticket) { delivered in
                outcome = harness.control.attemptClose(
                    expectedHandle: harness.handle, ticket: delivered, participants: [],
                    preflight: {
                        preflightCount += 1
                        return false
                    },
                    destroy: { _ in
                        XCTFail("A prompt action cannot synchronously destroy its owner.")
                        return .failed(1)
                    })
            }, .queued)

        harness.deliver(try harness.lastNonce())

        XCTAssertEqual(outcome, .busy(.nativeDispatch))
        XCTAssertEqual(preflightCount, 0)
        XCTAssertTrue(ticket.isCurrent)
        XCTAssertTrue(harness.lifetime.isAlive)
    }

    func testRetryDeliveryAuthorizesOnlyItsOwnControlsExactTicket() async throws {
        let first = try DeferredTestHarness(handle: 101)
        let second = try DeferredTestHarness(handle: 202)
        defer {
            first.registration.revoke()
            second.registration.revoke()
        }
        let firstTicket = try first.ticket()
        let wrongFirstTicket = try first.ticket()
        let secondTicket = try second.ticket()
        var results: [Win32CloseAttemptOutcome] = []
        var preflightCount = 0
        @MainActor func attempt(_ harness: DeferredTestHarness, ticket: Win32CloseTicket) -> Win32CloseAttemptOutcome {
            harness.control.attemptClose(
                expectedHandle: harness.handle, ticket: ticket, participants: [],
                preflight: {
                    preflightCount += 1
                    return false
                },
                destroy: { _ in
                    XCTFail("A rejected retry cannot destroy either test lifetime.")
                    return .failed(1)
                })
        }
        XCTAssertEqual(
            first.enqueue(firstTicket, phase: .retry) { _ in
                results.append(attempt(second, ticket: secondTicket))
                results.append(attempt(first, ticket: wrongFirstTicket))
                results.append(attempt(first, ticket: firstTicket))
            }, .queued)

        first.deliver(try first.lastNonce())

        XCTAssertEqual(results, [.busy(.nativeDispatch), .busy(.nativeDispatch), .vetoed])
        XCTAssertEqual(preflightCount, 1)
        XCTAssertFalse(firstTicket.isCurrent)
        XCTAssertTrue(wrongFirstTicket.isCurrent)
        XCTAssertTrue(secondTicket.isCurrent)
        XCTAssertTrue(first.lifetime.isAlive)
        XCTAssertTrue(second.lifetime.isAlive)
    }

    func testNestedDispatchAndModalConsumptionRearmOnlyAtTheOutermostExit() async throws {
        for modal in [false, true] {
            let harness = try DeferredTestHarness()
            defer { harness.registration.revoke() }
            let ticket = try harness.ticket()
            var deliveries = 0
            XCTAssertEqual(harness.enqueue(ticket) { _ in deliveries += 1 }, .queued)
            let nonce = try harness.lastNonce()
            let consume = {
                harness.deliver(nonce)
                harness.deliver(nonce)
                harness.deliver(nonce + 100)
                XCTAssertEqual(deliveries, 0)
                XCTAssertEqual(harness.posts.messages.count, 1)
            }

            if modal {
                Win32DispatchScope.withNativeModal {
                    Win32DispatchScope.withNativeModal { consume() }
                    XCTAssertEqual(harness.posts.messages.count, 1)
                }
            } else {
                Win32DispatchScope.withWindowDispatch { consume() }
            }

            XCTAssertEqual(harness.posts.messages.count, 2)
            XCTAssertEqual(harness.posts.messages[1].nonce, nonce, "Rearming preserves the same pending record.")
            XCTAssertEqual(deliveries, 0)
            harness.deliver(nonce)
            XCTAssertEqual(deliveries, 1)
            harness.deliver(nonce)
            XCTAssertEqual(deliveries, 1)
        }
    }

    func testAnOrdinaryClosePreflightCannotPumpPendingMailboxWork() async throws {
        let harness = try DeferredTestHarness()
        defer { harness.registration.revoke() }
        let ticket = try harness.ticket()
        var deliveries = 0
        XCTAssertEqual(harness.enqueue(ticket) { _ in deliveries += 1 }, .queued)
        let nonce = try harness.lastNonce()
        let outcome = harness.control.attemptClose(
            expectedHandle: harness.handle, ticket: nil, participants: [],
            preflight: {
                harness.deliver(nonce)
                XCTAssertEqual(deliveries, 0)
                XCTAssertEqual(harness.posts.messages.count, 1)
                return false
            },
            destroy: { _ in
                XCTFail("A rejected ordinary close cannot destroy the test lifetime.")
                return .failed(1)
            })

        XCTAssertEqual(outcome, .vetoed)
        XCTAssertTrue(ticket.isCurrent)
        XCTAssertEqual(harness.posts.messages.count, 2)
        XCTAssertEqual(deliveries, 0)
        harness.deliver(nonce)
        XCTAssertEqual(deliveries, 1)
    }

    func testOneMailboxActionCannotPumpAnotherWindowsPendingAction() async throws {
        let first = try DeferredTestHarness(handle: 101)
        let second = try DeferredTestHarness(handle: 202)
        defer {
            first.registration.revoke()
            second.registration.revoke()
        }
        let secondTicket = try second.ticket()
        var events: [String] = []
        XCTAssertEqual(second.enqueue(secondTicket) { _ in events.append("second") }, .queued)
        let secondNonce = try second.lastNonce()
        let firstTicket = try first.ticket()
        XCTAssertEqual(
            first.enqueue(firstTicket) { _ in
                events.append("first.begin")
                second.deliver(secondNonce)
                XCTAssertEqual(events, ["first.begin"])
                events.append("first.end")
            }, .queued)

        first.deliver(try first.lastNonce())
        XCTAssertEqual(events, ["first.begin", "first.end"])
        XCTAssertEqual(second.posts.messages.count, 2)
        second.deliver(secondNonce)
        XCTAssertEqual(events, ["first.begin", "first.end", "second"])
    }

    func testCancellationEpochRevocationAndDestructionRetirePendingCapturesBeforeOldWake() async throws {
        for retirement in DeferredTestRetirement.allCases {
            let harness = try DeferredTestHarness()
            defer { harness.registration.revoke() }
            let ticket = try harness.ticket()
            weak var capture: DeferredTestReleaseProbe?
            var releases = 0
            var deliveries = 0
            @MainActor func installCapturedAction() -> Win32DeferredCloseSubmission {
                let owned = DeferredTestReleaseProbe {
                    releases += 1
                    XCTAssertFalse(ticket.isCurrent)
                }
                capture = owned
                return harness.enqueue(ticket) { [owned] _ in
                    deliveries += 1
                    withExtendedLifetime(owned) {}
                }
            }
            XCTAssertEqual(installCapturedAction(), .queued)
            let nonce = try harness.lastNonce()
            XCTAssertNotNil(capture)

            switch retirement {
            case .cancel: ticket.cancel()
            case .epoch: harness.registration.invalidateTickets()
            case .revoke: harness.registration.revoke()
            case .destroy: harness.control.beginDestruction(harness.lifetime)
            }

            XCTAssertNil(capture)
            XCTAssertEqual(releases, 1)
            harness.deliver(nonce)
            XCTAssertEqual(deliveries, 0)
            XCTAssertEqual(releases, 1)
            XCTAssertEqual(harness.posts.messages.count, 1)
        }
    }

    func testCancelledCaptureCanEnqueueReplacementOnlyAfterOldRecordIsDetached() async throws {
        let harness = try DeferredTestHarness()
        defer { harness.registration.revoke() }
        let oldTicket = try harness.ticket()
        let replacement = try harness.ticket()
        var replacementSubmission: Win32DeferredCloseSubmission?
        var deliveries: [Foundation.UUID] = []
        @MainActor func installCapturedAction() -> Win32DeferredCloseSubmission {
            let capture = DeferredTestReleaseProbe {
                XCTAssertFalse(oldTicket.isCurrent)
                replacementSubmission = harness.enqueue(replacement) { deliveries.append($0.id) }
            }
            return harness.enqueue(oldTicket) { [capture] _ in withExtendedLifetime(capture) {} }
        }
        XCTAssertEqual(installCapturedAction(), .queued)
        let staleNonce = try harness.lastNonce()

        oldTicket.cancel()

        XCTAssertEqual(replacementSubmission, .queued)
        XCTAssertEqual(harness.posts.messages.count, 2)
        let currentNonce = try harness.lastNonce()
        XCTAssertNotEqual(staleNonce, currentNonce)
        harness.deliver(staleNonce)
        XCTAssertTrue(deliveries.isEmpty)
        harness.deliver(currentNonce)
        XCTAssertEqual(deliveries, [replacement.id])
    }

    func testWorkPinRetainsRevokedCapturesUntilCallerCompletesItsTeardown() async throws {
        let harness = try DeferredTestHarness()
        let ticket = try harness.ticket()
        var capabilitiesRevoked = false
        var releases = 0
        weak var capture: DeferredTestReleaseProbe?
        @MainActor func installCapturedAction() -> Win32DeferredCloseSubmission {
            let owned = DeferredTestReleaseProbe {
                releases += 1
                XCTAssertFalse(ticket.isCurrent)
                XCTAssertTrue(capabilitiesRevoked)
            }
            capture = owned
            return harness.enqueue(ticket) { [owned] _ in withExtendedLifetime(owned) {} }
        }
        XCTAssertEqual(installCapturedAction(), .queued)
        var pin: Win32CloseWorkPin? = try XCTUnwrap(harness.registration.pinDeferredWork())
        harness.registration.revoke()
        XCTAssertFalse(ticket.isCurrent)
        XCTAssertNotNil(capture)
        XCTAssertEqual(releases, 0)
        capabilitiesRevoked = true

        pin = nil

        XCTAssertNil(pin)
        XCTAssertNil(capture)
        XCTAssertEqual(releases, 1)
        harness.deliver(try harness.lastNonce())
        XCTAssertEqual(releases, 1)
    }

    func testWorkPinDoesNotBlockDeliveryButKeepsDeliveredPayloadUntilRelease() async throws {
        let harness = try DeferredTestHarness()
        defer { harness.registration.revoke() }
        let ticket = try harness.ticket()
        var deliveries = 0
        var releases = 0
        weak var capture: DeferredTestReleaseProbe?
        @MainActor func installCapturedAction() -> Win32DeferredCloseSubmission {
            let owned = DeferredTestReleaseProbe { releases += 1 }
            capture = owned
            return harness.enqueue(ticket) { [owned] _ in
                deliveries += 1
                withExtendedLifetime(owned) {}
            }
        }
        XCTAssertEqual(installCapturedAction(), .queued)
        var pin: Win32CloseWorkPin? = harness.control.pinDeferredWork()

        harness.deliver(try harness.lastNonce())

        XCTAssertEqual(deliveries, 1)
        XCTAssertNotNil(capture)
        XCTAssertEqual(releases, 0)
        pin = nil
        XCTAssertNil(pin)
        XCTAssertNil(capture)
        XCTAssertEqual(releases, 1)
    }

    func testInitialPostFailureReturnsOnceWithoutObserverOrAutomaticRetry() async throws {
        let harness = try DeferredTestHarness(postResults: [.failed(5), .succeeded])
        defer { harness.registration.revoke() }
        let ticket = try harness.ticket()
        var deliveries = 0
        var failures: [UInt32] = []

        XCTAssertEqual(
            harness.enqueue(ticket, onPostFailure: { _, error in failures.append(error) }) { _ in deliveries += 1 },
            .postFailed(5))
        XCTAssertEqual(harness.posts.messages.count, 1)
        XCTAssertTrue(failures.isEmpty)
        XCTAssertTrue(ticket.isCurrent)
        harness.deliver(try harness.lastNonce())
        XCTAssertEqual(deliveries, 0)
        XCTAssertEqual(harness.posts.messages.count, 1)
        XCTAssertEqual(harness.enqueue(ticket) { _ in deliveries += 1 }, .queued)
        XCTAssertEqual(harness.posts.messages.count, 2)
        XCTAssertNotEqual(harness.posts.messages[0].nonce, harness.posts.messages[1].nonce)
        harness.deliver(harness.posts.messages[1].nonce)
        XCTAssertEqual(deliveries, 1)
        XCTAssertTrue(failures.isEmpty)
    }

    func testExhaustedSequenceRejectsNewWorkWithoutPostingOrRetainingItsCaptures() async throws {
        let harness = try DeferredTestHarness(sequence: Win32CloseWakeSequence(startingAfter: UInt.max))
        let ticket = try harness.ticket()
        weak var capture: DeferredTestReleaseProbe?
        var releases = 0
        @MainActor func enqueueCapturedAction() -> Win32DeferredCloseSubmission {
            let owned = DeferredTestReleaseProbe { releases += 1 }
            capture = owned
            return harness.enqueue(ticket) { [owned] _ in withExtendedLifetime(owned) {} }
        }

        XCTAssertEqual(enqueueCapturedAction(), .unavailable)
        XCTAssertNil(capture)
        XCTAssertEqual(releases, 1)
        XCTAssertTrue(harness.posts.messages.isEmpty)
        XCTAssertTrue(ticket.isCurrent)
        XCTAssertEqual(harness.enqueue(ticket) { _ in XCTFail("Exhaustion cannot reset the sequence.") }, .unavailable)
        XCTAssertTrue(harness.posts.messages.isEmpty)
    }

    func testDeferredQueueDoesNotRetainItsWeakAuthorityUntilDelivery() async throws {
        let harness = try DeferredTestHarness()
        let ticket = try harness.ticket()
        weak var authority = harness.authority
        weak var capture: DeferredTestReleaseProbe?
        var deliveries = 0
        var releases = 0
        @MainActor func installCapturedAction() -> Win32DeferredCloseSubmission {
            let owned = DeferredTestReleaseProbe { releases += 1 }
            capture = owned
            return harness.enqueue(ticket) { [owned] _ in
                deliveries += 1
                withExtendedLifetime(owned) {}
            }
        }
        XCTAssertEqual(installCapturedAction(), .queued)
        harness.authority = nil

        XCTAssertNil(authority)
        XCTAssertFalse(ticket.isCurrent)
        harness.deliver(try harness.lastNonce())
        XCTAssertEqual(deliveries, 0)
        XCTAssertNil(capture)
        XCTAssertEqual(releases, 1)
        XCTAssertEqual(harness.posts.messages.count, 1)
    }

    func testDeliveryPinsAuthorityThroughActionCaptureCleanupAndDefersPumpedWake() async throws {
        let harness = try DeferredTestHarness()
        let other = try DeferredTestHarness(handle: 202)
        defer {
            harness.registration.revoke()
            other.registration.revoke()
        }
        let ticket = try harness.ticket()
        let otherTicket = try other.ticket()
        weak var authority = harness.authority
        weak var capture: DeferredTestReleaseProbe?
        var events: [String] = []
        XCTAssertEqual(other.enqueue(otherTicket) { _ in events.append("other.action") }, .queued)
        let otherNonce = try other.lastNonce()
        @MainActor func installCapturedAction() -> Win32DeferredCloseSubmission {
            let owned = DeferredTestReleaseProbe {
                events.append("capture.release")
                XCTAssertNotNil(authority)
                XCTAssertFalse(Win32DispatchScope.canDeliverWindowWake)
                other.deliver(otherNonce)
                XCTAssertFalse(events.contains("other.action"))
            }
            capture = owned
            return harness.enqueue(ticket) { [owned] _ in
                events.append("action")
                harness.authority = nil
                XCTAssertNotNil(authority)
                withExtendedLifetime(owned) {}
            }
        }
        XCTAssertEqual(installCapturedAction(), .queued)

        harness.deliver(try harness.lastNonce())

        XCTAssertEqual(events, ["action", "capture.release"])
        XCTAssertNil(authority)
        XCTAssertNil(capture)
        XCTAssertEqual(other.posts.messages.count, 2)
        other.deliver(otherNonce)
        XCTAssertEqual(events, ["action", "capture.release", "other.action"])
    }

    func testDelayedPostFailureNotifiesUnderCleanupAndAllowsExplicitReplacement() async throws {
        let harness = try DeferredTestHarness(postResults: [.succeeded, .failed(5)])
        defer { harness.registration.revoke() }
        let ticket = try harness.ticket()
        var failures: [UInt32] = []
        var deliveries = 0
        var nestedClose: Win32CloseAttemptOutcome?
        var replacement: Win32DeferredCloseSubmission?
        XCTAssertEqual(
            harness.enqueue(
                ticket,
                onPostFailure: { failedTicket, error in
                    XCTAssertTrue(failedTicket === ticket)
                    failures.append(error)
                    XCTAssertTrue(ticket.isCurrent)
                    XCTAssertEqual(harness.posts.messages.count, 2)
                    Win32DispatchScope.withWindowDispatch {
                        nestedClose = harness.control.attemptClose(
                            expectedHandle: harness.handle, ticket: ticket, participants: [],
                            preflight: {
                                XCTFail("A failure cleanup pump cannot begin a tagged close.")
                                return false
                            },
                            destroy: { _ in
                                XCTFail("A failure cleanup pump cannot destroy a window.")
                                return .failed(1)
                            })
                    }
                    replacement = harness.enqueue(ticket) { _ in deliveries += 1 }
                    if let nonce = harness.posts.messages.last?.nonce { harness.deliver(nonce) }
                    XCTAssertEqual(deliveries, 0)
                }
            ) { _ in XCTFail("The failed record must never deliver its action.") }, .queued)
        let failedNonce = try harness.lastNonce()

        Win32DispatchScope.withNativeModal { harness.deliver(failedNonce) }

        XCTAssertEqual(failures, [5])
        XCTAssertEqual(nestedClose, .busy(.nativeDispatch))
        XCTAssertEqual(replacement, .queued)
        XCTAssertEqual(harness.posts.messages.count, 4)
        XCTAssertEqual(harness.posts.messages[0].nonce, harness.posts.messages[1].nonce)
        XCTAssertEqual(harness.posts.messages[2].nonce, harness.posts.messages[3].nonce)
        XCTAssertNotEqual(harness.posts.messages[1].nonce, harness.posts.messages[2].nonce)
        harness.deliver(failedNonce)
        XCTAssertEqual(deliveries, 0)
        harness.deliver(try harness.lastNonce())
        XCTAssertEqual(deliveries, 1)
        XCTAssertEqual(failures, [5])
        XCTAssertTrue(ticket.isCurrent)
    }

    func testSupersededFailureDoesNotNotifyAfterOtherFailureRequeuesItsSameTicket() async throws {
        let first = try DeferredTestHarness(handle: 101, postResults: [.succeeded, .failed(5)])
        let second = try DeferredTestHarness(handle: 202, postResults: [.succeeded, .failed(6)])
        defer {
            first.registration.revoke()
            second.registration.revoke()
        }
        let firstTicket = try first.ticket()
        let secondTicket = try second.ticket()
        var failures: [String] = []
        var replacements: [String] = []
        var deliveries: [String] = []
        @MainActor func receiveFailure(
            _ name: String, otherName: String, other: DeferredTestHarness, otherTicket: Win32CloseTicket
        ) {
            failures.append(name)
            guard failures.count == 1 else {
                XCTFail("The superseded record delivered its obsolete post failure.")
                return
            }
            replacements.append(otherName)
            XCTAssertEqual(other.enqueue(otherTicket) { _ in deliveries.append(otherName) }, .queued)
        }
        XCTAssertEqual(
            first.enqueue(
                firstTicket,
                onPostFailure: { ticket, code in
                    XCTAssertTrue(ticket === firstTicket)
                    XCTAssertEqual(code, 5)
                    receiveFailure("first", otherName: "second", other: second, otherTicket: secondTicket)
                }
            ) { _ in XCTFail("The first failed record cannot execute.") }, .queued)
        XCTAssertEqual(
            second.enqueue(
                secondTicket,
                onPostFailure: { ticket, code in
                    XCTAssertTrue(ticket === secondTicket)
                    XCTAssertEqual(code, 6)
                    receiveFailure("second", otherName: "first", other: first, otherTicket: firstTicket)
                }
            ) { _ in XCTFail("The second failed record cannot execute.") }, .queued)
        let firstOldNonce = try first.lastNonce()
        let secondOldNonce = try second.lastNonce()

        Win32DispatchScope.withNativeModal {
            first.deliver(firstOldNonce)
            second.deliver(secondOldNonce)
        }

        XCTAssertEqual(failures.count, 1, "Dictionary iteration order must not affect supersession safety.")
        XCTAssertEqual(replacements.count, 1)
        XCTAssertTrue(deliveries.isEmpty)
        first.deliver(firstOldNonce)
        second.deliver(secondOldNonce)
        XCTAssertTrue(deliveries.isEmpty)
        let replacementName = try XCTUnwrap(replacements.first)
        let replacementHarness = replacementName == "first" ? first : second
        XCTAssertEqual(replacementHarness.posts.messages.count, 3)
        replacementHarness.deliver(try replacementHarness.lastNonce())
        XCTAssertEqual(deliveries, [replacementName])
        XCTAssertEqual(failures.count, 1)
        XCTAssertTrue(firstTicket.isCurrent)
        XCTAssertTrue(secondTicket.isCurrent)
    }

    func testCancellationDuringFailedRearmSuppressesObsoleteFailureCallback() async throws {
        let harness = try DeferredTestHarness(postResults: [.succeeded, .failed(5)])
        defer {
            harness.posts.onPost = nil
            harness.registration.revoke()
        }
        let ticket = try harness.ticket()
        var failures = 0
        var deliveries = 0
        harness.posts.onPost = { _, ordinal in
            if ordinal == 2 { ticket.cancel() }
        }
        XCTAssertEqual(
            harness.enqueue(ticket, onPostFailure: { _, _ in failures += 1 }) { _ in deliveries += 1 }, .queued)
        let nonce = try harness.lastNonce()

        Win32DispatchScope.withNativeModal { harness.deliver(nonce) }

        XCTAssertFalse(ticket.isCurrent)
        XCTAssertEqual(failures, 0)
        XCTAssertEqual(deliveries, 0)
        XCTAssertEqual(harness.posts.messages.count, 2)
        harness.deliver(nonce)
        XCTAssertEqual(failures, 0)
        XCTAssertEqual(deliveries, 0)
    }

    func testTaggedAttemptsDeferInsideModalNestedDispatchAndCleanupWithoutConsumingTicket() async throws {
        let harness = try DeferredTestHarness()
        let ticket = try harness.ticket()
        var preflightCount = 0
        @MainActor func attempt(_ ticket: Win32CloseTicket?) -> Win32CloseAttemptOutcome {
            harness.control.attemptClose(
                expectedHandle: harness.handle, ticket: ticket, participants: [],
                preflight: {
                    preflightCount += 1
                    return false
                },
                destroy: { _ in
                    XCTFail("Rejected attempts cannot destroy the fake lifetime.")
                    return .failed(1)
                })
        }

        Win32DispatchScope.withNativeModal {
            XCTAssertEqual(attempt(ticket), .busy(.nativeDispatch))
            XCTAssertEqual(attempt(nil), .vetoed, "Ordinary close retains its public preflight semantics.")
        }
        Win32DispatchScope.withWindowDispatch {
            Win32DispatchScope.withWindowDispatch {
                XCTAssertEqual(attempt(ticket), .busy(.nativeDispatch))
            }
        }
        Win32DispatchScope.withMailboxWork {
            XCTAssertEqual(attempt(ticket), .busy(.nativeDispatch))
            Win32DispatchScope.withWindowDispatch {
                XCTAssertEqual(attempt(ticket), .busy(.nativeDispatch))
            }
        }
        XCTAssertEqual(preflightCount, 1)
        XCTAssertTrue(ticket.isCurrent)
        XCTAssertEqual(attempt(ticket), .vetoed)
        XCTAssertFalse(ticket.isCurrent)
        XCTAssertEqual(preflightCount, 2)
    }

    func testOldNonceCannotAuthorizeWorkAfterSameControlReusesItsHandle() async throws {
        let harness = try DeferredTestHarness()
        let oldTicket = try harness.ticket()
        var oldDeliveries = 0
        var newDeliveries = 0
        XCTAssertEqual(harness.enqueue(oldTicket) { _ in oldDeliveries += 1 }, .queued)
        let oldNonce = try harness.lastNonce()
        harness.control.beginDestruction(harness.lifetime)
        harness.control.completeDestruction(harness.lifetime)
        let replacementLifetime = harness.control.beginLifetime(generation: 2)
        harness.control.didCreate(replacementLifetime, handle: harness.handle)
        let replacementAuthority = DeferredTestAuthority()
        let replacementRegistration = try XCTUnwrap(harness.control.installAuthority(replacementAuthority))
        defer { replacementRegistration.revoke() }
        let replacementTicket = try XCTUnwrap(replacementRegistration.makeTicket(intentID: oldTicket.intentID))
        XCTAssertEqual(
            replacementRegistration.enqueue(
                ticket: replacementTicket, phase: .prompt,
                onPostFailure: { _, _ in XCTFail("Unexpected replacement post failure.") },
                action: { _ in newDeliveries += 1 }), .queued)
        let replacementNonce = try harness.lastNonce()

        XCTAssertNotEqual(oldNonce, replacementNonce)
        XCTAssertFalse(oldTicket.isCurrent)
        harness.deliver(oldNonce)
        XCTAssertEqual(oldDeliveries, 0)
        XCTAssertEqual(newDeliveries, 0)
        XCTAssertTrue(replacementTicket.isCurrent)
        harness.deliver(replacementNonce)
        XCTAssertEqual(newDeliveries, 1)
        XCTAssertTrue(replacementLifetime.isAlive)
        withExtendedLifetime(replacementAuthority) {}
    }

    func testWorkPinDoesNotKeepTheControlOrRegistrationAuthorityAlive() async throws {
        let posts = DeferredTestPosts(results: [])
        var owner: Win32CloseControl? = Win32CloseControl(
            postWake: { [posts] handle, nonce in posts.post(handle: handle, nonce: nonce) },
            wakeSequence: Win32CloseWakeSequence())
        weak var control = owner
        var authorityOwner: DeferredTestAuthority? = DeferredTestAuthority()
        weak var authority = authorityOwner
        var registration: Win32CloseRegistration?
        var ticket: Win32CloseTicket?
        weak var capture: DeferredTestReleaseProbe?
        var releases = 0
        @MainActor func enqueueAndPin() throws -> Win32CloseWorkPin {
            let live = try XCTUnwrap(owner)
            let lifetime = live.beginLifetime(generation: 1)
            live.didCreate(lifetime, handle: 101)
            let installed = try XCTUnwrap(live.installAuthority(try XCTUnwrap(authorityOwner)))
            registration = installed
            let current = try XCTUnwrap(installed.makeTicket(intentID: UUID()))
            ticket = current
            let owned = DeferredTestReleaseProbe { releases += 1 }
            capture = owned
            XCTAssertEqual(
                installed.enqueue(
                    ticket: current, phase: .prompt,
                    onPostFailure: { _, _ in XCTFail("No failed post is expected.") },
                    action: { [owned] _ in withExtendedLifetime(owned) {} }), .queued)
            return live.pinDeferredWork()
        }
        var pin: Win32CloseWorkPin? = try enqueueAndPin()

        owner = nil
        authorityOwner = nil

        XCTAssertNil(control)
        XCTAssertNil(authority)
        XCTAssertFalse(ticket?.isCurrent == true)
        XCTAssertNil(registration?.pinDeferredWork())
        XCTAssertNotNil(capture)
        pin = nil
        XCTAssertNil(pin)
        XCTAssertNil(capture)
        XCTAssertEqual(releases, 1)
    }

    func testUnavailablePreflightMarkerOutranksVetoAndBusyInEitherOrder() async throws {
        let busyOrders: [Bool?] = [nil, true, false]
        for busyFirst in busyOrders {
            let harness = try DeferredTestHarness()
            let ticket = try harness.ticket()
            var captured: Win32CloseAttempt?
            let outcome = harness.control.attemptClose(
                expectedHandle: harness.handle, ticket: ticket, participants: [],
                preflight: {
                    captured = harness.control.activeAttempt
                    if busyFirst == true { captured?.deferUntilReady(.buildsNotSettled) }
                    captured?.rejectAsUnavailable()
                    if busyFirst == false { captured?.deferUntilReady(.buildsNotSettled) }
                    return false
                },
                destroy: { _ in
                    XCTFail("Unavailable preflight cannot enter native destruction.")
                    return .failed(1)
                })

            XCTAssertEqual(outcome, .unavailable)
            XCTAssertTrue(captured?.isUnavailable == true)
            XCTAssertEqual(captured?.busyReason, busyFirst == nil ? nil : .buildsNotSettled)
            XCTAssertFalse(ticket.isCurrent)
            XCTAssertEqual(harness.authority?.preparationCount, 0)
            XCTAssertTrue(harness.authority?.lease.finished.isEmpty == true)
            XCTAssertTrue(harness.lifetime.isAlive)
        }
    }

    func testUnavailablePreflightMarkerStrengthensTrueVoteWithoutCallingAuthority() async throws {
        let harness = try DeferredTestHarness()
        let ticket = try harness.ticket()
        let outcome = harness.control.attemptClose(
            expectedHandle: harness.handle, ticket: ticket, participants: [],
            preflight: {
                harness.control.activeAttempt?.rejectAsUnavailable()
                return true
            },
            destroy: { _ in
                XCTFail("The unavailability marker is not an approval.")
                return .failed(1)
            })

        XCTAssertEqual(outcome, .unavailable)
        XCTAssertEqual(harness.authority?.preparationCount, 0)
        XCTAssertFalse(ticket.isCurrent)
        XCTAssertTrue(harness.lifetime.isAlive)
    }

    func testStaleAttemptMarkerCannotRejectTheNextNativeEvaluation() async throws {
        let harness = try DeferredTestHarness()
        var stale: Win32CloseAttempt?
        var current: Win32CloseAttempt?
        XCTAssertEqual(
            harness.control.attemptClose(
                expectedHandle: harness.handle, ticket: nil, participants: [],
                preflight: {
                    stale = harness.control.activeAttempt
                    return false
                },
                destroy: { _ in .failed(1) }), .vetoed)
        stale?.rejectAsUnavailable()
        XCTAssertFalse(stale?.isUnavailable == true)

        XCTAssertEqual(
            harness.control.attemptClose(
                expectedHandle: harness.handle, ticket: nil, participants: [],
                preflight: {
                    current = harness.control.activeAttempt
                    stale?.rejectAsUnavailable()
                    XCTAssertFalse(stale?.isUnavailable == true)
                    XCTAssertFalse(current?.isUnavailable == true)
                    return true
                },
                destroy: { _ in
                    harness.control.beginDestruction(harness.lifetime)
                    harness.control.completeDestruction(harness.lifetime)
                    return .succeeded
                }), .closed)
        XCTAssertNotEqual(stale?.id, current?.id)
        XCTAssertFalse(current?.isUnavailable == true)
        XCTAssertEqual(harness.authority?.lease.finished, [.closed])
    }

    func testUnavailableMarkerDuringPreparationOrValidationFinishesLeaseExactlyOnce() async throws {
        for duringPreparation in [false, true] {
            let harness = try DeferredTestHarness()
            let authority = try XCTUnwrap(harness.authority)
            defer {
                authority.willPrepare = nil
                authority.lease.willValidate = nil
            }
            let ticket = try harness.ticket()
            authority.willPrepare = { attempt in
                if duringPreparation { attempt.rejectAsUnavailable() }
            }
            authority.lease.willValidate = {
                if !duringPreparation { harness.control.activeAttempt?.rejectAsUnavailable() }
            }
            let outcome = harness.control.attemptClose(
                expectedHandle: harness.handle, ticket: ticket, participants: [],
                preflight: { true },
                destroy: { _ in
                    XCTFail("A stronger rejection during commit cannot reach native destruction.")
                    return .failed(1)
                })

            XCTAssertEqual(outcome, .unavailable)
            XCTAssertEqual(authority.preparationCount, 1)
            XCTAssertEqual(authority.lease.validationCount, duringPreparation ? 0 : 1)
            XCTAssertEqual(authority.lease.finished, [.unavailable])
            XCTAssertFalse(ticket.isCurrent)
            XCTAssertTrue(harness.lifetime.isAlive)
        }
    }

    func testCompletedDestructionWinsOverUnavailableMarkerAtEveryCallbackStage() async throws {
        for stage in DeferredTestMarkerStage.allCases {
            let harness = try DeferredTestHarness()
            let authority = try XCTUnwrap(harness.authority)
            defer {
                authority.willPrepare = nil
                authority.lease.willValidate = nil
            }
            let ticket = try harness.ticket()
            let markAndComplete = {
                harness.control.activeAttempt?.rejectAsUnavailable()
                harness.control.beginDestruction(harness.lifetime)
                harness.control.completeDestruction(harness.lifetime)
            }
            authority.willPrepare = { _ in
                if stage == .preparation { markAndComplete() }
            }
            authority.lease.willValidate = {
                if stage == .validation { markAndComplete() }
            }
            let outcome = harness.control.attemptClose(
                expectedHandle: harness.handle, ticket: ticket, participants: [],
                preflight: {
                    if stage == .preflight {
                        markAndComplete()
                        return false
                    }
                    return true
                },
                destroy: { _ in
                    XCTFail("Completed destruction must not issue another native destroy.")
                    return .failed(1)
                })

            XCTAssertEqual(outcome, .closed)
            XCTAssertTrue(harness.lifetime.destructionCompleted)
            XCTAssertFalse(ticket.isCurrent)
            XCTAssertEqual(authority.preparationCount, stage == .preflight ? 0 : 1)
            XCTAssertEqual(authority.lease.validationCount, stage == .validation ? 1 : 0)
            XCTAssertEqual(authority.lease.finished, stage == .preflight ? [] : [.closed])
        }
    }

    func testHiddenNativePromptPostsRetryThenUsesTaggedCloseCommit() async throws {
        let fixture = try makeHiddenNativeFixture()
        defer { destroyHiddenNativeFixture(fixture) }
        let ticket = try XCTUnwrap(fixture.registration.makeTicket(intentID: UUID()))
        let registration = fixture.registration
        weak var window = fixture.window
        var events: [String] = []
        var outcome: Win32CloseAttemptOutcome?
        XCTAssertEqual(
            registration.enqueue(
                ticket: ticket, phase: .prompt,
                onPostFailure: { _, _ in XCTFail("Unexpected native prompt post failure.") },
                action: { delivered in
                    events.append("prompt")
                    XCTAssertTrue(delivered === ticket)
                    XCTAssertEqual(
                        registration.enqueue(
                            ticket: ticket, phase: .retry,
                            onPostFailure: { _, _ in XCTFail("Unexpected native retry post failure.") },
                            action: { retry in
                                events.append("retry")
                                guard let window else {
                                    XCTFail("Owned native window disappeared before retry.")
                                    return
                                }
                                outcome = window.attemptClose(ticket: retry)
                            }), .queued)
                }), .queued)
        XCTAssertTrue(events.isEmpty)

        var prompt = try takeNativeWake(fixture.window)
        DispatchMessageW(&prompt)
        XCTAssertEqual(events, ["prompt"])
        XCTAssertNotNil(fixture.window.nativeHandle)
        XCTAssertTrue(ticket.isCurrent)
        var retry = try takeNativeWake(fixture.window)
        XCTAssertNotEqual(prompt.wParam, retry.wParam)
        DispatchMessageW(&retry)

        XCTAssertEqual(events, ["prompt", "retry"])
        XCTAssertEqual(outcome, .closed)
        XCTAssertNil(fixture.window.nativeHandle)
        XCTAssertEqual(fixture.delegate.preflightCount, 1)
        XCTAssertEqual(fixture.delegate.closedCount, 1)
        XCTAssertEqual(fixture.authority.lease.finished, [.closed])
        XCTAssertFalse(ticket.isCurrent)
    }

    func testHiddenNativeWakeIgnoresWrongNonceAndDuplicateDelivery() async throws {
        let fixture = try makeHiddenNativeFixture()
        defer { destroyHiddenNativeFixture(fixture) }
        let handle = try hiddenNativeHandle(fixture.window)
        let ticket = try XCTUnwrap(fixture.registration.makeTicket(intentID: UUID()))
        var deliveries = 0
        let enqueue = {
            fixture.registration.enqueue(
                ticket: ticket, phase: .prompt,
                onPostFailure: { _, _ in XCTFail("Unexpected native post failure.") },
                action: { _ in deliveries += 1 })
        }
        XCTAssertEqual(enqueue(), .queued)
        var wake = try takeNativeWake(fixture.window)
        let wrongNonce = UInt(wake.wParam) ^ UInt.max
        SendMessageW(handle, Win32Window.deferredCloseMessage, WPARAM(wrongNonce), 0)
        XCTAssertEqual(deliveries, 0)
        XCTAssertEqual(enqueue(), .coalesced)

        DispatchMessageW(&wake)
        SendMessageW(handle, Win32Window.deferredCloseMessage, wake.wParam, 0)

        XCTAssertEqual(deliveries, 1)
        XCTAssertTrue(ticket.isCurrent)
        var unexpected = MSG()
        XCTAssertFalse(
            PeekMessageW(
                &unexpected, handle, Win32Window.deferredCloseMessage, Win32Window.deferredCloseMessage,
                UINT(PM_NOREMOVE)))
        XCTAssertFalse(IsWindowVisible(handle))
    }

    func testHiddenNativeModalPumpDefersTheConsumedWakeUntilModalExit() async throws {
        let fixture = try makeHiddenNativeFixture()
        defer { destroyHiddenNativeFixture(fixture) }
        let handle = try hiddenNativeHandle(fixture.window)
        let ticket = try XCTUnwrap(fixture.registration.makeTicket(intentID: UUID()))
        var deliveries = 0
        XCTAssertEqual(
            fixture.registration.enqueue(
                ticket: ticket, phase: .prompt,
                onPostFailure: { _, _ in XCTFail("Unexpected native modal rearm failure.") },
                action: { _ in deliveries += 1 }), .queued)
        var first = try takeNativeWake(fixture.window)

        Win32DispatchScope.withNativeModal {
            DispatchMessageW(&first)
            XCTAssertEqual(deliveries, 0)
            var pending = MSG()
            XCTAssertFalse(
                PeekMessageW(
                    &pending, handle, Win32Window.deferredCloseMessage, Win32Window.deferredCloseMessage,
                    UINT(PM_NOREMOVE)))
        }

        XCTAssertEqual(deliveries, 0)
        var rearmed = try takeNativeWake(fixture.window)
        XCTAssertEqual(first.wParam, rearmed.wParam)
        DispatchMessageW(&rearmed)
        XCTAssertEqual(deliveries, 1)
        XCTAssertTrue(IsWindow(handle))
        XCTAssertFalse(IsWindowVisible(handle))
    }

    func testHiddenNativeRecreationCannotUseAStaleScalarWake() async throws {
        let fixture = try makeHiddenNativeFixture()
        defer { destroyHiddenNativeFixture(fixture) }
        let oldTicket = try XCTUnwrap(fixture.registration.makeTicket(intentID: UUID()))
        var oldDeliveries = 0
        var newDeliveries = 0
        XCTAssertEqual(
            fixture.registration.enqueue(
                ticket: oldTicket, phase: .prompt,
                onPostFailure: { _, _ in XCTFail("Unexpected old native post failure.") },
                action: { _ in oldDeliveries += 1 }), .queued)
        let staleWake = try takeNativeWake(fixture.window)
        DestroyWindow(try hiddenNativeHandle(fixture.window))
        XCTAssertNil(fixture.window.nativeHandle)
        try fixture.window.create()
        let newHandle = try hiddenNativeHandle(fixture.window)
        let authority = DeferredTestAuthority()
        let registration = try XCTUnwrap(fixture.window.installCloseAuthority(authority))
        let ticket = try XCTUnwrap(registration.makeTicket(intentID: oldTicket.intentID))
        XCTAssertEqual(
            registration.enqueue(
                ticket: ticket, phase: .prompt,
                onPostFailure: { _, _ in XCTFail("Unexpected replacement native post failure.") },
                action: { _ in newDeliveries += 1 }), .queued)

        SendMessageW(newHandle, Win32Window.deferredCloseMessage, staleWake.wParam, 0)
        XCTAssertEqual(oldDeliveries, 0)
        XCTAssertEqual(newDeliveries, 0)
        var current = try takeNativeWake(fixture.window)
        XCTAssertNotEqual(staleWake.wParam, current.wParam)
        DispatchMessageW(&current)

        XCTAssertEqual(oldDeliveries, 0)
        XCTAssertEqual(newDeliveries, 1)
        XCTAssertFalse(oldTicket.isCurrent)
        XCTAssertTrue(ticket.isCurrent)
        XCTAssertFalse(IsWindowVisible(newHandle))
        withExtendedLifetime(authority) {}
    }

    private func makeHiddenNativeFixture() throws -> DeferredTestNativeFixture {
        try XCTSkipUnless(!hasPendingQuit(), "Another test has an unconsumed quit message on this thread.")
        let window = Win32Window(title: "Deferred close test", clientSize: IntSize(width: 160, height: 100))
        window.postsQuitMessageOnDestroy = false
        let delegate = DeferredTestNativeDelegate()
        let authority = DeferredTestAuthority()
        window.delegate = delegate
        do {
            try window.create()
        } catch {
            throw XCTSkip("This environment cannot create an owned hidden window: \(error)")
        }
        do {
            let handle = try hiddenNativeHandle(window)
            XCTAssertFalse(IsWindowVisible(handle))
            let registration = try XCTUnwrap(window.installCloseAuthority(authority))
            return DeferredTestNativeFixture(
                window: window, delegate: delegate, authority: authority, registration: registration)
        } catch {
            if let raw = window.nativeHandle?.rawPointer { DestroyWindow(HWND(bitPattern: Int(bitPattern: raw))) }
            throw error
        }
    }

    private func hiddenNativeHandle(_ window: Win32Window) throws -> HWND {
        let raw = try XCTUnwrap(window.nativeHandle?.rawPointer)
        return try XCTUnwrap(HWND(bitPattern: Int(bitPattern: raw)))
    }

    private func takeNativeWake(_ window: Win32Window) throws -> MSG {
        var message = MSG()
        guard
            PeekMessageW(
                &message, try hiddenNativeHandle(window), Win32Window.deferredCloseMessage,
                Win32Window.deferredCloseMessage, UINT(PM_REMOVE))
        else {
            XCTFail("The owned deferred wake was not present in the native queue.")
            throw DeferredTestError.missingNativeWake
        }
        return message
    }

    private func destroyHiddenNativeFixture(_ fixture: DeferredTestNativeFixture) {
        if let raw = fixture.window.nativeHandle?.rawPointer { DestroyWindow(HWND(bitPattern: Int(bitPattern: raw))) }
        XCTAssertFalse(hasPendingQuit(), "Owned native test windows must not post process quit.")
    }

    private func hasPendingQuit() -> Bool {
        var message = MSG()
        return PeekMessageW(&message, nil, UINT(WM_QUIT), UINT(WM_QUIT), UINT(PM_NOREMOVE))
    }
}

@MainActor
private final class DeferredTestHarness {
    let control: Win32CloseControl
    let lifetime: Win32CloseLifetime
    let handle: UInt
    let registration: Win32CloseRegistration
    let posts: DeferredTestPosts
    var authority: DeferredTestAuthority?

    init(
        handle: UInt = 101,
        sequence: Win32CloseWakeSequence? = nil,
        postResults: [Win32CloseNativeResult] = []
    ) throws {
        let posts = DeferredTestPosts(results: postResults)
        let control = Win32CloseControl(
            postWake: { [posts] handle, nonce in posts.post(handle: handle, nonce: nonce) },
            wakeSequence: sequence ?? Win32CloseWakeSequence())
        let lifetime = control.beginLifetime(generation: 1)
        control.didCreate(lifetime, handle: handle)
        let authority = DeferredTestAuthority()
        self.posts = posts
        self.control = control
        self.lifetime = lifetime
        self.handle = handle
        self.authority = authority
        registration = try XCTUnwrap(control.installAuthority(authority))
    }

    func ticket(intentID: Foundation.UUID = Foundation.UUID()) throws -> Win32CloseTicket {
        try XCTUnwrap(registration.makeTicket(intentID: intentID))
    }

    func enqueue(
        _ ticket: Win32CloseTicket,
        phase: Win32DeferredClosePhase = .prompt,
        onPostFailure: @escaping @MainActor (Win32CloseTicket, UInt32) -> Void = { _, _ in
            XCTFail("Unexpected deferred post failure.")
        },
        action: @escaping @MainActor (Win32CloseTicket) -> Void
    ) -> Win32DeferredCloseSubmission {
        registration.enqueue(ticket: ticket, phase: phase, onPostFailure: onPostFailure, action: action)
    }

    func deliver(_ nonce: UInt) {
        Win32DispatchScope.withWindowDispatch { control.receiveDeferredWake(nonce: nonce) }
    }

    func lastNonce() throws -> UInt { try XCTUnwrap(posts.messages.last).nonce }
}

@MainActor
private final class DeferredTestPosts {
    struct Message: Equatable {
        let handle: UInt
        let nonce: UInt
    }

    private(set) var messages: [Message] = []
    var results: [Win32CloseNativeResult]
    var onPost: (@MainActor (Message, Int) -> Void)?

    init(results: [Win32CloseNativeResult]) { self.results = results }

    func post(handle: UInt, nonce: UInt) -> Win32CloseNativeResult {
        let message = Message(handle: handle, nonce: nonce)
        messages.append(message)
        let result = results.isEmpty ? .succeeded : results.removeFirst()
        onPost?(message, messages.count)
        return result
    }
}

@MainActor
private final class DeferredTestAuthority: Win32CloseAuthority {
    let lease = DeferredTestLease()
    var willPrepare: (@MainActor (Win32CloseAttempt) -> Void)?
    private(set) var preparationCount = 0

    func prepareCloseCommit(for attempt: Win32CloseAttempt) -> Win32CloseCommitPreparation {
        preparationCount += 1
        willPrepare?(attempt)
        return .ready(lease)
    }
}

@MainActor
private struct DeferredTestNativeFixture {
    let window: Win32Window
    let delegate: DeferredTestNativeDelegate
    let authority: DeferredTestAuthority
    let registration: Win32CloseRegistration
}

@MainActor
private final class DeferredTestNativeDelegate: WindowDelegate {
    private(set) var preflightCount = 0
    private(set) var closedCount = 0

    func windowShouldClose(_ window: Win32Window) -> Bool {
        preflightCount += 1
        return true
    }

    func windowWillClose(_ window: Win32Window) { closedCount += 1 }
}

@MainActor
private final class DeferredTestLease: Win32CloseCommitLease {
    var willValidate: (@MainActor () -> Void)?
    private(set) var validationCount = 0
    private(set) var finished: [Win32CloseAttemptOutcome] = []

    func validateAndReserve() -> Win32CloseCommitDecision {
        validationCount += 1
        willValidate?()
        return .reserved
    }
    func finish(with outcome: Win32CloseAttemptOutcome) { finished.append(outcome) }
}

@MainActor
private final class DeferredTestWakeClient: Win32DispatchWakeClient {
    private let rearm: @MainActor () -> (@MainActor () -> Void)?
    private let onRelease: (@MainActor () -> Void)?

    init(
        rearm: @escaping @MainActor () -> (@MainActor () -> Void)?,
        onRelease: (@MainActor () -> Void)? = nil
    ) {
        self.rearm = rearm
        self.onRelease = onRelease
    }

    func dispatchScopeDidBecomeIdle() -> (@MainActor () -> Void)? { rearm() }
    isolated deinit { onRelease?() }
}

@MainActor
private final class DeferredTestReleaseProbe {
    private let onRelease: @MainActor () -> Void

    init(_ onRelease: @escaping @MainActor () -> Void) { self.onRelease = onRelease }
    isolated deinit { onRelease() }
}

private enum DeferredTestRetirement: CaseIterable {
    case cancel, epoch, revoke, destroy
}

private enum DeferredTestMarkerStage: CaseIterable, Equatable {
    case preflight, preparation, validation
}

private enum DeferredTestError: Error {
    case expected
    case missingNativeWake
}

// Continuation regressions extend the original 38 cases without changing them.
extension Win32DeferredCloseTests {
    func testBuildBusyRetryQueuesOneFreshContinuationAfterActionAndCaptureCleanup() async throws {
        let harness = try DeferredTestHarness()
        defer {
            harness.posts.onPost = nil
            harness.registration.revoke()
        }
        let ticket = try harness.ticket()
        let otherTicket = try harness.ticket(intentID: ticket.intentID)
        var events: [String] = []
        var attempts: [Foundation.UUID] = []
        weak var capture: DeferredTestReleaseProbe?
        harness.posts.onPost = { _, ordinal in
            guard ordinal == 2 else { return }
            XCTAssertEqual(
                events, ["retry.begin", "build.busy", "continuation.queued", "retry.end", "capture.release"])
            XCTAssertFalse(Win32DispatchScope.canDeliverWindowWake)
            events.append("continuation.post")
        }
        @MainActor func installInitialRetry() -> Win32DeferredCloseSubmission {
            let owned = DeferredTestReleaseProbe {
                events.append("capture.release")
                XCTAssertEqual(harness.posts.messages.count, 1)
                XCTAssertFalse(Win32DispatchScope.canDeliverWindowWake)
                XCTAssertEqual(
                    harness.enqueue(ticket, phase: .retry) { _ in events.append("cleanup.replacement") }, .coalesced)
            }
            capture = owned
            return harness.enqueue(ticket, phase: .retry) { [owned] delivered in
                XCTAssertTrue(delivered === ticket)
                events.append("retry.begin")
                XCTAssertEqual(
                    harness.enqueue(ticket, phase: .retry) { _ in events.append("premature.duplicate") }, .coalesced)
                XCTAssertEqual(
                    deferredContinuationBlockedAttempt(harness, ticket: ticket) { attempt in
                        if let attempt { attempts.append(attempt.id) }
                    }, .busy(.buildsNotSettled))
                events.append("build.busy")
                XCTAssertTrue(ticket.isCurrent)
                XCTAssertEqual(harness.enqueue(ticket) { _ in events.append("premature.wrong.phase") }, .busy)
                XCTAssertEqual(
                    harness.enqueue(otherTicket, phase: .retry) { _ in events.append("premature.wrong.ticket") }, .busy)
                XCTAssertEqual(
                    harness.enqueue(ticket, phase: .retry) { continued in
                        events.append("continuation.action")
                        XCTAssertTrue(continued === ticket)
                        XCTAssertEqual(
                            harness.enqueue(ticket, phase: .retry) { _ in events.append("inherited.permission") },
                            .coalesced)
                        let outcome = harness.control.attemptClose(
                            expectedHandle: harness.handle, ticket: continued, participants: [],
                            preflight: {
                                if let attempt = harness.control.activeAttempt { attempts.append(attempt.id) }
                                return false
                            },
                            destroy: { _ in
                                XCTFail("The continued preflight still has its own veto.")
                                return .failed(1)
                            })
                        XCTAssertEqual(outcome, .vetoed)
                        XCTAssertEqual(
                            harness.enqueue(ticket, phase: .retry) { _ in events.append("consumed.permission") },
                            .unavailable)
                    }, .queued)
                events.append("continuation.queued")
                XCTAssertEqual(
                    harness.enqueue(ticket, phase: .retry) { _ in events.append("replacement.action") }, .coalesced)
                XCTAssertEqual(harness.enqueue(ticket) { _ in events.append("wrong.phase") }, .busy)
                XCTAssertEqual(
                    harness.enqueue(otherTicket, phase: .retry) { _ in events.append("wrong.ticket") }, .busy)
                XCTAssertEqual(harness.posts.messages.count, 1)
                withExtendedLifetime(owned) {}
                events.append("retry.end")
            }
        }
        XCTAssertEqual(installInitialRetry(), .queued)
        let oldNonce = try harness.lastNonce()

        harness.deliver(oldNonce)

        XCTAssertNil(capture)
        XCTAssertEqual(harness.posts.messages.count, 2)
        let continuationNonce = try harness.lastNonce()
        XCTAssertNotEqual(oldNonce, continuationNonce)
        XCTAssertEqual(attempts.count, 1)
        harness.deliver(oldNonce)
        XCTAssertFalse(events.contains("continuation.action"))
        harness.deliver(continuationNonce)
        XCTAssertEqual(
            events,
            [
                "retry.begin", "build.busy", "continuation.queued", "retry.end", "capture.release", "continuation.post",
                "continuation.action",
            ])
        XCTAssertEqual(attempts.count, 2)
        XCTAssertEqual(Set(attempts).count, 2)
        XCTAssertFalse(ticket.isCurrent)
        XCTAssertTrue(otherTicket.isCurrent)
        XCTAssertEqual(harness.posts.messages.count, 2)
    }

    func testBuildBusyRetryDoesNotPostAnotherWakeWithoutExplicitContinuation() async throws {
        let harness = try DeferredTestHarness()
        defer { harness.registration.revoke() }
        let ticket = try harness.ticket()
        var actions = 0
        XCTAssertEqual(
            harness.enqueue(ticket, phase: .retry) { _ in
                actions += 1
                XCTAssertEqual(deferredContinuationBlockedAttempt(harness, ticket: ticket), .busy(.buildsNotSettled))
            }, .queued)
        let nonce = try harness.lastNonce()

        harness.deliver(nonce)
        harness.deliver(nonce)
        Win32DispatchScope.withWindowDispatch {}
        Win32DispatchScope.withNativeModal {}

        XCTAssertEqual(actions, 1)
        XCTAssertTrue(ticket.isCurrent)
        XCTAssertEqual(harness.posts.messages.count, 1)
        XCTAssertEqual(harness.enqueue(ticket, phase: .retry) { _ in actions += 1 }, .queued)
        XCTAssertEqual(harness.posts.messages.count, 2)
        harness.deliver(try harness.lastNonce())
        XCTAssertEqual(actions, 2)
    }

    func testContinuationCannotInheritBuildPermissionForAnotherBusyReason() async throws {
        let reasons: [Win32CloseBusyReason] = [.ownerOperation, .nativeDispatch, .closeInProgress]
        for reason in reasons {
            let harness = try DeferredTestHarness()
            defer { harness.registration.revoke() }
            let ticket = try harness.ticket()
            var actions = 0
            XCTAssertEqual(
                harness.enqueue(ticket, phase: .retry) { _ in
                    actions += 1
                    XCTAssertEqual(
                        deferredContinuationBlockedAttempt(harness, ticket: ticket), .busy(.buildsNotSettled))
                    XCTAssertEqual(
                        harness.enqueue(ticket, phase: .retry) { _ in
                            actions += 1
                            XCTAssertEqual(
                                deferredContinuationBlockedAttempt(harness, ticket: ticket, reason: reason),
                                .busy(reason))
                            XCTAssertEqual(
                                harness.enqueue(ticket, phase: .retry) { _ in
                                    XCTFail("Another busy reason cannot create a continuation.")
                                }, .busy)
                        }, .queued)
                }, .queued)

            harness.deliver(try harness.lastNonce())
            XCTAssertEqual(harness.posts.messages.count, 2)
            harness.deliver(try harness.lastNonce())

            XCTAssertEqual(actions, 2)
            XCTAssertTrue(ticket.isCurrent)
            XCTAssertEqual(harness.posts.messages.count, 2)
        }
    }

    func testTerminalRetryResultsCannotProduceAContinuation() async throws {
        for terminal in DeferredContinuationTerminalResult.allCases {
            let harness = try DeferredTestHarness()
            defer { harness.registration.revoke() }
            let ticket = try harness.ticket()
            var nativeCalls = 0
            var outcome: Win32CloseAttemptOutcome?
            var continuation: Win32DeferredCloseSubmission?
            XCTAssertEqual(
                harness.enqueue(ticket, phase: .retry) { delivered in
                    outcome = harness.control.attemptClose(
                        expectedHandle: harness.handle, ticket: delivered, participants: [],
                        preflight: {
                            if terminal == .unavailable { harness.control.activeAttempt?.rejectAsUnavailable() }
                            return terminal != .vetoed
                        },
                        destroy: { _ in
                            nativeCalls += 1
                            switch terminal {
                            case .nativeFailure: return .failed(5)
                            case .completionNotObserved: return .succeeded
                            case .closed:
                                harness.control.beginDestruction(harness.lifetime)
                                harness.control.completeDestruction(harness.lifetime)
                                return .succeeded
                            case .vetoed, .unavailable:
                                XCTFail("Rejected preflight cannot enter native destruction.")
                                return .failed(1)
                            }
                        })
                    continuation = harness.enqueue(ticket, phase: .retry) { _ in
                        XCTFail("A terminal retry cannot reuse its consumed ticket.")
                    }
                }, .queued)

            harness.deliver(try harness.lastNonce())

            XCTAssertEqual(outcome, terminal.outcome)
            XCTAssertEqual(continuation, .unavailable)
            XCTAssertFalse(ticket.isCurrent)
            XCTAssertEqual(nativeCalls, terminal == .vetoed || terminal == .unavailable ? 0 : 1)
            XCTAssertEqual(harness.posts.messages.count, 1)
        }
    }

    func testRetiredTicketCannotSpendAnEarnedBuildContinuation() async throws {
        for retirement in DeferredTestRetirement.allCases {
            let harness = try DeferredTestHarness()
            defer { harness.registration.revoke() }
            let ticket = try harness.ticket()
            var continuation: Win32DeferredCloseSubmission?
            XCTAssertEqual(
                harness.enqueue(ticket, phase: .retry) { _ in
                    XCTAssertEqual(
                        deferredContinuationBlockedAttempt(harness, ticket: ticket), .busy(.buildsNotSettled))
                    switch retirement {
                    case .cancel: ticket.cancel()
                    case .epoch: harness.registration.invalidateTickets()
                    case .revoke: harness.registration.revoke()
                    case .destroy: harness.control.beginDestruction(harness.lifetime)
                    }
                    continuation = harness.enqueue(ticket, phase: .retry) { _ in
                        XCTFail("A retired ticket cannot inherit continuation permission.")
                    }
                }, .queued)

            harness.deliver(try harness.lastNonce())

            XCTAssertEqual(continuation, .unavailable)
            XCTAssertFalse(ticket.isCurrent)
            XCTAssertEqual(harness.posts.messages.count, 1)
        }
    }

    func testCancellationDuringCaptureCleanupOrBeforeWakeStopsQueuedContinuation() async throws {
        for cancelDuringCleanup in [false, true] {
            let harness = try DeferredTestHarness()
            defer { harness.registration.revoke() }
            let ticket = try harness.ticket()
            var captureReleased = false
            var continuationActions = 0
            @MainActor func installInitialRetry() -> Win32DeferredCloseSubmission {
                let capture = DeferredTestReleaseProbe {
                    captureReleased = true
                    XCTAssertEqual(harness.posts.messages.count, 1)
                    if cancelDuringCleanup { ticket.cancel() }
                }
                return harness.enqueue(ticket, phase: .retry) { [capture] _ in
                    XCTAssertEqual(
                        deferredContinuationBlockedAttempt(harness, ticket: ticket), .busy(.buildsNotSettled))
                    XCTAssertEqual(
                        harness.enqueue(ticket, phase: .retry) { _ in continuationActions += 1 }, .queued)
                    withExtendedLifetime(capture) {}
                }
            }
            XCTAssertEqual(installInitialRetry(), .queued)
            let initialNonce = try harness.lastNonce()

            harness.deliver(initialNonce)

            XCTAssertTrue(captureReleased)
            XCTAssertEqual(harness.posts.messages.count, cancelDuringCleanup ? 1 : 2)
            if !cancelDuringCleanup { ticket.cancel() }
            XCTAssertFalse(ticket.isCurrent)
            harness.deliver(try harness.lastNonce())
            harness.deliver(initialNonce)
            XCTAssertEqual(continuationActions, 0)
            XCTAssertEqual(harness.posts.messages.count, cancelDuringCleanup ? 1 : 2)
        }
    }

    func testContinuationPostFailureIsDelayedUntilCleanupAndDoesNotRetryItself() async throws {
        let harness = try DeferredTestHarness(postResults: [.succeeded, .failed(87)])
        defer { harness.registration.revoke() }
        let ticket = try harness.ticket()
        var events: [String] = []
        var failures: [UInt32] = []
        @MainActor func installInitialRetry() -> Win32DeferredCloseSubmission {
            let capture = DeferredTestReleaseProbe { events.append("capture.release") }
            return harness.enqueue(ticket, phase: .retry) { [capture] _ in
                XCTAssertEqual(deferredContinuationBlockedAttempt(harness, ticket: ticket), .busy(.buildsNotSettled))
                XCTAssertEqual(
                    harness.enqueue(
                        ticket, phase: .retry,
                        onPostFailure: { failedTicket, code in
                            XCTAssertTrue(failedTicket === ticket)
                            XCTAssertEqual(events, ["action.end", "capture.release"])
                            failures.append(code)
                            XCTAssertTrue(ticket.isCurrent)
                            XCTAssertNil(harness.control.activeAttempt)
                            XCTAssertEqual(
                                deferredContinuationBlockedAttempt(harness, ticket: ticket), .busy(.nativeDispatch))
                        }
                    ) { _ in XCTFail("A failed continuation post cannot execute.") }, .queued)
                XCTAssertTrue(failures.isEmpty)
                withExtendedLifetime(capture) {}
                events.append("action.end")
            }
        }
        XCTAssertEqual(installInitialRetry(), .queued)

        harness.deliver(try harness.lastNonce())

        XCTAssertEqual(failures, [87])
        XCTAssertEqual(harness.posts.messages.count, 2)
        XCTAssertNotEqual(harness.posts.messages[0].nonce, harness.posts.messages[1].nonce)
        harness.deliver(try harness.lastNonce())
        XCTAssertEqual(failures, [87])
        XCTAssertTrue(ticket.isCurrent)
        XCTAssertEqual(harness.posts.messages.count, 2)
    }

    func testEarnedContinuationCannotFollowARecreatedLifetimeWithTheSameHandle() async throws {
        let harness = try DeferredTestHarness()
        let oldTicket = try harness.ticket()
        let replacementAuthority = DeferredTestAuthority()
        var replacementRegistration: Win32CloseRegistration?
        var replacementTicket: Win32CloseTicket?
        var replacementLifetime: Win32CloseLifetime?
        var insideSubmission: Win32DeferredCloseSubmission?
        var replacementActions = 0
        defer {
            replacementRegistration?.revoke()
            harness.registration.revoke()
        }
        XCTAssertEqual(
            harness.enqueue(oldTicket, phase: .retry) { _ in
                XCTAssertEqual(deferredContinuationBlockedAttempt(harness, ticket: oldTicket), .busy(.buildsNotSettled))
                harness.control.beginDestruction(harness.lifetime)
                harness.control.completeDestruction(harness.lifetime)
                let nextLifetime = harness.control.beginLifetime(generation: 2)
                harness.control.didCreate(nextLifetime, handle: harness.handle)
                replacementLifetime = nextLifetime
                guard let registration = harness.control.installAuthority(replacementAuthority),
                    let ticket = registration.makeTicket(intentID: oldTicket.intentID)
                else {
                    XCTFail("The recreated window must establish a distinct close authority and ticket.")
                    return
                }
                replacementRegistration = registration
                replacementTicket = ticket
                XCTAssertEqual(
                    harness.enqueue(oldTicket, phase: .retry) { _ in
                        XCTFail("An old ticket cannot target the new lifetime.")
                    },
                    .unavailable)
                insideSubmission = registration.enqueue(
                    ticket: ticket, phase: .retry,
                    onPostFailure: { _, _ in XCTFail("No replacement wake should be posted inside the old action.") },
                    action: { _ in replacementActions += 1 })
                XCTAssertEqual(
                    deferredContinuationBlockedAttempt(harness, ticket: ticket), .busy(.nativeDispatch))
            }, .queued)
        let oldNonce = try harness.lastNonce()

        harness.deliver(oldNonce)

        XCTAssertEqual(insideSubmission, .busy)
        XCTAssertFalse(oldTicket.isCurrent)
        XCTAssertTrue(replacementLifetime?.isAlive == true)
        XCTAssertEqual(replacementLifetime?.handle, harness.handle)
        XCTAssertEqual(harness.posts.messages.count, 1)
        XCTAssertEqual(replacementActions, 0)
        let registration = try XCTUnwrap(replacementRegistration)
        let ticket = try XCTUnwrap(replacementTicket)
        XCTAssertTrue(ticket.isCurrent)
        XCTAssertEqual(
            registration.enqueue(
                ticket: ticket, phase: .retry,
                onPostFailure: { _, _ in XCTFail("Unexpected fresh replacement post failure.") },
                action: { _ in replacementActions += 1 }), .queued)
        let nextNonce = try harness.lastNonce()
        XCTAssertNotEqual(oldNonce, nextNonce)
        XCTAssertEqual(harness.posts.messages.last?.handle, harness.handle)
        harness.deliver(oldNonce)
        XCTAssertEqual(replacementActions, 0)
        harness.deliver(nextNonce)
        XCTAssertEqual(replacementActions, 1)
        withExtendedLifetime(replacementAuthority) {}
    }

    func testSecondInlineAttemptRetiresUnusedPermissionButPreservesQueuedContinuation() async throws {
        for queueBeforeSecondAttempt in [false, true] {
            let harness = try DeferredTestHarness()
            defer { harness.registration.revoke() }
            let ticket = try harness.ticket()
            var preflightCount = 0
            var continuedActions = 0
            var secondOutcome: Win32CloseAttemptOutcome?
            var duplicateSubmission: Win32DeferredCloseSubmission?
            XCTAssertEqual(
                harness.enqueue(ticket, phase: .retry) { _ in
                    XCTAssertEqual(
                        deferredContinuationBlockedAttempt(harness, ticket: ticket) { _ in preflightCount += 1 },
                        .busy(.buildsNotSettled))
                    if queueBeforeSecondAttempt {
                        XCTAssertEqual(
                            harness.enqueue(ticket, phase: .retry) { _ in continuedActions += 1 }, .queued)
                    }
                    secondOutcome = deferredContinuationBlockedAttempt(harness, ticket: ticket) { _ in
                        preflightCount += 1
                    }
                    duplicateSubmission = harness.enqueue(ticket, phase: .retry) { _ in
                        XCTFail("A rejected inline attempt must not replace the already queued continuation.")
                    }
                    XCTAssertEqual(harness.posts.messages.count, 1)
                    XCTAssertTrue(ticket.isCurrent)
                }, .queued)
            let oldNonce = try harness.lastNonce()

            harness.deliver(oldNonce)

            XCTAssertEqual(secondOutcome, .busy(.nativeDispatch))
            XCTAssertEqual(preflightCount, 1)
            XCTAssertEqual(duplicateSubmission, queueBeforeSecondAttempt ? .coalesced : .busy)
            XCTAssertEqual(harness.posts.messages.count, queueBeforeSecondAttempt ? 2 : 1)
            harness.deliver(oldNonce)
            XCTAssertEqual(continuedActions, 0)
            if queueBeforeSecondAttempt { harness.deliver(try harness.lastNonce()) }
            XCTAssertEqual(continuedActions, queueBeforeSecondAttempt ? 1 : 0)
            XCTAssertTrue(ticket.isCurrent)
        }
    }

    func testExhaustedNonceCannotReuseTheExecutingWakeForAContinuation() async throws {
        let harness = try DeferredTestHarness(sequence: Win32CloseWakeSequence(startingAfter: UInt.max - 1))
        defer { harness.registration.revoke() }
        let ticket = try harness.ticket()
        var submissions: [Win32DeferredCloseSubmission] = []
        var actions = 0
        XCTAssertEqual(
            harness.enqueue(ticket, phase: .retry) { _ in
                actions += 1
                XCTAssertEqual(deferredContinuationBlockedAttempt(harness, ticket: ticket), .busy(.buildsNotSettled))
                submissions.append(
                    harness.enqueue(ticket, phase: .retry) { _ in XCTFail("An exhausted nonce cannot be reused.") })
                submissions.append(
                    harness.enqueue(ticket, phase: .retry) { _ in
                        XCTFail("Exhaustion cannot restart the nonce sequence.")
                    })
            }, .queued)
        XCTAssertEqual(try harness.lastNonce(), UInt.max)

        harness.deliver(UInt.max)
        harness.deliver(UInt.max)

        XCTAssertEqual(submissions, [.unavailable, .busy])
        XCTAssertEqual(actions, 1)
        XCTAssertTrue(ticket.isCurrent)
        XCTAssertEqual(harness.posts.messages, [.init(handle: harness.handle, nonce: UInt.max)])
        XCTAssertEqual(
            harness.enqueue(ticket, phase: .retry) { _ in XCTFail("The exhausted sequence remains unavailable.") },
            .unavailable)
        XCTAssertEqual(harness.posts.messages.count, 1)
    }

    func testBuildBusyPreparationAndValidationCanEachEarnOneContinuation() async throws {
        for busyDuringPreparation in [false, true] {
            let posts = DeferredTestPosts(results: [])
            let control = Win32CloseControl(
                postWake: { [posts] handle, nonce in posts.post(handle: handle, nonce: nonce) },
                wakeSequence: Win32CloseWakeSequence())
            let lifetime = control.beginLifetime(generation: 1)
            control.didCreate(lifetime, handle: 101)
            let lease = DeferredContinuationDecisionLease(decision: .busy(.buildsNotSettled))
            let authority = DeferredContinuationDecisionAuthority(
                preparation: busyDuringPreparation ? .busy(.buildsNotSettled) : .ready(lease))
            let registration = try XCTUnwrap(control.installAuthority(authority))
            defer { registration.revoke() }
            let ticket = try XCTUnwrap(registration.makeTicket(intentID: UUID()))
            var continuationActions = 0
            XCTAssertEqual(
                registration.enqueue(
                    ticket: ticket, phase: .retry,
                    onPostFailure: { _, _ in XCTFail("Unexpected initial retry post failure.") },
                    action: { _ in
                        XCTAssertEqual(
                            control.attemptClose(
                                expectedHandle: 101, ticket: ticket, participants: [],
                                preflight: { true },
                                destroy: { _ in
                                    XCTFail("Busy commit participants cannot enter native destruction.")
                                    return .failed(1)
                                }), .busy(.buildsNotSettled))
                        XCTAssertEqual(
                            registration.enqueue(
                                ticket: ticket, phase: .retry,
                                onPostFailure: { _, _ in XCTFail("Unexpected continuation post failure.") },
                                action: { _ in continuationActions += 1 }), .queued)
                        XCTAssertEqual(posts.messages.count, 1)
                    }), .queued)
            let firstNonce = try XCTUnwrap(posts.messages.first).nonce

            Win32DispatchScope.withWindowDispatch { control.receiveDeferredWake(nonce: firstNonce) }

            XCTAssertEqual(posts.messages.count, 2)
            XCTAssertEqual(authority.preparationCount, 1)
            XCTAssertEqual(lease.validationCount, busyDuringPreparation ? 0 : 1)
            XCTAssertEqual(lease.finished, busyDuringPreparation ? [] : [.busy(.buildsNotSettled)])
            XCTAssertTrue(ticket.isCurrent)
            let nextNonce = try XCTUnwrap(posts.messages.last).nonce
            XCTAssertNotEqual(firstNonce, nextNonce)
            Win32DispatchScope.withWindowDispatch { control.receiveDeferredWake(nonce: nextNonce) }
            XCTAssertEqual(continuationActions, 1)
            withExtendedLifetime(authority) {}
        }
    }

    func testTopologyOrHandleChangeRetiresContinuationEvenIfHandleIsRestored() async throws {
        for changeHandle in [false, true] {
            let harness = try DeferredTestHarness()
            defer { harness.registration.revoke() }
            let ticket = try harness.ticket()
            var submissions: [Win32DeferredCloseSubmission] = []
            XCTAssertEqual(
                harness.enqueue(ticket, phase: .retry) { _ in
                    XCTAssertEqual(
                        deferredContinuationBlockedAttempt(harness, ticket: ticket), .busy(.buildsNotSettled))
                    if changeHandle {
                        harness.control.didCreate(harness.lifetime, handle: harness.handle + 1)
                    } else {
                        harness.control.noteTopologyChanged()
                    }
                    submissions.append(
                        harness.enqueue(ticket, phase: .retry) { _ in
                            XCTFail("Changed native ownership cannot continue.")
                        })
                    if changeHandle { harness.control.didCreate(harness.lifetime, handle: harness.handle) }
                    submissions.append(
                        harness.enqueue(ticket, phase: .retry) { _ in
                            XCTFail("Restoring a value cannot revive permission.")
                        })
                }, .queued)

            harness.deliver(try harness.lastNonce())

            XCTAssertEqual(submissions, [.busy, .busy])
            XCTAssertTrue(ticket.isCurrent)
            XCTAssertEqual(harness.lifetime.handle, harness.handle)
            XCTAssertEqual(harness.posts.messages.count, 1)
        }
    }

    func testNestedRequestDuringPreflightOrLeaseFinishPreventsContinuationPublication() async throws {
        for duringFinish in [false, true] {
            for taggedNestedRequest in [false, true] {
                let posts = DeferredTestPosts(results: [])
                let control = Win32CloseControl(
                    postWake: { [posts] handle, nonce in posts.post(handle: handle, nonce: nonce) },
                    wakeSequence: Win32CloseWakeSequence())
                let lifetime = control.beginLifetime(generation: 1)
                control.didCreate(lifetime, handle: 101)
                let lease = DeferredContinuationDecisionLease(decision: .busy(.buildsNotSettled))
                let authority = DeferredContinuationDecisionAuthority(preparation: .ready(lease))
                let registration = try XCTUnwrap(control.installAuthority(authority))
                let ticket = try XCTUnwrap(registration.makeTicket(intentID: UUID()))
                defer {
                    lease.willFinish = nil
                    registration.revoke()
                }
                var nested: Win32CloseAttemptOutcome?
                var continuation: Win32DeferredCloseSubmission?
                @MainActor func makeNestedRequest() {
                    nested = control.attemptClose(
                        expectedHandle: 101, ticket: taggedNestedRequest ? ticket : nil, participants: [],
                        preflight: {
                            XCTFail("An active native attempt cannot reenter its preflight.")
                            return false
                        },
                        destroy: { _ in
                            XCTFail("An active native attempt cannot reenter native destruction.")
                            return .failed(1)
                        })
                }
                lease.willFinish = { outcome in
                    XCTAssertEqual(outcome, .busy(.buildsNotSettled))
                    XCTAssertNotNil(control.activeAttempt)
                    if duringFinish { makeNestedRequest() }
                }
                XCTAssertEqual(
                    registration.enqueue(
                        ticket: ticket, phase: .retry,
                        onPostFailure: { _, _ in XCTFail("Unexpected initial post failure.") },
                        action: { _ in
                            XCTAssertEqual(
                                control.attemptClose(
                                    expectedHandle: 101, ticket: ticket, participants: [],
                                    preflight: {
                                        if duringFinish { return true }
                                        control.activeAttempt?.deferUntilReady(.buildsNotSettled)
                                        makeNestedRequest()
                                        return false
                                    },
                                    destroy: { _ in
                                        XCTFail("A build wait cannot enter native destruction.")
                                        return .failed(1)
                                    }), .busy(.buildsNotSettled))
                            continuation = registration.enqueue(
                                ticket: ticket, phase: .retry,
                                onPostFailure: { _, _ in XCTFail("A rejected continuation cannot post.") },
                                action: { _ in XCTFail("Nested close requests retire the pending permission.") })
                        }), .queued)
                let nonce = try XCTUnwrap(posts.messages.first).nonce

                Win32DispatchScope.withWindowDispatch { control.receiveDeferredWake(nonce: nonce) }

                XCTAssertEqual(nested, .busy(.closeInProgress))
                XCTAssertEqual(continuation, .busy)
                XCTAssertEqual(lease.finished, duringFinish ? [.busy(.buildsNotSettled)] : [])
                XCTAssertTrue(ticket.isCurrent)
                XCTAssertEqual(posts.messages.count, 1)
                withExtendedLifetime(authority) {}
            }
        }
    }

    func testLeaseFinishEpochInvalidationCannotTransferContinuationToNewSameIntentTicket() async throws {
        let posts = DeferredTestPosts(results: [])
        let control = Win32CloseControl(
            postWake: { [posts] handle, nonce in posts.post(handle: handle, nonce: nonce) },
            wakeSequence: Win32CloseWakeSequence())
        let lifetime = control.beginLifetime(generation: 1)
        control.didCreate(lifetime, handle: 101)
        let lease = DeferredContinuationDecisionLease(decision: .busy(.buildsNotSettled))
        let authority = DeferredContinuationDecisionAuthority(preparation: .ready(lease))
        let registration = try XCTUnwrap(control.installAuthority(authority))
        let oldTicket = try XCTUnwrap(registration.makeTicket(intentID: UUID()))
        var freshTicket: Win32CloseTicket?
        var oldSubmission: Win32DeferredCloseSubmission?
        var freshSubmission: Win32DeferredCloseSubmission?
        defer {
            lease.willFinish = nil
            registration.revoke()
        }
        lease.willFinish = { outcome in
            XCTAssertEqual(outcome, .busy(.buildsNotSettled))
            XCTAssertTrue(control.activeAttempt?.ticket === oldTicket)
            registration.invalidateTickets()
            freshTicket = registration.makeTicket(intentID: oldTicket.intentID)
            XCTAssertFalse(oldTicket.isCurrent)
        }
        XCTAssertEqual(
            registration.enqueue(
                ticket: oldTicket, phase: .retry,
                onPostFailure: { _, _ in XCTFail("Unexpected initial post failure.") },
                action: { _ in
                    XCTAssertEqual(
                        control.attemptClose(
                            expectedHandle: 101, ticket: oldTicket, participants: [],
                            preflight: { true },
                            destroy: { _ in
                                XCTFail("A busy lease cannot destroy the fake lifetime.")
                                return .failed(1)
                            }), .busy(.buildsNotSettled))
                    oldSubmission = registration.enqueue(
                        ticket: oldTicket, phase: .retry,
                        onPostFailure: { _, _ in XCTFail("No old continuation can post.") },
                        action: { _ in XCTFail("The old ticket was invalidated by lease cleanup.") })
                    guard let freshTicket else {
                        XCTFail("Epoch invalidation preserves a usable registration for a fresh ticket.")
                        return
                    }
                    freshSubmission = registration.enqueue(
                        ticket: freshTicket, phase: .retry,
                        onPostFailure: { _, _ in XCTFail("No fresh continuation can post inside the old action.") },
                        action: { _ in XCTFail("A fresh ticket cannot inherit the old record's permission.") })
                }), .queued)
        let nonce = try XCTUnwrap(posts.messages.first).nonce

        Win32DispatchScope.withWindowDispatch { control.receiveDeferredWake(nonce: nonce) }

        XCTAssertEqual(oldSubmission, .unavailable)
        XCTAssertEqual(freshSubmission, .busy)
        XCTAssertFalse(oldTicket.isCurrent)
        XCTAssertTrue(freshTicket?.isCurrent == true)
        XCTAssertEqual(freshTicket?.intentID, oldTicket.intentID)
        XCTAssertNotEqual(freshTicket?.id, oldTicket.id)
        XCTAssertEqual(lease.finished, [.busy(.buildsNotSettled)])
        XCTAssertEqual(posts.messages.count, 1)
        withExtendedLifetime(authority) {}
    }

    func testRetryCaptureCleanupCannotBorrowOutgoingPermissionAfterNestedIgnoredWake() async throws {
        let harness = try DeferredTestHarness()
        defer { harness.registration.revoke() }
        let ticket = try harness.ticket()
        weak var capture: DeferredTestReleaseProbe?
        var cleanupSubmission: Win32DeferredCloseSubmission?
        var laterActions = 0
        @MainActor func installInitialRetry() -> Win32DeferredCloseSubmission {
            let owned = DeferredTestReleaseProbe {
                XCTAssertNil(harness.control.activeAttempt)
                XCTAssertTrue(ticket.isCurrent)
                // A nested receive with no matching pending record must leave
                // the outer retiring ticket and phase marker intact.
                harness.deliver(0)
                cleanupSubmission = harness.enqueue(ticket, phase: .retry) { _ in
                    XCTFail("An outgoing action capture cannot borrow its old continuation permission.")
                }
                XCTAssertEqual(harness.posts.messages.count, 1)
            }
            capture = owned
            return harness.enqueue(ticket, phase: .retry) { [owned] _ in
                XCTAssertEqual(deferredContinuationBlockedAttempt(harness, ticket: ticket), .busy(.buildsNotSettled))
                withExtendedLifetime(owned) {}
            }
        }
        XCTAssertEqual(installInitialRetry(), .queued)
        let oldNonce = try harness.lastNonce()

        harness.deliver(oldNonce)

        XCTAssertNil(capture)
        XCTAssertEqual(cleanupSubmission, .busy)
        XCTAssertTrue(ticket.isCurrent)
        XCTAssertEqual(harness.posts.messages.count, 1)
        XCTAssertEqual(harness.enqueue(ticket, phase: .retry) { _ in laterActions += 1 }, .queued)
        let laterNonce = try harness.lastNonce()
        XCTAssertNotEqual(oldNonce, laterNonce)
        harness.deliver(laterNonce)
        XCTAssertEqual(laterActions, 1, "The retired marker must not leak beyond its own cleanup scope.")
    }

    func testFreshReplacementFromCleanupWaitsForActionAndAuthorityPayloadRelease() async throws {
        let posts = DeferredTestPosts(results: [])
        let control = Win32CloseControl(
            postWake: { [posts] handle, nonce in posts.post(handle: handle, nonce: nonce) },
            wakeSequence: Win32CloseWakeSequence())
        let lifetime = control.beginLifetime(generation: 1)
        control.didCreate(lifetime, handle: 101)
        var events: [String] = []
        var oldOwner: DeferredContinuationReleaseAuthority? = DeferredContinuationReleaseAuthority {
            events.append("authority.release")
            XCTAssertEqual(posts.messages.count, 1)
            XCTAssertFalse(Win32DispatchScope.canDeliverWindowWake)
        }
        weak var oldAuthority = oldOwner
        let newAuthority = DeferredTestAuthority()
        var replacementRegistration: Win32CloseRegistration?
        var replacementSubmission: Win32DeferredCloseSubmission?
        var replacementActions = 0
        @MainActor func installOldAuthority() throws -> Win32CloseRegistration {
            try XCTUnwrap(control.installAuthority(try XCTUnwrap(oldOwner)))
        }
        let oldRegistration = try installOldAuthority()
        let oldTicket = try XCTUnwrap(oldRegistration.makeTicket(intentID: UUID()))
        defer {
            posts.onPost = nil
            replacementRegistration?.revoke()
            oldRegistration.revoke()
        }
        posts.onPost = { _, ordinal in
            guard ordinal == 2 else { return }
            XCTAssertEqual(events, ["action.end", "capture.begin", "capture.end", "authority.release"])
            XCTAssertNil(oldAuthority)
            events.append("replacement.post")
        }
        @MainActor func installInitialRetry() -> Win32DeferredCloseSubmission {
            let capture = DeferredTestReleaseProbe {
                events.append("capture.begin")
                XCTAssertNotNil(oldAuthority)
                guard let registration = control.installAuthority(newAuthority),
                    let ticket = registration.makeTicket(intentID: UUID())
                else {
                    XCTFail("Cleanup must be able to establish a genuinely new owner and intent.")
                    return
                }
                replacementRegistration = registration
                replacementSubmission = registration.enqueue(
                    ticket: ticket, phase: .retry,
                    onPostFailure: { _, _ in XCTFail("Unexpected replacement post failure.") },
                    action: { _ in replacementActions += 1 })
                XCTAssertEqual(posts.messages.count, 1)
                Win32DispatchScope.withWindowDispatch { control.receiveDeferredWake(nonce: 0) }
                XCTAssertEqual(posts.messages.count, 1)
                events.append("capture.end")
            }
            return oldRegistration.enqueue(
                ticket: oldTicket, phase: .retry,
                onPostFailure: { _, _ in XCTFail("Unexpected initial post failure.") },
                action: { [capture] _ in
                    XCTAssertEqual(
                        control.attemptClose(
                            expectedHandle: 101, ticket: oldTicket, participants: [],
                            preflight: {
                                control.activeAttempt?.deferUntilReady(.buildsNotSettled)
                                return false
                            },
                            destroy: { _ in
                                XCTFail("A build wait cannot enter native destruction.")
                                return .failed(1)
                            }), .busy(.buildsNotSettled))
                    oldOwner = nil
                    XCTAssertNotNil(oldAuthority)
                    withExtendedLifetime(capture) {}
                    events.append("action.end")
                })
        }
        XCTAssertEqual(installInitialRetry(), .queued)
        let oldNonce = try XCTUnwrap(posts.messages.first).nonce

        Win32DispatchScope.withWindowDispatch { control.receiveDeferredWake(nonce: oldNonce) }

        XCTAssertEqual(replacementSubmission, .queued)
        XCTAssertNil(oldOwner)
        XCTAssertNil(oldAuthority)
        XCTAssertEqual(
            events, ["action.end", "capture.begin", "capture.end", "authority.release", "replacement.post"])
        XCTAssertEqual(posts.messages.count, 2)
        XCTAssertEqual(replacementActions, 0)
        XCTAssertFalse(oldTicket.isCurrent)
        let replacementNonce = try XCTUnwrap(posts.messages.last).nonce
        XCTAssertNotEqual(oldNonce, replacementNonce)
        Win32DispatchScope.withWindowDispatch { control.receiveDeferredWake(nonce: oldNonce) }
        XCTAssertEqual(replacementActions, 0)
        Win32DispatchScope.withWindowDispatch { control.receiveDeferredWake(nonce: replacementNonce) }
        XCTAssertEqual(replacementActions, 1)
        withExtendedLifetime(newAuthority) {}
    }
}

@MainActor
private func deferredContinuationBlockedAttempt(
    _ harness: DeferredTestHarness,
    ticket: Win32CloseTicket,
    reason: Win32CloseBusyReason = .buildsNotSettled,
    observe: (@MainActor (Win32CloseAttempt?) -> Void)? = nil
) -> Win32CloseAttemptOutcome {
    harness.control.attemptClose(
        expectedHandle: harness.handle, ticket: ticket, participants: [],
        preflight: {
            let attempt = harness.control.activeAttempt
            XCTAssertNotNil(attempt)
            attempt?.deferUntilReady(reason)
            observe?(attempt)
            return false
        },
        destroy: { _ in
            XCTFail("A blocked preflight cannot enter native destruction.")
            return .failed(1)
        })
}

private enum DeferredContinuationTerminalResult: CaseIterable, Equatable {
    case vetoed, unavailable, nativeFailure, completionNotObserved, closed

    var outcome: Win32CloseAttemptOutcome {
        switch self {
        case .vetoed: return .vetoed
        case .unavailable: return .unavailable
        case .nativeFailure: return .destructionFailed(.native(5))
        case .completionNotObserved: return .destructionFailed(.destructionNotObserved)
        case .closed: return .closed
        }
    }
}

@MainActor
private final class DeferredContinuationDecisionAuthority: Win32CloseAuthority {
    let preparation: Win32CloseCommitPreparation
    private(set) var preparationCount = 0

    init(preparation: Win32CloseCommitPreparation) { self.preparation = preparation }

    func prepareCloseCommit(for attempt: Win32CloseAttempt) -> Win32CloseCommitPreparation {
        preparationCount += 1
        return preparation
    }
}

@MainActor
private final class DeferredContinuationDecisionLease: Win32CloseCommitLease {
    let decision: Win32CloseCommitDecision
    var willFinish: (@MainActor (Win32CloseAttemptOutcome) -> Void)?
    private(set) var validationCount = 0
    private(set) var finished: [Win32CloseAttemptOutcome] = []

    init(decision: Win32CloseCommitDecision) { self.decision = decision }

    func validateAndReserve() -> Win32CloseCommitDecision {
        validationCount += 1
        return decision
    }

    func finish(with outcome: Win32CloseAttemptOutcome) {
        finished.append(outcome)
        willFinish?(outcome)
    }
}

@MainActor
private final class DeferredContinuationReleaseAuthority: Win32CloseAuthority {
    private let onRelease: @MainActor () -> Void

    init(_ onRelease: @escaping @MainActor () -> Void) { self.onRelease = onRelease }

    func prepareCloseCommit(for attempt: Win32CloseAttempt) -> Win32CloseCommitPreparation {
        XCTFail("This authority's preflight is blocked before commit preparation.")
        return .unavailable
    }

    isolated deinit { onRelease() }
}
