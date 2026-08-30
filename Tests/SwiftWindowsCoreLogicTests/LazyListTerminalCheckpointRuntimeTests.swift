import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// These query the mounted runtime and inspect its completed pass without
/// refreshing adapter plans, row ordinals, or accessibility projections.
@MainActor
final class LazyListTerminalCheckpointRuntimeTests: XCTestCase {
    func testAcceptedGrowthSavesTheTerminalRoundWithBudgetStillAvailable() async throws {
        let fixture = TerminalCheckpointRuntimeFixture(secondLeafHeight: 25)
        let host = fixture.host
        defer { host.close() }
        let runtime = host.runtime
        XCTAssertTrue(runtime.configureLazyListResolutionBudget(elementLimit: 8, roundLimit: 4))

        XCTAssertNotNil(host.layout())

        let list = try host.list()
        let adapter = try XCTUnwrap(list.retainedLazyListAdapter)
        XCTAssertEqual(fixture.probe.factories, [0, 1])
        XCTAssertEqual(list.children.map { $0.resolvedFrame.minY }, [0, 5, 30, 35])
        XCTAssertEqual(list.children.map { $0.resolvedFrame.height }, [5, 25, 5, 25])
        XCTAssertTrue(list.children.allSatisfy { $0.parent === list && runtime.accessibilityTarget(for: $0) != nil })
        XCTAssertEqual(adapter.contentExtent, 20_020)
        XCTAssertEqual(list.resolvedContentSize.height, 20_020)
        XCTAssertFalse(adapter.hasUnresolvedWork)
        XCTAssertEqual(runtime.lastLazyListConsumedElements, 2)
        // The query allows four rounds so exhaustion cannot hide an empty third
        // scan. The accepted correction pass itself must prove completion.
        XCTAssertEqual(runtime.lastLazyListConsumedRounds, 2)
        XCTAssertEqual(runtime.lastLazyListWorkCompletion, .complete)
        _ = try settledReceipt(in: runtime)
    }

    func testPendingSettlementCallbackPreventsSkippingItsOrdinaryTerminalRound() async throws {
        let fixture = TerminalCheckpointRuntimeFixture()
        let host = fixture.host
        defer { host.close() }
        let runtime = host.runtime
        let (list, adapter) = try warm(fixture)
        let second = try leaf(at: 1, in: list)
        let owner = TerminalCheckpointRuntimeCallbackOwner()
        var scheduledCalls = 0
        var callbackCalls = 0
        list.onLayout = { [weak runtime, weak adapter] _ in
            guard let runtime, adapter?.contentExtent == 20_010, scheduledCalls == 0 else { return }
            scheduledCalls += 1
            runtime.scheduleAfterLazyListLayout(owner: owner) { callbackCalls += 1 }
        }
        defer { list.onLayout = nil }
        XCTAssertEqual(second.preferredSize, Size(width: 120, height: 15))
        second.preferredSize = Size(width: 120, height: 25)
        XCTAssertTrue(runtime.configureLazyListResolutionBudget(elementLimit: 8, roundLimit: 4))

        XCTAssertNotNil(host.layout())

        XCTAssertEqual(scheduledCalls, 1)
        XCTAssertEqual(callbackCalls, 1, "The real settlement queue must deliver before this query returns")
        XCTAssertEqual(fixture.probe.factories, [0, 1])
        XCTAssertEqual(second.resolvedFrame.height, 25)
        XCTAssertEqual(adapter.contentExtent, 20_010)
        XCTAssertEqual(list.resolvedContentSize.height, 20_010)
        XCTAssertFalse(adapter.hasUnresolvedWork)
        XCTAssertEqual(runtime.lastLazyListConsumedElements, 0)
        XCTAssertEqual(runtime.lastLazyListConsumedRounds, 2)
        XCTAssertEqual(runtime.lastLazyListWorkCompletion, .complete)
        _ = try settledReceipt(in: runtime)
    }

    func testUnresolvedReaderCannotUseAnAcceptedListMeasurementAsSettlement() async throws {
        let fixture = TerminalCheckpointRuntimeFixture()
        let host = fixture.host
        defer { host.close() }
        let runtime = host.runtime
        let (list, adapter) = try warm(fixture)
        let second = try leaf(at: 1, in: list)
        let oldReceipt = try settledReceipt(in: runtime)
        var bodyCalls = 0
        second.geometryReaderBuiltSize = Size(width: 120, height: 15)
        second.geometryReaderBuild = { _, _ in
            bodyCalls += 1
            return []
        }
        defer { second.geometryReaderBuild = nil }
        second.preferredSize = Size(width: 120, height: 25)
        XCTAssertTrue(runtime.configureLazyListResolutionBudget(elementLimit: 0, roundLimit: 4))

        XCTAssertNotNil(host.layout())

        XCTAssertEqual(bodyCalls, 0, "A terminal checkpoint cannot invoke an unpaid reader body")
        XCTAssertEqual(fixture.probe.factories, [0, 1])
        XCTAssertEqual(second.resolvedFrame.size, Size(width: 120, height: 25))
        XCTAssertEqual(second.geometryReaderBuiltSize, Size(width: 120, height: 15))
        XCTAssertEqual(adapter.contentExtent, 20_010)
        XCTAssertEqual(runtime.lastLazyListConsumedElements, 0)
        XCTAssertEqual(runtime.lastLazyListConsumedRounds, 2)
        XCTAssertEqual(runtime.lastLazyListWorkCompletion, .budgetExhausted)
        XCTAssertFalse(runtime.isLayoutSettlementReceiptCurrent(oldReceipt))
        assertNoSettledReceipt(in: runtime)
    }

    func testAnchorClampCannotSkipTheNextIndependentLayoutPass() async throws {
        let fixture = TerminalCheckpointRuntimeFixture(rowCount: 5, prefetchExtent: 40, viewportHeight: 60)
        let host = fixture.host
        defer { host.close() }
        let runtime = host.runtime
        let (list, adapter) = try warm(fixture)
        XCTAssertEqual(fixture.probe.factories, [0, 1, 2, 3, 4])
        try host.scroll(to: 40)
        let scroll = try host.scrollContainer()
        let oldReceipt = try settledReceipt(in: runtime)
        let last = try leaf(at: 9, in: list)
        XCTAssertEqual(last.preferredSize, Size(width: 120, height: 15))
        XCTAssertEqual(scroll.scrollOffset, 40)
        XCTAssertEqual(scroll.resolvedScrollOffset, 40)
        last.preferredSize = Size(width: 120, height: 5)
        XCTAssertTrue(runtime.configureLazyListResolutionBudget(elementLimit: 8, roundLimit: 1))

        XCTAssertNotNil(host.layout())

        XCTAssertEqual(fixture.probe.factories, [0, 1, 2, 3, 4])
        XCTAssertEqual(last.resolvedFrame.height, 5)
        XCTAssertEqual(adapter.contentExtent, 90)
        XCTAssertEqual(list.resolvedContentSize.height, 90)
        XCTAssertEqual(scroll.scrollOffset, 30)
        XCTAssertEqual(scroll.resolvedScrollOffset, 30)
        XCTAssertEqual(runtime.lastLazyListConsumedElements, 0)
        XCTAssertEqual(runtime.lastLazyListConsumedRounds, 1)
        XCTAssertEqual(runtime.lastLazyListWorkCompletion, .budgetExhausted)
        XCTAssertFalse(runtime.isLayoutSettlementReceiptCurrent(oldReceipt))
        assertNoSettledReceipt(in: runtime)

        // Only after the failed pass is observed does a separate request receive
        // its own one-round allowance to verify the clamped viewport.
        XCTAssertNotNil(host.layout())

        XCTAssertEqual(fixture.probe.factories, [0, 1, 2, 3, 4])
        XCTAssertEqual(scroll.scrollOffset, 30)
        XCTAssertEqual(scroll.resolvedScrollOffset, 30)
        XCTAssertEqual(runtime.lastLazyListConsumedElements, 0)
        XCTAssertEqual(runtime.lastLazyListConsumedRounds, 1)
        XCTAssertEqual(runtime.lastLazyListWorkCompletion, .complete)
        _ = try settledReceipt(in: runtime)
    }

    func testGeometryChangedThenRestoredDuringCorrectionCannotSettleThatPass() async throws {
        let fixture = TerminalCheckpointRuntimeFixture()
        let host = fixture.host
        defer { host.close() }
        let runtime = host.runtime
        let (list, adapter) = try warm(fixture)
        let second = try leaf(at: 1, in: list)
        let oldReceipt = try settledReceipt(in: runtime)
        let originalFrame = runtime.root.frame
        var interventions = 0
        list.onLayout = { [weak runtime, weak adapter] _ in
            guard let runtime, adapter?.contentExtent == 20_010, interventions == 0 else { return }
            interventions += 1
            runtime.root.frame = Rect(
                x: originalFrame.minX, y: originalFrame.minY,
                width: originalFrame.width + 1, height: originalFrame.height)
            runtime.root.frame = originalFrame
        }
        defer { list.onLayout = nil }
        second.preferredSize = Size(width: 120, height: 25)
        XCTAssertTrue(runtime.configureLazyListResolutionBudget(elementLimit: 8, roundLimit: 4))

        XCTAssertNotNil(host.layout())

        XCTAssertEqual(interventions, 1)
        XCTAssertEqual(runtime.root.frame, originalFrame)
        XCTAssertEqual(fixture.probe.factories, [0, 1])
        XCTAssertEqual(runtime.lastLazyListConsumedElements, 0)
        XCTAssertEqual(runtime.lastLazyListConsumedRounds, 2, "The invalid pass cannot skip the terminal check")
        XCTAssertFalse(runtime.isLayoutSettlementReceiptCurrent(oldReceipt))
        assertNoSettledReceipt(in: runtime)

        // This is a new ordinary query, not part of the assertions above.
        XCTAssertNotNil(host.layout())

        XCTAssertEqual(interventions, 1)
        XCTAssertEqual(fixture.probe.factories, [0, 1])
        XCTAssertEqual(runtime.lastLazyListConsumedElements, 0)
        XCTAssertFalse(runtime.isLayoutSettlementReceiptCurrent(oldReceipt))
        _ = try settledReceipt(in: runtime)
    }

    func testEqualChromeResetDuringCorrectionCannotPublishASettledReceipt() async throws {
        let fixture = TerminalCheckpointRuntimeFixture()
        let host = fixture.host
        defer { host.close() }
        let runtime = host.runtime
        let (list, adapter) = try warm(fixture)
        let first = try leaf(at: 0, in: list)
        let second = try leaf(at: 1, in: list)
        let chrome = RetainedLazyListRowChrome(alternatingBackground: .blue)
        first.backgroundColor = nil
        first.cornerRadius = 0
        first.retainedLazyListRowChrome = chrome
        XCTAssertNotNil(host.layout())
        XCTAssertEqual(first.retainedLazyListRowChromeUsesEstimatedParity, false)
        let oldReceipt = try settledReceipt(in: runtime)
        var resets = 0
        list.onLayout = { [weak first, weak adapter] _ in
            guard let first, adapter?.contentExtent == 20_010, resets == 0 else { return }
            resets += 1
            first.retainedLazyListRowChrome = chrome
        }
        defer { list.onLayout = nil }
        second.preferredSize = Size(width: 120, height: 25)
        XCTAssertTrue(runtime.configureLazyListResolutionBudget(elementLimit: 8, roundLimit: 4))

        XCTAssertNotNil(host.layout())

        XCTAssertEqual(resets, 1)
        XCTAssertEqual(first.retainedLazyListRowChrome, chrome)
        XCTAssertNil(first.retainedLazyListRowChromeUsesEstimatedParity)
        XCTAssertNil(first.backgroundColor)
        XCTAssertEqual(first.cornerRadius, 0)
        XCTAssertEqual(fixture.probe.factories, [0, 1])
        XCTAssertEqual(runtime.lastLazyListConsumedElements, 0)
        XCTAssertEqual(runtime.lastLazyListConsumedRounds, 2, "Unpublished chrome cannot skip the terminal check")
        XCTAssertFalse(runtime.isLayoutSettlementReceiptCurrent(oldReceipt))
        assertNoSettledReceipt(in: runtime)
    }

    func testChromePredicateReadsPublishedParityAndConfidenceWithoutMutation() async throws {
        let fixture = TerminalCheckpointRuntimeFixture()
        let host = fixture.host
        defer { host.close() }
        let (list, _) = try warm(fixture)
        let first = try leaf(at: 0, in: list)
        let chrome = RetainedLazyListRowChrome(alternatingBackground: .blue)
        first.backgroundColor = nil
        first.cornerRadius = 0
        first.retainedLazyListRowChrome = chrome

        for _ in 0..<3 {
            XCTAssertFalse(first.hasCurrentRetainedLazyListRowChrome(isOdd: false, hasUnknownPrefix: false))
            XCTAssertNil(first.retainedLazyListRowChromeUsesEstimatedParity)
            XCTAssertEqual(first.retainedLazyListRowChrome, chrome)
            XCTAssertNil(first.backgroundColor)
            XCTAssertEqual(first.cornerRadius, 0)
        }

        XCTAssertNotNil(host.layout())

        for _ in 0..<3 {
            XCTAssertTrue(first.hasCurrentRetainedLazyListRowChrome(isOdd: false, hasUnknownPrefix: false))
            XCTAssertFalse(first.hasCurrentRetainedLazyListRowChrome(isOdd: true, hasUnknownPrefix: false))
            XCTAssertFalse(first.hasCurrentRetainedLazyListRowChrome(isOdd: false, hasUnknownPrefix: true))
            XCTAssertEqual(first.retainedLazyListRowChromeUsesEstimatedParity, false)
            XCTAssertEqual(first.retainedLazyListRowChrome, chrome)
            XCTAssertNil(first.backgroundColor)
            XCTAssertEqual(first.cornerRadius, 0)
        }

        first.backgroundColor = .red

        for _ in 0..<3 {
            XCTAssertTrue(first.hasCurrentRetainedLazyListRowChrome(isOdd: false, hasUnknownPrefix: false))
            XCTAssertFalse(first.hasCurrentRetainedLazyListRowChrome(isOdd: false, hasUnknownPrefix: true))
            XCTAssertEqual(first.retainedLazyListRowChromeUsesEstimatedParity, false)
            XCTAssertEqual(first.retainedLazyListRowChrome, chrome)
            XCTAssertEqual(first.backgroundColor, .red)
            XCTAssertEqual(first.cornerRadius, 0)
        }

        first.retainedLazyListRowChrome = chrome

        for _ in 0..<3 {
            XCTAssertFalse(first.hasCurrentRetainedLazyListRowChrome(isOdd: false, hasUnknownPrefix: false))
            XCTAssertNil(first.retainedLazyListRowChromeUsesEstimatedParity)
            XCTAssertEqual(first.retainedLazyListRowChrome, chrome)
            XCTAssertEqual(first.backgroundColor, .red)
            XCTAssertEqual(first.cornerRadius, 0)
        }
        XCTAssertEqual(fixture.probe.factories, [0, 1])
    }

    private func warm(
        _ fixture: TerminalCheckpointRuntimeFixture,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> (ViewNode, RetainedLazyListRuntimeAdapter) {
        let runtime = fixture.host.runtime
        XCTAssertTrue(runtime.configureLazyListResolutionBudget(elementLimit: 8, roundLimit: 4), file: file, line: line)
        XCTAssertNotNil(fixture.host.layout(), file: file, line: line)
        let list = try fixture.host.list(file: file, line: line)
        let adapter = try XCTUnwrap(list.retainedLazyListAdapter, file: file, line: line)
        XCTAssertFalse(adapter.hasUnresolvedWork, file: file, line: line)
        XCTAssertEqual(runtime.lastLazyListWorkCompletion, .complete, file: file, line: line)
        _ = try settledReceipt(in: runtime, file: file, line: line)
        return (list, adapter)
    }

    private func leaf(
        at index: Int, in list: ViewNode,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> ViewNode {
        try XCTUnwrap(list.children.indices.contains(index) ? list.children[index] : nil, file: file, line: line)
    }

    private func settledReceipt(
        in runtime: RetainedViewRuntime,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> RetainedLayoutSettlementReceipt {
        var receipt: RetainedLayoutSettlementReceipt?
        if case .settled(let current) = runtime.layoutSettlementStatus { receipt = current }
        let current = try XCTUnwrap(receipt, "Expected a settled current layout", file: file, line: line)
        XCTAssertTrue(runtime.isLayoutSettlementReceiptCurrent(current), file: file, line: line)
        return current
    }

    private func assertNoSettledReceipt(
        in runtime: RetainedViewRuntime,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        if case .settled = runtime.layoutSettlementStatus {
            XCTFail("This pass did not prove a current global settlement", file: file, line: line)
        }
    }
}

@MainActor
private final class TerminalCheckpointRuntimeFixture {
    let probe: TerminalCheckpointRuntimeProbe
    let host: MountedLazyListTestHost

    init(
        rowCount: Int = 1000, secondLeafHeight: Double = 15,
        prefetchExtent: Double = 0, viewportHeight: Double = 40
    ) {
        let probe = TerminalCheckpointRuntimeProbe(secondLeafHeight: secondLeafHeight)
        self.probe = probe
        host = MountedLazyListTestHost(size: Size(width: 120, height: viewportHeight)) {
            ManagedLazyListContent(
                Array(0..<rowCount), id: \.self, estimatedExtent: 20, prefetchExtent: prefetchExtent,
                maximumMountedRecords: 8, maximumMountedLeaves: 16, maximumProtectedRecords: 2
            ) { probe.makeRows($0) }
        }
    }
}

@MainActor
private final class TerminalCheckpointRuntimeProbe {
    let secondLeafHeight: Double
    var factories: [Int] = []

    init(secondLeafHeight: Double) { self.secondLeafHeight = secondLeafHeight }

    func makeRows(_ id: Int) -> [AnyView] {
        factories.append(id)
        return [
            AnyView(Color.blue.frame(width: 120, height: 5)),
            AnyView(Color.red.frame(width: 120, height: secondLeafHeight)),
        ]
    }
}

@MainActor
private final class TerminalCheckpointRuntimeCallbackOwner {}
