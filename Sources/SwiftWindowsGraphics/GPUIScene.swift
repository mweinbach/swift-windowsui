import SwiftWindowsCore

/// A GPUI-style scene representing a frame as a stack of ordered layers,
/// each containing batched GPU primitives for instanced rendering.
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
}

/// A single rendering layer containing primitives grouped by type.
/// Within a layer, primitives are drawn in a fixed order:
/// shadows -> quads -> images -> glyphs.
public struct GPUILayer: Equatable, Sendable {
    public var shadows: [ShadowPrimitive] = []
    public var quads: [QuadPrimitive] = []
    public var glyphs: [GlyphPrimitive] = []
    public var images: [ImagePrimitive] = []

    public init() {}
}
