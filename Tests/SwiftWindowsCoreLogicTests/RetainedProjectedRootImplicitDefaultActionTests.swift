import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI

/// Two new supplemental oracles for the provisional composition's implicit route.
/// The historical explicit-action fixture and all 99 minimum oracles stay unchanged.
@MainActor
final class RetainedProjectedRootImplicitDefaultActionTests: XCTestCase {
    func testOrdinaryImplicitDefaultActionQueriesLayoutAndDispatchesOncePerInvocation() async throws {
        let ordinary = ViewNode()
        ordinary.accessibilityLabel = "Ordinary"
        ordinary.accessibilityTraits = .isButton
        var activations = 0
        var layouts = 0
        var isInvokingDefaultAction = false
        ordinary.onActivate = { activations += 1 }
        let runtime = RetainedViewRuntime(root: ordinary)
        defer {
            ordinary.onLayoutWithNode = nil
            ordinary.onActivate = nil
            runtime.stopRenderLifecycleCallbacks()
            runtime.cancelRenderLifecycleTasks()
            ordinary.removeAllChildren()
        }
        runtime.setRootSize(IntSize(width: 80, height: 40))
        _ = runtime.renderFrame()
        let projection = try XCTUnwrap(AccessibilityProjection.project(runtime: runtime))
        XCTAssertTrue(projection.sourceNode === ordinary)
        XCTAssertTrue(ordinary.accessibilityActions.isEmpty)
        XCTAssertTrue(projection.actions.isEmpty, "Only the implicit onActivate route may dispatch")
        ordinary.onLayoutWithNode = { [weak ordinary] node, _ in
            XCTAssertTrue(node === ordinary)
            XCTAssertTrue(isInvokingDefaultAction, "Layout must run inside the public invocation")
            layouts += 1
        }
        runtime.setRootSize(IntSize(width: 120, height: 40))
        XCTAssertEqual(layouts, 0)
        XCTAssertEqual(activations, 0)

        isInvokingDefaultAction = true
        let firstResult = projection.invokeDefaultAction()
        isInvokingDefaultAction = false
        XCTAssertTrue(firstResult)
        XCTAssertEqual(layouts, 1)
        XCTAssertEqual(activations, 1)
        XCTAssertTrue(ordinary.accessibilityActions.isEmpty)
        XCTAssertTrue(projection.actions.isEmpty)

        isInvokingDefaultAction = true
        let secondResult = projection.invokeDefaultAction()
        isInvokingDefaultAction = false
        XCTAssertTrue(secondResult)
        XCTAssertEqual(layouts, 1, "A settled repeat must not deliver another layout callback")
        XCTAssertEqual(activations, 2, "Each public invocation dispatches exactly one handler")
        XCTAssertTrue(ordinary.accessibilityActions.isEmpty)
        XCTAssertTrue(projection.actions.isEmpty)
    }

    func testSelectedRootImplicitDefaultActionRejectsQueryTimeABAThenFreshInvocationSucceeds() async throws {
        let selectedA = ViewNode()
        selectedA.accessibilityLabel = "A"
        selectedA.accessibilityTraits = .isButton
        let selectedB = ViewNode()
        selectedB.accessibilityLabel = "B"
        selectedB.accessibilityTraits = .isButton
        var activationsA = 0
        var activationsB = 0
        selectedA.onActivate = { activationsA += 1 }
        selectedB.onActivate = { activationsB += 1 }
        let root = ViewNode.selectedContentBoundary(role: .viewThatFits, child: selectedA)
        let runtime = RetainedViewRuntime(root: root)
        defer {
            selectedA.onLayoutWithNode = nil
            selectedA.onActivate = nil
            selectedB.onActivate = nil
            runtime.stopRenderLifecycleCallbacks()
            runtime.cancelRenderLifecycleTasks()
            root.removeAllChildren()
        }
        runtime.setRootSize(IntSize(width: 80, height: 40))
        _ = runtime.renderFrame()
        let originalPath = try XCTUnwrap(root.captureSelectedContentPath(in: runtime))
        XCTAssertTrue(originalPath.isCurrent)
        XCTAssertTrue(originalPath.isInstalled(in: runtime))
        let originalProjection = try XCTUnwrap(AccessibilityProjection.project(runtime: runtime))
        XCTAssertTrue(originalProjection.sourceNode === selectedA)
        XCTAssertEqual(originalProjection.flattened().count, 1)
        XCTAssertTrue(selectedA.accessibilityActions.isEmpty)
        XCTAssertTrue(selectedB.accessibilityActions.isEmpty)
        XCTAssertTrue(originalProjection.actions.isEmpty, "A stored action must not mask the implicit route")

        var layouts = 0
        var selectionChanges = 0
        var isInvokingOriginalAction = false
        selectedA.onLayoutWithNode = { [weak root] node, _ in
            layouts += 1
            guard selectionChanges == 0 else { return }
            XCTAssertTrue(isInvokingOriginalAction, "The ABA must occur in the original invocation's query")
            guard isInvokingOriginalAction, let root else { return }
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
        XCTAssertEqual(layouts, 0)
        XCTAssertEqual(selectionChanges, 0)
        XCTAssertEqual(activationsA, 0)
        XCTAssertEqual(activationsB, 0)

        isInvokingOriginalAction = true
        let originalResult = originalProjection.invokeDefaultAction()
        isInvokingOriginalAction = false

        XCTAssertFalse(originalResult, "The original implicit invocation must reject the replaced attachment")
        XCTAssertEqual(selectionChanges, 1)
        XCTAssertGreaterThanOrEqual(layouts, 1)
        XCTAssertEqual(root.children.count, 1)
        XCTAssertTrue(root.children.first === selectedA)
        XCTAssertTrue(selectedA.parent === root)
        XCTAssertNil(selectedB.parent)
        XCTAssertFalse(originalPath.isCurrent)
        XCTAssertFalse(originalPath.isInstalled(in: runtime))
        XCTAssertEqual(activationsA, 0, "The original invocation must not reacquire reinserted A")
        XCTAssertEqual(activationsB, 0, "The intermediate B must not receive the original action")
        XCTAssertTrue(selectedA.accessibilityActions.isEmpty)
        XCTAssertTrue(selectedB.accessibilityActions.isEmpty)
        XCTAssertTrue(originalProjection.actions.isEmpty)

        // A separate public invocation may capture the now-current path.
        // No render, separate layout query, retry or extra settlement budget is added.
        let currentProjection = try XCTUnwrap(AccessibilityProjection.project(runtime: runtime))
        XCTAssertTrue(currentProjection.sourceNode === selectedA)
        XCTAssertTrue(currentProjection.actions.isEmpty)
        XCTAssertTrue(currentProjection.invokeDefaultAction())
        XCTAssertEqual(selectionChanges, 1)
        XCTAssertEqual(activationsA, 1)
        XCTAssertEqual(activationsB, 0)
        XCTAssertEqual(root.children.count, 1)
        XCTAssertTrue(root.children.first === selectedA)
        XCTAssertTrue(selectedA.parent === root)
        XCTAssertNil(selectedB.parent)
        XCTAssertFalse(originalPath.isCurrent)
        XCTAssertFalse(originalPath.isInstalled(in: runtime))
        XCTAssertTrue(selectedA.accessibilityActions.isEmpty)
        XCTAssertTrue(selectedB.accessibilityActions.isEmpty)
    }
}
