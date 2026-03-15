import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import WinSDK

@MainActor
enum NativeTextRenderer {
    static func measure(_ text: String, style: PixelTextStyle, scaleFactor: Double, maxWidth: Double? = nil) -> Size? {
        DirectWriteTextRenderer.measure(text, style: style, scaleFactor: scaleFactor, maxWidth: maxWidth)
            ?? GDIRasterTextRenderer.measure(text, style: style, scaleFactor: scaleFactor, maxWidth: maxWidth)
    }

    static func appendCommands(
        for text: String,
        in rect: Rect,
        style: PixelTextStyle,
        scaleFactor: Double,
        clipRect: Rect?,
        into commands: inout [RenderCommand]
    ) -> Bool {
        DirectWriteTextRenderer.appendCommands(
            for: text,
            in: rect,
            style: style,
            scaleFactor: scaleFactor,
            clipRect: clipRect,
            into: &commands
        ) || GDIRasterTextRenderer.appendCommands(
            for: text,
            in: rect,
            style: style,
            scaleFactor: scaleFactor,
            clipRect: clipRect,
            into: &commands
        )
    }
}

@MainActor
enum GDIRasterTextRenderer {
    static func measure(_ text: String, style: PixelTextStyle, scaleFactor: Double, maxWidth: Double? = nil) -> Size? {
        guard !text.isEmpty else {
            return Size(width: style.insets.leading + style.insets.trailing, height: style.insets.top + style.insets.bottom)
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
        let drawFlags = baseDrawTextFlags(
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
        let measuredHeight = Double(measureRect.bottom - measureRect.top) / scaleFactor
        let measuredWidth = clampedMeasuredWidth(
            contentWidth,
            style: style,
            maxWidth: maxWidth
        )
        let width = measuredWidth + style.insets.leading + style.insets.trailing
        let height = measuredHeight + style.insets.top + style.insets.bottom
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
        guard let bitmap = rasterize(text, in: rect.size, style: style, scaleFactor: scaleFactor) else {
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

    private static func rasterize(_ text: String, in size: Size, style: PixelTextStyle, scaleFactor: Double) -> BitmapSurface? {
        let rasterSize = size.scaled(by: scaleFactor)
        let pixelWidth = max(1, Int32(rasterSize.width.rounded(.up)))
        let pixelHeight = max(1, Int32(rasterSize.height.rounded(.up)))
        let bytesPerRow = Int32(pixelWidth * 4)
        let bufferSize = Int(bytesPerRow * pixelHeight)

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

        memset(bits, 0, bufferSize)
        SetBkMode(dc, TRANSPARENT)
        SetTextColor(dc, colorRef(red: 255, green: 255, blue: 255))

        let contentRect = drawRectForInsets(style.insets, width: pixelWidth, height: pixelHeight, scaleFactor: scaleFactor)
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
            pixels: Data(bytes)
        )
    }

    static func tint(pixelBytes: inout [UInt8], style: PixelTextStyle) {
        let red = max(0, min(255, Int(style.color.red * 255)))
        let green = max(0, min(255, Int(style.color.green * 255)))
        let blue = max(0, min(255, Int(style.color.blue * 255)))
        let alphaScale = max(0, min(1, Double(style.color.alpha)))

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
        withWideString(style.fontFamily) { family in
            CreateFontW(
                -Int32((style.nativeFontPixelSize * scaleFactor).rounded()),
                0,
                0,
                0,
                Int32(style.weight.gdiWeight),
                0,
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
        let utf16Count = Int32(text.utf16.count)
        let result = withWideString(text) { wideText in
            GetTextExtentPoint32W(dc, wideText, utf16Count, &measuredSize)
        }

        guard result else {
            return nil
        }

        return Double(measuredSize.cx) / max(scaleFactor, 1)
    }

    private static func drawRectForInsets(_ insets: EdgeInsets, width: Int32, height: Int32, scaleFactor: Double) -> RECT {
        let scaledInsets = EdgeInsets(
            top: insets.top * scaleFactor,
            leading: insets.leading * scaleFactor,
            bottom: insets.bottom * scaleFactor,
            trailing: insets.trailing * scaleFactor
        )

        return RECT(
            left: LONG(Int32(scaledInsets.leading.rounded(.down))),
            top: LONG(Int32(scaledInsets.top.rounded(.down))),
            right: LONG(width - Int32(scaledInsets.trailing.rounded(.down))),
            bottom: LONG(height - Int32(scaledInsets.bottom.rounded(.down)))
        )
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

private func measureRectWidth(maxWidth: Double?, style: PixelTextStyle, scaleFactor: Double) -> Int32 {
    let contentWidth = contentWidthLimit(for: maxWidth, style: style) ?? 4096
    return max(1, Int32((contentWidth * max(scaleFactor, 1)).rounded(.up)))
}

private func clampedMeasuredWidth(_ contentWidth: Double, style: PixelTextStyle, maxWidth: Double?) -> Double {
    if style.lineBreakMode == .clip, let contentLimit = contentWidthLimit(for: maxWidth, style: style) {
        return min(contentWidth, contentLimit)
    }

    return contentWidth
}

extension PixelTextStyle {
    var nativeFontPixelSize: Double {
        max(12, scale * 6 + 8)
    }
}

extension TextWeight {
    var gdiWeight: Int {
        switch self {
        case .regular:
            return 400
        case .semibold:
            return 600
        case .bold:
            return 700
        }
    }
}

private func withWideString<Result>(_ string: String, _ body: (UnsafePointer<WCHAR>) -> Result) -> Result {
    var wide = Array(string.utf16)
    wide.append(0)
    return wide.withUnsafeBufferPointer { body($0.baseAddress!) }
}
