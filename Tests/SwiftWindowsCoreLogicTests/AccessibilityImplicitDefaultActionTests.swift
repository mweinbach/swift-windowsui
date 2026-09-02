import Foundation
import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Public projected defaults, not the provider's already-live fallback route.
@MainActor
final class AccessibilityImplicitDefaultActionTests: XCTestCase {
    func testPublicButtonImplicitDefaultUsesTheCurrentHandlerAcrossAcceptedReconciliation() async throws {
        var generation = 1
        var calls: [Int] = []
        let host = MountedOnChangeTestHost {
            let capturedGeneration = generation
            return AnyView(Button("Apply") { calls.append(capturedGeneration) })
        }
        defer { host.close() }
        host.render()
        let node = try implicitButton(named: "Apply", in: host)
        let cached = try implicitElement(for: node, in: host.runtime)
        let escapedOriginalActivation = try XCTUnwrap(node.onActivate)
        XCTAssertTrue(node.accessibilityActions.isEmpty)
        XCTAssertTrue(cached.actions.isEmpty)
        XCTAssertTrue(cached.invokeDefaultAction())
        host.render()
        XCTAssertEqual(calls, [1])
        XCTAssertTrue(try implicitButton(named: "Apply", in: host) === node)

        generation = 2
        host.reload()
        host.render()
        XCTAssertTrue(try implicitButton(named: "Apply", in: host) === node)
        XCTAssertTrue(cached.invokeDefaultAction())
        host.render()
        XCTAssertEqual(calls, [1, 2])
        let fresh = try implicitElement(for: node, in: host.runtime)
        XCTAssertTrue(fresh.actions.isEmpty)
        XCTAssertTrue(fresh.invokeDefaultAction())
        host.render()
        XCTAssertEqual(calls, [1, 2, 2])
        XCTAssertTrue(try implicitButton(named: "Apply", in: host) === node)

        // The escaped wrapper returns Void: retirement is proved by no effect.
        escapedOriginalActivation()
        XCTAssertEqual(calls, [1, 2, 2])
    }

    func testMultiDatePickerPublicDefaultsSurviveAcceptedMonthAndDayReconciliation() async throws {
        let february = DateComponents(year: 2024, month: 2, day: 15)
        let march = DateComponents(year: 2024, month: 3, day: 20)
        let selection = MultiDatePickerTestSelection([february])
        var clockReads = 0
        let host = multiDatePickerHost {
            multiDatePickerView(
                selection: selection.binding,
                now: {
                    clockReads += 1
                    return multiDatePickerDate(2024, 2, 15)
                })
        }
        defer { host.close() }
        host.render()
        XCTAssertEqual(try multiDatePickerTitle(in: host), "February 2024")
        let nextNode = try multiDatePickerNode(.nextMonth, in: host)
        let next = try implicitElement(for: nextNode, in: host.runtime)
        XCTAssertTrue(next.actions.isEmpty)
        XCTAssertEqual(next.name, "Next month")
        XCTAssertTrue(next.invokeDefaultAction())
        host.render()
        XCTAssertEqual(try multiDatePickerTitle(in: host), "March 2024")
        XCTAssertTrue(try multiDatePickerNode(.nextMonth, in: host) === nextNode)
        XCTAssertTrue(next.invokeDefaultAction())
        host.render()
        XCTAssertEqual(try multiDatePickerTitle(in: host), "April 2024")
        XCTAssertTrue(try multiDatePickerNode(.nextMonth, in: host) === nextNode)
        XCTAssertTrue(selection.writes.isEmpty)
        XCTAssertEqual(selection.value, [february])

        let previousNode = try multiDatePickerNode(.previousMonth, in: host)
        let previous = try implicitElement(for: previousNode, in: host.runtime)
        XCTAssertTrue(previous.invokeDefaultAction())
        host.render()
        XCTAssertEqual(try multiDatePickerTitle(in: host), "March 2024")
        XCTAssertTrue(selection.writes.isEmpty)
        let dayID = MultiDatePickerNodeID.day(multiDatePickerDate(2024, 3, 20))
        let dayNode = try multiDatePickerNode(dayID, in: host)
        let day = try implicitElement(for: dayNode, in: host.runtime)
        XCTAssertEqual(day.name, "Wednesday, March 20, 2024")
        XCTAssertTrue(day.actions.isEmpty)
        XCTAssertFalse(day.isSelected)
        XCTAssertTrue(day.invokeDefaultAction())
        host.render()
        XCTAssertEqual(selection.value, [february, march])
        XCTAssertEqual(selection.writes, [[february, march]])
        XCTAssertTrue(try multiDatePickerNode(dayID, in: host) === dayNode)
        XCTAssertTrue(try implicitElement(for: dayNode, in: host.runtime).isSelected)
        XCTAssertTrue(day.invokeDefaultAction())
        host.render()
        XCTAssertEqual(selection.value, [february])
        XCTAssertEqual(selection.writes, [[february, march], [february]])
        XCTAssertFalse(try implicitElement(for: dayNode, in: host.runtime).isSelected)
        XCTAssertEqual(clockReads, 1)
    }

    func testImplicitDefaultReadsCurrentActivationAndRequiresBothActionListsToStayEmpty() async throws {
        let fixture = ImplicitActionFixture()
        defer { fixture.retire() }
        fixture.settle()
        let cached = try fixture.element()
        XCTAssertTrue(cached.actions.isEmpty)
        XCTAssertTrue(fixture.target.accessibilityActions.isEmpty)
        XCTAssertFalse(cached.invokeDefaultAction())
        var originalCalls = 0
        var currentCalls = 0
        var customCalls = 0
        var defaultCalls = 0
        fixture.target.onActivate = { originalCalls += 1 }
        XCTAssertTrue(cached.invokeDefaultAction())
        XCTAssertEqual(originalCalls, 1)
        // There is no explicit render/invalidation between these assignments
        // and public invocation. Activation is not captured by the projection.
        fixture.target.onActivate = { currentCalls += 1 }
        XCTAssertTrue(cached.invokeDefaultAction())
        XCTAssertEqual(currentCalls, 1)
        fixture.target.onActivate = nil
        XCTAssertFalse(cached.invokeDefaultAction())
        XCTAssertEqual(currentCalls, 1)
        fixture.target.onActivate = { currentCalls += 1 }
        XCTAssertTrue(cached.invokeDefaultAction())
        XCTAssertEqual(currentCalls, 2)

        fixture.target.accessibilityActions = [
            RetainedAccessibilityAction(name: "Custom") { customCalls += 1 }
        ]
        XCTAssertFalse(cached.invokeDefaultAction())
        XCTAssertEqual(customCalls, 0)
        XCTAssertEqual(currentCalls, 2)
        let firstOnly = try fixture.element()
        XCTAssertTrue(firstOnly.invokeDefaultAction())
        XCTAssertEqual(customCalls, 1)
        fixture.target.accessibilityActions = []
        XCTAssertFalse(firstOnly.invokeDefaultAction())
        XCTAssertTrue(cached.invokeDefaultAction())
        XCTAssertEqual(currentCalls, 3)

        for installDuringLayout in [false, true] {
            let beforeImplicit = currentCalls
            let beforeDefault = defaultCalls
            let explicit = [
                RetainedAccessibilityAction(name: "Custom") { customCalls += 1 },
                RetainedAccessibilityAction(kind: .default) { defaultCalls += 1 },
            ]
            var layoutCallbacks = 0
            if installDuringLayout {
                fixture.runtime.scheduleAfterLayout(key: "install-implicit-test-explicit-list") {
                    [weak target = fixture.target] in
                    layoutCallbacks += 1
                    target?.accessibilityActions = explicit
                }
            } else {
                fixture.target.accessibilityActions = explicit
            }
            // This must check the raw current list after the one layout query.
            XCTAssertFalse(cached.invokeDefaultAction())
            XCTAssertEqual(layoutCallbacks, installDuringLayout ? 1 : 0)
            XCTAssertEqual(fixture.target.accessibilityActions.count, 2)
            XCTAssertEqual(currentCalls, beforeImplicit)
            XCTAssertEqual(defaultCalls, beforeDefault)
            XCTAssertEqual(customCalls, 1)
            let stored = try fixture.element()
            XCTAssertEqual(stored.actions.count, 2)
            XCTAssertTrue(stored.invokeDefaultAction())
            XCTAssertEqual(defaultCalls, beforeDefault + 1)
            XCTAssertEqual(customCalls, 1)
            XCTAssertEqual(currentCalls, beforeImplicit)
            // The explicit positive has settled any earlier paint change.
            // The old empty snapshot still cannot invoke that new list.
            XCTAssertFalse(cached.invokeDefaultAction())
            XCTAssertEqual(defaultCalls, beforeDefault + 1)
            XCTAssertEqual(customCalls, 1)
            XCTAssertEqual(currentCalls, beforeImplicit)

            fixture.target.accessibilityActions = [
                explicit[0],
                RetainedAccessibilityAction(name: "Renamed", kind: .default) { defaultCalls += 1 },
            ]
            XCTAssertFalse(stored.invokeDefaultAction())
            fixture.target.accessibilityActions = [
                explicit[0], RetainedAccessibilityAction(kind: .escape) { defaultCalls += 1 },
            ]
            XCTAssertFalse(stored.invokeDefaultAction())
            fixture.target.accessibilityActions =
                explicit + [
                    RetainedAccessibilityAction(name: "Extra") { customCalls += 1 }
                ]
            XCTAssertFalse(stored.invokeDefaultAction())
            fixture.target.accessibilityActions = []
            XCTAssertFalse(stored.invokeDefaultAction())
            XCTAssertEqual(defaultCalls, beforeDefault + 1)
            XCTAssertEqual(customCalls, 1)
            XCTAssertEqual(currentCalls, beforeImplicit)
            // Emptiness is a current-state check, not a historical revocation.
            XCTAssertTrue(cached.invokeDefaultAction())
            XCTAssertEqual(currentCalls, beforeImplicit + 1)
        }
        XCTAssertEqual(originalCalls, 1)
        XCTAssertEqual(defaultCalls, 2)
        XCTAssertEqual(customCalls, 1)
        XCTAssertEqual(currentCalls, 5)
    }

    func testImplicitDefaultRejectsDisabledHiddenModalRemovedAndReplacedSources() async throws {
        for rejection in ImplicitActionRejection.allCases {
            var generation = 0
            var calls = 0
            let host = MountedOnChangeTestHost {
                AnyView(
                    Button("Action") { calls += 1 }
                        .accessibilityIdentifier("same-public-identifier")
                        .id(generation))
            }
            defer { host.close() }
            host.render()
            let target = try implicitButton(named: "Action", in: host)
            let cached = try implicitElement(for: target, in: host.runtime)
            XCTAssertTrue(cached.actions.isEmpty, "\(rejection)")
            XCTAssertTrue(cached.invokeDefaultAction(), "\(rejection)")
            host.render()
            XCTAssertEqual(calls, 1, "\(rejection)")
            XCTAssertTrue(try implicitButton(named: "Action", in: host) === target)
            let ancestor = try XCTUnwrap(target.parent)
            let escaped = try XCTUnwrap(target.onActivate)
            var modal: ViewNode?
            var disabledSnapshot: AccessibilityElementProjection?

            switch rejection {
            case .ownDisabled:
                target.accessibilityRespondsToUserInteraction = false
                disabledSnapshot = try implicitElement(for: target, in: host.runtime)
            case .ancestorDisabled:
                ancestor.accessibilityRespondsToUserInteraction = false
                disabledSnapshot = try implicitElement(for: target, in: host.runtime)
            case .ownHidden:
                target.isHidden = true
            case .ancestorHidden:
                ancestor.isHidden = true
            case .ownAccessibilityHidden:
                target.isAccessibilityHidden = true
            case .ancestorAccessibilityHidden:
                ancestor.isAccessibilityHidden = true
            case .competingModal, .structuralModalAncestor:
                let presented = ViewNode(
                    frame: Rect(x: 0, y: 0, width: 40, height: 20),
                    accessibilityLabel: "Presented modal", accessibilityTraits: .isModal)
                modal = presented
                if rejection == .structuralModalAncestor {
                    target.addChild(presented)
                } else {
                    host.runtime.root.addChild(presented)
                }
            case .removed:
                ancestor.removeChild(target)
            case .replaced:
                generation += 1
                host.reload()
                host.render()
                let replacement = try implicitButton(named: "Action", in: host)
                XCTAssertFalse(replacement === target)
                XCTAssertEqual(replacement.accessibilityIdentifier, target.accessibilityIdentifier)
            case .closed:
                host.close()
            }
            XCTAssertFalse(cached.invokeDefaultAction(), "\(rejection)")
            XCTAssertEqual(calls, 1, "\(rejection)")
            if let disabledSnapshot {
                XCTAssertFalse(disabledSnapshot.isEnabled)
                XCTAssertFalse(disabledSnapshot.invokeDefaultAction())
            }
            if rejection == .structuralModalAncestor {
                let structural = try implicitElement(for: target, in: host.runtime)
                XCTAssertTrue(structural.actions.isEmpty)
                XCTAssertFalse(structural.invokeDefaultAction())
                XCTAssertEqual(calls, 1)
            }
            if rejection == .removed || rejection == .replaced || rejection == .closed {
                // These are retired physical owners, not merely hidden ones.
                // Their escaped Void wrappers cannot report acceptance.
                escaped()
                XCTAssertEqual(calls, 1, "\(rejection)")
            }

            target.accessibilityRespondsToUserInteraction = nil
            ancestor.accessibilityRespondsToUserInteraction = nil
            target.isHidden = false
            ancestor.isHidden = false
            target.isAccessibilityHidden = false
            ancestor.isAccessibilityHidden = false
            if let modal { modal.parent?.removeChild(modal) }
            if rejection == .removed {
                // A new declaration is accepted; never reattach a retired node.
                generation += 1
                host.reload()
            }
            if rejection == .closed {
                let replacementHost = MountedOnChangeTestHost {
                    AnyView(
                        Button("Action") { calls += 1 }
                            .accessibilityIdentifier("same-public-identifier"))
                }
                defer { replacementHost.close() }
                replacementHost.render()
                let replacement = try implicitButton(named: "Action", in: replacementHost)
                let fresh = try implicitElement(for: replacement, in: replacementHost.runtime)
                XCTAssertTrue(fresh.invokeDefaultAction())
                XCTAssertEqual(calls, 2)
                XCTAssertFalse(cached.invokeDefaultAction())
            } else {
                host.render()
                if let disabledSnapshot {
                    XCTAssertFalse(disabledSnapshot.invokeDefaultAction())
                    XCTAssertEqual(calls, 1)
                }
                let current = try implicitButton(named: "Action", in: host)
                let fresh = try implicitElement(for: current, in: host.runtime)
                XCTAssertTrue(fresh.invokeDefaultAction(), "\(rejection)")
                XCTAssertEqual(calls, 2, "\(rejection)")
                if rejection == .removed || rejection == .replaced {
                    XCTAssertFalse(current === target)
                    XCTAssertFalse(cached.invokeDefaultAction())
                    XCTAssertEqual(calls, 2)
                }
            }
        }
    }

    func testImplicitDefaultPinsRuntimeThroughLayoutAndHandlerButNotBetweenCalls() async throws {
        for drop in ImplicitLifetimeDrop.allCases {
            let fixture = try ImplicitLifetimeFixture(drop: drop)
            defer { fixture.retire() }
            XCTAssertNotNil(fixture.probe.runtime)
            XCTAssertTrue(fixture.target.accessibilityActions.isEmpty)
            XCTAssertTrue(fixture.element.actions.isEmpty)
            if drop == .handler {
                // Separate projection/scope: later refusal proves revocation,
                // rather than merely the primary scope's reentry guard.
                XCTAssertTrue(fixture.secondaryElement.invokeDefaultAction())
                XCTAssertEqual(fixture.probe.secondaryCalls, 1)
                fixture.probe.secondaryCalls = 0
            }
            XCTAssertTrue(fixture.element.invokeDefaultAction())
            XCTAssertEqual(fixture.probe.calls, 1)
            XCTAssertEqual(fixture.probe.layoutCallbacks, drop == .layout ? 1 : 0)
            XCTAssertEqual(fixture.probe.aliveInHandler, [true])
            if drop == .handler {
                XCTAssertEqual(fixture.probe.aliveAfterOwnerDrop, [true])
                XCTAssertEqual(fixture.probe.nestedResults, [false])
                XCTAssertEqual(fixture.probe.aliveAfterNestedAction, [true])
            }
            XCTAssertEqual(fixture.probe.secondaryCalls, 0)
            XCTAssertNil(fixture.owner.runtime)
            XCTAssertNil(fixture.probe.runtime)
            XCTAssertFalse(fixture.element.invokeDefaultAction())
            XCTAssertFalse(fixture.secondaryElement.invokeDefaultAction())
            XCTAssertEqual(fixture.probe.calls, 1)
            XCTAssertEqual(fixture.probe.secondaryCalls, 0)
            // Both exact nodes/root remain alive, excluding a dead-node-only
            // explanation for refusal after the runtime's final owner is gone.
            withExtendedLifetime((fixture.root, fixture.target, fixture.secondary)) {}
        }
    }

    func testImplicitDefaultUsesOneLayoutQueryAndRejectsSameScopeReentry() async throws {
        do {
            let fixture = ImplicitActionFixture()
            defer { fixture.retire() }
            var calls = 0
            var firstCallbacks = 0
            var secondCallbacks = 0
            fixture.target.onActivate = { calls += 1 }
            fixture.settle()
            let cached = try fixture.element()
            fixture.runtime.scheduleAfterLayout(key: "implicit-first-callback") { [weak runtime = fixture.runtime] in
                firstCallbacks += 1
                runtime?.scheduleAfterLayout(key: "implicit-second-callback") { secondCallbacks += 1 }
            }
            XCTAssertFalse(cached.invokeDefaultAction())
            XCTAssertEqual(firstCallbacks, 1)
            XCTAssertEqual(secondCallbacks, 0)
            XCTAssertEqual(calls, 0)
            XCTAssertTrue(cached.invokeDefaultAction())
            XCTAssertEqual(firstCallbacks, 1)
            XCTAssertEqual(secondCallbacks, 1)
            XCTAssertEqual(calls, 1)
        }
        do {
            let fixture = ImplicitActionFixture()
            defer { fixture.retire() }
            var calls = 0
            var layoutCallbacks = 0
            var nestedResults: [Bool] = []
            var isAttemptingNestedInvocation = false
            fixture.target.onActivate = { calls += 1 }
            fixture.settle()
            let cached = try fixture.element()
            fixture.runtime.scheduleAfterLayout(key: "implicit-layout-reentry") { [weak cached] in
                layoutCallbacks += 1
                guard !isAttemptingNestedInvocation else { return }
                isAttemptingNestedInvocation = true
                defer { isAttemptingNestedInvocation = false }
                nestedResults.append(cached?.invokeDefaultAction() ?? false)
            }
            XCTAssertTrue(cached.invokeDefaultAction())
            XCTAssertEqual(layoutCallbacks, 1)
            XCTAssertEqual(nestedResults, [false])
            XCTAssertEqual(calls, 1)
            XCTAssertTrue(cached.invokeDefaultAction())
            XCTAssertEqual(calls, 2)
            withExtendedLifetime(cached) {}
        }
        do {
            let fixture = ImplicitActionFixture()
            defer { fixture.retire() }
            var calls = 0
            var afterActionCallbacks = 0
            var nestedResults: [Bool] = []
            var isAttemptingNestedInvocation = false
            fixture.settle()
            let cached = try fixture.element()
            fixture.target.onActivate = { [weak cached, weak runtime = fixture.runtime] in
                calls += 1
                // A regressed scope must fail assertions, never overflow.
                guard !isAttemptingNestedInvocation else { return }
                isAttemptingNestedInvocation = true
                defer { isAttemptingNestedInvocation = false }
                nestedResults.append(cached?.invokeDefaultAction() ?? false)
                runtime?.scheduleAfterLayout(key: "implicit-after-action") { afterActionCallbacks += 1 }
            }
            XCTAssertTrue(cached.invokeDefaultAction())
            XCTAssertEqual(calls, 1)
            XCTAssertEqual(nestedResults, [false])
            XCTAssertEqual(afterActionCallbacks, 0)
            fixture.settle()
            XCTAssertEqual(afterActionCallbacks, 1)
            XCTAssertTrue(cached.invokeDefaultAction())
            XCTAssertEqual(calls, 2)
            XCTAssertEqual(nestedResults, [false, false])
            XCTAssertEqual(afterActionCallbacks, 1)
            fixture.settle()
            XCTAssertEqual(afterActionCallbacks, 2)
            withExtendedLifetime(cached) {}
        }
    }

    func testImplicitDefaultKeepsManualAndStandaloneProjectionSemantics() async throws {
        var calls = 0
        let fixture = ImplicitStandaloneFixture { calls += 1 }
        let manual = fixture.manualProjection()
        XCTAssertFalse(manual.invokeDefaultAction())
        XCTAssertEqual(calls, 0)
        var explicitCalls = 0
        let direct = AccessibilityProjectedAction(name: "Explicit", kind: .default, isDefault: true) {
            explicitCalls += 1
        }
        let manualWithExplicit = fixture.manualProjection(actions: [direct], includeSource: false)
        XCTAssertNil(manualWithExplicit.sourceNode)
        XCTAssertTrue(manualWithExplicit.invokeDefaultAction())
        XCTAssertEqual(explicitCalls, 1)
        direct.invoke()
        XCTAssertEqual(explicitCalls, 2)
        let cached = try fixture.element()
        XCTAssertTrue(cached.actions.isEmpty)
        XCTAssertTrue(cached.invokeDefaultAction())
        XCTAssertEqual(calls, 1)
        fixture.target?.isHidden = true
        XCTAssertFalse(cached.invokeDefaultAction())
        fixture.target?.isHidden = false
        XCTAssertTrue(cached.invokeDefaultAction())
        XCTAssertEqual(calls, 2)
        fixture.removeTarget()
        XCTAssertFalse(cached.invokeDefaultAction())
        XCTAssertEqual(calls, 2)
        fixture.releaseOwners()
        XCTAssertNil(fixture.weakRoot)
        XCTAssertNil(fixture.weakTarget)
        XCTAssertNil(manual.sourceNode)
        XCTAssertNil(cached.sourceNode)
        XCTAssertFalse(manual.invokeDefaultAction())
        XCTAssertFalse(cached.invokeDefaultAction())
        XCTAssertEqual(calls, 2)
        XCTAssertTrue(manualWithExplicit.invokeDefaultAction())
        XCTAssertEqual(explicitCalls, 3)
        withExtendedLifetime((manual, manualWithExplicit, direct, cached)) {}
    }

    func testVirtualizedImplicitDefaultValidatesCurrentPlaceholderIdentity() async throws {
        let root = ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 120))
        let row = ViewNode(
            frame: Rect(x: 0, y: 140, width: 160, height: 24),
            accessibilityLabel: "Deferred row", accessibilityTraits: .isButton)
        row.accessibilityIdentifier = "same-deferred-row"
        row.isLayoutDeferredByVirtualization = true
        row.addChild(ViewNode(accessibilityLabel: "Unlaid-out descendant"))
        var calls = 0
        row.onActivate = { calls += 1 }
        root.addChild(row)
        let cached = try XCTUnwrap(AccessibilityProjection.project(root: root)?.children.first)
        XCTAssertTrue(cached.isVirtualizedPlaceholder)
        XCTAssertTrue(cached.children.isEmpty)
        XCTAssertTrue(cached.actions.isEmpty)
        XCTAssertTrue(cached.sourceNode === row)
        XCTAssertTrue(cached.invokeDefaultAction())
        XCTAssertEqual(calls, 1)
        root.accessibilityRespondsToUserInteraction = false
        XCTAssertFalse(cached.invokeDefaultAction())
        root.accessibilityRespondsToUserInteraction = true
        let modal = ViewNode(accessibilityLabel: "Modal", accessibilityTraits: .isModal)
        root.addChild(modal)
        XCTAssertFalse(cached.invokeDefaultAction())
        root.removeChild(modal)
        row.isHidden = true
        XCTAssertFalse(cached.invokeDefaultAction())
        row.isHidden = false
        root.removeChild(row)
        XCTAssertFalse(cached.invokeDefaultAction())
        let replacement = ViewNode(
            frame: row.frame, accessibilityLabel: "Deferred row", accessibilityTraits: .isButton)
        replacement.accessibilityIdentifier = row.accessibilityIdentifier
        replacement.isLayoutDeferredByVirtualization = true
        var replacementCalls = 0
        replacement.onActivate = { replacementCalls += 1 }
        root.addChild(replacement)
        XCTAssertFalse(cached.invokeDefaultAction())
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(replacementCalls, 0)
        let fresh = try XCTUnwrap(AccessibilityProjection.project(root: root)?.children.first)
        XCTAssertTrue(fresh.sourceNode === replacement)
        XCTAssertTrue(fresh.isVirtualizedPlaceholder)
        XCTAssertTrue(fresh.children.isEmpty)
        XCTAssertTrue(fresh.actions.isEmpty)
        XCTAssertTrue(fresh.invokeDefaultAction())
        XCTAssertEqual(replacementCalls, 1)
        XCTAssertEqual(calls, 1)
        withExtendedLifetime((root, row)) {}
    }

    func testVirtualizedImplicitDefaultRejectsActiveModalDescendantsWithoutRealizingTheRow() async throws {
        for hasExplicitAction in [false, true] {
            var activationCalls = 0
            var explicitCalls = 0
            var rowLayouts = 0
            var descendantLayouts = 0
            let descendant = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 20), accessibilityLabel: "Nested modal")
            descendant.onLayout = { _ in descendantLayouts += 1 }
            let rows = (0..<5).map { index in
                ViewNode(
                    frame: Rect(x: 0, y: 0, width: 120, height: 40),
                    preferredSize: Size(width: 120, height: 40), accessibilityLabel: "Row \(index)")
            }
            let row = rows[4]
            row.accessibilityTraits = .isButton
            row.onActivate = { activationCalls += 1 }
            row.onLayout = { _ in rowLayouts += 1 }
            row.addChild(descendant)
            if hasExplicitAction {
                row.accessibilityActions = [
                    RetainedAccessibilityAction(name: "Explicit row action", kind: .default) { explicitCalls += 1 }
                ]
            }
            let stack = ViewNode(
                frame: Rect(x: 0, y: 0, width: 120, height: 200),
                layoutMode: .lazyStack(.vertical(spacing: 0)), children: rows)
            let scroll = ViewNode(
                frame: Rect(x: 0, y: 0, width: 120, height: 40), clipsToBounds: false,
                scrollAxis: .vertical, children: [stack])
            let root = ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 240), children: [scroll])
            let runtime = RetainedViewRuntime(root: root)
            _ = runtime.renderScene()

            // Public scroll/lazy configuration creates the deferred row. With
            // clipping disabled, prepaint still reaches its modal descendant.
            XCTAssertFalse(scroll.clipsToBounds)
            XCTAssertTrue(stack.virtualizationScrollAncestor === scroll)
            XCTAssertEqual(stack.layoutVirtualizationWindow(), Rect(x: 0, y: 0, width: 120, height: 40))
            XCTAssertEqual(row.resolvedFrame, Rect(x: 0, y: 160, width: 120, height: 40))
            XCTAssertTrue(row.isLayoutDeferredByVirtualization)
            XCTAssertGreaterThan(runtime.virtualizedLayoutSkipCount, 0)
            XCTAssertEqual(rowLayouts, 0)
            XCTAssertEqual(descendantLayouts, 0)
            XCTAssertNil(runtime.activeModalPresentationNode)
            let cached = try implicitElement(for: row, in: runtime)
            XCTAssertTrue(cached.isVirtualizedPlaceholder)
            XCTAssertTrue(cached.children.isEmpty)
            XCTAssertTrue(cached.permitsModalActions)
            XCTAssertEqual(cached.actions.count, hasExplicitAction ? 1 : 0)
            XCTAssertTrue(cached.invokeDefaultAction(), "explicit list: \(hasExplicitAction)")
            XCTAssertEqual(activationCalls, hasExplicitAction ? 0 : 1)
            XCTAssertEqual(explicitCalls, hasExplicitAction ? 1 : 0)

            descendant.accessibilityTraits = .isModal
            _ = runtime.renderScene()
            XCTAssertTrue(runtime.activeModalPresentationNode === descendant)
            XCTAssertTrue(row.isLayoutDeferredByVirtualization)
            XCTAssertEqual(rowLayouts, 0)
            XCTAssertEqual(descendantLayouts, 0)
            XCTAssertFalse(cached.invokeDefaultAction(), "explicit list: \(hasExplicitAction)")
            let structural = try implicitElement(for: row, in: runtime)
            XCTAssertTrue(structural.sourceNode === row)
            XCTAssertTrue(structural.isVirtualizedPlaceholder)
            XCTAssertTrue(structural.children.isEmpty)
            XCTAssertTrue(structural.isEnabled)
            XCTAssertFalse(structural.permitsModalActions)
            XCTAssertTrue(structural.actions.isEmpty)
            XCTAssertFalse(structural.invokeDefaultAction(), "explicit list: \(hasExplicitAction)")
            XCTAssertFalse(AccessibilityProjection.invokeDefaultAction(on: row, in: runtime))
            XCTAssertEqual(activationCalls, hasExplicitAction ? 0 : 1)
            XCTAssertEqual(explicitCalls, hasExplicitAction ? 1 : 0)

            // A row inside the active modal remains eligible. Only the
            // structural snapshot keeps its saved refusal after dismissal.
            descendant.accessibilityTraits = []
            root.accessibilityTraits = .isModal
            _ = runtime.renderScene()
            XCTAssertTrue(runtime.activeModalPresentationNode === root)
            XCTAssertTrue(row.isLayoutDeferredByVirtualization)
            XCTAssertTrue(cached.invokeDefaultAction(), "explicit list: \(hasExplicitAction)")
            XCTAssertEqual(activationCalls, hasExplicitAction ? 0 : 2)
            XCTAssertEqual(explicitCalls, hasExplicitAction ? 2 : 0)
            XCTAssertFalse(structural.invokeDefaultAction())
            XCTAssertEqual(activationCalls, hasExplicitAction ? 0 : 2)
            XCTAssertEqual(explicitCalls, hasExplicitAction ? 2 : 0)
            let inside = try implicitElement(for: row, in: runtime)
            XCTAssertTrue(inside.sourceNode === row)
            XCTAssertTrue(inside.isVirtualizedPlaceholder)
            XCTAssertTrue(inside.children.isEmpty)
            XCTAssertTrue(inside.permitsModalActions)
            XCTAssertEqual(inside.actions.count, hasExplicitAction ? 1 : 0)
            XCTAssertTrue(inside.invokeDefaultAction(), "explicit list: \(hasExplicitAction)")
            XCTAssertEqual(activationCalls, hasExplicitAction ? 0 : 3)
            XCTAssertEqual(explicitCalls, hasExplicitAction ? 3 : 0)
            XCTAssertTrue(AccessibilityProjection.invokeDefaultAction(on: row, in: runtime))
            XCTAssertEqual(activationCalls, hasExplicitAction ? 0 : 4)
            XCTAssertEqual(explicitCalls, hasExplicitAction ? 4 : 0)
            XCTAssertTrue(row.isLayoutDeferredByVirtualization)
            XCTAssertEqual(rowLayouts, 0)
            XCTAssertEqual(descendantLayouts, 0)
            withExtendedLifetime((runtime, root, scroll, stack, rows, descendant)) {}
        }
    }
}

@MainActor
private func implicitElement(for node: ViewNode, in runtime: RetainedViewRuntime) throws
    -> AccessibilityElementProjection
{
    try XCTUnwrap(AccessibilityProjection.project(runtime: runtime)?.flattened().first { $0.sourceNode === node })
}

@MainActor
private func implicitButton(named name: String, in host: MountedOnChangeTestHost) throws -> ViewNode {
    let element = try XCTUnwrap(
        AccessibilityProjection.project(runtime: host.runtime)?.flattened().first {
            $0.controlType == .button && $0.name == name
        })
    return try XCTUnwrap(element.sourceNode)
}

private enum ImplicitActionRejection: CaseIterable {
    case ownDisabled, ancestorDisabled, ownHidden, ancestorHidden
    case ownAccessibilityHidden, ancestorAccessibilityHidden
    case competingModal, structuralModalAncestor, removed, replaced, closed
}

@MainActor
private final class ImplicitActionFixture {
    let root: ViewNode
    let target: ViewNode
    let runtime: RetainedViewRuntime

    init() {
        let target = ViewNode(
            frame: Rect(x: 10, y: 10, width: 100, height: 30),
            accessibilityLabel: "Target", accessibilityTraits: .isButton)
        let root = ViewNode(frame: Rect(x: 0, y: 0, width: 240, height: 160), children: [target])
        self.root = root
        self.target = target
        runtime = RetainedViewRuntime(root: root)
    }

    func settle() { _ = runtime.resolvedLayoutFrame(of: root) }
    func element() throws -> AccessibilityElementProjection { try implicitElement(for: target, in: runtime) }

    func retire() {
        runtime.stopRenderLifecycleCallbacks()
        runtime.cancelRenderLifecycleTasks()
        target.accessibilityActions = []
        target.onActivate = nil
        root.removeAllChildren()
    }
}

private enum ImplicitLifetimeDrop: CaseIterable {
    case layout, handler
}

@MainActor
private final class ImplicitRuntimeOwner {
    var runtime: RetainedViewRuntime?
    init(_ runtime: RetainedViewRuntime) { self.runtime = runtime }
}

@MainActor
private final class ImplicitRuntimeProbe {
    weak var runtime: RetainedViewRuntime?
    var calls = 0
    var secondaryCalls = 0
    var layoutCallbacks = 0
    var aliveInHandler: [Bool] = []
    var aliveAfterOwnerDrop: [Bool] = []
    var aliveAfterNestedAction: [Bool] = []
    var nestedResults: [Bool] = []
    init(_ runtime: RetainedViewRuntime) { self.runtime = runtime }
}

@MainActor
private final class ImplicitLifetimeFixture {
    let owner: ImplicitRuntimeOwner
    let probe: ImplicitRuntimeProbe
    let root: ViewNode
    let target: ViewNode
    let secondary: ViewNode
    let element: AccessibilityElementProjection
    let secondaryElement: AccessibilityElementProjection

    init(drop: ImplicitLifetimeDrop) throws {
        let target = ViewNode(
            frame: Rect(x: 10, y: 10, width: 100, height: 30),
            accessibilityLabel: "Primary", accessibilityTraits: .isButton)
        let secondary = ViewNode(
            frame: Rect(x: 10, y: 50, width: 100, height: 30),
            accessibilityLabel: "Secondary", accessibilityTraits: .isButton)
        let root = ViewNode(frame: Rect(x: 0, y: 0, width: 240, height: 160), children: [target, secondary])
        let runtime = RetainedViewRuntime(root: root)
        let owner = ImplicitRuntimeOwner(runtime)
        let probe = ImplicitRuntimeProbe(runtime)
        secondary.onActivate = { probe.secondaryCalls += 1 }
        XCTAssertNotNil(runtime.resolvedLayoutFrame(of: root))
        let secondaryElement = try implicitElement(for: secondary, in: runtime)
        target.onActivate = { [weak owner] in
            probe.calls += 1
            probe.aliveInHandler.append(probe.runtime != nil)
            if drop == .handler {
                owner?.runtime = nil
                probe.aliveAfterOwnerDrop.append(probe.runtime != nil)
                probe.runtime?.stopRenderLifecycleCallbacks()
                probe.nestedResults.append(secondaryElement.invokeDefaultAction())
                probe.aliveAfterNestedAction.append(probe.runtime != nil)
            }
        }
        let element = try implicitElement(for: target, in: runtime)
        if drop == .layout {
            runtime.scheduleAfterLayout(key: "implicit-drop-runtime-owner") { [weak owner, weak probe] in
                probe?.layoutCallbacks += 1
                owner?.runtime = nil
            }
        }
        self.owner = owner
        self.probe = probe
        self.root = root
        self.target = target
        self.secondary = secondary
        self.element = element
        self.secondaryElement = secondaryElement
        // This initializer's local runtime expires before any invocation.
        // Only owner.runtime retains it; every projection scope stays weak.
    }

    func retire() {
        probe.runtime?.stopRenderLifecycleCallbacks()
        probe.runtime?.cancelRenderLifecycleTasks()
        owner.runtime = nil
        target.onActivate = nil
        secondary.onActivate = nil
    }
}

@MainActor
private final class ImplicitStandaloneFixture {
    var root: ViewNode?
    var target: ViewNode?
    weak var weakRoot: ViewNode?
    weak var weakTarget: ViewNode?

    init(action: @escaping () -> Void) {
        let target = ViewNode(
            frame: Rect(x: 10, y: 10, width: 100, height: 30),
            accessibilityLabel: "Standalone", accessibilityTraits: .isButton)
        target.onActivate = action
        let root = ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 120), children: [target])
        self.root = root
        self.target = target
        weakRoot = root
        weakTarget = target
    }

    func element() throws -> AccessibilityElementProjection {
        let root = try XCTUnwrap(root)
        return try XCTUnwrap(AccessibilityProjection.project(root: root)?.children.first)
    }

    func manualProjection(
        actions: [AccessibilityProjectedAction] = [], includeSource: Bool = true
    ) -> AccessibilityElementProjection {
        AccessibilityElementProjection(
            bounds: Rect(x: 10, y: 10, width: 100, height: 30), name: "Manual",
            value: nil, hint: nil, identifier: nil, controlType: .button, traits: .isButton,
            headingLevel: nil, isEnabled: true, isFocused: false, isSelected: false,
            sortPriority: 0, actions: actions, children: [], sourceNode: includeSource ? target : nil)
    }

    func removeTarget() {
        if let root, let target { root.removeChild(target) }
    }

    func releaseOwners() {
        root = nil
        target = nil
    }
}
