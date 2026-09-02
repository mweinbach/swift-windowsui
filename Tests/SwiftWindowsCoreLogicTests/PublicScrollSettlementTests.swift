import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsLayout
import XCTest

@testable import SwiftWindowsUI

/// Public scrolling after a layout-only query must use that original geometry.
/// These windowless fixtures retain render dirtiness deliberately. They do not
/// acquire UIA or List-navigation admission, paint to repair a failed request,
/// or install a synthetic layout frame on a target.
@MainActor
final class PublicScrollSettlementTests: XCTestCase {
    func testQueryOnlySettlementScrollsBothAxesWithoutRendering() async throws {
        for axis in [ScrollAxis.vertical, .horizontal] {
            let fixture = PublicScrollSettlementFixture(axis: axis)
            defer { fixture.retire() }
            let original = try fixture.prepareQuery()
            let pass = fixture.runtime.layoutPassID
            fixture.probe.clockCalls = 0
            fixture.runtime.clock = { [clock = fixture.clock, weak probe = fixture.probe] in
                probe?.clockCalls += 1
                return clock.value
            }

            XCTAssertTrue(fixture.scroll(to: 8))

            XCTAssertEqual(fixture.container.scrollOffset, 320, accuracy: 0.0001)
            XCTAssertEqual(fixture.runtime.layoutPassID, pass, "Scrolling must not run another layout query")
            XCTAssertTrue(fixture.runtime.hasPendingLayout)
            XCTAssertTrue(fixture.runtime.isDirty, "The later render must still receive its dirty work")
            XCTAssertEqual(fixture.probe.clockCalls, 1)
            XCTAssertTrue(fixture.runtime.isLayoutSettlementReceiptCurrent(original))
        }
    }

    func testQueriedResizeAndInsertionUseTheirActualGeometry() async throws {
        let fixture = PublicScrollSettlementFixture()
        defer { fixture.retire() }
        fixture.container.frame.size.height = 100
        let inserted = ViewNode(preferredSize: Size(width: 220, height: 40), isHitTestVisible: false)
        fixture.container.addChild(inserted)
        _ = try fixture.settlePendingQuery()
        XCTAssertEqual(inserted.resolvedFrame.origin.y, 800, accuracy: 0.0001)
        XCTAssertEqual(fixture.container.resolvedFrame.height, 100, accuracy: 0.0001)
        let pass = fixture.runtime.layoutPassID

        XCTAssertTrue(fixture.runtime.scrollToDescendant(inserted, transaction: Transaction()))

        XCTAssertEqual(fixture.container.scrollOffset, 740, accuracy: 0.0001)
        XCTAssertEqual(fixture.runtime.layoutPassID, pass)
        XCTAssertTrue(fixture.runtime.hasPendingLayout)
    }

    func testUnqueriedViewportResizeRemainsPending() async throws {
        let fixture = PublicScrollSettlementFixture()
        defer { fixture.retire() }
        fixture.container.frame.size.height = 100
        XCTAssertTrue(fixture.runtime.hasPendingLayout)
        assertUnsettled(fixture.runtime)
        let pass = fixture.runtime.layoutPassID

        XCTAssertFalse(fixture.scroll(to: 8))

        XCTAssertEqual(fixture.container.scrollOffset, 0)
        XCTAssertEqual(fixture.runtime.layoutPassID, pass)
        XCTAssertTrue(fixture.runtime.hasPendingLayout)
    }

    func testUnqueriedNewChildRemainsPending() async throws {
        let fixture = PublicScrollSettlementFixture()
        defer { fixture.retire() }
        let inserted = ViewNode(preferredSize: Size(width: 220, height: 40), isHitTestVisible: false)
        fixture.container.addChild(inserted)
        XCTAssertTrue(fixture.runtime.hasPendingLayout)
        assertUnsettled(fixture.runtime)
        let pass = fixture.runtime.layoutPassID

        XCTAssertFalse(fixture.runtime.scrollToDescendant(inserted, anchorY: 0, transaction: Transaction()))

        XCTAssertEqual(fixture.container.scrollOffset, 0)
        XCTAssertEqual(fixture.runtime.layoutPassID, pass)
    }

    func testUnavailableSettlementCannotAuthorizeScroll() async throws {
        for exhaustGeometry in [true, false] {
            let fixture = PublicScrollSettlementFixture()
            defer { fixture.retire() }
            let original = try fixture.prepareQuery()
            if exhaustGeometry {
                fixture.runtime.exhaustLayoutGeometryGenerationOnNextInvalidationForTesting()
                fixture.container.frame.size.height += 1
            } else {
                fixture.runtime.exhaustLayoutResolutionGenerationOnNextQueryForTesting()
                XCTAssertNotNil(fixture.runtime.resolvedLayoutFrame(of: fixture.root))
            }
            guard case .unavailable = fixture.runtime.layoutSettlementStatus else {
                return XCTFail("The actual invalidation or query must exhaust settlement")
            }
            XCTAssertFalse(fixture.runtime.canPrepareLayoutSettlement)
            XCTAssertFalse(fixture.runtime.isLayoutSettlementReceiptCurrent(original))
            XCTAssertTrue(fixture.runtime.hasPendingLayout)

            XCTAssertFalse(fixture.scroll(to: 8))

            XCTAssertEqual(fixture.container.scrollOffset, 0)
        }
    }

    func testClockEqualFrameQueryCannotReplaceOriginalReceipt() async throws {
        let fixture = PublicScrollSettlementFixture()
        defer { fixture.retire() }
        let original = try fixture.prepareQuery()
        let targetFrame = fixture.rows[8].resolvedFrame
        let viewport = fixture.container.resolvedFrame
        fixture.runtime.clock = { [weak fixture] in
            guard let fixture else { return 10 }
            fixture.probe.clockCalls += 1
            fixture.restoreClock()
            XCTAssertTrue(fixture.runtime.isLayoutSettlementReceiptCurrent(original))
            XCTAssertNotNil(fixture.runtime.resolvedLayoutFrame(of: fixture.rows[8]))
            fixture.probe.layoutQueries += 1
            XCTAssertEqual(fixture.rows[8].resolvedFrame, targetFrame)
            XCTAssertEqual(fixture.container.resolvedFrame, viewport)
            XCTAssertFalse(fixture.runtime.isLayoutSettlementReceiptCurrent(original))
            XCTAssertTrue(fixture.runtime.hasPendingLayout)
            return fixture.clock.value
        }
        _ = try fixture.requireQuerySettlement()

        XCTAssertFalse(fixture.scroll(to: 8))

        XCTAssertEqual(fixture.probe.clockCalls, 1)
        XCTAssertEqual(fixture.probe.layoutQueries, 1)
        XCTAssertEqual(fixture.container.scrollOffset, 0)
        _ = try fixture.requireQuerySettlement()
    }

    func testClockRenderCannotFallBackAfterReplacingReceipt() async throws {
        let fixture = PublicScrollSettlementFixture()
        defer { fixture.retire() }
        let original = try fixture.prepareQuery()
        fixture.runtime.clock = { [weak fixture] in
            guard let fixture else { return 10 }
            fixture.probe.clockCalls += 1
            fixture.restoreClock()
            _ = fixture.runtime.renderFrame(at: fixture.clock.value)
            fixture.probe.renders += 1
            XCTAssertFalse(fixture.runtime.hasPendingLayout)
            XCTAssertFalse(fixture.runtime.isLayoutSettlementReceiptCurrent(original))
            return fixture.clock.value
        }
        _ = try fixture.requireQuerySettlement()

        XCTAssertFalse(fixture.scroll(to: 8))

        XCTAssertEqual(fixture.probe.clockCalls, 1)
        XCTAssertEqual(fixture.probe.renders, 1)
        XCTAssertEqual(fixture.container.scrollOffset, 0)
        XCTAssertFalse(fixture.runtime.hasPendingLayout)
    }

    func testClockCaptureDestructionCannotAuthorizeOffset() async throws {
        let fixture = PublicScrollSettlementFixture()
        defer { fixture.retire() }
        _ = try fixture.prepareQuery()
        let probe = installReplacingClock(on: fixture)
        XCTAssertNotNil(probe.payload)
        _ = try fixture.requireQuerySettlement()

        XCTAssertFalse(fixture.scroll(to: 8))

        XCTAssertEqual(probe.clockCalls, 1)
        XCTAssertEqual(probe.cleanups, 1)
        XCTAssertNil(probe.payload, "The sampled capture must retire before the request is acknowledged")
        XCTAssertEqual(probe.offsetAtCleanup, 0)
        XCTAssertEqual(fixture.container.scrollOffset, 0)
        XCTAssertEqual(fixture.container.frame.height, 122)
    }

    func testClockNestedDifferentScrollSupersedesOriginalIntent() async throws {
        try assertClockSupersession(.different)
    }

    func testClockNestedEqualScrollSupersedesOriginalIntent() async throws {
        try assertClockSupersession(.equal)
    }

    func testClockNestedAwayAndBackScrollSupersedesOriginalIntent() async throws {
        try assertClockSupersession(.awayAndBack)
    }

    func testClockAncestorRemovalAndReinsertionRetiresOriginalPath() async throws {
        let fixture = PublicScrollSettlementFixture()
        defer { fixture.retire() }
        _ = try fixture.prepareQuery()
        let originalPath = try XCTUnwrap(fixture.runtime.accessibilityTarget(for: fixture.rows[8]))
        let originalAttachment = fixture.wrapper.captureLazyListAttachmentProof()
        fixture.runtime.clock = { [weak fixture] in
            guard let fixture else { return 10 }
            fixture.probe.clockCalls += 1
            fixture.restoreClock()
            fixture.root.removeChild(fixture.wrapper)
            fixture.root.addChild(fixture.wrapper)
            fixture.probe.reinsertions += 1
            XCTAssertTrue(fixture.wrapper.parent === fixture.root)
            XCTAssertTrue(fixture.rows[8].retainedLazyListRuntime === fixture.runtime)
            return fixture.clock.value
        }
        _ = try fixture.requireQuerySettlement()

        XCTAssertFalse(fixture.scroll(to: 8))

        XCTAssertEqual(fixture.probe.clockCalls, 1)
        XCTAssertEqual(fixture.probe.reinsertions, 1)
        XCTAssertEqual(fixture.container.scrollOffset, 0)
        XCTAssertTrue(fixture.wrapper.parent === fixture.root)
        XCTAssertFalse(originalAttachment.isCurrent)
        withExtendedLifetime(originalPath) {}
    }

    func testClockAxisRemovalAndRestorationRetiresOriginalContainer() async throws {
        let fixture = PublicScrollSettlementFixture()
        defer { fixture.retire() }
        _ = try fixture.prepareQuery()
        let originalEpoch = try XCTUnwrap(fixture.container.scrollSourceEpoch)
        fixture.runtime.clock = { [weak fixture] in
            guard let fixture else { return 10 }
            fixture.probe.clockCalls += 1
            fixture.restoreClock()
            fixture.container.scrollAxis = nil
            fixture.container.scrollAxis = .vertical
            fixture.probe.axisReplacements += 1
            return fixture.clock.value
        }
        _ = try fixture.requireQuerySettlement()

        XCTAssertFalse(fixture.scroll(to: 8))

        XCTAssertEqual(fixture.probe.clockCalls, 1)
        XCTAssertEqual(fixture.probe.axisReplacements, 1)
        XCTAssertEqual(fixture.container.scrollAxis, .vertical)
        XCTAssertNotEqual(fixture.container.scrollSourceEpoch, originalEpoch)
        XCTAssertEqual(fixture.container.scrollOffset, 0)
    }

    func testClockMutationExhaustsOriginalSettlementBeforeOffset() async throws {
        let fixture = PublicScrollSettlementFixture()
        defer { fixture.retire() }
        let original = try fixture.prepareQuery()
        fixture.runtime.clock = { [weak fixture] in
            guard let fixture else { return 10 }
            fixture.probe.clockCalls += 1
            fixture.restoreClock()
            fixture.runtime.exhaustLayoutGeometryGenerationOnNextInvalidationForTesting()
            fixture.container.frame.size.height += 1
            return fixture.clock.value
        }
        _ = try fixture.requireQuerySettlement()

        XCTAssertFalse(fixture.scroll(to: 8))

        XCTAssertEqual(fixture.probe.clockCalls, 1)
        XCTAssertFalse(fixture.runtime.isLayoutSettlementReceiptCurrent(original))
        guard case .unavailable = fixture.runtime.layoutSettlementStatus else {
            return XCTFail("The clock's invalidation must leave unavailable settlement")
        }
        XCTAssertEqual(fixture.container.scrollOffset, 0)
    }

    func testNativeCancellationChecksGeometryOverflowBeforeEffects() async throws {
        let fixture = PublicScrollSettlementFixture(lazy: true)
        defer { fixture.retire() }
        fixture.runtime.mouseWheel(at: Point(x: 30, y: 30), delta: 3, source: .precise)
        XCTAssertLessThan(fixture.container.scrollOvershoot, 0)
        XCTAssertTrue(fixture.container.hasVirtualizedDescendants)
        let overshoot = fixture.container.scrollOvershoot
        fixture.runtime.exhaustLayoutGeometryGenerationOnNextInvalidationForTesting()
        _ = try fixture.settlePendingQuery()
        XCTAssertEqual(fixture.container.scrollOvershoot, overshoot)

        XCTAssertFalse(fixture.scroll(to: 8))

        XCTAssertEqual(fixture.container.scrollOffset, 0)
        XCTAssertEqual(
            fixture.container.scrollOvershoot, overshoot,
            "An unrepresentable owned successor must fail before cancelling the existing presentation")
    }

    func testQueryOnlyScrollCancelsNonzeroLazyOvershoot() async throws {
        let fixture = PublicScrollSettlementFixture(lazy: true)
        defer { fixture.retire() }
        fixture.runtime.mouseWheel(at: Point(x: 30, y: 30), delta: 3, source: .precise)
        XCTAssertLessThan(fixture.container.scrollOvershoot, 0)
        XCTAssertTrue(fixture.container.hasVirtualizedDescendants)
        XCTAssertTrue(fixture.runtime.hasActiveAnimations)
        _ = try fixture.settlePendingQuery()
        let pass = fixture.runtime.layoutPassID

        XCTAssertTrue(fixture.scroll(to: 8))

        XCTAssertEqual(fixture.container.scrollOvershoot, 0)
        XCTAssertEqual(fixture.container.scrollOffset, 320, accuracy: 0.0001)
        XCTAssertEqual(fixture.runtime.layoutPassID, pass)
        fixture.clock.value += 2
        _ = fixture.runtime.tickAnimations(at: fixture.clock.value)
        XCTAssertEqual(fixture.container.scrollOffset, 320, accuracy: 0.0001)
        XCTAssertEqual(fixture.container.scrollOvershoot, 0)
    }

    func testQueryOnlyScrollRetargetsRunningLazyTweenFromPresentedPosition() async throws {
        let fixture = PublicScrollSettlementFixture(lazy: true)
        defer { fixture.retire() }
        XCTAssertTrue(fixture.scroll(to: 10, transaction: Transaction(animation: .linear(duration: 1))))
        fixture.clock.value += 0.25
        _ = fixture.runtime.tickAnimations(at: fixture.clock.value)
        XCTAssertNotEqual(fixture.container.scrollPresentedDelta, 0)
        XCTAssertTrue(fixture.runtime.hasActiveAnimations)
        _ = try fixture.settlePendingQuery()
        let presented = fixture.container.resolvedScrollOffset
        XCTAssertEqual(presented, 100, accuracy: 0.0001)
        let pass = fixture.runtime.layoutPassID

        XCTAssertTrue(fixture.scroll(to: 15, transaction: Transaction(animation: .linear(duration: 1))))

        XCTAssertEqual(fixture.container.scrollOffset, 600, accuracy: 0.0001)
        XCTAssertEqual(fixture.container.scrollPresentedDelta, presented - 600, accuracy: 0.0001)
        XCTAssertEqual(fixture.runtime.layoutPassID, pass)
        fixture.clock.value += 1
        _ = fixture.runtime.tickAnimations(at: fixture.clock.value)
        _ = fixture.runtime.renderFrame(at: fixture.clock.value)
        XCTAssertEqual(fixture.container.resolvedScrollOffset, 600, accuracy: 0.0001)
        XCTAssertEqual(fixture.container.scrollPresentedDelta, 0)
    }

    func testMatchingIndicatorCancellationUsesOneClockAndStopsOldDrag() async throws {
        let fixture = PublicScrollSettlementFixture(chrome: true)
        defer { fixture.retire() }
        fixture.runtime.pointerMoved(to: fixture.firstHoverPoint)
        let thumb = try fixture.beginIndicatorDrag()
        fixture.clock.value += 0.05
        _ = fixture.runtime.tickAnimations(at: fixture.clock.value)
        XCTAssertTrue(fixture.firstHover.isHovered)
        XCTAssertNotEqual(fixture.firstHover.backgroundColor, Color.white)
        _ = try fixture.prepareQuery()
        fixture.probe.clockCalls = 0
        fixture.runtime.clock = { [clock = fixture.clock, weak probe = fixture.probe] in
            probe?.clockCalls += 1
            return clock.value
        }
        _ = try fixture.requireQuerySettlement()

        XCTAssertTrue(fixture.scroll(to: 15))

        XCTAssertEqual(fixture.probe.clockCalls, 1, "Cancellation chrome must reuse the admitted timestamp")
        XCTAssertEqual(fixture.probe.firstHoverExits, 1)
        XCTAssertFalse(fixture.firstHover.isHovered)
        XCTAssertEqual(fixture.container.scrollOffset, 600, accuracy: 0.0001)
        fixture.restoreClock()
        fixture.runtime.pointerMoved(to: Point(x: thumb.x, y: thumb.y + 30))
        XCTAssertEqual(fixture.container.scrollOffset, 600, accuracy: 0.0001)
        fixture.clock.value += 1
        _ = fixture.runtime.tickAnimations(at: fixture.clock.value)
        XCTAssertEqual(fixture.firstHover.backgroundColor, Color.white)
    }

    func testExitInstalledHoverSurvivesAndStopsOldRequest() async throws {
        let fixture = PublicScrollSettlementFixture()
        defer { fixture.retire() }
        fixture.runtime.pointerMoved(to: fixture.firstHoverPoint)
        _ = try fixture.beginIndicatorDrag()
        fixture.firstHover.onPointerExit = { [weak fixture] in
            guard let fixture else { return }
            fixture.probe.firstHoverExits += 1
            fixture.firstHover.onPointerExit = nil
            fixture.runtime.pointerMoved(to: fixture.secondHoverPoint)
        }
        _ = try fixture.prepareQuery()

        XCTAssertFalse(fixture.scroll(to: 15))

        XCTAssertEqual(fixture.probe.firstHoverExits, 1)
        XCTAssertEqual(fixture.probe.secondHoverEnters, 1)
        XCTAssertTrue(fixture.secondHover.isHovered)
        XCTAssertEqual(fixture.container.scrollOffset, 0)
        fixture.runtime.pointerExitedWindow()
        XCTAssertEqual(fixture.probe.secondHoverExits, 1)
        XCTAssertFalse(fixture.secondHover.isHovered)
    }

    func testExitInstalledPointerCaptureSurvivesAndStopsOldRequest() async throws {
        let fixture = PublicScrollSettlementFixture()
        defer { fixture.retire() }
        fixture.runtime.pointerMoved(to: fixture.firstHoverPoint)
        _ = try fixture.beginIndicatorDrag()
        fixture.firstHover.onPointerExit = { [weak fixture] in
            guard let fixture else { return }
            fixture.probe.firstHoverExits += 1
            fixture.firstHover.onPointerExit = nil
            fixture.runtime.pointerDown(at: fixture.secondHoverPoint)
        }
        _ = try fixture.prepareQuery()

        XCTAssertFalse(fixture.scroll(to: 15))

        XCTAssertEqual(fixture.probe.firstHoverExits, 1)
        XCTAssertEqual(fixture.runtime.interactionPhase(for: fixture.secondHover), .pressed)
        XCTAssertEqual(fixture.container.scrollOffset, 0)
        fixture.runtime.pointerUp(at: fixture.secondHoverPoint)
        XCTAssertEqual(fixture.probe.secondPointerUpsInside, 1)
        XCTAssertEqual(fixture.probe.secondActivations, 1)
        XCTAssertEqual(fixture.container.scrollOffset, 0)
    }

    func testMixedPointerOwnershipRefusesWithoutCancellingOtherPress() async throws {
        let fixture = PublicScrollSettlementFixture()
        defer { fixture.retire() }
        _ = try fixture.beginIndicatorDrag()
        fixture.runtime.pointerDown(at: fixture.firstHoverPoint)
        XCTAssertEqual(fixture.runtime.interactionPhase(for: fixture.firstHover), .pressed)
        _ = try fixture.prepareQuery()

        XCTAssertFalse(fixture.scroll(to: 15))

        XCTAssertEqual(fixture.container.scrollOffset, 0)
        XCTAssertEqual(fixture.runtime.interactionPhase(for: fixture.firstHover), .pressed)
        XCTAssertEqual(fixture.probe.pointerUpsOutside, 0)
        fixture.runtime.pointerCancelled()
        XCTAssertEqual(fixture.probe.pointerUpsOutside, 1)
    }

    func testHoverExitDifferentScrollSupersedesOriginalIntent() async throws {
        try assertHoverSupersession(.different)
    }

    func testHoverExitEqualScrollSupersedesOriginalIntent() async throws {
        try assertHoverSupersession(.equal)
    }

    func testHoverExitAwayAndBackScrollSupersedesOriginalIntent() async throws {
        try assertHoverSupersession(.awayAndBack)
    }

    func testPrewritePhaseHistoryDestructionStopsOffsetAttempt() async throws {
        let fixture = PublicScrollSettlementFixture()
        defer { fixture.retire() }
        _ = try fixture.beginIndicatorDrag()
        _ = try fixture.prepareQuery()
        let probe = fixture.installPhaseHistory { fixture, probe in
            probe.offsetAtCleanup = fixture.container.scrollOffset
            probe.nestedResults.append(fixture.scroll(to: 0))
            probe.nestedOffsets.append(fixture.container.scrollOffset)
        }
        XCTAssertNotNil(probe.payload)
        _ = try fixture.requireQuerySettlement()

        XCTAssertFalse(fixture.scroll(to: 15, transaction: Transaction(animation: .linear(duration: 1))))

        XCTAssertEqual(probe.cleanups, 1, "Matching capture cancellation must reach its phase retirement")
        XCTAssertNil(probe.payload)
        XCTAssertEqual(probe.offsetAtCleanup, 0, "This retirement belongs before the outer offset write")
        XCTAssertEqual(probe.nestedResults, [true])
        XCTAssertEqual(probe.nestedOffsets, [0])
        XCTAssertEqual(fixture.container.scrollOffset, 0)
        XCTAssertEqual(fixture.container.scrollPresentedDelta, 0)
        fixture.clock.value += 2
        _ = fixture.runtime.tickAnimations(at: fixture.clock.value)
        XCTAssertEqual(fixture.container.scrollOffset, 0)
    }

    func testPostwriteHistoryDifferentScrollPreservesNewRequest() async throws {
        try assertPostwriteHistorySupersession(.different)
    }

    func testPostwriteHistoryEqualScrollPreventsStaleTweenTail() async throws {
        try assertPostwriteHistorySupersession(.equal)
    }

    func testPostwriteHistoryAwayAndBackScrollPreventsStaleTweenTail() async throws {
        try assertPostwriteHistorySupersession(.awayAndBack)
    }

    func testPostwriteHistoryEqualRequestSupersedesWithoutOtherMutation() async throws {
        let fixture = PublicScrollSettlementFixture()
        defer { fixture.retire() }
        let original = try fixture.prepareQuery()
        let probe = fixture.installPhaseHistory { fixture, probe in
            probe.offsetAtCleanup = fixture.container.scrollOffset
            XCTAssertTrue(fixture.runtime.hasPendingLayout)
            XCTAssertTrue(fixture.runtime.isLayoutSettlementReceiptCurrent(original))
            probe.nestedResults.append(fixture.scroll(to: 15))
            probe.nestedOffsets.append(fixture.container.scrollOffset)
            XCTAssertTrue(fixture.runtime.isLayoutSettlementReceiptCurrent(original))
        }
        XCTAssertNotNil(probe.payload)
        _ = try fixture.requireQuerySettlement()

        XCTAssertFalse(fixture.scroll(to: 15))

        XCTAssertEqual(probe.cleanups, 1)
        XCTAssertNil(probe.payload)
        XCTAssertEqual(probe.offsetAtCleanup, 600)
        XCTAssertEqual(probe.nestedResults, [true])
        XCTAssertEqual(probe.nestedOffsets, [600])
        XCTAssertEqual(fixture.container.scrollOffset, 600)
        XCTAssertEqual(fixture.container.scrollPresentedDelta, 0)
        XCTAssertFalse(fixture.runtime.hasActiveAnimations)
    }

    func testPostwriteHistoryPreservesNewAnimatedRequest() async throws {
        let fixture = PublicScrollSettlementFixture()
        defer { fixture.retire() }
        _ = try fixture.prepareQuery()
        let probe = fixture.installPhaseHistory { fixture, probe in
            probe.offsetAtCleanup = fixture.container.scrollOffset
            probe.nestedResults.append(
                fixture.scroll(to: 5, transaction: Transaction(animation: .linear(duration: 2))))
            probe.nestedOffsets.append(fixture.container.scrollOffset)
        }
        XCTAssertNotNil(probe.payload)
        _ = try fixture.requireQuerySettlement()

        XCTAssertFalse(fixture.scroll(to: 15, transaction: Transaction(animation: .linear(duration: 1))))

        XCTAssertEqual(probe.cleanups, 1)
        XCTAssertNil(probe.payload)
        XCTAssertEqual(probe.offsetAtCleanup, 600)
        XCTAssertEqual(probe.nestedResults, [true])
        XCTAssertEqual(probe.nestedOffsets, [200])
        XCTAssertEqual(fixture.container.scrollOffset, 200, accuracy: 0.0001)
        XCTAssertEqual(fixture.container.scrollPresentedDelta, -200, accuracy: 0.0001)
        XCTAssertTrue(fixture.runtime.hasActiveAnimations)
        fixture.clock.value += 1
        _ = fixture.runtime.tickAnimations(at: fixture.clock.value)
        _ = fixture.runtime.renderFrame(at: fixture.clock.value)
        XCTAssertEqual(fixture.container.resolvedScrollOffset, 100, accuracy: 0.0001)
        fixture.clock.value += 1
        _ = fixture.runtime.tickAnimations(at: fixture.clock.value)
        _ = fixture.runtime.renderFrame(at: fixture.clock.value)
        XCTAssertEqual(fixture.container.resolvedScrollOffset, 200, accuracy: 0.0001)
        XCTAssertEqual(fixture.container.scrollPresentedDelta, 0)
        XCTAssertFalse(fixture.runtime.hasActiveAnimations)
        XCTAssertEqual(probe.cleanups, 1)
    }

    func testQueryOnlyDeferredNestedTargetReceivesPreciseAlignment() async throws {
        let fixture = PublicScrollSettlementFixture(lazy: true)
        defer { fixture.retire() }
        let nested = try fixture.prepareDeferredNestedTarget()

        XCTAssertTrue(fixture.runtime.scrollToDescendant(nested, anchorY: 0, transaction: Transaction()))

        XCTAssertEqual(fixture.container.scrollOffset, 400)
        _ = fixture.runtime.renderFrame(at: fixture.clock.value)
        XCTAssertFalse(fixture.rows[10].isLayoutDeferredByVirtualization)
        XCTAssertEqual(fixture.rows[10].resolvedFrame.minY + nested.resolvedFrame.minY, 600)
        XCTAssertEqual(nested.resolvedFrame.size.height, 20)
        XCTAssertEqual(fixture.container.scrollOffset, 600)
    }

    func testPostwriteHistoryRawOffsetSupersessionPreventsStalePreciseAlignment() async throws {
        let fixture = PublicScrollSettlementFixture(lazy: true)
        defer { fixture.retire() }
        let nested = try fixture.prepareDeferredNestedTarget()
        let probe = fixture.installPhaseHistory { fixture, probe in
            probe.offsetAtCleanup = fixture.container.scrollOffset
            // The accepted lazy write has invalidated layout. An authored raw
            // offset is valid input here without borrowing a later settlement.
            fixture.container.scrollOffset = 450
            probe.nestedOffsets.append(fixture.container.scrollOffset)
        }
        XCTAssertNotNil(probe.payload)
        _ = try fixture.requireQuerySettlement()

        XCTAssertFalse(fixture.runtime.scrollToDescendant(nested, anchorY: 0, transaction: Transaction()))

        XCTAssertEqual(probe.cleanups, 1)
        XCTAssertNil(probe.payload)
        XCTAssertEqual(probe.offsetAtCleanup, 400)
        XCTAssertEqual(probe.nestedOffsets, [450])
        XCTAssertEqual(fixture.container.scrollOffset, 450)
        _ = fixture.runtime.renderFrame(at: fixture.clock.value)
        XCTAssertFalse(fixture.rows[10].isLayoutDeferredByVirtualization)
        XCTAssertEqual(fixture.rows[10].resolvedFrame.minY + nested.resolvedFrame.minY, 600)
        XCTAssertEqual(nested.resolvedFrame.size.height, 20)
        XCTAssertEqual(fixture.container.scrollOffset, 450, "The superseded request must not queue its old alignment")
        XCTAssertEqual(probe.cleanups, 1)
    }

    func testNoPendingPublicScrollKeepsExistingBehavior() async throws {
        let fixture = PublicScrollSettlementFixture()
        defer { fixture.retire() }
        XCTAssertFalse(fixture.runtime.hasPendingLayout)
        fixture.container.isScrollInputEnabled = false
        XCTAssertFalse(fixture.runtime.hasPendingLayout)

        XCTAssertTrue(fixture.scroll(to: 8))

        XCTAssertEqual(fixture.container.scrollOffset, 320, accuracy: 0.0001)
    }

    private func assertUnsettled(
        _ runtime: RetainedViewRuntime, file: StaticString = #filePath, line: UInt = #line
    ) {
        guard case .unsettled = runtime.layoutSettlementStatus else {
            return XCTFail("An unqueried mutation must remain unsettled", file: file, line: line)
        }
    }

    private func assertClockSupersession(
        _ mode: PublicScrollSupersession, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let fixture = PublicScrollSettlementFixture()
        defer { fixture.retire() }
        let original = try fixture.prepareQuery(file: file, line: line)
        fixture.runtime.clock = { [weak fixture] in
            guard let fixture else { return 10 }
            fixture.probe.clockCalls += 1
            fixture.restoreClock()
            XCTAssertTrue(fixture.runtime.isLayoutSettlementReceiptCurrent(original), file: file, line: line)
            fixture.performSupersession(mode, originalIndex: 0, probe: fixture.probe)
            XCTAssertTrue(
                fixture.runtime.isLayoutSettlementReceiptCurrent(original),
                "This eager, paint-only case must isolate scroll intent from layout invalidation",
                file: file, line: line)
            return fixture.clock.value
        }
        _ = try fixture.requireQuerySettlement(file: file, line: line)

        XCTAssertFalse(fixture.scroll(to: 15), file: file, line: line)

        XCTAssertEqual(fixture.probe.clockCalls, 1, file: file, line: line)
        assertSupersession(mode, originalIndex: 0, fixture: fixture, probe: fixture.probe, file: file, line: line)
    }

    private func assertHoverSupersession(
        _ mode: PublicScrollSupersession, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let fixture = PublicScrollSettlementFixture()
        defer { fixture.retire() }
        fixture.runtime.pointerMoved(to: fixture.firstHoverPoint)
        _ = try fixture.beginIndicatorDrag(file: file, line: line)
        let original = try fixture.prepareQuery(file: file, line: line)
        fixture.firstHover.onPointerExit = { [weak fixture] in
            guard let fixture else { return }
            fixture.probe.firstHoverExits += 1
            XCTAssertTrue(fixture.runtime.isLayoutSettlementReceiptCurrent(original), file: file, line: line)
            fixture.performSupersession(mode, originalIndex: 0, probe: fixture.probe)
            XCTAssertTrue(
                fixture.runtime.isLayoutSettlementReceiptCurrent(original),
                "Nested eager requests must revoke intent even when layout remains settled", file: file, line: line)
        }
        _ = try fixture.requireQuerySettlement(file: file, line: line)

        XCTAssertFalse(fixture.scroll(to: 15), file: file, line: line)

        XCTAssertEqual(fixture.probe.firstHoverExits, 1, file: file, line: line)
        assertSupersession(mode, originalIndex: 0, fixture: fixture, probe: fixture.probe, file: file, line: line)
    }

    private func assertPostwriteHistorySupersession(
        _ mode: PublicScrollSupersession, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let fixture = PublicScrollSettlementFixture()
        defer { fixture.retire() }
        let original = try fixture.prepareQuery(file: file, line: line)
        let probe = fixture.installPhaseHistory { fixture, probe in
            probe.offsetAtCleanup = fixture.container.scrollOffset
            XCTAssertTrue(
                fixture.runtime.isLayoutSettlementReceiptCurrent(original),
                "The eager write and phase bookkeeping must not create a new layout receipt", file: file, line: line)
            fixture.performSupersession(mode, originalIndex: 15, probe: probe)
        }
        XCTAssertNotNil(probe.payload, file: file, line: line)
        _ = try fixture.requireQuerySettlement(file: file, line: line)

        XCTAssertFalse(
            fixture.scroll(to: 15, transaction: Transaction(animation: .linear(duration: 1))), file: file, line: line)

        XCTAssertEqual(probe.cleanups, 1, file: file, line: line)
        XCTAssertNil(probe.payload, file: file, line: line)
        XCTAssertEqual(
            probe.offsetAtCleanup, 600, "The outer offset must be accepted before this retirement",
            file: file, line: line)
        assertSupersession(mode, originalIndex: 15, fixture: fixture, probe: probe, file: file, line: line)
        XCTAssertEqual(fixture.container.scrollPresentedDelta, 0, file: file, line: line)
        let acceptedOffset = fixture.container.scrollOffset
        fixture.clock.value += 2
        _ = fixture.runtime.tickAnimations(at: fixture.clock.value)
        _ = fixture.runtime.renderFrame(at: fixture.clock.value)
        XCTAssertEqual(fixture.container.scrollOffset, acceptedOffset, file: file, line: line)
        XCTAssertEqual(fixture.container.scrollPresentedDelta, 0, file: file, line: line)
        XCTAssertFalse(fixture.runtime.hasActiveAnimations, file: file, line: line)
        XCTAssertEqual(probe.cleanups, 1, file: file, line: line)
    }

    private func assertSupersession(
        _ mode: PublicScrollSupersession, originalIndex: Int, fixture: PublicScrollSettlementFixture,
        probe: PublicScrollSettlementProbe, file: StaticString = #filePath, line: UInt = #line
    ) {
        let offsets: [Double]
        switch mode {
        case .different: offsets = [200]
        case .equal: offsets = [Double(originalIndex) * 40]
        case .awayAndBack: offsets = [200, Double(originalIndex) * 40]
        }
        XCTAssertEqual(probe.nestedResults, Array(repeating: true, count: offsets.count), file: file, line: line)
        XCTAssertEqual(probe.nestedOffsets, offsets, file: file, line: line)
        XCTAssertEqual(fixture.container.scrollOffset, offsets.last!, file: file, line: line)
    }

    @inline(never)
    private func installReplacingClock(on fixture: PublicScrollSettlementFixture) -> PublicScrollSettlementProbe {
        let probe = PublicScrollSettlementProbe()
        let payload = PublicScrollRetirementPayload { [weak fixture, weak probe] in
            guard let fixture, let probe else { return XCTFail("The clock fixture must survive capture retirement") }
            probe.cleanups += 1
            probe.offsetAtCleanup = fixture.container.scrollOffset
            fixture.container.frame.size.height += 1
        }
        probe.payload = payload
        fixture.runtime.clock = { [weak fixture, weak probe, payload] in
            guard let fixture else { return 10 }
            probe?.clockCalls += 1
            fixture.restoreClock()
            withExtendedLifetime(payload) {}
            return fixture.clock.value
        }
        return probe
    }
}

private enum PublicScrollSupersession {
    case different
    case equal
    case awayAndBack
}

@MainActor
private final class PublicScrollSettlementFixture {
    let root: ViewNode
    let wrapper: ViewNode
    let container: ViewNode
    let rows: [ViewNode]
    let firstHover: ViewNode
    let secondHover: ViewNode
    let runtime: RetainedViewRuntime
    let axis: ScrollAxis
    let clock = PublicScrollSettlementClock()
    let probe = PublicScrollSettlementProbe()
    let firstHoverPoint = Point(x: 280, y: 20)
    let secondHoverPoint = Point(x: 340, y: 20)

    init(axis: ScrollAxis = .vertical, lazy: Bool = false, chrome: Bool = false) {
        self.axis = axis
        rows = (0..<20).map { _ in
            ViewNode(
                preferredSize: axis == .vertical ? Size(width: 220, height: 40) : Size(width: 40, height: 100),
                isHitTestVisible: false)
        }
        let layout = axis == .vertical ? StackLayout.vertical(spacing: 0) : StackLayout.horizontal(spacing: 0)
        container = ViewNode(
            frame: Rect(x: 0, y: 0, width: axis == .vertical ? 240 : 120, height: 120), clipsToBounds: true,
            layoutMode: lazy ? .lazyStack(layout) : .stack(layout), scrollAxis: axis,
            showsScrollIndicator: true, children: rows)
        container.scrollIndicatorAutoHides = false
        wrapper = ViewNode(
            frame: Rect(x: 0, y: 0, width: 240, height: 160), isHitTestVisible: false, children: [container])
        firstHover = ViewNode(frame: Rect(x: 260, y: 0, width: 40, height: 40), backgroundColor: .white)
        secondHover = ViewNode(frame: Rect(x: 320, y: 0, width: 40, height: 40), backgroundColor: .white)
        root = ViewNode(
            frame: Rect(x: 0, y: 0, width: 420, height: 180), isHitTestVisible: false,
            children: [wrapper, firstHover, secondHover])
        runtime = RetainedViewRuntime(root: root)
        restoreClock()
        firstHover.onActivate = {}
        firstHover.onPointerEnter = {}
        firstHover.onPointerExit = { [weak probe] in probe?.firstHoverExits += 1 }
        firstHover.onPointerUpOutside = { [weak probe] in probe?.pointerUpsOutside += 1 }
        secondHover.onActivate = { [weak probe] in probe?.secondActivations += 1 }
        secondHover.onPointerUpInside = { [weak probe] in probe?.secondPointerUpsInside += 1 }
        secondHover.onPointerEnter = { [weak probe] in probe?.secondHoverEnters += 1 }
        secondHover.onPointerExit = { [weak probe] in probe?.secondHoverExits += 1 }
        if chrome {
            firstHover.interactionSurface = RetainedInteractionSurface(
                idleBackground: .white, hoveredBackground: Color(red: 0, green: 0, blue: 1, alpha: 1),
                hoverDuration: 0.2)
        }
        _ = runtime.renderFrame(at: clock.value)
        XCTAssertFalse(runtime.hasPendingLayout)
        if lazy { XCTAssertTrue(rows[15].isLayoutDeferredByVirtualization) }
    }

    func restoreClock() {
        runtime.clock = { [clock] in clock.value }
    }

    func scroll(to index: Int, transaction: Transaction = Transaction()) -> Bool {
        runtime.scrollToDescendant(
            rows[index], anchorX: axis == .horizontal ? 0 : nil, anchorY: axis == .vertical ? 0 : nil,
            transaction: transaction)
    }

    func prepareQuery(file: StaticString = #filePath, line: UInt = #line) throws -> RetainedLayoutSettlementReceipt {
        if axis == .vertical {
            container.frame.size.height += 1
        } else {
            container.frame.size.width += 1
        }
        return try settlePendingQuery(file: file, line: line)
    }

    func settlePendingQuery(
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> RetainedLayoutSettlementReceipt {
        XCTAssertTrue(runtime.hasPendingLayout, file: file, line: line)
        XCTAssertNotNil(runtime.resolvedLayoutFrame(of: root), file: file, line: line)
        return try requireQuerySettlement(file: file, line: line)
    }

    func requireQuerySettlement(
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> RetainedLayoutSettlementReceipt {
        XCTAssertTrue(runtime.hasPendingLayout, "This test must enter the public prepared path", file: file, line: line)
        XCTAssertTrue(runtime.isDirty, file: file, line: line)
        XCTAssertFalse(runtime.isLayoutInProgress, file: file, line: line)
        XCTAssertNotNil(container.cachedLayoutKey, file: file, line: line)
        XCTAssertNil(container.pendingLayoutKey, file: file, line: line)
        guard case .settled(let receipt) = runtime.layoutSettlementStatus else {
            return try XCTUnwrap(
                nil as RetainedLayoutSettlementReceipt?, "The actual query must settle before the public call",
                file: file, line: line)
        }
        XCTAssertTrue(runtime.isLayoutSettlementReceiptCurrent(receipt), file: file, line: line)
        return receipt
    }

    func prepareDeferredNestedTarget(file: StaticString = #filePath, line: UInt = #line) throws -> ViewNode {
        let nested = ViewNode(
            frame: Rect(x: 0, y: 200, width: 80, height: 20), preferredSize: Size(width: 80, height: 20))
        rows[10].preferredSize = Size(width: 220, height: 300)
        rows[10].addChild(nested)
        _ = try prepareQuery(file: file, line: line)
        XCTAssertTrue(rows[10].isLayoutDeferredByVirtualization, file: file, line: line)
        XCTAssertEqual(rows[10].resolvedFrame.minY, 400, file: file, line: line)
        XCTAssertEqual(container.scrollOffset, 0, file: file, line: line)
        return nested
    }

    func beginIndicatorDrag(file: StaticString = #filePath, line: UInt = #line) throws -> Point {
        let track = try XCTUnwrap(
            runtime.currentPrepaintState.deferredDraws.compactMap { draw -> ScrollIndicatorTrack? in
                guard case .scrollIndicator(let payload) = draw.payload, payload.node === container else { return nil }
                return payload.track
            }.first, file: file, line: line)
        let point = Point(x: track.indicatorRect.midX, y: track.indicatorRect.midY)
        runtime.pointerDown(at: point)
        return point
    }

    func performSupersession(
        _ mode: PublicScrollSupersession, originalIndex: Int, probe: PublicScrollSettlementProbe
    ) {
        let indices: [Int]
        switch mode {
        case .different: indices = [5]
        case .equal: indices = [originalIndex]
        case .awayAndBack: indices = [5, originalIndex]
        }
        for index in indices {
            probe.nestedResults.append(scroll(to: index))
            probe.nestedOffsets.append(container.scrollOffset)
        }
    }

    @inline(never)
    func installPhaseHistory(
        onRelease: @escaping @MainActor (PublicScrollSettlementFixture, PublicScrollSettlementProbe) -> Void
    ) -> PublicScrollSettlementProbe {
        let probe = PublicScrollSettlementProbe()
        container.observeScrollGeometry(
            of: { _ in PublicScrollObservedValue(marker: 0, payload: nil) }, action: { _, _ in })
        container.observeScrollPhase { _, _, _ in }
        let payload = PublicScrollRetirementPayload { [weak self, weak probe] in
            guard let self, let probe else { return XCTFail("The phase fixture must survive history retirement") }
            probe.cleanups += 1
            onRelease(self, probe)
        }
        probe.payload = payload
        // No paint follows this registration. First phase bookkeeping selects
        // the actual source and retires this old opaque geometry-history value.
        container.scrollObserverStorage?.geometry.first?.previousValue =
            PublicScrollObservedValue(marker: 1, payload: payload)
        return probe
    }

    func retire() {
        runtime.stopRenderLifecycleCallbacks()
        restoreClock()
        for node in rows + [firstHover, secondHover] {
            node.onPointerEnter = nil
            node.onPointerExit = nil
            node.onPointerUpOutside = nil
            node.onPointerUpInside = nil
            node.onActivate = nil
        }
        container.scrollObserverStorage = nil
        runtime.pointerCancelled()
    }
}

@MainActor
private final class PublicScrollSettlementClock {
    var value = 10.0
}

@MainActor
private final class PublicScrollSettlementProbe {
    weak var payload: PublicScrollRetirementPayload?
    var clockCalls = 0
    var layoutQueries = 0
    var renders = 0
    var cleanups = 0
    var reinsertions = 0
    var axisReplacements = 0
    var firstHoverExits = 0
    var secondHoverEnters = 0
    var secondHoverExits = 0
    var secondActivations = 0
    var secondPointerUpsInside = 0
    var pointerUpsOutside = 0
    var offsetAtCleanup: Double?
    var nestedResults: [Bool] = []
    var nestedOffsets: [Double] = []
}

@MainActor
private final class PublicScrollRetirementPayload {
    private let onRelease: @MainActor () -> Void

    init(onRelease: @escaping @MainActor () -> Void) {
        self.onRelease = onRelease
    }

    isolated deinit { onRelease() }
}

private struct PublicScrollObservedValue: Equatable {
    var marker: Int
    var payload: PublicScrollRetirementPayload?

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.marker == rhs.marker }
}
