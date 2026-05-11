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
                advance: bitmap.advance
            )
        }
    }

    static let shared = NativeGlyphAtlas()

    private let atlas = GlyphAtlas(width: 2048, height: 2048)
    private let cache: GlyphAtlasCache
    private var usedInCurrentFrame = false
    private var didRecoverFromExhaustionInCurrentFrame = false

    private init() {
        self.cache = GlyphAtlasCache(atlas: atlas)
    }

    func beginFrame() {
        usedInCurrentFrame = false
        didRecoverFromExhaustionInCurrentFrame = false
        cache.nextFrame()
    }

    var wasUsedInCurrentFrame: Bool {
        usedInCurrentFrame && cache.count > 0
    }

    func snapshotIfUsedInCurrentFrame() -> GlyphAtlasSnapshot? {
        guard wasUsedInCurrentFrame, atlas.isDirty else {
            return nil
        }

        let snapshot = GlyphAtlasSnapshot(
            width: atlas.width,
            height: atlas.height,
            pixels: atlas.pixels,
            dirtyRegion: atlas.dirtyRegion
        )
        atlas.markClean()
        return snapshot
    }

    var size: IntSize {
        IntSize(width: atlas.width, height: atlas.height)
    }

    func consumeRecoveryRequest() -> Bool {
        let didRecover = didRecoverFromExhaustionInCurrentFrame
        didRecoverFromExhaustionInCurrentFrame = false
        return didRecover
    }

    /// Test-only helper for forcing the shared atlas back to a clean empty state.
    func resetForTesting() {
        cache.clear()
        atlas.markClean()
        usedInCurrentFrame = false
        didRecoverFromExhaustionInCurrentFrame = false
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
            weight: style.weight.glyphAtlasWeight
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
                fontFaceID: glyph.fontFace?.identifier,
                fontFamily: fontFamily,
                fontSize: Float(fontSize * scaleFactor),
                weight: weight
            )
        } else {
            key = GlyphKey(
                character: glyph.character,
                fontFamily: fontFamily,
                fontSize: Float(fontSize * scaleFactor),
                weight: weight
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
            advance: bitmap.advance
        )
        if cache.didRecoverFromExhaustionOnLastInsert, entry != nil {
            didRecoverFromExhaustionInCurrentFrame = true
        }
        if entry != nil {
            usedInCurrentFrame = true
        }
        return entry
    }

    private func prepareGlyph(
        key: GlyphKey,
        rasterize: () -> NativeGlyphBitmap?
    ) -> PreparedGlyph? {
        if let cached = cache.peek(key) {
            return PreparedGlyph(key: key, cachedEntry: cached, bitmap: nil)
        }

        guard let bitmap = rasterize() else {
            return nil
        }

        return PreparedGlyph(key: key, cachedEntry: nil, bitmap: bitmap)
    }
}

private extension TextWeight {
    var glyphAtlasWeight: GlyphKey.GlyphWeight {
        switch self {
        case .regular:
            return .regular
        case .semibold:
            return .semibold
        case .bold:
            return .bold
        }
    }
}
