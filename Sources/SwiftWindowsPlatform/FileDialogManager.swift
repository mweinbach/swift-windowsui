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
        var ofn = OPENFILENAMEW()
        ofn.lStructSize = DWORD(MemoryLayout<OPENFILENAMEW>.size)
        ofn.hwndOwner = GetActiveWindow()
        ofn.lpstrFile = buffer.withUnsafeMutableBufferPointer { $0.baseAddress }
        ofn.nMaxFile = DWORD(buffer.count)

        if let title = title {
            title.withWideChars { wideTitle in
                ofn.lpstrTitle = wideTitle
            }
        }

        if let defaultDirectory = defaultDirectory {
            defaultDirectory.path.withWideChars { widePath in
                ofn.lpstrInitialDir = widePath
            }
        }

        let filterBuffer = Self.makeFilterBuffer(allowedExtensions: allowedExtensions)
        if !filterBuffer.isEmpty {
            filterBuffer.withUnsafeBufferPointer { buf in
                ofn.lpstrFilter = buf.baseAddress
            }
        }

        if allowsMultipleSelection {
            ofn.Flags = DWORD(OFN_ALLOWMULTISELECT | OFN_FILEMUSTEXIST | OFN_EXPLORER)
        } else {
            ofn.Flags = DWORD(OFN_FILEMUSTEXIST | OFN_EXPLORER)
        }

        let result = GetOpenFileNameW(&ofn)
        guard result else {
            return []
        }

        if allowsMultipleSelection {
            return Self.parseMultiSelect(buffer: buffer)
        } else {
            let path = Self.wideStringToString(buffer)
            if let url = URL(string: path) {
                return [url]
            }
            return []
        }
    }

    public func showSaveFileDialog(
        defaultFilename: String?,
        allowedExtensions: [String]?,
        defaultDirectory: URL?,
        title: String?
    ) -> URL? {
        var buffer = [WCHAR](repeating: 0, count: 4096)

        if let defaultFilename = defaultFilename {
            defaultFilename.withWideChars { wideName in
                for i in 0..<min(buffer.count - 1, defaultFilename.utf16.count) {
                    buffer[i] = wideName[i]
                }
            }
        }

        var ofn = OPENFILENAMEW()
        ofn.lStructSize = DWORD(MemoryLayout<OPENFILENAMEW>.size)
        ofn.hwndOwner = GetActiveWindow()
        ofn.lpstrFile = buffer.withUnsafeMutableBufferPointer { $0.baseAddress }
        ofn.nMaxFile = DWORD(buffer.count)

        if let title = title {
            title.withWideChars { wideTitle in
                ofn.lpstrTitle = wideTitle
            }
        }

        if let defaultDirectory = defaultDirectory {
            defaultDirectory.path.withWideChars { widePath in
                ofn.lpstrInitialDir = widePath
            }
        }

        let filterBuffer = Self.makeFilterBuffer(allowedExtensions: allowedExtensions)
        if !filterBuffer.isEmpty {
            filterBuffer.withUnsafeBufferPointer { buf in
                ofn.lpstrFilter = buf.baseAddress
            }
        }

        ofn.Flags = DWORD(OFN_OVERWRITEPROMPT | OFN_EXPLORER)

        let result = GetSaveFileNameW(&ofn)
        guard result else {
            return nil
        }

        let path = Self.wideStringToString(buffer)
        return URL(string: path)
    }

    /// Double-null-terminated `lpstrFilter` payload ("Supported Files",
    /// "*.ext;*.ext2"). Empty when there is nothing to filter on.
    private static func makeFilterBuffer(allowedExtensions: [String]?) -> [WCHAR] {
        guard let allowedExtensions = allowedExtensions, !allowedExtensions.isEmpty else {
            return []
        }
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
        let extPattern = allowedExtensions.map { "*." + $0 }.joined(separator: ";")
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

    private static func parseMultiSelect(buffer: [WCHAR]) -> [URL] {
        let fullString = wideStringToString(buffer)
        let parts = fullString.split(separator: "\0", omittingEmptySubsequences: true)
        guard parts.count > 1 else {
            if let url = URL(string: fullString) {
                return [url]
            }
            return []
        }

        let directory = String(parts[0])
        var urls: [URL] = []
        for i in 1..<parts.count {
            let filename = String(parts[i])
            let path = directory + "\\" + filename
            if let url = URL(string: path) {
                urls.append(url)
            }
        }
        return urls
    }

    private static func wideStringToString(_ buffer: [WCHAR]) -> String {
        let length = buffer.firstIndex(of: 0) ?? buffer.count
        let data = Data(bytes: buffer, count: length * MemoryLayout<WCHAR>.size)
        return String(data: data, encoding: .utf16LittleEndian) ?? ""
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
        guard !fileURLs.isEmpty else { return }
        var buffer: [WCHAR] = []
        for url in fileURLs {
            let path = url.path
            path.withWideChars { widePath in
                var i = 0
                while widePath[i] != 0 {
                    buffer.append(widePath[i])
                    i += 1
                }
                buffer.append(0)
            }
        }
        buffer.append(0)

        buffer.withUnsafeBufferPointer { buf in
            guard let baseAddress = buf.baseAddress else { return }
            var fileOp = SHFILEOPSTRUCTW()
            fileOp.wFunc = UINT(FO_DELETE)
            fileOp.pFrom = baseAddress
            fileOp.fFlags = FILEOP_FLAGS(UInt16(FOF_ALLOWUNDO | FOF_NOCONFIRMATION))
            _ = SHFileOperationW(&fileOp)
        }
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
