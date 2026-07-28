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

    /// Releases every resource this backend acquired for its surface and
    /// returns it to the pre-attach state.
    ///
    /// The counterpart to ``attach(to:)``: a GPU backend holds a swap chain
    /// that pins its HWND, plus a device, pipeline objects, atlases and
    /// caches that nothing else in the process can release. Callers must
    /// invoke this when the window closes and before handing the same
    /// surface to a different backend, since flip-model presentation is
    /// exclusive per window. Detaching an unattached backend is a no-op,
    /// and a detached backend must be re-attachable.
    func detach()
}

extension BatchRenderBackend {
    public func bindResources(for scene: GPUIScene) {}

    /// Backends that own no platform resources (software rasterizers, test
    /// fakes) inherit a no-op teardown.
    public func detach() {}
}
