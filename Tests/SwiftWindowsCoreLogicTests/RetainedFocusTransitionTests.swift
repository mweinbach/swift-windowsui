import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI

/// Ordinary focus requests remain available during construction and rendering.
/// Callback reentry must leave the newer transition in charge of focus and chrome.
@MainActor
final class RetainedFocusTransitionTests: XCTestCase {
    private enum PaintPath: CaseIterable {
        case frame
        case scene

        @MainActor
        func draw(_ runtime: RetainedViewRuntime) {
            switch self {
            case .frame: _ = runtime.renderFrame()
            case .scene: _ = runtime.renderScene()
            }
        }
    }

    func testFocusRevisionExhaustionCannotWrapOrIssueAnotherRevision() async {
        var revision = RetainedFocusRevision(value: UInt64.max - 1)
        XCTAssertFalse(revision.isExhausted)
        XCTAssertEqual(revision.advance(), UInt64.max)
        XCTAssertEqual(revision.value, UInt64.max)
        XCTAssertFalse(revision.isExhausted)

        XCTAssertNil(revision.advance())

        XCTAssertTrue(revision.isExhausted)
        XCTAssertEqual(revision.value, UInt64.max)
        XCTAssertNil(revision.advance())
        XCTAssertTrue(revision.isExhausted)
        XCTAssertEqual(revision.value, UInt64.max)
    }

    func testExitRedirectRunsTheOldExitOnceAndSkipsTheSupersededEntry() async {
        let fixture = FocusTransitionFixture()
        defer { fixture.retire() }
        fixture.runtime.requestFocus(fixture.first)
        var exits = 0
        var secondEntries = 0
        var thirdEntries = 0
        var notifications: [String] = []
        fixture.runtime.onAccessibilityFocusChanged = { notifications.append($0?.accessibilityLabel ?? "nil") }
        fixture.first.onFocusExit = { [weak runtime = fixture.runtime, weak third = fixture.third] in
            exits += 1
            guard exits == 1 else { return }
            runtime?.requestFocus(third)
        }
        fixture.second.onFocusEnter = { secondEntries += 1 }
        fixture.third.onFocusEnter = { thirdEntries += 1 }

        fixture.runtime.requestFocus(fixture.second)

        assertFocus(fixture.third, in: fixture)
        XCTAssertEqual(exits, 1)
        XCTAssertEqual(secondEntries, 0)
        XCTAssertEqual(thirdEntries, 1)
        XCTAssertEqual(notifications, ["third"])
        assertChrome(fixture.first, focused: false)
        assertChrome(fixture.third, focused: true)
    }

    func testEnterRedirectKeepsTheNewFocusEvenIfTheCallbackThenStopsTheRuntime() async {
        for stopsAfterRedirect in [false, true] {
            let fixture = FocusTransitionFixture()
            defer { fixture.retire() }
            fixture.runtime.requestFocus(fixture.first)
            var firstExits = 0
            var secondEntries = 0
            var secondExits = 0
            var thirdEntries = 0
            var notifications: [String] = []
            fixture.runtime.onAccessibilityFocusChanged = { notifications.append($0?.accessibilityLabel ?? "nil") }
            fixture.first.onFocusExit = { firstExits += 1 }
            fixture.second.onFocusExit = { secondExits += 1 }
            fixture.third.onFocusEnter = { thirdEntries += 1 }
            fixture.second.onFocusEnter = { [weak runtime = fixture.runtime, weak third = fixture.third] in
                secondEntries += 1
                guard secondEntries == 1 else { return }
                runtime?.requestFocus(third)
                if stopsAfterRedirect { runtime?.stopRenderLifecycleCallbacks() }
            }

            fixture.runtime.requestFocus(fixture.second)

            assertFocus(fixture.third, in: fixture)
            XCTAssertEqual(firstExits, 1)
            XCTAssertEqual(secondEntries, 1)
            XCTAssertEqual(secondExits, 1)
            XCTAssertEqual(thirdEntries, 1)
            XCTAssertEqual(notifications, ["third"])
            assertChrome(fixture.second, focused: false)
            assertChrome(fixture.third, focused: true)
        }
    }

    func testSameTargetAndNilToNilIntentsAdvanceRevisionWithoutRepeatingCallbacks() async {
        let fixture = FocusTransitionFixture()
        defer { fixture.retire() }
        var entries = 0
        var exits = 0
        var notifications: [String] = []
        fixture.first.onFocusEnter = { entries += 1 }
        fixture.first.onFocusExit = { exits += 1 }
        fixture.runtime.onAccessibilityFocusChanged = { notifications.append($0?.accessibilityLabel ?? "nil") }

        fixture.runtime.requestFocus(fixture.first)
        let focusedRevision = fixture.runtime.presentationFocusRevision
        fixture.runtime.requestFocus(fixture.first)
        XCTAssertGreaterThan(fixture.runtime.presentationFocusRevision, focusedRevision)
        XCTAssertEqual(entries, 1)
        XCTAssertEqual(exits, 0)
        XCTAssertEqual(notifications, ["first"])

        fixture.runtime.requestFocus(nil)
        let clearedRevision = fixture.runtime.presentationFocusRevision
        fixture.runtime.requestFocus(nil)

        XCTAssertGreaterThan(fixture.runtime.presentationFocusRevision, clearedRevision)
        assertFocus(nil, in: fixture)
        XCTAssertEqual(entries, 1)
        XCTAssertEqual(exits, 1)
        XCTAssertEqual(notifications, ["first", "nil"])
    }

    func testSameTargetRequestFromEntryCompletesTheEntryAndNotificationOnce() async {
        let fixture = FocusTransitionFixture()
        defer { fixture.retire() }
        fixture.runtime.requestFocus(fixture.first)
        var entries = 0
        var revisions: [UInt64] = []
        var notifications: [String] = []
        fixture.runtime.onAccessibilityFocusChanged = { notifications.append($0?.accessibilityLabel ?? "nil") }
        fixture.second.onFocusEnter = { [weak runtime = fixture.runtime, weak second = fixture.second] in
            entries += 1
            guard entries == 1, let runtime else { return }
            revisions.append(runtime.presentationFocusRevision)
            runtime.requestFocus(second)
            revisions.append(runtime.presentationFocusRevision)
        }

        fixture.runtime.requestFocus(fixture.second)

        assertFocus(fixture.second, in: fixture)
        XCTAssertEqual(entries, 1)
        XCTAssertEqual(revisions.count, 2)
        if revisions.count == 2 { XCTAssertGreaterThan(revisions[1], revisions[0]) }
        XCTAssertEqual(notifications, ["second"])
        assertChrome(fixture.second, focused: true)
    }

    func testAwayAndBackFromEntryDoesNotCompleteTheOuterTransitionAgain() async {
        let fixture = FocusTransitionFixture()
        defer { fixture.retire() }
        fixture.runtime.requestFocus(fixture.first)
        var firstExits = 0
        var secondEntries = 0
        var thirdEntries = 0
        var notifications: [String] = []
        fixture.runtime.onAccessibilityFocusChanged = { notifications.append($0?.accessibilityLabel ?? "nil") }
        fixture.first.onFocusExit = { firstExits += 1 }
        fixture.third.onFocusEnter = { thirdEntries += 1 }
        fixture.second.onFocusEnter = {
            [weak runtime = fixture.runtime, weak second = fixture.second, weak third = fixture.third] in
            secondEntries += 1
            guard let runtime else { return }
            switch secondEntries {
            case 1:
                runtime.requestFocus(third)
                runtime.requestFocus(second)
            case 2:
                runtime.requestFocus(second)
            default:
                XCTFail("A same-entry request must not recursively enter the target")
            }
        }

        fixture.runtime.requestFocus(fixture.second)

        assertFocus(fixture.second, in: fixture)
        XCTAssertEqual(firstExits, 1)
        XCTAssertEqual(secondEntries, 2)
        XCTAssertEqual(thirdEntries, 1)
        XCTAssertEqual(notifications, ["third", "second"])
        assertChrome(fixture.first, focused: false)
        assertChrome(fixture.third, focused: false)
        assertChrome(fixture.second, focused: true)
    }

    func testOldChromeClockReaffirmationCannotOverwriteTheNewFocusedColors() async {
        for restoresPresentation in [false, true] {
            let fixture = FocusTransitionFixture()
            defer { fixture.retire() }
            fixture.second.interactionSurface = nil
            fixture.third.interactionSurface = nil
            fixture.runtime.requestFocus(fixture.first)
            assertChrome(fixture.first, focused: true)
            var clockCalls = 0
            var redirects = 0
            var secondEntries = 0
            var completions = 0
            fixture.second.onFocusEnter = { secondEntries += 1 }
            fixture.runtime.clock = { [weak runtime = fixture.runtime, weak first = fixture.first] in
                clockCalls += 1
                guard redirects == 0 else { return 1_000 }
                redirects += 1
                runtime?.requestFocus(first)
                return 1_000
            }

            requestSecondFocus(in: fixture, restoringPresentation: restoresPresentation) { completions += 1 }

            XCTAssertGreaterThan(clockCalls, 0)
            XCTAssertEqual(redirects, 1)
            XCTAssertEqual(secondEntries, 0)
            XCTAssertEqual(completions, restoresPresentation ? 1 : 0)
            assertFocus(fixture.first, in: fixture)
            // Inspect immediately: another render could repair stale chrome writes.
            assertChrome(fixture.first, focused: true)
        }
    }

    func testNewChromeClockRedirectCannotOverwriteTheNewerIdleColors() async {
        for restoresPresentation in [false, true] {
            let fixture = FocusTransitionFixture()
            defer { fixture.retire() }
            fixture.first.interactionSurface = nil
            fixture.third.interactionSurface = nil
            fixture.runtime.requestFocus(fixture.first)
            var clockCalls = 0
            var redirects = 0
            var secondEntries = 0
            var completions = 0
            var notifications: [String] = []
            fixture.second.onFocusEnter = { secondEntries += 1 }
            fixture.runtime.onAccessibilityFocusChanged = { notifications.append($0?.accessibilityLabel ?? "nil") }
            fixture.runtime.clock = {
                [weak runtime = fixture.runtime, weak second = fixture.second, weak third = fixture.third] in
                clockCalls += 1
                guard redirects == 0, let runtime, let second,
                    runtime.focusedNode === second, second.isFocused
                else { return 1_000 }
                redirects += 1
                runtime.requestFocus(third)
                return 1_000
            }

            requestSecondFocus(in: fixture, restoringPresentation: restoresPresentation) { completions += 1 }

            XCTAssertGreaterThan(clockCalls, 0)
            XCTAssertEqual(redirects, 1)
            XCTAssertEqual(secondEntries, 1)
            XCTAssertEqual(completions, restoresPresentation ? 1 : 0)
            assertFocus(fixture.third, in: fixture)
            XCTAssertEqual(notifications, ["third"])
            assertChrome(fixture.second, focused: false)
        }
    }

    func testActiveBuildAllowsOrdinaryFocusAndAnUnchangedTargetIntent() async throws {
        let fixture = FocusTransitionFixture()
        defer { fixture.retire() }
        fixture.runtime.requestFocus(fixture.first)
        let coordinator = fixture.runtime.retainedBuildCoordinator
        _ = try XCTUnwrap(coordinator.beginBuild())
        defer { if coordinator.isBuilding { coordinator.finishBuild() } }
        var entries = 0
        var notifications: [String] = []
        fixture.second.onFocusEnter = { entries += 1 }
        fixture.runtime.onAccessibilityFocusChanged = { notifications.append($0?.accessibilityLabel ?? "nil") }

        fixture.runtime.requestFocus(fixture.second)
        assertFocus(fixture.second, in: fixture)
        let revision = fixture.runtime.presentationFocusRevision
        fixture.runtime.requestFocus(fixture.second)

        XCTAssertTrue(coordinator.isBuilding)
        XCTAssertGreaterThan(fixture.runtime.presentationFocusRevision, revision)
        XCTAssertEqual(entries, 1)
        XCTAssertEqual(notifications, ["second"])
        coordinator.finishBuild()
        assertFocus(fixture.second, in: fixture)
    }

    func testDetachedConstructionCandidateCanTakeFocusBeforeAttachment() async {
        let fixture = FocusTransitionFixture()
        defer { fixture.retire() }
        let candidate = FocusTransitionFixture.control("constructed", y: 140)
        var entries = 0
        var notifications: [String] = []
        candidate.onFocusEnter = { entries += 1 }
        fixture.runtime.onAccessibilityFocusChanged = { notifications.append($0?.accessibilityLabel ?? "nil") }
        XCTAssertNil(candidate.parent)

        fixture.runtime.requestFocus(candidate)

        XCTAssertTrue(fixture.runtime.focusedNode === candidate)
        XCTAssertTrue(candidate.isFocused)
        XCTAssertEqual(entries, 1)
        XCTAssertEqual(notifications, ["constructed"])
        fixture.root.addChild(candidate)
        _ = fixture.runtime.renderFrame()
        XCTAssertTrue(fixture.runtime.focusedNode === candidate)
        XCTAssertTrue(candidate.isFocused)
        XCTAssertEqual(entries, 1)
        XCTAssertEqual(notifications, ["constructed"])
    }

    func testOnAppearCanRequestFocusOnBothRenderPaths() async {
        for path in PaintPath.allCases {
            let fixture = FocusTransitionFixture(renderInitialFrame: false)
            defer { fixture.retire() }
            let trigger = ViewNode(frame: Rect(x: 0, y: 160, width: 10, height: 10))
            fixture.root.addChild(trigger)
            var appearances = 0
            var entries = 0
            var focusedInsideCallback: [Bool] = []
            var notifications: [String] = []
            fixture.second.onFocusEnter = { entries += 1 }
            fixture.runtime.onAccessibilityFocusChanged = { notifications.append($0?.accessibilityLabel ?? "nil") }
            trigger.onAppear = { [weak runtime = fixture.runtime, weak second = fixture.second] in
                appearances += 1
                guard appearances == 1, let runtime, let second else { return }
                runtime.requestFocus(second)
                focusedInsideCallback.append(runtime.focusedNode === second)
            }

            path.draw(fixture.runtime)

            XCTAssertEqual(appearances, 1)
            XCTAssertEqual(focusedInsideCallback, [true])
            assertFocus(fixture.second, in: fixture)
            XCTAssertEqual(entries, 1)
            XCTAssertEqual(notifications, ["second"])
            path.draw(fixture.runtime)
            XCTAssertEqual(appearances, 1)
            XCTAssertEqual(entries, 1)
            XCTAssertEqual(notifications, ["second"])
        }
    }

    func testOnAppearWithNodeCanRequestFocusOnBothRenderPaths() async {
        for path in PaintPath.allCases {
            let fixture = FocusTransitionFixture(renderInitialFrame: false)
            defer { fixture.retire() }
            var appearances = 0
            var entries = 0
            var focusedInsideCallback: [Bool] = []
            var notifications: [String] = []
            fixture.second.onFocusEnter = { entries += 1 }
            fixture.runtime.onAccessibilityFocusChanged = { notifications.append($0?.accessibilityLabel ?? "nil") }
            fixture.second.onAppearWithNode = { [weak runtime = fixture.runtime] node in
                appearances += 1
                guard appearances == 1, let runtime else { return }
                runtime.requestFocus(node)
                focusedInsideCallback.append(runtime.focusedNode === node)
            }

            path.draw(fixture.runtime)

            XCTAssertEqual(appearances, 1)
            XCTAssertEqual(focusedInsideCallback, [true])
            assertFocus(fixture.second, in: fixture)
            XCTAssertEqual(entries, 1)
            XCTAssertEqual(notifications, ["second"])
            path.draw(fixture.runtime)
            XCTAssertEqual(appearances, 1)
            XCTAssertEqual(entries, 1)
            XCTAssertEqual(notifications, ["second"])
        }
    }

    func testStoppedRuntimeRejectsNewFocusButWindowCleanupEmitsOneOldExit() async {
        let fixture = FocusTransitionFixture()
        defer { fixture.retire() }
        fixture.runtime.requestFocus(fixture.first)
        let revision = fixture.runtime.presentationFocusRevision
        var exits = 0
        var secondEntries = 0
        fixture.second.onFocusEnter = { secondEntries += 1 }
        fixture.first.onFocusExit = { [weak runtime = fixture.runtime, weak second = fixture.second] in
            exits += 1
            guard exits == 1 else { return }
            runtime?.requestFocus(second)
            runtime?.keyboardFocusDidLeaveWindow()
        }
        fixture.runtime.stopRenderLifecycleCallbacks()

        fixture.runtime.requestFocus(fixture.second)

        assertFocus(fixture.first, in: fixture)
        XCTAssertEqual(fixture.runtime.presentationFocusRevision, revision)
        XCTAssertEqual(exits, 0)
        XCTAssertEqual(secondEntries, 0)
        fixture.runtime.keyboardFocusDidLeaveWindow()
        assertFocus(nil, in: fixture)
        XCTAssertEqual(exits, 1)
        XCTAssertEqual(secondEntries, 0)
        fixture.runtime.keyboardFocusDidLeaveWindow()
        XCTAssertEqual(exits, 1)
        XCTAssertEqual(secondEntries, 0)
    }

    func testStoppingFromExitOrEntryWithdrawsOnlyTheInterruptedDestination() async {
        for stopsFromExit in [true, false] {
            let fixture = FocusTransitionFixture()
            defer { fixture.retire() }
            fixture.runtime.requestFocus(fixture.first)
            var firstExits = 0
            var secondEntries = 0
            var secondExits = 0
            var notifications: [String] = []
            fixture.runtime.onAccessibilityFocusChanged = { notifications.append($0?.accessibilityLabel ?? "nil") }
            fixture.first.onFocusExit = { [weak runtime = fixture.runtime] in
                firstExits += 1
                guard firstExits == 1 else { return }
                if stopsFromExit { runtime?.stopRenderLifecycleCallbacks() }
            }
            fixture.second.onFocusEnter = { [weak runtime = fixture.runtime] in
                secondEntries += 1
                guard secondEntries == 1 else { return }
                if !stopsFromExit { runtime?.stopRenderLifecycleCallbacks() }
            }
            fixture.second.onFocusExit = { secondExits += 1 }

            fixture.runtime.requestFocus(fixture.second)

            assertFocus(nil, in: fixture)
            XCTAssertEqual(firstExits, 1)
            XCTAssertEqual(secondEntries, stopsFromExit ? 0 : 1)
            XCTAssertEqual(secondExits, 0, "Terminal withdrawal must not synthesize a new exit callback")
            XCTAssertTrue(notifications.isEmpty)
        }
    }

    func testExitDetachingTheDestinationCannotReuseConstructionAdmission() async {
        let fixture = FocusTransitionFixture()
        defer { fixture.retire() }
        fixture.runtime.requestFocus(fixture.first)
        var exits = 0
        var entries = 0
        var notifications: [String] = []
        fixture.second.onFocusEnter = { entries += 1 }
        fixture.runtime.onAccessibilityFocusChanged = { notifications.append($0?.accessibilityLabel ?? "nil") }
        fixture.first.onFocusExit = { [weak second = fixture.second] in
            exits += 1
            guard exits == 1 else { return }
            second?.removeFromParent()
        }

        fixture.runtime.requestFocus(fixture.second)

        XCTAssertNil(fixture.second.parent)
        XCTAssertFalse(fixture.runtime.focusedNode === fixture.second)
        XCTAssertFalse(fixture.second.isFocused)
        XCTAssertEqual(exits, 1)
        XCTAssertEqual(entries, 0)
        XCTAssertFalse(notifications.contains("second"))
    }

    func testReplacingAnUninvokedCallbackReleasesItsCaptureAndLetsNewFocusWin() async {
        let fixture = FocusTransitionFixture()
        defer { fixture.retire() }
        fixture.runtime.requestFocus(fixture.first)
        var exits = 0
        var entries = 0
        var releases = 0
        var notifications: [String] = []
        fixture.runtime.onAccessibilityFocusChanged = { notifications.append($0?.accessibilityLabel ?? "nil") }
        let observer = installCapturedEntry(
            on: fixture.second, onEnter: { entries += 1 },
            onRelease: { [weak runtime = fixture.runtime, weak third = fixture.third] in
                releases += 1
                guard releases == 1 else { return }
                runtime?.requestFocus(third)
            })
        fixture.first.onFocusExit = { [weak second = fixture.second] in
            exits += 1
            guard exits == 1 else { return }
            second?.onFocusEnter = nil
        }
        XCTAssertNotNil(observer.payload)

        fixture.runtime.requestFocus(fixture.second)

        XCTAssertNil(observer.payload)
        XCTAssertEqual(releases, 1)
        XCTAssertEqual(exits, 1)
        XCTAssertEqual(entries, 0)
        assertFocus(fixture.third, in: fixture)
        XCTAssertEqual(notifications, ["third"])
    }

    func testEntryCallbackCaptureReleaseCanSupersedeItsOwnTransition() async {
        let fixture = FocusTransitionFixture()
        defer { fixture.retire() }
        fixture.runtime.requestFocus(fixture.first)
        var entries = 0
        var releases = 0
        var notifications: [String] = []
        fixture.runtime.onAccessibilityFocusChanged = { notifications.append($0?.accessibilityLabel ?? "nil") }
        let observer = installCapturedEntry(
            on: fixture.second,
            onEnter: { [weak second = fixture.second] in
                entries += 1
                guard entries == 1 else { return }
                second?.onFocusEnter = nil
            },
            onRelease: { [weak runtime = fixture.runtime, weak third = fixture.third] in
                releases += 1
                guard releases == 1 else { return }
                runtime?.requestFocus(third)
            })
        XCTAssertNotNil(observer.payload)

        fixture.runtime.requestFocus(fixture.second)

        XCTAssertNil(observer.payload)
        XCTAssertEqual(releases, 1)
        XCTAssertEqual(entries, 1)
        assertFocus(fixture.third, in: fixture)
        XCTAssertEqual(notifications, ["third"])
        assertChrome(fixture.second, focused: false)
    }

    func testCaptureReleaseAfterStopCannotRequestNewFocusBeforeTrustedCleanup() async {
        let fixture = FocusTransitionFixture()
        defer { fixture.retire() }
        fixture.runtime.requestFocus(fixture.first)
        var firstExits = 0
        var secondEntries = 0
        var thirdEntries = 0
        var releases = 0
        fixture.first.onFocusExit = { firstExits += 1 }
        fixture.third.onFocusEnter = { thirdEntries += 1 }
        let observer = installCapturedEntry(
            on: fixture.second, onEnter: { secondEntries += 1 },
            onRelease: { [weak runtime = fixture.runtime, weak third = fixture.third] in
                releases += 1
                guard releases == 1 else { return }
                runtime?.requestFocus(third)
            })
        fixture.runtime.stopRenderLifecycleCallbacks()

        fixture.second.onFocusEnter = nil

        XCTAssertNil(observer.payload)
        XCTAssertEqual(releases, 1)
        assertFocus(fixture.first, in: fixture)
        XCTAssertEqual(firstExits, 0)
        XCTAssertEqual(secondEntries, 0)
        XCTAssertEqual(thirdEntries, 0)
        fixture.runtime.keyboardFocusDidLeaveWindow()
        assertFocus(nil, in: fixture)
        XCTAssertEqual(firstExits, 1)
        XCTAssertEqual(thirdEntries, 0)
    }

    func testAccessibilityNotificationRedirectPreservesNewFocusWithoutDrainingLayout() async {
        let fixture = FocusTransitionFixture()
        defer { fixture.retire() }
        fixture.runtime.requestFocus(fixture.first)
        var redirects = 0
        var notifications: [String] = []
        var deferredCallbacks = 0
        fixture.runtime.onAccessibilityFocusChanged = {
            [weak runtime = fixture.runtime, weak second = fixture.second, weak third = fixture.third] node in
            notifications.append(node?.accessibilityLabel ?? "nil")
            guard node === second else { return }
            redirects += 1
            guard redirects == 1, let runtime else { return }
            runtime.requestFocus(third)
            runtime.scheduleAfterLayout(key: "ordinary-focus-notification") { deferredCallbacks += 1 }
        }

        fixture.runtime.requestFocus(fixture.second)

        assertFocus(fixture.third, in: fixture)
        XCTAssertEqual(redirects, 1)
        XCTAssertEqual(notifications, ["second", "third"])
        XCTAssertEqual(deferredCallbacks, 0)
        XCTAssertNotNil(fixture.runtime.resolvedLayoutFrame(of: fixture.root))
        XCTAssertEqual(deferredCallbacks, 1)
        assertFocus(fixture.third, in: fixture)
    }

    func testOrdinaryFocusDoesNotDrainAnUnrelatedPendingLayoutCallback() async {
        let fixture = FocusTransitionFixture()
        defer { fixture.retire() }
        var callbacks = 0
        fixture.runtime.scheduleAfterLayout(key: "ordinary-focus-pending") { callbacks += 1 }

        fixture.runtime.requestFocus(fixture.second)

        assertFocus(fixture.second, in: fixture)
        XCTAssertEqual(callbacks, 0)
        XCTAssertNotNil(fixture.runtime.resolvedLayoutFrame(of: fixture.root))
        XCTAssertEqual(callbacks, 1)
    }

    private func assertFocus(
        _ target: ViewNode?, in fixture: FocusTransitionFixture,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(fixture.runtime.focusedNode === target, file: file, line: line)
        for node in [fixture.first, fixture.second, fixture.third] {
            XCTAssertEqual(node.isFocused, node === target, file: file, line: line)
        }
    }

    private func assertChrome(
        _ node: ViewNode, focused: Bool, file: StaticString = #filePath, line: UInt = #line
    ) {
        let fill: Color = focused ? .white : .black
        let shadow: Color = focused ? .white : .clear
        XCTAssertEqual(node.backgroundColor, fill, file: file, line: line)
        XCTAssertEqual(node.borderColor, fill, file: file, line: line)
        XCTAssertEqual(node.shadowColor, shadow, file: file, line: line)
        XCTAssertEqual(node.outlineColor, shadow, file: file, line: line)
        XCTAssertEqual(node.outlineWidth, focused ? 4 : 0, file: file, line: line)
    }

    private func requestSecondFocus(
        in fixture: FocusTransitionFixture, restoringPresentation: Bool,
        didFinish: @escaping @MainActor () -> Void
    ) {
        if restoringPresentation {
            fixture.runtime.schedulePresentationFocusRestoration(
                RetainedPresentationFocusRequest(
                    owner: FocusTransitionRestorationOwner(), preferred: fixture.second, underlyingModal: nil,
                    expectedFocusRevision: fixture.runtime.presentationFocusRevision,
                    isCurrent: { true }, resolveBase: { [weak root = fixture.root] in root }, didFinish: didFinish))
        } else {
            fixture.runtime.requestFocus(fixture.second)
        }
    }

    private func installCapturedEntry(
        on node: ViewNode, onEnter: @escaping () -> Void, onRelease: @escaping @MainActor () -> Void
    ) -> FocusTransitionReleaseObserver {
        let observer = FocusTransitionReleaseObserver()
        let payload = FocusTransitionReleasePayload(onRelease)
        observer.payload = payload
        node.onFocusEnter = { [payload] in withExtendedLifetime(payload) { onEnter() } }
        return observer
    }
}

@MainActor
private final class FocusTransitionFixture {
    let root: ViewNode
    let runtime: RetainedViewRuntime
    let first: ViewNode
    let second: ViewNode
    let third: ViewNode

    init(renderInitialFrame: Bool = true) {
        first = Self.control("first", y: 10)
        second = Self.control("second", y: 50)
        third = Self.control("third", y: 90)
        root = ViewNode(frame: Rect(x: 0, y: 0, width: 320, height: 200), children: [first, second, third])
        runtime = RetainedViewRuntime(root: root)
        runtime.clock = { 1_000 }
        if renderInitialFrame { _ = runtime.renderFrame() }
    }

    static func control(_ label: String, y: Double) -> ViewNode {
        let node = ViewNode(
            frame: Rect(x: 20, y: y, width: 120, height: 28),
            isFocusable: true, isHitTestVisible: true,
            accessibilityLabel: label, accessibilityTraits: [.isButton])
        node.backgroundColor = .black
        node.borderColor = .black
        node.interactionSurface = RetainedInteractionSurface(
            idleBackground: .black, focusedBackground: .white,
            idleBorder: .black, focusedBorder: .white,
            idleShadow: .clear, focusedShadow: .white,
            focusRingColor: .white, focusRingWidth: 4,
            hoverDuration: 0, pressDuration: 0, focusDuration: 0)
        return node
    }

    func retire() {
        runtime.stopRenderLifecycleCallbacks()
        runtime.clock = { 1_000 }
        runtime.onAccessibilityFocusChanged = nil
        var nodes = [root, first, second, third]
        var seen = Set<ObjectIdentifier>()
        while let node = nodes.popLast() {
            guard seen.insert(ObjectIdentifier(node)).inserted else { continue }
            nodes.append(contentsOf: node.children)
            node.onFocusEnter = nil
            node.onFocusExit = nil
            node.onAppear = nil
            node.onAppearWithNode = nil
        }
        runtime.cancelRenderLifecycleTasks()
    }
}

private final class FocusTransitionRestorationOwner {}

@MainActor
private final class FocusTransitionReleaseObserver {
    weak var payload: FocusTransitionReleasePayload?
}

@MainActor
private final class FocusTransitionReleasePayload {
    private let onRelease: @MainActor () -> Void

    init(_ onRelease: @escaping @MainActor () -> Void) {
        self.onRelease = onRelease
    }

    isolated deinit { onRelease() }
}
