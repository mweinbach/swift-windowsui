import Foundation

import SwiftWindowsCore

import SwiftWindowsGraphics

import SwiftWindowsPlatform

import XCTest

@testable import SwiftWindowsUI

/// Drives every animation source simultaneously across multiple view types
/// in a single tree, then runs sustained simulated frames to prove no
/// subsystem strands the runtime in a never-settling state.
///
/// Subsystems exercised together:
/// - Button color cross-fades and press-scale transitions.
/// - Scroll momentum on a wheel-driven container.
/// - Rubber-band overshoot at scroll edges.
/// - Animated keyboard-scroll presented-delta tween.
/// - Material backdrop blur background (static, just to verify the
///   blurred-quad path keeps emitting under continuous animation).
@testable import WinSwiftUI

@MainActor
final class ContinuousAnimationCrossViewTests: XCTestCase {

    func testExplicitAnimationsSurviveRebuildsAndRetargetFromThePresentedValues() async {
        let clock = RuntimeTestClock()
        clock.now = 10
        let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 300, height: 200)))
        runtime.clock = { clock.now }
        let host = ComponentHost(runtime: runtime)
        var width = 20.0
        var opacity = 1.0
        var translation = 0.0
        var color = Color.black
        host.setContent {
            Component { _ in
                let node = ViewNode(frame: Rect(x: 0, y: 0, width: width, height: 20), backgroundColor: color)
                node.opacity = opacity
                node.transform.translationX = translation
                return node
            }
        }
        let node = runtime.root.children[0]
        withAnimation(.linear(duration: 1)) {
            width = 120
            opacity = 0.2
            translation = 50
            color = .white
            host.reload()
        }

        clock.now = 10.4
        _ = runtime.tickAnimations(at: clock.now)
        host.reload()
        XCTAssertEqual(node.frame.size.width, 60, accuracy: 0.0001)
        XCTAssertEqual(node.opacity, 0.68, accuracy: 0.0001)
        XCTAssertEqual(node.transform.translationX, 20, accuracy: 0.0001)
        XCTAssertEqual(node.backgroundColor?.red ?? -1, 0.4, accuracy: 0.0001)
        XCTAssertEqual(node.animationStates[.frameWidth]?.startTime, 10)
        XCTAssertEqual(node.animationStates[.opacity]?.startTime, 10)

        clock.now = 10.6
        _ = runtime.tickAnimations(at: clock.now)
        withAnimation(.linear(duration: 0.5)) {
            width = 20
            opacity = 1
            translation = 0
            color = .black
            host.reload()
        }
        XCTAssertEqual(node.animationStates[.frameWidth]?.startValue ?? -1, 80, accuracy: 0.0001)
        XCTAssertEqual(node.animationStates[.opacity]?.startValue ?? -1, 0.52, accuracy: 0.0001)

        clock.now = 10.85
        _ = runtime.tickAnimations(at: clock.now)
        XCTAssertEqual(node.frame.size.width, 50, accuracy: 0.0001)
        XCTAssertEqual(node.opacity, 0.76, accuracy: 0.0001)
        XCTAssertEqual(node.transform.translationX, 15, accuracy: 0.0001)
        XCTAssertEqual(node.backgroundColor?.red ?? -1, 0.3, accuracy: 0.0001)

        clock.now = 11.1
        _ = runtime.tickAnimations(at: clock.now)
        XCTAssertEqual(node.frame.size.width, 20)
        XCTAssertEqual(node.opacity, 1)
        XCTAssertEqual(node.transform.translationX, 0)
        XCTAssertEqual(node.backgroundColor, .black)
        XCTAssertFalse(runtime.hasActiveAnimations)

        width = 100
        host.reload()
        withAnimation(.bouncy) {
            width = 1
            host.reload()
        }
        let springStartedAt = clock.now
        clock.now += 0.35
        _ = runtime.tickAnimations(at: clock.now)
        _ = runtime.renderFrame()
        XCTAssertGreaterThan(node.frame.size.width, 0)
        XCTAssertLessThan(node.resolvedFrame.size.width, 1)
        host.reload()
        _ = runtime.renderFrame()
        XCTAssertLessThan(node.resolvedFrame.size.width, 1)
        XCTAssertEqual(node.animationStates[.frameWidth]?.startTime, springStartedAt)
        clock.now += 3
        _ = runtime.tickAnimations(at: clock.now)
        XCTAssertEqual(node.frame.size.width, 1)
        XCTAssertFalse(runtime.hasActiveAnimations)
    }

    func testRemovingAnAnimatedFillCancelsEveryColorChannel() async {
        let clock = RuntimeTestClock()
        clock.now = 10
        let runtime = RetainedViewRuntime(root: ViewNode())
        runtime.clock = { clock.now }
        let host = ComponentHost(runtime: runtime)
        var color: Color? = .black
        var gradient: GradientType? = .linear(
            SwiftWindowsGraphics.LinearGradient(startColor: .black, endColor: .black, axis: .vertical))
        host.setContent {
            Component { _ in
                ViewNode(
                    frame: Rect(x: 0, y: 0, width: 40, height: 30),
                    backgroundColor: color, backgroundGradient: gradient)
            }
        }
        let node = runtime.root.children[0]
        withAnimation(.linear(duration: 1)) {
            color = .white
            gradient = .linear(
                SwiftWindowsGraphics.LinearGradient(startColor: .white, endColor: .white, axis: .vertical))
            host.reload()
        }
        clock.now = 10.25
        _ = runtime.tickAnimations(at: clock.now)
        XCTAssertTrue(runtime.hasActiveAnimations)

        color = nil
        gradient = nil
        host.reload()
        _ = runtime.tickAnimations(at: 11)

        XCTAssertNil(node.backgroundColor, "A cancelled colour tween must not resurrect a removed fill")
        XCTAssertNil(node.backgroundGradient)
        XCTAssertFalse(runtime.hasActiveAnimations)
    }

    func testRebuildPreservesPressedChromeMotionAndItsPaintedGradient() async {
        let clock = RuntimeTestClock()
        clock.now = 10
        let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 100)))
        runtime.clock = { clock.now }
        let host = ComponentHost(runtime: runtime)
        let palette = SurfacePalette(
            idle: .black, hovered: .black, focused: .black, pressed: .white, pressedContentOpacity: 0.5)
        host.setContent {
            Component { runtime in
                Controls.button(
                    runtime: runtime, frame: Rect(x: 10, y: 10, width: 100, height: 40), cornerRadius: 6,
                    palette: palette, chrome: SurfaceChrome(),
                    animation: ControlAnimationStyle(focusDuration: 1, pressDuration: 1, pressedScale: 0.8),
                    appliesSurfaceSheen: true, action: {})
            }
        }
        _ = runtime.renderFrame()
        let node = runtime.root.children[0]
        runtime.pointerMoved(to: Point(x: 30, y: 30))
        runtime.pointerDown(at: Point(x: 30, y: 30))
        XCTAssertEqual(node.transform.scaleX, 1, "A press starts at the current scale, not its destination")
        XCTAssertEqual(node.opacity, 1)

        clock.now = 10.4
        _ = runtime.tickAnimations(at: clock.now)
        host.reload()
        XCTAssertEqual(node.backgroundColor?.red ?? -1, 0.32, accuracy: 0.0001)
        XCTAssertEqual(node.backgroundGradient, Controls.backgroundSheen(for: node.backgroundColor ?? .clear))
        XCTAssertEqual(node.transform.scaleX, 0.872, accuracy: 0.0001)
        XCTAssertEqual(node.opacity, 0.68, accuracy: 0.0001)
        XCTAssertEqual(node.animationStates[.transformScaleX]?.startTime, 10)
        XCTAssertEqual(node.animationStates[.opacity]?.startTime, 10)

        clock.now = 10.7
        _ = runtime.tickAnimations(at: clock.now)
        XCTAssertEqual(node.backgroundColor?.red ?? -1, 0.82, accuracy: 0.0001)
        XCTAssertEqual(node.backgroundGradient, Controls.backgroundSheen(for: node.backgroundColor ?? .clear))
        XCTAssertEqual(node.transform.scaleX, 0.818, accuracy: 0.0001)
        XCTAssertEqual(node.opacity, 0.545, accuracy: 0.0001)
    }

    private func makeMixedRuntime() -> (RetainedViewRuntime, scroll: ViewNode, button: ViewNode) {
        let palette = SurfacePalette(
            idle: Color(red: 0.20, green: 0.30, blue: 0.50, alpha: 1),
            focused: Color(red: 0.30, green: 0.40, blue: 0.60, alpha: 1),
            pressed: Color(red: 0.45, green: 0.55, blue: 0.75, alpha: 1)
        )
        let root = ViewNode(
            frame: Rect(x: 0, y: 0, width: 360, height: 240),
            isHitTestVisible: false
        )
        let runtime = RetainedViewRuntime(root: root)

        // Scroll container with 12 rows so momentum has somewhere to travel.
        var rows: [ViewNode] = []
        for index in 0..<12 {
            rows.append(
                ViewNode(
                    frame: Rect(x: 0, y: 0, width: 220, height: 40),
                    backgroundColor: Color(
                        red: Float(index) / 12, green: 0.4, blue: 0.6, alpha: 1),
                    preferredSize: Size(width: 220, height: 40)
                )
            )
        }
        let scroll = ViewNode(
            frame: Rect(x: 10, y: 10, width: 240, height: 200),
            layoutMode: .stack(.vertical(spacing: 6)),
            scrollAxis: .vertical,
            scrollStep: 30,
            showsScrollIndicator: true,
            isHitTestVisible: false,
            children: rows
        )

        // Real button (has hover/press color + scale animation paths).
        let button = Controls.button(
            runtime: runtime,
            frame: Rect(x: 270, y: 20, width: 80, height: 36),
            cornerRadius: 8,
            palette: palette,
            chrome: SurfaceChrome(),
            animation: ControlAnimationStyle(focusDuration: 0.12, pressDuration: 0.10),
            action: {}
        )

        root.addChild(scroll)
        root.addChild(button)
        _ = runtime.renderFrame()
        return (runtime, scroll, button)
    }

    func testAllAnimationSourcesRunSimultaneouslyAndSettle() async {
        await MainActor.run {
            allAnimationSourcesRunSimultaneouslyAndSettleBody()
        }
    }

    private func allAnimationSourcesRunSimultaneouslyAndSettleBody() {
        let (runtime, scroll, button) = makeMixedRuntime()
        var t = Win32Window.currentTimestampSeconds()

        // Kick every subsystem at the start.
        runtime.mouseWheel(at: Point(x: scroll.frame.midX, y: scroll.frame.midY), delta: -4)
        runtime.pointerMoved(to: Point(x: button.frame.midX, y: button.frame.midY))
        runtime.pointerDown(at: Point(x: button.frame.midX, y: button.frame.midY))
        runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.downArrow.rawValue))

        XCTAssertTrue(runtime.hasActiveAnimations, "Every subsystem should be in flight initially")

        // Drive 60-fps frames for ~10 simulated seconds. Verify the runtime
        // never panics, that ticks are accepted, and that animations
        // eventually drain.
        var frameCount = 0
        while runtime.hasActiveAnimations, frameCount < 1200 {
            t += 1.0 / 60.0
            _ = runtime.tickAnimations(at: t)
            // Occasionally re-render to exercise the scene painter while
            // animations are active.
            if frameCount % 4 == 0 {
                _ = runtime.renderScene(at: t)
            }
            frameCount += 1
        }

        // Release the button so its press animation also drains.
        runtime.pointerUp(at: Point(x: button.frame.midX, y: button.frame.midY))
        var settleFrames = 0
        while runtime.hasActiveAnimations, settleFrames < 1200 {
            t += 1.0 / 60.0
            _ = runtime.tickAnimations(at: t)
            settleFrames += 1
        }

        XCTAssertFalse(
            runtime.hasActiveAnimations,
            "Every concurrent animation source must settle within the simulated budget")
        XCTAssertEqual(scroll.scrollOvershoot, 0, "Rubber-band overshoot must zero out")
        XCTAssertEqual(scroll.scrollPresentedDelta, 0, "Presented-delta tween must zero out")
        XCTAssertTrue(scroll.animationStates.isEmpty)
        XCTAssertTrue(button.animationStates.isEmpty)
    }

    func testRepeatedConcurrentAnimationsLeaveNoPerNodeResidue() async {
        await MainActor.run {
            repeatedConcurrentAnimationsLeaveNoPerNodeResidueBody()
        }
    }

    private func repeatedConcurrentAnimationsLeaveNoPerNodeResidueBody() {
        let (runtime, scroll, button) = makeMixedRuntime()
        var t = Win32Window.currentTimestampSeconds()

        // 200 rounds of: wheel + button press/release + key, plus a tick
        // each round. Exercises interleaved animation seeding to catch
        // races between subsystems.
        for round in 0..<200 {
            runtime.mouseWheel(
                at: Point(x: scroll.frame.midX, y: scroll.frame.midY),
                delta: round.isMultiple(of: 2) ? -1 : 1
            )
            runtime.pointerDown(at: Point(x: button.frame.midX, y: button.frame.midY))
            runtime.pointerUp(at: Point(x: button.frame.midX, y: button.frame.midY))
            if round.isMultiple(of: 3) {
                runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.downArrow.rawValue))
            }
            t += 1.0 / 60.0
            _ = runtime.tickAnimations(at: t)
        }

        // Drain.
        var ticks = 0
        while runtime.hasActiveAnimations, ticks < 2400 {
            t += 1.0 / 60.0
            _ = runtime.tickAnimations(at: t)
            ticks += 1
        }
        XCTAssertFalse(runtime.hasActiveAnimations)
        XCTAssertTrue(scroll.animationStates.isEmpty)
        XCTAssertTrue(button.animationStates.isEmpty)
        XCTAssertEqual(scroll.scrollOvershoot, 0)
        XCTAssertEqual(scroll.scrollPresentedDelta, 0)
    }
}
extension Rect {
    fileprivate var midX: Double { origin.x + size.width / 2 }
    fileprivate var midY: Double { origin.y + size.height / 2 }
}
