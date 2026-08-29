import SwiftWindowsCore
import SwiftWindowsLayout
import XCTest

@testable import SwiftWindowsUI

/// Headless retained fixtures for the public facade's runtime contract. These
/// do not claim native COM, a window host, or D3D11 presentation coverage.
@MainActor
final class PublicLazyListRuntimeTests: XCTestCase {
    func testSpacingCountsProjectedLeavesAndNoTrailingGap() async throws {
        let fixture = try PublicLazyRuntimeFixture(
            values: [0, 1, 2], height: 120, spacing: 5,
            heights: [0: [], 1: [7, 13], 2: [30]])
        defer { fixture.close() }

        XCTAssertTrue(fixture.calls.values.isEmpty)
        _ = fixture.runtime.renderFrame()

        XCTAssertEqual(fixture.calls.values, [0, 1, 2])
        XCTAssertEqual(fixture.list.children.map { $0.resolvedFrame.minY }, [0, 12, 30])
        XCTAssertEqual(fixture.list.children.map { $0.resolvedFrame.height }, [7, 13, 30])
        XCTAssertEqual(fixture.adapter.contentExtent, 60)
        XCTAssertEqual(fixture.list.resolvedContentSize.height, 60)
        assertSettled(fixture.runtime)
    }

    func testStyledOuterPaddingKeepsLargeListConstructionBounded() async throws {
        let fixture = try PublicLazyRuntimeFixture(
            values: Array(0..<10_000), height: 80, spacing: 3,
            padding: EdgeInsets(top: 8, leading: 6, bottom: 12, trailing: 10))
        defer { fixture.close() }

        _ = fixture.runtime.renderFrame()

        XCTAssertEqual(fixture.adapter.contentExtent, 229_997)
        XCTAssertEqual(fixture.list.resolvedFrame.minX, 6)
        XCTAssertEqual(fixture.list.resolvedFrame.minY, 8)
        XCTAssertEqual(fixture.list.resolvedFrame.width, 104)
        XCTAssertLessThan(fixture.calls.values.count, 12)
        XCTAssertLessThan(fixture.adapter.mountedRecordCount, 12)
        XCTAssertEqual(fixture.list.children.first?.resolvedFrame.width, 104)
        assertSettled(fixture.runtime)
    }

    func testLogicalEnumerationDoesNotBuildAndKeyboardRealizationDoesNotScroll() async throws {
        let fixture = try PublicLazyRuntimeFixture(values: Array(0..<10_000))
        defer { fixture.close() }
        _ = fixture.runtime.renderFrame()
        let originalCalls = fixture.calls.values
        var item = fixture.runtime.lazyListAccessibilityItem(in: fixture.list)
        for _ in 0..<175 {
            item = fixture.runtime.lazyListAccessibilityItem(in: fixture.list, after: try XCTUnwrap(item))
        }
        let target = try XCTUnwrap(item)
        XCTAssertEqual(fixture.calls.values, originalCalls)
        XCTAssertEqual(target.token, fixture.source.token(for: .init(175)))
        XCTAssertNil(fixture.runtime.realizedLazyListAccessibilityNodes(for: target))

        defer { fixture.runtime.releaseLazyListTarget(target) }
        let row = try XCTUnwrap(fixture.runtime.realizeLazyListTarget(target))

        XCTAssertEqual(row.dynamicContentIndex, 175)
        XCTAssertTrue(row.parent === fixture.list)
        XCTAssertEqual(fixture.scroll.scrollOffset, 0)
        XCTAssertEqual(fixture.calls.values.count, originalCalls.count + 1)
        XCTAssertLessThanOrEqual(fixture.adapter.mountedRecordCount, 16)
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedElements, 1)
        assertSettled(fixture.runtime)
    }

    func testLogicalAccessibilityRealizationUsesActualRowsAndExpiresOnDetach() async throws {
        let fixture = try PublicLazyRuntimeFixture(values: Array(0..<1000))
        defer { fixture.close() }
        _ = fixture.runtime.renderFrame()
        let token = try XCTUnwrap(fixture.source.token(for: .init(175)))
        let item = try XCTUnwrap(fixture.runtime.lazyListTarget(in: fixture.list, token: token))
        let mutation = try XCTUnwrap(fixture.runtime.beginAccessibilityMutation())
        let rows = fixture.runtime.realizeLazyListAccessibilityItem(item, during: mutation)
        fixture.runtime.endAccessibilityMutation(mutation)

        let row = try XCTUnwrap(rows?.first)
        XCTAssertEqual(row.dynamicContentIndex, 175)
        XCTAssertTrue(row.parent === fixture.list)
        XCTAssertGreaterThan(fixture.scroll.scrollOffset, 0)
        XCTAssertNotNil(fixture.runtime.realizedLazyListAccessibilityNodes(for: item))
        XCTAssertTrue(fixture.runtime.isLazyListAccessibilityItemCurrent(item))
        assertSettled(fixture.runtime)

        fixture.scroll.setChildren([])
        XCTAssertFalse(fixture.runtime.isLazyListAccessibilityItemCurrent(item))
        XCTAssertNil(fixture.runtime.realizedLazyListAccessibilityNodes(for: item))
        fixture.scroll.setChildren([fixture.list])
        XCTAssertFalse(fixture.runtime.isLazyListAccessibilityItemCurrent(item))
    }

    func testExpiredSourceNeverBuildsAnEscapedLogicalTarget() async throws {
        let fixture = try PublicLazyRuntimeFixture(values: Array(0..<1000))
        defer { fixture.close() }
        _ = fixture.runtime.renderFrame()
        let token = try XCTUnwrap(fixture.source.token(for: .init(175)))
        let item = try XCTUnwrap(fixture.runtime.lazyListTarget(in: fixture.list, token: token))
        let calls = fixture.calls.values

        fixture.source.close()

        XCTAssertFalse(fixture.runtime.isLazyListAccessibilityItemCurrent(item))
        XCTAssertNil(fixture.runtime.realizeLazyListTarget(item))
        XCTAssertEqual(fixture.calls.values, calls)
    }

    func testNativeGapsUseAdjacentActualRowsAcrossEmptyAndMultipleOutput() async throws {
        let ordinary = try XCTUnwrap(
            RetainedLazyListGap(
                spacing: 2, separatorThickness: 1, nextRowIsSelected: false, nextRowIsGrouped: false))
        let selected = try XCTUnwrap(
            RetainedLazyListGap(
                spacing: 2, separatorThickness: 1, nextRowIsSelected: true, nextRowIsGrouped: false))
        let grouped = try XCTUnwrap(
            RetainedLazyListGap(
                spacing: 2, separatorThickness: 1, nextRowIsSelected: false, nextRowIsGrouped: true))
        let fixture = try PublicLazyRuntimeFixture(
            values: [0, 1, 2, 3, 4, 5], height: 180,
            heights: [0: [], 1: [10, 10], 2: [10], 3: [10], 4: [10], 5: [10]],
            gaps: [1: [ordinary, ordinary], 2: [selected], 3: [grouped], 4: [ordinary], 5: [ordinary]])
        defer { fixture.close() }

        _ = fixture.runtime.renderFrame()

        let gaps = fixture.list.children.filter { $0.retainedLazyListGap != nil }
        let rows = fixture.list.children.filter { $0.retainedLazyListGap == nil }
        XCTAssertEqual(gaps.map { $0.resolvedFrame.height }, [0, 5, 2, 2, 2, 5])
        XCTAssertEqual(rows.map { $0.resolvedFrame.minY }, [0, 15, 27, 39, 51, 66])
        XCTAssertEqual(fixture.adapter.contentExtent, 76)
        XCTAssertEqual(fixture.calls.values, [0, 1, 2, 3, 4, 5])
        assertSettled(fixture.runtime)
    }

    func testMeasuredAlternatingChromeMatchesFlattenedStaticRows() async throws {
        let fixture = try PublicLazyRuntimeFixture(
            values: [0, 1, 2], height: 100,
            heights: [0: [], 1: [10, 10], 2: [10]], alternatingBackground: .blue)
        defer { fixture.close() }

        _ = fixture.runtime.renderFrame()

        let rows = fixture.list.children.filter { $0.retainedLazyListGap == nil }
        let expectedBackgrounds: [Color?] = [nil, .blue, nil]
        XCTAssertEqual(rows.map(\.backgroundColor), expectedBackgrounds)
        XCTAssertEqual(rows.map(\.cornerRadius), [0, 8, 0])
        XCTAssertEqual(rows.map(\.retainedLazyListRowChromeUsesEstimatedParity), [false, false, false])
        XCTAssertEqual(fixture.calls.values, [0, 1, 2])
        assertSettled(fixture.runtime)
    }

    func testPendingTargetContinuesAfterBudgetExhaustionWithoutAnotherRequest() async throws {
        let fixture = try PublicLazyRuntimeFixture(values: Array(0..<1000))
        defer { fixture.close() }
        _ = fixture.runtime.renderFrame()
        let originalCalls = fixture.calls.values.count
        let target = try XCTUnwrap(fixture.runtime.lazyListTarget(in: fixture.list, key: .init(175)))
        let request = PublicLazyPendingRequest(runtime: fixture.runtime, target: target)
        defer { request.cancel() }
        XCTAssertTrue(fixture.runtime.configureLazyListResolutionBudget(elementLimit: 0, roundLimit: 8))
        request.schedule()

        _ = fixture.runtime.renderFrame()

        XCTAssertGreaterThan(request.pendingCount, 0)
        XCTAssertNil(request.completedIndex)
        XCTAssertEqual(fixture.calls.values.count, originalCalls)
        XCTAssertTrue(fixture.runtime.configureLazyListResolutionBudget(elementLimit: 1, roundLimit: 8))
        for _ in 0..<8 where request.completedIndex == nil {
            let before = fixture.calls.values.count
            _ = fixture.runtime.renderFrame()
            XCTAssertLessThanOrEqual(fixture.calls.values.count - before, 1)
        }

        XCTAssertEqual(request.completedIndex, 175)
        XCTAssertEqual(request.completedCount, 1)
        XCTAssertTrue(request.completedWhileIdle)
        XCTAssertEqual(fixture.calls.values.filter { $0 == 175 }.count, 1)
        XCTAssertEqual(fixture.scroll.scrollOffset, 0)
    }

    func testDroppingPendingTargetDoesNotPinItsLogicalRow() async throws {
        let fixture = try PublicLazyRuntimeFixture(values: Array(0..<1000))
        defer { fixture.close() }
        _ = fixture.runtime.renderFrame()
        XCTAssertTrue(fixture.runtime.configureLazyListResolutionBudget(elementLimit: 0, roundLimit: 8))
        var item = fixture.runtime.lazyListTarget(in: fixture.list, key: .init(175))
        weak var weakItem = item
        guard case .pending = fixture.runtime.resolveLazyListTarget(try XCTUnwrap(item)) else {
            return XCTFail("Zero construction budget must leave this offscreen target pending")
        }

        item = nil

        XCTAssertNil(weakItem)
        XCTAssertTrue(fixture.runtime.configureLazyListResolutionBudget(elementLimit: 1, roundLimit: 8))
        _ = fixture.runtime.renderFrame()
        XCTAssertFalse(fixture.calls.values.contains(175))
        XCTAssertFalse(fixture.list.children.contains { $0.dynamicContentIndex == 175 })
    }

    func testPreparedActionProtectsUnfocusedSourceOnlyUntilItFinishes() async throws {
        let fixture = try PublicLazyRuntimeFixture(values: Array(0..<1000))
        defer { fixture.close() }
        _ = fixture.runtime.renderFrame()
        let scope = RetainedListNavigationOwner(runtime: fixture.runtime)
        scope.install(on: fixture.scroll)
        let sourceRow = try XCTUnwrap(fixture.list.children.first)
        sourceRow.isFocusable = true
        sourceRow.isFocusEnabled = true
        sourceRow.interceptsVerticalArrowKeys = true
        sourceRow.accessibilityTraits.insert(.isSelectable)
        let sourceOwner = scope.makeRowOwner(on: sourceRow)
        XCTAssertNil(fixture.runtime.focusedNode)
        var action = scope.prepareAction(from: sourceOwner)
        XCTAssertNotNil(action)
        let item = try XCTUnwrap(fixture.runtime.lazyListTarget(in: fixture.list, key: .init(175)))
        defer { fixture.runtime.releaseLazyListTarget(item) }
        let targetRow = try XCTUnwrap(fixture.runtime.realizeLazyListTarget(item))
        targetRow.isFocusable = true
        targetRow.isFocusEnabled = true
        targetRow.interceptsVerticalArrowKeys = true
        targetRow.accessibilityTraits.insert(.isSelectable)
        let targetOwner = scope.makeRowOwner(on: targetRow)

        XCTAssertTrue(action?.prepareTarget(targetOwner, requiresRevealBeforeFocus: true) == true)
        XCTAssertTrue(action?.finishNavigation() == true)

        XCTAssertTrue(fixture.runtime.focusedNode === targetRow)
        XCTAssertTrue(sourceRow.parent === fixture.list)
        XCTAssertGreaterThan(fixture.scroll.scrollOffset, 0)
        action = nil
        fixture.runtime.releaseLazyListTarget(item)
        _ = fixture.runtime.renderFrame()
        XCTAssertNil(sourceRow.parent)
        XCTAssertTrue(targetRow.parent === fixture.list)
    }

    func testAppearanceSearchBorrowsTheRenderConstructionBudget() async throws {
        let fixture = try PublicLazyRuntimeFixture(values: Array(0..<1000))
        defer { fixture.close() }
        XCTAssertTrue(fixture.runtime.configureLazyListResolutionBudget(elementLimit: 3, roundLimit: 8))
        var wasDeferred = false
        fixture.scroll.onAppear = { [weak fixture] in
            guard let fixture else { return }
            let result = fixture.runtime.probeLazyListScrollTarget(
                in: fixture.list, requestIsCurrent: { true }, matches: { _ in false })
            if case .deferred = result { wasDeferred = true }
        }

        _ = fixture.runtime.renderFrame()

        XCTAssertTrue(wasDeferred)
        XCTAssertEqual(fixture.calls.values, [0, 1, 2])
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedElements, 3)
    }

    func testLayoutSettlementQueueDoesNotBlockOrdinaryBuildObservers() async throws {
        var layoutIsIdle = false
        let coordinator = RetainedBuildCoordinator(layoutCallbacksAreAvailable: { layoutIsIdle })
        let layoutOwner = RetainedLazyListLogicalRealizationOwner()
        let ordinaryOwner = RetainedLazyListLogicalRealizationOwner()
        var events: [String] = []
        coordinator.scheduleAfterLayoutAndBuildsSettled(owner: layoutOwner) { events.append("layout") }
        coordinator.scheduleAfterBuildsSettled(owner: ordinaryOwner) { events.append("ordinary") }

        XCTAssertEqual(events, ["ordinary"])
        layoutIsIdle = true
        coordinator.retainedCallbacksDidDrain()
        coordinator.retainedCallbacksDidDrain()

        XCTAssertEqual(events, ["ordinary", "layout"])
    }

    func testLayoutSettlementRegistrationCannotRepeatInOneDrain() async throws {
        let coordinator = RetainedBuildCoordinator()
        let owner = RetainedLazyListLogicalRealizationOwner()
        var deliveries = 0
        coordinator.scheduleAfterLayoutAndBuildsSettled(owner: owner) {
            deliveries += 1
            coordinator.scheduleAfterLayoutAndBuildsSettled(owner: owner) { deliveries += 1 }
        }

        XCTAssertEqual(deliveries, 1)
        coordinator.retainedCallbacksDidDrain()
        XCTAssertEqual(deliveries, 2)
    }

    private func assertSettled(
        _ runtime: RetainedViewRuntime, file: StaticString = #filePath, line: UInt = #line
    ) {
        guard case .settled = runtime.layoutSettlementStatus else {
            XCTFail("Expected a completed bounded retained layout", file: file, line: line)
            return
        }
    }
}

@MainActor
private final class PublicLazyRuntimeCalls {
    var values: [Int] = []
}

@MainActor
private final class PublicLazyRuntimeFixture {
    let calls: PublicLazyRuntimeCalls
    let source: RetainedLazyListDataSource<Int, [ViewNode]>
    let adapter: RetainedLazyListRuntimeAdapter
    let list: ViewNode
    let scroll: ViewNode
    let runtime: RetainedViewRuntime

    init(
        values: [Int], height: Double = 60, spacing: Double = 0,
        padding: EdgeInsets = .zero, heights: [Int: [Double]] = [:], gaps: [Int: [RetainedLazyListGap]] = [:],
        alternatingBackground: Color? = nil
    ) throws {
        let identity = RetainedViewIdentity(segments: [.role(.content), .slot(0)])
        let calls = PublicLazyRuntimeCalls()
        let source = RetainedLazyListDataSource<Int, [ViewNode]>()
        XCTAssertTrue(
            source.replaceData(values, id: \.self, identityRoot: identity) { value, prefix in
                calls.values.append(value)
                return (heights[value] ?? [20]).enumerated().flatMap { leaf, height -> [ViewNode] in
                    let node = ViewNode(preferredSize: Size(width: 120, height: height))
                    let rowIdentity = prefix.appending(.slot(leaf))
                    node.retainedViewIdentity = rowIdentity.appending(.role(.row))
                    node.dynamicContentIndex = value
                    node.accessibilityIdentifier = "row-\(value)-\(leaf)"
                    if let alternatingBackground {
                        node.retainedLazyListRowChrome = RetainedLazyListRowChrome(
                            alternatingBackground: alternatingBackground)
                    }
                    guard let styles = gaps[value], styles.indices.contains(leaf) else { return [node] }
                    let gap = ViewNode(clipsToBounds: true, preferredSize: Size(width: 120, height: 0))
                    gap.retainedViewIdentity = rowIdentity.appending(.role(.background))
                    gap.retainedLazyListGap = styles[leaf]
                    gap.isSeparatorRule = true
                    gap.isAccessibilityHidden = true
                    return [gap, node]
                }
            })
        let adapter = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter(
                provider: source, estimatedExtent: 20, prefetchExtent: 0,
                maximumMountedRecords: 16, maximumMountedLeaves: 32, maximumProtectedRecords: 2,
                interLeafSpacing: spacing))
        let list = ViewNode(layoutMode: .lazyStack(.vertical(spacing: spacing, alignment: .stretch)))
        list.retainedViewIdentity = identity
        list.retainedLazyListAdapter = adapter
        list.retainedSubtreeBuildLease = PublicLazyRuntimeLease()
        let scroll = ViewNode(
            frame: Rect(x: 0, y: 0, width: 120, height: height), clipsToBounds: true,
            layoutMode: .stack(.vertical(spacing: 0, padding: padding, alignment: .stretch)),
            scrollAxis: .vertical, children: [list])
        let runtime = RetainedViewRuntime(root: scroll)
        runtime.clock = { 0 }
        XCTAssertTrue(runtime.configureLazyListResolutionBudget(elementLimit: 32, roundLimit: 8))
        self.calls = calls
        self.source = source
        self.adapter = adapter
        self.list = list
        self.scroll = scroll
        self.runtime = runtime
    }

    func close() { source.close() }
}

@MainActor
private final class PublicLazyPendingRequest {
    private weak var runtime: RetainedViewRuntime?
    private var target: RetainedLazyListAccessibilityItem?
    private let settlementOwner = RetainedLazyListLogicalRealizationOwner()
    private var isWaitingForIdle = false
    private(set) var pendingCount = 0
    private(set) var completedCount = 0
    private(set) var completedIndex: Int?
    private(set) var completedWhileIdle = false

    init(runtime: RetainedViewRuntime, target: RetainedLazyListAccessibilityItem) {
        self.runtime = runtime
        self.target = target
    }

    func schedule() {
        runtime?.scheduleAfterLayout(key: "public-lazy-pending-target") { [weak self] in
            self?.resume()
        }
    }

    private func resume() {
        guard let runtime, let target else { return }
        runtime.withLazyListResolutionBudget {
            switch runtime.resolveLazyListTarget(target) {
            case .ready(let nodes):
                guard runtime.canPrepareLayoutSettlement else {
                    if !isWaitingForIdle {
                        isWaitingForIdle = true
                        runtime.scheduleAfterLazyListLayout(owner: settlementOwner) { [weak self] in
                            guard let self else { return }
                            self.isWaitingForIdle = false
                            self.resume()
                        }
                    }
                    return
                }
                completedIndex = nodes.first(where: { !$0.isSeparatorRule })?.dynamicContentIndex
                completedCount += 1
                completedWhileIdle = true
                cancel()
            case .pending:
                pendingCount += 1
                schedule()
            case .empty, .obsolete, .unsupported:
                cancel()
            }
        }
    }

    func cancel() {
        if let target { runtime?.releaseLazyListTarget(target) }
        target = nil
    }
}

@MainActor
private final class PublicLazyRuntimeLease: RetainedSubtreeBuildLease {
    var canBuild: Bool { true }
    func beginBuild() -> (any RetainedBuildEpoch)? { PublicLazyRuntimeEpoch() }
}

@MainActor
private final class PublicLazyRuntimeEpoch: RetainedBuildEpoch {
    private var prepared = false
    private var wasSuperseded = false
    var canAdopt: Bool { !prepared && !wasSuperseded }
    func supersede() { if !prepared { wasSuperseded = true } }
    func willAdopt() -> Bool {
        guard canAdopt else { return false }
        prepared = true
        return true
    }
    func commit() {}
    func abandon() {}
    func finishAfterCallbacks() {}
}
