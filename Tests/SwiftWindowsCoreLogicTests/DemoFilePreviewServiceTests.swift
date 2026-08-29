import Foundation
import XCTest

@testable import SwiftWindowsDemo

@MainActor
final class DemoFilePreviewServiceTests: XCTestCase {
    func testEmptyAndUnicodeSamplesPreserveEveryUTF8Byte() async throws {
        for text in ["", "plain text", "\u{FEFF}e\u{301}😀\r\nline\rend\n", "日本語\t\0text"] {
            let bytes = Data(text.utf8)
            let preview = try await DemoFilePreviewService.localFiles.load(.sample(bytes))
            XCTAssertEqual(Data(preview.text.utf8), bytes)
            XCTAssertEqual(preview.byteCount, bytes.count)
        }
    }

    func testRealFileKeepsUnicodeAcrossReadChunksAndDoesNotChangeItsBytes() async throws {
        let fixture = try PreviewFileFixture()
        defer { XCTAssertNoThrow(try fixture.removeOwnedDirectory()) }
        let text =
            String(repeating: "a", count: DemoFilePreviewService.readChunkBytes - 1)
            + "😀e\u{301}\r\n" + String(repeating: "界", count: 3_000)
        let bytes = Data(text.utf8)
        let file = try fixture.write("unicode.txt", bytes)

        let preview = try await DemoFilePreviewService.localFiles.load(.file(file))

        XCTAssertEqual(Data(preview.text.utf8), bytes)
        XCTAssertEqual(preview.byteCount, bytes.count)
        XCTAssertEqual(try fixture.bytes(at: file), bytes)
        XCTAssertEqual(try fixture.childNames(), ["unicode.txt"])
    }

    func testRealFilesAcceptAnExactLimitAndRejectOneOverflowByte() async throws {
        let fixture = try PreviewFileFixture()
        defer { XCTAssertNoThrow(try fixture.removeOwnedDirectory()) }
        let empty = try fixture.write("empty.txt", Data())
        let exact = try fixture.write(
            "exact.txt", Data(repeating: 65, count: DemoFilePreviewService.maximumPreviewBytes))
        let overflow = try fixture.write(
            "overflow.txt", Data(repeating: 66, count: DemoFilePreviewService.maximumPreviewBytes + 1))

        let emptyPreview = try await DemoFilePreviewService.localFiles.load(.file(empty))
        let exactPreview = try await DemoFilePreviewService.localFiles.load(.file(exact))

        XCTAssertEqual(emptyPreview, DemoFilePreview(text: "", byteCount: 0))
        XCTAssertEqual(exactPreview.byteCount, DemoFilePreviewService.maximumPreviewBytes)
        XCTAssertEqual(exactPreview.text, String(repeating: "A", count: exactPreview.byteCount))
        await assertFailure(.previewTooLarge, source: .file(overflow))
        XCTAssertEqual(try fixture.bytes(at: overflow).count, DemoFilePreviewService.maximumPreviewBytes + 1)
        // Removing the files after each awaited outcome also exercises actual
        // handle release; deterministic close-call witnesses appear below.
        for file in [empty, exact, overflow] { try FileManager.default.removeItem(at: file) }
        XCTAssertTrue(try fixture.childNames().isEmpty)
    }

    func testOversizedSamplesAreRejectedBeforeCallingTheInjectedReader() async {
        let calls = PreviewReadCounter()
        let service = DemoFilePreviewService { _ in
            calls.increment()
            return Data()
        }
        await assertFailure(
            .previewTooLarge,
            source: .sample(Data(repeating: 65, count: DemoFilePreviewService.maximumPreviewBytes + 1)),
            service: service)
        XCTAssertEqual(calls.value, 0)
    }

    func testInjectedReaderCannotReturnOversizedOrRepairedUTF8Data() async {
        let oversized = DemoFilePreviewService { _ in
            Data(repeating: 65, count: DemoFilePreviewService.maximumPreviewBytes + 1)
        }
        await assertFailure(.previewTooLarge, source: .sample(Data()), service: oversized)
        let malformed = DemoFilePreviewService { _ in Data([0xC0, 0xAF]) }
        await assertFailure(.invalidUTF8, source: .sample(Data()), service: malformed)
    }

    func testMalformedUTF8SamplesFailInsteadOfInsertingReplacementCharacters() async {
        for bytes in [
            Data([0xFF]), Data([0x80]), Data([0xC0, 0xAF]), Data([0xE2, 0x82]),
            Data([0xED, 0xA0, 0x80]), Data([0xF4, 0x90, 0x80, 0x80]),
        ] {
            await assertFailure(.invalidUTF8, source: .sample(bytes))
        }
    }

    func testMissingAndMalformedFilesCanBeRetriedAfterRepair() async throws {
        let fixture = try PreviewFileFixture()
        defer { XCTAssertNoThrow(try fixture.removeOwnedDirectory()) }
        let file = fixture.file("retry.txt")
        do {
            _ = try await DemoFilePreviewService.localFiles.load(.file(file))
            XCTFail("A missing file must not produce a successful empty preview.")
        } catch {
            XCTAssertFalse(error is CancellationError)
            XCTAssertNotNil(error as? CocoaError)
        }
        try Data([0xFF]).write(to: file)
        await assertFailure(.invalidUTF8, source: .file(file))
        XCTAssertEqual(try fixture.bytes(at: file), Data([0xFF]))
        try Data("Repaired 日本語\r\n".utf8).write(to: file)

        let preview = try await DemoFilePreviewService.localFiles.load(.file(file))

        XCTAssertEqual(Data(preview.text.utf8), Data("Repaired 日本語\r\n".utf8))
        XCTAssertEqual(try fixture.childNames(), ["retry.txt"])
    }

    func testDirectoriesAreNotReadAsFiles() async throws {
        let fixture = try PreviewFileFixture()
        defer { XCTAssertNoThrow(try fixture.removeOwnedDirectory()) }
        let folder = fixture.file("folder.txt")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let child = folder.appendingPathComponent("child.txt", isDirectory: false)
        try Data("keep".utf8).write(to: child)

        await assertFailure(.notRegularFile, source: .file(folder))

        XCTAssertEqual(try fixture.childNames(), ["folder.txt"])
        XCTAssertEqual(try fixture.bytes(at: child), Data("keep".utf8))
    }

    func testSelectedSymbolicLinksAreRejectedWhenLinkCreationIsPermitted() async throws {
        let fixture = try PreviewFileFixture()
        defer { XCTAssertNoThrow(try fixture.removeOwnedDirectory()) }
        let target = try fixture.write("target.txt", Data("original".utf8))
        let link = fixture.file("link.txt")
        do {
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        } catch {
            #if os(Windows)
                if isSymlinkPermissionFailure(error) {
                    throw XCTSkip("This Windows account cannot create test symlinks; no privilege change is requested.")
                }
            #endif
            throw error
        }

        await assertFailure(.notRegularFile, source: .file(link))

        XCTAssertEqual(try fixture.bytes(at: target), Data("original".utf8))
        XCTAssertEqual(
            try FileManager.default.attributesOfItem(atPath: link.path)[.type] as? FileAttributeType,
            .typeSymbolicLink)
    }

    func testInvalidURLComponentsNeverReachTheInjectedReader() async throws {
        let calls = PreviewReadCounter()
        let service = DemoFilePreviewService { _ in
            calls.increment()
            return Data("must not be read".utf8)
        }
        let local = FileManager.default.temporaryDirectory.appendingPathComponent(
            "preview-url-only.txt", isDirectory: false)
        let base = try XCTUnwrap(URLComponents(url: local, resolvingAgainstBaseURL: false))
        var candidates = [try XCTUnwrap(URL(string: "https://example.invalid/preview.txt"))]
        let changes: [(inout URLComponents) -> Void] = [
            { $0.host = "other-host" },
            { $0.user = "" },
            { $0.user = "reader" },
            {
                $0.user = "reader"
                $0.password = "secret"
            },
            { $0.port = 123 },
            { $0.query = "" },
            { $0.query = "download=1" },
            { $0.fragment = "" },
            { $0.fragment = "selection" },
            { $0.path += "\0suffix" },
            { $0.percentEncodedPath += "/%2e%2e/other.txt" },
            { $0.percentEncodedPath += "/a%2Fb.txt" },
            { $0.percentEncodedPath += "/a%2fb.txt" },
            { $0.percentEncodedPath = "//server/share/file.txt" },
        ]
        for change in changes {
            var changed = base
            change(&changed)
            candidates.append(try XCTUnwrap(changed.url))
        }
        candidates.append(try XCTUnwrap(URL(string: "child.txt", relativeTo: local.deletingLastPathComponent())))
        candidates.append(try XCTUnwrap(URL(string: "file:C:relative.txt")))
        candidates.append(try XCTUnwrap(URL(string: "file:/relative.txt")))

        for url in candidates {
            await assertFailure(.invalidFileURL, source: .file(url), service: service)
        }
        XCTAssertEqual(calls.value, 0)
    }

    func testEscapedUndecodableAuthorityAndParameterPresenceCannotDisappear() async throws {
        let calls = PreviewReadCounter()
        let service = DemoFilePreviewService { _ in
            calls.increment()
            return Data()
        }
        let local = FileManager.default.temporaryDirectory.appendingPathComponent(
            "preview-url-only.txt", isDirectory: false)
        let path = try XCTUnwrap(URLComponents(url: local, resolvingAgainstBaseURL: false)).percentEncodedPath
        // Some Foundation versions reject these spellings in URL.init itself.
        // Every spelling that reaches this API must still be rejected before IO.
        for spelling in [
            "file://%FF\(path)", "file://%FF@localhost\(path)",
            "file://localhost:\(path)", "file://localhost\(path)?%FF",
            "file://localhost\(path)#%FF", "file://reader:%FF@localhost\(path)",
        ] {
            if let url = URL(string: spelling) {
                await assertFailure(.invalidFileURL, source: .file(url), service: service)
            }
        }
        XCTAssertEqual(calls.value, 0)
    }

    func testLexicalIdentityNormalizesWithoutReplacingTheOriginalReadURL() async throws {
        let directory = FileManager.default.temporaryDirectory
        let expected = directory.appendingPathComponent("preview-url-only.txt", isDirectory: false)
        var components = try XCTUnwrap(URLComponents(url: expected, resolvingAgainstBaseURL: false))
        components.host = "LOCALHOST"
        components.path = directory.path + "//./preview-url-only.txt"
        #if os(Windows)
            if !components.path.hasPrefix("/") { components.path = "/" + components.path }
        #endif
        let original = try XCTUnwrap(components.url)
        let received = PreviewSourceWitness()
        let service = DemoFilePreviewService { source in
            received.record(source)
            return Data("fixture".utf8)
        }

        let identity = try DemoFilePreviewService.validateFileURL(original)
        _ = try await service.load(.file(original))

        XCTAssertEqual(identity, try DemoFilePreviewService.validateFileURL(expected))
        XCTAssertTrue(identity.host?.isEmpty ?? true)
        XCTAssertEqual(received.source, .file(original))
    }

    func testLiteralPercentEncodedFilenamesKeepTheirExactIdentityAndActualBytes() async throws {
        let fixture = try PreviewFileFixture()
        defer { XCTAssertNoThrow(try fixture.removeOwnedDirectory()) }
        for name in ["literal%00.txt", "literal%2F.txt"] {
            let file = try fixture.write(name, Data(name.utf8))
            let identity = try DemoFilePreviewService.validateFileURL(file)
            XCTAssertEqual(identity.path, file.path)
            let preview = try await DemoFilePreviewService.localFiles.load(.file(file))
            XCTAssertEqual(preview.text, name)
        }
        XCTAssertEqual(try fixture.childNames(), ["literal%00.txt", "literal%2F.txt"])
    }

    func testURLStorageLimitIsEnforcedBeforeReaderAdmission() async throws {
        let calls = PreviewReadCounter()
        let service = DemoFilePreviewService { _ in
            calls.increment()
            return Data()
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            String(repeating: "x", count: DemoFilePreviewService.maximumFileURLBytes), isDirectory: false)
        XCTAssertGreaterThan(url.absoluteString.utf8.count, DemoFilePreviewService.maximumFileURLBytes)

        await assertFailure(.invalidFileURL, source: .file(url), service: service)

        XCTAssertEqual(calls.value, 0)
    }

    func testWindowsDeviceNetworkStreamAndAmbiguousDriveSpellingsAreRejectedWithoutIO() async throws {
        #if os(Windows)
            let calls = PreviewReadCounter()
            let service = DemoFilePreviewService { _ in
                calls.increment()
                return Data()
            }
            for path in [
                "//server/share/preview.txt", "/C:/preview.txt:stream", "/C:/CON.txt", "/C:/NUL .txt",
                "/C:/COM1 .txt", "/C:/LPT9.txt", "/C:/COM¹.txt", "/C:/LPT².txt", "/C:/AUX",
                "/C:/CONIN$", "/C:/CONOUT$", "/C:/trailing. ", "/C:/name.", "/C:/name ",
                "/C:/bad|name", "/C:/bad\u{1}name", "/C:/bad\\name",
                "/./C:/preview.txt", "/%43:/preview.txt", "/C%3A/preview.txt", "/C:",
            ] {
                let url = try XCTUnwrap(URL(string: "file://" + path))
                await assertFailure(.invalidFileURL, source: .file(url), service: service)
            }
            for path in ["\\\\server\\share\\preview.txt", "\\\\?\\C:\\preview.txt", "\\\\.\\NUL"] {
                let url = URL(fileURLWithPath: path, isDirectory: false)
                await assertFailure(.invalidFileURL, source: .file(url), service: service)
            }
            XCTAssertEqual(calls.value, 0)
            let ordinary = URL(fileURLWithPath: "C:/ordinary/.hidden file.txt", isDirectory: false)
            XCTAssertNoThrow(try DemoFilePreviewService.validateFileURL(ordinary))
        #endif
    }

    func testAlreadyCancelledCallerNeverStartsItsInjectedReader() async {
        let admission = PreviewAsyncReadGate()
        let calls = PreviewReadCounter()
        let service = DemoFilePreviewService { _ in
            calls.increment()
            return Data()
        }
        let running = Task.detached {
            _ = try await admission.readIgnoringCancellation()
            return try await service.load(.sample(Data()))
        }
        defer {
            running.cancel()
            admission.finish(.success(Data()))
        }
        let entered = await admission.waitUntilEntered()
        XCTAssertTrue(entered)
        running.cancel()
        admission.finish(.success(Data()))

        await assertCancellation(of: running)

        XCTAssertEqual(calls.value, 0)
    }

    func testLateInjectedSuccessAndFailureCannotOverrideCallerCancellation() async {
        let results: [Result<Data, Error>] = [.success(Data("stale".utf8)), .failure(PreviewFixtureError.readFailed)]
        for result in results {
            let gate = PreviewAsyncReadGate()
            let service = DemoFilePreviewService { _ in try await gate.readIgnoringCancellation() }
            let running = Task.detached { try await service.load(.sample(Data())) }
            defer {
                running.cancel()
                gate.finish(.success(Data()))
            }
            let entered = await gate.waitUntilEntered()
            XCTAssertTrue(entered)
            running.cancel()
            gate.finish(result)

            await assertCancellation(of: running)
        }
    }

    func testCallerCancellationReachesItsOwnedWorkerBeforeTheAwaitReturns() async {
        let gate = PreviewAsyncReadGate()
        let running = Task.detached {
            try await DemoFilePreviewService.readOnWorker { try await gate.readCooperatively() }
        }
        defer {
            running.cancel()
            gate.finish(.success(Data()))
        }
        let entered = await gate.waitUntilEntered()
        XCTAssertTrue(entered)
        running.cancel()
        let cancelled = await gate.waitUntilCancelled()
        XCTAssertTrue(cancelled)
        // A broken cancellation relay must fail, then release its worker,
        // instead of hanging this test on an unreleased continuation.
        gate.finish(.success(Data("late".utf8)))

        await assertCancellation(of: running)

        XCTAssertTrue(gate.didObserveCancellation)
    }

    func testBoundedReaderRequestsOnlyChunksAndOneOverflowProbe() async throws {
        var requests: [Int] = []
        var closes = 0
        let bytes = try DemoFilePreviewService.readBoundedBytes(
            read: { requested in
                requests.append(requested)
                return requested == 1 ? nil : Data(repeating: 65, count: requested)
            },
            close: { closes += 1 })

        XCTAssertEqual(bytes.count, DemoFilePreviewService.maximumPreviewBytes)
        XCTAssertEqual(requests, Array(repeating: DemoFilePreviewService.readChunkBytes, count: 8) + [1])
        XCTAssertEqual(closes, 1)
    }

    func testShortChunksAndEmptyEOFDoNotLoseOrRepairBytes() async throws {
        let expected = Data("\u{FEFF}😀e\u{301}\r\n".utf8)
        var offset = 0
        var closes = 0
        var requestSizes: [Int] = []
        let result = try DemoFilePreviewService.readBoundedBytes(
            read: { requested in
                requestSizes.append(requested)
                guard offset < expected.count else { return Data() }
                defer { offset += 1 }
                return Data([expected[offset]])
            },
            close: { closes += 1 })

        XCTAssertEqual(result, expected)
        XCTAssertEqual(offset, expected.count)
        XCTAssertTrue(requestSizes.allSatisfy { $0 > 0 && $0 <= DemoFilePreviewService.readChunkBytes })
        XCTAssertEqual(closes, 1)
    }

    func testOverflowAndReaderContractFailureAlwaysCloseWithoutReadingTheRemainder() async {
        var requests: [Int] = []
        var closes = 0
        XCTAssertThrowsError(
            try DemoFilePreviewService.readBoundedBytes(
                read: { requested in
                    requests.append(requested)
                    return Data(repeating: 65, count: requested)
                },
                close: { closes += 1 })
        ) { XCTAssertEqual($0 as? DemoFilePreviewServiceError, .previewTooLarge) }
        XCTAssertEqual(requests, Array(repeating: DemoFilePreviewService.readChunkBytes, count: 8) + [1])
        XCTAssertEqual(requests.reduce(0, +), DemoFilePreviewService.maximumPreviewBytes + 1)
        XCTAssertEqual(closes, 1)

        var invalidReads = 0
        var invalidCloses = 0
        XCTAssertThrowsError(
            try DemoFilePreviewService.readBoundedBytes(
                read: { requested in
                    invalidReads += 1
                    return Data(repeating: 65, count: requested + 1)
                },
                close: { invalidCloses += 1 })
        ) { XCTAssertEqual($0 as? DemoFilePreviewServiceError, .previewTooLarge) }
        XCTAssertEqual(invalidReads, 1)
        XCTAssertEqual(invalidCloses, 1)
    }

    func testReadFailureAndCancellationCloseTheHandleAndStopFurtherReads() async {
        var failedReads = 0
        var failedCloses = 0
        XCTAssertThrowsError(
            try DemoFilePreviewService.readBoundedBytes(
                read: { _ in
                    failedReads += 1
                    if failedReads == 2 { throw PreviewFixtureError.readFailed }
                    return Data([65])
                },
                close: { failedCloses += 1 })
        ) { XCTAssertEqual($0 as? PreviewFixtureError, .readFailed) }
        XCTAssertEqual(failedReads, 2)
        XCTAssertEqual(failedCloses, 1)

        for allowedReads in [0, 1, 8] {
            var reads = 0
            var closes = 0
            XCTAssertThrowsError(
                try DemoFilePreviewService.readBoundedBytes(
                    read: { requested in
                        reads += 1
                        return Data(repeating: 65, count: requested)
                    },
                    close: { closes += 1 },
                    checkCancellation: {
                        if reads == allowedReads { throw CancellationError() }
                    })
            ) { XCTAssertTrue($0 is CancellationError) }
            XCTAssertEqual(reads, allowedReads)
            XCTAssertEqual(closes, 1)
        }
    }

    func testCancellationAfterCloseAndCloseFailureCannotPublishAResult() async {
        var closes = 0
        XCTAssertThrowsError(
            try DemoFilePreviewService.readBoundedBytes(
                read: { _ in nil },
                close: { closes += 1 },
                checkCancellation: {
                    if closes > 0 { throw CancellationError() }
                })
        ) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertEqual(closes, 1)

        var failedCloses = 0
        XCTAssertThrowsError(
            try DemoFilePreviewService.readBoundedBytes(
                read: { _ in nil },
                close: {
                    failedCloses += 1
                    throw PreviewFixtureError.closeFailed
                })
        ) { XCTAssertEqual($0 as? PreviewFixtureError, .closeFailed) }
        XCTAssertEqual(failedCloses, 2, "An unsuccessful explicit close receives one final cleanup attempt.")
    }

    private func assertFailure(
        _ expected: DemoFilePreviewServiceError, source: DemoFilePreviewSource,
        service: DemoFilePreviewService = .localFiles,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            _ = try await service.load(source)
            XCTFail("Expected \(expected).", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? DemoFilePreviewServiceError, expected, file: file, line: line)
        }
    }

    private func assertCancellation<Value: Sendable>(
        of task: Task<Value, Error>, file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            _ = try await task.value
            XCTFail("A cancelled caller must not publish a preview.", file: file, line: line)
        } catch {
            XCTAssertTrue(error is CancellationError, file: file, line: line)
        }
    }

    #if os(Windows)
        private func isSymlinkPermissionFailure(_ error: Error) -> Bool {
            var current = error as NSError
            for _ in 0..<4 {
                if current.domain == NSCocoaErrorDomain,
                    current.code == CocoaError.Code.fileWriteNoPermission.rawValue
                {
                    return true
                }
                if current.domain == NSPOSIXErrorDomain, [1, 13].contains(current.code) { return true }
                if ["NSWin32ErrorDomain", "org.swift.Foundation.WindowsError"].contains(current.domain),
                    current.code == 1_314
                {
                    return true
                }
                guard let underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError else { break }
                current = underlying
            }
            return false
        }
    #endif
}

private enum PreviewFixtureError: Error, Equatable {
    case readFailed
    case closeFailed
    case unsafeCleanupPath
    case waitTimedOut
}

@MainActor
private final class PreviewFileFixture {
    static let prefix = "swift-windowsui-file-preview-tests-"
    let directory: URL

    init() throws {
        directory =
            FileManager.default.temporaryDirectory.appendingPathComponent(
                Self.prefix + UUID().uuidString, isDirectory: true
            ).standardizedFileURL
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    }

    func file(_ name: String) -> URL {
        directory.appendingPathComponent(name, isDirectory: false)
    }

    func write(_ name: String, _ data: Data) throws -> URL {
        let url = file(name)
        try data.write(to: url)
        return url
    }

    func bytes(at url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try handle.read(upToCount: DemoFilePreviewService.maximumPreviewBytes + 2) ?? Data()
    }

    func childNames() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    func removeOwnedDirectory() throws {
        let temporary = FileManager.default.temporaryDirectory.standardizedFileURL
        let owned = directory.standardizedFileURL
        guard owned.deletingLastPathComponent() == temporary,
            owned.lastPathComponent.hasPrefix(Self.prefix)
        else { throw PreviewFixtureError.unsafeCleanupPath }
        try FileManager.default.removeItem(at: owned)
    }
}

private final class PreviewReadCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        count += 1
    }
}

private final class PreviewSourceWitness: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: DemoFilePreviewSource?

    var source: DemoFilePreviewSource? {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func record(_ source: DemoFilePreviewSource) {
        lock.lock()
        defer { lock.unlock() }
        recorded = source
    }
}

/// Only owned test tasks touch this gate. All mutable state is under its lock.
/// Async XCTest waiters yield the executor. A timeout releases pending reads.
private final class PreviewAsyncReadGate: @unchecked Sendable {
    private let lock = NSLock()
    private let enteredExpectation = XCTestExpectation(description: "Preview reader entered")
    private let cancelledExpectation = XCTestExpectation(description: "Preview reader observed cancellation")
    private var continuation: CheckedContinuation<Data, Error>?
    private var outcome: Result<Data, Error>?
    private var entered = false
    private var cancelled = false

    var didObserveCancellation: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func readIgnoringCancellation() async throws -> Data {
        try await withCheckedThrowingContinuation { install($0) }
    }

    func readCooperatively() async throws -> Data {
        try await withTaskCancellationHandler {
            try await readIgnoringCancellation()
        } onCancel: {
            self.recordCancellation()
        }
    }

    func waitUntilEntered() async -> Bool { await waitFor(enteredExpectation) }
    func waitUntilCancelled() async -> Bool { await waitFor(cancelledExpectation) }

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
        let firstEntry = !entered
        entered = true
        let result = outcome
        if result == nil { continuation = pending }
        lock.unlock()
        if firstEntry { enteredExpectation.fulfill() }
        if let result { pending.resume(with: result) }
    }

    private func recordCancellation() {
        lock.lock()
        let firstCancellation = !cancelled
        cancelled = true
        lock.unlock()
        finish(.failure(CancellationError()))
        if firstCancellation { cancelledExpectation.fulfill() }
    }

    private func waitFor(_ expectation: XCTestExpectation) async -> Bool {
        let result = await XCTWaiter.fulfillment(of: [expectation], timeout: 5)
        guard result == .completed else {
            // Set an outcome even if the read has not entered yet. A delayed
            // install then resumes immediately, letting its owner drain it.
            finish(.failure(PreviewFixtureError.waitTimedOut))
            return false
        }
        return true
    }
}
