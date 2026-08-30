import Foundation
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import WinSwiftUI

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

@MainActor
final class AsyncImageLoadingTests: XCTestCase {
    func testLocalFileURLConversionPreservesTheDecodedPath() async throws {
        let local = URL(fileURLWithPath: "C:/fixture images/café.png")
        XCTAssertEqual(try AsyncImageFileURL.path(local), local.path)
        let localhost = try XCTUnwrap(URL(string: "file://localhost/C:/fixture.png"))
        XCTAssertEqual(try AsyncImageFileURL.path(localhost), localhost.path)
    }

    func testRemoteAndAmbiguousFileAuthoritiesCannotBecomeLocalPaths() async throws {
        for spelling in [
            "file://remote.example/C:/fixture.png", "file://user@localhost/C:/fixture.png",
            "file://localhost:42/C:/fixture.png", "file://%FF/C:/fixture.png",
        ] {
            guard let url = URL(string: spelling) else { continue }
            XCTAssertThrowsError(try AsyncImageFileURL.path(url), spelling) {
                XCTAssertEqual($0 as? AsyncImageLoadingError, .unsupportedFileURL)
            }
        }
        XCTAssertThrowsError(try AsyncImageFileURL.path(url("not-a-file")))
    }

    func testBufferAdmitsTheExactBudgetWithoutInventingHeaderLength() async throws {
        var buffer = AsyncImageDataBuffer(limit: 4)
        try buffer.validateExpectedLength(-1)
        try buffer.append(Data([1, 2]))
        try buffer.append(Data([3, 4]))
        XCTAssertEqual(buffer.data, Data([1, 2, 3, 4]))
        XCTAssertEqual(AsyncImageDataBuffer.maximumEncodedBytes, 8_388_608)
    }

    func testOversizedHeaderIsRejectedBeforeBodyAllocation() async throws {
        let buffer = AsyncImageDataBuffer(limit: 4)
        XCTAssertThrowsError(try buffer.validateExpectedLength(5)) {
            XCTAssertEqual($0 as? AsyncImageLoadingError, .encodedImageTooLarge)
        }
        XCTAssertTrue(buffer.data.isEmpty)
    }

    func testOverflowingChunkDoesNotMutateTheAcceptedPrefix() async throws {
        var buffer = AsyncImageDataBuffer(limit: 4)
        try buffer.append(Data([1, 2, 3]))
        XCTAssertThrowsError(try buffer.append(Data([4, 5]))) {
            XCTAssertEqual($0 as? AsyncImageLoadingError, .encodedImageTooLarge)
        }
        XCTAssertEqual(buffer.data, Data([1, 2, 3]))
    }

    func testAChunkLargerThanTheWholeBudgetFailsWithoutSubtractionOverflow() async throws {
        var buffer = AsyncImageDataBuffer(limit: 1)
        XCTAssertThrowsError(try buffer.append(Data([1, 2]))) {
            XCTAssertEqual($0 as? AsyncImageLoadingError, .encodedImageTooLarge)
        }
        XCTAssertTrue(buffer.data.isEmpty)
    }

    func testZeroBudgetStillAcceptsAnEmptyBodyAndRejectsNonemptyData() async throws {
        var buffer = AsyncImageDataBuffer(limit: 0)
        try buffer.append(Data())
        XCTAssertThrowsError(try buffer.append(Data([1])))
        XCTAssertTrue(buffer.data.isEmpty)
    }

    func testCancellationRunsEachRegisteredCallbackOnceAndSupportsLateRegistration() async throws {
        let token = AsyncImageCancellation()
        let calls = AsyncImageTestCounter()
        _ = token.register { calls.increment() }
        let removed = token.register { calls.increment(by: 100) }
        token.unregister(removed)
        token.cancel()
        token.cancel()
        _ = token.register { calls.increment() }
        XCTAssertEqual(calls.value, 2)
        XCTAssertTrue(token.isCancelled)
        XCTAssertThrowsError(try token.check()) { XCTAssertTrue($0 is CancellationError) }
    }

    func testCancellationCallbacksCanReenterWithoutHoldingTheTokenLock() async throws {
        let token = AsyncImageCancellation()
        let calls = AsyncImageTestCounter()
        _ = token.register {
            token.cancel()
            _ = token.register { calls.increment() }
        }
        token.cancel()
        XCTAssertEqual(calls.value, 1)
    }

    func testUnregisterReleasesCallbackCapturesOutsideTheTokenLock() async throws {
        let token = AsyncImageCancellation()
        let calls = AsyncImageTestCounter()
        var capture: AsyncImageCancellationReleaseProbe? = AsyncImageCancellationReleaseProbe {
            token.cancel()
            _ = token.register { calls.increment() }
        }
        let registration = token.register { [capture] in withExtendedLifetime(capture) {} }
        capture = nil
        XCTAssertEqual(calls.value, 0)
        token.unregister(registration)
        XCTAssertEqual(calls.value, 1)
    }

    func testAlreadyCancelledRequestNeverAcquiresAdmission() async throws {
        let calls = AsyncImageTestCounter()
        let service = AsyncImageService { _, _ in
            calls.increment()
            return asyncImageLoadingTestBitmap()
        }
        let token = AsyncImageCancellation()
        token.cancel()
        do {
            _ = try await service.load(url("cancelled"), cancellation: token)
            XCTFail("A cancelled request must not enter the operation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(calls.value, 0)
        XCTAssertEqual(service.snapshot, .init(activeRequests: 0, queuedRequests: 0, isClosed: false))
        service.close()
    }

    func testClosedServiceRejectsNewRequestsWithoutCreatingAWorker() async throws {
        let calls = AsyncImageTestCounter()
        let service = AsyncImageService { _, _ in
            calls.increment()
            return asyncImageLoadingTestBitmap()
        }
        service.close()
        service.close()
        do {
            _ = try await service.load(url("closed"), cancellation: AsyncImageCancellation())
            XCTFail("A closed host cannot admit more image work")
        } catch {
            XCTAssertEqual(error as? AsyncImageLoadingError, .serviceClosed)
        }
        XCTAssertEqual(calls.value, 0)
        XCTAssertEqual(service.snapshot, .init(activeRequests: 0, queuedRequests: 0, isClosed: true))
    }

    func testCancelledPhysicalWorkerKeepsItsSlotUntilTheOperationReturns() async throws {
        let started = expectation(description: "The controlled physical operation started")
        let gate = AsyncImageWorkGate { _ in started.fulfill() }
        let service = AsyncImageService(maximumActiveRequests: 1, maximumQueuedRequests: 0) { url, token in
            try await gate.perform(url, cancellation: token)
        }
        let cancellation = AsyncImageCancellation()
        let first = request(service, url: url("first"), cancellation: cancellation)
        await fulfillment(of: [started], timeout: 5)
        cancellation.cancel()
        XCTAssertEqual(service.snapshot.activeRequests, 1)
        do {
            _ = try await service.load(url("second"), cancellation: AsyncImageCancellation())
            XCTFail("Cancelling an unfinished decoder must not manufacture a free worker")
        } catch {
            XCTAssertEqual(error as? AsyncImageLoadingError, .queueFull)
        }
        await gate.finishAll()
        assertCancellation(await first.value)
        let returns = await gate.returnedTaskCancellation
        XCTAssertEqual(returns, [true], "The owned Swift worker itself receives cancellation")
        XCTAssertEqual(service.snapshot.activeRequests, 0)
        service.close()
    }

    func testQueueAdmissionIsBoundedAndCloseDrainsQueuedOwnersWithoutReleasingActiveWork() async throws {
        let started = expectation(description: "The only active slot is occupied")
        let gate = AsyncImageWorkGate { _ in started.fulfill() }
        let service = AsyncImageService(maximumActiveRequests: 1, maximumQueuedRequests: 1) { url, token in
            try await gate.perform(url, cancellation: token)
        }
        let active = request(service, url: url("active"))
        await fulfillment(of: [started], timeout: 5)
        let rejected = expectation(description: "Exactly one extra owner exceeds queue capacity")
        let pendingA = request(service, url: url("pending-a")) { result in
            if case .failure(let error) = result, error as? AsyncImageLoadingError == .queueFull { rejected.fulfill() }
        }
        let pendingB = request(service, url: url("pending-b")) { result in
            if case .failure(let error) = result, error as? AsyncImageLoadingError == .queueFull { rejected.fulfill() }
        }
        await fulfillment(of: [rejected], timeout: 5)
        XCTAssertEqual(service.snapshot, .init(activeRequests: 1, queuedRequests: 1, isClosed: false))
        service.close()
        XCTAssertEqual(service.snapshot, .init(activeRequests: 1, queuedRequests: 0, isClosed: true))
        let results = [await pendingA.value, await pendingB.value]
        XCTAssertEqual(results.filter { isCancellation($0) }.count, 1)
        XCTAssertEqual(results.filter { isQueueFull($0) }.count, 1)
        await gate.finishAll()
        assertCancellation(await active.value)
        XCTAssertEqual(service.snapshot, .init(activeRequests: 0, queuedRequests: 0, isClosed: true))
    }

    func testCancellingQueuedOwnersRemovesThemWithoutStartingTheirOperations() async throws {
        let started = expectation(description: "The active request started")
        let gate = AsyncImageWorkGate { _ in started.fulfill() }
        let service = AsyncImageService(maximumActiveRequests: 1, maximumQueuedRequests: 1) { url, token in
            try await gate.perform(url, cancellation: token)
        }
        let active = request(service, url: url("active"))
        await fulfillment(of: [started], timeout: 5)
        let rejected = expectation(description: "The queue is demonstrably full")
        let tokenA = AsyncImageCancellation()
        let tokenB = AsyncImageCancellation()
        let pendingA = request(service, url: url("pending-a"), cancellation: tokenA) { result in
            if case .failure(let error) = result, error as? AsyncImageLoadingError == .queueFull { rejected.fulfill() }
        }
        let pendingB = request(service, url: url("pending-b"), cancellation: tokenB) { result in
            if case .failure(let error) = result, error as? AsyncImageLoadingError == .queueFull { rejected.fulfill() }
        }
        await fulfillment(of: [rejected], timeout: 5)
        tokenA.cancel()
        tokenB.cancel()
        let results = [await pendingA.value, await pendingB.value]
        XCTAssertEqual(results.filter { isCancellation($0) }.count, 1)
        XCTAssertEqual(results.filter { isQueueFull($0) }.count, 1)
        XCTAssertEqual(service.snapshot.queuedRequests, 0)
        await gate.finishAll()
        _ = try await active.value.get()
        let starts = await gate.startedURLs
        XCTAssertEqual(starts, [url("active")])
        service.close()
    }

    func testCancellingOneOwnerDoesNotCancelAnotherOwnerOfTheSameURL() async throws {
        let started = expectation(description: "Two independent owners start two requests")
        started.expectedFulfillmentCount = 2
        let gate = AsyncImageWorkGate { _ in started.fulfill() }
        let service = AsyncImageService { url, token in try await gate.perform(url, cancellation: token) }
        let firstToken = AsyncImageCancellation()
        let first = request(service, url: url("shared"), cancellation: firstToken)
        let second = request(service, url: url("shared"))
        await fulfillment(of: [started], timeout: 5)
        firstToken.cancel()
        await gate.finishAll()
        assertCancellation(await first.value)
        let secondBitmap = try await second.value.get()
        XCTAssertEqual(secondBitmap, asyncImageLoadingTestBitmap())
        XCTAssertEqual(service.snapshot.activeRequests, 0)
        service.close()
    }

    func testCancellationOfTheAwaitingTaskReachesTheOwnedWorker() async throws {
        let started = expectation(description: "Worker entered its controlled operation")
        let cancelled = expectation(description: "Worker cancellation token was signalled")
        let gate = AsyncImageWorkGate { _ in started.fulfill() }
        let service = AsyncImageService { url, token in
            let registration = token.register { cancelled.fulfill() }
            defer { token.unregister(registration) }
            return try await gate.perform(url, cancellation: token)
        }
        let task = request(service, url: url("task-cancel"))
        await fulfillment(of: [started], timeout: 5)
        task.cancel()
        await fulfillment(of: [cancelled], timeout: 5)
        XCTAssertEqual(service.snapshot.activeRequests, 1)
        await gate.finishAll()
        assertCancellation(await task.value)
        service.close()
    }

    func testCloseMarksAdmissionClosedBeforeInvokingCancellationCallbacks() async throws {
        let started = expectation(description: "Request starts")
        let gate = AsyncImageWorkGate { _ in started.fulfill() }
        let service = AsyncImageService { url, token in try await gate.perform(url, cancellation: token) }
        let cancellation = AsyncImageCancellation()
        let callbacks = AsyncImageTestCounter()
        _ = cancellation.register {
            if service.snapshot.isClosed { callbacks.increment() }
            service.close()
        }
        let task = request(service, url: url("close-reentry"), cancellation: cancellation)
        await fulfillment(of: [started], timeout: 5)
        service.close()
        XCTAssertEqual(callbacks.value, 1)
        await gate.finishAll()
        assertCancellation(await task.value)
    }

    func testAdmissionSealDoesNotInvokeCallbacksUntilTheSeparateCloseDrain() async throws {
        let started = expectation(description: "Active work has acquired its slot")
        let gate = AsyncImageWorkGate { _ in started.fulfill() }
        let service = AsyncImageService { url, token in try await gate.perform(url, cancellation: token) }
        let token = AsyncImageCancellation()
        let calls = AsyncImageTestCounter()
        _ = token.register { calls.increment() }
        let task = request(service, url: url("two-phase-close"), cancellation: token)
        await fulfillment(of: [started], timeout: 5)
        service.closeAdmissions()
        XCTAssertEqual(service.snapshot, .init(activeRequests: 1, queuedRequests: 0, isClosed: true))
        XCTAssertEqual(calls.value, 0, "State revocation can occur before any cancellation callback")
        service.close()
        XCTAssertEqual(calls.value, 1)
        XCTAssertEqual(service.snapshot.activeRequests, 1)
        await gate.finishAll()
        assertCancellation(await task.value)
    }

    func testAnOperationFinishingBetweenSealAndDrainRevokesItsPublicationToken() async throws {
        let started = expectation(description: "The operation started before host teardown")
        let gate = AsyncImageWorkGate { _ in started.fulfill() }
        let service = AsyncImageService { url, token in try await gate.perform(url, cancellation: token) }
        let token = AsyncImageCancellation()
        let task = request(service, url: url("finish-after-seal"), cancellation: token)
        await fulfillment(of: [started], timeout: 5)
        service.closeAdmissions()
        await gate.finishAll()
        assertCancellation(await task.value)
        XCTAssertTrue(token.isCancelled, "A closing owner must suppress phase publication, not display cancellation")
        XCTAssertEqual(service.snapshot.activeRequests, 0)
        service.close()
    }

    func testHTTPTransportCancelsTheActualURLSessionTaskAndWaitsForItsCompletion() async throws {
        let started = expectation(description: "URLProtocol received startLoading")
        let stopped = expectation(description: "URLSession cancellation reached stopLoading")
        let url = url(UUID().uuidString)
        AsyncImageTestURLProtocol.install(
            url: url, stop: { stopped.fulfill() },
            start: { protocolInstance in
                protocolInstance.sendResponse(status: 200, headers: [:])
                started.fulfill()
            })
        defer { AsyncImageTestURLProtocol.remove(url: url) }
        let cancellation = AsyncImageCancellation()
        let configuration = urlProtocolConfiguration()
        let load = Task {
            try await AsyncImageHTTPTransport.load(url, cancellation: cancellation, configuration: configuration)
        }
        await fulfillment(of: [started], timeout: 5)
        cancellation.cancel()
        await fulfillment(of: [stopped], timeout: 5)
        do {
            _ = try await load.value
            XCTFail("An actually cancelled HTTP request cannot publish success")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testHTTPTransportRejectsOversizedContentLengthBeforeAcceptingBody() async throws {
        let url = url(UUID().uuidString)
        AsyncImageTestURLProtocol.install(url: url) { protocolInstance in
            protocolInstance.sendResponse(status: 200, headers: ["Content-Length": "5"])
            protocolInstance.finish()
        }
        defer { AsyncImageTestURLProtocol.remove(url: url) }
        do {
            _ = try await AsyncImageHTTPTransport.load(
                url, cancellation: AsyncImageCancellation(), configuration: urlProtocolConfiguration(),
                maximumEncodedBytes: 4)
            XCTFail("The header exceeds the admitted encoded budget")
        } catch {
            XCTAssertEqual(error as? AsyncImageLoadingError, .encodedImageTooLarge)
        }
    }

    func testCancellingHTTPAwaiterReachesURLSessionWithoutAnExplicitTokenCancel() async throws {
        let started = expectation(description: "URLProtocol started the transport")
        let stopped = expectation(description: "Awaiter cancellation stopped the actual transport")
        let url = url(UUID().uuidString)
        AsyncImageTestURLProtocol.install(
            url: url, stop: { stopped.fulfill() },
            start: { protocolInstance in
                protocolInstance.sendResponse(status: 200, headers: [:])
                started.fulfill()
            })
        defer { AsyncImageTestURLProtocol.remove(url: url) }
        let token = AsyncImageCancellation()
        let configuration = urlProtocolConfiguration()
        let task = Task {
            try await AsyncImageHTTPTransport.load(url, cancellation: token, configuration: configuration)
        }
        await fulfillment(of: [started], timeout: 5)
        task.cancel()
        await fulfillment(of: [stopped], timeout: 5)
        XCTAssertTrue(token.isCancelled)
        do {
            _ = try await task.value
            XCTFail("Cancellation must not return an admitted body")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testHTTPTransportRejectsChunkedOverflowAndPreservesHTTPFailure() async throws {
        for status in [200, 404] {
            let url = url(UUID().uuidString)
            AsyncImageTestURLProtocol.install(url: url) { protocolInstance in
                protocolInstance.sendResponse(status: status, headers: [:])
                protocolInstance.send(Data([1, 2, 3]))
                protocolInstance.send(Data([4, 5]))
                protocolInstance.finish()
            }
            defer { AsyncImageTestURLProtocol.remove(url: url) }
            do {
                _ = try await AsyncImageHTTPTransport.load(
                    url, cancellation: AsyncImageCancellation(), configuration: urlProtocolConfiguration(),
                    maximumEncodedBytes: 4)
                XCTFail("Neither an oversized body nor an HTTP failure may become an image")
            } catch {
                XCTAssertEqual(
                    error as? AsyncImageLoadingError, status == 200 ? .encodedImageTooLarge : .httpStatus(404))
            }
        }
    }

    func testHTTPTransportReturnsExactAdmittedBytesWithoutDiskSpooling() async throws {
        let url = url(UUID().uuidString)
        AsyncImageTestURLProtocol.install(url: url) { protocolInstance in
            protocolInstance.sendResponse(status: 200, headers: ["Content-Length": "4"])
            protocolInstance.send(Data([1, 2]))
            protocolInstance.send(Data([3, 4]))
            protocolInstance.finish()
        }
        defer { AsyncImageTestURLProtocol.remove(url: url) }
        let data = try await AsyncImageHTTPTransport.load(
            url, cancellation: AsyncImageCancellation(), configuration: urlProtocolConfiguration(),
            maximumEncodedBytes: 4)
        XCTAssertEqual(data, Data([1, 2, 3, 4]))
    }

    private func url(_ name: String) -> URL {
        URL(string: "https://async-image.invalid/\(name)")!
    }

    private func request(
        _ service: AsyncImageService, url: URL, cancellation: AsyncImageCancellation = AsyncImageCancellation(),
        completed: @escaping @MainActor (Result<BitmapSurface, any Error>) -> Void = { _ in }
    ) -> Task<Result<BitmapSurface, any Error>, Never> {
        Task {
            let result: Result<BitmapSurface, any Error>
            do { result = .success(try await service.load(url, cancellation: cancellation)) } catch {
                result = .failure(error)
            }
            completed(result)
            return result
        }
    }

    private func isCancellation(_ result: Result<BitmapSurface, any Error>) -> Bool {
        if case .failure(let error) = result { return error is CancellationError }
        return false
    }

    private func isQueueFull(_ result: Result<BitmapSurface, any Error>) -> Bool {
        if case .failure(let error) = result { return error as? AsyncImageLoadingError == .queueFull }
        return false
    }

    private func assertCancellation(
        _ result: Result<BitmapSurface, any Error>, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(isCancellation(result), file: file, line: line)
    }

    private func urlProtocolConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AsyncImageTestURLProtocol.self]
        return configuration
    }
}

private func asyncImageLoadingTestBitmap() -> BitmapSurface {
    BitmapSurface(width: 1, height: 1, bytesPerRow: 4, pixels: Data([0, 255, 0, 255]))
}

private final class AsyncImageTestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment(by value: Int = 1) {
        lock.lock()
        count += value
        lock.unlock()
    }
}

private final class AsyncImageCancellationReleaseProbe: @unchecked Sendable {
    let onRelease: @Sendable () -> Void

    init(onRelease: @escaping @Sendable () -> Void) { self.onRelease = onRelease }
    deinit { onRelease() }
}

private actor AsyncImageWorkGate {
    let started: @Sendable (URL) -> Void
    private(set) var startedURLs: [URL] = []
    private(set) var returnedTaskCancellation: [Bool] = []
    private var waiting: [CheckedContinuation<BitmapSurface, any Error>] = []

    init(started: @escaping @Sendable (URL) -> Void) { self.started = started }

    func perform(_ url: URL, cancellation: AsyncImageCancellation) async throws -> BitmapSurface {
        let bitmap: BitmapSurface = try await withCheckedThrowingContinuation { continuation in
            waiting.append(continuation)
            startedURLs.append(url)
            started(url)
        }
        // Intentionally noncooperative while suspended, just like a native
        // codec call. Tests control when the physical operation finally returns.
        returnedTaskCancellation.append(Task.isCancelled)
        return bitmap
    }

    func finishAll() {
        let pending = waiting
        waiting.removeAll()
        for continuation in pending { continuation.resume(returning: asyncImageLoadingTestBitmap()) }
    }
}

/// A deterministic URLSession protocol fixture. Its reserved `.invalid` URL
/// never leaves URLSession; no test relies on an external server or response.
private final class AsyncImageTestURLProtocol: URLProtocol, @unchecked Sendable {
    private struct Script: Sendable {
        let start: @Sendable (AsyncImageTestURLProtocol) -> Void
        let stop: @Sendable () -> Void
    }

    private final class Scripts: @unchecked Sendable {
        let lock = NSLock()
        var values: [URL: Script] = [:]
    }

    private static let scripts = Scripts()

    static func install(
        url: URL, stop: @escaping @Sendable () -> Void = {},
        start: @escaping @Sendable (AsyncImageTestURLProtocol) -> Void
    ) {
        scripts.lock.lock()
        scripts.values[url] = Script(start: start, stop: stop)
        scripts.lock.unlock()
    }

    static func remove(url: URL) {
        scripts.lock.lock()
        scripts.values.removeValue(forKey: url)
        scripts.lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "async-image.invalid"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() { script()?.start(self) }
    override func stopLoading() { script()?.stop() }

    func sendResponse(status: Int, headers: [String: String]) {
        guard let url = request.url,
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)
        else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    }

    func send(_ data: Data) { client?.urlProtocol(self, didLoad: data) }
    func finish() { client?.urlProtocolDidFinishLoading(self) }

    private func script() -> Script? {
        guard let url = request.url else { return nil }
        Self.scripts.lock.lock()
        defer { Self.scripts.lock.unlock() }
        return Self.scripts.values[url]
    }
}
