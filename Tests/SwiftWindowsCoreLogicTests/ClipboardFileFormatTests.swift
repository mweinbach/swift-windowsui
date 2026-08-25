import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

final class ClipboardFileFormatTests: XCTestCase {
    @MainActor
    private final class FakeClipboardTextStore: ClipboardTextStore {
        private(set) var text: String?
        private(set) var copyCallCount = 0
        private(set) var pasteCallCount = 0

        var hasText: Bool {
            text != nil
        }

        func copyString(_ text: String) {
            copyCallCount += 1
            self.text = text
        }

        func pasteString() -> String? {
            pasteCallCount += 1
            return text
        }
    }

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
    private static func withFakeClipboardStores(
        _ body: (FakeClipboardFileStore, FakeClipboardTextStore) -> Void
    ) {
        let fakeFiles = FakeClipboardFileStore()
        let fakeText = FakeClipboardTextStore()
        let originalFiles = ClipboardManager.fileStore
        let originalText = ClipboardManager.textStore
        ClipboardManager.fileStore = fakeFiles
        ClipboardManager.textStore = fakeText
        defer {
            ClipboardManager.textStore = originalText
            ClipboardManager.fileStore = originalFiles
        }
        body(fakeFiles, fakeText)
    }

    @MainActor
    private static func withFakeFileStore(_ body: (FakeClipboardFileStore) -> Void) {
        withFakeClipboardStores { fakeFiles, _ in
            body(fakeFiles)
        }
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

    func testInjectedTextStoreRoundTripsUnicodeWithoutUsingSystemClipboard() async {
        await MainActor.run {
            Self.withFakeClipboardStores { fakeFiles, fakeText in
                let text = "résumé 東京 🚀 café\u{301}\nsecond line"

                XCTAssertFalse(ClipboardManager.hasText)
                XCTAssertNil(ClipboardManager.pasteString())

                ClipboardManager.copyString(text)

                XCTAssertTrue(ClipboardManager.hasText)
                XCTAssertEqual(ClipboardManager.pasteString(), text)
                XCTAssertEqual(fakeText.copyCallCount, 1)
                XCTAssertEqual(fakeText.pasteCallCount, 2)
                XCTAssertEqual(fakeFiles.copyCallCount, 0)
            }
        }
    }

    func testInjectedTextStoreTreatsEmptyTextAsAvailableClipboardFormat() async {
        await MainActor.run {
            Self.withFakeClipboardStores { _, fakeText in
                ClipboardManager.copyString("")

                XCTAssertTrue(ClipboardManager.hasText)
                XCTAssertEqual(ClipboardManager.pasteString(), "")
                XCTAssertTrue(ClipboardManager.pasteItems(for: [.text, .plainText]).isEmpty)
                XCTAssertEqual(fakeText.copyCallCount, 1)
            }
        }
    }

    func testScopedClipboardOverridesRestoreBothPreviousProviders() async {
        await MainActor.run {
            let originalFiles = ClipboardManager.fileStore
            let originalText = ClipboardManager.textStore

            Self.withFakeClipboardStores { outerFiles, outerText in
                XCTAssertTrue(ClipboardManager.fileStore === outerFiles)
                XCTAssertTrue(ClipboardManager.textStore === outerText)

                Self.withFakeClipboardStores { innerFiles, innerText in
                    XCTAssertTrue(ClipboardManager.fileStore === innerFiles)
                    XCTAssertTrue(ClipboardManager.textStore === innerText)
                    XCTAssertFalse(innerFiles === outerFiles)
                    XCTAssertFalse(innerText === outerText)

                    ClipboardManager.copyString("nested fake")
                    XCTAssertEqual(innerText.text, "nested fake")
                    XCTAssertNil(outerText.text)
                }

                XCTAssertTrue(ClipboardManager.fileStore === outerFiles)
                XCTAssertTrue(ClipboardManager.textStore === outerText)
            }

            XCTAssertTrue(ClipboardManager.fileStore === originalFiles)
            XCTAssertTrue(ClipboardManager.textStore === originalText)
        }
    }

    func testCopyFileURLsRoundTripsThroughInjectedStore() async {
        await MainActor.run {
            Self.withFakeFileStore { fake in
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
    }

    func testCopyFileURLsIgnoresNonFileURLsAndLeavesStoreUntouched() async {
        await MainActor.run {
            Self.withFakeFileStore { fake in
                ClipboardManager.copyFileURLs([URL(string: "https://example.com/file.png")!])
                XCTAssertEqual(fake.copyCallCount, 0)
                XCTAssertFalse(ClipboardManager.hasFileURLs)
                XCTAssertEqual(ClipboardManager.pasteFileURLs(), [])
            }
        }
    }

    func testPasteFileURLsEmptyWhenStoreHasNoFiles() async {
        await MainActor.run {
            Self.withFakeFileStore { _ in
                XCTAssertFalse(ClipboardManager.hasFileURLs)
                XCTAssertEqual(ClipboardManager.pasteFileURLs(), [])
            }
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

                XCTAssertTrue(ClipboardManager.pasteItems(for: [.fileURL]).isEmpty)

                let urls = ClipboardManager.pasteItems(for: [.url]).compactMap { $0 as? URL }
                XCTAssertEqual(urls, [URL(string: "https://example.com/report.pdf")!])
            }
        }
    }

    func testURLRequestsRejectRelativeClipboardText() async {
        await MainActor.run {
            Self.withFakeFileStore { _ in
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
            Self.withFakeClipboardStores { _, fakeText in
                ClipboardManager.copyString("one clipboard payload")

                let text = ClipboardManager.pasteItems(for: [.text, .plainText, .utf8PlainText])
                    .compactMap { $0 as? String }

                XCTAssertEqual(text, ["one clipboard payload"])
                XCTAssertEqual(fakeText.pasteCallCount, 1)
            }
        }
    }

    func testUnsupportedContentTypesDoNotReceiveClipboardText() async {
        await MainActor.run {
            Self.withFakeClipboardStores { _, fakeText in
                ClipboardManager.copyString("clipboard text is not an image")

                for unsupportedType in [UTType.image, .png, .pdf, UTType("com.example.custom")] {
                    XCTAssertTrue(
                        ClipboardManager.pasteItems(for: [unsupportedType]).isEmpty,
                        "unexpected clipboard payload for \(unsupportedType.identifier)")
                }
                XCTAssertEqual(fakeText.pasteCallCount, 0)

                XCTAssertEqual(
                    ClipboardManager.pasteItems(for: [.image, .text, .png]).compactMap { $0 as? String },
                    ["clipboard text is not an image"])
                XCTAssertEqual(fakeText.pasteCallCount, 1)
            }
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
            // This explicitly named Win32 integration test is the only test in
            // this suite that writes the real OS clipboard. All ordinary text,
            // URL, and ShareLink workflows use scoped in-memory stores.
            // Verifies the DROPFILES layout and live DragQueryFileW read path.
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
