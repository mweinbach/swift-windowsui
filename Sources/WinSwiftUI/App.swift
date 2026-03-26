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
    private let configuration: WindowGroupConfiguration
    private let window: Win32Window
    private let renderer: any RenderBackend
    private let batchRenderer: (any BatchRenderBackend)?
    private let runtime: RetainedViewRuntime
    private let componentHost: ComponentHost
    private let surfaceDescriptorProvider: @MainActor (Win32Window) -> SurfaceDescriptor?

    private var isRendererReady = false

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
        componentHost.setContent(buildRootComponent())
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

            if let batchRenderer {
                try batchRenderer.attach(to: surface)
            } else {
                try renderer.attach(to: surface)
            }
            isRendererReady = true
            runtime.displayScale = surface.scaleFactor
            runtime.setRootSize(logicalSize(for: surface))
            componentHost.reload()
            syncAnimationDriver(for: window)
            renderCurrentFrame(in: window)
        } catch {
            report(error)
        }
    }

    func window(_ window: Win32Window, didResizeTo size: IntSize) {
        do {
            runtime.displayScale = window.scaleFactor
            runtime.setRootSize(logicalSize(for: size, scaleFactor: window.scaleFactor))
            componentHost.reload()
            if let batchRenderer {
                try batchRenderer.resize(to: size)
            } else {
                try renderer.resize(to: size)
            }
            renderCurrentFrame(in: window)
        } catch {
            report(error)
        }
    }

    func windowNeedsDisplay(_ window: Win32Window) {
        renderCurrentFrame(in: window)
    }

    func window(_ window: Win32Window, pointerMovedTo point: Point) {
        runtime.pointerMoved(to: logicalPoint(point, scaleFactor: window.scaleFactor))
        commitRuntimeState(in: window)
    }

    func windowPointerDidLeave(_ window: Win32Window) {
        runtime.pointerExitedWindow()
        commitRuntimeState(in: window)
    }

    func window(_ window: Win32Window, mouseWheelAt point: Point, delta: Double) {
        runtime.mouseWheel(at: logicalPoint(point, scaleFactor: window.scaleFactor), delta: delta)
        commitRuntimeState(in: window)
    }

    func window(_ window: Win32Window, leftMouseDownAt point: Point) {
        runtime.pointerDown(at: logicalPoint(point, scaleFactor: window.scaleFactor))
        commitRuntimeState(in: window)
    }

    func window(_ window: Win32Window, leftMouseUpAt point: Point) {
        runtime.pointerUp(at: logicalPoint(point, scaleFactor: window.scaleFactor))
        commitRuntimeState(in: window)
    }

    func window(_ window: Win32Window, keyDown event: KeyboardEvent) {
        runtime.keyDown(event)
        commitRuntimeState(in: window)
    }

    func windowDidLoseKeyboardFocus(_ window: Win32Window) {
        runtime.keyboardFocusDidLeaveWindow()
        commitRuntimeState(in: window)
    }

    func window(_ window: Win32Window, animationFrameAt timestamp: Double) {
        let didAdvanceAnimations = runtime.tickAnimations(at: timestamp)
        syncAnimationDriver(for: window)
        if didAdvanceAnimations || runtime.isDirty {
            renderCurrentFrame(in: window)
        }
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

    private func commitRuntimeState(in window: Win32Window) {
        syncAnimationDriver(for: window)
        if runtime.isDirty {
            renderCurrentFrame(in: window)
        }
    }

    private func renderCurrentFrame(in window: Win32Window) {
        guard isRendererReady else {
            if runtime.isDirty {
                window.invalidate()
            }
            return
        }

        do {
            if let batchRenderer {
                try batchRenderer.render(scene: runtime.renderScene())
            } else {
                try renderer.render(frame: runtime.renderFrame())
            }
        } catch {
            report(error)
        }
    }

    private func syncAnimationDriver(for window: Win32Window) {
        window.setAnimationTimerEnabled(runtime.hasActiveAnimations)
    }

    private func logicalSize(for surface: SurfaceDescriptor) -> IntSize {
        logicalSize(for: surface.pixelSize, scaleFactor: surface.scaleFactor)
    }

    private func logicalSize(for pixelSize: IntSize, scaleFactor: Double) -> IntSize {
        IntSize(
            width: Int32((Double(pixelSize.width) / max(scaleFactor, 1.0)).rounded(.down)),
            height: Int32((Double(pixelSize.height) / max(scaleFactor, 1.0)).rounded(.down))
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

    private func report(_ error: Error) {
        print("[WinSwiftUI] \(error)")
    }
}
