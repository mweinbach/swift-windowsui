import SwiftWindowsCore
import SwiftWindowsUI
@preconcurrency import XCTest

@testable import WinSwiftUI

@MainActor
final class StateMountRegistryTests: XCTestCase {
    func testLiveRevisionAdvancesBeforePayloadReleaseAndNewerMutationKeepsItsTransaction() async throws {
        let events = RegistryTestEvents()
        let coordinator = StateMountCoordinator(
            invalidate: { events.recordInvalidation() },
            observeObject: { _ in },
            updateObservedObjects: { _, _, _ in })
        let registry = coordinator.registry
        events.registry = registry
        defer { coordinator.close() }
        let initial = try XCTUnwrap(registry.beginRootBuild())
        let owner = try XCTUnwrap(initial.owner(at: identity("owner")))
        let newer = owner.resolve(at: RegistrySlotFields.secondSlot) { 0 }
        let originalRequest = try XCTUnwrap(coordinator.captureBuildRequest())
        let newerTransaction: Transaction = {
            var transaction = Transaction(animation: nil)
            transaction.isContinuous = true
            transaction.tracksVelocity = true
            transaction.scrollTargetAnchor = .bottom
            return transaction
        }()
        let outgoing = owner.resolve(at: RegistrySlotFields.firstSlot) {
            RegistryTestPayload(1) { [weak registry, weak newer] in
                guard let registry, let newer else {
                    XCTFail("The release must run while both mounted locations remain live")
                    return
                }
                events.releaseRevisions.append(registry.mutationRevision)
                events.requestValidityDuringRelease.append(originalRequest.isCurrent)
                withTransaction(newerTransaction) {
                    XCTAssertTrue(newer.write(9))
                }
            }
        }
        try commit(initial)
        XCTAssertEqual(registry.mutationRevision, 0)

        withTransaction(Transaction(animation: .linear(duration: 4))) {
            XCTAssertTrue(outgoing.write(RegistryTestPayload(2)))
        }

        XCTAssertEqual(events.releaseRevisions, [1], "The outgoing Value must see the accepted outer mutation")
        XCTAssertEqual(events.requestValidityDuringRelease, [false])
        XCTAssertEqual(registry.mutationRevision, 2)
        XCTAssertEqual(events.invalidations.map(\.revision), [2], "The older outer callback must not run again")
        let transaction = try XCTUnwrap(events.invalidations.first?.transaction)
        XCTAssertNil(transaction.animation, "The nested explicit nil must not inherit the outer animation")
        XCTAssertTrue(transaction.isContinuous)
        XCTAssertTrue(transaction.tracksVelocity)
        XCTAssertEqual(transaction.scrollTargetAnchor, .bottom)
        XCTAssertEqual(outgoing.readValue().value, 2)
        XCTAssertEqual(newer.readValue(), 9)
        XCTAssertFalse(originalRequest.isCurrent)
        XCTAssertTrue(try XCTUnwrap(coordinator.captureBuildRequest()).isCurrent)
        XCTAssertNil(currentTransaction)
        XCTAssertNil(currentAnimationTransaction)
    }

    func testRetiredSnapshotsRejectWritesAndReleasePayloadAfterTheLastExternalHandle() async throws {
        var invalidations = 0
        let registry = StateMountRegistry(invalidate: { invalidations += 1 })
        defer { registry.close() }
        let initial = try XCTUnwrap(registry.beginRootBuild())
        let owner = try XCTUnwrap(initial.owner(at: identity("snapshot")))
        var escaped: MountedStateCell<RegistryTestPayload>? = owner.resolve(at: RegistrySlotFields.firstSlot) {
            RegistryTestPayload(4)
        }
        try commit(initial)
        XCTAssertTrue(escaped?.write(RegistryTestPayload(8)) == true)
        weak var payload = escaped?.readValue()
        let removal = try XCTUnwrap(registry.beginRootBuild())
        XCTAssertTrue(removal.prepareForAdoption())
        XCTAssertFalse(escaped?.isWritable == true)
        XCTAssertTrue(escaped?.write(RegistryTestPayload(99)) == false)
        XCTAssertEqual(escaped?.readValue().value, 8)
        removal.commitAdoption()
        registry.finishRetirement(of: owner.generation)

        XCTAssertEqual(registry.liveOwnerCount, 0)
        XCTAssertEqual(registry.retiringOwnerCount, 0)
        XCTAssertEqual(registry.mutationRevision, 1)
        XCTAssertEqual(invalidations, 1)
        XCTAssertTrue(escaped?.write(RegistryTestPayload(100)) == false)
        XCTAssertEqual(registry.mutationRevision, 1, "A rejected retired setter must not advance request validity")
        XCTAssertEqual(invalidations, 1)
        payload?.value = 12
        XCTAssertEqual(escaped?.readValue().value, 12, "Snapshots retain ordinary shared reference semantics")

        escaped = nil
        withExtendedLifetime((initial, removal, owner, registry)) {
            XCTAssertNil(payload, "Finished epochs and retired owners must release their cell ownership")
        }
    }

    func testPropertySlotAndSamePathReplacementNeverRetargetDepartingCells() async throws {
        let registry = StateMountRegistry()
        defer { registry.close() }
        let ownerIdentity = identity("replacement")
        let firstSlot = RegistrySlotFields.firstSlot(concrete: RegistryFirstSlotType.self)
        let secondSlot = RegistrySlotFields.firstSlot(concrete: RegistrySecondSlotType.self)
        XCTAssertEqual(firstSlot.declaration, secondSlot.declaration)
        XCTAssertNotEqual(firstSlot.concreteTypes, secondSlot.concreteTypes)
        let initial = try XCTUnwrap(registry.beginRootBuild())
        let originalOwner = try XCTUnwrap(initial.owner(at: ownerIdentity))
        let original = originalOwner.resolve(at: firstSlot) { 7 }
        try commit(initial)
        let propertyChange = try XCTUnwrap(registry.beginRootBuild())
        let sameOwner = try XCTUnwrap(propertyChange.owner(at: ownerIdentity))
        let changed = sameOwner.resolve(at: secondSlot) { 11 }
        XCTAssertTrue(sameOwner === originalOwner)
        XCTAssertTrue(propertyChange.prepareForAdoption())
        XCTAssertFalse(original.write(70))
        XCTAssertFalse(changed.write(110), "New cells cannot write while adoption is prepared")
        propertyChange.commitAdoption()
        registry.finishPendingRetirements()
        XCTAssertEqual(original.readValue(), 7)
        XCTAssertTrue(changed.write(13))

        let removal = try XCTUnwrap(registry.beginRootBuild())
        try commit(removal)
        let insertion = try XCTUnwrap(registry.beginRootBuild())
        let replacementOwner = try XCTUnwrap(insertion.owner(at: ownerIdentity))
        let replacement = replacementOwner.resolve(at: secondSlot) { 99 }
        try commit(insertion)
        registry.finishRetirement(of: originalOwner.generation)

        XCTAssertNotEqual(originalOwner.generation, replacementOwner.generation)
        XCTAssertTrue(registry.owner(at: ownerIdentity) === replacementOwner)
        XCTAssertFalse(original.write(700))
        XCTAssertFalse(changed.write(130))
        XCTAssertEqual(changed.readValue(), 13)
        XCTAssertEqual(replacement.readValue(), 99)
        XCTAssertTrue(replacement.write(100), "Late cleanup for the old generation must not revoke the replacement")
    }

    func testRecursiveSeedReusesTheFirstResolvedCellInsteadOfLeavingAnUntrackedHandle() async throws {
        let registry = StateMountRegistry()
        defer { registry.close() }
        let initial = try XCTUnwrap(registry.beginRootBuild())
        let owner = try XCTUnwrap(initial.owner(at: identity("recursive")))
        var inner: MountedStateCell<Int>?
        var seeds = 0
        let outer = owner.resolve(at: RegistrySlotFields.firstSlot) {
            seeds += 1
            inner = owner.resolve(at: RegistrySlotFields.firstSlot) {
                seeds += 1
                return 1
            }
            return 2
        }

        XCTAssertEqual(seeds, 2)
        XCTAssertTrue(inner === outer)
        XCTAssertTrue(owner.isInstalled(cell: outer, at: RegistrySlotFields.firstSlot))
        XCTAssertEqual(outer.readValue(), 1)
        XCTAssertTrue(outer.write(3))
        XCTAssertEqual(registry.mutationRevision, 0, "Provisional initialization does not invalidate the host")
        try commit(initial)
        XCTAssertTrue(inner?.write(4) == true)
        XCTAssertEqual(registry.mutationRevision, 1)
        let rebuild = try XCTUnwrap(registry.beginRootBuild())
        let rebuiltOwner = try XCTUnwrap(rebuild.owner(at: owner.identity))
        let rebuilt = rebuiltOwner.resolve(at: RegistrySlotFields.firstSlot) { 99 }
        XCTAssertTrue(rebuilt === outer)
        XCTAssertEqual(rebuilt.readValue(), 4)
        rebuild.abort()
        XCTAssertTrue(outer.isWritable)
    }

    func testSeedInterruptionCannotAppendOwnershipToAFinishedOrSupersededEpoch() async throws {
        for interruption in RegistrySeedInterruption.allCases {
            let registry = StateMountRegistry()
            let epoch = try XCTUnwrap(registry.beginRootBuild())
            let owner = try XCTUnwrap(epoch.owner(at: identity("interrupted")))
            var escaped: MountedStateCell<RegistryTestPayload>? = owner.resolve(at: RegistrySlotFields.firstSlot) {
                switch interruption {
                case .abort: epoch.abort()
                case .supersede: epoch.supersede()
                case .close: registry.close()
                }
                return RegistryTestPayload(17)
            }
            weak var payload = escaped?.readValue()
            epoch.abort()

            XCTAssertFalse(epoch.canAdopt)
            XCTAssertFalse(epoch.didCommit)
            XCTAssertTrue(epoch.visitedOwnerIdentities.isEmpty)
            XCTAssertEqual(registry.liveOwnerCount, 0)
            XCTAssertEqual(registry.retiringOwnerCount, 0)
            XCTAssertEqual(escaped?.readValue().value, 17)
            XCTAssertTrue(escaped?.write(RegistryTestPayload(18)) == false)
            XCTAssertEqual(registry.mutationRevision, 0)
            escaped = nil
            withExtendedLifetime((epoch, owner, registry)) {
                XCTAssertNil(payload, "The finished epoch must not retain the seed result for \(interruption)")
            }
            registry.close()
        }
    }

    func testAbandonDiscardsNewLocationsButPreservesAcceptedWritesToTheLiveOwner() async throws {
        var invalidations = 0
        let registry = StateMountRegistry(invalidate: { invalidations += 1 })
        defer { registry.close() }
        let initial = try XCTUnwrap(registry.beginRootBuild())
        let owner = try XCTUnwrap(initial.owner(at: identity("live")))
        let live = owner.resolve(at: RegistrySlotFields.firstSlot) { 1 }
        try commit(initial)
        let candidate = try XCTUnwrap(registry.beginRootBuild())
        let sameOwner = try XCTUnwrap(candidate.owner(at: owner.identity))
        let sameCell = sameOwner.resolve(at: RegistrySlotFields.firstSlot) { 99 }
        var provisional: MountedStateCell<RegistryTestPayload>? = sameOwner.resolve(at: RegistrySlotFields.secondSlot) {
            RegistryTestPayload(20)
        }
        weak var payload = provisional?.readValue()
        let uncommittedIdentity = identity("uncommitted")
        let uncommittedOwner = try XCTUnwrap(candidate.owner(at: uncommittedIdentity))
        XCTAssertTrue(live === sameCell)
        XCTAssertTrue(live.write(7))
        candidate.supersede()
        XCTAssertFalse(candidate.prepareForAdoption())
        candidate.abort()

        XCTAssertTrue(registry.owner(at: owner.identity) === owner)
        XCTAssertNil(registry.owner(at: uncommittedIdentity))
        XCTAssertEqual(registry.liveOwnerCount, 1)
        XCTAssertEqual(registry.mutationRevision, 1)
        XCTAssertEqual(invalidations, 1)
        XCTAssertEqual(live.readValue(), 7)
        XCTAssertTrue(live.isWritable)
        XCTAssertEqual(provisional?.readValue().value, 20)
        XCTAssertTrue(provisional?.write(RegistryTestPayload(21)) == false)
        provisional = nil
        withExtendedLifetime((candidate, owner, uncommittedOwner, registry)) {
            XCTAssertNil(payload, "A new slot on a surviving owner is still provisional ownership")
        }
    }

    func testDeclaredSubtreesSurviveDiscardedMeasurementsWithoutKeepingNewCells() async throws {
        let registry = StateMountRegistry()
        defer { registry.close() }
        let parentIdentity = identity("declared")
        let firstIdentity = parentIdentity.appending(.slot(0))
        let secondIdentity = parentIdentity.appending(.slot(1))
        let siblingIdentity = identity("sibling")
        let measurementIdentity = identity("measurement")
        let initial = try XCTUnwrap(registry.beginRootBuild())
        let parent = try XCTUnwrap(initial.owner(at: parentIdentity))
        let firstOwner = try XCTUnwrap(initial.owner(at: firstIdentity))
        let first = firstOwner.resolve(at: RegistrySlotFields.firstSlot) { 1 }
        let secondOwner = try XCTUnwrap(initial.owner(at: secondIdentity))
        let second = secondOwner.resolve(at: RegistrySlotFields.firstSlot) { 2 }
        let siblingOwner = try XCTUnwrap(initial.owner(at: siblingIdentity))
        let sibling = siblingOwner.resolve(at: RegistrySlotFields.firstSlot) { 3 }
        try commit(initial)
        let candidate = try XCTUnwrap(registry.beginRootBuild())
        XCTAssertTrue(candidate.owner(at: parentIdentity) === parent)
        let measuredOwner = try XCTUnwrap(candidate.owner(at: firstIdentity))
        XCTAssertTrue(measuredOwner.resolve(at: RegistrySlotFields.firstSlot, seed: { 99 }) === first)
        var measured: MountedStateCell<RegistryTestPayload>? = measuredOwner.resolve(
            at: RegistrySlotFields.secondSlot
        ) { RegistryTestPayload(4) }
        weak var measuredPayload = measured?.readValue()
        candidate.discardUnadoptedSubtree(at: firstIdentity, preserveCommitted: true)
        candidate.preserveDeclaredSubtree(at: secondIdentity)
        let keptSibling = try XCTUnwrap(candidate.owner(at: siblingIdentity))
        XCTAssertTrue(keptSibling.resolve(at: RegistrySlotFields.firstSlot, seed: { 99 }) === sibling)
        let unusedOwner = try XCTUnwrap(candidate.owner(at: measurementIdentity))
        let unused = unusedOwner.resolve(at: RegistrySlotFields.firstSlot) { 5 }
        candidate.discardUnadoptedSubtree(at: measurementIdentity, preserveCommitted: false)
        try commit(candidate)

        XCTAssertEqual(registry.liveOwnerCount, 4)
        XCTAssertTrue(registry.owner(at: firstIdentity) === firstOwner)
        XCTAssertTrue(registry.owner(at: secondIdentity) === secondOwner)
        XCTAssertNil(registry.owner(at: measurementIdentity))
        XCTAssertEqual(first.readValue(), 1)
        XCTAssertEqual(second.readValue(), 2)
        XCTAssertTrue(first.isWritable)
        XCTAssertTrue(second.isWritable)
        XCTAssertFalse(unused.write(50))
        XCTAssertEqual(unused.readValue(), 5)
        XCTAssertTrue(measured?.write(RegistryTestPayload(40)) == false)
        measured = nil
        withExtendedLifetime((candidate, measuredOwner, registry)) {
            XCTAssertNil(measuredPayload, "Preserving the committed subtree must not adopt a measured new slot")
        }

        let removal = try XCTUnwrap(registry.beginRootBuild())
        removal.preserveDeclaredSubtree(at: secondIdentity)
        removal.preserveDeclaredSubtree(at: siblingIdentity)
        _ = try XCTUnwrap(removal.owner(at: parentIdentity))
        try commit(removal)
        registry.finishRetirement(of: firstOwner.generation)
        XCTAssertFalse(first.write(10))
        XCTAssertEqual(first.readValue(), 1)
        XCTAssertTrue(second.isWritable)
        XCTAssertTrue(sibling.isWritable)
    }

    func testReaderBuildRequiresAContentDescendantAndCannotSweepItsAnchorOrSibling() async throws {
        let registry = StateMountRegistry()
        defer { registry.close() }
        let readerIdentity = identity("reader")
        let contentPrefix = readerIdentity.appending(.role(.geometryContent))
        let childIdentity = contentPrefix.appending(.slot(0))
        let removedIdentity = contentPrefix.appending(.slot(1))
        let siblingIdentity = identity("reader sibling")
        let initial = try XCTUnwrap(registry.beginRootBuild())
        let reader = try XCTUnwrap(initial.owner(at: readerIdentity))
        let childOwner = try XCTUnwrap(initial.owner(at: childIdentity))
        let child = childOwner.resolve(at: RegistrySlotFields.firstSlot) { 1 }
        let removedOwner = try XCTUnwrap(initial.owner(at: removedIdentity))
        let removed = removedOwner.resolve(at: RegistrySlotFields.firstSlot) { 2 }
        let siblingOwner = try XCTUnwrap(initial.owner(at: siblingIdentity))
        let sibling = siblingOwner.resolve(at: RegistrySlotFields.firstSlot) { 3 }
        try commit(initial)
        XCTAssertNil(registry.beginSubtreeBuild(owner: reader, contentPrefix: readerIdentity))
        XCTAssertNil(registry.beginSubtreeBuild(owner: reader, contentPrefix: siblingIdentity))
        let subtree = try XCTUnwrap(registry.beginSubtreeBuild(owner: reader, contentPrefix: contentPrefix))
        XCTAssertNil(subtree.owner(at: readerIdentity))
        XCTAssertNil(subtree.owner(at: siblingIdentity))
        let sameChild = try XCTUnwrap(subtree.owner(at: childIdentity))
        XCTAssertTrue(sameChild.resolve(at: RegistrySlotFields.firstSlot, seed: { 99 }) === child)
        try commit(subtree)
        registry.finishPendingRetirements()

        XCTAssertTrue(registry.owner(at: readerIdentity) === reader)
        XCTAssertTrue(reader.isLive)
        XCTAssertTrue(registry.owner(at: siblingIdentity) === siblingOwner)
        XCTAssertEqual(registry.liveOwnerCount, 3)
        XCTAssertEqual(child.readValue(), 1)
        XCTAssertEqual(sibling.readValue(), 3)
        XCTAssertTrue(child.isWritable)
        XCTAssertTrue(sibling.isWritable)
        XCTAssertNil(registry.owner(at: removedIdentity))
        XCTAssertFalse(removed.write(20))
        XCTAssertEqual(removed.readValue(), 2)
    }

    func testCloseAndDeinitRevokeActiveBuildsWithoutRetainingTheirRegistryThroughSnapshots() async throws {
        for closeExplicitly in [false, true] {
            var registry: StateMountRegistry? = StateMountRegistry()
            weak var weakRegistry = registry
            let initial = try XCTUnwrap(registry?.beginRootBuild())
            let owner = try XCTUnwrap(initial.owner(at: identity("closing")))
            var live: MountedStateCell<RegistryTestPayload>? = owner.resolve(at: RegistrySlotFields.firstSlot) {
                RegistryTestPayload(1)
            }
            try commit(initial)
            weak var livePayload = live?.readValue()
            let candidate = try XCTUnwrap(registry?.beginRootBuild())
            let sameOwner = try XCTUnwrap(candidate.owner(at: owner.identity))
            _ = sameOwner.resolve(at: RegistrySlotFields.firstSlot) { RegistryTestPayload(99) }
            var provisional: MountedStateCell<RegistryTestPayload>? = sameOwner.resolve(
                at: RegistrySlotFields.secondSlot
            ) { RegistryTestPayload(2) }
            weak var provisionalPayload = provisional?.readValue()
            if closeExplicitly {
                registry?.close()
                XCTAssertFalse(candidate.canAdopt)
                XCTAssertFalse(live?.isWritable == true)
                candidate.abort()
                XCTAssertEqual(registry?.retiringOwnerCount, 0)
                XCTAssertNil(registry?.beginRootBuild())
            }
            registry = nil

            XCTAssertNil(weakRegistry, "Captured owners, epochs, and cells must not retain the registry")
            XCTAssertFalse(candidate.canAdopt)
            XCTAssertFalse(candidate.didCommit)
            XCTAssertFalse(owner.isLive)
            XCTAssertTrue(live?.write(RegistryTestPayload(10)) == false)
            XCTAssertTrue(provisional?.write(RegistryTestPayload(20)) == false)
            XCTAssertEqual(live?.readValue().value, 1)
            XCTAssertEqual(provisional?.readValue().value, 2)
            live = nil
            provisional = nil
            withExtendedLifetime((initial, candidate, owner, sameOwner)) {
                XCTAssertNil(livePayload)
                XCTAssertNil(provisionalPayload)
            }
        }
    }

    func testAbortingPreparedAdoptionRestoresOldPermissionsWithoutRollingBackLiveValues() async throws {
        let registry = StateMountRegistry()
        defer { registry.close() }
        let initial = try XCTUnwrap(registry.beginRootBuild())
        let removedOwner = try XCTUnwrap(initial.owner(at: identity("prepared removal")))
        let removed = removedOwner.resolve(at: RegistrySlotFields.firstSlot) { 3 }
        let survivingOwner = try XCTUnwrap(initial.owner(at: identity("prepared survivor")))
        let oldSlot = survivingOwner.resolve(at: RegistrySlotFields.firstSlot) { 4 }
        let stillLive = survivingOwner.resolve(at: RegistrySlotFields.thirdSlot) { 5 }
        try commit(initial)
        let candidate = try XCTUnwrap(registry.beginRootBuild())
        let sameOwner = try XCTUnwrap(candidate.owner(at: survivingOwner.identity))
        let newSlot = sameOwner.resolve(at: RegistrySlotFields.secondSlot) { 20 }
        XCTAssertTrue(sameOwner.resolve(at: RegistrySlotFields.thirdSlot, seed: { 99 }) === stillLive)
        let newIdentity = identity("prepared insertion")
        let newOwner = try XCTUnwrap(candidate.owner(at: newIdentity))
        let newCell = newOwner.resolve(at: RegistrySlotFields.firstSlot) { 30 }
        XCTAssertTrue(candidate.prepareForAdoption())
        XCTAssertFalse(removed.write(300))
        XCTAssertFalse(oldSlot.write(400))
        XCTAssertFalse(newSlot.write(200))
        XCTAssertFalse(newCell.write(300))
        XCTAssertEqual(registry.mutationRevision, 0)
        XCTAssertTrue(stillLive.write(9))
        candidate.abort()
        registry.finishPendingRetirements()

        XCTAssertFalse(candidate.didCommit)
        XCTAssertEqual(registry.liveOwnerCount, 2)
        XCTAssertEqual(registry.retiringOwnerCount, 0)
        XCTAssertTrue(registry.owner(at: removedOwner.identity) === removedOwner)
        XCTAssertTrue(registry.owner(at: survivingOwner.identity) === survivingOwner)
        XCTAssertNil(registry.owner(at: newIdentity))
        XCTAssertTrue(removedOwner.isLive)
        XCTAssertTrue(survivingOwner.isLive)
        XCTAssertEqual(stillLive.readValue(), 9, "Abandonment must not undo an accepted live mutation")
        XCTAssertTrue(removed.write(6))
        XCTAssertTrue(oldSlot.write(7), "The property cell must be removed from the pending retirement queue")
        XCTAssertFalse(newSlot.write(21))
        XCTAssertFalse(newCell.write(31))
        XCTAssertEqual(newSlot.readValue(), 20)
        XCTAssertEqual(newCell.readValue(), 30)
        XCTAssertEqual(registry.mutationRevision, 3)
        let next = try XCTUnwrap(registry.beginRootBuild())
        next.abort()
    }

    private func identity(_ key: String) -> RetainedViewIdentity {
        RetainedViewIdentity(segments: [.view(ObjectIdentifier(RegistrySlotFields.self)), .keyed(.init(key))])
    }

    private func commit(
        _ epoch: StateMountEpoch, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let prepared = epoch.prepareForAdoption()
        XCTAssertTrue(prepared, file: file, line: line)
        guard prepared else { throw RegistryTestFailure.cannotPrepare }
        epoch.commitAdoption()
        XCTAssertTrue(epoch.didCommit, file: file, line: line)
    }
}

private struct RegistrySlotFields {
    private var first = 0
    private var second = 0
    private var third = 0

    static var firstSlot: StatePropertySlot {
        StatePropertySlot(declaration: [\Self.first], concreteTypes: [ObjectIdentifier(Self.self)])
    }

    static var secondSlot: StatePropertySlot {
        StatePropertySlot(declaration: [\Self.second], concreteTypes: [ObjectIdentifier(Self.self)])
    }

    static var thirdSlot: StatePropertySlot {
        StatePropertySlot(declaration: [\Self.third], concreteTypes: [ObjectIdentifier(Self.self)])
    }

    static func firstSlot(concrete: Any.Type) -> StatePropertySlot {
        StatePropertySlot(
            declaration: [\Self.first], concreteTypes: [ObjectIdentifier(Self.self), ObjectIdentifier(concrete)])
    }
}

private struct RegistryFirstSlotType {}
private struct RegistrySecondSlotType {}

private enum RegistrySeedInterruption: CaseIterable {
    case abort
    case supersede
    case close
}

private enum RegistryTestFailure: Error {
    case cannotPrepare
}

private struct RegistryTestMutation {
    let revision: UInt64
    let transaction: Transaction?
}

@MainActor
private final class RegistryTestEvents {
    weak var registry: StateMountRegistry?
    var releaseRevisions: [UInt64] = []
    var requestValidityDuringRelease: [Bool] = []
    var invalidations: [RegistryTestMutation] = []

    func recordInvalidation() {
        guard let registry else {
            XCTFail("An invalidation must originate from the live registry")
            return
        }
        invalidations.append(RegistryTestMutation(revision: registry.mutationRevision, transaction: currentTransaction))
    }
}

@MainActor
private final class RegistryTestPayload {
    var value: Int
    private let onRelease: (@MainActor () -> Void)?

    init(_ value: Int, onRelease: (@MainActor () -> Void)? = nil) {
        self.value = value
        self.onRelease = onRelease
    }

    isolated deinit {
        onRelease?()
    }
}
