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

        func containsFiles() -> Bool {
            !paths.isEmpty
        }

        func copyFiles(_ paths: [String]) {
            copyCallCount += 1
            self.paths = paths
        }

        func pastedFiles() -> [String] {
            paths
        }
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
