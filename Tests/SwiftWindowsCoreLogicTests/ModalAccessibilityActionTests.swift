import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// These tests exercise retained projections and the live Swift UIA source.
/// They do not create HWNDs, exercise disconnected COM providers, or run Narrator.
@MainActor
final class ModalAccessibilityActionTests: XCTestCase {
    func testModalAncestorsKeepBoundsButLoseStoredAndFallbackActions() async throws {
        let fixture = ModalActionFixture()
        defer { fixture.retire() }
        var blocked = 0
        var accepted = 0
        for node in [fixture.root, fixture.owner] {
            node.accessibilityActions = [
                RetainedAccessibilityAction(kind: .default) { blocked += 1 },
                RetainedAccessibilityAction(name: "Custom") { blocked += 1 },
            ]
            node.onActivate = { blocked += 1 }
        }
        let rootID = UIAProviderBridge.rootElementID
        let ownerID = try fixture.id(named: "Owner")
        let modal = fixture.presentModal()
        modal.action.accessibilityActions = [
            RetainedAccessibilityAction(kind: .default) { accepted += 1 }
        ]
        fixture.settle()

        for projection in [
            AccessibilityProjection.project(runtime: fixture.runtime),
            AccessibilityProjection.project(root: fixture.root),
        ] {
            let root = try XCTUnwrap(projection)
            let owner = try XCTUnwrap(root.flattened().first { $0.sourceNode === fixture.owner })
            let action = try XCTUnwrap(root.flattened().first { $0.sourceNode === modal.action })
            XCTAssertEqual(owner.bounds.origin, Point(x: 20, y: 30))
            XCTAssertEqual(action.bounds.origin, Point(x: 62, y: 85))
            XCTAssertTrue(root.actions.isEmpty)
            XCTAssertTrue(owner.actions.isEmpty)
            XCTAssertFalse(root.invokeDefaultAction())
            XCTAssertFalse(owner.invokeDefaultAction())
        }

        let snapshots = fixture.source.uiaElementSnapshots()
        XCTAssertEqual(snapshots.first { $0.id == rootID }?.hasDefaultAction, false)
        XCTAssertEqual(snapshots.first { $0.id == ownerID }?.hasDefaultAction, false)
        XCTAssertFalse(fixture.source.uiaInvokeDefaultAction(elementID: rootID))
        XCTAssertFalse(fixture.source.uiaInvokeDefaultAction(elementID: ownerID))
        XCTAssertTrue(fixture.source.uiaInvokeDefaultAction(elementID: try fixture.id(named: "Modal action")))
        XCTAssertEqual(blocked, 0)
        XCTAssertEqual(accepted, 1)
    }

    func testCachedDefaultAndOldUIAIDRejectNewModalBeforeAnotherFrame() async throws {
        let fixture = ModalActionFixture()
        defer { fixture.retire() }
        var calls = 0
        fixture.action.accessibilityActions = [
            RetainedAccessibilityAction(kind: .default) { calls += 1 }
        ]
        let cached = try fixture.projection(for: fixture.action)
        let id = try fixture.id(named: "Action")
        _ = fixture.presentModal()

        XCTAssertFalse(cached.invokeDefaultAction())
        XCTAssertFalse(fixture.source.uiaInvokeDefaultAction(elementID: id))
        XCTAssertEqual(calls, 0)
    }

    func testCopiedCustomActionTracksCurrentModalAndResumesAfterDismissal() async throws {
        let fixture = ModalActionFixture()
        defer { fixture.retire() }
        var calls = 0
        fixture.action.accessibilityActions = [
            RetainedAccessibilityAction(name: "Apply") { calls += 1 }
        ]
        let cached = try XCTUnwrap(try fixture.projection(for: fixture.action).actions.first)
        let modal = fixture.presentModal()
        cached.invoke()
        XCTAssertEqual(calls, 0)

        fixture.owner.removeChild(modal.node)
        cached.invoke()
        XCTAssertEqual(calls, 1)
    }

    func testDisabledTargetRejectsCopiedActionsAndBothLiveInvocationRoutes() async throws {
        let fixture = ModalActionFixture()
        defer { fixture.retire() }
        var explicit = 0
        var fallback = 0
        fixture.action.accessibilityActions = [
            RetainedAccessibilityAction(kind: .default) { explicit += 1 }
        ]
        fixture.action.onActivate = { fallback += 1 }
        let cached = try fixture.projection(for: fixture.action)
        let action = try XCTUnwrap(cached.actions.first)
        let id = try fixture.id(named: "Action")
        fixture.action.accessibilityRespondsToUserInteraction = false

        action.invoke()
        XCTAssertFalse(cached.invokeDefaultAction())
        XCTAssertFalse(fixture.source.uiaInvokeDefaultAction(elementID: id))
        fixture.action.accessibilityActions = []
        XCTAssertFalse(fixture.source.uiaInvokeDefaultAction(elementID: id))
        XCTAssertEqual(explicit, 0)
        XCTAssertEqual(fallback, 0)
    }

    func testDisabledTransparentOwnerBlocksItsAttachedDescendant() async throws {
        let fixture = ModalActionFixture()
        defer { fixture.retire() }
        fixture.owner.accessibilityLabel = nil
        var calls = 0
        fixture.action.onActivate = { calls += 1 }
        let id = try fixture.id(named: "Action")
        fixture.owner.accessibilityRespondsToUserInteraction = false

        XCTAssertFalse(fixture.source.uiaInvokeDefaultAction(elementID: id))
        XCTAssertEqual(fixture.source.uiaElementSnapshots().first { $0.id == id }?.isEnabled, false)
        XCTAssertEqual(calls, 0)
        fixture.owner.accessibilityRespondsToUserInteraction = true
        XCTAssertTrue(fixture.source.uiaInvokeDefaultAction(elementID: id))
        XCTAssertEqual(calls, 1)
    }

    func testHiddenAccessibilityAndVisualOwnersRejectCachedActions() async throws {
        let fixture = ModalActionFixture()
        defer { fixture.retire() }
        var calls = 0
        fixture.action.accessibilityActions = [
            RetainedAccessibilityAction(name: "Apply") { calls += 1 }
        ]
        let cached = try fixture.projection(for: fixture.action)
        let id = try fixture.id(named: "Action")
        fixture.owner.isAccessibilityHidden = true
        XCTAssertFalse(cached.invokeDefaultAction())
        XCTAssertFalse(fixture.source.uiaInvokeDefaultAction(elementID: id))

        fixture.owner.isAccessibilityHidden = false
        fixture.owner.isHidden = true
        XCTAssertFalse(cached.invokeDefaultAction())
        XCTAssertFalse(fixture.source.uiaInvokeDefaultAction(elementID: id))
        XCTAssertEqual(calls, 0)
    }

    func testDetachedAndReparentedNodesCannotUseTheirOldRootScope() async throws {
        let fixture = ModalActionFixture()
        defer { fixture.retire() }
        var calls = 0
        fixture.action.accessibilityActions = [
            RetainedAccessibilityAction(kind: .default) { calls += 1 }
        ]
        let cached = try fixture.projection(for: fixture.action)
        let id = try fixture.id(named: "Action")
        fixture.owner.removeChild(fixture.action)
        XCTAssertFalse(cached.invokeDefaultAction())
        XCTAssertFalse(fixture.source.uiaInvokeDefaultAction(elementID: id))

        let replacementRoot = ViewNode(frame: fixture.root.frame, children: [fixture.action])
        let otherRuntime = RetainedViewRuntime(root: replacementRoot)
        XCTAssertFalse(cached.invokeDefaultAction())
        XCTAssertFalse(fixture.source.uiaInvokeDefaultAction(elementID: id))
        XCTAssertEqual(calls, 0)
        withExtendedLifetime((fixture.root, fixture.action, otherRuntime)) {}
    }

    func testReplacingModalDoesNotRetargetCachedElementOrUIAID() async throws {
        let fixture = ModalActionFixture()
        defer { fixture.retire() }
        let old = fixture.presentModal()
        var oldCalls = 0
        var newCalls = 0
        old.action.accessibilityActions = [
            RetainedAccessibilityAction(kind: .default) { oldCalls += 1 }
        ]
        fixture.settle()
        let cached = try fixture.projection(for: old.action)
        let oldID = try fixture.id(named: "Modal action")

        fixture.owner.removeChild(old.node)
        let replacement = fixture.presentModal()
        replacement.action.onActivate = { newCalls += 1 }
        XCTAssertFalse(cached.invokeDefaultAction())
        XCTAssertFalse(fixture.source.uiaInvokeDefaultAction(elementID: oldID))
        fixture.settle()
        let newID = try fixture.id(named: "Modal action")
        XCTAssertNotEqual(oldID, newID)
        XCTAssertTrue(fixture.source.uiaInvokeDefaultAction(elementID: newID))
        XCTAssertEqual(oldCalls, 0)
        XCTAssertEqual(newCalls, 1)
        withExtendedLifetime(old) {}
    }

    func testRepresentationActionUsesCurrentEnabledOwnerAndReplacementRoute() async throws {
        let fixture = ModalActionFixture()
        defer { fixture.retire() }
        let represented = ViewNode(accessibilityLabel: "Represented")
        var calls = 0
        represented.accessibilityActions = [
            RetainedAccessibilityAction(name: "Apply") { calls += 1 }
        ]
        fixture.owner.accessibilityRepresentationChildren = [represented]
        fixture.settle()
        XCTAssertNil(represented.parent)
        let cached = try fixture.projection(for: represented)
        let id = try fixture.id(named: "Represented")

        XCTAssertTrue(cached.invokeDefaultAction())
        XCTAssertTrue(fixture.source.uiaInvokeDefaultAction(elementID: id))
        fixture.owner.accessibilityRespondsToUserInteraction = false
        XCTAssertFalse(cached.invokeDefaultAction())
        XCTAssertFalse(fixture.source.uiaInvokeDefaultAction(elementID: id))
        fixture.owner.accessibilityRespondsToUserInteraction = true
        fixture.owner.accessibilityRepresentationChildren = [ViewNode(accessibilityLabel: "Replacement")]
        XCTAssertFalse(cached.invokeDefaultAction())
        XCTAssertFalse(fixture.source.uiaInvokeDefaultAction(elementID: id))
        XCTAssertEqual(calls, 2)
        withExtendedLifetime(represented) {}
    }

    func testWeakOldElementIDCannotBeRetargetedByBoundedReplacements() async throws {
        let fixture = ModalActionFixture()
        defer { fixture.retire() }
        weak var oldNode: ViewNode?
        let oldIdentity: ObjectIdentifier
        let oldID: UInt64
        do {
            let node = ViewNode(accessibilityLabel: "Retired")
            fixture.owner.addChild(node)
            oldNode = node
            oldIdentity = ObjectIdentifier(node)
            oldID = try XCTUnwrap(fixture.source.projectedElementID(forNodeOrAncestor: node))
            fixture.owner.removeChild(node)
        }
        fixture.settle()
        XCTAssertNil(oldNode)
        var observedAllocationReuse = false
        var calls = 0
        var allocatedIDs = Set<UInt64>([oldID])
        for index in 0..<16 {
            let node = ViewNode(accessibilityLabel: "Replacement \(index)")
            observedAllocationReuse = observedAllocationReuse || ObjectIdentifier(node) == oldIdentity
            node.onActivate = { calls += 1 }
            fixture.owner.addChild(node)
            // The focus-event path deliberately does not prune first. All
            // assertions hold whether or not the allocator reuses an address.
            let id = try XCTUnwrap(fixture.source.projectedElementID(forNodeOrAncestor: node))
            XCTAssertTrue(allocatedIDs.insert(id).inserted)
            XCTAssertFalse(fixture.source.uiaInvokeDefaultAction(elementID: oldID))
            XCTAssertTrue(fixture.source.uiaInvokeDefaultAction(elementID: id))
            XCTAssertEqual(calls, index + 1)
            fixture.owner.removeChild(node)
            fixture.settle()
        }
        print("Modal UIA replacement fixture observed allocation reuse: \(observedAllocationReuse)")
    }

    func testRepresentationInsideModalIsAllowedButItsOwnerAncestorIsNot() async throws {
        let fixture = ModalActionFixture()
        defer { fixture.retire() }
        let modal = fixture.presentModal()
        let represented = ViewNode(accessibilityLabel: "Represented modal action")
        var calls = 0
        represented.onActivate = { calls += 1 }
        modal.action.accessibilityRepresentationChildren = [represented]
        fixture.settle()

        XCTAssertTrue(
            fixture.source.uiaInvokeDefaultAction(
                elementID: try fixture.id(named: "Represented modal action")))
        XCTAssertFalse(fixture.source.uiaInvokeDefaultAction(elementID: UIAProviderBridge.rootElementID))
        XCTAssertEqual(calls, 1)
    }

    func testCopiedActionResolvesLatestMatchingHandlerAndRejectsChangedDescriptor() async throws {
        let fixture = ModalActionFixture()
        defer { fixture.retire() }
        var oldCalls = 0
        var currentCalls = 0
        fixture.action.accessibilityActions = [
            RetainedAccessibilityAction(name: "Apply") { oldCalls += 1 }
        ]
        let cached = try fixture.projection(for: fixture.action)
        fixture.action.accessibilityActions = [
            RetainedAccessibilityAction(name: "Apply") { currentCalls += 1 }
        ]
        XCTAssertTrue(cached.invokeDefaultAction())
        fixture.action.accessibilityActions = [
            RetainedAccessibilityAction(name: "Different") { currentCalls += 1 }
        ]
        XCTAssertFalse(cached.invokeDefaultAction())
        fixture.action.accessibilityActions = []
        XCTAssertFalse(cached.invokeDefaultAction())
        XCTAssertEqual(oldCalls, 0)
        XCTAssertEqual(currentCalls, 1)
    }

    func testCopiedActionRejectsChangedListShapeButLiveDefaultKeepsItsOrder() async throws {
        let fixture = ModalActionFixture()
        defer { fixture.retire() }
        var first = 0
        var second = 0
        fixture.action.accessibilityActions = [
            RetainedAccessibilityAction(name: "Apply") { first += 1 }
        ]
        let cached = try fixture.projection(for: fixture.action)
        let id = try fixture.id(named: "Action")
        fixture.action.accessibilityActions.append(
            RetainedAccessibilityAction(name: "Apply") { second += 1 })
        XCTAssertFalse(cached.invokeDefaultAction())
        XCTAssertTrue(fixture.source.uiaInvokeDefaultAction(elementID: id))
        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 0)
    }

    func testUnchangedDuplicateActionDescriptorsKeepTheirDeclaredSlots() async throws {
        let fixture = ModalActionFixture()
        defer { fixture.retire() }
        var first = 0
        var second = 0
        fixture.action.accessibilityActions = [
            RetainedAccessibilityAction(name: "Apply") { first += 1 },
            RetainedAccessibilityAction(name: "Apply") { second += 1 },
        ]
        let cached = try fixture.projection(for: fixture.action)
        cached.actions[0].invoke()
        cached.actions[1].invoke()
        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 1)
    }

    func testLayoutReplacementSelectsLatestExplicitHandlerWithoutFallback() async throws {
        let fixture = ModalActionFixture()
        defer { fixture.retire() }
        var oldCalls = 0
        var currentCalls = 0
        var fallback = 0
        fixture.action.accessibilityActions = [
            RetainedAccessibilityAction(kind: .default) { oldCalls += 1 }
        ]
        fixture.action.onActivate = { fallback += 1 }
        let id = try fixture.id(named: "Action")
        fixture.runtime.scheduleAfterLayout(key: "replace-action") { [weak fixture] in
            fixture?.action.accessibilityActions = [
                RetainedAccessibilityAction(kind: .default) { currentCalls += 1 }
            ]
        }

        XCTAssertTrue(fixture.source.uiaInvokeDefaultAction(elementID: id))
        XCTAssertEqual(oldCalls, 0)
        XCTAssertEqual(currentCalls, 1)
        XCTAssertEqual(fallback, 0)
    }

    func testLayoutRemovalRejectsBeforeEitherHandlerRuns() async throws {
        let fixture = ModalActionFixture()
        defer { fixture.retire() }
        var calls = 0
        fixture.action.accessibilityActions = [
            RetainedAccessibilityAction(kind: .default) { calls += 1 }
        ]
        fixture.action.onActivate = { calls += 1 }
        let id = try fixture.id(named: "Action")
        fixture.runtime.scheduleAfterLayout(key: "remove-action") { [weak fixture] in
            guard let fixture else { return }
            fixture.owner.removeChild(fixture.action)
        }

        XCTAssertFalse(fixture.source.uiaInvokeDefaultAction(elementID: id))
        XCTAssertEqual(calls, 0)
        XCTAssertNil(fixture.action.parent)
    }

    func testLayoutCallbackThatPresentsModalBlocksOldAction() async throws {
        let fixture = ModalActionFixture()
        defer { fixture.retire() }
        var calls = 0
        var layoutCallbacks = 0
        fixture.action.onActivate = { calls += 1 }
        let id = try fixture.id(named: "Action")
        fixture.runtime.scheduleAfterLayout(key: "present-modal") { [weak fixture] in
            layoutCallbacks += 1
            _ = fixture?.presentModal()
        }

        XCTAssertFalse(fixture.source.uiaInvokeDefaultAction(elementID: id))
        XCTAssertEqual(layoutCallbacks, 1)
        XCTAssertTrue(fixture.owner.children.contains { $0.isModalPresentationScope })
        XCTAssertEqual(calls, 0)
    }

    func testReentrantSourceInvocationDuringLayoutIsRejectedOnce() async throws {
        let fixture = ModalActionFixture()
        defer { fixture.retire() }
        var calls = 0
        var nestedResults: [Bool] = []
        fixture.action.onActivate = { calls += 1 }
        let id = try fixture.id(named: "Action")
        fixture.runtime.scheduleAfterLayout(key: "reenter") { [weak fixture] in
            nestedResults.append(fixture?.source.uiaInvokeDefaultAction(elementID: id) ?? false)
        }

        XCTAssertTrue(fixture.source.uiaInvokeDefaultAction(elementID: id))
        XCTAssertEqual(nestedResults, [false])
        XCTAssertEqual(calls, 1)
    }

    func testReentrantSourceInvocationDuringActionIsRejectedButLaterInvocationWorks() async throws {
        let fixture = ModalActionFixture()
        defer { fixture.retire() }
        let id = try fixture.id(named: "Action")
        var calls = 0
        var nestedResults: [Bool] = []
        var isAttemptingNestedInvocation = false
        fixture.action.onActivate = {
            calls += 1
            // A regressed source guard must fail these assertions, not make
            // the fixture recurse indefinitely and overflow its stack.
            guard !isAttemptingNestedInvocation else { return }
            isAttemptingNestedInvocation = true
            nestedResults.append(fixture.source.uiaInvokeDefaultAction(elementID: id))
            isAttemptingNestedInvocation = false
        }

        XCTAssertTrue(fixture.source.uiaInvokeDefaultAction(elementID: id))
        XCTAssertTrue(fixture.source.uiaInvokeDefaultAction(elementID: id))
        XCTAssertEqual(nestedResults, [false, false])
        XCTAssertEqual(calls, 2)
    }

    func testExplicitActionRemovalDuringInvocationDoesNotRunFallback() async throws {
        let fixture = ModalActionFixture()
        defer { fixture.retire() }
        var explicit = 0
        var fallback = 0
        fixture.action.accessibilityActions = [
            RetainedAccessibilityAction(kind: .default) {
                explicit += 1
                fixture.action.accessibilityActions = []
            }
        ]
        fixture.action.onActivate = { fallback += 1 }
        let id = try fixture.id(named: "Action")

        XCTAssertTrue(fixture.source.uiaInvokeDefaultAction(elementID: id))
        XCTAssertEqual(explicit, 1)
        XCTAssertEqual(fallback, 0)
        XCTAssertTrue(fixture.source.uiaInvokeDefaultAction(elementID: id))
        XCTAssertEqual(fallback, 1)
    }

    func testActionMayDismissOrReplaceModalWithoutASecondInvocation() async throws {
        let fixture = ModalActionFixture()
        defer { fixture.retire() }
        let modal = fixture.presentModal()
        var explicit = 0
        var fallback = 0
        modal.action.accessibilityActions = [
            RetainedAccessibilityAction(kind: .default) {
                explicit += 1
                fixture.owner.removeChild(modal.node)
                _ = fixture.presentModal()
            }
        ]
        modal.action.onActivate = { fallback += 1 }
        fixture.settle()
        let id = try fixture.id(named: "Modal action")

        XCTAssertTrue(fixture.source.uiaInvokeDefaultAction(elementID: id))
        XCTAssertFalse(fixture.source.uiaInvokeDefaultAction(elementID: id))
        XCTAssertEqual(explicit, 1)
        XCTAssertEqual(fallback, 0)
    }

    func testNoLayoutQueryRunsAfterTheSelectedAction() async throws {
        let fixture = ModalActionFixture()
        defer { fixture.retire() }
        var laterCallbacks = 0
        fixture.action.onActivate = {
            fixture.runtime.scheduleAfterLayout(key: "later") { laterCallbacks += 1 }
        }
        let id = try fixture.id(named: "Action")
        XCTAssertTrue(fixture.source.uiaInvokeDefaultAction(elementID: id))
        XCTAssertEqual(laterCallbacks, 0)
        fixture.settle()
        XCTAssertEqual(laterCallbacks, 1)
    }

    func testStoppedRuntimeRemainsInspectableButCannotStartActionLayout() async throws {
        let fixture = ModalActionFixture()
        defer { fixture.retire() }
        var calls = 0
        var layoutCallbacks = 0
        fixture.action.accessibilityActions = [
            RetainedAccessibilityAction(kind: .default) { calls += 1 }
        ]
        fixture.action.onActivate = { calls += 1 }
        let cached = try fixture.projection(for: fixture.action)
        let copied = try XCTUnwrap(cached.actions.first)
        let id = try fixture.id(named: "Action")
        fixture.runtime.stopRenderLifecycleCallbacks()
        fixture.runtime.scheduleAfterLayout(key: "must-not-run") { layoutCallbacks += 1 }

        XCTAssertFalse(fixture.runtime.permitsRetainedActionInvocation)
        XCTAssertFalse(fixture.source.uiaInvokeDefaultAction(elementID: id))
        XCTAssertFalse(cached.invokeDefaultAction())
        copied.invoke()
        XCTAssertNotNil(AccessibilityProjection.project(runtime: fixture.runtime))
        XCTAssertNotNil(fixture.source.uiaElementSnapshots().first { $0.id == id })
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(layoutCallbacks, 0)
    }

    func testStoppingRuntimeDuringActionLayoutRejectsBothRoutes() async throws {
        let fixture = ModalActionFixture()
        defer { fixture.retire() }
        var calls = 0
        var layoutCallbacks = 0
        fixture.action.accessibilityActions = [
            RetainedAccessibilityAction(kind: .default) { calls += 1 }
        ]
        fixture.action.onActivate = { calls += 1 }
        let id = try fixture.id(named: "Action")
        fixture.runtime.scheduleAfterLayout(key: "stop-runtime") { [weak fixture] in
            layoutCallbacks += 1
            fixture?.runtime.stopRenderLifecycleCallbacks()
        }

        XCTAssertFalse(fixture.source.uiaInvokeDefaultAction(elementID: id))
        XCTAssertFalse(fixture.source.uiaInvokeDefaultAction(elementID: id))
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(layoutCallbacks, 1)
    }

    func testRealHostCloseInsideActionConsumesOnlyThatActionAndRejectsLateReferences() async throws {
        let fixture = ModalActionHostFixture()
        defer { fixture.host.windowWillClose(fixture.host.platformWindow) }
        var calls = 0
        var fallback = 0
        fixture.action.accessibilityActions = [
            RetainedAccessibilityAction(kind: .default) { [weak host = fixture.host] in
                calls += 1
                guard let host else { return }
                host.windowWillClose(host.platformWindow)
            }
        ]
        fixture.action.onActivate = { fallback += 1 }
        let cached = try XCTUnwrap(
            AccessibilityProjection.project(runtime: fixture.host.hostedRuntime)?
                .flattened().first { $0.sourceNode === fixture.action })
        let id = try fixture.id()

        XCTAssertTrue(fixture.source.uiaInvokeDefaultAction(elementID: id))
        XCTAssertFalse(fixture.source.uiaInvokeDefaultAction(elementID: id))
        XCTAssertFalse(cached.invokeDefaultAction())
        XCTAssertFalse(fixture.host.hostedRuntime.permitsRetainedActionInvocation)
        XCTAssertNotNil(fixture.action.parent)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(fallback, 0)
        XCTAssertEqual(fixture.renderer.detachCount, 1)
    }

    func testRealHostCloseDuringLayoutPreventsTheSelectedAction() async throws {
        let fixture = ModalActionHostFixture()
        defer { fixture.host.windowWillClose(fixture.host.platformWindow) }
        var calls = 0
        fixture.action.accessibilityActions = [
            RetainedAccessibilityAction(kind: .default) { calls += 1 }
        ]
        fixture.action.onActivate = { calls += 1 }
        let id = try fixture.id()
        fixture.host.hostedRuntime.scheduleAfterLayout(key: "close-host") { [weak host = fixture.host] in
            guard let host else { return }
            host.windowWillClose(host.platformWindow)
        }

        XCTAssertFalse(fixture.source.uiaInvokeDefaultAction(elementID: id))
        XCTAssertFalse(fixture.source.uiaInvokeDefaultAction(elementID: id))
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(fixture.renderer.detachCount, 1)
        XCTAssertNotNil(fixture.action.parent)
    }

    func testCopiedActionDoesNotKeepOldApplicationHandlerAlive() async throws {
        let fixture = ModalActionFixture()
        defer { fixture.retire() }
        weak var weakPayload: ModalActionPayload?
        let cached: AccessibilityProjectedAction
        do {
            let payload = ModalActionPayload()
            weakPayload = payload
            fixture.action.accessibilityActions = [
                RetainedAccessibilityAction(name: "Apply") { payload.calls += 1 }
            ]
            cached = try XCTUnwrap(try fixture.projection(for: fixture.action).actions.first)
        }
        fixture.action.accessibilityActions = []
        XCTAssertNil(weakPayload)
        cached.invoke()
    }

    func testCopiedRuntimeActionDoesNotKeepRuntimeAliveOrBecomeStandalone() async throws {
        let root = ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 120))
        let action = ViewNode(accessibilityLabel: "Action")
        root.addChild(action)
        var calls = 0
        action.accessibilityActions = [
            RetainedAccessibilityAction(name: "Apply") { calls += 1 }
        ]
        var runtime: RetainedViewRuntime? = RetainedViewRuntime(root: root)
        weak var weakRuntime = runtime
        let projected = try XCTUnwrap(
            AccessibilityProjection.project(runtime: try XCTUnwrap(runtime))?
                .flattened().first { $0.sourceNode === action })
        let cached = try XCTUnwrap(projected.actions.first)
        runtime = nil

        XCTAssertNil(weakRuntime)
        cached.invoke()
        XCTAssertEqual(calls, 0)
        withExtendedLifetime((root, action, projected)) {}
    }

    func testStandaloneRootActionsKeepTheirExistingPublicInvocationShape() async throws {
        let root = ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 120))
        let action = ViewNode(accessibilityLabel: "Detached tree action")
        root.addChild(action)
        var calls = 0
        action.accessibilityActions = [
            RetainedAccessibilityAction(name: "Apply") { calls += 1 }
        ]
        let projected = try XCTUnwrap(AccessibilityProjection.project(root: root)?.children.first)
        XCTAssertTrue(projected.invokeDefaultAction())
        let direct = AccessibilityProjectedAction(name: "Direct", kind: nil, isDefault: false) { calls += 1 }
        direct.invoke()
        XCTAssertEqual(calls, 2)
        root.removeChild(action)
        XCTAssertFalse(projected.invokeDefaultAction())
        withExtendedLifetime((root, action)) {}
    }

    func testVirtualizedPlaceholderCopiedActionHonorsItsCurrentOwnerAndModal() async throws {
        let root = ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 120))
        let row = ViewNode(accessibilityLabel: "Deferred row")
        row.isLayoutDeferredByVirtualization = true
        var calls = 0
        row.accessibilityActions = [
            RetainedAccessibilityAction(name: "Select") { calls += 1 }
        ]
        root.addChild(row)
        let cached = try XCTUnwrap(AccessibilityProjection.project(root: root)?.children.first)
        XCTAssertTrue(cached.isVirtualizedPlaceholder)
        XCTAssertTrue(cached.invokeDefaultAction())
        root.accessibilityRespondsToUserInteraction = false
        XCTAssertFalse(cached.invokeDefaultAction())
        root.accessibilityRespondsToUserInteraction = true
        root.addChild(ViewNode(accessibilityTraits: [.isModal]))
        XCTAssertFalse(cached.invokeDefaultAction())
        XCTAssertEqual(calls, 1)
        withExtendedLifetime(root) {}
    }
}

@MainActor
private final class ModalActionFixture {
    let root: ViewNode
    let owner: ViewNode
    let action: ViewNode
    let runtime: RetainedViewRuntime
    let source: RuntimeUIAElementTreeSource
    private var modalNodes: [ViewNode] = []

    init() {
        root = ViewNode(frame: Rect(x: 0, y: 0, width: 400, height: 300))
        owner = ViewNode(frame: Rect(x: 20, y: 30, width: 340, height: 240), accessibilityLabel: "Owner")
        action = ViewNode(
            frame: Rect(x: 10, y: 15, width: 100, height: 30),
            accessibilityLabel: "Action", accessibilityTraits: .isButton)
        root.addChild(owner)
        owner.addChild(action)
        runtime = RetainedViewRuntime(root: root)
        source = RuntimeUIAElementTreeSource(runtime: runtime)
        settle()
    }

    func settle() {
        XCTAssertNotNil(runtime.resolvedLayoutFrame(of: root))
    }

    func retire() {
        runtime.stopRenderLifecycleCallbacks()
        for node in [root, owner, action] + modalNodes {
            node.accessibilityActions = []
            node.onActivate = nil
        }
        modalNodes = []
        runtime.cancelRenderLifecycleTasks()
    }

    func presentModal() -> (node: ViewNode, action: ViewNode) {
        let action = ViewNode(
            frame: Rect(x: 12, y: 15, width: 90, height: 30),
            accessibilityLabel: "Modal action", accessibilityTraits: .isButton)
        let modal = ViewNode(
            frame: Rect(x: 30, y: 40, width: 240, height: 160),
            accessibilityLabel: "Decision", accessibilityTraits: [.isModal], children: [action])
        modal.paintsInDeferredPhase = true
        owner.addChild(modal)
        modalNodes.append(contentsOf: [modal, action])
        return (modal, action)
    }

    func id(named name: String) throws -> UInt64 {
        try XCTUnwrap(source.uiaElementSnapshots().first { $0.name == name }?.id)
    }

    func projection(for node: ViewNode) throws -> AccessibilityElementProjection {
        try XCTUnwrap(AccessibilityProjection.project(runtime: runtime)?.flattened().first { $0.sourceNode === node })
    }
}

@MainActor
private final class ModalActionHostFixture {
    let host: WinSwiftUIWindowHost
    let renderer = FakeRenderBackend()
    let action: ViewNode
    let source: RuntimeUIAElementTreeSource

    init() {
        host = WinSwiftUIWindowHost(
            configuration: WindowGroupConfiguration(
                title: "Modal accessibility", size: IntSize(width: 240, height: 180),
                clearColor: .black, content: [AnyView(EmptyView())]),
            renderer: renderer, batchRenderer: FakeBatchRenderBackend(),
            startupProbeConfiguration: nil)
        action = ViewNode(
            frame: Rect(x: 10, y: 10, width: 100, height: 30),
            accessibilityLabel: "Host action", accessibilityTraits: .isButton)
        host.hostedRuntime.root.addChild(action)
        source = RuntimeUIAElementTreeSource(runtime: host.hostedRuntime)
        XCTAssertNotNil(host.hostedRuntime.resolvedLayoutFrame(of: host.hostedRuntime.root))
        XCTAssertNil(host.platformWindow.nativeHandle)
    }

    func id() throws -> UInt64 {
        try XCTUnwrap(source.uiaElementSnapshots().first { $0.name == "Host action" }?.id)
    }
}

private final class ModalActionPayload {
    var calls = 0
}

extension ModalAccessibilityActionTests {
    private enum FinalFocusMutation: Equatable {
        case accessibilityNotification
        case completion
        case captureCleanup
    }

    private enum FinalFocusActionRoute: CaseIterable, Equatable {
        case liveExplicit
        case liveFallback
        case copiedCustom
    }

    func testFinalFocusNotificationReorderingModalRejectsStaleActionsAndRecovers() async throws {
        try assertFinalFocusMutationRejectsStaleActions(.accessibilityNotification)
    }

    func testFocusCompletionAndCaptureCleanupReorderingModalRejectStaleActionsAndRecover() async throws {
        for mutation in [FinalFocusMutation.completion, .captureCleanup] {
            try assertFinalFocusMutationRejectsStaleActions(mutation)
        }
    }

    private func assertFinalFocusMutationRejectsStaleActions(
        _ mutation: FinalFocusMutation, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        for route in FinalFocusActionRoute.allCases {
            let fixture = ModalActionFixture()
            defer {
                fixture.runtime.onAccessibilityFocusChanged = nil
                fixture.retire()
            }
            let original = fixture.presentModal()
            let replacement = fixture.presentModal()
            original.node.zIndex = 2
            replacement.node.zIndex = 1
            original.action.accessibilityLabel = "Original modal action"
            replacement.action.accessibilityLabel = "Replacement modal action"
            original.action.isFocusable = true
            var oldExplicitCalls = 0
            var oldFallbackCalls = 0
            var currentExplicitCalls = 0
            var currentFallbackCalls = 0
            original.action.onActivate = { oldFallbackCalls += 1 }
            replacement.action.onActivate = { currentFallbackCalls += 1 }
            if route == .copiedCustom {
                original.action.accessibilityActions = [
                    RetainedAccessibilityAction(name: "Apply") { oldExplicitCalls += 1 }
                ]
            } else if route == .liveExplicit {
                original.action.accessibilityActions = [
                    RetainedAccessibilityAction(kind: .default) { oldExplicitCalls += 1 }
                ]
            }
            if route != .liveFallback {
                replacement.action.accessibilityActions = [
                    RetainedAccessibilityAction(kind: .default) { currentExplicitCalls += 1 }
                ]
            }
            fixture.settle()
            XCTAssertTrue(fixture.runtime.activeModalPresentationNode === original.node, file: file, line: line)
            let originalID = try fixture.id(named: "Original modal action")
            var copied: AccessibilityProjectedAction?
            if route == .copiedCustom {
                copied = try XCTUnwrap(try fixture.projection(for: original.action).actions.first)
                try XCTUnwrap(copied).invoke()
            } else {
                XCTAssertTrue(fixture.source.uiaInvokeDefaultAction(elementID: originalID), file: file, line: line)
            }
            // Ordinary admission remains positive before any late mutation.
            XCTAssertEqual(oldExplicitCalls, route == .liveFallback ? 0 : 1, file: file, line: line)
            XCTAssertEqual(oldFallbackCalls, route == .liveFallback ? 1 : 0, file: file, line: line)
            oldExplicitCalls = 0
            oldFallbackCalls = 0
            if mutation != .accessibilityNotification {
                fixture.runtime.requestFocus(original.action)
                fixture.settle()
                XCTAssertTrue(fixture.runtime.focusedNode === original.action, file: file, line: line)
            }
            XCTAssertTrue(fixture.runtime.hasCurrentAccessibilityPrepaint, file: file, line: line)

            var mutations = 0
            var completions = 0
            var enqueues = 0
            var layoutBeforeMutation: RetainedLayoutSettlementReceipt?
            let reorder: @MainActor () -> Void = { [weak fixture, weak raised = replacement.node] in
                guard let fixture, let raised else {
                    XCTFail("The owned modal fixture must remain live", file: file, line: line)
                    return
                }
                mutations += 1
                XCTAssertEqual(mutations, 1, file: file, line: line)
                guard case .settled(let receipt) = fixture.runtime.layoutSettlementStatus else {
                    XCTFail("The late paint mutation must start from settled geometry", file: file, line: line)
                    return
                }
                layoutBeforeMutation = receipt
                raised.zIndex = 3
                XCTAssertTrue(fixture.runtime.isLayoutSettlementReceiptCurrent(receipt), file: file, line: line)
                XCTAssertFalse(fixture.runtime.hasCurrentAccessibilityPrepaint, file: file, line: line)
            }
            if mutation == .accessibilityNotification {
                fixture.runtime.onAccessibilityFocusChanged = { [weak target = original.action] focused in
                    guard focused === target else { return }
                    reorder()
                }
            }
            var onCleanup: (@MainActor () -> Void)?
            if mutation == .captureCleanup { onCleanup = reorder }
            let payload = ModalActionCaptureProbe()
            let request = makeFinalFocusRequest(
                fixture: fixture, preferred: original.action, underlyingModal: original.node,
                payload: payload, onCleanup: onCleanup,
                didFinish: {
                    completions += 1
                    if mutation == .completion { reorder() }
                })
            XCTAssertNotNil(payload.value, file: file, line: line)
            fixture.runtime.scheduleAfterLayout(key: "modal-uia-final-focus") { [weak runtime = fixture.runtime] in
                enqueues += 1
                runtime?.schedulePresentationFocusRestoration(request)
            }

            if route == .copiedCustom {
                try XCTUnwrap(copied).invoke()
            } else {
                XCTAssertFalse(fixture.source.uiaInvokeDefaultAction(elementID: originalID), file: file, line: line)
            }

            XCTAssertEqual(enqueues, 1, file: file, line: line)
            XCTAssertEqual(completions, 1, file: file, line: line)
            XCTAssertEqual(mutations, 1, file: file, line: line)
            XCTAssertNil(payload.value, file: file, line: line)
            XCTAssertGreaterThan(replacement.node.zIndex, original.node.zIndex, file: file, line: line)
            let layoutReceipt = try XCTUnwrap(layoutBeforeMutation, file: file, line: line)
            XCTAssertTrue(fixture.runtime.isLayoutSettlementReceiptCurrent(layoutReceipt), file: file, line: line)
            XCTAssertFalse(fixture.runtime.hasCurrentAccessibilityPrepaint, file: file, line: line)
            XCTAssertTrue(fixture.runtime.activeModalPresentationNode === original.node, file: file, line: line)
            XCTAssertEqual(oldExplicitCalls, 0, file: file, line: line)
            XCTAssertEqual(oldFallbackCalls, 0, file: file, line: line)
            XCTAssertEqual(currentExplicitCalls, 0, file: file, line: line)
            XCTAssertEqual(currentFallbackCalls, 0, file: file, line: line)

            // A later independent query may consume the paint change normally.
            fixture.settle()
            XCTAssertTrue(fixture.runtime.hasCurrentAccessibilityPrepaint, file: file, line: line)
            XCTAssertTrue(fixture.runtime.activeModalPresentationNode === replacement.node, file: file, line: line)
            let currentID = try fixture.id(named: "Replacement modal action")
            XCTAssertTrue(fixture.source.uiaInvokeDefaultAction(elementID: currentID), file: file, line: line)
            XCTAssertFalse(fixture.source.uiaInvokeDefaultAction(elementID: originalID), file: file, line: line)
            XCTAssertEqual(currentExplicitCalls, route == .liveFallback ? 0 : 1, file: file, line: line)
            XCTAssertEqual(currentFallbackCalls, route == .liveFallback ? 1 : 0, file: file, line: line)
            XCTAssertEqual(oldExplicitCalls, 0, file: file, line: line)
            XCTAssertEqual(oldFallbackCalls, 0, file: file, line: line)
            XCTAssertEqual(mutations, 1, file: file, line: line)
            XCTAssertEqual(completions, 1, file: file, line: line)
        }
    }

    private func makeFinalFocusRequest(
        fixture: ModalActionFixture, preferred: ViewNode, underlyingModal: ViewNode,
        payload: ModalActionCaptureProbe, onCleanup: (@MainActor () -> Void)?,
        didFinish: @escaping @MainActor () -> Void
    ) -> RetainedPresentationFocusRequest {
        let capture = ModalActionReleasePayload(onCleanup)
        payload.value = capture
        return RetainedPresentationFocusRequest(
            owner: ModalActionPayload(), preferred: preferred, underlyingModal: underlyingModal,
            expectedFocusRevision: fixture.runtime.presentationFocusRevision,
            isCurrent: { [capture] in withExtendedLifetime(capture) { true } },
            resolveBase: { [weak base = fixture.owner] in base }, didFinish: didFinish)
    }
}

@MainActor
private final class ModalActionCaptureProbe {
    weak var value: ModalActionReleasePayload?
}

@MainActor
private final class ModalActionReleasePayload {
    private let onRelease: (@MainActor () -> Void)?

    init(_ onRelease: (@MainActor () -> Void)?) {
        self.onRelease = onRelease
    }

    isolated deinit { onRelease?() }
}
