import Foundation
import SwiftWindowsCore

// MARK: - GPUILayer

public enum GPUIPaintPrimitiveKind: Equatable, Sendable {
    case shadow
    case quad
    case glyph
    case pixelGlyph
    case image
}

public struct GPUIPaintOperation: Equatable, Sendable {
    public var kind: GPUIPaintPrimitiveKind
    public var startIndex: Int
    public var count: Int

    public init(kind: GPUIPaintPrimitiveKind, startIndex: Int, count: Int = 1) {
        self.kind = kind
        self.startIndex = startIndex
        self.count = count
    }
}

public struct GlyphAtlasRegion: Equatable, Sendable {
    public var x: Int32
    public var y: Int32
    public var width: Int32
    public var height: Int32

    public init(x: Int32, y: Int32, width: Int32, height: Int32) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct GlyphAtlasSnapshot: Equatable, Sendable {
    public var width: Int32
    public var height: Int32
    public var pixels: Data
    public var dirtyRegion: GlyphAtlasRegion?

    public init(width: Int32, height: Int32, pixels: Data, dirtyRegion: GlyphAtlasRegion? = nil) {
        self.width = width
        self.height = height
        self.pixels = pixels
        self.dirtyRegion = dirtyRegion
    }
}

/// A rendering layer containing typed, contiguous primitive arrays.
/// `paintOperations` preserves the source paint order across primitive families
/// without forcing each family transition into its own layer.
public struct GPUILayer: Equatable, Sendable {
    public var shadows: [ShadowPrimitive]
    public var quads: [QuadPrimitive]
    public var glyphs: [GlyphPrimitive]
    public var pixelGlyphs: [GlyphPrimitive]
    public var images: [ImagePrimitive]
    public var paintOperations: [GPUIPaintOperation]

    public init(
        shadows: [ShadowPrimitive] = [],
        quads: [QuadPrimitive] = [],
        glyphs: [GlyphPrimitive] = [],
        pixelGlyphs: [GlyphPrimitive] = [],
        images: [ImagePrimitive] = [],
        paintOperations: [GPUIPaintOperation] = []
    ) {
        self.shadows = shadows
        self.quads = quads
        self.glyphs = glyphs
        self.pixelGlyphs = pixelGlyphs
        self.images = images
        self.paintOperations = paintOperations
    }

    public var primitiveCount: Int {
        shadows.count + quads.count + glyphs.count + pixelGlyphs.count + images.count
    }

    public var isEmpty: Bool {
        primitiveCount == 0
    }

    public var paintOperationCount: Int {
        paintOperations.count
    }

    mutating func addShadow(_ shadow: ShadowPrimitive) {
        let startIndex = shadows.count
        shadows.append(shadow)
        appendPaintOperation(kind: .shadow, startIndex: startIndex)
    }

    mutating func addQuad(_ quad: QuadPrimitive) {
        let startIndex = quads.count
        quads.append(quad)
        appendPaintOperation(kind: .quad, startIndex: startIndex)
    }

    mutating func addGlyph(_ glyph: GlyphPrimitive) {
        let startIndex = glyphs.count
        glyphs.append(glyph)
        appendPaintOperation(kind: .glyph, startIndex: startIndex)
    }

    mutating func addPixelGlyph(_ glyph: GlyphPrimitive) {
        let startIndex = pixelGlyphs.count
        pixelGlyphs.append(glyph)
        appendPaintOperation(kind: .pixelGlyph, startIndex: startIndex)
    }

    mutating func addImage(_ image: ImagePrimitive) {
        let startIndex = images.count
        images.append(image)
        appendPaintOperation(kind: .image, startIndex: startIndex)
    }

    private mutating func appendPaintOperation(kind: GPUIPaintPrimitiveKind, startIndex: Int) {
        guard var lastOperation = paintOperations.last else {
            paintOperations.append(GPUIPaintOperation(kind: kind, startIndex: startIndex))
            return
        }

        let expectedNextIndex = lastOperation.startIndex + lastOperation.count
        if lastOperation.kind == kind, expectedNextIndex == startIndex {
            lastOperation.count += 1
            paintOperations[paintOperations.count - 1] = lastOperation
            return
        }

        paintOperations.append(GPUIPaintOperation(kind: kind, startIndex: startIndex))
    }
}

// MARK: - GPUIScene

/// Top-level GPUI-style scene container that organizes primitives by type into
/// contiguous arrays within layers. This structure replaces the flat
/// `[RenderCommand]` list with typed arrays suitable for instanced draw calls.
public struct GPUIScene: Equatable, Sendable {
    public var clearColor: Color
    public var layers: [GPUILayer]
    public var glyphAtlas: GlyphAtlasSnapshot?
    public var pixelGlyphAtlas: GlyphAtlasSnapshot?

    public init(
        clearColor: Color = .black,
        glyphAtlas: GlyphAtlasSnapshot? = nil,
        pixelGlyphAtlas: GlyphAtlasSnapshot? = nil
    ) {
        self.clearColor = clearColor
        self.layers = [GPUILayer()]
        self.glyphAtlas = glyphAtlas
        self.pixelGlyphAtlas = pixelGlyphAtlas
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
        addQuad(quad, toLayer: layers.count - 1)
    }

    public mutating func addGlyph(_ glyph: GlyphPrimitive) {
        addGlyph(glyph, toLayer: layers.count - 1)
    }

    public mutating func addImage(_ image: ImagePrimitive) {
        addImage(image, toLayer: layers.count - 1)
    }

    public mutating func addShadow(_ shadow: ShadowPrimitive) {
        addShadow(shadow, toLayer: layers.count - 1)
    }

    public mutating func addPixelGlyph(_ glyph: GlyphPrimitive) {
        addPixelGlyph(glyph, toLayer: layers.count - 1)
    }

    public mutating func addQuad(_ quad: QuadPrimitive, toLayer layerIndex: Int) {
        layers[layerIndex].addQuad(quad)
    }

    public mutating func addGlyph(_ glyph: GlyphPrimitive, toLayer layerIndex: Int) {
        layers[layerIndex].addGlyph(glyph)
    }

    public mutating func addImage(_ image: ImagePrimitive, toLayer layerIndex: Int) {
        layers[layerIndex].addImage(image)
    }

    public mutating func addShadow(_ shadow: ShadowPrimitive, toLayer layerIndex: Int) {
        layers[layerIndex].addShadow(shadow)
    }

    public mutating func addPixelGlyph(_ glyph: GlyphPrimitive, toLayer layerIndex: Int) {
        layers[layerIndex].addPixelGlyph(glyph)
    }

    public var primitiveCount: Int {
        layers.reduce(0) { $0 + $1.primitiveCount }
    }

    public var totalPrimitiveCount: Int {
        primitiveCount
    }
}
