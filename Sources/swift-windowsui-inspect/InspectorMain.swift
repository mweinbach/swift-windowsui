import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsRendererD3D11
import SwiftWindowsUI

@main
struct SwiftWindowsUIInspector {
    @MainActor
    static func main() {
        let textCapabilities = TextSystem.capabilities()
        let renderBackend = DefaultRenderBackendFactory.make()
        let batchBackend = DefaultRenderBackendFactory.makeBatchBackend()

        let runtime = makeSampleRuntime()
        let frame = runtime.renderFrame()
        let bridgedScene = runtime.renderScene()
        let paintedScene = ScenePainter.paint(
            root: runtime.root,
            clearColor: runtime.clearColor,
            surfaceSize: runtime.root.frame.size
        )
        let clipProbeScene = GPUIScene(from: makeClipProbeFrame(), surfaceSize: Size(width: 240, height: 180))
        let commandCounts = CommandCounts(frame.commands)

        print("Swift Windows UI Inspector")
        print("Render backend: \(renderBackend.backendStatusDescription)")
        print("Batch backend: \(batchBackend?.backendDisplayName ?? "unavailable")")
        print("Text backend: \(textCapabilities.renderingLabel)")
        print("RenderFrame commands: \(frame.commands.count)")
        print("  fillRect: \(commandCounts.fillRect)")
        print("  drawBitmap: \(commandCounts.drawBitmap)")
        print("  fillPath: \(commandCounts.fillPath)")
        print("  strokePath: \(commandCounts.strokePath)")
        print("  applyBlur: \(commandCounts.applyBlur)")
        print("  drawText: \(commandCounts.drawText)")
        print("  clip ops: \(commandCounts.clipOperations)")
        print("GPUIScene bridge: \(bridgedScene.layers.count) layers, \(bridgedScene.primitiveCount) primitives")
        print("ScenePainter batch: \(paintedScene.layers.count) layers, \(paintedScene.primitiveCount) primitives")
        print("  quads: \(paintedScene.totalQuads)")
        print("  shadows: \(paintedScene.totalShadows)")
        print("  glyphs: \(paintedScene.totalGlyphs)")
        print("  images: \(paintedScene.totalImages)")
        print("Clip stack probe: \(formatClip(clipProbeScene.layers.first?.quads.first?.clipRect))")
    }
}

@MainActor
private func makeSampleRuntime() -> RetainedViewRuntime {
    let title = Controls.label(
        "WINSWIFTUI INSPECT",
        color: Color(red: 0.96, green: 0.98, blue: 1.0, alpha: 1.0),
        scale: 2.4,
        weight: .bold,
        alignment: .leading,
        lineBreakMode: .truncateTail,
        maximumNumberOfLines: 1
    )
    let subtitle = Controls.label(
        "RENDERFRAME AND BATCH SCENE DIAGNOSTICS",
        color: Color(red: 0.60, green: 0.70, blue: 0.82, alpha: 1.0),
        scale: 1.6,
        alignment: .leading,
        lineBreakMode: .truncateTail,
        maximumNumberOfLines: 1
    )
    let card = ViewNode(
        frame: Rect(x: 20, y: 20, width: 340, height: 128),
        backgroundGradient: LinearGradient(
            startColor: Color(red: 0.18, green: 0.24, blue: 0.34, alpha: 0.92),
            endColor: Color(red: 0.08, green: 0.11, blue: 0.18, alpha: 0.96)
        ),
        borderColor: Color(red: 0.85, green: 0.92, blue: 1.0, alpha: 0.24),
        borderWidth: 1,
        shadowColor: Color(red: 0.02, green: 0.04, blue: 0.08, alpha: 0.22),
        shadowOffset: Point(x: 0, y: 12),
        shadowSpread: 10,
        cornerRadius: 18,
        layoutMode: .stack(
            .vertical(
                spacing: 8,
                padding: EdgeInsets(top: 18, leading: 20, bottom: 18, trailing: 20),
                alignment: .leading
            )
        ),
        isHitTestVisible: false,
        children: [title, subtitle]
    )
    let root = ViewNode(
        frame: Rect(x: 0, y: 0, width: 380, height: 180),
        backgroundColor: Color(red: 0.06, green: 0.08, blue: 0.12, alpha: 1.0),
        isHitTestVisible: false,
        children: [card]
    )
    return RetainedViewRuntime(
        clearColor: Color(red: 0.06, green: 0.08, blue: 0.12, alpha: 1.0),
        root: root,
        displayScale: 1.0
    )
}

private struct CommandCounts {
    var fillRect = 0
    var drawBitmap = 0
    var fillPath = 0
    var strokePath = 0
    var applyBlur = 0
    var drawText = 0
    var clipOperations = 0

    init(_ commands: [RenderCommand]) {
        for command in commands {
            switch command {
            case .fillRect:
                fillRect += 1
            case .drawBitmap:
                drawBitmap += 1
            case .fillPath:
                fillPath += 1
            case .strokePath:
                strokePath += 1
            case .applyBlur:
                applyBlur += 1
            case .drawText:
                drawText += 1
            case .pushClip, .popClip:
                clipOperations += 1
            }
        }
    }
}

private func makeClipProbeFrame() -> RenderFrame {
    RenderFrame(
        clearColor: .black,
        commands: [
            .pushClip(ClipCommand(shape: .rect(Rect(x: 0, y: 0, width: 120, height: 120), cornerRadius: 0))),
            .pushClip(ClipCommand(
                shape: .rect(Rect(x: 80, y: 40, width: 90, height: 80), cornerRadius: 0),
                operation: .replace
            )),
            .fillRect(FillRectCommand(
                rect: Rect(x: 0, y: 0, width: 240, height: 180),
                color: Color(red: 0.45, green: 0.74, blue: 0.98, alpha: 1.0),
                clipRect: Rect(x: 100, y: 50, width: 80, height: 80)
            )),
            .popClip,
            .popClip,
        ]
    )
}

private func formatClip(_ clip: (Float, Float, Float, Float)?) -> String {
    guard let clip else {
        return "none"
    }

    return "x=\(clip.0) y=\(clip.1) w=\(clip.2) h=\(clip.3)"
}

private extension GPUIScene {
    var totalQuads: Int {
        layers.reduce(0) { $0 + $1.quads.count }
    }

    var totalShadows: Int {
        layers.reduce(0) { $0 + $1.shadows.count }
    }

    var totalGlyphs: Int {
        layers.reduce(0) { $0 + $1.glyphs.count }
    }

    var totalImages: Int {
        layers.reduce(0) { $0 + $1.images.count }
    }
}
