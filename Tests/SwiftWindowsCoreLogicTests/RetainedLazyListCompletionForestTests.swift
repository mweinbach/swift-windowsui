import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI

/// Native storage and visit counts, not elapsed-time or frame-rate evidence.
/// Every forest belongs to a real candidate-backed retained admission.
@MainActor
final class RetainedLazyListCompletionForestTests: XCTestCase {
    func testNestedCompletionsRetainAndVisitEachCoveredWitnessOnce() async throws {
        for count in [4, 8, 16] {
            let chain = completionForestChain(count: count)
            let fixture = try CompletionForestFixture(previous: [chain[0]])
            defer { fixture.finish() }
            var receipts: [RetainedLazyListAdoptionCompletion] = []
            var totalVisits = 0

            for index in chain.indices.reversed() {
                let completion = try XCTUnwrap(RetainedLazyListAdoptionCompletion(of: chain[index]))
                receipts.append(completion)
                let expected = count - index
                XCTAssertEqual(completion.retainedNodeWitnessCount, expected)
                XCTAssertTrue(fixture.admission.recordCompletion(completion))
                XCTAssertEqual(fixture.admission.retainedCompletionCount, 1)
                XCTAssertEqual(fixture.admission.retainedCompletionWitnessCount, expected)

                let validation = fixture.admission.validateCompletedSubtrees()
                XCTAssertTrue(validation.isCurrent)
                XCTAssertEqual(validation.nodeVisits, expected)
                totalVisits += validation.nodeVisits
                XCTAssertTrue(receipts.allSatisfy { $0.isCurrent })
            }

            XCTAssertEqual(totalVisits, count * (count + 1) / 2)
            XCTAssertTrue(fixture.admission.isCurrent)
        }
    }

    func testParentThenDescendantsDoNotGrowAnAlreadyCoveringForest() async throws {
        let chain = completionForestChain(count: 5)
        let fixture = try CompletionForestFixture(previous: [chain[0]])
        defer { fixture.finish() }
        let parent = try XCTUnwrap(RetainedLazyListAdoptionCompletion(of: chain[0]))
        XCTAssertTrue(fixture.admission.recordCompletion(parent))

        for node in chain {
            let descendant = try XCTUnwrap(RetainedLazyListAdoptionCompletion(of: node))
            XCTAssertTrue(fixture.admission.recordCompletion(descendant))
            XCTAssertTrue(descendant.isCurrent)
            XCTAssertTrue(parent.isCurrent)
            XCTAssertEqual(fixture.admission.retainedCompletionCount, 1)
            XCTAssertEqual(fixture.admission.retainedCompletionWitnessCount, chain.count)
            let validation = fixture.admission.validateCompletedSubtrees()
            XCTAssertTrue(validation.isCurrent)
            XCTAssertEqual(validation.nodeVisits, chain.count)
        }
    }

    func testSiblingSnapshotsRemainSeparateUntilTheirParentCoversBoth() async throws {
        let parent = ViewNode()
        let left = completionForestChain(count: 2)
        let right = completionForestChain(count: 3)
        parent.addChild(left[0])
        parent.addChild(right[0])
        let fixture = try CompletionForestFixture(previous: [parent])
        defer { fixture.finish() }
        let leftCompletion = try XCTUnwrap(RetainedLazyListAdoptionCompletion(of: left[0]))
        let rightCompletion = try XCTUnwrap(RetainedLazyListAdoptionCompletion(of: right[0]))
        XCTAssertTrue(fixture.admission.recordCompletion(leftCompletion))
        XCTAssertTrue(fixture.admission.recordCompletion(rightCompletion))
        XCTAssertEqual(fixture.admission.retainedCompletionCount, 2)
        XCTAssertEqual(fixture.admission.retainedCompletionWitnessCount, 5)
        XCTAssertEqual(fixture.admission.validateCompletedSubtrees().nodeVisits, 5)

        let covering = try XCTUnwrap(RetainedLazyListAdoptionCompletion(of: parent))
        XCTAssertTrue(fixture.admission.recordCompletion(covering))

        XCTAssertEqual(fixture.admission.retainedCompletionCount, 1)
        XCTAssertEqual(fixture.admission.retainedCompletionWitnessCount, 6)
        let validation = fixture.admission.validateCompletedSubtrees()
        XCTAssertTrue(validation.isCurrent)
        XCTAssertEqual(validation.nodeVisits, 6)
        XCTAssertTrue(leftCompletion.isCurrent)
        XCTAssertTrue(rightCompletion.isCurrent)
    }

    func testCoveringOneBranchDoesNotDiscardAnIndependentCompletion() async throws {
        let left = completionForestChain(count: 3)
        let right = completionForestChain(count: 2)
        let fixture = try CompletionForestFixture(previous: [left[0], right[0]])
        defer { fixture.finish() }
        let leftChild = try XCTUnwrap(RetainedLazyListAdoptionCompletion(of: left[1]))
        let rightRoot = try XCTUnwrap(RetainedLazyListAdoptionCompletion(of: right[0]))
        XCTAssertTrue(fixture.admission.recordCompletion(leftChild))
        XCTAssertTrue(fixture.admission.recordCompletion(rightRoot))
        let coveringLeft = try XCTUnwrap(RetainedLazyListAdoptionCompletion(of: left[0]))

        XCTAssertTrue(fixture.admission.recordCompletion(coveringLeft))

        XCTAssertEqual(fixture.admission.retainedCompletionCount, 2)
        XCTAssertEqual(fixture.admission.retainedCompletionWitnessCount, 5)
        XCTAssertEqual(fixture.admission.validateCompletedSubtrees().nodeVisits, 5)
        right[1].retainedViewIdentity = nil
        XCTAssertTrue(coveringLeft.isCurrent)
        XCTAssertFalse(rightRoot.isCurrent)
        XCTAssertFalse(fixture.admission.validateCompletedSubtrees().isCurrent)
        XCTAssertFalse(fixture.admission.isCurrent)
    }

    func testReconciliationCompactsCompletionsThroughTheProductionAdmission() async throws {
        let previous = completionForestChain(count: 6)
        let incoming = completionForestChain(count: 6)
        let fixture = try CompletionForestFixture(previous: [previous[0]], incoming: [incoming[0]])
        defer { fixture.finish() }

        let result = ComponentHost.reconcileChildren(
            of: fixture.container, oldChildren: fixture.container.children,
            newNodes: fixture.candidate.children, admission: fixture.admission)

        XCTAssertTrue(result.completed)
        XCTAssertTrue(fixture.container.children.first === previous[0])
        XCTAssertTrue(fixture.admission.isCurrent)
        XCTAssertEqual(fixture.admission.retainedCompletionCount, 1)
        XCTAssertEqual(fixture.admission.retainedCompletionWitnessCount, previous.count + 1)
        let validation = fixture.admission.validateCompletedSubtrees()
        XCTAssertTrue(validation.isCurrent)
        XCTAssertEqual(validation.nodeVisits, previous.count + 1)
        let completion = try XCTUnwrap(result.completion)
        XCTAssertEqual(completion.validation().nodeVisits, previous.count + 1)
    }

    func testFreshCoveringSnapshotCannotEraseAnOlderStaleWitness() async throws {
        for change in CompletionForestWitnessChange.allCases {
            let parent = ViewNode()
            let affected = ViewNode()
            let first = ViewNode()
            let second = ViewNode()
            affected.addChild(first)
            affected.addChild(second)
            parent.addChild(affected)
            try prepareCompletionForestWitnessChange(change, on: affected)
            let fixture = try CompletionForestFixture(previous: [parent])
            defer { fixture.finish() }
            let original = try XCTUnwrap(RetainedLazyListAdoptionCompletion(of: affected))
            XCTAssertTrue(fixture.admission.recordCompletion(original), "\(change)")
            XCTAssertTrue(fixture.admission.isCurrent)

            try applyCompletionForestWitnessChange(change, to: affected)
            let fresh = try XCTUnwrap(RetainedLazyListAdoptionCompletion(of: parent))

            XCTAssertTrue(fresh.isCurrent, "\(change)")
            XCTAssertFalse(original.isCurrent, "\(change)")
            XCTAssertFalse(fixture.admission.validateCompletedSubtrees().isCurrent, "\(change)")
            XCTAssertFalse(fixture.admission.recordCompletion(fresh), "\(change)")
            XCTAssertEqual(fixture.admission.retainedCompletionCount, 1, "\(change)")
            XCTAssertEqual(fixture.admission.retainedCompletionWitnessCount, 3, "\(change)")
            XCTAssertFalse(original.isCurrent, "The old receipt must not be refreshed: \(change)")
        }
    }

    func testStaleIncomingSnapshotCannotChangeACurrentForest() async throws {
        let parent = ViewNode()
        let retainedChild = ViewNode()
        let changedChild = ViewNode()
        parent.addChild(retainedChild)
        parent.addChild(changedChild)
        let fixture = try CompletionForestFixture(previous: [parent])
        defer { fixture.finish() }
        let retained = try XCTUnwrap(RetainedLazyListAdoptionCompletion(of: retainedChild))
        XCTAssertTrue(fixture.admission.recordCompletion(retained))
        let incoming = try XCTUnwrap(RetainedLazyListAdoptionCompletion(of: parent))
        changedChild.retainedViewIdentity = nil
        XCTAssertTrue(retained.isCurrent)
        XCTAssertTrue(fixture.admission.isCurrent)
        XCTAssertFalse(incoming.isCurrent)

        XCTAssertFalse(fixture.admission.recordCompletion(incoming))

        XCTAssertEqual(fixture.admission.retainedCompletionCount, 1)
        XCTAssertEqual(fixture.admission.retainedCompletionWitnessCount, 1)
        let validation = fixture.admission.validateCompletedSubtrees()
        XCTAssertTrue(validation.isCurrent)
        XCTAssertEqual(validation.nodeVisits, 1)
        XCTAssertTrue(fixture.admission.isCurrent)
    }

    func testFutureWitnessChangesInvalidateCompactedForestAndExternalReceipt() async throws {
        for change in CompletionForestWitnessChange.allCases {
            let parent = ViewNode()
            let affected = ViewNode()
            affected.addChild(ViewNode())
            affected.addChild(ViewNode())
            parent.addChild(affected)
            try prepareCompletionForestWitnessChange(change, on: affected)
            let fixture = try CompletionForestFixture(previous: [parent])
            defer { fixture.finish() }
            let original = try XCTUnwrap(RetainedLazyListAdoptionCompletion(of: affected))
            let covering = try XCTUnwrap(RetainedLazyListAdoptionCompletion(of: parent))
            XCTAssertTrue(fixture.admission.recordCompletion(original), "\(change)")
            XCTAssertTrue(fixture.admission.recordCompletion(covering), "\(change)")
            XCTAssertEqual(fixture.admission.retainedCompletionCount, 1)
            XCTAssertEqual(fixture.admission.retainedCompletionWitnessCount, 4)
            let before = fixture.admission.validateCompletedSubtrees()
            XCTAssertTrue(before.isCurrent)
            XCTAssertEqual(before.nodeVisits, 4)

            try applyCompletionForestWitnessChange(change, to: affected)

            XCTAssertFalse(original.isCurrent, "\(change)")
            XCTAssertFalse(covering.isCurrent, "\(change)")
            XCTAssertFalse(fixture.admission.validateCompletedSubtrees().isCurrent, "\(change)")
            XCTAssertFalse(fixture.admission.isCurrent, "\(change)")
            let fresh = try XCTUnwrap(RetainedLazyListAdoptionCompletion(of: parent))
            XCTAssertTrue(fresh.isCurrent, "\(change)")
            XCTAssertFalse(fixture.admission.recordCompletion(fresh), "\(change)")
            XCTAssertEqual(fixture.admission.retainedCompletionCount, 1)
            XCTAssertEqual(fixture.admission.retainedCompletionWitnessCount, 4)
            XCTAssertFalse(original.isCurrent, "Compaction must not refresh external receipts: \(change)")
        }
    }

    func testRuntimeTransferCannotReplaceTheOldRuntimeWitness() async throws {
        let chain = completionForestChain(count: 2)
        let fixture = try CompletionForestFixture(previous: [chain[0]])
        defer { fixture.finish() }
        let original = try XCTUnwrap(RetainedLazyListAdoptionCompletion(of: chain[0]))
        XCTAssertTrue(fixture.admission.recordCompletion(original))
        let otherRuntime = RetainedViewRuntime(root: ViewNode())
        defer { withExtendedLifetime(otherRuntime) {} }

        otherRuntime.root.addChild(chain[0])
        let transferred = try XCTUnwrap(RetainedLazyListAdoptionCompletion(of: chain[0]))

        XCTAssertTrue(chain[0].parent === otherRuntime.root)
        XCTAssertTrue(transferred.isCurrent)
        XCTAssertFalse(original.isCurrent)
        XCTAssertFalse(fixture.admission.validateCompletedSubtrees().isCurrent)
        XCTAssertFalse(fixture.admission.recordCompletion(transferred))
        XCTAssertEqual(fixture.admission.retainedCompletionCount, 1)
        XCTAssertEqual(fixture.admission.retainedCompletionWitnessCount, 2)
    }

    func testRevokedClosedAndSupersededAdmissionsCannotCompactCurrentSnapshots() async throws {
        for change in CompletionForestAdmissionChange.allCases {
            let chain = completionForestChain(count: 3)
            let fixture = try CompletionForestFixture(previous: [chain[0]])
            defer { fixture.finish() }
            let child = try XCTUnwrap(RetainedLazyListAdoptionCompletion(of: chain[1]))
            XCTAssertTrue(fixture.admission.recordCompletion(child))
            let parent = try XCTUnwrap(RetainedLazyListAdoptionCompletion(of: chain[0]))

            switch change {
            case .revoked: fixture.admission.revoke()
            case .providerClosed: fixture.provider.close()
            case .superseded: fixture.runtime.retainedBuildCoordinator.scheduleReload {}
            }

            XCTAssertTrue(child.isCurrent)
            XCTAssertTrue(parent.isCurrent)
            XCTAssertTrue(fixture.admission.validateCompletedSubtrees().isCurrent)
            XCTAssertFalse(fixture.admission.isCurrent, "\(change)")
            XCTAssertFalse(fixture.admission.recordCompletion(parent), "\(change)")
            XCTAssertEqual(fixture.admission.retainedCompletionCount, 1)
            XCTAssertEqual(fixture.admission.retainedCompletionWitnessCount, 2)
        }
    }

    func testAuthoredCallbackInvalidatesCompactedAndExternalReceiptsBeforeTheNextKey() async throws {
        let chain = completionForestChain(count: 4)
        let fixture = try CompletionForestFixture(previous: [chain[0]])
        defer { fixture.finish() }
        let child = try XCTUnwrap(RetainedLazyListAdoptionCompletion(of: chain[2]))
        let parent = try XCTUnwrap(RetainedLazyListAdoptionCompletion(of: chain[0]))
        XCTAssertTrue(fixture.admission.recordCompletion(child))
        XCTAssertTrue(fixture.admission.recordCompletion(parent))
        XCTAssertEqual(fixture.admission.retainedCompletionCount, 1)
        XCTAssertTrue(fixture.admission.validateCompletedSubtrees().isCurrent)
        let events = CompletionForestKeyEvents()
        events.onHash = { chain[3].retainedViewIdentity = nil }
        defer { events.onHash = nil }
        let identity = RetainedViewIdentity(segments: [
            .keyed(.init(CompletionForestKey(value: 0, events: events))),
            .keyed(.init(CompletionForestKey(value: 1, events: events))),
        ])
        var hasher = Hasher()

        let completed = identity.checkedHash(into: &hasher) { fixture.admission.isCurrent }

        XCTAssertFalse(completed)
        XCTAssertEqual(events.hashes, [0])
        XCTAssertFalse(child.isCurrent)
        XCTAssertFalse(parent.isCurrent)
        XCTAssertFalse(fixture.admission.validateCompletedSubtrees().isCurrent)
        XCTAssertFalse(fixture.admission.isCurrent)
        let fresh = try XCTUnwrap(RetainedLazyListAdoptionCompletion(of: chain[0]))
        XCTAssertTrue(fresh.isCurrent)
        XCTAssertFalse(fixture.admission.recordCompletion(fresh))
        XCTAssertEqual(fixture.admission.retainedCompletionCount, 1)
    }

    func testCompactionComparesNativeProofsWithoutHashingOrComparingAuthoredIdentityValues() async throws {
        let chain = completionForestChain(count: 3)
        let fixture = try CompletionForestFixture(previous: [chain[0]])
        defer { fixture.finish() }
        let events = CompletionForestKeyEvents()
        chain[1].retainedViewIdentity = RetainedViewIdentity(segments: [
            .explicit(.init(CompletionForestKey(value: 42, events: events)))
        ])
        let child = try XCTUnwrap(RetainedLazyListAdoptionCompletion(of: chain[1]))
        let parent = try XCTUnwrap(RetainedLazyListAdoptionCompletion(of: chain[0]))

        XCTAssertTrue(fixture.admission.recordCompletion(child))
        XCTAssertTrue(fixture.admission.recordCompletion(parent))
        XCTAssertTrue(fixture.admission.recordCompletion(child))
        XCTAssertTrue(fixture.admission.validateCompletedSubtrees().isCurrent)

        XCTAssertEqual(fixture.admission.retainedCompletionCount, 1)
        XCTAssertEqual(fixture.admission.retainedCompletionWitnessCount, 3)
        XCTAssertTrue(events.hashes.isEmpty)
        XCTAssertEqual(events.comparisons, 0)
    }

    func testCompactedSnapshotRejectsRetirementBeforeTheOldLinksAreRemoved() async throws {
        let parent = ViewNode()
        let child = ViewNode()
        parent.addChild(child)
        let fixture = try CompletionForestFixture(previous: [parent])
        defer { fixture.finish() }
        let controller = CompletionForestRetirementController(parent: parent, admission: fixture.admission)
        child.textInputController = controller
        let oldChild = try XCTUnwrap(RetainedLazyListAdoptionCompletion(of: child))
        let covering = try XCTUnwrap(RetainedLazyListAdoptionCompletion(of: parent))
        XCTAssertTrue(fixture.admission.recordCompletion(oldChild))
        XCTAssertTrue(fixture.admission.recordCompletion(covering))
        controller.childCompletion = oldChild
        controller.coveringCompletion = covering
        let scope = RetainedLazyListDescriptorBuildScope(
            origin: .componentHostRoot, hostLifetime: fixture.runtime.lazyListLogicalHostLifetime,
            ownerLifetime: fixture.runtime.root.lazyListActivityStorage().descriptorOwnerLifetime)
        let journal = RetainedLazyListAdoptionJournal(descriptorScope: scope, transaction: RetainedBuildTransaction())
        let preparation = try XCTUnwrap(journal.preparation())
        let prepared = RetainedLazyListPreparedActivity(preparation: preparation, logicalMembershipPlans: [])
        XCTAssertTrue(journal.beginAdoption(preparation, preparedActivity: prepared))

        let result = parent.setChildren([], lazyJournal: journal)

        XCTAssertTrue(result.completed)
        XCTAssertEqual(controller.revocations, 1)
        XCTAssertTrue(controller.linksWereStillPresent)
        XCTAssertEqual(controller.childWasCurrent, false)
        XCTAssertEqual(controller.coveringWasCurrent, false)
        XCTAssertEqual(controller.forestWasCurrent, false)
        XCTAssertNil(child.parent)
        XCTAssertFalse(oldChild.isCurrent)
        XCTAssertFalse(covering.isCurrent)
        XCTAssertFalse(fixture.admission.isCurrent)
        _ = journal.seal(completedCheckedAdoption: result.completed)
        scope.finish()
    }

    func testForestAndExternalReceiptsDoNotRetainNodesRuntimeOrPayloads() async throws {
        let probe = CompletionForestWeakProbe()
        let captured = try captureEphemeralCompletionForest(probe: probe)

        XCTAssertNil(probe.node)
        XCTAssertNil(probe.runtime)
        XCTAssertNil(probe.controller)
        XCTAssertNil(probe.observers)
        XCTAssertEqual(probe.payloadDeinits, 1)
        XCTAssertEqual(captured.admission.retainedCompletionCount, 1)
        XCTAssertEqual(captured.admission.retainedCompletionWitnessCount, 2)
        XCTAssertFalse(captured.child.isCurrent)
        XCTAssertFalse(captured.parent.isCurrent)
        XCTAssertFalse(captured.admission.validateCompletedSubtrees().isCurrent)
    }

    func testCompletionKeepsItsExistingInclusiveDepthLimit() async throws {
        let count = ViewNode.maximumTraversalDepth + 1
        let chain = completionForestChain(count: count)
        let allowed = try XCTUnwrap(RetainedLazyListAdoptionCompletion(of: chain[0]))
        XCTAssertEqual(allowed.retainedNodeWitnessCount, count)
        let validation = allowed.validation()
        XCTAssertTrue(validation.isCurrent)
        XCTAssertEqual(validation.nodeVisits, count)

        chain[count - 1].addChild(ViewNode())

        XCTAssertNil(RetainedLazyListAdoptionCompletion(of: chain[0]))
        XCTAssertFalse(allowed.isCurrent)
    }
}

private enum CompletionForestWitnessChange: CaseIterable {
    case attachment, identity, childOrder
    case controller, controllerInsertion, controllerRemoval
    case observers, observersInsertion, observersRemoval
    case adapter, adapterInsertion, adapterRemoval
}

private enum CompletionForestAdmissionChange: CaseIterable {
    case revoked, providerClosed, superseded
}

@MainActor
private func prepareCompletionForestWitnessChange(_ change: CompletionForestWitnessChange, on node: ViewNode) throws {
    switch change {
    case .controller, .controllerRemoval:
        node.textInputController = CompletionForestTextController()
    case .observers, .observersRemoval:
        node.scrollObserverStorage = RetainedScrollObserverStorage()
    case .adapter, .adapterRemoval:
        node.retainedLazyListAdapter = try completionForestAdapter()
    case .attachment, .identity, .childOrder, .controllerInsertion, .observersInsertion, .adapterInsertion:
        break
    }
}

@MainActor
private func applyCompletionForestWitnessChange(_ change: CompletionForestWitnessChange, to node: ViewNode) throws {
    switch change {
    case .attachment:
        let parent = try XCTUnwrap(node.parent)
        node.removeFromParent()
        parent.addChild(node)
    case .identity:
        let identity = node.retainedViewIdentity
        node.retainedViewIdentity = identity
    case .childOrder:
        _ = node.setChildren(Array(node.children.reversed()))
    case .controller, .controllerInsertion:
        node.textInputController = CompletionForestTextController()
    case .controllerRemoval:
        node.textInputController = nil
    case .observers, .observersInsertion:
        node.scrollObserverStorage = RetainedScrollObserverStorage()
    case .observersRemoval:
        node.scrollObserverStorage = nil
    case .adapter, .adapterInsertion:
        node.retainedLazyListAdapter = try completionForestAdapter()
    case .adapterRemoval:
        node.retainedLazyListAdapter = nil
    }
}

@MainActor
private func completionForestChain(count: Int) -> [ViewNode] {
    precondition(count > 0)
    let nodes = (0..<count).map { index in
        let node = ViewNode()
        node.nodeTag = "completion-forest-\(index)"
        return node
    }
    for index in 1..<count { nodes[index - 1].addChild(nodes[index]) }
    return nodes
}

@MainActor
private func completionForestAdapter() throws -> RetainedLazyListRuntimeAdapter {
    let provider = RetainedLazyListDataSource<Int, [ViewNode]>()
    guard provider.replaceData([], id: \.self, rowContent: { _ in [] }) else {
        throw CompletionForestFixtureError.setup
    }
    return try XCTUnwrap(
        RetainedLazyListRuntimeAdapter(
            provider: provider, estimatedExtent: 20, prefetchExtent: 0,
            maximumMountedRecords: 4, maximumMountedLeaves: 16, maximumProtectedRecords: 1))
}

@MainActor
private final class CompletionForestFixture {
    let provider: RetainedLazyListDataSource<Int, [ViewNode]>
    let adapter: RetainedLazyListRuntimeAdapter
    let container: ViewNode
    let runtime: RetainedViewRuntime
    let lease: CompletionForestLease
    let epoch: CompletionForestEpoch
    let candidate: RetainedLazyListRuntimeAdapter.Candidate
    let admission: RetainedLazyListAdoptionAdmission
    private var didFinish = false

    init(previous: [ViewNode], incoming suppliedIncoming: [ViewNode]? = nil) throws {
        // Candidate identity proofs concern separate source nodes; changes in
        // the retained tree must be detected by the completion forest itself.
        let incoming = suppliedIncoming ?? [ViewNode()]
        let provider = RetainedLazyListDataSource<Int, [ViewNode]>()
        guard
            provider.replaceData(
                [0], id: \.self, identityRoot: .init(segments: [.role(.content)]), rowContent: { _, _ in incoming })
        else { throw CompletionForestFixtureError.setup }
        let row = try XCTUnwrap(provider.metadata?.rows.first)
        let request = try XCTUnwrap(provider.request(for: row.token))
        let prefix = try XCTUnwrap(provider.identityPrefix(for: request))
        for roots in [previous, incoming] {
            for (index, root) in roots.enumerated() {
                root.retainedViewIdentity = prefix.appending(contentsOf: [.role(.content), .slot(index)])
            }
        }
        let adapter = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter(
                provider: provider, estimatedExtent: 20, prefetchExtent: 0,
                maximumMountedRecords: 4, maximumMountedLeaves: 16, maximumProtectedRecords: 1))
        let context = try XCTUnwrap(
            RetainedLazyListMeasurementContext(width: 100, displayScale: 1, contentRevision: 0, environmentRevision: 0))
        let viewport = try XCTUnwrap(RetainedLazyListRuntimeAdapter.Viewport(context: context, offset: 0, extent: 60))
        let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 4, roundLimit: 2))
        let container = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 60))
        for node in previous { container.addChild(node) }
        let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 60)))
        runtime.root.addChild(container)
        let lease = CompletionForestLease()
        container.retainedSubtreeBuildLease = lease
        container.retainedLazyListAdapter = adapter
        let coordinator = runtime.retainedBuildCoordinator
        let sequence = try XCTUnwrap(coordinator.beginBuild())
        let epoch = CompletionForestEpoch()
        coordinator.install(epoch, startedAt: sequence)
        let admission = RetainedLazyListAdoptionAdmission(
            adapter: adapter, container: container, runtime: runtime, coordinator: coordinator, sequence: sequence)
        var completedSetup = false
        defer {
            if !completedSetup {
                provider.close()
                epoch.abandon()
                epoch.finishAfterCallbacks()
                coordinator.finishBuild()
            }
        }
        guard
            case .ready(let candidate) = adapter.prepare(
                viewport: viewport, protectedRoots: [], budget: budget, admission: admission),
            admission.installCandidate(candidate), epoch.willAdopt(), admission.isCurrent
        else { throw CompletionForestFixtureError.setup }
        self.provider = provider
        self.adapter = adapter
        self.container = container
        self.runtime = runtime
        self.lease = lease
        self.epoch = epoch
        self.candidate = candidate
        self.admission = admission
        completedSetup = true
    }

    func finish() {
        guard !didFinish else { return }
        didFinish = true
        admission.revoke()
        provider.close()
        if admission.didMutate { epoch.commit() } else { epoch.abandon() }
        epoch.finishAfterCallbacks()
        runtime.retainedBuildCoordinator.finishBuild()
    }
}

private enum CompletionForestFixtureError: Error { case setup }

@MainActor
private final class CompletionForestLease: RetainedSubtreeBuildLease {
    var canBuild: Bool { true }
    func beginBuild() -> (any RetainedBuildEpoch)? { CompletionForestEpoch() }
}

@MainActor
private final class CompletionForestEpoch: RetainedBuildEpoch {
    private var prepared = false
    var canAdopt: Bool { !prepared }
    func supersede() {}
    func willAdopt() -> Bool {
        guard !prepared else { return false }
        prepared = true
        return true
    }
    func commit() {}
    func abandon() {}
    func finishAfterCallbacks() {}
}

@MainActor
private final class CompletionForestTextController: RetainedTextInputController {
    func attach(to node: ViewNode) {}
    func reconcile(from previous: (any RetainedTextInputController)?, onto node: ViewNode) {}
    func detach(from node: ViewNode) {}
}

/// The revocation protocol forbids authored callbacks. Record native scalar
/// observations inside that phase, then assert them after removal returns.
@MainActor
private final class CompletionForestRetirementController: RetainedTextInputController {
    weak var parent: ViewNode?
    let admission: RetainedLazyListAdoptionAdmission
    var childCompletion: RetainedLazyListAdoptionCompletion?
    var coveringCompletion: RetainedLazyListAdoptionCompletion?
    private(set) var revocations = 0
    private(set) var linksWereStillPresent = false
    private(set) var childWasCurrent: Bool?
    private(set) var coveringWasCurrent: Bool?
    private(set) var forestWasCurrent: Bool?

    init(parent: ViewNode, admission: RetainedLazyListAdoptionAdmission) {
        self.parent = parent
        self.admission = admission
    }

    func attach(to node: ViewNode) {}
    func reconcile(from previous: (any RetainedTextInputController)?, onto node: ViewNode) {}
    func revokeOwnership(from node: ViewNode) {
        revocations += 1
        linksWereStillPresent = node.parent === parent
        childWasCurrent = childCompletion?.isCurrent
        coveringWasCurrent = coveringCompletion?.isCurrent
        forestWasCurrent = admission.validateCompletedSubtrees().isCurrent
    }
    func detach(from node: ViewNode) {}
}

@MainActor
private final class CompletionForestKeyEvents {
    var hashes: [Int] = []
    var comparisons = 0
    var onHash: (() -> Void)?
}

private struct CompletionForestKey: Hashable {
    let value: Int
    let events: CompletionForestKeyEvents

    static func == (lhs: Self, rhs: Self) -> Bool {
        MainActor.assumeIsolated { lhs.events.comparisons += 1 }
        return lhs.value == rhs.value
    }

    func hash(into hasher: inout Hasher) {
        MainActor.assumeIsolated {
            events.hashes.append(value)
            events.onHash?()
        }
        hasher.combine(value)
    }
}

@MainActor
private final class CompletionForestWeakProbe {
    weak var node: ViewNode?
    weak var runtime: RetainedViewRuntime?
    weak var controller: CompletionForestTextController?
    weak var observers: RetainedScrollObserverStorage?
    var payloadDeinits = 0
}

private final class CompletionForestPayload {
    let probe: CompletionForestWeakProbe
    init(probe: CompletionForestWeakProbe) { self.probe = probe }
    deinit { MainActor.assumeIsolated { probe.payloadDeinits += 1 } }
}

@MainActor
@inline(never)
private func captureEphemeralCompletionForest(probe: CompletionForestWeakProbe) throws -> (
    admission: RetainedLazyListAdoptionAdmission,
    child: RetainedLazyListAdoptionCompletion,
    parent: RetainedLazyListAdoptionCompletion
) {
    let parent = ViewNode()
    let child = ViewNode()
    let payload = CompletionForestPayload(probe: probe)
    child.onActivate = { withExtendedLifetime(payload) {} }
    let controller = CompletionForestTextController()
    let observers = RetainedScrollObserverStorage()
    child.textInputController = controller
    child.scrollObserverStorage = observers
    parent.addChild(child)
    let fixture = try CompletionForestFixture(previous: [parent])
    defer { fixture.finish() }
    probe.node = child
    probe.runtime = fixture.runtime
    probe.controller = controller
    probe.observers = observers
    let childCompletion = try XCTUnwrap(RetainedLazyListAdoptionCompletion(of: child))
    let parentCompletion = try XCTUnwrap(RetainedLazyListAdoptionCompletion(of: parent))
    guard fixture.admission.recordCompletion(childCompletion), fixture.admission.recordCompletion(parentCompletion)
    else {
        throw CompletionForestFixtureError.setup
    }
    return (fixture.admission, childCompletion, parentCompletion)
}
