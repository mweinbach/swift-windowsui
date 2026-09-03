import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI

/// NEW, unexecuted tests for the separately proposed panel assembly API.
/// Reentry uses existing structural operations, onDismantlePlatformView,
/// and the original admission callback. No append or revocation hook is injected.
@MainActor
final class RetainedSelectedContentPanelAssemblyTests: XCTestCase {
    func testOwnedAssemblyKeepsPhysicalChildrenAndReadsOnlyFiniteSelectedValues() async throws {
        for depth in [0, 1, 2] {
            let selected = ViewNode(backgroundColor: .blue, preferredSize: Size(width: 30, height: 20))
            selected.backgroundGradient = assemblyGradient()
            selected.opacity = 0.25
            selected.layoutFillAxes = .horizontalOnly
            let physical = assemblyBoundary(around: selected, depth: depth)
            let fixed = ViewNode(preferredSize: Size(width: 10, height: 10))
            let paths = try assemblyPaths([physical, fixed])
            let relative = try XCTUnwrap(paths[0].captureConstructionSelection())
            let assembly = try XCTUnwrap(
                RetainedSelectedContentPanelAssembly(sources: [physical, fixed], selectedContentPaths: paths))

            let panel = try XCTUnwrap(assembly.makePanel(preferredSize: Size(width: 30, height: 20)))

            assertAssemblyChildren(panel, [physical, fixed])
            XCTAssertNil(panel.selectedContentRole)
            XCTAssertNil(panel.parent)
            XCTAssertFalse(paths[0].isCurrent)
            XCTAssertFalse(paths[1].isCurrent)
            XCTAssertTrue(relative.isCurrent, "Relative selection remains metadata, not this assembly's authority")
            let style = try XCTUnwrap(assembly.backgroundStyle(at: 0))
            XCTAssertEqual(style.color, .blue)
            XCTAssertEqual(style.gradient, assemblyGradient())
            XCTAssertEqual(style.opacity, 0.25)
            XCTAssertEqual(assembly.layoutFillAxes(), .horizontalOnly)
            XCTAssertNil(panel.backgroundColor, "Reading values must not copy them to the panel")
            XCTAssertNil(panel.backgroundGradient)
            XCTAssertEqual(panel.layoutFillAxes, LayoutFillAxes())
            XCTAssertEqual(selected.opacity, 0.25)
            XCTAssertEqual(selected.layoutFillAxes, .horizontalOnly)
            if depth > 0 {
                XCTAssertEqual(physical.opacity, 1)
                XCTAssertEqual(physical.layoutFillAxes, LayoutFillAxes())
            }

            XCTAssertNil(assembly.makePanel(), "The original slots can only be consumed once")
            assertAssemblyChildren(panel, [physical, fixed])
        }
    }

    func testDetachedSourceCleanupPrecedesPostPanelDataReadInTheOriginalOrder() async throws {
        let selected = ViewNode(backgroundColor: .red, preferredSize: Size(width: 30, height: 20))
        selected.layoutFillAxes = .horizontalOnly
        let background = assemblyBoundary(around: selected, depth: 1)
        let base = ViewNode(preferredSize: Size(width: 30, height: 20))
        let tail = ViewNode()
        let staging = ViewNode(children: [base, tail])
        var events: [String] = []
        var observedPanel: ViewNode?
        base.onDismantlePlatformView = { node in
            events.append("base.dismantle")
            XCTAssertTrue(node === base)
            XCTAssertTrue(base.parent === staging, "The old parent store has not happened yet")
            assertAssemblyChildrenMembership(staging, [tail])
            guard let panel = background.parent else { return XCTFail("First slot was not appended") }
            observedPanel = panel
            assertAssemblyChildren(panel, [background])
            selected.backgroundColor = .blue
            selected.backgroundGradient = assemblyGradient()
            selected.opacity = 0.25
            selected.layoutFillAxes = .verticalOnly
        }
        tail.onDismantlePlatformView = { _ in
            events.append("tail.dismantle")
            XCTAssertTrue(tail.parent === staging)
            XCTAssertTrue(staging.children.isEmpty)
            if let panel = observedPanel { assertAssemblyChildren(panel, [background, base]) }
        }
        defer {
            base.onDismantlePlatformView = nil
            tail.onDismantlePlatformView = nil
        }
        let assembly = try makeAssembly([background, base, tail])

        let panel = try XCTUnwrap(assembly.makePanel())

        XCTAssertEqual(events, ["base.dismantle", "tail.dismantle"])
        XCTAssertTrue(observedPanel === panel)
        XCTAssertTrue(staging.children.isEmpty)
        assertAssemblyChildren(panel, [background, base, tail])
        let style = try XCTUnwrap(assembly.backgroundStyle(at: 0))
        XCTAssertEqual(style.color, .blue)
        XCTAssertEqual(style.gradient, assemblyGradient())
        XCTAssertEqual(style.opacity, 0.25)
        XCTAssertEqual(assembly.layoutFillAxes(), .verticalOnly)
    }

    func testSamePanelSourceABAInCleanupFinishesDepartureButNeverAddsTheNextSlot() async throws {
        let selected = ViewNode(backgroundColor: .blue)
        let first = assemblyBoundary(around: selected, depth: 1)
        let base = ViewNode()
        let tail = ViewNode()
        let staging = ViewNode(children: [base, tail])
        let paths = try assemblyPaths([first, base, tail])
        let relative = try XCTUnwrap(paths[0].captureConstructionSelection())
        var observedPanel: ViewNode?
        var dismantles: [String] = []
        base.onDismantlePlatformView = { _ in
            dismantles.append("base")
            guard let panel = first.parent else { return XCTFail("Missing accepted prefix") }
            observedPanel = panel
            assertAssemblyChildren(panel, [first])
            XCTAssertTrue(base.parent === staging)
            assertAssemblyChildrenMembership(staging, [tail])
            first.removeFromParent()
            panel.addChild(first)
            panel.backgroundColor = .green
            assertAssemblyChildren(panel, [first])
        }
        tail.onDismantlePlatformView = { _ in dismantles.append("tail") }
        defer {
            base.onDismantlePlatformView = nil
            tail.onDismantlePlatformView = nil
        }
        let assembly = try XCTUnwrap(
            RetainedSelectedContentPanelAssembly(sources: [first, base, tail], selectedContentPaths: paths))

        XCTAssertNil(assembly.makePanel())

        let panel = try XCTUnwrap(observedPanel)
        XCTAssertEqual(dismantles, ["base"])
        XCTAssertNil(base.parent, "The already claimed old departure must finish")
        assertAssemblyChildren(staging, [tail])
        assertAssemblyChildren(panel, [first])
        XCTAssertEqual(panel.backgroundColor, .green)
        XCTAssertTrue(relative.isCurrent, "An unchanged relative chain cannot authorize the rejected assembly")
        XCTAssertFalse(paths[0].isCurrent)
        XCTAssertNil(assembly.backgroundStyle(at: 0))
        XCTAssertNil(assembly.layoutFillAxes())
        XCTAssertNil(assembly.makePanel(), "Refusal cannot retry or recreate the old slots")
        XCTAssertEqual(dismantles, ["base"])
        assertAssemblyChildren(panel, [first])
        assertAssemblyChildren(staging, [tail])
    }

    func testPanelPublishDetachABAInCleanupCannotResumeAssemblyFromMatchingPointers() async throws {
        let first = assemblyBoundary(around: ViewNode(backgroundColor: .blue), depth: 1)
        let base = ViewNode()
        let tail = ViewNode()
        let staging = ViewNode(children: [base, tail])
        var observedPanel: ViewNode?
        var publishedRuntime: RetainedViewRuntime?
        var dismantles: [String] = []
        base.onDismantlePlatformView = { _ in
            dismantles.append("base")
            guard let panel = first.parent else { return XCTFail("Missing accepted prefix") }
            observedPanel = panel
            publishedRuntime = publishThenDetachAssemblyPanel(panel)
            assertAssemblyChildren(panel, [first])
            XCTAssertNil(panel.parent)
        }
        tail.onDismantlePlatformView = { _ in dismantles.append("tail") }
        defer {
            base.onDismantlePlatformView = nil
            tail.onDismantlePlatformView = nil
            stopAssemblyRuntime(publishedRuntime)
        }
        let assembly = try makeAssembly([first, base, tail])

        XCTAssertNil(assembly.makePanel())

        let panel = try XCTUnwrap(observedPanel)
        XCTAssertNotNil(publishedRuntime)
        XCTAssertEqual(dismantles, ["base"])
        XCTAssertNil(base.parent)
        assertAssemblyChildren(staging, [tail])
        assertAssemblyChildren(panel, [first])
        XCTAssertNotNil(panel.captureSelectedContentConstructionPath(), "Current detached shape was restored")
        XCTAssertNil(assembly.backgroundStyle(at: 0))
        XCTAssertNil(assembly.layoutFillAxes())
    }

    func testAnEmptyPanelStillRejectsItsOwnPublicationAndAttachmentABA() async throws {
        for publish in [false, true] {
            let assembly = try makeAssembly([])
            let panel = try XCTUnwrap(assembly.makePanel())
            var publishedRuntime: RetainedViewRuntime?
            defer { stopAssemblyRuntime(publishedRuntime) }
            if publish {
                publishedRuntime = publishThenDetachAssemblyPanel(panel)
            } else {
                let temporaryParent = ViewNode()
                temporaryParent.addChild(panel)
                panel.removeFromParent()
                XCTAssertTrue(temporaryParent.children.isEmpty)
            }
            XCTAssertNil(panel.parent)
            XCTAssertTrue(panel.children.isEmpty)
            XCTAssertNotNil(panel.captureSelectedContentConstructionPath())
            // No assembly getter ran during either invalid intermediate shape,
            // and there is no source path whose revocation could mask this bug.
            XCTAssertNil(assembly.layoutFillAxes())
        }
    }

    func testPanelChildListABAIsRejectedWhileEveryOriginalSelectedParentStaysTheSame() async throws {
        let selected = ViewNode(backgroundColor: .blue)
        let physical = assemblyBoundary(around: selected, depth: 2)
        let paths = try assemblyPaths([physical])
        let relative = try XCTUnwrap(paths[0].captureConstructionSelection())
        let assembly = try XCTUnwrap(
            RetainedSelectedContentPanelAssembly(sources: [physical], selectedContentPaths: paths))
        let panel = try XCTUnwrap(assembly.makePanel())
        let originalSelectedParent = selected.parent
        let extra = ViewNode()

        panel.addChild(extra)
        extra.removeFromParent()

        assertAssemblyChildren(panel, [physical])
        XCTAssertTrue(selected.parent === originalSelectedParent)
        XCTAssertTrue(relative.isCurrent)
        XCTAssertNil(extra.parent)
        XCTAssertNil(assembly.backgroundStyle(at: 0))
        XCTAssertNil(assembly.layoutFillAxes())
    }

    func testNestedSelectionChildListABACannotBeBorrowedAfterAssembly() async throws {
        let selected = ViewNode(backgroundColor: .blue)
        let inner = assemblyBoundary(around: selected, depth: 1)
        let outer = assemblyBoundary(around: inner, depth: 1)
        let assembly = try makeAssembly([outer])
        let panel = try XCTUnwrap(assembly.makePanel())
        let extra = ViewNode()

        inner.addChild(extra)
        extra.removeFromParent()

        assertAssemblyChildren(panel, [outer])
        assertAssemblyChildren(outer, [inner])
        assertAssemblyChildren(inner, [selected])
        XCTAssertNil(assembly.backgroundStyle(at: 0))
        XCTAssertNil(assembly.layoutFillAxes())
    }

    func testUnownedAttachmentRevocationRejectsWithoutAParentOrChildTableChange() async throws {
        for revokeSelected in [false, true] {
            let selected = ViewNode(backgroundColor: .blue)
            let physical = assemblyBoundary(around: selected, depth: 1)
            let assembly = try makeAssembly([physical])
            let panel = try XCTUnwrap(assembly.makePanel())
            let originalSelectedParent = selected.parent

            // This existing internal native writer is not an injected hook.
            // Nil must not inherit the original slot's acknowledgement rights.
            let target = revokeSelected ? selected : physical
            target.revokeLazyListAttachmentProofs(removalWrite: nil)

            assertAssemblyChildren(panel, [physical])
            XCTAssertTrue(selected.parent === originalSelectedParent)
            XCTAssertNil(assembly.backgroundStyle(at: 0))
            XCTAssertNil(assembly.layoutFillAxes())
        }
    }

    func testOriginalAdmissionRefusalDuringCleanupIsPermanentAndStopsLaterSlots() async throws {
        let first = ViewNode(backgroundColor: .blue)
        let base = ViewNode()
        let tail = ViewNode()
        let staging = ViewNode(children: [base, tail])
        var admitted = true
        var observedPanel: ViewNode?
        var dismantles: [String] = []
        base.onDismantlePlatformView = { _ in
            dismantles.append("base")
            observedPanel = first.parent
            admitted = false
        }
        tail.onDismantlePlatformView = { _ in dismantles.append("tail") }
        defer {
            base.onDismantlePlatformView = nil
            tail.onDismantlePlatformView = nil
        }
        let assembly = try makeAssembly([first, base, tail], admission: { admitted })

        XCTAssertNil(assembly.makePanel())
        admitted = true

        XCTAssertEqual(dismantles, ["base"])
        XCTAssertNil(base.parent)
        assertAssemblyChildren(staging, [tail])
        assertAssemblyChildren(try XCTUnwrap(observedPanel), [first])
        XCTAssertNil(assembly.backgroundStyle(at: 0))
        XCTAssertNil(assembly.layoutFillAxes())
    }

    func testPostPanelAdmissionCallbackCannotRenewABorrowAfterItsOwnABA() async throws {
        for readsFill in [false, true] {
            let physical = assemblyBoundary(around: ViewNode(backgroundColor: .blue), depth: 1)
            var onAdmission: (@MainActor () -> Void)?
            var admissionEffects = 0
            let assembly = try makeAssembly([physical]) {
                let callback = onAdmission
                onAdmission = nil
                callback?()
                return true
            }
            let panel = try XCTUnwrap(assembly.makePanel())
            onAdmission = {
                admissionEffects += 1
                let extra = ViewNode()
                panel.addChild(extra)
                extra.removeFromParent()
            }

            if readsFill {
                XCTAssertNil(assembly.layoutFillAxes())
            } else {
                XCTAssertNil(assembly.backgroundStyle(at: 0))
            }

            XCTAssertEqual(admissionEffects, 1)
            assertAssemblyChildren(panel, [physical])
            XCTAssertNil(assembly.backgroundStyle(at: 0))
            XCTAssertNil(assembly.layoutFillAxes())
        }
    }

    func testOnlyOriginalCurrentConstructionPathsForAnInjectiveForestAreAccepted() async throws {
        let first = ViewNode()
        let second = ViewNode()
        let paths = try assemblyPaths([first, second])
        XCTAssertNil(RetainedSelectedContentPanelAssembly(sources: [first], selectedContentPaths: paths))
        XCTAssertNil(RetainedSelectedContentPanelAssembly(sources: [first], selectedContentPaths: [paths[1]]))
        XCTAssertNil(
            RetainedSelectedContentPanelAssembly(sources: [first, first], selectedContentPaths: [paths[0], paths[0]]))
        XCTAssertNil(first.parent)
        XCTAssertNil(second.parent)

        let parent = ViewNode(children: [first])
        XCTAssertFalse(paths[0].isCurrent)
        XCTAssertNil(RetainedSelectedContentPanelAssembly(sources: [first], selectedContentPaths: [paths[0]]))
        assertAssemblyChildren(parent, [first])
        let overlapping = try assemblyPaths([parent, first])
        XCTAssertNil(
            RetainedSelectedContentPanelAssembly(sources: [parent, first], selectedContentPaths: overlapping))
        assertAssemblyChildren(parent, [first])

        let runtime = RetainedViewRuntime(root: parent)
        defer { stopAssemblyRuntime(runtime) }
        let installed = try XCTUnwrap(first.captureSelectedContentPath(in: runtime))
        XCTAssertTrue(installed.isCurrent)
        XCTAssertNil(RetainedSelectedContentPanelAssembly(sources: [first], selectedContentPaths: [installed]))
        assertAssemblyChildren(parent, [first])
    }

    func testFinalConstructionCheckIsOneShotAndSealsFurtherDataBorrowing() async throws {
        let selected = ViewNode(backgroundColor: .blue)
        let physical = assemblyBoundary(around: selected, depth: 1)
        let assembly = try makeAssembly([physical])
        let panel = try XCTUnwrap(assembly.makePanel())
        XCTAssertNotNil(assembly.backgroundStyle(at: 0))

        XCTAssertTrue(assembly.finishConstruction())

        XCTAssertFalse(assembly.finishConstruction())
        XCTAssertNil(assembly.backgroundStyle(at: 0))
        XCTAssertNil(assembly.layoutFillAxes())
        assertAssemblyChildren(panel, [physical])
        XCTAssertTrue(physical.children.first === selected)
        XCTAssertNil(panel.parent)
    }

    func testFinalConstructionCheckRejectsABAFromItsOriginalAdmissionCallback() async throws {
        var onAdmission: (@MainActor () -> Void)?
        var effects = 0
        let assembly = try makeAssembly([]) {
            let callback = onAdmission
            onAdmission = nil
            callback?()
            return true
        }
        let panel = try XCTUnwrap(assembly.makePanel())
        onAdmission = {
            effects += 1
            let extra = ViewNode()
            panel.addChild(extra)
            extra.removeFromParent()
        }

        XCTAssertFalse(assembly.finishConstruction())

        XCTAssertEqual(effects, 1)
        XCTAssertFalse(assembly.finishConstruction())
        XCTAssertNil(assembly.layoutFillAxes())
        XCTAssertNil(panel.parent)
        XCTAssertTrue(panel.children.isEmpty)
    }
}

@MainActor
private func makeAssembly(
    _ sources: [ViewNode], admission: @escaping @MainActor () -> Bool = { true }
) throws -> RetainedSelectedContentPanelAssembly {
    let paths = try assemblyPaths(sources)
    return try XCTUnwrap(
        RetainedSelectedContentPanelAssembly(
            sources: sources, selectedContentPaths: paths, admission: admission))
}

@MainActor
private func assemblyPaths(_ sources: [ViewNode]) throws -> [RetainedSelectedContentPath] {
    try sources.map { try XCTUnwrap($0.captureSelectedContentConstructionPath()) }
}

@MainActor
private func assemblyBoundary(around selected: ViewNode, depth: Int) -> ViewNode {
    var physical = selected
    for _ in 0..<depth { physical = ViewNode.selectedContentBoundary(role: .viewThatFits, child: physical) }
    return physical
}

@MainActor
private func assertAssemblyChildren(
    _ parent: ViewNode, _ expected: [ViewNode], file: StaticString = #filePath, line: UInt = #line
) {
    assertAssemblyChildrenMembership(parent, expected, file: file, line: line)
    for child in expected { XCTAssertTrue(child.parent === parent, file: file, line: line) }
}

@MainActor
private func assertAssemblyChildrenMembership(
    _ parent: ViewNode, _ expected: [ViewNode], file: StaticString = #filePath, line: UInt = #line
) {
    XCTAssertEqual(parent.children.count, expected.count, file: file, line: line)
    XCTAssertTrue(zip(parent.children, expected).allSatisfy { pair in pair.0 === pair.1 }, file: file, line: line)
}

@MainActor
private func publishThenDetachAssemblyPanel(_ panel: ViewNode) -> RetainedViewRuntime {
    let runtime = RetainedViewRuntime(root: panel)
    XCTAssertTrue(runtime.root === panel)
    XCTAssertNotNil(panel.captureSelectedContentPath(in: runtime))
    let temporaryParent = ViewNode()
    temporaryParent.addChild(panel)
    panel.removeFromParent()
    XCTAssertTrue(temporaryParent.children.isEmpty)
    XCTAssertNil(panel.parent)
    XCTAssertNotNil(panel.captureSelectedContentConstructionPath())
    return runtime
}

@MainActor
private func stopAssemblyRuntime(_ runtime: RetainedViewRuntime?) {
    runtime?.stopRenderLifecycleCallbacks()
    runtime?.cancelRenderLifecycleTasks()
}

private func assemblyGradient() -> GradientType {
    .linear(LinearGradient(startColor: .red, endColor: .blue))
}
