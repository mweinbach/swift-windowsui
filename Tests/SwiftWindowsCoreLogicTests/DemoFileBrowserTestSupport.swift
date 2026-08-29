import Foundation
@preconcurrency import XCTest

@testable import SwiftWindowsDemo
@testable import WinSwiftUI

/// A reader that retains its physical slot after cancellation. Only an explicit
/// finish, or cleanup, releases the read continuation. No URL is opened here.
final class DemoFilePreviewGate: @unchecked Sendable {
    struct Start: Equatable, Sendable {
        let id: Int
        let source: DemoFilePreviewSource
        let wasCancelledAtEntry: Bool
    }

    enum Event: Equatable, Sendable {
        case started(Int)
        case registered(Int)
        case cancelled(Int)
        case returned(Int)
    }

    struct Snapshot: Sendable {
        let starts: [Start]
        let registrations: Set<Int>
        let cancellations: Set<Int>
        let returns: Set<Int>
        let active: Set<Int>
        let maximumConcurrent: Int
        let events: [Event]
    }

    private enum Milestone {
        case starts(Int)
        case registrations(Int)
        case returns(Int)
        case cancellation(Int)

        func isReached(in state: State) -> Bool {
            switch self {
            case .starts(let count): return state.starts.count >= count
            case .registrations(let count): return state.registrations.count >= count
            case .returns(let count): return state.returns.count >= count
            case .cancellation(let id): return state.cancellations.contains(id)
            }
        }

        var description: String {
            switch self {
            case .starts(let count): return "\(count) file-preview reader starts"
            case .registrations(let count): return "\(count) file-preview continuation registrations"
            case .returns(let count): return "\(count) file-preview reader returns"
            case .cancellation(let id): return "cancellation of file-preview reader \(id)"
            }
        }
    }

    private final class Waiter {
        let milestone: Milestone
        let expectation: XCTestExpectation
        // Read and written only while the enclosing gate's lock is held.
        var result: Bool?

        init(milestone: Milestone) {
            self.milestone = milestone
            expectation = XCTestExpectation(description: milestone.description)
        }
    }

    private struct State {
        var starts: [Start] = []
        var registrations: Set<Int> = []
        var cancellations: Set<Int> = []
        var returns: Set<Int> = []
        var active: Set<Int> = []
        var maximumConcurrent = 0
        var events: [Event] = []
        var reads: [Int: CheckedContinuation<Data, Error>] = [:]
        var registrationBarriers: [Int: CheckedContinuation<Void, Never>] = [:]
        var allowedRegistrations: Set<Int> = []
        var bufferedResults: [Int: Result<Data, Error>] = [:]
        var waiters: [Waiter] = []
        var cancellationHook: (@Sendable (Int) -> Void)?
        var isClosed = false
    }

    private let lock = NSLock()
    private let holdsRegistrations: Bool
    private var state = State()

    init(holdsRegistrations: Bool = false) {
        self.holdsRegistrations = holdsRegistrations
    }

    var service: DemoFilePreviewService {
        DemoFilePreviewService { [self] source in try await read(source) }
    }

    var snapshot: Snapshot {
        locked { state in
            Snapshot(
                starts: state.starts, registrations: state.registrations,
                cancellations: state.cancellations, returns: state.returns,
                active: state.active, maximumConcurrent: state.maximumConcurrent,
                events: state.events)
        }
    }

    func waitForStarts(_ count: Int) async -> Bool { await wait(for: .starts(count)) }
    func waitForRegistrations(_ count: Int) async -> Bool { await wait(for: .registrations(count)) }
    func waitForReturns(_ count: Int) async -> Bool { await wait(for: .returns(count)) }
    func waitForCancellation(of id: Int) async -> Bool { await wait(for: .cancellation(id)) }

    func setCancellationHook(_ hook: (@Sendable (Int) -> Void)?) {
        locked { $0.cancellationHook = hook }
    }

    func allowRegistration(_ id: Int) {
        let continuation = locked { state in
            state.allowedRegistrations.insert(id)
            return state.registrationBarriers.removeValue(forKey: id)
        }
        continuation?.resume()
    }

    @discardableResult
    func succeed(_ id: Int, text: String) -> Bool {
        finish(id, result: .success(Data(text.utf8)))
    }

    @discardableResult
    func finish(_ id: Int, result: Result<Data, Error>) -> Bool {
        let completion = locked { state -> (Bool, CheckedContinuation<Data, Error>?) in
            guard !state.isClosed, state.active.contains(id), state.bufferedResults[id] == nil else {
                return (false, nil)
            }
            if let continuation = state.reads.removeValue(forKey: id) {
                // Retain a marker until the reader returns so duplicate finish
                // calls cannot manufacture a second continuation result.
                state.bufferedResults[id] = result
                return (true, continuation)
            }
            state.bufferedResults[id] = result
            return (true, nil)
        }
        completion.1?.resume(with: result)
        return completion.0
    }

    /// Releases every registered waiter, including readers cancelled before
    /// their data continuation was registered. Future reads fail immediately.
    func close() {
        let cleanup = locked { state in
            state.isClosed = true
            state.cancellationHook = nil
            let reads = Array(state.reads.values)
            let barriers = Array(state.registrationBarriers.values)
            let waiters = state.waiters
            for waiter in waiters { waiter.result = false }
            state.reads.removeAll()
            state.registrationBarriers.removeAll()
            state.bufferedResults.removeAll()
            state.waiters.removeAll()
            return (reads, barriers, waiters)
        }
        for continuation in cleanup.0 { continuation.resume(throwing: CancellationError()) }
        for continuation in cleanup.1 { continuation.resume() }
        for waiter in cleanup.2 { waiter.expectation.fulfill() }
    }

    private func read(_ source: DemoFilePreviewSource) async throws -> Data {
        let id = try begin(source, wasCancelled: Task.isCancelled)
        defer { didReturn(id) }
        return try await withTaskCancellationHandler {
            if holdsRegistrations {
                await withCheckedContinuation { continuation in
                    registerBarrier(id, continuation: continuation)
                }
            }
            return try await withCheckedThrowingContinuation { continuation in
                registerRead(id, continuation: continuation)
            }
        } onCancel: {
            self.didCancel(id)
        }
    }

    private func begin(_ source: DemoFilePreviewSource, wasCancelled: Bool) throws -> Int {
        let id = try locked { state in
            guard !state.isClosed else { throw CancellationError() }
            let id = state.starts.count
            state.starts.append(Start(id: id, source: source, wasCancelledAtEntry: wasCancelled))
            state.active.insert(id)
            state.maximumConcurrent = max(state.maximumConcurrent, state.active.count)
            state.events.append(.started(id))
            return id
        }
        releaseReachedWaiters()
        return id
    }

    private func registerBarrier(_ id: Int, continuation: CheckedContinuation<Void, Never>) {
        let shouldResume = locked { state in
            if state.isClosed || state.allowedRegistrations.contains(id) { return true }
            state.registrationBarriers[id] = continuation
            return false
        }
        if shouldResume { continuation.resume() }
    }

    private func registerRead(_ id: Int, continuation: CheckedContinuation<Data, Error>) {
        let result = locked { state -> Result<Data, Error>? in
            state.registrations.insert(id)
            state.events.append(.registered(id))
            if state.isClosed { return .failure(CancellationError()) }
            if let result = state.bufferedResults[id] { return result }
            state.reads[id] = continuation
            return nil
        }
        if let result { continuation.resume(with: result) }
        releaseReachedWaiters()
    }

    private func didCancel(_ id: Int) {
        let hook = locked { state in
            if state.cancellations.insert(id).inserted { state.events.append(.cancelled(id)) }
            return state.cancellationHook
        }
        releaseReachedWaiters()
        // Never invoke application reentry while the gate lock is held.
        hook?(id)
    }

    private func didReturn(_ id: Int) {
        locked { state in
            state.active.remove(id)
            state.returns.insert(id)
            state.bufferedResults.removeValue(forKey: id)
            state.events.append(.returned(id))
        }
        releaseReachedWaiters()
    }

    private func wait(for milestone: Milestone) async -> Bool {
        let waiter = Waiter(milestone: milestone)
        let immediate = locked { state -> Bool? in
            if milestone.isReached(in: state) { return true }
            if state.isClosed { return false }
            state.waiters.append(waiter)
            return nil
        }
        if let immediate { return immediate }
        let result = await XCTWaiter.fulfillment(of: [waiter.expectation], timeout: 5)
        guard result == .completed else {
            XCTFail("Timed out waiting for \(milestone.description); releasing injected readers for cleanup")
            close()
            return false
        }
        return locked { _ in waiter.result == true }
    }

    private func releaseReachedWaiters() {
        let reached = locked { state in
            let pending = state.waiters
            state.waiters.removeAll()
            var reached: [Waiter] = []
            for waiter in pending {
                if waiter.milestone.isReached(in: state) {
                    waiter.result = true
                    reached.append(waiter)
                } else {
                    state.waiters.append(waiter)
                }
            }
            return reached
        }
        for waiter in reached { waiter.expectation.fulfill() }
    }

    private func locked<Value>(_ operation: (inout State) throws -> Value) rethrows -> Value {
        lock.lock()
        defer { lock.unlock() }
        return try operation(&state)
    }
}

/// Model notifications are completion events because its authoritative snapshot
/// is committed before objectWillChange. This helper never polls phase labels.
@MainActor
final class DemoFileBrowserObservation {
    @MainActor
    private final class Waiter {
        let predicate: @MainActor (DemoFileBrowserModel) -> Bool
        let expectation = XCTestExpectation(description: "file-browser model notification")
        var result: Bool?

        init(predicate: @escaping @MainActor (DemoFileBrowserModel) -> Bool) {
            self.predicate = predicate
        }
    }

    private weak var model: DemoFileBrowserModel?
    private var subscription: AnyCancellable?
    private var waiters: [Waiter] = []
    private var isClosed = false
    private(set) var snapshots: [DemoFileBrowserSnapshot] = []

    init(_ model: DemoFileBrowserModel) {
        self.model = model
        snapshots = [model.snapshot]
        subscription = model.objectWillChange.sink { [weak self] _ in self?.recordChange() }
    }

    func waitFor(_ predicate: @escaping @MainActor (DemoFileBrowserModel) -> Bool) async -> Bool {
        guard let satisfied = evaluate(predicate) else { return false }
        if satisfied { return true }
        let waiter = Waiter(predicate: predicate)
        waiters.append(waiter)
        let result = await XCTWaiter.fulfillment(of: [waiter.expectation], timeout: 5)
        guard result == .completed else {
            XCTFail("Timed out waiting for a file-browser model notification; closing its observation")
            close()
            return false
        }
        return waiter.result == true
    }

    func close() {
        isClosed = true
        subscription?.cancel()
        subscription = nil
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { complete(waiter, result: false) }
    }

    private func recordChange() {
        guard !isClosed, let model else { return }
        snapshots.append(model.snapshot)
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            guard !isClosed else {
                complete(waiter, result: false)
                continue
            }
            let satisfied = waiter.predicate(model)
            if isClosed {
                complete(waiter, result: false)
            } else if satisfied {
                complete(waiter, result: true)
            } else {
                waiters.append(waiter)
            }
        }
    }

    private func evaluate(_ predicate: @MainActor (DemoFileBrowserModel) -> Bool) -> Bool? {
        guard !isClosed, let model else { return nil }
        let satisfied = predicate(model)
        return isClosed ? nil : satisfied
    }

    private func complete(_ waiter: Waiter, result: Bool) {
        guard waiter.result == nil else { return }
        waiter.result = result
        waiter.expectation.fulfill()
    }
}
