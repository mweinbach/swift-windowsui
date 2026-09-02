import Foundation
import SwiftWindowsCore

/// The runtime's one clip value.
///
/// Clipping used to be a bare `Rect?` (plus, in two of five traversals, a
/// corner radius) threaded through five independently written intersection
/// blocks — `appendPrepaintState`, `appendCommands`, `hitTest`,
/// `scrollTarget` and `ScenePainter.paintNode`. They drifted, as five copies
/// of one rule do:
///
/// - a rounded clip was re-anchored to the *intersected* rect, so a rounded
///   card scrolling past a `ScrollView` boundary popped its rounding onto the
///   viewport edge mid-scroll;
/// - a nested *square* `.clipped()` inherited its ancestor's radii and applied
///   them at the inner rect's square corners, biting corners out of list rows
///   nowhere near the card's rounded edge;
/// - only two of the five carried radii at all, and only one carried
///   per-corner radii, so the same tree clipped differently depending on which
///   traversal asked.
///
/// One type, one `intersecting(_:radii:uniformRadius:space:)`, three call
/// sites — `appendPrepaintState`, `appendCommands` and
/// `ScenePainter.paintNode`; the two recursive interaction traversals were
/// unreachable and are gone, and interaction now reads the clip prepaint
/// already recorded. Four fields carry what the loose scalars could not:
///
/// - `rect` — the **rejection** rect: the intersection of every clip rect on
///   the chain. Nothing outside it paints, hits or scrolls.
/// - `shapeRect` — the rect the rounding is **anchored** to: the frame of the
///   innermost node that established a rounded clip. It is deliberately *not*
///   narrowed by ancestors, which is what keeps a partially scrolled rounded
///   card rounded at its own corners.
/// - `radii` / `uniformRadius` — the rounding of `shapeRect`.
/// - `space` — which coordinate space the two rects live in. A clip is only
///   ever intersected against a frame in the same space; mixing them is what
///   made the visible clip, the interactive clip and the fallback renderer's
///   clip three different regions under a transform.
///
/// **Why a class.** It was made one when `appendCommands` was still a
/// recursion with an enormous unoptimized frame: a 120-byte clip value copied
/// into every argument and temporary along it cost kilobytes of stack per
/// level, enough to overflow the main thread's 1 MB stack at the demo's depth
/// of ~42, long before `ViewNode.maximumTraversalDepth` could fire. That walk
/// is an explicit worklist now, and the argument survives the change: the clip
/// is stored in a heap traversal record and inherited by every child, where a
/// reference is one word and the value would be fifteen. Every stored property
/// is a `let` and every operation returns a new instance, so this is a value in
/// everything but its 8-byte representation.
///
/// Scene primitives carry both rectangles and all four original radii. A
/// rectangular crop only narrows `rect`; coverage still evaluates the shape
/// anchored at `shapeRect`, including partial arcs left by a thin crop.
/// `resolvedCornerRadius(forQuadRect:)` remains the legacy scalar projection
/// for callers that cannot carry that geometry; it is not the scene mask.
final class RuntimeClipShape: Equatable, Sendable {

    /// The coordinate space a clip's rects are expressed in.
    ///
    /// `.painted` is screen space after the accumulated node transforms, and
    /// it is the space every clip the runtime narrows lives in. It has to be:
    /// one clip value is read by the painter (which writes it into the
    /// axis-aligned primitive clip fields) *and* by interaction, and prepaint
    /// hands its clip verbatim to `ScenePainter` for every deferred subtree
    /// and scroll indicator. A clip narrowed anywhere else would be two
    /// different regions depending on who asked.
    ///
    /// `.layout` is untransformed absolute layout space — the space a node's
    /// `resolvedFrame` chain, `PrepaintInteractionState.frame` and an
    /// inverse-mapped hit point live in. Nothing narrows a clip there; the
    /// case exists so the narrowing API can state which space a rect is in
    /// and a mismatch trips an assertion instead of silently producing a
    /// third region under a transform.
    enum Space: Equatable, Sendable {
        case layout
        case painted
    }

    /// Corners closer together than this count as the same corner. Clip rects
    /// come from `Rect.intersected`, which returns the untouched coordinate
    /// exactly when an edge is not narrowed, so this only absorbs the
    /// accumulated error of a transform chain.
    private static let cornerEpsilon = 1e-6

    /// Nothing outside this rect paints, hits or scrolls.
    let rect: Rect
    /// The rect `radii` / `uniformRadius` are anchored to. Equal to `rect`
    /// until an ancestor narrows a rounded clip.
    let shapeRect: Rect
    /// Per-corner rounding of `shapeRect`, when the clipping node had per-corner
    /// radii. `nil` falls back to `uniformRadius`.
    let radii: RetainedCornerRadii?
    /// Uniform rounding of `shapeRect`. `radii?.maxRadius` when per-corner radii
    /// are present, so a uniform-radius consumer always has an answer.
    let uniformRadius: Double
    /// Rotation of `shapeRect` about its own centre, in radians.
    ///
    /// R-ROT. `rect` is an axis-aligned *rejection* rect and stays one: it is
    /// what every emitter writes into a primitive's clip fields, and the scene
    /// contract has no other shape to offer. For a clip established by a
    /// rotated node that box is √2 too large at 45°, and the region the user
    /// should see is `shapeRect` turned by this angle. Two consumers act on it:
    /// `contains` — so a pointer in the corner the rotated clip does not cover
    /// is rejected — and `ScenePainter`, which routes such a subtree through an
    /// offscreen pass and composites the bitmap back rotated, because that is
    /// the only lowering the primitive ABI can express.
    ///
    /// `allowsDrawing` and `allowsSubtreeTraversal` deliberately keep using the
    /// box: they are *acceptance* predicates, and a superset there costs a
    /// primitive that the clip then rejects per pixel, while a subset loses
    /// content outright.
    let rotation: Double
    let space: Space

    /// Complete circular geometry for scene transport. A uniform clip must
    /// broadcast its ORIGINAL radius, even when the legacy scalar projection
    /// becomes zero because a rectangular crop removed its original corners.
    var sceneCornerRadii: RetainedCornerRadii {
        radii
            ?? RetainedCornerRadii(
                topLeft: uniformRadius, topRight: uniformRadius,
                bottomRight: uniformRadius, bottomLeft: uniformRadius)
    }

    init(
        rect: Rect,
        shapeRect: Rect? = nil,
        radii: RetainedCornerRadii? = nil,
        uniformRadius: Double = 0,
        rotation: Double = 0,
        space: Space
    ) {
        self.rect = rect
        self.shapeRect = shapeRect ?? rect
        self.rotation = rotation.isFinite ? rotation : 0
        // Per-corner radii get the floor the uniform scalar has always had.
        // They used to be copied verbatim, so a negative or non-finite corner
        // survived into `resolvedCornerRadius(forQuadRect:)` and from there
        // into a primitive's `clipCornerRadius` — the one clip field the
        // scene contract clamps but no emitter had to produce sanely. An
        // infinite radius is worse than a wrong one here: it is also the
        // `zone` the corner analysis below builds its rects from.
        let flooredRadii = radii.map(Self.floored)
        let positiveRadii = (flooredRadii?.hasPositiveRadius ?? false) ? flooredRadii : nil
        self.radii = positiveRadii
        self.uniformRadius = positiveRadii?.maxRadius ?? Self.floored(uniformRadius)
        self.space = space
    }

    /// A radius floored at 0, with non-finite mapped to 0 — a square corner
    /// is the degradation every consumer already handles. A radius larger
    /// than its rect is not a defect: both backends clamp rounding to half
    /// the shorter side.
    private static func floored(_ radius: Double) -> Double {
        radius.isFinite ? max(0, radius) : 0
    }

    private static func floored(_ radii: RetainedCornerRadii) -> RetainedCornerRadii {
        RetainedCornerRadii(
            topLeft: floored(radii.topLeft),
            topRight: floored(radii.topRight),
            bottomRight: floored(radii.bottomRight),
            bottomLeft: floored(radii.bottomLeft)
        )
    }

    static func == (lhs: RuntimeClipShape, rhs: RuntimeClipShape) -> Bool {
        lhs === rhs
            || (lhs.rect == rhs.rect && lhs.shapeRect == rhs.shapeRect && lhs.radii == rhs.radii
                && lhs.uniformRadius == rhs.uniformRadius && lhs.rotation == rhs.rotation
                && lhs.space == rhs.space)
    }

    /// The clip a `clipsToBounds` node establishes when no ancestor clips.
    ///
    /// `shape` is the node's frame with its rotation factored out and
    /// `rotation` is that angle; `frame` is the axis-aligned box the two
    /// describe together. They are the same rect, and the angle 0, for every
    /// node that is not rotated.
    static func bounds(
        of frame: Rect,
        shape: Rect? = nil,
        radii: RetainedCornerRadii?,
        uniformRadius: Double,
        rotation: Double = 0,
        space: Space
    ) -> RuntimeClipShape {
        RuntimeClipShape(
            rect: frame, shapeRect: shape ?? frame, radii: radii, uniformRadius: uniformRadius,
            rotation: rotation, space: space)
    }

    /// Narrows this clip by a `clipsToBounds` node's frame.
    ///
    /// Returns `nil` when the result is empty — the node and its whole subtree
    /// are unreachable, which is what every traversal does with it. That is
    /// the runtime's representation of "clips everything", and it is distinct
    /// from an *absent* clip (`Optional<RuntimeClipShape>.none`), which clips
    /// nothing. The scene contract needs the same distinction and cannot use
    /// an optional; see `GPUIClipEncoding` in `SwiftWindowsGraphics`.
    ///
    /// A node with its own rounding re-anchors the shape to *its* frame. A node
    /// without rounding narrows the rejection rect and leaves the anchor alone.
    /// Scene coverage preserves the residual arc at that original anchor; the
    /// legacy scalar projection still reports only surviving corner zones.
    ///
    /// `frameSpace` is the space `frame` is expressed in and it must be this
    /// clip's. Intersecting two rects from different spaces is arithmetically
    /// fine and geometrically meaningless — it is how the interactive clip and
    /// the painted clip became two regions under a transform — so the caller
    /// states the space and a mismatch trips here rather than downstream.
    func intersecting(
        _ frame: Rect,
        shape: Rect? = nil,
        radii nodeRadii: RetainedCornerRadii?,
        uniformRadius nodeRadius: Double,
        rotation nodeRotation: Double = 0,
        space frameSpace: Space
    ) -> RuntimeClipShape? {
        assert(frameSpace == space, "a \(space) clip cannot be narrowed by a \(frameSpace)-space frame")
        guard let narrowed = rect.intersected(with: frame) else {
            return nil
        }
        // A node that turns its own clip re-anchors the shape to its own
        // (unrotated) frame whether or not it rounds it: the rotation is a
        // property of *that* shape, and keeping an ancestor's while adopting
        // this node's box would turn a rect nothing established.
        if (nodeRadii?.hasPositiveRadius ?? false) || nodeRadius > 0 || nodeRotation != 0 {
            return RuntimeClipShape(
                rect: narrowed, shapeRect: shape ?? frame, radii: nodeRadii, uniformRadius: nodeRadius,
                rotation: nodeRotation, space: space)
        }
        return RuntimeClipShape(
            rect: narrowed, shapeRect: shapeRect, radii: radii, uniformRadius: uniformRadius,
            rotation: rotation, space: space)
    }

    /// Per-primitive acceptance: the same overlap test every emitter used.
    func allowsDrawing(_ bounds: Rect) -> Bool {
        rect.intersected(with: bounds) != nil
    }

    /// Whole-subtree culling, which differs from `allowsDrawing` for degenerate
    /// footprints — see `clipAllowsSubtreeTraversal` in `Runtime.swift`.
    func allowsSubtreeTraversal(bounds: Rect) -> Bool {
        clipAllowsSubtreeTraversal(clip: rect, bounds: bounds)
    }

    /// Whether `point` is inside the clipped region.
    ///
    /// The rejection rect answers it outright while the clip is axis-aligned.
    /// A rotated clip's box is a superset of what it actually covers, so the
    /// point is turned back into the shape's own space and tested there —
    /// which is what makes the interactive region the same region the painter
    /// composites, instead of a box √2 too large that accepted pointers in
    /// corners nothing was drawn in.
    func contains(_ point: Point) -> Bool {
        guard rect.contains(point) else { return false }
        guard rotation != 0 else { return true }
        let pivot = Point(x: shapeRect.midX, y: shapeRect.midY)
        let cosR = cos(-rotation)
        let sinR = sin(-rotation)
        let dx = point.x - pivot.x
        let dy = point.y - pivot.y
        return shapeRect.contains(
            Point(x: pivot.x + cosR * dx - sinR * dy, y: pivot.y + sinR * dx + cosR * dy))
    }

    /// Legacy uniform projection retained for scalar compatibility. Scene
    /// coverage uses `shapeRect` and `sceneCornerRadii` instead.
    func resolvedCornerRadius(forQuadRect quadRect: Rect) -> Double {
        resolvedCornerRadius(forQuadRect: quadRect, rejectingOutside: rect)
    }

    /// The uniform clip corner radius one emitted primitive should carry when
    /// it is rejected outside `rejectionRect` rather than this shape's own
    /// rect — which is the case for a node's OWN decoration: a view's
    /// background and border are shaped by the view's own corner radii and
    /// must not be re-rounded by the view's own clip, only by its ancestors'.
    ///
    /// Clip rounding is only visible in the corner zones a primitive actually
    /// reaches, and a corner of the rejection rect is only rounded when the
    /// narrowing that produced it left that corner where the clip shape put it:
    ///
    /// - a primitive reaching no rounded clip-corner zone needs no rounding,
    /// - a primitive reaching corners that all share one radius uses exactly
    ///   that radius (the left segment of a joined control keeps the left
    ///   radius and its square right corners stay square),
    /// - a primitive spanning differently-rounded corners falls back to the
    ///   largest reached radius (the historic uniform approximation).
    ///
    /// An intact shape (`rejectionRect == shapeRect`) with a uniform radius
    /// answers that radius for every primitive, exactly as it did before this
    /// type existed: the zone analysis only engages once an ancestor has
    /// actually cut a corner away, which is precisely the case the old code got
    /// wrong.
    func resolvedCornerRadius(forQuadRect quadRect: Rect, rejectingOutside rejectionRect: Rect) -> Double {
        guard uniformRadius > 0 else {
            return 0
        }

        let cornerRadii = radii ?? RetainedCornerRadii(uniform: uniformRadius)
        let surviving = survivingCornerRadii(cornerRadii, in: rejectionRect)
        if radii == nil, surviving == cornerRadii {
            // Intact uniform clip: the pre-existing rule, unchanged.
            return uniformRadius
        }

        let zone = cornerRadii.maxRadius
        var reached: [Double] = []
        reached.reserveCapacity(4)
        let corners: [(Rect, Double)] = [
            (Rect(x: rejectionRect.minX, y: rejectionRect.minY, width: zone, height: zone), surviving.topLeft),
            (Rect(x: rejectionRect.maxX - zone, y: rejectionRect.minY, width: zone, height: zone), surviving.topRight),
            (
                Rect(x: rejectionRect.maxX - zone, y: rejectionRect.maxY - zone, width: zone, height: zone),
                surviving.bottomRight
            ),
            (
                Rect(x: rejectionRect.minX, y: rejectionRect.maxY - zone, width: zone, height: zone),
                surviving.bottomLeft
            ),
        ]
        for (zoneRect, radius) in corners where quadRect.intersected(with: zoneRect) != nil {
            reached.append(radius)
        }

        guard let first = reached.first else {
            return 0
        }
        return reached.allSatisfy { $0 == first } ? first : (reached.max() ?? 0)
    }

    /// `cornerRadii` with every corner the ancestor chain cut away zeroed. A cut
    /// corner's visible boundary is the ancestor's straight edge, so rounding
    /// it would carve an arc out of the middle of the visible region — the
    /// "corner bites on list rows" bug, and the mid-scroll rounding pop.
    private func survivingCornerRadii(_ cornerRadii: RetainedCornerRadii, in rejectionRect: Rect)
        -> RetainedCornerRadii
    {
        let epsilon = Self.cornerEpsilon
        let left = abs(rejectionRect.minX - shapeRect.minX) <= epsilon
        let top = abs(rejectionRect.minY - shapeRect.minY) <= epsilon
        let right = abs(rejectionRect.maxX - shapeRect.maxX) <= epsilon
        let bottom = abs(rejectionRect.maxY - shapeRect.maxY) <= epsilon
        return RetainedCornerRadii(
            topLeft: left && top ? cornerRadii.topLeft : 0,
            topRight: right && top ? cornerRadii.topRight : 0,
            bottomRight: right && bottom ? cornerRadii.bottomRight : 0,
            bottomLeft: left && bottom ? cornerRadii.bottomLeft : 0
        )
    }
}

extension Optional where Wrapped == RuntimeClipShape {
    /// `clipAllowsDrawing` for an optional clip: no clip allows everything.
    func allowsDrawing(_ bounds: Rect) -> Bool {
        guard let shape = self else { return true }
        return shape.allowsDrawing(bounds)
    }

    func allowsSubtreeTraversal(bounds: Rect) -> Bool {
        guard let shape = self else { return true }
        return shape.allowsSubtreeTraversal(bounds: bounds)
    }

    func contains(_ point: Point) -> Bool {
        guard let shape = self else { return true }
        return shape.contains(point)
    }

    /// The rejection rect an emitter should write into a primitive's clip
    /// fields, or `nil` when the primitive is unclipped.
    var rejectionRect: Rect? {
        self?.rect
    }

    func resolvedCornerRadius(forQuadRect quadRect: Rect) -> Double {
        guard let shape = self else { return 0 }
        return shape.resolvedCornerRadius(forQuadRect: quadRect)
    }

    /// The clip rounding a node's OWN decoration carries: this node's rejection
    /// rect, rounded only by what `self` (its ancestors' clip) imposed.
    func ancestorCornerRadius(forQuadRect quadRect: Rect, rejectingOutside rejectionRect: Rect?) -> Double {
        guard let shape = self, let rejectionRect else { return 0 }
        return shape.resolvedCornerRadius(forQuadRect: quadRect, rejectingOutside: rejectionRect)
    }

    /// Narrows an optional clip by a `clipsToBounds` node's frame. Returns
    /// `nil` when the clip collapses; the caller culls the subtree.
    ///
    /// `shape`/`rotation` describe the node's frame with its rotation factored
    /// out; omitting them (every axis-aligned caller) is the historic
    /// behaviour exactly.
    func narrowed(
        to frame: Rect,
        shape: Rect? = nil,
        radii: RetainedCornerRadii?,
        uniformRadius: Double,
        rotation: Double = 0,
        space: RuntimeClipShape.Space
    ) -> RuntimeClipShape? {
        guard let clip = self else {
            return RuntimeClipShape.bounds(
                of: frame, shape: shape, radii: radii, uniformRadius: uniformRadius, rotation: rotation,
                space: space)
        }
        return clip.intersecting(
            frame, shape: shape, radii: radii, uniformRadius: uniformRadius, rotation: rotation, space: space)
    }
}
