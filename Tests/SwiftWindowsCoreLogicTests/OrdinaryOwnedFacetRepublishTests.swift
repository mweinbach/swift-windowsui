import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI

@MainActor
final class OrdinaryOwnedFacetRepublishTests: XCTestCase {
    func testPendingCleanupPreservesTheSameOwnerAndSlotRepublishedOnTheOriginalNode() async throws {
        let fixture = try OwnedFacetRepublishFixture()
        let incoming = republishNode(2)
        let next = OwnedFacetRepublishEpoch(fixture.runtime)
        let continued = try next.component(nodes: [incoming], slots: [fixture.slot], continuing: fixture.owned)
        XCTAssertTrue(next.journal.beginOrdinaryAdoption())
        let ticket = try XCTUnwrap(
            next.journal.recordOrdinaryPhysicalDeparture(of: fixture.old, cause: .acceptedReplacement))
        let intervening = OwnedFacetRepublishEpoch(fixture.runtime)
        let republished = try intervening.component(
            nodes: [fixture.old], slots: [fixture.slot], continuing: fixture.owned)
        XCTAssertTrue(intervening.journal.beginOrdinaryAdoption())
        intervening.publish(fixture.old, attaching: false)
        XCTAssertTrue(republished.owned.owner === fixture.owned.owner)
        XCTAssertTrue(republished.owned.hasAcceptedDeclaration)
        XCTAssertTrue(republished.contribution.isActive)
        XCTAssertFalse(republished.owned.permitsOwnedWrite(for: fixture.slot))
        next.publish(incoming, attaching: true)

        next.journal.finishOrdinaryOwnedDeparture(ticket)
        next.journal.finishOrdinaryOwnedDeparture(ticket)
        XCTAssertTrue(continued.owned.hasAcceptedOwnership(for: fixture.slot))
        _ = next.journal.recordPhysicalDeparture(of: incoming, cause: .acceptedReplacement)

        XCTAssertTrue(fixture.old.parent === fixture.runtime.root)
        XCTAssertTrue(republished.owned.hasAcceptedOwnership(for: fixture.slot))
        XCTAssertTrue(fixture.owned.hasDeclaredComponent)
        XCTAssertFalse(next.finish().retiredOwnedSlots.contains { $0 === fixture.slot })
        _ = intervening.journal.recordPhysicalDeparture(of: fixture.old, cause: .acceptedReplacement)
        XCTAssertFalse(fixture.owned.permitsOwnedWrite(for: fixture.slot))
        XCTAssertFalse(fixture.owned.hasDeclaredComponent)
        let disposition = intervening.finish()
        XCTAssertEqual(disposition.retiredOwnedSlots.filter { $0 === fixture.slot }.count, 1)
        XCTAssertEqual(disposition.retiredOwnedComponents.filter { $0 === fixture.owned.owner }.count, 1)
    }

    func testTheSameEmptyAnchorObjectCanRepublishTheOriginalOwnerAndSlot() async throws {
        let runtime = RetainedViewRuntime(root: ViewNode())
        let old = republishNode(1)
        runtime.root.addChild(old)
        let slot = RetainedOwnedSlotGenerationID()
        let anchor = old.lazyListActivityStorage().captureActualAttachment(of: old, in: runtime)
        let first = OwnedFacetRepublishEpoch(runtime)
        let original = try first.component(nodes: [], slots: [slot])
        XCTAssertTrue(first.journal.beginOrdinaryAdoption())
        let firstEmpty = first.journal.recordAcceptedOrdinaryEmptyGroups(
            structuralAnchor: anchor, groups: [original.group])
        XCTAssertEqual(firstEmpty.count, 1)
        XCTAssertTrue(try XCTUnwrap(firstEmpty.first).structuralAnchor === anchor)
        XCTAssertTrue(original.owned.hasAcceptedOwnership(for: slot))
        _ = first.finish()
        let incoming = republishNode(2)
        let next = OwnedFacetRepublishEpoch(runtime)
        _ = try next.component(nodes: [incoming], slots: [slot], continuing: original.owned)
        XCTAssertTrue(next.journal.beginOrdinaryAdoption())
        let ticket = try XCTUnwrap(next.journal.recordOrdinaryPhysicalDeparture(of: old, cause: .acceptedReplacement))
        let intervening = OwnedFacetRepublishEpoch(runtime)
        let repeated = try intervening.component(nodes: [], slots: [slot], continuing: original.owned)
        XCTAssertTrue(intervening.journal.beginOrdinaryAdoption())
        let laterEmpty = intervening.journal.recordAcceptedOrdinaryEmptyGroups(
            structuralAnchor: anchor, groups: [repeated.group])
        XCTAssertEqual(laterEmpty.count, 1)
        XCTAssertTrue(try XCTUnwrap(laterEmpty.first).structuralAnchor === anchor)
        XCTAssertTrue(repeated.owned.hasAcceptedDeclaration)
        XCTAssertTrue(repeated.contribution.isActive)
        XCTAssertFalse(repeated.owned.permitsOwnedWrite(for: slot))
        next.publish(incoming, attaching: true)

        next.journal.finishOrdinaryOwnedDeparture(ticket)
        _ = next.journal.recordPhysicalDeparture(of: incoming, cause: .acceptedReplacement)

        XCTAssertTrue(anchor.isAttached)
        XCTAssertTrue(repeated.owned.hasAcceptedOwnership(for: slot))
        XCTAssertTrue(original.owned.hasDeclaredComponent)
        XCTAssertTrue(next.finish().retiredOwnedSlots.isEmpty)
        _ = intervening.journal.recordPhysicalDeparture(of: old, cause: .acceptedReplacement)
        XCTAssertFalse(original.owned.permitsOwnedWrite(for: slot))
        XCTAssertFalse(original.owned.hasDeclaredComponent)
        XCTAssertEqual(intervening.finish().retiredOwnedSlots.filter { $0 === slot }.count, 1)
    }

    func testALaterAcceptedDeclaredMarkerPreservesTheSameOwnerAndSlot() async throws {
        let fixture = try OwnedFacetRepublishFixture()
        let incoming = republishNode(2)
        let next = OwnedFacetRepublishEpoch(fixture.runtime)
        _ = try next.component(nodes: [incoming], slots: [fixture.slot], continuing: fixture.owned)
        XCTAssertTrue(next.journal.beginOrdinaryAdoption())
        let declarationSource = republishNode(3)
        let intervening = OwnedFacetRepublishEpoch(fixture.runtime)
        let declared = try intervening.component(
            nodes: [declarationSource], slots: [fixture.slot], continuing: fixture.owned, declarationOnly: true)
        XCTAssertTrue(intervening.journal.beginOrdinaryAdoption())
        let ticket = try XCTUnwrap(
            next.journal.recordOrdinaryPhysicalDeparture(of: fixture.old, cause: .acceptedReplacement))
        XCTAssertTrue(declarationSource.children.isEmpty)
        XCTAssertTrue(fixture.old.children.isEmpty)
        XCTAssertTrue(
            intervening.journal.prepareOwnedStructuralDeclaration(from: declarationSource, to: fixture.old))
        // The complete children field is exactly unchanged; this native API
        // explicitly accepts that field without an intermediate mutation.
        intervening.journal.recordAcceptedOwnedStructuralDeclaration(from: declarationSource, to: fixture.old)
        XCTAssertTrue(declared.owned.hasAcceptedDeclaration)
        XCTAssertFalse(declared.owned.permitsOwnedWrite(for: fixture.slot))
        next.publish(incoming, attaching: true)

        next.journal.finishOrdinaryOwnedDeparture(ticket)
        _ = next.journal.recordPhysicalDeparture(of: incoming, cause: .acceptedReplacement)

        XCTAssertTrue(declared.owned.hasAcceptedOwnership(for: fixture.slot))
        XCTAssertTrue(fixture.owned.hasDeclaredComponent)
        XCTAssertTrue(next.finish().retiredOwnedSlots.isEmpty)
        _ = intervening.journal.recordPhysicalDeparture(of: fixture.old, cause: .acceptedReplacement)
        XCTAssertFalse(fixture.owned.permitsOwnedWrite(for: fixture.slot))
        XCTAssertFalse(fixture.owned.hasDeclaredComponent)
        XCTAssertEqual(intervening.finish().retiredOwnedSlots.filter { $0 === fixture.slot }.count, 1)
    }

    func testPayloadPreservationRequiresTheExactRepublishedField() async throws {
        let fixture = try OwnedFacetRepublishFixture(includeDisappear: true, includeIdentityPayload: false)
        let incoming = republishNode(2)
        let next = OwnedFacetRepublishEpoch(fixture.runtime)
        _ = try next.component(nodes: [incoming], slots: [fixture.slot], continuing: fixture.owned)
        XCTAssertTrue(next.journal.beginOrdinaryAdoption())
        let ticket = try XCTUnwrap(
            next.journal.recordOrdinaryPhysicalDeparture(of: fixture.old, cause: .acceptedReplacement))
        fixture.old.onDisappear = nil
        let intervening = OwnedFacetRepublishEpoch(fixture.runtime)
        let republished = try intervening.component(
            nodes: [fixture.old], slots: [fixture.slot], continuing: fixture.owned)
        XCTAssertTrue(intervening.journal.beginOrdinaryAdoption())
        intervening.publish(fixture.old, attaching: false)
        next.publish(incoming, attaching: true)
        next.journal.finishOrdinaryOwnedDeparture(ticket)
        let replacement = OwnedFacetRepublishEpoch(fixture.runtime)
        let source = republishNode(3)
        _ = try replacement.component(nodes: [source], slots: [])
        XCTAssertTrue(replacement.journal.beginOrdinaryAdoption())
        _ = replacement.journal.recordCompletedNode(from: source, to: fixture.old)
        _ = next.journal.recordPhysicalDeparture(of: incoming, cause: .acceptedReplacement)

        // Both structural footprints are gone. Only the later onAppear field
        // can keep this exact slot and component alive now.
        XCTAssertTrue(republished.owned.hasAcceptedOwnership(for: fixture.slot))
        XCTAssertTrue(fixture.owned.hasDeclaredComponent)
        XCTAssertTrue(
            replacement.journal.preparePropertyCopy(from: source, to: fixture.old, keyPath: \ViewNode.onAppear))
        fixture.old.onAppear = nil
        _ = replacement.journal.recordAcceptedProperty(from: source, to: fixture.old, keyPath: \ViewNode.onAppear)

        // The old onDisappear facet was not republished and cannot survive the
        // original pending cleanup to mask removal of that final onAppear field.
        XCTAssertFalse(fixture.owned.permitsOwnedWrite(for: fixture.slot))
        XCTAssertFalse(fixture.owned.hasDeclaredComponent)
        XCTAssertEqual(replacement.finish().retiredOwnedSlots.filter { $0 === fixture.slot }.count, 1)
        _ = intervening.finish()
        _ = next.finish()
    }

    func testADifferentLaterMemberDoesNotPreserveTheOriginalPermission() async throws {
        let fixture = try OwnedFacetRepublishFixture()
        let incoming = republishNode(2)
        let next = OwnedFacetRepublishEpoch(fixture.runtime)
        _ = try next.component(nodes: [incoming], slots: [fixture.slot], continuing: fixture.owned)
        XCTAssertTrue(next.journal.beginOrdinaryAdoption())
        let ticket = try XCTUnwrap(
            next.journal.recordOrdinaryPhysicalDeparture(of: fixture.old, cause: .acceptedReplacement))
        let intervening = OwnedFacetRepublishEpoch(fixture.runtime)
        let otherSlot = RetainedOwnedSlotGenerationID()
        let other = try intervening.component(nodes: [fixture.old], slots: [otherSlot])
        XCTAssertTrue(intervening.journal.beginOrdinaryAdoption())
        intervening.publish(fixture.old, attaching: false)
        next.publish(incoming, attaching: true)

        next.journal.finishOrdinaryOwnedDeparture(ticket)
        _ = next.journal.recordPhysicalDeparture(of: incoming, cause: .acceptedReplacement)

        XCTAssertFalse(fixture.owned.permitsOwnedWrite(for: fixture.slot))
        XCTAssertFalse(fixture.owned.hasDeclaredComponent)
        XCTAssertTrue(other.owned.hasAcceptedOwnership(for: otherSlot))
        XCTAssertEqual(next.finish().retiredOwnedSlots.filter { $0 === fixture.slot }.count, 1)
        _ = intervening.journal.recordPhysicalDeparture(of: fixture.old, cause: .acceptedReplacement)
        XCTAssertFalse(other.owned.permitsOwnedWrite(for: otherSlot))
        XCTAssertEqual(intervening.finish().retiredOwnedSlots.filter { $0 === otherSlot }.count, 1)
    }

    func testAnExpiredOriginalStorageCannotPreserveAnUnpublishedOldFacet() async throws {
        let fixture = try OwnedFacetRepublishFixture()
        let incoming = republishNode(2)
        let next = OwnedFacetRepublishEpoch(fixture.runtime)
        _ = try next.component(nodes: [incoming], slots: [fixture.slot], continuing: fixture.owned)
        XCTAssertTrue(next.journal.beginOrdinaryAdoption())
        let ticket = try XCTUnwrap(
            next.journal.recordOrdinaryPhysicalDeparture(of: fixture.old, cause: .acceptedReplacement))
        weak var originalStorage = fixture.old.retainedLazyListActivityStorage
        fixture.old.retainedLazyListActivityStorage = nil
        XCTAssertNil(originalStorage)
        next.publish(incoming, attaching: true)

        next.journal.finishOrdinaryOwnedDeparture(ticket)
        _ = next.journal.recordPhysicalDeparture(of: incoming, cause: .acceptedReplacement)

        XCTAssertFalse(fixture.owned.permitsOwnedWrite(for: fixture.slot))
        XCTAssertFalse(fixture.owned.hasDeclaredComponent)
        XCTAssertEqual(next.finish().retiredOwnedSlots.filter { $0 === fixture.slot }.count, 1)
    }

    func testAReplacementStorageKeepsItsIndependentSameOwnerPublication() async throws {
        let fixture = try OwnedFacetRepublishFixture()
        let originalStorage = fixture.old.lazyListActivityStorage()
        let incoming = republishNode(2)
        let next = OwnedFacetRepublishEpoch(fixture.runtime)
        _ = try next.component(nodes: [incoming], slots: [fixture.slot], continuing: fixture.owned)
        XCTAssertTrue(next.journal.beginOrdinaryAdoption())
        let ticket = try XCTUnwrap(
            next.journal.recordOrdinaryPhysicalDeparture(of: fixture.old, cause: .acceptedReplacement))
        fixture.old.retainedLazyListActivityStorage = RetainedLazyListNodeActivityStorage()
        XCTAssertFalse(fixture.old.lazyListActivityStorage() === originalStorage)
        let intervening = OwnedFacetRepublishEpoch(fixture.runtime)
        let republished = try intervening.component(
            nodes: [fixture.old], slots: [fixture.slot], continuing: fixture.owned)
        XCTAssertTrue(intervening.journal.beginOrdinaryAdoption())
        intervening.publish(fixture.old, attaching: false)
        next.publish(incoming, attaching: true)

        next.journal.finishOrdinaryOwnedDeparture(ticket)
        _ = next.journal.recordPhysicalDeparture(of: incoming, cause: .acceptedReplacement)

        XCTAssertTrue(republished.owned.hasAcceptedOwnership(for: fixture.slot))
        XCTAssertTrue(fixture.owned.hasDeclaredComponent)
        XCTAssertTrue(next.finish().retiredOwnedSlots.isEmpty)
        _ = intervening.journal.recordPhysicalDeparture(of: fixture.old, cause: .acceptedReplacement)
        XCTAssertFalse(fixture.owned.permitsOwnedWrite(for: fixture.slot))
        XCTAssertEqual(intervening.finish().retiredOwnedSlots.filter { $0 === fixture.slot }.count, 1)
        withExtendedLifetime(originalStorage) {}
    }

    func testAChangedAttachmentKeepsItsIndependentSameOwnerPublication() async throws {
        let fixture = try OwnedFacetRepublishFixture()
        let storage = fixture.old.lazyListActivityStorage()
        let originalAttachment = storage.attachmentID
        let incoming = republishNode(2)
        let next = OwnedFacetRepublishEpoch(fixture.runtime)
        _ = try next.component(nodes: [incoming], slots: [fixture.slot], continuing: fixture.owned)
        XCTAssertTrue(next.journal.beginOrdinaryAdoption())
        let ticket = try XCTUnwrap(
            next.journal.recordOrdinaryPhysicalDeparture(of: fixture.old, cause: .acceptedReplacement))
        storage.revokeAttachment()
        XCTAssertFalse(storage.attachmentID === originalAttachment)
        let intervening = OwnedFacetRepublishEpoch(fixture.runtime)
        let republished = try intervening.component(
            nodes: [fixture.old], slots: [fixture.slot], continuing: fixture.owned)
        XCTAssertTrue(intervening.journal.beginOrdinaryAdoption())
        intervening.publish(fixture.old, attaching: false)
        next.publish(incoming, attaching: true)

        next.journal.finishOrdinaryOwnedDeparture(ticket)
        _ = next.journal.recordPhysicalDeparture(of: incoming, cause: .acceptedReplacement)

        XCTAssertTrue(republished.owned.hasAcceptedOwnership(for: fixture.slot))
        XCTAssertTrue(fixture.owned.hasDeclaredComponent)
        XCTAssertTrue(next.finish().retiredOwnedSlots.isEmpty)
        _ = intervening.journal.recordPhysicalDeparture(of: fixture.old, cause: .acceptedReplacement)
        XCTAssertFalse(fixture.owned.permitsOwnedWrite(for: fixture.slot))
        XCTAssertEqual(intervening.finish().retiredOwnedSlots.filter { $0 === fixture.slot }.count, 1)
    }

    func testTheNativeOneShotCannotClearASecondPublication() async throws {
        let fixture = try OwnedFacetRepublishFixture()
        let storage = fixture.old.lazyListActivityStorage()
        let removal = RetainedOwnedPhysicalDepartureRemoval(
            storage: storage, targetID: storage.targetID, attachmentID: storage.attachmentID)
        XCTAssertNil(removal.successfullyClearedOriginalStorage)
        removal.removeOriginalMapsOnce()
        XCTAssertTrue(removal.successfullyClearedOriginalStorage === storage)
        let intervening = OwnedFacetRepublishEpoch(fixture.runtime)
        let republished = try intervening.component(
            nodes: [fixture.old], slots: [fixture.slot], continuing: fixture.owned)
        XCTAssertTrue(intervening.journal.beginOrdinaryAdoption())
        intervening.publish(fixture.old, attaching: false)

        removal.removeOriginalMapsOnce()
        XCTAssertTrue(republished.owned.hasAcceptedOwnership(for: fixture.slot))
        _ = intervening.journal.recordPhysicalDeparture(of: fixture.old, cause: .acceptedReplacement)

        // The second publication's map must still be present for its own real
        // departure to find and retire this exact original slot and component.
        XCTAssertFalse(fixture.owned.permitsOwnedWrite(for: fixture.slot))
        XCTAssertFalse(fixture.owned.hasDeclaredComponent)
        XCTAssertEqual(intervening.finish().retiredOwnedSlots.filter { $0 === fixture.slot }.count, 1)
    }

    func testARefusedOriginalClearNeverAcknowledgesLaterMatchingMembers() async throws {
        let fixture = try OwnedFacetRepublishFixture()
        let storage = fixture.old.lazyListActivityStorage()
        let removal = RetainedOwnedPhysicalDepartureRemoval(
            storage: storage, targetID: storage.targetID, attachmentID: storage.attachmentID)
        storage.revokeAttachment()
        let intervening = OwnedFacetRepublishEpoch(fixture.runtime)
        let republished = try intervening.component(
            nodes: [fixture.old], slots: [fixture.slot], continuing: fixture.owned)
        XCTAssertTrue(intervening.journal.beginOrdinaryAdoption())
        intervening.publish(fixture.old, attaching: false)

        removal.removeOriginalMapsOnce()
        removal.removeOriginalMapsOnce()

        XCTAssertNil(removal.successfullyClearedOriginalStorage)
        XCTAssertTrue(republished.owned.hasAcceptedOwnership(for: fixture.slot))
        _ = intervening.journal.recordPhysicalDeparture(of: fixture.old, cause: .acceptedReplacement)
        XCTAssertFalse(fixture.owned.permitsOwnedWrite(for: fixture.slot))
        XCTAssertFalse(fixture.owned.hasDeclaredComponent)
        XCTAssertEqual(intervening.finish().retiredOwnedSlots.filter { $0 === fixture.slot }.count, 1)
    }

    func testTheNativeOneShotDoesNotRetainExpiredStorageBeforeOrAfterClearing() async throws {
        for clearBeforeRelease in [false, true] {
            let probe = OwnedFacetStorageProbe()
            let removal = makeExpiredFacetRemoval(probe, clearBeforeRelease: clearBeforeRelease)

            XCTAssertNil(probe.storage)
            removal.removeOriginalMapsOnce()
            XCTAssertNil(removal.successfullyClearedOriginalStorage)
        }
        let absent = RetainedOwnedPhysicalDepartureRemoval(
            storage: nil, targetID: RetainedLazyListTargetID(), attachmentID: RetainedLazyListAttachmentID())
        absent.removeOriginalMapsOnce()
        XCTAssertNil(absent.successfullyClearedOriginalStorage)
    }
}

@MainActor
private func republishNode(_ identity: Int) -> ViewNode {
    let node = ViewNode()
    node.retainedViewIdentity = RetainedViewIdentity().appending(.slot(identity))
    return node
}

@MainActor
private final class OwnedFacetRepublishEpoch {
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
        nodes: [ViewNode], slots: [RetainedOwnedSlotGenerationID], continuing: RetainedOwnedComponentReceipt? = nil,
        declarationOnly: Bool = false
    ) throws -> OwnedFacetRepublishComponent {
        let attribution = try XCTUnwrap(scope.registerOrdinaryComponent())
        let owned = try XCTUnwrap(
            attribution.registerOwnedComponent(
                owner: continuing?.owner ?? RetainedOwnedComponentID(), slots: slots,
                continuing: continuing, declarationOnly: declarationOnly))
        let group = try XCTUnwrap(attribution.registerGroup(kind: .observation))
        for node in nodes { XCTAssertTrue(attribution.recordSourceOutput(node, group: group)) }
        _ = try XCTUnwrap(attribution.closeGroup(group))
        return OwnedFacetRepublishComponent(
            owned: owned, group: group, contribution: try XCTUnwrap(attribution.contribution(for: group)))
    }

    func publish(_ node: ViewNode, attaching: Bool) {
        XCTAssertTrue(journal.prepareInsertedNode(from: node))
        if attaching { runtime.root.addChild(node) }
        XCTAssertTrue(node.parent === runtime.root)
        _ = journal.recordAcceptedInsertedNode(on: node)
        _ = journal.recordCompletedNode(from: node, to: node)
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
private struct OwnedFacetRepublishComponent {
    let owned: RetainedOwnedComponentReceipt
    let group: RetainedDescriptorGroupID
    let contribution: RetainedDescriptorContributionReceipt
}

@MainActor
private final class OwnedFacetRepublishFixture {
    let runtime = RetainedViewRuntime(root: ViewNode())
    let old = republishNode(1)
    let slot = RetainedOwnedSlotGenerationID()
    let owned: RetainedOwnedComponentReceipt

    init(includeDisappear: Bool = false, includeIdentityPayload: Bool = true) throws {
        if !includeIdentityPayload { old.retainedViewIdentity = nil }
        old.onAppear = {}
        if includeDisappear { old.onDisappear = {} }
        let first = OwnedFacetRepublishEpoch(runtime)
        owned = try first.component(nodes: [old], slots: [slot]).owned
        XCTAssertTrue(first.journal.beginOrdinaryAdoption())
        first.publish(old, attaching: true)
        XCTAssertTrue(owned.hasAcceptedOwnership(for: slot))
        _ = first.finish()
    }
}

@MainActor
private final class OwnedFacetStorageProbe {
    weak var storage: RetainedLazyListNodeActivityStorage?
}

@MainActor
@inline(never)
private func makeExpiredFacetRemoval(
    _ probe: OwnedFacetStorageProbe, clearBeforeRelease: Bool
) -> RetainedOwnedPhysicalDepartureRemoval {
    let storage = RetainedLazyListNodeActivityStorage()
    probe.storage = storage
    let removal = RetainedOwnedPhysicalDepartureRemoval(
        storage: storage, targetID: storage.targetID, attachmentID: storage.attachmentID)
    if clearBeforeRelease {
        removal.removeOriginalMapsOnce()
        XCTAssertTrue(removal.successfullyClearedOriginalStorage === storage)
    }
    return removal
}
