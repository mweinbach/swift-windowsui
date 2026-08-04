import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI

/// R-ROT (CLF-9 closure). WS-19 lowered rotation for one family — the quad
/// decoration a node paints for itself — and left four documented residuals:
/// a rotated card's shadow haloed its bounding box, a `Shape` background or
/// `Canvas` drawing inside a rotated subtree painted upright, text stayed
/// upright, and a rotated `.clipped()` container clipped to the box its
/// rotated frame fits in (√2 too large on each axis at 45°).
///
/// These are absolute-placement tests: every expectation is computed from the
/// tree by hand, not read back from another path. Agreement between the two
/// paint paths is necessary but not sufficient — before WS-19 both were wrong
/// together.
@MainActor
final class RotationClosureTests: XCTestCase {

    private let surfaceSize = Size(width: 200, height: 200)
    private let marker = Color(red: 1, green: 0.3, blue: 0.3, alpha: 1)

    private func paint(_ root: ViewNode, size: Size? = nil) -> GPUIScene {
        ScenePainter.paint(root: root, clearColor: .black, surfaceSize: size ?? surfaceSize)
    }

    /// A rect turned about `pivot` by `radians`, as a set of corner points.
    private func turned(_ point: Point, by radians: Double, about pivot: Point) -> Point {
        let dx = point.x - pivot.x
        let dy = point.y - pivot.y
        return Point(
            x: pivot.x + cos(radians) * dx - sin(radians) * dy,
            y: pivot.y + sin(radians) * dx + cos(radians) * dy
        )
    }

    // MARK: - Shadows

    func testARotatedNodeShadowCarriesTheNodeRotation() async throws {
        let node = ViewNode(
            frame: Rect(x: 40, y: 60, width: 80, height: 40),
            backgroundColor: .white,
            shadowColor: Color(red: 0, green: 0, blue: 0, alpha: 0.5),
            shadowSpread: 6,
            transform: Transform2D(rotation: .pi / 4)
        )

        let shadow = try XCTUnwrap(paint(node).layers[0].shadows.first)
        XCTAssertEqual(
            Double(shadow.rotationRadians), .pi / 4, accuracy: 1e-5,
            "the halo turns with the card it belongs to")

        // The shadow rect is the node's *unrotated* frame outset by the
        // spread, turned about the node's centre — which is the frame's own
        // centre, since the rotation is about it. So the centre is unmoved and
        // the extent is frame + 2·spread on each axis.
        XCTAssertEqual(Double(shadow.x) + Double(shadow.width) * 0.5, 80, accuracy: 1e-4)
        XCTAssertEqual(Double(shadow.y) + Double(shadow.height) * 0.5, 80, accuracy: 1e-4)
        XCTAssertEqual(Double(shadow.width), 92, accuracy: 1e-4, "80 + 2 × 6, not the bounding box's √2")
        XCTAssertEqual(Double(shadow.height), 52, accuracy: 1e-4)
    }

    func testAnUnrotatedNodeShadowIsUnchanged() async throws {
        let node = ViewNode(
            frame: Rect(x: 40, y: 60, width: 80, height: 40),
            backgroundColor: .white,
            shadowColor: Color(red: 0, green: 0, blue: 0, alpha: 0.5),
            shadowOffset: Point(x: 3, y: 5),
            shadowSpread: 6
        )

        let shadow = try XCTUnwrap(paint(node).layers[0].shadows.first)
        XCTAssertEqual(shadow.rotationRadians, 0)
        // The rect the backends fill — `(x + offset, y + offset)` — is the
        // frame outset by the spread and moved by the offset. The offset rides
        // in the primitive's own field rather than being folded into the
        // origin; folding it in *and* filling in the field moved it twice.
        XCTAssertEqual(Double(shadow.x + shadow.offsetX), 40 - 6 + 3, accuracy: 1e-9)
        XCTAssertEqual(Double(shadow.y + shadow.offsetY), 60 - 6 + 5, accuracy: 1e-9)
    }

    /// The offset is authored in the shadowed view's own space, so a card
    /// turned a quarter turn casts to its side, not down-screen.
    func testARotatedNodeShadowOffsetTurnsWithTheNode() async throws {
        let node = ViewNode(
            frame: Rect(x: 40, y: 60, width: 80, height: 40),
            backgroundColor: .white,
            shadowColor: Color(red: 0, green: 0, blue: 0, alpha: 0.5),
            shadowOffset: Point(x: 0, y: 10),
            shadowSpread: 0,
            transform: Transform2D(rotation: .pi / 2)
        )

        let shadow = try XCTUnwrap(paint(node).layers[0].shadows.first)
        XCTAssertEqual(Double(shadow.offsetX), -10, accuracy: 1e-6, "down in the card's space is left on screen")
        XCTAssertEqual(Double(shadow.offsetY), 0, accuracy: 1e-6)
    }

    /// The picture, not just the number: a 45° shadow's ink has to reach the
    /// diamond's points and stay off the square's corners.
    func testARotatedShadowRastersAsADiamondNotABox() async {
        var scene = GPUIScene(clearColor: .black)
        scene.addShadow(
            ShadowPrimitive(
                x: 60, y: 76, width: 80, height: 48,
                colorR: 1, colorG: 1, colorB: 1, colorA: 1,
                blurRadius: 1,
                rotationRadians: .pi / 2
            )
        )
        scene.finish()
        let surface = GPUIRawSceneRasterizer.rasterize(
            scene, size: IntSize(width: 200, height: 200))

        func luminance(_ x: Int, _ y: Int) -> Int {
            let offset = y * Int(surface.bytesPerRow) + x * 4
            return Int(surface.pixels[offset])
        }

        // A quarter turn swaps the extents about the centre (100, 100): the
        // shadow is 48 wide and 80 tall now.
        XCTAssertGreaterThan(
            luminance(100, 100 - 30), 200, "30 px above the centre is inside the turned rect (half height 40)")
        XCTAssertLessThan(
            luminance(100 - 30, 100), 55, "30 px left of the centre is outside it (half width 24)")
    }

    // MARK: - Paths

    func testRotatingAPathTurnsItsElementsAndItsArcAngles() async {
        let path = PathPrimitive(
            elements: [
                .moveTo(Point(x: 10, y: 0)),
                .lineTo(Point(x: 10, y: 10)),
                .arc(center: Point(x: 0, y: 0), radius: 10, startAngle: 0, endAngle: .pi / 2, clockwise: false),
            ],
            bounds: Rect(x: 0, y: 0, width: 10, height: 10),
            fillColor: .white
        )

        let turnedPath = path.rotated(by: .pi / 2, about: Point(x: 0, y: 0))

        guard case .moveTo(let start) = turnedPath.elements[0] else {
            return XCTFail("element kinds survive the turn")
        }
        XCTAssertEqual(start.x, 0, accuracy: 1e-9)
        XCTAssertEqual(start.y, 10, accuracy: 1e-9, "(10, 0) turned a quarter clockwise in screen space")

        guard case .arc(let centre, let radius, let startAngle, let endAngle, let clockwise) = turnedPath.elements[2]
        else {
            return XCTFail("the arc survives the turn as an arc")
        }
        XCTAssertEqual(centre.x, 0, accuracy: 1e-9)
        XCTAssertEqual(centre.y, 0, accuracy: 1e-9)
        XCTAssertEqual(radius, 10, "a rotation is rigid")
        XCTAssertEqual(startAngle, .pi / 2, accuracy: 1e-9, "both endpoints shift by the angle")
        XCTAssertEqual(endAngle, .pi, accuracy: 1e-9)
        XCTAssertFalse(clockwise, "the sweep direction is rotation-invariant")
    }

    func testARotatedPathReKeysTheRasterCaches() async {
        let path = PathPrimitive(
            elements: [
                .moveTo(Point(x: 0, y: 0)),
                .lineTo(Point(x: 40, y: 0)),
                .lineTo(Point(x: 40, y: 12)),
                .close,
            ],
            bounds: Rect(x: 0, y: 0, width: 40, height: 12),
            fillColor: .white
        )
        let turnedPath = path.rotated(by: 0.7, about: Point(x: 20, y: 6))

        XCTAssertNotEqual(
            path.shapeHash, turnedPath.shapeHash,
            "a turned path is a different picture, so it must be a different cache key")
        XCTAssertFalse(
            turnedPath.matchesShapeAndPaint(of: path, translatedBy: .zero),
            "and the collision tie-break agrees")
    }

    func testAPathBackgroundInsideARotatedNodeIsPaintedTurned() async {
        // A right triangle filling the node's box. Under a quarter turn the
        // vertex that was at the frame's bottom-right ends at its
        // bottom-left, which no upright emission can produce.
        let triangle = RenderPath(segments: [
            .moveTo(Point(x: 0, y: 0)),
            .lineTo(Point(x: 1, y: 0)),
            .lineTo(Point(x: 1, y: 1)),
            .close,
        ])
        let node = ViewNode(
            frame: Rect(x: 50, y: 50, width: 100, height: 100),
            backgroundColor: marker,
            backgroundPath: triangle,
            transform: Transform2D(rotation: .pi / 2)
        )

        let surface = GPUIRawSceneRasterizer.rasterize(
            paint(node), size: IntSize(width: 200, height: 200))
        func red(_ x: Int, _ y: Int) -> Int {
            Int(surface.pixels[y * Int(surface.bytesPerRow) + x * 4 + 2])
        }

        // Scaled into the node's frame the triangle is (50, 50), (150, 50),
        // (150, 150): the half of the square with `y < x`. A quarter turn
        // about the node's centre (100, 100) maps it to (150, 50), (150, 150),
        // (50, 150): the half with `x + y > 200`. Each of the two probes is
        // inside exactly one of them.
        XCTAssertGreaterThan(
            red(110, 140), 200, "(110, 140) is inside the turned triangle and outside the upright one")
        XCTAssertLessThan(
            red(90, 60), 40, "(90, 60) is inside the upright triangle and outside the turned one")
    }

    func testACanvasInsideARotatedNodeIsPaintedTurned() async throws {
        let node = ViewNode(
            frame: Rect(x: 50, y: 50, width: 100, height: 100),
            canvasDraw: { context, _ in
                context.fill(
                    Rect(x: 0, y: 0, width: 20, height: 20),
                    with: .color(Color(red: 1, green: 0.3, blue: 0.3, alpha: 1)))
            },
            transform: Transform2D(rotation: .pi / 2)
        )

        let quads = paint(node).layers[0].quads
        let canvasQuad = try XCTUnwrap(quads.first { $0.width == 20 && $0.height == 20 })
        XCTAssertEqual(
            Double(canvasQuad.rotationRadians), .pi / 2, accuracy: 1e-5,
            "a canvas rect is a quad, and it carries the subtree's angle")
        // The canvas's (0, 0) is the node's own origin (50, 50); the 20x20
        // cell's centre (60, 60) turns about (100, 100) to (140, 60).
        XCTAssertEqual(Double(canvasQuad.x) + 10, 140, accuracy: 1e-4)
        XCTAssertEqual(Double(canvasQuad.y) + 10, 60, accuracy: 1e-4)
    }

    // MARK: - Glyphs

    func testTextInsideARotatedNodeCarriesTheSubtreeRotation() async throws {
        let node = ViewNode(
            frame: Rect(x: 20, y: 20, width: 160, height: 40),
            text: "ROTATE",
            textStyle: PixelTextStyle(color: .white),
            transform: Transform2D(rotation: .pi / 3)
        )

        let scene = paint(node)
        let glyphs = scene.layers[0].glyphs + scene.layers[0].pixelGlyphs
        XCTAssertFalse(glyphs.isEmpty, "the fixture has to actually produce glyphs")
        for glyph in glyphs {
            XCTAssertEqual(
                Double(glyph.rotationRadians), .pi / 3, accuracy: 1e-5,
                "every cell in the run turns with the node")
        }

        // The run is laid out across the node's own 160-wide frame and turned,
        // so the cells spread along the turned axis rather than horizontally.
        let ys = glyphs.map { Double($0.screenY) }
        XCTAssertGreaterThan(
            (ys.max() ?? 0) - (ys.min() ?? 0), 20,
            "an upright run would put every cell on one baseline")
    }

    func testUnrotatedTextIsUnchanged() async {
        let node = ViewNode(
            frame: Rect(x: 20, y: 20, width: 160, height: 40),
            text: "ROTATE",
            textStyle: PixelTextStyle(color: .white)
        )

        let scene = paint(node)
        let glyphs = scene.layers[0].glyphs + scene.layers[0].pixelGlyphs
        XCTAssertFalse(glyphs.isEmpty)
        XCTAssertTrue(
            glyphs.allSatisfy { $0.rotationRadians == 0 },
            "the axis-aligned path carries no angle at all")
    }

    func testARotatedGlyphCellRastersTurned() async {
        var scene = GPUIScene(clearColor: .black)
        let side = 8
        var pixels = [UInt8]()
        for row in 0..<side {
            for _ in 0..<side {
                // Opaque in the top half of the cell only, so an upright draw
                // and a half-turned one paint different pixels.
                let coverage: UInt8 = row < side / 2 ? 255 : 0
                pixels.append(contentsOf: [coverage, coverage, coverage, coverage])
            }
        }
        scene.glyphAtlas = GlyphAtlasSnapshot(
            width: Int32(side), height: Int32(side), pixels: Data(pixels),
            contentVersion: RenderContentVersion.next(), update: .full)
        scene.addGlyph(
            GlyphPrimitive(
                screenX: 60, screenY: 60, screenW: 80, screenH: 80,
                atlasU0: 0, atlasV0: 0, atlasU1: 1, atlasV1: 1,
                colorR: 1, colorG: 1, colorB: 1, colorA: 1,
                rotationRadians: .pi
            )
        )
        scene.finish()
        let surface = GPUIRawSceneRasterizer.rasterize(scene, size: IntSize(width: 200, height: 200))

        func luminance(_ x: Int, _ y: Int) -> Int {
            Int(surface.pixels[y * Int(surface.bytesPerRow) + x * 4])
        }

        XCTAssertGreaterThan(
            luminance(100, 120), 200, "a half turn puts the cell's inked half at the bottom")
        XCTAssertLessThan(luminance(100, 80), 55, "and leaves the top blank")
    }

    // MARK: - Rotated clipping

    private func rotatedClipTree() -> ViewNode {
        // A container turned 45° with a child that fills its whole frame. The
        // corners of the container's bounding box are outside the turned
        // square, so anything painted there escaped the clip.
        let child = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 100), backgroundColor: marker)
        return ViewNode(
            frame: Rect(x: 50, y: 50, width: 100, height: 100),
            clipsToBounds: true,
            transform: Transform2D(rotation: .pi / 4),
            children: [child]
        )
    }

    func testARotatedClipCompositesThroughARotatedOffscreenPass() async throws {
        let scene = paint(rotatedClipTree())

        let image = try XCTUnwrap(
            scene.layers[0].images.first,
            "a rotated clipsToBounds subtree takes the offscreen route")
        XCTAssertEqual(
            Double(image.rotationRadians), .pi / 4, accuracy: 1e-5,
            "and the composite carries the angle, because the ABI's clip cannot")
        XCTAssertEqual(Double(image.screenW), 100, accuracy: 0.51, "sized from the unrotated frame")
        XCTAssertEqual(Double(image.screenH), 100, accuracy: 0.51)
        XCTAssertTrue(
            scene.layers[0].quads.isEmpty,
            "the child painted into the buffer, not into the outer scene")
    }

    func testARotatedClipDoesNotPaintTheCornersOfItsBoundingBox() async {
        let scene = paint(rotatedClipTree(), size: Size(width: 200, height: 200))
        let surface = GPUIRawSceneRasterizer.rasterize(scene, size: IntSize(width: 200, height: 200))

        func red(_ x: Int, _ y: Int) -> Int {
            Int(surface.pixels[y * Int(surface.bytesPerRow) + x * 4 + 2])
        }

        // The turned square's bounding box spans roughly (29, 29)–(171, 171);
        // its own corners are at the box's edge midpoints. A point 8 px inside
        // the box's top-left corner is well outside the turned square.
        XCTAssertLessThan(
            red(37, 37), 40,
            "the corner of the bounding box is outside the rotated clip and must stay unpainted")
        XCTAssertGreaterThan(red(100, 100), 200, "the middle of the turned square is painted")
        XCTAssertGreaterThan(red(100, 40), 200, "and so is the diamond's top point")
    }

    func testARotatedClipRejectsAPointerInTheCornerOfItsBoundingBox() async throws {
        let frame = Rect(x: 50, y: 50, width: 100, height: 100)
        // The painter re-centres a node's own transform on the node's screen
        // frame before it composes; the raw operator turns about the origin,
        // which is a different clip entirely.
        let centre = Point(x: frame.midX, y: frame.midY)
        let centred = Transform2D.translation(x: -centre.x, y: -centre.y)
            .concatenating(Transform2D(rotation: .pi / 4))
            .concatenating(.translation(x: centre.x, y: centre.y))
        let placement = PaintPlacement.lowering(frame, through: centred)
        let clip = try XCTUnwrap(
            RuntimeClipShape?.none.narrowed(
                to: placement.boundingBox, shape: placement.frame, radii: nil, uniformRadius: 0,
                rotation: placement.rotation, space: .painted))

        XCTAssertTrue(clip.contains(Point(x: 100, y: 100)), "the middle is inside")
        XCTAssertTrue(clip.contains(Point(x: 100, y: 40)), "and so is the diamond's top point")
        XCTAssertFalse(
            clip.contains(Point(x: 37, y: 37)),
            "the corner of the bounding box is not: the interactive region is the visible one")
        XCTAssertFalse(clip.contains(Point(x: 10, y: 10)), "outside the box entirely, as before")
    }

    func testAnUnrotatedClipIsUnchanged() async throws {
        let frame = Rect(x: 10, y: 10, width: 40, height: 40)
        let clip = try XCTUnwrap(
            RuntimeClipShape?.none.narrowed(to: frame, radii: nil, uniformRadius: 0, space: .painted))
        XCTAssertEqual(clip.rotation, 0)
        XCTAssertTrue(clip.contains(Point(x: 12, y: 12)), "every corner of an axis-aligned clip is inside it")
        XCTAssertFalse(clip.contains(Point(x: 9, y: 12)))
    }

    /// The route is an optimisation of correctness, not of pixels: a subtree
    /// that cannot be buffered still has to draw. `offscreenPassBuffer`
    /// returns nil for a non-finite frame, and the node then paints inline
    /// against the bounding-box clip — the documented residual, not a blank.
    func testARotatedClipWithNoChildrenStillPaintsItsOwnDecoration() async throws {
        let node = ViewNode(
            frame: Rect(x: 50, y: 50, width: 100, height: 100),
            backgroundColor: marker,
            clipsToBounds: true,
            transform: Transform2D(rotation: .pi / 4)
        )

        let scene = paint(node)
        let quad = try XCTUnwrap(scene.layers[0].quads.first)
        XCTAssertEqual(
            Double(quad.rotationRadians), .pi / 4, accuracy: 1e-5,
            "a childless rotated clip has nothing to buffer and paints its own turned decoration")
    }
}
