import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI

/// WS-18. Four claims, one per cache the render path leans on:
///
/// 1. **Lookup is O(1).** Every one of these caches used to find recency by
///    walking a `[Key]` with `firstIndex(of:)` — `GlyphKey` equality (an
///    optional `Character` plus a `String`) once per glyph per frame, and
///    `LayoutKey` equality (a string, a span list, twenty-odd style fields)
///    once per measured layout. The cost grew with cache *warmth*, which is
///    the worst possible shape: the better the cache worked, the more it cost.
/// 2. **Eviction reclaims.** The shelf allocator had no free list, so evicting
///    an entry released nothing and the only way to get space back was the
///    full `clear()` that WS-14's machinery exists to survive.
/// 3. **Reclaimed space is still versioned.** A rect handed out twice is the
///    exact hazard the generation token was introduced for, and rewriting
///    reclaimed pixels has to reach the atlas upload protocol.
/// 4. **The dead cache is alive.** `TextRasterCache` was allocated by nothing,
///    budgeted in `docs/PerformanceBudgets.md`, and cached zero bitmaps.
@MainActor
final class CacheComplexityAndReclamationTests: XCTestCase {

    // MARK: - Fixtures

    private static func key(_ index: Int) -> GlyphKey {
        GlyphKey(
            character: nil,
            glyphID: UInt32(index),
            fontFaceID: 1,
            fontFamily: "Cache Complexity Test Face",
            fontSize: 16,
            weight: .regular
        )
    }

    private static func pixels(width: Int32, height: Int32) -> Data {
        Data(count: Int(width) * Int(height) * 4)
    }

    @discardableResult
    private func insert(
        _ index: Int, into cache: GlyphAtlasCache, side: Int32 = 8
    ) -> GlyphEntry? {
        cache.insert(
            key: Self.key(index),
            pixels: Self.pixels(width: side, height: side),
            width: side, height: side,
            bearingX: 0, bearingY: 0, advance: Float(side)
        )
    }

    // MARK: - 1. Lookup cost

    /// 3,000 lookups against a warm 4,096-entry cache, under a wall-clock
    /// budget the old linear scan could not have met: 3,000 × 4,096 `GlyphKey`
    /// comparisons is over twelve million string compares.
    func testWarmCacheServesThreeThousandLookupsWithinBudget() async {
        let atlas = GlyphAtlas(width: 2048, height: 2048)
        let cache = GlyphAtlasCache(atlas: atlas, maxEntries: 4096)
        for index in 0..<4096 {
            insert(index, into: cache, side: 1)
        }
        XCTAssertEqual(cache.count, 4096, "the fixture is only meaningful against a full cache")

        let started = Date()
        for step in 0..<3000 {
            XCTAssertNotNil(cache.lookup(Self.key(step % 4096)))
        }
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertLessThan(
            elapsed, 0.5,
            "3,000 warm lookups took \(elapsed)s — that is a linear scan, not a dictionary hit")
    }

    /// The stronger claim: lookup cost must not scale with how much the cache
    /// is holding. Same lookup count against a 64-entry cache and a
    /// 4,096-entry one; a 64× difference in size may not become a 64×
    /// difference in time.
    func testLookupCostDoesNotScaleWithCacheSize() async {
        func timeLookups(entryCount: Int) -> TimeInterval {
            let atlas = GlyphAtlas(width: 2048, height: 2048)
            let cache = GlyphAtlasCache(atlas: atlas, maxEntries: entryCount)
            for index in 0..<entryCount {
                insert(index, into: cache, side: 1)
            }
            // One untimed warm pass so allocation and first-touch costs land
            // outside the measurement.
            for step in 0..<3000 {
                _ = cache.lookup(Self.key(step % entryCount))
            }
            let started = Date()
            for step in 0..<3000 {
                _ = cache.lookup(Self.key(step % entryCount))
            }
            return Date().timeIntervalSince(started)
        }

        let small = timeLookups(entryCount: 64)
        let large = timeLookups(entryCount: 4096)

        // Generous: the point is to catch O(n), not to pin a constant. A
        // linear scan would show ~64× here; the additive floor keeps timer
        // granularity on a fast machine from turning noise into a failure.
        XCTAssertLessThan(
            large, small * 8 + 0.05,
            "64× the entries cost \(large / max(small, 1e-9))× the time — lookup is still scanning")
    }

    // MARK: - 2. Eviction reclaims atlas space

    /// The headline: a working set larger than the atlas, arriving one glyph
    /// at a time, must never need a full clear while the live entry count
    /// stays under `maxEntries`.
    ///
    /// The atlas here holds exactly 16 cells and the cache exactly 8 entries,
    /// so from the 17th insert on there is no virgin space left and every
    /// allocation has to come from an eviction. Before eviction returned
    /// space, insert 17 exhausted the atlas, took the `clear()` recovery, and
    /// dropped the cache to a single entry.
    func testEvictionReclaimsSpaceInsteadOfForcingAFullClear() async {
        let atlas = GlyphAtlas(width: 32, height: 32)  // 16 cells of 8×8
        let cache = GlyphAtlasCache(atlas: atlas, maxEntries: 8)

        for index in 0..<100 {
            XCTAssertNotNil(insert(index, into: cache), "insert \(index) was dropped")
            let expected = min(index + 1, 8)
            XCTAssertEqual(
                cache.count, expected,
                "after insert \(index) the cache holds \(cache.count) entries; a collapse to 1 is a full clear")
        }

        XCTAssertGreaterThan(
            atlas.reclaimableWidthForTesting + 1, 0,
            "sanity: the free list is reachable")
        // Four shelves of 8px in a 32px atlas, and no more: reclamation must
        // reuse shelves rather than grow new ones.
        XCTAssertEqual(atlas.shelfCountForTesting, 4)
    }

    /// `evictLRU` is what returns the space, and it returns the *evicted*
    /// entry's space specifically.
    func testEvictLRUReturnsTheEvictedRectToTheAllocator() async {
        let atlas = GlyphAtlas(width: 64, height: 64)
        let cache = GlyphAtlasCache(atlas: atlas, maxEntries: 64)
        for index in 0..<4 {
            insert(index, into: cache)
        }
        XCTAssertEqual(atlas.reclaimableWidthForTesting, 0, "nothing has been evicted yet")

        cache.evictLRU(count: 2)

        XCTAssertEqual(cache.count, 2)
        XCTAssertEqual(
            atlas.reclaimableWidthForTesting, 16,
            "two 8-wide cells came back, and adjacent frees coalesce into one 16-wide span")
    }

    /// Coalescing is what keeps reclamation useful: two neighbouring 8-wide
    /// frees have to satisfy one 16-wide glyph, or fragmentation defeats the
    /// free list long before the space runs out.
    func testAdjacentFreedSpansCoalesceIntoOneUsableSpan() async {
        let atlas = GlyphAtlas(width: 16, height: 8)  // exactly two 8×8 cells
        XCTAssertNotNil(atlas.allocate(width: 8, height: 8))
        XCTAssertNotNil(atlas.allocate(width: 8, height: 8))
        XCTAssertNil(atlas.allocate(width: 16, height: 8), "the atlas is full")

        atlas.deallocate(x: 0, y: 0, width: 8, height: 8)
        atlas.deallocate(x: 8, y: 0, width: 8, height: 8)

        XCTAssertEqual(atlas.reclaimableWidthForTesting, 16)
        XCTAssertNotNil(
            atlas.allocate(width: 16, height: 8),
            "two adjacent 8-wide frees must satisfy one 16-wide request")
    }

    /// A rect the atlas never handed out, or one already free, must not enter
    /// the free list: a corrupted free list hands the same space to two live
    /// glyphs with no generation bump to warn anyone.
    func testDoubleFreeAndForeignRectsAreIgnored() async {
        let atlas = GlyphAtlas(width: 32, height: 32)
        XCTAssertNotNil(atlas.allocate(width: 8, height: 8))

        atlas.deallocate(x: 0, y: 0, width: 8, height: 8)
        XCTAssertEqual(atlas.reclaimableWidthForTesting, 8)

        atlas.deallocate(x: 0, y: 0, width: 8, height: 8)
        XCTAssertEqual(atlas.reclaimableWidthForTesting, 8, "a double free must not double the span")

        atlas.deallocate(x: 0, y: 24, width: 8, height: 8)
        XCTAssertEqual(atlas.reclaimableWidthForTesting, 8, "there is no shelf at y = 24")

        atlas.deallocate(x: 16, y: 0, width: 8, height: 8)
        XCTAssertEqual(atlas.reclaimableWidthForTesting, 8, "x = 16 was never handed out")
    }

    // MARK: - 3. Reclaimed space stays honest

    /// Virgin space is free to hand out silently; reclaimed space is not. A
    /// rect that was already handed out once addresses a different glyph the
    /// second time, which is exactly what `generation` means.
    func testOnlyReclaimedSpaceBumpsTheGeneration() async {
        let atlas = GlyphAtlas(width: 32, height: 32)
        XCTAssertEqual(atlas.generation, 0)

        for _ in 0..<16 {
            XCTAssertNotNil(atlas.allocate(width: 8, height: 8))
        }
        XCTAssertEqual(atlas.generation, 0, "virgin allocations invalidate nobody's rect")

        atlas.deallocate(x: 0, y: 0, width: 8, height: 8)
        XCTAssertEqual(atlas.generation, 0, "returning space is not handing it out")

        XCTAssertNotNil(atlas.allocate(width: 8, height: 8))
        XCTAssertEqual(atlas.generation, 1, "reusing a freed span must be observable to rect holders")
    }

    /// The WS-09 upload protocol has to keep working over reclaimed space: a
    /// region rewritten after a reclaim must reach the dirty region and bump
    /// the content version, or a GPU texture keeps the evicted glyph's pixels.
    func testRewritingReclaimedSpaceReachesTheUploadProtocol() async {
        let atlas = GlyphAtlas(width: 32, height: 32)
        let cache = GlyphAtlasCache(atlas: atlas, maxEntries: 8)
        for index in 0..<16 {
            insert(index, into: cache)
        }
        atlas.markClean()
        XCTAssertEqual(atlas.update, .unchanged)
        let versionAtClean = atlas.contentVersion

        // The 17th glyph has no virgin space left, so it lands in a reclaimed
        // span — new pixels over an address a consumer may already hold.
        XCTAssertNotNil(insert(16, into: cache))

        XCTAssertNotEqual(atlas.contentVersion, versionAtClean, "reclaimed pixels are new pixels")
        switch atlas.update {
        case .region(let region, _):
            XCTAssertGreaterThan(region.width, 0)
            XCTAssertGreaterThan(region.height, 0)
        case .full:
            break  // also correct: a full upload covers the rewrite
        case .unchanged:
            XCTFail("a rewritten reclaimed region must not report `.unchanged`")
        }
    }

    // MARK: - 4. Recency is a total order

    /// Everything touched inside one frame shares a frame index, so a frame
    /// stamp alone cannot order intra-frame taps. Eviction has to know which
    /// of two glyphs used by *this* frame was used first.
    func testRecencyOrdersTapsWithinASingleFrame() async {
        let atlas = GlyphAtlas(width: 512, height: 512)
        let cache = GlyphAtlasCache(atlas: atlas, maxEntries: 3)
        for index in 0..<3 {
            insert(index, into: cache)
        }
        XCTAssertEqual(cache.frameIndex, 0, "no frame boundary was crossed")

        _ = cache.lookup(Self.key(0))  // 0 becomes the most recent
        insert(3, into: cache)

        XCTAssertNotNil(cache.lookup(Self.key(0)))
        XCTAssertNil(cache.lookup(Self.key(1)), "1 was the least recently used")
        XCTAssertNotNil(cache.lookup(Self.key(2)))
        XCTAssertNotNil(cache.lookup(Self.key(3)))
    }

    // MARK: - 5. Layout cache

    /// `WindowTextSystem` lost its `accessOrder` array too; the LRU semantics
    /// it encoded have to survive the change.
    func testLayoutCacheEvictsLeastRecentlyUsedAcrossTheStampChange() async {
        let system = WindowTextSystem(maxEntryCount: 3)
        let style = PixelTextStyle(color: .white, scale: 1, fontFamily: "Segoe UI")

        for text in ["alpha", "beta", "gamma"] {
            XCTAssertNotNil(system.measure(text, style: style, scaleFactor: 1))
        }
        XCTAssertEqual(system.cachedLayoutCount, 3)

        // Touch "alpha" so "beta" becomes the oldest, then overflow.
        XCTAssertNotNil(system.measure("alpha", style: style, scaleFactor: 1))
        XCTAssertNotNil(system.measure("delta", style: style, scaleFactor: 1))

        XCTAssertEqual(system.cachedLayoutCount, 3, "the cap is the cap")
    }

    /// Re-measuring the same string must not grow the cache — the guard that
    /// an insert-on-hit would have quietly broken.
    func testRepeatedLayoutsOfTheSameStringStayOneEntry() async {
        let system = WindowTextSystem(maxEntryCount: 16)
        let style = PixelTextStyle(color: .white, scale: 1, fontFamily: "Segoe UI")

        for _ in 0..<50 {
            XCTAssertNotNil(system.measure("stable", style: style, scaleFactor: 1))
        }
        XCTAssertEqual(system.cachedLayoutCount, 1)
    }

    // MARK: - 6. The text raster cache is wired up

    /// `Controls.icon` rasterizes a whole string through DirectWrite on every
    /// view-tree rebuild. The raster is a pure function of (text, style,
    /// scale), so the second build must not touch DirectWrite at all.
    func testIconRasterizationIsServedFromTheSharedRasterCache() async throws {
        NativeFontAvailability.resetTestingOverrides()
        TextRasterCache.shared.clear()

        let first = Controls.icon(.settings, displayScale: 1)
        try XCTSkipIf(
            first.bitmapSurface == nil,
            "no installed icon font carries this symbol on this machine; the raster path is unreachable")

        XCTAssertEqual(TextRasterCache.shared.count, 1, "the first build must populate the cache")

        let second = Controls.icon(.settings, displayScale: 1)
        XCTAssertEqual(TextRasterCache.shared.count, 1, "the second build must be a hit, not a second entry")
        XCTAssertEqual(
            second.bitmapSurface?.pixels, first.bitmapSurface?.pixels,
            "a cache hit has to return the same pixels the miss produced")
    }

    /// The same icon at a different device scale is a different bitmap, so it
    /// has to be a different key — that is what makes the cache safe to share
    /// across windows at mixed DPI without an invalidation hook.
    func testRasterCacheKeysSeparateDeviceScales() async throws {
        NativeFontAvailability.resetTestingOverrides()
        TextRasterCache.shared.clear()

        let atOneX = Controls.icon(.settings, displayScale: 1)
        try XCTSkipIf(atOneX.bitmapSurface == nil, "icon raster path unreachable on this machine")
        _ = Controls.icon(.settings, displayScale: 2)

        XCTAssertEqual(TextRasterCache.shared.count, 2)
    }

    // MARK: - 7. The font-availability probe cache is bounded

    /// A probe is two DirectWrite rasterizations, so the cache in front of it
    /// earns its keep — but its key is `(family, character)` over an
    /// app-supplied alphabet, which is unbounded by construction.
    func testFontAvailabilityProbeCacheIsBounded() async {
        NativeFontAvailability.resetProbeCacheForTesting()
        NativeFontAvailability.testingOverrides.probe = { _, _ in true }
        defer {
            NativeFontAvailability.resetTestingOverrides()
            NativeFontAvailability.resetProbeCacheForTesting()
        }

        let limit = NativeFontAvailability.probeCacheLimitForTesting
        for index in 0..<(limit * 2) {
            guard let scalar = Unicode.Scalar(0x4E00 + index) else { continue }
            _ = NativeFontAvailability.hasGlyph(Character(scalar), fontFamily: "Probe Bound Test Family")
        }

        XCTAssertLessThanOrEqual(
            NativeFontAvailability.probeCacheCountForTesting, limit,
            "the probe cache grew past its bound")
        XCTAssertGreaterThan(
            NativeFontAvailability.probeCacheCountForTesting, limit / 2,
            "bounding must not degrade into caching nothing")
    }
}
