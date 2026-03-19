import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics

public enum TextHorizontalAlignment: Sendable {
    case leading
    case center
    case trailing
}

public enum TextWeight: Sendable {
    case regular
    case semibold
    case bold
}

public enum TextLineBreakMode: Sendable {
    case clip
    case truncateTail
    case wrap
}

public struct PixelTextStyle: Sendable, Equatable {
    public var color: Color
    public var scale: Double
    public var alignment: TextHorizontalAlignment
    public var letterSpacing: Double
    public var lineSpacing: Double
    public var insets: EdgeInsets
    public var fontFamily: String
    public var weight: TextWeight
    public var lineBreakMode: TextLineBreakMode
    public var maximumNumberOfLines: Int?

    public init(
        color: Color,
        scale: Double = 2,
        alignment: TextHorizontalAlignment = .center,
        letterSpacing: Double = 1,
        lineSpacing: Double = 2,
        insets: EdgeInsets = .zero,
        fontFamily: String = "Segoe UI",
        weight: TextWeight = .regular,
        lineBreakMode: TextLineBreakMode = .truncateTail,
        maximumNumberOfLines: Int? = nil
    ) {
        self.color = color
        self.scale = scale
        self.alignment = alignment
        self.letterSpacing = letterSpacing
        self.lineSpacing = lineSpacing
        self.insets = insets
        self.fontFamily = fontFamily
        self.weight = weight
        self.lineBreakMode = lineBreakMode
        self.maximumNumberOfLines = maximumNumberOfLines
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
            Double(lineCount * glyphHeight) +
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
            Double(max(lines.count, 1) * glyphHeight) +
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

            y += Double(glyphHeight) * scale + style.lineSpacing * scale
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
            let glyph = glyphs[character] ?? glyphs["?"]!

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
                        endColumn: glyphWidth,
                        rowIndex: rowIndex,
                        origin: Point(x: cursorX, y: origin.y),
                        scale: scale,
                        color: color,
                        clipRect: clipRect,
                        into: &commands
                    )
                }
            }

            cursorX += (Double(glyphWidth) + letterSpacing) * scale
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

    fileprivate static func rawLineWidth(_ text: String, letterSpacing: Double) -> Double {
        guard !text.isEmpty else {
            return 0
        }

        let count = Double(text.count)
        return count * Double(glyphWidth) + Double(max(text.count - 1, 0)) * letterSpacing
    }

    private static let glyphWidth = 5
    private static let glyphHeight = 7

    private static let glyphs: [Character: [String]] = [
        " ": ["00000","00000","00000","00000","00000","00000","00000"],
        "-": ["00000","00000","00000","11111","00000","00000","00000"],
        ".": ["00000","00000","00000","00000","00000","01100","01100"],
        ":": ["00000","01100","01100","00000","01100","01100","00000"],
        "/": ["00001","00010","00100","01000","10000","00000","00000"],
        "?": ["01110","10001","00010","00100","00100","00000","00100"],
        "0": ["01110","10001","10011","10101","11001","10001","01110"],
        "1": ["00100","01100","00100","00100","00100","00100","01110"],
        "2": ["01110","10001","00001","00010","00100","01000","11111"],
        "3": ["11110","00001","00001","01110","00001","00001","11110"],
        "4": ["00010","00110","01010","10010","11111","00010","00010"],
        "5": ["11111","10000","10000","11110","00001","00001","11110"],
        "6": ["01110","10000","10000","11110","10001","10001","01110"],
        "7": ["11111","00001","00010","00100","01000","01000","01000"],
        "8": ["01110","10001","10001","01110","10001","10001","01110"],
        "9": ["01110","10001","10001","01111","00001","00001","01110"],
        "A": ["01110","10001","10001","11111","10001","10001","10001"],
        "B": ["11110","10001","10001","11110","10001","10001","11110"],
        "C": ["01110","10001","10000","10000","10000","10001","01110"],
        "D": ["11110","10001","10001","10001","10001","10001","11110"],
        "E": ["11111","10000","10000","11110","10000","10000","11111"],
        "F": ["11111","10000","10000","11110","10000","10000","10000"],
        "G": ["01110","10001","10000","10111","10001","10001","01110"],
        "H": ["10001","10001","10001","11111","10001","10001","10001"],
        "I": ["01110","00100","00100","00100","00100","00100","01110"],
        "J": ["00001","00001","00001","00001","10001","10001","01110"],
        "K": ["10001","10010","10100","11000","10100","10010","10001"],
        "L": ["10000","10000","10000","10000","10000","10000","11111"],
        "M": ["10001","11011","10101","10101","10001","10001","10001"],
        "N": ["10001","11001","10101","10011","10001","10001","10001"],
        "O": ["01110","10001","10001","10001","10001","10001","01110"],
        "P": ["11110","10001","10001","11110","10000","10000","10000"],
        "Q": ["01110","10001","10001","10001","10101","10010","01101"],
        "R": ["11110","10001","10001","11110","10100","10010","10001"],
        "S": ["01111","10000","10000","01110","00001","00001","11110"],
        "T": ["11111","00100","00100","00100","00100","00100","00100"],
        "U": ["10001","10001","10001","10001","10001","10001","01110"],
        "V": ["10001","10001","10001","10001","10001","01010","00100"],
        "W": ["10001","10001","10001","10101","10101","10101","01010"],
        "X": ["10001","10001","01010","00100","01010","10001","10001"],
        "Y": ["10001","10001","01010","00100","00100","00100","00100"],
        "Z": ["11111","00001","00010","00100","01000","10000","11111"],
    ]
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
