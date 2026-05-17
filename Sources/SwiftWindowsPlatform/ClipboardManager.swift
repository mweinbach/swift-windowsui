import Foundation
import SwiftWindowsCore
import WinSDK

@MainActor
public enum ClipboardManager {
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
