import SwiftWindowsCore
@preconcurrency import XCTest

@testable import SwiftWindowsUI

@MainActor
final class RetainedPrepaintTeardownTests: XCTestCase {
    func testTerminalPrepaintReleaseWaitsForOuterTaskCleanupAndCannotBeRepublished() async throws {
        let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 80, height: 60)))
        let events = TerminalPrepaintEvents()
        var row: ViewNode? = terminalPrepaintRow(events)
        weak var weakRow = row
        runtime.root.addChild(try XCTUnwrap(row))
        _ = runtime.renderFrame()
        XCTAssertTrue(terminalPrepaintContains(runtime, try XCTUnwrap(row)))
        row?.removeFromParent()
        row = nil
        XCTAssertNotNil(weakRow, "The prior prepaint is the detached row's surviving owner")
        XCTAssertNotNil(events.payload)

        let ready = expectation(description: "Lifecycle task has installed its cancellation handler")
        let completed = expectation(description: "Lifecycle task returned")
        let task = TerminalPrepaintTask(events: events, ready: ready, completed: completed)
        defer {
            task.onCancellation = nil
            task.release()
            runtime.stopRenderLifecycleCallbacks()
            runtime.cancelRenderLifecycleTasks()
            runtime.root.removeAllChildren()
        }
        task.onCancellation = { [weak runtime] in
            guard let runtime else { return }
            XCTAssertNotNil(events.payload)
            runtime.cancelRenderLifecycleTasks()
            XCTAssertNotNil(events.payload, "Nested cancellation cannot release the outer cohort's captures")
            _ = runtime.renderScene()
            XCTAssertNotNil(events.payload, "Closed rendering must not replace the prepass-owned snapshot")
        }
        runtime.root.launchLifecycleTask(
            ViewLifecycleTaskLaunch(key: "terminal-prepaint", priority: .userInitiated) { await task.run() })
        await fulfillment(of: [ready], timeout: 5)

        runtime.stopRenderLifecycleCallbacks()

        XCTAssertNotNil(weakRow)
        XCTAssertNotNil(events.payload)
        XCTAssertEqual(events.cancellations, 0)
        XCTAssertTrue(events.cancellationsAtRelease.isEmpty)

        runtime.cancelRenderLifecycleTasks()

        XCTAssertNil(weakRow)
        XCTAssertNil(events.payload)
        XCTAssertEqual(events.cancellationsAtRelease, [1])
        XCTAssertTrue(runtime.currentPrepaintState.dispatchNodes.isEmpty)
        XCTAssertTrue(runtime.currentPrepaintState.interactions.isEmpty)
        XCTAssertTrue(runtime.currentPrepaintState.deferredSubtrees.isEmpty)
        XCTAssertTrue(runtime.currentPrepaintState.deferredDraws.isEmpty)
        XCTAssertFalse(runtime.hasCurrentAccessibilityPrepaint)

        // The closed runtime can remain alive and be inspected or rendered.
        // It must not acquire another lasting owner through its prepaint cache.
        var later: ViewNode? = terminalPrepaintRow(events)
        weak var weakLater = later
        runtime.root.addChild(try XCTUnwrap(later))
        _ = runtime.renderScene()
        _ = runtime.renderFrame()
        XCTAssertTrue(runtime.currentPrepaintState.dispatchNodes.isEmpty)
        XCTAssertTrue(runtime.currentPrepaintState.deferredDraws.isEmpty)
        XCTAssertFalse(runtime.hasCurrentAccessibilityPrepaint)
        runtime.root.removeAllChildren()
        later = nil
        XCTAssertNil(weakLater)
        XCTAssertNil(events.payload)
        XCTAssertEqual(events.cancellationsAtRelease, [1, 1])
        runtime.stopRenderLifecycleCallbacks()
        runtime.cancelRenderLifecycleTasks()
        XCTAssertEqual(events.cancellationsAtRelease, [1, 1])
        await fulfillment(of: [completed], timeout: 5)

        for scene in [false, true] { try assertTerminalCloseDuringDeferredPaint(scene: scene) }
    }
}

@MainActor
private func assertTerminalCloseDuringDeferredPaint(scene: Bool) throws {
    let runtime = RetainedViewRuntime(root: ViewNode(frame: Rect(x: 0, y: 0, width: 80, height: 60)))
    let events = TerminalPrepaintEvents()
    var row: ViewNode? = terminalPrepaintRow(events)
    weak var weakRow = row
    var callbacks = 0
    row?.paintsInDeferredPhase = true
    row?.canvasDraw = { [weak runtime] _, _ in
        guard let runtime else { return }
        callbacks += 1
        XCTAssertFalse(runtime.currentPrepaintState.deferredDraws.isEmpty)
        runtime.stopRenderLifecycleCallbacks()
        runtime.cancelRenderLifecycleTasks()
        XCTAssertFalse(
            runtime.currentPrepaintState.deferredDraws.isEmpty,
            "The active painter still needs its deferred draw indices after this callback")
    }
    runtime.root.addChild(try XCTUnwrap(row))

    if scene { _ = runtime.renderScene() } else { _ = runtime.renderFrame() }

    XCTAssertEqual(callbacks, 1)
    XCTAssertTrue(runtime.currentPrepaintState.dispatchNodes.isEmpty)
    XCTAssertTrue(runtime.currentPrepaintState.deferredDraws.isEmpty)
    XCTAssertFalse(runtime.hasCurrentAccessibilityPrepaint)
    runtime.root.removeAllChildren()
    row = nil
    XCTAssertNil(weakRow)
    XCTAssertNil(events.payload)
    XCTAssertEqual(events.cancellationsAtRelease, [0])
}

@MainActor
private final class TerminalPrepaintEvents {
    weak var payload: TerminalPrepaintPayload?
    var cancellations = 0
    var cancellationsAtRelease: [Int] = []
}

@MainActor
private final class TerminalPrepaintPayload {
    let events: TerminalPrepaintEvents
    init(_ events: TerminalPrepaintEvents) { self.events = events }
    isolated deinit { events.cancellationsAtRelease.append(events.cancellations) }
}

@MainActor
@inline(never)
private func terminalPrepaintRow(_ events: TerminalPrepaintEvents) -> ViewNode {
    let payload = TerminalPrepaintPayload(events)
    events.payload = payload
    let node = ViewNode(frame: Rect(x: 0, y: 0, width: 80, height: 20))
    node.onKeyDown = { _ in withExtendedLifetime(payload) {} }
    return node
}

@MainActor
@inline(never)
private func terminalPrepaintContains(_ runtime: RetainedViewRuntime, _ node: ViewNode) -> Bool {
    runtime.currentPrepaintState.dispatchNodes.contains { $0.node === node }
}

@MainActor
private final class TerminalPrepaintTask {
    let events: TerminalPrepaintEvents
    let ready: XCTestExpectation
    let completed: XCTestExpectation
    var onCancellation: (@MainActor () -> Void)?
    private var continuation: CheckedContinuation<Void, Never>?
    private var wasReleased = false

    init(events: TerminalPrepaintEvents, ready: XCTestExpectation, completed: XCTestExpectation) {
        self.events = events
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
                let task = self
                MainActor.assumeIsolated { task?.cancel() }
            })
        completed.fulfill()
    }

    private func cancel() {
        guard events.cancellations == 0 else { return }
        events.cancellations += 1
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
