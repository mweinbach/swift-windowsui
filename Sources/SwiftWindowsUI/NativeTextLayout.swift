import Foundation

import SwiftWindowsCore

import SwiftWindowsGraphics

import WinSDK

/// Vertical frame a glyph's `origin.y` / `bearingY` is measured in.
///
/// The two rasterizers disagree by one ascent: `rasterizeCapturedGlyph` draws a
/// shaped glyph run at a known baseline and reports ink relative to *that*,
/// while `rasterizeGlyph(Character:)` lays a single character out in its own box
/// and reports ink relative to the box top. Both are correct; mixing them is
/// not, and until this type existed both travelled in the same untyped `Float`.
/// The frame now rides along with the value so the painter can anchor each
/// raster against the matching origin instead of assuming they agree.
enum GlyphVerticalFrame: Hashable, Sendable {
    /// Measured downward from the line's layout-box top (always ≥ 0 for ink
    /// inside the box).
    case layoutBoxTop
    /// Measured downward from the text baseline (negative above the baseline).
    case baseline
}

/// A font face identity that is stable for as long as any atlas entry can refer
/// to it. See `FontFaceRegistry`.
struct FontFaceID: Hashable, Sendable {
    var rawValue: UInt64
}

/// Anything the registry can hand out an ID for. `faceAddress` is the COM
/// object's address; the registry keeps the conforming object alive so that
/// address cannot be recycled underneath a live ID.
protocol RetainedFontFace: AnyObject {
    var faceAddress: UInt { get }
}

/// Monotonic font-face identity.
///
/// `GlyphKey.fontFaceID` used to be the raw `IDWriteFontFace` address, and the
/// atlas stored only the integer — so once every layout referencing a face was
/// evicted, the handle released the COM object and a *different* face allocated
/// at the same address inherited its atlas entries. The registry fixes both
/// halves: IDs are handed out monotonically (never recycled) and each face is
/// retained for the process lifetime of its ID, so an address can never be
/// reused while entries keyed on it are live.
///
/// Retention is a fixed cost rather than a leak only if the live face count is
/// bounded, and that rests on DirectWrite handing the same `IDWriteFontFace`
/// back for a given face — which it does in practice and nowhere promises.
/// Shaping runs per glyph run, so every run is a chance for the assumption to
/// be wrong. `registeredFaceCount` makes the count observable and
/// `reportThreshold` makes the assumption falsifiable at runtime: crossing it
/// reports once to stderr instead of growing silently forever.
@MainActor
final class FontFaceRegistry {
    static let shared = FontFaceRegistry()

    /// Faces a healthy process is expected to stay under. Segoe UI plus every
    /// script fallback plus the italic and weight variants of each is a few
    /// dozen; 256 is far enough above that to be a real signal rather than a
    /// tight bound, and low enough to catch a per-run leak long before the
    /// retained COM objects matter.
    static let reportThreshold = 256

    private var identifiers: [UInt: FontFaceID] = [:]
    private var retained: [UInt: any RetainedFontFace] = [:]
    private var nextRawValue: UInt64 = 1

    init() {}

    var registeredFaceCount: Int {
        identifiers.count
    }

    /// True once `registeredFaceCount` has crossed `reportThreshold`. The
    /// registry keeps working — a threshold is a report, not a policy — but
    /// the bounded-in-practice claim above is now known to be false on this
    /// machine.
    private(set) var hasExceededReportThreshold = false

    /// Stable ID for `face`, registering (and retaining) it on first sight.
    func identifier(for face: any RetainedFontFace) -> FontFaceID {
        let address = face.faceAddress
        if let existing = identifiers[address] {
            return existing
        }

        let identifier = FontFaceID(rawValue: nextRawValue)
        nextRawValue += 1
        identifiers[address] = identifier
        retained[address] = face
        reportThresholdCrossingIfNeeded()
        return identifier
    }

    private func reportThresholdCrossingIfNeeded() {
        guard !hasExceededReportThreshold, identifiers.count > Self.reportThreshold else {
            return
        }
        hasExceededReportThreshold = true
        FileHandle.standardError.write(
            Data(
                """
                [SwiftWindowsUI] font-face registry passed \(Self.reportThreshold) retained faces \
                (\(identifiers.count) live). Faces are retained for the process lifetime of their ID, \
                so this is unbounded growth rather than a cache: DirectWrite is handing back distinct \
                `IDWriteFontFace` objects for faces this stack assumed it would share.

                """.utf8
            )
        )
    }

    /// Test-only: drop every registration so an ID sequence can be asserted
    /// from a known starting point.
    func resetForTesting() {
        identifiers.removeAll()
        retained.removeAll()
        nextRawValue = 1
        hasExceededReportThreshold = false
    }
}

final class NativeFontFaceHandle: @unchecked Sendable {
    private let rawValue: UInt

    init?(_ rawPointer: UnsafeMutableRawPointer?) {
        guard let rawPointer else {
            return nil
        }

        let unknown = rawPointer.assumingMemoryBound(to: IUnknown.self)
        _ = unknown.pointee.lpVtbl.pointee.AddRef(unknown)

        self.rawValue = UInt(bitPattern: rawPointer)
    }

    var rawPointer: UnsafeMutableRawPointer {
        UnsafeMutableRawPointer(bitPattern: rawValue)!
    }

    deinit {
        guard let rawPointer = UnsafeMutableRawPointer(bitPattern: rawValue) else {
            return
        }
        let unknown = rawPointer.assumingMemoryBound(to: IUnknown.self)
        _ = unknown.pointee.lpVtbl.pointee.Release(unknown)
    }
}
extension NativeFontFaceHandle: RetainedFontFace {
    var faceAddress: UInt { rawValue }
}
struct NativeTextGlyphLayout: Sendable {
    var character: Character
    var origin: Point
    var advance: Double
    var glyphID: UInt32? = nil
    var fontFace: NativeFontFaceHandle? = nil
    /// Registry ID of `fontFace`, resolved on the main actor at capture time.
    /// Raw addresses alias; this does not.
    var fontFaceID: FontFaceID? = nil
    var fontFamily: String = "Segoe UI"
    var weight: TextWeight = .regular
    var fontSize: Double = 0
    var sourceIndex: Int? = nil
    /// Frame `origin.y` is measured in. Shaped runs report a baseline; the
    /// per-character hit-test walk reports the line top.
    var verticalFrame: GlyphVerticalFrame = .layoutBoxTop

    static func == (lhs: NativeTextGlyphLayout, rhs: NativeTextGlyphLayout) -> Bool {
        lhs.character == rhs.character
            && lhs.origin == rhs.origin
            && lhs.advance == rhs.advance
            && lhs.glyphID == rhs.glyphID
            && lhs.fontFaceID == rhs.fontFaceID
            && lhs.fontFamily == rhs.fontFamily
            && lhs.weight == rhs.weight
            && lhs.fontSize == rhs.fontSize
            && lhs.sourceIndex == rhs.sourceIndex
            && lhs.verticalFrame == rhs.verticalFrame
    }
}
extension NativeTextGlyphLayout: Equatable {}
struct NativeTextLineLayout: Equatable, Sendable {
    var text: String
    var width: Double
    var height: Double
    var ascent: Double = 0
    var descent: Double = 0
    var glyphs: [NativeTextGlyphLayout]
}
struct NativeTextLayoutResult: Equatable, Sendable {
    var lines: [NativeTextLineLayout]
    var lineSpacing: Double = 0
    var contentSize: Size
    var measuredSize: Size
}
struct NativeGlyphBitmap: Equatable, Sendable {
    var surface: BitmapSurface
    var bearingX: Float
    var bearingY: Float
    var advance: Float
    /// Frame `bearingY` is measured in — see `GlyphVerticalFrame`.
    var verticalFrame: GlyphVerticalFrame = .layoutBoxTop

    var width: Int32 { surface.width }
    var height: Int32 { surface.height }
    var pixels: Data { surface.pixels }
}
