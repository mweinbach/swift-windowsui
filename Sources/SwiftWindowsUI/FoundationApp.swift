import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsLayout
import SwiftWindowsPlatform

@MainActor
public final class FoundationApp: WindowDelegate {
    private let window: Win32Window
    private let renderer: any RenderBackend
    private let runtime: RetainedViewRuntime
    private let surfaceDescriptorProvider: @MainActor (Win32Window) -> SurfaceDescriptor?

    public convenience init(renderer: any RenderBackend) {
        self.init(renderer: renderer, surfaceDescriptorProvider: Self.defaultSurfaceDescriptor)
    }

    init(
        renderer: any RenderBackend,
        surfaceDescriptorProvider: @escaping @MainActor (Win32Window) -> SurfaceDescriptor?
    ) {
        self.window = Win32Window(title: "Swift Windows UI", clientSize: IntSize(width: 1280, height: 720))
        self.renderer = renderer
        self.surfaceDescriptorProvider = surfaceDescriptorProvider
        let root = Controls.panel()
        let runtime = RetainedViewRuntime(
            clearColor: Color(red: 0.07, green: 0.10, blue: 0.14, alpha: 1.0),
            root: root
        )
        self.runtime = runtime
        let textBackend = TextSystem.capabilities().backend.displayName

        func metricCard(title: String, value: String, palette: SurfacePalette) -> ViewNode {
            let content = Controls.stackPanel(
                preferredSize: Size(width: 184, height: 42),
                stackLayout: .vertical(spacing: 6, alignment: .leading, mainAlignment: .center),
                isHitTestVisible: false,
                children: [
                    Controls.label(title, color: Color(red: 0.84, green: 0.90, blue: 0.98, alpha: 0.92), scale: 1.4, alignment: .leading),
                    Controls.label(value, color: .white, scale: 2.2, alignment: .leading),
                ]
            )

            return Controls.button(
                runtime: runtime,
                preferredSize: Size(width: 232, height: 64),
                cornerRadius: 18,
                palette: palette,
                chrome: .elevatedButton,
                layoutMode: .stack(.vertical(alignment: .leading, mainAlignment: .center)),
                children: [content]
            )
        }

        let heroCard = Controls.panel(
            frame: Rect(x: 72, y: 80, width: 520, height: 320),
            backgroundColor: Color(red: 0.15, green: 0.20, blue: 0.28, alpha: 1.0),
            borderColor: Color(red: 0.74, green: 0.86, blue: 0.96, alpha: 0.10),
            borderWidth: 1,
            shadowColor: Color(red: 0.01, green: 0.03, blue: 0.06, alpha: 0.26),
            shadowOffset: Point(x: 0, y: 16),
            shadowSpread: 8,
            cornerRadius: 28,
            clipsToBounds: true
        )

        let heroContent = Controls.stackPanel(
            frame: Rect(x: 34, y: 28, width: 452, height: 150),
            stackLayout: .vertical(spacing: 12, alignment: .leading),
            isHitTestVisible: false,
            children: [
                Controls.label("SWIFT WINDOWS UI", color: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 1.0), scale: 3.6, alignment: .leading),
                Controls.label("PURE SWIFT D3D11 ENGINE", color: Color(red: 0.74, green: 0.88, blue: 0.98, alpha: 0.96), scale: 1.8, alignment: .leading),
                Controls.label("LAYOUT  INPUT  FOCUS  ANIMATION", color: Color(red: 0.86, green: 0.92, blue: 0.98, alpha: 0.84), scale: 1.4, alignment: .leading),
            ]
        )

        let heroActionRow = Controls.stackPanel(
            frame: Rect(x: 34, y: 224, width: 452, height: 56),
            stackLayout: .horizontal(spacing: 14, alignment: .stretch),
            isHitTestVisible: false,
            children: [
                Controls.button(
                    runtime: runtime,
                    title: "FOCUS LOOP",
                    preferredSize: Size(width: 170, height: 52),
                    cornerRadius: 18,
                    palette: SurfacePalette(
                        idle: Color(red: 0.25, green: 0.39, blue: 0.55, alpha: 0.98),
                        focused: Color(red: 0.35, green: 0.51, blue: 0.68, alpha: 1.0),
                        pressed: Color(red: 0.74, green: 0.88, blue: 0.97, alpha: 1.0)
                    )
                ),
                Controls.button(
                    runtime: runtime,
                    title: "GPU PATH",
                    preferredSize: Size(width: 150, height: 52),
                    cornerRadius: 18,
                    palette: SurfacePalette(
                        idle: Color(red: 0.19, green: 0.54, blue: 0.56, alpha: 0.98),
                        focused: Color(red: 0.28, green: 0.67, blue: 0.69, alpha: 1.0),
                        pressed: Color(red: 0.77, green: 0.94, blue: 0.95, alpha: 1.0)
                    )
                ),
            ]
        )

        let heroGlow = Controls.panel(
            frame: Rect(x: -32, y: 16, width: 320, height: 140),
            backgroundColor: Color(red: 0.30, green: 0.59, blue: 0.80, alpha: 0.92),
            cornerRadius: 18
        )

        let heroStripe = Controls.panel(
            frame: Rect(x: 24, y: 156, width: 620, height: 32),
            backgroundColor: Color(red: 0.43, green: 0.71, blue: 0.86, alpha: 0.88),
            cornerRadius: 16
        )

        let sideRail = Controls.panel(
            frame: Rect(x: 640, y: 80, width: 180, height: 520),
            backgroundColor: Color(red: 0.12, green: 0.16, blue: 0.22, alpha: 1.0),
            borderColor: Color(red: 0.67, green: 0.78, blue: 0.88, alpha: 0.12),
            borderWidth: 1,
            shadowColor: Color(red: 0.01, green: 0.03, blue: 0.06, alpha: 0.24),
            shadowOffset: Point(x: 0, y: 14),
            shadowSpread: 6,
            cornerRadius: 24,
            clipsToBounds: true
        )

        let railStack = Controls.stackPanel(
            frame: Rect(x: 16, y: 22, width: 148, height: 476),
            stackLayout: .vertical(spacing: 16, alignment: .stretch),
            isHitTestVisible: false,
            children: [
                Controls.label("MODULES", color: Color(red: 0.90, green: 0.95, blue: 1.0, alpha: 0.96), scale: 1.6),
                Controls.button(
                    runtime: runtime,
                    title: "LAYOUT",
                    preferredSize: Size(width: 148, height: 54),
                    cornerRadius: 16,
                    palette: SurfacePalette(
                        idle: Color(red: 0.19, green: 0.26, blue: 0.34, alpha: 0.98),
                        focused: Color(red: 0.31, green: 0.40, blue: 0.51, alpha: 1.0),
                        pressed: Color(red: 0.76, green: 0.84, blue: 0.93, alpha: 1.0)
                    )
                ),
                Controls.button(
                    runtime: runtime,
                    title: "INPUT",
                    preferredSize: Size(width: 148, height: 54),
                    cornerRadius: 16,
                    palette: SurfacePalette(
                        idle: Color(red: 0.18, green: 0.32, blue: 0.36, alpha: 0.98),
                        focused: Color(red: 0.27, green: 0.45, blue: 0.49, alpha: 1.0),
                        pressed: Color(red: 0.77, green: 0.91, blue: 0.92, alpha: 1.0)
                    )
                ),
                Controls.button(
                    runtime: runtime,
                    title: "ANIMATE",
                    preferredSize: Size(width: 148, height: 54),
                    cornerRadius: 16,
                    palette: SurfacePalette(
                        idle: Color(red: 0.39, green: 0.30, blue: 0.21, alpha: 0.98),
                        focused: Color(red: 0.55, green: 0.42, blue: 0.29, alpha: 1.0),
                        pressed: Color(red: 0.98, green: 0.84, blue: 0.66, alpha: 1.0)
                    )
                ),
            ]
        )

        let sideAccent = Controls.panel(
            frame: Rect(x: -28, y: 24, width: 220, height: 84),
            backgroundColor: Color(red: 0.96, green: 0.56, blue: 0.33, alpha: 1.0),
            cornerRadius: 18
        )

        let statusPill = Controls.button(
            runtime: runtime,
            title: "INTERACTIVE",
            frame: Rect(x: 864, y: 88, width: 280, height: 72),
            cornerRadius: 36,
            palette: SurfacePalette(
                idle: Color(red: 0.22, green: 0.31, blue: 0.41, alpha: 0.96),
                focused: Color(red: 0.27, green: 0.40, blue: 0.52, alpha: 0.98),
                pressed: Color(red: 0.96, green: 0.56, blue: 0.33, alpha: 1.0),
                activated: Color(red: 0.77, green: 0.87, blue: 0.95, alpha: 1.0)
            ),
            titleScale: 2.0
        )

        let metricsPanel = Controls.scrollPanel(
            axis: .vertical,
            frame: Rect(x: 864, y: 184, width: 280, height: 292),
            backgroundColor: Color(red: 0.13, green: 0.18, blue: 0.25, alpha: 0.98),
            borderColor: Color(red: 0.73, green: 0.84, blue: 0.94, alpha: 0.14),
            borderWidth: 1,
            shadowColor: Color(red: 0.01, green: 0.03, blue: 0.06, alpha: 0.24),
            shadowOffset: Point(x: 0, y: 16),
            shadowSpread: 7,
            cornerRadius: 26,
            stackLayout: .vertical(
                spacing: 16,
                padding: EdgeInsets(top: 24, leading: 24, bottom: 24, trailing: 24),
                alignment: .stretch
            ),
            scrollStep: 52,
            isHitTestVisible: false
        )

        let chipRow = Controls.stackPanel(
            preferredSize: Size(width: 232, height: 48),
            stackLayout: .horizontal(spacing: 12, alignment: .stretch),
            isHitTestVisible: false
        )

        let metricsHeader = Controls.label("METRICS", color: Color(red: 0.93, green: 0.97, blue: 1.0, alpha: 1.0), scale: 1.8, alignment: .leading)

        let chipA = Controls.button(
            runtime: runtime,
            title: "GPU",
            preferredSize: Size(width: 110, height: 48),
            cornerRadius: 14,
            palette: SurfacePalette(
                idle: Color(red: 0.31, green: 0.46, blue: 0.60, alpha: 1.0),
                focused: Color(red: 0.39, green: 0.57, blue: 0.73, alpha: 1.0),
                pressed: Color(red: 0.64, green: 0.79, blue: 0.89, alpha: 1.0)
            ),
            titleScale: 1.8
        )

        let chipB = Controls.button(
            runtime: runtime,
            title: "NATIVE",
            preferredSize: Size(width: 110, height: 48),
            cornerRadius: 14,
            palette: SurfacePalette(
                idle: Color(red: 0.20, green: 0.62, blue: 0.55, alpha: 0.96),
                focused: Color(red: 0.28, green: 0.71, blue: 0.63, alpha: 1.0),
                pressed: Color(red: 0.74, green: 0.90, blue: 0.84, alpha: 1.0)
            ),
            titleScale: 1.6
        )

        let metricCardA = metricCard(
            title: "RENDERER",
            value: "D3D11",
            palette: SurfacePalette(
                idle: Color(red: 0.24, green: 0.34, blue: 0.45, alpha: 1.0),
                focused: Color(red: 0.34, green: 0.46, blue: 0.58, alpha: 1.0),
                pressed: Color(red: 0.56, green: 0.68, blue: 0.80, alpha: 1.0)
            )
        )

        let metricCardB = metricCard(
            title: "FOCUS",
            value: "TAB LOOP",
            palette: SurfacePalette(
                idle: Color(red: 0.41, green: 0.54, blue: 0.72, alpha: 0.98),
                focused: Color(red: 0.49, green: 0.64, blue: 0.82, alpha: 1.0),
                pressed: Color(red: 0.78, green: 0.86, blue: 0.95, alpha: 1.0)
            )
        )

        let metricCardC = metricCard(
            title: "FRAME",
            value: "ANIMATED",
            palette: SurfacePalette(
                idle: Color(red: 0.92, green: 0.68, blue: 0.29, alpha: 0.96),
                focused: Color(red: 0.97, green: 0.77, blue: 0.41, alpha: 1.0),
                pressed: Color(red: 1.0, green: 0.89, blue: 0.67, alpha: 1.0)
            )
        )

        let metricCardD = metricCard(
            title: "TEXT",
            value: textBackend,
            palette: SurfacePalette(
                idle: Color(red: 0.24, green: 0.38, blue: 0.31, alpha: 0.98),
                focused: Color(red: 0.33, green: 0.52, blue: 0.42, alpha: 1.0),
                pressed: Color(red: 0.74, green: 0.90, blue: 0.80, alpha: 1.0)
            )
        )

        let metricCardE = metricCard(
            title: "SCROLL",
            value: "MOUSE WHEEL",
            palette: SurfacePalette(
                idle: Color(red: 0.35, green: 0.28, blue: 0.46, alpha: 0.98),
                focused: Color(red: 0.49, green: 0.38, blue: 0.63, alpha: 1.0),
                pressed: Color(red: 0.86, green: 0.79, blue: 0.95, alpha: 1.0)
            )
        )

        let footerBar = Controls.stackPanel(
            frame: Rect(x: 72, y: 440, width: 520, height: 96),
            backgroundColor: Color(red: 0.24, green: 0.30, blue: 0.37, alpha: 0.98),
            text: nil,
            borderColor: Color(red: 0.85, green: 0.90, blue: 0.96, alpha: 0.10),
            borderWidth: 1,
            shadowColor: Color(red: 0.01, green: 0.03, blue: 0.06, alpha: 0.22),
            shadowOffset: Point(x: 0, y: 14),
            shadowSpread: 6,
            cornerRadius: 22,
            stackLayout: .vertical(
                spacing: 10,
                padding: EdgeInsets(top: 18, leading: 22, bottom: 18, trailing: 22),
                alignment: .leading,
                mainAlignment: .center
            ),
            isHitTestVisible: false,
            children: [
                Controls.label("TAB TO MOVE FOCUS", color: Color(red: 0.95, green: 0.98, blue: 1.0, alpha: 1.0), scale: 1.8, alignment: .leading),
                Controls.label("ENTER OR SPACE TO ACTIVATE", color: Color(red: 0.82, green: 0.90, blue: 0.98, alpha: 0.92), scale: 1.4, alignment: .leading),
            ]
        )

        heroCard.addChild(heroGlow)
        heroCard.addChild(heroStripe)
        heroCard.addChild(heroContent)
        heroCard.addChild(heroActionRow)
        chipRow.addChild(chipA)
        chipRow.addChild(chipB)
        metricsPanel.addChild(metricsHeader)
        metricsPanel.addChild(chipRow)
        metricsPanel.addChild(metricCardA)
        metricsPanel.addChild(metricCardB)
        metricsPanel.addChild(metricCardC)
        metricsPanel.addChild(metricCardD)
        metricsPanel.addChild(metricCardE)
        sideRail.addChild(sideAccent)
        sideRail.addChild(railStack)
        root.addChild(heroCard)
        root.addChild(sideRail)
        root.addChild(statusPill)
        root.addChild(metricsPanel)
        root.addChild(footerBar)

        self.window.delegate = self
    }

    @discardableResult
    public func run() throws -> Int32 {
        try Win32Application.run(window: window)
    }

    public func windowDidCreate(_ window: Win32Window) {
        do {
            guard let surface = surfaceDescriptorProvider(window) else {
                return
            }

            try renderer.attach(to: surface)
            runtime.setRootSize(surface.pixelSize)
            syncAnimationDriver(for: window)
            window.invalidate()
        } catch {
            report(error)
        }
    }

    public func window(_ window: Win32Window, didResizeTo size: IntSize) {
        do {
            runtime.setRootSize(size)
            try renderer.resize(to: size)
            commitRuntimeState(in: window)
        } catch {
            report(error)
        }
    }

    public func windowNeedsDisplay(_ window: Win32Window) {
        do {
            try renderer.render(frame: runtime.renderFrame())
        } catch {
            report(error)
        }
    }

    public func window(_ window: Win32Window, pointerMovedTo point: Point) {
        runtime.pointerMoved(to: point)
        commitRuntimeState(in: window)
    }

    public func windowPointerDidLeave(_ window: Win32Window) {
        runtime.pointerExitedWindow()
        commitRuntimeState(in: window)
    }

    public func window(_ window: Win32Window, mouseWheelAt point: Point, delta: Double) {
        runtime.mouseWheel(at: point, delta: delta)
        commitRuntimeState(in: window)
    }

    public func window(_ window: Win32Window, leftMouseDownAt point: Point) {
        runtime.pointerDown(at: point)
        commitRuntimeState(in: window)
    }

    public func window(_ window: Win32Window, leftMouseUpAt point: Point) {
        runtime.pointerUp(at: point)
        commitRuntimeState(in: window)
    }

    public func window(_ window: Win32Window, keyDown event: KeyboardEvent) {
        runtime.keyDown(event)
        commitRuntimeState(in: window)
    }

    public func windowDidLoseKeyboardFocus(_ window: Win32Window) {
        runtime.keyboardFocusDidLeaveWindow()
        commitRuntimeState(in: window)
    }

    public func window(_ window: Win32Window, animationFrameAt timestamp: Double) {
        let didAdvanceAnimations = runtime.tickAnimations(at: timestamp)
        syncAnimationDriver(for: window)
        if didAdvanceAnimations || runtime.isDirty {
            window.invalidate()
        }
    }

    public func windowWillClose(_ window: Win32Window) {}

    private func commitRuntimeState(in window: Win32Window) {
        syncAnimationDriver(for: window)
        if runtime.isDirty {
            window.invalidate()
        }
    }

    private func syncAnimationDriver(for window: Win32Window) {
        window.setAnimationTimerEnabled(runtime.hasActiveAnimations)
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
        print("[SwiftWindowsUI] \(error)")
    }
}
