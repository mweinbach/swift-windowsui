import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

final class ClipboardFileFormatTests: XCTestCase {
    @MainActor
    private final class FakeClipboardFileStore: ClipboardFileStore {
        private(set) var paths: [String] = []
        private(set) var copyCallCount = 0
        private(set) var pasteCallCount = 0

        func containsFiles() -> Bool {
            !paths.isEmpty
        }

        func copyFiles(_ paths: [String]) {
            copyCallCount += 1
            self.paths = paths
        }

        func pastedFiles() -> [String] {
            pasteCallCount += 1
            return paths
        }
    }

    @MainActor
    private static func withFakeFileStore(_ body: (FakeClipboardFileStore) -> Void) {
        let fake = FakeClipboardFileStore()
        let original = ClipboardManager.fileStore
        ClipboardManager.fileStore = fake
        defer { ClipboardManager.fileStore = original }
        body(fake)
    }

    @MainActor
    private static func firstActivatableNode(_ node: ViewNode) -> ViewNode? {
        if node.onActivate != nil {
            return node
        }

        for child in node.children {
            if let match = firstActivatableNode(child) {
                return match
            }
        }

        return nil
    }

    func testCopyFileURLsRoundTripsThroughInjectedStore() async {
        await MainActor.run {
            let fake = FakeClipboardFileStore()
            let original = ClipboardManager.fileStore
            ClipboardManager.fileStore = fake
            defer { ClipboardManager.fileStore = original }

            let urls = [
                URL(fileURLWithPath: "C:\\data\\report.pdf"),
                URL(fileURLWithPath: "D:\\photos\\image one.png"),
            ]
            ClipboardManager.copyFileURLs(urls)

            XCTAssertTrue(ClipboardManager.hasFileURLs)
            XCTAssertEqual(fake.copyCallCount, 1)
            XCTAssertEqual(fake.paths, urls.map { $0.path })

            let pasted = ClipboardManager.pasteFileURLs()
            XCTAssertEqual(pasted.count, 2)
            XCTAssertEqual(pasted.map { $0.path }, urls.map { $0.path })
            XCTAssertTrue(pasted.allSatisfy { $0.isFileURL })
        }
    }

    func testCopyFileURLsIgnoresNonFileURLsAndLeavesStoreUntouched() async {
        await MainActor.run {
            let fake = FakeClipboardFileStore()
            let original = ClipboardManager.fileStore
            ClipboardManager.fileStore = fake
            defer { ClipboardManager.fileStore = original }

            ClipboardManager.copyFileURLs([URL(string: "https://example.com/file.png")!])
            XCTAssertEqual(fake.copyCallCount, 0)
            XCTAssertFalse(ClipboardManager.hasFileURLs)
            XCTAssertEqual(ClipboardManager.pasteFileURLs(), [])
        }
    }

    func testPasteFileURLsEmptyWhenStoreHasNoFiles() async {
        await MainActor.run {
            let fake = FakeClipboardFileStore()
            let original = ClipboardManager.fileStore
            ClipboardManager.fileStore = fake
            defer { ClipboardManager.fileStore = original }

            XCTAssertFalse(ClipboardManager.hasFileURLs)
            XCTAssertEqual(ClipboardManager.pasteFileURLs(), [])
        }
    }

    func testPasteItemsReturnsEveryHDROPFileForFileURLRequests() async {
        await MainActor.run {
            Self.withFakeFileStore { fake in
                let paths = [
                    "C:\\data\\report.pdf",
                    "D:\\photos\\image one.png",
                    "C:\\data\\résumé-東京-🚀.txt",
                ]
                fake.copyFiles(paths)

                let pasted = ClipboardManager.pasteItems(for: [.fileURL])
                let urls = pasted.compactMap { $0 as? URL }

                XCTAssertEqual(urls.count, paths.count)
                XCTAssertEqual(urls.map(\.path), paths.map { URL(fileURLWithPath: $0).path })
                XCTAssertTrue(urls.allSatisfy(\.isFileURL))
                XCTAssertEqual(fake.pasteCallCount, 1)
            }
        }
    }

    func testPasteItemsAcceptsHDROPFilesForGeneralURLRequests() async {
        await MainActor.run {
            Self.withFakeFileStore { fake in
                let paths = ["C:\\data\\first.txt", "C:\\data\\second.txt"]
                fake.copyFiles(paths)

                let urls = ClipboardManager.pasteItems(for: [.url]).compactMap { $0 as? URL }

                XCTAssertEqual(urls.map(\.path), paths.map { URL(fileURLWithPath: $0).path })
                XCTAssertEqual(fake.pasteCallCount, 1)
            }
        }
    }

    func testOverlappingURLTypesDoNotDuplicateFilesOrRereadTheClipboard() async {
        await MainActor.run {
            Self.withFakeFileStore { fake in
                fake.copyFiles(["C:\\data\\first.txt", "C:\\data\\second.txt"])

                let urls = ClipboardManager.pasteItems(for: [.fileURL, .url, .fileURL])
                    .compactMap { $0 as? URL }

                XCTAssertEqual(urls.count, 2)
                XCTAssertEqual(fake.pasteCallCount, 1)
            }
        }
    }

    func testFileURLRequestsRejectNonFileURLText() async {
        await MainActor.run {
            Self.withFakeFileStore { _ in
                ClipboardManager.copyString("https://example.com/report.pdf")
                defer { ClipboardManager.copyString("") }

                XCTAssertTrue(ClipboardManager.pasteItems(for: [.fileURL]).isEmpty)

                let urls = ClipboardManager.pasteItems(for: [.url]).compactMap { $0 as? URL }
                XCTAssertEqual(urls, [URL(string: "https://example.com/report.pdf")!])
            }
        }
    }

    func testURLRequestsRejectRelativeClipboardText() async {
        await MainActor.run {
            Self.withFakeFileStore { _ in
                defer { ClipboardManager.copyString("") }

                for relativeText in ["report.pdf", "../secrets", "hello"] {
                    ClipboardManager.copyString(relativeText)
                    XCTAssertTrue(
                        ClipboardManager.pasteItems(for: [.url]).isEmpty,
                        "relative text should not become a typed URL: \(relativeText)")
                }

                ClipboardManager.copyString("myapp://documents/report")
                XCTAssertEqual(
                    ClipboardManager.pasteItems(for: [.url]).compactMap { $0 as? URL },
                    [URL(string: "myapp://documents/report")!])
            }
        }
    }

    func testOverlappingTextTypesDeliverOneClipboardPayload() async {
        await MainActor.run {
            ClipboardManager.copyString("one clipboard payload")
            defer { ClipboardManager.copyString("") }

            let text = ClipboardManager.pasteItems(for: [.text, .plainText, .utf8PlainText])
                .compactMap { $0 as? String }

            XCTAssertEqual(text, ["one clipboard payload"])
        }
    }

    func testUnsupportedContentTypesDoNotReceiveClipboardText() async {
        await MainActor.run {
            ClipboardManager.copyString("clipboard text is not an image")
            defer { ClipboardManager.copyString("") }

            for unsupportedType in [UTType.image, .png, .pdf, UTType("com.example.custom")] {
                XCTAssertTrue(
                    ClipboardManager.pasteItems(for: [unsupportedType]).isEmpty,
                    "unexpected clipboard payload for \(unsupportedType.identifier)")
            }

            XCTAssertEqual(
                ClipboardManager.pasteItems(for: [.image, .text, .png]).compactMap { $0 as? String },
                ["clipboard text is not an image"])
        }
    }

    func testPasteButtonActivationDeliversCopiedFileReferences() async {
        await MainActor.run {
            Self.withFakeFileStore { fake in
                let paths = ["C:\\data\\first.txt", "C:\\data\\second.txt"]
                fake.copyFiles(paths)
                var deliveredURLs: [URL] = []
                let button = PasteButton(supportedContentTypes: [.fileURL]) { items in
                    deliveredURLs = items.compactMap { $0 as? URL }
                }
                let context = ViewBuildContext(
                    canvasSizeProvider: { Size(width: 200, height: 120) },
                    invalidateHandler: {}
                )
                let runtime = RetainedViewRuntime(root: ViewNode())
                let host = ComponentHost(runtime: runtime)
                host.setContent(button.makeComponent(context: context))

                guard let activatable = Self.firstActivatableNode(runtime.root) else {
                    XCTFail("expected PasteButton to build an activatable node")
                    return
                }
                activatable.onActivate?()

                XCTAssertEqual(deliveredURLs.map(\.path), paths.map { URL(fileURLWithPath: $0).path })
                XCTAssertEqual(fake.pasteCallCount, 1)
            }
        }
    }

    func testWin32FileStoreRoundTripsHDROPOnRealClipboard() async {
        await MainActor.run {
            // Writes to the real OS clipboard (same precedent as the existing
            // ExportButton clipboard test); verifies the DROPFILES layout and
            // DragQueryFileW read path against the live Win32 clipboard.
            let store = Win32ClipboardFileStore()
            let paths = [
                "C:\\swift-windowsui-hdrop-test\\a.txt",
                "C:\\swift-windowsui-hdrop-test\\b c.txt",
                "C:\\swift-windowsui-hdrop-test\\résumé-東京-🚀.txt",
            ]
            store.copyFiles(paths)

            XCTAssertTrue(store.containsFiles())
            XCTAssertTrue(ClipboardManager.hasFileURLs)
            XCTAssertEqual(store.pastedFiles(), paths)
            XCTAssertEqual(
                ClipboardManager.pasteItems(for: [.fileURL]).compactMap { $0 as? URL }.map(\.path),
                paths.map { URL(fileURLWithPath: $0).path }
            )

            // Restore a neutral clipboard state for subsequent tests.
            ClipboardManager.copyString("")
        }
    }

    func testFormatQueriesDoNotCrashAgainstRealClipboard() async {
        await MainActor.run {
            // Read-only smoke against whatever the real clipboard holds.
            _ = ClipboardManager.hasText
            _ = Win32ClipboardFileStore().pastedFiles()
        }
    }
}
