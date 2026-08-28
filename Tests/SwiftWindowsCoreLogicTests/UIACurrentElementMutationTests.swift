import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Retained source tests only: no HWND, COM provider, or native UI is created.
@MainActor
final class UIACurrentElementMutationTests: XCTestCase {
    func testOrdinaryIntentsUseOneCurrentHandlerWithoutFallback() async throws {
        for route in CurrentElementMutationRoute.allCases {
            for usesExplicitAction in [false, true] {
                let fixture = CurrentElementMutationFixture(traits: route.initialTraits)
                defer { fixture.retire() }
                var explicitCalls = 0
                var fallbackCalls = 0
                var layoutCallbacks = 0
                fixture.target.onActivate = { fallbackCalls += 1 }
                if usesExplicitAction {
                    fixture.target.accessibilityActions = [
                        RetainedAccessibilityAction(kind: .default) { explicitCalls += 1 }
                    ]
                }
                let id = try fixture.targetID()
                fixture.runtime.scheduleAfterLayout(key: "ordinary-intent") { layoutCallbacks += 1 }

                XCTAssertTrue(route.invoke(source: fixture.source, id: id))
                XCTAssertEqual(layoutCallbacks, 1)
                XCTAssertEqual(explicitCalls, usesExplicitAction ? 1 : 0)
                XCTAssertEqual(fallbackCalls, usesExplicitAction ? 0 : 1)
            }
        }
    }

    func testToggleRejectsRoleChangedToButtonDuringLayout() async throws {
        let fixture = CurrentElementMutationFixture(traits: .isToggle)
        defer { fixture.retire() }
        var oldCalls = 0
        var newCalls = 0
        var fallbackCalls = 0
        var layoutCallbacks = 0
        fixture.target.accessibilityActions = [
            RetainedAccessibilityAction(kind: .default) { oldCalls += 1 }
        ]
        fixture.target.onActivate = { fallbackCalls += 1 }
        let id = try fixture.targetID()
        fixture.runtime.scheduleAfterLayout(key: "change-toggle-role") { [weak target = fixture.target] in
            layoutCallbacks += 1
            target?.accessibilityTraits = .isButton
            target?.accessibilityActions = [
                RetainedAccessibilityAction(kind: .default) { newCalls += 1 }
            ]
        }

        XCTAssertFalse(fixture.source.uiaToggle(elementID: id))
        XCTAssertEqual(layoutCallbacks, 1)
        XCTAssertEqual(fixture.target.accessibilityTraits, .isButton)
        XCTAssertEqual(oldCalls, 0)
        XCTAssertEqual(newCalls, 0)
        XCTAssertEqual(fallbackCalls, 0)
        XCTAssertTrue(fixture.source.uiaInvokeDefaultAction(elementID: id))
        XCTAssertEqual(newCalls, 1)
        XCTAssertEqual(fallbackCalls, 0)
    }

    func testToggleAcceptsCurrentCheckboxRoleEstablishedDuringLayout() async throws {
        let fixture = CurrentElementMutationFixture(traits: .isButton)
        defer { fixture.retire() }
        var oldCalls = 0
        var newCalls = 0
        var layoutCallbacks = 0
        fixture.target.onActivate = { oldCalls += 1 }
        let id = try fixture.targetID()
        fixture.runtime.scheduleAfterLayout(key: "become-checkbox") { [weak target = fixture.target] in
            layoutCallbacks += 1
            target?.accessibilityTraits = .isToggle
            target?.onActivate = { newCalls += 1 }
        }

        XCTAssertTrue(fixture.source.uiaToggle(elementID: id))
        XCTAssertEqual(layoutCallbacks, 1)
        XCTAssertEqual(oldCalls, 0)
        XCTAssertEqual(newCalls, 1)
    }

    func testSelectionRejectsCurrentNonselectableRoleIncludingFormerNoOps() async throws {
        for route in CurrentElementMutationRoute.selectionRoutes {
            for initiallySelected in [false, true] {
                let fixture = CurrentElementMutationFixture(traits: .isSelectable)
                defer { fixture.retire() }
                fixture.setSelected(initiallySelected)
                var calls = 0
                var layoutCallbacks = 0
                fixture.target.onActivate = { calls += 1 }
                let id = try fixture.targetID()
                fixture.runtime.scheduleAfterLayout(key: "remove-selection-role") { [weak target = fixture.target] in
                    layoutCallbacks += 1
                    target?.accessibilityTraits = .isButton
                }

                XCTAssertFalse(route.invoke(source: fixture.source, id: id))
                XCTAssertEqual(layoutCallbacks, 1)
                XCTAssertEqual(fixture.target.accessibilityTraits, .isButton)
                XCTAssertEqual(calls, 0)
            }
        }
    }

    func testSelectionTransitionAndNoOpUsePostLayoutSelectedState() async throws {
        for route in CurrentElementMutationRoute.selectionRoutes {
            for initiallySelected in [false, true] {
                let fixture = CurrentElementMutationFixture(traits: .isSelectable)
                defer { fixture.retire() }
                fixture.setSelected(initiallySelected)
                let desiredSelection = route != .removeFromSelection
                let selectionAfterLayout = !initiallySelected
                var calls = 0
                var layoutCallbacks = 0
                fixture.target.onActivate = { [weak fixture] in
                    calls += 1
                    fixture?.setSelected(desiredSelection)
                }
                let id = try fixture.targetID()
                fixture.runtime.scheduleAfterLayout(key: "change-selection") { [weak fixture] in
                    layoutCallbacks += 1
                    fixture?.setSelected(selectionAfterLayout)
                }

                XCTAssertTrue(route.invoke(source: fixture.source, id: id))
                XCTAssertEqual(layoutCallbacks, 1)
                XCTAssertEqual(calls, selectionAfterLayout == desiredSelection ? 0 : 1)
                XCTAssertEqual(fixture.target.accessibilityTraits.contains(.isSelected), desiredSelection)
            }
        }
    }

    func testNewModalDuringLayoutRejectsAllIntentsIncludingSelectionNoOps() async throws {
        for route in CurrentElementMutationRoute.allCases {
            let fixture = CurrentElementMutationFixture(traits: route.initialTraits)
            defer { fixture.retire() }
            if CurrentElementMutationRoute.selectionRoutes.contains(route) {
                fixture.setSelected(route != .removeFromSelection)
            }
            var explicitCalls = 0
            var fallbackCalls = 0
            var layoutCallbacks = 0
            fixture.target.accessibilityActions = [
                RetainedAccessibilityAction(kind: .default) { explicitCalls += 1 }
            ]
            fixture.target.onActivate = { fallbackCalls += 1 }
            let id = try fixture.targetID()
            fixture.runtime.scheduleAfterLayout(key: "present-modal") { [weak fixture] in
                layoutCallbacks += 1
                fixture?.presentModal()
            }

            XCTAssertFalse(route.invoke(source: fixture.source, id: id))
            XCTAssertEqual(layoutCallbacks, 1)
            XCTAssertNotNil(fixture.runtime.activeModalPresentationNode)
            XCTAssertEqual(explicitCalls, 0)
            XCTAssertEqual(fallbackCalls, 0)
        }
    }

    func testRevocationRemovalAndDisablingDuringLayoutRejectAllIntents() async throws {
        for route in CurrentElementMutationRoute.allCases {
            for rejection in CurrentElementMutationRejection.allCases {
                let fixture = CurrentElementMutationFixture(traits: route.initialTraits)
                defer { fixture.retire() }
                var explicitCalls = 0
                var fallbackCalls = 0
                var layoutCallbacks = 0
                fixture.target.accessibilityActions = [
                    RetainedAccessibilityAction(kind: .default) { explicitCalls += 1 }
                ]
                fixture.target.onActivate = { fallbackCalls += 1 }
                let id = try fixture.targetID()
                fixture.runtime.scheduleAfterLayout(key: "revoke-target") { [weak fixture] in
                    layoutCallbacks += 1
                    guard let fixture else { return }
                    switch rejection {
                    case .terminal:
                        fixture.runtime.stopRenderLifecycleCallbacks()
                    case .removed:
                        fixture.root.removeChild(fixture.target)
                    case .disabled:
                        fixture.target.accessibilityRespondsToUserInteraction = false
                    }
                }

                XCTAssertFalse(route.invoke(source: fixture.source, id: id))
                XCTAssertEqual(layoutCallbacks, 1)
                XCTAssertEqual(explicitCalls, 0)
                XCTAssertEqual(fallbackCalls, 0)
            }
        }
    }

    func testPendingSecondLayoutCallbackIsNotDrainedByAnExtraActionQuery() async throws {
        for route in CurrentElementMutationRoute.allCases {
            let fixture = CurrentElementMutationFixture(traits: route.initialTraits)
            defer { fixture.retire() }
            var firstCallbacks = 0
            var secondCallbacks = 0
            var calls = 0
            fixture.target.onActivate = { calls += 1 }
            let id = try fixture.targetID()
            fixture.runtime.scheduleAfterLayout(key: "first-callback") { [weak runtime = fixture.runtime] in
                firstCallbacks += 1
                runtime?.scheduleAfterLayout(key: "second-callback") { secondCallbacks += 1 }
            }

            XCTAssertFalse(route.invoke(source: fixture.source, id: id))
            XCTAssertEqual(firstCallbacks, 1)
            XCTAssertEqual(secondCallbacks, 0)
            XCTAssertEqual(calls, 0)
            XCTAssertTrue(route.invoke(source: fixture.source, id: id))
            XCTAssertEqual(firstCallbacks, 1)
            XCTAssertEqual(secondCallbacks, 1)
            XCTAssertEqual(calls, 1)
        }
    }

    func testLayoutReentryIsRejectedAcrossActionIntents() async throws {
        for route in CurrentElementMutationRoute.allCases {
            let fixture = CurrentElementMutationFixture(traits: [.isToggle, .isSelectable])
            defer { fixture.retire() }
            fixture.setSelected(route == .removeFromSelection)
            var calls = 0
            var layoutCallbacks = 0
            var nestedResults: [Bool] = []
            fixture.target.onActivate = { calls += 1 }
            let id = try fixture.targetID()
            fixture.runtime.scheduleAfterLayout(key: "cross-intent-reentry") { [weak fixture] in
                layoutCallbacks += 1
                guard let fixture else { return }
                for nested in CurrentElementMutationRoute.allCases {
                    nestedResults.append(nested.invoke(source: fixture.source, id: id))
                }
            }

            XCTAssertTrue(route.invoke(source: fixture.source, id: id))
            XCTAssertEqual(layoutCallbacks, 1)
            XCTAssertEqual(nestedResults, Array(repeating: false, count: CurrentElementMutationRoute.allCases.count))
            XCTAssertEqual(calls, 1)
        }
    }

    func testActionReentryIsRejectedAndNoQueryRunsAfterTheAction() async throws {
        for route in CurrentElementMutationRoute.allCases {
            let fixture = CurrentElementMutationFixture(traits: [.isToggle, .isSelectable])
            defer { fixture.retire() }
            fixture.setSelected(route == .removeFromSelection)
            var calls = 0
            var afterActionCallbacks = 0
            var nestedResults: [Bool] = []
            var isAttemptingNestedInvocation = false
            let id = try fixture.targetID()
            fixture.target.onActivate = { [weak fixture] in
                calls += 1
                guard !isAttemptingNestedInvocation, let fixture else { return }
                isAttemptingNestedInvocation = true
                defer { isAttemptingNestedInvocation = false }
                for nested in CurrentElementMutationRoute.allCases {
                    nestedResults.append(nested.invoke(source: fixture.source, id: id))
                }
                fixture.runtime.scheduleAfterLayout(key: "after-action") { afterActionCallbacks += 1 }
            }

            XCTAssertTrue(route.invoke(source: fixture.source, id: id))
            XCTAssertEqual(calls, 1)
            XCTAssertEqual(nestedResults, Array(repeating: false, count: CurrentElementMutationRoute.allCases.count))
            XCTAssertEqual(afterActionCallbacks, 0)
            fixture.settle()
            XCTAssertEqual(afterActionCallbacks, 1)
        }
    }
}

private enum CurrentElementMutationRoute: CaseIterable, Equatable, Sendable {
    case invoke
    case toggle
    case select
    case addToSelection
    case removeFromSelection

    static let selectionRoutes: [Self] = [.select, .addToSelection, .removeFromSelection]

    var initialTraits: RetainedAccessibilityTraits {
        switch self {
        case .invoke: return .isButton
        case .toggle: return .isToggle
        case .select, .addToSelection: return .isSelectable
        case .removeFromSelection: return [.isSelectable, .isSelected]
        }
    }

    @MainActor
    func invoke(source: RuntimeUIAElementTreeSource, id: UInt64) -> Bool {
        switch self {
        case .invoke: return source.uiaInvokeDefaultAction(elementID: id)
        case .toggle: return source.uiaToggle(elementID: id)
        case .select: return source.uiaSelect(elementID: id)
        case .addToSelection: return source.uiaAddToSelection(elementID: id)
        case .removeFromSelection: return source.uiaRemoveFromSelection(elementID: id)
        }
    }
}

private enum CurrentElementMutationRejection: CaseIterable, Sendable {
    case terminal
    case removed
    case disabled
}

@MainActor
private final class CurrentElementMutationFixture {
    let root: ViewNode
    let target: ViewNode
    let runtime: RetainedViewRuntime
    let source: RuntimeUIAElementTreeSource

    init(traits: RetainedAccessibilityTraits) {
        target = ViewNode(
            frame: Rect(x: 20, y: 20, width: 100, height: 30),
            accessibilityLabel: "Mutation target", accessibilityTraits: traits)
        root = ViewNode(frame: Rect(x: 0, y: 0, width: 320, height: 200), children: [target])
        runtime = RetainedViewRuntime(root: root)
        source = RuntimeUIAElementTreeSource(runtime: runtime)
        settle()
    }

    func targetID() throws -> UInt64 {
        try XCTUnwrap(source.uiaElementSnapshots().first { $0.name == "Mutation target" }?.id)
    }

    func setSelected(_ selected: Bool) {
        if selected {
            target.accessibilityTraits.insert(.isSelected)
        } else {
            target.accessibilityTraits.remove(.isSelected)
        }
    }

    func presentModal() {
        let modal = ViewNode(
            frame: Rect(x: 40, y: 40, width: 180, height: 120),
            accessibilityLabel: "Current modal", accessibilityTraits: .isModal)
        modal.paintsInDeferredPhase = true
        root.addChild(modal)
    }

    func settle() {
        XCTAssertNotNil(runtime.resolvedLayoutFrame(of: root))
    }

    func retire() {
        runtime.stopRenderLifecycleCallbacks()
        target.accessibilityActions = []
        target.onActivate = nil
        runtime.cancelRenderLifecycleTasks()
    }
}
