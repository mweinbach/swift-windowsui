import Foundation
import SwiftWindowsGraphics
import SwiftWindowsUI

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// These limits bound owned buffers and admitted jobs, not WIC's private
/// scratch space or the images retained by the application's mounted views.
enum AsyncImageLoadingError: Error, Equatable {
    case serviceClosed
    case queueFull
    case unsupportedURLScheme
    case unsupportedFileURL
    case encodedImageTooLarge
    case invalidResponse
    case httpStatus(Int)
    case tooManyRedirects
}

/// Cancellation crosses the main actor, worker executor and URLSession's
/// delegate queue. Callbacks always run outside the lock, including late
/// registration after cancellation has already occurred.
final class AsyncImageCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var callbacks: [UUID: @Sendable () -> Void] = [:]

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func check() throws {
        if isCancelled || Task.isCancelled { throw CancellationError() }
    }

    func register(_ callback: @escaping @Sendable () -> Void) -> UUID {
        let id = UUID()
        lock.lock()
        let invokeNow = cancelled
        if !invokeNow { callbacks[id] = callback }
        lock.unlock()
        if invokeNow { callback() }
        return id
    }

    func unregister(_ id: UUID) {
        lock.lock()
        let removed = callbacks.removeValue(forKey: id)
        lock.unlock()
        // The final release of a callback's capture can itself reenter us.
        withExtendedLifetime(removed) {}
    }

    func cancel() {
        lock.lock()
        guard !cancelled else {
            lock.unlock()
            return
        }
        cancelled = true
        let pending = Array(callbacks.values)
        callbacks.removeAll()
        lock.unlock()
        for callback in pending { callback() }
    }
}

/// One host's data service; it never owns a view, phase or ObservableObject.
/// A queued request has no worker. An active request keeps its slot and its
/// continuation until the operation returns, even after cancellation/close.
final class AsyncImageService: @unchecked Sendable {
    typealias Operation = @Sendable (URL, AsyncImageCancellation) async throws -> BitmapSurface

    struct Snapshot: Equatable, Sendable {
        let activeRequests: Int
        let queuedRequests: Int
        let isClosed: Bool
    }

    private final class Request: @unchecked Sendable {
        let id = UUID()
        let url: URL
        let cancellation: AsyncImageCancellation
        // Only the service lock accesses these mutable fields.
        var continuation: CheckedContinuation<BitmapSurface, any Error>?
        var worker: Task<Void, Never>?

        init(url: URL, cancellation: AsyncImageCancellation) {
            self.url = url
            self.cancellation = cancellation
        }
    }

    private let lock = NSLock()
    private let maximumActiveRequests: Int
    private let maximumQueuedRequests: Int
    private let operation: Operation
    private var closed = false
    private var didDrainForClose = false
    private var active: [UUID: Request] = [:]
    private var queued: [Request] = []

    init(
        maximumActiveRequests: Int = 2,
        maximumQueuedRequests: Int = 64,
        operation: Operation? = nil
    ) {
        precondition((1...2).contains(maximumActiveRequests))
        precondition((0...64).contains(maximumQueuedRequests))
        self.maximumActiveRequests = maximumActiveRequests
        self.maximumQueuedRequests = maximumQueuedRequests
        self.operation = operation ?? Self.loadSource
    }

    var snapshot: Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(activeRequests: active.count, queuedRequests: queued.count, isClosed: closed)
    }

    func load(_ url: URL, cancellation: AsyncImageCancellation) async throws -> BitmapSurface {
        let request = Request(url: url, cancellation: cancellation)
        let registration = cancellation.register { [weak self, weak request] in
            guard let self, let request else { return }
            self.cancel(request)
        }
        defer { cancellation.unregister(registration) }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                enqueue(request, continuation: continuation)
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    /// The host seals admission before releasing mounted state. This phase
    /// does not cancel, resume, or release any application-owned payload.
    func closeAdmissions() {
        lock.lock()
        closed = true
        lock.unlock()
    }

    func close() {
        lock.lock()
        guard !didDrainForClose else {
            lock.unlock()
            return
        }
        // Close admission and detach pending continuations before cancellation
        // can invoke a handler which reenters this service.
        closed = true
        didDrainForClose = true
        let pending = queued
        queued.removeAll()
        let running = Array(active.values)
        let continuations = pending.compactMap { request in
            let continuation = request.continuation
            request.continuation = nil
            return continuation
        }
        lock.unlock()
        for request in pending + running { request.cancellation.cancel() }
        for continuation in continuations { continuation.resume(throwing: CancellationError()) }
    }

    private func enqueue(
        _ request: Request, continuation: CheckedContinuation<BitmapSurface, any Error>
    ) {
        lock.lock()
        let failure: (any Error)?
        var starts = false
        if request.cancellation.isCancelled {
            failure = CancellationError()
        } else if closed {
            failure = AsyncImageLoadingError.serviceClosed
        } else if active.count < maximumActiveRequests {
            failure = nil
            request.continuation = continuation
            active[request.id] = request
            starts = true
        } else if queued.count < maximumQueuedRequests {
            failure = nil
            request.continuation = continuation
            queued.append(request)
        } else {
            failure = AsyncImageLoadingError.queueFull
        }
        lock.unlock()
        if let failure { continuation.resume(throwing: failure) }
        if starts { start(request) }
    }

    private func start(_ request: Request) {
        // Deliberately detached from MainActor, but not detached from ownership:
        // the service records/cancels this handle and joins its operation via
        // the request continuation. At most two source/decode operations run;
        // a completed operation's task can still be finishing its bookkeeping.
        let worker = Task.detached(priority: .utility) { [self, request] in
            let result: Result<BitmapSurface, any Error>
            do {
                try request.cancellation.check()
                let bitmap = try await operation(request.url, request.cancellation)
                try request.cancellation.check()
                result = .success(bitmap)
            } catch {
                result = .failure(error)
            }
            finish(request, result: result)
        }
        lock.lock()
        if active[request.id] === request { request.worker = worker }
        let cancelled = closed || request.cancellation.isCancelled
        lock.unlock()
        if cancelled { worker.cancel() }
        withExtendedLifetime(worker) {}
    }

    private func cancel(_ request: Request) {
        lock.lock()
        let worker = request.worker
        var continuation: CheckedContinuation<BitmapSurface, any Error>?
        if let index = queued.firstIndex(where: { $0 === request }) {
            queued.remove(at: index)
            continuation = request.continuation
            request.continuation = nil
        }
        lock.unlock()
        worker?.cancel()
        continuation?.resume(throwing: CancellationError())
        // Active admission is released only by finish(), never by cancel().
    }

    private func finish(_ request: Request, result: Result<BitmapSurface, any Error>) {
        lock.lock()
        guard active.removeValue(forKey: request.id) != nil else {
            lock.unlock()
            return
        }
        let finishedWorker = request.worker
        request.worker = nil
        let continuation = request.continuation
        request.continuation = nil
        let wasCancelled = closed || request.cancellation.isCancelled
        let deliveredResult: Result<BitmapSurface, any Error> = wasCancelled ? .failure(CancellationError()) : result
        var starts: [Request] = []
        var cancelled: [CheckedContinuation<BitmapSurface, any Error>] = []
        var cancelledRequests: [Request] = []
        while !closed && active.count < maximumActiveRequests && !queued.isEmpty {
            let next = queued.removeFirst()
            if next.cancellation.isCancelled {
                if let continuation = next.continuation { cancelled.append(continuation) }
                next.continuation = nil
                cancelledRequests.append(next)
            } else {
                active[next.id] = next
                starts.append(next)
            }
        }
        lock.unlock()
        // Admission may have been sealed while this operation was finishing,
        // before close() collected its cancellation payload. Revoke the token
        // before resuming so that case cannot publish CancellationError as a
        // normal phase failure on a closing owner.
        if wasCancelled { request.cancellation.cancel() }
        continuation?.resume(with: deliveredResult)
        for continuation in cancelled { continuation.resume(throwing: CancellationError()) }
        for request in starts { start(request) }
        withExtendedLifetime((finishedWorker, result, cancelledRequests)) {}
    }

    private static func loadSource(_ url: URL, cancellation: AsyncImageCancellation) async throws -> BitmapSurface {
        try cancellation.check()
        if url.isFileURL {
            let path = try AsyncImageFileURL.path(url)
            let input = try BoundedImageFileReader.read(contentsOfFile: path) { try cancellation.check() }
            let decoded = try BoundedImageDecoder.decodeFirstFrame(input.data)
            try BoundedImageFileReader.validateCurrent(input.snapshot) { try cancellation.check() }
            return decoded.bitmap
        }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw AsyncImageLoadingError.unsupportedURLScheme
        }
        let data = try await AsyncImageHTTPTransport.load(url, cancellation: cancellation)
        try cancellation.check()
        return try BoundedImageDecoder.decodeFirstFrame(data).bitmap
    }
}

/// This is only the URL-to-path boundary, not the demo's stricter document URL
/// validator. In particular, never silently discard a remote or undecodable
/// authority and then publish bytes read from a different local path.
enum AsyncImageFileURL {
    static func path(_ url: URL) throws -> String {
        guard url.isFileURL else { throw AsyncImageLoadingError.unsupportedFileURL }
        let spelling = url.absoluteURL.absoluteString
        guard let colon = spelling.firstIndex(of: ":") else { throw AsyncImageLoadingError.unsupportedFileURL }
        let suffix = spelling[spelling.index(after: colon)...]
        if suffix.hasPrefix("//") {
            let authority = suffix.dropFirst(2).prefix { $0 != "/" && $0 != "?" && $0 != "#" }
            guard authority.isEmpty || authority.lowercased() == "localhost" else {
                throw AsyncImageLoadingError.unsupportedFileURL
            }
        }
        let path = url.path
        guard !path.isEmpty, !path.utf16.contains(0) else { throw AsyncImageLoadingError.unsupportedFileURL }
        return path
    }
}

struct AsyncImageDataBuffer {
    static let maximumEncodedBytes = 8_388_608
    let limit: Int
    private(set) var data = Data()

    init(limit: Int = maximumEncodedBytes) {
        precondition((0...Self.maximumEncodedBytes).contains(limit))
        self.limit = limit
    }

    func validateExpectedLength(_ length: Int64) throws {
        if length > Int64(limit) { throw AsyncImageLoadingError.encodedImageTooLarge }
    }

    mutating func append(_ chunk: Data) throws {
        guard chunk.count <= limit, data.count <= limit - chunk.count else {
            throw AsyncImageLoadingError.encodedImageTooLarge
        }
        data.append(chunk)
    }
}

/// URLSession streams bounded chunks instead of first buffering an arbitrarily
/// large `data(for:)` result. Cancellation calls the actual data task; completion
/// is not reported until URLSession sends didCompleteWithError.
final class AsyncImageHTTPTransport: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: AsyncImageDataBuffer
    private var failure: (any Error)?
    private var continuation: CheckedContinuation<Data, any Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var redirectCount = 0

    private init(maximumEncodedBytes: Int) {
        buffer = AsyncImageDataBuffer(limit: maximumEncodedBytes)
        super.init()
    }

    static func load(
        _ url: URL, cancellation: AsyncImageCancellation,
        configuration: URLSessionConfiguration = .ephemeral,
        maximumEncodedBytes: Int = AsyncImageDataBuffer.maximumEncodedBytes
    ) async throws -> Data {
        let transport = AsyncImageHTTPTransport(maximumEncodedBytes: maximumEncodedBytes)
        let registration = cancellation.register { [weak transport] in transport?.cancel() }
        defer { cancellation.unregister(registration) }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                transport.start(url, configuration: configuration, continuation: continuation)
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    private func start(
        _ url: URL, configuration: URLSessionConfiguration,
        continuation: CheckedContinuation<Data, any Error>
    ) {
        lock.lock()
        let priorFailure = failure
        lock.unlock()
        if let priorFailure {
            continuation.resume(throwing: priorFailure)
            return
        }
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.httpMaximumConnectionsPerHost = 2
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .utility
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        let task = session.dataTask(with: url)
        lock.lock()
        self.continuation = continuation
        self.session = session
        self.task = task
        let cancelled = failure != nil
        lock.unlock()
        if cancelled { task.cancel() }
        task.resume()
    }

    private func cancel() {
        lock.lock()
        if failure == nil { failure = CancellationError() }
        let task = task
        lock.unlock()
        task?.cancel()
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        lock.lock()
        if failure == nil {
            if let response = response as? HTTPURLResponse {
                if !(200...299).contains(response.statusCode) {
                    failure = AsyncImageLoadingError.httpStatus(response.statusCode)
                } else {
                    do { try buffer.validateExpectedLength(response.expectedContentLength) } catch { failure = error }
                }
            } else {
                failure = AsyncImageLoadingError.invalidResponse
            }
        }
        let permitsResponse = failure == nil
        lock.unlock()
        completionHandler(permitsResponse ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        if failure == nil {
            do { try buffer.append(data) } catch { failure = error }
        }
        let cancelled = failure != nil
        lock.unlock()
        if cancelled { dataTask.cancel() }
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        lock.lock()
        if failure == nil {
            if redirectCount >= 5 {
                failure = AsyncImageLoadingError.tooManyRedirects
            } else if let scheme = request.url?.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                redirectCount += 1
            } else {
                failure = AsyncImageLoadingError.unsupportedURLScheme
            }
        }
        let permitsRedirect = failure == nil
        lock.unlock()
        completionHandler(permitsRedirect ? request : nil)
        if !permitsRedirect { task.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        let completedTask = self.task
        self.task = nil
        self.session = nil
        let receivedData = buffer.data
        let result: Result<Data, any Error>
        if let failure = failure ?? error { result = .failure(failure) } else { result = .success(receivedData) }
        buffer = AsyncImageDataBuffer()
        lock.unlock()
        session.finishTasksAndInvalidate()
        continuation?.resume(with: result)
        withExtendedLifetime((completedTask, receivedData, error)) {}
    }
}

struct AsyncImageSource: Equatable, Sendable {
    let url: URL?
    let serviceID: ObjectIdentifier?

    init(url: URL?, service: AsyncImageService?) {
        self.url = url
        serviceID = service.map(ObjectIdentifier.init)
    }
}

/// Identity belongs to the source initializer, not to Transaction's contents.
/// Repeated builds can adopt new presentation configuration without restarting
/// the URL task or inventing equality for arbitrary transaction values.
struct AsyncImagePresentation: Equatable, Sendable {
    let id: UUID
    let source: AsyncImageSource
    let scale: Double
    let transaction: Transaction

    init(id: UUID = UUID(), source: AsyncImageSource, scale: Double, transaction: Transaction = Transaction()) {
        self.id = id
        self.source = source
        self.scale = Self.normalizedScale(scale)
        self.transaction = transaction
    }

    static func normalizedScale(_ scale: Double) -> Double {
        scale.isFinite && scale > 0 ? scale : 1
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.source == rhs.source && lhs.scale == rhs.scale
    }
}

@MainActor
public final class AsyncImageLoader: ObservableObject {
    @Published public var phase: AsyncImagePhase = .empty

    private final class Invocation: Sendable {
        let source: AsyncImageSource
        let cancellation = AsyncImageCancellation()

        init(source: AsyncImageSource) { self.source = source }
    }

    private var presentation: AsyncImagePresentation?
    private var currentSource: AsyncImageSource?
    private var publishedSource: AsyncImageSource?
    private var invocation: Invocation?
    private var bitmap: BitmapSurface?
    private var terminal = false
    private var standaloneService: AsyncImageService?
    private var manualTask: Task<Void, Never>?

    public init() {}

    init(service: AsyncImageService) { standaloneService = service }

    deinit {
        invocation?.cancellation.cancel()
        manualTask?.cancel()
        standaloneService?.close()
    }

    /// The existing imperative surface retains its own service and task.
    /// Repeating the same URL updates scale without restarting a completed or
    /// active request. Loading nil revokes the current request synchronously.
    public func load(url: URL?, scale: Double = 1) {
        let service = standaloneService ?? AsyncImageService()
        standaloneService = service
        let next = AsyncImagePresentation(
            source: AsyncImageSource(url: url, service: service), scale: scale,
            transaction: currentTransaction ?? Transaction())
        let priorScale = presentation?.scale
        configure(next)
        if url != nil && currentSource == next.source && terminal {
            if let bitmap, priorScale != next.scale {
                withTransaction(next.transaction) { phase = .success(Image(bitmap: bitmap, scale: next.scale)) }
            }
            return
        }
        let invocation = Invocation(source: next.source)
        guard begin(next, invocation: invocation) else { return }
        manualTask?.cancel()
        manualTask = Task { [weak self, invocation, service] in
            let result = await Self.result(for: invocation, service: service)
            self?.complete(invocation, result: result)
        }
    }

    func configure(_ next: AsyncImagePresentation) {
        let previousSource = presentation?.source
        presentation = next
        // This callback runs only after mounted adoption. Construction of a
        // rejected candidate cannot cancel the currently adopted URL.
        guard let previousSource, previousSource != next.source else { return }
        let retiredInvocation = invocation
        let retiredTask = manualTask
        let retiredBitmap = bitmap
        invocation = nil
        manualTask = nil
        currentSource = nil
        publishedSource = nil
        terminal = false
        bitmap = nil
        // An adopted A -> B -> A is a new source lifetime even when B's task
        // never starts. Settle all authority before cancellation or payload
        // destruction can reenter; no phase or I/O is published from adoption.
        retiredInvocation?.cancellation.cancel()
        retiredTask?.cancel()
        withExtendedLifetime(retiredBitmap) {}
    }

    func visiblePhase(for next: AsyncImagePresentation) -> AsyncImagePhase {
        guard publishedSource == next.source else { return .empty }
        if let bitmap, terminal { return .success(Image(bitmap: bitmap, scale: next.scale)) }
        return phase
    }

    func run(_ next: AsyncImagePresentation, service: AsyncImageService) async {
        // A retained task can be cancelled before its action first executes.
        guard !Task.isCancelled else { return }
        let invocation = Invocation(source: next.source)
        await withTaskCancellationHandler {
            guard !invocation.cancellation.isCancelled, !Task.isCancelled,
                begin(next, invocation: invocation)
            else { return }
            let result = await Self.result(for: invocation, service: service)
            complete(invocation, result: result)
        } onCancel: {
            // Installed before the initial phase callback: cancellation can
            // reenter there and immediately start a successor for the same URL.
            invocation.cancellation.cancel()
        }
    }

    private func begin(_ fallback: AsyncImagePresentation, invocation next: Invocation) -> Bool {
        if let presentation, presentation.source != fallback.source { return false }
        if presentation == nil { presentation = fallback }
        if fallback.source.url != nil && currentSource == fallback.source
            && (terminal || invocation?.cancellation.isCancelled == false)
        {
            return false
        }
        let previous = invocation
        invocation = next
        currentSource = fallback.source
        publishedSource = fallback.source
        bitmap = nil
        terminal = fallback.source.url == nil
        // Set every identity/terminal field before either cancellation or
        // @Published can reenter. No deferred cleanup may erase a successor.
        previous?.cancellation.cancel()
        guard invocation === next, presentation?.source == next.source else { return false }
        let transaction = presentation?.transaction ?? fallback.transaction
        withTransaction(transaction) { phase = .empty }
        guard invocation === next, presentation?.source == next.source,
            !next.cancellation.isCancelled, next.source.url != nil
        else { return false }
        return true
    }

    private nonisolated static func result(
        for invocation: Invocation, service: AsyncImageService
    ) async -> Result<BitmapSurface, any Error> {
        do {
            try invocation.cancellation.check()
            guard let url = invocation.source.url else { throw CancellationError() }
            let bitmap = try await service.load(url, cancellation: invocation.cancellation)
            try invocation.cancellation.check()
            return .success(bitmap)
        } catch {
            return .failure(error)
        }
    }

    private func complete(_ completed: Invocation, result: Result<BitmapSurface, any Error>) {
        guard invocation === completed, presentation?.source == completed.source else { return }
        invocation = nil
        manualTask = nil
        guard !completed.cancellation.isCancelled, !Task.isCancelled else { return }
        terminal = true
        publishedSource = completed.source
        let scale = presentation?.scale ?? 1
        let transaction = presentation?.transaction ?? Transaction()
        let newPhase: AsyncImagePhase
        switch result {
        case .success(let bitmap):
            self.bitmap = bitmap
            newPhase = .success(Image(bitmap: bitmap, scale: scale))
        case .failure(let error):
            bitmap = nil
            newPhase = .failure(error)
        }
        withTransaction(transaction) { phase = newPhase }
    }
}

private enum AsyncImageServiceKey: EnvironmentKey {
    static let defaultValue: AsyncImageService? = nil
}

extension EnvironmentValues {
    var asyncImageService: AsyncImageService? {
        get { self[AsyncImageServiceKey.self] }
        set { self[AsyncImageServiceKey.self] = newValue }
    }
}

@MainActor
struct MountedAsyncImage: View {
    @StateObject private var loader = AsyncImageLoader()
    let presentation: AsyncImagePresentation
    let service: AsyncImageService?
    let content: (AsyncImagePhase) -> AnyView

    init(
        presentation: AsyncImagePresentation, service: AsyncImageService?,
        content: @escaping (AsyncImagePhase) -> AnyView
    ) {
        self.presentation = presentation
        self.service = service
        self.content = content
    }

    var body: some View {
        let loader = loader
        // A real container remains the task's target even when the default
        // placeholder is empty, including inside a managed List row.
        return ZStack {
            content(loader.visiblePhase(for: presentation))
        }
        .onChange(of: presentation, initial: true) { _, adopted in loader.configure(adopted) }
        .task(id: presentation.source) {
            guard let service else { return }
            await loader.run(presentation, service: service)
        }
    }
}
