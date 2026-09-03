import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI

/// Real native insertion after one failed combined preparation. No preparation
/// retry, forced receipt, private table write, rendering, or asynchronous polling.
@MainActor
final class OrdinaryPreparedInsertionIsolationTests: XCTestCase {
    func testOwnedRefusalDoesNotDiscardPreparedOrdinaryDeferredAttachment() async throws {
        let fixture = try PreparedInsertionFixture()
        defer { fixture.finish() }
        let source = preparedInsertionNode()
        let next = PreparedInsertionEpoch(fixture.runtime)
        defer { next.finish() }
        let component = try next.component(source, continuing: fixture.original, slots: [fixture.slot])
        let preparation = try next.begin()
        let plan = try XCTUnwrap(preparation.ownedComponentDeclarations.first { $0.receipt === component.owned })
        XCTAssertEqual(plan.sourcePayloads.count, 1)
        XCTAssertEqual(component.proposal.requiredFacets.count, 2)

        fixture.removeOriginal()
        assertPreparedInsertionRefusalIsLocal(fixture, next: next, incoming: component.owned)
        // Ordinary preparation runs before the revoked owned plan is rejected.
        // This is the only preparation call for this source.
        XCTAssertFalse(next.journal.prepareInsertedNode(from: source))
        XCTAssertTrue(next.journal.canContinueAdoption)
        let storage = source.lazyListActivityStorage()
        let target = storage.targetID
        let attachment = storage.attachmentID
        XCTAssertNil(source.retainedLazyListRuntime)
        fixture.runtime.root.addChild(source)
        XCTAssertTrue(source.parent === fixture.runtime.root)
        XCTAssertTrue(source.retainedLazyListRuntime === fixture.runtime)
        XCTAssertTrue(storage.targetID === target)
        XCTAssertTrue(storage.attachmentID === attachment)

        XCTAssertTrue(next.journal.recordAcceptedInsertedNode(on: source).isEmpty)
        XCTAssertTrue(next.journal.recordAcceptedInsertedNode(on: source).isEmpty)
        XCTAssertFalse(component.contribution.isActive, "Insertion cannot manufacture node completion")
        XCTAssertNil(storage.descriptorDeferredSubtreeAnchor)
        XCTAssertTrue(next.journal.takeAcceptedDescriptorTaskGroups().isEmpty)
        assertPreparedInsertionRefusalIsLocal(fixture, next: next, incoming: component.owned)
        _ = next.journal.recordCompletedNode(from: source, to: source)

        let anchor = try XCTUnwrap(storage.descriptorDeferredSubtreeAnchor)
        XCTAssertTrue(anchor.contribution === component.contribution)
        XCTAssertTrue(anchor.contribution.isActive)
        XCTAssertTrue(anchor.actual.isAttached)
        XCTAssertTrue(anchor.actual.node === source)
        XCTAssertTrue(anchor.actual.target === target)
        XCTAssertTrue(anchor.actual.attachment === attachment)
        let disposition = next.finish()
        let accepted = try XCTUnwrap(
            disposition.acceptedOrdinaryGroups.first { $0.proposal.group === component.group })
        XCTAssertTrue(accepted.receipt === component.contribution)
        XCTAssertEqual(accepted.acceptedFacets.count, 2)
        XCTAssertEqual(accepted.acceptedFacets.filter { isPreparedInsertionAttachment($0) }.count, 1)
        XCTAssertEqual(accepted.acceptedFacets.filter { isPreparedInsertionCompletion($0) }.count, 1)
        XCTAssertTrue(disposition.acceptedOwnedComponents.filter { $0.plan === plan }.isEmpty)
        XCTAssertFalse(component.owned.hasAcceptedDeclaration)
        XCTAssertFalse(component.owned.hasDeclaredComponent)
        XCTAssertTrue(component.owned.owner.isRevoked)
        XCTAssertFalse(component.owned.hasAcceptedOwnership(for: fixture.slot))
        XCTAssertFalse(component.owned.permitsOwnedWrite(for: fixture.slot))
        XCTAssertTrue(component.contribution.isActive, "Finishing the epoch does not retire an accepted reader")

        // Native deferred admission is the lease oracle here. This is not a
        // claim about facade StateMountSubtreeLease construction or rendering.
        let later = PreparedInsertionEpoch(fixture.runtime, origin: .managedSubtree)
        defer { later.finish() }
        let admitted = try XCTUnwrap(
            later.scope.withAdmittedOrdinaryDeferredSubtree(
                originalActivity: component.contribution, originalAttachment: anchor.actual))
        XCTAssertTrue(admitted.canConstructDescriptors)
        fixture.runtime.root.removeChild(source)
        XCTAssertFalse(anchor.actual.isAttached)
        XCTAssertFalse(component.contribution.isActive)
        XCTAssertFalse(admitted.canConstructDescriptors)
    }

    func testMixedScopedTaskPendingInsertionCannotUseTheOrdinaryFallback() async throws {
        let fixture = try PreparedInsertionFixture()
        defer { fixture.finish() }
        let source = preparedInsertionNode()
        let next = PreparedInsertionEpoch(fixture.runtime)
        defer { next.finish() }
        let component = try next.component(source, continuing: fixture.original, slots: [fixture.slot])
        let taskGroup = try XCTUnwrap(component.attribution.registerGroup(kind: .scopedTask))
        let task = RetainedTaskDeclaration(
            mount: RetainedTaskMountToken(), priority: .userInitiated, action: {},
            isMember: { true }, isCurrentProposal: { true })
        XCTAssertTrue(
            task.stage(
                groupSources: [source], in: fixture.runtime,
                descriptorAttribution: component.attribution, group: taskGroup))
        source.onAppearWithNode = { [weak task] node in task?.appear(on: node) }
        source.onDisappearWithNode = { [weak task] node in task?.disappear(from: node) }
        let taskProposal = try XCTUnwrap(component.attribution.closeGroup(taskGroup))
        let taskContribution = try XCTUnwrap(component.attribution.contribution(for: taskGroup))
        XCTAssertEqual(taskProposal.requiredFacets.count, 4)
        let candidates = try XCTUnwrap(source.existingRetainedTaskState).descriptorCandidateDeclarations()
        XCTAssertTrue(
            candidates.contains { candidate in
                candidate.group === taskGroup && candidate.declarations.contains { $0 === task.declarationID }
            }, "Use real staged Task input so ordinary insertion preparation is supported")
        XCTAssertFalse(task.canCommit)
        _ = try next.begin()
        fixture.removeOriginal()
        assertPreparedInsertionRefusalIsLocal(fixture, next: next, incoming: component.owned)
        // Both the deferred and Task facets are in the same ordinary pending
        // ticket before the later owned-plan refusal. Never prepare again.
        XCTAssertFalse(next.journal.prepareInsertedNode(from: source))
        XCTAssertTrue(next.journal.canContinueAdoption)
        fixture.runtime.root.addChild(source)
        XCTAssertTrue(source.parent === fixture.runtime.root)
        XCTAssertTrue(next.journal.recordAcceptedInsertedNode(on: source).isEmpty)
        XCTAssertTrue(next.journal.takeAcceptedDescriptorTaskGroups().isEmpty)
        XCTAssertFalse(taskContribution.isActive)
        XCTAssertFalse(task.canCommit)
        XCTAssertFalse(component.contribution.isActive)
        _ = next.journal.recordCompletedNode(from: source, to: source)
        XCTAssertTrue(next.journal.takeAcceptedDescriptorTaskGroups().isEmpty)
        XCTAssertFalse(taskContribution.isActive)
        XCTAssertFalse(task.canCommit)
        XCTAssertNil(source.lazyListActivityStorage().descriptorDeferredSubtreeAnchor)
        let disposition = next.finish()
        XCTAssertTrue(disposition.acceptedOrdinaryGroups.isEmpty)
        XCTAssertTrue(disposition.acceptedOrdinaryFacets.filter { $0.group === taskGroup }.isEmpty)
        let deferredFacts = disposition.acceptedOrdinaryFacets.filter { $0.group === component.group }
        XCTAssertEqual(deferredFacts.count, 1)
        XCTAssertTrue(deferredFacts.allSatisfy { isPreparedInsertionCompletion($0) })
        let partial = try XCTUnwrap(
            disposition.partialOrdinaryGroups.first { $0.proposal.group === component.group })
        XCTAssertEqual(partial.unacceptedFacets.count, 1)
        XCTAssertTrue(disposition.acceptedOwnedComponents.isEmpty)
        XCTAssertFalse(component.owned.hasAcceptedDeclaration)
        XCTAssertTrue(component.owned.owner.isRevoked)
        XCTAssertFalse(component.owned.permitsOwnedWrite(for: fixture.slot))
        withExtendedLifetime(task) {}
    }

    func testOriginalPendingInsertionCannotRebindAfterSourceAndAttachmentChanges() async throws {
        let fixture = try PreparedInsertionFixture()
        defer { fixture.finish() }
        let source = preparedInsertionNode()
        let next = PreparedInsertionEpoch(fixture.runtime)
        defer { next.finish() }
        let component = try next.component(source, continuing: fixture.original, slots: [fixture.slot])
        _ = try next.begin()
        fixture.removeOriginal()
        assertPreparedInsertionRefusalIsLocal(fixture, next: next, incoming: component.owned)
        XCTAssertFalse(next.journal.prepareInsertedNode(from: source))
        let storage = source.lazyListActivityStorage()
        let target = storage.targetID
        let originalAttachment = storage.attachmentID

        // A different actual source cannot consume the original source's
        // ticket. It has no copied descriptor stamps or fabricated receipt.
        let replacement = preparedInsertionNode()
        fixture.runtime.root.addChild(replacement)
        XCTAssertFalse(replacement.lazyListActivityStorage().targetID === target)
        XCTAssertTrue(next.journal.recordAcceptedInsertedNode(on: replacement).isEmpty)
        XCTAssertNil(replacement.lazyListActivityStorage().descriptorDeferredSubtreeAnchor)
        XCTAssertFalse(component.contribution.isActive)
        fixture.runtime.root.removeChild(replacement)

        fixture.runtime.root.addChild(source)
        XCTAssertTrue(storage.attachmentID === originalAttachment)
        let originalActual = storage.captureActualAttachment(of: source, in: fixture.runtime)
        XCTAssertTrue(originalActual.isAttached)
        fixture.runtime.root.removeChild(source)
        XCTAssertFalse(originalActual.isAttached)
        XCTAssertFalse(storage.attachmentID === originalAttachment)
        fixture.runtime.root.addChild(source)
        XCTAssertTrue(source.parent === fixture.runtime.root)
        XCTAssertTrue(source.retainedLazyListRuntime === fixture.runtime)
        XCTAssertTrue(storage.targetID === target)
        XCTAssertFalse(storage.attachmentID === originalAttachment)
        XCTAssertTrue(storage.captureActualAttachment(of: source, in: fixture.runtime).isAttached)
        XCTAssertTrue(next.scope.canPublishDescriptors)
        XCTAssertTrue(next.journal.canContinueAdoption)
        // Do not retry preparation after the physical A -> detached -> A move.
        XCTAssertTrue(next.journal.recordAcceptedInsertedNode(on: source).isEmpty)
        _ = next.journal.recordCompletedNode(from: source, to: source)
        XCTAssertFalse(component.contribution.isActive)
        XCTAssertNil(storage.descriptorDeferredSubtreeAnchor)
        XCTAssertTrue(next.journal.takeAcceptedDescriptorTaskGroups().isEmpty)
        let disposition = next.finish()
        let facts = disposition.acceptedOrdinaryFacets.filter { $0.group === component.group }
        XCTAssertEqual(facts.count, 1)
        XCTAssertTrue(facts.allSatisfy { isPreparedInsertionCompletion($0) })
        XCTAssertTrue(disposition.acceptedOrdinaryGroups.isEmpty)
        let partial = try XCTUnwrap(
            disposition.partialOrdinaryGroups.first { $0.proposal.group === component.group })
        XCTAssertEqual(partial.unacceptedFacets.count, 1)
        XCTAssertTrue(disposition.acceptedOwnedComponents.isEmpty)
        XCTAssertFalse(component.owned.hasAcceptedDeclaration)
        XCTAssertTrue(component.owned.owner.isRevoked)
        XCTAssertFalse(component.owned.permitsOwnedWrite(for: fixture.slot))
    }
}

@MainActor
private func preparedInsertionNode() -> ViewNode {
    let node = ViewNode()
    node.retainedViewIdentity = nil
    return node
}

@MainActor
private struct PreparedInsertionComponent {
    let attribution: RetainedDescriptorComponentAttribution
    let owned: RetainedOwnedComponentReceipt
    let group: RetainedDescriptorGroupID
    let proposal: RetainedDescriptorGroupProposal
    let contribution: RetainedDescriptorContributionReceipt
}

@MainActor
private final class PreparedInsertionEpoch {
    let runtime: RetainedViewRuntime
    let scope: RetainedLazyListDescriptorBuildScope
    let journal: RetainedLazyListAdoptionJournal
    private var components: [PreparedInsertionComponent] = []
    private var sources: [ViewNode] = []
    private var disposition: RetainedLazyListAdoptionDisposition?

    init(
        _ runtime: RetainedViewRuntime,
        origin: RetainedLazyListDescriptorBuildOrigin = .componentHostRoot
    ) {
        self.runtime = runtime
        scope = RetainedLazyListDescriptorBuildScope(
            origin: origin, hostLifetime: runtime.lazyListLogicalHostLifetime,
            ownerLifetime: runtime.root.lazyListActivityStorage().descriptorOwnerLifetime)
        journal = RetainedLazyListAdoptionJournal(descriptorScope: scope, transaction: RetainedBuildTransaction())
    }

    func component(
        _ source: ViewNode, continuing: RetainedOwnedComponentReceipt? = nil,
        slots: [RetainedOwnedSlotGenerationID], kind: RetainedLazyListContributionKind = .deferredSubtree
    ) throws -> PreparedInsertionComponent {
        let attribution = try XCTUnwrap(scope.registerOrdinaryComponent())
        let owned = try XCTUnwrap(
            attribution.registerOwnedComponent(
                owner: continuing?.owner ?? RetainedOwnedComponentID(), slots: slots, continuing: continuing))
        let group = try XCTUnwrap(attribution.registerGroup(kind: kind))
        XCTAssertTrue(attribution.recordSourceOutput(source, group: group))
        let proposal = try XCTUnwrap(attribution.closeGroup(group))
        let contribution = try XCTUnwrap(attribution.contribution(for: group))
        let component = PreparedInsertionComponent(
            attribution: attribution, owned: owned, group: group, proposal: proposal, contribution: contribution)
        components.append(component)
        sources.append(source)
        return component
    }

    func begin() throws -> RetainedLazyListAdoptionPreparation {
        let preparation = try XCTUnwrap(journal.preparation())
        XCTAssertTrue(journal.beginOrdinaryAdoption())
        XCTAssertTrue(journal.markMutationStarted())
        XCTAssertTrue(scope.canPublishDescriptors)
        return preparation
    }

    @discardableResult
    func finish() -> RetainedLazyListAdoptionDisposition {
        if let disposition { return disposition }
        let result = journal.seal(completedCheckedAdoption: true)
        journal.releaseUnadoptedTransport()
        scope.finish()
        disposition = result
        return result
    }
}

@MainActor
private final class PreparedInsertionFixture {
    let runtime: RetainedViewRuntime
    let oldNode: ViewNode
    let slot: RetainedOwnedSlotGenerationID
    let seed: PreparedInsertionEpoch
    let original: RetainedOwnedComponentReceipt

    init() throws {
        let runtime = RetainedViewRuntime(root: preparedInsertionNode())
        self.runtime = runtime
        let oldNode = preparedInsertionNode()
        self.oldNode = oldNode
        let slot = RetainedOwnedSlotGenerationID()
        self.slot = slot
        let seed = PreparedInsertionEpoch(runtime)
        self.seed = seed
        let component = try seed.component(oldNode, slots: [slot], kind: .observation)
        original = component.owned
        _ = try seed.begin()
        XCTAssertTrue(seed.journal.prepareInsertedNode(from: oldNode))
        runtime.root.addChild(oldNode)
        _ = seed.journal.recordAcceptedInsertedNode(on: oldNode)
        _ = seed.journal.recordCompletedNode(from: oldNode, to: oldNode)
        let disposition = seed.finish()
        XCTAssertTrue(disposition.acceptedOwnedComponents.contains { $0.plan.receipt === original })
        XCTAssertTrue(original.hasAcceptedDeclaration)
        XCTAssertTrue(original.hasDeclaredComponent)
        XCTAssertTrue(original.hasAcceptedOwnership(for: slot))
        XCTAssertTrue(original.permitsOwnedWrite(for: slot))
        XCTAssertFalse(original.owner.isRevoked)
    }

    func removeOriginal() {
        XCTAssertTrue(oldNode.parent === runtime.root)
        runtime.root.removeChild(oldNode)
        XCTAssertNil(oldNode.parent)
        XCTAssertNil(oldNode.retainedLazyListRuntime)
        XCTAssertTrue(original.owner.isRevoked)
        XCTAssertFalse(original.hasDeclaredComponent)
        XCTAssertFalse(original.hasAcceptedOwnership(for: slot))
        XCTAssertFalse(original.permitsOwnedWrite(for: slot))
    }

    func finish() {
        runtime.root.removeAllChildren()
        _ = seed.finish()
    }
}

@MainActor
private func assertPreparedInsertionRefusalIsLocal(
    _ fixture: PreparedInsertionFixture, next: PreparedInsertionEpoch, incoming: RetainedOwnedComponentReceipt,
    file: StaticString = #filePath, line: UInt = #line
) {
    XCTAssertTrue(fixture.runtime.lazyListLogicalHostLifetime.isOpen, file: file, line: line)
    XCTAssertTrue(next.scope.canPublishDescriptors, file: file, line: line)
    XCTAssertTrue(next.journal.canContinueAdoption, file: file, line: line)
    XCTAssertTrue(incoming.owner === fixture.original.owner, file: file, line: line)
    XCTAssertTrue(incoming.owner.isRevoked, file: file, line: line)
    XCTAssertFalse(incoming.hasAcceptedDeclaration, file: file, line: line)
    XCTAssertFalse(incoming.hasDeclaredComponent, file: file, line: line)
    XCTAssertFalse(incoming.hasAcceptedOwnership(for: fixture.slot), file: file, line: line)
    XCTAssertFalse(incoming.permitsOwnedWrite(for: fixture.slot), file: file, line: line)
}

@MainActor
private func isPreparedInsertionAttachment(_ fact: RetainedDescriptorAcceptedFacet) -> Bool {
    if case .childAttachment = fact.nativeField { return true }
    return false
}

@MainActor
private func isPreparedInsertionCompletion(_ fact: RetainedDescriptorAcceptedFacet) -> Bool {
    if case .nodeCompletion = fact.nativeField { return true }
    return false
}
