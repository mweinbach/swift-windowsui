import Foundation
import SwiftWindowsCore

// MARK: - Limits

/// Magnitude and structural limits the scene contract enforces at the
/// `GPUIScene.add*` boundary.
///
/// Everything downstream of `add*` — both render backends, the CPU
/// rasterizer, the path-texture cache — assumes primitive fields are
/// finite and small enough that a `Float → Int` conversion is safe.
/// Nothing upstream guarantees it: `.blur(radius: a / b)` with `b == 0`,
/// a frame that collapses to NaN during layout, or an animation that
/// interpolates through infinity all reach `add*` from ordinary app
/// code. A Swift conversion trap is a *process kill*, not a thrown
/// error, so it is the one failure class the host's fallback policy
/// cannot degrade — hence sanitation here, once, where both backends
/// inherit it.
///
/// These are **shared engine limits, not backend capabilities**. Each one
/// bounds what this engine promises to draw at all — every backend, the
/// CPU rasterizer included, honours the same number, so a scene renders
/// the same everywhere rather than being truncated differently by each
/// consumer. Where a number happens to coincide with a D3D11 maximum that
/// is a floor the engine chose to live inside, not a capability read off
/// the device. Asking the *device* what it can do — feature level, real
/// maximum texture dimension, per-adapter kernel budgets — is a backend
/// capability record, which is WS-20; when that lands, a backend that can
/// do less than the engine limit reports it there rather than silently
/// clamping, and this enum keeps only what representability requires.
public enum GPUISceneLimits {
    /// Largest absolute pixel coordinate (position, size, corner radius)
    /// a primitive may carry. Far beyond any real surface, small enough
    /// that every downstream `Int` conversion and area computation stays
    /// in range.
    public static let maxCoordinate: Float = 1_000_000

    /// Largest post-process (backdrop) blur radius, in *device* pixels.
    /// Every consumer honours it — the D3D11 backdrop blur engine sizes its
    /// weight cbuffer to exactly this radius — so the backends agree above
    /// the cap instead of each truncating somewhere else, and the CPU
    /// rasterizer's O(w·h·r) separable blur is bounded rather than
    /// unbounded.
    ///
    /// 256 rather than 128 because the painter emits
    /// `radius × displayScale`: at 128 a `.blur(radius: 100)` was silently
    /// sharpened on any 1.5× or 2× display, which is where this stack
    /// mostly runs. 256 covers a 128pt blur at 2× — past any decorative
    /// use — and costs the GPU one more cbuffer page.
    public static let maxBlurRadius: Float = 256

    /// Largest shadow blur radius. Shadows only inflate a rect, so the
    /// bound is looser than the backdrop-blur one.
    public static let maxShadowBlurRadius: Float = 1024

    /// Largest absolute texture-space coordinate (atlas UVs, image UVs).
    /// Generous enough for tiling, tight enough that `uv * textureSize`
    /// cannot overflow an `Int` conversion.
    public static let maxTextureCoordinate: Float = 64

    /// Largest number of path elements a single `PathPrimitive` may
    /// carry. The scanline fill is O(segments) per row, so an unbounded
    /// element list is an unbounded frame.
    public static let maxPathElements = 65_536

    /// Largest number of layers a scene may hold. `ensureLayer` grew the
    /// array to whatever index it was handed, so one bad (or stale
    /// replayed) index was an unbounded allocation loop.
    public static let maxLayers = 256

    /// Largest CPU-rasterizer surface dimension. The engine draws no
    /// surface larger than this on any backend; past it the backing
    /// allocation is the failure, not the drawing. The number is the
    /// feature-level 11 texture maximum because that is the smallest
    /// ceiling any supported backend imposes, so one shared limit keeps
    /// the CPU reference and the GPU path drawing the same surfaces.
    public static let maxSurfaceDimension = 16_384

    /// Bounds scratch surfaces and recursive image passes independently of
    /// the main window. Requests above these limits are explicit scene defects.
    public static let maxImageRenderPassPixels = 4_194_304
    /// Cumulative source pixels across one scene graph or render execution.
    /// Backdrop isolation additionally reserves its bounded scratch planes.
    /// At BGRA8 this is 64 MiB of accounted pixel payload, not a total-memory
    /// bound: ordinary filter outputs, CPU conversion scratch and other
    /// renderer resources have separate lifetimes outside this count.
    public static let maxImageRenderPassTotalPixels = 16_777_216
    public static let maxImageRenderPassDepth = 32
    /// Also bound branching graphs: a shallow value graph can share child
    /// arrays while expanding into exponentially many renderer passes.
    public static let maxImageRenderPassCount = 1_024
    public static let maxColorEffects = 256

    /// Largest number of flattening recursions a single curve may take.
    /// The flatness test compares against NaN forever when a control
    /// point is non-finite, so the depth cap — not the flatness test —
    /// is what guarantees termination.
    public static let maxCurveFlatteningDepth = 24

    /// Largest number of line segments a single arc may flatten into.
    public static let maxArcSegments = 4_096
}

// MARK: - Saturating conversions

/// Conversions and clamps that saturate where Swift traps.
///
/// `Int(_: Float)` is a fatal error on NaN and on anything outside
/// `Int`'s range. Every scene-derived conversion in the stack goes
/// through `GPUISceneValue.int` instead, so a malformed scene renders
/// wrong rather than killing the process.
public enum GPUISceneValue {
    /// Saturation bound for `int(_:)`. Every consumer is a pixel index, a
    /// kernel radius or a byte offset, all far inside `Int32`.
    public static let intBound = Int(Int32.max)

    /// Truncating `Double → Int` that saturates instead of trapping.
    /// NaN maps to 0; ±infinity and out-of-range magnitudes map to
    /// ∓`intBound`.
    @inline(__always)
    public static func int(_ value: Double) -> Int {
        guard value.isFinite else {
            if value.isNaN { return 0 }
            return value < 0 ? -intBound : intBound
        }
        if value >= Double(intBound) { return intBound }
        if value <= Double(-intBound) { return -intBound }
        return Int(value)
    }

    /// Truncating `Float → Int` that saturates instead of trapping.
    @inline(__always)
    public static func int(_ value: Float) -> Int {
        int(Double(value))
    }

    /// Clamps `value` into `[-limit, limit]`, mapping NaN to 0. Finite
    /// in-range values are returned bit-identical (including `-0.0`), so
    /// sanitation never perturbs a well-formed scene.
    @inline(__always)
    public static func clamped(_ value: Float, to limit: Float) -> Float {
        guard value.isFinite else {
            if value.isNaN { return 0 }
            return value < 0 ? -limit : limit
        }
        if value > limit { return limit }
        if value < -limit { return -limit }
        return value
    }

    /// Clamps `value` into `[lower, upper]`, mapping NaN to `lower`.
    @inline(__always)
    public static func clamped(_ value: Float, lower: Float, upper: Float) -> Float {
        guard value.isFinite else {
            if value.isNaN { return lower }
            return value < 0 ? lower : upper
        }
        if value > upper { return upper }
        if value < lower { return lower }
        return value
    }

    /// Same as `clamped(_:to:)` for `Double` path geometry.
    @inline(__always)
    public static func clamped(_ value: Double, to limit: Double) -> Double {
        guard value.isFinite else {
            if value.isNaN { return 0 }
            return value < 0 ? -limit : limit
        }
        if value > limit { return limit }
        if value < -limit { return -limit }
        return value
    }
}

// MARK: - Primitive sanitation

/// The scene contract's sanitation pass. Each entry point returns a
/// primitive whose fields are finite and in range, or `nil` when the
/// primitive cannot be placed at all (non-finite geometry, or a clip
/// whose extent is unknowable — in which case dropping it is the only
/// answer that cannot let content escape its clip).
///
/// Sanitation is an identity transform for well-formed primitives: every
/// clamp returns finite in-range inputs unchanged, so accepted scenes
/// stay byte-identical.
public enum GPUISceneSanitizer {
    private static let coordinateLimit = GPUISceneLimits.maxCoordinate

    /// Clip fields are all-or-nothing: a non-finite clip extent means the
    /// visible region is unknown, and rendering unclipped would paint the
    /// subtree across the whole window.
    ///
    /// `clipCornerRadius` is deliberately not part of this test — an
    /// unrepresentable *rounding* still leaves the rejection rect known — but
    /// it is not exempt from sanitation either: every family clamps it into
    /// `[0, coordinateLimit]` (NaN and negatives become 0, i.e. a square
    /// clip), because both backends feed it straight into a signed-distance
    /// term where a NaN erases the primitive and a negative inverts the arc.
    @inline(__always)
    private static func clipIsRepresentable(_ x: Float, _ y: Float, _ width: Float, _ height: Float) -> Bool {
        x.isFinite && y.isFinite && width.isFinite && height.isFinite
    }

    /// All-zero shape fields mean dynamic fallback to R. Every other shape
    /// must remain finite and nonempty, even when the rejection clip is absent.
    @inline(__always)
    private static func clipShapeIsRepresentable(_ x: Float, _ y: Float, _ width: Float, _ height: Float) -> Bool {
        guard clipIsRepresentable(x, y, width, height) else { return false }
        return GPUIClipEncoding.isAbsent(clipX: x, clipY: y, clipWidth: width, clipHeight: height)
            || (width > 0 && height > 0)
    }

    public static func sanitized(_ quad: QuadPrimitive) -> QuadPrimitive? {
        guard quad.x.isFinite, quad.y.isFinite, quad.width.isFinite, quad.height.isFinite else {
            return nil
        }
        guard clipIsRepresentable(quad.clipX, quad.clipY, quad.clipWidth, quad.clipHeight) else {
            return nil
        }
        guard
            clipShapeIsRepresentable(
                quad.clipShapeX, quad.clipShapeY, quad.clipShapeWidth, quad.clipShapeHeight)
        else { return nil }

        var result = quad
        result.x = GPUISceneValue.clamped(quad.x, to: coordinateLimit)
        result.y = GPUISceneValue.clamped(quad.y, to: coordinateLimit)
        result.width = GPUISceneValue.clamped(quad.width, to: coordinateLimit)
        result.height = GPUISceneValue.clamped(quad.height, to: coordinateLimit)
        result.cornerRadius = GPUISceneValue.clamped(quad.cornerRadius, lower: 0, upper: coordinateLimit)
        result.cornerRadiusTopLeft = GPUISceneValue.clamped(quad.cornerRadiusTopLeft, lower: 0, upper: coordinateLimit)
        result.cornerRadiusTopRight = GPUISceneValue.clamped(
            quad.cornerRadiusTopRight, lower: 0, upper: coordinateLimit)
        result.cornerRadiusBottomRight = GPUISceneValue.clamped(
            quad.cornerRadiusBottomRight, lower: 0, upper: coordinateLimit)
        result.cornerRadiusBottomLeft = GPUISceneValue.clamped(
            quad.cornerRadiusBottomLeft, lower: 0, upper: coordinateLimit)
        result.clipX = GPUISceneValue.clamped(quad.clipX, to: coordinateLimit)
        result.clipY = GPUISceneValue.clamped(quad.clipY, to: coordinateLimit)
        result.clipWidth = GPUISceneValue.clamped(quad.clipWidth, to: coordinateLimit)
        result.clipHeight = GPUISceneValue.clamped(quad.clipHeight, to: coordinateLimit)
        result.clipCornerRadius = GPUISceneValue.clamped(quad.clipCornerRadius, lower: 0, upper: coordinateLimit)
        result.clipCornerRadiusTopLeft = GPUISceneValue.clamped(
            quad.clipCornerRadiusTopLeft, lower: 0, upper: coordinateLimit)
        result.clipCornerRadiusTopRight = GPUISceneValue.clamped(
            quad.clipCornerRadiusTopRight, lower: 0, upper: coordinateLimit)
        result.clipCornerRadiusBottomRight = GPUISceneValue.clamped(
            quad.clipCornerRadiusBottomRight, lower: 0, upper: coordinateLimit)
        result.clipCornerRadiusBottomLeft = GPUISceneValue.clamped(
            quad.clipCornerRadiusBottomLeft, lower: 0, upper: coordinateLimit)
        result.clipShapeX = GPUISceneValue.clamped(quad.clipShapeX, to: coordinateLimit)
        result.clipShapeY = GPUISceneValue.clamped(quad.clipShapeY, to: coordinateLimit)
        result.clipShapeWidth = GPUISceneValue.clamped(quad.clipShapeWidth, to: coordinateLimit)
        result.clipShapeHeight = GPUISceneValue.clamped(quad.clipShapeHeight, to: coordinateLimit)
        result.startR = GPUISceneValue.clamped(quad.startR, lower: 0, upper: 1)
        result.startG = GPUISceneValue.clamped(quad.startG, lower: 0, upper: 1)
        result.startB = GPUISceneValue.clamped(quad.startB, lower: 0, upper: 1)
        result.startA = GPUISceneValue.clamped(quad.startA, lower: 0, upper: 1)
        result.endR = GPUISceneValue.clamped(quad.endR, lower: 0, upper: 1)
        result.endG = GPUISceneValue.clamped(quad.endG, lower: 0, upper: 1)
        result.endB = GPUISceneValue.clamped(quad.endB, lower: 0, upper: 1)
        result.endA = GPUISceneValue.clamped(quad.endA, lower: 0, upper: 1)
        // Advanced gradient modes borrow all four color-effect parameters for
        // their authored geometry. Accept only exact, effect-free selectors
        // with representable parameters; malformed values retain the original
        // vertical/horizontal degradation instead of reinterpreting a live
        // effect or non-finite data as geometry. Directional endpoints are in
        // surface space before placement and therefore still reject rotation;
        // radial/conic geometry is quad-local and rotates with its footprint.
        let parametersRepresentable =
            quad.effectParam1.isFinite && abs(quad.effectParam1) <= coordinateLimit
            && quad.effectParam2.isFinite && abs(quad.effectParam2) <= coordinateLimit
            && quad.effectParam3.isFinite && abs(quad.effectParam3) <= coordinateLimit
            && quad.effectParam4.isFinite && abs(quad.effectParam4) <= coordinateLimit
        let isDirectional = quad.gradientAxis == 2 && quad.rotationRadians == 0
        let isPolar = quad.gradientAxis == 3 || quad.gradientAxis == 4
        result.gradientAxis =
            (isDirectional || isPolar) && quad.effectType == 0 && parametersRepresentable
            ? quad.gradientAxis
            : GPUISceneValue.clamped(quad.gradientAxis, lower: 0, upper: 1)
        result.gradientSegmentStart = GPUISceneValue.clamped(quad.gradientSegmentStart, lower: 0, upper: 1)
        result.gradientSegmentEnd = GPUISceneValue.clamped(quad.gradientSegmentEnd, lower: 0, upper: 1)
        result.gradientSegmentMode = GPUISceneValue.clamped(quad.gradientSegmentMode, lower: 0, upper: 2)
        // Admission clamps both selector ranges. Effects keep their encoded
        // dispatch; ordinary blend dispatch requires exact values 1...4, so
        // fractional blend encodings retain normal source-over behavior.
        result.effectType = GPUISceneValue.clamped(quad.effectType, lower: 0, upper: 8)
        result.blendMode = GPUISceneValue.clamped(quad.blendMode, lower: 0, upper: 4)
        result.effectIntensity = GPUISceneValue.clamped(quad.effectIntensity, to: coordinateLimit)
        result.effectParam1 = GPUISceneValue.clamped(quad.effectParam1, to: coordinateLimit)
        result.effectParam2 = GPUISceneValue.clamped(quad.effectParam2, to: coordinateLimit)
        result.effectParam3 = GPUISceneValue.clamped(quad.effectParam3, to: coordinateLimit)
        result.effectParam4 = GPUISceneValue.clamped(quad.effectParam4, to: coordinateLimit)
        result.blurRadius = GPUISceneValue.clamped(quad.blurRadius, lower: 0, upper: GPUISceneLimits.maxBlurRadius)
        result.blurOpaque = GPUISceneValue.clamped(quad.blurOpaque, lower: 0, upper: 1)
        // A non-finite rotation would make the rotated footprint (and so
        // the blur region and the scan bounds) NaN; unrotated is the
        // degradation both backends already handle.
        result.rotationRadians = quad.rotationRadians.isFinite ? quad.rotationRadians : 0
        return result
    }

    public static func sanitized(_ glyph: GlyphPrimitive) -> GlyphPrimitive? {
        guard glyph.screenX.isFinite, glyph.screenY.isFinite, glyph.screenW.isFinite, glyph.screenH.isFinite else {
            return nil
        }
        guard clipIsRepresentable(glyph.clipX, glyph.clipY, glyph.clipWidth, glyph.clipHeight) else {
            return nil
        }
        guard
            clipShapeIsRepresentable(
                glyph.clipShapeX, glyph.clipShapeY, glyph.clipShapeWidth, glyph.clipShapeHeight)
        else { return nil }

        var result = glyph
        result.screenX = GPUISceneValue.clamped(glyph.screenX, to: coordinateLimit)
        result.screenY = GPUISceneValue.clamped(glyph.screenY, to: coordinateLimit)
        result.screenW = GPUISceneValue.clamped(glyph.screenW, to: coordinateLimit)
        result.screenH = GPUISceneValue.clamped(glyph.screenH, to: coordinateLimit)
        result.clipX = GPUISceneValue.clamped(glyph.clipX, to: coordinateLimit)
        result.clipY = GPUISceneValue.clamped(glyph.clipY, to: coordinateLimit)
        result.clipWidth = GPUISceneValue.clamped(glyph.clipWidth, to: coordinateLimit)
        result.clipHeight = GPUISceneValue.clamped(glyph.clipHeight, to: coordinateLimit)
        result.clipCornerRadius = GPUISceneValue.clamped(glyph.clipCornerRadius, lower: 0, upper: coordinateLimit)
        result.clipCornerRadiusTopLeft = GPUISceneValue.clamped(
            glyph.clipCornerRadiusTopLeft, lower: 0, upper: coordinateLimit)
        result.clipCornerRadiusTopRight = GPUISceneValue.clamped(
            glyph.clipCornerRadiusTopRight, lower: 0, upper: coordinateLimit)
        result.clipCornerRadiusBottomRight = GPUISceneValue.clamped(
            glyph.clipCornerRadiusBottomRight, lower: 0, upper: coordinateLimit)
        result.clipCornerRadiusBottomLeft = GPUISceneValue.clamped(
            glyph.clipCornerRadiusBottomLeft, lower: 0, upper: coordinateLimit)
        result.clipShapeX = GPUISceneValue.clamped(glyph.clipShapeX, to: coordinateLimit)
        result.clipShapeY = GPUISceneValue.clamped(glyph.clipShapeY, to: coordinateLimit)
        result.clipShapeWidth = GPUISceneValue.clamped(glyph.clipShapeWidth, to: coordinateLimit)
        result.clipShapeHeight = GPUISceneValue.clamped(glyph.clipShapeHeight, to: coordinateLimit)
        result.atlasU0 = GPUISceneValue.clamped(glyph.atlasU0, to: GPUISceneLimits.maxTextureCoordinate)
        result.atlasV0 = GPUISceneValue.clamped(glyph.atlasV0, to: GPUISceneLimits.maxTextureCoordinate)
        result.atlasU1 = GPUISceneValue.clamped(glyph.atlasU1, to: GPUISceneLimits.maxTextureCoordinate)
        result.atlasV1 = GPUISceneValue.clamped(glyph.atlasV1, to: GPUISceneLimits.maxTextureCoordinate)
        result.colorR = GPUISceneValue.clamped(glyph.colorR, lower: 0, upper: 1)
        result.colorG = GPUISceneValue.clamped(glyph.colorG, lower: 0, upper: 1)
        result.colorB = GPUISceneValue.clamped(glyph.colorB, lower: 0, upper: 1)
        result.colorA = GPUISceneValue.clamped(glyph.colorA, lower: 0, upper: 1)
        result.rotationRadians = glyph.rotationRadians.isFinite ? glyph.rotationRadians : 0
        return result
    }

    public static func sanitized(_ image: ImagePrimitive) -> ImagePrimitive? {
        guard image.screenX.isFinite, image.screenY.isFinite, image.screenW.isFinite, image.screenH.isFinite else {
            return nil
        }
        guard image.hasValidAffineMatrix else { return nil }
        guard
            image.sampling.validationFailure(
                uvX: image.uvX, uvY: image.uvY, uvW: image.uvW, uvH: image.uvH) == nil
        else { return nil }
        guard
            image.sampling.placementValidationFailure(
                rect: Rect(
                    x: Double(image.screenX), y: Double(image.screenY),
                    width: Double(image.screenW), height: Double(image.screenH))) == nil
        else { return nil }
        if !image.sampling.isLegacy && !image.rotationRadians.isFinite { return nil }
        guard clipIsRepresentable(image.clipX, image.clipY, image.clipWidth, image.clipHeight) else {
            return nil
        }
        guard
            clipShapeIsRepresentable(
                image.clipShapeX, image.clipShapeY, image.clipShapeWidth, image.clipShapeHeight)
        else { return nil }

        var result = image
        result.screenX = GPUISceneValue.clamped(image.screenX, to: coordinateLimit)
        result.screenY = GPUISceneValue.clamped(image.screenY, to: coordinateLimit)
        result.screenW = GPUISceneValue.clamped(image.screenW, to: coordinateLimit)
        result.screenH = GPUISceneValue.clamped(image.screenH, to: coordinateLimit)
        result.clipX = GPUISceneValue.clamped(image.clipX, to: coordinateLimit)
        result.clipY = GPUISceneValue.clamped(image.clipY, to: coordinateLimit)
        result.clipWidth = GPUISceneValue.clamped(image.clipWidth, to: coordinateLimit)
        result.clipHeight = GPUISceneValue.clamped(image.clipHeight, to: coordinateLimit)
        result.clipCornerRadius = GPUISceneValue.clamped(image.clipCornerRadius, lower: 0, upper: coordinateLimit)
        result.clipCornerRadiusTopLeft = GPUISceneValue.clamped(
            image.clipCornerRadiusTopLeft, lower: 0, upper: coordinateLimit)
        result.clipCornerRadiusTopRight = GPUISceneValue.clamped(
            image.clipCornerRadiusTopRight, lower: 0, upper: coordinateLimit)
        result.clipCornerRadiusBottomRight = GPUISceneValue.clamped(
            image.clipCornerRadiusBottomRight, lower: 0, upper: coordinateLimit)
        result.clipCornerRadiusBottomLeft = GPUISceneValue.clamped(
            image.clipCornerRadiusBottomLeft, lower: 0, upper: coordinateLimit)
        result.clipShapeX = GPUISceneValue.clamped(image.clipShapeX, to: coordinateLimit)
        result.clipShapeY = GPUISceneValue.clamped(image.clipShapeY, to: coordinateLimit)
        result.clipShapeWidth = GPUISceneValue.clamped(image.clipShapeWidth, to: coordinateLimit)
        result.clipShapeHeight = GPUISceneValue.clamped(image.clipShapeHeight, to: coordinateLimit)
        result.uvX = GPUISceneValue.clamped(image.uvX, to: GPUISceneLimits.maxTextureCoordinate)
        result.uvY = GPUISceneValue.clamped(image.uvY, to: GPUISceneLimits.maxTextureCoordinate)
        result.uvW = GPUISceneValue.clamped(image.uvW, to: GPUISceneLimits.maxTextureCoordinate)
        result.uvH = GPUISceneValue.clamped(image.uvH, to: GPUISceneLimits.maxTextureCoordinate)
        result.opacity = GPUISceneValue.clamped(image.opacity, lower: 0, upper: 1)
        result.rotationRadians = image.rotationRadians.isFinite ? image.rotationRadians : 0
        guard result.affinePlacementDefect == nil else { return nil }
        return result
    }

    public static func sanitized(_ shadow: ShadowPrimitive) -> ShadowPrimitive? {
        guard shadow.x.isFinite, shadow.y.isFinite, shadow.width.isFinite, shadow.height.isFinite else {
            return nil
        }
        guard shadow.offsetX.isFinite, shadow.offsetY.isFinite else {
            return nil
        }
        guard clipIsRepresentable(shadow.clipX, shadow.clipY, shadow.clipWidth, shadow.clipHeight) else {
            return nil
        }
        guard
            clipShapeIsRepresentable(
                shadow.clipShapeX, shadow.clipShapeY, shadow.clipShapeWidth, shadow.clipShapeHeight)
        else { return nil }

        var result = shadow
        result.x = GPUISceneValue.clamped(shadow.x, to: coordinateLimit)
        result.y = GPUISceneValue.clamped(shadow.y, to: coordinateLimit)
        result.width = GPUISceneValue.clamped(shadow.width, to: coordinateLimit)
        result.height = GPUISceneValue.clamped(shadow.height, to: coordinateLimit)
        result.offsetX = GPUISceneValue.clamped(shadow.offsetX, to: coordinateLimit)
        result.offsetY = GPUISceneValue.clamped(shadow.offsetY, to: coordinateLimit)
        result.cornerRadius = GPUISceneValue.clamped(shadow.cornerRadius, lower: 0, upper: coordinateLimit)
        result.blurRadius = GPUISceneValue.clamped(
            shadow.blurRadius, lower: 0, upper: GPUISceneLimits.maxShadowBlurRadius)
        result.clipX = GPUISceneValue.clamped(shadow.clipX, to: coordinateLimit)
        result.clipY = GPUISceneValue.clamped(shadow.clipY, to: coordinateLimit)
        result.clipWidth = GPUISceneValue.clamped(shadow.clipWidth, to: coordinateLimit)
        result.clipHeight = GPUISceneValue.clamped(shadow.clipHeight, to: coordinateLimit)
        result.clipCornerRadius = GPUISceneValue.clamped(shadow.clipCornerRadius, lower: 0, upper: coordinateLimit)
        result.clipCornerRadiusTopLeft = GPUISceneValue.clamped(
            shadow.clipCornerRadiusTopLeft, lower: 0, upper: coordinateLimit)
        result.clipCornerRadiusTopRight = GPUISceneValue.clamped(
            shadow.clipCornerRadiusTopRight, lower: 0, upper: coordinateLimit)
        result.clipCornerRadiusBottomRight = GPUISceneValue.clamped(
            shadow.clipCornerRadiusBottomRight, lower: 0, upper: coordinateLimit)
        result.clipCornerRadiusBottomLeft = GPUISceneValue.clamped(
            shadow.clipCornerRadiusBottomLeft, lower: 0, upper: coordinateLimit)
        result.clipShapeX = GPUISceneValue.clamped(shadow.clipShapeX, to: coordinateLimit)
        result.clipShapeY = GPUISceneValue.clamped(shadow.clipShapeY, to: coordinateLimit)
        result.clipShapeWidth = GPUISceneValue.clamped(shadow.clipShapeWidth, to: coordinateLimit)
        result.clipShapeHeight = GPUISceneValue.clamped(shadow.clipShapeHeight, to: coordinateLimit)
        result.colorR = GPUISceneValue.clamped(shadow.colorR, lower: 0, upper: 1)
        result.colorG = GPUISceneValue.clamped(shadow.colorG, lower: 0, upper: 1)
        result.colorB = GPUISceneValue.clamped(shadow.colorB, lower: 0, upper: 1)
        result.colorA = GPUISceneValue.clamped(shadow.colorA, lower: 0, upper: 1)
        result.rotationRadians = shadow.rotationRadians.isFinite ? shadow.rotationRadians : 0
        return result
    }

    public static func sanitized(_ path: PathPrimitive) -> PathPrimitive? {
        guard path.bounds.origin.x.isFinite, path.bounds.origin.y.isFinite,
            path.bounds.size.width.isFinite, path.bounds.size.height.isFinite
        else {
            return nil
        }
        if let clip = path.clipBounds {
            guard clip.origin.x.isFinite, clip.origin.y.isFinite,
                clip.size.width.isFinite, clip.size.height.isFinite
            else {
                return nil
            }
        }
        if let shape = path.clipShapeBounds {
            guard shape.origin.x.isFinite, shape.origin.y.isFinite,
                shape.size.width.isFinite, shape.size.height.isFinite,
                shape.size.width > 0, shape.size.height > 0
            else { return nil }
        }
        guard path.elements.count <= GPUISceneLimits.maxPathElements else {
            return nil
        }

        var result = path
        result.bounds = clampedRect(path.bounds)
        result.clipBounds = path.clipBounds.map(clampedRect)
        result.clipShapeBounds = path.clipShapeBounds.map(clampedRect)
        result.lineWidth = GPUISceneValue.clamped(
            path.lineWidth.isFinite ? max(0, path.lineWidth) : 0, to: Double(coordinateLimit))
        // A limit below 1 would bevel a straight run, and a non-finite one
        // reaches `1 / cos(turn/2) <= limit` as "always miter", which is an
        // unbounded spike from an app-supplied number.
        result.miterLimit =
            path.miterLimit.isFinite
            ? max(1, min(path.miterLimit, Double(coordinateLimit)))
            : 10
        result.clipCornerRadius = GPUISceneValue.clamped(
            path.clipCornerRadius.isFinite ? max(0, path.clipCornerRadius) : 0, to: Double(coordinateLimit))
        result.clipCornerRadiusTopLeft = GPUISceneValue.clamped(
            path.clipCornerRadiusTopLeft.isFinite ? max(0, path.clipCornerRadiusTopLeft) : 0,
            to: Double(coordinateLimit))
        result.clipCornerRadiusTopRight = GPUISceneValue.clamped(
            path.clipCornerRadiusTopRight.isFinite ? max(0, path.clipCornerRadiusTopRight) : 0,
            to: Double(coordinateLimit))
        result.clipCornerRadiusBottomRight = GPUISceneValue.clamped(
            path.clipCornerRadiusBottomRight.isFinite ? max(0, path.clipCornerRadiusBottomRight) : 0,
            to: Double(coordinateLimit))
        result.clipCornerRadiusBottomLeft = GPUISceneValue.clamped(
            path.clipCornerRadiusBottomLeft.isFinite ? max(0, path.clipCornerRadiusBottomLeft) : 0,
            to: Double(coordinateLimit))
        result.elements = clampedElements(path.elements)
        result.fillGradient = path.fillGradient.map(sanitizedGradient)
        result.strokeGradient = path.strokeGradient.map(sanitizedGradient)
        result.gradientSpace = sanitizedGradientSpace(path.resolvedGradientSpace, fallbackBounds: result.bounds)
        return result
    }

    /// Path gradients run through the same scene boundary as their geometry.
    /// A finite stop is clamped rather than discarded; non-finite positions
    /// follow `LinearGradient.renderedSegments` and are ignored. Bounding the
    /// authored list also bounds path-cache hashing and every raster lookup.
    private static func sanitizedGradient(_ gradient: LinearGradient) -> LinearGradient {
        let maximum = LinearGradient.maximumRenderedStops
        let requiresSanitation =
            gradient.stops.count > maximum
            || gradient.stops.contains {
                !$0.position.isFinite || $0.position < 0 || $0.position > 1
                    || !gradientColorIsRepresentable($0.color)
            }
        guard requiresSanitation else { return gradient }

        var result = gradient
        let finiteCount = gradient.stops.reduce(into: 0) { count, stop in
            if stop.position.isFinite { count += 1 }
        }
        var stops: [GradientStop] = []
        stops.reserveCapacity(min(finiteCount, maximum))
        var finiteIndex = 0
        var nextSelectedIndex = 0

        for stop in gradient.stops where stop.position.isFinite {
            let shouldRetain: Bool
            if finiteCount > maximum {
                let selectedIndex = nextSelectedIndex * (finiteCount - 1) / (maximum - 1)
                shouldRetain = finiteIndex == selectedIndex
            } else {
                shouldRetain = true
            }
            if shouldRetain {
                stops.append(
                    GradientStop(
                        color: sanitizedGradientColor(stop.color),
                        position: GPUISceneValue.clamped(stop.position, lower: 0, upper: 1)))
                nextSelectedIndex += 1
            }
            finiteIndex += 1
        }

        if stops.isEmpty, let fallback = gradient.stops.first {
            // `renderedSegments` uses the first authored colour when every
            // position is invalid; sanitation must keep that visible fallback.
            stops = [GradientStop(color: sanitizedGradientColor(fallback.color), position: 0)]
        }

        result.stops = stops
        return result
    }

    private static func gradientColorIsRepresentable(_ color: Color) -> Bool {
        color.red.isFinite && color.red >= 0 && color.red <= 1
            && color.green.isFinite && color.green >= 0 && color.green <= 1
            && color.blue.isFinite && color.blue >= 0 && color.blue <= 1
            && color.alpha.isFinite && color.alpha >= 0 && color.alpha <= 1
    }

    private static func sanitizedGradientColor(_ color: Color) -> Color {
        Color(
            red: GPUISceneValue.clamped(color.red, lower: 0, upper: 1),
            green: GPUISceneValue.clamped(color.green, lower: 0, upper: 1),
            blue: GPUISceneValue.clamped(color.blue, lower: 0, upper: 1),
            alpha: GPUISceneValue.clamped(color.alpha, lower: 0, upper: 1))
    }

    private static func sanitizedGradientSpace(
        _ gradientSpace: PathGradientSpace?, fallbackBounds: Rect
    ) -> PathGradientSpace? {
        guard let gradientSpace else { return nil }
        let points = [gradientSpace.origin, gradientSpace.horizontalEnd, gradientSpace.verticalEnd]
        guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            return PathGradientSpace(bounds: fallbackBounds)
        }
        let limit = Double(coordinateLimit)
        return gradientSpace.mapped {
            Point(
                x: GPUISceneValue.clamped($0.x, to: limit),
                y: GPUISceneValue.clamped($0.y, to: limit))
        }
    }

    private static func clampedRect(_ rect: Rect) -> Rect {
        let limit = Double(coordinateLimit)
        return Rect(
            x: GPUISceneValue.clamped(rect.origin.x, to: limit),
            y: GPUISceneValue.clamped(rect.origin.y, to: limit),
            width: GPUISceneValue.clamped(rect.size.width, to: limit),
            height: GPUISceneValue.clamped(rect.size.height, to: limit)
        )
    }

    /// Element coordinates are clamped rather than rejected: a single bad
    /// control point in a long chart path should degrade that vertex, not
    /// erase the series. `bounds` already decides where the path is
    /// allowed to paint, so a clamped vertex cannot draw outside it.
    private static func clampedElements(_ elements: [PathElement]) -> [PathElement] {
        let limit = Double(coordinateLimit)
        guard elements.contains(where: { !elementIsRepresentable($0, limit: limit) }) else {
            return elements
        }

        return elements.map { element in
            switch element {
            case .moveTo(let point):
                return .moveTo(clampedPoint(point, limit: limit))
            case .lineTo(let point):
                return .lineTo(clampedPoint(point, limit: limit))
            case .quadraticCurveTo(let control, let end):
                return .quadraticCurveTo(
                    control: clampedPoint(control, limit: limit),
                    end: clampedPoint(end, limit: limit)
                )
            case .cubicCurveTo(let control1, let control2, let end):
                return .cubicCurveTo(
                    control1: clampedPoint(control1, limit: limit),
                    control2: clampedPoint(control2, limit: limit),
                    end: clampedPoint(end, limit: limit)
                )
            case .arc(let center, let radius, let startAngle, let endAngle, let clockwise):
                return .arc(
                    center: clampedPoint(center, limit: limit),
                    radius: GPUISceneValue.clamped(radius.isFinite ? max(0, radius) : 0, to: limit),
                    startAngle: GPUISceneValue.clamped(startAngle, to: .pi * 1_024),
                    endAngle: GPUISceneValue.clamped(endAngle, to: .pi * 1_024),
                    clockwise: clockwise
                )
            case .close:
                return .close
            }
        }
    }

    private static func elementIsRepresentable(_ element: PathElement, limit: Double) -> Bool {
        @inline(__always)
        func ok(_ value: Double) -> Bool { value.isFinite && value >= -limit && value <= limit }
        @inline(__always)
        func ok(_ point: Point) -> Bool { ok(point.x) && ok(point.y) }

        switch element {
        case .moveTo(let point), .lineTo(let point):
            return ok(point)
        case .quadraticCurveTo(let control, let end):
            return ok(control) && ok(end)
        case .cubicCurveTo(let control1, let control2, let end):
            return ok(control1) && ok(control2) && ok(end)
        case .arc(let center, let radius, let startAngle, let endAngle, _):
            return ok(center) && radius >= 0 && ok(radius) && startAngle.isFinite && endAngle.isFinite
                && abs(startAngle) <= .pi * 1_024 && abs(endAngle) <= .pi * 1_024
        case .close:
            return true
        }
    }

    private static func clampedPoint(_ point: Point, limit: Double) -> Point {
        Point(
            x: GPUISceneValue.clamped(point.x, to: limit),
            y: GPUISceneValue.clamped(point.y, to: limit)
        )
    }
}

// MARK: - Structural validation

/// A structural violation of the scene contract found by
/// `GPUIScene.validate()`.
///
/// Field-level sanitation happens at `add*`; this covers what direct
/// mutation of the scene's `public var` surface (or a hand-built
/// `GPUILayer`) can still break — the invariants a backend indexes
/// against and would otherwise *trap* on.
public struct SceneDefect: Equatable, Sendable, CustomStringConvertible {
    public enum Kind: Equatable, Sendable {
        /// The scene holds more layers than the contract allows.
        case layerCountExceedsLimit(count: Int, limit: Int)
        /// A paint operation names a range that is not inside its family
        /// array — the shape `makeRenderPlan` used to index unchecked.
        case paintOperationOutOfRange(
            layerIndex: Int,
            operationIndex: Int,
            kind: GPUIPaintPrimitiveKind,
            startIndex: Int,
            count: Int,
            familyCount: Int
        )
        /// A glyph atlas snapshot's declared size does not match (or
        /// overruns) its pixel buffer.
        case glyphAtlasBufferMismatch(width: Int32, height: Int32, byteCount: Int, requiredByteCount: Int)
        case invalidImageRenderPass(textureID: Int32, reason: String)
        /// A hand-built image bypassed the affine placement admission check.
        case invalidImagePlacement(layerIndex: Int, imageIndex: Int, reason: String)
        /// A hand-built image bypassed cap/tile descriptor admission.
        case invalidImageSampling(layerIndex: Int, imageIndex: Int, reason: String)
    }

    public var kind: Kind

    public init(kind: Kind) {
        self.kind = kind
    }

    public var description: String {
        switch kind {
        case .layerCountExceedsLimit(let count, let limit):
            return "Scene holds \(count) layers, above the contract limit of \(limit)."
        case .paintOperationOutOfRange(
            let layerIndex, let operationIndex, let kind, let startIndex, let count, let familyCount):
            let (endIndex, endIndexOverflowed) = startIndex.addingReportingOverflow(count)
            let upperBound = endIndexOverflowed ? "overflow" : String(endIndex)
            return
                "Layer \(layerIndex) paint operation \(operationIndex) (\(kind)) covers "
                + "\(startIndex)..<\(upperBound) of a \(familyCount)-element family."
        case .glyphAtlasBufferMismatch(let width, let height, let byteCount, let requiredByteCount):
            return "Glyph atlas is \(width)×\(height) but holds \(byteCount) bytes (needs \(requiredByteCount))."
        case .invalidImageRenderPass(let textureID, let reason):
            return "Scene image render pass \(textureID) is invalid: \(reason)."
        case .invalidImagePlacement(let layerIndex, let imageIndex, let reason):
            return "Layer \(layerIndex) image \(imageIndex) has invalid placement: \(reason)."
        case .invalidImageSampling(let layerIndex, let imageIndex, let reason):
            return "Layer \(layerIndex) image \(imageIndex) has invalid sampling: \(reason)."
        }
    }
}

extension GlyphAtlasSnapshot {
    /// Byte count `width × height × 4` requires, or `nil` when the
    /// declared dimensions are themselves invalid or their product cannot
    /// fit in an `Int`. Atlas snapshots are public scene inputs, so checked
    /// arithmetic is part of validation: an overflow must become a scene
    /// defect rather than killing the process while diagnosing one.
    var requiredByteCount: Int? {
        guard width > 0, height > 0 else { return nil }
        let (pixelCount, pixelCountOverflowed) = Int(width).multipliedReportingOverflow(by: Int(height))
        guard !pixelCountOverflowed else { return nil }
        let (byteCount, byteCountOverflowed) = pixelCount.multipliedReportingOverflow(by: 4)
        guard !byteCountOverflowed else { return nil }
        return byteCount
    }

    // Dirty-region clamping lives in `AtlasUploadProtocol.swift`
    // (`clampedRegion(_:)`): it is one step of the upload decision rather
    // than a property every consumer has to remember to prefer.

    var structuralDefect: SceneDefect? {
        guard let requiredByteCount else {
            return SceneDefect(
                kind: .glyphAtlasBufferMismatch(
                    width: width, height: height, byteCount: pixels.count, requiredByteCount: 0))
        }
        guard pixels.count >= requiredByteCount else {
            return SceneDefect(
                kind: .glyphAtlasBufferMismatch(
                    width: width, height: height, byteCount: pixels.count, requiredByteCount: requiredByteCount))
        }
        return nil
    }
}

extension GPUIScene {
    /// Structural defects a backend would otherwise trap on.
    ///
    /// Ordinary structural checks walk bounded scene declarations and paint
    /// operations. Used color-effect passes also analyze reachable emission,
    /// scanning at most 64 MiB of premultiplied bitmap texels per query and
    /// caching payload results within that query. Unused declarations retain
    /// their structural checks without this payload analysis. Backends call
    /// this on every frame: a trap cannot be downgraded by the host's fallback
    /// policy; a thrown `sceneContent` failure can.
    public func validate() -> [SceneDefect] {
        var imageRenderPassBudget = GPUISceneImageRenderPassBudget()
        return validate(
            imageRenderPassDepth: 0, imageRenderPassBudget: &imageRenderPassBudget, inBackdropIsolation: false,
            isUsedForRendering: true)
    }

    private func validate(
        imageRenderPassDepth: Int, imageRenderPassBudget: inout GPUISceneImageRenderPassBudget,
        inBackdropIsolation: Bool, isUsedForRendering: Bool
    ) -> [SceneDefect] {
        var defects: [SceneDefect] = []

        if layers.count > GPUISceneLimits.maxLayers {
            defects.append(
                SceneDefect(kind: .layerCountExceedsLimit(count: layers.count, limit: GPUISceneLimits.maxLayers)))
        }

        // Build a dimension map only for scenes using the new modes. Manual
        // renderer bindings are validated by that renderer once they resolve.
        // Resource replacement follows the same last-binding-wins policy as
        // the CPU and GPU image caches.
        var samplingSourceSizes: [Int32: IntSize] = [:]
        if layers.contains(where: { $0.images.contains(where: { !$0.sampling.isLegacy }) }) {
            for binding in imageResources {
                samplingSourceSizes[binding.textureID] = IntSize(
                    width: binding.bitmap.width, height: binding.bitmap.height)
            }
            for pass in imageRenderPasses where samplingSourceSizes[pass.textureID] == nil {
                samplingSourceSizes[pass.textureID] = pass.size
            }
        }
        for (layerIndex, layer) in layers.enumerated() {
            for (imageIndex, image) in layer.images.enumerated() {
                if let reason = image.affinePlacementDefect {
                    defects.append(
                        SceneDefect(
                            kind: .invalidImagePlacement(
                                layerIndex: layerIndex, imageIndex: imageIndex, reason: reason)))
                }
                if let failure = image.sampling.validationFailure(
                    sourceSize: samplingSourceSizes[image.textureID],
                    uvX: image.uvX, uvY: image.uvY, uvW: image.uvW, uvH: image.uvH)
                    ?? image.sampling.placementValidationFailure(
                        rect: Rect(
                            x: Double(image.screenX), y: Double(image.screenY),
                            width: Double(image.screenW), height: Double(image.screenH)))
                {
                    defects.append(
                        SceneDefect(
                            kind: .invalidImageSampling(
                                layerIndex: layerIndex, imageIndex: imageIndex, reason: failure.description)))
                }
            }
            for (operationIndex, operation) in layer.paintOperations.enumerated() {
                let familyCount: Int
                switch operation.kind {
                case .shadow: familyCount = layer.shadows.count
                case .quad: familyCount = layer.quads.count
                case .glyph: familyCount = layer.glyphs.count
                case .pixelGlyph: familyCount = layer.pixelGlyphs.count
                case .image: familyCount = layer.images.count
                case .path: familyCount = layer.paths.count
                }

                guard operation.count >= 0, operation.startIndex >= 0,
                    operation.startIndex <= familyCount - operation.count
                else {
                    defects.append(
                        SceneDefect(
                            kind: .paintOperationOutOfRange(
                                layerIndex: layerIndex,
                                operationIndex: operationIndex,
                                kind: operation.kind,
                                startIndex: operation.startIndex,
                                count: operation.count,
                                familyCount: familyCount
                            )))
                    continue
                }
            }
        }

        if let defect = glyphAtlas?.structuralDefect {
            defects.append(defect)
        }
        if let defect = pixelGlyphAtlas?.structuralDefect {
            defects.append(defect)
        }

        let bitmapIDs = Set(imageResources.map(\.textureID))
        var imageIDs = bitmapIDs
        var usedImageIDs: Set<Int32> = []
        if isUsedForRendering, !imageRenderPasses.isEmpty {
            for run in presentationOrder() where run.kind == .image {
                let layer = layers[run.layerIndex]
                for index in run.range {
                    let id = layer.images[index].textureID
                    if !bitmapIDs.contains(id) { usedImageIDs.insert(id) }
                }
            }
        }
        var dependentBackdropSources: [Int32: GPUISceneImageRenderPass] = [:]
        for pass in imageRenderPasses {
            let childIsUsedForRendering = isUsedForRendering && usedImageIDs.contains(pass.textureID)
            // Charge each declared namespace independently, even when its
            // value arrays share storage with another branch. Stop rejected
            // extents as well as exhausted budgets so invalid declarations
            // cannot turn this into an unbounded diagnostic walk.
            let admitted = imageRenderPassBudget.consume(pass, inBackdropIsolation: inBackdropIsolation)
            let reason: String?
            if !pass.hasValidExtent {
                reason = "extent exceeds the offscreen pixel budget or has no pixels"
            } else if !admitted {
                reason =
                    imageRenderPassBudget.remainingPasses == 0
                    ? "image-pass count exceeds \(GPUISceneLimits.maxImageRenderPassCount)"
                    : "cumulative source pixels exceed \(GPUISceneLimits.maxImageRenderPassTotalPixels)"
            } else if pass.textureID < 0 || !imageIDs.insert(pass.textureID).inserted {
                reason = "texture ID is negative or has more than one source"
            } else if pass.colorEffects.count > GPUISceneLimits.maxColorEffects {
                reason = "effect chain exceeds \(GPUISceneLimits.maxColorEffects) operations"
            } else if let inputDefect = pass.currentTargetSourceDefect {
                reason = inputDefect
            } else if let inputDefect = pass.isolatedBackdropSourceDefect {
                reason = inputDefect
            } else if let radiusDefect = pass.contentBlurRadiusDefect {
                reason = radiusDefect
            } else if imageRenderPassDepth >= GPUISceneLimits.maxImageRenderPassDepth {
                reason = "nesting exceeds \(GPUISceneLimits.maxImageRenderPassDepth) passes"
            } else {
                reason = nil
            }
            if let reason {
                defects.append(SceneDefect(kind: .invalidImageRenderPass(textureID: pass.textureID, reason: reason)))
                if !admitted { break }
            } else {
                // Emission admission follows actual image use through every
                // ancestor. Keep declaration validation and its budget walk
                // intact even when this new effect restriction is diagnosed.
                if childIsUsedForRendering, let effectDefect = pass.additiveEmissionColorEffectDefect {
                    defects.append(
                        SceneDefect(kind: .invalidImageRenderPass(textureID: pass.textureID, reason: effectDefect)))
                }
                let childIsInBackdropIsolation: Bool
                switch pass.input {
                case .independent:
                    childIsInBackdropIsolation = false
                case .currentTarget:
                    dependentBackdropSources[pass.textureID] = pass
                    childIsInBackdropIsolation = inBackdropIsolation
                case .isolatedBackdrop:
                    dependentBackdropSources[pass.textureID] = pass
                    childIsInBackdropIsolation = true
                }
                defects.append(
                    contentsOf: pass.scene.validate(
                        imageRenderPassDepth: imageRenderPassDepth + 1,
                        imageRenderPassBudget: &imageRenderPassBudget,
                        inBackdropIsolation: childIsInBackdropIsolation,
                        isUsedForRendering: childIsUsedForRendering))
            }
        }

        // The dictionary contains only admitted sources, so an invalid graph
        // cannot bypass the traversal budget by requesting mapping diagnostics.
        if !dependentBackdropSources.isEmpty {
            for layer in layers {
                for image in layer.images {
                    if let pass = dependentBackdropSources[image.textureID],
                        let reason = pass.currentTargetImageDefect(image) ?? pass.isolatedBackdropImageDefect(image)
                    {
                        defects.append(
                            SceneDefect(kind: .invalidImageRenderPass(textureID: pass.textureID, reason: reason)))
                    }
                }
            }
        }

        return defects
    }
}
