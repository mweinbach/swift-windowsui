import Foundation

/// Failures at the retained single-file export boundary. Encoding and filesystem
/// errors otherwise propagate unchanged from the document and Foundation.
public enum RetainedFileExportError: Error, LocalizedError, Sendable, Equatable {
    case unsupportedDocument
    case multipleDocumentsUnsupported
    case noWritableContentType
    case unsupportedFileWrapper
    case invalidDestination

    public var errorDescription: String? {
        switch self {
        case .unsupportedDocument:
            return "This document does not provide a supported single-file export representation."
        case .multipleDocumentsUnsupported:
            return "Exporting multiple documents is not supported yet."
        case .noWritableContentType:
            return "This document does not declare a writable content type."
        case .unsupportedFileWrapper:
            return "Only regular-file document wrappers are supported for export."
        case .invalidDestination:
            return "Document export requires a file URL."
        }
    }
}

extension RetainedFileExporterConfiguration {
    @MainActor
    func write(to destination: URL, validate: @MainActor () throws -> Void = {}) throws {
        try validate()
        guard destination.isFileURL else {
            throw RetainedFileExportError.invalidDestination
        }
        guard documents == nil else {
            throw RetainedFileExportError.multipleDocumentsUnsupported
        }
        guard let dataProvider else {
            throw RetainedFileExportError.unsupportedDocument
        }

        // Finish serialization before Foundation touches the destination. Atomic
        // writing replaces it only after the auxiliary file has been written.
        let data = try dataProvider(destination)
        // Serialization is application code and may close the owning window or
        // remove the presenter while the native modal operation is suspended.
        try validate()
        try data.write(to: destination, options: .atomic)
    }
}
