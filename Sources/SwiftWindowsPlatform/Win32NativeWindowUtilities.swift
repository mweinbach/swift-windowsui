import Foundation
import SwiftWindowsCore
import WinSDK

/// The failed-create registry decision after native creation/rollback has
/// unwound. Native ownership is retained until both handle destruction and
/// resource cleanup are facts, including a failed DestroyWindow rollback.
enum Win32NativeCreationCleanup: Equatable {
    case releaseOwner
    case retainOwner

    static func afterFailure(
        didBindHandle: Bool,
        didObserveNonClientDestruction: Bool,
        hasLiveNativeResources: Bool
    ) -> Self {
        guard !hasLiveNativeResources, !didBindHandle || didObserveNonClientDestruction else { return .retainOwner }
        return .releaseOwner
    }
}

/// Native-only helpers shared by the owner window implementation. None calls
/// the MainActor Win32Window's legacy helpers or its injectable UI state.
enum Win32NativeWindowUtilities {
    /// Only the disabled/grayed state changes. Check marks, highlighting,
    /// default-item status, and any other existing state bits are preserved.
    static func menuItemState(_ previous: UINT, enabled: Bool) -> UINT {
        let disabledMask = UINT(MFS_DISABLED)
        return (previous & ~disabledMask) | (enabled ? UINT(MFS_ENABLED) : disabledMask)
    }

    static func windowStyle(
        titleBarVisibility: WindowTitleBarVisibility, configuration: Win32WindowConfiguration
    ) -> DWORD {
        var style: Int32
        switch titleBarVisibility.kind {
        case .hidden:
            style =
                Int32(bitPattern: UInt32(WS_POPUP)) | Int32(WS_THICKFRAME) | Int32(WS_MINIMIZEBOX)
                | Int32(WS_MAXIMIZEBOX)
        default:
            style = Int32(WS_OVERLAPPEDWINDOW)
        }
        if configuration.resizability == .fixedSize { style &= ~(Int32(WS_THICKFRAME) | Int32(WS_MAXIMIZEBOX)) }
        return DWORD(UInt32(bitPattern: style))
    }

    static func creationGeometry(logicalSize: IntSize, style: DWORD, dpi: UINT) -> IntSize {
        let scale = Double(max(1, dpi)) / 96
        let width = min(Double(Int32.max), (Double(max(1, logicalSize.width)) * scale).rounded())
        let height = min(Double(Int32.max), (Double(max(1, logicalSize.height)) * scale).rounded())
        var rect = RECT(left: 0, top: 0, right: LONG(width), bottom: LONG(height))
        if AdjustWindowRectExForDpi(&rect, style, false, 0, dpi) {
            let outerWidth = Int64(rect.right) - Int64(rect.left)
            let outerHeight = Int64(rect.bottom) - Int64(rect.top)
            return IntSize(width: Int32(clamping: outerWidth), height: Int32(clamping: outerHeight))
        }
        return IntSize(width: Int32(width), height: Int32(height))
    }

    static func creationDpi() -> UINT {
        let dpi = GetDpiForSystem()
        return dpi > 0 ? dpi : 96
    }

    static func enableHighDpiSupport() {
        // Set the native owner's thread context even when another host has
        // already fixed the process-wide DPI policy. All its HWND creation
        // and geometry calls use the same public per-monitor-v2 context.
        guard let module = "user32.dll".withNativeWideChars({ GetModuleHandleW($0) }) else { return }
        typealias SetProcessContext = @convention(c) (UnsafeMutableRawPointer?) -> Int32
        if let address = "SetProcessDpiAwarenessContext".withCString({ GetProcAddress(module, $0) }) {
            let setContext = unsafeBitCast(address, to: SetProcessContext.self)
            _ = setContext(UnsafeMutableRawPointer(bitPattern: -4))
        }
        typealias SetContext = @convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
        if let address = "SetThreadDpiAwarenessContext".withCString({ GetProcAddress(module, $0) }) {
            let setContext = unsafeBitCast(address, to: SetContext.self)
            _ = setContext(UnsafeMutableRawPointer(bitPattern: -4))
        }
    }

    static func monitorSnapshot(hwnd: HWND?) -> (refreshRate: UInt32, displayIdentity: String, monitorID: UInt) {
        guard let hwnd else { return (60, "no-display", 0) }
        let monitor = MonitorFromWindow(hwnd, DWORD(MONITOR_DEFAULTTONEAREST))
        let identity = UInt(bitPattern: monitor)
        var info = MONITORINFOEXW()
        info.cbSize = DWORD(MemoryLayout<MONITORINFOEXW>.size)
        let read = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: MONITORINFO.self, capacity: 1) { GetMonitorInfoW(monitor, $0) }
        }
        guard read else { return (60, "unknown-display", identity) }
        let name = withUnsafePointer(to: info.szDevice) { pointer in
            pointer.withMemoryRebound(to: WCHAR.self, capacity: 32) { String(decodingCString: $0, as: UTF16.self) }
        }
        var mode = DEVMODEW()
        mode.dmSize = WORD(MemoryLayout<DEVMODEW>.size)
        let hasMode = withUnsafeMutablePointer(to: &info.szDevice.0) { device in
            EnumDisplaySettingsW(device, DWORD(bitPattern: -1), &mode)
        }
        guard hasMode else { return (60, name, identity) }
        return (
            mode.dmDisplayFrequency > 0 ? mode.dmDisplayFrequency : 60,
            "\(name) \(mode.dmPelsWidth)x\(mode.dmPelsHeight)@\(mode.dmDisplayFrequency)", identity
        )
    }

    static func point(from lParam: LPARAM) -> Point {
        let packed = UInt32(truncatingIfNeeded: lParam)
        return Point(
            x: Double(Int16(bitPattern: UInt16(packed & 0xFFFF))),
            y: Double(Int16(bitPattern: UInt16((packed >> 16) & 0xFFFF))))
    }

    static func clientPoint(fromScreenLParam lParam: LPARAM, hwnd: HWND?) -> Point {
        let screen = point(from: lParam)
        var native = POINT(x: LONG(screen.x), y: LONG(screen.y))
        ScreenToClient(hwnd, &native)
        return Point(x: Double(native.x), y: Double(native.y))
    }

    static func keyboardEvent(wParam: WPARAM, lParam: LPARAM) -> KeyboardEvent {
        var modifiers: KeyboardModifiers = []
        if GetKeyState(VK_SHIFT) < 0 { modifiers.insert(.shift) }
        if GetKeyState(VK_CONTROL) < 0 { modifiers.insert(.control) }
        if GetKeyState(VK_MENU) < 0 { modifiers.insert(.alt) }
        return KeyboardEvent(
            keyCode: UInt32(truncatingIfNeeded: wParam), modifiers: modifiers,
            isRepeat: (UInt(truncatingIfNeeded: lParam) & 0x4000_0000) != 0,
            textInputDelivery: .systemCharacter)
    }

    static func mouseWheelDelta(wParam: WPARAM, horizontal: Bool) -> Double {
        var units: UINT = 3
        let action = horizontal ? UINT(SPI_GETWHEELSCROLLCHARS) : UINT(SPI_GETWHEELSCROLLLINES)
        if !SystemParametersInfoW(action, 0, &units, 0) || units == UINT.max { units = 3 }
        let signedDelta = Int16(bitPattern: UInt16((UInt(wParam) >> 16) & 0xFFFF))
        return Double(signedDelta) / Double(WHEEL_DELTA) * Double(units)
    }

    static func shouldDeliverSettingChange(wParam: WPARAM, section: String?) -> Bool {
        let actions: Set<WPARAM> = [
            WPARAM(SPI_SETNONCLIENTMETRICS), WPARAM(SPI_SETICONTITLELOGFONT), WPARAM(SPI_SETICONMETRICS),
            WPARAM(SPI_SETHIGHCONTRAST), WPARAM(SPI_SETCLIENTAREAANIMATION), WPARAM(SPI_SETFONTSMOOTHING),
            WPARAM(SPI_SETFONTSMOOTHINGTYPE), WPARAM(SPI_SETFONTSMOOTHINGCONTRAST),
        ]
        return actions.contains(wParam)
            || ["immersivecolorset", "windowsthemeelement", "intl"].contains(section?.lowercased() ?? "")
    }

    static func settingChangeSection(_ lParam: LPARAM) -> String? {
        let address = UInt(bitPattern: Int(lParam))
        guard address != 0, address % UInt(MemoryLayout<WCHAR>.alignment) == 0 else { return nil }
        let maximumBytes = UInt(64 * MemoryLayout<WCHAR>.size)
        guard !address.addingReportingOverflow(maximumBytes).overflow else { return nil }
        var readable: UInt = 0
        let infoSize = SIZE_T(MemoryLayout<MEMORY_BASIC_INFORMATION>.size)
        while readable < maximumBytes {
            var info = MEMORY_BASIC_INFORMATION()
            guard VirtualQuery(UnsafeRawPointer(bitPattern: address + readable), &info, infoSize) == infoSize,
                info.State == DWORD(MEM_COMMIT), info.Protect & DWORD(PAGE_GUARD | PAGE_NOACCESS) == 0
            else { break }
            let allowed = DWORD(
                PAGE_READONLY | PAGE_READWRITE | PAGE_WRITECOPY | PAGE_EXECUTE_READ | PAGE_EXECUTE_READWRITE
                    | PAGE_EXECUTE_WRITECOPY)
            guard info.Protect & allowed != 0 else { break }
            let start = UInt(bitPattern: info.BaseAddress)
            let (end, overflow) = start.addingReportingOverflow(UInt(info.RegionSize))
            guard !overflow, end > address + readable else { break }
            readable = min(maximumBytes, end - address)
        }
        guard readable >= UInt(MemoryLayout<WCHAR>.size), let pointer = UnsafePointer<WCHAR>(bitPattern: address) else {
            return nil
        }
        var units: [WCHAR] = []
        for index in 0..<Int(readable / UInt(MemoryLayout<WCHAR>.size)) {
            if pointer[index] == 0 { return String(decoding: units, as: UTF16.self) }
            units.append(pointer[index])
        }
        return nil
    }

    static func dropPayload(wParam: WPARAM) -> FileDropPayload? {
        guard let raw = UnsafeMutableRawPointer(bitPattern: UInt(wParam)),
            GlobalSize(raw) >= SIZE_T(DropFilesPayloadValidator.headerSize)
        else { return nil }
        let drop = raw.assumingMemoryBound(to: HDROP__.self)
        defer { DragFinish(drop) }
        guard DropFilesPayloadValidator.hasWellFormedPayload(raw) else { return nil }
        let count = DragQueryFileW(drop, UINT.max, nil, 0)
        var paths: [URL] = []
        for index in 0..<count {
            let length = DragQueryFileW(drop, index, nil, 0)
            guard length > 0, length < UINT.max else { continue }
            var units = [WCHAR](repeating: 0, count: Int(length) + 1)
            let copied = units.withUnsafeMutableBufferPointer { buffer in
                DragQueryFileW(drop, index, buffer.baseAddress, UINT(buffer.count))
            }
            if copied > 0, copied <= length {
                paths.append(URL(fileURLWithPath: String(decoding: units.prefix(Int(copied)), as: UTF16.self)))
            }
        }
        guard !paths.isEmpty else { return nil }
        var nativePoint = POINT()
        let hasPoint = DragQueryPoint(drop, &nativePoint)
        return FileDropPayload(
            fileURLs: paths,
            clientPoint: hasPoint ? Point(x: Double(nativePoint.x), y: Double(nativePoint.y)) : .zero)
    }

    static func imeCompositionEvents(
        lParam: LPARAM, hwnd: HWND?, provider: any IMECompositionContextProvider
    ) -> [IMECompositionEvent] {
        let flags = UInt(truncatingIfNeeded: lParam)
        var events: [IMECompositionEvent] = []
        if flags & UInt(GCS_COMPSTR) != 0, let text = provider.compositionString(window: hwnd) {
            events.append(IMECompositionEvent(phase: .updated(text)))
        }
        if flags & UInt(GCS_RESULTSTR) != 0, let text = provider.resultString(window: hwnd) {
            events.append(IMECompositionEvent(phase: .committed(text)))
        }
        return events
    }

    static func imeAdjustedLParam(_ lParam: LPARAM) -> LPARAM {
        lParam & ~LPARAM(bitPattern: UInt64(0x8000_0000))
    }
}
