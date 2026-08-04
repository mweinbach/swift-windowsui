// Scoped, not `import Foundation`: corelibs-Foundation exports its own
// CG geometry types, and pulling the whole module in makes every
// `CGRect(x: a + b, …)` in the layout ambiguous enough to time out the
// type-checker. A scoped import still surfaces the member extensions
// (`.number` on `IntegerFormatStyle`) the settings form needs.
import struct Foundation.IntegerFormatStyle
import struct Foundation.URL

#if canImport(SwiftUI)
    import SwiftUI
#else
    import WinSwiftUI
#endif
#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

@MainActor
public final class DemoDashboardModel: ObservableObject {
    @Published var selectedModule: DemoModule = .layout
    @Published var interactionCount = 0
    @Published var lastAction = "Ready"
    @Published var recentEvents: [String] = [
        "System ready",
        "D3D11 ready",
        "Window toolkit active",
    ]

    /// Active top-level screen shown by the demo's `TabView` shell.
    @Published public var selectedScreen: DemoScreen = .dashboard {
        didSet {
            if selectedScreen != oldValue {
                performAction("Opened \(selectedScreen.label)")
            }
        }
    }

    // Settings screen state
    @Published var displayName = "Operator"
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

    // Integration surface state (color picker, file importer, drop target)
    @Published var accentColor: Color = .blue

    public init() {}

    /// Currently selected component on the data screen, if any.
    public var selectedComponent: DemoComponent? {
        components.first { $0.id == selectedComponentID }
    }

    func selectScreen(_ screen: DemoScreen) {
        selectedScreen = screen
    }

    func saveSettings() {
        performAction("Saved settings for \(displayName)")
    }

    func resetSettings() {
        displayName = "Operator"
        theme = .system
        itemsPerPage = 10
        animationsEnabled = true
        soundEffectsEnabled = false
        shareUsageData = true
        fontScale = 1.0
        performAction("Reset settings to defaults")
    }

    func runSync() {
        syncProgress = min(1.0, syncProgress + 0.25)
        performAction(syncProgress >= 1.0 ? "Sync complete" : "Sync advanced")
    }

    func restartSelectedComponent() {
        guard let component = selectedComponent else {
            performAction("No component selected")
            return
        }
        performAction("Restarted \(component.name)")
    }

    func runDiagnostics() {
        guard let component = selectedComponent else {
            performAction("No component selected")
            return
        }
        performAction("Diagnosed \(component.name)")
    }

    func selectFirstComponent() {
        selectedComponentID = components.first?.id
    }

    func noteImportedFile(_ url: URL) {
        performAction("Imported \(url.lastPathComponent)")
    }

    func noteDroppedItems(count: Int) {
        performAction("Received \(count) dropped \(count == 1 ? "file" : "files")")
    }

    func selectModule(_ module: DemoModule) {
        selectedModule = module
        performAction("Selected \(module.label)")
    }

    func cycleModule() {
        let modules = DemoModule.allCases
        guard let index = modules.firstIndex(of: selectedModule) else {
            return
        }

        let nextIndex = modules.index(after: index)
        selectedModule = nextIndex == modules.endIndex ? modules[modules.startIndex] : modules[nextIndex]
        performAction("Cycled \(selectedModule.label)")
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
                            model.selectedModule.glowColor.opacity(0.16),
                            model.selectedModule.stripeColor.opacity(0.04),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

                DemoAccent(
                    frame: layout.accentB,
                    fill: LinearGradient(
                        colors: [
                            model.selectedModule.stripeColor.opacity(0.13),
                            model.selectedModule.glowColor.opacity(0.03),
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
    @Environment(\.colorScheme) private var colorScheme
    private var theme: DemoTheme { DemoTheme(colorScheme: colorScheme) }

    let model: DemoDashboardModel
    let layout: DemoLayout

    var body: some View {
        // The toolbar band is a panel like any other; it used to restate the
        // panel's own default fill only to run it corner to corner, which put
        // a left-to-right lightness ramp across the top of the window.
        DemoGlassSurface(
            cornerRadius: layout.toolbarCornerRadius,
            contentPadding: layout.toolbarPadding,
            stroke: theme.surfaceStrokeStrong,
            shadowColor: theme.shadow
        ) {
            HStack(alignment: .center, spacing: layout.gap) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("WinSwiftUI")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(1)

                    Text("Same-source dashboard demo")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(1)
                }
                .frame(width: layout.toolbarTitleWidth, alignment: .leading)

                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))

                    Text("Search commands")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(1)
                }
                .padding(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14))
                .frame(width: layout.searchWidth, height: layout.pillHeight, alignment: .leading)
                .background(
                    LinearGradient(
                        colors: [theme.fieldTop, theme.fieldBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(layout.pillHeight * 0.5)
                .padding(1)
                .background(theme.surfaceStroke)
                .cornerRadius(layout.pillHeight * 0.5 + 1)
                .allowsHitTesting(false)
                .layoutPriority(1)

                Spacer(minLength: 0)

                DemoPillButton(
                    "D3D11",
                    width: layout.backendWidth,
                    colors: DemoTheme.readyFill
                ) {
                    model.performAction("Render stack ready")
                }

                DemoPillButton(
                    "Events \(model.interactionCount)",
                    width: layout.eventsWidth,
                    colors: DemoTheme.eventsFill
                ) {
                    model.performAction("Event HUD opened")
                }

                DemoPillButton(
                    model.selectedModule.statusLabel,
                    width: layout.modeWidth,
                    colors: model.selectedModule.accentFill
                ) {
                    model.cycleModule()
                }
            }
        }
        .frame(height: layout.toolbarHeight, alignment: .leading)
    }
}
struct DemoSidebar: View {
    @Environment(\.colorScheme) private var colorScheme
    private var theme: DemoTheme { DemoTheme(colorScheme: colorScheme) }

    let model: DemoDashboardModel
    let layout: DemoLayout

    var body: some View {
        DemoGlassSurface(
            cornerRadius: layout.panelCornerRadius,
            contentPadding: .zero,
            fill: LinearGradient(
                colors: [theme.sidebarTop, theme.sidebarBottom],
                startPoint: .top,
                endPoint: .bottom
            ),
            stroke: theme.surfaceStrokeStrong
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    DemoSectionTitle("Workspace")

                    // No hand-computed row width: every child fills the
                    // sidebar's own content width. The literal it used to carry
                    // was wider than the padded panel, so each row hung a
                    // couple of points over both edges of the surface it was
                    // supposed to be inside.
                    //
                    // A macOS source list fills the selected row with the
                    // accent and writes it in white — in *both* appearances.
                    // The selected row used to carry the module's glow at 0.92
                    // under a `.primary` label, which is a white label on a
                    // pale blue in the dark appearance.
                    ForEach(DemoModule.allCases, id: \.self) { module in
                        let isSelected = model.selectedModule == module
                        DemoModuleButton(
                            systemImage: module.systemImage,
                            title: module.label,
                            colors: isSelected ? module.accentFill : [theme.fieldTop, theme.fieldBottom],
                            textColor: isSelected ? theme.onTintedFillText : Color.primary
                        ) {
                            model.selectModule(module)
                        }
                    }

                    // A group boundary, the way a macOS source list draws one: a
                    // second eyebrow, not a rule. The 4pt accent bar that
                    // used to sit here had no semantic job — it was not a
                    // selection indicator (the selected row already carries
                    // the accent fill), not a separator (nothing in a source
                    // list separates with saturated colour), and not a
                    // progress bar (though at full width it read as one at
                    // 100%). The two rows under it are a different *kind* of
                    // thing from the module list — session status, not
                    // navigation — and the sidebar already speaks the
                    // eyebrow language: "Workspace" introduces the first
                    // group, so "Session" introduces the second.
                    DemoSectionTitle("Session")
                        .padding(.top, 6)

                    DemoRowButton(
                        title: "State",
                        detail: model.lastAction,
                        systemImage: "info.circle",
                        accent: model.selectedModule.accentFill
                    ) {
                        model.performAction("State panel opened")
                    }

                    DemoRowButton(
                        title: "Shortcuts",
                        detail: "Tab and wheel routing",
                        systemImage: "keyboard",
                        accent: model.selectedModule.accentFill
                    ) {
                        model.performAction("Shortcuts opened")
                    }
                }
                // The width lives here, once, and it is the surface's own
                // content width: a scroll view proposes no definite width to
                // its content, so without it every greedy child in the column
                // falls back to its own text and the sidebar frays into a
                // ragged stack. The literal this replaced was `sidebarWidth -
                // 16`, which was wider than the padded panel — every row hung
                // over both edges of the surface it was supposed to be in.
                .frame(width: layout.sidebarRowWidth, alignment: .leading)
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
                        DemoSectionTitle("Render pipeline")

                        // The panel's own content width, not a literal 32 that
                        // happened to be near it: the panel pads by 14 in a
                        // compact window and 16 otherwise, so the flat 32 left
                        // the plot short of the panel's right inset in one of
                        // the two and over it in the other.
                        DemoRenderPipelineChart(model: model)
                            .frame(
                                width: layout.contentInnerWidth
                                    - layout.panelPadding.leading - layout.panelPadding.trailing - 2,
                                height: layout.chartHeight
                            )
                            .clipped()
                    }
                }
                .frame(width: layout.contentInnerWidth, alignment: .leading)

                if layout.stacksMetrics {
                    VStack(alignment: .leading, spacing: 14) {
                        DemoMetricCard(
                            title: "Interactions", value: "\(model.interactionCount)", note: "Events tracked"
                        )
                        .frame(width: layout.contentInnerWidth, alignment: .leading)
                        DemoMetricCard(
                            title: "Module", value: model.selectedModule.label, note: model.selectedModule.summary
                        )
                        .frame(width: layout.contentInnerWidth, alignment: .leading)
                        DemoMetricCard(
                            title: "Target", value: "Same source", note: "Import WinSwiftUI or SwiftUI"
                        )
                        .frame(width: layout.contentInnerWidth, alignment: .leading)
                    }
                } else {
                    HStack(alignment: .center, spacing: 18) {
                        DemoMetricCard(
                            title: "Interactions", value: "\(model.interactionCount)", note: "Events tracked"
                        )
                        .frame(width: layout.metricCardWidth, alignment: .leading)
                        DemoMetricCard(
                            title: "Module", value: model.selectedModule.label, note: model.selectedModule.summary
                        )
                        .frame(width: layout.metricCardWidth, alignment: .leading)
                        DemoMetricCard(
                            title: "Target", value: "Same source", note: "Import WinSwiftUI or SwiftUI"
                        )
                        .frame(width: layout.metricCardWidth, alignment: .leading)
                    }
                    .frame(width: layout.contentInnerWidth, alignment: .leading)
                }

                DemoPanel {
                    VStack(alignment: .leading, spacing: 14) {
                        DemoSectionTitle("Activity")

                        ForEach(model.recentEvents.prefix(5), id: \.self) { event in
                            DemoActivityCard(
                                title: event,
                                detail: model.selectedModule.detailLine,
                                systemImage: model.selectedModule.systemImage,
                                accent: model.selectedModule.accentFill
                            )
                        }
                    }
                }
                .frame(width: layout.contentInnerWidth, alignment: .leading)
            }
        }
    }
}

/// Canvas-driven mini bar chart embedded in the dashboard's center pane.
/// Demonstrates the SwiftUI-shape `GraphicsContext` API (fillRect with color
/// and linear-gradient shading, `drawLayer`, `translateBy`) against the same
/// shared demo source compatible with macOS SwiftUI.
struct DemoRenderPipelineChart: View {
    @Environment(\.colorScheme) private var colorScheme

    let model: DemoDashboardModel

    var body: some View {
        let plotBackground = DemoTheme(colorScheme: colorScheme).fieldTop
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
                        plotBackground.opacity(0.55),
                        plotBackground.opacity(0.30),
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
                    // Square corners read as a filled table cell; a real chart
                    // bar carries a small radius. Keep it under half the bar
                    // width so a thin series never turns into a column of
                    // capsules.
                    //
                    // A solid shading, not the gradient the square bar used:
                    // `GraphicsContext` gradients are a *rect* feature in this
                    // stack (docs/CompatibilityStatus.md — `Canvas` is Partial),
                    // and a same-source demo must not read as correct only
                    // because a gap degrades quietly. The bar keeps its
                    // per-bar emphasis through the layer opacity above.
                    let radius = min(2.5, barWidth / 2)
                    sub.fill(
                        Path(
                            roundedRect: CGRect(x: 0, y: 0, width: barWidth, height: barHeight),
                            cornerRadius: radius
                        ),
                        with: .color(bar.fill)
                    )
                }

                index += 1
            }
        }
    }

    private struct Bar {
        let value: CGFloat
        let emphasis: CGFloat
        let fill: Color
    }

    private static func bars(interactions: Int, glow: Color, stripe: Color) -> [Bar] {
        let pattern: [CGFloat] = [0.35, 0.52, 0.40, 0.68, 0.56, 0.82, 0.64, 0.94, 0.72, 0.58]
        return pattern.enumerated().map { index, base in
            let phase = (Double(index) + Double(interactions) * 0.13).truncatingRemainder(dividingBy: 1)
            let value = min(1, max(0.10, base + CGFloat(phase) * 0.10))
            let emphasis = CGFloat(phase)
            // One series, two module tones: the taller half of the series
            // carries the module's glow, the shorter its stripe. A chart reads
            // as a chart because its bars share a colour, not because each one
            // is a gradient.
            return Bar(
                value: value,
                emphasis: emphasis,
                fill: base >= 0.6 ? glow : stripe
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
                    // 12, not 14: the rail carries two panels in the height
                    // the centre pane spends on one, so its internal rhythm
                    // is a step tighter than the centre column's.
                    VStack(alignment: .leading, spacing: 12) {
                        DemoSectionTitle("Detail track")

                        ForEach(model.selectedModule.cards, id: \.title) { card in
                            DemoInfoCard(card: card)
                        }
                    }
                }
                .frame(width: layout.railInnerWidth, alignment: .leading)

                DemoPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        DemoSectionTitle("Quick actions")

                        ForEach(model.selectedModule.actions, id: \.title) { action in
                            DemoRowButton(
                                title: action.title,
                                detail: action.caption,
                                systemImage: action.systemImage,
                                accent: model.selectedModule.accentFill
                            ) {
                                model.performAction(action.eventLabel)
                            }
                        }
                    }
                }
                .frame(width: layout.railInnerWidth, alignment: .leading)
            }
        }
    }
}
struct DemoHeroCard: View {
    @Environment(\.colorScheme) private var colorScheme
    private var theme: DemoTheme { DemoTheme(colorScheme: colorScheme) }

    let model: DemoDashboardModel
    let layout: DemoLayout

    var body: some View {
        DemoTintedSurface(
            cornerRadius: layout.panelCornerRadius + 4,
            contentPadding: layout.panelPadding,
            // The one card in the app with a tint of its own. It is a tint of
            // the *appearance*, not a fixed navy: a deep module-tinted card in
            // dark mode, a pale module-tinted one in light. It used to be navy
            // in both, which put a dark slab in the middle of the light
            // dashboard and made a light desktop read as a dark app.
            colors: [
                theme.heroTop(model.selectedModule),
                theme.heroBottom(model.selectedModule),
            ],
            stroke: theme.surfaceStrokeStrong,
            // A glow-tinted halo under the dark hero, the neutral panel
            // shadow under the light one: a blue shadow on a light window
            // reads as a cool smudge, not as ambience.
            shadowColor: colorScheme == .dark
                ? model.selectedModule.glowColor.opacity(0.12)
                : theme.shadow
        ) {
            // 14, not 18. Five rungs at 18 plus a 38pt pill row measured 214
            // inside a 210pt card, and a fixed-height card answers an
            // overflow by squeezing: the pills came out 31pt tall rather than
            // the 38 they asked for. The card's height is what the metric
            // band below it is positioned against, so the rhythm gives way
            // here rather than the card growing.
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 10) {
                    DemoCapsuleText("Control center")
                    DemoCapsuleText(model.selectedModule.label, tint: model.selectedModule.fillTop)
                }

                // Semantic rungs, not white: the card is dark in one
                // appearance and pale in the other, and `.primary` is the only
                // value that is legible on both.
                Text(model.selectedModule.headline)
                    .font(.system(size: layout.headlineSize, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)

                Text(model.selectedModule.summary)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)

                // The accent rule takes the accent *fill*, not the glow it
                // used to: a pale hue at 0.94 alpha over a pale hero card is
                // the same colour as the card, and the rule was invisible in
                // the light appearance. 4pt rather than 12, for the same
                // reason as the sidebar's — a saturated band that wide across
                // a card is a progress bar, not a rule.
                Color.clear
                    .frame(
                        width: layout.contentInnerWidth
                            - layout.panelPadding.leading - layout.panelPadding.trailing - 2,
                        height: 4
                    )
                    .background(
                        LinearGradient(
                            colors: model.selectedModule.accentFill,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(2)
                    .allowsHitTesting(false)

                if layout.compactActions {
                    VStack(alignment: .leading, spacing: 12) {
                        DemoPillButton(
                            "Open \(model.selectedModule.label)",
                            colors: model.selectedModule.accentFill
                        ) {
                            model.performAction("Opened \(model.selectedModule.label)")
                        }

                        DemoPillButton(
                            "Cycle mode",
                            colors: [theme.fieldTop, theme.fieldBottom],
                            textColor: Color.primary
                        ) {
                            model.cycleModule()
                        }
                    }
                } else {
                    HStack(alignment: .center, spacing: 12) {
                        DemoPillButton(
                            "Open \(model.selectedModule.label)",
                            colors: model.selectedModule.accentFill
                        ) {
                            model.performAction("Opened \(model.selectedModule.label)")
                        }
                        .layoutPriority(1)

                        DemoPillButton(
                            "Cycle mode",
                            colors: [theme.fieldTop, theme.fieldBottom],
                            textColor: Color.primary
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
    @Environment(\.colorScheme) private var colorScheme
    private var theme: DemoTheme { DemoTheme(colorScheme: colorScheme) }

    let size: CGSize

    var body: some View {
        Color.clear
            .frame(width: size.width, height: size.height)
            .background(
                LinearGradient(
                    colors: [
                        theme.backdropTop,
                        theme.backdropMiddle,
                        theme.backdropBottom,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .allowsHitTesting(false)
    }
}
struct DemoGlassSurface<Content: View>: View {
    // A default cannot be a stored constant any more: the appearance is
    // only known once the view is in an environment.
    @Environment(\.colorScheme) private var colorScheme

    let content: Content
    let cornerRadius: CGFloat
    let contentPadding: EdgeInsets
    let fill: LinearGradient?
    let stroke: Color?
    let shadowColor: Color?
    let elevation: DemoElevation

    init(
        cornerRadius: CGFloat = 30,
        contentPadding: EdgeInsets = EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18),
        fill: LinearGradient? = nil,
        stroke: Color? = nil,
        shadowColor: Color? = nil,
        elevation: DemoElevation = .panel,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.cornerRadius = cornerRadius
        self.contentPadding = contentPadding
        self.fill = fill
        self.stroke = stroke
        self.shadowColor = shadowColor
        self.elevation = elevation
    }

    private var theme: DemoTheme { DemoTheme(colorScheme: colorScheme) }

    /// A panel is lit from above, so its gradient runs top to bottom.
    ///
    /// It used to run corner to corner, which on a card far wider than it is
    /// tall is very nearly a *horizontal* gradient: a 730×140 pt card moved
    /// nine levels from its left edge to its right one and one level from its
    /// top to its bottom. Both halves of that are wrong — panels do not get
    /// lighter on one side, and the vertical fall is the only part of the
    /// gradient the eye reads as depth — which is why these cards audited as
    /// flat single-colour fills despite being authored as gradients.
    private var resolvedFill: LinearGradient {
        fill
            ?? LinearGradient(
                colors: [theme.surfaceTop, theme.surfaceBottom],
                startPoint: .top,
                endPoint: .bottom
            )
    }

    /// The panel's hairline, brightest along its top edge.
    private var resolvedStroke: LinearGradient {
        LinearGradient(
            colors: [theme.surfaceHighlight, stroke ?? theme.surfaceStroke],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var body: some View {
        content
            .padding(contentPadding)
            .background(resolvedFill)
            .cornerRadius(cornerRadius)
            .padding(1)
            .background(resolvedStroke)
            .cornerRadius(cornerRadius + 1)
            .shadow(
                color: elevation.castsShadow ? (shadowColor ?? theme.shadow) : .clear,
                radius: elevation.radius,
                x: 0,
                y: elevation.offsetY
            )
    }
}

/// How far off the page a surface sits. macOS has two answers, not one: a
/// window-level panel casts a wide soft shadow, and a *control* — a push
/// button, a source-list row — casts nothing, and is separated from its
/// background by its own edge. Every surface in this demo used to take the
/// panel value, which put an 8 pt halo 14 pt below a 38 pt pill and read as a
/// slab that had come loose from the button.
enum DemoElevation {
    case panel
    case control

    var castsShadow: Bool { self == .panel }

    var radius: CGFloat {
        switch self {
        case .panel: return 8
        case .control: return 0
        }
    }

    var offsetY: CGFloat {
        switch self {
        case .panel: return 14
        case .control: return 0
        }
    }
}
struct DemoTintedSurface<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let content: Content
    let cornerRadius: CGFloat
    let contentPadding: EdgeInsets
    let colors: [Color]
    let stroke: Color?
    let shadowColor: Color?
    let elevation: DemoElevation

    init(
        cornerRadius: CGFloat = 24,
        contentPadding: EdgeInsets = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16),
        colors: [Color],
        stroke: Color? = nil,
        shadowColor: Color? = nil,
        elevation: DemoElevation = .panel,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.cornerRadius = cornerRadius
        self.contentPadding = contentPadding
        self.colors = colors
        self.stroke = stroke
        self.shadowColor = shadowColor
        self.elevation = elevation
    }

    private var theme: DemoTheme { DemoTheme(colorScheme: colorScheme) }

    var body: some View {
        content
            .padding(contentPadding)
            .background(
                // Top to bottom, like every other panel: a tinted card is
                // still a card, and a corner-to-corner tint on a wide surface
                // reads as a lighting direction no window has.
                LinearGradient(
                    colors: colors,
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .cornerRadius(cornerRadius)
            .padding(1)
            .background(
                LinearGradient(
                    colors: [theme.surfaceHighlight, stroke ?? theme.surfaceStrokeStrong],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .cornerRadius(cornerRadius + 1)
            .shadow(
                color: elevation.castsShadow ? (shadowColor ?? theme.shadow) : .clear,
                radius: elevation.radius,
                x: 0,
                y: elevation.offsetY
            )
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
    @Environment(\.colorScheme) private var colorScheme
    private var theme: DemoTheme { DemoTheme(colorScheme: colorScheme) }

    let title: String
    let tint: Color?

    init(_ title: String, tint: Color? = nil) {
        self.title = title
        self.tint = tint
    }

    var body: some View {
        // Two chips, two jobs. The plain one is a scrim on the hero card, so
        // it takes the card's own contrast direction and `.primary` text. The
        // tinted one is a *badge*, so it keeps its accent at full strength and
        // near-white text — the 0.42 wash it used to carry was a legible blue
        // on the old navy card and a ghost on the light one.
        Text(title)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundColor(tint == nil ? Color.primary : theme.onTintedFillText)
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .padding(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
            // The badge takes its tint at full strength. The 0.92 it used to
            // apply was the last of the washes: a badge fill is an accent
            // fill, and a caller hands one over already opaque.
            .background(tint == nil ? theme.heroChipFill : tint!)
            .cornerRadius(12)
            .padding(1)
            .background(theme.surfaceStroke)
            .cornerRadius(13)
    }
}
struct DemoSectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        // The one place the demo genuinely wants small caps: a group
        // eyebrow, the way an NSTableView group row or a sidebar heading
        // reads. Expressing it as `.textCase(.uppercase)` on a sentence-case
        // string — rather than typing the string in caps — is what lets the
        // system set it as caps *and* apply the tracking caps need.
        Text(title)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .lineLimit(1)
    }
}
struct DemoPillButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let width: CGFloat?
    let colors: [Color]
    let textColor: Color?
    let perform: @MainActor @Sendable () -> Void

    private var theme: DemoTheme { DemoTheme(colorScheme: colorScheme) }

    init(
        _ title: String,
        width: CGFloat? = nil,
        colors: [Color],
        textColor: Color? = nil,
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
                contentPadding: EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14),
                colors: colors,
                stroke: theme.surfaceStrokeStrong,
                shadowColor: theme.shadow,
                elevation: .control
            ) {
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(textColor ?? theme.onTintedFillText)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .frame(width: width, height: 38)
            }
        }
        .buttonStyle(.plain)
    }
}
struct DemoModuleButton: View {
    @Environment(\.colorScheme) private var colorScheme
    private var theme: DemoTheme { DemoTheme(colorScheme: colorScheme) }

    let systemImage: String
    let title: String
    let colors: [Color]
    /// The label rung the row's own fill asks for: `.primary` on the neutral
    /// field, near-white on the accent fill of a selected row.
    let textColor: Color
    let perform: @MainActor @Sendable () -> Void

    var body: some View {
        Button(action: perform) {
            DemoTintedSurface(
                cornerRadius: 16,
                contentPadding: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0),
                colors: colors,
                stroke: theme.surfaceStroke,
                elevation: .control
            ) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: systemImage)
                        .foregroundColor(textColor)
                        .font(.system(size: 14))
                        .frame(width: 18, height: 18)

                    Text(title)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(textColor)
                        .multilineTextAlignment(.leading)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
                // Symmetric padding rather than a 42 pt fixed height: a
                // sidebar row is as tall as its label plus its insets, which
                // lands near the ~28 pt macOS source-list row. The fixed
                // height left the label sitting in the top half of a box with
                // an empty lower half.
                .padding(EdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 12))
                // Greedy *inside* the surface, not around it: the fill has to
                // reach the thing that draws the background, or the button
                // stays the width of its own label and just sits at the
                // leading edge of a wider invisible box.
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}
struct DemoRowButton: View {
    @Environment(\.colorScheme) private var colorScheme
    private var theme: DemoTheme { DemoTheme(colorScheme: colorScheme) }

    let title: String
    let detail: String
    let systemImage: String
    /// The row's accent *fill* ramp, not a glow to wash the chip in: the
    /// icon chip carries a near-white glyph, and a glow at 0.90 alpha put
    /// that glyph on a pastel in the light appearance.
    let accent: [Color]
    let perform: @MainActor @Sendable () -> Void

    var body: some View {
        Button(action: perform) {
            DemoGlassSurface(
                cornerRadius: 20,
                contentPadding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14),
                fill: LinearGradient(
                    colors: [theme.fieldTop, theme.fieldBottom],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                stroke: theme.surfaceStroke,
                elevation: .control
            ) {
                HStack(alignment: .center, spacing: 14) {
                    Color.clear
                        .frame(width: 8, height: 44)
                        .background(
                            LinearGradient(
                                colors: accent,
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .cornerRadius(4)
                        .allowsHitTesting(false)

                    DemoTintedSurface(
                        cornerRadius: 16,
                        contentPadding: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0),
                        colors: accent,
                        stroke: theme.surfaceStroke,
                        elevation: .control
                    ) {
                        Image(systemName: systemImage)
                            .foregroundColor(theme.onTintedFillText)
                            .font(.system(size: 15))
                            .frame(width: 30, height: 30)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(title)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(1)

                        // `.secondary`, not `.tertiary`: this line is the
                        // row's subtitle — content — and macOS keeps the
                        // tertiary rung for decoration and disabled chrome.
                        // On the light card the tertiary rung measured
                        // 1.88:1, which is a smudge, not a caption.
                        Text(detail)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(1)
                    }
                    .layoutPriority(1)
                }
                // A row in a column is as wide as the column. The fill goes
                // inside the surface, where the background is drawn: outside
                // it, the row keeps the width of its own longest line and a
                // stack of them fans out into a ragged list of chips.
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}
struct DemoMetricCard: View {
    let title: String
    let value: String
    let note: String

    var body: some View {
        DemoGlassSurface(cornerRadius: 26) {
            VStack(alignment: .leading, spacing: 10) {
                // The card's caption sits on the same rung as the section
                // headers around it ("WORKSPACE", "RENDER PIPELINE"), which
                // is `.secondary`. On the light card the tertiary rung this
                // used to carry measured 1.86:1 against the card fill — the
                // titles were legible only as a shape.
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)

                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)

                // One rule for captions across the app: a caption is
                // `.secondary`, and an accent means "you can click this".
                // These notes used to take a per-module accent, so "Events
                // tracked" sat in link blue next to "Import WinSwiftUI or
                // SwiftUI" in slate — two colours for one row of identical
                // roles, neither of them interactive.
                Text(note)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
struct DemoActivityCard: View {
    let title: String
    let detail: String
    let systemImage: String
    let accent: [Color]

    var body: some View {
        DemoRowButton(title: title, detail: detail, systemImage: systemImage, accent: accent) {}
            .allowsHitTesting(false)
    }
}
struct DemoInfoCard: View {
    @Environment(\.colorScheme) private var colorScheme
    private var theme: DemoTheme { DemoTheme(colorScheme: colorScheme) }

    let card: DemoCard

    var body: some View {
        // A rail card's own rhythm, tighter than a centre-pane panel's: 14pt
        // insets and a 6pt line gap, so the two cards plus the quick-action
        // panel under them are a column the default window can hold whole.
        // At 18/8 the rail ran ~30pt past the bottom of its scroll view and
        // the fold went through the middle of the last row button.
        DemoGlassSurface(
            cornerRadius: 24,
            contentPadding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14),
            fill: LinearGradient(
                colors: [theme.fieldTop, theme.fieldBottom],
                startPoint: .top,
                endPoint: .bottom
            ),
            stroke: theme.surfaceStroke
        ) {
            VStack(alignment: .leading, spacing: 6) {
                // A headline, not a title2: 20pt bold on a 260pt rail card
                // is the largest type on the screen after the hero headline,
                // for the smallest card.
                Text(card.title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)

                Text(card.summary)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)

                // Same rule as every caption in the app: `.secondary`, with
                // the accent reserved for things that can be clicked. The
                // per-module tint this carried made a static meta line the
                // most saturated text on the rail.
                Text(card.meta)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            // A column of cards is a column: every card takes the column's
            // width rather than its own longest line, or the rail reads as a
            // pile of differently sized boxes with a ragged right edge.
            .frame(maxWidth: .infinity, alignment: .leading)
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
/// The dashboard's surface palette, resolved for one appearance.
///
/// This used to be a single unconditional *light* theme with no
/// `colorScheme` awareness, while the settings and data screens used bare
/// system controls, which are appearance-driven. Three screens of one app
/// therefore met in the middle of a `TabView` with two independent
/// hardcoded appearances — and the dashboard's dark-slate secondary text
/// was also being applied on the dark data screen, where it measured 2.7:1.
///
/// Text hierarchy is not here at all any more: it is `.primary`,
/// `.secondary` and `.tertiary`, which the system resolves for whichever
/// appearance the view is actually in. Only the *surfaces* — which are a
/// design choice this demo is making, not a system role — carry values,
/// and they carry one per appearance.
struct DemoTheme {
    let colorScheme: ColorScheme

    private var isDark: Bool { colorScheme == .dark }

    private func pick(light: Color, dark: Color) -> Color { isDark ? dark : light }

    /// The window background. A window has one, and the tab bar the shell
    /// draws above the dashboard is part of the same window: a green-to-cream
    /// diagonal under a neutral system band put a visible seam across the top
    /// of the light window and made the page look like a different surface
    /// pasted under the chrome. What is left is a window grey with barely
    /// enough gradient to keep the demo's diagonal.
    var backdropTop: Color {
        pick(
            light: Color(red: 0.945, green: 0.949, blue: 0.957, opacity: 1.0),
            dark: Color(red: 0.098, green: 0.098, blue: 0.102, opacity: 1.0))
    }
    var backdropMiddle: Color {
        pick(
            light: Color(red: 0.925, green: 0.929, blue: 0.937, opacity: 1.0),
            dark: Color(red: 0.118, green: 0.118, blue: 0.125, opacity: 1.0))
    }
    var backdropBottom: Color {
        pick(
            light: Color(red: 0.949, green: 0.945, blue: 0.937, opacity: 1.0),
            dark: Color(red: 0.086, green: 0.086, blue: 0.090, opacity: 1.0))
    }
    var surfaceTop: Color {
        pick(
            light: Color(red: 0.99, green: 0.99, blue: 1.0, opacity: 0.92),
            dark: Color(red: 0.196, green: 0.196, blue: 0.204, opacity: 0.92))
    }
    var surfaceBottom: Color {
        pick(
            light: Color(red: 0.93, green: 0.95, blue: 0.98, opacity: 0.86),
            dark: Color(red: 0.157, green: 0.157, blue: 0.165, opacity: 0.86))
    }
    var fieldTop: Color {
        pick(
            light: Color(red: 0.97, green: 0.98, blue: 1.0, opacity: 0.96),
            dark: Color(red: 0.235, green: 0.235, blue: 0.243, opacity: 0.96))
    }
    var fieldBottom: Color {
        pick(
            light: Color(red: 0.91, green: 0.94, blue: 0.98, opacity: 0.90),
            dark: Color(red: 0.184, green: 0.184, blue: 0.192, opacity: 0.90))
    }
    var sidebarTop: Color {
        pick(
            light: Color(red: 0.95, green: 0.96, blue: 0.98, opacity: 0.90),
            dark: Color(red: 0.169, green: 0.169, blue: 0.176, opacity: 0.90))
    }
    var sidebarBottom: Color {
        pick(
            light: Color(red: 0.89, green: 0.92, blue: 0.96, opacity: 0.84),
            dark: Color(red: 0.137, green: 0.137, blue: 0.145, opacity: 0.84))
    }
    /// The hero card's fill, per appearance. The card is the one surface the
    /// demo tints with the selected module, and the tint has to be a *light*
    /// tint in light mode: a fixed deep navy over a light backdrop is a dark
    /// app pasted onto a light desktop, which is what this used to look like.
    func heroTop(_ module: DemoModule) -> Color {
        pick(light: module.heroTopLight, dark: module.panelStartColor)
    }

    func heroBottom(_ module: DemoModule) -> Color {
        pick(light: module.heroBottomLight, dark: module.panelEndColor)
    }

    /// The fill behind a plain chip on the hero card: a light scrim on the
    /// dark card, a dark scrim on the pale one, the way a macOS badge sits on
    /// whatever it is on.
    var heroChipFill: Color {
        pick(
            light: Color(red: 0.0, green: 0.0, blue: 0.0, opacity: 0.08),
            dark: Color(red: 1.0, green: 1.0, blue: 1.0, opacity: 0.14))
    }
    var surfaceStroke: Color {
        pick(
            light: Color(red: 0.0, green: 0.0, blue: 0.0, opacity: 0.10),
            dark: Color(red: 1.0, green: 1.0, blue: 1.0, opacity: 0.10))
    }
    /// The top edge of a panel's hairline. macOS lights a surface from above
    /// in both appearances: on a dark window that reads as a white highlight
    /// along the card's top edge, and on a light one as the ring withdrawing
    /// at the top and closing at the bottom. Matches the system treatment the
    /// runtime gives a `GroupBox` and a `Form` section box, so a card the
    /// demo draws itself and a card the framework draws are lit the same way.
    var surfaceHighlight: Color {
        pick(
            light: Color(red: 1.0, green: 1.0, blue: 1.0, opacity: 0.55),
            dark: Color(red: 1.0, green: 1.0, blue: 1.0, opacity: 0.16))
    }
    var surfaceStrokeStrong: Color {
        pick(
            light: Color(red: 0.0, green: 0.0, blue: 0.0, opacity: 0.16),
            dark: Color(red: 1.0, green: 1.0, blue: 1.0, opacity: 0.16))
    }
    /// The label colour on a *tinted* fill the demo chose itself (a pill, a
    /// hero card): those fills are dark in both appearances, so the label on
    /// them is near-white in both.
    var onTintedFillText: Color { Color(red: 1.0, green: 1.0, blue: 1.0, opacity: 0.95) }

    /// The two toolbar pills that report a fixed fact rather than the
    /// selected module. Opaque, for the reason `DemoModule.fillTop` gives:
    /// these used to be a green and a blue carrying 0.92-ish alpha, which on
    /// the light toolbar composited to a pastel with a white label on it.
    static let readyFill: [Color] = [
        Color(red: 0.165, green: 0.478, blue: 0.333, opacity: 1.0),
        Color(red: 0.122, green: 0.369, blue: 0.255, opacity: 1.0),
    ]
    static let eventsFill: [Color] = [
        Color(red: 0.235, green: 0.376, blue: 0.600, opacity: 1.0),
        Color(red: 0.180, green: 0.290, blue: 0.471, opacity: 1.0),
    ]
    /// Panel shadows, per appearance. Dark mode carries the depth in its
    /// shadows because a white hairline barely reads there. A light macOS
    /// window is the opposite — a System Settings box casts black at ~0.04 —
    /// and the 0.12 this used to be blanketed every gutter of the light
    /// dashboard in a #CFD5DA smudge: with 14–18pt gaps and a 14pt shadow
    /// offset, the *shadows* were the only "window background" the filled
    /// screen ever showed, and the page graded a step darker and cooler
    /// than the window tone its backdrop actually is.
    var shadow: Color {
        pick(
            light: Color(red: 0.0, green: 0.0, blue: 0.0, opacity: 0.05),
            dark: Color(red: 0.0, green: 0.0, blue: 0.0, opacity: 0.36))
    }
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
    // The content of a scrolling column is as wide as the column. These used
    // to reserve 8 pt for a scroll gutter, which stopped being a thing when
    // the scrollers became overlay scrollers: the reservation just pulled
    // every card in the centre pane and the right rail 8 pt short of the
    // toolbar's right edge directly above them, so the window's right margin
    // read as two different margins depending on which band you looked at.
    var contentInnerWidth: CGFloat { max(380, contentWidth) }
    var railInnerWidth: CGFloat { max(220, railWidth) }
    /// The width of a row inside the sidebar: the surface's own width, minus
    /// the 1 pt stroke ring it draws around itself and the panel padding.
    var sidebarRowWidth: CGFloat {
        max(150, sidebarWidth - 2 - panelPadding.leading - panelPadding.trailing)
    }
    var metricCardWidth: CGFloat {
        max(120, (contentInnerWidth - gap * 2) / 3)
    }
    /// Whether the three metric cards have to stack into a column.
    ///
    /// This is a question about the *content column's width* — can a card
    /// still hold a 24 pt value and a note? — and nothing else. It used to
    /// ask `compact`, which is also true in a short window, so a window that
    /// was wide and short stacked the band: exactly backwards. It tripled the
    /// band's height in the window with the least height to spend, and pushed
    /// the third card halfway past the bottom of the scroll view, where it
    /// read as a sliced-off box with a cut-in-half title.
    var stacksMetrics: Bool { metricCardWidth < 190 }
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
    /// The plot's own height, scaled with the window the way `heroHeight` and
    /// `toolbarHeight` are. It used to be a flat 80 pt: a 736 pt wide plot
    /// 80 pt tall is a strip rather than a card, the bars had no room to
    /// differentiate, and the band was the one part of the column that did
    /// not grow with the window. The taller plot also coarsens the column's
    /// rhythm, which is what puts the bottom of the scroll view in the gap
    /// between two cards instead of a dozen points into the top of one.
    var chartHeight: CGFloat { compact ? 112 : 128 }
    /// Whether the hero card's two action pills have to stack.
    ///
    /// The *width* half of `compact`, and only that half. Stacking is an
    /// answer to "there is no room beside it", which is a question about
    /// width; asking `compact` also stacked them in a window that was merely
    /// short, which is exactly backwards — it spends a second 50pt row of
    /// height in the window with the least height to spend. The hero card is
    /// a fixed height, so the extra row had nowhere to go and both pills were
    /// squeezed from 38pt to about 15: a bold 12pt label in a 15pt capsule.
    var compactActions: Bool { size.width < 1180 }

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

    // The two decorative washes live on the backdrop, *behind* the columns.
    // The only backdrop a filled window still shows is the outer margin and
    // the gutters between columns, so a wash that straddles a gutter is seen
    // as a bright vertical sliver with two hard edges — which reads as a
    // clipping bug, not as decoration. Both are kept inside the centre
    // column's horizontal span, where the only backdrop they can reach is the
    // horizontal band between two stacked cards, and both are dim enough to be
    // ambient light rather than a shape.
    var accentA: CGRect {
        CGRect(
            x: outerPadding + sidebarWidth + columnGap + contentWidth * 0.06,
            y: outerPadding + toolbarHeight + gap + 18,
            width: compact ? 160 : 240,
            height: compact ? 84 : 126
        )
    }

    var accentB: CGRect {
        CGRect(
            x: outerPadding + sidebarWidth + columnGap + contentWidth * 0.44,
            y: outerPadding + toolbarHeight + heroHeight + gap * 2,
            width: min(compact ? 132 : 180, contentWidth * 0.5),
            height: compact ? 68 : 94
        )
    }
}
struct DemoCard {
    let title: String
    let summary: String
    let meta: String
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
        case .layout: return "Layout"
        case .input: return "Input"
        case .animation: return "Animation"
        case .controls: return "Controls"
        }
    }

    var statusLabel: String { "Mode: \(label)" }
    var headline: String {
        switch self {
        case .layout: return "Pure Swift layout core"
        case .input: return "Pointer and keyboard routing"
        case .animation: return "Frame-driven UI motion"
        case .controls: return "Native control gallery"
        }
    }

    var summary: String {
        switch self {
        case .layout: return "Responsive composition and panel structure"
        case .input: return "Hover, press, focus, and scroll routing"
        case .animation: return "Frame-timed state transitions and chrome"
        case .controls: return "Toggle, slider, stepper, and input rendering"
        }
    }

    var detailLine: String {
        switch self {
        case .layout: return "Stack  Scroll  Clip  Intrinsic"
        case .input: return "Hover  Press  Focus  Activate"
        case .animation: return "Timers  Palettes  State  Redraw"
        case .controls: return "Toggle  Slider  Step  Pick"
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
        case .animation: return Color(red: 0.20, green: 0.19, blue: 0.24, opacity: 0.84)
        case .controls: return Color(red: 0.28, green: 0.20, blue: 0.36, opacity: 0.84)
        }
    }

    /// Top stop of the module's **accent fill** — the colour under a
    /// near-white label on a pill, a chip, or a selected source-list row.
    ///
    /// This is opaque on purpose, and it is the whole point of the value.
    /// `glowColor` and `stripeColor` are *glows*: pale hues carrying alpha,
    /// meant to be laid over something. Using them as a fill composited the
    /// pale hue onto whatever was behind it, so on a light window the "Open
    /// Layout" pill resolved to #88BDF2 and its white label measured 1.9:1 —
    /// and even on the dark window it only reached 2.4:1. An accent fill is
    /// not a wash of an accent: it is a colour, and macOS picks it dark
    /// enough that the label it was chosen for is legible on it. Every stop
    /// here clears 4.5:1 against the 0.95-alpha white the demo writes on it,
    /// in both appearances, because an opaque fill has no appearance to vary
    /// with.
    var fillTop: Color {
        switch self {
        case .layout: return Color(red: 0.118, green: 0.431, blue: 0.808, opacity: 1.0)
        case .input: return Color(red: 0.059, green: 0.463, blue: 0.525, opacity: 1.0)
        case .animation: return Color(red: 0.659, green: 0.322, blue: 0.0, opacity: 1.0)
        case .controls: return Color(red: 0.482, green: 0.294, blue: 0.737, opacity: 1.0)
        }
    }

    /// Bottom stop of the accent fill: the same hue a step down, so a filled
    /// control is lit from above like every other surface in the demo.
    var fillBottom: Color {
        switch self {
        case .layout: return Color(red: 0.078, green: 0.329, blue: 0.624, opacity: 1.0)
        case .input: return Color(red: 0.039, green: 0.357, blue: 0.412, opacity: 1.0)
        case .animation: return Color(red: 0.514, green: 0.247, blue: 0.0, opacity: 1.0)
        case .controls: return Color(red: 0.376, green: 0.227, blue: 0.576, opacity: 1.0)
        }
    }

    /// The accent fill as the two-stop ramp the demo's tinted surfaces take.
    var accentFill: [Color] { [fillTop, fillBottom] }

    var panelStartColor: Color {
        switch self {
        case .layout: return Color(red: 0.18, green: 0.24, blue: 0.37, opacity: 0.97)
        case .input: return Color(red: 0.15, green: 0.25, blue: 0.29, opacity: 0.97)
        case .animation: return Color(red: 0.17, green: 0.16, blue: 0.22, opacity: 0.97)
        case .controls: return Color(red: 0.24, green: 0.18, blue: 0.34, opacity: 0.97)
        }
    }

    var panelEndColor: Color {
        switch self {
        case .layout: return Color(red: 0.11, green: 0.16, blue: 0.27, opacity: 0.94)
        case .input: return Color(red: 0.10, green: 0.18, blue: 0.22, opacity: 0.94)
        case .animation: return Color(red: 0.11, green: 0.10, blue: 0.15, opacity: 0.94)
        case .controls: return Color(red: 0.17, green: 0.13, blue: 0.24, opacity: 0.94)
        }
    }

    /// The light-appearance hero stops: the same four hues, pale enough to
    /// carry dark text but tinted enough to carry *weight*. `panelStartColor`
    /// and `panelEndColor` stay the dark-appearance pair. The old stops
    /// started three levels off white and the hero read as one more white
    /// card in the column; its dark twin works because it is unmistakably a
    /// blue card. The headline and the `.secondary` summary sit in the upper
    /// half of the ramp, which is what bounds how deep the bottom stop can
    /// go: the summary must clear 4.5:1 against the mid-card fill.
    var heroTopLight: Color {
        switch self {
        case .layout: return Color(red: 0.945, green: 0.965, blue: 1.0, opacity: 0.97)
        case .input: return Color(red: 0.94, green: 0.985, blue: 0.98, opacity: 0.97)
        case .animation: return Color(red: 1.0, green: 0.965, blue: 0.935, opacity: 0.97)
        case .controls: return Color(red: 0.975, green: 0.95, blue: 1.0, opacity: 0.97)
        }
    }

    var heroBottomLight: Color {
        switch self {
        case .layout: return Color(red: 0.80, green: 0.87, blue: 0.97, opacity: 0.94)
        case .input: return Color(red: 0.79, green: 0.915, blue: 0.90, opacity: 0.94)
        case .animation: return Color(red: 0.985, green: 0.865, blue: 0.755, opacity: 0.94)
        case .controls: return Color(red: 0.885, green: 0.815, blue: 0.965, opacity: 0.94)
        }
    }

    var cards: [DemoCard] {
        switch self {
        case .layout:
            return [
                DemoCard(
                    title: "Stack layout", summary: "Panels stretch with priority and padding",
                    meta: "Retention-first measurement"),
                DemoCard(
                    title: "Clipping", summary: "Scissor-ready rect clipping through the render frame",
                    meta: "Backend-neutral commands"),
            ]
        case .input:
            return [
                DemoCard(
                    title: "Focus chain", summary: "Tab moves through focusable retained nodes",
                    meta: "Window delegate to runtime"),
                DemoCard(
                    title: "Press states", summary: "Buttons drive focused, pressed, and activated colors",
                    meta: "Main-actor control lifecycle"),
            ]
        case .animation:
            return [
                DemoCard(
                    title: "Tick driver", summary: "Window animation frames advance color transitions",
                    meta: "Only when active"),
                DemoCard(
                    title: "Frame cache", summary: "Unchanged UI reuses the last render frame until invalidated",
                    meta: "Retention redraws"),
            ]
        case .controls:
            return [
                DemoCard(
                    title: "Toggle and slider", summary: "Interactive binding-driven controls",
                    meta: "Hit-test and focus"),
                DemoCard(
                    title: "Text input", summary: "TextField and TextEditor with state", meta: "Keyboard routing"),
            ]
        }
    }

    var actions: [DemoAction] {
        switch self {
        case .layout:
            return [
                DemoAction(
                    title: "Inspect Stacks", caption: "Read the container tree", systemImage: "rectangle.3.group",
                    eventLabel: "Stack inspector opened"),
                DemoAction(
                    title: "Resize Panes", caption: "Drag the split dividers", systemImage: "rectangle.split.3x1",
                    eventLabel: "Pane editor opened"),
            ]
        case .input:
            return [
                DemoAction(
                    title: "Focus Walk", caption: "Tab through controls", systemImage: "keyboard",
                    eventLabel: "Focus walk started"),
                DemoAction(
                    title: "Route Events", caption: "Trace pointer to node", systemImage: "waveform.path.ecg",
                    eventLabel: "Input trace opened"),
            ]
        case .animation:
            return [
                DemoAction(
                    title: "Play Motion", caption: "Retrigger the status cycle", systemImage: "sparkles",
                    eventLabel: "Motion loop started"),
                DemoAction(
                    title: "Inspect Ticks", caption: "Follow runtime invalidation", systemImage: "bolt.fill",
                    eventLabel: "Tick inspector opened"),
            ]
        case .controls:
            return [
                DemoAction(
                    title: "Toggle Demo", caption: "Switch states and bindings", systemImage: "switch.2",
                    eventLabel: "Toggle demo opened"),
                DemoAction(
                    title: "Input Forms", caption: "Text and picker layout", systemImage: "textformat",
                    eventLabel: "Input form opened"),
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
        case .dashboard: return "Dashboard"
        case .settings: return "Settings"
        case .data: return "Data"
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
    var statusLabel: String { isHealthy ? "Healthy" : "Degraded" }

    static let defaults: [DemoComponent] = [
        DemoComponent(
            id: 1, name: "Render host", detail: "D3D11 batch pipeline", version: "v2.4.1",
            systemImage: "bolt.fill", load: 0.34),
        DemoComponent(
            id: 2, name: "Input router", detail: "Pointer and keyboard dispatch", version: "v1.9.0",
            systemImage: "keyboard", load: 0.12),
        DemoComponent(
            id: 3, name: "Layout engine", detail: "Retained stack measurement", version: "v3.1.2",
            systemImage: "rectangle.3.group", load: 0.48),
        DemoComponent(
            id: 4, name: "Animation ticker", detail: "Frame-driven state transitions", version: "v1.4.0",
            systemImage: "sparkles", load: 0.27),
        DemoComponent(
            id: 5, name: "Control surfaces", detail: "Buttons, toggles, and pickers", version: "v2.0.3",
            systemImage: "switch.2", load: 0.56),
        DemoComponent(
            id: 6, name: "Event log", detail: "Interaction telemetry buffer", version: "v0.9.8",
            systemImage: "waveform.path.ecg", load: 0.71),
        DemoComponent(
            id: 7, name: "Document store", detail: "Settings persistence layer", version: "v1.2.5",
            systemImage: "doc.text", load: 0.18),
        DemoComponent(
            id: 8, name: "System probe", detail: "Health and diagnostics", version: "v0.7.2",
            systemImage: "info.circle", load: 0.90),
    ]
}

// MARK: - Settings screen

/// Settings-style form exercising Supported-tier controls: text field,
/// segmented picker, stepper, toggles, slider, gauge, progress, and buttons.
struct DemoSettingsScreen: View {
    @ObservedObject var model: DemoDashboardModel
    @Environment(\.openWindow) private var openWindow
    @State private var isImporterPresented = false

    /// Width of the settings pane's content column, and the gutter between
    /// that column's edge and the section boxes inside it.
    ///
    /// A settings pane is a *column*, not a page: System Settings runs one a
    /// little over 600pt wide and lets the window keep whatever margin is
    /// left. The demo has to name the column because it wants the title on
    /// it — a `.navigationTitle` is drawn by the pane's chrome at the pane's
    /// own leading edge, which in a 1280pt window put "Settings" 320pt away
    /// from the form it was titling, with nothing under it in between.
    private let columnWidth: CGFloat = 640
    private let columnGutter: CGFloat = 20

    var body: some View {
        NavigationStack {
            // The form is taller than small windows; scroll instead of
            // squeezing sections until their tracks vanish.
            ScrollView {
                // 32 above the title and 32 under it: a settings pane's own
                // rhythm, and the numbers that put the default window's
                // scroll fold in the *gap* between the "Resources" box and
                // the "Actions" header. At 24/22 the fold landed 16pt later:
                // the header was fully visible with nothing under it — an
                // orphaned eyebrow captioning the bottom edge of the window.
                // The title used to start 6pt under the tab bar, which is
                // not a page inset, it is a collision.
                VStack(alignment: .leading, spacing: 32) {
                    // The title travels with the column: it sits on the
                    // section boxes' own leading edge, so the window's wide
                    // side margins read as the margins of one centred pane
                    // rather than as empty space next to a stray heading.
                    Text("Settings")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .lineLimit(1)
                        .padding(.horizontal, columnGutter)

                    Form {
                        Section("Profile") {
                            TextField("Display Name", text: $model.displayName)

                            Picker("Theme", selection: $model.theme) {
                                Text("System").tag(DemoThemeOption.system)
                                Text("Light").tag(DemoThemeOption.light)
                                Text("Dark").tag(DemoThemeOption.dark)
                            }
                            .pickerStyle(.segmented)

                            // System Settings puts the noun in the label
                            // column and the value beside its stepper in the
                            // control column. Folding the value into the
                            // label — "Items Per Page: 10" — makes the one
                            // row in the pane whose label is a sentence, and
                            // leaves the control column holding a bezel with
                            // nothing to be about.
                            //
                            // And the value is a *field*, not a numeral
                            // floating in the row: macOS pairs NSStepper
                            // with a text-field bezel (Date & Time, TextEdit
                            // page setup — every stepper in the OS), because
                            // the pair is one compound control that can also
                            // be typed into.
                            LabeledContent("Items Per Page") {
                                HStack(spacing: 8) {
                                    TextField(
                                        "Items Per Page",
                                        value: $model.itemsPerPage,
                                        format: .number
                                    )
                                    .labelsHidden()
                                    .frame(width: 44)

                                    Stepper(
                                        "Items Per Page",
                                        value: $model.itemsPerPage,
                                        in: 5...30,
                                        step: 5
                                    )
                                    .labelsHidden()
                                }
                            }
                        }

                        Section("Preferences") {
                            Toggle("Enable Animations", isOn: $model.animationsEnabled)
                            Toggle("Sound Effects", isOn: $model.soundEffectsEnabled)
                            Toggle("Share Usage Data", isOn: $model.shareUsageData)

                            ColorPicker("Accent Color", selection: $model.accentColor)

                            // No explicit `Divider()` here: a grouped Form
                            // section rules between every pair of rows on its
                            // own, the way System Settings does. One written
                            // here would be the only double rule in the pane.
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

                            Button("Open Second Window") {
                                openWindow(id: "main-dashboard")
                            }

                            Button("Import File…") {
                                isImporterPresented = true
                            }
                        }
                    }
                }
                // The column, then the centring. Two frames rather than one:
                // the inner one is the pane's own width, the outer one is the
                // window it is centred in. A `Form` fills whatever width it
                // is offered and centres its section boxes inside that, so
                // without the inner frame the column would be the window and
                // the title would be at the window's edge again.
                .frame(maxWidth: columnWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            }
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [.image, .plainText]
            ) { result in
                if case .success(let url) = result {
                    model.noteImportedFile(url)
                }
            }
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
            // The list is the greedy half of this screen and the detail block
            // is pinned under it. No `proxy.size.height - 224`: that literal
            // was a guess at the detail block's height, the guess was about
            // 75 pt too generous, and the screen ended in a bare strip of
            // window with nothing in it. A greedy child takes exactly what is
            // left once its siblings have measured themselves, so the list
            // grows and shrinks with the detail block instead of against it.
            VStack(alignment: .leading, spacing: 0) {
                List(model.components, selection: $model.selectedComponentID) { component in
                    DemoComponentRow(component: component)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(16)
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    model.noteDroppedItems(count: providers.count)
                    return true
                }

                // The inspector is a *bar*, not a paragraph that happens to
                // follow the list. It used to be a hairline `Divider()` in a
                // 12pt gap between two things standing on the same window
                // background — the rule measured 1.2:1 against what was on
                // either side of it, so the block read as floating text under
                // a card. A bar is what macOS puts at the bottom of an
                // inspector: its own scrim, closed at the top by a rule,
                // running edge to edge with its own insets. `.quaternary` is
                // a semantic rung: it lightens the dark window into a bar,
                // and in light mode it resolves to the window tone — a macOS
                // bottom bar is never darker than the window it closes, so
                // the divider carries the edge there.
                VStack(spacing: 0) {
                    Divider()

                    DemoComponentDetail(model: model)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                }
                .background(.quaternary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .navigationTitle("Components")
        }
    }
}

struct DemoComponentRow: View {
    let component: DemoComponent

    var body: some View {
        // One line, not two. A stacked version-over-status trailing block gave
        // every row two text baselines and a 42 pt box; macOS list rows are a
        // single line of about 24 pt, and the two values read perfectly well
        // side by side because they are short and always in the same order.
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Label(component.name, systemImage: component.systemImage)
                .lineLimit(1)

            Spacer(minLength: 8)

            // `.secondary` rather than a fixed grey: a row inside a
            // selection-bound List is drawn over the accent fill when
            // selected, and the semantic colour is the one that brightens
            // against a prominent background.
            Text(component.version)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            // macOS reserves colour for the state that needs attention — and
            // it carries that colour on a *symbol*, not on the word: a
            // Network-settings row is a coloured status dot beside plain
            // text. Painting the word itself `.orange` was faithful SwiftUI
            // (macOS composites the same 2.2:1 orange on white) and
            // illegible for exactly that reason: an accent is a colour for
            // shapes, not for 10pt text on white. The dot carries the orange
            // at full saturation in any size; the word stays `.secondary`,
            // legible on white and inverting to white with the rest of a
            // selected row — while the dot, like any app-authored colour on
            // macOS, passes through onto the selection fill unchanged.
            //
            // The status column is a column: every row's status ends on the
            // same trailing edge, or a table of eight rows reads as eight
            // ragged right margins. The fixed-width frame reserves the
            // column; trailing alignment puts a short word ("Healthy") on
            // the same edge as a long one ("Degraded").
            HStack(alignment: .center, spacing: 5) {
                if !component.isHealthy {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 7, height: 7)
                }

                Text(component.statusLabel)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .multilineTextAlignment(.trailing)
            }
            .frame(width: 72, alignment: .trailing)
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
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    // `.secondary`, not `.tertiary`: this line is content,
                    // and macOS reserves the tertiary rung for decoration.
                    Text("Version \(component.version)   Status \(component.statusLabel)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .layoutPriority(1)

                Spacer(minLength: 8)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Current load")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
