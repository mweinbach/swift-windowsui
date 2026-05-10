import Foundation
import Testing
@testable import SwiftWindowsCore
@testable import SwiftWindowsGraphics
@testable import SwiftWindowsUI

@MainActor
@Suite("ScenePainter")
struct ScenePainterTests {

    private let surfaceSize = Size(width: 800, height: 600)

    // MARK: - Basic quad emission

    @Test("Single node with backgroundColor produces 1 quad")
    func singleNodeWithBackground() {
        let node = ViewNode(
            frame: Rect(x: 10, y: 20, width: 100, height: 50),
            backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1)
        )

        let scene = ScenePainter.paint(root: node, clearColor: .black, surfaceSize: surfaceSize)

        #expect(scene.layers.count == 1)
        #expect(scene.layers[0].quads.count == 1)
        #expect(scene.layers[0].shadows.isEmpty)

        let quad = scene.layers[0].quads[0]
        #expect(quad.x == 10)
        #expect(quad.y == 20)
        #expect(quad.width == 100)
        #expect(quad.height == 50)
        #expect(quad.startR == 1)
        #expect(quad.startG == 0)
        #expect(quad.startA == 1)
    }

    // MARK: - Shadow + quad

    @Test("Node with shadow produces 1 shadow and 1 quad")
    func nodeWithShadow() {
        let node = ViewNode(
            frame: Rect(x: 0, y: 0, width: 200, height: 100),
            backgroundColor: Color(red: 0, green: 0, blue: 1, alpha: 1),
            shadowColor: Color(red: 0, green: 0, blue: 0, alpha: 0.5),
            shadowOffset: Point(x: 2, y: 4),
            shadowSpread: 3
        )

        let scene = ScenePainter.paint(root: node, clearColor: .black, surfaceSize: surfaceSize)

        #expect(scene.layers[0].shadows.count == 1)
        #expect(scene.layers[0].quads.count == 1)

        let shadow = scene.layers[0].shadows[0]
        #expect(shadow.colorA == 0.5)
        #expect(shadow.offsetX == 2)
        #expect(shadow.offsetY == 4)
    }

    @Test("Parent clip becomes the shadow content mask")
    func clippedParentMasksChildShadow() {
        let parent = ViewNode(
            frame: Rect(x: 50, y: 50, width: 120, height: 120),
            clipsToBounds: true
        )
        let child = ViewNode(
            frame: Rect(x: 80, y: 80, width: 40, height: 40),
            shadowColor: Color(red: 0, green: 0, blue: 0, alpha: 0.6),
            shadowOffset: Point(x: 6, y: 6),
            shadowSpread: 12
        )
        parent.addChild(child)

        let scene = ScenePainter.paint(root: parent, clearColor: .black, surfaceSize: surfaceSize)

        #expect(scene.layers[0].shadows.count == 1)
        let shadowMask = scene.layers[0].shadows[0].contentMask.bounds
        #expect(shadowMask == Rect(x: 50, y: 50, width: 120, height: 120))
    }

    // MARK: - Parent with colored children

    @Test("Parent with 3 colored children produces 4 quads")
    func parentWithColoredChildren() {
        let parent = ViewNode(
            frame: Rect(x: 0, y: 0, width: 400, height: 300),
            backgroundColor: Color(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        )

        for i in 0..<3 {
            let child = ViewNode(
                frame: Rect(x: Double(i * 110), y: 10, width: 100, height: 50),
                backgroundColor: Color(red: Float(i) * 0.3, green: 0, blue: 0, alpha: 1)
            )
            parent.addChild(child)
        }

        let scene = ScenePainter.paint(root: parent, clearColor: .black, surfaceSize: surfaceSize)

        let totalQuads = scene.layers.reduce(0) { $0 + $1.quads.count }
        #expect(totalQuads == 4) // parent + 3 children
    }

    // MARK: - Z-index layering

    @Test("Children with different zIndex values stay in one layer and sort by z order")
    func differentZIndexProducesLayers() {
        let parent = ViewNode(
            frame: Rect(x: 0, y: 0, width: 400, height: 300)
        )

        let childA = ViewNode(
            frame: Rect(x: 0, y: 0, width: 100, height: 100),
            backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1),
            zIndex: 0
        )
        let childB = ViewNode(
            frame: Rect(x: 50, y: 50, width: 100, height: 100),
            backgroundColor: Color(red: 0, green: 1, blue: 0, alpha: 1),
            zIndex: 1
        )
        let childC = ViewNode(
            frame: Rect(x: 100, y: 100, width: 100, height: 100),
            backgroundColor: Color(red: 0, green: 0, blue: 1, alpha: 1),
            zIndex: 2
        )

        parent.addChild(childA)
        parent.addChild(childB)
        parent.addChild(childC)

        let scene = ScenePainter.paint(root: parent, clearColor: .black, surfaceSize: surfaceSize)

        #expect(scene.layers.count == 1)
        #expect(scene.layers[0].quads.count == 3)
        #expect(scene.layers[0].quads[0].startR == 1)
        #expect(scene.layers[0].quads[1].startG == 1)
        #expect(scene.layers[0].quads[2].startB == 1)
    }

    @Test("Promoted overlapping descendants still sort ahead of later same-z siblings")
    func sameZSiblingReusesPriorSubtreeTopLayer() {
        let firstChild = ViewNode(
            frame: Rect(x: 0, y: 0, width: 100, height: 100),
            backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1)
        )
        let promotedGrandchild = ViewNode(
            frame: Rect(x: 12, y: 12, width: 40, height: 40),
            backgroundColor: Color(red: 0, green: 1, blue: 0, alpha: 1),
            zIndex: 1
        )
        firstChild.addChild(promotedGrandchild)

        let secondChild = ViewNode(
            frame: Rect(x: 20, y: 20, width: 100, height: 100),
            backgroundColor: Color(red: 0, green: 0, blue: 1, alpha: 1)
        )

        let parent = ViewNode(
            frame: Rect(x: 0, y: 0, width: 180, height: 160),
            children: [firstChild, secondChild]
        )

        let scene = ScenePainter.paint(root: parent, clearColor: .black, surfaceSize: surfaceSize)

        #expect(scene.layers.count == 1)
        #expect(scene.layers[0].quads.count == 3)
        #expect(scene.layers[0].quads[0].startR == 1)
        #expect(scene.layers[0].quads[1].startG == 1)
        #expect(scene.layers[0].quads[2].startB == 1)
    }

    // MARK: - Hidden node

    @Test("Hidden node produces no primitives")
    func hiddenNodeProducesNothing() {
        let node = ViewNode(
            frame: Rect(x: 0, y: 0, width: 100, height: 100),
            backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1),
            isHidden: true
        )

        let scene = ScenePainter.paint(root: node, clearColor: .black, surfaceSize: surfaceSize)

        #expect(scene.totalPrimitiveCount == 0)
    }

    // MARK: - Clips to bounds

    @Test("Node with clipsToBounds sets clip bounds on child quads")
    func clipsToBoundsAffectsChildren() {
        let parent = ViewNode(
            frame: Rect(x: 50, y: 50, width: 200, height: 200),
            backgroundColor: Color(red: 0.2, green: 0.2, blue: 0.2, alpha: 1),
            clipsToBounds: true
        )

        // Child extends beyond parent bounds.
        let child = ViewNode(
            frame: Rect(x: 100, y: 100, width: 200, height: 200),
            backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1)
        )
        parent.addChild(child)

        let scene = ScenePainter.paint(root: parent, clearColor: .black, surfaceSize: surfaceSize)

        let totalQuads = scene.layers.reduce(0) { $0 + $1.quads.count }
        #expect(totalQuads == 2) // parent + child

        // The child quad's clip should be constrained to the intersection of
        // the parent frame and the surface clip (i.e., the parent frame).
        let childQuad = scene.layers[0].quads[1]
        #expect(childQuad.clipX == 50)
        #expect(childQuad.clipY == 50)
        #expect(childQuad.clipWidth == 200)
        #expect(childQuad.clipHeight == 200)
    }

    // MARK: - Empty node

    @Test("Node with no background or children produces no primitives")
    func emptyNodeProducesNothing() {
        let node = ViewNode(
            frame: Rect(x: 0, y: 0, width: 100, height: 100)
        )

        let scene = ScenePainter.paint(root: node, clearColor: .black, surfaceSize: surfaceSize)

        #expect(scene.totalPrimitiveCount == 0)
    }

    // MARK: - Zero opacity

    @Test("Node with zero opacity produces no primitives")
    func zeroOpacityProducesNothing() {
        let node = ViewNode(
            frame: Rect(x: 0, y: 0, width: 100, height: 100),
            backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1),
            opacity: 0
        )

        let scene = ScenePainter.paint(root: node, clearColor: .black, surfaceSize: surfaceSize)

        #expect(scene.totalPrimitiveCount == 0)
    }

    // MARK: - Border

    @Test("Node with border produces border quad and fill quad")
    func nodeWithBorderProducesTwoQuads() {
        let node = ViewNode(
            frame: Rect(x: 0, y: 0, width: 100, height: 100),
            backgroundColor: Color(red: 1, green: 1, blue: 1, alpha: 1),
            borderColor: Color(red: 0, green: 0, blue: 0, alpha: 1),
            borderWidth: 2
        )

        let scene = ScenePainter.paint(root: node, clearColor: .black, surfaceSize: surfaceSize)

        // border quad + fill quad
        #expect(scene.layers[0].quads.count == 2)

        // Fill quad should be inset by the border width.
        let fillQuad = scene.layers[0].quads[1]
        #expect(fillQuad.x == 2)
        #expect(fillQuad.y == 2)
        #expect(fillQuad.width == 96)
        #expect(fillQuad.height == 96)
    }

    // MARK: - Opacity multiplied into alpha

    @Test("Opacity is multiplied into quad alpha")
    func opacityMultipliedIntoAlpha() {
        let node = ViewNode(
            frame: Rect(x: 0, y: 0, width: 100, height: 100),
            backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1),
            opacity: 0.5
        )

        let scene = ScenePainter.paint(root: node, clearColor: .black, surfaceSize: surfaceSize)

        #expect(scene.layers[0].quads.count == 1)
        let quad = scene.layers[0].quads[0]
        #expect(quad.startA == 0.5)
        #expect(quad.endA == 0.5)
    }

    @Test("Parent opacity cascades into child primitives")
    func parentOpacityCascadesIntoChildPrimitives() {
        let child = ViewNode(
            frame: Rect(x: 10, y: 10, width: 80, height: 80),
            backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1),
            opacity: 0.4
        )
        let parent = ViewNode(
            frame: Rect(x: 0, y: 0, width: 100, height: 100),
            opacity: 0.5,
            children: [child]
        )

        let scene = ScenePainter.paint(root: parent, clearColor: .black, surfaceSize: surfaceSize)

        #expect(scene.layers[0].quads.count == 1)
        let quad = scene.layers[0].quads[0]
        #expect(quad.startA == 0.2)
        #expect(quad.endA == 0.2)
    }

    // MARK: - Text

    @Test("Text nodes emit typed glyph primitives and atlas data")
    func textNodeProducesGlyphs() {
        let node = ViewNode(
            frame: Rect(x: 10, y: 20, width: 140, height: 40),
            text: "HI",
            textStyle: PixelTextStyle(color: .white, alignment: .leading, verticalAlignment: .top)
        )

        let scene = ScenePainter.paint(root: node, clearColor: .black, surfaceSize: surfaceSize)
        let totalGlyphCount = scene.layers[0].glyphs.count + scene.layers[0].pixelGlyphs.count
        let firstGlyph = scene.layers[0].glyphs.first ?? scene.layers[0].pixelGlyphs.first

        #expect(scene.layers.count == 1)
        #expect(totalGlyphCount == 2)
        #expect(scene.glyphAtlas != nil || scene.pixelGlyphAtlas != nil)
        #expect(firstGlyph != nil)
        if let firstGlyph {
            #expect(firstGlyph.screenX >= 10)
            #expect(firstGlyph.screenY >= 20)
        }
    }

    @Test("Symbol icons resolve to dedicated atlas glyphs")
    func symbolIconsUseDedicatedAtlasEntries() {
        let symbol = Character(SymbolIcon.search.rawValue)
        let fallback = PixelFontAtlas.glyph(for: "?")
        let symbolGlyph = PixelFontAtlas.glyph(for: symbol)
        let node = ViewNode(
            frame: Rect(x: 10, y: 20, width: 40, height: 40),
            text: SymbolIcon.search.rawValue,
            textStyle: PixelTextStyle(color: .white, alignment: .leading, verticalAlignment: .top)
        )

        let scene = ScenePainter.paint(root: node, clearColor: .black, surfaceSize: surfaceSize)
        let atlas = PixelFontAtlas.shared.surface
        let uv = symbolGlyph.uvRect(atlasWidth: atlas.width, atlasHeight: atlas.height)

        #expect(PixelFontAtlas.supports(symbol))
        #expect(symbolGlyph != fallback)
        #expect(scene.layers[0].pixelGlyphs.count == 1)
        #expect(scene.pixelGlyphAtlas != nil)
        #expect(scene.layers[0].pixelGlyphs[0].atlasU0 == uv.u0)
        #expect(scene.layers[0].pixelGlyphs[0].atlasV0 == uv.v0)
    }

    @Test("Mixed native text and icon glyphs keep separate atlases when native text is available")
    func mixedTextAndIconGlyphsUseSeparateAtlases() {
        let textNode = ViewNode(
            frame: Rect(x: 10, y: 20, width: 120, height: 32),
            text: "HELLO",
            textStyle: PixelTextStyle(color: .white, alignment: .leading, verticalAlignment: .top, nativeFontSize: 18)
        )
        let iconNode = ViewNode(
            frame: Rect(x: 10, y: 60, width: 32, height: 32),
            text: SymbolIcon.search.rawValue,
            textStyle: PixelTextStyle(color: .white, alignment: .leading, verticalAlignment: .top)
        )
        let root = ViewNode(
            frame: Rect(x: 0, y: 0, width: 180, height: 120),
            children: [textNode, iconNode]
        )

        let scene = ScenePainter.paint(root: root, clearColor: .black, surfaceSize: surfaceSize)

        #expect(scene.pixelGlyphAtlas != nil)
        if scene.layers[0].glyphs.isEmpty {
            #expect(scene.layers[0].pixelGlyphs.count >= 6)
            #expect(scene.glyphAtlas == nil)
        } else {
            #expect(scene.layers[0].pixelGlyphs.count == 1)
            #expect(scene.glyphAtlas != nil || NativeGlyphAtlas.shared.wasUsedInCurrentFrame)
        }
    }

    @Test("Private-use symbols stay on the pixel atlas path in mixed-content text - VAL-TEXT-008")
    func mixedContentPrivateUseSymbolsStayOnPixelPath() {
        let symbol = Character(SymbolIcon.search.rawValue)
        let node = ViewNode(
            frame: Rect(x: 10, y: 20, width: 180, height: 40),
            text: "A\(SymbolIcon.search.rawValue)B",
            textStyle: PixelTextStyle(color: .white, alignment: .leading, verticalAlignment: .top)
        )

        let scene = ScenePainter.paint(root: node, clearColor: .black, surfaceSize: surfaceSize)
        let atlas = PixelFontAtlas.shared.surface
        let uv = PixelFontAtlas.glyph(for: symbol).uvRect(atlasWidth: atlas.width, atlasHeight: atlas.height)

        #expect(scene.pixelGlyphAtlas != nil)
        #expect(scene.layers[0].glyphs.count + scene.layers[0].pixelGlyphs.count >= 3)
        #expect(scene.layers[0].pixelGlyphs.contains(where: {
            $0.atlasU0 == uv.u0 && $0.atlasV0 == uv.v0 && $0.atlasU1 == uv.u1 && $0.atlasV1 == uv.v1
        }))
    }

    @Test("Native text layout failure falls back to pixel glyphs without dropping scene text - VAL-TEXT-009")
    func nativeTextLayoutFailureFallsBackToPixelGlyphs() {
        defer { NativeTextRenderer.resetTestingOverrides() }
        NativeTextRenderer.testingOverrides.layout = { _, _, _, _ in nil }

        let node = ViewNode(
            frame: Rect(x: 10, y: 20, width: 160, height: 40),
            text: "Fallback",
            textStyle: PixelTextStyle(color: .white, alignment: .leading, verticalAlignment: .top, nativeFontSize: 18)
        )

        let scene = ScenePainter.paint(root: node, clearColor: .black, surfaceSize: surfaceSize)

        #expect(scene.layers[0].glyphs.isEmpty)
        #expect(scene.layers[0].pixelGlyphs.count > 0)
        #expect(scene.glyphAtlas == nil)
        #expect(scene.pixelGlyphAtlas != nil)
    }

    @Test("Effective clipping suppresses fully off-clip text and leaves the pass atlas-silent - VAL-TEXT-010")
    func fullyClippedTextEmitsNothingAndStaysAtlasSilent() {
        let textNode = ViewNode(
            frame: Rect(x: 0, y: 0, width: 160, height: 32),
            text: SymbolIcon.search.rawValue,
            textStyle: PixelTextStyle(color: .white, alignment: .trailing, verticalAlignment: .top)
        )
        let root = ViewNode(
            frame: Rect(x: 0, y: 0, width: 20, height: 32),
            clipsToBounds: true,
            children: [textNode]
        )

        let scene = ScenePainter.paint(root: root, clearColor: .black, surfaceSize: surfaceSize)

        expectAtlasSilent(scene)
    }

    @Test("Fully clipped native text, including padding-only clip intersections, does not dirty or attach the native atlas - VAL-TEXT-010")
    func fullyClippedNativeTextStaysAtlasSilent() {
        defer {
            NativeTextRenderer.resetTestingOverrides()
            NativeGlyphAtlas.shared.resetForTesting()
        }
        NativeGlyphAtlas.shared.resetForTesting()
        NativeTextRenderer.testingOverrides.layout = { text, style, _, _ in
            syntheticNativeLayout(for: text, style: style)
        }
        NativeTextRenderer.testingOverrides.rasterizeGlyphForLayout = { _, _, _ in
            stubNativeGlyphBitmap()
        }

        let fullyClippedTextNode = ViewNode(
            frame: Rect(x: 0, y: 0, width: 160, height: 32),
            text: "CLIPPED",
            textStyle: PixelTextStyle(color: .white, alignment: .trailing, verticalAlignment: .top, nativeFontSize: 18)
        )
        let fullyClippedRoot = ViewNode(
            frame: Rect(x: 0, y: 0, width: 20, height: 32),
            clipsToBounds: true,
            children: [fullyClippedTextNode]
        )

        let fullyClippedScene = ScenePainter.paint(root: fullyClippedRoot, clearColor: .black, surfaceSize: surfaceSize)

        expectAtlasSilent(fullyClippedScene)
        #expect(NativeGlyphAtlas.shared.wasUsedInCurrentFrame == false)

        NativeGlyphAtlas.shared.resetForTesting()

        let paddingOnlyIntersectionTextNode = ViewNode(
            frame: Rect(x: 21, y: 0, width: 40, height: 32),
            text: "A",
            textStyle: PixelTextStyle(color: .white, alignment: .leading, verticalAlignment: .top, nativeFontSize: 18)
        )
        let paddingOnlyIntersectionRoot = ViewNode(
            frame: Rect(x: 0, y: 0, width: 20, height: 32),
            clipsToBounds: true,
            children: [paddingOnlyIntersectionTextNode]
        )

        let paddingOnlyIntersectionScene = ScenePainter.paint(
            root: paddingOnlyIntersectionRoot,
            clearColor: .black,
            surfaceSize: surfaceSize
        )

        expectAtlasSilent(paddingOnlyIntersectionScene)
        #expect(NativeGlyphAtlas.shared.wasUsedInCurrentFrame == false)
    }

    @Test("Native glyphs without source character mapping still reach the native atlas - VAL-TEXT-010")
    func nativeGlyphsWithoutSourceMappingStillRender() {
        defer {
            NativeTextRenderer.resetTestingOverrides()
            NativeGlyphAtlas.shared.resetForTesting()
        }
        NativeGlyphAtlas.shared.resetForTesting()
        NativeTextRenderer.testingOverrides.layout = { _, style, _, _ in
            NativeTextLayoutResult(
                lines: [
                    NativeTextLineLayout(
                        text: "AB",
                        width: 18,
                        height: style.nativeFontPixelSize,
                        glyphs: [
                            NativeTextGlyphLayout(
                                character: " ",
                                origin: Point(x: 0, y: 0),
                                advance: 9,
                                glyphID: 41,
                                fontFamily: style.fontFamily,
                                weight: style.weight,
                                fontSize: style.nativeFontPixelSize,
                                sourceIndex: nil
                            ),
                            NativeTextGlyphLayout(
                                character: " ",
                                origin: Point(x: 9, y: 0),
                                advance: 9,
                                glyphID: 42,
                                fontFamily: style.fontFamily,
                                weight: style.weight,
                                fontSize: style.nativeFontPixelSize,
                                sourceIndex: nil
                            )
                        ]
                    )
                ],
                contentSize: Size(width: 18, height: style.nativeFontPixelSize),
                measuredSize: Size(width: 18, height: style.nativeFontPixelSize)
            )
        }
        NativeTextRenderer.testingOverrides.rasterizeGlyphForLayout = { _, _, _ in
            stubNativeGlyphBitmap()
        }

        let node = ViewNode(
            frame: Rect(x: 10, y: 20, width: 80, height: 32),
            text: "AB",
            textStyle: PixelTextStyle(color: .white, alignment: .leading, verticalAlignment: .top, nativeFontSize: 18)
        )

        let scene = ScenePainter.paint(root: node, clearColor: .black, surfaceSize: surfaceSize)

        #expect(scene.layers[0].glyphs.count == 2)
        #expect(scene.layers[0].pixelGlyphs.isEmpty)
    }

    @Test("Visible clipped text carries the active clip metadata - VAL-TEXT-010")
    func visibleClippedTextCarriesEffectiveClipMetadata() {
        let textNode = ViewNode(
            frame: Rect(x: 0, y: 0, width: 160, height: 32),
            text: SymbolIcon.search.rawValue,
            textStyle: PixelTextStyle(color: .white, alignment: .leading, verticalAlignment: .top)
        )
        let root = ViewNode(
            frame: Rect(x: 0, y: 0, width: 20, height: 32),
            clipsToBounds: true,
            children: [textNode]
        )

        let scene = ScenePainter.paint(root: root, clearColor: .black, surfaceSize: surfaceSize)
        let glyph = scene.layers[0].pixelGlyphs.first

        #expect(glyph != nil)
        if let glyph {
            #expect(glyph.clipX == 0)
            #expect(glyph.clipY == 0)
            #expect(glyph.clipWidth == 20)
            #expect(glyph.clipHeight == 32)
        }
    }

    @Test("Ancestor opacity multiplies native glyph alpha exactly once - VAL-TEXT-011")
    func ancestorOpacityMultipliesNativeGlyphAlphaExactlyOnce() {
        defer { NativeTextRenderer.resetTestingOverrides() }
        NativeTextRenderer.testingOverrides.layout = { text, style, _, _ in
            syntheticNativeLayout(for: text, style: style)
        }
        NativeTextRenderer.testingOverrides.rasterizeGlyphForLayout = { _, _, _ in
            stubNativeGlyphBitmap()
        }

        let child = ViewNode(
            frame: Rect(x: 10, y: 10, width: 40, height: 24),
            text: "A",
            textStyle: PixelTextStyle(
                color: Color(red: 1, green: 1, blue: 1, alpha: 0.8),
                alignment: .leading,
                verticalAlignment: .top,
                nativeFontSize: 18
            )
        )
        let parent = ViewNode(
            frame: Rect(x: 0, y: 0, width: 60, height: 40),
            opacity: 0.5,
            children: [child]
        )

        let scene = ScenePainter.paint(root: parent, clearColor: .black, surfaceSize: surfaceSize)
        let glyph = scene.layers[0].glyphs.first

        #expect(scene.layers[0].pixelGlyphs.isEmpty)
        #expect(glyph != nil)
        if let glyph {
            #expect(glyph.colorA == 0.4)
        }
    }

    @Test("Ancestor opacity multiplies pixel glyph alpha exactly once - VAL-TEXT-011")
    func ancestorOpacityMultipliesPixelGlyphAlphaExactlyOnce() {
        let child = ViewNode(
            frame: Rect(x: 10, y: 10, width: 40, height: 24),
            text: SymbolIcon.search.rawValue,
            textStyle: PixelTextStyle(
                color: Color(red: 1, green: 1, blue: 1, alpha: 0.8),
                alignment: .leading,
                verticalAlignment: .top
            )
        )
        let parent = ViewNode(
            frame: Rect(x: 0, y: 0, width: 60, height: 40),
            opacity: 0.5,
            children: [child]
        )

        let scene = ScenePainter.paint(root: parent, clearColor: .black, surfaceSize: surfaceSize)
        let glyph = scene.layers[0].pixelGlyphs.first

        #expect(glyph != nil)
        if let glyph {
            #expect(glyph.colorA == 0.4)
        }
    }

    @Test("Hidden and degenerate text nodes stay atlas-silent - VAL-TEXT-013")
    func hiddenAndDegenerateTextNodesStayAtlasSilent() {
        let hidden = ScenePainter.paint(
            root: ViewNode(
                frame: Rect(x: 0, y: 0, width: 80, height: 24),
                text: "Hidden",
                textStyle: PixelTextStyle(color: .white),
                isHidden: true
            ),
            clearColor: .black,
            surfaceSize: surfaceSize
        )
        let zeroSize = ScenePainter.paint(
            root: ViewNode(
                frame: Rect(x: 0, y: 0, width: 0, height: 24),
                text: "Zero",
                textStyle: PixelTextStyle(color: .white)
            ),
            clearColor: .black,
            surfaceSize: surfaceSize
        )
        let zeroVisibleArea = ScenePainter.paint(
            root: ViewNode(
                frame: Rect(x: 0, y: 0, width: 20, height: 20),
                text: "Inset",
                textStyle: PixelTextStyle(
                    color: .white,
                    insets: EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10)
                )
            ),
            clearColor: .black,
            surfaceSize: surfaceSize
        )
        let zeroEffectiveOpacity = ScenePainter.paint(
            root: ViewNode(
                frame: Rect(x: 0, y: 0, width: 80, height: 24),
                opacity: 0,
                children: [
                    ViewNode(
                        frame: Rect(x: 0, y: 0, width: 80, height: 24),
                        text: "Gone",
                        textStyle: PixelTextStyle(color: .white)
                    )
                ]
            ),
            clearColor: .black,
            surfaceSize: surfaceSize
        )

        expectAtlasSilent(hidden)
        expectAtlasSilent(zeroSize)
        expectAtlasSilent(zeroVisibleArea)
        expectAtlasSilent(zeroEffectiveOpacity)
    }

    @Test("Scrollable nodes emit indicator quads after children")
    func scrollableNodeEmitsIndicatorOverlay() {
        let child = ViewNode(
            frame: Rect(x: 0, y: 0, width: 160, height: 240),
            backgroundColor: .white
        )
        let node = ViewNode(
            frame: Rect(x: 10, y: 20, width: 120, height: 80),
            backgroundColor: Color(red: 0.1, green: 0.1, blue: 0.1, alpha: 1),
            scrollAxis: .vertical,
            scrollOffset: 32,
            showsScrollIndicator: true,
            children: [child]
        )

        let runtime = RetainedViewRuntime(root: node)
        let scene = runtime.renderScene()

        let totalQuads = scene.layers.reduce(0) { $0 + $1.quads.count }
        #expect(totalQuads >= 3)
    }

    @Test("Scroll indicators stay last in draw order after promoted children")
    func scrollIndicatorUsesParentSubtreeTopLayer() {
        let baseChild = ViewNode(
            frame: Rect(x: 0, y: 0, width: 160, height: 160),
            backgroundColor: .white
        )
        let promotedChild = ViewNode(
            frame: Rect(x: 0, y: 32, width: 160, height: 160),
            backgroundColor: Color(red: 0.2, green: 0.5, blue: 1.0, alpha: 1),
            zIndex: 1
        )
        let node = ViewNode(
            frame: Rect(x: 10, y: 20, width: 120, height: 80),
            backgroundColor: Color(red: 0.1, green: 0.1, blue: 0.1, alpha: 1),
            scrollAxis: .vertical,
            scrollOffset: 32,
            showsScrollIndicator: true,
            children: [baseChild, promotedChild]
        )

        let runtime = RetainedViewRuntime(root: node)
        let scene = runtime.renderScene()

        #expect(scene.layers.count == 1)
        #expect(scene.layers[0].quads.count == 4)
        let indicatorQuad = scene.layers[0].quads.last!
        #expect(indicatorQuad.startR == node.scrollIndicatorColor.red)
        #expect(indicatorQuad.startG == node.scrollIndicatorColor.green)
        #expect(indicatorQuad.startB == node.scrollIndicatorColor.blue)
    }

    @Test("Deferred scroll indicators flush after sibling base quads")
    func deferredScrollIndicatorsFlushAfterSiblingBaseQuads() {
        let leftIndicator = Color(red: 0.9, green: 0.2, blue: 0.2, alpha: 0.6)
        let rightIndicator = Color(red: 0.2, green: 0.7, blue: 1.0, alpha: 0.6)

        let left = ViewNode(
            frame: Rect(x: 0, y: 0, width: 80, height: 50),
            scrollAxis: .vertical,
            scrollOffset: 20,
            showsScrollIndicator: true,
            scrollIndicatorColor: leftIndicator,
            children: [ViewNode(frame: Rect(x: 0, y: 0, width: 80, height: 120), backgroundColor: .white)]
        )
        let right = ViewNode(
            frame: Rect(x: 90, y: 0, width: 80, height: 50),
            scrollAxis: .vertical,
            scrollOffset: 20,
            showsScrollIndicator: true,
            scrollIndicatorColor: rightIndicator,
            children: [ViewNode(frame: Rect(x: 0, y: 0, width: 80, height: 120), backgroundColor: .black)]
        )
        let root = ViewNode(
            frame: Rect(x: 0, y: 0, width: 180, height: 70),
            children: [left, right]
        )

        let runtime = RetainedViewRuntime(root: root)
        let scene = runtime.renderScene()
        let deferredColors = Array(scene.layers[0].quads.suffix(2)).map {
            Color(red: $0.startR, green: $0.startG, blue: $0.startB, alpha: $0.startA)
        }

        #expect(deferredColors == [leftIndicator, rightIndicator])
    }

    // MARK: - VAL-PARITY-004: ScenePainter-visible proof for replayed deferred overlays

    @Test("Replayed deferred overlays stay after base content on scene path - VAL-PARITY-004")
    func replayedDeferredOverlaysStayAfterBaseContent() {
        let base = ViewNode(
            frame: Rect(x: 0, y: 0, width: 40, height: 40),
            backgroundColor: .white
        )
        let deferredOverlay = ViewNode(
            frame: Rect(x: 10, y: 10, width: 20, height: 20),
            backgroundColor: .black,
            paintsInDeferredPhase: true
        )
        let root = ViewNode(
            frame: Rect(x: 0, y: 0, width: 60, height: 60),
            isHitTestVisible: false,
            children: [base, deferredOverlay]
        )
        let runtime = RetainedViewRuntime(root: root)

        // Initial scene paint - verify initial ordering
        let initialScene = runtime.renderScene()
        let initialQuads = sceneFillRects(in: initialScene)
        #expect(initialQuads.count == 2)
        #expect(initialQuads[0] == base.frame)
        #expect(initialQuads[1] == deferredOverlay.frame)

        // Mutate base content elsewhere to trigger replay
        base.backgroundColor = Color(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        let replayedScene = runtime.renderScene()
        let replayedQuads = sceneFillRects(in: replayedScene)

        // VAL-PARITY-004: Deferred overlay stays after base content on replay
        #expect(replayedQuads.count == 2)
        #expect(replayedQuads[0] == base.frame)
        #expect(replayedQuads[1] == deferredOverlay.frame)
    }

    @Test("Replayed deferred scroll indicators stay last after unchanged sibling subtree - VAL-PARITY-004")
    func replayedDeferredScrollIndicatorsStayLastAfterSiblingReplay() {
        let leftContent = ViewNode(
            frame: Rect(x: 0, y: 0, width: 80, height: 120),
            backgroundColor: .white
        )
        let rightContent = ViewNode(
            frame: Rect(x: 0, y: 0, width: 80, height: 120),
            backgroundColor: .black
        )

        let left = ViewNode(
            frame: Rect(x: 0, y: 0, width: 80, height: 50),
            scrollAxis: .vertical,
            scrollOffset: 20,
            showsScrollIndicator: true,
            children: [leftContent]
        )
        let right = ViewNode(
            frame: Rect(x: 90, y: 0, width: 80, height: 50),
            scrollAxis: .vertical,
            scrollOffset: 20,
            showsScrollIndicator: true,
            children: [rightContent]
        )

        let root = ViewNode(
            frame: Rect(x: 0, y: 0, width: 180, height: 70),
            isHitTestVisible: false,
            children: [left, right]
        )
        let runtime = RetainedViewRuntime(root: root)

        // Initial render
        let initialScene = runtime.renderScene()
        let initialQuadRects = sceneFillRects(in: initialScene)
        _ = sceneQuadColors(in: initialScene)

        #expect(initialQuadRects.count >= 4) // left content, right content, 2 indicators

        // Mutate right content to trigger replay of left subtree
        rightContent.backgroundColor = Color(red: 0.2, green: 0.5, blue: 0.8, alpha: 1)
        let replayedScene = runtime.renderScene()
        let replayedQuadRects = sceneFillRects(in: replayedScene)
        let replayedQuadColors = sceneQuadColors(in: replayedScene)

        // VAL-PARITY-004: Deferred indicators remain last after replay
        #expect(replayedQuadRects.count >= 4)
        #expect(replayedQuadRects.count == initialQuadRects.count)

        // Indicators should still be at the end
        let lastTwoColors = Array(replayedQuadColors.suffix(2))
        #expect(lastTwoColors[0] == left.scrollIndicatorColor)
        #expect(lastTwoColors[1] == right.scrollIndicatorColor)
    }

    // MARK: - VAL-PARITY-005: ScenePainter-visible proof for nested deferred subtree ordering

    @Test("Nested deferred subtrees keep parent-before-child ordering on scene path - VAL-PARITY-005")
    func nestedDeferredSceneSubtreesPreserveParentBeforeChildOrdering() {
        let deferredGrandchild = ViewNode(
            frame: Rect(x: 5, y: 5, width: 10, height: 10),
            backgroundColor: .black,
            paintsInDeferredPhase: true
        )
        let deferredChild = ViewNode(
            frame: Rect(x: 10, y: 10, width: 20, height: 20),
            backgroundColor: .white,
            isHitTestVisible: false,
            paintsInDeferredPhase: true,
            children: [deferredGrandchild]
        )
        let root = ViewNode(
            frame: Rect(x: 0, y: 0, width: 50, height: 50),
            isHitTestVisible: false,
            children: [deferredChild]
        )
        let runtime = RetainedViewRuntime(root: root)

        // Initial scene paint
        let initialScene = runtime.renderScene()
        let initialQuads = sceneFillRects(in: initialScene)

        // VAL-PARITY-005: Parent deferred comes before child deferred on initial paint
        #expect(initialQuads.count == 2)
        #expect(initialQuads[0] == deferredChild.frame)
        #expect(initialQuads[1] == Rect(x: 15, y: 15, width: 10, height: 10))
    }

    @Test("Nested deferred scene replay preserves parent-before-child ordering - VAL-PARITY-005")
    func nestedDeferredSceneReplayPreservesParentBeforeChildOrdering() {
        let base = ViewNode(
            frame: Rect(x: 0, y: 0, width: 12, height: 12),
            backgroundColor: .white
        )
        let deferredGrandchild = ViewNode(
            frame: Rect(x: 4, y: 4, width: 8, height: 8),
            backgroundColor: .black,
            paintsInDeferredPhase: true
        )
        let deferredChild = ViewNode(
            frame: Rect(x: 20, y: 20, width: 20, height: 20),
            backgroundColor: Color(red: 0.2, green: 0.4, blue: 0.8, alpha: 1),
            isHitTestVisible: false,
            paintsInDeferredPhase: true,
            children: [deferredGrandchild]
        )
        let root = ViewNode(
            frame: Rect(x: 0, y: 0, width: 60, height: 60),
            isHitTestVisible: false,
            children: [base, deferredChild]
        )
        let runtime = RetainedViewRuntime(root: root)

        // Initial render
        _ = runtime.renderScene()

        // Mutate base to trigger replay of deferred subtree
        base.backgroundColor = Color(red: 0.8, green: 0.9, blue: 1, alpha: 1)
        let replayedScene = runtime.renderScene()

        // VAL-PARITY-005: Parent-before-child ordering preserved on replay
        let quads = sceneFillRects(in: replayedScene)
        #expect(quads.count == 3)
        #expect(quads[0] == base.frame)  // Base first
        #expect(quads[1] == deferredChild.frame)  // Parent deferred before child
        #expect(quads[2] == Rect(x: 24, y: 24, width: 8, height: 8))  // Grandchild last
    }

    // MARK: - Clear color

    @Test("Scene preserves the clear color")
    func clearColorPreserved() {
        let node = ViewNode(frame: Rect(x: 0, y: 0, width: 10, height: 10))
        let scene = ScenePainter.paint(root: node, clearColor: .white, surfaceSize: surfaceSize)

        #expect(scene.clearColor == .white)
    }

    // MARK: - Helper functions for VAL-PARITY-004 and VAL-PARITY-005

    private func sceneFillRects(in scene: GPUIScene) -> [Rect] {
        scene.layers.flatMap { layer in
            layer.quads.map { quad in
                Rect(x: Double(quad.x), y: Double(quad.y), width: Double(quad.width), height: Double(quad.height))
            }
        }
    }

    private func sceneQuadColors(in scene: GPUIScene) -> [Color] {
        scene.layers.flatMap { layer in
            layer.quads.map { quad in
                Color(red: quad.startR, green: quad.startG, blue: quad.startB, alpha: quad.startA)
            }
        }
    }

    private func expectAtlasSilent(_ scene: GPUIScene) {
        #expect(scene.layers.allSatisfy { $0.glyphs.isEmpty && $0.pixelGlyphs.isEmpty })
        #expect(scene.glyphAtlas == nil)
        #expect(scene.pixelGlyphAtlas == nil)
    }

    private func syntheticNativeLayout(for text: String, style: PixelTextStyle) -> NativeTextLayoutResult {
        let characters = Array(text)
        let glyphs = characters.enumerated().map { index, character in
            NativeTextGlyphLayout(
                character: character,
                origin: Point(x: Double(index) * 9, y: 0),
                advance: 9,
                glyphID: UInt32(index + 1),
                fontFamily: style.fontFamily,
                weight: style.weight,
                fontSize: style.nativeFontPixelSize,
                sourceIndex: index
            )
        }
        let width = Double(max(characters.count, 1)) * 9
        let height = max(style.nativeFontPixelSize, 1)
        return NativeTextLayoutResult(
            lines: [
                NativeTextLineLayout(
                    text: text,
                    width: width,
                    height: height,
                    glyphs: glyphs
                )
            ],
            contentSize: Size(width: width, height: height),
            measuredSize: Size(width: width, height: height)
        )
    }

    private func stubNativeGlyphBitmap() -> NativeGlyphBitmap {
        NativeGlyphBitmap(
            surface: BitmapSurface(
                width: 1,
                height: 1,
                bytesPerRow: 4,
                pixels: Data([255, 255, 255, 255])
            ),
            bearingX: 0,
            bearingY: 0,
            advance: 1
        )
    }
}
