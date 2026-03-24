import SwiftWindowsCore

// MARK: - GPUI Scene Types
//
// A GPUIScene is the batch-renderer-friendly scene representation inspired by
// Zed's GPUI. Instead of a sequential command list, primitives are grouped by
// type within layers so the GPU can render each type in a single batched draw
// call.

/// A complete scene ready for batch rendering. Contains an ordered list of
/// layers, each holding primitives sorted by type.
public struct GPUIScene: Equatable, Sendable {
    public var clearColor: Color
    public var layers: [GPUILayer]

    public init(clearColor: Color = .black, layers: [GPUILayer] = [GPUILayer()]) {
        self.clearColor = clearColor
        self.layers = layers
    }

    /// Append a new empty layer and return its index.
    @discardableResult
    public mutating func pushLayer() -> Int {
        layers.append(GPUILayer())
        return layers.count - 1
    }

    /// The total number of primitives across all layers.
    public var primitiveCount: Int {
        layers.reduce(0) { $0 + $1.primitiveCount }
    }
}

/// A single rendering layer. Within a layer, each primitive type is drawn in
/// order: shadows, then quads, then glyphs, then images. To interleave
/// different primitive types, use multiple layers.
public struct GPUILayer: Equatable, Sendable {
    public var shadows: [ShadowPrimitive] = []
    public var quads: [QuadPrimitive] = []
    public var glyphs: [GlyphPrimitive] = []
    public var images: [ImagePrimitive] = []

    public init() {}

    /// Total number of primitives in this layer.
    public var primitiveCount: Int {
        shadows.count + quads.count + glyphs.count + images.count
    }
}
