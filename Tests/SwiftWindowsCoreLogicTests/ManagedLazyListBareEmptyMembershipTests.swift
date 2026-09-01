import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// A false builder branch returns no view at all. In particular, this fixture
/// does not install a State owner or an EmptyView to retain the logical row.
@MainActor
final class ManagedLazyListBareEmptyMembershipTests: XCTestCase {
    func testBareEmptyRowKeepsItsMembershipUntilTheFirstPhysicalDescendantIsInserted() async throws {
        let probe = BareEmptyMembershipProbe()
        let host = MountedLazyListTestHost(size: Size(width: 160, height: 40)) { bareEmptyMembershipList(probe) }
        defer { host.close() }
        host.runtime.clock = { 10 }
        XCTAssertNotNil(host.layout())
        let list = try host.list()
        let adapter = try XCTUnwrap(list.retainedLazyListAdapter)
        let original = try XCTUnwrap(adapter.materializedRowActivities.first)
        XCTAssertEqual(adapter.mountedRecordCount, 1)
        XCTAssertTrue(list.children.isEmpty)
        XCTAssertTrue(original.logicalMembership.isDeclared)
        XCTAssertTrue(original.physical.acceptedContributions.isEmpty)
        XCTAssertEqual(probe.factoryCalls, [0])

        probe.showsRows = true
        withAnimation(.linear(duration: 0.8)) { host.reload() }

        XCTAssertTrue(original.logicalMembership.isDeclared, "The next descriptor must retain the accepted empty row")
        XCTAssertEqual(probe.factoryCalls, [0], "Root declaration does not materialize the row")
        XCTAssertNotNil(host.layout())
        let row = try XCTUnwrap(host.find("bare.empty.membership.0"))
        let current = try XCTUnwrap(try host.list().retainedLazyListAdapter?.materializedRowActivities.first)
        XCTAssertTrue(current.logicalMembership === original.logicalMembership)
        let insertion = try XCTUnwrap(row.animationStates[.opacity])
        XCTAssertEqual(insertion.startTime, 10, accuracy: 0.0001)
        XCTAssertEqual(insertion.duration, 0.8, accuracy: 0.0001)
        XCTAssertEqual(insertion.startValue, 0, accuracy: 0.0001)
        XCTAssertEqual(insertion.endValue, 1, accuracy: 0.0001)
        XCTAssertEqual(host.nodes.filter { $0.animationStates[.opacity] != nil }.count, 1)
        XCTAssertEqual(probe.factoryCalls, [0, 0])
        try host.assertCommittedDescriptor()
    }

    func testAnotherEmptyDescriptorRetainsTheSameAcceptedLogicalRowWithoutAnEffectGroup() async throws {
        let probe = BareEmptyMembershipProbe()
        let host = MountedLazyListTestHost { bareEmptyMembershipList(probe) }
        defer { host.close() }
        XCTAssertNotNil(host.layout())
        let original = try XCTUnwrap(try host.list().retainedLazyListAdapter?.materializedRowActivities.first)
        XCTAssertTrue(original.physical.acceptedContributions.isEmpty)

        host.reload()

        XCTAssertTrue(original.logicalMembership.isDeclared)
        XCTAssertEqual(probe.factoryCalls, [0])
        XCTAssertNotNil(host.layout())
        let adapter = try XCTUnwrap(try host.list().retainedLazyListAdapter)
        let current = try XCTUnwrap(adapter.materializedRowActivities.first)
        XCTAssertEqual(adapter.mountedRecordCount, 1)
        XCTAssertTrue(current.logicalMembership === original.logicalMembership)
        XCTAssertTrue(current.physical.acceptedContributions.isEmpty)
        XCTAssertTrue(try host.list().children.isEmpty)
        XCTAssertEqual(probe.factoryCalls, [0, 0])
        try host.assertCommittedDescriptor()
    }

    func testDeletingAndReinsertingTheSameBareEmptyKeyCreatesANewMembership() async throws {
        let probe = BareEmptyMembershipProbe()
        let host = MountedLazyListTestHost { bareEmptyMembershipList(probe) }
        defer { host.close() }
        XCTAssertNotNil(host.layout())
        let original = try XCTUnwrap(try host.list().retainedLazyListAdapter?.materializedRowActivities.first)
        XCTAssertTrue(original.logicalMembership.isDeclared)

        probe.rows = []
        host.reload()

        XCTAssertFalse(original.logicalMembership.isDeclared)
        XCTAssertNotNil(host.layout())
        XCTAssertEqual(try host.list().retainedLazyListAdapter?.mountedRecordCount, 0)
        XCTAssertEqual(probe.factoryCalls, [0])
        probe.rows = [0]
        host.reload()
        XCTAssertNotNil(host.layout())
        let current = try XCTUnwrap(try host.list().retainedLazyListAdapter?.materializedRowActivities.first)
        XCTAssertFalse(current.logicalMembership.id === original.logicalMembership.id)
        XCTAssertTrue(current.logicalMembership.isDeclared)
        XCTAssertFalse(original.logicalMembership.isDeclared)
        XCTAssertTrue(current.physical.acceptedContributions.isEmpty)
        XCTAssertEqual(probe.factoryCalls, [0, 0])
        try host.assertCommittedDescriptor()
    }
}

@MainActor
private final class BareEmptyMembershipProbe {
    var rows = [0]
    var showsRows = false
    var factoryCalls: [Int] = []

    func record(_ row: Int) { factoryCalls.append(row) }
}

@MainActor
private func bareEmptyMembershipList(_ probe: BareEmptyMembershipProbe) -> some View {
    ManagedLazyListContent(
        probe.rows, id: \.self, estimatedExtent: 20, prefetchExtent: 0,
        maximumMountedRecords: 8, maximumMountedLeaves: 16, maximumProtectedRecords: 2
    ) { row in
        let _ = probe.record(row)
        if probe.showsRows {
            Color.blue.frame(width: 120, height: 20)
                .transition(.asymmetric(insertion: .opacity, removal: .identity))
                .accessibilityIdentifier("bare.empty.membership.\(row)")
        }
    }
}
