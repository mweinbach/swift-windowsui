import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// A new focus intent can complete an entered target without qualifying the
/// superseded strict caller. Clock callbacks and their captures are boundaries.
@MainActor
final class FocusClockCompletionTests: XCTestCase {
    private enum Mode: String, CaseIterable {
        case ordinary
        case strictSource
        case restoration
    }

    private enum Invalidation: String, CaseIterable {
        case stop
        case detach
    }

    func testNewChromeSameTargetIntentCompletesOnceAcrossAllFocusRoutes() async throws {
        for mode in Mode.allCases {
            let fixture = ClockCompletionFixture()
            defer { fixture.retire() }
            _ = installNewClock(in: fixture) { [weak fixture] in
                guard let fixture else { return }
                fixture.runtime.requestFocus(fixture.target)
            }

            let result = try requestTarget(in: fixture, mode: mode)

            assertOriginalStrictRejected(result, mode: mode)
            assertTargetCompletedOnce(fixture)
            XCTAssertEqual(fixture.probe.hookCalls, 1, mode.rawValue)
            XCTAssertEqual(fixture.probe.restorationCompletions, mode == .restoration ? 1 : 0)
        }
    }

    func testNewChromeAwayAndBackOwnsOnlyTheNewEntryAcrossAllFocusRoutes() async throws {
        for mode in Mode.allCases {
            let fixture = ClockCompletionFixture()
            defer { fixture.retire() }
            _ = installNewClock(in: fixture) { [weak fixture] in
                guard let fixture else { return }
                fixture.runtime.requestFocus(fixture.alternate)
                fixture.runtime.requestFocus(fixture.target)
            }

            let result = try requestTarget(in: fixture, mode: mode)

            assertOriginalStrictRejected(result, mode: mode)
            XCTAssertEqual(fixture.probe.hookCalls, 1, mode.rawValue)
            XCTAssertTrue(fixture.runtime.focusedNode === fixture.target)
            XCTAssertTrue(fixture.target.isFocused)
            XCTAssertFalse(fixture.previous.isFocused)
            XCTAssertFalse(fixture.alternate.isFocused)
            XCTAssertEqual(fixture.probe.targetEntries, 2)
            XCTAssertEqual(fixture.probe.targetExits, 1)
            XCTAssertEqual(fixture.probe.alternateEntries, 1)
            XCTAssertEqual(fixture.probe.notifications, ["alternate", "target"])
            XCTAssertEqual(fixture.probe.restorationCompletions, mode == .restoration ? 1 : 0)
            assertTargetChrome(fixture, focused: true)
        }
    }

    func testSelfReplacingClockCaptureSameTargetIntentCompletesOnceAcrossAllFocusRoutes() async throws {
        for mode in Mode.allCases {
            let fixture = ClockCompletionFixture()
            defer { fixture.retire() }
            let observer = try XCTUnwrap(
                installNewClock(in: fixture, fromCaptureCleanup: true) { [weak fixture] in
                    guard let fixture else { return }
                    fixture.runtime.requestFocus(fixture.target)
                })
            XCTAssertNotNil(observer.payload)

            let result = try requestTarget(in: fixture, mode: mode)

            assertOriginalStrictRejected(result, mode: mode)
            assertTargetCompletedOnce(fixture)
            XCTAssertEqual(fixture.probe.hookCalls, 1, mode.rawValue)
            XCTAssertEqual(fixture.probe.captureReleases, 1)
            XCTAssertNil(observer.payload)
            XCTAssertEqual(fixture.probe.restorationCompletions, mode == .restoration ? 1 : 0)
        }
    }

    func testClockAndCaptureCleanupStopOrDetachBlockStaleCompletion() async throws {
        for mode in Mode.allCases {
            for fromCaptureCleanup in [false, true] {
                for invalidation in Invalidation.allCases {
                    let fixture = ClockCompletionFixture()
                    defer { fixture.retire() }
                    let observer = installNewClock(in: fixture, fromCaptureCleanup: fromCaptureCleanup) {
                        [weak fixture] in
                        guard let fixture else { return }
                        switch invalidation {
                        case .stop: fixture.runtime.stopRenderLifecycleCallbacks()
                        case .detach: fixture.target.removeFromParent()
                        }
                    }
                    if let observer { XCTAssertNotNil(observer.payload) }

                    let result = try requestTarget(in: fixture, mode: mode)

                    let context = "\(mode), \(invalidation), capture cleanup: \(fromCaptureCleanup)"
                    assertOriginalStrictRejected(result, mode: mode)
                    XCTAssertEqual(fixture.probe.hookCalls, 1, context)
                    XCTAssertEqual(fixture.probe.targetEntries, 1, context)
                    XCTAssertFalse(fixture.runtime.focusedNode === fixture.target, context)
                    XCTAssertFalse(fixture.target.isFocused, context)
                    XCTAssertEqual(fixture.probe.notifications, invalidation == .detach ? ["nil"] : [], context)
                    XCTAssertEqual(fixture.probe.targetExits, invalidation == .detach ? 1 : 0, context)
                    XCTAssertEqual(fixture.probe.captureReleases, fromCaptureCleanup ? 1 : 0, context)
                    if let observer { XCTAssertNil(observer.payload) }
                    if invalidation == .detach { XCTAssertNil(fixture.target.parent) }
                }
            }
        }
    }

    func testClockAndCaptureCleanupDisablingTargetPreserveOnlyOrdinaryPolicy() async throws {
        for mode in Mode.allCases {
            for fromCaptureCleanup in [false, true] {
                let fixture = ClockCompletionFixture()
                defer { fixture.retire() }
                let observer = installNewClock(in: fixture, fromCaptureCleanup: fromCaptureCleanup) {
                    [weak target = fixture.target] in
                    target?.accessibilityRespondsToUserInteraction = false
                }
                if let observer { XCTAssertNotNil(observer.payload) }

                let result = try requestTarget(in: fixture, mode: mode)

                let context = "\(mode), capture cleanup: \(fromCaptureCleanup)"
                assertOriginalStrictRejected(result, mode: mode)
                XCTAssertEqual(fixture.probe.hookCalls, 1, context)
                XCTAssertEqual(fixture.probe.targetEntries, 1, context)
                XCTAssertEqual(fixture.target.accessibilityRespondsToUserInteraction, false)
                if mode == .ordinary {
                    // No newer ordinary request is introduced by this mutation.
                    // The original ordinary path keeps its existing disabled policy.
                    assertTargetCompletedOnce(fixture)
                } else {
                    XCTAssertFalse(fixture.runtime.focusedNode === fixture.target, context)
                    XCTAssertFalse(fixture.target.isFocused, context)
                    XCTAssertFalse(fixture.probe.notifications.contains("target"), context)
                }
                XCTAssertEqual(fixture.probe.captureReleases, fromCaptureCleanup ? 1 : 0, context)
                if let observer { XCTAssertNil(observer.payload) }
                XCTAssertEqual(fixture.probe.restorationCompletions, mode == .restoration ? 1 : 0)
            }
        }
    }

    func testFinalNotificationSameTargetIntentCannotEmitAnotherNotification() async throws {
        for mode in Mode.allCases {
            let fixture = ClockCompletionFixture()
            defer { fixture.retire() }
            let probe = fixture.probe
            var reaffirmations = 0
            fixture.runtime.onAccessibilityFocusChanged = { [weak fixture, probe] node in
                probe.notifications.append(node?.accessibilityLabel ?? "nil")
                guard let fixture, node === fixture.target else { return }
                reaffirmations += 1
                guard reaffirmations == 1 else { return }
                fixture.runtime.requestFocus(fixture.target)
            }

            let result = try requestTarget(in: fixture, mode: mode)

            assertOriginalStrictRejected(result, mode: mode)
            assertTargetCompletedOnce(fixture)
            XCTAssertEqual(reaffirmations, 1, mode.rawValue)
            XCTAssertEqual(fixture.probe.restorationCompletions, mode == .restoration ? 1 : 0)
        }
    }

    func testInitialAndFollowupQuerySameTargetIntentCannotRebaseTheStrictCaller() async throws {
        for isFollowupQuery in [false, true] {
            let fixture = ClockCompletionFixture()
            defer { fixture.retire() }
            var queryCalls = 0
            var revisionChanges: [Bool] = []
            let requestSameTarget: @MainActor () -> Void = { [weak fixture] in
                queryCalls += 1
                guard queryCalls == 1, let fixture else { return }
                let revision = fixture.runtime.presentationFocusRevision
                fixture.runtime.requestFocus(fixture.target)
                revisionChanges.append(fixture.runtime.presentationFocusRevision > revision)
            }
            if isFollowupQuery {
                _ = installNewClock(in: fixture) { [weak runtime = fixture.runtime] in
                    runtime?.scheduleAfterLayout(key: "focus-clock-followup-query", perform: requestSameTarget)
                }
            } else {
                fixture.runtime.scheduleAfterLayout(key: "focus-clock-initial-query", perform: requestSameTarget)
            }

            let result = try requestTarget(in: fixture, mode: .strictSource)

            XCTAssertEqual(result, false)
            XCTAssertEqual(queryCalls, 1)
            XCTAssertEqual(revisionChanges, [true])
            XCTAssertEqual(fixture.probe.hookCalls, isFollowupQuery ? 1 : 0)
            XCTAssertTrue(fixture.runtime.focusedNode === fixture.target)
            XCTAssertTrue(fixture.target.isFocused)
            XCTAssertEqual(fixture.probe.targetEntries, 1)
            // The initial query's ordinary transition completes independently.
            // A query during an existing entry cannot borrow that entry's completion.
            XCTAssertEqual(fixture.probe.notifications, isFollowupQuery ? [] : ["target"])
        }
    }

    func testOrdinaryReaffirmationFromEntryOrClockCompletesDuringAnActiveBuild() async throws {
        for fromEntry in [true, false] {
            let fixture = ClockCompletionFixture()
            defer { fixture.retire() }
            let coordinator = fixture.runtime.retainedBuildCoordinator
            defer { if coordinator.isBuilding { coordinator.finishBuild() } }
            let probe = fixture.probe
            var reaffirmations = 0
            let beginBuildAndReaffirm: @MainActor () -> Void = { [weak fixture] in
                reaffirmations += 1
                guard reaffirmations == 1, let fixture else { return }
                XCTAssertNotNil(fixture.runtime.retainedBuildCoordinator.beginBuild())
                fixture.runtime.requestFocus(fixture.target)
            }
            if fromEntry {
                fixture.target.onFocusEnter = { [probe] in
                    probe.targetEntries += 1
                    guard probe.targetEntries == 1 else { return }
                    beginBuildAndReaffirm()
                }
            } else {
                _ = installNewClock(in: fixture, action: beginBuildAndReaffirm)
            }

            let result = try requestTarget(in: fixture, mode: .strictSource)

            XCTAssertEqual(result, false)
            XCTAssertEqual(reaffirmations, 1)
            XCTAssertTrue(coordinator.isBuilding)
            assertTargetCompletedOnce(fixture)
            coordinator.finishBuild()
            XCTAssertEqual(probe.targetEntries, 1)
            XCTAssertEqual(probe.notifications, ["target"])
        }
    }

    func testRestorationEntryCannotBorrowCompletionThroughANestedStrictQuery() async throws {
        let fixture = ClockCompletionFixture()
        defer { fixture.retire() }
        let targetID = try fixture.targetID()
        let probe = fixture.probe
        var queryCalls = 0
        var nestedResults: [Bool] = []
        fixture.target.onFocusEnter = { [weak fixture, probe] in
            probe.targetEntries += 1
            guard probe.targetEntries == 1, let fixture else { return }
            fixture.runtime.scheduleAfterLayout(key: "focus-clock-restoration-nested-query") { [weak fixture] in
                queryCalls += 1
                guard queryCalls == 1, let fixture else { return }
                fixture.runtime.requestFocus(fixture.target)
            }
            nestedResults.append(fixture.source.uiaSetFocusResult(elementID: targetID))
        }

        let result = try requestTarget(in: fixture, mode: .restoration)

        XCTAssertNil(result)
        XCTAssertEqual(queryCalls, 1)
        XCTAssertEqual(nestedResults, [false])
        XCTAssertTrue(fixture.runtime.focusedNode === fixture.target)
        XCTAssertTrue(fixture.target.isFocused)
        XCTAssertEqual(probe.targetEntries, 1)
        XCTAssertTrue(probe.notifications.isEmpty)
        XCTAssertEqual(probe.restorationCompletions, 1)
    }

    private func requestTarget(in fixture: ClockCompletionFixture, mode: Mode) throws -> Bool? {
        switch mode {
        case .ordinary:
            fixture.runtime.requestFocus(fixture.target)
            return nil
        case .strictSource:
            return fixture.source.uiaSetFocusResult(elementID: try fixture.targetID())
        case .restoration:
            let probe = fixture.probe
            fixture.runtime.schedulePresentationFocusRestoration(
                RetainedPresentationFocusRequest(
                    owner: ClockCompletionRestorationOwner(), preferred: fixture.target, underlyingModal: nil,
                    expectedFocusRevision: fixture.runtime.presentationFocusRevision,
                    isCurrent: { true }, resolveBase: { [weak root = fixture.root] in root },
                    didFinish: { probe.restorationCompletions += 1 }))
            return nil
        }
    }

    private func installNewClock(
        in fixture: ClockCompletionFixture, fromCaptureCleanup: Bool = false,
        action: @escaping @MainActor () -> Void
    ) -> ClockCompletionCaptureObserver? {
        let probe = fixture.probe
        if fromCaptureCleanup {
            let observer = ClockCompletionCaptureObserver()
            let payload = ClockCompletionCapturePayload { [probe] in
                probe.captureReleases += 1
                guard probe.captureReleases == 1 else { return }
                action()
            }
            observer.payload = payload
            fixture.runtime.clock = {
                [weak runtime = fixture.runtime, weak target = fixture.target, payload, probe] in
                withExtendedLifetime(payload) {
                    probe.clockCalls += 1
                    guard probe.hookCalls == 0, let runtime, let target,
                        runtime.focusedNode === target, target.isFocused
                    else { return 1_000 }
                    probe.hookCalls += 1
                    // Do not preserve the old closure in a local or a teardown capture.
                    runtime.clock = { 1_000 }
                    return 1_000
                }
            }
            return observer
        }
        fixture.runtime.clock = { [weak runtime = fixture.runtime, weak target = fixture.target, probe] in
            probe.clockCalls += 1
            guard probe.hookCalls == 0, let runtime, let target,
                runtime.focusedNode === target, target.isFocused
            else { return 1_000 }
            probe.hookCalls += 1
            action()
            return 1_000
        }
        return nil
    }

    private func assertOriginalStrictRejected(
        _ result: Bool?, mode: Mode, file: StaticString = #filePath, line: UInt = #line
    ) {
        if mode == .strictSource {
            XCTAssertEqual(result, false, file: file, line: line)
        } else {
            XCTAssertNil(result, file: file, line: line)
        }
    }

    private func assertTargetCompletedOnce(
        _ fixture: ClockCompletionFixture, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(fixture.runtime.focusedNode === fixture.target, file: file, line: line)
        XCTAssertTrue(fixture.target.isFocused, file: file, line: line)
        XCTAssertFalse(fixture.previous.isFocused, file: file, line: line)
        XCTAssertFalse(fixture.alternate.isFocused, file: file, line: line)
        XCTAssertEqual(fixture.probe.targetEntries, 1, file: file, line: line)
        XCTAssertEqual(fixture.probe.targetExits, 0, file: file, line: line)
        XCTAssertEqual(fixture.probe.notifications, ["target"], file: file, line: line)
        assertTargetChrome(fixture, focused: true, file: file, line: line)
    }

    private func assertTargetChrome(
        _ fixture: ClockCompletionFixture, focused: Bool, file: StaticString = #filePath, line: UInt = #line
    ) {
        let fill: Color = focused ? .white : .black
        XCTAssertEqual(fixture.target.backgroundColor, fill, file: file, line: line)
        XCTAssertEqual(fixture.target.borderColor, fill, file: file, line: line)
        XCTAssertEqual(fixture.target.outlineColor, focused ? .white : .clear, file: file, line: line)
        XCTAssertEqual(fixture.target.outlineWidth, focused ? 4 : 0, file: file, line: line)
    }
}

@MainActor
private final class ClockCompletionFixture {
    let root: ViewNode
    let previous: ViewNode
    let target: ViewNode
    let alternate: ViewNode
    let runtime: RetainedViewRuntime
    let source: RuntimeUIAElementTreeSource
    let probe = ClockCompletionProbe()

    init() {
        previous = Self.control("previous", y: 10)
        target = Self.control("target", y: 50)
        alternate = Self.control("alternate", y: 90)
        target.interactionSurface = RetainedInteractionSurface(
            idleBackground: .black, focusedBackground: .white,
            idleBorder: .black, focusedBorder: .white,
            focusRingColor: .white, focusRingWidth: 4,
            hoverDuration: 0, pressDuration: 0, focusDuration: 0)
        root = ViewNode(frame: Rect(x: 0, y: 0, width: 320, height: 200), children: [previous, target, alternate])
        runtime = RetainedViewRuntime(root: root)
        runtime.clock = { 1_000 }
        source = RuntimeUIAElementTreeSource(runtime: runtime)
        _ = runtime.renderFrame()
        runtime.requestFocus(previous)
        XCTAssertTrue(runtime.focusedNode === previous)
        previous.onFocusExit = { [probe] in probe.previousExits += 1 }
        target.onFocusEnter = { [probe] in probe.targetEntries += 1 }
        target.onFocusExit = { [probe] in probe.targetExits += 1 }
        alternate.onFocusEnter = { [probe] in probe.alternateEntries += 1 }
        runtime.onAccessibilityFocusChanged = { [probe] node in
            probe.notifications.append(node?.accessibilityLabel ?? "nil")
        }
    }

    private static func control(_ label: String, y: Double) -> ViewNode {
        let node = ViewNode(
            frame: Rect(x: 20, y: y, width: 120, height: 28),
            isFocusable: true, isHitTestVisible: true,
            accessibilityLabel: label, accessibilityTraits: [.isButton])
        node.backgroundColor = .black
        node.borderColor = .black
        return node
    }

    func targetID() throws -> UInt64 {
        try XCTUnwrap(source.uiaElementSnapshots().first { $0.name == "target" }?.id)
    }

    func retire() {
        runtime.stopRenderLifecycleCallbacks()
        runtime.onAccessibilityFocusChanged = nil
        runtime.clock = { 1_000 }
        for node in [previous, target, alternate] {
            node.onFocusEnter = nil
            node.onFocusExit = nil
        }
        if runtime.retainedBuildCoordinator.isBuilding { runtime.retainedBuildCoordinator.finishBuild() }
        runtime.cancelRenderLifecycleTasks()
    }
}

@MainActor
private final class ClockCompletionProbe {
    var previousExits = 0
    var targetEntries = 0
    var targetExits = 0
    var alternateEntries = 0
    var notifications: [String] = []
    var clockCalls = 0
    var hookCalls = 0
    var captureReleases = 0
    var restorationCompletions = 0
}

private final class ClockCompletionRestorationOwner {}

@MainActor
private final class ClockCompletionCaptureObserver {
    weak var payload: ClockCompletionCapturePayload?
}

@MainActor
private final class ClockCompletionCapturePayload {
    private let onRelease: @MainActor () -> Void

    init(_ onRelease: @escaping @MainActor () -> Void) {
        self.onRelease = onRelease
    }

    isolated deinit { onRelease() }
}
