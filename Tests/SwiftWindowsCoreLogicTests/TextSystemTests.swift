import XCTest
import SwiftWindowsCore
import SwiftWindowsGraphics
import WinSDK
@testable import SwiftWindowsUI

final class TextSystemTests: XCTestCase {
    func testCapabilitiesFallBackToPixelFontWhenDWriteMissing() async {
        let loader = MockTextLibraryLoader(moduleAvailable: false, hasFactorySymbol: false, factoryCreationResult: nil)

        let capabilities = await MainActor.run {
            TextSystem.capabilities(loader: loader)
        }

        XCTAssertEqual(capabilities.backend, .pixelFont)
        XCTAssertFalse(capabilities.dwriteLibraryLoaded)
        XCTAssertFalse(capabilities.dwriteCreateFactoryAvailable)
        XCTAssertFalse(capabilities.dwriteFactoryCreationSucceeded)
    }

    func testCapabilitiesKeepPixelFontWhenFactoryCreationFails() async {
        let loader = MockTextLibraryLoader(
            moduleAvailable: true,
            hasFactorySymbol: true,
            factoryCreationResult: (HRESULT(bitPattern: 0x80004005), nil)
        )

        let capabilities = await MainActor.run {
            TextSystem.capabilities(loader: loader)
        }

        XCTAssertEqual(capabilities.backend, .pixelFont)
        XCTAssertTrue(capabilities.dwriteLibraryLoaded)
        XCTAssertTrue(capabilities.dwriteCreateFactoryAvailable)
        XCTAssertFalse(capabilities.dwriteFactoryCreationSucceeded)
    }

    func testCapabilitiesReportDirectWriteReadyWhenFactoryCreationSucceeds() async {
        let loader = MockTextLibraryLoader(
            moduleAvailable: true,
            hasFactorySymbol: true,
            factoryCreationResult: (0, UnsafeMutableRawPointer(bitPattern: 1))
        )

        let capabilities = await MainActor.run {
            TextSystem.capabilities(loader: loader)
        }

        XCTAssertEqual(capabilities.backend, .directWriteReady)
        XCTAssertTrue(capabilities.dwriteLibraryLoaded)
        XCTAssertTrue(capabilities.dwriteCreateFactoryAvailable)
        XCTAssertTrue(capabilities.dwriteFactoryCreationSucceeded)
    }

    func testDirectWriteRendererProducesBitmapCommandWhenAvailable() async throws {
        let capabilities = await MainActor.run {
            TextSystem.capabilities()
        }

        guard capabilities.dwriteFactoryCreationSucceeded else {
            throw XCTSkip("DirectWrite is not available on this environment")
        }

        let result = await MainActor.run { () -> (Size?, Bool) in
            let style = PixelTextStyle(color: .white, scale: 2, alignment: .leading, weight: .semibold)
            var commands: [RenderCommand] = []
            let measured = DirectWriteTextRenderer.measure("DirectWrite", style: style, scaleFactor: 1.0)
            let didAppend = DirectWriteTextRenderer.appendCommands(
                for: "DirectWrite",
                in: Rect(x: 0, y: 0, width: 180, height: 40),
                style: style,
                scaleFactor: 1.0,
                clipRect: nil,
                into: &commands
            )
            let hasBitmap = commands.contains { command in
                if case .drawBitmap = command {
                    return true
                }
                return false
            }
            return (measured, didAppend && hasBitmap)
        }

        XCTAssertNotNil(result.0)
        XCTAssertTrue(result.1)
    }

    func testFrameRenderingFallsBackToPixelCommandsWhenNativeAppendFails() async {
        let result = await MainActor.run { () -> (Int, Int, Bool) in
            defer { NativeTextRenderer.resetTestingOverrides() }
            NativeTextRenderer.testingOverrides.appendCommands = { _, _, _, _, _, _ in false }

            let runtime = RetainedViewRuntime(
                root: ViewNode(
                    frame: Rect(x: 0, y: 0, width: 160, height: 40),
                    text: "Fallback",
                    textStyle: PixelTextStyle(color: .white, alignment: .leading, verticalAlignment: .top, nativeFontSize: 18)
                )
            )
            let frame = runtime.renderFrame()
            let fillRectCount = frame.commands.reduce(into: 0) { count, command in
                if case .fillRect = command {
                    count += 1
                }
            }
            let hasBitmapCommand = frame.commands.contains { command in
                if case .drawBitmap = command {
                    return true
                }
                return false
            }
            return (frame.commands.count, fillRectCount, hasBitmapCommand)
        }

        XCTAssertGreaterThan(result.0, 0, "Frame fallback should still emit commands when native text append fails")
        XCTAssertGreaterThan(result.1, 0, "Pixel fallback should emit fillRect commands for text")
        XCTAssertFalse(result.2, "Native bitmap text commands should not appear when the native path is forced to fail")
    }

    func testNativeAppendExternalizesTextDecorationCommands() async {
        let result = await MainActor.run { () -> (PixelTextStyle?, [FillRectCommand]) in
            defer { NativeTextRenderer.resetTestingOverrides() }
            var capturedStyle: PixelTextStyle?
            NativeTextRenderer.testingOverrides.appendCommands = { _, rect, style, _, _, commands in
                capturedStyle = style
                commands.append(
                    .drawBitmap(
                        DrawBitmapCommand(
                            rect: rect,
                            bitmap: BitmapSurface(
                                width: 1,
                                height: 1,
                                bytesPerRow: 4,
                                pixels: Data([255, 255, 255, 255])
                            )
                        )
                    )
                )
                return true
            }
            NativeTextRenderer.testingOverrides.layout = { text, style, _, _ in
                NativeTextLayoutResult(
                    lines: [
                        NativeTextLineLayout(
                            text: text,
                            width: 36,
                            height: style.nativeFontPixelSize,
                            glyphs: []
                        )
                    ],
                    contentSize: Size(width: 36, height: style.nativeFontPixelSize),
                    measuredSize: Size(width: 36, height: style.nativeFontPixelSize)
                )
            }

            let underlineColor = Color(red: 0.2, green: 0.5, blue: 1, alpha: 0.7)
            let strikethroughColor = Color(red: 1, green: 0.2, blue: 0.1, alpha: 0.8)
            var commands: [RenderCommand] = []
            _ = NativeTextRenderer.appendCommands(
                for: "Decorated",
                in: Rect(x: 0, y: 0, width: 120, height: 36),
                style: PixelTextStyle(
                    color: .white,
                    alignment: .leading,
                    verticalAlignment: .top,
                    nativeFontSize: 18,
                    underline: true,
                    underlineColor: underlineColor,
                    strikethrough: true,
                    strikethroughColor: strikethroughColor
                ),
                scaleFactor: 1,
                clipRect: nil,
                into: &commands
            )

            let fills = commands.compactMap { command -> FillRectCommand? in
                if case .fillRect(let fillRect) = command {
                    return fillRect
                }
                return nil
            }
            return (capturedStyle, fills)
        }

        XCTAssertFalse(result.0?.underline ?? true)
        XCTAssertFalse(result.0?.strikethrough ?? true)
        XCTAssertEqual(result.1.map(\.color), [
            Color(red: 0.2, green: 0.5, blue: 1, alpha: 0.7),
            Color(red: 1, green: 0.2, blue: 0.1, alpha: 0.8)
        ])
    }

    func testPixelFrameFallbackEmitsTextDecorationCommands() async {
        let result = await MainActor.run { () -> [Color] in
            defer { NativeTextRenderer.resetTestingOverrides() }
            NativeTextRenderer.testingOverrides.appendCommands = { _, _, _, _, _, _ in false }

            let runtime = RetainedViewRuntime(
                root: ViewNode(
                    frame: Rect(x: 0, y: 0, width: 160, height: 40),
                    text: "Fallback",
                    textStyle: PixelTextStyle(
                        color: .white,
                        alignment: .leading,
                        verticalAlignment: .top,
                        underline: true,
                        underlineColor: Color(red: 0.2, green: 0.5, blue: 1, alpha: 0.7),
                        strikethrough: true,
                        strikethroughColor: Color(red: 1, green: 0.2, blue: 0.1, alpha: 0.8)
                    )
                )
            )

            return runtime.renderFrame().commands.compactMap { command in
                if case .fillRect(let fillRect) = command {
                    return fillRect.color
                }
                return nil
            }
        }

        XCTAssertTrue(result.contains(Color(red: 0.2, green: 0.5, blue: 1, alpha: 0.7)))
        XCTAssertTrue(result.contains(Color(red: 1, green: 0.2, blue: 0.1, alpha: 0.8)))
    }

    func testDirectWriteLayoutProducesGlyphPlacementsWhenAvailable() async throws {
        let capabilities = await MainActor.run {
            TextSystem.capabilities()
        }

        guard capabilities.dwriteFactoryCreationSucceeded else {
            throw XCTSkip("DirectWrite is not available on this environment")
        }

        let result = await MainActor.run { () -> NativeTextLayoutResult? in
            let style = PixelTextStyle(
                color: .white,
                alignment: .leading,
                verticalAlignment: .top,
                nativeFontSize: 18
            )
            return NativeTextRenderer.layout("Hello", style: style, scaleFactor: 1.0, maxWidth: 200)
        }

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.lines.count, 1)
        XCTAssertEqual(result?.lines.first?.glyphs.count, 5)
        XCTAssertGreaterThan(result?.lines.first?.glyphs.last?.origin.x ?? 0, result?.lines.first?.glyphs.first?.origin.x ?? 0)
        XCTAssertEqual(result?.lines.first?.glyphs.map(\.sourceIndex), [0, 1, 2, 3, 4])
        XCTAssertEqual(result?.lines.first?.glyphs.map(\.character), Array("Hello"))
    }

    func testWindowTextSystemPreservesLogicalLayoutAcrossDisplayScaleChanges() async throws {
        let capabilities = await MainActor.run {
            TextSystem.capabilities()
        }

        guard capabilities.dwriteFactoryCreationSucceeded else {
            throw XCTSkip("DirectWrite is not available on this environment")
        }

        let result = await MainActor.run { () -> (NativeTextLayoutResult?, NativeTextLayoutResult?, Int) in
            let system = WindowTextSystem()
            let style = PixelTextStyle(
                color: .white,
                scale: 2,
                alignment: .leading,
                verticalAlignment: .top,
                nativeFontSize: 18,
                lineBreakMode: .wrap
            )
            let first = system.layout(
                "Stable logical layout across scale changes",
                style: style,
                maxWidth: 120,
                scaleFactor: 1.0
            )
            let second = system.layout(
                "Stable logical layout across scale changes",
                style: style,
                maxWidth: 120,
                scaleFactor: 1.75
            )
            return (first, second, system.cachedLayoutCount)
        }

        XCTAssertEqual(result.2, 1)
        XCTAssertEqual(result.0?.lines.map(\.text), result.1?.lines.map(\.text))
        XCTAssertEqual(
            result.0?.lines.flatMap { $0.glyphs.map(\.character) },
            result.1?.lines.flatMap { $0.glyphs.map(\.character) }
        )
        XCTAssertEqual(
            result.0?.lines.flatMap { $0.glyphs.map(\.origin) },
            result.1?.lines.flatMap { $0.glyphs.map(\.origin) }
        )
        XCTAssertEqual(
            result.0?.lines.flatMap { $0.glyphs.map(\.sourceIndex) },
            result.1?.lines.flatMap { $0.glyphs.map(\.sourceIndex) }
        )
    }

    func testWindowTextSystemUsesLayoutInputsAsCacheBoundaries() async throws {
        let capabilities = await MainActor.run {
            TextSystem.capabilities()
        }

        guard capabilities.dwriteFactoryCreationSucceeded else {
            throw XCTSkip("DirectWrite is not available on this environment")
        }

        let counts = await MainActor.run { () -> [Int] in
            let system = WindowTextSystem()
            let text = "Alpha Beta Gamma Delta"
            let spanRange = text.range(of: "Beta")!
            let spanStyle = PixelTextStyle(
                color: .white,
                scale: 1.4,
                alignment: .leading,
                verticalAlignment: .top,
                letterSpacing: 1,
                lineSpacing: 2,
                fontFamily: "Segoe UI",
                nativeFontSize: nil,
                weight: .regular,
                lineBreakMode: .wrap,
                maximumNumberOfLines: 2,
                enableKerning: true
            )
            let baseStyle = PixelTextStyle(
                color: .white,
                scale: 2,
                alignment: .leading,
                verticalAlignment: .top,
                letterSpacing: 1,
                lineSpacing: 2,
                insets: EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4),
                fontFamily: "Segoe UI",
                nativeFontSize: 18,
                weight: .regular,
                lineBreakMode: .wrap,
                maximumNumberOfLines: 2,
                enableKerning: true,
                spans: [TextSpan(text: "Beta", style: spanStyle, range: spanRange)]
            )

            var widerStyle = baseStyle
            widerStyle.maximumNumberOfLines = 1

            var minimumLineStyle = baseStyle
            minimumLineStyle.minimumNumberOfLines = 2

            var truncateStyle = baseStyle
            truncateStyle.lineBreakMode = .truncateMiddle

            var familyStyle = baseStyle
            familyStyle.fontFamily = "Arial"

            var weightStyle = baseStyle
            weightStyle.weight = .bold

            var sizedStyle = baseStyle
            sizedStyle.nativeFontSize = 22

            var lineSpacingStyle = baseStyle
            lineSpacingStyle.lineSpacing = 4

            var letterSpacingStyle = baseStyle
            letterSpacingStyle.letterSpacing = 3

            var insetsStyle = baseStyle
            insetsStyle.insets = EdgeInsets(top: 2, leading: 6, bottom: 1, trailing: 5)

            var kerningStyle = baseStyle
            kerningStyle.enableKerning = false

            var monospacedDigitsStyle = baseStyle
            monospacedDigitsStyle.monospacedDigits = true

            var spanScaledStyle = baseStyle
            if var scaledSpan = spanScaledStyle.spans?.first {
                scaledSpan.style.scale = 2.2
                spanScaledStyle.spans = [scaledSpan]
            }

            var counts: [Int] = []

            _ = system.layout(text, style: baseStyle, maxWidth: 140, scaleFactor: 1.0)
            counts.append(system.cachedLayoutCount)

            _ = system.layout(text, style: baseStyle, maxWidth: 140, scaleFactor: 1.0)
            counts.append(system.cachedLayoutCount)

            _ = system.layout(text, style: baseStyle, maxWidth: 96, scaleFactor: 1.0)
            counts.append(system.cachedLayoutCount)

            _ = system.layout(text, style: truncateStyle, maxWidth: 140, scaleFactor: 1.0)
            counts.append(system.cachedLayoutCount)

            _ = system.layout(text, style: widerStyle, maxWidth: 140, scaleFactor: 1.0)
            counts.append(system.cachedLayoutCount)

            _ = system.layout(text, style: minimumLineStyle, maxWidth: 140, scaleFactor: 1.0)
            counts.append(system.cachedLayoutCount)

            _ = system.layout(text, style: familyStyle, maxWidth: 140, scaleFactor: 1.0)
            counts.append(system.cachedLayoutCount)

            _ = system.layout(text, style: weightStyle, maxWidth: 140, scaleFactor: 1.0)
            counts.append(system.cachedLayoutCount)

            _ = system.layout(text, style: sizedStyle, maxWidth: 140, scaleFactor: 1.0)
            counts.append(system.cachedLayoutCount)

            _ = system.layout(text, style: lineSpacingStyle, maxWidth: 140, scaleFactor: 1.0)
            counts.append(system.cachedLayoutCount)

            _ = system.layout(text, style: letterSpacingStyle, maxWidth: 140, scaleFactor: 1.0)
            counts.append(system.cachedLayoutCount)

            _ = system.layout(text, style: insetsStyle, maxWidth: 140, scaleFactor: 1.0)
            counts.append(system.cachedLayoutCount)

            _ = system.layout(text, style: kerningStyle, maxWidth: 140, scaleFactor: 1.0)
            counts.append(system.cachedLayoutCount)

            _ = system.layout(text, style: monospacedDigitsStyle, maxWidth: 140, scaleFactor: 1.0)
            counts.append(system.cachedLayoutCount)

            _ = system.layout(text, style: spanScaledStyle, maxWidth: 140, scaleFactor: 1.0)
            counts.append(system.cachedLayoutCount)

            return counts
        }

        XCTAssertEqual(counts, [1, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14])
    }

    func testWindowTextSystemLayoutKeyPreservesStructuralSpanIdentity() {
        let text = "Alpha Beta Gamma Beta"
        let firstRange = text.range(of: "Beta")!
        let secondRange = text.range(of: "Beta", range: firstRange.upperBound..<text.endIndex)!
        let spanStyle = PixelTextStyle(
            color: .white,
            scale: 1.4,
            alignment: .leading,
            verticalAlignment: .top,
            letterSpacing: 1,
            lineSpacing: 2,
            fontFamily: "Segoe UI",
            nativeFontSize: 18,
            weight: .regular,
            lineBreakMode: .wrap,
            maximumNumberOfLines: 2,
            enableKerning: true
        )
        let baseStyle = PixelTextStyle(
            color: .white,
            scale: 2,
            alignment: .leading,
            verticalAlignment: .top,
            letterSpacing: 1,
            lineSpacing: 2,
            insets: EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4),
            fontFamily: "Segoe UI",
            nativeFontSize: 18,
            weight: .regular,
            lineBreakMode: .wrap,
            maximumNumberOfLines: 2,
            enableKerning: true,
            spans: [TextSpan(text: "Beta", style: spanStyle, range: firstRange)]
        )

        var movedSpanStyle = baseStyle
        movedSpanStyle.spans = [TextSpan(text: "Beta", style: spanStyle, range: secondRange)]

        let firstKey = WindowTextSystem.LayoutKey(text: text, style: baseStyle, maxWidth: 140)
        let secondKey = WindowTextSystem.LayoutKey(text: text, style: movedSpanStyle, maxWidth: 140)
        let rebuiltFirstKey = WindowTextSystem.LayoutKey(text: String(text), style: baseStyle, maxWidth: 140)

        XCTAssertNotEqual(firstKey.spans, secondKey.spans)
        XCTAssertNotEqual(firstKey, secondKey)
        XCTAssertEqual(firstKey.spans, rebuiltFirstKey.spans)
        XCTAssertEqual(firstKey, rebuiltFirstKey)
    }

    func testWindowTextSystemInvalidatesReuseWhenNativeFontSizeIsDerivedFromScale() async throws {
        let capabilities = await MainActor.run {
            TextSystem.capabilities()
        }

        guard capabilities.dwriteFactoryCreationSucceeded else {
            throw XCTSkip("DirectWrite is not available on this environment")
        }

        let result = await MainActor.run { () -> (NativeTextLayoutResult?, NativeTextLayoutResult?, Int) in
            let system = WindowTextSystem()
            let text = "Scale derived fonts must invalidate cache reuse"
            let firstStyle = PixelTextStyle(
                color: .white,
                scale: 1,
                alignment: .leading,
                verticalAlignment: .top,
                lineBreakMode: .clip
            )
            let secondStyle = PixelTextStyle(
                color: .white,
                scale: 3,
                alignment: .leading,
                verticalAlignment: .top,
                lineBreakMode: .clip
            )
            let first = system.layout(text, style: firstStyle, maxWidth: 240, scaleFactor: 1.0)
            let second = system.layout(text, style: secondStyle, maxWidth: 240, scaleFactor: 1.0)
            return (first, second, system.cachedLayoutCount)
        }

        XCTAssertEqual(result.2, 2)
        XCTAssertNotEqual(result.0?.contentSize.width, result.1?.contentSize.width)
        XCTAssertNotEqual(
            result.0?.lines.first?.glyphs.map(\.origin.x),
            result.1?.lines.first?.glyphs.map(\.origin.x)
        )
    }

    func testWindowTextSystemKeepsExplicitNativeFontSizeStableAcrossStyleScaleChanges() async throws {
        let capabilities = await MainActor.run {
            TextSystem.capabilities()
        }

        guard capabilities.dwriteFactoryCreationSucceeded else {
            throw XCTSkip("DirectWrite is not available on this environment")
        }

        let result = await MainActor.run { () -> (NativeTextLayoutResult?, NativeTextLayoutResult?, Int) in
            let system = WindowTextSystem()
            let text = "Explicit size wins over style scale"
            let firstStyle = PixelTextStyle(
                color: .white,
                scale: 1,
                alignment: .leading,
                verticalAlignment: .top,
                nativeFontSize: 18,
                lineBreakMode: .clip
            )
            let secondStyle = PixelTextStyle(
                color: .white,
                scale: 3,
                alignment: .leading,
                verticalAlignment: .top,
                nativeFontSize: 18,
                lineBreakMode: .clip
            )
            let first = system.layout(text, style: firstStyle, maxWidth: 240, scaleFactor: 1.0)
            let second = system.layout(text, style: secondStyle, maxWidth: 240, scaleFactor: 1.0)
            return (first, second, system.cachedLayoutCount)
        }

        XCTAssertEqual(result.2, 1)
        XCTAssertEqual(result.0?.contentSize.width, result.1?.contentSize.width)
        XCTAssertEqual(
            result.0?.lines.first?.glyphs.map(\.origin.x),
            result.1?.lines.first?.glyphs.map(\.origin.x)
        )
    }

    func testSnapLogicalTextSizeRoundsUpToWholePixels() {
        let snapped = snapLogicalTextSize(Size(width: 18.2, height: 9.1), scaleFactor: 1.5)

        XCTAssertEqual(snapped.width, 18.666666666666668, accuracy: 0.0001)
        XCTAssertEqual(snapped.height, 9.333333333333334, accuracy: 0.0001)
    }

    func testCapturedGlyphRasterMetricsRejectNonFiniteInputs() {
        let glyph = NativeTextGlyphLayout(
            character: "A",
            origin: Point(x: 0, y: .nan),
            advance: .nan,
            glyphID: 12,
            fontFace: nil,
            fontFamily: "Segoe UI",
            weight: .regular,
            fontSize: .nan
        )

        XCTAssertNil(makeCapturedGlyphRasterMetrics(for: glyph, scaleFactor: 1.0))
    }

    func testCapturedGlyphRasterMetricsProduceFiniteTargetSize() {
        let glyph = NativeTextGlyphLayout(
            character: "A",
            origin: Point(x: 0, y: 14),
            advance: 11,
            glyphID: 12,
            fontFace: nil,
            fontFamily: "Segoe UI",
            weight: .regular,
            fontSize: 18
        )

        let metrics = makeCapturedGlyphRasterMetrics(for: glyph, scaleFactor: 1.5)

        guard let metrics else {
            return XCTFail("Expected finite raster metrics")
        }

        XCTAssertEqual(metrics.renderScale, 1.5, accuracy: 0.0001)
        XCTAssertGreaterThan(metrics.targetWidth, 0)
        XCTAssertGreaterThan(metrics.targetHeight, 0)
        XCTAssertGreaterThan(metrics.advance, 0)
    }

    func testCapturedGlyphRasterMetricsDoNotScaleWithLayoutBaseline() {
        let baselineGlyph = NativeTextGlyphLayout(
            character: "A",
            origin: Point(x: 0, y: 14),
            advance: 11,
            glyphID: 12,
            fontFace: nil,
            fontFamily: "Segoe UI",
            weight: .regular,
            fontSize: 18
        )
        let offsetGlyph = NativeTextGlyphLayout(
            character: "A",
            origin: Point(x: 0, y: 420),
            advance: 11,
            glyphID: 12,
            fontFace: nil,
            fontFamily: "Segoe UI",
            weight: .regular,
            fontSize: 18
        )

        XCTAssertEqual(
            makeCapturedGlyphRasterMetrics(for: baselineGlyph, scaleFactor: 1.0)?.targetHeight,
            makeCapturedGlyphRasterMetrics(for: offsetGlyph, scaleFactor: 1.0)?.targetHeight
        )
    }

    func testCapturedGlyphBitmapRejectsPathologicalExtents() {
        let normalBitmap = NativeGlyphBitmap(
            surface: BitmapSurface(width: 18, height: 22, bytesPerRow: 18 * 4, pixels: Data(repeating: 255, count: 18 * 22 * 4)),
            bearingX: 0,
            bearingY: 0,
            advance: 12
        )
        let oversizedBitmap = NativeGlyphBitmap(
            surface: BitmapSurface(width: 18, height: 420, bytesPerRow: 18 * 4, pixels: Data(repeating: 255, count: 18 * 420 * 4)),
            bearingX: 0,
            bearingY: 0,
            advance: 12
        )

        XCTAssertTrue(isUsableCapturedGlyphBitmap(normalBitmap, fontSize: 18, scaleFactor: 1.0))
        XCTAssertFalse(isUsableCapturedGlyphBitmap(oversizedBitmap, fontSize: 18, scaleFactor: 1.0))
    }

    func testResolveTextLayoutTruncatesSingleLineToFit() {
        let style = PixelTextStyle(color: .white, lineBreakMode: .truncateTail)

        let layout = resolveTextLayout(
            for: "HELLO WORLD",
            style: style,
            maxContentWidth: 8
        ) { line in
            Double(line.count)
        }

        XCTAssertEqual(layout.lines, ["HELLO..."])
    }

    func testResolveTextLayoutWrapsAndAppliesLineLimit() {
        let style = PixelTextStyle(color: .white, lineBreakMode: .wrap, maximumNumberOfLines: 2)

        let layout = resolveTextLayout(
            for: "ALPHA BETA GAMMA DELTA",
            style: style,
            maxContentWidth: 10
        ) { line in
            Double(line.count)
        }

        XCTAssertEqual(layout.lines, ["ALPHA BETA", "GAMMA..."])
    }

    func testResolveTextLayoutHeadAndMiddleTruncationAreDeterministicAndWidthRespecting() {
        let headStyle = PixelTextStyle(color: .white, lineBreakMode: .truncateHead)
        let middleStyle = PixelTextStyle(color: .white, lineBreakMode: .truncateMiddle)

        let firstHead = resolveTextLayout(
            for: "HELLO WORLD",
            style: headStyle,
            maxContentWidth: 8
        ) { line in
            Double(line.count)
        }
        let secondHead = resolveTextLayout(
            for: "HELLO WORLD",
            style: headStyle,
            maxContentWidth: 8
        ) { line in
            Double(line.count)
        }
        let firstMiddle = resolveTextLayout(
            for: "HELLO WORLD",
            style: middleStyle,
            maxContentWidth: 8
        ) { line in
            Double(line.count)
        }
        let secondMiddle = resolveTextLayout(
            for: "HELLO WORLD",
            style: middleStyle,
            maxContentWidth: 8
        ) { line in
            Double(line.count)
        }

        XCTAssertEqual(firstHead.lines, ["...WORLD"])
        XCTAssertEqual(firstHead, secondHead)
        XCTAssertTrue(firstHead.lines.allSatisfy { Double($0.count) <= 8 })

        XCTAssertEqual(firstMiddle.lines, ["HE...RLD"])
        XCTAssertEqual(firstMiddle, secondMiddle)
        XCTAssertTrue(firstMiddle.lines.allSatisfy { Double($0.count) <= 8 })
    }

    func testResolveTextLayoutNormalizesCRLFDeterministically() {
        let style = PixelTextStyle(color: .white, lineBreakMode: .wrap)
        let text = "ALPHA\r\nBETA\rGAMMA\nDELTA"

        let first = resolveTextLayout(
            for: text,
            style: style,
            maxContentWidth: 5
        ) { line in
            Double(line.count)
        }
        let second = resolveTextLayout(
            for: text,
            style: style,
            maxContentWidth: 5
        ) { line in
            Double(line.count)
        }

        XCTAssertEqual(first.lines, ["ALPHA", "BETA", "GAMMA", "DELTA"])
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.text, "ALPHA\nBETA\nGAMMA\nDELTA")
        XCTAssertTrue(first.lines.allSatisfy { Double($0.count) <= 5 })
    }

    func testMinimumScaleFactorResolvesEffectivePixelTextStyleBeforeTruncation() {
        let text = "ABCDEFGHIJ"
        let style = PixelTextStyle(
            color: .white,
            scale: 2,
            alignment: .leading,
            lineBreakMode: .truncateTail,
            minimumScaleFactor: 0.5
        )
        let naturalWidth = PixelFont.rawLineWidth(text, letterSpacing: style.letterSpacing) * style.scale
        let constrainedWidth = naturalWidth * 0.75

        let effectiveStyle = style.resolvingMinimumScaleFactor(
            for: text,
            maxContentWidth: constrainedWidth,
            measureLine: { line in
                PixelFont.rawLineWidth(line, letterSpacing: style.letterSpacing) * style.scale
            }
        )
        let scaledLayout = resolveTextLayout(
            for: text,
            style: effectiveStyle,
            maxContentWidth: constrainedWidth,
            measureLine: { line in
                PixelFont.rawLineWidth(line, letterSpacing: effectiveStyle.letterSpacing) * effectiveStyle.scale
            }
        )
        let unscaledLayout = resolveTextLayout(
            for: text,
            style: style,
            maxContentWidth: constrainedWidth,
            measureLine: { line in
                PixelFont.rawLineWidth(line, letterSpacing: style.letterSpacing) * style.scale
            }
        )

        XCTAssertEqual(effectiveStyle.scale, 1.5, accuracy: 0.0001)
        XCTAssertEqual(effectiveStyle.minimumScaleFactor, 1)
        XCTAssertEqual(scaledLayout.lines, [text])
        XCTAssertNotEqual(unscaledLayout.lines, [text])
    }

    func testPixelTextMeasurementReservesLineLimitSpaceWhenRequested() {
        let baseStyle = PixelTextStyle(
            color: .white,
            scale: 2,
            alignment: .leading,
            lineBreakMode: .wrap,
            maximumNumberOfLines: 3
        )
        var reservedStyle = baseStyle
        reservedStyle.reservesLineLimitSpace = true

        let unreserved = PixelFont.measure("ONE", style: baseStyle, maxWidth: nil)
        let reserved = PixelFont.measure("ONE", style: reservedStyle, maxWidth: nil)
        let expectedReservedContentHeight = pixelTextContentHeight(
            lineCount: 3,
            style: reservedStyle,
            scale: reservedStyle.scale
        )

        XCTAssertGreaterThan(reserved.height, unreserved.height)
        XCTAssertEqual(reserved.height, expectedReservedContentHeight, accuracy: 0.0001)
    }

    func testPixelTextMeasurementReservesMinimumLineLimitSpace() {
        let baseStyle = PixelTextStyle(
            color: .white,
            scale: 2,
            alignment: .leading,
            lineBreakMode: .wrap,
            minimumNumberOfLines: 2
        )

        let measured = PixelFont.measure("ONE", style: baseStyle, maxWidth: nil)
        let expectedReservedContentHeight = pixelTextContentHeight(
            lineCount: 2,
            style: baseStyle,
            scale: baseStyle.scale
        )

        XCTAssertEqual(measured.height, expectedReservedContentHeight, accuracy: 0.0001)
    }

    func testDirectWriteMinimumScaleFactorShrinksConstrainedLayoutWhenAvailable() async throws {
        let capabilities = await MainActor.run {
            TextSystem.capabilities()
        }

        guard capabilities.dwriteFactoryCreationSucceeded else {
            throw XCTSkip("DirectWrite is not available on this environment")
        }

        let result = await MainActor.run { () -> (NativeTextLayoutResult?, NativeTextLayoutResult?) in
            let text = "Scale Before Truncate"
            let baseStyle = PixelTextStyle(
                color: .white,
                alignment: .leading,
                verticalAlignment: .top,
                nativeFontSize: 24,
                lineBreakMode: .truncateTail
            )
            var scaledStyle = baseStyle
            scaledStyle.minimumScaleFactor = 0.5

            guard let naturalLayout = NativeTextRenderer.layout(text, style: baseStyle, scaleFactor: 1.0, maxWidth: nil) else {
                return (nil, nil)
            }

            let constrainedLayout = NativeTextRenderer.layout(
                text,
                style: scaledStyle,
                scaleFactor: 1.0,
                maxWidth: naturalLayout.contentSize.width * 0.75
            )
            return (naturalLayout, constrainedLayout)
        }

        guard let naturalLayout = result.0, let constrainedLayout = result.1 else {
            return XCTFail("Expected native text layouts")
        }

        XCTAssertEqual(constrainedLayout.lines.map(\.text), naturalLayout.lines.map(\.text))
        XCTAssertLessThan(constrainedLayout.contentSize.width, naturalLayout.contentSize.width)
        XCTAssertLessThan(
            constrainedLayout.lines.first?.glyphs.first?.fontSize ?? 24,
            naturalLayout.lines.first?.glyphs.first?.fontSize ?? 0
        )
    }

    func testDirectWriteMeasurementReservesLineLimitSpaceWhenAvailable() async throws {
        let capabilities = await MainActor.run {
            TextSystem.capabilities()
        }

        guard capabilities.dwriteFactoryCreationSucceeded else {
            throw XCTSkip("DirectWrite is not available on this environment")
        }

        let result = await MainActor.run { () -> (Size?, Size?) in
            let baseStyle = PixelTextStyle(
                color: .white,
                alignment: .leading,
                verticalAlignment: .top,
                nativeFontSize: 18,
                lineBreakMode: .wrap,
                maximumNumberOfLines: 3
            )
            var reservedStyle = baseStyle
            reservedStyle.reservesLineLimitSpace = true

            return (
                NativeTextRenderer.measure("One", style: baseStyle, scaleFactor: 1.0, maxWidth: nil),
                NativeTextRenderer.measure("One", style: reservedStyle, scaleFactor: 1.0, maxWidth: nil)
            )
        }

        guard let unreserved = result.0, let reserved = result.1 else {
            return XCTFail("Expected native text measurements")
        }

        XCTAssertGreaterThan(reserved.height, unreserved.height)
    }
}

private struct MockTextLibraryLoader: TextLibraryLoading {
    let moduleAvailable: Bool
    let hasFactorySymbol: Bool
    let factoryCreationResult: (HRESULT, UnsafeMutableRawPointer?)?

    func loadLibrary(named name: String) -> HMODULE? {
        moduleAvailable ? HMODULE(bitPattern: 1) : nil
    }

    func unloadLibrary(_ module: HMODULE) {}

    func loadSymbol(named name: String, from module: HMODULE) -> FARPROC? {
        hasFactorySymbol ? mockFarProc : nil
    }

    func createDWriteFactory(from module: HMODULE, iid: UnsafePointer<GUID>) -> (HRESULT, UnsafeMutableRawPointer?)? {
        factoryCreationResult
    }

    func releaseFactory(_ rawPointer: UnsafeMutableRawPointer) {}
}

private let mockFarProc: FARPROC = {
    0
}
