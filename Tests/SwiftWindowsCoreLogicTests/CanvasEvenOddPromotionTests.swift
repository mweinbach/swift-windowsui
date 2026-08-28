import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI

/// Even-odd coverage may use a solid GPU footprint only when its topology is
/// known to have the same interior under both rules. Default producers retain
/// their existing eligibility and compound paths retain one coverage raster.
final class CanvasEvenOddPromotionTests: XCTestCase {
    private func primitive(_ path: Path, rule: PathFillRule) -> PathPrimitive {
        PathPrimitive(
            elements: path.elements, bounds: path.boundingRect,
            fillColor: .white, fillRule: rule)
    }

    private func polygon(_ points: [Point], closed: Bool = true) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.moveTo(first)
        for point in points.dropFirst() { path.lineTo(point) }
        if closed { path.close() }
        return path
    }

    private func circlePolygon(vertexCount: Int) -> Path {
        polygon(
            (0..<vertexCount).map { index in
                let angle = 2 * Double.pi * Double(index) / Double(vertexCount)
                return Point(x: 40 + 24 * cos(angle), y: 40 + 24 * sin(angle))
            })
    }

    private func assertSamePromotion(
        _ path: Path, expectedCount: Int? = nil, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let normal = try XCTUnwrap(
            PathToQuadTessellator.tessellateMixed(primitive(path, rule: .nonZero)), file: file, line: line)
        let evenOdd = try XCTUnwrap(
            PathToQuadTessellator.tessellateMixed(primitive(path, rule: .evenOdd)), file: file, line: line)
        XCTAssertFalse(normal.quads.isEmpty, file: file, line: line)
        XCTAssertNil(normal.residualPath, file: file, line: line)
        XCTAssertEqual(evenOdd, normal, file: file, line: line)
        if let expectedCount { XCTAssertEqual(evenOdd.quads.count, expectedCount, file: file, line: line) }
    }

    func testEvenOddRectangleKeepsOneIdenticalGPUQuad() throws {
        try assertSamePromotion(Path(Rect(x: 8, y: 12, width: 48, height: 32)), expectedCount: 1)
    }

    func testEvenOddTriangleKeepsGPUScanlines() throws {
        try assertSamePromotion(
            polygon([Point(x: 8, y: 8), Point(x: 56, y: 12), Point(x: 24, y: 56)]))
    }

    func testEvenOddUnclosedTriangleKeepsGPUScanlines() throws {
        try assertSamePromotion(
            polygon([Point(x: 8, y: 8), Point(x: 56, y: 12), Point(x: 24, y: 56)], closed: false))
    }

    func testEvenOddConvexPolygonKeepsGPUScanlines() throws {
        try assertSamePromotion(
            polygon([
                Point(x: 12, y: 8), Point(x: 48, y: 12), Point(x: 56, y: 40),
                Point(x: 32, y: 56), Point(x: 8, y: 40),
            ]))
    }

    func testEvenOddConcavePolygonKeepsGPUScanlines() throws {
        try assertSamePromotion(
            polygon([
                Point(x: 8, y: 8), Point(x: 56, y: 8), Point(x: 56, y: 24),
                Point(x: 24, y: 24), Point(x: 24, y: 56), Point(x: 8, y: 56),
            ]))
    }

    func testEvenOddCanonicalRoundedRectangleKeepsOneGPUQuad() throws {
        try assertSamePromotion(
            Path(roundedRect: Rect(x: 8, y: 12, width: 48, height: 32), cornerRadius: 6), expectedCount: 1)
    }

    func testEvenOddPlacedRoundedRectangleKeepsOneGPUQuad() throws {
        let path = Path(roundedRect: Rect(x: 8, y: 12, width: 48, height: 32), cornerRadius: 6)
        let offset = Point(x: 7.25, y: 5.75)
        let normal = primitive(path, rule: .nonZero).translated(by: offset).scaled(by: 1.5)
        let evenOdd = primitive(path, rule: .evenOdd).translated(by: offset).scaled(by: 1.5)
        let result = try XCTUnwrap(PathToQuadTessellator.tessellateMixed(evenOdd))
        XCTAssertEqual(result.quads.count, 1)
        XCTAssertNil(result.residualPath)
        XCTAssertEqual(result, PathToQuadTessellator.tessellateMixed(normal))
    }

    func testEvenOddRectangleWithRepeatedClosingPointKeepsOneGPUQuad() throws {
        try assertSamePromotion(
            polygon([
                Point(x: 8, y: 8), Point(x: 56, y: 8), Point(x: 56, y: 40),
                Point(x: 8, y: 40), Point(x: 8, y: 8),
            ]), expectedCount: 1)
    }

    func testEvenOddRepeatedCornerDoesNotPromoteAsRectangle() {
        let path = polygon([
            Point(x: 8, y: 8), Point(x: 56, y: 8), Point(x: 56, y: 40), Point(x: 56, y: 8),
        ])
        XCTAssertNil(PathToQuadTessellator.tessellateMixed(primitive(path, rule: .evenOdd)))
    }

    func testEvenOddThinBowtieCannotPassApproximateRectangleAlignment() {
        let path = polygon([
            Point(x: 0, y: 0), Point(x: 0.00001, y: 10),
            Point(x: 0.00001, y: 0), Point(x: 0, y: 10),
        ])
        XCTAssertNil(PathToQuadTessellator.tessellateMixed(primitive(path, rule: .evenOdd)))
    }

    func testEvenOddCloseFollowedByMoreEdgesRetainsCoveragePath() {
        var path = polygon([Point(x: 8, y: 8), Point(x: 56, y: 8), Point(x: 56, y: 40)])
        path.lineTo(Point(x: 8, y: 40))
        XCTAssertNil(PathToQuadTessellator.tessellateMixed(primitive(path, rule: .evenOdd)))
    }

    func testEvenOddMultipleContoursRetainCoveragePath() {
        var path = Path(Rect(x: 8, y: 8, width: 48, height: 48))
        path.addRect(Rect(x: 20, y: 20, width: 24, height: 24))
        XCTAssertNil(PathToQuadTessellator.tessellateMixed(primitive(path, rule: .evenOdd)))
        XCTAssertNil(PathToQuadTessellator.tessellateMixed(primitive(path, rule: .nonZero)))
    }

    func testEvenOddPentagramRetainsCoverageDespiteConsistentTurnSigns() {
        let vertices = (0..<5).map { index in
            let angle = -Double.pi / 2 + Double(index) * 2 * Double.pi / 5
            return Point(x: 32 + 24 * cos(angle), y: 32 + 24 * sin(angle))
        }
        let path = polygon([0, 2, 4, 1, 3].map { vertices[$0] })
        XCTAssertNil(PathToQuadTessellator.tessellateMixed(primitive(path, rule: .evenOdd)))
    }

    func testEvenOddBacktrackingContourRetainsCoveragePath() {
        let path = polygon([
            Point(x: 8, y: 8), Point(x: 56, y: 8), Point(x: 32, y: 8),
            Point(x: 32, y: 40), Point(x: 8, y: 40),
        ])
        XCTAssertNil(PathToQuadTessellator.tessellateMixed(primitive(path, rule: .evenOdd)))
    }

    func testEvenOddUnprovenCurveRetainsCoveragePath() {
        let path = Path(ellipseIn: Rect(x: 8, y: 8, width: 48, height: 32))
        XCTAssertNil(PathToQuadTessellator.tessellateMixed(primitive(path, rule: .evenOdd)))
        XCTAssertNotNil(PathToQuadTessellator.tessellateMixed(primitive(path, rule: .nonZero)))
    }

    func testEvenOddRoundedRectangleWithMultiTurnArcRetainsCoveragePath() {
        let path = Path(roundedRect: Rect(x: 8, y: 12, width: 48, height: 32), cornerRadius: 6)
        var changed = primitive(path, rule: .evenOdd)
        guard case .arc(let center, let radius, let start, let end, let clockwise) = changed.elements[2] else {
            return XCTFail("the first corner must be an arc")
        }
        changed.elements[2] = .arc(
            center: center, radius: radius, startAngle: start,
            endAngle: end + 2 * .pi, clockwise: clockwise)
        XCTAssertNil(PathToQuadTessellator.tessellateMixed(changed))
    }

    func testEvenOddRoundedRectangleWithReorderedCornersRetainsCoveragePath() {
        let path = Path(roundedRect: Rect(x: 8, y: 12, width: 48, height: 32), cornerRadius: 6)
        var changed = primitive(path, rule: .evenOdd)
        changed.elements.swapAt(2, 4)
        XCTAssertNil(PathToQuadTessellator.tessellateMixed(changed))
    }

    func testEvenOddTinyRoundedRectangleCannotUseToleranceToReorderCorners() {
        let path = Path(roundedRect: Rect(x: 0, y: 0, width: 0.0008, height: 0.0008), cornerRadius: 0.0001)
        var changed = primitive(path, rule: .evenOdd)
        changed.elements.swapAt(2, 4)
        XCTAssertNil(PathToQuadTessellator.tessellateMixed(changed))
    }

    func testEvenOddPolygonAtProofBudgetKeepsGPUScanlines() throws {
        try assertSamePromotion(circlePolygon(vertexCount: 256))
    }

    func testEvenOddPolygonBeyondProofBudgetRetainsCoveragePath() {
        let path = circlePolygon(vertexCount: 257)
        XCTAssertNil(PathToQuadTessellator.tessellateMixed(primitive(path, rule: .evenOdd)))
        XCTAssertNotNil(PathToQuadTessellator.tessellateMixed(primitive(path, rule: .nonZero)))
    }

    func testStrokeOnlyPrimitiveKeepsTheSameGPUOutputUnderEitherFillRule() throws {
        let path = polygon([Point(x: 8, y: 8), Point(x: 48, y: 8), Point(x: 48, y: 40)], closed: false)
        var normal = primitive(path, rule: .nonZero)
        normal.fillColor = .clear
        normal.strokeColor = .white
        normal.lineWidth = 4
        var evenOdd = normal
        evenOdd.fillRule = .evenOdd
        let result = try XCTUnwrap(PathToQuadTessellator.tessellateMixed(evenOdd))
        XCTAssertFalse(result.quads.isEmpty)
        XCTAssertEqual(result, PathToQuadTessellator.tessellateMixed(normal))
    }

    func testEvenOddCombinedFillAndStrokeRetainsCoveragePath() {
        let path = Path(Rect(x: 8, y: 8, width: 48, height: 48))
        var value = primitive(path, rule: .evenOdd)
        value.strokeColor = .white
        value.lineWidth = 4
        XCTAssertNil(PathToQuadTessellator.tessellateMixed(value))
    }
}
