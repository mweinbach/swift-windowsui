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

public struct PixelTextStyle: Sendable {
    public var color: Color
    public var scale: Double
    public var alignment: TextHorizontalAlignment
    public var letterSpacing: Double
    public var lineSpacing: Double
    public var insets: EdgeInsets
    public var fontFamily: String
    public var weight: TextWeight

    public init(
        color: Color,
        scale: Double = 2,
        alignment: TextHorizontalAlignment = .center,
        letterSpacing: Double = 1,
        lineSpacing: Double = 2,
        insets: EdgeInsets = .zero,
        fontFamily: String = "Segoe UI",
        weight: TextWeight = .regular
    ) {
        self.color = color
        self.scale = scale
        self.alignment = alignment
        self.letterSpacing = letterSpacing
        self.lineSpacing = lineSpacing
        self.insets = insets
        self.fontFamily = fontFamily
        self.weight = weight
    }
}

enum PixelFont {
    static func measure(_ text: String, style: PixelTextStyle) -> Size {
        let lines = normalizedLines(from: text)
        let scale = max(style.scale, 1)
        let rawWidths = lines.map { rawLineWidth(String($0), letterSpacing: style.letterSpacing) }
        let width = (rawWidths.max() ?? 0) * scale + style.insets.leading + style.insets.trailing
        let lineCount = max(lines.count, 1)
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

        let lines = normalizedLines(from: text)
        let contentRect = rect.inset(by: style.insets)
        let scale = max(style.scale, 1)
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

    private static func normalizedLines(from text: String) -> [Substring] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        return normalized.split(separator: "\n", omittingEmptySubsequences: false)
    }

    private static func rawLineWidth(_ text: String, letterSpacing: Double) -> Double {
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
