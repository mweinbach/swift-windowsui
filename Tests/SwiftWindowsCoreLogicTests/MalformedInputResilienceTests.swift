import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI

/// Throws pathological inputs at the rendering pipeline. The contract:
/// no crashes, no infinite loops, no NaN/Inf leaking into the output
/// buffer. Each entry-point either degrades gracefully (returns nil or
/// no-op) or produces a sane bounded result.
///
/// These tests don't validate visual correctness for malformed input
/// — they only guarantee the *pipeline survives* whatever an app
/// throws at it, which is the "more robust" promise apps rely on for
/// production stability.
final class MalformedInputResilienceTests: XCTestCase {

    // MARK: - Tessellator resilience

    func testTessellatorRefusesEmptyPath() {
        let path = PathPrimitive(elements: [], bounds: .zero)
        XCTAssertNil(PathToQuadTessellator.tessellate(path))
        XCTAssertNil(PathToQuadTessellator.tessellateMixed(path))
    }

    func testTessellatorHandlesNaNCoordinatesWithoutCrashing() {
        let path = PathPrimitive(
            elements: [
                .moveTo(Point(x: .nan, y: 0)),
                .lineTo(Point(x: 50, y: .nan)),
                .close,
            ],
            bounds: Rect(x: 0, y: 0, width: 100, height: 100),
            fillColor: Color(red: 1, green: 0, blue: 0, alpha: 1)
        )
        _ = PathToQuadTessellator.tessellate(path)
        _ = PathToQuadTessellator.tessellateMixed(path)
        // No assertion — survival is the contract.
    }

    func testTessellatorHandlesInfiniteCoordinatesWithoutCrashing() {
        let path = PathPrimitive(
            elements: [
                .moveTo(Point(x: 0, y: 0)),
                .lineTo(Point(x: .infinity, y: 0)),
                .lineTo(Point(x: 0, y: .infinity)),
                .close,
            ],
            bounds: Rect(x: 0, y: 0, width: 100, height: 100),
            fillColor: Color(red: 1, green: 0, blue: 0, alpha: 1)
        )
        _ = PathToQuadTessellator.tessellate(path)
    }

    func testTessellatorRefusesSinglePointDegenerate() {
        let path = PathPrimitive(
            elements: [.moveTo(Point(x: 50, y: 50)), .close],
            bounds: .zero,
            fillColor: Color(red: 1, green: 0, blue: 0, alpha: 1)
        )
        XCTAssertNil(PathToQuadTessellator.tessellate(path))
    }

    func testTessellatorHandlesZeroRadiusArcWithoutCrashing() {
        let path = PathPrimitive(
            elements: [
                .moveTo(Point(x: 10, y: 10)),
                .arc(
                    center: Point(x: 50, y: 50), radius: 0,
                    startAngle: 0, endAngle: .pi, clockwise: false),
                .close,
            ],
            bounds: Rect(x: 0, y: 0, width: 100, height: 100),
            strokeColor: Color(red: 1, green: 0, blue: 0, alpha: 1),
            lineWidth: 2
        )
        _ = PathToQuadTessellator.tessellate(path)
    }

    func testTessellatorHandlesHugePolygonWithinReason() {
        // 500-vertex convex polygon — well-formed input that pushes
        // the fan triangulator. Must complete in bounded time without
        // pathological allocation.
        var elements: [PathElement] = [.moveTo(Point(x: 100, y: 0))]
        for i in 1..<500 {
            let angle = Double(i) / 500.0 * 2.0 * .pi
            elements.append(.lineTo(Point(x: 100 * cos(angle), y: 100 * sin(angle))))
        }
        elements.append(.close)
        let path = PathPrimitive(
            elements: elements,
            bounds: Rect(x: -100, y: -100, width: 200, height: 200),
            fillColor: Color(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        )
        let quads = PathToQuadTessellator.tessellate(path)
        XCTAssertNotNil(quads)
    }

    // MARK: - Rasterizer resilience

    func testRasterizerHandlesEmptySceneWithoutCrashing() {
        let scene = GPUIScene(clearColor: Color(red: 0, green: 0, blue: 0, alpha: 1))
        let bitmap = GPUIRawSceneRasterizer.rasterize(scene, size: IntSize(width: 50, height: 50))
        XCTAssertEqual(Int(bitmap.width), 50)
        XCTAssertEqual(Int(bitmap.height), 50)
    }

    func testRasterizerHandlesZeroSizeWithoutCrashing() {
        let scene = GPUIScene(clearColor: Color(red: 0, green: 0, blue: 0, alpha: 1))
        let bitmap = GPUIRawSceneRasterizer.rasterize(scene, size: IntSize(width: 0, height: 0))
        // Implementation clamps to at least 1×1; either is fine, just
        // mustn't crash.
        XCTAssertGreaterThanOrEqual(Int(bitmap.width), 1)
    }

    func testRasterizerHandlesQuadOutsideSurfaceBoundsWithoutCrashing() {
        var scene = GPUIScene(clearColor: Color(red: 0, green: 0, blue: 0, alpha: 1))
        scene.addQuad(
            QuadPrimitive(
                x: 1000, y: 1000, width: 50, height: 50,
                startR: 1, startG: 1, startB: 1, startA: 1,
                endR: 1, endG: 1, endB: 1, endA: 1,
                clipX: 0, clipY: 0, clipWidth: 100, clipHeight: 100
            )
        )
        scene.finish()
        _ = GPUIRawSceneRasterizer.rasterize(scene, size: IntSize(width: 100, height: 100))
    }

    func testRasterizerHandlesQuadWithNaNRotationWithoutCrashing() {
        var scene = GPUIScene(clearColor: Color(red: 0, green: 0, blue: 0, alpha: 1))
        scene.addQuad(
            QuadPrimitive(
                x: 30, y: 30, width: 20, height: 20,
                startR: 1, startG: 1, startB: 1, startA: 1,
                endR: 1, endG: 1, endB: 1, endA: 1,
                clipX: 0, clipY: 0, clipWidth: 100, clipHeight: 100,
                rotationRadians: .nan
            )
        )
        scene.finish()
        _ = GPUIRawSceneRasterizer.rasterize(scene, size: IntSize(width: 100, height: 100))
    }

    func testRasterizerHandlesHugeBlurRadiusWithoutHanging() {
        var scene = GPUIScene(clearColor: Color(red: 0, green: 0, blue: 0, alpha: 1))
        scene.addQuad(
            QuadPrimitive(
                x: 10, y: 10, width: 20, height: 20,
                startR: 1, startG: 1, startB: 1, startA: 1,
                endR: 1, endG: 1, endB: 1, endA: 1,
                clipX: 0, clipY: 0, clipWidth: 50, clipHeight: 50,
                blurRadius: 200  // way larger than the quad
            )
        )
        scene.finish()
        let bitmap = GPUIRawSceneRasterizer.rasterize(scene, size: IntSize(width: 50, height: 50))
        XCTAssertEqual(Int(bitmap.width), 50)
    }

    // MARK: - Scene graph resilience

    func testSceneAddPathHandlesNegativeWidthHeightWithoutCrashing() {
        let path = PathPrimitive(
            elements: [
                .moveTo(Point(x: 0, y: 0)),
                .lineTo(Point(x: 10, y: 0)),
                .lineTo(Point(x: 5, y: 10)),
                .close,
            ],
            bounds: Rect(x: 50, y: 50, width: -20, height: -20),  // negative
            fillColor: Color(red: 1, green: 1, blue: 1, alpha: 1)
        )
        _ = PathToQuadTessellator.tessellate(path)
    }

    func testTessellatorHandlesDeeplyNestedClosePathsWithoutHanging() {
        // 100 redundant close commands — the parser must accept and
        // not iterate forever.
        var elements: [PathElement] = [
            .moveTo(Point(x: 0, y: 0)),
            .lineTo(Point(x: 30, y: 0)),
            .lineTo(Point(x: 30, y: 30)),
            .lineTo(Point(x: 0, y: 30)),
        ]
        for _ in 0..<100 { elements.append(.close) }
        let path = PathPrimitive(
            elements: elements,
            bounds: Rect(x: 0, y: 0, width: 30, height: 30),
            fillColor: Color(red: 1, green: 1, blue: 1, alpha: 1)
        )
        _ = PathToQuadTessellator.tessellate(path)
    }

    func testTessellatorHandlesCurveWithCoincidentControlPointsWithoutCrashing() {
        let path = PathPrimitive(
            elements: [
                .moveTo(Point(x: 0, y: 0)),
                .cubicCurveTo(
                    control1: Point(x: 0, y: 0),
                    control2: Point(x: 0, y: 0),
                    end: Point(x: 0, y: 0)),
                .close,
            ],
            bounds: .zero,
            strokeColor: Color(red: 1, green: 0, blue: 0, alpha: 1),
            lineWidth: 1
        )
        _ = PathToQuadTessellator.tessellate(path)
    }
}
