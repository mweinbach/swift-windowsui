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
            Rect(x: 0, y: 0, width: 100, height: 50), radii: nil, uniformRadius: 0, space: .layout)

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
            clip.intersecting(
                Rect(x: 100, y: 100, width: 10, height: 10), radii: nil, uniformRadius: 0, space: .layout),
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
            Rect(x: 0, y: 0, width: 100, height: 60), radii: nil, uniformRadius: 0, space: .layout)!

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

    /// The uniform radius has always been floored at 0; per-corner radii were
    /// copied verbatim, so a negative or non-finite corner survived into
    /// `resolvedCornerRadius` and from there into a primitive's
    /// `clipCornerRadius` — a NaN that erases the primitive in both backends'
    /// distance term, and an infinity that also sizes the corner-zone rects
    /// the analysis is built from.
    func testPerCornerRadiiAreFlooredLikeTheUniformScalar() async {
        let clip = RuntimeClipShape.bounds(
            of: Rect(x: 0, y: 0, width: 100, height: 100),
            radii: RetainedCornerRadii(topLeft: 12, topRight: -4, bottomRight: .nan, bottomLeft: .infinity),
            uniformRadius: 0,
            space: .layout)

        let corners = try? XCTUnwrap(clip.radii)
        XCTAssertEqual(corners?.topLeft, 12)
        XCTAssertEqual(corners?.topRight, 0)
        XCTAssertEqual(corners?.bottomRight, 0)
        XCTAssertEqual(corners?.bottomLeft, 0)
        XCTAssertEqual(clip.uniformRadius, 12)

        for quadRect in [
            Rect(x: 0, y: 0, width: 8, height: 8),
            Rect(x: 92, y: 0, width: 8, height: 8),
            Rect(x: 92, y: 92, width: 8, height: 8),
            Rect(x: 0, y: 92, width: 8, height: 8),
        ] {
            let radius = clip.resolvedCornerRadius(forQuadRect: quadRect)
            XCTAssertTrue(radius.isFinite, "\(quadRect) resolved to \(radius)")
            XCTAssertGreaterThanOrEqual(radius, 0)
        }

        let nonFiniteUniform = RuntimeClipShape.bounds(
            of: Rect(x: 0, y: 0, width: 40, height: 40), radii: nil, uniformRadius: .infinity, space: .layout)
        XCTAssertEqual(nonFiniteUniform.uniformRadius, 0, "a square corner is the degradation every consumer handles")
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

    /// `encode` is the writer half of the same encoding, and it used to copy a
    /// collapsed rect through field for field. `Rect(0, 0, 0, 0)` written that
    /// way reads back as *absent* — the in-band sentinel this type exists to
    /// kill, reintroduced by the one function whose job is to avoid it.
    func testEncodingACollapsedClipSaysEmptyNotAbsent() async {
        var quad = QuadPrimitive(x: 0, y: 0, width: 40, height: 40, startA: 1, endA: 1)
        quad.contentMask = GPUIContentMask(bounds: Rect(x: 0, y: 0, width: 0, height: 0))

        XCTAssertFalse(
            GPUIClipEncoding.isAbsent(
                clipX: quad.clipX, clipY: quad.clipY, clipWidth: quad.clipWidth, clipHeight: quad.clipHeight),
            "an origin-anchored collapsed clip must not encode as 'unclipped'")
        XCTAssertTrue(
            GPUIClipEncoding.isEmpty(
                clipX: quad.clipX, clipY: quad.clipY, clipWidth: quad.clipWidth, clipHeight: quad.clipHeight))

        var scene = GPUIScene(clearColor: .black)
        scene.addQuad(quad)
        XCTAssertTrue(scene.layers[0].quads.isEmpty, "and the scene boundary must reject it")

        // A positioned collapse encodes the same way, and a real clip is
        // untouched.
        var positioned = quad
        positioned.contentMask = GPUIContentMask(bounds: Rect(x: 10, y: 10, width: 20, height: 0))
        XCTAssertEqual(positioned.clipWidth, GPUIClipEncoding.emptyExtent)
        XCTAssertEqual(positioned.clipHeight, GPUIClipEncoding.emptyExtent)

        var real = quad
        real.contentMask = GPUIContentMask(bounds: Rect(x: 4, y: 5, width: 6, height: 7))
        XCTAssertEqual([real.clipX, real.clipY, real.clipWidth, real.clipHeight], [4, 5, 6, 7])
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
    ///
    /// R-ROT sharpened the scene path to the *turned* shape (an offscreen pass
    /// composited back through `ImagePrimitive.rotationRadians`), which the
    /// frame path cannot follow: its clip is a rect on a `RenderCommand` and
    /// it has no offscreen pass to composite — the same reason it draws a
    /// rotated node's geometry as an upright bounding box (`PaintPlacement`'s
    /// `axisAligned`). So the two no longer paint the *same* region, and what
    /// is asserted here is the relationship that survives and matters: the
    /// fallback is a **superset**. Every pixel the GPU path paints, the
    /// fallback paints too; the fallback additionally fills the corners of the
    /// bounding box the turned rect does not reach. A fallback that over-paints
    /// a corner is a visible imprecision; one that dropped content would be a
    /// blank view. Documented in `docs/GPURenderingPipeline.md`.
    func testRotatedClipFallbackIsASupersetOfTheScenePathRegion() async {
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

        var scenePainted = 0
        var framePainted = 0
        var sceneOnly = 0
        for offset in stride(from: 0, to: sceneBitmap.pixels.count, by: 4) {
            let sceneCovered = sceneBitmap.pixels[offset + 2] > 128
            let frameCovered = frameBitmap.pixels[offset + 2] > 128
            if sceneCovered { scenePainted += 1 }
            if frameCovered { framePainted += 1 }
            if sceneCovered && !frameCovered { sceneOnly += 1 }
        }

        XCTAssertGreaterThan(scenePainted, 1000, "the fixture must paint a substantial clipped region")
        XCTAssertEqual(
            sceneOnly, 0,
            "the frame path may be imprecise at the corners, but it may never drop a pixel the scene "
                + "path paints")
        XCTAssertGreaterThan(
            framePainted, scenePainted,
            "and the imprecision is exactly the corners of the bounding box the turned rect misses")
    }

    /// The same divergence one level down. `appendCommands` took no inherited
    /// transform at all: it applied a node's *own* transform to `paintFrame`
    /// and then handed children a clip narrowed in that space while their
    /// frames were still in layout space. Under a single transform the two
    /// happen to coincide, which is why the rotated case above passed; nest a
    /// rotation inside a translated *and* scaled ancestor and the frame path
    /// clipped a region the scene path never painted. Both sides now say
    /// `.painted`, so the `Space` assertion cannot catch this — only agreement
    /// can.
    func testANestedNonCommutingTransformClipsTheSameRegionOnBothPaths() async {
        func makeTree() -> ViewNode {
            // Large enough that the surviving pixels are decided by the clip,
            // not by where the child's own edges land.
            let child = ViewNode(
                frame: Rect(x: -200, y: -200, width: 600, height: 600),
                backgroundColor: Color(red: 1, green: 0.2, blue: 0.2, alpha: 1)
            )
            let clipper = ViewNode(
                frame: Rect(x: 10, y: 10, width: 40, height: 40),
                clipsToBounds: true,
                transform: Transform2D(rotation: 0.6),
                children: [child]
            )
            // Translation and scale together: the ancestor moves the clip and
            // resizes it, and neither commutes with the rotation below it.
            let ancestor = ViewNode(
                frame: Rect(x: 20, y: 20, width: 80, height: 80),
                transform: Transform2D(translationX: 25, translationY: 15, scaleX: 1.6, scaleY: 1.6),
                children: [clipper]
            )
            return ViewNode(frame: Rect(x: 0, y: 0, width: 160, height: 160), children: [ancestor])
        }

        let size = IntSize(width: 160, height: 160)
        let sceneBitmap = GPUIRawSceneRasterizer.rasterize(
            RetainedViewRuntime(root: makeTree()).renderScene(), size: size)
        let frameBitmap = GPUIRawSceneRasterizer.rasterize(
            RetainedViewRuntime(root: makeTree()).renderFrame(), size: size)

        var agreeing = 0
        var total = 0
        var scenePainted = 0
        var framePainted = 0
        var sceneOnly = 0
        for offset in stride(from: 0, to: sceneBitmap.pixels.count, by: 4) {
            let sceneCovered = sceneBitmap.pixels[offset + 2] > 128
            let frameCovered = frameBitmap.pixels[offset + 2] > 128
            total += 1
            if sceneCovered { scenePainted += 1 }
            if frameCovered { framePainted += 1 }
            if sceneCovered && !frameCovered { sceneOnly += 1 }
            if sceneCovered == frameCovered {
                agreeing += 1
            }
        }

        // Guard against the degenerate agreement of two blank frames.
        XCTAssertGreaterThan(scenePainted, 1000, "the fixture must paint a substantial clipped region")
        XCTAssertGreaterThan(framePainted, 1000, "the frame path must paint the clipped region too")
        // The clip here is rotated, so the frame path's region is the bounding
        // box of the scene path's (see
        // `testRotatedClipFallbackIsASupersetOfTheScenePathRegion`). What this
        // test is about is the *ancestor* transform: if the frame path failed
        // to accumulate the translation and scale above the rotation, the two
        // regions would not even overlap, let alone nest.
        _ = agreeing
        _ = total
        XCTAssertEqual(
            sceneOnly, 0,
            "the frame path must accumulate ancestor transforms into the frame it clips by — without "
                + "them its region is somewhere else entirely, not a superset of this one")
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

    /// The clip a node establishes is narrowed by its *transformed* frame on
    /// every path that paints, and prepaint used to narrow it by the
    /// untransformed one — so a rotated `.clipped()` container painted one
    /// region and accepted pointers in a different one. Nothing the user can
    /// see may be dead to the pointer, and nothing dead to the eye may be
    /// live to the pointer.
    func testTheInteractiveRegionOfARotatedClipIsItsVisibleRegion() async {
        var activations = 0
        let child = ViewNode(
            frame: Rect(x: -40, y: -40, width: 180, height: 180),
            backgroundColor: Color(red: 1, green: 0.2, blue: 0.2, alpha: 1),
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
        let bitmap = GPUIRawSceneRasterizer.rasterize(
            runtime.renderScene(), size: IntSize(width: 100, height: 100))

        func isPainted(_ x: Int, _ y: Int) -> Bool {
            bitmap.pixels[(y * 100 + x) * 4 + 2] > 128
        }
        func hits(_ x: Int, _ y: Int) -> Bool {
            let before = activations
            let point = Point(x: Double(x) + 0.5, y: Double(y) + 0.5)
            runtime.pointerDown(at: point)
            runtime.pointerUp(at: point)
            return activations > before
        }

        // Inside the rotated container's painted region, outside the
        // *unrotated* rect the interaction clip used to be narrowed by. The
        // container is 60x60 at (20, 20) turned by 0.5 rad about (50, 50), so
        // its own corners reach out to roughly (50 ± 41, 50) and (50, 50 ± 41)
        // while the corners of that bounding box are outside it entirely.
        XCTAssertTrue(isPainted(85, 45), "the fixture must paint the probe")
        XCTAssertTrue(hits(85, 45), "a painted pixel of a rotated clip must accept the pointer")
        XCTAssertTrue(isPainted(50, 25))
        XCTAssertTrue(hits(50, 25))
        XCTAssertFalse(isPainted(95, 95))
        XCTAssertFalse(hits(95, 95), "a pixel the rotated clip rejects must stay dead")
        // R-ROT: and the corner of the bounding box is dead to both, now that
        // the clip is the turned shape rather than the box it fits in.
        XCTAssertFalse(isPainted(12, 12), "the corner of the bounding box is outside the turned clip")
        XCTAssertFalse(hits(12, 12), "so it takes no pointer either")

        var agreeing = 0
        var total = 0
        for y in stride(from: 1, to: 100, by: 3) {
            for x in stride(from: 1, to: 100, by: 3) {
                total += 1
                if isPainted(x, y) == hits(x, y) {
                    agreeing += 1
                }
            }
        }
        XCTAssertGreaterThan(
            Double(agreeing) / Double(total), 0.98,
            "the visible region and the interactive region are one region")
    }

    /// Prepaint's clip is handed straight to `ScenePainter` for every
    /// deferred subtree, so it has to be narrowed in the space the painter
    /// narrows in. A layout-space clip under a translating transform emptied
    /// out against the painted frame and the overlay vanished.
    func testADeferredSubtreeUnderATranslatedClipPaintsWhereItsClipMoved() async {
        let deferred = ViewNode(
            frame: Rect(x: 0, y: 0, width: 40, height: 40),
            backgroundColor: Color(red: 0, green: 1, blue: 0, alpha: 1),
            paintsInDeferredPhase: true
        )
        let clipper = ViewNode(
            frame: Rect(x: 0, y: 0, width: 40, height: 40),
            clipsToBounds: true,
            transform: Transform2D.translation(x: 50, y: 0),
            children: [deferred]
        )
        let root = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 100), children: [clipper])

        let quads = RetainedViewRuntime(root: root).renderScene().layers[0].quads
        XCTAssertEqual(quads.count, 1, "the deferred overlay travels with the transform, it is not clipped away")
        XCTAssertEqual(Double(quads[0].x), 50, accuracy: 0.001)
    }

    /// The frame path draws the border at `paintFrame` but used to gate it on
    /// the untransformed `absoluteFrame` — the one surviving mixed-space
    /// comparison after WS-16 — so a translated bordered view inside a clip
    /// lost its border on the fallback renderer while the scene path drew it.
    func testATranslatedBorderSurvivesTheFramePathClipGate() async {
        let bordered = ViewNode(
            frame: Rect(x: -60, y: 20, width: 50, height: 50),
            borderColor: Color(red: 0, green: 0, blue: 1, alpha: 1),
            borderWidth: 4,
            transform: Transform2D.translation(x: 80, y: 0)
        )
        let clipper = ViewNode(
            frame: Rect(x: 0, y: 0, width: 100, height: 100),
            clipsToBounds: true,
            children: [bordered]
        )

        let frame = RetainedViewRuntime(root: clipper).renderFrame()
        let borderRects: [Rect] = frame.commands.compactMap { command in
            guard case .fillRect(let fill) = command, fill.color.blue > 0.5 else { return nil }
            return fill.rect
        }
        XCTAssertEqual(borderRects.count, 1, "the border is gated on the frame the path actually paints")
        XCTAssertEqual(borderRects.first?.origin.x ?? -1, 20, accuracy: 0.001)
    }

    // MARK: - The space discriminator

    func testNarrowingCarriesTheClipSpaceForward() async {
        let painted = RuntimeClipShape.bounds(
            of: Rect(x: 0, y: 0, width: 60, height: 60), radii: nil, uniformRadius: 8, space: .painted)
        let narrowed = painted.intersecting(
            Rect(x: 0, y: 0, width: 60, height: 30), radii: nil, uniformRadius: 0, space: .painted)
        XCTAssertEqual(narrowed?.space, .painted, "a narrowed clip stays in the space it was narrowed in")

        let layout: RuntimeClipShape? = nil
        XCTAssertEqual(
            layout.narrowed(
                to: Rect(x: 0, y: 0, width: 10, height: 10), radii: nil, uniformRadius: 0, space: .layout)?.space,
            .layout)
    }

    func testEveryRuntimeClipIsNarrowedInPaintedSpace() async {
        let child = ViewNode(frame: Rect(x: 0, y: 0, width: 20, height: 20), paintsInDeferredPhase: true)
        let clipper = ViewNode(
            frame: Rect(x: 0, y: 0, width: 40, height: 40),
            clipsToBounds: true,
            children: [child]
        )
        let root = ViewNode(frame: Rect(x: 0, y: 0, width: 60, height: 60), children: [clipper])
        let runtime = RetainedViewRuntime(root: root)
        _ = runtime.renderScene()

        let spaces = runtime.prepaintClipSpacesForTesting
        XCTAssertFalse(spaces.isEmpty, "the fixture must record a clip")
        XCTAssertTrue(
            spaces.allSatisfy { $0 == .painted },
            "prepaint's clip is consumed by the painter, so it lives in the painter's space")
    }
}
