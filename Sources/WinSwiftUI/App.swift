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

enum WindowHostInputEvent {
    case pointerMoved(point: Point, scaleFactor: Double)
    case pointerExitedWindow
    case mouseWheel(point: Point, delta: Double, axis: ScrollAxis?, scaleFactor: Double)
    case pointerDown(point: Point, scaleFactor: Double)
    case pointerUp(point: Point, scaleFactor: Double)
    case keyDown(KeyboardEvent)
    case keyboardFocusDidLeaveWindow
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
    private let sceneRenderer: @MainActor (RetainedViewRuntime, Double) -> GPUIScene
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

    /// Counter for reload tasks actually scheduled (not coalesced).
    /// Used for testing same-turn coalescing behavior.
    private(set) var scheduledReloadCount = 0

    /// Counter for reloads actually executed (after dependency filtering).
    /// Used for testing dependency filtering behavior.
    private(set) var executedReloadCount = 0

    /// Counter for deferred observed-object reload tasks that finished.
    /// Used for testing that deferred reload work was awaited and processed.
    private(set) var completedObservedObjectReloadTaskCount = 0

    /// Counter for deferred observed-object reload tasks that were rejected by
    /// the ComponentHost dependency set.
    private(set) var skippedObservedObjectReloadCount = 0

    /// Counter for observed object registrations.
    /// Used for testing dependency registration tracking.
    private(set) var observedObjectRegistrationCount = 0

    /// Set of object IDs that triggered reloads (for dependency verification).
    /// Used for testing that only relevant objects trigger reloads.
    private(set) var reloadTriggeringObjectIDs: Set<ObjectIdentifier> = []

    /// Optional callback invoked when an observed object reload is scheduled.
    /// Used for testing coalescing behavior.
    var onObservedObjectReloadScheduled: ((_ changedObjectID: ObjectIdentifier, _ coalesced: Bool) -> Void)?

    /// Optional callback invoked when an observed object is registered.
    /// Used for testing dependency registration tracking.
    var onObservedObjectRegistered: ((_ objectID: ObjectIdentifier) -> Void)?

    /// Optional callback invoked when reloadContent completes.
    /// Used for testing rebuild/presentation counts.
    var onReloadContentCompleted: (() -> Void)?

    /// Optional callback invoked when a deferred observed-object reload task
    /// finishes dependency evaluation.
    /// Used for testing whether the task reloaded or was rejected.
    var onObservedObjectReloadTaskCompleted: ((_ didReload: Bool) -> Void)?

    /// Optional callback for recording timer state changes, used for testing.
    /// Called whenever `syncAnimationDriver` updates timer configuration.
    var onTimerStateChanged: ((TimerState) -> Void)?

    /// Optional callback for recording input events after the runtime consumes them.
    /// Used by host tests to prove the real WinSwiftUIWindowHost routed converted input.
    var onInputEventRouted: ((WindowHostInputEvent) -> Void)?

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
        surfaceDescriptorProvider: @escaping @MainActor (Win32Window) -> SurfaceDescriptor? = WinSwiftUIWindowHost.defaultSurfaceDescriptor,
        sceneRenderer: (@MainActor (RetainedViewRuntime, Double) -> GPUIScene)? = nil
    ) {
        self.configuration = configuration
        self.window = Win32Window(title: configuration.title, clientSize: configuration.size)
        self.renderer = renderer
        self.batchRenderer = batchRenderer
        self.surfaceDescriptorProvider = surfaceDescriptorProvider
        self.runtime = RetainedViewRuntime(clearColor: configuration.clearColor, root: ViewNode())
        self.componentHost = ComponentHost(runtime: runtime)
        self.sceneRenderer = sceneRenderer ?? { runtime, timestamp in
            runtime.renderScene(at: timestamp)
        }

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
            let scaleFactor = window.scaleFactor
            runtime.displayScale = scaleFactor
            surfaceDescriptor?.pixelSize = size
            surfaceDescriptor?.scaleFactor = scaleFactor
            runtime.setRootSize(logicalSize(for: size, scaleFactor: scaleFactor))
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
        let scaleFactor = window.scaleFactor
        let logicalPoint = logicalPoint(point, scaleFactor: scaleFactor)
        runtime.pointerMoved(to: logicalPoint)
        onInputEventRouted?(.pointerMoved(point: logicalPoint, scaleFactor: scaleFactor))
        commitRuntimeState(in: window, interactive: true)
    }

    func windowPointerDidLeave(_ window: Win32Window) {
        runtime.pointerExitedWindow()
        onInputEventRouted?(.pointerExitedWindow)
        commitRuntimeState(in: window, interactive: true)
    }

    func window(_ window: Win32Window, mouseWheelAt point: Point, delta: Double) {
        let scaleFactor = window.scaleFactor
        let logicalPoint = logicalPoint(point, scaleFactor: scaleFactor)
        runtime.mouseWheel(at: logicalPoint, delta: delta)
        onInputEventRouted?(.mouseWheel(point: logicalPoint, delta: delta, axis: nil, scaleFactor: scaleFactor))
        commitRuntimeState(in: window, interactive: true)
    }

    func window(_ window: Win32Window, horizontalScrollAt point: Point, delta: Double) {
        let scaleFactor = window.scaleFactor
        let logicalPoint = logicalPoint(point, scaleFactor: scaleFactor)
        runtime.mouseWheel(at: logicalPoint, delta: delta, axis: .horizontal)
        onInputEventRouted?(.mouseWheel(point: logicalPoint, delta: delta, axis: .horizontal, scaleFactor: scaleFactor))
        commitRuntimeState(in: window, interactive: true)
    }

    func window(_ window: Win32Window, leftMouseDownAt point: Point) {
        let scaleFactor = window.scaleFactor
        let logicalPoint = logicalPoint(point, scaleFactor: scaleFactor)
        runtime.pointerDown(at: logicalPoint)
        onInputEventRouted?(.pointerDown(point: logicalPoint, scaleFactor: scaleFactor))
        commitRuntimeState(in: window, interactive: true)
    }

    func window(_ window: Win32Window, leftMouseUpAt point: Point) {
        let scaleFactor = window.scaleFactor
        let logicalPoint = logicalPoint(point, scaleFactor: scaleFactor)
        runtime.pointerUp(at: logicalPoint)
        onInputEventRouted?(.pointerUp(point: logicalPoint, scaleFactor: scaleFactor))
        commitRuntimeState(in: window, interactive: true)
    }

    func window(_ window: Win32Window, keyDown event: KeyboardEvent) {
        runtime.keyDown(event)
        onInputEventRouted?(.keyDown(event))
        commitRuntimeState(in: window, interactive: true)
    }

    func windowDidLoseKeyboardFocus(_ window: Win32Window) {
        runtime.keyboardFocusDidLeaveWindow()
        onInputEventRouted?(.keyboardFocusDidLeaveWindow)
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
                self?.observeObject(object)
            }
        )
    }

    private func buildRootComponent() -> Component {
        composeComponent(from: configuration.content, context: buildContext)
    }

    private func reloadContent() {
        executedReloadCount += 1

        // Record the objects the ComponentHost accesses during this rebuild
        // so future notifications can be dependency-checked.
        componentHost.observedObjects.removeAll()
        resetObservedObjects()
        componentHost.reload()

        // After rebuild, snapshot which objects were observed.
        for identifier in observedObjectTokens.keys {
            componentHost.observedObjects.insert(identifier)
        }

        onReloadContentCompleted?()
        commitRuntimeState(in: window)
    }

    /// Manually observe an object for testing purposes.
    /// This allows tests to register observed objects without needing a view hierarchy.
    func observe(_ object: any ObservableObject) {
        observeObject(object)
    }

    private func observeObject(_ object: any ObservableObject) {
        let identifier = ObjectIdentifier(object)
        guard observedObjectTokens[identifier] == nil else {
            return
        }

        observedObjectRegistrationCount += 1
        onObservedObjectRegistered?(identifier)

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

    /// Reset all observability counters. Used by tests to establish baseline.
    func resetObservabilityCounters() {
        scheduledReloadCount = 0
        executedReloadCount = 0
        completedObservedObjectReloadTaskCount = 0
        skippedObservedObjectReloadCount = 0
        observedObjectRegistrationCount = 0
        reloadTriggeringObjectIDs.removeAll()
    }

    /// Current logical root size exposed for host-focused tests.
    var currentLogicalRootSize: IntSize {
        IntSize(
            width: Int32(runtime.root.frame.size.width),
            height: Int32(runtime.root.frame.size.height)
        )
    }

    /// Current display scale exposed for host-focused tests.
    var currentDisplayScale: Double {
        runtime.displayScale
    }

    /// Current runtime pacing interval exposed for host-focused tests.
    var currentRuntimeMinimumFrameInterval: Double? {
        runtime.minimumFrameInterval
    }

    /// Current presenter selection exposed for host-focused tests.
    var isUsingBatchPresentationBackend: Bool {
        activeBackend == .batch
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
        reloadTriggeringObjectIDs.insert(changedObjectID)

        guard !reloadScheduled else {
            // Same-turn coalescing: reload already scheduled, just accumulate the change
            onObservedObjectReloadScheduled?(changedObjectID, true)
            return
        }

        // New reload task being scheduled (not coalesced)
        reloadScheduled = true
        scheduledReloadCount += 1
        onObservedObjectReloadScheduled?(changedObjectID, false)

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
                // Dependency filtering: none of the changed objects are in our dependency set
                // Skip the reload entirely
                self.skippedObservedObjectReloadCount += 1
                self.completedObservedObjectReloadTaskCount += 1
                self.onObservedObjectReloadTaskCompleted?(false)
                return
            }

            self.reloadContent()
            self.completedObservedObjectReloadTaskCount += 1
            self.onObservedObjectReloadTaskCompleted?(true)
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
                let scene = sceneRenderer(runtime, timestamp ?? 0)
                batchRenderer.bindResources(for: scene)
                try batchRenderer.render(scene: scene)
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
