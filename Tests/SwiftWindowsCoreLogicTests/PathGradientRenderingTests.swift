import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsRendererD3D11

/// Path gradients are rasterized once into the same cached bitmap consumed by
/// the shipping D3D11 backend and the CPU reference renderer. Their coordinate
/// frame therefore has to survive placement, clipping and cache normalization.
@MainActor
final class PathGradientRenderingTests: XCTestCase {
    private static let size = IntSize(width: 128, height: 128)
    private static let red = Color(red: 1, green: 0, blue: 0, alpha: 1)
    private static let green = Color(red: 0, green: 1, blue: 0, alpha: 1)
    private static let blue = Color(red: 0, green: 0, blue: 1, alpha: 1)

    private func rectangle(
        bounds: Rect,
        fillColor: Color = .clear,
        fillGradient: LinearGradient? = nil,
        strokeColor: Color = .clear,
        strokeGradient: LinearGradient? = nil,
        lineWidth: Double = 0
    ) -> PathPrimitive {
        PathPrimitive(
            elements: [
                .moveTo(Point(x: bounds.minX, y: bounds.minY)),
                .lineTo(Point(x: bounds.maxX, y: bounds.minY)),
                .lineTo(Point(x: bounds.maxX, y: bounds.maxY)),
                .lineTo(Point(x: bounds.minX, y: bounds.maxY)),
                .close,
            ],
            bounds: bounds,
            fillColor: fillColor,
            fillGradient: fillGradient,
            strokeColor: strokeColor,
            strokeGradient: strokeGradient,
            lineWidth: lineWidth)
    }

    private func scene(for path: PathPrimitive, clearColor: Color = .black) -> GPUIScene {
        var scene = GPUIScene(clearColor: clearColor)
        scene.addPath(path, toLayer: 0)
        scene.finish()
        return scene
    }

    private func raster(_ path: PathPrimitive, clearColor: Color = .black) -> BitmapSurface {
        GPUIRawSceneRasterizer.rasterize(scene(for: path, clearColor: clearColor), size: Self.size)
    }

    private func pixel(_ surface: BitmapSurface, x: Int, y: Int) -> (red: Int, green: Int, blue: Int, alpha: Int) {
        let offset = y * Int(surface.bytesPerRow) + x * 4
        return (
            red: Int(surface.pixels[offset + 2]),
            green: Int(surface.pixels[offset + 1]),
            blue: Int(surface.pixels[offset]),
            alpha: Int(surface.pixels[offset + 3])
        )
    }

    private func redBlueGradient(axis: GradientAxis = .horizontal) -> LinearGradient {
        LinearGradient(startColor: Self.red, endColor: Self.blue, axis: axis)
    }

    func testFillGradientPreservesIntermediateStopAtItsAuthoredLocation() async {
        let gradient = LinearGradient(
            stops: [
                GradientStop(color: Self.red, position: 0),
                GradientStop(color: Self.green, position: 0.25),
                GradientStop(color: Self.blue, position: 1),
            ], axis: .horizontal)
        let bitmap = raster(
            rectangle(bounds: Rect(x: 8, y: 12, width: 100, height: 64), fillGradient: gradient))

        XCTAssertGreaterThan(pixel(bitmap, x: 8, y: 36).red, 245)
        XCTAssertGreaterThan(pixel(bitmap, x: 33, y: 36).green, 245)
        XCTAssertLessThan(pixel(bitmap, x: 33, y: 36).red, 12)
        XCTAssertGreaterThan(pixel(bitmap, x: 106, y: 36).blue, 245)
    }

    func testDisplacedStopsExtendEndpointColorsAcrossPathBounds() async {
        let gradient = LinearGradient(
            stops: [
                GradientStop(color: Self.red, position: 0.25),
                GradientStop(color: Self.blue, position: 0.75),
            ], axis: .horizontal)
        let bitmap = raster(
            rectangle(bounds: Rect(x: 10, y: 10, width: 100, height: 60), fillGradient: gradient))

        XCTAssertEqual(pixel(bitmap, x: 18, y: 35).red, 255)
        XCTAssertEqual(pixel(bitmap, x: 18, y: 35).blue, 0)
        XCTAssertEqual(pixel(bitmap, x: 101, y: 35).red, 0)
        XCTAssertEqual(pixel(bitmap, x: 101, y: 35).blue, 255)
    }

    func testDuplicateStopPositionsProduceHardTransitionWithoutSeam() async {
        let gradient = LinearGradient(
            stops: [
                GradientStop(color: Self.red, position: 0),
                GradientStop(color: Self.red, position: 0.5),
                GradientStop(color: Self.blue, position: 0.5),
                GradientStop(color: Self.blue, position: 1),
            ], axis: .horizontal)
        let bitmap = raster(
            rectangle(bounds: Rect(x: 10, y: 10, width: 100, height: 60), fillGradient: gradient))

        XCTAssertEqual(pixel(bitmap, x: 59, y: 35).red, 255)
        XCTAssertEqual(pixel(bitmap, x: 59, y: 35).blue, 0)
        XCTAssertEqual(pixel(bitmap, x: 60, y: 35).red, 0)
        XCTAssertEqual(pixel(bitmap, x: 60, y: 35).blue, 255)
    }

    func testReversedAuthoredStopsKeepTheirMirroredLocations() async {
        let gradient = LinearGradient(
            stops: [
                GradientStop(color: Self.blue, position: 0),
                GradientStop(color: Self.green, position: 0.75),
                GradientStop(color: Self.red, position: 1),
            ], axis: .horizontal, reversesAuthoredStops: true)
        let bitmap = raster(
            rectangle(bounds: Rect(x: 10, y: 10, width: 100, height: 60), fillGradient: gradient))

        XCTAssertGreaterThan(pixel(bitmap, x: 12, y: 35).blue, 245)
        XCTAssertGreaterThan(pixel(bitmap, x: 85, y: 35).green, 245)
        XCTAssertGreaterThan(pixel(bitmap, x: 108, y: 35).red, 235)
    }

    func testTransparentFirstStopDoesNotSuppressVisibleFill() async {
        let transparentRed = Color(red: 1, green: 0, blue: 0, alpha: 0)
        let gradient = LinearGradient(startColor: transparentRed, endColor: Self.blue, axis: .horizontal)
        let bitmap = raster(
            rectangle(
                bounds: Rect(x: 8, y: 8, width: 100, height: 64),
                fillColor: transparentRed,
                fillGradient: gradient))

        XCTAssertLessThan(pixel(bitmap, x: 10, y: 36).blue, 12)
        XCTAssertGreaterThan(pixel(bitmap, x: 103, y: 36).blue, 225)
    }

    func testTranslucentSegmentsCompositeEachCoveredPixelOnlyOnce() async {
        let translucent = Color(red: 1, green: 0, blue: 0, alpha: 0.4)
        let gradient = LinearGradient(
            stops: [
                GradientStop(color: translucent, position: 0),
                GradientStop(color: translucent, position: 0.5),
                GradientStop(color: translucent, position: 1),
            ], axis: .horizontal)
        let bitmap = raster(
            rectangle(bounds: Rect(x: 0, y: 8, width: 101, height: 64), fillGradient: gradient))

        XCTAssertEqual(pixel(bitmap, x: 49, y: 32).red, 102, accuracy: 1)
        XCTAssertEqual(pixel(bitmap, x: 50, y: 32).red, 102, accuracy: 1)
        XCTAssertEqual(pixel(bitmap, x: 51, y: 32).red, 102, accuracy: 1)
    }

    func testStrokeGradientSamplesOneContinuousPathWideRamp() async {
        let path = PathPrimitive(
            elements: [
                .moveTo(Point(x: 16, y: 16)),
                .lineTo(Point(x: 16, y: 80)),
            ],
            bounds: Rect(x: 12, y: 12, width: 8, height: 72),
            strokeColor: Self.red,
            strokeGradient: redBlueGradient(axis: .vertical),
            lineWidth: 8,
            lineCap: .round)
        let bitmap = raster(path)

        XCTAssertGreaterThan(pixel(bitmap, x: 16, y: 18).red, 225)
        XCTAssertLessThan(pixel(bitmap, x: 16, y: 18).blue, 30)
        XCTAssertGreaterThan(pixel(bitmap, x: 16, y: 76).blue, 220)
    }

    func testTransparentFirstStopDoesNotSuppressVisibleStroke() async {
        let transparent = Color(red: 1, green: 0, blue: 0, alpha: 0)
        let gradient = LinearGradient(startColor: transparent, endColor: Self.blue, axis: .horizontal)
        let path = PathPrimitive(
            elements: [.moveTo(Point(x: 12, y: 40)), .lineTo(Point(x: 108, y: 40))],
            bounds: Rect(x: 8, y: 36, width: 104, height: 8),
            strokeColor: transparent,
            strokeGradient: gradient,
            lineWidth: 8,
            lineCap: .round)

        XCTAssertGreaterThan(pixel(raster(path), x: 102, y: 40).blue, 210)
    }

    func testTranslatedGradientMovesWithItsPathAndKeepsCacheIdentity() async {
        let original = rectangle(
            bounds: Rect(x: 4, y: 8, width: 40, height: 24),
            fillGradient: redBlueGradient())
        let offset = Point(x: 52, y: 32)
        let translated = original.translated(by: offset)

        let originalPixel = pixel(raster(original), x: 14, y: 18)
        let translatedPixel = pixel(raster(translated), x: 66, y: 50)
        XCTAssertEqual(originalPixel.red, translatedPixel.red)
        XCTAssertEqual(originalPixel.blue, translatedPixel.blue)
        XCTAssertEqual(original.shapeHash, translated.shapeHash)
        XCTAssertTrue(translated.matchesShapeAndPaint(of: original, translatedBy: offset))
    }

    func testScaledGradientPreservesNormalizedStopLocations() async {
        let original = rectangle(
            bounds: Rect(x: 4, y: 4, width: 40, height: 20),
            fillGradient: redBlueGradient())
        let scaled = original.scaled(by: 2)
        let originalPixel = pixel(raster(original), x: 14, y: 12)
        let scaledPixel = pixel(raster(scaled), x: 29, y: 24)

        XCTAssertEqual(originalPixel.red, scaledPixel.red, accuracy: 3)
        XCTAssertEqual(originalPixel.blue, scaledPixel.blue, accuracy: 3)
    }

    func testRotatedGradientTurnsWithTheCoveredShape() async {
        let path = rectangle(
            bounds: Rect(x: 24, y: 40, width: 64, height: 24),
            fillGradient: redBlueGradient())
        let rotated = path.rotated(by: .pi / 2, about: Point(x: 56, y: 52))
        let bitmap = raster(rotated)

        XCTAssertGreaterThan(pixel(bitmap, x: 56, y: 24).red, 230)
        XCTAssertLessThan(pixel(bitmap, x: 56, y: 24).blue, 25)
        XCTAssertGreaterThan(pixel(bitmap, x: 56, y: 80).blue, 225)
        XCTAssertLessThan(pixel(bitmap, x: 56, y: 80).red, 35)
    }

    func testGradientStopsAndDirectionParticipateInPathCacheIdentity() async {
        let original = rectangle(
            bounds: Rect(x: 8, y: 8, width: 64, height: 48),
            fillGradient: redBlueGradient())
        var recolored = original
        recolored.fillGradient?.stops[1].color = Self.green
        var redirected = original
        redirected.fillGradient?.axis = .vertical

        XCTAssertNotEqual(original.shapeHash, recolored.shapeHash)
        XCTAssertFalse(original.matchesShapeAndPaint(of: recolored, translatedBy: .zero))
        XCTAssertNotEqual(original.shapeHash, redirected.shapeHash)
        XCTAssertFalse(original.matchesShapeAndPaint(of: redirected, translatedBy: .zero))
    }

    func testMalformedAndExcessiveGradientStopsAreBoundedAtSceneBoundary() async throws {
        var stops = [
            GradientStop(color: Color(red: .nan, green: .infinity, blue: -1, alpha: 2), position: .nan),
            GradientStop(color: Color(red: .nan, green: .infinity, blue: -1, alpha: 2), position: -1),
        ]
        for index in 0..<256 {
            stops.append(GradientStop(color: Self.blue, position: Float(index) / 255))
        }
        let path = rectangle(
            bounds: Rect(x: 4, y: 4, width: 96, height: 64),
            fillGradient: LinearGradient(stops: stops, axis: .horizontal))
        let stored = try XCTUnwrap(scene(for: path).layers.first?.paths.first?.fillGradient)

        XCTAssertLessThanOrEqual(stored.stops.count, LinearGradient.maximumRenderedStops)
        for stop in stored.stops {
            XCTAssertTrue(stop.position.isFinite)
            XCTAssertGreaterThanOrEqual(stop.position, 0)
            XCTAssertLessThanOrEqual(stop.position, 1)
            XCTAssertTrue(stop.color.red.isFinite)
            XCTAssertTrue(stop.color.green.isFinite)
            XCTAssertTrue(stop.color.blue.isFinite)
            XCTAssertTrue(stop.color.alpha.isFinite)
            XCTAssertGreaterThanOrEqual(stop.color.alpha, 0)
            XCTAssertLessThanOrEqual(stop.color.alpha, 1)
        }
    }

    func testD3D11CachedPathMatchesCPUMultistopGradientPixels() async throws {
        let gradient = LinearGradient(
            stops: [
                GradientStop(color: Self.red, position: 0),
                GradientStop(color: Self.green, position: 0.3),
                GradientStop(color: Self.blue, position: 1),
            ], axis: .horizontal)
        let path = rectangle(
            bounds: Rect(x: 12, y: 18, width: 100, height: 72),
            fillGradient: gradient)
        let scene = scene(for: path)
        let cpu = GPUIRawSceneRasterizer.rasterize(scene, size: Self.size)
        let gpu = try WARPBatchRenderer.render(scene, size: Self.size)
        let report = comparePixels(gpu, cpu, tolerance: 4)

        XCTAssertGreaterThan(
            report.matchRatio, 0.995,
            "cached path gradients diverged across backends: ratio=\(report.matchRatio), "
                + "maxDelta=\(report.maxChannelDelta)")
    }

    func testWindowedD3D11PathSamplesOriginalGradientCoordinates() async throws {
        let gradient = LinearGradient(
            stops: [
                GradientStop(color: Self.red, position: 0),
                GradientStop(color: Self.green, position: 0.5),
                GradientStop(color: Self.blue, position: 1),
            ], axis: .vertical)
        var path = rectangle(
            bounds: Rect(x: 8, y: -9_952, width: 96, height: 20_000),
            fillGradient: gradient)
        path.clipBounds = Rect(x: 8, y: 8, width: 96, height: 96)
        let scene = scene(for: path)
        let cpu = GPUIRawSceneRasterizer.rasterize(scene, size: Self.size)
        let gpu = try WARPBatchRenderer.render(scene, size: Self.size)
        let report = comparePixels(gpu, cpu, tolerance: 5)

        XCTAssertGreaterThan(pixel(cpu, x: 48, y: 48).green, 245)
        XCTAssertGreaterThan(pixel(gpu, x: 48, y: 48).green, 245)
        XCTAssertGreaterThan(
            report.matchRatio, 0.99,
            "window normalization changed the gradient coordinate frame: "
                + "ratio=\(report.matchRatio), maxDelta=\(report.maxChannelDelta)")
    }

    func testD3D11CacheHitsTranslatedGradientButMissesChangedStops() async throws {
        let renderer = D3D11BatchRenderer()
        do {
            try renderer.attachOffscreen(size: Self.size, driver: .warpFirst)
        } catch {
            throw XCTSkip("D3D11 batch renderer unavailable on this machine: \(error)")
        }
        defer { renderer.detach() }

        func renderThroughGPU(_ path: PathPrimitive) throws {
            let scene = scene(for: path)
            renderer.bindResources(for: scene)
            try renderer.render(scene: scene)
        }

        let original = rectangle(
            bounds: Rect(x: 8, y: 12, width: 64, height: 48),
            fillGradient: redBlueGradient())
        try renderThroughGPU(original)
        try renderThroughGPU(original.translated(by: Point(x: 20, y: 16)))

        XCTAssertEqual(renderer.pathCacheMisses, 1)
        XCTAssertEqual(renderer.pathCacheHits, 1)

        var recolored = original
        recolored.fillGradient?.stops[1].color = Self.green
        try renderThroughGPU(recolored)

        XCTAssertEqual(renderer.pathCacheMisses, 2)
        XCTAssertEqual(renderer.pathCacheEntryCountForTesting, 2)
    }
}
