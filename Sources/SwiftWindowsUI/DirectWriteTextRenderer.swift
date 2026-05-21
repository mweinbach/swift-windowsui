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

    static func appendCommands(
        for text: String,
        in rect: Rect,
        style: PixelTextStyle,
        scaleFactor: Double,
        clipRect: Rect?,
        into commands: inout [RenderCommand]
    ) -> Bool {
        guard let system = DirectWriteSystem.shared,
            let bitmap = system.rasterize(text, in: rect.size, style: style, scaleFactor: scaleFactor)
        else {
            return false
        }

        commands.append(
            .drawBitmap(
                DrawBitmapCommand(
                    rect: rect,
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
    guard scaleFactor.isFinite else {
        return nil
    }

    let renderScale = max(scaleFactor, 1.0)
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
    guard fontSize.isFinite, scaleFactor.isFinite, bitmap.width > 0, bitmap.height > 0 else {
        return false
    }

    let maxExtent = max(fontSize * max(scaleFactor, 1.0) * 4.0, 32.0)
    return Double(bitmap.width) <= maxExtent && Double(bitmap.height) <= maxExtent
}
private func roundedUpInt32(_ value: Double, minimum: Int32) -> Int32? {
    guard value.isFinite else {
        return nil
    }

    let rounded = value.rounded(.up)
    guard rounded <= Double(Int32.max), rounded >= Double(Int32.min) else {
        return nil
    }

    return max(minimum, Int32(rounded))
}
@MainActor
private final class DirectWriteSystem {
    static let shared: DirectWriteSystem? = try? DirectWriteSystem()

    private let loader: Win32TextLibraryLoader
    private let module: HMODULE
    private let factory: UnsafeMutablePointer<IDWriteFactory>
    private let gdiInterop: UnsafeMutablePointer<IDWriteGdiInterop>
    private let renderingParams: UnsafeMutablePointer<IDWriteRenderingParams>

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

    func layout(
        _ text: String,
        style: PixelTextStyle,
        scaleFactor: Double,
        maxWidth: Double? = nil,
        resolvesMinimumScaleFactor: Bool = true
    ) -> NativeTextLayoutResult? {
        guard !text.isEmpty else {
            let emptySize = snapLogicalTextSize(
                Size(
                    width: style.insets.leading + style.insets.trailing, height: style.insets.top + style.insets.bottom),
                scaleFactor: scaleFactor
            )
            return NativeTextLayoutResult(
                lines: [], lineSpacing: style.lineSpacing, contentSize: .zero, measuredSize: emptySize)
        }

        guard let measurementFormat = createTextFormat(style: style, wrapping: dwriteWordWrappingNoWrap) else {
            return nil
        }
        defer {
            var releasableFormat: UnsafeMutablePointer<IDWriteTextFormat>? = measurementFormat
            releaseDirectWriteCOM(&releasableFormat)
        }

        let maxContentWidth = contentWidthLimit(for: maxWidth, style: style)
        if resolvesMinimumScaleFactor {
            let effectiveStyle = style.resolvingMinimumScaleFactor(
                for: text,
                maxContentWidth: maxContentWidth,
                measureLine: { [weak self] line in
                    self?.measureSingleLine(line, format: measurementFormat) ?? 0
                }
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
            for: text,
            style: style,
            maxContentWidth: maxContentWidth,
            measureLine: { [weak self] line in
                self?.measureSingleLine(line, format: measurementFormat) ?? 0
            }
        )

        var lines: [NativeTextLineLayout] = []
        lines.reserveCapacity(resolvedLayout.lines.count)
        var contentWidth = 0.0
        var contentHeight = 0.0

        for (index, line) in resolvedLayout.lines.enumerated() {
            guard let lineLayout = layoutLine(line, style: style) else {
                return nil
            }
            lines.append(lineLayout)
            contentWidth = max(contentWidth, lineLayout.width)
            contentHeight += lineLayout.height
            if index < resolvedLayout.lines.count - 1 {
                contentHeight += style.lineSpacing
            }
        }

        if let reservedLineCount = reservedTextLineCount(for: style) {
            let reservedLineHeight = lines.first?.height ?? max(style.nativeFontPixelSize, 1)
            let reservedContentHeight =
                Double(reservedLineCount) * reservedLineHeight + Double(max(reservedLineCount - 1, 0))
                * style.lineSpacing
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
            lineSpacing: style.lineSpacing,
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
        let pixelWidth = max(1, UInt32((logicalSize.width * scaleFactor).rounded(.up)))
        let pixelHeight = max(1, UInt32((logicalSize.height * scaleFactor).rounded(.up)))

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

        let advance = measureSingleLine(text, format: format) ?? bounds.width
        return NativeGlyphBitmap(
            surface: cropped.surface,
            bearingX: Float(-(bounds.overhangLeft * scaleFactor)) + cropped.bearingX,
            bearingY: Float(-(bounds.overhangTop * scaleFactor)) + cropped.bearingY,
            advance: Float(advance * scaleFactor)
        )
    }

    func rasterizeGlyph(_ glyph: NativeTextGlyphLayout, style: PixelTextStyle, scaleFactor: Double)
        -> NativeGlyphBitmap?
    {
        var normalizedGlyph = glyph
        normalizedGlyph.fontSize = max(glyph.fontSize, 1)
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

        if resolvesMinimumScaleFactor {
            let effectiveStyle = style.resolvingMinimumScaleFactor(
                for: text,
                maxContentWidth: max(0, contentSize.width),
                measureLine: { [weak self] line in
                    self?.measureSingleLine(line, format: measurementFormat) ?? 0
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

        let resolvedLayout = resolveTextLayout(
            for: text,
            style: style,
            maxContentWidth: max(0, contentSize.width),
            measureLine: { [weak self] line in
                self?.measureSingleLine(line, format: measurementFormat) ?? 0
            }
        )

        guard let format = createTextFormat(style: style, wrapping: wrappingMode(for: resolvedLayout, style: style))
        else {
            return nil
        }
        defer {
            var releasableFormat: UnsafeMutablePointer<IDWriteTextFormat>? = format
            releaseDirectWriteCOM(&releasableFormat)
        }

        guard let layout = createTextLayout(text: resolvedLayout.text, format: format, size: contentSize, style: style)
        else {
            return nil
        }
        defer {
            var releasableLayout: UnsafeMutablePointer<IDWriteTextLayout>? = layout
            releaseDirectWriteCOM(&releasableLayout)
        }

        let pixelWidth = max(1, UInt32((size.width * scaleFactor).rounded(.up)))
        let pixelHeight = max(1, UInt32((size.height * scaleFactor).rounded(.up)))

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
        let origin = textOrigin(size: size, style: style, bounds: bounds)

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
        return surface
    }

    private func layoutLine(_ text: String, style: PixelTextStyle) -> NativeTextLineLayout? {
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
            let lineHeight = max(lineStyle.nativeFontPixelSize, 1)
            return NativeTextLineLayout(
                text: text,
                width: 0,
                height: lineHeight,
                ascent: lineHeight * 0.8,
                descent: lineHeight * 0.2,
                glyphs: []
            )
        }

        guard let format = createTextFormat(style: lineStyle, wrapping: dwriteWordWrappingNoWrap),
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

        let glyphs = fallbackGlyphLayouts(from: layout, text: text, bounds: bounds, style: lineStyle)
        let resolvedGlyphs =
            glyphs.isEmpty
            ? captureGlyphLayouts(from: layout, text: text, style: lineStyle) ?? []
            : glyphs

        let lineHeight = max(bounds.height, lineStyle.nativeFontPixelSize)
        let ascent = max(lineStyle.nativeFontPixelSize * 0.8, lineHeight * 0.7)
        let descent = max(0, lineHeight - ascent)
        return NativeTextLineLayout(
            text: text,
            width: bounds.width,
            height: lineHeight,
            ascent: ascent,
            descent: descent,
            glyphs: resolvedGlyphs
        )
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

        return NativeGlyphBitmap(
            surface: cropped.surface,
            bearingX: cropped.bearingX,
            bearingY: cropped.bearingY - Float(metrics.baselineYOffset * metrics.renderScale),
            advance: Float(metrics.advance * metrics.renderScale)
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
            return NativeTextGlyphLayout(
                character: resolvedCharacter?.character ?? " ",
                origin: glyph.origin,
                advance: glyph.advance,
                glyphID: glyph.glyphID,
                fontFace: glyph.fontFace,
                fontFamily: style.fontFamily,
                weight: style.weight,
                fontSize: style.nativeFontPixelSize,
                sourceIndex: resolvedCharacter?.index
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
                    sourceIndex: index
                )
            )
        }

        return glyphs
    }

    private static let fallbackFontFamilies = ["Segoe UI", "Arial", "sans-serif"]

    private func createTextFormat(style: PixelTextStyle, wrapping: DWriteWordWrapping) -> UnsafeMutablePointer<
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

        if style.lineSpacing >= 0 {
            _ = format.pointee.lpVtbl!.pointee.SetLineSpacing(
                UnsafeMutableRawPointer(format),
                dwriteLineSpacingMethodUniform,
                FLOAT(style.nativeFontPixelSize + style.lineSpacing),
                FLOAT(style.nativeFontPixelSize * 0.8)
            )
        }

        return format
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

            if style.underline {
                if let fn = layout.pointee.lpVtbl!.pointee.SetUnderline {
                    let proc = unsafeBitCast(
                        fn, to: (@convention(c) (UnsafeMutableRawPointer?, WindowsBool, UINT32, UINT32) -> HRESULT).self
                    )
                    _ = proc(UnsafeMutableRawPointer(layout), WindowsBool(true), rangeStart, rangeLength)
                }
            }

            if style.strikethrough {
                if let fn = layout.pointee.lpVtbl!.pointee.SetStrikethrough {
                    let proc = unsafeBitCast(
                        fn, to: (@convention(c) (UnsafeMutableRawPointer?, WindowsBool, UINT32, UINT32) -> HRESULT).self
                    )
                    _ = proc(UnsafeMutableRawPointer(layout), WindowsBool(true), rangeStart, rangeLength)
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
                to: (@convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UINT32, UINT32) -> HRESULT)
                    .self)
            _ = proc(UnsafeMutableRawPointer(layout), typographyRaw, startPosition, length)
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

            let spanStyle = span.style

            if let fn = layout.pointee.lpVtbl!.pointee.SetFontWeight {
                let proc = unsafeBitCast(
                    fn,
                    to: (@convention(c) (UnsafeMutableRawPointer?, DWriteFontWeight, UINT32, UINT32) -> HRESULT).self)
                _ = proc(UnsafeMutableRawPointer(layout), spanStyle.weight.dwriteWeight, startPosition, length)
            }

            if let fn = layout.pointee.lpVtbl!.pointee.SetFontStyle {
                let proc = unsafeBitCast(
                    fn, to: (@convention(c) (UnsafeMutableRawPointer?, DWriteFontStyle, UINT32, UINT32) -> HRESULT).self
                )
                _ = proc(UnsafeMutableRawPointer(layout), spanStyle.dwriteFontStyle, startPosition, length)
            }

            if let fn = layout.pointee.lpVtbl!.pointee.SetFontSize {
                let proc = unsafeBitCast(
                    fn, to: (@convention(c) (UnsafeMutableRawPointer?, FLOAT, UINT32, UINT32) -> HRESULT).self)
                _ = proc(UnsafeMutableRawPointer(layout), FLOAT(spanStyle.nativeFontPixelSize), startPosition, length)
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
                        fn, to: (@convention(c) (UnsafeMutableRawPointer?, WindowsBool, UINT32, UINT32) -> HRESULT).self
                    )
                    _ = proc(UnsafeMutableRawPointer(layout), WindowsBool(true), startPosition, length)
                }
            }

            if spanStyle.strikethrough {
                if let fn = layout.pointee.lpVtbl!.pointee.SetStrikethrough {
                    let proc = unsafeBitCast(
                        fn, to: (@convention(c) (UnsafeMutableRawPointer?, WindowsBool, UINT32, UINT32) -> HRESULT).self
                    )
                    _ = proc(UnsafeMutableRawPointer(layout), WindowsBool(true), startPosition, length)
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

    private func textOrigin(size: Size, style: PixelTextStyle, bounds: TextBounds) -> Point {
        let contentHeight = max(0, size.height - style.insets.top - style.insets.bottom)
        let reservedHeight: Double
        if let reservedLineCount = reservedTextLineCount(for: style) {
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
        memset(bits, 0, Int(bytesPerRow * height))
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
        let data = Data(bytes: bits, count: Int(bytesPerRow * height))

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
                pixels: Data(cropped)
            ),
            bearingX: Float(minX) - Float(paddingPixels),
            bearingY: Float(minY) - Float(paddingPixels)
        )
    }

    private func measureSingleLine(_ text: String, format: UnsafeMutablePointer<IDWriteTextFormat>) -> Double? {
        guard !text.isEmpty else {
            return 0
        }

        guard let layout = createTextLayout(text: text, format: format, size: Size(width: 4096, height: 4096)) else {
            return nil
        }
        defer {
            var releasableLayout: UnsafeMutablePointer<IDWriteTextLayout>? = layout
            releaseDirectWriteCOM(&releasableLayout)
        }

        return textBounds(for: layout)?.width
    }

    private func wrappingMode(for layout: ResolvedTextLayout, style: PixelTextStyle) -> DWriteWordWrapping {
        if layout.lines.count > 1 || style.lineBreakMode == .wrap {
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
private struct DirectWriteDrawingContext {
    var bitmapRenderTarget: UnsafeMutablePointer<IDWriteBitmapRenderTarget>
    var renderingParams: UnsafeMutablePointer<IDWriteRenderingParams>
    var pixelsPerDip: FLOAT
    var textColor: COLORREF
}
private struct DirectWriteGlyphLayoutContext {
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
    IsPixelSnappingDisabled: directWriteRendererIsPixelSnappingDisabled,
    GetCurrentTransform: directWriteRendererGetCurrentTransform,
    GetPixelsPerDip: directWriteRendererGetPixelsPerDip,
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
private func rendererStorage(from rawPointer: UnsafeMutableRawPointer?) -> UnsafeMutablePointer<SwiftTextRendererCOM>? {
    guard let rawPointer else {
        return nil
    }

    return rawPointer.assumingMemoryBound(to: SwiftTextRendererCOM.self)
}
private func drawingContext(from rawPointer: UnsafeMutableRawPointer?) -> UnsafeMutablePointer<
    DirectWriteDrawingContext
>? {
    guard let rawPointer else {
        return nil
    }

    return rawPointer.assumingMemoryBound(to: DirectWriteDrawingContext.self)
}
private func glyphLayoutContext(from rawPointer: UnsafeMutableRawPointer?) -> UnsafeMutablePointer<
    DirectWriteGlyphLayoutContext
>? {
    guard let rawPointer else {
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
    pixelsPerDip?.pointee = drawingContext(from: clientDrawingContext)?.pointee.pixelsPerDip ?? 1.0
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

    var cursorX = Double(baselineOriginX)
    for index in 0..<glyphCount {
        let offset = offsetsStorage[index]
        context.pointee.glyphs.append(
            DirectWriteCapturedGlyph(
                glyphID: UInt32(indices[index]),
                textPosition: textPositions[index],
                origin: Point(
                    x: cursorX + Double(offset.advanceOffset),
                    y: Double(baselineOriginY) - Double(offset.ascenderOffset)
                ),
                advance: Double(advancesStorage[index]),
                fontFace: fontFace,
                fontSize: Double(glyphRun.fontEmSize)
            )
        )
        cursorX += Double(advancesStorage[index])
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
