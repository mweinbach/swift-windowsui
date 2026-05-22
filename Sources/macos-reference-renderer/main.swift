// macOS-only reference renderer.
//
// Builds SwiftUI views using Apple's SwiftUI on macOS and saves PNG
// snapshots to `artifacts/macos-reference/`. The output is the *gold
// reference* against which Windows WinSwiftUI snapshots can be
// compared visually and numerically.
//
// This target intentionally has zero dependency on the Windows-only
// modules (SwiftWindowsUI, WinSwiftUI, SwiftWindowsRendererD3D11)
// so it can build on a clean macOS toolchain. The Windows build
// gracefully compiles a stub that explains why nothing happens.
//
// Run on macOS:
//   swift run macos-reference-renderer
//
// Output artifacts/macos-reference/{button-regular,toggle-on,
// slider-mid,text-body,system-colors,stack-default-spacing}.png

#if os(macOS)

    import AppKit
    import Foundation
    import SwiftUI

    // MARK: - Reference scenes

    private struct ButtonRegular: View {
        var body: some View {
            Button("OK") {}.padding(20).background(Color.white)
        }
    }

    private struct ToggleOn: View {
        @State private var on = true
        var body: some View {
            Toggle("Enabled", isOn: $on).toggleStyle(.switch).labelsHidden().padding(20)
                .background(Color.white)
        }
    }

    private struct SliderMid: View {
        @State private var value = 0.5
        var body: some View {
            Slider(value: $value).frame(width: 200).padding(20).background(Color.white)
        }
    }

    private struct TextBody: View {
        var body: some View {
            Text("Body 17 pt").font(.body).padding(20).background(Color.white)
        }
    }

    private struct SystemColors: View {
        private let palette: [(String, Color)] = [
            ("red", .red), ("orange", .orange), ("yellow", .yellow),
            ("green", .green), ("mint", .mint), ("teal", .teal),
            ("cyan", .cyan), ("blue", .blue), ("indigo", .indigo),
            ("purple", .purple), ("pink", .pink), ("brown", .brown),
            ("gray", .gray),
        ]
        var body: some View {
            HStack(spacing: 4) {
                ForEach(palette, id: \.0) { _, color in
                    Rectangle().fill(color).frame(width: 32, height: 32)
                }
            }
            .padding(20).background(Color.white)
        }
    }

    private struct StackDefaultSpacing: View {
        var body: some View {
            VStack {
                Text("Row 1")
                Text("Row 2")
                Text("Row 3")
            }
            .padding(20).background(Color.white)
        }
    }

    // MARK: - Rendering helper

    @MainActor
    private func render<V: View>(_ view: V, to file: URL, size: CGSize) throws {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()

        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw NSError(
                domain: "macos-reference-renderer", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "bitmap allocation failed"])
        }
        bitmap.size = host.bounds.size
        host.cacheDisplay(in: host.bounds, to: bitmap)

        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(
                domain: "macos-reference-renderer", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "PNG encoding failed"])
        }
        try png.write(to: file)
    }

    // MARK: - Driver

    @MainActor
    private func main() {
        let fileManager = FileManager.default
        let cwd = fileManager.currentDirectoryPath
        let outputDir = URL(fileURLWithPath: cwd)
            .appendingPathComponent("artifacts")
            .appendingPathComponent("macos-reference")
        do {
            try fileManager.createDirectory(at: outputDir, withIntermediateDirectories: true)
        } catch {
            FileHandle.standardError.write(
                Data("failed to create \(outputDir.path): \(error)\n".utf8))
            exit(1)
        }

        struct Scene {
            let name: String
            let size: CGSize
            let view: AnyView
        }

        let scenes: [Scene] = [
            Scene(
                name: "button-regular", size: CGSize(width: 120, height: 64),
                view: AnyView(ButtonRegular())),
            Scene(
                name: "toggle-on", size: CGSize(width: 120, height: 64),
                view: AnyView(ToggleOn())),
            Scene(
                name: "slider-mid", size: CGSize(width: 260, height: 64),
                view: AnyView(SliderMid())),
            Scene(
                name: "text-body", size: CGSize(width: 200, height: 64),
                view: AnyView(TextBody())),
            Scene(
                name: "system-colors", size: CGSize(width: 520, height: 80),
                view: AnyView(SystemColors())),
            Scene(
                name: "stack-default-spacing", size: CGSize(width: 200, height: 120),
                view: AnyView(StackDefaultSpacing())),
        ]

        var failures = 0
        for scene in scenes {
            let file = outputDir.appendingPathComponent("\(scene.name).png")
            do {
                try render(scene.view, to: file, size: scene.size)
                print("wrote \(file.path)")
            } catch {
                FileHandle.standardError.write(
                    Data("failed to render \(scene.name): \(error)\n".utf8))
                failures += 1
            }
        }
        if failures > 0 { exit(1) }
    }

    Task { @MainActor in
        main()
        exit(0)
    }
    RunLoop.main.run()

#else

    import Foundation

    FileHandle.standardError.write(
        Data(
            """
            macos-reference-renderer is macOS-only — it imports SwiftUI / \
            AppKit and produces PNG snapshots of canonical reference scenes \
            for cross-platform parity comparison. Run this on a macOS host \
            (or a macos-15 GitHub Actions runner) to generate \
            artifacts/macos-reference/*.png.
            """.utf8))
    exit(2)

#endif
