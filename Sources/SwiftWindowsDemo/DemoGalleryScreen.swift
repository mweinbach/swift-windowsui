#if canImport(SwiftUI)
    import SwiftUI
#else
    import WinSwiftUI
#endif

/// Durable interaction state for the component workbench.
///
/// The retained Windows host recreates child view values when an observed
/// object changes. A nested view's local `@State` therefore cannot own a sheet
/// binding or an editor value: the next host rebuild would immediately replace
/// it with the declaration's default. The app model retains this one object
/// and each interactive collection observes it directly, preserving normal
/// same-source SwiftUI bindings across both host and navigation rebuilds.
@MainActor
final class DemoGalleryState: ObservableObject {
    @Published var isObservationPreviewBright = true

    // Control workbench.
    @Published var draftName = "Native component kit"
    @Published var density: DemoShowcaseDensity = .balanced
    @Published var liveUpdatesEnabled = true
    @Published var notificationsEnabled = false
    @Published var intensity = 0.62
    @Published var concurrency = 3
    @Published var inspectorExpanded = false

    // Rendering samples.
    @Published var colorsAreReversed = false
    @Published var isExpanded = false

    // Presentation surfaces and their configuration.
    @Published var isSheetPresented = false
    @Published var isPopoverPresented = false
    @Published var isAlertPresented = false
    @Published var isConfirmationPresented = false
    @Published var areInteractionDetailsExpanded = false
    @Published var isLivePreviewEnabled = true
    @Published var areAlignmentGuidesEnabled = false
}

/// The gallery filters real, interactive collections rather than static image
/// thumbnails. Search includes the vocabulary an app author would naturally
/// use, so looking for "blur material" finds its rendering collection even
/// though those words are not both in the collection's short tab label.
enum DemoGalleryCategory: String, CaseIterable, Hashable {
    case all
    case controls
    case visuals
    case presentations

    static var collections: [Self] { [.controls, .visuals, .presentations] }

    var label: String {
        switch self {
        case .all: return "All"
        case .controls: return "Controls"
        case .visuals: return "Rendering"
        case .presentations: return "Presentations"
        }
    }

    var summary: String {
        switch self {
        case .all:
            return "Every interactive component and rendering example"
        case .controls:
            return "Buttons, text input, toggles, pickers, sliders, and progress"
        case .visuals:
            return "Gradients, materials, motion, typography, color, and surfaces"
        case .presentations:
            return "Sheets, popovers, alerts, confirmation dialogs, and menus"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .controls: return "slider.horizontal.3"
        case .visuals: return "sparkles"
        case .presentations: return "rectangle.split.3x1"
        }
    }

    /// An empty query includes every collection. Otherwise every
    /// whitespace-separated term must occur somewhere in the collection's
    /// title, description, or synonyms; terms may arrive in any order.
    func matches(query: String) -> Bool {
        let terms = query.lowercased().split(whereSeparator: { $0.isWhitespace })
        guard !terms.isEmpty else { return true }

        if self == .all {
            return Self.collections.contains { $0.matches(query: query) }
        }

        let searchableText = ([label, summary] + keywords).joined(separator: " ").lowercased()
        return terms.allSatisfy { searchableText.contains($0) }
    }

    private var keywords: [String] {
        switch self {
        case .all:
            return ["gallery", "showcase", "catalog", "examples", "patterns"]
        case .controls:
            return [
                "input", "field", "form", "binding", "state", "checkbox", "switch", "button",
                "segmented", "stepper", "picker", "slider", "progress", "validation", "text",
                "scroll", "geometry", "phase", "visibility", "observation", "animation",
            ]
        case .visuals:
            return [
                "visual", "render", "rendering", "gpu", "software", "gradient", "linear", "radial",
                "angular", "glass", "material", "blur", "shape", "animation", "motion", "font",
                "type", "typography", "swatch", "color", "clip", "surface", "transform",
            ]
        case .presentations:
            return [
                "present", "presentation", "sheet", "popover", "alert", "confirm", "dialog", "menu",
                "modal", "overlay", "navigation", "disclosure", "context", "action", "keyboard",
            ]
        }
    }
}

/// A complete, same-source SwiftUI workbench for the controls and retained
/// rendering features this project actually implements. The shell owns the
/// viewport and its children remain ordinary self-sized SwiftUI collections,
/// so the exact same gallery builds against native Apple SwiftUI on macOS.
struct DemoGalleryScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var windowState: DemoWindowState
    @ObservedObject var model: DemoDashboardModel

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }

    var visibleCategories: [DemoGalleryCategory] {
        DemoGalleryCategory.collections.filter { category in
            (model.selectedGalleryCategory == .all || model.selectedGalleryCategory == category)
                && category.matches(query: model.galleryQuery)
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 780
            let pageMargin = proxy.size.width < 620 ? DemoMetrics.s4 : DemoMetrics.s6
            let contentWidth = min(1040, max(0, proxy.size.width - pageMargin * 2))

            VStack(alignment: .leading, spacing: 0) {
                DemoGalleryHeader(model: model, compact: compact)
                    .frame(width: proxy.size.width, alignment: .leading)

                DemoRule(palette.strokeStrong, length: proxy.size.width)

                ScrollView {
                    VStack(alignment: .leading, spacing: DemoMetrics.s5) {
                        DemoGalleryIntroduction(model: model, compact: compact)

                        DemoGalleryCategoryBar(model: model)

                        if visibleCategories.isEmpty {
                            DemoGalleryEmptyState(model: model)
                        } else {
                            if visibleCategories.contains(.visuals) {
                                DemoGalleryVisualShowcase(model: model, compact: compact)
                            }

                            if visibleCategories.contains(.controls) {
                                DemoComponentShowcase(model: model, compact: compact)
                                DemoObservationShowcase(model: model, state: windowState.observation)
                            }

                            if visibleCategories.contains(.presentations) {
                                DemoGalleryPresentationShowcase(model: model, compact: compact)
                            }

                            DemoGalleryFooter(model: model)
                        }
                    }
                    .frame(width: contentWidth, alignment: .topLeading)
                    .padding(.horizontal, pageMargin)
                    .padding(.vertical, DemoMetrics.s5)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(palette.surface0)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .background(palette.base)
        }
    }
}

private struct DemoGalleryHeader: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: DemoDashboardModel
    let compact: Bool

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }

    @ViewBuilder
    var body: some View {
        if compact {
            VStack(alignment: .leading, spacing: DemoMetrics.s2) {
                HStack(alignment: .center, spacing: DemoMetrics.s2) {
                    title

                    Spacer(minLength: 0)

                    rendererStatus
                }

                DemoGallerySearchField(model: model)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, DemoMetrics.s4)
            .padding(.vertical, DemoMetrics.s3)
            .background(palette.base)
        } else {
            HStack(alignment: .center, spacing: DemoMetrics.s4) {
                VStack(alignment: .leading, spacing: 2) {
                    title

                    Text("Explore real controls, visual effects, and interaction patterns")
                        .font(DemoType.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: DemoMetrics.s4)

                DemoGallerySearchField(model: model)
                    .frame(width: 260)

                rendererStatus
            }
            .padding(.horizontal, DemoMetrics.s6)
            .frame(height: 72, alignment: .leading)
            .background(palette.base)
        }
    }

    private var title: some View {
        Text("Component gallery")
            .font(DemoType.screenTitle)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .accessibilityAddTraits(.isHeader)
    }

    private var rendererStatus: some View {
        HStack(alignment: .center, spacing: DemoMetrics.s1 + 2) {
            Circle()
                .fill(palette.success)
                .frame(width: DemoMetrics.dotSize, height: DemoMetrics.dotSize)

            Text(model.rendererIdentity.displayName)
                .font(DemoType.captionStrong)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, DemoMetrics.s2)
        .frame(height: DemoMetrics.chipHeight)
        .background(palette.surface2)
        .cornerRadius(DemoMetrics.radiusSM)
        .accessibilityLabel("Active renderer: \(model.rendererIdentity.displayName)")
    }
}

private struct DemoGallerySearchField: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: DemoDashboardModel

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }

    var body: some View {
        HStack(alignment: .center, spacing: DemoMetrics.s2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.tertiary)

            TextField("Search components", text: $model.galleryQuery)
                .font(DemoType.body)
                .textFieldStyle(.plain)
                .accessibilityLabel("Search components")

            if !model.galleryQuery.isEmpty {
                Button {
                    model.galleryQuery = ""
                    model.performAction("Cleared gallery search")
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear gallery search")
                .help("Clear the gallery search")
            }
        }
        .padding(.horizontal, DemoMetrics.s2)
        .frame(height: 34)
        .background(palette.surface1)
        .cornerRadius(DemoMetrics.radiusMD)
        .padding(1)
        .background(palette.stroke)
        .cornerRadius(DemoMetrics.radiusMD + 1)
    }
}

private struct DemoGalleryIntroduction: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: DemoDashboardModel
    let compact: Bool

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }

    var body: some View {
        DemoCard(padding: compact ? DemoMetrics.s4 : DemoMetrics.s5) {
            VStack(alignment: .leading, spacing: DemoMetrics.s3) {
                HStack(alignment: .top, spacing: DemoMetrics.s3) {
                    VStack(alignment: .leading, spacing: DemoMetrics.s1) {
                        DemoEyebrow("Interactive playground")

                        Text("Build with confidence")
                            .font(compact ? DemoType.section : DemoType.screenTitle)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text("Every example below is live, accessible, and rendered by the same UI engine.")
                            .font(DemoType.body)
                            .foregroundStyle(.secondary)
                            .lineLimit(compact ? 2 : 1)
                    }

                    Spacer(minLength: 0)

                    if !compact {
                        Image(systemName: "rectangle.grid.3x2")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(palette.accentInk)
                            .frame(width: 38, height: 38)
                            .background(palette.accentWash)
                            .cornerRadius(DemoMetrics.radiusMD)
                    }
                }

                DemoRule(palette.strokeSubtle)

                HStack(alignment: .center, spacing: compact ? DemoMetrics.s3 : DemoMetrics.s5) {
                    DemoGalleryFact(value: "3", caption: "Collections")
                    DemoGalleryFact(value: "20+", caption: "Live examples")
                    DemoGalleryFact(value: model.rendererIdentity.displayName, caption: "Renderer")

                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DemoGalleryFact: View {
    let value: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(DemoType.bodySelected)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(caption)
                .font(DemoType.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(caption)")
    }
}

private struct DemoGalleryCategoryBar: View {
    @ObservedObject var model: DemoDashboardModel

    var body: some View {
        VStack(alignment: .leading, spacing: DemoMetrics.s2) {
            HStack(alignment: .center, spacing: DemoMetrics.s2) {
                DemoEyebrow("Browse examples")

                Spacer(minLength: 0)

                Text(selectionSummary)
                    .font(DemoType.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            HStack(alignment: .center, spacing: DemoMetrics.s2) {
                ForEach(DemoGalleryCategory.allCases, id: \.self) { category in
                    DemoGalleryCategoryChip(model: model, category: category)
                }

                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var selectionSummary: String {
        if model.selectedGalleryCategory == .all {
            return "3 collections"
        }
        return model.selectedGalleryCategory.label
    }
}

private struct DemoGalleryCategoryChip: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: DemoDashboardModel
    @State private var isHovering = false
    let category: DemoGalleryCategory

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }
    private var isSelected: Bool { model.selectedGalleryCategory == category }

    var body: some View {
        Button {
            guard model.selectedGalleryCategory != category else { return }
            model.selectedGalleryCategory = category
            model.performAction("Showing \(category.label) examples")
        } label: {
            HStack(alignment: .center, spacing: DemoMetrics.s1 + 1) {
                Image(systemName: category.systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isSelected ? palette.accentInk : palette.strokeStrong)

                Text(category.label)
                    .font(isSelected ? DemoType.controlLabelStrong : DemoType.controlLabel)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, DemoMetrics.s2)
            .frame(height: 30)
            .background(isSelected ? palette.accentWash : restingFill)
            .cornerRadius(DemoMetrics.radiusSM)
            .padding(1)
            .background(isSelected ? palette.accentInk.opacity(0.35) : palette.stroke)
            .cornerRadius(DemoMetrics.radiusSM + 1)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("Show \(category.label) examples")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityIdentifier("gallery.category.\(category.rawValue)")
        .help(category.summary)
    }

    private var restingFill: Color {
        isHovering ? palette.surface2 : palette.surface1
    }
}

private struct DemoGalleryEmptyState: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: DemoDashboardModel

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }

    var body: some View {
        DemoCard(padding: DemoMetrics.s6) {
            VStack(alignment: .center, spacing: DemoMetrics.s2) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(palette.accentInk)

                Text("No matching examples")
                    .font(DemoType.cardTitle)
                    .foregroundStyle(.primary)

                Text("Try another search or clear the current filters.")
                    .font(DemoType.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                DemoButton("Clear search") {
                    model.galleryQuery = ""
                    model.selectedGalleryCategory = .all
                    model.performAction("Cleared gallery filters")
                }
                .padding(.top, DemoMetrics.s1)
            }
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DemoGalleryFooter: View {
    @ObservedObject var model: DemoDashboardModel

    var body: some View {
        HStack(alignment: .center, spacing: DemoMetrics.s2) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)

            Text("Rendered live with \(model.rendererIdentity.displayName)")
                .font(DemoType.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            Spacer(minLength: 0)

            Text("Shared SwiftUI source")
                .font(DemoType.caption)
                .foregroundStyle(.quaternary)
                .lineLimit(1)
        }
        .padding(.vertical, DemoMetrics.s2)
    }
}
