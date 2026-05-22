import SwiftWindowsCore

public struct GPUIContentMask: Equatable, Sendable {
    public var bounds: Rect?

    public init(bounds: Rect? = nil) {
        self.bounds = bounds
    }
}

// MARK: - Quad Primitive

/// A rounded rectangle with optional gradient fill, designed for direct upload
/// to a D3D11 structured buffer. All fields are `Float` for GPU compatibility.
/// Total: 24 floats = 96 bytes (divisible by 16 for StructuredBuffer alignment).
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
    // Visual effect: 0=none, 1=brightness, 2=contrast, 3=saturation,
    //                 4=grayscale, 5=colorInvert, 6=hueRotation,
    //                 7=colorMultiply, 8=luminanceToAlpha
    public var effectType: Float
    // Intensity parameter for the active effect (ignored by colorInvert)
    public var effectIntensity: Float
    // Post-process blur radius in pixels (0 = no blur)
    public var blurRadius: Float
    // 0 = blur with transparency, 1 = blur fills with opaque background
    public var blurOpaque: Float
    // Generic effect parameters (usage depends on effectType)
    public var effectParam1: Float
    public var effectParam2: Float
    public var effectParam3: Float
    public var effectParam4: Float
    public var clipCornerRadius: Float
    public var blendMode: Float
    // Rotation in radians around the quad's centre. 0 = axis-aligned
    // (the historic fast path). When non-zero, the GPU vertex shader
    // and CPU rasterizer both rotate the rendered footprint while
    // keeping interior coordinates (corner radius, gradient axis,
    // local-space effects) computed in unrotated space.
    public var rotationRadians: Float
    // Reserved padding so the struct's byte stride stays a multiple of
    // 16, which HLSL structured buffers require for their element
    // alignment. Three floats of padding bring us from 116 to 128.
    public var _reserved0: Float
    public var _reserved1: Float
    public var _reserved2: Float

    public init(
        x: Float = 0, y: Float = 0, width: Float = 0, height: Float = 0,
        cornerRadius: Float = 0,
        startR: Float = 0, startG: Float = 0, startB: Float = 0, startA: Float = 1,
        endR: Float = 0, endG: Float = 0, endB: Float = 0, endA: Float = 1,
        gradientAxis: Float = 0,
        clipX: Float = 0, clipY: Float = 0, clipWidth: Float = 0, clipHeight: Float = 0,
        clipCornerRadius: Float = 0,
        blendMode: Float = 0,
        effectType: Float = 0,
        effectIntensity: Float = 0,
        blurRadius: Float = 0,
        blurOpaque: Float = 0,
        effectParam1: Float = 0,
        effectParam2: Float = 0,
        effectParam3: Float = 0,
        effectParam4: Float = 0,
        rotationRadians: Float = 0
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
        self.clipCornerRadius = clipCornerRadius
        self.blendMode = blendMode
        self.effectType = effectType
        self.effectIntensity = effectIntensity
        self.blurRadius = blurRadius
        self.blurOpaque = blurOpaque
        self.effectParam1 = effectParam1
        self.effectParam2 = effectParam2
        self.effectParam3 = effectParam3
        self.effectParam4 = effectParam4
        self.rotationRadians = rotationRadians
        self._reserved0 = 0
        self._reserved1 = 0
        self._reserved2 = 0
    }

    public static var byteSize: Int { MemoryLayout<Self>.size }

    public var contentMask: GPUIContentMask {
        get {
            guard clipWidth > 0, clipHeight > 0 else {
                return GPUIContentMask()
            }

            return GPUIContentMask(
                bounds: Rect(
                    x: Double(clipX),
                    y: Double(clipY),
                    width: Double(clipWidth),
                    height: Double(clipHeight)
                ))
        }
        set {
            guard let bounds = newValue.bounds else {
                clipX = 0
                clipY = 0
                clipWidth = 0
                clipHeight = 0
                return
            }

            clipX = Float(bounds.origin.x)
            clipY = Float(bounds.origin.y)
            clipWidth = Float(bounds.size.width)
            clipHeight = Float(bounds.size.height)
        }
    }
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

    public var contentMask: GPUIContentMask {
        get {
            guard clipWidth > 0, clipHeight > 0 else {
                return GPUIContentMask()
            }

            return GPUIContentMask(
                bounds: Rect(
                    x: Double(clipX),
                    y: Double(clipY),
                    width: Double(clipWidth),
                    height: Double(clipHeight)
                ))
        }
        set {
            guard let bounds = newValue.bounds else {
                clipX = 0
                clipY = 0
                clipWidth = 0
                clipHeight = 0
                return
            }

            clipX = Float(bounds.origin.x)
            clipY = Float(bounds.origin.y)
            clipWidth = Float(bounds.size.width)
            clipHeight = Float(bounds.size.height)
        }
    }
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

    public var contentMask: GPUIContentMask {
        get {
            guard clipWidth > 0, clipHeight > 0 else {
                return GPUIContentMask()
            }

            return GPUIContentMask(
                bounds: Rect(
                    x: Double(clipX),
                    y: Double(clipY),
                    width: Double(clipWidth),
                    height: Double(clipHeight)
                ))
        }
        set {
            guard let bounds = newValue.bounds else {
                clipX = 0
                clipY = 0
                clipWidth = 0
                clipHeight = 0
                return
            }

            clipX = Float(bounds.origin.x)
            clipY = Float(bounds.origin.y)
            clipWidth = Float(bounds.size.width)
            clipHeight = Float(bounds.size.height)
        }
    }
}

// MARK: - Shadow Primitive

/// A soft shadow rectangle, designed for direct upload to a D3D11 structured
/// buffer. Total: 16 floats = 64 bytes (divisible by 16).
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
    // Content mask / clip bounds
    public var clipX: Float
    public var clipY: Float
    public var clipWidth: Float
    public var clipHeight: Float

    public init(
        x: Float = 0, y: Float = 0, width: Float = 0, height: Float = 0,
        cornerRadius: Float = 0,
        colorR: Float = 0, colorG: Float = 0, colorB: Float = 0, colorA: Float = 0.5,
        blurRadius: Float = 4,
        offsetX: Float = 0, offsetY: Float = 0,
        clipX: Float = 0, clipY: Float = 0, clipWidth: Float = 0, clipHeight: Float = 0
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
        self.clipX = clipX
        self.clipY = clipY
        self.clipWidth = clipWidth
        self.clipHeight = clipHeight
    }

    public static var byteSize: Int { MemoryLayout<Self>.size }

    public var contentMask: GPUIContentMask {
        get {
            guard clipWidth > 0, clipHeight > 0 else {
                return GPUIContentMask()
            }

            return GPUIContentMask(
                bounds: Rect(
                    x: Double(clipX),
                    y: Double(clipY),
                    width: Double(clipWidth),
                    height: Double(clipHeight)
                ))
        }
        set {
            guard let bounds = newValue.bounds else {
                clipX = 0
                clipY = 0
                clipWidth = 0
                clipHeight = 0
                return
            }

            clipX = Float(bounds.origin.x)
            clipY = Float(bounds.origin.y)
            clipWidth = Float(bounds.size.width)
            clipHeight = Float(bounds.size.height)
        }
    }
}

// MARK: - Path Primitive

/// A CPU-rasterized path with fill and/or stroke. Not designed for D3D11
/// structured buffers; the D3D11 backend tessellates or skips paths.
public struct PathPrimitive: Equatable, Sendable {
    public var elements: [PathElement]
    public var bounds: Rect
    public var fillColor: Color
    public var strokeColor: Color
    public var lineWidth: Double
    public var clipBounds: Rect?

    public init(
        elements: [PathElement],
        bounds: Rect,
        fillColor: Color = .clear,
        strokeColor: Color = .clear,
        lineWidth: Double = 0,
        clipBounds: Rect? = nil
    ) {
        self.elements = elements
        self.bounds = bounds
        self.fillColor = fillColor
        self.strokeColor = strokeColor
        self.lineWidth = lineWidth
        self.clipBounds = clipBounds
    }

    public var contentMask: GPUIContentMask {
        get {
            guard let bounds = clipBounds, !bounds.isEmpty else {
                return GPUIContentMask()
            }
            return GPUIContentMask(bounds: bounds)
        }
        set {
            clipBounds = newValue.bounds
        }
    }

    public var contentMaskedBounds: Rect? {
        guard !bounds.isEmpty else { return nil }
        if let clip = clipBounds, !clip.isEmpty {
            return bounds.intersected(with: clip) ?? bounds
        }
        return bounds
    }

    /// Returns a new path with all element coordinates and bounds offset by the given point.
    public func translated(by offset: Point) -> PathPrimitive {
        let translatedElements = elements.map { element -> PathElement in
            switch element {
            case .moveTo(let p):
                return .moveTo(Point(x: p.x + offset.x, y: p.y + offset.y))
            case .lineTo(let p):
                return .lineTo(Point(x: p.x + offset.x, y: p.y + offset.y))
            case .quadraticCurveTo(let c, let e):
                return .quadraticCurveTo(
                    control: Point(x: c.x + offset.x, y: c.y + offset.y),
                    end: Point(x: e.x + offset.x, y: e.y + offset.y)
                )
            case .cubicCurveTo(let c1, let c2, let e):
                return .cubicCurveTo(
                    control1: Point(x: c1.x + offset.x, y: c1.y + offset.y),
                    control2: Point(x: c2.x + offset.x, y: c2.y + offset.y),
                    end: Point(x: e.x + offset.x, y: e.y + offset.y)
                )
            case .arc(let c, let r, let s, let e, let cw):
                return .arc(
                    center: Point(x: c.x + offset.x, y: c.y + offset.y),
                    radius: r,
                    startAngle: s,
                    endAngle: e,
                    clockwise: cw
                )
            case .close:
                return .close
            }
        }

        let translatedBounds = Rect(
            origin: Point(x: bounds.origin.x + offset.x, y: bounds.origin.y + offset.y),
            size: bounds.size
        )
        let translatedClip = clipBounds.map { clip in
            Rect(
                origin: Point(x: clip.origin.x + offset.x, y: clip.origin.y + offset.y),
                size: clip.size
            )
        }

        return PathPrimitive(
            elements: translatedElements,
            bounds: translatedBounds,
            fillColor: fillColor,
            strokeColor: strokeColor,
            lineWidth: lineWidth,
            clipBounds: translatedClip
        )
    }
}
