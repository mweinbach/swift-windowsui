import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import WinSwiftUI
import XCTest

@testable import SwiftWindowsUI

/// A small row count does not guarantee that a large Double row can advance by one.
/// These inputs exercise the guarded entry point, never an unpatched loop. Values
/// outside the scene coordinate limit test progress and fallback, not pixel fidelity.
@MainActor
final class PathScanlineProgressTests: XCTestCase {
    private enum Figure {
        case triangle
        case trapezoid
    }

    private static let unitBoundary: Double = 9_007_199_254_740_992
    private static let stalledMagnitude: Double = 18_014_398_509_481_984
    private static let surface = IntSize(width: 16, height: 16)
    private static let rules: [PathFillRule] = [.nonZero, .evenOdd]

    private static var rejectedRanges: [(minY: Double, height: Double)] {
        [
            (stalledMagnitude, 16), (-stalledMagnitude, 16),
            (unitBoundary + 2, 16), (-unitBoundary - 2, 16),
            (unitBoundary - 4, 16),
            (1e19, 2048), (-1e19, 2048),
        ]
    }

    func testHugePositiveTriangleFallsBackForBothFillRules() async {
        assertImmediateFallback(.triangle, sign: 1)
    }

    func testHugeNegativeTriangleFallsBackForBothFillRules() async {
        assertImmediateFallback(.triangle, sign: -1)
    }

    func testHugePositiveTrapezoidFallsBackForBothFillRules() async {
        assertImmediateFallback(.trapezoid, sign: 1)
    }

    func testHugeNegativeTrapezoidFallsBackForBothFillRules() async {
        assertImmediateFallback(.trapezoid, sign: -1)
    }

    func testTriangleCrossingUnitBoundaryDiscardsAllStrips() async {
        assertCrossingFallback(.triangle)
    }

    func testTrapezoidCrossingUnitBoundaryDiscardsAllStrips() async {
        assertCrossingFallback(.trapezoid)
    }

    func testOrdinaryTriangleKeepsExactUnitRows() async throws {
        try assertOrdinaryRows(.triangle)
    }

    func testOrdinaryTrapezoidKeepsExactUnitRows() async throws {
        try assertOrdinaryRows(.trapezoid)
    }

    func testOrdinaryTriangleClipKeepsOnlyVisibleRows() async throws {
        try assertOrdinaryClippedRows(.triangle)
    }

    func testOrdinaryTrapezoidClipKeepsOnlyVisibleRows() async throws {
        try assertOrdinaryClippedRows(.trapezoid)
    }

    func testTriangleWithRepresentableBoundaryProgressRemainsAdmitted() async throws {
        try assertRepresentableProgress(.triangle)
    }

    func testTrapezoidWithRepresentableBoundaryProgressRemainsAdmitted() async throws {
        try assertRepresentableProgress(.trapezoid)
    }

    func testHugeTriangleVerticesCanUseOrdinaryClippedRows() async throws {
        try assertHugeVerticesWithOrdinaryClip(.triangle)
    }

    func testHugeTrapezoidVerticesCanUseOrdinaryClippedRows() async throws {
        try assertHugeVerticesWithOrdinaryClip(.trapezoid)
    }

    func testScenePainterTriangleFallbackIsSanitizedAndSmallRasterIsClear() async throws {
        try assertSceneFallback(.triangle)
    }

    func testScenePainterTrapezoidFallbackIsSanitizedAndSmallRasterIsClear() async throws {
        try assertSceneFallback(.trapezoid)
    }

    func testPublicCanvasCullsHugeTrianglesBeforeEmission() async {
        assertCanvasCulling(.triangle)
    }

    func testPublicCanvasCullsHugeTrapezoidsBeforeEmission() async {
        assertCanvasCulling(.trapezoid)
    }

    private func points(for figure: Figure, minY: Double, maxY: Double) -> [Point] {
        switch figure {
        case .triangle:
            return [Point(x: 0, y: minY), Point(x: 64, y: minY), Point(x: 32, y: maxY)]
        case .trapezoid:
            // Four distinct x coordinates reject the rectangle shortcut. The
            // sloped sides have disjoint x ranges, so the contour is simple.
            return [
                Point(x: 0, y: minY), Point(x: 64, y: minY),
                Point(x: 48, y: maxY), Point(x: 16, y: maxY),
            ]
        }
    }

    private func path(for figure: Figure, minY: Double, maxY: Double) -> Path {
        let vertices = points(for: figure, minY: minY, maxY: maxY)
        var path = Path()
        path.moveTo(vertices[0])
        for point in vertices.dropFirst() { path.lineTo(point) }
        path.close()
        return path
    }

    private func primitive(
        for figure: Figure, minY: Double, maxY: Double, rule: PathFillRule, clip: Rect? = nil
    ) -> PathPrimitive {
        let path = path(for: figure, minY: minY, maxY: maxY)
        return PathPrimitive(
            elements: path.elements, bounds: path.boundingRect,
            fillColor: .white, fillRule: rule, clipBounds: clip)
    }

    private func assertImmediateFallback(
        _ figure: Figure, sign: Double, file: StaticString = #filePath, line: UInt = #line
    ) {
        let ranges: [(minY: Double, height: Double, firstStep: Double)] = [
            (sign * Self.stalledMagnitude, 16, 0),
            (sign * (Self.unitBoundary + 2), 16, 2),
            (sign * 1e19, 2048, 0),
        ]
        XCTAssertGreaterThan(abs(ranges[2].minY), Double(Int64.max), file: file, line: line)
        for range in ranges {
            XCTAssertEqual((range.minY + 1) - range.minY, range.firstStep, file: file, line: line)
            assertRejected(figure, minY: range.minY, height: range.height, file: file, line: line)
        }
    }

    private func assertCrossingFallback(
        _ figure: Figure, file: StaticString = #filePath, line: UInt = #line
    ) {
        let minY = Self.unitBoundary - 4
        var row = minY
        // A check only at the initial row misses the stall on the fifth row.
        for _ in 0..<4 {
            let next = row + 1
            XCTAssertEqual(next - row, 1, file: file, line: line)
            row = next
        }
        XCTAssertEqual(row, Self.unitBoundary, file: file, line: line)
        XCTAssertEqual(row + 1, row, file: file, line: line)
        assertRejected(figure, minY: minY, height: 16, file: file, line: line)
    }

    private func assertRejected(
        _ figure: Figure, minY: Double, height: Double,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let maxY = minY + height
        let vertices = points(for: figure, minY: minY, maxY: maxY)
        XCTAssertEqual(maxY - minY, height, file: file, line: line)
        XCTAssertEqual(GPUISceneValue.int(ceil(maxY) - floor(minY)), Int(height), file: file, line: line)
        XCTAssertLessThanOrEqual(
            height, 8192, "the existing row budget must admit this fixture", file: file, line: line)
        XCTAssertTrue(vertices.allSatisfy { $0.x.isFinite && $0.y.isFinite }, file: file, line: line)
        for index in vertices.indices {
            let a = vertices[index]
            let b = vertices[(index + 1) % vertices.count]
            let c = vertices[(index + 2) % vertices.count]
            let turn = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
            XCTAssertGreaterThan(turn, 0.001, "nondegenerate, strictly convex input", file: file, line: line)
        }
        if case .trapezoid = figure {
            XCTAssertEqual(Set(vertices.map(\.x)).count, 4, file: file, line: line)
        }
        for rule in Self.rules {
            let path = primitive(for: figure, minY: minY, maxY: maxY, rule: rule)
            XCTAssertEqual(path.bounds.size.height, height, file: file, line: line)
            XCTAssertNil(
                PathToQuadTessellator.tessellateMixed(path),
                "\(figure), y=\(minY), height=\(height), \(rule) must fall back as a whole path",
                file: file, line: line)
        }
    }

    private func promotedResults(
        _ figure: Figure, minY: Double, maxY: Double, clip: Rect? = nil,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> [PathToQuadTessellator.Result] {
        let results = try Self.rules.map { rule in
            try XCTUnwrap(
                PathToQuadTessellator.tessellateMixed(
                    primitive(for: figure, minY: minY, maxY: maxY, rule: rule, clip: clip)),
                file: file, line: line)
        }
        XCTAssertEqual(
            results[0], results[1], "both rules cover this simple contour identically", file: file, line: line)
        for result in results {
            XCTAssertNil(result.residualPath, file: file, line: line)
            XCTAssertFalse(result.quads.isEmpty, file: file, line: line)
            XCTAssertTrue(
                result.quads.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.width.isFinite && $0.height == 1 },
                file: file, line: line)
        }
        return results
    }

    private func assertOrdinaryRows(
        _ figure: Figure, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        for minY in [0.0, -32.0] {
            for result in try promotedResults(figure, minY: minY, maxY: minY + 16, file: file, line: line) {
                XCTAssertEqual(result.quads.count, 16, file: file, line: line)
                XCTAssertEqual(result.quads.map(\.y), (0..<16).map { Float(minY + Double($0)) }, file: file, line: line)
                let expectedX: [Float]
                let expectedWidth: [Float]
                switch figure {
                case .triangle:
                    expectedX = (0..<16).map { 1 + 2 * Float($0) }
                    expectedWidth = (0..<16).map { 62 - 4 * Float($0) }
                case .trapezoid:
                    expectedX = (0..<16).map { 0.5 + Float($0) }
                    expectedWidth = (0..<16).map { 63 - 2 * Float($0) }
                }
                XCTAssertEqual(result.quads.map(\.x), expectedX, file: file, line: line)
                XCTAssertEqual(result.quads.map(\.width), expectedWidth, file: file, line: line)
            }
        }
    }

    private func assertOrdinaryClippedRows(
        _ figure: Figure, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let clip = Rect(x: 0, y: 0, width: 64, height: 4)
        for result in try promotedResults(figure, minY: -4, maxY: 12, clip: clip, file: file, line: line) {
            XCTAssertEqual(result.quads.count, 4, file: file, line: line)
            XCTAssertEqual(result.quads.map(\.y), [0, 1, 2, 3], file: file, line: line)
            let expectedWidth: [Float]
            switch figure {
            case .triangle: expectedWidth = [46, 42, 38, 34]
            case .trapezoid: expectedWidth = [55, 53, 51, 49]
            }
            XCTAssertEqual(result.quads.map(\.width), expectedWidth, file: file, line: line)
        }
    }

    private func assertRepresentableProgress(
        _ figure: Figure, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        for minY in [Self.unitBoundary - 16, -Self.unitBoundary] {
            var row = minY
            for _ in 0..<16 {
                let next = row + 1
                XCTAssertEqual(next - row, 1, file: file, line: line)
                row = next
            }
            XCTAssertEqual(row, minY + 16, file: file, line: line)
            for result in try promotedResults(figure, minY: minY, maxY: row, file: file, line: line) {
                // Half-row samples can round onto the triangle's apex here.
                // Pin admission and bounded strips, not out-of-domain coverage.
                XCTAssertLessThanOrEqual(result.quads.count, 16, file: file, line: line)
            }
        }
    }

    private func assertHugeVerticesWithOrdinaryClip(
        _ figure: Figure, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let clip = Rect(x: 0, y: 0, width: 64, height: 16)
        for magnitude in [Self.stalledMagnitude, 1e19] {
            for result in try promotedResults(
                figure, minY: -magnitude, maxY: magnitude, clip: clip, file: file, line: line)
            {
                XCTAssertEqual(result.quads.count, 16, "progress is checked after clipping", file: file, line: line)
                XCTAssertEqual(result.quads.map(\.y), (0..<16).map { Float($0) }, file: file, line: line)
            }
        }
    }

    private func assertSceneFallback(
        _ figure: Figure, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let coordinateLimit = Double(GPUISceneLimits.maxCoordinate)
        for range in Self.rejectedRanges {
            for rule in Self.rules {
                let path = primitive(for: figure, minY: range.minY, maxY: range.minY + range.height, rule: rule)
                var scene = GPUIScene(clearColor: .clear)
                ScenePainter.emit(path: path, into: &scene, layerIndex: 0, displayScale: 1)
                scene.finish()

                XCTAssertTrue(
                    scene.layers.flatMap(\.quads).isEmpty, "no partial strips escape fallback", file: file, line: line)
                let paths = scene.layers.flatMap(\.paths)
                XCTAssertEqual(paths.count, 1, file: file, line: line)
                let stored = try XCTUnwrap(paths.first, file: file, line: line)
                XCTAssertEqual(stored.fillRule, rule, file: file, line: line)
                XCTAssertEqual(stored.fillColor, .white, file: file, line: line)
                XCTAssertEqual(
                    stored.bounds.origin.y, range.minY < 0 ? -coordinateLimit : coordinateLimit, file: file, line: line)
                XCTAssertEqual(stored.elements.count, path.elements.count, file: file, line: line)
                for element in stored.elements {
                    switch element {
                    case .moveTo(let point), .lineTo(let point):
                        XCTAssertTrue(point.x.isFinite && point.y.isFinite, file: file, line: line)
                        XCTAssertLessThanOrEqual(abs(point.x), coordinateLimit, file: file, line: line)
                        XCTAssertEqual(
                            point.y, range.minY < 0 ? -coordinateLimit : coordinateLimit, file: file, line: line)
                    case .close:
                        break
                    default:
                        XCTFail("a straight contour must remain straight", file: file, line: line)
                    }
                }
                XCTAssertEqual(scene.paintMetrics.pathsRasterizedOnCPU, 1, file: file, line: line)
                XCTAssertEqual(scene.paintMetrics.pathsPromotedToGPU, 0, file: file, line: line)
                XCTAssertEqual(scene.paintMetrics.quadInstancesFromPromotedPaths, 0, file: file, line: line)
                XCTAssertTrue(scene.validate().isEmpty, file: file, line: line)

                // The cache-facing entry point must sanitize the raw origin
                // before translating it into a bounded local bitmap. All y
                // coordinates collapse together; this is not geometry parity.
                let local = try XCTUnwrap(GPUIRawSceneRasterizer.rasterizePath(path), file: file, line: line)
                XCTAssertEqual(local.width, 64, file: file, line: line)
                XCTAssertEqual(Double(local.height), range.height, file: file, line: line)
                XCTAssertTrue(local.pixels.allSatisfy { $0 == 0 }, file: file, line: line)

                let bitmap = GPUIRawSceneRasterizer.rasterize(scene, size: Self.surface)
                XCTAssertEqual(bitmap.width, 16, file: file, line: line)
                XCTAssertEqual(bitmap.height, 16, file: file, line: line)
                XCTAssertTrue(
                    bitmap.pixels.allSatisfy { $0 == 0 }, "sanitized outliers remain outside the small surface",
                    file: file, line: line)
            }
        }
    }

    private func canvasSnapshot(outliers: [Path], rule: PathFillRule) -> WinSwiftUIRenderSnapshot {
        let viewport = Rect(x: 0, y: 0, width: 16, height: 16)
        let control = Path(Rect(x: 2, y: 2, width: 4, height: 4))
        let style = FillStyle(eoFill: rule == .evenOdd)
        let view = Canvas { context, _ in
            context.clip(to: viewport)
            for path in outliers { context.fill(path, with: .color(.white), style: style) }
            context.fill(control, with: .color(.white), style: style)
        }
        .frame(width: 16, height: 16)
        return WinSwiftUIRendererSnapshotter.snapshot(of: view, size: Self.surface, clearColor: .clear)
    }

    private func assertCanvasCulling(
        _ figure: Figure, file: StaticString = #filePath, line: UInt = #line
    ) {
        let outliers = Self.rejectedRanges.map { range in
            path(for: figure, minY: range.minY, maxY: range.minY + range.height)
        }
        for rule in Self.rules {
            let reference = canvasSnapshot(outliers: [], rule: rule)
            let expected = GPUIRawSceneRasterizer.rasterize(reference.scene, size: Self.surface)
            XCTAssertTrue(expected.pixels.contains { $0 != 0 }, "the visible control must draw", file: file, line: line)
            let result = canvasSnapshot(outliers: outliers, rule: rule)
            XCTAssertTrue(result.scene.layers.flatMap(\.paths).isEmpty, file: file, line: line)
            XCTAssertEqual(result.scene.layers.flatMap(\.quads).count, 1, file: file, line: line)
            XCTAssertEqual(result.scene.paintMetrics.pathsPromotedToGPU, 1, file: file, line: line)
            XCTAssertEqual(result.scene.paintMetrics.pathsRasterizedOnCPU, 0, file: file, line: line)
            XCTAssertEqual(result.scene.paintMetrics.quadInstancesFromPromotedPaths, 1, file: file, line: line)
            XCTAssertTrue(result.scene.validate().isEmpty, file: file, line: line)
            let actual = GPUIRawSceneRasterizer.rasterize(result.scene, size: Self.surface)
            XCTAssertEqual(
                actual.pixels, expected.pixels, "the explicit Canvas clip culls all outliers", file: file, line: line)
        }
    }
}
