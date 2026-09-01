import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// These fixtures use real selected-row reservations and native adapter
/// candidates. Explicit journal notifications below test the publication seam;
/// ManagedLazyListBareEmptyMembershipTests covers the complete facade path.
@MainActor
final class RetainedLazyListAcceptedMembershipTests: XCTestCase {
    func testCompletedEmptyTableSealsMembershipWithoutAnOwnedComponentOrEffectGroup() async throws {
        let fixture = try EmptyMembershipFixture()
        defer { fixture.close() }
        let attempt = try fixture.makeAttempt()
        try attempt.beginAdoption()
        XCTAssertTrue(attempt.preparation?.groups.isEmpty == true)
        XCTAssertTrue(attempt.preparation?.ownedComponentDeclarations.isEmpty == true)
        XCTAssertTrue(attempt.candidate.children.isEmpty)
        XCTAssertEqual(attempt.candidate.recordLeafCounts, [0])

        XCTAssertTrue(attempt.completeTable())
        let disposition = attempt.journal.seal(completedCheckedAdoption: true)

        XCTAssertEqual(disposition.stop, .completedCheckedAdoption)
        XCTAssertEqual(disposition.acceptedRowMemberships.count, 1)
        XCTAssertTrue(disposition.acceptedRowMemberships.first === attempt.activity.reservations[0].membership)
        XCTAssertTrue(disposition.acceptedOwnedComponents.isEmpty)
        XCTAssertTrue(disposition.acceptedGroups.isEmpty)
        XCTAssertTrue(disposition.acceptedEmptyGroups.isEmpty)
        XCTAssertTrue(disposition.partialGroups.isEmpty)
        XCTAssertEqual(fixture.adapter.mountedRecordCount, 1)
        XCTAssertEqual(fixture.calls.values, [0])
    }

    func testRepeatedRowCompletionKeepsOneEntryPerOriginalComponentAndSealIsImmutable() async throws {
        let fixture = try EmptyMembershipFixture()
        defer { fixture.close() }
        let attempt = try fixture.makeAttempt()
        try attempt.beginAdoption()
        XCTAssertTrue(attempt.completeTable())
        let row = try XCTUnwrap(attempt.activity.rows.first)
        for _ in 0..<128 {
            XCTAssertTrue(attempt.recordCompletion(row))
        }

        let disposition = attempt.journal.seal(completedCheckedAdoption: true)

        XCTAssertEqual(disposition.acceptedRowMemberships.count, 1)
        XCTAssertTrue(disposition.acceptedRowMemberships.first === row.membership)
        XCTAssertFalse(attempt.recordCompletion(row))
        XCTAssertTrue(attempt.journal.seal() === disposition)
        XCTAssertEqual(disposition.acceptedRowMemberships.count, 1)
        XCTAssertEqual(fixture.calls.values, [0])
    }

    func testCompletedSiblingTablesSealEveryMembershipWithoutDictionaryOrderAssumptions() async throws {
        let fixture = try EmptyMembershipFixture(rows: [0, 1])
        defer { fixture.close() }
        let attempt = try fixture.makeAttempt()
        try attempt.beginAdoption()
        XCTAssertEqual(attempt.candidate.recordLeafCounts, [0, 0])

        XCTAssertTrue(attempt.completeTable())
        let disposition = attempt.journal.seal(completedCheckedAdoption: true)

        XCTAssertEqual(disposition.acceptedRowMemberships.count, 2)
        XCTAssertEqual(
            Set(disposition.acceptedRowMemberships.map { ObjectIdentifier($0) }),
            Set(attempt.activity.reservations.map { ObjectIdentifier($0.membership) }))
        XCTAssertTrue(disposition.acceptedOwnedComponents.isEmpty)
        XCTAssertTrue(disposition.acceptedGroups.isEmpty)
        XCTAssertTrue(disposition.acceptedEmptyGroups.isEmpty)
        XCTAssertEqual(fixture.calls.values, [0, 1])
    }

    func testEmptyFactoryObservationWithoutTableCompletionDoesNotPublishMembership() async throws {
        let fixture = try EmptyMembershipFixture()
        defer { fixture.close() }
        let attempt = try fixture.makeAttempt()
        try attempt.beginAdoption()
        let row = try XCTUnwrap(attempt.activity.rows.first)
        XCTAssertTrue(row.logicalMembership.isDeclared)
        XCTAssertEqual(row.physical.state, .provisional)
        XCTAssertEqual(fixture.calls.values, [0])
        XCTAssertTrue(attempt.candidate.children.isEmpty)

        let disposition = attempt.journal.seal()

        XCTAssertEqual(disposition.stop, .stoppedAfterAcceptance)
        XCTAssertEqual(disposition.acceptedLogicalDeclarations.count, 1)
        XCTAssertTrue(disposition.acceptedRowMemberships.isEmpty)
        XCTAssertTrue(row.physical.actualAttachments.isEmpty)
    }

    func testRejectedEmptyComponentCannotPublishMembership() async throws {
        let fixture = try EmptyMembershipFixture()
        defer { fixture.close() }
        let attempt = try fixture.makeAttempt()
        let row = try XCTUnwrap(attempt.activity.rows.first)
        row.rejectConstruction()
        try attempt.beginAdoption()
        XCTAssertTrue(row.logicalMembership.isDeclared)

        XCTAssertFalse(attempt.recordCompletion(row))

        XCTAssertTrue(attempt.journal.seal().acceptedRowMemberships.isEmpty)
        XCTAssertTrue(row.physical.actualAttachments.isEmpty)
        XCTAssertEqual(fixture.calls.values, [0])
    }

    func testForeignAttemptCannotPublishAnOtherwiseDeclaredEmptyRow() async throws {
        let fixture = try EmptyMembershipFixture()
        let foreign = try EmptyMembershipFixture()
        defer {
            fixture.close()
            foreign.close()
        }
        let attempt = try fixture.makeAttempt()
        let other = try foreign.makeAttempt()
        try attempt.beginAdoption()
        try other.beginAdoption()
        let row = try XCTUnwrap(attempt.activity.rows.first)
        let foreignRow = try XCTUnwrap(other.activity.rows.first)
        XCTAssertTrue(foreignRow.logicalMembership.isDeclared)
        XCTAssertFalse(foreignRow.attempt === attempt.journal.attempt)

        XCTAssertFalse(attempt.recordCompletion(foreignRow))
        XCTAssertTrue(attempt.recordCompletion(row))
        let disposition = attempt.journal.seal()

        XCTAssertEqual(disposition.acceptedRowMemberships.count, 1)
        XCTAssertTrue(disposition.acceptedRowMemberships.first === row.membership)
        XCTAssertFalse(disposition.acceptedRowMemberships.contains { $0 === foreignRow.membership })
        XCTAssertTrue(foreignRow.physical.actualAttachments.isEmpty)
    }

    func testDetachedOriginalAnchorCannotPublishEmptyMembership() async throws {
        let fixture = try EmptyMembershipFixture()
        defer { fixture.close() }
        let attempt = try fixture.makeAttempt()
        try attempt.beginAdoption()
        let row = try XCTUnwrap(attempt.activity.rows.first)
        XCTAssertTrue(attempt.anchor.isAttached)
        fixture.target.lazyListActivityStorage().revokeAttachment()
        XCTAssertFalse(attempt.anchor.isAttached)

        XCTAssertFalse(attempt.recordCompletion(row))

        XCTAssertTrue(attempt.journal.seal().acceptedRowMemberships.isEmpty)
        XCTAssertTrue(row.physical.actualAttachments.isEmpty)
    }

    func testRevokedLogicalMembershipCannotPublishAnEmptyTable() async throws {
        let fixture = try EmptyMembershipFixture()
        defer { fixture.close() }
        let attempt = try fixture.makeAttempt()
        try attempt.beginAdoption()
        let row = try XCTUnwrap(attempt.activity.rows.first)
        row.logicalMembership.revoke()
        XCTAssertFalse(row.logicalMembership.isDeclared)

        XCTAssertFalse(attempt.recordCompletion(row))

        XCTAssertTrue(attempt.journal.seal().acceptedRowMemberships.isEmpty)
        XCTAssertTrue(row.physical.actualAttachments.isEmpty)
    }

    func testPartialCompletionSealsOnlyTheAcceptedRowsWithoutDependingOnDictionaryOrder() async throws {
        let fixture = try EmptyMembershipFixture(rows: [0, 1])
        defer { fixture.close() }
        let attempt = try fixture.makeAttempt()
        try attempt.beginAdoption()
        XCTAssertEqual(attempt.activity.rows.count, 2)
        let first = attempt.activity.rows[0]
        let second = attempt.activity.rows[1]
        XCTAssertTrue(first.logicalMembership.isDeclared)
        XCTAssertTrue(second.logicalMembership.isDeclared)

        XCTAssertTrue(attempt.recordCompletion(first))
        let disposition = attempt.journal.seal()

        XCTAssertEqual(disposition.stop, .stoppedAfterAcceptance)
        XCTAssertEqual(
            Set(disposition.acceptedRowMemberships.map { ObjectIdentifier($0) }), [ObjectIdentifier(first.membership)])
        XCTAssertEqual(first.physical.state, .active)
        XCTAssertEqual(second.physical.state, .provisional)
        XCTAssertTrue(second.physical.actualAttachments.isEmpty)
        XCTAssertEqual(fixture.calls.values, [0, 1])
    }
}

@MainActor
final class MountedEmptyRowMembershipPublicationTests: XCTestCase {
    func testCompletedEmptyRowCommitsItsReservationWithoutGrantingStateOrEffectOwnership() async throws {
        let fixture = try EmptyMembershipFixture()
        defer { fixture.close() }
        let attempt = try fixture.makeAttempt()
        try attempt.beginAdoption()
        XCTAssertTrue(attempt.completeTable())
        let disposition = attempt.journal.seal(completedCheckedAdoption: true)
        let selection = try attempt.select(disposition)
        let reservation = try XCTUnwrap(attempt.activity.reservations.first)

        XCTAssertTrue(fixture.registry.commitLazySparseRow(reservation, selection: selection))

        XCTAssertTrue(try XCTUnwrap(reservation.boundRow).ownedSlots.isEmpty)
        XCTAssertEqual(fixture.registry.liveOwnerCount, 0)
        XCTAssertTrue(selection.acceptedOwnedSlots.isEmpty)
        XCTAssertTrue(selection.acceptedSyntheticCells.isEmpty)
        XCTAssertTrue(selection.acceptedGroups.isEmpty)
        XCTAssertTrue(selection.acceptedEmptyGroups.isEmpty)
        XCTAssertEqual(fixture.calls.values, [0])
    }

    func testUncompletedEmptyReservationIsNotAcceptedByTheDescriptorAlone() async throws {
        let fixture = try EmptyMembershipFixture()
        defer { fixture.close() }
        let attempt = try fixture.makeAttempt()
        try attempt.beginAdoption()
        let reservation = try XCTUnwrap(attempt.activity.reservations.first)
        let disposition = attempt.journal.seal()
        let selection = try attempt.select(disposition)
        XCTAssertEqual(disposition.acceptedLogicalDeclarations.count, 1)
        XCTAssertTrue(try XCTUnwrap(reservation.boundRow).isDeclared)
        XCTAssertTrue(disposition.acceptedRowMemberships.isEmpty)

        XCTAssertFalse(fixture.registry.commitLazySparseRow(reservation, selection: selection))

        XCTAssertEqual(fixture.registry.liveOwnerCount, 0)
        XCTAssertEqual(fixture.calls.values, [0])
    }

    func testPartialAcceptanceDoesNotCommitAnUncompletedSiblingReservation() async throws {
        let fixture = try EmptyMembershipFixture(rows: [0, 1])
        defer { fixture.close() }
        let attempt = try fixture.makeAttempt()
        try attempt.beginAdoption()
        XCTAssertTrue(attempt.recordCompletion(attempt.activity.rows[0]))
        let disposition = attempt.journal.seal()
        let selection = try attempt.select(disposition)

        XCTAssertTrue(fixture.registry.commitLazySparseRow(attempt.activity.reservations[0], selection: selection))
        XCTAssertFalse(fixture.registry.commitLazySparseRow(attempt.activity.reservations[1], selection: selection))

        XCTAssertEqual(disposition.acceptedRowMemberships.count, 1)
        XCTAssertEqual(fixture.registry.liveOwnerCount, 0)
        XCTAssertEqual(fixture.calls.values, [0, 1])
    }

    func testCurrentSelectionCannotAcceptAnOlderReservationForTheSameDeclaredMembership() async throws {
        let fixture = try EmptyMembershipFixture()
        defer { fixture.close() }
        let first = try fixture.makeAttempt()
        try first.beginAdoption()
        XCTAssertTrue(first.completeTable())
        let firstSelection = try first.select(first.journal.seal(completedCheckedAdoption: true))
        let oldReservation = try XCTUnwrap(first.activity.reservations.first)
        XCTAssertTrue(fixture.registry.commitLazySparseRow(oldReservation, selection: firstSelection))
        first.finish()

        let current = try fixture.makeAttempt()
        try current.beginAdoption()
        XCTAssertTrue(current.completeTable())
        let currentDisposition = current.journal.seal(completedCheckedAdoption: true)
        let currentSelection = try current.select(currentDisposition)
        let currentReservation = try XCTUnwrap(current.activity.reservations.first)
        XCTAssertTrue(currentReservation.membership === oldReservation.membership)
        XCTAssertTrue(currentReservation.boundRow === oldReservation.boundRow)
        XCTAssertTrue(try XCTUnwrap(oldReservation.boundRow).isDeclared)
        XCTAssertTrue(
            oldReservation.preparation.descriptor.scope.containsDeclaredDescriptor(
                oldReservation.preparation.descriptor.descriptor))
        XCTAssertFalse(oldReservation.preparation.attempt === currentSelection.attempt)
        XCTAssertTrue(currentDisposition.acceptedRowMemberships.contains { $0 === oldReservation.membership })

        XCTAssertFalse(fixture.registry.commitLazySparseRow(oldReservation, selection: currentSelection))
        XCTAssertFalse(fixture.registry.commitLazySparseRow(currentReservation, selection: firstSelection))
        XCTAssertTrue(fixture.registry.commitLazySparseRow(currentReservation, selection: currentSelection))

        XCTAssertEqual(fixture.calls.values, [0, 0])
        XCTAssertEqual(fixture.registry.liveOwnerCount, 0)
    }

    func testRevocationAfterNativeAcceptanceStillRejectsTheOriginalReservation() async throws {
        let fixture = try EmptyMembershipFixture()
        defer { fixture.close() }
        let attempt = try fixture.makeAttempt()
        try attempt.beginAdoption()
        XCTAssertTrue(attempt.completeTable())
        let reservation = try XCTUnwrap(attempt.activity.reservations.first)
        let row = try XCTUnwrap(reservation.boundRow)
        row.logicalReceipt.revoke()
        let disposition = attempt.journal.seal()
        let selection = try attempt.select(disposition)
        XCTAssertTrue(disposition.acceptedRowMemberships.contains { $0 === row.id })
        XCTAssertFalse(row.isDeclared)

        XCTAssertFalse(fixture.registry.commitLazySparseRow(reservation, selection: selection))

        XCTAssertTrue(row.ownedSlots.isEmpty)
        XCTAssertEqual(fixture.registry.liveOwnerCount, 0)
    }

    func testExpiredLogicalDescriptorScopeRejectsPreviouslyAcceptedEmptyMembership() async throws {
        let fixture = try EmptyMembershipFixture()
        defer { fixture.close() }
        let attempt = try fixture.makeAttempt()
        try attempt.beginAdoption()
        XCTAssertTrue(attempt.completeTable())
        let reservation = try XCTUnwrap(attempt.activity.reservations.first)
        attempt.binding.scope.revokeLogicalMembership()
        let disposition = attempt.journal.seal()
        let selection = try attempt.select(disposition)
        XCTAssertTrue(disposition.acceptedRowMemberships.contains { $0 === reservation.membership })
        XCTAssertFalse(attempt.binding.scope.containsDeclaredDescriptor(attempt.binding.descriptor))

        XCTAssertFalse(fixture.registry.commitLazySparseRow(reservation, selection: selection))

        XCTAssertEqual(fixture.registry.liveOwnerCount, 0)
    }

    func testNewNativeDescriptorCannotLendItsDeclarationToAnOldEmptyReservation() async throws {
        let fixture = try EmptyMembershipFixture()
        defer { fixture.close() }
        let attempt = try fixture.makeAttempt()
        try attempt.beginAdoption()
        XCTAssertTrue(attempt.completeTable())
        let reservation = try XCTUnwrap(attempt.activity.reservations.first)
        let row = try XCTUnwrap(reservation.boundRow)
        let replacement = try fixture.publishNativeReplacement(retaining: row.logicalReceipt)
        XCTAssertTrue(row.isDeclared)
        XCTAssertTrue(attempt.binding.scope.containsDeclaredDescriptor(replacement))
        XCTAssertFalse(attempt.binding.scope.containsDeclaredDescriptor(attempt.binding.descriptor))
        let disposition = attempt.journal.seal()
        let selection = try attempt.select(disposition)
        XCTAssertTrue(disposition.acceptedRowMemberships.contains { $0 === reservation.membership })

        XCTAssertFalse(fixture.registry.commitLazySparseRow(reservation, selection: selection))

        XCTAssertTrue(row.ownedSlots.isEmpty)
        XCTAssertEqual(fixture.registry.liveOwnerCount, 0)
    }

    func testClosedRegistryRejectsAnAlreadySelectedEmptyReservation() async throws {
        let fixture = try EmptyMembershipFixture()
        defer { fixture.close() }
        let attempt = try fixture.makeAttempt()
        try attempt.beginAdoption()
        XCTAssertTrue(attempt.completeTable())
        let disposition = attempt.journal.seal(completedCheckedAdoption: true)
        let selection = try attempt.select(disposition)
        let reservation = try XCTUnwrap(attempt.activity.reservations.first)
        fixture.registry.close()

        XCTAssertFalse(fixture.registry.commitLazySparseRow(reservation, selection: selection))

        XCTAssertTrue(disposition.acceptedRowMemberships.contains { $0 === reservation.membership })
        XCTAssertEqual(fixture.registry.liveOwnerCount, 0)
    }
}

@MainActor
private final class EmptyMembershipFixture {
    let target: ViewNode
    let runtime: RetainedViewRuntime
    let registry = StateMountRegistry()
    let calls: EmptyMembershipFactoryCalls
    let provider: RetainedLazyListDataSource<Int, [ViewNode]>
    let adapter: RetainedLazyListRuntimeAdapter
    private let lease = EmptyMembershipBuildLease()
    private var binding: RetainedLazyListManagedLogicalDescriptorBinding?
    private var attempts: [EmptyMembershipAttempt] = []
    private var isClosed = false

    init(rows: [Int] = [0]) throws {
        let target = ViewNode(frame: Rect(x: 0, y: 0, width: 120, height: 40))
        let runtime = RetainedViewRuntime(root: target)
        let calls = EmptyMembershipFactoryCalls()
        let provider = RetainedLazyListDataSource<Int, [ViewNode]>()
        XCTAssertTrue(
            provider.replaceData(
                rows, id: \.self,
                rowContent: { value in
                    calls.values.append(value)
                    return []
                }))
        let adapter = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter(
                provider: provider, estimatedExtent: 20, prefetchExtent: 0,
                maximumMountedRecords: 4, maximumMountedLeaves: 4, maximumProtectedRecords: 1))
        self.target = target
        self.runtime = runtime
        self.calls = calls
        self.provider = provider
        self.adapter = adapter
    }

    func makeAttempt() throws -> EmptyMembershipAttempt {
        let attempt = try EmptyMembershipAttempt(
            registry: registry, target: target, runtime: runtime, provider: provider,
            adapter: adapter, lease: lease, existingBinding: binding)
        binding = attempt.binding
        attempts.append(attempt)
        return attempt
    }

    /// A competing native declaration keeps the same logical row but replaces
    /// the descriptor identity. It deliberately does not update the old facade
    /// reservation, so that its original descriptor guard must reject commit.
    func publishNativeReplacement(retaining row: RetainedLazyListLogicalMembershipReceipt) throws
        -> RetainedLazyListLogicalDeclarationID
    {
        let old = try XCTUnwrap(binding)
        let metadata = try XCTUnwrap(provider.metadata)
        let scope = RetainedLazyListDescriptorBuildScope(
            origin: .componentHostRoot, hostLifetime: runtime.lazyListLogicalHostLifetime,
            ownerLifetime: target.lazyListActivityStorage().descriptorOwnerLifetime)
        let journal = RetainedLazyListAdoptionJournal(descriptorScope: scope, transaction: RetainedBuildTransaction())
        let replacement = RetainedLazyListManagedLogicalDescriptorBinding(
            descriptor: RetainedLazyListLogicalDeclarationID(), facadeProposal: RetainedLazyListLogicalProposalID(),
            scope: old.scope, metadata: metadata)
        let source = ViewNode()
        let sourceAdapter = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter(
                provider: provider, estimatedExtent: 20, prefetchExtent: 0,
                maximumMountedRecords: 4, maximumMountedLeaves: 4, maximumProtectedRecords: 1))
        XCTAssertTrue(sourceAdapter.installManagedLogicalDescriptor(replacement))
        source.retainedLazyListAdapter = sourceAdapter
        XCTAssertNotNil(journal.registerSourceDescriptor(replacement, on: source))
        let preparation = try XCTUnwrap(journal.preparation())
        let snapshot = try XCTUnwrap(preparation.logicalSnapshots.first { $0.scope === old.scope })
        let plan = try XCTUnwrap(
            RetainedLazyListLogicalMembershipPlan(
                descriptor: replacement.descriptor, facadeProposal: replacement.facadeProposal,
                expected: snapshot, sourceGeneration: metadata.generation,
                introduced: [], retained: [row], deleted: []))
        XCTAssertTrue(
            journal.beginAdoption(
                preparation,
                preparedActivity: RetainedLazyListPreparedActivity(
                    preparation: preparation, logicalMembershipPlans: [plan])))
        guard case .ready(let publication) = journal.prepareDescriptorCopy(from: source, to: target) else {
            throw EmptyMembershipFixtureError.descriptorPublication
        }
        XCTAssertTrue(journal.markMutationStarted())
        XCTAssertNotNil(journal.recordAcceptedLogicalDeclaration(publication))
        _ = journal.seal(completedCheckedAdoption: true)
        scope.finish()
        return replacement.descriptor
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        for attempt in attempts { attempt.finish() }
        attempts = []
        _ = adapter.releaseAttachment(from: target)
        registry.close()
        provider.close()
    }
}

@MainActor
private final class EmptyMembershipAttempt {
    let binding: RetainedLazyListManagedLogicalDescriptorBinding
    let journal: RetainedLazyListAdoptionJournal
    let activity: EmptyMembershipBuildActivity
    let admission: RetainedLazyListAdoptionAdmission
    let candidate: RetainedLazyListRuntimeAdapter.Candidate
    let anchor: RetainedLazyListActualAttachment
    private(set) var preparation: RetainedLazyListAdoptionPreparation?
    private let target: ViewNode
    private let adapter: RetainedLazyListRuntimeAdapter
    private let scope: RetainedLazyListDescriptorBuildScope
    private let nativeCoordinator: RetainedBuildCoordinator
    private let descriptorSource: ViewNode?
    private var isFinished = false

    init(
        registry: StateMountRegistry, target: ViewNode, runtime: RetainedViewRuntime,
        provider: RetainedLazyListDataSource<Int, [ViewNode]>, adapter: RetainedLazyListRuntimeAdapter,
        lease: EmptyMembershipBuildLease, existingBinding: RetainedLazyListManagedLogicalDescriptorBinding?
    ) throws {
        let epoch = try XCTUnwrap(registry.beginRootBuild())
        let activity = EmptyMembershipBuildActivity(registry: registry, epoch: epoch)
        let scope = RetainedLazyListDescriptorBuildScope(
            origin: .componentHostRoot, hostLifetime: runtime.lazyListLogicalHostLifetime,
            ownerLifetime: target.lazyListActivityStorage().descriptorOwnerLifetime)
        let nativeCoordinator = RetainedBuildCoordinator()
        var completedSetup = false
        defer {
            if !completedSetup {
                epoch.abort()
                scope.revoke()
                scope.finish()
                nativeCoordinator.finishBuild()
            }
        }
        XCTAssertTrue(activity.bindLazyListDescriptorScope(scope))
        let binding: RetainedLazyListManagedLogicalDescriptorBinding
        let descriptorSource: ViewNode?
        if let existingBinding {
            binding = existingBinding
            descriptorSource = nil
        } else {
            let identity = RetainedViewIdentity(segments: [.role(.content)])
            let owner = try XCTUnwrap(epoch.owner(at: identity))
            let receipt = try XCTUnwrap(
                LazyListDescriptorResolutionReceipt(
                    epoch: epoch, owner: owner, nativeScope: scope, containingAttribution: nil))
            let proposal = try XCTUnwrap(
                registry.stageLazyMembership(
                    at: identity, metadata: try XCTUnwrap(provider.metadata), parent: nil, in: epoch, receipt: receipt))
            binding = proposal.nativeBinding
            XCTAssertTrue(adapter.installManagedLogicalDescriptor(binding))
            let source = ViewNode()
            source.retainedLazyListAdapter = adapter
            descriptorSource = source
            target.retainedSubtreeBuildLease = lease
            target.retainedLazyListAdapter = adapter
            XCTAssertTrue(adapter.claimAttachment(to: target))
        }
        let sequence = try XCTUnwrap(nativeCoordinator.beginBuild())
        nativeCoordinator.install(activity, startedAt: sequence)
        let admission = RetainedLazyListAdoptionAdmission(
            adapter: adapter, container: target, runtime: runtime, coordinator: nativeCoordinator, sequence: sequence)
        XCTAssertTrue(admission.isBuildCurrent)
        let journal = RetainedLazyListAdoptionJournal(admission: admission, transaction: RetainedBuildTransaction())
        XCTAssertTrue(journal.bindDescriptorScope(scope))
        if let descriptorSource { XCTAssertNotNil(journal.registerSourceDescriptor(binding, on: descriptorSource)) }
        journal.seedExistingContributions(from: target.children)
        journal.seedExistingRowActivities(adapter.materializedRowActivities)
        let context = try XCTUnwrap(
            RetainedLazyListMeasurementContext(
                width: 120, displayScale: 1, contentRevision: 0, environmentRevision: 0))
        let viewport = try XCTUnwrap(RetainedLazyListRuntimeAdapter.Viewport(context: context, offset: 0, extent: 40))
        let budget = try XCTUnwrap(RetainedLazyListWorkBudget(elementLimit: 4, roundLimit: 4))
        guard
            case .ready(let candidate) = adapter.prepare(
                viewport: viewport, protectedRoots: [], budget: budget, admission: admission, activity: activity,
                journal: journal)
        else { throw EmptyMembershipFixtureError.candidate }
        XCTAssertTrue(admission.installCandidate(candidate))
        let anchor = target.lazyListActivityStorage().captureActualAttachment(of: target, in: runtime)
        XCTAssertTrue(anchor.isAttached)
        XCTAssertEqual(activity.reservations.count, activity.rows.count)
        self.target = target
        self.adapter = adapter
        self.binding = binding
        self.scope = scope
        self.descriptorSource = descriptorSource
        self.nativeCoordinator = nativeCoordinator
        self.activity = activity
        self.admission = admission
        self.journal = journal
        self.candidate = candidate
        self.anchor = anchor
        completedSetup = true
    }

    func beginAdoption() throws {
        let preparation = try XCTUnwrap(journal.preparation())
        self.preparation = preparation
        let prepared = try XCTUnwrap(activity.willAdoptLazyList(preparation))
        XCTAssertTrue(journal.beginAdoption(preparation, preparedActivity: prepared))
        XCTAssertTrue(candidate.configureManagedPublication(preparation))
        XCTAssertTrue(journal.markMutationStarted())
        if let descriptorSource {
            guard case .ready(let publication) = journal.prepareDescriptorCopy(from: descriptorSource, to: target)
            else {
                throw EmptyMembershipFixtureError.descriptorPublication
            }
            XCTAssertNotNil(journal.recordAcceptedLogicalDeclaration(publication))
        }
        XCTAssertTrue(admission.claimDepartingEmptyRows(journal: journal))
    }

    func completeTable() -> Bool {
        adapter.complete(candidate: candidate, adoptedChildren: [], journal: journal, structuralAnchor: anchor)
    }

    func recordCompletion(_ row: RetainedLazyListBuildAttribution) -> Bool {
        journal.recordCompletedOwnedRow(
            RetainedLazyListMaterializedRowActivity(row), sources: [], actualNodes: [], structuralAnchor: anchor)
    }

    func select(_ disposition: RetainedLazyListAdoptionDisposition) throws -> LazyListStateAdoptionSelection {
        activity.commitLazyList(disposition)
        return try XCTUnwrap(activity.selection)
    }

    func finish() {
        guard !isFinished else { return }
        isFinished = true
        journal.revokeBeforeAbandon()
        _ = journal.seal()
        admission.revoke()
        admission.finishCandidatePayload()
        journal.releaseUnadoptedTransport()
        if activity.selection == nil { activity.abandon() }
        activity.finishAfterCallbacks()
        scope.finish()
        nativeCoordinator.finishBuild()
    }
}

/// The test transport delegates lookup, preparation and selection to the real
/// registry. It keeps the original reservations so each test can call the same
/// sparse commit entry point that StateMountCoordinator calls after selection.
/// The descriptor's ordinary staging owner has no cells; no row State cell,
/// native owned component or effect group is created to obtain acceptance.
@MainActor
private final class EmptyMembershipBuildActivity: RetainedLazyListBuildActivity {
    let registry: StateMountRegistry
    let epoch: StateMountEpoch
    private(set) var reservations: [LazyListSelectedRowReservation] = []
    private(set) var rows: [RetainedLazyListBuildAttribution] = []
    private(set) var selection: LazyListStateAdoptionSelection?

    init(registry: StateMountRegistry, epoch: StateMountEpoch) {
        self.registry = registry
        self.epoch = epoch
    }

    var canAdopt: Bool { epoch.canAdopt }
    var canComplete: Bool { !registry.isClosed }
    func supersede() { epoch.supersede() }
    func willAdopt() -> Bool {
        XCTFail("Expected managed preparation")
        return false
    }
    func commit() { XCTFail("Expected managed selection") }
    func abandon() { epoch.abort() }
    func finishAfterCallbacks() { epoch.finishManagedTransport() }
    func bindLazyListDescriptorScope(_ scope: RetainedLazyListDescriptorBuildScope) -> Bool {
        epoch.bindNativeDescriptorScope(scope)
    }

    func resolveSelectedLazyListRow(_ preparation: RetainedLazyListSelectedRowPreparation)
        -> RetainedLazyListSelectedRowResolution?
    {
        guard let receipt = LazyListSelectionResolutionReceipt(epoch: epoch, nativePreparation: preparation),
            let reservation = registry.resolveSelectedLazyRow(preparation, in: epoch, receipt: receipt),
            let resolution = reservation.nativeResolution
        else { return nil }
        reservations.append(reservation)
        return resolution
    }

    func enterLazyListMaterialization(_ attribution: RetainedLazyListBuildAttribution) -> Bool {
        guard let reservation = reservations.first(where: { $0.resolutionID === attribution.resolutionID }),
            reservation.bindEnteredAttribution(attribution) != nil
        else { return false }
        rows.append(attribution)
        return true
    }

    func leaveLazyListMaterialization(_ attribution: RetainedLazyListBuildAttribution) {
        XCTAssertTrue(rows.last === attribution)
    }

    func willAdoptLazyList(_ preparation: RetainedLazyListAdoptionPreparation) -> RetainedLazyListPreparedActivity? {
        guard let plans = epoch.prepareLazyMembershipPlans(preparation), epoch.prepareLazyAdoption(preparation) else {
            return nil
        }
        return RetainedLazyListPreparedActivity(preparation: preparation, logicalMembershipPlans: plans)
    }

    func commitLazyList(_ disposition: RetainedLazyListAdoptionDisposition) {
        XCTAssertNil(selection)
        selection = epoch.commitLazyAdoption(disposition)
    }
}

@MainActor
private final class EmptyMembershipBuildLease: RetainedSubtreeBuildLease {
    var canBuild: Bool { true }
    func beginBuild() -> (any RetainedBuildEpoch)? { nil }
}

@MainActor
private final class EmptyMembershipFactoryCalls {
    var values: [Int] = []
}

private enum EmptyMembershipFixtureError: Error {
    case candidate, descriptorPublication
}
