import Foundation

#if canImport(SwiftUI)
    import SwiftUI
#else
    import WinSwiftUI
#endif

/// Both sources pass through the same size and exact UTF-8 checks.
public enum DemoFilePreviewSource: Equatable, Sendable {
    case file(URL)
    case sample(Data)
}

public struct DemoFilePreview: Equatable, Sendable {
    public let text: String
    public let byteCount: Int

    public init(text: String, byteCount: Int) {
        self.text = text
        self.byteCount = byteCount
    }
}

public enum DemoFilePreviewServiceError: Error, Equatable, Sendable, LocalizedError {
    case invalidFileURL
    case notRegularFile
    case previewTooLarge
    case invalidUTF8

    public var errorDescription: String? {
        switch self {
        case .invalidFileURL:
            return "Choose an absolute local file URL without parent traversal, credentials, or URL parameters."
        case .notRegularFile:
            return "Only regular files can be previewed. Folders and symbolic links are not supported."
        case .previewTooLarge:
            return "This file exceeds the 64 KiB preview limit."
        case .invalidUTF8:
            return "This file is not valid UTF-8 text."
        }
    }
}

/// A read-only adapter. Its caller owns admission and the number of active loads.
public struct DemoFilePreviewService: Sendable {
    public static let maximumPreviewBytes = 65_536
    public static let maximumFileURLBytes = 32_768
    static let readChunkBytes = 8_192

    private let readBytes: @Sendable (DemoFilePreviewSource) async throws -> Data

    public init(readBytes: @escaping @Sendable (DemoFilePreviewSource) async throws -> Data) {
        self.readBytes = readBytes
    }

    public func load(_ source: DemoFilePreviewSource) async throws -> DemoFilePreview {
        try Task.checkCancellation()
        switch source {
        case .file(let url):
            _ = try Self.validateFileURL(url)
        case .sample(let bytes):
            guard bytes.count <= Self.maximumPreviewBytes else {
                throw DemoFilePreviewServiceError.previewTooLarge
            }
        }

        // Preserve the original URL, including its security-scoped capability.
        // An injected reader cannot bypass cancellation, size, or codec checks.
        let bytes: Data
        do {
            bytes = try await readBytes(source)
        } catch {
            try Task.checkCancellation()
            throw error
        }
        try Task.checkCancellation()
        guard bytes.count <= Self.maximumPreviewBytes else {
            throw DemoFilePreviewServiceError.previewTooLarge
        }
        let text = String(decoding: bytes, as: UTF8.self)
        guard text.utf8.elementsEqual(bytes) else {
            throw DemoFilePreviewServiceError.invalidUTF8
        }
        try Task.checkCancellation()
        return DemoFilePreview(text: text, byteCount: bytes.count)
    }

    /// Returns a lexical identity without filesystem access or symlink resolution.
    ///
    /// Dot components and repeated separators are removed. Parent traversal is
    /// rejected because collapsing it can change a path through a symbolic link.
    /// This does not identify case aliases, hard links, or equivalent mounts.
    public static func validateFileURL(_ url: URL) throws -> URL {
        let spelling = url.absoluteString
        guard spelling.utf8.count <= maximumFileURLBytes,
            spelling.prefix(7).lowercased() == "file://",
            url.isFileURL, url.baseURL == nil,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.percentEncodedUser == nil, components.percentEncodedPassword == nil,
            components.rangeOfPort == nil,
            components.percentEncodedQuery == nil, components.percentEncodedFragment == nil,
            !components.percentEncodedPath.lowercased().contains("%2f"),
            let path = components.percentEncodedPath.removingPercentEncoding,
            path.hasPrefix("/"), !path.hasPrefix("//"), !path.utf16.contains(0)
        else {
            throw DemoFilePreviewServiceError.invalidFileURL
        }
        if let host = components.percentEncodedHost, !host.isEmpty, host.lowercased() != "localhost" {
            throw DemoFilePreviewServiceError.invalidFileURL
        }

        #if os(Windows)
            // Foundation recognizes a drive before decoding escaped characters.
            // An encoded drive or a dot before it would change native meaning.
            let prefix = Array(components.percentEncodedPath.utf8.prefix(4))
            guard prefix.count == 4, prefix[0] == 47, prefix[2] == 58, prefix[3] == 47,
                (65...90).contains(prefix[1]) || (97...122).contains(prefix[1])
            else {
                throw DemoFilePreviewServiceError.invalidFileURL
            }
        #endif
        var segments: [String] = []
        // Foundation's native path leaves encoded slashes escaped. Reject
        // them above rather than giving a different file the same identity.
        for segment in path.split(separator: "/", omittingEmptySubsequences: true) {
            guard segment != ".." else { throw DemoFilePreviewServiceError.invalidFileURL }
            if segment != "." { segments.append(String(segment)) }
        }
        #if os(Windows)
            guard !path.contains("\\"),
                let drive = segments.first, drive.utf8.count == 2,
                let letter = drive.utf8.first,
                (65...90).contains(letter) || (97...122).contains(letter),
                drive.last == ":"
            else {
                throw DemoFilePreviewServiceError.invalidFileURL
            }
            for segment in segments.dropFirst() {
                guard isOrdinaryWindowsPathSegment(segment) else {
                    throw DemoFilePreviewServiceError.invalidFileURL
                }
            }
        #endif

        var canonical = URLComponents()
        canonical.scheme = "file"
        canonical.host = ""
        canonical.path = "/" + segments.joined(separator: "/")
        #if os(Windows)
            if segments.count == 1 { canonical.path += "/" }
        #endif
        guard let result = canonical.url else {
            throw DemoFilePreviewServiceError.invalidFileURL
        }
        return result
    }

    /// One worker belongs to each awaited load. Cancellation is cooperative:
    /// metadata, opening, and an individual blocking read cannot be preempted.
    public static var localFiles: Self {
        Self { source in
            try await readOnWorker {
                switch source {
                case .file(let url):
                    return try readRegularFile(at: url)
                case .sample(let bytes):
                    return bytes
                }
            }
        }
    }

    /// The worker owns its handle; cancellation never closes it from another task.
    static func readOnWorker(_ operation: @escaping @Sendable () async throws -> Data) async throws -> Data {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let bytes = try await operation()
            try Task.checkCancellation()
            return bytes
        }
        return try await withTaskCancellationHandler {
            do {
                let bytes = try await worker.value
                try Task.checkCancellation()
                return bytes
            } catch {
                try Task.checkCancellation()
                throw error
            }
        } onCancel: {
            worker.cancel()
        }
    }

    private static func readRegularFile(at originalURL: URL) throws -> Data {
        _ = try validateFileURL(originalURL)
        try Task.checkCancellation()
        #if os(macOS)
            let scopedAccess = originalURL.startAccessingSecurityScopedResource()
            defer {
                if scopedAccess { originalURL.stopAccessingSecurityScopedResource() }
            }
        #endif
        try Task.checkCancellation()
        let attributes = try FileManager.default.attributesOfItem(atPath: originalURL.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw DemoFilePreviewServiceError.notRegularFile
        }
        try Task.checkCancellation()
        // Foundation checks the selected path, then opens it separately. This
        // is not a race-free no-follow open or proof that ancestors, mapped
        // drives, and filesystem providers are local. A path can change here.
        let handle = try FileHandle(forReadingFrom: originalURL)
        return try readBoundedBytes(
            read: { try handle.read(upToCount: $0) },
            close: { try handle.close() })
    }

    /// Shared by real handles and deterministic stream witnesses in the tests.
    static func readBoundedBytes(
        read: (Int) throws -> Data?,
        close: () throws -> Void,
        checkCancellation: () throws -> Void = { try Task.checkCancellation() }
    ) throws -> Data {
        var didClose = false
        defer { if !didClose { try? close() } }
        var bytes = Data()
        var reachedEnd = false
        while bytes.count < maximumPreviewBytes {
            try checkCancellation()
            let requested = min(readChunkBytes, maximumPreviewBytes - bytes.count)
            guard let chunk = try read(requested), !chunk.isEmpty else {
                reachedEnd = true
                break
            }
            // FileHandle honors requested sizes. Keep this boundary enforced
            // even when a test or a future adapter supplies a different reader.
            guard chunk.count <= requested else {
                throw DemoFilePreviewServiceError.previewTooLarge
            }
            bytes.append(chunk)
        }
        if !reachedEnd {
            try checkCancellation()
            if let overflow = try read(1), !overflow.isEmpty {
                throw DemoFilePreviewServiceError.previewTooLarge
            }
        }
        try checkCancellation()
        try close()
        didClose = true
        try checkCancellation()
        return bytes
    }

    #if os(Windows)
        private static func isOrdinaryWindowsPathSegment(_ segment: String) -> Bool {
            guard !segment.hasSuffix("."), !segment.hasSuffix(" "),
                !segment.unicodeScalars.contains(where: { $0.value < 32 }),
                !segment.contains(where: { "<>:\"|?*".contains($0) })
            else { return false }
            let stem =
                segment.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
                .first?.uppercased().trimmingCharacters(in: CharacterSet(charactersIn: " ")) ?? ""
            if ["CON", "PRN", "AUX", "NUL", "CONIN$", "CONOUT$"].contains(stem) { return false }
            for prefix in ["COM", "LPT"] where stem.hasPrefix(prefix) {
                let suffix = stem.dropFirst(prefix.count)
                if suffix.count == 1, "123456789¹²³".contains(String(suffix)) { return false }
            }
            return true
        }
    #endif
}
