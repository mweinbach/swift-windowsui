import Foundation
import XCTest

@testable import SwiftWindowsDemo
@testable import SwiftWindowsUI

@MainActor
final class DemoMediaImageServiceTests: XCTestCase {
    func testFixedServiceAndDecoderLimitsAgree() async {
        XCTAssertEqual(DemoMediaImageService.maximumEncodedBytes, BoundedImageDecoder.maximumEncodedBytes)
        XCTAssertEqual(DemoMediaImageService.maximumSourcePixels, BoundedImageDecoder.maximumSourcePixels)
        XCTAssertEqual(DemoMediaImageService.maximumPixelDimension, BoundedImageDecoder.maximumPixelDimension)
        XCTAssertEqual(DemoMediaImageService.maximumActiveWorkers, 2)
        XCTAssertEqual(DemoMediaImageService.maximumCachedPixelBytes, 16_777_216)
        XCTAssertEqual(DemoMediaImageService.maximumCachedImages, 32)
    }

    func testRealEncodedDataProducesOwnedPixelsAndNeverEntersTheFileCache() async throws {
        let service = DemoMediaImageService()
        let data = MediaImageTestFixtures.png(width: 1, height: 1, rgba: [255, 0, 0, 128])
        let image = try await service.load(.data(data))
        XCTAssertEqual(image.pixelWidth, 1)
        XCTAssertEqual(image.pixelHeight, 1)
        XCTAssertEqual(image.byteCount, 4)
        XCTAssertEqual(Array(image.pixelData), [0, 0, 128, 128])
        var external = image.pixelData
        external[2] = 0
        XCTAssertEqual(image.pixelData[2], 128)
        let stats = await service.statistics
        XCTAssertEqual(stats.activeWorkerCount, 0)
        XCTAssertEqual(stats.cachedImageCount, 0)
        XCTAssertEqual(stats.cachedPixelBytes, 0)
        await service.close()
    }

    func testRealFilePreviewIsReadOnlyAndExternalEditsRequireReload() async throws {
        let fixture = try MediaFileFixture()
        defer { XCTAssertNoThrow(try fixture.remove()) }
        let file = fixture.root.appendingPathComponent("image.png", isDirectory: false)
        let red = MediaImageTestFixtures.png(width: 1, height: 1, rgba: [255, 0, 0, 255])
        let blue = MediaImageTestFixtures.png(width: 1, height: 1, rgba: [0, 0, 255, 255])
        try red.write(to: file)
        let service = DemoMediaImageService()

        let first = try await service.load(.file(file))
        XCTAssertEqual(Array(first.pixelData), [0, 0, 255, 255])
        XCTAssertEqual(try Data(contentsOf: file), red)
        try blue.write(to: file)
        let cached = try await service.load(.file(file))
        XCTAssertEqual(cached.pixelData, first.pixelData, "No filesystem freshness guarantee is inferred from a URL.")
        let reloaded = try await service.load(.file(file), cachePolicy: .reload)
        XCTAssertEqual(Array(reloaded.pixelData), [255, 0, 0, 255])
        XCTAssertEqual(try Data(contentsOf: file), blue)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path), ["image.png"])
        await service.close()
    }

    func testMissingMalformedAndRepairedFileUsesTheSameRetryPath() async throws {
        let fixture = try MediaFileFixture()
        defer { XCTAssertNoThrow(try fixture.remove()) }
        let file = fixture.root.appendingPathComponent("retry.png", isDirectory: false)
        let service = DemoMediaImageService()
        do {
            _ = try await service.load(.file(file))
            XCTFail("Missing image cannot become a ready preview.")
        } catch { XCTAssertNotNil(error as? CocoaError) }
        try Data([1, 2, 3]).write(to: file)
        await assertFailure(.invalidData, service: service, source: .file(file))
        let good = MediaImageTestFixtures.png(width: 1, height: 1, rgba: [0, 255, 0, 255])
        try good.write(to: file)
        let repaired = try await service.load(.file(file), cachePolicy: .reload)
        XCTAssertEqual(Array(repaired.pixelData), [0, 255, 0, 255])
        XCTAssertEqual(try Data(contentsOf: file), good)
        await service.close()
    }

    func testSelectedDirectoryIsNotDecodedAsAnImage() async throws {
        let fixture = try MediaFileFixture()
        defer { XCTAssertNoThrow(try fixture.remove()) }
        let service = DemoMediaImageService()
        await assertFailure(.notRegularFile, service: service, source: .file(fixture.root))
        let stats = await service.statistics
        XCTAssertEqual(stats.cachedImageCount, 0)
        XCTAssertEqual(stats.activeWorkerCount, 0)
        await service.close()
    }

    func testInvalidURLInputSizeAndOutputEdgeNeverReachTheReader() async throws {
        let counter = MediaReadCounter()
        let service = DemoMediaImageService { _ in
            counter.increment()
            return MediaImageTestFixtures.gif
        }
        let remote = try XCTUnwrap(URL(string: "https://example.invalid/image.png"))
        await assertFailure(.invalidFileURL, service: service, source: .file(remote))
        await assertFailure(
            .encodedImageTooLarge, service: service, source: .data(Data(repeating: 0, count: 8_388_609)))
        for edge in [0, 1025, Int.max] {
            await assertFailure(.invalidPixelDimension, service: service, source: .file(url("edge")), edge: edge)
        }
        XCTAssertEqual(counter.value, 0)
        let stats = await service.statistics
        XCTAssertEqual(stats.activeWorkerCount, 0)
        await service.close()
    }

    func testOversizedInjectedResultAndInvalidImageDoNotEnterCache() async {
        let service = DemoMediaImageService { _ in Data(repeating: 0, count: 8_388_609) }
        await assertFailure(.encodedImageTooLarge, service: service, source: .file(url("oversized")))
        let stats = await service.statistics
        XCTAssertEqual(stats.cachedImageCount, 0)
        XCTAssertEqual(stats.activeWorkerCount, 0)
        await service.close()

        let strict = DemoMediaImageService { _ in MediaImageTestFixtures.gif }
        await assertFailure(.unsupportedFormat, service: strict, source: .file(url("not-a-png")))
        await strict.close()
    }

    func testCacheHasThirtyTwoEntriesAndHitsUpdateLRUOrder() async throws {
        let counter = MediaReadCounter()
        let data = MediaImageTestFixtures.png(width: 1, height: 1, rgba: [255, 0, 0, 255])
        let service = DemoMediaImageService { _ in
            counter.increment()
            return data
        }
        for index in 0..<32 { _ = try await service.load(.file(url("image-\(index)"))) }
        _ = try await service.load(.file(url("image-0")))
        _ = try await service.load(.file(url("image-32")))
        _ = try await service.load(.file(url("image-0")))
        XCTAssertEqual(counter.value, 33, "The first image was touched and must remain cached.")
        _ = try await service.load(.file(url("image-1")))
        XCTAssertEqual(counter.value, 34, "The untouched second image must have been evicted.")
        let stats = await service.statistics
        XCTAssertEqual(stats.cachedImageCount, 32)
        XCTAssertEqual(stats.cachedPixelBytes, 32 * 4)
        await service.close()
    }

    func testCacheByteLimitEvictsImagesWithoutInvalidatingRetainedValues() async throws {
        let data = MediaImageTestFixtures.bmp(width: 1024, height: 1024, gray: 73)
        let service = DemoMediaImageService { _ in data }
        let retained = try await service.load(.file(url("large-0")), maximumPixelDimension: 1024)
        for index in 1...4 {
            _ = try await service.load(.file(url("large-\(index)")), maximumPixelDimension: 1024)
        }
        let stats = await service.statistics
        XCTAssertEqual(stats.cachedImageCount, 4)
        XCTAssertEqual(stats.cachedPixelBytes, 16_777_216)
        XCTAssertEqual(retained.byteCount, 4_194_304)
        XCTAssertEqual(Array(retained.pixelData.prefix(4)), [73, 73, 73, 255])
        await service.invalidateAll()
        let empty = await service.statistics
        XCTAssertEqual(empty.cachedPixelBytes, 0)
        XCTAssertEqual(Array(retained.pixelData.suffix(4)), [73, 73, 73, 255])
        await service.close()
    }

    func testRequestedSizeAndRevisionArePartOfFileIdentity() async throws {
        let counter = MediaReadCounter()
        let data = MediaImageTestFixtures.bmp(width: 30, height: 20, gray: 37)
        let service = DemoMediaImageService { _ in
            counter.increment()
            return data
        }
        let file = url("sizes")
        let first = try await service.load(.file(file), maximumPixelDimension: 9)
        let second = try await service.load(.file(file), maximumPixelDimension: 6)
        XCTAssertEqual(first.pixelWidth, 9)
        XCTAssertEqual(second.pixelWidth, 6)
        let two = await service.statistics
        XCTAssertEqual(two.cachedImageCount, 2)
        XCTAssertEqual(two.cachedPixelBytes, 9 * 6 * 4 + 6 * 4 * 4)
        _ = try await service.load(.file(file), maximumPixelDimension: 9, revision: 1)
        XCTAssertEqual(counter.value, 3)
        let changed = await service.statistics
        XCTAssertEqual(changed.cachedImageCount, 1, "A revision change evicts all sizes of the previous content.")
        await service.close()
    }

    func testCancellationKeepsTwoPhysicalSlotsOccupiedAndDoesNotQueueExtraLoads() async throws {
        let firstGate = MediaReadGate()
        let secondGate = MediaReadGate()
        let thirdReads = MediaReadCounter()
        let firstURL = url("first")
        let secondURL = url("second")
        let thirdURL = url("third")
        let data = MediaImageTestFixtures.png(width: 1, height: 1, rgba: [255, 0, 0, 255])
        let service = DemoMediaImageService { source in
            if source == .file(firstURL) { return try await firstGate.read() }
            if source == .file(secondURL) { return try await secondGate.read() }
            thirdReads.increment()
            return data
        }
        let first = Task { try await service.load(.file(firstURL)) }
        let second = Task { try await service.load(.file(secondURL)) }
        defer {
            first.cancel()
            second.cancel()
            firstGate.finish(.failure(CancellationError()))
            secondGate.finish(.failure(CancellationError()))
        }
        await assertEntered(firstGate)
        await assertEntered(secondGate)
        first.cancel()
        await assertCancellationObserved(firstGate)
        let draining = await service.statistics
        XCTAssertEqual(draining.activeWorkerCount, 2)
        await assertFailure(.busy, service: service, source: .file(thirdURL))
        XCTAssertEqual(thirdReads.value, 0)
        firstGate.finish(.success(data))
        await assertCancelled(first)
        let free = await service.statistics
        XCTAssertEqual(free.activeWorkerCount, 1)
        _ = try await service.load(.file(thirdURL))
        XCTAssertEqual(thirdReads.value, 1)
        secondGate.finish(.success(data))
        _ = try await second.value
        let settled = await service.statistics
        XCTAssertEqual(settled.activeWorkerCount, 0)
        XCTAssertEqual(settled.cachedImageCount, 2, "The cancelled first image must not be cached.")
        await service.close()
    }

    func testNewRevisionCancelsOldWorkerAndRejectsItsLateSuccess() async throws {
        let gate = MediaReadGate()
        let reads = MediaReadCounter()
        let red = MediaImageTestFixtures.png(width: 1, height: 1, rgba: [255, 0, 0, 255])
        let blue = MediaImageTestFixtures.png(width: 1, height: 1, rgba: [0, 0, 255, 255])
        let service = DemoMediaImageService { _ in
            if reads.increment() == 1 { return try await gate.read() }
            return blue
        }
        let file = url("revision")
        let old = Task { try await service.load(.file(file), revision: 0) }
        defer {
            old.cancel()
            gate.finish(.failure(CancellationError()))
        }
        await assertEntered(gate)
        let current = try await service.load(.file(file), revision: 1)
        await assertCancellationObserved(gate)
        XCTAssertEqual(Array(current.pixelData), [255, 0, 0, 255])
        let occupied = await service.statistics
        XCTAssertEqual(occupied.activeWorkerCount, 1)
        gate.finish(.success(red))
        await assertCancelled(old)
        let cached = try await service.load(.file(file), revision: 1)
        XCTAssertEqual(cached.pixelData, current.pixelData)
        XCTAssertEqual(reads.value, 2)
        await service.close()
    }

    func testInvalidationRevokesLateSuccessAndFailureWithoutReleasingTheSlot() async {
        for fails in [false, true] {
            let gate = MediaReadGate()
            let service = DemoMediaImageService { _ in try await gate.read() }
            let file = url("invalidate")
            let task = Task { try await service.load(.file(file)) }
            await assertEntered(gate)
            do { try await service.invalidate(file) } catch {
                XCTFail("Valid URL invalidation unexpectedly failed: \(error)")
            }
            await assertCancellationObserved(gate)
            let draining = await service.statistics
            XCTAssertEqual(draining.activeWorkerCount, 1)
            gate.finish(
                fails
                    ? .failure(MediaFixtureError.readFailed)
                    : .success(MediaImageTestFixtures.png(width: 1, height: 1, rgba: [255, 0, 0, 255])))
            await assertCancelled(task)
            let finished = await service.statistics
            XCTAssertEqual(finished.activeWorkerCount, 0)
            XCTAssertEqual(finished.cachedImageCount, 0)
            await service.close()
        }
    }

    func testReloadWhileFullRevokesPriorAuthorityButDoesNotStartAThirdWorker() async {
        let firstGate = MediaReadGate()
        let secondGate = MediaReadGate()
        let firstURL = url("full-first")
        let secondURL = url("full-second")
        let service = DemoMediaImageService { source in
            try await (source == .file(firstURL) ? firstGate : secondGate).read()
        }
        let first = Task { try await service.load(.file(firstURL)) }
        let second = Task { try await service.load(.file(secondURL)) }
        await assertEntered(firstGate)
        await assertEntered(secondGate)
        do {
            _ = try await service.load(.file(firstURL), cachePolicy: .reload)
            XCTFail("Reload must keep the previous physical slot occupied.")
        } catch { XCTAssertEqual(error as? DemoMediaImageError, .busy) }
        await assertCancellationObserved(firstGate)
        let stats = await service.statistics
        XCTAssertEqual(stats.activeWorkerCount, 2)
        await service.close()
        firstGate.finish(.failure(MediaFixtureError.readFailed))
        secondGate.finish(.failure(MediaFixtureError.readFailed))
        await assertCancelled(first)
        await assertCancelled(second)
    }

    func testCloseIsTerminalAndDrainsOwnedWorkersBeforeTheirSlotsDisappear() async throws {
        let gate = MediaReadGate()
        let reads = MediaReadCounter()
        let data = MediaImageTestFixtures.png(width: 1, height: 1, rgba: [255, 0, 0, 255])
        let service = DemoMediaImageService { _ in
            if reads.increment() == 1 { return data }
            return try await gate.read()
        }
        _ = try await service.load(.file(url("cached-before-close")))
        let running = Task { try await service.load(.file(url("close"))) }
        await assertEntered(gate)
        await service.close()
        await assertCancellationObserved(gate)
        let closed = await service.statistics
        XCTAssertTrue(closed.isClosed)
        XCTAssertEqual(closed.cachedImageCount, 0)
        XCTAssertEqual(closed.activeWorkerCount, 1)
        await assertFailure(.closed, service: service, source: .file(url("after-close")))
        gate.finish(.success(data))
        await assertCancelled(running)
        let drained = await service.statistics
        XCTAssertEqual(drained.activeWorkerCount, 0)
        XCTAssertEqual(drained.cachedPixelBytes, 0)
    }

    func testIndependentServiceInstancesDoNotShareCacheOrCancellation() async throws {
        let counter = MediaReadCounter()
        let data = MediaImageTestFixtures.png(width: 1, height: 1, rgba: [255, 0, 0, 255])
        let first = DemoMediaImageService { _ in
            counter.increment()
            return data
        }
        let second = DemoMediaImageService { _ in
            counter.increment()
            return data
        }
        let file = url("same-source")
        _ = try await first.load(.file(file))
        _ = try await second.load(.file(file))
        XCTAssertEqual(counter.value, 2)
        await first.close()
        _ = try await second.load(.file(file))
        XCTAssertEqual(counter.value, 2)
        let stats = await second.statistics
        XCTAssertFalse(stats.isClosed)
        XCTAssertEqual(stats.cachedImageCount, 1)
        await second.close()
    }

    func testAlreadyCancelledCallerCannotStartReaderOrUseCachedSuccess() async throws {
        let reads = MediaReadCounter()
        let data = MediaImageTestFixtures.png(width: 1, height: 1, rgba: [255, 0, 0, 255])
        let service = DemoMediaImageService { _ in
            reads.increment()
            return data
        }
        let file = url("pre-cancelled")
        for cached in [false, true] {
            if cached { _ = try await service.load(.file(file)) }
            let task = Task.detached {
                withUnsafeCurrentTask { $0?.cancel() }
                return try await service.load(.file(file))
            }
            await assertCancelled(task)
            XCTAssertEqual(reads.value, cached ? 1 : 0)
        }
        await service.close()
    }

    func testCancellationBeforeWorkerInstallationPreventsPublication() async {
        let operation = DemoMediaImageOperation()
        operation.cancel()
        let task = Task.detached {
            try operation.checkCancellation()
            return try DemoMediaImage.decode(MediaImageTestFixtures.gif, maximumPixelDimension: 1)
        }
        operation.install(task)
        await assertCancelled(task)
        var published = false
        XCTAssertThrowsError(try operation.publish { published = true }) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertFalse(published)
    }

    func testPublicationCommitsBeforeUnlockedPayloadWorkAndLaterCancellation() async throws {
        let operation = DemoMediaImageOperation()
        let value = try operation.publish {
            // This would deadlock if arbitrary body/payload work ran under the
            // operation lock. Cancellation after commit cannot revoke its value.
            operation.cancel()
            return 7
        }
        XCTAssertEqual(value, 7)
        XCTAssertNoThrow(try operation.checkCancellation())
    }

    func testLiveReaderUsesBoundedChunksAndExactlyOneOverflowProbe() async throws {
        var requests: [Int] = []
        var closes = 0
        let data = try DemoMediaImageService.readBoundedBytes(
            read: { count in
                requests.append(count)
                return count == 1 ? nil : Data(repeating: 0, count: count)
            }, close: { closes += 1 })
        XCTAssertEqual(data.count, 8_388_608)
        XCTAssertEqual(requests, Array(repeating: 65_536, count: 128) + [1])
        XCTAssertEqual(closes, 1)
    }

    func testOverflowReaderFailureAndCancellationAlwaysCloseOwnedHandle() async {
        var requests: [Int] = []
        var closes = 0
        XCTAssertThrowsError(
            try DemoMediaImageService.readBoundedBytes(
                read: { count in
                    requests.append(count)
                    return Data(repeating: 0, count: count)
                }, close: { closes += 1 })
        ) { XCTAssertEqual($0 as? DemoMediaImageError, .encodedImageTooLarge) }
        XCTAssertEqual(requests.reduce(0, +), 8_388_609)
        XCTAssertEqual(closes, 1)

        for cancel in [false, true] {
            var readCount = 0
            var closeCount = 0
            XCTAssertThrowsError(
                try DemoMediaImageService.readBoundedBytes(
                    read: { count in
                        readCount += 1
                        if !cancel { throw MediaFixtureError.readFailed }
                        return Data(repeating: 0, count: count)
                    }, close: { closeCount += 1 },
                    checkCancellation: { if cancel && readCount == 1 { throw CancellationError() } }))
            XCTAssertEqual(readCount, 1)
            XCTAssertEqual(closeCount, 1)
        }
    }

    private func url(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "media-source-only-\(name).png", isDirectory: false)
    }

    private func assertFailure(
        _ expected: DemoMediaImageError, service: DemoMediaImageService, source: DemoMediaImageSource, edge: Int = 256
    ) async {
        do {
            _ = try await service.load(source, maximumPixelDimension: edge)
            XCTFail("Expected \(expected).")
        } catch { XCTAssertEqual(error as? DemoMediaImageError, expected) }
    }

    private func assertCancelled(_ task: Task<DemoMediaImage, Error>) async {
        do {
            _ = try await task.value
            XCTFail("Cancelled or invalidated image must not publish a result.")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    private func assertEntered(_ gate: MediaReadGate, file: StaticString = #filePath, line: UInt = #line) async {
        let entered = await gate.waitUntilEntered()
        XCTAssertTrue(entered, file: file, line: line)
    }

    private func assertCancellationObserved(_ gate: MediaReadGate, file: StaticString = #filePath, line: UInt = #line)
        async
    {
        let cancelled = await gate.waitUntilCancelled()
        XCTAssertTrue(cancelled, file: file, line: line)
    }
}

private enum MediaFixtureError: Error { case readFailed, timedOut }

private final class MediaReadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    @discardableResult
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }
}

/// Cancellation records intent but deliberately does not finish the physical
/// read. Only finish/timeout releases it, so tests cannot free a slot by fiat.
private final class MediaReadGate: @unchecked Sendable {
    private let lock = NSLock()
    private let entered = XCTestExpectation(description: "Image reader entered")
    private let cancelled = XCTestExpectation(description: "Image worker observed cancellation")
    private var hasEntered = false
    private var hasCancelled = false
    private var continuation: CheckedContinuation<Data, Error>?
    private var outcome: Result<Data, Error>?

    func read() async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { install($0) }
        } onCancel: {
            self.recordCancellation()
        }
    }

    func waitUntilEntered() async -> Bool { await waitFor(entered) }
    func waitUntilCancelled() async -> Bool { await waitFor(cancelled) }

    func finish(_ result: Result<Data, Error>) {
        lock.lock()
        guard outcome == nil else {
            lock.unlock()
            return
        }
        outcome = result
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }

    private func install(_ pending: CheckedContinuation<Data, Error>) {
        lock.lock()
        let first = !hasEntered
        hasEntered = true
        let result = outcome
        if result == nil { continuation = pending }
        lock.unlock()
        if first { entered.fulfill() }
        if let result { pending.resume(with: result) }
    }

    private func recordCancellation() {
        lock.lock()
        let first = !hasCancelled
        hasCancelled = true
        lock.unlock()
        if first { cancelled.fulfill() }
    }

    private func waitFor(_ expectation: XCTestExpectation) async -> Bool {
        let status = await XCTWaiter.fulfillment(of: [expectation], timeout: 5)
        guard status == .completed else {
            finish(.failure(MediaFixtureError.timedOut))
            return false
        }
        return true
    }
}

private final class MediaFileFixture {
    let root: URL
    private let temporaryRoot: URL

    init() throws {
        temporaryRoot = FileManager.default.temporaryDirectory.standardizedFileURL
        root = temporaryRoot.appendingPathComponent("swift-media-image-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }

    func remove() throws {
        guard root.standardizedFileURL.deletingLastPathComponent() == temporaryRoot,
            root.lastPathComponent.hasPrefix("swift-media-image-tests-")
        else { throw MediaFixtureError.readFailed }
        try FileManager.default.removeItem(at: root)
    }
}
