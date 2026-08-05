import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// The switch knob travels and the track cross-fades.
///
/// Before this, both properties reached their end value in a single frame:
/// sampled at 0.00 / 0.05 / 0.10 / 0.20 / 0.40s after a toggle, the track read
/// `(0, 0.478, 1, 1)` and the knob local x read 24.00 at *every* sample. The
/// knob's 20px of travel was never drawn. Nothing installed an animation on
/// either — `Controls.toggle` wrote both from the build-time `isOn`, and a
/// control's own state change carries no `currentAnimationTransaction` for
/// `updateNodeProperties` to pick up.
@MainActor
final class SwitchKnobMotionTests: XCTestCase {

    private func findNode(_ node: ViewNode, where predicate: (ViewNode) -> Bool) -> ViewNode? {
        if predicate(node) { return node }
        for child in node.children {
            if let found = findNode(child, where: predicate) { return found }
        }
        return nil
    }

    private struct SwitchHarness {
        let runtime: RetainedViewRuntime
        /// Retained deliberately: the invalidate handler holds the host
        /// weakly, so a harness that dropped it would never rebuild.
        let host: ComponentHost
        let toggle: () -> Void
        let track: () -> ViewNode?
        let knob: () -> ViewNode?
    }

    private func makeSwitch() -> SwitchHarness {
        let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 400, height: 300)))
        let host = ComponentHost(runtime: runtime)
        var isOn = false
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 400, height: 300) },
            invalidateHandler: { [weak host] in host?.reload() }
        )
        host.setComponents {
            [
                VStack {
                    Toggle("Sync", isOn: Binding(get: { isOn }, set: { isOn = $0 }))
                        .toggleStyle(.switch)
                }
                .frame(width: 400, height: 300)
                .makeComponent(context: context)
            ]
        }
        _ = runtime.renderFrame()

        func track() -> ViewNode? {
            findNode(
                runtime.root,
                where: {
                    $0.resolvedFrame.size.width == MacOSControlMetrics.Toggle.regularSize.width
                        && $0.resolvedFrame.size.height == MacOSControlMetrics.Toggle.regularSize.height
                })
        }
        return SwitchHarness(
            runtime: runtime,
            host: host,
            toggle: {
                guard
                    let switchNode = self.findNode(
                        runtime.root, where: { $0.accessibilityTraits.contains(.isButton) })
                else { return XCTFail("no switch in tree") }
                var x = switchNode.resolvedFrame.origin.x
                var y = switchNode.resolvedFrame.origin.y
                var ancestor = switchNode.parent
                while let current = ancestor {
                    x += current.resolvedFrame.origin.x
                    y += current.resolvedFrame.origin.y
                    ancestor = current.parent
                }
                let centre = Point(
                    x: x + switchNode.resolvedFrame.size.width / 2,
                    y: y + switchNode.resolvedFrame.size.height / 2)
                runtime.pointerMoved(to: centre)
                runtime.pointerDown(at: centre)
                runtime.pointerUp(at: centre)
            },
            track: track,
            knob: { track()?.children.first }
        )
    }

    /// The knob is sampled between frames, not at its end state: it has to be
    /// somewhere in the middle of its travel partway through, which is the
    /// entire claim.
    func testTheKnobIsDrawnInFlightAcrossTheTrack() async {
        let harness = makeSwitch()
        guard let knobStart = harness.knob()?.resolvedFrame.origin.x else { return XCTFail("no knob") }

        harness.toggle()
        _ = harness.runtime.renderFrame()
        XCTAssertEqual(
            harness.knob()?.frame.origin.x ?? -1, knobStart, accuracy: 0.001,
            "the frame the state changed on still shows the knob where it was")

        var clock = Win32Window.currentTimestampSeconds()
        var sampled: [Double] = []
        for _ in 0..<24 {
            clock += 1.0 / 60.0
            _ = harness.runtime.tickAnimations(at: clock)
            sampled.append(harness.knob()?.frame.origin.x ?? -1)
        }

        // Track width less the knob and its inset on the far side.
        let knobEnd =
            MacOSControlMetrics.Toggle.regularSize.width - MacOSControlMetrics.Toggle.knobDiameter
            - MacOSControlMetrics.Toggle.knobInset
        let travelled = sampled.filter { $0 > knobStart + 1 && $0 < knobEnd - 1 }
        XCTAssertGreaterThanOrEqual(
            travelled.count, 3,
            "the knob has to be drawn between its two ends, not teleported: \(sampled)")
        XCTAssertEqual(sampled.last ?? -1, knobEnd, accuracy: 0.5, "and it arrives")
        XCTAssertTrue(
            zip(sampled, sampled.dropFirst()).allSatisfy { $1 >= $0 - 0.001 },
            "the travel is monotonic across its span: \(sampled)")
    }

    /// The track cross-fades over the interval the knob's spring occupies —
    /// and it is the *gradient* that has to move, because a gradient wins over
    /// `backgroundColor` at paint time.
    func testTheTrackCrossFadesRatherThanSwitchingColourInOneFrame() async {
        let harness = makeSwitch()
        guard let offColor = harness.track()?.backgroundColor else { return XCTFail("no track") }

        harness.toggle()
        var clock = Win32Window.currentTimestampSeconds()
        var midColors: [Color] = []
        for _ in 0..<12 {
            clock += 1.0 / 60.0
            _ = harness.runtime.tickAnimations(at: clock)
            if let color = harness.track()?.backgroundColor { midColors.append(color) }
        }
        let onColor = midColors.last ?? offColor
        XCTAssertNotEqual(onColor, offColor, "the track ends up somewhere else")

        let intermediate = midColors.filter { $0 != offColor && $0 != onColor }
        XCTAssertGreaterThanOrEqual(
            intermediate.count, 3, "the fill passes through values between its two ends")

        let gradients = midColors.indices.compactMap { _ in harness.track()?.backgroundGradient }
        XCTAssertFalse(gradients.isEmpty, "the track paints as a gradient, so the gradient is what moves")
    }

    /// The switch animates without an ambient `withAnimation`, because macOS
    /// does: this is the point of `implicitReconcileAnimation`.
    func testTheSwitchCarriesItsOwnTransactionAtTheDocumentedSpring() async {
        let harness = makeSwitch()
        XCTAssertNil(currentAnimationTransaction, "no ambient animation is in play")
        XCTAssertEqual(harness.knob()?.implicitReconcileAnimation, Controls.switchKnobAnimation)
        XCTAssertEqual(harness.track()?.implicitReconcileAnimation, Controls.switchTrackAnimation)

        XCTAssertEqual(
            Controls.switchKnobAnimation.easing, Animation.snappy.easing,
            "the knob is Animation.snappy — response 0.5, damping fraction 0.85")
        XCTAssertEqual(Controls.switchKnobAnimation.duration, Animation.snappy.duration, accuracy: 0.0001)
        XCTAssertEqual(Controls.switchTrackCrossfadeDuration, 0.3125, accuracy: 0.0001)
    }
}
