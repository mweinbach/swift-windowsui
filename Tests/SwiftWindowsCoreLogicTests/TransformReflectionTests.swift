import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// R-MISC. A reflection used to stop being a reflection the first time it
/// composed.
///
/// `Transform2D` is stored decomposed, and every composition (`concatenating`,
/// `inverse`, and the centred transform the runtime builds for *every*
/// transformed node) goes out to the matrix and back through
/// `init(fromMatrix:)`. That read-back took non-negative scales, which cannot
/// carry a negative determinant, so `scaleEffect(x: -1)` came back as a half
/// turn: content placed upside down and backwards instead of mirrored, a
/// pointer inverse-mapped through the wrong matrix, and an interpolation that
/// walked through a rotation nobody asked for.
///
/// These tests are absolute: every expected value is computed by hand from the
/// matrix or the tree, never from the other path's answer.
@MainActor
final class TransformReflectionTests: XCTestCase {

    private let marker = Color(red: 1, green: 0.25, blue: 0.25, alpha: 1)
    private let childMarker = Color(red: 0.25, green: 0.9, blue: 0.4, alpha: 1)

    private func assertMatrix(
        _ actual: AffineMatrix, _ expected: AffineMatrix, _ message: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(actual.a, expected.a, accuracy: 1e-9, "\(message) — a", file: file, line: line)
        XCTAssertEqual(actual.b, expected.b, accuracy: 1e-9, "\(message) — b", file: file, line: line)
        XCTAssertEqual(actual.c, expected.c, accuracy: 1e-9, "\(message) — c", file: file, line: line)
        XCTAssertEqual(actual.d, expected.d, accuracy: 1e-9, "\(message) — d", file: file, line: line)
        XCTAssertEqual(actual.tx, expected.tx, accuracy: 1e-9, "\(message) — tx", file: file, line: line)
        XCTAssertEqual(actual.ty, expected.ty, accuracy: 1e-9, "\(message) — ty", file: file, line: line)
    }

    private func assertRect(
        _ actual: Rect, _ expected: Rect, _ message: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(actual.origin.x, expected.origin.x, accuracy: 0.001, "\(message) — x", file: file, line: line)
        XCTAssertEqual(actual.origin.y, expected.origin.y, accuracy: 0.001, "\(message) — y", file: file, line: line)
        XCTAssertEqual(
            actual.size.width, expected.size.width, accuracy: 0.001, "\(message) — width", file: file, line: line)
        XCTAssertEqual(
            actual.size.height, expected.size.height, accuracy: 0.001, "\(message) — height", file: file, line: line)
    }

    // MARK: - The decomposition itself

    /// The property the whole type rests on: the decomposition is the inverse
    /// of the composition. A reflection is the case that broke it — the mirror
    /// `(-1, 0, 0, 1)` came back as the half turn `(-1, 0, 0, -1)`.
    func testTheDecompositionRoundTripsAHorizontalMirror() async {
        let mirror = AffineMatrix(a: -1, b: 0, c: 0, d: 1, tx: 0, ty: 0)
        let decomposed = Transform2D(fromMatrix: mirror)

        XCTAssertEqual(decomposed.scaleX, -1, "a horizontal mirror is a negative scaleX")
        XCTAssertEqual(decomposed.scaleY, 1)
        XCTAssertEqual(decomposed.rotation, 0, "and no rotation at all — nothing turned")
        XCTAssertEqual(decomposed.skewX, 0)
        assertMatrix(decomposed.matrix, mirror, "the mirror survives the round trip")
    }

    /// The other branch. Both reflections are representable; which scale
    /// carries the sign is decided by which reading is the smaller turn, so a
    /// vertical mirror lands on `scaleY` and still needs no rotation.
    func testTheDecompositionRoundTripsAVerticalMirror() async {
        let mirror = AffineMatrix(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 0)
        let decomposed = Transform2D(fromMatrix: mirror)

        XCTAssertEqual(decomposed.scaleX, 1)
        XCTAssertEqual(decomposed.scaleY, -1, "a vertical mirror is a negative scaleY")
        XCTAssertEqual(decomposed.rotation, 0)
        assertMatrix(decomposed.matrix, mirror, "and it survives the round trip too")
    }

    /// The half turn must stay a half turn: it has a *positive* determinant and
    /// is not a reflection, so nothing about it may change.
    func testAHalfTurnIsStillAHalfTurnAndNotAPairOfMirrors() async {
        let halfTurn = Transform2D(rotation: .pi)
        let roundTripped = Transform2D(fromMatrix: halfTurn.matrix)

        XCTAssertEqual(roundTripped.rotation, .pi, accuracy: 1e-12, "a rotation stays a rotation")
        XCTAssertGreaterThan(roundTripped.scaleX, 0, "with both scales positive")
        XCTAssertGreaterThan(roundTripped.scaleY, 0)
        assertMatrix(roundTripped.matrix, halfTurn.matrix, "the half turn round trips unchanged")
    }

    /// A reflection composed with a rotation and a non-uniform scale — nothing
    /// separable, nothing axis-aligned. The round trip still has to be exact,
    /// because composition is where it is used.
    func testTheDecompositionRoundTripsAReflectionUnderRotationAndScale() async {
        let composed = Transform2D(scaleX: 3, scaleY: 2, rotation: .pi / 5)
            .concatenating(.scale(x: -1, y: 1))
        let expected = Transform2D(scaleX: 3, scaleY: 2, rotation: .pi / 5).matrix
            .concatenating(AffineMatrix(a: -1, b: 0, c: 0, d: 1, tx: 0, ty: 0))

        XCTAssertLessThan(
            composed.matrix.a * composed.matrix.d - composed.matrix.b * composed.matrix.c, 0,
            "the composition of a reflection with anything orientation-preserving still reflects")
        assertMatrix(composed.matrix, expected, "composing must not rewrite the geometry")
    }

    /// The quieter half of the same defect. `scaleY` was read as the *norm* of
    /// the derotated second row, which is `scaleY / cos(skewX)` — so a shear
    /// grew by a factor of `sec(skewX)` every single time it composed. Two
    /// compositions used to grow a 0.4 shear by ~18%.
    func testAShearDoesNotGrowEachTimeItComposes() async {
        let sheared = Transform2D(skewX: 0.4)
        var composed = sheared
        for _ in 0..<3 {
            composed = composed.concatenating(Transform2D.identity)
        }

        assertMatrix(composed.matrix, sheared.matrix, "composing with the identity must change nothing")
        XCTAssertEqual(composed.scaleY, 1, accuracy: 1e-9, "the shear's scale is 1, not sec(0.4)")
        XCTAssertEqual(composed.skewX, 0.4, accuracy: 1e-9)
    }

    /// Inversion goes through the same read-back, and the inverse of a mirror
    /// is that mirror. Hit testing is inverse-mapped, so this is the pointer's
    /// half of the fix.
    func testTheInverseOfAMirrorIsThatMirror() async {
        let mirror = Transform2D.scale(x: -1, y: 1)
        let inverse = mirror.inverse()

        XCTAssertEqual(inverse.scaleX, -1)
        XCTAssertEqual(inverse.scaleY, 1)
        assertMatrix(
            inverse.matrix, mirror.matrix, "a mirror is its own inverse — it may not come back as a half turn")

        let point = Point(x: 30, y: 12).applying(mirror).applying(inverse)
        XCTAssertEqual(point.x, 30, accuracy: 1e-9)
        XCTAssertEqual(point.y, 12, accuracy: 1e-9)
    }

    /// The authoring surface: `.scaleEffect(x: -1)` composes onto the node's
    /// transform, so it used to reach the runtime already degenerate.
    func testScaleEffectWithANegativeAxisReachesTheNodeAsAMirror() async {
        let node = makeReflectionNode(Text("MIRROR").scaleEffect(x: -1, y: 1))

        XCTAssertEqual(node.transform.scaleX, -1, "the authored mirror is the stored mirror")
        XCTAssertEqual(node.transform.scaleY, 1)
        XCTAssertEqual(node.transform.rotation, 0, "and no half turn came along with it")
    }

    /// Interpolation is component-wise, so which component carries the
    /// reflection decides what an animation to a mirrored state looks like: a
    /// scale that passes through zero (a flip), not a rotation through a
    /// quarter turn (a tumble).
    func testInterpolatingToAMirrorFlipsRatherThanTumbles() async {
        let mirror = Transform2D.identity.concatenating(.scale(x: -1, y: 1))
        let half = Transform2D.identity.interpolated(to: mirror, progress: 0.5)

        XCTAssertEqual(half.rotation, 0, "nothing rotates on the way to a mirror")
        XCTAssertEqual(half.scaleX, 0, accuracy: 1e-12, "halfway through a flip the view is edge-on")
        XCTAssertEqual(half.scaleY, 1, "and the other axis never moves")
    }

    // MARK: - What the painter does with one

    /// The scene contract has a rotation on its primitives and no reflection,
    /// so `PaintPlacement` degrades a mirror to its axis-aligned box — the
    /// historic behaviour for everything it cannot encode. That rejection used
    /// to be unreachable (the mirror had already become a half turn, which
    /// *is* encodable); it is reachable now, and it must still reject.
    func testPaintPlacementDegradesAReflectionToItsBoundingBox() async {
        let localFrame = Rect(x: 50, y: 50, width: 100, height: 40)
        let placement = PaintPlacement.lowering(localFrame, through: .scale(x: -1, y: 1))

        XCTAssertEqual(placement.rotation, 0, "a mirror is not a rotation and must not be lowered as one")
        XCTAssertFalse(placement.isRotated)
        assertRect(
            placement.boundingBox, Rect(x: -150, y: 50, width: 100, height: 40),
            "the box is the box of the four mirrored corners")
        assertRect(placement.frame, placement.boundingBox, "and an unrotated placement paints into its box")
    }

    /// End to end on the scene path. A mirrored container reflects its
    /// children *across* it — the child's y is untouched. The half turn the
    /// decomposition used to produce moved the child in y as well, by twice its
    /// offset from the centre, which is how the defect showed on screen.
    func testAMirroredContainerPlacesItsChildAcrossItAndNotUpsideDown() async throws {
        let scene = ScenePainter.paint(
            root: Self.mirroredTree(marker: marker, childMarker: childMarker),
            clearColor: .black,
            surfaceSize: Size(width: 200, height: 200))
        let quads = scene.layers[0].quads

        let container = try XCTUnwrap(quads.first { abs($0.startG - childMarker.green) < 0.01 })
        assertRect(
            Rect(
                x: Double(container.x), y: Double(container.y),
                width: Double(container.width), height: Double(container.height)),
            Rect(x: 50, y: 50, width: 100, height: 60),
            "a mirror about the container's own centre leaves the container where it is")
        XCTAssertEqual(container.rotationRadians, 0, "and it is emphatically not turned")

        let child = try XCTUnwrap(quads.first { abs($0.startR - marker.red) < 0.01 })
        assertRect(
            Rect(
                x: Double(child.x), y: Double(child.y),
                width: Double(child.width), height: Double(child.height)),
            Rect(x: 120, y: 60, width: 20, height: 20),
            "the child at (60, 60) reflects about x = 100 to (120, 60) — same y")
    }

    /// The frame path accumulates the transform itself
    /// (`ViewNode.accumulatedPaintGeometry`), so it has to reach the same
    /// place. Both were wrong together before this.
    func testTheFramePathMirrorsTheSameChild() async throws {
        let runtime = RetainedViewRuntime(root: Self.mirroredTree(marker: marker, childMarker: childMarker))
        let frame = runtime.renderFrame()
        let fills: [FillRectCommand] = frame.commands.compactMap {
            guard case .fillRect(let fill) = $0 else { return nil }
            return fill
        }

        let child = try XCTUnwrap(fills.first { abs($0.color.red - marker.red) < 0.01 })
        assertRect(
            child.rect, Rect(x: 120, y: 60, width: 20, height: 20),
            "the frame path mirrors the child where the painter does")
    }

    /// A pointer is inverse-mapped through the accumulated transform. Nothing
    /// the user can see may be dead to the pointer — including a mirrored
    /// child, which used to be clickable at the half turn's position instead.
    func testThePointerFindsTheMirroredChildWhereItIsPainted() async {
        var activations = 0
        let root = Self.mirroredTree(marker: marker, childMarker: childMarker, hitTestable: true)
        root.children[0].children[0].onActivate = { activations += 1 }
        let runtime = RetainedViewRuntime(root: root)

        // Centre of the painted child rect (120, 60, 20, 20).
        runtime.pointerDown(at: Point(x: 130, y: 70))
        runtime.pointerUp(at: Point(x: 130, y: 70))
        XCTAssertEqual(activations, 1, "the pointer hits the mirrored child where it is painted")

        // Its unmirrored layout position, and where the half turn used to put
        // it — both must now be dead.
        runtime.pointerDown(at: Point(x: 70, y: 70))
        runtime.pointerUp(at: Point(x: 70, y: 70))
        runtime.pointerDown(at: Point(x: 130, y: 90))
        runtime.pointerUp(at: Point(x: 130, y: 90))
        XCTAssertEqual(activations, 1, "and nowhere else")
    }

    // MARK: - Fixtures

    /// Container (50, 50, 100, 60), centre (100, 80), mirrored about its own
    /// vertical axis. Child laid out at absolute (60, 60, 20, 20), centre
    /// (70, 70) → reflected centre (130, 70).
    private static func mirroredTree(marker: Color, childMarker: Color, hitTestable: Bool = false) -> ViewNode {
        let child = ViewNode(
            frame: Rect(x: 10, y: 10, width: 20, height: 20),
            backgroundColor: marker,
            isHitTestVisible: hitTestable
        )
        let container = ViewNode(
            frame: Rect(x: 50, y: 50, width: 100, height: 60),
            backgroundColor: childMarker,
            transform: .scale(x: -1, y: 1),
            isHitTestVisible: false,
            children: [child]
        )
        return ViewNode(
            frame: Rect(x: 0, y: 0, width: 200, height: 200),
            isHitTestVisible: false,
            children: [container])
    }
}

@MainActor
private func makeReflectionNode<V: View>(_ view: V, size: Size = Size(width: 200, height: 200)) -> ViewNode {
    let runtime = RetainedViewRuntime(root: ViewNode())
    let context = ViewBuildContext(canvasSizeProvider: { size }, invalidateHandler: {})
    return view.makeComponent(context: context).makeNode(runtime: runtime)
}
