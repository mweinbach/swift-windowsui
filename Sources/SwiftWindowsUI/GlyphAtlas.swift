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
    /// Vertical frame `bearingY` is measured in. Carried through the cache so
    /// the painter anchors a raster against the origin it was measured from
    /// instead of assuming both rasterizers agree — they do not.
    var verticalFrame: GlyphVerticalFrame = .layoutBoxTop

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

    init(
        atlasX: Int32,
        atlasY: Int32,
        width: Int32,
        height: Int32,
        bearingX: Float,
        bearingY: Float,
        advance: Float,
        verticalFrame: GlyphVerticalFrame
    ) {
        self.init(
            atlasX: atlasX,
            atlasY: atlasY,
            width: width,
            height: height,
            bearingX: bearingX,
            bearingY: bearingY,
            advance: advance
        )
        self.verticalFrame = verticalFrame
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

    /// Bumped every time the allocator hands out space that was already
    /// handed out once — `clear()` recycling every shelf, or `allocate`
    /// satisfying a request from a span `deallocate` returned.
    ///
    /// Atlas rects are only meaningful within the generation that handed them
    /// out: after a recycle, the same rect addresses a *different* glyph.
    /// Anyone holding a rect across a paint pass (`ScenePainter` holds one per
    /// emitted `GlyphPrimitive`) must compare this before shipping it, or the
    /// scene draws — and caches — the wrong characters.
    public private(set) var generation: UInt64 = 0

    private var shelves: [Shelf] = []
    /// `shelves` index by shelf `y`. Every allocation on a shelf sits at that
    /// shelf's `y`, so a freed rect's `atlasY` identifies its shelf exactly.
    private var shelfIndexByY: [Int32: Int] = [:]

    struct Shelf {
        var y: Int32
        var height: Int32
        /// Frontier: the width of this shelf that has *ever* been handed out.
        /// It only grows. Space comes back through `freeSpans`, never by
        /// rewinding this, so "below the frontier" always means "a rect for
        /// this space was minted at some point".
        var usedWidth: Int32
        /// Space returned by `deallocate`, sorted by `x` and coalesced.
        ///
        /// Reusing one of these is the only allocation that can alias a rect
        /// someone else is still holding, which is why it — and only it —
        /// bumps `generation`. Keeping reclaimed space in its own list rather
        /// than rewinding `usedWidth` is what makes that distinction
        /// expressible: virgin frontier space is free to hand out silently.
        var freeSpans: [FreeSpan] = []
    }

    struct FreeSpan {
        var x: Int32
        var width: Int32
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

        if newShelfY + glyphHeight <= self.height {
            let newShelf = Shelf(y: newShelfY, height: glyphHeight, usedWidth: glyphWidth)
            shelves.append(newShelf)
            shelfIndexByY[newShelfY] = shelves.count - 1
            return (x: 0, y: newShelfY)
        }

        // Virgin space is gone. Before declaring exhaustion — which costs the
        // caller a full `clear()` and every glyph in the atlas — hand back
        // space an eviction returned. This is the one allocation that can
        // alias a live rect, so it bumps `generation`; the painter's retry
        // and the runtime's cached-scene check are exactly the machinery that
        // already handles that, and paying it beats re-rasterizing the whole
        // atlas.
        return allocateFromFreeSpan(width: glyphWidth, height: glyphHeight)
    }

    private func allocateFromFreeSpan(width glyphWidth: Int32, height glyphHeight: Int32) -> (x: Int32, y: Int32)? {
        for i in shelves.indices where glyphHeight <= shelves[i].height {
            guard let spanIndex = shelves[i].freeSpans.firstIndex(where: { $0.width >= glyphWidth }) else {
                continue
            }
            let span = shelves[i].freeSpans[spanIndex]
            if span.width == glyphWidth {
                shelves[i].freeSpans.remove(at: spanIndex)
            } else {
                shelves[i].freeSpans[spanIndex] = FreeSpan(x: span.x + glyphWidth, width: span.width - glyphWidth)
            }
            generation &+= 1
            return (x: span.x, y: shelves[i].y)
        }
        return nil
    }

    /// Returns a rect to the allocator. The pixels are deliberately left
    /// alone: nothing addresses them until the space is handed out again, and
    /// zeroing here would dirty a region no consumer needs to see. The
    /// rewrite that *does* matter goes through `writePixels`, which bumps
    /// `contentVersion` and unions the region like any other write.
    ///
    /// A rect this atlas never handed out, or one already free, is ignored:
    /// merging it would corrupt the free list, and the caller that
    /// double-freed has a bug that a silent corruption would hide.
    public func deallocate(x: Int32, y: Int32, width freedWidth: Int32, height freedHeight: Int32) {
        guard freedWidth > 0, freedHeight > 0, x >= 0, freedWidth <= self.width - x,
            let shelfIndex = shelfIndexByY[y],
            freedHeight <= shelves[shelfIndex].height,
            x + freedWidth <= shelves[shelfIndex].usedWidth
        else {
            return
        }

        var spans = shelves[shelfIndex].freeSpans
        let overlapsExistingSpan = spans.contains { $0.x < x + freedWidth && x < $0.x + $0.width }
        guard !overlapsExistingSpan else {
            return
        }

        let insertionIndex = spans.firstIndex { $0.x > x } ?? spans.count
        spans.insert(FreeSpan(x: x, width: freedWidth), at: insertionIndex)

        // Coalesce with the neighbours so two adjacent single-glyph frees can
        // satisfy one double-width glyph; without this, fragmentation makes
        // reclamation useless well before the space runs out.
        var coalesced: [FreeSpan] = []
        coalesced.reserveCapacity(spans.count)
        for span in spans {
            if var last = coalesced.last, last.x + last.width == span.x {
                last.width += span.width
                coalesced[coalesced.count - 1] = last
            } else {
                coalesced.append(span)
            }
        }
        shelves[shelfIndex].freeSpans = coalesced
    }

    /// Total reclaimed-but-unallocated width across every shelf. Test seam for
    /// "eviction actually returned the space".
    var reclaimableWidthForTesting: Int32 {
        shelves.reduce(0) { total, shelf in
            total + shelf.freeSpans.reduce(0) { $0 + $1.width }
        }
    }

    var shelfCountForTesting: Int {
        shelves.count
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
        shelfIndexByY.removeAll()
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
