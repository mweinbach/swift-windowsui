import SwiftWindowsCore
import SwiftWindowsGraphics

/// Headless rendering utility that produces a ``BitmapSurface`` from a view tree
/// without requiring a window, GPU, or display server.  Useful for:
///
/// 1. **Pixel-perfect unit tests** — assert exact colors at exact coordinates.
/// 2. **Visual regression baselines** — write BMP files for human inspection.
/// 3. **CI / headless validation** — ``CPUBatchRenderer`` works without D3D11.
///
/// Example:
/// ```swift
/// let bitmap = ViewSnapshot.rasterize(
///     components: { UI.label("Hello") },
///     size: Size(width: 200, height: 100)
/// )
/// XCTAssertEqual(bitmap.pixelColor(atX: 10, y: 10), .white)
/// ```
@MainActor
public enum ViewSnapshot {

    /// Rasterize a single ``Component`` to a bitmap at the given logical size.
    public static func rasterize(
        component: Component,
        size: Size,
        clearColor: Color = .black,
        displayScale: Double = 1.0
    ) throws -> BitmapSurface {
        let runtime = RetainedViewRuntime(clearColor: clearColor, displayScale: displayScale)
        let host = ComponentHost(runtime: runtime)
        host.setContent(component)
        runtime.setRootSize(IntSize(width: Int32(size.width), height: Int32(size.height)))
        return try rasterize(runtime: runtime, size: size)
    }

    /// Rasterize an array of components (using ``ComponentBuilder`` syntax).
    public static func rasterize(
        @ComponentBuilder components: @escaping () -> [Component],
        size: Size,
        clearColor: Color = .black,
        displayScale: Double = 1.0
    ) throws -> BitmapSurface {
        let runtime = RetainedViewRuntime(clearColor: clearColor, displayScale: displayScale)
        let host = ComponentHost(runtime: runtime)
        host.setComponents(components)
        runtime.setRootSize(IntSize(width: Int32(size.width), height: Int32(size.height)))
        return try rasterize(runtime: runtime, size: size)
    }

    /// Rasterize an existing ``RetainedViewRuntime`` whose tree has already been built.
    public static func rasterize(
        runtime: RetainedViewRuntime,
        size: Size
    ) throws -> BitmapSurface {
        let scene = runtime.renderScene()
        let renderer = CPUBatchRenderer()
        try renderer.resize(to: IntSize(width: Int32(size.width), height: Int32(size.height)))
        try renderer.render(scene: scene)
        guard let bitmap = renderer.lastRenderedBitmap else {
            throw ViewSnapshotError.noBitmapProduced
        }
        return bitmap
    }
}

public enum ViewSnapshotError: Error, CustomStringConvertible {
    case noBitmapProduced

    public var description: String {
        switch self {
        case .noBitmapProduced:
            return "CPUBatchRenderer did not produce a bitmap after rendering."
        }
    }
}
