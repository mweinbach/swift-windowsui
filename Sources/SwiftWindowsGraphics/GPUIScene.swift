import SwiftWindowsCore

// MARK: - GPUI Scene

/// A GPU-ready scene composed of typed primitive arrays organized into layers.
/// Layer boundaries are inserted when the primitive type changes to preserve
/// correct z-ordering while enabling batched instanced rendering.
public struct GPUIScene: Equatable, Sendable {
    /// Background clear color for the frame.
    public var clearColor: Color

    /// Ordered layers of primitives drawn front-to-back.
    public var layers: [GPUILayer]

    public init(clearColor: Color = .black, layers: [GPUILayer] = [GPUILayer()]) {
        self.clearColor = clearColor
        self.layers = layers
    }

    /// Appends a new empty layer.
    public mutating func pushLayer() {
        layers.append(GPUILayer())
    }

    /// The last layer, creating one if `layers` is empty.
    public var currentLayer: GPUILayer {
        get {
            layers.last ?? GPUILayer()
        }
        set {
            if layers.isEmpty {
                layers.append(newValue)
            } else {
                layers[layers.count - 1] = newValue
            }
        }
    }
}

/// A single rendering layer containing typed arrays of GPU primitives.
public struct GPUILayer: Equatable, Sendable {
    public var shadows: [ShadowPrimitive]
    public var quads: [QuadPrimitive]
    public var glyphs: [GlyphPrimitive]
    public var images: [ImagePrimitive]

    public init(
        shadows: [ShadowPrimitive] = [],
        quads: [QuadPrimitive] = [],
        glyphs: [GlyphPrimitive] = [],
        images: [ImagePrimitive] = []
    ) {
        self.shadows = shadows
        self.quads = quads
        self.glyphs = glyphs
        self.images = images
    }

    /// Whether this layer has no primitives at all.
    public var isEmpty: Bool {
        shadows.isEmpty && quads.isEmpty && glyphs.isEmpty && images.isEmpty
    }
}
