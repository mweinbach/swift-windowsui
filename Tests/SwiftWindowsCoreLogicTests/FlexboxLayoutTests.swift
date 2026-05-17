import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsLayout

final class FlexboxLayoutTests: XCTestCase {

    // MARK: - Basic Row Layout

    func testRowLayout() {
        let input = FlexboxEngine.LayoutInput(
            containerWidth: 400, containerHeight: 100,
            style: FlexStyle(direction: .row),
            children: [
                .init(intrinsicWidth: 100, intrinsicHeight: 50),
                .init(intrinsicWidth: 100, intrinsicHeight: 50),
                .init(intrinsicWidth: 100, intrinsicHeight: 50),
            ]
        )
        let result = FlexboxEngine.layout(input)
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].x, 0, accuracy: 0.01)
        XCTAssertEqual(result[1].x, 100, accuracy: 0.01)
        XCTAssertEqual(result[2].x, 200, accuracy: 0.01)
        // With stretch alignment, heights should fill cross axis (container height)
        XCTAssertEqual(result[0].height, 100, accuracy: 0.01)
    }

    // MARK: - Column Layout

    func testColumnLayout() {
        let input = FlexboxEngine.LayoutInput(
            containerWidth: 200, containerHeight: 400,
            style: FlexStyle(direction: .column),
            children: [
                .init(intrinsicWidth: 80, intrinsicHeight: 60),
                .init(intrinsicWidth: 80, intrinsicHeight: 60),
                .init(intrinsicWidth: 80, intrinsicHeight: 60),
            ]
        )
        let result = FlexboxEngine.layout(input)
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].y, 0, accuracy: 0.01)
        XCTAssertEqual(result[1].y, 60, accuracy: 0.01)
        XCTAssertEqual(result[2].y, 120, accuracy: 0.01)
        // Column: cross axis is horizontal, stretch fills width
        XCTAssertEqual(result[0].width, 200, accuracy: 0.01)
    }

    // MARK: - Flex Grow

    func testFlexGrow() {
        // Two items with grow=1 and grow=2 in a 300-wide container, both start at 0 intrinsic width
        let input = FlexboxEngine.LayoutInput(
            containerWidth: 300, containerHeight: 100,
            style: FlexStyle(direction: .row),
            children: [
                .init(itemStyle: FlexItemStyle(grow: 1), intrinsicWidth: 0, intrinsicHeight: 50),
                .init(itemStyle: FlexItemStyle(grow: 2), intrinsicWidth: 0, intrinsicHeight: 50),
            ]
        )
        let result = FlexboxEngine.layout(input)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].width, 100, accuracy: 0.01)
        XCTAssertEqual(result[1].width, 200, accuracy: 0.01)
        XCTAssertEqual(result[0].x, 0, accuracy: 0.01)
        XCTAssertEqual(result[1].x, 100, accuracy: 0.01)
    }

    // MARK: - Flex Shrink

    func testFlexShrink() {
        // Two items totaling 400 in a 300-wide container, default shrink=1 each
        let input = FlexboxEngine.LayoutInput(
            containerWidth: 300, containerHeight: 100,
            style: FlexStyle(direction: .row),
            children: [
                .init(itemStyle: FlexItemStyle(shrink: 1), intrinsicWidth: 200, intrinsicHeight: 50),
                .init(itemStyle: FlexItemStyle(shrink: 1), intrinsicWidth: 200, intrinsicHeight: 50),
            ]
        )
        let result = FlexboxEngine.layout(input)
        XCTAssertEqual(result.count, 2)
        // Each shrinks equally: 200 + (-100) * (1/2) = 150
        XCTAssertEqual(result[0].width, 150, accuracy: 0.01)
        XCTAssertEqual(result[1].width, 150, accuracy: 0.01)
    }

    // MARK: - Justify Center

    func testJustifyCenter() {
        let input = FlexboxEngine.LayoutInput(
            containerWidth: 400, containerHeight: 100,
            style: FlexStyle(direction: .row, justifyContent: .center),
            children: [
                .init(intrinsicWidth: 100, intrinsicHeight: 50),
                .init(intrinsicWidth: 100, intrinsicHeight: 50),
            ]
        )
        let result = FlexboxEngine.layout(input)
        XCTAssertEqual(result.count, 2)
        // Total used = 200, free = 200, offset = 100
        XCTAssertEqual(result[0].x, 100, accuracy: 0.01)
        XCTAssertEqual(result[1].x, 200, accuracy: 0.01)
    }

    // MARK: - Justify Space Between

    func testJustifySpaceBetween() {
        let input = FlexboxEngine.LayoutInput(
            containerWidth: 400, containerHeight: 100,
            style: FlexStyle(direction: .row, justifyContent: .spaceBetween),
            children: [
                .init(intrinsicWidth: 100, intrinsicHeight: 50),
                .init(intrinsicWidth: 100, intrinsicHeight: 50),
                .init(intrinsicWidth: 100, intrinsicHeight: 50),
            ]
        )
        let result = FlexboxEngine.layout(input)
        XCTAssertEqual(result.count, 3)
        // Free space = 100, 2 gaps, each gap = 50
        XCTAssertEqual(result[0].x, 0, accuracy: 0.01)
        XCTAssertEqual(result[1].x, 150, accuracy: 0.01)
        XCTAssertEqual(result[2].x, 300, accuracy: 0.01)
    }

    // MARK: - Justify Space Evenly

    func testJustifySpaceEvenly() {
        let input = FlexboxEngine.LayoutInput(
            containerWidth: 400, containerHeight: 100,
            style: FlexStyle(direction: .row, justifyContent: .spaceEvenly),
            children: [
                .init(intrinsicWidth: 50, intrinsicHeight: 50),
                .init(intrinsicWidth: 50, intrinsicHeight: 50),
            ]
        )
        let result = FlexboxEngine.layout(input)
        XCTAssertEqual(result.count, 2)
        // Free space = 300, 3 slots (count+1), each = 100
        XCTAssertEqual(result[0].x, 100, accuracy: 0.01)
        XCTAssertEqual(result[1].x, 250, accuracy: 0.01)
    }

    // MARK: - Justify Space Around

    func testJustifySpaceAround() {
        let input = FlexboxEngine.LayoutInput(
            containerWidth: 400, containerHeight: 100,
            style: FlexStyle(direction: .row, justifyContent: .spaceAround),
            children: [
                .init(intrinsicWidth: 100, intrinsicHeight: 50),
                .init(intrinsicWidth: 100, intrinsicHeight: 50),
            ]
        )
        let result = FlexboxEngine.layout(input)
        XCTAssertEqual(result.count, 2)
        // Free space = 200, space per item = 100, half = 50
        XCTAssertEqual(result[0].x, 50, accuracy: 0.01)
        XCTAssertEqual(result[1].x, 250, accuracy: 0.01)
    }

    // MARK: - Gap

    func testGap() {
        let input = FlexboxEngine.LayoutInput(
            containerWidth: 400, containerHeight: 100,
            style: FlexStyle(direction: .row, gap: 20),
            children: [
                .init(intrinsicWidth: 100, intrinsicHeight: 50),
                .init(intrinsicWidth: 100, intrinsicHeight: 50),
                .init(intrinsicWidth: 100, intrinsicHeight: 50),
            ]
        )
        let result = FlexboxEngine.layout(input)
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].x, 0, accuracy: 0.01)
        XCTAssertEqual(result[1].x, 120, accuracy: 0.01)
        XCTAssertEqual(result[2].x, 240, accuracy: 0.01)
    }

    // MARK: - Padding

    func testPadding() {
        let input = FlexboxEngine.LayoutInput(
            containerWidth: 400, containerHeight: 100,
            style: FlexStyle(
                direction: .row,
                padding: EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20)
            ),
            children: [
                .init(intrinsicWidth: 100, intrinsicHeight: 50)
            ]
        )
        let result = FlexboxEngine.layout(input)
        XCTAssertEqual(result.count, 1)
        // Padding offsets: x += leading, y += top
        XCTAssertEqual(result[0].x, 20, accuracy: 0.01)
        XCTAssertEqual(result[0].y, 10, accuracy: 0.01)
    }

    // MARK: - Align Items Stretch

    func testAlignStretch() {
        let input = FlexboxEngine.LayoutInput(
            containerWidth: 400, containerHeight: 100,
            style: FlexStyle(direction: .row, alignItems: .stretch),
            children: [
                .init(intrinsicWidth: 100, intrinsicHeight: 30),
                .init(intrinsicWidth: 100, intrinsicHeight: 50),
            ]
        )
        let result = FlexboxEngine.layout(input)
        // Both children should stretch to fill the full cross axis (100)
        XCTAssertEqual(result[0].height, 100, accuracy: 0.01)
        XCTAssertEqual(result[1].height, 100, accuracy: 0.01)
    }

    // MARK: - Align Items Center

    func testAlignCenter() {
        let input = FlexboxEngine.LayoutInput(
            containerWidth: 400, containerHeight: 100,
            style: FlexStyle(direction: .row, alignItems: .center),
            children: [
                .init(intrinsicWidth: 100, intrinsicHeight: 40)
            ]
        )
        let result = FlexboxEngine.layout(input)
        XCTAssertEqual(result.count, 1)
        // Cross size = 100 (single line), child height = 40, centered at (100-40)/2 = 30
        XCTAssertEqual(result[0].y, 30, accuracy: 0.01)
        XCTAssertEqual(result[0].height, 40, accuracy: 0.01)
    }

    // MARK: - Empty Container

    func testEmptyContainer() {
        let input = FlexboxEngine.LayoutInput(
            containerWidth: 400, containerHeight: 100,
            style: FlexStyle(direction: .row),
            children: []
        )
        let result = FlexboxEngine.layout(input)
        XCTAssertEqual(result.count, 0)
    }

    // MARK: - Single Child

    func testSingleChild() {
        let input = FlexboxEngine.LayoutInput(
            containerWidth: 400, containerHeight: 100,
            style: FlexStyle(direction: .row),
            children: [
                .init(intrinsicWidth: 150, intrinsicHeight: 60)
            ]
        )
        let result = FlexboxEngine.layout(input)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].x, 0, accuracy: 0.01)
        XCTAssertEqual(result[0].y, 0, accuracy: 0.01)
        XCTAssertEqual(result[0].width, 150, accuracy: 0.01)
        // Stretch: height fills cross axis
        XCTAssertEqual(result[0].height, 100, accuracy: 0.01)
    }

    // MARK: - Row Reverse

    func testRowReverse() {
        let input = FlexboxEngine.LayoutInput(
            containerWidth: 400, containerHeight: 100,
            style: FlexStyle(direction: .rowReverse),
            children: [
                .init(intrinsicWidth: 100, intrinsicHeight: 50),
                .init(intrinsicWidth: 100, intrinsicHeight: 50),
            ]
        )
        let result = FlexboxEngine.layout(input)
        XCTAssertEqual(result.count, 2)
        // Reversed: first item at right end, second to its left
        XCTAssertEqual(result[0].x, 300, accuracy: 0.01)
        XCTAssertEqual(result[1].x, 200, accuracy: 0.01)
    }

    // MARK: - Column Reverse

    func testColumnReverse() {
        let input = FlexboxEngine.LayoutInput(
            containerWidth: 200, containerHeight: 300,
            style: FlexStyle(direction: .columnReverse),
            children: [
                .init(intrinsicWidth: 80, intrinsicHeight: 60),
                .init(intrinsicWidth: 80, intrinsicHeight: 60),
            ]
        )
        let result = FlexboxEngine.layout(input)
        XCTAssertEqual(result.count, 2)
        // Reversed: first item at bottom, second above
        XCTAssertEqual(result[0].y, 240, accuracy: 0.01)
        XCTAssertEqual(result[1].y, 180, accuracy: 0.01)
    }

    // MARK: - Justify FlexEnd

    func testJustifyFlexEnd() {
        let input = FlexboxEngine.LayoutInput(
            containerWidth: 400, containerHeight: 100,
            style: FlexStyle(direction: .row, justifyContent: .flexEnd),
            children: [
                .init(intrinsicWidth: 100, intrinsicHeight: 50),
                .init(intrinsicWidth: 100, intrinsicHeight: 50),
            ]
        )
        let result = FlexboxEngine.layout(input)
        XCTAssertEqual(result.count, 2)
        // Free space = 200, items packed at end
        XCTAssertEqual(result[0].x, 200, accuracy: 0.01)
        XCTAssertEqual(result[1].x, 300, accuracy: 0.01)
    }

    // MARK: - Align Items FlexEnd

    func testAlignFlexEnd() {
        let input = FlexboxEngine.LayoutInput(
            containerWidth: 400, containerHeight: 100,
            style: FlexStyle(direction: .row, alignItems: .flexEnd),
            children: [
                .init(intrinsicWidth: 100, intrinsicHeight: 40)
            ]
        )
        let result = FlexboxEngine.layout(input)
        XCTAssertEqual(result.count, 1)
        // Cross = 100, child = 40, positioned at bottom: 100-40 = 60
        XCTAssertEqual(result[0].y, 60, accuracy: 0.01)
        XCTAssertEqual(result[0].height, 40, accuracy: 0.01)
    }

    // MARK: - Fixed Basis

    func testFixedBasis() {
        let input = FlexboxEngine.LayoutInput(
            containerWidth: 400, containerHeight: 100,
            style: FlexStyle(direction: .row),
            children: [
                .init(itemStyle: FlexItemStyle(basis: .fixed(200)), intrinsicWidth: 50, intrinsicHeight: 50),
                .init(intrinsicWidth: 100, intrinsicHeight: 50),
            ]
        )
        let result = FlexboxEngine.layout(input)
        XCTAssertEqual(result.count, 2)
        // First child uses fixed basis of 200, ignoring intrinsic 50
        XCTAssertEqual(result[0].width, 200, accuracy: 0.01)
        XCTAssertEqual(result[1].x, 200, accuracy: 0.01)
    }

    // MARK: - Align Self Override

    func testAlignSelfOverride() {
        let input = FlexboxEngine.LayoutInput(
            containerWidth: 400, containerHeight: 100,
            style: FlexStyle(direction: .row, alignItems: .stretch),
            children: [
                .init(itemStyle: FlexItemStyle(alignSelf: .center), intrinsicWidth: 100, intrinsicHeight: 40),
                .init(intrinsicWidth: 100, intrinsicHeight: 60),
            ]
        )
        let result = FlexboxEngine.layout(input)
        // First child overrides to center: (100 - 40)/2 = 30
        XCTAssertEqual(result[0].y, 30, accuracy: 0.01)
        XCTAssertEqual(result[0].height, 40, accuracy: 0.01)
        // Second child stretches to full cross
        XCTAssertEqual(result[1].height, 100, accuracy: 0.01)
    }

    // MARK: - Space Between Single Child

    func testSpaceBetweenSingleChild() {
        let input = FlexboxEngine.LayoutInput(
            containerWidth: 400, containerHeight: 100,
            style: FlexStyle(direction: .row, justifyContent: .spaceBetween),
            children: [
                .init(intrinsicWidth: 100, intrinsicHeight: 50)
            ]
        )
        let result = FlexboxEngine.layout(input)
        XCTAssertEqual(result.count, 1)
        // Single child with spaceBetween should be at start
        XCTAssertEqual(result[0].x, 0, accuracy: 0.01)
    }
}
