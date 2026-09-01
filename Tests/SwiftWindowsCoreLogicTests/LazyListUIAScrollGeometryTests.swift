import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI

final class LazyListUIAScrollGeometryTests: XCTestCase {
    func testOrdinaryBottomRevealUsesActualTargetExtent() {
        assertOffset(makeGeometry(), requested: 100, clamped: 100)
    }

    func testFractionalAncestorOriginsPreserveTheOrdinaryWalk() {
        let geometry = makeGeometry(
            targetFrame: Rect(x: 1.25, y: 3.5, width: 20.25, height: 12.75),
            ancestorOrigins: [Point(x: 0.125, y: 40.25), Point(x: 0.375, y: 10.5)],
            viewportSize: Size(width: 120.5, height: 20.5),
            contentSize: Size(width: 120.5, height: 500.75), logicalOffset: 40.5)

        assertOffset(geometry, requested: 46.5, clamped: 46.5)
    }

    func testVisibleTargetAndEqualViewportEdgesKeepTheCurrentOffset() {
        for y in [80.0, 90, 120] {
            assertOffset(
                makeGeometry(targetFrame: Rect(x: 0, y: y, width: 120, height: 20)),
                requested: 80, clamped: 80)
        }
    }

    func testLeadingEdgeTakesPrecedenceForAnOversizedTarget() {
        assertOffset(
            makeGeometry(targetFrame: Rect(x: 0, y: 60, width: 120, height: 200)),
            requested: 60, clamped: 60)
    }

    func testRequestedOffsetIsPreservedWhenClampingAtEitherBound() {
        assertOffset(
            makeGeometry(targetFrame: Rect(x: 0, y: -10, width: 120, height: 20)),
            requested: -10, clamped: 0)
        assertOffset(
            makeGeometry(targetFrame: Rect(x: 0, y: 980, width: 120, height: 40), logicalOffset: 0),
            requested: 960, clamped: 940)
    }

    func testLogicalOffsetIsClampedBeforeComputingTheVisibleInterval() {
        assertOffset(
            makeGeometry(targetFrame: Rect(x: 0, y: 0, width: 120, height: 20), logicalOffset: -100),
            requested: 0, clamped: 0)
        assertOffset(
            makeGeometry(targetFrame: Rect(x: 0, y: 950, width: 120, height: 20), logicalOffset: 2_000),
            requested: 940, clamped: 940)
    }

    func testContentSmallerThanTheViewportHasAValidZeroRange() {
        for contentSize in [Size.zero, Size(width: 120, height: 40)] {
            assertOffset(
                makeGeometry(
                    targetFrame: Rect(x: 0, y: 10, width: 20, height: 10),
                    contentSize: contentSize, logicalOffset: 900),
                requested: 0, clamped: 0)
        }
    }

    func testMotionCompositionRemainsLeftAssociated() {
        let geometry = makeGeometry(
            targetFrame: Rect(x: 0, y: 2, width: 1, height: 1),
            viewportSize: Size(width: 120, height: 10), contentSize: Size(width: 120, height: 100),
            logicalOffset: 1, overshoot: 1e16, presentedDelta: -1e16)

        // (1 + 1e16) - 1e16 rounds to zero; 1 + (1e16 - 1e16) is one.
        assertOffset(geometry, requested: 0, clamped: 0)
    }

    func testNegativePresentationOffsetIsClampedOnlyAfterTheRevealCalculation() {
        assertOffset(
            makeGeometry(
                targetFrame: Rect(x: 0, y: 0, width: 120, height: 20), logicalOffset: 0, overshoot: -5),
            requested: -5, clamped: 0)
    }

    func testRequestedSubtractionRetainsTheOrdinaryRoundingOrder() {
        let geometry = makeGeometry(
            targetFrame: Rect(x: 0, y: 1, width: 120, height: 1e16),
            viewportSize: Size(width: 120, height: 1e16 - 2),
            contentSize: Size(width: 120, height: 2e16), logicalOffset: 0)

        // (1 + 1e16) - (1e16 - 2) is two. Regrouping gives three.
        assertOffset(geometry, requested: 2, clamped: 2)
    }

    func testAncestorAccumulationIsNotRegrouped() {
        let geometry = makeGeometry(
            targetFrame: Rect(x: 0, y: 1, width: 1, height: 1),
            ancestorOrigins: [Point(x: 0, y: 1e16), Point(x: 0, y: -1e16)],
            viewportSize: Size(width: 120, height: 0.5),
            contentSize: Size(width: 120, height: 100), logicalOffset: 0)

        // The actual walk places the target at zero, not at one.
        assertOffset(geometry, requested: 0.5, clamped: 0.5)
    }

    func testEveryRawNonfiniteFieldIsRejected() {
        for value in [Double.nan, .infinity, -.infinity] {
            let cases: [(String, RetainedLazyListUIAScrollGeometry)] = [
                ("target x", makeGeometry(targetFrame: Rect(x: value, y: 140, width: 120, height: 20))),
                ("target y", makeGeometry(targetFrame: Rect(x: 0, y: value, width: 120, height: 20))),
                ("target width", makeGeometry(targetFrame: Rect(x: 0, y: 140, width: value, height: 20))),
                ("target height", makeGeometry(targetFrame: Rect(x: 0, y: 140, width: 120, height: value))),
                ("ancestor x", makeGeometry(ancestorOrigins: [Point(x: value, y: 0)])),
                ("ancestor y", makeGeometry(ancestorOrigins: [Point(x: 0, y: value)])),
                ("viewport width", makeGeometry(viewportSize: Size(width: value, height: 60))),
                ("viewport height", makeGeometry(viewportSize: Size(width: 120, height: value))),
                ("content width", makeGeometry(contentSize: Size(width: value, height: 1_000))),
                ("content height", makeGeometry(contentSize: Size(width: 120, height: value))),
                ("logical offset", makeGeometry(logicalOffset: value)),
                ("overshoot", makeGeometry(overshoot: value)),
                ("presented delta", makeGeometry(presentedDelta: value)),
            ]
            for (name, geometry) in cases {
                XCTAssertNil(geometry.checkedOffset(), "\(name): \(value)")
            }
        }
    }

    func testNonpositiveTargetAndViewportExtentsAreRejected() {
        for value in [0.0, -1, -Double.leastNonzeroMagnitude] {
            let cases = [
                makeGeometry(targetFrame: Rect(x: 0, y: 140, width: value, height: 20)),
                makeGeometry(targetFrame: Rect(x: 0, y: 140, width: 120, height: value)),
                makeGeometry(viewportSize: Size(width: value, height: 60)),
                makeGeometry(viewportSize: Size(width: 120, height: value)),
            ]
            for geometry in cases { XCTAssertNil(geometry.checkedOffset()) }
        }
    }

    func testNegativeContentExtentsAreRejected() {
        XCTAssertNil(makeGeometry(contentSize: Size(width: -1, height: 1_000)).checkedOffset())
        XCTAssertNil(makeGeometry(contentSize: Size(width: 120, height: -1)).checkedOffset())
    }

    func testRawTargetEdgeOverflowIsRejectedOnBothAxes() {
        let largest = Double.greatestFiniteMagnitude
        XCTAssertNil(
            makeGeometry(targetFrame: Rect(x: largest, y: 140, width: largest, height: 20)).checkedOffset())
        XCTAssertNil(
            makeGeometry(targetFrame: Rect(x: 0, y: largest, width: 120, height: largest)).checkedOffset())
    }

    func testTranslatedOriginOverflowIsRejectedOnBothAxesAndSigns() {
        for value in [Double.greatestFiniteMagnitude, -Double.greatestFiniteMagnitude] {
            XCTAssertNil(
                makeGeometry(
                    targetFrame: Rect(x: value, y: 140, width: 1, height: 20),
                    ancestorOrigins: [Point(x: value, y: 0)]
                ).checkedOffset())
            XCTAssertNil(
                makeGeometry(
                    targetFrame: Rect(x: 0, y: value, width: 120, height: 1),
                    ancestorOrigins: [Point(x: 0, y: value)]
                ).checkedOffset())
        }
    }

    func testLaterAncestorOverflowIsRejectedBeforeAnyCancellationSum() {
        let largest = Double.greatestFiniteMagnitude
        XCTAssertNil(
            makeGeometry(
                targetFrame: Rect(x: 0, y: 0, width: 1, height: 1),
                ancestorOrigins: [Point(x: 0, y: largest), Point(x: 0, y: largest), Point(x: 0, y: -largest)]
            ).checkedOffset())
    }

    func testTranslatedTargetEdgesCannotOverflowWithFiniteOrigins() {
        let largest = Double.greatestFiniteMagnitude
        XCTAssertNil(
            makeGeometry(
                targetFrame: Rect(x: 0, y: 140, width: largest, height: 20),
                ancestorOrigins: [Point(x: largest, y: 0)]
            ).checkedOffset())
        XCTAssertNil(
            makeGeometry(
                targetFrame: Rect(x: 0, y: 0, width: 120, height: largest),
                ancestorOrigins: [Point(x: 0, y: largest)]
            ).checkedOffset())
    }

    func testEachOverflowingMotionStageIsRejected() {
        let largest = Double.greatestFiniteMagnitude
        XCTAssertNil(
            makeGeometry(
                viewportSize: Size(width: 120, height: 1),
                contentSize: Size(width: 120, height: largest), logicalOffset: largest, overshoot: largest
            ).checkedOffset())
        XCTAssertNil(makeGeometry(logicalOffset: 0, overshoot: largest, presentedDelta: largest).checkedOffset())
        XCTAssertNil(makeGeometry(logicalOffset: 0, overshoot: -largest, presentedDelta: -largest).checkedOffset())
    }

    func testVisibleEndOverflowIsRejectedEvenWhenTheLeadingBranchWouldReturnFinite() {
        let largest = Double.greatestFiniteMagnitude
        XCTAssertNil(
            makeGeometry(
                viewportSize: Size(width: 120, height: largest),
                contentSize: Size(width: 120, height: largest), logicalOffset: 0, overshoot: largest
            ).checkedOffset())
    }

    func testTwoOverflowingEndsCannotMasqueradeAsAClampedZeroOffset() {
        let largest = Double.greatestFiniteMagnitude
        XCTAssertNil(
            makeGeometry(
                targetFrame: Rect(x: 0, y: largest, width: 120, height: largest),
                viewportSize: Size(width: 120, height: largest),
                contentSize: Size(width: 120, height: largest), logicalOffset: 0, overshoot: largest
            ).checkedOffset())
    }

    func testLargestFiniteCoordinatesAreNotRejectedSolelyForTheirMagnitude() {
        let largest = Double.greatestFiniteMagnitude
        assertOffset(
            makeGeometry(
                targetFrame: Rect(x: 0, y: largest, width: 120, height: 1),
                viewportSize: Size(width: 120, height: 1),
                contentSize: Size(width: 120, height: largest), logicalOffset: 0),
            requested: largest, clamped: largest)
        assertOffset(
            makeGeometry(targetFrame: Rect(x: 0, y: -largest, width: 120, height: 1), logicalOffset: 0),
            requested: -largest, clamped: 0)
    }

    private func makeGeometry(
        targetFrame: Rect = Rect(x: 0, y: 140, width: 120, height: 20),
        ancestorOrigins: [Point] = [], viewportSize: Size = Size(width: 120, height: 60),
        contentSize: Size = Size(width: 120, height: 1_000), logicalOffset: Double = 80,
        overshoot: Double = 0, presentedDelta: Double = 0
    ) -> RetainedLazyListUIAScrollGeometry {
        RetainedLazyListUIAScrollGeometry(
            targetFrame: targetFrame, ancestorOrigins: ancestorOrigins, viewportSize: viewportSize,
            contentSize: contentSize, logicalOffset: logicalOffset, overshoot: overshoot,
            presentedDelta: presentedDelta)
    }

    private func assertOffset(
        _ geometry: RetainedLazyListUIAScrollGeometry, requested: Double, clamped: Double,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(
            geometry.checkedOffset(),
            RetainedLazyListUIAScrollGeometry.Offset(requestedOffset: requested, clampedOffset: clamped),
            file: file, line: line)
    }
}
