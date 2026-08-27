/// Window configuration that does not name a windowing system or renderer.
///
/// A platform factory translates these values into its native window traits.
/// Keeping the requested size in logical points lets different hosts apply
/// their own display scaling without changing shared application code.
public struct PlatformWindowConfiguration: Equatable, Sendable {
    public var title: String
    public var clientSize: IntSize
    public var titleBarVisibility: WindowTitleBarVisibility
    public var minimumClientSize: IntSize?
    public var maximumClientSize: IntSize?
    public var normalizedPosition: Point?
    public var isResizable: Bool
    public var isAlwaysOnTop: Bool

    public init(
        title: String,
        clientSize: IntSize,
        titleBarVisibility: WindowTitleBarVisibility = .automatic,
        minimumClientSize: IntSize? = nil,
        maximumClientSize: IntSize? = nil,
        normalizedPosition: Point? = nil,
        isResizable: Bool = true,
        isAlwaysOnTop: Bool = false
    ) {
        self.title = title
        self.clientSize = clientSize
        self.titleBarVisibility = titleBarVisibility
        self.minimumClientSize = minimumClientSize
        self.maximumClientSize = maximumClientSize
        self.normalizedPosition = normalizedPosition
        self.isResizable = isResizable
        self.isAlwaysOnTop = isAlwaysOnTop
    }
}

/// The phase of a mouse or pen button delivered by a platform window.
public enum PlatformPointerPhase: Equatable, Sendable {
    case down
    case up
}

/// The axis of a platform-native scroll gesture.
public enum PlatformScrollAxis: Equatable, Sendable {
    case horizontal
    case vertical
}

/// The phase of a group of touch points delivered by a platform window.
public enum PlatformTouchPhase: Equatable, Sendable {
    case began
    case moved
    case ended
}

/// Input, display, and lifecycle events that can be emitted by any windowing
/// implementation without exposing HWNDs, messages, or native SDK types.
///
/// Existing keyboard, pointer, IME, geometry, and scroll-source values remain
/// the shared source of truth. File drops carry paths rather than a native
/// shell payload so the event stays inside the platform-neutral core.
public enum PlatformWindowEvent: Sendable {
    case created
    case resized(IntSize)
    case needsDisplay
    case animationFrame(timestamp: Double)
    case pointerMoved(Point)
    case pointerExited
    case pointerButton(MouseEvent, phase: PlatformPointerPhase)
    case pointerDoubleClicked(MouseEvent)
    case pointerInteractionCancelled
    case scroll(position: Point, delta: Double, axis: PlatformScrollAxis, source: ScrollInputSource)
    case keyDown(KeyboardEvent)
    case textInput(String)
    case keyboardFocusLost
    case willClose
    case displayChanged(scaleFactor: Double, refreshRate: UInt32)
    case activeStateChanged(Bool)
    case visibilityChanged(Bool)
    case systemAppearanceChanged
    case imeComposition(IMECompositionEvent)
    case touch(phase: PlatformTouchPhase, points: [Point])
    case filesDropped(paths: [String], position: Point)
}

/// Receives platform-neutral lifecycle and input events from a window.
///
/// Hosts are main-actor-centric, matching the retained runtime and the rest
/// of the UI stack. A host owns no assumptions about the concrete window or
/// the rendering backend attached to its opaque native surface.
@MainActor
public protocol PlatformWindowHost: AnyObject {
    func platformWindow(_ window: any PlatformWindow, didReceive event: PlatformWindowEvent)

    /// Consulted before an ordinary close request destroys the native window.
    /// Returning false preserves the window and its resources. A host may
    /// resolve a deferred decision and call `requestClose()` again later.
    /// `.willClose` is a teardown notification, not this permission check.
    func platformWindowShouldClose(_ window: any PlatformWindow) -> Bool

    /// The focused text input's logical caret rectangle, when available.
    /// Native input-method integrations use it to position candidate windows.
    func platformWindowTextInputCaretRect(_ window: any PlatformWindow) -> Rect?
}

extension PlatformWindowHost {
    public func platformWindowShouldClose(_ window: any PlatformWindow) -> Bool {
        true
    }

    public func platformWindowTextInputCaretRect(_ window: any PlatformWindow) -> Rect? {
        nil
    }
}

/// The window operations needed by a retained UI host and renderer.
///
/// `nativeHandle` is deliberately opaque: presentation backends translate it
/// into their own platform surface only at the backend boundary.
@MainActor
public protocol PlatformWindow: AnyObject {
    var title: String { get }
    var clientSize: IntSize { get }
    var nativeHandle: NativeWindowHandle? { get }
    var scaleFactor: Double { get }
    var effectiveScaleFactor: Double { get }
    var monitorRefreshRate: UInt32 { get }
    var isMinimized: Bool { get }

    func create() throws
    func show()
    func invalidate()
    func requestClose()
    func currentClientSize() -> IntSize
    func setAnimationTimerEnabled(_ enabled: Bool, intervalMilliseconds: UInt32)
    func clientRectToScreen(_ rect: Rect) -> Rect

    /// Installs or removes the neutral event host without retaining it.
    func setPlatformWindowHost(_ host: (any PlatformWindowHost)?)
}

/// Errors shared by platform-host factories without exposing native SDK codes.
public enum PlatformHostError: Equatable, Error, Sendable {
    case incompatibleWindow(expectedPlatform: String)
}

/// Creates windows and owns the native event-loop boundary for one platform.
///
/// This is independent of `RenderBackendFactory`: a platform chooses how
/// windows and events work, while a renderer chooses how a scene is drawn.
@MainActor
public protocol PlatformHostFactory {
    var platformName: String { get }

    func makeWindow(configuration: PlatformWindowConfiguration) throws -> any PlatformWindow
    func start(window: any PlatformWindow) throws
    func runEventLoop() throws -> Int32
    func terminateEventLoop()
}
