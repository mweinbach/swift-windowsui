import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI

/// These raw adapter fixtures verify only the production comparison's native
/// cache contract. Runtime separately supplies attachment and actual-pass proof.
@MainActor
final class LazyListTerminalCheckpointAdapterTests: XCTestCase {
    private typealias Adapter = RetainedLazyListRuntimeAdapter
    private typealias Source = RetainedLazyListDataSource<Int, [ViewNode]>

    func testFirstNilMeasurementsCannotBecomeAcceptedThroughAReadOnlyCheck() async throws {
        let fixture = try makeFixture()
        defer { fixture.source.close() }
        let batch = measurements(fixture)
        let token = try XCTUnwrap(batch.first?.token)
        let calls = fixture.provider.calls

        for _ in 0..<4 {
            XCTAssertFalse(fixture.adapter.matchesAcceptedMeasurements(batch, viewport: fixture.viewport))
        }

        XCTAssertNil(fixture.adapter.knownLeafCount(for: token))
        XCTAssertTrue(fixture.adapter.hasUnresolvedWork)
        XCTAssertEqual(fixture.adapter.contentExtent, 40)
        XCTAssertEqual(fixture.provider.calls, calls)
    }

    func testAcceptedExactMeasurementsMatchWithoutAnyProviderReadOrPublication() async throws {
        let fixture = try makeFixture()
        defer { fixture.source.close() }
        let batch = measurements(fixture)
        _ = try XCTUnwrap(fixture.adapter.recordMeasurements(batch, viewport: fixture.viewport))
        let token = try XCTUnwrap(batch.first?.token)
        let calls = fixture.provider.calls

        for _ in 0..<4 {
            XCTAssertTrue(fixture.adapter.matchesAcceptedMeasurements(batch, viewport: fixture.viewport))
        }

        XCTAssertEqual(fixture.adapter.knownLeafCount(for: token), 2)
        XCTAssertEqual(fixture.adapter.contentExtent, 40)
        XCTAssertEqual(fixture.adapter.mountedRecordCount, 1)
        XCTAssertEqual(fixture.adapter.mountedLeafCount, 2)
        XCTAssertFalse(fixture.adapter.hasUnresolvedWork)
        XCTAssertEqual(fixture.provider.calls, calls)
    }

    func testIncompleteDuplicateWrongNodeAndWrongLeafIndexBatchesAreRefused() async throws {
        let fixture = try makeFixture()
        defer { fixture.source.close() }
        let batch = measurements(fixture)
        _ = try XCTUnwrap(fixture.adapter.recordMeasurements(batch, viewport: fixture.viewport))
        let first = try XCTUnwrap(batch.first)
        let second = try XCTUnwrap(batch.dropFirst().first)
        let calls = fixture.provider.calls
        let malformed: [[Adapter.Measurement]] = [
            Array(batch.dropLast()),
            [first, first],
            [replacing(first, node: ViewNode()), second],
            [replacing(first, leafIndex: 2), second],
        ]

        for invalid in malformed {
            XCTAssertFalse(fixture.adapter.matchesAcceptedMeasurements(invalid, viewport: fixture.viewport))
        }

        XCTAssertTrue(fixture.adapter.matchesAcceptedMeasurements(batch, viewport: fixture.viewport))
        XCTAssertEqual(fixture.adapter.contentExtent, 40)
        XCTAssertEqual(fixture.adapter.knownLeafCount(for: first.token), 2)
        XCTAssertEqual(fixture.provider.calls, calls)
    }

    func testNonfiniteNegativeAndExactlyDifferentHeightsAreRefusedWithoutTolerance() async throws {
        let fixture = try makeFixture()
        defer { fixture.source.close() }
        let batch = measurements(fixture)
        _ = try XCTUnwrap(fixture.adapter.recordMeasurements(batch, viewport: fixture.viewport))
        let first = try XCTUnwrap(batch.first)
        let second = try XCTUnwrap(batch.dropFirst().first)
        let calls = fixture.provider.calls
        let invalidHeights: [Double] = [.nan, .infinity, -.infinity, -1, Double(10).nextUp]

        for height in invalidHeights {
            let changed = [replacing(first, extent: height), second]
            XCTAssertFalse(fixture.adapter.matchesAcceptedMeasurements(changed, viewport: fixture.viewport))
        }
        let sameTotal = [replacing(first, extent: 20), replacing(second, extent: 20)]
        XCTAssertFalse(
            fixture.adapter.matchesAcceptedMeasurements(sameTotal, viewport: fixture.viewport),
            "Equal record totals cannot hide a moved leaf boundary")

        XCTAssertTrue(fixture.adapter.matchesAcceptedMeasurements(batch, viewport: fixture.viewport))
        XCTAssertEqual(fixture.adapter.contentExtent, 40)
        XCTAssertEqual(fixture.adapter.knownLeafCount(for: first.token), 2)
        XCTAssertEqual(fixture.provider.calls, calls)
    }

    func testEveryChangedMeasurementContextIsRefusedWithoutRefreshingTheSnapshot() async throws {
        let fixture = try makeFixture()
        defer { fixture.source.close() }
        let batch = measurements(fixture)
        _ = try XCTUnwrap(fixture.adapter.recordMeasurements(batch, viewport: fixture.viewport))
        let calls = fixture.provider.calls
        let inputs: [(Double, Double, UInt64, UInt64)] = [
            (121, 1, 0, 0), (120, 2, 0, 0), (120, 1, 1, 0), (120, 1, 0, 1),
        ]

        for (width, scale, content, environment) in inputs {
            let context = try XCTUnwrap(
                RetainedLazyListMeasurementContext(
                    width: width, displayScale: scale, contentRevision: content, environmentRevision: environment))
            let viewport = try XCTUnwrap(Adapter.Viewport(context: context, offset: 0, extent: 40))
            XCTAssertFalse(fixture.adapter.matchesAcceptedMeasurements(batch, viewport: viewport))
        }

        XCTAssertFalse(fixture.adapter.hasUnresolvedWork)
        XCTAssertEqual(fixture.provider.calls, calls)
        XCTAssertTrue(fixture.adapter.matchesAcceptedMeasurements(batch, viewport: fixture.viewport))
    }

    func testAChangedViewportNeedingAbsentRowsDoesNotMutateRequiredSelection() async throws {
        let fixture = try makeFixture(values: Array(0..<1000), estimate: 20) { _ in [ViewNode()] }
        defer { fixture.source.close() }
        let batch = measurements(fixture) { _ in 20 }
        _ = try XCTUnwrap(fixture.adapter.recordMeasurements(batch, viewport: fixture.viewport))
        let viewport = try XCTUnwrap(Adapter.Viewport(context: fixture.viewport.context, offset: 40, extent: 40))
        let calls = fixture.provider.calls

        for _ in 0..<4 {
            XCTAssertFalse(fixture.adapter.matchesAcceptedMeasurements(batch, viewport: viewport))
        }

        XCTAssertFalse(fixture.adapter.hasUnresolvedWork, "A refusal must not replace the accepted selection")
        XCTAssertEqual(fixture.adapter.mountedRecordCount, 2)
        XCTAssertEqual(fixture.adapter.contentExtent, 20_000)
        XCTAssertEqual(fixture.provider.calls, calls)
        XCTAssertTrue(fixture.adapter.matchesAcceptedMeasurements(batch, viewport: fixture.viewport))
    }

    func testUnknownGapCannotBeCertifiedOrMeasuredByTheComparison() async throws {
        let fixture = try makeFixture(values: [0, 1, 2, 3], estimate: 21, offset: 42, extent: 21, rows: gapRows)
        defer { fixture.source.close() }
        let batch = measurements(fixture) { $0.leafIndex == 0 ? 1 : 20 }
        _ = try XCTUnwrap(fixture.adapter.recordMeasurements(batch, viewport: fixture.viewport))
        let token = try XCTUnwrap(batch.first?.token)
        let calls = fixture.provider.calls

        for _ in 0..<4 {
            XCTAssertFalse(fixture.adapter.matchesAcceptedMeasurements(batch, viewport: fixture.viewport))
        }

        XCTAssertNil(fixture.adapter.knownLeafCount(for: token))
        XCTAssertTrue(fixture.adapter.hasUnresolvedWork)
        XCTAssertEqual(fixture.adapter.contentExtent, 84)
        XCTAssertEqual(fixture.provider.calls, calls)
    }

    func testChangedGapBoundaryCannotRefreshItsCachedSummaryDuringTheComparison() async throws {
        let fixture = try makeFixture(values: [0, 1], estimate: 20) { _ in
            let gap = ViewNode()
            gap.retainedLazyListGap = RetainedLazyListGap(
                spacing: 0, separatorThickness: 0, nextRowIsSelected: false, nextRowIsGrouped: false)
            return [gap, ViewNode()]
        }
        defer { fixture.source.close() }
        let first = try XCTUnwrap(fixture.placements.first)
        let batch = measurements(fixture) { $0.leafIndex == 0 ? 0 : 20 }
        _ = try XCTUnwrap(fixture.adapter.recordMeasurements(batch, viewport: fixture.viewport))
        XCTAssertTrue(fixture.adapter.matchesAcceptedMeasurements(batch, viewport: fixture.viewport))
        // Both gap heights remain zero. Only the stale native summary differs;
        // a comparison that refreshes it would incorrectly accept this batch.
        first.node.retainedLazyListGap = RetainedLazyListGap(
            spacing: 0, separatorThickness: 0, nextRowIsSelected: true, nextRowIsGrouped: false)
        let calls = fixture.provider.calls

        for _ in 0..<4 {
            XCTAssertFalse(fixture.adapter.matchesAcceptedMeasurements(batch, viewport: fixture.viewport))
        }

        XCTAssertEqual(fixture.adapter.contentExtent, 40)
        XCTAssertEqual(fixture.adapter.knownLeafCount(for: first.token), 2)
        XCTAssertFalse(fixture.adapter.hasUnresolvedWork)
        XCTAssertEqual(fixture.provider.calls, calls)
    }

    func testChangedGapHeightIsRefusedEvenWhenItsBoundarySummaryIsEqual() async throws {
        let fixture = try makeFixture(values: [0, 1], estimate: 21, extent: 42, rows: gapRows)
        defer { fixture.source.close() }
        let first = try XCTUnwrap(fixture.placements.first)
        let batch = measurements(fixture) { placement in
            placement.leafIndex == 0 ? (placement.token == first.token ? 0 : 1) : 20
        }
        _ = try XCTUnwrap(fixture.adapter.recordMeasurements(batch, viewport: fixture.viewport))
        let secondGap = try XCTUnwrap(
            fixture.placements.first { $0.token != first.token && $0.leafIndex == 0 })
        secondGap.node.retainedLazyListGap = RetainedLazyListGap(
            spacing: 0, separatorThickness: 2, nextRowIsSelected: false, nextRowIsGrouped: false)
        let calls = fixture.provider.calls

        for _ in 0..<4 {
            XCTAssertFalse(fixture.adapter.matchesAcceptedMeasurements(batch, viewport: fixture.viewport))
        }

        XCTAssertEqual(fixture.adapter.contentExtent, 41)
        XCTAssertEqual(fixture.adapter.knownLeafCount(for: secondGap.token), 2)
        XCTAssertFalse(fixture.adapter.hasUnresolvedWork)
        XCTAssertEqual(fixture.provider.calls, calls)
    }

    func testExpiredLogicalDemandIsNotSilentlyDiscardedByTheComparison() async throws {
        let fixture = try makeFixture()
        defer { fixture.source.close() }
        let batch = measurements(fixture)
        _ = try XCTUnwrap(fixture.adapter.recordMeasurements(batch, viewport: fixture.viewport))
        let token = try XCTUnwrap(batch.first?.token)
        var owner: RetainedLazyListLogicalRealizationOwner? = RetainedLazyListLogicalRealizationOwner()
        let demand = try XCTUnwrap(fixture.adapter.beginLogicalRealization(of: token, owner: try XCTUnwrap(owner)))
        _ = try XCTUnwrap(fixture.adapter.recordMeasurements(batch, viewport: fixture.viewport))
        XCTAssertTrue(fixture.adapter.matchesAcceptedMeasurements(batch, viewport: fixture.viewport))
        owner = nil
        let calls = fixture.provider.calls

        for _ in 0..<4 {
            XCTAssertFalse(fixture.adapter.matchesAcceptedMeasurements(batch, viewport: fixture.viewport))
        }

        XCTAssertFalse(demand.isActive)
        XCTAssertFalse(fixture.adapter.hasUnresolvedWork)
        XCTAssertEqual(fixture.provider.calls, calls)
        fixture.adapter.endLogicalRealization(demand)
        XCTAssertTrue(fixture.adapter.matchesAcceptedMeasurements(batch, viewport: fixture.viewport))
    }

    func testChangedThenRestoredSourceCannotReviveAcceptedMeasurements() async throws {
        let fixture = try makeFixture()
        defer { fixture.source.close() }
        let batch = measurements(fixture)
        _ = try XCTUnwrap(fixture.adapter.recordMeasurements(batch, viewport: fixture.viewport))
        let generation = try XCTUnwrap(fixture.adapter.currentLogicalGeneration)
        XCTAssertTrue(fixture.source.replaceData([1], id: \.self) { _ in [ViewNode(), ViewNode()] })
        XCTAssertTrue(fixture.source.replaceData([0], id: \.self) { _ in [ViewNode(), ViewNode()] })
        let calls = fixture.provider.calls

        for _ in 0..<4 {
            XCTAssertFalse(fixture.adapter.matchesAcceptedMeasurements(batch, viewport: fixture.viewport))
        }

        XCTAssertFalse(generation.isCurrent)
        XCTAssertFalse(fixture.adapter.hasCurrentLogicalSnapshot)
        XCTAssertEqual(fixture.adapter.contentExtent, 40)
        XCTAssertEqual(fixture.adapter.mountedLeafCount, 2)
        XCTAssertEqual(fixture.provider.calls, calls)
    }

    func testPendingCandidateCannotBeCompletedOrConsumedByTheComparison() async throws {
        let fixture = try makeFixture()
        defer { fixture.source.close() }
        let batch = measurements(fixture)
        _ = try XCTUnwrap(fixture.adapter.recordMeasurements(batch, viewport: fixture.viewport))
        let context = try XCTUnwrap(
            RetainedLazyListMeasurementContext(width: 121, displayScale: 1, contentRevision: 0, environmentRevision: 0))
        let viewport = try XCTUnwrap(Adapter.Viewport(context: context, offset: 0, extent: 40))
        let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 8, roundLimit: 4))
        let prepared = fixture.adapter.prepare(viewport: viewport, protectedRoots: [], budget: budget)
        guard case .ready(let candidate) = prepared else { return XCTFail("Expected a pending replacement candidate") }
        let calls = fixture.provider.calls

        for _ in 0..<4 {
            XCTAssertFalse(fixture.adapter.matchesAcceptedMeasurements(batch, viewport: viewport))
        }

        XCTAssertEqual(candidate.children.count, 2)
        XCTAssertEqual(fixture.provider.calls, calls)
        XCTAssertTrue(fixture.adapter.complete(candidate: candidate, adoptedChildren: candidate.children))
    }

    private struct Fixture {
        let source: Source
        let provider: TerminalCheckpointProvider
        let adapter: Adapter
        let viewport: Adapter.Viewport
        let placements: [Adapter.Placement]
    }

    private func makeFixture(
        values: [Int] = [0], estimate: Double = 40, offset: Double = 0, extent: Double = 40,
        rows: @escaping @MainActor (Int) -> [ViewNode] = { _ in [ViewNode(), ViewNode()] }
    ) throws -> Fixture {
        let source = Source()
        XCTAssertTrue(source.replaceData(values, id: \.self, rowContent: rows))
        do {
            let provider = TerminalCheckpointProvider(source)
            let adapter = try XCTUnwrap(
                Adapter(
                    provider: provider, estimatedExtent: estimate, prefetchExtent: 0,
                    maximumMountedRecords: 8, maximumMountedLeaves: 16, maximumProtectedRecords: 2))
            let context = try XCTUnwrap(
                RetainedLazyListMeasurementContext(
                    width: 120, displayScale: 1, contentRevision: 0, environmentRevision: 0))
            let viewport = try XCTUnwrap(Adapter.Viewport(context: context, offset: offset, extent: extent))
            let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 8, roundLimit: 4))
            let prepared = adapter.prepare(viewport: viewport, protectedRoots: [], budget: budget)
            guard case .ready(let candidate) = prepared else { throw FixtureFailure.noCandidate }
            XCTAssertTrue(adapter.complete(candidate: candidate, adoptedChildren: candidate.children))
            let placements = adapter.layoutPlan(viewport: viewport).placements
            return Fixture(
                source: source, provider: provider, adapter: adapter, viewport: viewport, placements: placements)
        } catch {
            source.close()
            throw error
        }
    }

    private enum FixtureFailure: Error { case noCandidate }

    private func measurements(
        _ fixture: Fixture, height: @MainActor (Adapter.Placement) -> Double = { $0.leafIndex == 0 ? 10 : 30 }
    ) -> [Adapter.Measurement] {
        fixture.placements.map {
            Adapter.Measurement(token: $0.token, leafIndex: $0.leafIndex, node: $0.node, extent: height($0))
        }
    }

    private func replacing(
        _ measurement: Adapter.Measurement, node: ViewNode? = nil, leafIndex: Int? = nil, extent: Double? = nil
    ) -> Adapter.Measurement {
        Adapter.Measurement(
            token: measurement.token, leafIndex: leafIndex ?? measurement.leafIndex,
            node: node ?? measurement.node, extent: extent ?? measurement.extent)
    }

    private func gapRows(_ value: Int) -> [ViewNode] {
        let gap = ViewNode()
        gap.retainedLazyListGap = RetainedLazyListGap(
            spacing: 0, separatorThickness: 1, nextRowIsSelected: false, nextRowIsGrouped: false)
        return [gap, ViewNode()]
    }
}

@MainActor
private final class TerminalCheckpointProvider: RetainedLazyListProvider {
    typealias RowContent = [ViewNode]
    let source: RetainedLazyListDataSource<Int, [ViewNode]>
    private(set) var calls: [String] = []

    init(_ source: RetainedLazyListDataSource<Int, [ViewNode]>) { self.source = source }

    var metadata: RetainedLazyListMetadata? {
        calls.append("metadata")
        return source.metadata
    }

    func token(for key: RetainedViewIdentity.Key, occurrence: Int) -> RetainedLazyListRowToken? {
        calls.append("token")
        return source.token(for: key, occurrence: occurrence)
    }

    func request(for token: RetainedLazyListRowToken) -> RetainedLazyListRowRequest? {
        calls.append("request")
        return source.request(for: token)
    }

    func isCurrent(_ request: RetainedLazyListRowRequest) -> Bool {
        calls.append("current")
        return source.isCurrent(request)
    }

    func identityPrefix(for request: RetainedLazyListRowRequest) -> RetainedViewIdentity? {
        calls.append("identity")
        return source.identityPrefix(for: request)
    }

    func materialize(
        _ request: RetainedLazyListRowRequest, budget: RetainedLazyListWorkBudget
    ) -> RetainedLazyListMaterialization<[ViewNode]> {
        calls.append("materialize")
        return source.materialize(request, budget: budget)
    }
}
