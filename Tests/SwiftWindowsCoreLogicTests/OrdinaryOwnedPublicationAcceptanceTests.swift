import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI

@MainActor
final class OrdinaryOwnedPublicationAcceptanceTests: XCTestCase {
    func testOrdinaryNilControllerDetachCloseDoesNotPublishRejectedOwnedFacets() async throws {
        let runtime = RetainedViewRuntime(root: publicationAcceptanceNode())
        let target = publicationAcceptanceNode()
        let host = runtime.lazyListLogicalHostLifetime
        let controller = PublicationAcceptanceClosingController { runtime.stopRenderLifecycleCallbacks() }
        target.textInputController = controller
        let original = try PublicationAcceptanceSeed(runtime: runtime, node: target)
        let source = publicationAcceptanceNode()
        let next = PublicationAcceptanceEpoch(runtime)
        let continued = try next.component(
            source: source, slots: original.slots, continuing: original.component.owned)
        let preparation = try next.begin()
        let plan = try publicationAcceptancePlan(for: continued.owned, in: preparation)
        let storage = target.lazyListActivityStorage()
        let targetID = storage.targetID
        let attachmentID = storage.attachmentID
        let ticket = try XCTUnwrap(
            next.journal.recordOrdinaryPhysicalDeparture(of: target, cause: .acceptedReplacement))
        defer { withExtendedLifetime((original, next, source, plan, controller, ticket)) {} }

        XCTAssertNil(source.textInputController)
        XCTAssertNil(target.buttonActionOwner)
        XCTAssertNil(next.journal.uiaContinuationAuthority)
        XCTAssertFalse(continued.owned.hasAcceptedDeclaration)
        XCTAssertTrue(
            target.reconcileTextInputController(
                from: source, admission: nil, lazyJournal: next.journal,
                taskAdoption: nil, uiaAuthority: nil))

        XCTAssertEqual(controller.detachCalls, 1)
        XCTAssertFalse(host.isOpen)
        XCTAssertNil(target.textInputController)
        XCTAssertTrue(target.parent === runtime.root)
        XCTAssertTrue(target.lazyListActivityStorage() === storage)
        XCTAssertTrue(storage.targetID === targetID)
        XCTAssertTrue(storage.attachmentID === attachmentID)
        XCTAssertTrue(original.actual.isAttached)
        XCTAssertFalse(continued.owned.hasAcceptedDeclaration)
        for slot in original.slots {
            XCTAssertFalse(continued.owned.permitsOwnedWrite(for: slot))
        }

        next.journal.finishOrdinaryOwnedDeparture(ticket)
        next.journal.finishOrdinaryOwnedDeparture(ticket)
        let disposition = next.finish()
        try assertPublicationAcceptance(disposition, plan: plan, on: target, accepted: false)
        assertPublicationRetirement(disposition, owned: original.component.owned, slots: original.slots, count: 1)
        XCTAssertEqual(controller.detachCalls, 1)
    }

    func testRejectedPropertyPublicationRetiresOnlyTheActuallyReplacedPayloadFields() async throws {
        for replaceBothFields in [false, true] {
            let runtime = RetainedViewRuntime(root: publicationAcceptanceNode())
            let target = publicationAcceptanceNode()
            target.onAppear = {}
            target.onDisappear = {}
            let original = try PublicationAcceptanceSeed(runtime: runtime, node: target)
            let source = publicationAcceptanceNode()
            let next = PublicationAcceptanceEpoch(runtime)
            let incomingSlot = RetainedOwnedSlotGenerationID()
            let incoming = try next.component(source: source, slots: [incomingSlot])
            let preparation = try next.begin()
            let plan = try publicationAcceptancePlan(for: incoming.owned, in: preparation)
            defer { withExtendedLifetime((original, next, source, plan)) {} }

            XCTAssertNil(target.retainedViewIdentity)
            XCTAssertNil(source.onAppear)
            XCTAssertNil(source.onDisappear)
            XCTAssertTrue(
                next.journal.preparePropertyCopy(from: source, to: target, keyPath: \ViewNode.onAppear))
            XCTAssertTrue(
                next.journal.preparePropertyCopy(from: source, to: target, keyPath: \ViewNode.onDisappear))
            runtime.lazyListLogicalHostLifetime.revoke()

            target.onAppear = nil
            _ = next.journal.recordAcceptedProperty(from: source, to: target, keyPath: \ViewNode.onAppear)
            if replaceBothFields {
                target.onDisappear = nil
                _ = next.journal.recordAcceptedProperty(
                    from: source, to: target, keyPath: \ViewNode.onDisappear)
            }

            XCTAssertNil(target.onAppear)
            XCTAssertEqual(target.onDisappear == nil, replaceBothFields)
            XCTAssertTrue(original.actual.isAttached)
            XCTAssertFalse(incoming.owned.hasAcceptedDeclaration)
            XCTAssertFalse(incoming.owned.permitsOwnedWrite(for: incomingSlot))
            let disposition = next.finish()
            try assertPublicationAcceptance(disposition, plan: plan, on: target, accepted: false)
            assertPublicationRetirement(
                disposition, owned: original.component.owned, slots: original.slots,
                count: replaceBothFields ? 1 : 0)
        }
    }

    func testLiveSuspendedPropertyContinuationKeepsTheOriginalPermission() async throws {
        let runtime = RetainedViewRuntime(root: publicationAcceptanceNode())
        let target = publicationAcceptanceNode()
        let original = try PublicationAcceptanceSeed(runtime: runtime, node: target)
        let source = publicationAcceptanceNode()
        source.opacity = 0.4
        let next = PublicationAcceptanceEpoch(runtime)
        let continued = try next.component(
            source: source, slots: original.slots, continuing: original.component.owned)
        let preparation = try next.begin()
        let plan = try publicationAcceptancePlan(for: continued.owned, in: preparation)
        let storage = target.lazyListActivityStorage()
        let attachmentID = storage.attachmentID
        let ticket = try XCTUnwrap(
            next.journal.recordOrdinaryPhysicalDeparture(of: target, cause: .acceptedReplacement))
        defer { withExtendedLifetime((original, next, source, plan, ticket)) {} }

        for slot in original.slots {
            XCTAssertFalse(continued.owned.permitsOwnedWrite(for: slot))
        }
        XCTAssertTrue(next.journal.preparePropertyCopy(from: source, to: target, keyPath: \ViewNode.opacity))
        target.opacity = source.opacity
        _ = next.journal.recordAcceptedProperty(from: source, to: target, keyPath: \ViewNode.opacity)

        XCTAssertTrue(continued.owned.owner === original.component.owned.owner)
        XCTAssertTrue(continued.owned.hasAcceptedDeclaration)
        XCTAssertTrue(storage.attachmentID === attachmentID)
        XCTAssertTrue(original.actual.isAttached)
        for slot in original.slots {
            XCTAssertFalse(continued.owned.permitsOwnedWrite(for: slot))
        }

        // Sealing drains the original same-attachment ticket; accepting another
        // facet alone does not end that ticket's write suspension.
        let disposition = next.finish()
        try assertPublicationAcceptance(disposition, plan: plan, on: target, accepted: true)
        assertPublicationOwnership(continued.owned, slots: original.slots, accepted: true)
        assertPublicationRetirement(disposition, owned: original.component.owned, slots: original.slots, count: 0)

        let removal = try removePublicationFootprint(of: target, in: runtime)
        assertPublicationRetirement(removal, owned: original.component.owned, slots: original.slots, count: 1)
        assertPublicationOwnership(continued.owned, slots: original.slots, accepted: false)
    }

    func testPreparedDeclaredPublicationRejectsClosedOriginalNativeLifetime() async throws {
        for closeHost in [false, true] {
            let runtime = RetainedViewRuntime(root: publicationAcceptanceNode())
            let target = publicationAcceptanceNode()
            let original = try PublicationAcceptanceSeed(runtime: runtime, node: target)
            let source = publicationAcceptanceNode()
            let next = PublicationAcceptanceEpoch(runtime)
            _ = try next.component(
                source: source, slots: original.slots, continuing: original.component.owned)
            _ = try next.begin()

            let markerSource = publicationAcceptanceNode()
            let markerEpoch = PublicationAcceptanceEpoch(runtime)
            let marker = try markerEpoch.component(
                source: markerSource, slots: original.slots,
                continuing: original.component.owned, declarationOnly: true)
            let preparation = try markerEpoch.begin()
            let plan = try publicationAcceptancePlan(for: marker.owned, in: preparation)
            let storage = target.lazyListActivityStorage()
            let targetID = storage.targetID
            let attachmentID = storage.attachmentID
            // Both original plans were registered and frozen while the old
            // owner was writable, before the ordinary handoff suspended it.
            let ticket = try XCTUnwrap(
                next.journal.recordOrdinaryPhysicalDeparture(of: target, cause: .acceptedReplacement))
            markerEpoch.prepareDeclaration(from: markerSource, to: target)
            defer {
                withExtendedLifetime((original, next, source, markerEpoch, markerSource, plan, ticket)) {}
            }

            if closeHost {
                runtime.lazyListLogicalHostLifetime.revoke()
            } else {
                original.epoch.scope.revokeForOwnerClose()
            }
            markerEpoch.acceptDeclaration(from: markerSource, to: target)

            XCTAssertFalse(marker.owned.hasAcceptedDeclaration)
            for slot in original.slots {
                XCTAssertFalse(marker.owned.permitsOwnedWrite(for: slot))
            }
            next.journal.finishOrdinaryOwnedDeparture(ticket)
            let departure = next.finish()

            // This check precedes any other publication or physical removal
            // that could erase a refused marker and conceal its ghost facet.
            assertPublicationRetirement(
                departure, owned: original.component.owned, slots: original.slots, count: 1)
            XCTAssertTrue(target.parent === runtime.root)
            XCTAssertTrue(original.actual.isAttached)
            XCTAssertTrue(target.lazyListActivityStorage() === storage)
            XCTAssertTrue(storage.targetID === targetID)
            XCTAssertTrue(storage.attachmentID === attachmentID)
            try assertPublicationAcceptance(markerEpoch.finish(), plan: plan, on: target, accepted: false)
        }
    }

    func testRejectedDeclaredRosterStillRetiresItsPredecessorAndConsumesRevision() async throws {
        let fixture = try PublicationAcceptancePairFixture()
        let markerSeed = try PublicationAcceptanceSeed(
            runtime: fixture.runtime, node: publicationAcceptanceNode())
        let markerSource = publicationAcceptanceNode()
        let markerEpoch = PublicationAcceptanceEpoch(fixture.runtime)
        let previousMarker = try markerEpoch.component(
            source: markerSource, slots: markerSeed.slots,
            continuing: markerSeed.component.owned, declarationOnly: true)
        let markerPreparation = try markerEpoch.begin()
        let markerPlan = try publicationAcceptancePlan(for: previousMarker.owned, in: markerPreparation)
        markerEpoch.prepareDeclaration(from: markerSource, to: fixture.target)
        markerEpoch.acceptDeclaration(from: markerSource, to: fixture.target)
        try assertPublicationAcceptance(
            markerEpoch.finish(), plan: markerPlan, on: fixture.target, accepted: true)
        let seedRemoval = try removePublicationFootprint(of: markerSeed.node, in: fixture.runtime)
        assertPublicationRetirement(
            seedRemoval, owned: markerSeed.component.owned, slots: markerSeed.slots, count: 0)
        assertPublicationOwnership(previousMarker.owned, slots: markerSeed.slots, accepted: true)

        let rejectedSource = publicationAcceptanceNode()
        let rejectedEpoch = PublicationAcceptanceEpoch(fixture.runtime, origin: .managedSubtree)
        let qualified = try fixture.qualifiedScope(in: rejectedEpoch)
        let rejected = try rejectedEpoch.component(
            source: rejectedSource, slots: fixture.second.slots,
            continuing: fixture.second.component.owned, declarationOnly: true, in: qualified)
        let rejectedPreparation = try rejectedEpoch.begin()
        let rejectedPlan = try publicationAcceptancePlan(for: rejected.owned, in: rejectedPreparation)

        let liveSource = publicationAcceptanceNode()
        let liveEpoch = PublicationAcceptanceEpoch(fixture.runtime)
        let live = try liveEpoch.component(
            source: liveSource, slots: fixture.first.slots,
            continuing: fixture.first.component.owned, declarationOnly: true)
        let livePreparation = try liveEpoch.begin()
        let livePlan = try publicationAcceptancePlan(for: live.owned, in: livePreparation)
        rejectedEpoch.prepareDeclaration(from: rejectedSource, to: fixture.target)
        liveEpoch.prepareDeclaration(from: liveSource, to: fixture.target)
        defer {
            withExtendedLifetime(
                (
                    fixture, markerSeed, markerEpoch, markerSource, markerPlan,
                    rejectedEpoch, rejectedSource, rejectedPlan, qualified, liveEpoch, liveSource, livePlan
                )
            ) {}
        }

        XCTAssertFalse(rejected.owned.hasAcceptedDeclaration)
        XCTAssertFalse(live.owned.hasAcceptedDeclaration)
        fixture.second.epoch.scope.revokeForOwnerClose()
        XCTAssertTrue(rejectedEpoch.journal.canContinueAdoption)
        rejectedEpoch.acceptDeclaration(from: rejectedSource, to: fixture.target)
        let rejectedDisposition = rejectedEpoch.finish()
        try assertPublicationAcceptance(
            rejectedDisposition, plan: rejectedPlan, on: fixture.target, accepted: false)
        assertPublicationRetirement(
            rejectedDisposition, owned: markerSeed.component.owned, slots: markerSeed.slots, count: 1)
        assertPublicationOwnership(previousMarker.owned, slots: markerSeed.slots, accepted: false)

        // Replacing the complete field consumes its revision even when every
        // incoming declaration is refused. C's earlier preparation is stale.
        liveEpoch.acceptDeclaration(from: liveSource, to: fixture.target)
        XCTAssertFalse(live.owned.hasAcceptedDeclaration)
        assertPublicationOwnership(fixture.first.component.owned, slots: fixture.first.slots, accepted: true)

        // Keep this journal unsealed: prepare the same original C plan against
        // the new revision, without manufacturing a replacement receipt.
        liveEpoch.prepareDeclaration(from: liveSource, to: fixture.target)
        liveEpoch.acceptDeclaration(from: liveSource, to: fixture.target)
        XCTAssertTrue(live.owned.hasAcceptedDeclaration)
        try assertPublicationAcceptance(
            liveEpoch.finish(), plan: livePlan, on: fixture.target, accepted: true)
    }

    func testMixedPropertyAndDeclaredPublicationKeepsOnlyAcceptedOriginalOwners() async throws {
        for declarationOnly in [false, true] {
            for closeSecondOwner in [false, true] {
                for slotCount in [0, 1] {
                    let fixture = try PublicationAcceptancePairFixture(slotCount: slotCount)
                    let source = publicationAcceptanceNode()
                    source.opacity = 0.4
                    let next = PublicationAcceptanceEpoch(fixture.runtime, origin: .managedSubtree)
                    let qualified = try fixture.qualifiedScope(in: next)
                    let first = try next.component(
                        source: source, slots: fixture.first.slots,
                        continuing: fixture.first.component.owned, declarationOnly: declarationOnly)
                    let second = try next.component(
                        source: source, slots: fixture.second.slots,
                        continuing: fixture.second.component.owned, declarationOnly: declarationOnly,
                        in: qualified)
                    let preparation = try next.begin()
                    let firstPlan = try publicationAcceptancePlan(for: first.owned, in: preparation)
                    let secondPlan = try publicationAcceptancePlan(for: second.owned, in: preparation)
                    XCTAssertEqual(preparation.ownedComponentDeclarations.count, 2)
                    assertPublicationSourceRosters(firstPlan, secondPlan, sharePayload: false)
                    defer { withExtendedLifetime((fixture, next, qualified, source, firstPlan, secondPlan)) {} }

                    if declarationOnly {
                        next.prepareDeclaration(from: source, to: fixture.target)
                    } else {
                        XCTAssertTrue(
                            next.journal.preparePropertyCopy(
                                from: source, to: fixture.target, keyPath: \ViewNode.opacity))
                    }
                    if closeSecondOwner { fixture.second.epoch.scope.revokeForOwnerClose() }
                    XCTAssertTrue(next.journal.canContinueAdoption)
                    if declarationOnly {
                        next.acceptDeclaration(from: source, to: fixture.target)
                    } else {
                        fixture.target.opacity = source.opacity
                        _ = next.journal.recordAcceptedProperty(
                            from: source, to: fixture.target, keyPath: \ViewNode.opacity)
                    }

                    XCTAssertTrue(first.owned.hasAcceptedDeclaration)
                    XCTAssertEqual(second.owned.hasAcceptedDeclaration, !closeSecondOwner)
                    let disposition = next.finish()
                    try assertPublicationAcceptance(disposition, plan: firstPlan, on: fixture.target, accepted: true)
                    try assertPublicationAcceptance(
                        disposition, plan: secondPlan, on: fixture.target, accepted: !closeSecondOwner)
                    XCTAssertEqual(disposition.acceptedOwnedComponents.count, closeSecondOwner ? 1 : 2)

                    let firstRemoval = try removePublicationFootprint(of: fixture.first.node, in: fixture.runtime)
                    assertPublicationRetirement(
                        firstRemoval, owned: fixture.first.component.owned, slots: fixture.first.slots, count: 0)
                    assertPublicationOwnership(first.owned, slots: fixture.first.slots, accepted: true)
                    XCTAssertTrue(fixture.target.parent === fixture.runtime.root)

                    // B's original footprint is removed before T. A refused B
                    // must not have acquired a ghost on the still-attached T.
                    let secondRemoval = try removePublicationFootprint(of: fixture.second.node, in: fixture.runtime)
                    assertPublicationRetirement(
                        secondRemoval, owned: fixture.second.component.owned, slots: fixture.second.slots,
                        count: closeSecondOwner ? 1 : 0)
                    assertPublicationOwnership(second.owned, slots: fixture.second.slots, accepted: !closeSecondOwner)
                    let targetRemoval = try removePublicationFootprint(of: fixture.target, in: fixture.runtime)
                    assertPublicationRetirement(
                        targetRemoval, owned: fixture.first.component.owned, slots: fixture.first.slots, count: 1)
                    assertPublicationRetirement(
                        targetRemoval, owned: fixture.second.component.owned, slots: fixture.second.slots,
                        count: closeSecondOwner ? 0 : 1)
                    assertPublicationOwnership(first.owned, slots: fixture.first.slots, accepted: false)
                    assertPublicationOwnership(second.owned, slots: fixture.second.slots, accepted: false)
                }
            }
        }
    }

    func testPreparedInsertionPreservesLiveOwnerWhenSiblingOwnerRetires() async throws {
        for retireSecondOwner in [false, true] {
            let runtime = RetainedViewRuntime(root: publicationAcceptanceNode())
            let firstSeed = try PublicationAcceptanceSeed(runtime: runtime, node: publicationAcceptanceNode())
            let secondSeed = try PublicationAcceptanceSeed(runtime: runtime, node: publicationAcceptanceNode())
            let source = publicationAcceptanceNode()
            source.onAppear = {}
            let next = PublicationAcceptanceEpoch(runtime)
            let attribution = try next.attribution()
            let first = try next.owned(
                in: attribution, slots: firstSeed.slots, continuing: firstSeed.component.owned)
            let second = try next.owned(
                in: attribution, slots: secondSeed.slots, continuing: secondSeed.component.owned)
            let output = try next.recordSource(source, in: attribution)
            let preparation = try next.begin()
            let firstPlan = try publicationAcceptancePlan(for: first, in: preparation)
            let secondPlan = try publicationAcceptancePlan(for: second, in: preparation)
            XCTAssertEqual(preparation.ownedComponentDeclarations.count, 2)
            assertPublicationSourceRosters(firstPlan, secondPlan, sharePayload: true)
            XCTAssertTrue(next.journal.prepareInsertedNode(from: source))
            let storage = source.lazyListActivityStorage()
            let targetID = storage.targetID
            let attachmentID = storage.attachmentID
            defer {
                withExtendedLifetime(
                    (firstSeed, secondSeed, next, attribution, output, source, firstPlan, secondPlan)
                ) {}
            }

            if retireSecondOwner {
                let removal = try removePublicationFootprint(of: secondSeed.node, in: runtime)
                assertPublicationRetirement(
                    removal, owned: secondSeed.component.owned, slots: secondSeed.slots, count: 1)
                assertPublicationOwnership(secondSeed.component.owned, slots: secondSeed.slots, accepted: false)
            }
            XCTAssertNil(source.retainedLazyListRuntime)
            runtime.root.addChild(source)
            XCTAssertTrue(source.parent === runtime.root)
            XCTAssertTrue(source.lazyListActivityStorage() === storage)
            XCTAssertTrue(storage.targetID === targetID)
            XCTAssertTrue(storage.attachmentID === attachmentID)

            // Insertion notification is the sole publication on S. Calling
            // completion here would repair a missing insertion footprint.
            _ = next.journal.recordAcceptedInsertedNode(on: source)
            XCTAssertTrue(first.hasAcceptedDeclaration)
            XCTAssertEqual(second.hasAcceptedDeclaration, !retireSecondOwner)
            let disposition = next.finish()
            try assertPublicationAcceptance(disposition, plan: firstPlan, on: source, accepted: true)
            try assertPublicationAcceptance(
                disposition, plan: secondPlan, on: source, accepted: !retireSecondOwner)
            XCTAssertEqual(disposition.acceptedOwnedComponents.count, retireSecondOwner ? 1 : 2)

            let firstRemoval = try removePublicationFootprint(of: firstSeed.node, in: runtime)
            assertPublicationRetirement(
                firstRemoval, owned: firstSeed.component.owned, slots: firstSeed.slots, count: 0)
            assertPublicationOwnership(first, slots: firstSeed.slots, accepted: true)
            XCTAssertTrue(source.parent === runtime.root)
            if !retireSecondOwner {
                let secondRemoval = try removePublicationFootprint(of: secondSeed.node, in: runtime)
                assertPublicationRetirement(
                    secondRemoval, owned: secondSeed.component.owned, slots: secondSeed.slots, count: 0)
                assertPublicationOwnership(second, slots: secondSeed.slots, accepted: true)
            }

            let sourceRemoval = try removePublicationFootprint(of: source, in: runtime)
            assertPublicationRetirement(
                sourceRemoval, owned: firstSeed.component.owned, slots: firstSeed.slots, count: 1)
            assertPublicationRetirement(
                sourceRemoval, owned: secondSeed.component.owned, slots: secondSeed.slots,
                count: retireSecondOwner ? 0 : 1)
            assertPublicationOwnership(first, slots: firstSeed.slots, accepted: false)
            assertPublicationOwnership(second, slots: secondSeed.slots, accepted: false)
        }
    }

    func testCompletedNodePreservesLiveOwnerWhenSiblingNativeOwnerCloses() async throws {
        for state in PublicationAcceptanceSiblingState.allCases {
            let fixture = try PublicationAcceptancePairFixture()
            let source = publicationAcceptanceNode()
            let next = PublicationAcceptanceEpoch(fixture.runtime, origin: .managedSubtree)
            let qualified = try fixture.qualifiedScope(in: next)
            let first = try next.component(
                source: source, slots: fixture.first.slots, continuing: fixture.first.component.owned)
            let second = try next.component(
                source: source, slots: fixture.second.slots,
                continuing: fixture.second.component.owned, in: qualified)
            let preparation = try next.begin()
            let firstPlan = try publicationAcceptancePlan(for: first.owned, in: preparation)
            let secondPlan = try publicationAcceptancePlan(for: second.owned, in: preparation)
            XCTAssertEqual(preparation.ownedComponentDeclarations.count, 2)
            assertPublicationSourceRosters(firstPlan, secondPlan, sharePayload: false)
            defer { withExtendedLifetime((fixture, next, qualified, source, firstPlan, secondPlan)) {} }

            switch state {
            case .allLive:
                XCTAssertTrue(qualified.canPublishDescriptors)
            case .nativeOwnerClosed:
                // Closing the original scope revokes L2 without revoking the
                // incoming journal's shared state or its live root lifetime L1.
                fixture.second.epoch.scope.revokeForOwnerClose()
                XCTAssertFalse(qualified.canPublishDescriptors)
                XCTAssertTrue(fixture.second.actual.isAttached)
            case .ownedOwnerRetired:
                let removal = try removePublicationFootprint(of: fixture.second.node, in: fixture.runtime)
                assertPublicationRetirement(
                    removal, owned: fixture.second.component.owned, slots: fixture.second.slots, count: 1)
                assertPublicationOwnership(second.owned, slots: fixture.second.slots, accepted: false)
            }
            XCTAssertTrue(next.journal.canContinueAdoption)
            XCTAssertFalse(first.owned.hasAcceptedDeclaration)
            XCTAssertFalse(second.owned.hasAcceptedDeclaration)

            // No other owned publication on T can supply the missing footprint.
            _ = next.journal.recordCompletedNode(from: source, to: fixture.target)
            let acceptsSecond = state == .allLive
            XCTAssertTrue(first.owned.hasAcceptedDeclaration)
            XCTAssertEqual(second.owned.hasAcceptedDeclaration, acceptsSecond)
            let disposition = next.finish()
            try assertPublicationAcceptance(disposition, plan: firstPlan, on: fixture.target, accepted: true)
            try assertPublicationAcceptance(
                disposition, plan: secondPlan, on: fixture.target, accepted: acceptsSecond)
            XCTAssertEqual(disposition.acceptedOwnedComponents.count, acceptsSecond ? 2 : 1)

            let firstRemoval = try removePublicationFootprint(of: fixture.first.node, in: fixture.runtime)
            assertPublicationRetirement(
                firstRemoval, owned: fixture.first.component.owned, slots: fixture.first.slots, count: 0)
            assertPublicationOwnership(first.owned, slots: fixture.first.slots, accepted: true)
            XCTAssertTrue(fixture.target.parent === fixture.runtime.root)

            if state != .ownedOwnerRetired {
                let secondRemoval = try removePublicationFootprint(of: fixture.second.node, in: fixture.runtime)
                assertPublicationRetirement(
                    secondRemoval, owned: fixture.second.component.owned, slots: fixture.second.slots,
                    count: acceptsSecond ? 0 : 1)
                assertPublicationOwnership(second.owned, slots: fixture.second.slots, accepted: acceptsSecond)
            }
            let targetRemoval = try removePublicationFootprint(of: fixture.target, in: fixture.runtime)
            assertPublicationRetirement(
                targetRemoval, owned: fixture.first.component.owned, slots: fixture.first.slots, count: 1)
            assertPublicationRetirement(
                targetRemoval, owned: fixture.second.component.owned, slots: fixture.second.slots,
                count: acceptsSecond ? 1 : 0)
            assertPublicationOwnership(first.owned, slots: fixture.first.slots, accepted: false)
            assertPublicationOwnership(second.owned, slots: fixture.second.slots, accepted: false)
        }
    }
}

private enum PublicationAcceptanceSiblingState: CaseIterable, Equatable {
    case allLive, nativeOwnerClosed, ownedOwnerRetired
}

@MainActor
private func publicationAcceptanceNode() -> ViewNode {
    let node = ViewNode()
    // Identity is itself an owned payload field. Omit it before registration so
    // unrelated identity proof invalidation cannot conceal a field-cleanup bug.
    node.retainedViewIdentity = nil
    return node
}

@MainActor
private final class PublicationAcceptanceClosingController: RetainedTextInputController {
    private(set) var detachCalls = 0
    private let closeHost: () -> Void

    init(closeHost: @escaping () -> Void) { self.closeHost = closeHost }

    func attach(to node: ViewNode) {}
    func reconcile(from previous: (any RetainedTextInputController)?, onto node: ViewNode) {}
    func revokeOwnership(from node: ViewNode) {}

    func detach(from node: ViewNode) {
        detachCalls += 1
        closeHost()
    }
}

@MainActor
private struct PublicationAcceptanceComponent {
    let owned: RetainedOwnedComponentReceipt
    let group: RetainedDescriptorGroupID
    let contribution: RetainedDescriptorContributionReceipt
}

@MainActor
private final class PublicationAcceptanceEpoch {
    let runtime: RetainedViewRuntime
    let scope: RetainedLazyListDescriptorBuildScope
    let journal: RetainedLazyListAdoptionJournal
    private var retainedScopes: [RetainedLazyListDescriptorBuildScope] = []
    private var retainedAttributions: [RetainedDescriptorComponentAttribution] = []
    private var retainedSources: [ViewNode] = []
    private var disposition: RetainedLazyListAdoptionDisposition?

    init(
        _ runtime: RetainedViewRuntime,
        origin: RetainedLazyListDescriptorBuildOrigin = .componentHostRoot,
        scope: RetainedLazyListDescriptorBuildScope? = nil
    ) {
        self.runtime = runtime
        let scope =
            scope
            ?? RetainedLazyListDescriptorBuildScope(
                origin: origin, hostLifetime: runtime.lazyListLogicalHostLifetime,
                ownerLifetime: runtime.root.lazyListActivityStorage().descriptorOwnerLifetime)
        self.scope = scope
        journal = RetainedLazyListAdoptionJournal(descriptorScope: scope, transaction: RetainedBuildTransaction())
    }

    func attribution(
        in qualifiedScope: RetainedLazyListDescriptorBuildScope? = nil
    ) throws -> RetainedDescriptorComponentAttribution {
        let currentScope = qualifiedScope ?? scope
        let attribution = try XCTUnwrap(currentScope.registerOrdinaryComponent())
        retainedScopes.append(currentScope)
        retainedAttributions.append(attribution)
        return attribution
    }

    func owned(
        in attribution: RetainedDescriptorComponentAttribution, slots: [RetainedOwnedSlotGenerationID],
        continuing: RetainedOwnedComponentReceipt? = nil, declarationOnly: Bool = false
    ) throws -> RetainedOwnedComponentReceipt {
        try XCTUnwrap(
            attribution.registerOwnedComponent(
                owner: continuing?.owner ?? RetainedOwnedComponentID(), slots: slots,
                continuing: continuing, declarationOnly: declarationOnly))
    }

    func recordSource(
        _ source: ViewNode, in attribution: RetainedDescriptorComponentAttribution,
        kind: RetainedLazyListContributionKind = .observation
    ) throws -> (group: RetainedDescriptorGroupID, contribution: RetainedDescriptorContributionReceipt) {
        let group = try XCTUnwrap(attribution.registerGroup(kind: kind))
        XCTAssertTrue(attribution.recordSourceOutput(source, group: group))
        _ = try XCTUnwrap(attribution.closeGroup(group))
        retainedSources.append(source)
        return (group, try XCTUnwrap(attribution.contribution(for: group)))
    }

    func component(
        source: ViewNode, slots: [RetainedOwnedSlotGenerationID],
        continuing: RetainedOwnedComponentReceipt? = nil, declarationOnly: Bool = false,
        in qualifiedScope: RetainedLazyListDescriptorBuildScope? = nil,
        kind: RetainedLazyListContributionKind = .observation
    ) throws -> PublicationAcceptanceComponent {
        let componentAttribution = try attribution(in: qualifiedScope)
        let receipt = try owned(
            in: componentAttribution, slots: slots, continuing: continuing, declarationOnly: declarationOnly)
        let output = try recordSource(source, in: componentAttribution, kind: kind)
        return PublicationAcceptanceComponent(
            owned: receipt, group: output.group, contribution: output.contribution)
    }

    func begin() throws -> RetainedLazyListAdoptionPreparation {
        let preparation = try XCTUnwrap(journal.preparation())
        XCTAssertTrue(journal.beginOrdinaryAdoption())
        XCTAssertTrue(journal.markMutationStarted())
        return preparation
    }

    func insert(_ node: ViewNode, attaching: Bool) {
        XCTAssertTrue(journal.prepareInsertedNode(from: node))
        if attaching { runtime.root.addChild(node) }
        XCTAssertTrue(node.parent === runtime.root)
        _ = journal.recordAcceptedInsertedNode(on: node)
    }

    func prepareDeclaration(from source: ViewNode, to target: ViewNode) {
        XCTAssertTrue(source.children.isEmpty)
        XCTAssertTrue(target.children.isEmpty)
        XCTAssertTrue(journal.prepareOwnedStructuralDeclaration(from: source, to: target))
    }

    func acceptDeclaration(from source: ViewNode, to target: ViewNode) {
        journal.recordAcceptedOwnedStructuralDeclaration(from: source, to: target)
    }

    @discardableResult
    func finish() -> RetainedLazyListAdoptionDisposition {
        if let disposition { return disposition }
        let result = journal.seal(completedCheckedAdoption: true)
        journal.releaseUnadoptedTransport()
        scope.finish()
        disposition = result
        return result
    }
}

@MainActor
private final class PublicationAcceptanceSeed {
    let node: ViewNode
    let slots: [RetainedOwnedSlotGenerationID]
    let epoch: PublicationAcceptanceEpoch
    let component: PublicationAcceptanceComponent
    let disposition: RetainedLazyListAdoptionDisposition
    let actual: RetainedLazyListActualAttachment

    init(
        runtime: RetainedViewRuntime, node: ViewNode, slotCount: Int = 1,
        scope: RetainedLazyListDescriptorBuildScope? = nil,
        kind: RetainedLazyListContributionKind = .observation
    ) throws {
        let slots = (0..<slotCount).map { _ in RetainedOwnedSlotGenerationID() }
        let epoch = PublicationAcceptanceEpoch(runtime, scope: scope)
        let component = try epoch.component(source: node, slots: slots, kind: kind)
        _ = try epoch.begin()
        epoch.insert(node, attaching: node.parent == nil)
        _ = epoch.journal.recordCompletedNode(from: node, to: node)
        let disposition = epoch.finish()
        let accepted = try XCTUnwrap(
            disposition.acceptedOrdinaryGroups.first { $0.proposal.group === component.group })
        let actual = try XCTUnwrap(accepted.acceptedFacets.first?.actual)
        XCTAssertTrue(component.owned.hasAcceptedDeclaration)
        XCTAssertTrue(component.contribution === accepted.receipt)
        XCTAssertTrue(component.contribution.isActive)
        XCTAssertTrue(actual.isAttached)
        assertPublicationOwnership(component.owned, slots: slots, accepted: true)
        self.node = node
        self.slots = slots
        self.epoch = epoch
        self.component = component
        self.disposition = disposition
        self.actual = actual
    }
}

@MainActor
private final class PublicationAcceptancePairFixture {
    let runtime: RetainedViewRuntime
    let first: PublicationAcceptanceSeed
    let second: PublicationAcceptanceSeed
    let target: ViewNode

    init(slotCount: Int = 1) throws {
        let runtime = RetainedViewRuntime(root: publicationAcceptanceNode())
        let first = try PublicationAcceptanceSeed(
            runtime: runtime, node: publicationAcceptanceNode(), slotCount: slotCount)
        let secondNode = publicationAcceptanceNode()
        // Attach V before capturing L2. Its first attachment can establish a new
        // native descriptor lifetime; the accepted original must use that one.
        runtime.root.addChild(secondNode)
        let rootLifetime = runtime.root.lazyListActivityStorage().descriptorOwnerLifetime
        let secondLifetime = secondNode.lazyListActivityStorage().descriptorOwnerLifetime
        XCTAssertFalse(rootLifetime === secondLifetime)
        let secondScope = RetainedLazyListDescriptorBuildScope(
            origin: .componentHostRoot, hostLifetime: runtime.lazyListLogicalHostLifetime,
            ownerLifetime: secondLifetime)
        let second = try PublicationAcceptanceSeed(
            runtime: runtime, node: secondNode, slotCount: slotCount, scope: secondScope,
            kind: .deferredSubtree)
        let target = publicationAcceptanceNode()
        runtime.root.addChild(target)
        self.runtime = runtime
        self.first = first
        self.second = second
        self.target = target
    }

    func qualifiedScope(in epoch: PublicationAcceptanceEpoch) throws -> RetainedLazyListDescriptorBuildScope {
        XCTAssertTrue(second.component.contribution.isActive)
        XCTAssertTrue(second.actual.isAttached)
        return try XCTUnwrap(
            epoch.scope.withAdmittedOrdinaryDeferredSubtree(
                originalActivity: second.component.contribution, originalAttachment: second.actual))
    }
}

@MainActor
private func publicationAcceptancePlan(
    for receipt: RetainedOwnedComponentReceipt, in preparation: RetainedLazyListAdoptionPreparation
) throws -> RetainedOwnedComponentDeclarationPlan {
    try XCTUnwrap(preparation.ownedComponentDeclarations.first { $0.receipt === receipt })
}

@MainActor
private func assertPublicationSourceRosters(
    _ first: RetainedOwnedComponentDeclarationPlan, _ second: RetainedOwnedComponentDeclarationPlan,
    sharePayload: Bool, file: StaticString = #filePath, line: UInt = #line
) {
    XCTAssertEqual(first.sourcePayloads.count, 1, file: file, line: line)
    XCTAssertEqual(second.sourcePayloads.count, 1, file: file, line: line)
    let firstPayloads = first.sourcePayloads.map { ObjectIdentifier($0) }
    let secondPayloads = second.sourcePayloads.map { ObjectIdentifier($0) }
    // Two groups may record the same source node with distinct payload IDs.
    // Only the single-output insertion fixture shares one original payload.
    XCTAssertEqual(
        firstPayloads == secondPayloads, sharePayload, file: file, line: line)
    XCTAssertFalse(first.receipt.owner === second.receipt.owner, file: file, line: line)
}

@MainActor
private func assertPublicationAcceptance(
    _ disposition: RetainedLazyListAdoptionDisposition, plan: RetainedOwnedComponentDeclarationPlan,
    on target: ViewNode, accepted: Bool, file: StaticString = #filePath, line: UInt = #line
) throws {
    let facts = disposition.acceptedOwnedComponents.filter { $0.plan === plan }
    XCTAssertEqual(facts.count, accepted ? 1 : 0, file: file, line: line)
    XCTAssertEqual(plan.receipt.hasAcceptedDeclaration, accepted, file: file, line: line)
    if accepted {
        let fact = try XCTUnwrap(facts.first, file: file, line: line)
        let storage = target.lazyListActivityStorage()
        XCTAssertTrue(fact.plan.receipt === plan.receipt, file: file, line: line)
        XCTAssertEqual(
            fact.slots.map { ObjectIdentifier($0) },
            plan.receipt.slots.map { ObjectIdentifier($0) }, file: file, line: line)
        XCTAssertTrue(fact.actual.target === storage.targetID, file: file, line: line)
        XCTAssertTrue(fact.actual.attachment === storage.attachmentID, file: file, line: line)
        XCTAssertTrue(fact.actual.isAttached, file: file, line: line)
        let sourcePayload = try XCTUnwrap(fact.sourcePayload, file: file, line: line)
        XCTAssertTrue(plan.sourcePayloads.contains { $0 === sourcePayload }, file: file, line: line)
    }
}

@MainActor
private func assertPublicationOwnership(
    _ owned: RetainedOwnedComponentReceipt, slots: [RetainedOwnedSlotGenerationID], accepted: Bool,
    file: StaticString = #filePath, line: UInt = #line
) {
    XCTAssertEqual(owned.hasDeclaredComponent, accepted, file: file, line: line)
    XCTAssertEqual(
        owned.slots.map { ObjectIdentifier($0) }, slots.map { ObjectIdentifier($0) }, file: file, line: line)
    for slot in slots {
        XCTAssertEqual(owned.hasAcceptedOwnership(for: slot), accepted, file: file, line: line)
        XCTAssertEqual(owned.permitsOwnedWrite(for: slot), accepted, file: file, line: line)
    }
}

@MainActor
private func assertPublicationRetirement(
    _ disposition: RetainedLazyListAdoptionDisposition, owned: RetainedOwnedComponentReceipt,
    slots: [RetainedOwnedSlotGenerationID], count: Int,
    file: StaticString = #filePath, line: UInt = #line
) {
    XCTAssertEqual(
        disposition.retiredOwnedComponents.filter { $0 === owned.owner }.count, count, file: file, line: line)
    for slot in slots {
        XCTAssertEqual(
            disposition.retiredOwnedSlots.filter { $0 === slot }.count, count, file: file, line: line)
    }
}

@MainActor
private func removePublicationFootprint(
    of node: ViewNode, in runtime: RetainedViewRuntime
) throws -> RetainedLazyListAdoptionDisposition {
    let removal = PublicationAcceptanceEpoch(runtime)
    _ = try removal.begin()
    _ = removal.journal.recordPhysicalDeparture(of: node, cause: .acceptedReplacement)
    return removal.finish()
}
