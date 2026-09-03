import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI

/// This relative selection records only the actual selected chain. It does
/// not install its construction path or authorize any native publication.
@MainActor
final class RetainedSelectedContentConstructionSelectionTests: XCTestCase {
    func testMintedSelectionSurvivesAssemblyAndInstallationWhileItsStrictPathExpires() async throws {
        for depth in [0, 1, 2] {
            let selected = ViewNode(preferredSize: Size(width: 30, height: 20))
            let physical = constructionSelectionBoundary(around: selected, depth: depth)
            let construction = try XCTUnwrap(physical.captureSelectedContentConstructionPath())
            XCTAssertTrue(construction.isCurrent)
            let selection = try XCTUnwrap(construction.captureConstructionSelection())
            assertConstructionSelection(selection, physical: physical, selected: selected)

            // Minting consumes only extraction, not the strict path's current
            // physical facts. The same path cannot mint a second selection.
            XCTAssertTrue(construction.isCurrent)
            XCTAssertNil(construction.captureConstructionSelection())
            XCTAssertTrue(construction.isCurrent)
            XCTAssertNil(physical.parent)

            let panel = ViewNode()
            panel.addChild(physical)
            XCTAssertNil(panel.selectedContentRole)
            XCTAssertEqual(panel.children.count, 1)
            XCTAssertTrue(panel.children.first === physical)
            XCTAssertTrue(physical.parent === panel)
            XCTAssertFalse(construction.isCurrent, "Normal detached assembly changes the strict containing path")
            assertConstructionSelection(selection, physical: physical, selected: selected)
            XCTAssertNil(construction.captureConstructionSelection())

            let runtime = RetainedViewRuntime(root: panel)
            defer { retireConstructionSelectionRuntime(runtime) }
            XCTAssertTrue(runtime.root === panel)
            XCTAssertTrue(physical.parent === panel)
            XCTAssertFalse(construction.isCurrent)
            XCTAssertFalse(construction.isInstalled(in: runtime))
            assertConstructionSelection(selection, physical: physical, selected: selected)
            XCTAssertNil(construction.captureConstructionSelection())
            if depth == 0 {
                XCTAssertTrue(selection.physicalRoot === selection.selectedNode)
                XCTAssertTrue(selected.parent === panel)
            } else {
                XCTAssertFalse(selection.physicalRoot === selection.selectedNode)
                XCTAssertNotNil(selected.parent)
                XCTAssertTrue(selected.parent !== panel)
            }
        }
    }

    func testNestedCardinalityABADoesNotReviveAnUnreadRelativeSelection() async throws {
        let selected = ViewNode(preferredSize: Size(width: 30, height: 20))
        let inner = ViewNode.selectedContentBoundary(role: .viewThatFits, child: selected)
        let outer = ViewNode.selectedContentBoundary(role: .viewThatFits, child: inner)
        // These are two independent original paths, each captured and minted
        // once before any assembly or cardinality change.
        let observedPath = try XCTUnwrap(outer.captureSelectedContentConstructionPath())
        let unreadPath = try XCTUnwrap(outer.captureSelectedContentConstructionPath())
        let observed = try XCTUnwrap(observedPath.captureConstructionSelection())
        let notReadDuringInvalidShape = try XCTUnwrap(unreadPath.captureConstructionSelection())
        XCTAssertNil(observedPath.captureConstructionSelection())
        XCTAssertNil(unreadPath.captureConstructionSelection())
        assertConstructionSelection(observed, physical: outer, selected: selected)
        assertConstructionSelection(notReadDuringInvalidShape, physical: outer, selected: selected)

        let panel = ViewNode()
        panel.addChild(outer)
        XCTAssertTrue(outer.parent === panel)
        XCTAssertFalse(observedPath.isCurrent)
        XCTAssertFalse(unreadPath.isCurrent)
        assertConstructionSelection(observed, physical: outer, selected: selected)
        assertConstructionSelection(notReadDuringInvalidShape, physical: outer, selected: selected)

        let extra = ViewNode(preferredSize: Size(width: 5, height: 5))
        inner.addChild(extra)
        XCTAssertEqual(outer.children.count, 1)
        XCTAssertTrue(outer.children.first === inner)
        XCTAssertTrue(inner.parent === outer)
        XCTAssertEqual(inner.children.count, 2)
        XCTAssertTrue(inner.children.first === selected)
        XCTAssertTrue(selected.parent === inner, "The selected child never changes parent")
        XCTAssertTrue(extra.parent === inner)
        XCTAssertFalse(observed.isCurrent)

        extra.removeFromParent()
        XCTAssertEqual(inner.children.count, 1)
        XCTAssertTrue(inner.children.first === selected)
        XCTAssertTrue(selected.parent === inner)
        XCTAssertTrue(inner.parent === outer)
        XCTAssertTrue(outer.parent === panel)
        XCTAssertNil(extra.parent)
        XCTAssertFalse(observed.isCurrent)
        // This second witness was never read during the malformed shape.
        // Remembering only a failure observed by a getter cannot satisfy it.
        XCTAssertFalse(notReadDuringInvalidShape.isCurrent)
        XCTAssertNil(observedPath.captureConstructionSelection())
        XCTAssertNil(unreadPath.captureConstructionSelection())
    }

    func testFirstExtractionFromExpiredConstructionAndCurrentLivePathsIsRejected() async throws {
        for depth in [0, 1, 2] {
            let selected = ViewNode(preferredSize: Size(width: 30, height: 20))
            let physical = constructionSelectionBoundary(around: selected, depth: depth)
            let expired = try XCTUnwrap(physical.captureSelectedContentConstructionPath())
            XCTAssertTrue(expired.isCurrent)
            let panel = ViewNode()
            panel.addChild(physical)
            XCTAssertTrue(physical.parent === panel)
            XCTAssertFalse(expired.isCurrent)
            // This is the first extraction attempt from this path. Rejection
            // therefore cannot be explained by an earlier extraction alone.
            XCTAssertNil(expired.captureConstructionSelection())

            let runtime = RetainedViewRuntime(root: panel)
            defer { retireConstructionSelectionRuntime(runtime) }
            XCTAssertFalse(expired.isCurrent)
            XCTAssertFalse(expired.isInstalled(in: runtime))
            XCTAssertNil(expired.captureConstructionSelection())
            let live = try XCTUnwrap(physical.captureSelectedContentPath(in: runtime))
            XCTAssertTrue(live.isCurrent)
            XCTAssertTrue(live.isInstalled(in: runtime))
            XCTAssertTrue(live.physicalRoot === physical)
            XCTAssertTrue(live.selectedNode === selected)
            XCTAssertNil(live.captureConstructionSelection(), "An installed path cannot mint construction selection")
            XCTAssertTrue(live.isCurrent)
            XCTAssertTrue(live.isInstalled(in: runtime))
            XCTAssertNil(live.captureConstructionSelection())
        }
    }
}

@MainActor
private func constructionSelectionBoundary(around selected: ViewNode, depth: Int) -> ViewNode {
    var physical = selected
    for _ in 0..<depth {
        physical = ViewNode.selectedContentBoundary(role: .viewThatFits, child: physical)
    }
    return physical
}

@MainActor
private func assertConstructionSelection(
    _ selection: RetainedSelectedContentConstructionSelection,
    physical: ViewNode, selected: ViewNode,
    file: StaticString = #filePath, line: UInt = #line
) {
    XCTAssertTrue(selection.isCurrent, file: file, line: line)
    XCTAssertTrue(selection.physicalRoot === physical, file: file, line: line)
    XCTAssertTrue(selection.selectedNode === selected, file: file, line: line)
}

@MainActor
private func retireConstructionSelectionRuntime(_ runtime: RetainedViewRuntime) {
    runtime.stopRenderLifecycleCallbacks()
    runtime.cancelRenderLifecycleTasks()
    runtime.root.removeAllChildren()
}
