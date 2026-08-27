import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

final class FileDialogIntegrationTests: XCTestCase {
    @MainActor
    private final class FakeFileDialogProvider: FileDialogProvider {
        struct OpenRequest {
            var allowedExtensions: [String]?
            var allowsMultipleSelection: Bool
            var defaultDirectory: URL?
            var title: String?
        }

        struct SaveRequest {
            var defaultFilename: String?
            var allowedExtensions: [String]?
            var defaultDirectory: URL?
            var title: String?
        }

        var openResult: [URL] = []
        var saveResult: URL?
        private(set) var openRequests: [OpenRequest] = []
        private(set) var saveRequests: [SaveRequest] = []

        func showOpenFileDialog(
            allowedExtensions: [String]?,
            allowsMultipleSelection: Bool,
            defaultDirectory: URL?,
            title: String?
        ) -> [URL] {
            openRequests.append(
                OpenRequest(
                    allowedExtensions: allowedExtensions,
                    allowsMultipleSelection: allowsMultipleSelection,
                    defaultDirectory: defaultDirectory,
                    title: title
                ))
            return openResult
        }

        func showSaveFileDialog(
            defaultFilename: String?,
            allowedExtensions: [String]?,
            defaultDirectory: URL?,
            title: String?
        ) -> URL? {
            saveRequests.append(
                SaveRequest(
                    defaultFilename: defaultFilename,
                    allowedExtensions: allowedExtensions,
                    defaultDirectory: defaultDirectory,
                    title: title
                ))
            return saveResult
        }
    }

    @MainActor
    private static func makeContext() -> ViewBuildContext {
        ViewBuildContext(
            canvasSizeProvider: { Size(width: 200, height: 200) },
            invalidateHandler: {}
        )
    }

    func testFileImporterDeliversPickedURLThroughInjectedProvider() async {
        await MainActor.run {
            let fake = FakeFileDialogProvider()
            let picked = URL(fileURLWithPath: "C:\\picked.png")
            fake.openResult = [picked]
            let original = FileDialogManager.provider
            FileDialogManager.provider = fake
            defer { FileDialogManager.provider = original }

            var presented = false
            var received: Result<URL, Error>?
            let binding = Binding(get: { presented }, set: { presented = $0 })
            let view = Text("host").fileImporter(
                isPresented: binding,
                allowedContentTypes: [.png]
            ) { result in
                received = result
            }

            let runtime = RetainedViewRuntime(root: ViewNode())
            let host = ComponentHost(runtime: runtime)
            host.setContent(view.makeComponent(context: Self.makeContext()))

            presented = true
            host.processPendingFileDialogs()

            guard case .success(let url) = received else {
                XCTFail("expected importer completion to deliver a URL, got \(String(describing: received))")
                return
            }
            XCTAssertEqual(url, picked)
            XCTAssertFalse(presented, "presentation flag should reset after the dialog completes")
            XCTAssertEqual(fake.openRequests.count, 1)
            XCTAssertEqual(fake.openRequests.first?.allowedExtensions, ["png"])
            XCTAssertEqual(fake.openRequests.first?.allowsMultipleSelection, false)
        }
    }

    func testFileImporterCancellationDeliversFailureAndResetsPresentation() async {
        await MainActor.run {
            let fake = FakeFileDialogProvider()
            fake.openResult = []
            let original = FileDialogManager.provider
            FileDialogManager.provider = fake
            defer { FileDialogManager.provider = original }

            var presented = false
            var received: Result<URL, Error>?
            let binding = Binding(get: { presented }, set: { presented = $0 })
            let view = Text("host").fileImporter(
                isPresented: binding,
                allowedContentTypes: [.plainText]
            ) { result in
                received = result
            }

            let runtime = RetainedViewRuntime(root: ViewNode())
            let host = ComponentHost(runtime: runtime)
            host.setContent(view.makeComponent(context: Self.makeContext()))

            presented = true
            host.processPendingFileDialogs()

            guard case .failure = received else {
                XCTFail("expected cancellation to deliver a failure, got \(String(describing: received))")
                return
            }
            XCTAssertFalse(presented)
            XCTAssertEqual(fake.openRequests.count, 1)
        }
    }

    func testFileImporterMultiSelectionDeliversAllPickedURLs() async {
        await MainActor.run {
            let fake = FakeFileDialogProvider()
            let first = URL(fileURLWithPath: "C:\\a.txt")
            let second = URL(fileURLWithPath: "C:\\b.txt")
            fake.openResult = [first, second]
            let original = FileDialogManager.provider
            FileDialogManager.provider = fake
            defer { FileDialogManager.provider = original }

            var presented = false
            var received: Result<[URL], Error>?
            let binding = Binding(get: { presented }, set: { presented = $0 })
            let view = Text("host").fileImporter(
                isPresented: binding,
                allowedContentTypes: [.plainText, .json],
                allowsMultipleSelection: true
            ) { result in
                received = result
            }

            let runtime = RetainedViewRuntime(root: ViewNode())
            let host = ComponentHost(runtime: runtime)
            host.setContent(view.makeComponent(context: Self.makeContext()))

            presented = true
            host.processPendingFileDialogs()

            guard case .success(let urls) = received else {
                XCTFail("expected multi importer to deliver URLs, got \(String(describing: received))")
                return
            }
            XCTAssertEqual(urls, [first, second])
            XCTAssertEqual(fake.openRequests.first?.allowsMultipleSelection, true)
            XCTAssertEqual(fake.openRequests.first?.allowedExtensions, ["txt", "json"])
        }
    }

    func testFileExporterPassesContentTypeFilterAndDeliversURL() async throws {
        try await MainActor.run {
            let temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
                "swift-windowsui-file-export-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
            let fake = FakeFileDialogProvider()
            let destination = temporaryDirectory.appendingPathComponent("out.pdf")
            fake.saveResult = destination
            let original = FileDialogManager.provider
            FileDialogManager.provider = fake
            defer { FileDialogManager.provider = original }

            var presented = false
            var received: Result<URL, Error>?
            let binding = Binding(get: { presented }, set: { presented = $0 })
            let view = Text("host").fileExporter(
                isPresented: binding,
                document: FileDialogExportDocument(contents: Data("payload".utf8)),
                contentType: .pdf,
                defaultFilename: "out.pdf"
            ) { result in
                received = result
            }

            let runtime = RetainedViewRuntime(root: ViewNode())
            let host = ComponentHost(runtime: runtime)
            host.setContent(view.makeComponent(context: Self.makeContext()))

            presented = true
            host.processPendingFileDialogs()

            guard case .success(let url) = received else {
                XCTFail("expected exporter completion to deliver a URL, got \(String(describing: received))")
                return
            }
            XCTAssertEqual(url, destination)
            XCTAssertEqual(try Data(contentsOf: destination), Data("payload".utf8))
            XCTAssertFalse(presented)
            XCTAssertEqual(fake.saveRequests.count, 1)
            XCTAssertEqual(fake.saveRequests.first?.allowedExtensions, ["pdf"])
            XCTAssertEqual(fake.saveRequests.first?.defaultFilename, "out.pdf")
        }
    }

    func testFileExporterCancellationDoesNotCallCompletion() async {
        await MainActor.run {
            let fake = FakeFileDialogProvider()
            fake.saveResult = nil
            let original = FileDialogManager.provider
            FileDialogManager.provider = fake
            defer { FileDialogManager.provider = original }

            var presented = false
            var received: Result<URL, Error>?
            let binding = Binding(get: { presented }, set: { presented = $0 })
            let view = Text("host").fileExporter(
                isPresented: binding,
                document: FileDialogExportDocument(contents: Data("payload".utf8)),
                contentType: .plainText
            ) { result in
                received = result
            }

            let runtime = RetainedViewRuntime(root: ViewNode())
            let host = ComponentHost(runtime: runtime)
            host.setContent(view.makeComponent(context: Self.makeContext()))

            presented = true
            host.processPendingFileDialogs()

            XCTAssertNil(received, "canceling export must not invoke its completion")
            XCTAssertFalse(presented)
        }
    }

    func testContentTypeExtensionMappingCoversKnownTypes() async {
        await MainActor.run {
            XCTAssertEqual(FileDialogManager.fileExtensions(forContentTypes: [.plainText]), ["txt"])
            XCTAssertEqual(FileDialogManager.fileExtensions(forContentTypes: [.png]), ["png"])
            XCTAssertEqual(FileDialogManager.fileExtensions(forContentTypes: [.jpeg]), ["jpg", "jpeg"])
            XCTAssertEqual(FileDialogManager.fileExtensions(forContentTypes: [.pdf]), ["pdf"])
            XCTAssertEqual(FileDialogManager.fileExtensions(forContentTypes: [.json]), ["json"])
            XCTAssertEqual(FileDialogManager.fileExtensions(forContentTypes: [.html]), ["html", "htm"])
            XCTAssertEqual(FileDialogManager.fileExtensions(forContentTypes: [.zip]), ["zip"])
            XCTAssertEqual(
                FileDialogManager.fileExtensions(forContentTypes: [UTType(filenameExtension: "swift")]),
                ["swift"])
            XCTAssertEqual(
                FileDialogManager.fileExtensions(forContentTypes: [UTType(mimeType: "image/png")]),
                ["png"])
        }
    }

    func testContentTypeExtensionMappingDeduplicatesAndSkipsUnmappableTypes() async {
        await MainActor.run {
            XCTAssertEqual(
                FileDialogManager.fileExtensions(forContentTypes: [.png, UTType(filenameExtension: "png"), .jpeg]),
                ["png", "jpg", "jpeg"])
            XCTAssertNil(FileDialogManager.fileExtensions(forContentTypes: [.data]))
            XCTAssertNil(FileDialogManager.fileExtensions(forContentTypes: [.url, .fileURL]))
            XCTAssertNil(FileDialogManager.fileExtensions(forContentTypes: []))
        }
    }
}

private struct FileDialogExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText, .pdf] }
    let contents: Data

    init(contents: Data) {
        self.contents = contents
    }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw RetainedFileExportError.unsupportedFileWrapper
        }
        self.contents = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: contents)
    }
}
