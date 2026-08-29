import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class LazyListMeasurementLayoutTests: XCTestCase {
    private typealias Adapter = RetainedLazyListRuntimeAdapter
    private typealias Source = RetainedLazyListDataSource<Int, [ViewNode]>

    /// Raw adapter cases prove the measurement signal, not physical adoption.
    func testFirstExactMeasurementPublishesLeafCountWithoutAnotherLayout() async throws {
        let fixture = try makeRawFixture(estimate: 40) { _ in [ViewNode(), ViewNode()] }
        defer { fixture.source.close() }
        let token = try XCTUnwrap(fixture.adapter.layoutPlan(viewport: fixture.viewport).placements.first?.token)
        XCTAssertNil(fixture.adapter.knownLeafCount(for: token))

        let first = try measure(fixture.adapter, viewport: fixture.viewport) { $0.leafIndex == 0 ? 10 : 30 }

        XCTAssertTrue(first.extentChanged, "Measured cardinality remains an extent metadata change")
        XCTAssertFalse(first.requiresLayout)
        XCTAssertEqual(first.anchorAdjustedOffset, 0)
        XCTAssertEqual(fixture.adapter.knownLeafCount(for: token), 2)
        XCTAssertEqual(fixture.adapter.layoutPlan(viewport: fixture.viewport).placements.map(\.originY), [0, 10])
        XCTAssertFalse(fixture.adapter.hasUnresolvedWork)

        let repeated = try measure(fixture.adapter, viewport: fixture.viewport) { $0.leafIndex == 0 ? 10 : 30 }
        XCTAssertFalse(repeated.extentChanged)
        XCTAssertFalse(repeated.requiresLayout)
    }

    func testFirstMeasurementRequiresLayoutForTheSmallestRepresentableSizeChange() async throws {
        let fixture = try makeRawFixture(estimate: 20) { _ in [ViewNode()] }
        defer { fixture.source.close() }

        let update = try measure(fixture.adapter, viewport: fixture.viewport) { _ in Double(20).nextUp }

        XCTAssertTrue(update.extentChanged)
        XCTAssertTrue(update.requiresLayout, "There is no tolerance that can hide a real prefix change")
        XCTAssertEqual(fixture.adapter.contentExtent, Double(20).nextUp)
    }

    func testKnownLeafRedistributionRequiresLayoutEvenWithAnUnchangedRecordTotal() async throws {
        let fixture = try makeRawFixture(estimate: 40) { _ in [ViewNode(), ViewNode()] }
        defer { fixture.source.close() }
        _ = try measure(fixture.adapter, viewport: fixture.viewport) { $0.leafIndex == 0 ? 10 : 30 }

        let update = try measure(fixture.adapter, viewport: fixture.viewport) { _ in 20 }

        XCTAssertTrue(update.extentChanged)
        XCTAssertTrue(update.requiresLayout)
        XCTAssertEqual(fixture.adapter.contentExtent, 40)
        XCTAssertEqual(fixture.adapter.layoutPlan(viewport: fixture.viewport).placements.map(\.originY), [0, 20])
    }

    func testOpposingRecordChangesCannotCancelTheRequiredLayout() async throws {
        let fixture = try makeRawFixture(values: [0, 1], estimate: 20) { _ in [ViewNode()] }
        defer { fixture.source.close() }
        let first = try XCTUnwrap(fixture.adapter.layoutPlan(viewport: fixture.viewport).placements.first?.token)

        let update = try measure(fixture.adapter, viewport: fixture.viewport) { $0.token == first ? 10 : 30 }

        XCTAssertTrue(update.extentChanged)
        XCTAssertTrue(update.requiresLayout)
        XCTAssertEqual(fixture.adapter.contentExtent, 40)
        XCTAssertEqual(fixture.adapter.layoutPlan(viewport: fixture.viewport).placements.map(\.originY), [0, 10])
    }

    func testUnknownLeadingGapStillWithholdsMeasurementsAndSettlement() async throws {
        let fixture = try makeRawFixture(values: [0, 1, 2, 3], estimate: 21, offset: 42, extent: 21) { _ in
            let gap = ViewNode()
            gap.retainedLazyListGap = RetainedLazyListGap(
                spacing: 0, separatorThickness: 1, nextRowIsSelected: false, nextRowIsGrouped: false)
            return [gap, ViewNode()]
        }
        defer { fixture.source.close() }
        let token = try XCTUnwrap(fixture.adapter.layoutPlan(viewport: fixture.viewport).placements.first?.token)

        let update = try measure(fixture.adapter, viewport: fixture.viewport) { $0.leafIndex == 0 ? 1 : 20 }

        XCTAssertFalse(update.extentChanged)
        XCTAssertFalse(update.requiresLayout)
        XCTAssertNil(fixture.adapter.knownLeafCount(for: token))
        XCTAssertTrue(fixture.adapter.hasUnresolvedWork)
        XCTAssertTrue(fixture.adapter.layoutPlan(viewport: fixture.viewport).requiresResolution)
    }

    func testManagedExactMeasurementsSettleActualMultipleLeavesWithinTwoSharedRounds() async throws {
        let probe = MeasurementLayoutProbe()
        let host = makeManagedHost(probe)
        defer { host.close() }
        XCTAssertTrue(host.runtime.configureLazyListResolutionBudget(elementLimit: 8, roundLimit: 2))

        XCTAssertNotNil(host.layout())

        let list = try host.list()
        let adapter = try XCTUnwrap(list.retainedLazyListAdapter)
        XCTAssertEqual(probe.factories, [0, 1])
        XCTAssertEqual(list.children.map { $0.resolvedFrame.minY }, [0, 5, 20, 25])
        XCTAssertEqual(list.children.map { $0.resolvedFrame.height }, [5, 15, 5, 15])
        XCTAssertTrue(list.children.allSatisfy { $0.parent === list && $0.runtime === host.runtime })
        XCTAssertEqual(adapter.contentExtent, 20_000)
        XCTAssertEqual(list.resolvedContentSize.height, 20_000)
        XCTAssertFalse(adapter.hasUnresolvedWork)
        XCTAssertEqual(host.runtime.lastLazyListConsumedElements, 2)
        XCTAssertEqual(host.runtime.lastLazyListConsumedRounds, 2)
        XCTAssertEqual(host.runtime.lastLazyListWorkCompletion, .complete)
        guard case .settled(let receipt) = host.runtime.layoutSettlementStatus else {
            return XCTFail("Exact measurements must finish the actual current layout")
        }
        XCTAssertTrue(host.runtime.isLayoutSettlementReceiptCurrent(receipt))
    }

    func testManagedExactMeasurementsCannotSkipTheMeasurementRound() async throws {
        let probe = MeasurementLayoutProbe()
        let host = makeManagedHost(probe)
        defer { host.close() }
        XCTAssertTrue(host.runtime.configureLazyListResolutionBudget(elementLimit: 8, roundLimit: 1))

        XCTAssertNotNil(host.layout())

        XCTAssertEqual(probe.factories, [0, 1])
        XCTAssertEqual(host.runtime.lastLazyListConsumedElements, 2)
        XCTAssertEqual(host.runtime.lastLazyListConsumedRounds, 1)
        XCTAssertEqual(host.runtime.lastLazyListWorkCompletion, .budgetExhausted)
        XCTAssertTrue(try XCTUnwrap(try host.list().retainedLazyListAdapter).hasUnresolvedWork)
        if case .settled = host.runtime.layoutSettlementStatus {
            XCTFail("Estimated equality does not authorize an unmeasured window")
        }
    }

    func testManagedChangedTotalsStillNeedAnotherCheckedViewportPass() async throws {
        let probe = MeasurementLayoutProbe(secondLeafHeight: 5)
        let host = makeManagedHost(probe)
        defer { host.close() }
        XCTAssertTrue(host.runtime.configureLazyListResolutionBudget(elementLimit: 8, roundLimit: 2))

        XCTAssertNotNil(host.layout())

        XCTAssertEqual(probe.factories, [0, 1])
        XCTAssertEqual(host.runtime.lastLazyListConsumedRounds, 2)
        XCTAssertEqual(host.runtime.lastLazyListWorkCompletion, .budgetExhausted)
        XCTAssertTrue(try XCTUnwrap(try host.list().retainedLazyListAdapter).hasUnresolvedWork)
        if case .settled = host.runtime.layoutSettlementStatus {
            XCTFail("Shorter rows expose additional viewport work, even when their own leaves were measured")
        }
    }

    private func makeRawFixture(
        values: [Int] = [0], estimate: Double, offset: Double = 0, extent: Double = 40,
        rows: @escaping @MainActor (Int) -> [ViewNode]
    ) throws -> (source: Source, adapter: Adapter, viewport: Adapter.Viewport) {
        let source = Source()
        XCTAssertTrue(source.replaceData(values, id: \.self, rowContent: rows))
        do {
            let adapter = try XCTUnwrap(
                Adapter(
                    provider: source, estimatedExtent: estimate, prefetchExtent: 0,
                    maximumMountedRecords: 8, maximumMountedLeaves: 16, maximumProtectedRecords: 2))
            let context = try XCTUnwrap(
                RetainedLazyListMeasurementContext(
                    width: 120, displayScale: 1, contentRevision: 0, environmentRevision: 0))
            let viewport = try XCTUnwrap(Adapter.Viewport(context: context, offset: offset, extent: extent))
            let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 8, roundLimit: 4))
            let prepared = adapter.prepare(viewport: viewport, protectedRoots: [], budget: budget)
            var candidate: Adapter.Candidate?
            if case .ready(let value) = prepared { candidate = value }
            let actual = try XCTUnwrap(candidate)
            XCTAssertTrue(adapter.complete(candidate: actual, adoptedChildren: actual.children))
            return (source, adapter, viewport)
        } catch {
            source.close()
            throw error
        }
    }

    private func measure(
        _ adapter: Adapter, viewport: Adapter.Viewport, height: @MainActor (Adapter.Placement) -> Double
    ) throws -> Adapter.MeasurementUpdate {
        let measurements = adapter.layoutPlan(viewport: viewport).placements.map {
            Adapter.Measurement(token: $0.token, leafIndex: $0.leafIndex, node: $0.node, extent: height($0))
        }
        return try XCTUnwrap(adapter.recordMeasurements(measurements, viewport: viewport))
    }

    private func makeManagedHost(_ probe: MeasurementLayoutProbe) -> MountedLazyListTestHost {
        MountedLazyListTestHost {
            ManagedLazyListContent(
                Array(0..<1000), id: \.self, estimatedExtent: 20, prefetchExtent: 0,
                maximumMountedRecords: 8, maximumMountedLeaves: 16, maximumProtectedRecords: 2
            ) { probe.makeRows($0) }
        }
    }
}

@MainActor
private final class MeasurementLayoutProbe {
    let secondLeafHeight: Double
    var factories: [Int] = []

    init(secondLeafHeight: Double = 15) { self.secondLeafHeight = secondLeafHeight }

    func makeRows(_ id: Int) -> [AnyView] {
        factories.append(id)
        return [
            AnyView(Color.blue.frame(width: 120, height: 5)),
            AnyView(Color.red.frame(width: 120, height: secondLeafHeight)),
        ]
    }
}
