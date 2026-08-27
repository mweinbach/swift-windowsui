#if canImport(SwiftUI)
    import SwiftUI
#else
    import WinSwiftUI
#endif

@MainActor
final class DemoLongPressState: ObservableObject {
    @Published var isPressing = false
    @Published var confirmationCount = 0

    var status: String {
        if isPressing { return "Keep holding..." }
        if confirmationCount == 0 { return "Ready to hold" }
        return "Confirmed \(confirmationCount) \(confirmationCount == 1 ? "time" : "times")"
    }
}

/// One public-API gesture example shared with the macOS SwiftUI gallery.
struct DemoLongPressShowcase: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var state: DemoLongPressState

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }

    var body: some View {
        DemoCard(padding: DemoMetrics.s4) {
            VStack(alignment: .leading, spacing: DemoMetrics.s3) {
                Text("Press & hold")
                    .font(DemoType.cardTitle)
                    .foregroundStyle(.primary)

                Text("Hold for 0.6 seconds. Moving more than 12 points cancels.")
                    .font(DemoType.caption)
                    .foregroundStyle(.secondary)

                Text(state.isPressing ? "Keep holding..." : "Hold to confirm")
                    .font(DemoType.captionStrong)
                    .foregroundStyle(palette.accentInk)
                    .accessibilityIdentifier("gallery.long-press.target")
                    .accessibilityHint("Press and hold to add one confirmation")
                    .frame(height: 44)
                    .frame(maxWidth: .infinity)
                    .background(state.isPressing ? palette.accentWashStrong : palette.accentWash)
                    .cornerRadius(DemoMetrics.radiusSM)
                    .onLongPressGesture(
                        minimumDuration: 0.6,
                        maximumDistance: 12,
                        perform: { state.confirmationCount += 1 },
                        onPressingChanged: { state.isPressing = $0 }
                    )

                HStack(spacing: DemoMetrics.s3) {
                    Text(state.status)
                        .font(DemoType.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("gallery.long-press.status")

                    Spacer(minLength: 0)

                    DemoButton("Confirm once") {
                        state.confirmationCount += 1
                    }
                    .accessibilityHint("Alternative to pressing and holding")
                    .accessibilityIdentifier("gallery.long-press.confirm")

                    DemoButton("Reset counter") {
                        state.confirmationCount = 0
                    }
                    .accessibilityIdentifier("gallery.long-press.reset")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("gallery.long-press-showcase")
    }
}
