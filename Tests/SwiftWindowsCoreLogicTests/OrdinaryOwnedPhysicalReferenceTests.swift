import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI

/// Real native acceptance and withdrawals; these tests do not replace the
/// unchanged Raw3 oracles or manufacture facade acceptance.
@MainActor
final class OrdinaryOwnedPhysicalReferenceTests: XCTestCase {
    func testZeroSlotComponentRetiresAtItsLastRawReference() async throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let rootOwner = runtime.root.lazyListActivityStorage().descriptorOwnerLifetime
        let node = referenceNode(1)
        let first = NativeReferenceEpoch(runtime)
        let component = try first.component(nodes: [node], slots: [])
        first.begin()
        first.publish(node)
        let accepted = first.finish()
        XCTAssertEqual(accepted.acceptedOwnedComponents.count, 2)
        XCTAssertTrue(component.receipt.hasDeclaredComponent)
        let actual = node.lazyListActivityStorage().captureActualAttachment(of: node, in: runtime)

        runtime.root.removeChild(node)

        XCTAssertNil(node.parent)
        XCTAssertNil(node.retainedLazyListRuntime)
        XCTAssertFalse(actual.isAttached)
        XCTAssertTrue(rootOwner.isCurrent)
        XCTAssertTrue(component.receipt.hasAcceptedDeclaration)
        XCTAssertFalse(component.receipt.hasDeclaredComponent)
    }

    func testAllAliasesAreWithdrawnBeforeTheOriginalDismantleCallback() async throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let slot = RetainedOwnedSlotGenerationID()
        let node = referenceNode(1)
        node.onAppear = {}
        node.onDisappear = {}
        let first = NativeReferenceEpoch(runtime)
        let component = try first.component(nodes: [node], slots: [slot])
        first.begin()
        first.publish(node)
        XCTAssertEqual(first.finish().acceptedOwnedComponents.count, 2)
        XCTAssertTrue(component.receipt.permitsOwnedWrite(for: slot))
        var callbacks = 0
        node.onDismantlePlatformView = { departing in
            callbacks += 1
            XCTAssertNotNil(departing.parent)
            XCTAssertFalse(component.receipt.permitsOwnedWrite(for: slot))
            XCTAssertFalse(component.receipt.hasDeclaredComponent)
        }
        defer { node.onDismantlePlatformView = nil }

        runtime.root.removeChild(node)

        XCTAssertEqual(callbacks, 1)
        XCTAssertNil(node.parent)
        XCTAssertTrue(component.receipt.hasAcceptedDeclaration)
        XCTAssertFalse(component.receipt.hasAcceptedOwnership(for: slot))
        XCTAssertFalse(component.receipt.hasDeclaredComponent)
    }

    func testRemainingPayloadAliasSurvivesStructuralReplacementUntilItsOwnWrite() async throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let slot = RetainedOwnedSlotGenerationID()
        let node = ViewNode()
        node.onAppear = {}
        let first = NativeReferenceEpoch(runtime)
        let original = try first.component(nodes: [node], slots: [slot])
        first.begin()
        first.publish(node)
        _ = first.finish()
        let source = referenceNode(2)
        let replacement = NativeReferenceEpoch(runtime)
        _ = try replacement.component(nodes: [source], slots: [])
        replacement.begin()

        _ = replacement.journal.recordCompletedNode(from: source, to: node)

        XCTAssertTrue(original.receipt.permitsOwnedWrite(for: slot))
        XCTAssertTrue(original.receipt.hasDeclaredComponent)
        XCTAssertTrue(
            replacement.journal.preparePropertyCopy(from: source, to: node, keyPath: \ViewNode.onAppear))
        node.onAppear = nil
        _ = replacement.journal.recordAcceptedProperty(from: source, to: node, keyPath: \ViewNode.onAppear)

        XCTAssertFalse(original.receipt.permitsOwnedWrite(for: slot))
        XCTAssertFalse(original.receipt.hasDeclaredComponent)
        let disposition = replacement.finish()
        XCTAssertEqual(disposition.retiredOwnedSlots.filter { $0 === slot }.count, 1)
        XCTAssertEqual(disposition.retiredOwnedComponents.filter { $0 === original.receipt.owner }.count, 1)
    }

    func testReadingAnEmptyHolderDoesNotInvalidateTheOriginalMapObservation() async throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let node = ViewNode()
        runtime.root.addChild(node)
        let storage = node.lazyListActivityStorage()
        let removal = RetainedOwnedPhysicalDepartureRemoval(
            storage: storage, targetID: storage.targetID, attachmentID: storage.attachmentID)

        let actual = storage.captureActualAttachment(of: node, in: runtime)
        XCTAssertTrue(actual.isAttached)
        removal.removeOriginalMapsOnce()

        XCTAssertTrue(removal.successfullyClearedOriginalStorage === storage)
        node.retainedLazyListActivityStorage = nil
        node.retainedLazyListActivityStorage = storage
        XCTAssertNil(removal.successfullyClearedOriginalStorage)
    }

    func testTwoCapturesShareTheOriginalFieldButOnlyOneClearCanConsumeIt() async throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let node = referenceNode(1)
        let epoch = NativeReferenceEpoch(runtime)
        let owned = try epoch.component(nodes: [node], slots: [RetainedOwnedSlotGenerationID()])
        epoch.begin()
        epoch.publish(node)
        _ = epoch.finish()
        XCTAssertTrue(owned.receipt.hasDeclaredComponent)
        let storage = node.lazyListActivityStorage()
        let first = RetainedOwnedPhysicalDepartureRemoval(
            storage: storage, targetID: storage.targetID, attachmentID: storage.attachmentID)
        let second = RetainedOwnedPhysicalDepartureRemoval(
            storage: storage, targetID: storage.targetID, attachmentID: storage.attachmentID)

        first.removeOriginalMapsOnce()
        second.removeOriginalMapsOnce()

        XCTAssertTrue(first.successfullyClearedOriginalStorage === storage)
        XCTAssertNil(second.successfullyClearedOriginalStorage)
    }

    func testRejectedPropertyProposalLeavesTheOriginalMapClearUsable() async throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let node = referenceNode(1)
        let epoch = NativeReferenceEpoch(runtime)
        let owned = try epoch.component(nodes: [node], slots: [RetainedOwnedSlotGenerationID()])
        epoch.begin()
        epoch.publish(node)
        _ = epoch.finish()
        let storage = node.lazyListActivityStorage()
        let removal = RetainedOwnedPhysicalDepartureRemoval(
            storage: storage, targetID: storage.targetID, attachmentID: storage.attachmentID)
        let unrelated = NativeReferenceEpoch(runtime)
        unrelated.begin()

        XCTAssertFalse(
            unrelated.journal.preparePropertyCopy(from: referenceNode(2), to: node, keyPath: \ViewNode.onAppear))
        XCTAssertTrue(owned.receipt.hasDeclaredComponent)
        removal.removeOriginalMapsOnce()

        XCTAssertTrue(removal.successfullyClearedOriginalStorage === storage)
        _ = unrelated.finish()
    }

    func testEqualMemberRepublishCannotBeClearedByAnOlderOriginalField() async throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let slot = RetainedOwnedSlotGenerationID()
        let node = referenceNode(1)
        let first = NativeReferenceEpoch(runtime)
        let original = try first.component(nodes: [node], slots: [slot])
        first.begin()
        first.publish(node)
        _ = first.finish()
        let storage = node.lazyListActivityStorage()
        let target = storage.targetID
        let attachment = storage.attachmentID
        let removal = RetainedOwnedPhysicalDepartureRemoval(
            storage: storage, targetID: target, attachmentID: attachment)
        let second = NativeReferenceEpoch(runtime)
        let continued = try second.component(nodes: [node], slots: [slot], continuing: original.receipt)
        second.begin()
        second.publish(node, attaching: false)
        _ = second.finish()

        removal.removeOriginalMapsOnce()
        removal.removeOriginalMapsOnce()

        XCTAssertNil(removal.successfullyClearedOriginalStorage)
        XCTAssertTrue(storage.targetID === target)
        XCTAssertTrue(storage.attachmentID === attachment)
        XCTAssertTrue(continued.receipt.owner === original.receipt.owner)
        XCTAssertTrue(original.receipt.hasAcceptedOwnership(for: slot))
        runtime.root.removeChild(node)
        XCTAssertFalse(original.receipt.permitsOwnedWrite(for: slot))
        XCTAssertFalse(continued.receipt.hasDeclaredComponent)
    }

    func testRepublishingTheSameEmptyAnchorObjectInvalidatesTheOlderClear() async throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let slot = RetainedOwnedSlotGenerationID()
        let node = ViewNode()
        runtime.root.addChild(node)
        let storage = node.lazyListActivityStorage()
        let anchor = storage.captureActualAttachment(of: node, in: runtime)
        let first = NativeReferenceEpoch(runtime)
        let original = try first.component(nodes: [], slots: [slot])
        first.begin()
        XCTAssertEqual(
            first.journal.recordAcceptedOrdinaryEmptyGroups(
                structuralAnchor: anchor, groups: [original.group]
            ).count, 1)
        _ = first.finish()
        XCTAssertTrue(original.receipt.hasAcceptedOwnership(for: slot))
        let removal = RetainedOwnedPhysicalDepartureRemoval(
            storage: storage, targetID: storage.targetID, attachmentID: storage.attachmentID)
        let later = NativeReferenceEpoch(runtime)
        let continued = try later.component(nodes: [], slots: [slot], continuing: original.receipt)
        later.begin()
        let facts = later.journal.recordAcceptedOrdinaryEmptyGroups(
            structuralAnchor: anchor, groups: [continued.group])
        XCTAssertEqual(facts.count, 1)
        XCTAssertTrue(try XCTUnwrap(facts.first).structuralAnchor === anchor)
        _ = later.finish()

        removal.removeOriginalMapsOnce()

        XCTAssertNil(removal.successfullyClearedOriginalStorage)
        XCTAssertTrue(anchor.isAttached)
        XCTAssertTrue(original.receipt.hasAcceptedOwnership(for: slot))
        runtime.root.removeChild(node)
        XCTAssertFalse(original.receipt.permitsOwnedWrite(for: slot))
        XCTAssertFalse(continued.receipt.hasDeclaredComponent)
    }

    func testTwoZeroSlotPhysicalDebtsRetireOnlyAfterBothOriginalJournalsDrain() async throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let a = referenceNode(1)
        let b = referenceNode(2)
        let first = NativeReferenceEpoch(runtime)
        let original = try first.component(nodes: [a, b], slots: [])
        first.begin()
        first.publish(a)
        first.publish(b)
        _ = first.finish()
        XCTAssertTrue(original.receipt.hasDeclaredComponent)
        let j1 = NativeReferenceEpoch(runtime)
        let j2 = NativeReferenceEpoch(runtime)
        let incoming1 = referenceNode(3)
        let incoming2 = referenceNode(4)
        _ = try j1.component(nodes: [incoming1], slots: [], continuing: original.receipt)
        _ = try j2.component(nodes: [incoming2], slots: [], continuing: original.receipt)
        j1.begin()
        j2.begin()
        _ = j1.journal.recordPhysicalDeparture(of: a, cause: .acceptedReplacement, retireOwned: false)
        _ = j2.journal.recordPhysicalDeparture(of: b, cause: .acceptedReplacement, retireOwned: false)
        runtime.root.removeChild(a)
        runtime.root.removeChild(b)
        XCTAssertNil(a.parent)
        XCTAssertNil(b.parent)
        XCTAssertTrue(original.receipt.hasDeclaredComponent)

        let firstDrain = j1.finish()

        XCTAssertTrue(original.receipt.hasDeclaredComponent)
        XCTAssertFalse(firstDrain.retiredOwnedComponents.contains { $0 === original.receipt.owner })
        let lastDrain = j2.finish()
        XCTAssertFalse(original.receipt.hasDeclaredComponent)
        XCTAssertEqual(lastDrain.retiredOwnedComponents.filter { $0 === original.receipt.owner }.count, 1)
        XCTAssertEqual(j2.finish().retiredOwnedComponents.filter { $0 === original.receipt.owner }.count, 1)
        withExtendedLifetime([incoming1, incoming2]) {}
    }

    func testPhysicalAndDeclaredZeroSlotDebtsShareCustodyInBothDrainOrders() async throws {
        for physicalFirst in [false, true] {
            let runtime = RetainedViewRuntime(root: ViewNode())
            let marker = ViewNode()
            runtime.root.addChild(marker)
            let source = ViewNode()
            let initial = NativeReferenceEpoch(runtime)
            let original = try initial.component(nodes: [source], slots: [], structure: true)
            initial.beginChecked()
            _ = initial.journal.recordCompletedNode(from: source, to: marker)
            _ = initial.finish()
            XCTAssertTrue(original.receipt.hasDeclaredComponent)
            let dormantSource = ViewNode()
            let dormant = NativeReferenceEpoch(runtime)
            _ = try dormant.component(
                nodes: [dormantSource], slots: [], continuing: original.receipt, declarationOnly: true,
                structure: true)
            dormant.beginChecked()
            try dormant.publishDeclaration(from: dormantSource, to: marker)
            _ = dormant.journal.recordCompletedNode(from: dormantSource, to: marker)
            _ = dormant.finish()
            let originalActual = marker.lazyListActivityStorage().captureActualAttachment(of: marker, in: runtime)
            XCTAssertTrue(originalActual.isAttached)
            XCTAssertTrue(original.receipt.hasDeclaredComponent)

            let physical = NativeReferenceEpoch(runtime)
            let physicalSource = ViewNode()
            _ = try physical.component(
                nodes: [physicalSource], slots: [], continuing: original.receipt, structure: true)
            physical.beginChecked()
            _ = physical.journal.recordPhysicalDeparture(
                of: marker, cause: .acceptedReplacement, retireOwned: false)
            let declared = NativeReferenceEpoch(runtime)
            let normalSource = ViewNode()
            let emptyDeclarationSource = ViewNode()
            try declared.unownedSource(emptyDeclarationSource)
            _ = try declared.component(
                nodes: [normalSource], slots: [], continuing: original.receipt, structure: true)
            declared.beginChecked()
            try declared.publishDeclaration(from: emptyDeclarationSource, to: marker)
            XCTAssertTrue(original.receipt.hasDeclaredComponent)
            runtime.root.removeChild(marker)
            XCTAssertFalse(originalActual.isAttached)
            XCTAssertTrue(original.receipt.hasDeclaredComponent)

            let firstDrain = physicalFirst ? physical.finish() : declared.finish()

            XCTAssertTrue(original.receipt.hasDeclaredComponent)
            XCTAssertFalse(firstDrain.retiredOwnedComponents.contains { $0 === original.receipt.owner })
            let lastDrain = physicalFirst ? declared.finish() : physical.finish()
            XCTAssertFalse(original.receipt.hasDeclaredComponent)
            XCTAssertEqual(lastDrain.retiredOwnedComponents.filter { $0 === original.receipt.owner }.count, 1)
        }
    }

    func testRestoringTheSameStorageCannotRearmWithdrawnOwnership() async throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let slot = RetainedOwnedSlotGenerationID()
        let node = referenceNode(1)
        let initial = NativeReferenceEpoch(runtime)
        let original = try initial.component(nodes: [node], slots: [slot])
        initial.begin()
        initial.publish(node)
        _ = initial.finish()
        let storage = node.lazyListActivityStorage()
        let oldActual = storage.captureActualAttachment(of: node, in: runtime)
        let pinnedHolder = storage.captureOwnedPhysicalReferenceHolder()
        let removal = RetainedOwnedPhysicalDepartureRemoval(
            storage: storage, targetID: storage.targetID, attachmentID: storage.attachmentID)
        XCTAssertTrue(original.receipt.permitsOwnedWrite(for: slot))

        node.retainedLazyListActivityStorage = nil
        node.retainedLazyListActivityStorage = storage
        removal.removeOriginalMapsOnce()

        XCTAssertNil(removal.successfullyClearedOriginalStorage)
        XCTAssertFalse(pinnedHolder.matches(storage))
        XCTAssertTrue(oldActual.isAttached, "Restoring the old T/A does not restore its owned references")
        XCTAssertFalse(original.receipt.hasAcceptedOwnership(for: slot))
        XCTAssertFalse(original.receipt.hasDeclaredComponent)
        let read = storage.captureActualAttachment(of: node, in: runtime)
        XCTAssertTrue(read.isAttached)
        XCTAssertFalse(original.receipt.permitsOwnedWrite(for: slot))
        withExtendedLifetime(pinnedHolder) {}
    }

    func testProofOnlyRotationAllowsRealContinuationBeforeRawWithdrawalRetiresIt() async throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let slot = RetainedOwnedSlotGenerationID()
        let node = referenceNode(1)
        let first = NativeReferenceEpoch(runtime)
        let original = try first.component(nodes: [node], slots: [slot])
        first.begin()
        first.publish(node)
        _ = first.finish()
        let storage = node.lazyListActivityStorage()
        let originalActual = storage.captureActualAttachment(of: node, in: runtime)

        storage.revokeAttachment()

        XCTAssertFalse(originalActual.isAttached)
        XCTAssertTrue(original.receipt.permitsOwnedWrite(for: slot))
        XCTAssertTrue(original.receipt.hasDeclaredComponent)
        let next = NativeReferenceEpoch(runtime)
        let continued = try next.component(nodes: [node], slots: [slot], continuing: original.receipt)
        next.begin()
        next.publish(node, attaching: false)
        XCTAssertTrue(continued.receipt.hasAcceptedDeclaration)
        _ = next.finish()
        runtime.root.removeChild(node)
        XCTAssertFalse(original.receipt.permitsOwnedWrite(for: slot))
        XCTAssertFalse(continued.receipt.hasDeclaredComponent)
    }

    func testOriginalNodeAndStorageExpiryDoNotSpendAZeroSlotDebt() async throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let probe = NativeReferenceWeakProbe()
        let pending = try makePendingReferenceWithExpiredNode(runtime, probe: probe)
        XCTAssertNil(probe.node)
        XCTAssertNil(probe.storage)
        XCTAssertTrue(pending.original.hasDeclaredComponent)

        let disposition = pending.epoch.finish()

        XCTAssertFalse(pending.original.hasDeclaredComponent)
        XCTAssertEqual(disposition.retiredOwnedComponents.filter { $0 === pending.original.owner }.count, 1)
        withExtendedLifetime(pending.ticket) {}
    }

    func testDismantleCanAdmitASiblingDebtWithoutTheFirstDrainDroppingIt() async throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let slot = RetainedOwnedSlotGenerationID()
        let a = referenceNode(1)
        let b = referenceNode(2)
        let first = NativeReferenceEpoch(runtime)
        let original = try first.component(nodes: [a, b], slots: [slot])
        first.begin()
        first.publish(a)
        first.publish(b)
        _ = first.finish()
        let next = NativeReferenceEpoch(runtime)
        let incoming = referenceNode(3)
        _ = try next.component(nodes: [incoming], slots: [slot], continuing: original.receipt)
        next.begin()
        _ = next.journal.recordPhysicalDeparture(of: a, cause: .acceptedReplacement, retireOwned: false)
        var callbacks = 0
        a.onDismantlePlatformView = { _ in
            callbacks += 1
            _ = next.journal.recordPhysicalDeparture(of: b, cause: .acceptedReplacement, retireOwned: false)
        }
        defer { a.onDismantlePlatformView = nil }

        runtime.root.removeChild(a)
        next.journal.recordOwnedPhysicalDeparture(of: a, cause: .acceptedReplacement)
        XCTAssertEqual(callbacks, 1)
        XCTAssertTrue(original.receipt.hasDeclaredComponent)
        runtime.root.removeChild(b)
        XCTAssertTrue(original.receipt.hasDeclaredComponent)
        let disposition = next.finish()

        XCTAssertFalse(original.receipt.permitsOwnedWrite(for: slot))
        XCTAssertFalse(original.receipt.hasDeclaredComponent)
        XCTAssertEqual(disposition.retiredOwnedSlots.filter { $0 === slot }.count, 1)
        XCTAssertEqual(disposition.retiredOwnedComponents.filter { $0 === original.receipt.owner }.count, 1)
    }

    func testOriginalAliasReceiptDoesNotRetainTheNodeStorageOrRuntime() async throws {
        let probe = NativeReferenceWeakProbe()
        let removal = try makeReferenceRemovalAfterRuntimeRelease(probe)
        XCTAssertNil(probe.node)
        XCTAssertNil(probe.storage)
        XCTAssertNil(probe.runtime)

        removal.removeOriginalMapsOnce()

        XCTAssertNil(removal.successfullyClearedOriginalStorage)
    }
}

@MainActor
private func referenceNode(_ identity: Int) -> ViewNode {
    let node = ViewNode()
    node.retainedViewIdentity = RetainedViewIdentity().appending(.slot(identity))
    return node
}

@MainActor
private struct NativeReferenceComponent {
    let receipt: RetainedOwnedComponentReceipt
    let group: RetainedDescriptorGroupID
}

@MainActor
private final class NativeReferenceEpoch {
    let runtime: RetainedViewRuntime
    let scope: RetainedLazyListDescriptorBuildScope
    let journal: RetainedLazyListAdoptionJournal

    init(_ runtime: RetainedViewRuntime) {
        self.runtime = runtime
        scope = RetainedLazyListDescriptorBuildScope(
            origin: .componentHostRoot, hostLifetime: runtime.lazyListLogicalHostLifetime,
            ownerLifetime: runtime.root.lazyListActivityStorage().descriptorOwnerLifetime)
        journal = RetainedLazyListAdoptionJournal(descriptorScope: scope, transaction: RetainedBuildTransaction())
    }

    func component(
        nodes: [ViewNode], slots: [RetainedOwnedSlotGenerationID],
        continuing: RetainedOwnedComponentReceipt? = nil, declarationOnly: Bool = false, structure: Bool = false
    ) throws -> NativeReferenceComponent {
        let attribution = try XCTUnwrap(scope.registerOrdinaryComponent())
        let receipt = try XCTUnwrap(
            attribution.registerOwnedComponent(
                owner: continuing?.owner ?? RetainedOwnedComponentID(), slots: slots, continuing: continuing,
                declarationOnly: declarationOnly))
        let group = try XCTUnwrap(attribution.registerGroup(kind: structure ? .structure : .observation))
        for node in nodes { XCTAssertTrue(attribution.recordSourceOutput(node, group: group)) }
        XCTAssertNotNil(attribution.closeGroup(group))
        return NativeReferenceComponent(receipt: receipt, group: group)
    }

    func unownedSource(_ node: ViewNode) throws {
        let attribution = try XCTUnwrap(scope.registerOrdinaryComponent())
        let group = try XCTUnwrap(attribution.registerGroup(kind: .structure))
        XCTAssertTrue(attribution.recordSourceOutput(node, group: group))
        XCTAssertNotNil(attribution.closeGroup(group))
    }

    func begin() {
        XCTAssertTrue(journal.beginOrdinaryAdoption())
        XCTAssertTrue(journal.markMutationStarted())
    }

    func beginChecked() {
        guard let preparation = journal.preparation() else {
            XCTFail("Missing original native preparation")
            return
        }
        XCTAssertTrue(
            journal.beginAdoption(
                preparation,
                preparedActivity: RetainedLazyListPreparedActivity(
                    preparation: preparation, logicalMembershipPlans: [],
                    ownedComponentPlans: preparation.ownedComponentDeclarations)))
        XCTAssertTrue(journal.markMutationStarted())
    }

    func publish(_ node: ViewNode, attaching: Bool = true) {
        XCTAssertTrue(journal.prepareInsertedNode(from: node))
        if attaching { runtime.root.addChild(node) }
        XCTAssertTrue(node.parent === runtime.root)
        XCTAssertTrue(node.retainedLazyListRuntime === runtime)
        _ = journal.recordAcceptedInsertedNode(on: node)
        _ = journal.recordCompletedNode(from: node, to: node)
    }

    func publishDeclaration(from source: ViewNode, to target: ViewNode) throws {
        XCTAssertTrue(journal.prepareOwnedStructuralDeclaration(from: source, to: target))
        journal.recordAcceptedOwnedStructuralDeclaration(from: source, to: target)
    }

    @discardableResult
    func finish() -> RetainedLazyListAdoptionDisposition {
        let disposition = journal.seal(completedCheckedAdoption: true)
        journal.releaseUnadoptedTransport()
        scope.finish()
        return disposition
    }
}

@MainActor
private final class NativeReferenceWeakProbe {
    weak var node: ViewNode?
    weak var storage: RetainedLazyListNodeActivityStorage?
    weak var runtime: RetainedViewRuntime?
}

@MainActor
private struct NativeReferencePending {
    let original: RetainedOwnedComponentReceipt
    let epoch: NativeReferenceEpoch
    let ticket: RetainedOrdinaryOwnedDeparture
}

@MainActor
@inline(never)
private func makePendingReferenceWithExpiredNode(
    _ runtime: RetainedViewRuntime, probe: NativeReferenceWeakProbe
) throws -> NativeReferencePending {
    let node = referenceNode(1)
    let first = NativeReferenceEpoch(runtime)
    let original = try first.component(nodes: [node], slots: [])
    first.begin()
    first.publish(node)
    _ = first.finish()
    let next = NativeReferenceEpoch(runtime)
    let incoming = referenceNode(2)
    _ = try next.component(nodes: [incoming], slots: [], continuing: original.receipt)
    next.begin()
    let ticket = try XCTUnwrap(
        next.journal.recordOrdinaryPhysicalDeparture(of: node, cause: .acceptedReplacement))
    probe.node = node
    probe.storage = node.retainedLazyListActivityStorage
    runtime.root.removeChild(node)
    XCTAssertNil(node.parent)
    XCTAssertTrue(original.receipt.hasDeclaredComponent)
    withExtendedLifetime(incoming) {}
    return NativeReferencePending(original: original.receipt, epoch: next, ticket: ticket)
}

@MainActor
@inline(never)
private func makeReferenceRemovalAfterRuntimeRelease(
    _ probe: NativeReferenceWeakProbe
) throws -> RetainedOwnedPhysicalDepartureRemoval {
    let runtime = RetainedViewRuntime(root: ViewNode())
    let node = referenceNode(1)
    let first = NativeReferenceEpoch(runtime)
    let original = try first.component(nodes: [node], slots: [RetainedOwnedSlotGenerationID()])
    first.begin()
    first.publish(node)
    _ = first.finish()
    XCTAssertTrue(original.receipt.hasDeclaredComponent)
    let storage = node.lazyListActivityStorage()
    let removal = RetainedOwnedPhysicalDepartureRemoval(
        storage: storage, targetID: storage.targetID, attachmentID: storage.attachmentID)
    probe.node = node
    probe.storage = storage
    probe.runtime = runtime
    runtime.root.removeChild(node)
    return removal
}
