import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsLayout
import XCTest

@testable import SwiftWindowsUI

@MainActor
final class RuntimeProgrammaticScrollAnimationTests: XCTestCase {
    private struct Fixture {
        let runtime: RetainedViewRuntime
        let container: ViewNode
        let rows: [ViewNode]
        let clock: RuntimeTestClock
    }

    private func fixture(lazy: Bool = false) -> Fixture {
        let rows = (0..<20).map { index in
            ViewNode(
                backgroundColor: index == 19
                    ? Color(red: 1, green: 0, blue: 0, alpha: 1)
                    : index == 9 ? Color(red: 0, green: 0, blue: 1, alpha: 1) : .white,
                preferredSize: Size(width: 90, height: 30)
            )
        }
        let container = ViewNode(
            frame: Rect(x: 10, y: 10, width: 90, height: 70),
            clipsToBounds: true,
            layoutMode: lazy ? .lazyStack(.vertical(spacing: 0)) : .stack(.vertical(spacing: 0)),
            scrollAxis: .vertical,
            isHitTestVisible: false,
            children: rows
        )
        let runtime = RetainedViewRuntime(
            root: ViewNode(
                frame: Rect(x: 0, y: 0, width: 140, height: 110),
                isHitTestVisible: false,
                children: [container]
            )
        )
        let clock = RuntimeTestClock()
        runtime.clock = { clock.now }
        _ = runtime.renderScene()
        return Fixture(runtime: runtime, container: container, rows: rows, clock: clock)
    }

    private func oversizedDeferredFixture() -> (
        runtime: RetainedViewRuntime, container: ViewNode, row: ViewNode,
        target: ViewNode, clock: RuntimeTestClock
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
        let clock = RuntimeTestClock()
        runtime.clock = { clock.now }
        _ = runtime.renderScene()
        return (runtime, container, row, target, clock)
    }

    func testAuthoredEasingRetargetsFromPresentationAndSurvivesDisabledInput() async {
        let result = fixture()
        var phases: [RetainedScrollPhase] = []
        result.container.observeScrollPhase { _, new, _ in phases.append(new) }
        _ = result.runtime.renderScene()

        XCTAssertTrue(
            result.runtime.scrollToDescendant(
                result.rows[10], anchorY: 0,
                transaction: Transaction(animation: .easeIn(duration: 2)))
        )
        _ = result.runtime.renderScene()
        XCTAssertEqual(result.container.scrollOffset, 300)
        XCTAssertEqual(result.container.resolvedScrollOffset, 0)
        XCTAssertTrue(result.runtime.hasActiveAnimations)

        result.clock.now = 0.5
        _ = result.runtime.tickAnimations(at: result.clock.now)
        _ = result.runtime.renderFrame()
        XCTAssertEqual(result.container.resolvedScrollOffset, 18.75, accuracy: 0.0001)

        result.container.isScrollInputEnabled = false
        _ = result.runtime.renderScene()
        XCTAssertEqual(result.container.resolvedScrollOffset, 18.75, accuracy: 0.0001)
        XCTAssertTrue(result.runtime.hasActiveAnimations)
        XCTAssertEqual(phases, [.animating])

        XCTAssertTrue(
            result.runtime.scrollToDescendant(
                result.rows[16], anchorY: 0,
                transaction: Transaction(animation: .easeOut(duration: 1)))
        )
        _ = result.runtime.renderScene()
        XCTAssertEqual(result.container.scrollOffset, 480)
        XCTAssertEqual(
            result.container.resolvedScrollOffset, 18.75, accuracy: 0.0001,
            "A new request starts at the presented position rather than the previous logical target")

        result.clock.now = 1
        _ = result.runtime.tickAnimations(at: result.clock.now)
        _ = result.runtime.renderFrame()
        XCTAssertEqual(result.container.resolvedScrollOffset, 364.6875, accuracy: 0.0001)

        result.clock.now = 1.5
        _ = result.runtime.tickAnimations(at: result.clock.now)
        _ = result.runtime.renderScene()
        XCTAssertEqual(result.container.resolvedScrollOffset, 480, accuracy: 0.0001)
        XCTAssertEqual(phases, [.animating, .idle])
        XCTAssertFalse(result.runtime.hasActiveAnimations)
    }

    func testInvalidDurationSnapsAndNonfiniteEasingCannotPoisonPresentedGeometry() async {
        for duration in [0.0, -1, Double.nan, Double.infinity, -Double.infinity] {
            let result = fixture()
            XCTAssertTrue(
                result.runtime.scrollToDescendant(
                    result.rows[10], anchorY: 0,
                    transaction: Transaction(animation: .linear(duration: duration)))
            )
            _ = result.runtime.renderScene()
            XCTAssertEqual(result.container.resolvedScrollOffset, 300, accuracy: 0.0001)
            XCTAssertFalse(result.runtime.hasActiveAnimations)
        }

        let result = fixture()
        var offsets: [Double] = []
        result.container.observeScrollGeometry(of: { $0.contentOffset.y }, action: { _, new in offsets.append(new) })
        _ = result.runtime.renderScene()
        let malformed = Animation(
            duration: 1,
            easing: .timingCurve(c0x: 0.2, c0y: .nan, c1x: 0.8, c1y: .infinity))
        XCTAssertTrue(
            result.runtime.scrollToDescendant(
                result.rows[10], anchorY: 0, transaction: Transaction(animation: malformed))
        )
        for time in [0.25, 0.5, 0.75, 1.0] {
            result.clock.now = time
            _ = result.runtime.tickAnimations(at: result.clock.now)
            _ = result.runtime.renderScene()
            XCTAssertTrue(result.container.resolvedScrollOffset.isFinite)
            XCTAssertTrue(result.container.scrollPresentedDelta.isFinite)
            XCTAssertTrue(offsets.allSatisfy(\.isFinite))
        }
        XCTAssertEqual(result.container.resolvedScrollOffset, 300, accuracy: 0.0001)
        XCTAssertFalse(result.runtime.hasActiveAnimations)
    }

    func testLazyRowsGeometryAndHitTestingFollowThePresentedViewport() async {
        let result = fixture(lazy: true)
        var offsets: [Double] = []
        var activations = 0
        result.rows[9].onActivate = { activations += 1 }
        result.container.observeScrollGeometry(of: { $0.contentOffset.y }, action: { _, new in offsets.append(new) })
        _ = result.runtime.renderScene()

        XCTAssertTrue(
            result.runtime.scrollToDescendant(
                result.rows[19], anchorY: 1,
                transaction: Transaction(animation: .linear(duration: 1)))
        )
        _ = result.runtime.renderScene()
        XCTAssertEqual(result.container.scrollOffset, 530)
        XCTAssertEqual(result.container.resolvedScrollOffset, 0)
        XCTAssertFalse(result.rows[0].isLayoutDeferredByVirtualization)
        XCTAssertTrue(result.rows[16].isLayoutDeferredByVirtualization)

        result.clock.now = 0.5
        _ = result.runtime.tickAnimations(at: result.clock.now)
        let scene = result.runtime.renderScene()
        XCTAssertEqual(result.container.resolvedScrollOffset, 265, accuracy: 0.0001)
        XCTAssertEqual(offsets.last, 265)
        XCTAssertFalse(result.rows[9].isLayoutDeferredByVirtualization)
        XCTAssertTrue(result.rows[16].isLayoutDeferredByVirtualization)
        XCTAssertTrue(scene.layers.flatMap(\.quads).contains { $0.startR == 0 && $0.startG == 0 && $0.startB == 1 })

        // Row nine starts at content y=270, so its presented top is y=15.
        result.runtime.pointerDown(at: Point(x: 30, y: 20))
        result.runtime.pointerUp(at: Point(x: 30, y: 20))
        XCTAssertEqual(activations, 1, "Hit testing must use the same intermediate viewport that was painted")
    }

    func testDeferredNestedTargetUsesOnlyTheRemainingAuthoredDuration() async {
        let result = oversizedDeferredFixture()
        XCTAssertTrue(result.row.isLayoutDeferredByVirtualization)
        XCTAssertTrue(
            result.runtime.scrollToDescendant(
                result.target, anchorY: 0,
                transaction: Transaction(animation: .linear(duration: 1)))
        )
        _ = result.runtime.renderScene()
        XCTAssertEqual(result.container.scrollOffset, 400)
        XCTAssertEqual(result.container.resolvedScrollOffset, 0)

        result.clock.now = 0.6
        _ = result.runtime.tickAnimations(at: result.clock.now)
        _ = result.runtime.renderScene()
        XCTAssertFalse(result.row.isLayoutDeferredByVirtualization)
        XCTAssertEqual(result.container.scrollOffset, 600)
        XCTAssertEqual(
            result.container.resolvedScrollOffset, 240, accuracy: 0.0001,
            "Refining the target after realization must preserve the position already presented")

        result.clock.now = 0.8
        _ = result.runtime.tickAnimations(at: result.clock.now)
        _ = result.runtime.renderFrame()
        XCTAssertEqual(result.container.resolvedScrollOffset, 420, accuracy: 0.0001)

        result.clock.now = 1
        _ = result.runtime.tickAnimations(at: result.clock.now)
        let scene = result.runtime.renderScene()
        XCTAssertEqual(result.container.resolvedScrollOffset, 600, accuracy: 0.0001)
        XCTAssertFalse(result.runtime.hasActiveAnimations, "Precise alignment must not extend the original deadline")
        XCTAssertTrue(scene.layers.flatMap(\.quads).contains { $0.startR == 1 && $0.startG == 0 && $0.startB == 0 })
    }

    func testUnrealizedCoarseTargetDoesNotRestartAndDeadlineAlignmentPaintsInTheSameFrame() async {
        let result = oversizedDeferredFixture()
        XCTAssertTrue(
            result.runtime.scrollToDescendant(
                result.target, anchorY: 0,
                transaction: Transaction(animation: .linear(duration: 1)))
        )
        _ = result.runtime.renderScene()

        for time in [0.1, 0.2] {
            result.clock.now = time
            _ = result.runtime.tickAnimations(at: result.clock.now)
            _ = result.runtime.renderScene()
            XCTAssertEqual(result.container.scrollOffset, 400)
            XCTAssertEqual(result.container.resolvedScrollOffset, 400 * time, accuracy: 0.0001)
            XCTAssertTrue(result.row.isLayoutDeferredByVirtualization)
        }

        result.clock.now = 1
        _ = result.runtime.tickAnimations(at: result.clock.now)
        let scene = result.runtime.renderScene()
        XCTAssertEqual(result.container.scrollOffset, 600)
        XCTAssertEqual(result.container.resolvedScrollOffset, 600, accuracy: 0.0001)
        XCTAssertFalse(result.row.isLayoutDeferredByVirtualization)
        XCTAssertFalse(result.runtime.hasActiveAnimations)
        XCTAssertTrue(
            scene.layers.flatMap(\.quads).contains { $0.startR == 1 && $0.startG == 0 && $0.startB == 0 },
            "The deadline frame must show the nested target, not its oversized ancestor's coarse alignment")
    }

    func testShrinkingScrollRangeClampsPresentationAndCancelsProgrammaticAnimation() async {
        for enlargesViewport in [true, false] {
            let result = fixture()
            var offsets: [Double] = []
            var phases: [RetainedScrollPhase] = []
            result.rows[4].backgroundColor = Color(red: 0, green: 1, blue: 0, alpha: 1)
            result.container.observeScrollGeometry(
                of: { $0.contentOffset.y }, action: { _, new in offsets.append(new) })
            result.container.observeScrollPhase { _, new, _ in phases.append(new) }
            _ = result.runtime.renderScene()

            XCTAssertTrue(
                result.runtime.scrollToDescendant(
                    result.rows[19], anchorY: 1,
                    transaction: Transaction(animation: .linear(duration: 1)))
            )
            result.clock.now = 0.5
            _ = result.runtime.tickAnimations(at: result.clock.now)
            _ = result.runtime.renderScene()
            XCTAssertEqual(result.container.scrollOffset, 530)
            XCTAssertEqual(result.container.resolvedScrollOffset, 265, accuracy: 0.0001)
            XCTAssertEqual(result.container.scrollPresentedDelta, -265, accuracy: 0.0001)
            XCTAssertEqual(phases, [.animating])

            if enlargesViewport {
                result.container.frame.size.height = 500
            } else {
                // Keep the requested target attached so range reconciliation,
                // rather than target-removal cancellation, is exercised.
                for row in result.rows.prefix(15) {
                    result.container.removeChild(row)
                }
            }
            let expectedOffset: Double = enlargesViewport ? 100 : 80
            let scene = result.runtime.renderScene()
            XCTAssertEqual(result.container.scrollOffset, expectedOffset, accuracy: 0.0001)
            XCTAssertEqual(result.container.resolvedScrollOffset, expectedOffset, accuracy: 0.0001)
            XCTAssertGreaterThanOrEqual(result.container.resolvedScrollOffset, 0)
            XCTAssertLessThanOrEqual(result.container.resolvedScrollOffset, expectedOffset)
            XCTAssertEqual(result.container.scrollPresentedDelta, 0)
            XCTAssertEqual(offsets.last, expectedOffset)
            XCTAssertEqual(phases, [.animating, .idle])
            XCTAssertFalse(result.runtime.hasActiveAnimations)

            let marker = scene.layers.flatMap(\.quads).first {
                enlargesViewport
                    ? $0.startR == 0 && $0.startG == 1 && $0.startB == 0
                    : $0.startR == 1 && $0.startG == 0 && $0.startB == 0
            }
            XCTAssertEqual(
                Double(marker?.y ?? .nan), enlargesViewport ? 30 : 50, accuracy: 0.0001,
                "Painting must use the clamped presented offset in the resize frame")

            result.clock.now = 1
            _ = result.runtime.tickAnimations(at: result.clock.now)
            _ = result.runtime.renderFrame()
            XCTAssertEqual(result.container.scrollOffset, expectedOffset, accuracy: 0.0001)
            XCTAssertEqual(result.container.resolvedScrollOffset, expectedOffset, accuracy: 0.0001)
            XCTAssertEqual(phases, [.animating, .idle])
            XCTAssertFalse(result.runtime.hasActiveAnimations)
        }
    }

    func testDirectOffsetAndTargetRemovalCancelAnimationWithoutReplayingStaleAlignment() async {
        do {
            let result = oversizedDeferredFixture()
            XCTAssertTrue(
                result.runtime.scrollToDescendant(
                    result.target, anchorY: 0,
                    transaction: Transaction(animation: .linear(duration: 1)))
            )
            result.clock.now = 0.1
            _ = result.runtime.tickAnimations(at: result.clock.now)
            _ = result.runtime.renderScene()
            XCTAssertEqual(result.container.resolvedScrollOffset, 40, accuracy: 0.0001)

            result.container.scrollOffset = 450
            _ = result.runtime.renderScene()
            XCTAssertEqual(result.container.resolvedScrollOffset, 450, accuracy: 0.0001)
            XCTAssertFalse(result.runtime.hasActiveAnimations)

            result.clock.now = 1
            _ = result.runtime.tickAnimations(at: result.clock.now)
            _ = result.runtime.renderFrame()
            XCTAssertEqual(result.container.scrollOffset, 450)
            XCTAssertEqual(result.container.resolvedScrollOffset, 450, accuracy: 0.0001)
        }

        do {
            let result = fixture()
            XCTAssertTrue(
                result.runtime.scrollToDescendant(
                    result.rows[10], anchorY: 0,
                    transaction: Transaction(animation: .linear(duration: 1)))
            )
            result.clock.now = 0.25
            _ = result.runtime.tickAnimations(at: result.clock.now)
            _ = result.runtime.renderScene()
            XCTAssertEqual(result.container.resolvedScrollOffset, 75, accuracy: 0.0001)

            result.container.removeChild(result.rows[10])
            _ = result.runtime.renderScene()
            XCTAssertEqual(result.container.resolvedScrollOffset, 75, accuracy: 0.0001)
            XCTAssertFalse(result.runtime.hasActiveAnimations)

            result.clock.now = 1
            _ = result.runtime.tickAnimations(at: result.clock.now)
            _ = result.runtime.renderScene()
            XCTAssertEqual(result.container.resolvedScrollOffset, 75, accuracy: 0.0001)
        }
    }
}
