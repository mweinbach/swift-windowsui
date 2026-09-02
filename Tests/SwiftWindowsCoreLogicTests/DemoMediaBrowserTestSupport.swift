import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsDemo
@testable import SwiftWindowsUI
@testable import WinSwiftUI

enum DemoMediaBrowserWaitError: Error { case timedOut, missingRead }

/// Owns only test read continuations. Cancellation records intent; it does not
/// release a physical read. Returned bytes still use the actual bounded decoder.
final class DemoMediaBrowserGate: @unchecked Sendable {
    struct Start: Equatable, Sendable {
        let id: Int
        let source: DemoMediaImageSource
        let wasCancelledAtEntry: Bool
    }

    struct Snapshot: Sendable {
        let starts: [Start]
        let cancellations: Set<Int>
        let active: Set<Int>
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
        let expectation = XCTestExpectation(description: "media browser reader event")
        var result: Bool?

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
                starts: $0.starts, cancellations: $0.cancellations, active: $0.active,
                maximumConcurrent: $0.maximumConcurrent)
        }
    }

    func read(_ source: DemoMediaImageSource) async throws -> Data {
        let id = try locked { state in
            guard !state.closed else { throw CancellationError() }
            let id = state.starts.count
            state.starts.append(Start(id: id, source: source, wasCancelledAtEntry: Task.isCancelled))
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
            let waiters = state.waiters
            state.continuations.removeAll()
            state.waiters.removeAll()
            for waiter in waiters { waiter.result = false }
            return (reads, waiters)
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
        return locked { _ in waiter.result == true }
    }

    private func releaseWaiters() {
        let ready = locked { state in
            let pending = state.waiters
            state.waiters.removeAll()
            var ready: [Waiter] = []
            for waiter in pending {
                if waiter.milestone.reached(state) {
                    waiter.result = true
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

/// The model commits its snapshot before notification, so a waiter observes
/// actual transitions without polling, arbitrary yields, or a live delay.
@MainActor
final class DemoMediaBrowserObserver {
    private struct Waiter {
        let test: @MainActor (DemoMediaBrowserModel) -> Bool
        let expectation: XCTestExpectation
    }

    private weak var model: DemoMediaBrowserModel?
    private var subscription: AnyCancellable?
    private var waiters: [Waiter] = []
    private var closed = false

    init(_ model: DemoMediaBrowserModel) {
        self.model = model
        subscription = model.objectWillChange.sink { [weak self] _ in self?.changed() }
    }

    func waitFor(_ test: @escaping @MainActor (DemoMediaBrowserModel) -> Bool) async -> Bool {
        guard !closed, let model else { return false }
        if test(model) { return true }
        let expectation = XCTestExpectation(description: "media browser model transition")
        waiters.append(Waiter(test: test, expectation: expectation))
        let result = await XCTWaiter.fulfillment(of: [expectation], timeout: 5)
        return result == .completed && !closed && test(model)
    }

    func close() {
        closed = true
        subscription?.cancel()
        subscription = nil
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.expectation.fulfill() }
    }

    private func changed() {
        guard !closed, let model else { return }
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            if closed || waiter.test(model) { waiter.expectation.fulfill() } else { waiters.append(waiter) }
        }
    }
}

@MainActor
final class DemoMediaBrowserHarness {
    let gate: DemoMediaBrowserGate
    let service: DemoMediaImageService
    let model: DemoMediaBrowserModel
    let observation: DemoMediaBrowserObserver
    let mountID = UUID()
    private(set) var visibilityTask: Task<Void, Never>?

    init(includesSamples: Bool = true) {
        let gate = DemoMediaBrowserGate()
        self.gate = gate
        let service = DemoMediaImageService { try await gate.read($0) }
        self.service = service
        let model = DemoMediaBrowserModel(service: service, includesSamples: includesSamples)
        self.model = model
        observation = DemoMediaBrowserObserver(model)
    }

    func mount(preview: Bool = false, thumbnails: [String] = []) {
        model.appear(mountID: mountID)
        model.setBrowserVisible(true, mountID: mountID)
        model.setPreviewVisible(preview, mountID: mountID)
        for id in thumbnails {
            model.setThumbnailVisible(id: id, pageScope: model.pageScope, visible: true, mountID: mountID)
        }
        let model = model
        let mountID = mountID
        visibilityTask = Task { @MainActor in await model.runWhileVisible(mountID: mountID) }
    }

    func close() {
        model.close()
        visibilityTask?.cancel()
        observation.close()
        gate.close()
    }

    func starts(_ count: Int, file: StaticString = #filePath, line: UInt = #line) async throws {
        let reached = await gate.waitForStarts(count)
        XCTAssertTrue(reached, "Expected \(count) admitted reader calls", file: file, line: line)
        guard reached else { throw DemoMediaBrowserWaitError.missingRead }
    }

    func waitFor(
        _ predicate: @escaping @MainActor (DemoMediaBrowserModel) -> Bool,
        file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        let reached = await observation.waitFor(predicate)
        XCTAssertTrue(reached, "Expected an authoritative model transition", file: file, line: line)
        guard reached else {
            close()
            throw DemoMediaBrowserWaitError.timedOut
        }
    }

    func finishCurrent(
        _ ids: [Int], data: Data, file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        let tasks = model.activeReadTasks
        for id in ids { XCTAssertTrue(gate.finish(id, result: .success(data)), file: file, line: line) }
        try await awaitTasks(tasks, file: file, line: line)
    }

    func awaitTasks(
        _ tasks: [Task<Void, Never>], file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        let expectation = XCTestExpectation(description: "model-owned image tasks returned")
        let waiting = Task { @MainActor in
            for task in tasks { await task.value }
            expectation.fulfill()
        }
        defer { waiting.cancel() }
        let result = await XCTWaiter.fulfillment(of: [expectation], timeout: 5)
        guard result == .completed else {
            close()
            XCTFail("Image tasks did not return; releasing test readers", file: file, line: line)
            throw DemoMediaBrowserWaitError.timedOut
        }
    }
}

@MainActor
private final class DemoMediaBrowserFixtureState {
    var visible = true
    var size: IntSize
    var now: Double = 1

    init(size: IntSize) { self.size = size }
}

/// Actual public view composition and retained inputs, with no native window,
/// OS dialog, platform file drop, screenshot, or success-state image injection.
@MainActor
final class DemoMediaBrowserFixture {
    let runtime: RetainedViewRuntime
    let host: ComponentHost
    private let coordinator: StateMountCoordinator
    private let state: DemoMediaBrowserFixtureState

    init(
        model: DemoMediaBrowserModel, size: IntSize = IntSize(width: 900, height: 680),
        scheme: ColorScheme = .dark, scale: Double = 1, outerScroll: Bool = false,
        transitionRemoval: Bool = false,
        gallery: (DemoDashboardModel, DemoWindowState)? = nil
    ) {
        let state = DemoMediaBrowserFixtureState(size: size)
        self.state = state
        let runtime = RetainedViewRuntime(root: ViewNode(), displayScale: scale)
        runtime.clock = { state.now }
        runtime.setRootSize(size)
        self.runtime = runtime
        let host = ComponentHost(runtime: runtime)
        self.host = host
        let coordinator = StateMountCoordinator(
            invalidate: { [weak host] in host?.reload() }, observeObject: { _ in },
            updateObservedObjects: { _, _, _ in })
        self.coordinator = coordinator
        host.buildLifecycle = coordinator
        let context = ViewBuildContext(
            stateMountCoordinator: coordinator,
            canvasSizeProvider: { Size(width: Double(state.size.width), height: Double(state.size.height)) },
            invalidateHandler: { [weak host] in host?.reload() },
            environmentValuesProvider: {
                EnvironmentValues(colorScheme: scheme, displayScale: scale, pixelLength: 1 / scale)
            })
        // Deliberately reuse one authored source value across rebuild/remount.
        // Its StateObject factory must create a fresh logical mount on reentry.
        let template = DemoMediaBrowserTemplate(model: model)
        host.setComponents {
            guard state.visible else { return [makeViewComponent(Text("Hidden media browser"), context: context)] }
            if let (dashboard, window) = gallery {
                return [
                    makeViewComponent(DemoGalleryScreen(model: dashboard).environmentObject(window), context: context)
                ]
            }
            if outerScroll {
                return [
                    makeViewComponent(
                        ScrollView {
                            VStack(spacing: 0) {
                                Text("Before media").frame(height: 800)
                                template.frame(height: 680)
                                Text("After media").frame(height: 800)
                            }
                        }
                        .accessibilityIdentifier("media.test.outer.scroll"), context: context)
                ]
            }
            if transitionRemoval {
                return [makeViewComponent(template.transition(.opacity), context: context)]
            }
            return [makeViewComponent(template, context: context)]
        }
        render()
    }

    var nodes: [ViewNode] { Self.descendants(runtime.root) }
    var texts: [String] { nodes.compactMap(\.text) }
    var bitmaps: [BitmapSurface] { nodes.compactMap(\.bitmapSurface) }
    var selectableRows: [ViewNode] { nodes.filter { $0.accessibilityTraits.contains(.isSelectable) } }

    func rebuild() {
        host.reload()
        render()
    }

    func render() {
        _ = runtime.renderScene(at: state.now)
        _ = runtime.renderScene(at: state.now)
        XCTAssertNil(coordinator.latestInstallationError)
    }

    func close() { coordinator.close() }

    func setVisible(_ visible: Bool) {
        state.visible = visible
        rebuild()
    }

    func resize(_ size: IntSize) {
        state.size = size
        runtime.setRootSize(size)
        rebuild()
    }

    func advance(to timestamp: Double) {
        state.now = timestamp
        _ = runtime.tickAnimations(at: timestamp)
        render()
    }

    func node(_ identifier: String) throws -> ViewNode {
        let matches = nodes.filter { $0.accessibilityIdentifier == identifier }
        XCTAssertEqual(matches.count, 1, "Expected one node for \(identifier)")
        return try XCTUnwrap(matches.first)
    }

    func row(_ id: String) throws -> ViewNode {
        var current: ViewNode? = try node("media.browser.record.\(id)")
        while let node = current {
            if node.accessibilityTraits.contains(.isSelectable) { return node }
            current = node.parent
        }
        throw DemoMediaBrowserWaitError.missingRead
    }

    func activate(_ identifier: String) throws {
        let identified = try node(identifier)
        let candidates = Self.descendants(identified).filter {
            $0.accessibilityTraits.contains(.isButton) && $0.isFocusable && $0.onActivate != nil
        }
        XCTAssertEqual(candidates.count, 1, "Expected one enabled public Button owner inside \(identifier)")
        let control = try XCTUnwrap(candidates.first, "Missing public Button owner for \(identifier)")
        runtime.requestFocus(control)
        guard control.isFocused else {
            XCTFail("The identified public Button did not receive focus: \(identifier)")
            throw DemoMediaBrowserWaitError.missingRead
        }
        runtime.keyDown(KeyboardEvent(keyCode: KeyboardKey.space.rawValue))
    }

    func scroll(_ identifier: String = "media.browser.viewport", to offset: Double) throws {
        let root = try node(identifier)
        let scroll = try XCTUnwrap(Self.descendants(root).first { $0.scrollAxis == .vertical })
        scroll.scrollOffset = offset
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
