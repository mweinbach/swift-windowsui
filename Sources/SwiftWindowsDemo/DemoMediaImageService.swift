import Foundation

#if canImport(SwiftUI)
    import SwiftUI
#else
    import WinSwiftUI
#endif

public enum DemoMediaImageSource: Equatable, Sendable {
    case file(URL)
    /// Real encoded image bytes. Data sources are decoded but never cached.
    case data(Data)
}

public enum DemoMediaImageCachePolicy: Equatable, Sendable {
    case useCached
    /// Invalidates every size/revision of this file before attempting a reread.
    case reload
}

public struct DemoMediaImageServiceStatistics: Equatable, Sendable {
    public let activeWorkerCount: Int
    public let cachedImageCount: Int
    public let cachedPixelBytes: Int
    public let isClosed: Bool
}

/// Own one instance at a browser/window root. There is no global cache and no
/// implicit queue: a third physical load fails with `busy` until a slot drains.
public actor DemoMediaImageService {
    public static let maximumEncodedBytes = 8_388_608
    public static let maximumSourcePixels = 16_000_000
    public static let maximumPixelDimension = 1024
    public static let maximumActiveWorkers = 2
    public static let maximumCachedImages = 32
    public static let maximumCachedPixelBytes = 16_777_216
    static let readChunkBytes = 65_536

    private let readBytes: @Sendable (DemoMediaImageSource) async throws -> Data
    private var active: [UUID: ActiveLoad] = [:]
    private var cache: [CacheEntry] = []
    private var cachedPixelBytes = 0
    private var isClosed = false

    public init() {
        readBytes = { try Self.readLocalBytes($0) }
    }

    /// A replacement adapter still passes admission, returned-size, decoding,
    /// ownership, and cancellation checks. It must bound its own allocations.
    public init(readBytes: @escaping @Sendable (DemoMediaImageSource) async throws -> Data) {
        self.readBytes = readBytes
    }

    public var statistics: DemoMediaImageServiceStatistics {
        DemoMediaImageServiceStatistics(
            activeWorkerCount: active.count, cachedImageCount: cache.count,
            cachedPixelBytes: cachedPixelBytes, isClosed: isClosed)
    }

    /// `revision` is caller-owned content identity, not filesystem metadata.
    /// A changed revision revokes older results for the same lexical file URL.
    /// External edits require reload/invalidation or a changed revision.
    public func load(
        _ source: DemoMediaImageSource, maximumPixelDimension: Int = 256,
        revision: UInt64 = 0, cachePolicy: DemoMediaImageCachePolicy = .useCached
    ) async throws -> DemoMediaImage {
        let operation = DemoMediaImageOperation()
        return try await withTaskCancellationHandler {
            try operation.checkCancellation()
            try Task.checkCancellation()
            guard !isClosed else { throw DemoMediaImageError.closed }
            guard (1...Self.maximumPixelDimension).contains(maximumPixelDimension) else {
                throw DemoMediaImageError.invalidPixelDimension
            }
            let fileURL = try Self.admit(source)
            let key = fileURL.map { CacheKey(url: $0, revision: revision, edge: maximumPixelDimension) }
            if let fileURL {
                revoke(fileURL: fileURL, exceptRevision: cachePolicy == .reload ? nil : revision)
            }
            if let key, let index = cache.firstIndex(where: { $0.key == key }) {
                return try operation.publish {
                    let entry = cache.remove(at: index)
                    cache.append(entry)
                    return entry.image
                }
            }
            try operation.checkCancellation()
            guard active.count < Self.maximumActiveWorkers else { throw DemoMediaImageError.busy }
            let identifier = UUID()
            let reader = readBytes
            let worker = Task.detached(priority: .utility) {
                try operation.checkCancellation()
                try Task.checkCancellation()
                let data = try await reader(source)
                try operation.checkCancellation()
                try Task.checkCancellation()
                guard data.count <= Self.maximumEncodedBytes else { throw DemoMediaImageError.encodedImageTooLarge }
                let image = try DemoMediaImage.decode(data, maximumPixelDimension: maximumPixelDimension)
                try operation.checkCancellation()
                try Task.checkCancellation()
                return image
            }
            active[identifier] = ActiveLoad(key: key, operation: operation)
            operation.install(worker)
            // Neither cancellation nor invalidation releases this occupied slot.
            // Only the awaited worker's actual success/failure reaches this defer.
            defer { active.removeValue(forKey: identifier) }
            do {
                let image = try await worker.value
                return try operation.publish {
                    if let key { insert(image, for: key) }
                    return image
                }
            } catch {
                return try operation.publish { throw error }
            }
        } onCancel: {
            operation.cancel()
        }
    }

    /// Does not start work. It revokes both cached content and in-flight loads.
    public func invalidate(_ fileURL: URL) throws {
        let identity = try Self.fileIdentity(fileURL)
        revoke(fileURL: identity, exceptRevision: nil)
    }

    public func invalidateAll() {
        cache.removeAll()
        cachedPixelBytes = 0
        for load in active.values { load.operation.cancel() }
    }

    /// Terminal. Awaiting loads remain responsible for draining their workers.
    public func close() {
        isClosed = true
        invalidateAll()
    }

    private func revoke(fileURL: URL, exceptRevision revision: UInt64?) {
        cache.removeAll { entry in
            guard entry.key.url == fileURL, revision == nil || entry.key.revision != revision else { return false }
            cachedPixelBytes -= entry.image.byteCount
            return true
        }
        for load in active.values {
            if let key = load.key, key.url == fileURL, revision == nil || key.revision != revision {
                load.operation.cancel()
            }
        }
    }

    private func insert(_ image: DemoMediaImage, for key: CacheKey) {
        let cost = image.byteCount
        guard cost > 0, cost <= Self.maximumCachedPixelBytes else { return }
        if let index = cache.firstIndex(where: { $0.key == key }) {
            cachedPixelBytes -= cache.remove(at: index).image.byteCount
        }
        while !cache.isEmpty,
            cache.count >= Self.maximumCachedImages || cachedPixelBytes > Self.maximumCachedPixelBytes - cost
        {
            cachedPixelBytes -= cache.removeFirst().image.byteCount
        }
        cache.append(CacheEntry(key: key, image: image))
        cachedPixelBytes += cost
    }

    private static func admit(_ source: DemoMediaImageSource) throws -> URL? {
        switch source {
        case .file(let url): return try fileIdentity(url)
        case .data(let data):
            guard data.count <= maximumEncodedBytes else { throw DemoMediaImageError.encodedImageTooLarge }
            return nil
        }
    }

    private static func fileIdentity(_ url: URL) throws -> URL {
        do { return try DemoFilePreviewService.validateFileURL(url) } catch { throw DemoMediaImageError.invalidFileURL }
    }

    private static func readLocalBytes(_ source: DemoMediaImageSource) throws -> Data {
        try Task.checkCancellation()
        switch source {
        case .data(let bytes): return bytes
        case .file(let originalURL):
            _ = try fileIdentity(originalURL)
            #if os(macOS)
                let scopedAccess = originalURL.startAccessingSecurityScopedResource()
                defer { if scopedAccess { originalURL.stopAccessingSecurityScopedResource() } }
            #endif
            try Task.checkCancellation()
            let attributes = try FileManager.default.attributesOfItem(atPath: originalURL.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else {
                throw DemoMediaImageError.notRegularFile
            }
            try Task.checkCancellation()
            // Metadata and open are separate operations, not a no-follow open.
            // Ancestors, mapped drives, and providers can resolve remotely.
            let handle = try FileHandle(forReadingFrom: originalURL)
            return try readBoundedBytes(read: { try handle.read(upToCount: $0) }, close: { try handle.close() })
        }
    }

    static func readBoundedBytes(
        read: (Int) throws -> Data?, close: () throws -> Void,
        checkCancellation: () throws -> Void = { try Task.checkCancellation() }
    ) throws -> Data {
        var didClose = false
        defer { if !didClose { try? close() } }
        var bytes = Data()
        var reachedEnd = false
        while bytes.count < maximumEncodedBytes {
            try checkCancellation()
            let requested = min(readChunkBytes, maximumEncodedBytes - bytes.count)
            guard let chunk = try read(requested), !chunk.isEmpty else {
                reachedEnd = true
                break
            }
            guard chunk.count <= requested else { throw DemoMediaImageError.encodedImageTooLarge }
            bytes.append(chunk)
        }
        if !reachedEnd {
            try checkCancellation()
            if let overflow = try read(1), !overflow.isEmpty { throw DemoMediaImageError.encodedImageTooLarge }
        }
        try checkCancellation()
        try close()
        didClose = true
        try checkCancellation()
        return bytes
    }

    private struct CacheKey: Equatable, Sendable {
        let url: URL
        let revision: UInt64
        let edge: Int
    }

    private struct CacheEntry: Sendable {
        let key: CacheKey
        let image: DemoMediaImage
    }

    private struct ActiveLoad: Sendable {
        let key: CacheKey?
        let operation: DemoMediaImageOperation
    }
}

/// Synchronizes cancellation with worker installation and the publication
/// linearization point. A cancellation that wins this lock prevents cache/result
/// publication; once publication wins, later cancellation cannot revoke it.
final class DemoMediaImageOperation: @unchecked Sendable {
    private let lock = NSLock()
    private var isCancelled = false
    private var isCompleted = false
    private var worker: Task<DemoMediaImage, Error>?

    func install(_ task: Task<DemoMediaImage, Error>) {
        lock.lock()
        let cancel = isCancelled
        if !isCompleted { worker = task }
        lock.unlock()
        if cancel { task.cancel() }
    }

    func cancel() {
        lock.lock()
        guard !isCompleted else {
            lock.unlock()
            return
        }
        isCancelled = true
        let task = worker
        lock.unlock()
        task?.cancel()
    }

    func checkCancellation() throws {
        lock.lock()
        let cancelled = isCancelled
        lock.unlock()
        if cancelled { throw CancellationError() }
    }

    func publish<T>(_ body: () throws -> T) throws -> T {
        lock.lock()
        guard !isCancelled else {
            lock.unlock()
            throw CancellationError()
        }
        isCompleted = true
        let completedWorker = worker
        worker = nil
        lock.unlock()
        // The actor performs no await between this authority commit and the
        // cache/result write. Later cancellation cannot revoke committed work.
        // Cache eviction, payload release and task destruction happen unlocked.
        defer { withExtendedLifetime(completedWorker) {} }
        return try body()
    }
}
