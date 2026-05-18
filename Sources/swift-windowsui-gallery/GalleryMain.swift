import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import WinSwiftUI

@main
struct SwiftWindowsUIGalleryTool {
    @MainActor
    static func main() throws {
        let outputDir = URL(fileURLWithPath: "artifacts/gallery")
        try FileManager.default.createDirectory(
            at: outputDir,
            withIntermediateDirectories: true
        )

        let gallerySpecs: [GallerySpec] = [
            GallerySpec(
                id: "rectangle", title: "Rectangle",
                view: AnyView(
                    Rectangle().fill(.red).frame(width: 120, height: 80)
                )),
            GallerySpec(
                id: "circle", title: "Circle",
                view: AnyView(
                    Circle().fill(.blue).frame(width: 100, height: 100)
                )),
            GallerySpec(
                id: "rounded-rect", title: "Rounded Rectangle",
                view: AnyView(
                    RoundedRectangle(cornerRadius: 20).fill(.green).frame(width: 120, height: 80)
                )),
            GallerySpec(
                id: "text", title: "Text",
                view: AnyView(
                    Text("Hello").foregroundColor(.white)
                )),
            GallerySpec(
                id: "opacity", title: "Opacity 0.5",
                view: AnyView(
                    Rectangle().fill(.white).frame(width: 100, height: 100).opacity(0.5)
                )),
            GallerySpec(
                id: "corner-radius", title: "Corner Radius",
                view: AnyView(
                    Rectangle().fill(.white).frame(width: 120, height: 120).cornerRadius(30)
                )),
            GallerySpec(
                id: "border", title: "Border",
                view: AnyView(
                    Rectangle().fill(.black).frame(width: 120, height: 120).border(.yellow, width: 4)
                )),
            GallerySpec(
                id: "shadow", title: "Shadow",
                view: AnyView(
                    Rectangle().fill(.white).frame(width: 80, height: 80).shadow(color: .white, radius: 6, x: 4, y: 4)
                )),
            GallerySpec(
                id: "rotation", title: "Rotation 45°",
                view: AnyView(
                    Rectangle().fill(.purple).frame(width: 100, height: 40).rotationEffect(.degrees(45))
                )),
            GallerySpec(
                id: "scale", title: "Scale 1.5x",
                view: AnyView(
                    Rectangle().fill(.yellow).frame(width: 60, height: 60).scaleEffect(x: 1.5, y: 1.5)
                )),
            GallerySpec(
                id: "offset", title: "Offset (20, 10)",
                view: AnyView(
                    Rectangle().fill(.yellow).frame(width: 80, height: 80).offset(x: 20, y: 10)
                )),
            GallerySpec(
                id: "padding", title: "Padding",
                view: AnyView(
                    Rectangle().fill(.white).frame(width: 80, height: 80).padding(20)
                )),
            GallerySpec(
                id: "hstack", title: "HStack",
                view: AnyView(
                    HStack(spacing: 8) {
                        Rectangle().fill(.red).frame(width: 40, height: 40)
                        Rectangle().fill(.green).frame(width: 40, height: 40)
                        Rectangle().fill(.blue).frame(width: 40, height: 40)
                    }
                )),
            GallerySpec(
                id: "vstack", title: "VStack",
                view: AnyView(
                    VStack(spacing: 8) {
                        Rectangle().fill(.red).frame(width: 40, height: 20)
                        Rectangle().fill(.green).frame(width: 40, height: 20)
                        Rectangle().fill(.blue).frame(width: 40, height: 20)
                    }
                )),
            GallerySpec(
                id: "zstack", title: "ZStack",
                view: AnyView(
                    ZStack {
                        Rectangle().fill(.red).frame(width: 100, height: 100)
                        Rectangle().fill(.blue).frame(width: 60, height: 60)
                        Rectangle().fill(.green).frame(width: 30, height: 30)
                    }
                )),
            GallerySpec(
                id: "brightness", title: "Brightness -0.5",
                view: AnyView(
                    Rectangle().fill(.white).frame(width: 100, height: 100).brightness(-0.5)
                )),
            GallerySpec(
                id: "contrast", title: "Contrast 2.0",
                view: AnyView(
                    Rectangle().fill(.gray)
                        .frame(width: 100, height: 100).contrast(1.0)
                )),
            GallerySpec(
                id: "grayscale", title: "Grayscale",
                view: AnyView(
                    Rectangle().fill(.red).frame(width: 100, height: 100).grayscale(1.0)
                )),
            GallerySpec(
                id: "hue-rotation", title: "Hue Rotation 120°",
                view: AnyView(
                    Rectangle().fill(.red).frame(width: 100, height: 100).hueRotation(.degrees(120))
                )),
            GallerySpec(
                id: "color-invert", title: "Color Invert",
                view: AnyView(
                    Rectangle().fill(.red).frame(width: 100, height: 100).colorInvert()
                )),
            GallerySpec(
                id: "blur", title: "Blur",
                view: AnyView(
                    Rectangle().fill(.white).frame(width: 80, height: 80).blur(radius: 4)
                )),
            GallerySpec(
                id: "blend-multiply", title: "Blend Multiply",
                view: AnyView(
                    ZStack {
                        Rectangle().fill(.red).frame(width: 80, height: 80)
                        Rectangle().fill(.blue).frame(width: 80, height: 80).blendMode(.multiply)
                    }
                )),
            GallerySpec(
                id: "blend-screen", title: "Blend Screen",
                view: AnyView(
                    ZStack {
                        Rectangle().fill(.red).frame(width: 80, height: 80)
                        Rectangle().fill(.blue).frame(width: 80, height: 80).blendMode(.screen)
                    }
                )),
            GallerySpec(
                id: "blend-plus", title: "Blend Plus Lighter",
                view: AnyView(
                    ZStack {
                        Rectangle().fill(.green).frame(width: 80, height: 80)
                        Rectangle().fill(.red).frame(width: 80, height: 80).blendMode(.plusLighter)
                    }
                )),
            GallerySpec(
                id: "clip-shape", title: "ClipShape RoundedRect",
                view: AnyView(
                    Rectangle().fill(.white).frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 30))
                )),
            GallerySpec(
                id: "drawing-group", title: "DrawingGroup + Opacity",
                view: AnyView(
                    ZStack {
                        Rectangle().fill(.white).frame(width: 60, height: 60)
                        Rectangle().fill(.white).frame(width: 60, height: 60)
                    }
                    .opacity(0.5)
                    .drawingGroup()
                )),
            GallerySpec(
                id: "button", title: "Button",
                view: AnyView(
                    Button("Tap Me") {}
                        .frame(width: 100, height: 40)
                )),
            GallerySpec(
                id: "toggle", title: "Toggle",
                view: AnyView(
                    Toggle("Enabled", isOn: .constant(true))
                        .frame(width: 140, height: 40)
                )),
            GallerySpec(
                id: "slider", title: "Slider",
                view: AnyView(
                    Slider(value: .constant(0.5))
                        .frame(width: 160, height: 40)
                )),
            GallerySpec(
                id: "picker", title: "Picker",
                view: AnyView(
                    Picker("Color", selection: .constant(0)) {
                        Text("Red").tag(0)
                        Text("Green").tag(1)
                        Text("Blue").tag(2)
                    }
                    .frame(width: 160, height: 40)
                )),
            GallerySpec(
                id: "text-field", title: "TextField",
                view: AnyView(
                    TextField("Placeholder", text: .constant("Hello"))
                        .frame(width: 160, height: 40)
                        .padding(8)
                )),
            GallerySpec(
                id: "list", title: "List",
                view: AnyView(
                    List {
                        Text("Item 1")
                        Text("Item 2")
                        Text("Item 3")
                    }
                    .frame(width: 160, height: 120)
                )),
            GallerySpec(
                id: "form", title: "Form",
                view: AnyView(
                    Form {
                        TextField("Name", text: .constant(""))
                        Toggle("Active", isOn: .constant(false))
                    }
                    .frame(width: 160, height: 120)
                )),
            GallerySpec(
                id: "navigation-stack", title: "NavigationStack",
                view: AnyView(
                    NavigationStack {
                        Text("Root View")
                            .navigationTitle("Home")
                    }
                    .frame(width: 160, height: 120)
                )),
            GallerySpec(
                id: "aspect-ratio", title: "Aspect Ratio",
                view: AnyView(
                    Rectangle()
                        .fill(.red)
                        .aspectRatio(2.0, contentMode: .fit)
                        .frame(width: 160, height: 100)
                )),
            GallerySpec(
                id: "mask", title: "Mask",
                view: AnyView(
                    Rectangle()
                        .fill(.blue)
                        .frame(width: 120, height: 120)
                        .mask(
                            Circle()
                                .frame(width: 100, height: 100)
                        )
                )),
            GallerySpec(
                id: "overlay", title: "Overlay",
                view: AnyView(
                    Rectangle()
                        .fill(.green)
                        .frame(width: 100, height: 100)
                        .overlay(
                            Circle().fill(.white).frame(width: 40, height: 40),
                            alignment: .topTrailing
                        )
                )),
            GallerySpec(
                id: "background-alignment", title: "Background + Alignment",
                view: AnyView(
                    Text("A")
                        .frame(width: 60, height: 60)
                        .background(
                            Circle().fill(.red),
                            alignment: .center
                        )
                )),
            GallerySpec(
                id: "matched-geometry", title: "MatchedGeometryEffect",
                view: AnyView(
                    HStack(spacing: 20) {
                        Rectangle()
                            .fill(.blue)
                            .frame(width: 40, height: 40)
                            .matchedGeometryEffect(id: "shape", in: Namespace().wrappedValue)
                        Rectangle()
                            .fill(.blue)
                            .frame(width: 60, height: 60)
                            .matchedGeometryEffect(id: "shape2", in: Namespace().wrappedValue)
                    }
                )),
            GallerySpec(
                id: "progress-view", title: "ProgressView",
                view: AnyView(
                    ProgressView(value: 0.6)
                        .frame(width: 120, height: 40)
                )),
            GallerySpec(
                id: "stepper", title: "Stepper",
                view: AnyView(
                    Stepper(value: .constant(5), in: 0...10) {
                        Text("Count: 5")
                    }
                    .frame(width: 140, height: 40)
                )),
            GallerySpec(
                id: "menu", title: "Menu",
                view: AnyView(
                    Menu("Options") {
                        Button("Option 1") {}
                        Button("Option 2") {}
                    }
                    .frame(width: 120, height: 40)
                )),
            GallerySpec(
                id: "link", title: "Link",
                view: AnyView(
                    Link("Open", destination: URL(string: "https://example.com")!)
                        .frame(width: 100, height: 40)
                )),
            GallerySpec(
                id: "divider", title: "Divider",
                view: AnyView(
                    VStack {
                        Text("Above")
                        Divider()
                        Text("Below")
                    }
                    .frame(width: 120, height: 80)
                )),
            GallerySpec(
                id: "spacer", title: "Spacer",
                view: AnyView(
                    HStack {
                        Rectangle().fill(.red).frame(width: 30, height: 30)
                        Spacer()
                        Rectangle().fill(.blue).frame(width: 30, height: 30)
                    }
                    .frame(width: 160, height: 40)
                )),
            GallerySpec(
                id: "geometry-reader", title: "GeometryReader",
                view: AnyView(
                    GeometryReader { proxy in
                        Text("\(Int(proxy.size.width))x\(Int(proxy.size.height))")
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                    .frame(width: 120, height: 80)
                )),
            GallerySpec(
                id: "scroll-view", title: "ScrollView",
                view: AnyView(
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(0..<5) { i in
                                Rectangle()
                                    .fill(i % 2 == 0 ? .red : .blue)
                                    .frame(width: 140, height: 30)
                            }
                        }
                    }
                    .frame(width: 160, height: 100)
                )),
            GallerySpec(
                id: "for-each", title: "ForEach",
                view: AnyView(
                    VStack(spacing: 4) {
                        ForEach(0..<4) { i in
                            Rectangle()
                                .fill(i % 2 == 0 ? .green : .yellow)
                                .frame(width: 140, height: 20)
                        }
                    }
                )),
            GallerySpec(
                id: "if-else", title: "Conditional View",
                view: AnyView(
                    VStack(spacing: 8) {
                        if true {
                            Rectangle().fill(.red).frame(width: 80, height: 30)
                        } else {
                            Rectangle().fill(.blue).frame(width: 80, height: 30)
                        }
                    }
                )),
            GallerySpec(
                id: "group", title: "Group",
                view: AnyView(
                    Group {
                        Rectangle().fill(.red).frame(width: 60, height: 30)
                        Rectangle().fill(.green).frame(width: 60, height: 30)
                        Rectangle().fill(.blue).frame(width: 60, height: 30)
                    }
                )),
            GallerySpec(
                id: "transition", title: "Transition",
                view: AnyView(
                    Text("Hello")
                        .transition(.opacity)
                        .frame(width: 80, height: 40)
                )),
            GallerySpec(
                id: "animation", title: "Animation",
                view: AnyView(
                    Rectangle()
                        .fill(.red)
                        .frame(width: 80, height: 80)
                        .animation(.easeInOut, value: 1)
                )),
            GallerySpec(
                id: "canvas-fill-color", title: "Canvas (color fill)",
                view: AnyView(
                    Canvas { ctx, size in
                        var path = Path()
                        path.moveTo(Point(x: size.width / 2, y: 10))
                        path.lineTo(Point(x: size.width - 10, y: size.height - 10))
                        path.lineTo(Point(x: 10, y: size.height - 10))
                        path.close()
                        ctx.fill(path, with: .color(Color(red: 0.95, green: 0.55, blue: 0.20, alpha: 1)))
                    }
                    .frame(width: 160, height: 140)
                )),
            GallerySpec(
                id: "canvas-stroke", title: "Canvas (stroke)",
                view: AnyView(
                    Canvas { ctx, size in
                        var path = Path()
                        path.moveTo(Point(x: 10, y: size.height / 2))
                        let step = (size.width - 20) / 10
                        for index in 1...10 {
                            let x = 10 + Double(index) * step
                            let y = size.height / 2 + (index % 2 == 0 ? -30.0 : 30.0)
                            path.lineTo(Point(x: x, y: y))
                        }
                        ctx.stroke(
                            path,
                            with: .color(Color(red: 0.42, green: 0.78, blue: 0.92, alpha: 1)),
                            lineWidth: 3
                        )
                    }
                    .frame(width: 160, height: 140)
                )),
            GallerySpec(
                id: "canvas-gradient", title: "Canvas (gradient)",
                view: AnyView(
                    Canvas { ctx, size in
                        ctx.fill(
                            Rect(x: 10, y: 10, width: size.width - 20, height: size.height - 20),
                            with: .linearGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 0.20, green: 0.30, blue: 0.95, alpha: 1),
                                    Color(red: 0.80, green: 0.40, blue: 0.55, alpha: 1),
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    }
                    .frame(width: 160, height: 140)
                )),
        ]

        var entries: [GalleryEntry] = []
        let size = IntSize(width: 200, height: 200)
        let displayScale = 1.0

        for spec in gallerySpecs {
            let snapshot = WinSwiftUIRendererSnapshotter.snapshot(
                of: spec.view,
                size: size,
                displayScale: displayScale,
                clearColor: .black
            )
            let bitmap = GPUIRawSceneRasterizer.rasterize(snapshot.scene, size: snapshot.size)
            let filename = "\(spec.id).png"
            let url = outputDir.appendingPathComponent(filename)
            try bitmap.writePNG(to: url)

            entries.append(
                GalleryEntry(
                    id: spec.id,
                    title: spec.title,
                    filename: filename,
                    primitiveCount: snapshot.scene.primitiveCount,
                    layerCount: snapshot.scene.layers.count
                ))
            print("Rendered \(spec.id)")
        }

        let indexURL = outputDir.appendingPathComponent("index.html")
        try writeGalleryHTML(entries: entries, to: indexURL)
        print("Gallery=\(indexURL.path)")
        print("Entries=\(entries.count)")
    }
}

// MARK: - Gallery Specs

private struct GallerySpec {
    let id: String
    let title: String
    let view: AnyView
}

// MARK: - Gallery Entry

private struct GalleryEntry {
    let id: String
    let title: String
    let filename: String
    let primitiveCount: Int
    let layerCount: Int
}

// MARK: - HTML Report

private func writeGalleryHTML(entries: [GalleryEntry], to url: URL) throws {
    let cards = entries.map { entry in
        """
        <div class="card">
            <div class="image-wrapper">
                <img src="\(entry.filename)" alt="\(entry.title)" width="200" height="200">
            </div>
            <div class="info">
                <div class="title">\(entry.title)</div>
                <div class="meta">\(entry.primitiveCount) primitives · \(entry.layerCount) layers</div>
            </div>
        </div>
        """
    }.joined(separator: "\n")

    let html = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <title>SwiftWindowsUI Gallery</title>
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
                    margin: 24px;
                    background: #0f1419;
                    color: #e6edf3;
                }
                h1 { font-size: 22px; margin-bottom: 6px; }
                .subtitle { color: #8b949e; font-size: 13px; margin-bottom: 24px; }
                .grid {
                    display: grid;
                    grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
                    gap: 16px;
                }
                .card {
                    background: #161b22;
                    border: 1px solid #30363d;
                    border-radius: 8px;
                    overflow: hidden;
                }
                .image-wrapper {
                    background: #000;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    padding: 8px;
                }
                img {
                    display: block;
                    border-radius: 4px;
                    border: 1px solid #30363d;
                    image-rendering: pixelated;
                }
                .info {
                    padding: 10px 12px;
                    border-top: 1px solid #30363d;
                }
                .title {
                    font-size: 13px;
                    font-weight: 600;
                    margin-bottom: 4px;
                }
                .meta {
                    font-size: 11px;
                    color: #8b949e;
                    font-family: ui-monospace, SFMono-Regular, monospace;
                }
            </style>
        </head>
        <body>
            <h1>SwiftWindowsUI Gallery</h1>
            <div class="subtitle">\(entries.count) snapshots &middot; 200&times;200 &middot; raw-scene backend</div>
            <div class="grid">
                \(cards)
            </div>
        </body>
        </html>
        """
    try html.write(to: url, atomically: true, encoding: .utf8)
}
