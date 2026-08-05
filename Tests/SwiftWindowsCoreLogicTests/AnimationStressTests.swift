import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsPlatform
import XCTest

@testable import SwiftWindowsUI

/// Sustained-frame stress tests for the animation/scroll subsystem.
///
/// These drive the runtime through many simulated frames with several
/// concurrent animation sources (scroll momentum, presented-delta tweens,
/// color animations) and assert that:
/// - every animation eventually completes,
/// - per-frame caches stay bounded,
/// - the runtime's `hasActiveAnimations` returns to `false` once everything
///   has settled (no dangling state after a long ride).
@MainActor
final class AnimationStressTests: XCTestCase {

    private func makeStressRuntime() -> (RetainedViewRuntime, [ViewNode]) {
        let itemHeight = 100.0
        let itemCount = 8
        var scrollNodes: [ViewNode] = []
        var scrollableContainers: [ViewNode] = []

        for column in 0..<3 {
            var children: [ViewNode] = []
            for row in 0..<itemCount {
                let node = ViewNode(
                    frame: Rect(x: 0, y: 0, width: 80, height: itemHeight),
                    backgroundColor: Color(
                        red: Float(row) / Float(itemCount),
                        green: Float(column) / 3,
                        blue: 0.5,
                        alpha: 1
                    ),
                    preferredSize: Size(width: 80, height: itemHeight)
                )
                children.append(node)
            }
            let container = ViewNode(
                frame: Rect(x: 10 + Double(column) * 100, y: 10, width: 90, height: 200),
                layoutMode: .stack(.vertical(spacing: 8)),
                scrollAxis: .vertical,
                scrollStep: 30,
                showsScrollIndicator: true,
                isHitTestVisible: false,
                children: children
            )
            scrollableContainers.append(container)
            scrollNodes.append(contentsOf: children)
        }

        let root = ViewNode(
            frame: Rect(x: 0, y: 0, width: 320, height: 220),
            isHitTestVisible: false,
            children: scrollableContainers
        )
        let runtime = RetainedViewRuntime(root: root)
        _ = runtime.renderFrame()
        return (runtime, scrollableContainers)
    }

    func testSustainedTickingSettlesAllAnimations() async {
        await MainActor.run {
            let (runtime, containers) = makeStressRuntime()
            // Seed wheel momentum on every scroll container in alternating
            // directions to exercise both positive and negative momentum and
            // ensure both edges' rubber-band paths fire. The source has to be
            // a gesture: a click-wheel detent seeds no momentum at all, so a
            // notch here would leave the stress scene with nothing to settle.
            for (index, container) in containers.enumerated() {
                let delta: Double = index.isMultiple(of: 2) ? -4 : 4
                runtime.mouseWheel(at: container.frame.midpoint, delta: delta, source: .precise)
            }

            XCTAssertTrue(runtime.hasActiveAnimations, "Stress scene should start with active momentum")

            // Drive 1500 frames (~25s at 60fps); this far exceeds the longest
            // decay path even with rubber-band springs added.
            var t = Win32Window.currentTimestampSeconds()
            var ticks = 0
            while runtime.hasActiveAnimations, ticks < 1500 {
                t += 1.0 / 60.0
                _ = runtime.tickAnimations(at: t)
                ticks += 1
            }

            XCTAssertFalse(runtime.hasActiveAnimations, "All animations should settle within 25s of simulated ticks")
            for container in containers {
                XCTAssertEqual(container.scrollOvershoot, 0, "Rubber-band overshoot must zero out")
                XCTAssertEqual(container.scrollPresentedDelta, 0, "Presented-delta tween must zero out")
            }
        }
    }

    func testDynamicMutationPreservesScenePrimitiveTopology() async {
        await MainActor.run {
            let (runtime, containers) = makeStressRuntime()
            let baselineScene = runtime.renderScene()
            let baselineLayerCount = baselineScene.layers.count
            let baselineQuadCount = baselineScene.layers.reduce(0) { $0 + $1.quads.count }

            // Apply many rounds of mutations (scroll, key navigation,
            // pointer movement). Each round renders a fresh scene; we then
            // verify the broad topology (layer count, quad count) stays
            // anchored — proving the scene-graph doesn't accumulate ghost
            // primitives over a long session.
            var t = Win32Window.currentTimestampSeconds()
            for round in 0..<200 {
                let container = containers[round % containers.count]
                runtime.mouseWheel(at: container.frame.midpoint, delta: round.isMultiple(of: 2) ? -1 : 1)
                runtime.pointerMoved(to: Point(x: 50 + Double(round % 250), y: 50 + Double(round % 150)))
                t += 1.0 / 60.0
                _ = runtime.tickAnimations(at: t)
                _ = runtime.renderScene()
            }

            // Let momentum and hover animations settle. Move pointer
            // off-window so scroll-indicator hover state clears completely.
            runtime.pointerExitedWindow()
            var ticks = 0
            while runtime.hasActiveAnimations, ticks < 2000 {
                t += 1.0 / 60.0
                _ = runtime.tickAnimations(at: t)
                ticks += 1
            }

            // Scroll containers may end up at different offsets, but the
            // underlying primitive topology must stay bounded — within
            // baseline +/- the maximum possible indicator quad count (one per
            // scrollable container). This catches unbounded primitive
            // accumulation without being overly strict about transient
            // indicator visibility.
            let finalScene = runtime.renderScene()
            XCTAssertEqual(finalScene.layers.count, baselineLayerCount, "Layer count must not drift across mutations")
            let finalQuadCount = finalScene.layers.reduce(0) { $0 + $1.quads.count }
            let maxIndicatorDelta = containers.count
            XCTAssertLessThanOrEqual(
                abs(finalQuadCount - baselineQuadCount), maxIndicatorDelta,
                "Quad count drift across mutations must stay within +/- one indicator per container — anything larger signals a primitive leak"
            )
        }
    }

    func testRepeatedWheelAndTickPreservesRuntimeIntegrity() async {
        await MainActor.run {
            let (runtime, containers) = makeStressRuntime()
            var t = Win32Window.currentTimestampSeconds()

            // 500 wheel events interleaved with ticks. Mirrors a user
            // continuously scrolling. The runtime must not accumulate unbounded
            // state or leave animations stuck.
            for iteration in 0..<500 {
                let container = containers[iteration % containers.count]
                let delta: Double = (iteration % 5 == 0) ? -2 : 1
                runtime.mouseWheel(at: container.frame.midpoint, delta: delta)

                t += 1.0 / 60.0
                _ = runtime.tickAnimations(at: t)
            }

            // Let everything settle.
            var ticks = 0
            while runtime.hasActiveAnimations, ticks < 1500 {
                t += 1.0 / 60.0
                _ = runtime.tickAnimations(at: t)
                ticks += 1
            }

            XCTAssertFalse(runtime.hasActiveAnimations)
            for container in containers {
                // Offsets must remain within bounds (no overshoot leaked).
                XCTAssertGreaterThanOrEqual(container.scrollOffset, 0)
                XCTAssertLessThanOrEqual(container.scrollOffset, container.maxScrollOffsetExternal)
                XCTAssertEqual(container.scrollOvershoot, 0)
                XCTAssertEqual(container.scrollPresentedDelta, 0)
            }
        }
    }
}

@MainActor
extension ViewNode {
    /// Test-only accessor for the fileprivate maxScrollOffset.
    fileprivate var maxScrollOffsetExternal: Double {
        switch scrollAxis {
        case .horizontal:
            return max(0, resolvedContentSize.width - resolvedFrame.size.width)
        case .vertical:
            return max(0, resolvedContentSize.height - resolvedFrame.size.height)
        case nil:
            return 0
        }
    }
}

extension Rect {
    fileprivate var midpoint: Point {
        Point(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
    }
}
