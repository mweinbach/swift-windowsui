import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsRendererD3D11

/// Tests for the D3D11 path render cache infrastructure. These cover the
/// translation-invariance of the cache key and structural invariants on a
/// fresh renderer. End-to-end cache-hit verification needs a real device, so
/// the live cache behaviour is exercised by integration tests when D3D11 is
/// available.
final class D3D11PathCacheTests: XCTestCase {
    private func makePath(at origin: Point) -> PathPrimitive {
        let elements: [PathElement] = [
            .moveTo(Point(x: origin.x + 0, y: origin.y + 0)),
            .lineTo(Point(x: origin.x + 30, y: origin.y + 0)),
            .lineTo(Point(x: origin.x + 30, y: origin.y + 20)),
            .lineTo(Point(x: origin.x + 0, y: origin.y + 20)),
            .close,
        ]
        return PathPrimitive(
            elements: elements,
            bounds: Rect(origin: origin, size: Size(width: 30, height: 20)),
            fillColor: Color(red: 1, green: 0, blue: 0, alpha: 1),
            strokeColor: .clear,
            lineWidth: 0
        )
    }

    func testTranslatedPathsNormalizeToIdenticalKeys() {
        let a = makePath(at: Point(x: 12, y: 7))
        let b = makePath(at: Point(x: 200, y: 90))
        let aNorm = a.translated(by: Point(x: -a.bounds.origin.x, y: -a.bounds.origin.y))
        let bNorm = b.translated(by: Point(x: -b.bounds.origin.x, y: -b.bounds.origin.y))
        XCTAssertEqual(
            aNorm,
            bNorm,
            "Path translation invariance: two paths with the same shape at different offsets must hash to the same normalized key"
        )
        XCTAssertEqual(aNorm.bounds.origin.x, 0, accuracy: 0.0001)
        XCTAssertEqual(aNorm.bounds.origin.y, 0, accuracy: 0.0001)
    }

    func testPathsDifferingInShapeStayDistinct() {
        var a = makePath(at: .zero)
        let b = makePath(at: .zero)
        // Modify one element so the shape genuinely changes.
        a.elements[1] = .lineTo(Point(x: 50, y: 0))
        XCTAssertNotEqual(a, b)
    }

    func testPathsDifferingInColorStayDistinct() {
        var a = makePath(at: .zero)
        let b = makePath(at: .zero)
        a.fillColor = Color(red: 0, green: 1, blue: 0, alpha: 1)
        XCTAssertNotEqual(a, b)
    }

    func testFreshRendererHasEmptyPathCache() async {
        await MainActor.run {
            let renderer = D3D11BatchRenderer()
            XCTAssertEqual(renderer.pathCacheEntryCountForTesting, 0)
            XCTAssertEqual(renderer.pathCacheHits, 0)
            XCTAssertEqual(renderer.pathCacheMisses, 0)
        }
    }
}
