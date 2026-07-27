#if canImport(SwiftUI)
    import SwiftUI
#else
    import WinSwiftUI
#endif

@MainActor
public final class DemoDashboardModel: ObservableObject {
    @Published var selectedModule: DemoModule = .layout
    @Published var interactionCount = 0
    @Published var lastAction = "READY"
    @Published var recentEvents: [String] = [
        "SYSTEM READY",
        "D3D11 READY",
        "WINDOW TOOLKIT ACTIVE",
    ]

    /// Active top-level screen shown by the demo's `TabView` shell.
    @Published public var selectedScreen: DemoScreen = .dashboard {
        didSet {
            if selectedScreen != oldValue {
                performAction("OPENED \(selectedScreen.label)")
            }
        }
    }

    // Settings screen state
    @Published var displayName = "OPERATOR"
    @Published var theme: DemoThemeOption = .system
    @Published var itemsPerPage = 10
    @Published var animationsEnabled = true
    @Published var soundEffectsEnabled = false
    @Published var shareUsageData = true
    @Published var fontScale = 1.0
    @Published var storageUsed = 0.62
    @Published var syncProgress = 0.35

    // Data screen state
    @Published public var components: [DemoComponent] = DemoComponent.defaults
    @Published public var selectedComponentID: Int? = DemoComponent.defaults.first?.id

    public init() {}

    /// Currently selected component on the data screen, if any.
    public var selectedComponent: DemoComponent? {
        components.first { $0.id == selectedComponentID }
    }

    func selectScreen(_ screen: DemoScreen) {
        selectedScreen = screen
    }

    func saveSettings() {
        performAction("SAVED SETTINGS FOR \(displayName)")
    }

    func resetSettings() {
        displayName = "OPERATOR"
        theme = .system
        itemsPerPage = 10
        animationsEnabled = true
        soundEffectsEnabled = false
        shareUsageData = true
        fontScale = 1.0
        performAction("RESET SETTINGS TO DEFAULTS")
    }

    func runSync() {
        syncProgress = min(1.0, syncProgress + 0.25)
        performAction(syncProgress >= 1.0 ? "SYNC COMPLETE" : "SYNC ADVANCED")
    }

    func restartSelectedComponent() {
        guard let component = selectedComponent else {
            performAction("NO COMPONENT SELECTED")
            return
        }
        performAction("RESTARTED \(component.name)")
    }

    func runDiagnostics() {
        guard let component = selectedComponent else {
            performAction("NO COMPONENT SELECTED")
            return
        }
        performAction("DIAGNOSED \(component.name)")
    }

    func selectFirstComponent() {
        selectedComponentID = components.first?.id
    }

    func selectModule(_ module: DemoModule) {
        selectedModule = module
        performAction("SELECTED \(module.label)")
    }

    func cycleModule() {
        let modules = DemoModule.allCases
        guard let index = modules.firstIndex(of: selectedModule) else {
            return
        }

        let nextIndex = modules.index(after: index)
        selectedModule = nextIndex == modules.endIndex ? modules[modules.startIndex] : modules[nextIndex]
        performAction("CYCLED \(selectedModule.label)")
    }

    func performAction(_ action: String) {
        interactionCount += 1
        lastAction = action
        recentEvents.insert(action, at: 0)
        if recentEvents.count > 10 {
            recentEvents.removeLast(recentEvents.count - 10)
        }
    }
}
public struct DemoRootView: View {
    @ObservedObject var model: DemoDashboardModel

    public init(model: DemoDashboardModel) {
        self.model = model
    }

    /// Product-style shell: a tab bar navigates between the dashboard,
    /// settings, and data-list screens using only same-source SwiftUI APIs.
    public var body: some View {
        TabView(selection: $model.selectedScreen) {
            DemoDashboardScreen(model: model)
                .tabItem {
                    Label(DemoScreen.dashboard.label, systemImage: DemoScreen.dashboard.systemImage)
                }
                .tag(DemoScreen.dashboard)

            DemoSettingsScreen(model: model)
                .tabItem {
                    Label(DemoScreen.settings.label, systemImage: DemoScreen.settings.systemImage)
                }
                .tag(DemoScreen.settings)

            DemoDataScreen(model: model)
                .tabItem {
                    Label(DemoScreen.data.label, systemImage: DemoScreen.data.systemImage)
                }
                .tag(DemoScreen.data)
        }
    }
}

/// The original control-center dashboard, hosted as the first tab of `DemoRootView`.
struct DemoDashboardScreen: View {
    @ObservedObject var model: DemoDashboardModel

    var body: some View {
        GeometryReader { proxy in
            let layout = DemoLayout(size: proxy.size)

            ZStack(alignment: .topLeading) {
                DemoBackdrop(size: proxy.size)

                DemoAccent(
                    frame: layout.accentA,
                    fill: LinearGradient(
                        colors: [
                            model.selectedModule.glowColor.opacity(0.32),
                            model.selectedModule.stripeColor.opacity(0.10),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

                DemoAccent(
                    frame: layout.accentB,
                    fill: LinearGradient(
                        colors: [
                            model.selectedModule.stripeColor.opacity(0.26),
                            model.selectedModule.glowColor.opacity(0.08),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                VStack(alignment: .leading, spacing: layout.gap) {
                    DemoToolbar(model: model, layout: layout)

                    HStack(alignment: .top, spacing: layout.columnGap) {
                        DemoSidebar(model: model, layout: layout)
                            .frame(width: layout.sidebarWidth, height: layout.bodyHeight, alignment: .topLeading)

                        DemoCenterPane(model: model, layout: layout)
                            .frame(width: layout.contentWidth, height: layout.bodyHeight, alignment: .topLeading)

                        DemoRightRail(model: model, layout: layout)
                            .frame(width: layout.railWidth, height: layout.bodyHeight, alignment: .topLeading)
                    }
                    .frame(height: layout.bodyHeight, alignment: .topLeading)
                }
                .padding(layout.outerPadding)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
    }
}
struct DemoToolbar: View {
    let model: DemoDashboardModel
    let layout: DemoLayout

    var body: some View {
        DemoGlassSurface(
            cornerRadius: layout.toolbarCornerRadius,
            contentPadding: layout.toolbarPadding,
            fill: LinearGradient(
                colors: [DemoTheme.surfaceTop, DemoTheme.surfaceBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            stroke: DemoTheme.surfaceStrokeStrong,
            shadowColor: DemoTheme.shadow
        ) {
            HStack(alignment: .center, spacing: layout.gap) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("WINSWIFTUI")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(DemoTheme.primaryText)
                        .multilineTextAlignment(.leading)
                        .lineLimit(1)

                    Text("SAME-SOURCE DASHBOARD DEMO")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(DemoTheme.secondaryText)
                        .multilineTextAlignment(.leading)
                        .lineLimit(1)
                }
                .frame(width: layout.toolbarTitleWidth, alignment: .leading)

                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(DemoTheme.secondaryText)
                        .font(.system(size: 12))

                    Text("SEARCH COMMANDS")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(DemoTheme.secondaryText)
                        .multilineTextAlignment(.leading)
                        .lineLimit(1)
                }
                .padding(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14))
                .frame(width: layout.searchWidth, height: layout.pillHeight, alignment: .leading)
                .background(
                    LinearGradient(
                        colors: [DemoTheme.fieldTop, DemoTheme.fieldBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(layout.pillHeight * 0.5)
                .padding(1)
                .background(DemoTheme.surfaceStroke)
                .cornerRadius(layout.pillHeight * 0.5 + 1)
                .allowsHitTesting(false)
                .layoutPriority(1)

                Spacer(minLength: 0)

                DemoPillButton(
                    "D3D11",
                    width: layout.backendWidth,
                    colors: [
                        Color(red: 0.42, green: 0.70, blue: 0.56, opacity: 0.94),
                        Color(red: 0.26, green: 0.50, blue: 0.38, opacity: 0.84),
                    ]
                ) {
                    model.performAction("RENDER STACK READY")
                }

                DemoPillButton(
                    "EVENTS \(model.interactionCount)",
                    width: layout.eventsWidth,
                    colors: [
                        Color(red: 0.55, green: 0.69, blue: 0.95, opacity: 0.92),
                        Color(red: 0.36, green: 0.48, blue: 0.72, opacity: 0.82),
                    ]
                ) {
                    model.performAction("EVENT HUD OPENED")
                }

                DemoPillButton(
                    model.selectedModule.statusLabel,
                    width: layout.modeWidth,
                    colors: [
                        model.selectedModule.glowColor.opacity(0.94), model.selectedModule.stripeColor.opacity(0.70),
                    ]
                ) {
                    model.cycleModule()
                }
            }
        }
        .frame(height: layout.toolbarHeight, alignment: .leading)
    }
}
struct DemoSidebar: View {
    let model: DemoDashboardModel
    let layout: DemoLayout

    var body: some View {
        DemoGlassSurface(
            cornerRadius: layout.panelCornerRadius,
            contentPadding: .zero,
            fill: LinearGradient(
                colors: [DemoTheme.sidebarTop, DemoTheme.sidebarBottom],
                startPoint: .top,
                endPoint: .bottom
            ),
            stroke: DemoTheme.surfaceStrokeStrong
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    DemoSectionTitle("WORKSPACE")

                    ForEach(DemoModule.allCases, id: \.self) { module in
                        DemoModuleButton(
                            systemImage: module.systemImage,
                            title: module.label,
                            colors: model.selectedModule == module
                                ? [module.glowColor.opacity(0.92), module.stripeColor.opacity(0.74)]
                                : [DemoTheme.fieldTop, DemoTheme.fieldBottom]
                        ) {
                            model.selectModule(module)
                        }
                        .frame(width: layout.sidebarInnerWidth, alignment: .leading)
                    }

                    Color.clear
                        .frame(width: layout.sidebarInnerWidth, height: 10)
                        .background(
                            LinearGradient(
                                colors: [
                                    model.selectedModule.glowColor.opacity(0.88),
                                    model.selectedModule.stripeColor.opacity(0.62),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(5)
                        .allowsHitTesting(false)

                    DemoRowButton(
                        title: "STATE",
                        detail: model.lastAction,
                        systemImage: "info.circle",
                        accent: model.selectedModule.glowColor
                    ) {
                        model.performAction("STATE PANEL OPENED")
                    }
                    .frame(width: layout.sidebarInnerWidth, alignment: .leading)

                    DemoRowButton(
                        title: "SHORTCUTS",
                        detail: "TAB AND WHEEL ROUTING",
                        systemImage: "keyboard",
                        accent: model.selectedModule.stripeColor
                    ) {
                        model.performAction("SHORTCUTS OPENED")
                    }
                    .frame(width: layout.sidebarInnerWidth, alignment: .leading)
                }
                .padding(layout.panelPadding)
            }
        }
    }
}
struct DemoCenterPane: View {
    let model: DemoDashboardModel
    let layout: DemoLayout

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: layout.gap) {
                DemoHeroCard(model: model, layout: layout)
                    .frame(width: layout.contentInnerWidth, alignment: .leading)

                DemoPanel {
                    VStack(alignment: .leading, spacing: 10) {
                        DemoSectionTitle("RENDER PIPELINE")

                        DemoRenderPipelineChart(model: model)
                            .frame(width: layout.contentInnerWidth - 32, height: 80)
                    }
                }
                .frame(width: layout.contentInnerWidth, alignment: .leading)

                if layout.compact {
                    VStack(alignment: .leading, spacing: 14) {
                        DemoMetricCard(
                            title: "INTERACTIONS", value: "\(model.interactionCount)", note: "EVENTS TRACKED",
                            accent: model.selectedModule.accentColor
                        )
                        .frame(width: layout.contentInnerWidth, alignment: .leading)
                        DemoMetricCard(
                            title: "MODULE", value: model.selectedModule.label, note: model.selectedModule.summary,
                            accent: model.selectedModule.accentColor
                        )
                        .frame(width: layout.contentInnerWidth, alignment: .leading)
                        DemoMetricCard(
                            title: "TARGET", value: "SAME SOURCE", note: "IMPORT WINSWIFTUI OR SWIFTUI",
                            accent: Color(red: 0.30, green: 0.42, blue: 0.60, opacity: 0.95)
                        )
                        .frame(width: layout.contentInnerWidth, alignment: .leading)
                    }
                } else {
                    HStack(alignment: .center, spacing: 18) {
                        DemoMetricCard(
                            title: "INTERACTIONS", value: "\(model.interactionCount)", note: "EVENTS TRACKED",
                            accent: model.selectedModule.accentColor
                        )
                        .frame(width: layout.metricCardWidth, alignment: .leading)
                        DemoMetricCard(
                            title: "MODULE", value: model.selectedModule.label, note: model.selectedModule.summary,
                            accent: model.selectedModule.accentColor
                        )
                        .frame(width: layout.metricCardWidth, alignment: .leading)
                        DemoMetricCard(
                            title: "TARGET", value: "SAME SOURCE", note: "IMPORT WINSWIFTUI OR SWIFTUI",
                            accent: Color(red: 0.30, green: 0.42, blue: 0.60, opacity: 0.95)
                        )
                        .frame(width: layout.metricCardWidth, alignment: .leading)
                    }
                    .frame(width: layout.contentInnerWidth, alignment: .leading)
                }

                DemoPanel {
                    VStack(alignment: .leading, spacing: 14) {
                        DemoSectionTitle("ACTIVITY")

                        ForEach(model.recentEvents.prefix(5), id: \.self) { event in
                            DemoActivityCard(
                                title: event,
                                detail: model.selectedModule.detailLine,
                                systemImage: model.selectedModule.systemImage,
                                accent: model.selectedModule.glowColor
                            )
                        }
                    }
                }
                .frame(width: layout.contentInnerWidth, alignment: .leading)
            }
            .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 6))
        }
    }
}

/// Canvas-driven mini bar chart embedded in the dashboard's center pane.
/// Demonstrates the SwiftUI-shape `GraphicsContext` API (fillRect with color
/// and linear-gradient shading, `drawLayer`, `translateBy`) against the same
/// shared demo source compatible with macOS SwiftUI.
struct DemoRenderPipelineChart: View {
    let model: DemoDashboardModel

    var body: some View {
        let glow = model.selectedModule.glowColor
        let stripe = model.selectedModule.stripeColor
        let interactions = max(1, model.interactionCount)
        // A deterministic, seed-style bar series so the screenshot stays
        // stable across runs but still varies with interaction count + module.
        let bars = Self.bars(interactions: interactions, glow: glow, stripe: stripe)

        return Canvas { ctx, size in
            // Backing tint so the chart panel reads as one block.
            ctx.fill(
                Rect(x: 0, y: 0, width: size.width, height: size.height),
                with: .linearGradient(
                    Gradient(colors: [
                        Color(red: 0.96, green: 0.97, blue: 1.00, opacity: 0.55),
                        Color(red: 0.90, green: 0.93, blue: 0.98, opacity: 0.30),
                    ]),
                    startPoint: CGPoint(x: size.width / 2, y: 0),
                    endPoint: CGPoint(x: size.width / 2, y: size.height)
                )
            )

            let count = bars.count
            guard count > 0 else { return }
            let gap: CGFloat = 6
            let barWidth = max(2, (size.width - gap * CGFloat(count - 1)) / CGFloat(count))
            let baselineY: CGFloat = size.height - 8

            var index = 0
            while index < count {
                let bar = bars[index]
                let x = CGFloat(index) * (barWidth + gap)
                let barHeight = max(2, bar.value * (size.height - 18))

                ctx.drawLayer { sub in
                    sub.translateBy(x: x, y: baselineY - barHeight)
                    sub.opacity = 0.85 + bar.emphasis * 0.15
                    sub.fill(
                        Rect(x: 0, y: 0, width: barWidth, height: barHeight),
                        with: .linearGradient(
                            Gradient(colors: [bar.top, bar.bottom]),
                            startPoint: CGPoint(x: barWidth / 2, y: 0),
                            endPoint: CGPoint(x: barWidth / 2, y: barHeight)
                        )
                    )
                }

                index += 1
            }
        }
    }

    private struct Bar {
        let value: CGFloat
        let emphasis: CGFloat
        let top: Color
        let bottom: Color
    }

    private static func bars(interactions: Int, glow: Color, stripe: Color) -> [Bar] {
        let pattern: [CGFloat] = [0.35, 0.52, 0.40, 0.68, 0.56, 0.82, 0.64, 0.94, 0.72, 0.58]
        return pattern.enumerated().map { index, base in
            let phase = (Double(index) + Double(interactions) * 0.13).truncatingRemainder(dividingBy: 1)
            let value = min(1, max(0.10, base + CGFloat(phase) * 0.10))
            let emphasis = CGFloat(phase)
            return Bar(
                value: value,
                emphasis: emphasis,
                top: glow,
                bottom: stripe.opacity(0.75)
            )
        }
    }
}
struct DemoRightRail: View {
    let model: DemoDashboardModel
    let layout: DemoLayout

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: layout.gap) {
                DemoPanel {
                    VStack(alignment: .leading, spacing: 14) {
                        DemoSectionTitle("DETAIL TRACK")

                        ForEach(model.selectedModule.cards, id: \.title) { card in
                            DemoInfoCard(card: card)
                        }
                    }
                }
                .frame(width: layout.railInnerWidth, alignment: .leading)

                DemoPanel {
                    VStack(alignment: .leading, spacing: 14) {
                        DemoSectionTitle("QUICK ACTIONS")

                        ForEach(model.selectedModule.actions, id: \.title) { action in
                            DemoRowButton(
                                title: action.title,
                                detail: action.caption,
                                systemImage: action.systemImage,
                                accent: model.selectedModule.stripeColor
                            ) {
                                model.performAction(action.eventLabel)
                            }
                            .frame(width: layout.railInnerWidth - 32, alignment: .leading)
                        }
                    }
                }
                .frame(width: layout.railInnerWidth, alignment: .leading)
            }
            .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 6))
        }
    }
}
struct DemoHeroCard: View {
    let model: DemoDashboardModel
    let layout: DemoLayout

    var body: some View {
        DemoTintedSurface(
            cornerRadius: layout.panelCornerRadius + 4,
            contentPadding: layout.panelPadding,
            // Nearly opaque deep-navy stops: the headline/subtitle sit on this
            // card, so it must stay dark over the light backdrop instead of
            // washing out into mid-grey.
            colors: [
                model.selectedModule.panelStartColor,
                model.selectedModule.panelEndColor,
            ],
            stroke: DemoTheme.surfaceStrokeStrong,
            shadowColor: model.selectedModule.glowColor.opacity(0.12)
        ) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 10) {
                    DemoCapsuleText("CONTROL CENTER")
                    DemoCapsuleText(model.selectedModule.label, tint: model.selectedModule.glowColor)
                }

                Text(model.selectedModule.headline)
                    .font(.system(size: layout.headlineSize, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)

                Text(model.selectedModule.summary)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(DemoTheme.heroSubtitleText)
                    .multilineTextAlignment(.leading)

                Color.clear
                    .frame(
                        width: layout.contentInnerWidth
                            - layout.panelPadding.leading - layout.panelPadding.trailing - 2,
                        height: 12
                    )
                    .background(
                        LinearGradient(
                            colors: [
                                model.selectedModule.glowColor.opacity(0.94),
                                model.selectedModule.stripeColor.opacity(0.68),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(6)
                    .allowsHitTesting(false)

                if layout.compactActions {
                    VStack(alignment: .leading, spacing: 12) {
                        DemoPillButton(
                            "OPEN \(model.selectedModule.label)",
                            colors: [
                                model.selectedModule.glowColor.opacity(0.94),
                                model.selectedModule.stripeColor.opacity(0.70),
                            ]
                        ) {
                            model.performAction("OPENED \(model.selectedModule.label)")
                        }

                        DemoPillButton(
                            "CYCLE MODE",
                            colors: [DemoTheme.fieldTop, DemoTheme.fieldBottom],
                            textColor: DemoTheme.primaryText
                        ) {
                            model.cycleModule()
                        }
                    }
                } else {
                    HStack(alignment: .center, spacing: 12) {
                        DemoPillButton(
                            "OPEN \(model.selectedModule.label)",
                            colors: [
                                model.selectedModule.glowColor.opacity(0.94),
                                model.selectedModule.stripeColor.opacity(0.70),
                            ]
                        ) {
                            model.performAction("OPENED \(model.selectedModule.label)")
                        }
                        .layoutPriority(1)

                        DemoPillButton(
                            "CYCLE MODE",
                            colors: [DemoTheme.fieldTop, DemoTheme.fieldBottom],
                            textColor: DemoTheme.primaryText
                        ) {
                            model.cycleModule()
                        }
                        .layoutPriority(1)
                    }
                }
            }
        }
        .frame(height: layout.heroHeight, alignment: .leading)
    }
}
struct DemoBackdrop: View {
    let size: CGSize

    var body: some View {
        Color.clear
            .frame(width: size.width, height: size.height)
            .background(
                LinearGradient(
                    colors: [
                        DemoTheme.backdropTop,
                        DemoTheme.backdropMiddle,
                        DemoTheme.backdropBottom,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .allowsHitTesting(false)
    }
}
struct DemoGlassSurface<Content: View>: View {
    let content: Content
    let cornerRadius: CGFloat
    let contentPadding: EdgeInsets
    let fill: LinearGradient
    let stroke: Color
    let shadowColor: Color

    init(
        cornerRadius: CGFloat = 30,
        contentPadding: EdgeInsets = EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18),
        fill: LinearGradient = LinearGradient(
            colors: [DemoTheme.surfaceTop, DemoTheme.surfaceBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        ),
        stroke: Color = DemoTheme.surfaceStroke,
        shadowColor: Color = DemoTheme.shadow,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.cornerRadius = cornerRadius
        self.contentPadding = contentPadding
        self.fill = fill
        self.stroke = stroke
        self.shadowColor = shadowColor
    }

    var body: some View {
        content
            .padding(contentPadding)
            .background(fill)
            .cornerRadius(cornerRadius)
            .padding(1)
            .background(stroke)
            .cornerRadius(cornerRadius + 1)
            .shadow(color: shadowColor, radius: 8, x: 0, y: 14)
    }
}
struct DemoTintedSurface<Content: View>: View {
    let content: Content
    let cornerRadius: CGFloat
    let contentPadding: EdgeInsets
    let colors: [Color]
    let stroke: Color
    let shadowColor: Color

    init(
        cornerRadius: CGFloat = 24,
        contentPadding: EdgeInsets = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16),
        colors: [Color],
        stroke: Color = DemoTheme.surfaceStrokeStrong,
        shadowColor: Color = DemoTheme.shadow,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.cornerRadius = cornerRadius
        self.contentPadding = contentPadding
        self.colors = colors
        self.stroke = stroke
        self.shadowColor = shadowColor
    }

    var body: some View {
        content
            .padding(contentPadding)
            .background(
                LinearGradient(
                    colors: colors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(cornerRadius)
            .padding(1)
            .background(stroke)
            .cornerRadius(cornerRadius + 1)
            .shadow(color: shadowColor, radius: 8, x: 0, y: 14)
    }
}
struct DemoPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        DemoGlassSurface {
            content
        }
    }
}
struct DemoCapsuleText: View {
    let title: String
    let tint: Color?

    init(_ title: String, tint: Color? = nil) {
        self.title = title
        self.tint = tint
    }

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundColor(tint == nil ? DemoTheme.primaryText : DemoTheme.inverseText)
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .padding(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
            .background((tint ?? DemoTheme.fieldTop).opacity(tint == nil ? 0.84 : 0.42))
            .cornerRadius(12)
            .padding(1)
            .background(DemoTheme.surfaceStroke)
            .cornerRadius(13)
    }
}
struct DemoSectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundColor(DemoTheme.secondaryText)
            .multilineTextAlignment(.leading)
            .lineLimit(1)
    }
}
struct DemoPillButton: View {
    let title: String
    let width: CGFloat?
    let colors: [Color]
    let textColor: Color
    let perform: @MainActor @Sendable () -> Void

    init(
        _ title: String,
        width: CGFloat? = nil,
        colors: [Color],
        textColor: Color = DemoTheme.inverseText,
        perform: @escaping @MainActor @Sendable () -> Void
    ) {
        self.title = title
        self.width = width
        self.colors = colors
        self.textColor = textColor
        self.perform = perform
    }

    var body: some View {
        Button(action: perform) {
            DemoTintedSurface(
                cornerRadius: 20,
                contentPadding: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0),
                colors: colors,
                stroke: DemoTheme.surfaceStrokeStrong,
                shadowColor: DemoTheme.shadow
            ) {
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(textColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .frame(width: width, height: 38)
            }
        }
        .buttonStyle(.plain)
    }
}
struct DemoModuleButton: View {
    let systemImage: String
    let title: String
    let colors: [Color]
    let perform: @MainActor @Sendable () -> Void

    var body: some View {
        Button(action: perform) {
            DemoTintedSurface(
                cornerRadius: 16,
                contentPadding: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0),
                colors: colors,
                stroke: DemoTheme.surfaceStroke
            ) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: systemImage)
                        .foregroundColor(DemoTheme.primaryText)
                        .font(.system(size: 14))
                        .frame(width: 18, height: 18)

                    Text(title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(DemoTheme.primaryText)
                        .multilineTextAlignment(.leading)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
                .padding(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14))
                .frame(height: 42, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}
struct DemoRowButton: View {
    let title: String
    let detail: String
    let systemImage: String
    let accent: Color
    let perform: @MainActor @Sendable () -> Void

    var body: some View {
        Button(action: perform) {
            DemoGlassSurface(
                cornerRadius: 20,
                contentPadding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14),
                fill: LinearGradient(
                    colors: [DemoTheme.fieldTop, DemoTheme.fieldBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                stroke: DemoTheme.surfaceStroke
            ) {
                HStack(alignment: .center, spacing: 14) {
                    Color.clear
                        .frame(width: 8, height: 44)
                        .background(
                            LinearGradient(
                                colors: [accent.opacity(0.94), accent.opacity(0.62)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .cornerRadius(4)
                        .allowsHitTesting(false)

                    DemoTintedSurface(
                        cornerRadius: 16,
                        contentPadding: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0),
                        colors: [accent.opacity(0.90), accent.opacity(0.62)],
                        stroke: DemoTheme.surfaceStroke
                    ) {
                        Image(systemName: systemImage)
                            .foregroundColor(DemoTheme.inverseText)
                            .font(.system(size: 15))
                            .frame(width: 30, height: 30)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(DemoTheme.primaryText)
                            .multilineTextAlignment(.leading)
                            .lineLimit(1)

                        Text(detail)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(DemoTheme.tertiaryText)
                            .multilineTextAlignment(.leading)
                            .lineLimit(1)
                    }
                    .layoutPriority(1)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
struct DemoMetricCard: View {
    let title: String
    let value: String
    let note: String
    let accent: Color

    var body: some View {
        DemoGlassSurface(cornerRadius: 26) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(DemoTheme.tertiaryText)
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)

                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(DemoTheme.primaryText)
                    .multilineTextAlignment(.leading)

                Text(note)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(accent)
                    .multilineTextAlignment(.leading)
            }
        }
    }
}
struct DemoActivityCard: View {
    let title: String
    let detail: String
    let systemImage: String
    let accent: Color

    var body: some View {
        DemoRowButton(title: title, detail: detail, systemImage: systemImage, accent: accent) {}
            .allowsHitTesting(false)
    }
}
struct DemoInfoCard: View {
    let card: DemoCard

    var body: some View {
        DemoGlassSurface(
            cornerRadius: 24,
            fill: LinearGradient(
                colors: [DemoTheme.fieldTop, DemoTheme.fieldBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            stroke: DemoTheme.surfaceStroke
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text(card.title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(DemoTheme.primaryText)
                    .multilineTextAlignment(.leading)

                Text(card.summary)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(DemoTheme.secondaryText)
                    .multilineTextAlignment(.leading)

                Text(card.meta)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(card.accent)
                    .multilineTextAlignment(.leading)
            }
        }
    }
}
struct DemoAccent: View {
    let frame: CGRect
    let fill: LinearGradient

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: frame.origin.y)

            HStack(alignment: .center, spacing: 0) {
                Color.clear.frame(width: frame.origin.x)
                Color.clear
                    .frame(width: frame.size.width, height: frame.size.height)
                    .background(fill)
                    .cornerRadius(32)
                    .allowsHitTesting(false)
            }
        }
        .allowsHitTesting(false)
    }
}
enum DemoTheme {
    static let backdropTop = Color(red: 0.91, green: 0.95, blue: 0.92, opacity: 1.0)
    static let backdropMiddle = Color(red: 0.88, green: 0.92, blue: 0.97, opacity: 1.0)
    static let backdropBottom = Color(red: 0.96, green: 0.95, blue: 0.91, opacity: 1.0)
    static let surfaceTop = Color(red: 0.99, green: 0.99, blue: 1.0, opacity: 0.92)
    static let surfaceBottom = Color(red: 0.93, green: 0.95, blue: 0.98, opacity: 0.86)
    static let fieldTop = Color(red: 0.97, green: 0.98, blue: 1.0, opacity: 0.96)
    static let fieldBottom = Color(red: 0.91, green: 0.94, blue: 0.98, opacity: 0.90)
    static let sidebarTop = Color(red: 0.95, green: 0.96, blue: 0.98, opacity: 0.90)
    static let sidebarBottom = Color(red: 0.89, green: 0.92, blue: 0.96, opacity: 0.84)
    static let surfaceStroke = Color(red: 0.39, green: 0.47, blue: 0.60, opacity: 0.14)
    static let surfaceStrokeStrong = Color(red: 0.32, green: 0.42, blue: 0.58, opacity: 0.18)
    static let primaryText = Color(red: 0.18, green: 0.22, blue: 0.30, opacity: 0.96)
    static let secondaryText = Color(red: 0.34, green: 0.40, blue: 0.50, opacity: 0.86)
    static let tertiaryText = Color(red: 0.46, green: 0.52, blue: 0.62, opacity: 0.80)
    static let inverseText = Color(red: 0.99, green: 1.0, blue: 1.0, opacity: 0.98)
    /// Light secondary text for content that sits on the dark hero card.
    static let heroSubtitleText = Color(red: 0.80, green: 0.86, blue: 0.95, opacity: 0.92)
    static let shadow = Color(red: 0.16, green: 0.20, blue: 0.30, opacity: 0.10)
}
struct DemoLayout {
    let size: CGSize

    var compact: Bool { size.width < 1180 || size.height < 760 }
    var outerPadding: CGFloat { compact ? 18 : 24 }
    var gap: CGFloat { compact ? 14 : 18 }
    var columnGap: CGFloat { compact ? 14 : 18 }
    var toolbarHeight: CGFloat { compact ? 72 : 80 }
    var bodyHeight: CGFloat { max(280, size.height - outerPadding * 2 - toolbarHeight - gap) }
    var sidebarWidth: CGFloat { compact ? 220 : 236 }
    var railWidth: CGFloat { compact ? 260 : 292 }
    var contentWidth: CGFloat {
        max(420, size.width - outerPadding * 2 - sidebarWidth - railWidth - columnGap * 2)
    }
    var contentInnerWidth: CGFloat { max(380, contentWidth - 8) }
    var railInnerWidth: CGFloat { max(220, railWidth - 8) }
    var sidebarInnerWidth: CGFloat { max(180, sidebarWidth - 16) }
    var metricCardWidth: CGFloat {
        max(120, (contentInnerWidth - gap * 2) / 3)
    }
    var toolbarCornerRadius: CGFloat { compact ? 22 : 26 }
    var panelCornerRadius: CGFloat { compact ? 22 : 26 }
    var toolbarTitleWidth: CGFloat { compact ? 180 : 220 }
    var searchWidth: CGFloat { compact ? 220 : 280 }
    var backendWidth: CGFloat { compact ? 96 : 112 }
    var eventsWidth: CGFloat { compact ? 116 : 128 }
    var modeWidth: CGFloat { compact ? 126 : 146 }
    var pillHeight: CGFloat { 34 }
    var headlineSize: CGFloat { compact ? 24 : 30 }
    var heroHeight: CGFloat { compact ? 210 : 232 }
    var compactActions: Bool { compact }

    var toolbarPadding: EdgeInsets {
        compact
            ? EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
            : EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
    }

    var panelPadding: EdgeInsets {
        compact
            ? EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
            : EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
    }

    var accentA: CGRect {
        CGRect(
            x: outerPadding + size.width * 0.18,
            y: outerPadding + toolbarHeight + gap + 18,
            width: compact ? 160 : 240,
            height: compact ? 84 : 126
        )
    }

    var accentB: CGRect {
        CGRect(
            x: outerPadding + size.width * 0.70,
            y: outerPadding + toolbarHeight + heroHeight + gap * 2,
            width: compact ? 132 : 180,
            height: compact ? 68 : 94
        )
    }
}
struct DemoCard {
    let title: String
    let summary: String
    let meta: String
    let accent: Color
}
struct DemoAction {
    let title: String
    let caption: String
    let systemImage: String
    let eventLabel: String
}
enum DemoModule: CaseIterable, Hashable {
    case layout
    case input
    case animation
    case controls

    var label: String {
        switch self {
        case .layout: return "LAYOUT"
        case .input: return "INPUT"
        case .animation: return "ANIMATION"
        case .controls: return "CONTROLS"
        }
    }

    var statusLabel: String { "MODE: \(label)" }
    var headline: String {
        switch self {
        case .layout: return "PURE SWIFT LAYOUT CORE"
        case .input: return "POINTER AND KEYBOARD ROUTING"
        case .animation: return "FRAME-DRIVEN UI MOTION"
        case .controls: return "NATIVE CONTROL GALLERY"
        }
    }

    var summary: String {
        switch self {
        case .layout: return "RESPONSIVE COMPOSITION AND PANEL STRUCTURE"
        case .input: return "HOVER, PRESS, FOCUS, AND SCROLL ROUTING"
        case .animation: return "FRAME-TIMED STATE TRANSITIONS AND CHROME"
        case .controls: return "TOGGLE, SLIDER, STEPPER, AND INPUT RENDERING"
        }
    }

    var detailLine: String {
        switch self {
        case .layout: return "STACK  SCROLL  CLIP  INTRINSIC"
        case .input: return "HOVER  PRESS  FOCUS  ACTIVATE"
        case .animation: return "TIMERS  PALETTES  STATE  REDRAW"
        case .controls: return "TOGGLE  SLIDER  STEP  PICK"
        }
    }

    var systemImage: String {
        switch self {
        case .layout: return "rectangle.3.group"
        case .input: return "keyboard"
        case .animation: return "sparkles"
        case .controls: return "switch.2"
        }
    }

    var glowColor: Color {
        switch self {
        case .layout: return Color(red: 0.42, green: 0.68, blue: 0.96, opacity: 0.94)
        case .input: return Color(red: 0.36, green: 0.80, blue: 0.74, opacity: 0.94)
        case .animation: return Color(red: 1.0, green: 0.69, blue: 0.44, opacity: 0.96)
        case .controls: return Color(red: 0.72, green: 0.48, blue: 0.96, opacity: 0.94)
        }
    }

    var stripeColor: Color {
        switch self {
        case .layout: return Color(red: 0.58, green: 0.80, blue: 1.0, opacity: 0.90)
        case .input: return Color(red: 0.56, green: 0.88, blue: 0.82, opacity: 0.90)
        case .animation: return Color(red: 1.0, green: 0.80, blue: 0.54, opacity: 0.92)
        case .controls: return Color(red: 0.82, green: 0.62, blue: 1.0, opacity: 0.90)
        }
    }

    var fillColor: Color {
        switch self {
        case .layout: return Color(red: 0.19, green: 0.25, blue: 0.38, opacity: 0.84)
        case .input: return Color(red: 0.16, green: 0.28, blue: 0.30, opacity: 0.84)
        case .animation: return Color(red: 0.31, green: 0.24, blue: 0.18, opacity: 0.84)
        case .controls: return Color(red: 0.28, green: 0.20, blue: 0.36, opacity: 0.84)
        }
    }

    var accentColor: Color {
        switch self {
        case .layout: return Color(red: 0.30, green: 0.40, blue: 0.58, opacity: 0.98)
        case .input: return Color(red: 0.24, green: 0.42, blue: 0.44, opacity: 0.98)
        case .animation: return Color(red: 0.46, green: 0.36, blue: 0.26, opacity: 0.98)
        case .controls: return Color(red: 0.44, green: 0.32, blue: 0.58, opacity: 0.98)
        }
    }

    var panelStartColor: Color {
        switch self {
        case .layout: return Color(red: 0.18, green: 0.24, blue: 0.37, opacity: 0.97)
        case .input: return Color(red: 0.15, green: 0.25, blue: 0.29, opacity: 0.97)
        case .animation: return Color(red: 0.26, green: 0.21, blue: 0.18, opacity: 0.97)
        case .controls: return Color(red: 0.24, green: 0.18, blue: 0.34, opacity: 0.97)
        }
    }

    var panelEndColor: Color {
        switch self {
        case .layout: return Color(red: 0.11, green: 0.16, blue: 0.27, opacity: 0.94)
        case .input: return Color(red: 0.10, green: 0.18, blue: 0.22, opacity: 0.94)
        case .animation: return Color(red: 0.18, green: 0.15, blue: 0.13, opacity: 0.94)
        case .controls: return Color(red: 0.17, green: 0.13, blue: 0.24, opacity: 0.94)
        }
    }

    var cards: [DemoCard] {
        switch self {
        case .layout:
            return [
                DemoCard(
                    title: "STACK LAYOUT", summary: "PANELS STRETCH WITH PRIORITY AND PADDING",
                    meta: "RETENTION-FIRST MEASUREMENT", accent: accentColor),
                DemoCard(
                    title: "CLIPPING", summary: "SCISSOR-READY RECT CLIPPING THROUGH THE RENDER FRAME",
                    meta: "BACKEND-NEUTRAL COMMANDS", accent: accentColor),
            ]
        case .input:
            return [
                DemoCard(
                    title: "FOCUS CHAIN", summary: "TAB MOVES THROUGH FOCUSABLE RETAINED NODES",
                    meta: "WINDOW DELEGATE TO RUNTIME", accent: accentColor),
                DemoCard(
                    title: "PRESS STATES", summary: "BUTTONS DRIVE FOCUSED, PRESSED, AND ACTIVATED COLORS",
                    meta: "MAIN-ACTOR CONTROL LIFECYCLE", accent: accentColor),
            ]
        case .animation:
            return [
                DemoCard(
                    title: "TICK DRIVER", summary: "WINDOW ANIMATION FRAMES ADVANCE COLOR TRANSITIONS",
                    meta: "ONLY WHEN ACTIVE", accent: accentColor),
                DemoCard(
                    title: "FRAME CACHE", summary: "UNCHANGED UI REUSES THE LAST RENDER FRAME UNTIL INVALIDATED",
                    meta: "RETENTION REDRAWS", accent: accentColor),
            ]
        case .controls:
            return [
                DemoCard(
                    title: "TOGGLE AND SLIDER", summary: "INTERACTIVE BINDING-DRIVEN CONTROLS",
                    meta: "HIT-TEST AND FOCUS", accent: accentColor),
                DemoCard(
                    title: "TEXT INPUT", summary: "TEXTFIELD AND TEXTEDITOR WITH STATE", meta: "KEYBOARD ROUTING",
                    accent: accentColor),
            ]
        }
    }

    var actions: [DemoAction] {
        switch self {
        case .layout:
            return [
                DemoAction(
                    title: "Inspect Stacks", caption: "READ THE CONTAINER TREE", systemImage: "rectangle.3.group",
                    eventLabel: "STACK INSPECTOR OPENED"),
                DemoAction(
                    title: "Resize Panes", caption: "DRAG THE SPLIT DIVIDERS", systemImage: "rectangle.split.3x1",
                    eventLabel: "PANE EDITOR OPENED"),
            ]
        case .input:
            return [
                DemoAction(
                    title: "Focus Walk", caption: "TAB THROUGH CONTROLS", systemImage: "keyboard",
                    eventLabel: "FOCUS WALK STARTED"),
                DemoAction(
                    title: "Route Events", caption: "TRACE POINTER TO NODE", systemImage: "waveform.path.ecg",
                    eventLabel: "INPUT TRACE OPENED"),
            ]
        case .animation:
            return [
                DemoAction(
                    title: "Play Motion", caption: "RETRIGGER THE STATUS CYCLE", systemImage: "sparkles",
                    eventLabel: "MOTION LOOP STARTED"),
                DemoAction(
                    title: "Inspect Ticks", caption: "FOLLOW RUNTIME INVALIDATION", systemImage: "bolt.fill",
                    eventLabel: "TICK INSPECTOR OPENED"),
            ]
        case .controls:
            return [
                DemoAction(
                    title: "Toggle Demo", caption: "SWITCH STATES AND BINDINGS", systemImage: "switch.2",
                    eventLabel: "TOGGLE DEMO OPENED"),
                DemoAction(
                    title: "Input Forms", caption: "TEXT AND PICKER LAYOUT", systemImage: "textformat",
                    eventLabel: "INPUT FORM OPENED"),
            ]
        }
    }
}

// MARK: - Multi-screen shell

/// Top-level screens of the product-style demo, navigated through `TabView`.
public enum DemoScreen: String, CaseIterable, Hashable {
    case dashboard
    case settings
    case data

    var label: String {
        switch self {
        case .dashboard: return "DASHBOARD"
        case .settings: return "SETTINGS"
        case .data: return "DATA"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "rectangle.3.group"
        case .settings: return "gearshape"
        case .data: return "doc.text"
        }
    }
}

/// Theme choices shown by the settings screen picker.
public enum DemoThemeOption: String, CaseIterable, Hashable {
    case system
    case light
    case dark
}

/// A runtime component row shown on the data screen.
public struct DemoComponent: Identifiable, Hashable, Sendable {
    public let id: Int
    let name: String
    let detail: String
    let version: String
    let systemImage: String
    let load: Double

    var isHealthy: Bool { load < 0.85 }
    var statusLabel: String { isHealthy ? "HEALTHY" : "DEGRADED" }

    static let defaults: [DemoComponent] = [
        DemoComponent(
            id: 1, name: "RENDER HOST", detail: "D3D11 BATCH PIPELINE", version: "V2.4.1",
            systemImage: "bolt.fill", load: 0.34),
        DemoComponent(
            id: 2, name: "INPUT ROUTER", detail: "POINTER AND KEYBOARD DISPATCH", version: "V1.9.0",
            systemImage: "keyboard", load: 0.12),
        DemoComponent(
            id: 3, name: "LAYOUT ENGINE", detail: "RETAINED STACK MEASUREMENT", version: "V3.1.2",
            systemImage: "rectangle.3.group", load: 0.48),
        DemoComponent(
            id: 4, name: "ANIMATION TICKER", detail: "FRAME-DRIVEN STATE TRANSITIONS", version: "V1.4.0",
            systemImage: "sparkles", load: 0.27),
        DemoComponent(
            id: 5, name: "CONTROL SURFACES", detail: "BUTTONS, TOGGLES, AND PICKERS", version: "V2.0.3",
            systemImage: "switch.2", load: 0.56),
        DemoComponent(
            id: 6, name: "EVENT LOG", detail: "INTERACTION TELEMETRY BUFFER", version: "V0.9.8",
            systemImage: "waveform.path.ecg", load: 0.71),
        DemoComponent(
            id: 7, name: "DOCUMENT STORE", detail: "SETTINGS PERSISTENCE LAYER", version: "V1.2.5",
            systemImage: "doc.text", load: 0.18),
        DemoComponent(
            id: 8, name: "SYSTEM PROBE", detail: "HEALTH AND DIAGNOSTICS", version: "V0.7.2",
            systemImage: "info.circle", load: 0.90),
    ]
}

// MARK: - Settings screen

/// Settings-style form exercising Supported-tier controls: text field,
/// segmented picker, stepper, toggles, slider, gauge, progress, and buttons.
struct DemoSettingsScreen: View {
    @ObservedObject var model: DemoDashboardModel

    var body: some View {
        NavigationStack {
            // The form is taller than small windows; scroll instead of
            // squeezing sections until their tracks vanish.
            ScrollView {
                Form {
                    Section("Profile") {
                        TextField("Display Name", text: $model.displayName)

                        Picker("Theme", selection: $model.theme) {
                            Text("SYSTEM").tag(DemoThemeOption.system)
                            Text("LIGHT").tag(DemoThemeOption.light)
                            Text("DARK").tag(DemoThemeOption.dark)
                        }
                        .pickerStyle(.segmented)

                        Stepper(
                            "Items Per Page: \(model.itemsPerPage)",
                            value: $model.itemsPerPage,
                            in: 5...30,
                            step: 5
                        )
                    }

                    Section("Preferences") {
                        Toggle("Enable Animations", isOn: $model.animationsEnabled)
                        Toggle("Sound Effects", isOn: $model.soundEffectsEnabled)
                        Toggle("Share Usage Data", isOn: $model.shareUsageData)

                        Divider()

                        Slider(value: $model.fontScale, in: 0.8...1.4) {
                            Text("Font Scale")
                        }
                    }

                    Section("Resources") {
                        Gauge(value: model.storageUsed, in: 0...1) {
                            Text("Storage Used")
                        }

                        ProgressView("Sync Progress", value: model.syncProgress)

                        Button("Sync Now") {
                            model.runSync()
                        }
                    }

                    Section("Actions") {
                        Button("Save Settings") {
                            model.saveSettings()
                        }

                        Button("Reset To Defaults", role: .destructive) {
                            model.resetSettings()
                        }
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

// MARK: - Data screen

/// Selection-bound list of runtime components with a detail panel that
/// exercises labels, progress chrome, dividers, and action buttons.
struct DemoDataScreen: View {
    @ObservedObject var model: DemoDashboardModel

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let contentWidth = max(320, proxy.size.width - 32)

                VStack(alignment: .leading, spacing: 12) {
                    List(model.components, selection: $model.selectedComponentID) { component in
                        DemoComponentRow(component: component)
                    }
                    .frame(
                        width: contentWidth,
                        height: max(200, proxy.size.height - 224),
                        alignment: .topLeading
                    )

                    Divider()
                        .frame(width: contentWidth)

                    DemoComponentDetail(model: model)
                        .frame(width: contentWidth, alignment: .leading)
                }
                .padding(16)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
            .navigationTitle("Components")
        }
    }
}

struct DemoComponentRow: View {
    let component: DemoComponent

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Label(component.name, systemImage: component.systemImage)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(component.version)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(DemoTheme.secondaryText)
                    .lineLimit(1)

                Text(component.statusLabel)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(
                        component.isHealthy
                            ? Color(red: 0.30, green: 0.62, blue: 0.44, opacity: 0.95)
                            : Color(red: 0.85, green: 0.48, blue: 0.20, opacity: 0.95)
                    )
                    .lineLimit(1)
            }
        }
    }
}

struct DemoComponentDetail: View {
    @ObservedObject var model: DemoDashboardModel

    var body: some View {
        if let component = model.selectedComponent {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(component.name, systemImage: component.systemImage)

                    Text(component.detail)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(DemoTheme.secondaryText)
                        .lineLimit(1)

                    Text("VERSION \(component.version)  STATUS \(component.statusLabel)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(DemoTheme.tertiaryText)
                        .lineLimit(1)
                }
                .layoutPriority(1)

                Spacer(minLength: 8)

                VStack(alignment: .leading, spacing: 6) {
                    Text("CURRENT LOAD")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(DemoTheme.tertiaryText)
                        .lineLimit(1)

                    ProgressView(value: component.load)
                }
                .frame(width: 180, alignment: .leading)

                HStack(alignment: .center, spacing: 10) {
                    Button("Restart") {
                        model.restartSelectedComponent()
                    }

                    Button("Diagnose") {
                        model.runDiagnostics()
                    }
                }
            }
        } else {
            HStack(alignment: .center, spacing: 12) {
                Label("No Component Selected", systemImage: "info.circle")

                Spacer(minLength: 8)

                Button("Select First") {
                    model.selectFirstComponent()
                }
            }
        }
    }
}
