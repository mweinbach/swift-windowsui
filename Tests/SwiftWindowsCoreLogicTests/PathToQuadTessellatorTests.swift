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

    func testNonAxisAlignedQuadFillFallsThrough() {
        // A skewed quad — not an axis-aligned rect. Must fall back to
        // CPU rasterization.
        let path = makeFilledPath(elements: [
            .moveTo(Point(x: 10, y: 20)),
            .lineTo(Point(x: 60, y: 18)),
            .lineTo(Point(x: 62, y: 80)),
            .lineTo(Point(x: 8, y: 78)),
            .close,
        ])
        XCTAssertNil(
            PathToQuadTessellator.tessellate(path),
            "Non-axis-aligned quad must fall through to PathPrimitive")
    }

    func testTriangleFillFallsThrough() {
        let path = makeFilledPath(elements: [
            .moveTo(Point(x: 0, y: 0)),
            .lineTo(Point(x: 30, y: 0)),
            .lineTo(Point(x: 15, y: 25)),
            .close,
        ])
        XCTAssertNil(
            PathToQuadTessellator.tessellate(path),
            "Triangle (3 points) must fall through")
    }

    func testCurvedPathFillFallsThrough() {
        let path = makeFilledPath(elements: [
            .moveTo(Point(x: 0, y: 0)),
            .quadraticCurveTo(control: Point(x: 10, y: 10), end: Point(x: 20, y: 0)),
            .close,
        ])
        XCTAssertNil(
            PathToQuadTessellator.tessellate(path),
            "Quadratic curve segments must fall through")
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

    func testDiagonalStrokeFallsThrough() {
        let path = makeStrokedPath(
            elements: [
                .moveTo(Point(x: 10, y: 10)),
                .lineTo(Point(x: 60, y: 60)),
            ],
            lineWidth: 3
        )
        XCTAssertNil(
            PathToQuadTessellator.tessellate(path),
            "Diagonal strokes must fall through (no rotation support yet)")
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

    /// A genuinely diagonal Bezier curve produces subdivisions that
    /// aren't axis-aligned; the tessellator falls through.
    func testDiagonalQuadraticCurveFallsThrough() {
        let path = makeStrokedPath(
            elements: [
                .moveTo(Point(x: 10, y: 10)),
                .quadraticCurveTo(control: Point(x: 40, y: 80), end: Point(x: 90, y: 10)),
            ],
            lineWidth: 2
        )
        XCTAssertNil(
            PathToQuadTessellator.tessellate(path),
            "Diagonal curve subdivisions are not axis-aligned and must fall through")
    }

    /// Genuinely curved arcs (semi-circles, partial circles) produce
    /// diagonal subdivisions and fall through. Documents the boundary
    /// where the tessellator stops winning.
    func testCurvedArcFallsThrough() {
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
        XCTAssertNil(
            PathToQuadTessellator.tessellate(path),
            "Genuinely curved arcs produce diagonal subdivisions and fall through to CPU rasterization")
    }

    // MARK: - Mixed-output: partial GPU promotion

    /// A polyline of mostly-axis-aligned segments with one diagonal
    /// kink should put the axis-aligned segments on the GPU and bundle
    /// the diagonal as a residual CPU path. Previously the entire
    /// path fell through to CPU.
    func testMixedAxisAlignedAndDiagonalSegmentsSplitBetweenGPUAndCPU() {
        let path = makeStrokedPath(
            elements: [
                .moveTo(Point(x: 10, y: 10)),
                .lineTo(Point(x: 50, y: 10)),  // horizontal — GPU
                .lineTo(Point(x: 70, y: 30)),  // diagonal — CPU
                .lineTo(Point(x: 70, y: 80)),  // vertical — GPU
            ],
            lineWidth: 2
        )
        guard let result = PathToQuadTessellator.tessellateMixed(path) else {
            return XCTFail("Mixed result should be returned for a path with both axis-aligned and diagonal segments")
        }
        XCTAssertEqual(result.quads.count, 2, "Two axis-aligned segments should each become a quad")
        XCTAssertNotNil(
            result.residualPath, "Diagonal segment should go to a CPU residual path")
        XCTAssertEqual(
            result.residualPath?.lineWidth, 2.0,
            "Residual path must keep the original stroke style")
    }

    /// All axis-aligned: no residual, all quads.
    func testAllAxisAlignedSegmentsProduceNoResidual() {
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
        XCTAssertNil(result?.residualPath, "No diagonal segments → no residual")
    }

    /// All diagonal: residual covers everything, no quads.
    func testAllDiagonalSegmentsProduceNoQuads() {
        let path = makeStrokedPath(
            elements: [
                .moveTo(Point(x: 10, y: 10)),
                .lineTo(Point(x: 40, y: 50)),
                .lineTo(Point(x: 70, y: 20)),
            ],
            lineWidth: 2
        )
        let result = PathToQuadTessellator.tessellateMixed(path)
        XCTAssertEqual(result?.quads.count, 0)
        XCTAssertNotNil(result?.residualPath)
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
