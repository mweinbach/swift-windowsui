import Foundation
import SwiftWindowsCore

import SwiftWindowsGraphics

@MainActor
final class NativeGlyphAtlas {
    struct PreparedGlyph {
        fileprivate let key: GlyphKey
        fileprivate let cachedEntry: GlyphEntry?
        fileprivate let bitmap: NativeGlyphBitmap?

        var previewEntry: GlyphEntry? {
            if let cachedEntry {
                return cachedEntry
            }
            guard let bitmap else {
                return nil
            }

            return GlyphEntry(
                atlasX: 0,
                atlasY: 0,
                width: bitmap.width,
                height: bitmap.height,
                bearingX: bitmap.bearingX,
                bearingY: bitmap.bearingY,
                advance: bitmap.advance,
                verticalFrame: bitmap.verticalFrame
            )
        }
    }

    private static let processAtlas = NativeGlyphAtlas(atlasWidth: 2048, atlasHeight: 2048)

    /// The process-wide atlas every painter pass draws from. Substitutable so a
    /// test can point the painter at a deliberately small atlas — exhaustion is
    /// otherwise a four-thousand-glyph working set away.
    private(set) static var shared = processAtlas

    private let atlas: GlyphAtlas
    private let cache: GlyphAtlasCache
    private var usedInCurrentFrame = false

    /// While suspended the atlas hands out nothing at all — not even cached
    /// entries — so `ScenePainter` emits no native glyph and text falls through
    /// to the pixel-font path for the whole pass. The painter arms this on its
    /// final attempt: an atlas whose working set does not fit can never produce
    /// a pass whose UVs all survive to present, and bitmap text is strictly
    /// better than text drawn from recycled atlas cells.
    private(set) var isSuspended = false

    init(atlasWidth: Int32, atlasHeight: Int32, maxEntries: Int = 4096) {
        let atlas = GlyphAtlas(width: atlasWidth, height: atlasHeight)
        self.atlas = atlas
        self.cache = GlyphAtlasCache(atlas: atlas, maxEntries: maxEntries)
    }

    /// E6-TEXT. The atlas rung a run drawn at `contentScale` rasterizes on.
    ///
    /// A run under a transform is laid out once, in the view's own space, and
    /// the finished cells are scaled — so the *only* remaining question is at
    /// what pixel size the glyphs are rasterized. Rasterizing at exactly the
    /// effective device size is what keeps a `scaleEffect(2)` label crisp, but
    /// the scale of a live transform is a continuum: a press spring walks
    /// 1.0 → 0.97 → 1.0 across a dozen frames, and one atlas rung per visited
    /// scale would churn the cache every animation, for glyphs no one can tell
    /// apart.
    ///
    /// The rungs are therefore the powers of `2^(1/8)`. Consequences, in the
    /// order they matter:
    ///
    /// - Neighbouring rungs differ by 9%, so a run is resampled by at most
    ///   ±4.4% in linear size — a bilinear stretch of a full-detail raster,
    ///   which is invisible next to the 2x *upscale of a 1x raster* that a
    ///   fixed-size atlas would force.
    /// - `0.97` is within 4.4% of `1`, so every pressed control in the stack
    ///   rasterizes on the rung it already occupies: the press case costs no
    ///   atlas at all.
    /// - The authored scales that matter — `1`, `2`, `4`, `0.5` and the rest
    ///   of the powers of two — land on rungs *exactly*, so they are crisp
    ///   rather than merely close.
    ///
    /// Clamped to `[1/8, 8]`: past that the resample is the lesser evil
    /// against rasterizing a 400px glyph, and the atlas is 2048² total.
    static func glyphRasterScale(for contentScale: Double) -> Double {
        guard contentScale.isFinite, contentScale > 0 else { return 1 }
        let clamped = min(max(contentScale, 0.125), 8)
        let rung = (log2(clamped) * 8).rounded() / 8
        guard rung != 0 else { return 1 }
        return exp2(rung)
    }

    /// Test-only: swap the process-wide atlas. Always pair with
    /// `restoreSharedForTesting()` in a `defer`.
    static func installForTesting(_ replacement: NativeGlyphAtlas) {
        shared = replacement
    }

    static func restoreSharedForTesting() {
        shared = processAtlas
    }

    /// True while the *previous* frame reused reclaimed atlas space, so the
    /// scene it produced is not safe to replay paint records out of.
    ///
    /// Carried across the boundary rather than discovered mid-pass: a reclaim
    /// noticed halfway through a pass costs the whole pass, and once the atlas
    /// is full and the working set keeps moving, that is every frame. Starting
    /// the next frame with replay already off costs one pass instead of two and
    /// makes the mid-pass check unreachable for the reclaim case.
    private(set) var replayIsUnsafeThisFrame = false
    private var reclaimedSinceFrameStart = false

    func beginFrame() {
        usedInCurrentFrame = false
        replayIsUnsafeThisFrame = reclaimedSinceFrameStart
        reclaimedSinceFrameStart = false
        cache.nextFrame()
    }

    /// Starts one paint attempt inside the current frame.
    func beginPass() {
        cache.beginPass()
    }

    /// Records that this frame reused space the allocator had handed out
    /// before, so the next frame must not replay from the scene it ships.
    func noteReclaimedSpaceReused() {
        reclaimedSinceFrameStart = true
    }

    func setSuspended(_ suspended: Bool) {
        isSuspended = suspended
    }

    /// See `GlyphAtlas.generation`. A change across a paint pass means every
    /// rect the pass captured before it is now addressing someone else's pixels.
    var atlasGeneration: UInt64 {
        atlas.generation
    }

    /// See `GlyphAtlas.recycleGeneration` — the shelves-moved half of
    /// `atlasGeneration`, which is the half no pass can survive.
    var atlasRecycleGeneration: UInt64 {
        atlas.recycleGeneration
    }

    /// See `GlyphAtlasCache.didFreeCellUsedThisFrame`. True when this pass gave
    /// back a cell it had already drawn from, which is the only way reusing
    /// reclaimed space can alias a rect the pass itself emitted.
    var didFreeCellUsedThisFrame: Bool {
        cache.didFreeCellUsedThisFrame
    }

    /// LRU clock; advanced once per rendered frame, not once per paint attempt.
    var frameIndex: UInt64 {
        cache.frameIndex
    }

    var wasUsedInCurrentFrame: Bool {
        usedInCurrentFrame && cache.count > 0
    }

    /// Snapshot for a frame that draws from the atlas without having asked it
    /// for a glyph: text replayed out of the previous scene, or a cached scene
    /// shipped without a paint at all.
    ///
    /// `wasUsedInCurrentFrame` is the wrong question for those frames — their
    /// glyph quads address cells allocated on an earlier frame, and the pixels
    /// are still this frame's input. Like `currentSnapshot()` it leaves the
    /// dirty region for the painted frame's single consumer. `nil` only when
    /// the atlas holds no glyph at all, in which case there is nothing the
    /// quads could be addressing.
    func snapshotForCachedGlyphs() -> GlyphAtlasSnapshot? {
        guard cache.count > 0 else {
            return nil
        }

        return GlyphAtlasSnapshot(
            width: atlas.width,
            height: atlas.height,
            pixels: atlas.pixels,
            contentVersion: atlas.contentVersion,
            update: atlas.update
        )
    }

    /// Snapshot of the atlas as it stands right now, leaving the dirty region
    /// intact.
    ///
    /// A frame can have more than one reader: a compositing group rasterizes
    /// its sub-scene on the CPU *during* the traversal, long before the outer
    /// scene is finished. The dirty region, though, has exactly one consumer —
    /// the outer scene, which is what a GPU backend uploads from. If an
    /// intermediate reader called `snapshotIfUsedInCurrentFrame()` it would
    /// mark the atlas clean and the outer scene would ship an empty dirty
    /// region for glyphs that were never uploaded.
    func currentSnapshot() -> GlyphAtlasSnapshot? {
        guard wasUsedInCurrentFrame else {
            return nil
        }

        // Consumers without their own atlas-texture cache (CPU rasterizer,
        // snapshot tools) need to read pixels every frame, even when no new
        // glyphs were uploaded, so the full buffer always ships. What a GPU
        // backend does with it is decided by the version and the update:
        // a static text screen re-emits the same `contentVersion` frame
        // after frame and every texture already holding it skips.
        return GlyphAtlasSnapshot(
            width: atlas.width,
            height: atlas.height,
            pixels: atlas.pixels,
            contentVersion: atlas.contentVersion,
            update: atlas.update
        )
    }

    /// `currentSnapshot()` plus the frame's dirty-region bookkeeping. Called
    /// once per painted frame, by the frame's single owner.
    func snapshotIfUsedInCurrentFrame() -> GlyphAtlasSnapshot? {
        guard let snapshot = currentSnapshot() else {
            return nil
        }
        atlas.markClean()
        return snapshot
    }

    var size: IntSize {
        IntSize(width: atlas.width, height: atlas.height)
    }

    /// How many distinct glyph rasters the atlas is holding. A rung of
    /// `glyphRasterScale` is a distinct raster of the same character, so this
    /// is what a test observes to see which rung a run drew from.
    var cachedGlyphCount: Int {
        cache.count
    }

    /// Test-only helper for forcing the shared atlas back to a clean empty state.
    func resetForTesting() {
        cache.clear()
        atlas.markClean()
        usedInCurrentFrame = false
        isSuspended = false
    }

    func glyph(for character: Character, style: PixelTextStyle, scaleFactor: Double) -> GlyphEntry? {
        guard let preparedGlyph = prepareGlyph(for: character, style: style, scaleFactor: scaleFactor) else {
            return nil
        }
        return commitPreparedGlyph(preparedGlyph)
    }

    func prepareGlyph(for character: Character, style: PixelTextStyle, scaleFactor: Double) -> PreparedGlyph? {
        let key = GlyphKey(
            character: character,
            fontFamily: style.fontFamily,
            fontSize: Float(style.nativeFontPixelSize * scaleFactor),
            weight: style.weight.glyphAtlasWeight,
            fontWidth: style.fontWidth.glyphAtlasWidth,
            isItalic: style.isItalic,
            monospacedDigits: style.monospacedDigits,
            lowercaseSmallCaps: style.lowercaseSmallCaps,
            uppercaseSmallCaps: style.uppercaseSmallCaps
        )

        return prepareGlyph(key: key) {
            NativeTextRenderer.rasterizeGlyph(character, style: style, scaleFactor: scaleFactor)
        }
    }

    func glyph(for glyph: NativeTextGlyphLayout, style: PixelTextStyle, scaleFactor: Double) -> GlyphEntry? {
        guard let preparedGlyph = prepareGlyph(for: glyph, style: style, scaleFactor: scaleFactor) else {
            return nil
        }
        return commitPreparedGlyph(preparedGlyph)
    }

    func prepareGlyph(for glyph: NativeTextGlyphLayout, style: PixelTextStyle, scaleFactor: Double) -> PreparedGlyph? {
        let fontSize = glyph.fontSize.isFinite ? max(glyph.fontSize, 1) : style.nativeFontPixelSize
        let fontFamily = glyph.fontFamily
        let weight = glyph.weight.glyphAtlasWeight
        let key: GlyphKey
        if let glyphID = glyph.glyphID {
            key = GlyphKey(
                character: glyph.character,
                glyphID: glyphID,
                // Registry ID, never the raw COM address: an address is
                // recycled the moment the last handle to a face releases, and
                // the next face at that address would inherit these entries.
                fontFaceID: glyph.fontFaceID?.rawValue,
                fontFamily: fontFamily,
                fontSize: Float(fontSize * scaleFactor),
                weight: weight,
                fontWidth: style.fontWidth.glyphAtlasWidth,
                isItalic: style.isItalic,
                monospacedDigits: style.monospacedDigits,
                lowercaseSmallCaps: style.lowercaseSmallCaps,
                uppercaseSmallCaps: style.uppercaseSmallCaps
            )
        } else {
            key = GlyphKey(
                character: glyph.character,
                fontFamily: fontFamily,
                fontSize: Float(fontSize * scaleFactor),
                weight: weight,
                fontWidth: style.fontWidth.glyphAtlasWidth,
                isItalic: style.isItalic,
                monospacedDigits: style.monospacedDigits,
                lowercaseSmallCaps: style.lowercaseSmallCaps,
                uppercaseSmallCaps: style.uppercaseSmallCaps
            )
        }

        return prepareGlyph(key: key) {
            NativeTextRenderer.rasterizeGlyph(glyph, style: style, scaleFactor: scaleFactor)
        }
    }

    func commitPreparedGlyph(_ preparedGlyph: PreparedGlyph) -> GlyphEntry? {
        if let cached = cache.lookup(preparedGlyph.key) {
            usedInCurrentFrame = true
            return cached
        }

        guard let bitmap = preparedGlyph.bitmap else {
            return nil
        }

        let entry = cache.insert(
            key: preparedGlyph.key,
            pixels: bitmap.surface.pixels,
            width: bitmap.surface.width,
            height: bitmap.surface.height,
            bearingX: bitmap.bearingX,
            bearingY: bitmap.bearingY,
            advance: bitmap.advance,
            verticalFrame: bitmap.verticalFrame
        )
        if entry != nil {
            usedInCurrentFrame = true
        }
        return entry
    }

    private func prepareGlyph(
        key: GlyphKey,
        rasterize: () -> NativeGlyphBitmap?
    ) -> PreparedGlyph? {
        if isSuspended {
            return nil
        }

        if let cached = cache.peek(key) {
            return PreparedGlyph(key: key, cachedEntry: cached, bitmap: nil)
        }

        guard let bitmap = rasterize() else {
            TextRenderDiagnosticsCounters.glyphRasterFailures += 1
            return nil
        }

        return PreparedGlyph(key: key, cachedEntry: nil, bitmap: bitmap)
    }
}
extension TextWeight {
    fileprivate var glyphAtlasWeight: GlyphKey.GlyphWeight {
        switch self {
        case .regular:
            return .regular
        case .medium:
            return .medium
        case .semibold:
            return .semibold
        case .bold:
            return .bold
        }
    }
}
extension TextFontWidth {
    fileprivate var glyphAtlasWidth: GlyphKey.GlyphWidth {
        switch self {
        case .compressed:
            return .compressed
        case .condensed:
            return .condensed
        case .standard:
            return .standard
        case .expanded:
            return .expanded
        }
    }
}
