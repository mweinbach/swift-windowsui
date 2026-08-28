import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI

@MainActor
final class RetainedBuildSettlementTests: XCTestCase {
    func testIdleCoordinatorDeliversSynchronouslyWithoutBeginningOrSupersedingBuilds() async throws {
        let coordinator = RetainedBuildCoordinator()
        let owner = SettlementOwner()
        var events = ["before"]

        XCTAssertTrue(coordinator.isBuildSettled)
        coordinator.scheduleAfterBuildsSettled(owner: owner) {
            XCTAssertTrue(coordinator.isBuildSettled)
            XCTAssertFalse(coordinator.isBuilding)
            events.append("settled")
        }
        events.append("after")

        XCTAssertEqual(events, ["before", "settled", "after"])
        let sequence = try XCTUnwrap(coordinator.beginBuild())
        coordinator.scheduleAfterBuildsSettled(owner: owner) { events.append("after.build") }
        XCTAssertFalse(coordinator.wasSuperseded(since: sequence))
        XCTAssertFalse(coordinator.isBuildSettled)
        XCTAssertNil(coordinator.beginBuild())
        coordinator.finishBuild()
        XCTAssertEqual(events.last, "after.build")
    }

    func testActiveBuildDefersNotificationsAndCoalescesByRetainedOwnerIdentity() async throws {
        let coordinator = RetainedBuildCoordinator()
        let first = SettlementOwner()
        let second = SettlementOwner()
        var events: [String] = []
        _ = try XCTUnwrap(coordinator.beginBuild())

        coordinator.scheduleAfterBuildsSettled(owner: first) { events.append("obsolete") }
        coordinator.scheduleAfterBuildsSettled(owner: second) { events.append("second") }
        coordinator.scheduleAfterBuildsSettled(owner: first) { events.append("replacement") }
        XCTAssertTrue(events.isEmpty)

        coordinator.finishBuild()

        XCTAssertEqual(events, ["replacement", "second"])
        XCTAssertTrue(coordinator.isBuildSettled)
        coordinator.finishBuild()
        XCTAssertEqual(events, ["replacement", "second"], "Notifications are consumed once")
    }

    func testSettlementWaitsForTheEntireReloadAndDeferredWorkDrain() async throws {
        let coordinator = RetainedBuildCoordinator()
        let owner = SettlementOwner()
        let deferredOwner = SettlementOwner()
        var events: [String] = []
        _ = try XCTUnwrap(coordinator.beginBuild())
        coordinator.scheduleAfterBuildsSettled(owner: owner) {
            XCTAssertTrue(coordinator.isBuildSettled)
            events.append("settled")
        }
        coordinator.scheduleReload {
            XCTAssertFalse(coordinator.isBuildSettled)
            XCTAssertNotNil(coordinator.beginBuild())
            events.append("first")
            coordinator.finishBuild()
            XCTAssertFalse(coordinator.isBuildSettled, "Finishing one build does not finish the drain")
        }
        coordinator.scheduleWhenIdle(for: deferredOwner) {
            XCTAssertFalse(coordinator.isBuilding)
            XCTAssertFalse(coordinator.isBuildSettled, "The drain itself still owns this callback")
            events.append("deferred")
            coordinator.scheduleReload {
                XCTAssertNotNil(coordinator.beginBuild())
                events.append("nested")
                coordinator.finishBuild()
            }
        }
        coordinator.scheduleReload {
            XCTAssertNotNil(coordinator.beginBuild())
            events.append("second")
            coordinator.finishBuild()
        }

        coordinator.finishBuild()

        XCTAssertEqual(events, ["first", "deferred", "second", "nested", "settled"])
    }

    func testNotificationRegisteredFromTheLastPendingWorkWaitsUntilThatWorkReturns() async {
        let coordinator = RetainedBuildCoordinator()
        let owner = SettlementOwner()
        var events: [String] = []

        coordinator.scheduleReload {
            XCTAssertFalse(coordinator.isBuildSettled)
            events.append("work.begin")
            coordinator.scheduleAfterBuildsSettled(owner: owner) {
                XCTAssertTrue(coordinator.isBuildSettled)
                events.append("settled")
            }
            events.append("work.end")
        }

        XCTAssertEqual(events, ["work.begin", "work.end", "settled"])
    }

    func testCallbackStartingAnUnfinishedBuildDefersRemainingAndNewNotifications() async throws {
        let coordinator = RetainedBuildCoordinator()
        let first = SettlementOwner()
        let second = SettlementOwner()
        let third = SettlementOwner()
        var events: [String] = []
        _ = try XCTUnwrap(coordinator.beginBuild())
        coordinator.scheduleAfterBuildsSettled(owner: first) {
            events.append("first")
            XCTAssertNotNil(coordinator.beginBuild())
            coordinator.scheduleAfterBuildsSettled(owner: third) { events.append("third") }
        }
        coordinator.scheduleAfterBuildsSettled(owner: second) { events.append("second") }

        coordinator.finishBuild()
        XCTAssertEqual(events, ["first"])
        XCTAssertFalse(coordinator.isBuildSettled)

        coordinator.finishBuild()
        XCTAssertEqual(events, ["first", "second", "third"])
        XCTAssertTrue(coordinator.isBuildSettled)
    }

    func testCallbackReregistrationDoesNotReenterAndPreservesOtherOwnersOrder() async throws {
        let coordinator = RetainedBuildCoordinator()
        let first = SettlementOwner()
        let second = SettlementOwner()
        var events: [String] = []
        _ = try XCTUnwrap(coordinator.beginBuild())
        coordinator.scheduleAfterBuildsSettled(owner: first) {
            events.append("first.begin")
            coordinator.scheduleAfterBuildsSettled(owner: first) { events.append("obsolete") }
            coordinator.scheduleAfterBuildsSettled(owner: first) { events.append("first.again") }
            events.append("first.end")
        }
        coordinator.scheduleAfterBuildsSettled(owner: second) { events.append("second") }

        coordinator.finishBuild()

        XCTAssertEqual(events, ["first.begin", "first.end", "second"])
        coordinator.retainedCallbacksDidDrain()
        XCTAssertEqual(events, ["first.begin", "first.end", "second", "first.again"])
    }

    func testSynchronousCallbackBuildFinishesBeforeAnotherSettlementCallbackRuns() async throws {
        let coordinator = RetainedBuildCoordinator()
        let first = SettlementOwner()
        let second = SettlementOwner()
        let third = SettlementOwner()
        var events: [String] = []
        _ = try XCTUnwrap(coordinator.beginBuild())
        coordinator.scheduleAfterBuildsSettled(owner: first) {
            events.append("first.begin")
            coordinator.scheduleReload {
                XCTAssertNotNil(coordinator.beginBuild())
                events.append("build")
                coordinator.scheduleAfterBuildsSettled(owner: third) { events.append("third") }
                coordinator.finishBuild()
                events.append("build.return")
            }
            events.append("first.end")
        }
        coordinator.scheduleAfterBuildsSettled(owner: second) { events.append("second") }

        coordinator.finishBuild()

        XCTAssertEqual(events, ["first.begin", "build", "build.return", "first.end", "second"])
        coordinator.retainedCallbacksDidDrain()
        XCTAssertEqual(events, ["first.begin", "build", "build.return", "first.end", "second", "third"])
    }

    func testIdleSelfRegistrationWaitsForAnotherDrainOpportunity() async {
        let coordinator = RetainedBuildCoordinator()
        let owner = SettlementOwner()
        var deliveries = 0

        @MainActor
        func enqueue(_ remaining: Int) {
            coordinator.scheduleAfterBuildsSettled(owner: owner) {
                deliveries += 1
                if remaining > 1 { enqueue(remaining - 1) }
            }
        }

        enqueue(4)
        XCTAssertEqual(deliveries, 1)
        XCTAssertTrue(coordinator.isBuildSettled)
        for expected in 2...4 {
            coordinator.retainedCallbacksDidDrain()
            XCTAssertEqual(deliveries, expected)
        }
        coordinator.retainedCallbacksDidDrain()
        XCTAssertEqual(deliveries, 4)
    }

    func testRegistrationOwnerRemainsAliveThroughDeliveryAndIsReleasedAfterward() async throws {
        let coordinator = RetainedBuildCoordinator()
        var owner: SettlementOwner? = SettlementOwner()
        weak var weakOwner = owner
        var deliveries = 0
        _ = try XCTUnwrap(coordinator.beginBuild())
        coordinator.scheduleAfterBuildsSettled(owner: try XCTUnwrap(owner)) {
            XCTAssertNotNil(weakOwner)
            deliveries += 1
        }
        owner = nil
        XCTAssertNotNil(weakOwner, "A pending registration cannot lose or reuse its identity")

        coordinator.finishBuild()

        XCTAssertEqual(deliveries, 1)
        XCTAssertNil(weakOwner)
    }

    func testWeakTargetAndRevokedIntentCanDropDeliveryWithoutRetainingApplicationOwners() async throws {
        let coordinator = RetainedBuildCoordinator()
        let expiredOwner = SettlementOwner()
        let revokedOwner = SettlementOwner()
        var target: SettlementWakeTarget? = SettlementWakeTarget()
        weak var weakTarget = target
        var deliveries = 0
        _ = try XCTUnwrap(coordinator.beginBuild())
        coordinator.scheduleAfterBuildsSettled(owner: expiredOwner) { [weak target] in
            guard let target else { return }
            target.wakes += 1
            deliveries += 1
        }
        coordinator.scheduleAfterBuildsSettled(owner: revokedOwner) {
            guard revokedOwner.isCurrent else { return }
            deliveries += 1
        }
        target = nil
        revokedOwner.isCurrent = false

        coordinator.finishBuild()

        XCTAssertNil(weakTarget)
        XCTAssertEqual(deliveries, 0)
    }

    func testCoordinatorReleaseDropsPendingCapturesWithoutDelivering() async throws {
        var coordinator: RetainedBuildCoordinator? = RetainedBuildCoordinator()
        var owner: SettlementOwner? = SettlementOwner()
        weak var weakOwner = owner
        var payload: SettlementReleaseProbe? = SettlementReleaseProbe {}
        weak var weakPayload = payload
        var deliveries = 0
        _ = try XCTUnwrap(coordinator?.beginBuild())
        coordinator?.scheduleAfterBuildsSettled(owner: try XCTUnwrap(owner)) { [payload] in
            withExtendedLifetime(payload) {}
            deliveries += 1
        }
        owner = nil
        payload = nil

        coordinator = nil

        XCTAssertNil(weakOwner)
        XCTAssertNil(weakPayload)
        XCTAssertEqual(deliveries, 0)
    }

    func testReplacementCaptureReleaseCanReplaceTheSameOwnerWithoutLosingNewWork() async throws {
        let coordinator = RetainedBuildCoordinator()
        let owner = SettlementOwner()
        let second = SettlementOwner()
        var events: [String] = []
        var payload: SettlementReleaseProbe? = SettlementReleaseProbe { [weak coordinator] in
            events.append("release")
            coordinator?.scheduleAfterBuildsSettled(owner: owner) { events.append("reentrant.replacement") }
        }
        weak var weakPayload = payload
        _ = try XCTUnwrap(coordinator.beginBuild())
        coordinator.scheduleAfterBuildsSettled(owner: owner) { [payload] in
            withExtendedLifetime(payload) {}
            events.append("obsolete")
        }
        coordinator.scheduleAfterBuildsSettled(owner: second) { events.append("second") }
        payload = nil

        coordinator.scheduleAfterBuildsSettled(owner: owner) { events.append("superseded.replacement") }
        XCTAssertNil(weakPayload)
        XCTAssertEqual(events, ["release"])
        coordinator.finishBuild()

        XCTAssertEqual(events, ["release", "reentrant.replacement", "second"])
    }

    func testReplacementCaptureReleaseStartingABuildDefersNotificationsUntilItFinishes() async throws {
        let coordinator = RetainedBuildCoordinator()
        let mutator = SettlementOwner()
        let replaced = SettlementOwner()
        let last = SettlementOwner()
        var events: [String] = []
        var payload: SettlementReleaseProbe? = SettlementReleaseProbe { [weak coordinator] in
            events.append("release")
            XCTAssertNotNil(coordinator?.beginBuild())
        }
        weak var weakPayload = payload
        _ = try XCTUnwrap(coordinator.beginBuild())
        coordinator.scheduleAfterBuildsSettled(owner: mutator) {
            events.append("mutator.begin")
            coordinator.scheduleAfterBuildsSettled(owner: replaced) { events.append("replacement") }
            events.append("mutator.end")
        }
        coordinator.scheduleAfterBuildsSettled(owner: replaced) { [payload] in
            withExtendedLifetime(payload) {}
            events.append("obsolete")
        }
        coordinator.scheduleAfterBuildsSettled(owner: last) { events.append("last") }
        payload = nil

        coordinator.finishBuild()

        XCTAssertNil(weakPayload)
        XCTAssertEqual(events, ["mutator.begin", "release", "mutator.end"])
        XCTAssertFalse(coordinator.isBuildSettled)
        coordinator.finishBuild()
        XCTAssertEqual(events, ["mutator.begin", "release", "mutator.end", "replacement", "last"])
    }

    func testInvokedCaptureReleaseStartingABuildDelaysTheNextCallback() async throws {
        let coordinator = RetainedBuildCoordinator()
        let first = SettlementOwner()
        let second = SettlementOwner()
        var events: [String] = []
        var payload: SettlementReleaseProbe? = SettlementReleaseProbe { [weak coordinator] in
            events.append("release")
            XCTAssertNotNil(coordinator?.beginBuild())
        }
        weak var weakPayload = payload
        _ = try XCTUnwrap(coordinator.beginBuild())
        coordinator.scheduleAfterBuildsSettled(owner: first) { [payload] in
            events.append("first")
            withExtendedLifetime(payload) {}
        }
        coordinator.scheduleAfterBuildsSettled(owner: second) { events.append("second") }
        payload = nil

        coordinator.finishBuild()

        XCTAssertNil(weakPayload)
        XCTAssertEqual(events, ["first", "release"])
        XCTAssertFalse(coordinator.isBuildSettled)
        coordinator.finishBuild()
        XCTAssertEqual(events, ["first", "release", "second"])
    }

    func testInvokedRegistrationOwnerReleaseCanQueueWorkBeforeTheNextCallback() async throws {
        let coordinator = RetainedBuildCoordinator()
        var events: [String] = []
        var owner: SettlementReleaseProbe? = SettlementReleaseProbe { [weak coordinator] in
            events.append("owner.release")
            coordinator?.scheduleReload {
                XCTAssertNotNil(coordinator?.beginBuild())
                events.append("queued.build")
            }
        }
        let second = SettlementOwner()
        weak var weakOwner = owner
        _ = try XCTUnwrap(coordinator.beginBuild())
        coordinator.scheduleAfterBuildsSettled(owner: try XCTUnwrap(owner)) { events.append("first") }
        coordinator.scheduleAfterBuildsSettled(owner: second) { events.append("second") }
        owner = nil

        coordinator.finishBuild()

        XCTAssertNil(weakOwner)
        XCTAssertEqual(events, ["first", "owner.release", "queued.build"])
        coordinator.finishBuild()
        XCTAssertEqual(events, ["first", "owner.release", "queued.build", "second"])
    }

    func testRawHostRejectsSettlementCapabilityAtIdleDuringBuildAndDuringCompletion() async {
        let runtime = settlementRuntime()
        let host = ComponentHost(runtime: runtime)
        let owner = SettlementOwner()
        var attemptedPhases: [String] = []
        var deliveries = 0
        let attempt = { [weak host] (phase: String) in
            guard let host else {
                XCTFail("The raw host must survive the synchronous check")
                return
            }
            attemptedPhases.append(phase)
            XCTAssertFalse(host.isBuildSettled)
            XCTAssertFalse(host.scheduleAfterBuildsSettled(owner: owner) { deliveries += 1 })
        }
        attempt("idle")
        host.setComponents {
            attempt("compose")
            return [
                Component { _ in
                    attempt("node")
                    return settlementNode()
                }
            ]
        }
        runtime.beginLongPressReconciliation()
        host.reload(onCompleted: { attempt("completion") })
        XCTAssertFalse(attemptedPhases.contains("completion"))
        runtime.endLongPressReconciliation()

        XCTAssertEqual(attemptedPhases, ["idle", "compose", "node", "compose", "node", "completion"])
        XCTAssertEqual(deliveries, 0)
        XCTAssertFalse(host.isBuildSettled)
    }

    func testManagedHostReportsIdleAndAcceptsSynchronousSettlement() async {
        let host = ComponentHost(runtime: settlementRuntime())
        host.buildLifecycle = SettlementLifecycle()
        let owner = SettlementOwner()
        var deliveries = 0

        XCTAssertTrue(host.isBuildSettled)
        XCTAssertTrue(
            host.scheduleAfterBuildsSettled(owner: owner) {
                XCTAssertTrue(host.isBuildSettled)
                deliveries += 1
            })

        XCTAssertEqual(deliveries, 1)
    }

    func testRemovedLifecycleDropsPendingNotificationWithoutRetainingThatLifecycle() async throws {
        let runtime = settlementRuntime()
        let host = ComponentHost(runtime: runtime)
        var lifecycle: SettlementLifecycle? = SettlementLifecycle()
        weak var weakLifecycle = lifecycle
        host.buildLifecycle = lifecycle
        var deliveries = 0
        _ = try XCTUnwrap(runtime.retainedBuildCoordinator.beginBuild())
        XCTAssertTrue(host.scheduleAfterBuildsSettled(owner: SettlementOwner()) { deliveries += 1 })

        host.buildLifecycle = nil
        lifecycle = nil
        XCTAssertNil(weakLifecycle)
        runtime.retainedBuildCoordinator.finishBuild()

        XCTAssertEqual(deliveries, 0)
        XCTAssertFalse(host.isBuildSettled)
    }

    func testReplacingAndRestoringLifecycleDoesNotReviveAnOldInstallation() async throws {
        for replacementIsNil in [false, true] {
            let runtime = settlementRuntime()
            let host = ComponentHost(runtime: runtime)
            let original = SettlementLifecycle()
            host.buildLifecycle = original
            var deliveries: [String] = []
            _ = try XCTUnwrap(runtime.retainedBuildCoordinator.beginBuild())
            XCTAssertTrue(host.scheduleAfterBuildsSettled(owner: SettlementOwner()) { deliveries.append("old") })

            host.buildLifecycle = replacementIsNil ? nil : SettlementLifecycle()
            host.buildLifecycle = original
            XCTAssertTrue(host.scheduleAfterBuildsSettled(owner: SettlementOwner()) { deliveries.append("new") })
            runtime.retainedBuildCoordinator.finishBuild()

            XCTAssertEqual(deliveries, ["new"])
            XCTAssertTrue(host.isBuildSettled)
        }
    }

    func testAssigningTheSameLifecyclePreservesPendingRegistration() async throws {
        let runtime = settlementRuntime()
        let host = ComponentHost(runtime: runtime)
        let lifecycle = SettlementLifecycle()
        host.buildLifecycle = lifecycle
        var deliveries = 0
        _ = try XCTUnwrap(runtime.retainedBuildCoordinator.beginBuild())
        XCTAssertTrue(host.scheduleAfterBuildsSettled(owner: SettlementOwner()) { deliveries += 1 })

        host.buildLifecycle = lifecycle
        runtime.retainedBuildCoordinator.finishBuild()

        XCTAssertEqual(deliveries, 1)
    }

    func testPendingNotificationDoesNotKeepComponentHostAlive() async throws {
        let runtime = settlementRuntime()
        var host: ComponentHost? = ComponentHost(runtime: runtime)
        host?.buildLifecycle = SettlementLifecycle()
        weak var weakHost = host
        var owner: SettlementOwner? = SettlementOwner()
        weak var weakOwner = owner
        var deliveries = 0
        _ = try XCTUnwrap(runtime.retainedBuildCoordinator.beginBuild())
        XCTAssertEqual(host?.scheduleAfterBuildsSettled(owner: try XCTUnwrap(owner)) { deliveries += 1 }, true)
        owner = nil

        host = nil
        XCTAssertNil(weakHost)
        XCTAssertNotNil(weakOwner)
        runtime.retainedBuildCoordinator.finishBuild()

        XCTAssertNil(weakOwner)
        XCTAssertEqual(deliveries, 0)
    }

    func testEveryManagedBuildPhaseAndRuntimeCallbackTailPrecedeSettlement() async {
        let runtime = settlementRuntime()
        let host = ComponentHost(runtime: runtime)
        let lifecycle = SettlementLifecycle()
        let owner = SettlementOwner()
        var events: [String] = []
        let recordBusy = { [weak host] (event: String) in
            XCTAssertEqual(host?.isBuilding, true)
            XCTAssertEqual(host?.isBuildSettled, false)
            events.append(event)
        }
        host.buildLifecycle = lifecycle
        lifecycle.configure = { [weak host] epoch in
            recordBusy("begin")
            XCTAssertEqual(host?.scheduleAfterBuildsSettled(owner: owner) { events.append("obsolete") }, true)
            epoch.onWillAdopt = { recordBusy("prepare") }
            epoch.onCommit = { recordBusy("commit") }
            epoch.onFinish = { recordBusy("finish") }
        }
        host.onReloadCompleted = { recordBusy("host.complete") }
        runtime.beginLongPressReconciliation()
        host.setComponents {
            recordBusy("compose")
            return [
                Component { _ in
                    recordBusy("node")
                    return settlementNode()
                }
            ]
        }
        XCTAssertEqual(events, ["begin", "compose", "node", "prepare", "commit"])
        // This callback shares the runtime's existing completion queue; it
        // remains part of the drain even though it is not another build.
        runtime.afterRetainedCallbacks { [weak host] in
            XCTAssertEqual(host?.isBuildSettled, false)
            events.append("request.tail")
            XCTAssertEqual(
                host?.scheduleAfterBuildsSettled(owner: owner) {
                    XCTAssertEqual(host?.isBuildSettled, true)
                    events.append("settled")
                }, true)
        }

        runtime.endLongPressReconciliation()

        XCTAssertEqual(
            events,
            [
                "begin", "compose", "node", "prepare", "commit", "finish", "host.complete", "request.tail", "settled",
            ])
        XCTAssertTrue(host.isBuildSettled)
    }

    func testRejectedLifecycleAndSkippedUpdateStillNotifyOnlyAfterTheirAttemptReturns() async {
        for rejectsLifecycle in [false, true] {
            let host = ComponentHost(runtime: settlementRuntime())
            let lifecycle = SettlementLifecycle()
            lifecycle.rejectsBuild = rejectsLifecycle
            host.buildLifecycle = lifecycle
            let owner = SettlementOwner()
            var events: [String] = []
            host.shouldUpdate = { [weak host] in
                XCTAssertEqual(host?.isBuildSettled, false)
                events.append("shouldUpdate")
                XCTAssertEqual(
                    host?.scheduleAfterBuildsSettled(owner: owner) {
                        XCTAssertEqual(host?.isBuildSettled, true)
                        events.append("settled")
                    }, true)
                return rejectsLifecycle
            }
            host.onReloadCompleted = { XCTFail("An unadopted attempt must not complete") }

            host.reload(onCompleted: { XCTFail("An unadopted request must not complete") })

            XCTAssertEqual(events, ["shouldUpdate", "settled"])
            XCTAssertTrue(lifecycle.epochs.isEmpty)
            XCTAssertTrue(host.isBuildSettled)
        }
    }

    func testStaleQueuedRequestDoesNotCompleteOrPreventFinalSettlement() async throws {
        let runtime = settlementRuntime()
        let host = ComponentHost(runtime: runtime)
        let lifecycle = SettlementLifecycle()
        let revision = SettlementRevision()
        lifecycle.revision = revision
        host.buildLifecycle = lifecycle
        let owner = SettlementOwner()
        var events: [String] = []
        host.setContent(Component { _ in settlementNode() })
        let initialBuildCount = lifecycle.epochs.count
        runtime.beginLongPressReconciliation()
        host.reload(onCompleted: { events.append("first.complete") })
        host.reload(onCompleted: { XCTFail("The obsolete queued receipt must not complete") })
        XCTAssertTrue(host.scheduleAfterBuildsSettled(owner: owner) { events.append("settled") })
        revision.value += 1

        runtime.endLongPressReconciliation()

        XCTAssertEqual(events, ["first.complete", "settled"])
        XCTAssertEqual(lifecycle.epochs.count, initialBuildCount + 1)
        XCTAssertTrue(host.isBuildSettled)
    }

    func testQueuedRootTransactionsAndAmbientSettlementScopeRemainUnchanged() async {
        let runtime = settlementRuntime()
        let host = ComponentHost(runtime: runtime)
        let lifecycle = SettlementLifecycle()
        let owner = SettlementOwner()
        var events: [String] = []
        var snapshots: [String: SettlementTransactionSnapshot] = [:]
        var shouldRecord = false
        var buildCount = 0
        let record = { (event: String) in
            events.append(event)
            snapshots[event] = SettlementTransactionSnapshot()
        }
        host.setComponents {
            if shouldRecord {
                buildCount += 1
                record("compose\(buildCount)")
            }
            return [Component { _ in settlementNode() }]
        }
        host.buildLifecycle = lifecycle
        shouldRecord = true
        let outer = settlementTransaction(duration: 4)
        let animated = settlementTransaction(duration: 0.75)
        let explicitNil = settlementTransaction(duration: nil, disablesAnimations: true)
        let ambient = settlementTransaction(duration: 9)
        let initialScope = SettlementTransactionSnapshot()
        runtime.beginLongPressReconciliation()
        withSettlementTransaction(outer) {
            host.reload(onCompleted: {
                record("complete1")
                withSettlementTransaction(animated) {
                    host.reload(onCompleted: { record("complete2") })
                }
                withSettlementTransaction(explicitNil) {
                    host.reload(onCompleted: { record("complete3") })
                }
                withSettlementTransaction(nil) {
                    host.reload(onCompleted: { record("complete4") })
                }
            })
            XCTAssertTrue(
                host.scheduleAfterBuildsSettled(owner: owner) {
                    XCTAssertTrue(host.isBuildSettled)
                    record("settled")
                })
        }
        XCTAssertEqual(events, ["compose1"])

        withSettlementTransaction(ambient) { runtime.endLongPressReconciliation() }

        XCTAssertEqual(
            events,
            [
                "compose1", "complete1", "compose2", "complete2", "compose3", "complete3",
                "compose4", "complete4", "settled",
            ])
        XCTAssertEqual(snapshots["compose1"], SettlementTransactionSnapshot(transaction: outer))
        XCTAssertEqual(snapshots["complete1"], snapshots["compose1"])
        XCTAssertEqual(snapshots["compose2"], SettlementTransactionSnapshot(transaction: animated))
        XCTAssertEqual(snapshots["complete2"], snapshots["compose2"])
        XCTAssertEqual(snapshots["compose3"], SettlementTransactionSnapshot(transaction: explicitNil))
        XCTAssertEqual(snapshots["complete3"], snapshots["compose3"])
        XCTAssertEqual(snapshots["compose4"], SettlementTransactionSnapshot(transaction: nil))
        XCTAssertEqual(snapshots["complete4"], snapshots["compose4"])
        XCTAssertEqual(snapshots["settled"], SettlementTransactionSnapshot(transaction: ambient))
        XCTAssertEqual(SettlementTransactionSnapshot(), initialScope)
    }

    func testSettlementCallbackReloadsHostWithoutReentrantSettlementDelivery() async throws {
        let runtime = settlementRuntime()
        let host = ComponentHost(runtime: runtime)
        host.buildLifecycle = SettlementLifecycle()
        host.setContent(Component { _ in settlementNode() })
        let first = SettlementOwner()
        let second = SettlementOwner()
        var events: [String] = []
        _ = try XCTUnwrap(runtime.retainedBuildCoordinator.beginBuild())
        XCTAssertTrue(
            host.scheduleAfterBuildsSettled(owner: first) {
                events.append("first.begin")
                host.reload(onCompleted: {
                    XCTAssertFalse(host.isBuildSettled)
                    events.append("reload.complete")
                })
                XCTAssertTrue(host.isBuildSettled)
                events.append("first.end")
            })
        XCTAssertTrue(host.scheduleAfterBuildsSettled(owner: second) { events.append("second") })

        runtime.retainedBuildCoordinator.finishBuild()

        XCTAssertEqual(events, ["first.begin", "reload.complete", "first.end", "second"])
    }

    func testRuntimeReadinessHoldsNotificationsAcrossReopenedReconciliationScopes() async {
        let runtime = settlementRuntime()
        let host = ComponentHost(runtime: runtime)
        host.buildLifecycle = SettlementLifecycle()
        let owner = SettlementOwner()
        var events: [String] = []
        runtime.beginLongPressReconciliation()
        XCTAssertFalse(host.isBuildSettled)
        runtime.afterRetainedCallbacks {
            XCTAssertFalse(host.isBuildSettled)
            events.append("first.completion")
            runtime.beginLongPressReconciliation()
            runtime.afterRetainedCallbacks { events.append("second.completion") }
        }
        XCTAssertTrue(host.scheduleAfterBuildsSettled(owner: owner) { events.append("settled") })

        runtime.endLongPressReconciliation()
        XCTAssertEqual(events, ["first.completion"])
        XCTAssertFalse(host.isBuildSettled)
        runtime.endLongPressReconciliation()

        XCTAssertEqual(events, ["first.completion", "second.completion", "settled"])
        XCTAssertTrue(host.isBuildSettled)
    }

    func testRuntimeCallbackReadinessIsRecheckedBetweenSettlementCallbacks() async {
        let runtime = settlementRuntime()
        let host = ComponentHost(runtime: runtime)
        host.buildLifecycle = SettlementLifecycle()
        let first = SettlementOwner()
        let second = SettlementOwner()
        var events: [String] = []
        runtime.beginLongPressReconciliation()
        XCTAssertTrue(
            host.scheduleAfterBuildsSettled(owner: first) {
                events.append("first")
                runtime.beginLongPressReconciliation()
                runtime.afterRetainedCallbacks { events.append("terminal.tail") }
            })
        XCTAssertTrue(host.scheduleAfterBuildsSettled(owner: second) { events.append("second") })

        runtime.endLongPressReconciliation()
        XCTAssertEqual(events, ["first"])
        XCTAssertFalse(host.isBuildSettled)
        runtime.endLongPressReconciliation()

        XCTAssertEqual(events, ["first", "terminal.tail", "second"])
    }

    func testReleasedRuntimeMakesItsEscapedCoordinatorUnavailableForSettlement() async throws {
        var runtime: RetainedViewRuntime? = settlementRuntime()
        weak var weakRuntime = runtime
        let coordinator = try XCTUnwrap(runtime?.retainedBuildCoordinator)
        XCTAssertTrue(coordinator.isBuildSettled)

        runtime = nil

        XCTAssertNil(weakRuntime, "The readiness predicate must not retain the runtime")
        XCTAssertFalse(coordinator.isBuildSettled)
        var deliveries = 0
        coordinator.scheduleAfterBuildsSettled(owner: SettlementOwner()) { deliveries += 1 }
        coordinator.retainedCallbacksDidDrain()
        XCTAssertEqual(deliveries, 0)
    }

    func testManagedGeometryAndItsQueuedRootSettleOnlyAfterBothEpochsFinish() async throws {
        let runtime = settlementRuntime()
        let host = ComponentHost(runtime: runtime)
        let owner = SettlementOwner()
        let subtree = SettlementSubtreeLease()
        let lifecycle = SettlementLifecycle()
        var phase = 0
        var events: [String] = []
        let geometry = SettlementGeometry(lease: subtree)
        host.setComponents {
            if phase == 0 {
                return [Component { _ in geometry.makeNode(size: Size(width: 60, height: 40)) }]
            }
            events.append("root.compose")
            return [
                Component { _ in
                    let node = settlementNode(text: "replacement")
                    node.nodeTag = "replacement"
                    return node
                }
            ]
        }
        host.buildLifecycle = lifecycle
        let original = try XCTUnwrap(runtime.root.children.first)
        geometry.onBuild = { [weak host] in
            XCTAssertEqual(host?.isBuildSettled, false)
            events.append("geometry.body")
            XCTAssertEqual(
                host?.scheduleAfterBuildsSettled(owner: owner) {
                    XCTAssertEqual(host?.isBuildSettled, true)
                    events.append("settled")
                }, true)
            phase = 1
            host?.reload(onCompleted: { events.append("root.complete") })
            XCTAssertEqual(events, ["geometry.body"])
        }
        subtree.epoch.onAbandon = { events.append("geometry.abandon") }
        subtree.epoch.onFinish = { events.append("geometry.finish") }
        lifecycle.configure = { epoch in epoch.onFinish = { events.append("root.finish") } }
        original.frame.size = Size(width: 120, height: 80)

        _ = runtime.renderScene()

        XCTAssertEqual(
            events,
            [
                "geometry.body", "geometry.abandon", "geometry.finish", "root.compose", "root.finish",
                "root.complete", "settled",
            ])
        XCTAssertEqual(runtime.root.children.first?.text, "replacement")
        XCTAssertNil(original.parent)
        XCTAssertTrue(host.isBuildSettled)
    }

    func testManagedGeometryCleanupCanQueueCallbackWorkBeforeSettlement() async throws {
        let runtime = settlementRuntime()
        let host = ComponentHost(runtime: runtime)
        host.buildLifecycle = SettlementLifecycle()
        let owner = SettlementOwner()
        let subtree = SettlementSubtreeLease()
        let geometry = SettlementGeometry(lease: subtree)
        var events: [String] = []
        let reader = geometry.makeNode(size: Size(width: 120, height: 80))
        runtime.root.addChild(reader)
        geometry.onBuild = { [weak host] in
            events.append("geometry.body")
            XCTAssertEqual(host?.scheduleAfterBuildsSettled(owner: owner) { events.append("settled") }, true)
        }
        subtree.epoch.onFinish = { [weak host, weak runtime] in
            guard let host, let runtime else {
                XCTFail("The live geometry runtime and host must survive their cleanup")
                return
            }
            XCTAssertFalse(host.isBuildSettled)
            events.append("geometry.finish")
            runtime.afterRetainedCallbacks {
                XCTAssertFalse(host.isBuildSettled)
                events.append("terminal.tail")
            }
        }

        _ = runtime.renderScene()

        XCTAssertEqual(events, ["geometry.body", "geometry.finish", "terminal.tail", "settled"])
        XCTAssertEqual(reader.geometryReaderBuiltSize, Size(width: 120, height: 80))
        XCTAssertTrue(host.isBuildSettled)
    }

    func testSettlementDoesNotClaimDeferredGeometryLayoutHasAlreadyRendered() async throws {
        let runtime = settlementRuntime()
        let host = ComponentHost(runtime: runtime)
        let owner = SettlementOwner()
        let subtree = SettlementSubtreeLease()
        let geometry = SettlementGeometry(lease: subtree)
        let seed = Size(width: 60, height: 40)
        let resized = Size(width: 120, height: 80)
        var phase = 0
        var geometryBuilds = 0
        var events: [String] = []
        geometry.onBuild = {
            geometryBuilds += 1
            events.append("geometry.body")
        }
        host.setComponents { [weak host] in
            if phase == 1 {
                events.append("root.compose")
                _ = runtime.renderScene()
                XCTAssertEqual(geometryBuilds, 0)
                XCTAssertEqual(
                    host?.scheduleAfterBuildsSettled(owner: owner) {
                        XCTAssertEqual(host?.isBuildSettled, true)
                        XCTAssertEqual(geometryBuilds, 0)
                        events.append("settled")
                    }, true)
            }
            let size = phase == 0 ? seed : resized
            return [Component { _ in geometry.makeNode(size: size) }]
        }
        let original = try XCTUnwrap(runtime.root.children.first)
        host.buildLifecycle = SettlementLifecycle()
        original.frame.size = resized
        phase = 1

        host.reload(onCompleted: {
            _ = runtime.renderScene()
            XCTAssertEqual(geometryBuilds, 0)
            events.append("root.complete")
        })

        XCTAssertEqual(events, ["root.compose", "root.complete", "settled"])
        XCTAssertTrue(host.isBuildSettled)
        XCTAssertTrue(runtime.isDirty, "Queued idle work invalidates layout; it does not render the reader")
        _ = runtime.renderScene()
        XCTAssertEqual(events, ["root.compose", "root.complete", "settled", "geometry.body"])
        XCTAssertEqual(geometryBuilds, 1)
        XCTAssertEqual(original.geometryReaderBuiltSize, resized)
        XCTAssertTrue(host.isBuildSettled)
    }

    func testRawLeaseLessGeometryRemainsOutsideTheSettlementCapability() async {
        let runtime = settlementRuntime()
        let host = ComponentHost(runtime: runtime)
        let owner = SettlementOwner()
        let node = settlementNode()
        node.geometryReaderBuiltSize = Size(width: 60, height: 40)
        var attempts = 0
        var deliveries = 0
        node.geometryReaderBuild = { [weak host] _, size in
            attempts += 1
            XCTAssertEqual(host?.isBuildSettled, false)
            XCTAssertEqual(host?.scheduleAfterBuildsSettled(owner: owner) { deliveries += 1 }, false)
            let replacement = settlementNode()
            replacement.geometryReaderBuiltSize = size
            return [replacement]
        }
        runtime.root.addChild(node)

        _ = runtime.renderScene()

        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(deliveries, 0)
        XCTAssertFalse(host.isBuildSettled)
    }

    func testCompletionCreatedTerminalCallbackAndItsReloadFinishBeforeSettlement() async throws {
        let runtime = settlementRuntime()
        runtime.clock = { 10 }
        let host = ComponentHost(runtime: runtime)
        let owner = SettlementOwner()
        let lifecycle = SettlementLifecycle()
        var phase = 0
        var events: [String] = []
        var pressing: [Bool] = []
        host.setComponents { [weak host] in
            let candidatePhase = phase
            if candidatePhase > 0 { events.append("compose\(candidatePhase)") }
            if candidatePhase == 1 {
                XCTAssertEqual(
                    host?.scheduleAfterBuildsSettled(owner: owner) {
                        XCTAssertEqual(host?.isBuildSettled, true)
                        events.append("settled")
                    }, true)
            }
            return [
                Component { _ in
                    let node = settlementNode(text: "phase=\(candidatePhase)")
                    node.longPressGesture = RetainedLongPressGesture(
                        minimumDuration: 100,
                        onBegin: { _ in { events.append("press.cleanup") } },
                        onPressingChanged: { isPressing in
                            pressing.append(isPressing)
                            guard !isPressing else { return }
                            XCTAssertEqual(host?.isBuildSettled, false)
                            events.append("press.terminal")
                            phase = 2
                            host?.reload(onCompleted: { events.append("terminal.reload.complete") })
                        },
                        onRecognized: { XCTFail("This gesture must finish before recognition") }
                    )
                    return node
                }
            ]
        }
        _ = runtime.renderFrame()
        runtime.pointerDown(at: Point(x: 20, y: 20))
        XCTAssertEqual(pressing, [true])
        host.buildLifecycle = lifecycle
        lifecycle.configure = { epoch in
            let number = epoch.number
            epoch.onFinish = { events.append("finish\(number)") }
        }
        events.removeAll()
        phase = 1
        runtime.beginLongPressReconciliation()
        host.reload(onCompleted: {
            events.append("first.complete.begin")
            runtime.pointerUp(at: Point(x: 20, y: 20))
            events.append("first.complete.end")
        })
        XCTAssertTrue(host.isBuilding)
        XCTAssertFalse(host.isBuildSettled)
        XCTAssertEqual(events, ["compose1"])

        runtime.endLongPressReconciliation()

        XCTAssertEqual(pressing, [true, false])
        XCTAssertEqual(
            events,
            [
                "compose1", "finish1", "first.complete.begin", "first.complete.end", "press.terminal",
                "compose2", "press.cleanup", "finish2", "terminal.reload.complete", "settled",
            ])
        XCTAssertEqual(runtime.root.children.first?.text, "phase=2")
        XCTAssertTrue(host.isBuildSettled)
    }
}

@MainActor
private final class SettlementOwner {
    var isCurrent = true
}

@MainActor
private final class SettlementWakeTarget {
    var wakes = 0
}

@MainActor
private final class SettlementReleaseProbe {
    let onRelease: @MainActor () -> Void

    init(_ onRelease: @escaping @MainActor () -> Void) {
        self.onRelease = onRelease
    }

    isolated deinit { onRelease() }
}

@MainActor
private final class SettlementLifecycle: RetainedBuildLifecycle {
    var rejectsBuild = false
    var configure: ((SettlementEpoch) -> Void)?
    var revision: SettlementRevision?
    private(set) var epochs: [SettlementEpoch] = []

    func captureBuildRequest() -> (any RetainedBuildRequest)? {
        guard let revision else { return nil }
        return SettlementBuildRequest(revision: revision, captured: revision.value)
    }

    func beginBuild() -> (any RetainedBuildEpoch)? {
        guard !rejectsBuild else { return nil }
        let epoch = SettlementEpoch(number: epochs.count + 1)
        epochs.append(epoch)
        configure?(epoch)
        return epoch
    }
}

@MainActor
private final class SettlementEpoch: RetainedBuildEpoch {
    let number: Int
    var canAdopt = true
    var canComplete = true
    var onWillAdopt: (() -> Void)?
    var onCommit: (() -> Void)?
    var onAbandon: (() -> Void)?
    var onFinish: (() -> Void)?
    private var didPrepare = false

    init(number: Int) { self.number = number }

    func supersede() {
        if !didPrepare { canAdopt = false }
    }

    func willAdopt() -> Bool {
        guard canAdopt else { return false }
        didPrepare = true
        onWillAdopt?()
        return true
    }

    func commit() { onCommit?() }
    func abandon() { onAbandon?() }
    func finishAfterCallbacks() { onFinish?() }
}

@MainActor
private final class SettlementRevision {
    var value = 0
}

@MainActor
private final class SettlementBuildRequest: RetainedBuildRequest {
    let revision: SettlementRevision
    let captured: Int

    init(revision: SettlementRevision, captured: Int) {
        self.revision = revision
        self.captured = captured
    }

    var isCurrent: Bool { revision.value == captured }
}

@MainActor
private final class SettlementSubtreeLease: RetainedSubtreeBuildLease {
    var canBuild = true
    let epoch = SettlementEpoch(number: 1)

    func beginBuild() -> (any RetainedBuildEpoch)? { epoch }
}

@MainActor
private final class SettlementGeometry {
    let lease: SettlementSubtreeLease
    var onBuild: (() -> Void)?

    init(lease: SettlementSubtreeLease) { self.lease = lease }

    func makeNode(size: Size) -> ViewNode {
        let node = settlementNode(text: "geometry")
        node.frame.size = size
        node.retainedSubtreeBuildLease = lease
        node.geometryReaderBuiltSize = Size(width: 60, height: 40)
        node.geometryReaderBuild = { [self] _, slot in
            onBuild?()
            let candidate = makeNode(size: slot)
            candidate.geometryReaderBuiltSize = slot
            return [candidate]
        }
        return node
    }
}

private struct SettlementTransactionSnapshot: Equatable {
    let hasTransaction: Bool
    let duration: Double?
    let easing: AnimationEasing?
    let disablesAnimations: Bool?
    let isContinuous: Bool?
    let scrollTargetAnchor: UnitPoint?
    let tracksVelocity: Bool?
    let legacyDuration: Double?
    let legacyEasing: AnimationEasing?

    @MainActor
    init() {
        let transaction = currentTransaction
        hasTransaction = transaction != nil
        duration = transaction?.animation?.duration
        easing = transaction?.animation?.easing
        disablesAnimations = transaction?.disablesAnimations
        isContinuous = transaction?.isContinuous
        scrollTargetAnchor = transaction?.scrollTargetAnchor
        tracksVelocity = transaction?.tracksVelocity
        legacyDuration = currentAnimationTransaction?.duration
        legacyEasing = currentAnimationTransaction?.easing
    }

    init(transaction: Transaction?) {
        hasTransaction = transaction != nil
        duration = transaction?.animation?.duration
        easing = transaction?.animation?.easing
        disablesAnimations = transaction?.disablesAnimations
        isContinuous = transaction?.isContinuous
        scrollTargetAnchor = transaction?.scrollTargetAnchor
        tracksVelocity = transaction?.tracksVelocity
        legacyDuration = transaction?.disablesAnimations == true ? nil : transaction?.animation?.duration
        legacyEasing = transaction?.disablesAnimations == true ? nil : transaction?.animation?.easing
    }
}

private func settlementTransaction(duration: Double?, disablesAnimations: Bool = false) -> Transaction {
    var transaction = Transaction(animation: duration.map { .linear(duration: $0) })
    transaction.disablesAnimations = disablesAnimations
    transaction.isContinuous = true
    transaction.scrollTargetAnchor = .trailing
    transaction.tracksVelocity = true
    return transaction
}

@MainActor
private func withSettlementTransaction(_ transaction: Transaction?, _ body: () -> Void) {
    let previousTransaction = currentTransaction
    let previousAnimation = currentAnimationTransaction
    currentTransaction = transaction
    currentAnimationTransaction =
        transaction?.disablesAnimations == true ? nil : transaction?.animation.map { ($0.duration, $0.easing) }
    defer {
        currentTransaction = previousTransaction
        currentAnimationTransaction = previousAnimation
    }
    body()
}

@MainActor
private func settlementRuntime() -> RetainedViewRuntime {
    RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 320, height: 200), isHitTestVisible: false))
}

@MainActor
private func settlementNode(text: String = "value") -> ViewNode {
    let node = ViewNode(
        frame: Rect(x: 0, y: 0, width: 120, height: 80), backgroundColor: .white, text: text, isHitTestVisible: true)
    node.nodeTag = "settlement.value"
    return node
}

// Build history retires layout evidence even when the admitted work leaves the
// exact retained nodes, their geometry, and their render invalidations unchanged.
@MainActor
extension RetainedBuildSettlementTests {
    func testBuildStartedCallbackRunsOnceAfterAdmissionAndNotForRefusedNestedBuilds() async throws {
        weak var observedCoordinator: RetainedBuildCoordinator?
        var starts = 0
        let coordinator = RetainedBuildCoordinator(
            onBuildStarted: {
                starts += 1
                guard let coordinator = observedCoordinator else {
                    XCTFail("The coordinator must exist before an admitted build invokes its hook")
                    return
                }
                XCTAssertTrue(coordinator.isBuilding)
                XCTAssertFalse(coordinator.isBuildSettled)
                // Bound this probe even if a regression puts the hook before
                // admission: a wrongly admitted nested call must not recurse.
                if starts == 1 { XCTAssertNil(coordinator.beginBuild()) }
            })
        observedCoordinator = coordinator

        XCTAssertEqual(starts, 0, "Creating a coordinator is not build admission")
        let firstSequence = try XCTUnwrap(coordinator.beginBuild())
        XCTAssertEqual(starts, 1)
        XCTAssertNil(coordinator.beginBuild())
        XCTAssertEqual(starts, 1, "A refused nested build must not publish another start")
        coordinator.finishBuild()
        XCTAssertEqual(starts, 1, "Finishing a build must not republish its admission")
        XCTAssertTrue(coordinator.isBuildSettled)

        let secondSequence = try XCTUnwrap(coordinator.beginBuild())
        XCTAssertEqual(starts, 2)
        XCTAssertEqual(secondSequence, firstSequence, "Admission does not enqueue a new root request")
        coordinator.finishBuild()
        XCTAssertEqual(starts, 2)
        XCTAssertTrue(coordinator.isBuildSettled)
    }

    func testCompletedUnchangedManagedRootReloadRetiresItsPreviousLayoutReceipt() async throws {
        let fixture = makeSettlementHistoryFixture()
        defer { fixture.releaseCallbacks() }
        let runtime = fixture.runtime
        let host = fixture.host
        let lifecycle = fixture.lifecycle
        XCTAssertNotNil(runtime.resolvedLayoutFrame(of: runtime.root))
        let original = try settlementHistoryReceipt(runtime)
        let assertGeometryUnchanged = settlementHistoryGeometryWitness(fixture)
        let originalEpochCount = lifecycle.epochs.count
        let originalComposeCalls = fixture.probe.composeCalls
        let originalNodeCalls = fixture.probe.nodeCalls
        var phases: [String] = []
        lifecycle.configure = { epoch in
            XCTAssertTrue(runtime.hasActiveRetainedBuild)
            phases.append("begin")
            epoch.onWillAdopt = { phases.append("prepare") }
            epoch.onCommit = { phases.append("commit") }
            epoch.onFinish = { phases.append("finish") }
        }
        host.onReloadCompleted = { phases.append("host.complete") }

        host.reload(onCompleted: { phases.append("request.complete") })

        XCTAssertEqual(phases, ["begin", "prepare", "commit", "finish", "host.complete", "request.complete"])
        XCTAssertEqual(lifecycle.epochs.count, originalEpochCount + 1)
        XCTAssertEqual(fixture.probe.composeCalls, originalComposeCalls + 1)
        XCTAssertEqual(fixture.probe.nodeCalls, originalNodeCalls + 1)
        XCTAssertTrue(host.isBuildSettled)
        XCTAssertFalse(runtime.hasActiveRetainedBuild)
        assertGeometryUnchanged()
        assertSettlementHistoryUnsettled(runtime)
        XCTAssertFalse(runtime.isLayoutSettlementReceiptCurrent(original))

        // A separate ordinary layout may establish new proof. The completed
        // build must not have silently revived the old preflight receipt.
        let previousPass = runtime.layoutPassID
        XCTAssertNotNil(runtime.resolvedLayoutFrame(of: runtime.root))
        let refreshed = try settlementHistoryReceipt(runtime)
        XCTAssertGreaterThan(runtime.layoutPassID, previousPass)
        XCTAssertTrue(runtime.isLayoutSettlementReceiptCurrent(refreshed))
        XCTAssertFalse(runtime.isLayoutSettlementReceiptCurrent(original))
    }

    func testAbandonedManagedRootBuildRetiresReceiptWithoutChangingRetainedGeometry() async throws {
        let fixture = makeSettlementHistoryFixture()
        defer { fixture.releaseCallbacks() }
        let runtime = fixture.runtime
        let host = fixture.host
        let lifecycle = fixture.lifecycle
        let revision = SettlementRevision()
        lifecycle.revision = revision
        XCTAssertNotNil(runtime.resolvedLayoutFrame(of: runtime.root))
        let original = try settlementHistoryReceipt(runtime)
        let assertGeometryUnchanged = settlementHistoryGeometryWitness(fixture)
        let originalEpochCount = lifecycle.epochs.count
        let originalComposeCalls = fixture.probe.composeCalls
        let originalNodeCalls = fixture.probe.nodeCalls
        var phases: [String] = []
        lifecycle.configure = { epoch in
            phases.append("begin")
            epoch.onWillAdopt = {
                phases.append("prepare")
                // The captured request becomes obsolete after preparation,
                // before ComponentHost can adopt its otherwise identical node.
                revision.value += 1
            }
            epoch.onCommit = { XCTFail("An obsolete prepared request must not commit") }
            epoch.onAbandon = { phases.append("abandon") }
            epoch.onFinish = { phases.append("finish") }
        }
        host.onReloadCompleted = { XCTFail("An abandoned build must not complete") }

        host.reload(onCompleted: { XCTFail("An abandoned request must not complete") })

        XCTAssertEqual(phases, ["begin", "prepare", "abandon", "finish"])
        XCTAssertEqual(revision.value, 1)
        XCTAssertEqual(lifecycle.epochs.count, originalEpochCount + 1)
        XCTAssertEqual(fixture.probe.composeCalls, originalComposeCalls + 1)
        XCTAssertEqual(fixture.probe.nodeCalls, originalNodeCalls + 1)
        XCTAssertTrue(host.isBuildSettled)
        assertGeometryUnchanged()
        assertSettlementHistoryUnsettled(runtime)
        XCTAssertFalse(runtime.isLayoutSettlementReceiptCurrent(original))

        XCTAssertNotNil(runtime.resolvedLayoutFrame(of: runtime.root))
        XCTAssertTrue(runtime.isLayoutSettlementReceiptCurrent(try settlementHistoryReceipt(runtime)))
        XCTAssertFalse(runtime.isLayoutSettlementReceiptCurrent(original))
    }

    func testSkippedManagedRootUpdateRetiresReceiptBeforeReturningSettled() async throws {
        let fixture = makeSettlementHistoryFixture()
        defer { fixture.releaseCallbacks() }
        let runtime = fixture.runtime
        let host = fixture.host
        let lifecycle = fixture.lifecycle
        XCTAssertNotNil(runtime.resolvedLayoutFrame(of: runtime.root))
        let original = try settlementHistoryReceipt(runtime)
        let assertGeometryUnchanged = settlementHistoryGeometryWitness(fixture)
        let originalEpochCount = lifecycle.epochs.count
        let originalComposeCalls = fixture.probe.composeCalls
        let originalNodeCalls = fixture.probe.nodeCalls
        var updateChecks = 0
        host.shouldUpdate = {
            updateChecks += 1
            XCTAssertTrue(runtime.hasActiveRetainedBuild)
            return false
        }
        lifecycle.configure = { _ in XCTFail("A skipped update must not begin a lifecycle epoch") }
        host.onReloadCompleted = { XCTFail("A skipped update must not complete") }

        host.reload(onCompleted: { XCTFail("A skipped request must not complete") })

        XCTAssertEqual(updateChecks, 1)
        XCTAssertEqual(lifecycle.epochs.count, originalEpochCount)
        XCTAssertEqual(fixture.probe.composeCalls, originalComposeCalls)
        XCTAssertEqual(fixture.probe.nodeCalls, originalNodeCalls)
        XCTAssertTrue(host.isBuildSettled)
        assertGeometryUnchanged()
        assertSettlementHistoryUnsettled(runtime)
        XCTAssertFalse(runtime.isLayoutSettlementReceiptCurrent(original))

        XCTAssertNotNil(runtime.resolvedLayoutFrame(of: runtime.root))
        XCTAssertTrue(runtime.isLayoutSettlementReceiptCurrent(try settlementHistoryReceipt(runtime)))
        XCTAssertFalse(runtime.isLayoutSettlementReceiptCurrent(original))
    }

    func testRejectedManagedLifecycleRetiresReceiptWithoutConstructingAnotherTree() async throws {
        let fixture = makeSettlementHistoryFixture()
        defer { fixture.releaseCallbacks() }
        let runtime = fixture.runtime
        let host = fixture.host
        let lifecycle = fixture.lifecycle
        XCTAssertNotNil(runtime.resolvedLayoutFrame(of: runtime.root))
        let original = try settlementHistoryReceipt(runtime)
        let assertGeometryUnchanged = settlementHistoryGeometryWitness(fixture)
        let originalEpochCount = lifecycle.epochs.count
        let originalComposeCalls = fixture.probe.composeCalls
        let originalNodeCalls = fixture.probe.nodeCalls
        var updateChecks = 0
        lifecycle.rejectsBuild = true
        host.shouldUpdate = {
            updateChecks += 1
            XCTAssertTrue(runtime.hasActiveRetainedBuild)
            return true
        }
        host.onReloadCompleted = { XCTFail("A rejected lifecycle must not complete") }

        host.reload(onCompleted: { XCTFail("A rejected request must not complete") })

        XCTAssertEqual(updateChecks, 1)
        XCTAssertEqual(lifecycle.epochs.count, originalEpochCount)
        XCTAssertEqual(fixture.probe.composeCalls, originalComposeCalls)
        XCTAssertEqual(fixture.probe.nodeCalls, originalNodeCalls)
        XCTAssertTrue(host.isBuildSettled)
        assertGeometryUnchanged()
        assertSettlementHistoryUnsettled(runtime)
        XCTAssertFalse(runtime.isLayoutSettlementReceiptCurrent(original))

        XCTAssertNotNil(runtime.resolvedLayoutFrame(of: runtime.root))
        XCTAssertTrue(runtime.isLayoutSettlementReceiptCurrent(try settlementHistoryReceipt(runtime)))
        XCTAssertFalse(runtime.isLayoutSettlementReceiptCurrent(original))
    }

    func testCoordinatorOnlyBuildAdmissionRetiresReceiptWithoutAdvancingRootRequestSequence() async throws {
        let fixture = makeSettlementHistoryFixture()
        let runtime = fixture.runtime
        let coordinator = runtime.retainedBuildCoordinator
        XCTAssertNotNil(runtime.resolvedLayoutFrame(of: runtime.root))
        let original = try settlementHistoryReceipt(runtime)
        let assertFirstGeometryUnchanged = settlementHistoryGeometryWitness(fixture)
        let originalEpochCount = fixture.lifecycle.epochs.count
        let originalComposeCalls = fixture.probe.composeCalls
        let originalNodeCalls = fixture.probe.nodeCalls

        // This exercises only the runtime's coordinator admission boundary
        // shared with managed subtrees. It does not run a GeometryReader or
        // claim to cover the reader's lease, body, or reconciliation pipeline.
        let firstSequence = try XCTUnwrap(coordinator.beginBuild())
        XCTAssertTrue(runtime.hasActiveRetainedBuild)
        coordinator.finishBuild()

        XCTAssertTrue(coordinator.isBuildSettled)
        assertFirstGeometryUnchanged()
        assertSettlementHistoryUnsettled(runtime)
        XCTAssertFalse(runtime.isLayoutSettlementReceiptCurrent(original))
        XCTAssertNotNil(runtime.resolvedLayoutFrame(of: runtime.root))
        let betweenBuilds = try settlementHistoryReceipt(runtime)
        let assertSecondGeometryUnchanged = settlementHistoryGeometryWitness(fixture)

        let secondSequence = try XCTUnwrap(coordinator.beginBuild())
        XCTAssertEqual(secondSequence, firstSequence)
        XCTAssertFalse(coordinator.wasSuperseded(since: firstSequence))
        coordinator.finishBuild()

        XCTAssertTrue(coordinator.isBuildSettled)
        XCTAssertFalse(coordinator.wasSuperseded(since: firstSequence))
        XCTAssertEqual(fixture.lifecycle.epochs.count, originalEpochCount)
        XCTAssertEqual(fixture.probe.composeCalls, originalComposeCalls)
        XCTAssertEqual(fixture.probe.nodeCalls, originalNodeCalls)
        assertSecondGeometryUnchanged()
        assertSettlementHistoryUnsettled(runtime)
        XCTAssertFalse(runtime.isLayoutSettlementReceiptCurrent(betweenBuilds))
        XCTAssertFalse(runtime.isLayoutSettlementReceiptCurrent(original))
    }

    func testBuildAdmissionGeometryRevisionOverflowPrecedesAdmittedCallbacksAndStaysUnavailable() async throws {
        let fixture = makeSettlementHistoryFixture()
        defer { fixture.releaseCallbacks() }
        let runtime = fixture.runtime
        let host = fixture.host
        runtime.exhaustLayoutGeometryGenerationOnNextInvalidationForTesting()
        XCTAssertNotNil(runtime.resolvedLayoutFrame(of: runtime.root))
        let lastReceipt = try settlementHistoryReceipt(runtime)
        XCTAssertTrue(runtime.isLayoutSettlementReceiptCurrent(lastReceipt))
        let assertGeometryUnchanged = settlementHistoryGeometryWitness(fixture)
        var callouts: [String] = []
        host.shouldUpdate = {
            callouts.append("shouldUpdate")
            XCTAssertTrue(runtime.hasActiveRetainedBuild)
            // Unlike a merely busy build, exhausted proof is unavailable
            // even while the build guard is still held.
            assertSettlementHistoryUnavailable(runtime)
            return true
        }
        fixture.lifecycle.configure = { _ in
            callouts.append("lifecycle.begin")
            assertSettlementHistoryUnavailable(runtime)
        }

        host.reload()

        XCTAssertEqual(callouts, ["shouldUpdate", "lifecycle.begin"])
        XCTAssertTrue(host.isBuildSettled)
        assertGeometryUnchanged()
        assertSettlementHistoryUnavailable(runtime)
        XCTAssertFalse(runtime.isLayoutSettlementReceiptCurrent(lastReceipt))

        // Ordinary later layout and another admission cannot reset a checked
        // geometry generation that has already exhausted its scalar range.
        XCTAssertNotNil(runtime.resolvedLayoutFrame(of: runtime.root))
        assertSettlementHistoryUnavailable(runtime)
        let coordinator = runtime.retainedBuildCoordinator
        _ = try XCTUnwrap(coordinator.beginBuild())
        coordinator.finishBuild()
        assertSettlementHistoryUnavailable(runtime)
        runtime.exhaustLayoutGeometryGenerationOnNextInvalidationForTesting()
        assertSettlementHistoryUnavailable(runtime)
        XCTAssertFalse(runtime.isLayoutSettlementReceiptCurrent(lastReceipt))
    }
}

@MainActor
private final class SettlementHistoryProbe {
    var composeCalls = 0
    var nodeCalls = 0
}

@MainActor
private struct SettlementHistoryFixture {
    let runtime: RetainedViewRuntime
    let host: ComponentHost
    let lifecycle: SettlementLifecycle
    let node: ViewNode
    let probe: SettlementHistoryProbe

    func releaseCallbacks() {
        host.shouldUpdate = nil
        host.onReloadCompleted = nil
        lifecycle.configure = nil
        for epoch in lifecycle.epochs {
            epoch.onWillAdopt = nil
            epoch.onCommit = nil
            epoch.onAbandon = nil
            epoch.onFinish = nil
        }
    }
}

@MainActor
private func makeSettlementHistoryFixture() -> SettlementHistoryFixture {
    let runtime = settlementRuntime()
    let host = ComponentHost(runtime: runtime)
    let lifecycle = SettlementLifecycle()
    let node = settlementNode()
    let probe = SettlementHistoryProbe()
    host.buildLifecycle = lifecycle
    host.setComponents {
        probe.composeCalls += 1
        return [
            Component { _ in
                probe.nodeCalls += 1
                return node
            }
        ]
    }
    // Start with clean render flags, then let each test explicitly obtain its
    // layout-only receipt. Every later build returns this exact node object.
    _ = runtime.renderScene()
    XCTAssertTrue(host.isBuildSettled)
    XCTAssertTrue(runtime.dirtyFlags.isEmpty)
    XCTAssertTrue(runtime.root.subtreeDirtyFlags.isEmpty)
    XCTAssertTrue(node.subtreeDirtyFlags.isEmpty)
    XCTAssertEqual(runtime.root.children.count, 1)
    XCTAssertTrue(runtime.root.children.first === node)
    return SettlementHistoryFixture(runtime: runtime, host: host, lifecycle: lifecycle, node: node, probe: probe)
}

@MainActor
private func settlementHistoryReceipt(
    _ runtime: RetainedViewRuntime, file: StaticString = #filePath, line: UInt = #line
) throws -> RetainedLayoutSettlementReceipt {
    let receipt: RetainedLayoutSettlementReceipt?
    if case .settled(let current) = runtime.layoutSettlementStatus {
        receipt = current
    } else {
        receipt = nil
    }
    return try XCTUnwrap(receipt, "Expected an existing settled layout receipt", file: file, line: line)
}

@MainActor
private func assertSettlementHistoryUnsettled(
    _ runtime: RetainedViewRuntime, file: StaticString = #filePath, line: UInt = #line
) {
    guard case .unsettled = runtime.layoutSettlementStatus else {
        XCTFail("An admitted build must retire the previous layout proof", file: file, line: line)
        return
    }
}

@MainActor
private func assertSettlementHistoryUnavailable(
    _ runtime: RetainedViewRuntime, file: StaticString = #filePath, line: UInt = #line
) {
    guard case .unavailable = runtime.layoutSettlementStatus else {
        XCTFail("Exhausted layout proof must remain unavailable", file: file, line: line)
        return
    }
    XCTAssertFalse(runtime.canPrepareLayoutSettlement, file: file, line: line)
}

@MainActor
private func settlementHistoryGeometryWitness(
    _ fixture: SettlementHistoryFixture, file: StaticString = #filePath, line: UInt = #line
) -> @MainActor () -> Void {
    let runtime = fixture.runtime
    let root = runtime.root
    let node = fixture.node
    let rootFrame = root.frame
    let rootResolvedFrame = root.resolvedFrame
    let nodeFrame = node.frame
    let nodeResolvedFrame = node.resolvedFrame
    let runtimeDirtyFlags = runtime.dirtyFlags
    let rootDirtyFlags = root.subtreeDirtyFlags
    let nodeDirtyFlags = node.subtreeDirtyFlags
    let layoutPass = runtime.layoutPassID
    let contentRevision = runtime.contentRevision
    let sceneRebuilds = runtime.sceneRebuildCount
    let readerResolutions = runtime.geometryReaderResolveCount
    return {
        XCTAssertTrue(runtime.root === root, file: file, line: line)
        XCTAssertEqual(root.children.count, 1, file: file, line: line)
        XCTAssertTrue(root.children.first === node, file: file, line: line)
        XCTAssertTrue(node.parent === root, file: file, line: line)
        XCTAssertEqual(root.frame, rootFrame, file: file, line: line)
        XCTAssertEqual(root.resolvedFrame, rootResolvedFrame, file: file, line: line)
        XCTAssertEqual(node.frame, nodeFrame, file: file, line: line)
        XCTAssertEqual(node.resolvedFrame, nodeResolvedFrame, file: file, line: line)
        XCTAssertEqual(runtime.dirtyFlags, runtimeDirtyFlags, file: file, line: line)
        XCTAssertEqual(root.subtreeDirtyFlags, rootDirtyFlags, file: file, line: line)
        XCTAssertEqual(node.subtreeDirtyFlags, nodeDirtyFlags, file: file, line: line)
        XCTAssertEqual(runtime.layoutPassID, layoutPass, file: file, line: line)
        XCTAssertEqual(runtime.contentRevision, contentRevision, file: file, line: line)
        XCTAssertEqual(runtime.sceneRebuildCount, sceneRebuilds, file: file, line: line)
        XCTAssertEqual(runtime.geometryReaderResolveCount, readerResolutions, file: file, line: line)
    }
}

// These are raw retained-node and coordinator tests. They do not install
// State ownership or stand in for the native host's managed reader pipeline.
@MainActor
extension RetainedBuildSettlementTests {
    func testRawReaderSizeAssignmentInvalidatesAncestorsForEqualNonNilButNotNilToNil() async {
        let sizes: [Size?] = [nil, Size(width: 120, height: 80)]
        for size in sizes {
            let runtime = settlementRuntime()
            let parent = ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 100), isHitTestVisible: false)
            let node = ViewNode(frame: Rect(x: 0, y: 0, width: 120, height: 80), isHitTestVisible: false)
            node.geometryReaderBuiltSize = size
            parent.addChild(node)
            runtime.root.addChild(parent)
            _ = runtime.renderScene()
            XCTAssertTrue(runtime.dirtyFlags.isEmpty)
            for candidate in [runtime.root, parent, node] {
                XCTAssertTrue(candidate.subtreeDirtyFlags.isEmpty)
            }
            let authoredFrame = node.frame
            let resolvedFrame = node.resolvedFrame
            let parentFrame = parent.resolvedFrame
            let rootFrame = runtime.root.resolvedFrame
            let pass = runtime.layoutPassID
            let sceneCount = runtime.sceneRebuildCount

            // This is a primitive metadata assignment, with no reader body.
            // The captured value is deliberately equal to the existing size.
            node.geometryReaderBuiltSize = size

            let expectedFlags: DirtyFlags = size == nil ? [] : .layout
            XCTAssertEqual(runtime.dirtyFlags, expectedFlags)
            for candidate in [runtime.root, parent, node] {
                XCTAssertEqual(candidate.subtreeDirtyFlags, expectedFlags)
            }
            XCTAssertEqual(node.geometryReaderBuiltSize, size)
            XCTAssertEqual(node.frame, authoredFrame)
            XCTAssertEqual(node.resolvedFrame, resolvedFrame)
            XCTAssertEqual(parent.resolvedFrame, parentFrame)
            XCTAssertEqual(runtime.root.resolvedFrame, rootFrame)
            XCTAssertTrue(node.parent === parent)
            XCTAssertTrue(parent.parent === runtime.root)
            XCTAssertEqual(runtime.layoutPassID, pass)
            XCTAssertEqual(runtime.sceneRebuildCount, sceneCount)
        }
    }

    func testRawIdleDeniedReaderLeavesRenderingCleanAndDoesNotCreateBuildWork() async {
        let fixture = makeSettlementRawDeniedReader(suppressLifecycleCallbacks: false)
        let runtime = fixture.runtime

        _ = runtime.renderScene()

        XCTAssertEqual(fixture.lease.readCount, 1)
        fixture.assertNoBuilds()
        fixture.assertClean()
        XCTAssertEqual(fixture.reader.geometryReaderBuiltSize, Size(width: 60, height: 40))
        XCTAssertEqual(fixture.reader.resolvedFrame.size, Size(width: 120, height: 80))
        if case .unavailable = runtime.layoutSettlementStatus {
            // Rendering cleanly does not prove an unresolved reader's layout.
        } else {
            XCTFail("The render that denied a reader cannot supply settled layout evidence")
        }
        let coordinator = runtime.retainedBuildCoordinator
        XCTAssertTrue(coordinator.isBuildSettled)
        var settlements = 0
        coordinator.scheduleAfterBuildsSettled(owner: SettlementOwner()) { settlements += 1 }
        XCTAssertEqual(settlements, 1, "Idle denial must not leave pending coordinator work")

        // An ordinary unchanged query may inspect the unresolved reader; it
        // must not run its denied body or turn denial into a rendering retry.
        XCTAssertNotNil(runtime.resolvedLayoutFrame(of: runtime.root))
        fixture.assertNoBuilds()
        fixture.assertClean()
        XCTAssertTrue(coordinator.isBuildSettled)
        XCTAssertEqual(settlements, 1)
    }

    func testRawActiveBuildDenialStagesTheOwnedReaderWithoutQueuingAnotherBuild() async throws {
        let fixture = makeSettlementRawDeniedReader(suppressLifecycleCallbacks: true)
        let runtime = fixture.runtime
        let coordinator = runtime.retainedBuildCoordinator
        let sequence = try XCTUnwrap(coordinator.beginBuild())
        fixture.lease.onRead = { XCTAssertTrue(runtime.hasActiveRetainedBuild) }
        defer { fixture.lease.onRead = nil }

        _ = runtime.renderScene()

        XCTAssertEqual(fixture.lease.readCount, 1)
        fixture.assertNoBuilds()
        // This positive control uses the same suppressed lifecycle callbacks
        // as the stale-owner cases. Geometry denial must still stage its path.
        XCTAssertEqual(runtime.dirtyFlags, .layout)
        for node in [runtime.root, fixture.parent, fixture.reader] {
            XCTAssertEqual(node.subtreeDirtyFlags, .layout)
        }
        var settlements = 0
        coordinator.scheduleAfterBuildsSettled(owner: SettlementOwner()) { settlements += 1 }
        XCTAssertEqual(settlements, 0)

        coordinator.finishBuild()

        XCTAssertTrue(coordinator.isBuildSettled)
        XCTAssertFalse(coordinator.wasSuperseded(since: sequence))
        XCTAssertEqual(settlements, 1)
        XCTAssertEqual(fixture.lease.readCount, 1, "Finishing must not run a queued denial retry")
        fixture.assertNoBuilds()
        XCTAssertEqual(runtime.dirtyFlags, .layout)

        _ = runtime.renderScene()

        XCTAssertEqual(fixture.lease.readCount, 2)
        fixture.assertNoBuilds()
        fixture.assertClean()
        XCTAssertTrue(coordinator.isBuildSettled)
    }

    func testRawDenyingGetterCannotStageAReaderDetachedOrMovedToAnotherRuntime() async throws {
        for movesToForeignRuntime in [false, true] {
            let fixture = makeSettlementRawDeniedReader(suppressLifecycleCallbacks: true)
            let runtime = fixture.runtime
            let foreignRuntime = settlementRuntime()
            let coordinator = runtime.retainedBuildCoordinator
            _ = try XCTUnwrap(coordinator.beginBuild())
            fixture.lease.onRead = {
                XCTAssertTrue(runtime.hasActiveRetainedBuild)
                // The raw child-list operation creates only .children dirt.
                // removeFromParent() would add .all and mask illicit .layout.
                fixture.parent.setChildren([])
                if movesToForeignRuntime { foreignRuntime.root.addChild(fixture.reader) }
            }
            defer { fixture.lease.onRead = nil }

            _ = runtime.renderScene()

            XCTAssertEqual(fixture.lease.readCount, 1)
            fixture.assertNoBuilds()
            XCTAssertTrue(fixture.parent.children.isEmpty)
            XCTAssertEqual(runtime.dirtyFlags, .children)
            XCTAssertEqual(runtime.root.subtreeDirtyFlags, .children)
            XCTAssertEqual(fixture.parent.subtreeDirtyFlags, .children)
            if movesToForeignRuntime {
                XCTAssertTrue(fixture.reader.parent === foreignRuntime.root)
                XCTAssertTrue(foreignRuntime.root.children.first === fixture.reader)
            } else {
                XCTAssertNil(fixture.reader.parent)
                XCTAssertTrue(foreignRuntime.root.children.isEmpty)
            }

            coordinator.finishBuild()

            XCTAssertTrue(coordinator.isBuildSettled)
            XCTAssertEqual(fixture.lease.readCount, 1)
            fixture.assertNoBuilds()
            XCTAssertEqual(runtime.dirtyFlags, .children)
            XCTAssertEqual(foreignRuntime.geometryReaderResolveCount, 0)
        }
    }

    func testRawDenyingGetterCannotStageAfterItsLeaseIsReplacedOrItsBodyIsRemoved() async throws {
        for removesBody in [false, true] {
            let fixture = makeSettlementRawDeniedReader(suppressLifecycleCallbacks: true)
            let runtime = fixture.runtime
            let replacementLease = SettlementReaderDenialLease()
            let coordinator = runtime.retainedBuildCoordinator
            _ = try XCTUnwrap(coordinator.beginBuild())
            fixture.lease.onRead = {
                XCTAssertTrue(runtime.hasActiveRetainedBuild)
                if removesBody {
                    fixture.reader.geometryReaderBuild = nil
                } else {
                    fixture.reader.retainedSubtreeBuildLease = replacementLease
                }
                // Do not assign builtSize here: that would legitimately dirty
                // layout and hide whether the obsolete lease staged anything.
            }
            defer { fixture.lease.onRead = nil }

            _ = runtime.renderScene()

            XCTAssertEqual(fixture.lease.readCount, 1)
            XCTAssertEqual(replacementLease.readCount, 0)
            XCTAssertEqual(replacementLease.beginCount, 0)
            fixture.assertNoBuilds()
            fixture.assertClean()
            XCTAssertEqual(fixture.reader.geometryReaderBuiltSize, Size(width: 60, height: 40))
            XCTAssertTrue(fixture.reader.parent === fixture.parent)
            if removesBody {
                XCTAssertNil(fixture.reader.geometryReaderBuild)
                XCTAssertTrue(fixture.reader.retainedSubtreeBuildLease === fixture.lease)
            } else {
                XCTAssertNotNil(fixture.reader.geometryReaderBuild)
                XCTAssertTrue(fixture.reader.retainedSubtreeBuildLease === replacementLease)
            }

            coordinator.finishBuild()

            XCTAssertTrue(coordinator.isBuildSettled)
            XCTAssertEqual(fixture.lease.readCount, 1)
            XCTAssertEqual(replacementLease.readCount, 0)
            fixture.assertNoBuilds()
            fixture.assertClean()
        }
    }
}

@MainActor
private final class SettlementReaderDenialLease: RetainedSubtreeBuildLease {
    var onRead: (() -> Void)?
    private(set) var readCount = 0
    private(set) var beginCount = 0

    var canBuild: Bool {
        readCount += 1
        let callback = onRead
        onRead = nil
        callback?()
        return false
    }

    func beginBuild() -> (any RetainedBuildEpoch)? {
        beginCount += 1
        return nil
    }
}

@MainActor
private final class SettlementReaderDenialProbe {
    var bodyCalls = 0
}

@MainActor
private struct SettlementRawDeniedReader {
    let runtime: RetainedViewRuntime
    let parent: ViewNode
    let reader: ViewNode
    let lease: SettlementReaderDenialLease
    let probe: SettlementReaderDenialProbe

    func assertNoBuilds(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(lease.beginCount, 0, file: file, line: line)
        XCTAssertEqual(probe.bodyCalls, 0, file: file, line: line)
        XCTAssertEqual(runtime.geometryReaderResolveCount, 0, file: file, line: line)
    }

    func assertClean(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(runtime.dirtyFlags.isEmpty, file: file, line: line)
        for node in [runtime.root, parent, reader] {
            XCTAssertTrue(node.subtreeDirtyFlags.isEmpty, file: file, line: line)
        }
    }
}

@MainActor
private func makeSettlementRawDeniedReader(suppressLifecycleCallbacks: Bool) -> SettlementRawDeniedReader {
    let runtime = settlementRuntime()
    let parent = ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 100), isHitTestVisible: false)
    let reader = ViewNode(frame: Rect(x: 0, y: 0, width: 120, height: 80), isHitTestVisible: false)
    let lease = SettlementReaderDenialLease()
    let probe = SettlementReaderDenialProbe()
    reader.geometryReaderBuiltSize = Size(width: 60, height: 40)
    reader.retainedSubtreeBuildLease = lease
    reader.geometryReaderBuild = { _, _ in
        probe.bodyCalls += 1
        return []
    }
    parent.addChild(reader)
    runtime.root.addChild(parent)
    if suppressLifecycleCallbacks {
        // A raw isolation control: active-build rendering otherwise stages an
        // unrelated global lifecycle follow-up. Geometry resolution remains on.
        runtime.stopRenderLifecycleCallbacks()
    }
    return SettlementRawDeniedReader(runtime: runtime, parent: parent, reader: reader, lease: lease, probe: probe)
}
