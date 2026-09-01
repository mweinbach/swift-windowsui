import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI

@MainActor
final class OrdinarySourceCompletionTests: XCTestCase {
    func testKeyedReorderKeepsTheDescriptorCompletedFromEachOriginalCandidate() async throws {
        let first = completionNode(1)
        let second = completionNode(2)
        let runtime = RetainedViewRuntime(root: ViewNode(children: [first, second]))
        let scope = completionScope(runtime)
        let journal = RetainedLazyListAdoptionJournal(descriptorScope: scope, transaction: RetainedBuildTransaction())
        let firstSource = completionNode(1)
        let secondSource = completionNode(2)
        let firstReceipt = try completionGroup([firstSource], in: scope)
        let secondReceipt = try completionGroup([secondSource], in: scope)
        XCTAssertTrue(journal.beginOrdinaryAdoption())

        let result = ComponentHost.reconcileChildren(
            of: runtime.root, oldChildren: runtime.root.children, newNodes: [secondSource, firstSource],
            lazyJournal: journal)

        XCTAssertTrue(result.completed)
        XCTAssertTrue(runtime.root.children[0] === second)
        XCTAssertTrue(runtime.root.children[1] === first)
        XCTAssertTrue(firstReceipt.isActive)
        XCTAssertTrue(secondReceipt.isActive)
        _ = journal.seal(completedCheckedAdoption: true)
        journal.releaseUnadoptedTransport()
        scope.finish()
        XCTAssertTrue(firstReceipt.isActive)
        XCTAssertTrue(secondReceipt.isActive)

        runtime.root.removeChild(first)
        XCTAssertFalse(firstReceipt.isActive)
        runtime.root.addChild(first)
        XCTAssertFalse(firstReceipt.isActive, "Source membership cannot revive a departed contribution")
        XCTAssertTrue(secondReceipt.isActive)
    }

    func testMixedReorderCompletesNewSubtreesWithoutRetiringMatchedDescriptors() async throws {
        let first = completionNode(1)
        let second = completionNode(2)
        let runtime = RetainedViewRuntime(root: ViewNode(children: [first, second]))
        let scope = completionScope(runtime)
        let journal = RetainedLazyListAdoptionJournal(descriptorScope: scope, transaction: RetainedBuildTransaction())
        let insertedChild = completionNode(10)
        let firstSource = completionNode(1, children: [insertedChild])
        let secondSource = completionNode(2)
        let insertedLeaf = completionNode(30)
        let insertedRoot = completionNode(3, children: [insertedLeaf])
        let firstReceipt = try completionGroup([firstSource, insertedChild], in: scope)
        let secondReceipt = try completionGroup([secondSource], in: scope)
        let insertedReceipt = try completionGroup([insertedRoot, insertedLeaf], in: scope)
        XCTAssertTrue(journal.beginOrdinaryAdoption())

        let result = ComponentHost.reconcileChildren(
            of: runtime.root, oldChildren: runtime.root.children,
            newNodes: [secondSource, firstSource, insertedRoot], lazyJournal: journal)

        XCTAssertTrue(result.completed)
        XCTAssertEqual(runtime.root.children.count, 3)
        XCTAssertTrue(runtime.root.children[0] === second)
        XCTAssertTrue(runtime.root.children[1] === first)
        XCTAssertTrue(runtime.root.children[2] === insertedRoot)
        XCTAssertTrue(first.children.first === insertedChild)
        XCTAssertTrue(insertedRoot.children.first === insertedLeaf)
        XCTAssertTrue(firstReceipt.isActive)
        XCTAssertTrue(secondReceipt.isActive)
        XCTAssertTrue(insertedReceipt.isActive)
        let disposition = journal.seal(completedCheckedAdoption: true)
        for receipt in [firstReceipt, secondReceipt, insertedReceipt] {
            XCTAssertTrue(disposition.acceptedOrdinaryGroups.contains { $0.receipt === receipt })
        }
        journal.releaseUnadoptedTransport()
        scope.finish()
    }

    func testDirectSetterStillCompletesExplicitSameObjectSources() async throws {
        let first = completionNode(1)
        let second = completionNode(2)
        let runtime = RetainedViewRuntime(root: ViewNode(children: [first, second]))
        let scope = completionScope(runtime)
        let journal = RetainedLazyListAdoptionJournal(descriptorScope: scope, transaction: RetainedBuildTransaction())
        let receipt = try completionGroup([first, second], in: scope)
        XCTAssertTrue(journal.beginOrdinaryAdoption())
        XCTAssertTrue(journal.markMutationStarted())
        _ = journal.recordAcceptedAttachment(from: first, to: first)
        _ = journal.recordAcceptedAttachment(from: second, to: second)
        XCTAssertFalse(receipt.isActive, "Attachment alone is not node completion")

        let result = runtime.root.setChildren([second, first], lazyJournal: journal)

        XCTAssertTrue(result.completed)
        XCTAssertTrue(receipt.isActive)
        let disposition = journal.seal(completedCheckedAdoption: true)
        XCTAssertTrue(disposition.acceptedOrdinaryGroups.contains { $0.receipt === receipt })
        journal.releaseUnadoptedTransport()
        scope.finish()
        runtime.root.setChildren([])
        XCTAssertFalse(receipt.isActive)
    }

    func testReconciliationStillCompletesExplicitSameObjectSources() async throws {
        let first = completionNode(1)
        let second = completionNode(2)
        let runtime = RetainedViewRuntime(root: ViewNode(children: [first, second]))
        let scope = completionScope(runtime)
        let journal = RetainedLazyListAdoptionJournal(descriptorScope: scope, transaction: RetainedBuildTransaction())
        let receipt = try completionGroup([first, second], in: scope)
        XCTAssertTrue(journal.beginOrdinaryAdoption())

        let result = ComponentHost.reconcileChildren(
            of: runtime.root, oldChildren: runtime.root.children, newNodes: [second, first], lazyJournal: journal)

        XCTAssertTrue(result.completed)
        XCTAssertTrue(runtime.root.children[0] === second)
        XCTAssertTrue(runtime.root.children[1] === first)
        XCTAssertTrue(receipt.isActive)
        let disposition = journal.seal(completedCheckedAdoption: true)
        XCTAssertTrue(disposition.acceptedOrdinaryGroups.contains { $0.receipt === receipt })
        journal.releaseUnadoptedTransport()
        scope.finish()
    }

    func testDirectAdoptionKeepsOriginalSourceCompletionAcrossChildReordering() async throws {
        let first = completionNode(1)
        let second = completionNode(2)
        let target = completionNode(3, children: [first, second])
        let runtime = RetainedViewRuntime(root: ViewNode(children: [target]))
        let scope = completionScope(runtime)
        let journal = RetainedLazyListAdoptionJournal(descriptorScope: scope, transaction: RetainedBuildTransaction())
        let firstSource = completionNode(1)
        let secondSource = completionNode(2)
        let source = completionNode(3, children: [secondSource, firstSource])
        let receipt = try completionGroup([firstSource, secondSource], in: scope)
        XCTAssertTrue(journal.beginOrdinaryAdoption())

        let result = ComponentHost.adopt(source: source, into: target, lazyJournal: journal)

        XCTAssertTrue(result.completed)
        XCTAssertTrue(target.children[0] === second)
        XCTAssertTrue(target.children[1] === first)
        XCTAssertTrue(receipt.isActive)
        _ = journal.seal(completedCheckedAdoption: true)
        journal.releaseUnadoptedTransport()
        scope.finish()
        XCTAssertTrue(receipt.isActive)
    }

    func testMatchingCallbackCannotAddAReplacementToTheOriginalSourceRoster() async throws {
        let mutation = CompletionMatchingMutation()
        let originalChild = completionNode(10)
        let source = completionNode(1, children: [originalChild])
        source.retainedViewIdentity = RetainedViewIdentity(
            segments: [.explicit(.init(CompletionMatchingKey(value: 1, mutation: mutation)))])
        let target = completionNode(1)
        target.retainedViewIdentity = RetainedViewIdentity(
            segments: [.explicit(.init(CompletionMatchingKey(value: 1, mutation: mutation)))])
        let runtime = RetainedViewRuntime(root: ViewNode(children: [target]))
        let scope = completionScope(runtime)
        let journal = RetainedLazyListAdoptionJournal(descriptorScope: scope, transaction: RetainedBuildTransaction())
        let replacement = completionNode(20)
        let receipt = try completionGroup([replacement], in: scope)
        XCTAssertTrue(journal.beginOrdinaryAdoption())
        mutation.action = { [weak source, weak replacement] in
            guard let replacement else { return }
            source?.setChildren([replacement])
        }

        let result = ComponentHost.reconcileChildren(
            of: runtime.root, oldChildren: runtime.root.children, newNodes: [source], lazyJournal: journal)

        XCTAssertEqual(mutation.calls, 1)
        XCTAssertTrue(result.completed)
        XCTAssertTrue(target.children.first === replacement)
        XCTAssertFalse(receipt.isActive, "Ordinary publication cannot invent an original source-completion fact")
        let disposition = journal.seal(completedCheckedAdoption: true)
        XCTAssertFalse(disposition.acceptedOrdinaryGroups.contains { $0.receipt === receipt })
        journal.releaseUnadoptedTransport()
        scope.finish()
    }

    func testOriginalSourceMembershipDoesNotRetainNodesOrTheirAuthoredPayloads() async throws {
        let releases = CompletionSourceReleases()
        var source: ViewNode? = completionNodeWithPayload(releases)
        weak var original = source
        let membership = try XCTUnwrap(RetainedReconciliationSourceNodes(roots: [try XCTUnwrap(source)]))
        XCTAssertTrue(membership.contains(try XCTUnwrap(source)))

        source = nil

        XCTAssertNil(original)
        XCTAssertEqual(releases.count, 1)
        XCTAssertFalse(membership.contains(completionNode(1)))
    }

    func testSourceMembershipDoesNotRecaptureReplacementsOrGrantAttachmentPermission() async throws {
        let original = completionNode(1)
        let parent = ViewNode(children: [original])
        let membership = try XCTUnwrap(RetainedReconciliationSourceNodes(roots: [parent]))
        let attachment = original.captureLazyListAttachmentProof()
        let replacement = completionNode(1)

        parent.setChildren([replacement])

        XCTAssertTrue(membership.contains(original), "Membership records an original source, not current permission")
        XCTAssertFalse(membership.contains(replacement))
        XCTAssertFalse(attachment.isCurrent)
        parent.setChildren([original])
        XCTAssertTrue(membership.contains(original))
        XCTAssertFalse(attachment.isCurrent, "Reattachment does not refresh the original attachment proof")
        XCTAssertFalse(membership.contains(replacement))
    }

    func testMalformedSourceForestCannotBecomeAnUnrestrictedCompletionReplay() async throws {
        let source = completionNode(1)
        XCTAssertNil(RetainedReconciliationSourceNodes(roots: [source, source]))
        let target = completionNode(2)
        let runtime = RetainedViewRuntime(root: ViewNode(children: [target]))
        let scope = completionScope(runtime)
        let journal = RetainedLazyListAdoptionJournal(descriptorScope: scope, transaction: RetainedBuildTransaction())
        let receipt = try completionGroup([source], in: scope)
        XCTAssertTrue(journal.beginOrdinaryAdoption())

        let result = ComponentHost.reconcileChildren(
            of: runtime.root, oldChildren: runtime.root.children, newNodes: [source, source], lazyJournal: journal)

        XCTAssertFalse(result.completed)
        XCTAssertEqual(runtime.root.children.count, 1)
        XCTAssertTrue(runtime.root.children.first === target)
        XCTAssertFalse(receipt.isActive)
        _ = journal.seal()
        journal.releaseUnadoptedTransport()
        scope.finish()
    }
}

@MainActor
private func completionNode(_ identity: Int, children: [ViewNode] = []) -> ViewNode {
    let node = ViewNode(children: children)
    node.retainedViewIdentity = RetainedViewIdentity().appending(.slot(identity))
    return node
}

@MainActor
private func completionScope(_ runtime: RetainedViewRuntime) -> RetainedLazyListDescriptorBuildScope {
    RetainedLazyListDescriptorBuildScope(
        origin: .componentHostRoot, hostLifetime: runtime.lazyListLogicalHostLifetime,
        ownerLifetime: runtime.root.lazyListActivityStorage().descriptorOwnerLifetime)
}

@MainActor
private func completionGroup(
    _ sources: [ViewNode], in scope: RetainedLazyListDescriptorBuildScope
) throws -> RetainedDescriptorContributionReceipt {
    let component = try XCTUnwrap(scope.registerOrdinaryComponent())
    let group = try XCTUnwrap(component.registerGroup(kind: .observation))
    for source in sources { XCTAssertTrue(component.recordSourceOutput(source, group: group)) }
    _ = try XCTUnwrap(component.closeGroup(group))
    return try XCTUnwrap(component.contribution(for: group))
}

@MainActor
private final class CompletionSourceReleases {
    var count = 0
}

@MainActor
private final class CompletionMatchingMutation {
    var action: (() -> Void)?
    var calls = 0

    func fire() {
        guard let action else { return }
        self.action = nil
        calls += 1
        action()
    }
}

private struct CompletionMatchingKey: Hashable {
    let value: Int
    let mutation: CompletionMatchingMutation

    static func == (lhs: Self, rhs: Self) -> Bool {
        MainActor.assumeIsolated { lhs.mutation.fire() }
        return lhs.value == rhs.value
    }

    func hash(into hasher: inout Hasher) { hasher.combine(value) }
}

@MainActor
private final class CompletionSourcePayload {
    let releases: CompletionSourceReleases

    init(_ releases: CompletionSourceReleases) { self.releases = releases }
    isolated deinit { releases.count += 1 }
}

@MainActor
@inline(never)
private func completionNodeWithPayload(_ releases: CompletionSourceReleases) -> ViewNode {
    let payload = CompletionSourcePayload(releases)
    let node = completionNode(1)
    node.onAppear = { withExtendedLifetime(payload) {} }
    return node
}
