#if canImport(SwiftUI)
    import SwiftUI
#else
    import WinSwiftUI
#endif

/// A live component workbench, shared unchanged with the macOS SwiftUI demo.
///
/// The enclosing gallery owns scrolling and responsive breakpoints. Keeping
/// this surface self-sizing makes it equally useful as a full gallery page, an
/// inspector panel, or an embedded section in another dashboard.
struct DemoComponentShowcase: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: DemoDashboardModel
    @ObservedObject var galleryState: DemoGalleryState

    let compact: Bool

    init(model: DemoDashboardModel, compact: Bool = false) {
        self.model = model
        self.galleryState = model.galleryState
        self.compact = compact
    }

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }

    private var validDraft: Bool {
        galleryState.draftName.contains { !$0.isWhitespace } && galleryState.draftName.count <= 36
    }

    private var intensityPercent: Int {
        Int((galleryState.intensity * 100).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DemoMetrics.s4) {
            VStack(alignment: .leading, spacing: DemoMetrics.s1) {
                Text("Input & controls")
                    .font(DemoType.section)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("Exercise the same SwiftUI controls on every supported renderer")
                    .font(DemoType.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            actionSection
            inputSection
            selectionSection
            rangeSection
            stateSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("gallery.component-showcase")
    }

    // MARK: - Actions

    private var actionSection: some View {
        DemoShowcaseCard(
            title: "Actions & feedback",
            detail: "Pressable controls with focused, disabled, and destructive states",
            systemImage: "bolt.fill",
            count: "4 variants"
        ) {
            VStack(alignment: .leading, spacing: DemoMetrics.s3) {
                actionButtons

                HStack(alignment: .center, spacing: DemoMetrics.s2) {
                    DemoStatusDot(palette.success)

                    Text(model.lastAction)
                        .font(DemoType.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityIdentifier("gallery.actions.last-event")

                    Spacer(minLength: 0)

                    Text("\(model.interactionCount) events")
                        .font(DemoType.captionStrong)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .padding(.horizontal, DemoMetrics.s3)
                .frame(height: DemoMetrics.s8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.surface2)
                .cornerRadius(DemoMetrics.radiusSM)
            }
        }
        .accessibilityIdentifier("gallery.section.actions")
    }

    @ViewBuilder
    private var actionButtons: some View {
        if compact {
            VStack(alignment: .leading, spacing: DemoMetrics.s2) {
                HStack(alignment: .center, spacing: DemoMetrics.s2) {
                    primaryAction
                    duplicateAction
                }

                HStack(alignment: .center, spacing: DemoMetrics.s2) {
                    disabledAction
                    destructiveAction
                }
            }
        } else {
            HStack(alignment: .center, spacing: DemoMetrics.s2) {
                primaryAction
                duplicateAction
                disabledAction
                destructiveAction
                Spacer(minLength: 0)
            }
        }
    }

    private var primaryAction: some View {
        DemoButton("Run action", kind: .accent) {
            model.performAction("Ran component gallery action")
        }
        .accessibilityIdentifier("gallery.actions.run")
        .accessibilityHint("Runs the component gallery example action")
    }

    private var duplicateAction: some View {
        DemoButton("Duplicate") {
            model.performAction("Duplicated component example")
        }
        .accessibilityIdentifier("gallery.actions.duplicate")
    }

    private var disabledAction: some View {
        DemoButton("Unavailable") {}
            .disabled(true)
            .opacity(0.5)
            .accessibilityIdentifier("gallery.actions.unavailable")
            .help("This action demonstrates a disabled control")
    }

    private var destructiveAction: some View {
        DemoButton("Remove", labelColor: palette.danger) {
            model.performAction("Removed component example")
        }
        .accessibilityIdentifier("gallery.actions.remove")
    }

    // MARK: - Text entry

    private var inputSection: some View {
        DemoShowcaseCard(
            title: "Text entry & validation",
            detail: "Focusable input, submit handling, and live validation",
            systemImage: "textformat",
            count: "Interactive"
        ) {
            VStack(alignment: .leading, spacing: DemoMetrics.s3) {
                TextField("Name this component collection", text: $galleryState.draftName)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("gallery.input.name")
                    .accessibilityLabel("Component collection name")
                    .onSubmit {
                        applyDraft()
                    }

                inputFooter
            }
        }
        .accessibilityIdentifier("gallery.section.input")
    }

    @ViewBuilder
    private var inputFooter: some View {
        if compact {
            VStack(alignment: .leading, spacing: DemoMetrics.s2) {
                inputValidation
                applyDraftAction
            }
        } else {
            HStack(alignment: .center, spacing: DemoMetrics.s2) {
                inputValidation
                Spacer(minLength: 0)
                applyDraftAction
            }
        }
    }

    private var inputValidation: some View {
        HStack(alignment: .center, spacing: DemoMetrics.s2) {
            DemoStatusDot(validDraft ? palette.success : palette.warning)

            Text(validDraft ? "Ready to publish" : "Enter 1–36 nonblank characters")
                .font(DemoType.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text("\(galleryState.draftName.count)/36")
                .font(DemoType.captionStrong)
                .foregroundColor(validDraft ? palette.accentInk : palette.warning)
                .lineLimit(1)
                .accessibilityLabel("\(galleryState.draftName.count) of 36 characters")
        }
        .accessibilityIdentifier("gallery.input.validation")
    }

    private var applyDraftAction: some View {
        DemoButton("Apply label") {
            applyDraft()
        }
        .disabled(!validDraft)
        .opacity(validDraft ? 1 : 0.5)
        .accessibilityIdentifier("gallery.input.apply")
    }

    private func applyDraft() {
        guard validDraft else { return }
        model.performAction("Applied component label: \(galleryState.draftName)")
    }

    // MARK: - Selection

    private var selectionSection: some View {
        DemoShowcaseCard(
            title: "Selection & preferences",
            detail: "Segmented choice and independently bound switches",
            systemImage: "switch.2",
            count: "3 bindings"
        ) {
            VStack(alignment: .leading, spacing: DemoMetrics.s3) {
                VStack(alignment: .leading, spacing: DemoMetrics.s2) {
                    Text("Interface density")
                        .font(DemoType.bodyStrong)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Picker("Interface density", selection: densityBinding) {
                        Text("Compact").tag(DemoShowcaseDensity.compact)
                        Text("Balanced").tag(DemoShowcaseDensity.balanced)
                        Text("Relaxed").tag(DemoShowcaseDensity.relaxed)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityIdentifier("gallery.selection.density")
                }

                DemoRule(palette.strokeSubtle)

                DemoShowcaseControlRow(
                    title: "Live updates",
                    detail: "Refresh values as the scene changes",
                    compact: compact
                ) {
                    Toggle("Live updates", isOn: liveUpdatesBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityIdentifier("gallery.selection.live-updates")
                }

                DemoRule(palette.strokeSubtle)

                DemoShowcaseControlRow(
                    title: "Notifications",
                    detail: "Surface important interaction events",
                    compact: compact
                ) {
                    Toggle("Notifications", isOn: notificationsBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityIdentifier("gallery.selection.notifications")
                }
            }
        }
        .accessibilityIdentifier("gallery.section.selection")
    }

    private var densityBinding: Binding<DemoShowcaseDensity> {
        Binding(
            get: { galleryState.density },
            set: { nextDensity in
                guard nextDensity != galleryState.density else { return }
                galleryState.density = nextDensity
                model.performAction("Set gallery density to \(nextDensity.label)")
            }
        )
    }

    private var liveUpdatesBinding: Binding<Bool> {
        Binding(
            get: { galleryState.liveUpdatesEnabled },
            set: { enabled in
                guard enabled != galleryState.liveUpdatesEnabled else { return }
                galleryState.liveUpdatesEnabled = enabled
                model.performAction(enabled ? "Enabled gallery live updates" : "Paused gallery live updates")
            }
        )
    }

    private var notificationsBinding: Binding<Bool> {
        Binding(
            get: { galleryState.notificationsEnabled },
            set: { enabled in
                guard enabled != galleryState.notificationsEnabled else { return }
                galleryState.notificationsEnabled = enabled
                model.performAction(enabled ? "Enabled gallery notifications" : "Muted gallery notifications")
            }
        )
    }

    // MARK: - Ranges and progress

    private var rangeSection: some View {
        DemoShowcaseCard(
            title: "Ranges & progress",
            detail: "Stepped slider, bounded stepper, and determinate progress",
            systemImage: "slider.horizontal.3",
            count: "0–100%"
        ) {
            VStack(alignment: .leading, spacing: DemoMetrics.s3) {
                DemoShowcaseControlRow(
                    title: "Render intensity",
                    detail: "Drag or use the arrow keys",
                    compact: compact
                ) {
                    HStack(alignment: .center, spacing: DemoMetrics.s2) {
                        Slider(value: intensityBinding, in: 0...1, step: 0.05)
                            .accessibilityLabel("Render intensity")
                            .accessibilityValue("\(intensityPercent) percent")
                            .accessibilityIdentifier("gallery.range.intensity")
                            .frame(width: compact ? 136 : 160)

                        Text("\(intensityPercent)%")
                            .font(DemoType.captionStrong)
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .trailing)
                            .accessibilityHidden(true)
                    }
                }

                DemoRule(palette.strokeSubtle)

                DemoShowcaseControlRow(
                    title: "Concurrent tasks",
                    detail: "Bounded to eight simultaneous jobs",
                    compact: compact
                ) {
                    HStack(alignment: .center, spacing: DemoMetrics.s2) {
                        Text("\(galleryState.concurrency)")
                            .font(DemoType.captionStrong)
                            .foregroundStyle(.primary)
                            .frame(width: 20, alignment: .trailing)

                        Stepper("Concurrent tasks", value: concurrencyBinding, in: 1...8)
                            .labelsHidden()
                            .accessibilityIdentifier("gallery.range.concurrency")
                    }
                }

                DemoRule(palette.strokeSubtle)

                VStack(alignment: .leading, spacing: DemoMetrics.s2) {
                    HStack(alignment: .center, spacing: DemoMetrics.s2) {
                        Text("Pipeline capacity")
                            .font(DemoType.bodyStrong)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer(minLength: 0)

                        Text("\(intensityPercent)% reserved")
                            .font(DemoType.captionStrong)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    ProgressView(value: galleryState.intensity)
                        .progressViewStyle(.linear)
                        .accessibilityLabel("Pipeline capacity")
                        .accessibilityValue("\(intensityPercent) percent reserved")
                        .accessibilityIdentifier("gallery.range.progress")
                }
            }
        }
        .accessibilityIdentifier("gallery.section.ranges")
    }

    private var intensityBinding: Binding<Double> {
        Binding(
            get: { galleryState.intensity },
            set: { newIntensity in
                guard newIntensity != galleryState.intensity else { return }
                galleryState.intensity = newIntensity
                model.performAction("Set gallery intensity to \(Int((newIntensity * 100).rounded()))%")
            }
        )
    }

    private var concurrencyBinding: Binding<Int> {
        Binding(
            get: { galleryState.concurrency },
            set: { newConcurrency in
                guard newConcurrency != galleryState.concurrency else { return }
                galleryState.concurrency = newConcurrency
                model.performAction("Set gallery concurrency to \(newConcurrency)")
            }
        )
    }

    // MARK: - Status and inspection

    private var stateSection: some View {
        DemoShowcaseCard(
            title: "Status & inspection",
            detail: "Semantic status chips and expandable component metadata",
            systemImage: "chart.bar",
            count: "Live state"
        ) {
            VStack(alignment: .leading, spacing: DemoMetrics.s3) {
                statusPills

                DemoRule(palette.strokeSubtle)

                DemoShowcaseControlRow(
                    title: "Active renderer",
                    detail: "Backend identity supplied by the app shell",
                    compact: compact
                ) {
                    Text(model.rendererIdentity.displayName)
                        .font(DemoType.captionStrong)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .accessibilityIdentifier("gallery.status.renderer")
                }

                DemoRule(palette.strokeSubtle)

                DisclosureGroup("Inspect component state", isExpanded: inspectorBinding) {
                    VStack(alignment: .leading, spacing: DemoMetrics.s2) {
                        inspectorRow("Density", value: galleryState.density.label)
                        inspectorRow("Live updates", value: galleryState.liveUpdatesEnabled ? "Enabled" : "Paused")
                        inspectorRow("Notifications", value: galleryState.notificationsEnabled ? "Enabled" : "Muted")
                        inspectorRow("Capacity", value: "\(intensityPercent)%")
                        inspectorRow("Concurrency", value: "\(galleryState.concurrency) tasks")

                        DemoButton("Reset showcase") {
                            resetShowcase()
                        }
                        .padding(.top, DemoMetrics.s1)
                        .accessibilityIdentifier("gallery.inspector.reset")
                    }
                    .padding(.top, DemoMetrics.s2)
                }
                .font(DemoType.bodyStrong)
                .accessibilityIdentifier("gallery.inspector.disclosure")
            }
        }
        .accessibilityIdentifier("gallery.section.status")
    }

    @ViewBuilder
    private var statusPills: some View {
        if compact {
            VStack(alignment: .leading, spacing: DemoMetrics.s2) {
                HStack(alignment: .center, spacing: DemoMetrics.s2) {
                    DemoShowcaseStatusPill("Operational", color: palette.success)
                    DemoShowcaseStatusPill("Queued", color: palette.accentInk)
                }

                DemoShowcaseStatusPill("Needs attention", color: palette.warning)
            }
        } else {
            HStack(alignment: .center, spacing: DemoMetrics.s2) {
                DemoShowcaseStatusPill("Operational", color: palette.success)
                DemoShowcaseStatusPill("Queued", color: palette.accentInk)
                DemoShowcaseStatusPill("Needs attention", color: palette.warning)
                Spacer(minLength: 0)
            }
        }
    }

    private var inspectorBinding: Binding<Bool> {
        Binding(
            get: { galleryState.inspectorExpanded },
            set: { expanded in
                guard expanded != galleryState.inspectorExpanded else { return }
                galleryState.inspectorExpanded = expanded
                model.performAction(expanded ? "Expanded component inspector" : "Collapsed component inspector")
            }
        )
    }

    private func inspectorRow(_ label: String, value: String) -> some View {
        HStack(alignment: .center, spacing: DemoMetrics.s2) {
            Text(label)
                .font(DemoType.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            Spacer(minLength: 0)

            Text(value)
                .font(DemoType.captionStrong)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func resetShowcase() {
        galleryState.draftName = "Native component kit"
        galleryState.density = .balanced
        galleryState.liveUpdatesEnabled = true
        galleryState.notificationsEnabled = false
        galleryState.intensity = 0.62
        galleryState.concurrency = 3
        model.performAction("Reset component showcase")
    }
}

enum DemoShowcaseDensity: String, Hashable {
    case compact
    case balanced
    case relaxed

    var label: String {
        switch self {
        case .compact:
            return "Compact"
        case .balanced:
            return "Balanced"
        case .relaxed:
            return "Relaxed"
        }
    }
}

/// Consistent section chrome without adding a second surface system.
private struct DemoShowcaseCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let detail: String
    let systemImage: String
    let count: String
    let content: Content

    init(
        title: String,
        detail: String,
        systemImage: String,
        count: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.count = count
        self.content = content()
    }

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }

    var body: some View {
        DemoCard(padding: DemoMetrics.s4) {
            VStack(alignment: .leading, spacing: DemoMetrics.s3) {
                HStack(alignment: .center, spacing: DemoMetrics.s2) {
                    DemoRowGlyph(systemImage, size: 14)

                    VStack(alignment: .leading, spacing: DemoMetrics.s1) {
                        Text(title)
                            .font(DemoType.cardTitle)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text(detail)
                            .font(DemoType.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    .layoutPriority(1)

                    Spacer(minLength: 0)

                    Text(count)
                        .font(DemoType.captionStrong)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, DemoMetrics.s2)
                        .frame(height: DemoMetrics.chipHeight)
                        .background(palette.surface2)
                        .cornerRadius(DemoMetrics.radiusSM)
                        .accessibilityHidden(true)
                }

                DemoRule(palette.strokeSubtle)

                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A labelled control row which becomes a stacked row at narrow widths.
private struct DemoShowcaseControlRow<Control: View>: View {
    let title: String
    let detail: String
    let compact: Bool
    let control: Control

    init(
        title: String,
        detail: String,
        compact: Bool,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.detail = detail
        self.compact = compact
        self.control = control()
    }

    @ViewBuilder
    var body: some View {
        if compact {
            VStack(alignment: .leading, spacing: DemoMetrics.s2) {
                rowLabel
                control
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .center, spacing: DemoMetrics.s3) {
                rowLabel
                Spacer(minLength: DemoMetrics.s2)
                control
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var rowLabel: some View {
        VStack(alignment: .leading, spacing: DemoMetrics.s1) {
            Text(title)
                .font(DemoType.bodyStrong)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(detail)
                .font(DemoType.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .layoutPriority(1)
    }
}

/// A status color is restricted to a small dot and a low-opacity label wash.
private struct DemoShowcaseStatusPill: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let color: Color

    init(_ title: String, color: Color) {
        self.title = title
        self.color = color
    }

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }

    var body: some View {
        HStack(alignment: .center, spacing: DemoMetrics.s2 - 2) {
            DemoStatusDot(color)

            Text(title)
                .font(DemoType.badge)
                .foregroundColor(color)
                .lineLimit(1)
        }
        .padding(.horizontal, DemoMetrics.s2)
        .frame(height: DemoMetrics.chipHeight)
        .background(palette.statusWash(color))
        .cornerRadius(DemoMetrics.radiusSM)
    }
}
