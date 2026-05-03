import SwiftWindowsCore

// MARK: - GPUILayer

/// A rendering layer containing typed, contiguous primitive arrays.
/// Draw order within a layer: shadows, quads, glyphs, images.
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

    /// Total primitive count in this layer, useful for renderer diagnostics.
    public var primitiveCount: Int {
        shadows.count + quads.count + glyphs.count + images.count
    }

    public var isEmpty: Bool {
        primitiveCount == 0
    }
}

// MARK: - GPUIScene

public struct GPUISceneImageResource: Equatable, Sendable {
    public var id: Int32
    public var bitmap: BitmapSurface

    public init(id: Int32, bitmap: BitmapSurface) {
        self.id = id
        self.bitmap = bitmap
    }
}

/// Top-level GPUI-style scene container that organizes primitives by type into
/// contiguous arrays within layers. This structure replaces the flat
/// `[RenderCommand]` list with typed arrays suitable for instanced draw calls.
public struct GPUIScene: Equatable, Sendable {
    public var clearColor: Color
    public var layers: [GPUILayer]
    public var imageResources: [GPUISceneImageResource]

    public init(clearColor: Color = .black) {
        self.clearColor = clearColor
        self.layers = [GPUILayer()]
        self.imageResources = []
    }

    /// Total primitive count across all layers.
    public var primitiveCount: Int {
        layers.reduce(0) { $0 + $1.primitiveCount }
    }

    public var totalPrimitiveCount: Int {
        primitiveCount
    }

    // MARK: - Layer management

    /// Push a new empty layer onto the stack.
    @discardableResult
    public mutating func pushLayer() -> Int {
        layers.append(GPUILayer())
        return layers.count - 1
    }

    // MARK: - Primitive insertion (appends to last layer)

    public mutating func addQuad(_ quad: QuadPrimitive) {
        layers[layers.count - 1].quads.append(quad)
    }

    public mutating func addGlyph(_ glyph: GlyphPrimitive) {
        layers[layers.count - 1].glyphs.append(glyph)
    }

    public mutating func addImage(_ image: ImagePrimitive) {
        layers[layers.count - 1].images.append(image)
    }

    public mutating func addShadow(_ shadow: ShadowPrimitive) {
        layers[layers.count - 1].shadows.append(shadow)
    }

    @discardableResult
    public mutating func addImageResource(_ bitmap: BitmapSurface) -> Int32 {
        let id = Int32(imageResources.count)
        imageResources.append(GPUISceneImageResource(id: id, bitmap: bitmap))
        return id
    }

    public func imageResource(for textureID: Int32) -> GPUISceneImageResource? {
        guard textureID >= 0 else {
            return nil
        }

        let index = Int(textureID)
        guard imageResources.indices.contains(index) else {
            return nil
        }

        let resource = imageResources[index]
        return resource.id == textureID ? resource : nil
    }
}
