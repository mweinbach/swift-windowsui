import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

final class ShareLinkFileClipboardTests: XCTestCase {
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
    private static func withFakeFileStore(_ body: (FakeClipboardFileStore) -> Void) {
        let fake = FakeClipboardFileStore()
        let original = ClipboardManager.fileStore
        ClipboardManager.fileStore = fake
        defer { ClipboardManager.fileStore = original }
        body(fake)
    }

    func testCopyItemsRoutesSingleFileURLToFileStore() async {
        await MainActor.run {
            Self.withFakeFileStore { fake in
                let url = URL(fileURLWithPath: "C:\\data\\report.pdf")
                ClipboardManager.copyItems([url])

                XCTAssertEqual(fake.copyCallCount, 1)
                XCTAssertEqual(fake.paths, [url.path])
                XCTAssertTrue(ClipboardManager.hasFileURLs)
            }
        }
    }

    func testCopyItemsRoutesAllFileURLArraysToFileStore() async {
        await MainActor.run {
            Self.withFakeFileStore { fake in
                let urls = [
                    URL(fileURLWithPath: "C:\\data\\a.txt"),
                    URL(fileURLWithPath: "C:\\data\\b c.txt"),
                ]
                ClipboardManager.copyItems(urls)

                XCTAssertEqual(fake.copyCallCount, 1)
                XCTAssertEqual(fake.paths, urls.map { $0.path })
            }
        }
    }

    func testCopyItemsKeepsAbsoluteStringForNonFileURL() async {
        await MainActor.run {
            Self.withFakeFileStore { fake in
                let url = URL(string: "https://example.com/file.png")!
                // Writes to the real OS clipboard (same precedent as the
                // existing clipboard round-trip tests).
                ClipboardManager.copyItems([url])

                XCTAssertEqual(fake.copyCallCount, 0, "non-file URLs must not touch the HDROP store")
                XCTAssertEqual(ClipboardManager.pasteString(), url.absoluteString)
            }
        }
    }

    func testCopyItemsLeavesMixedArraysUntouched() async {
        await MainActor.run {
            Self.withFakeFileStore { fake in
                ClipboardManager.copyItems([URL(fileURLWithPath: "C:\\a.txt"), "not a url"])
                XCTAssertEqual(fake.copyCallCount, 0)
            }
        }
    }

    func testShareLinkActivationCopiesFileReferenceForFileURLItem() async {
        await MainActor.run {
            Self.withFakeFileStore { fake in
                let url = URL(fileURLWithPath: "C:\\data\\report.pdf")
                let view = ShareLink(item: url)
                let runtime = RetainedViewRuntime(root: ViewNode())
                let host = ComponentHost(runtime: runtime)
                host.setContent(view.makeComponent(context: Self.makeContext()))

                guard let button = Self.firstActivatableNode(runtime.root) else {
                    XCTFail("expected ShareLink to build an activatable button node")
                    return
                }
                button.onActivate?()

                XCTAssertEqual(fake.copyCallCount, 1)
                XCTAssertEqual(fake.paths, [url.path])
            }
        }
    }

    func testShareLinkActivationKeepsStringForNonFileURLItem() async {
        await MainActor.run {
            Self.withFakeFileStore { fake in
                let view = ShareLink(item: "hello share")
                let runtime = RetainedViewRuntime(root: ViewNode())
                let host = ComponentHost(runtime: runtime)
                host.setContent(view.makeComponent(context: Self.makeContext()))

                guard let button = Self.firstActivatableNode(runtime.root) else {
                    XCTFail("expected ShareLink to build an activatable button node")
                    return
                }
                button.onActivate?()

                XCTAssertEqual(fake.copyCallCount, 0)
                XCTAssertEqual(ClipboardManager.pasteString(), "hello share")
            }
        }
    }
}
