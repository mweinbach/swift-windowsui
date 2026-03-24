import Foundation

// MARK: - GlyphKey

public struct GlyphKey: Hashable, Sendable {
    public var character: Character
    public var fontFamily: String
    public var fontSize: Float
    public var weight: GlyphWeight

    public init(character: Character, fontFamily: String, fontSize: Float, weight: GlyphWeight) {
        self.character = character
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.weight = weight
    }

    public enum GlyphWeight: Hashable, Sendable {
        case thin, light, regular, medium, semibold, bold, heavy, black
    }
}

// MARK: - GlyphEntry

public struct GlyphEntry: Equatable, Sendable {
    public var atlasX: Int32
    public var atlasY: Int32
    public var width: Int32
    public var height: Int32
    public var bearingX: Float
    public var bearingY: Float
    public var advance: Float

    public init(
        atlasX: Int32,
        atlasY: Int32,
        width: Int32,
        height: Int32,
        bearingX: Float,
        bearingY: Float,
        advance: Float
    ) {
        self.atlasX = atlasX
        self.atlasY = atlasY
        self.width = width
        self.height = height
        self.bearingX = bearingX
        self.bearingY = bearingY
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

// MARK: - GlyphAtlas

@MainActor
public final class GlyphAtlas {
    public let width: Int32
    public let height: Int32
    public private(set) var pixels: Data
    public private(set) var isDirty: Bool

    private var shelves: [Shelf] = []

    struct Shelf {
        var y: Int32
        var height: Int32
        var usedWidth: Int32
    }

    public init(width: Int32 = 2048, height: Int32 = 2048) {
        self.width = width
        self.height = height
        self.pixels = Data(count: Int(width) * Int(height) * 4)
        self.isDirty = false
    }

    public func allocate(width glyphWidth: Int32, height glyphHeight: Int32) -> (x: Int32, y: Int32)? {
        guard glyphWidth > 0, glyphHeight > 0,
              glyphWidth <= self.width, glyphHeight <= self.height else {
            return nil
        }

        // Try to fit in an existing shelf
        for i in shelves.indices {
            let shelf = shelves[i]
            if glyphHeight <= shelf.height && shelf.usedWidth + glyphWidth <= self.width {
                let x = shelf.usedWidth
                let y = shelf.y
                shelves[i].usedWidth += glyphWidth
                return (x: x, y: y)
            }
        }

        // Start a new shelf
        let newShelfY: Int32
        if let lastShelf = shelves.last {
            newShelfY = lastShelf.y + lastShelf.height
        } else {
            newShelfY = 0
        }

        guard newShelfY + glyphHeight <= self.height else {
            return nil
        }

        let newShelf = Shelf(y: newShelfY, height: glyphHeight, usedWidth: glyphWidth)
        shelves.append(newShelf)
        return (x: 0, y: newShelfY)
    }

    public func writePixels(_ glyphPixels: Data, at x: Int32, y: Int32, width glyphWidth: Int32, height glyphHeight: Int32) {
        let bytesPerPixel = 4
        let atlasStride = Int(self.width) * bytesPerPixel
        let glyphStride = Int(glyphWidth) * bytesPerPixel

        for row in 0..<Int(glyphHeight) {
            let dstOffset = (Int(y) + row) * atlasStride + Int(x) * bytesPerPixel
            let srcOffset = row * glyphStride
            let count = glyphStride

            guard srcOffset + count <= glyphPixels.count,
                  dstOffset + count <= pixels.count else {
                continue
            }

            pixels.replaceSubrange(dstOffset..<(dstOffset + count),
                                   with: glyphPixels[srcOffset..<(srcOffset + count)])
        }

        isDirty = true
    }

    public func clear() {
        pixels = Data(count: Int(width) * Int(height) * 4)
        shelves.removeAll()
        isDirty = true
    }

    public func markClean() {
        isDirty = false
    }
}
