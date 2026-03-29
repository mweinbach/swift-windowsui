import SwiftWindowsCore
import SwiftWindowsGraphics

@MainActor
final class NativeGlyphAtlas {
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

    func glyph(for character: Character, style: PixelTextStyle, scaleFactor: Double) -> GlyphEntry? {
        let key = GlyphKey(
            character: character,
            fontFamily: style.fontFamily,
            fontSize: Float(style.nativeFontPixelSize * scaleFactor),
            weight: style.weight.glyphAtlasWeight
        )

        return lookupOrInsertGlyph(key: key) {
            NativeTextRenderer.rasterizeGlyph(character, style: style, scaleFactor: scaleFactor)
        }
    }

    func glyph(for glyph: NativeTextGlyphLayout, style: PixelTextStyle, scaleFactor: Double) -> GlyphEntry? {
        let fontSize = max(glyph.fontSize, style.nativeFontPixelSize)
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

        return lookupOrInsertGlyph(key: key) {
            NativeTextRenderer.rasterizeGlyph(glyph, style: style, scaleFactor: scaleFactor)
        }
    }

    private func lookupOrInsertGlyph(
        key: GlyphKey,
        rasterize: () -> NativeGlyphBitmap?
    ) -> GlyphEntry? {
        if let cached = cache.lookup(key) {
            usedInCurrentFrame = true
            return cached
        }

        guard let bitmap = rasterize() else {
            return nil
        }

        let entry = cache.insert(
            key: key,
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
