import SwiftWindowsCore
@preconcurrency import XCTest

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
