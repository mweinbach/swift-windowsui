@preconcurrency import XCTest

@testable import SwiftWindowsUI

/// Native scalar and receipt fixtures only. They do not construct a window,
/// run a task, render a snapshot, or establish public List state integration.
@MainActor
final class RetainedLazyListActivityTests: XCTestCase {
    func testSupersedingRequestBeforeAdoptionRejectsConstructionAndPublication() async throws {
        for wasPrepared in [false, true] {
            let fixture = ActivityScopeFixture()
            defer { withExtendedLifetime(fixture) {} }
            let scope = fixture.scope
            XCTAssertTrue(scope.canConstructDescriptors)
            XCTAssertFalse(scope.canPublishDescriptors)
            XCTAssertFalse(scope.canCompleteAcceptedDescriptors)
            if wasPrepared {
                scope.preparationDidSucceed()
                XCTAssertTrue(scope.canPublishDescriptors)
            }

            scope.noteSupersedingRequest()

            XCTAssertFalse(scope.canConstructDescriptors)
            XCTAssertFalse(scope.canPublishDescriptors)
            XCTAssertFalse(scope.canCompleteAcceptedDescriptors)
            scope.preparationDidSucceed()
            XCTAssertFalse(scope.beginAdoption())
            scope.beginFinishing()
            XCTAssertFalse(scope.canCompleteAcceptedDescriptors)
            scope.finish()
            XCTAssertFalse(scope.canConstructDescriptors)
        }
    }

    func testSupersedingRequestAfterAdoptionPreservesAcceptedDescriptorCompletion() async throws {
        let fixture = ActivityScopeFixture()
        defer { withExtendedLifetime(fixture) {} }
        let scope = fixture.scope
        scope.preparationDidSucceed()
        XCTAssertTrue(scope.beginAdoption())
        XCTAssertFalse(scope.canCompleteAcceptedDescriptors)
        scope.recordAcceptedDescriptor()

        scope.noteSupersedingRequest()

        XCTAssertFalse(scope.canConstructDescriptors)
        XCTAssertTrue(scope.canPublishDescriptors)
        XCTAssertTrue(scope.canCompleteAcceptedDescriptors)
        scope.beginFinishing()
        XCTAssertFalse(scope.canPublishDescriptors)
        XCTAssertTrue(scope.canCompleteAcceptedDescriptors)
        scope.finish()
        XCTAssertFalse(scope.canConstructDescriptors)
        XCTAssertFalse(scope.canPublishDescriptors)
        XCTAssertFalse(scope.canCompleteAcceptedDescriptors)
    }

    func testOwnerCloseRevokesEveryDescriptorPhaseAndCannotReviveAnotherAttempt() async throws {
        for phase in ActivityDescriptorPhase.allCases {
            let fixture = ActivityScopeFixture()
            let scope = fixture.scope
            if phase != .constructing { scope.preparationDidSucceed() }
            if phase == .adopting || phase == .finishing || phase == .finished {
                XCTAssertTrue(scope.beginAdoption())
                scope.recordAcceptedDescriptor()
            }
            if phase == .finishing || phase == .finished { scope.beginFinishing() }
            if phase == .finished { scope.finish() }

            scope.revokeForOwnerClose()

            XCTAssertFalse(fixture.ownerLifetime.isCurrent)
            XCTAssertFalse(scope.canConstructDescriptors)
            XCTAssertFalse(scope.canPublishDescriptors)
            XCTAssertFalse(scope.canCompleteAcceptedDescriptors)
            scope.preparationDidSucceed()
            XCTAssertFalse(scope.beginAdoption())
            scope.beginFinishing()
            XCTAssertFalse(scope.canCompleteAcceptedDescriptors)
            scope.finish()
            scope.revokeForOwnerClose()

            let later = RetainedLazyListDescriptorBuildScope(
                origin: .componentHostRoot, hostLifetime: fixture.hostLifetime,
                ownerLifetime: fixture.ownerLifetime)
            XCTAssertFalse(later.canConstructDescriptors)
            later.preparationDidSucceed()
            XCTAssertFalse(later.beginAdoption())
            XCTAssertFalse(later.canCompleteAcceptedDescriptors)
        }
    }

    func testHostLifetimeExpirationRevokesDescriptorAndLogicalScopes() async throws {
        var lifetime: RetainedLazyListLogicalHostLifetime? = .init()
        weak var observedLifetime = lifetime
        let owner = RetainedLazyListDescriptorOwnerLifetime(
            target: RetainedLazyListTargetID(), attachment: RetainedLazyListAttachmentID())
        let scope = RetainedLazyListDescriptorBuildScope(
            origin: .componentHostRoot, hostLifetime: try XCTUnwrap(lifetime), ownerLifetime: owner)
        let logical = try XCTUnwrap(RetainedLazyListLogicalMembershipScope(in: scope, parentRow: nil))
        XCTAssertTrue(scope.canConstructDescriptors)
        XCTAssertTrue(logical.isLogicallyLive)

        lifetime = nil

        XCTAssertNil(observedLifetime)
        XCTAssertFalse(scope.canConstructDescriptors)
        XCTAssertFalse(scope.canPublishDescriptors)
        XCTAssertFalse(scope.canCompleteAcceptedDescriptors)
        XCTAssertFalse(logical.isLogicallyLive)
        XCTAssertNil(logical.proposeMembership(id: RetainedLazyListMembershipID()))
        XCTAssertNil(RetainedLazyListLogicalMembershipScope(in: scope, parentRow: nil))
    }

    func testLogicalPlanMustBeSealedAfterSparseMembershipResolution() async throws {
        let fixture = try ActivityLogicalFixture()
        let beforeResolution = fixture.logical.snapshot()
        let first = try XCTUnwrap(fixture.logical.proposeMembership(id: RetainedLazyListMembershipID()))
        XCTAssertNil(fixture.makePlan(expected: beforeResolution, introduced: [first]))
        let plan = try XCTUnwrap(fixture.makePlan(introduced: [first]))
        XCTAssertTrue(plan.isCurrent)

        let second = try XCTUnwrap(fixture.logical.proposeMembership(id: RetainedLazyListMembershipID()))

        XCTAssertFalse(plan.isCurrent, "A newly resolved sparse owner must stale the sealed roster")
        XCTAssertNil(fixture.makePlan(expected: plan.expected, introduced: [first, second]))
        XCTAssertNotNil(fixture.makePlan(introduced: [first, second]))
        XCTAssertEqual(first.phase, .proposed)
        XCTAssertEqual(second.phase, .proposed)
        XCTAssertFalse(first.isDeclared)
        XCTAssertFalse(second.isDeclared)
        XCTAssertNil(fixture.logical.snapshot().acceptedDescriptor)
    }

    func testRepeatedMembershipProposalDoesNotChangeTheSealedRoster() async throws {
        let fixture = try ActivityLogicalFixture()
        let membership = RetainedLazyListMembershipID()
        let receipt = try XCTUnwrap(fixture.logical.proposeMembership(id: membership))
        let plan = try XCTUnwrap(fixture.makePlan(introduced: [receipt]))

        let repeated = try XCTUnwrap(fixture.logical.proposeMembership(id: membership))

        XCTAssertTrue(repeated === receipt)
        XCTAssertTrue(plan.isCurrent)
        XCTAssertEqual(receipt.phase, .proposed)
        XCTAssertFalse(receipt.isDeclared)
        XCTAssertTrue(fixture.logical.snapshot().declared.isEmpty)
    }

    func testLogicalPlanRejectsDuplicateForeignAndMisclassifiedMemberships() async throws {
        let fixture = try ActivityLogicalFixture()
        let other = try ActivityLogicalFixture()
        let local = try XCTUnwrap(fixture.logical.proposeMembership(id: RetainedLazyListMembershipID()))
        let foreign = try XCTUnwrap(other.logical.proposeMembership(id: RetainedLazyListMembershipID()))

        XCTAssertNil(fixture.makePlan(introduced: [local, local]))
        XCTAssertNil(fixture.makePlan(introduced: [foreign]))
        XCTAssertNil(fixture.makePlan(retained: [local]))
        XCTAssertNil(fixture.makePlan(deleted: [local]))
        XCTAssertNil(fixture.makePlan(introduced: [local], retained: [local]))
        XCTAssertNotNil(fixture.makePlan(introduced: [local]))
        XCTAssertEqual(local.phase, .proposed)
        XCTAssertEqual(foreign.phase, .proposed)
        XCTAssertFalse(local.isDeclared)
        XCTAssertFalse(foreign.isDeclared)
    }

    func testSourceSupersessionRevokesASealedPlanWithoutDeclaringProvisionalMembership() async throws {
        let fixture = try ActivityLogicalFixture()
        let receipt = try XCTUnwrap(fixture.logical.proposeMembership(id: RetainedLazyListMembershipID()))
        let plan = try XCTUnwrap(fixture.makePlan(introduced: [receipt]))
        XCTAssertTrue(plan.isCurrent)

        XCTAssertTrue(fixture.source.replaceData([0, 1], id: \.self, rowContent: { $0 }))

        XCTAssertFalse(fixture.generation.isCurrent)
        XCTAssertFalse(plan.isCurrent)
        XCTAssertEqual(receipt.phase, .proposed)
        XCTAssertFalse(receipt.isDeclared)
        XCTAssertTrue(fixture.logical.snapshot().declared.isEmpty)
        XCTAssertNil(fixture.logical.snapshot().acceptedDescriptor)
    }

    func testLogicalScopeRevocationPreventsLaterProposalsAndPlanPublication() async throws {
        let fixture = try ActivityLogicalFixture()
        let membership = RetainedLazyListMembershipID()
        let receipt = try XCTUnwrap(fixture.logical.proposeMembership(id: membership))
        let plan = try XCTUnwrap(fixture.makePlan(introduced: [receipt]))
        XCTAssertTrue(plan.isCurrent)

        fixture.logical.revokeLogicalMembership()

        XCTAssertFalse(fixture.logical.isLogicallyLive)
        XCTAssertFalse(plan.isCurrent)
        XCTAssertFalse(receipt.isDeclared)
        XCTAssertNil(fixture.logical.proposeMembership(id: membership))
        XCTAssertNil(fixture.logical.proposeMembership(id: RetainedLazyListMembershipID()))
        XCTAssertNil(fixture.makePlan(introduced: [receipt]))
    }

    func testDescriptorJournalPublishesOnlyAfterTheMutationBoundary() async throws {
        for mutationStarted in [false, true] {
            let fixture = try ActivityDescriptorFixture()
            defer { withExtendedLifetime(fixture) {} }
            let row = try XCTUnwrap(fixture.logical.proposeMembership(id: RetainedLazyListMembershipID()))
            let operation = try fixture.prepareDescriptor(introduced: [row])
            if mutationStarted { XCTAssertTrue(operation.journal.markMutationStarted()) }

            operation.scope.noteSupersedingRequest()

            if mutationStarted {
                XCTAssertTrue(operation.journal.canContinueAdoption)
                _ = try XCTUnwrap(operation.journal.recordAcceptedLogicalDeclaration(operation.publication))
            } else {
                XCTAssertFalse(operation.journal.markMutationStarted())
            }
            let disposition = operation.journal.seal(completedCheckedAdoption: true)
            XCTAssertEqual(disposition.acceptedLogicalDeclarations.count, mutationStarted ? 1 : 0)
            XCTAssertEqual(disposition.stop, mutationStarted ? .completedCheckedAdoption : .noAcceptance)
            XCTAssertEqual(row.isDeclared, mutationStarted)
            XCTAssertEqual(operation.scope.canCompleteAcceptedDescriptors, mutationStarted)
            if mutationStarted {
                XCTAssertTrue(fixture.logical.snapshot().acceptedDescriptor === operation.binding.descriptor)
            } else {
                XCTAssertEqual(row.phase, .proposed)
                XCTAssertNil(fixture.logical.snapshot().acceptedDescriptor)
                XCTAssertNil(fixture.target.retainedLazyListActivityStorage?.acceptedLogicalDeclaration)
            }
        }
    }

    func testOwnerCloseRetainsAcceptedDescriptorFactsButRevokesCompletion() async throws {
        let fixture = try ActivityDescriptorFixture()
        defer { withExtendedLifetime(fixture) {} }
        let row = try XCTUnwrap(fixture.logical.proposeMembership(id: RetainedLazyListMembershipID()))
        let operation = try fixture.prepareDescriptor(introduced: [row])
        XCTAssertTrue(operation.journal.markMutationStarted())
        let accepted = try XCTUnwrap(operation.journal.recordAcceptedLogicalDeclaration(operation.publication))

        operation.scope.revokeForOwnerClose()

        let disposition = operation.journal.seal(completedCheckedAdoption: true)
        XCTAssertFalse(operation.scope.canCompleteAcceptedDescriptors)
        XCTAssertFalse(operation.journal.canContinueAdoption)
        XCTAssertEqual(disposition.stop, .stoppedAfterAcceptance)
        XCTAssertEqual(disposition.acceptedLogicalDeclarations.count, 1)
        XCTAssertTrue(disposition.acceptedLogicalDeclarations.first?.membershipPlan === accepted.membershipPlan)
        XCTAssertTrue(fixture.logical.snapshot().acceptedDescriptor === accepted.declaration)
        XCTAssertTrue(operation.journal.seal() === disposition)
    }

    func testDeclaredMembershipPlanRequiresACompleteDisjointRetainedDeletedPartition() async throws {
        let fixture = try ActivityDescriptorFixture()
        let first = try XCTUnwrap(fixture.logical.proposeMembership(id: RetainedLazyListMembershipID()))
        let second = try XCTUnwrap(fixture.logical.proposeMembership(id: RetainedLazyListMembershipID()))
        let accepted = try fixture.acceptDescriptor(introduced: [first, second])
        let snapshot = fixture.logical.snapshot()
        XCTAssertEqual(snapshot.declared.count, 2)

        XCTAssertNil(fixture.makePlan(expected: snapshot, retained: [first]))
        XCTAssertNil(fixture.makePlan(expected: snapshot, deleted: [second]))
        XCTAssertNil(fixture.makePlan(expected: snapshot, retained: [first], deleted: [first, second]))
        XCTAssertNil(fixture.makePlan(expected: snapshot, retained: [first, first], deleted: [second]))
        XCTAssertNil(fixture.makePlan(expected: snapshot, retained: [first], deleted: [second, second]))
        XCTAssertNotNil(fixture.makePlan(expected: snapshot, retained: [first], deleted: [second]))
        XCTAssertNotNil(fixture.makePlan(expected: snapshot, retained: [second], deleted: [first]))
        XCTAssertTrue(first.isDeclared)
        XCTAssertTrue(second.isDeclared)
        XCTAssertTrue(fixture.logical.snapshot().acceptedDescriptor === accepted.binding.descriptor)
    }

    func testDescriptorAcceptanceRevokesDeletedMembershipBeforeDispositionCleanup() async throws {
        let fixture = try ActivityDescriptorFixture()
        let deleted = try XCTUnwrap(fixture.logical.proposeMembership(id: RetainedLazyListMembershipID()))
        let retained = try XCTUnwrap(fixture.logical.proposeMembership(id: RetainedLazyListMembershipID()))
        _ = try fixture.acceptDescriptor(introduced: [deleted, retained])
        let replacement = try fixture.prepareDescriptor(retained: [retained], deleted: [deleted])
        XCTAssertTrue(deleted.isDeclared)
        XCTAssertTrue(retained.isDeclared)
        XCTAssertTrue(replacement.journal.markMutationStarted())

        _ = try XCTUnwrap(replacement.journal.recordAcceptedLogicalDeclaration(replacement.publication))

        // The disposition has not been sealed or delivered to facade cleanup.
        XCTAssertEqual(deleted.phase, .revoked)
        XCTAssertFalse(deleted.isDeclared)
        XCTAssertTrue(retained.isDeclared)
        XCTAssertTrue(fixture.logical.snapshot().acceptedDescriptor === replacement.binding.descriptor)
        XCTAssertNil(fixture.logical.proposeMembership(id: deleted.id))
        replacement.journal.revokeBeforeAbandon()
        XCTAssertFalse(deleted.isDeclared, "Abandonment cannot undo accepted logical deletion")
        let disposition = replacement.journal.seal()
        XCTAssertEqual(disposition.acceptedLogicalDeclarations.count, 1)
        XCTAssertEqual(disposition.stop, .stoppedAfterAcceptance)
        XCTAssertTrue(disposition.acceptedCleanup.isEmpty)
    }

    func testLogicalDeletionDisablesAcceptedContributionBeforePhysicalCleanup() async throws {
        let fixture = try ActivityGroupFixture()
        defer { withExtendedLifetime(fixture) {} }
        let source = ViewNode()
        let group = try XCTUnwrap(fixture.attribution.registerGroup(kind: .observation))
        _ = try XCTUnwrap(fixture.attribution.recordSourceOutput(source, group: group))
        let proposal = try XCTUnwrap(fixture.attribution.closeGroup(group))
        try fixture.prepare()
        XCTAssertTrue(fixture.journal.markMutationStarted())
        _ = fixture.journal.recordAcceptedAttachment(from: source, to: fixture.owner.target)
        _ = fixture.journal.recordCompletedNode(from: source, to: fixture.owner.target)
        let accepted = try XCTUnwrap(fixture.journal.recordAcceptedGroup(proposal))
        let actual = try XCTUnwrap(accepted.acceptedFacets.first?.actual)
        XCTAssertTrue(accepted.receipt.isActive)
        let replacement = try fixture.owner.prepareDescriptor(deleted: [fixture.row])
        XCTAssertTrue(replacement.journal.markMutationStarted())

        _ = try XCTUnwrap(replacement.journal.recordAcceptedLogicalDeclaration(replacement.publication))

        XCTAssertFalse(fixture.row.isDeclared)
        XCTAssertFalse(accepted.receipt.isActive)
        XCTAssertTrue(actual.isAttached, "Logical revocation must not wait for physical detachment")
        XCTAssertEqual(accepted.receipt.physical.state, .active)
        XCTAssertTrue(
            fixture.owner.target.retainedLazyListActivityStorage?.committedContributions[ObjectIdentifier(group)]
                === accepted.receipt)
    }

    func testLogicalScopeRevocationDisablesAcceptedContributionBeforeDetachment() async throws {
        let fixture = try ActivityGroupFixture()
        defer { withExtendedLifetime(fixture) {} }
        let source = ViewNode()
        let group = try XCTUnwrap(fixture.attribution.registerGroup(kind: .observation))
        _ = try XCTUnwrap(fixture.attribution.recordSourceOutput(source, group: group))
        let proposal = try XCTUnwrap(fixture.attribution.closeGroup(group))
        try fixture.prepare()
        XCTAssertTrue(fixture.journal.markMutationStarted())
        _ = fixture.journal.recordAcceptedAttachment(from: source, to: fixture.owner.target)
        _ = fixture.journal.recordCompletedNode(from: source, to: fixture.owner.target)
        let accepted = try XCTUnwrap(fixture.journal.recordAcceptedGroup(proposal))
        let actual = try XCTUnwrap(accepted.acceptedFacets.first?.actual)
        XCTAssertTrue(accepted.receipt.isActive)

        fixture.owner.logical.revokeLogicalMembership()

        XCTAssertFalse(fixture.owner.logical.isLogicallyLive)
        XCTAssertFalse(fixture.row.isDeclared)
        XCTAssertFalse(accepted.receipt.isActive)
        XCTAssertTrue(fixture.owner.generation.isCurrent)
        XCTAssertTrue(actual.isAttached)
        XCTAssertEqual(accepted.receipt.physical.state, .active)
        XCTAssertTrue(
            fixture.owner.target.retainedLazyListActivityStorage?.committedContributions[ObjectIdentifier(group)]
                === accepted.receipt)
    }

    func testDeletedMembershipIDCannotReviveAfterItsReceiptAndSparseRosterEntryAreReleased() async throws {
        let fixture = try ActivityDescriptorFixture()
        defer { withExtendedLifetime(fixture) {} }
        let membership = RetainedLazyListMembershipID()
        var receipt: RetainedLazyListLogicalMembershipReceipt? =
            try XCTUnwrap(fixture.logical.proposeMembership(id: membership))
        weak var releasedReceipt = receipt
        _ = try fixture.acceptDescriptor(introduced: [try XCTUnwrap(receipt)])
        var deletion: ActivityDescriptorOperation? =
            try fixture.prepareDescriptor(deleted: [try XCTUnwrap(receipt)])
        do {
            let operation = try XCTUnwrap(deletion)
            XCTAssertTrue(operation.journal.markMutationStarted())
            _ = try XCTUnwrap(operation.journal.recordAcceptedLogicalDeclaration(operation.publication))
            _ = operation.journal.seal()
            operation.scope.finish()
        }
        XCTAssertEqual(receipt?.phase, .revoked)
        XCTAssertTrue(fixture.logical.snapshot().declared.isEmpty)
        XCTAssertNil(fixture.logical.proposeMembership(id: membership))

        receipt = nil
        deletion = nil
        XCTAssertNotNil(releasedReceipt, "The installed deletion fact still owns its cleanup membership")
        // A later empty descriptor releases that fact without closing the scope.
        _ = try fixture.acceptDescriptor()

        XCTAssertNil(releasedReceipt)
        XCTAssertTrue(fixture.logical.isLogicallyLive)
        XCTAssertTrue(fixture.logical.snapshot().declared.isEmpty)
        XCTAssertNil(fixture.logical.proposeMembership(id: membership))
        let fresh = try XCTUnwrap(fixture.logical.proposeMembership(id: RetainedLazyListMembershipID()))
        XCTAssertEqual(fresh.phase, .proposed)
        XCTAssertFalse(fresh.id === membership)
    }

    func testCommittedSparseVisitStalesTheRosterWithoutDescriptorAcceptanceOrPhysicalActivity() async throws {
        let fixture = try ActivityDescriptorFixture()
        let accepted = try fixture.acceptDescriptor()
        let pendingPlan = try XCTUnwrap(fixture.makePlan())
        XCTAssertTrue(pendingPlan.isCurrent)
        let selected = try ActivitySelectedRowFixture(owner: fixture, descriptor: accepted.binding)
        defer { selected.finish() }
        let token = try XCTUnwrap(fixture.source.metadata?.rows.first?.token)
        let request = try XCTUnwrap(fixture.source.request(for: token))
        let preparation = try XCTUnwrap(
            selected.journal.prepareSelectedRow(request: request, descriptor: accepted.binding))
        let response = RetainedLazyListSelectedRowResolution(
            preparation: preparation, membership: RetainedLazyListMembershipID(),
            source: .committed(descriptor: accepted.binding.descriptor))

        let attribution = try XCTUnwrap(
            selected.journal.consumeSelectedRowResolution(response, for: preparation))

        XCTAssertTrue(attribution.logicalMembership.isDeclared)
        XCTAssertEqual(attribution.physical.state, .provisional)
        XCTAssertEqual(attribution.constructionState, .admittedForConstruction)
        XCTAssertFalse(pendingPlan.isCurrent, "First visit changes the sparse roster under the same descriptor")
        XCTAssertTrue(fixture.logical.snapshot().acceptedDescriptor === accepted.binding.descriptor)
        XCTAssertEqual(fixture.logical.snapshot().declared.count, 1)
        XCTAssertFalse(selected.journal.hasAcceptedContributions)
        XCTAssertNil(selected.journal.consumeSelectedRowResolution(response, for: preparation))
        let disposition = selected.journal.seal()
        XCTAssertEqual(disposition.stop, .noAcceptance)
        XCTAssertTrue(disposition.acceptedLogicalDeclarations.isEmpty)
        XCTAssertTrue(disposition.acceptedFacets.isEmpty)
        XCTAssertTrue(disposition.acceptedGroups.isEmpty)
        XCTAssertTrue(disposition.acceptedEmptyGroups.isEmpty)
        XCTAssertEqual(attribution.physical.state, .provisional)
    }

    func testPartialGroupCannotMintAContributionOrCommitANodeAssociation() async throws {
        let fixture = try ActivityGroupFixture()
        defer { withExtendedLifetime(fixture) {} }
        let source = ViewNode()
        let group = try XCTUnwrap(fixture.attribution.registerGroup(kind: .observation))
        _ = try XCTUnwrap(fixture.attribution.recordSourceOutput(source, group: group))
        let proposal = try XCTUnwrap(fixture.attribution.closeGroup(group))
        XCTAssertEqual(proposal.requiredFacets.count, 2)
        try fixture.prepare()
        XCTAssertTrue(fixture.journal.markMutationStarted())

        _ = fixture.journal.recordAcceptedAttachment(from: source, to: fixture.owner.target)

        XCTAssertNil(fixture.journal.recordAcceptedGroup(proposal))
        XCTAssertNil(
            fixture.owner.target.retainedLazyListActivityStorage?.committedContributions[ObjectIdentifier(group)])
        let disposition = fixture.journal.seal()
        XCTAssertEqual(disposition.stop, .stoppedAfterAcceptance)
        XCTAssertTrue(disposition.acceptedGroups.isEmpty)
        XCTAssertTrue(disposition.acceptedEmptyGroups.isEmpty)
        XCTAssertNil(disposition.contribution(for: group))
        XCTAssertEqual(disposition.partialGroups.count, 1)
        XCTAssertEqual(disposition.partialGroups.first?.acceptedFacets.count, 1)
        XCTAssertEqual(disposition.partialGroups.first?.unacceptedFacets.count, 1)
        XCTAssertTrue(disposition.acceptedCleanup.isEmpty)
    }

    func testSameTargetGroupsShareAttachmentContinuityWithoutSharingAssociationRevocation() async throws {
        let fixture = try ActivityGroupFixture()
        defer { withExtendedLifetime(fixture) {} }
        let firstSource = ViewNode()
        let firstID = try XCTUnwrap(fixture.attribution.registerGroup(kind: .ownedState))
        _ = try XCTUnwrap(fixture.attribution.recordSourceOutput(firstSource, group: firstID))
        let firstProposal = try XCTUnwrap(fixture.attribution.closeGroup(firstID))
        let secondSource = ViewNode()
        let secondID = try XCTUnwrap(fixture.attribution.registerGroup(kind: .observation))
        _ = try XCTUnwrap(fixture.attribution.recordSourceOutput(secondSource, group: secondID))
        let secondProposal = try XCTUnwrap(fixture.attribution.closeGroup(secondID))
        try fixture.prepare()
        XCTAssertTrue(fixture.journal.markMutationStarted())
        for source in [firstSource, secondSource] {
            _ = fixture.journal.recordAcceptedAttachment(from: source, to: fixture.owner.target)
            _ = fixture.journal.recordCompletedNode(from: source, to: fixture.owner.target)
        }
        let first = try XCTUnwrap(fixture.journal.recordAcceptedGroup(firstProposal))
        let second = try XCTUnwrap(fixture.journal.recordAcceptedGroup(secondProposal))
        let firstActual = try XCTUnwrap(first.acceptedFacets.first?.actual)
        let secondActual = try XCTUnwrap(second.acceptedFacets.first?.actual)
        XCTAssertTrue(firstActual.target === secondActual.target)
        XCTAssertTrue(firstActual.attachment === secondActual.attachment)
        XCTAssertTrue(first.receipt.physical === second.receipt.physical)
        XCTAssertTrue(first.receipt.isActive)
        XCTAssertTrue(second.receipt.isActive)

        first.receipt.revoke()

        XCTAssertFalse(first.receipt.isActive)
        XCTAssertTrue(second.receipt.isActive)
        XCTAssertEqual(second.receipt.physical.state, .active)
        XCTAssertTrue(secondActual.isAttached)
        let storage = fixture.owner.target.lazyListActivityStorage()
        storage.revokeAttachment()
        let replacement = storage.captureActualAttachment(of: fixture.owner.target, in: fixture.owner.runtime)
        XCTAssertTrue(replacement.isAttached)
        XCTAssertFalse(firstActual.isAttached)
        XCTAssertFalse(secondActual.isAttached)
        XCTAssertFalse(first.receipt.activate(on: [replacement]))
        XCTAssertFalse(second.receipt.activate(on: [replacement]))
        XCTAssertEqual(second.receipt.physical.state, .revoked)
    }

    func testOwnerCloseRevokesContainingRowAndDeferredScopesWithoutRevival() async throws {
        let fixture = try ActivityGroupFixture()
        defer { withExtendedLifetime(fixture) {} }
        let containing = try XCTUnwrap(fixture.scope.withContainingRow(fixture.attribution))
        XCTAssertNotNil(RetainedLazyListLogicalMembershipScope(in: containing, parentRow: fixture.row))
        XCTAssertNil(RetainedLazyListLogicalMembershipScope(in: fixture.scope, parentRow: fixture.row))
        let source = ViewNode()
        let group = try XCTUnwrap(fixture.attribution.registerGroup(kind: .deferredSubtree))
        _ = try XCTUnwrap(fixture.attribution.recordSourceOutput(source, group: group))
        let proposal = try XCTUnwrap(fixture.attribution.closeGroup(group))
        try fixture.prepare()
        XCTAssertTrue(fixture.journal.markMutationStarted())
        _ = fixture.journal.recordAcceptedAttachment(from: source, to: fixture.owner.target)
        _ = fixture.journal.recordCompletedNode(from: source, to: fixture.owner.target)
        let accepted = try XCTUnwrap(fixture.journal.recordAcceptedGroup(proposal))
        let actual = try XCTUnwrap(accepted.acceptedFacets.first?.actual)
        let managed = RetainedLazyListDescriptorBuildScope(
            origin: .managedSubtree, hostLifetime: fixture.owner.runtime.lazyListLogicalHostLifetime,
            ownerLifetime: fixture.owner.target.lazyListActivityStorage().descriptorOwnerLifetime)
        let deferred = try XCTUnwrap(
            managed.withAdmittedDeferredSubtree(originalActivity: accepted.receipt, originalAttachment: actual))
        XCTAssertTrue(deferred.canConstructDescriptors)
        XCTAssertNotNil(RetainedLazyListLogicalMembershipScope(in: deferred, parentRow: fixture.row))

        fixture.scope.revokeForOwnerClose()

        for scope in [fixture.scope, containing, managed, deferred] {
            XCTAssertFalse(scope.canConstructDescriptors)
            XCTAssertFalse(scope.canPublishDescriptors)
            XCTAssertFalse(scope.canCompleteAcceptedDescriptors)
        }
        XCTAssertNil(fixture.scope.withContainingRow(fixture.attribution))
        XCTAssertNil(
            managed.withAdmittedDeferredSubtree(originalActivity: accepted.receipt, originalAttachment: actual))
        XCTAssertNil(RetainedLazyListLogicalMembershipScope(in: deferred, parentRow: fixture.row))
    }

    func testQualifiedOrdinaryDeferredGroupKeepsTheOriginalOwnerLifetime() async throws {
        let fixture = try ActivityDescriptorFixture()
        defer { withExtendedLifetime(fixture) {} }

        @MainActor
        func acceptGroup(
            in scope: RetainedLazyListDescriptorBuildScope, on target: ViewNode
        ) throws -> RetainedDescriptorAcceptedGroup {
            let journal = RetainedLazyListAdoptionJournal(
                descriptorScope: scope, transaction: RetainedBuildTransaction())
            let attribution = try XCTUnwrap(scope.registerOrdinaryComponent())
            let group = try XCTUnwrap(attribution.registerGroup(kind: .deferredSubtree))
            let source = ViewNode()
            XCTAssertTrue(attribution.recordSourceOutput(source, group: group))
            _ = try XCTUnwrap(attribution.closeGroup(group))
            XCTAssertTrue(journal.beginOrdinaryAdoption())
            XCTAssertTrue(journal.markMutationStarted())
            _ = journal.recordAcceptedAttachment(from: source, to: target)
            _ = journal.recordCompletedNode(from: source, to: target)
            let disposition = journal.seal(completedCheckedAdoption: true)
            let accepted = try XCTUnwrap(disposition.acceptedOrdinaryGroups.first { $0.proposal.group === group })
            scope.finish()
            return accepted
        }

        let originalOwner = fixture.target.lazyListActivityStorage().descriptorOwnerLifetime
        let originalScope = RetainedLazyListDescriptorBuildScope(
            origin: .componentHostRoot, hostLifetime: fixture.runtime.lazyListLogicalHostLifetime,
            ownerLifetime: originalOwner)
        let original = try acceptGroup(in: originalScope, on: fixture.target)
        XCTAssertTrue(original.receipt.isActive)
        let originalAttachment = try XCTUnwrap(original.acceptedFacets.first?.actual)
        let deferredTarget = ViewNode()
        fixture.target.addChild(deferredTarget)
        let bootstrapOwner = deferredTarget.lazyListActivityStorage().descriptorOwnerLifetime
        XCTAssertFalse(bootstrapOwner === originalOwner)
        let bootstrap = RetainedLazyListDescriptorBuildScope(
            origin: .managedSubtree, hostLifetime: fixture.runtime.lazyListLogicalHostLifetime,
            ownerLifetime: bootstrapOwner)
        let qualified = try XCTUnwrap(
            bootstrap.withAdmittedOrdinaryDeferredSubtree(
                originalActivity: original.receipt, originalAttachment: originalAttachment))

        let accepted = try acceptGroup(in: qualified, on: deferredTarget)

        XCTAssertTrue(accepted.receipt.isActive)
        XCTAssertTrue(accepted.receipt.hasSameOwnerLifetime(as: original.receipt))
    }

    func testPreparationSnapshotRejectsLateContributionRegistration() async throws {
        let fixture = try ActivityGroupFixture()
        defer { withExtendedLifetime(fixture) {} }
        let group = try XCTUnwrap(fixture.attribution.registerGroup(kind: .structure))
        let preparation = try XCTUnwrap(fixture.journal.preparation())

        XCTAssertNil(fixture.attribution.registerGroup(kind: .observation))

        XCTAssertEqual(preparation.groups.count, 1)
        XCTAssertTrue(preparation.groups.first?.group === group)
        XCTAssertEqual(preparation.groups.first?.construction, .closedEmpty)
    }
}

private enum ActivityDescriptorPhase: CaseIterable, Equatable {
    case constructing, prepared, adopting, finishing, finished
}

@MainActor
private struct ActivityScopeFixture {
    let hostLifetime: RetainedLazyListLogicalHostLifetime
    let ownerLifetime: RetainedLazyListDescriptorOwnerLifetime
    let scope: RetainedLazyListDescriptorBuildScope

    init() {
        let hostLifetime = RetainedLazyListLogicalHostLifetime()
        let ownerLifetime = RetainedLazyListDescriptorOwnerLifetime(
            target: RetainedLazyListTargetID(), attachment: RetainedLazyListAttachmentID())
        self.hostLifetime = hostLifetime
        self.ownerLifetime = ownerLifetime
        scope = RetainedLazyListDescriptorBuildScope(
            origin: .componentHostRoot, hostLifetime: hostLifetime, ownerLifetime: ownerLifetime)
    }
}

@MainActor
private struct ActivityLogicalFixture {
    let build: ActivityScopeFixture
    let source: RetainedLazyListDataSource<Int, Int>
    let logical: RetainedLazyListLogicalMembershipScope
    let generation: RetainedLazyListGeneration

    init() throws {
        let build = ActivityScopeFixture()
        let source = RetainedLazyListDataSource<Int, Int>()
        let logical = try XCTUnwrap(RetainedLazyListLogicalMembershipScope(in: build.scope, parentRow: nil))
        XCTAssertTrue(source.replaceData([0, 1], id: \.self, rowContent: { $0 }))
        self.build = build
        self.source = source
        self.logical = logical
        generation = try XCTUnwrap(source.metadata).generation
    }

    func makePlan(
        expected: RetainedLazyListLogicalMembershipSnapshot? = nil,
        introduced: [RetainedLazyListLogicalMembershipReceipt] = [],
        retained: [RetainedLazyListLogicalMembershipReceipt] = [],
        deleted: [RetainedLazyListLogicalMembershipReceipt] = []
    ) -> RetainedLazyListLogicalMembershipPlan? {
        RetainedLazyListLogicalMembershipPlan(
            descriptor: RetainedLazyListLogicalDeclarationID(),
            facadeProposal: RetainedLazyListLogicalProposalID(),
            expected: expected ?? logical.snapshot(), sourceGeneration: generation,
            introduced: introduced, retained: retained, deleted: deleted)
    }
}

private enum ActivityFixtureError: Error {
    case source, preparation, publication, admission
}

/// Tests the native journal publication seam. The calls below model the
/// descriptor writer's notifications; they do not replace a ComponentHost
/// property-copy integration test or claim that a checked tree was adopted.
@MainActor
private final class ActivityDescriptorFixture {
    let target: ViewNode
    let runtime: RetainedViewRuntime
    let source: RetainedLazyListDataSource<Int, [ViewNode]>
    let generation: RetainedLazyListGeneration
    let logical: RetainedLazyListLogicalMembershipScope

    init() throws {
        let target = ViewNode()
        let runtime = RetainedViewRuntime(root: target)
        let source = RetainedLazyListDataSource<Int, [ViewNode]>()
        let scope = RetainedLazyListDescriptorBuildScope(
            origin: .componentHostRoot, hostLifetime: runtime.lazyListLogicalHostLifetime,
            ownerLifetime: target.lazyListActivityStorage().descriptorOwnerLifetime)
        let logical = try XCTUnwrap(RetainedLazyListLogicalMembershipScope(in: scope, parentRow: nil))
        guard source.replaceData([0, 1], id: \.self, rowContent: { _ in [] }) else {
            throw ActivityFixtureError.source
        }
        self.target = target
        self.runtime = runtime
        self.source = source
        self.logical = logical
        generation = try XCTUnwrap(source.metadata).generation
    }

    func makePlan(
        expected: RetainedLazyListLogicalMembershipSnapshot? = nil,
        descriptor: RetainedLazyListLogicalDeclarationID = .init(),
        proposal: RetainedLazyListLogicalProposalID = .init(),
        introduced: [RetainedLazyListLogicalMembershipReceipt] = [],
        retained: [RetainedLazyListLogicalMembershipReceipt] = [],
        deleted: [RetainedLazyListLogicalMembershipReceipt] = []
    ) -> RetainedLazyListLogicalMembershipPlan? {
        RetainedLazyListLogicalMembershipPlan(
            descriptor: descriptor, facadeProposal: proposal, expected: expected ?? logical.snapshot(),
            sourceGeneration: generation, introduced: introduced, retained: retained, deleted: deleted)
    }

    func prepareDescriptor(
        introduced: [RetainedLazyListLogicalMembershipReceipt] = [],
        retained: [RetainedLazyListLogicalMembershipReceipt] = [],
        deleted: [RetainedLazyListLogicalMembershipReceipt] = []
    ) throws -> ActivityDescriptorOperation {
        let scope = RetainedLazyListDescriptorBuildScope(
            origin: .componentHostRoot, hostLifetime: runtime.lazyListLogicalHostLifetime,
            ownerLifetime: target.lazyListActivityStorage().descriptorOwnerLifetime)
        let journal = RetainedLazyListAdoptionJournal(descriptorScope: scope, transaction: RetainedBuildTransaction())
        let sourceNode = ViewNode()
        let binding = RetainedLazyListManagedLogicalDescriptorBinding(
            descriptor: RetainedLazyListLogicalDeclarationID(), facadeProposal: RetainedLazyListLogicalProposalID(),
            scope: logical, sourceGeneration: generation)
        let adapter = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter(
                provider: source, estimatedExtent: 20, prefetchExtent: 0,
                maximumMountedRecords: 2, maximumMountedLeaves: 2, maximumProtectedRecords: 1))
        guard adapter.installManagedLogicalDescriptor(binding) else { throw ActivityFixtureError.publication }
        sourceNode.retainedLazyListAdapter = adapter
        _ = try XCTUnwrap(journal.registerSourceDescriptor(binding, on: sourceNode))
        let preparation = try XCTUnwrap(journal.preparation())
        let snapshot = try XCTUnwrap(preparation.logicalSnapshots.first { $0.scope === logical })
        let plan = try XCTUnwrap(
            makePlan(
                expected: snapshot, descriptor: binding.descriptor, proposal: binding.facadeProposal,
                introduced: introduced, retained: retained, deleted: deleted))
        let activity = RetainedLazyListPreparedActivity(preparation: preparation, logicalMembershipPlans: [plan])
        guard journal.beginAdoption(preparation, preparedActivity: activity) else {
            throw ActivityFixtureError.preparation
        }
        guard case .ready(let publication) = journal.prepareDescriptorCopy(from: sourceNode, to: target) else {
            throw ActivityFixtureError.publication
        }
        return ActivityDescriptorOperation(
            scope: scope, journal: journal, sourceNode: sourceNode, binding: binding,
            plan: plan, publication: publication)
    }

    func acceptDescriptor(
        introduced: [RetainedLazyListLogicalMembershipReceipt] = []
    ) throws -> ActivityDescriptorOperation {
        let operation = try prepareDescriptor(introduced: introduced)
        guard operation.journal.markMutationStarted() else { throw ActivityFixtureError.admission }
        _ = try XCTUnwrap(operation.journal.recordAcceptedLogicalDeclaration(operation.publication))
        _ = operation.journal.seal(completedCheckedAdoption: true)
        operation.scope.finish()
        return operation
    }
}

@MainActor
private struct ActivityDescriptorOperation {
    let scope: RetainedLazyListDescriptorBuildScope
    let journal: RetainedLazyListAdoptionJournal
    let sourceNode: ViewNode
    let binding: RetainedLazyListManagedLogicalDescriptorBinding
    let plan: RetainedLazyListLogicalMembershipPlan
    let publication: RetainedLazyListLogicalDescriptorPublication
}

@MainActor
private final class ActivitySelectedRowFixture {
    let owner: ActivityDescriptorFixture
    let adapter: RetainedLazyListRuntimeAdapter
    let coordinator: RetainedBuildCoordinator
    let lease: ActivityScalarLease
    let admission: RetainedLazyListAdoptionAdmission
    let journal: RetainedLazyListAdoptionJournal

    init(owner: ActivityDescriptorFixture, descriptor: RetainedLazyListManagedLogicalDescriptorBinding) throws {
        let adapter = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter(
                provider: owner.source, estimatedExtent: 20, prefetchExtent: 0,
                maximumMountedRecords: 2, maximumMountedLeaves: 2, maximumProtectedRecords: 1))
        guard adapter.installManagedLogicalDescriptor(descriptor) else { throw ActivityFixtureError.admission }
        let coordinator = RetainedBuildCoordinator()
        let lease = ActivityScalarLease()
        owner.target.retainedSubtreeBuildLease = lease
        owner.target.retainedLazyListAdapter = adapter
        guard adapter.claimAttachment(to: owner.target) else { throw ActivityFixtureError.admission }
        let sequence = try XCTUnwrap(coordinator.beginBuild())
        let admission = RetainedLazyListAdoptionAdmission(
            adapter: adapter, container: owner.target, runtime: owner.runtime,
            coordinator: coordinator, sequence: sequence)
        guard admission.isBuildCurrent else { throw ActivityFixtureError.admission }
        self.owner = owner
        self.adapter = adapter
        self.coordinator = coordinator
        self.lease = lease
        self.admission = admission
        journal = RetainedLazyListAdoptionJournal(admission: admission, transaction: RetainedBuildTransaction())
    }

    func finish() {
        admission.revoke()
        coordinator.finishBuild()
    }
}

@MainActor
private final class ActivityScalarLease: RetainedSubtreeBuildLease {
    var canBuild: Bool { true }
    func beginBuild() -> (any RetainedBuildEpoch)? { nil }
}

@MainActor
private final class ActivityGroupFixture {
    let owner: ActivityDescriptorFixture
    let row: RetainedLazyListLogicalMembershipReceipt
    let scope: RetainedLazyListDescriptorBuildScope
    let journal: RetainedLazyListAdoptionJournal
    let attribution: RetainedLazyListBuildAttribution

    init() throws {
        let owner = try ActivityDescriptorFixture()
        let row = try XCTUnwrap(owner.logical.proposeMembership(id: RetainedLazyListMembershipID()))
        _ = try owner.acceptDescriptor(introduced: [row])
        let scope = RetainedLazyListDescriptorBuildScope(
            origin: .componentHostRoot, hostLifetime: owner.runtime.lazyListLogicalHostLifetime,
            ownerLifetime: owner.target.lazyListActivityStorage().descriptorOwnerLifetime)
        let journal = RetainedLazyListAdoptionJournal(descriptorScope: scope, transaction: RetainedBuildTransaction())
        let token = try XCTUnwrap(owner.source.metadata?.rows.first?.token)
        let request = try XCTUnwrap(owner.source.request(for: token))
        let attribution = RetainedLazyListBuildAttribution(
            journal: journal, rowRequest: request, logicalMembership: row,
            physical: RetainedLazyListPhysicalActivityReceipt(membership: row.id),
            component: RetainedLazyListComponentID(), resolutionID: RetainedLazyListRowResolutionID(),
            origin: .selectedRow)
        self.owner = owner
        self.row = row
        self.scope = scope
        self.journal = journal
        self.attribution = attribution
    }

    func prepare() throws {
        let preparation = try XCTUnwrap(journal.preparation())
        let activity = RetainedLazyListPreparedActivity(preparation: preparation, logicalMembershipPlans: [])
        guard journal.beginAdoption(preparation, preparedActivity: activity) else {
            throw ActivityFixtureError.preparation
        }
    }
}
