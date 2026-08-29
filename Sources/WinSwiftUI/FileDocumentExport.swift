import Foundation
import SwiftWindowsCore
import SwiftWindowsUI

extension View {
    @MainActor
    public func fileExporter<Document: FileDocument>(
        isPresented: Binding<Bool>,
        document: Document?,
        contentType: UTType,
        defaultFilename: String? = nil,
        onCompletion: @escaping (Result<URL, Error>) -> Void
    ) -> some View where Document.WriteConfiguration == FileDocumentWriteConfiguration {
        let writableTypes = Document.writableContentTypes
        let effectiveContentType: UTType? = writableTypes.contains(contentType) ? contentType : writableTypes.first
        return ModifiedView(content: self) { content, context in
            let base = content.makeComponent(context: context)
            return Component { runtime in
                let node = base.makeNode(runtime: runtime)
                if let document {
                    node.fileExporterConfiguration = RetainedFileExporterConfiguration(
                        isPresented: isPresented,
                        document: document,
                        dataProvider: { _ in
                            guard let effectiveContentType else {
                                throw RetainedFileExportError.noWritableContentType
                            }
                            return try fileDocumentExportData(document, contentType: effectiveContentType)
                        },
                        contentType: effectiveContentType ?? contentType,
                        defaultFilename: defaultFilename,
                        onCompletion: onCompletion
                    )
                    .withInvocationScope(FileDialogInvocationContext(context))
                } else {
                    node.fileExporterConfiguration = nil
                }
                return node
            }
        }
    }
}

@MainActor
func fileDocumentExportData<Document: FileDocument>(
    _ document: Document,
    contentType: UTType
) throws -> Data where Document.WriteConfiguration == FileDocumentWriteConfiguration {
    // Encoding does not read the destination or manufacture an existingFile.
    // An unrelated file chosen by Save As is not this document's saved wrapper.
    let configuration = FileDocumentWriteConfiguration(contentType: contentType)
    let wrapper = try document.fileWrapper(configuration: configuration)
    guard wrapper.fileWrappers == nil, let data = wrapper.regularFileContents else {
        throw RetainedFileExportError.unsupportedFileWrapper
    }
    return data
}
