import XCTest
import Foundation
@testable import SwiftWindowsUI

final class GlyphAtlasTests: XCTestCase {

    // MARK: - Atlas Allocation

    func testAllocateMultipleGlyphsNoOverlap() async {
        let atlas = await MainActor.run { GlyphAtlas(width: 256, height: 256) }

        let positions: [(x: Int32, y: Int32)] = await MainActor.run {
            var results: [(x: Int32, y: Int32)] = []
            for _ in 0..<5 {
                if let pos = atlas.allocate(width: 10, height: 12) {
                    results.append(pos)
                }
            }
            return results
        }

        XCTAssertEqual(positions.count, 5)

        // Verify no two allocations overlap by checking rectangles
        for i in 0..<positions.count {
            for j in (i + 1)..<positions.count {
                let a = positions[i]
                let b = positions[j]
                let aRight = a.x + 10
                let aBottom = a.y + 12
                let bRight = b.x + 10
                let bBottom = b.y + 12

                let overlapsX = a.x < bRight && b.x < aRight
                let overlapsY = a.y < bBottom && b.y < aBottom
                XCTAssertFalse(overlapsX && overlapsY, "Allocations \(i) and \(j) overlap")
            }
        }
    }

    func testShelfPackingCreatesShelvesForVaryingHeights() async {
        let atlas = await MainActor.run { GlyphAtlas(width: 100, height: 100) }

        let result = await MainActor.run { () -> [(x: Int32, y: Int32)] in
            var positions: [(x: Int32, y: Int32)] = []

            // First glyph: 20x10 -> shelf 0 at y=0, height=10
            if let pos = atlas.allocate(width: 20, height: 10) { positions.append(pos) }
            // Second glyph: 20x10 -> fits in shelf 0
            if let pos = atlas.allocate(width: 20, height: 10) { positions.append(pos) }
            // Third glyph: 20x15 -> too tall for shelf 0 (height=10), creates shelf 1 at y=10
            if let pos = atlas.allocate(width: 20, height: 15) { positions.append(pos) }

            return positions
        }

        XCTAssertEqual(result.count, 3)
        // First two should be on the same shelf (same y)
        XCTAssertEqual(result[0].y, result[1].y)
        // Third should be on a new shelf below
        XCTAssertGreaterThan(result[2].y, result[0].y)
        // The new shelf starts after the first shelf's height (10)
        XCTAssertEqual(result[2].y, 10)
    }

    func testAtlasFullReturnsNil() async {
        // Tiny atlas: 32x32
        let atlas = await MainActor.run { GlyphAtlas(width: 32, height: 32) }

        let result = await MainActor.run { () -> (Int, Bool) in
            var allocated = 0
            // Each glyph is 16x16, so we can fit at most 4 (2x2 grid)
            for _ in 0..<10 {
                if atlas.allocate(width: 16, height: 16) != nil {
                    allocated += 1
                }
            }
            // One more should fail
            let overflowed = atlas.allocate(width: 16, height: 16) == nil
            return (allocated, overflowed)
        }

        XCTAssertEqual(result.0, 4)
        XCTAssertTrue(result.1, "Atlas should return nil when full")
    }

    func testAllocateRejectsZeroOrNegativeDimensions() async {
        let atlas = await MainActor.run { GlyphAtlas(width: 256, height: 256) }

        await MainActor.run {
            XCTAssertNil(atlas.allocate(width: 0, height: 10))
            XCTAssertNil(atlas.allocate(width: 10, height: 0))
            XCTAssertNil(atlas.allocate(width: -1, height: 10))
            XCTAssertNil(atlas.allocate(width: 10, height: -1))
        }
    }

    func testAllocateRejectsGlyphLargerThanAtlas() async {
        let atlas = await MainActor.run { GlyphAtlas(width: 64, height: 64) }

        await MainActor.run {
            XCTAssertNil(atlas.allocate(width: 65, height: 10))
            XCTAssertNil(atlas.allocate(width: 10, height: 65))
        }
    }

    // MARK: - Pixel Writing

    func testWritePixelsAtCorrectOffset() async {
        let atlas = await MainActor.run { GlyphAtlas(width: 64, height: 64) }

        await MainActor.run {
            // Allocate a 2x2 glyph
            guard let pos = atlas.allocate(width: 2, height: 2) else {
                XCTFail("Allocation should succeed")
                return
            }

            // Create BGRA pixel data: 2x2 = 16 bytes
            // Pixel (0,0) = blue (255,0,0,255), Pixel (1,0) = green (0,255,0,255)
            // Pixel (0,1) = red (0,0,255,255), Pixel (1,1) = white (255,255,255,255)
            var glyphPixels = Data(count: 16)
            // Row 0
            glyphPixels[0] = 255; glyphPixels[1] = 0; glyphPixels[2] = 0; glyphPixels[3] = 255
            glyphPixels[4] = 0; glyphPixels[5] = 255; glyphPixels[6] = 0; glyphPixels[7] = 255
            // Row 1
            glyphPixels[8] = 0; glyphPixels[9] = 0; glyphPixels[10] = 255; glyphPixels[11] = 255
            glyphPixels[12] = 255; glyphPixels[13] = 255; glyphPixels[14] = 255; glyphPixels[15] = 255

            atlas.writePixels(glyphPixels, at: pos.x, y: pos.y, width: 2, height: 2)

            // Verify pixel data in atlas at the correct offset
            let stride = Int(atlas.width) * 4
            let baseOffset = Int(pos.y) * stride + Int(pos.x) * 4

            // Check pixel (0,0) - blue
            XCTAssertEqual(atlas.pixels[baseOffset], 255)
            XCTAssertEqual(atlas.pixels[baseOffset + 1], 0)
            XCTAssertEqual(atlas.pixels[baseOffset + 2], 0)
            XCTAssertEqual(atlas.pixels[baseOffset + 3], 255)

            // Check pixel (1,0) - green
            XCTAssertEqual(atlas.pixels[baseOffset + 4], 0)
            XCTAssertEqual(atlas.pixels[baseOffset + 5], 255)
            XCTAssertEqual(atlas.pixels[baseOffset + 6], 0)
            XCTAssertEqual(atlas.pixels[baseOffset + 7], 255)

            // Check pixel (0,1) - red (next row)
            let row1Offset = baseOffset + stride
            XCTAssertEqual(atlas.pixels[row1Offset], 0)
            XCTAssertEqual(atlas.pixels[row1Offset + 1], 0)
            XCTAssertEqual(atlas.pixels[row1Offset + 2], 255)
            XCTAssertEqual(atlas.pixels[row1Offset + 3], 255)
        }
    }

    // MARK: - UV Coordinates

    func testUVRectComputation() {
        let entry = GlyphEntry(
            atlasX: 100,
            atlasY: 200,
            width: 50,
            height: 60,
            bearingX: 2.0,
            bearingY: 10.0,
            advance: 12.0
        )

        let uv = entry.uvRect(atlasWidth: 1000, atlasHeight: 1000)

        XCTAssertEqual(uv.u0, 0.1, accuracy: 0.0001)
        XCTAssertEqual(uv.v0, 0.2, accuracy: 0.0001)
        XCTAssertEqual(uv.u1, 0.15, accuracy: 0.0001)
        XCTAssertEqual(uv.v1, 0.26, accuracy: 0.0001)
    }

    func testUVRectWithDefaultAtlasSize() {
        let entry = GlyphEntry(
            atlasX: 0,
            atlasY: 0,
            width: 2048,
            height: 2048,
            bearingX: 0,
            bearingY: 0,
            advance: 0
        )

        let uv = entry.uvRect(atlasWidth: 2048, atlasHeight: 2048)

        XCTAssertEqual(uv.u0, 0.0, accuracy: 0.0001)
        XCTAssertEqual(uv.v0, 0.0, accuracy: 0.0001)
        XCTAssertEqual(uv.u1, 1.0, accuracy: 0.0001)
        XCTAssertEqual(uv.v1, 1.0, accuracy: 0.0001)
    }

    // MARK: - Dirty Flag

    func testDirtyFlagStartsClean() async {
        let atlas = await MainActor.run { GlyphAtlas(width: 64, height: 64) }
        let dirty = await MainActor.run { atlas.isDirty }
        XCTAssertFalse(dirty)
    }

    func testDirtyAfterWriteCleanAfterMark() async {
        let atlas = await MainActor.run { GlyphAtlas(width: 64, height: 64) }

        await MainActor.run {
            _ = atlas.allocate(width: 4, height: 4)
            let pixels = Data(count: 64)
            atlas.writePixels(pixels, at: 0, y: 0, width: 4, height: 4)
            XCTAssertTrue(atlas.isDirty)

            atlas.markClean()
            XCTAssertFalse(atlas.isDirty)
        }
    }

    func testDirtyAfterClear() async {
        let atlas = await MainActor.run { GlyphAtlas(width: 64, height: 64) }

        await MainActor.run {
            atlas.clear()
            XCTAssertTrue(atlas.isDirty)
        }
    }

    // MARK: - Atlas Clear

    func testClearResetsAllocations() async {
        let atlas = await MainActor.run { GlyphAtlas(width: 32, height: 32) }

        await MainActor.run {
            // Fill the atlas
            _ = atlas.allocate(width: 32, height: 32)
            XCTAssertNil(atlas.allocate(width: 1, height: 1))

            // Clear and try again
            atlas.clear()
            XCTAssertNotNil(atlas.allocate(width: 32, height: 32))
        }
    }

    // MARK: - Cache Lookup

    func testCacheLookupAfterInsert() async {
        let atlas = await MainActor.run { GlyphAtlas(width: 256, height: 256) }
        let cache = await MainActor.run { GlyphAtlasCache(atlas: atlas) }

        let result = await MainActor.run { () -> GlyphEntry? in
            let key = GlyphKey(character: "A", fontFamily: "Segoe UI", fontSize: 16.0, weight: .regular)
            let pixels = Data(count: 10 * 12 * 4)
            _ = cache.insert(key: key, pixels: pixels, width: 10, height: 12, bearingX: 1.0, bearingY: 10.0, advance: 11.0)
            return cache.lookup(key)
        }

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.width, 10)
        XCTAssertEqual(result?.height, 12)
        XCTAssertEqual(result?.bearingX, 1.0)
        XCTAssertEqual(result?.bearingY, 10.0)
        XCTAssertEqual(result?.advance, 11.0)
    }

    func testCacheMissReturnsNil() async {
        let atlas = await MainActor.run { GlyphAtlas(width: 256, height: 256) }
        let cache = await MainActor.run { GlyphAtlasCache(atlas: atlas) }

        let result = await MainActor.run {
            cache.lookup(GlyphKey(character: "Z", fontFamily: "Arial", fontSize: 14.0, weight: .bold))
        }

        XCTAssertNil(result)
    }

    func testCacheMissForDifferentWeight() async {
        let atlas = await MainActor.run { GlyphAtlas(width: 256, height: 256) }
        let cache = await MainActor.run { GlyphAtlasCache(atlas: atlas) }

        await MainActor.run {
            let key = GlyphKey(character: "A", fontFamily: "Segoe UI", fontSize: 16.0, weight: .regular)
            let pixels = Data(count: 40)
            _ = cache.insert(key: key, pixels: pixels, width: 1, height: 1, bearingX: 0, bearingY: 0, advance: 0)

            let boldKey = GlyphKey(character: "A", fontFamily: "Segoe UI", fontSize: 16.0, weight: .bold)
            XCTAssertNil(cache.lookup(boldKey))
        }
    }

    // MARK: - LRU Eviction

    func testLRUEvictsOldestEntries() async {
        let atlas = await MainActor.run { GlyphAtlas(width: 512, height: 512) }
        let cache = await MainActor.run { GlyphAtlasCache(atlas: atlas, maxEntries: 3) }

        await MainActor.run {
            let pixels = Data(count: 4 * 4 * 4)
            let keyA = GlyphKey(character: "A", fontFamily: "F", fontSize: 16, weight: .regular)
            let keyB = GlyphKey(character: "B", fontFamily: "F", fontSize: 16, weight: .regular)
            let keyC = GlyphKey(character: "C", fontFamily: "F", fontSize: 16, weight: .regular)
            let keyD = GlyphKey(character: "D", fontFamily: "F", fontSize: 16, weight: .regular)

            _ = cache.insert(key: keyA, pixels: pixels, width: 4, height: 4, bearingX: 0, bearingY: 0, advance: 5)
            _ = cache.insert(key: keyB, pixels: pixels, width: 4, height: 4, bearingX: 0, bearingY: 0, advance: 5)
            _ = cache.insert(key: keyC, pixels: pixels, width: 4, height: 4, bearingX: 0, bearingY: 0, advance: 5)

            XCTAssertEqual(cache.count, 3)

            // Inserting a 4th entry should evict the oldest (A)
            _ = cache.insert(key: keyD, pixels: pixels, width: 4, height: 4, bearingX: 0, bearingY: 0, advance: 5)

            XCTAssertEqual(cache.count, 3)
            XCTAssertNil(cache.lookup(keyA), "Oldest entry should have been evicted")
            XCTAssertNotNil(cache.lookup(keyB))
            XCTAssertNotNil(cache.lookup(keyC))
            XCTAssertNotNil(cache.lookup(keyD))
        }
    }

    func testLookupUpdatesAccessOrder() async {
        let atlas = await MainActor.run { GlyphAtlas(width: 512, height: 512) }
        let cache = await MainActor.run { GlyphAtlasCache(atlas: atlas, maxEntries: 3) }

        await MainActor.run {
            let pixels = Data(count: 4 * 4 * 4)
            let keyA = GlyphKey(character: "A", fontFamily: "F", fontSize: 16, weight: .regular)
            let keyB = GlyphKey(character: "B", fontFamily: "F", fontSize: 16, weight: .regular)
            let keyC = GlyphKey(character: "C", fontFamily: "F", fontSize: 16, weight: .regular)
            let keyD = GlyphKey(character: "D", fontFamily: "F", fontSize: 16, weight: .regular)

            _ = cache.insert(key: keyA, pixels: pixels, width: 4, height: 4, bearingX: 0, bearingY: 0, advance: 5)
            _ = cache.insert(key: keyB, pixels: pixels, width: 4, height: 4, bearingX: 0, bearingY: 0, advance: 5)
            _ = cache.insert(key: keyC, pixels: pixels, width: 4, height: 4, bearingX: 0, bearingY: 0, advance: 5)

            // Access A to make it most recently used
            _ = cache.lookup(keyA)

            // Insert D - should evict B (now the oldest)
            _ = cache.insert(key: keyD, pixels: pixels, width: 4, height: 4, bearingX: 0, bearingY: 0, advance: 5)

            XCTAssertNotNil(cache.lookup(keyA), "A was accessed recently, should not be evicted")
            XCTAssertNil(cache.lookup(keyB), "B should have been evicted as the oldest")
            XCTAssertNotNil(cache.lookup(keyC))
            XCTAssertNotNil(cache.lookup(keyD))
        }
    }

    // MARK: - Cache Clear

    func testCacheClearResetsCount() async {
        let atlas = await MainActor.run { GlyphAtlas(width: 256, height: 256) }
        let cache = await MainActor.run { GlyphAtlasCache(atlas: atlas) }

        await MainActor.run {
            let pixels = Data(count: 4)
            let key = GlyphKey(character: "X", fontFamily: "F", fontSize: 12, weight: .regular)
            _ = cache.insert(key: key, pixels: pixels, width: 1, height: 1, bearingX: 0, bearingY: 0, advance: 1)

            XCTAssertEqual(cache.count, 1)

            cache.clear()

            XCTAssertEqual(cache.count, 0)
            XCTAssertNil(cache.lookup(key))
        }
    }

    // MARK: - Frame Counter

    func testNextFrameAdvancesCounter() async {
        let atlas = await MainActor.run { GlyphAtlas(width: 256, height: 256) }
        let cache = await MainActor.run { GlyphAtlasCache(atlas: atlas) }

        await MainActor.run {
            // Insert a glyph, advance frame, insert another
            let pixels = Data(count: 4)
            let keyA = GlyphKey(character: "A", fontFamily: "F", fontSize: 16, weight: .regular)
            let keyB = GlyphKey(character: "B", fontFamily: "F", fontSize: 16, weight: .regular)

            _ = cache.insert(key: keyA, pixels: pixels, width: 1, height: 1, bearingX: 0, bearingY: 0, advance: 1)
            cache.nextFrame()
            _ = cache.insert(key: keyB, pixels: pixels, width: 1, height: 1, bearingX: 0, bearingY: 0, advance: 1)

            // Both should still be accessible
            XCTAssertNotNil(cache.lookup(keyA))
            XCTAssertNotNil(cache.lookup(keyB))
            XCTAssertEqual(cache.count, 2)
        }
    }

    // MARK: - Explicit Evict

    func testExplicitEvictLRU() async {
        let atlas = await MainActor.run { GlyphAtlas(width: 256, height: 256) }
        let cache = await MainActor.run { GlyphAtlasCache(atlas: atlas, maxEntries: 100) }

        await MainActor.run {
            let pixels = Data(count: 4)
            for i: UInt32 in 0..<5 {
                let key = GlyphKey(character: Character(Unicode.Scalar(65 + i)!), fontFamily: "F", fontSize: 16, weight: .regular)
                _ = cache.insert(key: key, pixels: pixels, width: 1, height: 1, bearingX: 0, bearingY: 0, advance: 1)
            }

            XCTAssertEqual(cache.count, 5)

            cache.evictLRU(count: 2)

            XCTAssertEqual(cache.count, 3)
            // A and B should have been evicted (oldest)
            XCTAssertNil(cache.lookup(GlyphKey(character: "A", fontFamily: "F", fontSize: 16, weight: .regular)))
            XCTAssertNil(cache.lookup(GlyphKey(character: "B", fontFamily: "F", fontSize: 16, weight: .regular)))
            XCTAssertNotNil(cache.lookup(GlyphKey(character: "C", fontFamily: "F", fontSize: 16, weight: .regular)))
        }
    }
}
