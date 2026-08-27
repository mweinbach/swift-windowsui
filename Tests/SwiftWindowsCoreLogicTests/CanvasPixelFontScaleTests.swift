import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI

@MainActor
final class CanvasPixelFontScaleTests: XCTestCase {
    // Private-use text makes the scene's native path decline deterministically.
    private let text = "\u{E721}A\n\u{E721}A"
    private let canvasFrame = Rect(x: 160, y: 140, width: 160, height: 120)
    private let textRect = Rect(x: 12, y: 18, width: 112, height: 80)
    private let surfaceSize = Size(width: 600, height: 500)

    private func style(alignment: TextVerticalAlignment = .center, decorations: Bool = true) -> PixelTextStyle {
        PixelTextStyle(
            color: Color(red: 0.8, green: 0.5, blue: 0.2, alpha: 0.75), scale: 2,
            alignment: .leading, verticalAlignment: alignment, letterSpacing: 1.5,
            nativeLetterSpacing: 0.5, lineSpacing: 3,
            insets: EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4), nativeFontSize: 14,
            lineBreakMode: .clip, minimumNumberOfLines: 3,
            underline: decorations, underlineColor: Color(red: 1, green: 0, blue: 0, alpha: 1),
            strikethrough: decorations, strikethroughColor: Color(red: 0, green: 0, blue: 1, alpha: 1))
    }

    private func scene(
        text: String? = nil, style: PixelTextStyle, scale: Double = 1,
        rotation: Double = 0, displayScale: Double = 1
    ) -> GPUIScene {
        let content = text ?? self.text
        let rect = textRect
        let node = ViewNode(
            frame: canvasFrame,
            canvasDraw: { context, _ in context.draw(content, in: rect, style: style) },
            transform: Transform2D(scaleX: scale, scaleY: scale, rotation: rotation))
        return ScenePainter.paint(root: node, clearColor: .clear, surfaceSize: surfaceSize, displayScale: displayScale)
    }

    private func frameCommands(style: PixelTextStyle, scale: Double, origin: Point = .zero) -> [RenderCommand] {
        var context = CanvasGraphicsContext()
        context.draw(text, in: textRect, style: style)
        var commands: [RenderCommand] = []
        context.appendCommands(
            into: &commands, origin: origin, clipRect: nil, opacity: 1,
            displayScale: 1, coordinateScale: scale)
        return commands
    }

    private func scaledNativeStyle(_ style: PixelTextStyle, by scale: Double) throws -> PixelTextStyle {
        var context = CanvasGraphicsContext()
        context.draw("A", in: textRect, style: style)
        let operation = try XCTUnwrap(context.operationsScaled(by: scale).first)
        guard case .drawText(_, _, let result) = operation else {
            XCTFail("Canvas scaling must retain the text operation")
            return style
        }
        return result
    }

    private func assertPlacement(
        _ actual: Rect, from original: Rect, scale: Double, quarterTurn: Bool,
        displayScale: Double, file: StaticString = #filePath, line: UInt = #line
    ) {
        let pivot = Point(x: canvasFrame.midX * displayScale, y: canvasFrame.midY * displayScale)
        let scaledCentre = Point(
            x: pivot.x + (original.midX - pivot.x) * scale,
            y: pivot.y + (original.midY - pivot.y) * scale)
        let centre =
            quarterTurn
            ? Point(x: pivot.x - (scaledCentre.y - pivot.y), y: pivot.y + (scaledCentre.x - pivot.x))
            : scaledCentre
        XCTAssertEqual(actual.midX, centre.x, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.midY, centre.y, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.width, original.width * scale, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.height, original.height * scale, accuracy: 0.001, file: file, line: line)
    }

    private func rect(_ glyph: GlyphPrimitive) -> Rect {
        Rect(
            x: Double(glyph.screenX), y: Double(glyph.screenY), width: Double(glyph.screenW),
            height: Double(glyph.screenH))
    }

    private func rect(_ quad: QuadPrimitive) -> Rect {
        Rect(x: Double(quad.x), y: Double(quad.y), width: Double(quad.width), height: Double(quad.height))
    }

    func testIdentityFallbackStyleAndFrameBytesStayUnchanged() async {
        defer { NativeTextRenderer.resetTestingOverrides() }
        NativeTextRenderer.testingOverrides.appendCommands = { _, _, _, _, _, _ in false }
        var original = style()
        original.spans = [TextSpan(text: "A", style: style(alignment: .top, decorations: false))]
        XCTAssertEqual(original.canvasPixelFontFallback(coordinateScale: 1), original)

        let actual = frameCommands(style: original, scale: 1)
        var expected: [RenderCommand] = []
        PixelFont.appendCommands(for: text, in: textRect, style: original, clipRect: nil, into: &expected)
        XCTAssertFalse(actual.isEmpty)
        XCTAssertEqual(actual, expected)
        let size = IntSize(width: 160, height: 120)
        let actualPixels = GPUIRawSceneRasterizer.rasterize(
            RenderFrame(clearColor: .clear, commands: actual), size: size)
        let expectedPixels = GPUIRawSceneRasterizer.rasterize(
            RenderFrame(clearColor: .clear, commands: expected), size: size)
        XCTAssertEqual(actualPixels.pixels, expectedPixels.pixels)
    }

    func testFallbackRestoresAtlasUnitSpacingWithoutChangingNativeMetrics() async throws {
        var original = style()
        var spanStyle = style(decorations: false)
        spanStyle.lineSpacing = 5
        original.spans = [TextSpan(text: "A", style: spanStyle)]
        for scale in [1.0, 1.25, 1.5] {
            let native = try scaledNativeStyle(original, by: scale)
            let fallback = native.canvasPixelFontFallback(coordinateScale: scale)
            XCTAssertEqual(native.lineSpacing, original.lineSpacing * scale)
            XCTAssertEqual(fallback.lineSpacing, original.lineSpacing)
            XCTAssertEqual(fallback.spans?.first?.style.lineSpacing, spanStyle.lineSpacing)
            XCTAssertEqual(fallback.scale, native.scale)
            XCTAssertEqual(fallback.nativeFontSize, native.nativeFontSize)
            XCTAssertEqual(fallback.nativeLetterSpacing, native.nativeLetterSpacing)
            XCTAssertEqual(fallback.insets, native.insets)
            XCTAssertEqual(fallback.letterSpacing, native.letterSpacing)
            XCTAssertEqual(fallback.spans?.first?.style.nativeFontSize, native.spans?.first?.style.nativeFontSize)
        }
    }

    func testIdentityCanvasMatchesRetainedPixelTextPrimitivesAndBytes() async {
        let textStyle = style()
        let actual = scene(style: textStyle)
        let label = ViewNode(
            frame: textRect.offsetBy(dx: canvasFrame.minX, dy: canvasFrame.minY),
            text: text, textStyle: textStyle)
        let expected = ScenePainter.paint(root: label, clearColor: .clear, surfaceSize: surfaceSize)
        XCTAssertEqual(actual.layers.flatMap(\.pixelGlyphs).count, 4)
        XCTAssertEqual(actual.layers.flatMap(\.pixelGlyphs), expected.layers.flatMap(\.pixelGlyphs))
        XCTAssertEqual(actual.layers.flatMap(\.quads), expected.layers.flatMap(\.quads))
        let size = IntSize(width: 600, height: 500)
        XCTAssertEqual(
            GPUIRawSceneRasterizer.rasterize(actual, size: size).pixels,
            GPUIRawSceneRasterizer.rasterize(expected, size: size).pixels)
    }

    func testScaledAndRotatedFallbackKeepsLineSpacingAlignmentAndDecorations() async {
        for alignment in [TextVerticalAlignment.top, .center, .bottom] {
            let textStyle = style(alignment: alignment)
            for displayScale in [1.0, 1.25, 1.5] {
                let original = scene(style: textStyle, displayScale: displayScale)
                let originalGlyphs = original.layers.flatMap(\.pixelGlyphs)
                let originalDecorations = original.layers.flatMap(\.quads)
                XCTAssertEqual(originalGlyphs.count, 4)
                XCTAssertEqual(originalDecorations.count, 4)
                for scale in [1.0, 1.25, 1.5] {
                    for quarterTurn in [false, true] {
                        let rotation = quarterTurn ? Double.pi / 2 : 0
                        let placed = scene(
                            style: textStyle, scale: scale, rotation: rotation, displayScale: displayScale)
                        let glyphs = placed.layers.flatMap(\.pixelGlyphs)
                        let decorations = placed.layers.flatMap(\.quads)
                        XCTAssertTrue(placed.layers.flatMap(\.glyphs).isEmpty)
                        XCTAssertGreaterThan(placed.paintMetrics.textDiagnostics.pixelFontFallbacks, 0)
                        XCTAssertEqual(glyphs.count, originalGlyphs.count)
                        XCTAssertEqual(decorations.count, originalDecorations.count)
                        for (glyph, reference) in zip(glyphs, originalGlyphs) {
                            assertPlacement(
                                rect(glyph), from: rect(reference), scale: scale, quarterTurn: quarterTurn,
                                displayScale: displayScale)
                            XCTAssertEqual(Double(glyph.rotationRadians), rotation, accuracy: 0.0001)
                            XCTAssertEqual(glyph.atlasU0, reference.atlasU0)
                            XCTAssertEqual(glyph.atlasV0, reference.atlasV0)
                        }
                        for (quad, reference) in zip(decorations, originalDecorations) {
                            assertPlacement(
                                rect(quad), from: rect(reference), scale: scale, quarterTurn: quarterTurn,
                                displayScale: displayScale)
                            XCTAssertEqual(Double(quad.rotationRadians), rotation, accuracy: 0.0001)
                            XCTAssertEqual(quad.startA, reference.startA)
                        }
                    }
                }
            }
        }
    }

    func testLegacyFrameFallbackScalesLineSpacingOnlyOnce() async throws {
        defer { NativeTextRenderer.resetTestingOverrides() }
        NativeTextRenderer.testingOverrides.appendCommands = { _, _, _, _, _, _ in false }
        let original = style()
        let origin = Point(x: 7, y: 9)
        for scale in [1.0, 1.25, 1.5] {
            var expectedStyle = try scaledNativeStyle(original, by: scale)
            // PixelFont's spacing stays in atlas units; its scaled cell size
            // supplies the one coordinate conversion independently of the fix.
            expectedStyle.lineSpacing = original.lineSpacing
            var expected: [RenderCommand] = []
            PixelFont.appendCommands(
                for: text, in: textRect.scaled(by: scale).offsetBy(dx: origin.x, dy: origin.y),
                style: expectedStyle, clipRect: nil, into: &expected)
            let actual = frameCommands(style: original, scale: scale, origin: origin)
            XCTAssertFalse(actual.isEmpty)
            XCTAssertEqual(actual, expected, "Canvas coordinate scale \(scale) must not scale the line gap twice")
        }
    }

    func testNativeFrameAndSceneStillReceiveTheOriginalScaledStyles() async throws {
        NativeGlyphAtlas.shared.resetForTesting()
        defer {
            NativeTextRenderer.resetTestingOverrides()
            NativeGlyphAtlas.shared.resetForTesting()
        }
        var frameStyles: [PixelTextStyle] = []
        var sceneStyles: [PixelTextStyle] = []
        NativeTextRenderer.testingOverrides.appendCommands = { _, _, style, _, _, _ in
            frameStyles.append(style)
            return true
        }
        NativeTextRenderer.testingOverrides.layout = { text, style, _, _ in
            sceneStyles.append(style)
            let glyph = NativeTextGlyphLayout(
                character: "A", origin: .zero, advance: 8, glyphID: 65,
                fontFamily: style.fontFamily, weight: style.weight, fontSize: style.nativeFontPixelSize, sourceIndex: 0)
            return NativeTextLayoutResult(
                lines: [NativeTextLineLayout(text: text, width: 8, height: 8, glyphs: [glyph])],
                lineSpacing: style.lineSpacing, contentSize: Size(width: 8, height: 8),
                measuredSize: Size(width: 8, height: 8))
        }
        NativeTextRenderer.testingOverrides.rasterizeGlyphForLayout = { _, _, _ in
            NativeGlyphBitmap(
                surface: BitmapSurface(width: 8, height: 8, bytesPerRow: 32, pixels: Data(repeating: 255, count: 256)),
                bearingX: 0, bearingY: 0, advance: 8)
        }
        let original = style(decorations: false)
        for scale in [1.0, 1.25, 1.5] {
            let expected = try scaledNativeStyle(original, by: scale)
            frameStyles.removeAll()
            XCTAssertTrue(frameCommands(style: original, scale: scale).isEmpty)
            XCTAssertEqual(frameStyles, [expected])
            sceneStyles.removeAll()
            let rendered = scene(text: "A", style: original, scale: scale)
            XCTAssertFalse(sceneStyles.isEmpty)
            XCTAssertTrue(sceneStyles.allSatisfy { $0 == expected })
            XCTAssertFalse(rendered.layers.flatMap(\.glyphs).isEmpty)
            XCTAssertTrue(rendered.layers.flatMap(\.pixelGlyphs).isEmpty)
        }
    }
}
