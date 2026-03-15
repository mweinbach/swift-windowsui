import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import WinSDK

@MainActor
enum DirectWriteTextRenderer {
    static func measure(_ text: String, style: PixelTextStyle, scaleFactor: Double, maxWidth: Double? = nil) -> Size? {
        guard let system = DirectWriteSystem.shared else {
            return nil
        }

        return system.measure(text, style: style, scaleFactor: scaleFactor, maxWidth: maxWidth)
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
        let gdiInteropHR = factory.pointee.lpVtbl!.pointee.GetGdiInterop(UnsafeMutableRawPointer(factory), &gdiInteropRaw)
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
        guard !text.isEmpty else {
            return Size(width: style.insets.leading + style.insets.trailing, height: style.insets.top + style.insets.bottom)
        }

        let maxContentWidth = contentWidthLimit(for: maxWidth, style: style)
        guard let measurementFormat = createTextFormat(style: style, wrapping: dwriteWordWrappingNoWrap) else {
            return nil
        }
        defer {
            var releasableFormat: UnsafeMutablePointer<IDWriteTextFormat>? = measurementFormat
            releaseDirectWriteCOM(&releasableFormat)
        }

        let resolvedLayout = resolveTextLayout(
            for: text,
            style: style,
            maxContentWidth: maxContentWidth,
            measureLine: { [weak self] line in
                self?.measureSingleLine(line, format: measurementFormat) ?? 0
            }
        )

        let layoutSize = Size(width: maxContentWidth ?? 4096, height: 4096)
        guard let format = createTextFormat(style: style, wrapping: wrappingMode(for: resolvedLayout, style: style)) else {
            return nil
        }
        defer {
            var releasableFormat: UnsafeMutablePointer<IDWriteTextFormat>? = format
            releaseDirectWriteCOM(&releasableFormat)
        }

        guard let layout = createTextLayout(text: resolvedLayout.text, format: format, size: layoutSize) else {
            return nil
        }
        defer {
            var releasableLayout: UnsafeMutablePointer<IDWriteTextLayout>? = layout
            releaseDirectWriteCOM(&releasableLayout)
        }

        guard let bounds = textBounds(for: layout) else {
            return nil
        }

        let measuredWidth = clampedMeasuredWidth(bounds.width, style: style, maxWidth: maxWidth)
        return snapLogicalTextSize(
            Size(
                width: measuredWidth + style.insets.leading + style.insets.trailing,
                height: bounds.height + style.insets.top + style.insets.bottom
            ),
            scaleFactor: scaleFactor
        )
    }

    func rasterize(_ text: String, in size: Size, style: PixelTextStyle, scaleFactor: Double) -> BitmapSurface? {
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

        let resolvedLayout = resolveTextLayout(
            for: text,
            style: style,
            maxContentWidth: max(0, contentSize.width),
            measureLine: { [weak self] line in
                self?.measureSingleLine(line, format: measurementFormat) ?? 0
            }
        )

        guard let format = createTextFormat(style: style, wrapping: wrappingMode(for: resolvedLayout, style: style)) else {
            return nil
        }
        defer {
            var releasableFormat: UnsafeMutablePointer<IDWriteTextFormat>? = format
            releaseDirectWriteCOM(&releasableFormat)
        }

        guard let layout = createTextLayout(text: resolvedLayout.text, format: format, size: contentSize) else {
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

        _ = bitmapTarget.pointee.lpVtbl!.pointee.SetPixelsPerDip(UnsafeMutableRawPointer(bitmapTarget), FLOAT(scaleFactor))

        guard clearBitmapTarget(bitmapTarget) else {
            return nil
        }

        let bounds = textBounds(for: layout) ?? TextBounds(width: contentSize.width, height: contentSize.height, overhangTop: 0)
        let origin = textOrigin(size: size, style: style, bounds: bounds)

        var drawingContext = DirectWriteDrawingContext(
            bitmapRenderTarget: bitmapTarget,
            renderingParams: renderingParams,
            pixelsPerDip: FLOAT(scaleFactor),
            textColor: COLORREF(0x00FFFFFF)
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

    private func createTextFormat(style: PixelTextStyle, wrapping: DWriteWordWrapping) -> UnsafeMutablePointer<IDWriteTextFormat>? {
        var formatRaw: UnsafeMutableRawPointer?
        let hr = withWideString(style.fontFamily) { familyName in
            withWideString("en-us") { localeName in
                factory.pointee.lpVtbl!.pointee.CreateTextFormat(
                    UnsafeMutableRawPointer(factory),
                    familyName,
                    nil,
                    style.weight.dwriteWeight,
                    dwriteFontStyleNormal,
                    dwriteFontStretchNormal,
                    FLOAT(style.nativeFontPixelSize),
                    localeName,
                    &formatRaw
                )
            }
        }

        guard isSuccess(hr), let formatRaw else {
            return nil
        }

        let format = formatRaw.assumingMemoryBound(to: IDWriteTextFormat.self)
        _ = format.pointee.lpVtbl!.pointee.SetTextAlignment(UnsafeMutableRawPointer(format), style.alignment.dwriteAlignment)
        _ = format.pointee.lpVtbl!.pointee.SetParagraphAlignment(UnsafeMutableRawPointer(format), dwriteParagraphAlignmentNear)
        _ = format.pointee.lpVtbl!.pointee.SetWordWrapping(UnsafeMutableRawPointer(format), wrapping)
        return format
    }

    private func createTextLayout(text: String, format: UnsafeMutablePointer<IDWriteTextFormat>, size: Size) -> UnsafeMutablePointer<IDWriteTextLayout>? {
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

        return layoutRaw.assumingMemoryBound(to: IDWriteTextLayout.self)
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
            layout.pointee.lpVtbl!.pointee.GetOverhangMetrics(UnsafeMutableRawPointer(layout), UnsafeMutableRawPointer($0))
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
            overhangTop: overhangTop
        )
    }

    private func textOrigin(size: Size, style: PixelTextStyle, bounds: TextBounds) -> Point {
        let contentHeight = max(0, size.height - style.insets.top - style.insets.bottom)
        let centeredOffset = max(0, (contentHeight - bounds.height) * 0.5)
        return Point(
            x: style.insets.leading,
            y: style.insets.top + centeredOffset + bounds.overhangTop
        )
    }

    private static func makeRenderingParams(factory: UnsafeMutablePointer<IDWriteFactory>) throws -> UnsafeMutablePointer<IDWriteRenderingParams> {
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

        let defaultHR = factory.pointee.lpVtbl!.pointee.CreateRenderingParams(UnsafeMutableRawPointer(factory), &renderingParamsRaw)
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

private struct DirectWriteDrawingContext {
    var bitmapRenderTarget: UnsafeMutablePointer<IDWriteBitmapRenderTarget>
    var renderingParams: UnsafeMutablePointer<IDWriteRenderingParams>
    var pixelsPerDip: FLOAT
    var textColor: COLORREF
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
private func createTextRenderer() -> UnsafeMutablePointer<IDWriteTextRenderer>? {
    let storage = UnsafeMutablePointer<SwiftTextRendererCOM>.allocate(capacity: 1)
    storage.initialize(to: SwiftTextRendererCOM(interface: IDWriteTextRenderer(lpVtbl: &directWriteTextRendererVTable), refCount: 1))
    return UnsafeMutableRawPointer(storage).assumingMemoryBound(to: IDWriteTextRenderer.self)
}

private func rendererStorage(from rawPointer: UnsafeMutableRawPointer?) -> UnsafeMutablePointer<SwiftTextRendererCOM>? {
    guard let rawPointer else {
        return nil
    }

    return rawPointer.assumingMemoryBound(to: SwiftTextRendererCOM.self)
}

private func drawingContext(from rawPointer: UnsafeMutableRawPointer?) -> UnsafeMutablePointer<DirectWriteDrawingContext>? {
    guard let rawPointer else {
        return nil
    }

    return rawPointer.assumingMemoryBound(to: DirectWriteDrawingContext.self)
}

private func directWriteRendererQueryInterface(_ rawSelf: UnsafeMutableRawPointer?, _ iid: UnsafePointer<GUID>?, _ object: UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> HRESULT {
    guard let rawSelf, let iid else {
        object?.pointee = nil
        return HRESULT(bitPattern: 0x80004003)
    }

    let guid = iid.pointee
    if guidEquals(guid, iidIUnknownDirectWrite) || guidEquals(guid, iidIDWritePixelSnapping) || guidEquals(guid, iidIDWriteTextRenderer) {
        object?.pointee = rawSelf
        _ = directWriteRendererAddRef(rawSelf)
        return 0
    }

    object?.pointee = nil
    return HRESULT(bitPattern: 0x80004002)
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

private func directWriteRendererIsPixelSnappingDisabled(_ rawSelf: UnsafeMutableRawPointer?, _ clientDrawingContext: UnsafeMutableRawPointer?, _ isDisabled: UnsafeMutablePointer<WindowsBool>?) -> HRESULT {
    isDisabled?.pointee = WindowsBool(false)
    return 0
}

private func directWriteRendererGetCurrentTransform(_ rawSelf: UnsafeMutableRawPointer?, _ clientDrawingContext: UnsafeMutableRawPointer?, _ transform: UnsafeMutableRawPointer?) -> HRESULT {
    guard let transform else {
        return HRESULT(bitPattern: 0x80004003)
    }

    transform.assumingMemoryBound(to: DWRITE_MATRIX.self).pointee = DWRITE_MATRIX()
    return 0
}

private func directWriteRendererGetPixelsPerDip(_ rawSelf: UnsafeMutableRawPointer?, _ clientDrawingContext: UnsafeMutableRawPointer?, _ pixelsPerDip: UnsafeMutablePointer<FLOAT>?) -> HRESULT {
    pixelsPerDip?.pointee = drawingContext(from: clientDrawingContext)?.pointee.pixelsPerDip ?? 1.0
    return 0
}

private func directWriteRendererDrawGlyphRun(_ rawSelf: UnsafeMutableRawPointer?, _ clientDrawingContext: UnsafeMutableRawPointer?, _ baselineOriginX: FLOAT, _ baselineOriginY: FLOAT, _ measuringMode: DWriteMeasuringMode, _ glyphRun: UnsafeMutableRawPointer?, _ glyphRunDescription: UnsafeMutableRawPointer?, _ clientDrawingEffect: UnsafeMutableRawPointer?) -> HRESULT {
    guard let context = drawingContext(from: clientDrawingContext) else {
        return HRESULT(bitPattern: 0x80004003)
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

private func directWriteRendererDrawUnderline(_ rawSelf: UnsafeMutableRawPointer?, _ clientDrawingContext: UnsafeMutableRawPointer?, _ baselineOriginX: FLOAT, _ baselineOriginY: FLOAT, _ underlineRaw: UnsafeMutableRawPointer?, _ clientDrawingEffect: UnsafeMutableRawPointer?) -> HRESULT {
    guard let context = drawingContext(from: clientDrawingContext), let underlineRaw else {
        return 0
    }

    let underline = underlineRaw.assumingMemoryBound(to: DWRITE_UNDERLINE.self).pointee
    drawDecoration(width: underline.width, thickness: underline.thickness, offset: underline.offset, baselineOriginX: baselineOriginX, baselineOriginY: baselineOriginY, context: context.pointee)
    return 0
}

private func directWriteRendererDrawStrikethrough(_ rawSelf: UnsafeMutableRawPointer?, _ clientDrawingContext: UnsafeMutableRawPointer?, _ baselineOriginX: FLOAT, _ baselineOriginY: FLOAT, _ strikethroughRaw: UnsafeMutableRawPointer?, _ clientDrawingEffect: UnsafeMutableRawPointer?) -> HRESULT {
    guard let context = drawingContext(from: clientDrawingContext), let strikethroughRaw else {
        return 0
    }

    let strikethrough = strikethroughRaw.assumingMemoryBound(to: DWRITE_STRIKETHROUGH.self).pointee
    drawDecoration(width: strikethrough.width, thickness: strikethrough.thickness, offset: strikethrough.offset, baselineOriginX: baselineOriginX, baselineOriginY: baselineOriginY, context: context.pointee)
    return 0
}

private func directWriteRendererDrawInlineObject(_ rawSelf: UnsafeMutableRawPointer?, _ clientDrawingContext: UnsafeMutableRawPointer?, _ originX: FLOAT, _ originY: FLOAT, _ inlineObject: UnsafeMutableRawPointer?, _ isSideways: WindowsBool, _ isRightToLeft: WindowsBool, _ clientDrawingEffect: UnsafeMutableRawPointer?) -> HRESULT {
    return 0
}

private func drawDecoration(width: FLOAT, thickness: FLOAT, offset: FLOAT, baselineOriginX: FLOAT, baselineOriginY: FLOAT, context: DirectWriteDrawingContext) {
    guard let dc = context.bitmapRenderTarget.pointee.lpVtbl!.pointee.GetMemoryDC(UnsafeMutableRawPointer(context.bitmapRenderTarget)) else {
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

private extension TextWeight {
    var dwriteWeight: DWriteFontWeight {
        DWriteFontWeight(gdiWeight)
    }
}

private extension TextHorizontalAlignment {
    var dwriteAlignment: DWriteTextAlignment {
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

private func withWideString<Result>(_ string: String, _ body: (UnsafePointer<WCHAR>) -> Result) -> Result {
    var wide = Array(string.utf16)
    wide.append(0)
    return wide.withUnsafeBufferPointer { body($0.baseAddress!) }
}
