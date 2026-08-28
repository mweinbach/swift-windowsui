import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsPlatform
import XCTest

@testable import SwiftWindowsUI

/// A render pass runs arbitrary app code inside its traversal (`onLayout`,
/// `onAppear`, `onSizeChange`, `canvasDraw`) and then clears `dirtyFlags`.
/// Anything those closures invalidated has to survive that clear, or the
/// change is stranded until an unrelated event happens to dirty the runtime
/// again.
final class RuntimeDirtyFlagIntegrityTests: XCTestCase {

    /// A node whose Canvas callback mutates an earlier sibling. Canvas runs
    /// inside the paint traversal, after the sibling has already been
    /// appended and marked rendered, so the first frame is necessarily stale —
    /// the requirement is that the runtime is still dirty afterwards and the
    /// next pass repaints rather than replaying the sibling's cached range.
    func testInvalidationFromPaintClosureSurvivesTheRenderPass() async {
        await MainActor.run {
            for usesScene in [false, true] {
                let sibling = ViewNode(
                    frame: Rect(x: 0, y: 0, width: 40, height: 40),
                    backgroundColor: Color(red: 0, green: 0, blue: 0, alpha: 1)
                )
                let trigger = ViewNode(frame: Rect(x: 60, y: 0, width: 40, height: 40))
                let root = ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 200), isHitTestVisible: false)
                root.addChild(sibling)
                root.addChild(trigger)

                var didMutate = false
                trigger.canvasDraw = { _, _ in
                    guard !didMutate else { return }
                    didMutate = true
                    sibling.backgroundColor = Color(red: 1, green: 1, blue: 1, alpha: 1)
                }

                let runtime = RetainedViewRuntime(root: root)
                let firstContainsWhite = renderContainsWhiteFill(runtime, usesScene: usesScene)
                XCTAssertTrue(didMutate, "The Canvas callback must run during the first paint pass")
                XCTAssertFalse(
                    firstContainsWhite,
                    "the sibling was already painted when the closure ran, so the first frame is stale")
                XCTAssertTrue(
                    runtime.isDirty,
                    "an invalidation raised during the pass must not be wiped by the pass's own clear")

                XCTAssertTrue(
                    renderContainsWhiteFill(runtime, usesScene: usesScene),
                    "the second pass must repaint the sibling rather than replay its cached range")
                XCTAssertFalse(runtime.isDirty, "The follow-up pass must consume the staged invalidation")
            }
        }
    }

    /// Appearance is staged after layout and before painting on both paths.
    /// Its paint-only mutation is visible immediately, but must still survive
    /// the render pass's dirty-flag clear and settle on the follow-up pass.
    func testAppearanceInvalidationRunsBeforePaintAndStillSchedulesAFollowup() async {
        await MainActor.run {
            for usesScene in [false, true] {
                let sibling = ViewNode(
                    frame: Rect(x: 0, y: 0, width: 40, height: 40),
                    backgroundColor: Color(red: 0, green: 0, blue: 0, alpha: 1)
                )
                let trigger = ViewNode(frame: Rect(x: 60, y: 0, width: 40, height: 40))
                let root = ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 200), isHitTestVisible: false)
                root.addChild(sibling)
                root.addChild(trigger)

                var appearances = 0
                trigger.onAppear = {
                    appearances += 1
                    sibling.backgroundColor = Color(red: 1, green: 1, blue: 1, alpha: 1)
                }

                let runtime = RetainedViewRuntime(root: root)
                XCTAssertTrue(
                    renderContainsWhiteFill(runtime, usesScene: usesScene),
                    "Appearance must run before the sibling is painted on either render path")
                XCTAssertEqual(appearances, 1)
                XCTAssertTrue(
                    runtime.isDirty,
                    "an invalidation raised during the pass must not be wiped by the pass's own clear")

                XCTAssertTrue(
                    renderContainsWhiteFill(runtime, usesScene: usesScene),
                    "the second pass must repaint the sibling rather than replay its cached range")
                XCTAssertEqual(appearances, 1, "A follow-up paint must not repeat appearance")
                XCTAssertFalse(runtime.isDirty, "A completed appearance must allow the runtime to settle")
            }
        }
    }

    /// The staging must not leak across passes: a quiet frame still leaves the
    /// runtime clean, so the host's `shouldDriveFrames` gate can settle.
    func testQuietRenderPassLeavesTheRuntimeClean() async {
        await MainActor.run {
            let root = ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 200), isHitTestVisible: false)
            root.addChild(ViewNode(frame: Rect(x: 0, y: 0, width: 40, height: 40), backgroundColor: .white))

            let runtime = RetainedViewRuntime(root: root)
            _ = runtime.renderScene()
            XCTAssertFalse(runtime.isDirty)
            _ = runtime.renderScene()
            XCTAssertFalse(runtime.isDirty)
            _ = runtime.renderFrame()
            XCTAssertFalse(runtime.isDirty)
        }
    }

    func testUnchangedFrameAssignmentsDoNotInvalidateSettledGeometry() async {
        await MainActor.run {
            let child = ViewNode(frame: Rect(x: 0, y: 0, width: 40, height: 40), backgroundColor: .white)
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 200, height: 200),
                isHitTestVisible: false, children: [child])
            let runtime = RetainedViewRuntime(root: root)
            _ = runtime.renderScene()

            let unchangedFrame = child.frame
            child.frame = unchangedFrame
            child.frame.size.width = unchangedFrame.width
            XCTAssertFalse(runtime.isDirty, "No-op geometry writes must not schedule another frame")
            XCTAssertFalse(runtime.hasPendingLayout)

            child.frame.origin.x = 20
            XCTAssertTrue(runtime.hasPendingLayout, "A changed frame must still invalidate layout immediately")
            _ = runtime.renderScene()
            XCTAssertEqual(child.resolvedFrame.minX, 20, accuracy: 0.001)
            XCTAssertFalse(runtime.hasPendingLayout)
        }
    }

    func testRepeatedBorderWidthFromLayoutSettlesAndRealChangesStillInvalidate() async {
        await MainActor.run {
            var borderWidth = 1.0
            let child = ViewNode(
                frame: Rect(x: 0, y: 0, width: 40, height: 40),
                backgroundColor: .white, borderColor: .black, borderWidth: borderWidth)
            child.onLayout = { _ in child.borderWidth = borderWidth }
            let runtime = RetainedViewRuntime(
                root: ViewNode(
                    frame: Rect(x: 0, y: 0, width: 100, height: 100),
                    isHitTestVisible: false, children: [child]))

            _ = runtime.renderScene()
            XCTAssertFalse(runtime.hasPendingLayout)
            XCTAssertFalse(runtime.isDirty, "A shape reapplying its border during layout must settle")

            borderWidth = 2
            child.borderWidth = borderWidth
            XCTAssertTrue(runtime.hasPendingLayout, "A different border width must still invalidate layout")
            _ = runtime.renderScene()
            XCTAssertEqual(child.borderWidth, 2)
            XCTAssertFalse(runtime.hasPendingLayout)
            XCTAssertFalse(runtime.isDirty)
        }
    }

    /// Invalidations raised outside a render pass keep their historic
    /// immediate behaviour.
    func testInvalidationOutsideRenderPassAppliesImmediately() async {
        await MainActor.run {
            let child = ViewNode(frame: Rect(x: 0, y: 0, width: 40, height: 40), backgroundColor: .white)
            let root = ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 200), isHitTestVisible: false)
            root.addChild(child)

            let runtime = RetainedViewRuntime(root: root)
            _ = runtime.renderScene()
            XCTAssertFalse(runtime.isDirty)

            child.backgroundColor = Color(red: 0, green: 1, blue: 0, alpha: 1)
            XCTAssertTrue(runtime.isDirty)
        }
    }
}

@MainActor
private func renderContainsWhiteFill(_ runtime: RetainedViewRuntime, usesScene: Bool) -> Bool {
    if usesScene {
        return runtime.renderScene().layers.flatMap(\.quads).contains { quad in
            quad.startR == 1 && quad.startG == 1 && quad.startB == 1 && quad.startA == 1
        }
    }
    return runtime.renderFrame().commands.contains { command in
        guard case .fillRect(let fill) = command else { return false }
        return fill.color.red == 1 && fill.color.green == 1 && fill.color.blue == 1 && fill.color.alpha == 1
    }
}
