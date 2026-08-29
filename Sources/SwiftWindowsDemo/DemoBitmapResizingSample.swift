import Foundation

#if canImport(SwiftUI)
    import SwiftUI
#else
    import WinSwiftUI
#endif

/// The demo owns its images, so every consuming executable uses the same
/// SwiftPM resource bundle rather than looking in its working directory.
enum DemoBitmapResources {
    static var bundle: Bundle { .module }
}

/// A small same-source example, also used by the offscreen gallery. These
/// owned pixel patterns make fixed corners and incomplete tiles easy to see.
public struct DemoBitmapResizingSample: View {
    public enum Mode: String, CaseIterable, Hashable, Sendable {
        case cappedStretch
        case tile
        case aspectFit
    }

    private let mode: Mode
    private var caps: EdgeInsets { EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4) }

    public init(_ mode: Mode) {
        self.mode = mode
    }

    @ViewBuilder
    public var body: some View {
        switch mode {
        case .cappedStretch:
            Image("demo-bitmap-caps", bundle: DemoBitmapResources.bundle)
                .resizable(capInsets: caps, resizingMode: .stretch)
                .accessibilityLabel("Bitmap with fixed four point corners")
                .accessibilityIdentifier("gallery.bitmap.capped-stretch")
                .frame(width: 96, height: 96)
        case .tile:
            Image("demo-bitmap-tile", bundle: DemoBitmapResources.bundle)
                .resizable(resizingMode: .tile)
                .accessibilityLabel("Repeating bitmap with partial edge tiles")
                .accessibilityIdentifier("gallery.bitmap.tile")
                .frame(width: 96, height: 96)
        case .aspectFit:
            // Both proposal dimensions are finite. The 24 by 16 source fits
            // as 96 by 64 inside this square; the caps remain four points.
            Image("demo-bitmap-caps", bundle: DemoBitmapResources.bundle)
                .resizable(capInsets: caps, resizingMode: .tile)
                .scaledToFit()
                .accessibilityLabel("Capped bitmap fitted inside a square")
                .accessibilityIdentifier("gallery.bitmap.aspect-fit")
                .frame(width: 96, height: 96)
                .background(Color.gray.opacity(0.15))
        }
    }
}

struct DemoBitmapResizingShowcase: View {
    var body: some View {
        DemoCard(padding: DemoMetrics.s3) {
            VStack(alignment: .leading, spacing: DemoMetrics.s3) {
                Text("Bitmap images")
                    .font(DemoType.cardTitle)
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)

                Text("Shared resources, fixed corners, and repeating tiles")
                    .font(DemoType.caption)
                    .foregroundStyle(.secondary)

                HStack(alignment: .top, spacing: DemoMetrics.s4) {
                    sample(.cappedStretch, title: "Cap insets")
                    sample(.tile, title: "Tiling")
                    sample(.aspectFit, title: "Aspect fit")
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sample(_ mode: DemoBitmapResizingSample.Mode, title: String) -> some View {
        VStack(alignment: .leading, spacing: DemoMetrics.s2) {
            DemoBitmapResizingSample(mode)
            Text(title)
                .font(DemoType.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 96, alignment: .leading)
    }
}
