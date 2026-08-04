import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics

/// WS-19. The result of lowering a node's effective transform into the two
/// things the scene contract can actually carry: an axis-aligned rect, and
/// `QuadPrimitive.rotationRadians`.
///
/// `Rect.applying(transform:)` returns the *bounding box* of the four
/// transformed corners, so painting straight through it turned every rotated
/// node into an unrotated rectangle up to `√2` too large. The quad families
/// have carried a rotation since the tessellator started emitting diagonal
/// stroke segments (`PathToQuadTessellator.strokedSegmentQuad`); this type is
/// how a *node* reaches the same encoding.
///
/// Three values, deliberately kept apart:
///
/// - `frame` is the node's rect with translation and uniform scale applied and
///   the rotation factored out. It is what a rotation-capable primitive
///   carries, together with `rotation`.
/// - `rotation` is the angle about `frame`'s centre. It is exactly `0` for
///   every transform that is not a rotation — including shears, mirrors and
///   non-uniform scales, which fall back to the bounding box because the
///   encoding cannot express them.
/// - `boundingBox` is the axis-aligned footprint of the rotated rect: the
///   value every *predicate* uses (clip narrowing, culling, occlusion) and the
///   value the families with no rotation field (shadow, image, glyph, path)
///   still paint into. The scene contract's clip is an axis-aligned rect in
///   screen space, so a rotated clip stays an AABB — the documented residual
///   in `docs/GPURenderingPipeline.md`.
///
/// When `rotation == 0` — every axis-aligned tree, which is nearly all of
/// them — `frame` and `boundingBox` are the same value produced by the same
/// call as before, and `place`/`footprint` are the identity. The historic
/// output stays byte for byte identical.
struct PaintPlacement {
    var frame: Rect
    var rotation: Double
    var boundingBox: Rect

    var isRotated: Bool { rotation != 0 }

    static let identityTolerance = 1e-9

    /// The axis-aligned placement: no rotation lowered, bounding box and frame
    /// the same rect. Used directly by the frame path, which has no rotation
    /// encoding at all.
    static func axisAligned(_ rect: Rect) -> PaintPlacement {
        PaintPlacement(frame: rect, rotation: 0, boundingBox: rect)
    }

    /// Lowers `transform` applied to `localFrame`.
    ///
    /// The rotation is only separable when the transform's linear part is a
    /// *similarity* — a rotation composed with a uniform scale, with no
    /// reflection and no shear. In matrix terms (row-vector convention, the
    /// one `Point.applying` uses) that is `a == d` and `b == -c`: a rotation
    /// by θ scaled by s is `(s·cosθ, s·sinθ, -s·sinθ, s·cosθ)`. A mirror
    /// flips the sign of `d`, a non-uniform scale breaks `a == d`, and a shear
    /// breaks `b == -c`; all three fall back to the bounding box, which is
    /// what the painter did for everything before this existed.
    ///
    /// The mirror case is reachable, and this is where it stops. `Transform2D`
    /// carries a reflection through its decomposition as a negative scale
    /// (R-MISC), so a mirror now arrives here as a mirror instead of as the
    /// half turn it used to degenerate into — and a half turn *is* a
    /// similarity, so the degenerate form was lowered as `rotation = π` and
    /// drew upside down. The `a == d ∧ b == -c` test excludes reflections
    /// structurally: it forces `det = a² + b² > 0`. A reflection therefore
    /// paints into its bounding box, which is exact for the box and for every
    /// descendant's placement, and unmirrored for the content inside it —
    /// the scene contract has a rotation on its primitives and no reflection.
    /// See `TransformReflectionTests`.
    static func lowering(_ localFrame: Rect, through transform: Transform2D) -> PaintPlacement {
        guard !transform.isIdentity else {
            return .axisAligned(localFrame)
        }
        let matrix = transform.matrix
        let boundingBox = localFrame.applying(transform: transform)

        let scale = (matrix.a * matrix.a + matrix.b * matrix.b).squareRoot()
        guard scale.isFinite, scale > Self.identityTolerance else {
            return .axisAligned(boundingBox)
        }
        // Scale-relative tolerance: the comparison is between matrix entries
        // that are all O(scale).
        let tolerance = Self.identityTolerance * max(1, scale)
        guard abs(matrix.a - matrix.d) <= tolerance, abs(matrix.b + matrix.c) <= tolerance else {
            return .axisAligned(boundingBox)
        }

        let rotation = atan2(matrix.b, matrix.a)
        // A similarity with no rotation is a plain scale-and-translate, and
        // its bounding box *is* its frame — take the historic path so the
        // unrotated output stays bit-identical rather than round-tripping
        // through a centre and a half-extent.
        guard rotation != 0, rotation.isFinite else {
            return .axisAligned(boundingBox)
        }

        let centre = Point(x: localFrame.midX, y: localFrame.midY).applying(transform)
        let width = localFrame.size.width * scale
        let height = localFrame.size.height * scale
        let frame = Rect(
            x: centre.x - width * 0.5,
            y: centre.y - height * 0.5,
            width: width,
            height: height
        )
        // `boundingBox` is the bounding box `Rect.applying(transform:)` already
        // produced: rotating `frame` about `centre` by `rotation` reproduces
        // exactly the four transformed corners, because the linear part is a
        // similarity. Reusing that value keeps the painter bit-identical with
        // prepaint and the frame path, which have no rotation encoding and
        // compute the box directly.
        return PaintPlacement(frame: frame, rotation: rotation, boundingBox: boundingBox)
    }

    /// Maps a rect expressed in the node's unrotated paint space onto the rect
    /// a rotation-capable primitive carries: same size, centre turned about
    /// the node's centre. Rotation is rigid, so a rotated rect is still a rect
    /// — the primitive's own `rotationRadians` supplies the orientation the
    /// origin/size pair cannot.
    func place(_ rect: Rect) -> Rect {
        guard isRotated else { return rect }
        let pivot = Point(x: frame.midX, y: frame.midY)
        let centre = Self.rotate(Point(x: rect.midX, y: rect.midY), by: rotation, about: pivot)
        return Rect(
            x: centre.x - rect.size.width * 0.5,
            y: centre.y - rect.size.height * 0.5,
            width: rect.size.width,
            height: rect.size.height
        )
    }

    /// The axis-aligned footprint of `rect` once the node's rotation is
    /// applied. What the clip predicates compare against, and where the
    /// families with no rotation field paint.
    ///
    /// `place` has already turned the rect's centre about the node's centre,
    /// so the only rotation left is the rect's own, about *its* centre — the
    /// half-extents of a rect turned in place are
    /// `(|cos|·w + |sin|·h)/2` and `(|sin|·w + |cos|·h)/2`. Turning the placed
    /// rect about the node's centre a second time would rotate it twice.
    func footprint(of rect: Rect) -> Rect {
        guard isRotated else { return rect }
        let placed = place(rect)
        let cosR = abs(cos(rotation))
        let sinR = abs(sin(rotation))
        let width = cosR * placed.size.width + sinR * placed.size.height
        let height = sinR * placed.size.width + cosR * placed.size.height
        return Rect(
            x: placed.midX - width * 0.5,
            y: placed.midY - height * 0.5,
            width: width,
            height: height
        )
    }

    /// Maps a rect that is already in *device* space onto where the node's
    /// rotation puts it: same size, centre turned about the node's centre
    /// scaled by `displayScale`.
    ///
    /// Device space is the logical space scaled by a *uniform* `displayScale`,
    /// and a uniform scale commutes with a rotation about a correspondingly
    /// scaled pivot — so turning here is exact, and it keeps the rotation off
    /// every one of the painter's primitive constructors. An unrotated
    /// placement returns the rect untouched, so axis-aligned emission stays
    /// bit-identical.
    ///
    /// The orientation itself is not in the return value: the caller writes it
    /// into the primitive's own `rotationRadians`, which is what turns the
    /// rect in place about the centre this positions.
    func placingDevice(_ rect: Rect, displayScale: Double) -> Rect {
        guard isRotated else { return rect }
        let pivot = Point(x: frame.midX * displayScale, y: frame.midY * displayScale)
        let centre = Self.rotate(
            Point(x: rect.midX, y: rect.midY),
            by: rotation,
            about: pivot
        )
        return Rect(
            x: centre.x - rect.size.width * 0.5,
            y: centre.y - rect.size.height * 0.5,
            width: rect.size.width,
            height: rect.size.height
        )
    }

    /// Turns a *displacement* by the lowered rotation. A vector has no
    /// position, so there is no pivot: only the linear part applies.
    ///
    /// It exists for the one value the scene contract carries next to a rect
    /// instead of inside it — `ShadowPrimitive.offset`, which both backends add
    /// to the primitive's origin in screen space. A shadow's offset is authored
    /// in the shadowed view's own space (`.shadow(y: 14)` on a card that is
    /// then turned 90° casts to the card's *side*), so the offset has to arrive
    /// already turned, or the halo slides down-screen while the card lies on
    /// its side.
    func turning(_ vector: Point) -> Point {
        guard isRotated else { return vector }
        let cosR = cos(rotation)
        let sinR = sin(rotation)
        return Point(
            x: cosR * vector.x - sinR * vector.y,
            y: sinR * vector.x + cosR * vector.y
        )
    }

    /// The axis-aligned region of the node's *unrotated* paint space that can
    /// still reach `rect` once the node's rotation is applied — the preimage
    /// of `rect` under `place`, widened to a box.
    ///
    /// It exists for the one thing a screen-space clip rect is used for
    /// besides being written into a primitive: **culling** content that is
    /// laid out before the rotation is applied. Text is the case that needs
    /// it — a run is laid out in the node's own space and only then turned —
    /// and comparing an un-turned glyph cell against the turned clip drops
    /// glyphs that the rotation would have brought inside it. Rotation is
    /// rigid, so the box is a superset: it can keep a glyph the clip will
    /// reject per pixel, never drop one it would have shown.
    func unplacedFootprint(of rect: Rect) -> Rect {
        guard isRotated else { return rect }
        let pivot = Point(x: frame.midX, y: frame.midY)
        let centre = Self.rotate(Point(x: rect.midX, y: rect.midY), by: -rotation, about: pivot)
        let cosR = abs(cos(rotation))
        let sinR = abs(sin(rotation))
        let width = cosR * rect.size.width + sinR * rect.size.height
        let height = sinR * rect.size.width + cosR * rect.size.height
        return Rect(
            x: centre.x - width * 0.5,
            y: centre.y - height * 0.5,
            width: width,
            height: height
        )
    }

    /// Applies the lowered rotation to a quad that is already in device space.
    func rotating(_ quad: QuadPrimitive, displayScale: Double) -> QuadPrimitive {
        guard isRotated else { return quad }
        var rotated = quad
        let placed = placingDevice(
            Rect(
                x: Double(quad.x), y: Double(quad.y),
                width: Double(quad.width), height: Double(quad.height)),
            displayScale: displayScale)
        rotated.x = Float(placed.origin.x)
        rotated.y = Float(placed.origin.y)
        rotated.rotationRadians = Float(rotation)
        return rotated
    }

    /// Applies the lowered rotation to a glyph cell that is already in device
    /// space. Text laid out in the node's own space reaches its turned
    /// position here; the atlas UVs are untouched, because both backends
    /// sample the cell in unrotated cell coordinates.
    func rotating(_ glyph: GlyphPrimitive, displayScale: Double) -> GlyphPrimitive {
        guard isRotated else { return glyph }
        var rotated = glyph
        let placed = placingDevice(
            Rect(
                x: Double(glyph.screenX), y: Double(glyph.screenY),
                width: Double(glyph.screenW), height: Double(glyph.screenH)),
            displayScale: displayScale)
        rotated.screenX = Float(placed.origin.x)
        rotated.screenY = Float(placed.origin.y)
        rotated.rotationRadians = Float(rotation)
        return rotated
    }

    /// Applies the lowered rotation to an image that is already in device
    /// space — the composited result of an offscreen pass under a rotated
    /// transform.
    func rotating(_ image: ImagePrimitive, displayScale: Double) -> ImagePrimitive {
        guard isRotated else { return image }
        var rotated = image
        let placed = placingDevice(
            Rect(
                x: Double(image.screenX), y: Double(image.screenY),
                width: Double(image.screenW), height: Double(image.screenH)),
            displayScale: displayScale)
        rotated.screenX = Float(placed.origin.x)
        rotated.screenY = Float(placed.origin.y)
        rotated.rotationRadians = Float(rotation)
        return rotated
    }

    private static func rotate(_ point: Point, by angle: Double, about pivot: Point) -> Point {
        let cosR = cos(angle)
        let sinR = sin(angle)
        let dx = point.x - pivot.x
        let dy = point.y - pivot.y
        return Point(x: pivot.x + cosR * dx - sinR * dy, y: pivot.y + sinR * dx + cosR * dy)
    }
}
