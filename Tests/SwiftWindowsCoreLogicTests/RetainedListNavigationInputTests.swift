import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsLayout
import XCTest

@testable import SwiftWindowsUI

/// Headless input calls exercise the List receipt without borrowing UIA
/// authority. No native window or physical input is created by these fixtures.
@MainActor
final class RetainedListNavigationInputTests: XCTestCase {
    func testMatchingIndicatorCancellationCompletesBeforeDeferredFocus() async throws {
        let fixture = ListNavigationInputFixture()
        defer { fixture.retire() }
        fixture.runtime.pointerMoved(to: fixture.firstHoverPoint)
        let thumb = try fixture.beginIndicatorDrag()
        fixture.clock.value = 10.05
        _ = fixture.runtime.tickAnimations(at: fixture.clock.value)
        let receipt = try fixture.prepareNavigation(to: 99)

        XCTAssertTrue(receipt.finishNavigation())
        XCTAssertEqual(fixture.probe.firstHoverExits, 1)
        XCTAssertFalse(fixture.firstHover.isHovered)
        XCTAssertGreaterThan(fixture.list.scrollOffset, 3_000)
        XCTAssertFalse(fixture.rows[99].isLayoutDeferredByVirtualization)
        XCTAssertTrue(fixture.runtime.focusedNode === fixture.rows[99])

        let acceptedOffset = fixture.list.scrollOffset
        fixture.runtime.pointerMoved(to: Point(x: thumb.x, y: thumb.y + 25))
        XCTAssertEqual(fixture.list.scrollOffset, acceptedOffset, "The cancelled thumb must not keep dragging")
        XCTAssertFalse(receipt.finishNavigation(), "A completed receipt cannot perform a second navigation")
    }

    func testNestedHoverInstallationSurvivesListCancellationAndStopsOldNavigation() async throws {
        let fixture = ListNavigationInputFixture()
        defer { fixture.retire() }
        fixture.runtime.pointerMoved(to: fixture.firstHoverPoint)
        _ = try fixture.beginIndicatorDrag()
        fixture.firstHover.onPointerExit = { [weak fixture] in
            guard let fixture else { return }
            fixture.probe.firstHoverExits += 1
            fixture.firstHover.onPointerExit = nil
            fixture.runtime.pointerMoved(to: fixture.secondHoverPoint)
        }
        let receipt = try fixture.prepareNavigation(to: 99)

        XCTAssertFalse(receipt.finishNavigation())
        XCTAssertEqual(fixture.probe.firstHoverExits, 1)
        XCTAssertEqual(fixture.probe.secondHoverEnters, 1)
        XCTAssertTrue(fixture.secondHover.isHovered)
        XCTAssertEqual(fixture.list.scrollOffset, 0)
        XCTAssertNil(fixture.runtime.focusedNode)

        // Checking the flag alone misses legacy hoveredNode=nil overwrites.
        // The public exit must still find and retire the newly installed B.
        fixture.runtime.pointerExitedWindow()
        XCTAssertEqual(fixture.probe.secondHoverExits, 1)
        XCTAssertFalse(fixture.secondHover.isHovered)
        XCTAssertFalse(receipt.finishNavigation())
        XCTAssertEqual(fixture.list.scrollOffset, 0)
    }

    func testMixedPressAndIndicatorOwnershipRejectsWithoutTakingOverCleanup() async throws {
        let fixture = ListNavigationInputFixture()
        defer { fixture.retire() }
        _ = try fixture.beginIndicatorDrag()
        fixture.runtime.pointerDown(at: fixture.firstHoverPoint)
        XCTAssertEqual(fixture.runtime.interactionPhase(for: fixture.firstHover), .pressed)
        let receipt = try fixture.prepareNavigation(to: 99)

        XCTAssertFalse(receipt.finishNavigation())
        XCTAssertEqual(fixture.list.scrollOffset, 0)
        XCTAssertEqual(fixture.runtime.interactionPhase(for: fixture.firstHover), .pressed)
        XCTAssertEqual(fixture.probe.firstHoverExits, 0)
        XCTAssertEqual(fixture.probe.pointerUpsOutside, 0)
        XCTAssertNil(fixture.runtime.focusedNode)

        fixture.runtime.pointerCancelled()
        XCTAssertEqual(fixture.probe.pointerUpsOutside, 1, "The original input owner still owns its cancellation")
        XCTAssertEqual(fixture.list.scrollOffset, 0)
    }

    func testScrollPhaseHistoryDestructionCannotAuthorizeTrailingFocus() async throws {
        let fixture = ListNavigationInputFixture()
        defer { fixture.retire() }
        let probe = installPhaseHistoryPayload(on: fixture)
        let receipt = try fixture.prepareNavigation(to: 99)
        XCTAssertNotNil(probe.payload)

        XCTAssertFalse(receipt.finishNavigation())
        XCTAssertEqual(probe.cleanups, 1)
        XCTAssertNil(probe.payload)
        XCTAssertGreaterThan(fixture.list.scrollOffset, 3_000, "The offset was accepted before history retired")
        XCTAssertTrue(fixture.runtime.focusedNode === fixture.sentinel)
        XCTAssertTrue(fixture.rows[99].isLayoutDeferredByVirtualization)
        XCTAssertEqual(fixture.probe.targetFocusEntries, 0)

        _ = fixture.runtime.renderFrame(at: fixture.clock.value)
        XCTAssertFalse(fixture.rows[99].isLayoutDeferredByVirtualization)
        XCTAssertTrue(fixture.runtime.focusedNode === fixture.sentinel)
        XCTAssertEqual(fixture.probe.targetFocusEntries, 0)
        XCTAssertEqual(probe.cleanups, 1)
    }

    func testClockCaptureDestructionSupersedesBeforeTheOffsetWrite() async throws {
        let fixture = ListNavigationInputFixture()
        defer { fixture.retire() }
        let receipt = try fixture.prepareNavigation(to: 99)
        let probe = installReplacingClock(on: fixture)
        XCTAssertNotNil(probe.payload)

        XCTAssertFalse(receipt.finishNavigation())
        XCTAssertEqual(probe.clockCalls, 1)
        XCTAssertEqual(probe.cleanups, 1)
        XCTAssertNil(probe.payload)
        XCTAssertEqual(fixture.list.scrollOffset, 0)
        XCTAssertTrue(fixture.runtime.focusedNode === fixture.sentinel)
        XCTAssertTrue(fixture.rows[99].isLayoutDeferredByVirtualization)
        XCTAssertEqual(fixture.probe.targetFocusEntries, 0)
        XCTAssertFalse(receipt.finishNavigation())
        XCTAssertEqual(probe.clockCalls, 1)
    }

    func testUnsettledPreparationDoesNotDrainAnotherRoundOrRetryItsReceipt() async throws {
        let fixture = ListNavigationInputFixture()
        defer { fixture.retire() }
        let receipt = try fixture.prepareNavigation(to: 99)
        fixture.runtime.scheduleAfterLayout(key: "list-input-first-round") { [weak fixture] in
            guard let fixture else { return }
            fixture.probe.layoutCallbacks += 1
            fixture.runtime.scheduleAfterLayout(key: "list-input-next-round") { [weak fixture] in
                fixture?.probe.layoutCallbacks += 1
            }
        }

        XCTAssertFalse(receipt.finishNavigation())
        XCTAssertEqual(fixture.probe.layoutCallbacks, 1)
        XCTAssertEqual(fixture.list.scrollOffset, 0)
        XCTAssertNil(fixture.runtime.focusedNode)
        XCTAssertTrue(fixture.rows[99].isLayoutDeferredByVirtualization)
        XCTAssertFalse(receipt.finishNavigation())
        XCTAssertEqual(fixture.probe.layoutCallbacks, 1)

        _ = fixture.runtime.renderFrame(at: fixture.clock.value)
        XCTAssertEqual(fixture.probe.layoutCallbacks, 2)
        XCTAssertNil(fixture.runtime.focusedNode)
        XCTAssertEqual(fixture.list.scrollOffset, 0)
        XCTAssertFalse(receipt.finishNavigation())
    }

    func testQueuedRevealRunsOnceAndCannotBorrowANewerFocusIntent() async throws {
        for supersede in [false, true] {
            let fixture = ListNavigationInputFixture()
            defer { fixture.retire() }
            let receipt = try fixture.prepareNavigation(to: 1)
            XCTAssertTrue(receipt.finishNavigation())
            XCTAssertTrue(fixture.runtime.focusedNode === fixture.rows[1])
            fixture.probe.clockCalls = 0
            fixture.runtime.clock = { [weak probe = fixture.probe] in
                probe?.clockCalls += 1
                return 10
            }
            fixture.runtime.scheduleListNavigationReveal(
                key: "list-input-one-reveal", target: fixture.rows[1], receipt: receipt)
            if supersede { fixture.runtime.requestFocus(fixture.sentinel) }

            XCTAssertNotNil(fixture.runtime.resolvedLayoutFrame(of: fixture.root))
            XCTAssertEqual(fixture.probe.clockCalls, supersede ? 0 : 1)
            XCTAssertTrue(fixture.runtime.focusedNode === (supersede ? fixture.sentinel : fixture.rows[1]))
            XCTAssertNotNil(fixture.runtime.resolvedLayoutFrame(of: fixture.root))
            XCTAssertEqual(fixture.probe.clockCalls, supersede ? 0 : 1, "Replay must not enqueue itself")
        }
    }

    func testClockLayoutResolutionCannotRefreshThePreparedSettlementProof() async throws {
        let fixture = ListNavigationInputFixture()
        defer { fixture.retire() }
        let source = fixture.rows[0]
        let target = fixture.rows[99]
        XCTAssertFalse(source.isLayoutDeferredByVirtualization)
        XCTAssertGreaterThanOrEqual(source.resolvedFrame.origin.y, 0)
        XCTAssertLessThan(source.resolvedFrame.origin.y, fixture.list.resolvedFrame.size.height)
        fixture.runtime.requestFocus(source)
        XCTAssertTrue(fixture.runtime.focusedNode === source)
        XCTAssertTrue(source.isFocused)
        XCTAssertEqual(fixture.list.frame.size.height, 120)
        fixture.list.frame = Rect(x: 0, y: 0, width: 240, height: 121)
        XCTAssertEqual(fixture.list.frame.size.height, 121)
        XCTAssertTrue(fixture.runtime.hasPendingLayout)
        let receipt = try fixture.prepareNavigation(to: 99)
        let focusRevisionBeforeNavigation = fixture.runtime.presentationFocusRevision
        var layoutQueryCount = 0
        var originalCurrentBeforeQuery: [Bool] = []
        var originalCurrentAfterQuery: [Bool] = []
        var freshCurrentAfterQuery: [Bool] = []
        var pendingBeforeQuery: [Bool] = []
        var pendingAfterQuery: [Bool] = []
        fixture.runtime.clock = {
            [weak runtime = fixture.runtime, weak target, weak list = fixture.list, weak probe = fixture.probe] in
            guard let runtime, let target, let list, let probe else {
                XCTFail("The fixture must survive the clock's layout query")
                return 10
            }
            probe.clockCalls += 1
            guard case .settled(let original) = runtime.layoutSettlementStatus else {
                XCTFail("Navigation must establish its original settlement before sampling the clock")
                return 10
            }
            originalCurrentBeforeQuery.append(runtime.isLayoutSettlementReceiptCurrent(original))
            pendingBeforeQuery.append(runtime.hasPendingLayout)
            XCTAssertTrue(target.hasListNavigationRuntime(runtime))
            XCTAssertTrue(target.parent === list)
            let targetFrameBeforeQuery = target.resolvedFrame
            let listFrameBeforeQuery = list.resolvedFrame
            let focusedBeforeQuery = runtime.focusedNode
            let focusRevisionBeforeQuery = runtime.presentationFocusRevision
            let offsetBeforeQuery = list.scrollOffset

            // A new resolution must stale the original proof even when
            // geometry, focus, and scroll intent stay unchanged by the query.
            layoutQueryCount += 1
            XCTAssertNotNil(runtime.resolvedLayoutFrame(of: target))

            pendingAfterQuery.append(runtime.hasPendingLayout)
            XCTAssertTrue(target.hasListNavigationRuntime(runtime))
            XCTAssertTrue(target.parent === list)
            XCTAssertEqual(target.resolvedFrame, targetFrameBeforeQuery)
            XCTAssertEqual(list.resolvedFrame, listFrameBeforeQuery)
            XCTAssertTrue(runtime.focusedNode === focusedBeforeQuery)
            XCTAssertEqual(runtime.presentationFocusRevision, focusRevisionBeforeQuery)
            XCTAssertEqual(list.scrollOffset, offsetBeforeQuery)
            originalCurrentAfterQuery.append(runtime.isLayoutSettlementReceiptCurrent(original))
            guard case .settled(let fresh) = runtime.layoutSettlementStatus else {
                XCTFail("The extra query must produce its own successful settlement")
                return 10
            }
            freshCurrentAfterQuery.append(runtime.isLayoutSettlementReceiptCurrent(fresh))
            return 10
        }

        XCTAssertFalse(receipt.finishNavigation())

        XCTAssertEqual(fixture.probe.clockCalls, 1)
        XCTAssertEqual(layoutQueryCount, 1)
        XCTAssertEqual(originalCurrentBeforeQuery, [true])
        XCTAssertEqual(originalCurrentAfterQuery, [false])
        XCTAssertEqual(freshCurrentAfterQuery, [true])
        XCTAssertEqual(pendingBeforeQuery, [true])
        XCTAssertEqual(pendingAfterQuery, [true])
        XCTAssertEqual(fixture.list.scrollOffset, 0)
        XCTAssertTrue(fixture.runtime.focusedNode === source)
        XCTAssertTrue(source.isFocused)
        XCTAssertEqual(fixture.runtime.presentationFocusRevision, focusRevisionBeforeNavigation)
        XCTAssertFalse(target.isFocused)
        XCTAssertTrue(target.isLayoutDeferredByVirtualization)
        XCTAssertEqual(fixture.probe.targetFocusEntries, 0)

        XCTAssertFalse(receipt.finishNavigation())
        XCTAssertEqual(fixture.probe.clockCalls, 1)
        XCTAssertEqual(layoutQueryCount, 1)
        XCTAssertEqual(fixture.list.scrollOffset, 0)
        XCTAssertTrue(fixture.runtime.focusedNode === source)
        XCTAssertFalse(target.isFocused)
        XCTAssertEqual(fixture.probe.targetFocusEntries, 0)
    }

    private func installPhaseHistoryPayload(on fixture: ListNavigationInputFixture) -> ListNavigationInputProbe {
        let probe = ListNavigationInputProbe()
        fixture.list.observeScrollGeometry(
            of: { _ in ListNavigationObservedValue(marker: 0, payload: nil) },
            action: { _, _ in })
        fixture.list.observeScrollPhase { _, _, _ in }
        let payload = ListNavigationInputPayload { [weak fixture, weak probe] in
            guard let fixture, let probe else {
                return XCTFail("The fixture and probe must survive cached history cleanup")
            }
            probe.cleanups += 1
            fixture.runtime.requestFocus(fixture.sentinel)
        }
        probe.payload = payload
        // No source has been sampled by a paint since this registration. Its
        // first phase bookkeeping selects the List and retires the old Any.
        fixture.list.scrollObserverStorage?.geometry.first?.previousValue =
            ListNavigationObservedValue(marker: 1, payload: payload)
        return probe
    }

    private func installReplacingClock(on fixture: ListNavigationInputFixture) -> ListNavigationInputProbe {
        let probe = ListNavigationInputProbe()
        let payload = ListNavigationInputPayload { [weak fixture, weak probe] in
            guard let fixture, let probe else {
                return XCTFail("The fixture and probe must survive clock capture cleanup")
            }
            probe.cleanups += 1
            fixture.runtime.requestFocus(fixture.sentinel)
        }
        probe.payload = payload
        fixture.runtime.clock = { [weak runtime = fixture.runtime, weak probe, payload] in
            probe?.clockCalls += 1
            runtime?.clock = { 10 }
            withExtendedLifetime(payload) {}
            return 10
        }
        return probe
    }
}

@MainActor
private final class ListNavigationInputFixture {
    let root: ViewNode
    let list: ViewNode
    let rows: [ViewNode]
    let firstHover: ViewNode
    let secondHover: ViewNode
    let sentinel: ViewNode
    let runtime: RetainedViewRuntime
    let scope: RetainedListNavigationOwner
    let probe = ListNavigationInputProbe()
    let clock = ListNavigationInputClock()
    let firstHoverPoint = Point(x: 280, y: 20)
    let secondHoverPoint = Point(x: 340, y: 20)

    init() {
        rows = (0..<100).map { _ in
            let row = ViewNode(
                preferredSize: Size(width: 220, height: 40), isFocusable: true,
                accessibilityTraits: .isSelectable)
            row.interceptsVerticalArrowKeys = true
            return row
        }
        list = ViewNode(
            frame: Rect(x: 0, y: 0, width: 240, height: 120), clipsToBounds: true,
            layoutMode: .lazyStack(.vertical(spacing: 0)), scrollAxis: .vertical,
            showsScrollIndicator: true, children: rows)
        firstHover = ViewNode(frame: Rect(x: 260, y: 0, width: 40, height: 40))
        secondHover = ViewNode(frame: Rect(x: 320, y: 0, width: 40, height: 40))
        sentinel = ViewNode(frame: Rect(x: 260, y: 60, width: 40, height: 40), isFocusable: true)
        root = ViewNode(
            frame: Rect(x: 0, y: 0, width: 420, height: 160), isHitTestVisible: false,
            children: [list, firstHover, secondHover, sentinel])
        runtime = RetainedViewRuntime(root: root)
        scope = RetainedListNavigationOwner(runtime: runtime)
        scope.install(on: list)
        for row in rows { _ = scope.makeRowOwner(on: row) }
        runtime.clock = { [clock] in clock.value }
        firstHover.onActivate = {}
        firstHover.onPointerEnter = {}
        firstHover.onPointerExit = { [weak probe] in probe?.firstHoverExits += 1 }
        firstHover.onPointerUpOutside = { [weak probe] in probe?.pointerUpsOutside += 1 }
        secondHover.onPointerEnter = { [weak probe] in probe?.secondHoverEnters += 1 }
        secondHover.onPointerExit = { [weak probe] in probe?.secondHoverExits += 1 }
        rows[99].onFocusEnter = { [weak probe] in probe?.targetFocusEntries += 1 }
        _ = runtime.renderFrame(at: clock.value)
        XCTAssertTrue(rows[99].isLayoutDeferredByVirtualization)
        XCTAssertFalse(rows[1].isLayoutDeferredByVirtualization)
    }

    func prepareNavigation(to index: Int) throws -> RetainedListNavigationReceipt {
        let source = try XCTUnwrap(rows[0].listNavigationOwner)
        let target = try XCTUnwrap(rows[index].listNavigationOwner)
        let receipt = try XCTUnwrap(scope.prepareAction(from: source))
        XCTAssertTrue(receipt.prepareTarget(target))
        return receipt
    }

    func beginIndicatorDrag() throws -> Point {
        let track = try XCTUnwrap(
            runtime.currentPrepaintState.deferredDraws.compactMap { draw -> ScrollIndicatorTrack? in
                guard case .scrollIndicator(let payload) = draw.payload, payload.node === list else { return nil }
                return payload.track
            }.first)
        let point = Point(x: track.indicatorRect.midX, y: track.indicatorRect.midY)
        runtime.pointerDown(at: point)
        return point
    }

    func retire() {
        runtime.stopRenderLifecycleCallbacks()
        runtime.clock = { 10 }
        for node in rows + [firstHover, secondHover, sentinel] {
            node.onFocusEnter = nil
            node.onFocusExit = nil
            node.onPointerEnter = nil
            node.onPointerExit = nil
            node.onPointerUpOutside = nil
            node.onActivate = nil
        }
        list.scrollObserverStorage = nil
        runtime.pointerCancelled()
    }
}

@MainActor
private final class ListNavigationInputClock {
    var value = 10.0
}

@MainActor
private final class ListNavigationInputProbe {
    weak var payload: ListNavigationInputPayload?
    var firstHoverExits = 0
    var secondHoverEnters = 0
    var secondHoverExits = 0
    var pointerUpsOutside = 0
    var targetFocusEntries = 0
    var clockCalls = 0
    var cleanups = 0
    var layoutCallbacks = 0
}

@MainActor
private final class ListNavigationInputPayload {
    private let onRelease: @MainActor () -> Void

    init(onRelease: @escaping @MainActor () -> Void) {
        self.onRelease = onRelease
    }

    isolated deinit { onRelease() }
}

private struct ListNavigationObservedValue: Equatable {
    var marker: Int
    var payload: ListNavigationInputPayload?

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.marker == rhs.marker }
}
