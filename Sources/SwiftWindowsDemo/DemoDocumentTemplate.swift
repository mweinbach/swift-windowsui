import Foundation

#if canImport(SwiftUI)
    import SwiftUI
    import UniformTypeIdentifiers
#else
    import WinSwiftUI
#endif

/// A regular UTF-8 text document. Reading and writing preserve valid source
/// bytes, including a BOM, decomposed characters, and existing line endings.
public struct DemoPlainTextDocument: FileDocument, Sendable {
    public enum ReadError: Error, Equatable, Sendable, LocalizedError {
        case expectedRegularFile
        case invalidUTF8

        public var errorDescription: String? {
            switch self {
            case .expectedRegularFile:
                return "This document must be a regular UTF-8 text file."
            case .invalidUTF8:
                return "The document is not valid UTF-8 text."
            }
        }
    }

    public static var readableContentTypes: [UTType] { [.utf8PlainText] }
    public static var writableContentTypes: [UTType] { [.utf8PlainText] }

    public var text: String

    public init(text: String = "") {
        self.text = text
    }

    public init(configuration: ReadConfiguration) throws {
        guard configuration.file.isRegularFile, let bytes = configuration.file.regularFileContents else {
            throw ReadError.expectedRegularFile
        }
        let decoded = String(decoding: bytes, as: UTF8.self)
        // String(decoding:) repairs malformed input. An exact byte check
        // rejects that repair without normalizing valid text or removing BOMs.
        guard decoded.utf8.elementsEqual(bytes) else {
            throw ReadError.invalidUTF8
        }
        text = decoded
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// The document binding owns text; each mounted editor owns its selection.
@MainActor
public struct DemoDocumentEditor: View {
    @Binding private var document: DemoPlainTextDocument
    @State private var selection: TextSelection?
    public let fileURL: URL?

    public init(document: Binding<DemoPlainTextDocument>, fileURL: URL? = nil) {
        self._document = document
        self.fileURL = fileURL
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Plain text document")
                    .font(.title2)
                    .accessibilityAddTraits(.isHeader)
                Text(fileURL?.lastPathComponent ?? "Untitled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityIdentifier("document.template.filename")
            }
            TextEditor(text: $document.text, selection: $selection)
                .font(.system(size: 14, design: .monospaced))
                .accessibilityLabel("Document text")
                .accessibilityIdentifier("document.template.editor")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16)
        .frame(minWidth: 480, minHeight: 320)
    }
}

/// A shared scene declaration. The executable decides when to expose it.
@MainActor
public struct DemoDocumentScene: Scene {
    public init() {}

    public var body: some Scene {
        DocumentGroup(newDocument: DemoPlainTextDocument()) { configuration in
            DemoDocumentEditor(document: configuration.$document, fileURL: configuration.fileURL)
        }
    }
}
