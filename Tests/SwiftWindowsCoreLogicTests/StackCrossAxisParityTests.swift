import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// macOS parity for stack cross-axis sizing: a flexible-width child (a
/// `Color` / background-painted panel with no intrinsic or explicit width)
/// takes the stack's cross-axis width in leading, trailing, and center
/// aligned stacks instead of collapsing to zero, while non-flexible
/// children keep their intrinsic geometry and alignment.

private func unwrap<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) -> T {
    guard let value else {
        XCTFail("Unexpected nil value", file: file, line: line)
        fatalError("Unexpected nil value")
    }
    return value
}

@MainActor
private func makeStackRuntimeNode<V: View>(
    _ view: V,
    canvas: Size = Size(width: 480, height: 360)
) -> ViewNode {
    let runtime = RetainedViewRuntime(root: ViewNode())
    let context = ViewBuildContext(canvasSizeProvider: { canvas }, invalidateHandler: {})
    let node = view.makeComponent(context: context).makeNode(runtime: runtime)
    runtime.root.addChild(node)
    runtime.setRootSize(IntSize(width: Int32(canvas.width), height: Int32(canvas.height)))
    _ = runtime.renderFrame()
    return node
}

@MainActor
private func layoutStackInRuntime(_ node: ViewNode, size: Size = Size(width: 480, height: 360)) {
    let runtime = RetainedViewRuntime(root: ViewNode())
    runtime.root.addChild(node)
    runtime.setRootSize(IntSize(width: Int32(size.width), height: Int32(size.height)))
    _ = runtime.renderFrame()
}

@MainActor
private func firstStackNode(in node: ViewNode) -> ViewNode? {
    if case .stack = node.layoutMode {
        return node
    }
    for child in node.children {
        if let match = firstStackNode(in: child) {
            return match
        }
    }
    return nil
}

@MainActor
private func firstTextNodeInStack(in node: ViewNode) -> ViewNode? {
    if node.text != nil {
        return node
    }
    for child in node.children {
        if let match = firstTextNodeInStack(in: child) {
            return match
        }
    }
    return nil
}

/// Finds the test's subject stack: `.frame(...)` wraps views in an outer
/// alignment stack panel, so descend past that wrapper to the inner stack.
@MainActor
private func innerStackNode(under node: ViewNode) -> ViewNode? {
    guard let outer = firstStackNode(in: node) else {
        return nil
    }
    for child in outer.children {
        if let match = firstStackNode(in: child) {
            return match
        }
    }
    return nil
}

final class StackCrossAxisParityTests: XCTestCase {

    // MARK: - Flexible cross-axis expansion (macOS parity)

    func testFlexibleBackgroundChildExpandsToLeadingStackWidth() async {
        await MainActor.run {
            for width in [120.0, 200.0, 320.0] {
                let node = makeStackRuntimeNode(
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: 2).background(Color.red)
                        Text("Label")
                    }
                    .frame(width: width, height: 60)
                )
                let stack = unwrap(innerStackNode(under: node))
                let bar = unwrap(stack.children.first)
                XCTAssertEqual(bar.resolvedFrame.width, width, accuracy: 0.51, "bar should fill \(width)pt stack")
                XCTAssertEqual(bar.resolvedFrame.minX, 0, accuracy: 0.51)
            }
        }
    }

    func testFlexibleBackgroundChildExpandsAcrossAlignments() async {
        await MainActor.run {
            let width = 200.0
            for alignment in [HorizontalAlignment.leading, .center, .trailing] {
                let node = makeStackRuntimeNode(
                    VStack(alignment: alignment, spacing: 0) {
                        Color.clear.frame(height: 2).background(Color.red)
                        Text("Label")
                    }
                    .frame(width: width, height: 60)
                )
                let stack = unwrap(innerStackNode(under: node))
                let bar = unwrap(stack.children.first)
                let label = unwrap(firstTextNodeInStack(in: stack))
                XCTAssertEqual(
                    bar.resolvedFrame.width, width, accuracy: 0.51,
                    "flexible bar should fill the stack at \(alignment)")
                XCTAssertEqual(bar.resolvedFrame.minX, 0, accuracy: 0.51)
                XCTAssertLessThan(
                    label.resolvedFrame.width, width - 1,
                    "text keeps its intrinsic width at \(alignment)")
                switch alignment {
                case .leading:
                    XCTAssertEqual(label.resolvedFrame.minX, 0, accuracy: 0.51)
                case .center:
                    XCTAssertEqual(label.resolvedFrame.midX, width * 0.5, accuracy: 0.51)
                default:
                    XCTAssertEqual(label.resolvedFrame.maxX, width, accuracy: 0.51)
                }
            }
        }
    }

    func testFlexibleHeightChildExpandsInTopAlignedHStack() async {
        await MainActor.run {
            let height = 50.0
            let node = makeStackRuntimeNode(
                HStack(alignment: .top, spacing: 0) {
                    Color.clear.frame(width: 2).background(Color.red)
                    Text("Label")
                }
                .frame(width: 120, height: height)
            )
            let stack = unwrap(innerStackNode(under: node))
            let bar = unwrap(stack.children.first)
            XCTAssertEqual(bar.resolvedFrame.height, height, accuracy: 0.51)
            XCTAssertEqual(bar.resolvedFrame.minY, 0, accuracy: 0.51)
            XCTAssertEqual(bar.resolvedFrame.width, 2, accuracy: 0.51)
        }
    }

    // MARK: - Regression anchors (behavior that must not change)

    func testExplicitWidthChildIsNotExpanded() async {
        await MainActor.run {
            let node = makeStackRuntimeNode(
                VStack(alignment: .center, spacing: 0) {
                    Color.clear.frame(width: 40, height: 2).background(Color.red)
                    Text("Label")
                }
                .frame(width: 200, height: 60)
            )
            let stack = unwrap(innerStackNode(under: node))
            let bar = unwrap(stack.children.first)
            XCTAssertEqual(bar.resolvedFrame.width, 40, accuracy: 0.51)
            XCTAssertEqual(bar.resolvedFrame.midX, 100, accuracy: 0.51)
        }
    }

    func testUnpaintedZeroMeasureChildStaysZeroWidth() async {
        await MainActor.run {
            let stack = ViewNode(
                frame: Rect(x: 0, y: 0, width: 200, height: 60),
                layoutMode: .stack(.vertical(alignment: .leading))
            )
            let plain = ViewNode(preferredSize: Size(width: 0, height: 4))
            let painted = ViewNode(
                backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1),
                preferredSize: Size(width: 0, height: 2)
            )
            stack.addChild(plain)
            stack.addChild(painted)
            layoutStackInRuntime(stack)

            XCTAssertEqual(
                plain.resolvedFrame.width, 0, accuracy: 0.001,
                "invisible zero-measure children must not inflate")
            XCTAssertEqual(
                painted.resolvedFrame.width, 200, accuracy: 0.001,
                "background-painted flexible children expand to the stack width")
        }
    }

    func testCenterAlignedStackKeepsFixedChildGeometry() async {
        await MainActor.run {
            let stack = ViewNode(
                frame: Rect(x: 0, y: 0, width: 200, height: 60),
                layoutMode: .stack(.vertical(alignment: .center))
            )
            let fixed = ViewNode(preferredSize: Size(width: 50, height: 10))
            stack.addChild(fixed)
            layoutStackInRuntime(stack)

            XCTAssertEqual(fixed.resolvedFrame.width, 50, accuracy: 0.001)
            XCTAssertEqual(fixed.resolvedFrame.minX, 75, accuracy: 0.001)
        }
    }
}
