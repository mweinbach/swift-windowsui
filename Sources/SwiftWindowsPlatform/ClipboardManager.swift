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
        // The clipboard block belongs to another process; validate the
        // DROPFILES payload before DragQueryFileW walks its embedded offsets.
        guard DropFilesPayloadValidator.hasWellFormedPayload(handle) else { return [] }
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
                paths.append(String(decoding: buffer.prefix(Int(copied)), as: UTF16.self))
            }
        }
        return paths
    }
}

/// Live Win32 Unicode-text clipboard store.
///
/// Kept separate from ``Win32ClipboardFileStore`` so callers can replace the
/// platform's text and file-list services independently without changing the
/// high-level clipboard API.
public final class Win32ClipboardTextStore: ClipboardTextStore {
    public init() {}

    public var hasText: Bool {
        IsClipboardFormatAvailable(UINT(CF_UNICODETEXT))
    }

    public func copyString(_ text: String) {
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

    public func pasteString() -> String? {
        guard OpenClipboard(nil) else { return nil }
        defer { CloseClipboard() }

        guard let hGlobal = GetClipboardData(UINT(CF_UNICODETEXT)) else { return nil }
        guard let ptr = GlobalLock(hGlobal) else { return nil }
        defer { GlobalUnlock(hGlobal) }

        // The clipboard block belongs to another process and may lack a null
        // terminator, so the decode is bounded by the allocation size rather
        // than scanning for a terminator blindly.
        let unitCount = Int(GlobalSize(hGlobal)) / MemoryLayout<UTF16.CodeUnit>.size
        let units = UnsafeBufferPointer(
            start: ptr.assumingMemoryBound(to: UTF16.CodeUnit.self),
            count: unitCount
        )
        return ClipboardManager.decodeNullTerminatedUTF16(units)
    }
}

@MainActor
public enum ClipboardManager {
    /// Plain-text clipboard backend. Defaults to the real Win32 Unicode
    /// clipboard; other platform hosts and headless tests can inject their
    /// own ``ClipboardTextStore`` without touching the system clipboard.
    public static var textStore: any ClipboardTextStore = Win32ClipboardTextStore()

    /// File-list clipboard backend. Defaults to the real Win32 `CF_HDROP`
    /// store; tests inject a fake `ClipboardFileStore` and restore this
    /// afterwards. File and text providers are independently replaceable.
    public static var fileStore: any ClipboardFileStore = Win32ClipboardFileStore()

    /// `true` when the clipboard currently carries Unicode text. Read-only.
    public static var hasText: Bool {
        textStore.hasText
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
        textStore.copyString(text)
    }

    public static func pasteString() -> String? {
        textStore.pasteString()
    }

    /// Decodes UTF-16 code units up to the first null, tolerating a missing
    /// terminator (unterminated input decodes in full instead of reading
    /// past the buffer). Internal so hostile-input tests can drive it.
    static func decodeNullTerminatedUTF16(_ units: UnsafeBufferPointer<UTF16.CodeUnit>) -> String {
        let end = units.firstIndex(of: 0) ?? units.count
        return String(decoding: units[..<end], as: UTF16.self)
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
            // File URLs go onto the clipboard as a real HDROP file list so
            // Explorer-style targets receive actual files; non-file URLs keep
            // the absolute-string behavior.
            if url.isFileURL {
                copyFileURLs([url])
            } else {
                copyString(url.absoluteString)
            }
            return
        }
        let fileURLs = items.compactMap { ($0 as? URL).flatMap { $0.isFileURL ? $0 : nil } }
        if fileURLs.count == items.count, !fileURLs.isEmpty {
            copyFileURLs(fileURLs)
            return
        }
    }

    public static func pasteItems(for types: [UTType]) -> [Any] {
        var results: [Any] = []
        var cachedFileURLs: [URL]?
        var deliveredURLIdentifiers = Set<String>()
        var deliveredText = false

        func fileURLsFromClipboard() -> [URL] {
            if let cachedFileURLs {
                return cachedFileURLs
            }

            let urls = pasteFileURLs()
            cachedFileURLs = urls
            return urls
        }

        func appendUniqueURLs(_ urls: [URL]) {
            for url in urls where deliveredURLIdentifiers.insert(url.absoluteString).inserted {
                results.append(url)
            }
        }

        func appendClipboardText() {
            guard !deliveredText, let text = pasteString(), !text.isEmpty else {
                return
            }

            results.append(text)
            deliveredText = true
        }

        for type in types {
            switch type.identifier {
            case UTType.plainText.identifier, UTType.text.identifier, UTType.utf8PlainText.identifier:
                appendClipboardText()
            case UTType.fileURL.identifier:
                let fileURLs = fileURLsFromClipboard()
                if !fileURLs.isEmpty {
                    appendUniqueURLs(fileURLs)
                } else if let text = pasteString(), !text.isEmpty,
                    let url = URL(string: text), url.isFileURL
                {
                    appendUniqueURLs([url])
                }
            case UTType.url.identifier:
                let fileURLs = fileURLsFromClipboard()
                if !fileURLs.isEmpty {
                    appendUniqueURLs(fileURLs)
                } else if let text = pasteString(), !text.isEmpty,
                    let url = URL(string: text), let scheme = url.scheme, !scheme.isEmpty
                {
                    appendUniqueURLs([url])
                }
            default:
                break
            }
        }
        return results
    }
}
