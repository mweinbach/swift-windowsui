#if canImport(SwiftUI)
import SwiftUI
#else
import WinSwiftUI
#endif

@MainActor
final class DemoDashboardModel: ObservableObject {
    @Published var selectedModule: DemoModule = .layout
    @Published var interactionCount = 0
    @Published var lastAction = "READY"
    @Published var recentEvents: [String] = [
        "SYSTEM READY",
        "D3D11 READY",
        "WINDOW TOOLKIT ACTIVE",
    ]

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

struct DemoRootView: View {
    @ObservedObject var model: DemoDashboardModel

    var body: some View {
        GeometryReader { proxy in
            let layout = DemoLayout(size: proxy.size)

            ZStack(alignment: .topLeading) {
                DemoAccent(
                    frame: layout.accentA,
                    fill: LinearGradient(
                        colors: [model.selectedModule.glowColor, model.selectedModule.stripeColor],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

                DemoAccent(
                    frame: layout.accentB,
                    fill: LinearGradient(
                        colors: [model.selectedModule.stripeColor, model.selectedModule.glowColor],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                VStack(alignment: .leading, spacing: layout.gap) {
                    DemoToolbar(model: model, layout: layout)

                    HSplitView {
                        DemoSidebar(model: model, layout: layout)
                            .frame(width: layout.sidebarWidth, height: layout.bodyHeight, alignment: .topLeading)

                        HSplitView {
                            DemoCenterPane(model: model, layout: layout)
                                .frame(height: layout.bodyHeight, alignment: .topLeading)
                                .layoutPriority(1)

                            DemoRightRail(model: model, layout: layout)
                                .frame(width: layout.railWidth, height: layout.bodyHeight, alignment: .topLeading)
                        }
                        .layoutPriority(1)
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
        HStack(alignment: .center, spacing: layout.gap) {
            VStack(alignment: .leading, spacing: 6) {
                Text("WINSWIFTUI")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)

                Text("SAME-SOURCE DASHBOARD DEMO")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(red: 0.75, green: 0.86, blue: 0.97, opacity: 0.82))
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
            }
            .frame(width: layout.toolbarTitleWidth, alignment: .leading)

            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Color(red: 0.82, green: 0.89, blue: 0.97, opacity: 0.88))
                    .font(.system(size: 12))

                Text("SEARCH COMMANDS")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(red: 0.80, green: 0.88, blue: 0.97, opacity: 0.80))
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
            }
            .padding(EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14))
            .frame(width: layout.searchWidth, height: layout.pillHeight, alignment: .leading)
            .background(Color(red: 0.17, green: 0.22, blue: 0.30, opacity: 0.98))
            .cornerRadius(layout.pillHeight * 0.5)
            .allowsHitTesting(false)
            .layoutPriority(1)

            Spacer(minLength: 0)

            DemoPillButton(
                "D3D11",
                width: layout.backendWidth,
                fill: Color(red: 0.22, green: 0.32, blue: 0.27, opacity: 0.98)
            ) {
                model.performAction("RENDER STACK READY")
            }

            DemoPillButton(
                "EVENTS \(model.interactionCount)",
                width: layout.eventsWidth,
                fill: Color(red: 0.24, green: 0.28, blue: 0.40, opacity: 0.98)
            ) {
                model.performAction("EVENT HUD OPENED")
            }

            DemoPillButton(
                model.selectedModule.statusLabel,
                width: layout.modeWidth,
                fill: model.selectedModule.fillColor
            ) {
                model.cycleModule()
            }
        }
        .padding(layout.toolbarPadding)
        .frame(height: layout.toolbarHeight, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.13, green: 0.17, blue: 0.24, opacity: 0.98),
                    Color(red: 0.10, green: 0.14, blue: 0.20, opacity: 0.98),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .cornerRadius(layout.toolbarCornerRadius)
        .shadow(color: Color.black.opacity(0.22), radius: 6, x: 0, y: 12)
    }
}

struct DemoSidebar: View {
    let model: DemoDashboardModel
    let layout: DemoLayout

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                DemoSectionTitle("WORKSPACE")

                for module in DemoModule.allCases {
                    DemoModuleButton(
                        title: module.label,
                        fill: model.selectedModule == module ? module.accentColor : module.fillColor
                    ) {
                        model.selectModule(module)
                    }
                }

                Color.clear
                    .frame(height: 10)
                    .background(model.selectedModule.stripeColor)
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

                DemoRowButton(
                    title: "SHORTCUTS",
                    detail: "TAB AND WHEEL ROUTING",
                    systemImage: "keyboard",
                    accent: model.selectedModule.stripeColor
                ) {
                    model.performAction("SHORTCUTS OPENED")
                }
            }
            .padding(layout.panelPadding)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.14, green: 0.18, blue: 0.26, opacity: 0.98),
                    Color(red: 0.10, green: 0.14, blue: 0.20, opacity: 0.98),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .cornerRadius(layout.panelCornerRadius)
        .shadow(color: Color.black.opacity(0.24), radius: 8, x: 0, y: 14)
    }
}

struct DemoCenterPane: View {
    let model: DemoDashboardModel
    let layout: DemoLayout

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: layout.gap) {
                DemoHeroCard(model: model, layout: layout)

                if layout.compact {
                    VStack(alignment: .leading, spacing: 14) {
                        DemoMetricCard(title: "INTERACTIONS", value: "\(model.interactionCount)", note: "EVENTS TRACKED", accent: model.selectedModule.glowColor)
                        DemoMetricCard(title: "MODULE", value: model.selectedModule.label, note: model.selectedModule.summary, accent: model.selectedModule.stripeColor)
                        DemoMetricCard(title: "TARGET", value: "SAME SOURCE", note: "IMPORT WINSWIFTUI OR SWIFTUI", accent: Color(red: 0.79, green: 0.87, blue: 0.97, opacity: 0.96))
                    }
                } else {
                    HStack(alignment: .center, spacing: 18) {
                        DemoMetricCard(title: "INTERACTIONS", value: "\(model.interactionCount)", note: "EVENTS TRACKED", accent: model.selectedModule.glowColor)
                            .layoutPriority(1)
                        DemoMetricCard(title: "MODULE", value: model.selectedModule.label, note: model.selectedModule.summary, accent: model.selectedModule.stripeColor)
                            .layoutPriority(1)
                        DemoMetricCard(title: "TARGET", value: "SAME SOURCE", note: "IMPORT WINSWIFTUI OR SWIFTUI", accent: Color(red: 0.79, green: 0.87, blue: 0.97, opacity: 0.96))
                            .layoutPriority(1)
                    }
                }

                DemoPanel {
                    VStack(alignment: .leading, spacing: 14) {
                        DemoSectionTitle("ACTIVITY")

                        for event in model.recentEvents.prefix(5) {
                            DemoActivityCard(
                                title: event,
                                detail: model.selectedModule.detailLine,
                                systemImage: model.selectedModule.systemImage,
                                accent: model.selectedModule.glowColor
                            )
                        }
                    }
                }
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

                        for card in model.selectedModule.cards {
                            DemoInfoCard(card: card)
                        }
                    }
                }

                DemoPanel {
                    VStack(alignment: .leading, spacing: 14) {
                        DemoSectionTitle("QUICK ACTIONS")

                        for action in model.selectedModule.actions {
                            DemoRowButton(
                                title: action.title,
                                detail: action.caption,
                                systemImage: action.systemImage,
                                accent: model.selectedModule.stripeColor
                            ) {
                                model.performAction(action.eventLabel)
                            }
                        }
                    }
                }
            }
            .padding(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 6))
        }
    }
}

struct DemoHeroCard: View {
    let model: DemoDashboardModel
    let layout: DemoLayout

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DemoSectionTitle("CONTROL CENTER")

            Text(model.selectedModule.headline)
                .font(.system(size: layout.headlineSize, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)

            Text(model.selectedModule.summary)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color(red: 0.79, green: 0.88, blue: 0.97, opacity: 0.88))
                .multilineTextAlignment(.leading)

            Color.clear
                .frame(height: 12)
                .background(model.selectedModule.stripeColor)
                .cornerRadius(6)
                .allowsHitTesting(false)

            if layout.compactActions {
                VStack(alignment: .leading, spacing: 12) {
                    DemoPillButton("OPEN \(model.selectedModule.label)", fill: model.selectedModule.glowColor) {
                        model.performAction("OPENED \(model.selectedModule.label)")
                    }

                    DemoPillButton("CYCLE MODE", fill: model.selectedModule.stripeColor) {
                        model.cycleModule()
                    }
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    DemoPillButton("OPEN \(model.selectedModule.label)", fill: model.selectedModule.glowColor) {
                        model.performAction("OPENED \(model.selectedModule.label)")
                    }
                    .layoutPriority(1)

                    DemoPillButton("CYCLE MODE", fill: model.selectedModule.stripeColor) {
                        model.cycleModule()
                    }
                    .layoutPriority(1)
                }
            }
        }
        .padding(layout.panelPadding)
        .frame(height: layout.heroHeight, alignment: .leading)
        .background(
            LinearGradient(
                colors: [model.selectedModule.panelStartColor, model.selectedModule.panelEndColor],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .cornerRadius(layout.panelCornerRadius)
        .shadow(color: Color.black.opacity(0.26), radius: 8, x: 0, y: 14)
    }
}

struct DemoPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18))
            .background(Color(red: 0.14, green: 0.18, blue: 0.25, opacity: 0.98))
            .cornerRadius(28)
            .shadow(color: Color.black.opacity(0.24), radius: 8, x: 0, y: 14)
    }
}

struct DemoSectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(Color(red: 0.90, green: 0.95, blue: 1.0, opacity: 0.96))
            .multilineTextAlignment(.leading)
            .lineLimit(1)
    }
}

struct DemoPillButton: View {
    let title: String
    let width: CGFloat?
    let fill: Color
    let perform: @MainActor @Sendable () -> Void

    init(_ title: String, width: CGFloat? = nil, fill: Color, perform: @escaping @MainActor @Sendable () -> Void) {
        self.title = title
        self.width = width
        self.fill = fill
        self.perform = perform
    }

    var body: some View {
        Button(action: perform) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .frame(width: width, height: 38)
                .background(fill)
                .cornerRadius(19)
                .shadow(color: Color.black.opacity(0.18), radius: 4, x: 0, y: 8)
        }
    }
}

struct DemoModuleButton: View {
    let title: String
    let fill: Color
    let perform: @MainActor @Sendable () -> Void

    var body: some View {
        Button(action: perform) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .frame(height: 52)
                .background(fill)
                .cornerRadius(16)
        }
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
            HStack(alignment: .center, spacing: 14) {
                Color.clear
                    .frame(width: 8, height: 44)
                    .background(accent)
                    .cornerRadius(4)
                    .allowsHitTesting(false)

                Image(systemName: systemImage)
                    .foregroundColor(accent)
                    .font(.system(size: 15))
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                        .lineLimit(1)

                    Text(detail)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(red: 0.76, green: 0.86, blue: 0.95, opacity: 0.86))
                        .multilineTextAlignment(.leading)
                        .lineLimit(1)
                }
                .layoutPriority(1)
            }
            .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
            .background(Color(red: 0.18, green: 0.23, blue: 0.31, opacity: 0.98))
            .cornerRadius(18)
        }
    }
}

struct DemoMetricCard: View {
    let title: String
    let value: String
    let note: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Color(red: 0.82, green: 0.89, blue: 0.97, opacity: 0.84))
                .multilineTextAlignment(.leading)
                .lineLimit(1)

            Text(value)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)

            Text(note)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(accent)
                .multilineTextAlignment(.leading)
        }
        .padding(EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18))
        .background(Color(red: 0.14, green: 0.18, blue: 0.25, opacity: 0.98))
        .cornerRadius(24)
        .shadow(color: Color.black.opacity(0.20), radius: 6, x: 0, y: 10)
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
        VStack(alignment: .leading, spacing: 8) {
            Text(card.title)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)

            Text(card.summary)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(red: 0.79, green: 0.88, blue: 0.97, opacity: 0.86))
                .multilineTextAlignment(.leading)

            Text(card.meta)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(card.accent)
                .multilineTextAlignment(.leading)
        }
        .padding(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.21, blue: 0.29, opacity: 0.98),
                    Color(red: 0.12, green: 0.16, blue: 0.22, opacity: 0.98),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .cornerRadius(22)
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

struct DemoLayout {
    let size: CGSize

    var compact: Bool { size.width < 980 || size.height < 680 }
    var outerPadding: CGFloat { compact ? 18 : 26 }
    var gap: CGFloat { compact ? 14 : 18 }
    var toolbarHeight: CGFloat { compact ? 76 : 84 }
    var bodyHeight: CGFloat { max(280, size.height - outerPadding * 2 - toolbarHeight - gap) }
    var sidebarWidth: CGFloat { compact ? 220 : 248 }
    var railWidth: CGFloat { compact ? 260 : 300 }
    var toolbarCornerRadius: CGFloat { compact ? 18 : 22 }
    var panelCornerRadius: CGFloat { compact ? 24 : 30 }
    var toolbarTitleWidth: CGFloat { compact ? 188 : 248 }
    var searchWidth: CGFloat { compact ? 210 : 280 }
    var backendWidth: CGFloat { compact ? 108 : 132 }
    var eventsWidth: CGFloat { compact ? 124 : 136 }
    var modeWidth: CGFloat { compact ? 132 : 156 }
    var pillHeight: CGFloat { 38 }
    var headlineSize: CGFloat { compact ? 24 : 30 }
    var heroHeight: CGFloat { compact ? 230 : 250 }
    var compactActions: Bool { compact }

    var toolbarPadding: EdgeInsets {
        compact
            ? EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
            : EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18)
    }

    var panelPadding: EdgeInsets {
        compact
            ? EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
            : EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18)
    }

    var accentA: CGRect {
        CGRect(
            x: outerPadding + size.width * 0.30,
            y: outerPadding + toolbarHeight + gap + 18,
            width: compact ? 170 : 280,
            height: compact ? 108 : 146
        )
    }

    var accentB: CGRect {
        CGRect(
            x: outerPadding + size.width * 0.60,
            y: outerPadding + toolbarHeight + heroHeight + gap * 2,
            width: compact ? 148 : 210,
            height: compact ? 82 : 108
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

enum DemoModule: CaseIterable {
    case layout
    case input
    case animation

    var label: String {
        switch self {
        case .layout: return "LAYOUT"
        case .input: return "INPUT"
        case .animation: return "ANIMATION"
        }
    }

    var statusLabel: String { "MODE: \(label)" }
    var headline: String {
        switch self {
        case .layout: return "PURE SWIFT LAYOUT CORE"
        case .input: return "POINTER AND KEYBOARD ROUTING"
        case .animation: return "FRAME-DRIVEN UI MOTION"
        }
    }

    var summary: String {
        switch self {
        case .layout: return "RESPONSIVE COMPOSITION AND PANEL STRUCTURE"
        case .input: return "HOVER, PRESS, FOCUS, AND SCROLL ROUTING"
        case .animation: return "FRAME-TIMED STATE TRANSITIONS AND CHROME"
        }
    }

    var detailLine: String {
        switch self {
        case .layout: return "STACK  SCROLL  CLIP  INTRINSIC"
        case .input: return "HOVER  PRESS  FOCUS  ACTIVATE"
        case .animation: return "TIMERS  PALETTES  STATE  REDRAW"
        }
    }

    var systemImage: String {
        switch self {
        case .layout: return "rectangle.3.group"
        case .input: return "keyboard"
        case .animation: return "sparkles"
        }
    }

    var glowColor: Color {
        switch self {
        case .layout: return Color(red: 0.30, green: 0.59, blue: 0.80, opacity: 0.92)
        case .input: return Color(red: 0.25, green: 0.67, blue: 0.62, opacity: 0.92)
        case .animation: return Color(red: 0.94, green: 0.58, blue: 0.33, opacity: 0.94)
        }
    }

    var stripeColor: Color {
        switch self {
        case .layout: return Color(red: 0.43, green: 0.71, blue: 0.86, opacity: 0.88)
        case .input: return Color(red: 0.44, green: 0.78, blue: 0.73, opacity: 0.88)
        case .animation: return Color(red: 0.95, green: 0.71, blue: 0.38, opacity: 0.90)
        }
    }

    var fillColor: Color {
        switch self {
        case .layout: return Color(red: 0.22, green: 0.31, blue: 0.41, opacity: 0.96)
        case .input: return Color(red: 0.20, green: 0.35, blue: 0.38, opacity: 0.96)
        case .animation: return Color(red: 0.39, green: 0.29, blue: 0.21, opacity: 0.96)
        }
    }

    var accentColor: Color {
        switch self {
        case .layout: return Color(red: 0.31, green: 0.40, blue: 0.51, opacity: 1.0)
        case .input: return Color(red: 0.27, green: 0.45, blue: 0.49, opacity: 1.0)
        case .animation: return Color(red: 0.55, green: 0.42, blue: 0.29, opacity: 1.0)
        }
    }

    var panelStartColor: Color {
        switch self {
        case .layout: return Color(red: 0.19, green: 0.24, blue: 0.33, opacity: 0.98)
        case .input: return Color(red: 0.16, green: 0.24, blue: 0.28, opacity: 0.98)
        case .animation: return Color(red: 0.24, green: 0.21, blue: 0.18, opacity: 0.98)
        }
    }

    var panelEndColor: Color {
        switch self {
        case .layout: return Color(red: 0.13, green: 0.18, blue: 0.26, opacity: 0.98)
        case .input: return Color(red: 0.12, green: 0.21, blue: 0.24, opacity: 0.98)
        case .animation: return Color(red: 0.20, green: 0.17, blue: 0.14, opacity: 0.98)
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
        }
    }
}
