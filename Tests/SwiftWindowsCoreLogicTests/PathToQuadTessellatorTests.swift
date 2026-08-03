import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI

/// Pins the contract for the GPU stroked-line / rect-fill tessellator
/// — the first concrete step toward eliminating CPU path rasterization
/// for axis-aligned shapes. Each test reflects a row of the decision
/// table in PathToQuadTessellator.swift.
final class PathToQuadTessellatorTests: XCTestCase {

    private func makeStrokedPath(elements: [PathElement], lineWidth: Double, color: Color = .white)
        -> PathPrimitive
    {
        PathPrimitive(
            elements: elements,
            bounds: Rect(x: 0, y: 0, width: 100, height: 100),
            strokeColor: color,
            lineWidth: lineWidth
        )
    }

    private func makeFilledPath(elements: [PathElement], color: Color = .white) -> PathPrimitive {
        PathPrimitive(
            elements: elements,
            bounds: Rect(x: 0, y: 0, width: 100, height: 100),
            fillColor: color
        )
    }

    // MARK: - Rect fill promotion

    func testAxisAlignedRectFillTessellatesToSingleQuad() {
        let path = makeFilledPath(
            elements: [
                .moveTo(Point(x: 10, y: 20)),
                .lineTo(Point(x: 60, y: 20)),
                .lineTo(Point(x: 60, y: 80)),
                .lineTo(Point(x: 10, y: 80)),
                .close,
            ],
            color: Color(red: 0, green: 1, blue: 0, alpha: 1)
        )
        let quads = PathToQuadTessellator.tessellate(path)
        XCTAssertEqual(quads?.count, 1)
        guard let quad = quads?.first else { return XCTFail() }
        XCTAssertEqual(quad.x, 10, accuracy: 0.001)
        XCTAssertEqual(quad.y, 20, accuracy: 0.001)
        XCTAssertEqual(quad.width, 50, accuracy: 0.001)
        XCTAssertEqual(quad.height, 60, accuracy: 0.001)
        XCTAssertEqual(quad.startG, 1)
    }

    func testFilledRectWithExplicitClosingPointStillTessellates() {
        // Some Canvas implementations duplicate the start point as the
        // close marker; the tessellator must accept either form.
        let path = makeFilledPath(elements: [
            .moveTo(Point(x: 10, y: 20)),
            .lineTo(Point(x: 60, y: 20)),
            .lineTo(Point(x: 60, y: 80)),
            .lineTo(Point(x: 10, y: 80)),
            .lineTo(Point(x: 10, y: 20)),
            .close,
        ])
        let quads = PathToQuadTessellator.tessellate(path)
        XCTAssertEqual(quads?.count, 1)
    }

    func testNonAxisAlignedConvexQuadFillTessellatesViaFanTriangulation() {
        // A skewed but convex quadrilateral — no longer falls through;
        // fan-triangulated and emitted as scanline strips.
        let path = makeFilledPath(elements: [
            .moveTo(Point(x: 10, y: 20)),
            .lineTo(Point(x: 60, y: 18)),
            .lineTo(Point(x: 62, y: 80)),
            .lineTo(Point(x: 8, y: 78)),
            .close,
        ])
        let quads = PathToQuadTessellator.tessellate(path)
        XCTAssertNotNil(quads, "Convex 4-vertex polygon must tessellate via fan triangulation")
        XCTAssertTrue(
            quads!.allSatisfy { abs($0.height - 1.0) < 0.001 },
            "Fan-triangulated polygon emits 1-px scanline strips"
        )
    }

    func testTriangleFillScanlineTessellatesToStripQuads() {
        let path = makeFilledPath(elements: [
            .moveTo(Point(x: 0, y: 0)),
            .lineTo(Point(x: 30, y: 0)),
            .lineTo(Point(x: 15, y: 25)),
            .close,
        ])
        let quads = PathToQuadTessellator.tessellate(path)
        XCTAssertNotNil(quads, "Triangle fill should scanline-tessellate into GPU strips")
        // Approximately one strip per pixel row; allow for floor/ceil
        // boundary variation.
        XCTAssertGreaterThanOrEqual(quads?.count ?? 0, 24)
        XCTAssertLessThanOrEqual(quads?.count ?? 0, 26)
        // Each strip must be 1 pixel tall.
        XCTAssertTrue(
            quads!.allSatisfy { abs($0.height - 1.0) < 0.001 },
            "Every scanline strip must be exactly one pixel tall"
        )
    }

    func testDegenerateColinearTriangleFallsThrough() {
        // Three colinear points have zero area; the tessellator must
        // refuse rather than emit zero strips.
        let path = makeFilledPath(elements: [
            .moveTo(Point(x: 0, y: 0)),
            .lineTo(Point(x: 10, y: 0)),
            .lineTo(Point(x: 20, y: 0)),
            .close,
        ])
        XCTAssertNil(
            PathToQuadTessellator.tessellate(path),
            "Colinear triangle (zero area) must fall through")
    }

    func testTriangleScanlineCoversAllRows() {
        // A 4-row-tall triangle should produce roughly 4 strips, each
        // 1 pixel tall.
        let path = makeFilledPath(elements: [
            .moveTo(Point(x: 0, y: 0)),
            .lineTo(Point(x: 20, y: 0)),
            .lineTo(Point(x: 10, y: 4)),
            .close,
        ])
        let quads = PathToQuadTessellator.tessellate(path)
        XCTAssertNotNil(quads)
        XCTAssertGreaterThanOrEqual(quads?.count ?? 0, 3)
        XCTAssertLessThanOrEqual(quads?.count ?? 0, 5)
    }

    func testCurvedConvexFillTessellatesViaFanTriangulation() {
        // A closed convex curved path — quadratic curve bulging
        // outward then back along a straight line — fans into many
        // scanline strip quads. RoundedRectangle / Circle / Capsule
        // exercise this lane.
        let path = makeFilledPath(elements: [
            .moveTo(Point(x: 0, y: 20)),
            .quadraticCurveTo(control: Point(x: 30, y: -10), end: Point(x: 60, y: 20)),
            .lineTo(Point(x: 0, y: 20)),
            .close,
        ])
        let quads = PathToQuadTessellator.tessellate(path)
        XCTAssertNotNil(
            quads,
            "Convex curved fill must tessellate via fan triangulation + scanline strips"
        )
        XCTAssertTrue(
            quads!.allSatisfy { abs($0.height - 1.0) < 0.001 },
            "Every emitted quad is a 1-pixel-tall scanline strip"
        )
    }

    func testConcavePolygonFillTessellatesViaEarClipping() {
        // An arrowhead-shaped polygon — concave (interior notch).
        // Ear-clipping triangulates simple concave polygons too, so
        // this path now rides the GPU as scanline strips rather than
        // falling through to CPU rasterization.
        let path = makeFilledPath(elements: [
            .moveTo(Point(x: 0, y: 0)),
            .lineTo(Point(x: 40, y: 0)),
            .lineTo(Point(x: 30, y: 20)),  // notch — concave point
            .lineTo(Point(x: 40, y: 40)),
            .lineTo(Point(x: 0, y: 40)),
            .close,
        ])
        let quads = PathToQuadTessellator.tessellate(path)
        XCTAssertNotNil(
            quads,
            "Concave (but simple) polygons must tessellate via ear-clipping"
        )
        XCTAssertTrue(
            quads!.allSatisfy { abs($0.height - 1.0) < 0.001 },
            "Ear-clipped polygon emits 1-px scanline strips"
        )
    }

    func testSelfIntersectingBowtieStillFallsThrough() {
        // A bowtie (figure-8) — two triangles sharing a crossing
        // interior edge. Ear-clipping can't triangulate non-simple
        // polygons cleanly, so this must fall through.
        let path = makeFilledPath(elements: [
            .moveTo(Point(x: 0, y: 0)),
            .lineTo(Point(x: 40, y: 0)),
            .lineTo(Point(x: 0, y: 40)),  // crossing edge starts here
            .lineTo(Point(x: 40, y: 40)),
            .close,
        ])
        XCTAssertNil(
            PathToQuadTessellator.tessellate(path),
            "Self-intersecting (non-simple) polygons must fall through to CPU"
        )
    }

    func testConvexFiveVertexPolygonTessellates() {
        // Regular-ish pentagon. Each fan triangle (3 of them) becomes
        // a scanline strip.
        let path = makeFilledPath(elements: [
            .moveTo(Point(x: 30, y: 0)),
            .lineTo(Point(x: 60, y: 22)),
            .lineTo(Point(x: 48, y: 60)),
            .lineTo(Point(x: 12, y: 60)),
            .lineTo(Point(x: 0, y: 22)),
            .close,
        ])
        let quads = PathToQuadTessellator.tessellate(path)
        XCTAssertNotNil(quads, "Convex pentagon must tessellate via fan triangulation")
        XCTAssertGreaterThan(quads?.count ?? 0, 20)
    }

    // MARK: - Stroked-line promotion

    func testHorizontalStrokeTessellatesToSingleQuad() {
        let path = makeStrokedPath(
            elements: [
                .moveTo(Point(x: 10, y: 50)),
                .lineTo(Point(x: 90, y: 50)),
            ],
            lineWidth: 4,
            color: Color(red: 0, green: 0, blue: 1, alpha: 1)
        )
        let quads = PathToQuadTessellator.tessellate(path)
        XCTAssertEqual(quads?.count, 1)
        guard let quad = quads?.first else { return XCTFail() }
        // The default cap is butt, so the body stops flush at both endpoints.
        // Every segment used to be extended by half a line width whatever the
        // style said, which drew a square cap on a stroke that asked for none.
        XCTAssertEqual(quad.x, 10, accuracy: 0.001)
        XCTAssertEqual(quad.y, 48, accuracy: 0.001)
        XCTAssertEqual(quad.width, 80, accuracy: 0.001)
        XCTAssertEqual(quad.height, 4, accuracy: 0.001)
        XCTAssertEqual(quad.startB, 1)
    }

    func testVerticalStrokeTessellatesToSingleQuad() {
        let path = makeStrokedPath(
            elements: [
                .moveTo(Point(x: 50, y: 10)),
                .lineTo(Point(x: 50, y: 90)),
            ],
            lineWidth: 2
        )
        let quads = PathToQuadTessellator.tessellate(path)
        XCTAssertEqual(quads?.count, 1)
        guard let quad = quads?.first else { return XCTFail() }
        XCTAssertEqual(quad.x, 49, accuracy: 0.001)
        XCTAssertEqual(quad.y, 10, accuracy: 0.001)
        XCTAssertEqual(quad.width, 2, accuracy: 0.001)
        XCTAssertEqual(quad.height, 80, accuracy: 0.001)
    }

    /// The same vertical stroke with each of the three caps: butt stops
    /// flush, square extends by half a line width at both ends, round stops
    /// flush and gets a disc — a `lineWidth × lineWidth` quad whose corner
    /// radius is half its side.
    func testCapStyleDecidesHowFarTheBodyReaches() {
        func body(_ cap: StrokeStyle.LineCap) -> [QuadPrimitive] {
            var path = makeStrokedPath(
                elements: [.moveTo(Point(x: 50, y: 10)), .lineTo(Point(x: 50, y: 90))],
                lineWidth: 4)
            path.lineCap = cap
            return PathToQuadTessellator.tessellate(path) ?? []
        }

        let butt = body(.butt)
        XCTAssertEqual(butt.count, 1)
        XCTAssertEqual(butt.first?.y ?? -1, 10, accuracy: 0.001)
        XCTAssertEqual(butt.first?.height ?? -1, 80, accuracy: 0.001)

        let square = body(.square)
        XCTAssertEqual(square.count, 1)
        XCTAssertEqual(square.first?.y ?? -1, 8, accuracy: 0.001)
        XCTAssertEqual(square.first?.height ?? -1, 84, accuracy: 0.001)

        let round = body(.round)
        XCTAssertEqual(round.count, 3, "one body plus one disc per end")
        let stem = round.first { $0.height > 10 }
        XCTAssertEqual(stem?.y ?? -1, 10, accuracy: 0.001)
        XCTAssertEqual(stem?.height ?? -1, 80, accuracy: 0.001)
        let discs = round.filter { $0.cornerRadius > 0 }
        XCTAssertEqual(discs.count, 2)
        for disc in discs {
            XCTAssertEqual(disc.width, 4, accuracy: 0.001)
            XCTAssertEqual(disc.height, 4, accuracy: 0.001)
            XCTAssertEqual(disc.cornerRadius, 2, accuracy: 0.001)
        }
        XCTAssertEqual(discs.map(\.y).sorted(), [8, 88])
    }

    /// A right-angle miter is exactly the square the two extended bodies
    /// cover, so an L stays on the GPU; a 45° one is a kite no rectangle can
    /// be, so the whole path goes to the CPU stroker rather than rendering a
    /// join nobody asked for.
    func testMiterJoinPromotesOnlyWhenTheQuadFamilyCanDrawItExactly() {
        let rightAngle = makeStrokedPath(
            elements: [
                .moveTo(Point(x: 10, y: 10)),
                .lineTo(Point(x: 60, y: 10)),
                .lineTo(Point(x: 60, y: 60)),
            ],
            lineWidth: 6)
        XCTAssertEqual(PathToQuadTessellator.tessellate(rightAngle)?.count, 2)

        let sharp = makeStrokedPath(
            elements: [
                .moveTo(Point(x: 10, y: 10)),
                .lineTo(Point(x: 60, y: 10)),
                .lineTo(Point(x: 90, y: 40)),
            ],
            lineWidth: 6)
        XCTAssertNil(
            PathToQuadTessellator.tessellateMixed(sharp),
            "a 45° miter is not a rectangle; the CPU stroker draws it")

        var rounded = sharp
        rounded.lineJoin = .round
        let roundedQuads = PathToQuadTessellator.tessellate(rounded)
        XCTAssertEqual(roundedQuads?.count, 3, "two bodies plus the join disc")
        XCTAssertEqual(roundedQuads?.filter { $0.cornerRadius > 0 }.count, 1)
    }

    /// A bevel is a triangle whatever the angle, so a visible one always
    /// falls back — and a turn too shallow to show a join still promotes.
    func testBevelJoinFallsBackOnlyWhenTheJoinIsVisible() {
        var sharp = makeStrokedPath(
            elements: [
                .moveTo(Point(x: 10, y: 10)),
                .lineTo(Point(x: 60, y: 10)),
                .lineTo(Point(x: 60, y: 60)),
            ],
            lineWidth: 6)
        sharp.lineJoin = .bevel
        XCTAssertNil(PathToQuadTessellator.tessellateMixed(sharp))

        var shallow = makeStrokedPath(
            elements: [
                .moveTo(Point(x: 10, y: 10)),
                .lineTo(Point(x: 60, y: 10)),
                .lineTo(Point(x: 110, y: 10.2)),
            ],
            lineWidth: 2)
        shallow.lineJoin = .bevel
        XCTAssertEqual(PathToQuadTessellator.tessellate(shallow)?.count, 2)
    }

    func testMultipleAxisAlignedSegmentsProduceOneQuadPerSegment() {
        // An L-shape: horizontal then vertical.
        let path = makeStrokedPath(
            elements: [
                .moveTo(Point(x: 10, y: 10)),
                .lineTo(Point(x: 60, y: 10)),
                .lineTo(Point(x: 60, y: 80)),
            ],
            lineWidth: 2
        )
        let quads = PathToQuadTessellator.tessellate(path)
        XCTAssertEqual(quads?.count, 2)
    }

    func testDiagonalStrokeProducesRotatedQuad() {
        let path = makeStrokedPath(
            elements: [
                .moveTo(Point(x: 10, y: 10)),
                .lineTo(Point(x: 60, y: 60)),
            ],
            lineWidth: 3
        )
        let quads = PathToQuadTessellator.tessellate(path)
        XCTAssertEqual(quads?.count, 1, "Diagonal stroke should emit a single rotated quad")
        XCTAssertGreaterThan(
            Float(abs(quads?.first?.rotationRadians ?? 0)), 0.01,
            "Diagonal segment must carry non-zero rotation"
        )
    }

    func testClosedStrokedRectTessellatesToFourQuads() {
        // Closed stroked outline of a rect: emits one quad per side.
        let path = makeStrokedPath(
            elements: [
                .moveTo(Point(x: 10, y: 10)),
                .lineTo(Point(x: 60, y: 10)),
                .lineTo(Point(x: 60, y: 60)),
                .lineTo(Point(x: 10, y: 60)),
                .close,
            ],
            lineWidth: 2
        )
        let quads = PathToQuadTessellator.tessellate(path)
        XCTAssertEqual(quads?.count, 4, "Closed stroked rect should emit four side quads")
    }

    // MARK: - Curve subdivision

    /// A degenerate horizontal quadratic curve (control point on the
    /// line from start to end) traces a flat horizontal stroke. After
    /// subdivision every line segment is horizontal, so the tessellator
    /// emits per-segment quads on the GPU instead of CPU-rasterising.
    func testHorizontalDegenerateQuadraticCurveTessellates() {
        let path = makeStrokedPath(
            elements: [
                .moveTo(Point(x: 10, y: 30)),
                .quadraticCurveTo(control: Point(x: 50, y: 30), end: Point(x: 90, y: 30)),
            ],
            lineWidth: 2
        )
        let quads = PathToQuadTessellator.tessellate(path)
        XCTAssertNotNil(
            quads,
            "Horizontal degenerate quadratic curve must subdivide into axis-aligned quads")
        XCTAssertEqual(
            quads?.count, 16,
            "Expected one quad per curve subdivision sample")
        XCTAssertTrue(
            quads!.allSatisfy { abs($0.height - 2) < 0.001 },
            "Every subdivided quad must be the line-width tall horizontal strip")
    }

    /// A degenerate vertical cubic Bezier — both control points on the
    /// vertical axis — also tessellates to axis-aligned quads.
    func testVerticalDegenerateCubicCurveTessellates() {
        let path = makeStrokedPath(
            elements: [
                .moveTo(Point(x: 50, y: 10)),
                .cubicCurveTo(
                    control1: Point(x: 50, y: 30),
                    control2: Point(x: 50, y: 70),
                    end: Point(x: 50, y: 90)),
            ],
            lineWidth: 3
        )
        let quads = PathToQuadTessellator.tessellate(path)
        XCTAssertNotNil(quads)
        XCTAssertTrue(
            quads!.allSatisfy { abs($0.width - 3) < 0.001 },
            "Every subdivided quad must be the line-width wide vertical strip")
    }

    /// A genuinely diagonal Bezier curve subdivides into many small
    /// rotated quad segments — every subdivision rides the GPU now.
    func testDiagonalQuadraticCurveProducesRotatedQuadSegments() {
        let path = makeStrokedPath(
            elements: [
                .moveTo(Point(x: 10, y: 10)),
                .quadraticCurveTo(control: Point(x: 40, y: 80), end: Point(x: 90, y: 10)),
            ],
            lineWidth: 2
        )
        let quads = PathToQuadTessellator.tessellate(path)
        XCTAssertEqual(quads?.count, 16, "Curve subdivides into 16 segments — each becomes a quad")
        XCTAssertTrue(
            quads?.contains(where: { abs($0.rotationRadians) > 0.01 }) == true,
            "Curve segments must include rotated quads (the curve is not axis-aligned)")
    }

    /// A semicircle arc subdivides into 16 rotated-quad segments
    /// covering its sweep.
    func testCurvedArcProducesRotatedQuadSegments() {
        let path = makeStrokedPath(
            elements: [
                .moveTo(Point(x: 50, y: 50)),
                .arc(
                    center: Point(x: 50, y: 50),
                    radius: 20,
                    startAngle: 0,
                    endAngle: .pi,
                    clockwise: false),
            ],
            lineWidth: 2
        )
        let quads = PathToQuadTessellator.tessellate(path)
        XCTAssertNotNil(quads)
        XCTAssertGreaterThan(
            quads?.count ?? 0, 8,
            "Arc should subdivide into many rotated quad segments"
        )
        XCTAssertTrue(
            quads?.contains(where: { abs($0.rotationRadians) > 0.01 }) == true,
            "Arc segments must carry non-zero rotation")
    }

    // MARK: - Mixed-output: partial GPU promotion

    /// A polyline of mixed axis-aligned and diagonal segments puts every
    /// segment on the GPU — axis-aligned ones as fast-path quads, diagonal
    /// ones as rotated quads — as long as the joins between them are ones
    /// the quad family can draw. The CPU residual path is empty.
    func testMixedAxisAlignedAndDiagonalSegmentsAllReachGPU() {
        var path = makeStrokedPath(
            elements: [
                .moveTo(Point(x: 10, y: 10)),
                .lineTo(Point(x: 50, y: 10)),  // horizontal — quad rotation 0
                .lineTo(Point(x: 70, y: 30)),  // diagonal — rotated quad
                .lineTo(Point(x: 70, y: 80)),  // vertical — quad rotation 0
            ],
            // Thick enough for a 45° join to be worth drawing at all: at two
            // points wide the wedge is 0.076 px deep, below the tolerance
            // both stroke rasterizers share.
            lineWidth: 6
        )
        // The two 45° corners are round joins, which are discs; with the
        // default miter they would be kites and the path would go to the CPU
        // stroker instead of rendering a join nobody asked for.
        path.lineJoin = .round
        guard let result = PathToQuadTessellator.tessellateMixed(path) else {
            return XCTFail("Mixed result should be returned")
        }
        XCTAssertEqual(result.quads.count, 5, "three segment bodies plus two join discs")
        XCTAssertNil(
            result.residualPath, "Rotated-quad support eliminates the CPU residual path")
        // Exactly one segment is diagonal — exactly one body quad must
        // carry a non-zero rotation.
        let rotated = result.quads.filter { abs($0.rotationRadians) > 0.01 }
        XCTAssertEqual(rotated.count, 1)
        XCTAssertEqual(result.quads.filter { $0.cornerRadius > 0 }.count, 2)
    }

    /// All axis-aligned: every quad has rotation 0.
    func testAllAxisAlignedSegmentsProduceUnrotatedQuads() {
        let path = makeStrokedPath(
            elements: [
                .moveTo(Point(x: 10, y: 10)),
                .lineTo(Point(x: 50, y: 10)),
                .lineTo(Point(x: 50, y: 30)),
            ],
            lineWidth: 2
        )
        let result = PathToQuadTessellator.tessellateMixed(path)
        XCTAssertEqual(result?.quads.count, 2)
        XCTAssertTrue(
            result?.quads.allSatisfy { $0.rotationRadians == 0 } == true,
            "Axis-aligned segments must have zero rotation"
        )
        XCTAssertNil(result?.residualPath)
    }

    /// All diagonal: every segment body is rotated.
    func testAllDiagonalSegmentsProduceRotatedQuads() {
        var path = makeStrokedPath(
            elements: [
                .moveTo(Point(x: 10, y: 10)),
                .lineTo(Point(x: 40, y: 50)),
                .lineTo(Point(x: 70, y: 20)),
            ],
            lineWidth: 2
        )
        path.lineJoin = .round
        let result = PathToQuadTessellator.tessellateMixed(path)
        XCTAssertEqual(result?.quads.count, 3, "two rotated bodies plus the join disc")
        XCTAssertTrue(
            result?.quads.filter { $0.cornerRadius == 0 }.allSatisfy { abs($0.rotationRadians) > 0.01 } == true,
            "Diagonal segments must produce rotated quads"
        )
        XCTAssertNil(result?.residualPath)
    }

    // MARK: - Edge cases

    func testEmptyPathReturnsNil() {
        let path = makeStrokedPath(elements: [], lineWidth: 2)
        XCTAssertNil(PathToQuadTessellator.tessellate(path))
    }

    func testFilledAndStrokedPathFallsThroughToPathPrimitive() {
        // A path with BOTH fill and stroke — currently must go through
        // the CPU path so the rasterizer can layer them properly.
        let path = PathPrimitive(
            elements: [
                .moveTo(Point(x: 10, y: 20)),
                .lineTo(Point(x: 60, y: 20)),
                .lineTo(Point(x: 60, y: 80)),
                .lineTo(Point(x: 10, y: 80)),
                .close,
            ],
            bounds: Rect(x: 0, y: 0, width: 100, height: 100),
            fillColor: Color(red: 0, green: 1, blue: 0, alpha: 1),
            strokeColor: Color(red: 1, green: 0, blue: 0, alpha: 1),
            lineWidth: 2
        )
        XCTAssertNil(PathToQuadTessellator.tessellate(path))
    }
}
