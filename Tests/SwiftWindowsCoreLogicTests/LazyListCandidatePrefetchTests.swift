import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class LazyListCandidatePrefetchTests: XCTestCase {
    func testInitialPublicViewportRetainsPrefetchAfterItsIncomingPredecessor() async throws {
        let probe = CandidatePrefetchProbe()
        let host = MountedLazyListTestHost(size: Size(width: 320, height: 80)) {
            List(probe.rows, id: \.self) { probe.makeRows($0) }.listStyle(.plain)
        }
        defer { host.close() }

        XCTAssertNotNil(host.layout())

        XCTAssertNotNil(host.find("candidate.prefetch.3"))
        XCTAssertEqual(probe.factories.filter { $0 == 3 }.count, 1)
        XCTAssertEqual(Set(probe.factories).count, probe.factories.count)
        XCTAssertLessThan(probe.factories.count, 128)
        XCTAssertTrue(probe.activations.isEmpty)
        guard case .settled = host.runtime.layoutSettlementStatus else {
            return XCTFail("Accepted prefetch still requires an ordinary completed layout")
        }
    }

    func testIncomingEmptyPredecessorsRetainTheNextPublicPrefetchRow() async throws {
        let probe = CandidatePrefetchProbe(emptyRows: [1, 2])
        let host = MountedLazyListTestHost(size: Size(width: 320, height: 20)) {
            List(probe.rows, id: \.self) { probe.makeRows($0) }.listStyle(.plain)
        }
        defer { host.close() }

        XCTAssertNotNil(host.layout())

        XCTAssertNil(host.find("candidate.prefetch.1"))
        XCTAssertNil(host.find("candidate.prefetch.2"))
        XCTAssertNotNil(host.find("candidate.prefetch.3"))
        for id in 0...3 {
            XCTAssertEqual(probe.factories.filter { $0 == id }.count, 1)
        }
        XCTAssertLessThan(probe.factories.count, 128)
        XCTAssertTrue(probe.activations.isEmpty)
        guard case .settled = host.runtime.layoutSettlementStatus else {
            return XCTFail("The empty prefix must be accepted before its following gap can settle")
        }
    }

    /// This raw adapter case proves candidate selection only, not Runtime's
    /// physical adoption or measured geometry.
    func testDiscardedOversizedPredecessorCannotRetainLaterPrefetch() async throws {
        let source = RetainedLazyListDataSource<Int, [ViewNode]>()
        defer { source.close() }
        var factories: [Int] = []
        XCTAssertTrue(
            source.replaceData([0, 1, 2, 3], id: \.self) { id in
                factories.append(id)
                return self.rawGapRows(count: id == 1 ? 3 : 1)
            })
        let adapter = try makeAdapter(source, maximumLeaves: 4)
        let viewport = try makeViewport()
        let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 16, roundLimit: 4))

        let result = adapter.prepare(viewport: viewport, protectedRoots: [], budget: budget)

        guard case .ready(let candidate) = result else { return XCTFail("Expected the bounded visible row") }
        XCTAssertEqual(factories, [0, 1, 2, 3])
        XCTAssertEqual(candidate.recordLeafCounts, [2])
        XCTAssertEqual(candidate.children.count, 2)
        XCTAssertEqual(adapter.mountedRecordCount, 0, "A candidate has not published actual rows")
        XCTAssertFalse(adapter.hasCurrentLogicalSnapshot)
    }

    func testRevokedSourceCannotUseAnEarlierCandidateAsPrefetchAuthority() async throws {
        let source = RetainedLazyListDataSource<Int, [ViewNode]>()
        defer { source.close() }
        var factories: [Int] = []
        XCTAssertTrue(
            source.replaceData([0, 1, 2, 3], id: \.self) { [weak source] id in
                factories.append(id)
                if id == 1 { source?.close() }
                return self.rawGapRows(count: 1)
            })
        let adapter = try makeAdapter(source, maximumLeaves: 16)
        let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 16, roundLimit: 4))

        let result = adapter.prepare(viewport: try makeViewport(), protectedRoots: [], budget: budget)

        guard case .obsolete = result else { return XCTFail("Revoked construction cannot publish a candidate") }
        XCTAssertEqual(factories, [0, 1])
        XCTAssertEqual(adapter.mountedRecordCount, 0)
        XCTAssertFalse(adapter.hasCurrentLogicalSnapshot)
    }

    private func rawGapRows(count: Int) -> [ViewNode] {
        (0..<count).flatMap { _ in
            let gap = ViewNode()
            gap.retainedLazyListGap = RetainedLazyListGap(
                spacing: 2, separatorThickness: 1, nextRowIsSelected: false, nextRowIsGrouped: false)
            return [gap, ViewNode()]
        }
    }

    private func makeAdapter(
        _ source: RetainedLazyListDataSource<Int, [ViewNode]>, maximumLeaves: Int
    ) throws -> RetainedLazyListRuntimeAdapter {
        try XCTUnwrap(
            RetainedLazyListRuntimeAdapter(
                provider: source, estimatedExtent: 20, prefetchExtent: 60,
                maximumMountedRecords: 8, maximumMountedLeaves: maximumLeaves, maximumProtectedRecords: 2))
    }

    private func makeViewport() throws -> RetainedLazyListRuntimeAdapter.Viewport {
        let context = try XCTUnwrap(
            RetainedLazyListMeasurementContext(
                width: 120, displayScale: 1, contentRevision: 0, environmentRevision: 0))
        return try XCTUnwrap(RetainedLazyListRuntimeAdapter.Viewport(context: context, offset: 0, extent: 20))
    }
}

@MainActor
private final class CandidatePrefetchProbe {
    let rows = Array(0..<1000)
    let emptyRows: Set<Int>
    var factories: [Int] = []
    var activations: [Int] = []

    init(emptyRows: Set<Int> = []) { self.emptyRows = emptyRows }

    func makeRows(_ id: Int) -> [AnyView] {
        factories.append(id)
        if emptyRows.contains(id) { return [] }
        return [
            AnyView(
                Button("Row \(id)") { [weak self] in self?.activations.append(id) }
                    .accessibilityIdentifier("candidate.prefetch.\(id)")
                    .frame(height: 24))
        ]
    }
}
