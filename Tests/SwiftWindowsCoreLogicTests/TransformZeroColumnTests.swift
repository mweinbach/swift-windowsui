import SwiftWindowsCore
import XCTest

/// Literal matrices and points exercise the surviving second basis vector.
/// These controls do not claim to cover every rank-one decomposition.
final class TransformZeroColumnTests: XCTestCase {
    func testPositiveYColumnPreservesExactScaleMatrixAndPoint() {
        let matrix = AffineMatrix(a: 0, b: 0, c: 0, d: 1, tx: 0, ty: 0)
        let transform = Transform2D(fromMatrix: matrix)

        XCTAssertEqual(transform, .scale(x: 0, y: 1))
        XCTAssertEqual(transform.matrix, matrix)
        XCTAssertEqual(transform.applying(to: Point(x: 7, y: 11)), Point(x: 0, y: 11))
        XCTAssertNil(transform.inverseOrNil())
    }

    func testNegativeYColumnPreservesItsSignAndTranslation() {
        let matrix = AffineMatrix(a: 0, b: 0, c: 0, d: -2, tx: 5, ty: -6)
        let transform = Transform2D(fromMatrix: matrix)

        XCTAssertEqual(transform, Transform2D(translationX: 5, translationY: -6, scaleX: 0, scaleY: -2))
        XCTAssertEqual(transform.matrix, matrix)
        XCTAssertEqual(transform.applying(to: Point(x: 7, y: 11)), Point(x: 5, y: -28))
        XCTAssertEqual(transform.applying(to: Point(x: -19, y: 11)), Point(x: 5, y: -28))
        XCTAssertNil(transform.inverseOrNil())
    }

    func testRotatedSurvivingColumnPreservesAllQuadrants() {
        let cases: [(c: Double, d: Double, scaleY: Double, point: Point)] = [
            (3, 4, 5, Point(x: 38, y: 38)),
            (3, -4, -5, Point(x: 38, y: -50)),
            (-3, 4, 5, Point(x: -28, y: 38)),
            (-3, -4, -5, Point(x: -28, y: -50)),
        ]
        for value in cases {
            let matrix = AffineMatrix(a: 0, b: 0, c: value.c, d: value.d, tx: 5, ty: -6)
            let transform = Transform2D(fromMatrix: matrix)

            XCTAssertEqual(transform.scaleX, 0)
            XCTAssertEqual(transform.scaleY, value.scaleY)
            XCTAssertEqual(transform.skewX, 0)
            XCTAssertEqual(transform.skewY, 0)
            XCTAssertLessThanOrEqual(abs(transform.rotation), Double.pi / 2)
            assertMatrix(transform.matrix, equals: matrix)
            assertPoint(transform.applying(to: Point(x: 7, y: 11)), equals: value.point)
            assertPoint(transform.applying(to: Point(x: -19, y: 11)), equals: value.point)
            XCTAssertNil(transform.inverseOrNil())
        }
    }

    func testHorizontalSurvivingColumnPreservesBothQuarterTurns() {
        let cases: [(c: Double, rotation: Double, point: Point)] = [
            (5, -Double.pi / 2, Point(x: 60, y: -6)),
            (-5, Double.pi / 2, Point(x: -50, y: -6)),
        ]
        for value in cases {
            let matrix = AffineMatrix(a: 0, b: 0, c: value.c, d: 0, tx: 5, ty: -6)
            let transform = Transform2D(fromMatrix: matrix)

            XCTAssertEqual(transform.scaleX, 0)
            XCTAssertEqual(transform.scaleY, 5)
            XCTAssertEqual(transform.rotation, value.rotation, accuracy: 1e-12)
            assertMatrix(transform.matrix, equals: matrix)
            assertPoint(transform.applying(to: Point(x: 7, y: 11)), equals: value.point)
            XCTAssertNil(transform.inverseOrNil())
        }
    }

    func testZeroLinearMatrixPreservesOnlyItsTranslation() {
        let matrix = AffineMatrix(a: 0, b: 0, c: 0, d: 0, tx: 5, ty: -6)
        let transform = Transform2D(fromMatrix: matrix)

        XCTAssertEqual(transform, Transform2D(translationX: 5, translationY: -6, scaleX: 0, scaleY: 0))
        XCTAssertEqual(transform.matrix, matrix)
        XCTAssertEqual(transform.applying(to: Point(x: 7, y: 11)), Point(x: 5, y: -6))
        XCTAssertEqual(transform.applying(to: .zero), Point(x: 5, y: -6))
        XCTAssertNil(transform.inverseOrNil())
    }

    func testIdentityCompositionPreservesAuthoredZeroXScale() {
        let authored = Transform2D.scale(x: 0, y: 1)
        let matrix = AffineMatrix(a: 0, b: 0, c: 0, d: 1, tx: 0, ty: 0)
        let composed = [
            Transform2D.identity.concatenating(authored),
            authored.concatenating(Transform2D.identity),
        ]
        for transform in composed {
            XCTAssertEqual(transform, authored)
            XCTAssertEqual(transform.matrix, matrix)
            XCTAssertEqual(transform.applying(to: Point(x: 7, y: 11)), Point(x: 0, y: 11))
            XCTAssertNil(transform.inverseOrNil())
        }
    }

    func testCenteredCompositionRetainsUncollapsedCoordinates() {
        let transform = Transform2D.translation(x: -10, y: -20)
            .concatenating(.scale(x: 0, y: 1))
            .concatenating(.translation(x: 10, y: 20))
        let matrix = AffineMatrix(a: 0, b: 0, c: 0, d: 1, tx: 10, ty: 0)

        XCTAssertEqual(transform, Transform2D(translationX: 10, scaleX: 0, scaleY: 1))
        XCTAssertEqual(transform.matrix, matrix)
        XCTAssertEqual(transform.applying(to: Point(x: 7, y: 11)), Point(x: 10, y: 11))
        XCTAssertEqual(transform.applying(to: Point(x: 100, y: -7)), Point(x: 10, y: -7))
        XCTAssertNil(transform.inverseOrNil())
    }

    func testTinySurvivingColumnDoesNotUnderflowDuringNormCalculation() {
        let matrix = AffineMatrix(a: 0, b: 0, c: 3e-200, d: 4e-200, tx: 0, ty: 0)
        let transform = Transform2D(fromMatrix: matrix)

        // Absolute tolerances here are smaller than each expected coefficient;
        // an all-zero answer cannot pass as a small rounding difference.
        XCTAssertGreaterThan(transform.scaleY, 0)
        XCTAssertEqual(transform.scaleY, 5e-200, accuracy: 5e-212)
        assertMatrix(transform.matrix, equals: matrix, accuracy: 4e-212)
        assertPoint(
            transform.applying(to: Point(x: 7, y: 1)), equals: Point(x: 3e-200, y: 4e-200),
            accuracy: 4e-212)
        XCTAssertNil(transform.inverseOrNil())
    }

    func testLargeFiniteColumnDoesNotOverflowDuringNormCalculation() {
        let matrix = AffineMatrix(a: 0, b: 0, c: 3e200, d: 4e200, tx: 0, ty: 0)
        let transform = Transform2D(fromMatrix: matrix)

        XCTAssertTrue(transform.scaleY.isFinite)
        XCTAssertEqual(transform.scaleY, 5e200, accuracy: 5e188)
        assertMatrix(transform.matrix, equals: matrix, accuracy: 4e188)
        assertPoint(
            transform.applying(to: Point(x: 7, y: 1)), equals: Point(x: 3e200, y: 4e200),
            accuracy: 4e188)
        XCTAssertNil(transform.inverseOrNil())
    }

    func testTinyRotationRetainsTheSmallNonzeroCoefficient() {
        let matrix = AffineMatrix(a: 0, b: 0, c: 1, d: 1e14, tx: 0, ty: 0)
        let transform = Transform2D(fromMatrix: matrix)
        let actual = transform.matrix
        let point = transform.applying(to: Point(x: 7, y: 1))

        // Check c separately: a tolerance scaled to d would hide its loss.
        XCTAssertNotEqual(transform.rotation, 0)
        XCTAssertEqual(actual.a, 0)
        XCTAssertEqual(actual.b, 0)
        XCTAssertEqual(actual.c, 1, accuracy: 1e-12)
        XCTAssertEqual(actual.d, 1e14, accuracy: 1)
        XCTAssertEqual(actual.tx, 0)
        XCTAssertEqual(actual.ty, 0)
        XCTAssertEqual(point.x, 1, accuracy: 1e-12)
        XCTAssertEqual(point.y, 1e14, accuracy: 1)
        XCTAssertNil(transform.inverseOrNil())
    }

    func testIdentityFullRankAndReflectedMatricesRetainLiteralPointMappings() {
        let identity = Transform2D(fromMatrix: .identity)
        XCTAssertEqual(identity, .identity)
        XCTAssertEqual(identity.matrix, .identity)
        XCTAssertEqual(identity.applying(to: Point(x: 7, y: 11)), Point(x: 7, y: 11))

        let cases: [(matrix: AffineMatrix, point: Point)] = [
            (AffineMatrix(a: 2, b: 1, c: 3, d: 4, tx: 5, ty: -6), Point(x: 52, y: 45)),
            (AffineMatrix(a: -2, b: -1, c: 3, d: 4, tx: 5, ty: -6), Point(x: 24, y: 31)),
        ]
        for value in cases {
            let transform = Transform2D(fromMatrix: value.matrix)
            assertMatrix(transform.matrix, equals: value.matrix)
            assertPoint(transform.applying(to: Point(x: 7, y: 11)), equals: value.point)
            XCTAssertNotNil(transform.inverseOrNil())
        }
    }

    func testShearControlRetainsSecondColumnAndPoints() {
        let matrix = AffineMatrix(a: 1, b: 0, c: 2, d: 1, tx: 5, ty: -6)
        let transform = Transform2D(fromMatrix: matrix)

        XCTAssertEqual(transform.scaleX, 1)
        XCTAssertEqual(transform.scaleY, 1)
        XCTAssertEqual(transform.rotation, 0)
        assertMatrix(transform.matrix, equals: matrix)
        assertPoint(transform.applying(to: Point(x: 7, y: 11)), equals: Point(x: 34, y: 5))
        XCTAssertNotNil(transform.inverseOrNil())
    }

    func testFirstColumnOnlyRankOneRemainsRepresentable() {
        let matrix = AffineMatrix(a: 3, b: 4, c: 0, d: 0, tx: 5, ty: -6)
        let transform = Transform2D(fromMatrix: matrix)

        XCTAssertEqual(transform.scaleX, 5)
        XCTAssertEqual(transform.scaleY, 0)
        assertMatrix(transform.matrix, equals: matrix)
        assertPoint(transform.applying(to: Point(x: 7, y: 11)), equals: Point(x: 26, y: 22))
        XCTAssertNil(transform.inverseOrNil())
    }

    private func assertMatrix(
        _ actual: AffineMatrix, equals expected: AffineMatrix, accuracy: Double = 1e-12,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(actual.a, expected.a, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.b, expected.b, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.c, expected.c, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.d, expected.d, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.tx, expected.tx, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.ty, expected.ty, accuracy: accuracy, file: file, line: line)
    }

    private func assertPoint(
        _ actual: Point, equals expected: Point, accuracy: Double = 1e-12,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(actual.x, expected.x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: accuracy, file: file, line: line)
    }
}
