import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import WinSDK

@MainActor
enum DirectWriteTextRenderer {
    static func layout(_ text: String, style: PixelTextStyle, scaleFactor: Double, maxWidth: Double? = nil)
        -> NativeTextLayoutResult?
    {
        guard let system = DirectWriteSystem.shared else {
            return nil
        }

        return system.layout(text, style: style, scaleFactor: scaleFactor, maxWidth: maxWidth)
    }

    static func measure(_ text: String, style: PixelTextStyle, scaleFactor: Double, maxWidth: Double? = nil) -> Size? {
        layout(text, style: style, scaleFactor: scaleFactor, maxWidth: maxWidth)?.measuredSize
    }

    /// Test seam: the per-line width wrapping decisions are taken from,
    /// which must agree with the line width `layout` reports.
    static func measuredLineWidthForTesting(_ text: String, style: PixelTextStyle) -> Double? {
        DirectWriteSystem.shared?.measuredLineWidthForTesting(text, style: style)
    }

    /// Whether `family` names a font family that is actually installed.
    ///
    /// The only correct answer to that question, because
    /// `IDWriteFactory.CreateTextFormat` returns `S_OK` for families that are
    /// not installed and substitutes silently at layout time — so a stack that
    /// asks for "Segoe UI Variable Text" on Windows 10 gets a format, a
    /// layout, and glyphs, all of them from some other face. `nil` means
    /// DirectWrite itself is unavailable and the caller has no evidence
    /// either way.
    static func isFontFamilyInstalled(_ family: String) -> Bool? {
        DirectWriteSystem.shared?.isFontFamilyInstalled(family)
    }

    /// Test seam: DirectWrite shaping probes run for tracking coherence since
    /// the last `resetShapedGlyphCountCacheForTesting()`. Every probe is a full
    /// text layout plus a glyph-run capture on the main actor.
    static var shapedGlyphCountProbesForTesting: Int {
        DirectWriteSystem.shared?.shapedGlyphCountProbes ?? 0
    }

    static func resetShapedGlyphCountCacheForTesting() {
        DirectWriteSystem.shared?.resetShapedGlyphCountCacheForTesting()
    }

    static func appendCommands(
        for text: String,
        in rect: Rect,
        style: PixelTextStyle,
        scaleFactor: Double,
        clipRect: Rect?,
        into commands: inout [RenderCommand]
    ) -> Bool {
        guard let system = DirectWriteSystem.shared else {
            return false
        }

        // A collapsed layout frame (height or width smaller than the text's
        // natural extent) must not shrink the pre-rasterized bitmap: the
        // scene painter draws text overflowing such frames from the frame
        // origin, so the frame path rasterizes at least the measured size to
        // keep the text readable.
        let measured = system.measure(
            text,
            style: style,
            scaleFactor: scaleFactor,
            maxWidth: rect.size.width.isFinite ? rect.size.width : nil
        )
        let rasterSize = framePathTextRasterSize(frameSize: rect.size, measured: measured, style: style)
        guard
            let bitmap = FramePathTextRaster.bitmap(
                for: text, size: rasterSize, style: style, scaleFactor: scaleFactor,
                rasterize: { system.rasterize(text, in: rasterSize, style: style, scaleFactor: scaleFactor) })
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
        guard let system = DirectWriteSystem.shared,
            let size = system.measure(text, style: style, scaleFactor: scaleFactor, maxWidth: nil)
        else {
            return nil
        }

        return system.rasterize(text, in: size, style: style, scaleFactor: scaleFactor)
    }

    static func rasterizeGlyph(_ character: Character, style: PixelTextStyle, scaleFactor: Double) -> NativeGlyphBitmap?
    {
        guard let system = DirectWriteSystem.shared else {
            return nil
        }

        return system.rasterizeGlyph(character, style: style, scaleFactor: scaleFactor)
    }

    static func rasterizeGlyph(_ glyph: NativeTextGlyphLayout, style: PixelTextStyle, scaleFactor: Double)
        -> NativeGlyphBitmap?
    {
        guard let system = DirectWriteSystem.shared else {
            return nil
        }

        return system.rasterizeGlyph(glyph, style: style, scaleFactor: scaleFactor)
    }
}
/// Hard ceiling on any single DirectWrite/GDI raster surface, in device
/// pixels per axis. `framePathTextRasterSize` clamps to the same value in
/// logical points before scaling; this is the last line of defence for the
/// scaled result.
let maximumRasterPixels: UInt32 = 8192

private struct DirectWriteParagraphLineMetrics {
    var height: Double
    var baseline: Double
}

struct CapturedGlyphRasterMetrics: Equatable, Sendable {
    var renderScale: Double
    var fontSize: Double
    var baselineYOffset: Double
    var paddingPixels: Int32
    var targetWidth: Int32
    var targetHeight: Int32
    var advance: Double
}
func makeCapturedGlyphRasterMetrics(for glyph: NativeTextGlyphLayout, scaleFactor: Double)
    -> CapturedGlyphRasterMetrics?
{
    guard scaleFactor.isFinite, scaleFactor > 0 else {
        return nil
    }

    // The painter divides this raster's pixel metrics by the requested atlas
    // rung before applying the view transform. Clamping a shrinking run to 1x
    // leaves its ink full-size while its advances shrink, overlapping letters.
    let renderScale = scaleFactor
    guard glyph.fontSize.isFinite, glyph.origin.y.isFinite, glyph.advance.isFinite else {
        return nil
    }

    let fontSize = max(glyph.fontSize, 1)
    let baselineYOffset = fontSize * 0.8
    let paddingValue = (fontSize * renderScale * 0.75).rounded(.up)
    guard let paddingPixels = roundedUpInt32(paddingValue, minimum: 2) else {
        return nil
    }

    let advance = max(glyph.advance, fontSize * 0.5)
    let logicalWidth = max(advance * 2.0, fontSize * 2.5)
    let logicalHeight = max((baselineYOffset + fontSize) * 1.5, fontSize * 2.5)

    guard let contentWidth = roundedUpInt32(logicalWidth * renderScale, minimum: 8),
        let contentHeight = roundedUpInt32(logicalHeight * renderScale, minimum: 8)
    else {
        return nil
    }

    let paddedWidth = Int64(contentWidth) + Int64(paddingPixels) * 2
    let paddedHeight = Int64(contentHeight) + Int64(paddingPixels) * 2
    guard paddedWidth <= Int64(Int32.max), paddedHeight <= Int64(Int32.max) else {
        return nil
    }

    return CapturedGlyphRasterMetrics(
        renderScale: renderScale,
        fontSize: fontSize,
        baselineYOffset: baselineYOffset,
        paddingPixels: paddingPixels,
        targetWidth: Int32(paddedWidth),
        targetHeight: Int32(paddedHeight),
        advance: advance
    )
}
func isUsableCapturedGlyphBitmap(_ bitmap: NativeGlyphBitmap, fontSize: Double, scaleFactor: Double) -> Bool {
    guard fontSize.isFinite, scaleFactor.isFinite, scaleFactor > 0, bitmap.width > 0, bitmap.height > 0 else {
        return false
    }

    let maxExtent = max(fontSize * scaleFactor * 4.0, 32.0)
    return Double(bitmap.width) <= maxExtent && Double(bitmap.height) <= maxExtent
}
/// The one `Double -> Int32` conversion in the text layer.
///
/// Every raw `Int32(x.rounded(.up))` in this stack was a trap waiting for
/// `Text(...).frame(width: .infinity)`: Swift's fixed-width initializers fault
/// on non-finite and out-of-range input. Callers that cannot proceed without a
/// size get `nil` and degrade; nobody converts by hand.
func roundedUpInt32(_ value: Double, minimum: Int32, maximum: Int32 = Int32.max) -> Int32? {
    guard value.isFinite else {
        return nil
    }

    let rounded = value.rounded(.up)
    guard rounded <= Double(Int32.max), rounded >= Double(Int32.min) else {
        return nil
    }

    return min(maximum, max(minimum, Int32(rounded)))
}

/// `roundedUpInt32` for the DirectWrite APIs that take unsigned pixel extents.
func roundedUpUInt32(_ value: Double, minimum: UInt32, maximum: UInt32 = UInt32(Int32.max)) -> UInt32? {
    guard value.isFinite else {
        return nil
    }

    let rounded = value.rounded(.up)
    guard rounded >= 0, rounded <= Double(UInt32(Int32.max)) else {
        return nil
    }

    return min(maximum, max(minimum, UInt32(rounded)))
}
/// Everything about a candidate line that changes how many glyphs it shapes
/// into. Alignment, colour and decorations are deliberately absent: they change
/// where the run is drawn, never how many glyphs it has.
private struct ShapedGlyphCountKey: Hashable {
    var line: String
    var fontFamily: String
    var fontPixelSize: Double
    var weight: TextWeight
    var fontWidth: TextFontWidth
    var isItalic: Bool
    var enableKerning: Bool
    var monospacedDigits: Bool
    var lowercaseSmallCaps: Bool
    var uppercaseSmallCaps: Bool

    /// `nil` for spanned text, which has no single font to key on.
    init?(line: String, style: PixelTextStyle) {
        guard style.spans?.isEmpty ?? true else {
            return nil
        }

        self.line = line
        self.fontFamily = style.fontFamily
        self.fontPixelSize = style.nativeFontPixelSize
        self.weight = style.weight
        self.fontWidth = style.fontWidth
        self.isItalic = style.isItalic
        self.enableKerning = style.enableKerning
        self.monospacedDigits = style.monospacedDigits
        self.lowercaseSmallCaps = style.lowercaseSmallCaps
        self.uppercaseSmallCaps = style.uppercaseSmallCaps
    }
}
/// A memoised shaped glyph count, including the "shaping declined" answer —
/// which costs exactly as much to compute as a successful one.
private struct ShapedGlyphCount {
    var count: Int?
}
@MainActor
private final class DirectWriteSystem {
    static let shared: DirectWriteSystem? = try? DirectWriteSystem()

    /// Enough to hold every wrap probe of a few long tracked paragraphs; small
    /// enough that the memo can never become the thing that grows.
    static let maximumShapedGlyphCountEntries = 512

    private let loader: Win32TextLibraryLoader
    private let module: HMODULE
    private let factory: UnsafeMutablePointer<IDWriteFactory>
    private let gdiInterop: UnsafeMutablePointer<IDWriteGdiInterop>
    private let renderingParams: UnsafeMutablePointer<IDWriteRenderingParams>

    /// Bounded memo for ``shapedGlyphCount``, deliberately *not* scoped to one
    /// `makeLineMeasurer` closure.
    ///
    /// The wrap search probes a new prefix per gallop step, and a tracked
    /// paragraph pays a full DirectWrite layout plus a glyph-run capture for
    /// every one of them, on the main actor. Scoped to a single layout call
    /// that cost is paid again by the very next `measure`, `rasterize` and
    /// per-frame `layout` of the same unchanged paragraph. Living on the
    /// process-wide system, the second and every later pass over the same text
    /// shapes nothing at all. Eviction is oldest-first, which is what bounds
    /// it; a hit does not reorder, because a memo that never grows does not
    /// need to be clever about what it drops.
    fileprivate var shapedGlyphCounts: [ShapedGlyphCountKey: ShapedGlyphCount] = [:]
    fileprivate var shapedGlyphCountOrder: [ShapedGlyphCountKey] = []

    /// Test seam: shaping probes actually run, so a test can pin that a wrapped
    /// tracked paragraph does not re-shape what it has already shaped.
    fileprivate var shapedGlyphCountProbes = 0

    fileprivate func resetShapedGlyphCountCacheForTesting() {
        shapedGlyphCounts.removeAll()
        shapedGlyphCountOrder.removeAll()
        shapedGlyphCountProbes = 0
    }

    init() throws {
        let loader = Win32TextLibraryLoader()

        guard let module = loader.loadLibrary(named: "dwrite.dll") else {
            throw DirectWriteError.initializationFailed("LoadLibraryW(dwrite.dll)")
        }

        self.loader = loader
        self.module = module

        var iid = iidIDWriteFactory
        guard let factoryResult = withUnsafePointer(to: &iid, { loader.createDWriteFactory(from: module, iid: $0) }),
            isSuccess(factoryResult.0),
            let factoryRaw = factoryResult.1
        else {
            loader.unloadLibrary(module)
            throw DirectWriteError.initializationFailed("DWriteCreateFactory")
        }

        self.factory = factoryRaw.assumingMemoryBound(to: IDWriteFactory.self)

        var gdiInteropRaw: UnsafeMutableRawPointer?
        let gdiInteropHR = factory.pointee.lpVtbl!.pointee.GetGdiInterop(
            UnsafeMutableRawPointer(factory), &gdiInteropRaw)
        guard isSuccess(gdiInteropHR), let gdiInteropRaw else {
            var releasableFactory: UnsafeMutablePointer<IDWriteFactory>? = factory
            releaseDirectWriteCOM(&releasableFactory)
            loader.unloadLibrary(module)
            throw DirectWriteError.initializationFailed("IDWriteFactory.GetGdiInterop")
        }

        self.gdiInterop = gdiInteropRaw.assumingMemoryBound(to: IDWriteGdiInterop.self)

        self.renderingParams = try DirectWriteSystem.makeRenderingParams(factory: factory)
    }

    func measure(_ text: String, style: PixelTextStyle, scaleFactor: Double, maxWidth: Double? = nil) -> Size? {
        layout(text, style: style, scaleFactor: scaleFactor, maxWidth: maxWidth)?.measuredSize
    }

    /// `IDWriteFontCollection.FindFamilyName` against the system collection.
    ///
    /// The collection is fetched per call with `checkForUpdates: false`: this
    /// runs a handful of times per process (once per candidate face, memoized
    /// above), so caching the collection would only pin a COM object for the
    /// life of the process to save nothing.
    func isFontFamilyInstalled(_ family: String) -> Bool {
        guard !family.isEmpty else {
            return false
        }
        var collectionRaw: UnsafeMutableRawPointer?
        let hr = factory.pointee.lpVtbl!.pointee.GetSystemFontCollection(
            UnsafeMutableRawPointer(factory), &collectionRaw, WindowsBool(false))
        guard isSuccess(hr), let collectionRaw else {
            return false
        }
        var collection: UnsafeMutablePointer<IDWriteFontCollection>? = collectionRaw.assumingMemoryBound(
            to: IDWriteFontCollection.self)
        defer { releaseDirectWriteCOM(&collection) }

        var index: UINT32 = 0
        var exists = WindowsBool(false)
        let findHR = withWideString(family) { name in
            collection!.pointee.lpVtbl!.pointee.FindFamilyName(
                UnsafeMutableRawPointer(collection!), name, &index, &exists)
        }
        return isSuccess(findHR) && exists.boolValue
    }

    func layout(
        _ text: String,
        style: PixelTextStyle,
        scaleFactor: Double,
        maxWidth: Double? = nil,
        resolvesMinimumScaleFactor: Bool = true
    ) -> NativeTextLayoutResult? {
        // Uniform DirectWrite line metrics already include positive leading.
        // The painter adds this field between line boxes, so repeating that
        // leading here would double every paragraph's baseline spacing.
        var interLineSpacing = style.lineSpacing >= 0 ? 0 : style.lineSpacing
        guard !text.isEmpty else {
            let emptySize = snapLogicalTextSize(
                Size(
                    width: style.insets.leading + style.insets.trailing, height: style.insets.top + style.insets.bottom),
                scaleFactor: scaleFactor
            )
            return NativeTextLayoutResult(
                lines: [], lineSpacing: interLineSpacing, contentSize: .zero, measuredSize: emptySize)
        }

        guard let measurementFormat = createTextFormat(style: style, wrapping: dwriteWordWrappingNoWrap) else {
            return nil
        }
        defer {
            var releasableFormat: UnsafeMutablePointer<IDWriteTextFormat>? = measurementFormat
            releaseDirectWriteCOM(&releasableFormat)
        }

        let maxContentWidth = contentWidthLimit(for: maxWidth, style: style)
        let source = textFragment(for: text, style: style)
        let measureFragment = makeLineMeasurer(style: style, sourceText: text, format: measurementFormat)
        if resolvesMinimumScaleFactor {
            let effectiveStyle = style.scaledForMinimumScaleFactor(
                minimumTextScaleFactor(
                    for: source, style: style, maxContentWidth: maxContentWidth, measureFragment: measureFragment)
            )
            if effectiveStyle != style {
                return layout(
                    text,
                    style: effectiveStyle,
                    scaleFactor: scaleFactor,
                    maxWidth: maxWidth,
                    resolvesMinimumScaleFactor: false
                )
            }
        }

        let resolvedLayout = resolveTextLayout(
            for: source,
            style: style,
            maxContentWidth: maxContentWidth,
            measureFragment: measureFragment
        )
        let paragraphMetrics = expandedSpanLineMetrics(for: text, style: style)
        if paragraphMetrics != nil {
            interLineSpacing = 0
        }

        var lines: [NativeTextLineLayout] = []
        lines.reserveCapacity(resolvedLayout.fragments.count)
        var contentWidth = 0.0
        var contentHeight = 0.0

        for (index, fragment) in resolvedLayout.fragments.enumerated() {
            let lineStyle = fragment.rebasedStyle(style, sourceText: text)
            guard let lineLayout = layoutLine(fragment.text, style: lineStyle, paragraphMetrics: paragraphMetrics)
            else {
                return nil
            }
            lines.append(lineLayout)
            contentWidth = max(contentWidth, lineLayout.width)
            contentHeight += lineLayout.height
            if index < resolvedLayout.fragments.count - 1 {
                contentHeight += interLineSpacing
            }
        }

        if let reservedLineCount = reservedTextLineCount(for: style) {
            let reservedLineHeight = lines.first?.height ?? max(style.nativeFontPixelSize, 1)
            let reservedContentHeight =
                Double(reservedLineCount) * reservedLineHeight + Double(max(reservedLineCount - 1, 0))
                * interLineSpacing
            contentHeight = max(contentHeight, reservedContentHeight)
        }

        let measuredWidth = clampedMeasuredWidth(contentWidth, style: style, maxWidth: maxWidth)
        let measuredSize = snapLogicalTextSize(
            Size(
                width: measuredWidth + style.insets.leading + style.insets.trailing,
                height: contentHeight + style.insets.top + style.insets.bottom
            ),
            scaleFactor: scaleFactor
        )

        return NativeTextLayoutResult(
            lines: lines,
            lineSpacing: interLineSpacing,
            contentSize: Size(width: contentWidth, height: contentHeight),
            measuredSize: measuredSize
        )
    }

    func rasterizeGlyph(_ character: Character, style: PixelTextStyle, scaleFactor: Double) -> NativeGlyphBitmap? {
        let glyphStyle = atlasRasterizationStyle(from: style)

        guard let format = createTextFormat(style: glyphStyle, wrapping: dwriteWordWrappingNoWrap) else {
            return nil
        }
        defer {
            var releasableFormat: UnsafeMutablePointer<IDWriteTextFormat>? = format
            releaseDirectWriteCOM(&releasableFormat)
        }

        let text = String(character)
        guard
            let layout = createTextLayout(
                text: text, format: format, size: Size(width: 4096, height: 4096), style: glyphStyle),
            let bounds = textBounds(for: layout)
        else {
            return nil
        }
        defer {
            var releasableLayout: UnsafeMutablePointer<IDWriteTextLayout>? = layout
            releaseDirectWriteCOM(&releasableLayout)
        }

        let logicalSize = snapLogicalTextSize(
            Size(width: max(bounds.width, 1), height: max(bounds.height, 1)),
            scaleFactor: scaleFactor
        )
        guard
            let pixelWidth = roundedUpUInt32(
                logicalSize.width * scaleFactor, minimum: 1, maximum: maximumRasterPixels),
            let pixelHeight = roundedUpUInt32(
                logicalSize.height * scaleFactor, minimum: 1, maximum: maximumRasterPixels)
        else {
            return nil
        }

        var bitmapTargetRaw: UnsafeMutableRawPointer?
        let bitmapTargetHR = gdiInterop.pointee.lpVtbl!.pointee.CreateBitmapRenderTarget(
            UnsafeMutableRawPointer(gdiInterop),
            nil,
            pixelWidth,
            pixelHeight,
            &bitmapTargetRaw
        )
        guard isSuccess(bitmapTargetHR), let bitmapTargetRaw else {
            return nil
        }

        let bitmapTarget = bitmapTargetRaw.assumingMemoryBound(to: IDWriteBitmapRenderTarget.self)
        defer {
            var releasableBitmapTarget: UnsafeMutablePointer<IDWriteBitmapRenderTarget>? = bitmapTarget
            releaseDirectWriteCOM(&releasableBitmapTarget)
        }

        _ = bitmapTarget.pointee.lpVtbl!.pointee.SetPixelsPerDip(
            UnsafeMutableRawPointer(bitmapTarget), FLOAT(scaleFactor))
        guard clearBitmapTarget(bitmapTarget) else {
            return nil
        }

        var drawingContext = DirectWriteDrawingContext(
            bitmapRenderTarget: bitmapTarget,
            renderingParams: renderingParams,
            pixelsPerDip: FLOAT(scaleFactor),
            textColor: COLORREF(0x00FF_FFFF)
        )

        guard let renderer = createTextRenderer() else {
            return nil
        }
        defer {
            var releasableRenderer: UnsafeMutablePointer<IDWriteTextRenderer>? = renderer
            releaseDirectWriteCOM(&releasableRenderer)
        }

        let drawHR = withUnsafeMutablePointer(to: &drawingContext) { contextPointer in
            layout.pointee.lpVtbl!.pointee.Draw(
                UnsafeMutableRawPointer(layout),
                UnsafeMutableRawPointer(contextPointer),
                UnsafeMutableRawPointer(renderer),
                FLOAT(bounds.overhangLeft),
                FLOAT(bounds.overhangTop)
            )
        }
        guard isSuccess(drawHR),
            let surface = extractBitmapSurface(from: bitmapTarget),
            var cropped = cropGlyphSurface(surface, paddingPixels: 0)
        else {
            return nil
        }

        var pixels = [UInt8](cropped.surface.pixels)
        GDIRasterTextRenderer.tint(pixelBytes: &pixels, style: glyphStyle)
        cropped.surface.pixels = Data(pixels)
        // `tint` scales the colour channels by coverage.
        cropped.surface.format = .bgra8Premultiplied

        let advance = measureSingleLine(text, format: format, style: glyphStyle) ?? bounds.width
        return NativeGlyphBitmap(
            surface: cropped.surface,
            bearingX: Float(-(bounds.overhangLeft * scaleFactor)) + cropped.bearingX,
            bearingY: Float(-(bounds.overhangTop * scaleFactor)) + cropped.bearingY,
            advance: Float(advance * scaleFactor),
            // A one-character layout drawn at its own box origin: ink is
            // measured down from the layout-box top, not from a baseline.
            verticalFrame: .layoutBoxTop
        )
    }

    func rasterizeGlyph(_ glyph: NativeTextGlyphLayout, style: PixelTextStyle, scaleFactor: Double)
        -> NativeGlyphBitmap?
    {
        var normalizedGlyph = glyph
        normalizedGlyph.fontSize = glyph.fontSize.isFinite ? max(glyph.fontSize, 1) : max(style.nativeFontPixelSize, 1)
        if let bitmap = rasterizeCapturedGlyph(normalizedGlyph, scaleFactor: scaleFactor),
            isUsableCapturedGlyphBitmap(bitmap, fontSize: normalizedGlyph.fontSize, scaleFactor: scaleFactor)
        {
            return bitmap
        }

        var glyphStyle = style
        glyphStyle.fontFamily = normalizedGlyph.fontFamily
        glyphStyle.weight = normalizedGlyph.weight
        glyphStyle.nativeFontSize = normalizedGlyph.fontSize
        return rasterizeGlyph(normalizedGlyph.character, style: glyphStyle, scaleFactor: scaleFactor)
    }

    func rasterize(
        _ text: String,
        in size: Size,
        style: PixelTextStyle,
        scaleFactor: Double,
        resolvesMinimumScaleFactor: Bool = true
    ) -> BitmapSurface? {
        let contentSize = Size(
            width: max(1, size.width - style.insets.leading - style.insets.trailing),
            height: max(1, size.height - style.insets.top - style.insets.bottom)
        )

        guard let measurementFormat = createTextFormat(style: style, wrapping: dwriteWordWrappingNoWrap) else {
            return nil
        }
        defer {
            var releasableFormat: UnsafeMutablePointer<IDWriteTextFormat>? = measurementFormat
            releaseDirectWriteCOM(&releasableFormat)
        }

        let source = textFragment(for: text, style: style)
        let measureFragment = makeLineMeasurer(style: style, sourceText: text, format: measurementFormat)
        if resolvesMinimumScaleFactor {
            let effectiveStyle = style.scaledForMinimumScaleFactor(
                minimumTextScaleFactor(
                    for: source, style: style, maxContentWidth: max(0, contentSize.width),
                    measureFragment: measureFragment)
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

        let resolvedLayout = resolveTextLayout(
            for: source,
            style: style,
            maxContentWidth: max(0, contentSize.width),
            measureFragment: measureFragment
        )
        if style.nativeLetterSpacing ?? 0 != 0 {
            // The bitmap raster draws through `IDWriteTextLayout`, which has no
            // character-spacing knob in this interop (that lives on
            // `IDWriteTextLayout1`). Wrapping above honours the tracking; the
            // drawn glyph positions do not. Say so rather than pretending.
            TextRenderDiagnosticsCounters.letterSpacingDroppedRasterizations += 1
        }

        // textOrigin owns vertical alignment within the raster. Asking
        // DirectWrite to align the paragraph as well applies the same offset
        // twice and pushes bottom-aligned text beyond the bitmap.
        var rasterStyle = style
        rasterStyle.verticalAlignment = .top
        let paragraphMetrics = expandedSpanLineMetrics(for: text, style: style)
        guard
            let format = createTextFormat(
                style: rasterStyle, wrapping: wrappingMode(for: resolvedLayout, style: style),
                paragraphMetrics: paragraphMetrics)
        else {
            return nil
        }
        defer {
            var releasableFormat: UnsafeMutablePointer<IDWriteTextFormat>? = format
            releaseDirectWriteCOM(&releasableFormat)
        }

        let resolvedFragment = resolvedLayout.fragment
        let resolvedStyle = resolvedFragment.rebasedStyle(style, sourceText: text)
        guard
            let layout = createTextLayout(
                text: resolvedFragment.text, format: format, size: contentSize, style: resolvedStyle)
        else {
            return nil
        }
        defer {
            var releasableLayout: UnsafeMutablePointer<IDWriteTextLayout>? = layout
            releaseDirectWriteCOM(&releasableLayout)
        }

        guard let pixelWidth = roundedUpUInt32(size.width * scaleFactor, minimum: 1, maximum: maximumRasterPixels),
            let pixelHeight = roundedUpUInt32(size.height * scaleFactor, minimum: 1, maximum: maximumRasterPixels)
        else {
            return nil
        }

        var bitmapTargetRaw: UnsafeMutableRawPointer?
        let bitmapTargetHR = gdiInterop.pointee.lpVtbl!.pointee.CreateBitmapRenderTarget(
            UnsafeMutableRawPointer(gdiInterop),
            nil,
            pixelWidth,
            pixelHeight,
            &bitmapTargetRaw
        )
        guard isSuccess(bitmapTargetHR), let bitmapTargetRaw else {
            return nil
        }

        let bitmapTarget = bitmapTargetRaw.assumingMemoryBound(to: IDWriteBitmapRenderTarget.self)
        defer {
            var releasableBitmapTarget: UnsafeMutablePointer<IDWriteBitmapRenderTarget>? = bitmapTarget
            releaseDirectWriteCOM(&releasableBitmapTarget)
        }

        _ = bitmapTarget.pointee.lpVtbl!.pointee.SetPixelsPerDip(
            UnsafeMutableRawPointer(bitmapTarget), FLOAT(scaleFactor))

        guard clearBitmapTarget(bitmapTarget) else {
            return nil
        }

        let bounds =
            textBounds(for: layout)
            ?? TextBounds(width: contentSize.width, height: contentSize.height, overhangLeft: 0, overhangTop: 0)
        let origin = textOrigin(size: size, style: style, bounds: bounds, paragraphMetrics: paragraphMetrics)

        var drawingContext = DirectWriteDrawingContext(
            bitmapRenderTarget: bitmapTarget,
            renderingParams: renderingParams,
            pixelsPerDip: FLOAT(scaleFactor),
            textColor: COLORREF(0x00FF_FFFF)
        )

        guard let renderer = createTextRenderer() else {
            return nil
        }
        defer {
            var releasableRenderer: UnsafeMutablePointer<IDWriteTextRenderer>? = renderer
            releaseDirectWriteCOM(&releasableRenderer)
        }

        let drawHR = withUnsafeMutablePointer(to: &drawingContext) { contextPointer in
            layout.pointee.lpVtbl!.pointee.Draw(
                UnsafeMutableRawPointer(layout),
                UnsafeMutableRawPointer(contextPointer),
                UnsafeMutableRawPointer(renderer),
                FLOAT(origin.x),
                FLOAT(origin.y)
            )
        }
        guard isSuccess(drawHR) else {
            return nil
        }

        guard var surface = extractBitmapSurface(from: bitmapTarget) else {
            return nil
        }

        var pixels = [UInt8](surface.pixels)
        GDIRasterTextRenderer.tint(pixelBytes: &pixels, style: style)
        surface.pixels = Data(pixels)
        // `tint` scales the colour channels by coverage.
        surface.format = .bgra8Premultiplied
        return surface
    }

    private func layoutLine(
        _ text: String, style: PixelTextStyle, paragraphMetrics: DirectWriteParagraphLineMetrics? = nil
    ) -> NativeTextLineLayout? {
        var lineStyle = style
        lineStyle.verticalAlignment = .top
        // Force leading alignment so glyph origins come back relative to the
        // line's natural starting x. The caller (ScenePainter) handles the
        // actual horizontal alignment of the line within the visible rect via
        // its own startX computation. Without this override, DirectWrite
        // centers (or right-aligns) glyphs inside our 4096px layout box,
        // producing wildly off-screen origin.x values that fail the painter's
        // preflight visibility check and fall back to PixelText.
        lineStyle.alignment = .leading

        guard !text.isEmpty else {
            let lineHeight =
                paragraphMetrics?.height ?? max(lineStyle.nativeFontPixelSize + max(lineStyle.lineSpacing, 0), 1)
            let ascent = paragraphMetrics?.baseline ?? lineStyle.nativeFontPixelSize * 0.8
            return NativeTextLineLayout(
                text: text,
                width: 0,
                height: lineHeight,
                ascent: ascent,
                descent: max(0, lineHeight - ascent),
                glyphs: []
            )
        }

        guard
            let format = createTextFormat(
                style: lineStyle, wrapping: dwriteWordWrappingNoWrap, paragraphMetrics: paragraphMetrics),
            let layout = createTextLayout(
                text: text, format: format, size: Size(width: 4096, height: 4096), style: lineStyle),
            let bounds = textBounds(for: layout)
        else {
            return nil
        }
        defer {
            var releasableLayout: UnsafeMutablePointer<IDWriteTextLayout>? = layout
            releaseDirectWriteCOM(&releasableLayout)
            var releasableFormat: UnsafeMutablePointer<IDWriteTextFormat>? = format
            releaseDirectWriteCOM(&releasableFormat)
        }

        // Shaping first. `captureGlyphLayouts` receives real `DWRITE_GLYPH_RUN`s
        // - glyph IDs, shaped advances, per-glyph offsets and a cluster map -
        // so ligatures are single glyphs and complex scripts get their
        // contextual forms. The per-character `HitTestTextPosition` walk below
        // it re-lays every character out in isolation at shaped positions; it
        // is the fallback, not the default. `isGlyphShapingEnabled` is the
        // escape hatch if a font ever shapes into something we cannot raster.
        var resolvedGlyphs: [NativeTextGlyphLayout] = []
        if NativeTextRenderer.isGlyphShapingEnabled,
            let shaped = captureGlyphLayouts(from: layout, text: text, style: lineStyle),
            !shaped.isEmpty
        {
            resolvedGlyphs = shaped
            TextRenderDiagnosticsCounters.shapedGlyphRuns += 1
        } else {
            resolvedGlyphs = fallbackGlyphLayouts(from: layout, text: text, bounds: bounds, style: lineStyle)
            if !resolvedGlyphs.isEmpty {
                TextRenderDiagnosticsCounters.unshapedGlyphRuns += 1
            }
        }

        var lineWidth = bounds.width
        if let tracking = lineStyle.nativeLetterSpacing, tracking != 0, !resolvedGlyphs.isEmpty {
            lineWidth = applyLetterSpacing(tracking, to: &resolvedGlyphs, lineWidth: lineWidth)
        }

        let lineHeight = max(bounds.height, paragraphMetrics?.height ?? lineStyle.nativeFontPixelSize)
        let ascent =
            paragraphMetrics?.baseline
            ?? (lineStyle.lineSpacing >= 0
                ? lineStyle.nativeFontPixelSize * 0.8
                : max(lineStyle.nativeFontPixelSize * 0.8, lineHeight * 0.7))
        let descent = max(0, lineHeight - ascent)
        return NativeTextLineLayout(
            text: text,
            width: lineWidth,
            height: lineHeight,
            ascent: ascent,
            descent: descent,
            glyphs: resolvedGlyphs
        )
    }

    /// `letterSpacing` (`.kerning` / `.tracking`) is plumbed from `WinSwiftUI`
    /// and keyed in two caches, but DirectWrite's `IDWriteTextFormat` has no
    /// character-spacing knob (that lives on `IDWriteTextLayout1`, which this
    /// interop does not bind). Applying it to the shaped run keeps the one
    /// contract that matters: measurement and painting move together.
    /// Matches `PixelFont.rawLineWidth`, which spaces *between* glyphs only.
    private func applyLetterSpacing(
        _ letterSpacing: Double, to glyphs: inout [NativeTextGlyphLayout], lineWidth: Double
    ) -> Double {
        guard letterSpacing.isFinite else {
            return lineWidth
        }

        // Captured runs retain their logical glyph order. RTL runs walk left,
        // so spacing by array index would pull those glyphs closer together.
        // Apply gaps in visual order while retaining source/cluster identity.
        let visualOrder = glyphs.indices.sorted {
            if glyphs[$0].origin.x == glyphs[$1].origin.x {
                return $0 < $1
            }
            return glyphs[$0].origin.x < glyphs[$1].origin.x
        }
        for (position, index) in visualOrder.enumerated() {
            glyphs[index].origin.x += Double(position) * letterSpacing
            if position < glyphs.count - 1 {
                glyphs[index].advance += letterSpacing
            }
        }
        return max(0, lineWidth + Double(max(glyphs.count - 1, 0)) * letterSpacing)
    }

    private func atlasRasterizationStyle(from style: PixelTextStyle) -> PixelTextStyle {
        var glyphStyle = style
        glyphStyle.color = .white
        glyphStyle.alignment = .leading
        glyphStyle.verticalAlignment = .top
        glyphStyle.insets = .zero
        glyphStyle.maximumNumberOfLines = 1
        return glyphStyle
    }

    private func rasterizeCapturedGlyph(_ glyph: NativeTextGlyphLayout, scaleFactor: Double) -> NativeGlyphBitmap? {
        guard let fontFace = glyph.fontFace?.rawPointer, let glyphID = glyph.glyphID else {
            return nil
        }

        guard let metrics = makeCapturedGlyphRasterMetrics(for: glyph, scaleFactor: scaleFactor) else {
            return nil
        }

        guard
            let bitmapTarget = createBitmapRenderTarget(
                width: metrics.targetWidth,
                height: metrics.targetHeight,
                scaleFactor: metrics.renderScale
            )
        else {
            return nil
        }
        defer {
            var releasableBitmapTarget: UnsafeMutablePointer<IDWriteBitmapRenderTarget>? = bitmapTarget
            releaseDirectWriteCOM(&releasableBitmapTarget)
        }

        guard clearBitmapTarget(bitmapTarget) else {
            return nil
        }

        var drawingContext = DirectWriteDrawingContext(
            bitmapRenderTarget: bitmapTarget,
            renderingParams: renderingParams,
            pixelsPerDip: FLOAT(metrics.renderScale),
            textColor: COLORREF(0x00FF_FFFF)
        )

        let glyphIndices: [UINT16] = [UINT16(truncatingIfNeeded: glyphID)]
        let glyphAdvances: [FLOAT] = [FLOAT(metrics.advance)]
        let glyphOffsets: [DWRITE_GLYPH_OFFSET] = [DWRITE_GLYPH_OFFSET()]

        let baselineX = FLOAT(Double(metrics.paddingPixels) / metrics.renderScale)
        let baselineY = FLOAT(Double(metrics.paddingPixels) / metrics.renderScale + metrics.baselineYOffset)

        let drawHR = glyphIndices.withUnsafeBufferPointer { indices in
            glyphAdvances.withUnsafeBufferPointer { advances in
                glyphOffsets.withUnsafeBufferPointer { offsets in
                    var glyphRun = DWRITE_GLYPH_RUN(
                        fontFace: fontFace,
                        fontEmSize: FLOAT(metrics.fontSize),
                        glyphCount: 1,
                        glyphIndices: indices.baseAddress,
                        glyphAdvances: advances.baseAddress,
                        glyphOffsets: offsets.baseAddress,
                        isSideways: WindowsBool(false),
                        bidiLevel: 0
                    )

                    return withUnsafeMutablePointer(to: &drawingContext) { contextPointer in
                        drawGlyphRun(
                            glyphRun: &glyphRun,
                            baselineX: baselineX,
                            baselineY: baselineY,
                            contextPointer: contextPointer
                        )
                    }
                }
            }
        }

        guard isSuccess(drawHR),
            let surface = extractBitmapSurface(from: bitmapTarget),
            var cropped = cropGlyphSurface(surface, paddingPixels: metrics.paddingPixels)
        else {
            return nil
        }

        var pixels = [UInt8](cropped.surface.pixels)
        GDIRasterTextRenderer.tint(pixelBytes: &pixels, style: PixelTextStyle(color: .white))
        cropped.surface.pixels = Data(pixels)
        // `tint` scales the colour channels by coverage.
        cropped.surface.format = .bgra8Premultiplied

        return NativeGlyphBitmap(
            surface: cropped.surface,
            bearingX: cropped.bearingX,
            bearingY: cropped.bearingY - Float(metrics.baselineYOffset * metrics.renderScale),
            advance: Float(metrics.advance * metrics.renderScale),
            // The run was drawn at a known baseline inside the padded target,
            // and the crop is measured back to it.
            verticalFrame: .baseline
        )
    }

    private func captureGlyphLayouts(
        from layout: UnsafeMutablePointer<IDWriteTextLayout>,
        text: String,
        style: PixelTextStyle
    ) -> [NativeTextGlyphLayout]? {
        guard let renderer = createGlyphLayoutRenderer() else {
            return nil
        }
        defer {
            var releasableRenderer: UnsafeMutablePointer<IDWriteTextRenderer>? = renderer
            releaseDirectWriteCOM(&releasableRenderer)
        }

        var context = DirectWriteGlyphLayoutContext(glyphs: [])
        let drawHR = withUnsafeMutablePointer(to: &context) { contextPointer in
            layout.pointee.lpVtbl!.pointee.Draw(
                UnsafeMutableRawPointer(layout),
                UnsafeMutableRawPointer(contextPointer),
                UnsafeMutableRawPointer(renderer),
                0,
                0
            )
        }
        guard isSuccess(drawHR), !context.glyphs.isEmpty else {
            return nil
        }

        let characterInfo = characterInfoByUTF16Offset(for: text)
        return context.glyphs.map { glyph in
            let resolvedCharacter = glyph.textPosition.flatMap { characterInfo[$0] }
            // The run's own em size, not the paragraph's: a `TextSpan` with a
            // larger font shapes into a run whose `fontEmSize` is the span's,
            // and that is the size the glyph must be rastered at.
            let runFontSize = glyph.fontSize.isFinite && glyph.fontSize > 0 ? glyph.fontSize : style.nativeFontPixelSize
            return NativeTextGlyphLayout(
                character: resolvedCharacter?.character ?? " ",
                origin: glyph.origin,
                advance: glyph.advance,
                glyphID: glyph.glyphID,
                fontFace: glyph.fontFace,
                fontFaceID: glyph.fontFace.map { FontFaceRegistry.shared.identifier(for: $0) },
                fontFamily: style.fontFamily,
                weight: style.weight,
                fontSize: runFontSize,
                sourceIndex: resolvedCharacter?.index,
                // `DrawGlyphRun` reports a baseline origin, so `origin.y` is
                // the baseline - not the line top the hit-test walk reports.
                verticalFrame: .baseline
            )
        }
    }

    private func fallbackGlyphLayouts(
        from layout: UnsafeMutablePointer<IDWriteTextLayout>,
        text: String,
        bounds: TextBounds,
        style: PixelTextStyle
    ) -> [NativeTextGlyphLayout] {
        let characters = Array(text)
        let utf16Offsets = utf16CharacterOffsets(for: text)
        var glyphs: [NativeTextGlyphLayout] = []
        glyphs.reserveCapacity(characters.count)

        for index in characters.indices {
            guard let hit = hitTestTextPosition(layout: layout, textPosition: utf16Offsets[index]) else {
                continue
            }

            let nextX: Double
            if index + 1 < utf16Offsets.count,
                let nextHit = hitTestTextPosition(layout: layout, textPosition: utf16Offsets[index + 1])
            {
                nextX = nextHit.x
            } else {
                nextX = bounds.width
            }

            glyphs.append(
                NativeTextGlyphLayout(
                    character: characters[index],
                    origin: Point(x: hit.x, y: 0),
                    advance: max(0, nextX - hit.x),
                    fontFamily: style.fontFamily,
                    weight: style.weight,
                    fontSize: style.nativeFontPixelSize,
                    sourceIndex: index,
                    verticalFrame: .layoutBoxTop
                )
            )
        }

        return glyphs
    }

    private static let fallbackFontFamilies = ["Segoe UI", "Arial", "sans-serif"]

    private func createTextFormat(
        style: PixelTextStyle, wrapping: DWriteWordWrapping,
        paragraphMetrics: DirectWriteParagraphLineMetrics? = nil, usesNaturalLineMetrics: Bool = false
    ) -> UnsafeMutablePointer<
        IDWriteTextFormat
    >? {
        let format = createTextFormatWithFallback(style: style)
        guard let format else {
            return nil
        }

        _ = format.pointee.lpVtbl!.pointee.SetTextAlignment(
            UnsafeMutableRawPointer(format), style.alignment.dwriteAlignment)
        _ = format.pointee.lpVtbl!.pointee.SetParagraphAlignment(
            UnsafeMutableRawPointer(format), style.verticalAlignment.dwriteParagraphAlignment)
        _ = format.pointee.lpVtbl!.pointee.SetWordWrapping(UnsafeMutableRawPointer(format), wrapping)

        if let paragraphMetrics {
            _ = format.pointee.lpVtbl!.pointee.SetLineSpacing(
                UnsafeMutableRawPointer(format), dwriteLineSpacingMethodUniform,
                FLOAT(paragraphMetrics.height), FLOAT(paragraphMetrics.baseline))
        } else if !usesNaturalLineMetrics && style.lineSpacing >= 0 {
            _ = format.pointee.lpVtbl!.pointee.SetLineSpacing(
                UnsafeMutableRawPointer(format),
                dwriteLineSpacingMethodUniform,
                FLOAT(style.nativeFontPixelSize + style.lineSpacing),
                FLOAT(style.nativeFontPixelSize * 0.8)
            )
        }

        return format
    }

    /// Larger spans need a line box derived from the fonts DirectWrite actually
    /// resolved. Preserve the existing parity grid for plain/same-size text.
    /// One full-source grid is shared by every line and by the bitmap path;
    /// truncating a large span can conservatively leave extra leading.
    private func expandedSpanLineMetrics(for text: String, style: PixelTextStyle) -> DirectWriteParagraphLineMetrics? {
        guard
            style.spans?.contains(where: { $0.range != nil && $0.style.nativeFontPixelSize > style.nativeFontPixelSize }
            ) == true
        else {
            return nil
        }
        var probeStyle = TextLayoutFragment(source: text).rebasedStyle(style, sourceText: text)
        guard probeStyle.spans?.contains(where: { $0.style.nativeFontPixelSize > style.nativeFontPixelSize }) == true
        else {
            return nil
        }
        probeStyle.alignment = .leading
        probeStyle.verticalAlignment = .top
        guard
            let format = createTextFormat(
                style: probeStyle, wrapping: dwriteWordWrappingNoWrap, usesNaturalLineMetrics: true)
        else { return nil }
        defer {
            var releasableFormat: UnsafeMutablePointer<IDWriteTextFormat>? = format
            releaseDirectWriteCOM(&releasableFormat)
        }
        guard
            let layout = createTextLayout(
                text: text, format: format, size: Size(width: 4096, height: 4096), style: probeStyle)
        else { return nil }
        defer {
            var releasableLayout: UnsafeMutablePointer<IDWriteTextLayout>? = layout
            releaseDirectWriteCOM(&releasableLayout)
        }
        guard let rawGetLineMetrics = layout.pointee.lpVtbl!.pointee.GetLineMetrics else { return nil }
        let getLineMetrics = unsafeBitCast(rawGetLineMetrics, to: DWGetLineMetricsProc.self)
        var lineCount: UINT32 = 0
        let countHR = getLineMetrics(UnsafeMutableRawPointer(layout), nil, 0, &lineCount)
        guard isSuccess(countHR) || countHR == HRESULT(bitPattern: 0x8007_007A), lineCount > 0 else { return nil }
        var metrics = [DWRITE_LINE_METRICS](repeating: DWRITE_LINE_METRICS(), count: Int(lineCount))
        let capacity = lineCount
        let metricsHR = metrics.withUnsafeMutableBytes {
            getLineMetrics(UnsafeMutableRawPointer(layout), $0.baseAddress, capacity, &lineCount)
        }
        guard isSuccess(metricsHR), lineCount > 0, lineCount <= capacity else { return nil }
        var ascent = 0.0
        var descent = 0.0
        for line in metrics.prefix(Int(lineCount)) {
            guard line.height.isFinite, line.baseline.isFinite, line.height > 0, line.baseline >= 0 else { return nil }
            ascent = max(ascent, Double(line.baseline))
            descent = max(descent, Double(line.height - line.baseline))
        }
        let leading = style.lineSpacing.isFinite ? max(0, style.lineSpacing) : 0
        return DirectWriteParagraphLineMetrics(height: max(1, ascent + descent + leading), baseline: ascent)
    }

    private func createTextFormatWithFallback(style: PixelTextStyle) -> UnsafeMutablePointer<IDWriteTextFormat>? {
        if let format = attemptCreateTextFormat(fontFamily: style.fontFamily, style: style) {
            let resolvedFamily = fontFamilyName(from: format)
            if let resolvedFamily, resolvedFamily.lowercased() != style.fontFamily.lowercased() {
                debugLog("[DirectWrite] Font family '\(style.fontFamily)' resolved to '\(resolvedFamily)'")
            }
            return format
        }

        debugLog("[DirectWrite] Primary font '\(style.fontFamily)' unavailable, trying fallbacks")

        for fallback in DirectWriteSystem.fallbackFontFamilies {
            guard fallback.lowercased() != style.fontFamily.lowercased() else {
                continue
            }
            if let format = attemptCreateTextFormat(fontFamily: fallback, style: style) {
                debugLog("[DirectWrite] Using fallback font '\(fallback)'")
                return format
            }
        }

        debugLog("[DirectWrite] All font fallbacks failed")
        return nil
    }

    private func attemptCreateTextFormat(fontFamily: String, style: PixelTextStyle) -> UnsafeMutablePointer<
        IDWriteTextFormat
    >? {
        var formatRaw: UnsafeMutableRawPointer?
        let hr = withWideString(fontFamily) { familyName in
            withWideString("en-us") { localeName in
                factory.pointee.lpVtbl!.pointee.CreateTextFormat(
                    UnsafeMutableRawPointer(factory),
                    familyName,
                    nil,
                    style.weight.dwriteWeight,
                    style.dwriteFontStyle,
                    style.fontWidth.dwriteFontStretch,
                    FLOAT(style.nativeFontPixelSize),
                    localeName,
                    &formatRaw
                )
            }
        }

        guard isSuccess(hr), let formatRaw else {
            return nil
        }

        return formatRaw.assumingMemoryBound(to: IDWriteTextFormat.self)
    }

    private func fontFamilyName(from format: UnsafeMutablePointer<IDWriteTextFormat>) -> String? {
        var nameLength: UINT32 = 0
        let lengthHR = format.pointee.lpVtbl!.pointee.GetFontFamilyNameLength(
            UnsafeMutableRawPointer(format), &nameLength)
        guard isSuccess(lengthHR), nameLength > 0 else {
            return nil
        }

        let bufferSize = Int(nameLength + 1)
        var buffer = [WCHAR](repeating: 0, count: bufferSize)
        let nameHR = buffer.withUnsafeMutableBufferPointer { bufferPointer in
            format.pointee.lpVtbl!.pointee.GetFontFamilyName(
                UnsafeMutableRawPointer(format), bufferPointer.baseAddress!, UINT32(bufferSize))
        }
        guard isSuccess(nameHR) else {
            return nil
        }

        return String(decoding: buffer.prefix(Int(nameLength)), as: UTF16.self)
    }

    private func createTextLayout(
        text: String, format: UnsafeMutablePointer<IDWriteTextFormat>, size: Size, style: PixelTextStyle? = nil
    ) -> UnsafeMutablePointer<IDWriteTextLayout>? {
        let utf16 = Array(text.utf16)
        var layoutRaw: UnsafeMutableRawPointer?
        let hr = utf16.withUnsafeBufferPointer { buffer in
            factory.pointee.lpVtbl!.pointee.CreateTextLayout(
                UnsafeMutableRawPointer(factory),
                buffer.baseAddress,
                UINT32(buffer.count),
                UnsafeMutableRawPointer(format),
                FLOAT(max(size.width, 1)),
                FLOAT(max(size.height, 1)),
                &layoutRaw
            )
        }

        guard isSuccess(hr), let layoutRaw else {
            return nil
        }

        let layout = layoutRaw.assumingMemoryBound(to: IDWriteTextLayout.self)

        if let style {
            let rangeStart: UINT32 = 0
            let rangeLength = UINT32(utf16.count)
            let textRange = DWRITE_TEXT_RANGE(startPosition: rangeStart, length: rangeLength).packedValue

            if style.underline {
                if let fn = layout.pointee.lpVtbl!.pointee.SetUnderline {
                    let proc = unsafeBitCast(
                        fn, to: (@convention(c) (UnsafeMutableRawPointer?, WindowsBool, UInt64) -> HRESULT).self
                    )
                    _ = proc(UnsafeMutableRawPointer(layout), WindowsBool(true), textRange)
                }
            }

            if style.strikethrough {
                if let fn = layout.pointee.lpVtbl!.pointee.SetStrikethrough {
                    let proc = unsafeBitCast(
                        fn, to: (@convention(c) (UnsafeMutableRawPointer?, WindowsBool, UInt64) -> HRESULT).self
                    )
                    _ = proc(UnsafeMutableRawPointer(layout), WindowsBool(true), textRange)
                }
            }

            let typographyFeatures = style.dwriteTypographyFeatures
            if !typographyFeatures.isEmpty {
                applyTypographyFeatures(typographyFeatures, to: layout, startPosition: 0, length: UINT32(utf16.count))
            }

            if let spans = style.spans {
                applyTextSpans(spans, to: layout, fullText: text)
            }
        }

        return layout
    }

    private func applyTypographyFeatures(
        _ features: [DWriteFontFeature],
        to layout: UnsafeMutablePointer<IDWriteTextLayout>,
        startPosition: UINT32,
        length: UINT32
    ) {
        guard let typographyRaw = createTypography(features: features) else {
            return
        }
        defer {
            let unknown = typographyRaw.assumingMemoryBound(to: IUnknown.self)
            _ = unknown.pointee.lpVtbl.pointee.Release(unknown)
        }

        if let fn = layout.pointee.lpVtbl!.pointee.SetTypography {
            let proc = unsafeBitCast(
                fn,
                to: (@convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UInt64) -> HRESULT)
                    .self)
            let textRange = DWRITE_TEXT_RANGE(startPosition: startPosition, length: length).packedValue
            _ = proc(UnsafeMutableRawPointer(layout), typographyRaw, textRange)
        }
    }

    private func createTypography(features: [DWriteFontFeature]) -> UnsafeMutableRawPointer? {
        let createProc = factory.pointee.lpVtbl!.pointee.CreateTypography
        guard let createProc else {
            return nil
        }

        let createFn = unsafeBitCast(
            createProc,
            to: (@convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> HRESULT)
                .self)
        var typographyRaw: UnsafeMutableRawPointer?
        let hr = createFn(UnsafeMutableRawPointer(factory), &typographyRaw)
        guard isSuccess(hr), let typographyRaw else {
            return nil
        }

        let typography = typographyRaw.assumingMemoryBound(to: IDWriteTypography.self)
        for feature in features {
            let featureHR = typography.pointee.lpVtbl!.pointee.AddFontFeature(typographyRaw, feature.packedValue)
            guard isSuccess(featureHR) else {
                let unknown = typographyRaw.assumingMemoryBound(to: IUnknown.self)
                _ = unknown.pointee.lpVtbl.pointee.Release(unknown)
                return nil
            }
        }

        return typographyRaw
    }

    private func applyTextSpans(
        _ spans: [TextSpan], to layout: UnsafeMutablePointer<IDWriteTextLayout>, fullText: String
    ) {
        let utf16View = fullText.utf16

        for span in spans {
            guard let range = span.range else {
                continue
            }

            guard let utf16Start = range.lowerBound.samePosition(in: utf16View),
                let utf16End = range.upperBound.samePosition(in: utf16View)
            else {
                continue
            }

            let startPosition = UINT32(utf16View.distance(from: utf16View.startIndex, to: utf16Start))
            let length = UINT32(utf16View.distance(from: utf16Start, to: utf16End))
            let textRange = DWRITE_TEXT_RANGE(startPosition: startPosition, length: length).packedValue

            let spanStyle = span.style

            if let fn = layout.pointee.lpVtbl!.pointee.SetFontWeight {
                let proc = unsafeBitCast(
                    fn,
                    to: (@convention(c) (UnsafeMutableRawPointer?, DWriteFontWeight, UInt64) -> HRESULT).self)
                _ = proc(UnsafeMutableRawPointer(layout), spanStyle.weight.dwriteWeight, textRange)
            }

            if let fn = layout.pointee.lpVtbl!.pointee.SetFontStyle {
                let proc = unsafeBitCast(
                    fn, to: (@convention(c) (UnsafeMutableRawPointer?, DWriteFontStyle, UInt64) -> HRESULT).self
                )
                _ = proc(UnsafeMutableRawPointer(layout), spanStyle.dwriteFontStyle, textRange)
            }

            if let fn = layout.pointee.lpVtbl!.pointee.SetFontSize {
                let proc = unsafeBitCast(
                    fn, to: (@convention(c) (UnsafeMutableRawPointer?, FLOAT, UInt64) -> HRESULT).self)
                _ = proc(UnsafeMutableRawPointer(layout), FLOAT(spanStyle.nativeFontPixelSize), textRange)
            }

            let typographyFeatures = spanStyle.dwriteTypographyFeatures
            if !typographyFeatures.isEmpty {
                applyTypographyFeatures(
                    typographyFeatures,
                    to: layout,
                    startPosition: startPosition,
                    length: length
                )
            }

            if spanStyle.underline {
                if let fn = layout.pointee.lpVtbl!.pointee.SetUnderline {
                    let proc = unsafeBitCast(
                        fn, to: (@convention(c) (UnsafeMutableRawPointer?, WindowsBool, UInt64) -> HRESULT).self
                    )
                    _ = proc(UnsafeMutableRawPointer(layout), WindowsBool(true), textRange)
                }
            }

            if spanStyle.strikethrough {
                if let fn = layout.pointee.lpVtbl!.pointee.SetStrikethrough {
                    let proc = unsafeBitCast(
                        fn, to: (@convention(c) (UnsafeMutableRawPointer?, WindowsBool, UInt64) -> HRESULT).self
                    )
                    _ = proc(UnsafeMutableRawPointer(layout), WindowsBool(true), textRange)
                }
            }
        }
    }

    private func textBounds(for layout: UnsafeMutablePointer<IDWriteTextLayout>) -> TextBounds? {
        var metrics = DWRITE_TEXT_METRICS()
        let metricsHR = withUnsafeMutablePointer(to: &metrics) {
            layout.pointee.lpVtbl!.pointee.GetMetrics(UnsafeMutableRawPointer(layout), UnsafeMutableRawPointer($0))
        }
        guard isSuccess(metricsHR) else {
            return nil
        }

        var overhangs = DWRITE_OVERHANG_METRICS()
        let overhangsHR = withUnsafeMutablePointer(to: &overhangs) {
            layout.pointee.lpVtbl!.pointee.GetOverhangMetrics(
                UnsafeMutableRawPointer(layout), UnsafeMutableRawPointer($0))
        }
        guard isSuccess(overhangsHR) else {
            return nil
        }

        let overhangLeft = max(0, Double(overhangs.left))
        let overhangTop = max(0, Double(overhangs.top))
        let overhangRight = max(0, Double(overhangs.right))
        let overhangBottom = max(0, Double(overhangs.bottom))
        return TextBounds(
            width: Double(metrics.widthIncludingTrailingWhitespace) + overhangLeft + overhangRight,
            height: Double(metrics.height) + overhangTop + overhangBottom,
            overhangLeft: overhangLeft,
            overhangTop: overhangTop
        )
    }

    private func textOrigin(
        size: Size, style: PixelTextStyle, bounds: TextBounds,
        paragraphMetrics: DirectWriteParagraphLineMetrics? = nil
    ) -> Point {
        let contentHeight = max(0, size.height - style.insets.top - style.insets.bottom)
        let reservedHeight: Double
        if let reservedLineCount = reservedTextLineCount(for: style), let paragraphMetrics {
            reservedHeight = Double(reservedLineCount) * paragraphMetrics.height
        } else if let reservedLineCount = reservedTextLineCount(for: style) {
            reservedHeight =
                Double(reservedLineCount) * style.nativeFontPixelSize + Double(max(reservedLineCount - 1, 0))
                * style.lineSpacing
        } else {
            reservedHeight = 0
        }
        let alignmentHeight = max(bounds.height, reservedHeight)
        let verticalOffset: Double
        switch style.verticalAlignment {
        case .top:
            verticalOffset = 0
        case .center:
            verticalOffset = max(0, (contentHeight - alignmentHeight) * 0.5)
        case .bottom:
            verticalOffset = max(0, contentHeight - alignmentHeight)
        }
        return Point(
            x: style.insets.leading + bounds.overhangLeft,
            y: style.insets.top + verticalOffset + bounds.overhangTop
        )
    }

    private func hitTestTextPosition(layout: UnsafeMutablePointer<IDWriteTextLayout>, textPosition: UINT32) -> (
        x: Double, y: Double
    )? {
        guard let rawProc = layout.pointee.lpVtbl!.pointee.HitTestTextPosition else {
            return nil
        }

        let proc = unsafeBitCast(rawProc, to: DWHitTestTextPositionProc.self)
        var pointX: FLOAT = 0
        var pointY: FLOAT = 0
        var metrics = DWRITE_HIT_TEST_METRICS()
        let hr = withUnsafeMutablePointer(to: &metrics) { metricsPointer in
            proc(
                UnsafeMutableRawPointer(layout),
                textPosition,
                WindowsBool(false),
                &pointX,
                &pointY,
                UnsafeMutableRawPointer(metricsPointer)
            )
        }
        guard isSuccess(hr) else {
            return nil
        }

        return (Double(pointX), Double(pointY))
    }

    private static func makeRenderingParams(factory: UnsafeMutablePointer<IDWriteFactory>) throws
        -> UnsafeMutablePointer<IDWriteRenderingParams>
    {
        var renderingParamsRaw: UnsafeMutableRawPointer?
        let customHR = factory.pointee.lpVtbl!.pointee.CreateCustomRenderingParams(
            UnsafeMutableRawPointer(factory),
            2.2,
            1.0,
            0.0,
            dwritePixelGeometryFlat,
            dwriteRenderingModeNatural,
            &renderingParamsRaw
        )

        if isSuccess(customHR), let renderingParamsRaw {
            return renderingParamsRaw.assumingMemoryBound(to: IDWriteRenderingParams.self)
        }

        let defaultHR = factory.pointee.lpVtbl!.pointee.CreateRenderingParams(
            UnsafeMutableRawPointer(factory), &renderingParamsRaw)
        guard isSuccess(defaultHR), let renderingParamsRaw else {
            throw DirectWriteError.initializationFailed("IDWriteFactory.CreateRenderingParams")
        }

        return renderingParamsRaw.assumingMemoryBound(to: IDWriteRenderingParams.self)
    }

    private func clearBitmapTarget(_ target: UnsafeMutablePointer<IDWriteBitmapRenderTarget>) -> Bool {
        guard
            let dc = target.pointee.lpVtbl!.pointee.GetMemoryDC(UnsafeMutableRawPointer(target)),
            let bitmap = GetCurrentObject(dc, UINT(OBJ_BITMAP))
        else {
            return false
        }

        var dibSection = DIBSECTION()
        let result = GetObjectW(bitmap, Int32(MemoryLayout<DIBSECTION>.size), &dibSection)
        guard result != 0, let bits = dibSection.dsBm.bmBits else {
            return false
        }

        let height = abs(Int32(dibSection.dsBmih.biHeight))
        let bytesPerRow = Int32(dibSection.dsBm.bmWidthBytes)
        // Int, not Int32: a 4K-wide surface overflows the product in 32 bits
        // long before it overflows the allocation it describes.
        guard height > 0, bytesPerRow > 0 else {
            return false
        }
        memset(bits, 0, Int(bytesPerRow) * Int(height))
        return true
    }

    private func extractBitmapSurface(from target: UnsafeMutablePointer<IDWriteBitmapRenderTarget>) -> BitmapSurface? {
        guard
            let dc = target.pointee.lpVtbl!.pointee.GetMemoryDC(UnsafeMutableRawPointer(target)),
            let bitmap = GetCurrentObject(dc, UINT(OBJ_BITMAP))
        else {
            return nil
        }

        var dibSection = DIBSECTION()
        let result = GetObjectW(bitmap, Int32(MemoryLayout<DIBSECTION>.size), &dibSection)
        guard result != 0, let bits = dibSection.dsBm.bmBits else {
            return nil
        }

        let width = Int32(dibSection.dsBmih.biWidth)
        let height = abs(Int32(dibSection.dsBmih.biHeight))
        let bytesPerRow = Int32(dibSection.dsBm.bmWidthBytes)
        guard width > 0, height > 0, bytesPerRow >= width * 4 else {
            return nil
        }
        let data = Data(bytes: bits, count: Int(bytesPerRow) * Int(height))

        return BitmapSurface(width: width, height: height, bytesPerRow: bytesPerRow, pixels: data)
    }

    private func createBitmapRenderTarget(width: Int32, height: Int32, scaleFactor: Double) -> UnsafeMutablePointer<
        IDWriteBitmapRenderTarget
    >? {
        var bitmapTargetRaw: UnsafeMutableRawPointer?
        let hr = gdiInterop.pointee.lpVtbl!.pointee.CreateBitmapRenderTarget(
            UnsafeMutableRawPointer(gdiInterop),
            nil,
            UINT(max(width, 1)),
            UINT(max(height, 1)),
            &bitmapTargetRaw
        )
        guard isSuccess(hr), let bitmapTargetRaw else {
            return nil
        }

        let bitmapTarget = bitmapTargetRaw.assumingMemoryBound(to: IDWriteBitmapRenderTarget.self)
        _ = bitmapTarget.pointee.lpVtbl!.pointee.SetPixelsPerDip(
            UnsafeMutableRawPointer(bitmapTarget), FLOAT(scaleFactor))
        return bitmapTarget
    }

    private func drawGlyphRun(
        glyphRun: inout DWRITE_GLYPH_RUN,
        baselineX: FLOAT,
        baselineY: FLOAT,
        contextPointer: UnsafeMutablePointer<DirectWriteDrawingContext>
    ) -> HRESULT {
        guard let renderer = createTextRenderer() else {
            return HRESULT(bitPattern: 0x8000_4005)
        }
        defer {
            var releasableRenderer: UnsafeMutablePointer<IDWriteTextRenderer>? = renderer
            releaseDirectWriteCOM(&releasableRenderer)
        }

        return directWriteRendererDrawGlyphRun(
            UnsafeMutableRawPointer(renderer),
            UnsafeMutableRawPointer(contextPointer),
            baselineX,
            baselineY,
            dwriteMeasuringModeNatural,
            &glyphRun,
            nil,
            nil
        )
    }

    private func cropGlyphSurface(_ surface: BitmapSurface, paddingPixels: Int32) -> (
        surface: BitmapSurface, bearingX: Float, bearingY: Float
    )? {
        let width = Int(surface.width)
        let height = Int(surface.height)
        let stride = Int(surface.bytesPerRow)
        let bytes = [UInt8](surface.pixels)

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1

        for y in 0..<height {
            for x in 0..<width {
                let byteIndex = y * stride + x * 4
                guard byteIndex + 3 < bytes.count,
                    bytes[byteIndex] > 0 || bytes[byteIndex + 1] > 0 || bytes[byteIndex + 2] > 0
                        || bytes[byteIndex + 3] > 0
                else {
                    continue
                }

                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        guard maxX >= minX, maxY >= minY else {
            return nil
        }

        let croppedWidth = maxX - minX + 1
        let croppedHeight = maxY - minY + 1
        var cropped = [UInt8](repeating: 0, count: croppedWidth * croppedHeight * 4)

        for row in 0..<croppedHeight {
            let sourceOffset = (minY + row) * stride + minX * 4
            let destinationOffset = row * croppedWidth * 4
            let count = croppedWidth * 4
            cropped[destinationOffset..<(destinationOffset + count)] = bytes[sourceOffset..<(sourceOffset + count)]
        }

        return (
            surface: BitmapSurface(
                width: Int32(croppedWidth),
                height: Int32(croppedHeight),
                bytesPerRow: Int32(croppedWidth * 4),
                pixels: Data(cropped),
                format: surface.format
            ),
            bearingX: Float(minX) - Float(paddingPixels),
            bearingY: Float(minY) - Float(paddingPixels)
        )
    }

    /// One memoised `measureLine` closure for a whole `layout`/`rasterize`
    /// call.
    ///
    /// `resolveTextLayout` probes the same candidate strings more than once -
    /// the minimum-scale-factor pass and the wrap pass measure the same lines,
    /// and `wrapLine` re-measures the accumulating candidate - and every miss
    /// on the DirectWrite path builds and destroys a full `IDWriteTextLayout`.
    /// The memo also folds in `nativeLetterSpacing` so wrapping decisions and
    /// painted advances are computed from the same widths.
    private func textFragment(for text: String, style: PixelTextStyle) -> TextLayoutFragment {
        style.spans?.isEmpty == false ? TextLayoutFragment(source: text) : TextLayoutFragment(synthetic: text)
    }

    private func makeLineMeasurer(
        style: PixelTextStyle, sourceText: String, format: UnsafeMutablePointer<IDWriteTextFormat>
    ) -> (TextLayoutFragment) -> Double {
        let tracking = style.nativeLetterSpacing ?? 0
        var memo: [TextLayoutFragment: Double] = [:]
        return { [weak self] fragment in
            let key = style.spans?.isEmpty == false ? fragment : TextLayoutFragment(synthetic: fragment.text)
            if let cached = memo[key] {
                return cached
            }
            let candidateStyle = fragment.rebasedStyle(style, sourceText: sourceText)
            let base = self?.measureSingleLine(fragment.text, format: format, style: candidateStyle) ?? 0
            let spaced: Double
            if tracking == 0 {
                spaced = base
            } else {
                let gaps =
                    self?.trackedGapCount(for: fragment.text, style: candidateStyle) ?? max(fragment.text.count - 1, 0)
                spaced = max(0, base + Double(gaps) * tracking)
            }
            memo[key] = spaced
            return spaced
        }
    }

    /// How many inter-glyph gaps `applyLetterSpacing` will space `line` at,
    /// so measurement and painting add the same amount of tracking.
    ///
    /// This used to be `line.count - 1` — *characters*, not glyphs. Shaping
    /// makes the two counts different in both directions: a ligature
    /// collapses two characters into one glyph, a combining mark expands one
    /// character into two, and a complex script does both. Wrapping then
    /// reserved a width the paint never used (or, for a ligature, less than
    /// it used), which is exactly the divergence `makeLineMeasurer` exists to
    /// close.
    private func trackedGapCount(for line: String, style: PixelTextStyle) -> Int {
        max((shapedGlyphCount(for: line, style: style) ?? line.count) - 1, 0)
    }

    /// The shaped glyph count `layoutLine` will resolve for `line`, or `nil`
    /// when it will fall back to the per-character walk (whose glyph count is
    /// the character count).
    ///
    /// Built exactly the way `layoutLine` builds its layout — same forced
    /// leading/top alignment, same style-derived typography features and
    /// spans — because a count taken from a differently configured layout is
    /// no more trustworthy than the character count it replaces. Only ever
    /// called for text carrying `nativeLetterSpacing`, which nothing but
    /// `.kerning` / `.tracking` sets.
    private func shapedGlyphCount(for line: String, style: PixelTextStyle) -> Int? {
        guard NativeTextRenderer.isGlyphShapingEnabled, !line.isEmpty else {
            return nil
        }

        guard let cacheKey = ShapedGlyphCountKey(line: line, style: style) else {
            // This compact memo has no span-style identity. Do not share a
            // count between ranges with different fonts or typography.
            return uncachedShapedGlyphCount(for: line, style: style)
        }
        if let cached = shapedGlyphCounts[cacheKey] {
            return cached.count
        }

        let count = uncachedShapedGlyphCount(for: line, style: style)
        insertShapedGlyphCount(count, for: cacheKey)
        return count
    }

    /// Records `count` in ``shapedGlyphCounts``, evicting the oldest entry once
    /// the memo is full.
    private func insertShapedGlyphCount(_ count: Int?, for key: ShapedGlyphCountKey) {
        if shapedGlyphCounts[key] == nil, shapedGlyphCounts.count >= Self.maximumShapedGlyphCountEntries,
            let oldest = shapedGlyphCountOrder.first
        {
            shapedGlyphCountOrder.removeFirst()
            shapedGlyphCounts.removeValue(forKey: oldest)
        }
        if shapedGlyphCounts.updateValue(ShapedGlyphCount(count: count), forKey: key) == nil {
            shapedGlyphCountOrder.append(key)
        }
    }

    private func uncachedShapedGlyphCount(for line: String, style: PixelTextStyle) -> Int? {
        shapedGlyphCountProbes += 1

        var lineStyle = style
        lineStyle.verticalAlignment = .top
        lineStyle.alignment = .leading

        guard let format = createTextFormat(style: lineStyle, wrapping: dwriteWordWrappingNoWrap),
            let layout = createTextLayout(
                text: line, format: format, size: Size(width: 4096, height: 4096), style: lineStyle)
        else {
            return nil
        }
        defer {
            var releasableLayout: UnsafeMutablePointer<IDWriteTextLayout>? = layout
            releaseDirectWriteCOM(&releasableLayout)
            var releasableFormat: UnsafeMutablePointer<IDWriteTextFormat>? = format
            releaseDirectWriteCOM(&releasableFormat)
        }

        guard let shaped = captureGlyphLayouts(from: layout, text: line, style: lineStyle), !shaped.isEmpty else {
            return nil
        }
        return shaped.count
    }

    /// Test seam: the width wrapping and minimum-scale-factor decisions are
    /// made from, for one line. It must equal the width `layoutLine` paints;
    /// nothing else pins the two together.
    func measuredLineWidthForTesting(_ text: String, style: PixelTextStyle) -> Double? {
        guard let format = createTextFormat(style: style, wrapping: dwriteWordWrappingNoWrap) else {
            return nil
        }
        defer {
            var releasableFormat: UnsafeMutablePointer<IDWriteTextFormat>? = format
            releaseDirectWriteCOM(&releasableFormat)
        }
        return makeLineMeasurer(style: style, sourceText: text, format: format)(textFragment(for: text, style: style))
    }

    private func measureSingleLine(
        _ text: String, format: UnsafeMutablePointer<IDWriteTextFormat>, style: PixelTextStyle? = nil
    ) -> Double? {
        guard !text.isEmpty else {
            return 0
        }

        guard
            let layout = createTextLayout(
                text: text, format: format, size: Size(width: 4096, height: 4096), style: style)
        else {
            return nil
        }
        defer {
            var releasableLayout: UnsafeMutablePointer<IDWriteTextLayout>? = layout
            releaseDirectWriteCOM(&releasableLayout)
        }

        // Measure in the same natural coordinate space as layoutLine. A
        // centered 4096-point probe loses precision when DirectWrite derives
        // its width from positioned glyphs: a 15.2-point icon reports
        // 15.200073 instead of 15.199999. At 125% DPI its own raster is 15.2
        // points wide, so that error can truncate the icon to a missing-glyph
        // period. Override only this temporary layout, never the paint format.
        _ = layout.pointee.lpVtbl!.pointee.SetTextAlignment(
            UnsafeMutableRawPointer(layout), dwriteTextAlignmentLeading)
        _ = layout.pointee.lpVtbl!.pointee.SetParagraphAlignment(
            UnsafeMutableRawPointer(layout), dwriteParagraphAlignmentNear)

        return textBounds(for: layout)?.width
    }

    private func wrappingMode(for layout: ResolvedTextLayout, style: PixelTextStyle) -> DWriteWordWrapping {
        if layout.fragments.count > 1 || style.lineBreakMode == .wrap {
            return dwriteWordWrappingWrap
        }

        return dwriteWordWrappingNoWrap
    }
}
private struct TextBounds {
    var width: Double
    var height: Double
    var overhangLeft: Double
    var overhangTop: Double
}
private func contentWidthLimit(for maxWidth: Double?, style: PixelTextStyle) -> Double? {
    guard let maxWidth, maxWidth.isFinite else {
        return nil
    }

    return max(0, maxWidth - style.insets.leading - style.insets.trailing)
}
private func clampedMeasuredWidth(_ contentWidth: Double, style: PixelTextStyle, maxWidth: Double?) -> Double {
    if style.lineBreakMode == .clip, let contentLimit = contentWidthLimit(for: maxWidth, style: style) {
        return min(contentWidth, contentLimit)
    }

    return contentWidth
}
func snapLogicalTextSize(_ size: Size, scaleFactor: Double) -> Size {
    Size(
        width: max(1, snapLogicalTextExtent(size.width, scaleFactor: scaleFactor)),
        height: max(1, snapLogicalTextExtent(size.height, scaleFactor: scaleFactor))
    )
}
func snapLogicalTextExtent(_ extent: Double, scaleFactor: Double) -> Double {
    guard scaleFactor > 0 else {
        return extent
    }

    return (extent * scaleFactor).rounded(.up) / scaleFactor
}
private func utf16CharacterOffsets(for text: String) -> [UINT32] {
    var offsets: [UINT32] = []
    offsets.reserveCapacity(text.count)
    var utf16Offset: UInt32 = 0
    for character in text {
        offsets.append(utf16Offset)
        utf16Offset += UInt32(String(character).utf16.count)
    }
    return offsets
}
private func characterInfoByUTF16Offset(for text: String) -> [UInt32: (index: Int, character: Character)] {
    let characters = Array(text)
    let offsets = utf16CharacterOffsets(for: text)
    var result: [UInt32: (index: Int, character: Character)] = [:]
    result.reserveCapacity(characters.count)

    for index in characters.indices {
        result[offsets[index]] = (index, characters[index])
    }

    return result
}
/// Which struct a renderer callback's `clientDrawingContext` points at.
///
/// `IDWriteTextLayout.Draw` passes one untyped `void *` to every entry of the
/// renderer vtable, and this file installs *two* renderers that pass two
/// different structs through it: the bitmap draw path passes a
/// ``DirectWriteDrawingContext``, the shaping capture passes a
/// ``DirectWriteGlyphLayoutContext``. A callback shared by both vtables
/// therefore has to know which one it got. One did not: `GetPixelsPerDip` read
/// `pixelsPerDip` (offset 16) out of the 8-byte capture context and handed
/// DirectWrite whatever followed it in memory. DirectWrite feeds that value
/// into its baseline pixel snapping, so on an unlucky process every shaped line
/// reported `baselineOriginY == 0` — a whole ascent too high, with most of the
/// line then culled above the surface. The tag makes the confusion detectable
/// instead of silent.
///
/// Each context stores it as a plain `UInt32` first field rather than as an
/// enum value: a two-case enum occupies one byte, and the three padding bytes
/// after it are exactly the kind of uninitialized memory this tag exists to
/// stop anything reading.
private enum DirectWriteClientContextTag {
    static let bitmapDrawing: UInt32 = 0x4457_4244
    static let glyphLayoutCapture: UInt32 = 0x4457_474C
}
private struct DirectWriteDrawingContext {
    var contextTag: UInt32 = DirectWriteClientContextTag.bitmapDrawing
    var bitmapRenderTarget: UnsafeMutablePointer<IDWriteBitmapRenderTarget>
    var renderingParams: UnsafeMutablePointer<IDWriteRenderingParams>
    var pixelsPerDip: FLOAT
    var textColor: COLORREF
}
private struct DirectWriteGlyphLayoutContext {
    var contextTag: UInt32 = DirectWriteClientContextTag.glyphLayoutCapture
    var glyphs: [DirectWriteCapturedGlyph]
}
private struct DirectWriteCapturedGlyph {
    var glyphID: UInt32
    var textPosition: UInt32?
    var origin: Point
    var advance: Double
    var fontFace: NativeFontFaceHandle?
    var fontSize: Double
}
private struct SwiftTextRendererCOM {
    var interface: IDWriteTextRenderer
    var refCount: ULONG
}
@MainActor
private var directWriteTextRendererVTable = IDWriteTextRendererVtbl(
    QueryInterface: directWriteRendererQueryInterface,
    AddRef: directWriteRendererAddRef,
    Release: directWriteRendererRelease,
    IsPixelSnappingDisabled: directWriteRendererIsPixelSnappingDisabled,
    GetCurrentTransform: directWriteRendererGetCurrentTransform,
    GetPixelsPerDip: directWriteRendererGetPixelsPerDip,
    DrawGlyphRun: directWriteRendererDrawGlyphRun,
    DrawUnderline: directWriteRendererDrawUnderline,
    DrawStrikethrough: directWriteRendererDrawStrikethrough,
    DrawInlineObject: directWriteRendererDrawInlineObject
)
@MainActor
private var directWriteGlyphLayoutRendererVTable = IDWriteTextRendererVtbl(
    QueryInterface: directWriteRendererQueryInterface,
    AddRef: directWriteRendererAddRef,
    Release: directWriteRendererRelease,
    IsPixelSnappingDisabled: directWriteGlyphLayoutIsPixelSnappingDisabled,
    GetCurrentTransform: directWriteRendererGetCurrentTransform,
    GetPixelsPerDip: directWriteGlyphLayoutGetPixelsPerDip,
    DrawGlyphRun: directWriteGlyphLayoutDrawGlyphRun,
    DrawUnderline: directWriteGlyphLayoutDrawUnderline,
    DrawStrikethrough: directWriteGlyphLayoutDrawStrikethrough,
    DrawInlineObject: directWriteGlyphLayoutDrawInlineObject
)
@MainActor
private func createTextRenderer() -> UnsafeMutablePointer<IDWriteTextRenderer>? {
    let storage = UnsafeMutablePointer<SwiftTextRendererCOM>.allocate(capacity: 1)
    storage.initialize(
        to: SwiftTextRendererCOM(interface: IDWriteTextRenderer(lpVtbl: &directWriteTextRendererVTable), refCount: 1))
    return UnsafeMutableRawPointer(storage).assumingMemoryBound(to: IDWriteTextRenderer.self)
}
@MainActor
private func createGlyphLayoutRenderer() -> UnsafeMutablePointer<IDWriteTextRenderer>? {
    let storage = UnsafeMutablePointer<SwiftTextRendererCOM>.allocate(capacity: 1)
    storage.initialize(
        to: SwiftTextRendererCOM(
            interface: IDWriteTextRenderer(lpVtbl: &directWriteGlyphLayoutRendererVTable), refCount: 1))
    return UnsafeMutableRawPointer(storage).assumingMemoryBound(to: IDWriteTextRenderer.self)
}
/// Test seam: what the shaping-capture renderer answers DirectWrite's pixel
/// snapping questions with, asked through the installed vtable with the very
/// context ``captureGlyphLayouts`` passes.
///
/// Nothing else can observe this — the answers go straight into DirectWrite,
/// which folds them into the baseline origin it reports back. When
/// `GetPixelsPerDip` read them out of the wrong struct the value was
/// uninitialized memory: stable within a process, different in the next one,
/// and occasionally small enough to snap a whole line's baseline to zero.
@MainActor
func glyphLayoutRendererPixelSnappingForTesting() -> (isPixelSnappingDisabled: Bool, pixelsPerDip: Float)? {
    guard let renderer = createGlyphLayoutRenderer() else {
        return nil
    }
    defer {
        var releasableRenderer: UnsafeMutablePointer<IDWriteTextRenderer>? = renderer
        releaseDirectWriteCOM(&releasableRenderer)
    }

    var context = DirectWriteGlyphLayoutContext(glyphs: [])
    var isDisabled = WindowsBool(false)
    var pixelsPerDip: FLOAT = 0
    let vtable = renderer.pointee.lpVtbl!.pointee
    withUnsafeMutablePointer(to: &context) { contextPointer in
        _ = vtable.IsPixelSnappingDisabled(
            UnsafeMutableRawPointer(renderer), UnsafeMutableRawPointer(contextPointer), &isDisabled)
        _ = vtable.GetPixelsPerDip(
            UnsafeMutableRawPointer(renderer), UnsafeMutableRawPointer(contextPointer), &pixelsPerDip)
    }
    return (isDisabled == true, Float(pixelsPerDip))
}
private func rendererStorage(from rawPointer: UnsafeMutableRawPointer?) -> UnsafeMutablePointer<SwiftTextRendererCOM>? {
    guard let rawPointer else {
        return nil
    }

    return rawPointer.assumingMemoryBound(to: SwiftTextRendererCOM.self)
}
/// The tag both client-drawing-context structs carry in their first word.
/// Reading it is always in bounds: every context this file hands DirectWrite
/// begins with it.
private func clientContextTag(of rawPointer: UnsafeMutableRawPointer) -> UInt32 {
    rawPointer.load(as: UInt32.self)
}
private func drawingContext(from rawPointer: UnsafeMutableRawPointer?) -> UnsafeMutablePointer<
    DirectWriteDrawingContext
>? {
    guard let rawPointer, clientContextTag(of: rawPointer) == DirectWriteClientContextTag.bitmapDrawing else {
        return nil
    }

    return rawPointer.assumingMemoryBound(to: DirectWriteDrawingContext.self)
}
private func glyphLayoutContext(from rawPointer: UnsafeMutableRawPointer?) -> UnsafeMutablePointer<
    DirectWriteGlyphLayoutContext
>? {
    guard let rawPointer, clientContextTag(of: rawPointer) == DirectWriteClientContextTag.glyphLayoutCapture else {
        return nil
    }

    return rawPointer.assumingMemoryBound(to: DirectWriteGlyphLayoutContext.self)
}
private func directWriteRendererQueryInterface(
    _ rawSelf: UnsafeMutableRawPointer?, _ iid: UnsafePointer<GUID>?,
    _ object: UnsafeMutablePointer<UnsafeMutableRawPointer?>?
) -> HRESULT {
    guard let rawSelf, let iid else {
        object?.pointee = nil
        return HRESULT(bitPattern: 0x8000_4003)
    }

    let guid = iid.pointee
    if guidEquals(guid, iidIUnknownDirectWrite) || guidEquals(guid, iidIDWritePixelSnapping)
        || guidEquals(guid, iidIDWriteTextRenderer)
    {
        object?.pointee = rawSelf
        _ = directWriteRendererAddRef(rawSelf)
        return 0
    }

    object?.pointee = nil
    return HRESULT(bitPattern: 0x8000_4002)
}
private func directWriteRendererAddRef(_ rawSelf: UnsafeMutableRawPointer?) -> ULONG {
    guard let storage = rendererStorage(from: rawSelf) else {
        return 0
    }

    storage.pointee.refCount += 1
    return storage.pointee.refCount
}
private func directWriteRendererRelease(_ rawSelf: UnsafeMutableRawPointer?) -> ULONG {
    guard let storage = rendererStorage(from: rawSelf) else {
        return 0
    }

    storage.pointee.refCount -= 1
    let count = storage.pointee.refCount
    if count == 0 {
        storage.deinitialize(count: 1)
        storage.deallocate()
    }
    return count
}
private func directWriteRendererIsPixelSnappingDisabled(
    _ rawSelf: UnsafeMutableRawPointer?, _ clientDrawingContext: UnsafeMutableRawPointer?,
    _ isDisabled: UnsafeMutablePointer<WindowsBool>?
) -> HRESULT {
    isDisabled?.pointee = WindowsBool(false)
    return 0
}
private func directWriteRendererGetCurrentTransform(
    _ rawSelf: UnsafeMutableRawPointer?, _ clientDrawingContext: UnsafeMutableRawPointer?,
    _ transform: UnsafeMutableRawPointer?
) -> HRESULT {
    guard let transform else {
        return HRESULT(bitPattern: 0x8000_4003)
    }

    transform.assumingMemoryBound(to: DWRITE_MATRIX.self).pointee = DWRITE_MATRIX()
    return 0
}
private func directWriteRendererGetPixelsPerDip(
    _ rawSelf: UnsafeMutableRawPointer?, _ clientDrawingContext: UnsafeMutableRawPointer?,
    _ pixelsPerDip: UnsafeMutablePointer<FLOAT>?
) -> HRESULT {
    // DirectWrite divides by this to snap a run's baseline origin, so a garbage
    // value does not degrade the raster - it relocates the whole line. The
    // context tag rejects a foreign context and the finite/positive guard
    // rejects a corrupt one; either way DirectWrite gets 1 DIP per pixel.
    let reported = drawingContext(from: clientDrawingContext)?.pointee.pixelsPerDip ?? 1.0
    pixelsPerDip?.pointee = reported.isFinite && reported > 0 ? reported : 1.0
    return 0
}

/// The shaping capture asks the layout where its glyphs *are*, in the layout's
/// own DIP coordinates; it never draws. Pixel snapping would round the baseline
/// origin against a device grid the capture has no business knowing about, and
/// the painter snaps glyph destinations to device pixels itself
/// (`ScenePainter.appendNativeTextGlyphs`). So the capture renderer declares
/// snapping off and a 1:1 DIP scale, and never consults the client context.
private func directWriteGlyphLayoutIsPixelSnappingDisabled(
    _ rawSelf: UnsafeMutableRawPointer?, _ clientDrawingContext: UnsafeMutableRawPointer?,
    _ isDisabled: UnsafeMutablePointer<WindowsBool>?
) -> HRESULT {
    isDisabled?.pointee = WindowsBool(true)
    return 0
}
private func directWriteGlyphLayoutGetPixelsPerDip(
    _ rawSelf: UnsafeMutableRawPointer?, _ clientDrawingContext: UnsafeMutableRawPointer?,
    _ pixelsPerDip: UnsafeMutablePointer<FLOAT>?
) -> HRESULT {
    pixelsPerDip?.pointee = 1.0
    return 0
}
private func directWriteRendererDrawGlyphRun(
    _ rawSelf: UnsafeMutableRawPointer?, _ clientDrawingContext: UnsafeMutableRawPointer?, _ baselineOriginX: FLOAT,
    _ baselineOriginY: FLOAT, _ measuringMode: DWriteMeasuringMode, _ glyphRun: UnsafeMutableRawPointer?,
    _ glyphRunDescription: UnsafeMutableRawPointer?, _ clientDrawingEffect: UnsafeMutableRawPointer?
) -> HRESULT {
    guard let context = drawingContext(from: clientDrawingContext) else {
        return HRESULT(bitPattern: 0x8000_4003)
    }

    return context.pointee.bitmapRenderTarget.pointee.lpVtbl!.pointee.DrawGlyphRun(
        UnsafeMutableRawPointer(context.pointee.bitmapRenderTarget),
        baselineOriginX,
        baselineOriginY,
        measuringMode,
        glyphRun,
        UnsafeMutableRawPointer(context.pointee.renderingParams),
        context.pointee.textColor,
        nil
    )
}
private func directWriteRendererDrawUnderline(
    _ rawSelf: UnsafeMutableRawPointer?, _ clientDrawingContext: UnsafeMutableRawPointer?, _ baselineOriginX: FLOAT,
    _ baselineOriginY: FLOAT, _ underlineRaw: UnsafeMutableRawPointer?, _ clientDrawingEffect: UnsafeMutableRawPointer?
) -> HRESULT {
    guard let context = drawingContext(from: clientDrawingContext), let underlineRaw else {
        return 0
    }

    let underline = underlineRaw.assumingMemoryBound(to: DWRITE_UNDERLINE.self).pointee
    drawDecoration(
        width: underline.width, thickness: underline.thickness, offset: underline.offset,
        baselineOriginX: baselineOriginX, baselineOriginY: baselineOriginY, context: context.pointee)
    return 0
}
private func directWriteRendererDrawStrikethrough(
    _ rawSelf: UnsafeMutableRawPointer?, _ clientDrawingContext: UnsafeMutableRawPointer?, _ baselineOriginX: FLOAT,
    _ baselineOriginY: FLOAT, _ strikethroughRaw: UnsafeMutableRawPointer?,
    _ clientDrawingEffect: UnsafeMutableRawPointer?
) -> HRESULT {
    guard let context = drawingContext(from: clientDrawingContext), let strikethroughRaw else {
        return 0
    }

    let strikethrough = strikethroughRaw.assumingMemoryBound(to: DWRITE_STRIKETHROUGH.self).pointee
    drawDecoration(
        width: strikethrough.width, thickness: strikethrough.thickness, offset: strikethrough.offset,
        baselineOriginX: baselineOriginX, baselineOriginY: baselineOriginY, context: context.pointee)
    return 0
}
private func directWriteRendererDrawInlineObject(
    _ rawSelf: UnsafeMutableRawPointer?, _ clientDrawingContext: UnsafeMutableRawPointer?, _ originX: FLOAT,
    _ originY: FLOAT, _ inlineObject: UnsafeMutableRawPointer?, _ isSideways: WindowsBool, _ isRightToLeft: WindowsBool,
    _ clientDrawingEffect: UnsafeMutableRawPointer?
) -> HRESULT {
    return 0
}
private func directWriteGlyphLayoutDrawGlyphRun(
    _ rawSelf: UnsafeMutableRawPointer?, _ clientDrawingContext: UnsafeMutableRawPointer?, _ baselineOriginX: FLOAT,
    _ baselineOriginY: FLOAT, _ measuringMode: DWriteMeasuringMode, _ glyphRunRaw: UnsafeMutableRawPointer?,
    _ glyphRunDescription: UnsafeMutableRawPointer?, _ clientDrawingEffect: UnsafeMutableRawPointer?
) -> HRESULT {
    guard
        let context = glyphLayoutContext(from: clientDrawingContext),
        let glyphRunRaw
    else {
        return HRESULT(bitPattern: 0x8000_4003)
    }

    let glyphRun = glyphRunRaw.assumingMemoryBound(to: DWRITE_GLYPH_RUN.self).pointee
    let glyphCount = Int(glyphRun.glyphCount)
    guard
        glyphCount > 0,
        let glyphIndices = glyphRun.glyphIndices
    else {
        return 0
    }

    let fontFace = NativeFontFaceHandle(glyphRun.fontFace)
    let indices = UnsafeBufferPointer(start: glyphIndices, count: glyphCount)
    let advancesStorage: [FLOAT]
    if let glyphAdvances = glyphRun.glyphAdvances {
        advancesStorage = Array(UnsafeBufferPointer(start: glyphAdvances, count: glyphCount))
    } else {
        advancesStorage = Array(repeating: FLOAT(glyphRun.fontEmSize * 0.5), count: glyphCount)
    }

    let offsetsStorage: [DWRITE_GLYPH_OFFSET]
    if let glyphOffsets = glyphRun.glyphOffsets {
        offsetsStorage = Array(UnsafeBufferPointer(start: glyphOffsets, count: glyphCount))
    } else {
        offsetsStorage = Array(repeating: DWRITE_GLYPH_OFFSET(), count: glyphCount)
    }

    var textPositions = [UInt32?](repeating: nil, count: glyphCount)
    if let glyphRunDescription {
        let description = glyphRunDescription.assumingMemoryBound(to: DWRITE_GLYPH_RUN_DESCRIPTION.self).pointee
        if let clusterMap = description.clusterMap {
            let clusters = UnsafeBufferPointer(start: clusterMap, count: Int(description.stringLength))
            for textOffset in clusters.indices {
                let glyphIndex = Int(clusters[textOffset])
                guard glyphIndex >= 0, glyphIndex < glyphCount, textPositions[glyphIndex] == nil else {
                    continue
                }

                textPositions[glyphIndex] = description.textPosition + UInt32(textOffset)
            }
        } else {
            let count = min(Int(description.stringLength), glyphCount)
            for index in 0..<count {
                textPositions[index] = description.textPosition + UInt32(index)
            }
        }
    }

    let isRightToLeft = glyphRun.bidiLevel % 2 != 0
    var cursorX = Double(baselineOriginX)
    for index in 0..<glyphCount {
        let offset = offsetsStorage[index]
        let advance = Double(advancesStorage[index])
        // DirectWrite's RTL origin is the right edge and positive offsets
        // move left. Atlas glyphs are rasterized individually in LTR space,
        // so capture their left baseline origin, not the run's right edge.
        if isRightToLeft {
            cursorX -= advance
        }
        context.pointee.glyphs.append(
            DirectWriteCapturedGlyph(
                glyphID: UInt32(indices[index]),
                textPosition: textPositions[index],
                origin: Point(
                    x: cursorX + Double(offset.advanceOffset) * (isRightToLeft ? -1 : 1),
                    y: Double(baselineOriginY) - Double(offset.ascenderOffset)
                ),
                advance: advance,
                fontFace: fontFace,
                fontSize: Double(glyphRun.fontEmSize)
            )
        )
        if !isRightToLeft {
            cursorX += advance
        }
    }

    return 0
}
private func directWriteGlyphLayoutDrawUnderline(
    _ rawSelf: UnsafeMutableRawPointer?, _ clientDrawingContext: UnsafeMutableRawPointer?, _ baselineOriginX: FLOAT,
    _ baselineOriginY: FLOAT, _ underlineRaw: UnsafeMutableRawPointer?, _ clientDrawingEffect: UnsafeMutableRawPointer?
) -> HRESULT {
    0
}
private func directWriteGlyphLayoutDrawStrikethrough(
    _ rawSelf: UnsafeMutableRawPointer?, _ clientDrawingContext: UnsafeMutableRawPointer?, _ baselineOriginX: FLOAT,
    _ baselineOriginY: FLOAT, _ strikethroughRaw: UnsafeMutableRawPointer?,
    _ clientDrawingEffect: UnsafeMutableRawPointer?
) -> HRESULT {
    0
}
private func directWriteGlyphLayoutDrawInlineObject(
    _ rawSelf: UnsafeMutableRawPointer?, _ clientDrawingContext: UnsafeMutableRawPointer?, _ originX: FLOAT,
    _ originY: FLOAT, _ inlineObject: UnsafeMutableRawPointer?, _ isSideways: WindowsBool, _ isRightToLeft: WindowsBool,
    _ clientDrawingEffect: UnsafeMutableRawPointer?
) -> HRESULT {
    0
}
private func drawDecoration(
    width: FLOAT, thickness: FLOAT, offset: FLOAT, baselineOriginX: FLOAT, baselineOriginY: FLOAT,
    context: DirectWriteDrawingContext
) {
    guard
        let dc = context.bitmapRenderTarget.pointee.lpVtbl!.pointee.GetMemoryDC(
            UnsafeMutableRawPointer(context.bitmapRenderTarget))
    else {
        return
    }

    let pixelsPerDip = Double(context.pixelsPerDip)
    let left = Int32((Double(baselineOriginX) * pixelsPerDip).rounded(.down))
    let top = Int32(((Double(baselineOriginY) + Double(offset)) * pixelsPerDip).rounded(.down))
    let right = left + max(1, Int32((Double(width) * pixelsPerDip).rounded(.up)))
    let bottom = top + max(1, Int32((Double(thickness) * pixelsPerDip).rounded(.up)))

    var rect = RECT(left: left, top: top, right: right, bottom: bottom)
    guard let brush = CreateSolidBrush(context.textColor) else {
        return
    }
    FillRect(dc, &rect, brush)
    DeleteObject(HGDIOBJ(brush))
}
private enum DirectWriteError: Error {
    case initializationFailed(String)
}
extension TextWeight {
    fileprivate var dwriteWeight: DWriteFontWeight {
        DWriteFontWeight(gdiWeight)
    }
}
extension PixelTextStyle {
    fileprivate var dwriteFontStyle: DWriteFontStyle {
        isItalic ? dwriteFontStyleItalic : dwriteFontStyleNormal
    }

    fileprivate var dwriteTypographyFeatures: [DWriteFontFeature] {
        var features: [DWriteFontFeature] = []
        if !enableKerning {
            features.append(DWriteFontFeature(nameTag: dwriteFontFeatureTagKerning, parameter: 0))
        }
        if monospacedDigits {
            features.append(DWriteFontFeature(nameTag: dwriteFontFeatureTagTabularFigures, parameter: 1))
        }
        if lowercaseSmallCaps {
            features.append(DWriteFontFeature(nameTag: dwriteFontFeatureTagSmallCapitals, parameter: 1))
        }
        if uppercaseSmallCaps {
            features.append(DWriteFontFeature(nameTag: dwriteFontFeatureTagCapitalsToSmallCapitals, parameter: 1))
        }
        return features
    }
}
extension TextFontWidth {
    fileprivate var dwriteFontStretch: DWriteFontStretch {
        switch self {
        case .compressed:
            return dwriteFontStretchExtraCondensed
        case .condensed:
            return dwriteFontStretchCondensed
        case .standard:
            return dwriteFontStretchNormal
        case .expanded:
            return dwriteFontStretchExpanded
        }
    }
}
extension TextHorizontalAlignment {
    fileprivate var dwriteAlignment: DWriteTextAlignment {
        switch self {
        case .leading:
            return dwriteTextAlignmentLeading
        case .center:
            return dwriteTextAlignmentCenter
        case .trailing:
            return dwriteTextAlignmentTrailing
        }
    }
}
extension TextVerticalAlignment {
    fileprivate var dwriteParagraphAlignment: DWriteParagraphAlignment {
        switch self {
        case .top:
            return dwriteParagraphAlignmentNear
        case .center:
            return dwriteParagraphAlignmentCenter
        case .bottom:
            return dwriteParagraphAlignmentFar
        }
    }
}
private func debugLog(_ message: String) {
    #if DEBUG
        print(message)
    #endif
}
private func withWideString<Result>(_ string: String, _ body: (UnsafePointer<WCHAR>) -> Result) -> Result {
    var wide = Array(string.utf16)
    wide.append(0)
    return wide.withUnsafeBufferPointer { body($0.baseAddress!) }
}
