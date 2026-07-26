import SwiftWindowsCore

import WinSDK

private func win32HighResolutionTimerCallback(_ param: UnsafeMutableRawPointer?, _: UInt8) {
    guard let param else {
        return
    }

    let hwndValue = HWND(bitPattern: Int(bitPattern: param))
    PostMessageW(hwndValue, UINT(WM_TIMER), WPARAM(1), 0)
}
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
    func windowDidChangeDisplay(_ window: Win32Window)
    func windowDidChangeActiveState(_ window: Win32Window, isActive: Bool)
    func windowDidReceiveRightClick(_ window: Win32Window, event: MouseEvent)
    func windowDidReceiveDoubleClick(_ window: Win32Window, event: MouseEvent)
    func window(_ window: Win32Window, horizontalScrollAt point: Point, delta: Double)
    func windowDidChangeVisibility(_ window: Win32Window, isVisible: Bool)
    func windowDidChangeSystemSettings(_ window: Win32Window)
    func window(_ window: Win32Window, middleMouseDownAt point: Point)
    func window(_ window: Win32Window, middleMouseUpAt point: Point)
    func window(_ window: Win32Window, imeCompositionStarted placeholder: Bool)
    func window(_ window: Win32Window, imeCompositionString text: String)
    func window(_ window: Win32Window, imeCompositionEnded placeholder: Bool)
    func window(_ window: Win32Window, imeChar character: UInt32)
    func window(_ window: Win32Window, touchBegan points: [Point])
    func window(_ window: Win32Window, touchMoved points: [Point])
    func window(_ window: Win32Window, touchEnded points: [Point])
}
extension WindowDelegate {
    public func windowDidCreate(_ window: Win32Window) {}
    public func window(_ window: Win32Window, didResizeTo size: IntSize) {}
    public func windowNeedsDisplay(_ window: Win32Window) {}
    public func window(_ window: Win32Window, animationFrameAt timestamp: Double) {}
    public func window(_ window: Win32Window, pointerMovedTo point: Point) {}
    public func windowPointerDidLeave(_ window: Win32Window) {}
    public func window(_ window: Win32Window, mouseWheelAt point: Point, delta: Double) {}
    public func window(_ window: Win32Window, leftMouseDownAt point: Point) {}
    public func window(_ window: Win32Window, leftMouseUpAt point: Point) {}
    public func window(_ window: Win32Window, keyDown event: KeyboardEvent) {}
    public func windowDidLoseKeyboardFocus(_ window: Win32Window) {}
    public func windowWillClose(_ window: Win32Window) {}
    public func windowDidChangeDisplay(_ window: Win32Window) {}
    public func windowDidChangeActiveState(_ window: Win32Window, isActive: Bool) {}
    public func windowDidReceiveRightClick(_ window: Win32Window, event: MouseEvent) {}
    public func windowDidReceiveDoubleClick(_ window: Win32Window, event: MouseEvent) {}
    public func window(_ window: Win32Window, horizontalScrollAt point: Point, delta: Double) {}
    public func windowDidChangeVisibility(_ window: Win32Window, isVisible: Bool) {}
    public func windowDidChangeSystemSettings(_ window: Win32Window) {}
    public func window(_ window: Win32Window, middleMouseDownAt point: Point) {}
    public func window(_ window: Win32Window, middleMouseUpAt point: Point) {}
    public func window(_ window: Win32Window, imeCompositionStarted placeholder: Bool) {}
    public func window(_ window: Win32Window, imeCompositionString text: String) {}
    public func window(_ window: Win32Window, imeCompositionEnded placeholder: Bool) {}
    public func window(_ window: Win32Window, imeChar character: UInt32) {}
    public func window(_ window: Win32Window, touchBegan points: [Point]) {}
    public func window(_ window: Win32Window, touchMoved points: [Point]) {}
    public func window(_ window: Win32Window, touchEnded points: [Point]) {}
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
    public let titleBarVisibility: WindowTitleBarVisibility

    private var hwnd: HWND?
    private var isTrackingMouseLeave = false
    private var isAnimationTimerRunning = false

    // Size-move tracking
    private var isInSizeMove = false
    private var isInMenuLoop = false

    // Window position tracking
    private var windowPosition = POINT(x: 0, y: 0)

    // Active state tracking
    private var isAppActive = true

    // Visibility tracking
    private var isVisible = false

    // Fullscreen support
    public private(set) var isFullscreen = false
    private var preFullscreenStyle: DWORD = 0
    private var preFullscreenRect = RECT()

    // Monitor refresh rate cache
    private var cachedRefreshRate: UINT = 60
    private var refreshRateDirty = true

    // System appearance sampling
    /// Injectable settings source; defaults to live Win32 sampling. Tests
    /// substitute a fake so the host stays headless.
    public var systemAppearanceProvider: any SystemAppearanceProvider = Win32SystemAppearanceProvider()
    private var cachedSystemAppearance: SystemAppearanceSnapshot?

    // High-resolution timer support
    public var useHighResolutionTimer: Bool = false
    private var highResTimerHandle: HANDLE?
    private var animationTimerIntervalMilliseconds: UINT = 0
    private var animationTimerUsesHighResolution = false
    internal var testScaleFactorOverride: Double?
    internal var testMonitorRefreshRateOverride: UINT? {
        didSet {
            refreshRateDirty = true
        }
    }

    public init(title: String, clientSize: IntSize, titleBarVisibility: WindowTitleBarVisibility = .automatic) {
        self.title = title
        self.clientSize = clientSize
        self.titleBarVisibility = titleBarVisibility
    }

    public var nativeHandle: NativeWindowHandle? {
        let rawHandle: UnsafeMutableRawPointer? = unsafeBitCast(hwnd, to: UnsafeMutableRawPointer?.self)
        return NativeWindowHandle(rawPointer: rawHandle)
    }

    public var scaleFactor: Double {
        if let testScaleFactorOverride {
            return testScaleFactorOverride
        }

        guard let hwnd else {
            return 1.0
        }

        let dpi = GetDpiForWindow(hwnd)
        if dpi == 0 {
            return 1.0
        }

        return Double(dpi) / 96.0
    }

    public var monitorRefreshRate: UINT {
        if refreshRateDirty {
            refreshRateDirty = false
            cachedRefreshRate = queryMonitorRefreshRate()
        }
        return cachedRefreshRate
    }

    /// Latest sampled system appearance (light/dark, high contrast, text
    /// scale, reduce motion). Sampled lazily on first access and re-sampled
    /// after `WM_SETTINGCHANGE` / `WM_SYSCOLORCHANGE`.
    public var systemAppearance: SystemAppearanceSnapshot {
        if let cachedSystemAppearance {
            return cachedSystemAppearance
        }

        let sampled = systemAppearanceProvider.sampleSystemAppearance()
        cachedSystemAppearance = sampled
        return sampled
    }

    /// Drops the cached snapshot so the next `systemAppearance` access
    /// re-samples from the provider. Called from the settings-change message
    /// path; internal so headless tests can drive the same invalidation.
    internal func invalidateSystemAppearanceCache() {
        cachedSystemAppearance = nil
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
        let style: DWORD
        switch titleBarVisibility.kind {
        case .hidden:
            let hiddenStyle = Int32(WS_POPUP) | Int32(WS_THICKFRAME) | Int32(WS_MINIMIZEBOX) | Int32(WS_MAXIMIZEBOX)
            style = DWORD(UInt32(bitPattern: hiddenStyle))
        default:
            style = DWORD(UInt32(bitPattern: Int32(WS_OVERLAPPEDWINDOW)))
        }

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

        // Register for touch input
        if let window = createdWindow {
            RegisterTouchWindow(window, 0)
        }

        // Prime the system appearance snapshot at startup so the first
        // environment build sees current OS settings.
        _ = systemAppearance

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

    public func requestClose() {
        guard let hwnd else {
            PostQuitMessage(0)
            return
        }

        PostMessageW(hwnd, UINT(WM_CLOSE), 0, 0)
    }

    public func setAnimationTimerEnabled(_ enabled: Bool, intervalMilliseconds: UINT = 16) {
        guard hwnd != nil else {
            return
        }

        if enabled {
            let configuration = animationTimerConfiguration(requestedInterval: intervalMilliseconds)
            if isAnimationTimerRunning,
                animationTimerIntervalMilliseconds == configuration.intervalMilliseconds,
                animationTimerUsesHighResolution == configuration.useHighResolution
            {
                return
            }

            stopCurrentAnimationTimer()
            startAnimationTimer(using: configuration)
            isAnimationTimerRunning = true
            return
        }

        guard isAnimationTimerRunning else {
            return
        }

        stopCurrentAnimationTimer()
        isAnimationTimerRunning = false
    }

    public func currentClientSize() -> IntSize {
        return clientSize
    }

    public func toggleFullscreen() {
        guard let hwnd else {
            return
        }

        if isFullscreen {
            // Restore previous window style and position
            SetWindowLongW(hwnd, GWL_STYLE, Int32(bitPattern: preFullscreenStyle))
            SetWindowPos(
                hwnd,
                nil,
                preFullscreenRect.left,
                preFullscreenRect.top,
                preFullscreenRect.right - preFullscreenRect.left,
                preFullscreenRect.bottom - preFullscreenRect.top,
                UINT(SWP_FRAMECHANGED | SWP_NOACTIVATE | SWP_NOZORDER)
            )
            isFullscreen = false
        } else {
            // Save current window style and position
            preFullscreenStyle = DWORD(bitPattern: GetWindowLongW(hwnd, GWL_STYLE))
            GetWindowRect(hwnd, &preFullscreenRect)

            // Get monitor info for the monitor this window is on
            let monitor = MonitorFromWindow(hwnd, DWORD(MONITOR_DEFAULTTONEAREST))
            var monitorInfo = MONITORINFO()
            monitorInfo.cbSize = DWORD(MemoryLayout<MONITORINFO>.size)
            GetMonitorInfoW(monitor, &monitorInfo)

            // Set popup style and cover the monitor
            let popupStyle = Int32(bitPattern: UInt32(WS_POPUP)) | WS_VISIBLE
            SetWindowLongW(hwnd, GWL_STYLE, popupStyle)
            SetWindowPos(
                hwnd,
                nil,
                monitorInfo.rcMonitor.left,
                monitorInfo.rcMonitor.top,
                monitorInfo.rcMonitor.right - monitorInfo.rcMonitor.left,
                monitorInfo.rcMonitor.bottom - monitorInfo.rcMonitor.top,
                UINT(SWP_FRAMECHANGED | SWP_NOACTIVATE | SWP_NOZORDER)
            )
            isFullscreen = true
        }
    }

    // MARK: - Monitor refresh rate

    private func queryMonitorRefreshRate() -> UINT {
        if let testMonitorRefreshRateOverride {
            return testMonitorRefreshRateOverride
        }

        guard let hwnd else {
            return 60
        }

        let monitor = MonitorFromWindow(hwnd, DWORD(MONITOR_DEFAULTTONEAREST))
        var monitorInfoEx = MONITORINFOEXW()
        monitorInfoEx.cbSize = DWORD(MemoryLayout<MONITORINFOEXW>.size)

        guard
            withUnsafeMutablePointer(
                to: &monitorInfoEx,
                {
                    $0.withMemoryRebound(to: MONITORINFO.self, capacity: 1) {
                        GetMonitorInfoW(monitor, $0)
                    }
                })
        else {
            return 60
        }

        var devMode = DEVMODEW()
        devMode.dmSize = WORD(MemoryLayout<DEVMODEW>.size)

        let success = withUnsafeMutablePointer(to: &monitorInfoEx.szDevice.0) { deviceName in
            EnumDisplaySettingsW(deviceName, DWORD(bitPattern: -1), &devMode)
        }

        guard success else {
            return 60
        }

        let rate = devMode.dmDisplayFrequency
        return rate > 0 ? rate : 60
    }

    // MARK: - High-resolution timer

    private func startHighResolutionTimer(intervalMilliseconds: UINT) {
        guard let hwnd else {
            return
        }

        var timerHandle: HANDLE?
        let windowValue = UInt(bitPattern: hwnd)

        let created = CreateTimerQueueTimer(
            &timerHandle,
            nil,
            win32HighResolutionTimerCallback,
            UnsafeMutableRawPointer(bitPattern: windowValue),
            DWORD(intervalMilliseconds),
            DWORD(intervalMilliseconds),
            DWORD(WT_EXECUTEDEFAULT)
        )

        if created {
            highResTimerHandle = timerHandle
        }
    }

    private func stopHighResolutionTimer() {
        guard let timerHandle = highResTimerHandle else {
            return
        }

        DeleteTimerQueueTimer(nil, timerHandle, INVALID_HANDLE_VALUE)
        highResTimerHandle = nil
    }

    private func startAnimationTimer(using configuration: AnimationTimerConfiguration) {
        guard let hwnd else {
            return
        }

        if configuration.useHighResolution {
            startHighResolutionTimer(intervalMilliseconds: configuration.intervalMilliseconds)
        } else {
            SetTimer(hwnd, Self.animationTimerIdentifier, configuration.intervalMilliseconds, nil)
        }

        animationTimerIntervalMilliseconds = configuration.intervalMilliseconds
        animationTimerUsesHighResolution = configuration.useHighResolution
    }

    private func stopCurrentAnimationTimer() {
        guard let hwnd else {
            return
        }

        if animationTimerUsesHighResolution {
            stopHighResolutionTimer()
        } else {
            KillTimer(hwnd, Self.animationTimerIdentifier)
        }

        animationTimerIntervalMilliseconds = 0
        animationTimerUsesHighResolution = false
    }

    private func refreshAnimationTimerIfNeeded() {
        guard isAnimationTimerRunning else {
            return
        }

        stopCurrentAnimationTimer()
        startAnimationTimer(using: animationTimerConfiguration(requestedInterval: animationTimerIntervalMilliseconds))
    }

    private func animationTimerConfiguration(requestedInterval: UINT) -> AnimationTimerConfiguration {
        if isInSizeMove || isInMenuLoop {
            return AnimationTimerConfiguration(
                intervalMilliseconds: UINT(max(1, USER_TIMER_MINIMUM)),
                useHighResolution: false
            )
        }

        return AnimationTimerConfiguration(
            intervalMilliseconds: max(1, requestedInterval),
            useHighResolution: useHighResolutionTimer
        )
    }

    // MARK: - Message handling

    private func handleMessage(hwnd: HWND?, message: UINT, wParam: WPARAM, lParam: LPARAM) -> LRESULT {
        switch message {
        case UINT(WM_ERASEBKGND):
            return 1

        case UINT(WM_SIZE):
            updateCachedClientSize()
            delegate?.window(self, didResizeTo: clientSize)
            return 0

        case UINT(WM_DPICHANGED):
            if let suggestedRect = UnsafeMutableRawPointer(bitPattern: Int(lParam))?.assumingMemoryBound(to: RECT.self)
            {
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

            updateCachedClientSize()
            delegate?.window(self, didResizeTo: clientSize)
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
            let point = Self.clientPoint(fromScreenLParam: lParam, hwnd: hwnd)
            let modifiers = Self.currentKeyboardModifiers()
            if modifiers.contains(.shift) {
                delegate?.window(
                    self,
                    horizontalScrollAt: point,
                    delta: Self.mouseWheelDelta(from: wParam, unit: .characters)
                )
            } else {
                delegate?.window(
                    self,
                    mouseWheelAt: point,
                    delta: Self.mouseWheelDelta(from: wParam, unit: .lines)
                )
            }
            return 0

        case UINT(WM_MOUSEHWHEEL):
            delegate?.window(
                self,
                horizontalScrollAt: Self.clientPoint(fromScreenLParam: lParam, hwnd: hwnd),
                delta: Self.mouseWheelDelta(from: wParam, unit: .characters)
            )
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

        case UINT(WM_LBUTTONDBLCLK):
            let point = Self.point(from: lParam)
            let event = MouseEvent(button: .left, position: point, clickCount: 2)
            delegate?.windowDidReceiveDoubleClick(self, event: event)
            return 0

        case UINT(WM_RBUTTONDOWN):
            SetCapture(hwnd)
            let point = Self.point(from: lParam)
            let event = MouseEvent(button: .right, position: point)
            delegate?.windowDidReceiveRightClick(self, event: event)
            return 0

        case UINT(WM_RBUTTONUP):
            ReleaseCapture()
            return 0

        case UINT(WM_MBUTTONDOWN):
            SetCapture(hwnd)
            delegate?.window(self, middleMouseDownAt: Self.point(from: lParam))
            return 0

        case UINT(WM_MBUTTONUP):
            ReleaseCapture()
            delegate?.window(self, middleMouseUpAt: Self.point(from: lParam))
            return 0

        case UINT(WM_KEYDOWN):
            delegate?.window(self, keyDown: Self.keyboardEvent(from: wParam, lParam: lParam))
            return 0

        case UINT(WM_KILLFOCUS):
            delegate?.windowDidLoseKeyboardFocus(self)
            return 0

        // Window lifecycle and state messages

        case UINT(WM_DISPLAYCHANGE):
            refreshRateDirty = true
            delegate?.windowDidChangeDisplay(self)
            return 0

        case UINT(WM_ENTERSIZEMOVE):
            isInSizeMove = true
            refreshAnimationTimerIfNeeded()
            return 0

        case UINT(WM_EXITSIZEMOVE):
            isInSizeMove = false
            refreshAnimationTimerIfNeeded()
            updateCachedClientSize()
            delegate?.window(self, didResizeTo: clientSize)
            return 0

        case UINT(WM_ENTERMENULOOP):
            isInMenuLoop = true
            refreshAnimationTimerIfNeeded()
            return 0

        case UINT(WM_EXITMENULOOP):
            isInMenuLoop = false
            refreshAnimationTimerIfNeeded()
            return 0

        case UINT(WM_MOVE):
            let packed = UInt32(truncatingIfNeeded: lParam)
            windowPosition.x = LONG(Int16(bitPattern: UInt16(packed & 0xFFFF)))
            windowPosition.y = LONG(Int16(bitPattern: UInt16((packed >> 16) & 0xFFFF)))
            // Invalidate refresh rate cache in case the window moved to a different monitor
            refreshRateDirty = true
            delegate?.windowDidChangeDisplay(self)
            return 0

        case UINT(WM_ACTIVATEAPP):
            isAppActive = wParam != 0
            delegate?.windowDidChangeActiveState(self, isActive: isAppActive)
            return 0

        case UINT(WM_SHOWWINDOW):
            isVisible = wParam != 0
            delegate?.windowDidChangeVisibility(self, isVisible: isVisible)
            return 0

        case UINT(WM_SETTINGCHANGE):
            invalidateSystemAppearanceCache()
            delegate?.windowDidChangeSystemSettings(self)
            return 0

        case UINT(WM_SYSCOLORCHANGE):
            // High-contrast theme switches broadcast WM_SYSCOLORCHANGE;
            // route them through the same settings invalidation path.
            invalidateSystemAppearanceCache()
            delegate?.windowDidChangeSystemSettings(self)
            return 0

        case UINT(WM_SETCURSOR):
            let hitTest = UInt16(UInt(truncatingIfNeeded: lParam) & 0xFFFF)
            if hitTest == UINT16(HTCLIENT) {
                SetCursor(LoadCursorW(nil, UnsafePointer<WCHAR>(bitPattern: 32512)))
                return 1
            }
            return DefWindowProcW(hwnd, message, wParam, lParam)

        // IME composition messages

        case UINT(WM_IME_STARTCOMPOSITION):
            delegate?.window(self, imeCompositionStarted: true)
            return DefWindowProcW(hwnd, message, wParam, lParam)

        case UINT(WM_IME_COMPOSITION):
            if let compositionString = Self.extractIMECompositionString(hwnd: hwnd, lParam: lParam) {
                delegate?.window(self, imeCompositionString: compositionString)
            }
            return DefWindowProcW(hwnd, message, wParam, lParam)

        case UINT(WM_IME_ENDCOMPOSITION):
            delegate?.window(self, imeCompositionEnded: true)
            return DefWindowProcW(hwnd, message, wParam, lParam)

        case UINT(WM_IME_CHAR):
            delegate?.window(self, imeChar: UInt32(truncatingIfNeeded: wParam))
            return 0

        // Touch input

        case UINT(WM_TOUCH):
            handleTouchMessage(hwnd: hwnd, wParam: wParam, lParam: lParam)
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

    // MARK: - Cached client size

    private func updateCachedClientSize() {
        guard let hwnd else {
            return
        }

        var rect = RECT()
        GetClientRect(hwnd, &rect)
        clientSize = IntSize(width: Int32(rect.right - rect.left), height: Int32(rect.bottom - rect.top))
    }

    // MARK: - IME helpers

    private static func extractIMECompositionString(hwnd: HWND?, lParam: LPARAM) -> String? {
        guard let hwnd else { return nil }

        let hasResult = (UInt(truncatingIfNeeded: lParam) & UInt(GCS_RESULTSTR)) != 0
        let hasComposition = (UInt(truncatingIfNeeded: lParam) & UInt(GCS_COMPSTR)) != 0
        let flag: DWORD = hasResult ? DWORD(GCS_RESULTSTR) : (hasComposition ? DWORD(GCS_COMPSTR) : 0)

        guard flag != 0 else { return nil }

        let imc = ImmGetContext(hwnd)
        guard let imc else { return nil }
        defer { ImmReleaseContext(hwnd, imc) }

        let byteCount = ImmGetCompositionStringW(imc, flag, nil, 0)
        guard byteCount > 0 else { return nil }

        let charCount = Int(byteCount) / MemoryLayout<WCHAR>.size
        var buffer = [WCHAR](repeating: 0, count: charCount + 1)
        ImmGetCompositionStringW(imc, flag, &buffer, DWORD(byteCount))

        return String(decoding: buffer.prefix(charCount), as: UTF16.self)
    }

    // MARK: - Touch helpers

    private func handleTouchMessage(hwnd: HWND?, wParam: WPARAM, lParam: LPARAM) {
        let inputCount = UInt16(UInt(truncatingIfNeeded: wParam) & 0xFFFF)
        guard inputCount > 0 else { return }

        let touchHandle = HTOUCHINPUT(bitPattern: Int(lParam))
        var inputs = [TOUCHINPUT](repeating: TOUCHINPUT(), count: Int(inputCount))

        guard GetTouchInputInfo(touchHandle, UINT(inputCount), &inputs, Int32(MemoryLayout<TOUCHINPUT>.size)) else {
            return
        }
        defer { CloseTouchInputHandle(touchHandle) }

        var beganPoints: [Point] = []
        var movedPoints: [Point] = []
        var endedPoints: [Point] = []

        for input in inputs {
            var screenPoint = POINT(x: LONG(input.x / 100), y: LONG(input.y / 100))
            ScreenToClient(hwnd, &screenPoint)
            let point = Point(x: Double(screenPoint.x), y: Double(screenPoint.y))

            if (input.dwFlags & DWORD(TOUCHEVENTF_DOWN)) != 0 {
                beganPoints.append(point)
            } else if (input.dwFlags & DWORD(TOUCHEVENTF_MOVE)) != 0 {
                movedPoints.append(point)
            } else if (input.dwFlags & DWORD(TOUCHEVENTF_UP)) != 0 {
                endedPoints.append(point)
            }
        }

        if !beganPoints.isEmpty {
            delegate?.window(self, touchBegan: beganPoints)
        }
        if !movedPoints.isEmpty {
            delegate?.window(self, touchMoved: movedPoints)
        }
        if !endedPoints.isEmpty {
            delegate?.window(self, touchEnded: endedPoints)
        }
    }

    // MARK: - Window class registration

    private static func registerWindowClass() throws {
        if didRegisterClass {
            return
        }

        guard let instance = GetModuleHandleW(nil) else {
            throw lastError(for: "GetModuleHandleW")
        }

        let cursor = LoadCursorW(nil, UnsafePointer<WCHAR>(bitPattern: 32512))
        let backgroundBrush = GetStockObject(Int32(BLACK_BRUSH))

        try className.withWideChars { className in
            var windowClass = WNDCLASSEXW()
            windowClass.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
            windowClass.style = UINT(CS_HREDRAW | CS_VREDRAW | CS_DBLCLKS)
            windowClass.lpfnWndProc = windowProc
            windowClass.hInstance = instance
            windowClass.hCursor = cursor
            windowClass.hbrBackground = unsafeBitCast(backgroundBrush, to: HBRUSH?.self)
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

    private static func mouseWheelDelta(from wParam: WPARAM, unit: MouseWheelUnit) -> Double {
        let highWord = UInt16((UInt(truncatingIfNeeded: wParam) >> 16) & 0xFFFF)
        let signedDelta = Int16(bitPattern: highWord)
        return (Double(signedDelta) / Double(WHEEL_DELTA)) * Double(systemWheelUnitCount(for: unit))
    }

    private static func systemWheelUnitCount(for unit: MouseWheelUnit) -> UINT {
        var value: UINT = unit.defaultCount
        let action: UINT = {
            switch unit {
            case .lines:
                return UINT(SPI_GETWHEELSCROLLLINES)
            case .characters:
                return UINT(SPI_GETWHEELSCROLLCHARS)
            }
        }()

        let succeeded = SystemParametersInfoW(action, 0, &value, 0)
        guard succeeded else {
            return unit.defaultCount
        }

        if value == Self.wheelPageScrollValue {
            return unit.defaultCount
        }

        return max(1, value)
    }

    public static func currentTimestampSeconds() -> Double {
        Double(GetTickCount64()) / 1000.0
    }

    private static func keyboardEvent(from wParam: WPARAM, lParam: LPARAM) -> KeyboardEvent {
        KeyboardEvent(
            keyCode: UInt32(truncatingIfNeeded: wParam),
            modifiers: currentKeyboardModifiers(),
            isRepeat: (UInt(truncatingIfNeeded: lParam) & 0x4000_0000) != 0
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
    private static let wheelPageScrollValue = UINT.max

    private struct AnimationTimerConfiguration {
        var intervalMilliseconds: UINT
        var useHighResolution: Bool
    }

    private enum MouseWheelUnit {
        case lines
        case characters

        var defaultCount: UINT {
            switch self {
            case .lines:
                return 3
            case .characters:
                return 3
            }
        }
    }

    private static let windowProc: WNDPROC = {
        (hwnd: HWND?, message: UINT, wParam: WPARAM, lParam: LPARAM) -> LRESULT in
        if message == UINT(WM_NCCREATE) {
            let createStructure = UnsafeMutableRawPointer(bitPattern: Int(lParam))?.assumingMemoryBound(
                to: CREATESTRUCTW.self)
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

// MARK: - System appearance sampling

/// Value snapshot of OS-level appearance settings that drive environment
/// appearance (color scheme, high contrast, text scale, reduce motion).
/// Sampled through `SystemAppearanceProvider` on `Win32Window` and mapped
/// into `EnvironmentValues` by the WinSwiftUI layer.
public struct SystemAppearanceSnapshot: Sendable, Equatable {
    /// Light/dark preference. `nil` when the OS preference cannot be
    /// determined; callers keep their existing default in that case.
    public enum ColorSchemePreference: Sendable, Equatable {
        case light
        case dark
    }

    public var colorSchemePreference: ColorSchemePreference?
    public var isHighContrastEnabled: Bool
    /// Text scale as a multiplier (1.0 == 100%). `nil` when unavailable.
    public var textScaleFactor: Double?
    /// Reduced-motion preference. `nil` when unavailable.
    public var prefersReducedMotion: Bool?

    public init(
        colorSchemePreference: ColorSchemePreference? = nil,
        isHighContrastEnabled: Bool = false,
        textScaleFactor: Double? = nil,
        prefersReducedMotion: Bool? = nil
    ) {
        self.colorSchemePreference = colorSchemePreference
        self.isHighContrastEnabled = isHighContrastEnabled
        self.textScaleFactor = textScaleFactor
        self.prefersReducedMotion = prefersReducedMotion
    }

    /// Neutral snapshot used when no system information is available.
    public static let unavailable = SystemAppearanceSnapshot()
}

/// Source of `SystemAppearanceSnapshot` values. The production default is
/// `Win32SystemAppearanceProvider`; tests inject fakes so the host stays
/// headless (no live OS theme flips required).
public protocol SystemAppearanceProvider: Sendable {
    func sampleSystemAppearance() -> SystemAppearanceSnapshot
}

/// Live Win32 sampler: `SystemParametersInfoW` for high contrast and
/// client-area animation, registry reads for the app light/dark preference
/// and text scale. Every field degrades to `nil`/`false` when the
/// underlying call fails.
public struct Win32SystemAppearanceProvider: SystemAppearanceProvider {
    public init() {}

    public func sampleSystemAppearance() -> SystemAppearanceSnapshot {
        SystemAppearanceSnapshot(
            colorSchemePreference: Self.sampleColorSchemePreference(),
            isHighContrastEnabled: Self.sampleHighContrastEnabled(),
            textScaleFactor: Self.sampleTextScaleFactor(),
            prefersReducedMotion: Self.samplePrefersReducedMotion()
        )
    }

    private static func sampleHighContrastEnabled() -> Bool {
        var highContrast = HIGHCONTRASTW()
        highContrast.cbSize = UINT(MemoryLayout<HIGHCONTRASTW>.size)
        guard SystemParametersInfoW(UINT(SPI_GETHIGHCONTRAST), highContrast.cbSize, &highContrast, 0) else {
            return false
        }

        return (highContrast.dwFlags & DWORD(HCF_HIGHCONTRASTON)) != 0
    }

    private static func samplePrefersReducedMotion() -> Bool? {
        // Windows BOOL is a 32-bit integer; Swift's WinSDK does not export
        // the BOOL alias, so use Int32 for the raw storage.
        var animationEnabled: Int32 = 0
        guard SystemParametersInfoW(UINT(SPI_GETCLIENTAREAANIMATION), 0, &animationEnabled, 0) else {
            return nil
        }

        // Client-area animation off is the closest Win32-exposed proxy for
        // the "reduce motion" accessibility preference.
        return animationEnabled == 0
    }

    private static func sampleColorSchemePreference() -> SystemAppearanceSnapshot.ColorSchemePreference? {
        guard let appsUseLightTheme = readCurrentUserDWORD(
            subKey: #"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"#,
            valueName: "AppsUseLightTheme"
        ) else {
            return nil
        }

        return appsUseLightTheme == 0 ? .dark : .light
    }

    private static func sampleTextScaleFactor() -> Double? {
        guard let percent = readCurrentUserDWORD(
            subKey: #"Software\Microsoft\Accessibility"#,
            valueName: "TextScaleFactor"
        ), percent > 0 else {
            return nil
        }

        return Double(percent) / 100.0
    }

    private static func readCurrentUserDWORD(subKey: String, valueName: String) -> DWORD? {
        var value: DWORD = 0
        var size = DWORD(MemoryLayout<DWORD>.size)
        let status = subKey.withWideChars { subKeyPointer in
            valueName.withWideChars { valuePointer in
                RegGetValueW(
                    HKEY_CURRENT_USER,
                    subKeyPointer,
                    valuePointer,
                    DWORD(RRF_RT_REG_DWORD),
                    nil,
                    &value,
                    &size
                )
            }
        }

        guard status == ERROR_SUCCESS else {
            return nil
        }

        return value
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
        return result >= 0 || result == HRESULT(bitPattern: 0x8007_0005)
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
extension String {
    fileprivate func withWideChars<Result>(_ body: (UnsafePointer<WCHAR>) throws -> Result) rethrows -> Result {
        var characters = Array(utf16)
        characters.append(0)

        return try characters.withUnsafeBufferPointer { buffer in
            try body(UnsafePointer(buffer.baseAddress!))
        }
    }
}
