import SwiftWindowsCore

import SwiftWindowsGraphics

import SwiftWindowsLayout

import SwiftWindowsPlatform

import XCTest

@testable import SwiftWindowsUI

final class FlexIntegrationTests: XCTestCase {

    // MARK: - Row Layout

    func testFlexRowLayoutPositionsChildrenHorizontally() async {
        await MainActor.run {
            let child1 = ViewNode(backgroundColor: .white, preferredSize: Size(width: 50, height: 30))
            let child2 = ViewNode(backgroundColor: .white, preferredSize: Size(width: 60, height: 30))
            let child3 = ViewNode(backgroundColor: .white, preferredSize: Size(width: 40, height: 30))

            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 300, height: 100),
                layoutMode: .flex(FlexStyle(direction: .row)),
                isHitTestVisible: false
            )
            root.addChild(child1)
            root.addChild(child2)
            root.addChild(child3)

            let runtime = RetainedViewRuntime(root: root)
            _ = runtime.renderFrame()

            // Children should be positioned horizontally with stretch on cross axis
            XCTAssertEqual(child1.resolvedFrame.origin.x, 0, accuracy: 0.01)
            XCTAssertEqual(child1.resolvedFrame.size.width, 50, accuracy: 0.01)

            XCTAssertEqual(child2.resolvedFrame.origin.x, 50, accuracy: 0.01)
            XCTAssertEqual(child2.resolvedFrame.size.width, 60, accuracy: 0.01)

            XCTAssertEqual(child3.resolvedFrame.origin.x, 110, accuracy: 0.01)
            XCTAssertEqual(child3.resolvedFrame.size.width, 40, accuracy: 0.01)
        }
    }

    // MARK: - Column Layout

    func testFlexColumnLayoutPositionsChildrenVertically() async {
        await MainActor.run {
            let child1 = ViewNode(backgroundColor: .white, preferredSize: Size(width: 80, height: 40))
            let child2 = ViewNode(backgroundColor: .white, preferredSize: Size(width: 80, height: 50))

            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 200, height: 300),
                layoutMode: .flex(FlexStyle(direction: .column)),
                isHitTestVisible: false
            )
            root.addChild(child1)
            root.addChild(child2)

            let runtime = RetainedViewRuntime(root: root)
            _ = runtime.renderFrame()

            // Children should be stacked vertically
            XCTAssertEqual(child1.resolvedFrame.origin.y, 0, accuracy: 0.01)
            XCTAssertEqual(child1.resolvedFrame.size.height, 40, accuracy: 0.01)

            XCTAssertEqual(child2.resolvedFrame.origin.y, 40, accuracy: 0.01)
            XCTAssertEqual(child2.resolvedFrame.size.height, 50, accuracy: 0.01)
        }
    }

    // MARK: - Flex Grow

    func testFlexGrowDistributesRemainingSpace() async {
        await MainActor.run {
            let child1 = ViewNode(
                backgroundColor: .white,
                preferredSize: Size(width: 50, height: 30),
                flexItemStyle: FlexItemStyle(grow: 1)
            )
            let child2 = ViewNode(
                backgroundColor: .white,
                preferredSize: Size(width: 50, height: 30),
                flexItemStyle: FlexItemStyle(grow: 3)
            )

            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 300, height: 100),
                layoutMode: .flex(FlexStyle(direction: .row)),
                isHitTestVisible: false
            )
            root.addChild(child1)
            root.addChild(child2)

            let runtime = RetainedViewRuntime(root: root)
            _ = runtime.renderFrame()

            // 300 total, 100 base (50+50), 200 remaining
            // child1 gets 50 + 200*(1/4) = 100
            // child2 gets 50 + 200*(3/4) = 200
            XCTAssertEqual(child1.resolvedFrame.size.width, 100, accuracy: 0.01)
            XCTAssertEqual(child2.resolvedFrame.size.width, 200, accuracy: 0.01)
        }
    }

    // MARK: - Justify Content Center

    func testJustifyCenterCentersChildrenOnMainAxis() async {
        await MainActor.run {
            let child1 = ViewNode(backgroundColor: .white, preferredSize: Size(width: 40, height: 30))
            let child2 = ViewNode(backgroundColor: .white, preferredSize: Size(width: 60, height: 30))

            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 300, height: 100),
                layoutMode: .flex(FlexStyle(direction: .row, justifyContent: .center)),
                isHitTestVisible: false
            )
            root.addChild(child1)
            root.addChild(child2)

            let runtime = RetainedViewRuntime(root: root)
            _ = runtime.renderFrame()

            // Total children width: 100. Free space: 200. Offset: 100
            XCTAssertEqual(child1.resolvedFrame.origin.x, 100, accuracy: 0.01)
            XCTAssertEqual(child2.resolvedFrame.origin.x, 140, accuracy: 0.01)
        }
    }

    // MARK: - Gap

    func testGapAddsSpacingBetweenChildren() async {
        await MainActor.run {
            let child1 = ViewNode(backgroundColor: .white, preferredSize: Size(width: 50, height: 30))
            let child2 = ViewNode(backgroundColor: .white, preferredSize: Size(width: 50, height: 30))
            let child3 = ViewNode(backgroundColor: .white, preferredSize: Size(width: 50, height: 30))

            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 300, height: 100),
                layoutMode: .flex(FlexStyle(direction: .row, gap: 10)),
                isHitTestVisible: false
            )
            root.addChild(child1)
            root.addChild(child2)
            root.addChild(child3)

            let runtime = RetainedViewRuntime(root: root)
            _ = runtime.renderFrame()

            XCTAssertEqual(child1.resolvedFrame.origin.x, 0, accuracy: 0.01)
            XCTAssertEqual(child2.resolvedFrame.origin.x, 60, accuracy: 0.01)  // 50 + 10
            XCTAssertEqual(child3.resolvedFrame.origin.x, 120, accuracy: 0.01)  // 50 + 10 + 50 + 10
        }
    }

    // MARK: - Regression: Stack Layout Still Works

    func testStackLayoutRegressionCheck() async {
        await MainActor.run {
            let first = ViewNode(
                backgroundColor: .white,
                preferredSize: Size(width: 20, height: 10)
            )
            let second = ViewNode(
                backgroundColor: .black,
                preferredSize: Size(width: 40, height: 20)
            )
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 100),
                layoutMode: .stack(.vertical(spacing: 5)),
                isHitTestVisible: false,
                children: [first, second]
            )
            let runtime = RetainedViewRuntime(root: root)
            _ = runtime.renderFrame()

            // First child at y=0, second at y=15 (10 + 5 spacing)
            XCTAssertEqual(first.resolvedFrame.origin.y, 0, accuracy: 0.01)
            XCTAssertEqual(second.resolvedFrame.origin.y, 15, accuracy: 0.01)
        }
    }

    // MARK: - Regression: Absolute Layout Still Works

    func testAbsoluteLayoutRegressionCheck() async {
        await MainActor.run {
            let child = ViewNode(
                frame: Rect(x: 10, y: 20, width: 50, height: 50),
                backgroundColor: .white
            )
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 200, height: 200),
                layoutMode: .absolute,
                isHitTestVisible: false,
                children: [child]
            )
            let runtime = RetainedViewRuntime(root: root)
            _ = runtime.renderFrame()

            XCTAssertEqual(child.resolvedFrame.origin.x, 10, accuracy: 0.01)
            XCTAssertEqual(child.resolvedFrame.origin.y, 20, accuracy: 0.01)
            XCTAssertEqual(child.resolvedFrame.size.width, 50, accuracy: 0.01)
            XCTAssertEqual(child.resolvedFrame.size.height, 50, accuracy: 0.01)
        }
    }
}
