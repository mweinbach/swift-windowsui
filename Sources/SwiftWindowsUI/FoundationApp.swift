import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsLayout
import SwiftWindowsPlatform

@MainActor
public final class FoundationApp: WindowDelegate {
    private let window: Win32Window
    private let renderer: any RenderBackend
    private let runtime: RetainedViewRuntime
    private let componentHost: ComponentHost
    private let surfaceDescriptorProvider: @MainActor (Win32Window) -> SurfaceDescriptor?
    private let textBackendLabel: String

    private var selectedModule: DemoModule
    private var interactionCount: Int
    private var lastAction: String
    private var recentEvents: [String]
    private var isRendererReady = false

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
        self.componentHost = ComponentHost(runtime: runtime)
        self.textBackendLabel = TextSystem.capabilities().renderingLabel
        self.selectedModule = .layout
        self.interactionCount = 0
        self.lastAction = "READY"
        self.recentEvents = [
            "SYSTEM READY",
            "D3D11 PIPELINE ONLINE",
            "TEXT BACKEND \(textBackendLabel)"
        ]

        componentHost.setComponents { [weak self] in
            self?.makeDemoComponents() ?? []
        }

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
            isRendererReady = true
            runtime.setRootSize(surface.pixelSize)
            componentHost.reload()
            syncAnimationDriver(for: window)
            renderCurrentFrame(in: window)
        } catch {
            report(error)
        }
    }

    public func window(_ window: Win32Window, didResizeTo size: IntSize) {
        do {
            runtime.setRootSize(size)
            componentHost.reload()
            try renderer.resize(to: size)
            renderCurrentFrame(in: window)
        } catch {
            report(error)
        }
    }

    public func windowNeedsDisplay(_ window: Win32Window) {
        renderCurrentFrame(in: window)
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
            renderCurrentFrame(in: window)
        }
    }

    public func windowWillClose(_ window: Win32Window) {}

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
            try renderer.render(frame: runtime.renderFrame())
        } catch {
            report(error)
        }
    }

    private func rebuildDemo() {
        componentHost.reload()
        commitRuntimeState(in: window)
    }

    private func selectModule(_ module: DemoModule) {
        selectedModule = module
        interactionCount += 1
        lastAction = "SELECTED \(module.label)"
        recordEvent(lastAction)
        rebuildDemo()
    }

    private func cycleModule() {
        let allModules = DemoModule.allCases
        guard let currentIndex = allModules.firstIndex(of: selectedModule) else {
            return
        }

        let nextIndex = allModules.index(after: currentIndex)
        let nextModule = nextIndex == allModules.endIndex ? allModules[allModules.startIndex] : allModules[nextIndex]
        selectModule(nextModule)
    }

    private func performAction(_ action: String) {
        interactionCount += 1
        lastAction = action
        recordEvent(action)
        rebuildDemo()
    }

    private func recordEvent(_ event: String) {
        recentEvents.insert(event, at: 0)
        if recentEvents.count > 12 {
            recentEvents.removeLast(recentEvents.count - 12)
        }
    }

    private func makeDemoComponents() -> [Component] {
        let layout = DemoLayout(size: effectiveCanvasSize)

        return UI.group {
            UI.panel(frame: layout.backgroundAccentA, backgroundColor: selectedModule.glowColor, cornerRadius: 44)
            UI.panel(frame: layout.backgroundAccentB, backgroundColor: selectedModule.stripeColor, cornerRadius: 34)
            buildToolbar(layout)
            buildSidebar(layout)
            buildHeroSection(layout)
            buildStatsRow(layout)
            buildActivitySection(layout)
            buildRightRail(layout)
        }
    }

    private var effectiveCanvasSize: Size {
        let size = runtime.root.frame.size
        if size.width > 0, size.height > 0 {
            return size
        }

        return Size(width: 1280, height: 720)
    }

    private func buildToolbar(_ layout: DemoLayout) -> Component {
        UI.toolbar(frame: layout.toolbarFrame) {
            UI.stackPanel(
                preferredSize: Size(width: 240, height: 36),
                stackLayout: .vertical(spacing: 4, alignment: .leading),
                isHitTestVisible: false
            ) {
                UI.label("SWIFT WINDOWS UI", color: .white, scale: 1.8, alignment: .leading)
                UI.label("CUSTOM WINDOWS RENDER ENGINE", color: Color(red: 0.75, green: 0.86, blue: 0.97, alpha: 0.82), scale: 1.0, alignment: .leading)
            }

            UI.panel(
                preferredSize: Size(width: layout.searchWidth, height: 38),
                backgroundColor: Color(red: 0.17, green: 0.22, blue: 0.30, alpha: 0.98),
                borderColor: Color(red: 0.82, green: 0.89, blue: 0.97, alpha: 0.12),
                borderWidth: 1,
                cornerRadius: 19,
                layoutMode: .stack(.vertical(alignment: .leading, mainAlignment: .center)),
                isHitTestVisible: false
            ) {
                UI.label("SEARCH COMMANDS", color: Color(red: 0.80, green: 0.88, blue: 0.97, alpha: 0.80), scale: 1.2, alignment: .leading, insets: EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 8))
            }

            UI.button(
                title: textBackendLabel,
                preferredSize: Size(width: 138, height: 38),
                cornerRadius: 19,
                palette: SurfacePalette(
                    idle: Color(red: 0.22, green: 0.32, blue: 0.27, alpha: 0.98),
                    focused: Color(red: 0.30, green: 0.44, blue: 0.38, alpha: 1.0),
                    pressed: Color(red: 0.79, green: 0.92, blue: 0.87, alpha: 1.0)
                ),
                titleScale: 1.2,
                action: { [weak self] in self?.performAction("TEXT STACK READY") }
            )

            UI.button(
                title: "EVENTS \(interactionCount)",
                preferredSize: Size(width: 118, height: 38),
                cornerRadius: 19,
                palette: SurfacePalette(
                    idle: Color(red: 0.24, green: 0.28, blue: 0.40, alpha: 0.98),
                    focused: Color(red: 0.33, green: 0.38, blue: 0.55, alpha: 1.0),
                    pressed: Color(red: 0.83, green: 0.88, blue: 0.99, alpha: 1.0)
                ),
                titleScale: 1.2,
                action: { [weak self] in self?.performAction("EVENT HUD OPENED") }
            )

            UI.button(
                title: selectedModule.statusLabel,
                preferredSize: Size(width: 156, height: 38),
                cornerRadius: 19,
                palette: selectedModule.statusPalette,
                titleScale: 1.2,
                action: { [weak self] in self?.cycleModule() }
            )
        }
    }

    private func buildSidebar(_ layout: DemoLayout) -> Component {
        UI.section(
            title: "WORKSPACE",
            frame: layout.sidebarFrame,
            backgroundColor: Color(red: 0.12, green: 0.16, blue: 0.22, alpha: 0.98),
            borderColor: Color(red: 0.76, green: 0.84, blue: 0.93, alpha: 0.12),
            cornerRadius: 28,
            stackLayout: .vertical(
                spacing: 14,
                padding: EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18),
                alignment: .stretch
            )
        ) {
            buildModuleButton(.layout, width: layout.sidebarContentWidth)
            buildModuleButton(.input, width: layout.sidebarContentWidth)
            buildModuleButton(.animation, width: layout.sidebarContentWidth)

            UI.panel(
                preferredSize: Size(width: layout.sidebarContentWidth, height: 10),
                backgroundColor: selectedModule.stripeColor,
                cornerRadius: 5,
                isHitTestVisible: false
            )

            UI.listRow(
                title: "STATE",
                detail: lastAction,
                accentColor: selectedModule.glowColor,
                preferredSize: Size(width: layout.sidebarContentWidth, height: 72),
                action: { [weak self] in self?.performAction("STATE PANEL OPENED") }
            )

            UI.listRow(
                title: "SHORTCUTS",
                detail: "TAB AND WHEEL ROUTING",
                accentColor: selectedModule.stripeColor,
                preferredSize: Size(width: layout.sidebarContentWidth, height: 72),
                action: { [weak self] in self?.performAction("SHORTCUTS OPENED") }
            )
        }
    }

    private func buildModuleButton(_ module: DemoModule, width: Double) -> Component {
        UI.button(
            title: module.label,
            preferredSize: Size(width: width, height: 54),
            cornerRadius: 16,
            palette: module.buttonPalette(isSelected: selectedModule == module),
            action: { [weak self] in self?.selectModule(module) }
        )
    }

    private func buildHeroSection(_ layout: DemoLayout) -> Component {
        UI.section(
            title: "CONTROL CENTER",
            frame: layout.heroFrame,
            backgroundColor: Color(red: 0.15, green: 0.20, blue: 0.28, alpha: 0.98),
            borderColor: Color(red: 0.74, green: 0.86, blue: 0.96, alpha: 0.10),
            cornerRadius: 30,
            stackLayout: .vertical(
                spacing: 16,
                padding: EdgeInsets(top: 20, leading: 22, bottom: 22, trailing: 22),
                alignment: .stretch
            )
        ) {
            UI.label(selectedModule.headline, color: .white, scale: 3.0, alignment: .leading)
            UI.label(selectedModule.detailLine, color: Color(red: 0.81, green: 0.90, blue: 0.98, alpha: 0.86), scale: 1.4, alignment: .leading)

            UI.panel(
                preferredSize: Size(width: layout.heroFrame.size.width - 44, height: 12),
                backgroundColor: selectedModule.stripeColor,
                cornerRadius: 6,
                isHitTestVisible: false
            )

            UI.stackPanel(
                preferredSize: Size(width: layout.heroFrame.size.width - 44, height: 58),
                stackLayout: .horizontal(spacing: 14, alignment: .stretch),
                isHitTestVisible: false
            ) {
                UI.button(
                    title: "RUN DIAGNOSTICS",
                    preferredSize: Size(width: 192, height: 54),
                    cornerRadius: 18,
                    palette: SurfacePalette(
                        idle: Color(red: 0.27, green: 0.39, blue: 0.56, alpha: 0.98),
                        focused: Color(red: 0.36, green: 0.52, blue: 0.71, alpha: 1.0),
                        pressed: Color(red: 0.80, green: 0.90, blue: 0.99, alpha: 1.0)
                    ),
                    titleScale: 1.5,
                    action: { [weak self] in self?.performAction("DIAGNOSTICS PASSED") }
                )

                UI.button(
                    title: "SYNC SURFACES",
                    preferredSize: Size(width: 176, height: 54),
                    cornerRadius: 18,
                    palette: SurfacePalette(
                        idle: Color(red: 0.18, green: 0.52, blue: 0.56, alpha: 0.98),
                        focused: Color(red: 0.28, green: 0.66, blue: 0.70, alpha: 1.0),
                        pressed: Color(red: 0.79, green: 0.96, blue: 0.98, alpha: 1.0)
                    ),
                    titleScale: 1.5,
                    action: { [weak self] in self?.performAction("SURFACES RESYNCED") }
                )
            }
        }
    }

    private func buildStatsRow(_ layout: DemoLayout) -> Component {
        UI.stackPanel(
            frame: layout.statsFrame,
            stackLayout: .horizontal(spacing: 18, alignment: .stretch),
            isHitTestVisible: false
        ) {
            buildStatTile(title: "MODULE", value: selectedModule.label, width: layout.statTileWidth, palette: selectedModule.metricPalette, action: "MODULE TILE OPENED")
            buildStatTile(title: "TEXT", value: textBackendLabel, width: layout.statTileWidth, palette: SurfacePalette(
                idle: Color(red: 0.25, green: 0.38, blue: 0.31, alpha: 0.98),
                focused: Color(red: 0.34, green: 0.51, blue: 0.42, alpha: 1.0),
                pressed: Color(red: 0.75, green: 0.91, blue: 0.82, alpha: 1.0)
            ), action: "TEXT TILE OPENED")
            buildStatTile(title: "EVENTS", value: "\(interactionCount)", width: layout.statTileWidth, palette: SurfacePalette(
                idle: Color(red: 0.42, green: 0.31, blue: 0.23, alpha: 0.98),
                focused: Color(red: 0.58, green: 0.43, blue: 0.31, alpha: 1.0),
                pressed: Color(red: 0.99, green: 0.86, blue: 0.66, alpha: 1.0)
            ), action: "EVENT COUNTER OPENED")
        }
    }

    private func buildStatTile(title: String, value: String, width: Double, palette: SurfacePalette, action: String) -> Component {
        UI.buttonPanel(
            preferredSize: Size(width: width, height: 132),
            cornerRadius: 24,
            palette: palette,
            layoutMode: .stack(.vertical(alignment: .leading, mainAlignment: .center)),
            action: { [weak self] in self?.performAction(action) }
        ) {
            UI.stackPanel(
                preferredSize: Size(width: max(0, width - 44), height: 76),
                stackLayout: .vertical(spacing: 10, alignment: .leading, mainAlignment: .center),
                isHitTestVisible: false
            ) {
                UI.label(title, color: Color(red: 0.84, green: 0.90, blue: 0.98, alpha: 0.90), scale: 1.4, alignment: .leading)
                UI.label(value, color: .white, scale: 2.4, alignment: .leading)
            }
        }
    }

    private func buildActivitySection(_ layout: DemoLayout) -> Component {
        UI.section(
            title: "RECENT ACTIVITY",
            frame: layout.activityFrame,
            backgroundColor: Color(red: 0.14, green: 0.18, blue: 0.25, alpha: 0.98),
            borderColor: Color(red: 0.78, green: 0.86, blue: 0.95, alpha: 0.10),
            cornerRadius: 28,
            stackLayout: .vertical(
                spacing: 14,
                padding: EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18),
                alignment: .stretch
            )
        ) {
            UI.scrollPanel(
                axis: .vertical,
                preferredSize: Size(width: layout.activityFrame.size.width - 36, height: max(120, layout.activityFrame.size.height - 78)),
                backgroundColor: Color(red: 0.10, green: 0.13, blue: 0.19, alpha: 0.88),
                borderColor: Color(red: 0.76, green: 0.84, blue: 0.94, alpha: 0.08),
                borderWidth: 1,
                cornerRadius: 22,
                stackLayout: .vertical(
                    spacing: 12,
                    padding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16),
                    alignment: .stretch
                ),
                scrollStep: 44,
                isHitTestVisible: false
            ) {
                for event in recentEvents {
                    UI.listRow(
                        title: event,
                        detail: selectedModule.summary,
                        accentColor: selectedModule.glowColor,
                        preferredSize: Size(width: layout.activityFrame.size.width - 68, height: 68),
                        action: { [weak self] in self?.performAction("OPENED EVENT \(event)") }
                    )
                }
            }
        }
    }

    private func buildRightRail(_ layout: DemoLayout) -> Component {
        UI.section(
            title: "DETAILS",
            frame: layout.rightRailFrame,
            backgroundColor: Color(red: 0.13, green: 0.17, blue: 0.24, alpha: 0.98),
            borderColor: Color(red: 0.78, green: 0.86, blue: 0.95, alpha: 0.10),
            cornerRadius: 28,
            stackLayout: .vertical(
                spacing: 16,
                padding: EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18),
                alignment: .stretch
            )
        ) {
            UI.buttonPanel(
                preferredSize: Size(width: layout.rightRailContentWidth, height: 128),
                cornerRadius: 22,
                palette: selectedModule.metricPalette,
                layoutMode: .stack(.vertical(alignment: .leading, mainAlignment: .center)),
                action: { [weak self] in self?.performAction("DETAIL CARD OPENED") }
            ) {
                UI.stackPanel(
                    preferredSize: Size(width: layout.rightRailContentWidth - 40, height: 82),
                    stackLayout: .vertical(spacing: 8, alignment: .leading, mainAlignment: .center),
                    isHitTestVisible: false
                ) {
                    UI.label(selectedModule.label, color: .white, scale: 2.2, alignment: .leading)
                    UI.label(selectedModule.summary, color: Color(red: 0.83, green: 0.90, blue: 0.97, alpha: 0.90), scale: 1.2, alignment: .leading)
                    UI.label("LAST: \(lastAction)", color: Color(red: 0.90, green: 0.95, blue: 1.0, alpha: 0.76), scale: 1.0, alignment: .leading)
                }
            }

            UI.section(
                title: "QUICK ACTIONS",
                preferredSize: Size(width: layout.rightRailContentWidth, height: 252),
                backgroundColor: Color(red: 0.10, green: 0.13, blue: 0.19, alpha: 0.92),
                borderColor: Color(red: 0.76, green: 0.84, blue: 0.94, alpha: 0.08),
                shadowColor: .clear,
                cornerRadius: 22,
                stackLayout: .vertical(
                    spacing: 12,
                    padding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16),
                    alignment: .stretch
                )
            ) {
                UI.listRow(
                    title: "PROFILE LAYOUT",
                    detail: "MEASURE, PLACE, CACHE",
                    accentColor: selectedModule.glowColor,
                    preferredSize: Size(width: layout.rightRailContentWidth - 32, height: 68),
                    action: { [weak self] in self?.performAction("LAYOUT PROFILED") }
                )
                UI.listRow(
                    title: "INSPECT INPUT",
                    detail: "ROUTE POINTER AND FOCUS",
                    accentColor: selectedModule.stripeColor,
                    preferredSize: Size(width: layout.rightRailContentWidth - 32, height: 68),
                    action: { [weak self] in self?.performAction("INPUT INSPECTED") }
                )
                UI.listRow(
                    title: "QUEUE ANIMATION",
                    detail: "FRAME TIMER AND PALETTES",
                    accentColor: selectedModule.metricPalette.focused,
                    preferredSize: Size(width: layout.rightRailContentWidth - 32, height: 68),
                    action: { [weak self] in self?.performAction("ANIMATION QUEUED") }
                )
            }
        }
    }

    private struct DemoLayout {
        let size: Size
        let inset: Double = 28
        let gap: Double = 24
        let toolbarHeight: Double = 72

        var toolbarFrame: Rect {
            Rect(x: inset, y: inset, width: max(640, size.width - inset * 2), height: toolbarHeight)
        }

        var contentTop: Double {
            toolbarFrame.maxY + gap
        }

        var contentHeight: Double {
            max(320, size.height - contentTop - inset)
        }

        var sidebarWidth: Double {
            min(228, max(200, size.width * 0.18))
        }

        var rightRailWidth: Double {
            min(330, max(290, size.width * 0.25))
        }

        var sidebarFrame: Rect {
            Rect(x: inset, y: contentTop, width: sidebarWidth, height: contentHeight)
        }

        var rightRailFrame: Rect {
            Rect(x: size.width - inset - rightRailWidth, y: contentTop, width: rightRailWidth, height: contentHeight)
        }

        var centerOriginX: Double {
            sidebarFrame.maxX + gap
        }

        var centerWidth: Double {
            max(360, rightRailFrame.origin.x - gap - centerOriginX)
        }

        var heroHeight: Double {
            min(250, max(220, size.height * 0.24))
        }

        var statsHeight: Double {
            132
        }

        var activityHeight: Double {
            max(180, contentHeight - heroHeight - statsHeight - gap * 2)
        }

        var heroFrame: Rect {
            Rect(x: centerOriginX, y: contentTop, width: centerWidth, height: heroHeight)
        }

        var statsFrame: Rect {
            Rect(x: centerOriginX, y: heroFrame.maxY + gap, width: centerWidth, height: statsHeight)
        }

        var activityFrame: Rect {
            Rect(x: centerOriginX, y: statsFrame.maxY + gap, width: centerWidth, height: activityHeight)
        }

        var backgroundAccentA: Rect {
            Rect(x: centerOriginX - 60, y: contentTop + 26, width: min(320, centerWidth * 0.42), height: 150)
        }

        var backgroundAccentB: Rect {
            Rect(x: centerOriginX + centerWidth * 0.48, y: contentTop + heroHeight + 44, width: min(220, centerWidth * 0.28), height: 108)
        }

        var searchWidth: Double {
            max(180, toolbarFrame.size.width - 700)
        }

        var sidebarContentWidth: Double {
            max(120, sidebarWidth - 36)
        }

        var rightRailContentWidth: Double {
            max(220, rightRailWidth - 36)
        }

        var statTileWidth: Double {
            max(120, (centerWidth - gap * 2) / 3)
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

private enum DemoModule: CaseIterable {
    case layout
    case input
    case animation

    var label: String {
        switch self {
        case .layout:
            return "LAYOUT"
        case .input:
            return "INPUT"
        case .animation:
            return "ANIMATION"
        }
    }

    var headline: String {
        switch self {
        case .layout:
            return "PURE SWIFT LAYOUT CORE"
        case .input:
            return "POINTER AND KEYBOARD ROUTING"
        case .animation:
            return "FRAME-DRIVEN UI MOTION"
        }
    }

    var detailLine: String {
        switch self {
        case .layout:
            return "STACK  SCROLL  CLIP  INTRINSIC"
        case .input:
            return "HOVER  PRESS  FOCUS  ACTIVATE"
        case .animation:
            return "TIMERS  PALETTES  STATE  REDRAW"
        }
    }

    var summary: String {
        switch self {
        case .layout:
            return "RESPONSIVE COMPOSITION AND PANEL STRUCTURE"
        case .input:
            return "HOVER, PRESS, FOCUS, AND SCROLL ROUTING"
        case .animation:
            return "FRAME-TIMED STATE TRANSITIONS AND CHROME"
        }
    }

    var statusLabel: String {
        "MODE: \(label)"
    }

    var glowColor: Color {
        switch self {
        case .layout:
            return Color(red: 0.30, green: 0.59, blue: 0.80, alpha: 0.92)
        case .input:
            return Color(red: 0.25, green: 0.67, blue: 0.62, alpha: 0.92)
        case .animation:
            return Color(red: 0.94, green: 0.58, blue: 0.33, alpha: 0.94)
        }
    }

    var stripeColor: Color {
        switch self {
        case .layout:
            return Color(red: 0.43, green: 0.71, blue: 0.86, alpha: 0.88)
        case .input:
            return Color(red: 0.44, green: 0.78, blue: 0.73, alpha: 0.88)
        case .animation:
            return Color(red: 0.95, green: 0.71, blue: 0.38, alpha: 0.90)
        }
    }

    var metricPalette: SurfacePalette {
        switch self {
        case .layout:
            return SurfacePalette(
                idle: Color(red: 0.29, green: 0.40, blue: 0.54, alpha: 0.98),
                focused: Color(red: 0.38, green: 0.52, blue: 0.68, alpha: 1.0),
                pressed: Color(red: 0.73, green: 0.86, blue: 0.98, alpha: 1.0)
            )
        case .input:
            return SurfacePalette(
                idle: Color(red: 0.23, green: 0.46, blue: 0.48, alpha: 0.98),
                focused: Color(red: 0.31, green: 0.60, blue: 0.61, alpha: 1.0),
                pressed: Color(red: 0.77, green: 0.94, blue: 0.94, alpha: 1.0)
            )
        case .animation:
            return SurfacePalette(
                idle: Color(red: 0.47, green: 0.34, blue: 0.24, alpha: 0.98),
                focused: Color(red: 0.62, green: 0.46, blue: 0.31, alpha: 1.0),
                pressed: Color(red: 0.99, green: 0.86, blue: 0.66, alpha: 1.0)
            )
        }
    }

    var statusPalette: SurfacePalette {
        switch self {
        case .layout:
            return SurfacePalette(
                idle: Color(red: 0.22, green: 0.31, blue: 0.41, alpha: 0.96),
                focused: Color(red: 0.27, green: 0.40, blue: 0.52, alpha: 0.98),
                pressed: Color(red: 0.77, green: 0.87, blue: 0.95, alpha: 1.0),
                activated: Color(red: 0.92, green: 0.97, blue: 1.0, alpha: 1.0)
            )
        case .input:
            return SurfacePalette(
                idle: Color(red: 0.20, green: 0.35, blue: 0.38, alpha: 0.96),
                focused: Color(red: 0.27, green: 0.49, blue: 0.52, alpha: 0.98),
                pressed: Color(red: 0.73, green: 0.93, blue: 0.90, alpha: 1.0),
                activated: Color(red: 0.90, green: 0.99, blue: 0.96, alpha: 1.0)
            )
        case .animation:
            return SurfacePalette(
                idle: Color(red: 0.39, green: 0.29, blue: 0.21, alpha: 0.96),
                focused: Color(red: 0.56, green: 0.42, blue: 0.29, alpha: 0.98),
                pressed: Color(red: 0.99, green: 0.85, blue: 0.63, alpha: 1.0),
                activated: Color(red: 1.0, green: 0.95, blue: 0.84, alpha: 1.0)
            )
        }
    }

    func buttonPalette(isSelected: Bool) -> SurfacePalette {
        let base: SurfacePalette

        switch self {
        case .layout:
            base = SurfacePalette(
                idle: Color(red: 0.19, green: 0.26, blue: 0.34, alpha: 0.98),
                focused: Color(red: 0.31, green: 0.40, blue: 0.51, alpha: 1.0),
                pressed: Color(red: 0.76, green: 0.84, blue: 0.93, alpha: 1.0)
            )
        case .input:
            base = SurfacePalette(
                idle: Color(red: 0.18, green: 0.32, blue: 0.36, alpha: 0.98),
                focused: Color(red: 0.27, green: 0.45, blue: 0.49, alpha: 1.0),
                pressed: Color(red: 0.77, green: 0.91, blue: 0.92, alpha: 1.0)
            )
        case .animation:
            base = SurfacePalette(
                idle: Color(red: 0.39, green: 0.30, blue: 0.21, alpha: 0.98),
                focused: Color(red: 0.55, green: 0.42, blue: 0.29, alpha: 1.0),
                pressed: Color(red: 0.98, green: 0.84, blue: 0.66, alpha: 1.0)
            )
        }

        guard isSelected else {
            return base
        }

        return SurfacePalette(
            idle: base.focused,
            focused: base.pressed,
            pressed: base.pressed,
            activated: base.pressed
        )
    }
}
