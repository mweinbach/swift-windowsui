import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsDemo
@testable import SwiftWindowsUI
@testable import WinSwiftUI

enum DemoDashboardDataTestError: Error { case timedOut, missingRead, missingControl }

/// Holds actual encoded-byte delivery, not model outcomes. Cancellation records
/// intent but deliberately does not complete the physical read until released.
final class DemoDashboardDataGate: @unchecked Sendable {
    struct Start: Equatable, Sendable {
        let id: Int
        let sample: DemoDashboardDataSample
        let wasCancelledAtEntry: Bool
    }

    struct Snapshot: Sendable {
        let starts: [Start]
        let active: Set<Int>
        let cancellations: Set<Int>
        let maximumConcurrent: Int
    }

    private enum Milestone {
        case starts(Int)
        case cancelled(Int)

        func reached(_ state: State) -> Bool {
            switch self {
            case .starts(let count): return state.starts.count >= count
            case .cancelled(let id): return state.cancellations.contains(id)
            }
        }
    }

    private final class Waiter {
        let milestone: Milestone
        let expectation = XCTestExpectation(description: "dashboard local reader event")
        var reached = false

        init(_ milestone: Milestone) { self.milestone = milestone }
    }

    private struct State {
        var starts: [Start] = []
        var active: Set<Int> = []
        var cancellations: Set<Int> = []
        var maximumConcurrent = 0
        var continuations: [Int: CheckedContinuation<Data, Error>] = [:]
        var results: [Int: Result<Data, Error>] = [:]
        var waiters: [Waiter] = []
        var closed = false
    }

    private let lock = NSLock()
    private var state = State()

    var snapshot: Snapshot {
        locked {
            Snapshot(
                starts: $0.starts, active: $0.active, cancellations: $0.cancellations,
                maximumConcurrent: $0.maximumConcurrent)
        }
    }

    func read(_ sample: DemoDashboardDataSample) async throws -> Data {
        let id = try locked { state in
            guard !state.closed else { throw CancellationError() }
            let id = state.starts.count
            state.starts.append(Start(id: id, sample: sample, wasCancelledAtEntry: Task.isCancelled))
            state.active.insert(id)
            state.maximumConcurrent = max(state.maximumConcurrent, state.active.count)
            return id
        }
        defer {
            locked {
                $0.active.remove(id)
                $0.results.removeValue(forKey: id)
            }
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let buffered = locked { state -> Result<Data, Error>? in
                    if state.closed { return .failure(CancellationError()) }
                    if let result = state.results[id] { return result }
                    state.continuations[id] = continuation
                    return nil
                }
                if let buffered { continuation.resume(with: buffered) }
                releaseWaiters()
            }
        } onCancel: {
            _ = self.locked { $0.cancellations.insert(id) }
            self.releaseWaiters()
        }
    }

    @discardableResult
    func finish(_ id: Int, result: Result<Data, Error>) -> Bool {
        let completion = locked { state -> (Bool, CheckedContinuation<Data, Error>?) in
            guard !state.closed, state.active.contains(id), state.results[id] == nil else { return (false, nil) }
            state.results[id] = result
            return (true, state.continuations.removeValue(forKey: id))
        }
        completion.1?.resume(with: result)
        return completion.0
    }

    func close() {
        let cleanup = locked { state in
            state.closed = true
            let reads = Array(state.continuations.values)
            let waiting = state.waiters
            state.continuations.removeAll()
            state.waiters.removeAll()
            state.results.removeAll()
            return (reads, waiting)
        }
        for read in cleanup.0 { read.resume(throwing: CancellationError()) }
        for waiter in cleanup.1 { waiter.expectation.fulfill() }
    }

    func waitForStarts(_ count: Int) async -> Bool { await wait(.starts(count)) }
    func waitForCancellation(_ id: Int) async -> Bool { await wait(.cancelled(id)) }

    private func wait(_ milestone: Milestone) async -> Bool {
        let waiter = Waiter(milestone)
        let immediate = locked { state -> Bool? in
            if milestone.reached(state) { return true }
            if state.closed { return false }
            state.waiters.append(waiter)
            return nil
        }
        if let immediate { return immediate }
        let result = await XCTWaiter.fulfillment(of: [waiter.expectation], timeout: 5)
        guard result == .completed else {
            close()
            return false
        }
        return locked { _ in waiter.reached }
    }

    private func releaseWaiters() {
        let ready = locked { state in
            let pending = state.waiters
            state.waiters.removeAll()
            var ready: [Waiter] = []
            for waiter in pending {
                if waiter.milestone.reached(state) {
                    waiter.reached = true
                    ready.append(waiter)
                } else {
                    state.waiters.append(waiter)
                }
            }
            return ready
        }
        for waiter in ready { waiter.expectation.fulfill() }
    }

    private func locked<Value>(_ body: (inout State) throws -> Value) rethrows -> Value {
        lock.lock()
        defer { lock.unlock() }
        return try body(&state)
    }
}

@MainActor
func dashboardDataAwait(
    _ task: Task<Void, Never>, file: StaticString = #filePath, line: UInt = #line
) async throws {
    let completed = XCTestExpectation(description: "model-owned dashboard task returned")
    let waiting = Task { @MainActor in
        await task.value
        completed.fulfill()
    }
    defer { waiting.cancel() }
    let result = await XCTWaiter.fulfillment(of: [completed], timeout: 5)
    guard result == .completed else {
        task.cancel()
        XCTFail("The actual dashboard task did not return", file: file, line: line)
        throw DemoDashboardDataTestError.timedOut
    }
}

@MainActor
final class DemoDashboardDataHarness {
    let gate: DemoDashboardDataGate
    let service: DemoDashboardDataService
    let model: DemoDashboardDataModel

    init() {
        let gate = DemoDashboardDataGate()
        self.gate = gate
        let service = DemoDashboardDataService { try await gate.read($0) }
        self.service = service
        model = DemoDashboardDataModel(service: service)
    }

    func close() {
        model.close()
        gate.close()
    }

    func starts(_ count: Int, file: StaticString = #filePath, line: UInt = #line) async throws {
        let reached = await gate.waitForStarts(count)
        XCTAssertTrue(reached, "Expected \(count) physical local reads", file: file, line: line)
        guard reached else { throw DemoDashboardDataTestError.missingRead }
    }

    func cancelled(_ id: Int, file: StaticString = #filePath, line: UInt = #line) async throws {
        let reached = await gate.waitForCancellation(id)
        XCTAssertTrue(reached, "Expected cancellation to reach physical read \(id)", file: file, line: line)
        guard reached else { throw DemoDashboardDataTestError.timedOut }
    }

    func finish(
        _ id: Int, bytes: Data, file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        try await finish(id, result: .success(bytes), file: file, line: line)
    }

    func finish(
        _ id: Int, result: Result<Data, Error>, file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        let task = try XCTUnwrap(model.activeReadTask, "Expected a model-owned task", file: file, line: line)
        let released = gate.finish(id, result: result)
        XCTAssertTrue(released, "Expected an unfinished physical read", file: file, line: line)
        guard released else { throw DemoDashboardDataTestError.missingRead }
        try await dashboardDataAwait(task, file: file, line: line)
    }

    func report(file: StaticString = #filePath, line: UInt = #line) throws -> DemoDashboardReport {
        guard case .report(let report) = model.snapshot.content else {
            XCTFail("Expected actual decoded report content", file: file, line: line)
            throw DemoDashboardDataTestError.missingRead
        }
        return report
    }
}

@MainActor
func dashboardDataJSON(
    day: [[String: Any]] = [], week: [[String: Any]] = [], all: [[String: Any]] = [], version: Int = 1
) throws -> Data {
    try JSONSerialization.data(
        withJSONObject: ["version": version, "day": day, "week": week, "all": all], options: [.sortedKeys])
}

/// Uses real observation-center tokens registered by the mounted public views.
/// Notifications synchronously reload this fixture, not the native host's frame
/// scheduler. No test manually forces a model success or skips decoding.
@MainActor
private final class DemoDashboardDataSubscriptions {
    private struct Entry {
        let generation: UUID
        let token: ObservationToken
    }

    private var entries: [ObjectIdentifier: Entry] = [:]
    private(set) var notifications: [ObjectIdentifier] = []
    private(set) var closed = false
    var reload: (@MainActor () -> Void)?

    var objectIDs: Set<ObjectIdentifier> { Set(entries.keys) }

    func observe(_ object: any ObservableObject) {
        guard !closed else { return }
        let id = ObjectIdentifier(object)
        guard entries[id] == nil else { return }
        let generation = UUID()
        let token = ObservableObjectCenter.shared.addObserver(for: object) { [weak self] in
            guard let self, !self.closed, self.entries[id]?.generation == generation else { return }
            self.notifications.append(id)
            self.reload?()
        }
        entries[id] = Entry(generation: generation, token: token)
    }

    func retain(_ objectIDs: Set<ObjectIdentifier>) {
        let removed = Set(entries.keys).subtracting(objectIDs)
        let tokens = removed.compactMap { entries.removeValue(forKey: $0)?.token }
        for token in tokens { token.cancel() }
    }

    func close() {
        guard !closed else { return }
        closed = true
        reload = nil
        let tokens = entries.values.map(\.token)
        entries.removeAll()
        for token in tokens { token.cancel() }
    }
}

@MainActor
private final class DemoDashboardDataFixtureState {
    var size: IntSize
    var closed = false

    init(size: IntSize) { self.size = size }
}

/// Public SwiftUI-shaped composition, real mounted State/ObservedObject,
/// retained keyboard/pointer inputs and renderer-neutral scene preparation.
@MainActor
final class DemoDashboardDataFixture {
    let dashboard: DemoDashboardModel
    let runtime: RetainedViewRuntime
    let host: ComponentHost
    private let coordinator: StateMountCoordinator
    private let subscriptions: DemoDashboardDataSubscriptions
    private let state: DemoDashboardDataFixtureState

    init(
        model: DemoDashboardDataModel, size: IntSize = IntSize(width: 640, height: 720),
        scheme: ColorScheme = .dark, scale: Double = 1, wholeRoot: Bool = false
    ) {
        let dashboard = DemoDashboardModel(dashboardData: model)
        self.dashboard = dashboard
        let state = DemoDashboardDataFixtureState(size: size)
        self.state = state
        let runtime = RetainedViewRuntime(root: ViewNode(), displayScale: scale)
        runtime.clock = { 1 }
        runtime.setRootSize(size)
        self.runtime = runtime
        let host = ComponentHost(runtime: runtime)
        self.host = host
        let subscriptions = DemoDashboardDataSubscriptions()
        self.subscriptions = subscriptions
        let coordinator = StateMountCoordinator(
            invalidate: { [weak host] in host?.reload() },
            observeObject: { [weak subscriptions] in subscriptions?.observe($0) },
            updateObservedObjects: { [weak host, weak subscriptions] committed, retained, _ in
                host?.observedObjects = committed
                subscriptions?.retain(retained)
            })
        self.coordinator = coordinator
        host.buildLifecycle = coordinator
        host.shouldUpdate = { [weak state] in state?.closed == false }
        subscriptions.reload = { [weak host] in host?.reload() }
        let context = ViewBuildContext(
            stateMountCoordinator: coordinator,
            canvasSizeProvider: { Size(width: Double(state.size.width), height: Double(state.size.height)) },
            invalidateHandler: { [weak host] in host?.reload() },
            environmentValuesProvider: {
                EnvironmentValues(colorScheme: scheme, displayScale: scale, pixelLength: 1 / scale)
            })
        host.setComponents {
            guard !state.closed else { return [] }
            if wholeRoot { return [makeViewComponent(DemoRootView(model: dashboard), context: context)] }
            let layout = DemoLayout(size: Size(width: Double(state.size.width), height: Double(state.size.height)))
            return [makeViewComponent(DemoChartCard(model: dashboard, layout: layout), context: context)]
        }
        render()
    }

    var nodes: [ViewNode] { Self.descendants(runtime.root) }
    var texts: [String] { nodes.compactMap(\.text) }
    var observedObjectIDs: Set<ObjectIdentifier> { subscriptions.objectIDs }
    var observedNotifications: [ObjectIdentifier] { subscriptions.notifications }

    func render() {
        _ = runtime.renderScene(at: 1)
        _ = runtime.renderScene(at: 1)
        XCTAssertNil(coordinator.latestInstallationError)
    }

    func close() {
        guard !state.closed else { return }
        state.closed = true
        subscriptions.close()
        coordinator.close()
    }

    func node(_ identifier: String) throws -> ViewNode {
        let matches = nodes.filter { $0.accessibilityIdentifier == identifier }
        XCTAssertEqual(matches.count, 1, "Expected one node for \(identifier)")
        return try XCTUnwrap(matches.first)
    }

    func hasNode(_ identifier: String) -> Bool { nodes.contains { $0.accessibilityIdentifier == identifier } }

    func texts(in identifier: String) throws -> [String] {
        Self.descendants(try node(identifier)).compactMap(\.text)
    }

    func enabledButtons(in identifier: String) throws -> [ViewNode] {
        Self.descendants(try node(identifier)).filter {
            $0.accessibilityTraits.contains(.isButton) && $0.isFocusable && $0.onActivate != nil
        }
    }

    func activate(_ identifier: String) throws {
        let controls = try enabledButtons(in: identifier)
        XCTAssertEqual(controls.count, 1, "Expected one enabled public Button in \(identifier)")
        try activateControl(XCTUnwrap(controls.first))
    }

    func activateLabel(_ label: String) throws {
        let matches = nodes.filter { $0.text == label }
        XCTAssertEqual(matches.count, 1, "Expected one label for the public range button")
        var cursor: ViewNode? = try XCTUnwrap(matches.first)
        while let node = cursor {
            if node.accessibilityTraits.contains(.isButton), node.isFocusable, node.onActivate != nil {
                try activateControl(node)
                return
            }
            cursor = node.parent
        }
        XCTFail("Missing public Button for \(label)")
        throw DemoDashboardDataTestError.missingControl
    }

    private func activateControl(_ control: ViewNode) throws {
        runtime.requestFocus(control)
        guard control.isFocused else {
            XCTFail("The public Button did not receive focus")
            throw DemoDashboardDataTestError.missingControl
        }
        runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.space.rawValue))
        render()
    }

    func bounds(of node: ViewNode) -> Rect {
        var frame = node.resolvedFrame
        var ancestor = node.parent
        while let parent = ancestor {
            frame.origin.x += parent.resolvedFrame.origin.x
            frame.origin.y += parent.resolvedFrame.origin.y
            if parent.scrollAxis == .vertical { frame.origin.y -= parent.scrollOffset }
            if parent.scrollAxis == .horizontal { frame.origin.x -= parent.scrollOffset }
            ancestor = parent.parent
        }
        return frame
    }

    static func descendants(_ root: ViewNode) -> [ViewNode] {
        var result: [ViewNode] = []
        var pending = [root]
        while let node = pending.popLast() {
            result.append(node)
            pending.append(contentsOf: node.children.reversed())
        }
        return result
    }
}
