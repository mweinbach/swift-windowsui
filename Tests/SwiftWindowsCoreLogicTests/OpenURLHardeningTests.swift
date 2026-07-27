import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

final class OpenURLHardeningTests: XCTestCase {
    private final class FakeShellExecutor: OpenURLShellExecutor {
        struct Call: Equatable {
            var operation: String
            var target: String
        }

        var result = true
        private(set) var calls: [Call] = []

        func execute(operation: String, target: String) -> Bool {
            calls.append(Call(operation: operation, target: target))
            return result
        }
    }

    func testHTTPSURLPassesThroughToShellUnchanged() async {
        await MainActor.run {
            let fake = FakeShellExecutor()
            let original = openURLShellExecutor
            openURLShellExecutor = fake
            defer { openURLShellExecutor = original }

            let url = URL(string: "https://example.com/path?q=1&r=2")!
            XCTAssertTrue(defaultOpenURL(url))
            XCTAssertEqual(
                fake.calls,
                [FakeShellExecutor.Call(operation: "open", target: "https://example.com/path?q=1&r=2")])
        }
    }

    func testMailtoURLPassesThroughToShellUnchanged() async {
        await MainActor.run {
            let fake = FakeShellExecutor()
            let original = openURLShellExecutor
            openURLShellExecutor = fake
            defer { openURLShellExecutor = original }

            let url = URL(string: "mailto:user@example.com?subject=Hi")!
            XCTAssertTrue(defaultOpenURL(url))
            XCTAssertEqual(
                fake.calls,
                [FakeShellExecutor.Call(operation: "open", target: "mailto:user@example.com?subject=Hi")])
        }
    }

    func testFileURLResolvesToFilesystemPathForShell() async {
        await MainActor.run {
            let fake = FakeShellExecutor()
            let original = openURLShellExecutor
            openURLShellExecutor = fake
            defer { openURLShellExecutor = original }

            let url = URL(fileURLWithPath: "C:\\temp\\file.txt")
            XCTAssertTrue(defaultOpenURL(url))
            XCTAssertEqual(fake.calls.count, 1)
            let target = fake.calls.first?.target ?? ""
            XCTAssertFalse(target.contains("file:"), "file URLs must not reach the shell as URIs: \(target)")
            XCTAssertTrue(target.hasSuffix("file.txt"), "unexpected target: \(target)")
            XCTAssertFalse(target.hasPrefix("/"), "drive-letter paths must not keep a leading slash: \(target)")
        }
    }

    func testShellFailureIsReportedAsFalse() async {
        await MainActor.run {
            let fake = FakeShellExecutor()
            fake.result = false
            let original = openURLShellExecutor
            openURLShellExecutor = fake
            defer { openURLShellExecutor = original }

            XCTAssertFalse(defaultOpenURL(URL(string: "https://example.com")!))
        }
    }

    func testEmptyAndWhitespaceTargetsFailClosedWithoutTouchingShell() async {
        await MainActor.run {
            let fake = FakeShellExecutor()
            let original = openURLShellExecutor
            openURLShellExecutor = fake
            defer { openURLShellExecutor = original }

            XCTAssertNil(sanitizedShellTarget(""))
            XCTAssertNil(sanitizedShellTarget("   \n  "))
            XCTAssertNil(sanitizedShellTarget("https://example.com/\u{7}"))
            XCTAssertEqual(sanitizedShellTarget("  https://example.com  "), "https://example.com")
            XCTAssertTrue(fake.calls.isEmpty)
        }
    }

    func testControlCharactersInTargetFailClosed() async {
        await MainActor.run {
            let fake = FakeShellExecutor()
            let original = openURLShellExecutor
            openURLShellExecutor = fake
            defer { openURLShellExecutor = original }

            // A file path carrying a raw newline is malformed for the shell.
            let url = URL(fileURLWithPath: "C:\\bad\nname.txt")
            XCTAssertNil(shellTarget(for: url))
            XCTAssertFalse(defaultOpenURL(url))
            XCTAssertTrue(fake.calls.isEmpty)
        }
    }
}
