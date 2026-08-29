import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Native Task transport fixtures. They do not activate the public data-List
/// factory or claim native appearance/scheduling parity with SwiftUI.
@MainActor
final class MountedLazyListTaskTests: XCTestCase {
    func testRawPhysicalRetirementRevokesAnAssociatedDeclarationWithNoSlots() async {
        let host = LazyTaskTransportHost()
        defer { host.close() }
        let declaration = host.installOrdinary()
        let state = host.node.retainedTaskState()
        XCTAssertTrue(declaration.canCommit)
        XCTAssertFalse(state.hasCommittedSlots)

        let cleanup = state.claimLazyPhysicalDeparture()

        XCTAssertFalse(declaration.canCommit)
        XCTAssertFalse(cleanup.isFinished)
        declaration.deliver(restart: false)
        XCTAssertFalse(state.hasCommittedSlots)
        cleanup.finish()
        cleanup.finish()
        XCTAssertTrue(cleanup.isFinished)
    }

    func testEveryOriginalStateCanBeRevokedBeforeTheFirstForestCallback() async {
        let first = LazyTaskTransportHost()
        let second = LazyTaskTransportHost()
        defer {
            first.close()
            second.close()
        }
        let firstDeclaration = first.installOrdinary()
        let secondDeclaration = second.installOrdinary()
        firstDeclaration.deliver(restart: false)
        // The second state intentionally has an association but no slot.
        let cleanups = [
            first.node.retainedTaskState().claimLazyPhysicalDeparture(),
            second.node.retainedTaskState().claimLazyPhysicalDeparture(),
        ]
        var callbackObservations: [[Bool]] = []
        let firstCallback = {
            callbackObservations.append([firstDeclaration.canCommit, secondDeclaration.canCommit])
        }
        firstCallback()
        XCTAssertEqual(callbackObservations, [[false, false]])
        XCTAssertFalse(first.node.retainedTaskState().hasCommittedSlots)
        for cleanup in cleanups { cleanup.finish() }
        XCTAssertTrue(cleanups.allSatisfy(\.isFinished))
    }

    func testClaimedCleanupReleasesPendingActionAfterCompletionPermissionIsLost() async {
        let host = LazyTaskTransportHost()
        defer { host.close() }
        var releases = 0
        let cleanup = host.claimPendingAction { releases += 1 }
        XCTAssertEqual(releases, 0)
        host.epoch.canComplete = false
        let ledger = RetainedLazyListAcceptedTaskCleanupLedger()
        ledger.appendClaimed(cleanup)

        RetainedBuildTransaction().perform { ledger.finishClaimed() }

        XCTAssertEqual(releases, 1)
        XCTAssertTrue(cleanup.isFinished)
        ledger.finishClaimed()
        XCTAssertEqual(releases, 1)
        // Keeping the receipt does not keep its finished executable payload.
        withExtendedLifetime(cleanup) { XCTAssertEqual(releases, 1) }
    }

    func testCleanupLedgerDeduplicatesObjectsAndDrainsAReentrantAppend() async {
        let first = LazyTaskTransportHost()
        let second = LazyTaskTransportHost()
        defer {
            first.close()
            second.close()
        }
        let ledger = RetainedLazyListAcceptedTaskCleanupLedger()
        var releases: [Int] = []
        let secondCleanup = second.claimPendingAction { releases.append(2) }
        let firstCleanup = first.claimPendingAction {
            releases.append(1)
            ledger.appendClaimed(secondCleanup)
            // The current outer drain retains responsibility for this append.
            ledger.finishClaimed()
        }
        ledger.appendClaimed(firstCleanup)
        ledger.appendClaimed(firstCleanup)

        RetainedBuildTransaction().perform { ledger.finishClaimed() }

        XCTAssertEqual(releases, [1, 2])
        XCTAssertTrue(firstCleanup.isFinished)
        XCTAssertTrue(secondCleanup.isFinished)
    }

    func testPendingActionCaptureReleasesInsideTheCapturedFullTransaction() async throws {
        let host = LazyTaskTransportHost()
        defer { host.close() }
        var observed: LazyTaskTransactionSnapshot?
        let cleanup = host.claimPendingAction { observed = LazyTaskTransactionSnapshot() }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        transaction.isContinuous = true
        transaction.scrollTargetAnchor = .bottom
        transaction.tracksVelocity = true
        let captured = withTransaction(transaction) { RetainedBuildTransaction() }
        let outer = Transaction(animation: .linear(duration: 7))

        withTransaction(outer) {
            captured.perform { cleanup.finish() }
            XCTAssertEqual(currentTransaction?.animation?.duration, 7)
            XCTAssertEqual(currentAnimationTransaction?.duration, 7)
        }

        let snapshot = try XCTUnwrap(observed)
        XCTAssertNotNil(snapshot.transaction)
        XCTAssertNil(snapshot.transaction?.animation)
        XCTAssertEqual(snapshot.transaction?.disablesAnimations, true)
        XCTAssertEqual(snapshot.transaction?.isContinuous, true)
        XCTAssertEqual(snapshot.transaction?.scrollTargetAnchor, .bottom)
        XCTAssertEqual(snapshot.transaction?.tracksVelocity, true)
        XCTAssertNil(snapshot.animationDuration)
    }

    func testPendingActionCapturePreservesLegacyAnimationWithoutInventingATransaction() async throws {
        let host = LazyTaskTransportHost()
        defer { host.close() }
        var observed: LazyTaskTransactionSnapshot?
        let cleanup = host.claimPendingAction { observed = LazyTaskTransactionSnapshot() }
        let previousTransaction = currentTransaction
        let previousAnimation = currentAnimationTransaction
        currentTransaction = nil
        currentAnimationTransaction = (duration: 3, easing: .linear)
        let captured = RetainedBuildTransaction()
        currentTransaction = previousTransaction
        currentAnimationTransaction = previousAnimation
        let outer = Transaction(animation: .linear(duration: 8))

        withTransaction(outer) {
            captured.perform { cleanup.finish() }
            XCTAssertEqual(currentTransaction?.animation?.duration, 8)
            XCTAssertEqual(currentAnimationTransaction?.duration, 8)
        }

        let snapshot = try XCTUnwrap(observed)
        XCTAssertNil(snapshot.transaction)
        XCTAssertEqual(snapshot.animationDuration, 3)
        XCTAssertEqual(snapshot.animationEasing, .linear)
    }

    func testOriginalCleanupDoesNotCancelAReentrantSameMountReplacement() async {
        let host = LazyTaskTransportHost()
        let probe = LazyTaskRunProbe()
        defer {
            probe.onReady = nil
            probe.onCancellation = nil
            host.close()
            probe.releaseAll()
        }
        let mount = RetainedTaskMountToken()
        let original = host.installOrdinary(mount: mount) { await probe.run("old") }
        original.deliver(restart: false)
        let oldReady = expectation(description: "Original Task installed its cancellation handler")
        probe.onReady = { if $0 == "old" { oldReady.fulfill() } }
        host.render()
        await fulfillment(of: [oldReady], timeout: 5)

        let cleanup = host.node.retainedTaskState().claimLazyPhysicalDeparture()
        var replacement: RetainedTaskDeclaration?
        probe.onCancellation = { label in
            guard label == "old" else { return }
            let next = host.installOrdinary(mount: mount) { await probe.run("new") }
            replacement = next
            next.deliver(restart: false)
        }
        cleanup.finish()
        XCTAssertEqual(probe.cancellations, ["old"])
        XCTAssertTrue(replacement?.canCommit == true)
        XCTAssertTrue(host.node.retainedTaskState().hasCommittedSlots)
        cleanup.finish()
        XCTAssertEqual(probe.cancellations, ["old"])

        // The ordinary path keeps its existing pending-disappearance gate.
        // This seam verifies slot survival, not a fabricated second appearance.
        XCTAssertTrue(replacement?.canCommit == true)
        XCTAssertTrue(host.node.retainedTaskState().hasCommittedSlots)
        XCTAssertEqual(probe.runs, ["old"])
        XCTAssertEqual(probe.cancellations, ["old"])
    }

    func testEveryMemberMustAcceptBothLifecycleFieldsBeforeTaskAssociation() async throws {
        let host = try LazyTaskGroupHost()
        defer { host.close() }
        let operation = try host.operation()
        let declaration = try operation.stage()
        XCTAssertFalse(declaration.canCommit)
        try operation.prepare()

        try operation.acceptMember(0)
        XCTAssertTrue(operation.accepted.isEmpty)
        XCTAssertFalse(declaration.canCommit)
        operation.prepareMember(1)
        try operation.copyAppear(1)
        XCTAssertTrue(operation.accepted.isEmpty)
        XCTAssertFalse(declaration.canCommit)

        try operation.copyDisappear(1)
        XCTAssertEqual(operation.accepted.count, 1)
        XCTAssertEqual(operation.accepted.first?.members.count, 2)
        XCTAssertTrue(declaration.canCommit)
    }

    func testAssociationIsPublishedBeforeTheLastOutgoingHookCaptureReleases() async throws {
        let host = try LazyTaskGroupHost()
        defer { host.close() }
        let operation = try host.operation()
        let declaration = try operation.stage()
        var observed: Bool?
        installLazyTaskOutgoingHook(on: host.members[1]) { observed = declaration.canCommit }
        try operation.prepare()
        try operation.acceptMember(0)
        operation.prepareMember(1)
        try operation.copyAppear(1)
        XCTAssertNil(observed)

        try operation.copyDisappear(1)

        XCTAssertEqual(observed, true)
        XCTAssertTrue(declaration.canCommit)
    }

    func testTwoGroupsSharingTheSameActualTargetsKeepIndependentAssociations() async throws {
        let host = try LazyTaskGroupHost()
        defer { host.close() }
        let operation = try host.operation()
        let first = try operation.stage()
        let second = try operation.stage()
        var firstWasCurrentWhenSecondAssociated = false
        operation.onAssociation = { id in
            if id === second.declarationID { firstWasCurrentWhenSecondAssociated = first.canCommit }
        }
        try operation.prepare()
        try operation.acceptAll()

        XCTAssertEqual(operation.accepted.count, 2)
        XCTAssertTrue(firstWasCurrentWhenSecondAssociated)
        XCTAssertTrue(first.canCommit)
        XCTAssertTrue(second.canCommit)
        first.deliver(restart: false)
        second.deliver(restart: false)
        let cleanups = host.claimGroups()
        XCTAssertEqual(cleanups.count, 2)
        for cleanup in cleanups { cleanup.finish() }
    }

    func testAcceptedSourceSubsetDoesNotDrainAnUnacceptedGroupsCandidates() async throws {
        let host = try LazyTaskGroupHost()
        defer { host.close() }
        let operation = try host.operation()
        let first = try operation.stage(indices: [0])
        let second = try operation.stage(indices: [1])
        try operation.prepare()
        try operation.acceptMember(0)

        XCTAssertTrue(first.canCommit)
        XCTAssertFalse(second.canCommit)
        XCTAssertTrue(operation.sources[0].retainedTaskState().lazyCandidateDeclarations().isEmpty)
        let remaining = operation.sources[1].retainedTaskState().lazyCandidateDeclarations().flatMap { $0.declarations }
        XCTAssertEqual(remaining.count, 1)
        XCTAssertTrue(remaining.first === second.declarationID)

        try operation.acceptMember(1)
        XCTAssertTrue(first.canCommit)
        XCTAssertTrue(second.canCommit)
    }

    func testRetainedAbandonedSourceDoesNotKeepTheCandidateActionAlive() async throws {
        let host = try LazyTaskGroupHost()
        defer { host.close() }
        let operation = try host.operation()
        var releases = 0

        try stageUnownedLazyTask(in: operation) { releases += 1 }

        XCTAssertEqual(releases, 1)
        XCTAssertEqual(operation.sources[0].retainedTaskState().lazyCandidateDeclarations().count, 1)
        operation.journal.revokeBeforeAbandon()
        operation.journal.releaseUnadoptedTransport()
        withExtendedLifetime(operation.sources) { XCTAssertEqual(releases, 1) }
    }

    func testRejectedManagedStageCannotFallBackToOrdinaryTransport() async throws {
        let host = try LazyTaskGroupHost(memberCount: 1)
        defer { host.close() }
        let operation = try host.operation()
        let attribution = try XCTUnwrap(operation.attribution)
        let group = try XCTUnwrap(attribution.registerGroup(kind: .scopedTask))
        _ = try XCTUnwrap(attribution.closeGroup(group))
        let declaration = RetainedTaskDeclaration(
            mount: RetainedTaskMountToken(), priority: .userInitiated, action: {},
            isMember: { true }, isCurrentProposal: { true })

        XCTAssertFalse(
            declaration.stage(
                groupSources: operation.sources, in: host.runtime, lazyAttribution: attribution, group: group))
        declaration.stage(on: operation.sources[0], in: host.runtime)
        operation.taskContext.associate(source: operation.sources[0], target: host.members[0])
        declaration.deliver(restart: false)

        XCTAssertFalse(declaration.canCommit)
        XCTAssertFalse(host.members[0].retainedTaskState().hasCommittedSlots)
        XCTAssertTrue(operation.sources[0].existingRetainedTaskState?.lazyCandidateDeclarations().isEmpty != false)
    }

    func testEmptyTaskGroupCannotBorrowAnUnrelatedStructuralAnchor() async throws {
        let host = try LazyTaskGroupHost(memberCount: 1)
        defer { host.close() }
        let operation = try host.operation(sourceCount: 0)
        let attribution = try XCTUnwrap(operation.attribution)
        let group = try XCTUnwrap(attribution.registerGroup(kind: .scopedTask))
        let proposal = try XCTUnwrap(attribution.closeGroup(group))
        try operation.prepare()
        let actual = host.members[0].lazyListActivityStorage().captureActualAttachment(
            of: host.members[0], in: host.runtime)

        XCTAssertNil(operation.journal.recordAcceptedEmpty(proposal, structuralAnchor: actual))

        XCTAssertTrue(operation.accepted.isEmpty)
        XCTAssertEqual(proposal.construction, .closedEmpty)
        XCTAssertTrue(proposal.declarations.isEmpty)
        XCTAssertNil(host.members[0].existingRetainedTaskState)
    }

    func testOneGroupCreatesOneTaskAfterAllMembersActuallyRender() async throws {
        let host = try LazyTaskGroupHost()
        let probe = LazyTaskRunProbe()
        defer {
            probe.onReady = nil
            host.close()
            probe.releaseAll()
        }
        let operation = try host.operation()
        let declaration = try operation.stage(action: { await probe.run("group") })
        try operation.prepare()
        try operation.acceptAll()
        declaration.deliver(restart: false)
        let ready = expectation(description: "The one group Task starts after the complete footprint renders")
        probe.onReady = { if $0 == "group" { ready.fulfill() } }

        host.render()
        await fulfillment(of: [ready], timeout: 5)
        host.render()
        for member in host.members { declaration.appear(on: member) }

        XCTAssertEqual(probe.runs, ["group"])
        XCTAssertTrue(probe.cancellations.isEmpty)
        host.close()
        XCTAssertEqual(probe.cancellations, ["group"])
    }

    func testRenderingOnlyTheFirstMemberDoesNotEvenCreateAnAsyncAttempt() async throws {
        let host = try LazyTaskGroupHost()
        defer { host.close() }
        host.members[1].isHidden = true
        let operation = try host.operation()
        var releases = 0
        try operation.installPendingAction { releases += 1 }
        host.render()
        XCTAssertTrue(host.members[0].hasAppeared)
        XCTAssertFalse(host.members[1].hasAppeared)
        XCTAssertEqual(releases, 0)

        let cleanups = host.claimGroups()
        XCTAssertEqual(cleanups.count, 1)
        for cleanup in cleanups { cleanup.finish() }

        // No suspension occurred: an admitted Task would still retain its action
        // until its first execution. This positive release proves no attempt.
        XCTAssertEqual(releases, 1)
        withExtendedLifetime(operation.sources) { XCTAssertEqual(releases, 1) }
    }

    func testCompatibleAcceptedReplacementPreservesTheOriginalAttempt() async throws {
        let host = try LazyTaskGroupHost()
        let probe = LazyTaskRunProbe()
        defer {
            probe.onReady = nil
            host.close()
            probe.releaseAll()
        }
        let mount = RetainedTaskMountToken()
        let previous = try host.operation()
        let old = try previous.stage(mount: mount, action: { await probe.run("old") })
        try previous.prepare()
        try previous.acceptAll()
        old.deliver(restart: false)
        let ready = expectation(description: "The original attempt is running")
        probe.onReady = { if $0 == "old" { ready.fulfill() } }
        host.render()
        await fulfillment(of: [ready], timeout: 5)
        let group = try XCTUnwrap(previous.accepted.first)

        let next = try host.operation(physical: group.contribution.receipt.physical)
        let replacement = try next.stage(mount: mount, action: { await probe.run("replacement") })
        try next.prepare()
        next.prepareMember(0)
        try next.copyAppear(0)
        let cleanup = try next.claimAbsence(of: group)
        XCTAssertFalse(old.canCommit)
        XCTAssertFalse(replacement.canCommit)
        try next.copyDisappear(0)
        try next.acceptMember(1)
        XCTAssertTrue(replacement.canCommit)
        replacement.deliver(restart: false)
        next.journal.finishAcceptedTaskCleanup()

        XCTAssertTrue(cleanup.isFinished)
        XCTAssertEqual(probe.runs, ["old"])
        XCTAssertTrue(probe.cancellations.isEmpty)
        for cleanup in host.claimGroups() { cleanup.finish() }
        XCTAssertEqual(probe.cancellations, ["old"])
    }

    func testChangedTaskDecisionRestartsOnceOnTheSamePhysicalFootprint() async throws {
        let host = try LazyTaskGroupHost()
        let probe = LazyTaskRunProbe()
        defer {
            probe.onReady = nil
            host.close()
            probe.releaseAll()
        }
        let mount = RetainedTaskMountToken()
        let previous = try host.operation()
        let old = try previous.stage(mount: mount, action: { await probe.run("old") })
        try previous.prepare()
        try previous.acceptAll()
        old.deliver(restart: false)
        let oldReady = expectation(description: "The original group task is ready")
        probe.onReady = { if $0 == "old" { oldReady.fulfill() } }
        host.render()
        await fulfillment(of: [oldReady], timeout: 5)
        let group = try XCTUnwrap(previous.accepted.first)

        let next = try host.operation(physical: group.contribution.receipt.physical)
        let replacement = try next.stage(mount: mount, action: { await probe.run("new") })
        try next.prepare()
        let cleanup = try next.claimAbsence(of: group)
        try next.acceptAll()
        let newReady = expectation(description: "The changed decision starts one replacement")
        probe.onReady = { if $0 == "new" { newReady.fulfill() } }
        replacement.deliver(restart: true)
        replacement.deliver(restart: true)
        next.journal.finishAcceptedTaskCleanup()
        await fulfillment(of: [newReady], timeout: 5)

        XCTAssertTrue(cleanup.isFinished)
        XCTAssertEqual(probe.runs, ["old", "new"])
        XCTAssertEqual(probe.cancellations, ["old"])
    }

    func testPartialReplacementStillFinishesItsAdmittedOriginalCleanup() async throws {
        let host = try LazyTaskGroupHost()
        let probe = LazyTaskRunProbe()
        defer {
            probe.onReady = nil
            host.close()
            probe.releaseAll()
        }
        let mount = RetainedTaskMountToken()
        let previous = try host.operation()
        let old = try previous.stage(mount: mount, action: { await probe.run("old") })
        try previous.prepare()
        try previous.acceptAll()
        old.deliver(restart: false)
        let ready = expectation(description: "The old Task is ready for partial replacement")
        probe.onReady = { if $0 == "old" { ready.fulfill() } }
        host.render()
        await fulfillment(of: [ready], timeout: 5)
        let group = try XCTUnwrap(previous.accepted.first)

        let next = try host.operation(physical: group.contribution.receipt.physical)
        let replacement = try next.stage(mount: mount, action: { await probe.run("unaccepted") })
        try next.prepare()
        next.prepareMember(0)
        try next.copyAppear(0)
        let cleanup = try next.claimAbsence(of: group)
        XCTAssertFalse(old.canCommit)
        XCTAssertFalse(replacement.canCommit)
        host.epoch.canComplete = false
        replacement.deliver(restart: true)
        next.journal.finishAcceptedTaskCleanup()

        XCTAssertTrue(cleanup.isFinished)
        XCTAssertEqual(probe.runs, ["old"])
        XCTAssertEqual(probe.cancellations, ["old"])
        XCTAssertTrue(next.accepted.isEmpty)
    }

    func testForestDepartureRevokesBeforeHooksAndCancelsAfterAllMemberHooks() async throws {
        let host = try LazyTaskGroupHost()
        let probe = LazyTaskRunProbe()
        defer {
            probe.onReady = nil
            probe.onCancellation = nil
            host.close()
            probe.releaseAll()
        }
        let operation = try host.operation()
        let declaration = try operation.stage(action: { await probe.run("group") })
        try operation.prepare()
        try operation.acceptAll()
        declaration.deliver(restart: false)
        let ready = expectation(description: "A group task exists before physical departure")
        probe.onReady = { if $0 == "group" { ready.fulfill() } }
        host.render()
        await fulfillment(of: [ready], timeout: 5)
        var order: [String] = []
        for (index, member) in host.members.enumerated() {
            member.onDisappear = {
                XCTAssertFalse(declaration.canCommit)
                order.append("hook\(index)")
            }
        }
        probe.onCancellation = { _ in order.append("cancel") }

        host.runtime.root.removeAllChildren()

        XCTAssertEqual(order, ["hook0", "hook1", "cancel"])
        XCTAssertEqual(probe.cancellations, ["group"])
        XCTAssertTrue(host.row.isDeclared)
    }

    func testReturningAttachmentGetsANewAttemptWhileLogicalMembershipSurvives() async throws {
        let host = try LazyTaskGroupHost()
        let probe = LazyTaskRunProbe()
        defer {
            probe.onReady = nil
            host.close()
            probe.releaseAll()
        }
        let mount = RetainedTaskMountToken()
        let previous = try host.operation()
        let old = try previous.stage(mount: mount, action: { await probe.run("old") })
        try previous.prepare()
        try previous.acceptAll()
        old.deliver(restart: false)
        let oldReady = expectation(description: "Original physical generation starts")
        probe.onReady = { if $0 == "old" { oldReady.fulfill() } }
        host.render()
        await fulfillment(of: [oldReady], timeout: 5)
        let oldPhysical = try XCTUnwrap(previous.accepted.first?.contribution.receipt.physical)
        host.runtime.root.removeAllChildren()
        XCTAssertEqual(probe.cancellations, ["old"])
        XCTAssertTrue(host.row.isDeclared)
        for member in host.members { host.runtime.root.addChild(member) }

        let next = try host.operation()
        let replacement = try next.stage(mount: mount, action: { await probe.run("return") })
        try next.prepare()
        try next.acceptAll()
        let physical = try XCTUnwrap(next.accepted.first?.contribution.receipt.physical)
        XCTAssertFalse(oldPhysical.id === physical.id)
        replacement.deliver(restart: false)
        let newReady = expectation(description: "Returned physical generation starts a fresh Task")
        probe.onReady = { if $0 == "return" { newReady.fulfill() } }
        host.render()
        await fulfillment(of: [newReady], timeout: 5)

        XCTAssertEqual(probe.runs, ["old", "return"])
        XCTAssertFalse(old.canCommit)
        XCTAssertTrue(replacement.canCommit)
    }

    func testDescriptorTaskLifetimeDoesNotDependOnItsFinishedBuildScope() async throws {
        let host = try LazyTaskGroupHost()
        let probe = LazyTaskRunProbe()
        defer {
            probe.onReady = nil
            host.close()
            probe.releaseAll()
        }
        let operation = try host.operation(descriptor: true)
        let declaration = try operation.stage(action: { await probe.run("descriptor") })
        try operation.prepare()
        try operation.acceptAll()
        XCTAssertEqual(operation.acceptedDescriptor.count, 1)
        operation.finish()
        XCTAssertFalse(operation.scope.canConstructDescriptors)
        XCTAssertTrue(declaration.canCommit)
        declaration.deliver(restart: false)
        let ready = expectation(description: "A durable ordinary descriptor Task starts after build finish")
        probe.onReady = { if $0 == "descriptor" { ready.fulfill() } }

        host.render()
        await fulfillment(of: [ready], timeout: 5)

        XCTAssertEqual(probe.runs, ["descriptor"])
        XCTAssertTrue(declaration.canCommit)
    }

    func testGroupPendingActionReleasesInsideTheCapturedFullTransaction() async throws {
        let host = try LazyTaskGroupHost()
        defer { host.close() }
        let operation = try host.operation()
        var snapshot: LazyTaskTransactionSnapshot?
        try operation.installPendingAction { snapshot = LazyTaskTransactionSnapshot() }
        let cleanups = host.claimGroups()
        XCTAssertEqual(cleanups.count, 1)
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        transaction.isContinuous = true
        transaction.scrollTargetAnchor = .bottom
        transaction.tracksVelocity = true
        let captured = withTransaction(transaction) { RetainedBuildTransaction() }

        withTransaction(Transaction(animation: .linear(duration: 9))) {
            captured.perform { for cleanup in cleanups { cleanup.finish() } }
            XCTAssertEqual(currentTransaction?.animation?.duration, 9)
            XCTAssertEqual(currentAnimationTransaction?.duration, 9)
        }

        let observed = try XCTUnwrap(snapshot)
        XCTAssertNotNil(observed.transaction)
        XCTAssertNil(observed.transaction?.animation)
        XCTAssertEqual(observed.transaction?.disablesAnimations, true)
        XCTAssertEqual(observed.transaction?.isContinuous, true)
        XCTAssertEqual(observed.transaction?.scrollTargetAnchor, .bottom)
        XCTAssertEqual(observed.transaction?.tracksVelocity, true)
        XCTAssertNil(observed.animationDuration)
    }

    func testGroupCleanupDoesNotCancelAReentrantSameMountReplacement() async throws {
        let host = try LazyTaskGroupHost()
        let probe = LazyTaskRunProbe()
        defer {
            probe.onReady = nil
            probe.onCancellation = nil
            host.close()
            probe.releaseAll()
        }
        let mount = RetainedTaskMountToken()
        let previous = try host.operation()
        let old = try previous.stage(mount: mount, action: { await probe.run("old") })
        try previous.prepare()
        try previous.acceptAll()
        old.deliver(restart: false)
        let oldReady = expectation(description: "Old group Task is ready before cleanup reentry")
        probe.onReady = { if $0 == "old" { oldReady.fulfill() } }
        host.render()
        await fulfillment(of: [oldReady], timeout: 5)
        let physical = try XCTUnwrap(previous.accepted.first?.contribution.receipt.physical)
        let cleanup = try XCTUnwrap(host.claimGroups().first)
        let newReady = expectation(description: "Reentrant replacement survives original cleanup")
        probe.onReady = { if $0 == "new" { newReady.fulfill() } }
        var replacementOperation: LazyTaskGroupOperation?
        var replacement: RetainedTaskDeclaration?
        probe.onCancellation = { label in
            guard label == "old" else { return }
            do {
                let next = try host.operation(physical: physical)
                let declaration = try next.stage(mount: mount, action: { await probe.run("new") })
                try next.prepare()
                try next.acceptAll()
                replacementOperation = next
                replacement = declaration
                declaration.deliver(restart: false)
            } catch {
                XCTFail("Reentrant native association failed: \(error)")
            }
        }

        cleanup.finish()
        cleanup.finish()
        XCTAssertTrue(replacement?.canCommit == true)
        XCTAssertEqual(probe.cancellations, ["old"])
        await fulfillment(of: [newReady], timeout: 5)

        XCTAssertEqual(probe.runs, ["old", "new"])
        XCTAssertEqual(probe.cancellations, ["old"])
        withExtendedLifetime(replacementOperation) {}
    }

    func testOneMountTokenCannotAliasAcceptedGroupsInDifferentRuntimes() async throws {
        let firstHost = try LazyTaskGroupHost(memberCount: 1)
        let secondHost = try LazyTaskGroupHost(memberCount: 1)
        defer {
            firstHost.close()
            secondHost.close()
        }
        let mount = RetainedTaskMountToken()
        let first = try firstHost.operation()
        let firstDeclaration = try first.stage(mount: mount)
        let second = try secondHost.operation()
        let secondDeclaration = try second.stage(mount: mount)
        try first.prepare()
        try first.acceptAll()
        try second.prepare()
        try second.acceptAll()
        XCTAssertTrue(firstDeclaration.canCommit)
        XCTAssertTrue(secondDeclaration.canCommit)

        for cleanup in firstHost.claimGroups() { cleanup.finish() }

        XCTAssertFalse(firstDeclaration.canCommit)
        XCTAssertTrue(secondDeclaration.canCommit)
    }

    func testManagedGroupDepartureRevokesItsZeroSlotAssociation() async throws {
        let host = try LazyTaskGroupHost()
        defer { host.close() }
        let operation = try host.operation()
        let declaration = try operation.stage()
        try operation.prepare()
        try operation.acceptAll()
        XCTAssertTrue(declaration.canCommit)
        XCTAssertTrue(host.members.allSatisfy { !$0.retainedTaskState().hasCommittedSlots })

        let cleanups = host.claimGroups()

        XCTAssertEqual(cleanups.count, 1)
        XCTAssertFalse(declaration.canCommit)
        declaration.deliver(restart: false)
        for member in host.members { declaration.appear(on: member) }
        XCTAssertTrue(host.claimGroups().isEmpty)
        for cleanup in cleanups { cleanup.finish() }
        XCTAssertTrue(cleanups.allSatisfy(\.isFinished))
    }

    func testLogicalRevocationPreventsPendingTaskAdmissionWithoutDetachingNodes() async throws {
        let host = try LazyTaskGroupHost()
        defer { host.close() }
        let operation = try host.operation()
        var releases = 0
        try operation.installPendingAction { releases += 1 }
        let receipt = try XCTUnwrap(operation.accepted.first?.contribution.receipt)
        XCTAssertTrue(receipt.isActive)

        host.logical.revokeLogicalMembership()
        host.render()
        XCTAssertFalse(host.row.isDeclared)
        XCTAssertFalse(receipt.isActive)
        XCTAssertEqual(host.runtime.root.children.count, 2)
        for cleanup in host.claimGroups() { cleanup.finish() }

        // No async turn is needed to release an action that was never admitted.
        XCTAssertEqual(releases, 1)
        XCTAssertNil(host.logical.proposeMembership(id: host.row.id))
    }

    func testManagedAssociationDoesNotRotateTheOrdinaryNodeAssociation() async throws {
        let host = try LazyTaskGroupHost(memberCount: 1)
        defer { host.close() }
        let operation = try host.operation()
        let managed = try operation.stage()
        let ordinary = RetainedTaskDeclaration(
            mount: RetainedTaskMountToken(), priority: .userInitiated, action: {},
            isMember: { true }, isCurrentProposal: { true })
        ordinary.stage(on: operation.sources[0], in: host.runtime)
        operation.taskContext.associate(source: operation.sources[0], target: host.members[0])
        XCTAssertTrue(ordinary.canCommit)
        XCTAssertFalse(managed.canCommit)
        try operation.prepare()
        try operation.acceptAll()

        XCTAssertTrue(ordinary.canCommit)
        XCTAssertTrue(managed.canCommit)
        for cleanup in host.claimGroups() { cleanup.finish() }
        XCTAssertTrue(ordinary.canCommit)
        XCTAssertFalse(managed.canCommit)
    }

}

@MainActor
private final class LazyTaskTransportEpoch: RetainedBuildEpoch {
    var canAdopt = true
    var canComplete = true
    func supersede() { canAdopt = false }
    func willAdopt() -> Bool { canAdopt }
    func commit() {}
    func abandon() { canAdopt = false }
    func finishAfterCallbacks() {}
}

@MainActor
private final class LazyTaskTransportHost {
    let runtime: RetainedViewRuntime
    let node: ViewNode
    let epoch: LazyTaskTransportEpoch
    let taskContext: RetainedTaskAdoptionContext
    private var isClosed = false

    init() {
        runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 120, height: 80)))
        node = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 20))
        epoch = LazyTaskTransportEpoch()
        taskContext = RetainedTaskAdoptionContext(
            runtime: runtime, epoch: epoch, transaction: RetainedBuildTransaction())
        runtime.root.addChild(node)
    }

    func installOrdinary(
        mount: RetainedTaskMountToken? = nil, action: @escaping @Sendable () async -> Void = {}
    ) -> RetainedTaskDeclaration {
        let declaration = RetainedTaskDeclaration(
            mount: mount ?? RetainedTaskMountToken(), priority: .userInitiated, action: action,
            isMember: { true }, isCurrentProposal: { true })
        declaration.stage(on: node, in: runtime)
        taskContext.associate(source: node, target: node)
        return declaration
    }

    @inline(never)
    func claimPendingAction(onRelease: @escaping @MainActor () -> Void) -> RetainedLazyListAcceptedTaskCleanup {
        let token = LazyTaskReleaseToken(onRelease: onRelease)
        let declaration = installOrdinary { withExtendedLifetime(token) {} }
        declaration.deliver(restart: false)
        return node.retainedTaskState().claimLazyPhysicalDeparture()
    }

    func render() { _ = runtime.renderScene() }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        runtime.stopRenderLifecycleCallbacks()
        epoch.canAdopt = false
        epoch.canComplete = false
        runtime.cancelRenderLifecycleTasks()
        runtime.root.removeAllChildren()
    }
}

private final class LazyTaskReleaseToken: @unchecked Sendable {
    private let onRelease: @MainActor () -> Void

    init(onRelease: @escaping @MainActor () -> Void) { self.onRelease = onRelease }

    deinit {
        // Only the synchronous MainActor cleanup scopes in these fixtures own
        // this pending, never-started action's final reference.
        MainActor.assumeIsolated { onRelease() }
    }
}

@MainActor
private struct LazyTaskTransactionSnapshot {
    let transaction = currentTransaction
    let animationDuration = currentAnimationTransaction?.duration
    let animationEasing = currentAnimationTransaction?.easing
}

@MainActor
private final class LazyTaskRunProbe {
    private(set) var runs: [String] = []
    private(set) var cancellations: [String] = []
    var onReady: ((String) -> Void)?
    var onCancellation: ((String) -> Void)?
    private var continuations: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var wasReleased = false

    func run(_ label: String) async {
        runs.append(label)
        await withTaskCancellationHandler(
            operation: {
                await withCheckedContinuation { continuation in
                    if Task.isCancelled || cancellations.contains(label) {
                        cancel(label)
                        continuation.resume()
                    } else if wasReleased {
                        continuation.resume()
                    } else {
                        continuations[label, default: []].append(continuation)
                    }
                    onReady?(label)
                }
            },
            onCancel: { [weak self] in
                MainActor.assumeIsolated { self?.cancel(label) }
            })
    }

    private func cancel(_ label: String) {
        guard !cancellations.contains(label) else { return }
        cancellations.append(label)
        let pending = continuations.removeValue(forKey: label) ?? []
        onCancellation?(label)
        for continuation in pending { continuation.resume() }
    }

    func releaseAll() {
        wasReleased = true
        let pending = continuations.values.flatMap { $0 }
        continuations.removeAll()
        for continuation in pending { continuation.resume() }
    }
}

/// Uses native writer notifications with real retained attachments. This fixture
/// tests the transport seam; it does not claim a ComponentHost adopted a tree.
@MainActor
private final class LazyTaskGroupHost {
    let runtime: RetainedViewRuntime
    let members: [ViewNode]
    let epoch = LazyTaskTransportEpoch()
    let logical: RetainedLazyListLogicalMembershipScope
    let row: RetainedLazyListLogicalMembershipReceipt
    let provider: RetainedLazyListDataSource<Int, Int>
    let request: RetainedLazyListRowRequest
    private var isClosed = false

    init(memberCount: Int = 2) throws {
        let root = ViewNode(frame: Rect(x: 0, y: 0, width: 120, height: 100))
        let runtime = RetainedViewRuntime(root: root)
        let members = (0..<memberCount).map { index in
            ViewNode(frame: Rect(x: 0, y: Double(index * 25), width: 100, height: 20))
        }
        for member in members { root.addChild(member) }
        let scope = RetainedLazyListDescriptorBuildScope(
            origin: .componentHostRoot, hostLifetime: runtime.lazyListLogicalHostLifetime,
            ownerLifetime: root.lazyListActivityStorage().descriptorOwnerLifetime)
        let logical = try XCTUnwrap(RetainedLazyListLogicalMembershipScope(in: scope, parentRow: nil))
        let row = try XCTUnwrap(logical.proposeMembership(id: RetainedLazyListMembershipID()))
        let provider = RetainedLazyListDataSource<Int, Int>()
        XCTAssertTrue(provider.replaceData([0], id: \.self, rowContent: { $0 }))
        let metadata = try XCTUnwrap(provider.metadata)
        let token = try XCTUnwrap(metadata.rows.first?.token)
        let request = try XCTUnwrap(provider.request(for: token))

        let descriptorSource = ViewNode()
        let binding = RetainedLazyListManagedLogicalDescriptorBinding(
            descriptor: RetainedLazyListLogicalDeclarationID(), facadeProposal: RetainedLazyListLogicalProposalID(),
            scope: logical, sourceGeneration: metadata.generation)
        let journal = RetainedLazyListAdoptionJournal(descriptorScope: scope, transaction: RetainedBuildTransaction())
        let facet = try XCTUnwrap(journal.registerSourceDescriptor(binding, on: descriptorSource, scope: scope))
        let preparation = try XCTUnwrap(journal.preparation())
        let plan = try XCTUnwrap(
            RetainedLazyListLogicalMembershipPlan(
                descriptor: binding.descriptor, facadeProposal: binding.facadeProposal,
                expected: logical.snapshot(), sourceGeneration: metadata.generation,
                introduced: [row], retained: [], deleted: []))
        XCTAssertTrue(
            journal.beginAdoption(
                preparation,
                preparedActivity: RetainedLazyListPreparedActivity(
                    preparation: preparation, logicalMembershipPlans: [plan])))
        let actual = root.lazyListActivityStorage().captureActualAttachment(of: root, in: runtime)
        let publication = try XCTUnwrap(journal.prepareLogicalDescriptorPublication(source: facet, actual: actual))
        XCTAssertTrue(journal.markMutationStarted())
        _ = try XCTUnwrap(journal.recordAcceptedLogicalDeclaration(publication))
        _ = journal.seal(completedCheckedAdoption: true)
        scope.finish()
        XCTAssertTrue(row.isDeclared)
        withExtendedLifetime(descriptorSource) {}
        self.runtime = runtime
        self.members = members
        self.logical = logical
        self.row = row
        self.provider = provider
        self.request = request
    }

    func operation(
        descriptor: Bool = false, physical: RetainedLazyListPhysicalActivityReceipt? = nil,
        sourceCount: Int? = nil
    ) throws -> LazyTaskGroupOperation {
        try LazyTaskGroupOperation(
            host: self, descriptor: descriptor, physical: physical, sourceCount: sourceCount ?? members.count)
    }

    func render() { _ = runtime.renderScene() }

    func claimGroups() -> [RetainedLazyListAcceptedTaskCleanup] {
        members.flatMap { $0.existingRetainedTaskState?.claimLazyGroupTaskDepartures() ?? [] }
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        runtime.stopRenderLifecycleCallbacks()
        epoch.canAdopt = false
        epoch.canComplete = false
        logical.revokeLogicalMembership()
        runtime.cancelRenderLifecycleTasks()
        runtime.root.removeAllChildren()
    }
}

@MainActor
private final class LazyTaskGroupOperation {
    let host: LazyTaskGroupHost
    let scope: RetainedLazyListDescriptorBuildScope
    let journal: RetainedLazyListAdoptionJournal
    let taskContext: RetainedTaskAdoptionContext
    let attribution: RetainedLazyListBuildAttribution?
    let descriptorAttribution: RetainedDescriptorComponentAttribution?
    let sources: [ViewNode]
    private(set) var accepted: [RetainedLazyListAcceptedTaskGroup] = []
    private(set) var acceptedDescriptor: [RetainedDescriptorAcceptedTaskGroup] = []
    var onAssociation: ((RetainedTaskDeclarationID) -> Void)?

    init(
        host: LazyTaskGroupHost, descriptor: Bool, physical: RetainedLazyListPhysicalActivityReceipt?,
        sourceCount: Int
    ) throws {
        self.host = host
        let scope = RetainedLazyListDescriptorBuildScope(
            origin: .componentHostRoot, hostLifetime: host.runtime.lazyListLogicalHostLifetime,
            ownerLifetime: host.runtime.root.lazyListActivityStorage().descriptorOwnerLifetime)
        self.scope = scope
        let transaction = RetainedBuildTransaction()
        let journal = RetainedLazyListAdoptionJournal(descriptorScope: scope, transaction: transaction)
        self.journal = journal
        taskContext = RetainedTaskAdoptionContext(runtime: host.runtime, epoch: host.epoch, transaction: transaction)
        sources = (0..<sourceCount).map { _ in ViewNode() }
        if descriptor {
            descriptorAttribution = try XCTUnwrap(scope.registerOrdinaryComponent())
            attribution = nil
        } else {
            descriptorAttribution = nil
            attribution = RetainedLazyListBuildAttribution(
                journal: journal, rowRequest: host.request, logicalMembership: host.row,
                physical: physical ?? RetainedLazyListPhysicalActivityReceipt(membership: host.row.id),
                component: RetainedLazyListComponentID(), resolutionID: RetainedLazyListRowResolutionID(),
                origin: .selectedRow)
        }
    }

    func stage(
        mount: RetainedTaskMountToken? = nil, indices: [Int]? = nil,
        action: @escaping @Sendable () async -> Void = {},
        isMember: @escaping @MainActor () -> Bool = { true },
        isCurrentProposal: @escaping @MainActor () -> Bool = { true }
    ) throws -> RetainedTaskDeclaration {
        let selected = (indices ?? Array(sources.indices)).map { sources[$0] }
        let declaration = RetainedTaskDeclaration(
            mount: mount ?? RetainedTaskMountToken(), priority: .userInitiated, action: action,
            isMember: isMember, isCurrentProposal: isCurrentProposal)
        if let attribution {
            let group = try XCTUnwrap(attribution.registerGroup(kind: .scopedTask))
            XCTAssertTrue(
                declaration.stage(
                    groupSources: selected, in: host.runtime, lazyAttribution: attribution, group: group))
            installHooks(for: declaration, on: selected)
            _ = try XCTUnwrap(attribution.closeGroup(group))
        } else {
            let attribution = try XCTUnwrap(descriptorAttribution)
            let group = try XCTUnwrap(attribution.registerGroup(kind: .scopedTask))
            XCTAssertTrue(
                declaration.stage(
                    groupSources: selected, in: host.runtime, descriptorAttribution: attribution, group: group))
            installHooks(for: declaration, on: selected)
            _ = try XCTUnwrap(attribution.closeGroup(group))
        }
        return declaration
    }

    private func installHooks(for declaration: RetainedTaskDeclaration, on nodes: [ViewNode]) {
        for node in nodes {
            let appear = node.onAppearWithNode
            node.onAppearWithNode = { [weak declaration] actual in
                appear?(actual)
                declaration?.appear(on: actual)
            }
            let disappear = node.onDisappearWithNode
            node.onDisappearWithNode = { [weak declaration] actual in
                disappear?(actual)
                declaration?.disappear(from: actual)
            }
        }
    }

    func prepare() throws {
        let preparation = try XCTUnwrap(journal.preparation())
        XCTAssertTrue(
            journal.beginAdoption(
                preparation,
                preparedActivity: RetainedLazyListPreparedActivity(preparation: preparation, logicalMembershipPlans: [])
            ))
        XCTAssertTrue(journal.markMutationStarted())
    }

    func prepareMember(_ index: Int) {
        let source = sources[index]
        let target = host.members[index]
        let lazyIDs = source.existingRetainedTaskState?.lazyCandidateDeclarations().flatMap { $0.declarations } ?? []
        accept(journal.recordAcceptedTaskDeclarationTransport(from: source, to: target, declarationIDs: lazyIDs))
        let ordinaryIDs =
            source.existingRetainedTaskState?.descriptorCandidateDeclarations().flatMap { $0.declarations } ?? []
        journal.recordAcceptedDescriptorTaskDeclarationTransport(
            from: source, to: target, declarationIDs: ordinaryIDs)
        accept(journal.recordAcceptedAttachment(from: source, to: target))
    }

    func copyAppear(_ index: Int) throws {
        try copy(\ViewNode.onAppearWithNode, from: sources[index], to: host.members[index])
    }

    func copyDisappear(_ index: Int) throws {
        try copy(\ViewNode.onDisappearWithNode, from: sources[index], to: host.members[index])
    }

    func acceptMember(_ index: Int) throws {
        prepareMember(index)
        try copyAppear(index)
        try copyDisappear(index)
    }

    func acceptAll() throws {
        for index in sources.indices { try acceptMember(index) }
    }

    @inline(never)
    private func copy<Value>(
        _ keyPath: ReferenceWritableKeyPath<ViewNode, Value>, from source: ViewNode, to target: ViewNode
    ) throws {
        XCTAssertTrue(journal.preparePropertyCopy(from: source, to: target, keyPath: keyPath))
        let previous = target[keyPath: keyPath]
        target[keyPath: keyPath] = source[keyPath: keyPath]
        accept(journal.recordAcceptedProperty(from: source, to: target, keyPath: keyPath))
        withExtendedLifetime(previous) {}
    }

    private func accept(_ groups: [RetainedLazyListAcceptedTaskGroup]) {
        for group in groups {
            accepted.append(group)
            XCTAssertTrue(taskContext.associateLazyAccepted(group, journal: journal))
            for declaration in group.declarationIDs { onAssociation?(declaration) }
        }
        for group in journal.takeAcceptedDescriptorTaskGroups() {
            acceptedDescriptor.append(group)
            XCTAssertTrue(taskContext.associateDescriptorAccepted(group, journal: journal))
            for declaration in group.declarationIDs { onAssociation?(declaration) }
        }
    }

    @inline(never)
    func installPendingAction(
        mount: RetainedTaskMountToken? = nil, onRelease: @escaping @MainActor () -> Void
    ) throws {
        let token = LazyTaskReleaseToken(onRelease: onRelease)
        let declaration = try stage(mount: mount, action: { withExtendedLifetime(token) {} })
        try prepare()
        try acceptAll()
        declaration.deliver(restart: false)
    }

    func claimAbsence(of group: RetainedLazyListAcceptedTaskGroup) throws -> RetainedLazyListAcceptedTaskCleanup {
        let member = try XCTUnwrap(group.members.first)
        let node = try XCTUnwrap(member.actual.node)
        let absence = RetainedLazyListAcceptedAbsence(
            previous: group.contribution.receipt, actual: member.actual,
            removalFacets: group.contribution.acceptedFacets, cleanup: RetainedLazyListCleanupID())
        journal.recordAcceptedAbsence(absence)
        let cleanup = node.retainedTaskState().claimLazyAcceptedAbsence(absence, declarationIDs: group.declarationIDs)
        journal.claimTaskCleanup(cleanup)
        return cleanup
    }

    func finish() {
        _ = journal.seal(completedCheckedAdoption: true)
        journal.finishAcceptedTaskCleanup()
        journal.releaseUnadoptedTransport()
        scope.finish()
    }
}

@MainActor
@inline(never)
private func installLazyTaskOutgoingHook(on node: ViewNode, onRelease: @escaping @MainActor () -> Void) {
    let token = LazyTaskReleaseToken(onRelease: onRelease)
    node.onDisappearWithNode = { _ in withExtendedLifetime(token) {} }
}

@MainActor
@inline(never)
private func stageUnownedLazyTask(
    in operation: LazyTaskGroupOperation, onRelease: @escaping @MainActor () -> Void
) throws {
    let token = LazyTaskReleaseToken(onRelease: onRelease)
    let declaration = try operation.stage(action: { withExtendedLifetime(token) {} })
    withExtendedLifetime(declaration) {}
}
