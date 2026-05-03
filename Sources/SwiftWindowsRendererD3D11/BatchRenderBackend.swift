import SwiftWindowsCore
import SwiftWindowsGraphics

/// Protocol for renderers that consume GPUIScene (batched rendering).
///
/// This sits alongside the existing ``RenderBackend`` protocol. A batch
/// renderer groups primitives by type and issues fewer, larger draw calls
/// instead of one draw per command. `D3D11BatchRenderer` conforms to both
/// ``RenderBackend`` and ``BatchRenderBackend``: frame callers can use the
/// normal renderer-neutral path, while tools can still pass `GPUIScene`
/// directly when they want to inspect or stress the typed primitive path.
@MainActor
public protocol BatchRenderBackend: AnyObject {
    /// Human-readable name shown in debug overlays.
    var backendDisplayName: String { get }

    /// Attach to a platform window surface.
    func attach(to surface: SurfaceDescriptor) throws

    /// Handle surface resize.
    func resize(to size: IntSize) throws

    /// Render a complete GPUIScene.
    func render(scene: GPUIScene) throws
}
