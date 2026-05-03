import Foundation
import SwiftWindowsCore
import WinSDK

@MainActor
public final class Win32TextClipboard {
    /// The window that owns clipboard writes after `EmptyClipboard`.
    /// Reads can work without an owner, but writes should set this to the host window handle.
    public var ownerWindow: NativeWindowHandle?

    public init(ownerWindow: NativeWindowHandle? = nil) {
        self.ownerWindow = ownerWindow
    }

    public func readString() -> String? {
        try? readStringOrThrow()
    }

    public func writeString(_ string: String) {
        try? writeStringOrThrow(string)
    }

    public func readStringOrThrow() throws -> String? {
        guard IsClipboardFormatAvailable(UINT(CF_UNICODETEXT)) else {
            return nil
        }

        try openClipboard()
        defer { CloseClipboard() }

        guard let dataHandle = GetClipboardData(UINT(CF_UNICODETEXT)) else {
            return nil
        }

        guard let rawPointer = GlobalLock(dataHandle) else {
            throw lastClipboardError("GlobalLock")
        }
        defer { GlobalUnlock(dataHandle) }

        let textPointer = rawPointer.assumingMemoryBound(to: WCHAR.self)
        return WindowsClipboardTextEncoding.string(fromNullTerminatedUTF16: textPointer)
    }

    public func writeStringOrThrow(_ string: String) throws {
        let textUnits = WindowsClipboardTextEncoding.nullTerminatedUTF16Units(for: string)
        let byteCount = textUnits.count * MemoryLayout<WCHAR>.size

        guard let allocation = GlobalAlloc(UINT(GMEM_MOVEABLE), SIZE_T(byteCount)) else {
            throw lastClipboardError("GlobalAlloc")
        }

        var didTransferAllocationToClipboard = false
        defer {
            if !didTransferAllocationToClipboard {
                GlobalFree(allocation)
            }
        }

        guard let rawPointer = GlobalLock(allocation) else {
            throw lastClipboardError("GlobalLock")
        }

        textUnits.withUnsafeBufferPointer { buffer in
            rawPointer.copyMemory(from: buffer.baseAddress!, byteCount: byteCount)
        }
        GlobalUnlock(allocation)

        try openClipboard()
        defer { CloseClipboard() }

        guard EmptyClipboard() else {
            throw lastClipboardError("EmptyClipboard")
        }

        guard SetClipboardData(UINT(CF_UNICODETEXT), allocation) != nil else {
            throw lastClipboardError("SetClipboardData")
        }

        didTransferAllocationToClipboard = true
    }

    private func openClipboard() throws {
        let owner: HWND? = ownerWindow?.rawPointer?.assumingMemoryBound(to: HWND__.self)
        guard OpenClipboard(owner) else {
            throw lastClipboardError("OpenClipboard")
        }
    }
}

internal enum WindowsClipboardTextEncoding {
    static func nullTerminatedUTF16Units(for string: String) -> [WCHAR] {
        var units = Array(normalizeForClipboard(string).utf16)
        units.append(0)
        return units
    }

    static func string(fromUTF16Units units: [WCHAR]) -> String {
        let textUnits = units.prefix { $0 != 0 }
        let decoded = String(decoding: textUnits, as: UTF16.self)
        return normalizeFromClipboard(decoded)
    }

    static func string(fromNullTerminatedUTF16 pointer: UnsafePointer<WCHAR>) -> String {
        var units: [WCHAR] = []
        var offset = 0

        while pointer[offset] != 0 {
            units.append(pointer[offset])
            offset += 1
        }

        return string(fromUTF16Units: units)
    }

    private static func normalizeForClipboard(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: "\r\n")
    }

    private static func normalizeFromClipboard(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}

private func lastClipboardError(_ operation: String) -> Win32PlatformError {
    Win32PlatformError(operation: operation, code: GetLastError())
}
