import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import WinSDK

/// Weak box for ``NativeTextRenderer/claimDefaultIconDisplayScale(_:owner:)``:
/// the claim list must never keep a window host alive.
@MainActor
private struct WeakIconDisplayScaleClaimant {
    weak var object: AnyObject?
}

@MainActor
public enum NativeTextRenderer {
    /// Display scale applied to icon bitmaps rasterized without an explicit
    /// scale (the `displayScale` default of `Controls.icon`).
    ///
    /// This is a *last-resort* default for callers with no view environment —
    /// `DeclarativeUI`, tools, tests. Every `WinSwiftUI` icon now passes
    /// `ViewBuildContext.iconRasterDisplayScale`, which reads
    /// `EnvironmentValues.displayScale`, because a process-global that every
    /// window host overwrites on activation meant the last window to activate
    /// decided the icon raster scale for all of them at mixed DPI.
    /// It defaults to 1 — the deterministic screenshot value — and offscreen
    /// scale-1 tools leave it untouched, keeping their output byte-identical.
    ///
    /// Hosts must not write this directly: use
    /// ``claimDefaultIconDisplayScale(_:owner:)``, which refuses to let a
    /// second window stomp the first. Direct writes remain available for
    /// scoped, restored overrides (`RenderSnapshot`) and tests.
    public static var defaultIconDisplayScale: Double = 1

    /// Hosts that have claimed the process-global default, held weakly so a
    /// closed window drops out without needing a matching release call
    /// (and so a recycled address can never be mistaken for a live host).
    private static var iconDisplayScaleClaimants: [WeakIconDisplayScaleClaimant] = []

    /// Live hosts currently claiming ``defaultIconDisplayScale``.
    public static var iconDisplayScaleClaimantCount: Int {
        compactIconDisplayScaleClaimants()
        return iconDisplayScaleClaimants.count
    }

    /// Claims the process-global icon raster scale on behalf of `owner`.
    ///
    /// The write lands only while there is exactly one live claimant — the
    /// single-window case, where the scale is unambiguous, including after a
    /// DPI change or a monitor move. A second window opening leaves the value
    /// where the first window put it instead of overwriting it, because with
    /// two windows on different monitors there is no correct process-wide
    /// answer: the last host to activate or resize would otherwise decide the
    /// icon raster scale for every other window.
    ///
    /// This is a hazard *bound*, not a fix. `WinSwiftUI` icons never read the
    /// global — they take `ViewBuildContext.iconRasterDisplayScale`, which
    /// reads `EnvironmentValues.displayScale` and is therefore per-window
    /// correct at mixed DPI. What is left exposed is the last-resort default
    /// of `Controls.icon` for callers with no view environment
    /// (`DeclarativeUI`, tools, tests); in a multi-window process those
    /// callers get the first window's scale. De-globalizing that default is
    /// the real fix and is not attempted here.
    ///
    /// - Returns: whether ``defaultIconDisplayScale`` was written.
    @discardableResult
    public static func claimDefaultIconDisplayScale(_ scale: Double, owner: AnyObject) -> Bool {
        compactIconDisplayScaleClaimants()
        if !iconDisplayScaleClaimants.contains(where: { $0.object === owner }) {
            iconDisplayScaleClaimants.append(WeakIconDisplayScaleClaimant(object: owner))
        }

        guard iconDisplayScaleClaimants.count == 1 else {
            return false
        }

        defaultIconDisplayScale = scale
        return true
    }

    private static func compactIconDisplayScaleClaimants() {
        iconDisplayScaleClaimants.removeAll { $0.object == nil }
    }

    /// Drops every claim so a test starts from the single-window case
    /// regardless of what a host in an earlier test left alive.
    internal static func resetIconDisplayScaleClaimsForTesting() {
        iconDisplayScaleClaimants.removeAll()
    }

    /// Whether `layoutLine` resolves glyph runs through DirectWrite shaping
    /// (glyph IDs, shaped advances, cluster map) instead of the per-character
    /// `HitTestTextPosition` walk.
    ///
    /// Shaping is the correct path and the default: without it, ligatures paint
    /// as overlapping isolated glyphs and complex scripts render in isolated
    /// forms at shaped positions. The flag is an escape hatch - flip it off and
    /// the whole pipeline reverts to the per-character walk, which is fully
    /// intact and still exercised whenever a capture comes back empty.
    public static var isGlyphShapingEnabled: Bool = true

    struct TestingOverrides {
        var measure: ((String, PixelTextStyle, Double, Double?) -> Size?)?
        var layout: ((String, PixelTextStyle, Double, Double?) -> NativeTextLayoutResult?)?
        var editingLine: ((String, PixelTextStyle, Double) -> NativeTextEditingLine?)?
        var appendCommands: ((String, Rect, PixelTextStyle, Double, Rect?, inout [RenderCommand]) -> Bool)?
        var rasterize: ((String, PixelTextStyle, Double) -> BitmapSurface?)?
        var rasterizeGlyphForCharacter: ((Character, PixelTextStyle, Double) -> NativeGlyphBitmap?)?
        var rasterizeGlyphForLayout: ((NativeTextGlyphLayout, PixelTextStyle, Double) -> NativeGlyphBitmap?)?
    }

    static var testingOverrides = TestingOverrides()

    static func resetTestingOverrides() {
        testingOverrides = TestingOverrides()
    }

    static func measure(_ text: String, style: PixelTextStyle, scaleFactor: Double, maxWidth: Double? = nil) -> Size? {
        if let override = testingOverrides.measure {
            return override(text, style, scaleFactor, maxWidth)
        }
        if let layout = layout(text, style: style, scaleFactor: scaleFactor, maxWidth: maxWidth) {
            return layout.measuredSize
        }

        return DirectWriteTextRenderer.measure(text, style: style, scaleFactor: scaleFactor, maxWidth: maxWidth)
            ?? GDIRasterTextRenderer.measure(text, style: style, scaleFactor: scaleFactor, maxWidth: maxWidth)
    }

    static func layout(_ text: String, style: PixelTextStyle, scaleFactor: Double, maxWidth: Double? = nil)
        -> NativeTextLayoutResult?
    {
        if let override = testingOverrides.layout {
            return override(text, style, scaleFactor, maxWidth)
        }
        return DirectWriteTextRenderer.layout(text, style: style, scaleFactor: scaleFactor, maxWidth: maxWidth)
    }

    /// Only editor snapshots ask for native caret and selection geometry.
    /// Existing layout overrides remain authoritative, so a synthetic editor
    /// fixture never accidentally consults the machine's installed fonts.
    static func editingLine(_ text: String, style: PixelTextStyle, scaleFactor: Double) -> NativeTextEditingLine? {
        if let override = testingOverrides.editingLine {
            return override(text, style, scaleFactor)
        }
        if let override = testingOverrides.layout {
            if let layout = override(text, style, scaleFactor, nil) {
                return editingLineFromSyntheticLayout(layout, text: text, style: style)
            }
            if let size = unshapedEditingLineSize(text, style: style, scaleFactor: scaleFactor) {
                return NativeTextEditingLine(
                    text: text, width: size.width, height: size.height, carets: [], selectionRegions: [])
            }
            return pixelEditingLine(text, style: style)
        }
        if let line = DirectWriteTextRenderer.editingLine(text, style: style, scaleFactor: scaleFactor) {
            return line
        }
        // A failed native caret extraction is not permission to place pixel
        // carets over native glyphs. Keep exact drawable line metrics and make
        // the missing geometry explicit to the snapshot consumer.
        if let native = layout(text.isEmpty ? " " : text, style: style, scaleFactor: scaleFactor)?.lines.first {
            return NativeTextEditingLine(
                text: text, width: text.isEmpty ? 0 : native.width, height: native.height,
                carets: [], selectionRegions: [], lineSpacing: min(style.lineSpacing, 0))
        }
        if let size = unshapedEditingLineSize(text, style: style, scaleFactor: scaleFactor) {
            return NativeTextEditingLine(
                text: text, width: size.width, height: size.height, carets: [], selectionRegions: [])
        }
        return pixelEditingLine(text, style: style)
    }

    /// Wrapping probes need whole-fragment widths, not a native hit-test walk
    /// at every candidate prefix. The final chosen fragments request carets.
    static func editingLineSize(_ text: String, style: PixelTextStyle, scaleFactor: Double) -> Size? {
        if let override = testingOverrides.editingLine {
            guard let line = override(text, style, scaleFactor) else { return nil }
            return Size(width: line.width, height: line.height)
        }
        if let override = testingOverrides.layout {
            if let native = override(text, style, scaleFactor, nil)?.lines.first {
                return Size(width: text.isEmpty ? 0 : native.width, height: native.height)
            }
            return unshapedEditingLineSize(text, style: style, scaleFactor: scaleFactor)
                ?? pixelEditingLineSize(text, style: style)
        }
        if let native = layout(text.isEmpty ? " " : text, style: style, scaleFactor: scaleFactor)?.lines.first {
            return Size(width: text.isEmpty ? 0 : native.width, height: native.height)
        }
        return unshapedEditingLineSize(text, style: style, scaleFactor: scaleFactor)
            ?? pixelEditingLineSize(text, style: style)
    }

    private static func unshapedEditingLineSize(
        _ text: String, style: PixelTextStyle, scaleFactor: Double
    ) -> Size? {
        // The normal frame path can still paint native text through GDI when
        // DirectWrite glyph layout is unavailable. Its measured size permits
        // faithful whole-line painting, but supplies no native caret stops.
        // An injected layout may consult only an explicitly injected measure
        // fallback; never discover machine fonts behind a synthetic fixture.
        guard testingOverrides.layout == nil || testingOverrides.measure != nil,
            let size = measure(text.isEmpty ? " " : text, style: style, scaleFactor: scaleFactor)
        else { return nil }
        return Size(width: text.isEmpty ? 0 : size.width, height: size.height)
    }

    private static func editingLineFromSyntheticLayout(
        _ layout: NativeTextLayoutResult, text: String, style: PixelTextStyle
    ) -> NativeTextEditingLine? {
        guard layout.lines.count == 1, let line = layout.lines.first, line.text == text else { return nil }
        if text.isEmpty {
            return NativeTextEditingLine(
                text: text, width: 0, height: line.height,
                carets: [NativeTextEditingCaret(characterOffset: 0, affinity: .downstream, x: 0)],
                selectionRegions: [], lineSpacing: layout.lineSpacing)
        }
        let count = text.count
        // The original synthetic seam supplies one LTR glyph per Character.
        // More complex fixtures supply explicit editor geometry instead of
        // asking this adapter to invent cluster or bidi behavior.
        let indices = line.glyphs.compactMap(\.sourceIndex)
        var previousRight = 0.0
        let hasOrderedCells = line.glyphs.allSatisfy { glyph in
            let right = glyph.origin.x + glyph.advance
            guard glyph.origin.x.isFinite, glyph.origin.y.isFinite,
                glyph.advance.isFinite, glyph.advance >= 0, right.isFinite,
                glyph.origin.x >= previousRight
            else { return false }
            previousRight = right
            return true
        }
        guard indices == Array(0..<count), line.glyphs.count == count, hasOrderedCells else {
            return NativeTextEditingLine(
                text: text, width: line.width, height: line.height, carets: [], selectionRegions: [],
                lineSpacing: layout.lineSpacing)
        }
        var carets: [NativeTextEditingCaret] = []
        var regions: [NativeTextEditingRegion] = []
        for glyph in line.glyphs {
            guard let offset = glyph.sourceIndex else { continue }
            let leading = glyph.origin.x
            let trailing = leading + glyph.advance
            carets.append(NativeTextEditingCaret(characterOffset: offset, affinity: .downstream, x: leading))
            carets.append(NativeTextEditingCaret(characterOffset: offset + 1, affinity: .upstream, x: trailing))
            regions.append(
                NativeTextEditingRegion(
                    characterRange: offset..<(offset + 1),
                    rect: Rect(x: min(leading, trailing), y: 0, width: abs(trailing - leading), height: line.height)))
        }
        return NativeTextEditingLine(
            text: text, width: line.width, height: line.height, carets: carets, selectionRegions: regions,
            lineSpacing: layout.lineSpacing)
    }

    private static func pixelEditingLineSize(_ text: String, style: PixelTextStyle) -> Size {
        let scale = max(style.scale, 0.01)
        return Size(
            width: PixelFont.rawLineWidth(text.uppercased(), letterSpacing: style.letterSpacing) * scale,
            height: Double(PixelFont.glyphHeight) * scale)
    }

    private static func pixelEditingLine(_ text: String, style: PixelTextStyle) -> NativeTextEditingLine {
        let size = pixelEditingLineSize(text, style: style)
        let scale = max(style.scale, 0.01)
        let spacing = style.lineSpacing * scale
        // Pixel painting uppercases its input. A source-expanding transform
        // cannot supply one caret per source Character from a fixed advance.
        guard text.allSatisfy({ String($0).uppercased().count == 1 }) else {
            return NativeTextEditingLine(
                text: text, width: size.width, height: size.height, carets: [], selectionRegions: [],
                lineSpacing: spacing)
        }
        var carets = [NativeTextEditingCaret(characterOffset: 0, affinity: .downstream, x: 0)]
        var regions: [NativeTextEditingRegion] = []
        let count = text.count
        for offset in 0..<count {
            let leading = Double(offset) * (Double(PixelFont.glyphWidth) + style.letterSpacing) * scale
            let trailing = leading + Double(PixelFont.glyphWidth) * scale
            carets.append(NativeTextEditingCaret(characterOffset: offset, affinity: .downstream, x: leading))
            carets.append(NativeTextEditingCaret(characterOffset: offset + 1, affinity: .upstream, x: trailing))
            regions.append(
                NativeTextEditingRegion(
                    characterRange: offset..<(offset + 1),
                    rect: Rect(x: min(leading, trailing), y: 0, width: abs(trailing - leading), height: size.height)))
        }
        return NativeTextEditingLine(
            text: text, width: size.width, height: size.height, carets: carets, selectionRegions: regions,
            lineSpacing: spacing)
    }

    static func appendCommands(
        for text: String,
        in rect: Rect,
        style: PixelTextStyle,
        scaleFactor: Double,
        clipRect: Rect?,
        into commands: inout [RenderCommand]
    ) -> Bool {
        // A non-finite *origin* has no sane clamp - there is no pixel to draw
        // at - so the frame path declines and the caller falls back. A
        // non-finite *size* is fine: `framePathTextRasterSize` clamps it.
        guard rect.origin.x.isFinite, rect.origin.y.isFinite else {
            return false
        }

        let externalizesDecorations = style.hasTextDecorations
        let textRenderStyle = externalizesDecorations ? style.withoutTextDecorations : style

        if let override = testingOverrides.appendCommands {
            let didAppend = override(text, rect, textRenderStyle, scaleFactor, clipRect, &commands)
            appendExternalDecorationCommandsIfNeeded(
                didAppend: didAppend,
                text: text,
                rect: rect,
                style: style,
                scaleFactor: scaleFactor,
                clipRect: clipRect,
                into: &commands
            )
            return didAppend
        }
        let didAppend =
            DirectWriteTextRenderer.appendCommands(
                for: text,
                in: rect,
                style: textRenderStyle,
                scaleFactor: scaleFactor,
                clipRect: clipRect,
                into: &commands
            )
            || GDIRasterTextRenderer.appendCommands(
                for: text,
                in: rect,
                style: textRenderStyle,
                scaleFactor: scaleFactor,
                clipRect: clipRect,
                into: &commands
            )
        appendExternalDecorationCommandsIfNeeded(
            didAppend: didAppend,
            text: text,
            rect: rect,
            style: style,
            scaleFactor: scaleFactor,
            clipRect: clipRect,
            into: &commands
        )
        return didAppend
    }

    private static func appendExternalDecorationCommandsIfNeeded(
        didAppend: Bool,
        text: String,
        rect: Rect,
        style: PixelTextStyle,
        scaleFactor: Double,
        clipRect: Rect?,
        into commands: inout [RenderCommand]
    ) {
        guard didAppend, style.hasTextDecorations else {
            return
        }

        let contentWidth = max(0, rect.inset(by: style.insets).size.width)
        let nativeLayout = layout(text, style: style, scaleFactor: scaleFactor, maxWidth: contentWidth)
        TextDecorationCommandBuilder.appendCommands(
            for: text,
            in: rect,
            style: style,
            scaleFactor: scaleFactor,
            clipRect: clipRect,
            nativeLayout: nativeLayout,
            into: &commands
        )
    }

    static func rasterize(
        _ text: String, style: PixelTextStyle, scaleFactor: Double,
        observation: NativeBitmapFontObservation? = nil
    ) -> BitmapSurface? {
        if let override = testingOverrides.rasterize {
            let bitmap = override(text, style, scaleFactor)
            observation?.recordTestingOverrideResult(bitmap: bitmap)
            return bitmap
        }
        if let bitmap = DirectWriteTextRenderer.rasterize(
            text, style: style, scaleFactor: scaleFactor, observation: observation)
        {
            return bitmap
        }
        let bitmap = GDIRasterTextRenderer.rasterize(text, style: style, scaleFactor: scaleFactor)
        observation?.recordGDIResult(bitmap: bitmap)
        return bitmap
    }

    static func rasterizeGlyph(_ character: Character, style: PixelTextStyle, scaleFactor: Double) -> NativeGlyphBitmap?
    {
        if let override = testingOverrides.rasterizeGlyphForCharacter {
            return override(character, style, scaleFactor)
        }
        return DirectWriteTextRenderer.rasterizeGlyph(character, style: style, scaleFactor: scaleFactor)
    }

    static func rasterizeGlyph(_ glyph: NativeTextGlyphLayout, style: PixelTextStyle, scaleFactor: Double)
        -> NativeGlyphBitmap?
    {
        if let override = testingOverrides.rasterizeGlyphForLayout {
            return override(glyph, style, scaleFactor)
        }
        if let bitmap = DirectWriteTextRenderer.rasterizeGlyph(glyph, style: style, scaleFactor: scaleFactor) {
            return bitmap
        }

        // The atlas key is built from the *glyph's* family/weight/size, so the
        // last-chance raster has to use them too. Rasterizing the paragraph
        // style here cached a body-size bitmap under a title-size span's key,
        // and every later frame drew the small glyph.
        var glyphStyle = style
        glyphStyle.fontFamily = glyph.fontFamily
        glyphStyle.weight = glyph.weight
        glyphStyle.nativeFontSize = glyph.fontSize.isFinite ? max(glyph.fontSize, 1) : style.nativeFontPixelSize
        let bitmap = DirectWriteTextRenderer.rasterizeGlyph(
            glyph.character, style: glyphStyle, scaleFactor: scaleFactor)
        if bitmap == nil {
            TextRenderDiagnosticsCounters.glyphRasterFailures += 1
        }
        return bitmap
    }
}
@MainActor
enum GDIRasterTextRenderer {
    static func measure(
        _ text: String,
        style: PixelTextStyle,
        scaleFactor: Double,
        maxWidth: Double? = nil,
        resolvesMinimumScaleFactor: Bool = true
    ) -> Size? {
        guard !text.isEmpty else {
            return Size(
                width: style.insets.leading + style.insets.trailing, height: style.insets.top + style.insets.bottom)
        }

        guard let dc = CreateCompatibleDC(nil) else {
            return nil
        }
        defer { DeleteDC(dc) }

        guard let font = createFont(for: style, scaleFactor: scaleFactor) else {
            return nil
        }
        defer { DeleteObject(HGDIOBJ(font)) }

        let previousObject = SelectObject(dc, HGDIOBJ(font))
        defer { _ = SelectObject(dc, previousObject) }

        if resolvesMinimumScaleFactor {
            let effectiveStyle = style.resolvingMinimumScaleFactor(
                for: text,
                maxContentWidth: contentWidthLimit(for: maxWidth, style: style),
                measureLine: { line in
                    measureSingleLineWidth(line, in: dc, scaleFactor: scaleFactor) ?? 0
                }
            )
            if effectiveStyle != style {
                return measure(
                    text,
                    style: effectiveStyle,
                    scaleFactor: scaleFactor,
                    maxWidth: maxWidth,
                    resolvesMinimumScaleFactor: false
                )
            }
        }

        let resolvedLayout = resolveTextLayout(
            for: text,
            style: style,
            maxContentWidth: contentWidthLimit(for: maxWidth, style: style),
            measureLine: { line in
                measureSingleLineWidth(line, in: dc, scaleFactor: scaleFactor) ?? 0
            }
        )
        let resolvedText = resolvedLayout.text

        var measureRect = RECT(
            left: 0,
            top: 0,
            right: LONG(measureRectWidth(maxWidth: maxWidth, style: style, scaleFactor: scaleFactor)),
            bottom: 4096
        )
        let drawFlags =
            baseDrawTextFlags(
                for: resolvedText,
                alignment: style.alignment,
                lineBreakMode: resolvedLayout.lines.count > 1 ? .wrap : style.lineBreakMode
            ) | UINT(DT_CALCRECT)

        let measured = withWideString(resolvedText) { wideText in
            DrawTextW(dc, wideText, -1, &measureRect, drawFlags)
        }

        guard measured > 0 else {
            return nil
        }

        let contentWidth = Double(measureRect.right - measureRect.left) / scaleFactor
        let measuredHeight = Double(measured) / scaleFactor
        let reservedHeight: Double
        if let reservedLineCount = reservedTextLineCount(for: style) {
            let lineHeight = style.nativeFontPixelSize
            reservedHeight =
                Double(reservedLineCount) * lineHeight + Double(max(reservedLineCount - 1, 0)) * style.lineSpacing
        } else {
            reservedHeight = 0
        }
        let measuredWidth = clampedMeasuredWidth(
            contentWidth,
            style: style,
            maxWidth: maxWidth
        )
        let width = measuredWidth + style.insets.leading + style.insets.trailing
        let height = max(measuredHeight, reservedHeight) + style.insets.top + style.insets.bottom
        return Size(width: max(1, width), height: max(1, height))
    }

    static func appendCommands(
        for text: String,
        in rect: Rect,
        style: PixelTextStyle,
        scaleFactor: Double,
        clipRect: Rect?,
        into commands: inout [RenderCommand]
    ) -> Bool {
        // Match DirectWriteTextRenderer: a collapsed layout frame must not
        // shrink the pre-rasterized text bitmap (see framePathTextRasterSize).
        let measured = measure(
            text,
            style: style,
            scaleFactor: scaleFactor,
            maxWidth: rect.size.width.isFinite ? rect.size.width : nil
        )
        let rasterSize = framePathTextRasterSize(frameSize: rect.size, measured: measured, style: style)
        guard
            let bitmap = FramePathTextRaster.bitmap(
                for: text, size: rasterSize, style: style, scaleFactor: scaleFactor,
                rasterize: { rasterize(text, in: rasterSize, style: style, scaleFactor: scaleFactor) })
        else {
            return false
        }

        commands.append(
            .drawBitmap(
                DrawBitmapCommand(
                    rect: Rect(origin: rect.origin, size: rasterSize),
                    bitmap: bitmap,
                    opacity: 1.0,
                    clipRect: clipRect
                )
            )
        )

        return true
    }

    static func rasterize(_ text: String, style: PixelTextStyle, scaleFactor: Double) -> BitmapSurface? {
        guard let size = measure(text, style: style, scaleFactor: scaleFactor, maxWidth: nil) else {
            return nil
        }

        return rasterize(text, in: size, style: style, scaleFactor: scaleFactor)
    }

    static func rasterize(
        _ text: String,
        in size: Size,
        style: PixelTextStyle,
        scaleFactor: Double,
        resolvesMinimumScaleFactor: Bool = true
    ) -> BitmapSurface? {
        let rasterSize = size.scaled(by: scaleFactor)
        guard
            let pixelWidth = roundedUpInt32(
                rasterSize.width, minimum: 1, maximum: Int32(maximumRasterPixels)),
            let pixelHeight = roundedUpInt32(
                rasterSize.height, minimum: 1, maximum: Int32(maximumRasterPixels))
        else {
            return nil
        }
        guard
            let contentRect = drawRectForInsets(
                style.insets, width: pixelWidth, height: pixelHeight, scaleFactor: scaleFactor)
        else {
            return nil
        }
        let bytesPerRow = Int32(pixelWidth * 4)
        // `Int`, not `Int32`: the product of two clamped extents still exceeds
        // 2^31 at the ceiling, and a trap here is a crash on ordinary app code.
        let bufferSize = Int(bytesPerRow) * Int(pixelHeight)

        guard let dc = CreateCompatibleDC(nil) else {
            return nil
        }
        defer { DeleteDC(dc) }

        var bitmapInfo = BITMAPINFO()
        bitmapInfo.bmiHeader.biSize = DWORD(MemoryLayout<BITMAPINFOHEADER>.size)
        bitmapInfo.bmiHeader.biWidth = LONG(pixelWidth)
        bitmapInfo.bmiHeader.biHeight = LONG(-pixelHeight)
        bitmapInfo.bmiHeader.biPlanes = 1
        bitmapInfo.bmiHeader.biBitCount = 32
        bitmapInfo.bmiHeader.biCompression = DWORD(BI_RGB)

        var bits: UnsafeMutableRawPointer?
        guard let bitmap = CreateDIBSection(dc, &bitmapInfo, UINT(DIB_RGB_COLORS), &bits, nil, 0), let bits else {
            return nil
        }
        defer { DeleteObject(HGDIOBJ(bitmap)) }

        let previousBitmap = SelectObject(dc, HGDIOBJ(bitmap))
        defer { _ = SelectObject(dc, previousBitmap) }

        guard let font = createFont(for: style, scaleFactor: scaleFactor) else {
            return nil
        }
        defer { DeleteObject(HGDIOBJ(font)) }

        let previousFont = SelectObject(dc, HGDIOBJ(font))
        defer { _ = SelectObject(dc, previousFont) }

        if resolvesMinimumScaleFactor {
            let effectiveStyle = style.resolvingMinimumScaleFactor(
                for: text,
                maxContentWidth: max(0, size.width - style.insets.leading - style.insets.trailing),
                measureLine: { line in
                    measureSingleLineWidth(line, in: dc, scaleFactor: scaleFactor) ?? 0
                }
            )
            if effectiveStyle != style {
                return rasterize(
                    text,
                    in: size,
                    style: effectiveStyle,
                    scaleFactor: scaleFactor,
                    resolvesMinimumScaleFactor: false
                )
            }
        }

        memset(bits, 0, bufferSize)
        SetBkMode(dc, TRANSPARENT)
        SetTextColor(dc, colorRef(red: 255, green: 255, blue: 255))

        let resolvedLayout = resolveTextLayout(
            for: text,
            style: style,
            maxContentWidth: max(0, size.width - style.insets.leading - style.insets.trailing),
            measureLine: { line in
                measureSingleLineWidth(line, in: dc, scaleFactor: scaleFactor) ?? 0
            }
        )
        let drawFlags = baseDrawTextFlags(
            for: resolvedLayout.text,
            alignment: style.alignment,
            lineBreakMode: resolvedLayout.lines.count > 1 ? .wrap : style.lineBreakMode
        )

        var targetRect = contentRect
        _ = withWideString(resolvedLayout.text) { wideText in
            DrawTextW(dc, wideText, -1, &targetRect, drawFlags)
        }

        let pixelBuffer = bits.assumingMemoryBound(to: UInt8.self)
        let outputData = Data(bytes: pixelBuffer, count: bufferSize)
        var bytes = [UInt8](outputData)
        tint(pixelBytes: &bytes, style: style)

        return BitmapSurface(
            width: pixelWidth,
            height: pixelHeight,
            bytesPerRow: bytesPerRow,
            pixels: Data(bytes),
            format: .bgra8Premultiplied
        )
    }

    /// Converts GDI's white-on-black coverage into tinted, **premultiplied**
    /// BGRA: the colour channels come out scaled by coverage. Surfaces that
    /// have been through this must be tagged `.bgra8Premultiplied` so the
    /// GPU and CPU consumers do not re-multiply them.
    static func tint(pixelBytes: inout [UInt8], style: PixelTextStyle) {
        // Clamp before multiplication and integer conversion: a finite Float
        // can still overflow when multiplied by 255, and Int(NaN) traps.
        // Keep the existing Float RGB arithmetic and truncation so ordinary
        // text keeps exactly the same premultiplied pixel values.
        let red = Int(GPUISceneValue.clamped(style.color.red, lower: 0, upper: 1) * 255)
        let green = Int(GPUISceneValue.clamped(style.color.green, lower: 0, upper: 1) * 255)
        let blue = Int(GPUISceneValue.clamped(style.color.blue, lower: 0, upper: 1) * 255)
        let alphaScale = Double(GPUISceneValue.clamped(style.color.alpha, lower: 0, upper: 1))

        var index = 0
        while index + 3 < pixelBytes.count {
            let sourceBlue = Int(pixelBytes[index])
            let sourceGreen = Int(pixelBytes[index + 1])
            let sourceRed = Int(pixelBytes[index + 2])
            let intensity = max(sourceRed, max(sourceGreen, sourceBlue))

            if intensity == 0 {
                pixelBytes[index] = 0
                pixelBytes[index + 1] = 0
                pixelBytes[index + 2] = 0
                pixelBytes[index + 3] = 0
                index += 4
                continue
            }

            let alpha = Int(Double(intensity) * alphaScale)
            pixelBytes[index] = UInt8((blue * alpha) / 255)
            pixelBytes[index + 1] = UInt8((green * alpha) / 255)
            pixelBytes[index + 2] = UInt8((red * alpha) / 255)
            pixelBytes[index + 3] = UInt8(alpha)
            index += 4
        }
    }

    private static func createFont(for style: PixelTextStyle, scaleFactor: Double) -> HFONT? {
        guard let dimensions = fontDimensions(for: style, scaleFactor: scaleFactor) else {
            return nil
        }
        return withWideString(style.fontFamily) { family in
            CreateFontW(
                -dimensions.height,
                dimensions.width,
                0,
                0,
                Int32(style.weight.gdiWeight),
                DWORD(style.isItalic ? 1 : 0),
                0,
                0,
                DWORD(DEFAULT_CHARSET),
                DWORD(OUT_DEFAULT_PRECIS),
                DWORD(CLIP_DEFAULT_PRECIS),
                DWORD(ANTIALIASED_QUALITY),
                DWORD(DEFAULT_PITCH | FF_DONTCARE),
                family
            )
        }
    }

    /// Invalid font sizes decline the native path instead of reaching a
    /// trapping Int32 conversion (or negating Int32.min for CreateFontW).
    static func fontDimensions(for style: PixelTextStyle, scaleFactor: Double) -> (height: Int32, width: Int32)? {
        let fontSize = style.nativeFontPixelSize
        guard fontSize.isFinite, fontSize > 0, scaleFactor.isFinite, scaleFactor > 0,
            let height = Int32(exactly: (fontSize * scaleFactor).rounded()),
            let width = style.fontWidth.gdiAverageCharacterWidth(fontSize: fontSize, scaleFactor: scaleFactor)
        else {
            return nil
        }
        return (height, width)
    }

    private static func baseDrawTextFlags(
        for text: String,
        alignment: TextHorizontalAlignment,
        lineBreakMode: TextLineBreakMode
    ) -> UINT {
        var flags = UINT(DT_NOPREFIX)

        switch alignment {
        case .leading:
            flags |= UINT(DT_LEFT)
        case .center:
            flags |= UINT(DT_CENTER)
        case .trailing:
            flags |= UINT(DT_RIGHT)
        }

        if lineBreakMode == .wrap || text.contains("\n") {
            flags |= UINT(DT_WORDBREAK)
        } else {
            flags |= UINT(DT_SINGLELINE | DT_VCENTER)
        }

        return flags
    }

    private static func measureSingleLineWidth(_ text: String, in dc: HDC, scaleFactor: Double) -> Double? {
        var measuredSize = SIZE()
        guard let utf16Count = Int32(exactly: text.utf16.count) else {
            return nil
        }
        let result = withWideString(text) { wideText in
            GetTextExtentPoint32W(dc, wideText, utf16Count, &measuredSize)
        }

        guard result else {
            return nil
        }

        return Double(measuredSize.cx) / max(scaleFactor, 1)
    }

    static func drawRectForInsets(_ insets: EdgeInsets, width: Int32, height: Int32, scaleFactor: Double)
        -> RECT?
    {
        let scaledInsets = EdgeInsets(
            top: insets.top * scaleFactor,
            leading: insets.leading * scaleFactor,
            bottom: insets.bottom * scaleFactor,
            trailing: insets.trailing * scaleFactor
        )

        // Subtract in Double before checking the final coordinate as well:
        // a representable negative inset can overflow `width - inset`.
        guard let left = Int32(exactly: scaledInsets.leading.rounded(.down)),
            let top = Int32(exactly: scaledInsets.top.rounded(.down)),
            let right = Int32(exactly: Double(width) - scaledInsets.trailing.rounded(.down)),
            let bottom = Int32(exactly: Double(height) - scaledInsets.bottom.rounded(.down))
        else {
            return nil
        }
        return RECT(left: LONG(left), top: LONG(top), right: LONG(right), bottom: LONG(bottom))
    }

    private static func colorRef(red: UInt8, green: UInt8, blue: UInt8) -> COLORREF {
        COLORREF(UInt32(red) | (UInt32(green) << 8) | (UInt32(blue) << 16))
    }
}
private func contentWidthLimit(for maxWidth: Double?, style: PixelTextStyle) -> Double? {
    guard let maxWidth, maxWidth.isFinite else {
        return nil
    }

    return max(0, maxWidth - style.insets.leading - style.insets.trailing)
}
/// Expands a frame-path text node's draw size to at least the text's measured
/// natural size. A collapsed layout frame (height or width smaller than the
/// text's natural extent) must not shrink the pre-rasterized text bitmap into
/// an unreadable sliver: the scene painter draws text overflowing such frames
/// anchored at the frame origin, so frame-path text rasterizes at the measured
/// size and draws from the same origin to match.
///
/// Per-side insets are capped at `max(frame, content)` on their axis before
/// bounding the expansion: icon labels carry sentinel suppression insets of
/// 1,000,000pt per side (`iconTextSuppressionInsets`), and taking the raw
/// measured size literally would try to rasterize multi-million-pixel bitmaps
/// (E_INVALIDARG at texture upload). A hard ceiling keeps every raster within
/// backend texture limits.
let maximumFramePathRasterExtent = 4096.0

func framePathTextRasterSize(frameSize: Size, measured: Size?, style: PixelTextStyle) -> Size {
    // The frame is app-supplied and routinely non-finite: `.frame(width:
    // .infinity)` resolves to an infinite width, and the raw value used to
    // travel all the way into `UInt32(_:)` and trap. Both axes are sanitized
    // here, once, so no downstream conversion has to re-derive the rule.
    let sanitizedFrame = Size(
        width: frameRasterFloor(frameSize.width),
        height: frameRasterFloor(frameSize.height)
    )
    guard let measured else {
        return sanitizedFrame
    }

    let maxRasterExtent = maximumFramePathRasterExtent
    let measuredWidth = clampedRasterExtent(measured.width)
    let measuredHeight = clampedRasterExtent(measured.height)
    let contentWidth = max(0, measuredWidth - style.insets.leading - style.insets.trailing)
    let contentHeight = max(0, measuredHeight - style.insets.top - style.insets.bottom)
    let horizontalInsetCap = max(sanitizedFrame.width, contentWidth)
    let verticalInsetCap = max(sanitizedFrame.height, contentHeight)
    let horizontalInsets =
        min(style.insets.leading, horizontalInsetCap) + min(style.insets.trailing, horizontalInsetCap)
    let verticalInsets = min(style.insets.top, verticalInsetCap) + min(style.insets.bottom, verticalInsetCap)
    return Size(
        width: max(sanitizedFrame.width, min(measuredWidth, horizontalInsets + contentWidth, maxRasterExtent)),
        height: max(sanitizedFrame.height, min(measuredHeight, verticalInsets + contentHeight, maxRasterExtent))
    )
}

/// NaN and infinity collapse to the raster ceiling, never past it.
private func clampedRasterExtent(_ value: Double) -> Double {
    guard value.isFinite else {
        return maximumFramePathRasterExtent
    }
    return min(max(0, value), maximumFramePathRasterExtent)
}

/// The frame term is a *floor* ("rasterize at least the frame"). An unbounded
/// frame supplies no floor at all, so it contributes zero rather than the
/// ceiling - otherwise `.frame(width: .infinity)` would rasterize a 4096-wide
/// bitmap for a six-character label.
private func frameRasterFloor(_ value: Double) -> Double {
    guard value.isFinite else {
        return 0
    }
    return min(max(0, value), maximumFramePathRasterExtent)
}
private func measureRectWidth(maxWidth: Double?, style: PixelTextStyle, scaleFactor: Double) -> Int32 {
    let contentWidth = contentWidthLimit(for: maxWidth, style: style) ?? 4096
    return roundedUpInt32(contentWidth * max(scaleFactor, 1), minimum: 1, maximum: Int32(maximumRasterPixels)) ?? 4096
}
private func clampedMeasuredWidth(_ contentWidth: Double, style: PixelTextStyle, maxWidth: Double?) -> Double {
    if style.lineBreakMode == .clip, let contentLimit = contentWidthLimit(for: maxWidth, style: style) {
        return min(contentWidth, contentLimit)
    }

    return contentWidth
}
extension PixelTextStyle {
    var nativeFontPixelSize: Double {
        nativeFontSize ?? max(12, scale * 6 + 8)
    }
}
extension TextWeight {
    public var gdiWeight: Int {
        switch self {
        case .regular:
            return 400
        case .medium:
            return 500
        case .semibold:
            return 600
        case .bold:
            return 700
        }
    }
}
extension TextFontWidth {
    fileprivate func gdiAverageCharacterWidth(fontSize: Double, scaleFactor: Double) -> Int32? {
        let multiplier: Double
        switch self {
        case .compressed:
            multiplier = 0.36
        case .condensed:
            multiplier = 0.44
        case .standard:
            return 0
        case .expanded:
            multiplier = 0.66
        }
        return Int32(exactly: max(1, (fontSize * scaleFactor * multiplier).rounded()))
    }
}
private func withWideString<Result>(_ string: String, _ body: (UnsafePointer<WCHAR>) -> Result) -> Result {
    var wide = Array(string.utf16)
    wide.append(0)
    return wide.withUnsafeBufferPointer { body($0.baseAddress!) }
}
/// Probes installed fonts for glyph coverage so symbol icons can pick a font
/// family that actually contains their private-use codepoints (Segoe Fluent
/// Icons on Windows 11, Segoe MDL2 Assets on Windows 10) instead of painting
/// `.notdef` boxes.
///
/// The probe rasterizes through the same DirectWrite path the icon painter
/// uses and compares against a guaranteed-missing codepoint's `.notdef`
/// output; family-level APIs are unusable for this because
/// `IDWriteFactory.CreateTextFormat` succeeds even for families that are not
/// installed (substitution happens later, at layout time).
@MainActor
enum NativeFontAvailability {
    struct TestingOverrides {
        /// Answers `hasGlyph` *before* the cache, so a test can force a
        /// verdict regardless of what earlier probes recorded.
        var hasGlyph: ((Character, String) -> Bool)?
        /// Replaces only the DirectWrite probe, *after* the cache. A probe is
        /// two rasterizations, so this is how a test can fill the cache
        /// hundreds of entries deep to check its bound.
        var probe: ((Character, String) -> Bool)?
    }

    static var testingOverrides = TestingOverrides()

    static func resetTestingOverrides() {
        testingOverrides = TestingOverrides()
    }

    static func resetProbeCacheForTesting() {
        cache.removeAll()
        accessClock = 0
    }

    static var probeCacheCountForTesting: Int {
        cache.count
    }

    static var probeCacheLimitForTesting: Int {
        maxCacheEntries
    }

    /// Returns the first family in `preferred` that is installed and contains
    /// a glyph for `character`, preserving caller order (the fallback chain).
    static func resolvedFontFamily(
        for character: Character, preferred: [String], observation: NativeBitmapFontObservation? = nil
    ) -> String? {
        var seen = Set<String>()
        for family in preferred where !family.isEmpty {
            guard seen.insert(family.lowercased()).inserted else {
                continue
            }
            if hasGlyph(character, fontFamily: family, observation: observation) {
                return family
            }
        }
        return nil
    }

    /// Returns whether `fontFamily` is installed and maps `character` to a
    /// real glyph (not `.notdef`).
    static func hasGlyph(
        _ character: Character, fontFamily: String, observation: NativeBitmapFontObservation? = nil
    ) -> Bool {
        let candidateObservation = observation?.withPurpose(.candidateProbe)
        if let override = testingOverrides.hasGlyph {
            let result = override(character, fontFamily)
            candidateObservation?.recordTestingOverrideResult(bitmap: nil)
            return result
        }
        guard !fontFamily.isEmpty else {
            return false
        }
        let cacheKey = "\(fontFamily.lowercased())|\(String(character).utf16.map { String($0) }.joined(separator: ","))"
        if let index = cache.index(forKey: cacheKey) {
            cache.values[index].lastAccessed = nextAccessStamp()
            candidateObservation?.noteProbeCacheHit()
            return cache.values[index].hasGlyph
        }
        let result: Bool
        if let override = testingOverrides.probe {
            result = override(character, fontFamily)
            candidateObservation?.recordTestingOverrideResult(bitmap: nil)
        } else {
            result = probeHasGlyph(character, fontFamily: fontFamily, observation: observation)
        }
        if cache.count >= maxCacheEntries,
            let oldest = cache.min(by: { $0.value.lastAccessed < $1.value.lastAccessed })
        {
            cache.removeValue(forKey: oldest.key)
        }
        cache[cacheKey] = ProbeResult(hasGlyph: result, lastAccessed: nextAccessStamp())
        return result
    }

    private struct ProbeResult {
        var hasGlyph: Bool
        var lastAccessed: UInt64
    }

    /// A probe costs two DirectWrite rasterizations, so this cache earns its
    /// keep — but the key is `(family, character)` over an *app-supplied*
    /// alphabet, so it is unbounded by construction: text rendered through
    /// `SymbolIcon` fallbacks across a large character set grows it forever.
    /// 512 entries covers every icon set the fallback chain has, and the LRU
    /// eviction below keeps the hot ones.
    private static let maxCacheEntries = 512
    private static var cache: [String: ProbeResult] = [:]
    private static var accessClock: UInt64 = 0

    private static func nextAccessStamp() -> UInt64 {
        accessClock &+= 1
        return accessClock
    }

    /// A private-use codepoint from plane 16 that no shipping font contains;
    /// its rasterization is the `.notdef` reference for glyph-presence checks.
    private static let missingGlyphSentinel = "\u{10FFFD}"

    /// Renders `character` with the candidate family through the same
    /// DirectWrite path icons use, and compares it against the `.notdef`
    /// reference: identical output means the glyph is genuinely missing.
    private static func probeHasGlyph(
        _ character: Character, fontFamily: String, observation: NativeBitmapFontObservation? = nil
    ) -> Bool {
        let style = PixelTextStyle(color: .white, scale: 2, fontFamily: fontFamily)
        guard
            let glyphBitmap = DirectWriteTextRenderer.rasterize(
                String(character), style: style, scaleFactor: 1,
                observation: observation?.withPurpose(.candidateProbe)),
            glyphBitmap.pixels.contains(where: { $0 != 0 })
        else {
            return false
        }

        guard
            let notdefBitmap = DirectWriteTextRenderer.rasterize(
                missingGlyphSentinel, style: style, scaleFactor: 1,
                observation: observation?.withPurpose(.sentinelProbe))
        else {
            // No reference to compare against; a non-empty glyph bitmap is
            // the best available evidence of coverage.
            return true
        }

        return glyphBitmap.width != notdefBitmap.width
            || glyphBitmap.height != notdefBitmap.height
            || glyphBitmap.pixels != notdefBitmap.pixels
    }
}
