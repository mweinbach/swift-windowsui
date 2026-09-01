import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Source regression cases for the common Button payload owner. These do not
/// redefine arbitrary modifier callbacks as revocable Button actions.
@MainActor
final class RetainedButtonActionOwnershipTests: XCTestCase {
    func testIdleStandaloneControlCanActivateAndRepeat() async {
        let runtime = makeRuntime()
        var calls = 0
        let node = button(in: runtime) { calls += 1 }

        node.onActivate?()
        node.onRepeatActivate?()

        XCTAssertNil(node.parent)
        XCTAssertEqual(calls, 2)
    }

    func testStandaloneFacadeRetainsActionThenInvalidationOrder() async {
        let runtime = makeRuntime()
        var events: [String] = []
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 200, height: 100) },
            invalidateHandler: { events.append("invalidate") })
        let node = Button("Run") { events.append("action") }.makeComponent(context: context).makeNode(runtime: runtime)

        node.onActivate?()

        XCTAssertEqual(events, ["action", "invalidate"])
    }

    func testNonnilActivationWrapperCanDelegateToOriginalHandler() async {
        let runtime = makeRuntime()
        var events: [String] = []
        let node = button(in: runtime) { events.append("action") }
        let delegated = node.onActivate
        node.onActivate = {
            events.append("before")
            delegated?()
            events.append("after")
        }

        node.onActivate?()

        XCTAssertEqual(events, ["before", "action", "after"])
    }

    func testWrapperIsPreservedWhenItsDeclarationMovesOntoRetainedNode() async {
        let runtime = makeRuntime()
        let retained = button(in: runtime) {}
        runtime.root.addChild(retained)
        var events: [String] = []
        let incoming = button(in: runtime) { events.append("new action") }
        let delegated = incoming.onActivate
        incoming.onActivate = {
            events.append("before")
            delegated?()
            events.append("after")
        }

        XCTAssertTrue(ComponentHost.adopt(source: incoming, into: retained).completed)
        retained.onActivate?()

        XCTAssertTrue(runtime.root.children.first === retained)
        XCTAssertEqual(events, ["before", "new action", "after"])
    }

    func testNilActivationPermanentlyRetiresSavedActionAndRepeat() async {
        let runtime = makeRuntime()
        var calls = 0
        let node = button(in: runtime) { calls += 1 }
        let saved = node.onActivate
        let savedRepeat = node.onRepeatActivate
        node.onActivate = nil
        node.onActivate = saved
        node.onRepeatActivate = savedRepeat

        saved?()
        savedRepeat?()
        node.onActivate?()

        XCTAssertEqual(calls, 0)
    }

    func testClearingRepeatDoesNotDisablePrimaryActivation() async {
        let runtime = makeRuntime()
        var calls = 0
        let node = button(in: runtime) { calls += 1 }
        let savedRepeat = node.onRepeatActivate
        node.onRepeatActivate = nil
        node.onRepeatActivate = savedRepeat

        savedRepeat?()
        node.onActivate?()

        XCTAssertEqual(calls, 1)
    }

    func testRouteModifiersDoNotBecomeCommonLifetimePredicates() async {
        let runtime = makeRuntime()
        var calls = 0
        let node = button(in: runtime) { calls += 1 }
        runtime.root.addChild(node)
        node.isFocusable = false
        node.isFocusEnabled = false
        node.isHitTestVisible = false
        node.accessibilityRespondsToUserInteraction = false
        node.accessibilityTraits.remove(.isButton)

        node.onActivate?()

        XCTAssertEqual(calls, 1, "Each real input route applies its own eligibility checks")
    }

    func testDisabledConstructionHasNoOwnedAction() async {
        let runtime = makeRuntime()
        var calls = 0
        let node = button(in: runtime, enabled: false) { calls += 1 }
        runtime.root.addChild(node)

        XCTAssertNil(node.onActivate)
        XCTAssertNil(node.onRepeatActivate)
        XCTAssertNil(node.buttonActionOwner)
        XCTAssertEqual(calls, 0)
    }

    func testDisableThenEnableReplacementCannotReviveAnEscapedOldAction() async {
        let runtime = makeRuntime()
        var calls: [String] = []
        let retained = button(in: runtime) { calls.append("old") }
        runtime.root.addChild(retained)
        let oldAction = retained.onActivate
        let disabled = button(in: runtime, enabled: false) { calls.append("disabled") }

        XCTAssertTrue(ComponentHost.adopt(source: disabled, into: retained).completed)
        oldAction?()
        retained.onActivate?()
        XCTAssertTrue(calls.isEmpty)
        XCTAssertNil(retained.onActivate)

        let enabled = button(in: runtime) { calls.append("new") }
        XCTAssertTrue(ComponentHost.adopt(source: enabled, into: retained).completed)
        oldAction?()
        retained.onActivate?()
        XCTAssertEqual(calls, ["new"])
    }

    func testPublishedPointerAndKeyboardUseCurrentOwnedPayload() async {
        let runtime = makeRuntime()
        var calls = 0
        let node = button(in: runtime) { calls += 1 }
        runtime.root.addChild(node)

        runtime.pointerDown(at: Point(x: 40, y: 35))
        runtime.pointerUp(at: Point(x: 40, y: 35))
        runtime.requestFocus(node)
        runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.enter.rawValue))

        XCTAssertEqual(calls, 2)
    }

    func testPhysicalRemoveAndReinsertNeverRevivesSavedButtonPayload() async {
        let runtime = makeRuntime()
        var calls = 0
        let node = button(in: runtime) { calls += 1 }
        runtime.root.addChild(node)
        let saved = node.onActivate

        node.removeFromParent()
        runtime.root.addChild(node)
        saved?()
        node.onActivate?()

        XCTAssertTrue(runtime.root.children.first === node)
        XCTAssertEqual(calls, 0)
    }

    func testRemovingAnAncestorRetiresAllDescendantButtonPayloads() async {
        let runtime = makeRuntime()
        var calls = 0
        let first = button(in: runtime, tag: "first") { calls += 1 }
        let second = button(in: runtime, tag: "second") { calls += 1 }
        let container = ViewNode(children: [first, second])
        runtime.root.addChild(container)
        let saved = [first.onActivate, second.onActivate]

        container.removeFromParent()
        runtime.root.addChild(container)
        for action in saved { action?() }

        XCTAssertEqual(calls, 0)
    }

    func testMovingAnAcceptedControlToAnotherRuntimeDoesNotReviveIt() async {
        let source = makeRuntime()
        let destination = makeRuntime()
        var calls = 0
        let node = button(in: source) { calls += 1 }
        source.root.addChild(node)
        let saved = node.onActivate

        destination.root.addChild(node)
        saved?()

        XCTAssertTrue(destination.root.children.first === node)
        XCTAssertEqual(calls, 0)
    }

    func testWholeRemovalCohortIsClosedBeforeFirstPayloadDestructor() async {
        let runtime = makeRuntime()
        var calls = 0
        let later = button(in: runtime, tag: "later") { calls += 1 }
        var releases = 0
        var probe: ButtonActionReleaseProbe? = ButtonActionReleaseProbe {
            releases += 1
            later.onActivate?()
        }
        let first = button(in: runtime, tag: "first") { [captured = probe!] in
            withExtendedLifetime(captured) {}
        }
        probe = nil
        runtime.root.addChild(first)
        runtime.root.addChild(later)

        runtime.root.removeAllChildren()

        XCTAssertEqual(releases, 1)
        XCTAssertEqual(calls, 0)
    }

    func testTerminalCloseRejectsSavedActionAndNewConstruction() async {
        let runtime = makeRuntime()
        var calls = 0
        let node = button(in: runtime) { calls += 1 }
        runtime.root.addChild(node)
        let saved = node.onActivate

        runtime.stopRenderLifecycleCallbacks()
        saved?()
        let afterClose = button(in: runtime, tag: "after close") { calls += 1 }
        afterClose.onActivate?()
        runtime.root.addChild(afterClose)
        afterClose.onActivate?()

        XCTAssertEqual(calls, 0)
    }

    func testReplacementRetiresEscapedOldCallbackAndUsesNewCallback() async {
        let runtime = makeRuntime()
        var calls: [String] = []
        let retained = button(in: runtime) { calls.append("old") }
        runtime.root.addChild(retained)
        let saved = retained.onActivate
        let incoming = button(in: runtime) { calls.append("new") }

        XCTAssertTrue(ComponentHost.adopt(source: incoming, into: retained).completed)
        saved?()
        retained.onActivate?()

        XCTAssertNil(incoming.buttonActionOwner)
        XCTAssertEqual(calls, ["new"])
    }

    func testReplacingButtonWithPassiveNodeClearsOwnedAction() async {
        let runtime = makeRuntime()
        var calls = 0
        let retained = button(in: runtime) { calls += 1 }
        runtime.root.addChild(retained)
        let saved = retained.onActivate

        XCTAssertTrue(ComponentHost.adopt(source: ViewNode(), into: retained).completed)
        saved?()

        XCTAssertNil(retained.onActivate)
        XCTAssertNil(retained.buttonActionOwner)
        XCTAssertEqual(calls, 0)
    }

    func testAcceptedReplacementKeepsSharedFlightClosedUntilOriginalActionReturns() async {
        let runtime = makeRuntime()
        var calls: [String] = []
        var retained: ViewNode!
        retained = button(in: runtime) { [self] in
            calls.append("old")
            let incoming = button(in: runtime) { calls.append("new") }
            XCTAssertTrue(ComponentHost.adopt(source: incoming, into: retained).completed)
            retained.onActivate?()
            retained.onRepeatActivate?()
        }
        runtime.root.addChild(retained)

        retained.onActivate?()
        XCTAssertEqual(calls, ["old"])
        retained.onActivate?()
        XCTAssertEqual(calls, ["old", "new"])
    }

    func testPassiveRoleBetweenReentrantDeclarationsDoesNotOpenANewFlight() async {
        let runtime = makeRuntime()
        var calls: [String] = []
        var retained: ViewNode!
        retained = button(in: runtime) { [self] in
            calls.append("old")
            XCTAssertTrue(ComponentHost.adopt(source: ViewNode(), into: retained).completed)
            let incoming = button(in: runtime) { calls.append("new") }
            XCTAssertTrue(ComponentHost.adopt(source: incoming, into: retained).completed)
            retained.onActivate?()
        }
        runtime.root.addChild(retained)

        retained.onActivate?()
        XCTAssertEqual(calls, ["old"])
        retained.onActivate?()
        XCTAssertEqual(calls, ["old", "new"])
    }

    func testInvokedPayloadDestructorRunsBeforeTheSharedFlightReopens() async {
        let runtime = makeRuntime()
        var calls: [String] = []
        var releases = 0
        var retained: ViewNode!
        var probe: ButtonActionReleaseProbe? = ButtonActionReleaseProbe {
            releases += 1
            retained.onActivate?()
        }
        retained = button(in: runtime) { [self, captured = probe!] in
            calls.append("old")
            let incoming = button(in: runtime) { calls.append("new") }
            XCTAssertTrue(ComponentHost.adopt(source: incoming, into: retained).completed)
            XCTAssertEqual(releases, 0)
            withExtendedLifetime(captured) {}
        }
        probe = nil
        runtime.root.addChild(retained)

        retained.onActivate?()

        XCTAssertEqual(releases, 1)
        XCTAssertEqual(calls, ["old"])
        retained.onActivate?()
        XCTAssertEqual(calls, ["old", "new"])
    }

    func testActionRemovalSkipsItsGuardedCompletion() async {
        let runtime = makeRuntime()
        var completions = 0
        var retained: ViewNode!
        retained = button(in: runtime) { retained.removeFromParent() }
        retained.setButtonActionCompletion { completions += 1 }
        runtime.root.addChild(retained)

        retained.onActivate?()

        XCTAssertNil(retained.parent)
        XCTAssertEqual(completions, 0)
    }

    func testFacadeActionReplacementDoesNotInvalidateThroughOldContext() async throws {
        let runtime = makeRuntime()
        let host = ComponentHost(runtime: runtime)
        var first = true
        var calls = 0
        var invalidations = 0
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: 200, height: 100) },
            invalidateHandler: { [weak host] in
                invalidations += 1
                host?.reload()
            })
        host.setComponents {
            let isFirst = first
            return [
                Button("Run") {
                    calls += 1
                    if isFirst {
                        first = false
                        host.reload()
                    }
                }.makeComponent(context: context).keyed("shared")
            ]
        }
        let retained = try XCTUnwrap(runtime.root.children.first)

        retained.onActivate?()
        XCTAssertTrue(runtime.root.children.first === retained)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(invalidations, 0)
        retained.onActivate?()
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(invalidations, 1)
    }

    func testMatchingHashCalloutCannotInvokeAnOldAffectedButton() async {
        let runtime = makeRuntime()
        let hook = ButtonActionMatchingHook()
        var calls: [String] = []
        let old = button(in: runtime) { calls.append("old") }
        old.retainedViewIdentity = identity(1, hook: hook)
        runtime.root.addChild(old)
        let other = ViewNode()
        other.retainedViewIdentity = identity(2, hook: hook)
        runtime.root.addChild(other)
        let incoming = button(in: runtime) { calls.append("new") }
        incoming.retainedViewIdentity = identity(1, hook: hook)
        let nextOther = ViewNode()
        nextOther.retainedViewIdentity = identity(2, hook: hook)
        let saved = old.onActivate
        hook.action = { saved?() }

        let result = ComponentHost.reconcileChildren(
            of: runtime.root, oldChildren: runtime.root.children, newNodes: [incoming, nextOther])

        XCTAssertTrue(result.completed)
        XCTAssertEqual(hook.calls, 1)
        XCTAssertTrue(calls.isEmpty)
        old.onActivate?()
        XCTAssertEqual(calls, ["new"])
    }

    func testRejectedMatchingRestoresUntouchedOldControlAdmission() async {
        let runtime = makeRuntime()
        let hook = ButtonActionMatchingHook()
        var calls: [String] = []
        let old = button(in: runtime) { calls.append("old") }
        old.retainedViewIdentity = identity(1, hook: hook)
        runtime.root.addChild(old)
        let incoming = button(in: runtime) { calls.append("new") }
        incoming.retainedViewIdentity = identity(1, hook: hook)
        hook.action = { incoming.onActivate = nil }

        let result = ComponentHost.reconcileChildren(
            of: runtime.root, oldChildren: runtime.root.children, newNodes: [incoming])

        XCTAssertFalse(result.completed)
        XCTAssertEqual(hook.calls, 1)
        XCTAssertTrue(runtime.root.children.first === old)
        old.onActivate?()
        XCTAssertEqual(calls, ["old"])
    }

    func testMatchingPhysicalABACannotRefreshAnOldAttachmentWitness() async {
        let runtime = makeRuntime()
        let hook = ButtonActionMatchingHook()
        var calls = 0
        let old = button(in: runtime) { calls += 1 }
        old.retainedViewIdentity = identity(1, hook: hook)
        runtime.root.addChild(old)
        let incoming = button(in: runtime) { calls += 10 }
        incoming.retainedViewIdentity = identity(1, hook: hook)
        hook.action = {
            old.removeFromParent()
            runtime.root.addChild(old)
        }

        let result = ComponentHost.reconcileChildren(
            of: runtime.root, oldChildren: runtime.root.children, newNodes: [incoming])

        XCTAssertFalse(result.completed)
        XCTAssertEqual(hook.calls, 1)
        old.onActivate?()
        incoming.onActivate?()
        XCTAssertEqual(calls, 0)
    }

    func testOwnerSlotParticipatesInSourcePayloadAttribution() async {
        let runtime = makeRuntime()
        let node = button(in: runtime) {}
        XCTAssertTrue(node.retainedSourcePayloadFields.contains(\ViewNode.buttonActionOwner))
        XCTAssertFalse(ViewNode().retainedSourcePayloadFields.contains(\ViewNode.buttonActionOwner))
    }

    func testSourceIdentityMutationDuringHashingRejectsBeforeReplacingOldAction() async {
        assertMatchingIdentityMutationIsRejected(sourceChanges: true, equalAssignment: false, usesHashing: true)
    }

    func testRetainedIdentityMutationDuringHashingRejectsBeforeReplacingOldAction() async {
        assertMatchingIdentityMutationIsRejected(sourceChanges: false, equalAssignment: false, usesHashing: true)
    }

    func testSourceEqualIdentityAssignmentDuringEqualityRejectsBeforeReplacingOldAction() async {
        assertMatchingIdentityMutationIsRejected(sourceChanges: true, equalAssignment: true, usesHashing: false)
    }

    func testRetainedEqualIdentityAssignmentDuringEqualityRejectsBeforeReplacingOldAction() async {
        assertMatchingIdentityMutationIsRejected(sourceChanges: false, equalAssignment: true, usesHashing: false)
    }

    func testDeliberateOrdinaryIdentityCopyKeepsTheNewActionUsable() async {
        let runtime = makeRuntime()
        let hook = ButtonActionMatchingHook()
        var calls: [String] = []
        let retained = button(in: runtime) { calls.append("old") }
        retained.retainedViewIdentity = identity(1, hook: hook)
        runtime.root.addChild(retained)
        let old = retained.onActivate
        let source = button(in: runtime) { calls.append("new") }
        source.retainedViewIdentity = identity(2, hook: hook)

        let result = ComponentHost.adopt(source: source, into: retained)

        XCTAssertTrue(result.completed)
        XCTAssertEqual(retained.retainedViewIdentity, source.retainedViewIdentity)
        old?()
        retained.onActivate?()
        XCTAssertEqual(calls, ["new"])
    }

    func testNestedAdoptionCannotBorrowAnOuterPendingSource() async {
        let runtime = makeRuntime()
        let hook = ButtonActionMatchingHook()
        var calls: [String] = []
        let retained = button(in: runtime) { calls.append("old") }
        retained.retainedViewIdentity = identity(1, hook: hook)
        let other = ViewNode()
        runtime.root.addChild(retained)
        runtime.root.addChild(other)
        let source = button(in: runtime) { calls.append("pending") }
        source.retainedViewIdentity = identity(1, hook: hook)
        let saved = source.onActivate
        var nestedCompleted: Bool?
        hook.action = {
            nestedCompleted = ComponentHost.adopt(source: source, into: other).completed
            let unchanged = source.retainedViewIdentity
            source.retainedViewIdentity = unchanged
        }

        let result = ComponentHost.reconcileChildren(
            of: runtime.root, oldChildren: runtime.root.children, newNodes: [source, other])

        XCTAssertEqual(nestedCompleted, false)
        XCTAssertFalse(result.completed)
        XCTAssertNil(other.buttonActionOwner)
        retained.onActivate?()
        saved?()
        XCTAssertEqual(calls, ["old"])
    }

    func testAcceptedNestedDeclarationSurvivesAnOlderAdoptionFailure() async {
        let runtime = makeRuntime()
        var calls: [String] = []
        let retained = button(in: runtime) { calls.append("old") }
        let other = ViewNode()
        other.nodeTag = "other"
        runtime.root.addChild(retained)
        runtime.root.addChild(other)
        let source = button(in: runtime) { calls.append("outer") }
        var nestedCompleted: Bool?
        source.onUpdatePlatformView = { [self] _ in
            let nested = button(in: runtime) { calls.append("nested") }
            nestedCompleted = ComponentHost.adopt(source: nested, into: other).completed
        }
        defer {
            source.onUpdatePlatformView = nil
            retained.onUpdatePlatformView = nil
        }

        let result = ComponentHost.reconcileChildren(
            of: runtime.root, oldChildren: runtime.root.children, newNodes: [source, other])

        XCTAssertEqual(nestedCompleted, true)
        XCTAssertFalse(result.completed)
        XCTAssertFalse(other.buttonActionOwner?.isRetired == true)
        retained.onActivate?()
        other.onActivate?()
        XCTAssertEqual(calls, ["nested"])
    }

    func testTerminalPayloadReleaseDrainsStopOnlyReentryForRemainingOwners() async {
        let runtime = makeRuntime()
        var releases: [Int] = []
        var stopReentries = 0
        weak var firstPayload: ButtonActionReleaseProbe?
        weak var secondPayload: ButtonActionReleaseProbe?
        let install: (Int) -> Void = { [self] index in
            let payload = ButtonActionReleaseProbe {
                releases.append(index)
                if stopReentries == 0 {
                    stopReentries += 1
                    runtime.stopRenderLifecycleCallbacks()
                }
            }
            if index == 0 { firstPayload = payload } else { secondPayload = payload }
            runtime.root.addChild(button(in: runtime) { [payload] in withExtendedLifetime(payload) {} })
        }
        install(0)
        install(1)
        XCTAssertNotNil(firstPayload)
        XCTAssertNotNil(secondPayload)

        runtime.stopRenderLifecycleCallbacks()
        XCTAssertTrue(releases.isEmpty)
        runtime.cancelRenderLifecycleTasks()

        XCTAssertEqual(stopReentries, 1)
        XCTAssertEqual(Set(releases), Set([0, 1]))
        XCTAssertEqual(releases.count, 2)
        XCTAssertNil(firstPayload)
        XCTAssertNil(secondPayload)
        runtime.cancelRenderLifecycleTasks()
        XCTAssertEqual(releases.count, 2)
    }

    func testNativeDeparturePrepassReachesEditorAndPresenterBeyondLayoutDepthLimit() async {
        let root = ViewNode()
        var deepest = root
        for _ in 0..<(ViewNode.maximumTraversalDepth + 2) {
            let child = ViewNode()
            deepest.addChild(child)
            deepest = child
        }
        let controller = ButtonActionDeepRevocationController()
        deepest.textInputController = controller
        let presenter = deepest.beginFileDialogPresentation(kind: .exporter)
        XCTAssertTrue(presenter.isValid)
        XCTAssertNil(root.buttonActionOwner)

        root.revokeTextInputOwnership()

        XCTAssertEqual(controller.revocations, 1)
        XCTAssertFalse(presenter.isValid)
    }

    func testFreshDeclarationCanReplaceARetiredActionOnTheSameRetainedNode() async {
        let runtime = makeRuntime()
        var calls: [String] = []
        let retained = button(in: runtime) { calls.append("old") }
        runtime.root.addChild(retained)
        let oldAction = retained.onActivate
        retained.onActivate = nil
        let fresh = button(in: runtime) { calls.append("new") }

        let result = ComponentHost.adopt(source: fresh, into: retained)

        XCTAssertTrue(result.completed)
        oldAction?()
        retained.onActivate?()
        XCTAssertEqual(calls, ["new"])
    }

    func testFreshDeclarationAfterPhysicalABADoesNotReviveItsOldSavedHandler() async {
        let runtime = makeRuntime()
        var calls: [String] = []
        let retained = button(in: runtime) { calls.append("old") }
        runtime.root.addChild(retained)
        let oldAction = retained.onActivate
        retained.removeFromParent()
        runtime.root.addChild(retained)
        oldAction?()
        XCTAssertTrue(calls.isEmpty)
        let fresh = button(in: runtime) { calls.append("new") }

        let result = ComponentHost.adopt(source: fresh, into: retained)

        XCTAssertTrue(result.completed)
        oldAction?()
        retained.onActivate?()
        XCTAssertEqual(calls, ["new"])
    }

    func testSourceWithClearedActionCanStillAdoptItsVisualDeclaration() async {
        let runtime = makeRuntime()
        var calls: [String] = []
        let retained = button(in: runtime) { calls.append("old") }
        runtime.root.addChild(retained)
        let oldAction = retained.onActivate
        let source = button(in: runtime) { calls.append("source") }
        let sourceAction = source.onActivate
        source.onActivate = nil
        source.backgroundColor = .red

        let result = ComponentHost.adopt(source: source, into: retained)

        XCTAssertTrue(result.completed)
        XCTAssertEqual(retained.backgroundColor, .red)
        XCTAssertNil(retained.onActivate)
        XCTAssertNil(retained.buttonActionOwner)
        oldAction?()
        sourceAction?()
        retained.onRepeatActivate?()
        XCTAssertTrue(calls.isEmpty)
    }

    private func assertMatchingIdentityMutationIsRejected(
        sourceChanges: Bool, equalAssignment: Bool, usesHashing: Bool,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let runtime = makeRuntime()
        let hook = ButtonActionMatchingHook()
        var calls: [String] = []
        let retained = button(in: runtime) { calls.append("old") }
        retained.retainedViewIdentity = identity(1, hook: hook)
        runtime.root.addChild(retained)
        let source = button(in: runtime) { calls.append("new") }
        source.retainedViewIdentity = identity(1, hook: hook)
        let filler = ViewNode()
        if usesHashing { runtime.root.addChild(filler) }
        let changed = sourceChanges ? source : retained
        let original = changed.retainedViewIdentity
        let replacement = identity(2, hook: hook)
        hook.action = { changed.retainedViewIdentity = equalAssignment ? original : replacement }

        let result = ComponentHost.reconcileChildren(
            of: runtime.root, oldChildren: runtime.root.children, newNodes: usesHashing ? [source, filler] : [source])

        XCTAssertFalse(result.completed, file: file, line: line)
        XCTAssertEqual(hook.calls, 1, file: file, line: line)
        XCTAssertTrue(runtime.root.children.first === retained, file: file, line: line)
        retained.onActivate?()
        source.onActivate?()
        XCTAssertEqual(calls, ["old"], file: file, line: line)
    }

    private func makeRuntime() -> RetainedViewRuntime {
        RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 100), isHitTestVisible: false))
    }

    private func button(
        in runtime: RetainedViewRuntime, tag: String = "button", enabled: Bool = true,
        action: @escaping () -> Void
    ) -> ViewNode {
        let node = Controls.button(
            runtime: runtime, frame: Rect(x: 20, y: 20, width: 100, height: 30), cornerRadius: 4,
            palette: SurfacePalette(idle: .gray, focused: .blue, pressed: .black), isEnabled: enabled,
            animation: ControlAnimationStyle(focusDuration: 0, pressDuration: 0), action: action)
        node.nodeTag = tag
        return node
    }

    private func identity(_ value: Int, hook: ButtonActionMatchingHook) -> RetainedViewIdentity {
        RetainedViewIdentity(segments: [.keyed(.init(ButtonActionMatchingKey(value: value, hook: hook)))])
    }
}

@MainActor
private final class ButtonActionReleaseProbe {
    let action: @MainActor () -> Void
    init(_ action: @escaping @MainActor () -> Void) { self.action = action }
    isolated deinit { action() }
}

@MainActor
private final class ButtonActionMatchingHook {
    var action: (@MainActor () -> Void)?
    var calls = 0

    func fire() {
        guard let action else { return }
        self.action = nil
        calls += 1
        action()
    }
}

private struct ButtonActionMatchingKey: Hashable {
    let value: Int
    let hook: ButtonActionMatchingHook

    func hash(into hasher: inout Hasher) {
        MainActor.assumeIsolated { hook.fire() }
        hasher.combine(value)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        MainActor.assumeIsolated {
            lhs.hook.fire()
            rhs.hook.fire()
        }
        return lhs.value == rhs.value
    }
}

@MainActor
private final class ButtonActionDeepRevocationController: RetainedTextInputController {
    private(set) var revocations = 0
    func attach(to node: ViewNode) {}
    func reconcile(from previous: (any RetainedTextInputController)?, onto node: ViewNode) {}
    func revokeOwnership(from node: ViewNode) { revocations += 1 }
    func detach(from node: ViewNode) {}
}
