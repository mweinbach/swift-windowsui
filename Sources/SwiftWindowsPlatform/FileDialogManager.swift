import Foundation
import SwiftWindowsCore
import WinSDK

/// Abstraction over the Win32 common file dialogs. The production default is
/// `Win32FileDialogProvider`, which shows real modal `GetOpenFileNameW` /
/// `GetSaveFileNameW` dialogs; tests inject fakes so no live dialog appears
/// on headless runners (same pattern as `SystemAppearanceProvider`).
@MainActor
public protocol FileDialogProvider: AnyObject {
    func showOpenFileDialog(
        allowedExtensions: [String]?,
        allowsMultipleSelection: Bool,
        defaultDirectory: URL?,
        title: String?
    ) -> [URL]

    func showSaveFileDialog(
        defaultFilename: String?,
        allowedExtensions: [String]?,
        defaultDirectory: URL?,
        title: String?
    ) -> URL?
}

/// Internal callers distinguish a dismissed panel from a native failure.
/// The public provider keeps its original URL-only compatibility surface.
package enum FileDialogOutcome<Selection> {
    case selected(Selection)
    case cancelled
    case failed(Error)
}

/// Standalone callers retain the active-window behavior. A hosted request
/// must never fall back to another window when its own handle is absent.
package enum FileDialogOwner {
    case standalone
    case hosted(HWND?)

    @MainActor
    package static func hostedWindow(_ window: Win32Window?) -> FileDialogOwner {
        guard let handle = window?.nativeHandle else { return .hosted(nil) }
        return .hosted(HWND(bitPattern: Int(bitPattern: handle.rawValue)))
    }
}

package enum FileDialogError: Error, LocalizedError, Sendable, Equatable {
    case ownerUnavailable
    case nativeFailure(UInt32)
    case invalidSelection

    package var errorDescription: String? {
        switch self {
        case .ownerUnavailable:
            return "The window requesting this file dialog is no longer available."
        case .nativeFailure(let code):
            return "Windows could not complete the file dialog (common-dialog error \(code))."
        case .invalidSelection:
            return "The file dialog returned an invalid selection."
        }
    }
}

/// Package callers can opt in to explicit ownership and error delivery.
/// Existing custom FileDialogProvider conformers do not need to change.
@MainActor
package protocol FileDialogOutcomeProvider: FileDialogProvider {
    func openFileDialogOutcome(
        allowedExtensions: [String]?,
        allowsMultipleSelection: Bool,
        defaultDirectory: URL?,
        title: String?,
        owner: FileDialogOwner
    ) -> FileDialogOutcome<[URL]>

    func saveFileDialogOutcome(
        defaultFilename: String?,
        allowedExtensions: [String]?,
        defaultDirectory: URL?,
        title: String?,
        owner: FileDialogOwner
    ) -> FileDialogOutcome<URL>
}

/// A concrete native provider may also contain injected native-call fakes.
/// Capability is explicit so those fakes keep their synchronous test behavior.
@MainActor
package protocol NativeOwnerFileDialogProvider: FileDialogProvider {
    var supportsNativeOwnerRequests: Bool { get }
}

/// Live Win32 common-dialog provider.
@MainActor
public final class Win32FileDialogProvider: FileDialogOutcomeProvider, NativeOwnerFileDialogProvider {
    package let supportsNativeOwnerRequests: Bool
    private let openDialog: @MainActor (inout OPENFILENAMEW) -> Bool
    private let saveDialog: @MainActor (inout OPENFILENAMEW) -> Bool
    private let extendedError: @MainActor () -> DWORD
    private let activeWindow: @MainActor () -> HWND?

    public init() {
        supportsNativeOwnerRequests = true
        openDialog = { GetOpenFileNameW(&$0) }
        saveDialog = { GetSaveFileNameW(&$0) }
        extendedError = { CommDlgExtendedError() }
        activeWindow = { GetActiveWindow() }
    }

    /// Tests inject only the native invocation and its immediate dependencies;
    /// all configuration, buffer ownership, and result handling stay real.
    init(
        openDialog: @escaping @MainActor (inout OPENFILENAMEW) -> Bool,
        saveDialog: @escaping @MainActor (inout OPENFILENAMEW) -> Bool,
        extendedError: @escaping @MainActor () -> DWORD,
        activeWindow: @escaping @MainActor () -> HWND?
    ) {
        supportsNativeOwnerRequests = false
        self.openDialog = openDialog
        self.saveDialog = saveDialog
        self.extendedError = extendedError
        self.activeWindow = activeWindow
    }

    public func showOpenFileDialog(
        allowedExtensions: [String]?,
        allowsMultipleSelection: Bool,
        defaultDirectory: URL?,
        title: String?
    ) -> [URL] {
        guard
            case .selected(let urls) = openFileDialogOutcome(
                allowedExtensions: allowedExtensions,
                allowsMultipleSelection: allowsMultipleSelection,
                defaultDirectory: defaultDirectory,
                title: title,
                owner: .standalone
            )
        else { return [] }
        return urls
    }

    public func showSaveFileDialog(
        defaultFilename: String?,
        allowedExtensions: [String]?,
        defaultDirectory: URL?,
        title: String?
    ) -> URL? {
        guard
            case .selected(let url) = saveFileDialogOutcome(
                defaultFilename: defaultFilename,
                allowedExtensions: allowedExtensions,
                defaultDirectory: defaultDirectory,
                title: title,
                owner: .standalone
            )
        else { return nil }
        return url
    }

    package func openFileDialogOutcome(
        allowedExtensions: [String]? = nil,
        allowsMultipleSelection: Bool = false,
        defaultDirectory: URL? = nil,
        title: String? = nil,
        owner: FileDialogOwner = .standalone
    ) -> FileDialogOutcome<[URL]> {
        var buffer = [WCHAR](repeating: 0, count: 4096)
        let flags: DWORD =
            allowsMultipleSelection
            ? DWORD(OFN_ALLOWMULTISELECT | OFN_FILEMUSTEXIST | OFN_EXPLORER)
            : DWORD(OFN_FILEMUSTEXIST | OFN_EXPLORER)

        return performDialog(
            fileBuffer: &buffer,
            allowedExtensions: allowedExtensions,
            allowsMultipleSelection: allowsMultipleSelection,
            defaultDirectory: defaultDirectory,
            title: title,
            flags: flags,
            owner: owner,
            perform: openDialog
        )
    }

    package func saveFileDialogOutcome(
        defaultFilename: String? = nil,
        allowedExtensions: [String]? = nil,
        defaultDirectory: URL? = nil,
        title: String? = nil,
        owner: FileDialogOwner = .standalone
    ) -> FileDialogOutcome<URL> {
        var buffer = [WCHAR](repeating: 0, count: 4096)

        if let defaultFilename = defaultFilename {
            for (index, codeUnit) in defaultFilename.utf16.prefix(buffer.count - 1).enumerated() {
                buffer[index] = codeUnit
            }
        }

        let result = performDialog(
            fileBuffer: &buffer,
            allowedExtensions: allowedExtensions,
            allowsMultipleSelection: false,
            defaultDirectory: defaultDirectory,
            title: title,
            flags: DWORD(OFN_OVERWRITEPROMPT | OFN_EXPLORER),
            owner: owner,
            perform: saveDialog
        )
        switch result {
        case .selected(let urls):
            guard let url = urls.first else { return .failed(FileDialogError.invalidSelection) }
            return .selected(url)
        case .cancelled:
            return .cancelled
        case .failed(let error):
            return .failed(error)
        }
    }

    private func performDialog(
        fileBuffer: inout [WCHAR],
        allowedExtensions: [String]?,
        allowsMultipleSelection: Bool,
        defaultDirectory: URL?,
        title: String?,
        flags: DWORD,
        owner: FileDialogOwner,
        perform: @MainActor (inout OPENFILENAMEW) -> Bool
    ) -> FileDialogOutcome<[URL]> {
        let ownerHandle: HWND?
        switch owner {
        case .standalone:
            ownerHandle = activeWindow()
        case .hosted(let handle):
            guard let handle else { return .failed(FileDialogError.ownerUnavailable) }
            ownerHandle = handle
        }

        let result: FileDialogOutcome<Void> = Self.withConfiguredDialog(
            fileBuffer: &fileBuffer,
            allowedExtensions: allowedExtensions,
            defaultDirectory: defaultDirectory,
            title: title,
            flags: flags,
            ownerHandle: ownerHandle
        ) { configuration in
            Win32DispatchScope.withNativeModal {
                guard perform(&configuration) else {
                    // CommDlgExtendedError is meaningful only after FALSE. Sample
                    // it immediately, before buffer cleanup or any other callback.
                    let code = extendedError()
                    return code == 0 ? .cancelled : .failed(FileDialogError.nativeFailure(code))
                }
                return .selected(())
            }
        }
        switch result {
        case .selected:
            let urls = Self.selectedFileURLs(from: fileBuffer, allowsMultipleSelection: allowsMultipleSelection)
            guard !urls.isEmpty else { return .failed(FileDialogError.invalidSelection) }
            return .selected(urls)
        case .cancelled:
            return .cancelled
        case .failed(let error):
            return .failed(error)
        }
    }

    /// Keeps every pointer in `OPENFILENAMEW` valid throughout the synchronous
    /// common-dialog call. A pointer returned from `withUnsafeBufferPointer`
    /// cannot be stored and used after that closure has returned.
    nonisolated static func withConfiguredDialog<Result>(
        fileBuffer: inout [WCHAR],
        allowedExtensions: [String]?,
        defaultDirectory: URL?,
        title: String?,
        flags: DWORD,
        ownerHandle: HWND? = nil,
        perform: (inout OPENFILENAMEW) -> Result
    ) -> Result {
        let titleBuffer: [WCHAR] = title.map { Array($0.utf16) + [0] } ?? []
        let directoryBuffer: [WCHAR] = defaultDirectory.map { Array($0.path.utf16) + [0] } ?? []
        let filterBuffer = Self.makeFilterBuffer(allowedExtensions: allowedExtensions)

        return fileBuffer.withUnsafeMutableBufferPointer { filePointer in
            titleBuffer.withUnsafeBufferPointer { titlePointer in
                directoryBuffer.withUnsafeBufferPointer { directoryPointer in
                    filterBuffer.withUnsafeBufferPointer { filterPointer in
                        var configuration = OPENFILENAMEW()
                        configuration.lStructSize = DWORD(MemoryLayout<OPENFILENAMEW>.size)
                        configuration.hwndOwner = ownerHandle
                        configuration.lpstrFile = filePointer.baseAddress
                        configuration.nMaxFile = DWORD(filePointer.count)
                        configuration.lpstrTitle = titlePointer.isEmpty ? nil : titlePointer.baseAddress
                        configuration.lpstrInitialDir = directoryPointer.isEmpty ? nil : directoryPointer.baseAddress
                        configuration.lpstrFilter = filterPointer.isEmpty ? nil : filterPointer.baseAddress
                        configuration.Flags = flags
                        return perform(&configuration)
                    }
                }
            }
        }
    }

    /// Decodes the bounded UTF-16 list `OFN_EXPLORER` writes: one selected
    /// file is a complete path; multiple selections are directory, filename,
    /// filename, and an empty terminator. All paths are filesystem URLs.
    nonisolated static func selectedFileURLs(from buffer: [WCHAR], allowsMultipleSelection: Bool) -> [URL] {
        var components: [String] = []
        var index = buffer.startIndex

        while index < buffer.endIndex {
            guard let terminator = buffer[index...].firstIndex(of: 0) else {
                return []
            }

            guard terminator != index else {
                break
            }

            components.append(String(decoding: buffer[index..<terminator], as: UTF16.self))
            if !allowsMultipleSelection {
                break
            }
            index = buffer.index(after: terminator)
        }

        guard let firstPath = components.first else {
            return []
        }

        guard allowsMultipleSelection, components.count > 1 else {
            return [URL(fileURLWithPath: firstPath)]
        }

        let directory = URL(fileURLWithPath: firstPath, isDirectory: true)
        return components.dropFirst().map { directory.appendingPathComponent($0) }
    }

    /// Double-null-terminated `lpstrFilter` payload ("Supported Files",
    /// "*.ext;*.ext2"). Empty when there is nothing to filter on. Null code
    /// units are stripped from extensions: one would silently truncate the
    /// joined pattern mid-list. Internal so hostile-input tests can drive it.
    nonisolated static func makeFilterBuffer(allowedExtensions: [String]?) -> [WCHAR] {
        guard let allowedExtensions = allowedExtensions, !allowedExtensions.isEmpty else {
            return []
        }
        let sanitized = allowedExtensions.map { $0.replacingOccurrences(of: "\0", with: "") }
        var filterBuffer: [WCHAR] = []
        let desc = "Supported Files"
        desc.withWideChars { wideDesc in
            var i = 0
            while wideDesc[i] != 0 {
                filterBuffer.append(wideDesc[i])
                i += 1
            }
            filterBuffer.append(0)
        }
        let extPattern = sanitized.map { "*." + $0 }.joined(separator: ";")
        extPattern.withWideChars { widePattern in
            var i = 0
            while widePattern[i] != 0 {
                filterBuffer.append(widePattern[i])
                i += 1
            }
            filterBuffer.append(0)
        }
        filterBuffer.append(0)
        return filterBuffer
    }

}

@MainActor
public enum FileDialogManager {
    /// Dialog backend. Defaults to the real Win32 common dialogs; tests
    /// inject a fake `FileDialogProvider` and restore this afterwards.
    public static var provider: any FileDialogProvider = Win32FileDialogProvider()

    package static var providerSupportsNativeOwnerRequests: Bool {
        (provider as? any NativeOwnerFileDialogProvider)?.supportsNativeOwnerRequests == true
    }

    /// Hosted built-ins use completion-based selection. Legacy providers still
    /// complete inline; only an explicitly native-capable provider leaves A.
    package static func requestOpenFileDialog(
        allowedExtensions: [String]? = nil,
        allowsMultipleSelection: Bool = false,
        defaultDirectory: URL? = nil,
        title: String? = nil,
        owner: FileDialogOwner = .standalone,
        nativeSession: NativeDialogSession?,
        isCurrent: @escaping @MainActor () -> Bool = { true },
        completion: @escaping @MainActor (DialogRequestOutcome<[URL]>) -> Void
    ) {
        if let nativeSession, providerSupportsNativeOwnerRequests {
            nativeSession.request(
                .openFile(
                    allowedExtensions: allowedExtensions, allowsMultipleSelection: allowsMultipleSelection,
                    defaultDirectory: defaultDirectory, title: title),
                isCurrent: isCurrent
            ) { response in
                switch response {
                case .selectedFiles(let urls):
                    completion(urls.isEmpty ? .failed(FileDialogError.invalidSelection) : .selected(urls))
                case .cancelled: completion(.cancelled)
                case .failed(let error): completion(.failed(error.fileDialogError))
                case .revoked: completion(.revoked)
                default: completion(.failed(NativeDialogFailure.unexpectedResult))
                }
            }
            return
        }
        switch openFileDialogOutcome(
            allowedExtensions: allowedExtensions, allowsMultipleSelection: allowsMultipleSelection,
            defaultDirectory: defaultDirectory, title: title, owner: owner
        ) {
        case .selected(let urls): completion(.selected(urls))
        case .cancelled: completion(.cancelled)
        case .failed(let error): completion(.failed(error))
        }
    }

    package static func requestSaveFileDialog(
        defaultFilename: String? = nil,
        allowedExtensions: [String]? = nil,
        defaultDirectory: URL? = nil,
        title: String? = nil,
        owner: FileDialogOwner = .standalone,
        nativeSession: NativeDialogSession?,
        isCurrent: @escaping @MainActor () -> Bool = { true },
        completion: @escaping @MainActor (DialogRequestOutcome<URL>) -> Void
    ) {
        if let nativeSession, providerSupportsNativeOwnerRequests {
            nativeSession.request(
                .saveFile(
                    defaultFilename: defaultFilename, allowedExtensions: allowedExtensions,
                    defaultDirectory: defaultDirectory, title: title),
                isCurrent: isCurrent
            ) { response in
                switch response {
                case .selectedFiles(let urls):
                    guard urls.count == 1, let url = urls.first else {
                        completion(.failed(FileDialogError.invalidSelection))
                        return
                    }
                    completion(.selected(url))
                case .cancelled: completion(.cancelled)
                case .failed(let error): completion(.failed(error.fileDialogError))
                case .revoked: completion(.revoked)
                default: completion(.failed(NativeDialogFailure.unexpectedResult))
                }
            }
            return
        }
        switch saveFileDialogOutcome(
            defaultFilename: defaultFilename, allowedExtensions: allowedExtensions,
            defaultDirectory: defaultDirectory, title: title, owner: owner
        ) {
        case .selected(let url): completion(.selected(url))
        case .cancelled: completion(.cancelled)
        case .failed(let error): completion(.failed(error))
        }
    }

    package static func requestMoveToRecycleBin(
        fileURLs: [URL], nativeSession: NativeDialogSession?,
        isCurrent: @escaping @MainActor () -> Bool = { true }
    ) {
        guard let nativeSession else {
            moveToRecycleBin(fileURLs: fileURLs)
            return
        }
        // This button has no result callback, but the session retains the real
        // native failure instead of reporting queue admission as completed IO.
        nativeSession.request(.recycleFiles(fileURLs), isCurrent: isCurrent) { _ in }
    }

    /// Synchronous standalone/provider compatibility. Hosted controls use the
    /// request API; this entry point cannot service an N-to-A result transaction.
    public static func showOpenFileDialog(
        allowedExtensions: [String]? = nil,
        allowsMultipleSelection: Bool = false,
        defaultDirectory: URL? = nil,
        title: String? = nil
    ) -> [URL] {
        provider.showOpenFileDialog(
            allowedExtensions: allowedExtensions,
            allowsMultipleSelection: allowsMultipleSelection,
            defaultDirectory: defaultDirectory,
            title: title
        )
    }

    /// Synchronous standalone/provider compatibility; see `showOpenFileDialog`.
    public static func showSaveFileDialog(
        defaultFilename: String? = nil,
        allowedExtensions: [String]? = nil,
        defaultDirectory: URL? = nil,
        title: String? = nil
    ) -> URL? {
        provider.showSaveFileDialog(
            defaultFilename: defaultFilename,
            allowedExtensions: allowedExtensions,
            defaultDirectory: defaultDirectory,
            title: title
        )
    }

    package static func openFileDialogOutcome(
        allowedExtensions: [String]? = nil,
        allowsMultipleSelection: Bool = false,
        defaultDirectory: URL? = nil,
        title: String? = nil,
        owner: FileDialogOwner = .standalone
    ) -> FileDialogOutcome<[URL]> {
        if let provider = provider as? any FileDialogOutcomeProvider {
            return provider.openFileDialogOutcome(
                allowedExtensions: allowedExtensions,
                allowsMultipleSelection: allowsMultipleSelection,
                defaultDirectory: defaultDirectory,
                title: title,
                owner: owner
            )
        }

        // Legacy custom providers have no owner or error channel. Preserve
        // their behavior (including headless test providers) without claiming
        // native ownership or error qualification for this fallback.
        let urls = provider.showOpenFileDialog(
            allowedExtensions: allowedExtensions,
            allowsMultipleSelection: allowsMultipleSelection,
            defaultDirectory: defaultDirectory,
            title: title
        )
        return urls.isEmpty ? .cancelled : .selected(urls)
    }

    package static func saveFileDialogOutcome(
        defaultFilename: String? = nil,
        allowedExtensions: [String]? = nil,
        defaultDirectory: URL? = nil,
        title: String? = nil,
        owner: FileDialogOwner = .standalone
    ) -> FileDialogOutcome<URL> {
        if let provider = provider as? any FileDialogOutcomeProvider {
            return provider.saveFileDialogOutcome(
                defaultFilename: defaultFilename,
                allowedExtensions: allowedExtensions,
                defaultDirectory: defaultDirectory,
                title: title,
                owner: owner
            )
        }

        // As for open, nil from an old provider cannot distinguish a user
        // cancellation from a provider failure; no error is fabricated.
        guard
            let url = provider.showSaveFileDialog(
                defaultFilename: defaultFilename,
                allowedExtensions: allowedExtensions,
                defaultDirectory: defaultDirectory,
                title: title
            )
        else { return .cancelled }
        return .selected(url)
    }

    public static func moveToRecycleBin(fileURLs: [URL]) {
        guard let buffer = makeRecycleSourceList(fileURLs.map { $0.path }) else { return }

        buffer.withUnsafeBufferPointer { buf in
            guard let baseAddress = buf.baseAddress else { return }
            var fileOp = SHFILEOPSTRUCTW()
            fileOp.wFunc = UINT(FO_DELETE)
            fileOp.pFrom = baseAddress
            fileOp.fFlags = FILEOP_FLAGS(UInt16(FOF_ALLOWUNDO | FOF_NOCONFIRMATION))
            _ = SHFileOperationW(&fileOp)
        }
    }

    /// Builds the double-null-terminated wide path list for
    /// `SHFILEOPSTRUCTW.pFrom`. Paths containing embedded null code units are
    /// skipped: one would split the list and make `SHFileOperationW` act on a
    /// truncated, different path — fail closed instead. Returns `nil` when no
    /// usable paths remain. Internal so hostile-input tests can drive it.
    nonisolated static func makeRecycleSourceList(_ paths: [String]) -> [WCHAR]? {
        var buffer: [WCHAR] = []
        for path in paths {
            guard !path.utf16.contains(0) else { continue }
            path.withWideChars { widePath in
                var i = 0
                while widePath[i] != 0 {
                    buffer.append(widePath[i])
                    i += 1
                }
                buffer.append(0)
            }
        }
        guard !buffer.isEmpty else { return nil }
        buffer.append(0)
        return buffer
    }

    /// Maps `UTType`s to Win32 file-dialog filter extensions.
    ///
    /// Win32 common dialogs filter by filename extension only, so the mapping
    /// is inherently approximate: types with no extension identity (`.data`,
    /// `.url`, `.fileURL`) yield no filter, and category types cover only the
    /// common container/raster extensions (`.image` → png/jpg/jpeg/bmp/gif,
    /// `.audio` → mp3/wav/m4a/flac, `.movie`/`.video` → mp4/mov/wmv/avi/mkv),
    /// which is narrower than the UTI's full conformance set. Returns `nil`
    /// when no type maps to an extension, meaning "no filter".
    public static func fileExtensions(forContentTypes types: [UTType]) -> [String]? {
        var result: [String] = []
        var seen = Set<String>()
        for type in types {
            for ext in fileExtensions(forContentType: type) where seen.insert(ext).inserted {
                result.append(ext)
            }
        }
        return result.isEmpty ? nil : result
    }

    private static func fileExtensions(forContentType type: UTType) -> [String] {
        let identifier = type.identifier
        let extensionPrefix = "public.filename-extension."
        if identifier.hasPrefix(extensionPrefix) {
            let ext = String(identifier.dropFirst(extensionPrefix.count))
            return ext.isEmpty ? [] : [ext]
        }
        switch identifier {
        case UTType.plainText.identifier, UTType.text.identifier, UTType.utf8PlainText.identifier,
            "text/plain":
            return ["txt"]
        case UTType.png.identifier, "image/png":
            return ["png"]
        case UTType.jpeg.identifier, "image/jpeg":
            return ["jpg", "jpeg"]
        case UTType.json.identifier, "application/json":
            return ["json"]
        case UTType.pdf.identifier, "application/pdf":
            return ["pdf"]
        case UTType.html.identifier, "text/html":
            return ["html", "htm"]
        case UTType.zip.identifier, "application/zip":
            return ["zip"]
        case UTType.image.identifier:
            return ["png", "jpg", "jpeg", "bmp", "gif"]
        case UTType.audio.identifier:
            return ["mp3", "wav", "m4a", "flac"]
        case UTType.movie.identifier, UTType.video.identifier:
            return ["mp4", "mov", "wmv", "avi", "mkv"]
        default:
            return []
        }
    }
}

extension String {
    fileprivate func withWideChars(_ body: (UnsafePointer<WCHAR>) -> Void) {
        self.withCString(encodedAs: UTF16.self) { body($0) }
    }
}
