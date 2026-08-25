#if canImport(SwiftUI)
    import SwiftUI
#else
    import WinSwiftUI
#endif

/// A compact, interactive tour of the scene primitives behind the demo.
///
/// The cards stay neutral: color belongs to small samples and controls, never
/// another full-width saturated surface competing with the dashboard hero.
struct DemoGalleryVisualShowcase: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: DemoDashboardModel
    var compact: Bool = false

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: DemoMetrics.s3) {
            HStack(alignment: .center, spacing: DemoMetrics.s2) {
                VStack(alignment: .leading, spacing: DemoMetrics.s1) {
                    Text("Visual rendering")
                        .font(DemoType.section)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text("Gradients, materials, motion, and typography")
                        .font(DemoType.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                HStack(alignment: .center, spacing: DemoMetrics.s1 + 2) {
                    DemoStatusDot(palette.success)

                    Text(model.rendererIdentity.displayName)
                        .font(DemoType.badge)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, DemoMetrics.s2)
                .frame(height: DemoMetrics.chipHeight)
                .background(palette.surface2)
                .cornerRadius(DemoMetrics.radiusSM)
            }

            if compact {
                DemoGalleryGradientCard(model: model, compact: true)
                DemoGalleryMaterialCard(compact: true)
                DemoGalleryMotionCard(model: model, compact: true)
                DemoGalleryTypographyCard(model: model, compact: true)
            } else {
                HStack(alignment: .top, spacing: DemoMetrics.s3) {
                    DemoGalleryGradientCard(model: model, compact: false)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    DemoGalleryMaterialCard(compact: false)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(alignment: .top, spacing: DemoMetrics.s3) {
                    DemoGalleryMotionCard(model: model, compact: false)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    DemoGalleryTypographyCard(model: model, compact: false)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DemoGalleryCardHeader: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: DemoMetrics.s1) {
            HStack(alignment: .center, spacing: DemoMetrics.s2) {
                DemoRowGlyph(systemImage, size: 14)

                Text(title)
                    .font(DemoType.cardTitle)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }

            Text(subtitle)
                .font(DemoType.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct DemoGalleryGradientCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: DemoDashboardModel
    @ObservedObject var galleryState: DemoGalleryState

    let compact: Bool

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }
    private var sampleWidth: CGFloat { compact ? 76 : 56 }

    init(model: DemoDashboardModel, compact: Bool) {
        self.model = model
        self.compact = compact
        self.galleryState = model.galleryState
    }

    var body: some View {
        DemoCard(padding: DemoMetrics.s3) {
            VStack(alignment: .leading, spacing: DemoMetrics.s3) {
                DemoGalleryCardHeader(
                    title: "Gradient lab",
                    subtitle: "Three independently rendered paint families",
                    systemImage: "rectangle.grid.3x2"
                )

                HStack(alignment: .top, spacing: DemoMetrics.s2) {
                    DemoGalleryGradientSample(title: "Linear", width: sampleWidth) {
                        RoundedRectangle(cornerRadius: DemoMetrics.radiusMD)
                            .fill(
                                LinearGradient(
                                    colors: primaryColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }

                    DemoGalleryGradientSample(title: "Radial", width: sampleWidth) {
                        RoundedRectangle(cornerRadius: DemoMetrics.radiusMD)
                            .fill(
                                RadialGradient(
                                    colors: radialColors,
                                    center: .topLeading,
                                    startRadius: 0,
                                    endRadius: sampleWidth
                                )
                            )
                    }

                    DemoGalleryGradientSample(title: "Angular", width: sampleWidth) {
                        RoundedRectangle(cornerRadius: DemoMetrics.radiusMD)
                            .fill(
                                AngularGradient(
                                    colors: angularColors,
                                    center: .center,
                                    startAngle: .degrees(-90),
                                    endAngle: .degrees(270)
                                )
                            )
                    }

                    Spacer(minLength: 0)
                }

                Spacer(minLength: 0)

                DemoButton("Shuffle colors") {
                    withAnimation(model.animationsEnabled ? .easeInOut(duration: 0.3) : nil) {
                        galleryState.colorsAreReversed.toggle()
                    }
                    model.performAction("Shuffled gradient colors")
                }
            }
            .frame(maxWidth: .infinity, minHeight: compact ? 162 : 172, alignment: .topLeading)
        }
    }

    private var primaryColors: [Color] {
        galleryState.colorsAreReversed
            ? [DemoSignature.layoutStop, palette.accentInk]
            : [palette.accentInk, DemoSignature.layoutStop]
    }

    private var radialColors: [Color] {
        galleryState.colorsAreReversed
            ? [DemoSignature.animationStop, palette.warning]
            : [palette.warning, DemoSignature.animationStop]
    }

    private var angularColors: [Color] {
        galleryState.colorsAreReversed
            ? [palette.accentInk, palette.success, DemoSignature.inputStop, palette.accentInk]
            : [palette.accentInk, DemoSignature.inputStop, palette.success, palette.accentInk]
    }
}

private struct DemoGalleryGradientSample<Sample: View>: View {
    let title: String
    let width: CGFloat
    let sample: Sample

    init(title: String, width: CGFloat, @ViewBuilder sample: () -> Sample) {
        self.title = title
        self.width = width
        self.sample = sample()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DemoMetrics.s1 + 2) {
            sample
                .frame(width: width, height: DemoMetrics.s12)
                .accessibilityLabel("\(title) gradient sample")

            Text(title)
                .font(DemoType.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: width, alignment: .leading)
    }
}

private struct DemoGalleryMaterialCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let compact: Bool

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }

    var body: some View {
        DemoCard(padding: DemoMetrics.s3) {
            VStack(alignment: .leading, spacing: DemoMetrics.s3) {
                DemoGalleryCardHeader(
                    title: "Glass & materials",
                    subtitle: "Live backdrop blur with layered clipping",
                    systemImage: "rectangle.split.2x1"
                )

                ZStack(alignment: .leading) {
                    palette.surface2

                    RoundedRectangle(cornerRadius: DemoMetrics.radiusMD)
                        .fill(
                            LinearGradient(
                                colors: [palette.accentInk, DemoSignature.animationStop],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 56)
                        .offset(x: 12, y: -8)

                    RoundedRectangle(cornerRadius: DemoMetrics.radiusMD)
                        .fill(
                            RadialGradient(
                                colors: [palette.success, DemoSignature.inputStop],
                                center: .topTrailing,
                                startRadius: 0,
                                endRadius: 64
                            )
                        )
                        .frame(width: 64, height: 56)
                        .offset(x: 92, y: 9)

                    VStack(alignment: .leading, spacing: DemoMetrics.s1) {
                        Text("Backdrop blur")
                            .font(DemoType.controlLabelStrong)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text("Translucent material")
                            .font(DemoType.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, DemoMetrics.s2)
                    .frame(width: 144, height: 46, alignment: .leading)
                    .background(.thinMaterial)
                    .cornerRadius(DemoMetrics.radiusMD)
                    .offset(x: 38)
                }
                .frame(height: 84)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cornerRadius(DemoMetrics.radiusMD)

                Spacer(minLength: 0)

                HStack(alignment: .center, spacing: DemoMetrics.s2) {
                    DemoStatusDot(palette.success)

                    Text("Backdrop pass active")
                        .font(DemoType.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(height: DemoMetrics.controlHeight)
            }
            .frame(maxWidth: .infinity, minHeight: compact ? 162 : 172, alignment: .topLeading)
        }
    }
}

private struct DemoGalleryMotionCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: DemoDashboardModel
    @ObservedObject var galleryState: DemoGalleryState

    let compact: Bool

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }

    init(model: DemoDashboardModel, compact: Bool) {
        self.model = model
        self.compact = compact
        self.galleryState = model.galleryState
    }

    var body: some View {
        DemoCard(padding: DemoMetrics.s3) {
            VStack(alignment: .leading, spacing: DemoMetrics.s3) {
                DemoGalleryCardHeader(
                    title: "Motion studio",
                    subtitle: "Retained transforms and animated state",
                    systemImage: "sparkles"
                )

                HStack(alignment: .center, spacing: DemoMetrics.s3) {
                    ZStack(alignment: .center) {
                        RoundedRectangle(cornerRadius: DemoMetrics.radiusMD)
                            .stroke(palette.strokeStrong, lineWidth: 1)
                            .frame(width: 48, height: 48)
                            .rotationEffect(.degrees(galleryState.isExpanded ? 18 : -12))

                        RoundedRectangle(cornerRadius: DemoMetrics.radiusSM)
                            .fill(palette.accentInk)
                            .frame(width: 28, height: 28)
                            .rotationEffect(.degrees(galleryState.isExpanded ? 45 : 0))
                            .scaleEffect(galleryState.isExpanded ? 1.12 : 0.88)
                            .animation(
                                model.animationsEnabled ? .easeInOut(duration: 0.35) : nil,
                                value: galleryState.isExpanded
                            )
                    }
                    .frame(width: 76, height: 76)
                    .background(palette.surface2)
                    .cornerRadius(DemoMetrics.radiusMD)

                    VStack(alignment: .leading, spacing: DemoMetrics.s1) {
                        Text(galleryState.isExpanded ? "Expanded" : "Resting")
                            .font(DemoType.bodyStrong)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text("Rotation · Scale")
                            .font(DemoType.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }

                Spacer(minLength: 0)

                DemoButton("Replay motion") {
                    withAnimation(model.animationsEnabled ? .easeInOut(duration: 0.35) : nil) {
                        galleryState.isExpanded.toggle()
                    }
                    model.performAction("Replayed rendering motion")
                }
            }
            .frame(maxWidth: .infinity, minHeight: compact ? 162 : 172, alignment: .topLeading)
        }
    }
}

private struct DemoGalleryTypographyCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: DemoDashboardModel

    let compact: Bool

    private var palette: DemoPalette { DemoPalette(colorScheme: colorScheme) }
    private var colors: [Color] { [palette.accentInk, palette.success, palette.warning, palette.danger] }

    var body: some View {
        DemoCard(padding: DemoMetrics.s3) {
            VStack(alignment: .leading, spacing: DemoMetrics.s2) {
                DemoGalleryCardHeader(
                    title: "Type & color",
                    subtitle: "Optical text sizes and semantic accents",
                    systemImage: "textformat"
                )

                HStack(alignment: .center, spacing: DemoMetrics.s2) {
                    Text("Aa")
                        .font(DemoType.screenTitle)
                        .foregroundStyle(.primary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Variable UI")
                            .font(DemoType.bodyStrong)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text("13pt regular · 14pt semibold")
                            .font(DemoType.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                HStack(alignment: .center, spacing: DemoMetrics.s2) {
                    ForEach(0..<colors.count, id: \.self) { index in
                        RoundedRectangle(cornerRadius: DemoMetrics.radiusSM)
                            .fill(colors[index])
                            .frame(width: 20, height: 20)
                    }

                    Spacer(minLength: 0)

                    Text("\(Int((model.syncProgress * 100).rounded()))%")
                        .font(DemoType.captionStrong)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                ProgressView(value: model.syncProgress)
                    .progressViewStyle(.linear)
                    .tint(palette.accentInk)
                    .frame(maxWidth: 160, alignment: .leading)

                Spacer(minLength: 0)

                DemoButton("Advance progress") {
                    withAnimation(model.animationsEnabled ? .easeInOut(duration: 0.25) : nil) {
                        model.syncProgress =
                            model.syncProgress >= 0.99 ? 0.25 : min(1, model.syncProgress + 0.2)
                    }
                    model.performAction("Advanced gallery progress")
                }
            }
            .frame(maxWidth: .infinity, minHeight: compact ? 162 : 172, alignment: .topLeading)
        }
    }
}
