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

    @Test("Children with different zIndex values produce multiple layers")
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

        // Layer 0 contains childA (zIndex 0), then new layers pushed for zIndex 1 and 2.
        #expect(scene.layers.count == 3)
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

    // MARK: - Text

    @Test("Text nodes emit typed glyph primitives and atlas data")
    func textNodeProducesGlyphs() {
        let node = ViewNode(
            frame: Rect(x: 10, y: 20, width: 140, height: 40),
            text: "HI",
            textStyle: PixelTextStyle(color: .white, alignment: .leading, verticalAlignment: .top)
        )

        let scene = ScenePainter.paint(root: node, clearColor: .black, surfaceSize: surfaceSize)

        #expect(scene.layers.count == 1)
        #expect(scene.layers[0].glyphs.count == 2)
        #expect(scene.glyphAtlas != nil)
        #expect(scene.layers[0].glyphs[0].screenX >= 10)
        #expect(scene.layers[0].glyphs[0].screenY >= 20)
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
        #expect(scene.layers[0].glyphs.count == 1)
        #expect(scene.layers[0].glyphs[0].atlasU0 == uv.u0)
        #expect(scene.layers[0].glyphs[0].atlasV0 == uv.v0)
    }

    // MARK: - Clear color

    @Test("Scene preserves the clear color")
    func clearColorPreserved() {
        let node = ViewNode(frame: Rect(x: 0, y: 0, width: 10, height: 10))
        let scene = ScenePainter.paint(root: node, clearColor: .white, surfaceSize: surfaceSize)

        #expect(scene.clearColor == .white)
    }
}
