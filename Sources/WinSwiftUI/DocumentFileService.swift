import Foundation
import SwiftWindowsCore
import SwiftWindowsPlatform
import SwiftWindowsUI

/// Synchronous operations belonging to one document session's current ticket.
/// Dialogs choose URLs only; successful writes always use the real filesystem.
@MainActor
protocol DocumentFileService: AnyObject {
    func chooseOpenURL(types: [UTType], owner: FileDialogOwner) -> FileDialogOutcome<URL>
    func chooseSaveURL(
        name: String?, directory: URL?, type: UTType, owner: FileDialogOwner
    ) -> FileDialogOutcome<URL>
    func readRegularFile(at url: URL, maximumBytes: Int) throws -> Data
    func writeRegularFile(
        to url: URL,
        provideData: @MainActor (URL) throws -> Data,
        validate: @MainActor () throws -> Void
    ) throws -> Data
}

enum DocumentFileServiceError: Error, LocalizedError, Sendable, Equatable {
    case invalidFileURL
    case notRegularFile
    case invalidReadLimit
    case readLimitExceeded(maximumBytes: Int)

    var errorDescription: String? {
        switch self {
        case .invalidFileURL:
            return "A document requires a valid file URL."
        case .notRegularFile:
            return "Only regular-file documents are supported."
        case .invalidReadLimit:
            return "The document read limit must not be negative."
        case .readLimitExceeded(let maximumBytes):
            return "This document exceeds the current \(maximumBytes)-byte read limit."
        }
    }
}

@MainActor
final class LiveDocumentFileService: DocumentFileService {
    /// An explicit resource boundary for this synchronous session stage.
    /// Callers pass the limit to reads; tests can supply a smaller bound.
    static let defaultMaximumReadBytes = 16 * 1024 * 1024
    private static let readChunkBytes = 64 * 1024

    func chooseOpenURL(types: [UTType], owner: FileDialogOwner) -> FileDialogOutcome<URL> {
        switch FileDialogManager.openFileDialogOutcome(
            allowedExtensions: FileDialogManager.fileExtensions(forContentTypes: types),
            allowsMultipleSelection: false,
            owner: owner
        ) {
        case .selected(let urls):
            guard urls.count == 1, let url = urls.first else {
                return .failed(FileDialogError.invalidSelection)
            }
            guard Self.isValidFileURL(url) else { return .failed(DocumentFileServiceError.invalidFileURL) }
            return .selected(url)
        case .cancelled:
            return .cancelled
        case .failed(let error):
            return .failed(error)
        }
    }

    func chooseSaveURL(
        name: String?, directory: URL?, type: UTType, owner: FileDialogOwner
    ) -> FileDialogOutcome<URL> {
        if let directory, !Self.isValidFileURL(directory) {
            return .failed(DocumentFileServiceError.invalidFileURL)
        }
        switch FileDialogManager.saveFileDialogOutcome(
            defaultFilename: name,
            allowedExtensions: FileDialogManager.fileExtensions(forContentTypes: [type]),
            defaultDirectory: directory,
            owner: owner
        ) {
        case .selected(let url):
            guard Self.isValidFileURL(url) else { return .failed(DocumentFileServiceError.invalidFileURL) }
            return .selected(url)
        case .cancelled:
            return .cancelled
        case .failed(let error):
            return .failed(error)
        }
    }

    func readRegularFile(at url: URL, maximumBytes: Int) throws -> Data {
        guard maximumBytes >= 0 else { throw DocumentFileServiceError.invalidReadLimit }
        try Self.requireRegularFile(at: url, allowingMissing: false)
        let handle = try FileHandle(forReadingFrom: url)
        // The handle is closed before a caller can enter its document decoder.
        var didClose = false
        defer { if !didClose { try? handle.close() } }

        var result = Data()
        var reachedEnd = false
        while result.count < maximumBytes {
            let request = min(Self.readChunkBytes, maximumBytes - result.count)
            guard let chunk = try handle.read(upToCount: request), !chunk.isEmpty else {
                reachedEnd = true
                break
            }
            result.append(chunk)
        }
        // Do not allocate from the file's reported size or read the remainder
        // and check afterward. One byte distinguishes an exact fit from an
        // overflow, including a zero-byte limit and Int.max without addition.
        if !reachedEnd, let overflow = try handle.read(upToCount: 1), !overflow.isEmpty {
            throw DocumentFileServiceError.readLimitExceeded(maximumBytes: maximumBytes)
        }
        try handle.close()
        didClose = true
        return result
    }

    func writeRegularFile(
        to url: URL,
        provideData: @MainActor (URL) throws -> Data,
        validate: @MainActor () throws -> Void
    ) throws -> Data {
        try validate()
        try Self.requireRegularFile(at: url, allowingMissing: true)
        let data = try provideData(url)
        try validate()
        return try RetainedAtomicFileWriter.write(data, to: url) {
            try validate()
            // Validation can itself enter application code. Check the path
            // after that callback, with no further application callback before
            // the write. This is not filesystem identity/coordination support:
            // another process can still replace a path between OS operations.
            try Self.requireRegularFile(at: url, allowingMissing: true)
        }
    }

    private static func isValidFileURL(_ url: URL) -> Bool {
        guard url.isFileURL, !url.path(percentEncoded: false).utf16.contains(0) else { return false }
        // Foundation's filesystem path does not retain a URL authority. Native
        // Windows UNC paths instead keep //server/share in the URL path with
        // an empty host, so they remain available to the existing picker.
        if let host = url.host(percentEncoded: true), !host.isEmpty, host.lowercased() != "localhost" {
            return false
        }
        return true
    }

    private static func requireRegularFile(at url: URL, allowingMissing: Bool) throws {
        guard isValidFileURL(url) else { throw DocumentFileServiceError.invalidFileURL }
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            let cocoaError = error as NSError
            if allowingMissing, cocoaError.domain == NSCocoaErrorDomain,
                cocoaError.code == CocoaError.Code.fileNoSuchFile.rawValue
                    || cocoaError.code == CocoaError.Code.fileReadNoSuchFile.rawValue
            {
                return
            }
            throw error
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw DocumentFileServiceError.notRegularFile
        }
    }
}

enum DocumentCodecError: Error, LocalizedError, Sendable, Equatable {
    case unsupportedReadableContentType(UTType)
    case unsupportedWritableContentType(UTType)

    var errorDescription: String? {
        switch self {
        case .unsupportedReadableContentType(let type):
            return "This document cannot read the declared content type \(type.identifier)."
        case .unsupportedWritableContentType(let type):
            return "This document cannot write the declared content type \(type.identifier)."
        }
    }
}

/// The fixed configuration constraints belong to the relevant factory, not
/// the generic type or the standalone exporter. A viewing document need not
/// provide this stack's write configuration, and export needs no read support.
@MainActor
struct DocumentCodec<Document: FileDocument> {
    let decode: @MainActor (Data, UTType) throws -> Document
    let encode: (@MainActor (Document, UTType) throws -> Data)?
}

extension DocumentCodec where Document.ReadConfiguration == FileDocumentReadConfiguration {
    static func viewing(_ type: Document.Type) -> Self {
        Self(
            decode: { data, contentType in
                guard type.readableContentTypes.contains(contentType) else {
                    throw DocumentCodecError.unsupportedReadableContentType(contentType)
                }
                return try type.init(
                    configuration: FileDocumentReadConfiguration(
                        file: FileWrapper(regularFileWithContents: data), contentType: contentType))
            },
            encode: nil)
    }
}

extension DocumentCodec
where
    Document.ReadConfiguration == FileDocumentReadConfiguration,
    Document.WriteConfiguration == FileDocumentWriteConfiguration
{
    static func editable(_ type: Document.Type) -> Self {
        Self(
            decode: Self.viewing(type).decode,
            encode: { document, contentType in
                guard type.writableContentTypes.contains(contentType) else {
                    throw DocumentCodecError.unsupportedWritableContentType(contentType)
                }
                return try fileDocumentExportData(document, contentType: contentType)
            })
    }
}
