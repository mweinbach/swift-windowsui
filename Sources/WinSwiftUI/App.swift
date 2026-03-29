import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsPlatform
import SwiftWindowsRendererD3D11
import SwiftWindowsUI

@MainActor
public protocol Scene {
    associatedtype Body: Scene

    var body: Body { get }

    func makeWindowConfiguration() -> WindowGroupConfiguration
}

public extension Scene {
    func makeWindowConfiguration() -> WindowGroupConfiguration {
        body.makeWindowConfiguration()
    }
}

extension Never: Scene {
    public func makeWindowConfiguration() -> WindowGroupConfiguration {
        fatalError("Never cannot build a window configuration")
    }
}

@MainActor
public protocol App {
    associatedtype Body: Scene

    init()

    var body: Body { get }
}

public extension App {
    static func main() {
        let app = Self.init()

        do {
            let host = WinSwiftUIWindowHost(configuration: app.body.makeWindowConfiguration())
            _ = try host.run()
        } catch {
            print("Failed to start WinSwiftUI app: \(error)")
        }
    }
}

@MainActor
public struct WindowGroup: Scene {
    public typealias Body = Never

    private let configuration: WindowGroupConfiguration

    public init(
        _ title: String = "WinSwiftUI",
        size: IntSize = IntSize(width: 1280, height: 720),
        clearColor: Color = Color(red: 0.07, green: 0.10, blue: 0.14, alpha: 1.0),
        @ViewBuilder content: () -> [AnyView]
    ) {
        self.configuration = WindowGroupConfiguration(
            title: title,
            size: size,
            clearColor: clearColor,
            content: content()
        )
    }

    public var body: Never {
        fatalError("WindowGroup has no body")
    }

    public func makeWindowConfiguration() -> WindowGroupConfiguration {
        configuration
    }
}

public struct WindowGroupConfiguration {
    public var title: String
    public var size: IntSize
    public var clearColor: Color
    public var content: [AnyView]

    public init(title: String, size: IntSize, clearColor: Color, content: [AnyView]) {
        self.title = title
        self.size = size
        self.clearColor = clearColor
        self.content = content
    }
}

@MainActor
final class WinSwiftUIWindowHost: WindowDelegate {
    private enum PresentationBackend {
        case frame
        case batch
    }

    private let configuration: WindowGroupConfiguration
    private let window: Win32Window
    private let renderer: any RenderBackend
    private let batchRenderer: (any BatchRenderBackend)?
    private let runtime: RetainedViewRuntime
    private let componentHost: ComponentHost
    private let surfaceDescriptorProvider: @MainActor (Win32Window) -> SurfaceDescriptor?
    private let inputRateTracker = WindowInputRateTracker()

    private var isRendererReady = false
    private var activeBackend: PresentationBackend = .frame
    private var surfaceDescriptor: SurfaceDescriptor?
    private var pendingPresentation = false

    /// Batching flag: when true, a reload has already been scheduled for the
    /// next main-actor turn and additional change notifications are coalesced.
    private var reloadScheduled = false

    /// Set of ObjectIdentifiers for which we currently hold observation tokens.
    /// Tracked so we can match incoming change notifications to the
    /// ComponentHost's dependency set and skip rebuilds for unrelated objects.
    private var observedObjectTokens: [ObjectIdentifier: ObservationToken] = [:]

    /// Accumulates the identifiers of observable objects that triggered change
    /// notifications during the current batched window.  When the deferred
    /// reload fires, only rebuild if the ComponentHost actually depends on at
    /// least one of them.
    private var pendingChangedObjects: Set<ObjectIdentifier> = []

    /// Optional callback for recording timer state changes, used for testing.
    /// Called whenever `syncAnimationDriver` updates timer configuration.
    var onTimerStateChanged: ((TimerState) -> Void)?

    /// Current timer state for observability. Updated by `syncAnimationDriver`.
    private(set) var currentTimerState: TimerState = TimerState(
        isEnabled: false,
        intervalMilliseconds: 16,
        usesHighResolution: false,
        refreshRate: 60
    )

    init(
        configuration: WindowGroupConfiguration,
        renderer: any RenderBackend = DefaultRenderBackendFactory.make(),
        batchRenderer: (any BatchRenderBackend)? = DefaultRenderBackendFactory.makeBatchBackend(),
        surfaceDescriptorProvider: @escaping @MainActor (Win32Window) -> SurfaceDescriptor? = WinSwiftUIWindowHost.defaultSurfaceDescriptor
    ) {
        self.configuration = configuration
        self.window = Win32Window(title: configuration.title, clientSize: configuration.size)
        self.renderer = renderer
        self.batchRenderer = batchRenderer
        self.surfaceDescriptorProvider = surfaceDescriptorProvider
        self.runtime = RetainedViewRuntime(clearColor: configuration.clearColor, root: ViewNode())
        self.componentHost = ComponentHost(runtime: runtime)

        runtime.setRootSize(configuration.size)
        componentHost.setComponents { [weak self] in
            guard let self else {
                return []
            }

            return [self.buildRootComponent()]
        }
        window.delegate = self
    }

    @discardableResult
    func run() throws -> Int32 {
        try Win32Application.run(window: window)
    }

    func windowDidCreate(_ window: Win32Window) {
        do {
            guard let surface = surfaceDescriptorProvider(window) else {
                return
            }

            surfaceDescriptor = surface
            try attachPreferredRenderer(to: surface)
            isRendererReady = true
            runtime.displayScale = surface.scaleFactor
            runtime.setRootSize(logicalSize(for: surface))
            componentHost.reload()
            renderCurrentFrame(in: window)
        } catch {
            report(error)
        }
    }

    func window(_ window: Win32Window, didResizeTo size: IntSize) {
        do {
            runtime.displayScale = window.scaleFactor
            surfaceDescriptor?.pixelSize = size
            runtime.setRootSize(logicalSize(for: size, scaleFactor: window.scaleFactor))
            componentHost.reload()
            try resizeActiveRenderer(to: size, in: window)
            requestFrame(in: window)
        } catch {
            report(error)
        }
    }

    func windowNeedsDisplay(_ window: Win32Window) {
        renderCurrentFrame(in: window)
    }

    func window(_ window: Win32Window, pointerMovedTo point: Point) {
        runtime.pointerMoved(to: logicalPoint(point, scaleFactor: window.scaleFactor))
        commitRuntimeState(in: window, interactive: true)
    }

    func windowPointerDidLeave(_ window: Win32Window) {
        runtime.pointerExitedWindow()
        commitRuntimeState(in: window, interactive: true)
    }

    func window(_ window: Win32Window, mouseWheelAt point: Point, delta: Double) {
        runtime.mouseWheel(at: logicalPoint(point, scaleFactor: window.scaleFactor), delta: delta)
        commitRuntimeState(in: window, interactive: true)
    }

    func window(_ window: Win32Window, horizontalScrollAt point: Point, delta: Double) {
        runtime.mouseWheel(at: logicalPoint(point, scaleFactor: window.scaleFactor), delta: delta, axis: .horizontal)
        commitRuntimeState(in: window, interactive: true)
    }

    func window(_ window: Win32Window, leftMouseDownAt point: Point) {
        runtime.pointerDown(at: logicalPoint(point, scaleFactor: window.scaleFactor))
        commitRuntimeState(in: window, interactive: true)
    }

    func window(_ window: Win32Window, leftMouseUpAt point: Point) {
        runtime.pointerUp(at: logicalPoint(point, scaleFactor: window.scaleFactor))
        commitRuntimeState(in: window, interactive: true)
    }

    func window(_ window: Win32Window, keyDown event: KeyboardEvent) {
        runtime.keyDown(event)
        commitRuntimeState(in: window, interactive: true)
    }

    func windowDidLoseKeyboardFocus(_ window: Win32Window) {
        runtime.keyboardFocusDidLeaveWindow()
        commitRuntimeState(in: window, interactive: true)
    }

    func window(_ window: Win32Window, animationFrameAt timestamp: Double) {
        let didAdvanceAnimations = runtime.tickAnimations(at: timestamp)
        if didAdvanceAnimations || runtime.isDirty || pendingPresentation {
            renderCurrentFrame(in: window, timestamp: timestamp)
        } else {
            syncAnimationDriver(for: window)
        }
    }

    func windowDidChangeDisplay(_ window: Win32Window) {
        syncAnimationDriver(for: window)
    }

    func windowDidChangeSystemSettings(_ window: Win32Window) {
        syncAnimationDriver(for: window)
    }

    func windowWillClose(_ window: Win32Window) {}

    private var buildContext: ViewBuildContext {
        ViewBuildContext(
            canvasSizeProvider: { [weak self] in
                self?.runtime.root.frame.size ?? Size(
                    width: Double(self?.configuration.size.width ?? 0),
                    height: Double(self?.configuration.size.height ?? 0)
                )
            },
            invalidateHandler: { [weak self] in
                self?.reloadContent()
            },
            observedObjectHandler: { [weak self] object in
                self?.observe(object)
            }
        )
    }

    private func buildRootComponent() -> Component {
        composeComponent(from: configuration.content, context: buildContext)
    }

    private func reloadContent() {
        // Record the objects the ComponentHost accesses during this rebuild
        // so future notifications can be dependency-checked.
        componentHost.observedObjects.removeAll()
        resetObservedObjects()
        componentHost.reload()

        // After rebuild, snapshot which objects were observed.
        for identifier in observedObjectTokens.keys {
            componentHost.observedObjects.insert(identifier)
        }

        commitRuntimeState(in: window)
    }

    private func observe(_ object: any ObservableObject) {
        let identifier = ObjectIdentifier(object)
        guard observedObjectTokens[identifier] == nil else {
            return
        }

        observedObjectTokens[identifier] = ObservableObjectCenter.shared.addObserver(for: object) { [weak self] in
            self?.scheduleObservedObjectReload(for: identifier)
        }
    }

    private func resetObservedObjects() {
        let tokens = Array(observedObjectTokens.values)
        observedObjectTokens.removeAll()
        for token in tokens {
            token.cancel()
        }
    }

    /// Schedule a batched reload.  Multiple rapid @Published changes within
    /// the same run-loop turn are coalesced into a single rebuild.
    ///
    /// Additionally, when the deferred reload fires, we check whether the
    /// ComponentHost actually depends on any of the objects that changed.  If
    /// none of the changed objects are in the host's dependency set, the
    /// rebuild is skipped entirely.
    private func scheduleObservedObjectReload(for changedObjectID: ObjectIdentifier) {
        pendingChangedObjects.insert(changedObjectID)

        guard !reloadScheduled else {
            return
        }

        reloadScheduled = true
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            self.reloadScheduled = false

            // Dependency tracking: only rebuild if the ComponentHost actually
            // observed at least one of the changed objects.
            let relevantChanges = self.pendingChangedObjects
            self.pendingChangedObjects.removeAll()

            let dependsOnChangedObject = self.componentHost.observedObjects.isEmpty
                || !relevantChanges.isDisjoint(with: self.componentHost.observedObjects)

            guard dependsOnChangedObject else {
                return
            }

            self.reloadContent()
        }
    }

    private func commitRuntimeState(in window: Win32Window, interactive: Bool = false) {
        let needsPresentation = runtime.isDirty || pendingPresentation

        if interactive && needsPresentation {
            inputRateTracker.recordInput()
        }

        guard needsPresentation || inputRateTracker.isHighRate else {
            syncAnimationDriver(for: window)
            return
        }

        requestFrame(in: window)
    }

    private func requestFrame(in window: Win32Window) {
        let wasPending = pendingPresentation
        pendingPresentation = true
        syncAnimationDriver(for: window)
        if !wasPending {
            window.invalidate()
        }
    }

    private func renderCurrentFrame(in window: Win32Window, timestamp: Double? = nil) {
        guard isRendererReady else {
            if runtime.isDirty || pendingPresentation {
                window.invalidate()
            }
            return
        }

        guard runtime.isDirty || pendingPresentation || runtime.hasActiveAnimations || inputRateTracker.isHighRate else {
            syncAnimationDriver(for: window)
            return
        }

        do {
            if activeBackend == .batch, let batchRenderer {
                try batchRenderer.render(scene: runtime.renderScene(at: timestamp ?? 0))
            } else {
                try renderer.render(frame: runtime.renderFrame(at: timestamp ?? 0))
            }
        } catch {
            do {
                try fallbackToFrameRenderer(becauseOf: error, in: window)
                try renderer.render(frame: runtime.renderFrame(at: timestamp ?? 0))
            } catch {
                report(error)
            }
        }

        pendingPresentation = runtime.isDirty || runtime.hasActiveAnimations || inputRateTracker.isHighRate
        syncAnimationDriver(for: window)
    }

    private func syncAnimationDriver(for window: Win32Window) {
        let refreshRate = max(Int(window.monitorRefreshRate), 1)
        runtime.minimumFrameInterval = 1.0 / Double(refreshRate)
        window.useHighResolutionTimer = true
        let intervalMilliseconds = UInt32(max(1, Int((1000.0 / Double(refreshRate)).rounded())))
        let shouldDriveFrames = runtime.hasActiveAnimations || runtime.isDirty || pendingPresentation || inputRateTracker.isHighRate
        window.setAnimationTimerEnabled(shouldDriveFrames, intervalMilliseconds: intervalMilliseconds)

        // Record timer state for observability (testing and debugging)
        let newState = TimerState(
            isEnabled: shouldDriveFrames,
            intervalMilliseconds: intervalMilliseconds,
            usesHighResolution: true,
            refreshRate: UInt32(refreshRate)
        )
        currentTimerState = newState
        onTimerStateChanged?(newState)
    }

    private func logicalSize(for surface: SurfaceDescriptor) -> IntSize {
        logicalSize(for: surface.pixelSize, scaleFactor: surface.scaleFactor)
    }

    private func logicalSize(for pixelSize: IntSize, scaleFactor: Double) -> IntSize {
        let logicalScale = max(scaleFactor, 1.0)
        return IntSize(
            width: Int32((Double(pixelSize.width) / logicalScale).rounded(.toNearestOrAwayFromZero)),
            height: Int32((Double(pixelSize.height) / logicalScale).rounded(.toNearestOrAwayFromZero))
        )
    }

    private func logicalPoint(_ point: Point, scaleFactor: Double) -> Point {
        guard scaleFactor > 0 else {
            return point
        }

        return Point(x: point.x / scaleFactor, y: point.y / scaleFactor)
    }

    private static func defaultSurfaceDescriptor(for window: Win32Window) -> SurfaceDescriptor? {
        guard let handle = window.nativeHandle else {
            return nil
        }

        return SurfaceDescriptor(
            windowHandle: handle,
            pixelSize: window.currentClientSize(),
            scaleFactor: window.scaleFactor
        )
    }

    private func attachPreferredRenderer(to surface: SurfaceDescriptor) throws {
        if let batchRenderer {
            do {
                try batchRenderer.attach(to: surface)
                activeBackend = .batch
                return
            } catch {
                report("Batch renderer attach failed; falling back to frame renderer. \(error)")
            }
        }

        try renderer.attach(to: surface)
        activeBackend = .frame
    }

    private func resizeActiveRenderer(to size: IntSize, in window: Win32Window) throws {
        if activeBackend == .batch, let batchRenderer {
            do {
                try batchRenderer.resize(to: size)
                return
            } catch {
                try fallbackToFrameRenderer(becauseOf: error, in: window)
            }
        }

        try renderer.resize(to: size)
    }

    private func fallbackToFrameRenderer(becauseOf error: Error, in window: Win32Window) throws {
        report("Batch renderer failed; switching to frame renderer. \(error)")

        let surface = surfaceDescriptor ?? surfaceDescriptorProvider(window)
        guard let surface else {
            throw error
        }

        surfaceDescriptor = surface
        try renderer.attach(to: surface)
        try renderer.resize(to: surface.pixelSize)
        activeBackend = .frame
        isRendererReady = true
    }

    private func report(_ error: Error) {
        print("[WinSwiftUI] \(error)")
    }

    private func report(_ message: String) {
        print("[WinSwiftUI] \(message)")
    }
}

@MainActor
private final class WindowInputRateTracker {
    private var timestamps: [TimeInterval] = []
    private let windowDuration: TimeInterval = 0.1
    private let inputsPerSecond = 60.0
    private let sustainDuration: TimeInterval = 1.0
    private var sustainUntil: TimeInterval = 0

    func recordInput(at timestamp: TimeInterval = Win32Window.currentTimestampSeconds()) {
        timestamps.append(timestamp)
        prune(before: timestamp - windowDuration)

        let minEvents = Int((inputsPerSecond * windowDuration).rounded(.down))
        if timestamps.count >= max(minEvents, 1) {
            sustainUntil = timestamp + sustainDuration
        }
    }

    var isHighRate: Bool {
        Win32Window.currentTimestampSeconds() < sustainUntil
    }

    private func prune(before threshold: TimeInterval) {
        timestamps.removeAll { $0 < threshold }
    }
}

// MARK: - Timer State Observability

/// Immutable snapshot of animation timer state for observability.
/// Captures the configuration determined by `syncAnimationDriver`.
@MainActor
public struct TimerState: Equatable, Sendable {
    /// Whether the animation timer is currently enabled.
    public let isEnabled: Bool

    /// Timer interval in milliseconds (determined by refresh rate).
    public let intervalMilliseconds: UInt32

    /// Whether high-resolution timer mode is active.
    public let usesHighResolution: Bool

    /// The refresh rate used to calculate the timer interval.
    public let refreshRate: UInt32

    public init(
        isEnabled: Bool,
        intervalMilliseconds: UInt32,
        usesHighResolution: Bool,
        refreshRate: UInt32
    ) {
        self.isEnabled = isEnabled
        self.intervalMilliseconds = intervalMilliseconds
        self.usesHighResolution = usesHighResolution
        self.refreshRate = refreshRate
    }
}
