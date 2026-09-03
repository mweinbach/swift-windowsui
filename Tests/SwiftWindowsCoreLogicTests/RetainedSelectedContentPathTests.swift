import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Path validity is a property of one real physical publication, not a
/// currently matching shape or permission manufactured by a test fixture.
@MainActor
final class RetainedSelectedContentPathTests: XCTestCase {
    func testConstructionPathExpiresOnAdoptionForOrdinaryAndTypedRoots() async throws {
        for usesBoundary in [false, true] {
            let selected = ViewNode(preferredSize: Size(width: 30, height: 20))
            let physical =
                usesBoundary
                ? ViewNode.selectedContentBoundary(role: .viewThatFits, child: selected) : selected
            let construction = try XCTUnwrap(physical.captureSelectedContentConstructionPath())
            XCTAssertTrue(construction.isCurrent)
            XCTAssertTrue(construction.physicalRoot === physical)
            XCTAssertTrue(construction.selectedNode === selected)

            let runtime = RetainedViewRuntime(root: physical)
            defer { retireSelectedPathRuntime(runtime) }
            XCTAssertFalse(construction.isCurrent, "Adoption changes the captured construction attachment")
            XCTAssertFalse(construction.isInstalled(in: runtime))
            let installed = try XCTUnwrap(physical.captureSelectedContentPath(in: runtime))
            assertSelectedPath(installed, physical: physical, selected: selected, runtime: runtime)
            XCTAssertNil(physical.parent)
            if usesBoundary {
                XCTAssertTrue(selected.parent === physical)
                XCTAssertEqual(physical.children.count, 1)
            } else {
                XCTAssertTrue(installed.physicalRoot === installed.selectedNode)
                XCTAssertNil(selected.parent)
            }
        }
    }

    func testRemovedAndReinsertedSelectedNodeNeverRevivesAnOldPath() async throws {
        let selected = ViewNode(preferredSize: Size(width: 30, height: 20))
        let root = ViewNode.selectedContentBoundary(role: .viewThatFits, child: selected)
        let runtime = RetainedViewRuntime(root: root)
        defer { retireSelectedPathRuntime(runtime) }
        let original = try XCTUnwrap(root.captureSelectedContentPath(in: runtime))
        assertSelectedPath(original, physical: root, selected: selected, runtime: runtime)

        selected.removeFromParent()
        XCTAssertTrue(root.children.isEmpty)
        XCTAssertNil(selected.parent)
        XCTAssertFalse(original.isCurrent)
        XCTAssertFalse(original.isInstalled(in: runtime))
        XCTAssertNil(root.captureSelectedContentPath(in: runtime), "A typed boundary with no child is malformed")

        root.setChildren([selected])
        XCTAssertEqual(root.children.count, 1)
        XCTAssertTrue(root.children.first === selected)
        XCTAssertTrue(selected.parent === root)
        XCTAssertFalse(original.isCurrent, "Restored object identities do not restore the old attachment")
        XCTAssertFalse(original.isInstalled(in: runtime))
        let replacement = try XCTUnwrap(root.captureSelectedContentPath(in: runtime))
        assertSelectedPath(replacement, physical: root, selected: selected, runtime: runtime)
    }

    func testCardinalityABAExpiresPathsEvenWhenTheSelectedChildNeverMoves() async throws {
        let selected = ViewNode(preferredSize: Size(width: 30, height: 20))
        let root = ViewNode.selectedContentBoundary(role: .viewThatFits, child: selected)
        let runtime = RetainedViewRuntime(root: root)
        defer { retireSelectedPathRuntime(runtime) }
        let observed = try XCTUnwrap(root.captureSelectedContentPath(in: runtime))
        let notReadDuringInvalidShape = try XCTUnwrap(root.captureSelectedContentPath(in: runtime))
        assertSelectedPath(observed, physical: root, selected: selected, runtime: runtime)
        let extra = ViewNode(preferredSize: Size(width: 5, height: 5))

        root.addChild(extra)
        XCTAssertEqual(root.children.count, 2)
        XCTAssertTrue(root.children.first === selected)
        XCTAssertTrue(selected.parent === root, "Only sibling membership changed")
        XCTAssertTrue(extra.parent === root)
        XCTAssertFalse(observed.isCurrent)
        XCTAssertFalse(observed.isInstalled(in: runtime))
        XCTAssertNil(root.captureSelectedContentPath(in: runtime), "Selection cannot guess among multiple children")

        extra.removeFromParent()
        XCTAssertEqual(root.children.count, 1)
        XCTAssertTrue(root.children.first === selected)
        XCTAssertTrue(selected.parent === root)
        XCTAssertNil(extra.parent)
        XCTAssertFalse(observed.isCurrent)
        XCTAssertFalse(observed.isInstalled(in: runtime))
        // This proof was never queried while the shape was invalid. A getter
        // that merely latches an observed failure cannot satisfy this assertion.
        XCTAssertFalse(notReadDuringInvalidShape.isCurrent)
        XCTAssertFalse(notReadDuringInvalidShape.isInstalled(in: runtime))
        let current = try XCTUnwrap(root.captureSelectedContentPath(in: runtime))
        assertSelectedPath(current, physical: root, selected: selected, runtime: runtime)
    }

    func testCompletedRootActionKeepsSuccessWithoutInvokingItsReplacement() async throws {
        let root = ViewNode.selectedContentBoundary(role: .viewThatFits, child: ViewNode())
        let runtime = RetainedViewRuntime(root: root)
        defer { retireSelectedPathRuntime(runtime) }
        runtime.setRootSize(IntSize(width: 120, height: 40))
        var firstCalls = 0
        var replacementCalls = 0
        let replacement = selectedPathButton(runtime: runtime, label: "B") { replacementCalls += 1 }
        let first = selectedPathButton(runtime: runtime, label: "A") {
            firstCalls += 1
            root.setChildren([replacement])
        }
        root.setChildren([first])
        let original = try XCTUnwrap(root.captureSelectedContentPath(in: runtime))
        assertSelectedPath(original, physical: root, selected: first, runtime: runtime)
        let source = RuntimeUIAElementTreeSource(runtime: runtime)
        let initialSnapshot = try XCTUnwrap(source.uiaElementSnapshots().first)
        XCTAssertEqual(initialSnapshot.id, UIAProviderBridge.rootElementID)
        XCTAssertEqual(initialSnapshot.name, "A")

        // The admitted A action has completed successfully. A post-action path
        // change must neither rewrite that result nor dispatch B in this call.
        XCTAssertTrue(source.uiaInvokeDefaultAction(elementID: UIAProviderBridge.rootElementID))
        XCTAssertEqual(firstCalls, 1)
        XCTAssertEqual(replacementCalls, 0)
        XCTAssertTrue(root.children.first === replacement)
        XCTAssertTrue(replacement.parent === root)
        XCTAssertNil(first.parent)
        XCTAssertFalse(original.isCurrent)
        XCTAssertFalse(original.isInstalled(in: runtime))

        let current = try XCTUnwrap(root.captureSelectedContentPath(in: runtime))
        assertSelectedPath(current, physical: root, selected: replacement, runtime: runtime)
        XCTAssertTrue(source.uiaInvokeDefaultAction(elementID: UIAProviderBridge.rootElementID))
        XCTAssertEqual(firstCalls, 1)
        XCTAssertEqual(replacementCalls, 1)
    }
}

@MainActor
private func assertSelectedPath(
    _ path: RetainedSelectedContentPath, physical: ViewNode, selected: ViewNode,
    runtime: RetainedViewRuntime, file: StaticString = #filePath, line: UInt = #line
) {
    XCTAssertTrue(path.isCurrent, file: file, line: line)
    XCTAssertTrue(path.isInstalled(in: runtime), file: file, line: line)
    XCTAssertTrue(path.physicalRoot === physical, file: file, line: line)
    XCTAssertTrue(path.selectedNode === selected, file: file, line: line)
}

@MainActor
private func selectedPathButton(
    runtime: RetainedViewRuntime, label: String, action: @escaping () -> Void
) -> ViewNode {
    let button = Controls.button(
        runtime: runtime, frame: .zero, cornerRadius: 0,
        palette: SurfacePalette(idle: .gray, focused: .blue, pressed: .black), action: action)
    button.accessibilityLabel = label
    button.accessibilityTraits = .isButton
    return button
}

@MainActor
private func retireSelectedPathRuntime(_ runtime: RetainedViewRuntime) {
    runtime.stopRenderLifecycleCallbacks()
    runtime.cancelRenderLifecycleTasks()
    runtime.root.removeAllChildren()
}
