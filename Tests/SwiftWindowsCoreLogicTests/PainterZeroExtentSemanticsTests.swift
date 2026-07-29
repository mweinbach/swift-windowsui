import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI

/// What a zero-extent node means, pinned on both paint traversals.
///
/// The rule is macOS SwiftUI's: a frame boundary does not clip, so a container
/// collapsed to `0 × 0` still paints its overflowing children (`.clipped()` is
/// what hides them), while the collapsed node itself paints none of its own
/// decoration — an outset shadow or outline around a zero-extent frame would
/// otherwise draw a small square where the app asked for nothing.
///
/// The part that is easy to lose is the other half: a collapsed node is still
/// *culled*. `Rect.intersected` reports "no overlap" for every degenerate rect
/// wherever it sits, so the cull cannot simply run the primitive test — but
/// skipping the cull for zero-extent nodes (which is what gating it on a
/// paintable extent did) leaves a collapsed row parked far outside the clip
/// traversing its whole subtree every frame.
@MainActor
final class PainterZeroExtentSemanticsTests: XCTestCase {

    private let red = Color(red: 1, green: 0, blue: 0, alpha: 1)

    // MARK: - Scene path

    func testZeroExtentContainerInsideTheClipPaintsItsOverflowingChildren() async {
        let child = ViewNode(frame: Rect(x: 0, y: 0, width: 40, height: 40), backgroundColor: red)
        let collapsed = ViewNode(frame: Rect(x: 10, y: 10, width: 0, height: 0), children: [child])
        let root = ViewNode(
            frame: Rect(x: 0, y: 0, width: 200, height: 200),
            clipsToBounds: true,
            children: [collapsed]
        )

        let scene = ScenePainter.paint(
            root: root, clearColor: .black, surfaceSize: Size(width: 200, height: 200))

        XCTAssertEqual(
            scene.layers[0].quads.count, 1,
            "SwiftUI does not clip at a frame boundary: `.frame(height: 0)` without `.clipped()` "
                + "overflows and the children still render")
        XCTAssertEqual(scene.layers[0].quads[0].x, 10, accuracy: 0.001)
        XCTAssertEqual(scene.layers[0].quads[0].width, 40, accuracy: 0.001)
    }

    func testZeroExtentContainerOutsideTheClipPrunesItsSubtree() async {
        // The child's own frame lands back inside the clip, so this only passes
        // if the collapsed parent was culled — the cull's standing approximation
        // is that a subtree lives inside its parent's footprint, and a
        // degenerate parent is not exempt from it.
        let child = ViewNode(frame: Rect(x: -450, y: 0, width: 40, height: 40), backgroundColor: red)
        let collapsed = ViewNode(frame: Rect(x: 500, y: 20, width: 0, height: 0), children: [child])
        let root = ViewNode(
            frame: Rect(x: 0, y: 0, width: 100, height: 100),
            clipsToBounds: true,
            children: [collapsed]
        )

        let scene = ScenePainter.paint(
            root: root, clearColor: .black, surfaceSize: Size(width: 100, height: 100))

        XCTAssertTrue(
            scene.layers[0].quads.isEmpty,
            "a zero-extent node outside the clip must prune like any other node; gating the "
                + "occlusion cull on a paintable extent made it traverse its subtree every frame")
    }

    func testZeroExtentClippingContainerDropsItsChildren() async {
        let child = ViewNode(frame: Rect(x: 0, y: 0, width: 40, height: 40), backgroundColor: red)
        let collapsed = ViewNode(
            frame: Rect(x: 10, y: 10, width: 0, height: 0),
            clipsToBounds: true,
            children: [child]
        )
        let root = ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 200), children: [collapsed])

        let scene = ScenePainter.paint(
            root: root, clearColor: .black, surfaceSize: Size(width: 200, height: 200))

        XCTAssertTrue(
            scene.layers[0].quads.isEmpty,
            "`.clipped()` is what collapses the subtree; nothing survives an empty clip")
    }

    // MARK: - Frame path agreement

    func testFramePathPaintsTheOverflowingChildrenOfAZeroExtentContainer() async {
        let child = ViewNode(
            frame: Rect(x: 0, y: 0, width: 40, height: 40),
            backgroundColor: Color(red: 1, green: 1, blue: 1, alpha: 1)
        )
        let collapsed = ViewNode(frame: Rect(x: 10, y: 10, width: 0, height: 0), children: [child])
        let root = ViewNode(
            frame: Rect(x: 0, y: 0, width: 200, height: 200),
            clipsToBounds: true,
            isHitTestVisible: false,
            children: [collapsed]
        )

        let frame = RetainedViewRuntime(root: root).renderFrame()

        let fills = frame.commands.compactMap { command -> FillRectCommand? in
            guard case .fillRect(let fill) = command else { return nil }
            return fill
        }
        XCTAssertTrue(
            fills.contains { $0.rect == Rect(x: 10, y: 10, width: 40, height: 40) },
            "the frame path culled every degenerate node's subtree while the scene path kept "
                + "painting it — the two paint the same tree and must agree")
    }

    func testFramePathPaintsNoOutlineForAZeroExtentNode() async {
        let collapsed = ViewNode(
            frame: Rect(x: 10, y: 10, width: 0, height: 0),
            outlineColor: red,
            outlineWidth: 3
        )
        let root = ViewNode(
            frame: Rect(x: 0, y: 0, width: 200, height: 200),
            isHitTestVisible: false,
            children: [collapsed]
        )

        let frame = RetainedViewRuntime(root: root).renderFrame()

        let outlineFills = frame.commands.compactMap { command -> FillRectCommand? in
            guard case .fillRect(let fill) = command else { return nil }
            return fill.color.red == 1 && fill.color.green == 0 && fill.color.blue == 0 ? fill : nil
        }
        XCTAssertTrue(
            outlineFills.isEmpty,
            "an outline outset from a zero-extent frame is a 6 × 6 square the app never asked "
                + "for; the scene path already suppresses it")
    }

    // MARK: - The cull predicate itself

    func testSubtreeCullTreatsDegenerateBoundsAsTouchingAndEmptyClipsAsFatal() async {
        let clip = Rect(x: 0, y: 0, width: 100, height: 100)

        XCTAssertTrue(
            clipAllowsSubtreeTraversal(clip: clip, bounds: Rect(x: 50, y: 50, width: 0, height: 0)),
            "a collapsed node inside the clip is a legal parent for overflowing children")
        XCTAssertFalse(
            clipAllowsSubtreeTraversal(clip: clip, bounds: Rect(x: 500, y: 50, width: 0, height: 0)),
            "a collapsed node outside the clip prunes")
        XCTAssertTrue(
            clipAllowsSubtreeTraversal(clip: nil, bounds: Rect(x: 500, y: 50, width: 0, height: 0)),
            "no clip means no cull")
        XCTAssertFalse(
            clipAllowsSubtreeTraversal(
                clip: Rect(x: 0, y: 0, width: 0, height: 40),
                bounds: Rect(x: 0, y: 0, width: 10, height: 10)),
            "nothing beneath an empty clip can produce a visible pixel")
        XCTAssertFalse(
            clipAllowsSubtreeTraversal(
                clip: clip, bounds: Rect(x: .nan, y: 0, width: 0, height: 0)),
            "a non-finite collapsed footprint culls rather than descending on NaN comparisons")
        XCTAssertTrue(
            clipAllowsSubtreeTraversal(clip: clip, bounds: Rect(x: 50, y: 50, width: 10, height: 10)),
            "a normal overlapping footprint is unaffected")
        XCTAssertFalse(
            clipAllowsSubtreeTraversal(clip: clip, bounds: Rect(x: 100, y: 0, width: 10, height: 10)),
            "and a normal footprint that only touches the clip edge still culls")
    }
}
