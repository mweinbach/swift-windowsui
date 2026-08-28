import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import WinSDK

/// Text retained by wrapping or truncation, with exact offsets into the source.
/// A source range stays compact until an edit splits it; generated ellipses and
/// separators have no mapping and therefore cannot inherit an unrelated span.
struct TextLayoutFragment: Hashable, Sendable {
    struct Mapping: Hashable, Sendable {
        var outputUTF16Range: Range<Int>
        var sourceUTF16Range: Range<Int>
    }

    let text: String
    private(set) var mappings: [Mapping]

    init(source: String) {
        self.text = source
        let length = source.utf16.count
        self.mappings =
            length > 0
            ? [Mapping(outputUTF16Range: 0..<length, sourceUTF16Range: 0..<length)]
            : []
    }

    init(synthetic: String) {
        self.text = synthetic
        self.mappings = []
    }

    private init(text: String, mappings: [Mapping]) {
        self.text = text
        self.mappings = mappings
    }

    func slice(_ range: Range<String.Index>) -> Self {
        if range.lowerBound == text.startIndex, range.upperBound == text.endIndex {
            return self
        }
        // Scalar slicing also preserves Foundation's whitespace-trimming
        // behavior when a whitespace scalar shares a grapheme with a mark.
        let slicedText = String(text.unicodeScalars[range])
        guard !mappings.isEmpty, !slicedText.isEmpty else {
            return Self(synthetic: slicedText)
        }

        let lower = range.lowerBound.utf16Offset(in: text)
        let upper = range.upperBound.utf16Offset(in: text)
        let clipped = mappings.compactMap { mapping -> Mapping? in
            let start = max(lower, mapping.outputUTF16Range.lowerBound)
            let end = min(upper, mapping.outputUTF16Range.upperBound)
            guard start < end else { return nil }
            let sourceStart = mapping.sourceUTF16Range.lowerBound + start - mapping.outputUTF16Range.lowerBound
            return Mapping(
                outputUTF16Range: (start - lower)..<(end - lower),
                sourceUTF16Range: sourceStart..<(sourceStart + end - start))
        }
        return Self(text: slicedText, mappings: clipped)
    }

    func prefix(_ count: Int) -> Self {
        let end = text.index(text.startIndex, offsetBy: max(0, count), limitedBy: text.endIndex) ?? text.endIndex
        return slice(text.startIndex..<end)
    }

    func suffix(_ count: Int) -> Self {
        let start = text.index(text.endIndex, offsetBy: -max(0, count), limitedBy: text.startIndex) ?? text.startIndex
        return slice(start..<text.endIndex)
    }

    func droppingFirst(_ count: Int) -> Self {
        let start = text.index(text.startIndex, offsetBy: max(0, count), limitedBy: text.endIndex) ?? text.endIndex
        return slice(start..<text.endIndex)
    }

    func trimmingWhitespace() -> Self {
        let scalars = text.unicodeScalars
        let whitespace = CharacterSet.whitespaces
        var start = scalars.startIndex
        var end = scalars.endIndex
        while start < end, whitespace.contains(scalars[start]) {
            scalars.formIndex(after: &start)
        }
        while start < end {
            let previous = scalars.index(before: end)
            guard whitespace.contains(scalars[previous]) else { break }
            end = previous
        }
        return slice(start..<end)
    }

    func words() -> [Self] {
        text.split(whereSeparator: \.isWhitespace).map { slice($0.startIndex..<$0.endIndex) }
    }

    /// LF, CR, and CRLF each end one line. Slicing the original string keeps
    /// CRLF's two source code units from shifting every later span by one.
    func normalizedLines() -> [Self] {
        let scalars = text.unicodeScalars
        var lineStart = scalars.startIndex
        var cursor = lineStart
        var lines: [Self] = []
        while cursor < scalars.endIndex {
            let scalar = scalars[cursor]
            var next = scalars.index(after: cursor)
            if scalar == "\n" || scalar == "\r" {
                lines.append(slice(lineStart..<cursor))
                if scalar == "\r", next < scalars.endIndex, scalars[next] == "\n" {
                    scalars.formIndex(after: &next)
                }
                lineStart = next
            }
            cursor = next
        }
        lines.append(slice(lineStart..<scalars.endIndex))
        return lines
    }

    func appending(_ other: Self) -> Self {
        if text.isEmpty { return other }
        if other.text.isEmpty { return self }
        return Self.joined([self, other], separator: Self(synthetic: ""))
    }

    static func joined(_ parts: [Self], separator: Self) -> Self {
        guard !parts.isEmpty else { return Self(synthetic: "") }
        if parts.count == 1 { return parts[0] }

        let tracksSource = !separator.mappings.isEmpty || parts.contains { !$0.mappings.isEmpty }
        var combinedText = ""
        var combinedMappings: [Mapping] = []
        var outputOffset = 0

        func append(_ part: Self) {
            combinedText.append(contentsOf: part.text)
            guard tracksSource else { return }
            for mapping in part.mappings {
                let outputStart = mapping.outputUTF16Range.lowerBound + outputOffset
                let outputEnd = mapping.outputUTF16Range.upperBound + outputOffset
                let outputRange = outputStart..<outputEnd
                if let last = combinedMappings.last,
                    last.outputUTF16Range.upperBound == outputRange.lowerBound,
                    last.sourceUTF16Range.upperBound == mapping.sourceUTF16Range.lowerBound
                {
                    combinedMappings[combinedMappings.count - 1] = Mapping(
                        outputUTF16Range: last.outputUTF16Range.lowerBound..<outputRange.upperBound,
                        sourceUTF16Range: last.sourceUTF16Range.lowerBound..<mapping.sourceUTF16Range.upperBound)
                } else {
                    combinedMappings.append(
                        Mapping(outputUTF16Range: outputRange, sourceUTF16Range: mapping.sourceUTF16Range))
                }
            }
            outputOffset += part.text.utf16.count
        }

        for index in parts.indices {
            if index != parts.startIndex { append(separator) }
            append(parts[index])
        }
        return Self(text: combinedText, mappings: combinedMappings)
    }

    /// Called only for adjacent words from one normalized source line. Their
    /// source gap begins at the first original whitespace scalar (one UTF-16
    /// unit), which supplies the provenance of the normalized normal space.
    static func wordSeparator(after: Self, before: Self) -> Self {
        guard let previous = after.mappings.last, let next = before.mappings.first,
            previous.outputUTF16Range.upperBound == after.text.utf16.count,
            next.outputUTF16Range.lowerBound == 0,
            previous.sourceUTF16Range.upperBound < next.sourceUTF16Range.lowerBound
        else {
            return Self(synthetic: " ")
        }
        let sourceStart = previous.sourceUTF16Range.upperBound
        return Self(
            text: " ",
            mappings: [Mapping(outputUTF16Range: 0..<1, sourceUTF16Range: sourceStart..<(sourceStart + 1))])
    }

    /// Intersect each source span with the retained ranges. In particular,
    /// identical words at different source offsets retain different styles;
    /// generated ellipses are left in the paragraph's base style.
    func rebasedStyle(_ style: PixelTextStyle, sourceText: String) -> PixelTextStyle {
        guard let spans = style.spans, !spans.isEmpty else { return style }
        var rebased = style
        guard !mappings.isEmpty else {
            rebased.spans = nil
            return rebased
        }

        let sourceUTF16 = sourceText.utf16
        var outputSpans: [TextSpan] = []
        for span in spans {
            guard let range = span.range else { continue }
            let lowerBound = max(sourceText.startIndex, range.lowerBound)
            let upperBound = min(sourceText.endIndex, range.upperBound)
            guard lowerBound < upperBound,
                let start = lowerBound.samePosition(in: sourceUTF16),
                let end = upperBound.samePosition(in: sourceUTF16)
            else { continue }
            let sourceStart = sourceUTF16.distance(from: sourceUTF16.startIndex, to: start)
            let sourceEnd = sourceUTF16.distance(from: sourceUTF16.startIndex, to: end)
            for mapping in mappings {
                let lower = max(sourceStart, mapping.sourceUTF16Range.lowerBound)
                let upper = min(sourceEnd, mapping.sourceUTF16Range.upperBound)
                guard lower < upper else { continue }
                let outputStart = mapping.outputUTF16Range.lowerBound + lower - mapping.sourceUTF16Range.lowerBound
                let outputEnd = outputStart + upper - lower
                let outputRange =
                    String.Index(utf16Offset: outputStart, in: text)..<String.Index(utf16Offset: outputEnd, in: text)
                outputSpans.append(
                    TextSpan(text: String(text.unicodeScalars[outputRange]), style: span.style, range: outputRange))
            }
        }
        rebased.spans = outputSpans.isEmpty ? nil : outputSpans
        return rebased
    }
}

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

/// Editor-only geometry, copied out while the native layout is alive. These
/// values contain no COM object and use grapheme offsets into one whole line.
struct NativeTextEditingCaret: Equatable, Sendable {
    var characterOffset: Int
    var affinity: RetainedTextSelectionAffinity
    var x: Double
}

struct NativeTextEditingRegion: Equatable, Sendable {
    var characterRange: Range<Int>
    var rect: Rect
}

struct NativeTextEditingLine: Equatable, Sendable {
    var text: String
    var width: Double
    var height: Double
    var carets: [NativeTextEditingCaret]
    var selectionRegions: [NativeTextEditingRegion]
    /// Native positive leading is already part of height. The pixel fallback
    /// keeps its separate inter-line spacing here, without adding it twice.
    var lineSpacing: Double = 0
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
