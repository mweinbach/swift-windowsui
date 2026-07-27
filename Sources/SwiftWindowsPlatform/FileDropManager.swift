import Foundation
import SwiftWindowsCore
import WinSDK

/// Payload extracted from a `WM_DROPFILES` drop handle: the dropped files as
/// file URLs plus the client-coordinate drop point.
public struct FileDropPayload: Equatable, Sendable {
    public let fileURLs: [URL]
    public let clientPoint: Point

    public init(fileURLs: [URL], clientPoint: Point) {
        self.fileURLs = fileURLs
        self.clientPoint = clientPoint
    }
}

/// Raw HDROP access seam for `WM_DROPFILES` handling. The production default
/// is `Win32FileDropPayloadSource`, which talks to the real shell drag-drop
/// API; tests inject a fake so no OS drop handle is required (same pattern as
/// `SystemAppearanceProvider`). Handles are opaque `UInt`s so the seam never
/// leaks WinSDK types into tests.
@MainActor
public protocol FileDropPayloadSource: AnyObject {
    func filePaths(forDropHandle handle: UInt) -> [String]
    func clientPoint(forDropHandle handle: UInt) -> Point?
    func finishDrop(handle: UInt)
}

/// Live shell drag-drop source (`DragQueryFileW` / `DragQueryPoint` /
/// `DragFinish`), matching what Explorer produces when files are dragged onto
/// a window registered with `DragAcceptFiles`.
public final class Win32FileDropPayloadSource: FileDropPayloadSource {
    public init() {}

    public func filePaths(forDropHandle handle: UInt) -> [String] {
        guard let hDrop = Self.hDrop(for: handle) else { return [] }
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

    public func clientPoint(forDropHandle handle: UInt) -> Point? {
        guard let hDrop = Self.hDrop(for: handle) else { return nil }
        var rawPoint = POINT(x: 0, y: 0)
        // The returned coordinates are already in the drop target's client
        // space (the point is client-relative for WM_DROPFILES).
        guard DragQueryPoint(hDrop, &rawPoint) else { return nil }
        return Point(x: Double(rawPoint.x), y: Double(rawPoint.y))
    }

    public func finishDrop(handle: UInt) {
        guard let hDrop = Self.hDrop(for: handle) else { return }
        DragFinish(hDrop)
    }

    /// `HDROP` is not exposed by the WinSDK Swift module beyond its opaque
    /// pointee, so the handle is rebuilt from the raw `wParam` bits.
    private static func hDrop(for handle: UInt) -> UnsafeMutablePointer<HDROP__>? {
        guard handle != 0, let raw = UnsafeMutableRawPointer(bitPattern: handle) else { return nil }
        return raw.assumingMemoryBound(to: HDROP__.self)
    }
}

@MainActor
public enum FileDropManager {
    /// Drop-handle backend. Defaults to the real shell drag-drop API; tests
    /// inject a fake `FileDropPayloadSource` and restore this afterwards.
    public static var payloadSource: any FileDropPayloadSource = Win32FileDropPayloadSource()

    /// Extracts the payload for a `WM_DROPFILES` `wParam` (the HDROP handle).
    /// Always releases the handle via the payload source, matching the
    /// `DragFinish` contract. Returns `nil` when the drop carries no files.
    public static func payload(forDropHandle handle: UInt) -> FileDropPayload? {
        defer { payloadSource.finishDrop(handle: handle) }
        let urls = payloadSource.filePaths(forDropHandle: handle).map { URL(fileURLWithPath: $0) }
        guard !urls.isEmpty else { return nil }
        let point = payloadSource.clientPoint(forDropHandle: handle) ?? .zero
        return FileDropPayload(fileURLs: urls, clientPoint: point)
    }

    /// Registers or unregisters a window as a shell file-drop target
    /// (`DragAcceptFiles`). Call once after window creation; without this the
    /// window never receives `WM_DROPFILES`.
    public static func setAcceptsDroppedFiles(on hwnd: HWND?, _ accepts: Bool) {
        DragAcceptFiles(hwnd, accepts)
    }
}
