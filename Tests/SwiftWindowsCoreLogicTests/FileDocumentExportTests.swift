import Foundation
import SwiftWindowsCore
import SwiftWindowsPlatform
import SwiftWindowsUI
import WinSDK
import WinSwiftUI
import XCTest

final class FileDocumentExportTests: XCTestCase {
    func testRegularFileExportRoundTripsBeforeSuccessCompletion() async throws {
        try await MainActor.run {
            try withExportFixture { fixture in
                let document = ExportDocument(text: "Résumé — 文書\nSecond line\n", probe: fixture.probe)
                let destination = fixture.directory.appendingPathComponent("文書.txt")
                fixture.provider.destination = destination
                fixture.mount(document)
                fixture.onCompletion = { result in
                    XCTAssertFalse(fixture.presented)
                    XCTAssertEqual(try result.get(), destination)
                    XCTAssertEqual(try Data(contentsOf: destination), Data(document.text.utf8))
                }

                fixture.present()

                XCTAssertEqual(fixture.completions.count, 1)
                let saved = try Data(contentsOf: destination)
                let loaded = try ExportDocument(
                    configuration: .init(file: FileWrapper(regularFileWithContents: saved), contentType: .plainText))
                XCTAssertEqual(loaded.text, document.text)
                XCTAssertEqual(fixture.probe.configurations.count, 1)
                XCTAssertEqual(fixture.probe.configurations.first?.contentType, .plainText)
                XCTAssertNil(fixture.probe.configurations.first?.existingFile)
            }
        }
    }

    func testAtomicOverwriteReplacesBytesWithoutTreatingDestinationAsDocumentContent() async throws {
        try await MainActor.run {
            try withExportFixture { fixture in
                try fixture.writeExisting("unrelated old destination")
                fixture.mount(ExportDocument(text: "new document", probe: fixture.probe))

                fixture.present()

                XCTAssertEqual(try fixture.completions.first?.get(), fixture.destination)
                XCTAssertEqual(try Data(contentsOf: fixture.destination), Data("new document".utf8))
                XCTAssertNil(fixture.probe.configurations.first?.existingFile)
                XCTAssertEqual(try fixture.childNames(), ["export.txt"])
            }
        }
    }

    func testEncodingFailurePreservesExistingBytesAndPropagatesError() async throws {
        try await MainActor.run {
            try withExportFixture { fixture in
                try fixture.writeExisting("keep this document")
                fixture.probe.result = .failure(ExportFixtureError.encoding)
                fixture.mount(ExportDocument(text: "must not replace", probe: fixture.probe))

                fixture.present()

                XCTAssertEqual(fixture.failure as? ExportFixtureError, .encoding)
                XCTAssertEqual(fixture.completions.count, 1)
                XCTAssertFalse(fixture.presented)
                XCTAssertEqual(try Data(contentsOf: fixture.destination), Data("keep this document".utf8))
                XCTAssertEqual(try fixture.childNames(), ["export.txt"])
            }
        }
    }

    func testWriteFailurePreservesReadOnlyDestination() async throws {
        try await MainActor.run {
            try withExportFixture { fixture in
                try fixture.writeExisting("read-only original")
                let path = Array(fixture.destination.path.utf16) + [WCHAR(0)]
                let attributes = path.withUnsafeBufferPointer { GetFileAttributesW($0.baseAddress) }
                guard attributes != DWORD(INVALID_FILE_ATTRIBUTES) else {
                    XCTFail("Could not inspect the owned fixture file.")
                    return
                }
                let madeReadOnly = path.withUnsafeBufferPointer {
                    SetFileAttributesW($0.baseAddress, attributes | DWORD(FILE_ATTRIBUTE_READONLY))
                }
                guard madeReadOnly else {
                    XCTFail("Could not make the owned fixture file read-only.")
                    return
                }
                defer {
                    XCTAssertTrue(path.withUnsafeBufferPointer { SetFileAttributesW($0.baseAddress, attributes) })
                }
                fixture.mount(ExportDocument(text: "must not replace", probe: fixture.probe))

                fixture.present()

                XCTAssertNotNil(fixture.failure, "a rejected atomic replacement must not report success")
                XCTAssertEqual(fixture.completions.count, 1)
                XCTAssertEqual(fixture.probe.configurations.count, 1, "serialization precedes the real write failure")
                XCTAssertFalse(fixture.presented)
                XCTAssertEqual(try Data(contentsOf: fixture.destination), Data("read-only original".utf8))
            }
        }
    }

    func testDirectoryDestinationFailurePreservesItsContents() async throws {
        try await MainActor.run {
            try withExportFixture { fixture in
                let destination = fixture.directory.appendingPathComponent("existing-directory", isDirectory: true)
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
                let sentinel = destination.appendingPathComponent("keep.txt")
                try Data("keep".utf8).write(to: sentinel, options: .atomic)
                fixture.provider.destination = destination
                fixture.mount(ExportDocument(text: "must not replace", probe: fixture.probe))

                fixture.present()

                XCTAssertNotNil(fixture.failure)
                XCTAssertEqual(fixture.completions.count, 1)
                XCTAssertEqual(try Data(contentsOf: sentinel), Data("keep".utf8))
                XCTAssertEqual(
                    try FileManager.default.contentsOfDirectory(atPath: destination.path), ["keep.txt"])
            }
        }
    }

    func testCancellationDoesNotSerializeWriteOrCallCompletion() async throws {
        try await MainActor.run {
            try withExportFixture { fixture in
                try fixture.writeExisting("untouched")
                fixture.provider.destination = nil
                fixture.probe.result = .failure(ExportFixtureError.encoding)
                fixture.mount(ExportDocument(text: "must not encode", probe: fixture.probe))

                fixture.present()
                fixture.host.processPendingFileDialogs()

                XCTAssertFalse(fixture.presented)
                XCTAssertTrue(fixture.completions.isEmpty)
                XCTAssertTrue(fixture.probe.configurations.isEmpty)
                XCTAssertEqual(fixture.provider.saveRequests.count, 1)
                XCTAssertEqual(try Data(contentsOf: fixture.destination), Data("untouched".utf8))
                XCTAssertEqual(try fixture.childNames(), ["export.txt"])
            }
        }
    }

    func testLatestReconciledDocumentIsExported() async throws {
        try await MainActor.run {
            try withExportFixture { fixture in
                var document: ExportDocument? = ExportDocument(text: "initial", probe: fixture.probe)
                fixture.mount(document: { document })
                document = ExportDocument(text: "latest before presentation", probe: fixture.probe)
                fixture.host.reload()

                fixture.present()

                XCTAssertEqual(try Data(contentsOf: fixture.destination), Data("latest before presentation".utf8))
                XCTAssertEqual(fixture.completions.count, 1)
                XCTAssertEqual(fixture.probe.configurations.count, 1)
            }
        }
    }

    func testPresentationResetCannotChangeOrRepeatTheSelectedExport() async throws {
        try await MainActor.run {
            try withExportFixture { fixture in
                var document: ExportDocument? = ExportDocument(text: "selected snapshot", probe: fixture.probe)
                fixture.mount(document: { document })
                fixture.provider.onSave = {
                    fixture.host.processPendingFileDialogs()
                }
                fixture.onDismiss = {
                    document = ExportDocument(text: "next document", probe: fixture.probe)
                    fixture.host.reload()
                    fixture.host.processPendingFileDialogs()
                }

                fixture.present()

                XCTAssertEqual(try Data(contentsOf: fixture.destination), Data("selected snapshot".utf8))
                XCTAssertEqual(fixture.completions.count, 1)
                XCTAssertEqual(fixture.provider.saveRequests.count, 1)
                XCTAssertEqual(fixture.probe.configurations.count, 1)

                fixture.onDismiss = nil
                fixture.present()
                XCTAssertEqual(try Data(contentsOf: fixture.destination), Data("next document".utf8))
                XCTAssertEqual(fixture.completions.count, 2)
                XCTAssertEqual(fixture.provider.saveRequests.count, 2)
            }
        }
    }

    func testNilDocumentWaitsWithoutOpeningDialogOrCompleting() async throws {
        try await MainActor.run {
            try withExportFixture { fixture in
                var document: ExportDocument?
                fixture.mount(document: { document })

                fixture.present()

                XCTAssertTrue(fixture.presented)
                XCTAssertTrue(fixture.provider.saveRequests.isEmpty)
                XCTAssertTrue(fixture.completions.isEmpty)
                XCTAssertTrue(try fixture.childNames().isEmpty)

                document = ExportDocument(text: "now available", probe: fixture.probe)
                fixture.host.reload()
                fixture.host.processPendingFileDialogs()
                XCTAssertFalse(fixture.presented)
                XCTAssertEqual(try Data(contentsOf: fixture.destination), Data("now available".utf8))
                XCTAssertEqual(fixture.completions.count, 1)
            }
        }
    }

    func testCompletionCanRequestTheNextExportWithoutLosingPresentation() async throws {
        try await MainActor.run {
            try withExportFixture { fixture in
                var document: ExportDocument? = ExportDocument(text: "first", probe: fixture.probe)
                fixture.mount(document: { document })
                fixture.onCompletion = { _ in
                    if fixture.completions.count == 1 {
                        document = ExportDocument(text: "second", probe: fixture.probe)
                        fixture.presented = true
                        fixture.host.reload()
                        fixture.host.processPendingFileDialogs()
                    }
                }

                fixture.present()

                XCTAssertEqual(fixture.completions.count, 2)
                XCTAssertEqual(fixture.provider.saveRequests.count, 2)
                XCTAssertEqual(fixture.probe.configurations.count, 2)
                XCTAssertFalse(fixture.presented)
                XCTAssertEqual(try Data(contentsOf: fixture.destination), Data("second".utf8))
            }
        }
    }

    func testUnsupportedWrappersFailWithoutChangingExistingBytes() async throws {
        try await MainActor.run {
            let mixed = FileWrapper(regularFileWithContents: Data("not a regular-only wrapper".utf8))
            mixed.fileWrappers = [:]
            let wrappers = [
                FileWrapper(),
                FileWrapper(directoryWithFileWrappers: ["child": FileWrapper(regularFileWithContents: Data())]),
                mixed,
            ]
            for wrapper in wrappers {
                try withExportFixture { fixture in
                    try fixture.writeExisting("original")
                    fixture.probe.result = .success(wrapper)
                    fixture.mount(ExportDocument(text: "ignored", probe: fixture.probe))

                    fixture.present()

                    XCTAssertEqual(fixture.failure as? RetainedFileExportError, .unsupportedFileWrapper)
                    XCTAssertEqual(try Data(contentsOf: fixture.destination), Data("original".utf8))
                    XCTAssertEqual(try fixture.childNames(), ["export.txt"])
                }
            }
        }
    }

    func testEmptyRegularFileIsAValidExport() async throws {
        try await MainActor.run {
            try withExportFixture { fixture in
                try fixture.writeExisting("replace with empty bytes")
                fixture.mount(ExportDocument(text: "", probe: fixture.probe))

                fixture.present()

                XCTAssertEqual(try fixture.completions.first?.get(), fixture.destination)
                XCTAssertEqual(try Data(contentsOf: fixture.destination), Data())
            }
        }
    }

    func testUnsupportedAnyDocumentReportsFailureWithoutWriting() async throws {
        try await MainActor.run {
            try withExportFixture { fixture in
                try fixture.writeExisting("original")
                fixture.mountView(
                    Text("export").fileExporter(
                        isPresented: fixture.binding,
                        document: "not a FileDocument" as Any,
                        contentType: .plainText,
                        onCompletion: fixture.receive
                    ))

                fixture.present()

                XCTAssertEqual(fixture.failure as? RetainedFileExportError, .unsupportedDocument)
                XCTAssertEqual(try Data(contentsOf: fixture.destination), Data("original".utf8))
            }
        }
    }

    func testWrapperNamesDoNotRedirectTheAcceptedDestination() async throws {
        try await MainActor.run {
            try withExportFixture { fixture in
                let otherOwnedPath = fixture.directory.appendingPathComponent("not-selected.txt")
                let wrapper = FileWrapper(regularFileWithContents: Data("selected bytes".utf8))
                wrapper.filename = otherOwnedPath.path
                wrapper.preferredFilename = otherOwnedPath.lastPathComponent
                fixture.probe.result = .success(wrapper)
                fixture.mount(ExportDocument(text: "ignored", probe: fixture.probe))

                fixture.present()

                XCTAssertEqual(try fixture.completions.first?.get(), fixture.destination)
                XCTAssertEqual(try Data(contentsOf: fixture.destination), Data("selected bytes".utf8))
                XCTAssertFalse(FileManager.default.fileExists(atPath: otherOwnedPath.path))
                XCTAssertEqual(try fixture.childNames(), ["export.txt"])
            }
        }
    }

    func testMultipleDocumentsReportFailureWithoutWriting() async throws {
        try await MainActor.run {
            try withExportFixture { fixture in
                try fixture.writeExisting("original")
                fixture.mountView(
                    Text("export").fileExporter(
                        isPresented: fixture.binding,
                        documents: [ExportDocument(text: "one"), ExportDocument(text: "two")],
                        contentType: .plainText,
                        onCompletion: fixture.receive
                    ))

                fixture.present()

                XCTAssertEqual(fixture.failure as? RetainedFileExportError, .multipleDocumentsUnsupported)
                XCTAssertEqual(try Data(contentsOf: fixture.destination), Data("original".utf8))
            }
        }
    }

    func testWritableContentTypeSelectionReachesDialogAndSerializer() async throws {
        try await MainActor.run {
            for requestedType in [UTType.png, .json] {
                try withExportFixture { fixture in
                    fixture.mount(ExportDocument(text: "{}", probe: fixture.probe), contentType: requestedType)

                    fixture.present()

                    let expectedType: UTType = requestedType == .json ? .json : .plainText
                    XCTAssertEqual(ExportDocument.writableContentTypes, ExportDocument.readableContentTypes)
                    XCTAssertEqual(fixture.probe.configurations.first?.contentType, expectedType)
                    XCTAssertEqual(
                        fixture.provider.saveRequests.first?.allowedExtensions,
                        expectedType == .json ? ["json"] : ["txt"])
                    XCTAssertEqual(fixture.completions.count, 1)
                    XCTAssertNil(fixture.failure)
                }
            }
        }
    }

    func testWritableContentTypesOverrideIsRespected() async throws {
        try await MainActor.run {
            try withExportFixture { fixture in
                fixture.mount(JSONOnlyExportDocument(), contentType: .data)

                fixture.present()

                XCTAssertEqual(fixture.provider.saveRequests.first?.allowedExtensions, ["json"])
                XCTAssertEqual(try Data(contentsOf: fixture.destination), Data("public.json".utf8))
                XCTAssertEqual(fixture.completions.count, 1)
            }
        }
    }

    func testEmptyWritableTypesFailExplicitlyWithoutSerializationOrWriting() async throws {
        try await MainActor.run {
            try withExportFixture { fixture in
                try fixture.writeExisting("original")
                fixture.mount(NoWritableExportDocument())

                fixture.present()

                XCTAssertEqual(fixture.failure as? RetainedFileExportError, .noWritableContentType)
                XCTAssertEqual(try Data(contentsOf: fixture.destination), Data("original".utf8))
            }
        }
    }

    func testNonFileDestinationIsRejectedBeforeSerialization() async throws {
        try await MainActor.run {
            try withExportFixture { fixture in
                fixture.provider.destination = URL(string: "unsupported-export:destination")
                fixture.mount(ExportDocument(text: "must not encode", probe: fixture.probe))

                fixture.present()

                XCTAssertEqual(fixture.failure as? RetainedFileExportError, .invalidDestination)
                XCTAssertTrue(fixture.probe.configurations.isEmpty)
                XCTAssertTrue(try fixture.childNames().isEmpty)
            }
        }
    }
}

private enum ExportFixtureError: Error, Equatable {
    case encoding
    case invalidDocument
}

private final class ExportEncodingProbe {
    var configurations: [FileDocumentWriteConfiguration] = []
    var result: Result<FileWrapper, Error>?
}

private struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText, .json] }
    var text: String
    var probe: ExportEncodingProbe?

    init(text: String, probe: ExportEncodingProbe? = nil) {
        self.text = text
        self.probe = probe
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, let text = String(data: data, encoding: .utf8) else {
            throw ExportFixtureError.invalidDocument
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        probe?.configurations.append(configuration)
        if let result = probe?.result { return try result.get() }
        return FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

private struct JSONOnlyExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    static var writableContentTypes: [UTType] { [.json] }

    init() {}
    init(configuration: ReadConfiguration) throws {}

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(configuration.contentType.identifier.utf8))
    }
}

private struct NoWritableExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    static var writableContentTypes: [UTType] { [] }

    init() {}
    init(configuration: ReadConfiguration) throws {}

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        throw ExportFixtureError.encoding
    }
}

@MainActor
private final class ExportDialogProvider: FileDialogProvider {
    struct SaveRequest {
        let allowedExtensions: [String]?
    }

    var destination: URL?
    var onSave: (() -> Void)?
    var saveRequests: [SaveRequest] = []

    func showOpenFileDialog(
        allowedExtensions: [String]?,
        allowsMultipleSelection: Bool,
        defaultDirectory: URL?,
        title: String?
    ) -> [URL] {
        XCTFail("Export must not show an open dialog.")
        return []
    }

    func showSaveFileDialog(
        defaultFilename: String?,
        allowedExtensions: [String]?,
        defaultDirectory: URL?,
        title: String?
    ) -> URL? {
        saveRequests.append(SaveRequest(allowedExtensions: allowedExtensions))
        onSave?()
        return destination
    }
}

@MainActor
private final class ExportFixture {
    let directory: URL
    let provider = ExportDialogProvider()
    let probe = ExportEncodingProbe()
    let host: ComponentHost
    let context = ViewBuildContext(canvasSizeProvider: { Size(width: 200, height: 200) }, invalidateHandler: {})
    var presented = false
    var completions: [Result<URL, Error>] = []
    var onDismiss: (() -> Void)?
    var onCompletion: ((Result<URL, Error>) -> Void)?

    var destination: URL { directory.appendingPathComponent("export.txt") }
    var failure: Error? {
        guard case .failure(let error) = completions.first else { return nil }
        return error
    }
    var binding: Binding<Bool> {
        Binding(
            get: { [weak self] in self?.presented ?? false },
            set: { [weak self] value in
                self?.presented = value
                if !value { self?.onDismiss?() }
            })
    }

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "swift-windowsui-file-export-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        host = ComponentHost(runtime: RetainedViewRuntime(root: ViewNode()))
        provider.destination = destination
    }

    func mount<Document: FileDocument>(_ document: Document, contentType: UTType = .plainText)
    where Document.WriteConfiguration == FileDocumentWriteConfiguration {
        mount(document: { document }, contentType: contentType)
    }

    func mount<Document: FileDocument>(
        document: @escaping () -> Document?,
        contentType: UTType = .plainText
    ) where Document.WriteConfiguration == FileDocumentWriteConfiguration {
        host.setComponents { [weak self] in
            guard let self else { return [] }
            let view = Text("export").fileExporter(
                isPresented: self.binding,
                document: document(),
                contentType: contentType,
                defaultFilename: "export.txt",
                onCompletion: self.receive
            )
            return [view.makeComponent(context: self.context)]
        }
    }

    func mountView<Content: View>(_ content: Content) {
        host.setContent(content.makeComponent(context: context))
    }

    func receive(_ result: Result<URL, Error>) {
        completions.append(result)
        onCompletion?(result)
    }

    func present() {
        presented = true
        host.processPendingFileDialogs()
    }

    func writeExisting(_ text: String) throws {
        try Data(text.utf8).write(to: destination, options: .atomic)
    }

    func childNames() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    func removeOwnedDirectory() throws {
        // Never recursively remove anything outside the UUID directory created here.
        guard
            directory.deletingLastPathComponent().standardizedFileURL
                == FileManager.default.temporaryDirectory.standardizedFileURL,
            directory.lastPathComponent.hasPrefix("swift-windowsui-file-export-tests-")
        else {
            throw ExportFixtureError.invalidDocument
        }
        try FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private func withExportFixture(_ body: (ExportFixture) throws -> Void) throws {
    let fixture = try ExportFixture()
    let previousProvider = FileDialogManager.provider
    FileDialogManager.provider = fixture.provider
    defer {
        FileDialogManager.provider = previousProvider
        fixture.provider.onSave = nil
        fixture.onDismiss = nil
        fixture.onCompletion = nil
        fixture.host.setComponents { [] }
        do {
            try fixture.removeOwnedDirectory()
        } catch {
            XCTFail("Could not remove the owned export fixture directory: \(error)")
        }
    }
    try body(fixture)
}
