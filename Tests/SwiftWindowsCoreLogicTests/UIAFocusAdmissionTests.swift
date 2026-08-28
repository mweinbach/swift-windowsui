import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Retained focus admission and source results. The one host fixture uses fake
/// renderers and never creates an HWND; no native UIA HRESULT is qualified here.
@MainActor
final class UIAFocusAdmissionTests: XCTestCase {
    func testLiveTargetAndVoidEntryUseTheSameFocusPath() async throws {
        let fixture = UIAFocusAdmissionFixture()
        defer { fixture.retire() }
        let targetID = try fixture.id(for: fixture.target)
        var initialCallbacks = 0
        fixture.runtime.scheduleAfterLayout(key: "initial-focus-query") { initialCallbacks += 1 }

        XCTAssertTrue(fixture.source.uiaSetFocusResult(elementID: targetID))
        XCTAssertEqual(initialCallbacks, 1)
        XCTAssertTrue(fixture.runtime.focusedNode === fixture.target)
        XCTAssertTrue(fixture.target.isFocused)
        XCTAssertEqual(fixture.probe.entries, 1)
        XCTAssertEqual(fixture.probe.notifications, ["Target"])

        let alternateID = try fixture.id(for: fixture.alternate)
        fixture.source.uiaSetFocus(elementID: alternateID)
        XCTAssertTrue(fixture.runtime.focusedNode === fixture.alternate)
        XCTAssertFalse(fixture.target.isFocused)
        XCTAssertEqual(fixture.probe.notifications, ["Target", "Alternate"])
    }

    func testAlreadyFocusedTargetStillChecksAdmissionWithoutDuplicateDelivery() async throws {
        let fixture = UIAFocusAdmissionFixture()
        defer { fixture.retire() }
        fixture.runtime.requestFocus(fixture.target)
        fixture.settle()
        fixture.probe.reset()
        let id = try fixture.id(for: fixture.target)
        var initialCallbacks = 0
        fixture.runtime.scheduleAfterLayout(key: "already-focused-query") { initialCallbacks += 1 }

        XCTAssertTrue(fixture.source.uiaSetFocusResult(elementID: id))
        XCTAssertEqual(initialCallbacks, 1)
        XCTAssertTrue(fixture.runtime.focusedNode === fixture.target)
        XCTAssertEqual(fixture.probe.entries, 0)
        XCTAssertEqual(fixture.probe.exits, 0)
        XCTAssertTrue(fixture.probe.notifications.isEmpty)
    }

    func testPublicFocusBindingPaintInvalidationCanSettleTheSameTarget() async throws {
        let fixture = UIAFocusAdmissionFixture()
        defer { fixture.retire() }
        var focused = false
        var writes: [Bool] = []
        let binding = FocusState<Bool>.Binding(
            get: { focused },
            set: { [weak owner = fixture.owner] value in
                writes.append(value)
                focused = value
                owner?.accessibilityLabel = "Owner updated by focus binding"
            })
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 320, height: 200) }, invalidateHandler: {})
        let target = Text("Bound focus target")
            .focused(binding)
            .accessibilityLabel("Bound focus target")
            .makeComponent(context: context)
            .makeNode(runtime: fixture.runtime)
        fixture.owner.addChild(target)
        fixture.settle()
        let id = try fixture.id(for: target)
        XCTAssertFalse(focused)
        XCTAssertTrue(writes.isEmpty)

        XCTAssertTrue(fixture.source.uiaSetFocusResult(elementID: id))
        XCTAssertTrue(focused)
        XCTAssertEqual(writes, [true])
        XCTAssertEqual(fixture.owner.accessibilityLabel, "Owner updated by focus binding")
        XCTAssertTrue(fixture.runtime.focusedNode === target)
        XCTAssertTrue(target.isFocused)
        XCTAssertEqual(fixture.probe.notifications, ["Bound focus target"])
    }

    func testIneligibleTargetsRejectBeforeAnyFocusCallback() async throws {
        for route in UIAFocusAdmissionRoute.allCases {
            for rejection in UIAFocusInitialRejection.allCases {
                let fixture = UIAFocusAdmissionFixture(focusPrevious: true)
                defer { fixture.retire() }
                let id = try fixture.id(for: fixture.target)
                var foreignRuntime: RetainedViewRuntime?
                switch rejection {
                case .notFocusable:
                    fixture.target.isFocusable = false
                case .disabledTarget:
                    fixture.target.accessibilityRespondsToUserInteraction = false
                case .disabledAncestor:
                    fixture.owner.accessibilityRespondsToUserInteraction = false
                case .hiddenTarget:
                    fixture.target.isHidden = true
                case .hiddenAncestor:
                    fixture.owner.isHidden = true
                case .accessibilityHidden:
                    fixture.target.isAccessibilityHidden = true
                case .detached:
                    fixture.owner.removeChild(fixture.target)
                case .foreignRuntime:
                    fixture.owner.removeChild(fixture.target)
                    let foreignRoot = ViewNode(frame: fixture.root.frame, children: [fixture.target])
                    foreignRuntime = RetainedViewRuntime(root: foreignRoot)
                case .terminal:
                    fixture.runtime.stopRenderLifecycleCallbacks()
                }
                // Hiding the ancestor can legitimately clear the previous
                // focus during setup. Count only the rejected request below.
                fixture.probe.reset()

                withExtendedLifetime(foreignRuntime) {
                    XCTAssertFalse(route.invoke(fixture, id: id), "\(route), \(rejection)")
                }
                XCTAssertEqual(fixture.probe.entries, 0, "\(route), \(rejection)")
                XCTAssertEqual(fixture.probe.exits, 0, "\(route), \(rejection)")
                XCTAssertTrue(fixture.probe.notifications.isEmpty, "\(route), \(rejection)")
                XCTAssertFalse(fixture.target.isFocused, "\(route), \(rejection)")
            }
        }
    }

    func testTerminalRuntimeDoesNotStartQueuedFocusLayout() async throws {
        let fixture = UIAFocusAdmissionFixture()
        defer { fixture.retire() }
        let id = try fixture.id(for: fixture.target)
        var layoutCallbacks = 0
        fixture.runtime.scheduleAfterLayout(key: "must-not-start-after-close") { layoutCallbacks += 1 }
        fixture.runtime.stopRenderLifecycleCallbacks()

        XCTAssertFalse(fixture.source.uiaSetFocusResult(elementID: id))
        XCTAssertFalse(fixture.runtime.requestAccessibilityFocus(fixture.target))
        fixture.source.uiaSetFocus(elementID: id)
        XCTAssertEqual(layoutCallbacks, 0)
        XCTAssertEqual(fixture.probe.entries, 0)
        XCTAssertTrue(fixture.probe.notifications.isEmpty)
    }

    func testBuildAndLayoutCallbackEntryLeaveQueuedWorkForAnIndependentRequest() async throws {
        for duringLayoutCallback in [false, true] {
            let fixture = UIAFocusAdmissionFixture()
            defer { fixture.retire() }
            let id = try fixture.id(for: fixture.target)
            var pendingCallbacks = 0
            var nestedResults: [Bool] = []
            if duringLayoutCallback {
                fixture.runtime.scheduleAfterLayout(key: "focus-entry-from-layout") { [weak fixture] in
                    guard let fixture else { return }
                    fixture.runtime.scheduleAfterLayout(key: "pending-layout-entry-work") { pendingCallbacks += 1 }
                    nestedResults.append(fixture.source.uiaSetFocusResult(elementID: id))
                }
                fixture.settle()
                XCTAssertEqual(nestedResults, [false])
            } else {
                XCTAssertNotNil(fixture.runtime.retainedBuildCoordinator.beginBuild())
                fixture.runtime.scheduleAfterLayout(key: "pending-build-entry-work") { pendingCallbacks += 1 }
                XCTAssertFalse(fixture.source.uiaSetFocusResult(elementID: id))
                XCTAssertTrue(fixture.runtime.retainedBuildCoordinator.isBuilding)
                fixture.runtime.retainedBuildCoordinator.finishBuild()
            }
            XCTAssertEqual(pendingCallbacks, 0, "during layout callback: \(duringLayoutCallback)")
            XCTAssertEqual(fixture.probe.entries, 0)
            XCTAssertTrue(fixture.probe.notifications.isEmpty)
            XCTAssertNil(fixture.runtime.focusedNode)

            XCTAssertTrue(fixture.source.uiaSetFocusResult(elementID: id))
            XCTAssertEqual(pendingCallbacks, 1)
            XCTAssertEqual(fixture.probe.entries, 1)
            XCTAssertEqual(fixture.probe.notifications, ["Target"])
        }
    }

    func testSyntheticRepresentationDoesNotInventAKeyboardFocusOwner() async throws {
        for insideModal in [false, true] {
            let fixture = UIAFocusAdmissionFixture()
            defer { fixture.retire() }
            let representedOwner: ViewNode
            if insideModal {
                representedOwner = fixture.presentModal().action
            } else {
                representedOwner = fixture.owner
            }
            let synthetic = ViewNode(
                frame: Rect(x: 0, y: 0, width: 80, height: 30),
                isFocusable: true, accessibilityLabel: "Synthetic focus target", accessibilityTraits: .isButton)
            var entries = 0
            synthetic.onFocusEnter = { entries += 1 }
            representedOwner.accessibilityRepresentationChildren = [synthetic]
            fixture.settle()
            let id = try fixture.id(for: synthetic)
            XCTAssertNil(synthetic.parent)

            XCTAssertFalse(fixture.source.uiaSetFocusResult(elementID: id))
            XCTAssertFalse(fixture.runtime.requestAccessibilityFocus(synthetic))
            fixture.source.uiaSetFocus(elementID: id)
            XCTAssertEqual(entries, 0)
            XCTAssertFalse(synthetic.isFocused)
            XCTAssertNil(fixture.runtime.focusedNode)
            XCTAssertTrue(fixture.probe.notifications.isEmpty)
        }
    }

    func testCurrentModalAdmitsItsTargetButNotBackgroundOrStructuralRoot() async throws {
        let fixture = UIAFocusAdmissionFixture()
        defer { fixture.retire() }
        fixture.root.isFocusable = true
        let backgroundID = try fixture.id(for: fixture.target)
        let modal = fixture.presentModal()
        fixture.settle()
        let modalID = try fixture.id(for: modal.action)
        var modalEntries = 0
        modal.action.onFocusEnter = { modalEntries += 1 }

        XCTAssertFalse(fixture.source.uiaSetFocusResult(elementID: backgroundID))
        XCTAssertFalse(fixture.source.uiaSetFocusResult(elementID: UIAProviderBridge.rootElementID))
        XCTAssertTrue(fixture.source.uiaSetFocusResult(elementID: modalID))
        XCTAssertTrue(fixture.runtime.focusedNode === modal.action)
        XCTAssertEqual(modalEntries, 1)
        XCTAssertEqual(fixture.probe.entries, 0)
        XCTAssertFalse(fixture.root.isFocused)
    }

    func testPaintOnlyModalReorderingIsResolvedBeforeFocusAdmission() async throws {
        let fixture = UIAFocusAdmissionFixture()
        defer { fixture.retire() }
        let original = fixture.presentModal(label: "Original modal")
        let replacement = fixture.presentModal(label: "Replacement modal")
        original.node.zIndex = 2
        replacement.node.zIndex = 1
        fixture.settle()
        let originalID = try fixture.id(for: original.action)
        guard case .settled(let receipt) = fixture.runtime.layoutSettlementStatus else {
            return XCTFail("Expected settled geometry before the paint-only reorder")
        }
        XCTAssertTrue(fixture.runtime.activeModalPresentationNode === original.node)
        replacement.node.zIndex = 3
        XCTAssertTrue(fixture.runtime.isLayoutSettlementReceiptCurrent(receipt))
        XCTAssertTrue(fixture.runtime.activeModalPresentationNode === original.node)

        XCTAssertFalse(fixture.source.uiaSetFocusResult(elementID: originalID))
        XCTAssertFalse(original.action.isFocused)
        XCTAssertTrue(fixture.runtime.activeModalPresentationNode === replacement.node)
        XCTAssertTrue(fixture.source.uiaSetFocusResult(elementID: try fixture.id(for: replacement.action)))
        XCTAssertTrue(fixture.runtime.focusedNode === replacement.action)
    }

    func testInitialLayoutModalOrTerminalChangeRejectsBeforeFocusDelivery() async throws {
        for closesRuntime in [false, true] {
            let fixture = UIAFocusAdmissionFixture(focusPrevious: true)
            defer { fixture.retire() }
            let id = try fixture.id(for: fixture.target)
            var layoutCallbacks = 0
            fixture.runtime.scheduleAfterLayout(key: "invalidate-focus-at-entry") { [weak fixture] in
                layoutCallbacks += 1
                guard let fixture else { return }
                if closesRuntime {
                    fixture.runtime.stopRenderLifecycleCallbacks()
                } else {
                    fixture.presentModal()
                }
            }

            XCTAssertFalse(fixture.source.uiaSetFocusResult(elementID: id))
            XCTAssertEqual(layoutCallbacks, 1)
            XCTAssertEqual(fixture.probe.entries, 0)
            XCTAssertEqual(fixture.probe.exits, 0)
            XCTAssertTrue(fixture.probe.notifications.isEmpty)
            XCTAssertFalse(fixture.target.isFocused)
            if closesRuntime {
                XCTAssertFalse(fixture.runtime.permitsRetainedActionInvocation)
            } else {
                XCTAssertNotNil(fixture.runtime.activeModalPresentationNode)
            }
        }
    }

    func testHeadlessHostCloseDuringEntryQueryRejectsFocusAndLateVoidRequests() async throws {
        let renderer = FakeRenderBackend()
        let host = WinSwiftUIWindowHost(
            configuration: WindowGroupConfiguration(
                title: "Focus admission", size: IntSize(width: 320, height: 180),
                clearColor: .black, content: [AnyView(EmptyView())]),
            renderer: renderer, batchRenderer: FakeBatchRenderBackend(), startupProbeConfiguration: nil)
        defer { host.windowWillClose(host.platformWindow) }
        XCTAssertNil(host.platformWindow.nativeHandle)
        let runtime = host.hostedRuntime
        let target = ViewNode(
            frame: Rect(x: 10, y: 10, width: 100, height: 30), isFocusable: true,
            accessibilityLabel: "Host focus target", accessibilityTraits: .isButton)
        runtime.root.addChild(target)
        var entries = 0
        var closes = 0
        target.onFocusEnter = { entries += 1 }
        XCTAssertNotNil(runtime.resolvedLayoutFrame(of: runtime.root))
        let source = RuntimeUIAElementTreeSource(runtime: runtime)
        let id = try XCTUnwrap(source.uiaElementSnapshots().first { $0.name == "Host focus target" }?.id)
        runtime.scheduleAfterLayout(key: "close-before-focus") { [weak host] in
            closes += 1
            guard let host else { return }
            host.windowWillClose(host.platformWindow)
        }

        XCTAssertFalse(source.uiaSetFocusResult(elementID: id))
        source.uiaSetFocus(elementID: id)
        XCTAssertEqual(closes, 1)
        XCTAssertEqual(entries, 0)
        XCTAssertEqual(renderer.detachCount, 1)
        XCTAssertFalse(runtime.permitsRetainedActionInvocation)
        XCTAssertFalse(target.isFocused)
    }

    func testEntryQueryLeavesNewlyQueuedWorkForAnIndependentRequest() async throws {
        let fixture = UIAFocusAdmissionFixture()
        defer { fixture.retire() }
        let id = try fixture.id(for: fixture.target)
        var firstCallbacks = 0
        var secondCallbacks = 0
        fixture.runtime.scheduleAfterLayout(key: "first-entry-callback") { [weak runtime = fixture.runtime] in
            firstCallbacks += 1
            runtime?.scheduleAfterLayout(key: "second-entry-callback") { secondCallbacks += 1 }
        }

        XCTAssertFalse(fixture.source.uiaSetFocusResult(elementID: id))
        XCTAssertEqual(firstCallbacks, 1)
        XCTAssertEqual(secondCallbacks, 0)
        XCTAssertEqual(fixture.probe.entries, 0)
        XCTAssertTrue(fixture.probe.notifications.isEmpty)
        XCTAssertTrue(fixture.source.uiaSetFocusResult(elementID: id))
        XCTAssertEqual(firstCallbacks, 1)
        XCTAssertEqual(secondCallbacks, 1)
        XCTAssertEqual(fixture.probe.entries, 1)
        XCTAssertEqual(fixture.probe.notifications, ["Target"])
    }

    func testExitAndEnterCallbacksRevalidateTargetModalAndBuildState() async throws {
        for boundary in [UIAFocusCallbackBoundary.exit, .enter] {
            for mutation in UIAFocusCallbackMutation.allCases {
                let fixture = UIAFocusAdmissionFixture(focusPrevious: true)
                defer { fixture.retire() }
                let id = try fixture.id(for: fixture.target)
                var callbackCalls = 0
                var didMutate = false
                fixture.install(boundary) { [weak fixture] in
                    callbackCalls += 1
                    guard !didMutate, let fixture else { return }
                    didMutate = true
                    fixture.mutate(mutation)
                }

                XCTAssertFalse(fixture.source.uiaSetFocusResult(elementID: id), "\(boundary), \(mutation)")
                XCTAssertEqual(callbackCalls, 1, "\(boundary), \(mutation)")
                XCTAssertEqual(fixture.probe.entries, boundary == .enter ? 1 : 0, "\(boundary), \(mutation)")
                XCTAssertFalse(fixture.probe.notifications.contains("Target"), "\(boundary), \(mutation)")
                if mutation == .redirect {
                    XCTAssertTrue(fixture.runtime.focusedNode === fixture.alternate)
                    XCTAssertEqual(fixture.probe.notifications, ["Alternate"])
                }
                if mutation == .beginBuild {
                    XCTAssertTrue(fixture.runtime.retainedBuildCoordinator.isBuilding)
                }
            }
        }
    }

    func testEachPermittedCallbackBoundaryCanSettleOneNeutralLayoutCallback() async throws {
        for boundary in UIAFocusCallbackBoundary.allCases {
            let fixture = UIAFocusAdmissionFixture(focusPrevious: true)
            defer { fixture.retire() }
            let id = try fixture.id(for: fixture.target)
            var callbackCalls = 0
            var layoutCallbacks = 0
            var didEnqueue = false
            fixture.install(boundary) { [weak fixture] in
                callbackCalls += 1
                guard !didEnqueue, let fixture else { return }
                didEnqueue = true
                fixture.runtime.scheduleAfterLayout(key: "boundary-neutral-layout") { layoutCallbacks += 1 }
            }

            XCTAssertTrue(fixture.source.uiaSetFocusResult(elementID: id), "\(boundary)")
            XCTAssertEqual(callbackCalls, 1, "\(boundary)")
            XCTAssertEqual(layoutCallbacks, 1, "\(boundary)")
            XCTAssertEqual(fixture.probe.entries, 1, "\(boundary)")
            XCTAssertEqual(fixture.probe.notifications, ["Target"], "\(boundary)")
            XCTAssertTrue(fixture.runtime.focusedNode === fixture.target, "\(boundary)")
        }
    }

    func testEachPermittedCallbackBoundaryUsesAtMostOneFollowupQuery() async throws {
        for boundary in UIAFocusCallbackBoundary.allCases {
            let fixture = UIAFocusAdmissionFixture(focusPrevious: true)
            defer { fixture.retire() }
            let id = try fixture.id(for: fixture.target)
            var callbackCalls = 0
            var firstCallbacks = 0
            var secondCallbacks = 0
            var didEnqueue = false
            fixture.install(boundary) { [weak fixture] in
                callbackCalls += 1
                guard !didEnqueue, let fixture else { return }
                didEnqueue = true
                fixture.runtime.scheduleAfterLayout(key: "first-boundary-layout") { [weak runtime = fixture.runtime] in
                    firstCallbacks += 1
                    runtime?.scheduleAfterLayout(key: "second-boundary-layout") { secondCallbacks += 1 }
                }
            }

            XCTAssertFalse(fixture.source.uiaSetFocusResult(elementID: id), "\(boundary)")
            XCTAssertEqual(callbackCalls, 1, "\(boundary)")
            XCTAssertEqual(firstCallbacks, 1, "\(boundary)")
            XCTAssertEqual(secondCallbacks, 0, "\(boundary)")
            XCTAssertFalse(fixture.probe.notifications.contains("Target"), "\(boundary)")
            fixture.settle()
            XCTAssertEqual(secondCallbacks, 1, "\(boundary)")
            XCTAssertEqual(callbackCalls, 1, "\(boundary)")
        }
    }

    func testAllFourCallbackBoundariesFitTheFiveQueryBudgetWithoutASixthRetry() async throws {
        for queuesSixthQuery in [false, true] {
            let fixture = UIAFocusAdmissionFixture(focusPrevious: true)
            defer { fixture.retire() }
            let id = try fixture.id(for: fixture.target)
            fixture.previous.interactionSurface = RetainedInteractionSurface()
            fixture.target.interactionSurface = RetainedInteractionSurface()
            var events: [String] = []
            var clockCalls = 0
            var exitCalls = 0
            var enterCalls = 0
            var sixthCallbacks = 0
            fixture.runtime.scheduleAfterLayout(key: "compound-initial-query") {
                events.append("initial-layout")
            }
            fixture.runtime.clock = { [weak fixture] in
                clockCalls += 1
                guard let fixture else { return 0 }
                switch clockCalls {
                case 1:
                    events.append("old-clock")
                    fixture.runtime.scheduleAfterLayout(key: "compound-old-clock-query") {
                        events.append("old-layout")
                    }
                case 2:
                    events.append("new-clock")
                    fixture.runtime.scheduleAfterLayout(key: "compound-new-clock-query") { [weak fixture] in
                        events.append("new-layout")
                        if queuesSixthQuery {
                            fixture?.runtime.scheduleAfterLayout(key: "compound-sixth-query") {
                                sixthCallbacks += 1
                            }
                        }
                    }
                default:
                    events.append("unexpected-clock")
                }
                return 0
            }
            fixture.previous.onFocusExit = { [weak fixture] in
                exitCalls += 1
                guard exitCalls == 1, let fixture else { return }
                events.append("exit")
                fixture.runtime.scheduleAfterLayout(key: "compound-exit-query") {
                    events.append("exit-layout")
                }
            }
            fixture.target.onFocusEnter = { [weak fixture] in
                enterCalls += 1
                guard enterCalls == 1, let fixture else { return }
                events.append("enter")
                fixture.runtime.scheduleAfterLayout(key: "compound-enter-query") {
                    events.append("enter-layout")
                }
            }
            fixture.runtime.onAccessibilityFocusChanged = { [weak target = fixture.target] focused in
                guard focused === target else { return }
                events.append("notification")
            }

            XCTAssertEqual(fixture.source.uiaSetFocusResult(elementID: id), !queuesSixthQuery)
            let expected = [
                "initial-layout", "old-clock", "old-layout", "exit", "exit-layout",
                "enter", "enter-layout", "new-clock", "new-layout",
            ]
            XCTAssertEqual(events, queuesSixthQuery ? expected : expected + ["notification"])
            XCTAssertEqual(clockCalls, 2)
            XCTAssertEqual(exitCalls, 1)
            XCTAssertEqual(enterCalls, 1)
            XCTAssertEqual(sixthCallbacks, 0)
            if queuesSixthQuery {
                fixture.settle()
                XCTAssertEqual(sixthCallbacks, 1)
                XCTAssertEqual(events, expected)
                XCTAssertEqual(clockCalls, 2)
            } else {
                XCTAssertTrue(fixture.runtime.focusedNode === fixture.target)
                XCTAssertTrue(fixture.target.isFocused)
            }
        }
    }

    func testFinalAccessibilityNotificationCannotDrainAnotherLayoutQuery() async throws {
        let fixture = UIAFocusAdmissionFixture()
        defer { fixture.retire() }
        let id = try fixture.id(for: fixture.target)
        var notifications = 0
        var laterCallbacks = 0
        var didEnqueue = false
        fixture.runtime.onAccessibilityFocusChanged = { [weak fixture] focused in
            guard let fixture, focused === fixture.target else { return }
            notifications += 1
            guard !didEnqueue else { return }
            didEnqueue = true
            fixture.runtime.scheduleAfterLayout(key: "after-final-focus-notification") { laterCallbacks += 1 }
        }

        // The callback has already observed focus. Rejection does not pretend
        // those effects never happened, nor run another query to claim success.
        XCTAssertFalse(fixture.source.uiaSetFocusResult(elementID: id))
        XCTAssertEqual(notifications, 1)
        XCTAssertEqual(fixture.probe.entries, 1)
        XCTAssertEqual(laterCallbacks, 0)
        fixture.settle()
        XCTAssertEqual(laterCallbacks, 1)
        XCTAssertEqual(notifications, 1)
    }

    func testFinalAccessibilityNotificationCannotApproveInvalidatedFocus() async throws {
        for mutation in UIAFocusCallbackMutation.allCases {
            let fixture = UIAFocusAdmissionFixture()
            defer { fixture.retire() }
            let id = try fixture.id(for: fixture.target)
            var targetNotifications = 0
            var didMutate = false
            fixture.runtime.onAccessibilityFocusChanged = { [weak fixture] focused in
                guard let fixture, focused === fixture.target else { return }
                targetNotifications += 1
                guard !didMutate else { return }
                didMutate = true
                fixture.mutate(mutation)
            }

            XCTAssertFalse(fixture.source.uiaSetFocusResult(elementID: id), "\(mutation)")
            XCTAssertEqual(targetNotifications, 1, "\(mutation)")
            XCTAssertEqual(fixture.probe.entries, 1, "\(mutation)")
            if mutation == .redirect {
                XCTAssertTrue(fixture.runtime.focusedNode === fixture.alternate)
            }
        }
    }

    func testFinalCallbackCaptureCleanupFinishesBeforeThePureResultCheck() async throws {
        for queuesLayout in [false, true] {
            let fixture = UIAFocusAdmissionFixture()
            defer { fixture.retire() }
            let id = try fixture.id(for: fixture.target)
            let probe = installSelfRemovingFocusNotification(fixture, queuesLayout: queuesLayout)
            XCTAssertNotNil(probe.payload)

            XCTAssertFalse(fixture.source.uiaSetFocusResult(elementID: id))
            XCTAssertEqual(probe.notifications, 1)
            XCTAssertEqual(probe.cleanups, 1)
            XCTAssertNil(probe.payload)
            XCTAssertEqual(probe.laterCallbacks, 0)
            if queuesLayout {
                fixture.settle()
                XCTAssertEqual(probe.laterCallbacks, 1)
            } else {
                XCTAssertFalse(fixture.target.isFocusable)
            }
            XCTAssertEqual(probe.notifications, 1)
            XCTAssertEqual(probe.cleanups, 1)
        }
    }

    func testSourcePinsTheEntryRuntimeUntilTheFocusResultReturns() async throws {
        for drop in UIAFocusRuntimeDrop.allCases {
            let fixture = try UIAFocusRuntimeLifetimeFixture(drop: drop)
            defer { fixture.retire() }
            XCTAssertNotNil(fixture.probe.runtime)

            XCTAssertTrue(fixture.source.uiaSetFocusResult(elementID: fixture.targetID), "\(drop)")
            XCTAssertEqual(fixture.probe.entries, 1, "\(drop)")
            XCTAssertEqual(fixture.probe.notifications, 1, "\(drop)")
            XCTAssertEqual(fixture.probe.aliveInEntry, [true], "\(drop)")
            XCTAssertEqual(fixture.probe.aliveInNotification, [true], "\(drop)")
            XCTAssertEqual(fixture.probe.layoutCallbacks, drop == .layout ? 1 : 0)
            XCTAssertNil(fixture.owner.runtime)
            XCTAssertNil(fixture.probe.runtime)

            XCTAssertFalse(fixture.source.uiaSetFocusResult(elementID: fixture.targetID))
            fixture.source.uiaSetFocus(elementID: fixture.targetID)
            XCTAssertEqual(fixture.probe.entries, 1)
            XCTAssertEqual(fixture.probe.notifications, 1)
            withExtendedLifetime(fixture.root) {}
        }
    }

    private func installSelfRemovingFocusNotification(
        _ fixture: UIAFocusAdmissionFixture, queuesLayout: Bool
    ) -> UIAFocusCleanupProbe {
        let probe = UIAFocusCleanupProbe()
        let payload = UIAFocusCleanupPayload { [weak fixture, weak probe] in
            guard let fixture, let probe else {
                XCTFail("The fixture and probe must survive callback capture cleanup")
                return
            }
            probe.cleanups += 1
            if queuesLayout {
                fixture.runtime.scheduleAfterLayout(key: "focus-capture-cleanup-layout") { [weak probe] in
                    probe?.laterCallbacks += 1
                }
            } else {
                fixture.target.isFocusable = false
            }
        }
        probe.payload = payload
        fixture.runtime.onAccessibilityFocusChanged = {
            [weak runtime = fixture.runtime, weak target = fixture.target, payload, weak probe] focused in
            guard focused === target, let probe else { return }
            probe.notifications += 1
            runtime?.onAccessibilityFocusChanged = nil
            withExtendedLifetime(payload) {}
        }
        return probe
    }
}

private enum UIAFocusAdmissionRoute: CaseIterable, Sendable {
    case source
    case runtime

    @MainActor
    func invoke(_ fixture: UIAFocusAdmissionFixture, id: UInt64) -> Bool {
        switch self {
        case .source: return fixture.source.uiaSetFocusResult(elementID: id)
        case .runtime: return fixture.runtime.requestAccessibilityFocus(fixture.target)
        }
    }
}

private enum UIAFocusInitialRejection: CaseIterable, Sendable {
    case notFocusable
    case disabledTarget
    case disabledAncestor
    case hiddenTarget
    case hiddenAncestor
    case accessibilityHidden
    case detached
    case foreignRuntime
    case terminal
}

private enum UIAFocusCallbackBoundary: CaseIterable, Sendable {
    case oldClock
    case exit
    case enter
    case newClock
}

private enum UIAFocusCallbackMutation: CaseIterable, Sendable {
    case notFocusable
    case disabled
    case hidden
    case removed
    case modal
    case beginBuild
    case terminal
    case redirect
}

@MainActor
private final class UIAFocusAdmissionProbe {
    var entries = 0
    var exits = 0
    var notifications: [String] = []

    func reset() {
        entries = 0
        exits = 0
        notifications = []
    }
}

@MainActor
private final class UIAFocusAdmissionFixture {
    let root: ViewNode
    let owner: ViewNode
    let previous: ViewNode
    let target: ViewNode
    let alternate: ViewNode
    let runtime: RetainedViewRuntime
    let source: RuntimeUIAElementTreeSource
    let probe: UIAFocusAdmissionProbe

    init(focusPrevious: Bool = false) {
        let previous = ViewNode(
            frame: Rect(x: 10, y: 10, width: 100, height: 30),
            isFocusable: true, accessibilityLabel: "Previous", accessibilityTraits: .isButton)
        let target = ViewNode(
            frame: Rect(x: 10, y: 50, width: 100, height: 30),
            isFocusable: true, accessibilityLabel: "Target", accessibilityTraits: .isButton)
        let alternate = ViewNode(
            frame: Rect(x: 10, y: 90, width: 100, height: 30),
            isFocusable: true, accessibilityLabel: "Alternate", accessibilityTraits: .isButton)
        let owner = ViewNode(
            frame: Rect(x: 0, y: 0, width: 280, height: 160),
            accessibilityLabel: "Owner", children: [previous, target, alternate])
        let root = ViewNode(
            frame: Rect(x: 0, y: 0, width: 320, height: 200), accessibilityLabel: "Root", children: [owner])
        let runtime = RetainedViewRuntime(root: root)
        runtime.clock = { 0 }
        let probe = UIAFocusAdmissionProbe()
        self.root = root
        self.owner = owner
        self.previous = previous
        self.target = target
        self.alternate = alternate
        self.runtime = runtime
        self.probe = probe
        source = RuntimeUIAElementTreeSource(runtime: runtime)
        settle()
        if focusPrevious {
            runtime.requestFocus(previous)
            settle()
            XCTAssertTrue(runtime.focusedNode === previous)
        }
        previous.onFocusExit = { probe.exits += 1 }
        target.onFocusEnter = { probe.entries += 1 }
        runtime.onAccessibilityFocusChanged = { focused in
            probe.notifications.append(focused?.accessibilityLabel ?? "nil")
        }
    }

    func id(for node: ViewNode) throws -> UInt64 {
        let name = try XCTUnwrap(node.accessibilityLabel)
        return try XCTUnwrap(source.uiaElementSnapshots().first { $0.name == name }?.id)
    }

    func settle() {
        XCTAssertNotNil(runtime.resolvedLayoutFrame(of: root))
    }

    @discardableResult
    func presentModal(label: String = "Current modal") -> (node: ViewNode, action: ViewNode) {
        let action = ViewNode(
            frame: Rect(x: 10, y: 10, width: 100, height: 30),
            isFocusable: true, accessibilityLabel: "\(label) action", accessibilityTraits: .isButton)
        let modal = ViewNode(
            frame: Rect(x: 40, y: 20, width: 200, height: 140),
            accessibilityLabel: label, accessibilityTraits: .isModal, children: [action])
        modal.paintsInDeferredPhase = true
        root.addChild(modal)
        return (modal, action)
    }

    func install(_ boundary: UIAFocusCallbackBoundary, action: @escaping @MainActor () -> Void) {
        switch boundary {
        case .oldClock:
            previous.interactionSurface = RetainedInteractionSurface()
            runtime.clock = {
                action()
                return 0
            }
        case .exit:
            previous.onFocusExit = { [probe] in
                probe.exits += 1
                action()
            }
        case .enter:
            target.onFocusEnter = { [probe] in
                probe.entries += 1
                action()
            }
        case .newClock:
            target.interactionSurface = RetainedInteractionSurface()
            runtime.clock = {
                action()
                return 0
            }
        }
    }

    func mutate(_ mutation: UIAFocusCallbackMutation) {
        switch mutation {
        case .notFocusable: target.isFocusable = false
        case .disabled: target.accessibilityRespondsToUserInteraction = false
        case .hidden: target.isHidden = true
        case .removed: target.removeFromParent()
        case .modal: presentModal()
        case .beginBuild: XCTAssertNotNil(runtime.retainedBuildCoordinator.beginBuild())
        case .terminal: runtime.stopRenderLifecycleCallbacks()
        case .redirect: runtime.requestFocus(alternate)
        }
    }

    func retire() {
        runtime.stopRenderLifecycleCallbacks()
        runtime.onAccessibilityFocusChanged = nil
        runtime.clock = { 0 }
        for node in [previous, target, alternate] {
            node.onFocusEnter = nil
            node.onFocusExit = nil
        }
        if runtime.retainedBuildCoordinator.isBuilding { runtime.retainedBuildCoordinator.finishBuild() }
        runtime.cancelRenderLifecycleTasks()
    }
}

@MainActor
private final class UIAFocusCleanupProbe {
    weak var payload: UIAFocusCleanupPayload?
    var notifications = 0
    var cleanups = 0
    var laterCallbacks = 0
}

@MainActor
private final class UIAFocusCleanupPayload {
    private let onRelease: @MainActor () -> Void

    init(onRelease: @escaping @MainActor () -> Void) {
        self.onRelease = onRelease
    }

    isolated deinit { onRelease() }
}

private enum UIAFocusRuntimeDrop: CaseIterable, Sendable {
    case layout
    case enter
    case notification
}

@MainActor
private final class UIAFocusRuntimeOwner {
    var runtime: RetainedViewRuntime?
}

@MainActor
private final class UIAFocusRuntimeProbe {
    weak var runtime: RetainedViewRuntime?
    var layoutCallbacks = 0
    var entries = 0
    var notifications = 0
    var aliveInEntry: [Bool] = []
    var aliveInNotification: [Bool] = []
}

@MainActor
private final class UIAFocusRuntimeLifetimeFixture {
    let owner: UIAFocusRuntimeOwner
    let probe: UIAFocusRuntimeProbe
    let root: ViewNode
    let target: ViewNode
    let source: RuntimeUIAElementTreeSource
    let targetID: UInt64

    init(drop: UIAFocusRuntimeDrop) throws {
        let target = ViewNode(
            frame: Rect(x: 10, y: 10, width: 100, height: 30),
            isFocusable: true, accessibilityLabel: "Owned focus target", accessibilityTraits: .isButton)
        let root = ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 100), children: [target])
        let runtime = RetainedViewRuntime(root: root)
        runtime.clock = { 0 }
        let owner = UIAFocusRuntimeOwner()
        owner.runtime = runtime
        let probe = UIAFocusRuntimeProbe()
        probe.runtime = runtime
        let source = RuntimeUIAElementTreeSource(runtime: runtime)
        XCTAssertNotNil(runtime.resolvedLayoutFrame(of: root))
        let targetID = try XCTUnwrap(source.uiaElementSnapshots().first { $0.name == "Owned focus target" }?.id)
        target.onFocusEnter = { [weak owner] in
            probe.entries += 1
            if drop == .enter { owner?.runtime = nil }
            probe.aliveInEntry.append(probe.runtime != nil)
        }
        runtime.onAccessibilityFocusChanged = { [weak owner, weak target] focused in
            guard focused === target else { return }
            probe.notifications += 1
            if drop == .notification { owner?.runtime = nil }
            probe.aliveInNotification.append(probe.runtime != nil)
        }
        if drop == .layout {
            runtime.scheduleAfterLayout(key: "drop-runtime-during-focus-entry") { [weak owner, weak probe] in
                probe?.layoutCallbacks += 1
                owner?.runtime = nil
            }
        }
        self.owner = owner
        self.probe = probe
        self.root = root
        self.target = target
        self.source = source
        self.targetID = targetID
        // The initializer's runtime local ends here. Only owner.runtime keeps
        // it alive between operations; all other runtime references are weak.
    }

    func retire() {
        probe.runtime?.stopRenderLifecycleCallbacks()
        probe.runtime?.onAccessibilityFocusChanged = nil
        probe.runtime?.cancelRenderLifecycleTasks()
        owner.runtime = nil
        target.onFocusEnter = nil
    }
}
