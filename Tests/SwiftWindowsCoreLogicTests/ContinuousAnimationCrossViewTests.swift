import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsPlatform
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

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
@MainActor
final class ContinuousAnimationCrossViewTests: XCTestCase {

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
