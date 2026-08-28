import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import WinSDK
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class WindowCloseFinalizationTests: XCTestCase {
    func testLayoutStatusReadDoesNotStartLayoutOrCreateEvidence() async {
        let runtime = closeLayoutRuntime()
        XCTAssertTrue(runtime.canPrepareLayoutSettlement)
        assertCloseLayoutUnsettled(runtime)
        assertCloseLayoutUnsettled(runtime)
        XCTAssertEqual(runtime.layoutPassID, 0)
        XCTAssertEqual(runtime.contentRevision, 0)
    }

    func testInitialNormalButtonCanObtainReceiptWithoutRendering() async throws {
        let runtime = closeLayoutRuntime()
        var actions = 0
        let button = Controls.button(
            runtime: runtime, title: "Close", frame: Rect(x: 8, y: 8, width: 100, height: 32),
            cornerRadius: 6, palette: .default, action: { actions += 1 })
        runtime.root.addChild(button)

        XCTAssertNotNil(runtime.resolvedLayoutFrame(of: runtime.root))
        let receipt = try closeLayoutReceipt(runtime)
        XCTAssertTrue(runtime.isLayoutSettlementReceiptCurrent(receipt))
        XCTAssertEqual(actions, 0)
        XCTAssertEqual(runtime.contentRevision, 0)
        XCTAssertEqual(runtime.sceneRebuildCount, 0)
    }

    func testLayoutOnlyReceiptDoesNotRequireRenderDirtyFlagsToClear() async throws {
        let runtime = closeLayoutRuntime()
        runtime.root.addChild(ViewNode(frame: Rect(x: 4, y: 6, width: 20, height: 30)))
        XCTAssertTrue(runtime.hasPendingLayout)

        XCTAssertNotNil(runtime.resolvedLayoutFrame(of: runtime.root))
        let receipt = try closeLayoutReceipt(runtime)
        XCTAssertTrue(runtime.hasPendingLayout, "Layout-only preparation must not clear render invalidations")
        XCTAssertTrue(runtime.isLayoutSettlementReceiptCurrent(receipt))
        XCTAssertEqual(runtime.contentRevision, 0)
    }

    func testFirstSliderMutationIsUnavailableUntilAnOrdinaryLaterLayout() async throws {
        let runtime = closeLayoutRuntime()
        let slider = Controls.slider(runtime: runtime, value: 0.5)
        let thumb = try XCTUnwrap(slider.children.last)
        let initialThumbFrame = thumb.frame
        slider.preferredSize = Size(width: 150, height: 32)
        runtime.root.addChild(slider)

        XCTAssertNotNil(runtime.resolvedLayoutFrame(of: runtime.root))
        XCTAssertEqual(slider.resolvedFrame.size, Size(width: 150, height: 32))
        XCTAssertNotEqual(thumb.frame, initialThumbFrame)
        assertCloseLayoutUnavailable(runtime)
        let firstPass = runtime.layoutPassID
        assertCloseLayoutUnavailable(runtime)
        XCTAssertEqual(runtime.layoutPassID, firstPass, "Status reads must not retry a bounded resolution")

        // This is a separate, ordinary layout, not an implicit close retry.
        XCTAssertNotNil(runtime.resolvedLayoutFrame(of: runtime.root))
        let receipt = try closeLayoutReceipt(runtime)
        XCTAssertTrue(runtime.isLayoutSettlementReceiptCurrent(receipt))
        XCTAssertEqual(runtime.contentRevision, 0)
    }

    func testLateNodeGeometryInvalidatesOriginalReceiptWithoutBuilding() async throws {
        let runtime = closeLayoutRuntime()
        _ = runtime.resolvedLayoutFrame(of: runtime.root)
        let original = try closeLayoutReceipt(runtime)
        let pass = runtime.layoutPassID

        runtime.root.frame.size.width += 40
        assertCloseLayoutUnsettled(runtime)
        XCTAssertFalse(runtime.isLayoutSettlementReceiptCurrent(original))
        XCTAssertEqual(runtime.layoutPassID, pass)

        _ = runtime.resolvedLayoutFrame(of: runtime.root)
        XCTAssertTrue(runtime.isLayoutSettlementReceiptCurrent(try closeLayoutReceipt(runtime)))
        XCTAssertFalse(runtime.isLayoutSettlementReceiptCurrent(original))
    }

    func testGlobalLayoutInvalidationAlsoInvalidatesReceipt() async throws {
        let runtime = closeLayoutRuntime()
        _ = runtime.resolvedLayoutFrame(of: runtime.root)
        let original = try closeLayoutReceipt(runtime)
        runtime.displayScale = 1.25

        assertCloseLayoutUnsettled(runtime)
        XCTAssertFalse(runtime.isLayoutSettlementReceiptCurrent(original))
    }

    func testChildReplacementInvalidatesReceipt() async throws {
        let runtime = closeLayoutRuntime()
        _ = runtime.resolvedLayoutFrame(of: runtime.root)
        let original = try closeLayoutReceipt(runtime)

        runtime.root.setChildren([ViewNode(frame: Rect(x: 0, y: 0, width: 30, height: 20))])
        assertCloseLayoutUnsettled(runtime)
        XCTAssertFalse(runtime.isLayoutSettlementReceiptCurrent(original))
    }

    func testPaintOnlyMutationDoesNotPretendGeometryChanged() async throws {
        let runtime = closeLayoutRuntime()
        _ = runtime.resolvedLayoutFrame(of: runtime.root)
        let receipt = try closeLayoutReceipt(runtime)
        runtime.root.backgroundColor = .green

        XCTAssertTrue(runtime.isLayoutSettlementReceiptCurrent(receipt))
        XCTAssertEqual(runtime.contentRevision, 0)
    }

    func testPaintOnlyOnLayoutCallbacksCanStillProduceReceipt() async throws {
        let runtime = closeLayoutRuntime()
        var calls = 0
        runtime.root.onLayout = { [weak runtime] _ in
            calls += 1
            runtime?.root.backgroundColor = .green
        }

        _ = runtime.resolvedLayoutFrame(of: runtime.root)
        let receipt = try closeLayoutReceipt(runtime)
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(runtime.isLayoutSettlementReceiptCurrent(receipt))
        XCTAssertEqual(calls, 1)
    }

    func testDirectDismissalPolicyChangeInvalidatesReceipt() async throws {
        let runtime = closeLayoutRuntime()
        runtime.root.windowDismissBehavior = .enabled
        _ = runtime.resolvedLayoutFrame(of: runtime.root)
        let receipt = try closeLayoutReceipt(runtime)

        runtime.root.windowDismissBehavior = .disabled
        XCTAssertFalse(runtime.isLayoutSettlementReceiptCurrent(receipt))
        XCTAssertEqual(runtime.windowDismissalBehavior, .disabled)
    }

    func testAnotherCleanLayoutInvalidatesReceiptEvenWithIdenticalBounds() async throws {
        let runtime = closeLayoutRuntime()
        let before = runtime.resolvedLayoutFrame(of: runtime.root)
        let original = try closeLayoutReceipt(runtime)
        let after = runtime.resolvedLayoutFrame(of: runtime.root)
        let replacement = try closeLayoutReceipt(runtime)

        XCTAssertEqual(before, after)
        XCTAssertFalse(runtime.isLayoutSettlementReceiptCurrent(original))
        XCTAssertTrue(runtime.isLayoutSettlementReceiptCurrent(replacement))
    }

    func testReceiptCannotBeUsedByAnotherRuntimeWithMatchingGeometry() async throws {
        let first = closeLayoutRuntime()
        let second = closeLayoutRuntime()
        _ = first.resolvedLayoutFrame(of: first.root)
        _ = second.resolvedLayoutFrame(of: second.root)
        let firstReceipt = try closeLayoutReceipt(first)
        let secondReceipt = try closeLayoutReceipt(second)

        XCTAssertTrue(first.isLayoutSettlementReceiptCurrent(firstReceipt))
        XCTAssertFalse(second.isLayoutSettlementReceiptCurrent(firstReceipt))
        XCTAssertFalse(first.isLayoutSettlementReceiptCurrent(secondReceipt))
        second.root.frame.size.height += 10
        XCTAssertTrue(first.isLayoutSettlementReceiptCurrent(firstReceipt))
    }

    func testReceiptDoesNotRetainRuntimeOrApplicationCaptures() async throws {
        let witness = CloseLayoutLifetimeWitness()
        let receipt = try makeCloseLayoutLifetimeReceipt(witness: witness)
        XCTAssertNil(witness.runtime)
        XCTAssertNil(witness.payload)

        let replacement = closeLayoutRuntime()
        _ = replacement.resolvedLayoutFrame(of: replacement.root)
        XCTAssertFalse(replacement.isLayoutSettlementReceiptCurrent(receipt))
    }

    func testFinalReceiptChecksDoNotRunAppCallbacksLeaseGettersOrKeyHashing() async throws {
        let runtime = closeLayoutRuntime()
        let fixture = CloseLayoutReaderFixture()
        let lease = CloseLayoutLease()
        let hashes = CloseLayoutHashCounter()
        fixture.lease = lease
        let reader = fixture.makeNode(builtSize: runtime.root.frame.size)
        reader.retainedViewIdentity = RetainedViewIdentity(
            segments: [.keyed(.init(CloseLayoutHashKey(counter: hashes)))])
        var layouts = 0
        reader.onLayout = { _ in layouts += 1 }
        runtime.root.addChild(reader)
        _ = runtime.resolvedLayoutFrame(of: runtime.root)
        let receipt = try closeLayoutReceipt(runtime)
        let before = (layouts, fixture.bodyCount, lease.readCount, lease.beginCount, hashes.calls)
        let pass = runtime.layoutPassID

        for _ in 0..<10 {
            XCTAssertTrue(runtime.isLayoutSettlementReceiptCurrent(receipt))
            _ = try closeLayoutReceipt(runtime)
        }

        XCTAssertEqual(layouts, before.0)
        XCTAssertEqual(fixture.bodyCount, before.1)
        XCTAssertEqual(lease.readCount, before.2)
        XCTAssertEqual(lease.beginCount, before.3)
        XCTAssertEqual(hashes.calls, before.4)
        XCTAssertEqual(runtime.layoutPassID, pass)
        XCTAssertEqual(runtime.contentRevision, 0)
    }

    func testStatusIsUnsettledInsideLayoutAndPostLayoutCallbacks() async throws {
        let runtime = closeLayoutRuntime()
        var layoutReads = 0
        var afterLayoutReads = 0
        runtime.root.onLayout = { [weak runtime] _ in
            guard let runtime else { return }
            layoutReads += 1
            assertCloseLayoutUnsettled(runtime)
        }
        runtime.scheduleAfterLayout(key: "close-layout-readiness") { [weak runtime] in
            guard let runtime else { return }
            afterLayoutReads += 1
            assertCloseLayoutUnsettled(runtime)
        }

        _ = runtime.resolvedLayoutFrame(of: runtime.root)
        XCTAssertEqual(layoutReads, 2)
        XCTAssertEqual(afterLayoutReads, 1)
        XCTAssertTrue(runtime.isLayoutSettlementReceiptCurrent(try closeLayoutReceipt(runtime)))
    }

    func testReconciliationReadinessIsSeparateFromLayoutEvidence() async throws {
        let runtime = closeLayoutRuntime()
        _ = runtime.resolvedLayoutFrame(of: runtime.root)
        let receipt = try closeLayoutReceipt(runtime)

        runtime.beginLongPressReconciliation()
        assertCloseLayoutUnsettled(runtime)
        XCTAssertFalse(runtime.isLayoutSettlementReceiptCurrent(receipt))
        runtime.endLongPressReconciliation()

        XCTAssertTrue(runtime.isLayoutSettlementReceiptCurrent(receipt))
    }

    func testPreflightReadinessRejectsLayoutAndRawAfterLayoutWithoutAnotherQuery() async {
        let runtime = closeLayoutRuntime()
        var layoutChecks = 0
        var afterLayoutChecks = 0
        var nestedQueries = 0
        runtime.root.onLayout = { [weak runtime] _ in
            guard let runtime else { return }
            layoutChecks += 1
            XCTAssertTrue(runtime.isLayoutInProgress)
            XCTAssertFalse(runtime.canPrepareLayoutSettlement)
            let pass = runtime.layoutPassID
            if runtime.canPrepareLayoutSettlement {
                nestedQueries += 1
                _ = runtime.resolvedLayoutFrame(of: runtime.root)
            }
            XCTAssertEqual(runtime.layoutPassID, pass)
        }
        runtime.scheduleAfterLayout(key: "close-preflight-readiness") { [weak runtime] in
            guard let runtime else { return }
            afterLayoutChecks += 1
            XCTAssertFalse(runtime.isLayoutInProgress)
            XCTAssertFalse(runtime.canPrepareLayoutSettlement)
            let pass = runtime.layoutPassID
            if runtime.canPrepareLayoutSettlement {
                nestedQueries += 1
                _ = runtime.resolvedLayoutFrame(of: runtime.root)
            }
            XCTAssertEqual(runtime.layoutPassID, pass)
        }

        // Hit testing enters updateResolvedLayout without the public frame
        // query's guard. The readiness getter must still protect its callbacks.
        runtime.pointerMoved(to: Point(x: -20, y: -20))
        XCTAssertGreaterThan(layoutChecks, 0)
        XCTAssertEqual(afterLayoutChecks, 1)
        XCTAssertEqual(nestedQueries, 0)
        XCTAssertTrue(runtime.canPrepareLayoutSettlement)
        XCTAssertEqual(runtime.contentRevision, 0)
    }

    func testPreflightReadinessRejectsRawGeometryBodyWithoutNestedQuery() async {
        let runtime = closeLayoutRuntime()
        let fixture = CloseLayoutReaderFixture()
        var nestedQueries = 0
        fixture.onBuild = { runtime, _ in
            XCTAssertFalse(runtime.isLayoutInProgress)
            XCTAssertFalse(runtime.hasActiveRetainedBuild)
            XCTAssertFalse(runtime.canPrepareLayoutSettlement)
            if runtime.canPrepareLayoutSettlement {
                nestedQueries += 1
                _ = runtime.resolvedLayoutFrame(of: runtime.root)
            }
        }
        runtime.root.addChild(fixture.makeNode())

        runtime.pointerMoved(to: Point(x: -20, y: -20))
        XCTAssertEqual(fixture.bodyCount, 1)
        XCTAssertEqual(nestedQueries, 0)
        XCTAssertTrue(runtime.canPrepareLayoutSettlement)
        XCTAssertEqual(runtime.contentRevision, 0)
    }

    func testPreflightReadinessRejectsRetainedCompletionDrainWithoutQuery() async {
        let runtime = closeLayoutRuntime()
        var callbacks = 0
        var queries = 0
        runtime.beginLongPressReconciliation()
        XCTAssertFalse(runtime.canPrepareLayoutSettlement)
        runtime.afterRetainedCallbacks {
            callbacks += 1
            XCTAssertFalse(runtime.canPrepareLayoutSettlement)
            if runtime.canPrepareLayoutSettlement {
                queries += 1
                _ = runtime.resolvedLayoutFrame(of: runtime.root)
            }
        }
        XCTAssertEqual(callbacks, 0)

        runtime.endLongPressReconciliation()
        XCTAssertEqual(callbacks, 1)
        XCTAssertEqual(queries, 0)
        XCTAssertEqual(runtime.layoutPassID, 0)
        XCTAssertTrue(runtime.canPrepareLayoutSettlement)
        assertCloseLayoutUnsettled(runtime)
    }

    func testGeometryReaderPolicyUsesResolvedSlotInsteadOfCanvasSeed() async throws {
        let runtime = closeLayoutRuntime(width: 320, height: 100)
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 320, height: 100) }, invalidateHandler: {})
        let view = HStack(spacing: 0) {
            WinSwiftUI.Color.clear.frame(width: 120)
            GeometryReader { proxy in
                WinSwiftUI.Color.clear.windowDismissBehavior(proxy.size.width > 250 ? .enabled : .disabled)
            }
        }
        runtime.root.addChild(view.makeComponent(context: context).makeNode(runtime: runtime))
        XCTAssertEqual(runtime.windowDismissalBehavior, .enabled)

        _ = runtime.resolvedLayoutFrame(of: runtime.root)
        let receipt = try closeLayoutReceipt(runtime)
        XCTAssertEqual(runtime.windowDismissalBehavior, .disabled)
        XCTAssertTrue(runtime.isLayoutSettlementReceiptCurrent(receipt))
        XCTAssertGreaterThan(runtime.geometryReaderResolveCount, 0)
        XCTAssertEqual(runtime.contentRevision, 0)
    }

    func testGeometryConvergingOnFourthRoundDoesNotNeedFifthBodyCall() async throws {
        let runtime = closeLayoutRuntime(width: 200, height: 100)
        let fixture = CloseLayoutReaderFixture()
        fixture.onBuild = { runtime, slot in
            if slot.width < 500 {
                runtime.setRootSize(IntSize(width: Int32(slot.width + 100), height: 100))
            }
        }
        runtime.root.addChild(fixture.makeNode())

        XCTAssertEqual(runtime.resolvedLayoutFrame(of: runtime.root)?.size.width, 500)
        let receipt = try closeLayoutReceipt(runtime)
        XCTAssertEqual(fixture.bodyCount, 4)
        XCTAssertTrue(runtime.isLayoutSettlementReceiptCurrent(receipt))
        XCTAssertEqual(fixture.bodyCount, 4)
    }

    func testOscillatingGeometryExhaustsBoundWithoutReceiptOrRetry() async {
        let runtime = closeLayoutRuntime(width: 200, height: 100)
        let fixture = CloseLayoutReaderFixture()
        fixture.onBuild = { runtime, slot in
            runtime.setRootSize(IntSize(width: slot.width == 200 ? 300 : 200, height: 100))
        }
        runtime.root.addChild(fixture.makeNode())

        XCTAssertNotNil(runtime.resolvedLayoutFrame(of: runtime.root))
        assertCloseLayoutUnavailable(runtime)
        XCTAssertEqual(fixture.bodyCount, 4)
        let pass = runtime.layoutPassID
        assertCloseLayoutUnavailable(runtime)
        XCTAssertEqual(fixture.bodyCount, 4)
        XCTAssertEqual(runtime.layoutPassID, pass)
    }

    func testEmptyGeometryResultIsNotMistakenForConvergence() async {
        let runtime = closeLayoutRuntime()
        let fixture = CloseLayoutReaderFixture()
        fixture.returnsEmpty = true
        runtime.root.addChild(fixture.makeNode())

        XCTAssertNotNil(runtime.resolvedLayoutFrame(of: runtime.root))
        assertCloseLayoutUnavailable(runtime)
        XCTAssertEqual(fixture.bodyCount, 1)
        XCTAssertEqual(runtime.geometryReaderResolveCount, 0)
    }

    func testDeniedGeometryLeaseDoesNotInvokeExtraGetterToIssueReceipt() async {
        let runtime = closeLayoutRuntime()
        let fixture = CloseLayoutReaderFixture()
        let lease = CloseLayoutLease()
        lease.allowsBuild = false
        fixture.lease = lease
        runtime.root.addChild(fixture.makeNode())

        _ = runtime.resolvedLayoutFrame(of: runtime.root)
        assertCloseLayoutUnavailable(runtime)
        XCTAssertEqual(fixture.bodyCount, 0)
        XCTAssertEqual(lease.readCount, 1)
        XCTAssertEqual(lease.beginCount, 0)
        assertCloseLayoutUnavailable(runtime)
        XCTAssertEqual(lease.readCount, 1)
    }

    func testCoordinatedGeometryDeferredByActiveBuildCannotIssueReceipt() async throws {
        let runtime = closeLayoutRuntime()
        let fixture = CloseLayoutReaderFixture()
        fixture.lease = CloseLayoutLease()
        runtime.root.addChild(fixture.makeNode())
        let coordinator = runtime.retainedBuildCoordinator
        _ = try XCTUnwrap(coordinator.beginBuild())
        XCTAssertTrue(runtime.canPrepareLayoutSettlement, "Build settlement is a separate host requirement")

        _ = runtime.resolvedLayoutFrame(of: runtime.root)
        assertCloseLayoutUnsettled(runtime)
        XCTAssertEqual(fixture.bodyCount, 0)
        coordinator.finishBuild()
        assertCloseLayoutUnsettled(runtime)
        XCTAssertEqual(fixture.bodyCount, 0, "Draining the build only invalidates geometry; it does not resolve it")

        _ = runtime.resolvedLayoutFrame(of: runtime.root)
        XCTAssertTrue(runtime.isLayoutSettlementReceiptCurrent(try closeLayoutReceipt(runtime)))
        XCTAssertEqual(fixture.bodyCount, 1)
    }

    func testFurtherAfterLayoutWorkMakesBoundedAttemptUnavailable() async throws {
        let runtime = closeLayoutRuntime()
        var first = 0
        var second = 0
        runtime.scheduleAfterLayout(key: "first-close-layout-action") { [weak runtime] in
            first += 1
            runtime?.scheduleAfterLayout(key: "second-close-layout-action") { second += 1 }
        }

        _ = runtime.resolvedLayoutFrame(of: runtime.root)
        assertCloseLayoutUnavailable(runtime)
        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 0)
        assertCloseLayoutUnavailable(runtime)
        XCTAssertEqual(second, 0)

        _ = runtime.resolvedLayoutFrame(of: runtime.root)
        XCTAssertTrue(runtime.isLayoutSettlementReceiptCurrent(try closeLayoutReceipt(runtime)))
        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 1)
    }

    func testSchedulingAfterLayoutAfterReceiptInvalidatesItWithoutRunningAction() async throws {
        let runtime = closeLayoutRuntime()
        _ = runtime.resolvedLayoutFrame(of: runtime.root)
        let receipt = try closeLayoutReceipt(runtime)
        var calls = 0

        runtime.scheduleAfterLayout(key: "late-close-layout-action") { calls += 1 }
        XCTAssertFalse(runtime.isLayoutSettlementReceiptCurrent(receipt))
        assertCloseLayoutUnsettled(runtime)
        XCTAssertEqual(calls, 0)
    }

    func testPendingPreciseScrollAlignmentCannotProduceLayoutReceipt() async throws {
        let result = closeLayoutDeferredScrollFixture()
        _ = result.runtime.resolvedLayoutFrame(of: result.runtime.root)
        let original = try closeLayoutReceipt(result.runtime)
        XCTAssertTrue(result.row.isLayoutDeferredByVirtualization)
        XCTAssertTrue(
            result.runtime.scrollToDescendant(
                result.target, anchorY: 0,
                transaction: SwiftWindowsCore.Transaction(animation: .linear(duration: 1))))

        _ = result.runtime.resolvedLayoutFrame(of: result.runtime.root)
        XCTAssertFalse(result.runtime.isLayoutSettlementReceiptCurrent(original))
        XCTAssertTrue(result.row.isLayoutDeferredByVirtualization)
        XCTAssertEqual(result.container.scrollOffset, 400)
        XCTAssertEqual(result.container.resolvedScrollOffset, 0)
        assertCloseLayoutUnavailable(result.runtime)
        let pass = result.runtime.layoutPassID
        assertCloseLayoutUnavailable(result.runtime)
        XCTAssertEqual(result.runtime.layoutPassID, pass)

        // Normal animation/layout, outside final validation, realizes the
        // nested target and consumes its pending precise alignment.
        result.clock.now = 1
        _ = result.runtime.tickAnimations(at: result.clock.now)
        _ = result.runtime.renderScene()
        _ = result.runtime.resolvedLayoutFrame(of: result.runtime.root)
        XCTAssertFalse(result.row.isLayoutDeferredByVirtualization)
        XCTAssertEqual(result.container.resolvedScrollOffset, 600, accuracy: 0.0001)
        XCTAssertTrue(result.runtime.isLayoutSettlementReceiptCurrent(try closeLayoutReceipt(result.runtime)))
        XCTAssertFalse(result.runtime.isLayoutSettlementReceiptCurrent(original))
    }

    func testLateDescendantLayoutMutationCannotApproveAlreadyPlacedAncestor() async throws {
        let runtime = closeLayoutRuntime(width: 200, height: 100)
        let fixture = CloseLayoutReaderFixture()
        let reader = fixture.makeNode(builtSize: Size(width: 200, height: 100))
        let late = ViewNode(frame: Rect(x: 0, y: 0, width: 10, height: 10))
        var didChange = false
        late.onLayout = { [weak runtime] _ in
            guard !didChange, let runtime else { return }
            didChange = true
            runtime.root.frame.size.width = 400
        }
        runtime.root.setChildren([reader, late])

        XCTAssertEqual(runtime.resolvedLayoutFrame(of: runtime.root)?.size.width, 200)
        XCTAssertEqual(runtime.root.frame.size.width, 400)
        XCTAssertEqual(reader.geometryReaderBuiltSize?.width, 200)
        XCTAssertEqual(reader.resolvedFrame.size.width, 200)
        assertCloseLayoutUnavailable(runtime)

        XCTAssertEqual(runtime.resolvedLayoutFrame(of: runtime.root)?.size.width, 400)
        XCTAssertTrue(runtime.isLayoutSettlementReceiptCurrent(try closeLayoutReceipt(runtime)))
    }

    func testNestedLayoutCannotPublishEvidenceForOuterResolution() async throws {
        let runtime = closeLayoutRuntime()
        var nested = false
        runtime.root.onLayout = { [weak runtime] _ in
            guard let runtime, !nested else { return }
            nested = true
            // Public pointer routing performs layout for hit testing. This
            // deliberately probes a nested query without rendering pixels.
            runtime.pointerMoved(to: Point(x: -20, y: -20))
            assertCloseLayoutUnsettled(runtime)
        }

        _ = runtime.resolvedLayoutFrame(of: runtime.root)
        XCTAssertTrue(nested)
        assertCloseLayoutUnavailable(runtime)
        XCTAssertEqual(runtime.contentRevision, 0)

        _ = runtime.resolvedLayoutFrame(of: runtime.root)
        XCTAssertTrue(runtime.isLayoutSettlementReceiptCurrent(try closeLayoutReceipt(runtime)))
    }

    func testTruncatedTraversalCannotIssueReceipt() async {
        let runtime = closeLayoutRuntime()
        var deepest = runtime.root
        for _ in 0..<(ViewNode.maximumTraversalDepth + 1) {
            let next = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 100),
                layoutMode: .stack(.vertical(spacing: 0, alignment: .leading)),
                preferredSize: Size(width: 100, height: 100))
            deepest.addChild(next)
            deepest = next
        }
        let before = ViewNode.traversalDepthOverflowCount

        _ = runtime.resolvedLayoutFrame(of: runtime.root)
        XCTAssertGreaterThan(ViewNode.traversalDepthOverflowCount, before)
        assertCloseLayoutUnavailable(runtime)
    }

    func testGeometryGenerationOverflowPermanentlyMakesReceiptsUnavailable() async throws {
        let runtime = closeLayoutRuntime()
        runtime.exhaustLayoutGeometryGenerationOnNextInvalidationForTesting()
        _ = runtime.resolvedLayoutFrame(of: runtime.root)
        let lastReceipt = try closeLayoutReceipt(runtime)

        runtime.root.frame.size.width += 1
        assertCloseLayoutUnavailable(runtime)
        XCTAssertFalse(runtime.canPrepareLayoutSettlement)
        XCTAssertFalse(runtime.isLayoutSettlementReceiptCurrent(lastReceipt))
        _ = runtime.resolvedLayoutFrame(of: runtime.root)
        assertCloseLayoutUnavailable(runtime)
        runtime.exhaustLayoutGeometryGenerationOnNextInvalidationForTesting()
        assertCloseLayoutUnavailable(runtime)
    }

    func testGlobalInvalidationGenerationOverflowAlsoFailsUnavailable() async throws {
        let runtime = closeLayoutRuntime()
        runtime.exhaustLayoutGeometryGenerationOnNextInvalidationForTesting()
        _ = runtime.resolvedLayoutFrame(of: runtime.root)
        let receipt = try closeLayoutReceipt(runtime)

        runtime.displayScale = 1.5
        assertCloseLayoutUnavailable(runtime)
        XCTAssertFalse(runtime.isLayoutSettlementReceiptCurrent(receipt))
    }

    func testResolutionGenerationOverflowIsUnavailableEvenDuringLayout() async throws {
        let runtime = closeLayoutRuntime()
        _ = runtime.resolvedLayoutFrame(of: runtime.root)
        let receipt = try closeLayoutReceipt(runtime)
        var callbacks = 0
        runtime.root.onLayout = { [weak runtime] _ in
            guard let runtime else { return }
            callbacks += 1
            assertCloseLayoutUnavailable(runtime)
        }
        runtime.exhaustLayoutResolutionGenerationOnNextQueryForTesting()

        _ = runtime.resolvedLayoutFrame(of: runtime.root)
        XCTAssertEqual(callbacks, 1)
        assertCloseLayoutUnavailable(runtime)
        XCTAssertFalse(runtime.canPrepareLayoutSettlement)
        XCTAssertFalse(runtime.isLayoutSettlementReceiptCurrent(receipt))
        _ = runtime.resolvedLayoutFrame(of: runtime.root)
        assertCloseLayoutUnavailable(runtime)
    }
}

@MainActor
private func closeLayoutRuntime(width: Double = 200, height: Double = 100) -> RetainedViewRuntime {
    RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: width, height: height)))
}

@MainActor
private func closeLayoutDeferredScrollFixture() -> (
    runtime: RetainedViewRuntime, container: ViewNode, row: ViewNode,
    target: ViewNode, clock: RuntimeTestClock
) {
    let target = ViewNode(
        frame: Rect(x: 0, y: 200, width: 80, height: 20), preferredSize: Size(width: 80, height: 20))
    let row = ViewNode(
        preferredSize: Size(width: 80, height: 300), isHitTestVisible: false, children: [target])
    let preceding = (0..<10).map { _ in
        ViewNode(preferredSize: Size(width: 80, height: 40), isHitTestVisible: false)
    }
    let trailing = (0..<4).map { _ in
        ViewNode(preferredSize: Size(width: 80, height: 40), isHitTestVisible: false)
    }
    let container = ViewNode(
        frame: Rect(x: 0, y: 0, width: 100, height: 100), clipsToBounds: true,
        layoutMode: .lazyStack(.vertical(spacing: 0)), scrollAxis: .vertical,
        isHitTestVisible: false, children: preceding + [row] + trailing)
    let runtime = RetainedViewRuntime(
        root: ViewNode(
            frame: Rect(x: 0, y: 0, width: 100, height: 100), isHitTestVisible: false, children: [container]))
    let clock = RuntimeTestClock()
    runtime.clock = { clock.now }
    _ = runtime.renderScene()
    return (runtime, container, row, target, clock)
}

@MainActor
private func closeLayoutReceipt(
    _ runtime: RetainedViewRuntime, file: StaticString = #filePath, line: UInt = #line
) throws -> RetainedLayoutSettlementReceipt {
    guard case .settled(let receipt) = runtime.layoutSettlementStatus else {
        XCTFail("Expected a completed bounded layout receipt", file: file, line: line)
        throw CloseLayoutFixtureError.missingReceipt
    }
    return receipt
}

@MainActor
private func assertCloseLayoutUnsettled(
    _ runtime: RetainedViewRuntime, file: StaticString = #filePath, line: UInt = #line
) {
    guard case .unsettled = runtime.layoutSettlementStatus else {
        XCTFail("Expected unsettled layout without an implicit retry", file: file, line: line)
        return
    }
}

@MainActor
private func assertCloseLayoutUnavailable(
    _ runtime: RetainedViewRuntime, file: StaticString = #filePath, line: UInt = #line
) {
    guard case .unavailable = runtime.layoutSettlementStatus else {
        XCTFail("Expected unavailable layout proof, not a busy retry", file: file, line: line)
        return
    }
}

private enum CloseLayoutFixtureError: Error {
    case missingReceipt
}

@MainActor
private final class CloseLayoutReaderFixture {
    var bodyCount = 0
    var returnsEmpty = false
    var lease: CloseLayoutLease?
    var onBuild: ((RetainedViewRuntime, Size) -> Void)?

    func makeNode(builtSize: Size? = nil) -> ViewNode {
        let node = ViewNode()
        node.layoutFillAxes = .both
        node.geometryReaderBuiltSize = builtSize
        node.retainedSubtreeBuildLease = lease
        node.geometryReaderBuild = { [self] runtime, slot in
            bodyCount += 1
            onBuild?(runtime, slot)
            return returnsEmpty ? [] : [makeNode(builtSize: slot)]
        }
        return node
    }
}

@MainActor
private final class CloseLayoutLease: RetainedSubtreeBuildLease {
    var allowsBuild = true
    var readCount = 0
    var beginCount = 0

    var canBuild: Bool {
        readCount += 1
        return allowsBuild
    }

    func beginBuild() -> (any RetainedBuildEpoch)? {
        beginCount += 1
        return CloseLayoutEpoch()
    }
}

@MainActor
private final class CloseLayoutEpoch: RetainedBuildEpoch {
    var canAdopt = true
    func supersede() { canAdopt = false }
    func willAdopt() -> Bool { canAdopt }
    func commit() {}
    func abandon() {}
    func finishAfterCallbacks() {}
}

// Hashable's witness is deliberately not actor-isolated. All fixture access
// is synchronous on the test's main actor; no global/static counter is shared.
private final class CloseLayoutHashCounter {
    var calls = 0
}

private struct CloseLayoutHashKey: Hashable {
    let counter: CloseLayoutHashCounter
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.counter === rhs.counter }
    func hash(into hasher: inout Hasher) {
        counter.calls += 1
        hasher.combine(7)
    }
}

@MainActor
private final class CloseLayoutLifetimeWitness {
    weak var runtime: RetainedViewRuntime?
    weak var payload: CloseLayoutPayload?
}

private final class CloseLayoutPayload {}

@MainActor
private func makeCloseLayoutLifetimeReceipt(witness: CloseLayoutLifetimeWitness) throws
    -> RetainedLayoutSettlementReceipt
{
    let runtime = closeLayoutRuntime()
    let payload = CloseLayoutPayload()
    witness.runtime = runtime
    witness.payload = payload
    runtime.root.onLayout = { [payload] _ in withExtendedLifetime(payload) {} }
    _ = runtime.resolvedLayoutFrame(of: runtime.root)
    return try closeLayoutReceipt(runtime)
}

// Host/native fixtures are appended so the earlier layout-receipt cases stay unchanged.

@MainActor
private struct CloseHostHarness {
    let host: WinSwiftUIWindowHost
    let renderer: FakeRenderBackend
    let batchRenderer: FakeBatchRenderBackend
    var window: Win32Window { host.platformWindow }
}

@MainActor
private func makeCloseHost<Content: View>(
    _ content: Content, isDocumentGroup: Bool = false, clock: RuntimeTestClock? = nil
) throws -> CloseHostHarness {
    let size = IntSize(width: 360, height: 220)
    let renderer = FakeRenderBackend()
    let batchRenderer = FakeBatchRenderBackend()
    let window = Win32Window(title: "Native close finalization", clientSize: size)
    window.postsQuitMessageOnDestroy = false
    window.testScaleFactorOverride = 1
    let host = WinSwiftUIWindowHost(
        configuration: WindowGroupConfiguration(
            title: "Native close finalization", size: size, clearColor: .black,
            content: [AnyView(content)], isDocumentGroup: isDocumentGroup),
        platformWindow: window, renderer: renderer, batchRenderer: batchRenderer,
        surfaceDescriptorProvider: { window in
            guard let handle = window.nativeHandle else { return nil }
            return SurfaceDescriptor(
                windowHandle: handle, pixelSize: window.currentClientSize(),
                scaleFactor: window.effectiveScaleFactor)
        }, startupProbeConfiguration: nil)
    if let clock {
        host.frameClock = { clock.now }
        host.hostedRuntime.clock = { clock.now }
    }
    do {
        // create() does not show the owned HWND or enter a message loop.
        try window.create()
    } catch {
        window.destroyForFailedStartup()
        throw XCTSkip("This environment cannot create an owned test window: \(error)")
    }
    host.resetObservabilityCounters()
    return CloseHostHarness(host: host, renderer: renderer, batchRenderer: batchRenderer)
}

@MainActor
private func destroyCloseHostWindow(_ window: Win32Window) {
    if let raw = window.nativeHandle?.rawPointer {
        DestroyWindow(HWND(bitPattern: Int(bitPattern: raw)))
    }
}

@MainActor
private func closeHostTicket(_ host: WinSwiftUIWindowHost) throws -> Win32CloseTicket {
    let registration = try XCTUnwrap(host.windowCloseRegistration)
    return try XCTUnwrap(registration.makeTicket(intentID: UUID()))
}

@MainActor
private func assertCloseHostStillAlive(
    _ harness: CloseHostHarness, file: StaticString = #filePath, line: UInt = #line
) {
    XCTAssertNotNil(harness.window.nativeHandle, file: file, line: line)
    XCTAssertEqual(harness.renderer.detachCount, 0, file: file, line: line)
    XCTAssertEqual(harness.batchRenderer.detachCount, 0, file: file, line: line)
}

@MainActor
private final class CloseHostCalls {
    var votes = 0
    var preparations = 0
    var validations = 0
    var revocations = 0
    var finishes: [Win32CloseAttemptOutcome] = []
    var attempts: [Foundation.UUID] = []
}

@MainActor
private final class CloseHostLease: Win32CloseCommitLease {
    let calls: CloseHostCalls
    var decision: Win32CloseCommitDecision = .reserved
    var onValidate: (@MainActor () -> Void)?
    var onFinish: (@MainActor (Win32CloseAttemptOutcome) -> Void)?

    init(calls: CloseHostCalls) { self.calls = calls }

    func validateAndReserve() -> Win32CloseCommitDecision {
        calls.validations += 1
        onValidate?()
        return decision
    }

    func finish(with outcome: Win32CloseAttemptOutcome) {
        calls.finishes.append(outcome)
        onFinish?(outcome)
    }
}

@MainActor
private final class CloseHostParticipant: WindowCloseParticipant {
    let calls: CloseHostCalls
    let lease: CloseHostLease
    private(set) var isRevoked = false
    var onVote: (@MainActor (Win32CloseAttempt) -> Bool)?
    var onPrepare: (@MainActor (Win32CloseAttempt) -> Void)?

    init(calls: CloseHostCalls = CloseHostCalls()) {
        self.calls = calls
        lease = CloseHostLease(calls: calls)
    }

    func windowShouldClose(_ attempt: Win32CloseAttempt) -> Bool {
        calls.votes += 1
        calls.attempts.append(attempt.id)
        return !isRevoked && (onVote?(attempt) ?? true)
    }

    func prepareCloseCommit(for attempt: Win32CloseAttempt) -> Win32CloseCommitPreparation {
        calls.preparations += 1
        guard !isRevoked else { return .unavailable }
        onPrepare?(attempt)
        return .ready(lease)
    }

    func revokeCloseParticipation() {
        isRevoked = true
        calls.revocations += 1
    }
}

@MainActor
private final class CloseHostNeutral: PlatformWindowHost {
    var vote: (@MainActor (Win32Window) -> Bool)?
    var onWillClose: (@MainActor () -> Void)?
    private(set) var votes = 0
    private(set) var closes = 0

    func platformWindowShouldClose(_ window: any PlatformWindow) -> Bool {
        votes += 1
        guard let concrete = window as? Win32Window else { return false }
        return vote?(concrete) ?? true
    }

    func platformWindow(_ window: any PlatformWindow, didReceive event: PlatformWindowEvent) {
        if case .willClose = event {
            closes += 1
            onWillClose?()
        }
    }
}

@MainActor
private final class CloseHostModel: ObservableObject {
    @Published var revision = 0
    var bodyCalls = 0
}

@MainActor
private struct CloseHostObservedContent: View {
    @ObservedObject var model: CloseHostModel

    var body: some View {
        model.bodyCalls += 1
        return Text("Revision \(model.revision)")
    }
}

@MainActor
private final class CloseHostOwnerBox {
    var host: WinSwiftUIWindowHost?
    var participant: CloseHostParticipant?
}

@MainActor
private final class CloseHostWeakOwners {
    weak var host: WinSwiftUIWindowHost?
    weak var participant: CloseHostParticipant?
}

@MainActor
private func makeCloseHostWithReleasableOwners(
    box: CloseHostOwnerBox, witness: CloseHostWeakOwners, calls: CloseHostCalls
) throws -> Win32Window {
    let harness = try makeCloseHost(Text("Weak close owners"))
    let participant = CloseHostParticipant(calls: calls)
    XCTAssertTrue(harness.host.setWindowCloseParticipant(participant))
    box.host = harness.host
    box.participant = participant
    witness.host = harness.host
    witness.participant = participant
    return harness.window
}

/// These source fixtures use owned hidden HWNDs and fake presentation only.
/// A tagged attempt is the production native path; no test fabricates an
/// attempt, bypasses final validation, or pumps an unbounded message loop.
@MainActor
extension WindowCloseFinalizationTests {
    func testNativeHostFinalAuthorityClosesAnOrdinaryTaggedRequest() async throws {
        let harness = try makeCloseHost(Text("Ordinary close"))
        defer { destroyCloseHostWindow(harness.window) }
        let participant = CloseHostParticipant()
        XCTAssertTrue(harness.host.setWindowCloseParticipant(participant))
        let registration = try XCTUnwrap(harness.host.windowCloseRegistration)
        let ticket = try closeHostTicket(harness.host)

        XCTAssertEqual(harness.window.attemptClose(ticket: ticket), .closed)

        XCTAssertNil(harness.window.nativeHandle)
        XCTAssertNil(harness.window.activeCloseAttempt)
        XCTAssertEqual(participant.calls.votes, 1)
        XCTAssertEqual(participant.calls.preparations, 1)
        XCTAssertEqual(participant.calls.validations, 1)
        XCTAssertEqual(participant.calls.finishes, [.closed])
        XCTAssertEqual(participant.calls.revocations, 1)
        XCTAssertTrue(registration.isRevoked)
        XCTAssertFalse(ticket.isCurrent)
        XCTAssertEqual(harness.renderer.detachCount, 1)
        XCTAssertEqual(harness.batchRenderer.detachCount, 1)
    }

    func testNativeInitialDisabledPolicyVetoesBeforeParticipantPreparation() async throws {
        let harness = try makeCloseHost(Text("Disabled close").windowDismissBehavior(.disabled))
        defer { destroyCloseHostWindow(harness.window) }
        let participant = CloseHostParticipant()
        XCTAssertTrue(harness.host.setWindowCloseParticipant(participant))
        let ticket = try closeHostTicket(harness.host)

        XCTAssertEqual(harness.window.attemptClose(ticket: ticket), .vetoed)

        assertCloseHostStillAlive(harness)
        XCTAssertEqual(participant.calls.votes, 0)
        XCTAssertEqual(participant.calls.preparations, 0)
        XCTAssertTrue(participant.calls.finishes.isEmpty)
        XCTAssertFalse(ticket.isCurrent)
    }

    func testNativeLateNeutralPolicyMutationInvalidatesOriginalReceipt() async throws {
        let harness = try makeCloseHost(Text("Late policy"))
        defer { destroyCloseHostWindow(harness.window) }
        let runtime = harness.host.hostedRuntime
        let participant = CloseHostParticipant()
        let neutral = CloseHostNeutral()
        var preflightPass: UInt64?
        XCTAssertTrue(harness.host.setWindowCloseParticipant(participant))
        neutral.vote = { _ in
            preflightPass = runtime.layoutPassID
            runtime.root.windowDismissBehavior = .disabled
            return true
        }
        harness.window.setPlatformWindowHost(neutral)
        let ticket = try closeHostTicket(harness.host)

        XCTAssertEqual(harness.window.attemptClose(ticket: ticket), .unavailable)

        assertCloseHostStillAlive(harness)
        XCTAssertEqual(runtime.windowDismissalBehavior, .disabled)
        XCTAssertEqual(runtime.layoutPassID, preflightPass)
        XCTAssertEqual(participant.calls.votes, 1)
        XCTAssertEqual(participant.calls.preparations, 0)
        XCTAssertEqual(neutral.votes, 1)
        XCTAssertFalse(ticket.isCurrent)
    }

    func testNativeLateNeutralGeometryMutationCannotRefreshTheReceipt() async throws {
        let harness = try makeCloseHost(Text("Late geometry"))
        defer { destroyCloseHostWindow(harness.window) }
        let runtime = harness.host.hostedRuntime
        let participant = CloseHostParticipant()
        let neutral = CloseHostNeutral()
        var preflightPass: UInt64?
        XCTAssertTrue(harness.host.setWindowCloseParticipant(participant))
        neutral.vote = { _ in
            preflightPass = runtime.layoutPassID
            runtime.root.frame.size.width += 31
            return true
        }
        harness.window.setPlatformWindowHost(neutral)
        let ticket = try closeHostTicket(harness.host)

        XCTAssertEqual(harness.window.attemptClose(ticket: ticket), .unavailable)

        assertCloseHostStillAlive(harness)
        XCTAssertEqual(runtime.layoutPassID, preflightPass)
        XCTAssertEqual(participant.calls.preparations, 0)
        XCTAssertEqual(participant.calls.validations, 0)
        XCTAssertFalse(ticket.isCurrent)
        assertCloseLayoutUnsettled(runtime)
    }

    func testNativeLateObservedMutationDefersWithoutASecondFlush() async throws {
        let model = CloseHostModel()
        let harness = try makeCloseHost(CloseHostObservedContent(model: model))
        defer { destroyCloseHostWindow(harness.window) }
        let participant = CloseHostParticipant()
        let neutral = CloseHostNeutral()
        var bodyCallsAtLastVote = 0
        var preflightPass: UInt64?
        XCTAssertTrue(harness.host.setWindowCloseParticipant(participant))
        neutral.vote = { _ in
            bodyCallsAtLastVote = model.bodyCalls
            preflightPass = harness.host.hostedRuntime.layoutPassID
            model.revision += 1
            return true
        }
        harness.window.setPlatformWindowHost(neutral)
        let ticket = try closeHostTicket(harness.host)

        XCTAssertEqual(harness.window.attemptClose(ticket: ticket), .busy(.buildsNotSettled))

        assertCloseHostStillAlive(harness)
        XCTAssertEqual(model.bodyCalls, bodyCallsAtLastVote)
        XCTAssertEqual(harness.host.hostedRuntime.layoutPassID, preflightPass)
        XCTAssertEqual(harness.host.executedReloadCount, 0)
        XCTAssertEqual(participant.calls.preparations, 0)
        XCTAssertTrue(participant.calls.finishes.isEmpty)
        XCTAssertTrue(ticket.isCurrent, "A busy request retains its unconsumed intent")
    }

    func testNativeRepeatedConcreteVoteReusesTheFirstLayoutReceipt() async throws {
        let harness = try makeCloseHost(Text("Repeated concrete preflight"))
        defer { destroyCloseHostWindow(harness.window) }
        let runtime = harness.host.hostedRuntime
        let participant = CloseHostParticipant()
        let neutral = CloseHostNeutral()
        var repeatedVotes: [Bool] = []
        var originalPass: UInt64?
        var passAfterRepeatedVotes: UInt64?
        XCTAssertTrue(harness.host.setWindowCloseParticipant(participant))
        neutral.vote = { window in
            originalPass = runtime.layoutPassID
            repeatedVotes.append(harness.host.windowShouldClose(window))
            repeatedVotes.append(harness.host.windowShouldClose(window))
            passAfterRepeatedVotes = runtime.layoutPassID
            return true
        }
        harness.window.setPlatformWindowHost(neutral)
        let ticket = try closeHostTicket(harness.host)

        XCTAssertEqual(harness.window.attemptClose(ticket: ticket), .closed)

        XCTAssertEqual(repeatedVotes, [true, true])
        XCTAssertEqual(passAfterRepeatedVotes, originalPass)
        XCTAssertEqual(participant.calls.votes, 1, "The same attempt must not invoke the participant twice")
        XCTAssertEqual(participant.calls.preparations, 1)
        XCTAssertEqual(participant.calls.finishes, [.closed])
    }

    func testNativeRepeatedConcreteVoteCannotRecaptureAStaleReceipt() async throws {
        let harness = try makeCloseHost(Text("Stale repeated preflight"))
        defer { destroyCloseHostWindow(harness.window) }
        let runtime = harness.host.hostedRuntime
        let participant = CloseHostParticipant()
        let neutral = CloseHostNeutral()
        var repeatedVotes: [Bool] = []
        var originalPass: UInt64?
        XCTAssertTrue(harness.host.setWindowCloseParticipant(participant))
        neutral.vote = { window in
            originalPass = runtime.layoutPassID
            runtime.root.frame.size.height += 17
            repeatedVotes.append(harness.host.windowShouldClose(window))
            repeatedVotes.append(harness.host.windowShouldClose(window))
            return true
        }
        harness.window.setPlatformWindowHost(neutral)
        let ticket = try closeHostTicket(harness.host)

        XCTAssertEqual(harness.window.attemptClose(ticket: ticket), .unavailable)

        assertCloseHostStillAlive(harness)
        XCTAssertEqual(repeatedVotes, [false, false])
        XCTAssertEqual(runtime.layoutPassID, originalPass)
        XCTAssertEqual(participant.calls.votes, 1)
        XCTAssertEqual(participant.calls.preparations, 0)
        XCTAssertFalse(ticket.isCurrent)
    }

    func testNativeAttemptPinsWeakActualHostAndParticipantThroughReservation() async throws {
        let box = CloseHostOwnerBox()
        let witness = CloseHostWeakOwners()
        let calls = CloseHostCalls()
        let window = try makeCloseHostWithReleasableOwners(box: box, witness: witness, calls: calls)
        defer { destroyCloseHostWindow(window) }
        let neutral = CloseHostNeutral()
        var observations: [String] = []
        neutral.vote = { _ in
            box.host = nil
            box.participant = nil
            XCTAssertNotNil(witness.host)
            XCTAssertNotNil(witness.participant)
            observations.append("last-vote")
            return true
        }
        neutral.onWillClose = {
            XCTAssertNotNil(witness.host)
            XCTAssertNotNil(witness.participant)
            observations.append("destroy")
        }
        box.participant?.lease.onValidate = {
            XCTAssertNotNil(witness.host)
            XCTAssertNotNil(witness.participant)
            observations.append("reserve")
        }
        box.participant?.lease.onFinish = { outcome in
            XCTAssertEqual(outcome, .closed)
            XCTAssertNotNil(witness.host)
            XCTAssertNotNil(witness.participant)
            observations.append("finish")
        }
        window.setPlatformWindowHost(neutral)
        let ticket = try closeHostTicket(try XCTUnwrap(box.host))

        // The call receiver retains only the native window. Neither helper,
        // delegate callback, nor lease captures a strong host or participant.
        XCTAssertEqual(window.attemptClose(ticket: ticket), .closed)

        XCTAssertEqual(observations, ["last-vote", "reserve", "destroy", "finish"])
        XCTAssertEqual(calls.finishes, [.closed])
        XCTAssertEqual(calls.revocations, 1)
        XCTAssertNil(witness.host)
        XCTAssertNil(witness.participant)
        XCTAssertNil(window.nativeHandle)
    }

    func testNativeParticipantReplacementDuringItsVoteInvalidatesTheAttempt() async throws {
        let harness = try makeCloseHost(Text("Replace during participant vote"))
        defer { destroyCloseHostWindow(harness.window) }
        let original = CloseHostParticipant()
        let replacement = CloseHostParticipant()
        XCTAssertTrue(harness.host.setWindowCloseParticipant(original))
        original.onVote = { _ in
            XCTAssertTrue(harness.host.setWindowCloseParticipant(replacement))
            return true
        }
        let ticket = try closeHostTicket(harness.host)

        XCTAssertEqual(harness.window.attemptClose(ticket: ticket), .unavailable)

        assertCloseHostStillAlive(harness)
        XCTAssertEqual(original.calls.votes, 1)
        XCTAssertEqual(original.calls.revocations, 1)
        XCTAssertEqual(original.calls.preparations, 0)
        XCTAssertEqual(replacement.calls.votes, 0)
        XCTAssertEqual(replacement.calls.preparations, 0)
        XCTAssertFalse(ticket.isCurrent)
        XCTAssertEqual(harness.window.attemptClose(ticket: try closeHostTicket(harness.host)), .closed)
        XCTAssertEqual(replacement.calls.finishes, [.closed])
    }

    func testNativeLateParticipantReplacementDoesNotAdoptTheNewSlotInTheSameAttempt() async throws {
        let harness = try makeCloseHost(Text("Replace during last delegate vote"))
        defer { destroyCloseHostWindow(harness.window) }
        let original = CloseHostParticipant()
        let replacement = CloseHostParticipant()
        let neutral = CloseHostNeutral()
        var repeatedVote: Bool?
        var passBeforeReplacement: UInt64?
        XCTAssertTrue(harness.host.setWindowCloseParticipant(original))
        neutral.vote = { window in
            passBeforeReplacement = harness.host.hostedRuntime.layoutPassID
            XCTAssertTrue(harness.host.setWindowCloseParticipant(replacement))
            repeatedVote = harness.host.windowShouldClose(window)
            return true
        }
        harness.window.setPlatformWindowHost(neutral)
        let ticket = try closeHostTicket(harness.host)

        XCTAssertEqual(harness.window.attemptClose(ticket: ticket), .unavailable)

        assertCloseHostStillAlive(harness)
        XCTAssertEqual(repeatedVote, false)
        XCTAssertEqual(harness.host.hostedRuntime.layoutPassID, passBeforeReplacement)
        XCTAssertEqual(original.calls.revocations, 1)
        XCTAssertEqual(original.calls.preparations, 0)
        XCTAssertEqual(replacement.calls.votes, 0)
        XCTAssertEqual(replacement.calls.preparations, 0)
        XCTAssertFalse(ticket.isCurrent)
    }
}

@MainActor
extension WindowCloseFinalizationTests {
    func testNativeParticipantReplacementIsRefusedInsideFinalReservation() async throws {
        let harness = try makeCloseHost(Text("Reserved participant slot"))
        defer { destroyCloseHostWindow(harness.window) }
        let participant = CloseHostParticipant()
        let replacement = CloseHostParticipant()
        var replacementResults: [Bool] = []
        XCTAssertTrue(harness.host.setWindowCloseParticipant(participant))
        participant.lease.onValidate = {
            replacementResults.append(harness.host.setWindowCloseParticipant(replacement))
            replacementResults.append(harness.host.setWindowCloseParticipant(nil))
        }
        let ticket = try closeHostTicket(harness.host)

        XCTAssertEqual(harness.window.attemptClose(ticket: ticket), .closed)

        XCTAssertEqual(replacementResults, [false, false])
        XCTAssertEqual(participant.calls.validations, 1)
        XCTAssertEqual(participant.calls.finishes, [.closed])
        XCTAssertEqual(participant.calls.revocations, 1)
        XCTAssertEqual(replacement.calls.votes, 0)
        XCTAssertEqual(replacement.calls.revocations, 0)
    }

    func testNativePreparedLeaseStillFinishesOnceAfterPreparationChangesGeometry() async throws {
        let harness = try makeCloseHost(Text("Preparation changes geometry"))
        defer { destroyCloseHostWindow(harness.window) }
        let runtime = harness.host.hostedRuntime
        let participant = CloseHostParticipant()
        var passAtPreparation: UInt64?
        XCTAssertTrue(harness.host.setWindowCloseParticipant(participant))
        participant.onPrepare = { _ in
            passAtPreparation = runtime.layoutPassID
            runtime.root.frame.size.width += 23
        }
        let ticket = try closeHostTicket(harness.host)

        XCTAssertEqual(harness.window.attemptClose(ticket: ticket), .unavailable)

        assertCloseHostStillAlive(harness)
        XCTAssertEqual(runtime.layoutPassID, passAtPreparation)
        XCTAssertEqual(participant.calls.preparations, 1)
        XCTAssertEqual(participant.calls.validations, 0)
        XCTAssertEqual(participant.calls.finishes, [.unavailable])
        XCTAssertEqual(participant.calls.revocations, 0)
        XCTAssertFalse(ticket.isCurrent)
    }

    func testNativePreparedLeaseStillFinishesOnceAfterPreparationQueuesAnObservedBatch() async throws {
        let model = CloseHostModel()
        let harness = try makeCloseHost(CloseHostObservedContent(model: model))
        defer { destroyCloseHostWindow(harness.window) }
        let participant = CloseHostParticipant()
        var bodyCallsAtPreparation = 0
        XCTAssertTrue(harness.host.setWindowCloseParticipant(participant))
        participant.onPrepare = { _ in
            bodyCallsAtPreparation = model.bodyCalls
            model.revision += 1
        }
        let ticket = try closeHostTicket(harness.host)

        XCTAssertEqual(harness.window.attemptClose(ticket: ticket), .busy(.buildsNotSettled))

        assertCloseHostStillAlive(harness)
        XCTAssertEqual(model.bodyCalls, bodyCallsAtPreparation)
        XCTAssertEqual(harness.host.executedReloadCount, 0)
        XCTAssertEqual(participant.calls.preparations, 1)
        XCTAssertEqual(participant.calls.validations, 0)
        XCTAssertEqual(participant.calls.finishes, [.busy(.buildsNotSettled)])
        XCTAssertEqual(participant.calls.revocations, 0)
        XCTAssertTrue(ticket.isCurrent)
    }

    func testNativeFinalValidationDoesNotInvokeBodyLayoutOrPresentationCallbacks() async throws {
        let model = CloseHostModel()
        let harness = try makeCloseHost(CloseHostObservedContent(model: model))
        let runtime = harness.host.hostedRuntime
        defer {
            runtime.root.onLayout = nil
            destroyCloseHostWindow(harness.window)
        }
        let participant = CloseHostParticipant()
        var layoutCalls = 0
        var countsAtPreparation: (body: Int, layout: Int, pass: UInt64)?
        let frameCount = harness.renderer.renderedFrames.count
        let sceneCount = harness.batchRenderer.renderedScenes.count
        runtime.root.onLayout = { _ in layoutCalls += 1 }
        runtime.root.frame.size.width += 1
        XCTAssertTrue(harness.host.setWindowCloseParticipant(participant))
        participant.onPrepare = { _ in
            countsAtPreparation = (model.bodyCalls, layoutCalls, runtime.layoutPassID)
        }
        participant.lease.onValidate = {
            XCTAssertEqual(model.bodyCalls, countsAtPreparation?.body)
            XCTAssertEqual(layoutCalls, countsAtPreparation?.layout)
            XCTAssertEqual(runtime.layoutPassID, countsAtPreparation?.pass)
        }
        // Stop before destruction so teardown callbacks cannot muddy the
        // boundary being measured: preparation -> final checks -> finish.
        participant.lease.decision = .vetoed
        let ticket = try closeHostTicket(harness.host)

        XCTAssertEqual(harness.window.attemptClose(ticket: ticket), .vetoed)

        assertCloseHostStillAlive(harness)
        XCTAssertNotNil(countsAtPreparation)
        XCTAssertGreaterThan(layoutCalls, 0)
        XCTAssertEqual(model.bodyCalls, countsAtPreparation?.body)
        XCTAssertEqual(layoutCalls, countsAtPreparation?.layout)
        XCTAssertEqual(runtime.layoutPassID, countsAtPreparation?.pass)
        XCTAssertEqual(harness.renderer.renderedFrames.count, frameCount)
        XCTAssertEqual(harness.batchRenderer.renderedScenes.count, sceneCount)
        XCTAssertEqual(participant.calls.validations, 1)
        XCTAssertEqual(participant.calls.finishes, [.vetoed])
    }

    func testNativePendingLiveResizeRejectsCloseWithoutApplyingTheResize() async throws {
        let harness = try makeCloseHost(Text("Pending live resize"))
        defer { destroyCloseHostWindow(harness.window) }
        let participant = CloseHostParticipant()
        XCTAssertTrue(harness.host.setWindowCloseParticipant(participant))
        let runtime = harness.host.hostedRuntime
        let rootSize = runtime.root.frame.size
        let layoutPass = runtime.layoutPassID
        let resizedSurfaces = harness.batchRenderer.resizedSizes.count
        let resizeRebuildsBefore = harness.host.executedResizeRebuildCount
        harness.window.setModalLoopStateForTesting(isInSizeMove: true)
        harness.host.window(harness.window, didResizeTo: IntSize(width: 500, height: 300))
        // The normal native exit callback would apply its final size. Leave
        // that stored host work pending while clearing only the test flag.
        harness.window.setModalLoopStateForTesting(isInSizeMove: false)
        let ticket = try closeHostTicket(harness.host)

        XCTAssertEqual(harness.window.attemptClose(ticket: ticket), .unavailable)

        assertCloseHostStillAlive(harness)
        XCTAssertEqual(runtime.root.frame.size, rootSize)
        XCTAssertEqual(runtime.layoutPassID, layoutPass)
        XCTAssertEqual(harness.host.executedResizeRebuildCount, resizeRebuildsBefore)
        XCTAssertEqual(harness.batchRenderer.resizedSizes.count, resizedSurfaces)
        XCTAssertEqual(participant.calls.votes, 0)
        XCTAssertEqual(participant.calls.preparations, 0)
        XCTAssertFalse(ticket.isCurrent)
    }

    func testNativeActiveRetainedBuildReportsBusyWithoutRunningPreflightLayout() async throws {
        let harness = try makeCloseHost(Text("Active retained build"))
        defer { destroyCloseHostWindow(harness.window) }
        let participant = CloseHostParticipant()
        XCTAssertTrue(harness.host.setWindowCloseParticipant(participant))
        let runtime = harness.host.hostedRuntime
        let coordinator = runtime.retainedBuildCoordinator
        let layoutPass = runtime.layoutPassID
        let ticket = try closeHostTicket(harness.host)
        _ = try XCTUnwrap(coordinator.beginBuild())
        defer { coordinator.finishBuild() }

        XCTAssertEqual(harness.window.attemptClose(ticket: ticket), .busy(.buildsNotSettled))

        assertCloseHostStillAlive(harness)
        XCTAssertEqual(runtime.layoutPassID, layoutPass)
        XCTAssertEqual(participant.calls.votes, 0)
        XCTAssertEqual(participant.calls.preparations, 0)
        XCTAssertTrue(ticket.isCurrent)
    }

    func testNativeUnavailableLayoutProofDoesNotBecomeAnAutomaticBusyRetry() async throws {
        let harness = try makeCloseHost(Text("Unproven layout"))
        let runtime = harness.host.hostedRuntime
        defer {
            runtime.root.onLayout = nil
            destroyCloseHostWindow(harness.window)
        }
        let participant = CloseHostParticipant()
        var layoutCalls = 0
        XCTAssertTrue(harness.host.setWindowCloseParticipant(participant))
        runtime.root.onLayout = { [weak runtime] _ in
            layoutCalls += 1
            // No unmutated final pass exists. A close query may not loop to
            // manufacture one, clear dirty flags, or turn this into a wake.
            runtime?.root.frame.size.width += 1
        }
        runtime.root.frame.size.width += 1
        let ticket = try closeHostTicket(harness.host)

        XCTAssertEqual(harness.window.attemptClose(ticket: ticket), .unavailable)

        assertCloseHostStillAlive(harness)
        XCTAssertEqual(layoutCalls, 1)
        assertCloseLayoutUnavailable(runtime)
        XCTAssertEqual(participant.calls.votes, 0)
        XCTAssertEqual(participant.calls.preparations, 0)
        XCTAssertFalse(ticket.isCurrent)
    }

    func testNativeRevokedHostRegistrationNeverRunsTheParticipantAgain() async throws {
        let harness = try makeCloseHost(Text("Revoked close authority"))
        defer { destroyCloseHostWindow(harness.window) }
        let participant = CloseHostParticipant()
        XCTAssertTrue(harness.host.setWindowCloseParticipant(participant))
        let registration = try XCTUnwrap(harness.host.windowCloseRegistration)
        let ticket = try closeHostTicket(harness.host)
        let layoutPass = harness.host.hostedRuntime.layoutPassID
        registration.revoke()

        XCTAssertEqual(harness.window.attemptClose(ticket: ticket), .unavailable)

        assertCloseHostStillAlive(harness)
        XCTAssertEqual(harness.host.hostedRuntime.layoutPassID, layoutPass)
        XCTAssertEqual(participant.calls.votes, 0)
        XCTAssertEqual(participant.calls.preparations, 0)
        XCTAssertTrue(participant.calls.finishes.isEmpty)
        XCTAssertNil(registration.makeTicket(intentID: UUID()))
    }

    func testNativeParticipantBusyAndUnavailableMarkersRemainDistinct() async throws {
        let harness = try makeCloseHost(Text("Participant rejection reasons"))
        defer { destroyCloseHostWindow(harness.window) }
        let participant = CloseHostParticipant()
        XCTAssertTrue(harness.host.setWindowCloseParticipant(participant))
        participant.onVote = { attempt in
            attempt.deferUntilReady(.ownerOperation)
            return false
        }
        let ticket = try closeHostTicket(harness.host)

        XCTAssertEqual(harness.window.attemptClose(ticket: ticket), .busy(.ownerOperation))
        XCTAssertTrue(ticket.isCurrent)
        participant.onVote = { attempt in
            attempt.rejectAsUnavailable()
            return false
        }
        XCTAssertEqual(harness.window.attemptClose(ticket: ticket), .unavailable)

        assertCloseHostStillAlive(harness)
        XCTAssertEqual(participant.calls.votes, 2)
        XCTAssertEqual(Set(participant.calls.attempts).count, 2, "A retry owns a fresh native attempt")
        XCTAssertEqual(participant.calls.preparations, 0)
        XCTAssertTrue(participant.calls.finishes.isEmpty)
        XCTAssertFalse(ticket.isCurrent)
    }
}

@MainActor
private final class CloseHostReleaseProbe {
    private let onRelease: @MainActor () -> Void
    init(_ onRelease: @escaping @MainActor () -> Void) { self.onRelease = onRelease }
    isolated deinit { onRelease() }
}

@MainActor
private final class CloseHostExpiredUndoTarget {}

@MainActor
private final class CloseHostTeardownCapture {
    var payloadBinding: Binding<CloseHostReleaseProbe?>?
    var numberBinding: Binding<Int>?
    weak var manager: WinSwiftUI.UndoManager?
    weak var statePayload: CloseHostReleaseProbe?
    weak var editorPayload: CloseHostReleaseProbe?
    weak var undoTarget: CloseHostExpiredUndoTarget?
    var text = "a"
    var writes: [String] = []
    var releases: [String] = []
    var revokedAtRelease: [Bool] = []
}

@MainActor
private struct CloseHostTeardownContent: View {
    @Environment(\.undoManager) private var manager
    @State private var payload: CloseHostReleaseProbe? = nil
    @State private var number = 7
    let capture: CloseHostTeardownCapture

    var body: some View {
        capture.payloadBinding = $payload
        capture.numberBinding = $number
        capture.manager = manager
        let text = Binding<String>(
            get: { [capture] in capture.text },
            set: { [capture] value in
                capture.text = value
                capture.writes.append(value)
            })
        return VStack {
            TextField("Text", text: text)
                .accessibilityIdentifier("close.teardown.editor")
                .frame(width: 280, height: 44)
            Text(payload == nil ? "Empty" : "Owned")
            Text(String(number))
        }
    }
}

@MainActor
private func closeHostEditor(in runtime: RetainedViewRuntime) throws -> ViewNode {
    var pending = [runtime.root]
    while let node = pending.popLast() {
        if node.accessibilityIdentifier == "close.teardown.editor",
            node.accessibilityTraits.contains(.isTextInput)
        {
            return node
        }
        pending.append(contentsOf: node.children)
    }
    return try XCTUnwrap(nil, "The teardown fixture must build its real retained editor")
}

@MainActor
private func installCloseHostStateRelease(
    capture: CloseHostTeardownCapture, participant: CloseHostParticipant,
    manager: WinSwiftUI.UndoManager, escaped: Binding<Int>
) throws {
    let binding = try XCTUnwrap(capture.payloadBinding)
    let payload = CloseHostReleaseProbe { [weak capture, weak participant, weak manager] in
        capture?.releases.append("state")
        capture?.revokedAtRelease.append(participant?.isRevoked == true)
        escaped.wrappedValue = 91
        // The editor session must already reject replay even if its history
        // has not yet been purged when mounted State releases this payload.
        manager?.undo()
    }
    capture.statePayload = payload
    binding.wrappedValue = payload
}

@MainActor
private func installCloseHostEditorRelease(
    capture: CloseHostTeardownCapture, participant: CloseHostParticipant,
    manager: WinSwiftUI.UndoManager, escaped: Binding<Int>
) {
    let target = CloseHostExpiredUndoTarget()
    let payload = CloseHostReleaseProbe { [weak capture, weak participant] in
        capture?.releases.append("editor")
        capture?.revokedAtRelease.append(participant?.isRevoked == true)
        escaped.wrappedValue = 92
    }
    capture.undoTarget = target
    capture.editorPayload = payload
    manager.registerUndo(withTarget: target) { _ in withExtendedLifetime(payload) {} }
}

@MainActor
private func withCloseHostTextLayout(_ body: () throws -> Void) throws {
    NativeTextRenderer.testingOverrides.layout = { text, style, _, _ in
        let glyphs = Array(text).enumerated().map { index, character in
            NativeTextGlyphLayout(
                character: character, origin: Point(x: Double(index) * 9, y: 0), advance: 9,
                glyphID: UInt32(index + 1), fontFamily: style.fontFamily, weight: style.weight,
                fontSize: style.nativeFontPixelSize, sourceIndex: index)
        }
        let size = Size(width: Double(max(text.count, 1)) * 9, height: max(style.nativeFontPixelSize, 1))
        return NativeTextLayoutResult(
            lines: [NativeTextLineLayout(text: text, width: size.width, height: size.height, glyphs: glyphs)],
            contentSize: size, measuredSize: size)
    }
    defer { NativeTextRenderer.resetTestingOverrides() }
    try body()
}

@MainActor
extension WindowCloseFinalizationTests {
    func testNativeTeardownRevokesParticipantBeforeStateAndEditorCaptureRelease() async throws {
        try withCloseHostTextLayout {
            let capture = CloseHostTeardownCapture()
            let clock = RuntimeTestClock()
            clock.now = 7_000
            let harness = try makeCloseHost(CloseHostTeardownContent(capture: capture), clock: clock)
            defer { destroyCloseHostWindow(harness.window) }
            let participant = CloseHostParticipant()
            XCTAssertTrue(harness.host.setWindowCloseParticipant(participant))
            let runtime = harness.host.hostedRuntime
            runtime.requestFocus(try closeHostEditor(in: runtime))
            harness.host.window(harness.window, didInputText: "b")
            harness.host.windowNeedsDisplay(harness.window)
            let manager = try XCTUnwrap(capture.manager)
            let escaped = try XCTUnwrap(capture.numberBinding)
            XCTAssertEqual(capture.text, "ab")
            XCTAssertTrue(manager.canUndo)
            try installCloseHostStateRelease(
                capture: capture, participant: participant, manager: manager, escaped: escaped)
            // Let ordinary frames settle editor metrics before the close.
            for _ in 0..<2 {
                clock.now += 0.02
                harness.host.windowNeedsDisplay(harness.window)
            }
            // Escaped reads of the payload itself would retain a snapshot and
            // conceal the ownership-release boundary under test.
            capture.payloadBinding = nil
            installCloseHostEditorRelease(
                capture: capture, participant: participant, manager: manager, escaped: escaped)
            XCTAssertNil(capture.undoTarget)
            XCTAssertNotNil(capture.statePayload)
            XCTAssertNotNil(capture.editorPayload)
            XCTAssertTrue(capture.releases.isEmpty)
            // No availability query here: it would prune the expired target
            // and release its capture before the native close can exercise it.
            let ticket = try closeHostTicket(harness.host)

            XCTAssertEqual(harness.window.attemptClose(ticket: ticket), .closed)

            XCTAssertNil(harness.window.nativeHandle)
            XCTAssertEqual(participant.calls.revocations, 1)
            XCTAssertEqual(participant.calls.finishes, [.closed])
            XCTAssertEqual(capture.releases.count, 2)
            XCTAssertEqual(Set(capture.releases), Set(["state", "editor"]))
            XCTAssertEqual(capture.revokedAtRelease, [true, true])
            XCTAssertNil(capture.statePayload)
            XCTAssertNil(capture.editorPayload)
            XCTAssertEqual(escaped.wrappedValue, 7)
            XCTAssertEqual(capture.text, "ab")
            XCTAssertEqual(capture.writes, ["ab"])
            XCTAssertFalse(manager.canUndo)
            XCTAssertFalse(manager.canRedo)
        }
    }
}

@MainActor
private final class CloseHostWorkCalls {
    var firstDeliveries = 0
    var replacementDeliveries = 0
    var failures: [Win32DeferredCloseSubmission] = []
}

private enum CloseHostNativeFixtureError: Error {
    case missingWake
}

@MainActor
private func closeHostHasWake(_ window: Win32Window) throws -> Bool {
    let raw = try XCTUnwrap(window.nativeHandle?.rawPointer)
    let handle = try XCTUnwrap(HWND(bitPattern: Int(bitPattern: raw)))
    var message = MSG()
    return PeekMessageW(
        &message, handle, Win32Window.deferredCloseMessage, Win32Window.deferredCloseMessage,
        UINT(PM_NOREMOVE))
}

@MainActor
private func takeCloseHostWake(_ window: Win32Window) throws -> MSG {
    let raw = try XCTUnwrap(window.nativeHandle?.rawPointer)
    let handle = try XCTUnwrap(HWND(bitPattern: Int(bitPattern: raw)))
    var message = MSG()
    guard
        PeekMessageW(
            &message, handle, Win32Window.deferredCloseMessage, Win32Window.deferredCloseMessage,
            UINT(PM_REMOVE))
    else {
        XCTFail("The helper did not post its owned native wake")
        throw CloseHostNativeFixtureError.missingWake
    }
    return message
}

@MainActor
extension WindowCloseFinalizationTests {
    func testHostReadyCloseWorkCoalescesWithoutDeliveringInline() async throws {
        let harness = try makeCloseHost(Text("Ready native wake"))
        defer { destroyCloseHostWindow(harness.window) }
        let participant = CloseHostParticipant()
        let calls = CloseHostWorkCalls()
        XCTAssertTrue(harness.host.setWindowCloseParticipant(participant))
        let ticket = try closeHostTicket(harness.host)
        defer { ticket.cancel() }

        XCTAssertEqual(
            harness.host.enqueueCloseWork(
                ticket: ticket, for: participant, phase: .prompt,
                onSubmissionFailure: { [weak calls] _, failure in calls?.failures.append(failure) },
                action: { [weak calls] _ in calls?.firstDeliveries += 1 }), .queued)
        XCTAssertEqual(
            harness.host.enqueueCloseWork(
                ticket: ticket, for: participant, phase: .prompt,
                onSubmissionFailure: { [weak calls] _, failure in calls?.failures.append(failure) },
                action: { [weak calls] _ in calls?.replacementDeliveries += 1 }), .coalesced)
        XCTAssertEqual(calls.firstDeliveries, 0)
        XCTAssertEqual(calls.replacementDeliveries, 0)
        var wake = try takeCloseHostWake(harness.window)
        DispatchMessageW(&wake)

        XCTAssertEqual(calls.firstDeliveries, 1)
        XCTAssertEqual(calls.replacementDeliveries, 0, "Coalescing must preserve the original owned action")
        XCTAssertTrue(calls.failures.isEmpty)
        XCTAssertFalse(try closeHostHasWake(harness.window))
        XCTAssertTrue(ticket.isCurrent, "Delivering a prompt is not a close approval")
        assertCloseHostStillAlive(harness)
    }

    func testHostBuildWaitCoalescesAndPostsOnlyAfterSettlement() async throws {
        let harness = try makeCloseHost(Text("Wait for retained work"))
        defer { destroyCloseHostWindow(harness.window) }
        let participant = CloseHostParticipant()
        let calls = CloseHostWorkCalls()
        XCTAssertTrue(harness.host.setWindowCloseParticipant(participant))
        let coordinator = harness.host.hostedRuntime.retainedBuildCoordinator
        let ticket = try closeHostTicket(harness.host)
        defer { ticket.cancel() }
        _ = try XCTUnwrap(coordinator.beginBuild())
        var buildIsOpen = true
        defer { if buildIsOpen { coordinator.finishBuild() } }

        XCTAssertEqual(
            harness.host.enqueueCloseWork(
                ticket: ticket, for: participant, phase: .prompt,
                onSubmissionFailure: { [weak calls] _, failure in calls?.failures.append(failure) },
                action: { [weak calls] _ in calls?.firstDeliveries += 1 }), .waitingForBuilds)
        XCTAssertEqual(
            harness.host.enqueueCloseWork(
                ticket: ticket, for: participant, phase: .prompt,
                onSubmissionFailure: { [weak calls] _, failure in calls?.failures.append(failure) },
                action: { [weak calls] _ in calls?.replacementDeliveries += 1 }), .coalesced)
        XCTAssertFalse(try closeHostHasWake(harness.window))
        XCTAssertEqual(calls.firstDeliveries, 0)
        buildIsOpen = false
        coordinator.finishBuild()
        XCTAssertEqual(calls.firstDeliveries, 0, "Settlement may post, never invoke the prompt inline")
        var wake = try takeCloseHostWake(harness.window)
        DispatchMessageW(&wake)

        XCTAssertEqual(calls.firstDeliveries, 1)
        XCTAssertEqual(calls.replacementDeliveries, 0)
        XCTAssertTrue(calls.failures.isEmpty)
        XCTAssertFalse(try closeHostHasWake(harness.window))
        assertCloseHostStillAlive(harness)
    }

    func testHostDelayedMailboxContentionPublishesBusyOnceWithoutInlineRetry() async throws {
        let harness = try makeCloseHost(Text("Deferred contention"))
        defer { destroyCloseHostWindow(harness.window) }
        let participant = CloseHostParticipant()
        let calls = CloseHostWorkCalls()
        XCTAssertTrue(harness.host.setWindowCloseParticipant(participant))
        let registration = try XCTUnwrap(harness.host.windowCloseRegistration)
        let occupiedTicket = try closeHostTicket(harness.host)
        let waitingTicket = try closeHostTicket(harness.host)
        defer {
            occupiedTicket.cancel()
            waitingTicket.cancel()
        }
        XCTAssertEqual(
            registration.enqueue(
                ticket: occupiedTicket, phase: .prompt,
                onPostFailure: { _, _ in XCTFail("The occupying wake must not fail after submission") },
                action: { _ in XCTFail("This fixture never dispatches the occupying wake") }), .queued)
        let coordinator = harness.host.hostedRuntime.retainedBuildCoordinator
        _ = try XCTUnwrap(coordinator.beginBuild())
        var buildIsOpen = true
        defer { if buildIsOpen { coordinator.finishBuild() } }
        XCTAssertEqual(
            harness.host.enqueueCloseWork(
                ticket: waitingTicket, for: participant, phase: .prompt,
                onSubmissionFailure: { [weak calls] _, failure in calls?.failures.append(failure) },
                action: { [weak calls] _ in calls?.firstDeliveries += 1 }), .waitingForBuilds)
        XCTAssertTrue(calls.failures.isEmpty)

        buildIsOpen = false
        coordinator.finishBuild()
        coordinator.retainedCallbacksDidDrain()
        coordinator.retainedCallbacksDidDrain()

        XCTAssertEqual(calls.failures, [.busy])
        XCTAssertEqual(calls.firstDeliveries, 0)
        XCTAssertTrue(waitingTicket.isCurrent)
        // Remove only this fixture's occupying scalar. No message loop or
        // unrelated native event is needed to prove failure publication.
        _ = try takeCloseHostWake(harness.window)
        occupiedTicket.cancel()
        XCTAssertFalse(try closeHostHasWake(harness.window))
        assertCloseHostStillAlive(harness)
    }

    func testHostDelayedResizePublishesUnavailableOnceWithoutPostingAnotherWake() async throws {
        let harness = try makeCloseHost(Text("Deferred resize rejection"))
        defer { destroyCloseHostWindow(harness.window) }
        let participant = CloseHostParticipant()
        let calls = CloseHostWorkCalls()
        let resizeRebuildsBefore = harness.host.executedResizeRebuildCount
        XCTAssertTrue(harness.host.setWindowCloseParticipant(participant))
        let coordinator = harness.host.hostedRuntime.retainedBuildCoordinator
        let ticket = try closeHostTicket(harness.host)
        defer { ticket.cancel() }
        _ = try XCTUnwrap(coordinator.beginBuild())
        var buildIsOpen = true
        defer { if buildIsOpen { coordinator.finishBuild() } }
        XCTAssertEqual(
            harness.host.enqueueCloseWork(
                ticket: ticket, for: participant, phase: .prompt,
                onSubmissionFailure: { [weak calls] _, failure in calls?.failures.append(failure) },
                action: { [weak calls] _ in calls?.firstDeliveries += 1 }), .waitingForBuilds)
        harness.window.setModalLoopStateForTesting(isInSizeMove: true)
        harness.host.window(harness.window, didResizeTo: IntSize(width: 510, height: 310))
        harness.window.setModalLoopStateForTesting(isInSizeMove: false)
        XCTAssertTrue(calls.failures.isEmpty)

        buildIsOpen = false
        coordinator.finishBuild()
        coordinator.retainedCallbacksDidDrain()
        coordinator.retainedCallbacksDidDrain()

        XCTAssertEqual(calls.failures, [.unavailable])
        XCTAssertEqual(calls.firstDeliveries, 0)
        XCTAssertFalse(try closeHostHasWake(harness.window))
        XCTAssertEqual(harness.host.executedResizeRebuildCount, resizeRebuildsBefore)
        XCTAssertTrue(ticket.isCurrent)
        assertCloseHostStillAlive(harness)
    }
}

@MainActor
extension WindowCloseFinalizationTests {
    func testNativeUnadaptedDocumentGroupRejectsBeforeFlushOrLayout() async throws {
        // This direct host configuration tests only the fail-closed guard.
        // It does not construct a document session or enable App startup.
        let model = CloseHostModel()
        let harness = try makeCloseHost(CloseHostObservedContent(model: model), isDocumentGroup: true)
        let runtime = harness.host.hostedRuntime
        defer {
            runtime.root.onLayout = nil
            destroyCloseHostWindow(harness.window)
        }
        var layoutCalls = 0
        runtime.root.onLayout = { _ in layoutCalls += 1 }
        let originalPass = runtime.layoutPassID
        let originalBodyCalls = model.bodyCalls
        model.revision += 1
        let ticket = try closeHostTicket(harness.host)

        XCTAssertEqual(harness.window.attemptClose(ticket: ticket), .unavailable)

        assertCloseHostStillAlive(harness)
        XCTAssertEqual(layoutCalls, 0)
        XCTAssertEqual(runtime.layoutPassID, originalPass)
        XCTAssertEqual(model.bodyCalls, originalBodyCalls)
        XCTAssertEqual(harness.host.executedReloadCount, 0)
        XCTAssertFalse(ticket.isCurrent)
    }
}

// Full-host wait refinement: pending observation is not an idle owner even
// when the component coordinator has already left its retained build scope.
@MainActor
extension WindowCloseFinalizationTests {
    func testHostPendingObservedBatchParksWhileComponentCoordinatorIsIdle() async throws {
        let model = CloseHostModel()
        let clock = RuntimeTestClock()
        clock.now = 9_000
        let harness = try makeCloseHost(CloseHostObservedContent(model: model), clock: clock)
        defer { destroyCloseHostWindow(harness.window) }
        let participant = CloseHostParticipant()
        let calls = CloseHostWorkCalls()
        XCTAssertTrue(harness.host.setWindowCloseParticipant(participant))
        let ticket = try closeHostTicket(harness.host)
        defer { ticket.cancel() }
        let coordinator = harness.host.hostedRuntime.retainedBuildCoordinator
        let reloadsBefore = harness.host.executedReloadCount
        model.revision += 1
        XCTAssertTrue(coordinator.isBuildSettled, "The pending work belongs to the host, not an active component build")

        XCTAssertEqual(
            harness.host.enqueueCloseWork(
                ticket: ticket, for: participant, phase: .prompt,
                onSubmissionFailure: { [weak calls] _, failure in calls?.failures.append(failure) },
                action: { [weak calls] _ in calls?.firstDeliveries += 1 }), .waitingForBuilds)

        XCTAssertFalse(try closeHostHasWake(harness.window))
        XCTAssertEqual(calls.firstDeliveries, 0)
        XCTAssertEqual(harness.host.executedReloadCount, reloadsBefore)
        clock.now += 0.04
        harness.host.windowNeedsDisplay(harness.window)
        XCTAssertEqual(harness.host.executedReloadCount, reloadsBefore + 1)
        XCTAssertEqual(calls.firstDeliveries, 0, "The actual flush may post one wake, never invoke it inline")
        var wake = try takeCloseHostWake(harness.window)
        XCTAssertFalse(try closeHostHasWake(harness.window), "Only one owned wake may be queued")
        DispatchMessageW(&wake)

        XCTAssertEqual(calls.firstDeliveries, 1)
        XCTAssertTrue(calls.failures.isEmpty)
        XCTAssertFalse(try closeHostHasWake(harness.window))
        assertCloseHostStillAlive(harness)
    }

    func testHostDuplicateObservedWaitRequestsCoalesceIntoOneLaterWake() async throws {
        let model = CloseHostModel()
        let clock = RuntimeTestClock()
        clock.now = 9_100
        let harness = try makeCloseHost(CloseHostObservedContent(model: model), clock: clock)
        defer { destroyCloseHostWindow(harness.window) }
        let participant = CloseHostParticipant()
        let calls = CloseHostWorkCalls()
        XCTAssertTrue(harness.host.setWindowCloseParticipant(participant))
        let ticket = try closeHostTicket(harness.host)
        defer { ticket.cancel() }
        model.revision += 1
        XCTAssertTrue(harness.host.hostedRuntime.retainedBuildCoordinator.isBuildSettled)

        XCTAssertEqual(
            harness.host.enqueueCloseWork(
                ticket: ticket, for: participant, phase: .prompt,
                onSubmissionFailure: { [weak calls] _, failure in calls?.failures.append(failure) },
                action: { [weak calls] _ in calls?.firstDeliveries += 1 }), .waitingForBuilds)
        for _ in 0..<3 {
            XCTAssertEqual(
                harness.host.enqueueCloseWork(
                    ticket: ticket, for: participant, phase: .prompt,
                    onSubmissionFailure: { [weak calls] _, failure in calls?.failures.append(failure) },
                    action: { [weak calls] _ in calls?.replacementDeliveries += 1 }), .coalesced)
        }
        XCTAssertFalse(try closeHostHasWake(harness.window))
        clock.now += 0.04
        harness.host.windowNeedsDisplay(harness.window)
        var wake = try takeCloseHostWake(harness.window)
        XCTAssertFalse(try closeHostHasWake(harness.window))
        DispatchMessageW(&wake)
        clock.now += 0.04
        harness.host.windowNeedsDisplay(harness.window)

        XCTAssertEqual(calls.firstDeliveries, 1)
        XCTAssertEqual(calls.replacementDeliveries, 0)
        XCTAssertTrue(calls.failures.isEmpty)
        XCTAssertFalse(try closeHostHasWake(harness.window), "A later ordinary frame must not repost a consumed wait")
        assertCloseHostStillAlive(harness)
    }

    func testHostComponentSettlementKeepsOneWaitParkedBehindPendingObservation() async throws {
        let model = CloseHostModel()
        let clock = RuntimeTestClock()
        clock.now = 9_200
        let harness = try makeCloseHost(CloseHostObservedContent(model: model), clock: clock)
        defer { destroyCloseHostWindow(harness.window) }
        let participant = CloseHostParticipant()
        let calls = CloseHostWorkCalls()
        XCTAssertTrue(harness.host.setWindowCloseParticipant(participant))
        let ticket = try closeHostTicket(harness.host)
        defer { ticket.cancel() }
        let coordinator = harness.host.hostedRuntime.retainedBuildCoordinator
        _ = try XCTUnwrap(coordinator.beginBuild())
        var buildIsOpen = true
        defer { if buildIsOpen { coordinator.finishBuild() } }
        model.revision += 1
        XCTAssertEqual(
            harness.host.enqueueCloseWork(
                ticket: ticket, for: participant, phase: .prompt,
                onSubmissionFailure: { [weak calls] _, failure in calls?.failures.append(failure) },
                action: { [weak calls] _ in calls?.firstDeliveries += 1 }), .waitingForBuilds)

        buildIsOpen = false
        coordinator.finishBuild()

        XCTAssertTrue(coordinator.isBuildSettled)
        XCTAssertFalse(
            try closeHostHasWake(harness.window), "Component settlement cannot bypass the host's pending batch")
        XCTAssertEqual(calls.firstDeliveries, 0)
        XCTAssertTrue(calls.failures.isEmpty, "Transient host work must remain parked, not be published as a failure")
        XCTAssertEqual(
            harness.host.enqueueCloseWork(
                ticket: ticket, for: participant, phase: .prompt,
                onSubmissionFailure: { [weak calls] _, failure in calls?.failures.append(failure) },
                action: { [weak calls] _ in calls?.replacementDeliveries += 1 }), .coalesced)
        clock.now += 0.04
        harness.host.windowNeedsDisplay(harness.window)
        var wake = try takeCloseHostWake(harness.window)
        XCTAssertFalse(try closeHostHasWake(harness.window))
        DispatchMessageW(&wake)

        XCTAssertEqual(calls.firstDeliveries, 1)
        XCTAssertEqual(calls.replacementDeliveries, 0)
        XCTAssertTrue(calls.failures.isEmpty)
        XCTAssertFalse(try closeHostHasWake(harness.window))
        assertCloseHostStillAlive(harness)
    }

    func testHostCancelledObservedWaitDoesNotPostWhenTheRealFlushFinishes() async throws {
        let model = CloseHostModel()
        let clock = RuntimeTestClock()
        clock.now = 9_300
        let harness = try makeCloseHost(CloseHostObservedContent(model: model), clock: clock)
        defer { destroyCloseHostWindow(harness.window) }
        let participant = CloseHostParticipant()
        let calls = CloseHostWorkCalls()
        XCTAssertTrue(harness.host.setWindowCloseParticipant(participant))
        let ticket = try closeHostTicket(harness.host)
        model.revision += 1
        XCTAssertEqual(
            harness.host.enqueueCloseWork(
                ticket: ticket, for: participant, phase: .prompt,
                onSubmissionFailure: { [weak calls] _, failure in calls?.failures.append(failure) },
                action: { [weak calls] _ in calls?.firstDeliveries += 1 }), .waitingForBuilds)
        ticket.cancel()
        XCTAssertFalse(ticket.isCurrent)
        XCTAssertFalse(try closeHostHasWake(harness.window))

        clock.now += 0.04
        harness.host.windowNeedsDisplay(harness.window)
        clock.now += 0.04
        harness.host.windowNeedsDisplay(harness.window)

        XCTAssertEqual(calls.firstDeliveries, 0)
        XCTAssertTrue(calls.failures.isEmpty, "Cancellation retires the wait without delivering owner callbacks")
        XCTAssertFalse(try closeHostHasWake(harness.window))
        assertCloseHostStillAlive(harness)
    }

    func testHostNativeTeardownRetiresObservedWaitBeforeAnyLateFlush() async throws {
        let model = CloseHostModel()
        let clock = RuntimeTestClock()
        clock.now = 9_400
        let harness = try makeCloseHost(CloseHostObservedContent(model: model), clock: clock)
        defer {
            harness.host.onObservedObjectReloadTaskCompleted = nil
            destroyCloseHostWindow(harness.window)
        }
        let participant = CloseHostParticipant()
        let calls = CloseHostWorkCalls()
        var completionCount = 0
        XCTAssertTrue(harness.host.setWindowCloseParticipant(participant))
        let registration = try XCTUnwrap(harness.host.windowCloseRegistration)
        let ticket = try closeHostTicket(harness.host)
        harness.host.onObservedObjectReloadTaskCompleted = { _ in completionCount += 1 }
        model.revision += 1
        XCTAssertEqual(
            harness.host.enqueueCloseWork(
                ticket: ticket, for: participant, phase: .prompt,
                onSubmissionFailure: { [weak calls] _, failure in calls?.failures.append(failure) },
                action: { [weak calls] _ in calls?.firstDeliveries += 1 }), .waitingForBuilds)
        XCTAssertFalse(try closeHostHasWake(harness.window))

        // Exercise real native destruction, not a simulated host-close flag.
        destroyCloseHostWindow(harness.window)
        clock.now += 0.04
        harness.host.windowNeedsDisplay(harness.window)

        XCTAssertNil(harness.window.nativeHandle)
        XCTAssertTrue(registration.isRevoked)
        XCTAssertFalse(ticket.isCurrent)
        XCTAssertEqual(participant.calls.revocations, 1)
        XCTAssertEqual(completionCount, 0)
        XCTAssertEqual(calls.firstDeliveries, 0)
        XCTAssertTrue(calls.failures.isEmpty)
        XCTAssertEqual(harness.renderer.detachCount, 1)
        XCTAssertEqual(harness.batchRenderer.detachCount, 1)
        // No PeekMessage query is made against the destroyed handle.
    }

    func testNativePendingObservationCannotHideStickyLayoutReceiptExhaustion() async throws {
        let model = CloseHostModel()
        let clock = RuntimeTestClock()
        clock.now = 9_500
        let harness = try makeCloseHost(CloseHostObservedContent(model: model), clock: clock)
        defer { destroyCloseHostWindow(harness.window) }
        let participant = CloseHostParticipant()
        let calls = CloseHostWorkCalls()
        XCTAssertTrue(harness.host.setWindowCloseParticipant(participant))
        let ticket = try closeHostTicket(harness.host)
        defer { ticket.cancel() }
        let runtime = harness.host.hostedRuntime
        runtime.exhaustLayoutGeometryGenerationOnNextInvalidationForTesting()
        runtime.root.frame.size.width += 1
        model.revision += 1
        XCTAssertTrue(runtime.retainedBuildCoordinator.isBuildSettled)
        assertCloseLayoutUnavailable(runtime)
        let originalPass = runtime.layoutPassID
        let nativeTicket = try closeHostTicket(harness.host)
        XCTAssertEqual(harness.window.attemptClose(ticket: nativeTicket), .unavailable)
        XCTAssertFalse(nativeTicket.isCurrent)
        XCTAssertEqual(runtime.layoutPassID, originalPass)
        XCTAssertEqual(participant.calls.votes, 0)
        XCTAssertEqual(harness.host.executedReloadCount, 0)

        XCTAssertEqual(
            harness.host.enqueueCloseWork(
                ticket: ticket, for: participant, phase: .prompt,
                onSubmissionFailure: { [weak calls] _, failure in calls?.failures.append(failure) },
                action: { [weak calls] _ in calls?.firstDeliveries += 1 }), .unavailable)
        XCTAssertFalse(try closeHostHasWake(harness.window))
        clock.now += 0.04
        harness.host.windowNeedsDisplay(harness.window)
        assertCloseLayoutUnavailable(runtime)
        XCTAssertEqual(
            harness.host.enqueueCloseWork(
                ticket: ticket, for: participant, phase: .prompt,
                onSubmissionFailure: { [weak calls] _, failure in calls?.failures.append(failure) },
                action: { [weak calls] _ in calls?.firstDeliveries += 1 }), .unavailable)

        XCTAssertEqual(calls.firstDeliveries, 0)
        XCTAssertTrue(calls.failures.isEmpty, "Immediate unavailable results must not also publish a callback")
        XCTAssertFalse(try closeHostHasWake(harness.window))
        XCTAssertTrue(ticket.isCurrent)
        assertCloseHostStillAlive(harness)
    }
}

@MainActor
extension WindowCloseFinalizationTests {
    func testNativeCloseAndWakeStayDeferredThroughNestedObservedFlushes() async throws {
        let savedAnimation = currentAnimationTransaction
        let savedTransaction = currentTransaction
        currentAnimationTransaction = nil
        currentTransaction = nil
        defer {
            currentAnimationTransaction = savedAnimation
            currentTransaction = savedTransaction
        }
        let model = CloseHostModel()
        let clock = RuntimeTestClock()
        clock.now = 9_600
        let harness = try makeCloseHost(CloseHostObservedContent(model: model), clock: clock)
        defer {
            harness.host.onObservedObjectReloadTaskCompleted = nil
            destroyCloseHostWindow(harness.window)
        }
        let participant = CloseHostParticipant()
        let calls = CloseHostWorkCalls()
        XCTAssertTrue(harness.host.setWindowCloseParticipant(participant))
        let ticket = try closeHostTicket(harness.host)
        defer { ticket.cancel() }
        let runtime = harness.host.hostedRuntime
        var completionCount = 0
        var events: [String] = []
        var nestedVote: Bool?
        harness.host.onObservedObjectReloadTaskCompleted = { (didReload: Bool) throws(Never) -> Void in
            XCTAssertTrue(didReload)
            completionCount += 1
            XCTAssertTrue(runtime.retainedBuildCoordinator.isBuildSettled)
            XCTAssertFalse(try closeHostHasWake(harness.window))
            if completionCount == 1 {
                events.append("outer-completion-enter")
                XCTAssertEqual(currentAnimationTransaction?.duration, 0.3)
                let originalPass = runtime.layoutPassID
                // This call is inside a direct frame's completion callback,
                // outside a native dispatch or mailbox scope. Host flush
                // depth, not component activity, must block native preflight.
                XCTAssertEqual(harness.window.attemptClose(ticket: ticket), .busy(.buildsNotSettled))
                XCTAssertTrue(ticket.isCurrent)
                XCTAssertEqual(runtime.layoutPassID, originalPass)
                XCTAssertEqual(participant.calls.votes, 0)
                withAnimation(.linear(duration: 0.7)) { model.revision += 1 }
                // The existing Bool entry point consumes a real nested batch
                // without creating another native attempt or presenting.
                nestedVote = harness.host.windowShouldClose(harness.window)
                events.append("outer-completion-resumed")
                XCTAssertEqual(currentAnimationTransaction?.duration, 0.3)
                XCTAssertFalse(try closeHostHasWake(harness.window))
            } else {
                XCTAssertEqual(completionCount, 2, "The fixture permits one nested flush only")
                events.append("inner-completion")
                XCTAssertEqual(currentAnimationTransaction?.duration, 0.7)
                XCTAssertFalse(try closeHostHasWake(harness.window))
            }
        }
        withAnimation(.linear(duration: 0.3)) { model.revision += 1 }
        XCTAssertNil(currentAnimationTransaction)
        XCTAssertNil(currentTransaction)
        XCTAssertEqual(
            harness.host.enqueueCloseWork(
                ticket: ticket, for: participant, phase: .prompt,
                onSubmissionFailure: { [weak calls] _, failure in calls?.failures.append(failure) },
                action: { [weak calls] _ in
                    XCTAssertNil(currentAnimationTransaction)
                    XCTAssertNil(currentTransaction)
                    calls?.firstDeliveries += 1
                }), .waitingForBuilds)

        clock.now += 0.04
        harness.host.windowNeedsDisplay(harness.window)

        XCTAssertEqual(completionCount, 2)
        XCTAssertEqual(events, ["outer-completion-enter", "inner-completion", "outer-completion-resumed"])
        XCTAssertEqual(nestedVote, true)
        XCTAssertNil(currentAnimationTransaction)
        XCTAssertNil(currentTransaction)
        XCTAssertEqual(calls.firstDeliveries, 0)
        var wake = try takeCloseHostWake(harness.window)
        XCTAssertFalse(try closeHostHasWake(harness.window))
        DispatchMessageW(&wake)
        XCTAssertEqual(calls.firstDeliveries, 1)
        XCTAssertTrue(calls.failures.isEmpty)
        XCTAssertFalse(try closeHostHasWake(harness.window))
        assertCloseHostStillAlive(harness)
    }
}

@MainActor
private final class CloseHostBusyRetryDriver {
    weak var host: WinSwiftUIWindowHost?
    weak var participant: CloseHostParticipant?
    let clock: RuntimeTestClock
    var deliveries = 0
    var firstActionReturnedFromFlush = false
    var outcomes: [Win32CloseAttemptOutcome] = []
    var submissions: [WindowCloseWorkSubmission] = []
    var failures: [Win32DeferredCloseSubmission] = []

    init(host: WinSwiftUIWindowHost, participant: CloseHostParticipant, clock: RuntimeTestClock) {
        self.host = host
        self.participant = participant
        self.clock = clock
    }

    func enqueue(_ ticket: Win32CloseTicket) -> WindowCloseWorkSubmission {
        guard let host, let participant else { return .unavailable }
        return host.enqueueCloseWork(
            ticket: ticket, for: participant, phase: .retry,
            onSubmissionFailure: { [weak self] _, failure in self?.failures.append(failure) },
            action: { [weak self] ticket in self?.deliver(ticket) })
    }

    private func deliver(_ ticket: Win32CloseTicket) {
        guard let host else {
            XCTFail("The fixture owner disappeared before native retry delivery")
            return
        }
        let window = host.platformWindow
        deliveries += 1
        let outcome = window.attemptClose(ticket: ticket)
        outcomes.append(outcome)
        if deliveries == 1 {
            XCTAssertEqual(outcome, .busy(.buildsNotSettled))
            XCTAssertTrue(ticket.isCurrent)
            XCTAssertTrue(host.hostedRuntime.retainedBuildCoordinator.isBuildSettled)
            submissions.append(enqueue(ticket))
            submissions.append(enqueue(ticket))
            XCTAssertEqual(submissions, [.waitingForBuilds, .coalesced])
            XCTAssertFalse(try closeHostHasWake(window))
            let reloadsBefore = host.executedReloadCount
            clock.now += 0.04
            // Complete the actual host batch while the original owned retry
            // action is still executing. The core may reserve one new scalar,
            // but its native post must wait until this action unwinds.
            host.windowNeedsDisplay(window)
            XCTAssertEqual(host.executedReloadCount, reloadsBefore + 1)
            XCTAssertFalse(try closeHostHasWake(window))
            XCTAssertEqual(deliveries, 1)
            firstActionReturnedFromFlush = true
        } else {
            XCTAssertEqual(deliveries, 2, "Only one fresh retry delivery is permitted")
            XCTAssertEqual(outcome, .closed)
        }
    }
}

@MainActor
extension WindowCloseFinalizationTests {
    func testNativeBusyRetryGetsOneFreshWakeAfterItsRealFlushAndOldActionUnwind() async throws {
        let model = CloseHostModel()
        let clock = RuntimeTestClock()
        clock.now = 9_700
        let harness = try makeCloseHost(CloseHostObservedContent(model: model), clock: clock)
        defer { destroyCloseHostWindow(harness.window) }
        let participant = CloseHostParticipant()
        let neutral = CloseHostNeutral()
        XCTAssertTrue(harness.host.setWindowCloseParticipant(participant))
        var queuedLateMutation = false
        neutral.vote = { [weak model] _ in
            if !queuedLateMutation {
                queuedLateMutation = true
                model?.revision += 1
            }
            return true
        }
        harness.window.setPlatformWindowHost(neutral)
        let ticket = try closeHostTicket(harness.host)
        let driver = CloseHostBusyRetryDriver(host: harness.host, participant: participant, clock: clock)
        XCTAssertEqual(driver.enqueue(ticket), .queued)
        XCTAssertEqual(driver.deliveries, 0)
        var originalWake = try takeCloseHostWake(harness.window)
        let originalNonce = originalWake.wParam

        DispatchMessageW(&originalWake)

        XCTAssertTrue(driver.firstActionReturnedFromFlush)
        XCTAssertEqual(driver.deliveries, 1)
        XCTAssertEqual(driver.outcomes, [.busy(.buildsNotSettled)])
        XCTAssertEqual(driver.submissions, [.waitingForBuilds, .coalesced])
        XCTAssertTrue(driver.failures.isEmpty)
        XCTAssertTrue(ticket.isCurrent)
        assertCloseHostStillAlive(harness)
        var retryWake = try takeCloseHostWake(harness.window)
        XCTAssertNotEqual(retryWake.wParam, originalNonce, "A continuation must own a fresh delivery identity")
        XCTAssertFalse(try closeHostHasWake(harness.window), "There must be exactly one continuation wake")
        DispatchMessageW(&retryWake)

        XCTAssertEqual(driver.deliveries, 2)
        XCTAssertEqual(driver.outcomes, [.busy(.buildsNotSettled), .closed])
        XCTAssertTrue(driver.failures.isEmpty)
        XCTAssertEqual(participant.calls.finishes, [.closed])
        XCTAssertEqual(participant.calls.revocations, 1)
        XCTAssertEqual(neutral.votes, 2)
        XCTAssertFalse(ticket.isCurrent)
        XCTAssertNil(harness.window.nativeHandle)
    }
}

// Integration regressions for an unadapted DocumentGroup on every close entry.
// These fixtures do not construct a document session or enable native startup.
@MainActor
private final class CloseGuardWorkProbe {
    var layoutCalls = 0
    var afterLayoutCalls = 0
    var reloadResults: [Bool] = []
}

@MainActor
private struct CloseGuardPendingWork {
    let harness: CloseHostHarness
    let model: CloseHostModel
    let clock: RuntimeTestClock
    let probe: CloseGuardWorkProbe
    let hasNativeWindow: Bool
    let originalLayoutPass: UInt64
    let originalBodyCalls: Int
    let originalFrameCount: Int
    let originalSceneCount: Int

    var host: WinSwiftUIWindowHost { harness.host }
    var window: Win32Window { harness.window }
    var runtime: RetainedViewRuntime { host.hostedRuntime }

    func nativeHandle() throws -> HWND {
        let raw = try XCTUnwrap(window.nativeHandle?.rawPointer)
        return try XCTUnwrap(HWND(bitPattern: Int(bitPattern: raw)))
    }

    func assertStillLive(file: StaticString = #filePath, line: UInt = #line) {
        if hasNativeWindow {
            assertCloseHostStillAlive(harness, file: file, line: line)
        } else {
            XCTAssertNil(window.nativeHandle, file: file, line: line)
            XCTAssertEqual(harness.renderer.detachCount, 0, file: file, line: line)
            XCTAssertEqual(harness.batchRenderer.detachCount, 0, file: file, line: line)
        }
        XCTAssertNil(window.activeCloseAttempt, file: file, line: line)
    }

    func assertNoPresentation(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(harness.renderer.renderedFrames.count, originalFrameCount, file: file, line: line)
        XCTAssertEqual(harness.batchRenderer.renderedScenes.count, originalSceneCount, file: file, line: line)
    }

    func assertPendingWorkUntouched(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(host.scheduledReloadCount, 1, file: file, line: line)
        XCTAssertEqual(host.executedReloadCount, 0, file: file, line: line)
        XCTAssertEqual(host.completedObservedObjectReloadTaskCount, 0, file: file, line: line)
        XCTAssertEqual(host.skippedObservedObjectReloadCount, 0, file: file, line: line)
        XCTAssertEqual(model.bodyCalls, originalBodyCalls, file: file, line: line)
        XCTAssertEqual(runtime.layoutPassID, originalLayoutPass, file: file, line: line)
        XCTAssertEqual(probe.layoutCalls, 0, file: file, line: line)
        XCTAssertEqual(probe.afterLayoutCalls, 0, file: file, line: line)
        XCTAssertTrue(probe.reloadResults.isEmpty, file: file, line: line)
        assertNoPresentation(file: file, line: line)
        assertStillLive(file: file, line: line)
    }

    func assertObservedBatchConsumed(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(host.scheduledReloadCount, 1, file: file, line: line)
        XCTAssertEqual(host.executedReloadCount, 1, file: file, line: line)
        XCTAssertEqual(host.completedObservedObjectReloadTaskCount, 1, file: file, line: line)
        XCTAssertEqual(host.skippedObservedObjectReloadCount, 0, file: file, line: line)
        XCTAssertGreaterThan(model.bodyCalls, originalBodyCalls, file: file, line: line)
        XCTAssertEqual(probe.reloadResults, [true], file: file, line: line)
    }

    func displayPendingWork(file: StaticString = #filePath, line: UInt = #line) {
        // No new mutation: display drains the original layout callback,
        // consuming the original observed batch only if close left it pending.
        clock.now += 0.04
        host.windowNeedsDisplay(window)
        assertObservedBatchConsumed(file: file, line: line)
        XCTAssertGreaterThan(runtime.layoutPassID, originalLayoutPass, file: file, line: line)
        XCTAssertEqual(probe.afterLayoutCalls, 1, file: file, line: line)
        assertStillLive(file: file, line: line)
    }

    func assertNativeCloseCompleted(file: StaticString = #filePath, line: UInt = #line) {
        assertObservedBatchConsumed(file: file, line: line)
        XCTAssertGreaterThan(runtime.layoutPassID, originalLayoutPass, file: file, line: line)
        XCTAssertEqual(probe.afterLayoutCalls, 1, file: file, line: line)
        assertNoPresentation(file: file, line: line)
        XCTAssertNil(window.nativeHandle, file: file, line: line)
        XCTAssertNil(window.activeCloseAttempt, file: file, line: line)
        XCTAssertEqual(harness.renderer.detachCount, 1, file: file, line: line)
        XCTAssertEqual(harness.batchRenderer.detachCount, 1, file: file, line: line)
    }

    func tearDown() {
        runtime.root.onLayout = nil
        host.onObservedObjectReloadTaskCompleted = nil
        if hasNativeWindow {
            destroyCloseHostWindow(window)
        } else {
            host.windowWillClose(window)
        }
    }
}

@MainActor
private func makeCloseGuardPendingWork(
    isDocumentGroup: Bool, hasNativeWindow: Bool
) throws -> CloseGuardPendingWork {
    let model = CloseHostModel()
    let clock = RuntimeTestClock()
    clock.now = 9_800
    let harness: CloseHostHarness
    if hasNativeWindow {
        harness = try makeCloseHost(
            CloseHostObservedContent(model: model), isDocumentGroup: isDocumentGroup, clock: clock)
    } else {
        let size = IntSize(width: 360, height: 220)
        let surface = SurfaceDescriptor(offscreenPixelSize: size, scaleFactor: 1)
        let renderer = FakeRenderBackend()
        let batchRenderer = FakeBatchRenderBackend()
        let window = Win32Window(title: "Headless close guard", clientSize: size)
        window.postsQuitMessageOnDestroy = false
        window.testScaleFactorOverride = 1
        let host = WinSwiftUIWindowHost(
            configuration: WindowGroupConfiguration(
                title: "Headless close guard", size: size, clearColor: .black,
                content: [AnyView(CloseHostObservedContent(model: model))], isDocumentGroup: isDocumentGroup),
            platformWindow: window, renderer: renderer, batchRenderer: batchRenderer,
            surfaceDescriptorProvider: { _ in surface }, startupProbeConfiguration: nil)
        host.frameClock = { clock.now }
        host.hostedRuntime.clock = { clock.now }
        // Attach only fake presentation to an offscreen surface. No HWND is created.
        host.windowDidCreate(window)
        harness = CloseHostHarness(host: host, renderer: renderer, batchRenderer: batchRenderer)
    }

    let host = harness.host
    let runtime = host.hostedRuntime
    let probe = CloseGuardWorkProbe()
    host.resetObservabilityCounters()
    runtime.root.onLayout = { _ in probe.layoutCalls += 1 }
    runtime.scheduleAfterLayout(key: "close-guard-pending-layout") { probe.afterLayoutCalls += 1 }
    host.onObservedObjectReloadTaskCompleted = { probe.reloadResults.append($0) }
    let fixture = CloseGuardPendingWork(
        harness: harness, model: model, clock: clock, probe: probe, hasNativeWindow: hasNativeWindow,
        originalLayoutPass: runtime.layoutPassID, originalBodyCalls: model.bodyCalls,
        originalFrameCount: harness.renderer.renderedFrames.count,
        originalSceneCount: harness.batchRenderer.renderedScenes.count)

    // No suspension or message pump separates this write from the close entry.
    // The headless Task fallback cannot consume it before the synchronous assertions.
    model.revision += 1
    XCTAssertGreaterThan(fixture.originalFrameCount + fixture.originalSceneCount, 0)
    XCTAssertTrue(runtime.canPrepareLayoutSettlement)
    XCTAssertTrue(runtime.retainedBuildCoordinator.isBuildSettled)
    fixture.assertPendingWorkUntouched()
    return fixture
}

@MainActor
extension WindowCloseFinalizationTests {
    func testHeadlessUnadaptedDocumentGroupKeepsPendingWorkOnDirectCloseQuery() async throws {
        let fixture = try makeCloseGuardPendingWork(isDocumentGroup: true, hasNativeWindow: false)
        defer { fixture.tearDown() }

        XCTAssertFalse(fixture.host.windowShouldClose(fixture.window))
        XCTAssertFalse(fixture.host.windowShouldClose(fixture.window))

        fixture.assertPendingWorkUntouched()
        fixture.displayPendingWork()
        XCTAssertFalse(fixture.host.windowShouldClose(fixture.window))
        fixture.assertObservedBatchConsumed()
        fixture.assertStillLive()
    }

    func testHeadlessOrdinaryCloseQueryFlushesThePreparedObservedBatch() async throws {
        let fixture = try makeCloseGuardPendingWork(isDocumentGroup: false, hasNativeWindow: false)
        defer { fixture.tearDown() }

        XCTAssertTrue(fixture.host.windowShouldClose(fixture.window))

        fixture.assertObservedBatchConsumed()
        fixture.assertNoPresentation()
        fixture.assertStillLive()
        fixture.displayPendingWork()
    }

    func testNativeOrdinaryMessageKeepsUnadaptedDocumentWorkPending() async throws {
        let fixture = try makeCloseGuardPendingWork(isDocumentGroup: true, hasNativeWindow: true)
        defer { fixture.tearDown() }
        let handle = try fixture.nativeHandle()

        SendMessageW(handle, UINT(WM_CLOSE), 0, 0)

        XCTAssertTrue(IsWindow(handle))
        XCTAssertEqual(try fixture.nativeHandle(), handle)
        fixture.assertPendingWorkUntouched()
        fixture.displayPendingWork()
    }

    func testNativeOrdinaryMessageFlushesAndClosesAnOrdinaryHost() async throws {
        let fixture = try makeCloseGuardPendingWork(isDocumentGroup: false, hasNativeWindow: true)
        defer { fixture.tearDown() }
        let handle = try fixture.nativeHandle()

        SendMessageW(handle, UINT(WM_CLOSE), 0, 0)

        XCTAssertFalse(IsWindow(handle))
        fixture.assertNativeCloseCompleted()
    }

    func testNativeTaggedAttemptKeepsUnadaptedDocumentWorkPending() async throws {
        let fixture = try makeCloseGuardPendingWork(isDocumentGroup: true, hasNativeWindow: true)
        defer { fixture.tearDown() }
        let handle = try fixture.nativeHandle()
        let ticket = try closeHostTicket(fixture.host)

        XCTAssertEqual(fixture.window.attemptClose(ticket: ticket), .unavailable)

        XCTAssertFalse(ticket.isCurrent)
        XCTAssertTrue(IsWindow(handle))
        XCTAssertEqual(try fixture.nativeHandle(), handle)
        fixture.assertPendingWorkUntouched()
        fixture.displayPendingWork()
    }

    func testNativeTaggedAttemptFlushesAndClosesAnOrdinaryHost() async throws {
        let fixture = try makeCloseGuardPendingWork(isDocumentGroup: false, hasNativeWindow: true)
        defer { fixture.tearDown() }
        let handle = try fixture.nativeHandle()
        let ticket = try closeHostTicket(fixture.host)

        XCTAssertEqual(fixture.window.attemptClose(ticket: ticket), .closed)

        XCTAssertFalse(ticket.isCurrent)
        XCTAssertFalse(IsWindow(handle))
        fixture.assertNativeCloseCompleted()
    }
}

// Build history is independent of whether the coordinator is idle at final validation.
@MainActor
private final class CloseHistoryReaderProbe {
    weak var runtime: RetainedViewRuntime?
    weak var window: Win32Window?
    var restriction: Binding<Bool>?
    var rootBodyCalls = 0
    var widths: [Double] = []
    var managedBuilds: [Bool] = []
    var nativeAttemptIDs: [Foundation.UUID?] = []

    func record(width: Double) {
        widths.append(width)
        managedBuilds.append(runtime?.hasActiveRetainedBuild == true)
        nativeAttemptIDs.append(window?.activeCloseAttempt?.id)
    }

    func resetReaderCalls() {
        widths.removeAll()
        managedBuilds.removeAll()
        nativeAttemptIDs.removeAll()
    }
}

@MainActor
private final class CloseHistorySidebarModel: ObservableObject {
    @Published var width = 120.0
}

@MainActor
private struct CloseHistoryObservedReaderContent: View {
    @ObservedObject var model: CloseHistorySidebarModel
    let probe: CloseHistoryReaderProbe

    var body: some View {
        let width = model.width
        probe.rootBodyCalls += 1
        return HStack(spacing: 0) {
            WinSwiftUI.Color.clear.frame(width: width)
            GeometryReader { proxy in
                let _ = probe.record(width: proxy.size.width)
                WinSwiftUI.Color.clear.windowDismissBehavior(.enabled)
            }
        }
    }
}

@MainActor
private struct CloseHistoryStateReaderContent: View {
    @State private var restrictResolvedPolicy = false
    let probe: CloseHistoryReaderProbe

    var body: some View {
        probe.restriction = $restrictResolvedPolicy
        probe.rootBodyCalls += 1
        // Freeze the root build's value in this reader configuration. Reading
        // live State from the deferred closure would test a different lifetime.
        let restrictionSnapshot = restrictResolvedPolicy
        return HStack(spacing: 0) {
            WinSwiftUI.Color.clear.frame(width: 120)
            GeometryReader { proxy in
                let _ = probe.record(width: proxy.size.width)
                WinSwiftUI.Color.clear.windowDismissBehavior(
                    restrictionSnapshot && proxy.size.width < 300 ? .disabled : .enabled)
            }
        }
    }
}

@MainActor
private func closeHistoryReader(in runtime: RetainedViewRuntime) throws -> ViewNode {
    var pending = [runtime.root]
    while let node = pending.popLast() {
        if node.geometryReaderBuild != nil { return node }
        pending.append(contentsOf: node.children)
    }
    return try XCTUnwrap(nil, "The host fixture must contain its managed GeometryReader")
}

@MainActor
private final class CloseHistoryEpoch: RetainedBuildEpoch {
    private(set) var canAdopt = true
    private(set) var events: [String] = []

    func supersede() {
        canAdopt = false
        events.append("supersede")
    }

    func willAdopt() -> Bool {
        events.append("willAdopt")
        return canAdopt
    }

    func commit() {
        canAdopt = false
        events.append("commit")
    }

    func abandon() {
        canAdopt = false
        events.append("abandon")
    }

    func finishAfterCallbacks() { events.append("finish") }
}

@MainActor
private func assertNativeCloseRejectsFinishedCoordinatedBuild(
    abandoned: Bool, file: StaticString = #filePath, line: UInt = #line
) throws {
    let harness = try makeCloseHost(Text("Coordinated build history"))
    let runtime = harness.host.hostedRuntime
    let participant = CloseHostParticipant()
    let neutral = CloseHostNeutral()
    defer {
        neutral.vote = nil
        destroyCloseHostWindow(harness.window)
    }
    let coordinator = runtime.retainedBuildCoordinator
    let epoch = CloseHistoryEpoch()
    var originalReceipt: RetainedLayoutSettlementReceipt?
    var preflightPass: UInt64?
    let frameCount = harness.renderer.renderedFrames.count
    let sceneCount = harness.batchRenderer.renderedScenes.count
    XCTAssertFalse(runtime.isDirty, file: file, line: line)
    XCTAssertTrue(harness.host.setWindowCloseParticipant(participant), file: file, line: line)
    neutral.vote = { _ in
        guard case .settled(let receipt) = runtime.layoutSettlementStatus else {
            XCTFail("The host must have prepared its original receipt before the late vote", file: file, line: line)
            return false
        }
        originalReceipt = receipt
        preflightPass = runtime.layoutPassID
        let originalFrame = runtime.root.frame
        let originalDirty = runtime.isDirty
        guard let sequence = coordinator.beginBuild() else {
            XCTFail("The fixture starts exactly one idle coordinated build", file: file, line: line)
            return false
        }
        // This is a synthetic epoch at the shared coordinator boundary, not
        // a claim that a root or GeometryReader candidate was adopted here.
        coordinator.install(epoch, startedAt: sequence)
        if abandoned {
            epoch.abandon()
        } else {
            XCTAssertTrue(epoch.willAdopt(), file: file, line: line)
            epoch.commit()
        }
        epoch.finishAfterCallbacks()
        coordinator.finishBuild()

        XCTAssertTrue(coordinator.isBuildSettled, file: file, line: line)
        XCTAssertFalse(runtime.hasActiveRetainedBuild, file: file, line: line)
        XCTAssertEqual(runtime.root.frame, originalFrame, file: file, line: line)
        XCTAssertEqual(runtime.isDirty, originalDirty, file: file, line: line)
        XCTAssertEqual(runtime.layoutPassID, preflightPass, file: file, line: line)
        XCTAssertFalse(runtime.isLayoutSettlementReceiptCurrent(receipt), file: file, line: line)
        return true
    }
    harness.window.setPlatformWindowHost(neutral)
    let ticket = try closeHostTicket(harness.host)

    XCTAssertEqual(harness.window.attemptClose(ticket: ticket), .unavailable, file: file, line: line)

    let receipt = try XCTUnwrap(originalReceipt, file: file, line: line)
    XCTAssertFalse(runtime.isLayoutSettlementReceiptCurrent(receipt), file: file, line: line)
    XCTAssertEqual(
        epoch.events, abandoned ? ["abandon", "finish"] : ["willAdopt", "commit", "finish"], file: file, line: line)
    XCTAssertEqual(runtime.layoutPassID, preflightPass, file: file, line: line)
    XCTAssertEqual(harness.host.executedReloadCount, 0, file: file, line: line)
    XCTAssertEqual(harness.renderer.renderedFrames.count, frameCount, file: file, line: line)
    XCTAssertEqual(harness.batchRenderer.renderedScenes.count, sceneCount, file: file, line: line)
    XCTAssertEqual(participant.calls.votes, 1, file: file, line: line)
    XCTAssertEqual(participant.calls.preparations, 0, file: file, line: line)
    XCTAssertEqual(participant.calls.validations, 0, file: file, line: line)
    XCTAssertTrue(participant.calls.finishes.isEmpty, file: file, line: line)
    XCTAssertEqual(neutral.votes, 1, file: file, line: line)
    XCTAssertFalse(ticket.isCurrent, file: file, line: line)
    assertCloseHostStillAlive(harness, file: file, line: line)
}

@MainActor
extension WindowCloseFinalizationTests {
    func testNativePreflightOwnedFlushAndManagedReaderLayoutCanClose() async throws {
        let model = CloseHistorySidebarModel()
        let probe = CloseHistoryReaderProbe()
        let harness = try makeCloseHost(CloseHistoryObservedReaderContent(model: model, probe: probe))
        let runtime = harness.host.hostedRuntime
        let participant = CloseHostParticipant()
        let neutral = CloseHostNeutral()
        defer {
            neutral.vote = nil
            destroyCloseHostWindow(harness.window)
        }
        probe.runtime = runtime
        probe.window = harness.window
        let reader = try closeHistoryReader(in: runtime)
        XCTAssertNotNil(reader.retainedSubtreeBuildLease)
        XCTAssertEqual(reader.geometryReaderBuiltSize?.width, 240)
        let originalPass = runtime.layoutPassID
        let originalRootBodyCalls = probe.rootBodyCalls
        let originalResolveCount = runtime.geometryReaderResolveCount
        let frameCount = harness.renderer.renderedFrames.count
        let sceneCount = harness.batchRenderer.renderedScenes.count
        probe.resetReaderCalls()
        XCTAssertTrue(harness.host.setWindowCloseParticipant(participant))
        var passAtNeutralVote: UInt64?
        var attemptIDAtNeutralVote: Foundation.UUID?
        neutral.vote = { window in
            passAtNeutralVote = runtime.layoutPassID
            attemptIDAtNeutralVote = window.activeCloseAttempt?.id
            XCTAssertEqual(reader.geometryReaderBuiltSize?.width, 210)
            XCTAssertTrue(runtime.retainedBuildCoordinator.isBuildSettled)
            return true
        }
        harness.window.setPlatformWindowHost(neutral)
        // This real frame-width change already invalidates layout. No raw
        // reader metadata or extra layout query is used to prepare the test.
        model.width = 150
        XCTAssertEqual(harness.host.scheduledReloadCount, 1)
        XCTAssertEqual(harness.host.executedReloadCount, 0)
        XCTAssertEqual(probe.rootBodyCalls, originalRootBodyCalls)
        let ticket = try closeHostTicket(harness.host)

        XCTAssertEqual(harness.window.attemptClose(ticket: ticket), .closed)

        let attemptID = try XCTUnwrap(attemptIDAtNeutralVote)
        XCTAssertEqual(probe.rootBodyCalls, originalRootBodyCalls + 1)
        XCTAssertEqual(probe.widths, [360, 210])
        XCTAssertEqual(probe.managedBuilds, [true, true])
        XCTAssertEqual(probe.nativeAttemptIDs, [attemptID, attemptID])
        XCTAssertEqual(harness.host.executedReloadCount, 1)
        XCTAssertEqual(harness.host.completedObservedObjectReloadTaskCount, 1)
        XCTAssertEqual(runtime.geometryReaderResolveCount, originalResolveCount + 1)
        XCTAssertGreaterThan(runtime.layoutPassID, originalPass)
        XCTAssertEqual(runtime.layoutPassID, passAtNeutralVote, "Final validation must not run another layout query")
        XCTAssertEqual(harness.renderer.renderedFrames.count, frameCount)
        XCTAssertEqual(harness.batchRenderer.renderedScenes.count, sceneCount)
        XCTAssertEqual(participant.calls.finishes, [.closed])
        XCTAssertFalse(ticket.isCurrent)
        XCTAssertNil(harness.window.nativeHandle)
    }

    func testNativeLateStateReaderReplacementInvalidatesOriginalReceiptWithoutAnotherQuery() async throws {
        let probe = CloseHistoryReaderProbe()
        let harness = try makeCloseHost(CloseHistoryStateReaderContent(probe: probe))
        let runtime = harness.host.hostedRuntime
        // Initial reader adoption can legitimately stage follow-up layout.
        // Complete that ordinary work before capturing the clean baseline.
        _ = runtime.resolvedLayoutFrame(of: runtime.root)
        _ = runtime.renderScene()
        let participant = CloseHostParticipant()
        let neutral = CloseHostNeutral()
        defer {
            neutral.vote = nil
            destroyCloseHostWindow(harness.window)
        }
        probe.runtime = runtime
        probe.window = harness.window
        let restriction = try XCTUnwrap(probe.restriction)
        let reader = try closeHistoryReader(in: runtime)
        let originalLease = try XCTUnwrap(reader.retainedSubtreeBuildLease)
        let originalFrame = reader.frame
        let originalResolvedFrame = reader.resolvedFrame
        let originalRootBodyCalls = probe.rootBodyCalls
        let frameCount = harness.renderer.renderedFrames.count
        let sceneCount = harness.batchRenderer.renderedScenes.count
        XCTAssertFalse(runtime.isDirty, "The fixture must begin after ordinary rendering cleared layout dirtiness")
        XCTAssertEqual(reader.geometryReaderBuiltSize?.width, 240)
        XCTAssertEqual(reader.resolvedFrame.size.width, 240)
        XCTAssertEqual(runtime.windowDismissalBehavior, .enabled)
        probe.resetReaderCalls()
        var originalReceipt: RetainedLayoutSettlementReceipt?
        var preflightPass: UInt64?
        XCTAssertTrue(harness.host.setWindowCloseParticipant(participant))
        neutral.vote = { _ in
            guard case .settled(let receipt) = runtime.layoutSettlementStatus else {
                XCTFail("The late State write must follow a successful host preflight")
                return false
            }
            originalReceipt = receipt
            preflightPass = runtime.layoutPassID
            restriction.wrappedValue = true

            XCTAssertEqual(harness.host.executedReloadCount, 1)
            XCTAssertTrue(runtime.retainedBuildCoordinator.isBuildSettled)
            XCTAssertEqual(reader.frame, originalFrame)
            XCTAssertEqual(reader.resolvedFrame, originalResolvedFrame)
            XCTAssertEqual(reader.geometryReaderBuiltSize?.width, 360)
            XCTAssertNotNil(reader.retainedSubtreeBuildLease)
            XCTAssertFalse(reader.retainedSubtreeBuildLease === originalLease)
            XCTAssertEqual(runtime.windowDismissalBehavior, .enabled, "The canvas seed still permits close")
            XCTAssertEqual(runtime.layoutPassID, preflightPass)
            XCTAssertFalse(runtime.isLayoutSettlementReceiptCurrent(receipt))
            return true
        }
        harness.window.setPlatformWindowHost(neutral)
        let ticket = try closeHostTicket(harness.host)

        XCTAssertEqual(harness.window.attemptClose(ticket: ticket), .unavailable)

        let receipt = try XCTUnwrap(originalReceipt)
        XCTAssertFalse(runtime.isLayoutSettlementReceiptCurrent(receipt))
        XCTAssertTrue(try closeHistoryReader(in: runtime) === reader)
        XCTAssertEqual(probe.rootBodyCalls, originalRootBodyCalls + 1)
        XCTAssertEqual(probe.widths, [360], "The late root replacement must not get another resolved-slot query")
        XCTAssertEqual(harness.host.executedReloadCount, 1)
        XCTAssertEqual(
            harness.host.scheduledReloadCount, 0, "State rebuilt synchronously instead of parking an observation")
        XCTAssertEqual(runtime.layoutPassID, preflightPass)
        XCTAssertEqual(harness.renderer.renderedFrames.count, frameCount)
        XCTAssertEqual(harness.batchRenderer.renderedScenes.count, sceneCount)
        XCTAssertEqual(participant.calls.votes, 1)
        XCTAssertEqual(participant.calls.preparations, 0)
        XCTAssertEqual(participant.calls.validations, 0)
        XCTAssertTrue(participant.calls.finishes.isEmpty)
        XCTAssertEqual(neutral.votes, 1)
        XCTAssertFalse(ticket.isCurrent)
        assertCloseHostStillAlive(harness)
        // Fresh-query evaluation of this newly captured reader is a separate
        // regression; this case proves only rejection of the original receipt.
    }

    func testNativeLateCompletedCoordinatedEpochInvalidatesOriginalReceipt() async throws {
        try assertNativeCloseRejectsFinishedCoordinatedBuild(abandoned: false)
    }

    func testNativeLateAbandonedCoordinatedEpochInvalidatesOriginalReceipt() async throws {
        try assertNativeCloseRejectsFinishedCoordinatedBuild(abandoned: true)
    }
}

// Reader replacement is evaluated from a fresh ordinary query, including
// reentrant rendering when an old, application-owned capture is released.
@MainActor
private func makeHeadlessCloseReaderHost<Content: View>(_ content: Content) -> CloseHostHarness {
    let size = IntSize(width: 360, height: 220)
    let surface = SurfaceDescriptor(offscreenPixelSize: size, scaleFactor: 1)
    let renderer = FakeRenderBackend()
    let batchRenderer = FakeBatchRenderBackend()
    let window = Win32Window(title: "Headless reader replacement", clientSize: size)
    window.postsQuitMessageOnDestroy = false
    window.testScaleFactorOverride = 1
    let host = WinSwiftUIWindowHost(
        configuration: WindowGroupConfiguration(
            title: "Headless reader replacement", size: size, clearColor: .black,
            content: [AnyView(content)]),
        platformWindow: window, renderer: renderer, batchRenderer: batchRenderer,
        surfaceDescriptorProvider: { _ in surface }, startupProbeConfiguration: nil)
    host.frameClock = { 12_000 }
    host.hostedRuntime.clock = { 12_000 }
    host.windowDidCreate(window)
    return CloseHostHarness(host: host, renderer: renderer, batchRenderer: batchRenderer)
}

private struct CloseReaderReleaseObservation {
    let generation: Int
    let builtWidth: Double?
    let slotWidth: Double
    let buildWasActive: Bool
    let leaseWasReplaced: Bool
    let leaseWasBuildable: Bool?
    let contentRevisionBefore: UInt64
    let contentRevisionAfter: UInt64
    let layoutPassBefore: UInt64
    let layoutPassAfter: UInt64
    let bodyCallsBefore: Int
    let bodyCallsAfter: Int
    let runtimeDirtyAfterRender: Bool
    let subtreeDirtyAfterRender: Bool
}

@MainActor
private final class CloseReaderCleanupProbe {
    weak var runtime: RetainedViewRuntime?
    weak var reader: ViewNode?
    weak var originalLease: (any RetainedSubtreeBuildLease)?
    weak var payload: CloseHostReleaseProbe?
    var restriction: Binding<Bool>?
    var rootGeneration = 0
    var latestPayloadGeneration = 0
    var armedGeneration: Int?
    var releaseCount = 0
    var expectedBuiltWidth = 0.0
    var widths: [Double] = []
    var observations: [CloseReaderReleaseObservation] = []

    func makePayload(restricted: Bool, generation: Int) -> CloseHostReleaseProbe? {
        guard !restricted else { return nil }
        let payload = CloseHostReleaseProbe { [weak self] in self?.released(generation: generation) }
        self.payload = payload
        latestPayloadGeneration = generation
        return payload
    }

    func arm() {
        XCTAssertNotNil(payload, "The settled reader must still own the old capture")
        XCTAssertGreaterThan(latestPayloadGeneration, 0)
        armedGeneration = latestPayloadGeneration
    }

    private func released(generation: Int) {
        guard armedGeneration == generation else { return }
        // Startup can build the root more than once. Only its settled old
        // generation is armed, and it is disarmed before the nested render.
        armedGeneration = nil
        releaseCount += 1
        guard let runtime, let reader, let originalLease else {
            XCTFail("The armed capture must release while its original host and reader remain alive")
            return
        }
        let builtWidth = reader.geometryReaderBuiltSize?.width
        let slotWidth = reader.resolvedFrame.size.width
        let buildWasActive = runtime.hasActiveRetainedBuild
        let lease = reader.retainedSubtreeBuildLease
        let leaseWasReplaced = lease !== originalLease
        let leaseWasBuildable = lease?.canBuild
        let contentRevisionBefore = runtime.contentRevision
        let layoutPassBefore = runtime.layoutPassID
        let bodyCallsBefore = widths.count
        XCTAssertEqual(builtWidth, expectedBuiltWidth, "The fixture must actually reach the claimed release phase")
        XCTAssertEqual(slotWidth, 240)
        XCTAssertTrue(buildWasActive)
        XCTAssertNotNil(lease)
        XCTAssertTrue(leaseWasReplaced)
        XCTAssertEqual(leaseWasBuildable, false, "The adopted reader's new lease must still be provisional")
        XCTAssertNotNil(reader.geometryReaderBuild)

        // The baseline was rendered as a scene, leaving no frame cache. This
        // public frame render must traverse even if the before-copy path is clean.
        _ = runtime.renderFrame(at: 12_000.08)

        XCTAssertEqual(runtime.contentRevision, contentRevisionBefore + 1)
        XCTAssertGreaterThan(runtime.layoutPassID, layoutPassBefore)
        XCTAssertEqual(widths.count, bodyCallsBefore, "A provisional lease must not evaluate the replacement body")
        if expectedBuiltWidth == 360 {
            XCTAssertTrue(runtime.isDirty, "The denied managed build must survive render cleanup as pending layout")
            XCTAssertTrue(runtime.root.hasDirtySubtree)
        }
        observations.append(
            CloseReaderReleaseObservation(
                generation: generation, builtWidth: builtWidth, slotWidth: slotWidth,
                buildWasActive: buildWasActive, leaseWasReplaced: leaseWasReplaced,
                leaseWasBuildable: leaseWasBuildable,
                contentRevisionBefore: contentRevisionBefore, contentRevisionAfter: runtime.contentRevision,
                layoutPassBefore: layoutPassBefore, layoutPassAfter: runtime.layoutPassID,
                bodyCallsBefore: bodyCallsBefore, bodyCallsAfter: widths.count,
                runtimeDirtyAfterRender: runtime.isDirty, subtreeDirtyAfterRender: runtime.root.hasDirtySubtree))
    }
}

@MainActor
private struct CloseReaderCleanupContent: View {
    @State private var restrictResolvedPolicy = false
    let sharesPayloadWithChild: Bool
    let probe: CloseReaderCleanupProbe

    var body: some View {
        probe.restriction = $restrictResolvedPolicy
        probe.rootGeneration += 1
        let restrictionSnapshot = restrictResolvedPolicy
        let payload = probe.makePayload(restricted: restrictionSnapshot, generation: probe.rootGeneration)
        return HStack(spacing: 0) {
            WinSwiftUI.Color.clear.frame(width: 120)
            GeometryReader { proxy in
                let _ = withExtendedLifetime(payload) {}
                let _ = probe.widths.append(proxy.size.width)
                if sharesPayloadWithChild {
                    WinSwiftUI.Color.clear.windowDismissBehavior(
                        restrictionSnapshot && proxy.size.width < 300 ? .disabled : .enabled
                    ).onDisappear { [payload] in
                        withExtendedLifetime(payload) {}
                    }
                } else {
                    WinSwiftUI.Color.clear.windowDismissBehavior(
                        restrictionSnapshot && proxy.size.width < 300 ? .disabled : .enabled)
                }
            }
        }
    }
}

@MainActor
private func assertHeadlessReaderCaptureReleasePreservesFreshLayout(sharesPayloadWithChild: Bool) throws {
    let probe = CloseReaderCleanupProbe()
    probe.expectedBuiltWidth = sharesPayloadWithChild ? 360 : 240
    let harness = makeHeadlessCloseReaderHost(
        CloseReaderCleanupContent(sharesPayloadWithChild: sharesPayloadWithChild, probe: probe))
    let runtime = harness.host.hostedRuntime
    defer {
        probe.armedGeneration = nil
        harness.host.windowWillClose(harness.window)
    }
    // Complete ordinary startup follow-up layout before arming cleanup.
    // Scene rendering also removes the alternate frame cache used by deinit.
    _ = runtime.resolvedLayoutFrame(of: runtime.root)
    _ = runtime.renderScene(at: 12_000.04)
    XCTAssertFalse(runtime.isDirty)
    XCTAssertFalse(runtime.root.hasDirtySubtree)
    let reader = try closeHistoryReader(in: runtime)
    let originalLease = try XCTUnwrap(reader.retainedSubtreeBuildLease)
    let restriction = try XCTUnwrap(probe.restriction)
    probe.runtime = runtime
    probe.reader = reader
    probe.originalLease = originalLease
    probe.widths.removeAll()
    harness.host.resetObservabilityCounters()
    let originalGeneration = probe.rootGeneration
    let originalPass = runtime.layoutPassID
    let originalContentRevision = runtime.contentRevision
    let originalResolveCount = runtime.geometryReaderResolveCount
    let frameCount = harness.renderer.renderedFrames.count
    let sceneCount = harness.batchRenderer.renderedScenes.count
    XCTAssertEqual(reader.geometryReaderBuiltSize?.width, 240)
    XCTAssertEqual(reader.resolvedFrame.size.width, 240)
    XCTAssertEqual(runtime.windowDismissalBehavior, .enabled)
    XCTAssertNil(harness.window.nativeHandle, "These two cleanup fixtures never create a native window")
    probe.arm()

    withExtendedLifetime(originalLease) {
        restriction.wrappedValue = true
    }

    XCTAssertEqual(probe.releaseCount, 1, "The armed capture must release during the State replacement")
    XCTAssertEqual(probe.observations.count, 1)
    let observation = try XCTUnwrap(probe.observations.first)
    XCTAssertEqual(observation.generation, originalGeneration)
    XCTAssertEqual(observation.builtWidth, sharesPayloadWithChild ? 360 : 240)
    XCTAssertEqual(observation.slotWidth, 240)
    XCTAssertTrue(observation.buildWasActive)
    XCTAssertTrue(observation.leaseWasReplaced)
    XCTAssertEqual(observation.leaseWasBuildable, false)
    XCTAssertEqual(observation.contentRevisionBefore, originalContentRevision)
    XCTAssertEqual(observation.contentRevisionAfter, originalContentRevision + 1)
    XCTAssertEqual(observation.layoutPassBefore, originalPass)
    XCTAssertGreaterThan(observation.layoutPassAfter, observation.layoutPassBefore)
    XCTAssertEqual(observation.bodyCallsBefore, 1)
    XCTAssertEqual(observation.bodyCallsAfter, 1)
    if sharesPayloadWithChild {
        XCTAssertTrue(observation.runtimeDirtyAfterRender)
        XCTAssertTrue(observation.subtreeDirtyAfterRender)
    }
    XCTAssertNil(probe.armedGeneration)
    XCTAssertNil(probe.payload)
    XCTAssertEqual(probe.rootGeneration, originalGeneration + 1)
    XCTAssertEqual(probe.widths, [360], "The nested render must leave the resolved body pending")
    XCTAssertEqual(harness.host.executedReloadCount, 1)
    XCTAssertTrue(runtime.retainedBuildCoordinator.isBuildSettled)
    XCTAssertTrue(try closeHistoryReader(in: runtime) === reader)
    XCTAssertEqual(reader.geometryReaderBuiltSize?.width, 360)
    XCTAssertEqual(reader.resolvedFrame.size.width, 240)
    XCTAssertEqual(runtime.windowDismissalBehavior, .enabled)
    XCTAssertTrue(runtime.isDirty)
    XCTAssertTrue(runtime.root.hasDirtySubtree)
    XCTAssertEqual(runtime.geometryReaderResolveCount, originalResolveCount)

    _ = runtime.resolvedLayoutFrame(of: runtime.root)

    XCTAssertEqual(probe.widths, [360, 240])
    XCTAssertEqual(reader.geometryReaderBuiltSize?.width, 240)
    XCTAssertEqual(runtime.windowDismissalBehavior, .disabled)
    XCTAssertEqual(runtime.geometryReaderResolveCount, originalResolveCount + 1)
    XCTAssertEqual(runtime.contentRevision, observation.contentRevisionAfter)
    XCTAssertTrue(runtime.retainedBuildCoordinator.isBuildSettled)
    let resolvedBodyCalls = probe.widths.count
    let resolvedBuilds = runtime.geometryReaderResolveCount

    _ = runtime.resolvedLayoutFrame(of: runtime.root)

    XCTAssertEqual(probe.widths.count, resolvedBodyCalls)
    XCTAssertEqual(runtime.geometryReaderResolveCount, resolvedBuilds)
    XCTAssertEqual(runtime.contentRevision, observation.contentRevisionAfter)
    XCTAssertEqual(probe.releaseCount, 1)
    XCTAssertEqual(harness.renderer.renderedFrames.count, frameCount)
    XCTAssertEqual(harness.batchRenderer.renderedScenes.count, sceneCount)
    XCTAssertEqual(harness.renderer.detachCount, 0)
    XCTAssertEqual(harness.batchRenderer.detachCount, 0)
    XCTAssertNil(harness.window.nativeHandle)
}

@MainActor
extension WindowCloseFinalizationTests {
    func testNativeFreshStateReaderReplacementResolvesCurrentPolicyBeforeClose() async throws {
        let probe = CloseHistoryReaderProbe()
        let harness = try makeCloseHost(CloseHistoryStateReaderContent(probe: probe))
        let runtime = harness.host.hostedRuntime
        defer { destroyCloseHostWindow(harness.window) }
        _ = runtime.resolvedLayoutFrame(of: runtime.root)
        _ = runtime.renderScene()
        XCTAssertFalse(runtime.isDirty)
        XCTAssertFalse(runtime.root.hasDirtySubtree)
        probe.runtime = runtime
        probe.window = harness.window
        let restriction = try XCTUnwrap(probe.restriction)
        let reader = try closeHistoryReader(in: runtime)
        let participant = CloseHostParticipant()
        XCTAssertTrue(harness.host.setWindowCloseParticipant(participant))
        XCTAssertEqual(reader.geometryReaderBuiltSize?.width, 240)
        XCTAssertEqual(reader.resolvedFrame.size.width, 240)
        XCTAssertEqual(runtime.windowDismissalBehavior, .enabled)
        let originalRootBodyCalls = probe.rootBodyCalls
        let originalPass = runtime.layoutPassID
        let originalContentRevision = runtime.contentRevision
        let originalResolveCount = runtime.geometryReaderResolveCount
        let frameCount = harness.renderer.renderedFrames.count
        let sceneCount = harness.batchRenderer.renderedScenes.count
        probe.resetReaderCalls()

        restriction.wrappedValue = true

        XCTAssertEqual(probe.rootBodyCalls, originalRootBodyCalls + 1)
        XCTAssertEqual(probe.widths, [360])
        XCTAssertEqual(reader.geometryReaderBuiltSize?.width, 360)
        XCTAssertEqual(runtime.windowDismissalBehavior, .enabled, "The root build's canvas seed still permits close")
        XCTAssertEqual(runtime.layoutPassID, originalPass, "Do not resolve the new reader before native preflight")
        XCTAssertTrue(runtime.isDirty)
        let ticket = try closeHostTicket(harness.host)

        XCTAssertEqual(harness.window.attemptClose(ticket: ticket), .vetoed)

        assertCloseHostStillAlive(harness)
        XCTAssertEqual(probe.widths, [360, 240])
        XCTAssertEqual(reader.geometryReaderBuiltSize?.width, 240)
        XCTAssertEqual(runtime.windowDismissalBehavior, .disabled)
        XCTAssertEqual(runtime.geometryReaderResolveCount, originalResolveCount + 1)
        XCTAssertEqual(runtime.contentRevision, originalContentRevision)
        XCTAssertEqual(participant.calls.votes, 0)
        XCTAssertEqual(participant.calls.preparations, 0)
        XCTAssertTrue(participant.calls.finishes.isEmpty)
        XCTAssertFalse(ticket.isCurrent)
        let resolvedBodyCalls = probe.widths.count
        let resolvedBuilds = runtime.geometryReaderResolveCount

        _ = runtime.resolvedLayoutFrame(of: runtime.root)

        XCTAssertEqual(probe.widths.count, resolvedBodyCalls, "An unchanged ordinary query must not rebuild the body")
        XCTAssertEqual(runtime.geometryReaderResolveCount, resolvedBuilds)
        XCTAssertEqual(runtime.contentRevision, originalContentRevision)
        XCTAssertEqual(harness.renderer.renderedFrames.count, frameCount)
        XCTAssertEqual(harness.batchRenderer.renderedScenes.count, sceneCount)
        assertCloseHostStillAlive(harness)
    }

    func testHeadlessReaderBodyCaptureReleaseBeforeSizeCopyLeavesFreshLayoutPending() async throws {
        try assertHeadlessReaderCaptureReleasePreservesFreshLayout(sharesPayloadWithChild: false)
    }

    func testHeadlessReaderChildCaptureReleaseDuringProvisionalLeasePreservesLayout() async throws {
        try assertHeadlessReaderCaptureReleasePreservesFreshLayout(sharesPayloadWithChild: true)
    }
}
