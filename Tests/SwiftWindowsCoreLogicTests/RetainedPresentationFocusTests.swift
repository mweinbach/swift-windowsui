import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI

/// The caller supplies accepted-removal authority; these fixtures isolate the
/// runtime's settlement, modal scope, and reentrant focus transition.
@MainActor
final class RetainedPresentationFocusTests: XCTestCase {
    private enum PaintPath: CaseIterable {
        case frame, scene

        @MainActor
        func draw(_ runtime: RetainedViewRuntime) {
            switch self {
            case .frame: _ = runtime.renderFrame()
            case .scene: _ = runtime.renderScene()
            }
        }
    }

    private final class FocusOwner {}

    private struct Fixture {
        let runtime: RetainedViewRuntime
        let base: ViewNode
        let first: ViewNode
        let second: ViewNode
        let third: ViewNode
    }

    private static let bounds = Rect(x: 0, y: 0, width: 320, height: 240)

    private func control(_ name: String, y: Double = 20) -> ViewNode {
        let node = ViewNode(
            frame: Rect(x: 20, y: y, width: 120, height: 28),
            isFocusable: true, isHitTestVisible: true,
            accessibilityLabel: name, accessibilityTraits: [.isButton])
        node.accessibilityRespondsToUserInteraction = true
        return node
    }

    private func makeFixture(_ path: PaintPath = .frame) -> Fixture {
        let first = control("first")
        let second = control("second", y: 60)
        let third = control("third", y: 100)
        let base = ViewNode(frame: Self.bounds, children: [first, second, third])
        let root = ViewNode(frame: Self.bounds, children: [base])
        let runtime = RetainedViewRuntime(root: root)
        path.draw(runtime)
        return Fixture(runtime: runtime, base: base, first: first, second: second, third: third)
    }

    private func modal(containing children: [ViewNode]) -> ViewNode {
        let node = ViewNode(frame: Self.bounds, accessibilityTraits: [.isModal], children: children)
        node.paintsInDeferredPhase = true
        return node
    }

    private func request(
        _ fixture: Fixture, owner: AnyObject? = nil, preferred: ViewNode? = nil,
        underlyingModal: ViewNode? = nil, didFinish: (@MainActor () -> Void)? = nil
    ) -> RetainedPresentationFocusRequest {
        RetainedPresentationFocusRequest(
            owner: owner ?? FocusOwner(), preferred: preferred, underlyingModal: underlyingModal,
            expectedFocusRevision: fixture.runtime.presentationFocusRevision,
            isCurrent: { true }, resolveBase: { [weak base = fixture.base] in base }, didFinish: didFinish)
    }

    func testAcceptedAbsenceRestoresPreferredOnceOnBothRenderPaths() async {
        for path in PaintPath.allCases {
            let fixture = makeFixture(path)
            let action = control("alert action")
            let outgoing = modal(containing: [action])
            fixture.runtime.root.addChild(outgoing)
            path.draw(fixture.runtime)
            fixture.runtime.requestFocus(action)
            outgoing.removeFromParent()
            var focusEvents: [String] = []
            var completions = 0
            fixture.runtime.onAccessibilityFocusChanged = { focusEvents.append($0?.accessibilityLabel ?? "nil") }

            fixture.runtime.schedulePresentationFocusRestoration(
                request(fixture, preferred: fixture.second, didFinish: { completions += 1 }))
            path.draw(fixture.runtime)

            XCTAssertTrue(fixture.runtime.focusedNode === fixture.second)
            XCTAssertTrue(fixture.second.isFocused)
            XCTAssertFalse(action.isFocused)
            XCTAssertEqual(focusEvents, ["second"])
            XCTAssertEqual(completions, 1)
            path.draw(fixture.runtime)
            XCTAssertEqual(focusEvents, ["second"])
            XCTAssertEqual(completions, 1)
            XCTAssertFalse(fixture.runtime.isDirty, "A consumed request must not request continuous frames")
        }
    }

    func testFallbackSkipsHiddenDisabledDetachedAndOutOfBasePreferredTargets() async {
        for path in PaintPath.allCases {
            for variant in 0..<5 {
                let fixture = makeFixture(path)
                let detached = control("detached")
                let outside = control("outside", y: 180)
                fixture.runtime.root.addChild(outside)
                let preferred: ViewNode?
                switch variant {
                case 0: preferred = nil
                case 1:
                    fixture.second.isHidden = true
                    preferred = fixture.second
                case 2:
                    fixture.second.accessibilityRespondsToUserInteraction = false
                    preferred = fixture.second
                case 3: preferred = detached
                default: preferred = outside
                }
                fixture.first.accessibilityRespondsToUserInteraction = false
                fixture.second.isHidden = variant != 2

                fixture.runtime.schedulePresentationFocusRestoration(request(fixture, preferred: preferred))
                path.draw(fixture.runtime)

                XCTAssertTrue(fixture.runtime.focusedNode === fixture.third, "preferred variant \(variant)")
                XCTAssertFalse(fixture.first.isFocused)
                XCTAssertFalse(fixture.second.isFocused)
                XCTAssertFalse(detached.isFocused)
                XCTAssertFalse(outside.isFocused)
            }
        }
    }

    func testReplacementModalCancelsRestorationPermanently() async throws {
        for path in PaintPath.allCases {
            let fixture = makeFixture(path)
            let coordinator = fixture.runtime.retainedBuildCoordinator
            _ = try XCTUnwrap(coordinator.beginBuild())
            defer { if coordinator.isBuilding { coordinator.finishBuild() } }
            var entries = 0
            fixture.first.onFocusEnter = { entries += 1 }
            fixture.runtime.schedulePresentationFocusRestoration(request(fixture, preferred: fixture.first))
            let replacement = modal(containing: [control("replacement")])
            fixture.runtime.root.addChild(replacement)

            coordinator.finishBuild()
            path.draw(fixture.runtime)

            XCTAssertTrue(fixture.runtime.presentationModalSnapshot === replacement)
            XCTAssertFalse(fixture.first.isFocused)
            XCTAssertEqual(entries, 0)
            replacement.removeFromParent()
            path.draw(fixture.runtime)
            XCTAssertEqual(entries, 0, "Removing a replacement does not resurrect an old request")
        }
    }

    func testExistingUnderlyingModalPermitsItsOriginalFocusOutsideTheBase() async {
        for path in PaintPath.allCases {
            let fixture = makeFixture(path)
            let original = control("underlying action", y: 180)
            fixture.base.removeFromParent()
            let underlying = modal(containing: [fixture.base, original])
            fixture.runtime.root.addChild(underlying)
            path.draw(fixture.runtime)
            fixture.runtime.requestFocus(original)
            let outgoingAction = control("outgoing action")
            let outgoing = modal(containing: [outgoingAction])
            underlying.addChild(outgoing)
            path.draw(fixture.runtime)
            fixture.runtime.requestFocus(outgoingAction)
            outgoing.removeFromParent()

            fixture.runtime.schedulePresentationFocusRestoration(
                request(fixture, preferred: original, underlyingModal: underlying))
            path.draw(fixture.runtime)

            XCTAssertTrue(fixture.runtime.presentationModalSnapshot === underlying)
            XCTAssertTrue(fixture.runtime.focusedNode === original)
            XCTAssertFalse(fixture.first.isFocused)
        }
    }

    func testNewFocusIntentIncludingAnUnchangedTargetWinsOverPendingRestoration() async throws {
        for keepSameTarget in [false, true] {
            let fixture = makeFixture()
            fixture.runtime.requestFocus(fixture.second)
            let coordinator = fixture.runtime.retainedBuildCoordinator
            _ = try XCTUnwrap(coordinator.beginBuild())
            defer { if coordinator.isBuilding { coordinator.finishBuild() } }
            let expected = fixture.runtime.presentationFocusRevision
            fixture.runtime.schedulePresentationFocusRestoration(request(fixture, preferred: fixture.first))
            let chosen = keepSameTarget ? fixture.second : fixture.third

            fixture.runtime.requestFocus(chosen)
            XCTAssertGreaterThan(fixture.runtime.presentationFocusRevision, expected)
            coordinator.finishBuild()
            _ = fixture.runtime.renderFrame()

            XCTAssertTrue(fixture.runtime.focusedNode === chosen)
            XCTAssertFalse(fixture.first.isFocused)
        }
    }

    func testSameOwnerReplacementAndRevocationDoNotDeliverObsoleteRequests() async throws {
        let fixture = makeFixture()
        let coordinator = fixture.runtime.retainedBuildCoordinator
        let owner = FocusOwner()
        _ = try XCTUnwrap(coordinator.beginBuild())
        defer { if coordinator.isBuilding { coordinator.finishBuild() } }
        var firstEntries = 0
        fixture.first.onFocusEnter = { firstEntries += 1 }
        let obsolete = request(fixture, owner: owner, preferred: fixture.first)
        fixture.runtime.schedulePresentationFocusRestoration(obsolete)
        fixture.runtime.schedulePresentationFocusRestoration(
            request(fixture, owner: owner, preferred: fixture.second))
        obsolete.revoke()

        coordinator.finishBuild()
        _ = fixture.runtime.renderFrame()

        XCTAssertTrue(fixture.runtime.focusedNode === fixture.second)
        XCTAssertEqual(firstEntries, 0)
        _ = try XCTUnwrap(coordinator.beginBuild())
        var resolutions = 0
        var completions = 0
        let revoked = RetainedPresentationFocusRequest(
            owner: owner, preferred: fixture.first, underlyingModal: nil,
            expectedFocusRevision: fixture.runtime.presentationFocusRevision,
            isCurrent: { true },
            resolveBase: { [weak base = fixture.base] in
                resolutions += 1
                return base
            }, didFinish: { completions += 1 })
        fixture.runtime.schedulePresentationFocusRestoration(revoked)
        revoked.revoke()
        XCTAssertEqual(completions, 0, "Revocation marks admission without invoking cleanup")
        coordinator.finishBuild()
        _ = fixture.runtime.renderFrame()

        XCTAssertTrue(fixture.runtime.focusedNode === fixture.second)
        XCTAssertEqual(firstEntries, 0)
        XCTAssertEqual(resolutions, 0)
        XCTAssertEqual(completions, 1)
    }

    func testRestorationWaitsForAnIndependentlyFinishedDeferredBuildAndFreshLayout() async throws {
        for path in PaintPath.allCases {
            let fixture = makeFixture(path)
            let coordinator = fixture.runtime.retainedBuildCoordinator
            let deferredOwner = FocusOwner()
            _ = try XCTUnwrap(coordinator.beginBuild())
            defer { if coordinator.isBuilding { coordinator.finishBuild() } }
            var events: [String] = []
            fixture.first.onFocusEnter = { events.append("focus") }
            fixture.base.onLayout = { _ in events.append("layout") }
            let pending = RetainedPresentationFocusRequest(
                owner: FocusOwner(), preferred: fixture.first, underlyingModal: nil,
                expectedFocusRevision: fixture.runtime.presentationFocusRevision,
                isCurrent: { true },
                resolveBase: { [weak base = fixture.base, weak first = fixture.first] in
                    XCTAssertTrue(coordinator.isBuildSettled)
                    XCTAssertEqual(first?.resolvedFrame.size.width, 180)
                    events.append("resolve")
                    return base
                })
            fixture.runtime.schedulePresentationFocusRestoration(pending)
            coordinator.scheduleWhenIdle(for: deferredOwner) {
                events.append("deferred.begin")
                XCTAssertNotNil(coordinator.beginBuild())
                fixture.first.frame.size.width = 150
            }

            coordinator.finishBuild()
            path.draw(fixture.runtime)

            XCTAssertTrue(coordinator.isBuilding)
            XCTAssertFalse(events.contains("resolve"))
            XCTAssertFalse(events.contains("focus"))
            fixture.first.frame.size.width = 180
            events.append("deferred.end")
            coordinator.finishBuild()
            path.draw(fixture.runtime)

            XCTAssertTrue(fixture.runtime.focusedNode === fixture.first)
            let end = try XCTUnwrap(events.firstIndex(of: "deferred.end"))
            let focus = try XCTUnwrap(events.firstIndex(of: "focus"))
            XCTAssertLessThan(end, try XCTUnwrap(events.firstIndex(of: "resolve")))
            XCTAssertTrue(
                events.enumerated().contains {
                    $0.offset > end && $0.offset < focus && $0.element == "layout"
                })
            XCTAssertEqual(events.filter { $0 == "focus" }.count, 1)
        }
    }

    func testReconciliationCompletionRunsBeforeRestoration() async {
        let fixture = makeFixture()
        var events: [String] = []
        fixture.first.onFocusEnter = { events.append("focus") }
        fixture.runtime.beginLongPressReconciliation()
        fixture.runtime.schedulePresentationFocusRestoration(request(fixture, preferred: fixture.first))
        fixture.runtime.afterRetainedCallbacks { events.append("completion") }
        _ = fixture.runtime.renderScene()
        XCTAssertTrue(events.isEmpty)

        fixture.runtime.endLongPressReconciliation()
        _ = fixture.runtime.renderScene()

        XCTAssertEqual(events, ["completion", "focus"])
        XCTAssertTrue(fixture.runtime.focusedNode === fixture.first)
    }

    func testActivatingEnterDoesNotReachTheRestoredControlEvenAfterANestedRender() async {
        for path in PaintPath.allCases {
            for rendersDuringActivation in [false, true] {
                let fixture = makeFixture(path)
                let action = control("alert action")
                let outgoing = modal(containing: [action])
                fixture.runtime.root.addChild(outgoing)
                path.draw(fixture.runtime)
                fixture.runtime.requestFocus(action)
                var activations = 0
                var receivedKeys = 0
                fixture.first.onKeyDown = { _ in receivedKeys += 1 }
                action.onActivate = {
                    [
                        weak runtime = fixture.runtime, weak base = fixture.base,
                        weak preferred = fixture.first, weak outgoing
                    ] in
                    guard let runtime else { return }
                    activations += 1
                    outgoing?.removeFromParent()
                    runtime.schedulePresentationFocusRestoration(
                        RetainedPresentationFocusRequest(
                            owner: FocusOwner(), preferred: preferred, underlyingModal: nil,
                            expectedFocusRevision: runtime.presentationFocusRevision,
                            isCurrent: { true }, resolveBase: { [weak base] in base }))
                    if rendersDuringActivation { path.draw(runtime) }
                    XCTAssertFalse(runtime.focusedNode === preferred)
                }

                fixture.runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.enter.rawValue))

                XCTAssertEqual(activations, 1)
                XCTAssertEqual(receivedKeys, 0)
                XCTAssertFalse(fixture.first.isFocused)
                XCTAssertTrue(fixture.runtime.isDirty, "The key dispatch leaves a real rendering opportunity")
                path.draw(fixture.runtime)
                XCTAssertTrue(fixture.runtime.focusedNode === fixture.first)
                XCTAssertEqual(receivedKeys, 0, "The activating key belongs only to the outgoing alert")
                fixture.runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.enter.rawValue))
                XCTAssertEqual(receivedKeys, 1, "Later keys reach the restored control normally")
            }
        }
    }

    func testDismissingEscapeRestoresAfterTrailingCleanupWithoutReachingTheBackground() async {
        for path in PaintPath.allCases {
            for rendersDuringDismissal in [false, true] {
                let fixture = makeFixture(path)
                let action = control("alert action")
                let outgoing = modal(containing: [action])
                fixture.runtime.root.addChild(outgoing)
                path.draw(fixture.runtime)
                fixture.runtime.requestFocus(action)
                var dismissals = 0
                var receivedKeys = 0
                var completions = 0
                fixture.first.onKeyDown = { _ in receivedKeys += 1 }
                action.onKeyDown = {
                    [
                        weak runtime = fixture.runtime, weak base = fixture.base,
                        weak preferred = fixture.first, weak outgoing
                    ] event in
                    guard event.key == .escape, let runtime else { return }
                    dismissals += 1
                    outgoing?.removeFromParent()
                    XCTAssertNil(runtime.focusedNode, "Normal subtree removal releases the outgoing focus")
                    runtime.schedulePresentationFocusRestoration(
                        RetainedPresentationFocusRequest(
                            owner: FocusOwner(), preferred: preferred, underlyingModal: nil,
                            expectedFocusRevision: runtime.presentationFocusRevision,
                            isCurrent: { true }, resolveBase: { [weak base] in base },
                            didFinish: { completions += 1 }))
                    if rendersDuringDismissal { path.draw(runtime) }
                    XCTAssertFalse(runtime.focusedNode === preferred)
                }

                fixture.runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.escape.rawValue))

                XCTAssertEqual(dismissals, 1)
                XCTAssertEqual(receivedKeys, 0)
                XCTAssertEqual(completions, 0)
                XCTAssertFalse(fixture.first.isFocused)
                XCTAssertTrue(fixture.runtime.isDirty)
                path.draw(fixture.runtime)
                XCTAssertTrue(
                    fixture.runtime.focusedNode === fixture.first,
                    "Trailing Escape cleanup must not retire the request queued after removal")
                XCTAssertEqual(receivedKeys, 0, "The dismissing Escape belongs only to the outgoing alert")
                XCTAssertEqual(completions, 1)
                path.draw(fixture.runtime)
                XCTAssertEqual(completions, 1)
            }
        }
    }

    func testResolverCanReplaceTheQueueWithoutLosingTheNewRequest() async throws {
        let fixture = makeFixture()
        let coordinator = fixture.runtime.retainedBuildCoordinator
        _ = try XCTUnwrap(coordinator.beginBuild())
        defer { if coordinator.isBuilding { coordinator.finishBuild() } }
        let owner = FocusOwner()
        let replacement = request(fixture, owner: owner, preferred: fixture.second)
        var resolutions = 0
        var firstEntries = 0
        fixture.first.onFocusEnter = { firstEntries += 1 }
        let original = RetainedPresentationFocusRequest(
            owner: owner, preferred: fixture.first, underlyingModal: nil,
            expectedFocusRevision: fixture.runtime.presentationFocusRevision,
            isCurrent: { true },
            resolveBase: { [weak runtime = fixture.runtime, weak base = fixture.base] in
                resolutions += 1
                runtime?.schedulePresentationFocusRestoration(replacement)
                return base
            })
        fixture.runtime.schedulePresentationFocusRestoration(original)

        coordinator.finishBuild()
        _ = fixture.runtime.renderFrame()
        _ = fixture.runtime.renderFrame()

        XCTAssertEqual(resolutions, 1)
        XCTAssertEqual(firstEntries, 0)
        XCTAssertTrue(fixture.runtime.focusedNode === fixture.second)
    }

    func testResolverStartedBuildParksTheSameRequestUntilIndependentSettlement() async {
        for path in PaintPath.allCases {
            let fixture = makeFixture(path)
            let coordinator = fixture.runtime.retainedBuildCoordinator
            defer { if coordinator.isBuilding { coordinator.finishBuild() } }
            var resolutions = 0
            var entries = 0
            var completions = 0
            var startedBuild = false
            fixture.first.onFocusEnter = { [weak first = fixture.first] in
                entries += 1
                XCTAssertEqual(first?.resolvedFrame.size.width, 180)
            }
            let pending = RetainedPresentationFocusRequest(
                owner: FocusOwner(), preferred: fixture.first, underlyingModal: nil,
                expectedFocusRevision: fixture.runtime.presentationFocusRevision,
                isCurrent: { true },
                resolveBase: { [weak base = fixture.base, weak first = fixture.first] in
                    resolutions += 1
                    if !startedBuild {
                        startedBuild = true
                        XCTAssertNotNil(coordinator.beginBuild())
                    } else {
                        XCTAssertTrue(coordinator.isBuildSettled)
                        XCTAssertEqual(first?.resolvedFrame.size.width, 180)
                    }
                    return base
                }, didFinish: { completions += 1 })

            fixture.runtime.schedulePresentationFocusRestoration(pending)
            path.draw(fixture.runtime)

            XCTAssertTrue(startedBuild)
            XCTAssertTrue(coordinator.isBuilding)
            XCTAssertEqual(resolutions, 1)
            XCTAssertEqual(entries, 0)
            XCTAssertEqual(completions, 0, "A resolver-created build parks rather than consumes the request")
            XCTAssertFalse(fixture.first.isFocused)
            fixture.first.frame.size.width = 180
            coordinator.finishBuild()
            path.draw(fixture.runtime)

            XCTAssertTrue(fixture.runtime.focusedNode === fixture.first)
            XCTAssertGreaterThanOrEqual(resolutions, 2, "Resolve the accepted base again after the build")
            XCTAssertEqual(entries, 1)
            XCTAssertEqual(completions, 1)
            path.draw(fixture.runtime)
            XCTAssertEqual(entries, 1)
            XCTAssertEqual(completions, 1)
        }
    }

    func testResolverRechecksFocusModalAndCloseAfterApplicationCode() async {
        for mutation in 0..<3 {
            let fixture = makeFixture()
            let replacement = modal(containing: [control("replacement")])
            var firstEntries = 0
            var resolutions = 0
            fixture.first.onFocusEnter = { firstEntries += 1 }
            let pending = RetainedPresentationFocusRequest(
                owner: FocusOwner(), preferred: fixture.first, underlyingModal: nil,
                expectedFocusRevision: fixture.runtime.presentationFocusRevision,
                isCurrent: { true },
                resolveBase: {
                    [
                        weak runtime = fixture.runtime, weak base = fixture.base,
                        weak second = fixture.second, weak replacement
                    ] in
                    resolutions += 1
                    guard resolutions == 1 else { return base }
                    switch mutation {
                    case 0: runtime?.requestFocus(second)
                    case 1: if let replacement { runtime?.root.addChild(replacement) }
                    default: runtime?.stopRenderLifecycleCallbacks()
                    }
                    return base
                })

            fixture.runtime.schedulePresentationFocusRestoration(pending)
            _ = fixture.runtime.renderScene()
            _ = fixture.runtime.renderScene()

            XCTAssertEqual(firstEntries, 0, "resolver mutation \(mutation)")
            XCTAssertFalse(fixture.first.isFocused)
            if mutation == 0 { XCTAssertTrue(fixture.runtime.focusedNode === fixture.second) }
            if mutation == 1 { XCTAssertTrue(fixture.runtime.presentationModalSnapshot === replacement) }
            if mutation == 2 {
                XCTAssertFalse(fixture.runtime.presentationActionsAreAvailable)
                fixture.runtime.cancelRenderLifecycleTasks()
            }
        }
    }

    func testNewFocusFromExitOrEnterWinsWithoutStaleAccessibilityCompletion() async {
        for path in PaintPath.allCases {
            for reenterFromExit in [true, false] {
                let fixture = makeFixture(path)
                fixture.runtime.requestFocus(fixture.second)
                var didReenter = false
                var accessibilityEvents: [String] = []
                fixture.runtime.onAccessibilityFocusChanged = {
                    accessibilityEvents.append($0?.accessibilityLabel ?? "nil")
                }
                let reenter = { [weak runtime = fixture.runtime, weak third = fixture.third] in
                    guard !didReenter else { return }
                    didReenter = true
                    runtime?.requestFocus(third)
                }
                if reenterFromExit {
                    fixture.second.onFocusExit = reenter
                } else {
                    fixture.first.onFocusEnter = reenter
                }

                fixture.runtime.schedulePresentationFocusRestoration(request(fixture, preferred: fixture.first))
                path.draw(fixture.runtime)

                XCTAssertTrue(didReenter)
                XCTAssertTrue(fixture.runtime.focusedNode === fixture.third)
                XCTAssertFalse(fixture.first.isFocused)
                XCTAssertFalse(fixture.second.isFocused)
                XCTAssertEqual(accessibilityEvents, ["third"])
                path.draw(fixture.runtime)
                XCTAssertEqual(accessibilityEvents, ["third"])
            }
        }
    }

    func testSameTargetIntentFromEnterCompletesFocusAndAccessibilityExactlyOnce() async {
        for path in PaintPath.allCases {
            let fixture = makeFixture(path)
            fixture.runtime.requestFocus(fixture.second)
            var entries = 0
            var completions = 0
            var didReenter = false
            var accessibilityEvents: [String] = []
            fixture.runtime.onAccessibilityFocusChanged = {
                accessibilityEvents.append($0?.accessibilityLabel ?? "nil")
            }
            fixture.first.onFocusEnter = { [weak runtime = fixture.runtime, weak first = fixture.first] in
                entries += 1
                guard !didReenter else { return }
                didReenter = true
                runtime?.requestFocus(first)
            }

            fixture.runtime.schedulePresentationFocusRestoration(
                request(fixture, preferred: fixture.first, didFinish: { completions += 1 }))
            path.draw(fixture.runtime)

            XCTAssertTrue(didReenter)
            XCTAssertTrue(fixture.runtime.focusedNode === fixture.first)
            XCTAssertTrue(fixture.first.isFocused)
            XCTAssertFalse(fixture.second.isFocused)
            XCTAssertEqual(entries, 1, "A newer same-target intent must not enter the target twice")
            XCTAssertEqual(accessibilityEvents, ["first"])
            XCTAssertEqual(completions, 1)
            path.draw(fixture.runtime)
            XCTAssertEqual(entries, 1)
            XCTAssertEqual(accessibilityEvents, ["first"])
            XCTAssertEqual(completions, 1)
        }
    }

    func testAwayAndBackFocusFromEnterDoesNotDuplicateAccessibilityCompletion() async {
        for path in PaintPath.allCases {
            let fixture = makeFixture(path)
            fixture.runtime.requestFocus(fixture.second)
            var entries = 0
            var completions = 0
            var accessibilityEvents: [String] = []
            fixture.runtime.onAccessibilityFocusChanged = {
                accessibilityEvents.append($0?.accessibilityLabel ?? "nil")
            }
            fixture.first.onFocusEnter = {
                [weak runtime = fixture.runtime, weak first = fixture.first, weak third = fixture.third] in
                guard let runtime, let first, let third else { return }
                entries += 1
                switch entries {
                case 1:
                    runtime.requestFocus(third)
                    runtime.requestFocus(first)
                case 2:
                    runtime.requestFocus(first)
                default:
                    XCTFail("Reaffirming the nested entry must not enter the target again")
                }
            }

            fixture.runtime.schedulePresentationFocusRestoration(
                request(fixture, preferred: fixture.first, didFinish: { completions += 1 }))
            path.draw(fixture.runtime)

            XCTAssertTrue(fixture.runtime.focusedNode === fixture.first)
            XCTAssertTrue(fixture.first.isFocused)
            XCTAssertFalse(fixture.second.isFocused)
            XCTAssertFalse(fixture.third.isFocused)
            XCTAssertEqual(entries, 2)
            XCTAssertEqual(
                accessibilityEvents, ["third", "first"],
                "The suspended outer restoration must not complete the returned target a second time")
            XCTAssertEqual(completions, 1)
            path.draw(fixture.runtime)
            XCTAssertEqual(entries, 2)
            XCTAssertEqual(accessibilityEvents, ["third", "first"])
            XCTAssertEqual(completions, 1)
        }
    }

    func testExitReentryClearsThePreviousControlsFocusedChrome() async {
        for path in PaintPath.allCases {
            let fixture = makeFixture(path)
            fixture.second.interactionSurface = RetainedInteractionSurface(
                idleBackground: .black, focusedBackground: .white,
                idleBorder: .black, focusedBorder: .white,
                idleShadow: .clear, focusedShadow: .white,
                focusRingColor: .white, focusRingWidth: 4,
                hoverDuration: 0, pressDuration: 0, focusDuration: 0)
            fixture.runtime.requestFocus(fixture.second)
            XCTAssertEqual(fixture.second.backgroundColor, .white)
            XCTAssertEqual(fixture.second.borderColor, .white)
            XCTAssertEqual(fixture.second.shadowColor, .white)
            XCTAssertEqual(fixture.second.outlineColor, .white)
            XCTAssertEqual(fixture.second.outlineWidth, 4)
            var didReenter = false
            fixture.second.onFocusExit = { [weak runtime = fixture.runtime, weak third = fixture.third] in
                guard !didReenter else { return }
                didReenter = true
                runtime?.requestFocus(third)
            }

            fixture.runtime.schedulePresentationFocusRestoration(request(fixture, preferred: fixture.first))
            path.draw(fixture.runtime)

            XCTAssertTrue(didReenter)
            XCTAssertTrue(fixture.runtime.focusedNode === fixture.third)
            XCTAssertFalse(fixture.first.isFocused)
            XCTAssertFalse(fixture.second.isFocused)
            XCTAssertEqual(fixture.runtime.interactionPhase(for: fixture.second), .idle)
            XCTAssertEqual(fixture.second.backgroundColor, .black)
            XCTAssertEqual(fixture.second.borderColor, .black)
            XCTAssertEqual(fixture.second.shadowColor, .clear)
            XCTAssertEqual(fixture.second.outlineColor, .clear)
            XCTAssertEqual(fixture.second.outlineWidth, 0)
        }
    }

    func testModalOrCloseFromExitOrEnterDoesNotResurrectTheInterruptedTarget() async {
        for reenterFromExit in [true, false] {
            for closes in [false, true] {
                let fixture = makeFixture()
                let replacement = modal(containing: [control("replacement")])
                fixture.runtime.requestFocus(fixture.second)
                var accessibilityEvents: [String] = []
                var didReenter = false
                fixture.runtime.onAccessibilityFocusChanged = {
                    accessibilityEvents.append($0?.accessibilityLabel ?? "nil")
                }
                let reenter = { [weak runtime = fixture.runtime, weak replacement] in
                    guard !didReenter else { return }
                    didReenter = true
                    if closes {
                        runtime?.stopRenderLifecycleCallbacks()
                    } else if let replacement {
                        runtime?.root.addChild(replacement)
                    }
                }
                if reenterFromExit {
                    fixture.second.onFocusExit = reenter
                } else {
                    fixture.first.onFocusEnter = reenter
                }

                fixture.runtime.schedulePresentationFocusRestoration(request(fixture, preferred: fixture.first))
                _ = fixture.runtime.renderFrame()
                _ = fixture.runtime.renderFrame()

                XCTAssertTrue(didReenter)
                XCTAssertFalse(fixture.runtime.focusedNode === fixture.first)
                XCTAssertFalse(fixture.first.isFocused)
                XCTAssertFalse(accessibilityEvents.contains("first"))
                if closes {
                    XCTAssertFalse(fixture.runtime.presentationActionsAreAvailable)
                    fixture.runtime.cancelRenderLifecycleTasks()
                } else {
                    XCTAssertTrue(fixture.runtime.presentationModalSnapshot === replacement)
                }
            }
        }
    }

    func testCloseMarksAdmissionBeforeCleanupAndRejectsFutureRestoration() async throws {
        let fixture = makeFixture()
        let coordinator = fixture.runtime.retainedBuildCoordinator
        _ = try XCTUnwrap(coordinator.beginBuild())
        defer { if coordinator.isBuilding { coordinator.finishBuild() } }
        var resolutions = 0
        var completions = 0
        var entries = 0
        fixture.first.onFocusEnter = { entries += 1 }
        let pending = RetainedPresentationFocusRequest(
            owner: FocusOwner(), preferred: fixture.first, underlyingModal: nil,
            expectedFocusRevision: fixture.runtime.presentationFocusRevision,
            isCurrent: { true },
            resolveBase: { [weak base = fixture.base] in
                resolutions += 1
                return base
            }, didFinish: { completions += 1 })
        fixture.runtime.schedulePresentationFocusRestoration(pending)

        fixture.runtime.stopRenderLifecycleCallbacks()

        XCTAssertEqual(resolutions, 0)
        XCTAssertEqual(completions, 0, "The close admission step is mark-only")
        XCTAssertEqual(entries, 0)
        XCTAssertFalse(fixture.runtime.presentationActionsAreAvailable)
        fixture.runtime.cancelRenderLifecycleTasks()
        XCTAssertEqual(completions, 1)
        coordinator.finishBuild()
        fixture.runtime.schedulePresentationFocusRestoration(request(fixture, preferred: fixture.first))
        _ = fixture.runtime.renderScene()
        XCTAssertEqual(resolutions, 0)
        XCTAssertEqual(entries, 0)
        XCTAssertFalse(fixture.first.isFocused)
    }

    func testConstructionSnapshotsAndBusyAdmissionDoNotTriggerLayout() async throws {
        let fixture = makeFixture()
        let action = control("action")
        let overlay = modal(containing: [action])
        fixture.runtime.root.addChild(overlay)
        _ = fixture.runtime.renderFrame()
        var layouts = 0
        overlay.onLayout = { _ in layouts += 1 }
        action.frame.size.width = 150
        let coordinator = fixture.runtime.retainedBuildCoordinator
        _ = try XCTUnwrap(coordinator.beginBuild())
        defer { if coordinator.isBuilding { coordinator.finishBuild() } }

        XCTAssertTrue(fixture.runtime.presentationModalSnapshot === overlay)
        XCTAssertFalse(fixture.runtime.presentationActionsAreAvailable)
        XCTAssertFalse(fixture.runtime.permitsPresentationAction(on: action, within: overlay))
        XCTAssertEqual(layouts, 0)
        coordinator.finishBuild()
        fixture.runtime.beginLongPressReconciliation()
        XCTAssertFalse(fixture.runtime.presentationActionsAreAvailable)
        XCTAssertFalse(fixture.runtime.permitsPresentationAction(on: action, within: overlay))
        XCTAssertEqual(layouts, 0)
        fixture.runtime.endLongPressReconciliation()

        XCTAssertTrue(fixture.runtime.presentationActionsAreAvailable)
        XCTAssertTrue(fixture.runtime.presentationModalSnapshot === overlay)
        XCTAssertEqual(layouts, 0)
        XCTAssertTrue(fixture.runtime.permitsPresentationAction(on: action, within: overlay))
        XCTAssertGreaterThan(layouts, 0)
    }

    func testActionAdmissionRequiresCurrentEnabledAttachedInnermostModalControl() async {
        let fixture = makeFixture()
        let action = control("action")
        let disabled = control("disabled", y: 60)
        disabled.accessibilityRespondsToUserInteraction = false
        let hidden = control("hidden", y: 100)
        hidden.isHidden = true
        let overlay = modal(containing: [action, disabled, hidden])
        overlay.isHitTestVisible = false
        fixture.runtime.root.addChild(overlay)

        XCTAssertTrue(
            fixture.runtime.permitsPresentationAction(on: overlay, within: overlay),
            "Implicit dismissal uses the modal container without requiring a focusable button")
        XCTAssertTrue(fixture.runtime.permitsPresentationAction(on: action, within: overlay))
        XCTAssertFalse(fixture.runtime.permitsPresentationAction(on: disabled, within: overlay))
        XCTAssertFalse(fixture.runtime.permitsPresentationAction(on: hidden, within: overlay))
        XCTAssertFalse(fixture.runtime.permitsPresentationAction(on: control("detached"), within: overlay))
        XCTAssertFalse(fixture.runtime.permitsPresentationAction(on: fixture.first, within: fixture.base))
        let nestedAction = control("nested action")
        let nested = modal(containing: [nestedAction])
        overlay.addChild(nested)
        XCTAssertFalse(fixture.runtime.permitsPresentationAction(on: action, within: overlay))
        XCTAssertTrue(fixture.runtime.permitsPresentationAction(on: nestedAction, within: nested))
        nested.removeFromParent()
        XCTAssertFalse(fixture.runtime.permitsPresentationAction(on: nestedAction, within: nested))
        XCTAssertTrue(fixture.runtime.permitsPresentationAction(on: action, within: overlay))
    }

    func testActionAdmissionRejectsLayoutAndRenderReentryAndRechecksLayoutMutations() async {
        for path in PaintPath.allCases {
            let fixture = makeFixture(path)
            let action = control("action")
            let overlay = modal(containing: [action])
            var layoutAdmissions: [Bool] = []
            var renderAdmissions: [Bool] = []
            overlay.onLayout = { [weak runtime = fixture.runtime, weak action, weak overlay] _ in
                guard let runtime, let action, let overlay else { return }
                layoutAdmissions.append(runtime.presentationActionsAreAvailable)
                layoutAdmissions.append(runtime.permitsPresentationAction(on: action, within: overlay))
                action.accessibilityRespondsToUserInteraction = false
            }
            overlay.onAppear = { [weak runtime = fixture.runtime, weak action, weak overlay] in
                guard let runtime, let action, let overlay else { return }
                renderAdmissions.append(runtime.presentationActionsAreAvailable)
                renderAdmissions.append(runtime.permitsPresentationAction(on: action, within: overlay))
            }
            fixture.runtime.root.addChild(overlay)

            XCTAssertFalse(fixture.runtime.permitsPresentationAction(on: action, within: overlay))
            XCTAssertFalse(layoutAdmissions.isEmpty)
            XCTAssertTrue(layoutAdmissions.allSatisfy { !$0 })
            path.draw(fixture.runtime)
            XCTAssertEqual(renderAdmissions, [false, false])
            XCTAssertFalse(action.accessibilityRespondsToUserInteraction ?? true)
        }
    }

    func testEscapedRequestKeepsOnlyItsOwnerTokenAndWeakNodeReferences() async {
        weak var weakRuntime: RetainedViewRuntime?
        weak var weakPreferred: ViewNode?
        weak var weakModal: ViewNode?
        weak var weakOwner: FocusOwner?
        var escaped: RetainedPresentationFocusRequest?
        do {
            let preferred = control("preferred")
            let underlying = modal(containing: [preferred])
            let runtime = RetainedViewRuntime(root: underlying)
            let owner = FocusOwner()
            weakRuntime = runtime
            weakPreferred = preferred
            weakModal = underlying
            weakOwner = owner
            escaped = RetainedPresentationFocusRequest(
                owner: owner, preferred: preferred, underlyingModal: underlying,
                expectedFocusRevision: runtime.presentationFocusRevision,
                isCurrent: { true }, resolveBase: { [weak runtime] in runtime?.root })
        }

        XCTAssertNil(weakRuntime)
        XCTAssertNil(weakPreferred)
        XCTAssertNil(weakModal)
        XCTAssertNotNil(weakOwner)
        escaped?.revoke()
        escaped = nil
        XCTAssertNil(weakOwner)
    }
}
