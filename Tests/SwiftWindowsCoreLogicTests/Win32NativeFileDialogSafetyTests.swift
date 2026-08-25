import Foundation
import WinSDK

@preconcurrency import XCTest

@testable import SwiftWindowsPlatform

@MainActor
final class Win32NativeFileDialogSafetyTests: XCTestCase {
    private func wideList(_ entries: [String], appendingFinalTerminator: Bool = true) -> [WCHAR] {
        var result: [WCHAR] = []
        for entry in entries {
            result.append(contentsOf: entry.utf16)
            result.append(0)
        }
        if appendingFinalTerminator {
            result.append(0)
        }
        return result
    }

    private func wideString(_ pointer: UnsafePointer<WCHAR>?, limit: Int = 512) -> String? {
        guard let pointer else {
            return nil
        }

        var units: [WCHAR] = []
        for index in 0..<limit {
            let unit = pointer[index]
            if unit == 0 {
                return String(decoding: units, as: UTF16.self)
            }
            units.append(unit)
        }
        return nil
    }

    func testSingleSelectedWindowsPathBecomesAFileURL() async {
        let path = #"C:\Project Files\résumé #1.png"#
        let urls = Win32FileDialogProvider.selectedFileURLs(
            from: wideList([path]),
            allowsMultipleSelection: false
        )

        XCTAssertEqual(urls, [URL(fileURLWithPath: path)])
        XCTAssertTrue(urls.first?.isFileURL == true)
    }

    func testMultiSelectionCombinesDirectoryWithEveryUnicodeFilename() async {
        let directory = #"C:\My Photos"#
        let filenames = ["first image.png", "résumé.jpg", "旅行 😀.png"]
        let urls = Win32FileDialogProvider.selectedFileURLs(
            from: wideList([directory] + filenames),
            allowsMultipleSelection: true
        )

        let expectedDirectory = URL(fileURLWithPath: directory, isDirectory: true)
        XCTAssertEqual(urls, filenames.map { expectedDirectory.appendingPathComponent($0) })
        XCTAssertTrue(urls.allSatisfy(\.isFileURL))
    }

    func testMultiSelectionModeStillAcceptsOneCompleteSelectedPath() async {
        let path = #"C:\Users\Example\only file.txt"#
        let urls = Win32FileDialogProvider.selectedFileURLs(
            from: wideList([path]),
            allowsMultipleSelection: true
        )

        XCTAssertEqual(urls, [URL(fileURLWithPath: path)])
    }

    func testEmptyAndUnterminatedSelectionBuffersFailClosed() async {
        XCTAssertEqual(Win32FileDialogProvider.selectedFileURLs(from: [], allowsMultipleSelection: true), [])
        XCTAssertEqual(Win32FileDialogProvider.selectedFileURLs(from: [0, 0], allowsMultipleSelection: true), [])
        XCTAssertEqual(
            Win32FileDialogProvider.selectedFileURLs(
                from: Array(#"C:\unterminated.txt"#.utf16),
                allowsMultipleSelection: false
            ),
            []
        )

        var malformedMulti = wideList([#"C:\directory"#], appendingFinalTerminator: false)
        malformedMulti.append(contentsOf: "unterminated.png".utf16)
        XCTAssertEqual(
            Win32FileDialogProvider.selectedFileURLs(from: malformedMulti, allowsMultipleSelection: true),
            []
        )
    }

    func testDialogConfigurationKeepsAllWidePointersAliveDuringInvocation() async {
        var fileBuffer = [WCHAR](repeating: 0, count: 128)
        let title = "Choose an image — 画像"
        let directory = URL(fileURLWithPath: #"C:\My Photos\旅行"#, isDirectory: true)
        let expectedFilter = Win32FileDialogProvider.makeFilterBuffer(allowedExtensions: ["png", "jpg"])
        let selectedPath = #"C:\My Photos\旅行\chosen 😀.png"#

        let didInvoke = Win32FileDialogProvider.withConfiguredDialog(
            fileBuffer: &fileBuffer,
            allowedExtensions: ["png", "jpg"],
            defaultDirectory: directory,
            title: title,
            flags: DWORD(OFN_EXPLORER)
        ) { configuration in
            XCTAssertEqual(wideString(configuration.lpstrTitle), title)
            XCTAssertEqual(wideString(configuration.lpstrInitialDir), directory.path)
            XCTAssertEqual(configuration.nMaxFile, 128)
            XCTAssertEqual(configuration.Flags, DWORD(OFN_EXPLORER))

            guard let filter = configuration.lpstrFilter,
                let output = configuration.lpstrFile
            else {
                XCTFail("The filter and writable output buffer must remain valid throughout the dialog call.")
                return false
            }

            XCTAssertEqual(Array(UnsafeBufferPointer(start: filter, count: expectedFilter.count)), expectedFilter)

            for (index, unit) in selectedPath.utf16.enumerated() {
                output[index] = unit
            }
            output[selectedPath.utf16.count] = 0
            return true
        }

        XCTAssertTrue(didInvoke)
        XCTAssertEqual(
            Win32FileDialogProvider.selectedFileURLs(from: fileBuffer, allowsMultipleSelection: false),
            [URL(fileURLWithPath: selectedPath)]
        )
    }

    func testDialogConfigurationUsesNilPointersForAbsentOptionalValues() async {
        var fileBuffer = [WCHAR](repeating: 0, count: 8)

        Win32FileDialogProvider.withConfiguredDialog(
            fileBuffer: &fileBuffer,
            allowedExtensions: nil,
            defaultDirectory: nil,
            title: nil,
            flags: 0
        ) { configuration in
            XCTAssertNil(configuration.lpstrTitle)
            XCTAssertNil(configuration.lpstrInitialDir)
            XCTAssertNil(configuration.lpstrFilter)
            XCTAssertNotNil(configuration.lpstrFile)
            XCTAssertEqual(configuration.nMaxFile, 8)
        }
    }
}
