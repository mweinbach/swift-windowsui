import SwiftWindowsCore
import SwiftWindowsGraphics

public struct BatchPrimitiveCounts: Equatable, Sendable {
    public var shadows: Int
    public var quads: Int
    public var glyphs: Int
    public var images: Int

    public init(shadows: Int = 0, quads: Int = 0, glyphs: Int = 0, images: Int = 0) {
        self.shadows = shadows
        self.quads = quads
        self.glyphs = glyphs
        self.images = images
    }

    public var total: Int {
        shadows + quads + glyphs + images
    }
}

public struct BatchPrimitiveCapabilities: Equatable, Sendable {
    public var shadows: Bool
    public var quads: Bool
    public var glyphs: Bool
    public var images: Bool

    public init(shadows: Bool, quads: Bool, glyphs: Bool, images: Bool) {
        self.shadows = shadows
        self.quads = quads
        self.glyphs = glyphs
        self.images = images
    }

    public var supportedPrimitiveNames: [String] {
        var names: [String] = []
        if shadows { names.append("shadows") }
        if quads { names.append("quads") }
        if glyphs { names.append("glyphs") }
        if images { names.append("images") }
        return names
    }

    public var unsupportedPrimitiveNames: [String] {
        var names: [String] = []
        if !shadows { names.append("shadows") }
        if !quads { names.append("quads") }
        if !glyphs { names.append("glyphs") }
        if !images { names.append("images") }
        return names
    }

    public func supportedPrimitiveCounts(in scene: GPUIScene) -> BatchPrimitiveCounts {
        primitiveCounts(in: scene) { isSupported in
            isSupported
        }
    }

    public func unsupportedPrimitiveCounts(in scene: GPUIScene) -> BatchPrimitiveCounts {
        primitiveCounts(in: scene) { isSupported in
            !isSupported
        }
    }

    private func primitiveCounts(
        in scene: GPUIScene,
        including include: (Bool) -> Bool
    ) -> BatchPrimitiveCounts {
        var counts = BatchPrimitiveCounts()
        for layer in scene.layers {
            if include(shadows) { counts.shadows += layer.shadows.count }
            if include(quads) { counts.quads += layer.quads.count }
            if include(glyphs) { counts.glyphs += layer.glyphs.count }
            if include(images) { counts.images += layer.images.count }
        }
        return counts
    }
}

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

    /// Primitive families the concrete batch renderer can draw today.
    var primitiveCapabilities: BatchPrimitiveCapabilities { get }

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
