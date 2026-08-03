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
    }
}
/// Whole-string rasters, bounded by entry count and by bytes.
///
/// This is the cache in front of `NativeTextRenderer.rasterize` — the one
/// DirectWrite call in the stack that returns a whole laid-out string as a
/// bitmap rather than per-glyph cells. `Controls.icon` is its only caller, and
/// it runs once per icon per view-tree rebuild, so a screen of symbol icons
/// re-rasterized every icon on every state change before this was wired up.
///
/// It was previously allocated by nothing at all: `RetainedViewRuntime` held
/// an `Optional` that was only ever cleared, so the type existed, was budgeted
/// in `docs/PerformanceBudgets.md`, was gate-tested — and cached nothing.
@MainActor
public final class TextRasterCache {
    /// The process-wide instance `Controls.icon` rasterizes through. Icon
    /// rasters are keyed by content, style and device scale, so one instance
    /// serves every window without a cross-window invalidation story.
    static let shared = TextRasterCache()

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

    func get(for key: TextRasterCacheKey) -> BitmapSurface? {
        guard let index = entries.index(forKey: key) else {
            return nil
        }
        entries.values[index].lastAccessed = nextAccessStamp()
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
