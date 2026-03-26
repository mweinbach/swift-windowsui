import XCTest
import SwiftWindowsGraphics

final class GPUILayerStackTests: XCTestCase {

    // MARK: - splitSiblings

    func testAllSameZIndexReturnsSingleGroup() {
        let result = GPUILayerStack.splitSiblings(zIndices: [0, 0, 0])
        XCTAssertEqual(result.groups, [[0, 1, 2]])
    }

    func testMixedZIndicesReturnsTwoGroups() {
        let result = GPUILayerStack.splitSiblings(zIndices: [0, 1, 0])
        XCTAssertEqual(result.groups, [[0, 2], [1]])
    }

    func testAscendingZIndicesReturnsThreeGroups() {
        let result = GPUILayerStack.splitSiblings(zIndices: [0, 1, 2])
        XCTAssertEqual(result.groups, [[0], [1], [2]])
    }

    func testSingleSiblingReturnsSingleGroup() {
        let result = GPUILayerStack.splitSiblings(zIndices: [5])
        XCTAssertEqual(result.groups, [[0]])
    }

    func testEmptySiblingsReturnsSingleEmptyGroup() {
        let result = GPUILayerStack.splitSiblings(zIndices: [])
        XCTAssertEqual(result.groups, [[]])
    }

    func testNegativeZIndexGroupsSortedCorrectly() {
        let result = GPUILayerStack.splitSiblings(zIndices: [-1, 0, 1])
        XCTAssertEqual(result.groups, [[0], [1], [2]])
    }

    func testMixedWithDuplicatesPreservesTreeOrder() {
        let result = GPUILayerStack.splitSiblings(zIndices: [0, 0, 1, 0, 1])
        XCTAssertEqual(result.groups, [[0, 1, 3], [2, 4]])
    }

    // MARK: - needsCompositingLayer

    func testSemiTransparentWithChildrenDoesNotNeedLayer() {
        XCTAssertFalse(
            GPUILayerStack.needsCompositingLayer(
                opacity: 0.5, hasChildren: true, hasBlur: false, hasTransform: false
            )
        )
    }

    func testSemiTransparentWithoutChildrenDoesNotNeedLayer() {
        XCTAssertFalse(
            GPUILayerStack.needsCompositingLayer(
                opacity: 0.5, hasChildren: false, hasBlur: false, hasTransform: false
            )
        )
    }

    func testFullyOpaqueWithChildrenDoesNotNeedLayer() {
        XCTAssertFalse(
            GPUILayerStack.needsCompositingLayer(
                opacity: 1.0, hasChildren: true, hasBlur: false, hasTransform: false
            )
        )
    }

    func testBlurAlwaysNeedsLayer() {
        XCTAssertTrue(
            GPUILayerStack.needsCompositingLayer(
                opacity: 1.0, hasChildren: false, hasBlur: true, hasTransform: false
            )
        )
    }

    func testAllFalseDoesNotNeedLayer() {
        XCTAssertFalse(
            GPUILayerStack.needsCompositingLayer(
                opacity: 1.0, hasChildren: false, hasBlur: false, hasTransform: false
            )
        )
    }
}
