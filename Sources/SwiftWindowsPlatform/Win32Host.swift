import SwiftWindowsCore
import WinSDK

@MainActor
public protocol WindowDelegate: AnyObject {
    func windowDidCreate(_ window: Win32Window)
    func window(_ window: Win32Window, didResizeTo size: IntSize)
    func windowNeedsDisplay(_ window: Win32Window)
    func window(_ window: Win32Window, animationFrameAt timestamp: Double)
    func window(_ window: Win32Window, pointerMovedTo point: Point)
    func windowPointerDidLeave(_ window: Win32Window)
    func window(_ window: Win32Window, mouseWheelAt point: Point, delta: Double)
    func window(_ window: Win32Window, leftMouseDownAt point: Point)
    func window(_ window: Win32Window, leftMouseUpAt point: Point)
    func window(_ window: Win32Window, keyDown event: KeyboardEvent)
    func windowDidLoseKeyboardFocus(_ window: Win32Window)
    func windowWillClose(_ window: Win32Window)
}

public extension WindowDelegate {
    func windowDidCreate(_ window: Win32Window) {}
    func window(_ window: Win32Window, didResizeTo size: IntSize) {}
    func windowNeedsDisplay(_ window: Win32Window) {}
    func window(_ window: Win32Window, animationFrameAt timestamp: Double) {}
    func window(_ window: Win32Window, pointerMovedTo point: Point) {}
    func windowPointerDidLeave(_ window: Win32Window) {}
    func window(_ window: Win32Window, mouseWheelAt point: Point, delta: Double) {}
    func window(_ window: Win32Window, leftMouseDownAt point: Point) {}
    func window(_ window: Win32Window, leftMouseUpAt point: Point) {}
    func window(_ window: Win32Window, keyDown event: KeyboardEvent) {}
    func windowDidLoseKeyboardFocus(_ window: Win32Window) {}
    func windowWillClose(_ window: Win32Window) {}
}

public struct Win32PlatformError: Error, CustomStringConvertible, Sendable {
    public let operation: String
    public let code: DWORD

    public init(operation: String, code: DWORD) {
        self.operation = operation
        self.code = code
    }

    public var description: String {
        "\(operation) failed with Win32 error code \(code)."
    }
}

@MainActor
public final class Win32Window {
    public weak var delegate: WindowDelegate?

    public let title: String
    public private(set) var clientSize: IntSize

    private var hwnd: HWND?
    private var isTrackingMouseLeave = false
    private var isAnimationTimerRunning = false

    public init(title: String, clientSize: IntSize) {
        self.title = title
        self.clientSize = clientSize
    }

    public var nativeHandle: NativeWindowHandle? {
        let rawHandle: UnsafeMutableRawPointer? = unsafeBitCast(hwnd, to: UnsafeMutableRawPointer?.self)
        return NativeWindowHandle(rawPointer: rawHandle)
    }

    public var scaleFactor: Double {
        guard let hwnd else {
            return 1.0
        }

        let dpi = GetDpiForWindow(hwnd)
        if dpi == 0 {
            return 1.0
        }

        return Double(dpi) / 96.0
    }

    public func create() throws {
        guard hwnd == nil else {
            return
        }

        try Self.registerWindowClass()

        guard let instance = GetModuleHandleW(nil) else {
            throw Self.lastError(for: "GetModuleHandleW")
        }

        let rawSelf = Unmanaged.passUnretained(self).toOpaque()
        let style = DWORD(UInt32(bitPattern: Int32(WS_OVERLAPPEDWINDOW)))

        let createdWindow: HWND? = try Self.className.withWideChars { className in
            try title.withWideChars { title in
                let window = CreateWindowExW(
                    0,
                    className,
                    title,
                    style,
                    CW_USEDEFAULT,
                    CW_USEDEFAULT,
                    Int32(clientSize.width),
                    Int32(clientSize.height),
                    nil,
                    nil,
                    instance,
                    rawSelf
                )

                guard let window else {
                    throw Self.lastError(for: "CreateWindowExW")
                }

                return window
            }
        }

        hwnd = createdWindow
        delegate?.windowDidCreate(self)
    }

    public func show() {
        guard let hwnd else {
            return
        }

        ShowWindow(hwnd, SW_SHOW)
        UpdateWindow(hwnd)
        invalidate()
    }

    public func invalidate() {
        guard let hwnd else {
            return
        }

        InvalidateRect(hwnd, nil, false)
    }

    public func setAnimationTimerEnabled(_ enabled: Bool, intervalMilliseconds: UINT = 16) {
        guard let hwnd else {
            return
        }

        if enabled {
            guard !isAnimationTimerRunning else {
                return
            }

            SetTimer(hwnd, Self.animationTimerIdentifier, intervalMilliseconds, nil)
            isAnimationTimerRunning = true
            return
        }

        guard isAnimationTimerRunning else {
            return
        }

        KillTimer(hwnd, Self.animationTimerIdentifier)
        isAnimationTimerRunning = false
    }

    public func currentClientSize() -> IntSize {
        guard let hwnd else {
            return clientSize
        }

        var rect = RECT()
        GetClientRect(hwnd, &rect)
        return IntSize(width: Int32(rect.right - rect.left), height: Int32(rect.bottom - rect.top))
    }

    private func handleMessage(hwnd: HWND?, message: UINT, wParam: WPARAM, lParam: LPARAM) -> LRESULT {
        switch message {
        case UINT(WM_ERASEBKGND):
            return 1

        case UINT(WM_SIZE):
            let updatedSize = currentClientSize()
            clientSize = updatedSize
            delegate?.window(self, didResizeTo: updatedSize)
            return 0

        case UINT(WM_DPICHANGED):
            if let suggestedRect = UnsafeMutableRawPointer(bitPattern: Int(lParam))?.assumingMemoryBound(to: RECT.self) {
                SetWindowPos(
                    hwnd,
                    nil,
                    suggestedRect.pointee.left,
                    suggestedRect.pointee.top,
                    suggestedRect.pointee.right - suggestedRect.pointee.left,
                    suggestedRect.pointee.bottom - suggestedRect.pointee.top,
                    UINT(SWP_NOACTIVATE | SWP_NOZORDER)
                )
            }

            let updatedSize = currentClientSize()
            clientSize = updatedSize
            delegate?.window(self, didResizeTo: updatedSize)
            return 0

        case UINT(WM_PAINT):
            var paint = PAINTSTRUCT()
            BeginPaint(hwnd, &paint)
            delegate?.windowNeedsDisplay(self)
            EndPaint(hwnd, &paint)
            return 0

        case UINT(WM_TIMER):
            if UInt(truncatingIfNeeded: wParam) == Self.animationTimerIdentifier {
                delegate?.window(self, animationFrameAt: Self.currentTimestampSeconds())
                return 0
            }

            return DefWindowProcW(hwnd, message, wParam, lParam)

        case UINT(WM_MOUSEMOVE):
            beginTrackingMouseLeaveIfNeeded()
            delegate?.window(self, pointerMovedTo: Self.point(from: lParam))
            return 0

        case UINT(WM_MOUSELEAVE):
            isTrackingMouseLeave = false
            delegate?.windowPointerDidLeave(self)
            return 0

        case UINT(WM_MOUSEWHEEL):
            delegate?.window(self, mouseWheelAt: Self.clientPoint(fromScreenLParam: lParam, hwnd: hwnd), delta: Self.mouseWheelDelta(from: wParam))
            return 0

        case UINT(WM_LBUTTONDOWN):
            SetFocus(hwnd)
            SetCapture(hwnd)
            delegate?.window(self, leftMouseDownAt: Self.point(from: lParam))
            return 0

        case UINT(WM_LBUTTONUP):
            ReleaseCapture()
            delegate?.window(self, leftMouseUpAt: Self.point(from: lParam))
            return 0

        case UINT(WM_KEYDOWN):
            delegate?.window(self, keyDown: Self.keyboardEvent(from: wParam, lParam: lParam))
            return 0

        case UINT(WM_KILLFOCUS):
            delegate?.windowDidLoseKeyboardFocus(self)
            return 0

        case UINT(WM_DESTROY):
            setAnimationTimerEnabled(false)
            delegate?.windowWillClose(self)
            PostQuitMessage(0)
            return 0

        default:
            return DefWindowProcW(hwnd, message, wParam, lParam)
        }
    }

    private static func registerWindowClass() throws {
        if didRegisterClass {
            return
        }

        guard let instance = GetModuleHandleW(nil) else {
            throw lastError(for: "GetModuleHandleW")
        }

        let cursor = LoadCursorW(nil, UnsafePointer<WCHAR>(bitPattern: 32512))

        try className.withWideChars { className in
            var windowClass = WNDCLASSEXW()
            windowClass.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
            windowClass.style = UINT(CS_HREDRAW | CS_VREDRAW)
            windowClass.lpfnWndProc = windowProc
            windowClass.hInstance = instance
            windowClass.hCursor = cursor
            windowClass.lpszClassName = className

            let atom = RegisterClassExW(&windowClass)
            if atom == 0 {
                let error = GetLastError()
                if error != DWORD(ERROR_CLASS_ALREADY_EXISTS) {
                    throw Win32PlatformError(operation: "RegisterClassExW", code: error)
                }
            }
        }

        didRegisterClass = true
    }

    private static func lastError(for operation: String) -> Win32PlatformError {
        Win32PlatformError(operation: operation, code: GetLastError())
    }

    private func beginTrackingMouseLeaveIfNeeded() {
        guard !isTrackingMouseLeave, let hwnd else {
            return
        }

        var tracking = TRACKMOUSEEVENT()
        tracking.cbSize = DWORD(MemoryLayout<TRACKMOUSEEVENT>.size)
        tracking.dwFlags = DWORD(TME_LEAVE)
        tracking.hwndTrack = hwnd
        tracking.dwHoverTime = 0

        if TrackMouseEvent(&tracking) {
            isTrackingMouseLeave = true
        }
    }

    private static func point(from lParam: LPARAM) -> Point {
        let packed = UInt32(truncatingIfNeeded: lParam)
        let x = Int32(Int16(bitPattern: UInt16(packed & 0xFFFF)))
        let y = Int32(Int16(bitPattern: UInt16((packed >> 16) & 0xFFFF)))
        return Point(x: Double(x), y: Double(y))
    }

    private static func clientPoint(fromScreenLParam lParam: LPARAM, hwnd: HWND?) -> Point {
        var point = POINT(
            x: LONG(Int16(bitPattern: UInt16(UInt32(truncatingIfNeeded: lParam) & 0xFFFF))),
            y: LONG(Int16(bitPattern: UInt16((UInt32(truncatingIfNeeded: lParam) >> 16) & 0xFFFF)))
        )
        ScreenToClient(hwnd, &point)
        return Point(x: Double(point.x), y: Double(point.y))
    }

    private static func mouseWheelDelta(from wParam: WPARAM) -> Double {
        let highWord = UInt16((UInt(truncatingIfNeeded: wParam) >> 16) & 0xFFFF)
        let signedDelta = Int16(bitPattern: highWord)
        return Double(signedDelta) / Double(WHEEL_DELTA)
    }

    public static func currentTimestampSeconds() -> Double {
        Double(GetTickCount64()) / 1000.0
    }

    private static func keyboardEvent(from wParam: WPARAM, lParam: LPARAM) -> KeyboardEvent {
        KeyboardEvent(
            keyCode: UInt32(truncatingIfNeeded: wParam),
            modifiers: currentKeyboardModifiers(),
            isRepeat: (UInt(truncatingIfNeeded: lParam) & 0x40000000) != 0
        )
    }

    private static func currentKeyboardModifiers() -> KeyboardModifiers {
        var modifiers: KeyboardModifiers = []

        if keyIsPressed(VK_SHIFT) {
            modifiers.insert(.shift)
        }

        if keyIsPressed(VK_CONTROL) {
            modifiers.insert(.control)
        }

        if keyIsPressed(VK_MENU) {
            modifiers.insert(.alt)
        }

        return modifiers
    }

    private static func keyIsPressed(_ virtualKey: Int32) -> Bool {
        GetKeyState(virtualKey) < 0
    }

    private static let className = "SwiftWindowsUI.MainWindow"
    private static var didRegisterClass = false
    private static let animationTimerIdentifier: UINT_PTR = 1

    private static let windowProc: WNDPROC = { (hwnd: HWND?, message: UINT, wParam: WPARAM, lParam: LPARAM) -> LRESULT in
        if message == UINT(WM_NCCREATE) {
            let createStructure = UnsafeMutableRawPointer(bitPattern: Int(lParam))?.assumingMemoryBound(to: CREATESTRUCTW.self)
            let rawSelf = createStructure?.pointee.lpCreateParams

            if let rawSelf {
                SetWindowLongPtrW(hwnd, GWLP_USERDATA, LONG_PTR(Int(bitPattern: rawSelf)))
            }
        }

        let rawValue = GetWindowLongPtrW(hwnd, GWLP_USERDATA)
        if let rawSelf = UnsafeMutableRawPointer(bitPattern: Int(rawValue)) {
            let window = Unmanaged<Win32Window>.fromOpaque(rawSelf).takeUnretainedValue()
            return window.handleMessage(hwnd: hwnd, message: message, wParam: wParam, lParam: lParam)
        }

        return DefWindowProcW(hwnd, message, wParam, lParam)
    }
}

@MainActor
public enum Win32Application {
    @discardableResult
    public static func run(window: Win32Window) throws -> Int32 {
        Win32HighDpiSupport.enableIfNeeded()
        try window.create()
        window.show()
        return try runMessageLoop()
    }

    @discardableResult
    public static func runMessageLoop() throws -> Int32 {
        var message = MSG()

        while GetMessageW(&message, nil, 0, 0) {
            TranslateMessage(&message)
            DispatchMessageW(&message)
        }

        return Int32(truncatingIfNeeded: message.wParam)
    }
}

@MainActor
private enum Win32HighDpiSupport {
    private static var didConfigure = false
    private static let perMonitorAware: Int32 = 2
    private static let perMonitorAwareV2Context = UnsafeMutableRawPointer(bitPattern: -4)

    static func enableIfNeeded() {
        guard !didConfigure else {
            return
        }

        didConfigure = true

        if setProcessDpiAwarenessContext() {
            return
        }

        if setProcessDpiAwareness() {
            return
        }

        _ = setProcessDPIAware()
    }

    private static func setProcessDpiAwarenessContext() -> Bool {
        guard let module = loadLibrary(named: "user32.dll") else {
            return false
        }
        defer { FreeLibrary(module) }

        guard let symbol = "SetProcessDpiAwarenessContext".withCString({ GetProcAddress(module, $0) }) else {
            return false
        }

        typealias Proc = @convention(c) (UnsafeMutableRawPointer?) -> Int32
        let function = unsafeBitCast(symbol, to: Proc.self)
        return function(perMonitorAwareV2Context) != 0
    }

    private static func setProcessDpiAwareness() -> Bool {
        guard let module = loadLibrary(named: "shcore.dll") else {
            return false
        }
        defer { FreeLibrary(module) }

        guard let symbol = "SetProcessDpiAwareness".withCString({ GetProcAddress(module, $0) }) else {
            return false
        }

        typealias Proc = @convention(c) (Int32) -> HRESULT
        let function = unsafeBitCast(symbol, to: Proc.self)
        let result = function(perMonitorAware)
        return result >= 0 || result == HRESULT(bitPattern: 0x80070005)
    }

    private static func setProcessDPIAware() -> Bool {
        guard let module = loadLibrary(named: "user32.dll") else {
            return false
        }
        defer { FreeLibrary(module) }

        guard let symbol = "SetProcessDPIAware".withCString({ GetProcAddress(module, $0) }) else {
            return false
        }

        typealias Proc = @convention(c) () -> Int32
        let function = unsafeBitCast(symbol, to: Proc.self)
        return function() != 0
    }

    private static func loadLibrary(named name: String) -> HMODULE? {
        var wideName = Array(name.utf16)
        wideName.append(0)
        return wideName.withUnsafeBufferPointer { buffer in
            LoadLibraryW(buffer.baseAddress)
        }
    }
}

private extension String {
    func withWideChars<Result>(_ body: (UnsafePointer<WCHAR>) throws -> Result) rethrows -> Result {
        var characters = Array(utf16)
        characters.append(0)

        return try characters.withUnsafeBufferPointer { buffer in
            try body(UnsafePointer(buffer.baseAddress!))
        }
    }
}
