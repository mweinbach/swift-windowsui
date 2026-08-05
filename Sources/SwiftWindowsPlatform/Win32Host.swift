import SwiftWindowsCore
import Synchronization
import WinSDK

/// Callback context for the high-resolution animation timer.
///
/// `CreateTimerQueueTimer` fires on an arbitrary thread-pool thread while the
/// window consumes on the UI thread, and posted `WM_TIMER` messages are *not*
/// coalesced the way `SetTimer`'s synthesized ones are. Without a gate a
/// frame that takes longer than the timer period grows the message queue one
/// message per tick, and the app then works through a long tail of stale
/// ticks. The gate keeps at most one un-consumed post outstanding: the
/// callback claims it, the `WM_TIMER` handler releases it.
final class Win32AnimationTimerGate: Sendable {
    let windowHandleValue: UInt
    let isPostOutstanding = Atomic<Bool>(false)

    init(windowHandleValue: UInt) {
        self.windowHandleValue = windowHandleValue
    }

    /// Marks the outstanding post as consumed. Called from the UI thread when
    /// the window dequeues the `WM_TIMER` the callback posted.
    func consumePost() {
        isPostOutstanding.store(false, ordering: .releasing)
    }
}

private func win32HighResolutionTimerCallback(_ param: UnsafeMutableRawPointer?, _: UInt8) {
    guard let param else {
        return
    }

    let gate = Unmanaged<Win32AnimationTimerGate>.fromOpaque(param).takeUnretainedValue()
    let (claimed, _) = gate.isPostOutstanding.compareExchange(
        expected: false,
        desired: true,
        ordering: .acquiringAndReleasing
    )
    guard claimed else {
        // The previous tick is still queued; skipping this one is what bounds
        // the queue. The next tick after the UI thread catches up posts again.
        return
    }

    let hwndValue = HWND(bitPattern: Int(bitPattern: gate.windowHandleValue))
    if !PostMessageW(hwndValue, UINT(WM_TIMER), WPARAM(1), 0) {
        // The queue refused the message (full, or the window is gone). Release
        // the gate so the next tick is not suppressed by a post that never
        // arrived.
        gate.consumePost()
    }
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
    /// The wheel event with its provenance. `delta` is in lines; `source`
    /// separates a click-wheel detent -- which must not glide -- from a
    /// precision-touchpad gesture, which must. Defaults to forwarding to the
    /// three-argument form so existing conformances keep working.
    func window(_ window: Win32Window, mouseWheelAt point: Point, delta: Double, source: ScrollInputSource)
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
    func window(
        _ window: Win32Window, horizontalScrollAt point: Point, delta: Double, source: ScrollInputSource)
    func windowDidChangeVisibility(_ window: Win32Window, isVisible: Bool)
    func windowDidChangeSystemSettings(_ window: Win32Window)
    func window(_ window: Win32Window, middleMouseDownAt point: Point)
    func window(_ window: Win32Window, middleMouseUpAt point: Point)
    /// IME composition events (started / marked-text update / committed
    /// result / ended). Only delivered while an IME is actively composing.
    func window(_ window: Win32Window, imeComposition event: IMECompositionEvent)
    /// Caret rectangle of the focused text input in logical root
    /// coordinates, used to position the OS IME candidate/composition
    /// window. Return `nil` when no text input is focused.
    func windowTextInputCaretRect(_ window: Win32Window) -> Rect?
    func window(_ window: Win32Window, touchBegan points: [Point])
    func window(_ window: Win32Window, touchMoved points: [Point])
    func window(_ window: Win32Window, touchEnded points: [Point])
    /// Files dropped onto the window from the shell (WM_DROPFILES).
    func window(_ window: Win32Window, didReceiveFileDrop payload: FileDropPayload)
}
extension WindowDelegate {
    public func windowDidCreate(_ window: Win32Window) {}
    public func window(_ window: Win32Window, didResizeTo size: IntSize) {}
    public func windowNeedsDisplay(_ window: Win32Window) {}
    public func window(_ window: Win32Window, animationFrameAt timestamp: Double) {}
    public func window(_ window: Win32Window, pointerMovedTo point: Point) {}
    public func windowPointerDidLeave(_ window: Win32Window) {}
    public func window(_ window: Win32Window, mouseWheelAt point: Point, delta: Double) {}
    public func window(
        _ window: Win32Window, mouseWheelAt point: Point, delta: Double, source: ScrollInputSource
    ) {
        self.window(window, mouseWheelAt: point, delta: delta)
    }
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
    public func window(
        _ window: Win32Window, horizontalScrollAt point: Point, delta: Double, source: ScrollInputSource
    ) {
        self.window(window, horizontalScrollAt: point, delta: delta)
    }
    public func windowDidChangeVisibility(_ window: Win32Window, isVisible: Bool) {}
    public func windowDidChangeSystemSettings(_ window: Win32Window) {}
    public func window(_ window: Win32Window, middleMouseDownAt point: Point) {}
    public func window(_ window: Win32Window, middleMouseUpAt point: Point) {}
    public func window(_ window: Win32Window, imeComposition event: IMECompositionEvent) {}
    public func windowTextInputCaretRect(_ window: Win32Window) -> Rect? { nil }
    public func window(_ window: Win32Window, touchBegan points: [Point]) {}
    public func window(_ window: Win32Window, touchMoved points: [Point]) {}
    public func window(_ window: Win32Window, touchEnded points: [Point]) {}
    public func window(_ window: Win32Window, didReceiveFileDrop payload: FileDropPayload) {}
}
/// The window traits the scene layer asks for and the Win32 host can actually
/// enforce.
///
/// `WindowGroupConfiguration` has carried `minSize`, `maxSize`, `idealSize`,
/// `defaultPosition`, `resizability` and `windowLevel` since the scene
/// modifiers were written, and none of them ever reached an HWND: there was no
/// `WM_GETMINMAXINFO` handler and no `SetWindowPos` for placement or level, so
/// `.windowResizability(.contentSize)` and `.windowMinSize(…)` were silent
/// no-ops. This is the renderer-neutral subset the host can honour; the
/// translation from SwiftUI-shaped values lives in `WinSwiftUI`, and the
/// enforcement lives here.
public struct Win32WindowConfiguration: Equatable, Sendable {
    public enum Resizability: Sendable, Equatable {
        case resizable
        /// The window is pinned to its content size: no sizing border, no
        /// maximize box, and `WM_GETMINMAXINFO` reports one track size.
        case fixedSize
    }

    /// Smallest client size the user may drag the window down to, in logical
    /// points.
    public var minimumClientSize: IntSize?
    /// Largest client size the user may drag the window up to, in logical
    /// points.
    public var maximumClientSize: IntSize?
    /// Where to place the window inside its monitor's work area, normalized to
    /// 0…1 on each axis. `nil` leaves placement to Windows (`CW_USEDEFAULT`).
    public var normalizedPosition: Point?
    public var resizability: Resizability
    /// Whether the window sits above ordinary windows (`HWND_TOPMOST`).
    public var isAlwaysOnTop: Bool

    public init(
        minimumClientSize: IntSize? = nil,
        maximumClientSize: IntSize? = nil,
        normalizedPosition: Point? = nil,
        resizability: Resizability = .resizable,
        isAlwaysOnTop: Bool = false
    ) {
        self.minimumClientSize = minimumClientSize
        self.maximumClientSize = maximumClientSize
        self.normalizedPosition = normalizedPosition
        self.resizability = resizability
        self.isAlwaysOnTop = isAlwaysOnTop
    }

    public static let `default` = Win32WindowConfiguration()
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

    /// Optional accessibility (UI Automation) provider consulted on
    /// `WM_GETOBJECT`. Nil by default; assign a provider (typically a
    /// `UIAProviderBridge`) to expose the window's content to assistive
    /// technology.
    public var accessibilityProvider: (any Win32WindowAccessibilityProvider)?

    /// When true (the default), `WM_DESTROY` posts `PostQuitMessage`,
    /// preserving the historical single-window quit behavior. Multi-window
    /// coordinators set this to false and post the quit message themselves
    /// once the last managed window has closed.
    public var postsQuitMessageOnDestroy = true

    public let title: String
    public private(set) var clientSize: IntSize
    /// Whether the last `WM_SIZE` reported the window minimized. `clientSize`
    /// is 0×0 while this is true — the cache is not frozen at the pre-minimize
    /// rect — so callers that need a paintable surface can tell the two apart.
    public private(set) var isMinimized = false
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
    /// Identity of the monitor the window was last seen on. `WM_MOVE` only
    /// invalidates the refresh rate when this changes.
    private var cachedMonitorIdentity: UInt?
    private var lastRefreshRateQueryTime: Double = -.greatestFiniteMagnitude
    /// Number of display-mode enumerations this window has performed.
    /// Internal so a headless test can prove a drag does not run one per
    /// `WM_MOVE`.
    internal private(set) var refreshRateQueryCount = 0
    /// Injectable clock for the refresh-rate rate limiter.
    internal var refreshRateQueryClock: @MainActor () -> Double = { Win32Window.currentTimestampSeconds() }
    private static let refreshRateQueryMinimumInterval: Double = 0.25
    internal var testMonitorIdentityOverride: UInt?

    // System appearance sampling
    /// Injectable settings source; defaults to live Win32 sampling. Tests
    /// substitute a fake so the host stays headless.
    public var systemAppearanceProvider: any SystemAppearanceProvider = Win32SystemAppearanceProvider()
    private var cachedSystemAppearance: SystemAppearanceSnapshot?

    // IME composition context
    /// Injectable IMM32 seam; defaults to the live IMM32 API. Tests
    /// substitute a fake so composition translation stays headless.
    public var imeCompositionContextProvider: any IMECompositionContextProvider = Win32IMECompositionContextProvider()

    // High-resolution timer support
    public var useHighResolutionTimer: Bool = false
    private var highResTimerHandle: HANDLE?
    private var highResTimerGate: Win32AnimationTimerGate?
    private var animationTimerIntervalMilliseconds: UINT = 0
    private var animationTimerUsesHighResolution = false
    /// The interval the *caller* asked for, kept separately from the interval
    /// of the timer that is currently installed. `stopCurrentAnimationTimer`
    /// zeroes the installed interval, so a restart that read it back — which
    /// is what `refreshAnimationTimerIfNeeded` used to do — resurrected the
    /// timer at `max(1, 0) == 1` ms after every size/move and menu loop.
    private var requestedAnimationTimerIntervalMilliseconds: UINT = 16
    /// Sticky once `CreateTimerQueueTimer` has failed: the thread pool is not
    /// going to become available mid-session, and a per-frame retry would
    /// trade a silent freeze for a silent stall. The coalescing `SetTimer`
    /// path drives frames from then on.
    private var isHighResolutionTimerUnavailable = false
    /// Whether this window still owns the `+1` its `GWLP_USERDATA` self
    /// reference took at creation. Released exactly once, in `WM_NCDESTROY`.
    private var ownsRetainedSelfReference = false
    internal var testScaleFactorOverride: Double?
    internal var testMonitorRefreshRateOverride: UINT? {
        didSet {
            // Stands in for a genuine display-mode change, which is not the
            // spam source the rate limiter exists for.
            invalidateRefreshRate(force: true)
        }
    }

    /// The client size the caller asked for, in *logical points*. `clientSize`
    /// tracks the OS and is in physical pixels from the first `WM_SIZE`, so
    /// the requested size has to be kept separately: the min/max track sizes
    /// and the fixed-size pin are all expressed against it.
    public let requestedLogicalClientSize: IntSize
    public let configuration: Win32WindowConfiguration

    public init(
        title: String,
        clientSize: IntSize,
        titleBarVisibility: WindowTitleBarVisibility = .automatic,
        configuration: Win32WindowConfiguration = .default
    ) {
        self.title = title
        self.clientSize = clientSize
        self.requestedLogicalClientSize = clientSize
        self.titleBarVisibility = titleBarVisibility
        self.configuration = configuration
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

    /// The single scale every consumer of this window must agree on.
    ///
    /// The raw `GetDpiForWindow` value can legitimately be below 1.0 in remote
    /// and virtual-display sessions, and the layer above used to clamp it in
    /// one place (the logical root size) and not in the others (hit testing,
    /// the IME caret rect, `clientRectToScreen`). A 0.75 session then laid out
    /// an 800×600 root and converted a click at physical (400, 300) to logical
    /// (533, 400): every hit test, hover, drag and caret was off by a third
    /// with nothing crashing. One rule, one place.
    public var effectiveScaleFactor: Double {
        Self.effectiveScaleFactor(for: scaleFactor)
    }

    /// The clamp itself, so the layer above applies exactly this rule to the
    /// scale carried on a `SurfaceDescriptor`.
    public static func effectiveScaleFactor(for rawScaleFactor: Double) -> Double {
        guard rawScaleFactor.isFinite, rawScaleFactor > 0 else {
            return 1.0
        }

        return max(rawScaleFactor, 1.0)
    }

    /// Cached monitor refresh rate, re-queried only when the window's monitor
    /// actually changed and at most once per
    /// ``refreshRateQueryMinimumInterval``.
    ///
    /// `WM_MOVE` arrives at mouse-report rate (125–1000 Hz on a gaming mouse)
    /// and used to mark this dirty unconditionally, so every drag ran a
    /// `MonitorFromWindow` + `GetMonitorInfoW` + `EnumDisplaySettingsW`
    /// driver round-trip per message on the UI thread, inside the modal move
    /// loop.
    public var monitorRefreshRate: UINT {
        guard refreshRateDirty else {
            return cachedRefreshRate
        }

        let now = refreshRateQueryClock()
        guard now - lastRefreshRateQueryTime >= Self.refreshRateQueryMinimumInterval else {
            // Still dirty: the next access past the rate limit re-queries.
            return cachedRefreshRate
        }

        refreshRateDirty = false
        lastRefreshRateQueryTime = now
        refreshRateQueryCount &+= 1
        cachedRefreshRate = queryMonitorRefreshRate()
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

    /// Re-samples the appearance and reports whether anything the app can see
    /// actually changed. The snapshot has been `Equatable` all along; nothing
    /// compared it, so every broadcast was a full reload.
    @discardableResult
    internal func refreshSystemAppearanceIfChanged() -> Bool {
        let previous = cachedSystemAppearance
        cachedSystemAppearance = nil
        return systemAppearance != previous
    }

    /// Whether a `WM_SETTINGCHANGE` broadcast reaches the delegate on its own
    /// or only when the sampled appearance actually moved.
    internal enum SettingChangeDelivery: Equatable {
        /// Fonts, non-client metrics, locale, and the theme/accessibility
        /// broadcasts: forwarded whether or not `SystemAppearanceSnapshot`
        /// changed. The snapshot carries four fields; these broadcasts change
        /// things the app draws from that the snapshot does not carry, and
        /// `ImmersiveColorSet` in particular arrives *before* the theme
        /// registry value it announces is guaranteed readable — gating it on a
        /// re-sample dropped real dark-mode switches on the floor.
        case unconditional
        /// Everything else: the environment-variable, policy and per-app
        /// broadcasts any process on the machine can raise at any rate.
        /// Forwarding those tore down and re-registered every observed-object
        /// token, rebuilt the whole tree and raised a UIA structure change —
        /// which makes screen readers re-announce — for settings the app does
        /// not read.
        case whenAppearanceChanged
    }

    /// `SystemParametersInfo` actions whose broadcast is always delivered.
    private static let unconditionalSettingChangeActions: Set<WPARAM> = [
        WPARAM(SPI_SETNONCLIENTMETRICS),
        WPARAM(SPI_SETICONTITLELOGFONT),
        WPARAM(SPI_SETICONMETRICS),
        WPARAM(SPI_SETHIGHCONTRAST),
        WPARAM(SPI_SETCLIENTAREAANIMATION),
        WPARAM(SPI_SETFONTSMOOTHING),
        WPARAM(SPI_SETFONTSMOOTHINGTYPE),
        WPARAM(SPI_SETFONTSMOOTHINGCONTRAST),
    ]

    /// `lParam` section names whose broadcast is always delivered, lowercased
    /// because senders are not consistent about case.
    private static let unconditionalSettingChangeSections: Set<String> = [
        "immersivecolorset",
        "windowsthemeelement",
        "intl",
    ]

    /// Classification only — no sampling, no delegate call — so the routing
    /// table is testable without a live broadcast.
    internal static func settingChangeDelivery(wParam: WPARAM, section: String?) -> SettingChangeDelivery {
        if unconditionalSettingChangeActions.contains(wParam) {
            return .unconditional
        }

        if let section, unconditionalSettingChangeSections.contains(section.lowercased()) {
            return .unconditional
        }

        return .whenAppearanceChanged
    }

    /// Re-samples the appearance and forwards the broadcast when either the
    /// snapshot moved or the broadcast is one of the unconditional kinds.
    /// Returns whether the delegate was called; internal so a headless test can
    /// drive the same routing the wndproc does.
    @discardableResult
    internal func routeSettingChange(wParam: WPARAM, section: String?) -> Bool {
        let appearanceChanged = refreshSystemAppearanceIfChanged()
        guard appearanceChanged || Self.settingChangeDelivery(wParam: wParam, section: section) == .unconditional
        else {
            return false
        }

        delegate?.windowDidChangeSystemSettings(self)
        return true
    }

    /// `WM_SYSCOLORCHANGE` is rare and carries no payload to filter on, and
    /// the system colour palette is not in the snapshot at all — so this stays
    /// the cheap unconditional path it always was, minus the stale cache.
    internal func routeSystemColorChange() {
        refreshSystemAppearanceIfChanged()
        delegate?.windowDidChangeSystemSettings(self)
    }

    /// `WM_SETTINGCHANGE`'s `lParam` is either 0 or a pointer to a
    /// null-terminated wide string naming the changed section.
    ///
    /// Windows marshals that string into the receiving process only for the
    /// `SendMessage` family; `PostMessage(HWND_BROADCAST, WM_SETTINGCHANGE,
    /// 0, anything)` — which any process on the machine may do — arrives with
    /// `lParam` exactly as the sender wrote it. Bounding the *length* of the
    /// scan never made an invalid *base* safe: `pointer[0]` is the read that
    /// faults, on the UI thread, and Swift has no structured exception
    /// handling to catch it.
    ///
    /// So the address is checked before it is read. A `wParam` allow-list is
    /// not the gate here and would be the wrong one: the sections this host
    /// actually keys on (`ImmersiveColorSet`, `WindowsThemeElement`, `intl`)
    /// all arrive with `wParam == 0`, so allow-listing `wParam` would drop
    /// the dark-mode switch this routing exists to catch while still leaving
    /// the forgeable `wParam == 0` case dereferencing a raw address. What
    /// makes the read safe is `readableUnitCount`, and an unreadable `lParam`
    /// classifies as "no section" — a case the routing table already answers.
    internal static func settingChangeSection(_ lParam: LPARAM) -> String? {
        guard lParam != 0 else {
            return nil
        }

        let address = UInt(bitPattern: Int(lParam))
        // A real `LPCWSTR` is `WCHAR`-aligned; an unaligned base is by
        // definition not one, and an unaligned load is undefined behaviour
        // before it is ever a fault.
        guard address % UInt(MemoryLayout<WCHAR>.alignment) == 0 else {
            return nil
        }

        let readableUnits = readableUnitCount(from: address, limit: maximumSettingChangeSectionLength)
        guard readableUnits > 0, let pointer = UnsafePointer<WCHAR>(bitPattern: address) else {
            return nil
        }

        var units: [UTF16.CodeUnit] = []
        units.reserveCapacity(readableUnits)
        for index in 0..<readableUnits {
            let unit = pointer[index]
            if unit == 0 {
                return String(decoding: units, as: UTF16.self)
            }
            units.append(unit)
        }

        return nil
    }

    /// How many `WCHAR`s starting at `address` this process can read without
    /// faulting, capped at `limit`.
    ///
    /// `VirtualQuery` rather than `IsBadReadPtr`: the latter probes by
    /// *reading*, which trips the very guard pages it claims to test for and
    /// permanently breaks the thread's stack growth. `VirtualQuery` reports
    /// the region without touching it, and the walk continues into adjacent
    /// regions so a name that straddles a page boundary still resolves while
    /// one that runs off the end of a committed region stops at it. Anything
    /// not committed, not readable, or guarded ends the span.
    ///
    /// Internal so a headless test can point it at reserved-but-uncommitted
    /// and `PAGE_NOACCESS` pages without a live broadcast.
    internal static func readableUnitCount(from address: UInt, limit: Int) -> Int {
        let unitSize = UInt(MemoryLayout<WCHAR>.size)
        guard address != 0, limit > 0 else {
            return 0
        }
        let (wanted, overflowed) = UInt(limit).multipliedReportingOverflow(by: unitSize)
        guard !overflowed, !address.addingReportingOverflow(wanted).overflow else {
            return 0
        }

        var readableBytes: UInt = 0
        let infoSize = SIZE_T(MemoryLayout<MEMORY_BASIC_INFORMATION>.size)
        while readableBytes < wanted {
            let probe = address + readableBytes
            var info = MEMORY_BASIC_INFORMATION()
            guard VirtualQuery(UnsafeRawPointer(bitPattern: probe), &info, infoSize) == infoSize,
                info.State == DWORD(MEM_COMMIT),
                protectionAllowsReads(info.Protect)
            else {
                break
            }

            let regionEnd = UInt(bitPattern: info.BaseAddress) + UInt(info.RegionSize)
            guard regionEnd > probe else {
                break
            }
            readableBytes = min(wanted, regionEnd - address)
        }

        return Int(readableBytes / unitSize)
    }

    /// Whether a `MEMORY_BASIC_INFORMATION.Protect` value permits reads. The
    /// base protections occupy the low byte and are mutually exclusive;
    /// `PAGE_GUARD` is a modifier bit above them and makes the first touch a
    /// guard-page violation however readable the base protection looks.
    private static func protectionAllowsReads(_ protection: DWORD) -> Bool {
        guard protection & DWORD(PAGE_GUARD) == 0, protection & DWORD(PAGE_NOACCESS) == 0 else {
            return false
        }

        let readable =
            DWORD(PAGE_READONLY) | DWORD(PAGE_READWRITE) | DWORD(PAGE_WRITECOPY)
            | DWORD(PAGE_EXECUTE_READ) | DWORD(PAGE_EXECUTE_READWRITE)
            | DWORD(PAGE_EXECUTE_WRITECOPY)
        return protection & readable != 0
    }

    private static let maximumSettingChangeSectionLength = 64

    /// Invalidates the refresh-rate cache only when the window's monitor
    /// actually changed. Internal so a headless test can drive a drag.
    internal func noteWindowMayHaveChangedMonitor() {
        let identity = currentMonitorIdentity()
        guard identity != cachedMonitorIdentity else {
            return
        }

        cachedMonitorIdentity = identity
        invalidateRefreshRate()
    }

    /// Marks the cached refresh rate stale. `force` skips the rate limiter,
    /// which exists for `WM_MOVE`-shaped spam rather than for the rare, real
    /// display-topology change `WM_DISPLAYCHANGE` reports.
    private func invalidateRefreshRate(force: Bool = false) {
        refreshRateDirty = true
        if force {
            lastRefreshRateQueryTime = -.greatestFiniteMagnitude
        }
    }

    private func currentMonitorIdentity() -> UInt {
        if let testMonitorIdentityOverride {
            return testMonitorIdentityOverride
        }

        guard let hwnd else {
            return 0
        }

        return UInt(bitPattern: MonitorFromWindow(hwnd, DWORD(MONITOR_DEFAULTTONEAREST)))
    }

    public func create() throws {
        guard hwnd == nil else {
            return
        }

        try Self.registerWindowClass()

        guard let instance = GetModuleHandleW(nil) else {
            throw Self.lastError(for: "GetModuleHandleW")
        }

        // The window owns a strong reference to itself for as long as the
        // HWND exists. `WM_NCDESTROY` — the last message any window receives —
        // zeroes `GWLP_USERDATA` and releases it. Without that `+1`, closing a
        // window that the delegate chain also drops (the coordinator removes
        // its last strong reference from inside `windowWillClose`) frees the
        // object during `WM_DESTROY`, and the `WM_NCDESTROY` that Windows
        // sends immediately afterwards resolves freed memory.
        let rawSelf = Unmanaged.passRetained(self).toOpaque()
        ownsRetainedSelfReference = true
        let style = windowStyle
        // `nWidth`/`nHeight` are the *outer window* rect in *physical* pixels,
        // and `WindowGroup(size:)` is logical points. Passing one for the
        // other opened every app at a fraction of its intended area on any
        // HiDPI machine — a requested 1280×720 became a ≈632×341 logical
        // client area at 200 %, small enough to flip the app into the compact
        // size class before it ever painted.
        let creationDpi = Self.creationDpi()
        let geometry = Self.windowGeometry(forLogicalClientSize: clientSize, style: style, dpi: creationDpi)

        let createdWindow: HWND?
        do {
            createdWindow = try Self.className.withWideChars { className in
                try title.withWideChars { title in
                    let window = CreateWindowExW(
                        0,
                        className,
                        title,
                        style,
                        CW_USEDEFAULT,
                        CW_USEDEFAULT,
                        geometry.windowWidth,
                        geometry.windowHeight,
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
        } catch {
            // Creation failed. When it failed *after* `WM_NCCREATE`, Windows
            // has already delivered `WM_NCDESTROY` and the self reference is
            // gone; when it failed before, nothing else will ever release it.
            // The flag distinguishes the two, so the `+1` is balanced exactly
            // once on every path.
            releaseRetainedSelfReferenceIfNeeded()
            throw error
        }

        hwnd = createdWindow

        // The `WM_SIZE` Windows delivers from inside `CreateWindowExW` arrives
        // before `hwnd` is assigned, so the wndproc's cache refresh is a no-op
        // for it. Sample the real client rect here instead: until this ran,
        // `currentClientSize()` reported the *logical* size the caller asked
        // for, and the startup surface descriptor built a swap chain for it —
        // half the window's pixels on a 200 % display.
        updateCachedClientSize()

        // Accept files dragged from the shell (WM_DROPFILES).
        if let window = createdWindow {
            FileDropManager.setAcceptsDroppedFiles(on: window, true)
        }

        // Register for touch input
        if let window = createdWindow {
            RegisterTouchWindow(window, 0)
        }

        // Placement and z-order, once the HWND exists and its real monitor is
        // known. The size constraints ride `WM_GETMINMAXINFO`; the style
        // already carries the fixed-size decision.
        applyConfigurationToCreatedWindow()

        // Prime the system appearance snapshot at startup so the first
        // environment build sees current OS settings.
        _ = systemAppearance

        delegate?.windowDidCreate(self)
    }

    /// Window style for this window's title-bar visibility and resizability.
    /// `.fixedSize` drops the sizing border and the maximize box, which is the
    /// half of `.windowResizability(.contentSize)` that a track-size limit
    /// cannot express.
    private var windowStyle: DWORD {
        var style: Int32
        switch titleBarVisibility.kind {
        case .hidden:
            style = Int32(WS_POPUP) | Int32(WS_THICKFRAME) | Int32(WS_MINIMIZEBOX) | Int32(WS_MAXIMIZEBOX)
        default:
            style = Int32(WS_OVERLAPPEDWINDOW)
        }

        if configuration.resizability == .fixedSize {
            style &= ~(Int32(WS_THICKFRAME) | Int32(WS_MAXIMIZEBOX))
        }

        return DWORD(UInt32(bitPattern: style))
    }

    private func applyConfigurationToCreatedWindow() {
        guard let hwnd else {
            return
        }

        if configuration.isAlwaysOnTop {
            SetWindowPos(
                hwnd,
                Self.topmostWindowHandle,
                0,
                0,
                0,
                0,
                UINT(SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE)
            )
        }

        guard let normalizedPosition = configuration.normalizedPosition else {
            return
        }

        var windowRect = RECT()
        guard GetWindowRect(hwnd, &windowRect) else {
            return
        }

        let monitor = MonitorFromWindow(hwnd, DWORD(MONITOR_DEFAULTTONEAREST))
        var monitorInfo = MONITORINFO()
        monitorInfo.cbSize = DWORD(MemoryLayout<MONITORINFO>.size)
        guard GetMonitorInfoW(monitor, &monitorInfo) else {
            return
        }

        let origin = Self.windowOrigin(
            normalizedPosition: normalizedPosition,
            windowSize: IntSize(
                width: Int32(windowRect.right - windowRect.left),
                height: Int32(windowRect.bottom - windowRect.top)
            ),
            workArea: monitorInfo.rcWork
        )
        SetWindowPos(hwnd, nil, origin.x, origin.y, 0, 0, UINT(SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE))
    }

    /// Top-left of a window of `windowSize` placed at `normalizedPosition`
    /// within `workArea`. Pure, so the placement arithmetic is testable
    /// without a monitor.
    internal static func windowOrigin(
        normalizedPosition: Point,
        windowSize: IntSize,
        workArea: RECT
    ) -> (x: Int32, y: Int32) {
        func clamped(_ value: Double) -> Double {
            guard value.isFinite else { return 0.5 }
            return min(max(value, 0), 1)
        }

        let slackX = max(0, Int32(workArea.right - workArea.left) - windowSize.width)
        let slackY = max(0, Int32(workArea.bottom - workArea.top) - windowSize.height)
        return (
            x: Int32(workArea.left) + Int32((Double(slackX) * clamped(normalizedPosition.x)).rounded()),
            y: Int32(workArea.top) + Int32((Double(slackY) * clamped(normalizedPosition.y)).rounded())
        )
    }

    /// `HWND_TOPMOST`. Declared here because the WinSDK Swift overlay does not
    /// export the sentinel handles.
    private static let topmostWindowHandle = HWND(bitPattern: -1)

    /// Outer window size, in physical pixels, for a logical client size at a
    /// given DPI. Pure and callable without a window, so the DPI contract is
    /// testable headlessly.
    internal struct WindowCreationGeometry: Equatable {
        var windowWidth: Int32
        var windowHeight: Int32
    }

    internal static func windowGeometry(
        forLogicalClientSize clientSize: IntSize,
        style: DWORD,
        exStyle: DWORD = 0,
        dpi: UINT
    ) -> WindowCreationGeometry {
        let physical = physicalClientSize(forLogicalClientSize: clientSize, dpi: dpi)
        var rect = RECT(left: 0, top: 0, right: LONG(physical.width), bottom: LONG(physical.height))
        guard AdjustWindowRectExForDpi(&rect, style, false, exStyle, dpi) else {
            return WindowCreationGeometry(windowWidth: physical.width, windowHeight: physical.height)
        }

        return WindowCreationGeometry(
            windowWidth: Int32(rect.right - rect.left),
            windowHeight: Int32(rect.bottom - rect.top)
        )
    }

    internal static func physicalClientSize(forLogicalClientSize clientSize: IntSize, dpi: UINT) -> IntSize {
        let scale = Double(max(dpi, 1)) / 96.0
        return IntSize(
            width: Int32((Double(max(clientSize.width, 1)) * scale).rounded()),
            height: Int32((Double(max(clientSize.height, 1)) * scale).rounded())
        )
    }

    /// DPI of the monitor the window is about to be created on.
    ///
    /// `GetDpiForWindow` needs an HWND that does not exist yet. Under
    /// per-monitor-v2 awareness — which `Win32HighDpiSupport` installs before
    /// any window is created — `GetDpiForSystem` reports the *primary*
    /// monitor's DPI, which is the monitor `CW_USEDEFAULT` places the window
    /// on. A window that lands elsewhere is corrected by `WM_DPICHANGED`.
    internal static func creationDpi() -> UINT {
        if let testCreationDpiOverride {
            return testCreationDpiOverride
        }

        let dpi = GetDpiForSystem()
        return dpi > 0 ? dpi : 96
    }

    internal static var testCreationDpiOverride: UINT?

    /// Current DPI of this window, falling back to the creation DPI before the
    /// HWND exists.
    private var currentDpi: UINT {
        if let testScaleFactorOverride {
            return UINT(max(1, (testScaleFactorOverride * 96.0).rounded()))
        }

        guard let hwnd else {
            return Self.creationDpi()
        }

        let dpi = GetDpiForWindow(hwnd)
        return dpi > 0 ? dpi : Self.creationDpi()
    }

    /// Physical outer-window track sizes `WM_GETMINMAXINFO` reports, derived
    /// from the logical constraints the scene layer asked for. Internal so a
    /// headless test can pin the conversion.
    internal func trackSizeLimits(dpi: UINT) -> (minimum: IntSize?, maximum: IntSize?) {
        let style = windowStyle
        let pinnedSize = configuration.resizability == .fixedSize ? requestedLogicalClientSize : nil

        func outerSize(_ logical: IntSize) -> IntSize {
            let geometry = Self.windowGeometry(forLogicalClientSize: logical, style: style, dpi: dpi)
            return IntSize(width: geometry.windowWidth, height: geometry.windowHeight)
        }

        return (
            minimum: (configuration.minimumClientSize ?? pinnedSize).map(outerSize),
            maximum: (configuration.maximumClientSize ?? pinnedSize).map(outerSize)
        )
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
        invalidateRequestCount &+= 1
        guard let hwnd else {
            return
        }

        InvalidateRect(hwnd, nil, false)
    }

    /// Number of `invalidate()` calls this window has received. Internal so
    /// headless host tests can prove a failure path does not turn into a
    /// self-feeding repaint loop (an `InvalidateRect` issued from inside
    /// `WM_PAINT` re-dirties the region `BeginPaint` just validated).
    internal private(set) var invalidateRequestCount = 0

    /// Balances the `+1` `create()` took, exactly once. Returns `true` when
    /// this call is the one that consumed the ownership, so the caller can
    /// perform the release. Split from the release itself because the
    /// `WM_NCDESTROY` release must happen *outside* any method running on
    /// `self`.
    private func consumeRetainedSelfReferenceOwnership() -> Bool {
        guard ownsRetainedSelfReference else {
            return false
        }
        ownsRetainedSelfReference = false
        return true
    }

    /// Release path for window creation failures, where no `WM_NCDESTROY`
    /// will arrive to do it. Safe to call on `self` because `create()`'s
    /// caller necessarily holds its own strong reference.
    private func releaseRetainedSelfReferenceIfNeeded() {
        guard consumeRetainedSelfReferenceOwnership() else {
            return
        }
        Unmanaged.passUnretained(self).release()
    }

    public func requestClose() {
        guard let hwnd else {
            PostQuitMessage(0)
            return
        }

        PostMessageW(hwnd, UINT(WM_CLOSE), 0, 0)
    }

    public func setAnimationTimerEnabled(_ enabled: Bool, intervalMilliseconds: UINT = 16) {
        if enabled {
            // Recorded before the window check so the requested cadence
            // survives a stop/start cycle (and so tests can drive the plan
            // without an HWND). The *installed* interval is separate state.
            requestedAnimationTimerIntervalMilliseconds = max(1, intervalMilliseconds)
        }

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

    /// Converts a rectangle from logical client coordinates (the retained
    /// runtime's root-view space) to screen coordinates. Used by the
    /// accessibility bridge, which must report bounds in screen space.
    /// Returns the input unchanged when the window has no handle yet.
    public func clientRectToScreen(_ rect: Rect) -> Rect {
        guard let hwnd else {
            return rect
        }

        // The same clamped scale the runtime laid this rect out with — a raw
        // sub-1 DPI here would report accessibility bounds a third away from
        // the pixels the user sees.
        let scale = effectiveScaleFactor
        var topLeft = POINT(x: LONG((rect.origin.x * scale).rounded()), y: LONG((rect.origin.y * scale).rounded()))
        var bottomRight = POINT(
            x: LONG(((rect.origin.x + rect.size.width) * scale).rounded()),
            y: LONG(((rect.origin.y + rect.size.height) * scale).rounded())
        )
        ClientToScreen(hwnd, &topLeft)
        ClientToScreen(hwnd, &bottomRight)
        return Rect(
            x: Double(topLeft.x),
            y: Double(topLeft.y),
            width: Double(bottomRight.x - topLeft.x),
            height: Double(bottomRight.y - topLeft.y)
        )
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

    private func startHighResolutionTimer(intervalMilliseconds: UINT) -> Bool {
        guard let hwnd else {
            return false
        }

        var timerHandle: HANDLE?
        let gate = Win32AnimationTimerGate(windowHandleValue: UInt(bitPattern: hwnd))

        // The gate is retained by the property for as long as the timer can
        // fire; `stopHighResolutionTimer` drops it only after
        // `DeleteTimerQueueTimer` has waited for the last callback.
        let created = CreateTimerQueueTimer(
            &timerHandle,
            nil,
            win32HighResolutionTimerCallback,
            Unmanaged.passUnretained(gate).toOpaque(),
            DWORD(intervalMilliseconds),
            DWORD(intervalMilliseconds),
            DWORD(WT_EXECUTEDEFAULT)
        )

        guard created else {
            return false
        }

        highResTimerGate = gate
        highResTimerHandle = timerHandle
        return true
    }

    private func stopHighResolutionTimer() {
        guard let timerHandle = highResTimerHandle else {
            highResTimerGate = nil
            return
        }

        DeleteTimerQueueTimer(nil, timerHandle, INVALID_HANDLE_VALUE)
        highResTimerHandle = nil
        highResTimerGate = nil
    }

    private func startAnimationTimer(using configuration: AnimationTimerConfiguration) {
        guard let hwnd else {
            return
        }

        var usesHighResolution = configuration.useHighResolution
        if usesHighResolution, !startHighResolutionTimer(intervalMilliseconds: configuration.intervalMilliseconds) {
            // Thread-pool exhaustion or handle pressure. Reporting a "running"
            // timer that does not exist stops animation and pending
            // presentation permanently and silently, so fall back to the
            // coalescing `SetTimer` path instead.
            isHighResolutionTimerUnavailable = true
            usesHighResolution = false
        }

        if !usesHighResolution {
            SetTimer(hwnd, Self.animationTimerIdentifier, configuration.intervalMilliseconds, nil)
        }

        animationTimerIntervalMilliseconds = configuration.intervalMilliseconds
        animationTimerUsesHighResolution = usesHighResolution
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

        // Restart from what the caller asked for, not from the interval of the
        // timer we are about to stop: `stopCurrentAnimationTimer` zeroes that
        // field, and `max(1, 0)` is a 1 ms (1000 Hz) frame timer.
        stopCurrentAnimationTimer()
        startAnimationTimer(
            using: animationTimerConfiguration(requestedInterval: requestedAnimationTimerIntervalMilliseconds)
        )
    }

    private func animationTimerConfiguration(requestedInterval: UINT) -> AnimationTimerConfiguration {
        Self.animationTimerConfiguration(
            requestedInterval: requestedInterval,
            isInModalLoop: isInSizeMove || isInMenuLoop,
            prefersHighResolution: useHighResolutionTimer,
            isHighResolutionAvailable: !isHighResolutionTimerUnavailable
        )
    }

    /// Pure resolution of the animation timer plan. Modal size/move and menu
    /// loops run their own message pump, where only the coalescing `SetTimer`
    /// path is delivered, and a window whose timer-queue timer could not be
    /// created falls back to the same path. Static so headless tests can pin
    /// the rules without an HWND.
    internal static func animationTimerConfiguration(
        requestedInterval: UINT,
        isInModalLoop: Bool,
        prefersHighResolution: Bool,
        isHighResolutionAvailable: Bool
    ) -> AnimationTimerConfiguration {
        if isInModalLoop {
            return AnimationTimerConfiguration(
                intervalMilliseconds: UINT(max(1, USER_TIMER_MINIMUM)),
                useHighResolution: false
            )
        }

        return AnimationTimerConfiguration(
            intervalMilliseconds: max(1, requestedInterval),
            useHighResolution: prefersHighResolution && isHighResolutionAvailable
        )
    }

    /// The plan the window would install right now, given the cadence its
    /// delegate last requested and the modal-loop state the wndproc tracks.
    /// Internal so headless tests can drive enter/exit size-move transitions
    /// without a real HWND.
    internal var currentAnimationTimerConfiguration: AnimationTimerConfiguration {
        animationTimerConfiguration(requestedInterval: requestedAnimationTimerIntervalMilliseconds)
    }

    /// Headless seam for the modal-loop transitions `WM_ENTER/EXITSIZEMOVE`
    /// and `WM_ENTER/EXITMENULOOP` drive.
    internal func setModalLoopStateForTesting(isInSizeMove: Bool = false, isInMenuLoop: Bool = false) {
        self.isInSizeMove = isInSizeMove
        self.isInMenuLoop = isInMenuLoop
        refreshAnimationTimerIfNeeded()
    }

    /// Headless seam standing in for a `CreateTimerQueueTimer` failure.
    internal func markHighResolutionTimerUnavailableForTesting() {
        isHighResolutionTimerUnavailable = true
    }

    // MARK: - Message handling

    private func handleMessage(hwnd: HWND?, message: UINT, wParam: WPARAM, lParam: LPARAM) -> LRESULT {
        switch message {
        case UINT(WM_ERASEBKGND):
            return 1

        case UINT(WM_GETOBJECT):
            if let provider = accessibilityProvider,
                let result = provider.handleAccessibilityGetObject(hwnd: hwnd, wParam: wParam, lParam: lParam)
            {
                return result
            }
            return DefWindowProcW(hwnd, message, wParam, lParam)

        case UINT(WM_SIZE):
            // The cache always mirrors the OS. Skipping it while minimized
            // left `clientSize` reporting the pre-minimize rect, which
            // `currentClientSize()` feeds to the host's surface descriptor —
            // so a presenter attach that landed during a minimize built a
            // swap chain for a size the window does not have.
            isMinimized = Int(truncatingIfNeeded: wParam) == Int(SIZE_MINIMIZED)
            updateCachedClientSize()

            // Only the delegate callback is suppressed. A minimized window has
            // a 0×0 client rect, and forwarding that rebuilds the whole
            // component tree at zero size (and raises a UIA structure change
            // to any attached screen reader) on every minimize, then again on
            // restore, for a size nothing is painted at. The restore delivers
            // its own WM_SIZE with the real rect.
            if isMinimized {
                return 0
            }

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

        case UINT(WM_GETMINMAXINFO):
            // DefWindowProc fills the defaults; the configured constraints
            // override them. Without this handler `.windowMinSize(…)`,
            // `.windowMaxSize(…)` and `.windowResizability(.contentSize)` were
            // parsed by the scene modifiers and then dropped.
            let result = DefWindowProcW(hwnd, message, wParam, lParam)
            guard let info = UnsafeMutableRawPointer(bitPattern: Int(lParam))?.assumingMemoryBound(to: MINMAXINFO.self)
            else {
                return result
            }

            let limits = trackSizeLimits(dpi: currentDpi)
            if let minimum = limits.minimum {
                info.pointee.ptMinTrackSize.x = LONG(minimum.width)
                info.pointee.ptMinTrackSize.y = LONG(minimum.height)
            }
            if let maximum = limits.maximum {
                info.pointee.ptMaxTrackSize.x = LONG(maximum.width)
                info.pointee.ptMaxTrackSize.y = LONG(maximum.height)
            }
            return result

        case UINT(WM_PAINT):
            var paint = PAINTSTRUCT()
            BeginPaint(hwnd, &paint)
            delegate?.windowNeedsDisplay(self)
            EndPaint(hwnd, &paint)
            return 0

        case UINT(WM_TIMER):
            if UInt(truncatingIfNeeded: wParam) == Self.animationTimerIdentifier {
                // Release the post gate before the frame runs: a long frame may
                // then queue exactly one further tick, which is the intended
                // one-deep pipeline rather than an unbounded backlog.
                highResTimerGate?.consumePost()
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
            let source = Self.scrollInputSource(from: wParam)
            if modifiers.contains(.shift) {
                delegate?.window(
                    self,
                    horizontalScrollAt: point,
                    delta: Self.mouseWheelDelta(from: wParam, unit: .characters),
                    source: source
                )
            } else {
                delegate?.window(
                    self,
                    mouseWheelAt: point,
                    delta: Self.mouseWheelDelta(from: wParam, unit: .lines),
                    source: source
                )
            }
            return 0

        case UINT(WM_MOUSEHWHEEL):
            delegate?.window(
                self,
                horizontalScrollAt: Self.clientPoint(fromScreenLParam: lParam, hwnd: hwnd),
                delta: Self.mouseWheelDelta(from: wParam, unit: .characters),
                source: Self.scrollInputSource(from: wParam)
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
            invalidateRefreshRate(force: true)
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
            // A drag delivers this at mouse-report rate. Only a monitor change
            // can change the refresh rate, and the cache is rate limited on
            // top of that, so a drag costs one `MonitorFromWindow` per message
            // instead of a display-mode enumeration.
            noteWindowMayHaveChangedMonitor()
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
            routeSettingChange(wParam: wParam, section: Self.settingChangeSection(lParam))
            return 0

        case UINT(WM_SYSCOLORCHANGE):
            routeSystemColorChange()
            return 0

        case UINT(WM_SETCURSOR):
            let hitTest = UInt16(UInt(truncatingIfNeeded: lParam) & 0xFFFF)
            if hitTest == UINT16(HTCLIENT) {
                SetCursor(LoadCursorW(nil, UnsafePointer<WCHAR>(bitPattern: 32512)))
                return 1
            }
            return DefWindowProcW(hwnd, message, wParam, lParam)

        // IME composition messages. The app paints its own marked
        // (composition) text, so WM_IME_SETCONTEXT hides the OS in-line
        // composition window while keeping the candidate window; composition
        // and result strings become `IMECompositionEvent`s routed through
        // the delegate. When no IME is active none of these fire and
        // keyboard input is byte-identical to the pre-IME path.

        case UINT(WM_IME_SETCONTEXT):
            let adjustedLParam = Self.imeSetContextAdjustedLParam(lParam)
            return DefWindowProcW(hwnd, message, wParam, adjustedLParam)

        case UINT(WM_IME_STARTCOMPOSITION):
            updateIMECompositionWindowPosition()
            delegate?.window(self, imeComposition: IMECompositionEvent(phase: .started))
            return DefWindowProcW(hwnd, message, wParam, lParam)

        case UINT(WM_IME_COMPOSITION):
            for event in Self.imeCompositionEvents(
                lParam: lParam,
                provider: imeCompositionContextProvider,
                hwnd: hwnd
            ) {
                delegate?.window(self, imeComposition: event)
            }
            updateIMECompositionWindowPosition()
            return DefWindowProcW(hwnd, message, wParam, lParam)

        case UINT(WM_IME_ENDCOMPOSITION):
            delegate?.window(self, imeComposition: IMECompositionEvent(phase: .ended))
            return DefWindowProcW(hwnd, message, wParam, lParam)

        case UINT(WM_IME_CHAR):
            // Sent when input bypasses the composition window; treat the
            // character as an immediately committed result string.
            if let scalar = Unicode.Scalar(UInt32(truncatingIfNeeded: wParam)) {
                delegate?.window(self, imeComposition: IMECompositionEvent(phase: .committed(String(scalar))))
            }
            return 0

        // Touch input

        case UINT(WM_TOUCH):
            handleTouchMessage(hwnd: hwnd, wParam: wParam, lParam: lParam)
            return 0

        case UINT(WM_DESTROY):
            setAnimationTimerEnabled(false)
            delegate?.windowWillClose(self)
            if postsQuitMessageOnDestroy {
                PostQuitMessage(0)
            }
            return 0

        case UINT(WM_NCDESTROY):
            // Last message this HWND will ever receive. Drop the OS-side back
            // pointer before the handle dies so no later message can resolve
            // it, stop any timer that outlived WM_DESTROY (the stop path is
            // guarded on a live handle), and forget the handle so the public
            // API stops calling into a destroyed window. The matching release
            // of the self reference happens in `windowProc`, after this frame
            // has returned.
            let result = DefWindowProcW(hwnd, message, wParam, lParam)
            setAnimationTimerEnabled(false)
            if let hwnd {
                SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0)
            }
            self.hwnd = nil
            return result

        case UINT(WM_DROPFILES):
            if let payload = FileDropManager.payload(forDropHandle: UInt(wParam)) {
                delegate?.window(self, didReceiveFileDrop: payload)
            }
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

    /// Adjusts a `WM_IME_SETCONTEXT` lParam so the OS does not draw its own
    /// in-line composition window: the app paints marked text itself. The
    /// candidate window stays enabled. Static and internal so headless tests
    /// can verify the bit manipulation.
    static func imeSetContextAdjustedLParam(_ lParam: LPARAM) -> LPARAM {
        lParam & ~LPARAM(bitPattern: UInt64(Self.iscShowUICompositionWindowFlag))
    }

    /// Pure translation of a `WM_IME_COMPOSITION` lParam into delegate events
    /// via the injectable context provider. A single message can carry both a
    /// composition-string update and a result string; the update is delivered
    /// first so the commit lands on the latest marked state. Static and
    /// internal so headless tests can drive it with a fake provider.
    static func imeCompositionEvents(
        lParam: LPARAM,
        provider: any IMECompositionContextProvider,
        hwnd: HWND?
    ) -> [IMECompositionEvent] {
        let flags = UInt(truncatingIfNeeded: lParam)
        var events: [IMECompositionEvent] = []

        if (flags & UInt(GCS_COMPSTR)) != 0,
            let composition = provider.compositionString(window: hwnd)
        {
            events.append(IMECompositionEvent(phase: .updated(composition)))
        }

        if (flags & UInt(GCS_RESULTSTR)) != 0,
            let result = provider.resultString(window: hwnd)
        {
            events.append(IMECompositionEvent(phase: .committed(result)))
        }

        return events
    }

    /// Repositions the IME composition/candidate window at the focused text
    /// input's caret. The delegate reports the caret rectangle in logical
    /// root coordinates; IMM32 expects client coordinates in physical pixels,
    /// so the window scale factor is applied. Positioned at the caret's
    /// bottom-leading corner so the candidate window opens below the text.
    private func updateIMECompositionWindowPosition() {
        guard let hwnd,
            let caretRect = delegate?.windowTextInputCaretRect(self)
        else {
            return
        }

        let scale = effectiveScaleFactor
        let clientPoint = Point(
            x: (caretRect.origin.x * scale).rounded(),
            y: ((caretRect.origin.y + caretRect.size.height) * scale).rounded()
        )
        imeCompositionContextProvider.setCompositionWindowPosition(clientPoint, window: hwnd)
    }

    /// `ISC_SHOWUICOMPOSITIONWINDOW` from imm.h. Declared locally because the
    /// Swift WinSDK module does not export the constant.
    private static let iscShowUICompositionWindowFlag: UInt32 = 0x8000_0000

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

    /// A click wheel reports whole multiples of `WHEEL_DELTA`; a precision
    /// touchpad (and a Magic-Mouse-class device) reports fractions of it as
    /// the finger moves. That is the only signal Windows gives for the
    /// distinction AppKit exposes as `NSEvent.momentumPhase`, and it is
    /// enough: momentum belongs to the gesture, never to the detent.
    static func scrollInputSource(from wParam: WPARAM) -> ScrollInputSource {
        let highWord = UInt16((UInt(truncatingIfNeeded: wParam) >> 16) & 0xFFFF)
        let magnitude = abs(Int(Int16(bitPattern: highWord)))
        return magnitude != 0 && magnitude % Int(WHEEL_DELTA) == 0 ? .wheelNotch : .precise
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

    /// The window's monotonic frame clock, in seconds.
    ///
    /// `GetTickCount64` advances in system clock ticks — documented as 10–16 ms
    /// and typically 15.625 ms — which is *coarser than a 60 Hz vsync period*.
    /// Pacing fed by it saw 15.6 ms elapsed against a 16.667 ms interval, so
    /// every other animation frame was dropped and every continuous animation
    /// ran at ~30 fps with alternating 15.6/31.2 ms spacing, sampling the
    /// easing curves in `docs/AnimationParity.md` on a quantized, jittering
    /// clock. `QueryPerformanceCounter` is monotonic and sub-microsecond.
    public static func currentTimestampSeconds() -> Double {
        var counter = LARGE_INTEGER()
        guard QueryPerformanceCounter(&counter), performanceCounterFrequency > 0 else {
            return Double(GetTickCount64()) / 1000.0
        }

        return Double(counter.QuadPart) / performanceCounterFrequency
    }

    /// Counts per second, fixed at boot on every supported Windows version, so
    /// this is queried once. Zero means the query failed and the tick-count
    /// fallback applies.
    private static let performanceCounterFrequency: Double = {
        var frequency = LARGE_INTEGER()
        guard QueryPerformanceFrequency(&frequency), frequency.QuadPart > 0 else {
            return 0
        }

        return Double(frequency.QuadPart)
    }()

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

    internal struct AnimationTimerConfiguration: Equatable {
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
            let unmanaged = Unmanaged<Win32Window>.fromOpaque(rawSelf)
            let result = unmanaged.takeUnretainedValue()
                .handleMessage(hwnd: hwnd, message: message, wParam: wParam, lParam: lParam)

            // Balance `create()`'s `passRetained` here rather than inside the
            // handler, so the deallocation — which can run the delegate chain's
            // teardown — never happens on a frame that is still executing a
            // method on the window.
            if message == UINT(WM_NCDESTROY),
                unmanaged.takeUnretainedValue().consumeRetainedSelfReferenceOwnership()
            {
                unmanaged.release()
            }

            return result
        }

        return DefWindowProcW(hwnd, message, wParam, lParam)
    }
}

// MARK: - IME composition context

/// IMM32 composition-context access behind an injectable seam (same
/// precedent as `SystemAppearanceProvider`): the production default is
/// `Win32IMECompositionContextProvider`; tests inject fakes so composition
/// translation stays headless (no live IME required).
public protocol IMECompositionContextProvider: Sendable {
    /// Current in-progress composition string (`GCS_COMPSTR`), `nil` when
    /// absent or unavailable.
    func compositionString(window hwnd: HWND?) -> String?
    /// Committed result string (`GCS_RESULTSTR`), `nil` when absent or
    /// unavailable.
    func resultString(window hwnd: HWND?) -> String?
    /// Moves the composition window (`CFS_POINT`) to a client-space point in
    /// physical pixels; the candidate window follows it.
    func setCompositionWindowPosition(_ point: Point, window hwnd: HWND?)
}

/// Live IMM32 implementation used by `Win32Window` in production.
public struct Win32IMECompositionContextProvider: IMECompositionContextProvider {
    public init() {}

    public func compositionString(window hwnd: HWND?) -> String? {
        compositionString(window: hwnd, flag: DWORD(GCS_COMPSTR))
    }

    public func resultString(window hwnd: HWND?) -> String? {
        compositionString(window: hwnd, flag: DWORD(GCS_RESULTSTR))
    }

    public func setCompositionWindowPosition(_ point: Point, window hwnd: HWND?) {
        guard let hwnd, let imc = ImmGetContext(hwnd) else {
            return
        }
        defer { ImmReleaseContext(hwnd, imc) }

        var form = COMPOSITIONFORM()
        form.dwStyle = DWORD(CFS_POINT)
        form.ptCurrentPos = POINT(x: LONG(point.x), y: LONG(point.y))
        ImmSetCompositionWindow(imc, &form)
    }

    private func compositionString(window hwnd: HWND?, flag: DWORD) -> String? {
        guard let hwnd, let imc = ImmGetContext(hwnd) else {
            return nil
        }
        defer { ImmReleaseContext(hwnd, imc) }

        let byteCount = ImmGetCompositionStringW(imc, flag, nil, 0)
        // Error returns (IMM_ERROR_NODATA / IMM_ERROR_GENERAL) are negative;
        // the guard fails closed on those and on empty strings.
        guard byteCount > 0 else {
            return nil
        }

        let charCount = Int(byteCount) / MemoryLayout<WCHAR>.size
        var buffer = [WCHAR](repeating: 0, count: charCount + 1)
        // The composition can shrink between the size query and the copy, so
        // decode exactly what the second call reports rather than the
        // original size — decoding `charCount` unconditionally would leak
        // zero padding into the string.
        let copiedBytes = ImmGetCompositionStringW(imc, flag, &buffer, DWORD(byteCount))
        guard copiedBytes > 0 else {
            return nil
        }
        let copiedChars = min(Int(copiedBytes), Int(byteCount)) / MemoryLayout<WCHAR>.size
        return String(decoding: buffer.prefix(copiedChars), as: UTF16.self)
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
        guard
            let appsUseLightTheme = readCurrentUserDWORD(
                subKey: #"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"#,
                valueName: "AppsUseLightTheme"
            )
        else {
            return nil
        }

        return appsUseLightTheme == 0 ? .dark : .light
    }

    private static func sampleTextScaleFactor() -> Double? {
        guard
            let percent = readCurrentUserDWORD(
                subKey: #"Software\Microsoft\Accessibility"#,
                valueName: "TextScaleFactor"
            ), percent > 0
        else {
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
        try start(window: window)
        return try runMessageLoop()
    }

    /// Creates and shows the window without entering the message loop.
    /// Multi-window coordinators use this to realize additional windows
    /// after the primary window has booted.
    public static func start(window: Win32Window) throws {
        Win32HighDpiSupport.enableIfNeeded()
        try window.create()
        window.show()
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

    /// Posts `WM_QUIT` so `runMessageLoop` returns. Used by multi-window
    /// coordinators once the last managed window has closed.
    public static func terminateMessageLoop() {
        PostQuitMessage(0)
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
