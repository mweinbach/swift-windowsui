import Foundation
import SwiftWindowsCore
import SwiftWindowsDemo
import SwiftWindowsGraphics
import WinSwiftUI

@main
struct SwiftWindowsUISnapshotTool {
    @MainActor
    static func main() throws {
        let options = try SnapshotOptions.parse(CommandLine.arguments.dropFirst())
        let model = DemoDashboardModel()
        model.selectedScreen = options.screen
        // `--appearance` is what makes light mode renderable at all: without
        // it there was no way to produce a light-mode snapshot, so the fact
        // that control chrome ignored `colorScheme` could not be seen.
        let view = DemoRootView(model: model).preferredColorScheme(options.appearance)
        let snapshot = WinSwiftUIRendererSnapshotter.snapshot(
            of: view,
            size: IntSize(width: Int32(options.width), height: Int32(options.height)),
            displayScale: options.displayScale,
            // The window is in the appearance too, not just its content:
            // the page backdrop behind the app comes from here.
            colorScheme: options.appearance
        )

        let bitmap: BitmapSurface
        let backendName: String

        switch options.backend {
        case .rawScene:
            bitmap = GPUIRawSceneRasterizer.rasterize(snapshot.scene, size: snapshot.size)
            backendName = "raw-scene"
        case .rawFrame:
            bitmap = GPUIRawSceneRasterizer.rasterize(snapshot.frame, size: snapshot.size)
            backendName = "raw-frame"
        case .cpuBatch:
            let renderer = CPUBatchRenderer()
            try renderer.attach(
                to: SurfaceDescriptor(
                    windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 1)!)!,
                    pixelSize: snapshot.size,
                    scaleFactor: options.displayScale
                ))
            try renderer.render(scene: snapshot.scene)
            bitmap = try renderer.lastRenderedBitmap.unwrapOrThrow(SnapshotError.missingBitmap)
            backendName = "cpu-batch"
        }

        let outputURL = options.outputURL
        let format = options.format

        switch format {
        case .png:
            try bitmap.writePNG(to: outputURL)
        case .bmp:
            try writeBGRA32BMP(bitmap, to: outputURL)
        }

        print("Snapshot=\(outputURL.path)")
        print("Backend=\(backendName)")
        print("Mode=\(options.mode.rawValue)")
        print("Screen=\(options.screen.rawValue)")
        print("Appearance=\(options.appearance == .light ? "light" : "dark")")
        print("Format=\(format.rawValue)")
        print("Size=\(bitmap.width)x\(bitmap.height)")
        print("ScenePrimitives=\(snapshot.scene.primitiveCount)")
        print("FrameCommands=\(snapshot.frame.commands.count)")
        print("SceneLayers=\(snapshot.scene.layers.count)")

        if options.generateHTMLReport {
            let reportURL = outputURL.deletingPathExtension().appendingPathExtension("html")
            let report = SnapshotHTMLReport(
                snapshot: snapshot,
                bitmapURL: outputURL,
                backendName: backendName,
                width: Int(bitmap.width),
                height: Int(bitmap.height)
            )
            try report.write(to: reportURL)
            print("Report=\(reportURL.path)")
        }
    }
}

// MARK: - Options

private struct SnapshotOptions {
    var outputURL: URL
    var width: Int
    var height: Int
    var displayScale: Double
    var mode: SnapshotMode
    var backend: SnapshotBackend
    var format: SnapshotFormat
    var generateHTMLReport: Bool
    var screen: DemoScreen
    var appearance: ColorScheme

    static func parse<S: Sequence>(_ arguments: S) throws -> SnapshotOptions where S.Element == String {
        var output = URL(fileURLWithPath: "artifacts/demo-screenshot.bmp")
        var width = 1280
        var height = 720
        var displayScale = 1.0
        var mode = SnapshotMode.scene
        var backend: SnapshotBackend? = nil
        var format: SnapshotFormat? = nil
        var generateHTMLReport = false
        var screen = DemoScreen.dashboard
        var appearance = ColorScheme.dark

        var normalizedArguments = Array(arguments)
        if normalizedArguments.first == "--" {
            normalizedArguments.removeFirst()
        }

        var iterator = normalizedArguments.makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--output", "-o":
                output = URL(fileURLWithPath: try requireValue(after: argument, from: &iterator))
            case "--width":
                width = try parsePositiveInt(try requireValue(after: argument, from: &iterator), name: argument)
            case "--height":
                height = try parsePositiveInt(try requireValue(after: argument, from: &iterator), name: argument)
            case "--scale":
                displayScale = try parsePositiveDouble(
                    try requireValue(after: argument, from: &iterator), name: argument)
            case "--mode":
                let value = try requireValue(after: argument, from: &iterator)
                guard let parsed = SnapshotMode(rawValue: value) else {
                    throw SnapshotError.invalidArgument("--mode must be scene or frame.")
                }
                mode = parsed
            case "--backend":
                let value = try requireValue(after: argument, from: &iterator)
                guard let parsed = SnapshotBackend(rawValue: value) else {
                    throw SnapshotError.invalidArgument("--backend must be raw-scene, raw-frame, or cpu-batch.")
                }
                backend = parsed
            case "--format":
                let value = try requireValue(after: argument, from: &iterator)
                guard let parsed = SnapshotFormat(rawValue: value) else {
                    throw SnapshotError.invalidArgument("--format must be bmp or png.")
                }
                format = parsed
            case "--html-report":
                generateHTMLReport = true
            case "--screen":
                let value = try requireValue(after: argument, from: &iterator)
                guard let parsed = DemoScreen(rawValue: value) else {
                    throw SnapshotError.invalidArgument("--screen must be dashboard, settings, or data.")
                }
                screen = parsed
            case "--appearance":
                let value = try requireValue(after: argument, from: &iterator)
                switch value {
                case "light":
                    appearance = .light
                case "dark":
                    appearance = .dark
                default:
                    throw SnapshotError.invalidArgument("--appearance must be light or dark.")
                }
            case "--help", "-h":
                throw SnapshotError.help
            default:
                throw SnapshotError.invalidArgument("Unknown argument: \(argument)")
            }
        }

        let resolvedBackend = backend ?? mode.defaultBackend

        let resolvedFormat: SnapshotFormat
        if let explicit = format {
            resolvedFormat = explicit
        } else {
            let ext = output.pathExtension.lowercased()
            if ext == "png" {
                resolvedFormat = .png
            } else if ext == "bmp" {
                resolvedFormat = .bmp
            } else {
                output.deletePathExtension()
                output.appendPathExtension("bmp")
                resolvedFormat = .bmp
            }
        }

        return SnapshotOptions(
            outputURL: output,
            width: width,
            height: height,
            displayScale: displayScale,
            mode: mode,
            backend: resolvedBackend,
            format: resolvedFormat,
            generateHTMLReport: generateHTMLReport,
            screen: screen,
            appearance: appearance
        )
    }

    private static func requireValue(after argument: String, from iterator: inout IndexingIterator<[String]>) throws
        -> String
    {
        guard let value = iterator.next(), !value.hasPrefix("--") else {
            throw SnapshotError.invalidArgument("Missing value after \(argument).")
        }
        return value
    }

    private static func parsePositiveInt(_ value: String, name: String) throws -> Int {
        guard let parsed = Int(value), parsed > 0 else {
            throw SnapshotError.invalidArgument("\(name) must be a positive integer.")
        }
        return parsed
    }

    private static func parsePositiveDouble(_ value: String, name: String) throws -> Double {
        guard let parsed = Double(value), parsed > 0 else {
            throw SnapshotError.invalidArgument("\(name) must be a positive number.")
        }
        return parsed
    }
}

private enum SnapshotMode: String {
    case scene
    case frame

    var defaultBackend: SnapshotBackend {
        switch self {
        case .scene:
            return .rawScene
        case .frame:
            return .rawFrame
        }
    }
}

private enum SnapshotBackend: String {
    case rawScene = "raw-scene"
    case rawFrame = "raw-frame"
    case cpuBatch = "cpu-batch"
}

private enum SnapshotFormat: String {
    case bmp
    case png
}

private enum SnapshotError: Error, CustomStringConvertible {
    case help
    case invalidArgument(String)
    case missingBitmap

    var description: String {
        switch self {
        case .help:
            return """
                Usage: swift-windowsui-snapshot [options]

                Options:
                  -o, --output <path>     Output image path (default: artifacts/demo-screenshot.bmp)
                  --width <px>            Width in pixels (default: 1280)
                  --height <px>           Height in pixels (default: 720)
                  --scale <factor>        Display scale (default: 1.0)
                  --mode <scene|frame>    Snapshot mode (default: scene)
                  --backend <raw-scene|raw-frame|cpu-batch>
                                          Rendering backend (default: raw-scene)
                  --format <bmp|png>      Output format (default: inferred from output extension, else bmp)
                  --html-report           Generate an HTML inspection report
                  --screen <dashboard|settings|data>
                                          Demo tab to render (default: dashboard)
                  --appearance <light|dark>
                                          Color scheme to render in (default: dark)
                  -h, --help              Show this help message
                """
        case .invalidArgument(let message):
            return message
        case .missingBitmap:
            return "Renderer did not produce a bitmap."
        }
    }
}

// MARK: - HTML Report

private struct SnapshotHTMLReport {
    let snapshot: WinSwiftUIRenderSnapshot
    let bitmapURL: URL
    let backendName: String
    let width: Int
    let height: Int

    @MainActor
    func write(to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let bmpName = bitmapURL.lastPathComponent
        let html = """
            <!DOCTYPE html>
            <html lang="en">
            <head>
                <meta charset="UTF-8">
                <title>SwiftWindowsUI Snapshot Report</title>
                <style>
                    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; margin: 24px; background: #0f1419; color: #e6edf3; }
                    h1 { font-size: 20px; margin-bottom: 8px; }
                    .subtitle { color: #8b949e; font-size: 13px; margin-bottom: 24px; }
                    .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }
                    .card { background: #161b22; border: 1px solid #30363d; border-radius: 8px; padding: 16px; }
                    .card h2 { font-size: 14px; margin: 0 0 12px; color: #58a6ff; }
                    .metric { display: flex; justify-content: space-between; padding: 6px 0; border-bottom: 1px solid #21262d; font-size: 13px; }
                    .metric:last-child { border-bottom: none; }
                    .metric-key { color: #8b949e; }
                    .metric-val { font-family: ui-monospace, SFMono-Regular, monospace; }
                    img { max-width: 100%; border-radius: 4px; border: 1px solid #30363d; background: #000; image-rendering: pixelated; }
                    .image-card { grid-column: 1 / -1; }
                    .image-card h2 { margin-bottom: 12px; }
                </style>
            </head>
            <body>
                <h1>SwiftWindowsUI Snapshot Report</h1>
                <div class="subtitle">\(backendName) &middot; \(width)&times;\(height) &middot; \(snapshot.scene.primitiveCount) primitives</div>
                <div class="grid">
                    <div class="card">
                        <h2>Scene Metadata</h2>
                        <div class="metric"><span class="metric-key">Layers</span><span class="metric-val">\(snapshot.scene.layers.count)</span></div>
                        <div class="metric"><span class="metric-key">Primitives</span><span class="metric-val">\(snapshot.scene.primitiveCount)</span></div>
                        <div class="metric"><span class="metric-key">Paint Records</span><span class="metric-val">\(snapshot.scene.paintRecords.count)</span></div>
                        <div class="metric"><span class="metric-key">Glyph Atlas</span><span class="metric-val">\(snapshot.scene.glyphAtlas == nil ? "none" : "present")</span></div>
                        <div class="metric"><span class="metric-key">Pixel Glyph Atlas</span><span class="metric-val">\(snapshot.scene.pixelGlyphAtlas == nil ? "none" : "present")</span></div>
                        <div class="metric"><span class="metric-key">Image Resources</span><span class="metric-val">\(snapshot.scene.imageResources.count)</span></div>
                    </div>
                    <div class="card">
                        <h2>Frame Metadata</h2>
                        <div class="metric"><span class="metric-key">Commands</span><span class="metric-val">\(snapshot.frame.commands.count)</span></div>
                        <div class="metric"><span class="metric-key">Clear Color</span><span class="metric-val">rgba(\(Int(snapshot.frame.clearColor.red*255)), \(Int(snapshot.frame.clearColor.green*255)), \(Int(snapshot.frame.clearColor.blue*255)), \(Int(snapshot.frame.clearColor.alpha*255)))</span></div>
                        <div class="metric"><span class="metric-key">Display Scale</span><span class="metric-val">\(snapshot.displayScale)</span></div>
                        <div class="metric"><span class="metric-key">Logical Size</span><span class="metric-val">\(snapshot.size.width)&times;\(snapshot.size.height)</span></div>
                    </div>
                    <div class="card image-card">
                        <h2>Rendered Output</h2>
                        <img src="\(bmpName)" alt="Snapshot" width="\(width)" height="\(height)">
                    </div>
                </div>
            </body>
            </html>
            """
        try html.write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - BMP Writer

private func writeBGRA32BMP(_ bitmap: BitmapSurface, to url: URL) throws {
    let width = max(1, Int(bitmap.width))
    let height = max(1, Int(bitmap.height))
    let bytesPerPixel = 4
    let rowBytes = width * bytesPerPixel
    let sourceBytesPerRow = max(rowBytes, Int(bitmap.bytesPerRow))
    let pixelDataSize = rowBytes * height
    let fileHeaderSize = 14
    let dibHeaderSize = 40
    let pixelOffset = fileHeaderSize + dibHeaderSize
    let fileSize = pixelOffset + pixelDataSize

    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )

    var data = Data()
    data.reserveCapacity(fileSize)
    data.append(contentsOf: [0x42, 0x4d])
    data.appendUInt32LE(UInt32(fileSize))
    data.appendUInt16LE(0)
    data.appendUInt16LE(0)
    data.appendUInt32LE(UInt32(pixelOffset))
    data.appendUInt32LE(UInt32(dibHeaderSize))
    data.appendInt32LE(Int32(width))
    data.appendInt32LE(Int32(height))
    data.appendUInt16LE(1)
    data.appendUInt16LE(32)
    data.appendUInt32LE(0)
    data.appendUInt32LE(UInt32(pixelDataSize))
    data.appendInt32LE(2835)
    data.appendInt32LE(2835)
    data.appendUInt32LE(0)
    data.appendUInt32LE(0)

    for row in stride(from: height - 1, through: 0, by: -1) {
        let offset = row * sourceBytesPerRow
        let end = offset + rowBytes
        if end <= bitmap.pixels.count {
            data.append(bitmap.pixels[offset..<end])
        } else {
            data.append(contentsOf: Array(repeating: 0, count: rowBytes))
        }
    }

    try data.write(to: url, options: .atomic)
}

extension Data {
    fileprivate mutating func appendUInt16LE(_ value: UInt16) {
        append(contentsOf: [UInt8(value & 0xff), UInt8((value >> 8) & 0xff)])
    }

    fileprivate mutating func appendUInt32LE(_ value: UInt32) {
        append(contentsOf: [
            UInt8(value & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 24) & 0xff),
        ])
    }

    fileprivate mutating func appendInt32LE(_ value: Int32) {
        appendUInt32LE(UInt32(bitPattern: value))
    }
}

extension Optional {
    fileprivate func unwrapOrThrow(_ error: Error) throws -> Wrapped {
        guard let value = self else { throw error }
        return value
    }
}
