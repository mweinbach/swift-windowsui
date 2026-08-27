#if canImport(SwiftUI)
    import SwiftUI
#else
    import WinSwiftUI
#endif

/// The gallery retains these values across observed-object rebuilds. Keeping
/// the readouts outside the scroll content avoids changing the measured rows
/// in response to their own geometry or visibility callbacks.
@MainActor
final class DemoObservationState: ObservableObject {
    @Published private(set) var offset = 0
    @Published private(set) var phaseDescription = "Idle"
    @Published private(set) var isRowVisible = false
    @Published var isPreviewBright = true

    func recordOffset(_ value: Int) {
        guard offset != value else { return }
        offset = value
    }

    func recordVisibility(_ value: Bool) {
        guard isRowVisible != value else { return }
        isRowVisible = value
    }

    func recordPhase(from old: ScrollPhase, to new: ScrollPhase) {
        let description = "\(Self.name(new)) (from \(Self.name(old)))"
        guard phaseDescription != description else { return }
        phaseDescription = description
    }

    private static func name(_ phase: ScrollPhase) -> String {
        switch phase {
        case .idle: return "Idle"
        case .tracking: return "Tracking"
        case .interacting: return "Interacting"
        case .decelerating: return "Decelerating"
        case .animating: return "Animating"
        @unknown default: return "Unknown"
        }
    }
}

/// One small, public-API example: nested scrolling reports presentation
/// geometry and visibility, while an animated binding changes a preview.
struct DemoObservationShowcase: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var model: DemoDashboardModel
    @ObservedObject var state: DemoObservationState

    init(model: DemoDashboardModel) {
        self.model = model
        self.state = model.galleryState.observation
    }

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }
    private var animation: Animation? {
        model.animationsEnabled && !reduceMotion ? .linear(duration: 0.6) : nil
    }

    var body: some View {
        DemoCard(padding: DemoMetrics.s3) {
            VStack(alignment: .leading, spacing: DemoMetrics.s2) {
                Text("Scroll observations")
                    .font(DemoType.cardTitle)
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)

                Text("Scroll inside the sample; the readouts follow its viewport.")
                    .font(DemoType.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Offset: \(state.offset) pt")
                        .accessibilityIdentifier("gallery.observation.offset")
                    Spacer(minLength: DemoMetrics.s2)
                    Text(state.isRowVisible ? "Row 6: visible" : "Row 6: outside")
                        .accessibilityIdentifier("gallery.observation.visibility")
                }
                .font(DemoType.captionStrong)
                .foregroundStyle(.secondary)

                Text("Phase: \(state.phaseDescription)")
                    .font(DemoType.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityIdentifier("gallery.observation.phase")

                ScrollViewReader { proxy in
                    VStack(alignment: .leading, spacing: DemoMetrics.s3) {
                        ScrollView(.vertical) {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(1...12, id: \.self) { index in
                                    row(index).id(index)
                                }
                            }
                        }
                        .onScrollGeometryChange(
                            for: Int.self,
                            of: { geometry in
                                Int((geometry.contentOffset.y + geometry.contentInsets.top).rounded())
                            },
                            action: { _, offset in
                                state.recordOffset(offset)
                            }
                        )
                        .onScrollPhaseChange { old, new in
                            state.recordPhase(from: old, to: new)
                        }
                        .accessibilityLabel("Scroll observation sample")
                        .accessibilityIdentifier("gallery.observation.scroll")
                        .frame(height: 144)
                        .background(palette.surface0)
                        .cornerRadius(DemoMetrics.radiusSM)

                        HStack(alignment: .center, spacing: DemoMetrics.s3) {
                            DemoButton("Back to top") {
                                withAnimation(animation) {
                                    proxy.scrollTo(1, anchor: .top)
                                }
                            }
                            .accessibilityIdentifier("gallery.observation.reset")

                            Spacer(minLength: 0)

                            Toggle("Bright preview", isOn: $state.isPreviewBright.animation(animation))
                                .toggleStyle(.switch)
                                .accessibilityIdentifier("gallery.observation.toggle")

                            RoundedRectangle(cornerRadius: DemoMetrics.radiusSM)
                                .fill(palette.accentInk)
                                .accessibilityHidden(true)
                                .accessibilityIdentifier("gallery.observation.preview")
                                .opacity(state.isPreviewBright ? 1 : 0.25)
                                .frame(width: 32, height: 24)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("gallery.observation-showcase")
    }

    @ViewBuilder
    private func row(_ index: Int) -> some View {
        if index == 6 {
            rowContent(index)
                .onScrollVisibilityChange(threshold: 0.5) { state.recordVisibility($0) }
        } else {
            rowContent(index)
        }
    }

    private func rowContent(_ index: Int) -> some View {
        HStack {
            Text("Row \(index)")
                .font(DemoType.captionStrong)
            Spacer(minLength: DemoMetrics.s2)
            if index == 6 {
                Text("Observed at 50% visibility")
                    .font(DemoType.caption)
            }
        }
        .foregroundStyle(index == 6 ? .primary : .secondary)
        .padding(.horizontal, DemoMetrics.s3)
        .frame(height: 32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(index == 6 ? palette.accentWash : palette.surface1)
    }
}
