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
