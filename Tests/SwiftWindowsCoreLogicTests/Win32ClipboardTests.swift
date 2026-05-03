import XCTest
@testable import SwiftWindowsPlatform

final class Win32ClipboardTests: XCTestCase {
    func testClipboardEncodingNullTerminatesAndNormalizesLineEndings() {
        let units = WindowsClipboardTextEncoding.nullTerminatedUTF16Units(for: "A\nB\rC\r\nD")
        let expected = Array("A\r\nB\r\nC\r\nD".utf16) + [0]

        XCTAssertEqual(units, expected)
    }

    func testClipboardDecodingStopsAtNullAndNormalizesLineEndings() {
        let units = Array("A\r\nB\rC\nD".utf16) + [0] + Array("ignored".utf16)

        XCTAssertEqual(
            WindowsClipboardTextEncoding.string(fromUTF16Units: units),
            "A\nB\nC\nD"
        )
    }

    func testClipboardEncodingPreservesNonASCIIText() {
        let text = "Cafe\u{301} \u{1F44B}\nTokyo"
        let units = WindowsClipboardTextEncoding.nullTerminatedUTF16Units(for: text)

        XCTAssertEqual(
            WindowsClipboardTextEncoding.string(fromUTF16Units: units),
            text
        )
    }
}
