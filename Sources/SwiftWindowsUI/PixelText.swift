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

public enum TextLineBreakMode: Sendable {
    case clip
    case truncateTail
    case truncateHead
    case truncateMiddle
    case wrap
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
    public var lineBreakMode: TextLineBreakMode
    public var maximumNumberOfLines: Int?
    public var underline: Bool
    public var strikethrough: Bool
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
        lineBreakMode: TextLineBreakMode = .truncateTail,
        maximumNumberOfLines: Int? = nil,
        underline: Bool = false,
        strikethrough: Bool = false,
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
        self.lineBreakMode = lineBreakMode
        self.maximumNumberOfLines = maximumNumberOfLines
        self.underline = underline
        self.strikethrough = strikethrough
        self.enableKerning = enableKerning
        self.spans = spans
    }
}

enum PixelFont {
    static func measure(_ text: String, style: PixelTextStyle, maxWidth: Double? = nil) -> Size {
        let scale = max(style.scale, 1)
        let maxContentWidth = resolvedContentWidth(for: maxWidth, style: style)
        let layout = resolveTextLayout(
            for: text,
            style: style,
            maxContentWidth: maxContentWidth,
            measureLine: { line in rawLineWidth(line, letterSpacing: style.letterSpacing) * scale }
        )
        let contentWidth = measuredContentWidth(
            for: layout.lines,
            style: style,
            scale: scale,
            maxContentWidth: maxContentWidth
        )
        let width = contentWidth + style.insets.leading + style.insets.trailing
        let lineCount = max(layout.lines.count, 1)
        let height = (
            Double(lineCount * PixelFontAtlas.glyphHeight) +
            Double(max(lineCount - 1, 0)) * style.lineSpacing
        ) * scale + style.insets.top + style.insets.bottom

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
        let scale = max(style.scale, 1)
        let layout = resolveTextLayout(
            for: text,
            style: style,
            maxContentWidth: max(0, contentRect.size.width),
            measureLine: { line in rawLineWidth(line, letterSpacing: style.letterSpacing) * scale }
        )
        let lines = layout.lines
        let totalTextHeight = (
            Double(max(lines.count, 1) * PixelFontAtlas.glyphHeight) +
            Double(max(lines.count - 1, 0)) * style.lineSpacing
        ) * scale
        var y = contentRect.origin.y + max(0, (contentRect.size.height - totalTextHeight) * 0.5)

        for line in lines {
            let lineWidth = rawLineWidth(String(line), letterSpacing: style.letterSpacing) * scale
            let x: Double
            switch style.alignment {
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
                letterSpacing: style.letterSpacing,
                color: style.color,
                clipRect: clipRect,
                into: &commands
            )

            y += Double(PixelFontAtlas.glyphHeight) * scale + style.lineSpacing * scale
        }
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
        let scale = max(style.scale, 1)
        let layout = resolveTextLayout(
            for: text,
            style: style,
            maxContentWidth: max(0, contentRect.size.width),
            measureLine: { line in rawLineWidth(line, letterSpacing: style.letterSpacing) * scale }
        )
        let lines = layout.lines
        let totalTextHeight = (
            Double(max(lines.count, 1) * PixelFontAtlas.glyphHeight) +
            Double(max(lines.count - 1, 0)) * style.lineSpacing
        ) * scale
        var y = contentRect.origin.y + max(0, (contentRect.size.height - totalTextHeight) * 0.5)

        for line in lines {
            let lineWidth = rawLineWidth(String(line), letterSpacing: style.letterSpacing) * scale
            let x: Double
            switch style.alignment {
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
                letterSpacing: style.letterSpacing,
                color: style.color,
                clipRect: clipRect,
                into: &glyphs
            )

            y += Double(PixelFontAtlas.glyphHeight) * scale + style.lineSpacing * scale
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
    let tailLength = longestFittingSuffixLength(for: line, maxWidth: availableWidth - (headLength > 0 ? measureLine(String(characters.prefix(headLength))) : 0), measureLine: measureLine)

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
