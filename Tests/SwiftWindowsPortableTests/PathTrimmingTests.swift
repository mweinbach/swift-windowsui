import XCTest

@testable import SwiftWindowsCore

/// Analytic geometry tests, not a native-platform or renderer qualification.
/// Expected points and controls are derived from line lengths and polynomials,
/// never from a second call to the implementation under test.
final class PathTrimmingTests: XCTestCase {
    func testFullRangePreservesExactElementsAndBypassesPartialAdmission() throws {
        let path = Path(elements: [
            .moveTo(Point(x: 2, y: 3)),
            .quadraticCurveTo(control: Point(x: 7, y: 8), end: Point(x: 9, y: 10)),
            .cubicCurveTo(control1: Point(x: 3, y: 2), control2: Point(x: 5, y: 9), end: Point(x: 2, y: 3)),
            .close,
            .lineTo(Point(x: .infinity, y: 0)),
        ])
        var limits = PathTrimming.Limits()
        limits.maximumElements = 0
        limits.maximumWork = 0
        XCTAssertEqual(try PathTrimming.checkedTrim(path, from: 0, to: 1, limits: limits).get(), path)
        XCTAssertEqual(path.trimmedPath(from: 0, to: 1), path)
    }

    func testPolylineCutsAcrossElementsByDistance() throws {
        let path = Path(elements: [.moveTo(.zero), .lineTo(Point(x: 8, y: 0)), .lineTo(Point(x: 8, y: 6))])
        let trimmed = try checked(path, from: 0.25, to: 0.75)
        assertElements(
            trimmed.elements,
            [
                .moveTo(Point(x: 3.5, y: 0)), .lineTo(Point(x: 8, y: 0)), .lineTo(Point(x: 8, y: 2.5)),
            ], accuracy: 1e-12)
        XCTAssertEqual(path.elements.count, 3, "trimming must not mutate its source")
    }

    func testNonSquareRectangleUsesItsActualPerimeter() throws {
        let path = Path(Rect(x: 0, y: 0, width: 120, height: 40))
        assertElements(
            try checked(path, from: 0, to: 0.25).elements,
            [
                .moveTo(.zero), .lineTo(Point(x: 80, y: 0)),
            ], accuracy: 1e-12)
        let translated = Path(Rect(x: 10, y: -20, width: 120, height: 40))
        assertElements(
            try checked(translated, from: 0, to: 0.5).elements,
            [
                .moveTo(Point(x: 10, y: -20)), .lineTo(Point(x: 130, y: -20)), .lineTo(Point(x: 130, y: 20)),
            ], accuracy: 1e-12)
    }

    func testPartialClosedContourDoesNotAddAClosingStroke() throws {
        let square = Path(Rect(x: 0, y: 0, width: 100, height: 100))
        assertElements(
            try checked(square, from: 0.125, to: 0.875).elements,
            [
                .moveTo(Point(x: 50, y: 0)), .lineTo(Point(x: 100, y: 0)),
                .lineTo(Point(x: 100, y: 100)), .lineTo(Point(x: 0, y: 100)), .lineTo(Point(x: 0, y: 50)),
            ], accuracy: 1e-12)
        assertElements(
            try checked(square, from: 0.75, to: 1).elements,
            [
                .moveTo(Point(x: 0, y: 100)), .lineTo(.zero),
            ], accuracy: 1e-12)
    }

    func testDisconnectedContoursDoNotMeasureOrDrawTheirMoveGap() throws {
        let path = Path(elements: [
            .moveTo(.zero), .lineTo(Point(x: 4, y: 0)),
            .moveTo(Point(x: 1_000, y: 5)), .lineTo(Point(x: 1_008, y: 5)),
        ])
        assertElements(
            try checked(path, from: 0.25, to: 0.75).elements,
            [
                .moveTo(Point(x: 3, y: 0)), .lineTo(Point(x: 4, y: 0)),
                .moveTo(Point(x: 1_000, y: 5)), .lineTo(Point(x: 1_005, y: 5)),
            ], accuracy: 1e-12)
        assertElements(
            try checked(path, from: 1.0 / 3, to: 1).elements,
            [
                .moveTo(Point(x: 1_000, y: 5)), .lineTo(Point(x: 1_008, y: 5)),
            ], accuracy: 1e-12)
    }

    func testWholeClosedContourKeepsCloseEvenWhenClosingEdgeHasZeroLength() throws {
        let path = Path(elements: [
            .moveTo(.zero), .lineTo(Point(x: 4, y: 0)), .lineTo(.zero), .close,
            .moveTo(Point(x: 100, y: 0)), .lineTo(Point(x: 108, y: 0)),
        ])
        XCTAssertEqual(
            try checked(path, from: 0, to: 0.5).elements,
            [
                .moveTo(.zero), .lineTo(Point(x: 4, y: 0)), .lineTo(.zero), .close,
            ])
    }

    func testQuadraticLengthIsNotItsParameterEvenWhenItIsStraight() throws {
        // B(t) = (100*t*t, 0): a quarter of the length is t=1/2.
        let path = Path(elements: [.moveTo(.zero), .quadraticCurveTo(control: .zero, end: Point(x: 100, y: 0))])
        assertElements(
            try checked(path, from: 0, to: 0.25).elements,
            [
                .moveTo(.zero), .quadraticCurveTo(control: .zero, end: Point(x: 25, y: 0)),
            ])
        // Cutting both ends also checks rebasing the second De Casteljau split.
        assertElements(
            try checked(path, from: 0.25, to: 0.81).elements,
            [
                .moveTo(Point(x: 25, y: 0)),
                .quadraticCurveTo(control: Point(x: 45, y: 0), end: Point(x: 81, y: 0)),
            ])
    }

    func testCubicLengthIsNotItsParameterEvenWhenItIsStraight() throws {
        // B(t) = (64*t*t*t, 0), with t boundaries 1/2 and 3/4.
        let path = Path(elements: [
            .moveTo(.zero), .cubicCurveTo(control1: .zero, control2: .zero, end: Point(x: 64, y: 0)),
        ])
        assertElements(
            try checked(path, from: 0.125, to: 27.0 / 64).elements,
            [
                .moveTo(Point(x: 8, y: 0)),
                .cubicCurveTo(control1: Point(x: 12, y: 0), control2: Point(x: 18, y: 0), end: Point(x: 27, y: 0)),
            ])
    }

    func testDistantLongLineDoesNotRelaxASmallCurvesEndpointPrecision() throws {
        let path = Path(elements: [
            .moveTo(.zero), .quadraticCurveTo(control: .zero, end: Point(x: 100, y: 0)),
            .lineTo(Point(x: 10_000_000_100, y: 0)),
        ])
        assertElements(
            try checked(path, from: 0, to: 90.0 / 10_000_000_100).elements,
            [
                .moveTo(.zero), .quadraticCurveTo(control: .zero, end: Point(x: 90, y: 0)),
            ])
    }

    func testSymmetricQuadraticHalfHasAnalyticControls() throws {
        let path = Path(elements: [
            .moveTo(.zero), .quadraticCurveTo(control: Point(x: 50, y: 100), end: Point(x: 100, y: 0)),
        ])
        assertElements(
            try checked(path, from: 0, to: 0.5).elements,
            [
                .moveTo(.zero), .quadraticCurveTo(control: Point(x: 25, y: 50), end: Point(x: 50, y: 50)),
            ])
    }

    func testSymmetricCubicHalfHasAnalyticControls() throws {
        let path = Path(elements: [
            .moveTo(.zero),
            .cubicCurveTo(control1: Point(x: 0, y: 100), control2: Point(x: 100, y: 100), end: Point(x: 100, y: 0)),
        ])
        assertElements(
            try checked(path, from: 0, to: 0.5).elements,
            [
                .moveTo(.zero),
                .cubicCurveTo(control1: Point(x: 0, y: 50), control2: Point(x: 25, y: 75), end: Point(x: 50, y: 75)),
            ])
    }

    func testRetracedQuadraticHasLengthDespiteCoincidentEndpoints() throws {
        let path = Path(elements: [.moveTo(.zero), .quadraticCurveTo(control: Point(x: 100, y: 0), end: .zero)])
        assertElements(
            try checked(path, from: 0.25, to: 0.75).elements,
            [
                .moveTo(Point(x: 25, y: 0)),
                .quadraticCurveTo(control: Point(x: 75, y: 0), end: Point(x: 25, y: 0)),
            ])
    }

    func testNestedPathTrimComposesFractionsForAnOpenLine() throws {
        let path = Path(elements: [.moveTo(.zero), .lineTo(Point(x: 100, y: 0))])
        let inner = try checked(path, from: 0.2, to: 0.8)
        assertElements(
            try checked(inner, from: 0.25, to: 0.75).elements,
            [
                .moveTo(Point(x: 35, y: 0)), .lineTo(Point(x: 65, y: 0)),
            ], accuracy: 1e-12)
    }

    func testCircularArcUsesAnalyticLengthAndCanBeginAContour() throws {
        let path = Path(elements: [.arc(center: .zero, radius: 10, startAngle: 0, endAngle: .pi, clockwise: false)])
        let diagonal = 5 * 2.0.squareRoot()
        assertElements(
            try checked(path, from: 0.25, to: 0.75).elements,
            [
                .moveTo(Point(x: diagonal, y: diagonal)),
                .arc(center: .zero, radius: 10, startAngle: .pi / 4, endAngle: 3 * .pi / 4, clockwise: false),
            ], accuracy: 1e-10)
    }

    func testArcDirectionAndExplicitFullTurnAreNotShortestPathInterpolation() throws {
        let clockwise = Path(elements: [
            .arc(center: .zero, radius: 10, startAngle: 0, endAngle: 3 * .pi / 2, clockwise: true)
        ])
        assertElements(
            try checked(clockwise, from: 0, to: 0.5).elements,
            [
                .moveTo(Point(x: 10, y: 0)),
                .arc(center: .zero, radius: 10, startAngle: 0, endAngle: -.pi / 4, clockwise: true),
            ], accuracy: 1e-10)
        let full = Path(elements: [
            .arc(center: .zero, radius: 10, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
        ])
        assertElements(
            try checked(full, from: 0.25, to: 0.75).elements,
            [
                .moveTo(Point(x: 0, y: 10)),
                .arc(center: .zero, radius: 10, startAngle: .pi / 2, endAngle: 3 * .pi / 2, clockwise: false),
            ], accuracy: 1e-10)
    }

    func testSingleFullTurnsRetainRequestedDirectionForEitherAngleSign() throws {
        for clockwise in [true, false] {
            let direction = clockwise ? -1.0 : 1.0
            for endSign in [-1.0, 1.0] {
                let path = Path(elements: [
                    .arc(center: .zero, radius: 10, startAngle: 0, endAngle: endSign * 2 * .pi, clockwise: clockwise)
                ])
                assertElements(
                    try checked(path, from: 0.25, to: 0.75).elements,
                    [
                        .moveTo(Point(x: 0, y: direction * 10)),
                        .arc(
                            center: .zero, radius: 10, startAngle: direction * .pi / 2,
                            endAngle: direction * 3 * .pi / 2, clockwise: clockwise),
                    ], accuracy: 1e-10)
                XCTAssertEqual(try checked(path, from: 0, to: 1), path)
                XCTAssertEqual(path.trimmedPath(from: 0, to: 1), path)
            }
        }
    }

    func testExactOpposedWholeTurnMultiplesRetainOneRequestedTurn() throws {
        // Powers of two make these exact multiples of the stored Double turn.
        // One requested turn for opposed multiples is a bounded Core policy,
        // not a claim about native behavior beyond the documented single circle.
        for clockwise in [true, false] {
            let direction = clockwise ? -1.0 : 1.0
            for turns in [2.0, 4.0, 8.0, 4_096.0] {
                let path = Path(elements: [
                    .arc(
                        center: .zero, radius: 10, startAngle: 0, endAngle: -direction * turns * 2 * .pi,
                        clockwise: clockwise)
                ])
                assertElements(
                    try checked(path, from: 0, to: 0.5).elements,
                    [
                        .moveTo(Point(x: 10, y: 0)),
                        .arc(center: .zero, radius: 10, startAngle: 0, endAngle: direction * .pi, clockwise: clockwise),
                    ], accuracy: 1e-10)
            }
        }
    }

    func testAlignedWholeTurnMultiplesKeepExistingMultiTurnLength() throws {
        for clockwise in [true, false] {
            let direction = clockwise ? -1.0 : 1.0
            for turns in [2.0, 4.0, 8.0] {
                let path = Path(elements: [
                    .arc(
                        center: .zero, radius: 10, startAngle: 0, endAngle: direction * turns * 2 * .pi,
                        clockwise: clockwise)
                ])
                assertElements(
                    try checked(path, from: 0, to: 1 / (4 * turns)).elements,
                    [
                        .moveTo(Point(x: 10, y: 0)),
                        .arc(
                            center: .zero, radius: 10, startAngle: 0, endAngle: direction * .pi / 2,
                            clockwise: clockwise),
                    ], accuracy: 1e-10)
            }
        }
    }

    func testNonintegralReverseWrapAndEqualAnglesKeepPreviousPolicies() throws {
        for clockwise in [true, false] {
            let direction = clockwise ? -1.0 : 1.0
            let reversed = Path(elements: [
                .arc(center: .zero, radius: 10, startAngle: 0, endAngle: -direction * 3 * .pi, clockwise: clockwise)
            ])
            assertElements(
                try checked(reversed, from: 0, to: 0.5).elements,
                [
                    .moveTo(Point(x: 10, y: 0)),
                    .arc(center: .zero, radius: 10, startAngle: 0, endAngle: direction * .pi / 2, clockwise: clockwise),
                ], accuracy: 1e-10)
            for angle in [0.0, 0.75] {
                let equalAngles = Path(elements: [
                    .arc(center: .zero, radius: 10, startAngle: angle, endAngle: angle, clockwise: clockwise)
                ])
                XCTAssertTrue(try checked(equalAngles, from: 0, to: 0.5).isEmpty)
            }
        }
    }

    func testArcAfterCloseStartsAtItsOwnOriginWithoutConnector() throws {
        // The first closed line and the following semicircle both measure 10*pi.
        let path = Path(elements: [
            .moveTo(.zero), .lineTo(Point(x: 5 * .pi, y: 0)), .close,
            .arc(center: Point(x: 100, y: 0), radius: 10, startAngle: 0, endAngle: .pi, clockwise: false),
        ])
        assertElements(
            try checked(path, from: 0.5, to: 1).elements,
            [
                .moveTo(Point(x: 110, y: 0)),
                .arc(center: Point(x: 100, y: 0), radius: 10, startAngle: 0, endAngle: .pi, clockwise: false),
            ], accuracy: 1e-10)

        // Closing that new arc returns to its own start, not the previous contour.
        // The selection begins after 5*pi units of a 10*pi + 20 perimeter.
        let closedArc = Path(elements: [
            .moveTo(Point(x: 500, y: 500)), .close,
            .arc(center: Point(x: 100, y: 0), radius: 10, startAngle: 0, endAngle: .pi, clockwise: false), .close,
        ])
        assertElements(
            try checked(closedArc, from: 5 * .pi / (10 * .pi + 20), to: 1).elements,
            [
                .moveTo(Point(x: 100, y: 10)),
                .arc(center: Point(x: 100, y: 0), radius: 10, startAngle: .pi / 2, endAngle: .pi, clockwise: false),
                .lineTo(Point(x: 110, y: 0)),
            ], accuracy: 1e-10)
    }

    func testZeroArcBodyStillMeasuresItsImplicitConnector() throws {
        let path = Path(elements: [
            .moveTo(Point(x: 5, y: 0)),
            .arc(center: .zero, radius: 0, startAngle: 0, endAngle: 0, clockwise: false),
        ])
        assertElements(
            try checked(path, from: 0.2, to: 0.8).elements,
            [
                .moveTo(Point(x: 4, y: 0)), .lineTo(Point(x: 1, y: 0)),
            ], accuracy: 1e-12)
        let bareZero = Path(elements: [
            .arc(center: .zero, radius: 10, startAngle: 0, endAngle: 0, clockwise: false)
        ])
        XCTAssertTrue(try checked(bareZero, from: 0, to: 0.5).isEmpty)
    }

    func testEmptySelectionAndRepeatedZeroLengthSegmentsStayEmpty() throws {
        XCTAssertTrue(try checked(Path(), from: 0.2, to: 0.8).isEmpty)
        let repeated = Path(elements: [
            .moveTo(.zero), .lineTo(.zero), .quadraticCurveTo(control: .zero, end: .zero), .close,
        ])
        XCTAssertTrue(try checked(repeated, from: 0, to: 0.5).isEmpty)
        XCTAssertTrue(try checked(Path(Rect(x: 0, y: 0, width: 10, height: 10)), from: 0.4, to: 0.4).isEmpty)
    }

    func testInvalidFractionsRejectWithoutReturningTheOriginalPath() {
        let path = Path(Rect(x: 0, y: 0, width: 10, height: 10))
        for (from, to) in [(-0.1, 0.5), (0.0, 1.1), (0.8, 0.2), (Double.nan, 0.5), (0.0, .infinity)] {
            assertFailure(path, from: from, to: to, equals: .invalidFractions)
            XCTAssertTrue(path.trimmedPath(from: from, to: to).isEmpty)
        }
    }

    func testMalformedAndNonfiniteGeometryRejectsTheWholePartialPath() {
        let malformed = Path(elements: [.lineTo(Point(x: 20, y: 0))])
        assertFailure(malformed, equals: .missingCurrentPoint)
        let afterClose = Path(elements: [.moveTo(.zero), .lineTo(Point(x: 10, y: 0)), .close, .lineTo(.zero)])
        assertFailure(afterClose, equals: .missingCurrentPoint)
        let invalidTail = Path(elements: [
            .moveTo(.zero), .lineTo(Point(x: 10, y: 0)), .lineTo(Point(x: .nan, y: 0)),
        ])
        assertFailure(invalidTail, equals: .invalidGeometry)
        XCTAssertTrue(invalidTail.trimmedPath(from: 0, to: 0.25).isEmpty, "never emit a valid-looking prefix")
        for radius in [-1.0, Double.infinity] {
            assertFailure(
                Path(elements: [.arc(center: .zero, radius: radius, startAngle: 0, endAngle: 1, clockwise: false)]),
                equals: .invalidGeometry)
        }
        assertFailure(
            Path(elements: [.arc(center: .zero, radius: 1, startAngle: 0, endAngle: 1e100, clockwise: false)]),
            equals: .invalidGeometry)
    }

    func testFiniteButUnrepresentableGeometryRejectsRatherThanTrapping() {
        let overflowingDistance = Path(elements: [
            .moveTo(Point(x: -1e308, y: 0)), .lineTo(Point(x: 1e308, y: 0)),
        ])
        assertFailure(overflowingDistance, equals: .numericalLimit)
        let lostLength = Path(elements: [
            .moveTo(.zero), .lineTo(Point(x: 1e300, y: 0)), .moveTo(.zero), .lineTo(Point(x: 1, y: 0)),
        ])
        assertFailure(lostLength, equals: .numericalLimit)
        let overflowingArcInterior = Path(elements: [
            .arc(center: Point(x: 1.7e308, y: 0), radius: 1e307, startAngle: -0.5, endAngle: 0.5, clockwise: false)
        ])
        assertFailure(overflowingArcInterior, from: 0.1, to: 0.9, equals: .numericalLimit)
        XCTAssertTrue(overflowingArcInterior.trimmedPath(from: 0.5, to: 0.75).isEmpty)
    }

    func testFiniteWorkPoliciesRejectWithoutAWholePathOrPrefixFallback() {
        let curve = Path(elements: [
            .moveTo(.zero), .quadraticCurveTo(control: Point(x: 50, y: 100), end: Point(x: 100, y: 0)),
        ])
        var limits = PathTrimming.Limits()
        limits.maximumWork = 1
        assertFailure(curve, equals: .workLimit, limits: limits)
        limits = PathTrimming.Limits()
        limits.maximumCurveDepth = 0
        assertFailure(curve, equals: .workLimit, limits: limits)
        limits = PathTrimming.Limits()
        limits.maximumElements = 1
        assertFailure(curve, equals: .inputLimit, limits: limits)
        limits = PathTrimming.Limits()
        limits.maximumSegments = 0
        assertFailure(curve, equals: .inputLimit, limits: limits)
        limits = PathTrimming.Limits()
        limits.maximumInverseIterations = 0
        let straight = Path(elements: [.moveTo(.zero), .quadraticCurveTo(control: .zero, end: Point(x: 100, y: 0))])
        assertFailure(straight, equals: .workLimit, limits: limits)
    }

    private func checked(_ path: Path, from: Double, to: Double) throws -> Path {
        try PathTrimming.checkedTrim(path, from: from, to: to).get()
    }

    private func assertFailure(
        _ path: Path, from: Double = 0, to: Double = 0.5, equals expected: PathTrimming.Failure,
        limits: PathTrimming.Limits = PathTrimming.Limits(), file: StaticString = #filePath, line: UInt = #line
    ) {
        switch PathTrimming.checkedTrim(path, from: from, to: to, limits: limits) {
        case .failure(let actual): XCTAssertEqual(actual, expected, file: file, line: line)
        case .success: XCTFail("Expected an explicit partial-trim rejection", file: file, line: line)
        }
    }

    private func assertElements(
        _ actual: [PathElement], _ expected: [PathElement], accuracy: Double = 1e-5,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        for (actual, expected) in zip(actual, expected) {
            switch (actual, expected) {
            case (.moveTo(let a), .moveTo(let b)), (.lineTo(let a), .lineTo(let b)):
                assertPoint(a, b, accuracy: accuracy, file: file, line: line)
            case (.quadraticCurveTo(let ac, let ae), .quadraticCurveTo(let bc, let be)):
                assertPoint(ac, bc, accuracy: accuracy, file: file, line: line)
                assertPoint(ae, be, accuracy: accuracy, file: file, line: line)
            case (.cubicCurveTo(let a1, let a2, let ae), .cubicCurveTo(let b1, let b2, let be)):
                assertPoint(a1, b1, accuracy: accuracy, file: file, line: line)
                assertPoint(a2, b2, accuracy: accuracy, file: file, line: line)
                assertPoint(ae, be, accuracy: accuracy, file: file, line: line)
            case (.arc(let ac, let ar, let a0, let a1, let ad), .arc(let bc, let br, let b0, let b1, let bd)):
                assertPoint(ac, bc, accuracy: accuracy, file: file, line: line)
                XCTAssertEqual(ar, br, accuracy: accuracy, file: file, line: line)
                XCTAssertEqual(a0, b0, accuracy: accuracy, file: file, line: line)
                XCTAssertEqual(a1, b1, accuracy: accuracy, file: file, line: line)
                XCTAssertEqual(ad, bd, file: file, line: line)
            case (.close, .close): break
            default: XCTFail("Element kind differs: \(actual) versus \(expected)", file: file, line: line)
            }
        }
    }

    private func assertPoint(
        _ actual: Point, _ expected: Point, accuracy: Double, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(actual.x, expected.x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: accuracy, file: file, line: line)
    }
}
