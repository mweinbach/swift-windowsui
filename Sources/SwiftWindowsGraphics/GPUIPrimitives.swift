/// Axis-aligned filled rectangle with optional gradient and rounded corners.
/// Layout: 80 bytes (20 x Float).
public struct QuadPrimitive: Equatable, Sendable {
    public var x: Float
    public var y: Float
    public var width: Float
    public var height: Float
    public var cornerRadius: Float
    public var startR: Float
    public var startG: Float
    public var startB: Float
    public var startA: Float
    public var endR: Float
    public var endG: Float
    public var endB: Float
    public var endA: Float
    /// 0 = vertical, 1 = horizontal.
    public var gradientAxis: Float
    public var clipX: Float
    public var clipY: Float
    public var clipWidth: Float
    public var clipHeight: Float
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
}

/// A single glyph positioned on screen with atlas UV coordinates.
/// Layout: 48 bytes (12 x Float).
public struct GlyphPrimitive: Equatable, Sendable {
    public var screenX: Float
    public var screenY: Float
    public var screenW: Float
    public var screenH: Float
    public var atlasU0: Float
    public var atlasV0: Float
    public var atlasU1: Float
    public var atlasV1: Float
    public var colorR: Float
    public var colorG: Float
    public var colorB: Float
    public var colorA: Float

    public init(
        screenX: Float = 0, screenY: Float = 0, screenW: Float = 0, screenH: Float = 0,
        atlasU0: Float = 0, atlasV0: Float = 0, atlasU1: Float = 0, atlasV1: Float = 0,
        colorR: Float = 1, colorG: Float = 1, colorB: Float = 1, colorA: Float = 1
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
    }
}

/// A textured image quad with opacity, clipping, and texture binding.
/// Layout: 64 bytes (15 x Float + 1 x Int32 = 64 bytes).
public struct ImagePrimitive: Equatable, Sendable {
    public var screenX: Float
    public var screenY: Float
    public var screenW: Float
    public var screenH: Float
    public var uvX: Float
    public var uvY: Float
    public var uvW: Float
    public var uvH: Float
    public var opacity: Float
    public var clipX: Float
    public var clipY: Float
    public var clipWidth: Float
    public var clipHeight: Float
    /// Texture slot identifier. -1 means bitmap data is handled externally.
    public var textureID: Int32
    public var _pad0: Float
    public var _pad1: Float

    public init(
        screenX: Float = 0, screenY: Float = 0, screenW: Float = 0, screenH: Float = 0,
        uvX: Float = 0, uvY: Float = 0, uvW: Float = 1, uvH: Float = 1,
        opacity: Float = 1,
        clipX: Float = 0, clipY: Float = 0, clipWidth: Float = 0, clipHeight: Float = 0,
        textureID: Int32 = -1
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
}

/// A shadow primitive for box-shadow rendering.
/// Layout: 48 bytes (12 x Float).
public struct ShadowPrimitive: Equatable, Sendable {
    public var x: Float
    public var y: Float
    public var width: Float
    public var height: Float
    public var cornerRadius: Float
    public var colorR: Float
    public var colorG: Float
    public var colorB: Float
    public var colorA: Float
    public var blurRadius: Float
    public var offsetX: Float
    public var offsetY: Float

    public init(
        x: Float = 0, y: Float = 0, width: Float = 0, height: Float = 0,
        cornerRadius: Float = 0,
        colorR: Float = 0, colorG: Float = 0, colorB: Float = 0, colorA: Float = 0.5,
        blurRadius: Float = 0, offsetX: Float = 0, offsetY: Float = 0
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
}
