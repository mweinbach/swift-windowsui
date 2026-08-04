import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// A macOS scroller is an *overlay* scroller: it is invisible at rest, fades
/// in while the content moves, and fades back out a beat after it stops. That
/// is why a screenshot of a real macOS app shows no scrollbar anywhere.
///
/// Before this, every `ScrollView` and `List` drew a permanent blue-tinted
/// near-white bar down its trailing edge — visible in every screenshot, and
/// invisible in light mode, since white on white is nothing. The flash
/// plumbing (`scrollIndicatorsFlashOnAppear`, `scrollIndicatorsFlash(trigger:)`)
/// was stored on the node and read by nobody.
@MainActor
final class OverlayScrollIndicatorTests: XCTestCase {

    /// A 200pt viewport over 600pt of content, hosted in a real runtime so the
    /// prepaint pass runs and the indicator track exists.
    private func makeOverlayScrollFixture(
        showsScrollIndicator: Bool = true
    ) -> (runtime: RetainedViewRuntime, scroll: ViewNode) {
        let content = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 600), backgroundColor: .white)
        let scroll = Controls.scrollPanel(
            axis: .vertical,
            frame: Rect(x: 0, y: 0, width: 100, height: 200),
            stackLayout: .vertical(spacing: 0, padding: .zero, alignment: .stretch),
            scrollIndicatorColor: ControlPalette.darkStandard.scrollerKnob,
            scrollIndicatorAutoHides: true,
            children: [content]
        )
        scroll.showsScrollIndicator = showsScrollIndicator
        let root = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 200), children: [scroll])
        let runtime = RetainedViewRuntime(root: root)
        _ = runtime.renderScene()
        return (runtime, scroll)
    }

    private func indicatorTrack(of runtime: RetainedViewRuntime) -> ScrollIndicatorTrack? {
        for deferredDraw in runtime.currentPrepaintState.deferredDraws {
            if case .scrollIndicator(let payload) = deferredDraw.payload {
                return payload.track
            }
        }
        return nil
    }

    // MARK: - Hidden at rest

    func testAnOverlayScrollerIsInvisibleUntilSomethingScrolls() async {
        let (_, scroll) = makeOverlayScrollFixture()
        XCTAssertTrue(scroll.scrollIndicatorAutoHides)
        XCTAssertEqual(
            scroll.scrollIndicatorColor.alpha, 0,
            "an overlay scroller is not drawn at rest — a static screenshot must show no scrollbar")
        XCTAssertGreaterThan(
            scroll.scrollIndicatorIdleColor.alpha, 0,
            "the idle colour stays the *revealed* tone, so the same tween runs both directions")
    }

    /// The thumb still has to be grabbable while it is faded out — that is how
    /// a macOS overlay scroller comes back when the pointer approaches it —
    /// so geometry must not be gated on the painted alpha.
    func testAFadedOutThumbStillHasATrackToHitTest() async {
        let (runtime, scroll) = makeOverlayScrollFixture()
        XCTAssertEqual(scroll.scrollIndicatorColor.alpha, 0)
        XCTAssertNotNil(
            indicatorTrack(of: runtime),
            "an invisible thumb keeps its track; otherwise it can never be reached again")

        // And dragging it still scrolls: the track is real, not decorative.
        let track = indicatorTrack(of: runtime)!
        let grabPoint = Point(x: track.indicatorRect.midX, y: track.indicatorRect.midY)
        runtime.pointerDown(at: grabPoint)
        runtime.pointerMoved(to: Point(x: grabPoint.x, y: grabPoint.y + 40))
        XCTAssertGreaterThan(scroll.scrollOffset, 0)
        runtime.pointerUp(at: Point(x: grabPoint.x, y: grabPoint.y + 40))
    }

    // MARK: - Reveal, hold, fade out

    /// Driven by a plain offset change — the funnel every scroll reaches, and
    /// the one a scroll-into-view or a `scrollPosition` binding uses — so the
    /// timeline under test is the reveal machine and not the wheel's momentum
    /// glide.
    func testScrollingRevealsTheScrollerAndThenFadesItBackOut() async {
        let (runtime, scroll) = makeOverlayScrollFixture()

        scroll.scrollOffset = 120
        XCTAssertTrue(
            runtime.hasActiveAnimations,
            "a pending reveal has to keep the host's animation timer on, or the fade never runs")

        // Reveal: started on the first tick, complete by the end of its tween.
        _ = runtime.tickAnimations(at: 0)
        _ = runtime.tickAnimations(at: RetainedViewRuntime.scrollIndicatorRevealDuration)
        XCTAssertEqual(
            scroll.scrollIndicatorColor, scroll.scrollIndicatorIdleColor,
            "a scroll brings the overlay scroller all the way up")

        // Hold: still up, and still billing the host for frames so the
        // deadline can arrive at all.
        _ = runtime.tickAnimations(at: RetainedViewRuntime.scrollIndicatorVisibleHold * 0.5)
        XCTAssertEqual(scroll.scrollIndicatorColor, scroll.scrollIndicatorIdleColor)
        XCTAssertTrue(runtime.hasActiveAnimations)

        // Past the hold: the fade starts, and finishes at nothing.
        let hideStart = RetainedViewRuntime.scrollIndicatorVisibleHold + 0.001
        _ = runtime.tickAnimations(at: hideStart)
        _ = runtime.tickAnimations(at: hideStart + RetainedViewRuntime.scrollIndicatorFadeOutDuration + 0.05)
        XCTAssertEqual(
            scroll.scrollIndicatorColor.alpha, 0,
            "the scroller goes away on its own once the scrolling stops")
        XCTAssertFalse(
            runtime.hasActiveAnimations,
            "and stops asking for frames once it has")
    }

    func testScrollingAgainRestartsTheHoldRatherThanLettingItExpire() async {
        let (runtime, scroll) = makeOverlayScrollFixture()

        scroll.scrollOffset = 120
        _ = runtime.tickAnimations(at: 0)
        _ = runtime.tickAnimations(at: RetainedViewRuntime.scrollIndicatorVisibleHold * 0.9)

        // A second scroll just before the deadline pushes it out.
        scroll.scrollOffset = 200
        let justPastFirstDeadline = RetainedViewRuntime.scrollIndicatorVisibleHold + 0.001
        _ = runtime.tickAnimations(at: justPastFirstDeadline)
        _ = runtime.tickAnimations(at: justPastFirstDeadline + 0.05)
        XCTAssertEqual(
            scroll.scrollIndicatorColor, scroll.scrollIndicatorIdleColor,
            "the hold is measured from the last scroll, not the first")
    }

    /// The wheel path specifically: a notch has to reveal the scroller, not
    /// only move the content.
    func testAWheelScrollRevealsTheScroller() async {
        let (runtime, scroll) = makeOverlayScrollFixture()

        runtime.mouseWheel(at: Point(x: 50, y: 100), delta: -1)
        XCTAssertGreaterThan(scroll.scrollOffset, 0, "the fixture must actually scroll")

        _ = runtime.tickAnimations(at: 0)
        _ = runtime.tickAnimations(at: RetainedViewRuntime.scrollIndicatorRevealDuration)
        XCTAssertEqual(scroll.scrollIndicatorColor, scroll.scrollIndicatorIdleColor)
    }

    // MARK: - Flash

    func testFlashOnAppearShowsTheScrollerWithoutAnyScrolling() async {
        let content = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 600), backgroundColor: .white)
        let scroll = Controls.scrollPanel(
            axis: .vertical,
            frame: Rect(x: 0, y: 0, width: 100, height: 200),
            stackLayout: .vertical(spacing: 0, padding: .zero, alignment: .stretch),
            scrollIndicatorColor: ControlPalette.darkStandard.scrollerKnob,
            scrollIndicatorAutoHides: true,
            children: [content]
        )
        scroll.scrollIndicatorsFlashOnAppear = true
        let runtime = RetainedViewRuntime(
            root: ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 200), children: [scroll]))

        // The first render is what makes the node "appear" — the flash rides
        // the same lifecycle pass `onAppear` does.
        _ = runtime.renderFrame()
        _ = runtime.tickAnimations(at: 0)
        _ = runtime.tickAnimations(at: RetainedViewRuntime.scrollIndicatorRevealDuration)
        XCTAssertEqual(
            scroll.scrollIndicatorColor, scroll.scrollIndicatorIdleColor,
            "`scrollIndicatorsFlashOnAppear` used to be stored and read by nobody")
    }

    func testAFlashTriggerChangeFlashesTheScroller() async {
        let (runtime, scroll) = makeOverlayScrollFixture()
        scroll.scrollIndicatorsFlashTrigger = "Int:1"
        _ = runtime.tickAnimations(at: 0)
        XCTAssertEqual(
            scroll.scrollIndicatorColor.alpha, 0,
            "the first value a trigger takes is its baseline, not a flash")

        scroll.scrollIndicatorsFlashTrigger = "Int:2"
        _ = runtime.tickAnimations(at: 0)
        _ = runtime.tickAnimations(at: RetainedViewRuntime.scrollIndicatorRevealDuration)
        XCTAssertEqual(scroll.scrollIndicatorColor, scroll.scrollIndicatorIdleColor)
    }

    // MARK: - WinSwiftUI wiring

    func testAStockScrollViewGetsAnOverlayScrollerInBothAppearances() async {
        for scheme in [ColorScheme.dark, ColorScheme.light] {
            let node = makeScrollNode(colorScheme: scheme) {
                ScrollView { Text("ONE") }
            }
            XCTAssertTrue(node.scrollIndicatorAutoHides, "\(scheme): .automatic is macOS's overlay scroller")
            XCTAssertEqual(node.scrollIndicatorColor.alpha, 0, "\(scheme): hidden at rest")
            XCTAssertEqual(
                node.scrollIndicatorIdleColor,
                ControlPalette.resolve(colorScheme: scheme).scrollerKnob,
                "\(scheme): the knob is a neutral pill resolved for the appearance"
            )
            XCTAssertEqual(
                node.scrollIndicatorThickness,
                MacOSControlMetrics.Scroller.overlayThumbThickness,
                accuracy: 0.001
            )
        }
    }

    func testAListGetsTheSameOverlayScrollerAsAScrollView() async {
        let node = makeScrollNode(colorScheme: .light) {
            List { Text("ONE") }
        }
        XCTAssertTrue(node.scrollIndicatorAutoHides)
        XCTAssertEqual(node.scrollIndicatorColor.alpha, 0)
        XCTAssertEqual(node.scrollIndicatorIdleColor, ControlPalette.lightStandard.scrollerKnob)
    }

    /// `.scrollIndicators(.visible)` is the app asking for the scroller to be
    /// on screen — the "Show scroll bars: Always" appearance. That is the
    /// legacy persistent bar, and it must still be reachable.
    func testExplicitlyVisibleScrollIndicatorsStayOnScreen() async {
        let node = makeScrollNode(colorScheme: .dark) {
            ScrollView { Text("ONE") }
                .scrollIndicators(.visible)
        }
        XCTAssertTrue(node.showsScrollIndicator)
        XCTAssertFalse(node.scrollIndicatorAutoHides)
        XCTAssertEqual(node.scrollIndicatorColor, node.scrollIndicatorIdleColor)
        XCTAssertGreaterThan(node.scrollIndicatorColor.alpha, 0)
    }

    private func makeScrollNode<V: View>(
        colorScheme: ColorScheme,
        @ViewBuilder _ view: () -> V
    ) -> ViewNode {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 400, height: 300) },
            invalidateHandler: {}
        )
        .withEnvironmentValue(\.colorScheme, colorScheme)
        return view().makeComponent(context: context).makeNode(runtime: runtime)
    }
}
