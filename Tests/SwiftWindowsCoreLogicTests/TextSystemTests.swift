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
        XCTAssertNotNil(result?.lines.first?.glyphs.first?.glyphID)
        XCTAssertNotNil(result?.lines.first?.glyphs.first?.fontFace)
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

            _ = system.layout(text, style: spanScaledStyle, maxWidth: 140, scaleFactor: 1.0)
            counts.append(system.cachedLayoutCount)

            return counts
        }

        XCTAssertEqual(counts, [1, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12])
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
