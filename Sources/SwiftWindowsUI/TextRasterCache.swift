import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics

struct TextRasterCacheKey: Hashable, Sendable {
    var text: String
    var fontFamily: String
    var scale: Double
    var nativeFontSize: Double?
    var weight: TextWeight
    var alignment: TextHorizontalAlignment
    var verticalAlignment: TextVerticalAlignment
    var lineSpacing: Double
    var letterSpacing: Double
    var lineBreakMode: TextLineBreakMode
    var maximumNumberOfLines: Int?
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
    var italic: Bool
    var underline: Bool
    var strikethrough: Bool
    var enableKerning: Bool
    var displayScale: Double

    init(text: String, style: PixelTextStyle, size: Size, displayScale: Double) {
        self.text = text
        self.fontFamily = style.fontFamily
        self.scale = style.scale
        self.nativeFontSize = style.nativeFontSize
        self.weight = style.weight
        self.alignment = style.alignment
        self.verticalAlignment = style.verticalAlignment
        self.lineSpacing = style.lineSpacing
        self.letterSpacing = style.letterSpacing
        self.lineBreakMode = style.lineBreakMode
        self.maximumNumberOfLines = style.maximumNumberOfLines
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
        self.italic = style.italic
        self.underline = style.underline
        self.strikethrough = style.strikethrough
        self.enableKerning = style.enableKerning
        self.displayScale = displayScale
    }
}

struct TextMeasurementCacheKey: Hashable, Sendable {
    var text: String
    var fontFamily: String
    var scale: Double
    var weight: TextWeight
    var alignment: TextHorizontalAlignment
    var verticalAlignment: TextVerticalAlignment
    var lineSpacing: Double
    var letterSpacing: Double
    var lineBreakMode: TextLineBreakMode
    var maximumNumberOfLines: Int?
    var insetsTop: Double
    var insetsLeading: Double
    var insetsBottom: Double
    var insetsTrailing: Double
    var maxWidth: Double?
    var displayScale: Double
    var italic: Bool
    var underline: Bool
    var strikethrough: Bool
    var enableKerning: Bool

    init(text: String, style: PixelTextStyle, maxWidth: Double?, displayScale: Double) {
        self.text = text
        self.fontFamily = style.fontFamily
        self.scale = style.scale
        self.weight = style.weight
        self.alignment = style.alignment
        self.verticalAlignment = style.verticalAlignment
        self.lineSpacing = style.lineSpacing
        self.letterSpacing = style.letterSpacing
        self.lineBreakMode = style.lineBreakMode
        self.maximumNumberOfLines = style.maximumNumberOfLines
        self.insetsTop = style.insets.top
        self.insetsLeading = style.insets.leading
        self.insetsBottom = style.insets.bottom
        self.insetsTrailing = style.insets.trailing
        self.maxWidth = maxWidth
        self.displayScale = displayScale
        self.italic = style.italic
        self.underline = style.underline
        self.strikethrough = style.strikethrough
        self.enableKerning = style.enableKerning
    }
}

@MainActor
public final class TextRasterCache {
    private var entries: [TextRasterCacheKey: CacheEntry] = [:]
    private var accessOrder: [TextRasterCacheKey] = []
    private var measurements: [TextMeasurementCacheKey: Size] = [:]
    private var measurementAccessOrder: [TextMeasurementCacheKey] = []
    private let maxEntryCount: Int
    private let maxMemoryBytes: Int
    private let maxMeasurementCount: Int
    private var totalMemoryBytes: Int = 0

    public init(
        maxEntryCount: Int = 256,
        maxMemoryBytes: Int = 64 * 1024 * 1024,
        maxMeasurementCount: Int = 2048
    ) {
        self.maxEntryCount = maxEntryCount
        self.maxMemoryBytes = maxMemoryBytes
        self.maxMeasurementCount = maxMeasurementCount
    }

    func get(for key: TextRasterCacheKey) -> BitmapSurface? {
        guard let entry = entries[key] else {
            return nil
        }

        if let index = accessOrder.firstIndex(of: key) {
            accessOrder.remove(at: index)
            accessOrder.append(key)
        }

        return entry.surface
    }

    func insert(_ surface: BitmapSurface, for key: TextRasterCacheKey) {
        let entryBytes = Int(surface.width) * Int(surface.height) * 4

        if let existing = entries[key] {
            totalMemoryBytes -= existing.memoryBytes
            if let index = accessOrder.firstIndex(of: key) {
                accessOrder.remove(at: index)
            }
        }

        evictIfNeeded(incomingBytes: entryBytes)

        entries[key] = CacheEntry(surface: surface, memoryBytes: entryBytes)
        accessOrder.append(key)
        totalMemoryBytes += entryBytes
    }

    func measurement(for key: TextMeasurementCacheKey) -> Size? {
        guard let size = measurements[key] else {
            return nil
        }

        if let index = measurementAccessOrder.firstIndex(of: key) {
            measurementAccessOrder.remove(at: index)
            measurementAccessOrder.append(key)
        }

        return size
    }

    func insertMeasurement(_ size: Size, for key: TextMeasurementCacheKey) {
        if measurements[key] != nil, let index = measurementAccessOrder.firstIndex(of: key) {
            measurementAccessOrder.remove(at: index)
        }

        measurements[key] = size
        measurementAccessOrder.append(key)
        evictMeasurementsIfNeeded()
    }

    func clear() {
        entries.removeAll()
        accessOrder.removeAll()
        measurements.removeAll()
        measurementAccessOrder.removeAll()
        totalMemoryBytes = 0
    }

    public var count: Int {
        entries.count
    }

    public var currentMemoryBytes: Int {
        totalMemoryBytes
    }

    public var measurementCount: Int {
        measurements.count
    }

    private func evictIfNeeded(incomingBytes: Int) {
        while !accessOrder.isEmpty && (entries.count >= maxEntryCount || totalMemoryBytes + incomingBytes > maxMemoryBytes) {
            let oldestKey = accessOrder.removeFirst()
            if let entry = entries.removeValue(forKey: oldestKey) {
                totalMemoryBytes -= entry.memoryBytes
            }
        }
    }

    private func evictMeasurementsIfNeeded() {
        while measurementAccessOrder.count > maxMeasurementCount {
            let oldestKey = measurementAccessOrder.removeFirst()
            measurements.removeValue(forKey: oldestKey)
        }
    }
}

private struct CacheEntry {
    var surface: BitmapSurface
    var memoryBytes: Int
}

extension TextWeight: Hashable {}
extension TextHorizontalAlignment: Hashable {}
extension TextVerticalAlignment: Hashable {}
extension TextLineBreakMode: Hashable {}
