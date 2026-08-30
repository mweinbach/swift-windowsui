import Foundation
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI

/// These fixtures exercise the production cache/read orchestration without
/// opening a native file, decoding WIC pixels, sleeping, or using the network.
/// Existing DemoBitmapResourceTests retain the real named-bundle decoder checks.
@MainActor
final class ImageLoaderCacheTests: XCTestCase {
    private func metadata(
        _ identifier: UInt8? = 1, bytes: UInt64 = 2, creation: UInt64 = 7,
        modification: UInt64 = 11, change: Int64? = 13, volume: UInt64 = 5, stream: String = ""
    ) -> ImageLoaderFileMetadata {
        ImageLoaderFileMetadata(
            identity: identifier.map {
                ImageLoaderFileIdentity(
                    volume: volume, identifier: Data(repeating: $0, count: 16), streamName: Array(stream.utf16))
            },
            byteCount: bytes, creationTime: creation, modificationTime: modification, changeTime: change)
    }

    private func bitmap(
        bytes: Int = 4, width: Int32 = 1, height: Int32 = 1, stride: Int32 = 4,
        format: BitmapPixelFormat = .bgra8Straight
    ) -> BitmapSurface {
        BitmapSurface(
            width: width, height: height, bytesPerRow: stride,
            pixels: Data(repeating: 127, count: bytes), format: format)
    }

    private func file(_ identifier: UInt8? = 1, data: Data = Data([0x21, 0x23])) -> ImageLoaderFakeFile {
        ImageLoaderFakeFile(data: data, metadata: metadata(identifier, bytes: UInt64(data.count)))
    }

    private func read(
        _ file: ImageLoaderFakeFile, limit: Int = ImageLoaderLimits.encodedBytes,
        cancellationCheck: @Sendable () throws -> Void = {}
    ) throws -> BoundedImageFileReader.ReadResult {
        let opener = ImageLoaderFakeOpener([file])
        return try BoundedImageFileReader.read(
            contentsOfFile: "fixture.png", maximumBytes: limit,
            openFile: opener.open, cancellationCheck: cancellationCheck)
    }

    private func store(
        _ files: [ImageLoaderFakeFile], decoder: ImageLoaderFakeDecoder,
        entries: Int = 64, bytes: Int = 1024, encodedBytes: Int = ImageLoaderLimits.encodedBytes
    ) -> ImageLoaderStore {
        let opener = ImageLoaderFakeOpener(files)
        return ImageLoaderStore(
            maximumEntries: entries, maximumCachedBytes: bytes, maximumEncodedBytes: encodedBytes,
            openFile: opener.open, decode: decoder.decode)
    }

    func testProductionBudgetsUseTheApprovedBinaryAndDecimalLimits() async {
        XCTAssertEqual(ImageLoaderLimits.cacheEntries, 64)
        XCTAssertEqual(ImageLoaderLimits.cachePixelBytes, 33_554_432)
        XCTAssertEqual(ImageLoaderLimits.encodedBytes, 8_388_608)
        XCTAssertEqual(ImageLoaderLimits.sourcePixels, 16_000_000)
        XCTAssertEqual(ImageLoaderLimits.decodedBytes, 64_000_000)
        XCTAssertEqual(ImageLoaderLimits.readChunkBytes, 65_536)
    }

    func testCacheHitPreservesContentTokenPixelsAndAlphaConvention() async {
        let original = bitmap(bytes: 12, stride: 8, format: .bgra8Premultiplied)
        var cache = ImageLoaderBitmapCache()
        cache.insert(original, for: metadata())
        let cached = cache.value(for: metadata())
        XCTAssertEqual(cached, original)
        XCTAssertEqual(cached?.contentKey, original.contentKey)
        XCTAssertEqual(cached?.format, .bgra8Premultiplied)
        XCTAssertEqual(cache.pixelBytes, 12)
    }

    func testEntryBudgetEvictsLeastRecentlyUsedAfterHitPromotion() async {
        var cache = ImageLoaderBitmapCache(maximumEntries: 2, maximumBytes: 100)
        cache.insert(bitmap(), for: metadata(1))
        cache.insert(bitmap(), for: metadata(2))
        XCTAssertNotNil(cache.value(for: metadata(1)))
        cache.insert(bitmap(), for: metadata(3))
        XCTAssertNil(cache.value(for: metadata(2)))
        XCTAssertNotNil(cache.value(for: metadata(1)))
        XCTAssertNotNil(cache.value(for: metadata(3)))
        XCTAssertEqual(cache.count, 2)
        XCTAssertEqual(cache.pixelBytes, 8)
    }

    func testByteBudgetEvictsBeforeTheEntryCap() async {
        var cache = ImageLoaderBitmapCache(maximumEntries: 10, maximumBytes: 20)
        cache.insert(bitmap(bytes: 8), for: metadata(1))
        cache.insert(bitmap(bytes: 8), for: metadata(2))
        cache.insert(bitmap(bytes: 12), for: metadata(3))
        XCTAssertNil(cache.value(for: metadata(1)))
        XCTAssertNotNil(cache.value(for: metadata(2)))
        XCTAssertNotNil(cache.value(for: metadata(3)))
        XCTAssertEqual(cache.pixelBytes, 20)
        XCTAssertEqual(cache.count, 2)
    }

    func testByteCostIncludesPaddingAndTrailingDataRatherThanGeometryOnly() async {
        var cache = ImageLoaderBitmapCache(maximumEntries: 10, maximumBytes: 16)
        cache.insert(bitmap(bytes: 12, stride: 8), for: metadata(1))
        cache.insert(bitmap(bytes: 8), for: metadata(2))
        XCTAssertNil(cache.value(for: metadata(1)))
        XCTAssertEqual(cache.pixelBytes, 8)
        XCTAssertEqual(cache.count, 1)
    }

    func testReplacingOneIdentitySubtractsItsPreviousCostExactlyOnce() async {
        var cache = ImageLoaderBitmapCache(maximumEntries: 3, maximumBytes: 20)
        cache.insert(bitmap(), for: metadata(1))
        cache.insert(bitmap(), for: metadata(2))
        cache.insert(bitmap(bytes: 12), for: metadata(1, modification: 99))
        XCTAssertEqual(cache.pixelBytes, 16)
        XCTAssertEqual(cache.count, 2)
        XCTAssertNotNil(cache.value(for: metadata(1, modification: 99)))
        XCTAssertNotNil(cache.value(for: metadata(2)))
        cache.remove(identity: metadata(1).identity)
        cache.remove(identity: metadata(1).identity)
        XCTAssertEqual(cache.pixelBytes, 4)
    }

    func testOversizedCacheEntryDoesNotEvictUnrelatedImages() async {
        var cache = ImageLoaderBitmapCache(maximumEntries: 2, maximumBytes: 8)
        cache.insert(bitmap(), for: metadata(1))
        cache.insert(bitmap(bytes: 12), for: metadata(2))
        XCTAssertNotNil(cache.value(for: metadata(1)))
        XCTAssertNil(cache.value(for: metadata(2)))
        XCTAssertEqual(cache.count, 1)
        XCTAssertEqual(cache.pixelBytes, 4)
    }

    func testOversizedReplacementDropsOnlyItsPreviousVersion() async {
        var cache = ImageLoaderBitmapCache(maximumEntries: 2, maximumBytes: 8)
        cache.insert(bitmap(), for: metadata(1))
        cache.insert(bitmap(), for: metadata(2))
        cache.insert(bitmap(bytes: 12), for: metadata(1, modification: 99))
        XCTAssertNil(cache.value(for: metadata(1)))
        XCTAssertNotNil(cache.value(for: metadata(2)))
        XCTAssertEqual(cache.count, 1)
        XCTAssertEqual(cache.pixelBytes, 4)
    }

    func testZeroAndNegativeCacheBudgetsDisableRetention() async {
        for (entries, bytes) in [(0, 8), (2, 0), (-1, 8), (2, -1)] {
            var cache = ImageLoaderBitmapCache(maximumEntries: entries, maximumBytes: bytes)
            cache.insert(bitmap(), for: metadata())
            XCTAssertNil(cache.value(for: metadata()))
            XCTAssertEqual(cache.count, 0)
            XCTAssertEqual(cache.pixelBytes, 0)
        }
    }

    func testRequestedEntryCountCannotExpandTheProductionCacheBudget() async {
        var cache = ImageLoaderBitmapCache(maximumEntries: Int.max, maximumBytes: Int.max)
        for identifier in UInt8(1)...UInt8(65) {
            cache.insert(bitmap(), for: metadata(identifier))
        }
        XCTAssertEqual(cache.count, 64)
        XCTAssertNil(cache.value(for: metadata(1)))
        XCTAssertNotNil(cache.value(for: metadata(65)))
    }

    func testInvalidSurfaceIsNotRetained() async {
        let invalid = [
            bitmap(width: 0), bitmap(height: -1), bitmap(stride: 0),
            bitmap(width: 2), bitmap(bytes: 3),
        ]
        for surface in invalid {
            var cache = ImageLoaderBitmapCache()
            cache.insert(surface, for: metadata())
            XCTAssertNil(cache.value(for: metadata()))
            XCTAssertEqual(cache.count, 0)
            XCTAssertEqual(cache.pixelBytes, 0)
        }
    }

    func testAccessClockOverflowPreservesLRUOrdering() async {
        var cache = ImageLoaderBitmapCache(
            maximumEntries: 2, maximumBytes: 8, initialAccessClock: UInt64.max - 2)
        cache.insert(bitmap(), for: metadata(1))
        cache.insert(bitmap(), for: metadata(2))
        XCTAssertNotNil(cache.value(for: metadata(1)))
        cache.insert(bitmap(), for: metadata(3))
        XCTAssertNil(cache.value(for: metadata(2)))
        XCTAssertNotNil(cache.value(for: metadata(1)))
        XCTAssertNotNil(cache.value(for: metadata(3)))
        XCTAssertEqual(cache.pixelBytes, 8)
    }

    func testEqualPixelsDoNotAliasDifferentFileIdentitiesOrVolumes() async {
        var cache = ImageLoaderBitmapCache()
        let first = bitmap()
        let second = bitmap()
        let third = bitmap()
        cache.insert(first, for: metadata(1))
        cache.insert(second, for: metadata(2))
        cache.insert(third, for: metadata(1, volume: 99))
        XCTAssertEqual(cache.value(for: metadata(1))?.contentToken, first.contentToken)
        XCTAssertEqual(cache.value(for: metadata(2))?.contentToken, second.contentToken)
        XCTAssertEqual(cache.value(for: metadata(1, volume: 99))?.contentToken, third.contentToken)
        XCTAssertEqual(cache.count, 3)
    }

    func testSizeCreationWriteAndChangeTimesEachInvalidateTheCachedVersion() async {
        let versions = [
            metadata(1, bytes: 3), metadata(1, creation: 99),
            metadata(1, modification: 99), metadata(1, change: 99), metadata(1, change: nil),
        ]
        for version in versions {
            var cache = ImageLoaderBitmapCache()
            cache.insert(bitmap(), for: metadata(1))
            cache.insert(bitmap(), for: metadata(2))
            XCTAssertNil(cache.value(for: version))
            XCTAssertNil(cache.value(for: metadata(1)))
            XCTAssertNotNil(cache.value(for: metadata(2)))
            XCTAssertEqual(cache.pixelBytes, 4)
        }
    }

    func testUnavailableFileIdentityNeverCreatesAPathOnlyCacheEntry() async {
        var cache = ImageLoaderBitmapCache()
        cache.insert(bitmap(), for: metadata(nil))
        XCTAssertNil(cache.value(for: metadata(nil)))
        XCTAssertEqual(cache.count, 0)
        XCTAssertEqual(cache.pixelBytes, 0)
    }

    func testRepeatedLoadReopensAndChecksMetadataWithoutReadingOrDecodingAgain() async throws {
        let firstFile = file()
        let secondFile = file()
        let decoder = ImageLoaderFakeDecoder()
        let loader = store([firstFile, secondFile], decoder: decoder)
        let first = try loader.load(contentsOfFile: "named.png")
        let second = try loader.load(contentsOfFile: "named.png")
        XCTAssertEqual(first.contentKey, second.contentKey)
        XCTAssertEqual(decoder.calls.count, 1)
        XCTAssertEqual(firstFile.metadataReads, 3)
        XCTAssertEqual(secondFile.metadataReads, 2)
        XCTAssertTrue(secondFile.readRequests.isEmpty)
        XCTAssertEqual(firstFile.closeCount, 1)
        XCTAssertEqual(secondFile.closeCount, 1)
    }

    func testReplacementAtTheSamePathDoesNotReturnTheOldFile() async throws {
        let decoder = ImageLoaderFakeDecoder()
        let loader = store([file(1, data: Data([1, 2])), file(2, data: Data([3, 4]))], decoder: decoder)
        let first = try loader.load(contentsOfFile: "same.png")
        let replacement = try loader.load(contentsOfFile: "same.png")
        XCTAssertNotEqual(first.pixels, replacement.pixels)
        XCTAssertEqual(decoder.calls, [Data([1, 2]), Data([3, 4])])
    }

    func testDifferentPathSpellingsMayShareTheSameOpenedFileIdentity() async throws {
        let decoder = ImageLoaderFakeDecoder()
        let loader = store([file(), file()], decoder: decoder)
        let first = try loader.load(contentsOfFile: "alias-one.png")
        let alias = try loader.load(contentsOfFile: "Alias-Two.PNG")
        XCTAssertEqual(first.contentToken, alias.contentToken)
        XCTAssertEqual(loader.cachedEntryCount, 1)
        XCTAssertEqual(decoder.calls.count, 1)
    }

    func testEqualLengthAlternateStreamsDoNotShareCachedPixels() async throws {
        for (firstName, secondName) in [(":first:$DATA", ":second:$DATA"), (":é", ":e\u{0301}")] {
            let firstFile = file(1, data: Data([1, 2]))
            let secondFile = file(1, data: Data([3, 4]))
            firstFile.currentMetadata = metadata(stream: firstName)
            secondFile.currentMetadata = metadata(stream: secondName)
            XCTAssertEqual(
                firstFile.currentMetadata.identity?.identifier, secondFile.currentMetadata.identity?.identifier)
            XCTAssertEqual(firstFile.currentMetadata.byteCount, secondFile.currentMetadata.byteCount)
            XCTAssertEqual(firstFile.currentMetadata.modificationTime, secondFile.currentMetadata.modificationTime)
            XCTAssertNotEqual(firstFile.currentMetadata.identity, secondFile.currentMetadata.identity)
            let decoder = ImageLoaderFakeDecoder()
            let loader = store([firstFile, secondFile], decoder: decoder)
            let first = try loader.load(contentsOfFile: "file.png" + firstName)
            let second = try loader.load(contentsOfFile: "file.png" + secondName)
            XCTAssertNotEqual(first.pixels, second.pixels)
            XCTAssertEqual(decoder.calls, [Data([1, 2]), Data([3, 4])])
            XCTAssertEqual(loader.cachedEntryCount, 2)
        }
    }

    func testStreamIdentityUsesTheFinalUTF16ComponentWithoutCaseFolding() async {
        let paths = [
            ("C:\\base\\image.png", ""),
            ("C:/base/image.png::$DATA", "::$DATA"),
            ("\\\\?\\C:\\base\\image.png:One:$DATA", ":One:$DATA"),
            ("\\\\server\\share\\image.png:Two", ":Two"),
            ("C:\\base\\image.png:\u{0301}pixels", ":\u{0301}pixels"),
            ("C:\\base\\image%3Astream.png", ""),
        ]
        for (path, expected) in paths {
            XCTAssertEqual(ImageLoaderFileIdentity.streamName(inResolvedPath: path), Array(expected.utf16), path)
        }
        let prefix = Array("C:/image.png:".utf16)
        XCTAssertEqual(ImageLoaderFileIdentity.streamName(inResolvedPathUTF16: prefix + [0xD800]), [0x3A, 0xD800])
        XCTAssertEqual(ImageLoaderFileIdentity.streamName(inResolvedPathUTF16: prefix + [0xD801]), [0x3A, 0xD801])
    }

    func testUnknownIdentityStillAllowsUncachedLegacyLoads() async throws {
        let decoder = ImageLoaderFakeDecoder()
        let firstFile = file(nil)
        let secondFile = file(nil)
        let loader = store([firstFile, secondFile], decoder: decoder)
        _ = try loader.load(contentsOfFile: "uncacheable.png")
        _ = try loader.load(contentsOfFile: "uncacheable.png")
        XCTAssertEqual(decoder.calls.count, 2)
        XCTAssertEqual(loader.cachedEntryCount, 0)
        XCTAssertEqual(loader.cachedPixelBytes, 0)
        XCTAssertEqual(firstFile.closeCount + secondFile.closeCount, 2)
    }

    func testValidOverCacheBudgetBitmapIsReturnedWithoutEvictingOtherFiles() async throws {
        let decoder = ImageLoaderFakeDecoder()
        decoder.operation = { data in
            BitmapSurface(
                width: 1, height: 1, bytesPerRow: 4,
                pixels: Data(repeating: 1, count: data.first == 1 ? 4 : 12))
        }
        let loader = store(
            [file(1, data: Data([1])), file(2, data: Data([2])), file(1, data: Data([1]))],
            decoder: decoder, bytes: 8)
        let first = try loader.load(contentsOfFile: "small.png")
        let large = try loader.load(contentsOfFile: "large.png")
        let again = try loader.load(contentsOfFile: "small.png")
        XCTAssertEqual(large.pixels.count, 12)
        XCTAssertEqual(first.contentToken, again.contentToken)
        XCTAssertEqual(decoder.calls.count, 2)
        XCTAssertEqual(loader.cachedEntryCount, 1)
        XCTAssertEqual(loader.cachedPixelBytes, 4)
    }

    func testFailedStaleRefreshDoesNotReturnOrRetainTheOldVersion() async throws {
        let original = file(1)
        let unrelated = file(2)
        let changed = file(1)
        changed.currentMetadata = metadata(1, modification: 99)
        let retry = file(1)
        let decoder = ImageLoaderFakeDecoder()
        let loader = store([original, unrelated, changed, retry, file(2)], decoder: decoder)
        let first = try loader.load(contentsOfFile: "first.png")
        _ = try loader.load(contentsOfFile: "other.png")
        decoder.failure = .decode
        XCTAssertThrowsError(try loader.load(contentsOfFile: "first.png")) {
            XCTAssertEqual($0 as? ImageLoaderFixtureError, .decode)
        }
        XCTAssertEqual(loader.cachedEntryCount, 1)
        decoder.failure = nil
        let reloaded = try loader.load(contentsOfFile: "first.png")
        _ = try loader.load(contentsOfFile: "other.png")
        XCTAssertNotEqual(first.contentToken, reloaded.contentToken)
        XCTAssertEqual(decoder.calls.count, 4)
        XCTAssertEqual(changed.closeCount, 1)
    }

    func testCachedHitRejectsMetadataChangesDuringTheSecondObservation() async throws {
        let changed = file()
        let newMetadata = metadata(1, modification: 99)
        changed.metadataOperation = { source, call in call == 1 ? source.currentMetadata : newMetadata }
        let decoder = ImageLoaderFakeDecoder()
        let loader = store([file(), changed], decoder: decoder)
        _ = try loader.load(contentsOfFile: "same.png")
        XCTAssertThrowsError(try loader.load(contentsOfFile: "same.png")) {
            XCTAssertEqual($0 as? ImageLoaderFailure, .changedSource)
        }
        XCTAssertEqual(loader.cachedEntryCount, 0)
        XCTAssertEqual(decoder.calls.count, 1)
        XCTAssertTrue(changed.readRequests.isEmpty)
        XCTAssertEqual(changed.closeCount, 1)
    }

    func testReadUsesAtMost64KiBChunksAndPreservesAllBytes() async throws {
        let bytes = Data((0..<(65_536 + 17)).map { UInt8(truncatingIfNeeded: $0) })
        let source = file(data: bytes)
        let result = try read(source, limit: bytes.count)
        XCTAssertEqual(result.data, bytes)
        XCTAssertEqual(source.readRequests, [65_536, 17, 1])
        XCTAssertEqual(result.snapshot.byteCount, UInt64(bytes.count))
        XCTAssertTrue(result.snapshot.hasStableIdentity)
        XCTAssertEqual(source.closeCount, 1)
    }

    func testExactEncodedLimitRequiresAnEmptyOverflowProbe() async throws {
        let source = file(data: Data([1, 2, 3, 4]))
        XCTAssertEqual(try read(source, limit: 4).data, Data([1, 2, 3, 4]))
        XCTAssertEqual(source.readRequests, [4, 1])
        XCTAssertEqual(source.metadataReads, 2)
        XCTAssertEqual(source.closeCount, 1)
    }

    func testReportedEncodedOverflowFailsBeforeReadingOrDecoding() async {
        let source = file(data: Data([1, 2, 3, 4, 5]))
        let decoder = ImageLoaderFakeDecoder()
        let loader = store([source], decoder: decoder, encodedBytes: 4)
        XCTAssertThrowsError(try loader.load(contentsOfFile: "too-large.png")) {
            XCTAssertEqual($0 as? ImageLoaderFailure, .encodedLimitExceeded)
        }
        XCTAssertTrue(source.readRequests.isEmpty)
        XCTAssertTrue(decoder.calls.isEmpty)
        XCTAssertEqual(source.closeCount, 1)
        XCTAssertEqual(loader.cachedEntryCount, 0)
    }

    func testGrowingSourceCannotBypassEncodedLimitWithItsEarlierMetadata() async {
        let source = file(data: Data([1, 2, 3, 4, 5]))
        source.currentMetadata = metadata(bytes: 4)
        XCTAssertThrowsError(try read(source, limit: 4)) {
            XCTAssertEqual($0 as? ImageLoaderFailure, .encodedLimitExceeded)
        }
        XCTAssertEqual(source.readRequests, [4, 1])
        XCTAssertEqual(source.closeCount, 1)
    }

    func testReadContractRejectsChunksLargerThanRequested() async {
        let source = file()
        source.readOperation = { _ in Data([1, 2, 3, 4, 5]) }
        XCTAssertThrowsError(try read(source, limit: 4)) {
            XCTAssertEqual($0 as? ImageLoaderFailure, .invalidReadResult)
        }
        XCTAssertEqual(source.readRequests, [4])
        XCTAssertEqual(source.closeCount, 1)
    }

    func testOverflowProbeAlsoRejectsAnOversizedReadResult() async {
        let source = file(data: Data())
        source.readOperation = { _ in Data([1, 2]) }
        XCTAssertThrowsError(try read(source, limit: 0)) {
            XCTAssertEqual($0 as? ImageLoaderFailure, .invalidReadResult)
        }
        XCTAssertEqual(source.readRequests, [1])
        XCTAssertEqual(source.closeCount, 1)
    }

    func testZeroByteLimitAcceptsOnlyAnEmptyFile() async throws {
        let empty = file(data: Data())
        XCTAssertEqual(try read(empty, limit: 0).data, Data())
        XCTAssertEqual(empty.readRequests, [1])
        let nonempty = file(data: Data([1]))
        XCTAssertThrowsError(try read(nonempty, limit: 0)) {
            XCTAssertEqual($0 as? ImageLoaderFailure, .encodedLimitExceeded)
        }
        XCTAssertTrue(nonempty.readRequests.isEmpty)
        XCTAssertEqual(empty.closeCount + nonempty.closeCount, 2)
    }

    func testInternalReadLimitCannotExceedTheProductionEncodedLimit() async {
        let source = file()
        source.currentMetadata = metadata(bytes: UInt64(ImageLoaderLimits.encodedBytes) + 1)
        XCTAssertThrowsError(try read(source, limit: Int.max)) {
            XCTAssertEqual($0 as? ImageLoaderFailure, .encodedLimitExceeded)
        }
        XCTAssertTrue(source.readRequests.isEmpty)
        XCTAssertEqual(source.closeCount, 1)
    }

    func testReadFailureClosesTheSourceAndDoesNotDecode() async {
        let source = file()
        source.readOperation = { _ in throw ImageLoaderFixtureError.read }
        let decoder = ImageLoaderFakeDecoder()
        let loader = store([source], decoder: decoder)
        XCTAssertThrowsError(try loader.load(contentsOfFile: "broken.png")) {
            XCTAssertEqual($0 as? ImageLoaderFixtureError, .read)
        }
        XCTAssertTrue(decoder.calls.isEmpty)
        XCTAssertEqual(source.closeCount, 1)
        XCTAssertEqual(loader.cachedEntryCount, 0)
    }

    func testInitialMetadataFailureStillClosesTheOpenedHandle() async {
        let source = file()
        source.metadataOperation = { _, _ in throw ImageLoaderFixtureError.metadata }
        let decoder = ImageLoaderFakeDecoder()
        let loader = store([source], decoder: decoder)
        XCTAssertThrowsError(try loader.load(contentsOfFile: "missing-metadata.png")) {
            XCTAssertEqual($0 as? ImageLoaderFixtureError, .metadata)
        }
        XCTAssertEqual(source.closeCount, 1)
        XCTAssertTrue(source.readRequests.isEmpty)
        XCTAssertTrue(decoder.calls.isEmpty)
    }

    func testPostReadMetadataFailureClosesWithoutPublishingAResult() async {
        let source = file()
        source.metadataOperation = { source, call in
            if call > 1 { throw ImageLoaderFixtureError.metadata }
            return source.currentMetadata
        }
        XCTAssertThrowsError(try read(source)) {
            XCTAssertEqual($0 as? ImageLoaderFixtureError, .metadata)
        }
        XCTAssertEqual(source.closeCount, 1)
        XCTAssertEqual(source.metadataReads, 2)
    }

    func testMetadataChangeDuringReadPreventsDecoding() async {
        let source = file()
        let changed = metadata(modification: 99)
        source.metadataOperation = { source, call in call == 1 ? source.currentMetadata : changed }
        let decoder = ImageLoaderFakeDecoder()
        let loader = store([source], decoder: decoder)
        XCTAssertThrowsError(try loader.load(contentsOfFile: "changed.png")) {
            XCTAssertEqual($0 as? ImageLoaderFailure, .changedSource)
        }
        XCTAssertTrue(decoder.calls.isEmpty)
        XCTAssertEqual(source.closeCount, 1)
    }

    func testReadLengthMustMatchStableMetadataEvenWhenWithinBudget() async {
        let source = file(data: Data([1]))
        source.currentMetadata = metadata(bytes: 2)
        XCTAssertThrowsError(try read(source)) {
            XCTAssertEqual($0 as? ImageLoaderFailure, .changedSource)
        }
        XCTAssertEqual(source.closeCount, 1)
    }

    func testMutationDuringDecodeIsRejectedBeforeCacheInsertion() async {
        let source = file()
        let changed = metadata(modification: 99)
        let decoder = ImageLoaderFakeDecoder()
        let pixels = bitmap()
        decoder.operation = { _ in
            source.currentMetadata = changed
            return pixels
        }
        let loader = store([source], decoder: decoder)
        XCTAssertThrowsError(try loader.load(contentsOfFile: "changed.png")) {
            XCTAssertEqual($0 as? ImageLoaderFailure, .changedSource)
        }
        XCTAssertEqual(decoder.calls.count, 1)
        XCTAssertEqual(loader.cachedEntryCount, 0)
        XCTAssertEqual(source.closeCount, 1)
    }

    func testInvalidDecoderResultClosesTheSourceAndDoesNotCache() async {
        let source = file()
        let decoder = ImageLoaderFakeDecoder()
        let invalid = bitmap(bytes: 3)
        decoder.operation = { _ in invalid }
        let loader = store([source], decoder: decoder)
        XCTAssertThrowsError(try loader.load(contentsOfFile: "bad-result.png")) {
            XCTAssertEqual($0 as? ImageLoaderFailure, .invalidDecodedBitmap)
        }
        XCTAssertEqual(loader.cachedEntryCount, 0)
        XCTAssertEqual(source.closeCount, 1)
    }

    func testDecodedGeometryAndStrideLimitsUseCheckedArithmetic() async {
        let oversized = [
            bitmap(bytes: 0, width: 4_000_001, height: 4, stride: 16_000_004),
            bitmap(bytes: 0, stride: 64_000_001),
            bitmap(bytes: 0, width: Int32.max, height: Int32.max, stride: Int32.max),
        ]
        for surface in oversized {
            XCTAssertThrowsError(try ImageLoaderStore.validate(surface)) {
                XCTAssertEqual($0 as? ImageLoaderFailure, .decodedLimitExceeded)
            }
        }
        // Exact-limit geometry reaches buffer validation, rather than an
        // off-by-one limit failure; no 64 MB fixture allocation is necessary.
        let exact = bitmap(bytes: 0, width: 4000, height: 4000, stride: 16_000)
        XCTAssertThrowsError(try ImageLoaderStore.validate(exact)) {
            XCTAssertEqual($0 as? ImageLoaderFailure, .invalidDecodedBitmap)
        }
    }

    func testEmptyAndEmbeddedNULPathsNeverReachTheFileOpener() async {
        let opener = ImageLoaderFakeOpener([])
        let decoder = ImageLoaderFakeDecoder()
        let loader = ImageLoaderStore(openFile: opener.open, decode: decoder.decode)
        for path in ["", "good.png\0different.png"] {
            XCTAssertThrowsError(try loader.load(contentsOfFile: path)) {
                XCTAssertEqual($0 as? ImageLoaderFailure, .invalidPath)
            }
            XCTAssertThrowsError(
                try BoundedImageFileReader.read(
                    contentsOfFile: path, maximumBytes: 4, openFile: opener.open, cancellationCheck: {})
            ) {
                XCTAssertEqual($0 as? ImageLoaderFailure, .invalidPath)
            }
        }
        XCTAssertTrue(opener.paths.isEmpty)
        XCTAssertTrue(decoder.calls.isEmpty)
    }

    func testPathResolutionPreservesUnicodeCaseAndLiteralPercentEscapes() async throws {
        let name = "MiXeD 雪 %00.png"
        let opener = ImageLoaderFakeOpener([file()])
        let result = try BoundedImageFileReader.read(
            contentsOfFile: name, maximumBytes: 4, openFile: opener.open, cancellationCheck: {})
        XCTAssertEqual(URL(fileURLWithPath: result.snapshot.path).lastPathComponent, name)
        XCTAssertEqual(opener.paths, [result.snapshot.path])
        XCTAssertNotEqual(result.snapshot.path, name, "Relative paths must be resolved before the worker returns")
    }

    func testOpenFailurePropagatesWithoutTryingToDecode() async {
        let opener = ImageLoaderFakeOpener([])
        let decoder = ImageLoaderFakeDecoder()
        let loader = ImageLoaderStore(openFile: opener.open, decode: decoder.decode)
        XCTAssertThrowsError(try loader.load(contentsOfFile: "missing.png")) {
            XCTAssertEqual($0 as? ImageLoaderFixtureError, .open)
        }
        XCTAssertEqual(opener.paths.count, 1)
        XCTAssertTrue(decoder.calls.isEmpty)
    }

    func testSnapshotRevalidationChecksTheReopenedObjectWithoutReadingIt() async throws {
        let result = try read(file())
        let current = file()
        let opener = ImageLoaderFakeOpener([current])
        try BoundedImageFileReader.validateCurrent(result.snapshot, openFile: opener.open, cancellationCheck: {})
        XCTAssertEqual(opener.paths, [result.snapshot.path])
        XCTAssertEqual(current.metadataReads, 1)
        XCTAssertTrue(current.readRequests.isEmpty)
        XCTAssertEqual(current.closeCount, 1)
    }

    func testSnapshotRevalidationRejectsReplacementOrMetadataChanges() async throws {
        let result = try read(file())
        let versions = [
            metadata(2), metadata(bytes: 3), metadata(creation: 99),
            metadata(modification: 99), metadata(change: 99), metadata(nil),
        ]
        for version in versions {
            let current = file()
            current.currentMetadata = version
            let opener = ImageLoaderFakeOpener([current])
            XCTAssertThrowsError(
                try BoundedImageFileReader.validateCurrent(
                    result.snapshot, openFile: opener.open, cancellationCheck: {})
            ) {
                XCTAssertEqual($0 as? ImageLoaderFailure, .changedSource)
            }
            XCTAssertEqual(current.closeCount, 1)
            XCTAssertTrue(current.readRequests.isEmpty)
        }
    }

    func testSnapshotWithoutStableIdentityFailsClosedBeforeRevalidationOpen() async throws {
        let result = try read(file(nil))
        let opener = ImageLoaderFakeOpener([])
        XCTAssertFalse(result.snapshot.hasStableIdentity)
        XCTAssertThrowsError(
            try BoundedImageFileReader.validateCurrent(
                result.snapshot, openFile: opener.open, cancellationCheck: {})
        ) {
            XCTAssertEqual($0 as? ImageLoaderFailure, .unavailableFileIdentity)
        }
        XCTAssertTrue(opener.paths.isEmpty)
    }

    func testCancellationBeforeOpenDoesNotAcquireAHandle() async {
        let opener = ImageLoaderFakeOpener([file()])
        let cancellation = ImageLoaderCancellationProbe(cancelAtCheck: 1)
        XCTAssertThrowsError(
            try BoundedImageFileReader.read(
                contentsOfFile: "cancelled.png", maximumBytes: 4, openFile: opener.open,
                cancellationCheck: { try cancellation.check() })
        ) {
            XCTAssertTrue($0 is CancellationError)
        }
        XCTAssertTrue(opener.paths.isEmpty)
    }

    func testCancellationAfterOpenClosesBeforeMetadataOrRead() async {
        let source = file()
        let cancellation = ImageLoaderCancellationProbe(cancelAtCheck: 2)
        XCTAssertThrowsError(try read(source, cancellationCheck: { try cancellation.check() })) {
            XCTAssertTrue($0 is CancellationError)
        }
        XCTAssertEqual(source.metadataReads, 0)
        XCTAssertTrue(source.readRequests.isEmpty)
        XCTAssertEqual(source.closeCount, 1)
    }

    func testCancellationBeforeFirstReadDoesNotReadAnyBytes() async {
        let source = file()
        let cancellation = ImageLoaderCancellationProbe(cancelAtCheck: 4)
        XCTAssertThrowsError(try read(source, cancellationCheck: { try cancellation.check() })) {
            XCTAssertTrue($0 is CancellationError)
        }
        XCTAssertTrue(source.readRequests.isEmpty)
        XCTAssertEqual(source.metadataReads, 1)
        XCTAssertEqual(source.closeCount, 1)
    }

    func testCancellationAfterReadDiscardsTheChunkAndCloses() async {
        let source = file()
        let cancellation = ImageLoaderCancellationProbe(cancelAtCheck: 5)
        XCTAssertThrowsError(try read(source, cancellationCheck: { try cancellation.check() })) {
            XCTAssertTrue($0 is CancellationError)
        }
        XCTAssertEqual(source.readRequests.count, 1)
        XCTAssertEqual(source.metadataReads, 1)
        XCTAssertEqual(source.closeCount, 1)
    }

    func testCancellationBetweenChunksPreventsTheNextRead() async {
        let source = file(data: Data(repeating: 1, count: 65_537))
        let cancellation = ImageLoaderCancellationProbe(cancelAtCheck: 6)
        XCTAssertThrowsError(try read(source, cancellationCheck: { try cancellation.check() })) {
            XCTAssertTrue($0 is CancellationError)
        }
        XCTAssertEqual(source.readRequests, [65_536])
        XCTAssertEqual(source.closeCount, 1)
    }

    func testCancellationAfterOverflowProbeDoesNotReturnAnExactFit() async {
        let source = file(data: Data([1, 2, 3, 4]))
        let cancellation = ImageLoaderCancellationProbe(cancelAtCheck: 7)
        XCTAssertThrowsError(try read(source, limit: 4, cancellationCheck: { try cancellation.check() })) {
            XCTAssertTrue($0 is CancellationError)
        }
        XCTAssertEqual(source.readRequests, [4, 1])
        XCTAssertEqual(source.metadataReads, 1)
        XCTAssertEqual(source.closeCount, 1)
    }

    func testCancellationAfterFinalMetadataPreventsReadPublication() async {
        let source = file(data: Data([1, 2, 3, 4]))
        let cancellation = ImageLoaderCancellationProbe(cancelAtCheck: 8)
        XCTAssertThrowsError(try read(source, limit: 4, cancellationCheck: { try cancellation.check() })) {
            XCTAssertTrue($0 is CancellationError)
        }
        XCTAssertEqual(source.metadataReads, 2)
        XCTAssertEqual(source.closeCount, 1)
    }

    func testCancellationDuringRevalidationClosesTheNewHandle() async throws {
        let result = try read(file())
        for check in [2, 3] {
            let current = file()
            let opener = ImageLoaderFakeOpener([current])
            let cancellation = ImageLoaderCancellationProbe(cancelAtCheck: check)
            XCTAssertThrowsError(
                try BoundedImageFileReader.validateCurrent(
                    result.snapshot, openFile: opener.open,
                    cancellationCheck: { try cancellation.check() })
            ) {
                XCTAssertTrue($0 is CancellationError)
            }
            XCTAssertEqual(current.closeCount, 1)
            XCTAssertTrue(current.readRequests.isEmpty)
        }
    }
}

private enum ImageLoaderFixtureError: Error, Equatable {
    case open
    case read
    case metadata
    case decode
}

private final class ImageLoaderFakeFile: ImageLoaderFileSource {
    let data: Data
    var currentMetadata: ImageLoaderFileMetadata
    var metadataOperation: ((ImageLoaderFakeFile, Int) throws -> ImageLoaderFileMetadata)?
    var readOperation: ((Int) throws -> Data)?
    private var position = 0
    private(set) var readRequests: [Int] = []
    private(set) var metadataReads = 0
    private(set) var closeCount = 0

    init(data: Data, metadata: ImageLoaderFileMetadata) {
        self.data = data
        currentMetadata = metadata
    }

    func metadata() throws -> ImageLoaderFileMetadata {
        metadataReads += 1
        if let metadataOperation { return try metadataOperation(self, metadataReads) }
        return currentMetadata
    }

    func read(upToCount count: Int) throws -> Data {
        readRequests.append(count)
        if let readOperation { return try readOperation(count) }
        let end = position + min(count, data.count - position)
        defer { position = end }
        return Data(data[position..<end])
    }

    func close() {
        closeCount += 1
    }
}

private final class ImageLoaderFakeOpener {
    private let files: [ImageLoaderFakeFile]
    private(set) var paths: [String] = []

    init(_ files: [ImageLoaderFakeFile]) {
        self.files = files
    }

    func open(_ path: String) throws -> any ImageLoaderFileSource {
        paths.append(path)
        guard paths.count <= files.count else { throw ImageLoaderFixtureError.open }
        return files[paths.count - 1]
    }
}

private final class ImageLoaderFakeDecoder {
    var failure: ImageLoaderFixtureError?
    var operation: ((Data) throws -> BitmapSurface)?
    private(set) var calls: [Data] = []

    func decode(_ data: Data) throws -> BitmapSurface {
        calls.append(data)
        if let failure { throw failure }
        if let operation { return try operation(data) }
        return BitmapSurface(
            width: 1, height: 1, bytesPerRow: 4,
            pixels: Data([data.first ?? 0, data.last ?? 0, 0, 255]), format: .bgra8Straight)
    }
}

/// Only the lock-protected counter is shared with a Sendable cancellation
/// closure. No UI state, fake file handle, or XCTest assertion crosses actors.
private final class ImageLoaderCancellationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let cancelAtCheck: Int
    private var checkCount = 0

    init(cancelAtCheck: Int) {
        self.cancelAtCheck = cancelAtCheck
    }

    func check() throws {
        lock.lock()
        defer { lock.unlock() }
        checkCount += 1
        if checkCount >= cancelAtCheck { throw CancellationError() }
    }
}
