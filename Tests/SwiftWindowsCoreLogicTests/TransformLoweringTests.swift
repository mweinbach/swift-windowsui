import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI

/// WS-19. Two defects with one root: the painter had a transform algebra it
/// never quite believed.
///
/// It lowered every node transform to `Rect.applying(transform:)` — the
/// *bounding box* of the rotated corners — so a `rotationEffect` rendered as
/// an unrotated rectangle up to `√2` too large, even though both backends have
/// honoured `QuadPrimitive.rotationRadians` since the tessellator started
/// emitting diagonal stroke segments. And it composed the node's own transform
/// *before* its ancestors', which put the node's own frame and the frames its
/// descendants inherited in two different spaces.
///
/// These are absolute-placement tests: every expected rect is computed by hand
/// from the tree, not from the other path's answer. Agreement between the
/// scene path and the frame path is necessary but it is not sufficient — both
/// were wrong together.
@MainActor
final class TransformLoweringTests: XCTestCase {

    private let surfaceSize = Size(width: 200, height: 200)
    private let marker = Color(red: 1, green: 0.25, blue: 0.25, alpha: 1)
    private let secondMarker = Color(red: 0.25, green: 0.9, blue: 0.4, alpha: 1)

    private func quads(_ root: ViewNode, size: Size? = nil) -> [QuadPrimitive] {
        ScenePainter.paint(root: root, clearColor: .black, surfaceSize: size ?? surfaceSize)
            .layers[0].quads
    }

    private func quad(_ root: ViewNode, matching color: Color, size: Size? = nil) throws -> QuadPrimitive {
        let matches = quads(root, size: size).filter {
            abs($0.startR - color.red) < 0.01 && abs($0.startG - color.green) < 0.01
                && abs($0.startB - color.blue) < 0.01
        }
        return try XCTUnwrap(matches.first, "no quad painted in the marker colour")
    }

    private func fillRect(_ frame: RenderFrame, matching color: Color) throws -> FillRectCommand {
        let matches: [FillRectCommand] = frame.commands.compactMap { command in
            guard case .fillRect(let fill) = command else { return nil }
            guard abs(fill.color.red - color.red) < 0.01, abs(fill.color.green - color.green) < 0.01,
                abs(fill.color.blue - color.blue) < 0.01
            else { return nil }
            return fill
        }
        return try XCTUnwrap(matches.first, "no fillRect painted in the marker colour")
    }

    private func assertRect(
        _ actual: Rect, _ expected: Rect, accuracy: Double = 0.001, _ message: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(actual.origin.x, expected.origin.x, accuracy: accuracy, "\(message) — x", file: file, line: line)
        XCTAssertEqual(actual.origin.y, expected.origin.y, accuracy: accuracy, "\(message) — y", file: file, line: line)
        XCTAssertEqual(
            actual.size.width, expected.size.width, accuracy: accuracy, "\(message) — width", file: file, line: line)
        XCTAssertEqual(
            actual.size.height, expected.size.height, accuracy: accuracy, "\(message) — height", file: file, line: line)
    }

    private func rect(of quad: QuadPrimitive) -> Rect {
        Rect(x: Double(quad.x), y: Double(quad.y), width: Double(quad.width), height: Double(quad.height))
    }

    // MARK: - Rotation lowering

    /// The core of the workstream. A 100×40 card rotated 45° must stay a
    /// 100×40 quad with an angle on it, not become the 99×99 box its corners
    /// span.
    func testARotatedNodeEmitsItsUnrotatedRectAndAnAngle() async throws {
        let node = ViewNode(
            frame: Rect(x: 50, y: 80, width: 100, height: 40),
            backgroundColor: marker,
            transform: Transform2D(rotation: .pi / 4)
        )

        let painted = try quad(node, matching: marker)
        assertRect(
            rect(of: painted), Rect(x: 50, y: 80, width: 100, height: 40),
            "the rotated card keeps its own size and centre; the angle carries the rest")
        XCTAssertEqual(Double(painted.rotationRadians), .pi / 4, accuracy: 1e-5)
    }

    /// A uniform scale is part of the separable case: the rect scales, the
    /// angle survives.
    func testRotationSurvivesAUniformScale() async throws {
        let node = ViewNode(
            frame: Rect(x: 40, y: 40, width: 60, height: 20),
            backgroundColor: marker,
            transform: Transform2D(scaleX: 2, scaleY: 2, rotation: .pi / 6)
        )

        let painted = try quad(node, matching: marker)
        // Centre (70, 50) is a fixed point of a transform centred on it.
        assertRect(
            rect(of: painted), Rect(x: 10, y: 30, width: 120, height: 40),
            "a rotation with a uniform scale scales the rect and keeps the angle")
        XCTAssertEqual(Double(painted.rotationRadians), .pi / 6, accuracy: 1e-5)
    }

    /// Everything the encoding cannot express falls back to the bounding box —
    /// which is what the painter did for *everything* before this landed, so
    /// the fallback is the historic behaviour verbatim.
    func testShearsAndNonUniformScalesFallBackToTheBoundingBox() async throws {
        func painted(_ transform: Transform2D) throws -> QuadPrimitive {
            try quad(
                ViewNode(
                    frame: Rect(x: 50, y: 50, width: 100, height: 40),
                    backgroundColor: marker,
                    transform: transform
                ), matching: marker)
        }

        let sheared = try painted(Transform2D(skewX: 0.4))
        XCTAssertEqual(sheared.rotationRadians, 0, "a shear is not a rotation")
        XCTAssertGreaterThan(
            Double(sheared.width), 100.1, "a shear widens the box it degrades to")

        let stretched = try painted(Transform2D(scaleX: 2, scaleY: 1))
        XCTAssertEqual(stretched.rotationRadians, 0, "a non-uniform scale is not a rotation")
        assertRect(
            rect(of: stretched), Rect(x: 0, y: 50, width: 200, height: 40),
            "a non-uniform scale keeps the historic bounding box")
    }

    /// Why `mirror` is missing from the list above: it is in the list, it just
    /// has to survive being composed before it can get here. It does now —
    /// `Transform2D`'s decomposition carries the reflection as a negative
    /// scale (R-MISC; `TransformReflectionTests` owns that fix), where it used
    /// to come back from the first `concatenating` as a half turn, which the
    /// painter *can* encode and would happily have lowered as a rotation.
    /// A reflection that reaches the painter still degrades to its bounding
    /// box: the scene contract has no reflection on its primitives.
    func testAReflectionReachesThePainterAsOneAndFallsBackToTheBoundingBox() async throws {
        let mirror = Transform2D(scaleX: -1, scaleY: 1)
        XCTAssertLessThan(
            mirror.matrix.a * mirror.matrix.d - mirror.matrix.b * mirror.matrix.c, 0,
            "the matrix a mirror builds is a reflection")

        let composed = Transform2D.identity.concatenating(mirror)
        XCTAssertLessThan(
            composed.matrix.a * composed.matrix.d - composed.matrix.b * composed.matrix.c, 0,
            "and composing it may not quietly turn it into a rotation")

        // The painter applies a node's transform about the node's own centre,
        // so this mirror is AABB-invariant: the rect is the discriminator's
        // control, and the *angle* is the discriminator. A half turn is a
        // similarity, so the degenerate form was lowered as `rotation = π` and
        // the card drew upside down.
        let mirrored = try painted(Transform2D(scaleX: -1, scaleY: 1))
        XCTAssertEqual(mirrored.rotationRadians, 0, "a mirror is not a rotation")
        assertRect(
            rect(of: mirrored), Rect(x: 50, y: 50, width: 100, height: 40),
            "a mirror about the node's own centre leaves its box alone")
    }

    private func painted(_ transform: Transform2D) throws -> QuadPrimitive {
        try quad(
            ViewNode(
                frame: Rect(x: 50, y: 50, width: 100, height: 40),
                backgroundColor: marker,
                transform: transform
            ), matching: marker)
    }

    /// Node decoration is a *ring* of quads laid out around the frame, not one
    /// quad, so lowering the fill alone would have left the border square
    /// around a rotated card. Each segment is turned about the node's centre
    /// and carries the same angle.
    func testTheBorderRingRotatesWithTheNodeItSurrounds() async throws {
        let child = ViewNode(frame: Rect(x: 10, y: 10, width: 20, height: 20))
        let node = ViewNode(
            frame: Rect(x: 60, y: 60, width: 80, height: 40),
            borderColor: marker,
            borderWidth: 4,
            transform: Transform2D(rotation: .pi / 3),
            children: [child]
        )

        let segments = quads(node).filter {
            abs($0.startR - marker.red) < 0.01 && abs($0.startG - marker.green) < 0.01
        }
        XCTAssertFalse(segments.isEmpty, "a bordered container paints its ring after its children")
        for segment in segments {
            XCTAssertEqual(
                Double(segment.rotationRadians), .pi / 3, accuracy: 1e-5,
                "every ring segment carries the node's angle")
        }
        // The ring is centred on the node's centre (100, 80) whatever the
        // angle: rotation is rigid and the segments are symmetric about it.
        let minX = segments.map { Double($0.x) }.min() ?? 0
        let maxX = segments.map { Double($0.x) + Double($0.width) }.max() ?? 0
        XCTAssertEqual((minX + maxX) / 2, 100, accuracy: 0.5, "the ring stays centred on the node")

        // And one segment pinned absolutely: the angle and the symmetric
        // centre both survive a `placement.rotating` that moves nothing, so
        // neither can tell a turned ring from an axis-aligned one. The top
        // edge is laid out at (60, 60, 80, 4), centre (100, 62); the 60°
        // turn about the node's centre (100, 80) maps its offset (0, -18)
        // to (9√3, -9), so the placed origin is (60 + 9√3, 69).
        let edges = segments.filter { abs(Double($0.width) - 80) < 0.01 }
        XCTAssertEqual(edges.count, 2, "an 80-wide ring has exactly a top and a bottom edge")
        let topEdge = try XCTUnwrap(edges.min(by: { $0.y < $1.y }), "the ring must contain its top edge")
        XCTAssertEqual(
            Double(topEdge.x), 60 + 9 * 3.0.squareRoot(), accuracy: 1e-3,
            "the top edge's placed origin must match the hand-computed turn about (100, 80)")
        XCTAssertEqual(
            Double(topEdge.y), 69, accuracy: 1e-3,
            "the top edge's placed origin must match the hand-computed turn about (100, 80)")
    }

    /// `place` turns a rect's centre about the node's centre; `footprint` adds
    /// the rect's own turn about *its* centre and nothing more. Turning the
    /// already-placed rect about the node's centre a second time would rotate
    /// it twice — invisible in the common case where the footprint is only fed
    /// to a clip predicate against a clip that accepts everything, and wrong
    /// the moment a rotated node is near a clip edge.
    func testAPlacedRectsFootprintIsTurnedExactlyOnce() async {
        // A quarter-turn about (100, 100): the rect at (150, 90, 20, 40)
        // has centre (160, 110), which lands on (90, 160).
        let placement = PaintPlacement(
            frame: Rect(x: 50, y: 50, width: 100, height: 100),
            rotation: .pi / 2,
            boundingBox: Rect(x: 50, y: 50, width: 100, height: 100))
        let source = Rect(x: 150, y: 90, width: 20, height: 40)

        let placed = placement.place(source)
        assertRect(
            placed, Rect(x: 80, y: 140, width: 20, height: 40),
            "the centre turns, the size does not — the angle on the primitive supplies the rest")

        assertRect(
            placement.footprint(of: source), Rect(x: 70, y: 150, width: 40, height: 20),
            "a quarter-turn swaps the extents about the placed centre (90, 160)")
    }

    // MARK: - Rotation-aware bounds in the scene contract

    /// A rotated quad's footprint is the box of the *turned* rect. Comparing
    /// the untur ned one against the clip dropped primitives whose bodies were
    /// inside the clip all along.
    func testARotatedQuadIsAcceptedOnItsRotatedFootprint() async {
        // Body spans y ∈ [0, 20] unrotated; turned a quarter-turn about its
        // centre (50, 10) it spans y ∈ [-40, 60] and x ∈ [40, 60].
        func quad(rotation: Float) -> QuadPrimitive {
            QuadPrimitive(
                x: 0, y: 0, width: 100, height: 20,
                startR: 1, startG: 0, startB: 0, startA: 1,
                endR: 1, endG: 0, endB: 0, endA: 1,
                clipX: 45, clipY: -35, clipWidth: 12, clipHeight: 12,
                rotationRadians: rotation)
        }

        var unrotatedScene = GPUIScene(clearColor: .clear)
        unrotatedScene.addQuad(quad(rotation: 0), toLayer: 0)
        XCTAssertEqual(
            unrotatedScene.layers[0].quads.count, 0,
            "the clip misses the axis-aligned body entirely, so the contract rejects it")

        var rotatedScene = GPUIScene(clearColor: .clear)
        rotatedScene.addQuad(quad(rotation: .pi / 2), toLayer: 0)
        XCTAssertEqual(
            rotatedScene.layers[0].quads.count, 1,
            "the same clip catches the rotated body, so the contract must accept it")
    }

    // MARK: - Composition order

    /// Hand-computed placement, scene path.
    ///
    /// `ancestor` translates by (100, 60); `child` scales ×2 about its own
    /// screen centre, which the translation has already moved to (140, 100).
    /// The child's own frame therefore lands at (100, 60, 80, 80) and its
    /// grandchild — layout rect (30, 30, 10, 10) — at (120, 80, 20, 20).
    ///
    /// Composing node-before-ancestor put the grandchild at (20, 20, 20, 20):
    /// scaled first, then translated, so the scale never saw the ancestor's
    /// 100 points and the child and its own content disagreed by exactly that.
    func testATranslatedAncestorPlacesAScaledDescendantsContent() async throws {
        let root = Self.translateThenScaleTree(marker: marker, childMarker: secondMarker)

        let childQuad = try quad(root, matching: secondMarker)
        assertRect(rect(of: childQuad), Rect(x: 100, y: 60, width: 80, height: 80), "the scaled child's own frame")

        let grandchildQuad = try quad(root, matching: marker)
        assertRect(
            rect(of: grandchildQuad), Rect(x: 120, y: 80, width: 20, height: 20),
            "the grandchild inherits the ancestor translation *and* the child scale, in that order")
    }

    /// The same placement through the frame path, which accumulates the
    /// transform in `ViewNode.accumulatedPaintGeometry` rather than in the
    /// painter. Both had the same inverted order, so agreement alone would
    /// have kept them both wrong.
    func testTheFramePathPlacesTheSameScaledDescendantContent() async throws {
        let runtime = RetainedViewRuntime(root: Self.translateThenScaleTree(marker: marker, childMarker: secondMarker))
        let frame = runtime.renderFrame()

        assertRect(
            try fillRect(frame, matching: secondMarker).rect, Rect(x: 100, y: 60, width: 80, height: 80),
            "the frame path places the scaled child where the painter does")
        assertRect(
            try fillRect(frame, matching: marker).rect, Rect(x: 120, y: 80, width: 20, height: 20),
            "and its grandchild too")
    }

    /// Hand-computed placement for translate + rotate, scene path.
    ///
    /// `ancestor` translates by (60, 40); `child` (layout rect (50, 50,
    /// 120, 60)) turns a quarter-turn about its screen centre (170, 120). The
    /// child's quad is its unrotated 120×60 rect at (110, 90) with the angle
    /// on it; the grandchild's layout rect (60, 55, 20, 10) has centre
    /// (70, 60) → (130, 100) after the translation → (190, 80) after the
    /// quarter-turn, so its quad is 20×10 at (180, 75), also turned.
    func testATranslatedAncestorPlacesARotatedDescendantsContent() async throws {
        let root = Self.translateThenRotateTree(marker: marker, childMarker: secondMarker)

        let childQuad = try quad(root, matching: secondMarker)
        assertRect(rect(of: childQuad), Rect(x: 110, y: 90, width: 120, height: 60), "the rotated child's own frame")
        XCTAssertEqual(Double(childQuad.rotationRadians), .pi / 2, accuracy: 1e-5)

        let grandchildQuad = try quad(root, matching: marker)
        assertRect(
            rect(of: grandchildQuad), Rect(x: 180, y: 75, width: 20, height: 10),
            "the grandchild is carried around the child's centre by the child's rotation")
        XCTAssertEqual(Double(grandchildQuad.rotationRadians), .pi / 2, accuracy: 1e-5)
    }

    /// The frame path has no rotation encoding at all — `FillRectCommand`
    /// carries a rect and nothing else — so it degrades to the axis-aligned
    /// box of the same rotated geometry. That is a documented degradation, and
    /// the box has to be the box of the *right* rectangle.
    func testTheFramePathDegradesTheSameRotatedPlacementToItsBoundingBox() async throws {
        let runtime = RetainedViewRuntime(root: Self.translateThenRotateTree(marker: marker, childMarker: secondMarker))
        let frame = runtime.renderFrame()

        assertRect(
            try fillRect(frame, matching: secondMarker).rect, Rect(x: 140, y: 60, width: 60, height: 120),
            "a quarter-turn of a 120×60 rect about (170, 120) spans 60×120")
        assertRect(
            try fillRect(frame, matching: marker).rect, Rect(x: 185, y: 70, width: 10, height: 20),
            "and the grandchild's box is the box of the rotated grandchild, not of an unrotated one")
    }

    /// A pointer is inverse-mapped through the same accumulated transform, so
    /// the composition order decides what is clickable as well as what is
    /// visible. Nothing the user can see may be dead to the pointer.
    func testThePointerFindsTheScaledDescendantWhereItIsPainted() async {
        var activations = 0
        let root = Self.translateThenScaleTree(marker: marker, childMarker: secondMarker, hitTestable: true)
        let grandchild = root.children[0].children[0].children[0]
        grandchild.onActivate = { activations += 1 }
        let runtime = RetainedViewRuntime(root: root)

        // Centre of the painted grandchild rect (120, 80, 20, 20).
        runtime.pointerDown(at: Point(x: 130, y: 90))
        runtime.pointerUp(at: Point(x: 130, y: 90))
        XCTAssertEqual(activations, 1, "the pointer hits the grandchild where it is painted")

        // Where the inverted composition used to put it.
        runtime.pointerDown(at: Point(x: 30, y: 30))
        runtime.pointerUp(at: Point(x: 30, y: 30))
        XCTAssertEqual(activations, 1, "and nowhere else")
    }

    // MARK: - Cache keys

    /// `bounds` is an axis-aligned box, and a whole class of transforms leaves
    /// it unchanged: a mirror, a half-turn, a quarter-turn of a square. A node
    /// centred in such an ancestor keeps its box while its geometry turns, so
    /// keying replay on the box alone re-emitted last frame's primitives.
    func testAnAABBInvariantAncestorTransformInvalidatesReplay() async throws {
        let child = ViewNode(
            frame: Rect(x: 20, y: 20, width: 60, height: 60),
            backgroundColor: marker,
            cornerRadii: RetainedCornerRadii(topLeft: 20, topRight: 0, bottomRight: 0, bottomLeft: 0)
        )
        let ancestor = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 100), children: [child])
        let runtime = RetainedViewRuntime(
            root: ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 100), children: [ancestor]))

        let first = runtime.renderScene()
        let before = try XCTUnwrap(first.layers[0].quads.first { abs($0.startR - marker.red) < 0.01 })
        XCTAssertEqual(before.rotationRadians, 0)

        // A half-turn of a square container: the child is concentric with it,
        // so its bounding box — and every other field of the old key — is
        // unchanged.
        ancestor.transform = Transform2D(rotation: .pi)
        let second = runtime.renderScene()
        let after = try XCTUnwrap(second.layers[0].quads.first { abs($0.startR - marker.red) < 0.01 })
        assertRect(
            rect(of: after), rect(of: before),
            "the half-turn is exactly the case the bounding box cannot see")
        XCTAssertEqual(
            Double(after.rotationRadians), .pi, accuracy: 1e-5,
            "the accumulated transform is part of the replay key, so the turned child repaints")
    }

    // MARK: - The frame path resuming and drawing in the painter's space

    /// The canvas closure draws in a space `fillRect.size` wide, so its origin
    /// is the painted origin — inset by the border, and with the accumulated
    /// transform already in it. The frame path passed `absoluteOrigin`, the
    /// *layout* origin, which has neither: a bordered canvas drew its content
    /// `borderWidth` away from where the scene path put it.
    func testTheFramePathDrawsACanvasFromItsPaintedOrigin() async throws {
        func makeTree() -> ViewNode {
            ViewNode(
                frame: Rect(x: 30, y: 20, width: 100, height: 60),
                borderColor: secondMarker,
                borderWidth: 6,
                canvasDraw: { context, _ in
                    context.fill(Rect(x: 0, y: 0, width: 10, height: 10), with: .color(self.marker))
                }
            )
        }

        let sceneQuad = try quad(makeTree(), matching: marker)
        assertRect(
            rect(of: sceneQuad), Rect(x: 36, y: 26, width: 10, height: 10),
            "the painter draws the canvas from the border-inset painted origin")

        let frameFill = try fillRect(RetainedViewRuntime(root: makeTree()).renderFrame(), matching: marker)
        assertRect(
            frameFill.rect, Rect(x: 36, y: 26, width: 10, height: 10),
            "so the frame path has to draw it from the same origin")
    }

    /// Resuming a deferred subtree restores the state it was deferred from —
    /// all of it. The frame path dropped the inherited blend mode while
    /// `ScenePainter.appendDeferredDraws` passed it, so the same overlay
    /// composited two different ways depending on which renderer was live.
    func testADeferredSubtreeResumesWithItsInheritedBlendMode() async throws {
        func makeTree() -> ViewNode {
            let overlay = ViewNode(
                frame: Rect(x: 10, y: 10, width: 40, height: 20),
                backgroundColor: marker,
                paintsInDeferredPhase: true
            )
            return ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 100),
                blendMode: .multiply,
                children: [overlay])
        }

        let sceneQuad = try XCTUnwrap(
            RetainedViewRuntime(root: makeTree()).renderScene().layers[0].quads
                .first { abs($0.startR - marker.red) < 0.01 })
        XCTAssertEqual(
            sceneQuad.blendMode, Float(BlendMode.multiply.rawValue),
            "the painter carries the inherited blend mode into the deferred resume")

        let frameFill = try fillRect(RetainedViewRuntime(root: makeTree()).renderFrame(), matching: marker)
        XCTAssertEqual(
            frameFill.blendMode, .multiply,
            "and so must the frame path — it is the same tree either way")
    }

    // MARK: - Fixtures

    private static func translateThenScaleTree(
        marker: Color, childMarker: Color, hitTestable: Bool = false
    ) -> ViewNode {
        let grandchild = ViewNode(
            frame: Rect(x: 10, y: 10, width: 10, height: 10),
            backgroundColor: marker,
            isHitTestVisible: hitTestable
        )
        let child = ViewNode(
            frame: Rect(x: 20, y: 20, width: 40, height: 40),
            backgroundColor: childMarker,
            transform: Transform2D(scaleX: 2, scaleY: 2),
            isHitTestVisible: false,
            children: [grandchild]
        )
        let ancestor = ViewNode(
            frame: Rect(x: 0, y: 0, width: 200, height: 200),
            transform: Transform2D(translationX: 100, translationY: 60),
            isHitTestVisible: false,
            children: [child]
        )
        return ViewNode(
            frame: Rect(x: 0, y: 0, width: 200, height: 200),
            isHitTestVisible: false,
            children: [ancestor])
    }

    private static func translateThenRotateTree(marker: Color, childMarker: Color) -> ViewNode {
        let grandchild = ViewNode(
            frame: Rect(x: 10, y: 5, width: 20, height: 10),
            backgroundColor: marker
        )
        let child = ViewNode(
            frame: Rect(x: 50, y: 50, width: 120, height: 60),
            backgroundColor: childMarker,
            transform: Transform2D(rotation: .pi / 2),
            children: [grandchild]
        )
        let ancestor = ViewNode(
            frame: Rect(x: 0, y: 0, width: 200, height: 200),
            transform: Transform2D(translationX: 60, translationY: 40),
            children: [child]
        )
        return ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 200), children: [ancestor])
    }
}
