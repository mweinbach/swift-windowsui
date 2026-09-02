import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI

@MainActor
final class OrdinaryOwnedRawWithdrawalTests: XCTestCase {
    func testRawRemovalRetiresLastAcceptedNormalOwnerAndSlotBeforeReturning() async throws {
        let fixture = NormalRawWithdrawalFixture()
        let publication = try fixture.acceptSource(identity: 1)
        fixture.assertOriginalRootIsCurrent()
        XCTAssertEqual(fixture.runtime.root.children.count, 1)
        XCTAssertTrue(fixture.runtime.root.children.first === publication.node)
        XCTAssertTrue(publication.actual.isAttached)
        XCTAssertTrue(publication.contribution.isActive)
        XCTAssertTrue(publication.owned.hasAcceptedOwnership(for: fixture.slot))
        XCTAssertTrue(publication.owned.permitsOwnedWrite(for: fixture.slot))
        XCTAssertTrue(publication.owned.hasDeclaredComponent)

        // The publication journal has finished. This public removal receives
        // neither that journal nor a manually recorded owned departure.
        fixture.runtime.root.removeChild(publication.node)

        XCTAssertTrue(fixture.runtime.root.children.isEmpty)
        XCTAssertNil(publication.node.parent)
        XCTAssertNil(publication.node.retainedLazyListRuntime)
        XCTAssertFalse(publication.actual.isAttached)
        XCTAssertFalse(publication.localOwner.isCurrent)
        XCTAssertFalse(publication.contribution.isActive)
        fixture.assertOriginalRootIsCurrent()
        // Historical acceptance stays recorded; its last native footprint no
        // longer authorizes the escaped original receipt to write or continue.
        XCTAssertTrue(publication.owned.hasAcceptedDeclaration)
        XCTAssertFalse(publication.owned.permitsOwnedWrite(for: fixture.slot))
        XCTAssertFalse(publication.owned.hasAcceptedOwnership(for: fixture.slot))
        XCTAssertFalse(publication.owned.hasDeclaredComponent)
    }

    func testRawRemovalPreservesSeparateAcceptedReferenceUntilItsOwnRemoval() async throws {
        let fixture = NormalRawWithdrawalFixture()
        let first = try fixture.acceptSource(identity: 1)
        let second = try fixture.acceptSource(identity: 2, continuing: first.owned)
        fixture.assertOriginalRootIsCurrent()
        XCTAssertFalse(first.node === second.node)
        XCTAssertFalse(first.actual.target === second.actual.target)
        XCTAssertFalse(first.actual.attachment === second.actual.attachment)
        XCTAssertFalse(first.owned === second.owned)
        XCTAssertTrue(first.owned.owner === second.owned.owner)
        XCTAssertTrue(first.owned.slots.first === fixture.slot)
        XCTAssertTrue(second.owned.slots.first === fixture.slot)
        XCTAssertEqual(fixture.runtime.root.children.count, 2)
        XCTAssertTrue(first.actual.isAttached)
        XCTAssertTrue(second.actual.isAttached)
        XCTAssertTrue(first.contribution.isActive)
        XCTAssertTrue(second.contribution.isActive)

        fixture.runtime.root.removeChild(first.node)

        XCTAssertEqual(fixture.runtime.root.children.count, 1)
        XCTAssertTrue(fixture.runtime.root.children.first === second.node)
        XCTAssertNil(first.node.parent)
        XCTAssertNil(first.node.retainedLazyListRuntime)
        XCTAssertFalse(first.actual.isAttached)
        XCTAssertFalse(first.localOwner.isCurrent)
        XCTAssertFalse(first.contribution.isActive)
        XCTAssertTrue(second.node.parent === fixture.runtime.root)
        XCTAssertTrue(second.node.retainedLazyListRuntime === fixture.runtime)
        XCTAssertTrue(second.actual.isAttached)
        XCTAssertTrue(second.localOwner.isCurrent)
        XCTAssertTrue(second.contribution.isActive)
        fixture.assertOriginalRootIsCurrent()
        // Exact continuation shares the native permission and presence. Losing
        // one actual must not revoke either receipt while the other remains.
        XCTAssertTrue(first.owned.permitsOwnedWrite(for: fixture.slot))
        XCTAssertTrue(second.owned.permitsOwnedWrite(for: fixture.slot))
        XCTAssertTrue(first.owned.hasAcceptedOwnership(for: fixture.slot))
        XCTAssertTrue(second.owned.hasAcceptedOwnership(for: fixture.slot))
        XCTAssertTrue(first.owned.hasDeclaredComponent)
        XCTAssertTrue(second.owned.hasDeclaredComponent)

        fixture.runtime.root.removeChild(second.node)

        XCTAssertTrue(fixture.runtime.root.children.isEmpty)
        XCTAssertNil(second.node.parent)
        XCTAssertNil(second.node.retainedLazyListRuntime)
        XCTAssertFalse(second.actual.isAttached)
        XCTAssertFalse(second.localOwner.isCurrent)
        XCTAssertFalse(second.contribution.isActive)
        fixture.assertOriginalRootIsCurrent()
        XCTAssertTrue(first.owned.hasAcceptedDeclaration)
        XCTAssertTrue(second.owned.hasAcceptedDeclaration)
        XCTAssertFalse(first.owned.permitsOwnedWrite(for: fixture.slot))
        XCTAssertFalse(second.owned.permitsOwnedWrite(for: fixture.slot))
        XCTAssertFalse(first.owned.hasAcceptedOwnership(for: fixture.slot))
        XCTAssertFalse(second.owned.hasAcceptedOwnership(for: fixture.slot))
        XCTAssertFalse(first.owned.hasDeclaredComponent)
        XCTAssertFalse(second.owned.hasDeclaredComponent)
    }

    func testRawRemovalPreservesAcceptedSurvivorDuringTemporaryEmptyParentTable() async throws {
        let fixture = NormalRawWithdrawalFixture()
        let first = try fixture.acceptSource(identity: 1)
        let container = ViewNode()
        fixture.runtime.root.addChild(container)
        // B is accepted directly under Q. Moving it after acceptance would
        // revoke its original attachment and would not model a survivor.
        let survivor = try fixture.acceptSource(identity: 2, continuing: first.owned, parent: container)
        let outgoing = ViewNode()
        container.addChild(outgoing)
        let incoming = ViewNode()
        let survivorStorage = try XCTUnwrap(survivor.node.retainedLazyListActivityStorage)
        let originalTarget = survivor.actual.target
        let originalAttachment = survivor.actual.attachment
        let outgoingIdentity = ObjectIdentifier(outgoing)

        fixture.assertOriginalRootIsCurrent()
        XCTAssertEqual(fixture.runtime.root.children.count, 2)
        XCTAssertTrue(fixture.runtime.root.children.first === first.node)
        XCTAssertTrue(fixture.runtime.root.children.last === container)
        XCTAssertEqual(container.children.count, 2)
        XCTAssertTrue(container.children.first === survivor.node)
        XCTAssertTrue(container.children.last === outgoing)
        XCTAssertTrue(first.actual.isAttached)
        XCTAssertTrue(survivor.actual.isAttached)
        XCTAssertTrue(first.contribution.isActive)
        XCTAssertTrue(survivor.contribution.isActive)
        XCTAssertFalse(first.owned === survivor.owned)
        XCTAssertTrue(first.owned.owner === survivor.owned.owner)
        XCTAssertTrue(first.owned.slots.first === fixture.slot)
        XCTAssertTrue(survivor.owned.slots.first === fixture.slot)
        XCTAssertTrue(survivorStorage.targetID === originalTarget)
        XCTAssertTrue(survivorStorage.attachmentID === originalAttachment)

        var events: [String] = []
        outgoing.onDismantlePlatformView = { departing in
            events.append("outgoing-dismantle")
            XCTAssertEqual(ObjectIdentifier(departing), outgoingIdentity)
            XCTAssertTrue(departing.parent === container)
            XCTAssertTrue(container.children.isEmpty)
            XCTAssertTrue(first.actual.isAttached)
            XCTAssertTrue(survivor.node.parent === container)
            XCTAssertTrue(survivor.node.retainedLazyListRuntime === fixture.runtime)
            XCTAssertTrue(survivor.node.retainedLazyListActivityStorage === survivorStorage)
            XCTAssertTrue(survivorStorage.targetID === originalTarget)
            XCTAssertTrue(survivorStorage.attachmentID === originalAttachment)
            XCTAssertTrue(survivor.localOwner.isCurrent)
            // Physical activity cannot traverse Q's temporary empty table.
            // Neither B's native marker nor its original attachment has left.
            XCTAssertFalse(survivor.actual.isAttached)
            XCTAssertFalse(survivor.contribution.isActive)

            fixture.runtime.root.removeChild(first.node)
            events.append("first-removed")

            XCTAssertTrue(container.children.isEmpty)
            XCTAssertEqual(fixture.runtime.root.children.count, 1)
            XCTAssertTrue(fixture.runtime.root.children.first === container)
            XCTAssertNil(first.node.parent)
            XCTAssertNil(first.node.retainedLazyListRuntime)
            XCTAssertFalse(first.actual.isAttached)
            XCTAssertFalse(first.localOwner.isCurrent)
            XCTAssertFalse(first.contribution.isActive)
            XCTAssertTrue(survivor.node.parent === container)
            XCTAssertTrue(survivor.node.retainedLazyListRuntime === fixture.runtime)
            XCTAssertTrue(survivor.node.retainedLazyListActivityStorage === survivorStorage)
            XCTAssertTrue(survivorStorage.targetID === originalTarget)
            XCTAssertTrue(survivorStorage.attachmentID === originalAttachment)
            XCTAssertTrue(survivor.localOwner.isCurrent)
            XCTAssertFalse(survivor.actual.isAttached)
            fixture.assertOriginalRootIsCurrent()
            // Losing A cannot retire the original P/C shared with surviving B,
            // even while a tree-reachability query cannot currently find B.
            XCTAssertTrue(first.owned.hasAcceptedDeclaration)
            XCTAssertTrue(survivor.owned.hasAcceptedDeclaration)
            XCTAssertTrue(first.owned.permitsOwnedWrite(for: fixture.slot))
            XCTAssertTrue(survivor.owned.permitsOwnedWrite(for: fixture.slot))
            XCTAssertTrue(first.owned.hasAcceptedOwnership(for: fixture.slot))
            XCTAssertTrue(survivor.owned.hasAcceptedOwnership(for: fixture.slot))
            XCTAssertTrue(first.owned.hasDeclaredComponent)
            XCTAssertTrue(survivor.owned.hasDeclaredComponent)
        }
        defer { outgoing.onDismantlePlatformView = nil }

        events.append("replace-begin")
        let result = container.setChildren([survivor.node, incoming])
        events.append("replace-returned")

        XCTAssertEqual(events, ["replace-begin", "outgoing-dismantle", "first-removed", "replace-returned"])
        XCTAssertTrue(result.completed)
        XCTAssertTrue(result.didMutate)
        XCTAssertEqual(result.children.count, 2)
        XCTAssertTrue(result.children.first === survivor.node)
        XCTAssertTrue(result.children.last === incoming)
        XCTAssertEqual(container.children.count, 2)
        XCTAssertTrue(container.children.first === survivor.node)
        XCTAssertTrue(container.children.last === incoming)
        XCTAssertNil(outgoing.parent)
        XCTAssertNil(outgoing.retainedLazyListRuntime)
        XCTAssertTrue(incoming.parent === container)
        XCTAssertTrue(incoming.retainedLazyListRuntime === fixture.runtime)
        XCTAssertTrue(survivor.node.parent === container)
        XCTAssertTrue(survivor.node.retainedLazyListRuntime === fixture.runtime)
        XCTAssertTrue(survivor.node.retainedLazyListActivityStorage === survivorStorage)
        XCTAssertTrue(survivorStorage.targetID === originalTarget)
        XCTAssertTrue(survivorStorage.attachmentID === originalAttachment)
        XCTAssertTrue(survivor.localOwner.isCurrent)
        XCTAssertTrue(survivor.actual.isAttached)
        XCTAssertTrue(survivor.contribution.isActive)
        XCTAssertFalse(first.actual.isAttached)
        XCTAssertFalse(first.contribution.isActive)
        fixture.assertOriginalRootIsCurrent()
        XCTAssertTrue(first.owned.hasAcceptedDeclaration)
        XCTAssertTrue(survivor.owned.hasAcceptedDeclaration)
        XCTAssertTrue(first.owned.permitsOwnedWrite(for: fixture.slot))
        XCTAssertTrue(survivor.owned.permitsOwnedWrite(for: fixture.slot))
        XCTAssertTrue(first.owned.hasAcceptedOwnership(for: fixture.slot))
        XCTAssertTrue(survivor.owned.hasAcceptedOwnership(for: fixture.slot))
        XCTAssertTrue(first.owned.hasDeclaredComponent)
        XCTAssertTrue(survivor.owned.hasDeclaredComponent)
        // The existing raw2 pair separately covers removing the last reference.
    }
}

// These tests exercise native receipt liveness, not an escaped WinSwiftUI
// Binding. Both references carry normal source-bearing publications; no
// declaration-only, empty-group, or descriptor-scope marker is synthesized.
@MainActor
private final class NormalRawWithdrawalFixture {
    let runtime: RetainedViewRuntime
    let slot = RetainedOwnedSlotGenerationID()
    private let originalHost: RetainedLazyListLogicalHostLifetime
    private let originalRootOwner: RetainedLazyListDescriptorOwnerLifetime
    private let originalRootActual: RetainedLazyListActualAttachment

    init() {
        let runtime = RetainedViewRuntime(root: ViewNode())
        self.runtime = runtime
        originalHost = runtime.lazyListLogicalHostLifetime
        let storage = runtime.root.lazyListActivityStorage()
        originalRootOwner = storage.descriptorOwnerLifetime
        originalRootActual = storage.captureActualAttachment(of: runtime.root, in: runtime)
    }

    func acceptSource(
        identity: Int, continuing: RetainedOwnedComponentReceipt? = nil, parent: ViewNode? = nil,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> NormalRawWithdrawalPublication {
        assertOriginalRootIsCurrent(file: file, line: line)
        let destination = parent ?? runtime.root
        XCTAssertTrue(destination.retainedLazyListRuntime === runtime, file: file, line: line)
        let node = ViewNode()
        node.retainedViewIdentity = RetainedViewIdentity().appending(.slot(identity))
        let scope = RetainedLazyListDescriptorBuildScope(
            origin: .componentHostRoot, hostLifetime: originalHost, ownerLifetime: originalRootOwner)
        let journal = RetainedLazyListAdoptionJournal(
            descriptorScope: scope, transaction: RetainedBuildTransaction())
        defer {
            journal.releaseUnadoptedTransport()
            scope.finish()
        }
        let attribution = try XCTUnwrap(scope.registerOrdinaryComponent(), file: file, line: line)
        let owned = try XCTUnwrap(
            attribution.registerOwnedComponent(
                owner: continuing?.owner ?? RetainedOwnedComponentID(), slots: [slot],
                continuing: continuing, declarationOnly: false),
            file: file, line: line)
        let group = try XCTUnwrap(attribution.registerGroup(kind: .observation), file: file, line: line)
        XCTAssertTrue(attribution.recordSourceOutput(node, group: group), file: file, line: line)
        _ = try XCTUnwrap(attribution.closeGroup(group), file: file, line: line)
        let contribution = try XCTUnwrap(attribution.contribution(for: group), file: file, line: line)
        let preparation = try XCTUnwrap(journal.preparation(), file: file, line: line)
        XCTAssertEqual(preparation.ownedComponentDeclarations.count, 1, file: file, line: line)
        let plan = try XCTUnwrap(
            preparation.ownedComponentDeclarations.first { $0.receipt === owned }, file: file, line: line)
        XCTAssertFalse(plan.declarationOnly, file: file, line: line)
        XCTAssertEqual(plan.sourcePayloads.count, 1, file: file, line: line)
        XCTAssertTrue(owned.isDescriptorOwnership, file: file, line: line)
        XCTAssertFalse(owned.hasAcceptedDeclaration, file: file, line: line)
        XCTAssertTrue(journal.beginOrdinaryAdoption(), file: file, line: line)
        XCTAssertTrue(journal.prepareInsertedNode(from: node), file: file, line: line)
        XCTAssertTrue(journal.markMutationStarted(), file: file, line: line)

        destination.addChild(node)
        XCTAssertTrue(node.parent === destination, file: file, line: line)
        XCTAssertTrue(node.retainedLazyListRuntime === runtime, file: file, line: line)
        _ = journal.recordAcceptedInsertedNode(on: node)
        _ = journal.recordCompletedNode(from: node, to: node)
        let disposition = journal.seal(completedCheckedAdoption: true)
        // Insertion and completion each publish this same normal plan. These
        // are two facts for one physical attachment, not two owned references.
        let facts = disposition.acceptedOwnedComponents
        XCTAssertEqual(facts.count, 2, file: file, line: line)
        let insertion = try XCTUnwrap(facts.first, file: file, line: line)
        let completion = try XCTUnwrap(facts.last, file: file, line: line)
        XCTAssertFalse(insertion.actual === completion.actual, file: file, line: line)
        let storage = node.lazyListActivityStorage()
        for fact in facts {
            XCTAssertTrue(fact.plan === plan, file: file, line: line)
            switch fact.kind {
            case .structuralEntry:
                break
            default:
                XCTFail("Expected a normal source publication", file: file, line: line)
            }
            let payload = try XCTUnwrap(fact.sourcePayload, file: file, line: line)
            XCTAssertTrue(plan.sourcePayloads.contains { $0 === payload }, file: file, line: line)
            XCTAssertTrue(fact.plan.receipt === owned, file: file, line: line)
            XCTAssertEqual(fact.slots.count, 1, file: file, line: line)
            XCTAssertTrue(fact.slots.first === slot, file: file, line: line)
            XCTAssertTrue(fact.actual.node === node, file: file, line: line)
            XCTAssertTrue(fact.actual.target === storage.targetID, file: file, line: line)
            XCTAssertTrue(fact.actual.attachment === storage.attachmentID, file: file, line: line)
            XCTAssertTrue(fact.actual.isAttached, file: file, line: line)
        }
        XCTAssertTrue(contribution.isActive, file: file, line: line)
        XCTAssertTrue(owned.hasAcceptedDeclaration, file: file, line: line)
        XCTAssertTrue(owned.hasAcceptedOwnership(for: slot), file: file, line: line)
        XCTAssertTrue(owned.permitsOwnedWrite(for: slot), file: file, line: line)
        XCTAssertTrue(owned.hasDeclaredComponent, file: file, line: line)
        XCTAssertTrue(disposition.retiredOwnedSlots.isEmpty, file: file, line: line)
        XCTAssertTrue(disposition.retiredOwnedComponents.isEmpty, file: file, line: line)
        XCTAssertFalse(storage.descriptorOwnerLifetime === originalRootOwner, file: file, line: line)
        XCTAssertTrue(storage.descriptorOwnerLifetime.isCurrent, file: file, line: line)
        return NormalRawWithdrawalPublication(
            node: node, owned: owned, contribution: contribution, actual: insertion.actual,
            localOwner: storage.descriptorOwnerLifetime)
    }

    func assertOriginalRootIsCurrent(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(runtime.lazyListLogicalHostLifetime === originalHost, file: file, line: line)
        XCTAssertTrue(originalHost.isOpen, file: file, line: line)
        XCTAssertTrue(
            runtime.root.lazyListActivityStorage().descriptorOwnerLifetime === originalRootOwner,
            file: file, line: line)
        XCTAssertTrue(originalRootOwner.isCurrent, file: file, line: line)
        XCTAssertTrue(originalRootActual.isAttached, file: file, line: line)
    }
}

@MainActor
private struct NormalRawWithdrawalPublication {
    let node: ViewNode
    let owned: RetainedOwnedComponentReceipt
    let contribution: RetainedDescriptorContributionReceipt
    let actual: RetainedLazyListActualAttachment
    let localOwner: RetainedLazyListDescriptorOwnerLifetime
}
