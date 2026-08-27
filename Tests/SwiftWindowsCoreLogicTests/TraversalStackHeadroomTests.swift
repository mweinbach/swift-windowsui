import Foundation

import SwiftWindowsCore

import SwiftWindowsGraphics

import SwiftWindowsLayout

import XCTest

@testable import SwiftWindowsUI

@testable import WinSwiftUI

/// `ViewNode.maximumTraversalDepth` is a promise about how deep a tree may be.
/// These tests are what makes it one.
///
/// It used not to be. Layout, measure, prepaint and the frame-path command walk
/// were recursions with `-Onone` frames of 12 KB, 5 KB, 15 KB and 24 KB; against
/// the main thread's 1 MB that is a real ceiling of about 43 levels, an eighth
/// of the cap, and the demo's deepest screen already reaches 42. Crossing it is
/// an access violation on Windows: no assertion, no log, no renderer fallback —
/// the whole test process disappears with exit code 1, which is exactly how this
/// regression presented.
///
/// So the guard cannot be another cap. Layout and both paint walks are explicit
/// worklists and cost no stack per level at all; measurement is still a
/// recursion and is kept to about a kilobyte a level. A tree *at* the cap has to
/// render, and a tree past it has to degrade to a diagnostic — both at the
/// production cap, in a debug build, which is the worst case that ships.
@MainActor
final class TraversalStackHeadroomTests: XCTestCase {

    /// A chain exactly `maximumTraversalDepth` deep: every node is inside the
    /// cap, so nothing may be dropped — and every traversal has to walk all of
    /// it. A stack overflow here kills the process rather than failing the
    /// assertion, which is the point: this test is the canary for frame growth
    /// on any of the four walks.
    func testTreeAtTheProductionDepthCapRendersWithoutOverflowingTheStack() async {
        await MainActor.run {
            let cap = ViewNode.maximumTraversalDepth
            XCTAssertEqual(cap, 256, "the pinned cap these traversals are budgeted against")

            let (root, runtime) = makeChain(depth: cap - 1, leafColor: Color(red: 0, green: 1, blue: 0, alpha: 1))

            let scene = runtime.renderScene()
            let frame = runtime.renderFrame()

            XCTAssertGreaterThanOrEqual(
                ViewNode.maxObservedTraversalDepth, cap,
                "the traversals must actually have walked to the cap")
            XCTAssertTrue(
                scene.layers.flatMap(\.quads).contains { $0.startG == 1 && $0.startR == 0 },
                "the leaf at the bottom of a cap-deep tree still reaches the scene")
            XCTAssertFalse(frame.commands.isEmpty, "and the frame path walks the same tree")
            _ = root
        }
    }

    /// The measure recursion runs *nested inside* layout, so a cap-deep tree
    /// that is also being measured from every level is the deepest the stack
    /// ever gets. Re-laying the tree out after invalidating it forces exactly
    /// that: a cold measure pass under a full-depth layout pass.
    func testMeasurementNestedInsideLayoutSurvivesAtTheDepthCap() async {
        await MainActor.run {
            let cap = ViewNode.maximumTraversalDepth
            let (root, runtime) = makeChain(depth: cap - 1, leafColor: Color(red: 1, green: 0, blue: 0, alpha: 1))

            _ = runtime.renderScene()
            // A public property change invalidates layout for the whole subtree,
            // which is what forces the cold measure pass this test is about.
            root.frame = Rect(x: 0, y: 0, width: 220, height: 220)
            let scene = runtime.renderScene()

            XCTAssertTrue(
                scene.layers.flatMap(\.quads).contains { $0.startR == 1 && $0.startG == 0 },
                "a cold measure pass beneath a cap-deep layout pass still produces the leaf")
            _ = root
        }
    }

    /// Width allocation may grow a fixed-width wrapper without changing the
    /// width it proposes to its content. Repeating that unchanged measurement
    /// at every level turns a two-pass row measurement into exponential work.
    func testGrowingNestedFixedWidthRowsDoNotRemeasureUnchangedContent() async {
        await MainActor.run {
            let originalOverrides = NativeTextRenderer.testingOverrides
            defer { NativeTextRenderer.testingOverrides = originalOverrides }
            var measurements = 0
            NativeTextRenderer.testingOverrides.measure = { _, _, _, _ in
                measurements += 1
                return Size(width: 10, height: 10)
            }

            let depth = 14
            var node = ViewNode(text: "Leaf")
            for level in 0..<depth {
                node.layoutPriority = 1
                node = ViewNode(
                    layoutMode: .stack(.horizontal()),
                    preferredSize: Size(width: Double(20 + level * 10), height: 0),
                    children: [node])
            }

            // Unattached measurement exercises the runtime's tree walk
            // without WindowTextSystem hiding repeated leaf measurements.
            let size = node.intrinsicContentSize()
            XCTAssertEqual(size, Size(width: 150, height: 10))
            XCTAssertGreaterThan(measurements, 0)
            XCTAssertLessThanOrEqual(
                measurements, depth * 2 + 2,
                "Fixed-width content with an unchanged proposal must not be measured twice per ancestor")
        }
    }

    func testConstrainedNestedRowsMemoizeProposalsOnlyForTheCurrentMeasurement() async {
        await MainActor.run {
            let originalOverrides = NativeTextRenderer.testingOverrides
            defer { NativeTextRenderer.testingOverrides = originalOverrides }
            var measurements = 0
            NativeTextRenderer.testingOverrides.layout = { _, _, _, _ in nil }
            NativeTextRenderer.testingOverrides.measure = { text, _, _, _ in
                measurements += 1
                return Size(width: 1_000, height: text == "Changed" ? 20 : 10)
            }

            let depth = 14
            let leaf = ViewNode(text: "Leaf")
            leaf.textStyle.lineBreakMode = .wrap
            var node = leaf
            for level in (0..<depth).reversed() {
                node = ViewNode(
                    layoutMode: .stack(.horizontal()),
                    preferredSize: Size(width: Double(80 + level * 10), height: 0),
                    children: [node])
            }
            let runtime = RetainedViewRuntime(root: node)
            XCTAssertEqual(node.intrinsicContentSize(), Size(width: 80, height: 10))
            XCTAssertGreaterThan(measurements, 0)
            XCTAssertLessThanOrEqual(
                measurements + runtime.lastMeasureReuseCount, depth * depth * 4,
                "Repeated ideal and constrained proposals must not walk a nested row exponentially")

            // No paint has cleared the dirty flags. A new measurement walk
            // must nevertheless observe the mutation rather than retain the
            // previous walk's memoized answer.
            leaf.text = "Changed"
            XCTAssertEqual(node.intrinsicContentSize(), Size(width: 80, height: 20))
        }
    }

    /// Past the cap the contract is a truncated picture and one diagnostic, not
    /// an access violation — asserted here at the *production* cap rather than a
    /// lowered one, because a lowered cap proves the branch works, not that the
    /// stack can reach it.
    func testTreeBeyondTheDepthCapTruncatesInsteadOfOverflowing() async {
        await MainActor.run {
            let cap = ViewNode.maximumTraversalDepth
            let (root, runtime) = makeChain(depth: cap * 2, leafColor: Color(red: 0, green: 0, blue: 1, alpha: 1))
            let overflowsBefore = ViewNode.traversalDepthOverflowCount

            _ = runtime.renderScene()
            XCTAssertGreaterThan(
                ViewNode.traversalDepthOverflowCount, overflowsBefore,
                "the depth cap must have reported the truncation")

            let afterScene = ViewNode.traversalDepthOverflowCount
            _ = runtime.renderFrame()
            XCTAssertGreaterThan(
                ViewNode.traversalDepthOverflowCount, afterScene,
                "the frame path is capped the same way the scene path is")
            XCTAssertLessThanOrEqual(ViewNode.maxObservedTraversalDepth, cap)
            _ = root
        }
    }

    /// The shape the regression actually arrived in: SwiftUI-shaped source,
    /// where every modifier adds a wrapper node, so a hierarchy 60 levels deep
    /// in *view* terms is over 120 levels of runtime traversal. This crashed the
    /// test process at 21.
    func testDeeplyNestedSwiftUIHierarchyStillEmitsItsLeaf() async {
        await MainActor.run {
            var view: AnyView = AnyView(
                Text("Leaf")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
            )
            for _ in 0..<60 {
                let child = view
                view = AnyView(
                    VStack(alignment: .center, spacing: 0) {
                        child
                    }
                    .padding(2)
                )
            }

            // Roomy enough that sixty levels of `.padding(2)` still leave the
            // leaf a box to draw in: this test is about depth, not squeeze.
            let snapshot = WinSwiftUIRendererSnapshotter.snapshot(
                of: view,
                size: IntSize(width: 800, height: 600),
                displayScale: 1,
                clearColor: .black
            )

            XCTAssertGreaterThan(
                ViewNode.maxObservedTraversalDepth, 100,
                "60 nested views is well over 100 levels of traversal")
            XCTAssertGreaterThan(
                snapshot.scene.layers.reduce(0) { $0 + $1.glyphs.count }, 0,
                "the leaf Text survives the whole descent")
        }
    }

    private func makeChain(depth: Int, leafColor: Color) -> (ViewNode, RetainedViewRuntime) {
        let root = ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 200), isHitTestVisible: false)
        let runtime = RetainedViewRuntime(root: root)
        var deepest = root
        for level in 0..<depth {
            let next = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 100),
                backgroundColor: level == depth - 1 ? leafColor : nil,
                layoutMode: .stack(.vertical(spacing: 0, alignment: .leading)),
                preferredSize: Size(width: 100, height: 100)
            )
            deepest.addChild(next)
            deepest = next
        }
        return (root, runtime)
    }
}
