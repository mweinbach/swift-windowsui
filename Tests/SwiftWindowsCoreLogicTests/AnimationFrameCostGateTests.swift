import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI

/// Structural gates on what an *animating* frame costs (see
/// `docs/PerformanceBudgets.md`).
///
/// The budgets in `PerformanceBudgetGateTests` bound what a scene *contains*;
/// these bound what a frame *redoes* while an animation is running, which is
/// the only regime where sustained frame rate is actually at risk. An idle
/// window serves its whole scene from one cache hit and costs nothing to
/// measure. A window with an animation running has, by construction, something
/// that changed every frame, so the question is not "did anything change" but
/// "how much of the tree did one changing subtree drag along with it".
///
/// The measured quantity is `ScenePaintMetrics.nodesVisited`, not the replay
/// count. Replay counts *ranges*, and a range can be one row or the entire
/// root: a frame that replays the whole tree in a single range and a frame
/// that replays nothing both report one replay, and they differ by the whole
/// tree. Visits count the traversal itself, which is the work.
///
/// Every assertion is a count — nodes entered — never a duration. A live 12 s
/// release run of the demo (2026-08, RTX 5090, unpaced) measured animating
/// frames at p50 0.22 ms / p95 0.65 ms / p99 0.91 ms with zero of 613 over a
/// 16.67 ms refresh budget; these gates exist so that stays true by
/// construction rather than by luck, on machines where nobody is measuring.
@MainActor
final class AnimationFrameCostGateTests: XCTestCase {

    /// Sibling subtrees in the probe, and rows inside each one. 40 x 6 puts
    /// 281 nodes in the tree, so "walked the animating branch" and "walked
    /// everything" differ by an unmistakable margin rather than by noise.
    private static let siblingCount = 40
    private static let rowsPerSibling = 6
    private static var totalNodeCount: Int { siblingCount * (rowsPerSibling + 1) + 1 }

    /// A row of independent, identically-shaped sibling subtrees under one
    /// parent. Each sibling is a scroll container, so any one of them can be
    /// given an animation that belongs to it alone.
    private func makeSiblingRuntime() -> (RetainedViewRuntime, [ViewNode]) {
        let (runtime, siblings, _) = makeSiblingRuntimeAndFirstScene()
        return (runtime, siblings)
    }

    private func makeSiblingRuntimeAndFirstScene() -> (RetainedViewRuntime, [ViewNode], GPUIScene) {
        var siblings: [ViewNode] = []
        for index in 0..<Self.siblingCount {
            var rows: [ViewNode] = []
            for row in 0..<Self.rowsPerSibling {
                rows.append(
                    ViewNode(
                        frame: Rect(x: 0, y: 0, width: 60, height: 40),
                        backgroundColor: Color(
                            red: Float(row) / 6, green: Float(index % 8) / 8, blue: 0.4, alpha: 1),
                        preferredSize: Size(width: 60, height: 40)
                    )
                )
            }
            siblings.append(
                ViewNode(
                    frame: Rect(x: 4 + Double(index) * 64, y: 8, width: 60, height: 120),
                    layoutMode: .stack(.vertical(spacing: 4)),
                    scrollAxis: .vertical,
                    scrollStep: 20,
                    showsScrollIndicator: true,
                    isHitTestVisible: false,
                    children: rows
                )
            )
        }

        let root = ViewNode(
            frame: Rect(x: 0, y: 0, width: 4 + Double(Self.siblingCount) * 64, height: 140),
            isHitTestVisible: false,
            children: siblings
        )
        let runtime = RetainedViewRuntime(root: root)
        // Populate the paint cache. Replay has no source until a scene has
        // been built once, so a test that measured the first frame would
        // measure the one frame where a full traversal is correct.
        let firstScene = runtime.renderScene()
        return (runtime, siblings, firstScene)
    }

    private func wheelPoint(for node: ViewNode) -> Point {
        Point(x: node.frame.minX + node.frame.width / 2, y: node.frame.minY + node.frame.height / 2)
    }

    /// The first paint has to walk everything — otherwise the bounds below
    /// measure a tree that was never there.
    func testTheProbeTreeIsAsLargeAsTheBoundsAssume() async {
        await MainActor.run {
            let root = ViewNode(frame: Rect(x: 0, y: 0, width: 10, height: 10))
            let runtime = RetainedViewRuntime(root: root)
            let singleNodeScene = runtime.renderScene()
            XCTAssertEqual(
                singleNodeScene.paintMetrics.nodesVisited, 1,
                "a one-node tree must report exactly one visit, or the counter is not counting nodes")

            // A fresh runtime's first scene has no replay source, so it is the
            // one paint that legitimately walks everything — and the ceiling
            // the bounds below are measured against.
            let (_, _, firstScene) = makeSiblingRuntimeAndFirstScene()
            XCTAssertEqual(
                firstScene.paintMetrics.nodesVisited, Self.totalNodeCount,
                "the first paint of the probe tree must walk all of it")
        }
    }

    /// One animating subtree must not drag the rest of the tree into the
    /// traversal.
    ///
    /// This is the invariant behind sustained frame rate during animation. If
    /// it breaks, nothing else observable breaks with it — the window still
    /// draws the right pixels, `hasActiveAnimations` still clears, every scene
    /// budget still passes — and the frame cost quietly becomes proportional
    /// to the whole tree instead of to the part that moved.
    func testAnimatingOneSubtreeDoesNotWalkTheWholeTree() async {
        await MainActor.run {
            let (runtime, siblings) = makeSiblingRuntime()
            guard let animated = siblings.first else {
                return XCTFail("probe must build its siblings")
            }

            runtime.mouseWheel(at: wheelPoint(for: animated), delta: -4, source: .precise)
            XCTAssertTrue(
                runtime.hasActiveAnimations,
                "a precise-source wheel on one container must start momentum on that container")

            var rebuildFrames = 0
            var worstVisitCount = 0
            var timestamp = 1.0
            for _ in 0..<30 {
                timestamp += 1.0 / 60.0
                _ = runtime.tickAnimations(at: timestamp)
                let rebuildsBefore = runtime.sceneRebuildCount
                let scene = runtime.renderScene()
                guard runtime.sceneRebuildCount != rebuildsBefore else {
                    continue
                }
                rebuildFrames += 1
                worstVisitCount = max(worstVisitCount, scene.paintMetrics.nodesVisited)
            }

            XCTAssertGreaterThan(
                rebuildFrames, 0,
                "an animation must actually rebuild scenes; a run of pure cache hits proves nothing")
            // The animating container, its own rows and the root are walked;
            // the other 39 containers are replayed from their cached ranges,
            // one visit each, and their 234 rows are never entered. That is
            // 1 + 7 + 39 = 47 visits against a 281-node tree. The bound
            // carries ~1.7x headroom and still fails an order of magnitude
            // before a full walk.
            XCTAssertLessThan(
                worstVisitCount, 80,
                """
                an animation on one of \(Self.siblingCount) sibling subtrees walked \
                \(worstVisitCount) of \(Self.totalNodeCount) nodes; unchanged siblings must \
                replay instead of being traversed
                """
            )
        }
    }

    /// Replay must survive a long ride, not just the first few frames.
    ///
    /// A cache that is invalidated once and never repopulated looks identical
    /// to a working one for exactly as long as the first scene stays valid.
    /// Momentum runs for hundreds of frames; the last one has to be as cheap
    /// as the first.
    func testFrameCostHoldsForTheWholeLifeOfAnAnimation() async {
        await MainActor.run {
            let (runtime, siblings) = makeSiblingRuntime()
            guard let animated = siblings.first else {
                return XCTFail("probe must build its siblings")
            }

            runtime.mouseWheel(at: wheelPoint(for: animated), delta: -8, source: .precise)

            var timestamp = 1.0
            var rebuildFrames = 0
            var overBudgetFrames = 0
            var ticks = 0
            while runtime.hasActiveAnimations, ticks < 600 {
                ticks += 1
                timestamp += 1.0 / 60.0
                _ = runtime.tickAnimations(at: timestamp)
                let rebuildsBefore = runtime.sceneRebuildCount
                let scene = runtime.renderScene()
                guard runtime.sceneRebuildCount != rebuildsBefore else {
                    continue
                }
                rebuildFrames += 1
                if scene.paintMetrics.nodesVisited >= 80 {
                    overBudgetFrames += 1
                }
            }

            XCTAssertGreaterThan(rebuildFrames, 10, "momentum must produce a run of rebuilt frames")
            XCTAssertEqual(
                overBudgetFrames, 0,
                """
                \(overBudgetFrames) of \(rebuildFrames) rebuilt frames walked the whole tree \
                instead of replaying the subtrees that did not change
                """
            )
        }
    }

    /// A settled animation must stop costing a traversal at all.
    ///
    /// The frame after everything settles is served from the whole-scene
    /// cache, and the host stops asking for frames. If either half regresses,
    /// an idle window burns a core.
    func testASettledWindowStopsRebuildingScenes() async {
        await MainActor.run {
            let (runtime, siblings) = makeSiblingRuntime()
            guard let animated = siblings.first else {
                return XCTFail("probe must build its siblings")
            }

            runtime.mouseWheel(at: wheelPoint(for: animated), delta: -4, source: .precise)
            var timestamp = 1.0
            var ticks = 0
            while runtime.hasActiveAnimations, ticks < 1500 {
                ticks += 1
                timestamp += 1.0 / 60.0
                _ = runtime.tickAnimations(at: timestamp)
                _ = runtime.renderScene()
            }
            XCTAssertFalse(runtime.hasActiveAnimations, "momentum must settle")

            let rebuildsAtRest = runtime.sceneRebuildCount
            for _ in 0..<20 {
                timestamp += 1.0 / 60.0
                _ = runtime.tickAnimations(at: timestamp)
                _ = runtime.renderScene()
            }
            XCTAssertEqual(
                runtime.sceneRebuildCount, rebuildsAtRest,
                "a settled window must serve every frame from the scene cache")
        }
    }
}
