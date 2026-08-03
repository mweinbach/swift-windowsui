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

    /// Value of `accessClock` at the last frame boundary. An entry stamped
    /// above this was touched by the frame in flight.
    private var frameStartAccessClock: UInt64 = 0

    /// Set when freeing an entry's atlas cell took a cell the *current* frame
    /// had already used.
    ///
    /// This is the one way a single paint pass can alias a rect it already
    /// emitted: the cell goes back to the allocator, the next glyph reuses it,
    /// and the primitive emitted earlier now samples someone else's pixels.
    /// Freeing a cell no one has touched this frame cannot do that — nothing in
    /// this pass is addressing it — which is what lets `ScenePainter` tell a
    /// reclaim it has to repaint for from one it can ship. Reset per paint
    /// attempt by `beginPass()`, because an attempt re-emits everything.
    private(set) var didFreeCellUsedThisFrame = false

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

    /// Entries visited by a linear scan since `resetScanCounterForTesting()`.
    ///
    /// The claim this cache exists to make is that a lookup costs one hash and
    /// nothing that grows with how much the cache holds. A wall-clock budget is
    /// the wrong instrument for that claim — `docs/PerformanceBudgets.md`
    /// forbids one outright, because a timing gate flakes on a loaded runner —
    /// so the scan is *counted* instead. `lookup` and `peek` never touch this;
    /// eviction, the one place a scan is legitimate, adds the entries it
    /// walked. A regression to `accessOrder.firstIndex(of:)` shows up here as a
    /// non-zero count on a pure-lookup workload, on any machine, at any load.
    private(set) var scannedEntriesForTesting: Int = 0

    func resetScanCounterForTesting() {
        scannedEntriesForTesting = 0
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
        if let previous = entries[key] {
            noteCellFreed(stampedAt: previous.lastAccessed)
            atlas.deallocate(
                x: previous.entry.atlasX, y: previous.entry.atlasY,
                width: previous.entry.width, height: previous.entry.height)
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
                releaseAtlasSpace(for: entry)
            }
            entries.removeAll(keepingCapacity: true)
            return
        }

        if count == 1 {
            scannedEntriesForTesting += entries.count
            guard
                let oldest = entries.min(by: { $0.value.lastAccessed < $1.value.lastAccessed })
            else {
                return
            }
            releaseAtlasSpace(for: oldest.value)
            entries.removeValue(forKey: oldest.key)
            return
        }

        scannedEntriesForTesting += entries.count
        let doomed = entries.sorted { $0.value.lastAccessed < $1.value.lastAccessed }.prefix(count)
        for element in doomed {
            releaseAtlasSpace(for: element.value)
            entries.removeValue(forKey: element.key)
        }
    }

    private func releaseAtlasSpace(for cached: CacheEntry) {
        noteCellFreed(stampedAt: cached.lastAccessed)
        let entry = cached.entry
        atlas.deallocate(x: entry.atlasX, y: entry.atlasY, width: entry.width, height: entry.height)
    }

    private func noteCellFreed(stampedAt stamp: UInt64) {
        if stamp > frameStartAccessClock {
            didFreeCellUsedThisFrame = true
        }
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
        frameStartAccessClock = accessClock
        didFreeCellUsedThisFrame = false
    }

    /// Starts one paint attempt. A retry re-emits every glyph the discarded
    /// attempt did, so the aliasing question is asked again from scratch; the
    /// frame's recency clock is deliberately *not* reset, because the entries
    /// the discarded attempt touched are still this frame's working set.
    func beginPass() {
        didFreeCellUsedThisFrame = false
    }
}
