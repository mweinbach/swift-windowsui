import XCTest

@testable import SwiftWindowsCore

/// Analytic controls for error sharing at curve reversals. These are not native
/// platform or renderer qualification tests.
final class PathTrimmingReversalTests: XCTestCase {
    func testNonDyadicRightReversalReusesItsMonotoneSiblingAllowance() throws {
        let path = Path(elements: [
            .moveTo(.zero),
            .quadraticCurveTo(control: Point(x: 100, y: 0), end: Point(x: 50, y: 0)),
        ])
        // The cusp is at t=2/3 and total length is 250/3. These fractions
        // select t=1/6...5/6, independently of the implementation's inversion.
        assertQuadratic(
            try PathTrimming.checkedTrim(path, from: 0.35, to: 0.85).get(),
            start: Point(x: 175.0 / 6.0, y: 0),
            control: Point(x: 475.0 / 6.0, y: 0),
            end: Point(x: 125.0 / 2.0, y: 0))
    }

    func testNonDyadicLeftReversalReusesItsMonotoneSiblingAllowance() throws {
        let path = Path(elements: [
            .moveTo(Point(x: 50, y: 0)),
            .quadraticCurveTo(control: Point(x: 100, y: 0), end: .zero),
        ])
        // Reversing the previous polynomial places its cusp at t=1/3.
        assertQuadratic(
            try PathTrimming.checkedTrim(path, from: 0.15, to: 0.65).get(),
            start: Point(x: 125.0 / 2.0, y: 0),
            control: Point(x: 475.0 / 6.0, y: 0),
            end: Point(x: 175.0 / 6.0, y: 0))
    }

    func testRotatedAndTranslatedReversalUsesEuclideanLength() throws {
        let start = Point(x: 10, y: -20)
        let path = Path(elements: [
            .moveTo(start),
            .quadraticCurveTo(control: Point(x: 70, y: 60), end: start),
        ])
        // The (60,80) control vector has length 100.
        assertQuadratic(
            try PathTrimming.checkedTrim(path, from: 0.25, to: 0.75).get(),
            start: Point(x: 25, y: 0), control: Point(x: 55, y: 40), end: Point(x: 25, y: 0))
    }

    func testCubicWithTwoReversalsSharesItsOriginalErrorAllowance() throws {
        let path = Path(elements: [
            .moveTo(.zero),
            .cubicCurveTo(control1: Point(x: 100, y: 0), control2: Point(x: -100, y: 0), end: .zero),
        ])
        // B(t)=300t(1-t)(1-2t), total length 200*sqrt(3)/3.
        // These fractions select t=1/6...5/6, away from the zero-speed extrema.
        let fraction = 5.0 / (12.0 * 3.0.squareRoot())
        let result = try PathTrimming.checkedTrim(path, from: fraction, to: 1 - fraction).get()
        guard result.elements.count == 2,
            case .moveTo(let start) = result.elements[0],
            case .cubicCurveTo(let first, let second, let end) = result.elements[1]
        else {
            XCTFail("Expected one selected cubic and its move")
            return
        }
        assertPoint(start, Point(x: 250.0 / 9.0, y: 0))
        assertPoint(first, Point(x: 350.0 / 9.0, y: 0))
        assertPoint(second, Point(x: -350.0 / 9.0, y: 0))
        assertPoint(end, Point(x: -250.0 / 9.0, y: 0))
    }

    func testReusingSiblingErrorDoesNotBypassDepthWorkOrInverseLimits() {
        let path = Path(elements: [
            .moveTo(.zero), .quadraticCurveTo(control: Point(x: 100, y: 0), end: .zero),
        ])
        var limits = PathTrimming.Limits()
        limits.maximumCurveDepth = 8
        assertFailure(path, equals: .workLimit, limits: limits)
        limits = PathTrimming.Limits()
        limits.maximumWork = 10
        assertFailure(path, equals: .workLimit, limits: limits)
        limits = PathTrimming.Limits()
        limits.maximumInverseIterations = 1
        assertFailure(path, equals: .workLimit, limits: limits)
    }

    func testExactMidpointStagnationStillRejectsTheEntireSelection() {
        let coordinate = 9_007_199_254_740_992.0
        let path = Path(elements: [
            .moveTo(Point(x: coordinate, y: coordinate)),
            .quadraticCurveTo(
                control: Point(x: coordinate, y: coordinate + 2),
                end: Point(x: coordinate + 2, y: coordinate + 2)),
        ])
        // Binary64 midpoint rounding leaves the right split identical to its
        // parent while the chord/polygon error still exceeds its allowance.
        assertFailure(path, equals: .numericalLimit)
        XCTAssertTrue(path.trimmedPath(from: 0.25, to: 0.75).isEmpty)
    }

    private func assertQuadratic(
        _ path: Path, start expectedStart: Point, control expectedControl: Point, end expectedEnd: Point,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        guard path.elements.count == 2,
            case .moveTo(let start) = path.elements[0],
            case .quadraticCurveTo(let control, let end) = path.elements[1]
        else {
            XCTFail("Expected one selected quadratic and its move", file: file, line: line)
            return
        }
        assertPoint(start, expectedStart, file: file, line: line)
        assertPoint(control, expectedControl, file: file, line: line)
        assertPoint(end, expectedEnd, file: file, line: line)
    }

    private func assertPoint(
        _ actual: Point, _ expected: Point, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(actual.x, expected.x, accuracy: 1e-5, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: 1e-5, file: file, line: line)
    }

    private func assertFailure(
        _ path: Path, equals expected: PathTrimming.Failure, limits: PathTrimming.Limits = PathTrimming.Limits(),
        file: StaticString = #filePath, line: UInt = #line
    ) {
        switch PathTrimming.checkedTrim(path, from: 0.25, to: 0.75, limits: limits) {
        case .failure(let actual): XCTAssertEqual(actual, expected, file: file, line: line)
        case .success: XCTFail("Expected the entire partial selection to be rejected", file: file, line: line)
        }
    }
}
