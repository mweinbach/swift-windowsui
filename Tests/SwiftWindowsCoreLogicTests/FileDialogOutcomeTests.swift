import Foundation
import SwiftWindowsCore
import WinSDK
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform

/// These tests invoke the real configuration/result adapter with synthetic
/// native calls. No window, dialog, or filesystem write is created.
@MainActor
final class FileDialogOutcomeTests: XCTestCase {
    private func makeProvider(
        open: @escaping @MainActor (inout OPENFILENAMEW) -> Bool = { _ in false },
        save: @escaping @MainActor (inout OPENFILENAMEW) -> Bool = { _ in false },
        error: @escaping @MainActor () -> DWORD = { 0 },
        active: @escaping @MainActor () -> HWND? = { nil }
    ) -> Win32FileDialogProvider {
        Win32FileDialogProvider(
            openDialog: open, saveDialog: save, extendedError: error, activeWindow: active)
    }

    private func writeSelection(_ paths: [String], to configuration: inout OPENFILENAMEW) {
        let units = paths.flatMap { Array($0.utf16) + [WCHAR(0)] } + [WCHAR(0)]
        guard let output = configuration.lpstrFile, units.count <= Int(configuration.nMaxFile) else {
            XCTFail("The synthetic selection must fit in the provided native buffer.")
            return
        }
        for (index, unit) in units.enumerated() { output[index] = unit }
    }

    private func assertFailure<Selection>(
        _ outcome: FileDialogOutcome<Selection>, _ expected: FileDialogError,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        guard case .failed(let error) = outcome else {
            XCTFail("Expected a file dialog failure.", file: file, line: line)
            return
        }
        XCTAssertEqual(error as? FileDialogError, expected, file: file, line: line)
    }

    private func assertCancelled<Selection>(
        _ outcome: FileDialogOutcome<Selection>, file: StaticString = #filePath, line: UInt = #line
    ) {
        guard case .cancelled = outcome else {
            XCTFail("Expected a file dialog cancellation.", file: file, line: line)
            return
        }
    }

    func testNativeMissingHostedOwnerRejectsBothRequestsWithoutAnyNativeLookup() async {
        var calls: [String] = []
        let provider = makeProvider(
            open: { _ in
                calls.append("open")
                return false
            },
            save: { _ in
                calls.append("save")
                return false
            },
            error: {
                calls.append("error")
                return 0
            },
            active: {
                calls.append("active")
                return HWND(bitPattern: 1)
            }
        )

        assertFailure(provider.openFileDialogOutcome(owner: .hosted(nil)), .ownerUnavailable)
        assertFailure(provider.saveFileDialogOutcome(owner: .hosted(nil)), .ownerUnavailable)
        XCTAssertTrue(calls.isEmpty)
    }

    func testNativeHostedRequestsUseTheirOwnHandleWithoutActiveWindowFallback() async {
        let first = HWND(bitPattern: 101)
        let second = HWND(bitPattern: 202)
        var owners: [HWND?] = []
        var activeCalls = 0
        let provider = makeProvider(
            open: {
                owners.append($0.hwndOwner)
                return false
            },
            save: {
                owners.append($0.hwndOwner)
                return false
            },
            active: {
                activeCalls += 1
                return HWND(bitPattern: 303)
            }
        )

        assertCancelled(provider.openFileDialogOutcome(owner: .hosted(first)))
        assertCancelled(provider.saveFileDialogOutcome(owner: .hosted(second)))
        XCTAssertEqual(owners, [first, second])
        XCTAssertEqual(activeCalls, 0)
    }

    func testStandaloneRequestsResolveTheActiveWindowSeparatelyAndAllowNoOwner() async {
        let first = HWND(bitPattern: 101)
        var activeCalls = 0
        var owners: [HWND?] = []
        let provider = makeProvider(
            open: {
                owners.append($0.hwndOwner)
                return false
            },
            save: {
                owners.append($0.hwndOwner)
                return false
            },
            active: {
                activeCalls += 1
                return activeCalls == 1 ? first : nil
            }
        )

        assertCancelled(provider.openFileDialogOutcome())
        assertCancelled(provider.saveFileDialogOutcome())
        XCTAssertEqual(activeCalls, 2)
        XCTAssertEqual(owners, [first, nil])
    }

    func testHostedWindowConvenienceDoesNotMakeAnAbsentHandleStandalone() async {
        let window = Win32Window(title: "headless", clientSize: IntSize(width: 100, height: 100))
        for owner in [FileDialogOwner.hostedWindow(nil), .hostedWindow(window)] {
            guard case .hosted(let handle) = owner else {
                XCTFail("A missing hosted handle must retain its hosted requirement.")
                continue
            }
            XCTAssertNil(handle)
        }
    }

    func testNativeFailureReadsTheErrorImmediatelyWhileTheOutputBufferIsAlive() async {
        var events: [String] = []
        var borrowedOutput: UnsafeMutablePointer<WCHAR>?
        let provider = makeProvider(
            open: { configuration in
                events.append("open")
                borrowedOutput = configuration.lpstrFile
                borrowedOutput?.pointee = WCHAR(65)
                defer { events.append("returned") }
                return false
            },
            error: {
                XCTAssertEqual(events, ["open", "returned"])
                XCTAssertEqual(borrowedOutput?.pointee, WCHAR(65))
                events.append("error")
                return DWORD(0x3003)
            }
        )

        assertFailure(provider.openFileDialogOutcome(owner: .hosted(HWND(bitPattern: 1))), .nativeFailure(0x3003))
        borrowedOutput = nil
        XCTAssertEqual(events, ["open", "returned", "error"])
    }

    func testNativeZeroErrorMeansCancellationForOpenAndSave() async {
        var errorCalls = 0
        let provider = makeProvider(error: {
            errorCalls += 1
            return 0
        })

        assertCancelled(provider.openFileDialogOutcome())
        assertCancelled(provider.saveFileDialogOutcome())
        XCTAssertEqual(errorCalls, 2)
    }

    func testNativeSaveFailureIsNotReportedAsCancellation() async {
        var errorCalls = 0
        let provider = makeProvider(error: {
            errorCalls += 1
            return DWORD(0x3002)
        })

        assertFailure(provider.saveFileDialogOutcome(), .nativeFailure(0x3002))
        XCTAssertEqual(errorCalls, 1)
    }

    func testSuccessfulUnicodeMultiSelectionDoesNotReadAnUndefinedExtendedError() async {
        let directory = #"C:\Dialog Fixture\旅行"#
        let names = ["résumé.txt", "文書 😀.txt"]
        var errorCalls = 0
        let provider = makeProvider(
            open: { configuration in
                XCTAssertNotEqual(configuration.Flags & DWORD(OFN_ALLOWMULTISELECT), 0)
                self.writeSelection([directory] + names, to: &configuration)
                return true
            },
            error: {
                errorCalls += 1
                return DWORD(0xFFFF)
            }
        )

        guard case .selected(let urls) = provider.openFileDialogOutcome(allowsMultipleSelection: true) else {
            XCTFail("The accepted UTF-16 list must produce selected file URLs.")
            return
        }
        XCTAssertEqual(
            urls, names.map { URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent($0) })
        XCTAssertEqual(errorCalls, 0)
    }

    func testSuccessfulSavePreservesSuggestedFilenameAndSkipsExtendedError() async {
        let path = #"C:\Dialog Fixture\saved 😀.txt"#
        let suggested = "résumé.txt"
        var errorCalls = 0
        let provider = makeProvider(
            save: { configuration in
                if let file = configuration.lpstrFile {
                    let units = UnsafeBufferPointer(start: file, count: suggested.utf16.count)
                    XCTAssertEqual(String(decoding: units, as: UTF16.self), suggested)
                } else {
                    XCTFail("The native save buffer must contain the suggested filename.")
                }
                XCTAssertNotEqual(configuration.Flags & DWORD(OFN_OVERWRITEPROMPT), 0)
                self.writeSelection([path], to: &configuration)
                return true
            },
            error: {
                errorCalls += 1
                return DWORD(0xFFFF)
            }
        )

        guard case .selected(let url) = provider.saveFileDialogOutcome(defaultFilename: suggested) else {
            XCTFail("A successful native save selection must deliver its file URL.")
            return
        }
        XCTAssertEqual(url, URL(fileURLWithPath: path))
        XCTAssertEqual(errorCalls, 0)
    }

    func testAcceptedEmptyOrUnterminatedBufferFailsWithoutReadingExtendedError() async {
        var errorCalls = 0
        let provider = makeProvider(
            open: { configuration in
                if let output = configuration.lpstrFile {
                    for index in 0..<Int(configuration.nMaxFile) { output[index] = WCHAR(65) }
                }
                return true
            },
            save: { _ in true },
            error: {
                errorCalls += 1
                return DWORD(0xFFFF)
            }
        )

        assertFailure(provider.openFileDialogOutcome(), .invalidSelection)
        assertFailure(provider.saveFileDialogOutcome(), .invalidSelection)
        XCTAssertEqual(errorCalls, 0)
    }

    func testPublicNativeMethodsKeepTheirOriginalFailureAndCancellationProjection() async {
        var code = DWORD(0x3003)
        let provider = makeProvider(error: { code })
        for nextCode in [DWORD(0x3003), DWORD(0)] {
            code = nextCode
            XCTAssertEqual(
                provider.showOpenFileDialog(
                    allowedExtensions: nil, allowsMultipleSelection: false, defaultDirectory: nil, title: nil), [])
            XCTAssertNil(
                provider.showSaveFileDialog(
                    defaultFilename: nil, allowedExtensions: nil, defaultDirectory: nil, title: nil))
        }
    }

    func testManagerPreservesLegacyProvidersAndTheirArgumentsForHeadlessRequests() async {
        let provider = LegacyOutcomeTestProvider()
        let selected = FileManager.default.temporaryDirectory.appendingPathComponent("dialog-\(UUID().uuidString).txt")
        provider.openResult = [selected]
        provider.saveResult = selected
        let previous = FileDialogManager.provider
        FileDialogManager.provider = provider
        defer { FileDialogManager.provider = previous }

        guard
            case .selected(let urls) = FileDialogManager.openFileDialogOutcome(
                allowedExtensions: ["txt"], allowsMultipleSelection: true,
                defaultDirectory: selected.deletingLastPathComponent(), title: "Open fixture", owner: .hosted(nil))
        else {
            XCTFail("A legacy injected provider remains usable without a native HWND.")
            return
        }
        XCTAssertEqual(urls, [selected])
        XCTAssertEqual(provider.openCalls, 1)
        XCTAssertEqual(provider.extensions, ["txt"])
        XCTAssertTrue(provider.multipleSelection)
        XCTAssertEqual(provider.directory, selected.deletingLastPathComponent())
        XCTAssertEqual(provider.title, "Open fixture")

        guard
            case .selected(let url) = FileDialogManager.saveFileDialogOutcome(
                defaultFilename: "fixture.txt", allowedExtensions: ["txt"],
                defaultDirectory: selected.deletingLastPathComponent(), title: "Save fixture", owner: .hosted(nil))
        else {
            XCTFail("The legacy save result must not be replaced by a native invocation.")
            return
        }
        XCTAssertEqual(url, selected)
        XCTAssertEqual(provider.saveCalls, 1)
        XCTAssertEqual(provider.filename, "fixture.txt")
        XCTAssertEqual(provider.title, "Save fixture")

        provider.openResult = []
        provider.saveResult = nil
        assertCancelled(FileDialogManager.openFileDialogOutcome(owner: .hosted(nil)))
        assertCancelled(FileDialogManager.saveFileDialogOutcome(owner: .hosted(nil)))
    }

    func testManagerPassesHeadlessOwnershipAndErrorsToCapableProviders() async {
        let provider = DetailedOutcomeTestProvider()
        let previous = FileDialogManager.provider
        FileDialogManager.provider = provider
        defer { FileDialogManager.provider = previous }

        assertFailure(FileDialogManager.openFileDialogOutcome(owner: .hosted(nil)), .nativeFailure(9))
        assertFailure(FileDialogManager.saveFileDialogOutcome(owner: .hosted(nil)), .nativeFailure(9))
        XCTAssertEqual(provider.owners.count, 2)
        for owner in provider.owners {
            guard case .hosted(let handle) = owner else {
                XCTFail("The caller's explicit ownership request must reach the capable provider.")
                continue
            }
            XCTAssertNil(handle)
        }
        XCTAssertEqual(provider.openCalls, 0)
        XCTAssertEqual(provider.saveCalls, 0)
    }
}

@MainActor
private class LegacyOutcomeTestProvider: FileDialogProvider {
    var openResult: [URL] = []
    var saveResult: URL?
    var openCalls = 0
    var saveCalls = 0
    var extensions: [String]?
    var multipleSelection = false
    var filename: String?
    var directory: URL?
    var title: String?

    func showOpenFileDialog(
        allowedExtensions: [String]?, allowsMultipleSelection: Bool, defaultDirectory: URL?, title: String?
    ) -> [URL] {
        openCalls += 1
        extensions = allowedExtensions
        multipleSelection = allowsMultipleSelection
        directory = defaultDirectory
        self.title = title
        return openResult
    }

    func showSaveFileDialog(
        defaultFilename: String?, allowedExtensions: [String]?, defaultDirectory: URL?, title: String?
    ) -> URL? {
        saveCalls += 1
        filename = defaultFilename
        extensions = allowedExtensions
        directory = defaultDirectory
        self.title = title
        return saveResult
    }
}

@MainActor
private final class DetailedOutcomeTestProvider: LegacyOutcomeTestProvider, FileDialogOutcomeProvider {
    var owners: [FileDialogOwner] = []

    func openFileDialogOutcome(
        allowedExtensions: [String]?, allowsMultipleSelection: Bool,
        defaultDirectory: URL?, title: String?, owner: FileDialogOwner
    ) -> FileDialogOutcome<[URL]> {
        owners.append(owner)
        return .failed(FileDialogError.nativeFailure(9))
    }

    func saveFileDialogOutcome(
        defaultFilename: String?, allowedExtensions: [String]?,
        defaultDirectory: URL?, title: String?, owner: FileDialogOwner
    ) -> FileDialogOutcome<URL> {
        owners.append(owner)
        return .failed(FileDialogError.nativeFailure(9))
    }
}
