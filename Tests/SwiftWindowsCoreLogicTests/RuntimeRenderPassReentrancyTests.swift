import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI

/// A render pass stages invalidations while it runs and clears `dirtyFlags`
/// when it ends, so the pass has to be the only thing that opens and closes it.
/// A pass runs arbitrary app closures (`onAppear`, `onLayout`, `onSizeChange`,
/// `canvasDraw`), and one of them rendering again used to close the outer
/// pass's staging on the way out: everything the rest of the outer pass
/// invalidated then went straight into `dirtyFlags` and was wiped by the outer
/// pass's own clear. The runtime went permanently clean, the host stopped
/// asking for frames, and nothing said why.
final class RuntimeRenderPassReentrancyTests: XCTestCase {

    func testNestedRenderFromALifecycleClosureDoesNotSwallowInvalidations() async {
        await MainActor.run {
            let sibling = ViewNode(
                frame: Rect(x: 0, y: 0, width: 40, height: 40),
                backgroundColor: Color(red: 0, green: 0, blue: 0, alpha: 1)
            )
            let trigger = ViewNode(frame: Rect(x: 60, y: 0, width: 40, height: 40))
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 200, height: 200),
                isHitTestVisible: false,
                children: [sibling, trigger]
            )

            let runtime = RetainedViewRuntime(root: root)
            let reentriesBefore = RetainedViewRuntime.reentrantRenderPassCount
            var didReenter = false
            trigger.onAppear = { [weak runtime] in
                guard !didReenter, let runtime else { return }
                didReenter = true
                // An app closure rendering from inside a render is a bug in the
                // app; losing the invalidation that follows it is a bug here.
                _ = runtime.renderFrame()
                sibling.backgroundColor = Color(red: 1, green: 1, blue: 1, alpha: 1)
            }

            _ = runtime.renderFrame()

            XCTAssertTrue(didReenter, "the lifecycle closure must have run inside the pass")
            XCTAssertGreaterThan(
                RetainedViewRuntime.reentrantRenderPassCount, reentriesBefore,
                "the nested pass must be recognised as nested, not silently opened")
            XCTAssertTrue(
                runtime.isDirty,
                "an invalidation raised after a nested render must still reach the next frame")

            let second = runtime.renderFrame()
            XCTAssertTrue(
                second.commands.contains { command in
                    guard case .fillRect(let fill) = command else { return false }
                    return fill.color.red == 1 && fill.color.green == 1 && fill.color.blue == 1
                },
                "and the next pass must repaint the sibling rather than replay its stale range")
        }
    }

    func testNestedSceneRenderLeavesTheOuterPassInChargeOfTheStaging() async {
        await MainActor.run {
            let sibling = ViewNode(
                frame: Rect(x: 0, y: 0, width: 40, height: 40),
                backgroundColor: Color(red: 0, green: 0, blue: 0, alpha: 1)
            )
            let trigger = ViewNode(frame: Rect(x: 60, y: 0, width: 40, height: 40))
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 200, height: 200),
                isHitTestVisible: false,
                children: [sibling, trigger]
            )

            let runtime = RetainedViewRuntime(root: root)
            var didReenter = false
            trigger.onAppear = { [weak runtime] in
                guard !didReenter, let runtime else { return }
                didReenter = true
                _ = runtime.renderScene()
                sibling.opacity = 0.5
            }

            _ = runtime.renderScene()

            XCTAssertTrue(didReenter)
            XCTAssertTrue(
                runtime.isDirty,
                "a nested pass must not close the staging the outer pass is still filling")
        }
    }

    /// The ordinary case has to keep working: a pass that opens and closes
    /// normally still ends clean.
    func testNonNestedPassStillEndsClean() async {
        await MainActor.run {
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 200, height: 200),
                isHitTestVisible: false,
                children: [
                    ViewNode(
                        frame: Rect(x: 0, y: 0, width: 40, height: 40),
                        backgroundColor: Color(red: 1, green: 1, blue: 1, alpha: 1)
                    )
                ]
            )

            let runtime = RetainedViewRuntime(root: root)
            _ = runtime.renderFrame()
            XCTAssertFalse(runtime.isDirty)
            _ = runtime.renderScene()
            XCTAssertFalse(runtime.isDirty)
        }
    }
}
