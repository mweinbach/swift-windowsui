import SwiftWindowsGraphics

/// Main-actor accumulator behind `ScenePaintMetrics.textDiagnostics`.
///
/// The text stack reports failure as `nil` from a dozen places that have no
/// scene in scope — a glyph raster that returned nothing, a shaping capture
/// that came back empty, a string pushed onto the 5×7 bitmap font. The painter
/// brackets each pass with `beginPass()` / `snapshot()`, so those counters
/// arrive on the scene without threading an `inout` through the whole layer.
///
/// Counters are advisory: nothing in the pipeline branches on them.
@MainActor
enum TextRenderDiagnosticsCounters {
    private static var current = TextRenderDiagnostics()

    static var pixelFontFallbacks: Int {
        get { current.pixelFontFallbacks }
        set { current.pixelFontFallbacks = newValue }
    }

    static var glyphRasterFailures: Int {
        get { current.glyphRasterFailures }
        set { current.glyphRasterFailures = newValue }
    }

    static var atlasRecoveries: Int {
        get { current.atlasRecoveries }
        set { current.atlasRecoveries = newValue }
    }

    static var shapedGlyphRuns: Int {
        get { current.shapedGlyphRuns }
        set { current.shapedGlyphRuns = newValue }
    }

    static var unshapedGlyphRuns: Int {
        get { current.unshapedGlyphRuns }
        set { current.unshapedGlyphRuns = newValue }
    }

    static var letterSpacingDroppedRasterizations: Int {
        get { current.letterSpacingDroppedRasterizations }
        set { current.letterSpacingDroppedRasterizations = newValue }
    }

    /// Zero the counters at the top of a paint pass. A pass that is retried
    /// after atlas recovery calls this again, so the shipped scene describes
    /// the attempt it actually shipped — except for `atlasRecoveries`, which
    /// the painter carries across attempts because that *is* the retry.
    static func beginPass(preservingAtlasRecoveries: Bool = false) {
        let recoveries = preservingAtlasRecoveries ? current.atlasRecoveries : 0
        current = TextRenderDiagnostics()
        current.atlasRecoveries = recoveries
    }

    static func snapshot() -> TextRenderDiagnostics {
        current
    }

    /// Test-only: full reset, including the recovery count.
    static func resetForTesting() {
        current = TextRenderDiagnostics()
    }
}
