@preconcurrency import XCTest

@testable import SwiftWindowsUI

/// Native accepted-write fixtures only; these do not render a window or run a task.
@MainActor
final class RetainedLazyListCompletionPeerTests: XCTestCase {
    func testSameJournalCompletionPreservesBothAcceptedPeers() async throws {
        let fixture = try CompletionPeerFixture()
        defer { withExtendedLifetime(fixture) {} }
        let operation = fixture.operation()
        let firstSource = try operation.stage(.ownedState)
        let secondSource = try operation.stage(.observation)
        try operation.begin()
        let first = try operation.accept(firstSource)
        XCTAssertTrue(first.receipt.isActive)
        let second = try operation.accept(secondSource)
        let firstActual = try XCTUnwrap(first.acceptedFacets.first?.actual)
        let secondActual = try XCTUnwrap(second.acceptedFacets.first?.actual)

        XCTAssertTrue(first.receipt.isActive)
        XCTAssertTrue(second.receipt.isActive)
        XCTAssertFalse(first.receipt === second.receipt)
        XCTAssertTrue(first.proposal.attempt === second.proposal.attempt)
        XCTAssertTrue(first.receipt.physical === second.receipt.physical)
        XCTAssertTrue(firstActual.target === secondActual.target)
        XCTAssertTrue(firstActual.attachment === secondActual.attachment)
        let storage = fixture.target.lazyListActivityStorage()
        XCTAssertTrue(storage.committedContributions[ObjectIdentifier(first.proposal.group)] === first.receipt)
        XCTAssertTrue(storage.committedContributions[ObjectIdentifier(second.proposal.group)] === second.receipt)

        // Repeated completion in the opposite order must not retire the second peer.
        _ = operation.journal.recordCompletedNode(from: firstSource.node, to: fixture.target)
        XCTAssertTrue(first.receipt.isActive)
        XCTAssertTrue(second.receipt.isActive)
        let disposition = operation.journal.seal(completedCheckedAdoption: true)
        XCTAssertEqual(disposition.acceptedGroups.count, 2)
        XCTAssertTrue(disposition.acceptedAbsences.isEmpty)
        XCTAssertTrue(disposition.acceptedCleanup.isEmpty)
        first.receipt.revoke()
        XCTAssertFalse(first.receipt.isActive)
        XCTAssertTrue(second.receipt.isActive)
        XCTAssertTrue(firstActual.isAttached)
        XCTAssertEqual(fixture.physical.state, .active)
    }

    func testPriorJournalContributionRetiresDespiteSharedPhysicalAndAttachment() async throws {
        let fixture = try CompletionPeerFixture()
        defer { withExtendedLifetime(fixture) {} }
        let previous = fixture.operation()
        let oldSource = try previous.stage(.ownedState)
        try previous.begin()
        let old = try previous.accept(oldSource)
        let oldActual = try XCTUnwrap(old.acceptedFacets.first?.actual)
        XCTAssertTrue(old.receipt.isActive)
        _ = previous.journal.seal(completedCheckedAdoption: true)
        previous.scope.finish()

        let successor = fixture.operation()
        let newSource = try successor.stage(.observation)
        try successor.begin()
        let current = try successor.accept(newSource)
        let currentActual = try XCTUnwrap(current.acceptedFacets.first?.actual)
        XCTAssertFalse(old.proposal.attempt === current.proposal.attempt)
        XCTAssertTrue(old.receipt.physical === current.receipt.physical)
        XCTAssertTrue(oldActual.target === currentActual.target)
        XCTAssertTrue(oldActual.attachment === currentActual.attachment)
        XCTAssertTrue(oldActual.isAttached)
        XCTAssertTrue(currentActual.isAttached)
        XCTAssertFalse(old.receipt.isActive)
        XCTAssertTrue(current.receipt.isActive)
        XCTAssertEqual(fixture.physical.state, .active)
        let storage = fixture.target.lazyListActivityStorage()
        XCTAssertNil(storage.committedContributions[ObjectIdentifier(old.proposal.group)])
        XCTAssertTrue(storage.committedContributions[ObjectIdentifier(current.proposal.group)] === current.receipt)
        let disposition = successor.journal.seal(completedCheckedAdoption: true)
        XCTAssertEqual(disposition.acceptedAbsences.count, 1)
        XCTAssertTrue(disposition.acceptedAbsences.first?.previous === old.receipt)
        XCTAssertEqual(disposition.acceptedCleanup.count, 1)
        XCTAssertFalse(old.receipt.activate(on: [currentActual]))
    }

    func testExplicitAbsenceAndDepartureStillRetireCurrentJournalPeers() async throws {
        let fixture = try CompletionPeerFixture()
        defer { withExtendedLifetime(fixture) {} }
        let operation = fixture.operation()
        let firstSource = try operation.stage(.ownedState)
        let secondSource = try operation.stage(.observation)
        try operation.begin()
        let first = try operation.accept(firstSource)
        let second = try operation.accept(secondSource)
        let actual = try XCTUnwrap(first.acceptedFacets.first?.actual)
        XCTAssertTrue(first.receipt.isActive)
        XCTAssertTrue(second.receipt.isActive)

        let absence = RetainedLazyListAcceptedAbsence(
            previous: first.receipt, actual: actual, removalFacets: first.acceptedFacets,
            cleanup: RetainedLazyListCleanupID())
        operation.journal.recordAcceptedAbsence(absence)
        XCTAssertFalse(first.receipt.isActive)
        XCTAssertTrue(second.receipt.isActive)
        XCTAssertTrue(actual.isAttached)
        XCTAssertEqual(fixture.physical.state, .active)
        XCTAssertFalse(first.receipt.activate(on: [actual]))
        let storage = fixture.target.lazyListActivityStorage()
        XCTAssertNil(storage.committedContributions[ObjectIdentifier(first.proposal.group)])
        XCTAssertTrue(storage.committedContributions[ObjectIdentifier(second.proposal.group)] === second.receipt)

        let departure = try XCTUnwrap(
            operation.journal.recordPhysicalDeparture(of: fixture.target, cause: .acceptedReplacement))
        XCTAssertTrue(departure.physical === fixture.physical)
        XCTAssertEqual(departure.contributions.count, 1)
        XCTAssertTrue(departure.contributions.first === second.receipt)
        XCTAssertFalse(second.receipt.isActive)
        XCTAssertTrue(actual.isAttached)
        fixture.target.removeFromParent()
        XCTAssertFalse(actual.isAttached)
        XCTAssertTrue(storage.committedContributions.isEmpty)
        XCTAssertEqual(fixture.physical.state, .revoked)

        fixture.root.addChild(fixture.target)
        let replacement = storage.captureActualAttachment(of: fixture.target, in: fixture.runtime)
        XCTAssertTrue(replacement.isAttached)
        XCTAssertFalse(first.receipt.activate(on: [replacement]))
        XCTAssertFalse(second.receipt.activate(on: [replacement]))
        let disposition = operation.journal.seal()
        XCTAssertEqual(disposition.acceptedAbsences.count, 1)
        XCTAssertTrue(disposition.acceptedAbsences.first?.previous === first.receipt)
        XCTAssertEqual(disposition.acceptedDepartures.count, 1)
        XCTAssertEqual(disposition.acceptedCleanup.count, 2)
    }

    func testAcceptedPropertyReplacementStillRetiresCurrentJournalPeer() async throws {
        let fixture = try CompletionPeerFixture()
        defer { withExtendedLifetime(fixture) {} }
        let operation = fixture.operation()
        let firstSource = try operation.stage(.ownedState)
        let secondSource = try operation.stage(.observation)
        firstSource.node.onActivate = {}
        secondSource.node.onActivate = {}
        try operation.begin()
        operation.copyActivation(from: firstSource)
        let first = try operation.accept(firstSource)
        let actual = try XCTUnwrap(first.acceptedFacets.first?.actual)
        XCTAssertTrue(first.receipt.isActive)

        operation.copyActivation(from: secondSource)
        XCTAssertFalse(first.receipt.isActive)
        let second = try operation.accept(secondSource)
        XCTAssertTrue(second.receipt.isActive)
        XCTAssertTrue(first.receipt.physical === second.receipt.physical)
        XCTAssertTrue(actual.isAttached)
        XCTAssertEqual(fixture.physical.state, .active)
        let disposition = operation.journal.seal(completedCheckedAdoption: true)
        XCTAssertEqual(disposition.acceptedAbsences.count, 1)
        let absence = try XCTUnwrap(disposition.acceptedAbsences.first)
        XCTAssertTrue(absence.previous === first.receipt)
        XCTAssertEqual(absence.removalFacets.count, 1)
        guard case .nodeProperty(let keyPath) = try XCTUnwrap(absence.removalFacets.first).source.nativeField else {
            return XCTFail("Property replacement must retain its exact removal facet")
        }
        XCTAssertEqual(keyPath, \ViewNode.onActivate)
        XCTAssertFalse(first.receipt.activate(on: [actual]))
    }
}

@MainActor
private final class CompletionPeerFixture {
    let root: ViewNode
    let target: ViewNode
    let runtime: RetainedViewRuntime
    let source: RetainedLazyListDataSource<Int, [ViewNode]>
    let membership: RetainedLazyListLogicalMembershipReceipt
    let physical: RetainedLazyListPhysicalActivityReceipt
    let request: RetainedLazyListRowRequest

    init() throws {
        let root = ViewNode()
        let target = ViewNode()
        root.addChild(target)
        let runtime = RetainedViewRuntime(root: root)
        let source = RetainedLazyListDataSource<Int, [ViewNode]>()
        XCTAssertTrue(source.replaceData([0], id: \.self, rowContent: { _ in [] }))
        let metadata = try XCTUnwrap(source.metadata)
        let scope = RetainedLazyListDescriptorBuildScope(
            origin: .componentHostRoot, hostLifetime: runtime.lazyListLogicalHostLifetime,
            ownerLifetime: root.lazyListActivityStorage().descriptorOwnerLifetime)
        let logical = try XCTUnwrap(RetainedLazyListLogicalMembershipScope(in: scope, parentRow: nil))
        let membership = try XCTUnwrap(logical.proposeMembership(id: RetainedLazyListMembershipID()))
        let journal = RetainedLazyListAdoptionJournal(descriptorScope: scope, transaction: RetainedBuildTransaction())
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
        XCTAssertNotNil(journal.registerSourceDescriptor(binding, on: descriptorSource))
        let preparation = try XCTUnwrap(journal.preparation())
        let snapshot = try XCTUnwrap(preparation.logicalSnapshots.first { $0.scope === logical })
        let plan = try XCTUnwrap(
            RetainedLazyListLogicalMembershipPlan(
                descriptor: binding.descriptor, facadeProposal: binding.facadeProposal,
                expected: snapshot, sourceGeneration: metadata.generation,
                introduced: [membership], retained: [], deleted: []))
        XCTAssertTrue(
            journal.beginAdoption(
                preparation,
                preparedActivity: RetainedLazyListPreparedActivity(
                    preparation: preparation, logicalMembershipPlans: [plan])))
        guard case .ready(let publication) = journal.prepareDescriptorCopy(from: descriptorSource, to: root) else {
            throw CompletionPeerFixtureError.descriptor
        }
        XCTAssertTrue(journal.markMutationStarted())
        XCTAssertNotNil(journal.recordAcceptedLogicalDeclaration(publication))
        _ = journal.seal(completedCheckedAdoption: true)
        scope.finish()
        XCTAssertTrue(membership.isDeclared)

        self.root = root
        self.target = target
        self.runtime = runtime
        self.source = source
        self.membership = membership
        physical = RetainedLazyListPhysicalActivityReceipt(membership: membership.id)
        request = try XCTUnwrap(source.request(for: try XCTUnwrap(metadata.rows.first?.token)))
    }

    func operation() -> CompletionPeerOperation { CompletionPeerOperation(fixture: self) }
}

@MainActor
private final class CompletionPeerOperation {
    let fixture: CompletionPeerFixture
    let scope: RetainedLazyListDescriptorBuildScope
    let journal: RetainedLazyListAdoptionJournal
    let attribution: RetainedLazyListBuildAttribution

    init(fixture: CompletionPeerFixture) {
        self.fixture = fixture
        scope = RetainedLazyListDescriptorBuildScope(
            origin: .componentHostRoot, hostLifetime: fixture.runtime.lazyListLogicalHostLifetime,
            ownerLifetime: fixture.root.lazyListActivityStorage().descriptorOwnerLifetime)
        journal = RetainedLazyListAdoptionJournal(descriptorScope: scope, transaction: RetainedBuildTransaction())
        attribution = RetainedLazyListBuildAttribution(
            journal: journal, rowRequest: fixture.request, logicalMembership: fixture.membership,
            physical: fixture.physical, component: RetainedLazyListComponentID(),
            resolutionID: RetainedLazyListRowResolutionID(), origin: .selectedRow)
    }

    func stage(_ kind: RetainedLazyListContributionKind) throws -> CompletionPeerSource {
        let node = ViewNode()
        let group = try XCTUnwrap(attribution.registerGroup(kind: kind))
        XCTAssertNotNil(attribution.recordSourceOutput(node, group: group))
        return CompletionPeerSource(node: node, proposal: try XCTUnwrap(attribution.closeGroup(group)))
    }

    func begin() throws {
        let preparation = try XCTUnwrap(journal.preparation())
        XCTAssertTrue(
            journal.beginAdoption(
                preparation,
                preparedActivity: RetainedLazyListPreparedActivity(
                    preparation: preparation, logicalMembershipPlans: [])))
        XCTAssertTrue(journal.markMutationStarted())
    }

    func accept(_ source: CompletionPeerSource) throws -> RetainedLazyListAcceptedGroup {
        _ = journal.recordAcceptedAttachment(from: source.node, to: fixture.target)
        _ = journal.recordCompletedNode(from: source.node, to: fixture.target)
        return try XCTUnwrap(journal.recordAcceptedGroup(source.proposal))
    }

    @inline(never)
    func copyActivation(from source: CompletionPeerSource) {
        XCTAssertTrue(
            journal.preparePropertyCopy(from: source.node, to: fixture.target, keyPath: \ViewNode.onActivate))
        let previous = fixture.target.onActivate
        fixture.target.onActivate = source.node.onActivate
        _ = journal.recordAcceptedProperty(from: source.node, to: fixture.target, keyPath: \ViewNode.onActivate)
        withExtendedLifetime(previous) {}
    }
}

@MainActor
private struct CompletionPeerSource {
    let node: ViewNode
    let proposal: RetainedLazyListGroupProposal
}

private enum CompletionPeerFixtureError: Error {
    case descriptor
}
