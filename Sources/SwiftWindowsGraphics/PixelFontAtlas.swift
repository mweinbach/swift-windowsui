import Foundation
import SwiftWindowsCore

public struct PixelFontGlyph: Equatable, Sendable {
    public var atlasX: Int32
    public var atlasY: Int32
    public var width: Int32
    public var height: Int32
    public var advance: Float

    public init(atlasX: Int32, atlasY: Int32, width: Int32, height: Int32, advance: Float) {
        self.atlasX = atlasX
        self.atlasY = atlasY
        self.width = width
        self.height = height
        self.advance = advance
    }

    public func uvRect(atlasWidth: Int32, atlasHeight: Int32) -> (u0: Float, v0: Float, u1: Float, v1: Float) {
        let aw = Float(atlasWidth)
        let ah = Float(atlasHeight)
        return (
            u0: Float(atlasX) / aw,
            v0: Float(atlasY) / ah,
            u1: Float(atlasX + width) / aw,
            v1: Float(atlasY + height) / ah
        )
    }
}

public struct PixelFontAtlasData: Equatable, Sendable {
    public var surface: BitmapSurface
    public var glyphs: [Character: PixelFontGlyph]

    public init(surface: BitmapSurface, glyphs: [Character: PixelFontGlyph]) {
        self.surface = surface
        self.glyphs = glyphs
    }
}

public enum PixelFontAtlas {
    public static let glyphWidth = 5
    public static let glyphHeight = 7
    public static let shared: PixelFontAtlasData = buildAtlas()

    public static func pattern(for character: Character) -> [String] {
        let uppercase = Character(String(character).uppercased())
        return glyphPatterns[uppercase] ?? glyphPatterns["?"]!
    }

    public static func glyph(for character: Character) -> PixelFontGlyph {
        let uppercase = Character(String(character).uppercased())
        return shared.glyphs[uppercase] ?? shared.glyphs["?"]!
    }

    public static func supports(_ character: Character) -> Bool {
        let uppercase = Character(String(character).uppercased())
        return glyphPatterns[uppercase] != nil
    }

    private static let glyphPatterns: [Character: [String]] = [
        " ": ["00000","00000","00000","00000","00000","00000","00000"],
        "-": ["00000","00000","00000","11111","00000","00000","00000"],
        ".": ["00000","00000","00000","00000","00000","01100","01100"],
        ":": ["00000","01100","01100","00000","01100","01100","00000"],
        "/": ["00001","00010","00100","01000","10000","00000","00000"],
        "?": ["01110","10001","00010","00100","00100","00000","00100"],
        "\u{E721}": ["01110","10001","10001","01110","00110","00100","01010"], // search
        "\u{E8B7}": ["01110","10000","11110","10001","10001","10001","11111"], // folder
        "\u{E713}": ["00100","10101","01110","11111","01110","10101","00100"], // settings
        "\u{E945}": ["00100","01100","11111","00110","00100","01000","11000"], // lightning
        "\u{ECA5}": ["11111","10001","11111","10001","11111","10001","10001"], // layout
        "\u{E765}": ["00000","11111","10001","10101","10101","11111","00000"], // keyboard
        "\u{EAAC}": ["00100","10101","01110","11111","01110","10101","00100"], // sparkle
        "\u{E946}": ["00100","00000","00100","00100","00100","00100","00100"], // info
        "\u{E7C3}": ["00000","01000","11100","00111","00100","01110","00010"], // activity
        "\u{E8A5}": ["11110","10010","10011","10001","10001","10001","11111"], // document
        "\u{E7FD}": ["11111","00100","00100","11111","00100","00100","11111"], // split
        "\u{E73E}": ["00000","00001","00010","10100","01000","00000","00000"], // checkmark
        "\u{E70D}": ["00000","00000","10001","01010","00100","00000","00000"], // chevronDown
        "\u{E915}": ["00000","01110","10001","10101","10001","01110","00000"], // radioSelected
        "\u{E916}": ["00000","01110","10001","10001","10001","01110","00000"], // radioUnselected
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

    private static func buildAtlas() -> PixelFontAtlasData {
        let sortedGlyphs = glyphPatterns.keys.sorted { String($0) < String($1) }
        let columns = 8
        let cellWidth = glyphWidth + 1
        let cellHeight = glyphHeight + 1
        let rows = (sortedGlyphs.count + columns - 1) / columns
        let atlasWidth = Int32(columns * cellWidth)
        let atlasHeight = Int32(rows * cellHeight)
        let bytesPerRow = Int32(Int(atlasWidth) * 4)
        var pixels = [UInt8](repeating: 0, count: Int(bytesPerRow * atlasHeight))
        var glyphs: [Character: PixelFontGlyph] = [:]

        for (index, character) in sortedGlyphs.enumerated() {
            let column = index % columns
            let row = index / columns
            let originX = column * cellWidth
            let originY = row * cellHeight
            let pattern = glyphPatterns[character]!

            for (rowIndex, rowPattern) in pattern.enumerated() {
                for (columnIndex, bit) in rowPattern.enumerated() where bit == "1" {
                    let pixelOffset = ((originY + rowIndex) * Int(bytesPerRow)) + ((originX + columnIndex) * 4)
                    pixels[pixelOffset] = 255
                    pixels[pixelOffset + 1] = 255
                    pixels[pixelOffset + 2] = 255
                    pixels[pixelOffset + 3] = 255
                }
            }

            glyphs[character] = PixelFontGlyph(
                atlasX: Int32(originX),
                atlasY: Int32(originY),
                width: Int32(glyphWidth),
                height: Int32(glyphHeight),
                advance: Float(glyphWidth)
            )
        }

        let surface = BitmapSurface(
            width: atlasWidth,
            height: atlasHeight,
            bytesPerRow: bytesPerRow,
            pixels: Data(pixels)
        )

        return PixelFontAtlasData(surface: surface, glyphs: glyphs)
    }
}
