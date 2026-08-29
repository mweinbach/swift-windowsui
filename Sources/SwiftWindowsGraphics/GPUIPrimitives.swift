import Foundation
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
/// Total: 36 floats = 144 bytes (divisible by 16 for StructuredBuffer alignment).
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
    // 0 = vertical, 1 = horizontal, 2 = authored two-dimensional vector,
    // 3 = radial, 4 = angular/conic. Advanced modes borrow effectParam1...4
    // for their quad-local geometry when effectType is zero.
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
    // Per-corner rounding in pixels: topLeft, topRight, bottomRight,
    // bottomLeft. When any of these is > 0 the quad renders with
    // per-corner radii and the uniform `cornerRadius` is ignored; when
    // all are 0 the uniform `cornerRadius` applies exactly as before
    // (this keeps every pre-existing scene byte-identical). The D3D11
    // pixel shader and the CPU rasterizer implement the same
    // quadrant-selection maths so both backends stay coherent.
    public var cornerRadiusTopLeft: Float
    public var cornerRadiusTopRight: Float
    public var cornerRadiusBottomRight: Float
    public var cornerRadiusBottomLeft: Float
    // These three existing ABI slots carry piecewise-linear gradient
    // intervals without changing the 144-byte structured-buffer stride.
    // Their stored names remain stable because existing layout probes pin
    // offsets 132, 136 and 140. Zero in the final slot means the original
    // single-quad gradient path, preserving every existing scene byte-for-byte.
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
        rotationRadians: Float = 0,
        cornerRadiusTopLeft: Float = 0,
        cornerRadiusTopRight: Float = 0,
        cornerRadiusBottomRight: Float = 0,
        cornerRadiusBottomLeft: Float = 0
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
        self.cornerRadiusTopLeft = cornerRadiusTopLeft
        self.cornerRadiusTopRight = cornerRadiusTopRight
        self.cornerRadiusBottomRight = cornerRadiusBottomRight
        self.cornerRadiusBottomLeft = cornerRadiusBottomLeft
        self._reserved0 = 0
        self._reserved1 = 0
        self._reserved2 = 0
    }

    public static var byteSize: Int { MemoryLayout<Self>.size }

    /// Normalized beginning of the gradient interval owned by this quad.
    public var gradientSegmentStart: Float {
        get { _reserved0 }
        set { _reserved0 = newValue }
    }

    /// Normalized end of the gradient interval owned by this quad.
    public var gradientSegmentEnd: Float {
        get { _reserved1 }
        set { _reserved1 = newValue }
    }

    /// 0 = legacy whole gradient, 1 = half-open segment, 2 = final segment.
    public var gradientSegmentMode: Float {
        get { _reserved2 }
        set { _reserved2 = newValue }
    }

    /// True when this primitive samples an explicitly positioned,
    /// two-dimensional gradient instead of stretching a ramp along one of its
    /// bounds axes. The authored points occupy existing color-effect parameter
    /// slots, preserving the structured-buffer's pinned 144-byte ABI.
    public var usesDirectionalGradient: Bool {
        gradientAxis == 2
    }

    /// Radial gradients store their local center and authored start/end radii
    /// in the four otherwise-unused color-effect parameter slots.
    public var usesRadialGradient: Bool {
        gradientAxis == 3
    }

    /// Angular gradients store their local center, starting angle and signed
    /// sweep in the four otherwise-unused color-effect parameter slots.
    public var usesConicGradient: Bool {
        gradientAxis == 4
    }

    /// Configures a gradient in surface coordinates while retaining this
    /// quad's original footprint, rounded coverage and clip. The stored points
    /// are quad-local, so moving the complete scene does not alter the sampled
    /// ramp. Color effects own the same four existing ABI slots and therefore
    /// cannot be combined with this representation.
    public func segmented(
        for gradient: LinearGradient,
        from start: Point,
        to end: Point,
        opacity: Float = 1
    ) -> [QuadPrimitive]? {
        guard effectType == 0, rotationRadians == 0 else { return nil }

        let coordinates = [
            start.x - Double(x),
            start.y - Double(y),
            end.x - Double(x),
            end.y - Double(y),
        ]
        let limit = Double(GPUISceneLimits.maxCoordinate)
        guard coordinates.allSatisfy({ $0.isFinite && abs($0) <= limit }) else {
            return nil
        }

        var quad = self
        quad.gradientAxis = 2
        quad.effectParam1 = Float(coordinates[0])
        quad.effectParam2 = Float(coordinates[1])
        quad.effectParam3 = Float(coordinates[2])
        quad.effectParam4 = Float(coordinates[3])
        quad.startR = gradient.startColor.red
        quad.startG = gradient.startColor.green
        quad.startB = gradient.startColor.blue
        quad.startA = gradient.startColor.alpha * opacity
        quad.endR = gradient.endColor.red
        quad.endG = gradient.endColor.green
        quad.endB = gradient.endColor.blue
        quad.endA = gradient.endColor.alpha * opacity
        return quad.segmented(for: gradient, opacity: opacity)
    }

    /// Configures a radial-gradient footprint without widening the 144-byte
    /// instance ABI. Relative SwiftUI centers resolve against this exact quad;
    /// absolute renderer-neutral centers remain surface coordinates.
    public func radialGradientQuad(
        for gradient: RadialGradient,
        displayScale: Double = 1,
        opacity: Float = 1
    ) -> QuadPrimitive? {
        guard displayScale.isFinite, displayScale > 0,
            gradient.startRadius >= 0, gradient.radius >= 0
        else {
            return nil
        }
        let center = localGradientCenter(
            gradient.center,
            isUnitPoint: gradient.centerIsUnitPoint,
            displayScale: displayScale)
        return parameterizedGradientQuad(
            stops: gradient.stops,
            mode: 3,
            parameters: [
                center.x,
                center.y,
                gradient.startRadius * displayScale,
                gradient.radius * displayScale,
            ],
            opacity: opacity)
    }

    /// Configures an angular-gradient footprint. Equal or absent endpoint
    /// angles mean a full turn; an explicit negative sweep reverses direction.
    public func conicGradientQuad(
        for gradient: ConicGradient,
        displayScale: Double = 1,
        opacity: Float = 1
    ) -> QuadPrimitive? {
        guard displayScale.isFinite, displayScale > 0 else { return nil }
        let center = localGradientCenter(
            gradient.center,
            isUnitPoint: gradient.centerIsUnitPoint,
            displayScale: displayScale)
        let authoredSweep = gradient.endAngle.map { $0 - gradient.angle } ?? (2 * Double.pi)
        let sweep = abs(authoredSweep) < 0.000_001 ? 2 * Double.pi : authoredSweep
        return parameterizedGradientQuad(
            stops: gradient.stops,
            mode: 4,
            parameters: [center.x, center.y, gradient.angle, sweep],
            opacity: opacity)
    }

    private func localGradientCenter(
        _ center: Point,
        isUnitPoint: Bool,
        displayScale: Double
    ) -> Point {
        if isUnitPoint {
            return Point(
                x: center.x * Double(width),
                y: center.y * Double(height))
        }
        return Point(
            x: center.x * displayScale - Double(x),
            y: center.y * displayScale - Double(y))
    }

    private func parameterizedGradientQuad(
        stops: [GradientStop],
        mode: Float,
        parameters: [Double],
        opacity: Float
    ) -> QuadPrimitive? {
        guard effectType == 0, opacity.isFinite else { return nil }
        let limit = Double(GPUISceneLimits.maxCoordinate)
        guard parameters.count == 4,
            parameters.allSatisfy({ $0.isFinite && abs($0) <= limit })
        else {
            return nil
        }

        let start = stops.first?.color ?? .clear
        let end = stops.last?.color ?? start
        var quad = self
        quad.gradientAxis = mode
        quad.effectParam1 = Float(parameters[0])
        quad.effectParam2 = Float(parameters[1])
        quad.effectParam3 = Float(parameters[2])
        quad.effectParam4 = Float(parameters[3])
        quad.startR = start.red
        quad.startG = start.green
        quad.startB = start.blue
        quad.startA = start.alpha * opacity
        quad.endR = end.red
        quad.endG = end.green
        quad.endB = end.blue
        quad.endA = end.alpha * opacity
        return quad
    }

    /// Expands an authored gradient into full-geometry, disjoint color
    /// segments. Keeping the original footprint preserves rounded coverage,
    /// transformed coordinates and inherited clipping on both renderers.
    public func segmented(for gradient: LinearGradient, opacity: Float = 1) -> [QuadPrimitive] {
        let segments = gradient.renderedSegments

        // The ubiquitous two-stop gradient remains the exact primitive the
        // caller built: no extra paint operations, no ABI changes and no
        // shifted gallery baselines.
        if gradient.stops.count == 2,
            gradient.stops[0].position == 0,
            gradient.stops[1].position == 1
        {
            guard gradient.reversesAuthoredStops else { return [self] }
            var corrected = self
            corrected.startR = gradient.startColor.red
            corrected.startG = gradient.startColor.green
            corrected.startB = gradient.startColor.blue
            corrected.startA = gradient.startColor.alpha * opacity
            corrected.endR = gradient.endColor.red
            corrected.endG = gradient.endColor.green
            corrected.endB = gradient.endColor.blue
            corrected.endA = gradient.endColor.alpha * opacity
            return [corrected]
        }

        return segments.enumerated().map { index, segment in
            var quad = self
            quad.startR = segment.startColor.red
            quad.startG = segment.startColor.green
            quad.startB = segment.startColor.blue
            quad.startA = segment.startColor.alpha * opacity
            quad.endR = segment.endColor.red
            quad.endG = segment.endColor.green
            quad.endB = segment.endColor.blue
            quad.endA = segment.endColor.alpha * opacity
            quad.gradientSegmentStart = segment.start
            quad.gradientSegmentEnd = segment.end
            quad.gradientSegmentMode = index == segments.count - 1 ? 2 : 1
            return quad
        }
    }

    /// True when per-corner radii override the uniform `cornerRadius`.
    /// Both render backends check this exact predicate.
    public var usesPerCornerRadii: Bool {
        cornerRadiusTopLeft > 0 || cornerRadiusTopRight > 0
            || cornerRadiusBottomRight > 0 || cornerRadiusBottomLeft > 0
    }

    public var contentMask: GPUIContentMask {
        get {
            GPUIClipEncoding.contentMask(
                clipX: clipX, clipY: clipY, clipWidth: clipWidth, clipHeight: clipHeight)
        }
        set {
            GPUIClipEncoding.encode(
                newValue.bounds, into: &clipX, &clipY, &clipWidth, &clipHeight)
        }
    }
}

// MARK: - Glyph Primitive

/// A single glyph from a font atlas, designed for direct upload to a D3D11
/// structured buffer. Total: 20 floats = 80 bytes (divisible by 16).
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
    // Rounding of the clip rect. Text inside a rounded container used to be
    // clipped square on both backends — consistent, and consistently wrong
    // against macOS — because only `QuadPrimitive` could express it.
    public var clipCornerRadius: Float
    // Rotation in radians around the glyph cell's centre. 0 = upright (the
    // historic fast path). Non-zero turns the sampled cell, so a run of
    // text inside a `.rotationEffect` subtree reads along the rotated
    // baseline instead of staying upright inside a turned card. This slot
    // used to be `_pad0`, so the stride is unchanged at 80 bytes.
    public var rotationRadians: Float
    // Padding to a 16-byte multiple, which HLSL structured buffers require
    // for their element stride. 18 floats round up to 20.
    public var _pad1: Float
    public var _pad2: Float

    public init(
        screenX: Float = 0, screenY: Float = 0, screenW: Float = 0, screenH: Float = 0,
        atlasU0: Float = 0, atlasV0: Float = 0, atlasU1: Float = 0, atlasV1: Float = 0,
        colorR: Float = 1, colorG: Float = 1, colorB: Float = 1, colorA: Float = 1,
        clipX: Float = 0, clipY: Float = 0, clipWidth: Float = 0, clipHeight: Float = 0,
        clipCornerRadius: Float = 0,
        rotationRadians: Float = 0
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
        self.clipCornerRadius = clipCornerRadius
        self.rotationRadians = rotationRadians
        self._pad1 = 0
        self._pad2 = 0
    }

    public static var byteSize: Int { MemoryLayout<Self>.size }

    public var contentMask: GPUIContentMask {
        get {
            GPUIClipEncoding.contentMask(
                clipX: clipX, clipY: clipY, clipWidth: clipWidth, clipHeight: clipHeight)
        }
        set {
            GPUIClipEncoding.encode(
                newValue.bounds, into: &clipX, &clipY, &clipWidth, &clipHeight)
        }
    }
}

// MARK: - Image Primitive

/// A texture-mapped quad, designed for direct upload to a D3D11 structured
/// buffer. Total: 32 fields = 128 bytes (divisible by 16). The original
/// placement/UV fields retain their offsets; sampling occupies bytes 80...127.
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
    // Rounding of the clip rect. This field used to be `_pad0`, so an image
    // inside a rounded card clipped square while the card background rounded
    // — the rounding cost nothing here but a name.
    public var clipCornerRadius: Float
    // Rotation in radians around the destination rect's centre. 0 = axis
    // aligned (the historic fast path). This is what lets a composited
    // offscreen pass — a `.drawingGroup()`, or the bitmap a rotated
    // `clipsToBounds` subtree renders into — land turned rather than
    // squared off into its own bounding box.
    public var rotationRadians: Float
    // The affine basis acts on local offsets from the destination centre,
    // before rotationRadians: x' = A*x + C*y, y' = B*x + D*y. Identity keeps
    // the historic placement; a negative determinant preserves reflections.
    public var affineA: Float
    public var affineB: Float
    public var affineC: Float
    public var affineD: Float

    // Fixed-size cap/tile sampling, kept flat for structured-buffer upload.
    public var sourceCapLeft: Float
    public var sourceCapTop: Float
    public var sourceCapRight: Float
    public var sourceCapBottom: Float
    public var destinationCapLeft: Float
    public var destinationCapTop: Float
    public var destinationCapRight: Float
    public var destinationCapBottom: Float
    public var centerRepeatX: Float
    public var centerRepeatY: Float
    public var samplingKind: Int32
    public var samplingPadding: Float

    public init(
        screenX: Float = 0, screenY: Float = 0, screenW: Float = 0, screenH: Float = 0,
        uvX: Float = 0, uvY: Float = 0, uvW: Float = 1, uvH: Float = 1,
        opacity: Float = 1,
        clipX: Float = 0, clipY: Float = 0, clipWidth: Float = 0, clipHeight: Float = 0,
        clipCornerRadius: Float = 0,
        textureID: Int32 = 0,
        rotationRadians: Float = 0,
        affineA: Float = 1, affineB: Float = 0, affineC: Float = 0, affineD: Float = 1,
        sampling: ImageSamplingDescriptor = .legacy
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
        self.clipCornerRadius = clipCornerRadius
        self.rotationRadians = rotationRadians
        self.affineA = affineA
        self.affineB = affineB
        self.affineC = affineC
        self.affineD = affineD
        sourceCapLeft = sampling.sourceCapLeft
        sourceCapTop = sampling.sourceCapTop
        sourceCapRight = sampling.sourceCapRight
        sourceCapBottom = sampling.sourceCapBottom
        destinationCapLeft = sampling.destinationCapLeft
        destinationCapTop = sampling.destinationCapTop
        destinationCapRight = sampling.destinationCapRight
        destinationCapBottom = sampling.destinationCapBottom
        centerRepeatX = sampling.centerRepeatX
        centerRepeatY = sampling.centerRepeatY
        samplingKind = sampling.samplingKind
        samplingPadding = sampling.samplingPadding
    }

    public static var byteSize: Int { MemoryLayout<Self>.size }

    public var sampling: ImageSamplingDescriptor {
        get {
            ImageSamplingDescriptor(
                sourceCapLeft: sourceCapLeft, sourceCapTop: sourceCapTop,
                sourceCapRight: sourceCapRight, sourceCapBottom: sourceCapBottom,
                destinationCapLeft: destinationCapLeft, destinationCapTop: destinationCapTop,
                destinationCapRight: destinationCapRight, destinationCapBottom: destinationCapBottom,
                centerRepeatX: centerRepeatX, centerRepeatY: centerRepeatY,
                samplingKind: samplingKind, samplingPadding: samplingPadding)
        }
        set {
            sourceCapLeft = newValue.sourceCapLeft
            sourceCapTop = newValue.sourceCapTop
            sourceCapRight = newValue.sourceCapRight
            sourceCapBottom = newValue.sourceCapBottom
            destinationCapLeft = newValue.destinationCapLeft
            destinationCapTop = newValue.destinationCapTop
            destinationCapRight = newValue.destinationCapRight
            destinationCapBottom = newValue.destinationCapBottom
            centerRepeatX = newValue.centerRepeatX
            centerRepeatY = newValue.centerRepeatY
            samplingKind = newValue.samplingKind
            samplingPadding = newValue.samplingPadding
        }
    }

    public var contentMask: GPUIContentMask {
        get {
            GPUIClipEncoding.contentMask(
                clipX: clipX, clipY: clipY, clipWidth: clipWidth, clipHeight: clipHeight)
        }
        set {
            GPUIClipEncoding.encode(
                newValue.bounds, into: &clipX, &clipY, &clipWidth, &clipHeight)
        }
    }
}

extension ImagePrimitive {
    var hasIdentityAffineTransform: Bool {
        affineA == 1 && affineB == 0 && affineC == 0 && affineD == 1
    }

    /// Invalid bases cannot be repaired by clamping: doing that would paint
    /// a different parallelogram. Double products exactly represent the
    /// products of these Float coefficients, including very small scales.
    var hasValidAffineMatrix: Bool {
        guard affineA.isFinite, affineB.isFinite, affineC.isFinite, affineD.isFinite else { return false }
        let determinant = Double(affineA) * Double(affineD) - Double(affineB) * Double(affineC)
        return determinant.isFinite && determinant != 0
    }

    var affinePlacementDefect: String? {
        guard hasValidAffineMatrix else { return "affine matrix is nonfinite or singular" }
        guard rotationRadians.isFinite else { return "rotation is nonfinite" }
        guard ImagePlacementGeometry(self) != nil else {
            return "affine placement is not representable within the scene coordinate limit"
        }
        return nil
    }
}

/// One renderer-neutral model for affine image bounds and inverse sampling.
/// The clip stays in world coordinates; only geometry and source UVs move.
struct ImagePlacementGeometry {
    let bounds: Rect
    private let centreX: Double
    private let centreY: Double
    private let cosR: Double
    private let sinR: Double
    private let inverseA: Double
    private let inverseB: Double
    private let inverseC: Double
    private let inverseD: Double
    private let includesLeft: Bool
    private let includesRight: Bool
    private let includesTop: Bool
    private let includesBottom: Bool

    init?(_ image: ImagePrimitive) {
        guard image.hasValidAffineMatrix,
            image.screenX.isFinite, image.screenY.isFinite,
            image.screenW.isFinite, image.screenH.isFinite,
            image.rotationRadians.isFinite,
            image.screenW >= 0, image.screenH >= 0
        else { return nil }

        let a = Double(image.affineA)
        let b = Double(image.affineB)
        let c = Double(image.affineC)
        let d = Double(image.affineD)
        let determinant = a * d - b * c
        let angle = Double(image.rotationRadians)
        let cosR = cos(angle)
        let sinR = sin(angle)
        let halfW = Double(image.screenW) * 0.5
        let halfH = Double(image.screenH) * 0.5
        let centreX = Double(image.screenX) + halfW
        let centreY = Double(image.screenY) + halfH
        let basisA = cosR * a - sinR * b
        let basisB = sinR * a + cosR * b
        let basisC = cosR * c - sinR * d
        let basisD = sinR * c + cosR * d
        let extentX = abs(basisA) * halfW + abs(basisC) * halfH
        let extentY = abs(basisB) * halfW + abs(basisD) * halfH
        let bounds = Rect(x: centreX - extentX, y: centreY - extentY, width: extentX * 2, height: extentY * 2)

        // Existing identity-basis scenes keep their established sanitation
        // and rotation behavior. New affine placements must keep the entire
        // transformed footprint within the shared coordinate magnitude cap.
        if !image.hasIdentityAffineTransform {
            let limit = Double(GPUISceneLimits.maxCoordinate)
            guard bounds.minX >= -limit, bounds.minY >= -limit,
                bounds.maxX <= limit, bounds.maxY <= limit,
                bounds.size.width <= limit, bounds.size.height <= limit
            else { return nil }
        }

        self.bounds = bounds
        self.centreX = centreX
        self.centreY = centreY
        self.cosR = cosR
        self.sinR = sinR
        inverseA = d / determinant
        inverseB = -b / determinant
        inverseC = -c / determinant
        inverseD = a / determinant
        // D3D's top/left fill rule applies in world space. A reflection
        // reverses winding, so source-left can become the excluded right
        // edge. Testing only the untransformed half-open rect gets pixels
        // exactly on those reflected edges wrong.
        let winding: Double = determinant > 0 ? 1 : -1
        includesLeft = Self.isTopLeftEdge(dx: -winding * basisC, dy: -winding * basisD)
        includesRight = Self.isTopLeftEdge(dx: winding * basisC, dy: winding * basisD)
        includesTop = Self.isTopLeftEdge(dx: winding * basisA, dy: winding * basisB)
        includesBottom = Self.isTopLeftEdge(dx: -winding * basisA, dy: -winding * basisB)
    }

    func localPoint(worldX: Double, worldY: Double) -> (Double, Double) {
        let dx = worldX - centreX
        let dy = worldY - centreY
        let unrotatedX = cosR * dx + sinR * dy
        let unrotatedY = -sinR * dx + cosR * dy
        return (
            inverseA * unrotatedX + inverseC * unrotatedY + centreX,
            inverseB * unrotatedX + inverseD * unrotatedY + centreY
        )
    }

    func geometryCovers(localX: Double, localY: Double, rect: Rect) -> Bool {
        (localX > rect.minX || (includesLeft && localX == rect.minX))
            && (localX < rect.maxX || (includesRight && localX == rect.maxX))
            && (localY > rect.minY || (includesTop && localY == rect.minY))
            && (localY < rect.maxY || (includesBottom && localY == rect.maxY))
    }

    private static func isTopLeftEdge(dx: Double, dy: Double) -> Bool {
        dy < 0 || (dy == 0 && dx > 0)
    }
}

// MARK: - Shadow Primitive

/// A soft shadow rectangle, designed for direct upload to a D3D11 structured
/// buffer. Total: 20 floats = 80 bytes (divisible by 16).
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
    // Rounding of the clip rect, so a shadow inside a rounded container is
    // shaped by the container instead of squaring off at its corners.
    public var clipCornerRadius: Float
    // Rotation in radians around the centre of the *offset* rect — the
    // rect this actually draws, `(x + offsetX, y + offsetY, width,
    // height)`. 0 = axis-aligned (the historic fast path). Without it a
    // rotated card's `.shadow()` haloed the card's bounding box, which at
    // 45° is √2 too large on each axis and square where the card is
    // diamond. The soft envelope is concentric with the rect, so one angle
    // turns both. The slot used to be `_pad0`; the stride is unchanged at
    // 80 bytes.
    public var rotationRadians: Float
    // Padding to a 16-byte multiple: 18 floats round up to 20.
    public var _pad1: Float
    public var _pad2: Float

    public init(
        x: Float = 0, y: Float = 0, width: Float = 0, height: Float = 0,
        cornerRadius: Float = 0,
        colorR: Float = 0, colorG: Float = 0, colorB: Float = 0, colorA: Float = 0.5,
        blurRadius: Float = 4,
        offsetX: Float = 0, offsetY: Float = 0,
        clipX: Float = 0, clipY: Float = 0, clipWidth: Float = 0, clipHeight: Float = 0,
        clipCornerRadius: Float = 0,
        rotationRadians: Float = 0
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
        self.clipCornerRadius = clipCornerRadius
        self.rotationRadians = rotationRadians
        self._pad1 = 0
        self._pad2 = 0
    }

    public static var byteSize: Int { MemoryLayout<Self>.size }

    public var contentMask: GPUIContentMask {
        get {
            GPUIClipEncoding.contentMask(
                clipX: clipX, clipY: clipY, clipWidth: clipWidth, clipHeight: clipHeight)
        }
        set {
            GPUIClipEncoding.encode(
                newValue.bounds, into: &clipX, &clipY, &clipWidth, &clipHeight)
        }
    }
}

// MARK: - Path Primitive

/// The original coordinate frame of a path gradient, carried along with the
/// path rather than reconstructed from its current axis-aligned bounds.
///
/// Reconstructing the endpoints after a rotation would leave the colour ramp
/// upright while the covered shape turns. Keeping the two basis endpoints also
/// lets a clipped D3D11 path-cache window sample the same portion of the ramp
/// as a full CPU raster.
struct PathGradientSpace: Equatable, Sendable {
    var origin: Point
    var horizontalEnd: Point
    var verticalEnd: Point

    init(bounds: Rect) {
        origin = bounds.origin
        horizontalEnd = Point(x: bounds.maxX, y: bounds.minY)
        verticalEnd = Point(x: bounds.minX, y: bounds.maxY)
    }

    init(origin: Point, horizontalEnd: Point, verticalEnd: Point) {
        self.origin = origin
        self.horizontalEnd = horizontalEnd
        self.verticalEnd = verticalEnd
    }

    func mapped(_ transform: (Point) -> Point) -> PathGradientSpace {
        PathGradientSpace(
            origin: transform(origin),
            horizontalEnd: transform(horizontalEnd),
            verticalEnd: transform(verticalEnd))
    }
}

/// The rule used to decide which parts of a filled path are inside.
/// Stroke outlines always use their non-zero union independently of this rule.
public enum PathFillRule: Equatable, Sendable {
    case nonZero
    case evenOdd
}

/// A CPU-rasterized path with fill and/or stroke. Not designed for D3D11
/// structured buffers; the D3D11 backend tessellates or skips paths.
public struct PathPrimitive: Equatable, Sendable {
    public var elements: [PathElement]
    public var bounds: Rect
    public var fillColor: Color
    /// Optional piecewise-linear fill sampled across the path's original
    /// bounds. Its stops supersede `fillColor`, which remains the frame-path
    /// fallback and preserves compatibility with existing producers.
    public var fillGradient: LinearGradient?
    /// Defaults to the non-zero winding rule used by existing path producers.
    /// Even-odd counts crossings without depending on contour direction.
    public var fillRule: PathFillRule
    public var strokeColor: Color
    /// Optional piecewise-linear stroke sampled in the same coordinate frame
    /// as `fillGradient` rather than separately for each flattened segment.
    public var strokeGradient: LinearGradient?
    public var lineWidth: Double
    /// How the stroke ends an *open* subpath, how it turns a corner, and how
    /// long a miter may get before it degrades to a bevel.
    ///
    /// The primitive used to carry `lineWidth` and nothing else, so both
    /// stroke rasterizers had to invent the rest: the CPU coverage path
    /// butt-capped and round-joined everything, and the painter's quad
    /// tessellator square-capped everything. A `Canvas` stroke asking for
    /// `StrokeStyle(lineCap: .round)` — which is what the SF-symbol vector
    /// fallback asks for on every icon it draws — got neither.
    ///
    /// Defaults match `StrokeStyle`'s own, so a path built without an
    /// opinion renders like a `StrokeStyle` built without one.
    public var lineCap: StrokeStyle.LineCap
    public var lineJoin: StrokeStyle.LineJoin
    /// A ratio of miter length to half width, so — unlike every other scalar
    /// on this primitive — it is invariant under `scaled(by:)`.
    public var miterLimit: Double
    public var clipBounds: Rect?
    /// Rounding of `clipBounds`, so a `Shape`, `Canvas` drawing or vector icon
    /// inside a rounded container is cut by the container arc rather than by
    /// its bounding box. Logical points, scaled with everything else by
    /// `scaled(by:)`.
    public var clipCornerRadius: Double

    /// Internal because path placement owns subsequent translation, scaling
    /// and rotation; callers author explicit endpoints through
    /// `setGradientEndpoints(start:end:)`.
    var gradientSpace: PathGradientSpace?

    public init(
        elements: [PathElement],
        bounds: Rect,
        fillColor: Color = .clear,
        fillGradient: LinearGradient? = nil,
        fillRule: PathFillRule = .nonZero,
        strokeColor: Color = .clear,
        strokeGradient: LinearGradient? = nil,
        lineWidth: Double = 0,
        lineCap: StrokeStyle.LineCap = .butt,
        lineJoin: StrokeStyle.LineJoin = .miter,
        miterLimit: Double = 10,
        clipBounds: Rect? = nil,
        clipCornerRadius: Double = 0
    ) {
        self.elements = elements
        self.bounds = bounds
        self.fillColor = fillColor
        self.fillGradient = fillGradient
        self.fillRule = fillRule
        self.strokeColor = strokeColor
        self.strokeGradient = strokeGradient
        self.lineWidth = lineWidth
        self.lineCap = lineCap
        self.lineJoin = lineJoin
        self.miterLimit = miterLimit
        self.clipBounds = clipBounds
        self.clipCornerRadius = clipCornerRadius
        self.gradientSpace =
            fillGradient != nil || strokeGradient != nil ? PathGradientSpace(bounds: bounds) : nil
    }

    /// Positions the path's fill or stroke gradient along an explicitly
    /// authored segment instead of stretching it across the path bounds.
    /// Placement transforms and raster-cache identity preserve this segment.
    public mutating func setGradientEndpoints(start: Point, end: Point) {
        gradientSpace = PathGradientSpace(origin: start, horizontalEnd: end, verticalEnd: end)
    }

    /// Handles callers which assign a gradient after creating a solid path.
    var resolvedGradientSpace: PathGradientSpace? {
        guard fillGradient != nil || strokeGradient != nil else { return nil }
        return gradientSpace ?? PathGradientSpace(bounds: bounds)
    }

    /// Lowers a gradient-filled path that is already known to be exactly
    /// covered by `quad` into GPU-native directional gradient instances.
    /// Curved or combined fill/stroke paths remain eligible for the cached
    /// coverage rasterizer when they cannot be represented by one quad.
    public func gradientFillQuads(covering quad: QuadPrimitive) -> [QuadPrimitive]? {
        guard let gradient = fillGradient,
            strokeGradient == nil,
            strokeColor.alpha <= 0 || lineWidth <= 0,
            let space = resolvedGradientSpace
        else {
            return nil
        }

        let end = gradient.axis == .horizontal ? space.horizontalEnd : space.verticalEnd
        return quad.segmented(for: gradient, from: space.origin, to: end)
    }

    /// The stroke style this primitive carries, for callers that speak
    /// `StrokeStyle` (the frame path's `StrokePathCommand`, the painter's
    /// `Canvas` lowering). `dashPattern` is not part of the path contract, so
    /// it stays empty: dashes are resolved into geometry upstream, by
    /// `BorderSegments` for a rect or rounded-rect border and by
    /// ``PathDashing`` for every other outline — a `Shape` stroke, a `Canvas`
    /// `strokePath`, a frame-path stroke command.
    public var strokeStyle: StrokeStyle {
        StrokeStyle(lineWidth: lineWidth, lineCap: lineCap, lineJoin: lineJoin, miterLimit: miterLimit)
    }

    /// A digest of everything that decides what this path *looks like*: its
    /// element stream taken relative to its own `bounds` origin, its extent,
    /// and its paint. Clip state is excluded, and so is position — the digest
    /// is invariant under ``translated(by:)``.
    ///
    /// CPU-only data. Paths never cross the GPU as typed primitives (both
    /// backends rasterize them), so this stays a renderer-neutral scalar with
    /// no layout to keep in sync with HLSL.
    ///
    /// It exists so a raster cache can key on a path without *copying* one.
    /// The D3D11 path cache used to build `path.translated(by: -origin)` on
    /// every frame for every path just to have a key to hash — an element
    /// array allocated and copied per path per frame, which is precisely the
    /// work the cache was added to avoid.
    public var shapeHash: Int {
        var hasher = Hasher()
        hasher.combine(elements.count)
        hasher.combine(bounds.size.width)
        hasher.combine(bounds.size.height)
        hasher.combine(lineWidth)
        // `LineCap`/`LineJoin` are `Equatable` in Core with no `Hashable` to
        // inherit; two strokes differing only in cap are different rasters.
        hasher.combine(Self.discriminator(lineCap))
        hasher.combine(Self.discriminator(lineJoin))
        hasher.combine(miterLimit)
        Self.combine(color: fillColor, into: &hasher)
        Self.combine(gradient: fillGradient, into: &hasher)
        hasher.combine(fillRule == .evenOdd)
        Self.combine(color: strokeColor, into: &hasher)
        Self.combine(gradient: strokeGradient, into: &hasher)
        let originX = bounds.origin.x
        let originY = bounds.origin.y
        if let gradientSpace = resolvedGradientSpace {
            hasher.combine(true)
            Self.combine(point: gradientSpace.origin, originX: originX, originY: originY, into: &hasher)
            Self.combine(point: gradientSpace.horizontalEnd, originX: originX, originY: originY, into: &hasher)
            Self.combine(point: gradientSpace.verticalEnd, originX: originX, originY: originY, into: &hasher)
        } else {
            hasher.combine(false)
        }
        for element in elements {
            Self.combine(element: element, originX: originX, originY: originY, into: &hasher)
        }
        return hasher.finalize()
    }

    /// Exact structural comparison of shape and paint against `other` shifted
    /// by `offset`, without materializing the shifted copy.
    ///
    /// The tie-break behind ``shapeHash``: a digest collision must cost one
    /// comparison, never a wrong texture. Clip state is deliberately not
    /// compared — a raster cache strips it, because the clip rides along as a
    /// draw parameter rather than baking into the pixels.
    public func matchesShapeAndPaint(of other: PathPrimitive, translatedBy offset: Point) -> Bool {
        guard elements.count == other.elements.count,
            lineWidth == other.lineWidth,
            lineCap == other.lineCap,
            lineJoin == other.lineJoin,
            miterLimit == other.miterLimit,
            fillColor == other.fillColor,
            fillGradient == other.fillGradient,
            fillRule == other.fillRule,
            strokeColor == other.strokeColor,
            strokeGradient == other.strokeGradient,
            bounds.size.width == other.bounds.size.width,
            bounds.size.height == other.bounds.size.height,
            bounds.origin.x == other.bounds.origin.x + offset.x,
            bounds.origin.y == other.bounds.origin.y + offset.y
        else { return false }
        switch (resolvedGradientSpace, other.resolvedGradientSpace) {
        case (let lhs?, let rhs?):
            guard Self.matches(lhs.origin, rhs.origin, offset: offset),
                Self.matches(lhs.horizontalEnd, rhs.horizontalEnd, offset: offset),
                Self.matches(lhs.verticalEnd, rhs.verticalEnd, offset: offset)
            else { return false }
        case (nil, nil):
            break
        default:
            return false
        }
        for index in elements.indices {
            guard Self.matches(elements[index], other.elements[index], offset: offset) else {
                return false
            }
        }
        return true
    }

    private static func discriminator(_ cap: StrokeStyle.LineCap) -> Int {
        switch cap {
        case .butt: return 0
        case .round: return 1
        case .square: return 2
        }
    }

    private static func discriminator(_ join: StrokeStyle.LineJoin) -> Int {
        switch join {
        case .miter: return 0
        case .round: return 1
        case .bevel: return 2
        }
    }

    private static func combine(color: Color, into hasher: inout Hasher) {
        hasher.combine(color.red)
        hasher.combine(color.green)
        hasher.combine(color.blue)
        hasher.combine(color.alpha)
    }

    private static func combine(gradient: LinearGradient?, into hasher: inout Hasher) {
        guard let gradient else {
            hasher.combine(false)
            return
        }
        hasher.combine(true)
        hasher.combine(gradient.axis == .horizontal)
        hasher.combine(gradient.reversesAuthoredStops)
        hasher.combine(gradient.stops.count)
        for stop in gradient.stops {
            hasher.combine(stop.position)
            combine(color: stop.color, into: &hasher)
        }
    }

    private static func combine(
        point: Point, originX: Double, originY: Double, into hasher: inout Hasher
    ) {
        hasher.combine(point.x - originX)
        hasher.combine(point.y - originY)
    }

    private static func combine(
        element: PathElement, originX: Double, originY: Double, into hasher: inout Hasher
    ) {
        func combine(_ point: Point) {
            hasher.combine(point.x - originX)
            hasher.combine(point.y - originY)
        }
        switch element {
        case .moveTo(let point):
            hasher.combine(0)
            combine(point)
        case .lineTo(let point):
            hasher.combine(1)
            combine(point)
        case .quadraticCurveTo(let control, let end):
            hasher.combine(2)
            combine(control)
            combine(end)
        case .cubicCurveTo(let control1, let control2, let end):
            hasher.combine(3)
            combine(control1)
            combine(control2)
            combine(end)
        case .arc(let centre, let radius, let startAngle, let endAngle, let clockwise):
            hasher.combine(4)
            combine(centre)
            hasher.combine(radius)
            hasher.combine(startAngle)
            hasher.combine(endAngle)
            hasher.combine(clockwise)
        case .close:
            hasher.combine(5)
        }
    }

    private static func matches(_ lhs: PathElement, _ rhs: PathElement, offset: Point) -> Bool {
        func same(_ shifted: Point, _ unshifted: Point) -> Bool {
            Self.matches(shifted, unshifted, offset: offset)
        }
        switch (lhs, rhs) {
        case (.moveTo(let a), .moveTo(let b)):
            return same(a, b)
        case (.lineTo(let a), .lineTo(let b)):
            return same(a, b)
        case (.quadraticCurveTo(let ac, let ae), .quadraticCurveTo(let bc, let be)):
            return same(ac, bc) && same(ae, be)
        case (.cubicCurveTo(let a1, let a2, let ae), .cubicCurveTo(let b1, let b2, let be)):
            return same(a1, b1) && same(a2, b2) && same(ae, be)
        case (
            .arc(let ac, let ar, let as1, let ae1, let acw),
            .arc(let bc, let br, let bs1, let be1, let bcw)
        ):
            return same(ac, bc) && ar == br && as1 == bs1 && ae1 == be1 && acw == bcw
        case (.close, .close):
            return true
        default:
            return false
        }
    }

    private static func matches(_ lhs: Point, _ rhs: Point, offset: Point) -> Bool {
        lhs.x == rhs.x + offset.x && lhs.y == rhs.y + offset.y
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

    /// The same acceptance rule the four float-clip families apply (see
    /// `contentMaskedBounds(x:y:width:height:…)` in `GPUIScene.swift`): a
    /// clip that misses the path entirely rejects it. This used to fall
    /// back to the *unclipped* bounds, so a path outside its clip was
    /// still accepted — it burned a paint operation, a cached path
    /// texture and a draw call, and left "who decides visibility" as the
    /// one question answered per family instead of by the contract.
    ///
    /// What it does *not* share is those families' in-band "collapsed in
    /// both dimensions means unclipped" sentinel, which they need only
    /// because four floats cannot express absence.
    public var contentMaskedBounds: Rect? {
        guard !bounds.isEmpty else { return nil }
        // `clipBounds` is an Optional, so `nil` already says "unclipped".
        // The four float-clip families need an in-band sentinel — collapsed
        // in *both* dimensions means "no clip" — precisely because they
        // cannot express absence; importing that sentinel here made a
        // present, collapsed clip mean the opposite of what it says. A path
        // under a `clipsToBounds` node whose frame collapsed to 0×0 is
        // clipped away, not unclipped.
        guard let clip = clipBounds else { return bounds }
        guard clip.size.width > 0, clip.size.height > 0 else { return nil }

        guard let masked = bounds.intersected(with: clip) else { return nil }
        guard masked.size.width > 0, masked.size.height > 0 else { return nil }
        return masked
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

        var result = PathPrimitive(
            elements: translatedElements,
            bounds: translatedBounds,
            fillColor: fillColor,
            fillGradient: fillGradient,
            fillRule: fillRule,
            strokeColor: strokeColor,
            strokeGradient: strokeGradient,
            lineWidth: lineWidth,
            lineCap: lineCap,
            lineJoin: lineJoin,
            miterLimit: miterLimit,
            clipBounds: translatedClip,
            clipCornerRadius: clipCornerRadius
        )
        result.gradientSpace = resolvedGradientSpace?.mapped {
            Point(x: $0.x + offset.x, y: $0.y + offset.y)
        }
        return result
    }

    /// Returns a new path with every coordinate — elements, bounds, clip
    /// bounds and line width — multiplied by `factor`.
    ///
    /// Paths are the one primitive family that used to reach a backend in
    /// *logical* points: quads, glyphs, images and shadows are all
    /// converted with the painter's `scaleRect(_:by: displayScale)` while
    /// `addPath` received the geometry unscaled, so on a 150 % display
    /// every `Shape` background, `Canvas` drawing and vector icon rendered
    /// at 1/1.5 size anchored toward the window origin. The conversion
    /// belongs on the primitive (GPUI does the same with `Path::scale`)
    /// so there is exactly one place left to forget it.
    public func scaled(by factor: Double) -> PathPrimitive {
        guard factor != 1 else { return self }

        func scale(_ point: Point) -> Point {
            Point(x: point.x * factor, y: point.y * factor)
        }

        let scaledElements = elements.map { element -> PathElement in
            switch element {
            case .moveTo(let p):
                return .moveTo(scale(p))
            case .lineTo(let p):
                return .lineTo(scale(p))
            case .quadraticCurveTo(let c, let e):
                return .quadraticCurveTo(control: scale(c), end: scale(e))
            case .cubicCurveTo(let c1, let c2, let e):
                return .cubicCurveTo(control1: scale(c1), control2: scale(c2), end: scale(e))
            case .arc(let c, let r, let s, let e, let cw):
                // A uniform scale moves the centre and grows the radius;
                // the sweep angles are scale-invariant.
                return .arc(center: scale(c), radius: r * factor, startAngle: s, endAngle: e, clockwise: cw)
            case .close:
                return .close
            }
        }

        var result = PathPrimitive(
            elements: scaledElements,
            bounds: bounds.scaled(by: factor),
            fillColor: fillColor,
            fillGradient: fillGradient,
            fillRule: fillRule,
            strokeColor: strokeColor,
            strokeGradient: strokeGradient,
            lineWidth: lineWidth * factor,
            lineCap: lineCap,
            lineJoin: lineJoin,
            // A ratio, not a length: scaling both the miter and the width
            // leaves the limit it is measured against unchanged.
            miterLimit: miterLimit,
            clipBounds: clipBounds.map { $0.scaled(by: factor) },
            clipCornerRadius: clipCornerRadius * factor
        )
        result.gradientSpace = resolvedGradientSpace?.mapped(scale)
        return result
    }

    /// Returns a new path with every element turned by `radians` about
    /// `pivot`, and `bounds` widened to the axis-aligned footprint of the
    /// turned rect.
    ///
    /// This is how a `Shape` background, a `Canvas` drawing or a vector icon
    /// under a `.rotationEffect` reaches the raster turned. Paths never cross
    /// the GPU as typed primitives — both backends rasterize them — so there
    /// is no `rotationRadians` field to carry the angle to a shader the way
    /// the quad, glyph, image and shadow families do. Transforming the
    /// *elements* is the honest lowering: the coverage rasterizer then simply
    /// covers the turned geometry, strokes join and cap along it, and the
    /// path-texture caches re-key naturally because `shapeHash` digests the
    /// element stream.
    ///
    /// What is deliberately **not** rotated:
    ///
    /// - `clipBounds` and `clipCornerRadius`. The scene contract's clip is an
    ///   axis-aligned screen-space rect for every family; the caller has
    ///   already narrowed it in that space and rotating it here would put the
    ///   path's clip in a space no other primitive shares.
    /// - `lineWidth` and `miterLimit`. A rotation is rigid, so a stroke keeps
    ///   its width.
    ///
    /// `bounds` becomes the footprint of the *rotated bounds rect* rather
    /// than a fresh scan of the turned elements: rotation is rigid and the
    /// elements were inside `bounds`, so the turned elements are inside the
    /// turned rect, and both CPU raster windows (`drawPath`, the D3D11 path
    /// cache) stay conservative without an extra pass over the geometry.
    public func rotated(by radians: Double, about pivot: Point) -> PathPrimitive {
        guard radians != 0, radians.isFinite, pivot.x.isFinite, pivot.y.isFinite else { return self }
        let cosR = cos(radians)
        let sinR = sin(radians)

        func turn(_ point: Point) -> Point {
            let dx = point.x - pivot.x
            let dy = point.y - pivot.y
            return Point(x: pivot.x + cosR * dx - sinR * dy, y: pivot.y + sinR * dx + cosR * dy)
        }

        let turnedElements = elements.map { element -> PathElement in
            switch element {
            case .moveTo(let p):
                return .moveTo(turn(p))
            case .lineTo(let p):
                return .lineTo(turn(p))
            case .quadraticCurveTo(let c, let e):
                return .quadraticCurveTo(control: turn(c), end: turn(e))
            case .cubicCurveTo(let c1, let c2, let e):
                return .cubicCurveTo(control1: turn(c1), control2: turn(c2), end: turn(e))
            case .arc(let c, let r, let s, let e, let cw):
                // A point on the arc is `centre + r·(cos φ, sin φ)`, so
                // turning it by θ is the same point at `φ + θ` about the
                // turned centre: the radius and the sweep direction are
                // rotation-invariant, both endpoints shift by the angle.
                return .arc(
                    center: turn(c), radius: r, startAngle: s + radians, endAngle: e + radians, clockwise: cw)
            case .close:
                return .close
            }
        }

        let turnedCentre = turn(Point(x: bounds.midX, y: bounds.midY))
        let halfWidth = (abs(cosR) * bounds.size.width + abs(sinR) * bounds.size.height) * 0.5
        let halfHeight = (abs(sinR) * bounds.size.width + abs(cosR) * bounds.size.height) * 0.5

        var result = PathPrimitive(
            elements: turnedElements,
            bounds: Rect(
                x: turnedCentre.x - halfWidth,
                y: turnedCentre.y - halfHeight,
                width: halfWidth * 2,
                height: halfHeight * 2
            ),
            fillColor: fillColor,
            fillGradient: fillGradient,
            fillRule: fillRule,
            strokeColor: strokeColor,
            strokeGradient: strokeGradient,
            lineWidth: lineWidth,
            lineCap: lineCap,
            lineJoin: lineJoin,
            miterLimit: miterLimit,
            clipBounds: clipBounds,
            clipCornerRadius: clipCornerRadius
        )
        result.gradientSpace = resolvedGradientSpace?.mapped(turn)
        return result
    }
}
