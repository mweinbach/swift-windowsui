import SwiftWindowsCore
import SwiftWindowsLayout
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Phase records are native observations of actual queries. None of these
/// tests supplies a saved phase, callback sink, replacement debit, or receipt.
/// The existing public default/8/16/1x1 budget oracles remain separate.
@MainActor
final class LazyListUIAUnusedProviderPhaseTests: XCTestCase {
    func testPublicPendingReplacementResumesOneUnenteredPhaseWithinFourDebits() async throws {
        let fixture = try UnusedProviderPublicFixture()
        defer { fixture.close() }
        let element = try fixture.item(at: 300)
        let identities = fixture.source.logicalItemIdentityCount
        fixture.host.reload()
        let factories = fixture.probe.factories.count
        let runtime = fixture.host.runtime
        runtime.recordsLazyListUIAPhasesForTesting = true

        let completed = fixture.source.uiaRealizeVirtualizedItem(elementID: element)

        XCTAssertTrue(completed)
        XCTAssertEqual(fixture.source.uiaLogicalItemState(elementID: element), .ordinary)
        XCTAssertEqual(fixture.source.logicalItemIdentityCount, identities)
        XCTAssertTrue(fixture.probe.factories.contains(300))
        XCTAssertLessThan(fixture.probe.factories.count - factories, 128)
        XCTAssertEqual(runtime.lastLazyListConsumedRounds, 4)
        XCTAssertLessThanOrEqual(runtime.lastLazyListConsumedElements, 128)
        XCTAssertTrue(fixture.probe.activations.isEmpty)
        try assertFourRoundTrace(in: runtime)
        try assertSettledWithoutQuery(runtime)
    }

    func testPublicStateRowsRetireOrdinarilyBeforeTheCompletedReveal() async throws {
        let fixture = try UnusedProviderPublicFixture(stateful: true)
        defer { fixture.close() }
        let element = try fixture.item(at: 300)
        fixture.host.reload()
        let runtime = fixture.host.runtime
        runtime.recordsLazyListUIAPhasesForTesting = true

        XCTAssertTrue(fixture.source.uiaRealizeVirtualizedItem(elementID: element))

        try assertFourRoundTrace(in: runtime)
        try assertSettledWithoutQuery(runtime)
        let target = try XCTUnwrap(
            fixture.probe.captures.first { $0.id == 300 && $0.round == 2 },
            "The target belongs to the resumed, already charged provider phase")
        XCTAssertEqual(target.physical.state, .active)
        XCTAssertTrue(target.owner.isLive)
        XCTAssertEqual(target.binding.wrappedValue, 41)
        let trace = runtime.lazyListUIAPhasesForTesting
        let resumedIndex = try XCTUnwrap(trace.firstIndex { $0.kind == .resumedProviderPhase })
        let adoptedPass = try XCTUnwrap(
            trace.enumerated().first { $0.offset > resumedIndex && $0.element.kind == .layoutPass }?.element)
        let scroll = try XCTUnwrap(trace.first { $0.kind == .ownedScroll })
        let adoptedIDs = Set(try XCTUnwrap(adoptedPass.activePhysicalActivityIDs))
        let scrolledIDs = Set(try XCTUnwrap(scroll.activePhysicalActivityIDs))
        XCTAssertEqual(adoptedPass.consumedRounds, 2)
        XCTAssertTrue(adoptedIDs.contains(ObjectIdentifier(target.physical)))
        XCTAssertTrue(scrolledIDs.contains(ObjectIdentifier(target.physical)))
        let retiredPlanningRows = fixture.probe.captures.filter {
            $0.round == 2 && $0.id != 300 && adoptedIDs.contains(ObjectIdentifier($0.physical))
                && !scrolledIDs.contains(ObjectIdentifier($0.physical))
        }
        XCTAssertFalse(
            retiredPlanningRows.isEmpty,
            "At least one actual adopted State row must retire before the owned scroll, not during the final viewport")
        for retired in retiredPlanningRows {
            XCTAssertEqual(retired.physical.state, .revoked)
            XCTAssertTrue(retired.owner.isLive, "Physical eviction does not delete a still-declared logical row")
            XCTAssertFalse(retired.physical.actualAttachments.contains(where: \.isAttached))
            XCTAssertTrue(fixture.host.coordinator.registry.owner(at: retired.owner.identity) === retired.owner)
            XCTAssertEqual(retired.binding.wrappedValue, 41)
        }
        XCTAssertFalse(runtime.hasActiveRetainedBuild)
        XCTAssertTrue(fixture.probe.activations.isEmpty)

        // All completion diagnostics above are passive. This is deliberately
        // a subsequent ordinary State update, after the UIA request has ended.
        runtime.recordsLazyListUIAPhasesForTesting = false
        let previousCaptures = fixture.probe.captures.count
        target.binding.wrappedValue = 87
        XCTAssertNotNil(fixture.host.layout())
        let refreshed = try XCTUnwrap(fixture.probe.captures.dropFirst(previousCaptures).last { $0.id == 300 })
        XCTAssertTrue(refreshed.owner === target.owner)
        XCTAssertEqual(refreshed.binding.wrappedValue, 87)
    }

    func testTreeOwnedOldPrepaintAllowsExactlyOneResume() async throws {
        let fixture = try UnusedProviderRawFixture(hasSentinel: true)
        defer { fixture.close() }
        let runtime = fixture.runtime
        let generation = fixture.prepaintGeneration()
        let witness = try fixture.target()
        let mutation = try XCTUnwrap(runtime.beginAccessibilityMutation())
        defer { runtime.endAccessibilityMutation(mutation) }
        runtime.recordsLazyListUIAPhasesForTesting = true

        try runtime.withLazyListResolutionBudget {
            let request = try XCTUnwrap(
                runtime.prepareLazyListUIARequest(token: witness.token, in: witness, during: mutation))
            defer { runtime.finishLazyListUIARequest(request) }
            XCTAssertNotEqual(fixture.prepaintGeneration(), generation)
            XCTAssertNotNil(fixture.sentinel)
            XCTAssertEqual(fixture.probe.releases, 0)
            XCTAssertFalse(fixture.probe.factories.contains(300))
            let preparedTrace = runtime.lazyListUIAPhasesForTesting
            let saved = try XCTUnwrap(preparedTrace.last { $0.kind == .savedProviderPhase })
            XCTAssertEqual(preparedTrace.filter { $0.kind == .savedProviderPhase }.count, 1)
            XCTAssertFalse(
                preparedTrace.contains {
                    $0.consumedRounds == saved.consumedRounds
                        && ($0.kind == .readerPhase || $0.kind == .providerPhase)
                }, "A phase is reusable only if neither reader nor provider work entered it")

            XCTAssertNotNil(runtime.resolveLazyListUIARequest(request))
            try assertSettledWithoutQuery(runtime)
            let completedTrace = runtime.lazyListUIAPhasesForTesting
            let resumed = try XCTUnwrap(completedTrace.first { $0.kind == .resumedProviderPhase })
            XCTAssertEqual(resumed.layoutPassID, saved.layoutPassID)
            XCTAssertEqual(resumed.consumedRounds, saved.consumedRounds)
            XCTAssertEqual(completedTrace.filter { $0.kind == .resumedProviderPhase }.count, 1)
            XCTAssertGreaterThan(fixture.scroll.scrollOffset, 0)
            let factories = fixture.probe.factories
            let traceCount = completedTrace.count

            XCTAssertNil(runtime.resolveLazyListUIARequest(request))

            XCTAssertEqual(fixture.probe.factories, factories)
            XCTAssertEqual(runtime.lazyListUIAPhasesForTesting.count, traceCount)
            XCTAssertNotNil(fixture.sentinel)
            XCTAssertEqual(fixture.probe.releases, 0)
        }
    }

    func testSnapshotOnlyRetiredNodeRevokesBeforeItsNoOpDestructor() async throws {
        let fixture = try UnusedProviderRawFixture(hasSentinel: true)
        defer { fixture.close() }
        let runtime = fixture.runtime
        let witness = try fixture.target()
        fixture.removeSentinel()
        XCTAssertNotNil(fixture.sentinel, "Only the old prepaint now owns this detached node")
        XCTAssertEqual(fixture.probe.releases, 0)
        XCTAssertTrue(runtime.configureLazyListResolutionBudget(elementLimit: 32, roundLimit: 1))
        let mutation = try XCTUnwrap(runtime.beginAccessibilityMutation())
        defer { runtime.endAccessibilityMutation(mutation) }
        runtime.recordsLazyListUIAPhasesForTesting = true

        runtime.withLazyListResolutionBudget {
            let request = runtime.prepareLazyListUIARequest(token: witness.token, in: witness, during: mutation)
            if let request { runtime.finishLazyListUIARequest(request) }
            XCTAssertNil(request)
        }

        XCTAssertNil(fixture.sentinel)
        XCTAssertEqual(fixture.probe.releases, 1)
        XCTAssertEqual(fixture.probe.resumesAtRelease, 0)
        XCTAssertEqual(fixture.probe.savedAtRelease, fixture.probe.revokedAtRelease)
        XCTAssertEqual(fixture.probe.farFactoriesAtRelease, 0)
        XCTAssertEqual(fixture.probe.offsetAtRelease, 0)
        XCTAssertFalse(runtime.lazyListUIAPhasesForTesting.contains { $0.kind == .resumedProviderPhase })
        XCTAssertFalse(fixture.probe.factories.contains(300))
        XCTAssertEqual(fixture.scroll.scrollOffset, 0)
        XCTAssertEqual(runtime.lastLazyListConsumedRounds, 1)
    }

    func testSnapshotOwnershipIsCheckedWhileThePreparedRequestStillHasASpareRound() async throws {
        for retireSentinel in [false, true] {
            let fixture = try UnusedProviderRawFixture(hasSentinel: true)
            defer { fixture.close() }
            let runtime = fixture.runtime
            let witness = try fixture.target()
            if retireSentinel { fixture.removeSentinel() }
            XCTAssertNotNil(fixture.sentinel)
            XCTAssertEqual(fixture.probe.releases, 0)
            XCTAssertTrue(runtime.configureLazyListResolutionBudget(elementLimit: 32, roundLimit: 2))
            let mutation = try XCTUnwrap(runtime.beginAccessibilityMutation())
            defer { runtime.endAccessibilityMutation(mutation) }
            runtime.recordsLazyListUIAPhasesForTesting = true

            try runtime.withLazyListResolutionBudget {
                let request = try XCTUnwrap(
                    runtime.prepareLazyListUIARequest(token: witness.token, in: witness, during: mutation))
                defer { runtime.finishLazyListUIARequest(request) }
                let trace = runtime.lazyListUIAPhasesForTesting
                let debit = try XCTUnwrap(trace.last { $0.kind == .roundDebit })
                XCTAssertEqual(debit.consumedRounds, 1)
                XCTAssertEqual(debit.remainingRounds, 1, "Exhaustion must not conceal the ownership check")
                XCTAssertFalse(trace.contains { $0.kind == .resumedProviderPhase })
                XCTAssertFalse(trace.contains { $0.kind == .ownedScroll })
                XCTAssertFalse(fixture.probe.factories.contains(300))
                XCTAssertEqual(fixture.scroll.scrollOffset, 0)
                if retireSentinel {
                    XCTAssertNil(fixture.sentinel)
                    XCTAssertEqual(fixture.probe.releases, 1)
                    XCTAssertEqual(fixture.probe.savedAtRelease, fixture.probe.revokedAtRelease)
                    XCTAssertEqual(fixture.probe.resumesAtRelease, 0)
                    XCTAssertEqual(fixture.probe.farFactoriesAtRelease, 0)
                    XCTAssertEqual(fixture.probe.offsetAtRelease, 0)
                    XCTAssertEqual(
                        trace.filter { $0.kind == .savedProviderPhase }.count,
                        trace.filter { $0.kind == .revokedProviderPhase }.count)
                } else {
                    XCTAssertNotNil(fixture.sentinel)
                    XCTAssertEqual(fixture.probe.releases, 0)
                    XCTAssertEqual(trace.filter { $0.kind == .savedProviderPhase }.count, 1)
                    XCTAssertFalse(trace.contains { $0.kind == .revokedProviderPhase })
                }
                // Inspect preparation before any target resolve can consume
                // the spare round. Both requests then use normal cleanup.
            }

            XCTAssertEqual(runtime.lastLazyListConsumedRounds, 1)
        }
    }

    func testDroppingThePreparedRequestCannotRetainOrLendItsSavedPhaseToAnotherToken() async throws {
        let fixture = try UnusedProviderRawFixture()
        defer { fixture.close() }
        let runtime = fixture.runtime
        let witness = try fixture.target()
        let otherToken = try XCTUnwrap(fixture.source.token(for: .init(400)))
        let otherWitness = try XCTUnwrap(runtime.lazyListTarget(in: fixture.list, token: otherToken))
        XCTAssertTrue(runtime.configureLazyListResolutionBudget(elementLimit: 32, roundLimit: 2))
        let mutation = try XCTUnwrap(runtime.beginAccessibilityMutation())
        defer { runtime.endAccessibilityMutation(mutation) }
        runtime.recordsLazyListUIAPhasesForTesting = true

        try runtime.withLazyListResolutionBudget {
            let released = try prepareWithoutRetainingRequest(in: fixture, witness: witness, during: mutation)
            XCTAssertNil(released.request, "A saved phase must not extend its original request's lifetime")
            let saved = try XCTUnwrap(runtime.lazyListUIAPhasesForTesting.last { $0.kind == .savedProviderPhase })
            XCTAssertEqual(saved.remainingRounds, 1)
            let factories = fixture.probe.factories

            let next = runtime.prepareLazyListUIARequest(token: otherToken, in: otherWitness, during: mutation)
            if let next { runtime.finishLazyListUIARequest(next) }

            XCTAssertNil(next)
            let trace = runtime.lazyListUIAPhasesForTesting
            XCTAssertEqual(
                trace.filter { $0.kind == .roundDebit }.map(\.consumedRounds), [1, 2],
                "A new preparation must actually enter; a retained old preparation would block its query")
            XCTAssertEqual(trace.last { $0.kind == .roundDebit }?.remainingRounds, 0)
            XCTAssertEqual(trace.filter { $0.kind == .savedProviderPhase }.count, 1)
            XCTAssertEqual(trace.filter { $0.kind == .revokedProviderPhase }.count, 1)
            let revokedIndex = try XCTUnwrap(trace.firstIndex { $0.kind == .revokedProviderPhase })
            let nextPassIndex = try XCTUnwrap(
                trace.firstIndex { $0.kind == .layoutPass && $0.layoutPassID > saved.layoutPassID })
            XCTAssertEqual(trace[revokedIndex].consumedRounds, 1)
            XCTAssertEqual(trace[revokedIndex].remainingRounds, 1)
            XCTAssertLessThan(revokedIndex, nextPassIndex)
            XCTAssertFalse(trace.contains { $0.kind == .resumedProviderPhase })
            XCTAssertFalse(trace.contains { $0.kind == .ownedScroll })
            XCTAssertEqual(fixture.probe.factories, factories)
            XCTAssertFalse(fixture.probe.factories.contains(300))
            XCTAssertFalse(fixture.probe.factories.contains(400))
            XCTAssertEqual(fixture.scroll.scrollOffset, 0)
        }
        XCTAssertEqual(runtime.lastLazyListConsumedElements, 0)
        XCTAssertEqual(runtime.lastLazyListConsumedRounds, 2)
    }

    func testQueuedInitialNoOpCannotReissueTheSpentProviderPhase() async throws {
        let fixture = try UnusedProviderRawFixture()
        defer { fixture.close() }
        let runtime = fixture.runtime
        let witness = try fixture.target()
        XCTAssertTrue(runtime.configureLazyListResolutionBudget(elementLimit: 32, roundLimit: 1))
        var callbackCount = 0
        var callbackPass: UInt64?
        runtime.scheduleAfterLayout(key: "uia-unused-provider-initial-no-op") { [weak runtime] in
            callbackCount += 1
            callbackPass = runtime?.layoutPassID
        }
        let mutation = try XCTUnwrap(runtime.beginAccessibilityMutation())
        defer { runtime.endAccessibilityMutation(mutation) }
        runtime.recordsLazyListUIAPhasesForTesting = true

        runtime.withLazyListResolutionBudget {
            let request = runtime.prepareLazyListUIARequest(token: witness.token, in: witness, during: mutation)
            if let request { runtime.finishLazyListUIARequest(request) }
            XCTAssertNil(request)
        }

        XCTAssertEqual(callbackCount, 1, "The ordinary initial epilogue still delivers its queued callback")
        XCTAssertGreaterThan(runtime.layoutPassID, try XCTUnwrap(callbackPass))
        let trace = runtime.lazyListUIAPhasesForTesting
        XCTAssertEqual(trace.filter { $0.kind == .roundDebit }.map(\.consumedRounds), [1])
        XCTAssertEqual(trace.filter { $0.kind == .providerPhase }.count, 1)
        XCTAssertFalse(trace.contains { $0.kind == .savedProviderPhase || $0.kind == .resumedProviderPhase })
        XCTAssertFalse(fixture.probe.factories.contains(300))
        XCTAssertEqual(fixture.scroll.scrollOffset, 0)
        XCTAssertEqual(runtime.lastLazyListConsumedRounds, 1)
    }

    func testReaderWorkFollowedByAnEmptyProviderPhaseCannotBeSavedAfterLayout() async throws {
        let readerProbe = UnusedProviderReaderProbe()
        let reader = readerProbe.makeNode(builtSize: Size(width: 120, height: 20))
        let fixture = try UnusedProviderRawFixture(beforeList: [reader])
        defer { fixture.close() }
        let runtime = fixture.runtime
        let witness = try fixture.target()
        let factories = fixture.probe.factories
        XCTAssertEqual(readerProbe.calls, 0)
        XCTAssertTrue(runtime.configureLazyListResolutionBudget(elementLimit: 32, roundLimit: 1))
        reader.geometryReaderBuiltSize = Size(width: 120, height: 10)
        let mutation = try XCTUnwrap(runtime.beginAccessibilityMutation())
        defer { runtime.endAccessibilityMutation(mutation) }
        runtime.recordsLazyListUIAPhasesForTesting = true

        runtime.withLazyListResolutionBudget {
            let request = runtime.prepareLazyListUIARequest(token: witness.token, in: witness, during: mutation)
            if let request { runtime.finishLazyListUIARequest(request) }
            XCTAssertNil(request)
        }

        XCTAssertEqual(readerProbe.calls, 1)
        XCTAssertEqual(reader.geometryReaderBuiltSize, Size(width: 120, height: 20))
        XCTAssertEqual(fixture.probe.factories, factories, "The provider phase was entered but had no List work")
        let trace = runtime.lazyListUIAPhasesForTesting
        let readerIndex = try XCTUnwrap(trace.firstIndex { $0.kind == .readerPhase })
        let providerIndex = try XCTUnwrap(trace.firstIndex { $0.kind == .providerPhase })
        let layoutIndex = try XCTUnwrap(trace.indices.first { $0 > providerIndex && trace[$0].kind == .layoutPass })
        XCTAssertLessThan(readerIndex, providerIndex)
        XCTAssertLessThan(providerIndex, layoutIndex)
        XCTAssertEqual(trace[layoutIndex].consumedRounds, 1)
        XCTAssertFalse(trace.contains { $0.kind == .savedProviderPhase || $0.kind == .resumedProviderPhase })
        XCTAssertEqual(runtime.lastLazyListConsumedRounds, 1)
        XCTAssertEqual(fixture.scroll.scrollOffset, 0)
    }

    func testARealNewPassCannotResumeTheOriginalSavedPhaseAfterBudgetExhaustion() async throws {
        let fixture = try UnusedProviderRawFixture()
        defer { fixture.close() }
        let runtime = fixture.runtime
        let witness = try fixture.target()
        XCTAssertTrue(runtime.configureLazyListResolutionBudget(elementLimit: 32, roundLimit: 2))
        let mutation = try XCTUnwrap(runtime.beginAccessibilityMutation())
        defer { runtime.endAccessibilityMutation(mutation) }
        runtime.recordsLazyListUIAPhasesForTesting = true

        try runtime.withLazyListResolutionBudget {
            let request = try XCTUnwrap(
                runtime.prepareLazyListUIARequest(token: witness.token, in: witness, during: mutation))
            defer { runtime.finishLazyListUIARequest(request) }
            let saved = try XCTUnwrap(runtime.lazyListUIAPhasesForTesting.last { $0.kind == .savedProviderPhase })
            XCTAssertEqual(saved.remainingRounds, 1)
            let factories = fixture.probe.factories

            XCTAssertNotNil(runtime.resolvedLayoutFrame(of: fixture.scroll))
            XCTAssertGreaterThan(runtime.layoutPassID, saved.layoutPassID)
            let interruptedTrace = runtime.lazyListUIAPhasesForTesting
            let finalDebit = try XCTUnwrap(interruptedTrace.last { $0.kind == .roundDebit })
            XCTAssertEqual(finalDebit.consumedRounds, 2)
            XCTAssertEqual(finalDebit.remainingRounds, 0)
            XCTAssertEqual(interruptedTrace.filter { $0.kind == .revokedProviderPhase }.count, 1)
            XCTAssertNil(runtime.resolveLazyListUIARequest(request))

            XCTAssertEqual(fixture.probe.factories, factories)
            XCTAssertFalse(runtime.lazyListUIAPhasesForTesting.contains { $0.kind == .resumedProviderPhase })
            XCTAssertEqual(runtime.lazyListUIAPhasesForTesting.filter { $0.kind == .savedProviderPhase }.count, 1)
            XCTAssertEqual(fixture.scroll.scrollOffset, 0)
        }
        XCTAssertEqual(runtime.lastLazyListConsumedRounds, 2)
    }

    func testRestoringIdentityOrScrollValuesCannotReviveASavedPhase() async throws {
        for replacement in UnusedProviderABA.allCases {
            let fixture = try UnusedProviderRawFixture()
            defer { fixture.close() }
            let runtime = fixture.runtime
            let witness = try fixture.target()
            let mutation = try XCTUnwrap(runtime.beginAccessibilityMutation())
            defer { runtime.endAccessibilityMutation(mutation) }
            runtime.recordsLazyListUIAPhasesForTesting = true

            try runtime.withLazyListResolutionBudget {
                let request = try XCTUnwrap(
                    runtime.prepareLazyListUIARequest(token: witness.token, in: witness, during: mutation))
                defer { runtime.finishLazyListUIARequest(request) }
                XCTAssertEqual(runtime.lazyListUIAPhasesForTesting.filter { $0.kind == .savedProviderPhase }.count, 1)
                let factories = fixture.probe.factories
                switch replacement {
                case .identity:
                    let identity = fixture.list.retainedViewIdentity
                    fixture.list.retainedViewIdentity = RetainedViewIdentity(segments: [.slot(999)])
                    fixture.list.retainedViewIdentity = identity
                case .scroll:
                    fixture.scroll.scrollOffset = 1
                    fixture.scroll.scrollOffset = 0
                case .attachment:
                    fixture.scroll.setChildren([])
                    fixture.scroll.setChildren([fixture.list])
                }

                XCTAssertNil(runtime.resolveLazyListUIARequest(request), "\(replacement)")

                XCTAssertEqual(fixture.probe.factories, factories, "\(replacement)")
                XCTAssertFalse(runtime.lazyListUIAPhasesForTesting.contains { $0.kind == .resumedProviderPhase })
                XCTAssertEqual(fixture.scroll.scrollOffset, 0)
            }
        }
    }

    func testExhaustedGeometryGenerationCannotEnterAResumedProvider() async throws {
        let fixture = try UnusedProviderRawFixture()
        defer { fixture.close() }
        let runtime = fixture.runtime
        let witness = try fixture.target()
        let factories = fixture.probe.factories
        runtime.exhaustLayoutGeometryGenerationOnNextInvalidationForTesting()
        let mutation = try XCTUnwrap(runtime.beginAccessibilityMutation())
        defer { runtime.endAccessibilityMutation(mutation) }
        runtime.recordsLazyListUIAPhasesForTesting = true

        try runtime.withLazyListResolutionBudget {
            let request = try XCTUnwrap(
                runtime.prepareLazyListUIARequest(token: witness.token, in: witness, during: mutation))
            defer { runtime.finishLazyListUIARequest(request) }
            try assertSettledWithoutQuery(runtime)
            let preparedTrace = runtime.lazyListUIAPhasesForTesting
            let debit = try XCTUnwrap(preparedTrace.last { $0.kind == .roundDebit })
            XCTAssertEqual(debit.geometryRevision, .max)
            XCTAssertEqual(debit.consumedRounds, 1)
            XCTAssertEqual(debit.remainingRounds, 15)
            XCTAssertFalse(
                preparedTrace.contains { $0.kind == .savedProviderPhase || $0.kind == .resumedProviderPhase })
            XCTAssertEqual(preparedTrace.filter { $0.kind == .providerPhase }.count, 1)
            XCTAssertEqual(fixture.probe.factories, factories)

            // G == max still permits ordinary preparation. The request's
            // own target-demand invalidation must be the actual overflow.
            XCTAssertNil(runtime.resolveLazyListUIARequest(request))

            guard case .unavailable = runtime.layoutSettlementStatus else {
                XCTFail("The ordinary target-demand path must latch geometry exhaustion")
                return
            }
        }

        XCTAssertEqual(fixture.probe.factories, factories)
        XCTAssertFalse(runtime.lazyListUIAPhasesForTesting.contains { $0.kind == .resumedProviderPhase })
        XCTAssertFalse(runtime.lazyListUIAPhasesForTesting.contains { $0.kind == .ownedScroll })
        XCTAssertEqual(fixture.scroll.scrollOffset, 0)
        XCTAssertEqual(runtime.lastLazyListConsumedElements, 0)
        XCTAssertEqual(runtime.lastLazyListConsumedRounds, 1)
    }

    func testGeometryExhaustionInsideTheFirstResumedFactoryStopsConstructionButFinishesItsEpoch() async throws {
        let fixture = try UnusedProviderRawFixture(hasSentinel: true)
        defer { fixture.close() }
        let runtime = fixture.runtime
        let sentinel = try XCTUnwrap(fixture.sentinel)
        let witness = try fixture.target()
        let mutation = try XCTUnwrap(runtime.beginAccessibilityMutation())
        defer { runtime.endAccessibilityMutation(mutation) }
        runtime.recordsLazyListUIAPhasesForTesting = true

        try runtime.withLazyListResolutionBudget {
            let request = try XCTUnwrap(
                runtime.prepareLazyListUIARequest(token: witness.token, in: witness, during: mutation))
            defer { runtime.finishLazyListUIARequest(request) }
            let saved = try XCTUnwrap(runtime.lazyListUIAPhasesForTesting.last { $0.kind == .savedProviderPhase })
            XCTAssertEqual(saved.consumedRounds, 1)
            XCTAssertEqual(saved.remainingRounds, 15)
            let factories = fixture.probe.factories
            let begins = fixture.lease.begins
            let commits = fixture.lease.commits
            let abandons = fixture.lease.abandons
            let finishes = fixture.lease.finishes
            var factoryCalls = 0
            var entryTrace: [RetainedViewRuntime.LazyListUIAPhaseTrace]?
            fixture.probe.onFactory = { [weak runtime, weak sentinel] id in
                factoryCalls += 1
                guard factoryCalls == 1 else { return }
                XCTAssertEqual(id, 300)
                guard let runtime, let sentinel else {
                    XCTFail("Expected the runtime and its attached sibling during target construction")
                    return
                }
                XCTAssertTrue(sentinel.parent === runtime.root)
                XCTAssertTrue(runtime.hasActiveRetainedBuild)
                entryTrace = runtime.lazyListUIAPhasesForTesting
                runtime.exhaustLayoutGeometryGenerationOnNextInvalidationForTesting()
                // This sibling is outside the list's ancestry. Its authored
                // frame change overflows G without revoking the target's
                // local geometry, attachment, identity, or scroll proofs.
                sentinel.frame.size.width += 1
            }
            defer { fixture.probe.onFactory = nil }

            XCTAssertNil(runtime.resolveLazyListUIARequest(request))

            let entered = try XCTUnwrap(entryTrace, "The target factory must enter before exhaustion")
            XCTAssertEqual(entered.last?.kind, .providerPhase)
            XCTAssertEqual(entered.last?.consumedRounds, 1)
            XCTAssertEqual(entered.filter { $0.kind == .resumedProviderPhase }.count, 1)
            let trace = runtime.lazyListUIAPhasesForTesting
            let afterFactory = trace.dropFirst(entered.count)
            XCTAssertFalse(afterFactory.contains { $0.kind == .readerPhase || $0.kind == .providerPhase })
            XCTAssertFalse(trace.contains { $0.kind == .ownedScroll })
            XCTAssertEqual(trace.filter { $0.kind == .roundDebit }.map(\.consumedRounds), [1])
            XCTAssertEqual(factoryCalls, 1)
            XCTAssertEqual(Array(fixture.probe.factories.dropFirst(factories.count)), [300])
            XCTAssertFalse(fixture.list.children.contains { $0.dynamicContentIndex == 300 })
            XCTAssertEqual(fixture.scroll.scrollOffset, 0)
            XCTAssertEqual(fixture.lease.begins - begins, 1)
            XCTAssertEqual(fixture.lease.commits - commits, 0)
            XCTAssertEqual(fixture.lease.abandons - abandons, 1)
            XCTAssertEqual(fixture.lease.finishes - finishes, 1)
            XCTAssertFalse(runtime.hasActiveRetainedBuild)
            guard case .unavailable = runtime.layoutSettlementStatus else {
                XCTFail("The real attached-node invalidation must latch geometry exhaustion")
                return
            }
        }
        XCTAssertEqual(runtime.lastLazyListConsumedElements, 1)
        XCTAssertEqual(runtime.lastLazyListConsumedRounds, 1)
    }

    func testReservationsRejectEveryOverflowIncludingOnlyTheSecondGeometryIncrement() async throws {
        typealias Reservation = RetainedViewRuntime.LazyListUIAProviderPhaseReservation
        let ordinary = try XCTUnwrap(
            Reservation(geometryRevision: 10, mutationRevision: 20, resolutionSequence: 30, presentationRevision: 40))
        XCTAssertEqual(ordinary.demandGeometryRevision, 11)
        XCTAssertEqual(ordinary.buildGeometryRevision, 12)
        XCTAssertEqual(ordinary.demandMutationRevision, 21)
        XCTAssertEqual(ordinary.resumeResolutionSequence, 31)
        XCTAssertEqual(ordinary.demandPresentationRevision, 41)
        let boundary = try XCTUnwrap(
            Reservation(
                geometryRevision: .max - 2, mutationRevision: .max - 1,
                resolutionSequence: .max - 1, presentationRevision: .max - 1))
        XCTAssertEqual(boundary.demandGeometryRevision, .max - 1)
        XCTAssertEqual(boundary.buildGeometryRevision, .max)
        XCTAssertEqual(boundary.demandMutationRevision, .max)
        XCTAssertEqual(boundary.resumeResolutionSequence, .max)
        XCTAssertEqual(boundary.demandPresentationRevision, .max)
        XCTAssertNil(
            Reservation(geometryRevision: .max - 1, mutationRevision: 0, resolutionSequence: 0, presentationRevision: 0)
        )
        XCTAssertNil(
            Reservation(geometryRevision: .max, mutationRevision: 0, resolutionSequence: 0, presentationRevision: 0))
        XCTAssertNil(
            Reservation(geometryRevision: 0, mutationRevision: .max, resolutionSequence: 0, presentationRevision: 0))
        XCTAssertNil(
            Reservation(geometryRevision: 0, mutationRevision: 0, resolutionSequence: .max, presentationRevision: 0))
        XCTAssertNil(
            Reservation(geometryRevision: 0, mutationRevision: 0, resolutionSequence: 0, presentationRevision: .max))
    }

    @inline(never)
    private func prepareWithoutRetainingRequest(
        in fixture: UnusedProviderRawFixture, witness: RetainedLazyListAccessibilityItem,
        during mutation: RetainedAccessibilityMutation
    ) throws -> UnusedProviderWeakRequest {
        let request = try XCTUnwrap(
            fixture.runtime.prepareLazyListUIARequest(token: witness.token, in: witness, during: mutation))
        // No resolution started and no demand was installed. Let this request
        // expire without explicit finish so its weak phase edges are tested.
        return UnusedProviderWeakRequest(request)
    }

    private func assertFourRoundTrace(
        in runtime: RetainedViewRuntime, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let trace = runtime.lazyListUIAPhasesForTesting
        let debits = trace.filter { $0.kind == .roundDebit }
        let measurements = trace.filter { $0.kind == .measurementPhase }
        let readers = trace.filter { $0.kind == .readerPhase }
        let providers = trace.filter { $0.kind == .providerPhase }
        XCTAssertEqual(debits.map(\.consumedRounds), [1, 2, 3, 4], file: file, line: line)
        XCTAssertEqual(measurements.map(\.consumedRounds), [1, 2, 3, 4], file: file, line: line)
        XCTAssertEqual(readers.map(\.consumedRounds), [1, 2, 3, 4], file: file, line: line)
        XCTAssertEqual(providers.map(\.consumedRounds), [1, 2, 3, 4], file: file, line: line)
        XCTAssertEqual(trace.filter { $0.kind == .savedProviderPhase }.count, 1, file: file, line: line)
        XCTAssertEqual(trace.filter { $0.kind == .resumedProviderPhase }.count, 1, file: file, line: line)
        XCTAssertFalse(trace.contains { $0.kind == .revokedProviderPhase }, file: file, line: line)

        let savedIndex = try XCTUnwrap(trace.firstIndex { $0.kind == .savedProviderPhase }, file: file, line: line)
        let resumedIndex = try XCTUnwrap(trace.firstIndex { $0.kind == .resumedProviderPhase }, file: file, line: line)
        let saved = trace[savedIndex]
        let resumed = trace[resumedIndex]
        guard savedIndex < resumedIndex else {
            XCTFail("A provider phase must be saved before it is resumed", file: file, line: line)
            return
        }
        XCTAssertEqual(saved.consumedRounds, 2, file: file, line: line)
        XCTAssertEqual(resumed.consumedRounds, saved.consumedRounds, file: file, line: line)
        XCTAssertEqual(resumed.remainingRounds, saved.remainingRounds, file: file, line: line)
        XCTAssertEqual(resumed.remainingElements, saved.remainingElements, file: file, line: line)
        XCTAssertEqual(resumed.layoutPassID, saved.layoutPassID, file: file, line: line)
        XCTAssertEqual(resumed.geometryRevision, saved.geometryRevision + 1, file: file, line: line)
        XCTAssertEqual(resumed.mutationRevision, saved.mutationRevision + 1, file: file, line: line)
        XCTAssertEqual(resumed.resolutionSequence, saved.resolutionSequence + 1, file: file, line: line)
        XCTAssertFalse(
            trace[..<savedIndex].contains {
                $0.consumedRounds == saved.consumedRounds
                    && ($0.kind == .readerPhase || $0.kind == .providerPhase)
            }, "The saved phase must be unentered within its original paid round", file: file, line: line)
        let intervening = trace[(savedIndex + 1)..<resumedIndex]
        XCTAssertFalse(
            intervening.contains {
                $0.kind == .layoutPass || $0.kind == .roundDebit || $0.kind == .measurementPhase
                    || $0.kind == .readerPhase || $0.kind == .providerPhase
            }, "Initial epilogues must finish without starting another phase or pass", file: file, line: line)

        let resumedProviderIndex = try XCTUnwrap(
            trace.indices.first { $0 > resumedIndex && trace[$0].kind == .providerPhase }, file: file, line: line)
        let postProviderPassIndex = try XCTUnwrap(
            trace.indices.first { $0 > resumedIndex && trace[$0].kind == .layoutPass }, file: file, line: line)
        XCTAssertLessThan(resumedProviderIndex, postProviderPassIndex, file: file, line: line)
        XCTAssertEqual(trace[resumedProviderIndex].layoutPassID, saved.layoutPassID, file: file, line: line)
        XCTAssertEqual(trace[resumedProviderIndex].geometryRevision, resumed.geometryRevision, file: file, line: line)
        XCTAssertEqual(trace[resumedProviderIndex].mutationRevision, resumed.mutationRevision, file: file, line: line)
        XCTAssertEqual(
            trace[resumedProviderIndex].resolutionSequence, resumed.resolutionSequence, file: file, line: line)
        XCTAssertFalse(
            trace[(resumedIndex + 1)..<resumedProviderIndex].contains {
                $0.kind == .roundDebit || $0.kind == .measurementPhase || $0.kind == .layoutPass
            }, "Resuming cannot repeat measurement or hide an initial target pass", file: file, line: line)

        let retirementIndex = try XCTUnwrap(
            trace.firstIndex { $0.kind == .providerPhase && $0.consumedRounds == 3 }, file: file, line: line)
        let scrollIndex = try XCTUnwrap(trace.firstIndex { $0.kind == .ownedScroll }, file: file, line: line)
        let finalDebitIndex = try XCTUnwrap(
            trace.firstIndex { $0.kind == .roundDebit && $0.consumedRounds == 4 }, file: file, line: line)
        XCTAssertLessThan(
            retirementIndex, scrollIndex, "Probe retirement remains ordinary paid work", file: file, line: line)
        XCTAssertLessThan(scrollIndex, finalDebitIndex, file: file, line: line)
        for entry in trace {
            XCTAssertEqual(entry.remainingRounds + entry.consumedRounds, 4, file: file, line: line)
        }
        for (previous, next) in zip(trace, trace.dropFirst()) {
            XCTAssertGreaterThanOrEqual(next.consumedRounds, previous.consumedRounds, file: file, line: line)
            XCTAssertLessThanOrEqual(next.remainingElements, previous.remainingElements, file: file, line: line)
        }
    }

    private func assertSettledWithoutQuery(
        _ runtime: RetainedViewRuntime, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        guard case .settled(let receipt) = runtime.layoutSettlementStatus else {
            XCTFail("Realize must return with its own completed settlement", file: file, line: line)
            return
        }
        XCTAssertTrue(runtime.isLayoutSettlementReceiptCurrent(receipt), file: file, line: line)
        XCTAssertTrue(runtime.hasCurrentAccessibilityPrepaint, file: file, line: line)
    }
}

@MainActor
private final class UnusedProviderPublicFixture {
    let probe: UnusedProviderPublicProbe
    let host: MountedLazyListTestHost
    let source: RuntimeUIAElementTreeSource
    let containerID: UInt64

    init(stateful: Bool = false) throws {
        let probe = UnusedProviderPublicProbe(stateful: stateful)
        self.probe = probe
        host = MountedLazyListTestHost(size: Size(width: 320, height: 80)) {
            List(probe.rows, id: \.self) { probe.makeRows($0) }.listStyle(.plain)
        }
        probe.runtime = host.runtime
        source = RuntimeUIAElementTreeSource(runtime: host.runtime)
        do {
            XCTAssertNotNil(host.layout())
            containerID = try XCTUnwrap(source.uiaElementSnapshots().first(where: \.supportsItemContainer)?.id)
        } catch {
            host.close()
            throw error
        }
    }

    func item(at index: Int) throws -> UInt64 {
        var current: UInt64?
        for _ in 0...index {
            let result = source.uiaFindItem(containerID: containerID, afterElementID: current)
            guard case .item(let id) = result else {
                XCTFail("Expected the next current logical List item, got \(result)")
                return try XCTUnwrap(nil as UInt64?)
            }
            current = id
        }
        return try XCTUnwrap(current)
    }

    func close() {
        host.close()
        probe.captures.removeAll()
    }
}

@MainActor
private struct UnusedProviderStateCapture {
    let id: Int
    let round: Int
    let owner: StateMountOwner
    let physical: RetainedLazyListPhysicalActivityReceipt
    let binding: Binding<Int>
}

@MainActor
private final class UnusedProviderPublicProbe {
    let rows = Array(0..<1000)
    let stateful: Bool
    weak var runtime: RetainedViewRuntime?
    var factories: [Int] = []
    var activations: [Int] = []
    var captures: [UnusedProviderStateCapture] = []

    init(stateful: Bool) { self.stateful = stateful }

    func makeRows(_ id: Int) -> [AnyView] {
        factories.append(id)
        if stateful { return [AnyView(UnusedProviderStateRow(id: id, probe: self))] }
        return [AnyView(Button("Row \(id)") { [weak self] in self?.activations.append(id) }.frame(height: 24))]
    }

    func record(_ id: Int, binding: Binding<Int>) {
        guard let identity = ViewBuildContextScope.current?.viewIdentity,
            let owner = identity.installedOwner, let activity = identity.lazyList?.native.physical
        else {
            XCTFail("A public List State row must be installed in its actual managed build")
            return
        }
        captures.append(
            UnusedProviderStateCapture(
                id: id, round: runtime?.lazyListUIAPhasesForTesting.last?.consumedRounds ?? 0,
                owner: owner, physical: activity, binding: binding))
    }
}

@MainActor
private struct UnusedProviderStateRow: View {
    @State private var value = 41
    let id: Int
    let probe: UnusedProviderPublicProbe

    var body: some View {
        probe.record(id, binding: $value)
        return Button("Row \(id): \(value)") { [weak probe] in probe?.activations.append(id) }.frame(height: 24)
    }
}

private enum UnusedProviderABA: CaseIterable {
    case identity, scroll, attachment
}

@MainActor
private final class UnusedProviderWeakRequest {
    weak var request: RetainedLazyListUIARequest?
    init(_ request: RetainedLazyListUIARequest) { self.request = request }
}

@MainActor
private final class UnusedProviderRawFixture {
    let probe = UnusedProviderRawProbe()
    let lease = UnusedProviderBuildLease()
    let source: RetainedLazyListDataSource<Int, [ViewNode]>
    let list: ViewNode
    let scroll: ViewNode
    let runtime: RetainedViewRuntime
    weak var sentinel: ViewNode?

    init(hasSentinel: Bool = false, beforeList: [ViewNode] = []) throws {
        let identity = RetainedViewIdentity(segments: [.role(.content), .slot(0)])
        let source = RetainedLazyListDataSource<Int, [ViewNode]>()
        let probe = probe
        let factory: @MainActor @Sendable (Int, RetainedViewIdentity) -> [ViewNode] = { id, prefix in
            probe.factories.append(id)
            probe.onFactory?(id)
            let row = ViewNode(preferredSize: Size(width: 120, height: 20))
            row.retainedViewIdentity = prefix.appending(.slot(0)).appending(.role(.row))
            row.dynamicContentIndex = id
            row.accessibilityIdentifier = "uia.unused.row.\(id)"
            return [row]
        }
        XCTAssertTrue(source.replaceData(Array(0..<1000), id: \.self, identityRoot: identity, rowContent: factory))
        let adapter = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter(
                provider: source, estimatedExtent: 20, prefetchExtent: 0,
                maximumMountedRecords: 16, maximumMountedLeaves: 32, maximumProtectedRecords: 2))
        let list = ViewNode(layoutMode: .lazyStack(.vertical(spacing: 0, alignment: .stretch)))
        list.retainedViewIdentity = identity
        list.retainedLazyListAdapter = adapter
        list.retainedSubtreeBuildLease = lease
        let scroll = ViewNode(
            frame: Rect(x: 0, y: 0, width: 120, height: 60), clipsToBounds: true,
            layoutMode: .stack(.vertical(spacing: 0, alignment: .stretch)),
            scrollAxis: .vertical, children: beforeList + [list])
        let root = ViewNode(frame: Rect(x: 0, y: 0, width: 120, height: 60), children: [scroll])
        let runtime = RetainedViewRuntime(root: root)
        runtime.clock = { 0 }
        self.source = source
        self.list = list
        self.scroll = scroll
        self.runtime = runtime
        probe.runtime = runtime
        probe.scroll = scroll
        if hasSentinel { installSentinel() }
        // Raw contract cases have their own explicit allowance. Public tests
        // above and the unchanged budget suite exercise the actual default.
        XCTAssertTrue(runtime.configureLazyListResolutionBudget(elementLimit: 32, roundLimit: 16))
        XCTAssertNotNil(runtime.resolvedLayoutFrame(of: scroll))
        XCTAssertTrue(runtime.hasCurrentAccessibilityPrepaint)
        XCTAssertFalse(adapter.hasUnresolvedWork)
        XCTAssertFalse(probe.factories.contains(300))
    }

    func target() throws -> RetainedLazyListAccessibilityItem {
        let token = try XCTUnwrap(source.token(for: .init(300)))
        return try XCTUnwrap(runtime.lazyListTarget(in: list, token: token))
    }

    @inline(never)
    func prepaintGeneration() -> ObjectIdentifier {
        ObjectIdentifier(runtime.currentPrepaintState.generation)
    }

    @inline(never)
    private func installSentinel() {
        let sentinel = ViewNode(frame: Rect(x: 105, y: 45, width: 10, height: 10))
        let payload = UnusedProviderSnapshotPayload(probe: probe)
        sentinel.onActivate = { [payload] in withExtendedLifetime(payload) {} }
        runtime.root.addChild(sentinel)
        self.sentinel = sentinel
    }

    @inline(never)
    func removeSentinel() {
        guard let sentinel else {
            XCTFail("Expected the warmed snapshot sentinel")
            return
        }
        runtime.root.removeChild(sentinel)
    }

    func close() {
        probe.onFactory = nil
        runtime.stopRenderLifecycleCallbacks()
        source.close()
        runtime.cancelRenderLifecycleTasks()
        runtime.root.removeAllChildren()
    }
}

@MainActor
private final class UnusedProviderRawProbe {
    weak var runtime: RetainedViewRuntime?
    weak var scroll: ViewNode?
    var factories: [Int] = []
    var onFactory: (@MainActor @Sendable (Int) -> Void)?
    var releases = 0
    var savedAtRelease: Int?
    var revokedAtRelease: Int?
    var resumesAtRelease: Int?
    var farFactoriesAtRelease: Int?
    var offsetAtRelease: Double?

    func recordRelease() {
        releases += 1
        let trace = runtime?.lazyListUIAPhasesForTesting ?? []
        savedAtRelease = trace.filter { $0.kind == .savedProviderPhase }.count
        revokedAtRelease = trace.filter { $0.kind == .revokedProviderPhase }.count
        resumesAtRelease = trace.filter { $0.kind == .resumedProviderPhase }.count
        farFactoriesAtRelease = factories.filter { $0 == 300 }.count
        offsetAtRelease = scroll?.scrollOffset
    }
}

@MainActor
private final class UnusedProviderSnapshotPayload {
    let probe: UnusedProviderRawProbe
    init(probe: UnusedProviderRawProbe) { self.probe = probe }

    // This deliberately does not invalidate, detach, or otherwise change the
    // runtime. A no-op destructor is already an application callout boundary.
    isolated deinit { probe.recordRelease() }
}

@MainActor
private final class UnusedProviderReaderProbe {
    var calls = 0

    func makeNode(builtSize: Size) -> ViewNode {
        let node = ViewNode(preferredSize: Size(width: 120, height: 20))
        install(on: node, builtSize: builtSize)
        return node
    }

    private func install(on node: ViewNode, builtSize: Size) {
        let preferredSize = node.preferredSize
        let identity = node.retainedViewIdentity
        node.geometryReaderBuiltSize = builtSize
        node.geometryReaderBuild = { [self] _, slot in
            calls += 1
            let candidate = ViewNode(preferredSize: preferredSize)
            candidate.retainedViewIdentity = identity
            install(on: candidate, builtSize: slot)
            return [candidate]
        }
    }
}

@MainActor
private final class UnusedProviderBuildLease: RetainedSubtreeBuildLease {
    var begins = 0
    var commits = 0
    var abandons = 0
    var finishes = 0
    var canBuild: Bool { true }
    func beginBuild() -> (any RetainedBuildEpoch)? {
        begins += 1
        return UnusedProviderBuildEpoch(lease: self)
    }
}

@MainActor
private final class UnusedProviderBuildEpoch: RetainedBuildEpoch {
    let lease: UnusedProviderBuildLease
    private var prepared = false
    private var wasSuperseded = false
    init(lease: UnusedProviderBuildLease) { self.lease = lease }
    var canAdopt: Bool { !prepared && !wasSuperseded }
    func supersede() { if !prepared { wasSuperseded = true } }
    func willAdopt() -> Bool {
        guard canAdopt else { return false }
        prepared = true
        return true
    }
    func commit() { lease.commits += 1 }
    func abandon() { lease.abandons += 1 }
    func finishAfterCallbacks() { lease.finishes += 1 }
}
