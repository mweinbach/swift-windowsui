import SwiftWindowsCore
import SwiftWindowsGraphics

/// Cache for pre-rasterized text glyphs keyed by content, style, and scale.
/// The runtime holds an optional reference and invalidates it only when the
/// display scale factor changes (see RetainedViewRuntime.displayScale didSet).
@MainActor
public final class TextRasterCache {
    private var entries: [String: CachedTextEntry] = [:]

    public init() {}

    /// Remove all cached entries (e.g. after a scale-factor change).
    public func invalidateAll() {
        entries.removeAll(keepingCapacity: true)
    }

    /// Remove a single entry by key.
    public func invalidate(key: String) {
        entries.removeValue(forKey: key)
    }

    public var count: Int { entries.count }
}

private struct CachedTextEntry {
    let bitmap: BitmapSurface
    let scaleFactor: Double
}
