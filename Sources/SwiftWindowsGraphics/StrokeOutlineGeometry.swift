import Foundation
import SwiftWindowsCore

/// The stroke-outline rules both stroke rasterizers apply.
///
/// A stroke reaches pixels by two routes: `PathCoverageRasterizer`, which
/// unions the outline polygons — and is what `GPUIRawSceneRasterizer` draws
/// and what the D3D11 path-texture cache uploads — and the painter's
/// `PathToQuadTessellator`, which promotes the same outline to
/// `QuadPrimitive`s. The two have to agree about *when* a join is worth
/// drawing and *how far* a cap reaches, or the same `StrokeStyle` renders as
/// two different shapes depending on a promotion decision the app never made.
///
/// So the decisions live here, once, in the renderer-neutral layer both
/// routes already depend on.
public enum StrokeOutlineGeometry {

    /// Largest distance, in the primitive's own (device-pixel) space, that an
    /// omitted join may move the stroke boundary by.
    ///
    /// A flattened curve turns by a fraction of a degree per segment, so
    /// drawing a join at every vertex costs thousands of polygons to move a
    /// boundary by a thousandth of a pixel. A tenth of a pixel is below the
    /// cross-backend parity suite's ±4/255 tolerance for every angle a real
    /// corner makes.
    public static let joinTolerance: Double = 0.1

    /// `1 / cos(turn / 2)` — the miter length as a multiple of the half
    /// width — derived from the dot product of two unit segment directions.
    ///
    /// `nil` when the segments double back on themselves, where the two
    /// outer offset lines are parallel and the miter is unbounded. Every
    /// caller treats that as "past any limit", which is what the limit is
    /// for.
    public static func miterRatio(directionDot dot: Double) -> Double? {
        let cosHalfSquared = (1 + dot) / 2
        guard cosHalfSquared > 0, cosHalfSquared.isFinite else { return nil }
        let ratio = (1 / cosHalfSquared).squareRoot()
        guard ratio.isFinite else { return nil }
        return ratio
    }

    /// The join a renderer actually draws at this turn: a `.miter` whose
    /// length exceeds the limit in half-widths degrades to `.bevel`, which is
    /// what SwiftUI, Core Graphics and Direct2D all do. `.round` and
    /// `.bevel` are unconditional.
    ///
    /// The limit applied is ``effectiveMiterLimit(_:)``, not the app's raw
    /// number, so the drawn spike can never reach past the `bounds` that
    /// sized its own raster.
    public static func resolvedJoin(
        _ join: StrokeStyle.LineJoin,
        directionDot dot: Double,
        miterLimit: Double
    ) -> StrokeStyle.LineJoin {
        guard join == .miter else { return join }
        let limit = effectiveMiterLimit(miterLimit)
        guard let ratio = miterRatio(directionDot: dot), ratio <= limit else {
            return .bevel
        }
        return .miter
    }

    /// The miter limit a renderer actually applies: the app's own limit,
    /// floored at 1 and capped at ``maxMiterBoundsRatio``.
    ///
    /// `boundsOutset` refuses to size a raster off an app-supplied number —
    /// a `miterLimit` of 10, which is `StrokeStyle`'s default, would let a
    /// stroke's footprint be twenty times its width — so it clamped the
    /// outset at four half-widths. `resolvedJoin` did not clamp, so a corner
    /// sharper than ~29° drew a spike reaching past the `bounds` that sized
    /// its own bitmap, and shipped sheared flat by the buffer edge.
    ///
    /// Bounds and geometry now read the same number, and the resolution is
    /// to degrade rather than to grow: past the ratio a raster can hold, the
    /// miter becomes the bevel it would have become at a tighter
    /// `miterLimit`. A bevel is a shape SwiftUI also draws; a cropped spike
    /// is not.
    public static func effectiveMiterLimit(_ miterLimit: Double) -> Double {
        // A limit below 1 would bevel even a straight run, which no stroker
        // means; `StrokeStyle` defaults to 10 and Core Graphics floors at 1.
        let limit = miterLimit.isFinite ? max(1, miterLimit) : maxMiterBoundsRatio
        return min(limit, maxMiterBoundsRatio)
    }

    /// How far the join's own geometry reaches beyond the two segment bodies:
    /// the error a renderer accepts by not drawing it at all.
    ///
    /// `join` must already be resolved through `resolvedJoin(_:…)` — a miter
    /// past its limit leaves a bevel's error, not a miter's.
    public static func omittedJoinError(
        halfWidth: Double,
        directionDot dot: Double,
        join: StrokeStyle.LineJoin
    ) -> Double {
        guard halfWidth > 0, dot.isFinite else { return 0 }
        // The two butt ends meet along a chord at `halfWidth * cos(turn / 2)`
        // from the vertex; every join fills outward from there.
        let cosHalf = max(0, min(1, (1 + dot) / 2)).squareRoot()
        switch join {
        case .round, .bevel:
            return halfWidth * (1 - cosHalf)
        case .miter:
            guard let ratio = miterRatio(directionDot: dot) else { return .infinity }
            return halfWidth * (ratio - cosHalf)
        }
    }

    /// Whether this turn is sharp enough for its join to be worth drawing.
    public static func joinIsVisible(
        halfWidth: Double,
        directionDot dot: Double,
        join: StrokeStyle.LineJoin
    ) -> Bool {
        omittedJoinError(halfWidth: halfWidth, directionDot: dot, join: join) > joinTolerance
    }

    /// Largest miter, in half-widths, that either an emitter's `bounds` or a
    /// renderer's geometry will reach.
    ///
    /// `bounds` sizes a CPU raster buffer and a GPU texture, so letting it
    /// track `miterLimit` — which defaults to 10 and is an app-supplied
    /// number — would let a stroke's footprint be 20× its width. Four
    /// half-widths covers every corner down to a 29° included angle; a
    /// spike sharper than that bevels (see ``effectiveMiterLimit(_:)``)
    /// rather than being drawn and then cropped at `bounds`.
    public static let maxMiterBoundsRatio: Double = 4

    /// How far outside the path's own geometry the stroke outline can reach,
    /// so an emitter can size `bounds` before anything is flattened.
    ///
    /// Caps are exact. Joins are exact at the straight-line corners that
    /// actually make spikes — a polyline, a stroked rect — and assumed
    /// smooth across a curve or arc joint, where a stroker's turn per
    /// flattened segment is a fraction of a degree.
    public static func boundsOutset(
        forElements elements: [PathElement],
        lineWidth: Double,
        lineCap: StrokeStyle.LineCap,
        lineJoin: StrokeStyle.LineJoin,
        miterLimit: Double
    ) -> Double {
        let halfWidth = lineWidth / 2
        guard halfWidth > 0, halfWidth.isFinite else { return 0 }
        // A square cap's outer corner sits one half-width along the segment
        // and one across it, so on a diagonal it reaches √2 half-widths on
        // either axis.
        let capFactor: Double = lineCap == .square ? 2.0.squareRoot() : 1
        let joinFactor = lineJoin == .miter ? sharpestMiterRatio(forElements: elements, miterLimit: miterLimit) : 1
        // `sharpestMiterRatio` only counts corners `resolvedJoin` keeps as
        // miters, so it is already bounded by `maxMiterBoundsRatio`; the
        // clamp stays as the belt to that braces.
        return halfWidth * max(capFactor, min(joinFactor, maxMiterBoundsRatio))
    }

    /// The largest miter ratio any straight-line corner in `elements` asks
    /// for, or 1 when there is none. Curve and arc joints count as smooth.
    private static func sharpestMiterRatio(forElements elements: [PathElement], miterLimit: Double) -> Double {
        var sharpest: Double = 1
        var current: Point?
        var subpathStart: Point?
        var previousDirection: (x: Double, y: Double)?
        var firstDirection: (x: Double, y: Double)?

        func direction(from start: Point, to end: Point) -> (x: Double, y: Double)? {
            let deltaX = end.x - start.x
            let deltaY = end.y - start.y
            let length = (deltaX * deltaX + deltaY * deltaY).squareRoot()
            guard length > 0, length.isFinite else { return nil }
            return (x: deltaX / length, y: deltaY / length)
        }

        func consider(_ previous: (x: Double, y: Double), _ next: (x: Double, y: Double)) {
            let dot = previous.x * next.x + previous.y * next.y
            guard resolvedJoin(.miter, directionDot: dot, miterLimit: miterLimit) == .miter,
                let ratio = miterRatio(directionDot: dot)
            else { return }
            sharpest = max(sharpest, ratio)
        }

        for element in elements {
            switch element {
            case .moveTo(let point):
                current = point
                subpathStart = point
                previousDirection = nil
                firstDirection = nil
            case .lineTo(let point):
                guard let start = current, let next = direction(from: start, to: point) else {
                    current = point
                    continue
                }
                if let previous = previousDirection { consider(previous, next) }
                if firstDirection == nil { firstDirection = next }
                previousDirection = next
                current = point
            case .close:
                if let start = current, let origin = subpathStart, let next = direction(from: start, to: origin) {
                    if let previous = previousDirection { consider(previous, next) }
                    if let leading = firstDirection { consider(next, leading) }
                } else if let previous = previousDirection, let leading = firstDirection {
                    consider(previous, leading)
                }
                current = subpathStart
                previousDirection = nil
                firstDirection = nil
            case .quadraticCurveTo(_, let end):
                current = end
                previousDirection = nil
                firstDirection = nil
            case .cubicCurveTo(_, _, let end):
                current = end
                previousDirection = nil
                firstDirection = nil
            case .arc(let centre, let radius, _, let endAngle, _):
                current = Point(x: centre.x + radius * cos(endAngle), y: centre.y + radius * sin(endAngle))
                previousDirection = nil
                firstDirection = nil
            }
        }
        return sharpest
    }

    /// How far past the endpoint a cap reaches along the segment direction.
    ///
    /// `.round` reaches exactly as far as `.square` — the disc's outermost
    /// point — but only `.square` fills the whole extension, so this is the
    /// *reach*, not a licence to extend a rectangle by it.
    public static func capReach(_ cap: StrokeStyle.LineCap, halfWidth: Double) -> Double {
        switch cap {
        case .butt: return 0
        case .round, .square: return halfWidth
        }
    }
}
