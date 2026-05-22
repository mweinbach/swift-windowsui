import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

/// Pins the rotated-quad rasterization contract. The CPU rasterizer
/// must:
///   1. Render an axis-aligned quad (rotation == 0) byte-identical to
///      pre-rotation behaviour. Locked by VisualBaselineRegressionTests
///      already; this suite double-checks via direct pixel sampling.
///   2. Render a rotated quad with the same fill color landing at
///      rotated coordinates, with empty pixels at the unrotated
///      footprint.
final class RotatedQuadRasterTests: XCTestCase {

    private func makeScene(
        rotation: Float,
        color: Color = Color(red: 1, green: 1, blue: 1, alpha: 1)
    ) -> BitmapSurface {
        var scene = GPUIScene(clearColor: Color(red: 0, green: 0, blue: 0, alpha: 1))
        scene.addQuad(
            QuadPrimitive(
                x: 40, y: 40, width: 20, height: 20,
                cornerRadius: 0,
                startR: color.red, startG: color.green, startB: color.blue, startA: color.alpha,
                endR: color.red, endG: color.green, endB: color.blue, endA: color.alpha,
                gradientAxis: 0,
                clipX: 0, clipY: 0, clipWidth: 100, clipHeight: 100,
                rotationRadians: rotation
            )
        )
        scene.finish()
        return GPUIRawSceneRasterizer.rasterize(scene, size: IntSize(width: 100, height: 100))
    }

    func testZeroRotationFillsAxisAlignedSquareAtKnownCoordinates() {
        let bitmap = makeScene(rotation: 0)
        // Centre of the 20×20 square at (40,40)..(60,60).
        let centre = bitmap.pixelColor(atX: 50, y: 50)
        XCTAssertEqual(centre?.red ?? 0, 1.0, accuracy: 0.01)
        XCTAssertEqual(centre?.green ?? 0, 1.0, accuracy: 0.01)
        XCTAssertEqual(centre?.blue ?? 0, 1.0, accuracy: 0.01)

        // Pixel just outside the square — should be clear (black).
        let outside = bitmap.pixelColor(atX: 30, y: 50)
        XCTAssertEqual(outside?.red ?? 1, 0.0, accuracy: 0.05)
    }

    func test45DegreeRotationProducesDiamondFootprint() {
        let rot45 = Float.pi / 4  // 45° clockwise (positive in screen-space Y-down)
        let bitmap = makeScene(rotation: rot45)
        let cx = 50
        let cy = 50

        // Centre still inside the rotated square.
        let centre = bitmap.pixelColor(atX: cx, y: cy)
        XCTAssertEqual(
            centre?.red ?? 0, 1.0, accuracy: 0.05,
            "Quad centre is rotation-invariant and must remain filled")

        // For a 20×20 square rotated 45° around its centre, the rotated
        // footprint is a diamond with cardinal corners at distance
        // 10·√2 ≈ 14.14 from the centre. Diamond edges follow
        // |dx| + |dy| ≤ 14.14.
        //
        // Sample (50, 50+12) — cardinal-axis pixel at distance 12 from
        // centre. INSIDE the rotated diamond, OUTSIDE the unrotated
        // square (whose half-extent was 10). This pixel must be filled
        // ONLY because of rotation.
        let cardinalInside = bitmap.pixelColor(atX: cx, y: cy + 12)
        XCTAssertGreaterThan(
            (cardinalInside?.red ?? 0), 0.5,
            "Pixel at cardinal corner of rotated diamond must be filled"
        )

        // Diamond is symmetric under cardinal-axis reflection.
        let cardinalLeft = bitmap.pixelColor(atX: cx - 12, y: cy)
        XCTAssertGreaterThan(
            (cardinalLeft?.red ?? 0), 0.5,
            "Rotated diamond must be symmetric across cardinal axes"
        )

        // Pixels on the diagonal y = x at distance 12 from centre are
        // OUTSIDE the diamond (|12|+|12| = 24 > 14.14). The unrotated
        // square WOULD have filled this point — so it must now be empty.
        let diagonalOutside = bitmap.pixelColor(atX: cx + 9, y: cy + 9)
        XCTAssertLessThan(
            (diagonalOutside?.red ?? 1), 0.5,
            "Rotation must remove fill from points outside the diamond"
        )

        // Far outside both the original square and the rotated diamond
        // must remain background.
        let farOutside = bitmap.pixelColor(atX: 5, y: 5)
        XCTAssertEqual(farOutside?.red ?? 1, 0.0, accuracy: 0.05)
    }

    func test90DegreeRotationProducesIdenticalSquareFootprint() {
        // A 90° rotation of a square (equal width/height) should
        // produce the same pixel set as the unrotated square.
        let unrotated = makeScene(rotation: 0)
        let rotated = makeScene(rotation: .pi / 2)
        // Compare a handful of points inside and outside the
        // (identical) footprint.
        for (x, y) in [(50, 50), (45, 55), (55, 45), (30, 50), (50, 70)] {
            let u = unrotated.pixelColor(atX: x, y: y)
            let r = rotated.pixelColor(atX: x, y: y)
            XCTAssertEqual(
                u?.red ?? 0, r?.red ?? 0, accuracy: 0.05,
                "90° rotation of a square must yield identical footprint at (\(x), \(y))"
            )
        }
    }
}
