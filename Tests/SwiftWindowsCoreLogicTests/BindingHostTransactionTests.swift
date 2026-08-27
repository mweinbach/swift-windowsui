import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
private final class BindingHostModel: ObservableObject {
    @Published var isOn = false
    @Published var revision = 0
}

@MainActor
private final class BindingHostPlainValue {
    var isOn = false
}

@MainActor
private final class BindingHostStateCapture {
    var binding: Binding<Bool>?
}

@MainActor
private struct PlainBindingHostContent: View {
    @ObservedObject var model: BindingHostModel
    let value: BindingHostPlainValue

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Plain binding", isOn: Binding(get: { value.isOn }, set: { value.isOn = $0 }))
                .labelsHidden()
                .accessibilityIdentifier("plain-toggle")
            Rectangle()
                .fill(WinSwiftUI.Color.blue)
                .frame(width: 80, height: 24)
                .opacity(value.isOn ? 0.2 : 1)
                .accessibilityIdentifier("plain-opacity")
            Text("Revision \(model.revision)")
        }
        .padding(12)
    }
}

/// These controls use the actual host-provided invalidation handlers. A
/// binding setter alone cannot exercise the control's later invalidation,
/// after the binding's transaction scope has already been restored.
@MainActor
private struct BindingHostContent: View {
    @ObservedObject var model: BindingHostModel
    @State var stateIsOn = false
    let bindingAnimation: Animation?
    var stateCapture: BindingHostStateCapture? = nil

    var body: some View {
        let stateBinding = $stateIsOn
        stateCapture?.binding = stateBinding
        return VStack(alignment: .leading, spacing: 8) {
            Toggle("Observed binding", isOn: $model.isOn.animation(bindingAnimation))
                .labelsHidden()
                .accessibilityIdentifier("observed-toggle")
            Rectangle()
                .fill(WinSwiftUI.Color.blue)
                .frame(width: 80, height: 24)
                .opacity(model.isOn ? 0.2 : 1)
                .accessibilityIdentifier("observed-opacity")
            Toggle("State binding", isOn: stateBinding)
                .labelsHidden()
                .accessibilityIdentifier("state-toggle")
            Rectangle()
                .fill(WinSwiftUI.Color.red)
                .frame(width: 80, height: 24)
                .opacity(stateIsOn ? 0.2 : 1)
                .accessibilityIdentifier("state-opacity")
            Text("Revision \(model.revision)")
        }
        .padding(12)
    }
}

@MainActor
private struct BindingHostHarness {
    let host: WinSwiftUIWindowHost
    let window: Win32Window
    let renderer: FakeRenderBackend
    let clock: RuntimeTestClock

    var runtime: RetainedViewRuntime { host.hostedRuntime }

    func present(at timestamp: Double) {
        clock.now = timestamp
        host.windowNeedsDisplay(window)
    }
}

@MainActor
final class BindingHostTransactionTests: XCTestCase {
    private func makeHost<Content: View>(_ content: Content) -> BindingHostHarness {
        let clock = RuntimeTestClock()
        clock.now = 5_000
        let renderer = FakeRenderBackend()
        let surface = SurfaceDescriptor(
            windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
            pixelSize: IntSize(width: 320, height: 240), scaleFactor: 1)
        let window = Win32Window(title: "Binding transactions", clientSize: surface.pixelSize)
        let host = WinSwiftUIWindowHost(
            configuration: WindowGroupConfiguration(
                title: "Binding transactions", size: surface.pixelSize, clearColor: .black,
                content: [AnyView(content)]),
            platformWindow: window,
            renderer: renderer,
            batchRenderer: nil,
            surfaceDescriptorProvider: { _ in surface },
            startupProbeConfiguration: nil)
        host.frameClock = { clock.now }
        host.hostedRuntime.clock = { clock.now }
        host.windowDidCreate(window)
        host.resetObservabilityCounters()
        return BindingHostHarness(host: host, window: window, renderer: renderer, clock: clock)
    }

    private func node(_ identifier: String, in harness: BindingHostHarness) throws -> ViewNode {
        var pending = [harness.runtime.root]
        while let candidate = pending.popLast() {
            if candidate.accessibilityIdentifier == identifier { return candidate }
            pending.append(contentsOf: candidate.children)
        }
        return try XCTUnwrap(nil as ViewNode?, "Missing \(identifier)")
    }

    private func activateWithKeyboard(_ identifier: String, in harness: BindingHostHarness) throws {
        let control = try node(identifier, in: harness)
        XCTAssertNotNil(control.onActivate)
        harness.runtime.requestFocus(control)
        harness.host.window(harness.window, keyDown: KeyboardEvent(keyCode: KeyboardKey.space.rawValue))
    }

    private func activateWithPointer(_ identifier: String, in harness: BindingHostHarness) throws {
        let control = try node(identifier, in: harness)
        XCTAssertNotNil(control.onActivate)
        var origin = control.resolvedFrame.origin
        var parent = control.parent
        while let current = parent {
            origin.x += current.resolvedFrame.origin.x
            origin.y += current.resolvedFrame.origin.y
            parent = current.parent
        }
        let scale = harness.window.effectiveScaleFactor
        let point = Point(
            x: (origin.x + control.resolvedFrame.width / 2) * scale,
            y: (origin.y + control.resolvedFrame.height / 2) * scale)
        harness.host.window(harness.window, pointerMovedTo: point)
        harness.host.window(harness.window, leftMouseDownAt: point)
        harness.host.window(harness.window, leftMouseUpAt: point)
    }

    @discardableResult
    private func assertOpacityAnimation(
        _ node: ViewNode, startTime: Double, duration: Double = 1,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> AnimationState {
        let state = try XCTUnwrap(node.animationStates[.opacity], file: file, line: line)
        XCTAssertEqual(node.opacity, 1, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(state.startValue, 1, file: file, line: line)
        XCTAssertEqual(state.endValue, 0.2, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(state.startTime, startTime, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(state.duration, duration, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(state.easing, .linear, file: file, line: line)
        return state
    }

    private func yieldToQueuedReloadTasks() async {
        await Task.yield()
        await Task.yield()
    }

    func testKeyboardBindingAnimationStartsSynchronouslyAndSurvivesTheQueuedTask() async throws {
        let model = BindingHostModel()
        let harness = makeHost(BindingHostContent(model: model, bindingAnimation: .linear(duration: 1)))
        let target = try node("observed-opacity", in: harness)
        var rebuildDurations: [Double?] = []
        harness.host.onReloadContentCompleted = { rebuildDurations.append(currentAnimationTransaction?.duration) }
        let startedAt = harness.clock.now

        try activateWithKeyboard("observed-toggle", in: harness)

        XCTAssertTrue(model.isOn)
        try assertOpacityAnimation(target, startTime: startedAt)
        XCTAssertEqual(rebuildDurations, [1])
        XCTAssertEqual(harness.host.scheduledReloadCount, 1)
        XCTAssertEqual(harness.host.executedReloadCount, 1)
        XCTAssertEqual(harness.host.completedObservedObjectReloadTaskCount, 1)
        XCTAssertNil(currentTransaction)
        XCTAssertNil(currentAnimationTransaction)

        // No await or native frame was needed to install the opacity tween.
        // The Task scheduled by @Published must now be a harmless fallback.
        await yieldToQueuedReloadTasks()
        XCTAssertEqual(harness.host.executedReloadCount, 1)
        try assertOpacityAnimation(target, startTime: startedAt)

        let initialPresentations = harness.renderer.renderedFrames.count
        harness.present(at: startedAt + 0.5)
        XCTAssertEqual(target.opacity, 0.6, accuracy: 0.0001)
        XCTAssertGreaterThan(harness.renderer.renderedFrames.count, initialPresentations)
        XCTAssertEqual(target.animationStates[.opacity]?.startTime, startedAt)
        harness.present(at: startedAt + 1)
        XCTAssertEqual(target.opacity, 0.2, accuracy: 0.0001)
        XCTAssertNil(target.animationStates[.opacity])
    }

    func testPointerBindingAnimationStartsBeforeTheFirstFrameAndPresentsItsMidpoint() async throws {
        let model = BindingHostModel()
        let harness = makeHost(BindingHostContent(model: model, bindingAnimation: .linear(duration: 1)))
        let target = try node("observed-opacity", in: harness)
        let startedAt = harness.clock.now

        try activateWithPointer("observed-toggle", in: harness)

        XCTAssertTrue(model.isOn)
        try assertOpacityAnimation(target, startTime: startedAt)
        XCTAssertEqual(harness.host.executedReloadCount, 1)
        harness.present(at: startedAt + 0.5)
        XCTAssertEqual(target.opacity, 0.6, accuracy: 0.0001)
        await yieldToQueuedReloadTasks()
        XCTAssertEqual(harness.host.executedReloadCount, 1)
        XCTAssertEqual(target.animationStates[.opacity]?.startTime, startedAt)
        XCTAssertEqual(target.animationStates[.opacity]?.duration, 1)
        harness.present(at: startedAt + 1)
        XCTAssertEqual(target.opacity, 0.2, accuracy: 0.0001)
        XCTAssertNil(target.animationStates[.opacity])
    }

    func testExplicitNilBindingTransactionReachesTheSynchronousControlRebuild() async throws {
        let model = BindingHostModel()
        let harness = makeHost(BindingHostContent(model: model, bindingAnimation: nil))
        let target = try node("observed-opacity", in: harness)
        var rebuiltTransaction: Transaction?
        harness.host.onReloadContentCompleted = { rebuiltTransaction = currentTransaction }

        try activateWithKeyboard("observed-toggle", in: harness)

        XCTAssertTrue(model.isOn)
        XCTAssertNotNil(rebuiltTransaction, "Explicit nil is a transaction, not the absence of a transaction")
        XCTAssertNil(rebuiltTransaction?.animation)
        XCTAssertEqual(target.opacity, 0.2, accuracy: 0.0001)
        XCTAssertNil(target.animationStates[.opacity])
        XCTAssertEqual(harness.host.completedObservedObjectReloadTaskCount, 1)
        await yieldToQueuedReloadTasks()
        XCTAssertEqual(harness.host.executedReloadCount, 1)
        XCTAssertNil(target.animationStates[.opacity])
        XCTAssertNil(currentTransaction)
    }

    func testExplicitNilBindingOverridesTheRestoredOuterAnimationDuringControlInvalidation() async throws {
        let model = BindingHostModel()
        let harness = makeHost(BindingHostContent(model: model, bindingAnimation: nil))
        let target = try node("observed-opacity", in: harness)
        var rebuiltTransaction: Transaction?
        harness.host.onReloadContentCompleted = { rebuiltTransaction = currentTransaction }

        try withAnimation(.linear(duration: 3)) {
            try activateWithKeyboard("observed-toggle", in: harness)
            XCTAssertEqual(currentTransaction?.animation?.duration, 3, "The caller's scope must still be restored")
            XCTAssertEqual(currentAnimationTransaction?.duration, 3)
        }

        XCTAssertTrue(model.isOn)
        XCTAssertNotNil(rebuiltTransaction)
        XCTAssertNil(
            rebuiltTransaction?.animation, "The control's restored outer scope must not override binding.animation(nil)"
        )
        XCTAssertEqual(target.opacity, 0.2, accuracy: 0.0001)
        XCTAssertNil(target.animationStates[.opacity])
        XCTAssertEqual(harness.host.executedReloadCount, 1)
        await yieldToQueuedReloadTasks()
        harness.present(at: harness.clock.now + 0.5)
        XCTAssertEqual(harness.host.executedReloadCount, 1)
        XCTAssertEqual(target.opacity, 0.2, accuracy: 0.0001)
        XCTAssertNil(target.animationStates[.opacity])
        XCTAssertNil(currentTransaction)
        XCTAssertNil(currentAnimationTransaction)
    }

    func testUnrelatedPendingNotificationCannotSuppressAPlainControlInvalidation() async throws {
        let model = BindingHostModel()
        let unrelated = BindingHostModel()
        let value = BindingHostPlainValue()
        let harness = makeHost(PlainBindingHostContent(model: model, value: value))
        // Establish the same dependency snapshot that a normal host rebuild
        // uses, then register an object the view never reads.
        model.revision = 1
        harness.present(at: harness.clock.now + 0.02)
        harness.host.observe(unrelated)
        harness.host.resetObservabilityCounters()
        let target = try node("plain-opacity", in: harness)

        withAnimation(.linear(duration: 4)) { unrelated.isOn = true }
        XCTAssertEqual(harness.host.executedReloadCount, 0)
        try activateWithKeyboard("plain-toggle", in: harness)

        XCTAssertTrue(value.isOn)
        XCTAssertEqual(
            target.opacity, 0.2, accuracy: 0.0001,
            "Rejecting the unrelated batch must still rebuild the changed control")
        XCTAssertNil(target.animationStates[.opacity])
        XCTAssertEqual(harness.host.skippedObservedObjectReloadCount, 1)
        XCTAssertEqual(harness.host.completedObservedObjectReloadTaskCount, 1)
        XCTAssertEqual(
            harness.host.executedReloadCount, 1, "This binding has no State invalidation to mask the control fallback")
        let completedRebuilds = harness.host.executedReloadCount
        await yieldToQueuedReloadTasks()
        XCTAssertEqual(harness.host.executedReloadCount, completedRebuilds)
        XCTAssertNil(currentTransaction)
    }

    func testNewerStateAnimationOverridesAnOlderQueuedObserverAndIsNotRestarted() async throws {
        let model = BindingHostModel()
        let capture = BindingHostStateCapture()
        let content = BindingHostContent(model: model, bindingAnimation: .linear(duration: 1), stateCapture: capture)
        let harness = makeHost(content)
        let stateBinding = try XCTUnwrap(capture.binding)
        let observedTarget = try node("observed-opacity", in: harness)
        let stateTarget = try node("state-opacity", in: harness)
        let startedAt = harness.clock.now
        var rebuildDurations: [Double?] = []
        harness.host.onReloadContentCompleted = { rebuildDurations.append(currentAnimationTransaction?.duration) }

        withAnimation(.linear(duration: 4)) { model.isOn = true }
        XCTAssertEqual(harness.host.executedReloadCount, 0)
        withAnimation(.linear(duration: 1)) { stateBinding.wrappedValue = true }

        XCTAssertTrue(stateBinding.wrappedValue)
        XCTAssertEqual(rebuildDurations, [1])
        XCTAssertEqual(harness.host.executedReloadCount, 1)
        XCTAssertEqual(harness.host.completedObservedObjectReloadTaskCount, 1)
        try assertOpacityAnimation(observedTarget, startTime: startedAt)
        try assertOpacityAnimation(stateTarget, startTime: startedAt)

        harness.present(at: startedAt + 0.25)
        XCTAssertEqual(stateTarget.opacity, 0.8, accuracy: 0.0001)
        await yieldToQueuedReloadTasks()
        XCTAssertEqual(harness.host.executedReloadCount, 1)
        XCTAssertEqual(stateTarget.animationStates[.opacity]?.startTime, startedAt)
        XCTAssertEqual(stateTarget.animationStates[.opacity]?.duration, 1)
        harness.present(at: startedAt + 0.5)
        XCTAssertEqual(observedTarget.opacity, 0.6, accuracy: 0.0001)
        XCTAssertEqual(stateTarget.opacity, 0.6, accuracy: 0.0001)
        harness.present(at: startedAt + 1)
        XCTAssertEqual(stateTarget.opacity, 0.2, accuracy: 0.0001)
        XCTAssertNil(stateTarget.animationStates[.opacity])
        XCTAssertNil(observedTarget.animationStates[.opacity])
        XCTAssertNil(currentTransaction)
    }

    func testNewerExplicitNilStateTransactionSuppressesAnOlderQueuedAnimation() async throws {
        let model = BindingHostModel()
        let capture = BindingHostStateCapture()
        let content = BindingHostContent(model: model, bindingAnimation: .linear(duration: 1), stateCapture: capture)
        let harness = makeHost(content)
        let stateBinding = try XCTUnwrap(capture.binding)
        let observedTarget = try node("observed-opacity", in: harness)
        let stateTarget = try node("state-opacity", in: harness)
        var rebuiltTransaction: Transaction?
        harness.host.onReloadContentCompleted = { rebuiltTransaction = currentTransaction }

        withAnimation(.linear(duration: 4)) { model.isOn = true }
        stateBinding.animation(nil).wrappedValue = true

        XCTAssertNotNil(rebuiltTransaction)
        XCTAssertNil(rebuiltTransaction?.animation)
        XCTAssertEqual(harness.host.executedReloadCount, 1)
        for target in [observedTarget, stateTarget] {
            XCTAssertEqual(target.opacity, 0.2, accuracy: 0.0001)
            XCTAssertNil(target.animationStates[.opacity])
        }
        await yieldToQueuedReloadTasks()
        harness.present(at: harness.clock.now + 0.5)
        XCTAssertEqual(harness.host.executedReloadCount, 1)
        XCTAssertNil(stateTarget.animationStates[.opacity])
        XCTAssertNil(observedTarget.animationStates[.opacity])
        XCTAssertNil(currentTransaction)
    }

    func testNewerPlainStateMutationDoesNotInheritAnOlderQueuedAnimation() async throws {
        let model = BindingHostModel()
        let capture = BindingHostStateCapture()
        let content = BindingHostContent(model: model, bindingAnimation: .linear(duration: 1), stateCapture: capture)
        let harness = makeHost(content)
        let stateBinding = try XCTUnwrap(capture.binding)
        let observedTarget = try node("observed-opacity", in: harness)
        let stateTarget = try node("state-opacity", in: harness)
        var rebuildDurations: [Double?] = []
        harness.host.onReloadContentCompleted = { rebuildDurations.append(currentAnimationTransaction?.duration) }

        withAnimation(.linear(duration: 4)) { model.isOn = true }
        XCTAssertNil(currentTransaction)
        stateBinding.wrappedValue = true

        XCTAssertEqual(rebuildDurations.count, 1)
        XCTAssertNil(rebuildDurations.first ?? nil)
        XCTAssertEqual(harness.host.executedReloadCount, 1)
        for target in [observedTarget, stateTarget] {
            XCTAssertEqual(target.opacity, 0.2, accuracy: 0.0001)
            XCTAssertNil(target.animationStates[.opacity])
        }
        await yieldToQueuedReloadTasks()
        harness.present(at: harness.clock.now + 0.5)
        XCTAssertEqual(harness.host.executedReloadCount, 1)
        XCTAssertNil(stateTarget.animationStates[.opacity])
        XCTAssertNil(observedTarget.animationStates[.opacity])
    }

    func testControlFlushCoalescesSameTurnChangesAndKeepsChangesProducedByTheRebuild() async throws {
        let model = BindingHostModel()
        let harness = makeHost(BindingHostContent(model: model, bindingAnimation: .linear(duration: 1)))
        let target = try node("observed-opacity", in: harness)
        let startedAt = harness.clock.now
        var coalesced: [Bool] = []
        var completedRebuilds = 0
        harness.host.onObservedObjectReloadScheduled = { _, wasCoalesced in coalesced.append(wasCoalesced) }
        harness.host.onReloadContentCompleted = {
            completedRebuilds += 1
            if completedRebuilds == 1 { model.revision = 3 }
        }

        withAnimation(.linear(duration: 4)) { model.revision = 1 }
        withAnimation(.linear(duration: 2)) { model.revision = 2 }
        try activateWithKeyboard("observed-toggle", in: harness)

        XCTAssertTrue(model.isOn)
        XCTAssertEqual(coalesced, [false, true, true, false])
        XCTAssertEqual(harness.host.scheduledReloadCount, 2)
        XCTAssertEqual(harness.host.executedReloadCount, 1)
        XCTAssertEqual(harness.host.completedObservedObjectReloadTaskCount, 1)
        try assertOpacityAnimation(target, startTime: startedAt)

        // The control consumed the first batch before rebuilding. The new
        // notification from onReloadContentCompleted belongs to another batch.
        harness.present(at: startedAt + 0.02)
        XCTAssertEqual(harness.host.executedReloadCount, 2)
        XCTAssertEqual(harness.host.completedObservedObjectReloadTaskCount, 2)
        XCTAssertEqual(completedRebuilds, 2)
        XCTAssertEqual(target.animationStates[.opacity]?.startTime, startedAt)
        XCTAssertEqual(target.animationStates[.opacity]?.duration, 1)
        await yieldToQueuedReloadTasks()
        XCTAssertEqual(harness.host.executedReloadCount, 2)
        harness.present(at: startedAt + 0.5)
        XCTAssertEqual(target.opacity, 0.6, accuracy: 0.0001)
        harness.present(at: startedAt + 1)
        XCTAssertEqual(target.opacity, 0.2, accuracy: 0.0001)
        XCTAssertNil(target.animationStates[.opacity])
    }
}
