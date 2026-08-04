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
    /// - Parameters:
    ///   - colorScheme: the appearance the snapshot window is in. This is
    ///     the *window's* appearance, as `NSWindow.effectiveAppearance` is
    ///     on macOS: it seeds the root environment and picks the backdrop.
    ///     A fixed navy clear colour meant a light-mode render still had a
    ///     dark page behind it.
    ///   - clearColor: overrides the appearance's window background.
    public static func snapshot<V: View>(
        of view: V,
        size: IntSize = IntSize(width: 1280, height: 720),
        displayScale: Double = 1,
        colorScheme: ColorScheme = .dark,
        clearColor: Color? = nil,
        timestamp: Double = 0
    ) -> WinSwiftUIRenderSnapshot {
        let palette = ControlPalette.resolve(colorScheme: colorScheme)
        let resolvedClearColor = clearColor ?? palette.windowBackground
        let runtime = RetainedViewRuntime(
            clearColor: resolvedClearColor, root: ViewNode(), displayScale: displayScale)
        runtime.setRootSize(size)
        // Icons rasterize eagerly at build time; point them at this render's
        // scale (1 for the deterministic screenshot path), then restore.
        let previousIconDisplayScale = NativeTextRenderer.defaultIconDisplayScale
        NativeTextRenderer.defaultIconDisplayScale = displayScale
        defer { NativeTextRenderer.defaultIconDisplayScale = previousIconDisplayScale }

        let context = ViewBuildContext(
            canvasSizeProvider: {
                Size(width: Double(size.width), height: Double(size.height))
            },
            invalidateHandler: {},
            environmentValuesProvider: {
                EnvironmentValues(
                    colorScheme: colorScheme,
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
