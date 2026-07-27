import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

final class FileDialogFilterWiringTests: XCTestCase {
    @MainActor
    private final class FakeFileDialogProvider: FileDialogProvider {
        struct OpenRequest {
            var allowedExtensions: [String]?
            var allowsMultipleSelection: Bool
        }

        var openResult: [URL] = []
        private(set) var openRequests: [OpenRequest] = []

        func showOpenFileDialog(
            allowedExtensions: [String]?,
            allowsMultipleSelection: Bool,
            defaultDirectory: URL?,
            title: String?
        ) -> [URL] {
            openRequests.append(
                OpenRequest(
                    allowedExtensions: allowedExtensions,
                    allowsMultipleSelection: allowsMultipleSelection
                ))
            return openResult
        }

        func showSaveFileDialog(
            defaultFilename: String?,
            allowedExtensions: [String]?,
            defaultDirectory: URL?,
            title: String?
        ) -> URL? {
            nil
        }
    }

    @MainActor
    private static func makeContext() -> ViewBuildContext {
        ViewBuildContext(
            canvasSizeProvider: { Size(width: 200, height: 200) },
            invalidateHandler: {}
        )
    }

    @MainActor
    private static func firstActivatableNode(_ node: ViewNode) -> ViewNode? {
        if node.onActivate != nil {
            return node
        }
        for child in node.children {
            if let found = firstActivatableNode(child) {
                return found
            }
        }
        return nil
    }

    @MainActor
    private static func withFakeProvider(
        openResult: [URL] = [],
        _ body: (FakeFileDialogProvider) -> Void
    ) {
        let fake = FakeFileDialogProvider()
        fake.openResult = openResult
        let original = FileDialogManager.provider
        FileDialogManager.provider = fake
        defer { FileDialogManager.provider = original }
        body(fake)
    }

    @MainActor
    private static func activateButton<V: View>(in view: V, file: StaticString = #filePath, line: UInt = #line) {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let host = ComponentHost(runtime: runtime)
        host.setContent(view.makeComponent(context: makeContext()))
        guard let button = firstActivatableNode(runtime.root) else {
            XCTFail("expected an activatable button node", file: file, line: line)
            return
        }
        button.onActivate?()
    }

    func testImportButtonPassesAllowedContentTypeFilter() async {
        await MainActor.run {
            let picked = URL(fileURLWithPath: "C:\\picked.png")
            Self.withFakeProvider(openResult: [picked]) { fake in
                var imported: [Any] = []
                let view = ImportButton(supportedContentTypes: [.png, .jpeg]) { items in
                    imported = items
                }
                Self.activateButton(in: view)

                XCTAssertEqual(fake.openRequests.count, 1)
                XCTAssertEqual(fake.openRequests.first?.allowedExtensions, ["png", "jpg", "jpeg"])
                XCTAssertEqual(fake.openRequests.first?.allowsMultipleSelection, true)
                XCTAssertEqual(imported.count, 1)
                XCTAssertEqual((imported.first as? URL)?.path, picked.path)
            }
        }
    }

    func testImportButtonWithUnmappableTypesRequestsNoFilter() async {
        await MainActor.run {
            Self.withFakeProvider { fake in
                let view = ImportButton(supportedContentTypes: [.data]) { _ in }
                Self.activateButton(in: view)

                XCTAssertEqual(fake.openRequests.count, 1)
                XCTAssertNil(fake.openRequests.first?.allowedExtensions)
            }
        }
    }

    func testPhotosPickerSingleSelectionPassesImageFilter() async {
        await MainActor.run {
            let picked = URL(fileURLWithPath: "C:\\photos\\one.png")
            Self.withFakeProvider(openResult: [picked]) { fake in
                var selection: PhotosPickerItem?
                let binding = Binding(get: { selection }, set: { selection = $0 })
                Self.activateButton(in: PhotosPicker(selection: binding))

                XCTAssertEqual(fake.openRequests.count, 1)
                XCTAssertEqual(fake.openRequests.first?.allowedExtensions, ["png", "jpg", "jpeg", "bmp", "gif"])
                XCTAssertEqual(fake.openRequests.first?.allowsMultipleSelection, false)
                XCTAssertEqual(selection?.fileURL?.path, picked.path)
            }
        }
    }

    func testPhotosPickerMultipleSelectionPassesImageFilterAndMultiSelect() async {
        await MainActor.run {
            let picked = [
                URL(fileURLWithPath: "C:\\photos\\one.png"),
                URL(fileURLWithPath: "C:\\photos\\two.jpg"),
            ]
            Self.withFakeProvider(openResult: picked) { fake in
                var selections: [PhotosPickerItem] = []
                let binding = Binding(get: { selections }, set: { selections = $0 })
                Self.activateButton(in: PhotosPicker(selections: binding))

                XCTAssertEqual(fake.openRequests.count, 1)
                XCTAssertEqual(fake.openRequests.first?.allowedExtensions, ["png", "jpg", "jpeg", "bmp", "gif"])
                XCTAssertEqual(fake.openRequests.first?.allowsMultipleSelection, true)
                XCTAssertEqual(selections.compactMap { $0.fileURL?.path }, picked.map { $0.path })
            }
        }
    }

    func testImagePickerPassesImageFilter() async {
        await MainActor.run {
            let picked = URL(fileURLWithPath: "C:\\photos\\chosen.png")
            Self.withFakeProvider(openResult: [picked]) { fake in
                var selection: URL?
                let binding = Binding(get: { selection }, set: { selection = $0 })
                Self.activateButton(in: ImagePicker(selection: binding))

                XCTAssertEqual(fake.openRequests.count, 1)
                XCTAssertEqual(fake.openRequests.first?.allowedExtensions, ["png", "jpg", "jpeg", "bmp", "gif"])
                XCTAssertEqual(fake.openRequests.first?.allowsMultipleSelection, false)
                XCTAssertEqual(selection?.path, picked.path)
            }
        }
    }
}
