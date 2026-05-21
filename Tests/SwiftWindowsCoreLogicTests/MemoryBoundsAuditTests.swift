import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsPlatform
import XCTest

@testable import SwiftWindowsRendererD3D11
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Audits that runtime caches stay bounded under sustained activity.
///
/// Every cache in `RetainedViewRuntime` has either a hard cap (glyph atlas,
/// path texture cache) or a self-clearing lifecycle (animation states,
/// scroll momentum, presented-delta tweens, transition overlays). These
/// tests drive long-running activity and then verify each collection has
/// either drained to empty or stayed below its documented cap.
///
/// The goal is to catch silent memory leaks (e.g. an animation that never
/// completes, a transition overlay that isn't removed, a momentum entry
/// whose node was deallocated).
@MainActor
final class MemoryBoundsAuditTests: XCTestCase {

    private func makeScrollableRuntime(containerCount: Int = 4) -> (RetainedViewRuntime, [ViewNode]) {
        var containers: [ViewNode] = []
        for column in 0..<containerCount {
            var children: [ViewNode] = []
            for row in 0..<10 {
                children.append(
                    ViewNode(
                        frame: Rect(x: 0, y: 0, width: 80, height: 60),
                        backgroundColor: Color(
                            red: Float(row) / 10, green: Float(column) / Float(containerCount),
                            blue: 0.5, alpha: 1),
                        preferredSize: Size(width: 80, height: 60)
                    )
                )
            }
            let container = ViewNode(
                frame: Rect(x: 10 + Double(column) * 100, y: 10, width: 90, height: 200),
                layoutMode: .stack(.vertical(spacing: 6)),
                scrollAxis: .vertical,
                scrollStep: 30,
                showsScrollIndicator: true,
                isHitTestVisible: false,
                children: children
            )
            containers.append(container)
        }

        let root = ViewNode(
            frame: Rect(x: 0, y: 0, width: 480, height: 220),
            isHitTestVisible: false,
            children: containers
        )
        let runtime = RetainedViewRuntime(root: root)
        _ = runtime.renderFrame()
        return (runtime, containers)
    }

    func testScrollMomentumCachesDrainAfterActivitySettles() async {
        await MainActor.run {
            let (runtime, containers) = makeScrollableRuntime()
            // Fire wheel on every container.
            for (i, container) in containers.enumerated() {
                runtime.mouseWheel(
                    at: Point(x: container.frame.midX, y: container.frame.midY),
                    delta: i.isMultiple(of: 2) ? -4 : 4
                )
            }
            // Plus key navigation to seed presented-delta tweens.
            for _ in 0..<3 {
                runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.downArrow.rawValue))
            }
            XCTAssertTrue(runtime.hasActiveAnimations, "Activity should be in flight")

            // Drive enough frames for everything to settle.
            var t = Win32Window.currentTimestampSeconds()
            var ticks = 0
            while runtime.hasActiveAnimations, ticks < 3000 {
                t += 1.0 / 60.0
                _ = runtime.tickAnimations(at: t)
                ticks += 1
            }

            XCTAssertFalse(runtime.hasActiveAnimations, "All animations should settle")
            // The per-node animation state dictionary must drain after the
            // animations complete.
            for container in containers {
                XCTAssertTrue(
                    container.animationStates.isEmpty,
                    "Container animationStates should drain after settling; found \(container.animationStates.keys)")
            }
            XCTAssertTrue(
                runtime.transitionOverlays.isEmpty,
                "transitionOverlays should be empty when no transitions are pending")
        }
    }

    func testRepeatedScrollOscillationKeepsMomentaBounded() async {
        await MainActor.run {
            let (runtime, containers) = makeScrollableRuntime()
            var t = Win32Window.currentTimestampSeconds()

            // 1000 wheel events alternating direction. The container count is
            // small (4) so even at peak there can never be more momentum
            // entries than scroll containers, regardless of how many wheel
            // events arrive.
            for i in 0..<1000 {
                let container = containers[i % containers.count]
                let delta: Double = i.isMultiple(of: 2) ? -1 : 1
                runtime.mouseWheel(at: Point(x: container.frame.midX, y: container.frame.midY), delta: delta)
                t += 1.0 / 60.0
                _ = runtime.tickAnimations(at: t)
            }

            // Settle.
            var ticks = 0
            while runtime.hasActiveAnimations, ticks < 3000 {
                t += 1.0 / 60.0
                _ = runtime.tickAnimations(at: t)
                ticks += 1
            }

            XCTAssertFalse(runtime.hasActiveAnimations)
            // After settling, every container must have an empty
            // animationStates dictionary (no per-node leftover animation).
            for container in containers {
                XCTAssertTrue(container.animationStates.isEmpty)
                XCTAssertEqual(container.scrollOvershoot, 0)
                XCTAssertEqual(container.scrollPresentedDelta, 0)
            }
        }
    }

    func testTransitionOverlaysClearWhenAnimationsComplete() async {
        await MainActor.run {
            // Build a runtime where children come and go to exercise the
            // transition-overlay path.
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 200, height: 200),
                isHitTestVisible: false
            )
            let runtime = RetainedViewRuntime(root: root)
            _ = runtime.renderFrame()

            // Add and remove children rapidly. With no explicit transitions
            // this should not leak overlays.
            for round in 0..<50 {
                let child = ViewNode(
                    frame: Rect(x: 10, y: 10, width: 40, height: 40),
                    backgroundColor: Color(red: 1, green: Float(round) / 50, blue: 0, alpha: 1)
                )
                root.addChild(child)
                _ = runtime.renderFrame()
                root.removeChild(child)
                _ = runtime.renderFrame()
            }

            XCTAssertTrue(
                runtime.transitionOverlays.isEmpty,
                "Transient additions without explicit transitions should not leak overlays")
        }
    }

    func testD3D11PathCacheStaysAtZeroForFreshRenderer() async {
        // Without GPU we cannot exercise the live cache, but the renderer's
        // initial state must have an empty cache and zero hit/miss counters.
        await MainActor.run {
            let counts = (0..<10).map { _ -> (Int, UInt64, UInt64) in
                let renderer = D3D11BatchRenderer()
                return (renderer.pathCacheEntryCountForTesting, renderer.pathCacheHits, renderer.pathCacheMisses)
            }
            for (entries, hits, misses) in counts {
                XCTAssertEqual(entries, 0)
                XCTAssertEqual(hits, 0)
                XCTAssertEqual(misses, 0)
            }
        }
    }
}

extension Rect {
    fileprivate var midX: Double { origin.x + size.width / 2 }
    fileprivate var midY: Double { origin.y + size.height / 2 }
}
