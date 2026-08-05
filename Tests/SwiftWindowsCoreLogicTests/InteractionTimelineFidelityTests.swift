import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Mid-tween assertions on the interaction layer.
///
/// Every case here drives the runtime through its own input entry points and
/// samples the timeline at fixed offsets from an *injected* clock
/// (`RetainedViewRuntime.clock`), reading node state between frames. That was
/// impossible before: `tickAnimations(at:)` took a timestamp but tween start
/// times were stamped from the wall clock, so a test could tick a timeline it
/// could not place a tween on. The gallery's interaction tier renders at
/// `t = 1e12` for exactly that reason and by construction captures only settled
/// end states — which is how a linear cross-fade, a fade through black, and a
/// screen that animated itself in on launch all shipped.
@MainActor
final class InteractionTimelineFidelityTests: XCTestCase {

    // MARK: - Harness

    /// A clock the test owns. Reads are what the runtime stamps tween starts
    /// with; the test moves it and ticks with the same value.
    private final class TestClock {
        var now: Double = 1_000.0
    }

    private func findNode(_ node: ViewNode, where predicate: (ViewNode) -> Bool) -> ViewNode? {
        if predicate(node) { return node }
        for child in node.children {
            if let found = findNode(child, where: predicate) { return found }
        }
        return nil
    }

    private func collectNodes(_ node: ViewNode, where predicate: (ViewNode) -> Bool) -> [ViewNode] {
        var out: [ViewNode] = []
        if predicate(node) { out.append(node) }
        for child in node.children {
            out.append(contentsOf: collectNodes(child, where: predicate))
        }
        return out
    }

    private func absoluteFrame(of node: ViewNode) -> Rect {
        var x = node.resolvedFrame.origin.x
        var y = node.resolvedFrame.origin.y
        var ancestor = node.parent
        while let current = ancestor {
            x += current.resolvedFrame.origin.x
            y += current.resolvedFrame.origin.y
            ancestor = current.parent
        }
        return Rect(x: x, y: y, width: node.resolvedFrame.size.width, height: node.resolvedFrame.size.height)
    }

    /// Moves the shared clock to `time` and ticks the runtime there. One clock
    /// for the stamp and the tick is the whole point of the mechanism.
    private func tick(_ runtime: RetainedViewRuntime, _ clock: TestClock, to time: Double) {
        clock.now = time
        _ = runtime.tickAnimations(at: time)
    }

    /// Steps to `time` at 60 Hz so springs and decay integrators see realistic
    /// frame deltas rather than one enormous one.
    private func advance(_ runtime: RetainedViewRuntime, _ clock: TestClock, to time: Double) {
        while clock.now + 1.0 / 60.0 < time {
            tick(runtime, clock, to: clock.now + 1.0 / 60.0)
        }
        tick(runtime, clock, to: time)
    }

    private func makeRuntime(_ clock: TestClock) -> RetainedViewRuntime {
        let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 420, height: 320)))
        runtime.clock = { clock.now }
        return runtime
    }

    private func makeButtonHost(_ clock: TestClock) -> (RetainedViewRuntime, ComponentHost) {
        let runtime = makeRuntime(clock)
        let host = ComponentHost(runtime: runtime)
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 420, height: 320) },
            invalidateHandler: { [weak host] in host?.reload() }
        )
        host.setComponents {
            [
                VStack {
                    Button("Sample") {}
                }
                .frame(width: 420, height: 320)
                .makeComponent(context: context)
            ]
        }
        _ = runtime.renderFrame()
        return (runtime, host)
    }

    private func button(in runtime: RetainedViewRuntime) -> ViewNode? {
        findNode(runtime.root, where: { $0.accessibilityTraits.contains(.isButton) })
    }

    /// The quadratic ease-in-out `AnimationState` evaluates, restated here so
    /// the assertion does not read its expectation out of the code under test.
    private func easeInOut(_ t: Double) -> Double {
        t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t
    }

    // MARK: - Colour cross-fades are eased, not linear

    /// Hover-in on a button, sampled through the tween.
    ///
    /// The audit measured this ramp at exactly 0.00278 alpha per 10ms from the
    /// first step to the last — a straight line, where AppKit's implicit
    /// property changes run on `kCAMediaTimingFunctionEaseInEaseOut`. The
    /// assertion is on the *shape*: each sample's normalised progress has to
    /// track `easeInOut`, and at least one has to be measurably off the linear
    /// ramp, which is what the old implementation produced at every sample.
    func testHoverCrossFadeFollowsAnEaseInOutCurveRatherThanARamp() async {
        let clock = TestClock()
        let (runtime, _) = makeButtonHost(clock)
        guard let button = button(in: runtime) else { return XCTFail("no button in tree") }
        guard let surface = button.interactionSurface else { return XCTFail("button has no interaction surface") }
        let duration = surface.duration(intoPhase: .hovered)
        XCTAssertGreaterThan(duration, 0)

        let start = Double(button.backgroundColor?.alpha ?? 0)
        let frame = absoluteFrame(of: button)
        let t0 = clock.now
        runtime.pointerMoved(to: Point(x: frame.midX, y: frame.midY))

        let fractions = [0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875]
        var sampled: [Double] = []
        for fraction in fractions {
            tick(runtime, clock, to: t0 + duration * fraction)
            sampled.append(Double(button.backgroundColor?.alpha ?? 0))
        }
        tick(runtime, clock, to: t0 + duration * 2)
        let end = Double(button.backgroundColor?.alpha ?? 0)
        XCTAssertNotEqual(end, start, accuracy: 0.0001, "a hover has to change the fill or there is no tween to shape")

        var maximumLinearDeviation = 0.0
        for (index, fraction) in fractions.enumerated() {
            let progress = (sampled[index] - start) / (end - start)
            XCTAssertEqual(
                progress, easeInOut(fraction), accuracy: 0.002,
                "at \(fraction) of the tween the fill has to sit on the ease-in-out curve")
            maximumLinearDeviation = max(maximumLinearDeviation, abs(progress - fraction))
        }
        XCTAssertGreaterThan(
            maximumLinearDeviation, 0.05,
            "the sampled ramp has to be measurably off a straight line — a linear tween passed this test's "
                + "curve assertion only at 0, 0.5 and 1")
    }

    /// The border tween is the same mechanism on a different property, and the
    /// press ramp is the same mechanism at a different duration. Both were
    /// linear; both are pinned here so a future change cannot ease one and
    /// leave the other.
    func testPressAndBorderCrossFadesShareTheHoverCurve() async {
        let clock = TestClock()
        let (runtime, _) = makeButtonHost(clock)
        guard let button = button(in: runtime) else { return XCTFail("no button in tree") }
        guard let surface = button.interactionSurface else { return XCTFail("button has no interaction surface") }
        let frame = absoluteFrame(of: button)
        let centre = Point(x: frame.midX, y: frame.midY)

        runtime.pointerMoved(to: centre)
        advance(runtime, clock, to: clock.now + 1.0)
        let hoveredBackground = Double(button.backgroundColor?.alpha ?? 0)
        let hoveredBorder = Double(button.borderColor.alpha)

        let pressDuration = surface.duration(intoPhase: .pressed)
        let t0 = clock.now
        runtime.pointerDown(at: centre)
        tick(runtime, clock, to: t0 + pressDuration * 0.25)
        let quarterBackground = Double(button.backgroundColor?.alpha ?? 0)
        let quarterBorder = Double(button.borderColor.alpha)
        tick(runtime, clock, to: t0 + pressDuration * 2)
        let pressedBackground = Double(button.backgroundColor?.alpha ?? 0)
        let pressedBorder = Double(button.borderColor.alpha)

        if abs(pressedBackground - hoveredBackground) > 0.001 {
            let progress = (quarterBackground - hoveredBackground) / (pressedBackground - hoveredBackground)
            XCTAssertEqual(progress, easeInOut(0.25), accuracy: 0.002, "the press fill eases")
        }
        if abs(pressedBorder - hoveredBorder) > 0.001 {
            let progress = (quarterBorder - hoveredBorder) / (pressedBorder - hoveredBorder)
            XCTAssertEqual(progress, easeInOut(0.25), accuracy: 0.002, "the press border eases")
        }
    }

    // MARK: - Fades hold their hue

    /// `Color.interpolated` in isolation, against the naive implementation it
    /// replaced. The measured symptoms were a white scroll thumb revealing as
    /// (0.069, 0.069, 0.069) at 8ms of its 0.12s fade, and a light-appearance
    /// accent focus ring rasterising grey-blue at the half-way point.
    func testInterpolationFromClearHoldsTheTargetHue() async {
        let white = Color(red: 1, green: 1, blue: 1, alpha: 0.48)
        let clear = Color(red: 0, green: 0, blue: 0, alpha: 0)

        for step in 1...9 {
            let progress = Double(step) / 10.0
            let blended = clear.interpolated(to: white, progress: progress)
            XCTAssertEqual(Double(blended.red), 1.0, accuracy: 0.0001, "hue is constant across the fade")
            XCTAssertEqual(Double(blended.green), 1.0, accuracy: 0.0001)
            XCTAssertEqual(Double(blended.blue), 1.0, accuracy: 0.0001)
            XCTAssertEqual(
                Double(blended.alpha), 0.48 * progress, accuracy: 0.0001,
                "alpha still interpolates linearly — only the colour channels changed")

            // The implementation this replaced, restated: an unpremultiplied
            // lerp drags every channel toward black in lockstep with alpha.
            let naive = Float(progress) * white.red
            XCTAssertLessThan(
                Double(naive), 1.0,
                "progress \(progress): the naive lerp produced \(naive) here, which is the bug")
        }

        // Symmetric on the way out.
        let fadingOut = white.interpolated(to: clear, progress: 0.75)
        XCTAssertEqual(Double(fadingOut.red), 1.0, accuracy: 0.0001)
        XCTAssertEqual(Double(fadingOut.alpha), 0.48 * 0.25, accuracy: 0.0001)

        // Endpoints are exact, and a fade that lands on zero alpha keeps the
        // hue it was heading for rather than becoming a transparent black.
        XCTAssertEqual(clear.interpolated(to: white, progress: 0), clear)
        XCTAssertEqual(clear.interpolated(to: white, progress: 1), white)
        let landed = white.interpolated(to: Color(red: 1, green: 1, blue: 1, alpha: 0), progress: 1)
        XCTAssertEqual(Double(landed.red), 1.0, accuracy: 0.0001)
    }

    /// Endpoints that share an alpha are untouched by the change — which is
    /// every opaque cross-fade and every sheen gradient in the stack, and the
    /// reason no baseline moved.
    func testInterpolationBetweenEqualAlphaEndpointsIsUnchanged() async {
        let a = Color(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.6)
        let b = Color(red: 0.9, green: 0.8, blue: 0.7, alpha: 0.6)
        let mid = a.interpolated(to: b, progress: 0.5)
        XCTAssertEqual(Double(mid.red), 0.5, accuracy: 0.0001)
        XCTAssertEqual(Double(mid.green), 0.5, accuracy: 0.0001)
        XCTAssertEqual(Double(mid.blue), 0.5, accuracy: 0.0001)
        XCTAssertEqual(Double(mid.alpha), 0.6, accuracy: 0.0001)
    }

    /// The same rule where the audit rasterised it: a white overlay scroll
    /// thumb revealing from nothing is white on its first visible frame.
    /// Measured before the fix at (0.069, 0.069, 0.069) alpha 0.033 at t=8ms
    /// and (0.347, 0.347, 0.347) alpha 0.167 at t=42ms — a near-black smudge
    /// that gradually became a thumb.
    func testAnOverlayScrollThumbRevealsWhiteRatherThanBlack() async {
        let clock = TestClock()
        let (runtime, scroll) = makeScrollHost(clock)
        scroll.scrollIndicatorAutoHides = true
        scroll.showsScrollIndicator = true
        let target = Color(red: 1, green: 1, blue: 1, alpha: 0.48)
        scroll.scrollIndicatorIdleColor = target
        scroll.scrollIndicatorColor = Color(red: 0, green: 0, blue: 0, alpha: 0)

        let t0 = clock.now
        runtime.flashScrollIndicator(for: scroll)
        // The reveal is armed on this tick and starts its tween on it.
        tick(runtime, clock, to: t0)

        let duration = RetainedViewRuntime.scrollIndicatorRevealDuration
        for fraction in [0.1, 0.25, 0.5, 0.75] {
            tick(runtime, clock, to: t0 + duration * fraction)
            let colour = scroll.scrollIndicatorColor
            guard colour.alpha > 0.001 else { continue }
            XCTAssertEqual(
                Double(colour.red), 1.0, accuracy: 0.002,
                "at \(fraction) of the reveal the thumb is white, not a grey on its way to white")
            XCTAssertEqual(Double(colour.green), 1.0, accuracy: 0.002)
            XCTAssertEqual(Double(colour.blue), 1.0, accuracy: 0.002)
            XCTAssertLessThan(Double(colour.alpha), 0.48, "and is still arriving")
        }
    }

    // MARK: - The first build is a state, not an insertion

    private func makeTransitioningListHost(
        _ clock: TestClock, rows: @escaping () -> [String]
    ) -> (RetainedViewRuntime, ComponentHost) {
        let runtime = makeRuntime(clock)
        let host = ComponentHost(runtime: runtime)
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 420, height: 320) },
            invalidateHandler: { [weak host] in host?.reload() }
        )
        host.setComponents {
            [
                VStack {
                    ForEach(rows(), id: \.self) { row in
                        Text(row)
                            .transition(.opacity)
                    }
                }
                .frame(width: 420, height: 320)
                .makeComponent(context: context)
            ]
        }
        return (runtime, host)
    }

    /// The audit built a three-row list with `.transition(.opacity)` for the
    /// first time and read the tree immediately: all three rows at opacity
    /// 0.000, one animation state each, still at 0.175 a tenth of a second
    /// later. SwiftUI does not transition a view that is present in the first
    /// render of its container.
    func testAHostsFirstBuildDoesNotPlayItsTransitions() async {
        let clock = TestClock()
        var rows = ["alpha", "beta", "gamma"]
        let (runtime, host) = makeTransitioningListHost(clock, rows: { rows })

        let texts = collectNodes(runtime.root, where: { $0.text != nil })
        XCTAssertEqual(texts.count, 3, "three rows built")
        for node in texts {
            XCTAssertEqual(node.opacity, 1.0, accuracy: 0.0001, "'\(node.text ?? "")' is present, not arriving")
            XCTAssertTrue(node.animationStates.isEmpty, "'\(node.text ?? "")' has nothing in flight")
        }
        XCTAssertFalse(
            runtime.hasActiveAnimations,
            "a window that has only just been given its content is not animating")

        // A rebuild before the first frame is still the initial state.
        host.reload()
        for node in collectNodes(runtime.root, where: { $0.text != nil }) {
            XCTAssertEqual(node.opacity, 1.0, accuracy: 0.0001)
        }
        XCTAssertFalse(runtime.hasActiveAnimations)

        // A genuine insertion afterwards still transitions.
        _ = runtime.renderFrame()
        rows.append("delta")
        host.reload()
        guard let inserted = findNode(runtime.root, where: { $0.text == "delta" }) else {
            return XCTFail("the new row was not built")
        }
        XCTAssertEqual(inserted.opacity, 0.0, accuracy: 0.0001, "an insertion into an existing container fades in")
        XCTAssertFalse(inserted.animationStates.isEmpty)
        for name in ["alpha", "beta", "gamma"] {
            guard let existing = findNode(runtime.root, where: { $0.text == name }) else {
                return XCTFail("row \(name) vanished")
            }
            XCTAssertEqual(existing.opacity, 1.0, accuracy: 0.0001, "\(name) was already there and does not replay")
        }
    }

    // MARK: - The disclosure opens

    private final class ExpansionBox {
        var isExpanded = false
        var builds = 0
    }

    private func makeDisclosureHost(_ clock: TestClock) -> (RetainedViewRuntime, ComponentHost, ExpansionBox) {
        let runtime = makeRuntime(clock)
        let host = ComponentHost(runtime: runtime)
        let box = ExpansionBox()
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 420, height: 320) },
            invalidateHandler: { [weak host] in host?.reload() }
        )
        host.setComponents {
            box.builds += 1
            return [
                VStack {
                    DisclosureGroup(
                        "Details",
                        isExpanded: Binding(get: { box.isExpanded }, set: { box.isExpanded = $0 })
                    ) {
                        Text("Body")
                    }
                }
                .frame(width: 420, height: 320)
                .makeComponent(context: context)
            ]
        }
        _ = runtime.renderFrame()
        return (runtime, host, box)
    }

    /// The audit drove a disclosure open through the runtime and found the
    /// body at full opacity and full height in one frame, with
    /// `hasActiveAnimations` false immediately after the rebuild — nothing in
    /// flight for the runtime to tick.
    func testDisclosureExpansionAnimatesItsChevronAndItsBody() async {
        let clock = TestClock()
        // The host must stay alive: the rebuild the header press triggers goes
        // through `invalidateHandler`, which holds it weakly.
        let (runtime, host, box) = makeDisclosureHost(clock)
        defer { withExtendedLifetime(host) {} }
        guard let header = findNode(runtime.root, where: { $0.accessibilityTraits.contains(.isButton) }) else {
            return XCTFail("no disclosure header")
        }
        guard let chevron = findNode(runtime.root, where: { $0.text == ">" }) else {
            return XCTFail("no chevron glyph — the disclosure should turn one glyph, not swap two")
        }
        XCTAssertEqual(chevron.transform.rotation, 0, accuracy: 0.0001, "closed: the chevron points along the header")

        let frame = absoluteFrame(of: header)
        let centre = Point(x: frame.midX, y: frame.midY)
        runtime.pointerMoved(to: centre)
        runtime.pointerDown(at: centre)
        let t0 = clock.now
        runtime.pointerUp(at: centre)

        XCTAssertTrue(box.isExpanded, "the header press toggled the disclosure open")
        XCTAssertTrue(
            runtime.hasActiveAnimations,
            "opening a disclosure puts something in flight — before this the rebuild settled in one frame")

        guard let openChevron = findNode(runtime.root, where: { $0.text == ">" }) else {
            return XCTFail("chevron vanished on expand")
        }
        guard let text = findNode(runtime.root, where: { $0.text == "Body" }) else {
            let texts = collectNodes(runtime.root, where: { $0.text != nil }).map { $0.text ?? "" }
            return XCTFail(
                "the disclosure did not expand; builds=\(box.builds) open=\(box.isExpanded) texts=\(texts)")
        }

        // The reveal is carried by the inserted wrapper the disclosure builds
        // around its content, which is what the transition is attached to.
        var revealed: ViewNode? = text
        while let node = revealed, node.transition.kind == .identity {
            revealed = node.parent
        }
        guard let body = revealed else {
            return XCTFail("the revealed content carries no transition — it appeared in one frame")
        }

        let duration = Controls.disclosureDuration
        tick(runtime, clock, to: t0 + duration * 0.25)
        let quarterRotation = openChevron.transform.rotation
        let quarterOpacity = body.opacity
        let quarterOffset = body.transform.translationY
        XCTAssertGreaterThan(quarterRotation, 0.0, "the chevron is turning")
        XCTAssertLessThan(
            quarterRotation, Controls.disclosureOpenRotation - 0.01,
            "and has not arrived a quarter of the way through")
        XCTAssertGreaterThan(quarterOpacity, 0.0)
        XCTAssertLessThan(quarterOpacity, 0.99, "the body is fading in, not appearing")
        XCTAssertLessThan(quarterOffset, 0.0, "and sliding down out from under the header")

        tick(runtime, clock, to: t0 + duration * 0.75)
        XCTAssertGreaterThan(openChevron.transform.rotation, quarterRotation, "the turn keeps going")
        XCTAssertGreaterThan(body.opacity, quarterOpacity, "so does the fade")
        XCTAssertGreaterThan(body.transform.translationY, quarterOffset, "so does the slide")

        advance(runtime, clock, to: t0 + duration * 2)
        XCTAssertEqual(
            openChevron.transform.rotation, Controls.disclosureOpenRotation, accuracy: 0.001,
            "open: the chevron points down")
        XCTAssertEqual(body.opacity, 1.0, accuracy: 0.001, "and the body is fully there")
        XCTAssertEqual(body.transform.translationY, 0.0, accuracy: 0.001, "at its resting place")
        XCTAssertFalse(runtime.hasActiveAnimations, "with nothing left in flight")
    }

    // MARK: - A wheel push against a stationary edge

    private func makeScrollHost(
        _ clock: TestClock, contentHeight: Double = 1_200
    ) -> (RetainedViewRuntime, ViewNode) {
        let runtime = makeRuntime(clock)
        let content = ViewNode(
            backgroundColor: .white, preferredSize: Size(width: 200, height: contentHeight))
        let scroll = ViewNode(
            frame: Rect(x: 0, y: 0, width: 200, height: 200),
            layoutMode: .stack(.vertical(spacing: 0, alignment: .stretch)),
            scrollAxis: .vertical,
            scrollStep: 16,
            children: [content])
        runtime.root.addChild(scroll)
        _ = runtime.renderFrame()
        return (runtime, scroll)
    }

    /// With a scroll view resting at offset 0, the audit sent a wheel event in
    /// the 'up' direction and ticked at 60 Hz for two seconds: offset 0.0000,
    /// overshoot 0.000 and `hasActiveAnimations` false at every sample. The
    /// documented rubber band was reachable only from an already-moving glide,
    /// so a user pushing against a stationary edge got no bounce, no overshoot
    /// and not even an indicator flash.
    func testWheelPushAgainstAStationaryEdgeBouncesAndSpringsBack() async {
        let clock = TestClock()
        let (runtime, scroll) = makeScrollHost(clock)
        XCTAssertEqual(scroll.scrollOffset, 0, accuracy: 0.0001, "resting at the top bound")

        // There is somewhere to scroll to: a push the other way moves.
        runtime.mouseWheel(at: Point(x: 100, y: 100), delta: -1)
        XCTAssertGreaterThan(scroll.scrollOffset, 0, "the view can scroll")
        scroll.scrollOffset = 0
        scroll.scrollOvershoot = 0
        _ = runtime.renderFrame()

        let t0 = clock.now
        runtime.mouseWheel(at: Point(x: 100, y: 100), delta: 3)

        XCTAssertEqual(scroll.scrollOffset, 0, accuracy: 0.0001, "the offset itself stays clamped")
        XCTAssertLessThan(scroll.scrollOvershoot, 0, "the refused push becomes visible overshoot")
        XCTAssertGreaterThan(
            scroll.scrollOvershoot, -80.0001, "capped at the documented rubber-band maximum")
        XCTAssertTrue(runtime.hasActiveAnimations, "and the spring is registered so the host keeps ticking")

        let peak = scroll.scrollOvershoot
        var sawMotion = false
        var settledAt: Double?
        var time = t0
        while time < t0 + 1.5 {
            time += 1.0 / 60.0
            tick(runtime, clock, to: time)
            if scroll.scrollOvershoot != peak { sawMotion = true }
            if scroll.scrollOvershoot == 0, settledAt == nil { settledAt = time - t0 }
        }
        XCTAssertTrue(sawMotion, "the band has to move, not sit at its excursion")
        guard let settled = settledAt else {
            return XCTFail("the band never returned to rest")
        }
        XCTAssertLessThan(settled, 0.6, "a macOS bounce is back in well under a second")
        XCTAssertEqual(scroll.scrollOffset, 0, accuracy: 0.0001, "and the logical offset never moved")
        XCTAssertFalse(runtime.hasActiveAnimations, "nothing left in flight once it has settled")
    }

    /// A view with nothing to scroll must sit perfectly still: a bounce there
    /// would be feedback for an input that was never meaningful.
    func testWheelPushOnAViewWithNothingToScrollDoesNothing() async {
        let clock = TestClock()
        let (runtime, scroll) = makeScrollHost(clock, contentHeight: 100)

        runtime.mouseWheel(at: Point(x: 100, y: 100), delta: 3)
        XCTAssertEqual(scroll.scrollOvershoot, 0, accuracy: 0.0001)
        XCTAssertEqual(scroll.scrollOffset, 0, accuracy: 0.0001)
        XCTAssertFalse(runtime.hasActiveAnimations)
    }

    /// The stretch curve itself: WebKit's `ScrollElasticityController` shape,
    /// unit slope at zero and asymptotic to `dimension / 0.55`, so a hard push
    /// leans in rather than snapping to the cap.
    func testRubberBandStretchResistsProgressively() async {
        let dimension = 200.0
        let small = RetainedViewRuntime.rubberBandStretch(forRefusedDistance: 4, viewportDimension: dimension)
        XCTAssertEqual(small, 4, accuracy: 0.25, "the first few points track the push")

        var previous = 0.0
        var previousGain = Double.infinity
        for distance in stride(from: 20.0, through: 400.0, by: 20.0) {
            let stretch = RetainedViewRuntime.rubberBandStretch(
                forRefusedDistance: distance, viewportDimension: dimension)
            XCTAssertGreaterThan(stretch, previous, "monotonic in the push")
            let gain = stretch - previous
            XCTAssertLessThan(gain, previousGain + 0.0001, "each additional point of push gives back less")
            XCTAssertLessThan(stretch, dimension / 0.55, "and never passes the asymptote")
            previous = stretch
            previousGain = gain
        }

        XCTAssertEqual(
            RetainedViewRuntime.rubberBandStretch(forRefusedDistance: -40, viewportDimension: dimension),
            -RetainedViewRuntime.rubberBandStretch(forRefusedDistance: 40, viewportDimension: dimension),
            accuracy: 0.0001, "symmetric about the bound")
    }

    // MARK: - Deferred rebuilds are on the animation clock

    /// The mechanism `PhaseAnimator` now advances on. A pending deadline is
    /// represented in `hasActiveAnimations` — the exposure the audit reported
    /// was a phase with a nil or zero-duration animation, where nothing else
    /// is registered and the host is free to switch its timer off.
    func testADeferredRebuildFiresOnTheAnimationClockAndHoldsTheTimerOpen() async {
        let clock = TestClock()
        let runtime = makeRuntime(clock)
        var fired = 0

        runtime.scheduleDeferredRebuild(key: "probe", delay: 0.20) { fired += 1 }
        XCTAssertTrue(runtime.hasDeferredRebuild(key: "probe"))
        XCTAssertTrue(runtime.hasActiveAnimations, "a pending phase keeps the host ticking")

        tick(runtime, clock, to: clock.now + 0.10)
        XCTAssertEqual(fired, 0, "not due yet")
        XCTAssertTrue(runtime.hasActiveAnimations)

        tick(runtime, clock, to: clock.now + 0.11)
        XCTAssertEqual(fired, 1, "due, and fired from the tick rather than from a sleep")
        XCTAssertFalse(runtime.hasDeferredRebuild(key: "probe"))
        XCTAssertFalse(runtime.hasActiveAnimations, "and it does not re-arm itself")

        tick(runtime, clock, to: clock.now + 1.0)
        XCTAssertEqual(fired, 1, "one-shot")

        // A zero-duration deadline is still a deadline: it fires on the next
        // tick, not on a scheduler hop of unknown length.
        runtime.scheduleDeferredRebuild(key: "immediate", delay: 0) { fired += 1 }
        XCTAssertTrue(runtime.hasActiveAnimations)
        tick(runtime, clock, to: clock.now + 1.0 / 60.0)
        XCTAssertEqual(fired, 2)

        runtime.scheduleDeferredRebuild(key: "cancelled", delay: 0.05) { fired += 1 }
        runtime.cancelDeferredRebuild(key: "cancelled")
        tick(runtime, clock, to: clock.now + 1.0)
        XCTAssertEqual(fired, 2, "a cancelled deadline never runs")
        XCTAssertFalse(runtime.hasActiveAnimations)
    }

    /// End to end: a `PhaseAnimator` advances because the frame clock reached
    /// its deadline, with no `Task.sleep` anywhere in the path — so the phase
    /// boundary is reproducible and lands on a frame.
    func testPhaseAnimatorAdvancesOnTheFrameClock() async {
        let clock = TestClock()
        let runtime = makeRuntime(clock)
        let host = ComponentHost(runtime: runtime)
        defer { withExtendedLifetime(host) {} }
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 420, height: 320) },
            invalidateHandler: { [weak host] in host?.reload() }
        )
        host.setComponents {
            [
                Text("Phased")
                    .phaseAnimator(["first", "second"]) { content, phase in
                        content.opacity(phase == "first" ? 0.25 : 1.0)
                    } animation: { _ in
                        .linear(duration: 0.20)
                    }
                    .makeComponent(context: context)
            ]
        }
        _ = runtime.renderFrame()

        guard let node = findNode(runtime.root, where: { $0.phaseAnimatorState != nil }) else {
            return XCTFail("no phase animator in the tree")
        }
        XCTAssertEqual(node.phaseAnimatorState?.currentPhaseIndex, 0)
        XCTAssertTrue(
            runtime.hasActiveAnimations,
            "a phase animator waiting out a phase has to keep the host's timer on — before this the pending "
                + "sleep was represented nowhere and the timer could stop between phases")

        tick(runtime, clock, to: clock.now + 0.10)
        let midway = findNode(runtime.root, where: { $0.phaseAnimatorState != nil })
        XCTAssertEqual(midway?.phaseAnimatorState?.currentPhaseIndex, 0, "half a phase in, still the first phase")

        tick(runtime, clock, to: clock.now + 0.12)
        guard let advanced = findNode(runtime.root, where: { $0.phaseAnimatorState != nil }) else {
            return XCTFail("the phase animator left the tree")
        }
        XCTAssertEqual(
            advanced.phaseAnimatorState?.currentPhaseIndex, 1,
            "the boundary landed on the frame the deadline fell in")
    }

    /// `tickAnimations` has to report the rebuild, or the host will decide the
    /// frame produced nothing and skip the render that shows the new phase.
    func testTickReportsWorkWhenOnlyADeferredRebuildRan() async {
        let clock = TestClock()
        let runtime = makeRuntime(clock)
        runtime.scheduleDeferredRebuild(key: "probe", delay: 0.05) {}
        clock.now += 0.10
        XCTAssertTrue(runtime.tickAnimations(at: clock.now))
        XCTAssertFalse(runtime.tickAnimations(at: clock.now))
    }

    // MARK: - One clock

    /// The structural guarantee the rest of this file rests on: with the
    /// runtime's clock injected, a tween seeded by a pointer event lands on the
    /// timeline the test ticks. Before this the seed came from the wall clock
    /// and the tween was already over — or had not started — by any timestamp a
    /// test could name.
    func testControlTweensAreSeededOnTheInjectedClock() async {
        let clock = TestClock()
        let (runtime, _) = makeButtonHost(clock)
        guard let button = button(in: runtime) else { return XCTFail("no button in tree") }
        guard let surface = button.interactionSurface else { return XCTFail("no interaction surface") }
        let duration = surface.duration(intoPhase: .hovered)
        let start = Double(button.backgroundColor?.alpha ?? 0)

        // Seed at an arbitrary point on an arbitrary timeline.
        clock.now = 5_000.0
        let frame = absoluteFrame(of: button)
        runtime.pointerMoved(to: Point(x: frame.midX, y: frame.midY))

        // A tick *before* the seed must not advance it.
        tick(runtime, clock, to: 4_999.0)
        XCTAssertEqual(Double(button.backgroundColor?.alpha ?? 0), start, accuracy: 0.0001)

        tick(runtime, clock, to: 5_000.0 + duration * 0.5)
        let halfway = Double(button.backgroundColor?.alpha ?? 0)
        XCTAssertNotEqual(halfway, start, accuracy: 0.0005, "half a tween in, the fill has moved")

        tick(runtime, clock, to: 5_000.0 + duration + 0.0001)
        let settled = Double(button.backgroundColor?.alpha ?? 0)
        XCTAssertNotEqual(settled, halfway, accuracy: 0.0005, "and it kept going to the end")
        XCTAssertFalse(runtime.hasActiveAnimations, "the tween retires exactly at its own duration")
    }
}
