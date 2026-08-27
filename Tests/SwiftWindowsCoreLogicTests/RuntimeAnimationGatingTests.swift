import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsPlatform
import XCTest

@testable import SwiftWindowsUI

/// `hasActiveAnimations` is the sole gate on the host's animation timer
/// (`App.swift`: `shouldDriveFrames = runtime.hasActiveAnimations ||
/// runtime.isDirty || …`). Anything that needs a tick to finish has to be
/// visible through it, or it stops mid-flight and never resumes: the frame
/// that starts the animation is also the frame that clears `dirtyFlags`, and
/// with nothing else reporting activity the timer is switched off.
final class RuntimeAnimationGatingTests: XCTestCase {

    func testRemovalOverlayRepaintsIntermediateFrameAndSceneSamples() async {
        await MainActor.run {
            for scenePath in [false, true] {
                let clock = RuntimeTestClock()
                clock.now = 10
                let child = ViewNode(
                    frame: Rect(x: 10, y: 10, width: 40, height: 30), backgroundColor: .white,
                    transition: RetainedTransition(kind: .opacity))
                let root = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 100), children: [child])
                let runtime = RetainedViewRuntime(root: root)
                runtime.clock = { clock.now }
                let paintedAlpha: @MainActor () -> Float = {
                    if scenePath {
                        return runtime.renderScene().layers.flatMap(\.quads).first?.startA ?? -1
                    }
                    return runtime.renderFrame().commands.compactMap { command -> Float? in
                        guard case .fillRect(let fill) = command else { return nil }
                        return fill.color.alpha
                    }.first ?? -1
                }

                XCTAssertEqual(paintedAlpha(), 1)
                root.removeChild(child)
                XCTAssertEqual(paintedAlpha(), 1)
                XCTAssertFalse(runtime.isDirty)

                clock.now += 0.175
                XCTAssertTrue(runtime.tickAnimations(at: clock.now))
                XCTAssertTrue(runtime.isDirty, "A detached overlay must dirty its owning runtime each frame")
                XCTAssertEqual(paintedAlpha(), 0.5, accuracy: 0.0001)

                clock.now += 0.0875
                _ = runtime.tickAnimations(at: clock.now)
                XCTAssertEqual(paintedAlpha(), 0.125, accuracy: 0.0001)
                XCTAssertEqual(runtime.transitionOverlays.count, 1)
            }
        }
    }

    func testZeroAndSubmillisecondPropertyAnimationsFinishAtTheirDeadline() async {
        await MainActor.run {
            for duration in [0.0, 0.0001] {
                let node = ViewNode(frame: Rect(x: 0, y: 0, width: 40, height: 30))
                let runtime = RetainedViewRuntime(root: node)
                node.opacity = 0.2
                node.animationStates[.opacity] = AnimationState(
                    startValue: 0.2, endValue: 0.8, startTime: 0, duration: duration, easing: .linear)

                _ = runtime.tickAnimations(at: duration)

                XCTAssertEqual(node.opacity, 0.8)
                XCTAssertTrue(node.animationStates.isEmpty)
                XCTAssertFalse(runtime.hasActiveAnimations)
            }
        }
    }

    func testCompletedCurvesReachTheExactDeclaredScalarAndColorEndpoints() async {
        await MainActor.run {
            let curve = AnimationEasing.timingCurve(c0x: 0.2, c0y: 0.1, c1x: 0.8, c1y: 0.9)
            let state = AnimationState(startValue: 0.2, endValue: 0.8, startTime: 0, duration: 1, easing: curve)
            let color = Color(red: 0.8, green: 0.6, blue: 0.4, alpha: 0.5)
            let colorState = ColorAnimationState(
                startColor: .clear, endColor: color, startTime: 0, duration: 1, easing: curve)
            let node = ViewNode()
            let runtime = RetainedViewRuntime(root: node)
            node.animationStates[.opacity] = state

            _ = runtime.tickAnimations(at: 1)

            XCTAssertEqual(node.opacity, 0.8, "Retiring a curve must not strand its final approximate sample")
            XCTAssertEqual(state.interpolatedValue(at: 1), 0.8)
            XCTAssertEqual(colorState.interpolatedColor(at: 1), color)
            XCTAssertFalse(runtime.hasActiveAnimations)
        }
    }

    func testExplicitlyDisabledTransitionsDoNotLeaveAOneFrameRemovalOverlay() async {
        await MainActor.run {
            let previous = currentTransaction
            defer { currentTransaction = previous }
            let child = ViewNode(
                frame: Rect(x: 0, y: 0, width: 40, height: 30), backgroundColor: .white,
                transition: RetainedTransition(kind: .opacity))
            let runtime = RetainedViewRuntime(root: ViewNode(children: [child]))
            _ = runtime.renderFrame()
            currentTransaction = Transaction(animation: nil)

            runtime.root.removeChild(child)

            XCTAssertTrue(runtime.transitionOverlays.isEmpty)
            XCTAssertFalse(runtime.hasActiveAnimations)
            XCTAssertFalse(child.hasAppeared)
        }
    }

    func testReparentingCancelsThePreviousRuntimesColorAnimation() async {
        await MainActor.run {
            let child = ViewNode(frame: Rect(x: 0, y: 0, width: 40, height: 30), backgroundColor: .black)
            let first = RetainedViewRuntime(root: ViewNode(children: [child]))
            let second = RetainedViewRuntime(root: ViewNode())
            first.animateBackgroundColor(of: child, to: .white, duration: 10, at: 0)
            XCTAssertTrue(first.hasActiveAnimations)

            second.root.addChild(child)
            second.animateBackgroundColor(
                of: child, to: Color(red: 1, green: 0, blue: 0, alpha: 1), duration: 1, at: 0, easing: .linear)
            _ = second.tickAnimations(at: 0.5)
            let presentedColor = child.backgroundColor
            _ = first.tickAnimations(at: 10)

            XCTAssertEqual(child.backgroundColor, presentedColor)
            XCTAssertEqual(child.backgroundColor?.red ?? -1, 0.5, accuracy: 0.0001)
            XCTAssertEqual(child.backgroundColor?.green, 0)
            XCTAssertFalse(first.hasActiveAnimations)
        }
    }

    /// The regression this class exists for: a child removed with an explicit
    /// removal transition becomes a `transitionOverlay` whose only state lives
    /// in `animationStates`. Before the fix the runtime reported no activity
    /// the moment the first frame cleared `dirtyFlags`, so the row stayed
    /// painted at full opacity forever and its `onDisappear` never ran.
    func testRemovalTransitionKeepsRuntimeReportingActiveAnimations() async {
        await MainActor.run {
            let root = ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 200), isHitTestVisible: false)
            let child = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 40),
                backgroundColor: .white,
                transition: RetainedTransition(kind: .opacity)
            )
            root.addChild(child)

            let runtime = RetainedViewRuntime(root: root)
            _ = runtime.renderFrame()

            root.removeChild(child)
            XCTAssertEqual(runtime.transitionOverlays.count, 1)

            // The frame that first paints the overlay also clears the dirty
            // flags; from here only hasActiveAnimations can keep the driver on.
            _ = runtime.renderFrame()
            XCTAssertFalse(runtime.isDirty, "the render pass must have consumed the invalidation")
            XCTAssertTrue(
                runtime.hasActiveAnimations,
                "a pending removal transition must keep the animation driver running")
        }
    }

    /// Driving ticks drains the overlay, fires `onDisappear` (which is also
    /// what cancels the node's `.task {}` lifecycle tasks) and returns the
    /// runtime to quiescence.
    func testDrivingTicksDrainsRemovalOverlayAndFiresDisappear() async {
        await MainActor.run {
            let root = ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 200), isHitTestVisible: false)
            var didDisappear = false
            let child = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 40),
                backgroundColor: .white,
                transition: RetainedTransition(kind: .opacity)
            )
            child.onDisappear = { didDisappear = true }
            root.addChild(child)

            let runtime = RetainedViewRuntime(root: root)
            _ = runtime.renderFrame()
            XCTAssertTrue(child.hasAppeared)

            let start = Win32Window.currentTimestampSeconds()
            root.removeChild(child)
            _ = runtime.renderFrame()

            runtime.tickAnimations(at: start + 0.05)
            XCTAssertEqual(runtime.transitionOverlays.count, 1, "mid-flight the overlay is still present")
            XCTAssertTrue(runtime.hasActiveAnimations)

            runtime.tickAnimations(at: start + 5)
            XCTAssertTrue(runtime.transitionOverlays.isEmpty, "a completed transition must drop its overlay")
            XCTAssertTrue(didDisappear, "onDisappear must fire when the removal transition finishes")
            XCTAssertFalse(child.hasAppeared)
            XCTAssertFalse(runtime.hasActiveAnimations)
        }
    }

    /// Per-node `animationStates` — what `.animation()`, insertion transitions,
    /// button presses and matched geometry all write to — has to be visible
    /// through the gate as well, and has to stop being visible when it drains.
    func testNodeAnimationStatesGateTheAnimationDriver() async {
        await MainActor.run {
            let root = ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 200), isHitTestVisible: false)
            let child = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 40), backgroundColor: .white)
            root.addChild(child)

            let runtime = RetainedViewRuntime(root: root)
            _ = runtime.renderFrame()
            XCTAssertFalse(runtime.hasActiveAnimations)

            let start = Win32Window.currentTimestampSeconds()
            child.animationStates[.opacity] = AnimationState(
                startValue: 0, endValue: 1, startTime: start, duration: 0.3)
            XCTAssertTrue(runtime.hasActiveAnimations)

            runtime.tickAnimations(at: start + 5)
            XCTAssertTrue(child.animationStates.isEmpty)
            XCTAssertFalse(
                runtime.hasActiveAnimations,
                "a drained animationStates dictionary must release the driver")
        }
    }

    /// A node dropped mid-animation must not pin the driver on for the rest of
    /// the session — the registry holds nodes weakly and detaching clears the
    /// registration eagerly.
    func testNodeDroppedMidAnimationDoesNotPinTheDriver() async {
        await MainActor.run {
            let root = ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 200), isHitTestVisible: false)
            let child = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 40), backgroundColor: .white)
            root.addChild(child)

            let runtime = RetainedViewRuntime(root: root)
            _ = runtime.renderFrame()

            child.animationStates[.opacity] = AnimationState(
                startValue: 0, endValue: 1, startTime: Win32Window.currentTimestampSeconds(), duration: 10)
            XCTAssertTrue(runtime.hasActiveAnimations)

            // No explicit transition, so the node is dropped outright rather
            // than promoted to an overlay.
            root.removeChild(child)
            XCTAssertTrue(runtime.transitionOverlays.isEmpty)
            XCTAssertFalse(
                runtime.hasActiveAnimations,
                "a detached node's animation must not keep the driver awake")
        }
    }
}
