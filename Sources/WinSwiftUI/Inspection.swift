import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsUI

public struct WinSwiftUIRenderCommandCounts: Sendable, Equatable {
    public let total: Int
    public let fillRect: Int
    public let drawBitmap: Int
    public let fillPath: Int
    public let strokePath: Int
    public let drawText: Int
    public let applyBlur: Int
    public let clipOperations: Int

    init(commands: [RenderCommand]) {
        var fillRect = 0
        var drawBitmap = 0
        var fillPath = 0
        var strokePath = 0
        var drawText = 0
        var applyBlur = 0
        var clipOperations = 0

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
            case .drawText:
                drawText += 1
            case .applyBlur:
                applyBlur += 1
            case .pushClip, .popClip:
                clipOperations += 1
            }
        }

        self.total = commands.count
        self.fillRect = fillRect
        self.drawBitmap = drawBitmap
        self.fillPath = fillPath
        self.strokePath = strokePath
        self.drawText = drawText
        self.applyBlur = applyBlur
        self.clipOperations = clipOperations
    }
}

public struct WinSwiftUIInspectionSnapshot: Sendable, Equatable {
    public let nodeCount: Int
    public let textNodeCount: Int
    public let focusableNodeCount: Int
    public let hitTestVisibleNodeCount: Int
    public let hiddenNodeCount: Int
    public let maxDepth: Int
    public let rootLayoutKind: String
    public let invalidationCountDuringBuild: Int
    public let textSamples: [String]
    public let renderCommands: WinSwiftUIRenderCommandCounts
}

@MainActor
public enum WinSwiftUIInspection {
    public static func snapshot<V: View>(
        of view: V,
        size: Size = Size(width: 800, height: 600),
        displayScale: Double = 1.0,
        maximumTextSamples: Int = 8
    ) -> WinSwiftUIInspectionSnapshot {
        var invalidationCount = 0
        let root = ViewNode(
            frame: Rect(x: 0, y: 0, width: size.width, height: size.height),
            isHitTestVisible: false
        )
        let runtime = RetainedViewRuntime(root: root, displayScale: displayScale)
        let context = ViewBuildContext(
            canvasSizeProvider: { size },
            invalidateHandler: { invalidationCount += 1 }
        )
        let node = view.makeComponent(context: context).makeNode(runtime: runtime)
        root.addChild(node)
        runtime.setRootSize(IntSize(
            width: Int32(max(0, size.width.rounded())),
            height: Int32(max(0, size.height.rounded()))
        ))
        let frame = runtime.renderFrame()

        var stats = InspectionStats()
        inspect(node, depth: 0, maximumTextSamples: maximumTextSamples, stats: &stats)

        return WinSwiftUIInspectionSnapshot(
            nodeCount: stats.nodeCount,
            textNodeCount: stats.textNodeCount,
            focusableNodeCount: stats.focusableNodeCount,
            hitTestVisibleNodeCount: stats.hitTestVisibleNodeCount,
            hiddenNodeCount: stats.hiddenNodeCount,
            maxDepth: stats.maxDepth,
            rootLayoutKind: layoutKind(for: node.layoutMode),
            invalidationCountDuringBuild: invalidationCount,
            textSamples: stats.textSamples,
            renderCommands: WinSwiftUIRenderCommandCounts(commands: frame.commands)
        )
    }

    private static func inspect(
        _ node: ViewNode,
        depth: Int,
        maximumTextSamples: Int,
        stats: inout InspectionStats
    ) {
        stats.nodeCount += 1
        stats.maxDepth = max(stats.maxDepth, depth)

        if node.text != nil {
            stats.textNodeCount += 1
        }
        if let text = node.text, !text.isEmpty, stats.textSamples.count < maximumTextSamples {
            stats.textSamples.append(text)
        }
        if node.isFocusable {
            stats.focusableNodeCount += 1
        }
        if node.isHitTestVisible {
            stats.hitTestVisibleNodeCount += 1
        }
        if node.isHidden {
            stats.hiddenNodeCount += 1
        }

        for child in node.children {
            inspect(child, depth: depth + 1, maximumTextSamples: maximumTextSamples, stats: &stats)
        }
    }

    private static func layoutKind(for mode: ViewLayoutMode) -> String {
        switch mode {
        case .absolute:
            return "absolute"
        case .stack(let stack):
            switch stack.axis {
            case .vertical:
                return "stack.vertical"
            case .horizontal:
                return "stack.horizontal"
            }
        case .flex:
            return "flex"
        }
    }
}

private struct InspectionStats {
    var nodeCount = 0
    var textNodeCount = 0
    var focusableNodeCount = 0
    var hitTestVisibleNodeCount = 0
    var hiddenNodeCount = 0
    var maxDepth = 0
    var textSamples: [String] = []
}
