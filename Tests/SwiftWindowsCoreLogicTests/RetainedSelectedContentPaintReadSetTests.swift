import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI

/// Direct public scene painting must not clean an ancestor after a later
/// Canvas callback invalidates an earlier consumed typed selection.
@MainActor
final class RetainedSelectedContentPaintReadSetTests: XCTestCase {
    func testLaterOrdinaryCanvasKeepsAnAncestorDirtyAfterReplacingAnEarlierPaintedSelection() async throws {
        let size = IntSize(width: 80, height: 40)
        let selectedFrame = Rect(x: 8, y: 8, width: 16, height: 16)
        let replacementColor = Color(red: 0, green: 0, blue: 1, alpha: 1)
        let selectedA = ViewNode(frame: selectedFrame, backgroundColor: .white)
        let selectedB = ViewNode(frame: selectedFrame, backgroundColor: replacementColor)
        let boundary = ViewNode.selectedContentBoundary(role: .viewThatFits, child: selectedA)
        let laterCanvas = ViewNode(frame: Rect(x: 40, y: 0, width: 10, height: 10))
        let root = ViewNode(children: [boundary, laterCanvas])
        let runtime = RetainedViewRuntime(root: root)
        defer {
            laterCanvas.canvasDraw = nil
            runtime.stopRenderLifecycleCallbacks()
            runtime.cancelRenderLifecycleTasks()
            root.removeAllChildren()
        }
        runtime.setRootSize(size)
        // Warm normal layout with no Canvas callback installed. The frame
        // painter does not publish ScenePainter's separate cache tuple.
        _ = runtime.renderFrame()
        XCTAssertFalse(runtime.isDirty)
        XCTAssertFalse(root.hasDirtySubtree)
        XCTAssertNil(root.selectedContentRole)
        XCTAssertNil(laterCanvas.selectedContentRole)
        XCTAssertEqual(root.children.count, 2)
        XCTAssertTrue(root.children[0] === boundary)
        XCTAssertTrue(root.children[1] === laterCanvas)
        XCTAssertEqual(selectedA.resolvedFrame, selectedFrame)
        XCTAssertEqual(boundary.resolvedFrame.origin, .zero)
        XCTAssertNil(root.cachedSceneKey)
        XCTAssertNil(root.cachedScenePaintRange)
        XCTAssertNil(root.cachedSceneSnapshotIdentity)
        XCTAssertNil(selectedA.cachedSceneSnapshotIdentity)
        XCTAssertFalse(selectedB.hasPaintedCurrentAttachment)
        let originalPath = try XCTUnwrap(boundary.captureSelectedContentPath(in: runtime))
        XCTAssertTrue(originalPath.isCurrent)

        var canvasCalls = 0
        var selectionChanges = 0
        laterCanvas.canvasDraw = { [weak boundary] _, _ in
            canvasCalls += 1
            guard selectionChanges == 0 else { return }
            guard let boundary else {
                return XCTFail("The original installed boundary must still exist")
            }
            // With stable equal-z physical child order, A has completed its
            // scene paint before this later ordinary Canvas callback begins.
            XCTAssertNotNil(selectedA.cachedSceneSnapshotIdentity)
            XCTAssertFalse(selectedA.hasDirtySubtree)
            XCTAssertTrue(originalPath.isCurrent)
            XCTAssertTrue(boundary.children.first === selectedA)
            selectionChanges += 1
            boundary.setChildren([selectedB])
            XCTAssertTrue(boundary.children.first === selectedB)
            XCTAssertTrue(selectedB.parent === boundary)
            XCTAssertNil(selectedA.parent)
            XCTAssertFalse(originalPath.isCurrent)
        }
        XCTAssertEqual(canvasCalls, 0)
        XCTAssertEqual(selectionChanges, 0)
        XCTAssertTrue(runtime.isDirty)

        // This is the existing public painter API, outside an owned runtime
        // render pass. endRenderPass must not mask a stale ancestor finish by
        // reapplying pending dirty flags after ScenePainter has returned.
        _ = ScenePainter.paint(
            root: root, clearColor: .black,
            surfaceSize: Size(width: 80, height: 40))

        XCTAssertEqual(canvasCalls, 1)
        XCTAssertEqual(selectionChanges, 1)
        XCTAssertTrue(boundary.children.first === selectedB)
        XCTAssertTrue(selectedB.parent === boundary)
        XCTAssertNil(selectedA.parent)
        XCTAssertFalse(originalPath.isCurrent)
        XCTAssertFalse(originalPath.isInstalled(in: runtime))
        XCTAssertTrue(boundary.hasDirtySubtree)
        XCTAssertTrue(selectedB.hasDirtySubtree)
        XCTAssertFalse(selectedB.hasPaintedCurrentAttachment, "The obsolete paint cannot reacquire the replacement")
        XCTAssertTrue(runtime.isDirty)
        XCTAssertTrue(root.hasDirtySubtree, "An expired consumed child path must not become a clean ancestor")
        XCTAssertNil(root.cachedSceneKey, "The rejected ancestor must not publish a scene cache tuple")
        XCTAssertNil(root.cachedScenePaintRange)
        XCTAssertNil(root.cachedSceneSnapshotIdentity)

        // A separate normal request captures current B and may paint it.
        // No render loop, timer, forced invalidation, or extra budget is used.
        let fresh = runtime.renderScene()
        let bitmap = GPUIRawSceneRasterizer.rasterize(fresh, size: size)
        XCTAssertEqual(bitmap.pixelColor(atX: 12, y: 12), replacementColor)
        XCTAssertEqual(bitmap.pixelColor(atX: 30, y: 12), .black)
        XCTAssertEqual(selectionChanges, 1)
        XCTAssertTrue(selectedB.hasPaintedCurrentAttachment)
        XCTAssertFalse(originalPath.isCurrent)
        XCTAssertFalse(root.hasDirtySubtree)
        XCTAssertFalse(runtime.isDirty)
        XCTAssertNotNil(root.cachedSceneKey)
        XCTAssertNotNil(root.cachedScenePaintRange)
        XCTAssertNotNil(root.cachedSceneSnapshotIdentity)
    }
}
