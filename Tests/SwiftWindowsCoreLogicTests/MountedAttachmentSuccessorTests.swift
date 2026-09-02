import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// The kernels use original forest captures and the production native writers.
/// The public-removal controls use real journal adoption and running Tasks.
/// None of these cases forces ARC reentry inside the storage-revocation prefix.
@MainActor
final class MountedAttachmentSuccessorTests: XCTestCase {
    func testK1NativeRevokeWithoutActivityStorageReturnsItsKnownSuccessor() async throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let node = ViewNode()
        runtime.root.addChild(node)
        XCTAssertNil(node.retainedLazyListActivityStorage)
        let ordinary = node.captureLazyListAttachmentProof()
        let departure = RetainedTaskPhysicalDeparture(roots: [node])
        let continuation = try originalContinuation(for: node, from: departure)
        let write = try XCTUnwrap(continuation.prepareRevoke())

        XCTAssertTrue(ordinary.isCurrent)
        XCTAssertTrue(continuation.isCurrent)
        XCTAssertFalse(continuation.hasEnteredInitialRevoke)
        let result = try XCTUnwrap(node.revokeLazyListAttachmentProofs(removalWrite: write))

        XCTAssertTrue(result.isCurrent)
        XCTAssertTrue(continuation.isCurrent)
        XCTAssertTrue(continuation.hasEnteredInitialRevoke)
        XCTAssertFalse(continuation.hasRefusedWrite)
        XCTAssertFalse(ordinary.isCurrent)
        XCTAssertTrue(node.parent === runtime.root)
        XCTAssertTrue(node.retainedLazyListRuntime === runtime)
        XCTAssertNil(node.retainedLazyListActivityStorage)
    }

    func testK1AcceptedStorageRotationLeavesTheOriginalRuntimePredecessorUsable() async throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let node = ViewNode()
        node.retainedViewIdentity = RetainedViewIdentity().appending(.slot(1))
        let accepted = try publishOrdinaryMember(node, in: runtime)
        XCTAssertTrue(accepted.hasDeclaredComponent)
        let storage = try XCTUnwrap(node.retainedLazyListActivityStorage)
        let actual = storage.captureActualAttachment(of: node, in: runtime)
        let ordinary = node.captureLazyListAttachmentProof()
        let departure = RetainedTaskPhysicalDeparture(roots: [node])
        let continuation = try originalContinuation(for: node, from: departure)
        let write = try XCTUnwrap(continuation.prepareRevoke())
        XCTAssertTrue(actual.isAttached)

        // This is the real S-only rotation. R's predecessor does not consult S
        // or Actual, and preparation has not performed the runtime-token write.
        storage.revokeAttachment()
        XCTAssertFalse(actual.isAttached)
        XCTAssertTrue(accepted.hasDeclaredComponent)
        XCTAssertTrue(ordinary.isCurrent)
        XCTAssertTrue(continuation.isCurrent)
        XCTAssertFalse(continuation.hasEnteredInitialRevoke)

        let result = try XCTUnwrap(node.revokeLazyListAttachmentProofs(removalWrite: write))
        XCTAssertTrue(result.isCurrent)
        XCTAssertTrue(continuation.isCurrent)
        XCTAssertTrue(continuation.hasEnteredInitialRevoke)
        XCTAssertFalse(continuation.hasRefusedWrite)
        XCTAssertFalse(ordinary.isCurrent)
        XCTAssertFalse(actual.isAttached)
        XCTAssertTrue(node.parent === runtime.root)
        XCTAssertTrue(node.retainedLazyListRuntime === runtime)
    }

    func testK2PreparedRevokeRefusesAfterPublicDetachAndSameParentReattachment() async throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let node = ViewNode()
        runtime.root.addChild(node)
        let departure = RetainedTaskPhysicalDeparture(roots: [node])
        let continuation = try originalContinuation(for: node, from: departure)
        let write = try XCTUnwrap(continuation.prepareRevoke())

        runtime.root.removeChild(node)
        runtime.root.addChild(node)
        XCTAssertTrue(node.parent === runtime.root)
        XCTAssertTrue(node.retainedLazyListRuntime === runtime)
        XCTAssertFalse(continuation.isCurrent)

        // A refusal does not suppress the baseline native revoke. The oracle
        // is lack of acknowledgement, not preservation of a later attachment.
        XCTAssertNil(node.revokeLazyListAttachmentProofs(removalWrite: write))
        XCTAssertTrue(continuation.hasRefusedWrite)
        XCTAssertFalse(continuation.hasEnteredInitialRevoke)
        runtime.root.removeChild(node)
        runtime.root.addChild(node)
        XCTAssertNil(continuation.prepareRevoke())
        XCTAssertNil(continuation.prepareParentNil())
        XCTAssertFalse(continuation.isCurrent)
    }

    func testK3PreparedParentNilCannotImportAnAttachmentAfterItsOwnRevoke() async throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let node = ViewNode()
        runtime.root.addChild(node)
        let departure = RetainedTaskPhysicalDeparture(roots: [node])
        let continuation = try originalContinuation(for: node, from: departure)
        let revoke = try XCTUnwrap(continuation.prepareRevoke())
        let originalResult = try XCTUnwrap(node.revokeLazyListAttachmentProofs(removalWrite: revoke))
        let parentNil = try XCTUnwrap(continuation.prepareParentNil())
        XCTAssertTrue(originalResult.isCurrent)

        runtime.root.removeChild(node)
        runtime.root.addChild(node)
        XCTAssertFalse(originalResult.isCurrent)
        XCTAssertNil(node.writeRemovalParentNil(removalWrite: parentNil))
        XCTAssertTrue(continuation.hasRefusedWrite)
        XCTAssertNil(node.parent, "The generic parent write still runs when metadata refuses")
        XCTAssertNil(node.revokeLazyListAttachmentProofs(removalWrite: revoke))
        XCTAssertNil(continuation.prepareRuntimeNil())
        XCTAssertFalse(originalResult.isCurrent)
    }

    func testK3PreparedRuntimeNilCannotImportAnAttachmentAfterItsOwnParentWrite() async throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let node = ViewNode()
        runtime.root.addChild(node)
        let departure = RetainedTaskPhysicalDeparture(roots: [node])
        let continuation = try originalContinuation(for: node, from: departure)
        let revoke = try XCTUnwrap(continuation.prepareRevoke())
        _ = try XCTUnwrap(node.revokeLazyListAttachmentProofs(removalWrite: revoke))
        let parentNil = try XCTUnwrap(continuation.prepareParentNil())
        let parentResult = try XCTUnwrap(node.writeRemovalParentNil(removalWrite: parentNil))
        let runtimeNil = try XCTUnwrap(continuation.prepareRuntimeNil())
        XCTAssertTrue(parentResult.isCurrent)

        // The literal kernel leaves the original child table in place. Use
        // the public remover to consume that table before the new attachment.
        runtime.root.removeChild(node)
        runtime.root.addChild(node)
        XCTAssertFalse(parentResult.isCurrent)
        XCTAssertNil(node.writeRemovalRuntimeNil(removalWrite: runtimeNil))
        XCTAssertTrue(continuation.hasRefusedWrite)
        XCTAssertNil(node.retainedLazyListRuntime, "A metadata refusal cannot suppress the native nil write")
        XCTAssertNil(node.revokeLazyListAttachmentProofs(removalWrite: revoke))
        XCTAssertNil(continuation.prepareRevoke())
        XCTAssertFalse(parentResult.isCurrent)
    }

    func testK4WrongNodeSpendsTheRecordAndDoesNotAcknowledgeEitherOrigin() async throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let first = ViewNode()
        let second = ViewNode()
        runtime.root.addChild(first)
        runtime.root.addChild(second)
        let firstDeparture = RetainedTaskPhysicalDeparture(roots: [first])
        let secondDeparture = RetainedTaskPhysicalDeparture(roots: [second])
        let firstOrigin = try originalContinuation(for: first, from: firstDeparture)
        let secondOrigin = try originalContinuation(for: second, from: secondDeparture)
        let firstWrite = try XCTUnwrap(firstOrigin.prepareRevoke())
        let secondWrite = try XCTUnwrap(secondOrigin.prepareRevoke())

        XCTAssertNil(second.revokeLazyListAttachmentProofs(removalWrite: firstWrite))
        XCTAssertTrue(firstOrigin.hasRefusedWrite)
        XCTAssertFalse(firstOrigin.hasEnteredInitialRevoke)
        XCTAssertFalse(secondOrigin.hasEnteredInitialRevoke)
        // The wrong-node call still revoked second's native token. Its own
        // previously prepared record cannot turn that write into an ACK.
        XCTAssertNil(second.revokeLazyListAttachmentProofs(removalWrite: secondWrite))
        XCTAssertTrue(secondOrigin.hasRefusedWrite)
        XCTAssertNil(first.revokeLazyListAttachmentProofs(removalWrite: firstWrite))
        XCTAssertNil(firstOrigin.prepareRevoke())
        XCTAssertNil(secondOrigin.prepareRevoke())
    }

    func testK4WrongNativeWriterCannotSpendARevokeRecordSuccessfully() async throws {
        for writer in [SuccessorNilWriter.parent, .runtime] {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let node = ViewNode()
            runtime.root.addChild(node)
            let departure = RetainedTaskPhysicalDeparture(roots: [node])
            let continuation = try originalContinuation(for: node, from: departure)
            let revoke = try XCTUnwrap(continuation.prepareRevoke())

            switch writer {
            case .parent:
                XCTAssertNil(node.writeRemovalParentNil(removalWrite: revoke))
                XCTAssertNil(node.parent)
            case .runtime:
                XCTAssertNil(node.writeRemovalRuntimeNil(removalWrite: revoke))
                XCTAssertNil(node.retainedLazyListRuntime)
            }
            XCTAssertTrue(continuation.hasRefusedWrite)
            XCTAssertFalse(continuation.hasEnteredInitialRevoke)
            XCTAssertNil(node.revokeLazyListAttachmentProofs(removalWrite: revoke))
            XCTAssertNil(continuation.prepareRevoke())
        }
    }

    func testK4ARealSuccessfulWriteCannotBeAcknowledgedTwice() async throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let node = ViewNode()
        runtime.root.addChild(node)
        let departure = RetainedTaskPhysicalDeparture(roots: [node])
        let continuation = try originalContinuation(for: node, from: departure)
        let write = try XCTUnwrap(continuation.prepareRevoke())
        let result = try XCTUnwrap(node.revokeLazyListAttachmentProofs(removalWrite: write))
        XCTAssertTrue(result.isCurrent)
        XCTAssertTrue(continuation.hasEnteredInitialRevoke)

        XCTAssertNil(node.revokeLazyListAttachmentProofs(removalWrite: write))
        XCTAssertTrue(continuation.hasRefusedWrite)
        XCTAssertFalse(result.isCurrent, "A replay performs the baseline revoke, not a second successor write")
        XCTAssertNil(continuation.prepareParentNil())
        XCTAssertNil(continuation.prepareRevoke())
    }

    func testK4PreparationAloneDoesNotEnterRemovalOrAuthorizeNilSuccessors() async throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let node = ViewNode()
        runtime.root.addChild(node)
        let ordinary = node.captureLazyListAttachmentProof()
        let departure = RetainedTaskPhysicalDeparture(roots: [node])
        let continuation = try originalContinuation(for: node, from: departure)
        let write = try XCTUnwrap(continuation.prepareRevoke())

        XCTAssertFalse(continuation.hasEnteredInitialRevoke)
        XCTAssertNil(continuation.prepareParentNil())
        XCTAssertNil(continuation.prepareRuntimeNil())
        XCTAssertTrue(ordinary.isCurrent)
        XCTAssertTrue(node.parent === runtime.root)
        XCTAssertTrue(node.retainedLazyListRuntime === runtime)
        XCTAssertFalse(node.isRemovalOverlay)
        XCTAssertTrue(runtime.transitionOverlays.isEmpty)
        withExtendedLifetime(write) {}
        // Actual Task admission also requires the private native append. Its
        // unentered-result branch is a source proof; E tests drive real append
        // through public removals instead of fabricating overlay state here.
    }

    func testK4AnotherOriginalCaptureCannotAdoptTheFirstWritersAcknowledgement() async throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let node = ViewNode()
        runtime.root.addChild(node)
        let firstDeparture = RetainedTaskPhysicalDeparture(roots: [node])
        let secondDeparture = RetainedTaskPhysicalDeparture(roots: [node])
        let first = try originalContinuation(for: node, from: firstDeparture)
        let second = try originalContinuation(for: node, from: secondDeparture)
        let firstWrite = try XCTUnwrap(first.prepareRevoke())
        let secondWrite = try XCTUnwrap(second.prepareRevoke())
        let result = try XCTUnwrap(node.revokeLazyListAttachmentProofs(removalWrite: firstWrite))
        XCTAssertTrue(result.isCurrent)
        XCTAssertTrue(first.hasEnteredInitialRevoke)
        XCTAssertFalse(second.hasEnteredInitialRevoke)

        XCTAssertNil(node.revokeLazyListAttachmentProofs(removalWrite: secondWrite))
        XCTAssertTrue(second.hasRefusedWrite)
        XCTAssertFalse(result.isCurrent)
        XCTAssertNil(second.prepareParentNil())
        // This rejects an independent writer's stale predecessor, not multiple
        // compatible Task roots consuming one actually appended public overlay.
    }

    func testK5LiteralNilWritersKeepOnlyTheirPredeterminedEndpoints() async throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let node = ViewNode()
        runtime.root.addChild(node)
        let ordinary = node.captureLazyListAttachmentProof()
        let departure = RetainedTaskPhysicalDeparture(roots: [node])
        let continuation = try originalContinuation(for: node, from: departure)
        let revoke = try XCTUnwrap(continuation.prepareRevoke())
        let revoked = try XCTUnwrap(node.revokeLazyListAttachmentProofs(removalWrite: revoke))
        XCTAssertTrue(revoked.isCurrent)
        let parentNil = try XCTUnwrap(continuation.prepareParentNil())
        let unparented = try XCTUnwrap(node.writeRemovalParentNil(removalWrite: parentNil))
        XCTAssertTrue(unparented.isCurrent)
        XCTAssertFalse(revoked.isCurrent, "The earlier result keeps its immutable parent endpoint")
        XCTAssertNil(node.parent)
        XCTAssertTrue(node.retainedLazyListRuntime === runtime)
        let runtimeNil = try XCTUnwrap(continuation.prepareRuntimeNil())
        let detached = try XCTUnwrap(node.writeRemovalRuntimeNil(removalWrite: runtimeNil))

        XCTAssertTrue(detached.isCurrent)
        XCTAssertTrue(continuation.isCurrent)
        XCTAssertFalse(continuation.hasRefusedWrite)
        XCTAssertFalse(unparented.isCurrent)
        XCTAssertFalse(ordinary.isCurrent)
        XCTAssertNil(node.parent)
        XCTAssertNil(node.retainedLazyListRuntime)
        XCTAssertTrue(runtime.root.children.contains { $0 === node })
        // These are literal pre-table writer kernels, not a completed public
        // removal. A different public parent now makes their nil result stale.
        let destinationRuntime = RetainedViewRuntime(root: ViewNode())
        destinationRuntime.root.addChild(node)
        XCTAssertTrue(node.parent === destinationRuntime.root)
        XCTAssertTrue(node.retainedLazyListRuntime === destinationRuntime)
        XCTAssertFalse(detached.isCurrent)
        XCTAssertFalse(continuation.isCurrent)
    }

    func testK6OriginalPreparedAndExecutedRecordsDoNotRetainTheUIGraph() async throws {
        let weakGraph = SuccessorWeakGraph()
        let records = try captureRecordsWithoutKeepingFixture(weakGraph)

        XCTAssertNil(weakGraph.node)
        XCTAssertNil(weakGraph.parent)
        XCTAssertNil(weakGraph.runtime)
        XCTAssertFalse(records.continuation.isCurrent)
        XCTAssertFalse(records.result.isCurrent)
        withExtendedLifetime(records) {}
    }

    func testK6ExpiredOriginalEndpointsDoNotInvalidateAcknowledgedNilEndpoints() async throws {
        let weakGraph = SuccessorWeakGraph()
        let captured = try captureNilEndpointsKeepingOnlyNode(weakGraph)

        XCTAssertTrue(weakGraph.node === captured.node)
        XCTAssertNil(weakGraph.parent)
        XCTAssertNil(weakGraph.runtime)
        XCTAssertNil(captured.node.parent)
        XCTAssertNil(captured.node.retainedLazyListRuntime)
        XCTAssertTrue(captured.continuation.isCurrent)
        XCTAssertTrue(captured.result.isCurrent)
        XCTAssertFalse(captured.continuation.hasRefusedWrite)
        withExtendedLifetime(captured) {}
    }

    func testE1ClockSupersessionCannotAcquireTheNewTaskAfterOriginalTaskClaim() async throws {
        let probe = SuccessorTaskProbe()
        let fixture = SuccessorTaskFixture(probe: probe)
        defer { fixture.finish(probe: probe) }
        let sourceParent = fixture.members[0]
        let destination = fixture.members[1]
        let reused = ViewNode(frame: Rect(x: 0, y: 0, width: 40, height: 20))
        sourceParent.addChild(reused)
        var oldDisappearances = 0
        reused.onDisappear = { oldDisappearances += 1 }
        let original = try fixture.installGroup(probe: probe, targets: [reused], label: "original")
        let originalReady = expectReady(probe)
        original.deliver(restart: false)
        _ = fixture.runtime.renderScene()
        await fulfillment(of: [originalReady], timeout: 5)
        XCTAssertEqual(probe.runs.map(\.label), ["original"])
        XCTAssertTrue(reused.hasAppeared)
        reused.transition = RetainedTransition(kind: .opacity)
        let originalTerminal = expectTerminal(probe, ordinals: [0])
        let replacementReady = expectReady(probe)
        var didReenter = false
        var replacement: RetainedTaskDeclaration?
        fixture.runtime.clock = { [weak fixture] in
            guard let fixture, !didReenter else { return probe.now }
            didReenter = true
            XCTAssertTrue(sourceParent.children.contains { $0 === reused })
            XCTAssertTrue(probe.cancellations.isEmpty)
            reused.transition = .identity
            withTransaction(Transaction(animation: nil)) {
                destination.addChild(reused)
                XCTAssertEqual(oldDisappearances, 1)
                XCTAssertTrue(reused.parent === destination)
                reused.onDisappear = { probe.recordDisappearance(label: "replacement", generation: 1) }
                do {
                    let next = try fixture.installGroup(
                        probe: probe, targets: [reused], label: "replacement", generation: 1)
                    replacement = next
                    XCTAssertTrue(next.canCommit)
                    next.deliver(restart: false)
                    _ = fixture.runtime.renderScene()
                    XCTAssertTrue(reused.hasAppeared)
                    XCTAssertFalse(reused.hasPendingAppearanceCallbacks)
                } catch {
                    XCTFail("Replacement Task must finish real journal adoption: \(error)")
                }
            }
            reused.transition = RetainedTransition(kind: .opacity)
            return probe.now
        }

        withAnimation(.linear(duration: 1)) { sourceParent.removeAllChildren() }
        XCTAssertTrue(didReenter)
        XCTAssertNotNil(replacement)
        await fulfillment(of: originalTerminal + [replacementReady], timeout: 5)
        XCTAssertEqual(probe.runs.map(\.label), ["original", "replacement"])
        XCTAssertEqual(probe.cancellations.map(\.ordinal), [0])
        assertFinishedExactlyOnce(probe, ordinal: 0)
        XCTAssertEqual(probe.suspendedCount, 1)
        XCTAssertEqual(oldDisappearances, 1)
        XCTAssertTrue(probe.disappearances.isEmpty)

        // Legacy parent/runtime writes may overwrite the replacement after the
        // clock returns. Do not repair, reattach, or render before this oracle.
        probe.now += 1.25
        _ = fixture.runtime.tickAnimations(at: probe.now)
        XCTAssertTrue(fixture.runtime.transitionOverlays.isEmpty)
        XCTAssertEqual(oldDisappearances, 1)
        XCTAssertTrue(probe.disappearances.isEmpty)
        XCTAssertEqual(probe.cancellations.map(\.ordinal), [0])
        XCTAssertEqual(probe.suspendedCount, 1)
        let replacementTerminal = expectTerminal(probe, ordinals: [1])
        fixture.close()
        await fulfillment(of: replacementTerminal, timeout: 5)
        assertFinishedExactlyOnce(probe, ordinal: 0)
        assertFinishedExactlyOnce(probe, ordinal: 1)
    }

    func testE2EarlierRootClockCannotRefreshALaterRootWithNoOriginalTask() async throws {
        let probe = SuccessorTaskProbe()
        let fixture = SuccessorTaskFixture(probe: probe)
        defer { fixture.finish(probe: probe) }
        let sourceParent = fixture.members[0]
        let destination = fixture.members[1]
        let first = ViewNode(frame: Rect(x: 0, y: 0, width: 40, height: 20))
        let later = ViewNode(frame: Rect(x: 0, y: 25, width: 40, height: 20))
        sourceParent.addChild(first)
        sourceParent.addChild(later)
        var firstDisappearances = 0
        var oldLaterDisappearances = 0
        first.onDisappear = { firstDisappearances += 1 }
        later.onDisappear = { oldLaterDisappearances += 1 }
        _ = fixture.runtime.renderScene()
        XCTAssertTrue(first.hasAppeared)
        XCTAssertTrue(later.hasAppeared)
        XCTAssertTrue(probe.runs.isEmpty)
        XCTAssertNil(later.existingRetainedTaskState)
        let originalLater = later.captureLazyListAttachmentProof()
        first.transition = RetainedTransition(kind: .opacity)
        later.transition = RetainedTransition(kind: .opacity)
        let ready = expectReady(probe)
        var didReenter = false
        var replacement: RetainedTaskDeclaration?
        fixture.runtime.clock = { [weak fixture] in
            guard let fixture, !didReenter else { return probe.now }
            didReenter = true
            // The outer remover has not reached this later root's first write.
            XCTAssertTrue(originalLater.isCurrent)
            XCTAssertTrue(later.parent === sourceParent)
            later.transition = .identity
            withTransaction(Transaction(animation: nil)) {
                destination.addChild(later)
                sourceParent.addChild(later)
                XCTAssertEqual(oldLaterDisappearances, 1)
                XCTAssertTrue(later.parent === sourceParent)
                XCTAssertTrue(later.retainedLazyListRuntime === fixture.runtime)
                XCTAssertFalse(originalLater.isCurrent)
                later.onDisappear = { probe.recordDisappearance(label: "later-replacement", generation: 1) }
                do {
                    let next = try fixture.installGroup(
                        probe: probe, targets: [later], label: "later-replacement", generation: 1)
                    replacement = next
                    next.deliver(restart: false)
                    _ = fixture.runtime.renderScene()
                    XCTAssertTrue(later.hasAppeared)
                    XCTAssertFalse(later.hasPendingAppearanceCallbacks)
                } catch {
                    XCTFail("Later replacement must complete real Task adoption: \(error)")
                }
            }
            later.transition = RetainedTransition(kind: .opacity)
            return probe.now
        }

        withAnimation(.linear(duration: 1)) { sourceParent.removeAllChildren() }
        XCTAssertTrue(didReenter)
        XCTAssertNotNil(replacement)
        await fulfillment(of: [ready], timeout: 5)
        XCTAssertEqual(probe.runs.map(\.label), ["later-replacement"])
        XCTAssertTrue(probe.cancellations.isEmpty)
        XCTAssertTrue(probe.disappearances.isEmpty)
        XCTAssertEqual(probe.suspendedCount, 1)
        XCTAssertEqual(oldLaterDisappearances, 1)
        XCTAssertEqual(firstDisappearances, 0)

        // Check the old entries without another render or attachment write.
        // The generic final child-table overwrite is a separate inherited limit.
        probe.now += 1.25
        _ = fixture.runtime.tickAnimations(at: probe.now)
        XCTAssertEqual(firstDisappearances, 1)
        XCTAssertEqual(oldLaterDisappearances, 1)
        XCTAssertTrue(fixture.runtime.transitionOverlays.isEmpty)
        XCTAssertTrue(probe.disappearances.isEmpty)
        XCTAssertTrue(probe.cancellations.isEmpty)
        XCTAssertEqual(probe.suspendedCount, 1)
        let terminal = expectTerminal(probe, ordinals: [0])
        fixture.close()
        await fulfillment(of: terminal, timeout: 5)
        assertFinishedExactlyOnce(probe, ordinal: 0)
    }

    func testE2OriginalExtractionDoesNotDiscoverDescendantsOrLaterForestRoots() async throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let original = ViewNode()
        let originalDescendant = ViewNode()
        original.addChild(originalDescendant)
        runtime.root.addChild(original)
        let departure = RetainedTaskPhysicalDeparture(roots: [original])
        let captured = departure.captureOriginalRemovalAttachments()
        XCTAssertEqual(Set(captured.keys), Set([ObjectIdentifier(original)]))
        XCTAssertNil(captured[ObjectIdentifier(originalDescendant)])

        let laterRoot = ViewNode()
        let laterDescendant = ViewNode()
        runtime.root.addChild(laterRoot)
        original.addChild(laterDescendant)
        let after = departure.captureOriginalRemovalAttachments()
        XCTAssertEqual(Set(after.keys), Set([ObjectIdentifier(original)]))
        XCTAssertNil(after[ObjectIdentifier(originalDescendant)])
        XCTAssertNil(after[ObjectIdentifier(laterRoot)])
        XCTAssertNil(after[ObjectIdentifier(laterDescendant)])
        XCTAssertFalse(try XCTUnwrap(after[ObjectIdentifier(original)]).hasEnteredInitialRevoke)
    }

    func testE3RawRemoveChildDefersTheAcceptedStorageTaskUntilFadeCompletion() async throws {
        try await assertPublishedStorageFade(.removeChild)
    }

    func testE3RawReplaceChildDefersTheAcceptedStorageTaskUntilFadeCompletion() async throws {
        try await assertPublishedStorageFade(.replaceChild)
    }

    func testE3RawRemoveAllChildrenDefersTheAcceptedStorageTaskUntilFadeCompletion() async throws {
        try await assertPublishedStorageFade(.removeAllChildren)
    }

    func testE4ActualOwnedGateBlocksNestedTicksUntilItsControllerAndQueuedDrainFinish() async throws {
        let probe = SuccessorTaskProbe()
        let fixture = SuccessorTaskFixture(probe: probe, memberCount: 1)
        let provider = RetainedLazyListDataSource<Int, [ViewNode]>()
        defer {
            fixture.finish(probe: probe)
            provider.close()
        }
        let container = fixture.members[0]
        let descendant = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 20), text: "adapter row")
        container.addChild(descendant)
        XCTAssertTrue(provider.replaceData([0], id: \.self, rowContent: { _ in [descendant] }))
        let adapter = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter(
                provider: provider, estimatedExtent: 40, prefetchExtent: 0,
                maximumMountedRecords: 4, maximumMountedLeaves: 16, maximumProtectedRecords: 1))
        let declaration = try fixture.installGroup(probe: probe, targets: [container], label: "adapter")
        let ready = expectReady(probe)
        declaration.deliver(restart: false)
        _ = fixture.runtime.renderScene()
        await fulfillment(of: [ready], timeout: 5)
        XCTAssertTrue(container.hasAppeared)
        let controller = SuccessorTextController()
        container.textInputController = controller
        container.retainedSubtreeBuildLease = SuccessorAdapterLease()
        container.retainedLazyListAdapter = adapter
        XCTAssertTrue(adapter.ownsAttachment(container))
        container.transition = RetainedTransition(kind: .opacity)
        var cleanupOrder: [String] = []
        var didRunQueuedDrain = false
        controller.onWillDetach = { [weak fixture, weak container, weak controller] in
            guard let fixture, let container, let controller else {
                XCTFail("The original controller must drain while its native owner is live")
                return
            }
            cleanupOrder.append("willDetach")
            XCTAssertTrue(adapter.ownsAttachment(container))
            XCTAssertTrue(container.retainedLazyListRuntime === fixture.runtime)
            _ = fixture.runtime.tickAnimations(at: probe.now + 1.25)
            XCTAssertTrue(fixture.runtime.transitionOverlays.contains { $0 === container })
            XCTAssertTrue(probe.order.isEmpty)
            XCTAssertEqual(probe.suspendedCount, 1)
            fixture.runtime.afterRetainedCallbacks { [weak fixture, weak container, weak controller] in
                guard let fixture, let container, let controller else {
                    XCTFail("The original queued drain must precede its gate release")
                    return
                }
                didRunQueuedDrain = true
                cleanupOrder.append("queuedDrain")
                XCTAssertTrue(adapter.ownsAttachment(container))
                XCTAssertEqual(controller.detachCalls, 1)
                _ = fixture.runtime.tickAnimations(at: probe.now + 1.25)
                XCTAssertTrue(fixture.runtime.transitionOverlays.contains { $0 === container })
                XCTAssertTrue(probe.order.isEmpty)
                XCTAssertEqual(probe.suspendedCount, 1)
            }
        }
        controller.onDetach = { [weak fixture, weak container] in
            guard let fixture, let container else {
                XCTFail("The captured controller must receive its original detach")
                return
            }
            cleanupOrder.append("detach")
            XCTAssertTrue(adapter.ownsAttachment(container))
            _ = fixture.runtime.tickAnimations(at: probe.now + 1.25)
            XCTAssertTrue(fixture.runtime.transitionOverlays.contains { $0 === container })
            XCTAssertTrue(probe.order.isEmpty)
        }
        let originalDisappear = try XCTUnwrap(container.onDisappear)
        container.onDisappear = { [weak container] in
            guard let container else {
                XCTFail("The original overlay must own its disappearance callback")
                return
            }
            XCTAssertTrue(didRunQueuedDrain)
            XCTAssertFalse(adapter.ownsAttachment(container))
            XCTAssertEqual(controller.willDetachCalls, 1)
            XCTAssertEqual(controller.detachCalls, 1)
            cleanupOrder.append("disappear")
            originalDisappear()
        }

        withAnimation(.linear(duration: 1)) { fixture.runtime.root.removeChild(container) }
        XCTAssertEqual(cleanupOrder, ["willDetach", "detach", "queuedDrain"])
        XCTAssertTrue(didRunQueuedDrain)
        XCTAssertFalse(adapter.ownsAttachment(container))
        XCTAssertFalse(declaration.canCommit)
        XCTAssertTrue(fixture.runtime.transitionOverlays.contains { $0 === container })
        XCTAssertTrue(probe.order.isEmpty)
        XCTAssertEqual(probe.suspendedCount, 1)

        // The actual old gate has now released its claim. A subsequent holder
        // may acquire it; completing the old overlay must not release that claim.
        let subsequentHolder = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 20))
        subsequentHolder.retainedSubtreeBuildLease = SuccessorAdapterLease()
        subsequentHolder.retainedLazyListAdapter = adapter
        fixture.runtime.root.addChild(subsequentHolder)
        XCTAssertTrue(adapter.ownsAttachment(subsequentHolder))
        let terminal = expectTerminal(probe, ordinals: [0])
        probe.now += 1.5
        _ = fixture.runtime.tickAnimations(at: probe.now)
        await fulfillment(of: terminal, timeout: 5)
        XCTAssertEqual(cleanupOrder, ["willDetach", "detach", "queuedDrain", "disappear"])
        XCTAssertEqual(probe.order, ["disappear:root-0:0", "cancel:adapter:0"])
        XCTAssertTrue(fixture.runtime.transitionOverlays.isEmpty)
        XCTAssertTrue(adapter.ownsAttachment(subsequentHolder))
        XCTAssertEqual(probe.runs.count, 1)
        assertFinishedExactlyOnce(probe, ordinal: 0)
        _ = fixture.runtime.tickAnimations(at: probe.now + 2)
        XCTAssertTrue(adapter.ownsAttachment(subsequentHolder))
        XCTAssertEqual(controller.willDetachCalls, 1)
        XCTAssertEqual(controller.detachCalls, 1)
        assertFinishedExactlyOnce(probe, ordinal: 0)
    }

    private func originalContinuation(
        for node: ViewNode, from departure: RetainedTaskPhysicalDeparture
    ) throws -> RetainedRemovalAttachmentContinuation {
        try XCTUnwrap(departure.captureOriginalRemovalAttachments()[ObjectIdentifier(node)])
    }

    /// This is ordinary physical acceptance, not a proof-only Actual capture.
    /// It follows the native O fixture's declaration, journal, and publication.
    private func publishOrdinaryMember(
        _ node: ViewNode, in runtime: RetainedViewRuntime
    ) throws -> RetainedOwnedComponentReceipt {
        let scope = RetainedLazyListDescriptorBuildScope(
            origin: .componentHostRoot, hostLifetime: runtime.lazyListLogicalHostLifetime,
            ownerLifetime: runtime.root.lazyListActivityStorage().descriptorOwnerLifetime)
        let journal = RetainedLazyListAdoptionJournal(descriptorScope: scope, transaction: RetainedBuildTransaction())
        let attribution = try XCTUnwrap(scope.registerOrdinaryComponent())
        let receipt = try XCTUnwrap(
            attribution.registerOwnedComponent(owner: RetainedOwnedComponentID(), slots: []))
        let group = try XCTUnwrap(attribution.registerGroup(kind: .observation))
        XCTAssertTrue(attribution.recordSourceOutput(node, group: group))
        XCTAssertNotNil(attribution.closeGroup(group))
        XCTAssertTrue(journal.beginOrdinaryAdoption())
        XCTAssertTrue(journal.markMutationStarted())
        XCTAssertTrue(journal.prepareInsertedNode(from: node))
        runtime.root.addChild(node)
        XCTAssertTrue(node.parent === runtime.root)
        XCTAssertTrue(node.retainedLazyListRuntime === runtime)
        _ = journal.recordAcceptedInsertedNode(on: node)
        _ = journal.recordCompletedNode(from: node, to: node)
        let disposition = journal.seal(completedCheckedAdoption: true)
        XCTAssertEqual(disposition.acceptedOwnedComponents.count, 2)
        journal.releaseUnadoptedTransport()
        scope.finish()
        return receipt
    }

    @inline(never)
    private func captureRecordsWithoutKeepingFixture(_ weakGraph: SuccessorWeakGraph) throws -> SuccessorNativeRecords {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let node = ViewNode()
        runtime.root.addChild(node)
        weakGraph.node = node
        weakGraph.parent = runtime.root
        weakGraph.runtime = runtime
        XCTAssertNil(node.existingRetainedTaskState)
        XCTAssertTrue(runtime.transitionOverlays.isEmpty)
        let departure = RetainedTaskPhysicalDeparture(roots: [node])
        let continuation = try originalContinuation(for: node, from: departure)
        let revoke = try XCTUnwrap(continuation.prepareRevoke())
        let result = try XCTUnwrap(node.revokeLazyListAttachmentProofs(removalWrite: revoke))
        let pendingParent = try XCTUnwrap(continuation.prepareParentNil())
        XCTAssertTrue(result.isCurrent)
        return SuccessorNativeRecords(
            departure: departure, continuation: continuation, revoke: revoke,
            result: result, pendingParent: pendingParent)
    }

    @inline(never)
    private func captureNilEndpointsKeepingOnlyNode(
        _ weakGraph: SuccessorWeakGraph
    ) throws -> (
        node: ViewNode, departure: RetainedTaskPhysicalDeparture,
        continuation: RetainedRemovalAttachmentContinuation, result: RetainedRemovalAttachmentWriteResult
    ) {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let node = ViewNode()
        runtime.root.addChild(node)
        weakGraph.node = node
        weakGraph.parent = runtime.root
        weakGraph.runtime = runtime
        XCTAssertNil(node.existingRetainedTaskState)
        let departure = RetainedTaskPhysicalDeparture(roots: [node])
        let continuation = try originalContinuation(for: node, from: departure)
        let revoke = try XCTUnwrap(continuation.prepareRevoke())
        _ = try XCTUnwrap(node.revokeLazyListAttachmentProofs(removalWrite: revoke))
        let parentNil = try XCTUnwrap(continuation.prepareParentNil())
        _ = try XCTUnwrap(node.writeRemovalParentNil(removalWrite: parentNil))
        let runtimeNil = try XCTUnwrap(continuation.prepareRuntimeNil())
        let result = try XCTUnwrap(node.writeRemovalRuntimeNil(removalWrite: runtimeNil))
        XCTAssertTrue(result.isCurrent)
        return (node, departure, continuation, result)
    }

    private func assertPublishedStorageFade(_ removal: SuccessorRawRemoval) async throws {
        let probe = SuccessorTaskProbe()
        let fixture = SuccessorTaskFixture(probe: probe, memberCount: 1)
        defer { fixture.finish(probe: probe) }
        let node = fixture.members[0]
        let declaration = try fixture.installGroup(probe: probe, label: "published")
        let ready = expectReady(probe)
        declaration.deliver(restart: false)
        _ = fixture.runtime.renderScene()
        await fulfillment(of: [ready], timeout: 5)
        XCTAssertTrue(node.hasAppeared)
        XCTAssertTrue(declaration.canCommit)
        let storage = try XCTUnwrap(node.retainedLazyListActivityStorage)
        XCTAssertFalse(storage.committedDescriptorContributions.isEmpty)
        let actual = storage.captureActualAttachment(of: node, in: fixture.runtime)
        let ordinary = node.captureLazyListAttachmentProof()
        XCTAssertTrue(actual.isAttached)
        XCTAssertTrue(ordinary.isCurrent)
        node.transition = RetainedTransition(kind: .opacity)

        withAnimation(.linear(duration: 1)) {
            switch removal {
            case .removeChild: fixture.runtime.root.removeChild(node)
            case .replaceChild: fixture.runtime.root.replaceChild(at: 0, with: ViewNode(frame: node.frame))
            case .removeAllChildren: fixture.runtime.root.removeAllChildren()
            }
        }
        XCTAssertFalse(actual.isAttached)
        XCTAssertFalse(ordinary.isCurrent)
        XCTAssertNil(node.parent)
        XCTAssertNil(node.retainedLazyListRuntime)
        XCTAssertTrue(fixture.runtime.transitionOverlays.contains { $0 === node })
        XCTAssertTrue(node.hasAppeared)
        XCTAssertTrue(probe.order.isEmpty)
        XCTAssertEqual(probe.suspendedCount, 1)
        probe.now += 0.5
        _ = fixture.runtime.tickAnimations(at: probe.now)
        XCTAssertEqual(node.opacity, 0.5, accuracy: 0.0001)
        XCTAssertTrue(node.hasAppeared)
        XCTAssertTrue(probe.cancellations.isEmpty)
        XCTAssertTrue(probe.disappearances.isEmpty)
        let terminal = expectTerminal(probe, ordinals: [0])

        probe.now += 1
        _ = fixture.runtime.tickAnimations(at: probe.now)
        await fulfillment(of: terminal, timeout: 5)
        XCTAssertEqual(probe.order, ["disappear:root-0:0", "cancel:published:0"])
        XCTAssertFalse(node.hasAppeared)
        XCTAssertTrue(fixture.runtime.transitionOverlays.isEmpty)
        XCTAssertEqual(probe.runs.count, 1)
        assertFinishedExactlyOnce(probe, ordinal: 0)
        _ = fixture.runtime.tickAnimations(at: probe.now + 2)
        XCTAssertEqual(probe.disappearances.count, 1)
        assertFinishedExactlyOnce(probe, ordinal: 0)
    }

    private func expectReady(_ probe: SuccessorTaskProbe) -> XCTestExpectation {
        let ready = expectation(description: "Task installed its cancellation handler and owned continuation")
        ready.assertForOverFulfill = true
        probe.onReady = { _ in ready.fulfill() }
        return ready
    }

    private func expectTerminal(_ probe: SuccessorTaskProbe, ordinals: [Int]) -> [XCTestExpectation] {
        let cancelled = expectation(description: "Original Task cancellation handler ran")
        let completed = expectation(description: "Original Task action reached its terminal receipt")
        for receipt in [cancelled, completed] {
            receipt.expectedFulfillmentCount = ordinals.count
            receipt.assertForOverFulfill = true
        }
        probe.onCancelled = { run in
            XCTAssertTrue(ordinals.contains(run.ordinal))
            cancelled.fulfill()
        }
        probe.onCompleted = { run in
            XCTAssertTrue(ordinals.contains(run.ordinal))
            completed.fulfill()
        }
        return [cancelled, completed]
    }

    private func assertFinishedExactlyOnce(
        _ probe: SuccessorTaskProbe, ordinal: Int,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(probe.cancellationHandlerCalls.filter { $0 == ordinal }.count, 1, file: file, line: line)
        XCTAssertEqual(probe.cancellations.filter { $0.ordinal == ordinal }.count, 1, file: file, line: line)
        XCTAssertEqual(probe.completions.filter { $0 == ordinal }.count, 1, file: file, line: line)
    }
}

private enum SuccessorNilWriter {
    case parent
    case runtime
}

private enum SuccessorRawRemoval {
    case removeChild
    case replaceChild
    case removeAllChildren
}

@MainActor
private final class SuccessorWeakGraph {
    weak var node: ViewNode?
    weak var parent: ViewNode?
    weak var runtime: RetainedViewRuntime?
}

@MainActor
private struct SuccessorNativeRecords {
    let departure: RetainedTaskPhysicalDeparture
    let continuation: RetainedRemovalAttachmentContinuation
    let revoke: RetainedRemovalAttachmentWrite
    let result: RetainedRemovalAttachmentWriteResult
    let pendingParent: RetainedRemovalAttachmentWrite
}

private struct SuccessorTaskRun: Equatable, Sendable {
    let ordinal: Int
    let label: String
    let generation: Int
}

/// Readiness follows publication of an owned continuation inside the installed
/// cancellation handler, as in the frozen M fixture. No scheduler sleeps or
/// synthetic cancellation acknowledgements stand in for an actual Task.
@MainActor
private final class SuccessorTaskProbe {
    var now = 100.0
    private(set) var runs: [SuccessorTaskRun] = []
    private(set) var cancellationHandlerCalls: [Int] = []
    private(set) var cancellations: [SuccessorTaskRun] = []
    private(set) var completions: [Int] = []
    private(set) var disappearances: [String] = []
    private(set) var order: [String] = []
    var onReady: ((SuccessorTaskRun) -> Void)?
    var onCancelled: ((SuccessorTaskRun) -> Void)?
    var onCompleted: ((SuccessorTaskRun) -> Void)?
    private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var isReleased = false

    var suspendedCount: Int { continuations.count }

    func recordDisappearance(label: String, generation: Int) {
        let event = "disappear:\(label):\(generation)"
        disappearances.append(event)
        order.append(event)
    }

    func run(label: String, generation: Int) async {
        let run = SuccessorTaskRun(ordinal: runs.count, label: label, generation: generation)
        runs.append(run)
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                if Task.isCancelled || cancellations.contains(where: { $0.ordinal == run.ordinal }) {
                    cancel(run)
                    continuation.resume()
                } else if isReleased {
                    continuation.resume()
                } else {
                    continuations[run.ordinal] = continuation
                }
                onReady?(run)
            }
        } onCancel: { [weak self] in
            let probe = self
            MainActor.assumeIsolated {
                probe?.cancellationHandlerCalls.append(run.ordinal)
                probe?.cancel(run)
            }
        }
        completions.append(run.ordinal)
        onCompleted?(run)
    }

    private func cancel(_ run: SuccessorTaskRun) {
        guard !cancellations.contains(where: { $0.ordinal == run.ordinal }) else { return }
        cancellations.append(run)
        order.append("cancel:\(run.label):\(run.generation)")
        let continuation = continuations.removeValue(forKey: run.ordinal)
        onCancelled?(run)
        continuation?.resume()
    }

    func clearAcknowledgements() {
        onReady = nil
        onCancelled = nil
        onCompleted = nil
    }

    func releaseAll() {
        isReleased = true
        let pending = Array(continuations.values)
        continuations.removeAll()
        for continuation in pending { continuation.resume() }
    }
}

@MainActor
private final class SuccessorTaskEpoch: RetainedBuildEpoch {
    var canAdopt = true
    var canComplete = true
    func supersede() { canAdopt = false }
    func willAdopt() -> Bool { canAdopt }
    func commit() {}
    func abandon() { canAdopt = false }
    func finishAfterCallbacks() {}
}

/// Native source transport copied from the M fixture: every lifecycle field,
/// actual attachment, and Task group is accepted by the production journal.
@MainActor
private final class SuccessorTaskFixture {
    let runtime: RetainedViewRuntime
    let members: [ViewNode]
    private let epoch = SuccessorTaskEpoch()

    init(probe: SuccessorTaskProbe, memberCount: Int = 2) {
        let root = ViewNode(frame: Rect(x: 0, y: 0, width: 120, height: 100))
        runtime = RetainedViewRuntime(root: root)
        members = (0..<memberCount).map { index in
            ViewNode(frame: Rect(x: 0, y: Double(index) * 25, width: 100, height: 20))
        }
        for (index, member) in members.enumerated() {
            root.addChild(member)
            member.onDisappear = { probe.recordDisappearance(label: "root-\(index)", generation: 0) }
        }
        runtime.clock = { probe.now }
    }

    func installGroup(
        probe: SuccessorTaskProbe, targets selected: [ViewNode]? = nil,
        label: String = "group", generation: Int = 0
    ) throws -> RetainedTaskDeclaration {
        let targets = selected ?? members
        let scope = RetainedLazyListDescriptorBuildScope(
            origin: .componentHostRoot, hostLifetime: runtime.lazyListLogicalHostLifetime,
            ownerLifetime: runtime.root.lazyListActivityStorage().descriptorOwnerLifetime)
        let transaction = RetainedBuildTransaction()
        let journal = RetainedLazyListAdoptionJournal(descriptorScope: scope, transaction: transaction)
        let context = RetainedTaskAdoptionContext(runtime: runtime, epoch: epoch, transaction: transaction)
        let attribution = try XCTUnwrap(scope.registerOrdinaryComponent())
        let group = try XCTUnwrap(attribution.registerGroup(kind: .scopedTask))
        let sources = targets.map { _ in ViewNode() }
        let declaration = RetainedTaskDeclaration(
            mount: RetainedTaskMountToken(), priority: .userInitiated,
            action: { await probe.run(label: label, generation: generation) },
            isMember: { true }, isCurrentProposal: { true })
        XCTAssertTrue(
            declaration.stage(groupSources: sources, in: runtime, descriptorAttribution: attribution, group: group))
        for source in sources {
            source.onAppearWithNode = { [weak declaration] node in declaration?.appear(on: node) }
            source.onDisappearWithNode = { [weak declaration] node in declaration?.disappear(from: node) }
        }
        _ = try XCTUnwrap(attribution.closeGroup(group))
        let preparation = try XCTUnwrap(journal.preparation())
        XCTAssertTrue(
            journal.beginAdoption(
                preparation,
                preparedActivity: RetainedLazyListPreparedActivity(preparation: preparation, logicalMembershipPlans: [])
            ))
        XCTAssertTrue(journal.markMutationStarted())
        for (source, target) in zip(sources, targets) {
            let identifiers =
                source.existingRetainedTaskState?.descriptorCandidateDeclarations().flatMap { $0.declarations } ?? []
            journal.recordAcceptedDescriptorTaskDeclarationTransport(
                from: source, to: target, declarationIDs: identifiers)
            _ = journal.recordAcceptedAttachment(from: source, to: target)
            try copy(\ViewNode.onAppearWithNode, from: source, to: target, journal: journal)
            try copy(\ViewNode.onDisappearWithNode, from: source, to: target, journal: journal)
        }
        let accepted = journal.takeAcceptedDescriptorTaskGroups()
        XCTAssertEqual(accepted.count, 1)
        let acceptedGroup = try XCTUnwrap(accepted.first)
        XCTAssertEqual(acceptedGroup.members.count, targets.count)
        withExtendedLifetime(sources) {
            XCTAssertTrue(context.associateDescriptorAccepted(acceptedGroup, journal: journal))
        }
        _ = journal.seal(completedCheckedAdoption: true)
        journal.finishAcceptedTaskCleanup()
        journal.releaseUnadoptedTransport()
        scope.finish()
        return declaration
    }

    private func copy<Value>(
        _ keyPath: ReferenceWritableKeyPath<ViewNode, Value>, from source: ViewNode, to target: ViewNode,
        journal: RetainedLazyListAdoptionJournal
    ) throws {
        XCTAssertTrue(journal.preparePropertyCopy(from: source, to: target, keyPath: keyPath))
        let previous = target[keyPath: keyPath]
        target[keyPath: keyPath] = source[keyPath: keyPath]
        _ = journal.recordAcceptedProperty(from: source, to: target, keyPath: keyPath)
        withExtendedLifetime(previous) {}
    }

    func close() {
        runtime.stopRenderLifecycleCallbacks()
        epoch.canAdopt = false
        epoch.canComplete = false
        runtime.cancelRenderLifecycleTasks()
        runtime.root.removeAllChildren()
    }

    func finish(probe: SuccessorTaskProbe) {
        probe.clearAcknowledgements()
        runtime.clock = { probe.now }
        close()
        probe.releaseAll()
    }
}

@MainActor
private final class SuccessorAdapterLease: RetainedSubtreeBuildLease {
    var canBuild: Bool { true }
    func beginBuild() -> (any RetainedBuildEpoch)? { SuccessorAdapterEpoch() }
}

@MainActor
private final class SuccessorAdapterEpoch: RetainedBuildEpoch {
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

/// Existing controller callbacks are the gate-drain boundary under test.
/// Revocation itself only changes native state and never invokes a callback.
@MainActor
private final class SuccessorTextController: RetainedTextInputController {
    var onWillDetach: (() -> Void)?
    var onDetach: (() -> Void)?
    private weak var owner: ViewNode?
    private var authorized = false
    private(set) var willDetachCalls = 0
    private(set) var detachCalls = 0

    func attach(to node: ViewNode) {
        owner = node
        authorized = true
    }

    func prepareForReconciliation(from previous: (any RetainedTextInputController)?, onto node: ViewNode) {
        if let previous, previous !== self { previous.revokeOwnership(from: node) }
    }

    func reconcile(from previous: (any RetainedTextInputController)?, onto node: ViewNode) {}

    func revokeOwnership(from node: ViewNode) {
        guard owner === node, authorized else { return }
        authorized = false
    }

    func willDetach(from node: ViewNode) {
        guard owner === node else { return }
        willDetachCalls += 1
        onWillDetach?()
    }

    func detach(from node: ViewNode) {
        guard owner === node else { return }
        authorized = false
        owner = nil
        detachCalls += 1
        onDetach?()
    }
}
