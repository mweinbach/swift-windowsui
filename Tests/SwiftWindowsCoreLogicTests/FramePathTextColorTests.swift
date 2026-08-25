import SwiftWindowsCore

import SwiftWindowsGraphics

import XCTest

@testable import SwiftWindowsUI

/// Regression tests for the frame-fallback text bug: on the frame path
/// (`RetainedViewRuntime.renderFrame` → `NativeTextRenderer.appendCommands` →
/// pre-rasterized text bitmaps), a text node whose layout frame is collapsed
/// (height or width smaller than the text's natural extent — e.g. a flex-squashed
/// stack child) had its text bitmap rasterized at the collapsed frame size,
/// producing a 1px-tall smear instead of readable text (verified live at 150%
/// DPI on the demo dashboard's "CONTROL CENTER" capsule and the wrapped hero
/// subtitle). The scene painter draws text overflowing such frames, so the
/// frame path must rasterize at least the measured natural size. These tests
/// inspect the produced bitmap pixels directly — no GPU needed.
final class FramePathTextColorTests: XCTestCase {
    /// Average unpremultiplied RGB + number of opaque pixels in a premultiplied
    /// BGRA bitmap. Returns nil when there is no visible ink at all.
    private func inkStatistics(of bitmap: BitmapSurface, alphaThreshold: UInt8 = 128) -> (
        red: Double, green: Double, blue: Double, opaquePixels: Int, totalPixels: Int
    )? {
        let bytes = [UInt8](bitmap.pixels)
        let pixelCount = Int(bitmap.width) * Int(bitmap.height)
        guard bytes.count >= pixelCount * 4 else {
            return nil
        }

        var redSum = 0.0
        var greenSum = 0.0
        var blueSum = 0.0
        var opaque = 0
        var index = 0
        while index + 3 < bytes.count {
            let alpha = bytes[index + 3]
            if alpha > alphaThreshold {
                // Pixels are premultiplied BGRA (v = color * alpha), so the
                // unpremultiplied color channel is v / alpha.
                blueSum += Double(bytes[index]) / Double(alpha)
                greenSum += Double(bytes[index + 1]) / Double(alpha)
                redSum += Double(bytes[index + 2]) / Double(alpha)
                opaque += 1
            }
            index += 4
        }

        guard opaque > 0 else {
            return nil
        }
        return (redSum / Double(opaque), greenSum / Double(opaque), blueSum / Double(opaque), opaque, pixelCount)
    }

    private func assertDarkInk(
        in bitmap: BitmapSurface,
        expectedColor: Color,
        _ message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let stats = inkStatistics(of: bitmap) else {
            XCTFail("\(message): text bitmap contains no opaque ink pixels", file: file, line: line)
            return
        }

        let tolerance = 0.08
        XCTAssertEqual(
            stats.red, Double(expectedColor.red), accuracy: tolerance,
            "\(message): ink red channel is wrong (opaque=\(stats.opaquePixels)/\(stats.totalPixels))",
            file: file, line: line)
        XCTAssertEqual(
            stats.green, Double(expectedColor.green), accuracy: tolerance,
            "\(message): ink green channel is wrong (opaque=\(stats.opaquePixels)/\(stats.totalPixels))",
            file: file, line: line)
        XCTAssertEqual(
            stats.blue, Double(expectedColor.blue), accuracy: tolerance,
            "\(message): ink blue channel is wrong (opaque=\(stats.opaquePixels)/\(stats.totalPixels))",
            file: file, line: line)
    }

    private static func textBitmaps(from commands: [RenderCommand]) -> [DrawBitmapCommand] {
        commands.compactMap { command in
            guard case .drawBitmap(let draw) = command else {
                return nil
            }
            return draw
        }
    }

    private func requireDirectWrite(file: StaticString = #filePath, line: UInt = #line) async throws {
        let capabilities = await MainActor.run { TextSystem.capabilities() }
        guard capabilities.dwriteFactoryCreationSucceeded else {
            throw XCTSkip("DirectWrite is not available on this environment", file: file, line: line)
        }
    }

    /// Dark-styled text keeps dark ink in its frame-path bitmap (the original
    /// "white text on light pill" report: ink must match the node's text color).
    func testNativeAppendCommandsRasterizesDarkTextWithDarkInk() async throws {
        try await requireDirectWrite()

        let bitmaps = await MainActor.run { () -> [BitmapSurface] in
            let style = PixelTextStyle(
                color: framePathDarkNavy,
                alignment: .leading,
                verticalAlignment: .top,
                nativeFontSize: 15,
                weight: .semibold
            )
            var commands: [RenderCommand] = []
            let didAppend = NativeTextRenderer.appendCommands(
                for: "Dark subtitle text",
                in: Rect(x: 0, y: 0, width: 260, height: 24),
                style: style,
                scaleFactor: 1.5,
                clipRect: nil,
                into: &commands
            )
            XCTAssertTrue(didAppend, "Native text append should succeed with DirectWrite available")
            return Self.textBitmaps(from: commands).map(\.bitmap)
        }

        XCTAssertEqual(bitmaps.count, 1, "Native text should ride exactly one pre-rasterized bitmap")
        for bitmap in bitmaps {
            assertDarkInk(in: bitmap, expectedColor: framePathDarkNavy, "frame-path native text bitmap")
        }
    }

    /// A capsule-style text node whose frame height collapsed to a fraction of
    /// a point (flex squash) must still produce a full-height, readable text
    /// bitmap at its natural measured size.
    func testCollapsedFrameHeightStillRasterizesFullText() async throws {
        try await requireDirectWrite()

        let result = await MainActor.run { () -> (draws: [DrawBitmapCommand], measured: Size?) in
            let style = PixelTextStyle(
                color: framePathDarkNavy,
                alignment: .center,
                verticalAlignment: .center,
                nativeFontSize: 10,
                weight: .semibold,
                maximumNumberOfLines: 1
            )
            let collapsedRect = Rect(x: 10, y: 6, width: 85.5, height: 0.625)
            let measured = NativeTextRenderer.measure(
                "CONTROL CENTER", style: style, scaleFactor: 1.5, maxWidth: collapsedRect.size.width)
            var commands: [RenderCommand] = []
            let didAppend = NativeTextRenderer.appendCommands(
                for: "CONTROL CENTER",
                in: collapsedRect,
                style: style,
                scaleFactor: 1.5,
                clipRect: nil,
                into: &commands
            )
            XCTAssertTrue(didAppend, "Native text append should succeed with DirectWrite available")
            return (Self.textBitmaps(from: commands), measured)
        }

        let draws = result.draws
        XCTAssertEqual(draws.count, 1, "Capsule text should emit exactly one pre-rasterized bitmap")
        guard let draw = draws.first, let measured = result.measured else {
            XCTFail("Capsule text should produce a bitmap and a measurement")
            return
        }

        let minimumPixelHeight = Int32((measured.height * 0.9 * 1.5).rounded(.down))
        XCTAssertGreaterThanOrEqual(
            draw.bitmap.height, max(minimumPixelHeight, 8),
            "Collapsed frame must not shrink the text bitmap below its measured line height "
                + "(bitmap=\(draw.bitmap.width)x\(draw.bitmap.height), measured=\(measured))")
        XCTAssertEqual(
            Double(draw.bitmap.width), measured.width * 1.5, accuracy: 2.0,
            "Bitmap width should match the measured natural width at the display scale")
        XCTAssertEqual(
            draw.rect.origin, Point(x: 10, y: 6),
            "The expanded bitmap must keep the node frame origin (scene-path overflow anchor)")
        assertDarkInk(in: draw.bitmap, expectedColor: framePathDarkNavy, "collapsed-frame capsule text bitmap")
    }

    /// A wrapped two-line subtitle squeezed to a single-line frame height must
    /// still rasterize both lines, with correct ink on the second line too.
    func testWrappedTextCollapsedToOneLineFrameRasterizesAllLines() async throws {
        try await requireDirectWrite()

        let result = await MainActor.run { () -> (draws: [DrawBitmapCommand], measured: Size?) in
            let style = PixelTextStyle(
                color: framePathDarkNavy,
                alignment: .leading,
                verticalAlignment: .top,
                nativeFontSize: 15,
                weight: .semibold,
                lineBreakMode: .wrap
            )
            let collapsedRect = Rect(x: 0, y: 0, width: 220, height: 20)
            let measured = NativeTextRenderer.measure(
                "RESPONSIVE COMPOSITION AND PANEL STRUCTURE",
                style: style,
                scaleFactor: 1.5,
                maxWidth: collapsedRect.size.width
            )
            var commands: [RenderCommand] = []
            let didAppend = NativeTextRenderer.appendCommands(
                for: "RESPONSIVE COMPOSITION AND PANEL STRUCTURE",
                in: collapsedRect,
                style: style,
                scaleFactor: 1.5,
                clipRect: nil,
                into: &commands
            )
            XCTAssertTrue(didAppend, "Native text append should succeed with DirectWrite available")
            return (Self.textBitmaps(from: commands), measured)
        }

        let draws = result.draws
        XCTAssertEqual(draws.count, 1, "Wrapped text should emit exactly one pre-rasterized bitmap")
        guard let draw = draws.first, let measured = result.measured else {
            XCTFail("Wrapped text should produce a bitmap and a measurement")
            return
        }

        XCTAssertGreaterThan(
            measured.height, 24,
            "The measurement should span two wrapped lines (measured=\(measured))")
        XCTAssertGreaterThanOrEqual(
            draw.bitmap.height, Int32((measured.height * 0.9 * 1.5).rounded(.down)),
            "The bitmap must contain both wrapped lines, not just the collapsed frame height "
                + "(bitmap=\(draw.bitmap.width)x\(draw.bitmap.height), measured=\(measured))")

        // Both lines carry the dark ink: inspect the lower half (second line).
        let bitmap = draw.bitmap
        let stride = Int(bitmap.bytesPerRow)
        let halfHeight = Int(bitmap.height) / 2
        let lowerPixels = bitmap.pixels.subdata(in: (halfHeight * stride)..<bitmap.pixels.count)
        let lowerHalf = BitmapSurface(
            width: bitmap.width,
            height: bitmap.height - Int32(halfHeight),
            bytesPerRow: bitmap.bytesPerRow,
            pixels: lowerPixels
        )
        assertDarkInk(in: lowerHalf, expectedColor: framePathDarkNavy, "second wrapped line")
    }

    /// End to end through the retained runtime: a dark-styled text node with a
    /// collapsed frame still yields a full-height dark-ink bitmap in the frame.
    func testRuntimeRenderFrameExpandsCollapsedTextNode() async throws {
        try await requireDirectWrite()

        let bitmaps = await MainActor.run { () -> [BitmapSurface] in
            let runtime = RetainedViewRuntime(
                root: ViewNode(
                    frame: Rect(x: 0, y: 0, width: 200, height: 0.6),
                    text: "Squashed dark text",
                    textStyle: PixelTextStyle(
                        color: framePathDarkNavy,
                        alignment: .leading,
                        verticalAlignment: .top,
                        nativeFontSize: 15,
                        weight: .semibold
                    )
                )
            )
            runtime.displayScale = 1.5
            let frame = runtime.renderFrame()
            return Self.textBitmaps(from: frame.commands).map(\.bitmap)
        }

        XCTAssertEqual(bitmaps.count, 1, "Runtime frame should carry the text as one pre-rasterized bitmap")
        guard let bitmap = bitmaps.first else {
            return
        }
        XCTAssertGreaterThanOrEqual(
            bitmap.height, 12,
            "Collapsed text node must not produce a degenerate bitmap (bitmap=\(bitmap.width)x\(bitmap.height))")
        assertDarkInk(in: bitmap, expectedColor: framePathDarkNavy, "runtime frame text bitmap")
    }

    /// Un-collapsed frames keep their existing behavior: the raster size stays
    /// the frame size when the frame already covers the measured text.
    func testFrameCoveringMeasuredTextKeepsFrameSize() async {
        await MainActor.run {
            let style = PixelTextStyle(color: framePathDarkNavy)
            let frameSize = Size(width: 260, height: 40)
            let measured = Size(width: 180, height: 20)
            let rasterSize = framePathTextRasterSize(frameSize: frameSize, measured: measured, style: style)
            XCTAssertEqual(rasterSize, frameSize)

            let collapsed = framePathTextRasterSize(
                frameSize: Size(width: 260, height: 0.625), measured: measured, style: style)
            XCTAssertEqual(collapsed, Size(width: 260, height: 20))

            XCTAssertEqual(
                framePathTextRasterSize(frameSize: frameSize, measured: nil, style: style), frameSize,
                "A failed measurement must leave the frame size untouched")
        }
    }

    /// Icon labels use sentinel 1,000,000pt suppression insets to hide their
    /// raw unicode text; the expansion must clamp those insets instead of
    /// producing multi-million-pixel bitmaps (E_INVALIDARG at texture upload).
    func testSuppressionInsetsDoNotProduceGiantBitmaps() async {
        await MainActor.run {
            let iconStyle = PixelTextStyle(
                color: .white,
                insets: EdgeInsets(top: 0, leading: 1_000_000, bottom: 0, trailing: 1_000_000),
                nativeFontSize: 19
            )
            let frameSize = Size(width: 19.4, height: 15.4)
            // The measured size with suppression insets is ~2,000,000 wide.
            let measured = Size(width: 2_000_000, height: 19)
            let rasterSize = framePathTextRasterSize(frameSize: frameSize, measured: measured, style: iconStyle)
            XCTAssertLessThanOrEqual(
                rasterSize.width, 3 * frameSize.width + 1,
                "Suppression insets must not expand the raster beyond the frame and its content")
            XCTAssertLessThanOrEqual(
                rasterSize.height, measured.height,
                "Height expansion stays bounded by the measured natural size")

            // End to end: appending commands for a suppressed icon label must
            // not emit a giant bitmap.
            var commands: [RenderCommand] = []
            _ = NativeTextRenderer.appendCommands(
                for: "\u{E70F}",
                in: Rect(x: 0, y: 0, width: frameSize.width, height: frameSize.height),
                style: iconStyle,
                scaleFactor: 1.5,
                clipRect: nil,
                into: &commands
            )
            for case .drawBitmap(let draw) in commands {
                XCTAssertLessThan(
                    draw.bitmap.width, 4096,
                    "Suppressed icon text bitmap must stay within texture limits (got \(draw.bitmap.width)x\(draw.bitmap.height))"
                )
                XCTAssertLessThan(draw.bitmap.height, 4096)
            }
        }
    }
}

/// Dark navy matching DemoTheme.primaryText (the unreadable capsule text).
private let framePathDarkNavy = Color(red: 0.18, green: 0.22, blue: 0.30, alpha: 0.96)
