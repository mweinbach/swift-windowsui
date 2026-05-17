import Foundation
import WinSDK

@MainActor
public enum FileDialogManager {
    public static func showOpenFileDialog(
        allowedExtensions: [String]? = nil,
        allowsMultipleSelection: Bool = false,
        defaultDirectory: URL? = nil,
        title: String? = nil
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

        var filterBuffer: [WCHAR] = []
        if let allowedExtensions = allowedExtensions, !allowedExtensions.isEmpty {
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
            return parseMultiSelect(buffer: buffer)
        } else {
            let path = wideStringToString(buffer)
            if let url = URL(string: path) {
                return [url]
            }
            return []
        }
    }

    public static func showSaveFileDialog(
        defaultFilename: String? = nil,
        defaultDirectory: URL? = nil,
        title: String? = nil
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

        ofn.Flags = DWORD(OFN_OVERWRITEPROMPT | OFN_EXPLORER)

        let result = GetSaveFileNameW(&ofn)
        guard result else {
            return nil
        }

        let path = wideStringToString(buffer)
        return URL(string: path)
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

extension String {
    fileprivate func withWideChars(_ body: (UnsafePointer<WCHAR>) -> Void) {
        self.withCString(encodedAs: UTF16.self) { body($0) }
    }
}
