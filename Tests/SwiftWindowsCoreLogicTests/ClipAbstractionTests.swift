import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI

/// WS-16. Clipping used to be five hand-written intersection blocks that had
/// drifted in coordinate space, radius handling and nesting semantics. These
/// pin the single rule they were replaced by (`RuntimeClipShape`), the scene
/// contract's now-representable empty clip, and the rounded clip finally
/// reaching the glyph, image, shadow and path families.
@MainActor
final class ClipAbstractionTests: XCTestCase {

    // MARK: - RuntimeClipShape

    func testNarrowingWithoutRadiiKeepsTheRoundingAnchoredToTheShapeThatSetIt() async {
        let card = RuntimeClipShape.bounds(
            of: Rect(x: 0, y: 0, width: 100, height: 100), radii: nil, uniformRadius: 12, space: .layout)
        // A square `.clipped()` ancestor cuts the bottom half away.
        let narrowed = card.intersecting(
            Rect(x: 0, y: 0, width: 100, height: 50), radii: nil, uniformRadius: 0)

        let clipped = try? XCTUnwrap(narrowed)
        XCTAssertEqual(clipped?.rect, Rect(x: 0, y: 0, width: 100, height: 50))
        XCTAssertEqual(
            clipped?.shapeRect, Rect(x: 0, y: 0, width: 100, height: 100),
            "the rounding anchor stays on the node that established it")
        XCTAssertEqual(clipped?.uniformRadius, 12)
    }

    func testNarrowingToAnEmptyRegionIsRepresentableAndDistinctFromNoClip() async {
        let clip = RuntimeClipShape.bounds(
            of: Rect(x: 0, y: 0, width: 40, height: 40), radii: nil, uniformRadius: 0, space: .layout)
        XCTAssertNil(
            clip.intersecting(Rect(x: 100, y: 100, width: 10, height: 10), radii: nil, uniformRadius: 0),
            "an empty intersection is nil — the caller culls, it does not fall back to unclipped")

        let noClip: RuntimeClipShape? = nil
        XCTAssertTrue(noClip.allowsDrawing(Rect(x: 1000, y: 1000, width: 5, height: 5)))
        XCTAssertTrue(noClip.contains(Point(x: -50, y: -50)))
    }

    func testCutCornersResolveSquareWhileSurvivingCornersKeepTheirRadius() async {
        let card = RuntimeClipShape.bounds(
            of: Rect(x: 0, y: 0, width: 100, height: 100), radii: nil, uniformRadius: 16, space: .layout)
        // The scroll viewport cuts the card's bottom edge away.
        let scrolled = card.intersecting(
            Rect(x: 0, y: 0, width: 100, height: 60), radii: nil, uniformRadius: 0)!

        XCTAssertEqual(
            scrolled.resolvedCornerRadius(forQuadRect: Rect(x: 0, y: 0, width: 100, height: 8)), 16,
            accuracy: 0.001, "the card's own top corners survive the cut and stay rounded")
        XCTAssertEqual(
            scrolled.resolvedCornerRadius(forQuadRect: Rect(x: 0, y: 52, width: 100, height: 8)), 0,
            accuracy: 0.001, "the exposed cut edge is a straight ancestor edge, not an arc")
    }

    func testIntactUniformClipStillAnswersItsRadiusForEveryPrimitive() async {
        let clip = RuntimeClipShape.bounds(
            of: Rect(x: 0, y: 0, width: 200, height: 40), radii: nil, uniformRadius: 8, space: .layout)
        XCTAssertEqual(
            clip.resolvedCornerRadius(forQuadRect: Rect(x: 90, y: 15, width: 20, height: 10)), 8,
            accuracy: 0.001,
            "an intact uniform clip keeps the pre-existing rule: the zone analysis only engages once a corner is cut")
    }

    // MARK: - Nested clips (the square-inside-rounded bite)

    private func paintedQuads(root: ViewNode, size: Size = Size(width: 200, height: 200)) -> [QuadPrimitive] {
        ScenePainter.paint(root: root, clearColor: .black, surfaceSize: size).layers[0].quads
    }

    func testSquareInnerClipInsideRoundedCardEmitsNoClipRounding() async {
        let row = ViewNode(
            frame: Rect(x: 0, y: 0, width: 120, height: 20),
            backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1)
        )
        // The list body: a plain `.clipped()` inset inside the card.
        let body = ViewNode(
            frame: Rect(x: 20, y: 20, width: 120, height: 120),
            clipsToBounds: true,
            children: [row]
        )
        let card = ViewNode(
            frame: Rect(x: 0, y: 0, width: 160, height: 160),
            cornerRadius: 16,
            clipsToBounds: true,
            children: [body]
        )

        let quads = paintedQuads(root: card)
        XCTAssertEqual(quads.count, 1)
        XCTAssertEqual(
            quads[0].clipCornerRadius, 0, accuracy: 0.001,
            "a square inner clip must not apply the card's radius at its own square corners")
    }

    func testSquareInnerClipInsideRoundedCardEmitsNoClipRoundingOnTheDeferredPath() async {
        let row = ViewNode(
            frame: Rect(x: 0, y: 0, width: 120, height: 20),
            backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1),
            paintsInDeferredPhase: true
        )
        let body = ViewNode(
            frame: Rect(x: 20, y: 20, width: 120, height: 120),
            clipsToBounds: true,
            children: [row]
        )
        let card = ViewNode(
            frame: Rect(x: 0, y: 0, width: 160, height: 160),
            cornerRadius: 16,
            clipsToBounds: true,
            children: [body]
        )
        let runtime = RetainedViewRuntime(root: card)
        let scene = runtime.renderScene()

        let quads = scene.layers[0].quads
        XCTAssertEqual(quads.count, 1)
        XCTAssertEqual(
            quads[0].clipCornerRadius, 0, accuracy: 0.001,
            "the deferred path resolves clip rounding through the same clip shape as inline content")
    }

    func testPartiallyScrolledRoundedCardKeepsItsOwnRoundingAndSquaresTheCutEdge() async {
        // Two full-width bands inside the card: one at the card's rounded top,
        // one at the edge the viewport cuts.
        let topBand = ViewNode(
            frame: Rect(x: 0, y: 0, width: 100, height: 10),
            backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1)
        )
        let cutBand = ViewNode(
            frame: Rect(x: 0, y: 50, width: 100, height: 10),
            backgroundColor: Color(red: 0, green: 1, blue: 0, alpha: 1)
        )
        let card = ViewNode(
            frame: Rect(x: 0, y: 0, width: 100, height: 100),
            cornerRadius: 16,
            clipsToBounds: true,
            children: [topBand, cutBand]
        )
        let viewport = ViewNode(
            frame: Rect(x: 0, y: 0, width: 100, height: 60),
            clipsToBounds: true,
            children: [card]
        )

        let quads = paintedQuads(root: viewport, size: Size(width: 100, height: 100))
        XCTAssertEqual(quads.count, 2)
        XCTAssertEqual(
            quads[0].clipCornerRadius, 16, accuracy: 0.001,
            "the card's top corners are untouched by the viewport and stay rounded")
        XCTAssertEqual(
            quads[1].clipCornerRadius, 0, accuracy: 0.001,
            "the viewport's straight cut must not pop the card's rounding onto the viewport edge")
    }

    // MARK: - Rounded clips on the non-quad families

    func testTextInsideARoundedContainerCarriesTheContainerRounding() async {
        let label = ViewNode(
            frame: Rect(x: 0, y: 0, width: 120, height: 40),
            text: "CLIPPED",
            textStyle: PixelTextStyle(color: .white)
        )
        let card = ViewNode(
            frame: Rect(x: 0, y: 0, width: 120, height: 40),
            cornerRadius: 12,
            clipsToBounds: true,
            children: [label]
        )
        let scene = ScenePainter.paint(
            root: card, clearColor: .black, surfaceSize: Size(width: 120, height: 40))
        let glyphs = scene.layers[0].glyphs + scene.layers[0].pixelGlyphs
        XCTAssertFalse(glyphs.isEmpty, "the fixture must actually emit glyphs")
        for glyph in glyphs {
            XCTAssertEqual(
                glyph.clipCornerRadius, 12, accuracy: 0.001,
                "text inside a rounded container must be rounded, not rect-clipped")
        }
    }

    func testImageInsideARoundedContainerCarriesTheContainerRounding() async {
        let bitmap = BitmapSurface(
            width: 8, height: 8, bytesPerRow: 32, pixels: Data(repeating: 200, count: 8 * 8 * 4))
        let card = ViewNode(
            frame: Rect(x: 0, y: 0, width: 64, height: 64),
            bitmapSurface: bitmap,
            cornerRadius: 10,
            clipsToBounds: true
        )
        let scene = ScenePainter.paint(
            root: card, clearColor: .black, surfaceSize: Size(width: 64, height: 64))
        let images = scene.layers[0].images
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(
            images[0].clipCornerRadius, 10, accuracy: 0.001,
            "an image has no radius of its own, so its own clip has to round it")
    }

    // MARK: - The scene contract's empty clip

    func testPositionedZeroExtentClipDropsEveryFamily() async {
        var scene = GPUIScene(clearColor: .black)
        scene.addQuad(
            QuadPrimitive(
                x: 0, y: 0, width: 40, height: 40,
                startA: 1, endA: 1,
                clipX: 10, clipY: 10, clipWidth: 0, clipHeight: 0))
        scene.addGlyph(
            GlyphPrimitive(
                screenX: 0, screenY: 0, screenW: 40, screenH: 40,
                clipX: 10, clipY: 10, clipWidth: 0, clipHeight: 0))
        scene.addImage(
            ImagePrimitive(
                screenX: 0, screenY: 0, screenW: 40, screenH: 40,
                clipX: 10, clipY: 10, clipWidth: 0, clipHeight: 0))
        scene.addShadow(
            ShadowPrimitive(
                x: 0, y: 0, width: 40, height: 40,
                clipX: 10, clipY: 10, clipWidth: 0, clipHeight: 0))

        XCTAssertTrue(scene.layers[0].quads.isEmpty)
        XCTAssertTrue(scene.layers[0].glyphs.isEmpty)
        XCTAssertTrue(scene.layers[0].images.isEmpty)
        XCTAssertTrue(scene.layers[0].shadows.isEmpty)
        XCTAssertEqual(scene.paintRecordCount, 0)
    }

    func testCollapsedClipRasterizesToNothing() async {
        var scene = GPUIScene(clearColor: .black)
        scene.addQuad(
            QuadPrimitive(
                x: 0, y: 0, width: 32, height: 32,
                startR: 1, startG: 1, startB: 1, startA: 1,
                endR: 1, endG: 1, endB: 1, endA: 1,
                clipX: 10, clipY: 10, clipWidth: 0, clipHeight: 0))
        scene.finish()

        let bitmap = GPUIRawSceneRasterizer.rasterize(scene, size: IntSize(width: 32, height: 32))
        let nonBackground = stride(from: 0, to: bitmap.pixels.count, by: 4).filter { offset in
            bitmap.pixels[offset] != 0 || bitmap.pixels[offset + 1] != 0 || bitmap.pixels[offset + 2] != 0
        }
        XCTAssertTrue(
            nonBackground.isEmpty,
            "a clip that collapsed to nothing must hide its content, not release it onto the whole surface")
    }

    func testAllZeroClipStillMeansUnclipped() async {
        var scene = GPUIScene(clearColor: .black)
        scene.addQuad(QuadPrimitive(x: 0, y: 0, width: 40, height: 40, startA: 1, endA: 1))
        XCTAssertEqual(
            scene.layers[0].quads.count, 1,
            "the all-zero sentinel is how every unclipped primitive has always been encoded")
    }

    func testExplicitEmptyExtentIsDistinctFromAbsent() async {
        XCTAssertTrue(GPUIClipEncoding.isAbsent(clipX: 0, clipY: 0, clipWidth: 0, clipHeight: 0))
        XCTAssertFalse(GPUIClipEncoding.isEmpty(clipX: 0, clipY: 0, clipWidth: 0, clipHeight: 0))
        XCTAssertTrue(
            GPUIClipEncoding.isEmpty(
                clipX: 0, clipY: 0, clipWidth: GPUIClipEncoding.emptyExtent,
                clipHeight: GPUIClipEncoding.emptyExtent),
            "the negative sentinel lets a producer say 'clips everything' even at the origin")
        XCTAssertTrue(GPUIClipEncoding.isEmpty(clipX: 0, clipY: 0, clipWidth: 0, clipHeight: 10))
    }

    func testPathWithACollapsedClipIsDropped() async {
        var scene = GPUIScene(clearColor: .black)
        scene.addPath(
            PathPrimitive(
                elements: [
                    .moveTo(Point(x: 0, y: 0)), .lineTo(Point(x: 20, y: 0)), .lineTo(Point(x: 20, y: 20)), .close,
                ],
                bounds: Rect(x: 0, y: 0, width: 20, height: 20),
                fillColor: .white,
                clipBounds: Rect(x: 10, y: 10, width: 0, height: 0)
            ), toLayer: 0)
        XCTAssertTrue(scene.layers[0].paths.isEmpty)
    }

    // MARK: - One region under a transform

    /// The scene path used to clip a rotated `.clipped()` container to the
    /// rotated AABB while the frame path clipped to the *unrotated* rect at the
    /// original position — two completely different regions for one tree,
    /// swapped silently whenever the host fell back to the frame renderer.
    func testRotatedClipAgreesBetweenTheScenePathAndTheFramePath() async {
        func makeTree() -> ViewNode {
            let child = ViewNode(
                frame: Rect(x: -40, y: -40, width: 180, height: 180),
                backgroundColor: Color(red: 1, green: 0.2, blue: 0.2, alpha: 1)
            )
            let clipper = ViewNode(
                frame: Rect(x: 20, y: 20, width: 60, height: 60),
                clipsToBounds: true,
                transform: Transform2D(rotation: 0.5),
                children: [child]
            )
            return ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 100), children: [clipper])
        }

        let size = IntSize(width: 100, height: 100)
        let sceneBitmap = GPUIRawSceneRasterizer.rasterize(
            RetainedViewRuntime(root: makeTree()).renderScene(), size: size)
        let frameBitmap = GPUIRawSceneRasterizer.rasterize(
            RetainedViewRuntime(root: makeTree()).renderFrame(), size: size)

        var agreeing = 0
        var total = 0
        for offset in stride(from: 0, to: sceneBitmap.pixels.count, by: 4) {
            let sceneCovered = sceneBitmap.pixels[offset + 2] > 128
            let frameCovered = frameBitmap.pixels[offset + 2] > 128
            total += 1
            if sceneCovered == frameCovered {
                agreeing += 1
            }
        }
        XCTAssertGreaterThan(
            Double(agreeing) / Double(total), 0.98,
            "both paths must clip the rotated container to the same region")
    }

    func testAPointOutsideARotatedClipDoesNotHitTest() async {
        var activations = 0
        let child = ViewNode(
            frame: Rect(x: -40, y: -40, width: 180, height: 180),
            isHitTestVisible: true
        )
        child.onActivate = { activations += 1 }
        let clipper = ViewNode(
            frame: Rect(x: 20, y: 20, width: 60, height: 60),
            clipsToBounds: true,
            transform: Transform2D(rotation: 0.5),
            isHitTestVisible: false,
            children: [child]
        )
        let root = ViewNode(
            frame: Rect(x: 0, y: 0, width: 100, height: 100),
            isHitTestVisible: false,
            children: [clipper]
        )
        let runtime = RetainedViewRuntime(root: root)

        // Well outside the 60x60 clip in the container's own space.
        runtime.pointerDown(at: Point(x: 95, y: 95))
        runtime.pointerUp(at: Point(x: 95, y: 95))
        XCTAssertEqual(activations, 0, "the interactive clip must reject a point outside the clipped region")

        runtime.pointerDown(at: Point(x: 50, y: 50))
        runtime.pointerUp(at: Point(x: 50, y: 50))
        XCTAssertEqual(activations, 1, "the clip's interior still hits")
    }
}
