import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI

/// Producer intent is independent of the bitmap's origin and sampling mode.
/// A cached icon or symbol can still need an authored destination rectangle.
@MainActor
final class FrameBitmapProducerPlacementTests: XCTestCase {
    private static let displayScales = [1.0, 1.25, 1.5, 2.0]
    private static let runtimeClip = Rect(x: 0, y: 0, width: 64, height: 64)

    func testRuntimeBitmapKeepsItsLogicalDestinationAndOriginalSource() async throws {
        let source = bitmap(width: 2, height: 1)
        let destination = Rect(x: 10.25, y: 5.5, width: 18.75, height: 9.5)
        for scale in Self.displayScales {
            let node = ViewNode(frame: destination, bitmapSurface: source, borderWidth: 0.5)
            node.opacity = 0.6
            let runtime = makeRuntime(for: node, displayScale: scale)
            let frame = runtime.renderFrame()
            let draw = try onlyBitmap(in: frame.commands)
            assertDraw(
                draw, placement: .destinationRect, rect: destination.inset(by: 0.5),
                source: source, opacity: 0.6, clip: Self.runtimeClip)
            XCTAssertEqual(node.bitmapSurface?.contentKey, source.contentKey)
            XCTAssertEqual(runtime.renderFrame(), frame, "Frame replay must preserve placement intent")
        }
    }

    func testNativeIconBitmapLeafUsesDestinationPlacementAndReusesItsRaster() async throws {
        let previousText = NativeTextRenderer.testingOverrides
        let previousFonts = NativeFontAvailability.testingOverrides
        let previousAvailability = SystemUIFontFace.availabilityOverrideForTesting
        TextRasterCache.installForTesting(TextRasterCache(maxEntryCount: 8, maxMemoryBytes: 64 * 1024))
        defer {
            NativeTextRenderer.testingOverrides = previousText
            NativeFontAvailability.testingOverrides = previousFonts
            SystemUIFontFace.availabilityOverrideForTesting = previousAvailability
            TextRasterCache.restoreSharedForTesting()
        }

        let scale = 1.5
        let source = bitmap(width: 29, height: 15)
        let destination = Rect(x: 4.25, y: 6.5, width: 24.25, height: 18.5)
        var rasterizations = 0
        SystemUIFontFace.availabilityOverrideForTesting = false
        NativeFontAvailability.testingOverrides.hasGlyph = { _, _ in true }
        NativeTextRenderer.testingOverrides.measure = { _, _, _, _ in Size(width: 12, height: 10) }
        NativeTextRenderer.testingOverrides.layout = { _, _, _, _ in nil }
        // Suppress the label's separate text fallback without replacing the
        // runtime bitmap producer this test is exercising.
        NativeTextRenderer.testingOverrides.appendCommands = { _, _, _, _, _, _ in true }
        NativeTextRenderer.testingOverrides.rasterize = { _, _, receivedScale in
            XCTAssertEqual(receivedScale, scale)
            rasterizations += 1
            return source
        }
        let icon = Controls.icon(
            .search, frame: destination, preferredSize: destination.size, displayScale: scale)
        let cachedIcon = Controls.icon(
            .search, frame: destination, preferredSize: destination.size, displayScale: scale)
        XCTAssertEqual(rasterizations, 1)
        XCTAssertEqual(icon.bitmapSurface?.contentToken, source.contentToken)
        XCTAssertEqual(cachedIcon.bitmapSurface?.contentToken, source.contentToken)
        XCTAssertEqual(icon.preferredSize, destination.size)
        XCTAssertNotEqual(Double(source.width), destination.width * scale)

        icon.opacity = 0.75
        let draw = try onlyBitmap(in: makeRuntime(for: icon, displayScale: scale).renderFrame().commands)
        assertDraw(
            draw, placement: .destinationRect, rect: destination,
            source: source, opacity: 0.75, clip: Self.runtimeClip)
    }

    func testCanvasBitmapKeepsAuthoredExtentCoordinateScaleOpacityAndClip() async throws {
        let source = bitmap(width: 2, height: 3)
        let authored = Rect(x: 2.25, y: 3.5, width: 8.75, height: 5.5)
        let origin = Point(x: 3.125, y: 4.25)
        let clip = Rect(x: 6, y: 6, width: 32, height: 24)
        let coordinateScale = 1.25
        let destination = authored.scaled(by: coordinateScale).offsetBy(dx: origin.x, dy: origin.y)
        for scale in Self.displayScales {
            var context = CanvasGraphicsContext()
            context.draw(source, in: authored, opacity: 0.5)
            var commands: [RenderCommand] = []
            context.appendCommands(
                into: &commands, origin: origin, clipRect: clip, opacity: 0.6,
                displayScale: scale, coordinateScale: coordinateScale)
            assertDraw(
                try onlyBitmap(in: commands), placement: .destinationRect, rect: destination,
                source: source, opacity: 0.3, clip: clip)
        }
    }

    func testCachedAxisAlignedSymbolMapsItsSourceDensityToEachDestination() async throws {
        var paints = 0
        let symbol = try XCTUnwrap(
            CanvasSymbolSource(displayScale: 1.5) { _ in
                ViewNode(
                    frame: Rect(x: 0, y: 0, width: 10.25, height: 6.5), backgroundColor: .white,
                    canvasDraw: { _, _ in paints += 1 })
            })
        XCTAssertEqual(symbol.pixelSize, IntSize(width: 16, height: 10))
        let first = Rect(x: 10.25, y: 8.5, width: 20.5, height: 13)
        let second = Rect(x: 40.25, y: 8.5, width: 10.25, height: 6.5)
        let origin = Point(x: 2.125, y: 3.25)
        let clip = Rect(x: 15, y: 0, width: 60, height: 40)
        var context = CanvasGraphicsContext()
        context.draw(symbol, in: first, opacity: 0.5)
        context.draw(symbol, in: second, opacity: 0.25)
        let draws = bitmaps(in: canvasCommands(context, origin: origin, clip: clip, displayScale: 1.25))
        XCTAssertEqual(draws.count, 2)
        guard draws.count == 2 else { return }
        XCTAssertEqual(paints, 1, "Destinations must share the single recorded source")
        XCTAssertEqual(draws[0].bitmap.width, 16)
        XCTAssertEqual(draws[0].bitmap.height, 10)
        XCTAssertEqual(draws[0].bitmap.contentToken, draws[1].bitmap.contentToken)

        for (index, destination) in [first, second].enumerated() {
            let expected = Rect(
                x: destination.minX + origin.x, y: destination.minY + origin.y,
                width: 16 / symbol.displayScale * destination.width / symbol.size.width,
                height: 10 / symbol.displayScale * destination.height / symbol.size.height)
            assertDraw(
                draws[index], placement: .destinationRect, rect: expected,
                source: draws[0].bitmap, opacity: index == 0 ? 0.25 : 0.125, clip: clip)
        }
    }

    func testComposedAffineSymbolKeepsDeviceGridExtentAndLogicalClip() async throws {
        let symbol = try XCTUnwrap(
            CanvasSymbolSource(displayScale: 1) { _ in
                ViewNode(frame: Rect(x: 0, y: 0, width: 8, height: 4), backgroundColor: .white)
            })
        let origin = Point(x: 2.125, y: 3.25)
        let clip = Rect(x: 19.125, y: 4.125, width: 6.5, height: 3.25)
        for scale in Self.displayScales {
            var context = CanvasGraphicsContext()
            context.draw(
                symbol, in: Rect(x: 0, y: 0, width: 8, height: 4),
                transform: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 24.25, ty: 0.5),
                opacity: 0.5)
            let draw = try onlyBitmap(
                in: canvasCommands(context, origin: origin, clip: clip, displayScale: scale))
            let left = (clip.minX * scale / 2).rounded(.down) * 2
            let top = (clip.minY * scale / 2).rounded(.down) * 2
            let right = (clip.maxX * scale).rounded(.up)
            let bottom = (clip.maxY * scale).rounded(.up)
            let deviceBounds = Rect(x: left, y: top, width: right - left, height: bottom - top)
            assertDraw(
                draw, placement: .devicePixelRaster, rect: deviceBounds.scaled(by: 1 / scale),
                source: draw.bitmap, opacity: 0.25, clip: clip)
            XCTAssertEqual(Double(draw.bitmap.width), deviceBounds.width)
            XCTAssertEqual(Double(draw.bitmap.height), deviceBounds.height)
            XCTAssertTrue(draw.bitmap.pixels.contains { $0 != 0 })
        }
    }

    func testSymbolRejectionCheckerUsesDestinationExtentInsteadOfItsTwoTexels() async throws {
        let symbol = try XCTUnwrap(
            CanvasSymbolSource(displayScale: 1) { _ in
                ViewNode(frame: Rect(x: 0, y: 0, width: 4, height: 4), backgroundColor: .white)
            })
        let origin = Point(x: 3.125, y: 4.25)
        let clip = Rect(x: 5.25, y: 6.125, width: 4.5, height: 3.25)
        for scale in Self.displayScales {
            var context = CanvasGraphicsContext()
            context.draw(
                symbol, in: Rect(x: 0, y: 0, width: 4, height: 4),
                transform: CGAffineTransform(scaleX: 1e40, y: 1e40), opacity: 0.5)
            let marker = try onlyBitmap(
                in: canvasCommands(context, origin: origin, displayScale: scale))
            let expected = Rect(origin: origin, size: Size(width: 16 / scale, height: 16 / scale))
            assertDraw(
                marker, placement: .destinationRect, rect: expected,
                source: marker.bitmap, opacity: 0.25, clip: expected)
            XCTAssertEqual(marker.bitmap.width, 2)
            XCTAssertEqual(marker.bitmap.height, 2)
            XCTAssertEqual(marker.bitmap.pixels.count, 16)

            let clipped = try onlyBitmap(
                in: canvasCommands(context, origin: origin, clip: clip, displayScale: scale))
            assertDraw(
                clipped, placement: .destinationRect, rect: clip,
                source: clipped.bitmap, opacity: 0.25, clip: clip)
            XCTAssertEqual(clipped.bitmap.pixels, marker.bitmap.pixels)
        }
    }

    func testDirectWriteTextKeepsCachedPhysicalRasterAndOriginalLogicalRect() async throws {
        guard TextSystem.capabilities().dwriteFactoryCreationSucceeded else {
            throw XCTSkip("DirectWrite is required to exercise its frame bitmap producer")
        }
        try assertCachedTextPlacement(directWrite: true)
    }

    func testGDITextKeepsCachedPhysicalRasterAndOriginalLogicalRect() async throws {
        try assertCachedTextPlacement(directWrite: false)
    }

    func testDegradedFillAndStrokeKeepPhysicalRasterExtentClipAndOrder() async throws {
        var fill = RenderPath()
        fill.move(to: Point(x: 10.25, y: 6.5))
        fill.addLine(to: Point(x: 29, y: 6.5))
        fill.addLine(to: Point(x: 29, y: 16))
        fill.addLine(to: Point(x: 10.25, y: 16))
        fill.close()
        var stroke = RenderPath()
        stroke.move(to: Point(x: 10.25, y: 11))
        stroke.addLine(to: Point(x: 29, y: 11))
        let clip = Rect(x: 12.125, y: 8.25, width: 11.25, height: 5.75)
        let leading = RenderCommand.fillRect(
            FillRectCommand(rect: Rect(x: 0, y: 0, width: 2, height: 2), color: .black))
        let trailing = RenderCommand.fillRect(
            FillRectCommand(rect: Rect(x: 32, y: 20, width: 2, height: 2), color: .white))
        let frame = RenderFrame(
            clearColor: .clear,
            commands: [
                leading, .fillPath(FillPathCommand(path: fill, color: .white, clipRect: clip)),
                .strokePath(
                    StrokePathCommand(path: stroke, color: .white, style: StrokeStyle(lineWidth: 2.5), clipRect: clip)),
                trailing,
            ])
        for scale in Self.displayScales {
            let degraded = FramePathDegradation.degradingPathsToBitmaps(in: frame, scaleFactor: scale)
            XCTAssertEqual(degraded.clearColor, frame.clearColor)
            XCTAssertEqual(degraded.commands.count, 4)
            XCTAssertEqual(degraded.commands.first, leading)
            XCTAssertEqual(degraded.commands.last, trailing)
            let draws = bitmaps(in: degraded.commands)
            XCTAssertEqual(draws.count, 2)
            let filled = try XCTUnwrap(draws.first)
            XCTAssertEqual(filled.rect.origin, clip.origin)
            XCTAssertEqual(Double(filled.bitmap.width), (clip.width * scale).rounded(.up))
            XCTAssertEqual(Double(filled.bitmap.height), (clip.height * scale).rounded(.up))
            for draw in draws {
                XCTAssertEqual(draw.placement, .devicePixelRaster)
                XCTAssertNil(draw.placementFailure)
                XCTAssertEqual(draw.clipRect, clip)
                XCTAssertEqual(draw.sampling, .legacy)
                XCTAssertEqual(draw.opacity, 1)
                XCTAssertEqual(draw.rect.width * scale, Double(draw.bitmap.width), accuracy: 0.000001)
                XCTAssertEqual(draw.rect.height * scale, Double(draw.bitmap.height), accuracy: 0.000001)
                XCTAssertTrue(draw.bitmap.pixels.contains { $0 != 0 })
            }
        }
    }

    private func assertCachedTextPlacement(
        directWrite: Bool, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let cache = TextRasterCache(maxEntryCount: 8, maxMemoryBytes: 1024 * 1024)
        TextRasterCache.installForTesting(cache)
        defer { TextRasterCache.restoreSharedForTesting() }
        let text = "A"
        var style = PixelTextStyle(color: .black, nativeFontSize: 10)
        style.insets = .zero
        let rect = Rect(x: 10.25, y: 5.5, width: 40.25, height: 28.5)
        let clip = Rect(x: 11.125, y: 6.25, width: 25.75, height: 21.5)
        for scale in Self.displayScales {
            let measured =
                directWrite
                ? DirectWriteTextRenderer.measure(text, style: style, scaleFactor: scale, maxWidth: rect.width)
                : GDIRasterTextRenderer.measure(text, style: style, scaleFactor: scale, maxWidth: rect.width)
            let rasterSize = framePathTextRasterSize(frameSize: rect.size, measured: measured, style: style)
            let source = bitmap(
                width: Int32((rasterSize.width * scale).rounded(.up)),
                height: Int32((rasterSize.height * scale).rounded(.up)))
            cache.insert(
                source, for: TextRasterCacheKey(text: text, style: style, size: rasterSize, renderScale: scale))
            let previousHits = cache.hitCountForTesting
            // A seeded cache avoids font-pixel expectations and native
            // rasterization; measurement still uses the real backend.
            for origin in [rect.origin, Point(x: 13.5, y: 9.625)] {
                var commands: [RenderCommand] = []
                let placed = Rect(origin: origin, size: rect.size)
                let appended =
                    directWrite
                    ? DirectWriteTextRenderer.appendCommands(
                        for: text, in: placed, style: style, scaleFactor: scale, clipRect: clip, into: &commands)
                    : GDIRasterTextRenderer.appendCommands(
                        for: text, in: placed, style: style, scaleFactor: scale, clipRect: clip, into: &commands)
                XCTAssertTrue(appended, file: file, line: line)
                assertDraw(
                    try onlyBitmap(in: commands, file: file, line: line),
                    placement: .devicePixelRaster, rect: Rect(origin: origin, size: rasterSize),
                    source: source, opacity: 1, clip: clip, file: file, line: line)
            }
            XCTAssertEqual(cache.hitCountForTesting, previousHits + 2, file: file, line: line)
        }
    }

    private func bitmap(width: Int32, height: Int32) -> BitmapSurface {
        BitmapSurface(
            width: width, height: height, bytesPerRow: width * 4,
            pixels: Data((0..<(Int(width) * Int(height))).flatMap { _ in [UInt8(0), 255, 0, 255] }))
    }

    private func makeRuntime(for node: ViewNode, displayScale: Double) -> RetainedViewRuntime {
        let runtime = RetainedViewRuntime(clearColor: .clear, displayScale: displayScale)
        runtime.setRootSize(IntSize(width: 64, height: 64))
        runtime.root.clipsToBounds = true
        runtime.root.addChild(node)
        return runtime
    }

    private func canvasCommands(
        _ context: CanvasGraphicsContext, origin: Point = .zero, clip: Rect? = nil, displayScale: Double
    ) -> [RenderCommand] {
        var commands: [RenderCommand] = []
        context.appendCommands(
            into: &commands, origin: origin, clipRect: clip, opacity: 0.5, displayScale: displayScale)
        return commands
    }

    private func bitmaps(in commands: [RenderCommand]) -> [DrawBitmapCommand] {
        commands.compactMap {
            guard case .drawBitmap(let draw) = $0 else { return nil }
            return draw
        }
    }

    private func onlyBitmap(
        in commands: [RenderCommand], file: StaticString = #filePath, line: UInt = #line
    ) throws -> DrawBitmapCommand {
        let draws = bitmaps(in: commands)
        XCTAssertEqual(draws.count, 1, file: file, line: line)
        return try XCTUnwrap(draws.first, file: file, line: line)
    }

    private func assertDraw(
        _ draw: DrawBitmapCommand, placement: BitmapPlacement, rect: Rect,
        source: BitmapSurface, opacity: Float, clip: Rect?,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(draw.placement, placement, file: file, line: line)
        XCTAssertNil(draw.placementFailure, file: file, line: line)
        XCTAssertEqual(draw.rect.minX, rect.minX, accuracy: 0.000000001, file: file, line: line)
        XCTAssertEqual(draw.rect.minY, rect.minY, accuracy: 0.000000001, file: file, line: line)
        XCTAssertEqual(draw.rect.width, rect.width, accuracy: 0.000000001, file: file, line: line)
        XCTAssertEqual(draw.rect.height, rect.height, accuracy: 0.000000001, file: file, line: line)
        XCTAssertEqual(draw.bitmap.contentKey, source.contentKey, file: file, line: line)
        XCTAssertEqual(draw.bitmap.contentToken, source.contentToken, file: file, line: line)
        XCTAssertEqual(draw.opacity, opacity, accuracy: 0.000001, file: file, line: line)
        XCTAssertEqual(draw.clipRect, clip, file: file, line: line)
        XCTAssertEqual(draw.sampling, .legacy, file: file, line: line)
    }
}
