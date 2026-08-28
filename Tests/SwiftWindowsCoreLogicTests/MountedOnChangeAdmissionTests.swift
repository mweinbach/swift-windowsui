import SwiftWindowsCore
import SwiftWindowsUI
@preconcurrency import XCTest

@testable import WinSwiftUI

@MainActor
final class MountedOnChangeAdmissionTests: XCTestCase {
    func testClosingFromFinalOwnerAdmissionHashRejectsUpdateConstruction() async throws {
        let events = MountedOnChangeAdmissionEvents()
        let coordinator = StateMountCoordinator(
            invalidate: {}, observeObject: { _ in }, updateObservedObjects: { _, _, _ in })
        defer { coordinator.close() }
        let epoch = try XCTUnwrap(coordinator.beginBuild())
        let hashing = MountedOnChangeAdmissionHashHook()
        defer {
            hashing.disarm()
            epoch.abandon()
            epoch.finishAfterCallbacks()
            XCTAssertEqual(events.commits, 0)
            XCTAssertEqual(events.deliveries, 0)
            XCTAssertEqual(coordinator.registry.liveOwnerCount, 0)
            XCTAssertEqual(coordinator.registry.retiringOwnerCount, 0)
        }
        let identity = RetainedViewIdentity(segments: [
            .explicit(.init(MountedOnChangeAdmissionKey(value: 1, hashing: hashing)))
        ])
        var seededUpdates = 0
        coordinator.stageOnChange(at: identity) { owner in
            seededUpdates += 1
            return MountedOnChangeAdmissionUpdate(owner: owner, events: events)
        }
        XCTAssertEqual(seededUpdates, 1)
        XCTAssertTrue(epoch.canAdopt)

        // The existing candidate takes one hash to resolve its owner. The
        // second hash is the final owner.isInstallationActive lookup before
        // update construction, not a payload setter or an observer callback.
        hashing.arm { coordinator.close() }
        var rejectedUpdateConstructions = 0
        coordinator.stageOnChange(at: identity) { owner in
            rejectedUpdateConstructions += 1
            return MountedOnChangeAdmissionUpdate(owner: owner, events: events)
        }

        XCTAssertEqual(hashing.firedAtHash, 2)
        XCTAssertEqual(hashing.invocations, 1)
        XCTAssertEqual(rejectedUpdateConstructions, 0, "A retired build must not enter makeUpdate")
        XCTAssertTrue(coordinator.registry.isClosed)
        XCTAssertFalse(epoch.canAdopt)
        XCTAssertFalse(epoch.canComplete)
    }

    func testSupersedingFromFinalOwnerAdmissionHashRejectsUpdateConstruction() async throws {
        let events = MountedOnChangeAdmissionEvents()
        let coordinator = StateMountCoordinator(
            invalidate: {}, observeObject: { _ in }, updateObservedObjects: { _, _, _ in })
        defer { coordinator.close() }
        let epoch = try XCTUnwrap(coordinator.beginBuild())
        let hashing = MountedOnChangeAdmissionHashHook()
        defer {
            hashing.disarm()
            epoch.abandon()
            epoch.finishAfterCallbacks()
            XCTAssertEqual(events.commits, 0)
            XCTAssertEqual(events.deliveries, 0)
            XCTAssertEqual(coordinator.registry.liveOwnerCount, 0)
            XCTAssertEqual(coordinator.registry.retiringOwnerCount, 0)
        }
        let identity = RetainedViewIdentity(segments: [
            .explicit(.init(MountedOnChangeAdmissionKey(value: 2, hashing: hashing)))
        ])
        var seededUpdates = 0
        coordinator.stageOnChange(at: identity) { owner in
            seededUpdates += 1
            return MountedOnChangeAdmissionUpdate(owner: owner, events: events)
        }
        XCTAssertEqual(seededUpdates, 1)
        XCTAssertTrue(epoch.canAdopt)

        hashing.arm { epoch.supersede() }
        var rejectedUpdateConstructions = 0
        coordinator.stageOnChange(at: identity) { owner in
            rejectedUpdateConstructions += 1
            return MountedOnChangeAdmissionUpdate(owner: owner, events: events)
        }

        XCTAssertEqual(hashing.firedAtHash, 2)
        XCTAssertEqual(hashing.invocations, 1)
        XCTAssertEqual(rejectedUpdateConstructions, 0, "A superseded build must not enter makeUpdate")
        XCTAssertFalse(coordinator.registry.isClosed, "Superseding construction must not close its host")
        XCTAssertFalse(epoch.canAdopt)
        XCTAssertFalse(epoch.canComplete)
    }
}

@MainActor
private final class MountedOnChangeAdmissionEvents {
    var commits = 0
    var deliveries = 0
}

@MainActor
private final class MountedOnChangeAdmissionUpdate: MountedOnChangeUpdate {
    let owner: StateMountOwner
    private let events: MountedOnChangeAdmissionEvents

    init(owner: StateMountOwner, events: MountedOnChangeAdmissionEvents) {
        self.owner = owner
        self.events = events
    }

    func commit() { events.commits += 1 }
    func deliver() { events.deliveries += 1 }
}

@MainActor
private final class MountedOnChangeAdmissionHashHook {
    private var action: (@MainActor () -> Void)?
    private var hashesSinceArming = 0
    private(set) var firedAtHash: Int?
    private(set) var invocations = 0

    func arm(_ action: @escaping @MainActor () -> Void) {
        hashesSinceArming = 0
        self.action = action
    }

    func disarm() { action = nil }

    func recordHash() {
        guard let action else { return }
        hashesSinceArming += 1
        guard hashesSinceArming == 2 else { return }
        self.action = nil
        firedAtHash = hashesSinceArming
        invocations += 1
        action()
    }
}

// The key is used only by these main-actor tests. Its plain Hashable witnesses
// retain a stable hash/equality value while the isolated hook records reentry.
private struct MountedOnChangeAdmissionKey: Hashable {
    let value: Int
    let hashing: MountedOnChangeAdmissionHashHook

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.value == rhs.value }

    func hash(into hasher: inout Hasher) {
        hasher.combine(value)
        MainActor.assumeIsolated { hashing.recordHash() }
    }
}
