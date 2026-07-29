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
