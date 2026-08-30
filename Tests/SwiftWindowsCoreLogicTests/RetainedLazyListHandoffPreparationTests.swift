import XCTest

@testable import SwiftWindowsUI

/// Native journal phase tests. Attachment notifications below model the
/// reconciliation seam; mounted List tests exercise the complete adoption.
@MainActor
final class RetainedLazyListHandoffPreparationTests: XCTestCase {
    func testOpenImplicitGroupsCanReserveAndCollectOutputsBeforePreparation() async throws {
        for kind in [RetainedLazyListContributionKind.objectDependency, .deferredSubtree] {
            let fixture = try HandoffPreparationFixture()
            defer { withExtendedLifetime(fixture) {} }
            let group = try XCTUnwrap(fixture.attribution.registerGroup(kind: kind))

            XCTAssertTrue(fixture.reserve())
            XCTAssertFalse(fixture.journal.markMutationStarted())
            XCTAssertFalse(fixture.journal.canContinueAdoption)
            XCTAssertFalse(fixture.journal.hasAcceptedContributions)
            XCTAssertEqual(fixture.physical.actualAttachments.count, 1)
            XCTAssertTrue(fixture.actual.isAttached)

            // The implicit group stays open so a later descendant output is
            // inherited. Only preparation, not handoff reservation, closes it.
            let child = try XCTUnwrap(fixture.attribution.registerChildComponent())
            let structure = try XCTUnwrap(child.registerGroup(kind: .structure))
            let source = ViewNode()
            XCTAssertNotNil(child.recordSourceOutput(source, group: structure))
            XCTAssertNotNil(child.closeGroup(structure))
            let preparation = try XCTUnwrap(fixture.journal.preparation())
            let proposal = try XCTUnwrap(preparation.groups.first { $0.group === group })
            XCTAssertEqual(proposal.construction, .closedWithFacets)
            XCTAssertEqual(proposal.requiredFacets.count, 2)
            XCTAssertNil(fixture.attribution.recordSourceOutput(ViewNode(), group: group))
            XCTAssertFalse(fixture.journal.markMutationStarted())
            XCTAssertFalse(fixture.journal.hasAcceptedContributions)
            XCTAssertNil(source.parent)

            XCTAssertTrue(fixture.beginAdoption(preparation))
            XCTAssertFalse(fixture.journal.hasAcceptedContributions)
            XCTAssertTrue(fixture.journal.markMutationStarted())
            XCTAssertFalse(fixture.journal.hasAcceptedContributions)
            _ = fixture.journal.seal()
        }
    }

    func testReservationCannotKeepPhysicalActivityAliveBeforeAdoption() async throws {
        let fixture = try HandoffPreparationFixture()
        defer { withExtendedLifetime(fixture) {} }
        XCTAssertNotNil(fixture.attribution.registerGroup(kind: .objectDependency))
        XCTAssertTrue(fixture.reserve())

        fixture.physical.removeAttachment(target: fixture.actual.target, attachment: fixture.actual.attachment)

        XCTAssertEqual(fixture.physical.state, .revoked)
        XCTAssertFalse(fixture.journal.markMutationStarted())
        XCTAssertFalse(fixture.journal.hasAcceptedContributions)
        XCTAssertEqual(fixture.journal.seal().stop, .noAcceptance)
    }

    func testPreparedHandoffKeepsPhysicalActivityAcrossTheAcceptedAttachmentGap() async throws {
        let fixture = try HandoffPreparationFixture()
        defer { withExtendedLifetime(fixture) {} }
        let group = try XCTUnwrap(fixture.attribution.registerGroup(kind: .deferredSubtree))
        let source = ViewNode()
        XCTAssertNotNil(fixture.attribution.recordSourceOutput(source, group: group))
        XCTAssertTrue(fixture.reserve())
        let preparation = try XCTUnwrap(fixture.journal.preparation())
        let proposal = try XCTUnwrap(preparation.groups.first { $0.group === group })
        XCTAssertEqual(proposal.construction, .closedWithFacets)
        XCTAssertTrue(fixture.beginAdoption(preparation))
        XCTAssertTrue(fixture.journal.markMutationStarted())

        fixture.physical.removeAttachment(target: fixture.actual.target, attachment: fixture.actual.attachment)

        XCTAssertTrue(fixture.physical.actualAttachments.isEmpty)
        XCTAssertEqual(fixture.physical.state, .active)
        XCTAssertFalse(fixture.journal.hasAcceptedContributions)
        let successorNode = ViewNode()
        fixture.root.addChild(successorNode)
        _ = fixture.journal.recordAcceptedAttachment(from: source, to: successorNode)
        _ = fixture.journal.recordCompletedNode(from: source, to: successorNode)
        let accepted = try XCTUnwrap(fixture.journal.recordAcceptedGroup(proposal))
        XCTAssertTrue(accepted.receipt.isActive)
        XCTAssertTrue(accepted.receipt.physical === fixture.physical)
        let disposition = fixture.journal.seal(completedCheckedAdoption: true)
        XCTAssertEqual(disposition.stop, .completedCheckedAdoption)
        XCTAssertEqual(fixture.physical.state, .active)
        XCTAssertEqual(fixture.physical.actualAttachments.count, 1)
        XCTAssertTrue(fixture.physical.actualAttachments.first?.node === successorNode)
    }

    func testActivationRejectsAuthorityThatChangedAfterReservation() async throws {
        for invalidation in HandoffPreparationInvalidation.allCases {
            let fixture = try HandoffPreparationFixture()
            defer { withExtendedLifetime(fixture) {} }
            XCTAssertNotNil(fixture.attribution.registerGroup(kind: .objectDependency))
            XCTAssertTrue(fixture.reserve())
            let preparation = try XCTUnwrap(fixture.journal.preparation())
            XCTAssertTrue(fixture.beginAdoption(preparation))
            switch invalidation {
            case .sourceGeneration:
                XCTAssertTrue(fixture.source.replaceData([0], id: \.self, rowContent: { _ in [] }))
                XCTAssertFalse(fixture.successor.request.isGenerationCurrent)
            case .logicalMembership:
                fixture.membership.revoke()
                XCTAssertFalse(fixture.membership.isDeclared)
            case .attachment:
                // Keep the physical lifetime active on another real attachment
                // so the stale captured attachment must still be checked.
                let other = ViewNode()
                fixture.root.addChild(other)
                let otherActual = other.lazyListActivityStorage().captureActualAttachment(
                    of: other, in: fixture.runtime)
                XCTAssertTrue(fixture.physical.activate(on: otherActual))
                fixture.rowNode.lazyListActivityStorage().revokeAttachment()
                XCTAssertFalse(fixture.actual.isAttached)
                XCTAssertEqual(fixture.physical.state, .active)
            }

            XCTAssertFalse(fixture.journal.markMutationStarted(), "\(invalidation)")
            XCTAssertFalse(fixture.journal.hasAcceptedContributions)
            let disposition = fixture.journal.seal()
            XCTAssertEqual(disposition.stop, .noAcceptance)
            XCTAssertTrue(disposition.acceptedGroups.isEmpty)
            XCTAssertTrue(disposition.acceptedEmptyGroups.isEmpty)
            XCTAssertTrue(disposition.acceptedFacets.isEmpty)
        }
    }
}

private enum HandoffPreparationInvalidation: CaseIterable {
    case sourceGeneration, logicalMembership, attachment
}

@MainActor
private final class HandoffPreparationFixture {
    let root: ViewNode
    let rowNode: ViewNode
    let runtime: RetainedViewRuntime
    let source: RetainedLazyListDataSource<Int, [ViewNode]>
    let membership: RetainedLazyListLogicalMembershipReceipt
    let physical: RetainedLazyListPhysicalActivityReceipt
    let actual: RetainedLazyListActualAttachment
    let journal: RetainedLazyListAdoptionJournal
    let attribution: RetainedLazyListBuildAttribution
    let previous: RetainedLazyListMaterializedRowActivity
    let successor: RetainedLazyListMaterializedRowActivity

    init() throws {
        let root = ViewNode()
        let rowNode = ViewNode()
        root.addChild(rowNode)
        let runtime = RetainedViewRuntime(root: root)
        let source = RetainedLazyListDataSource<Int, [ViewNode]>()
        XCTAssertTrue(source.replaceData([0], id: \.self, rowContent: { _ in [] }))
        let metadata = try XCTUnwrap(source.metadata)
        let scope = RetainedLazyListDescriptorBuildScope(
            origin: .componentHostRoot, hostLifetime: runtime.lazyListLogicalHostLifetime,
            ownerLifetime: root.lazyListActivityStorage().descriptorOwnerLifetime)
        let logical = try XCTUnwrap(RetainedLazyListLogicalMembershipScope(in: scope, parentRow: nil))
        let membership = try XCTUnwrap(logical.proposeMembership(id: RetainedLazyListMembershipID()))
        let descriptorJournal = RetainedLazyListAdoptionJournal(
            descriptorScope: scope, transaction: RetainedBuildTransaction())
        let binding = RetainedLazyListManagedLogicalDescriptorBinding(
            descriptor: RetainedLazyListLogicalDeclarationID(), facadeProposal: RetainedLazyListLogicalProposalID(),
            scope: logical, metadata: metadata)
        let adapter = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter(
                provider: source, estimatedExtent: 20, prefetchExtent: 0,
                maximumMountedRecords: 2, maximumMountedLeaves: 2, maximumProtectedRecords: 1))
        XCTAssertTrue(adapter.installManagedLogicalDescriptor(binding))
        let descriptorSource = ViewNode()
        descriptorSource.retainedLazyListAdapter = adapter
        XCTAssertNotNil(descriptorJournal.registerSourceDescriptor(binding, on: descriptorSource))
        let preparation = try XCTUnwrap(descriptorJournal.preparation())
        let snapshot = try XCTUnwrap(preparation.logicalSnapshots.first { $0.scope === logical })
        let plan = try XCTUnwrap(
            RetainedLazyListLogicalMembershipPlan(
                descriptor: binding.descriptor, facadeProposal: binding.facadeProposal,
                expected: snapshot, sourceGeneration: metadata.generation,
                introduced: [membership], retained: [], deleted: []))
        XCTAssertTrue(
            descriptorJournal.beginAdoption(
                preparation,
                preparedActivity: RetainedLazyListPreparedActivity(
                    preparation: preparation, logicalMembershipPlans: [plan])))
        guard case .ready(let publication) = descriptorJournal.prepareDescriptorCopy(from: descriptorSource, to: root)
        else { throw HandoffPreparationError.descriptor }
        XCTAssertTrue(descriptorJournal.markMutationStarted())
        XCTAssertNotNil(descriptorJournal.recordAcceptedLogicalDeclaration(publication))
        _ = descriptorJournal.seal(completedCheckedAdoption: true)
        scope.finish()
        XCTAssertTrue(membership.isDeclared)

        let physical = RetainedLazyListPhysicalActivityReceipt(membership: membership.id)
        let actual = rowNode.lazyListActivityStorage().captureActualAttachment(of: rowNode, in: runtime)
        XCTAssertTrue(physical.activate(on: actual))
        let request = try XCTUnwrap(source.request(for: try XCTUnwrap(metadata.rows.first?.token)))
        let oldAttribution = RetainedLazyListBuildAttribution(
            journal: descriptorJournal, rowRequest: request, logicalMembership: membership, physical: physical,
            component: RetainedLazyListComponentID(), resolutionID: RetainedLazyListRowResolutionID(),
            origin: .selectedRow)
        let replacementScope = RetainedLazyListDescriptorBuildScope(
            origin: .componentHostRoot, hostLifetime: runtime.lazyListLogicalHostLifetime,
            ownerLifetime: root.lazyListActivityStorage().descriptorOwnerLifetime)
        let journal = RetainedLazyListAdoptionJournal(
            descriptorScope: replacementScope, transaction: RetainedBuildTransaction())
        let parent = RetainedLazyListBuildAttribution(
            journal: journal, rowRequest: request, logicalMembership: membership, physical: physical,
            component: RetainedLazyListComponentID(), resolutionID: RetainedLazyListRowResolutionID(),
            origin: .selectedRow)
        let attribution = try XCTUnwrap(parent.registerChildComponent())
        self.root = root
        self.rowNode = rowNode
        self.runtime = runtime
        self.source = source
        self.membership = membership
        self.physical = physical
        self.actual = actual
        self.journal = journal
        self.attribution = attribution
        previous = RetainedLazyListMaterializedRowActivity(oldAttribution)
        successor = RetainedLazyListMaterializedRowActivity(attribution)
    }

    func reserve() -> Bool {
        journal.prepareRowReplacementHandoff(from: previous, to: successor)
    }

    func beginAdoption(_ preparation: RetainedLazyListAdoptionPreparation) -> Bool {
        journal.beginAdoption(
            preparation,
            preparedActivity: RetainedLazyListPreparedActivity(preparation: preparation, logicalMembershipPlans: []))
    }
}

private enum HandoffPreparationError: Error {
    case descriptor
}
