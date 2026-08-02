import SwiftWindowsCore

/// How the four float clip fields on `QuadPrimitive`, `GlyphPrimitive`,
/// `ImagePrimitive` and `ShadowPrimitive` encode a clip.
///
/// Four floats have to say three things — "no clip", "this rect", and "clip
/// everything" — and until this type existed they could only say two. The
/// in-band sentinel was `clipWidth == clipHeight == 0` meaning *unclipped*, so
/// a container whose clip collapsed to nothing (a `.clipped()` view animating
/// closed, a collapsed disclosure row, a zero-height scroll viewport) did not
/// hide its children: it **removed their clip**, and they painted at full size
/// across the whole window. `contentMaskedBounds` rejected the *asymmetric*
/// collapse (`0 × h`, `w × 0`) and documented the symmetric one as "no clip",
/// which is the accessor asymmetry this closes.
///
/// The distinction the encoding was missing is already in the data: an absent
/// clip is *all four* fields zero — the value every unclipped primitive has had
/// since the contract was written — while a clip that is positioned but
/// collapsed, or has a negative extent, is an explicitly empty clip and rejects
/// its primitive. So `(0, 0, 0, 0)` still means unclipped, `(10, 10, 0, 0)` now
/// means "clips everything" rather than "clips nothing", and `emptyExtent` gives
/// a producer a canonical way to say it even at the origin.
///
/// `PathPrimitive` needs none of this: it carries `clipBounds: Rect?`, where
/// `nil` already means unclipped, so a present collapsed clip there has always
/// been empty and nothing else.
public enum GPUIClipEncoding {

    /// The canonical "clips everything" extent. Negative rather than zero so an
    /// empty clip at the origin stays distinguishable from an absent one, and so
    /// a consumer that only checks `> 0` (every shipping pixel shader does)
    /// treats it as inactive rather than as a huge rect. The scene boundary
    /// rejects these primitives before any backend sees them.
    public static let emptyExtent: Float = -1

    /// The clip fields of an unclipped primitive.
    public static let unclipped: (x: Float, y: Float, width: Float, height: Float) = (0, 0, 0, 0)

    /// True when the four fields carry no clip at all.
    public static func isAbsent(clipX: Float, clipY: Float, clipWidth: Float, clipHeight: Float) -> Bool {
        clipX == 0 && clipY == 0 && clipWidth == 0 && clipHeight == 0
    }

    /// True when the four fields carry a clip that rejects every pixel.
    public static func isEmpty(clipX: Float, clipY: Float, clipWidth: Float, clipHeight: Float) -> Bool {
        guard !isAbsent(clipX: clipX, clipY: clipY, clipWidth: clipWidth, clipHeight: clipHeight) else {
            return false
        }
        return !(clipWidth > 0) || !(clipHeight > 0)
    }

    /// The content mask the four fields describe: `nil` bounds for an absent
    /// clip *and* for an empty one, since `GPUIContentMask` cannot express
    /// emptiness either. Emptiness is decided by `isEmpty` before the mask is
    /// consulted — see `contentMaskedBounds` in `GPUIScene.swift`.
    public static func contentMask(clipX: Float, clipY: Float, clipWidth: Float, clipHeight: Float)
        -> GPUIContentMask
    {
        guard clipWidth > 0, clipHeight > 0 else {
            return GPUIContentMask()
        }
        return GPUIContentMask(
            bounds: Rect(
                x: Double(clipX), y: Double(clipY), width: Double(clipWidth), height: Double(clipHeight)))
    }

    /// Writes a content mask into a primitive's four clip fields.
    public static func encode(
        _ bounds: Rect?, into clipX: inout Float, _ clipY: inout Float, _ clipWidth: inout Float,
        _ clipHeight: inout Float
    ) {
        guard let bounds else {
            clipX = unclipped.x
            clipY = unclipped.y
            clipWidth = unclipped.width
            clipHeight = unclipped.height
            return
        }
        clipX = Float(bounds.origin.x)
        clipY = Float(bounds.origin.y)
        clipWidth = Float(bounds.size.width)
        clipHeight = Float(bounds.size.height)
    }
}
