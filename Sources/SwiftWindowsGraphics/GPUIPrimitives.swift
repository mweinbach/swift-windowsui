import SwiftWindowsCore

/// A filled rounded rectangle with solid or gradient color and clip bounds.
/// Layout: 20 floats for GPU-friendly instanced rendering.
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
    public var pad1: Float
    public var pad2: Float

    public init(
        x: Float, y: Float, width: Float, height: Float,
        cornerRadius: Float = 0,
        startR: Float, startG: Float, startB: Float, startA: Float,
        endR: Float, endG: Float, endB: Float, endA: Float,
        gradientAxis: Float = 0,
        clipX: Float, clipY: Float, clipWidth: Float, clipHeight: Float,
        pad1: Float = 0, pad2: Float = 0
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
        self.pad1 = pad1
        self.pad2 = pad2
    }
}

/// A single glyph positioned on screen with atlas UV coordinates.
/// Layout: 12 floats.
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
        screenX: Float, screenY: Float, screenW: Float, screenH: Float,
        atlasU0: Float, atlasV0: Float, atlasU1: Float, atlasV1: Float,
        colorR: Float, colorG: Float, colorB: Float, colorA: Float
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

/// A textured image quad with clip bounds and opacity.
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
    public var textureID: Int32
    public var pad1: Float
    public var pad2: Float

    public init(
        screenX: Float, screenY: Float, screenW: Float, screenH: Float,
        uvX: Float = 0, uvY: Float = 0, uvW: Float = 1, uvH: Float = 1,
        opacity: Float = 1,
        clipX: Float, clipY: Float, clipWidth: Float, clipHeight: Float,
        textureID: Int32 = 0, pad1: Float = 0, pad2: Float = 0
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
        self.pad1 = pad1
        self.pad2 = pad2
    }
}

/// A shadow drawn behind a rounded rectangle.
/// Layout: 12 floats.
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
        x: Float, y: Float, width: Float, height: Float,
        cornerRadius: Float = 0,
        colorR: Float, colorG: Float, colorB: Float, colorA: Float,
        blurRadius: Float = 0,
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
}
