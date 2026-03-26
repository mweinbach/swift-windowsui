import SwiftWindowsCore

// MARK: - Quad Primitive

/// A rounded rectangle with optional gradient fill, designed for direct upload
/// to a D3D11 structured buffer. All fields are `Float` for GPU compatibility.
/// Total: 20 floats = 80 bytes (divisible by 16).
@frozen
public struct QuadPrimitive: Equatable, Sendable {
    // Position & size (pixels)
    public var x: Float
    public var y: Float
    public var width: Float
    public var height: Float
    // Corner rounding
    public var cornerRadius: Float
    // Gradient start color (premultiplied alpha)
    public var startR: Float
    public var startG: Float
    public var startB: Float
    public var startA: Float
    // Gradient end color (premultiplied alpha)
    public var endR: Float
    public var endG: Float
    public var endB: Float
    public var endA: Float
    // 0 = vertical, 1 = horizontal
    public var gradientAxis: Float
    // Clip bounds
    public var clipX: Float
    public var clipY: Float
    public var clipWidth: Float
    public var clipHeight: Float
    // Padding to reach 80 bytes (20 floats)
    public var _pad0: Float
    public var _pad1: Float

    public init(
        x: Float = 0, y: Float = 0, width: Float = 0, height: Float = 0,
        cornerRadius: Float = 0,
        startR: Float = 0, startG: Float = 0, startB: Float = 0, startA: Float = 1,
        endR: Float = 0, endG: Float = 0, endB: Float = 0, endA: Float = 1,
        gradientAxis: Float = 0,
        clipX: Float = 0, clipY: Float = 0, clipWidth: Float = 0, clipHeight: Float = 0
    ) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
        self.startR = startR
        self.startG = startG
        self.startB = startB
        self.startA = startA
        self.endR = endR
        self.endG = endG
        self.endB = endB
        self.endA = endA
        self.gradientAxis = gradientAxis
        self.clipX = clipX
        self.clipY = clipY
        self.clipWidth = clipWidth
        self.clipHeight = clipHeight
        self._pad0 = 0
        self._pad1 = 0
    }

    public static var byteSize: Int { MemoryLayout<Self>.size }
}

// MARK: - Glyph Primitive

/// A single glyph from a font atlas, designed for direct upload to a D3D11
/// structured buffer. Total: 16 floats = 64 bytes (divisible by 16).
@frozen
public struct GlyphPrimitive: Equatable, Sendable {
    // Screen destination
    public var screenX: Float
    public var screenY: Float
    public var screenW: Float
    public var screenH: Float
    // UV coordinates in the atlas texture
    public var atlasU0: Float
    public var atlasV0: Float
    public var atlasU1: Float
    public var atlasV1: Float
    // Text color
    public var colorR: Float
    public var colorG: Float
    public var colorB: Float
    public var colorA: Float
    // Clip bounds
    public var clipX: Float
    public var clipY: Float
    public var clipWidth: Float
    public var clipHeight: Float

    public init(
        screenX: Float = 0, screenY: Float = 0, screenW: Float = 0, screenH: Float = 0,
        atlasU0: Float = 0, atlasV0: Float = 0, atlasU1: Float = 0, atlasV1: Float = 0,
        colorR: Float = 1, colorG: Float = 1, colorB: Float = 1, colorA: Float = 1,
        clipX: Float = 0, clipY: Float = 0, clipWidth: Float = 0, clipHeight: Float = 0
    ) {
        self.screenX = screenX
        self.screenY = screenY
        self.screenW = screenW
        self.screenH = screenH
        self.atlasU0 = atlasU0
        self.atlasV0 = atlasV0
        self.atlasU1 = atlasU1
        self.atlasV1 = atlasV1
        self.colorR = colorR
        self.colorG = colorG
        self.colorB = colorB
        self.colorA = colorA
        self.clipX = clipX
        self.clipY = clipY
        self.clipWidth = clipWidth
        self.clipHeight = clipHeight
    }

    public static var byteSize: Int { MemoryLayout<Self>.size }
}

// MARK: - Image Primitive

/// A texture-mapped quad, designed for direct upload to a D3D11 structured
/// buffer. Total: 16 fields = 64 bytes (divisible by 16).
@frozen
public struct ImagePrimitive: Equatable, Sendable {
    // Screen destination
    public var screenX: Float
    public var screenY: Float
    public var screenW: Float
    public var screenH: Float
    // UV rect in source texture
    public var uvX: Float
    public var uvY: Float
    public var uvW: Float
    public var uvH: Float
    // Opacity
    public var opacity: Float
    // Clip bounds
    public var clipX: Float
    public var clipY: Float
    public var clipWidth: Float
    public var clipHeight: Float
    // Which texture to bind
    public var textureID: Int32
    // Padding to reach 64 bytes (16 x 4-byte fields)
    public var _pad0: Float
    public var _pad1: Float

    public init(
        screenX: Float = 0, screenY: Float = 0, screenW: Float = 0, screenH: Float = 0,
        uvX: Float = 0, uvY: Float = 0, uvW: Float = 1, uvH: Float = 1,
        opacity: Float = 1,
        clipX: Float = 0, clipY: Float = 0, clipWidth: Float = 0, clipHeight: Float = 0,
        textureID: Int32 = 0
    ) {
        self.screenX = screenX
        self.screenY = screenY
        self.screenW = screenW
        self.screenH = screenH
        self.uvX = uvX
        self.uvY = uvY
        self.uvW = uvW
        self.uvH = uvH
        self.opacity = opacity
        self.clipX = clipX
        self.clipY = clipY
        self.clipWidth = clipWidth
        self.clipHeight = clipHeight
        self.textureID = textureID
        self._pad0 = 0
        self._pad1 = 0
    }

    public static var byteSize: Int { MemoryLayout<Self>.size }
}

// MARK: - Shadow Primitive

/// A soft shadow rectangle, designed for direct upload to a D3D11 structured
/// buffer. Total: 12 floats = 48 bytes (divisible by 16).
@frozen
public struct ShadowPrimitive: Equatable, Sendable {
    // Shadow rect
    public var x: Float
    public var y: Float
    public var width: Float
    public var height: Float
    // Corner rounding
    public var cornerRadius: Float
    // Shadow color
    public var colorR: Float
    public var colorG: Float
    public var colorB: Float
    public var colorA: Float
    // Blur radius
    public var blurRadius: Float
    // Shadow offset
    public var offsetX: Float
    public var offsetY: Float

    public init(
        x: Float = 0, y: Float = 0, width: Float = 0, height: Float = 0,
        cornerRadius: Float = 0,
        colorR: Float = 0, colorG: Float = 0, colorB: Float = 0, colorA: Float = 0.5,
        blurRadius: Float = 4,
        offsetX: Float = 0, offsetY: Float = 0
    ) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
        self.colorR = colorR
        self.colorG = colorG
        self.colorB = colorB
        self.colorA = colorA
        self.blurRadius = blurRadius
        self.offsetX = offsetX
        self.offsetY = offsetY
    }

    public static var byteSize: Int { MemoryLayout<Self>.size }
}
