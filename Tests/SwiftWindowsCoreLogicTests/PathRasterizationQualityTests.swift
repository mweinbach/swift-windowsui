import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

/// Path fill and stroke quality.
///
/// This is not a fallback-only concern: `D3D11BatchRenderer`'s path
/// texture cache calls `GPUIRawSceneRasterizer.rasterizePath` and uploads
/// the result, so whatever this suite pins *is* the shipping appearance of
/// `Canvas`, `Shape` strokes, chart lines and the SF-symbol vector
/// fallback.
@MainActor
final class PathRasterizationQualityTests: XCTestCase {

    private static let surface = IntSize(width: 64, height: 64)

    private func render(_ path: PathPrimitive) -> BitmapSurface {
        var scene = GPUIScene(clearColor: .black)
        scene.addPath(path, toLayer: 0)
        scene.finish()
        return GPUIRawSceneRasterizer.rasterize(scene, size: Self.surface)
    }

    private func green(_ bitmap: BitmapSurface, x: Int, y: Int) -> Int {
        Int(bitmap.pixels[y * Int(bitmap.bytesPerRow) + x * 4 + 1])
    }

    private func red(_ bitmap: BitmapSurface, x: Int, y: Int) -> Int {
        Int(bitmap.pixels[y * Int(bitmap.bytesPerRow) + x * 4 + 2])
    }

    private static let fill = Color(red: 0, green: 1, blue: 0, alpha: 1)

    // MARK: - Implicit closure

    /// SwiftUI's fill semantics close every subpath. The rasterizer only
    /// closed on an explicit `.close`, so most scanlines of an unclosed
    /// triangle produced a single crossing — which the old pairing loop
    /// discarded, making the shape invisible.
    func testUnclosedSubpathFillsTheSameAsAClosedOne() async {
        let points: [PathElement] = [
            .moveTo(Point(x: 12, y: 50)),
            .lineTo(Point(x: 32, y: 12)),
            .lineTo(Point(x: 52, y: 50)),
        ]
        let bounds = Rect(x: 12, y: 12, width: 40, height: 38)
        let open = render(PathPrimitive(elements: points, bounds: bounds, fillColor: Self.fill))
        let closed = render(PathPrimitive(elements: points + [.close], bounds: bounds, fillColor: Self.fill))

        XCTAssertGreaterThan(green(open, x: 32, y: 40), 200, "an unclosed triangle must still fill")
        XCTAssertEqual(open.pixels, closed.pixels, "closing a subpath explicitly may not change the fill")
    }

    /// Two subpaths, only the second closed: the first must still fill,
    /// which is what the per-subpath implicit close buys over closing the
    /// whole element list once.
    func testEachSubpathClosesIndependently() async {
        let bitmap = render(
            PathPrimitive(
                elements: [
                    .moveTo(Point(x: 6, y: 6)),
                    .lineTo(Point(x: 26, y: 6)),
                    .lineTo(Point(x: 26, y: 26)),
                    .moveTo(Point(x: 38, y: 38)),
                    .lineTo(Point(x: 58, y: 38)),
                    .lineTo(Point(x: 58, y: 58)),
                    .close,
                ],
                bounds: Rect(x: 6, y: 6, width: 52, height: 52),
                fillColor: Self.fill))

        XCTAssertGreaterThan(green(bitmap, x: 22, y: 12), 200, "the unclosed first subpath fills")
        XCTAssertGreaterThan(green(bitmap, x: 54, y: 44), 200, "the closed second subpath fills")
        XCTAssertLessThan(green(bitmap, x: 12, y: 22), 40, "and neither leaks outside itself")
    }

    // MARK: - Fill rule

    /// Non-zero winding, matching SwiftUI's default and this stack's own
    /// `Path.contains(_:eoFill: false)`. Under the old even-odd pairing a
    /// self-overlapping shape filled with holes its own hit testing called
    /// solid.
    func testSelfOverlappingShapeFillsSolidUnderNonZeroWinding() async {
        // Two concentric squares wound the same way: even-odd punches the
        // inner one out, non-zero keeps it filled.
        let bitmap = render(
            PathPrimitive(
                elements: [
                    .moveTo(Point(x: 8, y: 8)),
                    .lineTo(Point(x: 56, y: 8)),
                    .lineTo(Point(x: 56, y: 56)),
                    .lineTo(Point(x: 8, y: 56)),
                    .close,
                    .moveTo(Point(x: 20, y: 20)),
                    .lineTo(Point(x: 44, y: 20)),
                    .lineTo(Point(x: 44, y: 44)),
                    .lineTo(Point(x: 20, y: 44)),
                    .close,
                ],
                bounds: Rect(x: 8, y: 8, width: 48, height: 48),
                fillColor: Self.fill))

        XCTAssertGreaterThan(green(bitmap, x: 32, y: 32), 200, "the overlap stays filled under non-zero")
        XCTAssertGreaterThan(green(bitmap, x: 12, y: 32), 200)
    }

    // MARK: - Antialiasing

    /// A diagonal edge produces fractional coverage. The rasterizer used
    /// to blend the fill colour at full strength across integer spans, so
    /// every curve and every diagonal was a staircase.
    func testDiagonalEdgeHasFractionalCoverage() async {
        let bitmap = render(
            PathPrimitive(
                elements: [
                    .moveTo(Point(x: 8, y: 8)),
                    .lineTo(Point(x: 56, y: 56)),
                    .lineTo(Point(x: 8, y: 56)),
                    .close,
                ],
                bounds: Rect(x: 8, y: 8, width: 48, height: 48),
                fillColor: Self.fill))

        var fractional = 0
        for y in 8..<56 {
            for x in 8..<56 {
                let value = green(bitmap, x: x, y: y)
                if value > 20, value < 235 { fractional += 1 }
            }
        }
        XCTAssertGreaterThan(fractional, 20, "the hypotenuse must be antialiased, not stepped")
    }

    // MARK: - Stroke

    /// One blend per pixel per path. Each flattened segment used to be
    /// scanline-filled as its own quad, and the spans overlapped at every
    /// shared vertex, so a translucent polyline came out blotchy and
    /// progressively darker.
    func testTranslucentPolylineNeverExceedsItsSingleSegmentAlpha() async {
        let stroke = Color(red: 1, green: 0, blue: 0, alpha: 0.4)
        let single = render(
            PathPrimitive(
                elements: [.moveTo(Point(x: 8, y: 32)), .lineTo(Point(x: 24, y: 32))],
                bounds: Rect(x: 6, y: 28, width: 52, height: 10),
                strokeColor: stroke, lineWidth: 4))
        let polyline = render(
            PathPrimitive(
                elements: [
                    .moveTo(Point(x: 8, y: 32)),
                    .lineTo(Point(x: 24, y: 32)),
                    .lineTo(Point(x: 40, y: 32)),
                    .lineTo(Point(x: 56, y: 32)),
                ],
                bounds: Rect(x: 6, y: 28, width: 52, height: 10),
                strokeColor: stroke, lineWidth: 4))

        let singleMax = (28..<38).map { red(single, x: 16, y: $0) }.max() ?? 0
        XCTAssertGreaterThan(singleMax, 60, "the fixture must actually draw something")
        for x in 9..<55 {
            for y in 28..<38 {
                XCTAssertLessThanOrEqual(
                    red(polyline, x: x, y: y), singleMax + 1,
                    "no pixel of a 3-segment polyline may be darker than one segment's own alpha "
                        + "(double blending at (\(x), \(y)))")
            }
        }
    }

    /// A thick polyline turning a corner has no wedge missing at the
    /// joint. Independent segment quads left one at every vertex.
    func testThickCornerHasNoGapAtTheJoin() async {
        let bitmap = render(
            PathPrimitive(
                elements: [
                    .moveTo(Point(x: 10, y: 12)),
                    .lineTo(Point(x: 40, y: 12)),
                    .lineTo(Point(x: 40, y: 52)),
                ],
                bounds: Rect(x: 4, y: 6, width: 44, height: 52),
                strokeColor: Color(red: 1, green: 0, blue: 0, alpha: 1), lineWidth: 10))

        // (43, 9) is outside both segment quads — past x = 40 and above
        // y = 12 — and inside the round join's disc, so it is ink only if
        // the join exists.
        XCTAssertGreaterThan(red(bitmap, x: 43, y: 9), 200, "the join must fill the outer corner")
        // Well outside the stroke stays empty.
        XCTAssertLessThan(red(bitmap, x: 47, y: 6), 40)
    }

    /// Stroking does *not* close an open subpath, even though filling
    /// does — the same asymmetry SwiftUI has.
    func testStrokeDoesNotCloseAnOpenSubpath() async {
        let elements: [PathElement] = [
            .moveTo(Point(x: 12, y: 12)),
            .lineTo(Point(x: 52, y: 12)),
            .lineTo(Point(x: 52, y: 52)),
        ]
        let bounds = Rect(x: 8, y: 8, width: 48, height: 48)
        let stroke = Color(red: 1, green: 0, blue: 0, alpha: 1)
        let open = render(PathPrimitive(elements: elements, bounds: bounds, strokeColor: stroke, lineWidth: 3))
        let closed = render(
            PathPrimitive(elements: elements + [.close], bounds: bounds, strokeColor: stroke, lineWidth: 3))

        // The closing diagonal exists only in the explicitly closed path.
        XCTAssertLessThan(red(open, x: 32, y: 32), 40)
        XCTAssertGreaterThan(red(closed, x: 32, y: 32), 200)
    }

    // MARK: - Caps

    private static let strokeRed = Color(red: 1, green: 0, blue: 0, alpha: 1)

    /// A horizontal stroke ending at x = 48, six points of half width, with
    /// each cap. The primitive used to carry a `lineWidth` and nothing else,
    /// so every stroke ended butt whatever its `StrokeStyle` said — including
    /// the round-capped ones the SF-symbol vector fallback draws every icon
    /// with.
    private func cappedStroke(_ cap: StrokeStyle.LineCap) -> BitmapSurface {
        render(
            PathPrimitive(
                elements: [.moveTo(Point(x: 16, y: 32)), .lineTo(Point(x: 48, y: 32))],
                bounds: Rect(x: 4, y: 20, width: 56, height: 24),
                strokeColor: Self.strokeRed,
                lineWidth: 12,
                lineCap: cap))
    }

    /// A butt cap stops at the endpoint: nothing past x = 48.
    func testButtCapDoesNotReachPastTheEndpoint() async {
        let bitmap = cappedStroke(.butt)
        XCTAssertGreaterThan(red(bitmap, x: 47, y: 32), 200, "the body reaches the endpoint")
        XCTAssertLessThan(red(bitmap, x: 49, y: 32), 40, "and stops there")
    }

    /// A round cap reaches exactly half a line width past the endpoint, and
    /// its corner is missing because the boundary is an arc.
    func testRoundCapExtendsHalfALineWidthAsAnArc() async {
        let bitmap = cappedStroke(.round)
        XCTAssertGreaterThan(red(bitmap, x: 52, y: 32), 200, "4.5 past the end is inside the disc")
        XCTAssertLessThan(red(bitmap, x: 55, y: 32), 40, "7.5 past it is outside a 6-point radius")
        XCTAssertLessThan(
            red(bitmap, x: 52, y: 26), 40,
            "the corner of the cap box is 7.1 from the endpoint, so an arc leaves it empty")
    }

    /// A square cap reaches the same distance, squarely: the corner the round
    /// cap leaves empty is ink.
    func testSquareCapExtendsHalfALineWidthSquarely() async {
        let bitmap = cappedStroke(.square)
        XCTAssertGreaterThan(red(bitmap, x: 52, y: 32), 200)
        XCTAssertGreaterThan(red(bitmap, x: 52, y: 26), 200, "the cap is a box, corner included")
        XCTAssertLessThan(red(bitmap, x: 55, y: 32), 40, "and it still stops at half a line width")
    }

    // MARK: - Joins

    /// A 67° corner with each join. The apex is at (32, 12); the two butt
    /// ends meet along a chord 2.24 above it, the round join fills to a
    /// 5-point radius, and the miter runs 11.2 past it.
    private func joinedCorner(_ join: StrokeStyle.LineJoin, miterLimit: Double = 10) -> BitmapSurface {
        render(
            PathPrimitive(
                elements: [
                    .moveTo(Point(x: 12, y: 52)),
                    .lineTo(Point(x: 32, y: 12)),
                    .lineTo(Point(x: 52, y: 52)),
                ],
                bounds: Rect(x: 2, y: 0, width: 60, height: 60),
                strokeColor: Self.strokeRed,
                lineWidth: 10,
                lineJoin: join,
                miterLimit: miterLimit))
    }

    func testMiterJoinFillsTheSpikePastTheCorner() async {
        let bitmap = joinedCorner(.miter)
        XCTAssertGreaterThan(red(bitmap, x: 32, y: 3), 200, "the miter runs 11.2 past the apex")
        XCTAssertGreaterThan(red(bitmap, x: 32, y: 9), 200)
    }

    func testRoundJoinFillsToTheHalfWidthAndNoFurther() async {
        let bitmap = joinedCorner(.round)
        XCTAssertGreaterThan(red(bitmap, x: 32, y: 9), 200, "2.6 from the apex is inside the disc")
        XCTAssertLessThan(red(bitmap, x: 32, y: 6), 40, "5.5 from it is outside a 5-point radius")
    }

    func testBevelJoinStopsAtTheChordBetweenTheTwoEnds() async {
        let bitmap = joinedCorner(.bevel)
        XCTAssertGreaterThan(red(bitmap, x: 32, y: 11), 200, "the wedge below the chord is filled")
        XCTAssertLessThan(red(bitmap, x: 32, y: 8), 40, "and the first row clear of the chord is empty")
    }

    /// The corner's miter is 2.24 half-widths long, so a limit of 2 degrades
    /// it to a bevel — pixel for pixel the bevel this suite already pins.
    func testMiterPastItsLimitIsExactlyABevel() async {
        let limited = joinedCorner(.miter, miterLimit: 2)
        let bevel = joinedCorner(.bevel)
        XCTAssertLessThan(red(limited, x: 32, y: 3), 40, "the spike is gone")
        XCTAssertEqual(limited.pixels, bevel.pixels, "and what is left is a bevel, not a shorter miter")
    }

    /// A closed subpath has no ends, so its cap is irrelevant — the same
    /// asymmetry `testStrokeDoesNotCloseAnOpenSubpath` pins for closure.
    func testCapStyleDoesNotChangeAClosedSubpath() async {
        func square(_ cap: StrokeStyle.LineCap) -> BitmapSurface {
            render(
                PathPrimitive(
                    elements: [
                        .moveTo(Point(x: 16, y: 16)),
                        .lineTo(Point(x: 48, y: 16)),
                        .lineTo(Point(x: 48, y: 48)),
                        .lineTo(Point(x: 16, y: 48)),
                        .close,
                    ],
                    bounds: Rect(x: 10, y: 10, width: 44, height: 44),
                    strokeColor: Self.strokeRed,
                    lineWidth: 6,
                    lineCap: cap))
        }
        XCTAssertEqual(square(.round).pixels, square(.butt).pixels)
        XCTAssertEqual(square(.square).pixels, square(.butt).pixels)
    }

    // MARK: - Clipping

    /// Path clipping rejects per pixel centre against the float rect, like
    /// every other family, instead of relying on an outward-rounded
    /// integer window.
    func testPathClipRejectsPerPixelCentre() async {
        let bitmap = render(
            PathPrimitive(
                elements: [
                    .moveTo(Point(x: 8, y: 8)),
                    .lineTo(Point(x: 56, y: 8)),
                    .lineTo(Point(x: 56, y: 56)),
                    .lineTo(Point(x: 8, y: 56)),
                    .close,
                ],
                bounds: Rect(x: 8, y: 8, width: 48, height: 48),
                fillColor: Self.fill,
                clipBounds: Rect(x: 8, y: 8, width: 24.2, height: 48)))

        XCTAssertGreaterThan(green(bitmap, x: 30, y: 32), 200, "inside the clip")
        XCTAssertLessThan(
            green(bitmap, x: 32, y: 32), 40,
            "pixel centre 32.5 is past the clip's 32.2 edge, so it is discarded rather than painted")
    }
}
