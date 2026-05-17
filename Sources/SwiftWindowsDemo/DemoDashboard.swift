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

    public init() {}

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

    public var body: some View {
        GeometryReader { proxy in
            let layout = DemoLayout(size: proxy.size)

            ZStack(alignment: .topLeading) {
                DemoBackdrop(size: proxy.size)

                DemoAccent(
                    frame: layout.accentA,
                    fill: LinearGradient(
                        colors: [model.selectedModule.glowColor.opacity(0.32), model.selectedModule.stripeColor.opacity(0.10)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

                DemoAccent(
                    frame: layout.accentB,
                    fill: LinearGradient(
                        colors: [model.selectedModule.stripeColor.opacity(0.26), model.selectedModule.glowColor.opacity(0.08)],
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
                    colors: [model.selectedModule.glowColor.opacity(0.94), model.selectedModule.stripeColor.opacity(0.70)]
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
                        .frame(height: 10)
                        .background(
                            LinearGradient(
                                colors: [model.selectedModule.glowColor.opacity(0.88), model.selectedModule.stripeColor.opacity(0.62)],
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

                if layout.compact {
                    VStack(alignment: .leading, spacing: 14) {
                        DemoMetricCard(title: "INTERACTIONS", value: "\(model.interactionCount)", note: "EVENTS TRACKED", accent: model.selectedModule.glowColor)
                            .frame(width: layout.contentInnerWidth, alignment: .leading)
                        DemoMetricCard(title: "MODULE", value: model.selectedModule.label, note: model.selectedModule.summary, accent: model.selectedModule.stripeColor)
                            .frame(width: layout.contentInnerWidth, alignment: .leading)
                        DemoMetricCard(title: "TARGET", value: "SAME SOURCE", note: "IMPORT WINSWIFTUI OR SWIFTUI", accent: Color(red: 0.79, green: 0.87, blue: 0.97, opacity: 0.96))
                            .frame(width: layout.contentInnerWidth, alignment: .leading)
                    }
                } else {
                    HStack(alignment: .center, spacing: 18) {
                        DemoMetricCard(title: "INTERACTIONS", value: "\(model.interactionCount)", note: "EVENTS TRACKED", accent: model.selectedModule.glowColor)
                            .frame(width: layout.metricCardWidth, alignment: .leading)
                        DemoMetricCard(title: "MODULE", value: model.selectedModule.label, note: model.selectedModule.summary, accent: model.selectedModule.stripeColor)
                            .frame(width: layout.metricCardWidth, alignment: .leading)
                        DemoMetricCard(title: "TARGET", value: "SAME SOURCE", note: "IMPORT WINSWIFTUI OR SWIFTUI", accent: Color(red: 0.79, green: 0.87, blue: 0.97, opacity: 0.96))
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
            colors: [
                model.selectedModule.panelStartColor.opacity(0.92),
                model.selectedModule.panelEndColor.opacity(0.70),
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
                    .foregroundColor(DemoTheme.secondaryText)
                    .multilineTextAlignment(.leading)

                Color.clear
                    .frame(height: 12)
                    .background(
                        LinearGradient(
                            colors: [model.selectedModule.glowColor.opacity(0.94), model.selectedModule.stripeColor.opacity(0.68)],
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
                            colors: [model.selectedModule.glowColor.opacity(0.94), model.selectedModule.stripeColor.opacity(0.70)]
                        ) {
                            model.performAction("OPENED \(model.selectedModule.label)")
                        }

                        DemoPillButton(
                            "CYCLE MODE",
                            colors: [DemoTheme.fieldTop, DemoTheme.fieldBottom]
                        ) {
                            model.cycleModule()
                        }
                    }
                } else {
                    HStack(alignment: .center, spacing: 12) {
                        DemoPillButton(
                            "OPEN \(model.selectedModule.label)",
                            colors: [model.selectedModule.glowColor.opacity(0.94), model.selectedModule.stripeColor.opacity(0.70)]
                        ) {
                            model.performAction("OPENED \(model.selectedModule.label)")
                        }
                        .layoutPriority(1)

                        DemoPillButton(
                            "CYCLE MODE",
                            colors: [DemoTheme.fieldTop, DemoTheme.fieldBottom]
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
            .foregroundColor(DemoTheme.primaryText)
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
    let perform: @MainActor @Sendable () -> Void

    init(
        _ title: String,
        width: CGFloat? = nil,
        colors: [Color],
        perform: @escaping @MainActor @Sendable () -> Void
    ) {
        self.title = title
        self.width = width
        self.colors = colors
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
                    .foregroundColor(DemoTheme.inverseText)
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
        case .layout: return Color(red: 0.18, green: 0.24, blue: 0.37, opacity: 0.84)
        case .input: return Color(red: 0.15, green: 0.25, blue: 0.29, opacity: 0.84)
        case .animation: return Color(red: 0.26, green: 0.21, blue: 0.18, opacity: 0.84)
        case .controls: return Color(red: 0.24, green: 0.18, blue: 0.34, opacity: 0.84)
        }
    }

    var panelEndColor: Color {
        switch self {
        case .layout: return Color(red: 0.11, green: 0.16, blue: 0.27, opacity: 0.68)
        case .input: return Color(red: 0.10, green: 0.18, blue: 0.22, opacity: 0.68)
        case .animation: return Color(red: 0.18, green: 0.15, blue: 0.13, opacity: 0.68)
        case .controls: return Color(red: 0.17, green: 0.13, blue: 0.24, opacity: 0.68)
        }
    }

    var cards: [DemoCard] {
        switch self {
        case .layout:
            return [
                DemoCard(title: "STACK LAYOUT", summary: "PANELS STRETCH WITH PRIORITY AND PADDING", meta: "RETENTION-FIRST MEASUREMENT", accent: glowColor),
                DemoCard(title: "CLIPPING", summary: "SCISSOR-READY RECT CLIPPING THROUGH THE RENDER FRAME", meta: "BACKEND-NEUTRAL COMMANDS", accent: stripeColor),
            ]
        case .input:
            return [
                DemoCard(title: "FOCUS CHAIN", summary: "TAB MOVES THROUGH FOCUSABLE RETAINED NODES", meta: "WINDOW DELEGATE TO RUNTIME", accent: glowColor),
                DemoCard(title: "PRESS STATES", summary: "BUTTONS DRIVE FOCUSED, PRESSED, AND ACTIVATED COLORS", meta: "MAIN-ACTOR CONTROL LIFECYCLE", accent: stripeColor),
            ]
        case .animation:
            return [
                DemoCard(title: "TICK DRIVER", summary: "WINDOW ANIMATION FRAMES ADVANCE COLOR TRANSITIONS", meta: "ONLY WHEN ACTIVE", accent: glowColor),
                DemoCard(title: "FRAME CACHE", summary: "UNCHANGED UI REUSES THE LAST RENDER FRAME UNTIL INVALIDATED", meta: "RETENTION REDRAWS", accent: stripeColor),
            ]
        case .controls:
            return [
                DemoCard(title: "TOGGLE AND SLIDER", summary: "INTERACTIVE BINDING-DRIVEN CONTROLS", meta: "HIT-TEST AND FOCUS", accent: glowColor),
                DemoCard(title: "TEXT INPUT", summary: "TEXTFIELD AND TEXTEDITOR WITH STATE", meta: "KEYBOARD ROUTING", accent: stripeColor),
            ]
        }
    }

    var actions: [DemoAction] {
        switch self {
        case .layout:
            return [
                DemoAction(title: "Inspect Stacks", caption: "READ THE CONTAINER TREE", systemImage: "rectangle.3.group", eventLabel: "STACK INSPECTOR OPENED"),
                DemoAction(title: "Resize Panes", caption: "DRAG THE SPLIT DIVIDERS", systemImage: "rectangle.split.3x1", eventLabel: "PANE EDITOR OPENED"),
            ]
        case .input:
            return [
                DemoAction(title: "Focus Walk", caption: "TAB THROUGH CONTROLS", systemImage: "keyboard", eventLabel: "FOCUS WALK STARTED"),
                DemoAction(title: "Route Events", caption: "TRACE POINTER TO NODE", systemImage: "waveform.path.ecg", eventLabel: "INPUT TRACE OPENED"),
            ]
        case .animation:
            return [
                DemoAction(title: "Play Motion", caption: "RETRIGGER THE STATUS CYCLE", systemImage: "sparkles", eventLabel: "MOTION LOOP STARTED"),
                DemoAction(title: "Inspect Ticks", caption: "FOLLOW RUNTIME INVALIDATION", systemImage: "bolt.fill", eventLabel: "TICK INSPECTOR OPENED"),
            ]
        case .controls:
            return [
                DemoAction(title: "Toggle Demo", caption: "SWITCH STATES AND BINDINGS", systemImage: "switch.2", eventLabel: "TOGGLE DEMO OPENED"),
                DemoAction(title: "Input Forms", caption: "TEXT AND PICKER LAYOUT", systemImage: "textformat", eventLabel: "INPUT FORM OPENED"),
            ]
        }
    }
}
