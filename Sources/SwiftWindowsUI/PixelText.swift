import Foundation

import SwiftWindowsCore

import SwiftWindowsGraphics

public enum TextHorizontalAlignment: Sendable {
    case leading
    case center
    case trailing
}
public enum TextVerticalAlignment: Sendable {
    case top
    case center
    case bottom
}
public enum TextWeight: Sendable {
    case regular
    case semibold
    case bold
}
public enum TextFontWidth: Sendable, Equatable {
    case compressed
    case condensed
    case standard
    case expanded
}
public enum TextLineBreakMode: Sendable {
    case clip
    case truncateTail
    case truncateHead
    case truncateMiddle
    case wrap
}
public enum TextDecorationPattern: Sendable, Equatable, Hashable {
    case solid
    case dot
    case dash
    case dashDot
    case dashDotDot
}
public struct TextSpan: Sendable, Equatable {
    public var text: String
    public var style: PixelTextStyle
    public var range: Range<String.Index>?

    public init(text: String, style: PixelTextStyle, range: Range<String.Index>? = nil) {
        self.text = text
        self.style = style
        self.range = range
    }
}
public struct PixelTextStyle: Sendable, Equatable {
    public var color: Color
    public var scale: Double
    public var alignment: TextHorizontalAlignment
    public var verticalAlignment: TextVerticalAlignment
    public var letterSpacing: Double
    public var lineSpacing: Double
    public var insets: EdgeInsets
    public var fontFamily: String
    public var nativeFontSize: Double?
    public var weight: TextWeight
    public var fontWidth: TextFontWidth
    public var isItalic: Bool
    public var monospacedDigits: Bool
    public var lowercaseSmallCaps: Bool
    public var uppercaseSmallCaps: Bool
    public var lineBreakMode: TextLineBreakMode
    public var maximumNumberOfLines: Int?
    public var minimumNumberOfLines: Int?
    public var minimumScaleFactor: Double
    public var reservesLineLimitSpace: Bool
    public var underline: Bool
    public var underlinePattern: TextDecorationPattern
    public var underlineColor: Color?
    public var strikethrough: Bool
    public var strikethroughPattern: TextDecorationPattern
    public var strikethroughColor: Color?
    public var enableKerning: Bool
    public var spans: [TextSpan]?

    public init(
        color: Color,
        scale: Double = 2,
        alignment: TextHorizontalAlignment = .center,
        verticalAlignment: TextVerticalAlignment = .center,
        letterSpacing: Double = 1,
        lineSpacing: Double = 2,
        insets: EdgeInsets = .zero,
        fontFamily: String = "Segoe UI",
        nativeFontSize: Double? = nil,
        weight: TextWeight = .regular,
        fontWidth: TextFontWidth = .standard,
        isItalic: Bool = false,
        monospacedDigits: Bool = false,
        lowercaseSmallCaps: Bool = false,
        uppercaseSmallCaps: Bool = false,
        lineBreakMode: TextLineBreakMode = .truncateTail,
        maximumNumberOfLines: Int? = nil,
        minimumNumberOfLines: Int? = nil,
        minimumScaleFactor: Double = 1,
        reservesLineLimitSpace: Bool = false,
        underline: Bool = false,
        underlinePattern: TextDecorationPattern = .solid,
        underlineColor: Color? = nil,
        strikethrough: Bool = false,
        strikethroughPattern: TextDecorationPattern = .solid,
        strikethroughColor: Color? = nil,
        enableKerning: Bool = true,
        spans: [TextSpan]? = nil
    ) {
        self.color = color
        self.scale = scale
        self.alignment = alignment
        self.verticalAlignment = verticalAlignment
        self.letterSpacing = letterSpacing
        self.lineSpacing = lineSpacing
        self.insets = insets
        self.fontFamily = fontFamily
        self.nativeFontSize = nativeFontSize
        self.weight = weight
        self.fontWidth = fontWidth
        self.isItalic = isItalic
        self.monospacedDigits = monospacedDigits
        self.lowercaseSmallCaps = lowercaseSmallCaps
        self.uppercaseSmallCaps = uppercaseSmallCaps
        self.lineBreakMode = lineBreakMode
        self.maximumNumberOfLines = maximumNumberOfLines
        self.minimumNumberOfLines = minimumNumberOfLines
        self.minimumScaleFactor = min(max(minimumScaleFactor, 0), 1)
        self.reservesLineLimitSpace = reservesLineLimitSpace
        self.underline = underline
        self.underlinePattern = underline ? underlinePattern : .solid
        self.underlineColor = underline ? underlineColor : nil
        self.strikethrough = strikethrough
        self.strikethroughPattern = strikethrough ? strikethroughPattern : .solid
        self.strikethroughColor = strikethrough ? strikethroughColor : nil
        self.enableKerning = enableKerning
        self.spans = spans
    }
}
extension PixelTextStyle {
    var hasTextDecorations: Bool {
        underline || strikethrough
    }

    var withoutTextDecorations: PixelTextStyle {
        var copy = self
        copy.underline = false
        copy.underlinePattern = .solid
        copy.underlineColor = nil
        copy.strikethrough = false
        copy.strikethroughPattern = .solid
        copy.strikethroughColor = nil
        copy.spans = copy.spans?.map { span in
            var span = span
            span.style = span.style.withoutTextDecorations
            return span
        }
        return copy
    }

    public func multipliedOpacity(by opacity: Float) -> PixelTextStyle {
        guard opacity != 1 else {
            return self
        }

        var copy = self
        copy.color = copy.color.multipliedAlpha(by: opacity)
        copy.underlineColor = copy.underlineColor?.multipliedAlpha(by: opacity)
        copy.strikethroughColor = copy.strikethroughColor?.multipliedAlpha(by: opacity)
        copy.spans = copy.spans?.map { span in
            var span = span
            span.style = span.style.multipliedOpacity(by: opacity)
            return span
        }
        return copy
    }

    func scaledForMinimumScaleFactor(_ factor: Double) -> PixelTextStyle {
        let clampedFactor = min(max(factor, minimumScaleFactor), 1)
        return scaledTextMetrics(by: clampedFactor)
    }

    private func scaledTextMetrics(by factor: Double) -> PixelTextStyle {
        guard factor < 1 else {
            return self
        }

        var copy = self
        copy.scale = max(0.01, scale * factor)
        copy.nativeFontSize = max(1, nativeFontPixelSize * factor)
        copy.letterSpacing = letterSpacing * factor
        copy.lineSpacing = lineSpacing * factor
        copy.minimumScaleFactor = 1
        copy.spans = spans?.map { span in
            var scaledSpan = span
            scaledSpan.style = span.style.scaledTextMetrics(by: factor)
            return scaledSpan
        }
        return copy
    }

    func resolvingMinimumScaleFactor(
        for text: String,
        maxContentWidth: Double?,
        measureLine: (String) -> Double
    ) -> PixelTextStyle {
        let factor = minimumTextScaleFactor(
            for: text,
            style: self,
            maxContentWidth: maxContentWidth,
            measureLine: measureLine
        )
        return scaledForMinimumScaleFactor(factor)
    }
}
enum PixelFont {
    private static func textScale(for style: PixelTextStyle) -> Double {
        max(style.scale, 0.01)
    }

    static func measure(_ text: String, style: PixelTextStyle, maxWidth: Double? = nil) -> Size {
        let maxContentWidth = resolvedContentWidth(for: maxWidth, style: style)
        let effectiveStyle = style.resolvingMinimumScaleFactor(
            for: text,
            maxContentWidth: maxContentWidth,
            measureLine: { line in rawLineWidth(line, letterSpacing: style.letterSpacing) * textScale(for: style) }
        )
        let scale = textScale(for: effectiveStyle)
        let layout = resolveTextLayout(
            for: text,
            style: effectiveStyle,
            maxContentWidth: maxContentWidth,
            measureLine: { line in rawLineWidth(line, letterSpacing: effectiveStyle.letterSpacing) * scale }
        )
        let contentWidth = measuredContentWidth(
            for: layout.lines,
            style: effectiveStyle,
            scale: scale,
            maxContentWidth: maxContentWidth
        )
        let width = contentWidth + effectiveStyle.insets.leading + effectiveStyle.insets.trailing
        let lineCount = max(layout.lines.count, 1)
        let reservedLineCount = reservedTextLineCount(for: effectiveStyle)
        let measuredLineCount = max(lineCount, reservedLineCount ?? 0)
        let height =
            pixelTextContentHeight(
                lineCount: measuredLineCount,
                style: effectiveStyle,
                scale: scale
            ) + effectiveStyle.insets.top + effectiveStyle.insets.bottom

        return Size(width: width, height: height)
    }

    static func appendCommands(
        for text: String,
        in rect: Rect,
        style: PixelTextStyle,
        clipRect: Rect?,
        into commands: inout [RenderCommand]
    ) {
        guard !text.isEmpty, style.color.alpha > 0 else {
            return
        }

        let contentRect = rect.inset(by: style.insets)
        let effectiveStyle = style.resolvingMinimumScaleFactor(
            for: text,
            maxContentWidth: max(0, contentRect.size.width),
            measureLine: { line in rawLineWidth(line, letterSpacing: style.letterSpacing) * textScale(for: style) }
        )
        let scale = textScale(for: effectiveStyle)
        let layout = resolveTextLayout(
            for: text,
            style: effectiveStyle,
            maxContentWidth: max(0, contentRect.size.width),
            measureLine: { line in rawLineWidth(line, letterSpacing: effectiveStyle.letterSpacing) * scale }
        )
        let lines = layout.lines
        let reservedLineCount = reservedTextLineCount(for: effectiveStyle)
        let verticalLineCount = max(max(lines.count, 1), reservedLineCount ?? 0)
        let totalTextHeight = pixelTextContentHeight(
            lineCount: verticalLineCount,
            style: effectiveStyle,
            scale: scale
        )
        var y = contentRect.origin.y + max(0, (contentRect.size.height - totalTextHeight) * 0.5)

        for line in lines {
            let lineWidth = rawLineWidth(String(line), letterSpacing: effectiveStyle.letterSpacing) * scale
            let x: Double
            switch effectiveStyle.alignment {
            case .leading:
                x = contentRect.origin.x
            case .center:
                x = contentRect.origin.x + max(0, (contentRect.size.width - lineWidth) * 0.5)
            case .trailing:
                x = contentRect.maxX - lineWidth
            }

            appendLineCommands(
                for: String(line),
                at: Point(x: x, y: y),
                scale: scale,
                letterSpacing: effectiveStyle.letterSpacing,
                color: effectiveStyle.color,
                clipRect: clipRect,
                into: &commands
            )

            y += Double(PixelFontAtlas.glyphHeight) * scale + effectiveStyle.lineSpacing * scale
        }

        TextDecorationCommandBuilder.appendCommands(
            for: text,
            in: rect,
            style: effectiveStyle,
            scaleFactor: 1,
            clipRect: clipRect,
            nativeLayout: nil,
            into: &commands
        )
    }

    static func appendGlyphPrimitives(
        for text: String,
        in rect: Rect,
        style: PixelTextStyle,
        clipRect: Rect?,
        into glyphs: inout [GlyphPrimitive]
    ) {
        guard !text.isEmpty, style.color.alpha > 0 else {
            return
        }

        let contentRect = rect.inset(by: style.insets)
        let effectiveStyle = style.resolvingMinimumScaleFactor(
            for: text,
            maxContentWidth: max(0, contentRect.size.width),
            measureLine: { line in rawLineWidth(line, letterSpacing: style.letterSpacing) * textScale(for: style) }
        )
        let scale = textScale(for: effectiveStyle)
        let layout = resolveTextLayout(
            for: text,
            style: effectiveStyle,
            maxContentWidth: max(0, contentRect.size.width),
            measureLine: { line in rawLineWidth(line, letterSpacing: effectiveStyle.letterSpacing) * scale }
        )
        let lines = layout.lines
        let reservedLineCount = reservedTextLineCount(for: effectiveStyle)
        let verticalLineCount = max(max(lines.count, 1), reservedLineCount ?? 0)
        let totalTextHeight = pixelTextContentHeight(
            lineCount: verticalLineCount,
            style: effectiveStyle,
            scale: scale
        )
        var y = contentRect.origin.y + max(0, (contentRect.size.height - totalTextHeight) * 0.5)

        for line in lines {
            let lineWidth = rawLineWidth(String(line), letterSpacing: effectiveStyle.letterSpacing) * scale
            let x: Double
            switch effectiveStyle.alignment {
            case .leading:
                x = contentRect.origin.x
            case .center:
                x = contentRect.origin.x + max(0, (contentRect.size.width - lineWidth) * 0.5)
            case .trailing:
                x = contentRect.maxX - lineWidth
            }

            appendLineGlyphPrimitives(
                for: String(line),
                at: Point(x: x, y: y),
                scale: scale,
                letterSpacing: effectiveStyle.letterSpacing,
                color: effectiveStyle.color,
                clipRect: clipRect,
                into: &glyphs
            )

            y += Double(PixelFontAtlas.glyphHeight) * scale + effectiveStyle.lineSpacing * scale
        }
    }

    private static func appendLineCommands(
        for line: String,
        at origin: Point,
        scale: Double,
        letterSpacing: Double,
        color: Color,
        clipRect: Rect?,
        into commands: inout [RenderCommand]
    ) {
        var cursorX = origin.x

        for character in line.uppercased() {
            let glyph = glyphRows(for: character)

            for (rowIndex, row) in glyph.enumerated() {
                var runStart: Int?

                for (columnIndex, bit) in row.enumerated() {
                    if bit == "1" {
                        if runStart == nil {
                            runStart = columnIndex
                        }
                    } else if let activeRunStart = runStart {
                        appendRun(
                            startColumn: activeRunStart,
                            endColumn: columnIndex,
                            rowIndex: rowIndex,
                            origin: Point(x: cursorX, y: origin.y),
                            scale: scale,
                            color: color,
                            clipRect: clipRect,
                            into: &commands
                        )
                        runStart = nil
                    }
                }

                if let runStart {
                    appendRun(
                        startColumn: runStart,
                        endColumn: PixelFontAtlas.glyphWidth,
                        rowIndex: rowIndex,
                        origin: Point(x: cursorX, y: origin.y),
                        scale: scale,
                        color: color,
                        clipRect: clipRect,
                        into: &commands
                    )
                }
            }

            cursorX += (Double(PixelFontAtlas.glyphWidth) + letterSpacing) * scale
        }
    }

    private static func appendLineGlyphPrimitives(
        for line: String,
        at origin: Point,
        scale: Double,
        letterSpacing: Double,
        color: Color,
        clipRect: Rect?,
        into glyphs: inout [GlyphPrimitive]
    ) {
        var cursorX = origin.x
        let atlas = PixelFontAtlas.shared
        let clip = clipRect.map {
            (
                x: Float($0.origin.x),
                y: Float($0.origin.y),
                width: Float($0.size.width),
                height: Float($0.size.height)
            )
        }

        for character in line.uppercased() {
            let glyph = PixelFontAtlas.glyph(for: character)
            let destinationRect = Rect(
                x: cursorX,
                y: origin.y,
                width: Double(glyph.width) * scale,
                height: Double(glyph.height) * scale
            )

            if clipRect == nil || clipRect?.intersected(with: destinationRect) != nil {
                let uv = glyph.uvRect(atlasWidth: atlas.surface.width, atlasHeight: atlas.surface.height)
                glyphs.append(
                    GlyphPrimitive(
                        screenX: Float(destinationRect.origin.x),
                        screenY: Float(destinationRect.origin.y),
                        screenW: Float(destinationRect.size.width),
                        screenH: Float(destinationRect.size.height),
                        atlasU0: uv.u0,
                        atlasV0: uv.v0,
                        atlasU1: uv.u1,
                        atlasV1: uv.v1,
                        colorR: color.red,
                        colorG: color.green,
                        colorB: color.blue,
                        colorA: color.alpha,
                        clipX: clip?.x ?? 0,
                        clipY: clip?.y ?? 0,
                        clipWidth: clip?.width ?? 0,
                        clipHeight: clip?.height ?? 0
                    )
                )
            }

            cursorX += (Double(PixelFontAtlas.glyphWidth) + letterSpacing) * scale
        }
    }

    private static func appendRun(
        startColumn: Int,
        endColumn: Int,
        rowIndex: Int,
        origin: Point,
        scale: Double,
        color: Color,
        clipRect: Rect?,
        into commands: inout [RenderCommand]
    ) {
        let rect = Rect(
            x: origin.x + Double(startColumn) * scale,
            y: origin.y + Double(rowIndex) * scale,
            width: Double(endColumn - startColumn) * scale,
            height: scale
        )

        commands.append(
            .fillRect(
                FillRectCommand(
                    rect: rect,
                    color: color,
                    cornerRadius: 0,
                    clipRect: clipRect
                )
            )
        )
    }

    static func rawLineWidth(_ text: String, letterSpacing: Double) -> Double {
        guard !text.isEmpty else {
            return 0
        }

        let count = Double(text.count)
        return count * Double(PixelFontAtlas.glyphWidth) + Double(max(text.count - 1, 0)) * letterSpacing
    }

    static var glyphWidth: Int { PixelFontAtlas.glyphWidth }
    static var glyphHeight: Int { PixelFontAtlas.glyphHeight }

    static func glyphRows(for character: Character) -> [String] {
        PixelFontAtlas.pattern(for: character)
    }
}
enum TextDecorationCommandBuilder {
    static func appendCommands(
        for text: String,
        in rect: Rect,
        style: PixelTextStyle,
        scaleFactor: Double,
        clipRect: Rect?,
        nativeLayout: NativeTextLayoutResult?,
        into commands: inout [RenderCommand]
    ) {
        guard !text.isEmpty, style.hasTextDecorations else {
            return
        }

        if let nativeLayout {
            appendNativeDecorationCommands(
                in: rect,
                style: style,
                scaleFactor: scaleFactor,
                clipRect: clipRect,
                layout: nativeLayout,
                into: &commands
            )
            return
        }

        appendPixelDecorationCommands(
            for: text,
            in: rect,
            style: style,
            scaleFactor: scaleFactor,
            clipRect: clipRect,
            into: &commands
        )
    }

    private static func appendNativeDecorationCommands(
        in rect: Rect,
        style: PixelTextStyle,
        scaleFactor: Double,
        clipRect: Rect?,
        layout: NativeTextLayoutResult,
        into commands: inout [RenderCommand]
    ) {
        let contentRect = rect.inset(by: style.insets)
        let baseY: Double
        switch style.verticalAlignment {
        case .top:
            baseY = contentRect.origin.y
        case .center:
            baseY = contentRect.origin.y + max(0, (contentRect.size.height - layout.contentSize.height) * 0.5)
        case .bottom:
            baseY = contentRect.maxY - layout.contentSize.height
        }

        var lineOriginY = baseY
        for line in layout.lines {
            let startX: Double
            switch style.alignment {
            case .leading:
                startX = contentRect.origin.x
            case .center:
                startX = contentRect.origin.x + max(0, (contentRect.size.width - line.width) * 0.5)
            case .trailing:
                startX = contentRect.maxX - line.width
            }

            appendLineDecorationCommands(
                lineRect: Rect(x: startX, y: lineOriginY, width: line.width, height: line.height),
                style: style,
                scaleFactor: scaleFactor,
                clipRect: clipRect,
                into: &commands
            )
            lineOriginY += line.height + layout.lineSpacing
        }
    }

    private static func appendPixelDecorationCommands(
        for text: String,
        in rect: Rect,
        style: PixelTextStyle,
        scaleFactor: Double,
        clipRect: Rect?,
        into commands: inout [RenderCommand]
    ) {
        let contentRect = rect.inset(by: style.insets)
        guard contentRect.size.width > 0, contentRect.size.height > 0 else {
            return
        }

        let maxContentWidth = max(0, contentRect.size.width)
        let effectiveStyle = style.resolvingMinimumScaleFactor(
            for: text,
            maxContentWidth: maxContentWidth,
            measureLine: { line in
                PixelFont.rawLineWidth(line, letterSpacing: style.letterSpacing) * max(style.scale, 0.01)
            }
        )
        let scale = max(effectiveStyle.scale, 0.01)
        let layout = resolveTextLayout(
            for: text,
            style: effectiveStyle,
            maxContentWidth: maxContentWidth,
            measureLine: { line in PixelFont.rawLineWidth(line, letterSpacing: effectiveStyle.letterSpacing) * scale }
        )
        let reservedLineCount = reservedTextLineCount(for: effectiveStyle)
        let verticalLineCount = max(max(layout.lines.count, 1), reservedLineCount ?? 0)
        let totalTextHeight = pixelTextContentHeight(
            lineCount: verticalLineCount,
            style: effectiveStyle,
            scale: scale
        )

        var y = contentRect.origin.y + max(0, (contentRect.size.height - totalTextHeight) * 0.5)
        for line in layout.lines {
            let lineWidth = PixelFont.rawLineWidth(line, letterSpacing: effectiveStyle.letterSpacing) * scale
            let x: Double
            switch effectiveStyle.alignment {
            case .leading:
                x = contentRect.origin.x
            case .center:
                x = contentRect.origin.x + max(0, (contentRect.size.width - lineWidth) * 0.5)
            case .trailing:
                x = contentRect.maxX - lineWidth
            }

            appendLineDecorationCommands(
                lineRect: Rect(
                    x: x,
                    y: y,
                    width: lineWidth,
                    height: Double(PixelFontAtlas.glyphHeight) * scale
                ),
                style: effectiveStyle,
                scaleFactor: scaleFactor,
                clipRect: clipRect,
                into: &commands
            )
            y += Double(PixelFontAtlas.glyphHeight) * scale + effectiveStyle.lineSpacing * scale
        }
    }

    private static func appendLineDecorationCommands(
        lineRect: Rect,
        style: PixelTextStyle,
        scaleFactor: Double,
        clipRect: Rect?,
        into commands: inout [RenderCommand]
    ) {
        guard lineRect.size.width > 0, lineRect.size.height > 0 else {
            return
        }

        let thickness = max(1 / max(scaleFactor, 1), min(lineRect.size.height, max(1, lineRect.size.height * 0.08)))
        if style.underline {
            appendDecorationCommand(
                lineRect: lineRect,
                y: min(lineRect.maxY - thickness, lineRect.origin.y + lineRect.size.height * 0.86),
                thickness: thickness,
                color: style.underlineColor ?? style.color,
                pattern: style.underlinePattern,
                clipRect: clipRect,
                into: &commands
            )
        }

        if style.strikethrough {
            appendDecorationCommand(
                lineRect: lineRect,
                y: lineRect.origin.y + max(0, (lineRect.size.height - thickness) * 0.52),
                thickness: thickness,
                color: style.strikethroughColor ?? style.color,
                pattern: style.strikethroughPattern,
                clipRect: clipRect,
                into: &commands
            )
        }
    }

    private static func appendDecorationCommand(
        lineRect: Rect,
        y: Double,
        thickness: Double,
        color: Color,
        pattern: TextDecorationPattern,
        clipRect: Rect?,
        into commands: inout [RenderCommand]
    ) {
        guard color.alpha > 0 else {
            return
        }

        for rect in decorationSegments(lineRect: lineRect, y: y, thickness: thickness, pattern: pattern) {
            if let clipRect, clipRect.intersected(with: rect) == nil {
                continue
            }

            commands.append(
                .fillRect(
                    FillRectCommand(
                        rect: rect,
                        color: color,
                        cornerRadius: 0,
                        clipRect: clipRect
                    )
                )
            )
        }
    }

    private static func decorationSegments(
        lineRect: Rect,
        y: Double,
        thickness: Double,
        pattern: TextDecorationPattern
    ) -> [Rect] {
        guard lineRect.size.width > 0 else {
            return []
        }
        guard pattern != .solid else {
            return [Rect(x: lineRect.origin.x, y: y, width: lineRect.size.width, height: thickness)]
        }

        let unit = max(thickness, 1)
        let sequence: [(draw: Bool, length: Double)] = decorationSequence(for: pattern, unit: unit)
        var segments: [Rect] = []
        var x = lineRect.origin.x
        var index = 0
        while x < lineRect.maxX {
            let item = sequence[index % sequence.count]
            let width = min(item.length, lineRect.maxX - x)
            if item.draw, width > 0 {
                segments.append(Rect(x: x, y: y, width: width, height: thickness))
            }
            x += max(width, 0.01)
            index += 1
        }
        return segments
    }

    private static func decorationSequence(for pattern: TextDecorationPattern, unit: Double) -> [(
        draw: Bool, length: Double
    )] {
        switch pattern {
        case .solid:
            return [(true, Double.greatestFiniteMagnitude)]
        case .dot:
            return [(true, unit), (false, unit)]
        case .dash:
            return [(true, unit * 4), (false, unit * 2)]
        case .dashDot:
            return [(true, unit * 4), (false, unit * 1.5), (true, unit), (false, unit * 1.5)]
        case .dashDotDot:
            return [
                (true, unit * 4),
                (false, unit * 1.5),
                (true, unit),
                (false, unit * 1.5),
                (true, unit),
                (false, unit * 1.5),
            ]
        }
    }
}
func reservedTextLineCount(for style: PixelTextStyle) -> Int? {
    let minimumNumberOfLines = style.minimumNumberOfLines.flatMap { $0 > 0 ? $0 : nil }
    let reservedMaximumNumberOfLines =
        style.reservesLineLimitSpace
        ? style.maximumNumberOfLines.flatMap { $0 > 0 ? $0 : nil }
        : nil

    switch (minimumNumberOfLines, reservedMaximumNumberOfLines) {
    case (.some(let minimum), .some(let maximum)):
        return max(minimum, maximum)
    case (.some(let minimum), .none):
        return minimum
    case (.none, .some(let maximum)):
        return maximum
    case (.none, .none):
        return nil
    }
}
func pixelTextContentHeight(lineCount: Int, style: PixelTextStyle, scale: Double) -> Double {
    (Double(max(lineCount, 1) * PixelFontAtlas.glyphHeight) + Double(max(lineCount - 1, 0)) * style.lineSpacing) * scale
}
func minimumTextScaleFactor(
    for text: String,
    style: PixelTextStyle,
    maxContentWidth: Double?,
    measureLine: (String) -> Double
) -> Double {
    guard
        style.minimumScaleFactor < 1,
        let maxContentWidth,
        maxContentWidth.isFinite,
        maxContentWidth > 0
    else {
        return 1
    }

    let widestLine =
        normalizedTextLines(from: text)
        .map(measureLine)
        .filter(\.isFinite)
        .max() ?? 0
    guard widestLine > maxContentWidth, widestLine > 0 else {
        return 1
    }

    return min(1, max(style.minimumScaleFactor, maxContentWidth / widestLine))
}
struct ResolvedTextLayout: Equatable, Sendable {
    var lines: [String]

    var text: String {
        lines.joined(separator: "\n")
    }
}
func resolveTextLayout(
    for text: String,
    style: PixelTextStyle,
    maxContentWidth: Double?,
    measureLine: (String) -> Double
) -> ResolvedTextLayout {
    let sourceLines = normalizedTextLines(from: text)
    let fittedLines: [String]

    switch style.lineBreakMode {
    case .clip:
        fittedLines = sourceLines
    case .truncateTail:
        guard let maxContentWidth, maxContentWidth.isFinite else {
            fittedLines = sourceLines
            break
        }
        fittedLines = sourceLines.map { truncateLine($0, toFit: maxContentWidth, measureLine: measureLine) }
    case .truncateHead:
        guard let maxContentWidth, maxContentWidth.isFinite else {
            fittedLines = sourceLines
            break
        }
        fittedLines = sourceLines.map { truncateLineHead($0, toFit: maxContentWidth, measureLine: measureLine) }
    case .truncateMiddle:
        guard let maxContentWidth, maxContentWidth.isFinite else {
            fittedLines = sourceLines
            break
        }
        fittedLines = sourceLines.map { truncateLineMiddle($0, toFit: maxContentWidth, measureLine: measureLine) }
    case .wrap:
        guard let maxContentWidth, maxContentWidth.isFinite else {
            fittedLines = sourceLines
            break
        }
        fittedLines = sourceLines.flatMap { wrapLine($0, maxWidth: maxContentWidth, measureLine: measureLine) }
    }

    return ResolvedTextLayout(
        lines: applyLineLimit(
            to: fittedLines,
            style: style,
            maxContentWidth: maxContentWidth,
            measureLine: measureLine
        )
    )
}
func normalizedTextLines(from text: String) -> [String] {
    let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    return normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
}
private func applyLineLimit(
    to lines: [String],
    style: PixelTextStyle,
    maxContentWidth: Double?,
    measureLine: (String) -> Double
) -> [String] {
    guard let maximumNumberOfLines = style.maximumNumberOfLines, maximumNumberOfLines > 0 else {
        return lines.isEmpty ? [""] : lines
    }

    guard lines.count > maximumNumberOfLines else {
        return lines.isEmpty ? [""] : lines
    }

    var visibleLines = Array(lines.prefix(maximumNumberOfLines))
    guard style.lineBreakMode != .clip, !visibleLines.isEmpty else {
        return visibleLines
    }

    let lastLine = visibleLines.removeLast()
    visibleLines.append(appendingEllipsis(to: lastLine, maxWidth: maxContentWidth, measureLine: measureLine))
    return visibleLines
}
private func wrapLine(_ line: String, maxWidth: Double, measureLine: (String) -> Double) -> [String] {
    guard !line.isEmpty else {
        return [""]
    }

    let trimmedLine = line.trimmingCharacters(in: .whitespaces)
    guard !trimmedLine.isEmpty else {
        return [""]
    }

    let words = trimmedLine.split(whereSeparator: \.isWhitespace).map(String.init)
    var wrappedLines: [String] = []
    var currentLine = ""

    for word in words {
        let candidate = currentLine.isEmpty ? word : "\(currentLine) \(word)"
        if measureLine(candidate) <= maxWidth {
            currentLine = candidate
            continue
        }

        if !currentLine.isEmpty {
            wrappedLines.append(currentLine)
        }

        let wordLines = splitLongToken(word, maxWidth: maxWidth, measureLine: measureLine)
        if wordLines.count > 1 {
            wrappedLines.append(contentsOf: wordLines.dropLast())
        }
        currentLine = wordLines.last ?? ""
    }

    if !currentLine.isEmpty || wrappedLines.isEmpty {
        wrappedLines.append(currentLine)
    }

    return wrappedLines
}
private func splitLongToken(_ token: String, maxWidth: Double, measureLine: (String) -> Double) -> [String] {
    guard !token.isEmpty else {
        return [""]
    }

    if measureLine(token) <= maxWidth {
        return [token]
    }

    let characters = Array(token)
    var slices: [String] = []
    var startIndex = 0

    while startIndex < characters.count {
        let remaining = String(characters[startIndex...])
        let nextCount = max(1, longestFittingPrefixLength(for: remaining, maxWidth: maxWidth, measureLine: measureLine))
        let endIndex = min(characters.count, startIndex + nextCount)
        slices.append(String(characters[startIndex..<endIndex]))
        startIndex = endIndex
    }

    return slices
}
private func truncateLine(_ line: String, toFit maxWidth: Double, measureLine: (String) -> Double) -> String {
    guard measureLine(line) > maxWidth else {
        return line
    }

    return appendingEllipsis(to: line, maxWidth: maxWidth, measureLine: measureLine)
}
private func truncateLineHead(_ line: String, toFit maxWidth: Double, measureLine: (String) -> Double) -> String {
    guard measureLine(line) > maxWidth else {
        return line
    }

    return prependingEllipsis(to: line, maxWidth: maxWidth, measureLine: measureLine)
}
private func truncateLineMiddle(_ line: String, toFit maxWidth: Double, measureLine: (String) -> Double) -> String {
    guard measureLine(line) > maxWidth else {
        return line
    }

    let ellipsis = fittingEllipsis(maxWidth: maxWidth, measureLine: measureLine)
    guard !ellipsis.isEmpty else {
        return ""
    }

    let ellipsisWidth = measureLine(ellipsis)
    let availableWidth = max(0, maxWidth - ellipsisWidth)
    let halfWidth = availableWidth * 0.5

    let characters = Array(line)
    let headLength = longestFittingPrefixLength(for: line, maxWidth: halfWidth, measureLine: measureLine)
    let tailLength = longestFittingSuffixLength(
        for: line, maxWidth: availableWidth - (headLength > 0 ? measureLine(String(characters.prefix(headLength))) : 0),
        measureLine: measureLine)

    if headLength <= 0 && tailLength <= 0 {
        return ellipsis
    }

    let head = String(characters.prefix(headLength)).trimmingCharacters(in: .whitespaces)
    let tail = String(characters.suffix(tailLength)).trimmingCharacters(in: .whitespaces)
    return head + ellipsis + tail
}
private func prependingEllipsis(to line: String, maxWidth: Double?, measureLine: (String) -> Double) -> String {
    let ellipsis = fittingEllipsis(maxWidth: maxWidth, measureLine: measureLine)
    guard !ellipsis.isEmpty else {
        return ""
    }

    guard let maxWidth, maxWidth.isFinite else {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix(ellipsis) ? trimmed : ellipsis + trimmed
    }

    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard measureLine(trimmed) + measureLine(ellipsis) > maxWidth else {
        return ellipsis + trimmed
    }

    let suffixLength = longestFittingSuffixLength(
        for: trimmed,
        maxWidth: max(0, maxWidth - measureLine(ellipsis)),
        measureLine: measureLine
    )

    if suffixLength <= 0 {
        return ellipsis
    }

    let characters = Array(trimmed)
    let suffix = String(characters.suffix(suffixLength)).trimmingCharacters(in: .whitespaces)
    return suffix.isEmpty ? ellipsis : ellipsis + suffix
}
private func longestFittingSuffixLength(
    for text: String,
    maxWidth: Double,
    measureLine: (String) -> Double
) -> Int {
    let characters = Array(text)
    var lowerBound = 0
    var upperBound = characters.count
    var best = 0

    while lowerBound <= upperBound {
        let midpoint = (lowerBound + upperBound) / 2
        let candidate = String(characters.suffix(midpoint))
        if measureLine(candidate) <= maxWidth {
            best = midpoint
            lowerBound = midpoint + 1
        } else {
            upperBound = midpoint - 1
        }
    }

    return best
}
private func appendingEllipsis(to line: String, maxWidth: Double?, measureLine: (String) -> Double) -> String {
    let ellipsis = fittingEllipsis(maxWidth: maxWidth, measureLine: measureLine)
    guard !ellipsis.isEmpty else {
        return ""
    }

    guard let maxWidth, maxWidth.isFinite else {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasSuffix(ellipsis) ? trimmed : trimmed + ellipsis
    }

    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard measureLine(trimmed) + measureLine(ellipsis) > maxWidth else {
        return trimmed + ellipsis
    }

    let prefixLength = longestFittingPrefixLength(
        for: trimmed,
        maxWidth: maxWidth,
        reservedWidth: measureLine(ellipsis),
        measureLine: measureLine
    )

    if prefixLength <= 0 {
        return ellipsis
    }

    let characters = Array(trimmed)
    let prefix = String(characters.prefix(prefixLength)).trimmingCharacters(in: .whitespaces)
    return prefix.isEmpty ? ellipsis : prefix + ellipsis
}
private func fittingEllipsis(maxWidth: Double?, measureLine: (String) -> Double) -> String {
    let candidates = ["...", "..", "."]

    guard let maxWidth, maxWidth.isFinite else {
        return candidates[0]
    }

    for candidate in candidates {
        if measureLine(candidate) <= maxWidth {
            return candidate
        }
    }

    return ""
}
private func longestFittingPrefixLength(
    for text: String,
    maxWidth: Double,
    reservedWidth: Double = 0,
    measureLine: (String) -> Double
) -> Int {
    let characters = Array(text)
    var lowerBound = 0
    var upperBound = characters.count
    var best = 0
    let remainingWidth = max(0, maxWidth - reservedWidth)

    while lowerBound <= upperBound {
        let midpoint = (lowerBound + upperBound) / 2
        let candidate = String(characters.prefix(midpoint))
        if measureLine(candidate) <= remainingWidth {
            best = midpoint
            lowerBound = midpoint + 1
        } else {
            upperBound = midpoint - 1
        }
    }

    return best
}
private func resolvedContentWidth(for maxWidth: Double?, style: PixelTextStyle) -> Double? {
    guard let maxWidth, maxWidth.isFinite else {
        return nil
    }

    return max(0, maxWidth - style.insets.leading - style.insets.trailing)
}
private func measuredContentWidth(
    for lines: [String],
    style: PixelTextStyle,
    scale: Double,
    maxContentWidth: Double?
) -> Double {
    let measuredWidth = lines.map { PixelFont.rawLineWidth($0, letterSpacing: style.letterSpacing) * scale }.max() ?? 0

    if style.lineBreakMode == .clip, let maxContentWidth {
        return min(measuredWidth, maxContentWidth)
    }

    return measuredWidth
}
