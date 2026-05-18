import XCTest

@testable import SwiftWindowsCore

final class GeometryTests: XCTestCase {
    func testRectIntersectionReturnsOverlapOnly() {
        let first = Rect(x: 0, y: 0, width: 10, height: 10)
        let second = Rect(x: 5, y: 4, width: 10, height: 10)

        XCTAssertEqual(first.intersected(with: second), Rect(x: 5, y: 4, width: 5, height: 6))
        XCTAssertNil(first.intersected(with: Rect(x: 10, y: 0, width: 4, height: 4)))
    }

    func testRectContainsAndInsetClampToValidBounds() {
        let rect = Rect(x: 10, y: 20, width: 30, height: 40)

        XCTAssertTrue(rect.contains(Point(x: 10, y: 20)))
        XCTAssertFalse(rect.contains(Point(x: 40, y: 20)))
        XCTAssertFalse(rect.contains(Point(x: 10, y: 60)))
        XCTAssertEqual(
            rect.inset(by: EdgeInsets(top: 5, leading: 8, bottom: 50, trailing: 40)),
            Rect(x: 18, y: 25, width: 0, height: 0)
        )
    }

    func testColorInterpolationClampsProgress() {
        let start = Color(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4)
        let end = Color(red: 0.9, green: 0.8, blue: 0.7, alpha: 0.6)
        let midpoint = start.interpolated(to: end, progress: 0.5)

        XCTAssertEqual(start.interpolated(to: end, progress: -1), start)
        XCTAssertEqual(start.interpolated(to: end, progress: 2), end)
        XCTAssertEqual(midpoint.red, 0.5, accuracy: 0.0001)
        XCTAssertEqual(midpoint.green, 0.5, accuracy: 0.0001)
        XCTAssertEqual(midpoint.blue, 0.5, accuracy: 0.0001)
        XCTAssertEqual(midpoint.alpha, 0.5, accuracy: 0.0001)
    }

    // MARK: - Path.contains

    func testPathContainsInsideAxisAlignedRect() {
        var path = Path()
        path.addRect(Rect(x: 10, y: 20, width: 30, height: 40))
        XCTAssertTrue(path.contains(Point(x: 25, y: 40)))
    }

    func testPathContainsOutsideAxisAlignedRect() {
        var path = Path()
        path.addRect(Rect(x: 10, y: 20, width: 30, height: 40))
        XCTAssertFalse(path.contains(Point(x: 5, y: 5)))
        XCTAssertFalse(path.contains(Point(x: 50, y: 40)))
        XCTAssertFalse(path.contains(Point(x: 25, y: 80)))
    }

    func testPathContainsConcavePolygon() {
        // Plus-sign shape: 12 vertices, classic concave test.
        var path = Path()
        path.moveTo(Point(x: 30, y: 10))
        path.lineTo(Point(x: 50, y: 10))
        path.lineTo(Point(x: 50, y: 30))
        path.lineTo(Point(x: 70, y: 30))
        path.lineTo(Point(x: 70, y: 50))
        path.lineTo(Point(x: 50, y: 50))
        path.lineTo(Point(x: 50, y: 70))
        path.lineTo(Point(x: 30, y: 70))
        path.lineTo(Point(x: 30, y: 50))
        path.lineTo(Point(x: 10, y: 50))
        path.lineTo(Point(x: 10, y: 30))
        path.lineTo(Point(x: 30, y: 30))
        path.close()

        XCTAssertTrue(path.contains(Point(x: 40, y: 40)))  // center of cross
        XCTAssertTrue(path.contains(Point(x: 40, y: 20)))  // upper arm
        XCTAssertTrue(path.contains(Point(x: 60, y: 40)))  // right arm
        XCTAssertFalse(path.contains(Point(x: 20, y: 20)))  // top-left empty corner
        XCTAssertFalse(path.contains(Point(x: 60, y: 60)))  // bottom-right empty corner
    }

    func testPathContainsEvenOddHonoursNestedHole() {
        var path = Path()
        path.addRect(Rect(x: 0, y: 0, width: 100, height: 100))
        // Inner counter-rect carving a hole.
        path.moveTo(Point(x: 30, y: 30))
        path.lineTo(Point(x: 70, y: 30))
        path.lineTo(Point(x: 70, y: 70))
        path.lineTo(Point(x: 30, y: 70))
        path.close()

        // Even-odd: the inner rect overlaps the outer, so points inside it
        // count as "outside" because they cross two edges to the right.
        XCTAssertFalse(path.contains(Point(x: 50, y: 50), eoFill: true))
        XCTAssertTrue(path.contains(Point(x: 10, y: 50), eoFill: true))
    }

    func testPathContainsCircleApproximatesInteriorAndExterior() {
        var path = Path()
        path.addEllipse(in: Rect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertTrue(path.contains(Point(x: 50, y: 50)))  // dead center
        XCTAssertTrue(path.contains(Point(x: 70, y: 50)))  // inside right
        XCTAssertFalse(path.contains(Point(x: 5, y: 5)))  // outside top-left corner
        XCTAssertFalse(path.contains(Point(x: 150, y: 150)))  // far outside
    }
}
