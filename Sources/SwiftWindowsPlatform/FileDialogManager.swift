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

/// Live Win32 common-dialog provider.
public final class Win32FileDialogProvider: FileDialogProvider {
    public init() {}

    public func showOpenFileDialog(
        allowedExtensions: [String]?,
        allowsMultipleSelection: Bool,
        defaultDirectory: URL?,
        title: String?
    ) -> [URL] {
        var buffer = [WCHAR](repeating: 0, count: 4096)
        let flags: DWORD =
            allowsMultipleSelection
            ? DWORD(OFN_ALLOWMULTISELECT | OFN_FILEMUSTEXIST | OFN_EXPLORER)
            : DWORD(OFN_FILEMUSTEXIST | OFN_EXPLORER)

        let result = Self.withConfiguredDialog(
            fileBuffer: &buffer,
            allowedExtensions: allowedExtensions,
            defaultDirectory: defaultDirectory,
            title: title,
            flags: flags
        ) { configuration in
            GetOpenFileNameW(&configuration)
        }
        guard result else {
            return []
        }

        return Self.selectedFileURLs(from: buffer, allowsMultipleSelection: allowsMultipleSelection)
    }

    public func showSaveFileDialog(
        defaultFilename: String?,
        allowedExtensions: [String]?,
        defaultDirectory: URL?,
        title: String?
    ) -> URL? {
        var buffer = [WCHAR](repeating: 0, count: 4096)

        if let defaultFilename = defaultFilename {
            for (index, codeUnit) in defaultFilename.utf16.prefix(buffer.count - 1).enumerated() {
                buffer[index] = codeUnit
            }
        }

        let result = Self.withConfiguredDialog(
            fileBuffer: &buffer,
            allowedExtensions: allowedExtensions,
            defaultDirectory: defaultDirectory,
            title: title,
            flags: DWORD(OFN_OVERWRITEPROMPT | OFN_EXPLORER)
        ) { configuration in
            GetSaveFileNameW(&configuration)
        }
        guard result else {
            return nil
        }

        return Self.selectedFileURLs(from: buffer, allowsMultipleSelection: false).first
    }

    /// Keeps every pointer in `OPENFILENAMEW` valid throughout the synchronous
    /// common-dialog call. A pointer returned from `withUnsafeBufferPointer`
    /// cannot be stored and used after that closure has returned.
    static func withConfiguredDialog<Result>(
        fileBuffer: inout [WCHAR],
        allowedExtensions: [String]?,
        defaultDirectory: URL?,
        title: String?,
        flags: DWORD,
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
                        configuration.hwndOwner = GetActiveWindow()
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
    static func selectedFileURLs(from buffer: [WCHAR], allowsMultipleSelection: Bool) -> [URL] {
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
    static func makeFilterBuffer(allowedExtensions: [String]?) -> [WCHAR] {
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
    static func makeRecycleSourceList(_ paths: [String]) -> [WCHAR]? {
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
