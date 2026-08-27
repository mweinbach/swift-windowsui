import CUIAInterop
import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import WinSDK
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
private final class WindowClosePolicyModel: ObservableObject {
    @Published var behavior: WindowInteractionBehavior = .automatic
    @Published var includesModifier = true
    @Published var revision = 0
}

@MainActor
private struct WindowClosePolicyContent: View {
    @ObservedObject var model: WindowClosePolicyModel

    var body: some View {
        VStack {
            if model.includesModifier {
                Text("Policy")
                    .accessibilityIdentifier("policy")
                    .windowDismissBehavior(model.behavior)
            } else {
                Text("Policy")
                    .accessibilityIdentifier("policy")
            }
            Text("Revision \(model.revision)")
        }
    }
}

@MainActor
private struct RemovedWindowClosePolicyContent: View {
    @ObservedObject var model: WindowClosePolicyModel

    var body: some View {
        VStack {
            if model.includesModifier {
                Text("Close guard")
                    .id("close-guard")
                    .windowDismissBehavior(.disabled)
                    .transition(.opacity)
            }
            Text("Window content")
                .id("window-content")
        }
    }
}

@MainActor
private struct WindowCloseGestureStateContent: View {
    @GestureState var isHolding = false
    var onUpdating: @MainActor (Bool) -> Void = { _ in }
    var onRecognized: @MainActor () -> Void = {}

    var body: some View {
        Text(isHolding ? "Holding" : "Ready")
            .frame(width: 120, height: 60)
            .accessibilityIdentifier("policy")
            .gesture(
                LongPressGesture(minimumDuration: 1)
                    .updating($isHolding) { value, state, _ in
                        state = value
                        onUpdating(value)
                    }
                    .onEnded { _ in onRecognized() }
            )
    }
}

@MainActor
private final class RefusingNeutralCloseHost: PlatformWindowHost {
    private(set) var requests = 0
    private(set) var closes = 0

    func platformWindowShouldClose(_ window: any PlatformWindow) -> Bool {
        requests += 1
        return false
    }

    func platformWindow(_ window: any PlatformWindow, didReceive event: PlatformWindowEvent) {
        if case .willClose = event { closes += 1 }
    }
}

@MainActor
final class WindowDismissBehaviorTests: XCTestCase {
    private struct Harness {
        let host: WinSwiftUIWindowHost
        let renderer: FakeRenderBackend
        let batchRenderer: FakeBatchRenderBackend
        var window: Win32Window { host.platformWindow }
    }

    private enum StartFailure: Error { case expected }

    private func configuration<Content: View>(_ content: Content, id: String = "main") -> WindowGroupConfiguration {
        WindowGroupConfiguration(
            title: "Window close policy", size: IntSize(width: 220, height: 140), clearColor: .black,
            content: [AnyView(content)], windowID: id)
    }

    private func makeHost<Content: View>(_ content: Content, native: Bool = false) throws -> Harness {
        let renderer = FakeRenderBackend()
        let batch = FakeBatchRenderBackend()
        let config = configuration(content)
        let window = Win32Window(title: config.title, clientSize: config.size)
        window.postsQuitMessageOnDestroy = false
        let surface = SurfaceDescriptor(
            windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
            pixelSize: config.size, scaleFactor: 1)
        let host = WinSwiftUIWindowHost(
            configuration: config, platformWindow: window, renderer: renderer, batchRenderer: batch,
            surfaceDescriptorProvider: { window in
                guard native else { return surface }
                guard let handle = window.nativeHandle else { return nil }
                return SurfaceDescriptor(
                    windowHandle: handle, pixelSize: window.currentClientSize(),
                    scaleFactor: window.effectiveScaleFactor)
            },
            startupProbeConfiguration: nil)
        if native {
            do {
                try window.create()
            } catch {
                throw XCTSkip("This environment cannot create an owned test window: \(error)")
            }
        } else {
            host.windowDidCreate(window)
        }
        host.resetObservabilityCounters()
        return Harness(host: host, renderer: renderer, batchRenderer: batch)
    }

    private func tearDown(_ harness: Harness) {
        if let raw = harness.window.nativeHandle?.rawPointer {
            DestroyWindow(HWND(bitPattern: Int(bitPattern: raw)))
        } else {
            harness.host.windowWillClose(harness.window)
        }
    }

    private func nativeHandle(_ window: Win32Window) throws -> HWND {
        let raw = try XCTUnwrap(window.nativeHandle?.rawPointer)
        return try XCTUnwrap(HWND(bitPattern: Int(bitPattern: raw)))
    }

    private func dispatchPostedCloses(to handle: HWND) {
        for _ in 0..<8 {
            var message = MSG()
            guard PeekMessageW(&message, handle, UINT(WM_CLOSE), UINT(WM_CLOSE), UINT(PM_REMOVE)) else { return }
            DispatchMessageW(&message)
        }
        XCTFail("Close requests did not settle within the bounded message drain.")
    }

    private func policyNode(in harness: Harness) throws -> ViewNode {
        var candidates = [harness.host.hostedRuntime.root]
        while let node = candidates.popLast() {
            if node.accessibilityIdentifier == "policy" { return node }
            candidates.append(contentsOf: node.children)
        }
        return try XCTUnwrap(nil, "The test view failed to produce its policy node.")
    }

    private func inputClock(for harness: Harness) -> RuntimeTestClock {
        let clock = RuntimeTestClock()
        clock.now = 1_000
        harness.host.frameClock = { clock.now }
        harness.host.hostedRuntime.clock = { clock.now }
        return clock
    }

    private func inputCenter(of node: ViewNode) -> Point {
        var point = Point(x: node.resolvedFrame.midX, y: node.resolvedFrame.midY)
        var ancestor = node.parent
        while let current = ancestor {
            point.x += current.resolvedFrame.origin.x
            point.y += current.resolvedFrame.origin.y
            ancestor = current.parent
        }
        return point
    }

    func testWindowWithoutModifierUsesEnabledSceneDefault() async throws {
        let harness = try makeHost(Text("Ordinary window"))
        defer { tearDown(harness) }

        XCTAssertEqual(harness.host.hostedRuntime.windowDismissalBehavior, .automatic)
        XCTAssertTrue(harness.host.windowShouldClose(harness.window))
        XCTAssertTrue(harness.window.isCloseButtonEnabled)
    }

    func testEnclosingModifierOverridesNestedDeclarations() async throws {
        let enabled = try makeHost(
            VStack { Text("Child").windowDismissBehavior(.disabled) }
                .windowDismissBehavior(.enabled))
        defer { tearDown(enabled) }
        XCTAssertTrue(enabled.host.windowShouldClose(enabled.window))

        let disabled = try makeHost(
            VStack { Text("Child").windowDismissBehavior(.enabled) }
                .windowDismissBehavior(.disabled))
        defer { tearDown(disabled) }
        XCTAssertFalse(disabled.host.windowShouldClose(disabled.window))

        let automatic = try makeHost(
            VStack { Text("Child").windowDismissBehavior(.disabled) }
                .windowDismissBehavior(.automatic))
        defer { tearDown(automatic) }
        XCTAssertTrue(automatic.host.windowShouldClose(automatic.window))
    }

    func testNestedDeclarationIsConsumedWhenNoEnclosingOverrideExists() async throws {
        let harness = try makeHost(VStack { HStack { Text("Child").windowDismissBehavior(.disabled) } })
        defer { tearDown(harness) }

        XCTAssertFalse(harness.host.windowShouldClose(harness.window))
        XCTAssertFalse(harness.window.isCloseButtonEnabled)
    }

    func testCloseReadsLatestObservedPolicyAndModifierRemoval() async throws {
        let model = WindowClosePolicyModel()
        let harness = try makeHost(WindowClosePolicyContent(model: model))
        defer { tearDown(harness) }
        let originalNode = try policyNode(in: harness)

        model.behavior = .disabled
        XCTAssertFalse(harness.host.windowShouldClose(harness.window))
        XCTAssertFalse(harness.window.isCloseButtonEnabled)
        XCTAssertEqual(harness.host.executedReloadCount, 1)

        model.behavior = .enabled
        XCTAssertTrue(harness.host.windowShouldClose(harness.window))
        model.behavior = .automatic
        XCTAssertTrue(harness.host.windowShouldClose(harness.window))
        model.behavior = .disabled
        XCTAssertFalse(harness.host.windowShouldClose(harness.window))

        model.includesModifier = false
        XCTAssertTrue(harness.host.windowShouldClose(harness.window))
        XCTAssertTrue(harness.window.isCloseButtonEnabled)
        XCTAssertNil(try policyNode(in: harness).windowDismissBehavior)
        XCTAssertTrue(
            try policyNode(in: harness) === originalNode, "Reconciliation must clear the surviving node's policy.")
    }

    func testRemovalTransitionDoesNotKeepDetachedClosePolicyActive() async throws {
        let model = WindowClosePolicyModel()
        let harness = try makeHost(RemovedWindowClosePolicyContent(model: model))
        defer { tearDown(harness) }
        XCTAssertFalse(harness.host.windowShouldClose(harness.window))

        withAnimation(.linear(duration: 2)) { model.includesModifier = false }

        XCTAssertTrue(harness.host.windowShouldClose(harness.window))
        XCTAssertFalse(harness.host.hostedRuntime.transitionOverlays.isEmpty)
        XCTAssertEqual(harness.host.hostedRuntime.windowDismissalBehavior, .automatic)
    }

    func testOrdinaryRebuildUpdatesNativeCloseAvailabilityWithoutARequest() async throws {
        let model = WindowClosePolicyModel()
        let harness = try makeHost(WindowClosePolicyContent(model: model), native: true)
        defer { tearDown(harness) }
        let menu = try XCTUnwrap(GetSystemMenu(try nativeHandle(harness.window), false))

        model.behavior = .disabled
        harness.host.windowNeedsDisplay(harness.window)
        XCTAssertFalse(harness.window.isCloseButtonEnabled)
        XCTAssertNotEqual(GetMenuState(menu, UINT(SC_CLOSE), UINT(MF_BYCOMMAND)) & UINT(MF_GRAYED), 0)

        model.includesModifier = false
        harness.host.windowNeedsDisplay(harness.window)
        XCTAssertTrue(harness.window.isCloseButtonEnabled)
        XCTAssertEqual(GetMenuState(menu, UINT(SC_CLOSE), UINT(MF_BYCOMMAND)) & UINT(MF_GRAYED), 0)
    }

    func testReentrantPolicyQueryDoesNotReenterItsReload() async throws {
        let model = WindowClosePolicyModel()
        model.behavior = .disabled
        let harness = try makeHost(WindowClosePolicyContent(model: model))
        defer {
            harness.host.onReloadContentCompleted = nil
            tearDown(harness)
        }
        var nestedResults: [Bool] = []
        harness.host.onReloadContentCompleted = {
            nestedResults.append(harness.host.windowShouldClose(harness.window))
        }
        model.behavior = .enabled

        XCTAssertTrue(harness.host.windowShouldClose(harness.window))
        XCTAssertEqual(nestedResults, [false])
        XCTAssertEqual(harness.host.executedReloadCount, 1)
        XCTAssertEqual(harness.renderer.detachCount, 0)
    }

    func testPolicyMutationDuringReloadDefersTheStaleApproval() async throws {
        let model = WindowClosePolicyModel()
        model.behavior = .disabled
        let harness = try makeHost(WindowClosePolicyContent(model: model))
        defer {
            harness.host.onReloadContentCompleted = nil
            tearDown(harness)
        }
        harness.host.onReloadContentCompleted = {
            harness.host.onReloadContentCompleted = nil
            model.behavior = .disabled
        }
        model.behavior = .enabled

        XCTAssertFalse(
            harness.host.windowShouldClose(harness.window), "A second pending rebuild invalidates this approval.")
        XCTAssertEqual(harness.host.executedReloadCount, 1, "Do not loop through arbitrary app callbacks in preflight.")
        XCTAssertFalse(harness.host.windowShouldClose(harness.window))
        XCTAssertEqual(harness.host.executedReloadCount, 2)
        XCTAssertEqual(harness.batchRenderer.detachCount, 0)
    }

    func testRejectedNativeClosePreservesBackendsAccessibilityAndHostUntilApproval() async throws {
        let model = WindowClosePolicyModel()
        model.behavior = .disabled
        let harness = try makeHost(WindowClosePolicyContent(model: model), native: true)
        defer { tearDown(harness) }
        let handle = try nativeHandle(harness.window)
        let bridge = try XCTUnwrap(harness.window.accessibilityProvider as? UIAProviderBridge)
        let provider = try XCTUnwrap(bridge.retainedRootProviderForTesting())
        defer { SWU_UIAReleaseProvider(provider) }
        let timerState = harness.host.currentTimerState
        var closeCount = 0
        harness.host.onWindowClosed = { host in
            closeCount += 1
            host.windowWillClose(host.platformWindow)
        }

        SendMessageW(handle, UINT(WM_CLOSE), 0, 0)

        XCTAssertTrue(IsWindow(handle))
        XCTAssertEqual(closeCount, 0)
        XCTAssertEqual(harness.renderer.detachCount, 0)
        XCTAssertEqual(harness.batchRenderer.detachCount, 0)
        XCTAssertTrue(harness.window.accessibilityProvider === bridge)
        XCTAssertEqual(harness.host.currentTimerState, timerState)
        XCTAssertEqual(
            SWU_UIAProviderGetControlType(provider), Int32(SWU_UIA_CONTROL_TYPE_PANE),
            "Refusing close must leave the real UIA provider queryable.")

        model.behavior = .enabled
        harness.window.requestClose()
        dispatchPostedCloses(to: handle)

        XCTAssertNil(harness.window.nativeHandle)
        XCTAssertNil(harness.window.accessibilityProvider)
        XCTAssertEqual(closeCount, 1)
        XCTAssertEqual(harness.renderer.detachCount, 1)
        XCTAssertEqual(harness.batchRenderer.detachCount, 1)
        XCTAssertFalse(harness.host.currentTimerState.isEnabled)
    }

    func testProgrammaticDismissalKeepsRejectedWindowInCoordinator() async throws {
        let model = WindowClosePolicyModel()
        model.behavior = .disabled
        var created: [Harness] = []
        var quitCount = 0
        let hooks = WindowCoordinatorHooks(
            startWindow: { host in
                host.platformWindow.postsQuitMessageOnDestroy = false
                try host.platformWindow.create()
            },
            requestCloseWindow: { $0.platformWindow.requestClose() },
            runMessageLoop: { 0 }, terminateMessageLoop: { quitCount += 1 })
        let coordinator = WinSwiftUIWindowCoordinator(
            sceneConfigurations: [
                configuration(WindowClosePolicyContent(model: model)),
                configuration(Text("Auxiliary"), id: "aux"),
            ], hooks: hooks,
            hostFactory: { config, _ in
                let renderer = FakeRenderBackend()
                let batch = FakeBatchRenderBackend()
                let host = WinSwiftUIWindowHost(
                    configuration: config, renderer: renderer, batchRenderer: batch, startupProbeConfiguration: nil)
                created.append(Harness(host: host, renderer: renderer, batchRenderer: batch))
                return host
            })
        defer { for harness in created { tearDown(harness) } }
        let primary: WinSwiftUIWindowHost
        do {
            primary = try coordinator.bootPrimaryWindow()
        } catch {
            throw XCTSkip("This environment cannot create an owned test window: \(error)")
        }
        XCTAssertTrue(coordinator.openWindow(payload: WindowActionPayload(id: "aux", value: nil)))
        XCTAssertEqual(created.count, 2)
        let primaryHandle = try nativeHandle(primary.platformWindow)
        let auxiliary = try XCTUnwrap(created.last)
        let auxiliaryHandle = try nativeHandle(auxiliary.window)
        let environment = try XCTUnwrap(primary.windowEnvironment)

        environment.dismissWindow()
        dispatchPostedCloses(to: primaryHandle)
        XCTAssertEqual(coordinator.windowCount, 2)
        XCTAssertEqual(quitCount, 0)
        XCTAssertTrue(IsWindow(primaryHandle))
        XCTAssertEqual(created[0].renderer.detachCount, 0)

        environment.dismissWindow(id: "aux")
        dispatchPostedCloses(to: auxiliaryHandle)
        XCTAssertEqual(coordinator.windowCount, 1)
        XCTAssertEqual(quitCount, 0)

        model.behavior = .enabled
        environment.dismissWindow()
        dispatchPostedCloses(to: primaryHandle)
        environment.dismissWindow()
        XCTAssertEqual(coordinator.windowCount, 0)
        XCTAssertEqual(quitCount, 1)
        XCTAssertEqual(created[0].renderer.detachCount, 1)
        XCTAssertEqual(auxiliary.renderer.detachCount, 1)
    }

    func testFailedStartupCleansUpADisabledNativeWindowExactlyOnce() async throws {
        var created: Harness?
        var quitCount = 0
        let neutral = RefusingNeutralCloseHost()
        let hooks = WindowCoordinatorHooks(
            startWindow: { host in
                host.platformWindow.postsQuitMessageOnDestroy = false
                host.platformWindow.setPlatformWindowHost(neutral)
                try host.platformWindow.create()
                throw StartFailure.expected
            },
            requestCloseWindow: { _ in XCTFail("Failed startup must not make a vetoable dismiss request.") },
            runMessageLoop: { 0 }, terminateMessageLoop: { quitCount += 1 })
        let coordinator = WinSwiftUIWindowCoordinator(
            sceneConfigurations: [configuration(Text("Disabled startup").windowDismissBehavior(.disabled))],
            hooks: hooks,
            hostFactory: { config, _ in
                let renderer = FakeRenderBackend()
                let batch = FakeBatchRenderBackend()
                let host = WinSwiftUIWindowHost(
                    configuration: config, renderer: renderer, batchRenderer: batch, startupProbeConfiguration: nil)
                created = Harness(host: host, renderer: renderer, batchRenderer: batch)
                return host
            })
        defer { if let created { tearDown(created) } }

        do {
            _ = try coordinator.bootPrimaryWindow()
            XCTFail("The injected startup failure must propagate.")
        } catch StartFailure.expected {
        } catch {
            throw XCTSkip("This environment cannot create an owned test window: \(error)")
        }

        let harness = try XCTUnwrap(created)
        XCTAssertNil(harness.window.nativeHandle)
        XCTAssertNil(harness.window.accessibilityProvider)
        XCTAssertEqual(harness.renderer.detachCount, 1)
        XCTAssertEqual(harness.batchRenderer.detachCount, 1)
        XCTAssertEqual(coordinator.windowCount, 0)
        XCTAssertEqual(quitCount, 0, "Startup failure does not apply the normal last-window quit policy.")
        XCTAssertEqual(neutral.requests, 0)
        XCTAssertEqual(neutral.closes, 1, "Rollback destroys even a window with a vetoing neutral wrapper.")
    }

    func testClosedFailedPresenterCannotRetryOrResizeFromALateCallback() async {
        let renderer = FakeRenderBackend(attachShouldFail: true)
        let batch = FakeBatchRenderBackend(attachShouldFail: true)
        let surface = SurfaceDescriptor(
            windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
            pixelSize: IntSize(width: 220, height: 140), scaleFactor: 1)
        let host = WinSwiftUIWindowHost(
            configuration: configuration(Text("Failed presenter")), renderer: renderer, batchRenderer: batch,
            surfaceDescriptorProvider: { _ in surface }, startupProbeConfiguration: nil)
        let clock = RuntimeTestClock()
        clock.now = 1_000
        host.recoveryClock = { clock.now }
        host.windowDidCreate(host.platformWindow)
        XCTAssertNotNil(host.rendererHealthSnapshot.nextPresenterAttachInSeconds)
        let originalSize = host.currentLogicalRootSize

        host.windowWillClose(host.platformWindow)
        let frameDetaches = renderer.detachCount
        let sceneDetaches = batch.detachCount
        renderer.setAttachShouldFail(false)
        batch.setAttachShouldFail(false)
        clock.now += 100
        host.window(host.platformWindow, animationFrameAt: clock.now)
        host.window(host.platformWindow, didResizeTo: IntSize(width: 640, height: 480))
        host.windowNeedsDisplay(host.platformWindow)

        XCTAssertNil(host.rendererHealthSnapshot.nextPresenterAttachInSeconds)
        XCTAssertTrue(renderer.attachedSurfaces.isEmpty)
        XCTAssertTrue(batch.attachedSurfaces.isEmpty)
        XCTAssertTrue(renderer.resizedSizes.isEmpty)
        XCTAssertTrue(batch.resizedSizes.isEmpty)
        XCTAssertEqual(host.currentLogicalRootSize, originalSize)
        XCTAssertEqual(renderer.detachCount, frameDetaches)
        XCTAssertEqual(batch.detachCount, sceneDetaches)
        XCTAssertFalse(host.currentTimerState.isEnabled)
    }

    func testDirectCloseCancelsMouseLongPressAndResetsGestureState() async throws {
        var updates: [Bool] = []
        var completions = 0
        let content = WindowCloseGestureStateContent(
            onUpdating: { updates.append($0) }, onRecognized: { completions += 1 })
        let harness = try makeHost(content)
        defer { tearDown(harness) }
        let clock = inputClock(for: harness)
        let point = inputCenter(of: try policyNode(in: harness))

        harness.host.window(harness.window, leftMouseDownAt: point)
        XCTAssertTrue(content.isHolding)
        XCTAssertEqual(updates, [true])

        // No HWND, focus-loss, capture-loss, or touch callback precedes this
        // teardown. Mouse holds must terminate through the host itself.
        harness.host.windowWillClose(harness.window)
        harness.host.windowWillClose(harness.window)
        clock.now += 2
        harness.host.window(harness.window, animationFrameAt: clock.now)
        harness.host.window(harness.window, leftMouseUpAt: point)

        XCTAssertFalse(content.isHolding)
        XCTAssertEqual(updates, [true], "Cancellation must not synthesize an updating(false) event.")
        XCTAssertEqual(completions, 0)
        XCTAssertFalse(harness.host.hostedRuntime.hasActiveAnimations)
        XCTAssertNil(harness.host.hostedRuntime.focusedNode)
        XCTAssertFalse(harness.host.currentTimerState.isEnabled)
        XCTAssertEqual(harness.batchRenderer.detachCount, 1)
    }

    func testCloseCleanupCannotReenterPointerKeyboardOrFocusInput() async throws {
        let harness = try makeHost(Text("Close target").frame(width: 120, height: 60).accessibilityIdentifier("policy"))
        defer { tearDown(harness) }
        let clock = inputClock(for: harness)
        let node = try policyNode(in: harness)
        defer {
            node.onFocusExit = nil
            node.longPressGesture = nil
        }
        let point = inputCenter(of: node)
        var pressing: [Bool] = []
        var begins = 0
        var cleanups = 0
        var completions = 0
        var activations = 0
        var textEvents = 0
        var focusExits = 0
        var attemptedPointerReentry = false
        var attemptedFocusReentry = false
        node.isHitTestVisible = true
        node.isFocusable = true
        node.onActivate = { activations += 1 }
        node.onIMEComposition = { _ in textEvents += 1 }
        node.longPressGesture = RetainedLongPressGesture(
            minimumDuration: 1,
            onBegin: { _ in
                begins += 1
                return { cleanups += 1 }
            },
            onPressingChanged: { value in
                pressing.append(value)
                if !value, !attemptedPointerReentry {
                    attemptedPointerReentry = true
                    harness.host.window(harness.window, leftMouseDownAt: point)
                    harness.host.injectDiagnosticsClick(at: point)
                    harness.host.window(harness.window, keyDown: KeyboardEvent(keyCode: UInt32(VK_RETURN)))
                }
            }, onRecognized: { completions += 1 })
        node.onFocusExit = {
            focusExits += 1
            guard !attemptedFocusReentry else { return }
            attemptedFocusReentry = true
            harness.host.window(harness.window, keyDown: KeyboardEvent(keyCode: UInt32(VK_RETURN)))
            harness.host.window(harness.window, didInputText: "late text")
            harness.host.window(harness.window, imeComposition: IMECompositionEvent(phase: .updated("late IME")))
            harness.host.windowDidLoseKeyboardFocus(harness.window)
        }
        harness.host.window(harness.window, leftMouseDownAt: point)
        XCTAssertEqual(pressing, [true])
        XCTAssertTrue(harness.host.hostedRuntime.focusedNode === node)
        var routedAfterClose = 0
        harness.host.onInputEventRouted = { _ in routedAfterClose += 1 }

        harness.host.windowWillClose(harness.window)
        harness.host.windowWillClose(harness.window)
        clock.now += 2
        _ = harness.host.hostedRuntime.tickAnimations(at: clock.now)

        XCTAssertEqual(pressing, [true, false])
        XCTAssertEqual(begins, 1)
        XCTAssertEqual(cleanups, 1)
        XCTAssertEqual(completions, 0)
        XCTAssertEqual(activations, 0)
        XCTAssertEqual(textEvents, 0)
        XCTAssertEqual(focusExits, 1)
        XCTAssertEqual(routedAfterClose, 0)
        XCTAssertNil(harness.host.hostedRuntime.focusedNode)
        XCTAssertFalse(harness.host.hostedRuntime.hasActiveAnimations)
    }

    func testClosedHostRejectsLateInputAndDoesNotInvalidateItsRemainingHWND() async throws {
        let harness = try makeHost(
            Text("Late input target").frame(width: 120, height: 60).accessibilityIdentifier("policy"), native: true)
        defer { tearDown(harness) }
        let handle = try nativeHandle(harness.window)
        let node = try policyNode(in: harness)
        let logicalPoint = inputCenter(of: node)
        let scale = harness.window.effectiveScaleFactor
        let point = Point(x: logicalPoint.x * scale, y: logicalPoint.y * scale)
        var actions = 0
        var routed = 0
        node.isHitTestVisible = true
        node.isFocusable = true
        node.onActivate = { actions += 1 }
        node.onContextMenu = { _ in actions += 1 }
        node.onDropPayloads = { _, _ in
            actions += 1
            return true
        }
        harness.host.windowWillClose(harness.window)
        harness.host.onInputEventRouted = { _ in routed += 1 }
        let frameCount = harness.renderer.renderedFrames.count
        let sceneCount = harness.batchRenderer.renderedScenes.count
        ValidateRect(handle, nil)

        harness.host.window(harness.window, leftMouseDownAt: point)
        harness.host.window(harness.window, pointerMovedTo: point)
        harness.host.window(harness.window, leftMouseUpAt: point)
        harness.host.window(harness.window, touchBegan: [point])
        harness.host.window(harness.window, touchMoved: [point])
        harness.host.window(harness.window, touchEnded: [point])
        harness.host.window(harness.window, mouseWheelAt: point, delta: 1)
        harness.host.window(harness.window, mouseWheelAt: point, delta: 1, source: .precise)
        harness.host.window(harness.window, horizontalScrollAt: point, delta: 1)
        harness.host.window(harness.window, horizontalScrollAt: point, delta: 1, source: .precise)
        harness.host.windowDidReceiveRightClick(harness.window, event: MouseEvent(button: .right, position: point))
        harness.host.window(harness.window, keyDown: KeyboardEvent(keyCode: UInt32(VK_RETURN)))
        harness.host.window(harness.window, didInputText: "late")
        harness.host.window(harness.window, imeComposition: IMECompositionEvent(phase: .committed("late")))
        harness.host.window(
            harness.window,
            didReceiveFileDrop: FileDropPayload(
                fileURLs: [URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("not-created.txt")],
                clientPoint: point))
        harness.host.windowDidCancelPointerInteraction(harness.window)
        harness.host.windowPointerDidLeave(harness.window)
        harness.host.windowDidLoseKeyboardFocus(harness.window)
        harness.host.injectDiagnosticsPointerMove(to: logicalPoint)
        harness.host.injectDiagnosticsScroll(at: logicalPoint, delta: 1)
        harness.host.injectDiagnosticsClick(at: logicalPoint)
        harness.host.requestDiagnosticsFrame()
        harness.host.windowNeedsDisplay(harness.window)

        XCTAssertEqual(actions, 0)
        XCTAssertEqual(routed, 0)
        XCTAssertEqual(harness.renderer.renderedFrames.count, frameCount)
        XCTAssertEqual(harness.batchRenderer.renderedScenes.count, sceneCount)
        XCTAssertNil(harness.host.windowTextInputCaretRect(harness.window))
        XCTAssertNil(harness.host.hostedRuntime.focusedNode)
        XCTAssertFalse(harness.host.currentTimerState.isEnabled)
        XCTAssertFalse(
            GetUpdateRect(handle, nil, false), "Closed-host callbacks must not dirty even an HWND awaiting rollback.")
    }

    func testNormalFocusLossStillCancelsAHoldAndAllowsLaterInput() async throws {
        var completions = 0
        let content = WindowCloseGestureStateContent(onRecognized: { completions += 1 })
        let harness = try makeHost(content)
        defer { tearDown(harness) }
        let clock = inputClock(for: harness)
        let point = inputCenter(of: try policyNode(in: harness))

        harness.host.window(harness.window, leftMouseDownAt: point)
        XCTAssertTrue(content.isHolding)
        harness.host.windowDidLoseKeyboardFocus(harness.window)
        XCTAssertFalse(content.isHolding)
        XCTAssertEqual(completions, 0)
        XCTAssertEqual(harness.batchRenderer.detachCount, 0)

        clock.now += 2
        harness.host.window(harness.window, leftMouseDownAt: point)
        XCTAssertTrue(content.isHolding)
        clock.now += 1
        harness.host.window(harness.window, leftMouseUpAt: point)
        XCTAssertFalse(content.isHolding)
        XCTAssertEqual(completions, 1, "Only teardown should permanently reject subsequent input.")
    }

    func testApprovedTeardownCancelsQueuedObservedReloadsAndRemainsIdempotent() async throws {
        let model = WindowClosePolicyModel()
        let harness = try makeHost(WindowClosePolicyContent(model: model))
        defer { tearDown(harness) }
        var closeCount = 0
        harness.host.onWindowClosed = { _ in
            closeCount += 1
            model.revision += 1
        }
        model.revision += 1
        XCTAssertEqual(harness.host.scheduledReloadCount, 1)

        // Simulates destruction after an approved request while a coalesced
        // task is still queued. The task must not reopen a dialog or presenter.
        harness.host.windowWillClose(harness.window)
        harness.host.windowWillClose(harness.window)
        let renderCount = harness.batchRenderer.renderedScenes.count
        harness.host.windowNeedsDisplay(harness.window)
        harness.host.windowDidCreate(harness.window)
        for _ in 0..<8 { await Task.yield() }

        XCTAssertEqual(closeCount, 1)
        XCTAssertEqual(harness.host.executedReloadCount, 0)
        XCTAssertEqual(harness.host.scheduledReloadCount, 1)
        XCTAssertEqual(harness.batchRenderer.renderedScenes.count, renderCount)
        XCTAssertEqual(harness.renderer.detachCount, 1)
        XCTAssertEqual(harness.batchRenderer.detachCount, 1)
        XCTAssertNil(harness.window.accessibilityProvider)
        XCTAssertFalse(harness.host.currentTimerState.isEnabled)
    }
}
