import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI

/// A compositing group (`.drawingGroup()`, `.compositingGroup()`) rasterizes
/// its whole subtree into an offscreen bitmap on the CPU, on the main actor.
/// That is the single most expensive thing the painter does per node, and it
/// used to happen on every frame the group was painted — the buffer was
/// clamped and bounded, but never amortized.
///
/// The bitmap is now cached on the node under the same condition the paint
/// record replay uses: the node's paint key is unchanged and its subtree is
/// clean. `ScenePaintMetrics` reports which of the two happened, so the
/// amortization is observable from app code and from here.
@MainActor
final class CompositingGroupBitmapCacheTests: XCTestCase {

    private let surfaceSize = Size(width: 200, height: 100)

    private func makeGroup() -> (group: ViewNode, child: ViewNode) {
        let child = ViewNode(
            frame: Rect(x: 0, y: 0, width: 60, height: 60),
            backgroundColor: Color(red: 0, green: 0, blue: 1, alpha: 1)
        )
        let group = ViewNode(
            frame: Rect(x: 0, y: 0, width: 120, height: 80),
            isCompositingGroup: true,
            children: [child]
        )
        return (group, child)
    }

    private func paint(_ root: ViewNode) -> GPUIScene {
        ScenePainter.paint(root: root, clearColor: .black, surfaceSize: surfaceSize)
    }

    func testUnchangedCompositingGroupIsRasterizedOnceAndThenReused() async {
        let (group, _) = makeGroup()

        let first = paint(group)
        XCTAssertEqual(first.paintMetrics.compositingGroupsRasterized, 1)
        XCTAssertEqual(first.paintMetrics.compositingGroupsReused, 0)

        let second = paint(group)
        XCTAssertEqual(
            second.paintMetrics.compositingGroupsRasterized, 0,
            "an unchanged group must not walk and CPU-rasterize its subtree again")
        XCTAssertEqual(second.paintMetrics.compositingGroupsReused, 1)

        XCTAssertEqual(
            second.imageResources.first?.bitmap, first.imageResources.first?.bitmap,
            "and the composited image must be the same pixels, not just the same count")
    }

    func testChangingTheSubtreeReRasterizesTheGroup() async {
        let (group, child) = makeGroup()

        let first = paint(group)
        _ = paint(group)

        child.backgroundColor = Color(red: 1, green: 0, blue: 0, alpha: 1)

        let third = paint(group)
        XCTAssertEqual(
            third.paintMetrics.compositingGroupsRasterized, 1,
            "a dirty descendant must invalidate the cached bitmap")
        XCTAssertEqual(third.paintMetrics.compositingGroupsReused, 0)
        XCTAssertNotEqual(
            third.imageResources.first?.bitmap, first.imageResources.first?.bitmap,
            "the recomposited bitmap must carry the change")
    }

    func testChangingTheGroupsOwnPaintKeyReRasterizesIt() async {
        let (group, _) = makeGroup()

        _ = paint(group)
        _ = paint(group)

        // Display scale is part of the paint key and of the buffer's size, and
        // no descendant is dirty when it changes: reusing across it would
        // upscale last frame's pixels on the DPI change that moved the window.
        let scaled = ScenePainter.paint(
            root: group, clearColor: .black, surfaceSize: surfaceSize, displayScale: 2)

        XCTAssertEqual(scaled.paintMetrics.compositingGroupsRasterized, 1)
        XCTAssertEqual(scaled.paintMetrics.compositingGroupsReused, 0)
        XCTAssertEqual(
            scaled.imageResources.first?.bitmap.width, 240,
            "the re-rasterized buffer is sized in device pixels")
    }

    func testGroupPaintedInlineReleasesItsCachedBitmap() async {
        let (group, _) = makeGroup()

        _ = paint(group)
        XCTAssertNotNil(group.cachedCompositingGroupBitmap)

        group.isCompositingGroup = false
        _ = paint(group)

        XCTAssertNil(
            group.cachedCompositingGroupBitmap,
            "a buffer up to maxCompositingGroupPixels must not outlive the modifier that asked "
                + "for it")
        XCTAssertNil(group.cachedCompositingGroupKey)
    }

    func testReusedGroupStillCompositesTheSameImagePrimitive() async {
        let (group, _) = makeGroup()

        _ = paint(group)
        let second = paint(group)

        XCTAssertEqual(second.layers[0].images.count, 1, "reuse composites, it does not skip")
        XCTAssertEqual(second.imageResources.count, 1)
        XCTAssertTrue(
            (second.imageResources.first?.bitmap.pixels.contains { $0 != 0 }) ?? false,
            "and the reused bitmap still carries the group's content")
    }
}
