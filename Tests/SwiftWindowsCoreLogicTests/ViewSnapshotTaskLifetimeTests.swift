import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class ViewSnapshotTaskLifetimeTests: XCTestCase {
    func testOwnedSingleComponentSuccessCancelsItsTaskWithoutRetainingTheTree() async throws {
        let probe = SnapshotTaskLifetimeProbe()
        let gate = SnapshotTaskLifetimeGate()
        defer { gate.releaseSuspensions() }

        let bitmap = try rasterizeOwned(.single, probe: probe, gate: gate)

        XCTAssertNil(probe.runtime)
        XCTAssertNil(probe.node)
        XCTAssertEqual(bitmap.width, 32)
        XCTAssertEqual(bitmap.height, 24)
        XCTAssertEqual(bitmap.pixelColor(atX: 8, y: 8), Color.white)
        await assertOwnedLifetimeEnded(probe: probe, gate: gate)
    }

    func testOwnedComponentBuilderSuccessCancelsItsTaskWithoutRetainingTheTree() async throws {
        let probe = SnapshotTaskLifetimeProbe()
        let gate = SnapshotTaskLifetimeGate()
        defer { gate.releaseSuspensions() }

        let bitmap = try rasterizeOwned(.builder, probe: probe, gate: gate)

        XCTAssertNil(probe.runtime)
        XCTAssertNil(probe.node)
        XCTAssertEqual(bitmap.width, 32)
        XCTAssertEqual(bitmap.height, 24)
        XCTAssertEqual(bitmap.pixelColor(atX: 8, y: 8), Color.white)
        await assertOwnedLifetimeEnded(probe: probe, gate: gate)
    }

    func testBothOwnedOverloadsCancelTasksWhenRasterizationThrowsAfterSceneRendering() async throws {
        for overload in [OwnedSnapshotOverload.single, .builder] {
            let probe = SnapshotTaskLifetimeProbe()
            let gate = SnapshotTaskLifetimeGate()
            defer { gate.releaseSuspensions() }

            assertInvalidSize {
                try rasterizeOwned(overload, probe: probe, gate: gate, size: Size(width: 0, height: 24))
            }

            XCTAssertNil(probe.runtime)
            XCTAssertNil(probe.node)
            // The invalid-size error comes from the CPU renderer after the
            // scene pass. This must exercise a launched task, not an early
            // argument rejection that never created a lifecycle owner.
            XCTAssertEqual(probe.appearances, 1)
            XCTAssertEqual(probe.launches, 1)
            await assertOwnedLifetimeEnded(probe: probe, gate: gate)
        }
    }

    func testBorrowedRuntimeSuccessAndFailureLeaveItsTaskActiveUntilCallerCleanup() async throws {
        for throwsDuringRasterization in [false, true] {
            let probe = SnapshotTaskLifetimeProbe()
            let gate = SnapshotTaskLifetimeGate()
            let runtime = RetainedViewRuntime(clearColor: .black)
            let host = ComponentHost(runtime: runtime)
            host.setContent(snapshotTaskComponent(probe: probe, gate: gate))
            runtime.setRootSize(IntSize(width: 32, height: 24))
            defer {
                runtime.stopRenderLifecycleCallbacks()
                runtime.cancelRenderLifecycleTasks()
                gate.releaseSuspensions()
            }
            _ = runtime.renderScene()
            await flushUntil { gate.entries.count == 1 && gate.suspendedCount == 1 }
            XCTAssertEqual(gate.entries, [false])
            XCTAssertEqual(gate.suspendedCount, 1)

            if throwsDuringRasterization {
                assertInvalidSize {
                    try ViewSnapshot.rasterize(runtime: runtime, size: Size(width: 0, height: 24))
                }
            } else {
                let bitmap = try ViewSnapshot.rasterize(runtime: runtime, size: Size(width: 32, height: 24))
                XCTAssertEqual(bitmap.pixelColor(atX: 8, y: 8), Color.white)
            }
            await flushExecutor()

            XCTAssertTrue(probe.runtime === runtime)
            XCTAssertNotNil(probe.node)
            XCTAssertNotNil(probe.payload)
            XCTAssertEqual(probe.appearances, 1)
            XCTAssertEqual(probe.disappearances, 0)
            XCTAssertEqual(gate.entries, [false])
            XCTAssertTrue(
                gate.cancelled.isEmpty, "A borrowed runtime must keep its active task after the helper returns")
            XCTAssertTrue(gate.completed.isEmpty)
            XCTAssertEqual(gate.suspendedCount, 1)

            runtime.stopRenderLifecycleCallbacks()
            runtime.cancelRenderLifecycleTasks()
            await flushUntil { gate.cancelled == Set([0]) && gate.completed == Set([0]) }

            XCTAssertEqual(gate.cancelled, Set([0]))
            XCTAssertEqual(gate.completed, Set([0]))
            XCTAssertEqual(gate.suspendedCount, 0)
            XCTAssertEqual(probe.disappearances, 0)
            // The caller deliberately still owns the node and its declaration.
            // No payload-release expectation is imposed on that live tree.
            withExtendedLifetime((runtime, host)) {}
        }
    }

    func testPublicSnapshottersReturnedRuntimeKeepsItsTaskUntilCallerStopsIt() async throws {
        let probe = SnapshotTaskLifetimeProbe()
        let gate = SnapshotTaskLifetimeGate()
        var snapshot: WinSwiftUIRenderSnapshot? = makeReturnedSnapshot(probe: probe, gate: gate)
        defer {
            snapshot?.runtime.stopRenderLifecycleCallbacks()
            snapshot?.runtime.cancelRenderLifecycleTasks()
            snapshot = nil
            gate.releaseSuspensions()
        }
        captureReturnedSnapshot(try XCTUnwrap(snapshot), in: probe)
        await flushUntil { gate.entries.count == 1 && gate.suspendedCount == 1 }

        XCTAssertNotNil(probe.runtime)
        XCTAssertNotNil(probe.node)
        XCTAssertNotNil(probe.payload)
        XCTAssertEqual(gate.entries, [false])
        XCTAssertEqual(gate.suspendedCount, 1)
        XCTAssertEqual(probe.appearances, 1)
        XCTAssertEqual(probe.disappearances, 0)
        _ = snapshot?.runtime.renderScene(at: 5_001)
        await flushExecutor()
        XCTAssertTrue(gate.cancelled.isEmpty)
        XCTAssertTrue(gate.completed.isEmpty)
        XCTAssertEqual(gate.entries.count, 1)

        snapshot?.runtime.stopRenderLifecycleCallbacks()
        snapshot?.runtime.cancelRenderLifecycleTasks()
        await flushUntil { gate.cancelled == Set([0]) && gate.completed == Set([0]) }

        XCTAssertEqual(gate.cancelled, Set([0]))
        XCTAssertEqual(gate.completed, Set([0]))
        XCTAssertEqual(gate.suspendedCount, 0)
        XCTAssertEqual(probe.disappearances, 0)
        // The public snapshot owns its declaration, including the task action.
        // Release that intentional owner before inspecting payload lifetime.
        snapshot = nil
        await flushUntil {
            probe.runtime == nil && probe.node == nil && probe.payload == nil && probe.payloadReleases == 1
        }
        XCTAssertNil(probe.runtime)
        XCTAssertNil(probe.node)
        XCTAssertNil(probe.payload)
        XCTAssertEqual(probe.payloadReleases, 1)
        XCTAssertTrue(probe.payloadReleasedAfterCompletion)
    }

    private func rasterizeOwned(
        _ overload: OwnedSnapshotOverload,
        probe: SnapshotTaskLifetimeProbe,
        gate: SnapshotTaskLifetimeGate,
        size: Size = Size(width: 32, height: 24)
    ) throws -> BitmapSurface {
        let component = snapshotTaskComponent(probe: probe, gate: gate)
        switch overload {
        case .single:
            return try ViewSnapshot.rasterize(component: component, size: size)
        case .builder:
            return try ViewSnapshot.rasterize(components: { component }, size: size)
        }
    }

    private func assertInvalidSize(
        _ operation: () throws -> BitmapSurface, file: StaticString = #filePath, line: UInt = #line
    ) {
        do {
            _ = try operation()
            XCTFail("Expected the CPU renderer's invalid-size error", file: file, line: line)
        } catch {
            guard let rendererError = error as? CPUBatchRendererError,
                case .invalidSize(let size) = rendererError
            else {
                return XCTFail("Unexpected rasterization error: \(error)", file: file, line: line)
            }
            XCTAssertEqual(size, IntSize(width: 0, height: 24), file: file, line: line)
        }
    }

    private func assertOwnedLifetimeEnded(
        probe: SnapshotTaskLifetimeProbe, gate: SnapshotTaskLifetimeGate,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        XCTAssertEqual(probe.appearances, 1, file: file, line: line)
        XCTAssertEqual(probe.launches, 1, file: file, line: line)
        XCTAssertNil(probe.runtime, "The task must not capture the temporary runtime", file: file, line: line)
        XCTAssertNil(probe.node, "The task must not capture its temporary node", file: file, line: line)
        // A synchronous snapshot cannot await its newly created task. The
        // body may enter already cancelled, and completion is cooperative.
        await flushUntil { gate.completed == Set([0]) && probe.payload == nil && probe.payloadReleases == 1 }
        XCTAssertEqual(gate.entries.count, 1, file: file, line: line)
        XCTAssertEqual(gate.cancelled, Set([0]), file: file, line: line)
        XCTAssertEqual(gate.completed, Set([0]), file: file, line: line)
        XCTAssertEqual(gate.suspendedCount, 0, file: file, line: line)
        XCTAssertNil(probe.payload, file: file, line: line)
        XCTAssertEqual(probe.payloadReleases, 1, file: file, line: line)
        XCTAssertTrue(probe.payloadReleasedAfterCompletion, file: file, line: line)
        XCTAssertEqual(
            probe.disappearances, 0, "Ownership cleanup is not a synthetic disappearance", file: file, line: line)
    }

    private func flushUntil(_ condition: @MainActor () -> Bool) async {
        for _ in 0..<64 {
            if condition() { return }
            await Task.yield()
        }
    }

    private func flushExecutor() async {
        for _ in 0..<8 { await Task.yield() }
    }

    private func makeReturnedSnapshot(
        probe: SnapshotTaskLifetimeProbe, gate: SnapshotTaskLifetimeGate
    ) -> WinSwiftUIRenderSnapshot {
        let payload = SnapshotTaskPayload(probe: probe, gate: gate)
        probe.payload = payload
        let view = Rectangle().fill(Color.white)
            .frame(width: 32, height: 24)
            .accessibilityIdentifier("returned-snapshot-task")
            .onAppear { [weak probe] in probe?.appearances += 1 }
            .onDisappear { [weak probe] in probe?.disappearances += 1 }
            .task { [payload, gate] in await gate.run(payload: payload) }
        return WinSwiftUIRendererSnapshotter.snapshot(of: view, size: IntSize(width: 32, height: 24), timestamp: 5_000)
    }

    private func captureReturnedSnapshot(
        _ snapshot: WinSwiftUIRenderSnapshot, in probe: SnapshotTaskLifetimeProbe
    ) {
        probe.runtime = snapshot.runtime
        var pending = [snapshot.runtime.root]
        while let node = pending.popLast() {
            if node.accessibilityIdentifier == "returned-snapshot-task" {
                probe.node = node
                return
            }
            pending.append(contentsOf: node.children)
        }
        XCTFail("The public task view was not installed in the returned runtime")
    }
}

private enum OwnedSnapshotOverload {
    case single
    case builder
}

@MainActor
private final class SnapshotTaskLifetimeProbe {
    weak var runtime: RetainedViewRuntime?
    weak var node: ViewNode?
    weak var payload: SnapshotTaskPayload?
    var appearances = 0
    var disappearances = 0
    var launches = 0
    var payloadReleases = 0
    var payloadReleasedAfterCompletion = false
}

@MainActor
private final class SnapshotTaskPayload {
    private weak var probe: SnapshotTaskLifetimeProbe?
    private weak var gate: SnapshotTaskLifetimeGate?

    init(probe: SnapshotTaskLifetimeProbe, gate: SnapshotTaskLifetimeGate) {
        self.probe = probe
        self.gate = gate
    }

    isolated deinit {
        probe?.payloadReleases += 1
        probe?.payloadReleasedAfterCompletion = gate?.completed.isEmpty == false
    }
}

@MainActor
private final class SnapshotTaskLaunchBox {
    var payload: SnapshotTaskPayload?

    init(_ payload: SnapshotTaskPayload) { self.payload = payload }

    func take() -> SnapshotTaskPayload? {
        let result = payload
        payload = nil
        return result
    }
}

@MainActor
private func snapshotTaskComponent(probe: SnapshotTaskLifetimeProbe, gate: SnapshotTaskLifetimeGate) -> Component {
    Component { runtime in
        let node = ViewNode()
        node.frame = Rect(x: 0, y: 0, width: 32, height: 24)
        node.backgroundColor = .white
        probe.runtime = runtime
        probe.node = node
        let payload = SnapshotTaskPayload(probe: probe, gate: gate)
        probe.payload = payload
        let launchBox = SnapshotTaskLaunchBox(payload)
        node.onAppear = { [weak probe] in probe?.appearances += 1 }
        node.onDisappear = { [weak probe] in probe?.disappearances += 1 }
        node.onAppearWithNode = { [launchBox, gate, weak probe] appearingNode in
            guard let payload = launchBox.take() else { return }
            probe?.launches += 1
            // No node or runtime enters the task's capture graph. The box
            // also stops retaining the payload once the task owns it.
            appearingNode.launchLifecycleTask(
                ViewLifecycleTaskLaunch(
                    key: "owned-snapshot-task", priority: .userInitiated,
                    action: { [payload, gate] in await gate.run(payload: payload) }))
        }
        return node
    }
}

@MainActor
private final class SnapshotTaskLifetimeGate {
    private(set) var entries: [Bool] = []
    private(set) var cancelled = Set<Int>()
    private(set) var completed = Set<Int>()
    private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var isFinishing = false

    var suspendedCount: Int { continuations.count }

    func run(payload: SnapshotTaskPayload) async {
        let identifier = entries.count
        entries.append(Task.isCancelled)
        defer { withExtendedLifetime(payload) {} }
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                if Task.isCancelled || cancelled.contains(identifier) {
                    observeCancellation(identifier)
                    continuation.resume()
                } else if isFinishing {
                    continuation.resume()
                } else {
                    continuations[identifier] = continuation
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.observeCancellation(identifier) }
        }
        completed.insert(identifier)
    }

    private func observeCancellation(_ identifier: Int) {
        cancelled.insert(identifier)
        continuations.removeValue(forKey: identifier)?.resume()
    }

    func releaseSuspensions() {
        isFinishing = true
        let pending = Array(continuations.values)
        continuations.removeAll()
        for continuation in pending { continuation.resume() }
    }
}
