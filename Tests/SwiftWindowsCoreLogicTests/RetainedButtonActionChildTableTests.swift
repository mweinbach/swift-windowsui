import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI

@MainActor
final class RetainedButtonActionChildTableTests: XCTestCase {
    func testCapturedEmptySingleTwoAndWideTablesKeepExactValidationCounts() async throws {
        for count in [0, 1, 2, 17] {
            let fixture = try ButtonChildTableFixture(childCount: count)
            defer { fixture.finish() }
            let before = try XCTUnwrap(fixture.adoption.validationSnapshot)
            XCTAssertEqual(before.witnessCount, count + 2)
            XCTAssertEqual(before.checkCount, 0)
            XCTAssertEqual(before.witnessVisitCount, 0)

            for _ in 0..<7 { XCTAssertTrue(fixture.adoption.isCurrent, "count \(count)") }

            let after = try XCTUnwrap(fixture.adoption.validationSnapshot)
            XCTAssertEqual(after.witnessCount, count + 2)
            XCTAssertEqual(after.checkCount, 7)
            XCTAssertEqual(after.witnessVisitCount, UInt64(7 * (count + 2)))
            XCTAssertFalse(after.didOverflow)
            XCTAssertEqual(before.checkCount, 0, "An earlier scalar snapshot stays unchanged")
            XCTAssertEqual(before.witnessVisitCount, 0)
        }
    }

    func testUnrecordedCountTransitionsRejectEveryChildTableShape() async throws {
        for beforeCount in [0, 1, 2, 7] {
            for afterCount in [0, 1, 2, 7] where beforeCount != afterCount {
                let fixture = try ButtonChildTableFixture(childCount: 0)
                defer { fixture.finish() }
                let original = (0..<beforeCount).map { _ in ViewNode() }
                let replacement = (0..<afterCount).map { _ in ViewNode() }
                let firstWrite = fixture.parent.setChildren(original)
                let firstRecorded = fixture.adoption.recordChildrenWrite(on: fixture.parent)
                XCTAssertTrue(firstWrite.completed)
                XCTAssertTrue(firstRecorded)
                XCTAssertTrue(fixture.adoption.isCurrent)

                XCTAssertTrue(fixture.parent.setChildren(replacement).completed)

                XCTAssertEqual(fixture.parent.children.count, afterCount)
                XCTAssertNotEqual(
                    fixture.parent.children.map(ObjectIdentifier.init), original.map(ObjectIdentifier.init))
                fixture.assertOriginalNonChildFacetsCurrent()
                XCTAssertFalse(fixture.adoption.isCurrent, "\(beforeCount) -> \(afterCount)")
                withExtendedLifetime(original) {}
            }
        }
    }

    func testUnrecordedReplacementAndReorderRejectEqualCountTables() async throws {
        for count in [1, 2, 7] {
            for reorders in [false, true] where !reorders || count > 1 {
                let fixture = try ButtonChildTableFixture(childCount: 0)
                defer { fixture.finish() }
                let original = (0..<count).map { _ in ViewNode() }
                let originalIDs = original.map(ObjectIdentifier.init)
                let firstWrite = fixture.parent.setChildren(original)
                let firstRecorded = fixture.adoption.recordChildrenWrite(on: fixture.parent)
                XCTAssertTrue(firstWrite.completed)
                XCTAssertTrue(firstRecorded)
                var changed = original
                if reorders {
                    changed.swapAt(0, count - 1)
                } else {
                    changed[count - 1] = ViewNode()
                }

                XCTAssertTrue(fixture.parent.setChildren(changed).completed)

                XCTAssertEqual(fixture.parent.children.count, count)
                XCTAssertNotEqual(fixture.parent.children.map(ObjectIdentifier.init), originalIDs)
                fixture.assertOriginalNonChildFacetsCurrent()
                XCTAssertFalse(fixture.adoption.isCurrent, "count \(count), reorder \(reorders)")
                withExtendedLifetime(original) {}
            }
        }
    }

    func testAuthorizedChildWritesAdvanceOnlyFreshPassiveTablesAcrossAllShapes() async throws {
        for firstCount in [0, 1, 2, 7] {
            for nextCount in [0, 1, 2, 7] {
                let fixture = try ButtonChildTableFixture(childCount: 0)
                defer { fixture.finish() }
                // Neither table's passive children belonged to the captured cohort.
                // This does not excuse a changed attachment on a captured child.
                let first = (0..<firstCount).map { _ in ViewNode() }
                let next = (0..<nextCount).map { _ in ViewNode() }
                XCTAssertTrue(fixture.adoption.isCurrent)
                let firstWrite = fixture.parent.setChildren(first)
                let firstRecorded = fixture.adoption.recordChildrenWrite(on: fixture.parent)
                XCTAssertTrue(firstWrite.completed)
                XCTAssertTrue(firstRecorded)
                let before = try XCTUnwrap(fixture.adoption.validationSnapshot)

                let nextWrite = fixture.parent.setChildren(next)
                let nextRecorded = fixture.adoption.recordChildrenWrite(on: fixture.parent)

                XCTAssertTrue(nextWrite.completed)
                XCTAssertTrue(nextRecorded, "\(firstCount) -> \(nextCount)")
                fixture.assertOriginalNonChildFacetsCurrent()
                XCTAssertEqual(fixture.parent.children.map(ObjectIdentifier.init), next.map(ObjectIdentifier.init))
                XCTAssertTrue(fixture.adoption.isCurrent)
                let after = try XCTUnwrap(fixture.adoption.validationSnapshot)
                XCTAssertEqual(after.witnessCount, 2, "A receipt does not enroll newly inserted nodes")
                XCTAssertEqual(after.checkCount - before.checkCount, 2)
                XCTAssertEqual(after.witnessVisitCount - before.witnessVisitCount, 4)
                XCTAssertFalse(after.didOverflow)
            }
        }
    }

    func testChildOnlyReceiptCannotBlessRemovalOfCapturedChildren() async throws {
        for count in [1, 2, 7] {
            let fixture = try ButtonChildTableFixture(childCount: count)
            defer { fixture.finish() }
            let captured = fixture.parent.children
            let attachments = captured.map { $0.captureLazyListAttachmentProof() }
            XCTAssertTrue(fixture.adoption.isCurrent)

            let write = fixture.parent.setChildren([])
            let recorded = fixture.adoption.recordChildrenWrite(on: fixture.parent)

            XCTAssertTrue(write.completed)
            XCTAssertTrue(fixture.parent.children.isEmpty)
            XCTAssertTrue(attachments.allSatisfy { !$0.isCurrent })
            XCTAssertFalse(recorded, "The child-only exception cannot refresh captured child attachments")
            XCTAssertFalse(fixture.adoption.isCurrent)
            XCTAssertTrue(fixture.parent.setChildren(captured).completed)
            XCTAssertFalse(fixture.adoption.recordChildrenWrite(on: fixture.parent))
            XCTAssertFalse(fixture.adoption.isCurrent, "A refused receipt remains refused after restoration")
        }
    }

    func testChildOnlyReceiptRejectsOtherStaleFacetsAtEachAcceptedShape() async throws {
        for count in [0, 1, 3] {
            for facet in ButtonChildTableStaleFacet.allCases {
                let fixture = try ButtonChildTableFixture(childCount: 0)
                defer { fixture.finish() }
                let accepted = (0..<count).map { _ in ViewNode() }
                let firstWrite = fixture.parent.setChildren(accepted)
                let firstRecorded = fixture.adoption.recordChildrenWrite(on: fixture.parent)
                XCTAssertTrue(firstWrite.completed)
                XCTAssertTrue(firstRecorded)
                let retainedMutation = fixture.makeStale(facet, identityNode: fixture.parent)
                let next = (0..<count).map { _ in ViewNode() }
                let write = fixture.parent.setChildren(next)

                let recorded = fixture.adoption.recordChildrenWrite(on: fixture.parent)

                XCTAssertTrue(write.completed)
                XCTAssertFalse(recorded, "count \(count), facet \(facet)")
                XCTAssertFalse(fixture.adoption.isCurrent)
                withExtendedLifetime(retainedMutation) {}
            }
        }
    }

    func testPairedAttachmentReceiptsAdvanceEmptySingleAndMultipleParentTables() async throws {
        let pool = (0..<5).map { _ in ViewNode() }
        let fixture = try ButtonChildTableFixture(childCount: 0, extraRoots: pool)
        defer { fixture.finish() }
        XCTAssertEqual(try XCTUnwrap(fixture.adoption.validationSnapshot).witnessCount, 7)
        XCTAssertTrue(fixture.adoption.isCurrent)

        // Every moved leaf was captured while detached. Each public native
        // write has no callbacks, and its paired receipt advances only that
        // leaf's attachment and this parent's table together.
        for (index, child) in pool.enumerated() {
            fixture.parent.addChild(child)
            let recorded = fixture.adoption.recordAttachmentWrite(on: child, afterChildrenWriteOf: fixture.parent)
            XCTAssertTrue(recorded)
            XCTAssertEqual(fixture.parent.children.count, index + 1)
            XCTAssertTrue(child.parent === fixture.parent)
            XCTAssertTrue(fixture.adoption.isCurrent)
        }
        for (index, child) in pool.reversed().enumerated() {
            child.removeFromParent()
            let recorded = fixture.adoption.recordAttachmentWrite(on: child, afterChildrenWriteOf: fixture.parent)
            XCTAssertTrue(recorded)
            XCTAssertEqual(fixture.parent.children.count, pool.count - index - 1)
            XCTAssertNil(child.parent)
            XCTAssertTrue(fixture.adoption.isCurrent)
        }
        XCTAssertTrue(fixture.parent.children.isEmpty)
        XCTAssertTrue(pool.allSatisfy { $0.retainedLazyListRuntime == nil })
        let before = try XCTUnwrap(fixture.adoption.validationSnapshot)
        XCTAssertTrue(fixture.adoption.isCurrent)
        let after = try XCTUnwrap(fixture.adoption.validationSnapshot)
        XCTAssertEqual(after.checkCount - before.checkCount, 1)
        XCTAssertEqual(after.witnessVisitCount - before.witnessVisitCount, 7)
    }

    func testPairedAttachmentReceiptRejectsUnrelatedStaleFacetsAtEveryShape() async throws {
        for count in [0, 1, 3] {
            for facet in ButtonChildTableStaleFacet.allCases {
                let incoming = ViewNode()
                let fixture = try ButtonChildTableFixture(childCount: count, extraRoots: [incoming])
                defer { fixture.finish() }
                XCTAssertTrue(fixture.adoption.isCurrent)
                let retainedMutation = fixture.makeStale(facet, identityNode: incoming)

                fixture.parent.addChild(incoming)
                let recorded = fixture.adoption.recordAttachmentWrite(
                    on: incoming, afterChildrenWriteOf: fixture.parent)

                XCTAssertTrue(incoming.parent === fixture.parent)
                XCTAssertEqual(fixture.parent.children.count, count + 1)
                XCTAssertFalse(recorded, "count \(count), facet \(facet)")
                XCTAssertFalse(fixture.adoption.isCurrent)
                withExtendedLifetime(retainedMutation) {}
            }
        }
    }

    func testIdentityReceiptRefreshesEachShapeOnlyWithAnUnchangedChildTable() async throws {
        for count in [0, 1, 2, 17] {
            let fixture = try ButtonChildTableFixture(childCount: count)
            defer { fixture.finish() }
            let originalIDs = fixture.parent.children.map(ObjectIdentifier.init)
            let attachments = ([fixture.parent] + fixture.parent.children).map {
                $0.captureLazyListAttachmentProof()
            }
            for changesValue in [false, true] {
                let before = try XCTUnwrap(fixture.adoption.validationSnapshot)
                let previousIdentity = fixture.parent.retainedViewIdentity
                fixture.parent.retainedViewIdentity =
                    changesValue ? RetainedViewIdentity(segments: [.role(.content)]) : previousIdentity

                fixture.adoption.recordIdentityWrite(on: fixture.parent)

                XCTAssertEqual(fixture.parent.children.map(ObjectIdentifier.init), originalIDs)
                XCTAssertTrue(attachments.allSatisfy(\.isCurrent))
                XCTAssertTrue(fixture.adoption.isCurrent)
                let after = try XCTUnwrap(fixture.adoption.validationSnapshot)
                XCTAssertEqual(after.checkCount - before.checkCount, 1)
                XCTAssertEqual(after.witnessVisitCount - before.witnessVisitCount, UInt64(count + 2))
            }
        }
    }

    func testIdentityReceiptNeverBlessesChildTableChangesOrOtherStaleFacets() async throws {
        for beforeCount in [0, 1, 2, 7] {
            for afterCount in [0, 1, 2, 7] where beforeCount != afterCount || beforeCount != 0 {
                let fixture = try ButtonChildTableFixture(childCount: 0)
                defer { fixture.finish() }
                // Accepted passive children were not captured witnesses. Their
                // later removal cannot mask a faulty child-table equality guard
                // with a second failure from an old child attachment proof.
                let original = (0..<beforeCount).map { _ in ViewNode() }
                let next = (0..<afterCount).map { _ in ViewNode() }
                let firstWrite = fixture.parent.setChildren(original)
                let firstRecorded = fixture.adoption.recordChildrenWrite(on: fixture.parent)
                XCTAssertTrue(firstWrite.completed)
                XCTAssertTrue(firstRecorded)
                XCTAssertTrue(fixture.parent.setChildren(next).completed)
                fixture.assertOriginalNonChildFacetsCurrent()
                fixture.parent.retainedViewIdentity = RetainedViewIdentity(segments: [.role(.content)])

                fixture.adoption.recordIdentityWrite(on: fixture.parent)

                XCTAssertFalse(fixture.adoption.isCurrent, "\(beforeCount) -> \(afterCount)")
                XCTAssertFalse(
                    fixture.adoption.recordChildrenWrite(on: fixture.parent),
                    "A refused identity receipt cannot be repaired by refreshing the child table later")
                withExtendedLifetime(original) {}
            }
        }
        for count in [2, 7] {
            let fixture = try ButtonChildTableFixture(childCount: 0)
            defer { fixture.finish() }
            let children = (0..<count).map { _ in ViewNode() }
            let firstWrite = fixture.parent.setChildren(children)
            let firstRecorded = fixture.adoption.recordChildrenWrite(on: fixture.parent)
            XCTAssertTrue(firstWrite.completed)
            XCTAssertTrue(firstRecorded)
            XCTAssertTrue(fixture.parent.setChildren(Array(children.reversed())).completed)
            fixture.assertOriginalNonChildFacetsCurrent()
            fixture.parent.retainedViewIdentity = RetainedViewIdentity(segments: [.role(.content)])

            fixture.adoption.recordIdentityWrite(on: fixture.parent)

            XCTAssertFalse(fixture.adoption.isCurrent)
            XCTAssertFalse(fixture.adoption.recordChildrenWrite(on: fixture.parent))
            withExtendedLifetime(children) {}
        }
        for count in [0, 1, 3] {
            for facet in ButtonChildTableStaleFacet.allCases {
                let fixture = try ButtonChildTableFixture(childCount: count)
                defer { fixture.finish() }
                let originalIDs = fixture.parent.children.map(ObjectIdentifier.init)
                let retainedMutation = fixture.makeStale(facet, identityNode: fixture.button)
                fixture.parent.retainedViewIdentity = RetainedViewIdentity(segments: [.role(.content)])

                fixture.adoption.recordIdentityWrite(on: fixture.parent)

                XCTAssertEqual(fixture.parent.children.map(ObjectIdentifier.init), originalIDs)
                XCTAssertFalse(fixture.adoption.isCurrent, "count \(count), facet \(facet)")
                withExtendedLifetime(retainedMutation) {}
            }
        }
    }

    func testHeldAdoptionDoesNotRetainPassiveTablesOrTheirChildren() async throws {
        for count in [0, 1, 3] {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let button = makeChildTableSentinel(runtime: runtime)
            var parent: ViewNode? = ViewNode(children: (0..<count).map { _ in ViewNode() })
            weak var observedParent = parent
            let observedChildren = try XCTUnwrap(parent).children.map(ButtonChildTableWeakNode.init)
            let adoption = try XCTUnwrap(
                RetainedButtonActionAdoption(
                    retainedRoots: [button, try XCTUnwrap(parent)], sourceRoots: [],
                    collectValidationDiagnostics: true))
            let check = try makeChildTableCleanupCheck(runtime: runtime)
            defer {
                _ = adoption.finish(completed: false, check: check, completion: nil)
                runtime.stopRenderLifecycleCallbacks()
                runtime.cancelRenderLifecycleTasks()
            }
            XCTAssertTrue(adoption.isCurrent)

            parent = nil

            XCTAssertNil(observedParent)
            XCTAssertTrue(observedChildren.allSatisfy { $0.node == nil })
            XCTAssertFalse(adoption.isCurrent)
            XCTAssertEqual(try XCTUnwrap(adoption.validationSnapshot).witnessCount, count + 2)
            withExtendedLifetime((adoption, button)) {}
        }
    }

    func testHeldAdoptionDoesNotRetainRuntimeForAnyChildTableShape() async throws {
        for count in [0, 1, 3] {
            var runtime: RetainedViewRuntime? = RetainedViewRuntime(root: ViewNode())
            weak var observedRuntime = runtime
            weak var observedRoot = runtime?.root
            let button = makeChildTableSentinel(runtime: try XCTUnwrap(runtime))
            let parent = ViewNode(children: (0..<count).map { _ in ViewNode() })
            let adoption = try XCTUnwrap(
                RetainedButtonActionAdoption(
                    retainedRoots: [button, parent], sourceRoots: [], collectValidationDiagnostics: true))
            let check = try makeChildTableCleanupCheck(runtime: try XCTUnwrap(runtime))
            defer { _ = adoption.finish(completed: false, check: check, completion: nil) }
            XCTAssertTrue(adoption.isCurrent)

            runtime = nil

            XCTAssertNil(observedRuntime)
            XCTAssertNil(observedRoot)
            let before = try XCTUnwrap(adoption.validationSnapshot)
            XCTAssertFalse(adoption.isCurrent)
            let after = try XCTUnwrap(adoption.validationSnapshot)
            XCTAssertEqual(after.checkCount - before.checkCount, 1)
            XCTAssertEqual(after.witnessVisitCount, before.witnessVisitCount)
            withExtendedLifetime((adoption, button, parent)) {}
        }
    }

    func testUnmanagedInitialAdoptionPreservesEmptySingleAndMultipleSubtreeTables() async throws {
        for count in [0, 1, 2, 7] {
            let runtime = RetainedViewRuntime(root: ViewNode())
            defer {
                runtime.stopRenderLifecycleCallbacks()
                runtime.cancelRenderLifecycleTasks()
            }
            var calls = 0
            let incoming = makeChildTableButton(runtime: runtime) { calls += 1 }
            let leaves = (0..<count).map { _ in ViewNode() }
            XCTAssertTrue(incoming.setChildren(leaves).completed)
            let saved = try XCTUnwrap(incoming.onActivate)
            XCTAssertTrue(runtime.root.children.isEmpty)

            let result = ComponentHost.reconcileChildren(of: runtime.root, oldChildren: [], newNodes: [incoming])

            XCTAssertTrue(result.completed)
            XCTAssertEqual(runtime.root.children.map(ObjectIdentifier.init), [ObjectIdentifier(incoming)])
            XCTAssertEqual(incoming.children.map(ObjectIdentifier.init), leaves.map(ObjectIdentifier.init))
            XCTAssertTrue(incoming.isRetainedLazyListAttached(in: runtime))
            XCTAssertTrue(leaves.allSatisfy { $0.parent === incoming && $0.retainedLazyListRuntime === runtime })
            XCTAssertFalse(incoming.buttonActionOwner?.isRetired == true)
            XCTAssertEqual(calls, 0)
            saved()
            incoming.onActivate?()
            XCTAssertEqual(calls, 2)
        }
    }

    func testTemporaryParentTransfersKeepSavedActionsClosedThroughDismantleAndControllerCallbacks() async throws {
        for count in [1, 2, 5] {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let temporary = ViewNode()
            var events: [String] = []
            var calls = 0
            let buttons = (0..<count).map { _ in makeChildTableButton(runtime: runtime) { calls += 1 } }
            let incoming = buttons.map { ViewNode(children: [$0]) }
            let controllers = (0..<count).map { _ in ButtonChildTableAttachmentController() }
            let saved = try buttons.map { try XCTUnwrap($0.onActivate) }
            XCTAssertTrue(temporary.setChildren(incoming).completed)
            for (index, node) in incoming.enumerated() {
                node.onDismantlePlatformView = { _ in
                    events.append("dismantle \(index)")
                    XCTAssertEqual(temporary.children.count, count - index - 1)
                    XCTAssertTrue(runtime.root.children.isEmpty)
                    for action in saved { action() }
                    XCTAssertEqual(calls, 0)
                }
                node.textInputController = controllers[index]
                controllers[index].onAttach = {
                    events.append("attach \(index)")
                    XCTAssertEqual(temporary.children.count, count - index - 1)
                    // Ordinary reconciliation publishes its destination table
                    // only after every incoming subtree finishes attachment.
                    XCTAssertTrue(runtime.root.children.isEmpty)
                    for action in saved { action() }
                    XCTAssertEqual(calls, 0)
                }
            }
            defer {
                for node in incoming { node.onDismantlePlatformView = nil }
                for controller in controllers { controller.onAttach = nil }
                runtime.stopRenderLifecycleCallbacks()
                runtime.cancelRenderLifecycleTasks()
            }

            let result = ComponentHost.reconcileChildren(of: runtime.root, oldChildren: [], newNodes: incoming)

            XCTAssertTrue(result.completed)
            XCTAssertEqual(events, (0..<count).flatMap { ["dismantle \($0)", "attach \($0)"] })
            XCTAssertTrue(temporary.children.isEmpty)
            XCTAssertEqual(runtime.root.children.map(ObjectIdentifier.init), incoming.map(ObjectIdentifier.init))
            XCTAssertTrue(controllers.allSatisfy { $0.attachCalls == 1 })
            XCTAssertTrue(incoming.allSatisfy { $0.parent === runtime.root })
            XCTAssertTrue(buttons.allSatisfy { $0.isRetainedLazyListAttached(in: runtime) })
            XCTAssertEqual(calls, 0)
            for action in saved { action() }
            for button in buttons { button.onActivate?() }
            XCTAssertEqual(calls, count * 2)
        }
    }
}

@MainActor
private final class ButtonChildTableFixture {
    let runtime: RetainedViewRuntime
    let button: ViewNode
    let parent: ViewNode
    let owner: RetainedButtonActionOwner
    let adoption: RetainedButtonActionAdoption
    private let attachments: [RetainedLazyListAttachmentProof]
    private let identities: [RetainedLazyListViewIdentityProof]
    private let cleanupCheck: ComponentHost.NodeReconcileAdmission
    private var didFinish = false

    init(childCount: Int, extraRoots: [ViewNode] = []) throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let button = makeChildTableSentinel(runtime: runtime)
        let parent = ViewNode(children: (0..<childCount).map { _ in ViewNode() })
        let nodes = [button, parent] + parent.children + extraRoots
        self.runtime = runtime
        self.button = button
        self.parent = parent
        owner = try XCTUnwrap(button.buttonActionOwner)
        cleanupCheck = try makeChildTableCleanupCheck(runtime: runtime)
        attachments = nodes.map { $0.captureLazyListAttachmentProof() }
        identities = nodes.map { $0.captureLazyListIdentityProof() }
        adoption = try XCTUnwrap(
            RetainedButtonActionAdoption(
                retainedRoots: [button, parent] + extraRoots, sourceRoots: [], collectValidationDiagnostics: true))
    }

    func assertOriginalNonChildFacetsCurrent(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(attachments.allSatisfy(\.isCurrent), file: file, line: line)
        XCTAssertTrue(identities.allSatisfy(\.isCurrent), file: file, line: line)
        XCTAssertTrue(button.buttonActionOwner === owner, file: file, line: line)
        XCTAssertFalse(owner.isRetired, file: file, line: line)
        XCTAssertNil(parent.buttonActionOwner, file: file, line: line)
        XCTAssertTrue(runtime.permitsRetainedActionInvocation, file: file, line: line)
    }

    func makeStale(_ facet: ButtonChildTableStaleFacet, identityNode: ViewNode) -> ViewNode? {
        switch facet {
        case .identity:
            let original = identityNode.retainedViewIdentity
            identityNode.retainedViewIdentity = original
        case .attachment:
            return ViewNode(children: [button])
        case .owner:
            button.buttonActionOwner = RetainedButtonActionOwner(action: nil, node: button, runtime: runtime)
        case .retirement:
            owner.retire()
        case .children:
            button.addChild(ViewNode())
        case .runtime:
            runtime.stopRenderLifecycleCallbacks()
        }
        return nil
    }

    func finish() {
        guard !didFinish else { return }
        didFinish = true
        _ = adoption.finish(completed: false, check: cleanupCheck, completion: nil)
        runtime.stopRenderLifecycleCallbacks()
        runtime.cancelRenderLifecycleTasks()
    }
}

private enum ButtonChildTableStaleFacet: CaseIterable {
    case identity, attachment, owner, retirement, children, runtime
}

@MainActor
private final class ButtonChildTableWeakNode {
    weak var node: ViewNode?
    init(_ node: ViewNode) { self.node = node }
}

@MainActor
private final class ButtonChildTableAttachmentController: RetainedTextInputController {
    var onAttach: (@MainActor () -> Void)?
    private(set) var attachCalls = 0

    func attach(to node: ViewNode) {
        attachCalls += 1
        let callback = onAttach
        onAttach = nil
        callback?()
    }

    func reconcile(from previous: (any RetainedTextInputController)?, onto node: ViewNode) {}
    func revokeOwnership(from node: ViewNode) {}
    func willDetach(from node: ViewNode) {}
    func detach(from node: ViewNode) {}
}

@MainActor
private func makeChildTableSentinel(runtime: RetainedViewRuntime) -> ViewNode {
    let node = ViewNode()
    node.buttonActionOwner = RetainedButtonActionOwner(action: nil, node: node, runtime: runtime)
    return node
}

@MainActor
private func makeChildTableButton(runtime: RetainedViewRuntime, action: @escaping () -> Void) -> ViewNode {
    Controls.button(
        runtime: runtime, frame: Rect(x: 0, y: 0, width: 80, height: 24), cornerRadius: 4,
        palette: SurfacePalette(idle: .gray, focused: .blue, pressed: .black), action: action)
}

@MainActor
private func makeChildTableCleanupCheck(runtime: RetainedViewRuntime) throws -> ComponentHost.NodeReconcileAdmission {
    try XCTUnwrap(
        ComponentHost.makeRemovalTransitionCheck(
            admission: nil, target: runtime.root, parent: runtime.root, proposedChildren: [], lazyJournal: nil))
}
