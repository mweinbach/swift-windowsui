import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsLayout
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// These cases keep the default allowance. Geometry is checked before another
/// render or input query can run; subsequent painting and input have their own
/// ordinary entry points and cannot repair the original realization oracle.
@MainActor
final class LazyListLogicalVerticalGeometryTests: XCTestCase {
    func testAlreadyWarmFiftyThousandPublicRowsRealize300WithinDefaultAllowance() async throws {
        let probe = LogicalVerticalPublicProbe()
        let host = MountedLazyListTestHost(size: Size(width: 320, height: 80)) {
            List(probe.rows, id: \.self) { probe.makeRows($0) }.listStyle(.plain)
        }
        defer { host.close() }
        XCTAssertNotNil(host.layout())
        let runtime = host.runtime
        let list = try host.list()
        let adapter = try XCTUnwrap(list.retainedLazyListAdapter)
        let scroll = try host.scrollContainer()
        XCTAssertEqual(probe.rows.count, 50_000)
        XCTAssertGreaterThan(adapter.contentExtent, Double(GPUISceneLimits.maxCoordinate))
        XCTAssertEqual(list.resolvedContentSize.height, adapter.contentExtent)
        assertSettled(runtime)
        let source = RuntimeUIAElementTreeSource(runtime: runtime)
        let container = try XCTUnwrap(source.uiaElementSnapshots().first(where: \.supportsItemContainer)?.id)
        var element: UInt64?
        for _ in 0...300 {
            guard case .item(let next) = source.uiaFindItem(containerID: container, afterElementID: element) else {
                return XCTFail("Expected the original fifty-thousand-row logical source")
            }
            element = next
        }
        let id = try XCTUnwrap(element)
        XCTAssertEqual(source.uiaLogicalItemState(elementID: id), .placeholder)
        XCTAssertFalse(probe.factories.contains(300))
        let before = probe.factories.count
        runtime.recordsLazyListUIAPhasesForTesting = true

        // No reload, source replacement, new budget, or preparatory render.
        XCTAssertTrue(source.uiaRealizeVirtualizedItem(elementID: id))

        assertSettled(runtime)
        assertOriginalAllowance(runtime)
        XCTAssertEqual(source.uiaLogicalItemState(elementID: id), .ordinary)
        XCTAssertEqual(list.resolvedContentSize.height, adapter.contentExtent)
        XCTAssertEqual(scroll.resolvedContentSize.height, adapter.contentExtent)
        XCTAssertGreaterThan(scroll.scrollOffset, 0)
        XCTAssertTrue(probe.factories.contains(300))
        XCTAssertLessThan(probe.factories.count - before, 128)
        XCTAssertTrue(probe.activations.isEmpty)
        let snapshot = try XCTUnwrap(source.uiaElementSnapshots().first { $0.id == id })
        XCTAssertEqual(snapshot.name, "Row 300")
        XCTAssertFalse(snapshot.isOffscreen)
        XCTAssertGreaterThan(snapshot.bounds.height, 0)
        XCTAssertLessThan(snapshot.bounds.minY, 80)
        XCTAssertGreaterThan(snapshot.bounds.maxY, 0)
        XCTAssertTrue(source.uiaInvokeDefaultAction(elementID: id))
        XCTAssertEqual(probe.activations, [300])
    }

    func testDeepTypedTargetKeepsItsOriginalPrefixAndMeasuredSettlement() async throws {
        let fixture = try LogicalVerticalFixture()
        defer { fixture.close() }
        XCTAssertEqual(fixture.adapter.logicalRecordCount, 50_000)
        XCTAssertEqual(fixture.adapter.contentExtent, 1_600_000)
        XCTAssertFalse(fixture.probe.factories.contains(40_000))

        try fixture.withRequest(target: 40_000) { request in
            let roots = try XCTUnwrap(fixture.runtime.resolveLazyListUIARequest(request))
            let row = try XCTUnwrap(roots.first { $0.dynamicContentIndex == 40_000 })
            _ = try assertDeepGeometry(row, request: request, fixture: fixture)
        }

        assertOriginalAllowance(fixture.runtime)
        XCTAssertEqual(fixture.probe.factories.filter { $0 == 40_000 }.count, 1)
        XCTAssertLessThan(fixture.probe.factories.count, 128)
        XCTAssertTrue(fixture.probe.activations.isEmpty)
    }

    func testDeepTargetUsesViewportPrepaintHitTestingAndUIAAction() async throws {
        let fixture = try LogicalVerticalFixture()
        defer { fixture.close() }
        var originalPoint: Point?
        var originalRow: ViewNode?
        try fixture.withRequest(target: 40_000) { request in
            let roots = try XCTUnwrap(fixture.runtime.resolveLazyListUIARequest(request))
            let row = try XCTUnwrap(roots.first { $0.dynamicContentIndex == 40_000 })
            originalPoint = try assertDeepGeometry(row, request: request, fixture: fixture)
            originalRow = row
        }
        assertOriginalAllowance(fixture.runtime)
        let point = try XCTUnwrap(originalPoint)
        let row = try XCTUnwrap(originalRow)
        XCTAssertTrue(fixture.probe.activations.isEmpty)

        // Both renderers receive a viewport coordinate after the large native
        // prefix and the scroll offset have cancelled in Double arithmetic.
        let frame = fixture.runtime.renderFrame()
        let fills = frame.commands.compactMap { command -> FillRectCommand? in
            guard case .fillRect(let fill) = command else { return nil }
            return fill
        }
        XCTAssertTrue(fills.contains { $0.rect.contains(point) })
        for fill in fills { assertPaintRect(fill.rect) }
        let scene = fixture.runtime.renderScene()
        let quads = scene.layers.flatMap(\.quads)
        XCTAssertFalse(quads.isEmpty)
        XCTAssertTrue(
            quads.contains {
                Rect(x: Double($0.x), y: Double($0.y), width: Double($0.width), height: Double($0.height)).contains(
                    point)
            })
        for quad in quads {
            assertPaintRect(
                Rect(x: Double(quad.x), y: Double(quad.y), width: Double(quad.width), height: Double(quad.height)))
            for value in [quad.clipX, quad.clipY, quad.clipWidth, quad.clipHeight] {
                XCTAssertTrue(value.isFinite)
                XCTAssertLessThanOrEqual(abs(value), GPUISceneLimits.maxCoordinate)
            }
        }

        fixture.runtime.pointerMoved(to: point)
        XCTAssertTrue(row.isHovered)
        fixture.runtime.pointerDown(at: point)
        fixture.runtime.pointerUp(at: point)
        XCTAssertEqual(fixture.probe.activations, [40_000])
        let source = RuntimeUIAElementTreeSource(runtime: fixture.runtime)
        let snapshot = try XCTUnwrap(source.uiaElementSnapshots().first { $0.automationID == "logical.vertical.40000" })
        XCTAssertFalse(snapshot.isOffscreen)
        XCTAssertTrue(snapshot.bounds.contains(point))
        XCTAssertTrue(source.uiaInvokeDefaultAction(elementID: snapshot.id))
        XCTAssertEqual(fixture.probe.activations, [40_000, 40_000])
    }

    func testDeepScrollObserverReportsTheSameLogicalRangeAndOffset() async throws {
        let fixture = try LogicalVerticalFixture()
        defer { fixture.close() }
        var values: [RetainedScrollGeometry] = []
        fixture.scroll.observeScrollGeometry(of: { $0 }, action: { _, next in values.append(next) })
        try fixture.withRequest(target: 40_000) { request in
            let roots = try XCTUnwrap(fixture.runtime.resolveLazyListUIARequest(request))
            let row = try XCTUnwrap(roots.first { $0.dynamicContentIndex == 40_000 })
            _ = try assertDeepGeometry(row, request: request, fixture: fixture)
        }
        assertOriginalAllowance(fixture.runtime)
        let offset = fixture.scroll.resolvedScrollOffset
        XCTAssertGreaterThan(offset, Double(GPUISceneLimits.maxCoordinate))
        _ = fixture.runtime.renderScene()
        let geometry = try XCTUnwrap(values.last)
        XCTAssertEqual(geometry.contentSize.height, fixture.adapter.contentExtent)
        XCTAssertEqual(geometry.contentOffset.y, offset)
        XCTAssertEqual(geometry.containerSize.height, 80)
        XCTAssertEqual(geometry.contentInsets, .zero)
        XCTAssertTrue(geometry.contentSize.height.isFinite)
        XCTAssertTrue(geometry.contentOffset.y.isFinite)
    }

    func testSingleChildWrappersCarryTheLogicalHeightThroughTheirActualPass() async throws {
        let fixture = try LogicalVerticalFixture(wrapperCount: 2)
        defer { fixture.close() }
        XCTAssertEqual(fixture.wrappers.count, 2)
        try fixture.withRequest(target: 40_000) { request in
            let roots = try XCTUnwrap(fixture.runtime.resolveLazyListUIARequest(request))
            let row = try XCTUnwrap(roots.first { $0.dynamicContentIndex == 40_000 })
            _ = try assertDeepGeometry(row, request: request, fixture: fixture)
            for wrapper in fixture.wrappers {
                XCTAssertEqual(wrapper.resolvedFrame.height, fixture.adapter.contentExtent)
                XCTAssertEqual(wrapper.resolvedContentSize.height, fixture.adapter.contentExtent)
                XCTAssertEqual(wrapper.lastLayoutVisitPassID, fixture.runtime.layoutPassID)
            }
        }
        assertOriginalAllowance(fixture.runtime)
    }

    func testNestedScrollOwnerDoesNotInheritItsChildsLogicalRange() async throws {
        let fixture = try LogicalVerticalFixture(surroundings: .nestedScroll)
        defer { fixture.close() }
        let outer = try XCTUnwrap(fixture.otherScroll)
        var outerValues: [RetainedScrollGeometry] = []
        outer.observeScrollGeometry(of: { $0 }, action: { _, next in outerValues.append(next) })
        try fixture.withRequest(target: 40_000) { request in
            let roots = try XCTUnwrap(fixture.runtime.resolveLazyListUIARequest(request))
            let row = try XCTUnwrap(roots.first { $0.dynamicContentIndex == 40_000 })
            _ = try assertDeepGeometry(row, request: request, fixture: fixture)
        }
        assertOriginalAllowance(fixture.runtime)
        XCTAssertEqual(outer.resolvedContentSize.height, 80)
        XCTAssertEqual(outer.scrollOffset, 0)
        _ = fixture.runtime.renderScene()
        let geometry = try XCTUnwrap(outerValues.last)
        XCTAssertEqual(geometry.contentSize.height, 80)
        XCTAssertEqual(geometry.contentOffset.y, 0)
        XCTAssertGreaterThan(fixture.scroll.scrollOffset, Double(GPUISceneLimits.maxCoordinate))
    }

    func testUnrelatedOrdinaryScrollerKeepsItsExistingSanitation() async throws {
        let fixture = try LogicalVerticalFixture(surroundings: .unrelatedScroller)
        defer { fixture.close() }
        let ordinary = try XCTUnwrap(fixture.otherScroll)
        let ordinaryContent = try XCTUnwrap(ordinary.children.first)
        var values: [RetainedScrollGeometry] = []
        ordinary.observeScrollGeometry(of: { $0 }, action: { _, next in values.append(next) })
        try fixture.withRequest(target: 40_000) { request in
            let roots = try XCTUnwrap(fixture.runtime.resolveLazyListUIARequest(request))
            let row = try XCTUnwrap(roots.first { $0.dynamicContentIndex == 40_000 })
            _ = try assertDeepGeometry(row, request: request, fixture: fixture)
        }
        assertOriginalAllowance(fixture.runtime)
        XCTAssertEqual(ordinaryContent.resolvedFrame.height, Double(GPUISceneLimits.maxCoordinate))
        XCTAssertEqual(ordinary.resolvedContentSize.height, Double(GPUISceneLimits.maxCoordinate))
        XCTAssertEqual(ordinary.scrollOffset, 0)
        _ = fixture.runtime.renderFrame()
        let geometry = try XCTUnwrap(values.last)
        XCTAssertEqual(geometry.contentSize.height, Double(GPUISceneLimits.maxCoordinate))
        XCTAssertEqual(geometry.contentOffset.y, 0)
    }

    func testUnrecognizedMultiChildCarrierKeepsOrdinarySanitation() async throws {
        let fixture = try LogicalVerticalFixture(surroundings: .multiChildCarrier)
        defer { fixture.close() }
        let carrier = try XCTUnwrap(fixture.scroll.children.first)
        XCTAssertEqual(carrier.children.count, 2)
        XCTAssertGreaterThan(fixture.adapter.contentExtent, Double(GPUISceneLimits.maxCoordinate))
        XCTAssertEqual(fixture.list.resolvedContentSize.height, fixture.adapter.contentExtent)
        XCTAssertEqual(carrier.resolvedFrame.height, Double(GPUISceneLimits.maxCoordinate))
        XCTAssertEqual(fixture.scroll.resolvedContentSize.height, Double(GPUISceneLimits.maxCoordinate))
        XCTAssertFalse(fixture.probe.factories.contains(40_000))
        // This patch does not qualify large extents through arbitrary sibling
        // branches. In particular, this is not a deep-scroll success oracle.
    }

    func testNonfiniteLogicalWrapperCannotBecomeAClampedSettlement() async throws {
        for value in [Double.infinity, -Double.infinity, Double.nan] {
            let fixture = try LogicalVerticalFixture(wrapperCount: 1)
            defer { fixture.close() }
            let witness = try fixture.target(40_000)
            let wrapper = try XCTUnwrap(fixture.wrappers.first)
            // The same originally attached native List remains below the
            // carrier. Its malformed natural vertical arithmetic cannot be
            // repaired into a successful measured settlement by a size floor.
            wrapper.layoutMode = .stack(.vertical(spacing: 0, padding: EdgeInsets(top: value), alignment: .stretch))
            try assertRejectedGeometry(fixture, witness: witness)
        }
    }

    func testFiniteLogicalPaddingOverflowCannotBecomeAClampedSettlement() async throws {
        let fixture = try LogicalVerticalFixture(wrapperCount: 1)
        defer { fixture.close() }
        let witness = try fixture.target(40_000)
        let wrapper = try XCTUnwrap(fixture.wrappers.first)
        let finite = Double.greatestFiniteMagnitude
        XCTAssertTrue(finite.isFinite)
        XCTAssertFalse((finite + finite).isFinite)
        wrapper.layoutMode = .stack(
            .vertical(spacing: 0, padding: EdgeInsets(top: finite, bottom: finite), alignment: .stretch))
        try assertRejectedGeometry(fixture, witness: witness)
    }

    func testNonfiniteLogicalSpacingCannotHideBehindOneChild() async throws {
        let fixture = try LogicalVerticalFixture(wrapperCount: 1)
        defer { fixture.close() }
        let witness = try fixture.target(40_000)
        let wrapper = try XCTUnwrap(fixture.wrappers.first)
        XCTAssertEqual(wrapper.children.count, 1)
        wrapper.layoutMode = .stack(.vertical(spacing: .nan, alignment: .stretch))
        try assertRejectedGeometry(fixture, witness: witness)
    }

    func testRejectedLogicalInputRemainsRejectedAfterRenderingAndFiniteRepairSucceeds() async throws {
        let fixture = try LogicalVerticalFixture(wrapperCount: 2)
        defer { fixture.close() }
        let witness = try fixture.target(40_000)
        let wrapper = try XCTUnwrap(fixture.wrappers.first)
        wrapper.layoutMode = .stack(.vertical(padding: EdgeInsets(top: .nan), alignment: .stretch))
        try assertRejectedGeometry(fixture, witness: witness)

        // Rendering clears dirty flags. A later otherwise-clean query must
        // still reject the original input below its clean ancestor wrapper.
        _ = fixture.runtime.renderFrame()
        XCTAssertFalse(wrapper.hasDirtySubtree)
        assertNotSettled(fixture.runtime)
        try assertRejectedGeometry(fixture, witness: witness)
        _ = fixture.runtime.renderScene()
        XCTAssertFalse(wrapper.hasDirtySubtree)
        try assertRejectedGeometry(fixture, witness: witness)

        // This is an explicit ordinary repair and then a distinct request;
        // it cannot pay for or retroactively certify either rejected query.
        wrapper.layoutMode = .stack(.vertical(spacing: 0, alignment: .stretch))
        XCTAssertTrue(wrapper.hasDirtySubtree)
        XCTAssertNotNil(fixture.runtime.resolvedLayoutFrame(of: fixture.scroll))
        assertSettled(fixture.runtime)
        try fixture.withRequest(target: 40_000) { request in
            let roots = try XCTUnwrap(fixture.runtime.resolveLazyListUIARequest(request))
            let row = try XCTUnwrap(roots.first { $0.dynamicContentIndex == 40_000 })
            _ = try assertDeepGeometry(row, request: request, fixture: fixture)
        }
        assertOriginalAllowance(fixture.runtime)
    }

    func testFiniteChildAndFinitePaddingOverflowRejectsTheActualNaturalSumAfterCacheReuse() async throws {
        let maximum = Double.greatestFiniteMagnitude
        let estimated = maximum / 50_000 * 0.9
        let padding = maximum * 0.5
        XCTAssertTrue(estimated.isFinite)
        XCTAssertTrue(padding.isFinite)
        let fixture = try LogicalVerticalFixture(estimatedExtent: estimated, warm: false)
        defer { fixture.close() }
        fixture.scroll.layoutMode = .stack(
            .vertical(spacing: 0, padding: EdgeInsets(top: padding), alignment: .stretch))
        fixture.runtime.recordsLazyListUIAPhasesForTesting = true

        for _ in 0..<2 {
            _ = fixture.runtime.resolvedLayoutFrame(of: fixture.scroll)
            XCTAssertTrue(fixture.adapter.contentExtent.isFinite)
            XCTAssertGreaterThan(fixture.adapter.contentExtent, maximum * 0.5)
            XCTAssertFalse((fixture.adapter.contentExtent + padding).isFinite)
            assertNotSettled(fixture.runtime)
            XCTAssertLessThanOrEqual(fixture.runtime.lastLazyListConsumedElements, 128)
            XCTAssertLessThanOrEqual(fixture.runtime.lastLazyListConsumedRounds, 4)
            _ = fixture.runtime.renderFrame()
            XCTAssertFalse(fixture.scroll.hasDirtySubtree)
            assertNotSettled(fixture.runtime)
        }
        XCTAssertEqual(fixture.scroll.scrollOffset, 0)
        XCTAssertTrue(fixture.probe.activations.isEmpty)
        XCTAssertFalse(fixture.runtime.lazyListUIAPhasesForTesting.contains { $0.kind == .ownedScroll })
        XCTAssertFalse(fixture.runtime.hasActiveRetainedBuild)
    }

    func testMalformedUnrelatedScrollerKeepsOrdinaryObserverSanitation() async throws {
        let fixture = try LogicalVerticalFixture(surroundings: .unrelatedScroller)
        defer { fixture.close() }
        let ordinary = try XCTUnwrap(fixture.otherScroll)
        ordinary.layoutMode = .stack(
            .vertical(padding: EdgeInsets(top: .infinity, leading: .nan), alignment: .stretch))
        var values: [RetainedScrollGeometry] = []
        ordinary.observeScrollGeometry(of: { $0 }, action: { _, value in values.append(value) })
        _ = fixture.runtime.renderFrame()
        _ = fixture.runtime.renderScene()
        let geometry = try XCTUnwrap(values.first)
        let coordinates = [
            geometry.contentOffset.x, geometry.contentOffset.y,
            geometry.contentSize.width, geometry.contentSize.height,
            geometry.contentInsets.top, geometry.contentInsets.leading,
            geometry.contentInsets.bottom, geometry.contentInsets.trailing,
            geometry.containerSize.width, geometry.containerSize.height,
        ]
        XCTAssertTrue(coordinates.allSatisfy(\.isFinite))
        XCTAssertTrue(coordinates.allSatisfy { abs($0) <= Double(GPUISceneLimits.maxCoordinate) })
        XCTAssertEqual(geometry.contentInsets.leading, 0)
        XCTAssertEqual(geometry.contentInsets.top, Double(GPUISceneLimits.maxCoordinate))
        XCTAssertEqual(geometry.contentOffset.y, -geometry.contentInsets.top)
        XCTAssertEqual(values.count, 1)
    }

    func testAbsoluteAssignedOverflowRemainsRejectedAfterCleanQueriesAndRepairSucceeds() async throws {
        try assertAssignedOverflow(.absoluteFrame)
    }

    func testAbsoluteCallbackOverflowRemainsRejectedAfterCleanQueriesAndRepairSucceeds() async throws {
        try assertAssignedOverflow(.absoluteCallback)
    }

    func testStackAssignmentOverflowDespiteFinitePaddingSumRemainsRejectedUntilRepair() async throws {
        try assertAssignedOverflow(.stackPadding)
    }

    func testLatePositionOverflowRemainsRejectedAfterCleanQueriesAndRepairSucceeds() async throws {
        try assertAssignedOverflow(.position)
    }

    func testFiniteAllocatedChildDoesNotInheritAnOverflowFromItsUnallocatedEstimate() async throws {
        let maximum = Double.greatestFiniteMagnitude
        let padding = maximum * 0.5
        let fixture = try LogicalVerticalFixture(
            wrapperCount: 1, estimatedExtent: maximum / 50_000 * 0.9, warm: false)
        defer { fixture.close() }
        let wrapper = try XCTUnwrap(fixture.wrappers.first)
        wrapper.preferredSize = Size(width: 120, height: 80)
        wrapper.layoutMode = .stack(
            .vertical(spacing: 0, padding: EdgeInsets(top: padding), alignment: .stretch))

        XCTAssertNotNil(fixture.runtime.resolvedLayoutFrame(of: fixture.scroll))

        XCTAssertGreaterThan(fixture.adapter.contentExtent, maximum * 0.5)
        XCTAssertFalse((fixture.adapter.contentExtent + padding).isFinite)
        XCTAssertEqual(wrapper.resolvedFrame.height, 80)
        XCTAssertEqual(fixture.list.resolvedFrame.height, 0)
        XCTAssertTrue(fixture.list.resolvedFrame.maxY.isFinite)
        XCTAssertEqual(wrapper.resolvedContentSize.height, padding)
        XCTAssertEqual(fixture.scroll.resolvedContentSize.height, 80)
        assertSettled(fixture.runtime)
        // A naive fold of adapter extent plus padding would reject this
        // valid allocation. It is not a claim that its clipped rows are visible.
    }

    func testOverflowingExtentIndexDoesNotProduceAClampedLogicalList() async throws {
        let huge = Double.greatestFiniteMagnitude * 0.75
        XCTAssertTrue(huge.isFinite)
        XCTAssertFalse((huge + huge).isFinite)
        let fixture = try LogicalVerticalFixture(rowCount: 2, estimatedExtent: huge, warm: false)
        defer { fixture.close() }
        fixture.runtime.recordsLazyListUIAPhasesForTesting = true
        _ = fixture.runtime.resolvedLayoutFrame(of: fixture.scroll)
        assertNotSettled(fixture.runtime)
        XCTAssertTrue(fixture.probe.factories.isEmpty)
        XCTAssertEqual(fixture.scroll.scrollOffset, 0)
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedElements, 0)
        XCTAssertLessThanOrEqual(fixture.runtime.lastLazyListConsumedRounds, 4)
        XCTAssertFalse(fixture.runtime.lazyListUIAPhasesForTesting.contains { $0.kind == .ownedScroll })
    }

    func testLogicalWrapperDepthOverflowDoesNotCertifyClampedGeometry() async throws {
        let fixture = try LogicalVerticalFixture(wrapperCount: 4)
        defer { fixture.close() }
        let witness = try fixture.target(40_000)
        let previousLimit = ViewNode.maximumTraversalDepth
        defer { ViewNode.maximumTraversalDepth = previousLimit }
        ViewNode.maximumTraversalDepth = 3
        // Use the existing depth guard, not a new breadth or logical-row cap.
        fixture.scroll.frame.size.width += 1
        try assertRejectedGeometry(fixture, witness: witness)
    }

    func testAnOrdinaryAuthoredRowStillUsesItsExistingSizeLimit() async throws {
        let fixture = try LogicalVerticalFixture(rowCount: 1, rowHeight: 1_200_000)
        defer { fixture.close() }
        let row = try XCTUnwrap(fixture.list.children.first)
        XCTAssertEqual(row.preferredSize?.height, 1_200_000)
        XCTAssertEqual(row.resolvedFrame.height, Double(GPUISceneLimits.maxCoordinate))
        XCTAssertEqual(row.resolvedFrame.width, 120)
        XCTAssertEqual(row.resolvedFrame.origin.x, 0)
        XCTAssertEqual(fixture.adapter.contentExtent, row.resolvedFrame.height)
    }

    func testANativeRowDoesNotGainAnAuthoredHeightExemptionFromANestedAdapter() async throws {
        let fixture = try LogicalVerticalFixture(rowCount: 1)
        defer { fixture.close() }
        let row = try XCTUnwrap(fixture.list.children.first)
        let innerSource = RetainedLazyListDataSource<Int, [ViewNode]>()
        defer { innerSource.close() }
        let identity = RetainedViewIdentity(segments: [.role(.content), .slot(9)])
        XCTAssertTrue(
            innerSource.replaceData([0, 1], id: \.self, identityRoot: identity) { _, prefix in
                let leaf = ViewNode(preferredSize: Size(width: 120, height: 32))
                leaf.retainedViewIdentity = prefix.appending(.role(.row))
                return [leaf]
            })
        let innerAdapter = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter(
                provider: innerSource, estimatedExtent: 32, prefetchExtent: 0,
                maximumMountedRecords: 4, maximumMountedLeaves: 4, maximumProtectedRecords: 2))
        let inner = ViewNode(layoutMode: .lazyStack(.vertical(spacing: 0, alignment: .stretch)))
        inner.retainedViewIdentity = identity
        inner.retainedLazyListAdapter = innerAdapter
        inner.retainedSubtreeBuildLease = LogicalVerticalLease()
        row.layoutMode = .stack(.vertical(spacing: 0, alignment: .stretch))
        row.preferredSize = Size(width: 120, height: 1_200_000)
        row.addChild(inner)

        XCTAssertNotNil(fixture.runtime.resolvedLayoutFrame(of: fixture.scroll))

        XCTAssertTrue(row.parent === fixture.list)
        XCTAssertTrue(row.children.first === inner)
        XCTAssertTrue(inner.retainedLazyListAdapter === innerAdapter)
        XCTAssertEqual(row.preferredSize?.height, 1_200_000)
        XCTAssertEqual(row.resolvedFrame.height, Double(GPUISceneLimits.maxCoordinate))
        XCTAssertEqual(row.resolvedFrame.origin.y, 0)
    }

    private func assertDeepGeometry(
        _ row: ViewNode, request: RetainedLazyListUIARequest, fixture: LogicalVerticalFixture,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> Point {
        let runtime = fixture.runtime
        XCTAssertTrue(runtime.isResolvedLazyListUIARequestCurrent(request), file: file, line: line)
        assertSettled(runtime, file: file, line: line)
        XCTAssertTrue(row.parent === fixture.list, file: file, line: line)
        XCTAssertEqual(row.resolvedFrame.minY, 1_280_000, file: file, line: line)
        XCTAssertEqual(row.resolvedFrame.height, 32, file: file, line: line)
        XCTAssertEqual(row.lastLayoutVisitPassID, runtime.layoutPassID, file: file, line: line)
        XCTAssertFalse(row.isLayoutDeferredByVirtualization, file: file, line: line)
        XCTAssertEqual(fixture.list.resolvedContentSize.height, fixture.adapter.contentExtent, file: file, line: line)
        XCTAssertEqual(fixture.scroll.resolvedContentSize.height, fixture.adapter.contentExtent, file: file, line: line)
        XCTAssertGreaterThan(fixture.scroll.scrollOffset, Double(GPUISceneLimits.maxCoordinate), file: file, line: line)
        XCTAssertEqual(fixture.scroll.scrollOffset, fixture.scroll.resolvedScrollOffset, file: file, line: line)
        XCTAssertTrue(runtime.currentPrepaintState.dispatchNodes.contains { $0.node === row }, file: file, line: line)
        let interaction = try XCTUnwrap(
            runtime.currentPrepaintState.interactions.first { $0.node === row }, file: file, line: line)
        XCTAssertEqual(
            interaction.frame.minY, row.resolvedFrame.minY - fixture.scroll.resolvedScrollOffset, file: file, line: line
        )
        XCTAssertGreaterThan(interaction.frame.height, 0, file: file, line: line)
        XCTAssertLessThan(interaction.frame.minY, 80, file: file, line: line)
        XCTAssertGreaterThan(interaction.frame.maxY, 0, file: file, line: line)
        XCTAssertTrue(fixture.probe.activations.isEmpty, file: file, line: line)
        return Point(x: interaction.frame.midX, y: interaction.frame.midY)
    }

    private func assertOriginalAllowance(
        _ runtime: RetainedViewRuntime, file: StaticString = #filePath, line: UInt = #line
    ) {
        let debits = runtime.lazyListUIAPhasesForTesting.filter { $0.kind == .roundDebit }
        guard !debits.isEmpty else { return XCTFail("Expected paid original rounds", file: file, line: line) }
        XCTAssertEqual(debits.map(\.consumedRounds), Array(1...debits.count), file: file, line: line)
        XCTAssertEqual(runtime.lastLazyListConsumedRounds, debits.count, file: file, line: line)
        XCTAssertLessThanOrEqual(runtime.lastLazyListConsumedRounds, 4, file: file, line: line)
        XCTAssertGreaterThan(runtime.lastLazyListConsumedElements, 0, file: file, line: line)
        XCTAssertLessThanOrEqual(runtime.lastLazyListConsumedElements, 128, file: file, line: line)
        XCTAssertEqual(runtime.lastLazyListWorkCompletion, .complete, file: file, line: line)
        XCTAssertEqual(
            runtime.lazyListUIAPhasesForTesting.filter { $0.kind == .ownedScroll }.count, 1, file: file, line: line)
        XCTAssertFalse(runtime.hasActiveRetainedBuild, file: file, line: line)
    }

    private func assertSettled(
        _ runtime: RetainedViewRuntime, file: StaticString = #filePath, line: UInt = #line
    ) {
        guard case .settled(let receipt) = runtime.layoutSettlementStatus else {
            return XCTFail("Expected this request's own measured settlement", file: file, line: line)
        }
        XCTAssertTrue(runtime.isLayoutSettlementReceiptCurrent(receipt), file: file, line: line)
        XCTAssertTrue(runtime.hasCurrentAccessibilityPrepaint, file: file, line: line)
    }

    private func assertNotSettled(
        _ runtime: RetainedViewRuntime, file: StaticString = #filePath, line: UInt = #line
    ) {
        if case .settled = runtime.layoutSettlementStatus {
            XCTFail("Invalid logical geometry must not certify its finite fallback", file: file, line: line)
        }
    }

    private func assertPaintRect(_ rect: Rect, file: StaticString = #filePath, line: UInt = #line) {
        for value in [rect.origin.x, rect.origin.y, rect.width, rect.height] {
            XCTAssertTrue(value.isFinite, file: file, line: line)
            XCTAssertLessThanOrEqual(abs(value), Double(GPUISceneLimits.maxCoordinate), file: file, line: line)
        }
    }

    private func assertRejectedGeometry(
        _ fixture: LogicalVerticalFixture, witness: RetainedLazyListAccessibilityItem,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let runtime = fixture.runtime
        let offset = fixture.scroll.scrollOffset
        let factoryCount = fixture.probe.factories.count
        runtime.recordsLazyListUIAPhasesForTesting = true
        _ = runtime.resolvedLayoutFrame(of: fixture.scroll)
        assertNotSettled(runtime, file: file, line: line)
        let mutation = try XCTUnwrap(runtime.beginAccessibilityMutation(), file: file, line: line)
        defer { runtime.endAccessibilityMutation(mutation) }
        runtime.withLazyListResolutionBudget {
            guard let request = runtime.prepareLazyListUIARequest(token: witness.token, in: witness, during: mutation)
            else { return }
            defer { runtime.finishLazyListUIARequest(request) }
            XCTAssertNil(runtime.resolveLazyListUIARequest(request), file: file, line: line)
        }
        assertNotSettled(runtime, file: file, line: line)
        XCTAssertEqual(fixture.probe.factories.count, factoryCount, file: file, line: line)
        XCTAssertFalse(fixture.probe.factories.contains(40_000), file: file, line: line)
        XCTAssertTrue(fixture.probe.activations.isEmpty, file: file, line: line)
        XCTAssertEqual(fixture.scroll.scrollOffset, offset, file: file, line: line)
        XCTAssertFalse(runtime.lazyListUIAPhasesForTesting.contains { $0.kind == .ownedScroll }, file: file, line: line)
        XCTAssertLessThanOrEqual(runtime.lastLazyListConsumedElements, 128, file: file, line: line)
        XCTAssertLessThanOrEqual(runtime.lastLazyListConsumedRounds, 4, file: file, line: line)
        XCTAssertFalse(runtime.hasActiveRetainedBuild, file: file, line: line)
    }

    private func assertAssignedOverflow(
        _ kind: LogicalVerticalAssignedFailure, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let fixture = try LogicalVerticalFixture(wrapperCount: 2)
        defer { fixture.close() }
        let runtime = fixture.runtime
        let inner = try XCTUnwrap(fixture.wrappers.first, file: file, line: line)
        let outer = try XCTUnwrap(fixture.wrappers.last, file: file, line: line)
        let witness = try fixture.target(40_000)
        let maximum = Double.greatestFiniteMagnitude
        let huge = maximum * 0.75
        let invalid = Rect(x: 0, y: huge, width: 120, height: huge)
        XCTAssertTrue(invalid.origin.y.isFinite, file: file, line: line)
        XCTAssertTrue(invalid.height.isFinite, file: file, line: line)
        XCTAssertFalse(invalid.maxY.isFinite, file: file, line: line)
        var callbackCalls = 0
        switch kind {
        case .absoluteFrame, .absoluteCallback:
            outer.layoutMode = .absolute
            outer.preferredSize = Size(width: 120, height: maximum * 0.9)
            if kind == .absoluteFrame {
                inner.frame = invalid
            } else {
                outer.absoluteChildFrame = { _, _ in
                    callbackCalls += 1
                    return invalid
                }
            }
        case .stackPadding:
            fixture.scroll.layoutMode = .stack(
                .vertical(spacing: 0, padding: EdgeInsets(top: huge, bottom: -huge), alignment: .stretch))
            outer.preferredSize = Size(width: 120, height: huge)
            XCTAssertEqual(huge + -huge, 0, file: file, line: line)
            XCTAssertTrue((80 - huge).isFinite, file: file, line: line)
            XCTAssertTrue((80 - huge - -huge).isFinite, file: file, line: line)
        case .position:
            outer.preferredSize = Size(width: 120, height: huge)
            outer.position = Point(x: 60, y: maximum)
            XCTAssertTrue((maximum - huge / 2).isFinite, file: file, line: line)
            XCTAssertFalse((maximum - huge / 2 + huge).isFinite, file: file, line: line)
        }
        runtime.recordsLazyListUIAPhasesForTesting = true
        for _ in 0..<2 {
            let before = callbackCalls
            _ = runtime.resolvedLayoutFrame(of: fixture.scroll)
            assertNotSettled(runtime, file: file, line: line)
            if kind == .absoluteCallback { XCTAssertGreaterThan(callbackCalls, before, file: file, line: line) }
            let mutation = try XCTUnwrap(runtime.beginAccessibilityMutation(), file: file, line: line)
            runtime.withLazyListResolutionBudget {
                guard
                    let request = runtime.prepareLazyListUIARequest(token: witness.token, in: witness, during: mutation)
                else { return }
                defer { runtime.finishLazyListUIARequest(request) }
                XCTAssertNil(runtime.resolveLazyListUIARequest(request), file: file, line: line)
            }
            runtime.endAccessibilityMutation(mutation)
            assertNotSettled(runtime, file: file, line: line)
            XCTAssertFalse(fixture.probe.factories.contains(40_000), file: file, line: line)
            XCTAssertTrue(fixture.probe.activations.isEmpty, file: file, line: line)
            XCTAssertEqual(fixture.scroll.scrollOffset, 0, file: file, line: line)
            XCTAssertFalse(
                runtime.lazyListUIAPhasesForTesting.contains { $0.kind == .ownedScroll }, file: file, line: line)
            XCTAssertLessThanOrEqual(runtime.lastLazyListConsumedElements, 128, file: file, line: line)
            XCTAssertLessThanOrEqual(runtime.lastLazyListConsumedRounds, 4, file: file, line: line)
            XCTAssertFalse(runtime.hasActiveRetainedBuild, file: file, line: line)
            _ = runtime.renderFrame()
            XCTAssertFalse(outer.hasDirtySubtree, file: file, line: line)
            assertNotSettled(runtime, file: file, line: line)
        }

        outer.absoluteChildFrame = nil
        fixture.scroll.layoutMode = .stack(.vertical(spacing: 0, alignment: .stretch))
        for wrapper in fixture.wrappers {
            wrapper.position = nil
            wrapper.preferredSize = nil
            wrapper.frame = .zero
            wrapper.layoutMode = .stack(.vertical(spacing: 0, alignment: .stretch))
        }
        XCTAssertNotNil(runtime.resolvedLayoutFrame(of: fixture.scroll), file: file, line: line)
        assertSettled(runtime, file: file, line: line)
        try fixture.withRequest(target: 40_000) { request in
            let roots = try XCTUnwrap(runtime.resolveLazyListUIARequest(request), file: file, line: line)
            let row = try XCTUnwrap(roots.first { $0.dynamicContentIndex == 40_000 }, file: file, line: line)
            _ = try assertDeepGeometry(row, request: request, fixture: fixture, file: file, line: line)
        }
        assertOriginalAllowance(runtime, file: file, line: line)
    }
}

private enum LogicalVerticalAssignedFailure {
    case absoluteFrame, absoluteCallback, stackPadding, position
}

private enum LogicalVerticalSurroundings {
    case none, nestedScroll, unrelatedScroller, multiChildCarrier
}

@MainActor
private final class LogicalVerticalFixture {
    let source: RetainedLazyListDataSource<Int, [ViewNode]>
    let adapter: RetainedLazyListRuntimeAdapter
    let list: ViewNode
    let wrappers: [ViewNode]
    let scroll: ViewNode
    let otherScroll: ViewNode?
    let runtime: RetainedViewRuntime
    let probe: LogicalVerticalProbe

    init(
        wrapperCount: Int = 0, surroundings: LogicalVerticalSurroundings = .none,
        rowCount: Int = 50_000, estimatedExtent: Double = 32, rowHeight: Double = 32, warm: Bool = true
    ) throws {
        let source = RetainedLazyListDataSource<Int, [ViewNode]>()
        let probe = LogicalVerticalProbe(rowHeight: rowHeight)
        let identity = RetainedViewIdentity(segments: [.role(.content), .slot(0)])
        let factory: @MainActor @Sendable (Int, RetainedViewIdentity) -> [ViewNode] = { id, prefix in
            probe.makeRows(id, prefix: prefix)
        }
        XCTAssertTrue(source.replaceData(Array(0..<rowCount), id: \.self, identityRoot: identity, rowContent: factory))
        let adapter = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter(
                provider: source, estimatedExtent: estimatedExtent, prefetchExtent: 80,
                maximumMountedRecords: 16, maximumMountedLeaves: 32, maximumProtectedRecords: 2))
        let list = ViewNode(layoutMode: .lazyStack(.vertical(spacing: 0, alignment: .stretch)), isHitTestVisible: false)
        list.retainedViewIdentity = identity
        list.retainedLazyListAdapter = adapter
        list.retainedSubtreeBuildLease = LogicalVerticalLease()
        var content = list
        var wrappers: [ViewNode] = []
        for _ in 0..<wrapperCount {
            let wrapper = ViewNode(layoutMode: .stack(.vertical(spacing: 0, alignment: .stretch)), children: [content])
            wrappers.append(wrapper)
            content = wrapper
        }
        if surroundings == .multiChildCarrier {
            content = ViewNode(
                layoutMode: .stack(.vertical(spacing: 0, alignment: .stretch)),
                children: [content, ViewNode(preferredSize: Size(width: 120, height: 1))])
        }
        let scroll = ViewNode(
            frame: Rect(x: 0, y: 0, width: 120, height: 80), clipsToBounds: true,
            layoutMode: .stack(.vertical(spacing: 0, alignment: .stretch)), scrollAxis: .vertical, children: [content])
        let root: ViewNode
        let otherScroll: ViewNode?
        switch surroundings {
        case .nestedScroll:
            let outer = ViewNode(
                frame: Rect(x: 0, y: 0, width: 120, height: 80), clipsToBounds: true,
                layoutMode: .stack(.vertical(spacing: 0, alignment: .stretch)), scrollAxis: .vertical,
                children: [scroll])
            root = outer
            otherScroll = outer
        case .unrelatedScroller:
            let ordinary = ViewNode(
                frame: Rect(x: 140, y: 0, width: 120, height: 80), clipsToBounds: true,
                layoutMode: .stack(.vertical(spacing: 0, alignment: .stretch)), scrollAxis: .vertical,
                children: [ViewNode(preferredSize: Size(width: 120, height: 2_000_000))])
            root = ViewNode(frame: Rect(x: 0, y: 0, width: 260, height: 80), children: [scroll, ordinary])
            otherScroll = ordinary
        case .none, .multiChildCarrier:
            root = scroll
            otherScroll = nil
        }
        let runtime = RetainedViewRuntime(root: root)
        runtime.clock = { 0 }
        self.source = source
        self.adapter = adapter
        self.list = list
        self.wrappers = wrappers
        self.scroll = scroll
        self.otherScroll = otherScroll
        self.runtime = runtime
        self.probe = probe
        if warm {
            XCTAssertNotNil(runtime.resolvedLayoutFrame(of: scroll))
            XCTAssertFalse(adapter.hasUnresolvedWork)
            XCTAssertTrue(runtime.hasCurrentAccessibilityPrepaint)
            XCTAssertFalse(probe.factories.contains(40_000))
        }
    }

    func target(_ index: Int) throws -> RetainedLazyListAccessibilityItem {
        let token = try XCTUnwrap(source.token(for: .init(index)))
        return try XCTUnwrap(runtime.lazyListTarget(in: list, token: token))
    }

    func withRequest(target index: Int, inspect: @MainActor (RetainedLazyListUIARequest) throws -> Void) throws {
        let witness = try target(index)
        let mutation = try XCTUnwrap(runtime.beginAccessibilityMutation())
        defer { runtime.endAccessibilityMutation(mutation) }
        runtime.recordsLazyListUIAPhasesForTesting = true
        try runtime.withLazyListResolutionBudget {
            let request = try XCTUnwrap(
                runtime.prepareLazyListUIARequest(token: witness.token, in: witness, during: mutation))
            defer { runtime.finishLazyListUIARequest(request) }
            try inspect(request)
        }
    }

    func close() {
        for wrapper in wrappers { wrapper.onLayoutWithNode = nil }
        runtime.stopRenderLifecycleCallbacks()
        source.close()
        runtime.cancelRenderLifecycleTasks()
        runtime.root.removeAllChildren()
    }
}

@MainActor
private final class LogicalVerticalProbe {
    let rowHeight: Double
    var factories: [Int] = []
    var activations: [Int] = []
    init(rowHeight: Double) { self.rowHeight = rowHeight }
    func makeRows(_ id: Int, prefix: RetainedViewIdentity) -> [ViewNode] {
        factories.append(id)
        let row = ViewNode(backgroundColor: .white, preferredSize: Size(width: 120, height: rowHeight))
        row.retainedViewIdentity = prefix.appending(.slot(0)).appending(.role(.row))
        row.dynamicContentIndex = id
        row.accessibilityIdentifier = "logical.vertical.\(id)"
        row.accessibilityLabel = "Logical row \(id)"
        row.isFocusable = true
        row.onActivate = { [weak self] in self?.activations.append(id) }
        return [row]
    }
}

@MainActor
private final class LogicalVerticalLease: RetainedSubtreeBuildLease {
    var canBuild: Bool { true }
    func beginBuild() -> (any RetainedBuildEpoch)? { LogicalVerticalEpoch() }
}

@MainActor
private final class LogicalVerticalEpoch: RetainedBuildEpoch {
    private var prepared = false
    private var superseded = false
    var canAdopt: Bool { !prepared && !superseded }
    func supersede() { if !prepared { superseded = true } }
    func willAdopt() -> Bool {
        guard canAdopt else { return false }
        prepared = true
        return true
    }
    func commit() {}
    func abandon() {}
    func finishAfterCallbacks() {}
}

@MainActor
private final class LogicalVerticalPublicProbe {
    let rows = Array(0..<50_000)
    var factories: [Int] = []
    var activations: [Int] = []
    func makeRows(_ id: Int) -> [AnyView] {
        factories.append(id)
        return [
            AnyView(
                Button("Row \(id)") { [weak self] in self?.activations.append(id) }
                    .accessibilityIdentifier("logical.public.row.\(id)")
                    .frame(height: 24))
        ]
    }
}
