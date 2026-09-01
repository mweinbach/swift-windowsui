import SwiftWindowsCore
import SwiftWindowsLayout
@preconcurrency import XCTest

@testable import SwiftWindowsUI

/// Headless gapless rows exercise the Runtime continuation, actual layout,
/// and prepaint. They do not establish native COM or public List gap budgets.
@MainActor
final class LazyListUIAContinuationTests: XCTestCase {
    func testMeasuredOffscreenTargetKeepsItsOriginalNodeThroughOwnedReveal() async throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        let calls = fixture.probe.factories
        var preparedReceipt: RetainedLayoutSettlementReceipt?

        try withRequest(in: fixture) { request, _ in
            XCTAssertEqual(request.item.token, fixture.source.token(for: .init(300)))
            XCTAssertTrue(fixture.runtime.isLazyListAccessibilityItemCurrent(request.item))
            XCTAssertEqual(fixture.probe.factories, calls, "Preparation cannot install the far target demand")
            preparedReceipt = try settledReceipt(in: fixture.runtime)
            XCTAssertEqual(fixture.scroll.scrollOffset, 0)

            let roots = try XCTUnwrap(fixture.runtime.resolveLazyListUIARequest(request))

            try assertResolved(roots, for: request, in: fixture, id: 300)
            XCTAssertEqual(fixture.probe.factories.filter { $0 == 300 }.count, 1)
            XCTAssertGreaterThan(fixture.scroll.scrollOffset, 0)
            XCTAssertEqual(fixture.scroll.resolvedScrollOffset, fixture.scroll.scrollOffset)
            XCTAssertFalse(fixture.runtime.isLayoutSettlementReceiptCurrent(try XCTUnwrap(preparedReceipt)))
            // Finishing is native and idempotent; it cannot keep advertising
            // the synchronous request after the platform releases its scope.
            fixture.runtime.finishLazyListUIARequest(request)
            XCTAssertFalse(fixture.runtime.isResolvedLazyListUIARequestCurrent(request))
            fixture.runtime.finishLazyListUIARequest(request)
            XCTAssertTrue(fixture.runtime.hasCurrentAccessibilityPrepaint)
            _ = try settledReceipt(in: fixture.runtime)
        }

        XCTAssertGreaterThan(fixture.runtime.lastLazyListConsumedElements, 0)
        XCTAssertLessThanOrEqual(fixture.runtime.lastLazyListConsumedElements, 32)
        XCTAssertLessThanOrEqual(fixture.runtime.lastLazyListConsumedRounds, 16)
        XCTAssertEqual(fixture.runtime.lastLazyListWorkCompletion, .complete)
    }

    func testAlreadyVisibleTargetReturnsWithFreshSettledLayout() async throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        let original = try XCTUnwrap(fixture.probe.rows[0]?.first)
        let calls = fixture.probe.factories

        try withRequest(in: fixture, id: 0) { request, _ in
            let prepared = try settledReceipt(in: fixture.runtime)
            let roots = try XCTUnwrap(fixture.runtime.resolveLazyListUIARequest(request))

            try assertResolved(roots, for: request, in: fixture, id: 0)
            XCTAssertTrue(roots.first === original)
            XCTAssertEqual(fixture.scroll.scrollOffset, 0)
            XCTAssertEqual(fixture.scroll.resolvedScrollOffset, 0)
            XCTAssertEqual(fixture.probe.factories, calls)
            XCTAssertFalse(fixture.runtime.isLayoutSettlementReceiptCurrent(prepared))
        }
    }

    func testMultipleActualLeavesKeepTheirOrderAndMeasuredSizes() async throws {
        let fixture = try makeFixture(heights: [300: [7, 13]])
        defer { fixture.close() }

        try withRequest(in: fixture) { request, _ in
            let roots = try XCTUnwrap(fixture.runtime.resolveLazyListUIARequest(request))

            try assertResolved(roots, for: request, in: fixture, id: 300)
            XCTAssertEqual(roots.map(\.resolvedFrame.height), [7, 13])
            XCTAssertEqual(roots.map(\.accessibilityIdentifier), ["uia.row.300.0", "uia.row.300.1"])
            XCTAssertEqual(roots[1].resolvedFrame.minY, roots[0].resolvedFrame.maxY)
            XCTAssertEqual(request.item.knownLeafCount, 2)
            XCTAssertEqual(fixture.probe.factories.filter { $0 == 300 }.count, 1)
        }
    }

    func testOversizedTargetUsesItsActualHeightAndRemainsPartiallyVisible() async throws {
        let fixture = try makeFixture(heights: [300: [180]])
        defer { fixture.close() }

        try withRequest(in: fixture) { request, _ in
            let roots = try XCTUnwrap(fixture.runtime.resolveLazyListUIARequest(request))

            try assertResolved(roots, for: request, in: fixture, id: 300)
            let target = try XCTUnwrap(roots.first)
            let visible = try XCTUnwrap(
                fixture.runtime.currentPrepaintState.interactions.first { $0.node === target })
            XCTAssertEqual(target.resolvedFrame.height, 180)
            XCTAssertEqual(visible.visibleFrame.height, 60, accuracy: 0.001)
            XCTAssertLessThan(visible.visibleFrame.height, target.resolvedFrame.height)
            XCTAssertEqual(fixture.probe.factories.filter { $0 == 300 }.count, 1)
        }
    }

    func testEmptyTargetCannotBecomeAVisibleSuccessfulRequest() async throws {
        let fixture = try makeFixture(heights: [300: []])
        defer { fixture.close() }

        try withRequest(in: fixture) { request, _ in
            XCTAssertNil(fixture.runtime.resolveLazyListUIARequest(request))
            XCTAssertFalse(fixture.runtime.isResolvedLazyListUIARequestCurrent(request))
            XCTAssertEqual(fixture.probe.factories.filter { $0 == 300 }.count, 1)
            XCTAssertEqual(fixture.probe.rows[300]?.count, 0)
            XCTAssertEqual(request.item.knownLeafCount, 0)
            XCTAssertEqual(fixture.scroll.scrollOffset, 0)
            XCTAssertFalse(fixture.list.children.contains { $0.dynamicContentIndex == 300 })
        }
    }

    func testInitialOneElementOneRoundExhaustionNeverBuildsTheFarTarget() async throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        let witness = try fixture.target(300)
        let calls = fixture.probe.factories.count
        fixture.scroll.scrollOffset = 200
        XCTAssertTrue(fixture.runtime.configureLazyListResolutionBudget(elementLimit: 1, roundLimit: 1))
        let mutation = try XCTUnwrap(fixture.runtime.beginAccessibilityMutation())
        defer { fixture.runtime.endAccessibilityMutation(mutation) }

        fixture.runtime.withLazyListResolutionBudget {
            let request = fixture.runtime.prepareLazyListUIARequest(
                token: witness.token, in: witness, during: mutation)
            XCTAssertNil(request)
            if let request { fixture.runtime.finishLazyListUIARequest(request) }
        }

        XCTAssertEqual(fixture.probe.factories.count - calls, 1)
        XCTAssertFalse(fixture.probe.factories.contains(300))
        XCTAssertEqual(fixture.scroll.scrollOffset, 200)
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedElements, 1)
        XCTAssertEqual(fixture.runtime.lastLazyListConsumedRounds, 1)
        XCTAssertEqual(fixture.runtime.lastLazyListWorkCompletion, .budgetExhausted)
    }

    func testGenericPreparationOnlyConstructsTheOrdinaryViewport() async throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        let witness = try fixture.target(300)
        let calls = fixture.probe.factories.count
        fixture.scroll.scrollOffset = 200
        let mutation = try XCTUnwrap(fixture.runtime.beginAccessibilityMutation())
        defer { fixture.runtime.endAccessibilityMutation(mutation) }

        let item = fixture.runtime.withLazyListResolutionBudget {
            fixture.runtime.prepareLazyListAccessibilityTarget(
                token: witness.token, in: witness, during: mutation)
        }

        let prepared = try XCTUnwrap(item)
        XCTAssertEqual(prepared.token, witness.token)
        XCTAssertTrue(fixture.runtime.isLazyListAccessibilityItemCurrent(prepared))
        XCTAssertGreaterThan(fixture.probe.factories.count, calls)
        XCTAssertFalse(fixture.probe.factories.contains(300))
        XCTAssertNil(fixture.runtime.realizedLazyListAccessibilityNodes(for: prepared))
        XCTAssertEqual(fixture.scroll.scrollOffset, 200)
        _ = try settledReceipt(in: fixture.runtime)
    }

    func testSameKeysInANewSourceGenerationCannotContinueThePreparedRequest() async throws {
        let fixture = try makeFixture()
        defer { fixture.close() }

        try withRequest(in: fixture) { request, _ in
            let calls = fixture.probe.factories
            XCTAssertTrue(fixture.replaceValues(Array(0..<1000)))
            XCTAssertEqual(fixture.source.token(for: .init(300)), request.item.token)

            XCTAssertNil(fixture.runtime.resolveLazyListUIARequest(request))
            XCTAssertFalse(fixture.runtime.isResolvedLazyListUIARequestCurrent(request))
            XCTAssertEqual(fixture.probe.factories, calls)
            XCTAssertEqual(fixture.scroll.scrollOffset, 0)
        }
    }

    func testRemovalAndSameKeyReinsertionCannotReviveTheOriginalToken() async throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        let original = try fixture.target(300)
        XCTAssertTrue(fixture.replaceValues(Array(0..<1000).filter { $0 != 300 }))
        XCTAssertTrue(fixture.replaceValues(Array(0..<1000)))
        XCTAssertNotNil(fixture.runtime.resolvedLayoutFrame(of: fixture.scroll))
        _ = try settledReceipt(in: fixture.runtime)
        let current = try fixture.target(300)
        XCTAssertNotEqual(current.token, original.token)
        XCTAssertFalse(fixture.runtime.isLazyListAccessibilityTokenCurrent(original.token, in: current))
        let calls = fixture.probe.factories
        let mutation = try XCTUnwrap(fixture.runtime.beginAccessibilityMutation())
        defer { fixture.runtime.endAccessibilityMutation(mutation) }

        fixture.runtime.withLazyListResolutionBudget {
            let request = fixture.runtime.prepareLazyListUIARequest(
                token: original.token, in: current, during: mutation)
            XCTAssertNil(request)
            if let request { fixture.runtime.finishLazyListUIARequest(request) }
        }

        XCTAssertEqual(fixture.probe.factories, calls)
        XCTAssertFalse(fixture.probe.factories.contains(300))
        XCTAssertEqual(fixture.scroll.scrollOffset, 0)
    }

    func testAttemptedSourceReplacementInsideTheTargetFactoryStopsFurtherConstruction() async throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        fixture.probe.onFactory = { [weak fixture] id in
            guard let fixture, id == 300, fixture.probe.interventions == 0 else { return }
            fixture.probe.interventions += 1
            XCTAssertFalse(
                fixture.replaceValues(Array(0..<1000)),
                "A reentrant replacement is refused after revoking the original generation")
        }
        let calls = fixture.probe.factories.count

        try withRequest(in: fixture) { request, _ in
            XCTAssertNil(fixture.runtime.resolveLazyListUIARequest(request))
            XCTAssertFalse(fixture.runtime.isResolvedLazyListUIARequestCurrent(request))
            XCTAssertEqual(fixture.probe.interventions, 1)
            XCTAssertEqual(Array(fixture.probe.factories.dropFirst(calls)), [300])
            XCTAssertEqual(fixture.scroll.scrollOffset, 0)
        }
    }

    func testFailedRequestDoesNotClearACompetingLogicalDemand() async throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        let competingItem = try fixture.target(400)
        let owner = RetainedLazyListLogicalRealizationOwner()
        let competing = try XCTUnwrap(
            fixture.adapter.beginLogicalRealization(of: competingItem.token, owner: owner))
        defer { fixture.adapter.endLogicalRealization(competing) }

        try withRequest(in: fixture) { request, _ in
            XCTAssertTrue(competing.isActive)
            XCTAssertNil(fixture.runtime.resolveLazyListUIARequest(request))
            fixture.runtime.finishLazyListUIARequest(request)

            XCTAssertTrue(competing.isActive)
            XCTAssertFalse(fixture.probe.factories.contains(300))
            let otherOwner = RetainedLazyListLogicalRealizationOwner()
            XCTAssertNil(fixture.adapter.beginLogicalRealization(of: request.item.token, owner: otherOwner))
            XCTAssertTrue(competing.isActive, "Finishing the failed request cannot release another owner's lease")
        }
    }

    func testTargetFactoryFocusChangeRevokesTheOriginalInputProof() async throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        let first = try XCTUnwrap(fixture.probe.rows[0]?.first)
        first.isFocusable = true
        first.isFocusEnabled = true
        fixture.probe.onFactory = { [weak fixture, weak first] id in
            guard let fixture, let first, id == 300, fixture.probe.interventions == 0 else { return }
            fixture.probe.interventions += 1
            fixture.runtime.requestFocus(first)
        }
        let calls = fixture.probe.factories.count

        try withRequest(in: fixture) { request, _ in
            XCTAssertNil(fixture.runtime.resolveLazyListUIARequest(request))
            XCTAssertFalse(fixture.runtime.isResolvedLazyListUIARequestCurrent(request))
            XCTAssertEqual(fixture.probe.interventions, 1)
            XCTAssertTrue(fixture.runtime.focusedNode === first)
            XCTAssertEqual(Array(fixture.probe.factories.dropFirst(calls)), [300])
            XCTAssertEqual(fixture.scroll.scrollOffset, 0)
        }
    }

    func testEqualAuthoredOffsetInTheTargetFactoryIsStillANewerIntent() async throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        fixture.probe.onFactory = { [weak fixture] id in
            guard let fixture, id == 300, fixture.probe.interventions == 0 else { return }
            fixture.probe.interventions += 1
            let offset = fixture.scroll.scrollOffset
            fixture.scroll.scrollOffset = offset
        }
        let calls = fixture.probe.factories.count

        try withRequest(in: fixture) { request, _ in
            XCTAssertNil(fixture.runtime.resolveLazyListUIARequest(request))
            XCTAssertFalse(fixture.runtime.isResolvedLazyListUIARequestCurrent(request))
            XCTAssertEqual(fixture.probe.interventions, 1)
            XCTAssertEqual(Array(fixture.probe.factories.dropFirst(calls)), [300])
            XCTAssertEqual(fixture.scroll.scrollOffset, 0)
        }
    }

    func testTargetFactoryGeometryChangedThenRestoredCannotAcquireANewProof() async throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        let originalFrame = fixture.scroll.frame
        fixture.probe.onFactory = { [weak fixture] id in
            guard let fixture, id == 300, fixture.probe.interventions == 0 else { return }
            fixture.probe.interventions += 1
            fixture.scroll.frame = Rect(x: 0, y: 0, width: originalFrame.width + 1, height: originalFrame.height)
            fixture.scroll.frame = originalFrame
        }
        let calls = fixture.probe.factories.count

        try withRequest(in: fixture) { request, _ in
            XCTAssertNil(fixture.runtime.resolveLazyListUIARequest(request))
            XCTAssertFalse(fixture.runtime.isResolvedLazyListUIARequestCurrent(request))
            XCTAssertEqual(fixture.probe.interventions, 1)
            XCTAssertEqual(fixture.scroll.frame, originalFrame)
            XCTAssertEqual(Array(fixture.probe.factories.dropFirst(calls)), [300])
            XCTAssertEqual(fixture.scroll.scrollOffset, 0)
        }
    }

    func testQueuedNoOpAfterLayoutCannotGrantATargetProofFromItsLaterPass() async throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        fixture.probe.onFactory = { [weak fixture] id in
            guard let fixture, id == 300, fixture.probe.interventions == 0 else { return }
            fixture.probe.interventions += 1
            // Pending work prevents the first target proof from being issued.
            // Its epilogue cannot grant one using the later no-op pass instead.
            fixture.runtime.scheduleAfterLayout(key: "uia-continuation-no-op") { [weak fixture] in
                guard let fixture else { return }
                fixture.probe.callbackCalls += 1
                fixture.probe.passAtCallback = fixture.runtime.layoutPassID
                // Deliberately leave the UI unchanged. The ordinary epilogue
                // must still run its new pass without granting a fresh proof.
            }
        }

        try withRequest(in: fixture) { request, _ in
            XCTAssertNil(fixture.runtime.resolveLazyListUIARequest(request))
            XCTAssertFalse(fixture.runtime.isResolvedLazyListUIARequestCurrent(request))
            XCTAssertEqual(fixture.probe.interventions, 1)
            XCTAssertEqual(fixture.probe.callbackCalls, 1)
            XCTAssertGreaterThan(fixture.runtime.layoutPassID, try XCTUnwrap(fixture.probe.passAtCallback))
            XCTAssertEqual(fixture.scroll.scrollOffset, 0)
        }
    }

    func testAuthoredScrollChangedThenRestoredDuringFinalQueryRevokesTheOwnedMarker() async throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        fixture.list.onLayout = { [weak fixture] _ in
            guard let fixture, fixture.scroll.scrollOffset > 0, fixture.probe.interventions == 0 else { return }
            fixture.probe.interventions += 1
            let offset = fixture.scroll.scrollOffset
            fixture.probe.ownedOffset = offset
            fixture.scroll.scrollOffset = offset + 1
            fixture.scroll.scrollOffset = offset
        }

        try withRequest(in: fixture) { request, _ in
            let prepared = try settledReceipt(in: fixture.runtime)

            XCTAssertNil(fixture.runtime.resolveLazyListUIARequest(request))
            XCTAssertFalse(fixture.runtime.isResolvedLazyListUIARequestCurrent(request))
            XCTAssertEqual(
                fixture.probe.interventions, 1, "This test must reach the query after the owned offset write")
            let ownedOffset = try XCTUnwrap(fixture.probe.ownedOffset)
            XCTAssertGreaterThan(ownedOffset, 0)
            XCTAssertEqual(fixture.scroll.scrollOffset, ownedOffset)
            XCTAssertFalse(fixture.runtime.isLayoutSettlementReceiptCurrent(prepared))
        }
    }

    func testDetachedAndReattachedOriginalContainerCannotContinue() async throws {
        let fixture = try makeFixture()
        defer { fixture.close() }

        try withRequest(in: fixture) { request, mutation in
            let original = try XCTUnwrap(fixture.runtime.accessibilityTarget(for: fixture.list))
            let calls = fixture.probe.factories
            fixture.scroll.setChildren([])
            fixture.scroll.setChildren([fixture.list])
            XCTAssertTrue(fixture.list.parent === fixture.scroll)
            XCTAssertTrue(fixture.scroll.children.first === fixture.list)
            XCTAssertFalse(fixture.runtime.isAccessibilityTargetCurrent(original, during: mutation))

            XCTAssertNil(fixture.runtime.resolveLazyListUIARequest(request))
            XCTAssertFalse(fixture.runtime.isResolvedLazyListUIARequestCurrent(request))
            XCTAssertEqual(fixture.probe.factories, calls)
            XCTAssertEqual(fixture.scroll.scrollOffset, 0)
        }
    }

    func testDetachedAndReattachedActualTargetCannotBorrowItsPreviousAttachment() async throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        fixture.list.onLayout = { [weak fixture] _ in
            guard let fixture, fixture.scroll.scrollOffset > 0, fixture.probe.interventions == 0,
                let target = fixture.probe.rows[300]?.first
            else { return }
            fixture.probe.interventions += 1
            fixture.probe.borrowedTarget = fixture.runtime.accessibilityTarget(for: target)
            let children = fixture.list.children
            fixture.list.setChildren([])
            fixture.list.setChildren(children)
            fixture.probe.restoredOriginalChildren =
                target.parent === fixture.list && fixture.list.children.contains { $0 === target }
        }

        try withRequest(in: fixture) { request, mutation in
            XCTAssertNil(fixture.runtime.resolveLazyListUIARequest(request))
            XCTAssertFalse(fixture.runtime.isResolvedLazyListUIARequestCurrent(request))
            XCTAssertEqual(fixture.probe.interventions, 1)
            XCTAssertTrue(fixture.probe.restoredOriginalChildren)
            let original = try XCTUnwrap(fixture.probe.borrowedTarget)
            XCTAssertFalse(fixture.runtime.isAccessibilityTargetCurrent(original, during: mutation))
        }
    }

    func testLaterOrdinaryQueryCannotRefreshAnAlreadyResolvedRequest() async throws {
        let fixture = try makeFixture()
        defer { fixture.close() }

        try withRequest(in: fixture) { request, _ in
            let roots = try XCTUnwrap(fixture.runtime.resolveLazyListUIARequest(request))
            try assertResolved(roots, for: request, in: fixture, id: 300)
            let target = try XCTUnwrap(roots.first)
            let frame = target.resolvedFrame
            let pass = fixture.runtime.layoutPassID
            let receipt = try settledReceipt(in: fixture.runtime)

            XCTAssertNotNil(fixture.runtime.resolvedLayoutFrame(of: fixture.scroll))

            XCTAssertGreaterThan(fixture.runtime.layoutPassID, pass)
            XCTAssertEqual(target.resolvedFrame, frame)
            XCTAssertTrue(target.parent === fixture.list)
            XCTAssertTrue(fixture.runtime.hasCurrentAccessibilityPrepaint)
            _ = try settledReceipt(in: fixture.runtime)
            XCTAssertFalse(fixture.runtime.isLayoutSettlementReceiptCurrent(receipt))
            XCTAssertFalse(fixture.runtime.isResolvedLazyListUIARequestCurrent(request))
        }
    }

    func testTargetIdentityAssignmentRevokesWithoutALayoutOrMutationRevisionChange() async throws {
        for changesIdentityValue in [false, true] {
            let fixture = try makeFixture()
            defer { fixture.close() }

            try withRequest(in: fixture) { request, mutation in
                let roots = try XCTUnwrap(fixture.runtime.resolveLazyListUIARequest(request))
                try assertResolved(roots, for: request, in: fixture, id: 300)
                let target = try XCTUnwrap(roots.first)
                let original = try XCTUnwrap(target.retainedViewIdentity)
                let frame = target.resolvedFrame
                let pass = fixture.runtime.layoutPassID
                let mutationRevision = mutation.revision
                if changesIdentityValue { target.retainedViewIdentity = original.appending(.slot(99)) }

                target.retainedViewIdentity = original

                XCTAssertEqual(target.retainedViewIdentity, original)
                XCTAssertEqual(target.resolvedFrame, frame)
                XCTAssertEqual(fixture.runtime.layoutPassID, pass)
                XCTAssertEqual(mutation.revision, mutationRevision)
                XCTAssertTrue(fixture.runtime.hasCurrentAccessibilityPrepaint)
                XCTAssertFalse(
                    fixture.runtime.isResolvedLazyListUIARequestCurrent(request),
                    "A same-value identity assignment also revokes the original physical row proof")
            }
        }
    }

    func testPendingReaderRebuildsOnceDuringTheOriginalTypedPreparation() async throws {
        let geometry = UIAContinuationReaderProbe()
        let reader = geometry.node(builtSize: Size(width: 120, height: 20))
        let fixture = try makeFixture(beforeList: [reader])
        defer { fixture.close() }
        let factories = fixture.probe.factories
        let previousReceipt = try settledReceipt(in: fixture.runtime)
        XCTAssertEqual(geometry.calls, 0)

        try withUnpreparedRequest(in: fixture) { witness, mutation in
            reader.geometryReaderBuiltSize = Size(width: 120, height: 10)
            let request = try XCTUnwrap(
                fixture.runtime.prepareLazyListUIARequest(token: witness.token, in: witness, during: mutation))
            defer { fixture.runtime.finishLazyListUIARequest(request) }

            XCTAssertEqual(geometry.calls, 1)
            XCTAssertEqual(reader.geometryReaderBuiltSize, Size(width: 120, height: 20))
            XCTAssertEqual(reader.resolvedFrame.size, Size(width: 120, height: 20))
            XCTAssertNotNil(reader.geometryReaderBuild)
            XCTAssertEqual(request.item.token, witness.token)
            XCTAssertTrue(fixture.runtime.isLazyListAccessibilityItemCurrent(request.item))
            XCTAssertEqual(fixture.probe.factories, factories)
            XCTAssertFalse(fixture.probe.factories.contains(300))
            XCTAssertEqual(fixture.scroll.scrollOffset, 0)
            XCTAssertTrue(fixture.runtime.hasCurrentAccessibilityPrepaint)
            XCTAssertFalse(fixture.runtime.isLayoutSettlementReceiptCurrent(previousReceipt))
            _ = try settledReceipt(in: fixture.runtime)
        }

        XCTAssertEqual(geometry.calls, 1)
        XCTAssertFalse(fixture.runtime.retainedBuildCoordinator.isBuilding)
        XCTAssertLessThanOrEqual(fixture.runtime.lastLazyListConsumedElements, 32)
        XCTAssertLessThanOrEqual(fixture.runtime.lastLazyListConsumedRounds, 16)
    }

    func testFarFactoryReaderKeepsTheOriginalRequestThroughRawAndLeasedRebuilds() async throws {
        for leased in [false, true] {
            let fixture = try makeFixture()
            let geometry = UIAContinuationReaderProbe()
            let lease = UIAContinuationReaderLease()
            defer { fixture.close() }
            fixture.probe.configureRows = { id, rows in
                guard id == 300, let row = rows.first else { return }
                if leased { row.retainedSubtreeBuildLease = lease }
                geometry.install(on: row, builtSize: Size(width: 120, height: 10))
            }

            try withRequest(in: fixture) { request, _ in
                XCTAssertEqual(geometry.calls, 0)
                XCTAssertFalse(fixture.probe.factories.contains(300))
                let originalToken = request.item.token
                let roots = try XCTUnwrap(fixture.runtime.resolveLazyListUIARequest(request))

                try assertResolved(roots, for: request, in: fixture, id: 300)
                XCTAssertEqual(request.item.token, originalToken)
                XCTAssertEqual(geometry.calls, 1)
                XCTAssertEqual(roots.first?.geometryReaderBuiltSize, Size(width: 120, height: 20))
                XCTAssertEqual(fixture.probe.factories.filter { $0 == 300 }.count, 1)
                if leased {
                    XCTAssertEqual(lease.commits, 1)
                    XCTAssertEqual(lease.abandons, 0)
                    XCTAssertEqual(lease.finishes, 1)
                }
                fixture.runtime.finishLazyListUIARequest(request)
                XCTAssertTrue(roots.first?.retainedLazyListRuntime === fixture.runtime)
                XCTAssertTrue(roots.first?.parent === fixture.list)
                XCTAssertNotNil(roots.first?.geometryReaderBuild)
                XCTAssertFalse(fixture.runtime.isResolvedLazyListUIARequestCurrent(request))
            }

            XCTAssertFalse(fixture.runtime.retainedBuildCoordinator.isBuilding)
            XCTAssertLessThanOrEqual(fixture.runtime.lastLazyListConsumedElements, 32)
            XCTAssertLessThanOrEqual(fixture.runtime.lastLazyListConsumedRounds, 16)
        }
    }

    func testInitialReaderBodyEndingTheMutationStopsAdoptionAndTheNextReader() async throws {
        let geometry = UIAContinuationReaderProbe()
        let laterGeometry = UIAContinuationReaderProbe()
        let reader = geometry.node(builtSize: Size(width: 120, height: 20))
        let later = laterGeometry.node(builtSize: Size(width: 120, height: 20))
        let fixture = try makeFixture(beforeList: [reader, later])
        defer { fixture.close() }
        let factories = fixture.probe.factories

        try withUnpreparedRequest(in: fixture) { witness, mutation in
            reader.geometryReaderBuiltSize = Size(width: 120, height: 10)
            later.geometryReaderBuiltSize = Size(width: 120, height: 10)
            geometry.onBuild = { [weak fixture] _, _ in
                fixture?.runtime.endAccessibilityMutation(mutation)
            }
            let request = fixture.runtime.prepareLazyListUIARequest(
                token: witness.token, in: witness, during: mutation)
            if let request { fixture.runtime.finishLazyListUIARequest(request) }

            XCTAssertNil(request)
            XCTAssertEqual(geometry.calls, 1)
            XCTAssertEqual(laterGeometry.calls, 0, "An ended query cannot invoke another pending reader")
            XCTAssertEqual(reader.geometryReaderBuiltSize, Size(width: 120, height: 10))
            XCTAssertEqual(fixture.probe.factories, factories)
            XCTAssertEqual(fixture.scroll.scrollOffset, 0)
            XCTAssertFalse(fixture.runtime.retainedBuildCoordinator.isBuilding)
        }
    }

    func testInitialReaderListGeometryABACannotRefreshAuthorityForTheNextReader() async throws {
        let geometry = UIAContinuationReaderProbe()
        let laterGeometry = UIAContinuationReaderProbe()
        let reader = geometry.node(builtSize: Size(width: 120, height: 20))
        let later = laterGeometry.node(builtSize: Size(width: 120, height: 20))
        let fixture = try makeFixture(beforeList: [reader, later])
        defer { fixture.close() }
        let factories = fixture.probe.factories
        let original = fixture.list.preferredSize

        try withUnpreparedRequest(in: fixture) { witness, mutation in
            reader.geometryReaderBuiltSize = Size(width: 120, height: 10)
            later.geometryReaderBuiltSize = Size(width: 120, height: 10)
            geometry.onBuild = { [weak fixture] _, _ in
                fixture?.list.preferredSize = Size(width: 121, height: 21)
                fixture?.list.preferredSize = original
            }
            let request = fixture.runtime.prepareLazyListUIARequest(
                token: witness.token, in: witness, during: mutation)
            if let request { fixture.runtime.finishLazyListUIARequest(request) }

            XCTAssertNil(request)
            XCTAssertEqual(geometry.calls, 1)
            XCTAssertEqual(laterGeometry.calls, 0, "The next reader must inherit the original query's revocation")
            XCTAssertEqual(fixture.list.preferredSize, original)
            XCTAssertEqual(reader.geometryReaderBuiltSize, Size(width: 120, height: 10))
            XCTAssertEqual(fixture.probe.factories, factories)
            XCTAssertEqual(fixture.scroll.scrollOffset, 0)
        }
    }

    func testReaderLeaseCalloutsCannotContinueAfterEndingTheOriginalMutation() async throws {
        for point in UIAContinuationReaderCallout.allCases {
            let geometry = UIAContinuationReaderProbe()
            let reader = geometry.node(builtSize: Size(width: 120, height: 20))
            let lease = UIAContinuationReaderLease()
            reader.retainedSubtreeBuildLease = lease
            geometry.install(on: reader, builtSize: Size(width: 120, height: 20))
            let fixture = try makeFixture(beforeList: [reader])
            defer { fixture.close() }
            let factories = fixture.probe.factories

            try withUnpreparedRequest(in: fixture) { witness, mutation in
                reader.geometryReaderBuiltSize = Size(width: 120, height: 10)
                lease.onCall = { [weak fixture] current in
                    if current == point { fixture?.runtime.endAccessibilityMutation(mutation) }
                }
                let request = fixture.runtime.prepareLazyListUIARequest(
                    token: witness.token, in: witness, during: mutation)
                if let request { fixture.runtime.finishLazyListUIARequest(request) }

                XCTAssertNil(request, "\(point)")
                XCTAssertEqual(lease.calls.last, point, "No protocol call may follow the revoked \(point)")
                XCTAssertEqual(geometry.calls, point == .willAdopt ? 1 : 0, "\(point)")
                XCTAssertEqual(reader.geometryReaderBuiltSize, Size(width: 120, height: 10))
                XCTAssertEqual(lease.commits, 0)
                XCTAssertEqual(lease.abandons, point == .canBuild ? 0 : 1)
                XCTAssertEqual(lease.finishes, point == .canBuild ? 0 : 1)
                XCTAssertEqual(fixture.probe.factories, factories)
                XCTAssertEqual(fixture.scroll.scrollOffset, 0)
                XCTAssertFalse(fixture.runtime.retainedBuildCoordinator.isBuilding)
            }
        }
    }

    func testReaderFalseAndNilLeaseResultsStillRevokeBeforeTheNextReader() async throws {
        for point in UIAContinuationReaderCallout.allCases {
            let geometry = UIAContinuationReaderProbe()
            let laterGeometry = UIAContinuationReaderProbe()
            let reader = geometry.node(builtSize: Size(width: 120, height: 20))
            let later = laterGeometry.node(builtSize: Size(width: 120, height: 20))
            let identity = RetainedViewIdentity(segments: [.role(.content), .slot(54)])
            reader.retainedViewIdentity = identity
            let lease = UIAContinuationReaderLease()
            reader.retainedSubtreeBuildLease = lease
            geometry.install(on: reader, builtSize: Size(width: 120, height: 20))
            let fixture = try makeFixture(beforeList: [reader, later])
            defer { fixture.close() }
            let factories = fixture.probe.factories
            var revocations = 0

            try withUnpreparedRequest(in: fixture) { witness, mutation in
                reader.geometryReaderBuiltSize = Size(width: 120, height: 10)
                later.geometryReaderBuiltSize = Size(width: 120, height: 10)
                lease.refusedCallout = point
                lease.onCall = { [weak reader] current in
                    if current == point {
                        revocations += 1
                        reader?.retainedViewIdentity = identity
                    }
                }
                let request = fixture.runtime.prepareLazyListUIARequest(
                    token: witness.token, in: witness, during: mutation)
                if let request { fixture.runtime.finishLazyListUIARequest(request) }

                XCTAssertNil(request, "\(point)")
                XCTAssertEqual(revocations, 1, "\(point)")
                XCTAssertEqual(lease.calls.last, point)
                XCTAssertEqual(geometry.calls, point == .willAdopt ? 1 : 0)
                XCTAssertEqual(laterGeometry.calls, 0, "A false/nil \(point) cannot bypass the revocation audit")
                XCTAssertEqual(reader.geometryReaderBuiltSize, Size(width: 120, height: 10))
                XCTAssertEqual(reader.retainedViewIdentity, identity)
                XCTAssertEqual(lease.commits, 0)
                let hadEpoch = point == .canAdopt || point == .willAdopt
                XCTAssertEqual(lease.abandons, hadEpoch ? 1 : 0)
                XCTAssertEqual(lease.finishes, hadEpoch ? 1 : 0)
                XCTAssertEqual(fixture.probe.factories, factories)
                XCTAssertEqual(fixture.scroll.scrollOffset, 0)
                XCTAssertFalse(fixture.runtime.retainedBuildCoordinator.isBuilding)
            }
        }
    }

    func testReaderRejectedBodyPayloadReleaseRevokesBeforeTheNextReader() async throws {
        for rejectsDuringAdoption in [false, true] {
            let geometry = UIAContinuationReaderProbe()
            let laterGeometry = UIAContinuationReaderProbe()
            let reader = geometry.node(builtSize: Size(width: 120, height: 20))
            let later = laterGeometry.node(builtSize: Size(width: 120, height: 20))
            let identity = RetainedViewIdentity(segments: [.role(.content), .slot(55)])
            reader.retainedViewIdentity = identity
            let lease = UIAContinuationReaderLease()
            if rejectsDuringAdoption { reader.retainedSubtreeBuildLease = lease }
            geometry.install(on: reader, builtSize: Size(width: 120, height: 20))
            let fixture = try makeFixture(beforeList: [reader, later])
            defer { fixture.close() }
            let factories = fixture.probe.factories
            var releases = 0

            try withUnpreparedRequest(in: fixture) { witness, mutation in
                reader.geometryReaderBuiltSize = Size(width: 120, height: 10)
                later.geometryReaderBuiltSize = Size(width: 120, height: 10)
                geometry.rejectsResult = !rejectsDuringAdoption
                if rejectsDuringAdoption { lease.refusedCallout = .willAdopt }
                geometry.onBuild = { [self] _, candidate in
                    installReaderBodyRelease(on: candidate) { [weak reader] in
                        releases += 1
                        reader?.retainedViewIdentity = identity
                    }
                }
                let request = fixture.runtime.prepareLazyListUIARequest(
                    token: witness.token, in: witness, during: mutation)
                if let request { fixture.runtime.finishLazyListUIARequest(request) }

                XCTAssertNil(request)
                XCTAssertEqual(geometry.calls, 1)
                XCTAssertEqual(releases, 1, "The discarded candidate must release its own body payload")
                XCTAssertEqual(laterGeometry.calls, 0, "Rejected output still owes an audit after payload release")
                XCTAssertEqual(reader.retainedViewIdentity, identity)
                XCTAssertEqual(reader.geometryReaderBuiltSize, Size(width: 120, height: 10))
                if rejectsDuringAdoption {
                    // The nonempty body survived until the helper rejected
                    // willAdopt. Its destructor runs as that helper unwinds.
                    XCTAssertEqual(lease.calls.last, .willAdopt)
                    XCTAssertEqual(lease.abandons, 1)
                    XCTAssertEqual(lease.finishes, 1)
                }
                XCTAssertEqual(lease.commits, 0)
                XCTAssertEqual(fixture.probe.factories, factories)
                XCTAssertEqual(fixture.scroll.scrollOffset, 0)
                XCTAssertFalse(fixture.runtime.retainedBuildCoordinator.isBuilding)
            }
        }
    }

    func testReaderCanBuildBodyReplacementDoesNotInvokeTheCapturedOldBody() async throws {
        let geometry = UIAContinuationReaderProbe()
        let replacement = UIAContinuationReaderProbe()
        let reader = geometry.node(builtSize: Size(width: 120, height: 20))
        let lease = UIAContinuationReaderLease()
        reader.retainedSubtreeBuildLease = lease
        geometry.install(on: reader, builtSize: Size(width: 120, height: 20))
        let fixture = try makeFixture(beforeList: [reader])
        defer { fixture.close() }
        let factories = fixture.probe.factories

        try withUnpreparedRequest(in: fixture) { witness, mutation in
            reader.geometryReaderBuiltSize = Size(width: 120, height: 10)
            lease.onCall = { [weak reader] point in
                guard point == .canBuild, let reader else { return }
                replacement.install(on: reader, builtSize: Size(width: 120, height: 10))
            }
            let request = fixture.runtime.prepareLazyListUIARequest(
                token: witness.token, in: witness, during: mutation)
            if let request { fixture.runtime.finishLazyListUIARequest(request) }

            XCTAssertNil(request)
            XCTAssertEqual(geometry.calls, 0, "The old body was captured before canBuild replaced it")
            XCTAssertEqual(replacement.calls, 0, "The same query cannot acquire the replacement body")
            XCTAssertEqual(lease.calls, [.canBuild])
            XCTAssertNotNil(reader.geometryReaderBuild)
            XCTAssertEqual(reader.geometryReaderBuiltSize, Size(width: 120, height: 10))
            XCTAssertEqual(fixture.probe.factories, factories)
            XCTAssertEqual(fixture.scroll.scrollOffset, 0)
        }
    }

    func testReaderOwnGeometryABABlocksStaleSlotAdoptionBeforeAndAfterTheBody() async throws {
        for duringBody in [false, true] {
            let geometry = UIAContinuationReaderProbe()
            let reader = geometry.node(builtSize: Size(width: 120, height: 20))
            let lease = UIAContinuationReaderLease()
            reader.retainedSubtreeBuildLease = lease
            geometry.install(on: reader, builtSize: Size(width: 120, height: 20))
            let fixture = try makeFixture(beforeList: [reader])
            defer { fixture.close() }
            let original = reader.preferredSize
            let factories = fixture.probe.factories
            let changeAndRestore = { @MainActor [weak reader] in
                reader?.preferredSize = Size(width: 121, height: 21)
                reader?.preferredSize = original
            }

            try withUnpreparedRequest(in: fixture) { witness, mutation in
                reader.geometryReaderBuiltSize = Size(width: 120, height: 10)
                if duringBody {
                    geometry.onBuild = { _, _ in changeAndRestore() }
                } else {
                    lease.onCall = { point in if point == .canBuild { changeAndRestore() } }
                }
                let request = fixture.runtime.prepareLazyListUIARequest(
                    token: witness.token, in: witness, during: mutation)
                if let request { fixture.runtime.finishLazyListUIARequest(request) }

                XCTAssertNil(request)
                XCTAssertEqual(geometry.calls, duringBody ? 1 : 0)
                XCTAssertEqual(reader.preferredSize, original)
                XCTAssertEqual(reader.geometryReaderBuiltSize, Size(width: 120, height: 10))
                XCTAssertFalse(lease.calls.contains(.willAdopt))
                XCTAssertEqual(lease.commits, 0)
                XCTAssertEqual(fixture.probe.factories, factories)
                XCTAssertEqual(fixture.scroll.scrollOffset, 0)
                XCTAssertFalse(fixture.runtime.retainedBuildCoordinator.isBuilding)
            }
        }
    }

    func testReaderBodyIdentityABACannotAdoptOntoItsRestoredNode() async throws {
        let geometry = UIAContinuationReaderProbe()
        let reader = geometry.node(builtSize: Size(width: 120, height: 20))
        let original = RetainedViewIdentity(segments: [.role(.content), .slot(51)])
        reader.retainedViewIdentity = original
        let fixture = try makeFixture(beforeList: [reader])
        defer { fixture.close() }

        try withUnpreparedRequest(in: fixture) { witness, mutation in
            reader.geometryReaderBuiltSize = Size(width: 120, height: 10)
            geometry.onBuild = { [weak reader] _, _ in
                reader?.retainedViewIdentity = original.appending(.slot(1))
                reader?.retainedViewIdentity = original
            }
            let request = fixture.runtime.prepareLazyListUIARequest(
                token: witness.token, in: witness, during: mutation)
            if let request { fixture.runtime.finishLazyListUIARequest(request) }

            XCTAssertNil(request)
            XCTAssertEqual(geometry.calls, 1)
            XCTAssertEqual(reader.retainedViewIdentity, original)
            XCTAssertEqual(reader.geometryReaderBuiltSize, Size(width: 120, height: 10))
            XCTAssertFalse(fixture.probe.factories.contains(300))
            XCTAssertEqual(fixture.scroll.scrollOffset, 0)
        }
    }

    func testReaderBodyFocusAndScrollChangesPreserveNewIntentWithoutAdoption() async throws {
        for changesFocus in [false, true] {
            let geometry = UIAContinuationReaderProbe()
            let reader = geometry.node(builtSize: Size(width: 120, height: 20))
            reader.isFocusable = true
            reader.isFocusEnabled = true
            let fixture = try makeFixture(beforeList: [reader])
            defer { fixture.close() }
            let factories = fixture.probe.factories

            try withUnpreparedRequest(in: fixture) { witness, mutation in
                reader.geometryReaderBuiltSize = Size(width: 120, height: 10)
                geometry.onBuild = { [weak fixture, weak reader] _, _ in
                    guard let fixture, let reader else { return }
                    if changesFocus {
                        fixture.runtime.requestFocus(reader)
                    } else {
                        fixture.scroll.scrollOffset = 1
                        fixture.scroll.scrollOffset = 0
                    }
                }
                let request = fixture.runtime.prepareLazyListUIARequest(
                    token: witness.token, in: witness, during: mutation)
                if let request { fixture.runtime.finishLazyListUIARequest(request) }

                XCTAssertNil(request)
                XCTAssertEqual(geometry.calls, 1)
                XCTAssertEqual(reader.geometryReaderBuiltSize, Size(width: 120, height: 10))
                if changesFocus { XCTAssertTrue(fixture.runtime.focusedNode === reader) }
                XCTAssertEqual(fixture.scroll.scrollOffset, 0)
                XCTAssertEqual(fixture.probe.factories, factories)
            }
        }
    }

    func testFarReaderEndingItsRequestCannotUseTheExpiredAuthorityForAdoption() async throws {
        let fixture = try makeFixture()
        let geometry = UIAContinuationReaderProbe()
        defer { fixture.close() }
        fixture.probe.configureRows = { id, rows in
            if id == 300, let row = rows.first {
                geometry.install(on: row, builtSize: Size(width: 120, height: 10))
            }
        }

        try withRequest(in: fixture) { request, _ in
            geometry.onBuild = { [weak fixture] _, _ in
                fixture?.runtime.finishLazyListUIARequest(request)
            }

            XCTAssertNil(fixture.runtime.resolveLazyListUIARequest(request))
            XCTAssertEqual(geometry.calls, 1)
            XCTAssertEqual(fixture.probe.rows[300]?.first?.geometryReaderBuiltSize, Size(width: 120, height: 10))
            XCTAssertFalse(fixture.runtime.isResolvedLazyListUIARequestCurrent(request))
            XCTAssertEqual(fixture.scroll.scrollOffset, 0)
            XCTAssertEqual(fixture.probe.factories.filter { $0 == 300 }.count, 1)
        }
    }

    func testReaderNestedMutationIsRefusedWithoutReplacingTheOriginalPreparation() async throws {
        let geometry = UIAContinuationReaderProbe()
        let reader = geometry.node(builtSize: Size(width: 120, height: 20))
        let fixture = try makeFixture(beforeList: [reader])
        defer { fixture.close() }
        var competing: RetainedAccessibilityMutation?
        var attempts = 0

        try withUnpreparedRequest(in: fixture) { witness, mutation in
            reader.geometryReaderBuiltSize = Size(width: 120, height: 10)
            geometry.onBuild = { [weak fixture] _, _ in
                guard let fixture else { return }
                attempts += 1
                competing = fixture.runtime.beginAccessibilityMutation()
            }
            defer { if let competing { fixture.runtime.endAccessibilityMutation(competing) } }
            let request = try XCTUnwrap(
                fixture.runtime.prepareLazyListUIARequest(token: witness.token, in: witness, during: mutation))
            defer { fixture.runtime.finishLazyListUIARequest(request) }

            XCTAssertEqual(attempts, 1)
            XCTAssertNil(competing)
            XCTAssertEqual(geometry.calls, 1)
            XCTAssertTrue(fixture.runtime.isAccessibilityMutationCurrent(mutation))
            XCTAssertEqual(request.item.token, witness.token)
            XCTAssertEqual(reader.geometryReaderBuiltSize, Size(width: 120, height: 20))
            XCTAssertFalse(fixture.probe.factories.contains(300))
            XCTAssertEqual(fixture.scroll.scrollOffset, 0)
            _ = try settledReceipt(in: fixture.runtime)
        }
    }

    func testReaderDisplayScaleABACannotAuthorizeTheNextReaderOrFactory() async throws {
        let geometry = UIAContinuationReaderProbe()
        let laterGeometry = UIAContinuationReaderProbe()
        let reader = geometry.node(builtSize: Size(width: 120, height: 20))
        let later = laterGeometry.node(builtSize: Size(width: 120, height: 20))
        let fixture = try makeFixture(beforeList: [reader, later])
        defer { fixture.close() }
        let originalScale = fixture.runtime.displayScale
        let factories = fixture.probe.factories

        try withUnpreparedRequest(in: fixture) { witness, mutation in
            reader.geometryReaderBuiltSize = Size(width: 120, height: 10)
            later.geometryReaderBuiltSize = Size(width: 120, height: 10)
            geometry.onBuild = { [weak fixture] _, _ in
                fixture?.runtime.displayScale = originalScale + 1
                fixture?.runtime.displayScale = originalScale
            }
            let request = fixture.runtime.prepareLazyListUIARequest(
                token: witness.token, in: witness, during: mutation)
            if let request { fixture.runtime.finishLazyListUIARequest(request) }

            XCTAssertNil(request)
            XCTAssertEqual(geometry.calls, 1)
            XCTAssertEqual(laterGeometry.calls, 0)
            XCTAssertEqual(reader.geometryReaderBuiltSize, Size(width: 120, height: 10))
            XCTAssertEqual(fixture.runtime.displayScale, originalScale)
            XCTAssertEqual(fixture.probe.factories, factories)
            XCTAssertEqual(fixture.scroll.scrollOffset, 0)
        }
    }

    func testReaderControllerAttachRevocationStopsReconcileAndLaterMetadata() async throws {
        let geometry = UIAContinuationReaderProbe()
        let reader = geometry.node(builtSize: Size(width: 120, height: 20))
        reader.textSelectability = .enabled
        let fixture = try makeFixture(beforeList: [reader])
        let controller = UIAContinuationReaderController()
        defer { fixture.close() }
        var platformUpdates = 0

        try withUnpreparedRequest(in: fixture) { witness, mutation in
            reader.geometryReaderBuiltSize = Size(width: 120, height: 10)
            geometry.onBuild = { _, candidate in
                candidate.textInputController = controller
                candidate.textSelectability = .disabled
                candidate.onUpdatePlatformView = { _ in platformUpdates += 1 }
            }
            controller.onAttach = { [weak fixture] _ in
                fixture?.runtime.endAccessibilityMutation(mutation)
            }
            let request = fixture.runtime.prepareLazyListUIARequest(
                token: witness.token, in: witness, during: mutation)
            if let request { fixture.runtime.finishLazyListUIARequest(request) }

            XCTAssertNil(request)
            XCTAssertEqual(geometry.calls, 1)
            XCTAssertEqual(controller.attaches, 1)
            XCTAssertEqual(controller.reconciles, 0, "attach revoked the query inside controller adoption")
            XCTAssertTrue(reader.textInputController === controller, "The accepted field must not roll back")
            XCTAssertEqual(reader.textSelectability, .enabled)
            XCTAssertEqual(reader.geometryReaderBuiltSize, Size(width: 120, height: 10))
            XCTAssertEqual(platformUpdates, 0)
            XCTAssertFalse(fixture.probe.factories.contains(300))
            XCTAssertEqual(fixture.scroll.scrollOffset, 0)
        }
    }

    func testReaderOutgoingControllerReleaseStopsFallbackMetadataAndTheNextReader() async throws {
        let geometry = UIAContinuationReaderProbe()
        let laterGeometry = UIAContinuationReaderProbe()
        let reader = geometry.node(builtSize: Size(width: 120, height: 20))
        let later = laterGeometry.node(builtSize: Size(width: 120, height: 20))
        reader.textInputCaretOffset = 3
        reader.textSelectability = .enabled
        let fixture = try makeFixture(beforeList: [reader, later])
        defer { fixture.close() }
        var events: [String] = []
        var releaseSawNoController = false

        try withUnpreparedRequest(in: fixture) { witness, mutation in
            installReaderReleaseController(
                on: reader,
                onDetach: { node in
                    events.append("detach")
                    node.textInputCaretOffset = 9
                },
                onRelease: { [weak fixture, weak reader] in
                    events.append("release")
                    releaseSawNoController = reader?.textInputController == nil
                    fixture?.runtime.endAccessibilityMutation(mutation)
                })
            reader.geometryReaderBuiltSize = Size(width: 120, height: 10)
            later.geometryReaderBuiltSize = Size(width: 120, height: 10)
            geometry.onBuild = { _, candidate in
                candidate.textInputCaretOffset = 44
                candidate.textSelectability = .disabled
            }
            let request = fixture.runtime.prepareLazyListUIARequest(
                token: witness.token, in: witness, during: mutation)
            if let request { fixture.runtime.finishLazyListUIARequest(request) }

            // These checks precede fixture shutdown: teardown cannot supply
            // a missing release or make a late destructor appear synchronous.
            XCTAssertNil(request)
            XCTAssertEqual(events, ["detach", "release"])
            XCTAssertTrue(releaseSawNoController)
            XCTAssertNil(reader.textInputController)
            XCTAssertEqual(reader.textInputCaretOffset, 9)
            XCTAssertEqual(reader.textSelectability, .enabled)
            XCTAssertEqual(geometry.calls, 1)
            XCTAssertEqual(laterGeometry.calls, 0)
            XCTAssertFalse(fixture.probe.factories.contains(300))
            XCTAssertEqual(fixture.scroll.scrollOffset, 0)
        }
    }

    func testReaderOldBodyReleaseIdentityABAStopsTheNextReaderAfterAcceptedAdoption() async throws {
        let geometry = UIAContinuationReaderProbe()
        let laterGeometry = UIAContinuationReaderProbe()
        let reader = geometry.node(builtSize: Size(width: 120, height: 20))
        let later = laterGeometry.node(builtSize: Size(width: 120, height: 20))
        let original = RetainedViewIdentity(segments: [.role(.content), .slot(52)])
        reader.retainedViewIdentity = original
        geometry.install(on: reader, builtSize: Size(width: 120, height: 20))
        let fixture = try makeFixture(beforeList: [reader, later])
        defer { fixture.close() }
        let factories = fixture.probe.factories
        var releases = 0

        try withUnpreparedRequest(in: fixture) { witness, mutation in
            reader.geometryReaderBuiltSize = Size(width: 120, height: 10)
            later.geometryReaderBuiltSize = Size(width: 120, height: 10)
            installReaderBodyRelease(on: reader) { [weak reader] in
                releases += 1
                reader?.retainedViewIdentity = original
            }
            let request = fixture.runtime.prepareLazyListUIARequest(
                token: witness.token, in: witness, during: mutation)
            if let request { fixture.runtime.finishLazyListUIARequest(request) }

            XCTAssertNil(request)
            XCTAssertEqual(geometry.calls, 1)
            XCTAssertEqual(releases, 1, "The old body must unwind before admitting another reader")
            XCTAssertEqual(reader.retainedViewIdentity, original)
            XCTAssertEqual(reader.geometryReaderBuiltSize, Size(width: 120, height: 20))
            XCTAssertEqual(laterGeometry.calls, 0, "An accepted reader needs proof through capture release")
            XCTAssertEqual(fixture.probe.factories, factories)
            XCTAssertEqual(fixture.scroll.scrollOffset, 0)
        }
    }

    func testReaderTaskCancellationRevocationStopsBothReplacementAndNextTask() async throws {
        let geometry = UIAContinuationReaderProbe()
        let reader = geometry.node(builtSize: Size(width: 120, height: 20))
        let fixture = try makeFixture(beforeList: [reader])
        let work = UIAContinuationReaderTaskProbe()
        defer {
            work.onCancel = nil
            work.release()
            fixture.close()
        }
        _ = fixture.runtime.renderScene()
        XCTAssertTrue(reader.hasAppeared)
        let ready = expectation(description: "Original reader task installed its cancellation handler")
        let forbidden = expectation(description: "No task may launch after the query is revoked")
        forbidden.isInverted = true
        reader.launchLifecycleTask(
            ViewLifecycleTaskLaunch(
                key: "reader-task", priority: .userInitiated,
                action: { await work.run(ready: ready) }))
        await fulfillment(of: [ready], timeout: 1)
        XCTAssertEqual(work.starts, 1)

        try withUnpreparedRequest(in: fixture) { witness, mutation in
            reader.geometryReaderBuiltSize = Size(width: 120, height: 10)
            work.onCancel = { [weak fixture] in
                fixture?.runtime.endAccessibilityMutation(mutation)
            }
            geometry.onBuild = { _, candidate in
                candidate.pendingLifecycleTaskLaunches = [
                    ViewLifecycleTaskLaunch(
                        key: "reader-task", priority: .userInitiated, action: { forbidden.fulfill() }),
                    ViewLifecycleTaskLaunch(
                        key: "reader-next-task", priority: .userInitiated, action: { forbidden.fulfill() }),
                ]
            }
            let request = fixture.runtime.prepareLazyListUIARequest(
                token: witness.token, in: witness, during: mutation)
            if let request { fixture.runtime.finishLazyListUIARequest(request) }

            XCTAssertNil(request)
            XCTAssertEqual(geometry.calls, 1)
            XCTAssertEqual(work.cancellations, 1, "The first task's actual cancellation must revoke the query")
            XCTAssertTrue(reader.pendingLifecycleTaskLaunches.isEmpty)
            XCTAssertFalse(fixture.probe.factories.contains(300))
            XCTAssertEqual(fixture.scroll.scrollOffset, 0)
        }

        await fulfillment(of: [forbidden], timeout: 0.1)
        XCTAssertEqual(work.starts, 1)
    }

    func testReaderPartialChildAdoptionCommitsAndCleansOnlyAcceptedOutput() async throws {
        let geometry = UIAContinuationReaderProbe()
        let reader = geometry.node(builtSize: Size(width: 120, height: 20))
        let lease = UIAContinuationReaderLease()
        reader.retainedSubtreeBuildLease = lease
        geometry.install(on: reader, builtSize: Size(width: 120, height: 20))
        let accepted = readerChild(tag: "accepted", text: "old accepted")
        let interrupted = readerChild(tag: "interrupted", text: "old interrupted")
        let later = readerChild(tag: "later", text: "old later")
        reader.setChildren([accepted, interrupted, later])
        let fixture = try makeFixture(beforeList: [reader])
        let controller = UIAContinuationReaderController()
        defer { fixture.close() }
        var dismantles = 0

        try withUnpreparedRequest(in: fixture) { witness, mutation in
            reader.geometryReaderBuiltSize = Size(width: 120, height: 10)
            geometry.onBuild = { [self] _, candidate in
                let first = readerChild(tag: "accepted", text: "new accepted")
                first.onDismantlePlatformView = { _ in dismantles += 1 }
                let second = readerChild(tag: "interrupted", text: "new interrupted")
                second.textInputController = controller
                let third = readerChild(tag: "later", text: "must not be copied")
                candidate.setChildren([first, second, third])
            }
            controller.onAttach = { [weak fixture] _ in
                fixture?.runtime.endAccessibilityMutation(mutation)
            }
            let request = fixture.runtime.prepareLazyListUIARequest(
                token: witness.token, in: witness, during: mutation)
            if let request { fixture.runtime.finishLazyListUIARequest(request) }

            XCTAssertNil(request)
            XCTAssertEqual(controller.attaches, 1)
            XCTAssertEqual(controller.reconciles, 0)
            XCTAssertEqual(accepted.text, "new accepted")
            XCTAssertEqual(later.text, "old later", "The next sibling cannot receive a stale property copy")
            XCTAssertTrue(accepted.parent === reader)
            XCTAssertTrue(accepted.retainedLazyListRuntime === fixture.runtime)
            XCTAssertEqual(lease.commits, 1, "Accepted output requires its ordinary publication epilogue")
            XCTAssertEqual(lease.abandons, 0)
            XCTAssertEqual(lease.finishes, 1)
            XCTAssertFalse(fixture.runtime.retainedBuildCoordinator.isBuilding)
            XCTAssertEqual(dismantles, 0, "Revocation must not roll back an already accepted child")
            XCTAssertFalse(fixture.probe.factories.contains(300))
            XCTAssertEqual(fixture.scroll.scrollOffset, 0)
        }

        reader.setChildren([])
        reader.setChildren([])
        XCTAssertNil(accepted.parent)
        XCTAssertNil(accepted.retainedLazyListRuntime)
        XCTAssertEqual(dismantles, 1)
    }

    func testReaderLaterChildCallbackCannotRefreshACompletedDescendantAfterIdentityABA() async throws {
        let geometry = UIAContinuationReaderProbe()
        let reader = geometry.node(builtSize: Size(width: 120, height: 20))
        let first = readerChild(tag: "first", text: "first")
        let descendant = readerChild(tag: "descendant", text: "old descendant")
        let identity = RetainedViewIdentity(segments: [.role(.content), .slot(53)])
        descendant.retainedViewIdentity = identity
        first.setChildren([descendant])
        let second = readerChild(tag: "second", text: "old second")
        let later = readerChild(tag: "later", text: "old later")
        reader.setChildren([first, second, later])
        let fixture = try makeFixture(beforeList: [reader])
        defer { fixture.close() }
        var secondUpdates = 0
        var laterUpdates = 0

        try withUnpreparedRequest(in: fixture) { witness, mutation in
            reader.geometryReaderBuiltSize = Size(width: 120, height: 10)
            geometry.onBuild = { [self] _, candidate in
                let firstCandidate = readerChild(tag: "first", text: "first")
                let leaf = readerChild(tag: "descendant", text: "new descendant")
                leaf.retainedViewIdentity = identity
                firstCandidate.setChildren([leaf])
                let secondCandidate = readerChild(tag: "second", text: "new second")
                secondCandidate.onUpdatePlatformView = { [weak descendant] _ in
                    secondUpdates += 1
                    descendant?.retainedViewIdentity = identity
                }
                let laterCandidate = readerChild(tag: "later", text: "must not be copied")
                laterCandidate.onUpdatePlatformView = { _ in laterUpdates += 1 }
                candidate.setChildren([firstCandidate, secondCandidate, laterCandidate])
            }
            let request = fixture.runtime.prepareLazyListUIARequest(
                token: witness.token, in: witness, during: mutation)
            if let request { fixture.runtime.finishLazyListUIARequest(request) }

            XCTAssertNil(request)
            XCTAssertEqual(geometry.calls, 1)
            XCTAssertEqual(descendant.text, "new descendant")
            XCTAssertEqual(descendant.retainedViewIdentity, identity)
            XCTAssertTrue(descendant.parent === first)
            XCTAssertEqual(secondUpdates, 1)
            XCTAssertEqual(laterUpdates, 0, "Earlier completed descendants remain part of the original proof")
            XCTAssertEqual(later.text, "old later")
            XCTAssertFalse(fixture.probe.factories.contains(300))
            XCTAssertEqual(fixture.scroll.scrollOffset, 0)
        }
    }

    private func readerChild(tag: String, text: String) -> ViewNode {
        let child = ViewNode(frame: Rect(x: 0, y: 0, width: 30, height: 6), text: text)
        child.nodeTag = tag
        return child
    }

    @inline(never)
    private func installReaderBodyRelease(on node: ViewNode, onRelease: @escaping @MainActor () -> Void) {
        let body = node.geometryReaderBuild
        let payload = UIAContinuationReaderReleasePayload(onRelease)
        node.geometryReaderBuild = { runtime, size in
            let result = body?(runtime, size) ?? []
            withExtendedLifetime(payload) {}
            return result
        }
    }

    @inline(never)
    private func installReaderReleaseController(
        on node: ViewNode, onDetach: @escaping (ViewNode) -> Void, onRelease: @escaping @MainActor () -> Void
    ) {
        let controller = UIAContinuationReaderController()
        let payload = UIAContinuationReaderReleasePayload(onRelease)
        controller.onDetach = { [payload] node in
            onDetach(node)
            withExtendedLifetime(payload) {}
        }
        node.textInputController = controller
    }

    private func withUnpreparedRequest(
        in fixture: UIAContinuationFixture,
        _ body: @MainActor (RetainedLazyListAccessibilityItem, RetainedAccessibilityMutation) throws -> Void
    ) throws {
        let witness = try fixture.target(300)
        let mutation = try XCTUnwrap(fixture.runtime.beginAccessibilityMutation())
        defer { fixture.runtime.endAccessibilityMutation(mutation) }
        try fixture.runtime.withLazyListResolutionBudget { try body(witness, mutation) }
    }

    private func makeFixture(
        heights: [Int: [Double]] = [:], beforeList: [ViewNode] = [],
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> UIAContinuationFixture {
        let fixture = try UIAContinuationFixture(heights: heights, beforeList: beforeList)
        XCTAssertNotNil(fixture.runtime.resolvedLayoutFrame(of: fixture.scroll), file: file, line: line)
        XCTAssertTrue(fixture.runtime.hasCurrentAccessibilityPrepaint, file: file, line: line)
        XCTAssertFalse(fixture.adapter.hasUnresolvedWork, file: file, line: line)
        XCTAssertFalse(fixture.probe.factories.contains(300), file: file, line: line)
        _ = try settledReceipt(in: fixture.runtime, file: file, line: line)
        return fixture
    }

    private func withRequest(
        in fixture: UIAContinuationFixture, id: Int = 300,
        file: StaticString = #filePath, line: UInt = #line,
        _ body: @MainActor (RetainedLazyListUIARequest, RetainedAccessibilityMutation) throws -> Void
    ) throws {
        let witness = try fixture.target(id, file: file, line: line)
        let mutation = try XCTUnwrap(fixture.runtime.beginAccessibilityMutation(), file: file, line: line)
        defer { fixture.runtime.endAccessibilityMutation(mutation) }
        try fixture.runtime.withLazyListResolutionBudget {
            let request = try XCTUnwrap(
                fixture.runtime.prepareLazyListUIARequest(token: witness.token, in: witness, during: mutation),
                file: file, line: line)
            defer { fixture.runtime.finishLazyListUIARequest(request) }
            try body(request, mutation)
        }
    }

    private func assertResolved(
        _ roots: [ViewNode], for request: RetainedLazyListUIARequest, in fixture: UIAContinuationFixture, id: Int,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let target = try XCTUnwrap(roots.first, file: file, line: line)
        let constructed = try XCTUnwrap(fixture.probe.rows[id], file: file, line: line)
        XCTAssertEqual(roots.count, constructed.count, file: file, line: line)
        XCTAssertTrue(zip(roots, constructed).allSatisfy { $0.0 === $0.1 }, file: file, line: line)
        XCTAssertTrue(
            roots.allSatisfy {
                $0.parent === fixture.list && $0.retainedLazyListRuntime === fixture.runtime
                    && $0.lastLayoutVisitPassID == fixture.runtime.layoutPassID
                    && !$0.isLayoutDeferredByVirtualization
            }, file: file, line: line)
        XCTAssertTrue(fixture.runtime.isLazyListAccessibilityItemCurrent(request.item), file: file, line: line)
        XCTAssertTrue(fixture.runtime.isResolvedLazyListUIARequestCurrent(request), file: file, line: line)
        XCTAssertTrue(fixture.runtime.hasCurrentAccessibilityPrepaint, file: file, line: line)
        let visible = try XCTUnwrap(
            fixture.runtime.currentPrepaintState.interactions.first { $0.node === target }, file: file, line: line)
        XCTAssertGreaterThan(visible.visibleFrame.width, 0, file: file, line: line)
        XCTAssertGreaterThan(visible.visibleFrame.height, 0, file: file, line: line)
        _ = try settledReceipt(in: fixture.runtime, file: file, line: line)
    }

    private func settledReceipt(
        in runtime: RetainedViewRuntime, file: StaticString = #filePath, line: UInt = #line
    ) throws -> RetainedLayoutSettlementReceipt {
        var receipt: RetainedLayoutSettlementReceipt?
        if case .settled(let current) = runtime.layoutSettlementStatus { receipt = current }
        let current = try XCTUnwrap(receipt, "Expected a real settled layout", file: file, line: line)
        XCTAssertTrue(runtime.isLayoutSettlementReceiptCurrent(current), file: file, line: line)
        return current
    }
}

@MainActor
private final class UIAContinuationFixture {
    let probe: UIAContinuationProbe
    let source: RetainedLazyListDataSource<Int, [ViewNode]>
    let adapter: RetainedLazyListRuntimeAdapter
    let list: ViewNode
    let scroll: ViewNode
    let runtime: RetainedViewRuntime
    private let identity: RetainedViewIdentity

    init(heights: [Int: [Double]], beforeList: [ViewNode] = []) throws {
        let identity = RetainedViewIdentity(segments: [.role(.content), .slot(0)])
        let probe = UIAContinuationProbe(heights: heights)
        let source = RetainedLazyListDataSource<Int, [ViewNode]>()
        let factory: @MainActor @Sendable (Int, RetainedViewIdentity) -> [ViewNode] = { value, prefix in
            probe.makeRows(value, prefix: prefix)
        }
        XCTAssertTrue(source.replaceData(Array(0..<1000), id: \.self, identityRoot: identity, rowContent: factory))
        let adapter = try XCTUnwrap(
            RetainedLazyListRuntimeAdapter(
                provider: source, estimatedExtent: 20, prefetchExtent: 0,
                maximumMountedRecords: 16, maximumMountedLeaves: 32, maximumProtectedRecords: 2))
        let list = ViewNode(layoutMode: .lazyStack(.vertical(spacing: 0, alignment: .stretch)))
        list.retainedViewIdentity = identity
        list.retainedLazyListAdapter = adapter
        list.retainedSubtreeBuildLease = UIAContinuationBuildLease()
        let scroll = ViewNode(
            frame: Rect(x: 0, y: 0, width: 120, height: 60), clipsToBounds: true,
            layoutMode: .stack(.vertical(spacing: 0, alignment: .stretch)),
            scrollAxis: .vertical, children: beforeList + [list])
        let runtime = RetainedViewRuntime(root: scroll)
        runtime.clock = { 0 }
        // This is an explicit adequate allowance for the typed contract, not
        // a change to a production default or the separate four-round oracle.
        XCTAssertTrue(runtime.configureLazyListResolutionBudget(elementLimit: 32, roundLimit: 16))
        self.probe = probe
        self.source = source
        self.adapter = adapter
        self.list = list
        self.scroll = scroll
        self.runtime = runtime
        self.identity = identity
    }

    func target(
        _ id: Int, file: StaticString = #filePath, line: UInt = #line
    ) throws -> RetainedLazyListAccessibilityItem {
        let token = try XCTUnwrap(source.token(for: .init(id)), file: file, line: line)
        return try XCTUnwrap(runtime.lazyListTarget(in: list, token: token), file: file, line: line)
    }

    func replaceValues(_ values: [Int]) -> Bool {
        let probe = probe
        let factory: @MainActor @Sendable (Int, RetainedViewIdentity) -> [ViewNode] = { value, prefix in
            probe.makeRows(value, prefix: prefix)
        }
        return source.replaceData(values, id: \.self, identityRoot: identity, rowContent: factory)
    }

    func close() {
        probe.onFactory = nil
        probe.configureRows = nil
        list.onLayout = nil
        scroll.onLayout = nil
        runtime.stopRenderLifecycleCallbacks()
        source.close()
        runtime.cancelRenderLifecycleTasks()
    }
}

@MainActor
private final class UIAContinuationProbe {
    let heights: [Int: [Double]]
    var factories: [Int] = []
    var rows: [Int: [ViewNode]] = [:]
    var onFactory: (@MainActor @Sendable (Int) -> Void)?
    var configureRows: (@MainActor @Sendable (Int, [ViewNode]) -> Void)?
    var interventions = 0
    var callbackCalls = 0
    var passAtCallback: UInt64?
    var ownedOffset: Double?
    var borrowedTarget: RetainedAccessibilityTarget?
    var restoredOriginalChildren = false

    init(heights: [Int: [Double]]) { self.heights = heights }

    func makeRows(_ id: Int, prefix: RetainedViewIdentity) -> [ViewNode] {
        factories.append(id)
        onFactory?(id)
        let result = (heights[id] ?? [20]).enumerated().map { leaf, height in
            let node = ViewNode(preferredSize: Size(width: 120, height: height))
            node.retainedViewIdentity = prefix.appending(.slot(leaf)).appending(.role(.row))
            node.dynamicContentIndex = id
            node.accessibilityIdentifier = "uia.row.\(id).\(leaf)"
            return node
        }
        configureRows?(id, result)
        rows[id] = result
        return result
    }
}

@MainActor
private final class UIAContinuationReaderProbe {
    private(set) var calls = 0
    var onBuild: ((RetainedViewRuntime, ViewNode) -> Void)?
    var rejectsResult = false

    func node(builtSize: Size) -> ViewNode {
        let node = ViewNode(preferredSize: Size(width: 120, height: 20))
        install(on: node, builtSize: builtSize)
        return node
    }

    func install(on node: ViewNode, builtSize: Size) {
        let preferredSize = node.preferredSize
        let identity = node.retainedViewIdentity
        let dynamicIndex = node.dynamicContentIndex
        let identifier = node.accessibilityIdentifier
        let lease = node.retainedSubtreeBuildLease
        node.geometryReaderBuiltSize = builtSize
        node.geometryReaderBuild = { [self] runtime, slot in
            calls += 1
            let candidate = ViewNode(preferredSize: preferredSize)
            // A factory reader is the actual row, not a replacement logical
            // item. Reproduce its existing row identity in the body result.
            candidate.retainedViewIdentity = identity
            candidate.dynamicContentIndex = dynamicIndex
            candidate.accessibilityIdentifier = identifier
            candidate.retainedSubtreeBuildLease = lease
            install(on: candidate, builtSize: slot)
            onBuild?(runtime, candidate)
            return rejectsResult ? [] : [candidate]
        }
    }
}

private enum UIAContinuationReaderCallout: CaseIterable, Equatable {
    case canBuild, beginBuild, canAdopt, willAdopt
}

@MainActor
private final class UIAContinuationReaderLease: RetainedSubtreeBuildLease {
    var calls: [UIAContinuationReaderCallout] = []
    var onCall: ((UIAContinuationReaderCallout) -> Void)?
    var refusedCallout: UIAContinuationReaderCallout?
    var commits = 0
    var abandons = 0
    var finishes = 0

    var canBuild: Bool {
        call(.canBuild)
        return refusedCallout != .canBuild
    }

    func beginBuild() -> (any RetainedBuildEpoch)? {
        call(.beginBuild)
        guard refusedCallout != .beginBuild else { return nil }
        return UIAContinuationReaderEpoch(lease: self)
    }

    func call(_ point: UIAContinuationReaderCallout) {
        calls.append(point)
        onCall?(point)
    }
}

@MainActor
private final class UIAContinuationReaderEpoch: RetainedBuildEpoch {
    let lease: UIAContinuationReaderLease
    private var prepared = false
    private var wasSuperseded = false

    init(lease: UIAContinuationReaderLease) { self.lease = lease }

    var canAdopt: Bool {
        lease.call(.canAdopt)
        return !prepared && !wasSuperseded && lease.refusedCallout != .canAdopt
    }

    func supersede() { if !prepared { wasSuperseded = true } }
    func willAdopt() -> Bool {
        lease.call(.willAdopt)
        guard !prepared && !wasSuperseded && lease.refusedCallout != .willAdopt else { return false }
        prepared = true
        return true
    }
    func commit() { lease.commits += 1 }
    func abandon() { lease.abandons += 1 }
    func finishAfterCallbacks() { lease.finishes += 1 }
}

@MainActor
private final class UIAContinuationReaderController: RetainedTextInputController {
    var attaches = 0
    var reconciles = 0
    var onAttach: ((ViewNode) -> Void)?
    var onDetach: ((ViewNode) -> Void)?

    func attach(to node: ViewNode) {
        attaches += 1
        onAttach?(node)
    }

    func reconcile(from previous: (any RetainedTextInputController)?, onto node: ViewNode) {
        reconciles += 1
    }

    func detach(from node: ViewNode) { onDetach?(node) }
}

@MainActor
private final class UIAContinuationReaderReleasePayload {
    let onRelease: @MainActor () -> Void
    init(_ onRelease: @escaping @MainActor () -> Void) { self.onRelease = onRelease }
    isolated deinit { onRelease() }
}

@MainActor
private final class UIAContinuationReaderTaskProbe {
    private(set) var starts = 0
    private(set) var cancellations = 0
    var onCancel: (() -> Void)?
    private var continuation: CheckedContinuation<Void, Never>?

    func run(ready: XCTestExpectation) async {
        starts += 1
        await withTaskCancellationHandler {
            await withCheckedContinuation { pending in
                if Task.isCancelled {
                    pending.resume()
                } else {
                    continuation = pending
                }
                ready.fulfill()
            }
        } onCancel: { [weak self] in
            // Only the synchronous MainActor runtime cancellation paths in
            // this fixture own this running task's cancellation handle.
            MainActor.assumeIsolated { self?.cancel() }
        }
    }

    private func cancel() {
        cancellations += 1
        onCancel?()
        release()
    }

    func release() {
        let pending = continuation
        continuation = nil
        pending?.resume()
    }
}

@MainActor
private final class UIAContinuationBuildLease: RetainedSubtreeBuildLease {
    var canBuild: Bool { true }
    func beginBuild() -> (any RetainedBuildEpoch)? { UIAContinuationBuildEpoch() }
}

@MainActor
private final class UIAContinuationBuildEpoch: RetainedBuildEpoch {
    private var prepared = false
    private var wasSuperseded = false
    var canAdopt: Bool { !prepared && !wasSuperseded }
    func supersede() { if !prepared { wasSuperseded = true } }
    func willAdopt() -> Bool {
        guard canAdopt else { return false }
        prepared = true
        return true
    }
    func commit() {}
    func abandon() {}
    func finishAfterCallbacks() {}
}
