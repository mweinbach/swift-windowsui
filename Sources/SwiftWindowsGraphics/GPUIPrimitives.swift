import SwiftWindowsCore

/// GPU-ready quad instance for batched instanced rendering.
/// Layout: 20 floats = 80 bytes, matching the StructuredBuffer stride in HLSL.
public struct QuadPrimitive: Equatable, Sendable {
    // Position and size (float4 boundary 1)
    public var x: Float
    public var y: Float
    public var width: Float
    public var height: Float
    // Corner radius + start color RGB (float4 boundary 2)
    public var cornerRadius: Float
    public var startR: Float
    public var startG: Float
    public var startB: Float
    // Start alpha + end color RGB (float4 boundary 3)
    public var startA: Float
    public var endR: Float
    public var endG: Float
    public var endB: Float
    // End alpha + gradient axis + clip X/Y (float4 boundary 4)
    public var endA: Float
    public var gradientAxis: Float
    public var clipX: Float
    public var clipY: Float
    // Clip width/height + padding (float4 boundary 5)
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
        clipX: Float = -1, clipY: Float = -1,
        clipWidth: Float = -1, clipHeight: Float = -1,
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

/// GPU-ready glyph instance for text rendering via a glyph atlas.
/// Layout: 12 floats = 48 bytes.
public struct GlyphPrimitive: Equatable, Sendable {
    // Screen position and size (float4 boundary 1)
    public var screenX: Float
    public var screenY: Float
    public var screenW: Float
    public var screenH: Float
    // Atlas UV coordinates (float4 boundary 2)
    public var atlasU0: Float
    public var atlasV0: Float
    public var atlasU1: Float
    public var atlasV1: Float
    // Color (float4 boundary 3)
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

/// GPU-ready image instance for textured quad rendering.
/// Layout: 16 floats = 64 bytes.
public struct ImagePrimitive: Equatable, Sendable {
    // Screen position and size (float4 boundary 1)
    public var screenX: Float
    public var screenY: Float
    public var screenW: Float
    public var screenH: Float
    // UV rect (float4 boundary 2)
    public var uvX: Float
    public var uvY: Float
    public var uvW: Float
    public var uvH: Float
    // Opacity + clip rect (float4 boundary 3)
    public var opacity: Float
    public var clipX: Float
    public var clipY: Float
    public var clipWidth: Float
    // Clip height + texture ID + padding (float4 boundary 4)
    public var clipHeight: Float
    public var textureID: Int32
    public var pad1: Float
    public var pad2: Float

    public init(
        screenX: Float, screenY: Float, screenW: Float, screenH: Float,
        uvX: Float = 0, uvY: Float = 0, uvW: Float = 1, uvH: Float = 1,
        opacity: Float = 1,
        clipX: Float = -1, clipY: Float = -1,
        clipWidth: Float = -1, clipHeight: Float = -1,
        textureID: Int32 = 0,
        pad1: Float = 0, pad2: Float = 0
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

/// GPU-ready shadow instance for soft shadow rendering via SDF.
/// Layout: 12 floats = 48 bytes.
public struct ShadowPrimitive: Equatable, Sendable {
    // Position and size (float4 boundary 1)
    public var x: Float
    public var y: Float
    public var width: Float
    public var height: Float
    // Corner radius + color RGBA (float4 boundary 2 partial)
    public var cornerRadius: Float
    public var colorR: Float
    public var colorG: Float
    public var colorB: Float
    // Color alpha + blur radius + offset (float4 boundary 3)
    public var colorA: Float
    public var blurRadius: Float
    public var offsetX: Float
    public var offsetY: Float

    public init(
        x: Float, y: Float, width: Float, height: Float,
        cornerRadius: Float = 0,
        colorR: Float = 0, colorG: Float = 0, colorB: Float = 0, colorA: Float = 0.5,
        blurRadius: Float = 8,
        offsetX: Float = 0, offsetY: Float = 4
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
