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
    private var rendererBackendLabel: String
    private var rendererStatusDescription: String

    private var selectedModule: DemoModule
    private var interactionCount: Int
    private var lastAction: String
    private var recentEvents: [String]
    private var sidebarSplitRatio: Double
    private var detailSplitRatio: Double
    private var activeLayoutProfile: DemoLayoutProfile
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
        self.rendererBackendLabel = renderer.backendDisplayName
        self.rendererStatusDescription = renderer.backendStatusDescription
        self.selectedModule = .layout
        self.interactionCount = 0
        self.lastAction = "READY"
        self.sidebarSplitRatio = 0.18
        self.detailSplitRatio = 0.72
        self.activeLayoutProfile = DemoLayoutProfile.forSize(Size(width: 1280, height: 720))
        self.recentEvents = [
            "SYSTEM READY",
            rendererStatusDescription,
            "TEXT BACKEND \(textBackendLabel)"
        ]

        componentHost.setComponents { [weak self] in
            self?.makeDemoComponents() ?? []
        }
        runtime.root.onLayout = { [weak self] bounds in
            self?.applyDemoRootLayout(in: bounds)
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
            refreshRendererStatus()
            isRendererReady = true
            runtime.displayScale = surface.scaleFactor
            runtime.setRootSize(logicalSize(for: surface))
            refreshDemoLayoutProfileIfNeeded(for: runtime.root.frame.size)
            syncAnimationDriver(for: window)
            renderCurrentFrame(in: window)
        } catch {
            report(error)
        }
    }

    public func window(_ window: Win32Window, didResizeTo size: IntSize) {
        do {
            runtime.displayScale = window.scaleFactor
            runtime.setRootSize(logicalSize(for: size, scaleFactor: window.scaleFactor))
            refreshDemoLayoutProfileIfNeeded(for: runtime.root.frame.size)
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
        runtime.pointerMoved(to: logicalPoint(point, scaleFactor: window.scaleFactor))
        commitRuntimeState(in: window)
    }

    public func windowPointerDidLeave(_ window: Win32Window) {
        runtime.pointerExitedWindow()
        commitRuntimeState(in: window)
    }

    public func window(_ window: Win32Window, mouseWheelAt point: Point, delta: Double) {
        runtime.mouseWheel(at: logicalPoint(point, scaleFactor: window.scaleFactor), delta: delta)
        commitRuntimeState(in: window)
    }

    public func window(_ window: Win32Window, leftMouseDownAt point: Point) {
        runtime.pointerDown(at: logicalPoint(point, scaleFactor: window.scaleFactor))
        commitRuntimeState(in: window)
    }

    public func window(_ window: Win32Window, leftMouseUpAt point: Point) {
        runtime.pointerUp(at: logicalPoint(point, scaleFactor: window.scaleFactor))
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

    private func refreshDemoLayoutProfileIfNeeded(for size: Size) {
        let nextLayoutProfile = DemoLayoutProfile.forSize(size)
        guard nextLayoutProfile != activeLayoutProfile else {
            return
        }

        activeLayoutProfile = nextLayoutProfile
        componentHost.reload()
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

    private func refreshRendererStatus() {
        rendererBackendLabel = renderer.backendDisplayName
        rendererStatusDescription = renderer.backendStatusDescription

        if recentEvents.isEmpty {
            recentEvents = [rendererStatusDescription]
            return
        }

        if recentEvents.count >= 2 {
            recentEvents[1] = rendererStatusDescription
            return
        }

        recentEvents.append(rendererStatusDescription)
    }

    private func makeDemoComponents() -> [Component] {
        let layout = DemoLayout(size: effectiveCanvasSize)

        return UI.group {
            UI.panel(
                frame: layout.backgroundAccentA,
                backgroundColor: selectedModule.glowColor,
                backgroundGradient: .linear(LinearGradient(startColor: selectedModule.glowColor, endColor: selectedModule.stripeColor, axis: .horizontal)),
                cornerRadius: 44
            )
            UI.panel(
                frame: layout.backgroundAccentB,
                backgroundColor: selectedModule.stripeColor,
                backgroundGradient: .linear(LinearGradient(startColor: selectedModule.stripeColor, endColor: selectedModule.glowColor, axis: .vertical)),
                cornerRadius: 34
            )
            buildToolbar(layout)
            UI.splitView(
                axis: .horizontal,
                frame: layout.bodyFrame,
                ratio: sidebarSplitRatio,
                minPrimaryExtent: layout.sidebarMinExtent,
                minSecondaryExtent: layout.bodySecondaryMinExtent,
                dividerThickness: layout.dividerThickness,
                dividerIdleColor: Color(red: 0.76, green: 0.86, blue: 0.95, alpha: 0.06),
                dividerHoverColor: Color(red: 0.58, green: 0.76, blue: 0.94, alpha: 0.16),
                dividerActiveColor: Color(red: 0.70, green: 0.86, blue: 1.0, alpha: 0.28),
                onRatioChanged: { [weak self] in self?.sidebarSplitRatio = $0 }
            ) {
                buildSidebar(layout)
            } secondary: {
                UI.splitView(
                    axis: .horizontal,
                    ratio: detailSplitRatio,
                    minPrimaryExtent: layout.centerMinExtent,
                    minSecondaryExtent: layout.detailMinExtent,
                    dividerThickness: layout.dividerThickness,
                    dividerIdleColor: Color(red: 0.76, green: 0.86, blue: 0.95, alpha: 0.05),
                    dividerHoverColor: Color(red: 0.58, green: 0.76, blue: 0.94, alpha: 0.14),
                    dividerActiveColor: Color(red: 0.70, green: 0.86, blue: 1.0, alpha: 0.24),
                    onRatioChanged: { [weak self] in self?.detailSplitRatio = $0 }
                ) {
                    buildCenterPane(layout)
                } secondary: {
                    buildRightRail(layout)
                }
            }
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
        UI.toolbar(
            frame: layout.toolbarFrame,
            backgroundGradient: .linear(LinearGradient(
                startColor: Color(red: 0.13, green: 0.17, blue: 0.24, alpha: 0.98),
                endColor: Color(red: 0.10, green: 0.14, blue: 0.20, alpha: 0.98),
                axis: .horizontal
            )),
            cornerRadius: layout.toolbarCornerRadius,
            stackLayout: .horizontal(
                spacing: layout.toolbarSpacing,
                padding: layout.toolbarPadding,
                alignment: .center,
                mainAlignment: .start
            )
        ) {
            UI.stackPanel(
                preferredSize: Size(width: layout.toolbarTitleWidth, height: layout.toolbarTitleHeight),
                layoutPriority: 1,
                stackLayout: .vertical(spacing: layout.toolbarTitleSpacing, alignment: .leading),
                isHitTestVisible: false
            ) {
                UI.label("SWIFT WINDOWS UI", color: .white, scale: layout.toolbarTitleScale, alignment: .leading, maximumNumberOfLines: 1)
                if layout.showsToolbarSubtitle {
                    UI.label(
                        "CUSTOM WINDOWS RENDER ENGINE",
                        color: Color(red: 0.75, green: 0.86, blue: 0.97, alpha: 0.82),
                        scale: layout.toolbarSubtitleScale,
                        alignment: .leading,
                        maximumNumberOfLines: 1
                    )
                }
            }

            UI.panel(
                preferredSize: Size(width: layout.toolbarSearchBaseWidth, height: layout.toolbarPillHeight),
                layoutPriority: 2,
                backgroundColor: Color(red: 0.17, green: 0.22, blue: 0.30, alpha: 0.98),
                borderColor: Color(red: 0.82, green: 0.89, blue: 0.97, alpha: 0.12),
                borderWidth: 1,
                cornerRadius: layout.toolbarPillHeight * 0.5,
                layoutMode: .stack(.horizontal(spacing: layout.toolbarSearchSpacing, padding: layout.toolbarSearchPadding, alignment: .center)),
                isHitTestVisible: false
            ) {
                UI.icon(.search, preferredSize: Size(width: layout.toolbarIconSize, height: layout.toolbarIconSize), color: Color(red: 0.82, green: 0.89, blue: 0.97, alpha: 0.88), scale: layout.toolbarIconScale)
                UI.label(layout.toolbarSearchPlaceholder, layoutPriority: 1, color: Color(red: 0.80, green: 0.88, blue: 0.97, alpha: 0.80), scale: layout.toolbarSearchScale, alignment: .leading, maximumNumberOfLines: 1)
            }

            UI.button(
                title: rendererBackendLabel,
                preferredSize: Size(width: layout.toolbarBackendWidth, height: layout.toolbarPillHeight),
                cornerRadius: layout.toolbarPillHeight * 0.5,
                palette: SurfacePalette(
                    idle: Color(red: 0.22, green: 0.32, blue: 0.27, alpha: 0.98),
                    focused: Color(red: 0.30, green: 0.44, blue: 0.38, alpha: 1.0),
                    pressed: Color(red: 0.79, green: 0.92, blue: 0.87, alpha: 1.0)
                ),
                titleScale: layout.toolbarBadgeScale,
                action: { [weak self] in self?.performAction("RENDER STACK READY") }
            )

            UI.button(
                title: "EVENTS \(interactionCount)",
                preferredSize: Size(width: layout.toolbarEventsWidth, height: layout.toolbarPillHeight),
                cornerRadius: layout.toolbarPillHeight * 0.5,
                palette: SurfacePalette(
                    idle: Color(red: 0.24, green: 0.28, blue: 0.40, alpha: 0.98),
                    focused: Color(red: 0.33, green: 0.38, blue: 0.55, alpha: 1.0),
                    pressed: Color(red: 0.83, green: 0.88, blue: 0.99, alpha: 1.0)
                ),
                titleScale: layout.toolbarBadgeScale,
                action: { [weak self] in self?.performAction("EVENT HUD OPENED") }
            )

            UI.button(
                title: layout.statusTitle(for: selectedModule),
                preferredSize: Size(width: layout.toolbarModeWidth, height: layout.toolbarPillHeight),
                cornerRadius: layout.toolbarPillHeight * 0.5,
                palette: selectedModule.statusPalette,
                titleScale: layout.toolbarBadgeScale,
                action: { [weak self] in self?.cycleModule() }
            )
        }
    }

    private func buildSidebar(_ layout: DemoLayout) -> Component {
        UI.section(
            title: "WORKSPACE",
            backgroundColor: Color(red: 0.12, green: 0.16, blue: 0.22, alpha: 0.98),
            backgroundGradient: .linear(LinearGradient(
                startColor: Color(red: 0.14, green: 0.18, blue: 0.26, alpha: 0.98),
                endColor: Color(red: 0.10, green: 0.14, blue: 0.20, alpha: 0.98),
                axis: .vertical
            )),
            borderColor: Color(red: 0.76, green: 0.84, blue: 0.93, alpha: 0.12),
            cornerRadius: layout.sectionCornerRadius,
            stackLayout: .vertical(
                spacing: layout.sectionSpacing,
                padding: layout.sectionPadding,
                alignment: .stretch
            ),
            scrollAxis: .vertical,
            scrollStep: layout.sidebarScrollStep,
            scrollIndicatorThickness: layout.paneScrollIndicatorThickness
        ) {
            buildModuleButton(.layout, layout: layout)
            buildModuleButton(.input, layout: layout)
            buildModuleButton(.animation, layout: layout)

            UI.panel(
                preferredSize: Size(width: 0, height: layout.sidebarStripeHeight),
                backgroundColor: selectedModule.stripeColor,
                cornerRadius: layout.sidebarStripeHeight * 0.5,
                isHitTestVisible: false
            )

            UI.listRow(
                title: "STATE",
                detail: lastAction,
                accentColor: selectedModule.glowColor,
                symbol: .info,
                preferredSize: Size(width: 0, height: layout.sidebarRowHeight),
                action: { [weak self] in self?.performAction("STATE PANEL OPENED") }
            )

            UI.listRow(
                title: "SHORTCUTS",
                detail: "TAB AND WHEEL ROUTING",
                accentColor: selectedModule.stripeColor,
                symbol: .keyboard,
                preferredSize: Size(width: 0, height: layout.sidebarRowHeight),
                action: { [weak self] in self?.performAction("SHORTCUTS OPENED") }
            )
        }
    }

    private func buildModuleButton(_ module: DemoModule, layout: DemoLayout) -> Component {
        UI.button(
            title: module.label,
            preferredSize: Size(width: 0, height: layout.moduleButtonHeight),
            cornerRadius: layout.moduleButtonCornerRadius,
            palette: module.buttonPalette(isSelected: selectedModule == module),
            action: { [weak self] in self?.selectModule(module) }
        )
    }

    private func buildCenterPane(_ layout: DemoLayout) -> Component {
        UI.scrollPanel(
            axis: .vertical,
            backgroundColor: nil,
            borderColor: .clear,
            cornerRadius: 0,
            stackLayout: .vertical(
                spacing: layout.contentSectionGap,
                padding: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 4),
                alignment: .stretch
            ),
            scrollStep: layout.centerScrollStep,
            scrollIndicatorColor: Color(red: 0.92, green: 0.96, blue: 1.0, alpha: 0.18),
            scrollIndicatorHoverColor: Color(red: 0.95, green: 0.98, blue: 1.0, alpha: 0.34),
            scrollIndicatorActiveColor: Color(red: 0.98, green: 1.0, blue: 1.0, alpha: 0.58),
            scrollIndicatorThickness: layout.paneScrollIndicatorThickness,
            isHitTestVisible: false
        ) {
            buildHeroSection(layout)
            buildStatsRow(layout)
            buildActivitySection(layout)
        }
    }

    private func buildHeroSection(_ layout: DemoLayout) -> Component {
        UI.section(
            title: "CONTROL CENTER",
            preferredSize: Size(width: 0, height: layout.heroHeight),
            backgroundColor: Color(red: 0.15, green: 0.20, blue: 0.28, alpha: 0.98),
            backgroundGradient: .linear(LinearGradient(startColor: selectedModule.panelStartColor, endColor: selectedModule.panelEndColor, axis: .horizontal)),
            borderColor: Color(red: 0.74, green: 0.86, blue: 0.96, alpha: 0.10),
            cornerRadius: layout.heroCornerRadius,
            stackLayout: .vertical(
                spacing: layout.heroContentSpacing,
                padding: layout.heroPadding,
                alignment: .stretch
            )
        ) {
            UI.label(selectedModule.headline, color: .white, scale: layout.heroHeadlineScale, alignment: .leading, maximumNumberOfLines: 1)
            UI.label(selectedModule.detailLine, color: Color(red: 0.81, green: 0.90, blue: 0.98, alpha: 0.92), scale: layout.heroDetailScale, alignment: .leading, maximumNumberOfLines: 1)

            UI.panel(
                preferredSize: Size(width: 0, height: layout.heroStripeHeight),
                backgroundColor: selectedModule.stripeColor,
                cornerRadius: layout.heroStripeHeight * 0.5,
                isHitTestVisible: false
            )

            UI.stackPanel(
                preferredSize: layout.heroActionPreferredSize,
                stackLayout: layout.heroActionLayout,
                isHitTestVisible: false
            ) {
                UI.button(
                    title: "RUN DIAGNOSTICS",
                    preferredSize: Size(width: 0, height: layout.heroButtonHeight),
                    layoutPriority: 1,
                    cornerRadius: layout.heroButtonCornerRadius,
                    palette: SurfacePalette(
                        idle: Color(red: 0.27, green: 0.39, blue: 0.56, alpha: 0.98),
                        focused: Color(red: 0.36, green: 0.52, blue: 0.71, alpha: 1.0),
                        pressed: Color(red: 0.80, green: 0.90, blue: 0.99, alpha: 1.0)
                    ),
                    titleScale: layout.heroButtonScale,
                    action: { [weak self] in self?.performAction("DIAGNOSTICS PASSED") }
                )

                UI.button(
                    title: "SYNC SURFACES",
                    preferredSize: Size(width: 0, height: layout.heroButtonHeight),
                    layoutPriority: 1,
                    cornerRadius: layout.heroButtonCornerRadius,
                    palette: SurfacePalette(
                        idle: Color(red: 0.18, green: 0.52, blue: 0.56, alpha: 0.98),
                        focused: Color(red: 0.28, green: 0.66, blue: 0.70, alpha: 1.0),
                        pressed: Color(red: 0.79, green: 0.96, blue: 0.98, alpha: 1.0)
                    ),
                    titleScale: layout.heroButtonScale,
                    action: { [weak self] in self?.performAction("SURFACES RESYNCED") }
                )
            }
        }
    }

    private func buildStatsRow(_ layout: DemoLayout) -> Component {
        UI.stackPanel(
            preferredSize: layout.statsRowPreferredSize,
            stackLayout: layout.statsRowLayout,
            isHitTestVisible: false
        ) {
            buildStatTile(title: "MODULE", value: selectedModule.label, layout: layout, palette: selectedModule.metricPalette, action: "MODULE TILE OPENED")
            buildStatTile(title: "TEXT", value: textBackendLabel, layout: layout, palette: SurfacePalette(
                idle: Color(red: 0.25, green: 0.38, blue: 0.31, alpha: 0.98),
                focused: Color(red: 0.34, green: 0.51, blue: 0.42, alpha: 1.0),
                pressed: Color(red: 0.75, green: 0.91, blue: 0.82, alpha: 1.0)
            ), action: "TEXT TILE OPENED")
            buildStatTile(title: "EVENTS", value: "\(interactionCount)", layout: layout, palette: SurfacePalette(
                idle: Color(red: 0.42, green: 0.31, blue: 0.23, alpha: 0.98),
                focused: Color(red: 0.58, green: 0.43, blue: 0.31, alpha: 1.0),
                pressed: Color(red: 0.99, green: 0.86, blue: 0.66, alpha: 1.0)
            ), action: "EVENT COUNTER OPENED")
        }
    }

    private func buildStatTile(title: String, value: String, layout: DemoLayout, palette: SurfacePalette, action: String) -> Component {
        UI.buttonPanel(
            preferredSize: Size(width: 0, height: layout.statTileHeight),
            layoutPriority: 1,
            cornerRadius: layout.statTileCornerRadius,
            palette: palette,
            layoutMode: .stack(.vertical(alignment: .leading, mainAlignment: .center)),
            action: { [weak self] in self?.performAction(action) }
        ) {
            UI.stackPanel(
                preferredSize: Size(width: 0, height: layout.statTileContentHeight),
                layoutPriority: 1,
                stackLayout: .vertical(spacing: layout.statTileSpacing, alignment: .leading, mainAlignment: .center),
                isHitTestVisible: false
            ) {
                UI.label(title, color: Color(red: 0.84, green: 0.90, blue: 0.98, alpha: 0.90), scale: layout.statTitleScale, alignment: .leading, maximumNumberOfLines: 1)
                UI.label(value, color: .white, scale: layout.statValueScale, alignment: .leading, maximumNumberOfLines: 1)
            }
        }
    }

    private func buildActivitySection(_ layout: DemoLayout) -> Component {
        UI.section(
            title: "RECENT ACTIVITY",
            backgroundColor: Color(red: 0.14, green: 0.18, blue: 0.25, alpha: 0.98),
            backgroundGradient: .linear(LinearGradient(
                startColor: Color(red: 0.14, green: 0.18, blue: 0.25, alpha: 0.98),
                endColor: Color(red: 0.11, green: 0.15, blue: 0.21, alpha: 0.98),
                axis: .vertical
            )),
            borderColor: Color(red: 0.78, green: 0.86, blue: 0.95, alpha: 0.10),
            cornerRadius: layout.sectionCornerRadius,
            stackLayout: .vertical(
                spacing: layout.sectionSpacing,
                padding: layout.sectionPadding,
                alignment: .stretch
            )
        ) {
            for event in recentEvents {
                UI.listRow(
                    title: event,
                    detail: selectedModule.summary,
                    accentColor: selectedModule.glowColor,
                    symbol: .activity,
                    preferredSize: Size(width: 0, height: layout.activityRowHeight),
                    action: { [weak self] in self?.performAction("OPENED EVENT \(event)") }
                )
            }
        }
    }

    private func buildRightRail(_ layout: DemoLayout) -> Component {
        UI.section(
            title: "DETAILS",
            backgroundColor: Color(red: 0.13, green: 0.17, blue: 0.24, alpha: 0.98),
            backgroundGradient: .linear(LinearGradient(
                startColor: Color(red: 0.14, green: 0.18, blue: 0.26, alpha: 0.98),
                endColor: Color(red: 0.10, green: 0.13, blue: 0.19, alpha: 0.98),
                axis: .vertical
            )),
            borderColor: Color(red: 0.78, green: 0.86, blue: 0.95, alpha: 0.10),
            cornerRadius: layout.sectionCornerRadius,
            stackLayout: .vertical(
                spacing: layout.sectionSpacing,
                padding: layout.sectionPadding,
                alignment: .stretch
            ),
            scrollAxis: .vertical,
            scrollStep: layout.rightRailScrollStep,
            scrollIndicatorThickness: layout.paneScrollIndicatorThickness
        ) {
            UI.buttonPanel(
                preferredSize: Size(width: 0, height: layout.detailCardHeight),
                cornerRadius: layout.detailCardCornerRadius,
                palette: selectedModule.metricPalette,
                layoutMode: .stack(.vertical(alignment: .leading, mainAlignment: .center)),
                action: { [weak self] in self?.performAction("DETAIL CARD OPENED") }
            ) {
                UI.stackPanel(
                    preferredSize: Size(width: 0, height: layout.detailCardContentHeight),
                    layoutPriority: 1,
                    stackLayout: .vertical(spacing: layout.detailCardSpacing, alignment: .leading, mainAlignment: .center),
                    isHitTestVisible: false
                ) {
                    UI.label(selectedModule.label, color: .white, scale: layout.detailCardTitleScale, alignment: .leading, maximumNumberOfLines: 1)
                    UI.label(selectedModule.summary, color: Color(red: 0.83, green: 0.90, blue: 0.97, alpha: 0.92), scale: layout.detailCardSummaryScale, alignment: .leading, lineBreakMode: .wrap, maximumNumberOfLines: 2)
                    UI.label("LAST: \(lastAction)", color: Color(red: 0.90, green: 0.95, blue: 1.0, alpha: 0.80), scale: layout.detailCardMetaScale, alignment: .leading, maximumNumberOfLines: 1)
                }
            }

            UI.label("QUICK ACTIONS", color: Color(red: 0.90, green: 0.95, blue: 1.0, alpha: 0.96), scale: layout.quickActionsTitleScale, weight: .semibold, alignment: .leading, maximumNumberOfLines: 1)
            UI.listRow(
                title: "PROFILE LAYOUT",
                detail: "MEASURE, PLACE, CACHE",
                accentColor: selectedModule.glowColor,
                symbol: .layout,
                preferredSize: Size(width: 0, height: layout.quickActionRowHeight),
                action: { [weak self] in self?.performAction("LAYOUT PROFILED") }
            )
            UI.listRow(
                title: "INSPECT INPUT",
                detail: "ROUTE POINTER AND FOCUS",
                accentColor: selectedModule.stripeColor,
                symbol: .keyboard,
                preferredSize: Size(width: 0, height: layout.quickActionRowHeight),
                action: { [weak self] in self?.performAction("INPUT INSPECTED") }
            )
            UI.listRow(
                title: "QUEUE ANIMATION",
                detail: "FRAME TIMER AND PALETTES",
                accentColor: selectedModule.metricPalette.focused,
                symbol: .sparkle,
                preferredSize: Size(width: 0, height: layout.quickActionRowHeight),
                action: { [weak self] in self?.performAction("ANIMATION QUEUED") }
            )
        }
    }

    private struct DemoLayout {
        let size: Size
        let profile: DemoLayoutProfile

        init(size: Size) {
            self.size = size
            self.profile = DemoLayoutProfile.forSize(size)
        }

        var isCompact: Bool {
            profile != .regular
        }

        var isCondensed: Bool {
            profile == .condensed
        }

        var inset: Double {
            switch profile {
            case .regular:
                return 28
            case .compact:
                return 20
            case .condensed:
                return 14
            }
        }

        var gap: Double {
            switch profile {
            case .regular:
                return 24
            case .compact:
                return 18
            case .condensed:
                return 12
            }
        }

        var dividerThickness: Double {
            isCondensed ? 14 : 18
        }

        var toolbarHeight: Double {
            switch profile {
            case .regular:
                return 84
            case .compact:
                return 78
            case .condensed:
                return 72
            }
        }

        var toolbarCornerRadius: Double {
            isCondensed ? 18 : 22
        }

        var toolbarSpacing: Double {
            isCondensed ? 10 : 14
        }

        var toolbarPadding: EdgeInsets {
            switch profile {
            case .regular:
                return EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18)
            case .compact:
                return EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)
            case .condensed:
                return EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
            }
        }

        var toolbarTitleWidth: Double {
            switch profile {
            case .regular:
                return 260
            case .compact:
                return 198
            case .condensed:
                return 156
            }
        }

        var toolbarTitleHeight: Double {
            showsToolbarSubtitle ? 44 : 28
        }

        var toolbarTitleSpacing: Double {
            showsToolbarSubtitle ? 4 : 0
        }

        var toolbarTitleScale: Double {
            switch profile {
            case .regular:
                return 1.8
            case .compact:
                return 1.65
            case .condensed:
                return 1.5
            }
        }

        var toolbarSubtitleScale: Double {
            switch profile {
            case .regular:
                return 1.1
            case .compact:
                return 1.0
            case .condensed:
                return 0.95
            }
        }

        var showsToolbarSubtitle: Bool {
            !isCondensed
        }

        var toolbarPillHeight: Double {
            isCondensed ? 34 : 38
        }

        var toolbarSearchBaseWidth: Double {
            switch profile {
            case .regular:
                return 280
            case .compact:
                return 220
            case .condensed:
                return 168
            }
        }

        var toolbarSearchPadding: EdgeInsets {
            EdgeInsets(top: 0, leading: isCondensed ? 12 : 14, bottom: 0, trailing: isCondensed ? 10 : 12)
        }

        var toolbarSearchSpacing: Double {
            isCondensed ? 8 : 10
        }

        var toolbarSearchPlaceholder: String {
            isCondensed ? "SEARCH" : "SEARCH COMMANDS"
        }

        var toolbarSearchScale: Double {
            isCondensed ? 1.05 : 1.2
        }

        var toolbarIconSize: Double {
            isCondensed ? 16 : 18
        }

        var toolbarIconScale: Double {
            isCondensed ? 1.1 : 1.2
        }

        var toolbarBackendWidth: Double {
            switch profile {
            case .regular:
                return 138
            case .compact:
                return 124
            case .condensed:
                return 112
            }
        }

        var toolbarEventsWidth: Double {
            switch profile {
            case .regular:
                return 118
            case .compact:
                return 108
            case .condensed:
                return 96
            }
        }

        var toolbarModeWidth: Double {
            switch profile {
            case .regular:
                return 156
            case .compact:
                return 138
            case .condensed:
                return 120
            }
        }

        var toolbarBadgeScale: Double {
            isCondensed ? 1.05 : 1.2
        }

        var toolbarFrame: Rect {
            Rect(x: inset, y: inset, width: max(320, size.width - inset * 2), height: toolbarHeight)
        }

        var contentTop: Double {
            toolbarFrame.maxY + gap
        }

        var bodyFrame: Rect {
            Rect(x: inset, y: contentTop, width: max(320, size.width - inset * 2), height: max(240, size.height - contentTop - inset))
        }

        var sidebarMinExtent: Double {
            clamp(bodyFrame.size.width * (isCondensed ? 0.22 : 0.18), min: 156, max: isCompact ? 196 : 220)
        }

        var detailMinExtent: Double {
            clamp(bodyFrame.size.width * (isCondensed ? 0.26 : 0.24), min: isCondensed ? 188 : 220, max: 300)
        }

        var centerMinExtent: Double {
            clamp(bodyFrame.size.width * (isCondensed ? 0.42 : 0.48), min: isCondensed ? 260 : 320, max: isCompact ? 460 : 560)
        }

        var bodySecondaryMinExtent: Double {
            centerMinExtent + detailMinExtent + dividerThickness
        }

        var sectionCornerRadius: Double {
            isCondensed ? 22 : 28
        }

        var sectionSpacing: Double {
            isCondensed ? 12 : 16
        }

        var sectionPadding: EdgeInsets {
            switch profile {
            case .regular:
                return EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18)
            case .compact:
                return EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
            case .condensed:
                return EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
            }
        }

        var heroHeight: Double {
            switch profile {
            case .regular:
                return 240
            case .compact:
                return 224
            case .condensed:
                return 248
            }
        }

        var heroCornerRadius: Double {
            isCondensed ? 24 : 30
        }

        var heroPadding: EdgeInsets {
            switch profile {
            case .regular:
                return EdgeInsets(top: 20, leading: 22, bottom: 22, trailing: 22)
            case .compact:
                return EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18)
            case .condensed:
                return EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
            }
        }

        var heroContentSpacing: Double {
            isCondensed ? 12 : 16
        }

        var heroHeadlineScale: Double {
            switch profile {
            case .regular:
                return 3.0
            case .compact:
                return 2.6
            case .condensed:
                return 2.2
            }
        }

        var heroDetailScale: Double {
            switch profile {
            case .regular:
                return 1.55
            case .compact:
                return 1.35
            case .condensed:
                return 1.15
            }
        }

        var heroStripeHeight: Double {
            isCondensed ? 10 : 12
        }

        var heroButtonHeight: Double {
            isCondensed ? 48 : 54
        }

        var heroButtonCornerRadius: Double {
            isCondensed ? 16 : 18
        }

        var heroButtonScale: Double {
            isCondensed ? 1.25 : 1.5
        }

        var heroActionLayout: StackLayout {
            if isCondensed {
                return .vertical(spacing: 12, alignment: .stretch)
            }

            return .horizontal(spacing: 14, alignment: .stretch)
        }

        var heroActionPreferredSize: Size? {
            isCondensed ? nil : Size(width: 0, height: heroButtonHeight)
        }

        var contentSectionGap: Double {
            isCondensed ? 14 : 18
        }

        var centerScrollStep: Double {
            72
        }

        var sidebarScrollStep: Double {
            44
        }

        var rightRailScrollStep: Double {
            44
        }

        var paneScrollIndicatorThickness: Double {
            isCondensed ? 5 : 6
        }

        var moduleButtonHeight: Double {
            isCondensed ? 48 : 54
        }

        var moduleButtonCornerRadius: Double {
            isCondensed ? 14 : 16
        }

        var sidebarStripeHeight: Double {
            isCondensed ? 8 : 10
        }

        var sidebarRowHeight: Double {
            isCondensed ? 66 : 72
        }

        var stackedStats: Bool {
            isCondensed
        }

        var statsRowLayout: StackLayout {
            if stackedStats {
                return .vertical(spacing: 14, alignment: .stretch)
            }

            return .horizontal(spacing: 18, alignment: .stretch)
        }

        var statsRowPreferredSize: Size? {
            stackedStats ? nil : Size(width: 0, height: statTileHeight)
        }

        var statTileHeight: Double {
            isCondensed ? 118 : 132
        }

        var statTileCornerRadius: Double {
            isCondensed ? 20 : 24
        }

        var statTileContentHeight: Double {
            isCondensed ? 68 : 76
        }

        var statTileSpacing: Double {
            isCondensed ? 8 : 10
        }

        var statTitleScale: Double {
            isCondensed ? 1.2 : 1.4
        }

        var statValueScale: Double {
            isCondensed ? 2.0 : 2.4
        }

        var activityRowHeight: Double {
            isCondensed ? 64 : 68
        }

        var detailCardHeight: Double {
            isCondensed ? 118 : 128
        }

        var detailCardCornerRadius: Double {
            isCondensed ? 20 : 22
        }

        var detailCardContentHeight: Double {
            isCondensed ? 82 : 90
        }

        var detailCardSpacing: Double {
            isCondensed ? 6 : 8
        }

        var detailCardTitleScale: Double {
            isCondensed ? 2.0 : 2.2
        }

        var detailCardSummaryScale: Double {
            isCondensed ? 1.15 : 1.25
        }

        var detailCardMetaScale: Double {
            isCondensed ? 1.0 : 1.05
        }

        var quickActionsTitleScale: Double {
            isCondensed ? 1.45 : 1.6
        }

        var quickActionRowHeight: Double {
            isCondensed ? 64 : 68
        }

        func statusTitle(for module: DemoModule) -> String {
            isCondensed ? module.label : module.statusLabel
        }

        var backgroundAccentA: Rect {
            Rect(
                x: bodyFrame.origin.x + bodyFrame.size.width * 0.28,
                y: bodyFrame.origin.y + (isCondensed ? 18 : 26),
                width: min(isCondensed ? 180 : 320, bodyFrame.size.width * 0.22),
                height: isCondensed ? 112 : 150
            )
        }

        var backgroundAccentB: Rect {
            Rect(
                x: bodyFrame.origin.x + bodyFrame.size.width * 0.58,
                y: bodyFrame.origin.y + heroHeight + gap,
                width: min(isCondensed ? 150 : 220, bodyFrame.size.width * 0.18),
                height: isCondensed ? 86 : 108
            )
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

    private func applyDemoRootLayout(in bounds: Rect) {
        let children = runtime.root.children
        guard children.count >= 4 else {
            return
        }

        let layout = DemoLayout(size: bounds.size)
        let demoFrames = [
            layout.backgroundAccentA,
            layout.backgroundAccentB,
            layout.toolbarFrame,
            layout.bodyFrame,
        ]

        for (index, frame) in demoFrames.enumerated() where children[index].frame != frame {
            children[index].frame = frame
        }
    }

    private func report(_ error: Error) {
        print("[SwiftWindowsUI] \(error)")
    }
}

private enum DemoLayoutProfile: Equatable {
    case regular
    case compact
    case condensed

    static func forSize(_ size: Size) -> DemoLayoutProfile {
        if size.width < 940 || size.height < 640 {
            return .condensed
        }

        if size.width < 1180 || size.height < 760 {
            return .compact
        }

        return .regular
    }
}

private func clamp(_ value: Double, min minimum: Double, max maximum: Double) -> Double {
    Swift.min(Swift.max(value, minimum), maximum)
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

    var panelStartColor: Color {
        switch self {
        case .layout:
            return Color(red: 0.19, green: 0.24, blue: 0.33, alpha: 0.98)
        case .input:
            return Color(red: 0.16, green: 0.24, blue: 0.28, alpha: 0.98)
        case .animation:
            return Color(red: 0.24, green: 0.21, blue: 0.18, alpha: 0.98)
        }
    }

    var panelEndColor: Color {
        switch self {
        case .layout:
            return Color(red: 0.13, green: 0.18, blue: 0.26, alpha: 0.98)
        case .input:
            return Color(red: 0.12, green: 0.21, blue: 0.24, alpha: 0.98)
        case .animation:
            return Color(red: 0.20, green: 0.17, blue: 0.14, alpha: 0.98)
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
