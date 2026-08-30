@preconcurrency import XCTest

@testable import SwiftWindowsUI

@MainActor
final class RetainedBuildNativePendingWorkTests: XCTestCase {
    func testIdleReadsDoNotConsultReadinessClosures() async {
        var buildReadinessCalls = 0
        var layoutReadinessCalls = 0
        let coordinator = RetainedBuildCoordinator(
            retainedCallbacksAreSettled: {
                buildReadinessCalls += 1
                return false
            },
            layoutCallbacksAreAvailable: {
                layoutReadinessCalls += 1
                return false
            })

        for _ in 0..<8 {
            XCTAssertFalse(coordinator.hasPendingNativeWork)
        }

        XCTAssertEqual(buildReadinessCalls, 0)
        XCTAssertEqual(layoutReadinessCalls, 0)
        XCTAssertFalse(coordinator.isBuilding)
    }

    func testQueuedLayoutCallbackRemainsPendingWithoutReadingReadinessOrReleasingCaptures() async {
        var buildReadinessCalls = 0
        var layoutReadinessCalls = 0
        var layoutAvailable = false
        var deliveries = 0
        var releases = 0
        let coordinator = RetainedBuildCoordinator(
            retainedCallbacksAreSettled: {
                buildReadinessCalls += 1
                return true
            },
            layoutCallbacksAreAvailable: {
                layoutReadinessCalls += 1
                return layoutAvailable
            })
        let owner = NativePendingWorkOwner()
        var payload: NativePendingWorkCapture? = NativePendingWorkCapture { releases += 1 }
        weak var weakPayload = payload
        coordinator.scheduleAfterLayoutAndBuildsSettled(owner: owner) { [payload] in
            withExtendedLifetime(payload) {}
            deliveries += 1
        }
        payload = nil

        XCTAssertTrue(coordinator.isBuildSettled, "Build settlement does not drain a blocked layout observer")
        XCTAssertFalse(coordinator.isBuilding)
        XCTAssertNotNil(weakPayload)
        let buildCallsBeforeReads = buildReadinessCalls
        let layoutCallsBeforeReads = layoutReadinessCalls

        for _ in 0..<8 {
            XCTAssertTrue(coordinator.hasPendingNativeWork)
        }

        XCTAssertEqual(buildReadinessCalls, buildCallsBeforeReads)
        XCTAssertEqual(layoutReadinessCalls, layoutCallsBeforeReads)
        XCTAssertEqual(deliveries, 0)
        XCTAssertEqual(releases, 0)
        XCTAssertNotNil(weakPayload, "Native pending reads must not retire the queued action's captures")

        layoutAvailable = true
        coordinator.retainedCallbacksDidDrain()

        XCTAssertEqual(deliveries, 1)
        XCTAssertEqual(releases, 1)
        XCTAssertNil(weakPayload)
        let buildCallsAfterDelivery = buildReadinessCalls
        let layoutCallsAfterDelivery = layoutReadinessCalls
        for _ in 0..<8 {
            XCTAssertFalse(coordinator.hasPendingNativeWork)
        }
        XCTAssertEqual(buildReadinessCalls, buildCallsAfterDelivery)
        XCTAssertEqual(layoutReadinessCalls, layoutCallsAfterDelivery)
    }

    func testLastSettlementCallbackIsPendingUntilItsDeliveryReturns() async {
        var readinessCalls = 0
        var deliveries = 0
        let coordinator = RetainedBuildCoordinator(
            retainedCallbacksAreSettled: {
                readinessCalls += 1
                return true
            })
        let owner = NativePendingWorkOwner()

        coordinator.scheduleAfterBuildsSettled(owner: owner) {
            deliveries += 1
            // The sole slot was removed before this action. Only the active
            // delivery still prevents the coordinator from being natively idle.
            XCTAssertFalse(coordinator.isBuilding)
            XCTAssertTrue(coordinator.isBuildSettled)
            let callsBeforeReads = readinessCalls
            for _ in 0..<8 {
                XCTAssertTrue(coordinator.hasPendingNativeWork)
            }
            XCTAssertEqual(readinessCalls, callsBeforeReads)
        }

        XCTAssertEqual(deliveries, 1)
        let callsAfterDelivery = readinessCalls
        XCTAssertFalse(coordinator.hasPendingNativeWork)
        XCTAssertEqual(readinessCalls, callsAfterDelivery)
    }

    func testLastReloadIsPendingUntilItsDrainReturns() async {
        var readinessCalls = 0
        var deliveries = 0
        let coordinator = RetainedBuildCoordinator(
            retainedCallbacksAreSettled: {
                readinessCalls += 1
                return true
            })

        coordinator.scheduleReload {
            deliveries += 1
            // The sole reload has left the queue, and this action starts no
            // build or observer. The active drain itself remains pending work.
            XCTAssertFalse(coordinator.isBuilding)
            XCTAssertFalse(coordinator.isBuildSettled)
            let callsBeforeReads = readinessCalls
            for _ in 0..<8 {
                XCTAssertTrue(coordinator.hasPendingNativeWork)
            }
            XCTAssertEqual(readinessCalls, callsBeforeReads)
        }

        XCTAssertEqual(deliveries, 1)
        XCTAssertFalse(coordinator.hasPendingNativeWork)
        XCTAssertEqual(readinessCalls, 0)
    }

    func testActiveBuildIsPendingBeforeItsStartCallbackAndUntilItFinishes() async throws {
        weak var observedCoordinator: RetainedBuildCoordinator?
        var starts = 0
        var buildReadinessCalls = 0
        var layoutReadinessCalls = 0
        let coordinator = RetainedBuildCoordinator(
            onBuildStarted: {
                starts += 1
                XCTAssertTrue(observedCoordinator?.hasPendingNativeWork == true)
            },
            retainedCallbacksAreSettled: {
                buildReadinessCalls += 1
                return true
            },
            layoutCallbacksAreAvailable: {
                layoutReadinessCalls += 1
                return true
            })
        observedCoordinator = coordinator
        XCTAssertFalse(coordinator.hasPendingNativeWork)

        _ = try XCTUnwrap(coordinator.beginBuild())
        defer { if coordinator.isBuilding { coordinator.finishBuild() } }

        XCTAssertTrue(coordinator.isBuilding)
        for _ in 0..<8 {
            XCTAssertTrue(coordinator.hasPendingNativeWork)
        }
        XCTAssertEqual(starts, 1)
        XCTAssertEqual(buildReadinessCalls, 0)
        XCTAssertEqual(layoutReadinessCalls, 0)

        coordinator.finishBuild()

        XCTAssertFalse(coordinator.isBuilding)
        XCTAssertFalse(coordinator.hasPendingNativeWork)
        XCTAssertEqual(starts, 1)
        XCTAssertEqual(buildReadinessCalls, 0)
        XCTAssertEqual(layoutReadinessCalls, 0)
    }
}

@MainActor
private final class NativePendingWorkOwner {}

@MainActor
private final class NativePendingWorkCapture {
    private let onRelease: @MainActor () -> Void

    init(_ onRelease: @escaping @MainActor () -> Void) {
        self.onRelease = onRelease
    }

    isolated deinit { onRelease() }
}
