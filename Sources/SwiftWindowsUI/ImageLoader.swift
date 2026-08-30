import Foundation
import SwiftWindowsGraphics
import WinSDK

/// Loads named/local WIC images synchronously, preserving their admitted full
/// size, first frame, raw orientation and straight-alpha BGRA pixels.
@MainActor
public enum ImageLoader {
    // A process budget for this cache's retained Data, not for surfaces retained
    // by views, renderer caches, or the native codec's own working memory.
    private static let loader = ImageLoaderStore(
        openFile: NativeImageLoaderFile.open,
        decode: { try BoundedImageDecoder.decodeFirstFrame($0).bitmap })

    public static func load(contentsOfFile path: String) -> BitmapSurface? {
        try? loader.load(contentsOfFile: path)
    }
}

enum ImageLoaderLimits {
    static let cacheEntries = 64
    static let cachePixelBytes = 32 * 1024 * 1024
    static let encodedBytes = 8 * 1024 * 1024
    static let sourcePixels = 16_000_000
    static let decodedBytes = 64_000_000
    static let readChunkBytes = 64 * 1024
}

enum ImageLoaderFailure: Error, Equatable {
    case invalidPath
    case unreadableFile
    case encodedLimitExceeded
    case invalidReadResult
    case changedSource
    case unavailableFileIdentity
    case invalidDecodedBitmap
    case decodedLimitExceeded
}

struct ImageLoaderFileIdentity: Hashable, Sendable {
    let volume: UInt64
    let identifier: Data
    // NTFS data streams share their parent file's ID and timestamps. Preserve
    // the selected stream spelling too; case-only aliases may miss the cache,
    // but two equal-length streams must never share each other's pixels.
    let streamName: [UInt16]

    init(volume: UInt64, identifier: Data, streamName: [UInt16] = []) {
        self.volume = volume
        self.identifier = identifier
        self.streamName = streamName
    }

    static func streamName(inResolvedPath path: String) -> [UInt16] {
        streamName(inResolvedPathUTF16: Array(path.utf16))
    }

    static func streamName(inResolvedPathUTF16 units: [UInt16]) -> [UInt16] {
        let start =
            units.lastIndex(where: { $0 == 0x2F || $0 == 0x5C }).map { units.index(after: $0) }
            ?? units.startIndex
        guard let colon = units[start...].firstIndex(of: 0x3A) else { return [] }
        // Work in UTF-16 rather than Character so a combining mark after ':'
        // cannot hide the native stream delimiter inside a grapheme cluster.
        // NTFS can also distinguish canonically equivalent Unicode spellings;
        // String equality would merge those stream names even without folding.
        return Array(units[colon...])
    }
}

struct ImageLoaderFileMetadata: Equatable, Sendable {
    let identity: ImageLoaderFileIdentity?
    let byteCount: UInt64
    let creationTime: UInt64
    let modificationTime: UInt64
    let changeTime: Int64?
}

/// A synchronous, stack-owned source. Implementations must return at most the
/// requested bytes and release their handle when close() is called. It never
/// crosses an actor boundary; only immutable read results do.
protocol ImageLoaderFileSource: AnyObject {
    func metadata() throws -> ImageLoaderFileMetadata
    func read(upToCount count: Int) throws -> Data
    func close()
}

/// Shared file I/O for named images and asynchronous image requests. Each read
/// uses one opened handle and bounded chunks; there is no cache or global state.
package enum BoundedImageFileReader {
    package struct Snapshot: Equatable, Sendable {
        package let path: String
        fileprivate let metadata: ImageLoaderFileMetadata

        package var hasStableIdentity: Bool { metadata.identity != nil }
        package var byteCount: UInt64 { metadata.byteCount }
    }

    package struct ReadResult: Sendable {
        package let data: Data
        package let snapshot: Snapshot
    }

    package static func read(
        contentsOfFile path: String,
        cancellationCheck: @Sendable () throws -> Void
    ) throws -> ReadResult {
        try read(
            contentsOfFile: path, maximumBytes: ImageLoaderLimits.encodedBytes,
            openFile: NativeImageLoaderFile.open, cancellationCheck: cancellationCheck)
    }

    /// This checks the source at the time of the reopened-handle observation.
    /// Another process can change the path after this returns, including during
    /// an executor hop. Callers still need request-generation admission; this
    /// is ordinary file freshness, not atomic publication or content attestation.
    package static func validateCurrent(
        _ snapshot: Snapshot,
        cancellationCheck: @Sendable () throws -> Void
    ) throws {
        try validateCurrent(
            snapshot, openFile: NativeImageLoaderFile.open, cancellationCheck: cancellationCheck)
    }

    static func read(
        contentsOfFile path: String, maximumBytes: Int,
        openFile: (String) throws -> any ImageLoaderFileSource,
        cancellationCheck: @Sendable () throws -> Void
    ) throws -> ReadResult {
        try cancellationCheck()
        let resolvedPath = try checkedPath(path)
        let file = try openFile(resolvedPath)
        defer { file.close() }
        try cancellationCheck()
        let before = try file.metadata()
        try cancellationCheck()
        let data = try readOpenedFile(
            file, before: before, maximumBytes: maximumBytes, cancellationCheck: cancellationCheck)
        return ReadResult(data: data, snapshot: Snapshot(path: resolvedPath, metadata: before))
    }

    static func validateCurrent(
        _ snapshot: Snapshot,
        openFile: (String) throws -> any ImageLoaderFileSource,
        cancellationCheck: @Sendable () throws -> Void
    ) throws {
        try cancellationCheck()
        guard snapshot.hasStableIdentity else { throw ImageLoaderFailure.unavailableFileIdentity }
        let file = try openFile(snapshot.path)
        defer { file.close() }
        try cancellationCheck()
        let current = try file.metadata()
        try cancellationCheck()
        guard current == snapshot.metadata else { throw ImageLoaderFailure.changedSource }
    }

    static func checkedPath(_ path: String) throws -> String {
        guard !path.isEmpty, !path.utf16.contains(0) else { throw ImageLoaderFailure.invalidPath }
        // Resolve relative paths now, so a later current-directory change cannot
        // change the meaning of an asynchronous request's freshness snapshot.
        return URL(fileURLWithPath: path).path
    }

    static func readOpenedFile(
        _ file: any ImageLoaderFileSource, before: ImageLoaderFileMetadata, maximumBytes: Int,
        cancellationCheck: @Sendable () throws -> Void
    ) throws -> Data {
        let limit = max(0, min(maximumBytes, ImageLoaderLimits.encodedBytes))
        guard before.byteCount <= UInt64(limit) else { throw ImageLoaderFailure.encodedLimitExceeded }
        var data = Data()
        var reachedEnd = false
        while data.count < limit {
            let requested = min(ImageLoaderLimits.readChunkBytes, limit - data.count)
            try cancellationCheck()
            let chunk = try file.read(upToCount: requested)
            try cancellationCheck()
            guard chunk.count <= requested else { throw ImageLoaderFailure.invalidReadResult }
            if chunk.isEmpty {
                reachedEnd = true
                break
            }
            data.append(chunk)
        }
        if !reachedEnd {
            // One byte distinguishes an exact fit from overflow without ever
            // allocating from the reported size or reading the entire remainder.
            try cancellationCheck()
            let overflow = try file.read(upToCount: 1)
            try cancellationCheck()
            guard overflow.count <= 1 else { throw ImageLoaderFailure.invalidReadResult }
            guard overflow.isEmpty else { throw ImageLoaderFailure.encodedLimitExceeded }
        }
        let after = try file.metadata()
        try cancellationCheck()
        guard after == before, UInt64(data.count) == before.byteCount else {
            throw ImageLoaderFailure.changedSource
        }
        return data
    }
}

@MainActor
final class ImageLoaderStore {
    private var cache: ImageLoaderBitmapCache
    private let encodedByteLimit: Int
    private let openFile: (String) throws -> any ImageLoaderFileSource
    private let decode: (Data) throws -> BitmapSurface

    init(
        maximumEntries: Int = ImageLoaderLimits.cacheEntries,
        maximumCachedBytes: Int = ImageLoaderLimits.cachePixelBytes,
        maximumEncodedBytes: Int = ImageLoaderLimits.encodedBytes,
        openFile: @escaping (String) throws -> any ImageLoaderFileSource,
        decode: @escaping (Data) throws -> BitmapSurface
    ) {
        cache = ImageLoaderBitmapCache(maximumEntries: maximumEntries, maximumBytes: maximumCachedBytes)
        encodedByteLimit = max(0, min(maximumEncodedBytes, ImageLoaderLimits.encodedBytes))
        self.openFile = openFile
        self.decode = decode
    }

    var cachedEntryCount: Int { cache.count }
    var cachedPixelBytes: Int { cache.pixelBytes }

    func load(contentsOfFile path: String) throws -> BitmapSurface {
        let file = try openFile(BoundedImageFileReader.checkedPath(path))
        defer { file.close() }
        let before = try file.metadata()
        do {
            guard before.byteCount <= UInt64(encodedByteLimit) else {
                throw ImageLoaderFailure.encodedLimitExceeded
            }
            if let bitmap = cache.value(for: before) {
                guard try file.metadata() == before else { throw ImageLoaderFailure.changedSource }
                return bitmap
            }
            let data = try BoundedImageFileReader.readOpenedFile(
                file, before: before, maximumBytes: encodedByteLimit, cancellationCheck: {})
            let bitmap = try decode(data)
            try Self.validate(bitmap)
            guard try file.metadata() == before else { throw ImageLoaderFailure.changedSource }
            cache.insert(bitmap, for: before)
            return bitmap
        } catch {
            // Never fall back to an earlier version after a failed refresh.
            cache.remove(identity: before.identity)
            throw error
        }
    }

    static func validate(_ bitmap: BitmapSurface) throws {
        guard bitmap.width > 0, bitmap.height > 0, bitmap.bytesPerRow > 0 else {
            throw ImageLoaderFailure.invalidDecodedBitmap
        }
        let pixels = Int(bitmap.width).multipliedReportingOverflow(by: Int(bitmap.height))
        let stride = Int(bitmap.width).multipliedReportingOverflow(by: 4)
        let describedBytes = Int(bitmap.bytesPerRow).multipliedReportingOverflow(by: Int(bitmap.height))
        guard !pixels.overflow, pixels.partialValue <= ImageLoaderLimits.sourcePixels,
            !describedBytes.overflow, describedBytes.partialValue <= ImageLoaderLimits.decodedBytes,
            bitmap.pixels.count <= ImageLoaderLimits.decodedBytes
        else { throw ImageLoaderFailure.decodedLimitExceeded }
        guard !stride.overflow, Int(bitmap.bytesPerRow) >= stride.partialValue,
            bitmap.pixels.count >= describedBytes.partialValue
        else { throw ImageLoaderFailure.invalidDecodedBitmap }
    }
}

/// A small process cache. Hits only update one stamp; insertion may inspect at
/// most the configured entry cap per eviction. Cost includes row padding and
/// trailing Data bytes. Data allocator overhead is not included in this budget.
@MainActor
struct ImageLoaderBitmapCache {
    private struct Entry {
        let metadata: ImageLoaderFileMetadata
        let bitmap: BitmapSurface
        let cost: Int
        var lastAccess: UInt64
    }

    private var entries: [ImageLoaderFileIdentity: Entry] = [:]
    private let maximumEntries: Int
    private let maximumBytes: Int
    private var accessClock: UInt64
    private(set) var pixelBytes = 0

    init(
        maximumEntries: Int = ImageLoaderLimits.cacheEntries,
        maximumBytes: Int = ImageLoaderLimits.cachePixelBytes,
        initialAccessClock: UInt64 = 0
    ) {
        self.maximumEntries = max(0, min(maximumEntries, ImageLoaderLimits.cacheEntries))
        self.maximumBytes = max(0, min(maximumBytes, ImageLoaderLimits.cachePixelBytes))
        accessClock = initialAccessClock
    }

    var count: Int { entries.count }

    mutating func value(for metadata: ImageLoaderFileMetadata) -> BitmapSurface? {
        guard let identity = metadata.identity, var entry = entries[identity] else { return nil }
        guard entry.metadata == metadata else {
            remove(identity: identity)
            return nil
        }
        entry.lastAccess = nextAccessStamp()
        entries[identity] = entry
        return entry.bitmap
    }

    mutating func insert(_ bitmap: BitmapSurface, for metadata: ImageLoaderFileMetadata) {
        guard let identity = metadata.identity else { return }
        remove(identity: identity)
        let cost = bitmap.pixels.count
        guard maximumEntries > 0, cost <= maximumBytes,
            (try? ImageLoaderStore.validate(bitmap)) != nil
        else { return }
        while entries.count >= maximumEntries || pixelBytes > maximumBytes - cost {
            guard let oldest = entries.min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key else { break }
            remove(identity: oldest)
        }
        let stamp = nextAccessStamp()
        entries[identity] = Entry(metadata: metadata, bitmap: bitmap, cost: cost, lastAccess: stamp)
        pixelBytes += cost
    }

    mutating func remove(identity: ImageLoaderFileIdentity?) {
        guard let identity, let old = entries.removeValue(forKey: identity) else { return }
        pixelBytes -= old.cost
    }

    private mutating func nextAccessStamp() -> UInt64 {
        if accessClock == .max {
            let ordered = entries.sorted { $0.value.lastAccess < $1.value.lastAccess }.map(\.key)
            accessClock = 0
            for key in ordered {
                accessClock += 1
                entries[key]?.lastAccess = accessClock
            }
        }
        accessClock += 1
        return accessClock
    }
}

/// The handle is used only synchronously on its opening thread and explicitly
/// closed by the caller's defer. It is never captured by a worker result.
private final class NativeImageLoaderFile: ImageLoaderFileSource {
    private var handle: HANDLE?
    private let streamName: [UInt16]?

    private init(handle: HANDLE) {
        self.handle = handle
        streamName = Self.openedStreamName(handle)
    }

    static func open(_ path: String) throws -> any ImageLoaderFileSource {
        let handle = path.withCString(encodedAs: UTF16.self) { widePath in
            CreateFileW(
                widePath, DWORD(GENERIC_READ), DWORD(FILE_SHARE_READ), nil, DWORD(OPEN_EXISTING),
                DWORD(FILE_ATTRIBUTE_NORMAL | FILE_FLAG_SEQUENTIAL_SCAN), nil)
        }
        guard let handle, handle != INVALID_HANDLE_VALUE else { throw ImageLoaderFailure.unreadableFile }
        return NativeImageLoaderFile(handle: handle)
    }

    func metadata() throws -> ImageLoaderFileMetadata {
        guard let handle, GetFileType(handle) == DWORD(FILE_TYPE_DISK) else {
            throw ImageLoaderFailure.unreadableFile
        }
        var information = BY_HANDLE_FILE_INFORMATION()
        guard GetFileInformationByHandle(handle, &information),
            information.dwFileAttributes & DWORD(FILE_ATTRIBUTE_DIRECTORY) == 0
        else { throw ImageLoaderFailure.unreadableFile }

        var identity: ImageLoaderFileIdentity?
        var fullIdentity = FILE_ID_INFO()
        if let streamName,
            GetFileInformationByHandleEx(handle, FileIdInfo, &fullIdentity, DWORD(MemoryLayout<FILE_ID_INFO>.size))
        {
            let bytes = withUnsafeBytes(of: fullIdentity.FileId.Identifier) { Data($0) }
            identity = ImageLoaderFileIdentity(
                volume: fullIdentity.VolumeSerialNumber, identifier: bytes, streamName: streamName)
        }
        var basic = FILE_BASIC_INFO()
        let hasBasic = GetFileInformationByHandleEx(
            handle, FileBasicInfo, &basic, DWORD(MemoryLayout<FILE_BASIC_INFO>.size))
        return ImageLoaderFileMetadata(
            identity: identity,
            byteCount: Self.combine(information.nFileSizeHigh, information.nFileSizeLow),
            creationTime: Self.combine(
                information.ftCreationTime.dwHighDateTime, information.ftCreationTime.dwLowDateTime),
            modificationTime: Self.combine(
                information.ftLastWriteTime.dwHighDateTime, information.ftLastWriteTime.dwLowDateTime),
            changeTime: hasBasic ? basic.ChangeTime.QuadPart : nil)
    }

    func read(upToCount count: Int) throws -> Data {
        guard let handle, count > 0, count <= ImageLoaderLimits.readChunkBytes else {
            throw ImageLoaderFailure.invalidReadResult
        }
        var data = Data(count: count)
        var readCount: DWORD = 0
        let succeeded = data.withUnsafeMutableBytes { bytes in
            ReadFile(handle, bytes.baseAddress, DWORD(count), &readCount, nil)
        }
        guard succeeded else { throw ImageLoaderFailure.unreadableFile }
        guard readCount <= DWORD(count) else { throw ImageLoaderFailure.invalidReadResult }
        data.removeSubrange(Int(readCount)..<data.count)
        return data
    }

    func close() {
        guard let handle else { return }
        self.handle = nil
        _ = CloseHandle(handle)
    }

    private static func combine(_ high: DWORD, _ low: DWORD) -> UInt64 {
        (UInt64(high) << 32) | UInt64(low)
    }

    private static func openedStreamName(_ handle: HANDLE) -> [UInt16]? {
        guard GetFileType(handle) == DWORD(FILE_TYPE_DISK) else { return nil }
        let flags = DWORD(FILE_NAME_NORMALIZED | VOLUME_NAME_DOS)
        let required = GetFinalPathNameByHandleW(handle, nil, 0, flags)
        // A fixed upper bound also covers the extended Windows path form. An
        // unavailable/unstable final name makes the source uncacheable; legacy
        // reads still use their opened handle and bounded decoder normally.
        guard required > 0, required <= 32_768 else { return nil }
        var path = [WCHAR](repeating: 0, count: Int(required))
        let written = path.withUnsafeMutableBufferPointer { buffer in
            GetFinalPathNameByHandleW(handle, buffer.baseAddress, DWORD(buffer.count), flags)
        }
        guard written > 0, written < required, path[Int(written)] == 0 else { return nil }
        // Query the opened object rather than parsing the caller's spelling:
        // a reparse alias can resolve to a different file or data stream.
        return ImageLoaderFileIdentity.streamName(inResolvedPathUTF16: Array(path.prefix(Int(written))))
    }
}
