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
}
