import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI

/// Native proof and visit-count fixtures. They do not measure elapsed time or
/// replace the public interaction, ownership, or callback integration tests.
@MainActor
final class RetainedDescriptorAttachmentQueryTests: XCTestCase {
    func testSharedAncestorsAndSiblingPrefixesAreVisitedOncePerQuery() async {
        let tree = AttachmentQueryTree(depth: 40, leaves: 48)
        defer { withExtendedLifetime(tree) {} }
        let actuals = tree.leaves.map { tree.actual($0) }
        XCTAssertTrue(actuals.allSatisfy(\.isAttached))

        for order in [actuals, Array(actuals.reversed())] {
            let result = checkAttachments(order)

            XCTAssertTrue(result.accepted)
            XCTAssertEqual(result.ancestorVisits, 40 + 1 + 48)
            XCTAssertEqual(result.childLinkVisits, 40 + 48)
        }
    }

    func testEnclosingOrdinaryScopesShareStructureButRecheckContributionRevocation() async throws {
        let tree = AttachmentQueryTree(depth: 12, leaves: 16)
        defer { withExtendedLifetime(tree) {} }
        let accepted = try acceptOrdinaryGroup(on: tree.leaves, in: tree.runtime)
        let actual = try XCTUnwrap(accepted.acceptedFacets.first?.actual)
        var scope = tree.scope()
        for _ in 0..<8 {
            scope = try XCTUnwrap(
                scope.withAdmittedOrdinaryDeferredSubtree(
                    originalActivity: accepted.receipt, originalAttachment: actual))
        }

        XCTAssertTrue(scope.canConstructDescriptors)
        let result = checkConstruction(scope)
        XCTAssertTrue(result.accepted)
        XCTAssertEqual(result.ancestorVisits, 12 + 1 + 16)
        XCTAssertEqual(result.childLinkVisits, 12 + 16)

        accepted.receipt.revoke()

        XCTAssertFalse(scope.canConstructDescriptors)
        XCTAssertFalse(accepted.receipt.isActive)
        let revoked = checkConstruction(scope)
        XCTAssertFalse(revoked.accepted)
        XCTAssertEqual(revoked.ancestorVisits, 0)
        XCTAssertEqual(revoked.childLinkVisits, 0)
    }

    func testFreshConstructionQueriesPreserveHostOwnerSupersessionAndPhaseGuards() async throws {
        for change in AttachmentQueryScopeChange.allCases {
            let tree = AttachmentQueryTree(depth: 3, leaves: 2)
            defer { withExtendedLifetime(tree) {} }
            let accepted = try acceptOrdinaryGroup(on: tree.leaves, in: tree.runtime)
            let actual = try XCTUnwrap(accepted.acceptedFacets.first?.actual)
            let bootstrap = tree.scope()
            let scope = try XCTUnwrap(
                bootstrap.withAdmittedOrdinaryDeferredSubtree(
                    originalActivity: accepted.receipt, originalAttachment: actual))
            XCTAssertTrue(scope.canConstructDescriptors)
            XCTAssertTrue(checkConstruction(scope).accepted)

            switch change {
            case .hostClose: tree.runtime.lazyListLogicalHostLifetime.revoke()
            case .ownerClose: tree.runtime.root.lazyListActivityStorage().descriptorOwnerLifetime.revoke()
            case .superseded: scope.noteSupersedingRequest()
            case .prepared: scope.preparationDidSucceed()
            case .revoked: scope.revoke()
            }

            XCTAssertFalse(scope.canConstructDescriptors)
            XCTAssertFalse(checkConstruction(scope).accepted)
            switch change {
            case .hostClose, .ownerClose: XCTAssertFalse(accepted.receipt.isActive)
            case .superseded, .prepared, .revoked: XCTAssertTrue(accepted.receipt.isActive)
            }
        }
    }

    func testCachedAncestryDoesNotCacheTargetAttachmentOrViewIdentityPermission() async throws {
        let tree = AttachmentQueryTree(depth: 2, leaves: 1)
        defer { withExtendedLifetime(tree) {} }
        let node = try XCTUnwrap(tree.leaves.first)
        let storage = node.lazyListActivityStorage()
        let original = tree.actual(node)
        let wrongTarget = RetainedLazyListActualAttachment(
            node: node, runtime: tree.runtime,
            target: RetainedLazyListTargetID(), attachment: storage.attachmentID)
        let wrongAttachment = RetainedLazyListActualAttachment(
            node: node, runtime: tree.runtime,
            target: storage.targetID, attachment: RetainedLazyListAttachmentID())
        for invalid in [wrongTarget, wrongAttachment] {
            let result = checkAttachments([original, invalid])
            XCTAssertFalse(result.accepted)
            XCTAssertEqual(result.ancestorVisits, 4)
            XCTAssertEqual(result.childLinkVisits, 3)
            XCTAssertFalse(invalid.isAttached)
        }

        // The hierarchy is unchanged. Equal-value identity assignment must
        // still invalidate the old witness after the fresh one warms the path.
        node.retainedViewIdentity = nil
        let freshIdentity = tree.actual(node)
        XCTAssertTrue(freshIdentity.isAttached)
        XCTAssertFalse(original.isAttached)
        let identityResult = checkAttachments([freshIdentity, original])
        XCTAssertFalse(identityResult.accepted)
        XCTAssertEqual(identityResult.ancestorVisits, 4)
        XCTAssertEqual(identityResult.childLinkVisits, 3)

        storage.revokeAttachment()
        let freshAttachment = tree.actual(node)
        XCTAssertTrue(freshAttachment.isAttached)
        XCTAssertFalse(freshIdentity.isAttached)
        let attachmentResult = checkAttachments([freshAttachment, freshIdentity])
        XCTAssertFalse(attachmentResult.accepted)
        XCTAssertEqual(attachmentResult.ancestorVisits, 4)
        XCTAssertEqual(attachmentResult.childLinkVisits, 3)
    }

    func testMovesDetachAndSameParentReinsertionDoNotReviveOldAttachments() async throws {
        let tree = AttachmentQueryTree(depth: 1, leaves: 1)
        defer { withExtendedLifetime(tree) {} }
        let node = try XCTUnwrap(tree.leaves.first)
        let originalParent = tree.branch
        let otherParent = ViewNode()
        tree.runtime.root.addChild(otherParent)
        let original = tree.actual(node)
        XCTAssertTrue(checkAttachments([original]).accepted)

        otherParent.addChild(node)
        let moved = tree.actual(node)
        XCTAssertTrue(node.parent === otherParent)
        XCTAssertTrue(moved.isAttached)
        XCTAssertFalse(original.isAttached)
        XCTAssertFalse(checkAttachments([moved, original]).accepted)

        originalParent.addChild(node)
        let returned = tree.actual(node)
        XCTAssertTrue(node.parent === originalParent)
        XCTAssertTrue(checkAttachments([returned]).accepted)
        XCTAssertFalse(checkAttachments([returned, original]).accepted)
        XCTAssertFalse(checkAttachments([returned, moved]).accepted)

        node.removeFromParent()
        XCTAssertNil(node.parent)
        XCTAssertFalse(returned.isAttached)
        XCTAssertFalse(checkAttachments([returned]).accepted)
        originalParent.addChild(node)
        let reinserted = tree.actual(node)
        XCTAssertTrue(reinserted.isAttached)
        XCTAssertFalse(checkAttachments([reinserted, returned]).accepted)
        XCTAssertFalse(checkAttachments([reinserted, original]).accepted)
    }

    func testAlternateRuntimeCannotReuseTheSameNodesValidRootEntry() async {
        let root = ViewNode()
        let firstRuntime = RetainedViewRuntime(root: root)
        let original = root.lazyListActivityStorage().captureActualAttachment(of: root, in: firstRuntime)
        XCTAssertTrue(checkAttachments([original]).accepted)
        let secondRuntime = RetainedViewRuntime(root: root)
        defer { withExtendedLifetime((firstRuntime, secondRuntime)) {} }
        let storage = root.lazyListActivityStorage()
        let second = storage.captureActualAttachment(of: root, in: secondRuntime)
        // All local identities are current; only the expected runtime differs.
        let foreign = storage.captureActualAttachment(of: root, in: firstRuntime)

        XCTAssertTrue(firstRuntime.root === secondRuntime.root)
        XCTAssertTrue(second.isAttached)
        XCTAssertFalse(foreign.isAttached)
        XCTAssertFalse(original.isAttached)
        let result = checkAttachments([second, foreign])
        XCTAssertFalse(result.accepted)
        XCTAssertEqual(result.ancestorVisits, 2)
        XCTAssertEqual(result.childLinkVisits, 0)
        XCTAssertEqual(
            checkAncestries([(root, secondRuntime), (root, firstRuntime), (root, secondRuntime)]).accepted,
            [true, false, true])
    }

    func testCachedRootDistanceCannotBypassTheOriginalTraversalLimit() async throws {
        let limit = ViewNode.maximumTraversalDepth
        let tree = AttachmentQueryTree(depth: limit, leaves: 0)
        defer { withExtendedLifetime(tree) {} }
        let root = tree.runtime.root
        let deepestAllowed = tree.chain[limit - 1]
        let tooDeep = tree.chain[limit]
        XCTAssertTrue(deepestAllowed.isRetainedLazyListAttached(in: tree.runtime))
        XCTAssertFalse(tooDeep.isRetainedLazyListAttached(in: tree.runtime))

        let result = checkAncestries([
            (root, tree.runtime), (deepestAllowed, tree.runtime),
            (tooDeep, tree.runtime), (tree.chain[1], tree.runtime),
        ])

        XCTAssertEqual(result.accepted, [true, true, false, true])
        XCTAssertEqual(result.ancestorVisits, limit + 1)
        XCTAssertEqual(result.childLinkVisits, limit)
        let fresh = checkAncestries([(tooDeep, tree.runtime), (deepestAllowed, tree.runtime)])
        XCTAssertEqual(fresh.accepted, [false, true], "A failed long prefix must not poison its valid suffix")
    }

    func testAuthoredHashCallbackEndsThePreviousQueryBeforeTheNextKey() async throws {
        for detach in [false, true] {
            let tree = AttachmentQueryTree(depth: 4, leaves: 3)
            defer { withExtendedLifetime(tree) {} }
            let accepted = try acceptOrdinaryGroup(on: tree.leaves, in: tree.runtime)
            let actual = try XCTUnwrap(accepted.acceptedFacets.first?.actual)
            let bootstrap = tree.scope()
            let scope = try XCTUnwrap(
                bootstrap.withAdmittedOrdinaryDeferredSubtree(
                    originalActivity: accepted.receipt, originalAttachment: actual))
            let events = AttachmentQueryHashEvents()
            events.onHash = {
                if detach {
                    tree.branch.removeFromParent()
                } else {
                    tree.leaves[0].retainedViewIdentity = nil
                }
            }
            let identity = RetainedViewIdentity(segments: [
                .keyed(.init(AttachmentQueryHashKey(0, events: events))),
                .keyed(.init(AttachmentQueryHashKey(1, events: events))),
            ])
            var hasher = Hasher()
            XCTAssertTrue(scope.canConstructDescriptors)
            XCTAssertTrue(checkConstruction(scope).accepted)

            let completed = identity.checkedHash(into: &hasher) { scope.canConstructDescriptors }

            XCTAssertFalse(completed)
            XCTAssertEqual(events.hashes, [0])
            XCTAssertFalse(scope.canConstructDescriptors)
            XCTAssertFalse(checkConstruction(scope).accepted)
            XCTAssertFalse(accepted.receipt.isActive)
            events.onHash = nil
        }
    }

    func testRetiringNodeRejectsBeforeItsParentAndRuntimeLinksAreRemoved() async throws {
        let tree = AttachmentQueryTree(depth: 0, leaves: 1)
        defer { withExtendedLifetime(tree) {} }
        let node = try XCTUnwrap(tree.leaves.first)
        let actual = tree.actual(node)
        let controller = AttachmentQueryRetirementController(runtime: tree.runtime)
        node.textInputController = controller
        let scope = tree.scope(origin: .componentHostRoot)
        let journal = RetainedLazyListAdoptionJournal(descriptorScope: scope, transaction: RetainedBuildTransaction())
        let preparation = try XCTUnwrap(journal.preparation())
        let prepared = RetainedLazyListPreparedActivity(preparation: preparation, logicalMembershipPlans: [])
        XCTAssertTrue(journal.beginAdoption(preparation, preparedActivity: prepared))
        XCTAssertTrue(checkAttachments([actual]).accepted)

        let result = tree.runtime.root.setChildren([], lazyJournal: journal)

        XCTAssertTrue(result.completed)
        XCTAssertEqual(controller.revocations, 1)
        XCTAssertTrue(controller.linksWereStillPresent)
        XCTAssertEqual(controller.originalWalkAccepted, false)
        XCTAssertEqual(controller.sharedWalkAccepted, [true, false])
        XCTAssertEqual(controller.ancestorVisits, 2)
        XCTAssertFalse(actual.isAttached)
        XCTAssertFalse(checkAttachments([actual]).accepted)
        _ = journal.seal(completedCheckedAdoption: result.completed)
        scope.finish()
        tree.runtime.root.addChild(node)
        XCTAssertTrue(checkAttachments([tree.actual(node)]).accepted)
        XCTAssertFalse(checkAttachments([tree.actual(node), actual]).accepted)
    }

    func testNativeQueriesDoNotHashAuthoredViewIdentities() async {
        let tree = AttachmentQueryTree(depth: 6, leaves: 8)
        defer { withExtendedLifetime(tree) {} }
        let events = AttachmentQueryHashEvents()
        for (index, node) in tree.leaves.enumerated() {
            node.retainedViewIdentity = RetainedViewIdentity(segments: [
                .explicit(.init(AttachmentQueryHashKey(index, events: events)))
            ])
        }
        let actuals = tree.leaves.map { tree.actual($0) }
        events.hashes.removeAll()

        let result = checkAttachments(actuals)

        XCTAssertTrue(result.accepted)
        XCTAssertEqual(result.ancestorVisits, 6 + 1 + 8)
        XCTAssertEqual(result.childLinkVisits, 6 + 8)
        XCTAssertTrue(events.hashes.isEmpty)
    }
}

private enum AttachmentQueryScopeChange: CaseIterable {
    case hostClose, ownerClose, superseded, prepared, revoked
}

private struct AttachmentQueryResult<Value> {
    let accepted: Value
    let ancestorVisits: Int
    let childLinkVisits: Int
}

/// These helpers return only scalar evidence. The mutable query cannot escape
/// into a test callback, mutation, assertion, or subsequent validity query.
@MainActor
private func checkAttachments(_ actuals: [RetainedLazyListActualAttachment]) -> AttachmentQueryResult<Bool> {
    var query = RetainedLazyListAttachmentQuery()
    let accepted = actuals.allSatisfy { $0.isAttached(using: &query) }
    return AttachmentQueryResult(
        accepted: accepted, ancestorVisits: query.ancestorVisits, childLinkVisits: query.childLinkVisits)
}

@MainActor
private func checkConstruction(_ scope: RetainedLazyListDescriptorBuildScope) -> AttachmentQueryResult<Bool> {
    var query = RetainedLazyListAttachmentQuery()
    let accepted = scope.canConstructDescriptors(using: &query)
    return AttachmentQueryResult(
        accepted: accepted, ancestorVisits: query.ancestorVisits, childLinkVisits: query.childLinkVisits)
}

@MainActor
private func checkAncestries(_ entries: [(ViewNode, RetainedViewRuntime)]) -> AttachmentQueryResult<[Bool]> {
    var query = RetainedLazyListAttachmentQuery()
    let accepted = entries.map { query.isAttached($0.0, in: $0.1) }
    return AttachmentQueryResult(
        accepted: accepted, ancestorVisits: query.ancestorVisits, childLinkVisits: query.childLinkVisits)
}

@MainActor
private final class AttachmentQueryTree {
    let runtime: RetainedViewRuntime
    let chain: [ViewNode]
    let leaves: [ViewNode]
    var branch: ViewNode { chain[chain.count - 1] }

    init(depth: Int, leaves count: Int) {
        let root = ViewNode()
        runtime = RetainedViewRuntime(root: root)
        var chain = [root]
        for _ in 0..<depth {
            let node = ViewNode()
            chain[chain.count - 1].addChild(node)
            chain.append(node)
        }
        self.chain = chain
        leaves = (0..<count).map { _ in ViewNode() }
        for leaf in leaves { chain[chain.count - 1].addChild(leaf) }
    }

    func actual(_ node: ViewNode) -> RetainedLazyListActualAttachment {
        node.lazyListActivityStorage().captureActualAttachment(of: node, in: runtime)
    }

    func scope(origin: RetainedLazyListDescriptorBuildOrigin = .managedSubtree) -> RetainedLazyListDescriptorBuildScope
    {
        RetainedLazyListDescriptorBuildScope(
            origin: origin, hostLifetime: runtime.lazyListLogicalHostLifetime,
            ownerLifetime: runtime.root.lazyListActivityStorage().descriptorOwnerLifetime)
    }
}

/// Exercise the existing native journal seam, including its complete footprint
/// requirements. This helper neither bypasses adoption nor weakens old tests.
@MainActor
private func acceptOrdinaryGroup(
    on targets: [ViewNode], in runtime: RetainedViewRuntime
) throws -> RetainedDescriptorAcceptedGroup {
    let scope = RetainedLazyListDescriptorBuildScope(
        origin: .componentHostRoot, hostLifetime: runtime.lazyListLogicalHostLifetime,
        ownerLifetime: runtime.root.lazyListActivityStorage().descriptorOwnerLifetime)
    let journal = RetainedLazyListAdoptionJournal(descriptorScope: scope, transaction: RetainedBuildTransaction())
    let attribution = try XCTUnwrap(scope.registerOrdinaryComponent())
    let group = try XCTUnwrap(attribution.registerGroup(kind: .deferredSubtree))
    let sources = targets.map { _ in ViewNode() }
    for source in sources { XCTAssertTrue(attribution.recordSourceOutput(source, group: group)) }
    _ = try XCTUnwrap(attribution.closeGroup(group))
    XCTAssertTrue(journal.beginOrdinaryAdoption())
    XCTAssertTrue(journal.markMutationStarted())
    for (source, target) in zip(sources, targets) {
        _ = journal.recordAcceptedAttachment(from: source, to: target)
        _ = journal.recordCompletedNode(from: source, to: target)
    }
    let disposition = journal.seal(completedCheckedAdoption: true)
    let accepted = try XCTUnwrap(disposition.acceptedOrdinaryGroups.first { $0.proposal.group === group })
    XCTAssertTrue(accepted.receipt.isActive)
    scope.finish()
    return accepted
}

@MainActor
private final class AttachmentQueryHashEvents {
    var hashes: [Int] = []
    var onHash: (@MainActor () -> Void)?
}

private struct AttachmentQueryHashKey: Hashable {
    let value: Int
    let events: AttachmentQueryHashEvents

    init(_ value: Int, events: AttachmentQueryHashEvents) {
        self.value = value
        self.events = events
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.value == rhs.value }

    func hash(into hasher: inout Hasher) {
        MainActor.assumeIsolated {
            events.hashes.append(value)
            events.onHash?()
        }
        hasher.combine(value)
    }
}

/// Revocation records native booleans only: no authored callback or payload is
/// invoked or released while the runtime is installing its retirement gates.
@MainActor
private final class AttachmentQueryRetirementController: RetainedTextInputController {
    private weak var runtime: RetainedViewRuntime?
    private(set) var revocations = 0
    private(set) var linksWereStillPresent = false
    private(set) var originalWalkAccepted: Bool?
    private(set) var sharedWalkAccepted: [Bool] = []
    private(set) var ancestorVisits = 0

    init(runtime: RetainedViewRuntime) { self.runtime = runtime }

    func attach(to node: ViewNode) {}
    func reconcile(from previous: (any RetainedTextInputController)?, onto node: ViewNode) {}
    func detach(from node: ViewNode) {}

    func revokeOwnership(from node: ViewNode) {
        guard let runtime else { return }
        revocations += 1
        linksWereStillPresent =
            node.parent === runtime.root && runtime.root.children.contains { $0 === node }
            && node.retainedLazyListRuntime === runtime
        originalWalkAccepted = node.isRetainedLazyListAttached(in: runtime)
        let result = checkAncestries([(runtime.root, runtime), (node, runtime)])
        sharedWalkAccepted = result.accepted
        ancestorVisits = result.ancestorVisits
    }
}
