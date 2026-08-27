import Foundation

import SwiftWindowsCore

import SwiftWindowsGraphics

struct TextRasterCacheKey: Hashable, Sendable {
    var text: String
    var fontFamily: String
    var scale: Double
    /// Device scale the bitmap was rasterized at. Two windows at different
    /// DPI ask for the same string in the same style and need different
    /// pixels, so this belongs in the key — which is also why the cache needs
    /// no scale-change invalidation hook: a scale change is a different key,
    /// not a stale entry.
    var renderScale: Double
    var nativeFontSize: Double?
    var weight: TextWeight
    var fontWidth: TextFontWidth
    var isItalic: Bool
    var monospacedDigits: Bool
    var lowercaseSmallCaps: Bool
    var uppercaseSmallCaps: Bool
    var alignment: TextHorizontalAlignment
    var verticalAlignment: TextVerticalAlignment
    var lineSpacing: Double
    var letterSpacing: Double
    var nativeLetterSpacing: Double?
    var lineBreakMode: TextLineBreakMode
    var maximumNumberOfLines: Int?
    var minimumNumberOfLines: Int?
    var minimumScaleFactor: Double
    var reservesLineLimitSpace: Bool
    var insetsTop: Double
    var insetsLeading: Double
    var insetsBottom: Double
    var insetsTrailing: Double
    var width: Double
    var height: Double
    var colorRed: Float
    var colorGreen: Float
    var colorBlue: Float
    var colorAlpha: Float
    var underline: Bool
    var underlinePattern: TextDecorationPattern
    var underlineColorRed: Float?
    var underlineColorGreen: Float?
    var underlineColorBlue: Float?
    var underlineColorAlpha: Float?
    var strikethrough: Bool
    var strikethroughPattern: TextDecorationPattern
    var strikethroughColorRed: Float?
    var strikethroughColorGreen: Float?
    var strikethroughColorBlue: Float?
    var strikethroughColorAlpha: Float?
    var enableKerning: Bool
    var spans: [SpanKey]

    struct SpanKey: Hashable, Sendable {
        var utf16RangeStart: Int?
        var utf16RangeLength: Int?
        var style: TextRasterCacheKey

        init(span: TextSpan, in text: String) {
            // Use the layout cache's structural range, not String.Index identity.
            // A rebuilt string with the same spans must still hit the cache.
            let layoutSpan = WindowTextSystem.LayoutSpanKey(span: span, in: text)
            self.utf16RangeStart = layoutSpan.utf16RangeStart
            self.utf16RangeLength = layoutSpan.utf16RangeLength
            // Span paint inputs matter too, so use the complete raster key rather
            // than only the font and layout fields in LayoutSpanKey.
            self.style = TextRasterCacheKey(text: span.text, style: span.style, size: .zero)
        }
    }

    init(text: String, style: PixelTextStyle, size: Size, renderScale: Double = 1) {
        self.text = text
        self.fontFamily = style.fontFamily
        self.scale = style.scale
        self.renderScale = renderScale
        self.nativeFontSize = style.nativeFontSize
        self.weight = style.weight
        self.fontWidth = style.fontWidth
        self.isItalic = style.isItalic
        self.monospacedDigits = style.monospacedDigits
        self.lowercaseSmallCaps = style.lowercaseSmallCaps
        self.uppercaseSmallCaps = style.uppercaseSmallCaps
        self.alignment = style.alignment
        self.verticalAlignment = style.verticalAlignment
        self.lineSpacing = style.lineSpacing
        self.letterSpacing = style.letterSpacing
        self.nativeLetterSpacing = style.nativeLetterSpacing
        self.lineBreakMode = style.lineBreakMode
        self.maximumNumberOfLines = style.maximumNumberOfLines
        self.minimumNumberOfLines = style.minimumNumberOfLines
        self.minimumScaleFactor = style.minimumScaleFactor
        self.reservesLineLimitSpace = style.reservesLineLimitSpace
        self.insetsTop = style.insets.top
        self.insetsLeading = style.insets.leading
        self.insetsBottom = style.insets.bottom
        self.insetsTrailing = style.insets.trailing
        self.width = size.width
        self.height = size.height
        self.colorRed = style.color.red
        self.colorGreen = style.color.green
        self.colorBlue = style.color.blue
        self.colorAlpha = style.color.alpha
        self.underline = style.underline
        self.underlinePattern = style.underlinePattern
        self.underlineColorRed = style.underlineColor?.red
        self.underlineColorGreen = style.underlineColor?.green
        self.underlineColorBlue = style.underlineColor?.blue
        self.underlineColorAlpha = style.underlineColor?.alpha
        self.strikethrough = style.strikethrough
        self.strikethroughPattern = style.strikethroughPattern
        self.strikethroughColorRed = style.strikethroughColor?.red
        self.strikethroughColorGreen = style.strikethroughColor?.green
        self.strikethroughColorBlue = style.strikethroughColor?.blue
        self.strikethroughColorAlpha = style.strikethroughColor?.alpha
        self.enableKerning = style.enableKerning
        self.spans = (style.spans ?? []).map { SpanKey(span: $0, in: text) }
    }
}
/// Whole-string rasters, bounded by entry count and by bytes.
///
/// This is the cache in front of every DirectWrite call in the stack that
/// returns a whole laid-out string as a bitmap rather than per-glyph cells:
/// `Controls.icon` (once per icon per view-tree rebuild) and the frame path's
/// `NativeTextRenderer.appendCommands`, which re-rasterized every visible
/// string on every frame it drew.
///
/// It was previously allocated by nothing at all: `RetainedViewRuntime` held
/// an `Optional` that was only ever cleared, so the type existed, was budgeted
/// in `docs/PerformanceBudgets.md`, was gate-tested — and cached nothing.
@MainActor
public final class TextRasterCache {
    /// The process-wide instance every whole-string raster goes through.
    ///
    /// A process global rather than a `RetainedViewRuntime` property, and
    /// deliberately so — AGENTS.md prefers an injectable seam, so the reasons
    /// are stated here rather than assumed:
    ///
    /// 1. **Its callers have no runtime.** `Controls.icon` builds a `ViewNode`
    ///    from a static factory, and `NativeTextRenderer.appendCommands` /
    ///    `DirectWriteTextRenderer.appendCommands` are static entry points
    ///    reached from `ViewNode.appendCommands` — a recursive function with
    ///    almost no stack headroom, which is the last place to thread a new
    ///    parameter through. Reaching a per-runtime cache from any of them
    ///    means a current-runtime global with extra steps.
    /// 2. **There is no per-runtime state to separate.** The key carries every
    ///    input that varies between windows — content, full style, target size
    ///    and device scale — so two runtimes at different DPI ask different
    ///    questions rather than invalidating each other's answers. That is also
    ///    why there is no invalidation hook: nothing about a runtime can go
    ///    stale here.
    /// 3. **The budget is a process budget.** What it bounds is rasterized
    ///    bitmap bytes held live in one process; per-runtime instances would
    ///    multiply the 64 MiB bound by the window count.
    ///
    /// What the global does owe is a seam, which `installForTesting` supplies:
    /// a test substitutes a small instance instead of reaching into shared
    /// state that outlives it.
    private static let processCache = TextRasterCache()
    private(set) static var shared = processCache

    /// Test-only: swap the process-wide cache. Always pair with
    /// `restoreSharedForTesting()` in a `defer`.
    static func installForTesting(_ replacement: TextRasterCache) {
        shared = replacement
    }

    static func restoreSharedForTesting() {
        shared = processCache
    }

    private var entries: [TextRasterCacheKey: CacheEntry] = [:]
    private var accessClock: UInt64 = 0
    private let maxEntryCount: Int
    private let maxMemoryBytes: Int
    private var totalMemoryBytes: Int = 0

    init(maxEntryCount: Int = 256, maxMemoryBytes: Int = 64 * 1024 * 1024) {
        self.maxEntryCount = maxEntryCount
        self.maxMemoryBytes = maxMemoryBytes
    }

    private func nextAccessStamp() -> UInt64 {
        accessClock &+= 1
        return accessClock
    }

    /// Hits served since the last `clear()`. The frame path's whole claim is
    /// that a string it drew last frame does not reach DirectWrite again this
    /// frame, and a hit is the only way that can be true — so the test probe is
    /// a hit count, not a clock.
    private(set) var hitCountForTesting: Int = 0

    func get(for key: TextRasterCacheKey) -> BitmapSurface? {
        guard let index = entries.index(forKey: key) else {
            return nil
        }
        entries.values[index].lastAccessed = nextAccessStamp()
        hitCountForTesting += 1
        return entries.values[index].surface
    }

    func insert(_ surface: BitmapSurface, for key: TextRasterCacheKey) {
        let entryBytes = Int(surface.width) * Int(surface.height) * 4

        if let existing = entries.removeValue(forKey: key) {
            totalMemoryBytes -= existing.memoryBytes
        }

        evictIfNeeded(incomingBytes: entryBytes)

        entries[key] = CacheEntry(
            surface: surface, memoryBytes: entryBytes, lastAccessed: nextAccessStamp())
        totalMemoryBytes += entryBytes
    }

    func clear() {
        entries.removeAll()
        totalMemoryBytes = 0
        hitCountForTesting = 0
    }

    var count: Int {
        entries.count
    }

    var currentMemoryBytes: Int {
        totalMemoryBytes
    }

    /// Evicts least-recently-used entries until both bounds hold with the
    /// incoming entry counted. One stamp scan per eviction, on insert only —
    /// `get` no longer scans at all.
    private func evictIfNeeded(incomingBytes: Int) {
        while !entries.isEmpty
            && (entries.count >= maxEntryCount || totalMemoryBytes + incomingBytes > maxMemoryBytes)
        {
            guard let oldest = entries.min(by: { $0.value.lastAccessed < $1.value.lastAccessed }) else {
                return
            }
            totalMemoryBytes -= oldest.value.memoryBytes
            entries.removeValue(forKey: oldest.key)
        }
    }
}
/// The frame path's whole-string raster, served from `TextRasterCache`.
///
/// The frame path (`RetainedViewRuntime.renderFrame` → `ViewNode.appendCommands`
/// → `NativeTextRenderer.appendCommands`) draws text as one pre-rasterized
/// bitmap per string rather than as glyph quads, and it rebuilt that bitmap
/// through DirectWrite on *every frame it drew* — a full text layout plus a
/// full GDI/DirectWrite raster per visible string per frame, for text whose
/// pixels are a pure function of `(text, style, raster size, scale)`. That
/// tuple is exactly `TextRasterCacheKey`, which is why the cache in front of
/// `Controls.icon` serves this path unchanged.
///
/// Both frame-path renderers go through here so the two cannot drift into
/// caching on different keys; the scene path is untouched, because it draws
/// text from the glyph atlas and never asks for a whole-string bitmap.
@MainActor
enum FramePathTextRaster {
    static func bitmap(
        for text: String,
        size: Size,
        style: PixelTextStyle,
        scaleFactor: Double,
        rasterize: () -> BitmapSurface?
    ) -> BitmapSurface? {
        let key = TextRasterCacheKey(text: text, style: style, size: size, renderScale: scaleFactor)
        if let cached = TextRasterCache.shared.get(for: key) {
            return cached
        }
        guard let bitmap = rasterize() else {
            return nil
        }
        TextRasterCache.shared.insert(bitmap, for: key)
        return bitmap
    }
}
private struct CacheEntry {
    var surface: BitmapSurface
    var memoryBytes: Int
    var lastAccessed: UInt64
}
extension TextWeight: Hashable {}
extension TextFontWidth: Hashable {}
extension TextHorizontalAlignment: Hashable {}
extension TextVerticalAlignment: Hashable {}
extension TextLineBreakMode: Hashable {}
