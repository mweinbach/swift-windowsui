import SwiftWindowsCore

/// A single rendering layer containing typed primitive arrays.
/// Layers are used to enforce draw-order across z-index groups.
public struct GPUILayer: Equatable, Sendable {
    public var shadows: [ShadowPrimitive] = []
    public var quads: [QuadPrimitive] = []
    public var glyphs: [GlyphPrimitive] = []
    public var images: [ImagePrimitive] = []

    public init() {}

    /// True when the layer contains no primitives at all.
    public var isEmpty: Bool {
        shadows.isEmpty && quads.isEmpty && glyphs.isEmpty && images.isEmpty
    }
}

/// A complete scene produced by the paint phase, ready for GPU submission.
/// Contains a clear color and one or more layers of typed primitive arrays.
public struct GPUIScene: Equatable, Sendable {
    public var clearColor: Color
    public var layers: [GPUILayer]

    public init(clearColor: Color = .black, layers: [GPUILayer] = [GPUILayer()]) {
        self.clearColor = clearColor
        self.layers = layers
    }

    /// Appends a new empty layer to the scene.
    public mutating func pushLayer() {
        layers.append(GPUILayer())
    }

    /// Total number of primitives across all layers.
    public var totalPrimitiveCount: Int {
        layers.reduce(0) { $0 + $1.shadows.count + $1.quads.count + $1.glyphs.count + $1.images.count }
    }
}
