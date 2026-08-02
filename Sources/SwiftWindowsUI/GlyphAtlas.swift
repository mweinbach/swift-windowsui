import Foundation

// MARK: - GlyphKey

import SwiftWindowsGraphics

// MARK: - GlyphEntry

// MARK: - GlyphAtlas

public struct GlyphKey: Hashable, Sendable {
    public var character: Character?
    public var glyphID: UInt32?
    public var fontFaceID: UInt64?
    public var fontFamily: String
    public var fontSize: Float
    public var weight: GlyphWeight
    public var fontWidth: GlyphWidth
    public var isItalic: Bool
    public var monospacedDigits: Bool
    public var lowercaseSmallCaps: Bool
    public var uppercaseSmallCaps: Bool

    public init(
        character: Character,
        fontFamily: String,
        fontSize: Float,
        weight: GlyphWeight,
        fontWidth: GlyphWidth = .standard,
        isItalic: Bool = false,
        monospacedDigits: Bool = false,
        lowercaseSmallCaps: Bool = false,
        uppercaseSmallCaps: Bool = false
    ) {
        self.character = character
        self.glyphID = nil
        self.fontFaceID = nil
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.weight = weight
        self.fontWidth = fontWidth
        self.isItalic = isItalic
        self.monospacedDigits = monospacedDigits
        self.lowercaseSmallCaps = lowercaseSmallCaps
        self.uppercaseSmallCaps = uppercaseSmallCaps
    }

    public init(
        character: Character? = nil,
        glyphID: UInt32,
        fontFaceID: UInt64?,
        fontFamily: String,
        fontSize: Float,
        weight: GlyphWeight,
        fontWidth: GlyphWidth = .standard,
        isItalic: Bool = false,
        monospacedDigits: Bool = false,
        lowercaseSmallCaps: Bool = false,
        uppercaseSmallCaps: Bool = false
    ) {
        self.character = character
        self.glyphID = glyphID
        self.fontFaceID = fontFaceID
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.weight = weight
        self.fontWidth = fontWidth
        self.isItalic = isItalic
        self.monospacedDigits = monospacedDigits
        self.lowercaseSmallCaps = lowercaseSmallCaps
        self.uppercaseSmallCaps = uppercaseSmallCaps
    }

    public enum GlyphWeight: Hashable, Sendable {
        case thin, light, regular, medium, semibold, bold, heavy, black
    }

    public enum GlyphWidth: Hashable, Sendable {
        case compressed, condensed, standard, expanded
    }
}
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
@MainActor
public final class GlyphAtlas {
    public let width: Int32
    public let height: Int32
    public private(set) var pixels: Data
    public private(set) var isDirty: Bool
    public private(set) var dirtyRegion: GlyphAtlasRegion?

    /// Identifies the current pixels, process-wide (see
    /// `RenderContentVersion`). Bumped by every write and every clear, and
    /// minted rather than started at zero so two atlases — the shared one
    /// and a test's small one, or a future per-scale atlas — can never
    /// claim the same version for different pixels.
    public private(set) var contentVersion: UInt64 = RenderContentVersion.next()

    /// The version `dirtyRegion` accumulated from: applying the region to
    /// pixels at this version yields pixels at `contentVersion`. Reset by
    /// `markClean()`, which is what ends one accumulation window.
    private var dirtyBaseVersion: UInt64
    /// Set by `clear()`: the shelves moved, so no region describes the
    /// difference and every consumer needs the whole atlas.
    private var needsFullUpdate = false

    /// What a consumer has to upload to be current with these pixels.
    /// `GlyphAtlasSnapshot` carries this verbatim; the decision itself is
    /// the backend's, via `uploadDecision(for:)`.
    public var update: AtlasUpdate {
        if needsFullUpdate {
            return .full
        }
        guard isDirty, let dirtyRegion else {
            return .unchanged
        }
        return .region(dirtyRegion, since: dirtyBaseVersion)
    }

    /// Bumped every time `clear()` recycles the shelf allocator.
    ///
    /// Atlas rects are only meaningful within the generation that handed them
    /// out: after a clear, the same rect addresses a *different* glyph. Anyone
    /// holding a rect across a paint pass (`ScenePainter` holds one per emitted
    /// `GlyphPrimitive`) must compare this before shipping it, or the scene
    /// draws — and caches — the wrong characters.
    public private(set) var generation: UInt64 = 0

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
        self.dirtyRegion = nil
        self.dirtyBaseVersion = contentVersion
    }

    public func allocate(width glyphWidth: Int32, height glyphHeight: Int32) -> (x: Int32, y: Int32)? {
        guard glyphWidth > 0, glyphHeight > 0,
            glyphWidth <= self.width, glyphHeight <= self.height
        else {
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

    public func writePixels(
        _ glyphPixels: Data, at x: Int32, y: Int32, width glyphWidth: Int32, height glyphHeight: Int32
    ) {
        let bytesPerPixel = 4
        let atlasStride = Int(self.width) * bytesPerPixel
        let glyphStride = Int(glyphWidth) * bytesPerPixel

        for row in 0..<Int(glyphHeight) {
            let dstOffset = (Int(y) + row) * atlasStride + Int(x) * bytesPerPixel
            let srcOffset = row * glyphStride
            let count = glyphStride

            guard srcOffset + count <= glyphPixels.count,
                dstOffset + count <= pixels.count
            else {
                continue
            }

            pixels.replaceSubrange(
                dstOffset..<(dstOffset + count),
                with: glyphPixels[srcOffset..<(srcOffset + count)])
        }

        isDirty = true
        contentVersion = RenderContentVersion.next()
        let nextRegion = GlyphAtlasRegion(x: x, y: y, width: glyphWidth, height: glyphHeight)
        dirtyRegion =
            dirtyRegion.map { existing in
                let minX = min(existing.x, nextRegion.x)
                let minY = min(existing.y, nextRegion.y)
                let maxX = max(existing.x + existing.width, nextRegion.x + nextRegion.width)
                let maxY = max(existing.y + existing.height, nextRegion.y + nextRegion.height)
                return GlyphAtlasRegion(
                    x: minX,
                    y: minY,
                    width: maxX - minX,
                    height: maxY - minY
                )
            } ?? nextRegion
    }

    public func clear() {
        pixels = Data(count: Int(width) * Int(height) * 4)
        shelves.removeAll()
        isDirty = true
        dirtyRegion = GlyphAtlasRegion(x: 0, y: 0, width: width, height: height)
        contentVersion = RenderContentVersion.next()
        needsFullUpdate = true
        generation &+= 1
    }

    /// Ends the current accumulation window: the frame's single consumer
    /// has taken the region, so the next one starts from here. The version
    /// is *not* reset — a consumer that missed this window is caught by the
    /// version comparison and takes a full upload.
    public func markClean() {
        isDirty = false
        dirtyRegion = nil
        needsFullUpdate = false
        dirtyBaseVersion = contentVersion
    }
}
