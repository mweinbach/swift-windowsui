import Foundation

import SwiftWindowsCore

@MainActor
final class WindowTextSystem {
    struct LayoutStyleKey: Hashable {
        var fontFamily: String
        var resolvedNativeFontSize: Double
        var weight: TextWeight
        var fontWidth: TextFontWidth
        var isItalic: Bool
        var monospacedDigits: Bool
        var lowercaseSmallCaps: Bool
        var uppercaseSmallCaps: Bool
        var letterSpacing: Double
        var nativeLetterSpacing: Double?
        var lineSpacing: Double
        var lineBreakMode: TextLineBreakMode
        var maximumNumberOfLines: Int?
        var minimumNumberOfLines: Int?
        var minimumScaleFactor: Double
        var reservesLineLimitSpace: Bool
        var insetsTop: Double
        var insetsLeading: Double
        var insetsBottom: Double
        var insetsTrailing: Double
        var underline: Bool
        var underlinePattern: TextDecorationPattern
        var strikethrough: Bool
        var strikethroughPattern: TextDecorationPattern
        var enableKerning: Bool

        init(style: PixelTextStyle) {
            self.fontFamily = style.fontFamily
            self.resolvedNativeFontSize = style.nativeFontPixelSize
            self.weight = style.weight
            self.fontWidth = style.fontWidth
            self.isItalic = style.isItalic
            self.monospacedDigits = style.monospacedDigits
            self.lowercaseSmallCaps = style.lowercaseSmallCaps
            self.uppercaseSmallCaps = style.uppercaseSmallCaps
            self.letterSpacing = style.letterSpacing
            self.nativeLetterSpacing = style.nativeLetterSpacing
            self.lineSpacing = style.lineSpacing
            self.lineBreakMode = style.lineBreakMode
            self.maximumNumberOfLines = style.maximumNumberOfLines
            self.minimumNumberOfLines = style.minimumNumberOfLines
            self.minimumScaleFactor = style.minimumScaleFactor
            self.reservesLineLimitSpace = style.reservesLineLimitSpace
            self.insetsTop = style.insets.top
            self.insetsLeading = style.insets.leading
            self.insetsBottom = style.insets.bottom
            self.insetsTrailing = style.insets.trailing
            self.underline = style.underline
            self.underlinePattern = style.underlinePattern
            self.strikethrough = style.strikethrough
            self.strikethroughPattern = style.strikethroughPattern
            self.enableKerning = style.enableKerning
        }
    }

    struct LayoutSpanKey: Hashable {
        var text: String
        var style: LayoutStyleKey
        var utf16RangeStart: Int?
        var utf16RangeLength: Int?

        init(span: TextSpan, in fullText: String) {
            self.text = span.text
            self.style = LayoutStyleKey(style: span.style)

            let range = Self.utf16Range(for: span.range, in: fullText)
            self.utf16RangeStart = range?.start
            self.utf16RangeLength = range?.length
        }

        private static func utf16Range(
            for range: Range<String.Index>?,
            in text: String
        ) -> (start: Int, length: Int)? {
            guard let range else {
                return nil
            }

            let utf16View = text.utf16
            guard let utf16Start = range.lowerBound.samePosition(in: utf16View),
                let utf16End = range.upperBound.samePosition(in: utf16View)
            else {
                return nil
            }

            let start = utf16View.distance(from: utf16View.startIndex, to: utf16Start)
            let length = utf16View.distance(from: utf16Start, to: utf16End)
            return (start, length)
        }
    }

    struct LayoutKey: Hashable {
        var text: String
        var style: LayoutStyleKey
        var maxWidth: Double?
        var spans: [LayoutSpanKey]

        init(text: String, style: PixelTextStyle, maxWidth: Double?) {
            self.text = text
            self.style = LayoutStyleKey(style: style)
            self.maxWidth = maxWidth
            self.spans = (style.spans ?? []).map { LayoutSpanKey(span: $0, in: text) }
        }
    }

    private var layouts: [LayoutKey: NativeTextLayoutResult] = [:]
    private var accessOrder: [LayoutKey] = []
    private let maxEntryCount: Int

    init(maxEntryCount: Int = 512) {
        self.maxEntryCount = maxEntryCount
    }

    func layout(_ text: String, style: PixelTextStyle, maxWidth: Double? = nil, scaleFactor: Double)
        -> NativeTextLayoutResult?
    {
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
