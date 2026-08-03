import Foundation

/// Glyph rects, keyed by identity and bounded by `maxEntries`.
///
/// Recency is a per-entry stamp, not a `[GlyphKey]` ordered from front to
/// back. The array version cost `accessOrder.firstIndex(of:)` — a linear scan
/// with `GlyphKey` equality (an optional `Character` plus a `String`) at every
/// tap — *per glyph per frame*, so a text-dense screen paid millions of string
/// comparisons per frame and paid more of them the warmer the cache got.
/// Lookups are now a dictionary hit and one integer store; the only scan left
/// is eviction's, which runs when a *new* glyph arrives at capacity.
@MainActor
public final class GlyphAtlasCache {
    private var entries: [GlyphKey: CacheEntry] = [:]
    private let atlas: GlyphAtlas
    private let maxEntries: Int
    private var frameCounter: UInt64 = 0

    /// Strictly increasing tap counter. `frameCounter` is the wrong clock for
    /// recency on its own: everything touched inside one frame shares its
    /// value, and eviction would then break ties arbitrarily among the glyphs
    /// of the *current* frame. This orders taps totally, so "least recently
    /// used" means what it says even within a frame.
    private var accessClock: UInt64 = 0

    /// Generation of the backing atlas. `insert` recovers from exhaustion by
    /// clearing the atlas, which invalidates every rect handed out before it;
    /// callers holding rects across a batch of inserts compare this instead of
    /// trusting a per-insert flag, so a recovery that happens anywhere in the
    /// batch is still visible at the end of it.
    public var atlasGeneration: UInt64 {
        atlas.generation
    }

    /// LRU clock, advanced once per rendered frame by `nextFrame()`.
    public var frameIndex: UInt64 {
        frameCounter
    }

    struct CacheEntry {
        var entry: GlyphEntry
        /// Value of `accessClock` at the last tap. Total order, so eviction
        /// never has to guess between two entries touched in the same frame.
        var lastAccessed: UInt64
    }

    public init(atlas: GlyphAtlas, maxEntries: Int = 4096) {
        self.atlas = atlas
        self.maxEntries = maxEntries
    }

    private func nextAccessStamp() -> UInt64 {
        accessClock &+= 1
        return accessClock
    }

    public func lookup(_ key: GlyphKey) -> GlyphEntry? {
        // One hash for the whole operation: `index(forKey:)` then an in-place
        // store through `values`. Reading, editing and reassigning the struct
        // hashes the (string-bearing) key twice on the hottest path in text
        // painting.
        guard let index = entries.index(forKey: key) else {
            return nil
        }
        entries.values[index].lastAccessed = nextAccessStamp()
        return entries.values[index].entry
    }

    public func peek(_ key: GlyphKey) -> GlyphEntry? {
        entries[key]?.entry
    }

    public func insert(
        key: GlyphKey,
        pixels: Data,
        width: Int32,
        height: Int32,
        bearingX: Float,
        bearingY: Float,
        advance: Float
    ) -> GlyphEntry? {
        insert(
            key: key,
            pixels: pixels,
            width: width,
            height: height,
            bearingX: bearingX,
            bearingY: bearingY,
            advance: advance,
            verticalFrame: .layoutBoxTop
        )
    }

    func insert(
        key: GlyphKey,
        pixels: Data,
        width: Int32,
        height: Int32,
        bearingX: Float,
        bearingY: Float,
        advance: Float,
        verticalFrame: GlyphVerticalFrame
    ) -> GlyphEntry? {
        // Evict if at capacity
        if entries.count >= maxEntries {
            evictLRU(count: 1)
        }

        guard width > 0,
            height > 0,
            width <= atlas.width,
            height <= atlas.height
        else {
            return nil
        }

        guard
            let entry = insertWithoutRecovery(
                key: key,
                pixels: pixels,
                width: width,
                height: height,
                bearingX: bearingX,
                bearingY: bearingY,
                advance: advance,
                verticalFrame: verticalFrame
            )
        else {
            // Recovery bumps `atlasGeneration`; that bump is the signal every
            // holder of a previously returned rect has to react to.
            clear()
            return insertWithoutRecovery(
                key: key,
                pixels: pixels,
                width: width,
                height: height,
                bearingX: bearingX,
                bearingY: bearingY,
                advance: advance,
                verticalFrame: verticalFrame
            )
        }

        return entry
    }

    private func insertWithoutRecovery(
        key: GlyphKey,
        pixels: Data,
        width: Int32,
        height: Int32,
        bearingX: Float,
        bearingY: Float,
        advance: Float,
        verticalFrame: GlyphVerticalFrame
    ) -> GlyphEntry? {
        guard let position = atlas.allocate(width: width, height: height) else {
            return nil
        }

        atlas.writePixels(pixels, at: position.x, y: position.y, width: width, height: height)

        let entry = GlyphEntry(
            atlasX: position.x,
            atlasY: position.y,
            width: width,
            height: height,
            bearingX: bearingX,
            bearingY: bearingY,
            advance: advance,
            verticalFrame: verticalFrame
        )

        // Re-inserting a key abandons its old rect; hand the space back rather
        // than leak it for the life of the atlas.
        if let previous = entries[key]?.entry {
            atlas.deallocate(
                x: previous.atlasX, y: previous.atlasY, width: previous.width, height: previous.height)
        }

        entries[key] = CacheEntry(entry: entry, lastAccessed: nextAccessStamp())

        return entry
    }

    /// Drops the `count` least recently used entries and returns their atlas
    /// space to the allocator.
    ///
    /// The scan is over stamps, not keys, and it runs only here — eviction is
    /// reached when a *new* glyph arrives at capacity, not on every tap, so
    /// the cost that used to scale with cache warmth now scales with cache
    /// misses.
    public func evictLRU(count: Int) {
        guard count > 0, !entries.isEmpty else {
            return
        }
        guard count < entries.count else {
            for entry in entries.values {
                releaseAtlasSpace(for: entry.entry)
            }
            entries.removeAll(keepingCapacity: true)
            return
        }

        if count == 1 {
            guard
                let oldest = entries.min(by: { $0.value.lastAccessed < $1.value.lastAccessed })
            else {
                return
            }
            releaseAtlasSpace(for: oldest.value.entry)
            entries.removeValue(forKey: oldest.key)
            return
        }

        let doomed = entries.sorted { $0.value.lastAccessed < $1.value.lastAccessed }.prefix(count)
        for element in doomed {
            releaseAtlasSpace(for: element.value.entry)
            entries.removeValue(forKey: element.key)
        }
    }

    private func releaseAtlasSpace(for entry: GlyphEntry) {
        atlas.deallocate(x: entry.atlasX, y: entry.atlasY, width: entry.width, height: entry.height)
    }

    public func clear() {
        entries.removeAll()
        atlas.clear()
    }

    public var count: Int {
        entries.count
    }

    public func nextFrame() {
        frameCounter += 1
    }
}
