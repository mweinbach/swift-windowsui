import Foundation

import SwiftWindowsCore

import XCTest

@testable import SwiftWindowsUI

@testable import WinSwiftUI

/// A `Spacer` is a greedy view, and greed travels.
///
/// In SwiftUI the row `HStack { Text; Spacer; Button }` is offered a width
/// and takes all of it — the Spacer swallows whatever the other children
/// leave. The row is therefore as wide as its proposal, not as wide as its
/// content, and a `.frame(height:)` around it changes nothing about that
/// because a height-only frame forwards the width proposal untouched.
///
/// The tests below pin both halves: the greed itself, and the places it has
/// to stop — an intrinsic (infinite) proposal, and any ancestor that pins
/// its own extent along the same axis.
@MainActor
final class SpacerFillSemanticsTests: XCTestCase {

    private func layoutNode<V: View>(
        _ view: V,
        size: Size = Size(width: 1000, height: 400)
    ) -> ViewNode {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let context = ViewBuildContext(canvasSizeProvider: { size }, invalidateHandler: {})
        let node = view.makeComponent(context: context).makeNode(runtime: runtime)
        node.frame = Rect(origin: .zero, size: size)
        runtime.root.addChild(node)
        runtime.setRootSize(IntSize(width: Int32(size.width), height: Int32(size.height)))
        _ = runtime.renderFrame()
        return node
    }

    private func buildNode<V: View>(_ view: V, size: Size = Size(width: 1000, height: 400)) -> ViewNode {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let context = ViewBuildContext(canvasSizeProvider: { size }, invalidateHandler: {})
        return view.makeComponent(context: context).makeNode(runtime: runtime)
    }

    private func descendants(of node: ViewNode) -> [ViewNode] {
        var found: [ViewNode] = [node]
        var index = 0
        while index < found.count {
            found.append(contentsOf: found[index].children)
            index += 1
        }
        return found
    }

    /// The widest painted surface in the subtree — the toolbar's own
    /// background, in the dashboard shape this reproduces.
    private func widestPaintedWidth(in node: ViewNode) -> Double {
        descendants(of: node)
            .filter { $0.backgroundColor != nil }
            .map(\.resolvedFrame.width)
            .max() ?? 0
    }

    // MARK: - The greed

    func testRowWithASpacerTakesTheWidthItIsProposed() async {
        let width: Double = 1000
        let node = layoutNode(
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text("Title")
                    Spacer(minLength: 0)
                    Text("Trailing")
                }
                .frame(height: 44)
            },
            size: Size(width: width, height: 300)
        )

        let rows = descendants(of: node).filter { $0.layoutMode.stackLayout?.axis == .horizontal }
        guard let row = rows.first else {
            return XCTFail("the HStack should be in the tree")
        }
        XCTAssertEqual(
            row.resolvedFrame.width,
            width,
            accuracy: 0.51,
            "A row holding a Spacer is as wide as its proposal, not as wide as its text"
        )
        XCTAssertEqual(row.resolvedFrame.height, 44, accuracy: 0.51, "…and the height-only frame still pins the height")
    }

    /// The dashboard's own shape: the row is buried under padding and
    /// background wrappers, and the only thing that reaches the window edge
    /// is the surface those wrappers paint.
    func testAPaddedBackgroundedRowWithASpacerSpansItsContainer() async {
        let width: Double = 1000
        let node = layoutNode(
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text("WinSwiftUI")
                    Spacer(minLength: 0)
                    Text("Mode")
                }
                .padding(14)
                .background(Color.red)
                .frame(height: 60)
            },
            size: Size(width: width, height: 300)
        )

        XCTAssertEqual(
            widestPaintedWidth(in: node),
            width,
            accuracy: 0.51,
            "The toolbar surface reaches the edge of the column it sits in"
        )
    }

    // MARK: - Where it stops

    func testSpacerDoesNotInflateAnIntrinsicMeasurement() async {
        let node = buildNode(
            HStack(spacing: 8) {
                Text("A")
                Spacer(minLength: 0)
                Text("B")
            }
        )
        let intrinsic = node.intrinsicContentSize()
        XCTAssertGreaterThan(intrinsic.width, 0)
        XCTAssertLessThan(
            intrinsic.width,
            400,
            "Greed is answered against a proposal; an unconstrained measure still reports content size"
        )
        XCTAssertTrue(intrinsic.width.isFinite)
    }

    func testAPinnedWidthEndsTheFillChain() async {
        let node = layoutNode(
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text("A")
                    Spacer(minLength: 0)
                }
                .frame(width: 200)
            },
            size: Size(width: 1000, height: 300)
        )
        guard
            let pinned = descendants(of: node).first(where: {
                ($0.preferredSize?.width ?? 0) == 200
            })
        else {
            return XCTFail("the pinned frame should be in the tree")
        }
        XCTAssertEqual(
            pinned.resolvedFrame.width,
            200,
            accuracy: 0.51,
            "`.frame(width:)` is the author's answer; a greedy child inside it does not override it"
        )
    }

    func testAPinnedHeightEndsTheFillChainAlongTheOtherAxis() async {
        let node = layoutNode(
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    Text("A")
                    Spacer(minLength: 0)
                }
                .frame(height: 80)
                Text("Below")
            },
            size: Size(width: 400, height: 600)
        )
        guard
            let pinned = descendants(of: node).first(where: {
                ($0.preferredSize?.height ?? 0) == 80
            })
        else {
            return XCTFail("the pinned frame should be in the tree")
        }
        XCTAssertEqual(
            pinned.resolvedFrame.height,
            80,
            accuracy: 0.51,
            "A vertical Spacer does not stretch the fixed-height box it lives in"
        )
    }

    /// Cross-axis greed is already carried by measurement (a greedy child
    /// reports the proposal, and the stack folds that in as its cross
    /// extent), so it must not *also* be inherited — a `.frame(width:)`
    /// wrapper is a single-child vertical stack, and inheriting across the
    /// axis would let a `Divider` inside one blow the pin away.
    func testCrossAxisGreedIsNotInherited() async {
        let node = buildNode(
            VStack(spacing: 0) {
                Divider()
            }
        )
        _ = node.intrinsicContentSize()
        XCTAssertFalse(
            node.inheritedStackFillAxes.horizontal,
            "A vertical stack derives greed along its own axis only"
        )
        XCTAssertFalse(node.inheritedStackFillAxes.vertical)
    }
}
