import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// These are source-authored regressions for the shared Button prerequisite.
/// They use retained controls and fake host presentation, never a native window.
@MainActor
final class RetainedButtonActionTeardownTests: XCTestCase {
    func testTerminalStopDefersButtonPayloadReleaseUntilTaskCleanup() async throws {
        let runtime = makeRuntime()
        let events = ButtonTeardownEvents()
        let button = installButton(in: runtime, events: events, name: "terminal") {
            events.releases.append("terminal")
        }
        let escaped = try XCTUnwrap(button.onActivate)
        defer { finish(runtime) }
        escaped()
        XCTAssertEqual(events.activations, ["terminal"])
        XCTAssertNotNil(events.payloads["terminal"]?.value)

        runtime.stopRenderLifecycleCallbacks()

        escaped()
        XCTAssertEqual(events.activations, ["terminal"])
        XCTAssertTrue(events.releases.isEmpty)
        XCTAssertNotNil(events.payloads["terminal"]?.value)

        runtime.cancelRenderLifecycleTasks()

        XCTAssertEqual(events.releases, ["terminal"])
        XCTAssertNil(events.payloads["terminal"]?.value)
        escaped()
        XCTAssertEqual(events.activations, ["terminal"])
        runtime.cancelRenderLifecycleTasks()
        XCTAssertEqual(events.releases, ["terminal"])
    }

    func testNativeRevocationPrepassDoesNotReleaseButtonPayload() async throws {
        let runtime = makeRuntime()
        let events = ButtonTeardownEvents()
        let button = installButton(in: runtime, events: events, name: "prepass") {
            events.releases.append("prepass")
        }
        let escaped = try XCTUnwrap(button.onActivate)
        defer { finish(runtime) }

        runtime.root.revokeTextInputOwnership()

        escaped()
        XCTAssertTrue(events.activations.isEmpty)
        XCTAssertTrue(events.releases.isEmpty)
        XCTAssertNotNil(events.payloads["prepass"]?.value)
        XCTAssertTrue(button.parent === runtime.root)

        runtime.root.removeAllChildren()

        XCTAssertEqual(events.releases, ["prepass"])
        XCTAssertNil(events.payloads["prepass"]?.value)
        XCTAssertNil(button.parent)
        escaped()
        XCTAssertTrue(events.activations.isEmpty)
    }

    func testWindowCloseRevokesStateEditorAndTasksBeforeButtonPayloadRelease() async throws {
        try await withTextLayout {
            let capture = ButtonTeardownBindingCapture()
            let document = ButtonTeardownDocument()
            let manager = WinSwiftUI.UndoManager()
            let fixture = ButtonTeardownHost(
                ButtonTeardownRoot(capture: capture, document: document)
                    .environment(\.undoManager, manager))
            let events = ButtonTeardownEvents()
            let ready = expectation(description: "Host lifecycle task installed")
            let completed = expectation(description: "Host lifecycle task completed")
            let task = ButtonTeardownTaskProbe(name: "host", ready: ready, completed: completed)
            defer {
                task.onCancellation = nil
                fixture.close()
                task.release()
            }
            try fixture.focusEditor()
            fixture.type("b")
            let escapedState = try XCTUnwrap(capture.binding)
            XCTAssertEqual(escapedState.wrappedValue, 7)
            XCTAssertEqual(document.text, "ab")
            XCTAssertEqual(document.writes, ["ab"])
            XCTAssertTrue(manager.canUndo)
            XCTAssertNil(fixture.window.nativeHandle)

            task.onCancellation = {
                escapedState.wrappedValue = 98
                manager.undo()
                events.cancellationValues.append(escapedState.wrappedValue)
            }
            fixture.runtime.root.launchLifecycleTask(
                ViewLifecycleTaskLaunch(key: "button-teardown-host", priority: .userInitiated) {
                    await task.run()
                })
            await fulfillment(of: [ready], timeout: 5)
            XCTAssertEqual(task.cancelCount, 0)
            XCTAssertTrue(task.isSuspended)

            // Only the retained Button payload owns this capture. The authored
            // root configuration above contains no copy of its action closure.
            let button = installButton(in: fixture.runtime, events: events, name: "host") {
                events.releases.append("host")
                events.cancellationCountsAtRelease.append(task.cancelCount)
                escapedState.wrappedValue = 99
                manager.undo()
                events.stateValuesAtRelease.append(escapedState.wrappedValue)
                events.editorValuesAtRelease.append(document.text)
            }
            let escapedAction = try XCTUnwrap(button.onActivate)
            XCTAssertNotNil(events.payloads["host"]?.value)

            fixture.close()

            XCTAssertEqual(events.releases, ["host"])
            XCTAssertEqual(events.cancellationCountsAtRelease, [1])
            XCTAssertEqual(events.cancellationValues, [7])
            XCTAssertEqual(events.stateValuesAtRelease, [7])
            XCTAssertEqual(events.editorValuesAtRelease, ["ab"])
            XCTAssertEqual(escapedState.wrappedValue, 7)
            XCTAssertEqual(document.text, "ab")
            XCTAssertEqual(document.writes, ["ab"])
            XCTAssertFalse(manager.canUndo)
            XCTAssertFalse(manager.canRedo)
            XCTAssertFalse(task.isSuspended)
            XCTAssertNil(events.payloads["host"]?.value)
            escapedAction()
            XCTAssertTrue(events.activations.isEmpty)
            XCTAssertNil(fixture.window.nativeHandle)
            await fulfillment(of: [completed], timeout: 5)
        }
    }

    func testNestedTerminalCancellationWaitsForTheOuterTaskCohortBeforeButtonRelease() async throws {
        let runtime = makeRuntime()
        let events = ButtonTeardownEvents()
        let ready = expectation(description: "Both cancellation handlers installed")
        ready.expectedFulfillmentCount = 2
        ready.assertForOverFulfill = true
        let completed = expectation(description: "Both lifecycle tasks completed")
        completed.expectedFulfillmentCount = 2
        completed.assertForOverFulfill = true
        let first = ButtonTeardownTaskProbe(name: "first", ready: ready, completed: completed)
        let second = ButtonTeardownTaskProbe(name: "second", ready: ready, completed: completed)
        let tasks = [first, second]
        defer {
            for task in tasks { task.onCancellation = nil }
            finish(runtime)
            for task in tasks { task.release() }
        }
        let button = installButton(in: runtime, events: events, name: "nested") {
            events.releases.append("nested")
            events.cancellationCountsAtRelease.append(tasks.reduce(0) { $0 + $1.cancelCount })
        }
        let escaped = try XCTUnwrap(button.onActivate)
        var reentered = false
        for task in tasks {
            task.onCancellation = {
                if !reentered {
                    reentered = true
                    runtime.cancelRenderLifecycleTasks()
                    events.releasesAfterNestedCancellation.append(events.releases.count)
                    escaped()
                }
            }
            runtime.root.launchLifecycleTask(
                ViewLifecycleTaskLaunch(key: "nested-\(task.name)", priority: .userInitiated) {
                    await task.run()
                })
        }
        await fulfillment(of: [ready], timeout: 5)
        XCTAssertTrue(tasks.allSatisfy(\.isSuspended))

        runtime.stopRenderLifecycleCallbacks()
        XCTAssertTrue(events.releases.isEmpty)
        runtime.cancelRenderLifecycleTasks()

        XCTAssertTrue(reentered)
        XCTAssertEqual(events.releasesAfterNestedCancellation, [0])
        XCTAssertEqual(events.releases, ["nested"])
        XCTAssertEqual(events.cancellationCountsAtRelease, [2])
        XCTAssertEqual(tasks.map(\.cancelCount), [1, 1])
        XCTAssertTrue(tasks.allSatisfy { !$0.isSuspended })
        XCTAssertTrue(events.activations.isEmpty)
        XCTAssertNil(events.payloads["nested"]?.value)
        await fulfillment(of: [completed], timeout: 5)
    }

    func testStoppedStandaloneRuntimeDeallocationCannotReviveButton() async throws {
        var runtime: RetainedViewRuntime? = makeRuntime()
        weak var oldRuntime = runtime
        var activations = 0
        let button = makeButton(runtime: try XCTUnwrap(runtime)) { activations += 1 }
        let escaped = try XCTUnwrap(button.onActivate)
        XCTAssertNil(button.parent)
        escaped()
        XCTAssertEqual(activations, 1)

        runtime?.stopRenderLifecycleCallbacks()
        escaped()
        XCTAssertEqual(activations, 1)
        runtime?.cancelRenderLifecycleTasks()
        runtime = nil

        XCTAssertNil(oldRuntime)
        escaped()
        XCTAssertEqual(activations, 1)
        button.onActivate = nil
        button.onActivate = escaped
        escaped()
        XCTAssertEqual(activations, 1)

        let replacementRuntime = makeRuntime()
        defer { finish(replacementRuntime) }
        replacementRuntime.root.addChild(button)
        escaped()
        XCTAssertEqual(activations, 1)
        let fresh = makeButton(runtime: replacementRuntime) { activations += 1 }
        replacementRuntime.root.addChild(fresh)
        fresh.onActivate?()
        XCTAssertEqual(activations, 2)
    }

    func testOrdinaryRemoveAllFinishesEveryTaskAndDisappearanceBeforeButtonRelease() async throws {
        let runtime = makeRuntime()
        let events = ButtonTeardownEvents()
        let ready = expectation(description: "Departure tasks installed")
        ready.expectedFulfillmentCount = 2
        ready.assertForOverFulfill = true
        let completed = expectation(description: "Departure tasks completed")
        completed.expectedFulfillmentCount = 2
        completed.assertForOverFulfill = true
        let tasks = ["first", "second"].map {
            ButtonTeardownTaskProbe(name: $0, ready: ready, completed: completed)
        }
        defer {
            finish(runtime)
            for task in tasks { task.release() }
            events.handlers = []
        }
        var buttons: [ViewNode] = []
        for task in tasks {
            let button = installButton(in: runtime, events: events, name: task.name) {
                events.releases.append(task.name)
                events.cancellationCountsAtRelease.append(tasks.reduce(0) { $0 + $1.cancelCount })
                events.disappearanceCountsAtRelease.append(events.disappearances.count)
                events.tablesAtRelease.append(runtime.root.children.map(ObjectIdentifier.init))
                for handler in events.handlers { handler() }
            }
            button.onDisappear = { events.disappearances.append(task.name) }
            events.handlers.append { @MainActor [handler = try XCTUnwrap(button.onActivate)] in handler() }
            buttons.append(button)
        }
        _ = runtime.renderScene()
        XCTAssertTrue(buttons.allSatisfy(\.hasAppeared))
        for (button, task) in zip(buttons, tasks) {
            button.launchLifecycleTask(
                ViewLifecycleTaskLaunch(key: "departure-\(task.name)", priority: .userInitiated) {
                    await task.run()
                })
        }
        await fulfillment(of: [ready], timeout: 5)

        runtime.root.removeAllChildren()

        XCTAssertEqual(Set(events.releases), Set(["first", "second"]))
        XCTAssertEqual(events.releases.count, 2)
        XCTAssertEqual(events.cancellationCountsAtRelease, [2, 2])
        XCTAssertEqual(events.disappearanceCountsAtRelease, [2, 2])
        XCTAssertEqual(events.tablesAtRelease, [[], []])
        XCTAssertTrue(events.activations.isEmpty)
        XCTAssertEqual(tasks.map(\.cancelCount), [1, 1])
        XCTAssertTrue(buttons.allSatisfy { $0.parent == nil && !$0.hasAppeared })
        XCTAssertTrue(events.payloads.values.allSatisfy { $0.value == nil })
        await fulfillment(of: [completed], timeout: 5)
    }

    func testOrdinarySingleChildRemovalFinishesTaskBeforeButtonRelease() async throws {
        for operation in ButtonTeardownRemoval.allCases {
            let runtime = makeRuntime()
            let events = ButtonTeardownEvents()
            let ready = expectation(description: "Task installed for \(operation)")
            let completed = expectation(description: "Task completed for \(operation)")
            let task = ButtonTeardownTaskProbe(name: "single", ready: ready, completed: completed)
            let replacement = ViewNode(frame: Rect(x: 0, y: 0, width: 50, height: 30))
            defer {
                finish(runtime)
                task.release()
                events.handlers = []
            }
            let button = installButton(in: runtime, events: events, name: "single") {
                events.releases.append("single")
                events.cancellationCountsAtRelease.append(task.cancelCount)
                events.disappearanceCountsAtRelease.append(events.disappearances.count)
                events.tablesAtRelease.append(runtime.root.children.map(ObjectIdentifier.init))
                for handler in events.handlers { handler() }
            }
            events.handlers.append { @MainActor [handler = try XCTUnwrap(button.onActivate)] in handler() }
            button.onDisappear = { events.disappearances.append("single") }
            _ = runtime.renderScene()
            XCTAssertTrue(button.hasAppeared)
            button.launchLifecycleTask(
                ViewLifecycleTaskLaunch(key: "single-departure", priority: .userInitiated) {
                    await task.run()
                })
            await fulfillment(of: [ready], timeout: 5)

            switch operation {
            case .remove:
                runtime.root.removeChild(button)
            case .replace:
                runtime.root.replaceChild(at: 0, with: replacement)
            case .setChildren:
                XCTAssertTrue(runtime.root.setChildren([]).completed)
            }

            let expectedTable = operation == .replace ? [ObjectIdentifier(replacement)] : []
            XCTAssertEqual(events.releases, ["single"])
            XCTAssertEqual(events.cancellationCountsAtRelease, [1])
            XCTAssertEqual(events.disappearanceCountsAtRelease, [1])
            XCTAssertEqual(events.tablesAtRelease, [expectedTable])
            XCTAssertTrue(events.activations.isEmpty)
            XCTAssertNil(events.payloads["single"]?.value)
            XCTAssertNil(button.parent)
            XCTAssertFalse(button.hasAppeared)
            await fulfillment(of: [completed], timeout: 5)
        }
    }

    private func makeRuntime() -> RetainedViewRuntime {
        RetainedViewRuntime(
            root: ViewNode(frame: Rect(x: 0, y: 0, width: 400, height: 300), isHitTestVisible: false))
    }

    private func makeButton(runtime: RetainedViewRuntime, action: @escaping @MainActor () -> Void) -> ViewNode {
        Controls.button(
            runtime: runtime, frame: Rect(x: 0, y: 0, width: 80, height: 30),
            cornerRadius: 4, palette: SurfacePalette(idle: .black, focused: .black, pressed: .black),
            action: action)
    }

    @inline(never)
    private func installButton(
        in runtime: RetainedViewRuntime, events: ButtonTeardownEvents, name: String,
        onRelease: @escaping @MainActor () -> Void
    ) -> ViewNode {
        let payload = ButtonTeardownReleaseProbe(onRelease)
        events.payloads[name] = ButtonTeardownWeakProbe(payload)
        let button = makeButton(runtime: runtime) { [payload] in
            events.activations.append(name)
            withExtendedLifetime(payload) {}
        }
        runtime.root.addChild(button)
        return button
    }

    private func finish(_ runtime: RetainedViewRuntime) {
        runtime.stopRenderLifecycleCallbacks()
        runtime.cancelRenderLifecycleTasks()
        runtime.root.removeAllChildren()
    }

    private func withTextLayout(_ body: @MainActor () async throws -> Void) async rethrows {
        NativeTextRenderer.testingOverrides.layout = { text, style, _, _ in
            let glyphs = Array(text).enumerated().map { index, character in
                NativeTextGlyphLayout(
                    character: character, origin: Point(x: Double(index) * 9, y: 0), advance: 9,
                    glyphID: UInt32(index + 1), fontFamily: style.fontFamily, weight: style.weight,
                    fontSize: style.nativeFontPixelSize, sourceIndex: index)
            }
            let size = Size(width: Double(max(text.count, 1)) * 9, height: max(style.nativeFontPixelSize, 1))
            return NativeTextLayoutResult(
                lines: [NativeTextLineLayout(text: text, width: size.width, height: size.height, glyphs: glyphs)],
                contentSize: size, measuredSize: size)
        }
        defer { NativeTextRenderer.resetTestingOverrides() }
        try await body()
    }
}

private enum ButtonTeardownRemoval: CaseIterable, Equatable {
    case remove
    case replace
    case setChildren
}

@MainActor
private final class ButtonTeardownReleaseProbe {
    let onRelease: @MainActor () -> Void

    init(_ onRelease: @escaping @MainActor () -> Void) { self.onRelease = onRelease }

    isolated deinit { onRelease() }
}

@MainActor
private final class ButtonTeardownWeakProbe {
    weak var value: ButtonTeardownReleaseProbe?

    init(_ value: ButtonTeardownReleaseProbe) { self.value = value }
}

@MainActor
private final class ButtonTeardownEvents {
    var payloads: [String: ButtonTeardownWeakProbe] = [:]
    var handlers: [@MainActor () -> Void] = []
    var activations: [String] = []
    var releases: [String] = []
    var disappearances: [String] = []
    var cancellationValues: [Int] = []
    var cancellationCountsAtRelease: [Int] = []
    var disappearanceCountsAtRelease: [Int] = []
    var stateValuesAtRelease: [Int] = []
    var editorValuesAtRelease: [String] = []
    var releasesAfterNestedCancellation: [Int] = []
    var tablesAtRelease: [[ObjectIdentifier]] = []
}

/// The test causes cancellation only from MainActor runtime/host teardown.
/// Readiness acknowledges that the handler and continuation are installed.
@MainActor
private final class ButtonTeardownTaskProbe {
    let name: String
    let ready: XCTestExpectation
    let completed: XCTestExpectation
    private(set) var cancelCount = 0
    var onCancellation: (@MainActor () -> Void)?
    private var continuation: CheckedContinuation<Void, Never>?
    private var wasReleased = false

    var isSuspended: Bool { continuation != nil }

    init(name: String, ready: XCTestExpectation, completed: XCTestExpectation) {
        self.name = name
        self.ready = ready
        self.completed = completed
    }

    func run() async {
        await withTaskCancellationHandler(
            operation: {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    if Task.isCancelled || wasReleased {
                        continuation.resume()
                    } else {
                        self.continuation = continuation
                    }
                    ready.fulfill()
                }
            },
            onCancel: { [weak self] in
                let probe = self
                MainActor.assumeIsolated { probe?.cancel() }
            })
        completed.fulfill()
    }

    private func cancel() {
        guard cancelCount == 0 else { return }
        cancelCount += 1
        let previous = continuation
        continuation = nil
        onCancellation?()
        previous?.resume()
    }

    func release() {
        wasReleased = true
        let previous = continuation
        continuation = nil
        previous?.resume()
    }
}

@MainActor
private final class ButtonTeardownBindingCapture {
    var binding: Binding<Int>?
}

@MainActor
private final class ButtonTeardownDocument {
    var text = "a"
    var writes: [String] = []
}

@MainActor
private struct ButtonTeardownRoot: View {
    @State private var value = 7
    let capture: ButtonTeardownBindingCapture
    let document: ButtonTeardownDocument

    var body: some View {
        capture.binding = $value
        let text = Binding<String>(
            get: { document.text },
            set: {
                document.writes.append($0)
                document.text = $0
            })
        return VStack {
            TextField("Text", text: text)
                .accessibilityIdentifier("button-teardown.editor")
                .frame(width: 320, height: 44)
            Text(String(value))
        }
    }
}

@MainActor
private final class ButtonTeardownHost {
    let host: WinSwiftUIWindowHost
    let window: Win32Window
    let clock: RuntimeTestClock

    var runtime: RetainedViewRuntime { host.hostedRuntime }

    init<Content: View>(_ content: Content) {
        let clock = RuntimeTestClock()
        clock.now = 5_000
        let surface = SurfaceDescriptor(offscreenPixelSize: IntSize(width: 640, height: 400), scaleFactor: 1)
        let window = Win32Window(title: "Button teardown", clientSize: surface.pixelSize)
        let host = WinSwiftUIWindowHost(
            configuration: WindowGroupConfiguration(
                title: "Button teardown", size: surface.pixelSize, clearColor: .black,
                content: [AnyView(content)]),
            platformWindow: window, renderer: FakeRenderBackend(), batchRenderer: FakeBatchRenderBackend(),
            surfaceDescriptorProvider: { _ in surface }, startupProbeConfiguration: nil)
        self.clock = clock
        self.window = window
        self.host = host
        host.frameClock = { clock.now }
        runtime.clock = { clock.now }
        host.windowDidCreate(window)
        flush()
        XCTAssertNil(window.nativeHandle)
    }

    func flush() {
        for _ in 0..<2 {
            clock.now += 0.02
            host.windowNeedsDisplay(window)
            _ = runtime.renderScene(at: clock.now)
        }
    }

    func focusEditor() throws {
        var nodes = [runtime.root]
        var editor: ViewNode?
        while let node = nodes.popLast() {
            if node.accessibilityIdentifier == "button-teardown.editor",
                node.accessibilityTraits.contains(.isTextInput)
            {
                editor = node
                break
            }
            nodes.append(contentsOf: node.children)
        }
        runtime.requestFocus(try XCTUnwrap(editor))
        flush()
    }

    func type(_ text: String) {
        host.window(window, didInputText: text)
        flush()
    }

    func close() { host.windowWillClose(window) }
}
