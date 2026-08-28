import SwiftWindowsCore
import SwiftWindowsUI
@preconcurrency import XCTest

@testable import WinSwiftUI

@MainActor
final class PresentationActivityTests: XCTestCase {
    func testAcceptedInactivityPreservesStateButNeverRevivesAnOldDismissal() async throws {
        let harness = PresentationActivityTestHarness()
        let events = PresentationActivityTestEvents()
        defer { harness.close() }
        let initial = try harness.rootBuild()
        let owner = try XCTUnwrap(initial.epoch.owner(at: identity("sheet")))
        let state = owner.resolve(at: PresentationActivityTestSlots.value) { 7 }
        let original = stage(owner, in: initial, configuration: configuration("original", events: events))
        try harness.adopt(initial)
        XCTAssertTrue(state.write(8))

        let inactive = try harness.rootBuild()
        inactive.epoch.preserveDeclaredSubtree(at: owner.identity)
        try harness.adopt(inactive)
        XCTAssertTrue(owner.isLive)
        XCTAssertTrue(harness.registry.owner(at: owner.identity) === owner)
        XCTAssertTrue(state.isWritable)
        original.dismiss()
        original.dismissInteractively()
        XCTAssertEqual(events.values, [])

        let reopened = try harness.rootBuild()
        let sameOwner = try XCTUnwrap(reopened.epoch.owner(at: owner.identity))
        let sameState = sameOwner.resolve(at: PresentationActivityTestSlots.value) { 99 }
        let current = stage(sameOwner, in: reopened, configuration: configuration("reopened", events: events))
        try harness.adopt(reopened)
        XCTAssertTrue(sameOwner === owner)
        XCTAssertEqual(sameOwner.generation, owner.generation)
        XCTAssertTrue(sameState === state)
        XCTAssertEqual(sameState.readValue(), 8)
        original.dismiss()
        original.dismissInteractively()
        XCTAssertEqual(events.values, [], "Preserved State cannot lend authority to the retired activity session")
        current.dismiss()
        XCTAssertEqual(events.values, dismissalEvents("reopened"))
    }

    func testContinuouslyActiveCopiesUseTheNewestAcceptedConfigurationAndFocusRoute() async throws {
        let harness = PresentationActivityTestHarness()
        let events = PresentationActivityTestEvents()
        defer { harness.close() }
        let initial = try harness.rootBuild()
        let owner = try XCTUnwrap(initial.epoch.owner(at: identity("continuous")))
        let original = stage(
            owner, in: initial, configuration: configuration("old", events: events),
            preparingFocus: focus("old", events: events))
        try harness.adopt(initial)

        let replacement = try harness.rootBuild()
        let sameOwner = try XCTUnwrap(replacement.epoch.owner(at: owner.identity))
        let current = stage(
            sameOwner, in: replacement, configuration: configuration("new", events: events),
            preparingFocus: focus("new", events: events))
        current.dismiss()
        current.dismissInteractively()
        XCTAssertEqual(events.values, [])
        original.dismiss()
        XCTAssertEqual(events.values, dismissalEvents("old"))
        events.values.removeAll()
        try harness.adopt(replacement)

        original.dismissInteractively()
        XCTAssertEqual(events.values, ["new.validate", "new.focus"] + dismissalEvents("new"))
        events.values.removeAll()
        current.dismiss()
        XCTAssertEqual(
            events.values, dismissalEvents("new"), "Environment dismissal does not prepare interactive focus")
    }

    func testAProvisionalSameOwnerReceiptRemainsInertAfterAbandonmentAndLaterAcceptance() async throws {
        let harness = PresentationActivityTestHarness()
        let events = PresentationActivityTestEvents()
        defer { harness.close() }
        let initial = try harness.rootBuild()
        let owner = try XCTUnwrap(initial.epoch.owner(at: identity("receipt")))
        let original = stage(owner, in: initial, configuration: configuration("old", events: events))
        try harness.adopt(initial)

        let rejected = try harness.rootBuild()
        let candidateOwner = try XCTUnwrap(rejected.epoch.owner(at: owner.identity))
        let provisional = stage(candidateOwner, in: rejected, configuration: configuration("rejected", events: events))
        provisional.dismiss()
        provisional.dismissInteractively()
        XCTAssertEqual(events.values, [])
        harness.abandon(rejected)
        provisional.dismiss()
        original.dismiss()
        XCTAssertEqual(events.values, dismissalEvents("old"))
        events.values.removeAll()

        let accepted = try harness.rootBuild()
        let acceptedOwner = try XCTUnwrap(accepted.epoch.owner(at: owner.identity))
        let current = stage(acceptedOwner, in: accepted, configuration: configuration("accepted", events: events))
        try harness.adopt(accepted)
        provisional.dismiss()
        provisional.dismissInteractively()
        XCTAssertEqual(events.values, [], "Sharing a live session never accepts a discarded declaration receipt")
        original.dismiss()
        current.dismiss()
        XCTAssertEqual(events.values, dismissalEvents("accepted") + dismissalEvents("accepted"))
    }

    func testPrepareSuspendsAllCoveredActivityAndAbandonRestoresItBeforeStateCleanup() async throws {
        let harness = PresentationActivityTestHarness()
        let events = PresentationActivityTestEvents()
        let payload = PresentationActivityWeakProbe()
        defer { harness.close() }
        let initial = try harness.rootBuild()
        let survivor = try XCTUnwrap(initial.epoch.owner(at: identity("survivor")))
        let departure = try XCTUnwrap(initial.epoch.owner(at: identity("departure")))
        let reader = try XCTUnwrap(initial.epoch.owner(at: identity("reader")))
        let original = stage(survivor, in: initial, configuration: configuration("survivor", events: events))
        let departing = stage(departure, in: initial, configuration: configuration("departure", events: events))
        let anchor = initial.activity.stageAnchor(
            owner: reader, contentPrefix: reader.identity.appending(.role(.geometryContent)))
        initial.activity.materialize(anchor)
        try harness.adopt(initial)

        let candidate = try harness.rootBuild()
        let sameSurvivor = try XCTUnwrap(candidate.epoch.owner(at: survivor.identity))
        _ = try XCTUnwrap(candidate.epoch.owner(at: reader.identity))
        let provisional = stage(sameSurvivor, in: candidate, configuration: configuration("candidate", events: events))
        let provisionalOwner = try XCTUnwrap(candidate.epoch.owner(at: identity("provisional payload")))
        _ = provisionalOwner.resolve(at: PresentationActivityTestSlots.payload) {
            let probe = PresentationActivityReleaseProbe {
                events.values.append("state.release")
                XCTAssertTrue(survivor.isLive)
                XCTAssertTrue(departure.isLive)
                XCTAssertTrue(anchor.isActive)
                original.dismiss()
                departing.dismiss()
                provisional.dismiss()
            }
            payload.value = probe
            return probe
        }
        try harness.prepare(candidate)
        XCTAssertTrue(survivor.isLive, "The compatible State owner remains live during preparation")
        XCTAssertFalse(departure.isLive)
        XCTAssertFalse(anchor.isActive)
        original.dismiss()
        departing.dismissInteractively()
        provisional.dismiss()
        XCTAssertEqual(events.values, [], "Activity must suspend compatible survivors as well as departures")

        candidate.activity.abandon()
        XCTAssertTrue(anchor.isActive)
        candidate.epoch.abort()
        candidate.activity.finish()
        harness.registry.finishPendingRetirements()
        withExtendedLifetime((candidate, provisionalOwner, survivor, departure)) {
            XCTAssertNil(payload.value)
        }
        XCTAssertEqual(events.values, ["state.release"] + dismissalEvents("survivor") + dismissalEvents("departure"))
        XCTAssertTrue(survivor.isLive)
        XCTAssertTrue(departure.isLive)
        provisional.dismiss()
        XCTAssertFalse(candidate.epoch.didCommit)
    }

    func testPublicationInstallsEveryNewConfigurationBeforeDisplacedPayloadRelease() async throws {
        let harness = PresentationActivityTestHarness()
        let events = PresentationActivityTestEvents()
        let firstPayload = PresentationActivityWeakProbe()
        let secondPayload = PresentationActivityWeakProbe()
        var first: PresentationDismissHandle?
        var second: PresentationDismissHandle?
        defer { harness.close() }
        let initial = try harness.rootBuild()
        let firstOwner = try XCTUnwrap(initial.epoch.owner(at: identity("first")))
        let secondOwner = try XCTUnwrap(initial.epoch.owner(at: identity("second")))
        first = stage(
            firstOwner, in: initial,
            configuration: releasingConfiguration("old first", events: events, weakProbe: firstPayload) {
                events.values.append("release.first")
                first?.dismiss()
                second?.dismiss()
            })
        second = stage(
            secondOwner, in: initial,
            configuration: releasingConfiguration("old second", events: events, weakProbe: secondPayload) {
                events.values.append("release.second")
                first?.dismiss()
                second?.dismiss()
            })
        try harness.adopt(initial)

        let replacement = try harness.rootBuild()
        let nextFirst = try XCTUnwrap(replacement.epoch.owner(at: firstOwner.identity))
        let nextSecond = try XCTUnwrap(replacement.epoch.owner(at: secondOwner.identity))
        _ = stage(nextFirst, in: replacement, configuration: configuration("new first", events: events))
        _ = stage(nextSecond, in: replacement, configuration: configuration("new second", events: events))
        try harness.adopt(replacement, finish: false)
        XCTAssertNotNil(firstPayload.value)
        XCTAssertNotNil(secondPayload.value)
        XCTAssertEqual(events.values, [], "Displaced captures must survive until publication is complete")
        harness.finish(replacement)

        withExtendedLifetime((initial, replacement, firstOwner, secondOwner, first, second)) {
            XCTAssertNil(firstPayload.value)
            XCTAssertNil(secondPayload.value)
        }
        XCTAssertEqual(events.values.filter { $0.hasPrefix("release.") }.sorted(), ["release.first", "release.second"])
        let newEvents = dismissalEvents("new first") + dismissalEvents("new second")
        XCTAssertEqual(events.values.filter { !$0.hasPrefix("release.") }, newEvents + newEvents)
    }

    func testCloseRevokesAllActivityBeforePayloadCleanupAndPreparedAbandonCannotReopenIt() async throws {
        let harness = PresentationActivityTestHarness()
        let events = PresentationActivityTestEvents()
        let statePayload = PresentationActivityWeakProbe()
        let firstPayload = PresentationActivityWeakProbe()
        let secondPayload = PresentationActivityWeakProbe()
        let candidatePayload = PresentationActivityWeakProbe()
        var first: PresentationDismissHandle?
        var second: PresentationDismissHandle?
        var provisional: PresentationDismissHandle?
        var anchor: PresentationActivityAnchor?
        let verifyClosed: @MainActor () -> Void = { [weak harness] in
            XCTAssertTrue(harness?.ledger.isClosed == true)
            XCTAssertTrue(harness?.registry.isClosed == true)
            XCTAssertFalse(anchor?.isActive == true)
            first?.dismiss()
            second?.dismissInteractively()
            provisional?.dismiss()
        }
        defer { harness.close() }
        let initial = try harness.rootBuild()
        let firstOwner = try XCTUnwrap(initial.epoch.owner(at: identity("close first")))
        let secondOwner = try XCTUnwrap(initial.epoch.owner(at: identity("close second")))
        let reader = try XCTUnwrap(initial.epoch.owner(at: identity("close reader")))
        _ = firstOwner.resolve(at: PresentationActivityTestSlots.payload) {
            let probe = PresentationActivityReleaseProbe {
                events.values.append("release.state")
                verifyClosed()
            }
            statePayload.value = probe
            return probe
        }
        first = stage(
            firstOwner, in: initial,
            configuration: releasingConfiguration("first", events: events, weakProbe: firstPayload) {
                events.values.append("release.first")
                verifyClosed()
            })
        second = stage(
            secondOwner, in: initial,
            configuration: releasingConfiguration("second", events: events, weakProbe: secondPayload) {
                events.values.append("release.second")
                verifyClosed()
            })
        anchor = initial.activity.stageAnchor(
            owner: reader, contentPrefix: reader.identity.appending(.role(.geometryContent)))
        initial.activity.materialize(try XCTUnwrap(anchor))
        try harness.adopt(initial)

        let candidate = try harness.rootBuild()
        let sameFirst = try XCTUnwrap(candidate.epoch.owner(at: firstOwner.identity))
        provisional = stage(
            sameFirst, in: candidate,
            configuration: releasingConfiguration("candidate", events: events, weakProbe: candidatePayload) {
                events.values.append("release.candidate")
                verifyClosed()
            })
        try harness.prepare(candidate)
        harness.ledger.closeAdmissions()
        first?.dismiss()
        second?.dismissInteractively()
        provisional?.dismiss()
        XCTAssertEqual(events.values, [])
        harness.registry.close()
        XCTAssertFalse(firstOwner.isLive)
        XCTAssertFalse(secondOwner.isLive)
        harness.ledger.releaseClosedPayloads()
        candidate.activity.abandon()
        candidate.epoch.abort()
        harness.finish(candidate)

        verifyClosed()
        XCTAssertNil(harness.ledger.beginBuild())
        XCTAssertNil(harness.registry.beginRootBuild())
        XCTAssertFalse(candidate.epoch.didCommit)
        withExtendedLifetime((initial, candidate, firstOwner, secondOwner, reader, first, second, provisional, anchor))
        {
            XCTAssertNil(statePayload.value)
            XCTAssertNil(firstPayload.value)
            XCTAssertNil(secondPayload.value)
            XCTAssertNil(candidatePayload.value)
        }
        XCTAssertEqual(
            events.values.sorted(), ["release.candidate", "release.first", "release.second", "release.state"])
    }

    func testCloseReentryFromProvisionalAndDiscardedPayloadsUsesDetachedCollections() async throws {
        let harness = PresentationActivityTestHarness()
        let events = PresentationActivityTestEvents()
        let discardedPayload = PresentationActivityWeakProbe()
        let currentPayload = PresentationActivityWeakProbe()
        var isReenteringClose = false
        let closeAgain: @MainActor () -> Void = { [weak harness] in
            XCTAssertTrue(harness?.ledger.isClosed == true)
            XCTAssertTrue(harness?.registry.isClosed == true)
            guard !isReenteringClose else { return }
            isReenteringClose = true
            defer { isReenteringClose = false }
            harness?.close()
        }
        defer { harness.close() }
        let build = try harness.rootBuild()
        let owner = try XCTUnwrap(build.epoch.owner(at: identity("reentrant provisional close")))
        let discarded = stage(
            owner, in: build,
            configuration: releasingConfiguration("discarded", events: events, weakProbe: discardedPayload) {
                events.values.append("release.discarded")
                closeAgain()
            })
        let current = stage(
            owner, in: build,
            configuration: releasingConfiguration("current", events: events, weakProbe: currentPayload) {
                events.values.append("release.current")
                closeAgain()
            })

        harness.close()
        discarded.dismiss()
        current.dismissInteractively()
        build.activity.abandon()
        build.epoch.abort()
        harness.finish(build)

        withExtendedLifetime((build, owner, discarded, current)) {
            XCTAssertNil(discardedPayload.value)
            XCTAssertNil(currentPayload.value)
        }
        XCTAssertEqual(events.values.sorted(), ["release.current", "release.discarded"])
    }

    func testCloseReentryFromDisplacedPayloadsAfterAdoptionUsesDetachedCollections() async throws {
        let harness = PresentationActivityTestHarness()
        let events = PresentationActivityTestEvents()
        let oldPayload = PresentationActivityWeakProbe()
        let newPayload = PresentationActivityWeakProbe()
        var isReenteringClose = false
        let closeAgain: @MainActor () -> Void = { [weak harness] in
            XCTAssertTrue(harness?.ledger.isClosed == true)
            XCTAssertTrue(harness?.registry.isClosed == true)
            guard !isReenteringClose else { return }
            isReenteringClose = true
            defer { isReenteringClose = false }
            harness?.close()
        }
        defer { harness.close() }
        let initial = try harness.rootBuild()
        let owner = try XCTUnwrap(initial.epoch.owner(at: identity("reentrant displaced close")))
        let original = stage(
            owner, in: initial,
            configuration: releasingConfiguration("old", events: events, weakProbe: oldPayload) {
                events.values.append("release.old")
                closeAgain()
            })
        try harness.adopt(initial)
        let replacement = try harness.rootBuild()
        let sameOwner = try XCTUnwrap(replacement.epoch.owner(at: owner.identity))
        let current = stage(
            sameOwner, in: replacement,
            configuration: releasingConfiguration("new", events: events, weakProbe: newPayload) {
                events.values.append("release.new")
                closeAgain()
            })
        try harness.adopt(replacement, finish: false)
        XCTAssertEqual(events.values, [])
        XCTAssertNotNil(oldPayload.value)
        XCTAssertNotNil(newPayload.value)

        harness.close()
        original.dismiss()
        current.dismissInteractively()
        harness.finish(replacement)

        withExtendedLifetime((initial, replacement, owner, original, current)) {
            XCTAssertNil(oldPayload.value)
            XCTAssertNil(newPayload.value)
        }
        XCTAssertEqual(events.values.sorted(), ["release.new", "release.old"])
    }

    func testDeferredAdoptionReplacesOnlyItsPrefixAndPublishesItsOuterBoundary() async throws {
        let harness = PresentationActivityTestHarness()
        let events = PresentationActivityTestEvents()
        defer { harness.close() }
        let initial = try harness.rootBuild()
        let reader = try XCTUnwrap(initial.epoch.owner(at: identity("outer reader")))
        let prefix = reader.identity.appending(.role(.geometryContent))
        let insideOwner = try XCTUnwrap(initial.epoch.owner(at: prefix.appending(.slot(0))))
        let nestedReader = try XCTUnwrap(initial.epoch.owner(at: prefix.appending(.slot(1))))
        let outsideOwner = try XCTUnwrap(initial.epoch.owner(at: identity("outside sheet")))
        let outsideReader = try XCTUnwrap(initial.epoch.owner(at: identity("outside reader")))
        let inside = stage(insideOwner, in: initial, configuration: configuration("old inside", events: events))
        let outside = stage(outsideOwner, in: initial, configuration: configuration("outside", events: events))
        let boundary = initial.activity.stageAnchor(owner: reader, contentPrefix: prefix)
        let nested = initial.activity.stageAnchor(
            owner: nestedReader, contentPrefix: nestedReader.identity.appending(.role(.geometryContent)))
        let outsideAnchor = initial.activity.stageAnchor(
            owner: outsideReader, contentPrefix: outsideReader.identity.appending(.role(.geometryContent)))
        for anchor in [boundary, nested, outsideAnchor] { initial.activity.materialize(anchor) }
        try harness.adopt(initial)

        let subtree = try harness.subtreeBuild(boundary: boundary)
        XCTAssertNil(
            subtree.epoch.owner(at: reader.identity), "The boundary State owner lies above the replaced prefix")
        let replacementOwner = try XCTUnwrap(subtree.epoch.owner(at: prefix.appending(.slot(2))))
        let replacement = stage(
            replacementOwner, in: subtree, configuration: configuration("new inside", events: events))
        subtree.epoch.preserveDeclaredSubtree(at: nestedReader.identity)
        let nextBoundary = subtree.activity.stageAnchor(owner: reader, contentPrefix: prefix)
        subtree.activity.materialize(nextBoundary)
        try harness.prepare(subtree)
        XCTAssertFalse(boundary.isActive)
        XCTAssertFalse(nested.isActive)
        XCTAssertTrue(outsideAnchor.isActive)
        inside.dismiss()
        outside.dismiss()
        XCTAssertEqual(events.values, dismissalEvents("outside"))
        events.values.removeAll()
        try harness.commitPrepared(subtree)

        XCTAssertTrue(reader.isLive)
        XCTAssertTrue(nestedReader.isLive, "Inactive nested State is distinct from its retired reader authority")
        XCTAssertFalse(boundary.isActive)
        XCTAssertTrue(nextBoundary.isActive)
        XCTAssertFalse(nested.isActive)
        XCTAssertTrue(outsideAnchor.isActive)
        XCTAssertTrue(harness.registry.owner(at: outsideOwner.identity) === outsideOwner)
        inside.dismiss()
        replacement.dismiss()
        outside.dismiss()
        XCTAssertEqual(events.values, dismissalEvents("new inside") + dismissalEvents("outside"))
        XCTAssertNil(harness.ledger.beginBuild(prefix: prefix, boundary: boundary))
        let next = try harness.subtreeBuild(boundary: nextBoundary)
        harness.abandon(next)
    }

    func testDeferredAttemptsWithoutAcceptanceKeepTheOldLeaseAndConfiguration() async throws {
        let harness = PresentationActivityTestHarness()
        let events = PresentationActivityTestEvents()
        defer { harness.close() }
        let initial = try harness.rootBuild()
        let reader = try XCTUnwrap(initial.epoch.owner(at: identity("deferred reader")))
        let prefix = reader.identity.appending(.role(.geometryContent))
        let owner = try XCTUnwrap(initial.epoch.owner(at: prefix.appending(.role(.presentation))))
        let original = stage(owner, in: initial, configuration: configuration("accepted", events: events))
        let boundary = initial.activity.stageAnchor(owner: reader, contentPrefix: prefix)
        initial.activity.materialize(boundary)
        try harness.adopt(initial)

        let busy = try harness.rootBuild()
        let sameReader = try XCTUnwrap(busy.epoch.owner(at: reader.identity))
        let provisionalBoundary = busy.activity.stageAnchor(owner: sameReader, contentPrefix: prefix)
        busy.activity.materialize(provisionalBoundary)
        XCTAssertFalse(provisionalBoundary.isActive)
        XCTAssertTrue(boundary.isActive)
        XCTAssertNil(harness.ledger.beginBuild(prefix: prefix, boundary: boundary))
        XCTAssertNil(harness.registry.beginSubtreeBuild(owner: reader, contentPrefix: prefix))
        original.dismiss()
        XCTAssertEqual(events.values, dismissalEvents("accepted"))
        harness.abandon(busy)
        XCTAssertFalse(provisionalBoundary.isActive)

        for superseded in [false, true] {
            events.values.removeAll()
            let candidate = try harness.subtreeBuild(boundary: boundary)
            let sameOwner = try XCTUnwrap(candidate.epoch.owner(at: owner.identity))
            let provisional = stage(sameOwner, in: candidate, configuration: configuration("rejected", events: events))
            let nextBoundary = candidate.activity.stageAnchor(owner: reader, contentPrefix: prefix)
            candidate.activity.materialize(nextBoundary)
            if superseded {
                candidate.epoch.supersede()
                XCTAssertFalse(candidate.activity.prepare(isCurrent: { candidate.epoch.canAdopt }))
            }
            original.dismiss()
            provisional.dismiss()
            XCTAssertTrue(boundary.isActive)
            XCTAssertFalse(nextBoundary.isActive)
            harness.abandon(candidate)
            provisional.dismiss()
            original.dismiss()
            XCTAssertEqual(events.values, dismissalEvents("accepted") + dismissalEvents("accepted"))
            XCTAssertTrue(boundary.isActive)
            XCTAssertFalse(nextBoundary.isActive)
        }
    }

    func testUnmaterializedAndDiscardedClaimsNeverPublishOrDismissDuringStateCleanup() async throws {
        let harness = PresentationActivityTestHarness()
        let events = PresentationActivityTestEvents()
        let statePayload = PresentationActivityWeakProbe()
        let configPayload = PresentationActivityWeakProbe()
        var discarded: PresentationDismissHandle?
        defer { harness.close() }
        let candidate = try harness.rootBuild()
        let unmaterializedOwner = try XCTUnwrap(candidate.epoch.owner(at: identity("unmaterialized")))
        let unmaterialized = candidate.activity.stagePresentation(
            owner: unmaterializedOwner, configuration: configuration("unmaterialized", events: events))
        let unmaterializedAnchor = candidate.activity.stageAnchor(
            owner: unmaterializedOwner,
            contentPrefix: unmaterializedOwner.identity.appending(.role(.geometryContent)))
        let discardedOwner = try XCTUnwrap(candidate.epoch.owner(at: identity("discarded")))
        discarded = stage(
            discardedOwner, in: candidate,
            configuration: releasingConfiguration("discarded", events: events, weakProbe: configPayload) {
                events.values.append("config.release")
                discarded?.dismiss()
                unmaterialized.dismiss()
            })
        let discardedAnchor = candidate.activity.stageAnchor(
            owner: discardedOwner, contentPrefix: discardedOwner.identity.appending(.role(.geometryContent)))
        candidate.activity.materialize(discardedAnchor)
        _ = discardedOwner.resolve(at: PresentationActivityTestSlots.payload) {
            let probe = PresentationActivityReleaseProbe {
                events.values.append("state.release")
                discarded?.dismiss()
                discarded?.dismissInteractively()
                unmaterialized.dismiss()
                XCTAssertFalse(discardedAnchor.isActive)
            }
            statePayload.value = probe
            return probe
        }
        candidate.activity.discardSubtree(at: discardedOwner.identity) { candidate.epoch.canAdopt }
        candidate.epoch.discardUnadoptedSubtree(at: discardedOwner.identity, preserveCommitted: false)
        withExtendedLifetime((candidate, discardedOwner, discarded, discardedAnchor)) {
            XCTAssertNil(statePayload.value)
            XCTAssertNotNil(configPayload.value, "Discarded configuration cleanup waits for the build to finish")
        }
        XCTAssertEqual(events.values, ["state.release"])
        try harness.adopt(candidate)
        XCTAssertTrue(unmaterializedOwner.isLive)
        XCTAssertFalse(unmaterializedAnchor.isActive)
        XCTAssertFalse(discardedAnchor.isActive)
        XCTAssertNil(harness.registry.owner(at: discardedOwner.identity))
        XCTAssertNil(configPayload.value)
        unmaterialized.dismiss()
        discarded?.dismiss()
        XCTAssertEqual(events.values, ["state.release", "config.release"])

        let accepted = try harness.rootBuild()
        let sameOwner = try XCTUnwrap(accepted.epoch.owner(at: unmaterializedOwner.identity))
        let current = stage(sameOwner, in: accepted, configuration: configuration("materialized", events: events))
        try harness.adopt(accepted)
        events.values.removeAll()
        unmaterialized.dismiss()
        discarded?.dismiss()
        XCTAssertEqual(events.values, [])
        current.dismiss()
        XCTAssertEqual(events.values, dismissalEvents("materialized"))
    }

    func testInteractiveFocusRevalidatesAndRestoresTheStillAdmittedModalScopeOnFailure() async throws {
        let harness = PresentationActivityTestHarness()
        let events = PresentationActivityTestEvents()
        var isPresented = true
        defer { harness.close() }
        let initial = try harness.rootBuild()
        let owner = try XCTUnwrap(initial.epoch.owner(at: identity("focus rollback")))
        let handle = stage(
            owner, in: initial,
            configuration: configuration(
                "sheet", events: events,
                validate: { admission in
                    isPresented && admission()
                }),
            preparingFocus: { admission in
                XCTAssertTrue(admission())
                events.values.append("focus.prepare")
                isPresented = false
                return { events.values.append("focus.restore") }
            })
        try harness.adopt(initial)
        handle.dismissInteractively()
        XCTAssertEqual(events.values, ["sheet.validate", "focus.prepare", "sheet.validate", "focus.restore"])

        events.values.removeAll()
        isPresented = true
        handle.dismiss()
        XCTAssertEqual(events.values, dismissalEvents("sheet"))
    }

    func testAcceptedCopiesShareOneRecursionGuardAcrossValidationFocusWriteAndCallbacks() async throws {
        let harness = PresentationActivityTestHarness()
        let events = PresentationActivityTestEvents()
        var original: PresentationDismissHandle?
        var current: PresentationDismissHandle?
        var isAttemptingNestedDismiss = false
        let recurse: @MainActor () -> Void = {
            guard !isAttemptingNestedDismiss else { return }
            isAttemptingNestedDismiss = true
            defer { isAttemptingNestedDismiss = false }
            original?.dismiss()
            original?.dismissInteractively()
            current?.dismiss()
            current?.dismissInteractively()
        }
        defer { harness.close() }
        let initial = try harness.rootBuild()
        let owner = try XCTUnwrap(initial.epoch.owner(at: identity("recursion")))
        original = stage(owner, in: initial, configuration: configuration("old", events: events))
        try harness.adopt(initial)
        let replacement = try harness.rootBuild()
        let sameOwner = try XCTUnwrap(replacement.epoch.owner(at: owner.identity))
        current = stage(
            sameOwner, in: replacement,
            configuration: configuration(
                "current", events: events,
                validate: { admission in
                    recurse()
                    return admission()
                }, write: recurse, onDismiss: recurse, invalidate: recurse),
            preparingFocus: { admission in
                events.values.append("current.focus")
                recurse()
                guard admission() else { return nil }
                return {}
            })
        try harness.adopt(replacement)
        original?.dismissInteractively()
        XCTAssertEqual(events.values, ["current.validate", "current.focus"] + dismissalEvents("current"))
        events.values.removeAll()
        current?.dismiss()
        XCTAssertEqual(
            events.values, dismissalEvents("current"), "A later call is allowed when the binding ignored the write")
    }

    func testGetterTriggeredAcceptedRebuildRejectsTheOldConfigurationWrite() async throws {
        let harness = PresentationActivityTestHarness()
        let events = PresentationActivityTestEvents()
        var current: PresentationDismissHandle?
        var shouldRebuild = true
        defer { harness.close() }
        let initial = try harness.rootBuild()
        let owner = try XCTUnwrap(initial.epoch.owner(at: identity("getter rebuild")))
        let original = stage(
            owner, in: initial,
            configuration: configuration(
                "old", events: events,
                validate: { admission in
                    if shouldRebuild {
                        shouldRebuild = false
                        do {
                            let replacement = try harness.rootBuild()
                            let sameOwner = try XCTUnwrap(replacement.epoch.owner(at: owner.identity))
                            current = stage(
                                sameOwner, in: replacement, configuration: configuration("new", events: events))
                            try harness.adopt(replacement)
                        } catch {
                            XCTFail("Synchronous replacement failed: \(error)")
                        }
                    }
                    return admission()
                }))
        try harness.adopt(initial)
        original.dismiss()
        XCTAssertEqual(
            events.values, ["old.validate"], "The old admission cannot write or retry using the new configuration")
        XCTAssertNotNil(current)
        XCTAssertTrue(harness.registry.owner(at: owner.identity) === owner)
        events.values.removeAll()
        current?.dismiss()
        original.dismiss()
        XCTAssertEqual(events.values, dismissalEvents("new") + dismissalEvents("new"))
    }

    func testAnAcceptedWriteThatRetiresItsOwnerStillRunsItsAdmittedCallbackAndInvalidation() async throws {
        let harness = PresentationActivityTestHarness()
        let events = PresentationActivityTestEvents()
        var original: PresentationDismissHandle?
        defer { harness.close() }
        let initial = try harness.rootBuild()
        let owner = try XCTUnwrap(initial.epoch.owner(at: identity("write retirement")))
        original = stage(
            owner, in: initial,
            configuration: configuration(
                "sheet", events: events,
                write: {
                    do {
                        let removal = try harness.rootBuild()
                        try harness.adopt(removal)
                        XCTAssertFalse(owner.isLive)
                    } catch {
                        XCTFail("Synchronous dismissal rebuild failed: \(error)")
                    }
                },
                onDismiss: {
                    XCTAssertFalse(owner.isLive)
                    original?.dismiss()
                }))
        try harness.adopt(initial)
        original?.dismiss()
        XCTAssertEqual(events.values, dismissalEvents("sheet"))
        XCTAssertNil(harness.registry.owner(at: owner.identity))
        original?.dismiss()
        original?.dismissInteractively()
        XCTAssertEqual(events.values, dismissalEvents("sheet"))
    }

    func testUnadoptedAbsenceAndReplacementDoNotCreateAnActivityGenerationGap() async throws {
        let harness = PresentationActivityTestHarness()
        let events = PresentationActivityTestEvents()
        defer { harness.close() }
        let initial = try harness.rootBuild()
        let owner = try XCTUnwrap(initial.epoch.owner(at: identity("coalesced A")))
        let original = stage(owner, in: initial, configuration: configuration("original", events: events))
        try harness.adopt(initial)

        let absentCandidate = try harness.rootBuild()
        harness.abandon(absentCandidate)
        original.dismiss()
        XCTAssertEqual(events.values, dismissalEvents("original"))
        events.values.removeAll()

        let replacementCandidate = try harness.rootBuild()
        let otherOwner = try XCTUnwrap(replacementCandidate.epoch.owner(at: identity("coalesced B")))
        let other = stage(
            otherOwner, in: replacementCandidate, configuration: configuration("unadopted B", events: events))
        replacementCandidate.activity.discardSubtree(at: otherOwner.identity) { replacementCandidate.epoch.canAdopt }
        replacementCandidate.epoch.discardUnadoptedSubtree(at: otherOwner.identity, preserveCommitted: false)
        let sameOwner = try XCTUnwrap(replacementCandidate.epoch.owner(at: owner.identity))
        let current = stage(
            sameOwner, in: replacementCandidate, configuration: configuration("accepted A", events: events))
        try harness.adopt(replacementCandidate)

        XCTAssertTrue(sameOwner === owner)
        XCTAssertEqual(sameOwner.generation, owner.generation)
        XCTAssertFalse(otherOwner.isLive)
        other.dismiss()
        other.dismissInteractively()
        XCTAssertEqual(events.values, [])
        original.dismiss()
        current.dismiss()
        XCTAssertEqual(events.values, dismissalEvents("accepted A") + dismissalEvents("accepted A"))
    }
}

@MainActor
private func identity(_ name: String) -> RetainedViewIdentity {
    RetainedViewIdentity(segments: [.view(ObjectIdentifier(PresentationActivityTestSlots.self)), .keyed(.init(name))])
}

@MainActor
private func dismissalEvents(_ name: String) -> [String] {
    ["\(name).validate", "\(name).write", "\(name).onDismiss", "\(name).invalidate"]
}

@MainActor
private func configuration(
    _ name: String, events: PresentationActivityTestEvents,
    validate: (@MainActor (PresentationDismissConfiguration.Admission) -> Bool)? = nil,
    write: (@MainActor () -> Void)? = nil,
    onDismiss: (@MainActor () -> Void)? = nil,
    invalidate: (@MainActor () -> Void)? = nil
) -> PresentationDismissConfiguration {
    PresentationDismissConfiguration(
        validate: { admission in
            events.values.append("\(name).validate")
            return validate?(admission) ?? admission()
        },
        writeDismissal: {
            events.values.append("\(name).write")
            write?()
        },
        onDismiss: {
            events.values.append("\(name).onDismiss")
            onDismiss?()
        },
        invalidate: {
            events.values.append("\(name).invalidate")
            invalidate?()
        })
}

@MainActor
private func releasingConfiguration(
    _ name: String, events: PresentationActivityTestEvents, weakProbe: PresentationActivityWeakProbe,
    onRelease: @escaping @MainActor () -> Void
) -> PresentationDismissConfiguration {
    let probe = PresentationActivityReleaseProbe(onRelease)
    weakProbe.value = probe
    return configuration(
        name, events: events,
        validate: { [probe] admission in
            withExtendedLifetime(probe) { admission() }
        })
}

@MainActor
private func focus(
    _ name: String, events: PresentationActivityTestEvents
) -> PresentationDismissConfiguration.FocusPreparation {
    { admission in
        guard admission() else { return nil }
        events.values.append("\(name).focus")
        return { events.values.append("\(name).restore") }
    }
}

@MainActor
private func stage(
    _ owner: StateMountOwner, in build: PresentationActivityTestBuild,
    configuration: PresentationDismissConfiguration,
    preparingFocus: @escaping PresentationDismissConfiguration.FocusPreparation = { _ in {} }
) -> PresentationDismissHandle {
    let handle = build.activity.stagePresentation(owner: owner, configuration: configuration)
    handle.materialize(preparingFocus: preparingFocus)
    return handle
}

private struct PresentationActivityTestBuild {
    let epoch: StateMountEpoch
    let activity: PresentationActivityBuild
}

@MainActor
private final class PresentationActivityTestHarness {
    let registry = StateMountRegistry()
    let ledger = PresentationActivityLedger()

    func rootBuild() throws -> PresentationActivityTestBuild {
        let epoch = try XCTUnwrap(registry.beginRootBuild())
        let activity = try XCTUnwrap(ledger.beginBuild())
        return PresentationActivityTestBuild(epoch: epoch, activity: activity)
    }

    func subtreeBuild(boundary: PresentationActivityAnchor) throws -> PresentationActivityTestBuild {
        let epoch = try XCTUnwrap(
            registry.beginSubtreeBuild(owner: boundary.owner, contentPrefix: boundary.contentPrefix))
        let activity = try XCTUnwrap(ledger.beginBuild(prefix: boundary.contentPrefix, boundary: boundary))
        return PresentationActivityTestBuild(epoch: epoch, activity: activity)
    }

    func prepare(_ build: PresentationActivityTestBuild, file: StaticString = #filePath, line: UInt = #line) throws {
        let activityPrepared = build.activity.prepare(isCurrent: { build.epoch.canAdopt })
        XCTAssertTrue(activityPrepared, file: file, line: line)
        guard activityPrepared else { throw PresentationActivityTestFailure.cannotPrepare }
        let statePrepared = build.epoch.prepareForAdoption()
        XCTAssertTrue(statePrepared, file: file, line: line)
        guard statePrepared else { throw PresentationActivityTestFailure.cannotPrepare }
    }

    func adopt(
        _ build: PresentationActivityTestBuild, finish: Bool = true, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        try prepare(build, file: file, line: line)
        try commitPrepared(build, finish: finish, file: file, line: line)
    }

    func commitPrepared(
        _ build: PresentationActivityTestBuild, finish: Bool = true, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        build.epoch.commitAdoption()
        XCTAssertTrue(build.epoch.didCommit, file: file, line: line)
        guard build.epoch.didCommit else { throw PresentationActivityTestFailure.cannotCommit }
        build.activity.commit()
        if finish { self.finish(build) }
    }

    func abandon(_ build: PresentationActivityTestBuild) {
        build.activity.abandon()
        build.epoch.abort()
        finish(build)
    }

    func finish(_ build: PresentationActivityTestBuild) {
        build.activity.finish()
        registry.finishPendingRetirements()
    }

    func close() {
        ledger.closeAdmissions()
        registry.close()
        ledger.releaseClosedPayloads()
    }
}

private enum PresentationActivityTestFailure: Error {
    case cannotPrepare
    case cannotCommit
}

private struct PresentationActivityTestSlots {
    private var storedValue = 0
    private var storedPayload = 0

    static var value: StatePropertySlot {
        StatePropertySlot(declaration: [\Self.storedValue], concreteTypes: [ObjectIdentifier(Self.self)])
    }

    static var payload: StatePropertySlot {
        StatePropertySlot(declaration: [\Self.storedPayload], concreteTypes: [ObjectIdentifier(Self.self)])
    }
}

@MainActor
private final class PresentationActivityTestEvents {
    var values: [String] = []
}

@MainActor
private final class PresentationActivityWeakProbe {
    weak var value: PresentationActivityReleaseProbe?
}

@MainActor
private final class PresentationActivityReleaseProbe {
    private let onRelease: @MainActor () -> Void

    init(_ onRelease: @escaping @MainActor () -> Void) {
        self.onRelease = onRelease
    }

    isolated deinit { onRelease() }
}
