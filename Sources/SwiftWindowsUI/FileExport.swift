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
    func write(to destination: URL) throws {
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
        try data.write(to: destination, options: .atomic)
    }
}
