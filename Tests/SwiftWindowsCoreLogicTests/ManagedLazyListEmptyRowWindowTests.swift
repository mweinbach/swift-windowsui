import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// An accepted managed empty row has a real container attachment, but occupies
/// no coordinate interval. Keeping that bounded cohort must not materialize
/// cold zero metadata or displace a positive visible row.
@MainActor
final class ManagedLazyListEmptyRowWindowTests: XCTestCase {
    func testAcceptedEmptyCohortUsesHalfOpenWindowsAndAnExactEmptyViewportPoint() async throws {
        let probe = ManagedEmptyWindowProbe(rows: [0], emptyRows: [0])
        let host = MountedLazyListTestHost { managedEmptyWindowContent(probe) }
        defer { host.close() }
        XCTAssertNotNil(host.layout())
        let list = try host.list()
        let adapter = try XCTUnwrap(list.retainedLazyListAdapter)
        let activity = try XCTUnwrap(adapter.materializedRowActivities.first)
        XCTAssertEqual(adapter.mountedRecordCount, 1)
        XCTAssertTrue(activity.physical.state == .active)
        XCTAssertTrue(try XCTUnwrap(adapter.mountedNodes(for: activity.request.token)).isEmpty)
        let calls = probe.factoryCalls

        let windows: [(Double, Double, Bool)] = [
            (-1, 1, true), (-1, 2, false), (0, 0, false),
            (0, .leastNonzeroMagnitude, false), (.leastNonzeroMagnitude, 1, true), (0, 40, false),
        ]
        for (offset, extent, requiresResolution) in windows {
            let context = try XCTUnwrap(
                RetainedLazyListMeasurementContext(
                    width: list.resolvedFrame.width, displayScale: 1,
                    contentRevision: list.lazyListContentRevision,
                    environmentRevision: list.lazyListEnvironmentRevision))
            let viewport = try XCTUnwrap(
                RetainedLazyListRuntimeAdapter.Viewport(context: context, offset: offset, extent: extent))
            let plan = adapter.layoutPlan(viewport: viewport)
            XCTAssertEqual(plan.requiresResolution, requiresResolution, "offset=\(offset), extent=\(extent)")
            XCTAssertEqual(plan.contentExtent, 0)
            XCTAssertTrue(plan.placements.isEmpty)
            XCTAssertEqual(adapter.mountedRecordCount, 1, "A cached query cannot evict a physical cohort")
        }

        for _ in 0..<3 { XCTAssertNotNil(host.layout()) }
        XCTAssertEqual(probe.factoryCalls, calls, "Stable empty geometry needs no additional row factories")
        XCTAssertTrue(adapter.materializedRowActivities.first === activity)
        XCTAssertEqual(adapter.mountedRecordCount, 1)
        try host.assertCommittedDescriptor()
    }

    func testLeavingTheViewportEvictsEmptyCohortWithoutRemountingKnownZeroMetadata() async throws {
        let probe = ManagedEmptyWindowProbe(rows: Array(0..<100), emptyRows: [0])
        let host = MountedLazyListTestHost { managedEmptyWindowContent(probe) }
        defer { host.close() }
        XCTAssertNotNil(host.layout())
        let adapter = try XCTUnwrap(try host.list().retainedLazyListAdapter)
        let empty = try XCTUnwrap(adapter.materializedRowActivities.first { $0.request.sourceIndex == 0 })
        XCTAssertTrue(try XCTUnwrap(adapter.mountedNodes(for: empty.request.token)).isEmpty)
        XCTAssertEqual(probe.factoryCalls[0], 1)

        try host.scroll(to: 200)

        XCTAssertNil(adapter.mountedNodes(for: empty.request.token))
        XCTAssertNotEqual(empty.physical.state, .active)
        XCTAssertTrue(empty.logicalMembership.isDeclared)
        XCTAssertEqual(adapter.knownLeafCount(for: empty.request.token), 0)
        XCTAssertLessThanOrEqual(adapter.mountedRecordCount, 4)

        try host.scroll(to: 0)

        XCTAssertNotNil(host.find("managed.empty.window.1"))
        XCTAssertNotNil(host.find("managed.empty.window.2"))
        XCTAssertNil(adapter.mountedNodes(for: empty.request.token))
        XCTAssertEqual(probe.factoryCalls[0], 1, "Logical zero metadata does not restore physical insertion provenance")
        XCTAssertEqual(adapter.knownLeafCount(for: empty.request.token), 0)
        XCTAssertLessThanOrEqual(adapter.mountedRecordCount, 4)
        try host.assertCommittedDescriptor()
    }

    func testPositiveViewportRowsTakeCapacityBeforeAcceptedEmptyCohorts() async throws {
        let probe = ManagedEmptyWindowProbe(rows: [0, 1, 2], emptyRows: [0])
        let host = MountedLazyListTestHost { managedEmptyWindowContent(probe, records: 2) }
        defer { host.close() }
        XCTAssertNotNil(host.layout())
        let adapter = try XCTUnwrap(try host.list().retainedLazyListAdapter)
        XCTAssertEqual(adapter.logicalRecordCount, 3)
        XCTAssertEqual(adapter.mountedRecordCount, 2)
        XCTAssertEqual(adapter.materializedRowActivities.map { $0.request.sourceIndex }.sorted(), [1, 2])
        XCTAssertNotNil(host.find("managed.empty.window.1"))
        XCTAssertNotNil(host.find("managed.empty.window.2"))
        XCTAssertEqual(probe.factoryCalls[0], 1)
        let calls = probe.factoryCalls
        XCTAssertNotNil(host.layout())
        XCTAssertEqual(probe.factoryCalls, calls)
        try host.assertCommittedDescriptor()
    }

    func testAcceptedEmptyCohortTakesSpareCapacityBeforeOptionalPrefetch() async throws {
        let probe = ManagedEmptyWindowProbe(rows: Array(0..<20), emptyRows: [0])
        let host = MountedLazyListTestHost(size: Size(width: 120, height: 20)) {
            managedEmptyWindowContent(probe, records: 2, prefetch: 100)
        }
        defer { host.close() }
        XCTAssertNotNil(host.layout())
        let adapter = try XCTUnwrap(try host.list().retainedLazyListAdapter)
        XCTAssertEqual(adapter.mountedRecordCount, 2)
        XCTAssertEqual(adapter.materializedRowActivities.map { $0.request.sourceIndex }.sorted(), [0, 1])
        XCTAssertEqual(probe.factoryCalls[0], 1)
        XCTAssertEqual(probe.factoryCalls[1], 1)
        XCTAssertNil(probe.factoryCalls[2])
        let calls = probe.factoryCalls
        XCTAssertNotNil(host.layout())
        XCTAssertEqual(probe.factoryCalls, calls)
        XCTAssertEqual(adapter.mountedRecordCount, 2)
        try host.assertCommittedDescriptor()
    }

    func testLogicalDeletionRevokesAnAcceptedEmptyCohort() async throws {
        let probe = ManagedEmptyWindowProbe(rows: [0], emptyRows: [0])
        let host = MountedLazyListTestHost { managedEmptyWindowContent(probe) }
        defer { host.close() }
        XCTAssertNotNil(host.layout())
        let original = try XCTUnwrap(try host.list().retainedLazyListAdapter)
        let empty = try XCTUnwrap(original.materializedRowActivities.first)
        XCTAssertEqual(original.mountedRecordCount, 1)
        let calls = probe.factoryCalls

        probe.rows = []
        host.reload()
        XCTAssertNotNil(host.layout())

        let replacement = try XCTUnwrap(try host.list().retainedLazyListAdapter)
        XCTAssertEqual(replacement.logicalRecordCount, 0)
        XCTAssertEqual(replacement.mountedRecordCount, 0)
        XCTAssertFalse(empty.logicalMembership.isDeclared)
        XCTAssertNotEqual(empty.physical.state, .active)
        XCTAssertEqual(probe.factoryCalls, calls)
        try host.assertCommittedDescriptor()
    }
}

@MainActor
private final class ManagedEmptyWindowProbe {
    var rows: [Int]
    let emptyRows: Set<Int>
    private(set) var factoryCalls: [Int: Int] = [:]

    init(rows: [Int], emptyRows: Set<Int>) {
        self.rows = rows
        self.emptyRows = emptyRows
    }

    func row(_ row: Int) -> [AnyView] {
        factoryCalls[row, default: 0] += 1
        guard !emptyRows.contains(row) else { return [] }
        return [AnyView(Color.blue.frame(height: 20).accessibilityIdentifier("managed.empty.window.\(row)"))]
    }
}

@MainActor
private func managedEmptyWindowContent(
    _ probe: ManagedEmptyWindowProbe, records: Int = 4, prefetch: Double = 0
) -> some View {
    ManagedLazyListContent(
        probe.rows, id: \.self, estimatedExtent: 20, prefetchExtent: prefetch,
        maximumMountedRecords: records, maximumMountedLeaves: 4, maximumProtectedRecords: 1
    ) { probe.row($0) }
}
