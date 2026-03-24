import SwiftWindowsCore

// MARK: - GPUI Primitive Types
//
// These are the GPU-friendly primitive types used by the batch rendering
// pipeline. Each primitive is a flat struct with Float fields suitable for
// uploading to GPU constant buffers or vertex data.

/// A filled (optionally rounded) rectangle primitive.
public struct QuadPrimitive: Equatable, Sendable {
    public var x: Float
    public var y: Float
    public var width: Float
    public var height: Float
    public var cornerRadius: Float
    public var red: Float
    public var green: Float
    public var blue: Float
    public var alpha: Float
    /// Clip rect (x, y, width, height). When nil, no clipping is applied.
    public var clipRect: (Float, Float, Float, Float)?

    public init(
        x: Float, y: Float, width: Float, height: Float,
        cornerRadius: Float = 0,
        red: Float, green: Float, blue: Float, alpha: Float,
        clipRect: (Float, Float, Float, Float)? = nil
    ) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
        self.clipRect = clipRect
    }

    public static func == (lhs: QuadPrimitive, rhs: QuadPrimitive) -> Bool {
        lhs.x == rhs.x && lhs.y == rhs.y &&
        lhs.width == rhs.width && lhs.height == rhs.height &&
        lhs.cornerRadius == rhs.cornerRadius &&
        lhs.red == rhs.red && lhs.green == rhs.green &&
        lhs.blue == rhs.blue && lhs.alpha == rhs.alpha &&
        lhs.clipRect?.0 == rhs.clipRect?.0 &&
        lhs.clipRect?.1 == rhs.clipRect?.1 &&
        lhs.clipRect?.2 == rhs.clipRect?.2 &&
        lhs.clipRect?.3 == rhs.clipRect?.3
    }
}

/// A shadow primitive rendered behind a quad.
public struct ShadowPrimitive: Equatable, Sendable {
    public var x: Float
    public var y: Float
    public var width: Float
    public var height: Float
    public var cornerRadius: Float
    public var blurRadius: Float
    public var red: Float
    public var green: Float
    public var blue: Float
    public var alpha: Float

    public init(
        x: Float, y: Float, width: Float, height: Float,
        cornerRadius: Float = 0, blurRadius: Float = 0,
        red: Float, green: Float, blue: Float, alpha: Float
    ) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
        self.blurRadius = blurRadius
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

/// A glyph (single character) primitive for GPU text rendering.
public struct GlyphPrimitive: Equatable, Sendable {
    public var x: Float
    public var y: Float
    public var width: Float
    public var height: Float
    /// UV coordinates into the glyph atlas (u0, v0, u1, v1).
    public var atlasU0: Float
    public var atlasV0: Float
    public var atlasU1: Float
    public var atlasV1: Float
    public var red: Float
    public var green: Float
    public var blue: Float
    public var alpha: Float

    public init(
        x: Float, y: Float, width: Float, height: Float,
        atlasU0: Float = 0, atlasV0: Float = 0,
        atlasU1: Float = 1, atlasV1: Float = 1,
        red: Float, green: Float, blue: Float, alpha: Float
    ) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.atlasU0 = atlasU0
        self.atlasV0 = atlasV0
        self.atlasU1 = atlasU1
        self.atlasV1 = atlasV1
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

/// An image (bitmap) primitive.
public struct ImagePrimitive: Equatable, Sendable {
    public var x: Float
    public var y: Float
    public var width: Float
    public var height: Float
    public var opacity: Float
    /// Texture identifier — resolved by the renderer to an actual GPU texture.
    public var textureID: UInt32

    public init(
        x: Float, y: Float, width: Float, height: Float,
        opacity: Float = 1.0, textureID: UInt32 = 0
    ) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.opacity = opacity
        self.textureID = textureID
    }
}
