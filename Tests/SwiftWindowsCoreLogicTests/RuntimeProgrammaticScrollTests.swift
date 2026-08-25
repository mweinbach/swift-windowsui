import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsLayout
import XCTest

@testable import SwiftWindowsUI

/// Programmatic scrolling belongs to retained layout, including rows whose
/// lazy descendants have never received an individual layout callback.
@MainActor
final class RuntimeProgrammaticScrollTests: XCTestCase {
    private struct ScrollFixture {
        let runtime: RetainedViewRuntime
        let container: ViewNode
        let rows: [ViewNode]
        let nestedTargets: [ViewNode]
    }

    private func fixture(
        axis: ScrollAxis = .vertical,
        lazy: Bool = false,
        nestedTargets: Bool = false,
        count: Int = 20,
        render: Bool = true
    ) -> ScrollFixture {
        let targetColor = Color(red: 1, green: 0, blue: 0, alpha: 1)
        let extent: Double = 30
        let viewport: Double = 70
        var targets: [ViewNode] = []
        let rows = (0..<count).map { index -> ViewNode in
            let target = ViewNode()
            targets.append(target)
            return ViewNode(
                backgroundColor: index == count - 1 ? targetColor : nil,
                preferredSize: axis == .vertical
                    ? Size(width: 90, height: extent)
                    : Size(width: extent, height: 70),
                isHitTestVisible: false,
                children: nestedTargets ? [target] : []
            )
        }
        let layout =
            axis == .vertical
            ? StackLayout.vertical(spacing: 0)
            : StackLayout.horizontal(spacing: 0)
        let container = ViewNode(
            frame: axis == .vertical
                ? Rect(x: 10, y: 10, width: 90, height: viewport)
                : Rect(x: 10, y: 10, width: viewport, height: 70),
            clipsToBounds: true,
            layoutMode: lazy ? .lazyStack(layout) : .stack(layout),
            scrollAxis: axis,
            isHitTestVisible: false,
            children: rows
        )
        let root = ViewNode(
            frame: Rect(x: 0, y: 0, width: 140, height: 110),
            isHitTestVisible: false,
            children: [container]
        )
        let runtime = RetainedViewRuntime(root: root)
        if render {
            _ = runtime.renderScene()
        }
        return ScrollFixture(runtime: runtime, container: container, rows: rows, nestedTargets: targets)
    }

    private func oversizedDeferredFixture() -> (
        runtime: RetainedViewRuntime,
        container: ViewNode,
        row: ViewNode,
        target: ViewNode
    ) {
        let target = ViewNode(
            frame: Rect(x: 0, y: 200, width: 80, height: 20),
            backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1),
            preferredSize: Size(width: 80, height: 20)
        )
        let row = ViewNode(
            preferredSize: Size(width: 80, height: 300),
            isHitTestVisible: false,
            children: [target]
        )
        let preceding = (0..<10).map { _ in
            ViewNode(preferredSize: Size(width: 80, height: 40), isHitTestVisible: false)
        }
        let trailing = (0..<4).map { _ in
            ViewNode(preferredSize: Size(width: 80, height: 40), isHitTestVisible: false)
        }
        let container = ViewNode(
            frame: Rect(x: 0, y: 0, width: 100, height: 100),
            clipsToBounds: true,
            layoutMode: .lazyStack(.vertical(spacing: 0)),
            scrollAxis: .vertical,
            isHitTestVisible: false,
            children: preceding + [row] + trailing
        )
        let runtime = RetainedViewRuntime(
            root: ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 100),
                isHitTestVisible: false,
                children: [container]
            )
        )
        _ = runtime.renderScene()
        return (runtime, container, row, target)
    }

    func testRequestBeforeFirstLayoutDefersAndThenUsesMinimalVerticalReveal() async {
        let result = fixture(render: false)

        XCTAssertFalse(result.runtime.hasCompletedLayout)
        XCTAssertFalse(result.runtime.scrollToDescendant(result.rows[5]))
        XCTAssertEqual(result.container.scrollOffset, 0)

        _ = result.runtime.renderScene()
        XCTAssertTrue(result.runtime.hasCompletedLayout)
        XCTAssertFalse(result.runtime.isLayoutInProgress)
        XCTAssertTrue(result.runtime.scrollToDescendant(result.rows[5]))
        XCTAssertEqual(result.container.scrollOffset, 110, accuracy: 0.0001)

        XCTAssertTrue(result.runtime.scrollToDescendant(result.rows[4]))
        XCTAssertEqual(
            result.container.scrollOffset,
            110,
            accuracy: 0.0001,
            "an already-visible target must not introduce unnecessary movement"
        )
    }

    func testExplicitVerticalAnchorsAlignTargetAndViewportAndClampContentBounds() async {
        let result = fixture()

        XCTAssertTrue(result.runtime.scrollToDescendant(result.rows[5], anchorY: 0))
        XCTAssertEqual(result.container.scrollOffset, 150, accuracy: 0.0001)

        XCTAssertTrue(result.runtime.scrollToDescendant(result.rows[5], anchorY: 0.5))
        XCTAssertEqual(result.container.scrollOffset, 130, accuracy: 0.0001)

        XCTAssertTrue(result.runtime.scrollToDescendant(result.rows[5], anchorY: 1))
        XCTAssertEqual(result.container.scrollOffset, 110, accuracy: 0.0001)

        XCTAssertTrue(result.runtime.scrollToDescendant(result.rows[19], anchorY: 0))
        XCTAssertEqual(result.container.scrollOffset, 530, accuracy: 0.0001)

        XCTAssertTrue(result.runtime.scrollToDescendant(result.rows[0], anchorY: 1))
        XCTAssertEqual(result.container.scrollOffset, 0, accuracy: 0.0001)
    }

    func testHorizontalScrollingUsesHorizontalAnchorWithoutMovingOtherAxes() async {
        let result = fixture(axis: .horizontal)

        XCTAssertTrue(result.runtime.scrollToDescendant(result.rows[6], anchorX: 0.5, anchorY: 1))
        XCTAssertEqual(result.container.scrollOffset, 160, accuracy: 0.0001)

        XCTAssertTrue(result.runtime.scrollToDescendant(result.rows[2], anchorX: 0))
        XCTAssertEqual(result.container.scrollOffset, 60, accuracy: 0.0001)
    }

    func testDeferredLazyDescendantUsesItsPlacedAncestorAndResumesAfterScroll() async {
        let result = fixture(lazy: true, nestedTargets: true)
        let deferredRow = result.rows[16]
        let nestedTarget = result.nestedTargets[16]

        XCTAssertTrue(deferredRow.isLayoutDeferredByVirtualization)
        XCTAssertEqual(nestedTarget.resolvedFrame.size, .zero)
        XCTAssertTrue(result.runtime.scrollToDescendant(nestedTarget, anchorY: 0))
        XCTAssertEqual(result.container.scrollOffset, 480, accuracy: 0.0001)
        XCTAssertTrue(result.container.subtreeDirtyFlags.contains(.layout))

        _ = result.runtime.renderScene()
        XCTAssertFalse(deferredRow.isLayoutDeferredByVirtualization)
    }

    func testDetachedHiddenAndNonfiniteTargetsAreRejectedWithoutChangingOffset() async {
        let result = fixture()

        XCTAssertFalse(result.runtime.scrollToDescendant(ViewNode(frame: Rect(x: 0, y: 200, width: 30, height: 30))))
        XCTAssertFalse(result.runtime.scrollToDescendant(result.rows[5], anchorY: .nan))
        XCTAssertFalse(result.runtime.scrollToDescendant(result.rows[5], anchorY: .infinity))
        result.rows[5].isHidden = true
        XCTAssertFalse(result.runtime.scrollToDescendant(result.rows[5]))
        XCTAssertEqual(result.container.scrollOffset, 0, accuracy: 0.0001)
    }

    func testProgrammaticScrollCancelsExistingPreciseWheelMomentum() async {
        let result = fixture()
        result.runtime.mouseWheel(at: Point(x: 30, y: 30), delta: -2, source: .precise)
        XCTAssertGreaterThan(result.container.scrollOffset, 0)

        XCTAssertTrue(result.runtime.scrollToDescendant(result.rows[10], anchorY: 0))
        let requestedOffset = result.container.scrollOffset
        _ = result.runtime.tickAnimations(at: result.runtime.clock() + 1)
        _ = result.runtime.tickAnimations(at: result.runtime.clock() + 2)

        XCTAssertEqual(result.container.scrollOffset, requestedOffset, accuracy: 0.0001)
    }

    func testAfterLayoutScrollSettlesVirtualizedRowsBeforeFirstScenePaint() async {
        let result = fixture(lazy: true, render: false)
        result.runtime.scheduleAfterLayout(key: "initial-scroll") { [weak runtime = result.runtime] in
            guard let runtime else { return }
            XCTAssertTrue(runtime.scrollToDescendant(result.rows[19], anchorY: 1))
        }

        let scene = result.runtime.renderScene()

        XCTAssertEqual(result.container.scrollOffset, 530, accuracy: 0.0001)
        XCTAssertFalse(result.rows[19].isLayoutDeferredByVirtualization)
        XCTAssertTrue(
            scene.layers.flatMap(\.quads).contains { $0.startR == 1 && $0.startG == 0 && $0.startB == 0 },
            "the very first scene must paint the newly visible lazy row"
        )
    }

    func testAfterLayoutActionsAreKeyedOneShotAndNewActionsWaitForTheNextPass() async {
        let result = fixture(render: false)
        var calls: [String] = []

        result.runtime.scheduleAfterLayout(key: "first") {
            calls.append("stale")
        }
        result.runtime.scheduleAfterLayout(key: "first") { [weak runtime = result.runtime] in
            calls.append("replacement")
            runtime?.scheduleAfterLayout(key: "next-pass") {
                calls.append("next")
            }
        }
        result.runtime.scheduleAfterLayout(key: "second") {
            calls.append("second")
        }

        _ = result.runtime.renderScene()
        XCTAssertEqual(calls, ["replacement", "second"])

        _ = result.runtime.renderScene()
        XCTAssertEqual(calls, ["replacement", "second", "next"])

        _ = result.runtime.renderScene()
        XCTAssertEqual(calls, ["replacement", "second", "next"])
    }

    func testActionReplacingAnotherPendingKeyCannotStealItsCurrentPassCallback() async {
        let result = fixture(render: false)
        var calls: [String] = []

        result.runtime.scheduleAfterLayout(key: "first") { [weak runtime = result.runtime] in
            calls.append("first")
            runtime?.scheduleAfterLayout(key: "second") {
                calls.append("second-replacement")
            }
        }
        result.runtime.scheduleAfterLayout(key: "second") {
            calls.append("second-original")
        }

        _ = result.runtime.renderScene()
        XCTAssertEqual(calls, ["first", "second-original"])

        _ = result.runtime.renderScene()
        XCTAssertEqual(calls, ["first", "second-original", "second-replacement"])
    }

    func testAfterLayoutCallbackCanScrollAnAlreadyCachedCleanContainer() async {
        let result = fixture()
        let previousContainerPass = result.container.lastLayoutVisitPassID
        XCTAssertFalse(result.runtime.isDirty)

        result.runtime.scheduleAfterLayout(key: "cached-scroll") { [weak runtime = result.runtime] in
            guard let runtime else { return }
            XCTAssertFalse(runtime.isLayoutInProgress)
            XCTAssertTrue(runtime.scrollToDescendant(result.rows[8], anchorY: 0))
        }

        _ = result.runtime.renderScene()

        XCTAssertGreaterThan(result.runtime.layoutPassID, previousContainerPass)
        XCTAssertEqual(result.container.scrollOffset, 240, accuracy: 0.0001)
    }

    func testCachedCleanContainerCanScrollAfterAnUnrelatedLayoutPass() async {
        let result = fixture()
        let previousContainerPass = result.container.lastLayoutVisitPassID

        result.runtime.scheduleAfterLayout(key: "unrelated") {}
        _ = result.runtime.renderScene()

        XCTAssertEqual(result.container.lastLayoutVisitPassID, previousContainerPass)
        XCTAssertGreaterThan(result.runtime.layoutPassID, previousContainerPass)
        XCTAssertTrue(result.runtime.scrollToDescendant(result.rows[8], anchorY: 0))
        XCTAssertEqual(result.container.scrollOffset, 240, accuracy: 0.0001)
    }

    func testAfterLayoutCallbacksAlsoRunBeforeFirstFramePathPaint() async {
        let result = fixture(render: false)
        result.runtime.scheduleAfterLayout(key: "frame-scroll") { [weak runtime = result.runtime] in
            guard let runtime else { return }
            XCTAssertTrue(runtime.scrollToDescendant(result.rows[8], anchorY: 0))
        }

        _ = result.runtime.renderFrame()

        XCTAssertEqual(result.container.scrollOffset, 240, accuracy: 0.0001)
    }

    func testDeferredNestedTargetReceivesOnePreciseAlignmentAfterItsTallRowIsRealized() async {
        let result = oversizedDeferredFixture()
        XCTAssertTrue(result.row.isLayoutDeferredByVirtualization)

        XCTAssertTrue(result.runtime.scrollToDescendant(result.target, anchorY: 0))
        XCTAssertEqual(result.container.scrollOffset, 400, accuracy: 0.0001)

        let scene = result.runtime.renderScene()

        XCTAssertEqual(result.container.scrollOffset, 600, accuracy: 0.0001)
        XCTAssertFalse(result.row.isLayoutDeferredByVirtualization)
        XCTAssertTrue(
            scene.layers.flatMap(\.quads).contains { $0.startR == 1 && $0.startG == 0 && $0.startB == 0 },
            "the corrected nested target must be visible in the same settled scene"
        )
    }

    func testNewerUserScrollCancelsAStaleDeferredPreciseAlignment() async {
        let result = oversizedDeferredFixture()

        XCTAssertTrue(result.runtime.scrollToDescendant(result.target, anchorY: 0))
        XCTAssertEqual(result.container.scrollOffset, 400, accuracy: 0.0001)

        result.container.scrollOffset = 450
        _ = result.runtime.renderScene()

        XCTAssertEqual(
            result.container.scrollOffset,
            450,
            accuracy: 0.0001,
            "an intervening user scroll supersedes the queued coarse-to-precise correction"
        )
    }

    func testReparentedTargetCannotRedirectADeferredAlignmentIntoAnotherScroller() async {
        let result = oversizedDeferredFixture()
        XCTAssertTrue(result.runtime.scrollToDescendant(result.target, anchorY: 0))
        XCTAssertEqual(result.container.scrollOffset, 400, accuracy: 0.0001)

        let filler = (0..<8).map { _ in
            ViewNode(preferredSize: Size(width: 80, height: 40), isHitTestVisible: false)
        }
        let alternative = ViewNode(
            frame: Rect(x: 0, y: 0, width: 100, height: 100),
            layoutMode: .stack(.vertical(spacing: 0)),
            scrollAxis: .vertical,
            isHitTestVisible: false,
            children: filler
        )
        result.runtime.root.addChild(alternative)
        alternative.addChild(result.target)

        _ = result.runtime.renderScene()

        XCTAssertEqual(result.container.scrollOffset, 400, accuracy: 0.0001)
        XCTAssertEqual(
            alternative.scrollOffset,
            0,
            accuracy: 0.0001,
            "a stale retry belongs to its original scroll container, never a reparented target"
        )
    }
}
