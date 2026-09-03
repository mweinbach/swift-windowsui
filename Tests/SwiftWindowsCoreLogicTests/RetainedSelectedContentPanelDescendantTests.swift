import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI

/// NEW source-only regressions for detached panel receiver eligibility.
/// The callback case tests metadata refusal after publication and runtime
/// release. It does not assert protection of a descendant left installed
/// across the earlier, unchanged markSubtreeDisappeared/group-claim walk.
@MainActor
final class RetainedSelectedContentPanelDescendantTests: XCTestCase {
    func testAnInitiallyInstalledDescendantRefusesBeforeAdmissionOrDeparture() async throws {
        for depth in [0, 1, 2] {
            let descendant = ViewNode(preferredSize: Size(width: 10, height: 10))
            let selected = ViewNode(children: [descendant])
            let physical = panelDescendantBoundary(around: selected, depth: depth)
            let staging = ViewNode(children: [physical])
            let liveRuntime = RetainedViewRuntime(root: descendant)
            var admissionCalls = 0
            var dismantles: [String] = []
            physical.onDismantlePlatformView = { _ in dismantles.append("source") }
            descendant.onDismantlePlatformView = { _ in dismantles.append("descendant") }
            defer {
                physical.onDismantlePlatformView = nil
                descendant.onDismantlePlatformView = nil
                liveRuntime.stopRenderLifecycleCallbacks()
                liveRuntime.cancelRenderLifecycleTasks()
            }
            let originalInstalled = try XCTUnwrap(descendant.captureSelectedContentPath(in: liveRuntime))
            let originalConstruction = try XCTUnwrap(physical.captureSelectedContentConstructionPath())
            XCTAssertTrue(originalInstalled.isCurrent)
            XCTAssertTrue(originalConstruction.isCurrent, "The selected path does not inspect ordinary descendants")
            XCTAssertTrue(liveRuntime.root === descendant)
            XCTAssertTrue(descendant.parent === selected, "Runtime.init does not remove the old physical parent")

            let assembly = RetainedSelectedContentPanelAssembly(
                sources: [physical], selectedContentPaths: [originalConstruction],
                admission: {
                    admissionCalls += 1
                    return true
                })

            XCTAssertNil(assembly, "A detached selected root cannot authorize its installed descendant")
            XCTAssertEqual(admissionCalls, 0, "Reject mixed ownership before any authored admission callback")
            XCTAssertTrue(dismantles.isEmpty, "No source departure has been claimed or started")
            XCTAssertTrue(originalInstalled.isCurrent)
            XCTAssertTrue(originalConstruction.isCurrent)
            XCTAssertTrue(descendant.retainedLazyListRuntime === liveRuntime)
            XCTAssertTrue(liveRuntime.root === descendant)
            assertPanelDescendantChildren(staging, [physical])
            assertPanelDescendantChildren(selected, [descendant])
        }
    }

    func testDescendantPublicationThenRuntimeReleaseRefusesMetadataAfterOwedCleanup() async throws {
        for depth in [0, 1, 2] {
            let prefix = ViewNode(backgroundColor: .blue)
            let descendant = ViewNode(preferredSize: Size(width: 10, height: 10))
            let selected = ViewNode(children: [descendant])
            let source = panelDescendantBoundary(around: selected, depth: depth)
            let tail = ViewNode()
            let staging = ViewNode(children: [source, tail])
            let sources = [prefix, source, tail]
            let paths = try sources.map { try XCTUnwrap($0.captureSelectedContentConstructionPath()) }
            let originalSelection = try XCTUnwrap(paths[1].captureConstructionSelection())
            var dismantles: [String] = []
            var publications = 0
            var acceptedPrefix: ViewNode?
            source.onDismantlePlatformView = { node in
                dismantles.append("source")
                XCTAssertTrue(node === source)
                XCTAssertTrue(source.parent === staging, "The source parent-nil write is still owed")
                assertPanelDescendantChildrenMembership(staging, [tail])
                guard let panel = prefix.parent else { return XCTFail("The first slot was not accepted") }
                acceptedPrefix = panel
                assertPanelDescendantChildren(panel, [prefix])
                XCTAssertNil(descendant.retainedLazyListRuntime)
                assertPanelDescendantChildren(selected, [descendant])

                let releasedRuntime = publishAndReleasePanelDescendant(descendant)
                publications += 1

                XCTAssertNil(releasedRuntime.runtime, "No test reference keeps the temporary runtime installed")
                XCTAssertNil(descendant.retainedLazyListRuntime)
                assertPanelDescendantChildren(selected, [descendant])
                XCTAssertTrue(originalSelection.isCurrent, "The original selected chain was never replaced")
            }
            tail.onDismantlePlatformView = { _ in dismantles.append("tail") }
            defer {
                source.onDismantlePlatformView = nil
                tail.onDismantlePlatformView = nil
            }
            let assembly = try XCTUnwrap(
                RetainedSelectedContentPanelAssembly(sources: sources, selectedContentPaths: paths))

            XCTAssertNil(assembly.makePanel())

            XCTAssertEqual(publications, 1)
            XCTAssertEqual(dismantles, ["source"], "The next construction slot must remain untouched")
            XCTAssertNil(source.parent, "The already claimed original source departure still finishes")
            XCTAssertNil(source.retainedLazyListRuntime)
            XCTAssertNil(descendant.retainedLazyListRuntime)
            assertPanelDescendantChildren(staging, [tail])
            assertPanelDescendantChildren(selected, [descendant])
            let panel = try XCTUnwrap(acceptedPrefix)
            assertPanelDescendantChildren(panel, [prefix])
            XCTAssertNil(panel.parent)
            XCTAssertTrue(originalSelection.isCurrent)
            XCTAssertNil(assembly.backgroundStyle(at: 0))
            XCTAssertNil(assembly.layoutFillAxes())
            XCTAssertFalse(assembly.finishConstruction())
            XCTAssertNil(assembly.makePanel(), "Refusal cannot retry the original slots")
            XCTAssertEqual(publications, 1)
            XCTAssertEqual(dismantles, ["source"])
            assertPanelDescendantChildren(panel, [prefix])
            assertPanelDescendantChildren(staging, [tail])
        }
    }
}

@MainActor
private final class PanelDescendantWeakRuntime {
    weak var runtime: RetainedViewRuntime?
}

/// Runtime publication changes only this descendant's runtime attachment.
/// Returning a weak holder releases the sole strong runtime reference without
/// removing/reinserting the descendant or changing its parent's child table.
@MainActor
private func publishAndReleasePanelDescendant(_ node: ViewNode) -> PanelDescendantWeakRuntime {
    let result = PanelDescendantWeakRuntime()
    let runtime = RetainedViewRuntime(root: node)
    result.runtime = runtime
    XCTAssertTrue(runtime.root === node)
    XCTAssertTrue(node.retainedLazyListRuntime === runtime)
    XCTAssertNotNil(node.captureSelectedContentPath(in: runtime))
    runtime.stopRenderLifecycleCallbacks()
    runtime.cancelRenderLifecycleTasks()
    return result
}

@MainActor
private func panelDescendantBoundary(around selected: ViewNode, depth: Int) -> ViewNode {
    var physical = selected
    for _ in 0..<depth { physical = ViewNode.selectedContentBoundary(role: .viewThatFits, child: physical) }
    return physical
}

@MainActor
private func assertPanelDescendantChildren(
    _ parent: ViewNode, _ expected: [ViewNode], file: StaticString = #filePath, line: UInt = #line
) {
    assertPanelDescendantChildrenMembership(parent, expected, file: file, line: line)
    for child in expected { XCTAssertTrue(child.parent === parent, file: file, line: line) }
}

@MainActor
private func assertPanelDescendantChildrenMembership(
    _ parent: ViewNode, _ expected: [ViewNode], file: StaticString = #filePath, line: UInt = #line
) {
    XCTAssertEqual(parent.children.count, expected.count, file: file, line: line)
    XCTAssertTrue(zip(parent.children, expected).allSatisfy { pair in pair.0 === pair.1 }, file: file, line: line)
}
