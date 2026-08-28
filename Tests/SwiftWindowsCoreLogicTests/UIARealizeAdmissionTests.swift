import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Source-level Realize admission over retained lazy rows and real prepaint
/// indicator tracks. These fixtures do not create an HWND or call native UIA.
@MainActor
final class UIARealizeAdmissionTests: XCTestCase {
    func testOffscreenRowIsRealizedOnceAndAnAlreadyVisibleRowIsNotRetried() async throws {
        for inputEnabled in [true, false] {
            let fixture = UIARealizeAdmissionFixture()
            defer { fixture.retire() }
            fixture.scroll.isScrollInputEnabled = inputEnabled
            fixture.settle()
            let id = try fixture.id(for: fixture.target)
            XCTAssertTrue(fixture.target.isLayoutDeferredByVirtualization)
            XCTAssertTrue(try fixture.snapshot(for: fixture.target).isVirtualizedPlaceholder)
            fixture.countClockCalls()

            XCTAssertTrue(fixture.source.uiaRealizeVirtualizedItem(elementID: id), "input enabled: \(inputEnabled)")
            XCTAssertEqual(fixture.probe.clockCalls, 1)
            XCTAssertEqual(fixture.scroll.scrollOffset, fixture.revealedOffset, accuracy: 0.0001)
            fixture.settle()
            XCTAssertFalse(fixture.target.isLayoutDeferredByVirtualization)
            XCTAssertFalse(try fixture.snapshot(for: fixture.target).isVirtualizedPlaceholder)
            XCTAssertFalse(fixture.source.uiaRealizeVirtualizedItem(elementID: id))
            XCTAssertEqual(fixture.probe.clockCalls, 1, "A visible row must reject before another clock sample")
            XCTAssertEqual(fixture.scroll.scrollOffset, fixture.revealedOffset, accuracy: 0.0001)
        }
    }

    func testPublicProgrammaticScrollStillWorksFromLayoutWithInputDisabled() async throws {
        let fixture = UIARealizeAdmissionFixture()
        defer { fixture.retire() }
        fixture.scroll.isScrollInputEnabled = false
        fixture.settle()
        var results: [Bool] = []
        fixture.runtime.scheduleAfterLayout(key: "public-scroll-with-input-disabled") { [weak fixture] in
            guard let fixture else { return }
            results.append(fixture.runtime.scrollToDescendant(fixture.target))
        }

        fixture.settle()
        XCTAssertEqual(results, [true])
        XCTAssertFalse(fixture.scroll.isScrollInputEnabled)
        XCTAssertEqual(fixture.scroll.scrollOffset, fixture.revealedOffset, accuracy: 0.0001)
    }

    func testStoppedRuntimeDoesNotStartQueuedLayoutOrSampleTheClock() async throws {
        let fixture = UIARealizeAdmissionFixture()
        defer { fixture.retire() }
        let id = try fixture.id(for: fixture.target)
        var layoutCalls = 0
        fixture.runtime.scheduleAfterLayout(key: "must-not-query-stopped-realize") { layoutCalls += 1 }
        fixture.countClockCalls()
        fixture.runtime.stopRenderLifecycleCallbacks()

        XCTAssertFalse(fixture.source.uiaRealizeVirtualizedItem(elementID: id))
        XCTAssertEqual(layoutCalls, 0)
        XCTAssertEqual(fixture.probe.clockCalls, 0)
        XCTAssertEqual(fixture.scroll.scrollOffset, 0)
    }

    func testInitialQueryAndClockChangesCannotAuthorizeTheOriginalRow() async throws {
        for boundary in UIARealizeCallbackBoundary.allCases {
            for mutation in UIARealizeCallbackMutation.allCases {
                let fixture = UIARealizeAdmissionFixture()
                defer { fixture.retire() }
                let id = try fixture.id(for: fixture.target)
                var mutationCalls = 0
                switch boundary {
                case .query:
                    fixture.countClockCalls()
                    fixture.runtime.scheduleAfterLayout(key: "change-realize-target-in-query") { [weak fixture] in
                        mutationCalls += 1
                        fixture?.mutate(mutation)
                    }
                case .clock:
                    fixture.runtime.clock = { [weak fixture] in
                        guard let fixture else { return 100 }
                        fixture.probe.clockCalls += 1
                        if mutationCalls == 0 {
                            mutationCalls += 1
                            fixture.mutate(mutation)
                        }
                        return 100
                    }
                }

                XCTAssertFalse(fixture.source.uiaRealizeVirtualizedItem(elementID: id), "\(boundary), \(mutation)")
                XCTAssertEqual(mutationCalls, 1, "\(boundary), \(mutation)")
                XCTAssertEqual(fixture.probe.clockCalls, boundary == .query ? 0 : 1, "\(boundary), \(mutation)")
                XCTAssertEqual(fixture.scroll.scrollOffset, 0, "\(boundary), \(mutation)")
                XCTAssertEqual(fixture.alternateScroll.scrollOffset, 0, "\(boundary), \(mutation)")
                XCTAssertEqual(fixture.probe.activations, 0)
                XCTAssertEqual(fixture.probe.focusEntries, 0)
            }
        }
    }

    func testBuildAndLayoutCallbackEntryLeaveWorkForAnIndependentRequest() async throws {
        for duringLayoutCallback in [false, true] {
            let fixture = UIARealizeAdmissionFixture()
            defer { fixture.retire() }
            let id = try fixture.id(for: fixture.target)
            var laterCalls = 0
            var nestedResults: [Bool] = []
            fixture.countClockCalls()
            if duringLayoutCallback {
                fixture.runtime.scheduleAfterLayout(key: "realize-from-layout-callback") { [weak fixture] in
                    guard let fixture else { return }
                    fixture.runtime.scheduleAfterLayout(key: "later-realize-layout-work") { laterCalls += 1 }
                    nestedResults.append(fixture.source.uiaRealizeVirtualizedItem(elementID: id))
                }
                fixture.settle()
                XCTAssertEqual(nestedResults, [false])
            } else {
                XCTAssertNotNil(fixture.runtime.retainedBuildCoordinator.beginBuild())
                fixture.runtime.scheduleAfterLayout(key: "later-realize-build-work") { laterCalls += 1 }
                XCTAssertFalse(fixture.source.uiaRealizeVirtualizedItem(elementID: id))
                fixture.runtime.retainedBuildCoordinator.finishBuild()
            }
            XCTAssertEqual(laterCalls, 0, "during layout callback: \(duringLayoutCallback)")
            XCTAssertEqual(fixture.probe.clockCalls, 0)
            XCTAssertEqual(fixture.scroll.scrollOffset, 0)

            XCTAssertTrue(fixture.source.uiaRealizeVirtualizedItem(elementID: id))
            XCTAssertEqual(laterCalls, 1)
            XCTAssertEqual(fixture.probe.clockCalls, 1)
            XCTAssertEqual(fixture.scroll.scrollOffset, fixture.revealedOffset, accuracy: 0.0001)
        }
    }

    func testClockCannotReenterAnyMutationThroughTheSameOrAnotherSource() async throws {
        let fixture = UIARealizeAdmissionFixture()
        defer { fixture.retire() }
        let otherSource = RuntimeUIAElementTreeSource(runtime: fixture.runtime)
        let origins = try [fixture.source, otherSource].map { (source: RuntimeUIAElementTreeSource) in
            (
                source: source,
                row: try fixture.id(for: fixture.target, using: source),
                action: try fixture.id(for: fixture.gesture, using: source),
                edit: try fixture.id(for: fixture.editor, using: source)
            )
        }
        var attempted = false
        var nestedResults: [Bool] = []
        fixture.runtime.clock = { [weak fixture] in
            guard let fixture else { return 100 }
            fixture.probe.clockCalls += 1
            // Keep a missing production guard from recursing without a bound.
            if !attempted {
                attempted = true
                for origin in origins {
                    nestedResults.append(origin.source.uiaInvokeDefaultAction(elementID: origin.action))
                    nestedResults.append(origin.source.uiaSetFocusResult(elementID: origin.edit))
                    nestedResults.append(origin.source.uiaSetValue(elementID: origin.edit, value: "nested"))
                    nestedResults.append(origin.source.uiaRealizeVirtualizedItem(elementID: origin.row))
                }
            }
            return 100
        }

        XCTAssertTrue(fixture.source.uiaRealizeVirtualizedItem(elementID: origins[0].row))
        XCTAssertEqual(nestedResults, Array(repeating: false, count: 8))
        XCTAssertEqual(fixture.probe.clockCalls, 1)
        XCTAssertEqual(fixture.probe.activations, 0)
        XCTAssertEqual(fixture.probe.focusEntries, 0)
        XCTAssertEqual(fixture.probe.keys, 0)
        XCTAssertEqual(fixture.probe.commits, 0)
        XCTAssertEqual(fixture.editor.accessibilityValue, "original")

        fixture.runtime.clock = { 100 }
        XCTAssertTrue(otherSource.uiaInvokeDefaultAction(elementID: origins[1].action))
        XCTAssertEqual(fixture.probe.activations, 1)
        XCTAssertTrue(otherSource.uiaSetFocusResult(elementID: origins[1].edit))
        XCTAssertEqual(fixture.probe.focusEntries, 1)
        fixture.scroll.scrollOffset = 0
        fixture.settle()
        XCTAssertTrue(otherSource.uiaRealizeVirtualizedItem(elementID: origins[1].row))
    }

    func testRejectedClockMutationDoesNotKeepAdmissionClosed() async throws {
        let fixture = UIARealizeAdmissionFixture()
        defer { fixture.retire() }
        let id = try fixture.id(for: fixture.target)
        fixture.runtime.clock = { [weak fixture] in
            fixture?.target.accessibilityRespondsToUserInteraction = false
            return 100
        }
        XCTAssertFalse(fixture.source.uiaRealizeVirtualizedItem(elementID: id))
        XCTAssertEqual(fixture.scroll.scrollOffset, 0)

        fixture.runtime.clock = { 100 }
        fixture.target.accessibilityRespondsToUserInteraction = true
        fixture.settle()
        XCTAssertTrue(fixture.source.uiaRealizeVirtualizedItem(elementID: id))
        XCTAssertEqual(fixture.scroll.scrollOffset, fixture.revealedOffset, accuracy: 0.0001)
    }

    func testSoleIndicatorCancellationDeliversHoverExitAndUsesOnlyTheSampledClock() async throws {
        let fixture = UIARealizeAdmissionFixture()
        defer { fixture.retire() }
        let id = try fixture.id(for: fixture.target)
        fixture.runtime.pointerMoved(to: fixture.gesturePoint)
        XCTAssertTrue(fixture.gesture.isHovered)
        let grabPoint = try fixture.beginIndicatorDrag()
        XCTAssertTrue(
            fixture.gesture.isHovered, "The direct indicator press must preserve the old hover for cancellation")
        fixture.countClockCalls()

        XCTAssertTrue(fixture.source.uiaRealizeVirtualizedItem(elementID: id))
        XCTAssertEqual(fixture.probe.clockCalls, 1)
        XCTAssertEqual(fixture.probe.hoverExits, 1)
        XCTAssertFalse(fixture.gesture.isHovered)
        XCTAssertEqual(fixture.scroll.scrollOffset, fixture.revealedOffset, accuracy: 0.0001)

        fixture.runtime.clock = { 100 }
        fixture.runtime.pointerMoved(to: Point(x: grabPoint.x, y: grabPoint.y + 35))
        XCTAssertEqual(
            fixture.scroll.scrollOffset, fixture.revealedOffset, accuracy: 0.0001, "UIA must retire the thumb drag")
        fixture.settle()
        XCTAssertFalse(fixture.target.isLayoutDeferredByVirtualization)
    }

    func testHoverExitRevocationStopsBeforeAnotherClockOffsetOrLayoutEffect() async throws {
        for mutation in UIARealizeHoverExitMutation.allCases {
            let fixture = UIARealizeAdmissionFixture()
            defer { fixture.retire() }
            let id = try fixture.id(for: fixture.target)
            fixture.runtime.pointerMoved(to: fixture.gesturePoint)
            _ = try fixture.beginIndicatorDrag()
            let hoveredColor = fixture.gesture.backgroundColor
            fixture.gesture.onPointerExit = { [weak fixture] in
                guard let fixture else { return }
                fixture.probe.hoverExits += 1
                switch mutation {
                case .terminal:
                    fixture.runtime.stopRenderLifecycleCallbacks()
                case .detached:
                    fixture.target.removeFromParent()
                case .queuedLayout:
                    fixture.runtime.scheduleAfterLayout(key: "after-rejected-hover-exit") {
                        [weak probe = fixture.probe] in
                        probe?.laterCalls += 1
                    }
                }
            }
            fixture.countClockCalls()

            XCTAssertFalse(fixture.source.uiaRealizeVirtualizedItem(elementID: id), "\(mutation)")
            XCTAssertEqual(fixture.probe.hoverExits, 1, "\(mutation)")
            XCTAssertEqual(fixture.probe.clockCalls, 1, "\(mutation)")
            XCTAssertEqual(fixture.probe.laterCalls, 0, "\(mutation)")
            XCTAssertEqual(fixture.scroll.scrollOffset, 0, "\(mutation)")
            XCTAssertEqual(
                fixture.gesture.backgroundColor, hoveredColor, "Rejected exit must not continue into old chrome")
            XCTAssertFalse(fixture.gesture.isHovered, "Cancellation already published its owned pointer state")
            if mutation != .terminal {
                fixture.runtime.clock = { 100 }
                fixture.settle()
                XCTAssertEqual(fixture.probe.laterCalls, mutation == .queuedLayout ? 1 : 0)
                XCTAssertEqual(fixture.scroll.scrollOffset, 0, "Independent layout must not replay rejected Realize")
            }
        }
    }

    func testPublicMixedPointerOwnershipRejectsBeforeTakingOverGestureCleanup() async throws {
        for gesture in UIARealizeMixedGesture.allCases {
            let fixture = UIARealizeAdmissionFixture()
            defer { fixture.retire() }
            let id = try fixture.id(for: fixture.target)
            switch gesture {
            case .drag:
                fixture.gesture.onDragStart = { [probe = fixture.probe] _ in probe.dragStarts += 1 }
                fixture.gesture.onDragEnd = { [probe = fixture.probe] _, _ in probe.dragEnds += 1 }
                fixture.runtime.pointerDown(at: fixture.gesturePoint)
                _ = try fixture.beginIndicatorDrag()
                XCTAssertEqual(fixture.probe.dragStarts, 1)
            case .press:
                _ = try fixture.beginIndicatorDrag()
                fixture.runtime.pointerDown(at: fixture.gesturePoint)
                XCTAssertEqual(fixture.runtime.interactionPhase(for: fixture.gesture), .pressed)
            case .longPress:
                fixture.gesture.longPressGesture = RetainedLongPressGesture(
                    minimumDuration: 1,
                    onBegin: { [probe = fixture.probe] _ in
                        probe.longPressBegins += 1
                        return { probe.longPressCleanups += 1 }
                    },
                    onPressingChanged: { [probe = fixture.probe] in probe.pressing.append($0) },
                    onRecognized: { [probe = fixture.probe] in probe.longPressCompletions += 1 })
                _ = try fixture.beginIndicatorDrag()
                fixture.runtime.pointerDown(at: fixture.gesturePoint)
                XCTAssertEqual(fixture.probe.pressing, [true])
                XCTAssertEqual(fixture.probe.longPressBegins, 1)
            }
            fixture.countClockCalls()

            XCTAssertFalse(fixture.source.uiaRealizeVirtualizedItem(elementID: id), "\(gesture)")
            XCTAssertEqual(fixture.probe.clockCalls, 0, "Mixed ownership must reject before clock/cancellation effects")
            XCTAssertEqual(fixture.scroll.scrollOffset, 0)
            XCTAssertEqual(fixture.probe.dragEnds, 0)
            XCTAssertEqual(fixture.probe.pointerUpsOutside, 0)
            XCTAssertEqual(fixture.probe.longPressCleanups, 0)
            if gesture == .longPress { XCTAssertEqual(fixture.probe.pressing, [true]) }
            if gesture != .drag {
                XCTAssertEqual(fixture.runtime.interactionPhase(for: fixture.gesture), .pressed)
            }

            fixture.runtime.clock = { 100 }
            fixture.runtime.pointerCancelled()
            XCTAssertEqual(fixture.probe.dragEnds, gesture == .drag ? 1 : 0)
            XCTAssertEqual(fixture.probe.pointerUpsOutside, gesture == .drag ? 0 : 1)
            XCTAssertEqual(fixture.probe.longPressCleanups, gesture == .longPress ? 1 : 0)
            XCTAssertEqual(fixture.probe.longPressCompletions, 0)
            if gesture == .longPress { XCTAssertEqual(fixture.probe.pressing, [true, false]) }
            fixture.runtime.pointerCancelled()
            XCTAssertEqual(fixture.probe.dragEnds, gesture == .drag ? 1 : 0)
            XCTAssertEqual(fixture.probe.pointerUpsOutside, gesture == .drag ? 0 : 1)
            XCTAssertEqual(fixture.probe.longPressCleanups, gesture == .longPress ? 1 : 0)
        }
    }

    func testClockCaptureCleanupRevokesBeforeOffsetOrAnotherClock() async throws {
        for detachesTarget in [false, true] {
            let fixture = UIARealizeAdmissionFixture()
            defer { fixture.retire() }
            let id = try fixture.id(for: fixture.target)
            let probe = installSelfReplacingClock(fixture, detachesTarget: detachesTarget)
            XCTAssertNotNil(probe.payload)

            XCTAssertFalse(fixture.source.uiaRealizeVirtualizedItem(elementID: id))
            XCTAssertEqual(probe.calls, 1)
            XCTAssertEqual(probe.cleanups, 1)
            XCTAssertNil(probe.payload)
            XCTAssertEqual(probe.laterClockCalls, 0)
            XCTAssertEqual(fixture.scroll.scrollOffset, 0)
            if detachesTarget {
                XCTAssertNil(fixture.target.parent)
            } else {
                XCTAssertFalse(fixture.runtime.permitsRetainedActionInvocation)
            }
        }
    }

    func testHoverExitCaptureCleanupFinishesBeforeScrollContinuation() async throws {
        let fixture = UIARealizeAdmissionFixture()
        defer { fixture.retire() }
        let id = try fixture.id(for: fixture.target)
        fixture.runtime.pointerMoved(to: fixture.gesturePoint)
        _ = try fixture.beginIndicatorDrag()
        let probe = installSelfRemovingHoverExit(fixture)
        fixture.countClockCalls()
        XCTAssertNotNil(probe.payload)

        XCTAssertFalse(fixture.source.uiaRealizeVirtualizedItem(elementID: id))
        XCTAssertEqual(probe.calls, 1)
        XCTAssertEqual(probe.cleanups, 1)
        XCTAssertNil(probe.payload)
        XCTAssertEqual(fixture.probe.clockCalls, 1)
        XCTAssertEqual(fixture.scroll.scrollOffset, 0)
        XCTAssertFalse(fixture.runtime.permitsRetainedActionInvocation)
    }

    func testRetiredGeometryHistoryCannotApproveItsCleanupOffsetOrQueueARealizeRetry() async throws {
        for observesOtherScroll in [false, true] {
            let fixture = UIARealizeAdmissionFixture()
            defer { fixture.retire() }
            let id = try fixture.id(for: fixture.target)
            let owner = observesOtherScroll ? fixture.alternateScroll : fixture.root
            let observedScroll = observesOtherScroll ? fixture.alternateScroll : fixture.scroll
            let probe = installGeometryHistoryPayload(fixture, owner: owner)
            _ = fixture.runtime.renderScene()
            XCTAssertNotNil(probe.payload)
            XCTAssertEqual(probe.samples, 1)
            XCTAssertEqual(probe.geometryActions, 1)
            XCTAssertTrue(owner.scrollObserverStorage?.source === observedScroll)

            // The wrapper retains its prior Any until source selection notices
            // the new epoch. No render may consume it before the UIA request.
            observedScroll.scrollAxis = nil
            observedScroll.scrollAxis = .vertical
            XCTAssertNotNil(probe.payload)
            XCTAssertEqual(probe.cleanups, 0)
            fixture.countClockCalls()

            XCTAssertFalse(
                fixture.source.uiaRealizeVirtualizedItem(elementID: id), "other source: \(observesOtherScroll)")
            XCTAssertEqual(fixture.probe.clockCalls, 1)
            XCTAssertEqual(probe.samples, 1, "Admission must not deliver the scroll observer")
            XCTAssertEqual(probe.geometryActions, 1)
            XCTAssertEqual(probe.cleanups, 1)
            XCTAssertNil(probe.payload, "The pin must be released before the source result returns")
            XCTAssertEqual(probe.offsetsAtCleanup.count, 1)
            XCTAssertEqual(try XCTUnwrap(probe.offsetsAtCleanup.first), fixture.revealedOffset, accuracy: 0.0001)
            XCTAssertEqual(fixture.scroll.scrollOffset, 0, "Cleanup's replacement offset is an effect, not UIA success")
            XCTAssertEqual(probe.laterCalls, 0)

            fixture.runtime.clock = { 100 }
            fixture.settle()
            XCTAssertEqual(probe.laterCalls, 1)
            XCTAssertEqual(fixture.scroll.scrollOffset, 0)
            _ = fixture.runtime.renderScene()
            _ = fixture.runtime.renderFrame()
            XCTAssertEqual(
                fixture.scroll.scrollOffset, 0, "A rejected operation must not install later alignment/retry work")
            XCTAssertEqual(probe.cleanups, 1)
            XCTAssertNil(probe.payload)
        }
    }

    private func installSelfReplacingClock(
        _ fixture: UIARealizeAdmissionFixture, detachesTarget: Bool
    ) -> UIARealizeReleaseProbe {
        let probe = UIARealizeReleaseProbe()
        let payload = UIARealizeReleasePayload { [weak fixture, weak probe] in
            guard let fixture, let probe else {
                XCTFail("The fixture and probe must survive clock capture cleanup")
                return
            }
            probe.cleanups += 1
            if detachesTarget {
                fixture.target.removeFromParent()
            } else {
                fixture.runtime.stopRenderLifecycleCallbacks()
            }
        }
        probe.payload = payload
        fixture.runtime.clock = { [weak runtime = fixture.runtime, payload, weak probe] in
            probe?.calls += 1
            runtime?.clock = { [weak probe] in
                probe?.laterClockCalls += 1
                return 100
            }
            withExtendedLifetime(payload) {}
            return 100
        }
        return probe
    }

    private func installSelfRemovingHoverExit(_ fixture: UIARealizeAdmissionFixture) -> UIARealizeReleaseProbe {
        let probe = UIARealizeReleaseProbe()
        let payload = UIARealizeReleasePayload { [weak fixture, weak probe] in
            guard let fixture, let probe else {
                XCTFail("The fixture and probe must survive hover capture cleanup")
                return
            }
            probe.cleanups += 1
            fixture.runtime.stopRenderLifecycleCallbacks()
        }
        probe.payload = payload
        fixture.gesture.onPointerExit = { [weak node = fixture.gesture, payload, weak probe] in
            probe?.calls += 1
            node?.onPointerExit = nil
            withExtendedLifetime(payload) {}
        }
        return probe
    }

    private func installGeometryHistoryPayload(
        _ fixture: UIARealizeAdmissionFixture, owner: ViewNode
    ) -> UIARealizeReleaseProbe {
        let probe = UIARealizeReleaseProbe()
        owner.observeScrollGeometry(
            of: { [weak fixture, weak probe] _ -> UIARealizeObservedValue in
                guard let fixture, let probe else { return UIARealizeObservedValue(marker: 0, payload: nil) }
                probe.samples += 1
                guard probe.samples == 1 else { return UIARealizeObservedValue(marker: 2, payload: nil) }
                let payload = UIARealizeReleasePayload { [weak fixture, weak probe] in
                    guard let fixture, let probe else {
                        XCTFail("The fixture and probe must survive cached Any cleanup")
                        return
                    }
                    probe.cleanups += 1
                    probe.offsetsAtCleanup.append(fixture.scroll.scrollOffset)
                    fixture.scroll.scrollOffset = 0
                    fixture.runtime.scheduleAfterLayout(key: "after-retired-scroll-history") { [weak probe] in
                        probe?.laterCalls += 1
                    }
                }
                probe.payload = payload
                return UIARealizeObservedValue(marker: 1, payload: payload)
            },
            action: { [weak probe] _, _ in
                probe?.geometryActions += 1
            }
        )
        owner.observeScrollPhase { _, _, _ in }
        return probe
    }
}

private enum UIARealizeCallbackBoundary: CaseIterable, Sendable {
    case query
    case clock
}

private enum UIARealizeCallbackMutation: CaseIterable, Sendable {
    case terminal
    case hidden
    case accessibilityHidden
    case hiddenAncestor
    case disabled
    case disabledAncestor
    case modal
    case detached
    case reparented
    case reattached
}

private enum UIARealizeHoverExitMutation: CaseIterable, Sendable {
    case terminal
    case detached
    case queuedLayout
}

private enum UIARealizeMixedGesture: CaseIterable, Sendable {
    case drag
    case press
    case longPress
}

@MainActor
private final class UIARealizeAdmissionProbe {
    var clockCalls = 0
    var activations = 0
    var focusEntries = 0
    var keys = 0
    var commits = 0
    var hoverExits = 0
    var pointerUpsOutside = 0
    var dragStarts = 0
    var dragEnds = 0
    var longPressBegins = 0
    var longPressCleanups = 0
    var longPressCompletions = 0
    var pressing: [Bool] = []
    var laterCalls = 0
}

@MainActor
private final class UIARealizeAdmissionFixture {
    let root: ViewNode
    let scroll: ViewNode
    let alternateScroll: ViewNode
    let target: ViewNode
    let gesture: ViewNode
    let editor: ViewNode
    let runtime: RetainedViewRuntime
    let source: RuntimeUIAElementTreeSource
    let probe: UIARealizeAdmissionProbe
    let revealedOffset: Double = 410
    let gesturePoint = Point(x: 200, y: 25)

    init() {
        let rows = (0..<20).map { index in
            ViewNode(
                preferredSize: Size(width: 120, height: 30),
                isHitTestVisible: false, accessibilityLabel: "Realize row \(index)")
        }
        let scroll = ViewNode(
            frame: Rect(x: 0, y: 0, width: 120, height: 100), clipsToBounds: true,
            layoutMode: .lazyStack(.vertical(spacing: 0)), scrollAxis: .vertical, children: rows)
        scroll.showsScrollIndicator = true
        scroll.scrollIndicatorAutoHides = true
        let alternateRows = (0..<20).map { index in
            ViewNode(
                preferredSize: Size(width: 120, height: 30),
                isHitTestVisible: false, accessibilityLabel: "Other row \(index)")
        }
        let alternateScroll = ViewNode(
            frame: Rect(x: 160, y: 120, width: 120, height: 100), clipsToBounds: true,
            layoutMode: .lazyStack(.vertical(spacing: 0)), scrollAxis: .vertical, children: alternateRows)
        let gesture = ViewNode(
            frame: Rect(x: 160, y: 10, width: 100, height: 30),
            accessibilityLabel: "Gesture action", accessibilityTraits: .isButton)
        gesture.interactionSurface = RetainedInteractionSurface(
            idleBackground: .black, hoveredBackground: .white,
            hoverDuration: 0, pressDuration: 0, focusDuration: 0)
        let editor = ViewNode(
            frame: Rect(x: 160, y: 55, width: 100, height: 30), isFocusable: true,
            accessibilityLabel: "Nested mutation editor", accessibilityValue: "original",
            accessibilityTraits: .isTextInput)
        let root = ViewNode(
            frame: Rect(x: 0, y: 0, width: 320, height: 240),
            children: [scroll, gesture, editor, alternateScroll])
        let runtime = RetainedViewRuntime(root: root)
        runtime.clock = { 100 }
        let probe = UIARealizeAdmissionProbe()
        gesture.onActivate = { probe.activations += 1 }
        gesture.onPointerExit = { probe.hoverExits += 1 }
        gesture.onPointerUpOutside = { probe.pointerUpsOutside += 1 }
        editor.onFocusEnter = { probe.focusEntries += 1 }
        editor.onKeyDown = { _ in probe.keys += 1 }
        editor.onIMEComposition = { _ in probe.commits += 1 }
        self.root = root
        self.scroll = scroll
        self.alternateScroll = alternateScroll
        self.target = rows[16]
        self.gesture = gesture
        self.editor = editor
        self.runtime = runtime
        self.probe = probe
        source = RuntimeUIAElementTreeSource(runtime: runtime)
        _ = runtime.renderScene()
        XCTAssertTrue(target.isLayoutDeferredByVirtualization)
        XCTAssertEqual(scroll.scrollOffset, 0)
    }

    func snapshot(for node: ViewNode, using source: RuntimeUIAElementTreeSource? = nil) throws -> UIAElementSnapshot {
        let name = try XCTUnwrap(node.accessibilityLabel)
        return try XCTUnwrap((source ?? self.source).uiaElementSnapshots().first { $0.name == name })
    }

    func id(for node: ViewNode, using source: RuntimeUIAElementTreeSource? = nil) throws -> UInt64 {
        try snapshot(for: node, using: source).id
    }

    func settle() {
        XCTAssertNotNil(runtime.resolvedLayoutFrame(of: root))
    }

    func countClockCalls() {
        probe.clockCalls = 0
        runtime.clock = { [weak probe] in
            probe?.clockCalls += 1
            return 100
        }
    }

    func beginIndicatorDrag() throws -> Point {
        let track = try XCTUnwrap(
            runtime.currentPrepaintState.deferredDraws.compactMap { draw -> ScrollIndicatorTrack? in
                guard case .scrollIndicator(let payload) = draw.payload, payload.node === scroll else { return nil }
                return payload.track
            }.first)
        let point = Point(x: track.indicatorRect.midX, y: track.indicatorRect.midY)
        runtime.pointerDown(at: point)
        return point
    }

    func mutate(_ mutation: UIARealizeCallbackMutation) {
        switch mutation {
        case .terminal: runtime.stopRenderLifecycleCallbacks()
        case .hidden: target.isHidden = true
        case .accessibilityHidden: target.isAccessibilityHidden = true
        case .hiddenAncestor: scroll.isHidden = true
        case .disabled: target.accessibilityRespondsToUserInteraction = false
        case .disabledAncestor: scroll.accessibilityRespondsToUserInteraction = false
        case .modal:
            let modal = ViewNode(
                frame: Rect(x: 10, y: 10, width: 290, height: 210),
                accessibilityLabel: "Blocking modal", accessibilityTraits: .isModal)
            modal.paintsInDeferredPhase = true
            root.addChild(modal)
        case .detached:
            target.removeFromParent()
        case .reparented:
            target.removeFromParent()
            alternateScroll.addChild(target)
        case .reattached:
            target.removeFromParent()
            scroll.addChild(target)
        }
    }

    func retire() {
        runtime.clock = { 100 }
        runtime.stopRenderLifecycleCallbacks()
        gesture.onPointerExit = nil
        gesture.onPointerUpOutside = nil
        gesture.onDragStart = nil
        gesture.onDragEnd = nil
        gesture.onActivate = nil
        editor.onFocusEnter = nil
        editor.onKeyDown = nil
        editor.onIMEComposition = nil
        runtime.pointerCancelled()
        gesture.longPressGesture = nil
        if runtime.retainedBuildCoordinator.isBuilding { runtime.retainedBuildCoordinator.finishBuild() }
        runtime.cancelRenderLifecycleTasks()
    }
}

@MainActor
private final class UIARealizeReleaseProbe {
    weak var payload: UIARealizeReleasePayload?
    var calls = 0
    var cleanups = 0
    var laterClockCalls = 0
    var laterCalls = 0
    var samples = 0
    var geometryActions = 0
    var offsetsAtCleanup: [Double] = []
}

@MainActor
private final class UIARealizeReleasePayload {
    private let onRelease: @MainActor () -> Void

    init(onRelease: @escaping @MainActor () -> Void) {
        self.onRelease = onRelease
    }

    isolated deinit { onRelease() }
}

private struct UIARealizeObservedValue: Equatable {
    let marker: Int
    let payload: UIARealizeReleasePayload?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.marker == rhs.marker && lhs.payload === rhs.payload
    }
}
