#if canImport(SwiftUI)
    import SwiftUI
#else
    import WinSwiftUI
#endif

/// A static, shared-source gallery sample. Gray shapes show the complete path
/// behind each colored selection; the last fill deliberately selects no path.
public struct DemoPartialTrimSample: View {
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Static partial trim")
                .font(.headline)

            HStack(alignment: .top, spacing: 16) {
                quarterStroke(title: "Wide 0...0.25", width: 160, height: 56)
                quarterStroke(title: "Tall 0...0.25", width: 56, height: 160)
                curveStroke
            }

            HStack(alignment: .top, spacing: 16) {
                fillSample(title: "Full 0...1", from: 0, to: 1)
                fillSample(title: "Half 0...0.5", from: 0, to: 0.5)
                fillSample(title: "Empty 0.5...0.5", from: 0.5, to: 0.5)
            }
        }
        .padding(20)
    }

    private func quarterStroke(title: String, width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.caption).lineLimit(1)
            ZStack {
                Rectangle().trim(from: 0, to: 1)
                    .stroke(Color.gray.opacity(0.35), lineWidth: 6)
                Rectangle().trim(from: 0, to: 0.25)
                    .stroke(Color.cyan, lineWidth: 6)
            }
            .frame(width: width, height: height)
            .frame(width: 176, height: 176)
        }
    }

    private var curveStroke: some View {
        VStack(spacing: 8) {
            Text("Curve 0...0.5").font(.caption).lineLimit(1)
            ZStack {
                DemoTrimCurve().trim(from: 0, to: 1)
                    .stroke(Color.gray.opacity(0.35), lineWidth: 6)
                DemoTrimCurve().trim(from: 0, to: 0.5)
                    .stroke(Color.orange, lineWidth: 6)
            }
            .frame(width: 160, height: 96)
            .frame(width: 176, height: 176)
        }
    }

    private func fillSample(title: String, from: CGFloat, to: CGFloat) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.caption).lineLimit(1)
            ZStack {
                Rectangle().fill(Color.gray.opacity(0.18))
                Rectangle().trim(from: from, to: to).fill(Color.mint)
            }
            .frame(width: 160, height: 64)
        }
        .frame(width: 176)
    }
}

private struct DemoTrimCurve: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control: CGPoint(x: rect.midX, y: rect.minY))
        return path
    }
}
