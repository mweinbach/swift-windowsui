#if canImport(SwiftUI)
    import SwiftUI
#else
    import WinSwiftUI
#endif

/// Ordinary shared-source controls. Small built-in inputs may finish before a
/// pointer can reach Cancel; no artificial timer delays actual completion.
struct DemoDashboardDataControls: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: DemoDashboardDataModel

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: DemoMetrics.s2) {
            Text(title)
                .font(DemoType.captionStrong)
                .foregroundStyle(model.snapshot.phase == .failed ? palette.danger : palette.accentInk)
                .accessibilityIdentifier("dashboard.data.status")

            Text(detail)
                .font(DemoType.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("dashboard.data.detail")

            HStack(spacing: DemoMetrics.s2) {
                Text("Input")
                    .font(DemoType.caption)
                    .foregroundStyle(.secondary)
                ForEach(DemoDashboardDataSample.allCases, id: \.self) { sample in
                    Button {
                        model.select(sample)
                    } label: {
                        Text(sample.label)
                            .font(DemoType.captionStrong)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, DemoMetrics.s2)
                            .padding(.vertical, DemoMetrics.s1)
                            .background(model.snapshot.selectedSample == sample ? palette.surface3 : palette.surface2)
                            .cornerRadius(DemoMetrics.radiusSM)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isClosed)
                    .accessibilityLabel("\(sample.label) local data")
                    .accessibilityValue(model.snapshot.selectedSample == sample ? "Selected" : "Not selected")
                    .accessibilityIdentifier("dashboard.data.sample.\(sample.rawValue)")
                }
            }

            HStack(spacing: DemoMetrics.s2) {
                Button("Refresh") { model.refresh() }
                    .disabled(model.isClosed)
                    .accessibilityIdentifier("dashboard.data.refresh")
                if model.canRetry {
                    Button("Retry") { model.retry() }
                        .accessibilityIdentifier("dashboard.data.retry")
                }
                if model.canCancel {
                    Button("Cancel") { model.cancel() }
                        .accessibilityIdentifier("dashboard.data.cancel")
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var title: String {
        switch model.snapshot.phase {
        case .preview: return "Preview data"
        case .loading:
            return model.isWaitingForPreviousRead ? "Waiting for previous read" : "Loading local data"
        case .ready: return "Local data loaded"
        case .empty: return "Local data is empty"
        case .failed: return "Unable to load local data"
        case .cancelled: return "Load cancelled"
        case .closed: return "Data loader closed"
        }
    }

    private var detail: String {
        switch model.snapshot.phase {
        case .preview:
            return "Choose an input, then Refresh to read and decode its local JSON."
        case .loading:
            if model.isWaitingForPreviousRead {
                return "The previous read is cancelling. Only the latest request will start."
            }
            return "Reading local JSON. The current chart stays visible until the read finishes."
        case .ready:
            if case .report(let report) = model.snapshot.content {
                let noun = report.pointCount == 1 ? "sample" : "samples"
                return "Loaded \(report.pointCount) \(noun). Dashboard activity still adjusts this sample chart."
            }
            return "Local data loaded."
        case .empty:
            return "This report contains no samples. Choose Valid, then Refresh to load data."
        case .failed:
            return (model.snapshot.error?.message ?? "The local read failed.")
                + " Retry uses the same input; Refresh uses the selection below."
        case .cancelled:
            return model.isReading
                ? "Result discarded. Waiting for the physical read to return."
                : "No result was published. Refresh to load the selected input."
        case .closed:
            return "The owner released the report. This model no longer accepts requests."
        }
    }
}
