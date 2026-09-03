import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI

/// Additive source-only regression freeze at 93171a31ce811ab4a98e52620fd9741f9f32e640.
/// Invokes public projected actions, without a fabricated accessibility target.
@MainActor
final class RetainedProjectedRootActionTests: XCTestCase {
    func testSavedProjectedRootActionRejectsQueryTimeSelectionABAWithoutChangingOrdinaryCallbacks() async throws {
        let ordinary = ViewNode()
        ordinary.accessibilityLabel = "Ordinary"
        ordinary.accessibilityTraits = .isButton
        var ordinaryActions = 0
        var ordinaryLayouts = 0
        ordinary.accessibilityActions = [
            RetainedAccessibilityAction(name: "Activate", kind: .default) { ordinaryActions += 1 }
        ]
        let ordinaryRuntime = RetainedViewRuntime(root: ordinary)
        defer {
            ordinary.onLayoutWithNode = nil
            ordinaryRuntime.stopRenderLifecycleCallbacks()
            ordinaryRuntime.cancelRenderLifecycleTasks()
            ordinary.removeAllChildren()
        }
        ordinaryRuntime.setRootSize(IntSize(width: 80, height: 40))
        _ = ordinaryRuntime.renderFrame()
        let ordinaryProjection = try XCTUnwrap(AccessibilityProjection.project(runtime: ordinaryRuntime))
        XCTAssertTrue(ordinaryProjection.sourceNode === ordinary)
        XCTAssertEqual(ordinaryProjection.actions.count, 1)
        let ordinarySavedAction = try XCTUnwrap(ordinaryProjection.actions.first)
        XCTAssertTrue(ordinarySavedAction.isDefault)
        ordinary.onLayoutWithNode = { node, _ in
            XCTAssertTrue(node === ordinary)
            ordinaryLayouts += 1
        }
        ordinaryRuntime.setRootSize(IntSize(width: 120, height: 40))
        XCTAssertEqual(ordinaryLayouts, 0, "The callback must run inside the action's layout query")
        XCTAssertEqual(ordinaryActions, 0)

        ordinarySavedAction.invoke()
        XCTAssertEqual(ordinaryLayouts, 1)
        XCTAssertEqual(ordinaryActions, 1)
        ordinarySavedAction.invoke()
        XCTAssertEqual(ordinaryLayouts, 1, "A settled repeat must not deliver another layout callback")
        XCTAssertEqual(ordinaryActions, 2, "One ordinary invocation still dispatches exactly one handler")

        let selectedA = ViewNode()
        selectedA.accessibilityLabel = "A"
        selectedA.accessibilityTraits = .isButton
        let selectedB = ViewNode()
        selectedB.accessibilityLabel = "B"
        selectedB.accessibilityTraits = .isButton
        var actionsA = 0
        var actionsB = 0
        selectedA.accessibilityActions = [
            RetainedAccessibilityAction(name: "Activate", kind: .default) { actionsA += 1 }
        ]
        selectedB.accessibilityActions = [
            RetainedAccessibilityAction(name: "Activate", kind: .default) { actionsB += 1 }
        ]
        let root = ViewNode.selectedContentBoundary(role: .viewThatFits, child: selectedA)
        let runtime = RetainedViewRuntime(root: root)
        defer {
            selectedA.onLayoutWithNode = nil
            runtime.stopRenderLifecycleCallbacks()
            runtime.cancelRenderLifecycleTasks()
            root.removeAllChildren()
        }
        runtime.setRootSize(IntSize(width: 80, height: 40))
        _ = runtime.renderFrame()
        let originalPath = try XCTUnwrap(root.captureSelectedContentPath(in: runtime))
        XCTAssertTrue(originalPath.isCurrent)
        let originalProjection = try XCTUnwrap(AccessibilityProjection.project(runtime: runtime))
        XCTAssertTrue(originalProjection.sourceNode === selectedA)
        XCTAssertEqual(originalProjection.flattened().count, 1)
        XCTAssertEqual(originalProjection.actions.count, 1)
        let savedRootAction = try XCTUnwrap(originalProjection.actions.first)
        XCTAssertTrue(savedRootAction.isDefault)

        var typedLayouts = 0
        var selectionChanges = 0
        var isInvokingSavedAction = false
        selectedA.onLayoutWithNode = { [weak root] node, _ in
            typedLayouts += 1
            guard selectionChanges == 0 else { return }
            XCTAssertTrue(isInvokingSavedAction, "Selection changes must occur in this invocation's query")
            guard isInvokingSavedAction, let root else { return }
            selectionChanges += 1
            XCTAssertTrue(root.children.first === node)
            root.setChildren([selectedB])
            XCTAssertTrue(root.children.first === selectedB)
            XCTAssertTrue(selectedB.parent === root)
            XCTAssertNil(node.parent)
            root.setChildren([node])
            XCTAssertTrue(root.children.first === node)
            XCTAssertTrue(node.parent === root)
            XCTAssertNil(selectedB.parent)
        }
        runtime.setRootSize(IntSize(width: 120, height: 40))
        XCTAssertEqual(typedLayouts, 0)
        XCTAssertEqual(selectionChanges, 0)
        XCTAssertEqual(actionsA, 0)
        XCTAssertEqual(actionsB, 0)

        isInvokingSavedAction = true
        savedRootAction.invoke()
        isInvokingSavedAction = false

        XCTAssertEqual(selectionChanges, 1, "The original query must actually exercise physical A-B-A replacement")
        XCTAssertGreaterThanOrEqual(typedLayouts, 1)
        XCTAssertTrue(root.children.first === selectedA)
        XCTAssertTrue(selectedA.parent === root)
        XCTAssertNil(selectedB.parent)
        XCTAssertFalse(originalPath.isCurrent, "The original attachment cannot revive after identical topology returns")
        XCTAssertFalse(originalPath.isInstalled(in: runtime))
        XCTAssertEqual(actionsA, 0, "The old operation must not reacquire A after its query replaced the selection")
        XCTAssertEqual(actionsB, 0, "The old operation must not dispatch the intermediate selection")

        // A separate invocation may capture the now-current selected attachment.
        // No render, retry loop, or extra settlement budget is inserted here.
        let currentProjection = try XCTUnwrap(AccessibilityProjection.project(runtime: runtime))
        XCTAssertTrue(currentProjection.sourceNode === selectedA)
        XCTAssertEqual(currentProjection.actions.count, 1)
        let currentAction = try XCTUnwrap(currentProjection.actions.first)
        currentAction.invoke()
        XCTAssertEqual(selectionChanges, 1)
        XCTAssertEqual(actionsA, 1)
        XCTAssertEqual(actionsB, 0)
    }
}
