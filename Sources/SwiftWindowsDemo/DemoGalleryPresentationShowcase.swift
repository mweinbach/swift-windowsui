#if canImport(SwiftUI)
    import SwiftUI
#else
    import WinSwiftUI
#endif

/// Hands-on examples of the standard SwiftUI presentation surfaces.
///
/// The gallery intentionally exercises the same presentation modifiers as an
/// application: every overlay is real, starts dismissed, and records useful
/// actions in the shared activity feed. Keeping the popover on its own button
/// also demonstrates source-anchored positioning instead of simulating a menu
/// inside the card.
struct DemoGalleryPresentationShowcase: View {
    @ObservedObject var model: DemoDashboardModel
    var compact: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @State private var isSheetPresented = false
    @State private var isPopoverPresented = false
    @State private var isAlertPresented = false
    @State private var isConfirmationPresented = false
    @State private var areInteractionDetailsExpanded = false
    @State private var isLivePreviewEnabled = true
    @State private var areAlignmentGuidesEnabled = false

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }

    init(model: DemoDashboardModel, compact: Bool = false) {
        self.model = model
        self.compact = compact
    }

    var body: some View {
        DemoCard(padding: compact ? DemoMetrics.s3 : DemoMetrics.s4) {
            VStack(alignment: .leading, spacing: DemoMetrics.s4) {
                showcaseHeader

                DemoRule(palette.strokeSubtle)

                presentationControls

                DemoRule(palette.strokeSubtle)

                contextualActions

                interactionDetails
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $isSheetPresented) {
            presentationSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .alert("Presentation ready", isPresented: $isAlertPresented) {
            Button("Continue") {
                model.performAction("Accepted gallery alert")
            }

            Button("Not Now", role: .cancel) {
                model.performAction("Dismissed gallery alert")
            }
        } message: {
            Text("The retained presentation stack is ready for its next interaction.")
        }
        .confirmationDialog(
            "Reset presentation example?",
            isPresented: $isConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Reset Example", role: .destructive) {
                isLivePreviewEnabled = true
                areAlignmentGuidesEnabled = false
                model.performAction("Confirmed gallery action")
            }

            Button("Cancel", role: .cancel) {
                model.performAction("Cancelled gallery action")
            }
        } message: {
            Text("Live preview and alignment guides will return to their defaults.")
        }
    }

    private var showcaseHeader: some View {
        HStack(alignment: .top, spacing: DemoMetrics.s2) {
            DemoRowGlyph("rectangle.split.2x1", accent: palette.accentInk)
                .padding(.top, DemoMetrics.s1)

            VStack(alignment: .leading, spacing: DemoMetrics.s1) {
                Text("Presentation & navigation")
                    .font(DemoType.cardTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("Explore real sheets, popovers, alerts, and contextual actions.")
                    .font(DemoType.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(compact ? 2 : 1)
            }

            Spacer(minLength: 0)

            if !compact {
                HStack(alignment: .center, spacing: DemoMetrics.s1) {
                    DemoStatusDot(palette.success)

                    Text("Interactive")
                        .font(DemoType.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.top, DemoMetrics.s1)
            }
        }
    }

    private var presentationControls: some View {
        VStack(alignment: .leading, spacing: DemoMetrics.s2) {
            DemoEyebrow("Presentation surfaces")

            HStack(alignment: .center, spacing: DemoMetrics.s2) {
                DemoButton("Open Sheet", kind: .accent) {
                    isSheetPresented = true
                    model.performAction("Opened presentation sheet")
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                DemoButton("Show Popover") {
                    isPopoverPresented = true
                    model.performAction("Opened renderer popover")
                }
                .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
                    rendererPopover
                }

                Spacer(minLength: 0)
            }

            HStack(alignment: .center, spacing: DemoMetrics.s2) {
                DemoButton("Show Alert") {
                    isAlertPresented = true
                    model.performAction("Opened gallery alert")
                }

                DemoButton("Confirm Action") {
                    isConfirmationPresented = true
                    model.performAction("Requested gallery action confirmation")
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var contextualActions: some View {
        VStack(alignment: .leading, spacing: DemoMetrics.s2) {
            DemoEyebrow("Commands & context")

            HStack(alignment: .center, spacing: DemoMetrics.s2) {
                Menu {
                    Button("Queue Sample Export") {
                        model.performAction("Queued sample export")
                    }

                    Button("Pin Presentation Example") {
                        model.performAction("Pinned presentation example")
                    }

                    Button("Reset Example", role: .destructive) {
                        isConfirmationPresented = true
                        model.performAction("Requested gallery action confirmation")
                    }
                } label: {
                    HStack(alignment: .center, spacing: DemoMetrics.s1) {
                        Text("Quick Actions")
                            .font(DemoType.controlLabel)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Image(systemName: "chevron.down")
                            .font(DemoType.hint)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, DemoMetrics.s3)
                    .frame(height: DemoMetrics.controlHeight)
                    .background(palette.surface2)
                    .cornerRadius(DemoMetrics.radiusSM)
                    .padding(1)
                    .background(palette.strokeStrong)
                    .cornerRadius(DemoMetrics.radiusSM + 1)
                }
                .buttonStyle(.plain)

                Text("⌘⇧O opens the sheet")
                    .font(DemoType.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }

            contextMenuExample
        }
    }

    private var contextMenuExample: some View {
        HStack(alignment: .center, spacing: DemoMetrics.s2) {
            DemoRowGlyph("ellipsis.circle", size: 13)

            Text("Right-click for more actions")
                .font(DemoType.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            Image(systemName: "ellipsis")
                .font(DemoType.bodyStrong)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, DemoMetrics.s2)
        .frame(height: DemoMetrics.listRowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface2)
        .cornerRadius(DemoMetrics.radiusMD)
        .contextMenu {
            Button("Show Renderer Details") {
                isPopoverPresented = true
                model.performAction("Opened renderer popover")
            }

            Button("Pin Presentation Example") {
                model.performAction("Pinned presentation example")
            }

            Button("Reset Example", role: .destructive) {
                isConfirmationPresented = true
                model.performAction("Requested gallery action confirmation")
            }
        }
    }

    private var interactionDetails: some View {
        DisclosureGroup("Interaction details", isExpanded: $areInteractionDetailsExpanded) {
            VStack(alignment: .leading, spacing: DemoMetrics.s2) {
                detailRow("Renderer", value: model.rendererIdentity.displayName)
                detailRow("Presentation", value: "Retained overlays")
                detailRow("Keyboard", value: "Focus restoration enabled")
            }
            .padding(.top, DemoMetrics.s2)
            .padding(.bottom, DemoMetrics.s1)
        }
        .font(DemoType.body)
        .foregroundStyle(.secondary)
    }

    private var presentationSheet: some View {
        VStack(alignment: .leading, spacing: DemoMetrics.s3) {
            HStack(alignment: .center, spacing: DemoMetrics.s2) {
                DemoRowGlyph("slider.horizontal.3", accent: palette.accentInk)

                Text("Configure presentation")
                    .font(DemoType.cardTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            Text("Adjust the interactive example and return to the gallery.")
                .font(DemoType.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            DemoRule(palette.strokeSubtle)

            Toggle("Live preview", isOn: $isLivePreviewEnabled)
                .font(DemoType.body)

            Toggle("Alignment guides", isOn: $areAlignmentGuidesEnabled)
                .font(DemoType.body)

            DemoRule(palette.strokeSubtle)

            HStack(alignment: .center, spacing: DemoMetrics.s2) {
                Spacer(minLength: 0)

                DemoButton("Cancel") {
                    isSheetPresented = false
                    model.performAction("Dismissed presentation sheet")
                }

                DemoButton("Apply", kind: .accent) {
                    isSheetPresented = false
                    model.performAction("Applied presentation configuration")
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .frame(width: compact ? 272 : 320, alignment: .leading)
        .padding(DemoMetrics.s4)
    }

    private var rendererPopover: some View {
        VStack(alignment: .leading, spacing: DemoMetrics.s3) {
            HStack(alignment: .center, spacing: DemoMetrics.s2) {
                DemoStatusDot(palette.success)

                Text("Renderer details")
                    .font(DemoType.cardTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            Text(model.rendererIdentity.componentDescription)
                .font(DemoType.body)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            DemoRule(palette.strokeSubtle)

            detailRow("Backend", value: model.rendererIdentity.displayName)
            detailRow("Status", value: "Ready")

            HStack(alignment: .center, spacing: DemoMetrics.s2) {
                Spacer(minLength: 0)

                DemoButton("Done") {
                    isPopoverPresented = false
                    model.performAction("Dismissed renderer popover")
                }
            }
        }
        .frame(width: compact ? 224 : 256, alignment: .leading)
        .padding(DemoMetrics.s3)
    }

    private func detailRow(_ title: String, value: String) -> some View {
        HStack(alignment: .center, spacing: DemoMetrics.s2) {
            Text(title)
                .font(DemoType.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            Spacer(minLength: 0)

            Text(value)
                .font(DemoType.captionStrong)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
