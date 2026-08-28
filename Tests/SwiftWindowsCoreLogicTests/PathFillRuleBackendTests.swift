import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsRendererD3D11

/// The fill rule is paint state: placement, replay, frame degradation and
/// cached D3D11 rasters must preserve its visible holes as well as its value.
@MainActor
final class PathFillRuleBackendTests: XCTestCase {
    private static let surface = IntSize(width: 128, height: 128)
    private static let outerBounds = Rect(x: 8, y: 8, width: 80, height: 80)
    private static let red = Color(red: 1, green: 0, blue: 0, alpha: 1)
    private static let green = Color(red: 0, green: 1, blue: 0, alpha: 1)
    private static let translucentRed = Color(red: 1, green: 0, blue: 0, alpha: 0.5)

    func testPrimitiveAndFrameCommandDefaultToNonZeroFilling() async {
        let primitive = PathPrimitive(
            elements: nestedElements(), bounds: Self.outerBounds, fillColor: Self.green)
        let command = FillPathCommand(path: nestedRenderPath(), color: Self.green)

        XCTAssertEqual(primitive.fillRule, .nonZero)
        XCTAssertEqual(command.fillRule, .nonZero)
        let primitivePixels = raster(primitive)
        let framePixels = GPUIRawSceneRasterizer.rasterize(
            RenderFrame(clearColor: .clear, commands: [.fillPath(command)]), size: Self.surface)

        for bitmap in [primitivePixels, framePixels] {
            XCTAssertEqual(pixel(bitmap, x: 48, y: 48).alpha, 255, "the default fills the nested overlap")
            XCTAssertEqual(pixel(bitmap, x: 20, y: 48).alpha, 255)
            XCTAssertEqual(pixel(bitmap, x: 4, y: 48).alpha, 0)
        }
        XCTAssertEqual(primitivePixels.pixels, framePixels.pixels)
    }

    func testEvenOddDistinguishesSameWindingNestedContoursFromNonZero() async {
        let nonZero = raster(nestedPath(fillRule: .nonZero))
        let evenOdd = raster(nestedPath(fillRule: .evenOdd))

        XCTAssertEqual(pixel(nonZero, x: 48, y: 48).alpha, 255)
        XCTAssertEqual(pixel(evenOdd, x: 48, y: 48).alpha, 0, "two crossings make a hole under even-odd")
        for bitmap in [nonZero, evenOdd] {
            XCTAssertEqual(pixel(bitmap, x: 20, y: 48).alpha, 255, "the surrounding ring must still paint")
            XCTAssertEqual(pixel(bitmap, x: 4, y: 48).alpha, 0)
        }
        XCTAssertNotEqual(evenOdd.pixels, nonZero.pixels)
    }

    func testOppositeWindingContoursRemainHolesForBothRules() async {
        let nonZero = raster(nestedPath(fillRule: .nonZero, reverseInner: true))
        let evenOdd = raster(nestedPath(fillRule: .evenOdd, reverseInner: true))

        for bitmap in [nonZero, evenOdd] {
            XCTAssertEqual(pixel(bitmap, x: 48, y: 48).alpha, 0)
            XCTAssertEqual(pixel(bitmap, x: 20, y: 48).alpha, 255)
        }
        XCTAssertEqual(evenOdd.pixels, nonZero.pixels)
    }

    func testEvenOddImplicitlyClosesEachSubpath() async {
        let explicit = raster(nestedPath(fillRule: .evenOdd))
        let implicit = raster(nestedPath(fillRule: .evenOdd, closeSubpaths: false))

        XCTAssertEqual(pixel(implicit, x: 48, y: 48).alpha, 0)
        XCTAssertEqual(pixel(implicit, x: 20, y: 48).alpha, 255)
        XCTAssertEqual(implicit.pixels, explicit.pixels, "each open contour needs its own implicit closing edge")
    }

    func testTranslatedPrimitiveRetainsFillRuleAndPaint() async {
        var original = nestedPath(fillRule: .evenOdd, fillColor: Self.translucentRed)
        original.clipBounds = Rect(x: 16, y: 8, width: 64, height: 80)
        let offset = Point(x: 12, y: 18)
        let translated = original.translated(by: offset)

        XCTAssertEqual(original.fillRule, .evenOdd)
        XCTAssertEqual(translated.fillRule, .evenOdd)
        XCTAssertEqual(translated.fillColor, original.fillColor)
        XCTAssertEqual(translated.bounds, Rect(x: 20, y: 26, width: 80, height: 80))
        XCTAssertEqual(translated.clipBounds, Rect(x: 28, y: 26, width: 64, height: 80))
        XCTAssertEqual(translated.shapeHash, original.shapeHash)
        XCTAssertTrue(translated.matchesShapeAndPaint(of: original, translatedBy: offset))

        let bitmap = raster(translated)
        XCTAssertEqual(pixel(bitmap, x: 60, y: 66).alpha, 0)
        XCTAssertEqual(pixel(bitmap, x: 32, y: 66).alpha, 128, accuracy: 1)
        XCTAssertEqual(pixel(bitmap, x: 24, y: 66).alpha, 0, "the translated clip remains a draw restriction")
    }

    func testFractionallyScaledPrimitiveRetainsFillRuleAndClip() async {
        var original = nestedPath(fillRule: .evenOdd)
        original.clipBounds = Rect(x: 16, y: 8, width: 64, height: 80)
        original.clipCornerRadius = 4
        let scaled = original.scaled(by: 1.25)

        XCTAssertEqual(original.scaled(by: 1), original)
        XCTAssertEqual(scaled.fillRule, .evenOdd)
        XCTAssertEqual(scaled.bounds, Rect(x: 10, y: 10, width: 100, height: 100))
        XCTAssertEqual(scaled.clipBounds, Rect(x: 20, y: 10, width: 80, height: 100))
        XCTAssertEqual(scaled.clipCornerRadius, 5)

        let bitmap = raster(scaled)
        XCTAssertEqual(pixel(bitmap, x: 60, y: 60).alpha, 0)
        XCTAssertEqual(pixel(bitmap, x: 25, y: 60).alpha, 255)
        XCTAssertEqual(pixel(bitmap, x: 14, y: 60).alpha, 0)
    }

    func testRotatedPrimitiveRetainsFillRuleAndScreenSpaceClip() async {
        var original = nestedPath(fillRule: .evenOdd)
        let clip = Rect(x: 16, y: 0, width: 96, height: 96)
        original.clipBounds = clip
        let rotated = original.rotated(by: .pi / 4, about: Point(x: 48, y: 48))

        XCTAssertEqual(original.rotated(by: 0, about: Point(x: 48, y: 48)), original)
        XCTAssertEqual(rotated.fillRule, .evenOdd)
        XCTAssertEqual(rotated.clipBounds, clip, "rotation must not rotate the screen-space clip")
        XCTAssertGreaterThan(rotated.bounds.width, original.bounds.width)

        let bitmap = raster(rotated)
        XCTAssertEqual(pixel(bitmap, x: 48, y: 48).alpha, 0)
        XCTAssertEqual(pixel(bitmap, x: 48, y: 12).alpha, 255)
        XCTAssertEqual(pixel(bitmap, x: 12, y: 48).alpha, 0)
    }

    func testClippedLocalRasterRetainsFillRule() async throws {
        let original = nestedPath(fillRule: .evenOdd)
        var bounded = original
        bounded.bounds = bounded.bounds.outset(by: 4)
        bounded.clipBounds = Rect(x: 16, y: 8, width: 64, height: 80)
        let bitmap = try XCTUnwrap(GPUIRawSceneRasterizer.rasterizePath(bounded))

        XCTAssertEqual(original.bounds, Self.outerBounds)
        XCTAssertEqual(bounded.fillRule, .evenOdd)
        XCTAssertEqual(bitmap.width, 64)
        XCTAssertEqual(bitmap.height, 80)
        // The local bitmap starts at the clip's (16, 8), not at the path's
        // widened bounds or the original scene origin.
        XCTAssertEqual(pixel(bitmap, x: 32, y: 40).alpha, 0)
        XCTAssertEqual(pixel(bitmap, x: 4, y: 40).alpha, 255)
    }

    func testRuleSeparatesShapeHashesAndExactCacheComparisons() async {
        let nonZero = nestedPath(fillRule: .nonZero)
        let evenOdd = nestedPath(fillRule: .evenOdd)
        let offset = Point(x: 20, y: 16)
        let translated = evenOdd.translated(by: offset)

        XCTAssertEqual(nonZero.elements, evenOdd.elements)
        XCTAssertEqual(nonZero.bounds, evenOdd.bounds)
        XCTAssertNotEqual(nonZero, evenOdd)
        XCTAssertNotEqual(nonZero.shapeHash, evenOdd.shapeHash)
        XCTAssertFalse(nonZero.matchesShapeAndPaint(of: evenOdd, translatedBy: .zero))
        XCTAssertFalse(evenOdd.matchesShapeAndPaint(of: nonZero, translatedBy: .zero))
        XCTAssertEqual(translated.shapeHash, evenOdd.shapeHash)
        XCTAssertTrue(translated.matchesShapeAndPaint(of: evenOdd, translatedBy: offset))
        XCTAssertFalse(translated.matchesShapeAndPaint(of: nonZero, translatedBy: offset))
    }

    func testSceneReplayPreservesFillRulesAndVisiblePaintOrder() async {
        var original = GPUIScene(clearColor: .clear)
        original.addPath(nestedPath(fillRule: .nonZero, fillColor: Self.red), toLayer: 0)
        original.addPath(nestedPath(fillRule: .evenOdd, fillColor: Self.green), toLayer: 0)
        original.finish()
        var replayed = GPUIScene(clearColor: .clear)

        XCTAssertEqual(replayed.replay(0..<original.paintRecordCount, from: original), .success)
        replayed.finish()
        XCTAssertEqual(replayed.layers.flatMap(\.paths).map(\.fillRule), [.nonZero, .evenOdd])
        XCTAssertEqual(replayed.paintRecords, original.paintRecords)

        let bitmap = GPUIRawSceneRasterizer.rasterize(replayed, size: Self.surface)
        let expected = GPUIRawSceneRasterizer.rasterize(original, size: Self.surface)
        XCTAssertEqual(bitmap.pixels, expected.pixels)
        XCTAssertEqual(pixel(bitmap, x: 48, y: 48).red, 255, "the upper path's hole reveals the earlier red fill")
        XCTAssertEqual(pixel(bitmap, x: 48, y: 48).green, 0)
        XCTAssertEqual(pixel(bitmap, x: 20, y: 48).green, 255, "the later green ring remains on top")
        XCTAssertEqual(pixel(bitmap, x: 20, y: 48).red, 0)
        XCTAssertEqual(pixel(bitmap, x: 4, y: 48).alpha, 0)
    }

    func testFrameBridgeRetainsEvenOddFillRuleAndClip() async throws {
        let clip = Rect(x: 16, y: 8, width: 64, height: 80)
        let frame = frame(fillRule: .evenOdd, clip: clip)
        let scene = GPUIScene(from: frame, surfaceSize: Size(width: 128, height: 128))
        let path = try XCTUnwrap(scene.layers.flatMap(\.paths).first)

        XCTAssertEqual(path.fillRule, .evenOdd)
        XCTAssertEqual(path.clipBounds, clip)
        XCTAssertEqual(path.fillColor, Self.translucentRed)
        let bitmap = GPUIRawSceneRasterizer.rasterize(scene, size: Self.surface)
        XCTAssertEqual(pixel(bitmap, x: 48, y: 48).alpha, 0)
        XCTAssertEqual(pixel(bitmap, x: 20, y: 48).alpha, 128, accuracy: 1)
        XCTAssertEqual(pixel(bitmap, x: 12, y: 48).alpha, 0)
    }

    func testFrameBitmapDegradationRetainsHoleAndClip() async throws {
        let clip = Rect(x: 16, y: 8, width: 64, height: 80)
        for rule in [PathFillRule.nonZero, .evenOdd] {
            let frame = frame(fillRule: rule, clip: clip)
            let degraded = FramePathDegradation.degradingPathsToBitmaps(in: frame)
            XCTAssertEqual(degraded.commands.count, 1)
            let command = try XCTUnwrap(bitmapCommands(in: degraded).first)
            XCTAssertEqual(command.clipRect, clip)
            XCTAssertEqual(command.rect, clip)
            XCTAssertEqual(command.opacity, 1)

            let bitmap = GPUIRawSceneRasterizer.rasterize(degraded, size: Self.surface)
            let expected = GPUIRawSceneRasterizer.rasterize(frame, size: Self.surface)
            XCTAssertEqual(bitmap.pixels, expected.pixels)
            XCTAssertEqual(pixel(bitmap, x: 48, y: 48).alpha, rule == .evenOdd ? 0 : 128, accuracy: 1)
            XCTAssertEqual(pixel(bitmap, x: 20, y: 48).alpha, 128, accuracy: 1)
            XCTAssertEqual(pixel(bitmap, x: 12, y: 48).alpha, 0)
        }
    }

    func testFrameBitmapDegradationScalesEvenOddCoverage() async throws {
        let clip = Rect(x: 16, y: 8, width: 64, height: 80)
        for rule in [PathFillRule.nonZero, .evenOdd] {
            let degraded = FramePathDegradation.degradingPathsToBitmaps(
                in: frame(fillRule: rule, clip: clip), scaleFactor: 1.25)
            XCTAssertEqual(degraded.commands.count, 1)
            let command = try XCTUnwrap(bitmapCommands(in: degraded).first)

            XCTAssertEqual(command.rect, clip, "bitmap placement remains in logical coordinates")
            XCTAssertEqual(command.clipRect, clip)
            XCTAssertEqual(command.bitmap.width, 80)
            XCTAssertEqual(command.bitmap.height, 100)
            XCTAssertEqual(pixel(command.bitmap, x: 40, y: 50).alpha, rule == .evenOdd ? 0 : 128, accuracy: 1)
            XCTAssertEqual(pixel(command.bitmap, x: 5, y: 50).alpha, 128, accuracy: 1)
        }
    }

    func testFillRuleDoesNotTurnStrokeOverlapIntoHole() async {
        var nonZero = PathPrimitive(
            elements: [
                .moveTo(Point(x: 12, y: 48)), .lineTo(Point(x: 76, y: 48)),
                .moveTo(Point(x: 40, y: 48)), .lineTo(Point(x: 100, y: 48)),
            ],
            bounds: Rect(x: 4, y: 40, width: 104, height: 16),
            strokeColor: Color(red: 1, green: 0, blue: 0, alpha: 0.4),
            lineWidth: 12, lineCap: .round, lineJoin: .round)
        nonZero.fillRule = .nonZero
        var evenOdd = nonZero
        evenOdd.fillRule = .evenOdd
        let nonZeroPixels = raster(nonZero)
        let evenOddPixels = raster(evenOdd)

        XCTAssertEqual(evenOddPixels.pixels, nonZeroPixels.pixels, "stroke outlines always use non-zero union coverage")
        for x in [20, 56, 92] {
            XCTAssertEqual(pixel(evenOddPixels, x: x, y: 48).alpha, 102, accuracy: 1)
        }
        XCTAssertEqual(pixel(evenOddPixels, x: 56, y: 36).alpha, 0)
    }

    func testTranslucentGradientFillsOnlyEvenOddInterior() async {
        let evenOdd = raster(gradientPath(fillRule: .evenOdd))
        let nonZero = raster(gradientPath(fillRule: .nonZero))

        XCTAssertEqual(pixel(evenOdd, x: 48, y: 48).alpha, 0)
        XCTAssertEqual(pixel(nonZero, x: 48, y: 48).alpha, 128, accuracy: 1)
        for bitmap in [evenOdd, nonZero] {
            let left = pixel(bitmap, x: 20, y: 48)
            let right = pixel(bitmap, x: 76, y: 48)
            XCTAssertEqual(left.alpha, 128, accuracy: 1)
            XCTAssertEqual(right.alpha, 128, accuracy: 1)
            XCTAssertGreaterThan(left.red, left.blue)
            XCTAssertGreaterThan(right.blue, right.red)
            XCTAssertEqual(pixel(bitmap, x: 4, y: 48).alpha, 0)
        }
    }

    func testOneD3D11CacheKeepsAlternatingRulesSeparate() async throws {
        // A private offscreen renderer makes the counters exact. Attachment
        // errors propagate as failures; this suite adds no device skip path.
        let renderer = D3D11BatchRenderer()
        defer { renderer.detach() }
        try renderer.attachOffscreen(size: Self.surface, driver: .warpFirst)
        XCTAssertEqual(
            renderer.backendDiagnostics?.adapterIsSoftware, true,
            "WARP coverage requires a software adapter, not the hardware fallback")
        XCTAssertEqual(renderer.pathCacheEntryCountForTesting, 0)
        XCTAssertEqual(renderer.pathCacheMisses, 0)
        XCTAssertEqual(renderer.pathCacheHits, 0)
        let rules: [PathFillRule] = [.nonZero, .evenOdd, .nonZero, .evenOdd]

        for (index, rule) in rules.enumerated() {
            let scene = scene(for: nestedPath(fillRule: rule))
            renderer.bindResources(for: scene)
            try renderer.render(scene: scene)
            let bitmap = try renderer.readOffscreenPixels()

            assertMatchesCPU(bitmap, scene: scene)
            XCTAssertEqual(pixel(bitmap, x: 48, y: 48).alpha, rule == .evenOdd ? 0 : 255)
            XCTAssertEqual(pixel(bitmap, x: 20, y: 48).alpha, 255)
            XCTAssertEqual(pixel(bitmap, x: 4, y: 48).alpha, 0)
            XCTAssertEqual(renderer.pathCacheMisses, UInt64(min(index + 1, 2)))
            XCTAssertEqual(renderer.pathCacheHits, UInt64(max(index - 1, 0)))
            XCTAssertEqual(renderer.pathCacheEntryCountForTesting, min(index + 1, 2))
        }

        XCTAssertGreaterThan(renderer.largestPathRasterPixelsForTesting, 0)
        XCTAssertLessThanOrEqual(renderer.largestPathRasterPixelsForTesting, 80 * 80)
    }

    func testTransformedClippedEvenOddGradientMatchesCPUOnWARP() async throws {
        let renderer = D3D11BatchRenderer()
        defer { renderer.detach() }
        try renderer.attachOffscreen(size: Self.surface, driver: .warpFirst)
        XCTAssertEqual(
            renderer.backendDiagnostics?.adapterIsSoftware, true,
            "WARP coverage requires a software adapter, not the hardware fallback")
        var path = gradientPath(fillRule: .evenOdd)
            .rotated(by: .pi / 2, about: Point(x: 48, y: 48))
            .scaled(by: 1.25)
            .translated(by: Point(x: 2, y: 6))
        path.clipBounds = Rect(x: 22, y: 16, width: 80, height: 100)
        let scene = scene(for: path)
        renderer.bindResources(for: scene)
        try renderer.render(scene: scene)
        let gpu = try renderer.readOffscreenPixels()
        let cpu = GPUIRawSceneRasterizer.rasterize(scene, size: Self.surface)

        XCTAssertEqual(path.fillRule, .evenOdd)
        assertMatchesCPU(gpu, scene: scene)
        for bitmap in [cpu, gpu] {
            XCTAssertEqual(pixel(bitmap, x: 62, y: 66).alpha, 0)
            XCTAssertEqual(pixel(bitmap, x: 16, y: 66).alpha, 0, "the left ring is excluded by the screen clip")
            let top = pixel(bitmap, x: 62, y: 30)
            let bottom = pixel(bitmap, x: 62, y: 102)
            XCTAssertEqual(top.alpha, 128, accuracy: 1)
            XCTAssertEqual(bottom.alpha, 128, accuracy: 1)
            XCTAssertGreaterThan(top.red, top.blue)
            XCTAssertGreaterThan(bottom.blue, bottom.red)
        }
        XCTAssertEqual(renderer.pathCacheMisses, 1)
        XCTAssertEqual(renderer.pathCacheEntryCountForTesting, 1)
    }

    private func nestedElements(reverseInner: Bool = false, closeSubpaths: Bool = true) -> [PathElement] {
        var elements: [PathElement] = [
            .moveTo(Point(x: 8, y: 8)),
            .lineTo(Point(x: 88, y: 8)),
            .lineTo(Point(x: 88, y: 88)),
            .lineTo(Point(x: 8, y: 88)),
        ]
        if closeSubpaths { elements.append(.close) }
        if reverseInner {
            elements += [
                .moveTo(Point(x: 32, y: 32)),
                .lineTo(Point(x: 32, y: 64)),
                .lineTo(Point(x: 64, y: 64)),
                .lineTo(Point(x: 64, y: 32)),
            ]
        } else {
            elements += [
                .moveTo(Point(x: 32, y: 32)),
                .lineTo(Point(x: 64, y: 32)),
                .lineTo(Point(x: 64, y: 64)),
                .lineTo(Point(x: 32, y: 64)),
            ]
        }
        if closeSubpaths { elements.append(.close) }
        return elements
    }

    private func nestedPath(
        fillRule: PathFillRule,
        fillColor: Color = .white,
        reverseInner: Bool = false,
        closeSubpaths: Bool = true
    ) -> PathPrimitive {
        PathPrimitive(
            elements: nestedElements(reverseInner: reverseInner, closeSubpaths: closeSubpaths),
            bounds: Self.outerBounds, fillColor: fillColor, fillRule: fillRule)
    }

    private func gradientPath(fillRule: PathFillRule) -> PathPrimitive {
        let gradient = LinearGradient(
            startColor: Self.translucentRed,
            endColor: Color(red: 0, green: 0, blue: 1, alpha: 0.5),
            axis: .horizontal)
        var path = PathPrimitive(
            elements: nestedElements(), bounds: Self.outerBounds,
            fillGradient: gradient, fillRule: fillRule)
        path.setGradientEndpoints(start: Point(x: 8, y: 48), end: Point(x: 88, y: 48))
        return path
    }

    private func nestedRenderPath() -> RenderPath {
        var path = RenderPath()
        for bounds in [Self.outerBounds, Rect(x: 32, y: 32, width: 32, height: 32)] {
            path.move(to: Point(x: bounds.minX, y: bounds.minY))
            path.addLine(to: Point(x: bounds.maxX, y: bounds.minY))
            path.addLine(to: Point(x: bounds.maxX, y: bounds.maxY))
            path.addLine(to: Point(x: bounds.minX, y: bounds.maxY))
            path.close()
        }
        return path
    }

    private func frame(fillRule: PathFillRule, clip: Rect?) -> RenderFrame {
        RenderFrame(
            clearColor: .clear,
            commands: [
                .fillPath(
                    FillPathCommand(
                        path: nestedRenderPath(), color: Self.translucentRed,
                        clipRect: clip, fillRule: fillRule))
            ])
    }

    private func bitmapCommands(in frame: RenderFrame) -> [DrawBitmapCommand] {
        frame.commands.compactMap { command in
            guard case .drawBitmap(let bitmap) = command else { return nil }
            return bitmap
        }
    }

    private func scene(for path: PathPrimitive) -> GPUIScene {
        var scene = GPUIScene(clearColor: .clear)
        scene.addPath(path, toLayer: 0)
        scene.finish()
        return scene
    }

    private func raster(_ path: PathPrimitive) -> BitmapSurface {
        GPUIRawSceneRasterizer.rasterize(scene(for: path), size: Self.surface)
    }

    private func pixel(
        _ bitmap: BitmapSurface, x: Int, y: Int,
        file: StaticString = #filePath, line: UInt = #line
    ) -> (red: Int, green: Int, blue: Int, alpha: Int) {
        let offset = y * Int(bitmap.bytesPerRow) + x * 4
        guard x >= 0, y >= 0, x < Int(bitmap.width), y < Int(bitmap.height),
            offset >= 0, offset + 3 < bitmap.pixels.count
        else {
            XCTFail("pixel (\(x), \(y)) is outside the returned bitmap", file: file, line: line)
            return (0, 0, 0, 0)
        }
        return (
            red: Int(bitmap.pixels[offset + 2]), green: Int(bitmap.pixels[offset + 1]),
            blue: Int(bitmap.pixels[offset]), alpha: Int(bitmap.pixels[offset + 3])
        )
    }

    private func assertMatchesCPU(
        _ actual: BitmapSurface, scene: GPUIScene,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let expected = GPUIRawSceneRasterizer.rasterize(scene, size: Self.surface)
        XCTAssertEqual(actual.width, expected.width, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, file: file, line: line)
        // Readback is premultiplied while the CPU returns straight alpha.
        // Compare the same convention, retaining the existing cached-path
        // tolerance from PathGradientRenderingTests.
        let report = comparePixels(actual.premultipliedAlpha(), expected.premultipliedAlpha(), tolerance: 4)
        XCTAssertGreaterThan(
            report.matchRatio, 0.995,
            "fill-rule raster mismatch: ratio=\(report.matchRatio), maxDelta=\(report.maxChannelDelta)",
            file: file, line: line)
    }
}
