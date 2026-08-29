import SwiftWindowsCore
import SwiftWindowsUI
@preconcurrency import XCTest

@testable import WinSwiftUI

@MainActor
final class MountedObserverReentryTests: XCTestCase {
    func testOrdinaryResolutionDuringObserverHashSurvivesAdoptionAndRejectsObserver() async throws {
        for mutation in ObserverReentryMutation.allCases {
            try exerciseOrdinaryResolution(at: .identityHash, mutation: mutation)
        }
    }

    func testOrdinaryResolutionDuringObserverSeedSurvivesAdoptionAndRejectsObserver() async throws {
        for mutation in ObserverReentryMutation.allCases {
            try exerciseOrdinaryResolution(at: .seed, mutation: mutation)
        }
    }

    func testOrdinaryResolutionDuringFinalAdmissionHashRejectsOnlyTheObserverUpdate() async throws {
        for mutation in ObserverReentryMutation.allCases {
            try exerciseOrdinaryResolution(at: .finalAdmissionHash, mutation: mutation)
        }
    }

    func testOutgoingSnapshotCellCleanupCanCloseOrSupersedeWithoutLaterPublication() async throws {
        for cancellation in ObserverReentryCancellation.allCases {
            try exerciseSnapshotCleanup(of: .cellPayload, cancellation: cancellation)
        }
    }

    func testOutgoingSnapshotOwnerIdentityCleanupCanCloseOrSupersedeWithoutLaterPublication() async throws {
        for cancellation in ObserverReentryCancellation.allCases {
            try exerciseSnapshotCleanup(of: .ownerIdentity, cancellation: cancellation)
        }
    }

    func testMaterializedRejectionKeepsBaselineWhileNestedOwnerAdopts() async throws {
        try exerciseCommittedPreservation(at: .identityHash, nestedInObserverOwner: false)
    }

    func testNestedCandidateWithoutObservationSlotClaimKeepsCommittedBaseline() async throws {
        try exerciseCommittedPreservation(at: .identityHash, nestedInObserverOwner: true)
    }

    func testFinalAdmissionHashReentryKeepsCommittedBaselineWithoutDeliveringProposal() async throws {
        for sameOwner in [false, true] {
            try exerciseCommittedPreservation(at: .finalAdmissionHash, nestedInObserverOwner: sameOwner)
        }
    }

    func testRejectedParentDiscardsTheMaterializedPreservationMarker() async throws {
        let fixture = try ObserverReentryFixture()
        let hashing = ObserverReentryGate()
        defer {
            hashing.disarm()
            fixture.close()
        }
        let parent = RetainedViewIdentity(segments: [.view(ObjectIdentifier(ObserverReentryRejectedParent.self))])
        let identity = observerReentryIdentity(hashing: hashing, prefix: parent.appending(.role(.content)))
        let original = try establishObserver(in: fixture, at: identity)
        let nested = try materializeRejectedObserver(in: fixture, at: identity, hashing: hashing)

        // This is the coordinator's rejected-parent path without an explicit
        // declaration-preservation request. A discarded marker must not add
        // preservation back when this otherwise valid build prepares.
        fixture.coordinator.discardUnadoptedSubtree(at: parent, preserveCommitted: false)
        try fixture.acceptBuild {
            XCTAssertFalse(original.cell.isWritable)
        }
        XCTAssertNil(fixture.coordinator.registry.owner(at: identity))
        XCTAssertFalse(original.owner.isLive)
        XCTAssertFalse(original.cell.isWritable)
        XCTAssertEqual(original.cell.readValue().baseline?.number, 10)
        XCTAssertTrue(nested.cell.isWritable)
        fixture.events.assertNoObserverCallbacks()
        try assertFreshObservation(in: fixture, at: identity, replacing: original.cell, value: 30)
    }

    func testViewThatFitsRejectsMarkerCandidateWithoutAffectingSelectedSibling() async throws {
        let probe = ObserverReentryFitsProbe()
        var selectedValues: [Int] = []
        let host = MountedOnChangeTestHost {
            AnyView(
                ViewThatFits(in: .horizontal) {
                    ObserverReentryFitsView(
                        value: probe.value, width: probe.primaryFits ? 20 : 800, probe: probe
                    )
                    .id(ObserverReentryHashKey(value: 71, hashing: probe.hashing))
                    Color.blue.frame(width: 20, height: 40)
                        .onChange(of: probe.value, initial: true) { _, new in selectedValues.append(new) }
                })
        }
        defer {
            probe.hashing.disarm()
            host.close()
        }
        let identity = try XCTUnwrap(probe.identity)
        let originalOwner = try XCTUnwrap(host.coordinator.registry.owner(at: identity))
        let originalCell = try XCTUnwrap(probe.events.lastObserverCell)
        XCTAssertEqual(originalCell.readValue().baseline?.number, 10)
        XCTAssertTrue(originalCell.isWritable)
        XCTAssertEqual(selectedValues, [])

        probe.events.resetCounters()
        probe.value = 20
        probe.primaryFits = false
        probe.reenterOnNextMaterialization = true
        host.reload()
        probe.hashing.disarm()
        XCTAssertEqual(probe.reentries, 1, "The real candidate must reach its authored admission hash")
        XCTAssertEqual(probe.hashing.firings, 1)
        XCTAssertFalse(host.isClosed)
        XCTAssertFalse(host.componentHost.isBuilding)
        XCTAssertEqual(selectedValues, [20], "The sibling selected by ViewThatFits still delivers its own update")
        probe.events.assertNoObserverCallbacks()
        XCTAssertTrue(host.coordinator.registry.owner(at: identity) === originalOwner)
        XCTAssertEqual(originalCell.readValue().baseline?.number, 10)
        // ViewThatFits separately preserves declared inactive history after
        // discarding the measured candidate. It must not publish value 20.
        XCTAssertTrue(originalCell.isWritable)

        probe.value = 30
        probe.primaryFits = true
        host.reload()
        XCTAssertTrue(probe.events.lastObserverCell === originalCell)
        XCTAssertEqual(probe.events.comparisonInputs, [[10, 30]])
        XCTAssertEqual(probe.events.actionValues, [30])
        XCTAssertEqual(selectedValues, [20])
        XCTAssertFalse(host.componentHost.isBuilding)
    }

    func testConditionalLookupWithoutMaterializationDoesNotPreserveBaseline() async throws {
        let fixture = try ObserverReentryFixture()
        let hashing = ObserverReentryGate()
        defer {
            hashing.disarm()
            fixture.close()
        }
        let identity = observerReentryIdentity(hashing: hashing)
        let original = try establishObserver(in: fixture, at: identity)
        var nested: (owner: StateMountOwner, cell: MountedStateCell<Int>)?
        var lookupSeeds = 0
        hashing.arm {
            nested = self.resolveOrdinary(in: fixture, at: observerReentryOrdinaryIdentity())
        }
        let lookup = fixture.epoch.resolveSyntheticObservation(at: identity) {
            lookupSeeds += 1
            return ObserverReentryObservation()
        }
        hashing.disarm()
        XCTAssertEqual(hashing.firings, 1)
        XCTAssertNil(lookup)
        XCTAssertEqual(lookupSeeds, 0)
        XCTAssertTrue(fixture.build.canAdopt)
        try fixture.acceptBuild()
        XCTAssertTrue(try XCTUnwrap(nested).cell.isWritable)
        XCTAssertNil(fixture.coordinator.registry.owner(at: identity))
        XCTAssertFalse(original.owner.isLive)
        XCTAssertFalse(original.cell.isWritable)
        fixture.events.assertNoObserverCallbacks()
        try assertFreshObservation(in: fixture, at: identity, replacing: original.cell, value: 30)
    }

    func testUnmaterializedComponentDoesNotRequestBaselinePreservation() async throws {
        let fixture = try ObserverReentryFixture()
        let hashing = ObserverReentryGate()
        defer { fixture.close() }
        let identity = observerReentryIdentity(hashing: hashing)
        let original = try establishObserver(in: fixture, at: identity)
        let unused = Component { _ in
            fixture.stageObserver(at: identity, value: 20)
            return ViewNode()
        }
        let nested = try XCTUnwrap(resolveOrdinary(in: fixture, at: observerReentryOrdinaryIdentity()))
        try fixture.acceptBuild()
        XCTAssertEqual(fixture.events.seeds, 0)
        XCTAssertEqual(fixture.events.factories, 0)
        XCTAssertTrue(nested.cell.isWritable)
        XCTAssertNil(fixture.coordinator.registry.owner(at: identity))
        XCTAssertFalse(original.cell.isWritable)
        fixture.events.assertNoObserverCallbacks()
        withExtendedLifetime(unused) {}
        try assertFreshObservation(in: fixture, at: identity, replacing: original.cell, value: 30)
    }

    func testObserverPreservationDoesNotKeepUnrelatedChildState() async throws {
        let fixture = try ObserverReentryFixture()
        let hashing = ObserverReentryGate()
        defer {
            hashing.disarm()
            fixture.close()
        }
        let identity = observerReentryIdentity(hashing: hashing)
        let childIdentity = identity.appending(.role(.content)).appending(
            .view(ObjectIdentifier(ObserverReentryChild.self)))
        let unrelatedSlot = try XCTUnwrap(resolveOrdinary(in: fixture, at: identity, seed: 92))
        let child = try XCTUnwrap(resolveOrdinary(in: fixture, at: childIdentity, seed: 91))
        let original = try establishObserver(in: fixture, at: identity)
        XCTAssertTrue(unrelatedSlot.owner === original.owner)
        let nested = try materializeRejectedObserver(in: fixture, at: identity, hashing: hashing)
        try fixture.acceptBuild {
            XCTAssertTrue(original.cell.isWritable)
            XCTAssertFalse(
                unrelatedSlot.cell.isWritable, "An owner mask must not preserve every old slot on that owner")
            XCTAssertFalse(child.cell.isWritable, "Exact observer preservation must not keep its former child subtree")
        }
        XCTAssertTrue(fixture.coordinator.registry.owner(at: identity) === original.owner)
        XCTAssertTrue(original.cell.isWritable)
        XCTAssertEqual(original.cell.readValue().baseline?.number, 10)
        XCTAssertNil(fixture.coordinator.registry.owner(at: childIdentity))
        XCTAssertFalse(child.owner.isLive)
        XCTAssertFalse(child.cell.isWritable)
        XCTAssertEqual(child.cell.readValue(), 91)
        XCTAssertFalse(unrelatedSlot.cell.isWritable)
        XCTAssertEqual(unrelatedSlot.cell.readValue(), 92)
        XCTAssertTrue(nested.cell.isWritable)
        fixture.events.assertNoObserverCallbacks()
        try assertPreservedObservation(in: fixture, at: identity, original: original, from: 10, to: 30)
    }

    func testCloseAfterMarkerCreationRevokesOwnerAndCellBeforePreparation() async throws {
        let fixture = try ObserverReentryFixture()
        let hashing = ObserverReentryGate()
        defer {
            hashing.disarm()
            fixture.close()
        }
        let identity = observerReentryIdentity(hashing: hashing)
        let original = try establishObserver(in: fixture, at: identity)
        _ = try materializeRejectedObserver(in: fixture, at: identity, hashing: hashing)
        fixture.coordinator.close()
        XCTAssertFalse(fixture.build.willAdopt())
        XCTAssertFalse(original.owner.isLive)
        XCTAssertFalse(original.cell.isWritable)
        fixture.stageObserver(at: identity, value: 30)
        XCTAssertEqual(fixture.events.seeds, 0)
        XCTAssertEqual(fixture.events.factories, 0)
        fixture.abandonBuild()
        XCTAssertEqual(original.cell.readValue().baseline?.number, 10)
        XCTAssertNil(fixture.coordinator.registry.owner(at: identity))
        XCTAssertEqual(fixture.coordinator.registry.liveOwnerCount, 0)
        XCTAssertEqual(fixture.coordinator.registry.retiringOwnerCount, 0)
        fixture.events.assertNoObserverCallbacks()
    }

    func testAbandonedMarkerCannotPreserveOrRetargetARemovedOwnerGeneration() async throws {
        let fixture = try ObserverReentryFixture()
        let hashing = ObserverReentryGate()
        defer {
            hashing.disarm()
            fixture.close()
        }
        let identity = observerReentryIdentity(hashing: hashing)
        let original = try establishObserver(in: fixture, at: identity)
        _ = try materializeRejectedObserver(in: fixture, at: identity, hashing: hashing)
        fixture.build.supersede()
        fixture.abandonBuild()
        fixture.events.assertNoObserverCallbacks()
        try fixture.beginBuild()
        try fixture.acceptBuild()
        XCTAssertFalse(original.owner.isLive)
        XCTAssertFalse(original.cell.isWritable)
        XCTAssertNil(fixture.coordinator.registry.owner(at: identity))

        try fixture.beginBuild()
        let replacement = try establishObserver(in: fixture, at: identity, value: 70)
        XCTAssertNotEqual(replacement.owner.generation, original.owner.generation)
        XCTAssertFalse(replacement.cell === original.cell)
        _ = try materializeRejectedObserver(in: fixture, at: identity, hashing: hashing)
        try fixture.acceptBuild()
        XCTAssertEqual(replacement.cell.readValue().baseline?.number, 70)
        XCTAssertTrue(replacement.cell.isWritable)
        XCTAssertEqual(original.cell.readValue().baseline?.number, 10)
        XCTAssertFalse(original.cell.isWritable)
        fixture.events.assertNoObserverCallbacks()
        try assertPreservedObservation(in: fixture, at: identity, original: replacement, from: 70, to: 30)
    }

    func testRetiredObservationCellIsNotRevivedByItsStillLiveOwnerOrReplacement() async throws {
        let fixture = try ObserverReentryFixture()
        let hashing = ObserverReentryGate()
        defer {
            hashing.disarm()
            fixture.close()
        }
        let identity = observerReentryIdentity(hashing: hashing)
        let original = try establishObserver(in: fixture, at: identity)
        let ordinary = try XCTUnwrap(resolveOrdinary(in: fixture, at: identity))
        try fixture.acceptBuild()
        XCTAssertTrue(original.owner.isLive)
        XCTAssertTrue(ordinary.owner === original.owner)
        XCTAssertTrue(ordinary.cell.isWritable)
        XCTAssertFalse(original.cell.isWritable, "An ordinary slot claim must not claim the omitted observation")

        fixture.events.resetCounters()
        try fixture.beginBuild()
        let nested = try materializeRejectedObserver(
            in: fixture, at: identity, hashing: hashing, nestedIdentity: identity)
        try fixture.acceptBuild()
        XCTAssertTrue(nested.cell === ordinary.cell)
        XCTAssertTrue(nested.cell.isWritable)
        XCTAssertTrue(fixture.coordinator.registry.owner(at: identity) === original.owner)
        XCTAssertFalse(original.cell.isWritable)
        XCTAssertEqual(original.cell.readValue().baseline?.number, 10)
        fixture.events.assertNoObserverCallbacks()

        try assertFreshObservation(in: fixture, at: identity, replacing: original.cell, value: 30)
        let replacement = (
            owner: try XCTUnwrap(fixture.coordinator.registry.owner(at: identity)),
            cell: try XCTUnwrap(fixture.events.lastObserverCell)
        )
        XCTAssertTrue(replacement.owner === original.owner)
        XCTAssertFalse(replacement.cell === original.cell)
        fixture.events.resetCounters()
        try fixture.beginBuild()
        _ = try materializeRejectedObserver(in: fixture, at: identity, hashing: hashing, nestedIdentity: identity)
        try fixture.acceptBuild()
        XCTAssertEqual(replacement.cell.readValue().baseline?.number, 30)
        XCTAssertTrue(replacement.cell.isWritable)
        XCTAssertFalse(original.cell.isWritable)
        fixture.events.assertNoObserverCallbacks()
        try assertPreservedObservation(in: fixture, at: identity, original: replacement, from: 30, to: 50)
    }

    func testFallbackLookupCannotRecreateMarkerAfterItsParentWasDiscarded() async throws {
        try exerciseFallbackDiscard(rematerialize: false)
    }

    func testLaterMaterializationAfterFallbackDiscardCanObserveTheSameOccurrence() async throws {
        try exerciseFallbackDiscard(rematerialize: true)
    }

    func testNonNilFactoryCannotStageUpdateOrPreservationAfterPostFactoryParentDiscard() async throws {
        let fixture = try ObserverReentryFixture()
        let hashing = ObserverReentryGate()
        defer {
            hashing.disarm()
            fixture.close()
        }
        let parent = RetainedViewIdentity(segments: [.view(ObjectIdentifier(ObserverReentryRejectedParent.self))])
        let identity = observerReentryIdentity(hashing: hashing, prefix: parent.appending(.role(.content)))
        let original = try establishObserver(in: fixture, at: identity)
        var discards = 0
        fixture.stageObserver(
            at: identity, value: 20,
            duringFactory: {
                // Unlike the nil-factory case, a concrete update has been
                // constructed before its owner/cell admission hashes again.
                hashing.arm {
                    discards += 1
                    fixture.coordinator.discardUnadoptedSubtree(at: parent, preserveCommitted: false)
                }
            })
        hashing.disarm()
        XCTAssertEqual(hashing.firings, 1)
        XCTAssertEqual(discards, 1)
        XCTAssertEqual(fixture.events.seeds, 0)
        XCTAssertEqual(fixture.events.factories, 1)
        XCTAssertTrue(fixture.build.canAdopt)
        fixture.events.assertNoObserverCallbacks()

        try fixture.acceptBuild {
            XCTAssertFalse(original.cell.isWritable, "Neither the update nor its fallback may outlive parent discard")
        }
        XCTAssertNil(fixture.coordinator.registry.owner(at: identity))
        XCTAssertFalse(original.owner.isLive)
        XCTAssertFalse(original.cell.isWritable)
        XCTAssertEqual(original.cell.readValue().baseline?.number, 10)
        fixture.events.assertNoObserverCallbacks()
        try assertFreshObservation(in: fixture, at: identity, replacing: original.cell, value: 30)
    }

    func testDiscardCleanupRejectsMatchingStagesButAllowsAnUnrelatedPrefix() async throws {
        try exerciseAdmissionDuringDiscardCleanup(rematerialize: false)
    }

    func testMatchingPrefixCanRematerializeAfterDiscardCleanupReturns() async throws {
        try exerciseAdmissionDuringDiscardCleanup(rematerialize: true)
    }

    private func exerciseAdmissionDuringDiscardCleanup(rematerialize: Bool) throws {
        let fixture = try ObserverReentryFixture()
        let hashing = ObserverReentryGate()
        let cleanup = ObserverReentryGate()
        defer {
            hashing.disarm()
            cleanup.disarm()
            fixture.close()
        }
        let parent = RetainedViewIdentity(segments: [.view(ObjectIdentifier(ObserverReentryRejectedParent.self))])
        let identity = observerReentryIdentity(hashing: hashing, prefix: parent.appending(.role(.content)))
        let original = try establishObserver(in: fixture, at: identity)
        let victim = try installVictim(
            .cellPayload, prefix: parent.appending(.role(.overlay)), in: fixture.epoch, cleanup: cleanup)
        let unrelatedIdentity = RetainedViewIdentity(segments: [
            .view(ObjectIdentifier(ObserverReentryLateObserver.self))
        ])
        let unrelatedEvents = ObserverReentryEvents()
        var matchingSeeds = 0
        var matchingFactories = 0
        var discardReturned = false
        var cleanupRanInsideDiscard = false
        cleanup.arm {
            cleanupRanInsideDiscard = !discardReturned
            // The epoch has already selected the victim identities to remove.
            // Without the coordinator's active discard scope, a new matching
            // owner could be inserted after that selection and escape it.
            fixture.coordinator.stageOnChange(
                at: identity,
                seedObservation: {
                    matchingSeeds += 1
                    return ObserverReentryObservation()
                },
                makeUpdate: { owner, cell in
                    matchingFactories += 1
                    return ObserverReentryUpdate(owner: owner, cell: cell, value: 20, events: fixture.events)
                })
            fixture.coordinator.stageOnChange(
                at: unrelatedIdentity,
                seedObservation: {
                    unrelatedEvents.seeds += 1
                    let observation = ObserverReentryObservation()
                    unrelatedEvents.observations.append(ObserverReentryWeakObservation(observation))
                    return observation
                },
                makeUpdate: { owner, cell in
                    unrelatedEvents.factories += 1
                    unrelatedEvents.lastObserverCell = cell
                    return ObserverReentryUpdate(owner: owner, cell: cell, value: 70, events: unrelatedEvents)
                })
        }
        fixture.coordinator.discardUnadoptedSubtree(at: parent, preserveCommitted: false)
        hashing.disarm()
        cleanup.disarm()
        discardReturned = true
        XCTAssertEqual(cleanup.firings, 1)
        XCTAssertTrue(cleanupRanInsideDiscard)
        XCTAssertNil(victim.payload)
        XCTAssertNil(victim.cell)
        XCTAssertNil(victim.owner)
        XCTAssertEqual(matchingSeeds, 0)
        XCTAssertEqual(matchingFactories, 0)
        XCTAssertEqual(unrelatedEvents.seeds, 1, "Discard must not block unrelated materialization")
        XCTAssertEqual(unrelatedEvents.factories, 1)
        XCTAssertTrue(fixture.build.canAdopt)
        XCTAssertEqual(original.cell.readValue().baseline?.number, 10)
        fixture.events.assertNoObserverCallbacks()
        unrelatedEvents.assertNoObserverCallbacks()

        if rematerialize { fixture.stageObserver(at: identity, value: 30) }
        try fixture.acceptBuild()
        XCTAssertNotNil(fixture.coordinator.registry.owner(at: unrelatedIdentity))
        XCTAssertTrue(unrelatedEvents.lastObserverCell?.isWritable == true)
        XCTAssertEqual(unrelatedEvents.lastObserverCell?.readValue().baseline?.number, 70)
        XCTAssertEqual(unrelatedEvents.commits, 1)
        XCTAssertEqual(unrelatedEvents.deliveries, 1)
        XCTAssertEqual(unrelatedEvents.comparisonInputs, [])
        XCTAssertEqual(unrelatedEvents.actionValues, [])
        if rematerialize {
            XCTAssertTrue(fixture.coordinator.registry.owner(at: identity) === original.owner)
            XCTAssertTrue(fixture.events.lastObserverCell === original.cell)
            XCTAssertTrue(original.cell.isWritable)
            XCTAssertEqual(original.cell.readValue().baseline?.number, 30)
            XCTAssertEqual(fixture.events.commits, 1)
            XCTAssertEqual(fixture.events.deliveries, 1)
            XCTAssertEqual(fixture.events.comparisonInputs, [[10, 30]])
            XCTAssertEqual(fixture.events.actionValues, [30])
        } else {
            XCTAssertNil(fixture.coordinator.registry.owner(at: identity))
            XCTAssertFalse(original.owner.isLive)
            XCTAssertFalse(original.cell.isWritable)
            fixture.events.assertNoObserverCallbacks()
            try assertFreshObservation(in: fixture, at: identity, replacing: original.cell, value: 30)
        }
    }

    private func exerciseFallbackDiscard(rematerialize: Bool) throws {
        let fixture = try ObserverReentryFixture()
        let hashing = ObserverReentryGate()
        defer {
            hashing.disarm()
            fixture.close()
        }
        let parent = RetainedViewIdentity(segments: [.view(ObjectIdentifier(ObserverReentryRejectedParent.self))])
        let identity = observerReentryIdentity(hashing: hashing, prefix: parent.appending(.role(.content)))
        let original = try establishObserver(in: fixture, at: identity)
        var discards = 0
        fixture.stageObserver(
            at: identity, value: 20,
            duringFactory: {
                // The seed/cell resolution has already succeeded. Nil forces
                // the conditional committed lookup, whose real key hash
                // discards this still-running materialization's parent.
                hashing.arm {
                    discards += 1
                    fixture.coordinator.discardUnadoptedSubtree(at: parent, preserveCommitted: false)
                }
            }, declinesUpdate: true)
        hashing.disarm()
        XCTAssertEqual(hashing.firings, 1)
        XCTAssertEqual(discards, 1)
        XCTAssertEqual(fixture.events.seeds, 0)
        XCTAssertEqual(fixture.events.factories, 1)
        XCTAssertTrue(fixture.build.canAdopt)
        fixture.events.assertNoObserverCallbacks()
        XCTAssertEqual(original.cell.readValue().baseline?.number, 10)

        if rematerialize {
            // This is a separate call after discard and the first admission
            // both returned. A revoked receipt must not blacklist the path.
            fixture.stageObserver(at: identity, value: 30)
            try fixture.acceptBuild()
            XCTAssertTrue(fixture.coordinator.registry.owner(at: identity) === original.owner)
            XCTAssertTrue(fixture.events.lastObserverCell === original.cell)
            XCTAssertTrue(original.cell.isWritable)
            XCTAssertEqual(original.cell.readValue().baseline?.number, 30)
            XCTAssertEqual(fixture.events.factories, 2)
            XCTAssertEqual(fixture.events.commits, 1)
            XCTAssertEqual(fixture.events.deliveries, 1)
            XCTAssertEqual(fixture.events.comparisonInputs, [[10, 30]])
            XCTAssertEqual(fixture.events.actionValues, [30])
        } else {
            try fixture.acceptBuild {
                XCTAssertFalse(original.cell.isWritable, "The stale call must not republish its marker after discard")
            }
            XCTAssertNil(fixture.coordinator.registry.owner(at: identity))
            XCTAssertFalse(original.owner.isLive)
            XCTAssertFalse(original.cell.isWritable)
            fixture.events.assertNoObserverCallbacks()
            try assertFreshObservation(in: fixture, at: identity, replacing: original.cell, value: 30)
        }
    }

    private func exerciseCommittedPreservation(
        at point: ObserverReentryPoint, nestedInObserverOwner: Bool
    ) throws {
        let fixture = try ObserverReentryFixture()
        let hashing = ObserverReentryGate()
        defer {
            hashing.disarm()
            fixture.close()
        }
        let identity = observerReentryIdentity(hashing: hashing)
        let original = try establishObserver(in: fixture, at: identity)
        let nested = try materializeRejectedObserver(
            in: fixture, at: identity, hashing: hashing,
            nestedIdentity: nestedInObserverOwner ? identity : observerReentryOrdinaryIdentity(), point: point)
        XCTAssertEqual(original.cell.readValue().baseline?.number, 10)
        try fixture.acceptBuild {
            XCTAssertTrue(original.cell.isWritable, "The exact committed cell must survive preparation")
        }
        XCTAssertTrue(fixture.coordinator.registry.owner(at: identity) === original.owner)
        XCTAssertTrue(original.cell.isWritable)
        XCTAssertEqual(original.cell.readValue().baseline?.number, 10)
        XCTAssertTrue(nested.owner.isLive)
        XCTAssertTrue(nested.cell.isWritable)
        XCTAssertEqual(nested.cell.readValue(), 47)
        if nestedInObserverOwner { XCTAssertTrue(nested.owner === original.owner) }
        fixture.events.assertNoObserverCallbacks()
        XCTAssertTrue(nested.cell.write(48))
        XCTAssertEqual(fixture.events.invalidations, 1)
        try assertPreservedObservation(in: fixture, at: identity, original: original, from: 10, to: 30)
    }

    private func establishObserver(
        in fixture: ObserverReentryFixture, at identity: RetainedViewIdentity, value: Int = 10
    ) throws -> (owner: StateMountOwner, cell: MountedStateCell<ObserverReentryObservation>) {
        fixture.stageObserver(at: identity, value: value)
        try fixture.acceptBuild()
        let owner = try XCTUnwrap(fixture.coordinator.registry.owner(at: identity))
        let cell = try XCTUnwrap(fixture.events.lastObserverCell)
        XCTAssertTrue(owner.isLive)
        XCTAssertTrue(cell.isWritable)
        XCTAssertEqual(cell.readValue().baseline?.number, value)
        fixture.events.resetCounters()
        try fixture.beginBuild()
        return (owner, cell)
    }

    private func materializeRejectedObserver(
        in fixture: ObserverReentryFixture, at identity: RetainedViewIdentity, hashing: ObserverReentryGate,
        nestedIdentity: RetainedViewIdentity? = nil, point: ObserverReentryPoint = .identityHash
    ) throws -> (owner: StateMountOwner, cell: MountedStateCell<Int>) {
        var nested: (owner: StateMountOwner, cell: MountedStateCell<Int>)?
        let resolve: @MainActor () -> Void = {
            nested = self.resolveOrdinary(in: fixture, at: nestedIdentity ?? observerReentryOrdinaryIdentity())
        }
        if point == .identityHash { hashing.arm(resolve) }
        let duringFactory: (@MainActor () -> Void)?
        if point == .finalAdmissionHash {
            duringFactory = { hashing.arm(resolve) }
        } else {
            duringFactory = nil
        }
        fixture.stageObserver(
            at: identity, value: 20,
            duringFactory: duringFactory)
        hashing.disarm()
        XCTAssertEqual(hashing.firings, 1)
        XCTAssertEqual(fixture.events.seeds, 0)
        XCTAssertEqual(fixture.events.factories, point == .finalAdmissionHash ? 1 : 0)
        XCTAssertTrue(fixture.build.canAdopt)
        fixture.events.assertNoObserverCallbacks()
        return try XCTUnwrap(nested)
    }

    private func resolveOrdinary(
        in fixture: ObserverReentryFixture, at identity: RetainedViewIdentity, seed: Int = 47
    ) -> (owner: StateMountOwner, cell: MountedStateCell<Int>)? {
        guard let owner = fixture.epoch.owner(at: identity) else {
            XCTFail("The current build must admit its nested ordinary owner")
            return nil
        }
        let slot = StatePropertySlot(concreteTypes: [ObjectIdentifier(ObserverReentryNestedSlot.self)])
        return (owner, owner.resolve(at: slot) { seed })
    }

    private func assertPreservedObservation(
        in fixture: ObserverReentryFixture, at identity: RetainedViewIdentity,
        original: (owner: StateMountOwner, cell: MountedStateCell<ObserverReentryObservation>),
        from oldValue: Int, to newValue: Int
    ) throws {
        fixture.events.resetCounters()
        try fixture.beginBuild()
        fixture.stageObserver(at: identity, value: newValue)
        try fixture.acceptBuild()
        XCTAssertEqual(fixture.events.seeds, 0)
        XCTAssertTrue(fixture.events.lastObserverCell === original.cell)
        XCTAssertTrue(fixture.coordinator.registry.owner(at: identity) === original.owner)
        XCTAssertEqual(original.cell.readValue().baseline?.number, newValue)
        XCTAssertEqual(fixture.events.commits, 1)
        XCTAssertEqual(fixture.events.deliveries, 1)
        XCTAssertEqual(fixture.events.comparisonInputs, [[oldValue, newValue]])
        XCTAssertEqual(fixture.events.actionValues, [newValue])
    }

    private func assertFreshObservation(
        in fixture: ObserverReentryFixture, at identity: RetainedViewIdentity,
        replacing oldCell: MountedStateCell<ObserverReentryObservation>, value: Int
    ) throws {
        fixture.events.resetCounters()
        try fixture.beginBuild()
        fixture.stageObserver(at: identity, value: value)
        try fixture.acceptBuild()
        XCTAssertEqual(fixture.events.seeds, 1)
        XCTAssertFalse(fixture.events.lastObserverCell === oldCell)
        XCTAssertEqual(fixture.events.lastObserverCell?.readValue().baseline?.number, value)
        XCTAssertFalse(oldCell.isWritable)
        XCTAssertEqual(fixture.events.commits, 1)
        XCTAssertEqual(fixture.events.deliveries, 1)
        XCTAssertEqual(fixture.events.comparisonInputs, [])
        XCTAssertEqual(fixture.events.actionValues, [])
    }

    private func exerciseOrdinaryResolution(
        at point: ObserverReentryPoint, mutation: ObserverReentryMutation
    ) throws {
        let fixture = try ObserverReentryFixture()
        let hashing = ObserverReentryGate()
        defer {
            hashing.disarm()
            fixture.close()
        }
        let identity = observerReentryIdentity(hashing: hashing)
        let ordinaryIdentity = RetainedViewIdentity(segments: [
            .view(ObjectIdentifier(ObserverReentryOrdinaryOwner.self))
        ])
        let firstSlot = StatePropertySlot(concreteTypes: [ObjectIdentifier(ObserverReentryFirstSlot.self)])
        let nestedSlot = StatePropertySlot(concreteTypes: [ObjectIdentifier(ObserverReentryNestedSlot.self)])
        var previousOwner: StateMountOwner?
        var previousCell: MountedStateCell<Int>?
        if mutation != .newOwnerAndCell {
            let owner = try XCTUnwrap(fixture.epoch.owner(at: ordinaryIdentity))
            let slot = mutation == .existingOwnerAndCell ? nestedSlot : firstSlot
            previousOwner = owner
            previousCell = owner.resolve(at: slot) { 11 }
        }

        var nestedOwner: StateMountOwner?
        var nestedCell: MountedStateCell<Int>?
        var nestedSeeds = 0
        var reentries = 0
        var phaseAtReentry: ObserverReentryPoint?
        let resolveOrdinary: @MainActor () -> Void = {
            reentries += 1
            phaseAtReentry =
                fixture.events.factories > 0
                ? .finalAdmissionHash : fixture.events.seeds > 0 ? .seed : .identityHash
            guard let owner = fixture.epoch.owner(at: ordinaryIdentity) else {
                XCTFail("The still-current epoch must admit the ordinary State owner")
                return
            }
            nestedOwner = owner
            nestedCell = owner.resolve(at: nestedSlot) {
                nestedSeeds += 1
                return 47
            }
        }
        if point == .identityHash { hashing.arm(resolveOrdinary) }
        let duringFactory: (@MainActor () -> Void)?
        if point == .finalAdmissionHash {
            duringFactory = { hashing.arm(resolveOrdinary) }
        } else {
            duringFactory = nil
        }
        fixture.stageObserver(
            at: identity,
            duringSeed: point == .seed ? resolveOrdinary : nil,
            duringFactory: duringFactory)
        // A missed target must never leave an authored callback armed during
        // the ordinary registry's subsequent adoption or retirement work.
        hashing.disarm()
        let label = "\(point), \(mutation)"

        XCTAssertEqual(reentries, 1, label)
        XCTAssertEqual(phaseAtReentry, point, label)
        XCTAssertEqual(hashing.firings, point == .seed ? 0 : 1, label)
        XCTAssertEqual(fixture.events.seeds, point == .identityHash ? 0 : 1, label)
        XCTAssertEqual(fixture.events.factories, point == .finalAdmissionHash ? 1 : 0, label)
        XCTAssertEqual(nestedSeeds, mutation == .existingOwnerAndCell ? 0 : 1, label)
        XCTAssertTrue(fixture.build.canAdopt, "Ordinary resolution does not supersede the candidate: \(label)")
        XCTAssertFalse(fixture.coordinator.registry.isClosed, label)
        fixture.events.assertNoObserverCallbacks()

        let owner = try XCTUnwrap(nestedOwner)
        let cell = try XCTUnwrap(nestedCell)
        if let previousOwner { XCTAssertTrue(owner === previousOwner, label) }
        if mutation == .existingOwnerAndCell { XCTAssertTrue(cell === previousCell, label) }
        let expected = mutation == .existingOwnerAndCell ? 11 : 47
        XCTAssertEqual(cell.readValue(), expected, label)
        if point != .finalAdmissionHash {
            XCTAssertFalse(
                fixture.epoch.visitedOwnerIdentities.contains(identity),
                "A discarded observer snapshot must not be published over the nested maps: \(label)")
        }
        if point == .seed {
            XCTAssertEqual(fixture.events.liveObservations, 1, "Rejected seed cleanup must wait for build finish")
        }

        try fixture.acceptBuild()
        XCTAssertTrue(fixture.coordinator.registry.owner(at: ordinaryIdentity) === owner, label)
        XCTAssertTrue(owner.isLive, label)
        XCTAssertTrue(cell.isWritable, label)
        XCTAssertEqual(cell.readValue(), expected, label)
        if let previousCell {
            XCTAssertTrue(previousCell.isWritable, label)
            XCTAssertEqual(previousCell.readValue(), 11, label)
        }
        fixture.events.assertNoObserverCallbacks()
        if point == .finalAdmissionHash {
            XCTAssertNotNil(fixture.coordinator.registry.owner(at: identity), label)
            XCTAssertNil(fixture.events.lastObserverCell?.readValue().baseline, label)
        } else {
            XCTAssertNil(fixture.coordinator.registry.owner(at: identity), label)
            XCTAssertEqual(
                fixture.events.liveObservations, 0, "An accepted build must finish its rejected seed cleanup")
        }
        XCTAssertTrue(cell.write(expected + 1), label)
        XCTAssertEqual(cell.readValue(), expected + 1, label)
        XCTAssertEqual(fixture.events.invalidations, 1, "The nested cell must be live, not a writable-looking orphan")
        fixture.events.assertNoObserverCallbacks()

        fixture.close()
        XCTAssertFalse(cell.isWritable, label)
        XCTAssertEqual(fixture.events.liveObservations, 0, label)
        XCTAssertEqual(fixture.coordinator.registry.liveOwnerCount, 0, label)
        XCTAssertEqual(fixture.coordinator.registry.retiringOwnerCount, 0, label)
        withExtendedLifetime(fixture.epoch) {}
    }

    private func exerciseSnapshotCleanup(
        of victimKind: ObserverReentryVictim, cancellation: ObserverReentryCancellation
    ) throws {
        let fixture = try ObserverReentryFixture()
        let hashing = ObserverReentryGate()
        let cleanup = ObserverReentryGate()
        defer {
            hashing.disarm()
            cleanup.disarm()
            fixture.close()
        }
        let victimPrefix = RetainedViewIdentity(segments: [.view(ObjectIdentifier(ObserverReentryVictimOwner.self))])
        let victim = try installVictim(victimKind, prefix: victimPrefix, in: fixture.epoch, cleanup: cleanup)
        XCTAssertNotNil(victim.owner)
        XCTAssertNotNil(victim.cell)
        XCTAssertNotNil(victim.payload)
        let identity = observerReentryIdentity(hashing: hashing)
        let lateIdentity = RetainedViewIdentity(segments: [.view(ObjectIdentifier(ObserverReentryLateObserver.self))])
        var order: [ObserverReentryCleanupStep] = []
        var remainedPinnedAfterDiscard = false
        var lateResolutionRejected: Bool?
        var lateSeeds = 0
        var lateFactories = 0

        cleanup.arm {
            order.append(.cleanup)
            switch cancellation {
            case .close: fixture.coordinator.close()
            case .supersede: fixture.build.supersede()
            }
            let late = fixture.epoch.resolveSyntheticObservation(at: lateIdentity) {
                lateSeeds += 1
                return ObserverReentryObservation()
            }
            lateResolutionRejected = late == nil
            fixture.coordinator.stageOnChange(
                at: lateIdentity,
                seedObservation: {
                    lateSeeds += 1
                    return ObserverReentryObservation()
                },
                makeUpdate: { _, _ in
                    lateFactories += 1
                    return nil
                })
        }
        hashing.arm {
            order.append(.hash)
            fixture.epoch.discardUnadoptedSubtree(at: victimPrefix, preserveCommitted: false)
            // These are weak handles. Only the observer's old local maps can
            // still own this removed provisional owner, cell, and payload.
            remainedPinnedAfterDiscard = victim.owner != nil && victim.cell != nil && victim.payload != nil
            order.append(.discardReturned)
        }
        fixture.stageObserver(at: identity)
        hashing.disarm()
        cleanup.disarm()
        order.append(.stageReturned)
        let label = "\(victimKind), \(cancellation)"

        XCTAssertEqual(hashing.firings, 1, label)
        XCTAssertTrue(remainedPinnedAfterDiscard, "The callback must come from snapshot cleanup, not discard: \(label)")
        XCTAssertEqual(cleanup.firings, 1, label)
        XCTAssertEqual(order, [.hash, .discardReturned, .cleanup, .stageReturned], label)
        XCTAssertNil(victim.payload, label)
        XCTAssertNil(victim.cell, label)
        XCTAssertNil(victim.owner, label)
        XCTAssertEqual(lateResolutionRejected, true, label)
        XCTAssertEqual(lateSeeds, 0, label)
        XCTAssertEqual(lateFactories, 0, label)
        XCTAssertEqual(fixture.events.seeds, 0, label)
        XCTAssertEqual(fixture.events.factories, 0, label)
        XCTAssertFalse(fixture.build.canAdopt, label)
        XCTAssertEqual(fixture.coordinator.registry.isClosed, cancellation == .close, label)
        fixture.events.assertNoObserverCallbacks()
        let visited = fixture.epoch.visitedOwnerIdentities
        XCTAssertFalse(visited.contains(identity), label)
        XCTAssertFalse(visited.contains(lateIdentity), label)
        XCTAssertFalse(visited.contains { $0.segments.starts(with: victimPrefix.segments) }, label)

        fixture.abandonBuild()
        fixture.events.assertNoObserverCallbacks()
        XCTAssertEqual(fixture.coordinator.registry.liveOwnerCount, 0, label)
        XCTAssertEqual(fixture.coordinator.registry.retiringOwnerCount, 0, label)
        XCTAssertEqual(fixture.events.liveObservations, 0, label)
        withExtendedLifetime(fixture.epoch) {}
    }

    private func installVictim(
        _ kind: ObserverReentryVictim, prefix: RetainedViewIdentity,
        in epoch: StateMountEpoch, cleanup: ObserverReentryGate
    ) throws -> ObserverReentryWeakVictim {
        // This scope drops every strong fixture handle before observation.
        // The identity lifetime case is addressed later by its plain prefix;
        // retaining the full authored key here would prevent owner cleanup.
        let payload = ObserverReentryReleaseProbe { cleanup.fire() }
        let identity: RetainedViewIdentity
        if kind == .ownerIdentity {
            identity = prefix.appending(.explicit(.init(ObserverReentryLifetimeKey(value: 7, lifetime: payload))))
        } else {
            identity = prefix
        }
        let owner = try XCTUnwrap(epoch.owner(at: identity))
        let slot = StatePropertySlot(concreteTypes: [ObjectIdentifier(ObserverReentryVictimSlot.self)])
        switch kind {
        case .cellPayload:
            let cell = owner.resolve(at: slot) { payload }
            return ObserverReentryWeakVictim(owner: owner, cell: cell, payload: payload)
        case .ownerIdentity:
            let cell = owner.resolve(at: slot) { 29 }
            return ObserverReentryWeakVictim(owner: owner, cell: cell, payload: payload)
        }
    }
}

private enum ObserverReentryMutation: CaseIterable, Equatable {
    case newOwnerAndCell
    case existingOwnerNewSlot
    case existingOwnerAndCell
}

private enum ObserverReentryPoint: Equatable {
    case identityHash
    case seed
    case finalAdmissionHash
}

private enum ObserverReentryVictim: Equatable {
    case cellPayload
    case ownerIdentity
}

private enum ObserverReentryCancellation: CaseIterable, Equatable {
    case close
    case supersede
}

private enum ObserverReentryCleanupStep: Equatable {
    case hash
    case discardReturned
    case cleanup
    case stageReturned
}

private enum ObserverReentryFailure: Error {
    case rejectedPreparation
    case unfinishedBuild
}

private enum ObserverReentryFixtureOwner {}
private enum ObserverReentryOrdinaryOwner {}
private enum ObserverReentryFirstSlot {}
private enum ObserverReentryNestedSlot {}
private enum ObserverReentryVictimOwner {}
private enum ObserverReentryVictimSlot {}
private enum ObserverReentryLateObserver {}
private enum ObserverReentryRejectedParent {}
private enum ObserverReentryChild {}
private enum ObserverReentryFitsOrdinaryOwner {}

@MainActor
private final class ObserverReentryFitsProbe {
    let events = ObserverReentryEvents()
    let hashing = ObserverReentryGate()
    var value = 10
    var primaryFits = true
    var reenterOnNextMaterialization = false
    var reentries = 0
    var identity: RetainedViewIdentity?
}

@MainActor
private struct ObserverReentryFitsView: View {
    typealias Body = Never
    let value: Int
    let width: Double
    let probe: ObserverReentryFitsProbe

    var body: Never { fatalError("The admission fixture constructs its retained node directly") }

    func makeComponent(context: ViewBuildContext) -> Component {
        Component { _ in
            guard let coordinator = context.stateMountCoordinator,
                let installedOwner = context.viewIdentity.installedOwner,
                let epoch = installedOwner.installationEpoch
            else {
                XCTFail("The retained host must provide the candidate's actual installation")
                return Controls.panel(preferredSize: Size(width: width, height: 40), isHitTestVisible: false)
            }
            let identity = context.retainedViewIdentity
            probe.identity = identity
            if probe.reenterOnNextMaterialization {
                probe.reenterOnNextMaterialization = false
                // Installation and context lookup have finished. Only the
                // following observer admission sees the armed authored key.
                probe.hashing.arm {
                    probe.reentries += 1
                    let nestedIdentity = RetainedViewIdentity(segments: [
                        .view(ObjectIdentifier(ObserverReentryFitsOrdinaryOwner.self))
                    ])
                    guard let owner = epoch.owner(at: nestedIdentity) else {
                        XCTFail("Ordinary nested construction must remain admitted")
                        return
                    }
                    let slot = StatePropertySlot(concreteTypes: [ObjectIdentifier(ObserverReentryNestedSlot.self)])
                    _ = owner.resolve(at: slot) { 47 }
                }
            }
            coordinator.stageOnChange(
                at: identity,
                seedObservation: {
                    probe.events.seeds += 1
                    let observation = ObserverReentryObservation()
                    probe.events.observations.append(ObserverReentryWeakObservation(observation))
                    return observation
                },
                makeUpdate: { owner, cell in
                    probe.events.factories += 1
                    probe.events.lastObserverCell = cell
                    return ObserverReentryUpdate(owner: owner, cell: cell, value: value, events: probe.events)
                })
            probe.hashing.disarm()
            return Controls.panel(preferredSize: Size(width: width, height: 40), isHitTestVisible: false)
        }
    }
}

@MainActor
private final class ObserverReentryFixture {
    let events: ObserverReentryEvents
    let coordinator: StateMountCoordinator
    private(set) var build: any RetainedBuildEpoch
    private(set) var epoch: StateMountEpoch
    private var didFinish = false

    init() throws {
        let events = ObserverReentryEvents()
        self.events = events
        let coordinator = StateMountCoordinator(
            invalidate: { events.invalidations += 1 },
            observeObject: { _ in }, updateObservedObjects: { _, _, _ in })
        self.coordinator = coordinator
        build = try XCTUnwrap(coordinator.beginBuild())
        var capturedEpoch: StateMountEpoch?
        let anchor = RetainedViewIdentity(segments: [.view(ObjectIdentifier(ObserverReentryFixtureOwner.self))])
        // The existing compatibility entry supplies a real installing owner.
        // No private epoch constructor or fabricated adoption receipt is used.
        coordinator.stageOnChange(at: anchor) { owner in
            capturedEpoch = owner.installationEpoch
            return ObserverReentryAnchorUpdate(owner: owner)
        }
        epoch = try XCTUnwrap(capturedEpoch)
    }

    func beginBuild() throws {
        XCTAssertTrue(didFinish)
        guard didFinish else { throw ObserverReentryFailure.unfinishedBuild }
        build = try XCTUnwrap(coordinator.beginBuild())
        didFinish = false
        var capturedEpoch: StateMountEpoch?
        let anchor = RetainedViewIdentity(segments: [.view(ObjectIdentifier(ObserverReentryFixtureOwner.self))])
        coordinator.stageOnChange(at: anchor) { owner in
            capturedEpoch = owner.installationEpoch
            return ObserverReentryAnchorUpdate(owner: owner)
        }
        epoch = try XCTUnwrap(capturedEpoch)
    }

    func stageObserver(
        at identity: RetainedViewIdentity, value: Int = 20, duringSeed: (@MainActor () -> Void)? = nil,
        duringFactory: (@MainActor () -> Void)? = nil, declinesUpdate: Bool = false
    ) {
        coordinator.stageOnChange(
            at: identity,
            seedObservation: {
                self.events.seeds += 1
                let observation = ObserverReentryObservation()
                self.events.observations.append(ObserverReentryWeakObservation(observation))
                duringSeed?()
                return observation
            },
            makeUpdate: { owner, cell in
                self.events.factories += 1
                self.events.lastObserverCell = cell
                duringFactory?()
                guard !declinesUpdate else { return nil }
                return ObserverReentryUpdate(owner: owner, cell: cell, value: value, events: self.events)
            })
    }

    func acceptBuild(beforeCommit: (@MainActor () -> Void)? = nil) throws {
        let prepared = build.willAdopt()
        XCTAssertTrue(prepared)
        guard prepared else { throw ObserverReentryFailure.rejectedPreparation }
        beforeCommit?()
        build.commit()
        XCTAssertTrue(build.canComplete)
        build.finishAfterCallbacks()
        didFinish = true
    }

    func abandonBuild() {
        guard !didFinish else { return }
        build.abandon()
        build.finishAfterCallbacks()
        didFinish = true
    }

    func close() {
        coordinator.close()
        abandonBuild()
    }
}

@MainActor
private final class ObserverReentryAnchorUpdate: MountedOnChangeUpdate {
    let owner: StateMountOwner

    init(owner: StateMountOwner) { self.owner = owner }
    func commit() {}
    func deliver() {}
}

@MainActor
private final class ObserverReentryEvents {
    var seeds = 0
    var factories = 0
    var commits = 0
    var deliveries = 0
    var equalities = 0
    var actions = 0
    var invalidations = 0
    var comparisonInputs: [[Int]] = []
    var actionValues: [Int] = []
    var observations: [ObserverReentryWeakObservation] = []
    weak var lastObserverCell: MountedStateCell<ObserverReentryObservation>?

    var liveObservations: Int { observations.filter { $0.value != nil }.count }

    func assertNoObserverCallbacks(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(commits, 0, file: file, line: line)
        XCTAssertEqual(deliveries, 0, file: file, line: line)
        XCTAssertEqual(equalities, 0, file: file, line: line)
        XCTAssertEqual(actions, 0, file: file, line: line)
        XCTAssertEqual(comparisonInputs, [], file: file, line: line)
        XCTAssertEqual(actionValues, [], file: file, line: line)
    }

    func resetCounters() {
        seeds = 0
        factories = 0
        commits = 0
        deliveries = 0
        equalities = 0
        actions = 0
        invalidations = 0
        comparisonInputs = []
        actionValues = []
    }
}

@MainActor
private final class ObserverReentryObservation {
    var baseline: ObserverReentryValue?
}

@MainActor
private final class ObserverReentryUpdate: MountedOnChangeUpdate {
    let owner: StateMountOwner
    private let cell: MountedStateCell<ObserverReentryObservation>
    private let events: ObserverReentryEvents
    private let proposed: ObserverReentryValue
    private var previous: ObserverReentryValue?

    init(
        owner: StateMountOwner, cell: MountedStateCell<ObserverReentryObservation>, value: Int,
        events: ObserverReentryEvents
    ) {
        self.owner = owner
        self.cell = cell
        self.events = events
        proposed = ObserverReentryValue(number: value, events: events)
    }

    func commit() {
        events.commits += 1
        previous = cell.readValue().baseline
        cell.readValue().baseline = proposed
    }

    func deliver() {
        events.deliveries += 1
        if let previous, previous != proposed {
            events.actions += 1
            events.actionValues.append(proposed.number)
        }
    }
}

private struct ObserverReentryValue: Equatable {
    let number: Int
    let events: ObserverReentryEvents

    static func == (lhs: Self, rhs: Self) -> Bool {
        MainActor.assumeIsolated {
            lhs.events.equalities += 1
            lhs.events.comparisonInputs.append([lhs.number, rhs.number])
        }
        return lhs.number == rhs.number
    }
}

@MainActor
private final class ObserverReentryWeakObservation {
    weak var value: ObserverReentryObservation?

    init(_ value: ObserverReentryObservation) { self.value = value }
}

@MainActor
private final class ObserverReentryWeakVictim {
    weak var owner: StateMountOwner?
    weak var cell: AnyObject?
    weak var payload: ObserverReentryReleaseProbe?

    init(owner: StateMountOwner, cell: AnyObject, payload: ObserverReentryReleaseProbe) {
        self.owner = owner
        self.cell = cell
        self.payload = payload
    }
}

@MainActor
private final class ObserverReentryReleaseProbe {
    private let onRelease: @MainActor () -> Void

    init(onRelease: @escaping @MainActor () -> Void) { self.onRelease = onRelease }

    isolated deinit { onRelease() }
}

@MainActor
private final class ObserverReentryGate {
    private var action: (@MainActor () -> Void)?
    private(set) var firings = 0

    func arm(_ action: @escaping @MainActor () -> Void) {
        firings = 0
        self.action = action
    }

    func disarm() { action = nil }

    func fire() {
        guard let action else { return }
        self.action = nil
        firings += 1
        action()
    }
}

private struct ObserverReentryHashKey: Hashable {
    let value: Int
    let hashing: ObserverReentryGate

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.value == rhs.value }

    func hash(into hasher: inout Hasher) {
        hasher.combine(value)
        MainActor.assumeIsolated { hashing.fire() }
    }
}

private struct ObserverReentryLifetimeKey: Hashable {
    let value: Int
    let lifetime: ObserverReentryReleaseProbe

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.value == rhs.value }

    func hash(into hasher: inout Hasher) { hasher.combine(value) }
}

@MainActor
private func observerReentryIdentity(
    hashing: ObserverReentryGate, prefix: RetainedViewIdentity = RetainedViewIdentity()
) -> RetainedViewIdentity {
    prefix.appending(.explicit(.init(ObserverReentryHashKey(value: 17, hashing: hashing))))
}

@MainActor
private func observerReentryOrdinaryIdentity() -> RetainedViewIdentity {
    RetainedViewIdentity(segments: [.view(ObjectIdentifier(ObserverReentryOrdinaryOwner.self))])
}
