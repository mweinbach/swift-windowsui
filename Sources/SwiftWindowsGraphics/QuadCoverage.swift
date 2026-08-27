import Foundation
import SwiftWindowsCore

/// The one Swift transcription of the D3D11 quad shaders' coverage math.
///
/// There are exactly two implementations of "how much of this pixel does a
/// rounded rect cover": `roundedRectDistance` + `saturate(0.5 - d/aa)` in
/// `BatchShaders.swift`, and this. Every CPU rasterizer call site — quad
/// body, rounded clip, shadow envelope — goes through here, so a
/// divergence between the backends is one edit apart rather than four.
///
/// Three things this deliberately does *not* simplify away:
///
/// - **There is no `radius == 0` short circuit.** The rasterizer used to
///   answer square quads with `rect.contains(pixelCentre) ? 1 : 0`, which
///   is a whole antialiasing model the shipping shader does not have: the
///   HLSL runs the same box SDF for radius 0 as for radius 18. Every
///   divider, border segment and un-rounded control background was
///   therefore snapped to whole pixels in the reference render and
///   feathered on screen.
/// - **`aa` is `fwidth(distance)` as the hardware measures it**: a finite
///   difference across the 2×2 pixel quad the pixel belongs to, not an
///   analytic gradient. The two agree wherever the distance field is
///   smooth across that quad and part company where it is not — along a
///   corner arc, on a rotated edge, and most sharply on a primitive
///   thinner than the derivative quad, where the box SDF's `max` picks a
///   different axis in the helper pixel than in the covered one. Sampling
///   the three points the hardware samples costs two extra distance
///   evaluations and removes the whole class.
/// - **The rasterizer's own coverage rule is part of the model.** A pixel
///   shader only runs where the geometry covers the pixel centre, so the
///   shipping antialiasing is a *half* ramp: alpha falls from 1 to 0.5
///   across the last half pixel inside the quad and is cut to 0 outside
///   it. Evaluating the SDF over an outward-rounded scan window instead
///   paints an outward half-ramp the GPU has no way to draw.
public enum GPUIQuadCoverage {

    /// Per-corner radii in y-down pixel space, matching the shader's
    /// `float4 cornerRadii` (x=topLeft, y=topRight, z=bottomRight,
    /// w=bottomLeft).
    public struct CornerRadii: Equatable, Sendable {
        public var topLeft: Double
        public var topRight: Double
        public var bottomRight: Double
        public var bottomLeft: Double

        public init(topLeft: Double, topRight: Double, bottomRight: Double, bottomLeft: Double) {
            self.topLeft = topLeft
            self.topRight = topRight
            self.bottomRight = bottomRight
            self.bottomLeft = bottomLeft
        }

        public init(uniform radius: Double) {
            self.init(topLeft: radius, topRight: radius, bottomRight: radius, bottomLeft: radius)
        }
    }

    /// `roundedRectDistance(localPosition, size, cornerRadii)`.
    ///
    /// `localX`/`localY` are relative to the rect's origin, exactly as the
    /// vertex stage hands `localPosition` to the pixel stage.
    public static func signedDistance(
        localX: Double,
        localY: Double,
        width: Double,
        height: Double,
        radii: CornerRadii
    ) -> Double {
        let halfWidth = width * 0.5
        let halfHeight = height * 0.5
        let pointX = localX - halfWidth
        let pointY = localY - halfHeight
        let radius =
            pointX > 0
            ? (pointY > 0 ? radii.bottomRight : radii.topRight)
            : (pointY > 0 ? radii.bottomLeft : radii.topLeft)
        // No `max(_, 0)`: the shader has none either, and the scene
        // sanitizer is what keeps negative radii out of the contract.
        let clampedRadius = min(radius, min(halfWidth, halfHeight))
        let cornerX = max(halfWidth - clampedRadius, 0)
        let cornerY = max(halfHeight - clampedRadius, 0)
        let deltaX = abs(pointX) - cornerX
        let deltaY = abs(pointY) - cornerY
        let outsideX = max(deltaX, 0)
        let outsideY = max(deltaY, 0)
        let outside = (outsideX * outsideX + outsideY * outsideY).squareRoot()
        let inside = min(max(deltaX, deltaY), 0)
        return outside + inside - clampedRadius
    }

    /// The rasterizer's coverage rule for a primitive's own geometry: the
    /// pixel shader runs only where a pixel centre falls inside the rect,
    /// top-left inclusive. Callers evaluate this in the primitive's local
    /// space, which is the rotated footprint in world space.
    public static func geometryCovers(localX: Double, localY: Double, rect: Rect) -> Bool {
        localX >= rect.minX && localX < rect.maxX && localY >= rect.minY && localY < rect.maxY
    }

    /// `saturate(0.5 - distance / max(fwidth(distance), 0.75))` for the
    /// pixel at `(pixelX, pixelY)`.
    ///
    /// `distanceAt` is handed *surface* coordinates and returns the signed
    /// distance there, so a rotated primitive's caller folds the inverse
    /// rotation into the closure and the finite difference is taken in
    /// screen space — exactly where `fwidth` takes it.
    ///
    /// `extraEdgeSoftness` is the plain quad shader's
    /// `edgeSoftness = aa + blurRadius * 2` term, which only ever applies
    /// to sub-pixel blur radii: anything that truncates to ≥ 1 is routed
    /// to the material/backdrop path on both backends.
    public static func coverage(
        pixelX: Int,
        pixelY: Int,
        extraEdgeSoftness: Double = 0,
        distanceAt: (Double, Double) -> Double
    ) -> Double {
        // Derivative quads are aligned to even pixel coordinates.
        let baseX = Double(pixelX & ~1) + 0.5
        let baseY = Double(pixelY & ~1) + 0.5
        let base = distanceAt(baseX, baseY)
        let edgeWidth = max(
            abs(distanceAt(baseX + 1, baseY) - base) + abs(distanceAt(baseX, baseY + 1) - base), 0.75)

        let centreX = Double(pixelX) + 0.5
        let centreY = Double(pixelY) + 0.5
        let distance = (centreX == baseX && centreY == baseY) ? base : distanceAt(centreX, centreY)

        let softness = edgeWidth + max(extraEdgeSoftness, 0)
        guard softness > 0 else {
            return distance <= 0 ? 1 : 0
        }
        return min(max(0.5 - distance / softness, 0), 1)
    }

    /// HLSL `smoothstep(edge0, edge1, x)`.
    public static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        guard edge1 > edge0 else {
            return x < edge0 ? 0 : 1
        }
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }
}

/// A primitive's four float clip fields read as one value, with the
/// shader's acceptance rule attached.
///
/// Every quad-family pixel shader starts with the same three lines: a
/// clip is active when its width and height are both positive; a pixel
/// whose *centre* falls outside the float rect is discarded; a positive
/// clip corner radius contributes an antialiased `clipAlpha` that
/// multiplies the output rather than gating it. The CPU rasterizer used
/// to do neither — it relied on the outward-rounded integer scan window
/// (a systematic 1 px bleed at fractional DPI) and threw the rounded
/// coverage away after computing it (hard-edged card corners in every
/// screenshot).
public struct GPUIClipRegion: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var cornerRadius: Double

    public init(x: Double, y: Double, width: Double, height: Double, cornerRadius: Double = 0) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }

    public init(x: Float, y: Float, width: Float, height: Float, cornerRadius: Float = 0) {
        self.init(
            x: Double(x), y: Double(y), width: Double(width), height: Double(height),
            cornerRadius: Double(cornerRadius))
    }

    /// The shader's `input.clipRect.z > 0.0 && input.clipRect.w > 0.0`.
    public var isActive: Bool { width > 0 && height > 0 }

    /// The rect this clip restricts drawing to, or `nil` when inactive —
    /// what the rasterizer intersects to pick its scan window.
    public var rect: Rect? {
        guard isActive else { return nil }
        return Rect(x: x, y: y, width: width, height: height)
    }

    /// `clipAlpha` for a pixel: `0` means the shader would have
    /// discarded, anything else multiplies the primitive's alpha.
    public func alpha(atPixelX pixelX: Int, y pixelY: Int) -> Double {
        guard isActive else { return 1 }
        let centreX = Double(pixelX) + 0.5
        let centreY = Double(pixelY) + 0.5
        // Match the shader and the geometry's top-left fill rule. Including
        // the far edge lets adjacent scroll clips both paint the shared row
        // when that boundary lands on a pixel centre at fractional DPI.
        if centreX < x || centreY < y || centreX >= x + width || centreY >= y + height {
            return 0
        }
        guard cornerRadius > 0 else { return 1 }
        let radii = GPUIQuadCoverage.CornerRadii(uniform: cornerRadius)
        return GPUIQuadCoverage.coverage(pixelX: pixelX, pixelY: pixelY) { sampleX, sampleY in
            GPUIQuadCoverage.signedDistance(
                localX: sampleX - x, localY: sampleY - y, width: width, height: height, radii: radii)
        }
    }
}
