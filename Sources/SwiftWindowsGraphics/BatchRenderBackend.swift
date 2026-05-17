import SwiftWindowsCore

/// Protocol for renderers that consume GPUIScene (batched rendering).
///
/// This sits alongside the existing ``RenderBackend`` protocol. A batch
/// renderer groups primitives by type and issues fewer, larger draw calls
/// instead of one draw per command. Concrete implementations (e.g. the
/// D3D11BatchRenderer) will conform to both ``RenderBackend``
/// and ``BatchRenderBackend``.
@MainActor
public protocol BatchRenderBackend: AnyObject {
    /// Human-readable name shown in debug overlays.
    var backendDisplayName: String { get }

    /// Attach to a platform window surface.
    func attach(to surface: SurfaceDescriptor) throws

    /// Handle surface resize.
    func resize(to size: IntSize) throws

    /// Bind any scene-owned resources needed before rendering.
    func bindResources(for scene: GPUIScene)

    /// Render a complete GPUIScene.
    func render(scene: GPUIScene) throws
}

public extension BatchRenderBackend {
    func bindResources(for scene: GPUIScene) {}
}
