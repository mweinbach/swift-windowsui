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

    /// A node whose `onAppear` mutates an earlier sibling. `onAppear` fires
    /// from inside the paint traversal, after the sibling has already been
    /// appended and marked rendered, so the first frame is necessarily stale —
    /// the requirement is that the runtime is still dirty afterwards and the
    /// next pass repaints rather than replaying the sibling's cached range.
    func testInvalidationFromPaintClosureSurvivesTheRenderPass() async {
        await MainActor.run {
            let sibling = ViewNode(
                frame: Rect(x: 0, y: 0, width: 40, height: 40),
                backgroundColor: Color(red: 0, green: 0, blue: 0, alpha: 1)
            )
            let trigger = ViewNode(frame: Rect(x: 60, y: 0, width: 40, height: 40))
            let root = ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 200), isHitTestVisible: false)
            root.addChild(sibling)
            root.addChild(trigger)

            var didMutate = false
            trigger.onAppear = {
                guard !didMutate else { return }
                didMutate = true
                sibling.backgroundColor = Color(red: 1, green: 1, blue: 1, alpha: 1)
            }

            let runtime = RetainedViewRuntime(root: root)
            let first = runtime.renderFrame()
            XCTAssertTrue(didMutate, "the lifecycle closure must have run during the first pass")
            XCTAssertFalse(
                containsWhiteFill(first),
                "the sibling was already painted when the closure ran, so the first frame is stale")
            XCTAssertTrue(
                runtime.isDirty,
                "an invalidation raised during the pass must not be wiped by the pass's own clear")

            let second = runtime.renderFrame()
            XCTAssertTrue(
                containsWhiteFill(second),
                "the second pass must repaint the sibling rather than replay its cached range")
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
private func containsWhiteFill(_ frame: RenderFrame) -> Bool {
    frame.commands.contains { command in
        guard case .fillRect(let fill) = command else { return false }
        return fill.color.red == 1 && fill.color.green == 1 && fill.color.blue == 1 && fill.color.alpha == 1
    }
}
