import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI

/// Real native proof predicates and checked adoption boundaries. These tests
/// do not measure production getter counts, elapsed time, or reduced work.
@MainActor
final class RetainedAdoptionProofPredicateTests: XCTestCase {
    func testAttachmentPredicatesRemainFreshAndStopInOrderAfterSameParentABA() async {
        let parent = ViewNode()
        let stableNode = ViewNode()
        let changedNode = ViewNode()
        parent.addChild(stableNode)
        parent.addChild(changedNode)
        defer { withExtendedLifetime(parent) {} }
        let stable = stableNode.captureLazyListAttachmentProof()
        let changed = changedNode.captureLazyListAttachmentProof()
        let empty: [RetainedLazyListAttachmentProof] = []
        XCTAssertTrue(empty.allSatisfy { $0.isCurrent })
        XCTAssertTrue([stable, changed].allSatisfy { $0.isCurrent })
        XCTAssertTrue([changed, stable].allSatisfy { $0.isCurrent })

        changedNode.removeFromParent()
        parent.addChild(changedNode)

        let fresh = changedNode.captureLazyListAttachmentProof()
        XCTAssertTrue(changedNode.parent === parent)
        XCTAssertTrue(fresh.isCurrent)
        XCTAssertFalse(changed.isCurrent)
        var visited: [ObjectIdentifier] = []
        XCTAssertFalse(
            [changed, stable].allSatisfy { proof in
                visited.append(ObjectIdentifier(proof))
                return proof.isCurrent
            })
        XCTAssertEqual(visited, [ObjectIdentifier(changed)])
        visited.removeAll()
        XCTAssertFalse(
            [stable, changed].allSatisfy { proof in
                visited.append(ObjectIdentifier(proof))
                return proof.isCurrent
            })
        XCTAssertEqual(visited, [ObjectIdentifier(stable), ObjectIdentifier(changed)])
        XCTAssertTrue([stable, fresh].allSatisfy { $0.isCurrent })
        XCTAssertFalse(changed.isCurrent)
    }

    func testIdentityPredicatesRejectEqualValueABAInEitherPositionWithoutRefreshingOldProofs() async {
        let stableNode = ViewNode()
        let changedNode = ViewNode()
        changedNode.retainedViewIdentity = .init(segments: [.slot(7)])
        defer { withExtendedLifetime((stableNode, changedNode)) {} }
        let stable = stableNode.captureLazyListIdentityProof()
        let changed = changedNode.captureLazyListIdentityProof()
        let empty: [RetainedLazyListViewIdentityProof] = []
        XCTAssertTrue(empty.allSatisfy { $0.isCurrent })
        XCTAssertTrue([stable, changed].allSatisfy { $0.isCurrent })
        let sameValue = changedNode.retainedViewIdentity

        changedNode.retainedViewIdentity = sameValue

        let fresh = changedNode.captureLazyListIdentityProof()
        XCTAssertTrue(fresh.isCurrent)
        var visited: [ObjectIdentifier] = []
        XCTAssertFalse(
            [changed, stable].allSatisfy { proof in
                visited.append(ObjectIdentifier(proof))
                return proof.isCurrent
            })
        XCTAssertEqual(visited, [ObjectIdentifier(changed)])
        visited.removeAll()
        XCTAssertFalse(
            [stable, changed].allSatisfy { proof in
                visited.append(ObjectIdentifier(proof))
                return proof.isCurrent
            })
        XCTAssertEqual(visited, [ObjectIdentifier(stable), ObjectIdentifier(changed)])
        XCTAssertTrue([stable, fresh].allSatisfy { $0.isCurrent })
        XCTAssertFalse(changed.isCurrent)
    }

    func testCompletionPredicatesRevalidateDescendantsAndShortCircuitBeforeLaterCompletions() async throws {
        let root = ViewNode()
        let child = ViewNode()
        let leaf = ViewNode()
        let independent = ViewNode()
        root.addChild(child)
        child.addChild(leaf)
        defer { withExtendedLifetime((root, independent)) {} }
        let original = try XCTUnwrap(RetainedLazyListAdoptionCompletion(of: root))
        let stable = try XCTUnwrap(RetainedLazyListAdoptionCompletion(of: independent))
        let empty: [RetainedLazyListAdoptionCompletion] = []
        XCTAssertTrue(empty.allSatisfy { $0.isCurrent })
        XCTAssertTrue([original, stable].allSatisfy { $0.isCurrent })
        XCTAssertEqual(original.validation().nodeVisits, 3)

        leaf.retainedViewIdentity = nil

        let staleValidation = original.validation()
        XCTAssertFalse(staleValidation.isCurrent)
        XCTAssertEqual(staleValidation.nodeVisits, 3)
        let fresh = try XCTUnwrap(RetainedLazyListAdoptionCompletion(of: root))
        XCTAssertTrue(fresh.isCurrent)
        var visited: [ObjectIdentifier] = []
        XCTAssertFalse(
            [fresh, original, stable].allSatisfy { completion in
                visited.append(ObjectIdentifier(completion))
                return completion.isCurrent
            })
        XCTAssertEqual(visited, [ObjectIdentifier(fresh), ObjectIdentifier(original)])
        visited.removeAll()
        XCTAssertFalse(
            [original, fresh, stable].allSatisfy { completion in
                visited.append(ObjectIdentifier(completion))
                return completion.isCurrent
            })
        XCTAssertEqual(visited, [ObjectIdentifier(original)])

        root.retainedViewIdentity = nil

        let staleRootValidation = fresh.validation()
        XCTAssertFalse(staleRootValidation.isCurrent)
        XCTAssertEqual(staleRootValidation.nodeVisits, 1)
        XCTAssertFalse([fresh, stable].allSatisfy { $0.isCurrent })
    }

    func testCheckedMatchingRechecksLaterSourceIdentityAfterAuthoredHashingBeforeAnyWrite() async throws {
        let hooks = ProofPredicateHashHooks()
        let previous = proofPredicateNode("old parent", tag: "parent")
        let incoming = proofPredicateNode("new parent", tag: "parent")
        let oldChildren = [
            proofPredicateNode("old first", tag: "first"), proofPredicateNode("old second", tag: "second"),
        ]
        let newChildren = [
            proofPredicateNode("new first", tag: "first"), proofPredicateNode("new second", tag: "second"),
        ]
        for index in oldChildren.indices {
            let identity = RetainedViewIdentity(segments: [
                .keyed(.init(ProofPredicateHashKey(value: index, hooks: hooks)))
            ])
            oldChildren[index].retainedViewIdentity = identity
            newChildren[index].retainedViewIdentity = identity
            previous.addChild(oldChildren[index])
            incoming.addChild(newChildren[index])
        }
        let fixture = try ProofPredicateAdoptionFixture(previous: [previous], incoming: [incoming])
        defer {
            hooks.onHash = nil
            fixture.finish()
        }
        let laterProof = newChildren[1].captureLazyListIdentityProof()
        let sameValue = newChildren[1].retainedViewIdentity
        XCTAssertTrue(laterProof.isCurrent)
        hooks.values.removeAll()
        hooks.onHash = { newChildren[1].retainedViewIdentity = sameValue }

        let result = ComponentHost.adopt(source: incoming, into: previous, admission: fixture.admission)

        XCTAssertFalse(hooks.values.isEmpty)
        XCTAssertFalse(hooks.values.contains(1), "The later authored key must not run after the native proof fails")
        XCTAssertFalse(result.completed)
        XCTAssertFalse(result.didMutate)
        XCTAssertFalse(laterProof.isCurrent)
        XCTAssertTrue(newChildren[1].captureLazyListIdentityProof().isCurrent)
        XCTAssertEqual(previous.text, "old parent")
        XCTAssertEqual(oldChildren.map(\.text), ["old first", "old second"])
        XCTAssertEqual(previous.children.map(ObjectIdentifier.init), oldChildren.map(ObjectIdentifier.init))
        XCTAssertEqual(incoming.children.map(ObjectIdentifier.init), newChildren.map(ObjectIdentifier.init))
        XCTAssertNotNil(fixture.provider.metadata)
    }

    func testPayloadCleanupCannotReuseEarlierPredicateSuccessForALaterPreparedSibling() async throws {
        let previous = proofPredicateNode("old parent", tag: "parent")
        let oldFirst = proofPredicateNode("old first", tag: "first")
        let oldSecond = proofPredicateNode("old second", tag: "second")
        previous.addChild(oldFirst)
        previous.addChild(oldSecond)
        let incoming = proofPredicateNode("new parent", tag: "parent")
        let newFirst = proofPredicateNode("new first", tag: "first")
        let newSecond = proofPredicateNode("new second", tag: "second")
        incoming.addChild(newFirst)
        incoming.addChild(newSecond)
        let fixture = try ProofPredicateAdoptionFixture(previous: [previous], incoming: [incoming])
        defer { fixture.finish() }
        let laterProof = newSecond.captureLazyListIdentityProof()
        let sameValue = newSecond.retainedViewIdentity
        XCTAssertTrue([laterProof].allSatisfy { $0.isCurrent })
        var cleanups = 0
        var predicateResults: [Bool] = []
        var firstUpdates = 0
        var secondUpdates = 0
        newFirst.onUpdatePlatformView = { _ in firstUpdates += 1 }
        newSecond.onUpdatePlatformView = { _ in secondUpdates += 1 }
        installProofPredicateCleanup(on: oldFirst) {
            cleanups += 1
            newSecond.retainedViewIdentity = sameValue
            predicateResults.append([laterProof].allSatisfy { $0.isCurrent })
            let fresh = newSecond.captureLazyListIdentityProof()
            predicateResults.append([fresh].allSatisfy { $0.isCurrent })
            predicateResults.append([laterProof].allSatisfy { $0.isCurrent })
        }

        let result = ComponentHost.adopt(source: incoming, into: previous, admission: fixture.admission)

        XCTAssertEqual(cleanups, 1)
        XCTAssertEqual(predicateResults, [false, true, false])
        XCTAssertFalse(result.completed)
        XCTAssertTrue(result.didMutate)
        XCTAssertNil(oldFirst.canvasDraw)
        XCTAssertEqual(previous.text, "new parent")
        XCTAssertEqual(oldFirst.text, "new first")
        XCTAssertEqual(firstUpdates, 1)
        XCTAssertEqual(oldSecond.text, "old second")
        XCTAssertEqual(secondUpdates, 0)
        XCTAssertEqual(previous.children.map(ObjectIdentifier.init), [oldFirst, oldSecond].map(ObjectIdentifier.init))
        XCTAssertEqual(incoming.children.map(ObjectIdentifier.init), [newFirst, newSecond].map(ObjectIdentifier.init))
        XCTAssertFalse(laterProof.isCurrent)
        XCTAssertNotNil(fixture.provider.metadata)
    }

    func testPreparedInsertionCompletionRejectsIdentityABAFromALaterRowCallback() async throws {
        let retained = proofPredicateNode("old retained", tag: "retained")
        let incomingRetained = proofPredicateNode("new retained", tag: "retained")
        let insertion = proofPredicateNode("insertion", tag: "insertion")
        let child = proofPredicateNode("prepared child", tag: "child")
        insertion.addChild(child)
        let fixture = try ProofPredicateAdoptionFixture(
            previous: [retained], incoming: [insertion, incomingRetained])
        defer { fixture.finish() }
        let original = try XCTUnwrap(RetainedLazyListAdoptionCompletion(of: insertion))
        XCTAssertTrue(original.isCurrent)
        let sameValue = child.retainedViewIdentity
        var callbacks = 0
        incomingRetained.onUpdatePlatformView = { _ in
            callbacks += 1
            child.retainedViewIdentity = sameValue
        }

        let result = fixture.reconcile()

        XCTAssertEqual(callbacks, 1)
        XCTAssertFalse(result.completed)
        XCTAssertTrue(result.didMutate)
        XCTAssertEqual(retained.text, "new retained")
        XCTAssertEqual(result.children.map(ObjectIdentifier.init), [ObjectIdentifier(retained)])
        XCTAssertNil(insertion.parent)
        XCTAssertTrue(insertion.children.first === child)
        XCTAssertFalse(original.isCurrent)
        XCTAssertTrue(try XCTUnwrap(RetainedLazyListAdoptionCompletion(of: insertion)).isCurrent)
        XCTAssertFalse(original.isCurrent)
        XCTAssertNotNil(fixture.provider.metadata)
    }
}

@MainActor
private func proofPredicateNode(_ text: String, tag: String) -> ViewNode {
    let node = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 20), text: text)
    node.nodeTag = tag
    return node
}

@MainActor
private func installProofPredicateCleanup(on node: ViewNode, action: @escaping @MainActor () -> Void) {
    let payload = ProofPredicateCleanup(action)
    node.canvasDraw = { [payload] _, _ in withExtendedLifetime(payload) {} }
}

private final class ProofPredicateCleanup {
    let action: @MainActor () -> Void
    init(_ action: @escaping @MainActor () -> Void) { self.action = action }
    deinit { MainActor.assumeIsolated { [action] in action() } }
}

@MainActor
private final class ProofPredicateHashHooks {
    var values: [Int] = []
    var onHash: (() -> Void)?
}

private struct ProofPredicateHashKey: Hashable {
    let value: Int
    let hooks: ProofPredicateHashHooks

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.value == rhs.value }

    func hash(into hasher: inout Hasher) {
        MainActor.assumeIsolated {
            hooks.values.append(value)
            hooks.onHash?()
        }
        hasher.combine(value)
    }
}

/// The source roots and retained roots have separate native proofs. This is
/// the existing candidate-backed admission seam, not an adopted-row substitute.
@MainActor
private final class ProofPredicateAdoptionFixture {
    let provider: RetainedLazyListDataSource<Int, [ViewNode]>
    let adapter: RetainedLazyListRuntimeAdapter
    let container: ViewNode
    let runtime: RetainedViewRuntime
    let lease: ProofPredicateLease
    let epoch: ProofPredicateEpoch
    let candidate: RetainedLazyListRuntimeAdapter.Candidate
    let admission: RetainedLazyListAdoptionAdmission
    private var didFinish = false

    init(previous: [ViewNode], incoming: [ViewNode]) throws {
        let provider = RetainedLazyListDataSource<Int, [ViewNode]>()
        guard
            provider.replaceData(
                [0], id: \.self, identityRoot: .init(segments: [.role(.content)]), rowContent: { _, _ in incoming })
        else { throw ProofPredicateFixtureError.setup }
        let row = try XCTUnwrap(provider.metadata?.rows.first)
        let request = try XCTUnwrap(provider.request(for: row.token))
        let prefix = try XCTUnwrap(provider.identityPrefix(for: request))
        var configured: Set<ObjectIdentifier> = []
        for nodes in [previous, incoming] {
            for (position, node) in nodes.enumerated() where configured.insert(ObjectIdentifier(node)).inserted {
                let path: [RetainedViewIdentity.Segment]
                if let identity = node.retainedViewIdentity {
                    path = [.role(.content)] + identity.segments
                } else if let tag = node.nodeTag {
                    path = [.role(.content), .explicit(.init(tag))]
                } else {
                    path = [.role(.content), .slot(position)]
                }
                node.retainedViewIdentity = prefix.appending(contentsOf: path)
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
        let lease = ProofPredicateLease()
        container.retainedSubtreeBuildLease = lease
        container.retainedLazyListAdapter = adapter
        let coordinator = runtime.retainedBuildCoordinator
        let sequence = try XCTUnwrap(coordinator.beginBuild())
        let epoch = ProofPredicateEpoch()
        coordinator.install(epoch, startedAt: sequence)
        let admission = RetainedLazyListAdoptionAdmission(
            adapter: adapter, container: container, runtime: runtime, coordinator: coordinator, sequence: sequence)
        var setupCompleted = false
        defer {
            if !setupCompleted {
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
        else { throw ProofPredicateFixtureError.setup }
        self.provider = provider
        self.adapter = adapter
        self.container = container
        self.runtime = runtime
        self.lease = lease
        self.epoch = epoch
        self.candidate = candidate
        self.admission = admission
        setupCompleted = true
    }

    func reconcile() -> RetainedLazyListAdoptionResult {
        ComponentHost.reconcileChildren(
            of: container, oldChildren: container.children, newNodes: candidate.children, admission: admission)
    }

    func finish() {
        guard !didFinish else { return }
        didFinish = true
        admission.revoke()
        provider.close()
        var pending = candidate.children + [container]
        var visited: Set<ObjectIdentifier> = []
        while let node = pending.popLast() {
            guard visited.insert(ObjectIdentifier(node)).inserted else { continue }
            pending.append(contentsOf: node.children)
            node.onUpdatePlatformView = nil
            node.canvasDraw = nil
        }
        if admission.didMutate { epoch.commit() } else { epoch.abandon() }
        epoch.finishAfterCallbacks()
        runtime.retainedBuildCoordinator.finishBuild()
    }
}

private enum ProofPredicateFixtureError: Error { case setup }

@MainActor
private final class ProofPredicateLease: RetainedSubtreeBuildLease {
    var canBuild: Bool { true }
    func beginBuild() -> (any RetainedBuildEpoch)? { ProofPredicateEpoch() }
}

@MainActor
private final class ProofPredicateEpoch: RetainedBuildEpoch {
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
