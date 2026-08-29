import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class ManagedListBuildAdmissionTests: XCTestCase {
    func testFirstLayoutBuildsManagedRowsWithoutStartingPresentation() async throws {
        let probe = ManagedListBuildAdmissionProbe()
        let host = makeHost(probe)
        defer { host.close() }
        try host.assertCommittedDescriptor()
        let adapter = try XCTUnwrap(try host.list().retainedLazyListAdapter)
        XCTAssertTrue(probe.factories.isEmpty)
        XCTAssertFalse(adapter.hasCurrentLogicalSnapshot)

        XCTAssertNotNil(host.layout())

        XCTAssertTrue(adapter.hasCurrentLogicalSnapshot)
        XCTAssertEqual(adapter.logicalRecordCount, 1_000)
        XCTAssertFalse(probe.factories.isEmpty)
        XCTAssertLessThan(probe.factories.count, 128)
        XCTAssertFalse(probe.factories.contains(300))
        XCTAssertTrue(probe.appearances.isEmpty, "A layout query must not start presentation callbacks")
        XCTAssertFalse(host.runtime.hasActiveRetainedBuild)
    }

    func testRestoredGeometryDuringLeaseReadStillRejectsTheOldVisit() async throws {
        let probe = ManagedListBuildAdmissionProbe()
        let host = makeHost(probe)
        defer { host.close() }
        let list = try host.list()
        let originalLease = try XCTUnwrap(list.retainedSubtreeBuildLease)
        let originalFrame = host.runtime.root.frame
        let lease = ManagedListBuildAdmissionLease(base: originalLease) { [weak runtime = host.runtime] in
            guard let runtime else { return }
            runtime.root.frame.size.width += 1
            runtime.root.frame = originalFrame
        }
        list.retainedSubtreeBuildLease = lease

        XCTAssertNotNil(host.layout())

        XCTAssertEqual(host.runtime.root.frame, originalFrame)
        XCTAssertTrue(probe.factories.isEmpty, "Restored dimensions do not restore the prior geometry revision")
        XCTAssertFalse(host.runtime.hasActiveRetainedBuild)
        XCTAssertNotNil(host.layout())
        XCTAssertFalse(probe.factories.isEmpty, "A new independent layout visit can use the restored geometry")
        XCTAssertTrue(probe.appearances.isEmpty)
    }

    func testBusyCoordinatorRetainsItsBuildAndDefersManagedRows() async throws {
        let probe = ManagedListBuildAdmissionProbe()
        let host = makeHost(probe)
        defer { host.close() }
        let coordinator = host.runtime.retainedBuildCoordinator
        _ = try XCTUnwrap(coordinator.beginBuild())
        defer { if coordinator.isBuilding { coordinator.finishBuild() } }

        XCTAssertNotNil(host.layout())

        XCTAssertTrue(probe.factories.isEmpty)
        XCTAssertTrue(coordinator.isBuilding, "A refused nested build must not finish the current owner")
        coordinator.finishBuild()
        XCTAssertNotNil(host.layout())
        XCTAssertFalse(probe.factories.isEmpty)
        XCTAssertFalse(coordinator.isBuilding)
        XCTAssertTrue(probe.appearances.isEmpty)
    }

    func testBuildAdmissionOverflowStaysUnavailableBeforeAnyRowFactory() async throws {
        let probe = ManagedListBuildAdmissionProbe()
        let host = makeHost(probe)
        defer { host.close() }
        host.runtime.exhaustLayoutGeometryGenerationOnNextInvalidationForTesting()

        XCTAssertNotNil(host.layout())

        XCTAssertTrue(probe.factories.isEmpty)
        XCTAssertTrue(probe.appearances.isEmpty)
        XCTAssertFalse(host.runtime.hasActiveRetainedBuild, "Rejected admission must finish its owned build")
        if case .unavailable = host.runtime.layoutSettlementStatus {
        } else {
            XCTFail("The existing build-start invalidation must exhaust, not restore, settlement evidence")
        }
    }

    private func makeHost(_ probe: ManagedListBuildAdmissionProbe) -> MountedLazyListTestHost {
        MountedLazyListTestHost(size: Size(width: 320, height: 80)) {
            List(Array(0..<1_000), id: \.self) { probe.makeRow($0) }.listStyle(.plain)
        }
    }
}

@MainActor
private final class ManagedListBuildAdmissionProbe {
    var factories: [Int] = []
    var appearances: [Int] = []

    func makeRow(_ id: Int) -> [AnyView] {
        factories.append(id)
        return [
            AnyView(
                Text("Row \(id)").frame(height: 24)
                    .onAppear { [weak self] in self?.appearances.append(id) })
        ]
    }
}

@MainActor
private final class ManagedListBuildAdmissionLease: RetainedSubtreeBuildLease {
    private let base: any RetainedSubtreeBuildLease
    private var beforeFirstSuccessfulRead: (@MainActor () -> Void)?

    init(base: any RetainedSubtreeBuildLease, beforeFirstSuccessfulRead: @escaping @MainActor () -> Void) {
        self.base = base
        self.beforeFirstSuccessfulRead = beforeFirstSuccessfulRead
    }

    var canBuild: Bool {
        let result = base.canBuild
        if result {
            let callback = beforeFirstSuccessfulRead
            beforeFirstSuccessfulRead = nil
            callback?()
        }
        return result
    }

    func beginBuild() -> (any RetainedBuildEpoch)? { base.beginBuild() }
}
