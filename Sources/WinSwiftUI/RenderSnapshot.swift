import SwiftWindowsCore

import SwiftWindowsGraphics

import SwiftWindowsUI

@MainActor
public struct WinSwiftUIRenderSnapshot {
    public var runtime: RetainedViewRuntime
    public var frame: RenderFrame
    public var scene: GPUIScene
    public var size: IntSize
    public var displayScale: Double

    public init(
        runtime: RetainedViewRuntime,
        frame: RenderFrame,
        scene: GPUIScene,
        size: IntSize,
        displayScale: Double
    ) {
        self.runtime = runtime
        self.frame = frame
        self.scene = scene
        self.size = size
        self.displayScale = displayScale
    }
}
@MainActor
public enum WinSwiftUIRendererSnapshotter {
    public static func snapshot<V: View>(
        of view: V,
        size: IntSize = IntSize(width: 1280, height: 720),
        displayScale: Double = 1,
        clearColor: Color = Color(red: 0.07, green: 0.10, blue: 0.14, alpha: 1.0),
        timestamp: Double = 0
    ) -> WinSwiftUIRenderSnapshot {
        let runtime = RetainedViewRuntime(clearColor: clearColor, root: ViewNode(), displayScale: displayScale)
        runtime.setRootSize(size)

        let context = ViewBuildContext(
            canvasSizeProvider: {
                Size(width: Double(size.width), height: Double(size.height))
            },
            invalidateHandler: {},
            environmentValuesProvider: {
                EnvironmentValues(
                    displayScale: displayScale,
                    pixelLength: displayScale > 0 ? 1 / displayScale : 1
                )
            }
        )
        let component = view.makeComponent(context: context)
        let host = ComponentHost(runtime: runtime)
        host.setContent(component)

        let scene = runtime.renderScene(at: timestamp)
        let frame = runtime.renderFrame(at: timestamp)
        return WinSwiftUIRenderSnapshot(
            runtime: runtime,
            frame: frame,
            scene: scene,
            size: size,
            displayScale: displayScale
        )
    }
}
