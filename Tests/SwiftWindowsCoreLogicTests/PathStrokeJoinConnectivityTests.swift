import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI

/// Connected stroke interiors have exact coverage even when the exterior
/// difference between a bevel and a round/miter join is below tolerance.
/// Literal polylines keep these oracles independent of Arc's producer.
@MainActor
final class PathStrokeJoinConnectivityTests: XCTestCase {
    private static let size = IntSize(width: 64, height: 64)
    private static let shallow = [Point(x: 16, y: 16), Point(x: 32, y: 17), Point(x: 48, y: 16)]
    private static let joins: [StrokeStyle.LineJoin] = [.miter, .round, .bevel]

    func testShallowOpaqueMiterConnectsBothSegmentBodies() async {
        let bitmap = raster(path(Self.shallow))
        // The two directions have slopes +1/16 and -1/16. Omitting their
        // connector removes 1/32 of each outward pixel below the vertex,
        // although both complete pixels lie inside the requested join.
        assertBlue(bitmap, at: [(31, 17), (32, 17), (32, 16)])
        assertClear(bitmap, at: [(32, 20)])
    }

    func testShallowRoundAndBevelKeepConnectedInteriors() async {
        for join in [StrokeStyle.LineJoin.round, .bevel] {
            let bitmap = raster(path(Self.shallow, join: join))
            assertBlue(bitmap, at: [(31, 17), (32, 17), (32, 16)])
            assertClear(bitmap, at: [(32, 20)])
        }
    }

    func testShallowTranslucentJoinsBlendOnce() async {
        for join in Self.joins {
            let bitmap = raster(path(Self.shallow, join: join, alpha: 0.5))
            // The connector belongs to the same coverage union. Painting
            // it separately would also change the fully covered overlap.
            assertBlue(bitmap, at: [(31, 17), (32, 17), (32, 16), (24, 16)], alpha: 128)
            assertClear(bitmap, at: [(32, 20)])
        }
    }

    func testMirroredAndReversedShallowTurnsKeepCoverage() async {
        let mirrored = [Point(x: 16, y: 48), Point(x: 32, y: 47), Point(x: 48, y: 48)]
        for join in Self.joins {
            for reversed in [false, true] {
                let lower = reversed ? Array(Self.shallow.reversed()) : Self.shallow
                let upper = reversed ? Array(mirrored.reversed()) : mirrored
                assertBlue(raster(path(lower, join: join)), at: [(31, 17), (32, 17)])
                let upperBitmap = raster(path(upper, join: join))
                assertBlue(upperBitmap, at: [(31, 46), (32, 46)])
                assertClear(upperBitmap, at: [(32, 43)])
            }
        }
    }

    func testClosedSubpathConnectsItsClosingJoin() async {
        // The shallow corner is the starting vertex, so only the closing
        // join connects it. The distant top edge cannot cover these probes.
        let points = [
            Point(x: 32, y: 33), Point(x: 16, y: 32), Point(x: 16, y: 8),
            Point(x: 48, y: 8), Point(x: 48, y: 32),
        ]
        for join in Self.joins {
            let bitmap = raster(path(points, closed: true, join: join))
            assertBlue(bitmap, at: [(31, 33), (32, 33)])
            assertClear(bitmap, at: [(32, 36), (32, 20)])
        }
    }

    func testCollinearVerticesPreserveButtCapsAndSingleBlend() async {
        let plain = path([Point(x: 12, y: 32), Point(x: 52, y: 32)], alpha: 0.5)
        let split = path(
            [Point(x: 12, y: 32), Point(x: 32, y: 32), Point(x: 32, y: 32), Point(x: 52, y: 32)],
            alpha: 0.5)
        let bitmap = raster(split)
        assertBlue(bitmap, at: [(12, 32), (31, 31), (32, 31), (51, 32)], alpha: 128)
        assertClear(bitmap, at: [(11, 32), (52, 32), (32, 29)])
        XCTAssertEqual(bitmap.pixels, raster(plain).pixels)

        // A reversal still gets its visible round disc before the exact
        // collinearity guard. Miter resolves to bevel and adds no spike.
        let reversed = [Point(x: 12, y: 32), Point(x: 32, y: 32), Point(x: 12, y: 32)]
        for join in Self.joins {
            let reversedBitmap = raster(path(reversed, join: join))
            assertBlue(reversedBitmap, at: [(30, 31)])
            if join == .round {
                assertBlue(reversedBitmap, at: [(32, 31)])
            } else {
                assertClear(reversedBitmap, at: [(32, 31)])
            }
        }
    }

    func testVisibleRoundBevelAndMiterKeepDistinctOuterGeometry() async {
        let points = [Point(x: 8, y: 32), Point(x: 32, y: 32), Point(x: 32, y: 56)]
        for join in Self.joins {
            let bitmap = raster(path(points, join: join, width: 16))
            assertBlue(bitmap, at: [(33, 28)])
            // This whole pixel is inside the radius8 round join but beyond
            // the bevel's x + outwardY <= 8 chord. Its farthest radius is
            // sqrt(61), also inside the sampled disc's inscribed radius.
            if join == .bevel {
                assertClear(bitmap, at: [(36, 26)])
            } else {
                assertBlue(bitmap, at: [(36, 26)])
            }
            // Only the miter reaches this square corner. The entire pixel
            // is outside the radius8 circle and the bevel triangle.
            if join == .miter {
                assertBlue(bitmap, at: [(38, 25)])
            } else {
                assertClear(bitmap, at: [(38, 25)])
            }
        }
    }

    func testPromotedAndRawShallowStrokeInteriorsAgree() async {
        for join in Self.joins {
            let source = path(Self.shallow, join: join)
            var promoted = GPUIScene(clearColor: .clear)
            ScenePainter.emit(path: source, into: &promoted, layerIndex: 0, displayScale: 1)
            promoted.finish()
            XCTAssertTrue(promoted.validate().isEmpty)
            XCTAssertEqual(promoted.paintMetrics.pathsPromotedToGPU, 1)
            XCTAssertEqual(promoted.paintMetrics.pathsRasterizedOnCPU, 0)
            XCTAssertEqual(promoted.paintMetrics.quadInstancesFromPromotedPaths, 2)
            // Opaque interiors have the same independent oracle on both
            // routes. This does not assert full-image or native GPU parity.
            let promotedBitmap = GPUIRawSceneRasterizer.rasterize(promoted, size: Self.size)
            assertBlue(promotedBitmap, at: [(31, 17), (32, 17)])
            assertClear(promotedBitmap, at: [(32, 20)])
            assertBlue(raster(source), at: [(31, 17), (32, 17)])
        }
    }

    private func path(
        _ points: [Point], closed: Bool = false, join: StrokeStyle.LineJoin = .miter,
        alpha: Float = 1, width: Double = 4
    ) -> PathPrimitive {
        var elements = points.enumerated().map { index, point in
            index == 0 ? PathElement.moveTo(point) : .lineTo(point)
        }
        if closed { elements.append(.close) }
        return PathPrimitive(
            elements: elements, bounds: Rect(x: 0, y: 0, width: 64, height: 64),
            strokeColor: Color(red: 0, green: 0, blue: 1, alpha: alpha), lineWidth: width,
            lineCap: .butt, lineJoin: join, miterLimit: 10)
    }

    private func raster(_ path: PathPrimitive) -> BitmapSurface {
        var scene = GPUIScene(clearColor: .clear)
        scene.addPath(path, toLayer: 0)
        scene.finish()
        XCTAssertTrue(scene.validate().isEmpty)
        return GPUIRawSceneRasterizer.rasterize(scene, size: Self.size)
    }

    private func assertBlue(
        _ bitmap: BitmapSurface, at points: [(Int, Int)], alpha: UInt8 = 255,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        assertPixels(bitmap, at: points, expected: [255, 0, 0, alpha], file: file, line: line)
    }

    private func assertClear(
        _ bitmap: BitmapSurface, at points: [(Int, Int)], file: StaticString = #filePath, line: UInt = #line
    ) {
        assertPixels(bitmap, at: points, expected: [0, 0, 0, 0], file: file, line: line)
    }

    private func assertPixels(
        _ bitmap: BitmapSurface, at points: [(Int, Int)], expected: [UInt8],
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(bitmap.width, Self.size.width, file: file, line: line)
        XCTAssertEqual(bitmap.height, Self.size.height, file: file, line: line)
        for (x, y) in points {
            guard x >= 0, y >= 0, x < Int(bitmap.width), y < Int(bitmap.height) else {
                XCTFail("probe is outside its fixed surface", file: file, line: line)
                continue
            }
            let offset = y * Int(bitmap.bytesPerRow) + x * 4
            XCTAssertEqual(
                Array(bitmap.pixels[offset..<(offset + 4)]), expected,
                "exact BGRA at (\(x), \(y))", file: file, line: line)
        }
    }
}
