import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI

/// Cost bounds for the path tessellator.
///
/// The scanline fill emits one quad per row and derived its row range purely
/// from vertex `y`, so a chart with a single outlier vertex produced millions of
/// `QuadPrimitive`s per frame that the clip then discarded — and a finite but
/// huge coordinate (`1e300`, trivially produced by `1/ε` arithmetic in app code)
/// trapped outright at `Int(_:)`. App-supplied numbers must bound the *shape*,
/// never the frame's cost.
final class PathTessellationBudgetTests: XCTestCase {

    private func triangle(
        _ v0: Point, _ v1: Point, _ v2: Point, clip: Rect?
    ) -> PathPrimitive {
        PathPrimitive(
            elements: [.moveTo(v0), .lineTo(v1), .lineTo(v2), .close],
            bounds: clip ?? Rect(x: 0, y: 0, width: 100, height: 100),
            fillColor: Color(red: 1, green: 0, blue: 0, alpha: 1),
            clipBounds: clip
        )
    }

    func testOutlierTriangleIsBoundedByItsClip() {
        let clip = Rect(x: 0, y: 0, width: 100, height: 100)
        let path = triangle(
            Point(x: 10, y: -1_000_000),
            Point(x: 90, y: 1_000_000),
            Point(x: 50, y: 20),
            clip: clip
        )

        let result = PathToQuadTessellator.tessellateMixed(path)
        let quadCount = result?.quads.count ?? 0
        XCTAssertLessThanOrEqual(
            quadCount, 200,
            "only rows the clip can show are worth a quad; unclipped this emitted ~2 M strips")
    }

    func testUnclippedOutlierTriangleFallsBackToCPU() {
        let path = triangle(
            Point(x: 10, y: -1_000_000),
            Point(x: 90, y: 1_000_000),
            Point(x: 50, y: 20),
            clip: nil
        )

        XCTAssertNil(
            PathToQuadTessellator.tessellateMixed(path),
            "past the row budget the path belongs on the CPU rasterizer, which is bounded by the surface")
    }

    func testHugeFiniteCoordinateDoesNotTrap() {
        let path = triangle(
            Point(x: 0, y: 0),
            Point(x: 50, y: 1e300),
            Point(x: 100, y: 10),
            clip: nil
        )

        XCTAssertNil(
            PathToQuadTessellator.tessellateMixed(path),
            "`Int(1e300)` is a process kill, not an error — the row count must saturate instead")
    }

    func testOrdinaryTriangleStillPromotesToQuads() {
        let clip = Rect(x: 0, y: 0, width: 100, height: 100)
        let path = triangle(
            Point(x: 10, y: 10),
            Point(x: 90, y: 10),
            Point(x: 50, y: 60),
            clip: clip
        )

        let result = PathToQuadTessellator.tessellateMixed(path)
        XCTAssertNotNil(result, "clipping the row range must not change ordinary tessellation")
        XCTAssertGreaterThan(result?.quads.count ?? 0, 10)
        XCTAssertNil(result?.residualPath)
    }

    func testLargeConcavePolygonFallsBackInsteadOfEarClipping() {
        // Ear clipping is O(n³); a long area-chart boundary is exactly the shape
        // that used to spend ~10¹¹ containment tests inside one frame.
        var elements: [PathElement] = [.moveTo(Point(x: 0, y: 100))]
        for index in 0..<600 {
            let x = Double(index) * 0.5
            let y = index.isMultiple(of: 2) ? 20.0 : 80.0
            elements.append(.lineTo(Point(x: x, y: y)))
        }
        elements.append(.lineTo(Point(x: 300, y: 100)))
        elements.append(.close)

        let path = PathPrimitive(
            elements: elements,
            bounds: Rect(x: 0, y: 0, width: 300, height: 100),
            fillColor: Color(red: 0, green: 1, blue: 0, alpha: 1),
            clipBounds: Rect(x: 0, y: 0, width: 300, height: 100)
        )

        XCTAssertNil(
            PathToQuadTessellator.tessellateMixed(path),
            "past the vertex budget the polygon goes to the CPU rasterizer")
    }
}

/// Dash-walk granularity. `StrokeStyle(dashPattern: [0.001, 0.001])` on a long
/// perimeter used to emit hundreds of thousands of segments per border per
/// frame, because the walk advanced by the pattern entry with only a 0.01 floor.
final class BorderDashBudgetTests: XCTestCase {

    func testSubPixelDashPatternIsBounded() {
        let segments = BorderSegments.dashedSegments(
            frame: Rect(x: 0, y: 0, width: 1000, height: 1000),
            width: 1,
            cornerRadius: 0,
            strokeStyle: StrokeStyle(lineWidth: 1, dashPattern: [0.001, 0.001])
        )

        let count = try? XCTUnwrap(segments).count
        guard let count else { return }
        XCTAssertLessThanOrEqual(
            count, 8_192,
            "dash granularity below what the perimeter can resolve must degrade the dashes, not the frame")
        XCTAssertGreaterThan(count, 0, "the border must still be drawn")
    }

    func testOrdinaryDashPatternIsUnchanged() {
        let segments = BorderSegments.dashedSegments(
            frame: Rect(x: 0, y: 0, width: 40, height: 40),
            width: 1,
            cornerRadius: 0,
            strokeStyle: StrokeStyle(lineWidth: 1, dashPattern: [4, 4])
        )

        let unwrapped = try? XCTUnwrap(segments)
        guard let unwrapped else { return }
        // 160 pt perimeter, 8 pt pattern -> 20 dashes, each landing on one edge
        // or spanning a corner (the walk splits those across regions).
        XCTAssertGreaterThanOrEqual(unwrapped.count, 20)
        XCTAssertLessThanOrEqual(unwrapped.count, 30)
    }
}
