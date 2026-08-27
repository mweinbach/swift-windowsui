import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI

@MainActor
final class CanvasSymbolRuntimeTests: XCTestCase {
    private let red = Color(red: 1, green: 0, blue: 0, alpha: 1)
    private let blue = Color(red: 0, green: 0, blue: 1, alpha: 1)

    private func commands(
        for context: CanvasGraphicsContext, origin: Point = .zero, clip: Rect? = nil,
        opacity: Float = 1, displayScale: Double = 1
    ) -> [RenderCommand] {
        var result: [RenderCommand] = []
        context.appendCommands(
            into: &result, origin: origin, clipRect: clip, opacity: opacity, displayScale: displayScale)
        return result
    }

    private func bitmaps(in commands: [RenderCommand]) -> [DrawBitmapCommand] {
        commands.compactMap {
            guard case .drawBitmap(let command) = $0 else { return nil }
            return command
        }
    }

    private func raster(_ commands: [RenderCommand], size: IntSize = IntSize(width: 64, height: 64))
        -> BitmapSurface
    {
        GPUIRawSceneRasterizer.rasterize(RenderFrame(clearColor: .clear, commands: commands), size: size)
    }

    private func assertPixel(
        _ bitmap: BitmapSurface, x: Int, y: Int, color: Color,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let pixels = bitmap.premultipliedAlpha()
        let offset = y * Int(pixels.bytesPerRow) + x * 4
        XCTAssertEqual(
            Float(pixels.pixels[offset + 2]) / 255, color.red * color.alpha, accuracy: 2 / 255, file: file, line: line)
        XCTAssertEqual(
            Float(pixels.pixels[offset + 1]) / 255, color.green * color.alpha, accuracy: 2 / 255, file: file, line: line
        )
        XCTAssertEqual(
            Float(pixels.pixels[offset]) / 255, color.blue * color.alpha, accuracy: 2 / 255, file: file, line: line)
        XCTAssertEqual(Float(pixels.pixels[offset + 3]) / 255, color.alpha, accuracy: 2 / 255, file: file, line: line)
    }

    func testPreparationMeasuresAtFractionalScaleWithoutPainting() async throws {
        var paints = 0
        let content = ViewNode(
            frame: Rect(x: 0, y: 0, width: 10.25, height: 6.5),
            canvasDraw: { _, _ in paints += 1 })
        let symbol = try XCTUnwrap(CanvasSymbolSource(displayScale: 1.5) { _ in content })
        XCTAssertEqual(symbol.size, Size(width: 10.25, height: 6.5))
        XCTAssertEqual(symbol.displayScale, 1.5)
        XCTAssertEqual(symbol.pixelSize, IntSize(width: 16, height: 10))
        XCTAssertTrue(content.parent === symbol.runtime.root)
        XCTAssertEqual(symbol.runtime.root.frame.size, symbol.size)
        XCTAssertEqual(content.resolvedFrame.size, symbol.size)
        XCTAssertEqual(symbol.runtime.sceneRebuildCount, 0)
        XCTAssertEqual(paints, 0, "Resolving a symbol during Canvas paint must not recursively start another paint")
    }

    func testMissingContentAndInvalidScaleDoNotCreateAResolvedSource() async {
        var builds = 0
        for scale in [Double.nan, 0, -Double.infinity] {
            XCTAssertNil(
                CanvasSymbolSource(displayScale: scale) { _ in
                    builds += 1
                    return ViewNode()
                })
        }
        XCTAssertEqual(builds, 0)
        XCTAssertNil(CanvasSymbolSource(displayScale: 1) { _ in nil })
    }

    func testEmptySymbolsResolveAndOversizeSourcesRejectBeforePainting() async throws {
        let empty = try XCTUnwrap(CanvasSymbolSource(displayScale: 2) { _ in ViewNode() })
        XCTAssertEqual(empty.size, .zero)
        XCTAssertEqual(empty.pixelSize, .zero)
        var context = CanvasGraphicsContext()
        context.draw(empty, in: Rect(x: 0, y: 0, width: 20, height: 20))
        XCTAssertTrue(commands(for: context).isEmpty)

        var paints = 0
        XCTAssertNil(
            CanvasSymbolSource(displayScale: 1) { _ in
                ViewNode(
                    frame: Rect(x: 0, y: 0, width: 2_049, height: 2_049),
                    canvasDraw: { _, _ in paints += 1 })
            })
        XCTAssertNil(CanvasSymbolSource.pixelSize(for: Size(width: 16_385, height: 1), displayScale: 1))
        XCTAssertNil(CanvasSymbolSource.pixelSize(for: Size(width: .nan, height: 1), displayScale: 1))
        XCTAssertEqual(paints, 0)
    }

    func testRecursiveConstructionIsBoundedAndTheGuardUnwindsAfterFailure() async {
        var builds = 0
        func nestedSource(_ depth: Int) -> CanvasSymbolSource? {
            CanvasSymbolSource(displayScale: 1) { _ in
                builds += 1
                if depth > 0, nestedSource(depth - 1) == nil { return nil }
                return ViewNode(frame: Rect(x: 0, y: 0, width: 1, height: 1))
            }
        }
        XCTAssertNil(nestedSource(GPUISceneLimits.maxImageRenderPassDepth + 1))
        XCTAssertEqual(builds, GPUISceneLimits.maxImageRenderPassDepth)
        XCTAssertNotNil(nestedSource(0))
    }

    func testLegacyFrameCachesTheSourceAndPreservesOpacityOriginAndClip() async throws {
        var paints = 0
        let color = Color(red: 1, green: 0, blue: 0, alpha: 0.5)
        let symbol = try XCTUnwrap(
            CanvasSymbolSource(displayScale: 1) { _ in
                ViewNode(
                    frame: Rect(x: 0, y: 0, width: 8, height: 8), backgroundColor: color,
                    canvasDraw: { _, _ in paints += 1 })
            })
        var context = CanvasGraphicsContext()
        context.draw(symbol, in: Rect(x: 10, y: 10, width: 8, height: 8), opacity: 0.5)
        context.draw(symbol, in: Rect(x: 22, y: 10, width: 8, height: 8), opacity: 0.5)
        let result = commands(
            for: context, origin: Point(x: 3, y: 4), clip: Rect(x: 14, y: 0, width: 50, height: 64), opacity: 0.5)
        let draws = bitmaps(in: result)
        XCTAssertEqual(draws.count, 2)
        XCTAssertEqual(paints, 1)
        XCTAssertEqual(draws.first?.bitmap.contentToken, draws.last?.bitmap.contentToken)
        XCTAssertEqual(draws.first?.rect.origin, Point(x: 13, y: 14))
        XCTAssertEqual(draws.first?.opacity, 0.25)
        let bitmap = raster(result)
        assertPixel(bitmap, x: 13, y: 18, color: .clear)
        assertPixel(bitmap, x: 17, y: 18, color: Color(red: 1, green: 0, blue: 0, alpha: 0.125))
        assertPixel(bitmap, x: 29, y: 18, color: Color(red: 1, green: 0, blue: 0, alpha: 0.125))
    }

    func testLegacyAffineReflectionPreservesTheSourceOrientation() async throws {
        let symbol = try XCTUnwrap(
            CanvasSymbolSource(displayScale: 1) { _ in
                ViewNode(
                    frame: Rect(x: 0, y: 0, width: 8, height: 4),
                    children: [
                        ViewNode(frame: Rect(x: 0, y: 0, width: 4, height: 4), backgroundColor: red),
                        ViewNode(frame: Rect(x: 4, y: 0, width: 4, height: 4), backgroundColor: blue),
                    ])
            })
        var context = CanvasGraphicsContext()
        context.draw(
            symbol, in: Rect(x: 0, y: 0, width: 8, height: 4),
            transform: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 24, ty: 0))
        let result = commands(for: context, origin: Point(x: 2, y: 2))
        let bitmap = raster(result)
        assertPixel(bitmap, x: 19, y: 3, color: blue)
        assertPixel(bitmap, x: 24, y: 3, color: red)
        assertPixel(bitmap, x: 17, y: 3, color: .clear)
        assertPixel(bitmap, x: 26, y: 3, color: .clear)
    }

    func testDisjointNestedLegacyClipStaysEmptyUntilItsPop() async throws {
        let symbol = try XCTUnwrap(
            CanvasSymbolSource(displayScale: 1) { _ in
                ViewNode(frame: Rect(x: 0, y: 0, width: 8, height: 8), backgroundColor: red)
            })
        var context = CanvasGraphicsContext()
        context.clip(to: Rect(x: 0, y: 0, width: 4, height: 4))
        context.clip(to: Rect(x: 12, y: 12, width: 4, height: 4))
        context.draw(symbol, in: Rect(x: 0, y: 0, width: 8, height: 8))
        context.popClip()
        context.draw(symbol, in: Rect(x: 0, y: 0, width: 8, height: 8))
        context.popClip()
        let result = commands(for: context)
        XCTAssertEqual(bitmaps(in: result).count, 1)
        let bitmap = raster(result)
        assertPixel(bitmap, x: 2, y: 2, color: red)
        assertPixel(bitmap, x: 6, y: 2, color: .clear)
        assertPixel(bitmap, x: 13, y: 13, color: .clear)
    }

    func testCopiedCanvasContextsShareDrawOrderButKeepIndependentClips() async {
        let green = Color(red: 0, green: 1, blue: 0, alpha: 1)
        let fullRect = Rect(x: 0, y: 0, width: 12, height: 8)
        var context = CanvasGraphicsContext()
        var copy = context
        copy.clip(to: Rect(x: 0, y: 0, width: 4, height: 8))
        context.fill(fullRect, with: .color(red))
        copy.fill(fullRect, with: .color(blue))
        context.fill(Rect(x: 8, y: 0, width: 4, height: 8), with: .color(green))
        let bitmap = raster(commands(for: context))
        assertPixel(bitmap, x: 2, y: 2, color: blue)
        assertPixel(bitmap, x: 6, y: 2, color: red)
        assertPixel(bitmap, x: 10, y: 2, color: green)
        XCTAssertNil(context.currentClip)
        XCTAssertEqual(copy.currentClip, Rect(x: 0, y: 0, width: 4, height: 8))
        XCTAssertEqual(context.operations.count, copy.operations.count)
    }

    func testLayerContextAndAppendDoNotDuplicateASharedDestination() async {
        var context = CanvasGraphicsContext()
        context.clip(to: Rect(x: 0, y: 0, width: 8, height: 8))
        var layer = context.makeLayerContext()
        layer.clip(to: Rect(x: 0, y: 0, width: 4, height: 8))
        context.fill(Rect(x: 0, y: 0, width: 12, height: 8), with: .color(red))
        layer.fill(Rect(x: 0, y: 0, width: 12, height: 8), with: .color(blue))
        let count = context.operations.count
        context.append(contentsOf: layer)
        XCTAssertEqual(context.operations.count, count)
        context.popClip()
        var independent = CanvasGraphicsContext()
        independent.fill(Rect(x: 10, y: 0, width: 2, height: 8), with: .color(blue))
        context.append(contentsOf: independent)
        let bitmap = raster(commands(for: context))
        assertPixel(bitmap, x: 2, y: 2, color: blue)
        assertPixel(bitmap, x: 6, y: 2, color: red)
        assertPixel(bitmap, x: 9, y: 2, color: .clear)
        assertPixel(bitmap, x: 11, y: 2, color: blue)
    }

    func testUniformPlacementScalesCoordinatesTextAndSymbolTransformsWithoutMutatingTheSink() async throws {
        let symbol = try XCTUnwrap(
            CanvasSymbolSource(displayScale: 1) { _ in
                ViewNode(frame: Rect(x: 0, y: 0, width: 8, height: 4), backgroundColor: red)
            })
        var context = CanvasGraphicsContext()
        var path = Path()
        path.moveTo(Point(x: 1, y: 2))
        path.arc(center: Point(x: 3, y: 4), radius: 2, startAngle: 0, endAngle: .pi, clockwise: false)
        let gradient = LinearGradient(startColor: red, endColor: blue)
        let stroke = StrokeStyle(lineWidth: 3, dashPattern: [2, 4], dashOffset: 1)
        context.stroke(
            path, with: .positionedGradient(gradient, startPoint: Point(x: 1, y: 2), endPoint: Point(x: 4, y: 6)),
            style: stroke)
        let textStyle = PixelTextStyle(
            color: red, scale: 1.5, letterSpacing: 2, nativeLetterSpacing: 3, lineSpacing: 4,
            insets: EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4), nativeFontSize: 14,
            spans: [TextSpan(text: "A", style: PixelTextStyle(color: blue, nativeFontSize: 6))])
        context.draw("A", in: Rect(x: 1, y: 2, width: 8, height: 4), style: textStyle)
        let transform = CGAffineTransform(a: 1, b: 0, c: 0.5, d: 1, tx: 3, ty: 4)
        let destination = Rect(x: 2, y: 3, width: 8, height: 4)
        context.draw(symbol, in: destination, transform: transform, opacity: 0.5)
        context.clip(to: Rect(x: 1, y: 1, width: 2, height: 2))
        context.fill(Rect(x: 0, y: 0, width: 4, height: 4), with: .color(red))

        let scaled = context.operationsScaled(by: 2)
        guard case .strokePathGradient(let scaledPath, _, let scaledStroke, let start, let end) = scaled[0],
            case .drawText(_, let textRect, let scaledText) = scaled[1],
            case .drawSymbol(let scaledSymbol, let symbolRect, let scaledTransform, let opacity) = scaled[2],
            case .pushClip(let clip) = scaled[3],
            case .fillRect(let fill, _) = scaled[4],
            case .popClip = scaled[5]
        else { return XCTFail("Scaling must retain every operation kind and its invocation order") }
        XCTAssertEqual(scaledPath, RenderPath(path: path).scaled(to: Rect(x: 0, y: 0, width: 2, height: 2)))
        XCTAssertEqual(scaledStroke.lineWidth, 6)
        XCTAssertEqual(scaledStroke.dashOffset, 2)
        XCTAssertEqual(scaledStroke.dashPattern, [4, 8])
        XCTAssertEqual(start, Point(x: 2, y: 4))
        XCTAssertEqual(end, Point(x: 8, y: 12))
        XCTAssertEqual(textRect, Rect(x: 2, y: 4, width: 16, height: 8))
        XCTAssertEqual(scaledText.scale, 3)
        XCTAssertEqual(scaledText.nativeFontSize, 28)
        XCTAssertEqual(scaledText.nativeLetterSpacing, 6)
        XCTAssertEqual(scaledText.lineSpacing, 8)
        XCTAssertEqual(scaledText.letterSpacing, 2, "Atlas-unit spacing already scales with the pixel font")
        XCTAssertEqual(scaledText.insets, EdgeInsets(top: 2, leading: 4, bottom: 6, trailing: 8))
        XCTAssertEqual(scaledText.spans?.first?.style.nativeFontSize, 12)
        XCTAssertTrue(scaledSymbol === symbol)
        XCTAssertEqual(symbolRect, destination)
        XCTAssertEqual(scaledTransform, CGAffineTransform(a: 2, b: 0, c: 1, d: 2, tx: 6, ty: 8))
        XCTAssertEqual(opacity, 0.5)
        XCTAssertEqual(clip, Rect(x: 2, y: 2, width: 4, height: 4))
        XCTAssertEqual(fill, Rect(x: 0, y: 0, width: 8, height: 8))
        guard case .drawSymbol(_, let originalRect, let originalTransform, _) = context.operationsScaled(by: 1)[2]
        else { return XCTFail("Identity scaling must retain the original symbol operation") }
        XCTAssertEqual(originalRect, destination)
        XCTAssertEqual(originalTransform, transform)
    }

    func testUnsupportedLegacyAffineExtentsUseOnlyTheSmallVisibleChecker() async throws {
        var paints = 0
        let symbol = try XCTUnwrap(
            CanvasSymbolSource(displayScale: 1) { _ in
                ViewNode(
                    frame: Rect(x: 0, y: 0, width: 4, height: 4), backgroundColor: red,
                    canvasDraw: { _, _ in paints += 1 })
            })
        var context = CanvasGraphicsContext()
        context.draw(
            symbol, in: Rect(x: 0, y: 0, width: 4, height: 4),
            transform: CGAffineTransform(scaleX: 1_000, y: 1_000))
        context.draw(
            symbol, in: Rect(x: 0, y: 0, width: 4, height: 4),
            transform: CGAffineTransform(scaleX: 0, y: 1))
        let before = CanvasSymbolSource.rejectionCount
        let draws = bitmaps(in: commands(for: context))
        XCTAssertEqual(draws.count, 2)
        XCTAssertEqual(paints, 1)
        XCTAssertGreaterThan(CanvasSymbolSource.rejectionCount, before)
        for draw in draws {
            XCTAssertEqual(draw.bitmap.width, 2)
            XCTAssertEqual(draw.bitmap.height, 2)
            XCTAssertEqual(draw.bitmap.pixels.count, 16)
        }
    }

    func testEnormousFiniteLegacyTransformStillPaintsAClippedRejectionMarker() async throws {
        let symbol = try XCTUnwrap(
            CanvasSymbolSource(displayScale: 1) { _ in
                ViewNode(frame: Rect(x: 0, y: 0, width: 4, height: 4), backgroundColor: red)
            })
        let marker = Color(red: 1, green: 0, blue: 1, alpha: 0.5)
        for displayScale in [1.0, 1.5] {
            var context = CanvasGraphicsContext()
            context.draw(
                symbol, in: Rect(x: 0, y: 0, width: 4, height: 4),
                transform: CGAffineTransform(scaleX: 1e40, y: 1e40))
            let output = commands(for: context, opacity: 0.5, displayScale: displayScale)
            let draw = try XCTUnwrap(bitmaps(in: output).first)
            XCTAssertEqual(draw.bitmap.pixels.count, 16)
            XCTAssertEqual(draw.rect.width * displayScale, 16, accuracy: 0.001)
            XCTAssertEqual(draw.rect.height * displayScale, 16, accuracy: 0.001)
            XCTAssertTrue(draw.rect.origin.x.isFinite && draw.rect.origin.y.isFinite)
            let pixels = raster(output)
            assertPixel(pixels, x: 0, y: 0, color: marker)
            assertPixel(pixels, x: 20, y: 20, color: .clear)

            let clip = Rect(x: 4, y: 4, width: 4, height: 4)
            let clippedOutput = commands(for: context, clip: clip, opacity: 0.5, displayScale: displayScale)
            let clippedDraw = try XCTUnwrap(bitmaps(in: clippedOutput).first)
            XCTAssertEqual(clippedDraw.rect, clip)
            XCTAssertEqual(clippedDraw.clipRect, clip)
            let clippedPixels = raster(clippedOutput)
            assertPixel(clippedPixels, x: 4, y: 4, color: marker)
            assertPixel(clippedPixels, x: 3, y: 4, color: .clear)
            assertPixel(clippedPixels, x: 8, y: 4, color: .clear)
        }
    }

    func testExhaustedLegacyBudgetDoesNotRecordANewSymbolSource() async throws {
        var firstPaints = 0
        var laterPaints = 0
        let first = try XCTUnwrap(
            CanvasSymbolSource(displayScale: 1) { _ in
                ViewNode(
                    frame: Rect(x: 0, y: 0, width: 1, height: 1), backgroundColor: red,
                    canvasDraw: { _, _ in firstPaints += 1 })
            })
        let later = try XCTUnwrap(
            CanvasSymbolSource(displayScale: 1) { _ in
                ViewNode(
                    frame: Rect(x: 0, y: 0, width: 1, height: 1), backgroundColor: blue,
                    canvasDraw: { _, _ in laterPaints += 1 })
            })
        var context = CanvasGraphicsContext()
        for _ in 0..<GPUISceneLimits.maxImageRenderPassCount {
            // One source allocation plus each one-pixel affine realization
            // exhausts the count budget without allocating large images.
            context.draw(
                first, in: Rect(x: 0, y: 0, width: 1, height: 1),
                transform: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 1, ty: 0))
        }
        context.draw(later, in: Rect(x: 8, y: 8, width: 1, height: 1))
        let output = bitmaps(in: commands(for: context))
        XCTAssertEqual(firstPaints, 1)
        XCTAssertEqual(laterPaints, 0, "A depleted allocation budget must reject before source recording")
        XCTAssertEqual(output.count, GPUISceneLimits.maxImageRenderPassCount + 1)
        XCTAssertEqual(output.last?.bitmap.pixels.count, 16)
    }
}
