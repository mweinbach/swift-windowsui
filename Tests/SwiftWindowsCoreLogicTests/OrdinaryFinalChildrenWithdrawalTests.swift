import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI

@MainActor
final class OrdinaryFinalChildrenWithdrawalTests: XCTestCase {
    func testFinalWriteRetiresCallbackInstalledAcceptedNormalReferenceBeforeReturn() async throws {
        let fixture = FinalChildrenWithdrawalFixture()
        let outgoing = ViewNode()
        fixture.runtime.root.addChild(outgoing)
        let incoming = ViewNode()
        var late: FinalChildrenWithdrawalPublication?
        var callbackError: Error?
        var events: [String] = []
        outgoing.onDismantlePlatformView = { departing in
            events.append("outgoing-dismantle")
            XCTAssertTrue(departing === outgoing)
            XCTAssertTrue(departing.parent === fixture.runtime.root)
            XCTAssertTrue(fixture.runtime.root.children.isEmpty)
            do {
                let publication = try fixture.acceptSource(identity: 1)
                late = publication
                XCTAssertEqual(publication.owned.slots.count, 1)
                XCTAssertEqual(fixture.runtime.root.children.count, 1)
                XCTAssertTrue(fixture.runtime.root.children.first === publication.node)
                XCTAssertTrue(publication.actual.isAttached)
                XCTAssertTrue(publication.contribution.isActive)
                publication.assertOwnershipIsLive()
                fixture.assertOriginalRootIsCurrent()
            } catch {
                callbackError = error
            }
        }
        defer { outgoing.onDismantlePlatformView = nil }

        events.append("replace-begin")
        let result = fixture.runtime.root.setChildren([incoming])
        events.append("replace-returned")

        if let callbackError { throw callbackError }
        let publication = try XCTUnwrap(late)
        XCTAssertEqual(events, ["replace-begin", "outgoing-dismantle", "replace-returned"])
        XCTAssertTrue(result.completed)
        XCTAssertTrue(result.didMutate)
        XCTAssertEqual(result.children.count, 1)
        XCTAssertTrue(result.children.first === incoming)
        XCTAssertEqual(fixture.runtime.root.children.count, 1)
        XCTAssertTrue(fixture.runtime.root.children.first === incoming)
        XCTAssertTrue(incoming.parent === fixture.runtime.root)
        XCTAssertTrue(incoming.retainedLazyListRuntime === fixture.runtime)
        // No reload, second removal, or asynchronous turn can settle this cut
        // on the setter's behalf. Keep the escaped node and receipt alive.
        publication.assertWithdrawn()
        fixture.assertOriginalRootIsCurrent()
    }

    func testFinalWriteRetiresCallbackInstalledZeroSlotComponentBeforeReturn() async throws {
        let fixture = FinalChildrenWithdrawalFixture()
        let outgoing = ViewNode()
        fixture.runtime.root.addChild(outgoing)
        let incoming = ViewNode()
        var late: FinalChildrenWithdrawalPublication?
        var callbackError: Error?
        var callbackCount = 0
        outgoing.onDismantlePlatformView = { departing in
            callbackCount += 1
            XCTAssertTrue(departing === outgoing)
            XCTAssertTrue(fixture.runtime.root.children.isEmpty)
            do {
                let publication = try fixture.acceptSource(identity: 1, slots: [])
                late = publication
                XCTAssertTrue(publication.owned.slots.isEmpty)
                XCTAssertEqual(fixture.runtime.root.children.count, 1)
                XCTAssertTrue(fixture.runtime.root.children.first === publication.node)
                XCTAssertTrue(publication.actual.isAttached)
                XCTAssertTrue(publication.contribution.isActive)
                XCTAssertTrue(publication.owned.hasAcceptedDeclaration)
                XCTAssertTrue(publication.owned.hasDeclaredComponent)
            } catch {
                callbackError = error
            }
        }
        defer { outgoing.onDismantlePlatformView = nil }

        let result = fixture.runtime.root.setChildren([incoming])

        if let callbackError { throw callbackError }
        let publication = try XCTUnwrap(late)
        XCTAssertEqual(callbackCount, 1)
        XCTAssertTrue(result.completed)
        XCTAssertTrue(result.didMutate)
        XCTAssertEqual(result.children.count, 1)
        XCTAssertTrue(result.children.first === incoming)
        XCTAssertEqual(fixture.runtime.root.children.count, 1)
        XCTAssertTrue(fixture.runtime.root.children.first === incoming)
        XCTAssertTrue(incoming.parent === fixture.runtime.root)
        XCTAssertTrue(incoming.retainedLazyListRuntime === fixture.runtime)
        XCTAssertTrue(publication.owned.slots.isEmpty)
        XCTAssertFalse(publication.actual.isAttached)
        XCTAssertFalse(publication.contribution.isActive)
        XCTAssertTrue(publication.owned.hasAcceptedDeclaration)
        // Component presence must retire even though there are no slots.
        XCTAssertFalse(publication.owned.hasDeclaredComponent)
        fixture.assertOriginalRootIsCurrent()
    }

    func testFinalWritePreservesSeparateAcceptedReferenceUntilItsOwnWithdrawal() async throws {
        let fixture = FinalChildrenWithdrawalFixture()
        let survivor = try fixture.acceptSource(identity: 1)
        let container = ViewNode()
        fixture.runtime.root.addChild(container)
        let outgoing = ViewNode()
        container.addChild(outgoing)
        let incoming = ViewNode()
        var late: FinalChildrenWithdrawalPublication?
        var callbackError: Error?
        var callbackCount = 0
        outgoing.onDismantlePlatformView = { departing in
            callbackCount += 1
            XCTAssertTrue(departing === outgoing)
            XCTAssertTrue(container.children.isEmpty)
            XCTAssertTrue(survivor.actual.isAttached)
            do {
                let publication = try fixture.acceptSource(
                    identity: 2, continuing: survivor.owned, parent: container)
                late = publication
                XCTAssertFalse(publication.owned === survivor.owned)
                XCTAssertTrue(publication.owned.owner === survivor.owned.owner)
                XCTAssertTrue(publication.owned.slots.first === fixture.slot)
                XCTAssertFalse(publication.actual.target === survivor.actual.target)
                XCTAssertFalse(publication.actual.attachment === survivor.actual.attachment)
                XCTAssertTrue(publication.actual.isAttached)
                XCTAssertTrue(publication.contribution.isActive)
                XCTAssertEqual(container.children.count, 1)
                XCTAssertTrue(container.children.first === publication.node)
                publication.assertOwnershipIsLive()
                survivor.assertOwnershipIsLive()
            } catch {
                callbackError = error
            }
        }
        defer { outgoing.onDismantlePlatformView = nil }

        let result = container.setChildren([incoming])

        if let callbackError { throw callbackError }
        let publication = try XCTUnwrap(late)
        XCTAssertEqual(callbackCount, 1)
        XCTAssertTrue(result.completed)
        XCTAssertTrue(result.didMutate)
        XCTAssertEqual(result.children.count, 1)
        XCTAssertTrue(result.children.first === incoming)
        XCTAssertEqual(container.children.count, 1)
        XCTAssertTrue(container.children.first === incoming)
        XCTAssertTrue(incoming.parent === container)
        XCTAssertTrue(incoming.retainedLazyListRuntime === fixture.runtime)
        XCTAssertFalse(publication.actual.isAttached)
        XCTAssertFalse(publication.contribution.isActive)
        XCTAssertTrue(survivor.node.parent === fixture.runtime.root)
        XCTAssertTrue(survivor.actual.isAttached)
        XCTAssertTrue(survivor.contribution.isActive)
        publication.assertOwnershipIsLive()
        survivor.assertOwnershipIsLive()
        fixture.assertOriginalRootIsCurrent()

        // The separate accepted reference, not a later reload, owns the
        // remaining lifetime. Its actual raw departure must settle it now.
        fixture.runtime.root.removeChild(survivor.node)

        XCTAssertEqual(fixture.runtime.root.children.count, 1)
        XCTAssertTrue(fixture.runtime.root.children.first === container)
        XCTAssertNil(survivor.node.parent)
        XCTAssertNil(survivor.node.retainedLazyListRuntime)
        XCTAssertFalse(survivor.localOwner.isCurrent)
        survivor.assertWithdrawn()
        publication.assertWithdrawn()
        fixture.assertOriginalRootIsCurrent()
    }

    func testFinalWritePreservesRetainedChildThroughTemporaryEmptyField() async throws {
        let fixture = FinalChildrenWithdrawalFixture()
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

        var late: FinalChildrenWithdrawalPublication?
        var callbackError: Error?
        let lateSlot = RetainedOwnedSlotGenerationID()
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

            // Add a distinct late owner only after the complete original
            // Raw3 callback oracle has checked B through temporary [].
            do {
                let publication = try fixture.acceptSource(identity: 3, parent: container, slots: [lateSlot])
                late = publication
                XCTAssertFalse(publication.owned.owner === survivor.owned.owner)
                XCTAssertTrue(publication.owned.slots.first === lateSlot)
                XCTAssertTrue(publication.actual.isAttached)
                XCTAssertTrue(publication.contribution.isActive)
                XCTAssertEqual(container.children.count, 1)
                XCTAssertTrue(container.children.first === publication.node)
                publication.assertOwnershipIsLive()
            } catch {
                callbackError = error
            }
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

        if let callbackError { throw callbackError }
        let publication = try XCTUnwrap(late)
        publication.assertWithdrawn()
    }

    func testFinalWriteClaimsCurrentDescendantsButNotAnEarlierMovedDescendant() async throws {
        let fixture = FinalChildrenWithdrawalFixture()
        let container = ViewNode()
        let outside = ViewNode()
        fixture.runtime.root.addChild(container)
        fixture.runtime.root.addChild(outside)
        let firstOutgoing = ViewNode()
        let secondOutgoing = ViewNode()
        container.addChild(firstOutgoing)
        container.addChild(secondOutgoing)
        let originalMoved = try fixture.acceptSource(identity: 1, parent: firstOutgoing)
        let originalStorage = try XCTUnwrap(originalMoved.node.retainedLazyListActivityStorage)
        let movedSlot = RetainedOwnedSlotGenerationID()
        let descendantSlot = RetainedOwnedSlotGenerationID()
        let incoming = ViewNode()
        var moved: FinalChildrenWithdrawalPublication?
        var cutRoot: ViewNode?
        var descendant: FinalChildrenWithdrawalPublication?
        var callbackError: Error?
        var events: [String] = []
        firstOutgoing.onDismantlePlatformView = { departing in
            events.append("move-descendant")
            XCTAssertTrue(departing === firstOutgoing)
            XCTAssertTrue(container.children.isEmpty)
            XCTAssertTrue(originalMoved.node.parent === firstOutgoing)
            XCTAssertFalse(originalMoved.actual.isAttached)
            originalMoved.assertOwnershipIsLive()

            // A real move leaves the earlier forest before its later walk.
            // The revoked old owner is not reused for the new attachment.
            originalMoved.node.removeFromParent()
            XCTAssertNil(originalMoved.node.parent)
            XCTAssertNil(originalMoved.node.retainedLazyListRuntime)
            originalMoved.assertWithdrawn()
            do {
                let publication = try fixture.acceptSource(
                    identity: 1, parent: outside, node: originalMoved.node, slots: [movedSlot])
                moved = publication
                XCTAssertTrue(publication.node === originalMoved.node)
                XCTAssertTrue(publication.node.retainedLazyListActivityStorage === originalStorage)
                XCTAssertTrue(publication.actual.target === originalMoved.actual.target)
                XCTAssertFalse(publication.actual.attachment === originalMoved.actual.attachment)
                XCTAssertFalse(publication.owned.owner === originalMoved.owned.owner)
                XCTAssertTrue(publication.node.parent === outside)
                XCTAssertTrue(publication.actual.isAttached)
                XCTAssertTrue(publication.contribution.isActive)
                publication.assertOwnershipIsLive()
            } catch {
                callbackError = error
            }
        }
        secondOutgoing.onDismantlePlatformView = { departing in
            events.append("install-descendant")
            XCTAssertTrue(departing === secondOutgoing)
            XCTAssertTrue(container.children.isEmpty)
            do {
                let movedPublication = try XCTUnwrap(moved)
                XCTAssertTrue(movedPublication.node.parent === outside)
                XCTAssertTrue(movedPublication.actual.isAttached)
                movedPublication.assertOwnershipIsLive()
                let root = ViewNode()
                container.addChild(root)
                cutRoot = root
                let publication = try fixture.acceptSource(identity: 2, parent: root, slots: [descendantSlot])
                descendant = publication
                XCTAssertEqual(container.children.count, 1)
                XCTAssertTrue(container.children.first === root)
                XCTAssertEqual(root.children.count, 1)
                XCTAssertTrue(root.children.first === publication.node)
                XCTAssertTrue(publication.actual.isAttached)
                XCTAssertTrue(publication.contribution.isActive)
                publication.assertOwnershipIsLive()
            } catch {
                callbackError = error
            }
        }
        defer {
            firstOutgoing.onDismantlePlatformView = nil
            secondOutgoing.onDismantlePlatformView = nil
        }

        events.append("replace-begin")
        let result = container.setChildren([incoming])
        events.append("replace-returned")

        if let callbackError { throw callbackError }
        let movedPublication = try XCTUnwrap(moved)
        let root = try XCTUnwrap(cutRoot)
        let descendantPublication = try XCTUnwrap(descendant)
        XCTAssertEqual(events, ["replace-begin", "move-descendant", "install-descendant", "replace-returned"])
        XCTAssertTrue(result.completed)
        XCTAssertTrue(result.didMutate)
        XCTAssertEqual(result.children.count, 1)
        XCTAssertTrue(result.children.first === incoming)
        XCTAssertEqual(container.children.count, 1)
        XCTAssertTrue(container.children.first === incoming)
        XCTAssertFalse(container.children.contains { $0 === root })
        XCTAssertTrue(incoming.parent === container)
        XCTAssertTrue(incoming.retainedLazyListRuntime === fixture.runtime)
        descendantPublication.assertWithdrawn()
        originalMoved.assertWithdrawn()
        XCTAssertEqual(outside.children.count, 1)
        XCTAssertTrue(outside.children.first === movedPublication.node)
        XCTAssertTrue(movedPublication.node.parent === outside)
        XCTAssertTrue(movedPublication.node.retainedLazyListRuntime === fixture.runtime)
        XCTAssertTrue(movedPublication.node.retainedLazyListActivityStorage === originalStorage)
        XCTAssertTrue(originalStorage.targetID === movedPublication.actual.target)
        XCTAssertTrue(originalStorage.attachmentID === movedPublication.actual.attachment)
        XCTAssertTrue(movedPublication.localOwner.isCurrent)
        XCTAssertTrue(movedPublication.actual.isAttached)
        XCTAssertTrue(movedPublication.contribution.isActive)
        movedPublication.assertOwnershipIsLive()
        fixture.assertOriginalRootIsCurrent()
    }

    func testFinalWriteRetiresAReattachedOutgoingNodeOnlyAtItsNewActualCut() async throws {
        let fixture = FinalChildrenWithdrawalFixture()
        let container = ViewNode()
        fixture.runtime.root.addChild(container)
        let original = try fixture.acceptSource(identity: 1, parent: container)
        let originalStorage = try XCTUnwrap(original.node.retainedLazyListActivityStorage)
        let outgoingTrigger = ViewNode()
        container.addChild(outgoingTrigger)
        let incoming = ViewNode()
        let nextSlot = RetainedOwnedSlotGenerationID()
        var late: FinalChildrenWithdrawalPublication?
        var callbackError: Error?
        var callbackCount = 0
        outgoingTrigger.onDismantlePlatformView = { departing in
            callbackCount += 1
            XCTAssertTrue(departing === outgoingTrigger)
            XCTAssertTrue(container.children.isEmpty)
            // The first original departure has finished before this second
            // outgoing callback reattaches the same node.
            XCTAssertNil(original.node.parent)
            XCTAssertNil(original.node.retainedLazyListRuntime)
            XCTAssertFalse(original.localOwner.isCurrent)
            original.assertWithdrawn()
            do {
                let publication = try fixture.acceptSource(
                    identity: 1, parent: container, node: original.node, slots: [nextSlot])
                late = publication
                XCTAssertTrue(publication.node === original.node)
                XCTAssertTrue(publication.node.retainedLazyListActivityStorage === originalStorage)
                XCTAssertTrue(publication.actual.target === original.actual.target)
                XCTAssertFalse(publication.actual.attachment === original.actual.attachment)
                XCTAssertFalse(publication.owned === original.owned)
                XCTAssertFalse(publication.owned.owner === original.owned.owner)
                XCTAssertTrue(publication.owned.slots.first === nextSlot)
                XCTAssertEqual(container.children.count, 1)
                XCTAssertTrue(container.children.first === publication.node)
                XCTAssertTrue(publication.actual.isAttached)
                XCTAssertTrue(publication.contribution.isActive)
                publication.assertOwnershipIsLive()
                original.assertWithdrawn()
                fixture.assertOriginalRootIsCurrent()
            } catch {
                callbackError = error
            }
        }
        defer { outgoingTrigger.onDismantlePlatformView = nil }

        let result = container.setChildren([incoming])

        if let callbackError { throw callbackError }
        let publication = try XCTUnwrap(late)
        XCTAssertEqual(callbackCount, 1)
        XCTAssertTrue(result.completed)
        XCTAssertTrue(result.didMutate)
        XCTAssertEqual(result.children.count, 1)
        XCTAssertTrue(result.children.first === incoming)
        XCTAssertEqual(container.children.count, 1)
        XCTAssertTrue(container.children.first === incoming)
        XCTAssertTrue(incoming.parent === container)
        XCTAssertTrue(incoming.retainedLazyListRuntime === fixture.runtime)
        original.assertWithdrawn()
        publication.assertWithdrawn()
        fixture.assertOriginalRootIsCurrent()
    }
}

// This is the existing real normal-source journal sequence used by Raw3,
// extended only to choose an empty slot roster or a fully detached node.
// No declaration-only, empty-group, final-field, or scope ACK is synthesized.
@MainActor
private final class FinalChildrenWithdrawalFixture {
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
        node suppliedNode: ViewNode? = nil, slots requestedSlots: [RetainedOwnedSlotGenerationID]? = nil,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> FinalChildrenWithdrawalPublication {
        assertOriginalRootIsCurrent(file: file, line: line)
        let destination = parent ?? runtime.root
        XCTAssertTrue(destination.retainedLazyListRuntime === runtime, file: file, line: line)
        let node = suppliedNode ?? ViewNode()
        XCTAssertNil(node.parent, file: file, line: line)
        XCTAssertNil(node.retainedLazyListRuntime, file: file, line: line)
        let slots = requestedSlots ?? continuing?.slots ?? [slot]
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
                owner: continuing?.owner ?? RetainedOwnedComponentID(), slots: slots,
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
            XCTAssertEqual(fact.slots.count, slots.count, file: file, line: line)
            for (actualSlot, requestedSlot) in zip(fact.slots, slots) {
                XCTAssertTrue(actualSlot === requestedSlot, file: file, line: line)
            }
            XCTAssertTrue(fact.actual.node === node, file: file, line: line)
            XCTAssertTrue(fact.actual.target === storage.targetID, file: file, line: line)
            XCTAssertTrue(fact.actual.attachment === storage.attachmentID, file: file, line: line)
            XCTAssertTrue(fact.actual.isAttached, file: file, line: line)
        }
        XCTAssertTrue(contribution.isActive, file: file, line: line)
        XCTAssertTrue(owned.hasAcceptedDeclaration, file: file, line: line)
        for slot in slots {
            XCTAssertTrue(owned.hasAcceptedOwnership(for: slot), file: file, line: line)
            XCTAssertTrue(owned.permitsOwnedWrite(for: slot), file: file, line: line)
        }
        XCTAssertTrue(owned.hasDeclaredComponent, file: file, line: line)
        XCTAssertTrue(disposition.retiredOwnedSlots.isEmpty, file: file, line: line)
        XCTAssertTrue(disposition.retiredOwnedComponents.isEmpty, file: file, line: line)
        XCTAssertFalse(storage.descriptorOwnerLifetime === originalRootOwner, file: file, line: line)
        XCTAssertTrue(storage.descriptorOwnerLifetime.isCurrent, file: file, line: line)
        return FinalChildrenWithdrawalPublication(
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
private struct FinalChildrenWithdrawalPublication {
    let node: ViewNode
    let owned: RetainedOwnedComponentReceipt
    let contribution: RetainedDescriptorContributionReceipt
    let actual: RetainedLazyListActualAttachment
    let localOwner: RetainedLazyListDescriptorOwnerLifetime

    func assertOwnershipIsLive(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(owned.hasAcceptedDeclaration, file: file, line: line)
        for slot in owned.slots {
            XCTAssertTrue(owned.hasAcceptedOwnership(for: slot), file: file, line: line)
            XCTAssertTrue(owned.permitsOwnedWrite(for: slot), file: file, line: line)
        }
        XCTAssertTrue(owned.hasDeclaredComponent, file: file, line: line)
    }

    func assertWithdrawn(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(actual.isAttached, file: file, line: line)
        XCTAssertFalse(contribution.isActive, file: file, line: line)
        XCTAssertTrue(owned.hasAcceptedDeclaration, file: file, line: line)
        for slot in owned.slots {
            XCTAssertFalse(owned.hasAcceptedOwnership(for: slot), file: file, line: line)
            XCTAssertFalse(owned.permitsOwnedWrite(for: slot), file: file, line: line)
        }
        XCTAssertFalse(owned.hasDeclaredComponent, file: file, line: line)
    }
}
