import Foundation
import SwiftWindowsCore

@MainActor
final class WindowTextSystem {
    private struct LayoutKey: Hashable {
        var text: String
        var fontFamily: String
        var nativeFontSize: Double?
        var weight: TextWeight
        var letterSpacing: Double
        var lineSpacing: Double
        var lineBreakMode: TextLineBreakMode
        var maximumNumberOfLines: Int?
        var insetsTop: Double
        var insetsLeading: Double
        var insetsBottom: Double
        var insetsTrailing: Double
        var underline: Bool
        var strikethrough: Bool
        var enableKerning: Bool
        var maxWidth: Double?
        var spansFingerprint: Int

        init(text: String, style: PixelTextStyle, maxWidth: Double?) {
            self.text = text
            self.fontFamily = style.fontFamily
            self.nativeFontSize = style.nativeFontSize
            self.weight = style.weight
            self.letterSpacing = style.letterSpacing
            self.lineSpacing = style.lineSpacing
            self.lineBreakMode = style.lineBreakMode
            self.maximumNumberOfLines = style.maximumNumberOfLines
            self.insetsTop = style.insets.top
            self.insetsLeading = style.insets.leading
            self.insetsBottom = style.insets.bottom
            self.insetsTrailing = style.insets.trailing
            self.underline = style.underline
            self.strikethrough = style.strikethrough
            self.enableKerning = style.enableKerning
            self.maxWidth = maxWidth
            self.spansFingerprint = Self.makeSpansFingerprint(style.spans, in: text)
        }

        private static func makeSpansFingerprint(_ spans: [TextSpan]?, in text: String) -> Int {
            var hasher = Hasher()
            hasher.combine(spans?.count ?? 0)
            let utf16View = text.utf16

            for span in spans ?? [] {
                hasher.combine(span.text)
                combineLayoutStyle(span.style, into: &hasher)

                if let range = span.range,
                   let utf16Start = range.lowerBound.samePosition(in: utf16View),
                   let utf16End = range.upperBound.samePosition(in: utf16View)
                {
                    hasher.combine(utf16View.distance(from: utf16View.startIndex, to: utf16Start))
                    hasher.combine(utf16View.distance(from: utf16Start, to: utf16End))
                } else {
                    hasher.combine(-1)
                }
            }

            return hasher.finalize()
        }

        private static func combineLayoutStyle(_ style: PixelTextStyle, into hasher: inout Hasher) {
            hasher.combine(style.fontFamily)
            hasher.combine(style.nativeFontSize)
            hasher.combine(style.weight)
            hasher.combine(style.letterSpacing)
            hasher.combine(style.lineSpacing)
            hasher.combine(style.lineBreakMode)
            hasher.combine(style.maximumNumberOfLines)
            hasher.combine(style.insets.top)
            hasher.combine(style.insets.leading)
            hasher.combine(style.insets.bottom)
            hasher.combine(style.insets.trailing)
            hasher.combine(style.underline)
            hasher.combine(style.strikethrough)
            hasher.combine(style.enableKerning)
        }
    }

    private var layouts: [LayoutKey: NativeTextLayoutResult] = [:]
    private var accessOrder: [LayoutKey] = []
    private let maxEntryCount: Int

    init(maxEntryCount: Int = 512) {
        self.maxEntryCount = maxEntryCount
    }

    func layout(_ text: String, style: PixelTextStyle, maxWidth: Double? = nil, scaleFactor: Double) -> NativeTextLayoutResult? {
        let key = LayoutKey(text: text, style: style, maxWidth: maxWidth)
        if let cached = layouts[key] {
            touch(key)
            return snappedLayout(cached, scaleFactor: scaleFactor)
        }

        guard let layout = NativeTextRenderer.layout(text, style: style, scaleFactor: 1.0, maxWidth: maxWidth) else {
            return nil
        }

        insert(layout, for: key)
        return snappedLayout(layout, scaleFactor: scaleFactor)
    }

    func measure(_ text: String, style: PixelTextStyle, maxWidth: Double? = nil, scaleFactor: Double) -> Size? {
        layout(text, style: style, maxWidth: maxWidth, scaleFactor: scaleFactor)?.measuredSize
    }

    func clear() {
        layouts.removeAll()
        accessOrder.removeAll()
    }

    var cachedLayoutCount: Int {
        layouts.count
    }

    private func insert(_ layout: NativeTextLayoutResult, for key: LayoutKey) {
        if layouts[key] != nil {
            touch(key)
            layouts[key] = layout
            return
        }

        if layouts.count >= maxEntryCount, let oldest = accessOrder.first {
            accessOrder.removeFirst()
            layouts.removeValue(forKey: oldest)
        }

        layouts[key] = layout
        accessOrder.append(key)
    }

    private func touch(_ key: LayoutKey) {
        guard let index = accessOrder.firstIndex(of: key) else {
            return
        }

        accessOrder.remove(at: index)
        accessOrder.append(key)
    }

    private func snappedLayout(_ layout: NativeTextLayoutResult, scaleFactor: Double) -> NativeTextLayoutResult {
        guard scaleFactor > 0 else {
            return layout
        }

        var copy = layout
        copy.measuredSize = snapLogicalTextSize(layout.measuredSize, scaleFactor: scaleFactor)
        return copy
    }
}
