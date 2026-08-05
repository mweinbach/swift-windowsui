import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Reconciliation matches on identity, not position.
///
/// The regression these pin: `reconcileChildren` walked old and new children
/// by index and only asked `nodesMatch` at the same index, so removing
/// anything but the tail of a `ForEach` mismatched at the edit point and at
/// every index after it. Removing the head of a four-row list produced **four**
/// removal overlays carrying the whole previous list, fading out on top of a
/// new list whose every surviving row had been re-created and faded in from
/// zero. The identity needed to do it right was already on the nodes —
/// `ForEach` tags every row — and was being used only as an equality test.
@MainActor
final class KeyedReconciliationTests: XCTestCase {

    private func texts(in node: ViewNode) -> [String] {
        var out: [String] = []
        if let text = node.text, !text.isEmpty { out.append(text) }
        for child in node.children { out.append(contentsOf: texts(in: child)) }
        return out
    }

    /// Drives a `ForEach` over `rows`, returning the runtime, the host and a
    /// setter that mutates the list and reloads inside `withAnimation`.
    private func makeListHost(
        rows initialRows: [Int]
    ) -> (RetainedViewRuntime, ComponentHost, ([Int]) -> Void) {
        let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 400, height: 300)))
        let host = ComponentHost(runtime: runtime)
        var rows = initialRows
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 400, height: 300) },
            invalidateHandler: { [weak host] in host?.reload() }
        )
        host.setComponents {
            [
                VStack {
                    ForEach(rows, id: \.self) { row in
                        Text("Row \(row)")
                            .transition(.opacity)
                    }
                }
                .frame(width: 400, height: 300)
                .makeComponent(context: context)
            ]
        }
        _ = runtime.renderFrame()
        return (
            runtime, host,
            { next in
                rows = next
                withAnimation { host.reload() }
            }
        )
    }

    /// One row leaves, one overlay — at any index. Measured before the fix:
    /// head removal produced 4 overlays carrying "Row 1", "Row 2", "Row 3",
    /// "Row 4", all at opacity 1.0.
    func testRemovingAnyRowProducesExactlyOneRemovalOverlay() async {
        for (label, remaining, expectedGhost) in [
            ("head", [2, 3, 4], "Row 1"),
            ("middle", [1, 2, 4], "Row 3"),
            ("tail", [1, 2, 3], "Row 4"),
        ] {
            let (runtime, _, setRows) = makeListHost(rows: [1, 2, 3, 4])
            var clock = Win32Window.currentTimestampSeconds()
            for _ in 0..<40 {
                clock += 1.0 / 60.0
                _ = runtime.tickAnimations(at: clock)
            }

            setRows(remaining)

            XCTAssertEqual(
                texts(in: runtime.root), remaining.map { "Row \($0)" },
                "\(label): the live tree is the new list")
            XCTAssertEqual(
                runtime.transitionOverlays.count, 1,
                "\(label): exactly the row that left fades out")
            XCTAssertEqual(
                runtime.transitionOverlays.first.map { texts(in: $0) } ?? [], [expectedGhost],
                "\(label): and it is the right row")
        }
    }

    /// The surviving rows are the *same nodes*, moved — not rebuilt. Node
    /// identity is what carries scroll offsets, focus, `hasAppeared` and every
    /// in-flight animation across an edit.
    func testSurvivingRowsKeepTheirIdentityAcrossAHeadRemoval() async {
        let (runtime, _, setRows) = makeListHost(rows: [1, 2, 3, 4])
        var clock = Win32Window.currentTimestampSeconds()
        for _ in 0..<40 {
            clock += 1.0 / 60.0
            _ = runtime.tickAnimations(at: clock)
        }

        func rowNodes() -> [ViewNode] {
            func collect(_ node: ViewNode) -> [ViewNode] {
                if node.nodeTag != nil, !texts(in: node).isEmpty { return [node] }
                return node.children.flatMap(collect)
            }
            return collect(runtime.root)
        }

        let before = rowNodes()
        XCTAssertEqual(before.count, 4)
        let survivorsBefore = Array(before.dropFirst())

        setRows([2, 3, 4])

        let after = rowNodes()
        XCTAssertEqual(after.count, 3)
        for (index, node) in after.enumerated() {
            XCTAssertTrue(
                node === survivorsBefore[index],
                "row \(index) after the deletion is the node that was already there, moved")
            XCTAssertEqual(node.opacity, 1.0, accuracy: 0.001, "a survivor does not fade in from zero")
        }
    }

    /// Reordering is a pure move: no node is destroyed, nothing fades.
    func testReorderingRowsMovesNodesWithoutRemovalsOrInsertions() async {
        let (runtime, _, setRows) = makeListHost(rows: [1, 2, 3, 4])
        var clock = Win32Window.currentTimestampSeconds()
        for _ in 0..<40 {
            clock += 1.0 / 60.0
            _ = runtime.tickAnimations(at: clock)
        }

        setRows([4, 3, 2, 1])

        XCTAssertEqual(texts(in: runtime.root), ["Row 4", "Row 3", "Row 2", "Row 1"])
        XCTAssertTrue(
            runtime.transitionOverlays.isEmpty,
            "a reorder destroys nothing, so nothing fades out")
    }

    /// Inserting at the head animates exactly the inserted row.
    func testInsertingAtTheHeadAnimatesOnlyTheNewRow() async {
        let (runtime, _, setRows) = makeListHost(rows: [2, 3, 4])
        var clock = Win32Window.currentTimestampSeconds()
        for _ in 0..<40 {
            clock += 1.0 / 60.0
            _ = runtime.tickAnimations(at: clock)
        }

        setRows([1, 2, 3, 4])

        XCTAssertTrue(runtime.transitionOverlays.isEmpty, "nothing left, so nothing fades out")
        func fadingRows(_ node: ViewNode) -> [String] {
            var out: [String] = []
            if node.animationStates[.opacity] != nil, !texts(in: node).isEmpty {
                out.append(contentsOf: texts(in: node))
            }
            for child in node.children { out.append(contentsOf: fadingRows(child)) }
            return out
        }
        XCTAssertEqual(fadingRows(runtime.root), ["Row 1"], "only the inserted row fades in")
    }

    /// The untagged path is the old index walk, unchanged: a structural
    /// mismatch at an index still replaces in place.
    func testUntaggedChildrenStillReconcilePositionally() async {
        let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 100)))
        let parent = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 100))
        runtime.root.addChild(parent)
        let first = ViewNode(frame: Rect(x: 0, y: 0, width: 10, height: 10), backgroundColor: .white)
        let second = ViewNode(frame: Rect(x: 0, y: 10, width: 10, height: 10), backgroundColor: .black)
        parent.addChild(first)
        parent.addChild(second)

        let replacementFirst = ViewNode(frame: Rect(x: 0, y: 0, width: 20, height: 20), backgroundColor: .red)
        let replacementSecond = ViewNode(frame: Rect(x: 0, y: 20, width: 20, height: 20), backgroundColor: .blue)
        ComponentHost.reconcileChildren(
            of: parent, oldChildren: parent.children, newNodes: [replacementFirst, replacementSecond])

        XCTAssertTrue(parent.children[0] === first, "same layout mode: matched and updated in place")
        XCTAssertTrue(parent.children[1] === second)
        XCTAssertEqual(parent.children[0].backgroundColor, .red)
        XCTAssertEqual(parent.children[1].backgroundColor, .blue)
    }
}
