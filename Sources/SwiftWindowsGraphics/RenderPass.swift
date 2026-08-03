import Foundation
import SwiftWindowsCore

// MARK: - Render targets and passes

/// What a render pass is drawing into.
///
/// The stack had three unrelated spellings of "draw somewhere that is not
/// the window": the batch renderer's `renderTargetKind` (swap chain vs
/// offscreen texture), the backdrop blur engine's ping-pong pair, and the
/// painter's compositing-group CPU round trip. None of them shared a
/// vocabulary, so each grew its own rules about size, clearing and what
/// inherited state survives the boundary — which is why a material could
/// not blur inside a `drawingGroup` and why the group used to drop the
/// inherited clip.
///
/// `RenderTargetKind` is the first word of the shared vocabulary. It is
/// deliberately renderer-neutral: a `.presentation` target is whatever the
/// backend shows the user (swap-chain buffer, offscreen snapshot texture,
/// CPU bitmap), and an `.offscreen` target is a scratch surface a pass
/// owns and a later pass samples.
public enum RenderTargetKind: String, Equatable, Sendable {
    /// The surface the frame is presented from.
    case presentation
    /// A scratch surface produced and consumed inside one frame.
    case offscreen
}

/// Size, kind and load behaviour of the surface a `RenderPassDescriptor`
/// writes into.
///
/// `clearColor == nil` means *load*: the pass composites over whatever the
/// target already holds. That distinction is what makes a backdrop pass
/// (loads the scene so far) and a compositing-group pass (clears to
/// transparent) expressible in one type.
public struct RenderTargetDescriptor: Equatable, Sendable {
    public var kind: RenderTargetKind
    public var width: Int
    public var height: Int
    public var clearColor: Color?

    public init(kind: RenderTargetKind, width: Int, height: Int, clearColor: Color? = nil) {
        self.kind = kind
        // Saturating rather than trapping: a caller that computed a
        // negative extent from a collapsed layout gets an empty target it
        // can test for, not a crash on the way to allocating it.
        self.width = max(0, min(width, GPUISceneLimits.maxSurfaceDimension))
        self.height = max(0, min(height, GPUISceneLimits.maxSurfaceDimension))
        self.clearColor = clearColor
    }

    /// True when the target has no pixels; every consumer treats this as
    /// "skip the pass" rather than as an error.
    public var isEmpty: Bool { width <= 0 || height <= 0 }

    /// True when the pass must preserve the target's existing contents.
    public var loadsExistingContents: Bool { clearColor == nil }
}

/// One pass over one target, plus the inherited paint state that crosses
/// the boundary with it.
///
/// The three consumers need exactly these fields:
///
/// - the batch renderer needs `target` and `viewport` to bind an RTV and a
///   viewport;
/// - the backdrop blur engine needs `viewport` (the region it blurs) and
///   `target` (the ping-pong surface it blurs into);
/// - the painter's compositing group needs `target`, `inheritedOpacity`
///   and `isCacheable` to decide whether last frame's bitmap can stand in.
///
/// Nothing speculative lives here: a field that no consumer reads is a
/// field that will drift out of sync with what the passes actually do.
public struct RenderPassDescriptor: Equatable, Sendable {
    /// Human-readable pass name, used in diagnostics and test failure
    /// messages. Never load-bearing.
    public var label: String
    public var target: RenderTargetDescriptor
    /// The sub-rectangle of `target` this pass writes, in device pixels.
    public var viewport: SubTextureRegion
    /// Opacity already applied by ancestors, carried across the boundary
    /// so a sub-scene composites the same way an inline subtree would.
    public var inheritedOpacity: Float
    /// True when the pass's result may be reused across frames while its
    /// inputs are unchanged (the compositing-group bitmap cache).
    public var isCacheable: Bool

    public init(
        label: String,
        target: RenderTargetDescriptor,
        viewport: SubTextureRegion,
        inheritedOpacity: Float = 1,
        isCacheable: Bool = false
    ) {
        self.label = label
        self.target = target
        self.viewport = viewport
        self.inheritedOpacity = GPUISceneValue.clamped(inheritedOpacity, lower: 0, upper: 1)
        self.isCacheable = isCacheable
    }

    /// True when the pass would draw nothing.
    public var isEmpty: Bool { target.isEmpty || viewport.isEmpty }
}

// MARK: - SubTextureRegion

/// A rectangle of texels inside a larger texture, and the texture it
/// belongs to.
///
/// This type exists to make one bug class unrepresentable. Grow-only
/// scratch textures (the blur ping-pong pair, the path cache) hold a
/// region smaller than the texture, and every texel past the region is
/// whatever the *previous*, larger region left there. Sampling normalized
/// UVs derived from `region / textureSize` reaches those stale texels at
/// the region's far edge, because bilinear filtering at the region
/// boundary blends the last in-region texel with the first out-of-region
/// one — a right/bottom edge smear of the previous frame's content.
///
/// Every UV this type hands out is already inset to the region's outermost
/// texel *centres*, so a tap clamped through `clampUV` cannot reach
/// outside the region no matter how far the sample offset runs. The
/// initializer additionally clamps the region into the texture, so a
/// region that claims texels the texture does not have is not expressible
/// either.
public struct SubTextureRegion: Equatable, Sendable {
    public let originX: Int
    public let originY: Int
    public let width: Int
    public let height: Int
    public let textureWidth: Int
    public let textureHeight: Int

    public init(
        originX: Int,
        originY: Int,
        width: Int,
        height: Int,
        textureWidth: Int,
        textureHeight: Int
    ) {
        let clampedTextureWidth = max(0, min(textureWidth, GPUISceneLimits.maxSurfaceDimension))
        let clampedTextureHeight = max(0, min(textureHeight, GPUISceneLimits.maxSurfaceDimension))
        let clampedOriginX = max(0, min(originX, clampedTextureWidth))
        let clampedOriginY = max(0, min(originY, clampedTextureHeight))
        self.textureWidth = clampedTextureWidth
        self.textureHeight = clampedTextureHeight
        self.originX = clampedOriginX
        self.originY = clampedOriginY
        self.width = max(0, min(width, clampedTextureWidth - clampedOriginX))
        self.height = max(0, min(height, clampedTextureHeight - clampedOriginY))
    }

    /// A region covering the whole of a texture.
    public init(textureWidth: Int, textureHeight: Int) {
        self.init(
            originX: 0, originY: 0,
            width: textureWidth, height: textureHeight,
            textureWidth: textureWidth, textureHeight: textureHeight)
    }

    public var isEmpty: Bool { width <= 0 || height <= 0 }

    public var maxX: Int { originX + width }
    public var maxY: Int { originY + height }

    /// Normalized UV of the region's origin corner.
    public var uvOriginX: Float { textureWidth > 0 ? Float(originX) / Float(textureWidth) : 0 }
    public var uvOriginY: Float { textureHeight > 0 ? Float(originY) / Float(textureHeight) : 0 }

    /// Normalized UV extent of the region — what a shader multiplies a
    /// `[0, 1]` viewport coordinate by to land inside the region.
    public var uvWidth: Float { textureWidth > 0 ? Float(width) / Float(textureWidth) : 0 }
    public var uvHeight: Float { textureHeight > 0 ? Float(height) / Float(textureHeight) : 0 }

    /// Half a texel in normalized units — the inset that turns a region
    /// *boundary* into the outermost texel *centre*.
    public var halfTexelU: Float { textureWidth > 0 ? 0.5 / Float(textureWidth) : 0 }
    public var halfTexelV: Float { textureHeight > 0 ? 0.5 / Float(textureHeight) : 0 }

    /// Lower UV clamp bound: the centre of the region's first texel.
    public var uvMinU: Float { uvOriginX + halfTexelU }
    public var uvMinV: Float { uvOriginY + halfTexelV }

    /// Upper UV clamp bound: the centre of the region's last texel. Never
    /// below the lower bound — a one-texel region clamps every tap to that
    /// texel rather than inverting the interval.
    public var uvMaxU: Float { max(uvOriginX + uvWidth - halfTexelU, uvMinU) }
    public var uvMaxV: Float { max(uvOriginY + uvHeight - halfTexelV, uvMinV) }

    /// The one clamp every sub-texture sampler goes through. A tap outside
    /// the region snaps to the nearest in-region texel centre instead of
    /// bleeding a neighbour's texels in.
    ///
    /// Non-finite inputs clamp to the lower bound rather than propagating
    /// NaN into a texture fetch.
    public func clampUV(_ u: Float, _ v: Float) -> (u: Float, v: Float) {
        (Self.clamp(u, uvMinU, uvMaxU), Self.clamp(v, uvMinV, uvMaxV))
    }

    private static func clamp(_ value: Float, _ lower: Float, _ upper: Float) -> Float {
        guard value.isFinite else { return lower }
        return min(max(value, lower), upper)
    }

    /// The region this one becomes after `factor` successive halvings of
    /// the image it describes, with the texture kept the same size.
    ///
    /// Downsample passes render into the same grow-only scratch texture at
    /// a smaller viewport, so the reduced image occupies the texture's
    /// top-left corner and the surrounding texels stay stale — exactly the
    /// case `clampUV` exists for.
    public func reduced(byFactor factor: Int) -> SubTextureRegion {
        guard factor > 1 else { return self }
        return SubTextureRegion(
            originX: originX / factor,
            originY: originY / factor,
            width: max(1, width / factor),
            height: max(1, height / factor),
            textureWidth: textureWidth,
            textureHeight: textureHeight)
    }
}

// MARK: - Blur cost model

/// How a Gaussian blur of `radius` over a `regionWidth × regionHeight`
/// region is actually executed.
///
/// A two-pass separable Gaussian costs `2 · w · h · (2r + 1)` texture
/// samples. The painter emits `radius × displayScale`, so both `r` and the
/// device-pixel region scale with the display: the cost is **cubic** in
/// display scale, against a cost model that was written down for 1× only.
/// A `.blur(radius: 100)` panel that costs 20 M samples on a 1× monitor
/// costs 160 M on a 2× one.
///
/// The fix is the standard one: blur at reduced resolution and upsample.
/// Halving the image quarters the pixel count *and* halves the radius, so
/// one halving is an 8× cost reduction and two halvings 64×. The error it
/// introduces lives entirely in the frequencies a wide Gaussian is
/// removing anyway.
///
/// Two properties matter more than the exact schedule:
///
/// 1. **The factor depends on the radius alone.** Both backends compute
///    the plan from the same integer radius, so the CPU rasterizer and the
///    D3D11 blur engine always take the same number of halvings. Keying it
///    on the region size instead would let a one-pixel disagreement about
///    the region flip one backend to a different schedule and blow up
///    cross-backend parity.
/// 2. **Small radii are untouched.** Built-in materials top out at 40
///    device pixels and every pinned blur baseline sits below the
///    threshold, so the reduced path is reachable only by app-supplied
///    `.blur(radius:)` wide enough that the downsample is invisible.
public struct BlurPassPlan: Equatable, Sendable {
    /// Radii at or below this run at full resolution. 128 device pixels is
    /// above every built-in material (max 40) and above every blur pinned
    /// by a baseline, so turning the reduced path on moved no reference
    /// render.
    public static let fullResolutionRadiusLimit = 128

    /// Radii above this take two halvings. Chosen so the reduced radius
    /// stays in the 64…96 band where a Gaussian is still sampled densely
    /// enough to be smooth.
    public static let quarterResolutionRadiusLimit = 192

    /// Largest supported reduction. Two halvings; a third would put the
    /// reduced radius of the largest legal blur (`maxBlurRadius` = 256)
    /// down at 32, where the upsample starts to show as banding.
    public static let maxDownsampleFactor = 4

    public let requestedRadius: Int
    public let regionWidth: Int
    public let regionHeight: Int
    /// 1, 2 or 4 — always a power of two, so the reduction is a sequence
    /// of exact 2×2 box averages on both backends.
    public let downsampleFactor: Int

    public init(radius: Int, regionWidth: Int, regionHeight: Int) {
        let clampedRadius = max(0, min(radius, Int(GPUISceneLimits.maxBlurRadius)))
        self.requestedRadius = clampedRadius
        self.regionWidth = max(0, regionWidth)
        self.regionHeight = max(0, regionHeight)
        self.downsampleFactor = Self.downsampleFactor(forRadius: clampedRadius)
    }

    /// The reduction schedule, radius-only by design (see the type doc).
    public static func downsampleFactor(forRadius radius: Int) -> Int {
        if radius <= fullResolutionRadiusLimit { return 1 }
        if radius <= quarterResolutionRadiusLimit { return 2 }
        return maxDownsampleFactor
    }

    /// Number of 2× halving passes this plan runs before blurring.
    public var halvingPassCount: Int {
        switch downsampleFactor {
        case 4: return 2
        case 2: return 1
        default: return 0
        }
    }

    /// Blur radius applied to the reduced image. Never zero for a
    /// non-zero request: a plan that reduced the radius to nothing would
    /// silently turn a blur into a resample.
    public var reducedRadius: Int {
        guard requestedRadius > 0 else { return 0 }
        return max(1, requestedRadius / downsampleFactor)
    }

    /// Size of the reduced image the blur passes run over. At least one
    /// texel in each axis so a tiny region still has something to sample.
    public var reducedWidth: Int { max(1, regionWidth / downsampleFactor) }
    public var reducedHeight: Int { max(1, regionHeight / downsampleFactor) }

    public var isReduced: Bool { downsampleFactor > 1 }

    /// Texture samples a full-resolution two-pass separable blur would
    /// take over this region. The number the reduced path is measured
    /// against.
    public var fullResolutionSampleCost: Int {
        guard requestedRadius > 0 else { return 0 }
        return 2 * regionWidth * regionHeight * (2 * requestedRadius + 1)
    }

    /// Texture samples this plan actually takes: one bilinear tap per
    /// output texel of each halving pass, then the two separable blur
    /// passes at reduced resolution.
    ///
    /// The upsample is not counted: it is folded into the composite draw
    /// that had to sample the backdrop anyway.
    public var sampleCost: Int {
        guard requestedRadius > 0 else { return 0 }
        var cost = 0
        var width = regionWidth
        var height = regionHeight
        for _ in 0..<halvingPassCount {
            width = max(1, width / 2)
            height = max(1, height / 2)
            cost += width * height
        }
        cost += 2 * reducedWidth * reducedHeight * (2 * reducedRadius + 1)
        return cost
    }
}
