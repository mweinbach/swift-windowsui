import Foundation
import SwiftWindowsCore
import WinSDK

/// Backend for the file-list clipboard payload (`CF_HDROP`). The production
/// default is `Win32ClipboardFileStore`, which talks to the real Win32
/// clipboard; tests inject an in-memory fake so clipboard state never leaves
/// the test process (same pattern as `SystemAppearanceProvider`).
@MainActor
public protocol ClipboardFileStore: AnyObject {
    func containsFiles() -> Bool
    func copyFiles(_ paths: [String])
    func pastedFiles() -> [String]
}

/// Live Win32 `CF_HDROP` file-list store, matching what Explorer produces
/// and consumes for file copy/paste.
public final class Win32ClipboardFileStore: ClipboardFileStore {
    /// `CF_HDROP` is not exposed by the WinSDK Swift module.
    private static let cfHDrop = UINT(15)

    public init() {}

    public func containsFiles() -> Bool {
        IsClipboardFormatAvailable(Self.cfHDrop)
    }

    public func copyFiles(_ paths: [String]) {
        guard !paths.isEmpty else { return }

        // DROPFILES header: DWORD pFiles; POINT pt; BOOL fNC; BOOL fWide.
        // The struct is not exposed by the WinSDK Swift module, so the
        // 20-byte header is laid out manually.
        var payload = Data(count: 20)
        payload.withUnsafeMutableBytes { bytes in
            bytes.storeBytes(of: UInt32(20), toByteOffset: 0, as: UInt32.self)  // pFiles
            bytes.storeBytes(of: UInt32(1), toByteOffset: 16, as: UInt32.self)  // fWide = TRUE
        }
        for path in paths {
            var widePath = Array(path.utf16)
            widePath.append(0)
            widePath.withUnsafeBytes { payload.append(contentsOf: $0) }
        }
        payload.append(contentsOf: [0, 0])  // final double-null terminator

        guard OpenClipboard(nil) else { return }
        defer { CloseClipboard() }
        EmptyClipboard()

        guard let hGlobal = GlobalAlloc(UINT(GMEM_MOVEABLE), SIZE_T(payload.count)) else { return }
        guard let ptr = GlobalLock(hGlobal) else {
            GlobalFree(hGlobal)
            return
        }
        let destination = ptr.bindMemory(to: UInt8.self, capacity: payload.count)
        payload.withUnsafeBytes { source in
            for index in 0..<source.count {
                destination[index] = source[index]
            }
        }
        GlobalUnlock(hGlobal)

        _ = SetClipboardData(Self.cfHDrop, hGlobal)
    }

    public func pastedFiles() -> [String] {
        guard OpenClipboard(nil) else { return [] }
        defer { CloseClipboard() }

        guard let handle = GetClipboardData(Self.cfHDrop) else { return [] }
        let hDrop = handle.assumingMemoryBound(to: HDROP__.self)
        let count = DragQueryFileW(hDrop, 0xFFFF_FFFF, nil, 0)
        guard count > 0 else { return [] }

        var paths: [String] = []
        for index in 0..<count {
            let length = DragQueryFileW(hDrop, index, nil, 0)
            guard length > 0 else { continue }
            var buffer = [WCHAR](repeating: 0, count: Int(length) + 1)
            let copied = buffer.withUnsafeMutableBufferPointer { buf in
                DragQueryFileW(hDrop, index, buf.baseAddress, UINT(buf.count))
            }
            if copied > 0 {
                paths.append(String(decodingCString: buffer, as: UTF16.self))
            }
        }
        return paths
    }
}

@MainActor
public enum ClipboardManager {
    /// File-list clipboard backend. Defaults to the real Win32 `CF_HDROP`
    /// store; tests inject a fake `ClipboardFileStore` and restore this
    /// afterwards. The plain-text path above does not go through this seam.
    public static var fileStore: any ClipboardFileStore = Win32ClipboardFileStore()

    /// `true` when the clipboard currently carries Unicode text. Read-only.
    public static var hasText: Bool {
        IsClipboardFormatAvailable(UINT(CF_UNICODETEXT))
    }

    /// `true` when the clipboard currently carries a file list (`CF_HDROP`).
    public static var hasFileURLs: Bool {
        fileStore.containsFiles()
    }

    /// Copies file URLs onto the clipboard as an HDROP file list so
    /// Explorer-style file workflows (ShareLink, ExportButton) can paste real
    /// files. Non-file URLs are ignored; when none remain the clipboard is
    /// left untouched.
    public static func copyFileURLs(_ urls: [URL]) {
        let paths = urls.filter { $0.isFileURL }.map { $0.path }
        guard !paths.isEmpty else { return }
        fileStore.copyFiles(paths)
    }

    /// File URLs from the clipboard's HDROP file list, empty when the
    /// clipboard carries no files.
    public static func pasteFileURLs() -> [URL] {
        fileStore.pastedFiles().map { URL(fileURLWithPath: $0) }
    }

    public static func copyString(_ text: String) {
        guard OpenClipboard(nil) else { return }
        defer { CloseClipboard() }
        EmptyClipboard()

        let utf16 = text.utf16
        let byteCount = (utf16.count + 1) * MemoryLayout<UTF16.CodeUnit>.size
        guard let hGlobal = GlobalAlloc(UINT(GMEM_MOVEABLE), SIZE_T(byteCount)) else { return }
        guard let ptr = GlobalLock(hGlobal) else {
            GlobalFree(hGlobal)
            return
        }
        defer { GlobalUnlock(hGlobal) }

        let buffer = ptr.bindMemory(to: UTF16.CodeUnit.self, capacity: utf16.count + 1)
        for (index, codeUnit) in utf16.enumerated() {
            buffer[index] = codeUnit
        }
        buffer[utf16.count] = 0

        _ = SetClipboardData(UINT(CF_UNICODETEXT), hGlobal)
    }

    public static func pasteString() -> String? {
        guard OpenClipboard(nil) else { return nil }
        defer { CloseClipboard() }

        guard let hGlobal = GetClipboardData(UINT(CF_UNICODETEXT)) else { return nil }
        guard let ptr = GlobalLock(hGlobal) else { return nil }
        defer { GlobalUnlock(hGlobal) }

        let text = String(decodingCString: ptr.assumingMemoryBound(to: UTF16.CodeUnit.self), as: UTF16.self)
        return text
    }

    public static func copyItems(_ items: [Any]) {
        if items.count == 1, let text = items.first as? String {
            copyString(text)
            return
        }
        if let strings = items as? [String], !strings.isEmpty {
            copyString(strings.joined(separator: "\n"))
            return
        }
        if items.count == 1, let url = items.first as? URL {
            copyString(url.absoluteString)
            return
        }
    }

    public static func pasteItems(for types: [UTType]) -> [Any] {
        var results: [Any] = []
        for type in types {
            switch type.identifier {
            case UTType.plainText.identifier, UTType.text.identifier, UTType.utf8PlainText.identifier:
                if let text = pasteString(), !text.isEmpty {
                    results.append(text)
                }
            case UTType.url.identifier, UTType.fileURL.identifier:
                if let text = pasteString(), !text.isEmpty, let url = URL(string: text) {
                    results.append(url)
                }
            default:
                if let text = pasteString(), !text.isEmpty {
                    results.append(text)
                }
            }
        }
        return results.isEmpty ? [] : results
    }
}
