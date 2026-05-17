import Foundation

@MainActor
public final class GlyphAtlasCache {
    private var entries: [GlyphKey: CacheEntry] = [:]
    private var accessOrder: [GlyphKey] = []
    private let atlas: GlyphAtlas
    private let maxEntries: Int
    private var frameCounter: UInt64 = 0
    public private(set) var didRecoverFromExhaustionOnLastInsert = false

    struct CacheEntry {
        var entry: GlyphEntry
        var lastAccessed: UInt64
    }

    public init(atlas: GlyphAtlas, maxEntries: Int = 4096) {
        self.atlas = atlas
        self.maxEntries = maxEntries
    }

    public func lookup(_ key: GlyphKey) -> GlyphEntry? {
        guard var cached = entries[key] else {
            return nil
        }

        cached.lastAccessed = frameCounter
        entries[key] = cached

        if let index = accessOrder.firstIndex(of: key) {
            accessOrder.remove(at: index)
            accessOrder.append(key)
        }

        return cached.entry
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
        didRecoverFromExhaustionOnLastInsert = false

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
                advance: advance
            )
        else {
            clear()
            didRecoverFromExhaustionOnLastInsert = true
            return insertWithoutRecovery(
                key: key,
                pixels: pixels,
                width: width,
                height: height,
                bearingX: bearingX,
                bearingY: bearingY,
                advance: advance
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
        advance: Float
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
            advance: advance
        )

        // Remove old entry if re-inserting the same key
        if entries[key] != nil {
            if let index = accessOrder.firstIndex(of: key) {
                accessOrder.remove(at: index)
            }
        }

        entries[key] = CacheEntry(entry: entry, lastAccessed: frameCounter)
        accessOrder.append(key)

        return entry
    }

    public func evictLRU(count: Int) {
        let evictCount = min(count, accessOrder.count)
        for _ in 0..<evictCount {
            let key = accessOrder.removeFirst()
            entries.removeValue(forKey: key)
        }
    }

    public func clear() {
        entries.removeAll()
        accessOrder.removeAll()
        atlas.clear()
    }

    public var count: Int {
        entries.count
    }

    public func nextFrame() {
        frameCounter += 1
    }
}
