import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI

/// These raw adapter tests establish construction order, cached-coordinate
/// planning, and ordinary probe retirement. Their explicit measurement batches
/// do not establish Runtime layout, scrolling, or an end-to-end round budget.
/// The unchanged public pending-replacement tests supply those separate gates.
@MainActor
final class LazyListUIATargetRelativePlanTests: XCTestCase {
    private typealias Adapter = RetainedLazyListRuntimeAdapter
    private typealias Source = RetainedLazyListDataSource<Int, [ViewNode]>

    func testDownwardShrinkKeepsActualFutureRowsAndRetiresSlackWithTheProbe() async throws {
        let fixture = try makeFixture(hasGaps: true) { (295...300).contains($0) ? 10 : 20 }
        defer { fixture.source.close() }
        let request = try beginHint(fixture, target: 300)
        let originalGeneration = fixture.adapter.currentLogicalGeneration
        let calls = fixture.probe.factories.count
        let shared = try budget(128)
        let candidate = try ready(fixture, budget: shared)

        // The real future window is first; measurement slack follows nearest
        // first, and exactly one boundary probe follows that complete prefix.
        XCTAssertEqual(Array(fixture.probe.factories.dropFirst(calls)), [300, 299, 298, 297, 296, 295])
        XCTAssertEqual(rowIDs(candidate.children), Array(0...4) + Array(295...300))
        XCTAssertFalse(fixture.probe.factories.contains(294))
        XCTAssertTrue(fixture.adapter.complete(candidate: candidate, adoptedChildren: candidate.children))
        XCTAssertEqual(readiness(fixture, request.hint), .awaitingProbeRetirement)
        _ = try XCTUnwrap(fixture.adapter.recordMeasurements(measurements(fixture), viewport: fixture.viewport))
        let target = try XCTUnwrap(fixture.adapter.logicalBounds(for: request.token))
        XCTAssertEqual(target.origin, 5_960)
        XCTAssertEqual(target.extent, 10)
        XCTAssertNil(fixture.adapter.knownLeafCount(for: try token(295, in: fixture)))
        let acceptedFactories = fixture.probe.factories

        let retirement = try ready(fixture, budget: shared)

        XCTAssertEqual(rowIDs(retirement.children), Array(0...4) + Array(297...300))
        XCTAssertEqual(fixture.probe.factories, acceptedFactories)
        XCTAssertTrue(fixture.adapter.complete(candidate: retirement, adoptedChildren: retirement.children))
        XCTAssertNil(fixture.adapter.mountedNodes(for: try token(295, in: fixture)))
        XCTAssertNil(fixture.adapter.mountedNodes(for: try token(296, in: fixture)))
        XCTAssertEqual(readiness(fixture, request.hint), .measurementOnly)
        XCTAssertTrue(request.hint.isCurrent)
        XCTAssertEqual(fixture.adapter.currentLogicalGeneration, originalGeneration)
        XCTAssertEqual(shared.remainingElements, 122)
        XCTAssertEqual(shared.remainingRounds, 4, "Raw preparation must not debit or refund Runtime rounds")
        XCTAssertTrue(fixture.adapter.hasUnresolvedWork, "The hint cannot publish settlement")
    }

    func testUpwardShrinkUsesTrailingSlackAfterTheRealFutureWindow() async throws {
        let fixture = try makeFixture(offset: 12_000) { (100...104).contains($0) ? 10 : 20 }
        defer { fixture.source.close() }
        let request = try beginHint(fixture, target: 100)
        let calls = fixture.probe.factories.count
        let shared = try budget(128)
        let candidate = try ready(fixture, budget: shared)

        XCTAssertEqual(Array(fixture.probe.factories.dropFirst(calls)), [100, 101, 102, 103, 104])
        XCTAssertFalse(fixture.probe.factories.contains(99))
        XCTAssertFalse(fixture.probe.factories.contains(105))
        XCTAssertTrue(fixture.adapter.complete(candidate: candidate, adoptedChildren: candidate.children))
        XCTAssertEqual(readiness(fixture, request.hint), .awaitingPreparation)
        _ = try XCTUnwrap(fixture.adapter.recordMeasurements(measurements(fixture), viewport: fixture.viewport))
        let target = try XCTUnwrap(fixture.adapter.logicalBounds(for: request.token))
        XCTAssertEqual(target.origin, 2_000)
        XCTAssertEqual(target.extent, 10)
        let measuredCalls = fixture.probe.factories.count

        let retirement = try ready(fixture, budget: shared)

        XCTAssertEqual(rowIDs(retirement.children).filter { $0 < 500 }, [100, 101, 102, 103])
        XCTAssertTrue(fixture.probe.factories.dropFirst(measuredCalls).allSatisfy { $0 > 500 })
        XCTAssertTrue(fixture.adapter.complete(candidate: retirement, adoptedChildren: retirement.children))
        XCTAssertEqual(readiness(fixture, request.hint), .measurementOnly)
        XCTAssertTrue(request.hint.isCurrent)
        XCTAssertEqual(shared.remainingRounds, 4)
        XCTAssertLessThanOrEqual(fixture.adapter.mountedRecordCount, 16)
    }

    func testRealFutureRowsPrecedeSlackUnderARecordOrLeafCap() async throws {
        for limits in [(records: 4, leaves: 8), (records: 16, leaves: 8)] {
            let fixture = try makeFixture(records: limits.records, leaves: limits.leaves, hasGaps: true)
            defer { fixture.source.close() }
            let request = try beginHint(fixture, target: 300)
            let calls = fixture.probe.factories.count
            let shared = try budget(128)
            let candidate = try ready(fixture, budget: shared)

            XCTAssertEqual(Array(fixture.probe.factories.dropFirst(calls)), [300, 299])
            XCTAssertEqual(rowIDs(candidate.children), [0, 1, 299, 300])
            XCTAssertEqual(candidate.children.count, 8)
            XCTAssertTrue(fixture.adapter.complete(candidate: candidate, adoptedChildren: candidate.children))
            XCTAssertEqual(readiness(fixture, request.hint), .awaitingPreparation)
            XCTAssertLessThanOrEqual(fixture.adapter.mountedRecordCount, limits.records)
            XCTAssertLessThanOrEqual(fixture.adapter.mountedLeafCount, limits.leaves)
            XCTAssertEqual(shared.remainingElements, 126)
            XCTAssertEqual(shared.remainingRounds, 4)
        }
    }

    func testSlackLeavesTheLastRecordSlotForTheExistingBoundaryProbe() async throws {
        let fixture = try makeFixture(records: 5, leaves: 10, hasGaps: true)
        defer { fixture.source.close() }
        let request = try beginHint(fixture, target: 300)
        let calls = fixture.probe.factories.count
        let candidate = try ready(fixture)

        XCTAssertEqual(Array(fixture.probe.factories.dropFirst(calls)), [300, 299, 298])
        XCTAssertEqual(rowIDs(candidate.children), [0, 1, 298, 299, 300])
        XCTAssertFalse(fixture.probe.factories.contains(297))
        XCTAssertTrue(fixture.adapter.complete(candidate: candidate, adoptedChildren: candidate.children))
        XCTAssertEqual(readiness(fixture, request.hint), .awaitingProbeRetirement)
        XCTAssertEqual(fixture.adapter.mountedRecordCount, 5)
        XCTAssertEqual(fixture.adapter.mountedLeafCount, 10)
    }

    func testTwoElementAllowanceConstructsTheRealFutureWindowBeforeAnySlack() async throws {
        let fixture = try makeFixture()
        defer { fixture.source.close() }
        let request = try beginHint(fixture, target: 300)
        let calls = fixture.probe.factories.count
        let shared = try budget(2)
        let candidate = try ready(fixture, budget: shared)

        XCTAssertEqual(Array(fixture.probe.factories.dropFirst(calls)), [300, 299])
        XCTAssertEqual(rowIDs(candidate.children), Array(0...4) + [299, 300])
        XCTAssertTrue(fixture.adapter.complete(candidate: candidate, adoptedChildren: candidate.children))
        XCTAssertEqual(readiness(fixture, request.hint), .awaitingPreparation)
        XCTAssertEqual(shared.remainingElements, 0)
        XCTAssertEqual(shared.remainingRounds, 4)
        XCTAssertFalse(fixture.probe.factories.contains(298))
    }

    func testZeroPrefetchPreservesTheOriginalPlanAndPureReadiness() async throws {
        let fixture = try makeFixture(prefetch: 0, records: 4, leaves: 4)
        defer { fixture.source.close() }
        let request = try beginHint(fixture, target: 300)
        let calls = fixture.probe.factories.count
        let candidate = try ready(fixture)

        XCTAssertEqual(Array(fixture.probe.factories.dropFirst(calls)), [300, 299])
        XCTAssertEqual(rowIDs(candidate.children), [0, 1, 299, 300])
        XCTAssertTrue(fixture.adapter.complete(candidate: candidate, adoptedChildren: candidate.children))
        let acceptedFactories = fixture.probe.factories
        let batch = measurements(fixture)
        for _ in 0..<3 {
            XCTAssertEqual(
                fixture.adapter.uiAConstructionReadiness(
                    for: request.hint, viewport: fixture.viewport, measurements: batch),
                .measurementOnly)
        }
        XCTAssertEqual(fixture.probe.factories, acceptedFactories)
        XCTAssertNil(fixture.adapter.knownLeafCount(for: request.token))
        XCTAssertEqual(fixture.adapter.contentExtent, 20_000)
    }

    func testProspectiveViewportExcludesTheTargetsTrailingInterLeafSpacing() async throws {
        let fixture = try makeFixture(prefetch: 0, records: 5, leaves: 5, spacing: 10, viewportExtent: 60)
        defer { fixture.source.close() }
        let request = try beginHint(fixture, target: 300)
        let bounds = try XCTUnwrap(fixture.adapter.logicalBounds(for: request.token))
        XCTAssertEqual(bounds.origin, 9_000)
        XCTAssertEqual(bounds.extent, 20)
        let calls = fixture.probe.factories.count
        let candidate = try ready(fixture)

        // The future viewport ends at 9020, not at the 9030 record boundary.
        // Its 8960 lower edge intersects row 298 as well as rows 299 and 300.
        XCTAssertEqual(Array(fixture.probe.factories.dropFirst(calls)), [300, 298, 299])
        XCTAssertEqual(rowIDs(candidate.children), [0, 1, 298, 299, 300])
        XCTAssertTrue(fixture.adapter.complete(candidate: candidate, adoptedChildren: candidate.children))
        XCTAssertEqual(readiness(fixture, request.hint), .measurementOnly)
        XCTAssertTrue(request.hint.isCurrent)
    }

    func testAcceptedMeasurementsChooseSlackDirectionForTheOriginalHint() async throws {
        let fixture = try makeFixture(offset: 500)
        defer { fixture.source.close() }
        XCTAssertEqual(Set(fixture.probe.factories), Set(22...29))
        let request = try beginHint(fixture, target: 28)
        let before = try XCTUnwrap(fixture.adapter.logicalBounds(for: request.token))
        XCTAssertEqual(before.origin, 560)
        let factories = fixture.probe.factories.count
        let calls = fixture.probe.providerCalls
        let batch = fixture.adapter.layoutPlan(viewport: fixture.viewport).placements.map { placement in
            let id = placement.node.accessibilityIdentifier.flatMap(Int.init)
            return Adapter.Measurement(
                token: placement.token, leafIndex: placement.leafIndex, node: placement.node,
                extent: id.map { (22...26).contains($0) ? 0 : 20 } ?? 0)
        }
        _ = try XCTUnwrap(fixture.adapter.recordMeasurements(batch, viewport: fixture.viewport))
        let moved = try XCTUnwrap(fixture.adapter.logicalBounds(for: request.token))
        XCTAssertEqual(moved.origin, 460)
        XCTAssertEqual(moved.extent, 20)
        XCTAssertTrue(request.hint.isCurrent)
        XCTAssertEqual(fixture.probe.providerCalls, calls)
        XCTAssertEqual(fixture.probe.factories.count, factories)
        let shared = try budget(128)

        let candidate = try ready(fixture, budget: shared)

        // The original target is now above the unchanged viewport. Current
        // required rows 30/31 precede trailing slack 32; accepted rows 28/29 reuse
        // their exact rows. The original downward estimate must not add leading
        // slack instead or renew the hint to discover the new direction.
        let built = Array(fixture.probe.factories.dropFirst(factories))
        XCTAssertEqual(Array(built.prefix(3)), [30, 31, 32])
        XCTAssertTrue(built.allSatisfy { $0 >= 30 })
        XCTAssertTrue(rowIDs(candidate.children).contains(32))
        XCTAssertTrue(fixture.adapter.complete(candidate: candidate, adoptedChildren: candidate.children))
        let acceptedCalls = fixture.probe.providerCalls
        XCTAssertEqual(readiness(fixture, request.hint), .awaitingPreparation)
        XCTAssertEqual(fixture.probe.providerCalls, acceptedCalls)
        XCTAssertTrue(request.hint.isCurrent)
        XCTAssertEqual(shared.remainingRounds, 4)
        XCTAssertLessThanOrEqual(fixture.adapter.mountedRecordCount, 16)
    }

    func testEndingTheOriginalHintInAMainWindowFactoryStopsAllSlack() async throws {
        let fixture = try makeFixture()
        defer {
            fixture.probe.onFactory = nil
            fixture.source.close()
        }
        let request = try beginHint(fixture, target: 300)
        let calls = fixture.probe.factories.count
        let originalRows = fixture.adapter.mountedRecordCount
        var cancellations = 0
        fixture.probe.onFactory = { id in
            guard id == 299 else { return }
            cancellations += 1
            XCTAssertTrue(fixture.adapter.endUIAConstructionHint(request.hint))
        }
        let shared = try budget(128)

        let result = fixture.adapter.prepare(viewport: fixture.viewport, protectedRoots: [], budget: shared)

        guard case .obsolete = result else { return XCTFail("Expected the original hint's rejection") }
        XCTAssertEqual(cancellations, 1)
        XCTAssertEqual(Array(fixture.probe.factories.dropFirst(calls)), [300, 299])
        XCTAssertFalse(request.hint.isCurrent)
        XCTAssertNil(fixture.adapter.mountedNodes(for: request.token))
        XCTAssertEqual(fixture.adapter.mountedRecordCount, originalRows)
        XCTAssertEqual(shared.remainingElements, 126)
        XCTAssertEqual(shared.remainingRounds, 4)
    }

    private struct Fixture {
        let source: Source
        let probe: TargetRelativePlanProbe
        let adapter: Adapter
        let viewport: Adapter.Viewport
        let owner: RetainedLazyListLogicalRealizationOwner
        let height: @MainActor (Int) -> Double
    }

    private func makeFixture(
        offset: Double = 0, prefetch: Double = 60, records: Int = 16, leaves: Int = 32,
        hasGaps: Bool = false, spacing: Double = 0, viewportExtent: Double = 40,
        height: @escaping @MainActor (Int) -> Double = { _ in 20 }
    ) throws -> Fixture {
        let source = Source()
        let probe = TargetRelativePlanProbe()
        XCTAssertTrue(
            source.replaceData(Array(0..<1000), id: \.self) { id in
                probe.factories.append(id)
                probe.onFactory?(id)
                let row = ViewNode()
                row.accessibilityIdentifier = String(id)
                guard hasGaps else { return [row] }
                let gap = ViewNode()
                gap.retainedLazyListGap = RetainedLazyListGap(
                    spacing: 0, separatorThickness: 0, nextRowIsSelected: false, nextRowIsGrouped: false)
                return [gap, row]
            })
        do {
            let adapter = try XCTUnwrap(
                Adapter(
                    provider: TargetRelativePlanProvider(source: source, probe: probe),
                    estimatedExtent: 20, prefetchExtent: prefetch,
                    maximumMountedRecords: records, maximumMountedLeaves: leaves, maximumProtectedRecords: 2,
                    interLeafSpacing: spacing))
            let context = try XCTUnwrap(
                RetainedLazyListMeasurementContext(
                    width: 120, displayScale: 1, contentRevision: 0, environmentRevision: 0))
            let viewport = try XCTUnwrap(Adapter.Viewport(context: context, offset: offset, extent: viewportExtent))
            let fixture = Fixture(
                source: source, probe: probe, adapter: adapter, viewport: viewport,
                owner: RetainedLazyListLogicalRealizationOwner(), height: height)
            let candidate = try ready(fixture)
            XCTAssertTrue(adapter.complete(candidate: candidate, adoptedChildren: candidate.children))
            _ = try XCTUnwrap(adapter.recordMeasurements(measurements(fixture), viewport: viewport))
            XCTAssertFalse(probe.factories.contains(300))
            return fixture
        } catch {
            source.close()
            throw error
        }
    }

    private func token(_ id: Int, in fixture: Fixture) throws -> RetainedLazyListRowToken {
        try XCTUnwrap(fixture.source.metadata?.rows[id].token)
    }

    private func beginHint(
        _ fixture: Fixture, target: Int
    ) throws -> (
        token: RetainedLazyListRowToken, demand: RetainedLazyListLogicalRealization, hint: Adapter.UIAConstructionHint
    ) {
        let token = try token(target, in: fixture)
        let demand = try XCTUnwrap(fixture.adapter.beginLogicalRealization(of: token, owner: fixture.owner))
        let hint = try XCTUnwrap(fixture.adapter.beginUIAConstructionHint(for: demand, viewport: fixture.viewport))
        return (token, demand, hint)
    }

    private func budget(_ elements: Int) throws -> RetainedLazyListWorkBudget {
        try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: elements, roundLimit: 4))
    }

    private func ready(
        _ fixture: Fixture, budget shared: RetainedLazyListWorkBudget? = nil
    ) throws -> Adapter.Candidate {
        let result = fixture.adapter.prepare(
            viewport: fixture.viewport, protectedRoots: [], budget: try shared ?? budget(128))
        guard case .ready(let candidate) = result else {
            XCTFail("Expected a bounded raw candidate")
            throw TargetRelativePlanFailure.noCandidate
        }
        return candidate
    }

    private func measurements(_ fixture: Fixture) -> [Adapter.Measurement] {
        fixture.adapter.layoutPlan(viewport: fixture.viewport).placements.map { placement in
            let extent = placement.node.accessibilityIdentifier.flatMap(Int.init).map { fixture.height($0) } ?? 0
            return Adapter.Measurement(
                token: placement.token, leafIndex: placement.leafIndex, node: placement.node, extent: extent)
        }
    }

    private func readiness(_ fixture: Fixture, _ hint: Adapter.UIAConstructionHint) -> Adapter.UIAConstructionReadiness
    {
        fixture.adapter.uiAConstructionReadiness(
            for: hint, viewport: fixture.viewport, measurements: measurements(fixture))
    }

    private func rowIDs(_ nodes: [ViewNode]) -> [Int] {
        nodes.compactMap { $0.accessibilityIdentifier.flatMap(Int.init) }
    }
}

private enum TargetRelativePlanFailure: Error {
    case noCandidate
}

@MainActor
private final class TargetRelativePlanProbe {
    var factories: [Int] = []
    var providerCalls = 0
    var onFactory: (@MainActor (Int) -> Void)?
}

@MainActor
private final class TargetRelativePlanProvider: RetainedLazyListProvider {
    typealias RowContent = [ViewNode]
    let source: RetainedLazyListDataSource<Int, [ViewNode]>
    let probe: TargetRelativePlanProbe

    init(source: RetainedLazyListDataSource<Int, [ViewNode]>, probe: TargetRelativePlanProbe) {
        self.source = source
        self.probe = probe
    }

    var metadata: RetainedLazyListMetadata? {
        probe.providerCalls += 1
        return source.metadata
    }

    func token(for key: RetainedViewIdentity.Key, occurrence: Int) -> RetainedLazyListRowToken? {
        probe.providerCalls += 1
        return source.token(for: key, occurrence: occurrence)
    }

    func request(for token: RetainedLazyListRowToken) -> RetainedLazyListRowRequest? {
        probe.providerCalls += 1
        return source.request(for: token)
    }

    func isCurrent(_ request: RetainedLazyListRowRequest) -> Bool {
        probe.providerCalls += 1
        return source.isCurrent(request)
    }

    func identityPrefix(for request: RetainedLazyListRowRequest) -> RetainedViewIdentity? {
        probe.providerCalls += 1
        return source.identityPrefix(for: request)
    }

    func materialize(
        _ request: RetainedLazyListRowRequest, budget: RetainedLazyListWorkBudget
    ) -> RetainedLazyListMaterialization<[ViewNode]> {
        probe.providerCalls += 1
        return source.materialize(request, budget: budget)
    }
}
