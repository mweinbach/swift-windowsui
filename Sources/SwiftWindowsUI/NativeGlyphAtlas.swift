import SwiftWindowsCore
import SwiftWindowsGraphics

@MainActor
final class NativeGlyphAtlas {
    static let shared = NativeGlyphAtlas()

    private let atlas = GlyphAtlas(width: 2048, height: 2048)
    private let cache: GlyphAtlasCache
    private var usedInCurrentFrame = false

    private init() {
        self.cache = GlyphAtlasCache(atlas: atlas)
    }

    func beginFrame() {
        usedInCurrentFrame = false
        cache.nextFrame()
    }

    func snapshotIfUsedInCurrentFrame() -> GlyphAtlasSnapshot? {
        guard usedInCurrentFrame, cache.count > 0 else {
            return nil
        }

        return GlyphAtlasSnapshot(width: atlas.width, height: atlas.height, pixels: atlas.pixels)
    }

    var size: IntSize {
        IntSize(width: atlas.width, height: atlas.height)
    }

    func glyph(for character: Character, style: PixelTextStyle, scaleFactor: Double) -> GlyphEntry? {
        let key = GlyphKey(
            character: character,
            fontFamily: style.fontFamily,
            fontSize: Float(style.nativeFontPixelSize * scaleFactor),
            weight: style.weight.glyphAtlasWeight
        )

        if let cached = cache.lookup(key) {
            usedInCurrentFrame = true
            return cached
        }

        guard let bitmap = NativeTextRenderer.rasterize(String(character), style: style, scaleFactor: scaleFactor) else {
            return nil
        }

        let entry = cache.insert(
            key: key,
            pixels: bitmap.pixels,
            width: bitmap.width,
            height: bitmap.height,
            bearingX: 0,
            bearingY: 0,
            advance: Float(bitmap.width)
        )

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
