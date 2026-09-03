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
/// The rungs of the weight axis the design system actually uses: 400 / 500 /
/// 600, plus 700 for anything that asks for bold.
///
/// `medium` is not decoration. The type ramp separates `body` (13/400) from
/// `body-strong` (13/500) at one point of size, so *all* of the difference
/// between them is the weight — and with only regular and semibold on the
/// axis, 500 rounded down to 400 and the two roles rendered identically. A
/// selected table row's name, a control label, a caption-strong figure and a
/// selected tab all looked exactly like the resting state beside them.
/// Segoe UI Variable carries a continuous weight axis, so 500 is a real
/// instance rather than a synthesised one.
public enum TextWeight: Sendable {
    case regular
    case medium
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
    /// Inter-glyph gap of the 5x7 `PixelFontAtlas`, in atlas units (its
    /// glyphs are 5 units wide). This is *not* typographic tracking and not a
    /// point value: its default of 1 is the bitmap font's normal spacing, so
    /// applying it to a real font would space every string out by a point.
    /// Native tracking lives in `nativeLetterSpacing`.
    public var letterSpacing: Double
    /// Typographic tracking in points, applied by the DirectWrite glyph path
    /// to both measurement and painting. `nil` means "the font's own
    /// spacing" - only `.kerning` / `.tracking` set it.
    public var nativeLetterSpacing: Double?
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
        nativeLetterSpacing: Double? = nil,
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
        self.nativeLetterSpacing = nativeLetterSpacing
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
        copy.nativeLetterSpacing = nativeLetterSpacing.map { $0 * factor }
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
/// Text-measurement facade for caret placement and pointer hit testing
/// outside the retained runtime. Measures through the same path
/// `ViewNode.textContentSize` uses: native (DirectWrite/GDI) layout when
/// installed, fixed pixel-font advance otherwise. All results are in logical
/// points so they line up with `ViewNode.frame` and runtime pointer
/// coordinates, and are content-relative (style insets are not included in
/// caret boundaries).
@MainActor
public enum RetainedTextMetrics {
    /// Measures exactly as `ViewNode.textContentSize` does: native layout
    /// when installed, pixel-font fallback otherwise.
    public static func size(
        of text: String,
        style: PixelTextStyle,
        displayScale: Double = 1,
        maxWidth: Double? = nil
    ) -> Size {
        NativeTextRenderer.measure(text, style: style, scaleFactor: displayScale, maxWidth: maxWidth)
            ?? PixelFont.measure(text, style: style, maxWidth: maxWidth)
    }

    /// Leading-edge x of the caret at character `offset` within a single line.
    public static func caretX(
        atOffset offset: Int,
        in line: String,
        style: PixelTextStyle,
        displayScale: Double = 1
    ) -> Double {
        let boundaries = caretBoundaries(in: line, style: style, displayScale: displayScale)
        return boundaries[max(0, min(offset, line.count))]
    }

    /// Character offset whose caret boundary is nearest `x` within a single
    /// line. `x` outside the line's extent clamps to the nearest edge.
    public static func characterOffset(
        atX x: Double,
        in line: String,
        style: PixelTextStyle,
        displayScale: Double = 1
    ) -> Int {
        guard !line.isEmpty else {
            return 0
        }

        let boundaries = caretBoundaries(in: line, style: style, displayScale: displayScale)
        let clampedX = max(0, min(x, boundaries[line.count]))
        var bestOffset = 0
        var bestDistance = abs(boundaries[0] - clampedX)
        for offset in 1...line.count {
            let distance = abs(boundaries[offset] - clampedX)
            if distance < bestDistance {
                bestDistance = distance
                bestOffset = offset
            }
        }
        return bestOffset
    }

    /// Caret boundary x positions for every character offset in `line`,
    /// derived from native glyph advances when available and from the fixed
    /// pixel-font advance otherwise.
    private static func caretBoundaries(
        in line: String,
        style: PixelTextStyle,
        displayScale: Double
    ) -> [Double] {
        let count = line.count
        // An empty line still has one caret boundary at the content origin.
        guard count > 0 else { return [0] }
        if count > 0,
            let layout = NativeTextRenderer.layout(line, style: style, scaleFactor: displayScale, maxWidth: nil),
            let nativeLine = layout.lines.first
        {
            var boundaries = [Double](repeating: -1, count: count + 1)
            boundaries[count] = 0
            for glyph in nativeLine.glyphs {
                guard let sourceIndex = glyph.sourceIndex, sourceIndex >= 0, sourceIndex < count else {
                    continue
                }
                boundaries[sourceIndex] = glyph.origin.x
                boundaries[count] = max(boundaries[count], glyph.origin.x + glyph.advance)
            }
            // Ligatures and clusters leave interior offsets without a glyph;
            // snap them forward to the next real boundary so the caret never
            // lands inside a cluster.
            var nextBoundary = boundaries[count]
            for offset in stride(from: count, through: 0, by: -1) {
                if boundaries[offset] < 0 {
                    boundaries[offset] = nextBoundary
                } else {
                    nextBoundary = boundaries[offset]
                }
            }
            return boundaries
        }

        let scale = max(style.scale, 0.01)
        var boundaries = [Double](repeating: 0, count: count + 1)
        for offset in 1...count {
            boundaries[offset] =
                (Double(offset) * Double(PixelFont.glyphWidth) + Double(offset - 1) * style.letterSpacing) * scale
        }
        return boundaries
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
    var fragments: [TextLayoutFragment]

    var lines: [String] {
        get { fragments.map(\.text) }
        set { fragments = newValue.map { TextLayoutFragment(synthetic: $0) } }
    }

    init(lines: [String]) {
        self.fragments = lines.map { TextLayoutFragment(synthetic: $0) }
    }

    init(fragments: [TextLayoutFragment]) {
        self.fragments = fragments
    }

    var text: String {
        lines.joined(separator: "\n")
    }

    var fragment: TextLayoutFragment {
        TextLayoutFragment.joined(fragments, separator: TextLayoutFragment(synthetic: "\n"))
    }
}
func resolveTextLayout(
    for text: String,
    style: PixelTextStyle,
    maxContentWidth: Double?,
    measureLine: (String) -> Double
) -> ResolvedTextLayout {
    resolveTextLayout(
        for: TextLayoutFragment(synthetic: text),
        style: style,
        maxContentWidth: maxContentWidth,
        measureFragment: { measureLine($0.text) }
    )
}
func resolveTextLayout(
    for text: TextLayoutFragment,
    style: PixelTextStyle,
    maxContentWidth: Double?,
    measureFragment: (TextLayoutFragment) -> Double
) -> ResolvedTextLayout {
    let sourceLines = text.normalizedLines()
    let fittedLines: [TextLayoutFragment]

    switch style.lineBreakMode {
    case .clip:
        fittedLines = sourceLines
    case .truncateTail:
        guard let maxContentWidth, maxContentWidth.isFinite else {
            fittedLines = sourceLines
            break
        }
        fittedLines = sourceLines.map { truncateLine($0, toFit: maxContentWidth, measureFragment: measureFragment) }
    case .truncateHead:
        guard let maxContentWidth, maxContentWidth.isFinite else {
            fittedLines = sourceLines
            break
        }
        fittedLines = sourceLines.map { truncateLineHead($0, toFit: maxContentWidth, measureFragment: measureFragment) }
    case .truncateMiddle:
        guard let maxContentWidth, maxContentWidth.isFinite else {
            fittedLines = sourceLines
            break
        }
        fittedLines = sourceLines.map {
            truncateLineMiddle($0, toFit: maxContentWidth, measureFragment: measureFragment)
        }
    case .wrap:
        guard let maxContentWidth, maxContentWidth.isFinite else {
            fittedLines = sourceLines
            break
        }
        fittedLines = sourceLines.flatMap { wrapLine($0, maxWidth: maxContentWidth, measureFragment: measureFragment) }
    }

    return ResolvedTextLayout(
        fragments: applyLineLimit(
            to: fittedLines,
            style: style,
            maxContentWidth: maxContentWidth,
            measureFragment: measureFragment
        )
    )
}
func normalizedTextLines(from text: String) -> [String] {
    let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    return normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
}
func minimumTextScaleFactor(
    for text: TextLayoutFragment,
    style: PixelTextStyle,
    maxContentWidth: Double?,
    measureFragment: (TextLayoutFragment) -> Double
) -> Double {
    guard
        style.minimumScaleFactor < 1,
        let maxContentWidth,
        maxContentWidth.isFinite,
        maxContentWidth > 0
    else {
        return 1
    }

    let widestLine = text.normalizedLines().map(measureFragment).filter(\.isFinite).max() ?? 0
    guard widestLine > maxContentWidth, widestLine > 0 else {
        return 1
    }
    return min(1, max(style.minimumScaleFactor, maxContentWidth / widestLine))
}
private func applyLineLimit(
    to lines: [TextLayoutFragment],
    style: PixelTextStyle,
    maxContentWidth: Double?,
    measureFragment: (TextLayoutFragment) -> Double
) -> [TextLayoutFragment] {
    guard let maximumNumberOfLines = style.maximumNumberOfLines, maximumNumberOfLines > 0 else {
        return lines.isEmpty ? [TextLayoutFragment(synthetic: "")] : lines
    }

    guard lines.count > maximumNumberOfLines else {
        return lines.isEmpty ? [TextLayoutFragment(synthetic: "")] : lines
    }

    var visibleLines = Array(lines.prefix(maximumNumberOfLines))
    guard style.lineBreakMode != .clip, !visibleLines.isEmpty else {
        return visibleLines
    }

    let lastLine = visibleLines.removeLast()
    visibleLines.append(appendingEllipsis(to: lastLine, maxWidth: maxContentWidth, measureFragment: measureFragment))
    return visibleLines
}
private func wrapLine(
    _ line: TextLayoutFragment, maxWidth: Double, measureFragment: (TextLayoutFragment) -> Double
) -> [TextLayoutFragment] {
    guard !line.text.isEmpty else {
        return [line]
    }

    let trimmedLine = line.trimmingWhitespace()
    guard !trimmedLine.text.isEmpty else {
        return [trimmedLine]
    }

    let words = trimmedLine.words()
    var wrappedLines: [TextLayoutFragment] = []
    var currentLine = TextLayoutFragment(synthetic: "")

    for word in words {
        let candidate =
            currentLine.text.isEmpty
            ? word
            : currentLine.appending(.wordSeparator(after: currentLine, before: word)).appending(word)
        if measureFragment(candidate) <= maxWidth {
            currentLine = candidate
            continue
        }

        if !currentLine.text.isEmpty {
            wrappedLines.append(currentLine)
        }

        let wordLines = splitLongToken(word, maxWidth: maxWidth, measureFragment: measureFragment)
        if wordLines.count > 1 {
            wrappedLines.append(contentsOf: wordLines.dropLast())
        }
        currentLine = wordLines.last ?? TextLayoutFragment(synthetic: "")
    }

    if !currentLine.text.isEmpty || wrappedLines.isEmpty {
        wrappedLines.append(currentLine)
    }

    return wrappedLines
}
private func splitLongToken(
    _ token: TextLayoutFragment, maxWidth: Double, measureFragment: (TextLayoutFragment) -> Double
) -> [TextLayoutFragment] {
    guard !token.text.isEmpty else {
        return [token]
    }

    if measureFragment(token) <= maxWidth {
        return [token]
    }

    let characterCount = token.text.count
    var slices: [TextLayoutFragment] = []
    var startIndex = 0

    while startIndex < characterCount {
        let remaining = token.droppingFirst(startIndex)
        let nextCount = max(
            1, longestFittingPrefixLength(for: remaining, maxWidth: maxWidth, measureFragment: measureFragment))
        let endIndex = min(characterCount, startIndex + nextCount)
        slices.append(remaining.prefix(endIndex - startIndex))
        startIndex = endIndex
    }

    return slices
}
private func truncateLine(
    _ line: TextLayoutFragment, toFit maxWidth: Double, measureFragment: (TextLayoutFragment) -> Double
) -> TextLayoutFragment {
    guard measureFragment(line) > maxWidth else {
        return line
    }

    return appendingEllipsis(to: line, maxWidth: maxWidth, measureFragment: measureFragment)
}
private func truncateLineHead(
    _ line: TextLayoutFragment, toFit maxWidth: Double, measureFragment: (TextLayoutFragment) -> Double
) -> TextLayoutFragment {
    guard measureFragment(line) > maxWidth else {
        return line
    }

    return prependingEllipsis(to: line, maxWidth: maxWidth, measureFragment: measureFragment)
}
private func truncateLineMiddle(
    _ line: TextLayoutFragment, toFit maxWidth: Double, measureFragment: (TextLayoutFragment) -> Double
) -> TextLayoutFragment {
    guard measureFragment(line) > maxWidth else {
        return line
    }

    let ellipsis = fittingEllipsis(maxWidth: maxWidth, measureFragment: measureFragment)
    guard !ellipsis.text.isEmpty else {
        return TextLayoutFragment(synthetic: "")
    }

    let ellipsisWidth = measureFragment(ellipsis)
    let availableWidth = max(0, maxWidth - ellipsisWidth)
    let halfWidth = availableWidth * 0.5

    let headLength = longestFittingPrefixLength(for: line, maxWidth: halfWidth, measureFragment: measureFragment)
    let headWidth = headLength > 0 ? measureFragment(line.prefix(headLength)) : 0
    let tailLength = longestFittingSuffixLength(
        for: line, maxWidth: availableWidth - headWidth, measureFragment: measureFragment)

    if headLength <= 0 && tailLength <= 0 {
        return ellipsis
    }

    let head = line.prefix(headLength).trimmingWhitespace()
    let tail = line.suffix(tailLength).trimmingWhitespace()
    return head.appending(ellipsis).appending(tail)
}
private func prependingEllipsis(
    to line: TextLayoutFragment, maxWidth: Double?, measureFragment: (TextLayoutFragment) -> Double
) -> TextLayoutFragment {
    let ellipsis = fittingEllipsis(maxWidth: maxWidth, measureFragment: measureFragment)
    guard !ellipsis.text.isEmpty else {
        return TextLayoutFragment(synthetic: "")
    }

    guard let maxWidth, maxWidth.isFinite else {
        let trimmed = line.trimmingWhitespace()
        return trimmed.text.hasPrefix(ellipsis.text) ? trimmed : ellipsis.appending(trimmed)
    }

    let trimmed = line.trimmingWhitespace()
    guard measureFragment(trimmed) + measureFragment(ellipsis) > maxWidth else {
        return ellipsis.appending(trimmed)
    }

    let suffixLength = longestFittingSuffixLength(
        for: trimmed,
        maxWidth: max(0, maxWidth - measureFragment(ellipsis)),
        measureFragment: measureFragment
    )

    if suffixLength <= 0 {
        return ellipsis
    }

    let suffix = trimmed.suffix(suffixLength).trimmingWhitespace()
    return suffix.text.isEmpty ? ellipsis : ellipsis.appending(suffix)
}
private func longestFittingSuffixLength(
    for text: TextLayoutFragment,
    maxWidth: Double,
    measureFragment: (TextLayoutFragment) -> Double
) -> Int {
    var lowerBound = 0
    var upperBound = text.text.count
    var best = 0

    while lowerBound <= upperBound {
        let midpoint = lowerBound + (upperBound - lowerBound) / 2
        let candidate = text.suffix(midpoint)
        if measureFragment(candidate) <= maxWidth {
            best = midpoint
            lowerBound = midpoint + 1
        } else {
            upperBound = midpoint - 1
        }
    }

    return best
}
private func appendingEllipsis(
    to line: TextLayoutFragment, maxWidth: Double?, measureFragment: (TextLayoutFragment) -> Double
) -> TextLayoutFragment {
    let ellipsis = fittingEllipsis(maxWidth: maxWidth, measureFragment: measureFragment)
    guard !ellipsis.text.isEmpty else {
        return TextLayoutFragment(synthetic: "")
    }

    guard let maxWidth, maxWidth.isFinite else {
        let trimmed = line.trimmingWhitespace()
        return trimmed.text.hasSuffix(ellipsis.text) ? trimmed : trimmed.appending(ellipsis)
    }

    let trimmed = line.trimmingWhitespace()
    guard measureFragment(trimmed) + measureFragment(ellipsis) > maxWidth else {
        return trimmed.appending(ellipsis)
    }

    let prefixLength = longestFittingPrefixLength(
        for: trimmed,
        maxWidth: maxWidth,
        reservedWidth: measureFragment(ellipsis),
        measureFragment: measureFragment
    )

    if prefixLength <= 0 {
        return ellipsis
    }

    let prefix = trimmed.prefix(prefixLength).trimmingWhitespace()
    return prefix.text.isEmpty ? ellipsis : prefix.appending(ellipsis)
}
private func fittingEllipsis(
    maxWidth: Double?, measureFragment: (TextLayoutFragment) -> Double
) -> TextLayoutFragment {
    let candidates = ["...", "..", "."].map { TextLayoutFragment(synthetic: $0) }

    guard let maxWidth, maxWidth.isFinite else {
        return candidates[0]
    }

    for candidate in candidates {
        if measureFragment(candidate) <= maxWidth {
            return candidate
        }
    }

    return TextLayoutFragment(synthetic: "")
}
/// Longest prefix of `text` that fits, found by galloping up from a short
/// prefix before binary-searching. Keeping each shaping probe bounded by
/// roughly twice the fitted line length avoids quadratic DirectWrite work
/// for long tokens and scripts without spaces.
private func longestFittingPrefixLength(
    for text: TextLayoutFragment,
    maxWidth: Double,
    reservedWidth: Double = 0,
    measureFragment: (TextLayoutFragment) -> Double
) -> Int {
    let characterCount = text.text.count
    guard characterCount > 0 else {
        return 0
    }

    let remainingWidth = max(0, maxWidth - reservedWidth)
    func fits(_ count: Int) -> Bool {
        measureFragment(text.prefix(count)) <= remainingWidth
    }

    var best = 0
    var firstMisfit = characterCount + 1
    var probe = 1
    while probe <= characterCount {
        guard fits(probe) else {
            firstMisfit = probe
            break
        }
        best = probe
        guard probe <= Int.max / 2 else {
            break
        }
        probe *= 2
    }

    var lowerBound = best + 1
    var upperBound = min(firstMisfit - 1, characterCount)
    while lowerBound <= upperBound {
        let midpoint = lowerBound + (upperBound - lowerBound) / 2
        if fits(midpoint) {
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
