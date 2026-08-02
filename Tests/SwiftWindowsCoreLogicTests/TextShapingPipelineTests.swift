import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// WS-17. The text pipeline's shaped path, its coordinate frames, its
/// `Double -> Int` conversions, its font identity and its wrap complexity.
///
/// Everything here except the registry and the wrap-complexity cases needs a
/// real DirectWrite; the suite runs on Windows, where it is always present.
/// Cases that would silently pass on a machine without it assert that the
/// layout came back at all first.
final class TextShapingPipelineTests: XCTestCase {
    override func tearDown() async throws {
        await MainActor.run {
            NativeTextRenderer.isGlyphShapingEnabled = true
            NativeTextRenderer.defaultIconDisplayScale = 1
            TextRenderDiagnosticsCounters.resetForTesting()
            NativeGlyphAtlas.shared.resetForTesting()
        }
        try await super.tearDown()
    }

    /// Root + text child, matching how the runtime emits text: the painter
    /// draws a node's text inside its frame, so the text needs a frame of its
    /// own inside the surface.
    @MainActor
    private func paintText(_ text: String, style: PixelTextStyle? = nil) -> GPUIScene {
        let surface = Size(width: 320, height: 80)
        let child = ViewNode(
            frame: Rect(x: 0, y: 0, width: 300, height: 40),
            text: text,
            textStyle: style ?? bodyStyle()
        )
        let root = ViewNode(frame: Rect(origin: .zero, size: surface), children: [child])
        return ScenePainter.paint(root: root, clearColor: .black, surfaceSize: surface)
    }

    private func bodyStyle(size: Double = 16) -> PixelTextStyle {
        PixelTextStyle(
            color: .white,
            alignment: .leading,
            verticalAlignment: .top,
            fontFamily: "Segoe UI",
            nativeFontSize: size,
            lineBreakMode: .clip
        )
    }

    // MARK: - Shaping is the primary path

    @MainActor
    func testLatinLayoutProducesShapedGlyphIdentity() async throws {
        let layout = try XCTUnwrap(
            NativeTextRenderer.layout("Handgloves", style: bodyStyle(), scaleFactor: 1),
            "DirectWrite must lay out a plain Latin string")
        let line = try XCTUnwrap(layout.lines.first)
        XCTAssertFalse(line.glyphs.isEmpty)

        for glyph in line.glyphs {
            XCTAssertNotNil(glyph.glyphID, "shaped run must carry glyph IDs")
            XCTAssertNotNil(glyph.fontFace, "shaped run must carry the resolved font face")
            XCTAssertNotNil(glyph.fontFaceID, "shaped run must carry a registry face ID")
            XCTAssertEqual(
                glyph.verticalFrame, .baseline,
                "DrawGlyphRun reports a baseline origin, so origin.y is baseline-relative")
        }
    }

    @MainActor
    func testShapingDisabledFallsBackToPerCharacterWalk() async throws {
        NativeTextRenderer.isGlyphShapingEnabled = false
        defer { NativeTextRenderer.isGlyphShapingEnabled = true }

        let layout = try XCTUnwrap(NativeTextRenderer.layout("Handgloves", style: bodyStyle(), scaleFactor: 1))
        let line = try XCTUnwrap(layout.lines.first)
        XCTAssertFalse(line.glyphs.isEmpty, "the escape hatch must keep producing glyphs")

        for glyph in line.glyphs {
            XCTAssertNil(glyph.glyphID, "the hit-test walk has no glyph IDs")
            XCTAssertEqual(glyph.verticalFrame, .layoutBoxTop)
            XCTAssertEqual(glyph.origin.y, 0, accuracy: 1e-9)
        }
    }

    @MainActor
    func testLigatureCandidateNeverEmitsMoreGlyphsThanCharacters() async throws {
        // Whether "ffi" collapses into one glyph is a property of the installed
        // font, so the assertion is the invariant shaping guarantees in every
        // font: a shaped run has at most one glyph per character (the
        // per-character walk always has exactly one), and every glyph carries
        // the identity that lets the atlas key it.
        let text = "office fluffier"
        let layout = try XCTUnwrap(NativeTextRenderer.layout(text, style: bodyStyle(), scaleFactor: 1))
        let line = try XCTUnwrap(layout.lines.first)

        XCTAssertLessThanOrEqual(line.glyphs.count, text.count)
        XCTAssertTrue(line.glyphs.allSatisfy { $0.glyphID != nil })
    }

    @MainActor
    func testShapedAndUnshapedLayoutsAgreeOnMeasuredWidth() async throws {
        let style = bodyStyle()
        let shaped = try XCTUnwrap(NativeTextRenderer.measure("Handgloves 123", style: style, scaleFactor: 1))

        NativeTextRenderer.isGlyphShapingEnabled = false
        let unshaped = try XCTUnwrap(NativeTextRenderer.measure("Handgloves 123", style: style, scaleFactor: 1))
        NativeTextRenderer.isGlyphShapingEnabled = true

        // Measurement comes from the layout's own bounds either way, so
        // enabling shaping must not move layout.
        XCTAssertEqual(shaped.width, unshaped.width, accuracy: 0.001)
        XCTAssertEqual(shaped.height, unshaped.height, accuracy: 0.001)
    }

    // MARK: - Glyph coordinate frames

    @MainActor
    func testGlyphRastersDeclareTheFrameTheyMeasuredInkFrom() async throws {
        let style = bodyStyle()
        let characterRaster = try XCTUnwrap(
            NativeTextRenderer.rasterizeGlyph(Character("H"), style: style, scaleFactor: 1))
        XCTAssertEqual(
            characterRaster.verticalFrame, .layoutBoxTop,
            "a one-character layout measures ink from its own box top")

        let layout = try XCTUnwrap(NativeTextRenderer.layout("H", style: style, scaleFactor: 1))
        let glyph = try XCTUnwrap(layout.lines.first?.glyphs.first)
        let shapedRaster = try XCTUnwrap(NativeTextRenderer.rasterizeGlyph(glyph, style: style, scaleFactor: 1))
        XCTAssertEqual(
            shapedRaster.verticalFrame, .baseline,
            "a shaped run is drawn at a known baseline and cropped back to it")

        // The two conventions differ by roughly one ascent; that difference is
        // exactly why the frame has to travel with the value.
        XCTAssertGreaterThan(Double(characterRaster.bearingY), Double(shapedRaster.bearingY))
    }

    @MainActor
    func testAtlasEntryCarriesTheRasterFrame() async throws {
        let atlas = NativeGlyphAtlas(atlasWidth: 512, atlasHeight: 512)
        let style = bodyStyle()
        let layout = try XCTUnwrap(NativeTextRenderer.layout("H", style: style, scaleFactor: 1))
        let glyph = try XCTUnwrap(layout.lines.first?.glyphs.first)

        let shapedEntry = try XCTUnwrap(atlas.glyph(for: glyph, style: style, scaleFactor: 1))
        XCTAssertEqual(shapedEntry.verticalFrame, .baseline)

        let characterEntry = try XCTUnwrap(atlas.glyph(for: Character("H"), style: style, scaleFactor: 1))
        XCTAssertEqual(characterEntry.verticalFrame, .layoutBoxTop)
    }

    @MainActor
    func testShapedTextPaintsAtTheSameHeightAsUnshapedText() async {
        func glyphTops(shaping: Bool) -> [Float] {
            NativeTextRenderer.isGlyphShapingEnabled = shaping
            NativeGlyphAtlas.shared.resetForTesting()
            let scene = paintText("Handgloves")
            return scene.layers.flatMap { $0.glyphs }.map(\.screenY).sorted()
        }

        let shaped = glyphTops(shaping: true)
        let unshaped = glyphTops(shaping: false)
        NativeTextRenderer.isGlyphShapingEnabled = true
        NativeGlyphAtlas.shared.resetForTesting()

        XCTAssertFalse(shaped.isEmpty, "text must paint through the native glyph path")
        XCTAssertEqual(shaped.count, unshaped.count)
        // The frame plumbing exists so both paths land on the same pixels. A
        // one-ascent mis-anchor would show up here as a double-digit delta.
        for (lhs, rhs) in zip(shaped, unshaped) {
            XCTAssertEqual(Double(lhs), Double(rhs), accuracy: 1.0)
        }
    }

    // MARK: - Conversion guards

    @MainActor
    func testFramePathRasterSizeSurvivesNonFiniteFrames() async {
        let style = bodyStyle()
        let measured = Size(width: 120, height: 20)

        for frame in [
            Size(width: .infinity, height: .infinity),
            Size(width: .nan, height: .nan),
            Size(width: -.infinity, height: 1e30),
            Size(width: 1e30, height: .infinity),
        ] {
            let size = framePathTextRasterSize(frameSize: frame, measured: measured, style: style)
            XCTAssertTrue(size.width.isFinite, "width must be finite for \(frame)")
            XCTAssertTrue(size.height.isFinite, "height must be finite for \(frame)")
            XCTAssertLessThanOrEqual(size.width, 4096)
            XCTAssertLessThanOrEqual(size.height, 4096)
            XCTAssertGreaterThanOrEqual(size.width, 0)
            XCTAssertGreaterThanOrEqual(size.height, 0)
        }
    }

    @MainActor
    func testUnboundedFrameRastersAtTheMeasuredSizeNotTheCeiling() async {
        let style = bodyStyle()
        let measured = Size(width: 120, height: 20)
        let size = framePathTextRasterSize(
            frameSize: Size(width: .infinity, height: 20), measured: measured, style: style)

        // An unbounded frame supplies no floor, so a six-character label must
        // not rasterize a 4096-wide bitmap.
        XCTAssertEqual(size.width, 120, accuracy: 0.5)
    }

    @MainActor
    func testFramePathRasterSizeWithoutMeasurementStaysFinite() async {
        let size = framePathTextRasterSize(
            frameSize: Size(width: .infinity, height: .nan), measured: nil, style: bodyStyle())
        XCTAssertTrue(size.width.isFinite)
        XCTAssertTrue(size.height.isFinite)
    }

    @MainActor
    func testAppendCommandsWithNonFiniteRectReturnsFalseInsteadOfTrapping() async {
        var commands: [RenderCommand] = []
        let didAppend = NativeTextRenderer.appendCommands(
            for: "Frame",
            in: Rect(x: .infinity, y: 0, width: .infinity, height: 20),
            style: bodyStyle(),
            scaleFactor: 1,
            clipRect: nil,
            into: &commands
        )
        XCTAssertFalse(didAppend)
        XCTAssertTrue(commands.isEmpty)
    }

    @MainActor
    func testAppendCommandsWithInfiniteWidthStillDrawsAtAFiniteSize() async {
        var commands: [RenderCommand] = []
        let didAppend = NativeTextRenderer.appendCommands(
            for: "Frame",
            in: Rect(x: 0, y: 0, width: .infinity, height: 24),
            style: bodyStyle(),
            scaleFactor: 1,
            clipRect: nil,
            into: &commands
        )

        // A finite origin with an unbounded size is ordinary app code
        // (`.frame(maxWidth: .infinity)`): it must draw, at a sane size.
        XCTAssertTrue(didAppend)
        guard case .drawBitmap(let command)? = commands.first else {
            return XCTFail("expected a bitmap draw, got \(commands)")
        }
        XCTAssertTrue(command.rect.size.width.isFinite)
        XCTAssertLessThanOrEqual(command.rect.size.width, 4096)
        XCTAssertLessThanOrEqual(command.bitmap.width, 8192)
    }

    @MainActor
    func testRoundedUpConversionsRejectNonFiniteInput() async {
        XCTAssertNil(roundedUpInt32(.infinity, minimum: 1))
        XCTAssertNil(roundedUpInt32(.nan, minimum: 1))
        XCTAssertNil(roundedUpUInt32(.infinity, minimum: 1))
        XCTAssertNil(roundedUpUInt32(.nan, minimum: 1))
        XCTAssertNil(roundedUpUInt32(-5, minimum: 1))
        XCTAssertEqual(roundedUpInt32(12.2, minimum: 1), 13)
        XCTAssertEqual(roundedUpInt32(1e30, minimum: 1), nil)
        XCTAssertEqual(roundedUpInt32(9000, minimum: 1, maximum: 4096), 4096)
        XCTAssertEqual(roundedUpUInt32(0.2, minimum: 4), 4)
    }

    // MARK: - Font identity

    private final class FakeFontFace: RetainedFontFace {
        let faceAddress: UInt
        init(faceAddress: UInt) { self.faceAddress = faceAddress }
    }

    @MainActor
    func testFontFaceRegistryHandsOutStableMonotonicIdentifiers() async {
        let registry = FontFaceRegistry()
        let first = FakeFontFace(faceAddress: 0x1000)
        let second = FakeFontFace(faceAddress: 0x2000)

        let firstID = registry.identifier(for: first)
        let secondID = registry.identifier(for: second)

        XCTAssertNotEqual(firstID, secondID, "two live faces must never share an ID")
        XCTAssertEqual(registry.identifier(for: first), firstID, "identity must be stable")
        XCTAssertGreaterThan(secondID.rawValue, firstID.rawValue, "IDs are monotonic, never recycled")
        XCTAssertEqual(registry.registeredFaceCount, 2)
    }

    @MainActor
    func testFontFaceRegistryRetainsRegisteredFaces() async {
        let registry = FontFaceRegistry()
        weak var weakFace: FakeFontFace?
        do {
            let face = FakeFontFace(faceAddress: 0x3000)
            weakFace = face
            _ = registry.identifier(for: face)
        }

        // Retention is the whole point: a released face frees its address, and
        // the next face allocated there would inherit its atlas entries.
        XCTAssertNotNil(weakFace, "the registry must keep every face it has issued an ID for alive")
        registry.resetForTesting()
        XCTAssertNil(weakFace)
    }

    @MainActor
    func testDistinctFaceIdentifiersYieldDistinctAtlasEntries() async {
        let atlas = GlyphAtlas(width: 64, height: 64)
        let cache = GlyphAtlasCache(atlas: atlas, maxEntries: 16)
        let registry = FontFaceRegistry()
        let firstID = registry.identifier(for: FakeFontFace(faceAddress: 0x4000))
        let secondID = registry.identifier(for: FakeFontFace(faceAddress: 0x5000))

        func key(_ faceID: FontFaceID) -> GlyphKey {
            GlyphKey(
                character: "A", glyphID: 77, fontFaceID: faceID.rawValue, fontFamily: "Segoe UI",
                fontSize: 16, weight: .regular)
        }

        let pixels = Data(repeating: 0xFF, count: 4 * 4 * 4)
        let firstEntry = cache.insert(
            key: key(firstID), pixels: pixels, width: 4, height: 4, bearingX: 0, bearingY: 0, advance: 4)
        let secondEntry = cache.insert(
            key: key(secondID), pixels: pixels, width: 4, height: 4, bearingX: 0, bearingY: 0, advance: 4)

        XCTAssertNotNil(firstEntry)
        XCTAssertNotNil(secondEntry)
        XCTAssertEqual(cache.count, 2, "glyph 77 of two faces must occupy two atlas cells")
        XCTAssertNotEqual(firstEntry?.atlasX ?? 0, secondEntry?.atlasX ?? 0)
        XCTAssertNil(cache.peek(key(FontFaceID(rawValue: 999))), "an unrelated face must not alias either")
    }

    // MARK: - Fallback raster style

    @MainActor
    func testGlyphRasterUsesTheGlyphsOwnFontSizeNotTheParagraphs() async throws {
        // A `TextSpan` at .title inside body text produces a glyph whose
        // fontSize is the span's. The atlas keys on that size, so the raster
        // has to be taken at it — caching a body-size bitmap under a title-size
        // key made every later frame draw the small glyph.
        let paragraphStyle = bodyStyle(size: 12)
        let spanGlyph = NativeTextGlyphLayout(
            character: "H",
            origin: .zero,
            advance: 20,
            fontFamily: "Segoe UI",
            weight: .regular,
            fontSize: 36
        )

        let spanRaster = try XCTUnwrap(
            NativeTextRenderer.rasterizeGlyph(spanGlyph, style: paragraphStyle, scaleFactor: 1))
        let paragraphRaster = try XCTUnwrap(
            NativeTextRenderer.rasterizeGlyph(Character("H"), style: paragraphStyle, scaleFactor: 1))

        XCTAssertGreaterThan(
            spanRaster.height, paragraphRaster.height,
            "a 36pt glyph must not be rastered at the paragraph's 12pt")
        XCTAssertGreaterThan(Double(spanRaster.height), Double(paragraphRaster.height) * 1.8)
    }

    @MainActor
    func testNonFiniteGlyphFontSizeFallsBackToTheParagraphSize() async {
        let glyph = NativeTextGlyphLayout(
            character: "H", origin: .zero, advance: 10, fontFamily: "Segoe UI", weight: .regular,
            fontSize: .nan)
        // Must not trap and must still produce something drawable.
        let raster = NativeTextRenderer.rasterizeGlyph(glyph, style: bodyStyle(size: 18), scaleFactor: 1)
        XCTAssertNotNil(raster)
    }

    // MARK: - Tracking

    @MainActor
    func testNativeTrackingMovesBothMeasurementAndPaintedAdvance() async throws {
        var plain = bodyStyle()
        plain.nativeLetterSpacing = nil
        var tracked = bodyStyle()
        tracked.nativeLetterSpacing = 4

        let plainSize = try XCTUnwrap(NativeTextRenderer.measure("Handgloves", style: plain, scaleFactor: 1))
        let trackedSize = try XCTUnwrap(NativeTextRenderer.measure("Handgloves", style: tracked, scaleFactor: 1))
        XCTAssertEqual(trackedSize.width - plainSize.width, 9 * 4, accuracy: 1.5)

        let plainLine = try XCTUnwrap(
            NativeTextRenderer.layout("Handgloves", style: plain, scaleFactor: 1)?.lines.first)
        let trackedLine = try XCTUnwrap(
            NativeTextRenderer.layout("Handgloves", style: tracked, scaleFactor: 1)?.lines.first)
        let plainLast = try XCTUnwrap(plainLine.glyphs.last)
        let trackedLast = try XCTUnwrap(trackedLine.glyphs.last)
        XCTAssertGreaterThan(
            trackedLast.origin.x, plainLast.origin.x + 20,
            "tracking must move painted glyph positions, not only the cache key")
    }

    @MainActor
    func testPixelFontLetterSpacingDefaultDoesNotTrackNativeText() async throws {
        // `PixelTextStyle.letterSpacing` defaults to 1 because that is the 5x7
        // atlas's inter-glyph gap. Treating it as points would space every
        // string in the app out by a point per character.
        var style = bodyStyle()
        style.letterSpacing = 1
        style.nativeLetterSpacing = nil
        let withGap = try XCTUnwrap(NativeTextRenderer.measure("Handgloves", style: style, scaleFactor: 1))

        style.letterSpacing = 0
        let withoutGap = try XCTUnwrap(NativeTextRenderer.measure("Handgloves", style: style, scaleFactor: 1))
        XCTAssertEqual(withGap.width, withoutGap.width, accuracy: 0.001)
    }

    // MARK: - Wrap complexity

    @MainActor
    func testSpacelessWrapProbesStayLinearInLength() async {
        // 20,000 CJK characters with no break opportunity: one token, wrapped
        // into ~n/m slices. A plain binary search measures ~n/2 characters on
        // its first probe of every slice; galloping bounds each probe at ~2x
        // the answer.
        let text = String(repeating: "\u{6F22}", count: 20000)
        var style = bodyStyle()
        style.lineBreakMode = .wrap
        var probeCount = 0
        var charactersMeasured = 0

        let resolved = resolveTextLayout(
            for: text,
            style: style,
            maxContentWidth: 400,
            measureLine: { line in
                probeCount += 1
                charactersMeasured += line.count
                return Double(line.count) * 16
            }
        )

        XCTAssertGreaterThan(resolved.lines.count, 100)
        XCTAssertEqual(resolved.lines.joined().count, text.count, "wrapping must not lose characters")
        // A plain binary search costs ~n^2 log n / m characters measured
        // (~10^8 here). Galloping keeps it within a small multiple of n.
        XCTAssertLessThan(charactersMeasured, 40 * text.count)
        XCTAssertLessThan(probeCount, 40 * resolved.lines.count)
    }

    @MainActor
    func testSpacelessWrapCompletesWithinBudget() async {
        let text = String(repeating: "\u{6F22}", count: 20000)
        var style = bodyStyle()
        style.lineBreakMode = .wrap

        let start = Date()
        let resolved = resolveTextLayout(
            for: text, style: style, maxContentWidth: 400,
            measureLine: { Double($0.count) * 16 })
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertFalse(resolved.lines.isEmpty)
        XCTAssertLessThan(elapsed, 5.0, "a 20k-character space-less wrap must not freeze the main actor")
    }

    @MainActor
    func testGallopingPrefixSearchAgreesWithExhaustiveSearch() async {
        // Same answers, different probe sequence: the widths below are
        // deliberately irregular so an off-by-one in the gallop shows up.
        var style = bodyStyle()
        style.lineBreakMode = .wrap
        for limit in [1.0, 17.0, 40.0, 133.0, 1000.0] {
            let text = String(repeating: "x", count: 200)
            let resolved = resolveTextLayout(
                for: text, style: style, maxContentWidth: limit,
                measureLine: { Double($0.count) * 7 })
            let perLine = Int(limit / 7)
            let expected = max(1, perLine)
            XCTAssertEqual(
                resolved.lines.first?.count, min(expected, 200),
                "limit \(limit) should fit \(expected) characters on the first line")
            XCTAssertEqual(resolved.lines.joined().count, 200)
        }
    }

    // MARK: - Diagnostics

    @MainActor
    func testPixelFontFallbackIsCounted() async {
        NativeGlyphAtlas.shared.resetForTesting()
        // A private-use codepoint forces the native path to decline for the
        // whole string, which is the 5x7 quality cliff.
        let scene = paintText("\u{E721} MENU")
        XCTAssertGreaterThan(scene.paintMetrics.textDiagnostics.pixelFontFallbacks, 0)
        XCTAssertFalse(scene.paintMetrics.textDiagnostics.isClean)
    }

    @MainActor
    func testCleanTextSceneReportsNoDegradation() async {
        NativeGlyphAtlas.shared.resetForTesting()
        let scene = paintText("Handgloves")
        XCTAssertFalse(
            scene.layers.flatMap { $0.glyphs }.isEmpty, "the clean case must actually draw native glyphs")
        let diagnostics = scene.paintMetrics.textDiagnostics
        XCTAssertEqual(diagnostics.pixelFontFallbacks, 0)
        XCTAssertEqual(diagnostics.atlasRecoveries, 0)
        XCTAssertEqual(diagnostics.unshapedGlyphRuns, 0, "shaping must be the path a healthy scene takes")
        XCTAssertTrue(diagnostics.isClean)
    }

    // MARK: - Icon raster scale

    @MainActor
    func testIconRasterScaleComesFromTheEnvironmentNotTheProcessGlobal() async {
        NativeTextRenderer.defaultIconDisplayScale = 1
        let base = ViewBuildContext(
            canvasSizeProvider: { Size(width: 200, height: 100) },
            invalidateHandler: {}
        )

        XCTAssertEqual(base.withEnvironmentValue(\.displayScale, 1).iconRasterDisplayScale, 1)
        XCTAssertEqual(base.withEnvironmentValue(\.displayScale, 2).iconRasterDisplayScale, 2)
        // Two hosts at different scales read different values from the same
        // process; the global no longer decides for both.
        XCTAssertEqual(NativeTextRenderer.defaultIconDisplayScale, 1)
        XCTAssertEqual(base.withEnvironmentValue(\.displayScale, 0).iconRasterDisplayScale, 1)
        XCTAssertEqual(base.withEnvironmentValue(\.displayScale, .nan).iconRasterDisplayScale, 1)
    }

    @MainActor
    func testIconsRasterizeAtTheContextScale() async throws {
        NativeTextRenderer.defaultIconDisplayScale = 1
        let scaleOne = Controls.icon(.search, preferredSize: Size(width: 24, height: 24), displayScale: 1)
        let scaleTwo = Controls.icon(.search, preferredSize: Size(width: 24, height: 24), displayScale: 2)

        let one = try XCTUnwrap(scaleOne.bitmapSurface)
        let two = try XCTUnwrap(scaleTwo.bitmapSurface)
        XCTAssertGreaterThan(two.width, one.width)
        // The process-global stayed at 1 throughout: the scale came from the
        // caller, which is now the view's environment.
        XCTAssertEqual(NativeTextRenderer.defaultIconDisplayScale, 1)
    }
}
