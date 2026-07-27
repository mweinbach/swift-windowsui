import Foundation
import SwiftWindowsCore
import WinSDK
import XCTest

@testable import SwiftWindowsPlatform

/// Hostile-input tests for the hand-laid double-null-terminated wide string
/// lists built in `FileDialogManager` (common-dialog `lpstrFilter`,
/// `SHFILEOPSTRUCTW.pFrom`). Embedded nulls and empty inputs must fail
/// closed — never split a path into a different file, never silently drop
/// trailing filter entries.
final class FileDialogHardeningTests: XCTestCase {

    /// Decodes a double-null-terminated wide list into its entries.
    private static func entries(of buffer: [WCHAR]) -> [String] {
        var result: [String] = []
        var current: [UTF16.CodeUnit] = []
        for unit in buffer {
            if unit == 0 {
                result.append(String(decoding: current, as: UTF16.self))
                current = []
            } else {
                current.append(unit)
            }
        }
        return result
    }

    // MARK: - lpstrFilter building

    func testFilterBufferIsEmptyForNilAndEmptyExtensionLists() async {
        await MainActor.run {
            XCTAssertTrue(Win32FileDialogProvider.makeFilterBuffer(allowedExtensions: nil).isEmpty)
            XCTAssertTrue(Win32FileDialogProvider.makeFilterBuffer(allowedExtensions: []).isEmpty)
        }
    }

    func testFilterBufferLayoutMatchesDoubleNullContract() async {
        await MainActor.run {
            let buffer = Win32FileDialogProvider.makeFilterBuffer(allowedExtensions: ["png", "jpg"])
            XCTAssertEqual(
                Self.entries(of: buffer),
                ["Supported Files", "*.png;*.jpg", ""],
                "filter must be description, pattern, empty terminator")
            XCTAssertEqual(buffer.suffix(2), [0, 0], "filter must end double-null terminated")
        }
    }

    func testFilterBufferStripsEmbeddedNullsWithoutDroppingLaterExtensions() async {
        await MainActor.run {
            // A null inside one extension must not truncate the joined
            // pattern mid-list (previously every later extension vanished).
            let buffer = Win32FileDialogProvider.makeFilterBuffer(allowedExtensions: ["pn\0g", "jpg"])
            XCTAssertEqual(Self.entries(of: buffer), ["Supported Files", "*.png;*.jpg", ""])
        }
    }

    func testFilterBufferSurvivesEmptyAndWhitespaceExtensions() async {
        await MainActor.run {
            let buffer = Win32FileDialogProvider.makeFilterBuffer(allowedExtensions: ["", " "])
            XCTAssertEqual(Self.entries(of: buffer), ["Supported Files", "*.;*. ", ""])
            XCTAssertEqual(buffer.suffix(2), [0, 0])
        }
    }

    // MARK: - SHFileOperation source list

    func testRecycleSourceListIsNilForNoPaths() async {
        await MainActor.run {
            XCTAssertNil(FileDialogManager.makeRecycleSourceList([]))
        }
    }

    func testRecycleSourceListLayoutMatchesDoubleNullContract() async {
        await MainActor.run {
            let list = FileDialogManager.makeRecycleSourceList(["C:\\a.txt", "D:\\b c.png"])
            XCTAssertNotNil(list)
            XCTAssertEqual(Self.entries(of: list ?? []), ["C:\\a.txt", "D:\\b c.png", ""])
            XCTAssertEqual(list?.suffix(2), [0, 0])
        }
    }

    func testRecycleSourceListSkipsPathsWithEmbeddedNulls() async {
        await MainActor.run {
            // An embedded null would split pFrom so SHFileOperationW acted on
            // a truncated, different path — the path must be skipped instead.
            let list = FileDialogManager.makeRecycleSourceList(["C:\\important\0junk", "C:\\a.txt"])
            XCTAssertEqual(Self.entries(of: list ?? []), ["C:\\a.txt", ""])
        }
    }

    func testRecycleSourceListIsNilWhenEveryPathIsHostile() async {
        await MainActor.run {
            XCTAssertNil(FileDialogManager.makeRecycleSourceList(["\0", "a\0b"]))
        }
    }
}
