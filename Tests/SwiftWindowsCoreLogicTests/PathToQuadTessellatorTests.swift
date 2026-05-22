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

    func testConcavePolygonFillFallsThrough() {
        // An arrowhead-shaped polygon — concave (the notch creates an
        // interior angle > 180°). Fan triangulation would emit invalid
        // quads, so the tessellator must refuse.
        let path = makeFilledPath(elements: [
            .moveTo(Point(x: 0, y: 0)),
            .lineTo(Point(x: 40, y: 0)),
            .lineTo(Point(x: 30, y: 20)),  // notch — concave point
            .lineTo(Point(x: 40, y: 40)),
            .lineTo(Point(x: 0, y: 40)),
            .close,
        ])
        XCTAssertNil(
            PathToQuadTessellator.tessellate(path),
            "Concave polygons must fall through to CPU rasterization"
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
        // x = min(10,90) - lineWidth/2 = 8; width = 80 + lineWidth = 84.
        XCTAssertEqual(quad.x, 8, accuracy: 0.001)
        XCTAssertEqual(quad.y, 48, accuracy: 0.001)
        XCTAssertEqual(quad.width, 84, accuracy: 0.001)
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
        XCTAssertEqual(quad.width, 2, accuracy: 0.001)
        XCTAssertEqual(quad.height, 82, accuracy: 0.001)
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

    /// A polyline of mixed axis-aligned and diagonal segments now
    /// puts every segment on the GPU — axis-aligned ones as fast-path
    /// quads, diagonal ones as rotated quads. The CPU residual path
    /// is empty.
    func testMixedAxisAlignedAndDiagonalSegmentsAllReachGPU() {
        let path = makeStrokedPath(
            elements: [
                .moveTo(Point(x: 10, y: 10)),
                .lineTo(Point(x: 50, y: 10)),  // horizontal — quad rotation 0
                .lineTo(Point(x: 70, y: 30)),  // diagonal — rotated quad
                .lineTo(Point(x: 70, y: 80)),  // vertical — quad rotation 0
            ],
            lineWidth: 2
        )
        guard let result = PathToQuadTessellator.tessellateMixed(path) else {
            return XCTFail("Mixed result should be returned")
        }
        XCTAssertEqual(result.quads.count, 3, "Three segments → three GPU quads")
        XCTAssertNil(
            result.residualPath, "Rotated-quad support eliminates the CPU residual path")
        // Exactly one segment is diagonal — exactly one quad must
        // carry a non-zero rotation.
        let rotated = result.quads.filter { abs($0.rotationRadians) > 0.01 }
        XCTAssertEqual(rotated.count, 1)
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

    /// All diagonal: every quad is rotated.
    func testAllDiagonalSegmentsProduceRotatedQuads() {
        let path = makeStrokedPath(
            elements: [
                .moveTo(Point(x: 10, y: 10)),
                .lineTo(Point(x: 40, y: 50)),
                .lineTo(Point(x: 70, y: 20)),
            ],
            lineWidth: 2
        )
        let result = PathToQuadTessellator.tessellateMixed(path)
        XCTAssertEqual(result?.quads.count, 2)
        XCTAssertTrue(
            result?.quads.allSatisfy { abs($0.rotationRadians) > 0.01 } == true,
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
