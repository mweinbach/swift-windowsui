import Foundation
import SwiftWindowsCore
import Synchronization
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform

private final class NativeMailboxTestValues<Value: Sendable>: Sendable {
    private let storage = Mutex<[Value]>([])

    func append(_ value: Value) { storage.withLock { $0.append(value) } }
    var all: [Value] { storage.withLock { $0 } }
}

/// Each callback is removed before invocation. Reentrant admission can post
/// the next wake without taking this test recorder's lock recursively.
private final class NativeMailboxTestPoster: Sendable {
    typealias Action = @Sendable () -> Result<Void, NativeWindowOwnerFailure>

    private struct State: Sendable {
        var handles: [UInt] = []
        var actions: [Int: Action] = [:]
    }

    private let storage = Mutex(State())

    func onCall(_ number: Int, perform action: @escaping Action) {
        let previous = storage.withLock { $0.actions.updateValue(action, forKey: number) }
        withExtendedLifetime(previous) {}
    }

    func post(_ handle: UInt) -> Result<Void, NativeWindowOwnerFailure> {
        let action = storage.withLock { stored in
            stored.handles.append(handle)
            return stored.actions.removeValue(forKey: stored.handles.count)
        }
        return action?() ?? .success(())
    }

    var handles: [UInt] { storage.withLock { $0.handles } }
}

private struct NativeMailboxTestCommand: NativeWindowOwnerCommand {
    let windowKey: NativeWindowKey
    let requestID: NativeWindowRequestID
    let reply: NativeWindowReply<Int>
    var commandReply: NativeWindowCommandReply { reply.commandReply }

    init(
        windowKey: NativeWindowKey = NativeWindowKey(), requestID: NativeWindowRequestID = NativeWindowRequestID(),
        reply: NativeWindowReply<Int>
    ) {
        self.windowKey = windowKey
        self.requestID = requestID
        self.reply = reply
    }

    func execute(in context: any NativeWindowOwnerContext) throws {
        reply.complete(.success(17))
    }

    func reject(_ failure: NativeWindowOwnerFailure) { reply.complete(.failure(failure)) }
}

private final class NativeMailboxTestReleaseProbe: Sendable {
    private let release: @Sendable () -> Void

    init(_ release: @escaping @Sendable () -> Void) { self.release = release }
    deinit { release() }
}

/// Getters and the legacy reject override are deliberately observable. Queue
/// rejection must use its cached Core capability, without invoking either
/// arbitrary getter or the override while it owns the mailbox lock.
private struct NativeMailboxTestInspectedCommand: NativeWindowOwnerCommand {
    let windowKey = NativeWindowKey()
    private let id = NativeWindowRequestID()
    let reply: NativeWindowReply<Int>
    let probe: NativeMailboxTestReleaseProbe?
    let read: @Sendable (String) -> Void
    let rejected: @Sendable (NativeWindowOwnerFailure) -> Void

    init(
        reply: NativeWindowReply<Int>, probe: NativeMailboxTestReleaseProbe? = nil,
        read: @escaping @Sendable (String) -> Void = { _ in },
        rejected: @escaping @Sendable (NativeWindowOwnerFailure) -> Void = { _ in }
    ) {
        self.reply = reply
        self.probe = probe
        self.read = read
        self.rejected = rejected
    }

    var requestID: NativeWindowRequestID {
        read("requestID")
        return id
    }

    var commandReply: NativeWindowCommandReply {
        read("commandReply")
        return reply.commandReply
    }

    func execute(in context: any NativeWindowOwnerContext) throws {
        _ = withExtendedLifetime(probe) { reply.complete(.success(17)) }
    }

    func reject(_ failure: NativeWindowOwnerFailure) {
        rejected(failure)
        _ = withExtendedLifetime(probe) { reply.complete(.failure(failure)) }
    }
}

private enum NativeMailboxTestWork: Equatable, Sendable {
    case create(NativeWindowKey)
    case command(NativeWindowRequestID)
    case close(NativeWindowKey)
    case stop

    init(_ work: Win32NativePumpWork) {
        switch work {
        case .create(let creation): self = .create(creation.key)
        case .command(let command): self = .command(command.requestID)
        case .close(let request): self = .close(request.key)
        case .stop: self = .stop
        }
    }
}

private enum NativeMailboxTestControlResult: Equatable, Sendable {
    case completed
    case activated(Bool)
    case failure(NativeWindowOwnerFailure)

    init(_ result: Result<Win32NativeWindowOperationResult, NativeWindowOwnerFailure>) {
        switch result {
        case .success(.completed): self = .completed
        case .success(.activated(let value)): self = .activated(value)
        case .failure(let failure): self = .failure(failure)
        }
    }
}

/// Controlled mailbox fixtures only: the poster never calls Win32, and no
/// fixture launches a pump, creates an HWND, or executes a native command.
@MainActor
final class Win32NativePumpMailboxTests: XCTestCase {
    private let postFailure = NativeWindowOwnerFailure.postFailed(code: 1816)

    private func runningMailbox(
        commands: Int = 2, controlCommands: Int = 2, startWaiters: Int = 2, stopWaiters: Int = 2,
        poster: NativeMailboxTestPoster = NativeMailboxTestPoster()
    ) -> Win32NativePumpMailbox {
        let mailbox = Win32NativePumpMailbox(
            limits: .init(
                commands: commands, controlCommands: controlCommands, startWaiters: startWaiters,
                stopWaiters: stopWaiters),
            post: { poster.post($0) })
        XCTAssertTrue(mailbox.requestStart(NativeWindowReply { _ in }))
        mailbox.didStart(controlHandle: 42)
        return mailbox
    }

    private func command(
        results: NativeMailboxTestValues<Result<Int, NativeWindowOwnerFailure>> = NativeMailboxTestValues()
    ) -> NativeMailboxTestCommand {
        NativeMailboxTestCommand(reply: NativeWindowReply { results.append($0) })
    }

    private func control(
        key: NativeWindowKey, operation: Win32NativeWindowOperation,
        results: NativeMailboxTestValues<NativeMailboxTestControlResult> = NativeMailboxTestValues()
    ) -> Win32NativeWindowOperationCommand {
        Win32NativeWindowOperationCommand(
            windowKey: key, operation: operation,
            reply: NativeWindowReply { results.append(NativeMailboxTestControlResult($0)) })
    }

    private func creation(
        key: NativeWindowKey = NativeWindowKey(),
        results: NativeMailboxTestValues<Result<NativeWindowSurface, NativeWindowOwnerFailure>> =
            NativeMailboxTestValues()
    ) -> Win32NativeWindowCreation {
        Win32NativeWindowCreation(
            key: key, title: "Mailbox fixture", logicalClientSize: IntSize(width: 20, height: 20),
            titleBarVisibility: .automatic, configuration: .default,
            ingress: Win32NativeEventIngress { _ in }, snapshotSource: Win32NativeSnapshotSource(),
            caretQuery: Win32NativeCaretQuery { _ in .success(nil) },
            reply: NativeWindowReply { results.append($0) })
    }

    private func close(
        key: NativeWindowKey,
        results: NativeMailboxTestValues<Result<Win32NativeCloseDestruction, NativeWindowOwnerFailure>> =
            NativeMailboxTestValues()
    ) -> Win32NativeDestructionRequest {
        Win32NativeDestructionRequest(key: key, reply: NativeWindowReply { results.append($0) })
    }

    private func next(_ mailbox: Win32NativePumpMailbox) -> NativeMailboxTestWork? {
        mailbox.takeNext().map(NativeMailboxTestWork.init)
    }

    func testProductionLimitsBoundOrdinaryWorkAt128() async throws {
        let poster = NativeMailboxTestPoster()
        let mailbox = Win32NativePumpMailbox(post: { poster.post($0) })
        XCTAssertTrue(mailbox.requestStart(NativeWindowReply { _ in }))
        mailbox.didStart(controlHandle: 42)
        for _ in 0..<128 { XCTAssertEqual(mailbox.submit(.command(command())), .accepted) }
        let results = NativeMailboxTestValues<Result<Int, NativeWindowOwnerFailure>>()
        XCTAssertEqual(
            mailbox.submit(.command(command(results: results))),
            .rejected(.capacityExceeded(resource: "nativeCommandQueue", limit: 128)))
        XCTAssertEqual(results.all, [.failure(.capacityExceeded(resource: "nativeCommandQueue", limit: 128))])
        XCTAssertEqual(mailbox.snapshot.queuedCommands, 128)
        XCTAssertEqual(mailbox.snapshot.storageCapacity, 129)
        XCTAssertEqual(poster.handles, [42])
    }

    func testCreationAndCommandsShareTheSameOrdinaryLimit() async throws {
        let mailbox = runningMailbox()
        let first = creation()
        let second = command()
        XCTAssertEqual(mailbox.submit(.create(first)), .accepted)
        XCTAssertEqual(mailbox.submit(.command(second)), .accepted)
        let rejected = NativeMailboxTestValues<Result<NativeWindowSurface, NativeWindowOwnerFailure>>()
        XCTAssertEqual(
            mailbox.submit(.create(creation(results: rejected))),
            .rejected(.capacityExceeded(resource: "nativeCommandQueue", limit: 2)))
        XCTAssertEqual(rejected.all, [.failure(.capacityExceeded(resource: "nativeCommandQueue", limit: 2))])
        XCTAssertEqual(next(mailbox), .create(first.key))
        XCTAssertEqual(next(mailbox), .command(second.requestID))
        XCTAssertNil(next(mailbox))
        XCTAssertEqual(mailbox.snapshot.queuedCommands, 0)
    }

    func testRingWrapAndDrainReuseDoNotGrowTheBackingStorage() async throws {
        let mailbox = runningMailbox(commands: 3)
        var expected: [NativeWindowRequestID] = []
        for _ in 0..<3 {
            let work = command()
            expected.append(work.requestID)
            XCTAssertEqual(mailbox.submit(.command(work)), .accepted)
        }
        for index in 0..<120 {
            let first = expected[index]
            XCTAssertEqual(next(mailbox), .command(first))
            let work = command()
            expected.append(work.requestID)
            XCTAssertEqual(mailbox.submit(.command(work)), .accepted)
            XCTAssertEqual(mailbox.snapshot.queuedCommands, 3)
            XCTAssertEqual(mailbox.snapshot.storageCapacity, 4)
        }
        for id in expected.suffix(3) { XCTAssertEqual(next(mailbox), .command(id)) }
        XCTAssertNil(next(mailbox))
        XCTAssertFalse(mailbox.hasQueuedWork)
        XCTAssertEqual(mailbox.snapshot.storageCapacity, 4)
    }

    func testFullOrdinaryQueueStillAdmitsOwnedClosesAndOneStopInFIFO() async throws {
        let mailbox = runningMailbox(commands: 3)
        let firstKey = NativeWindowKey()
        let secondKey = NativeWindowKey()
        XCTAssertTrue(mailbox.registerOwnedWindow(firstKey))
        XCTAssertTrue(mailbox.registerOwnedWindow(secondKey))
        let first = command()
        let second = creation()
        let third = command()
        XCTAssertEqual(mailbox.submit(.command(first)), .accepted)
        XCTAssertEqual(mailbox.submit(.close(close(key: firstKey))), .accepted)
        XCTAssertEqual(mailbox.submit(.create(second)), .accepted)
        XCTAssertEqual(mailbox.submit(.command(third)), .accepted)
        XCTAssertEqual(mailbox.submit(.close(close(key: secondKey))), .accepted)
        mailbox.requestStop(NativeWindowReply { _ in })
        mailbox.requestStop(NativeWindowReply { _ in })
        XCTAssertEqual(mailbox.snapshot.queuedWork, 6)
        XCTAssertEqual(mailbox.snapshot.storageCapacity, 14)
        XCTAssertEqual(mailbox.snapshot.stopWaiters, 2)
        XCTAssertEqual(next(mailbox), .command(first.requestID))
        XCTAssertEqual(next(mailbox), .close(firstKey))
        XCTAssertEqual(next(mailbox), .create(second.key))
        XCTAssertEqual(next(mailbox), .command(third.requestID))
        XCTAssertEqual(next(mailbox), .close(secondKey))
        XCTAssertEqual(next(mailbox), .stop)
        XCTAssertNil(next(mailbox))
    }

    func testUnknownLifetimesCannotAllocateReservedCloseSlots() async throws {
        let mailbox = runningMailbox(commands: 0)
        let results = NativeMailboxTestValues<Result<Win32NativeCloseDestruction, NativeWindowOwnerFailure>>()
        for _ in 0..<64 {
            XCTAssertEqual(
                mailbox.submit(.close(close(key: NativeWindowKey(), results: results))), .rejected(.staleWindow))
        }
        XCTAssertEqual(results.all, Array(repeating: .failure(.staleWindow), count: 64))
        XCTAssertEqual(mailbox.snapshot.ownedWindows, 0)
        XCTAssertEqual(mailbox.snapshot.reservedCloses, 0)
        XCTAssertEqual(mailbox.snapshot.queuedWork, 0)
        XCTAssertEqual(mailbox.snapshot.storageCapacity, 1)
    }

    func testQueuedCreationDoesNotYetOwnAReservedCloseSlot() async throws {
        let mailbox = runningMailbox()
        let pending = creation()
        XCTAssertEqual(mailbox.submit(.create(pending)), .accepted)
        XCTAssertEqual(mailbox.submit(.close(close(key: pending.key))), .rejected(.staleWindow))
        XCTAssertEqual(mailbox.snapshot.ownedWindows, 0)
        XCTAssertEqual(mailbox.snapshot.storageCapacity, 3)
        XCTAssertEqual(next(mailbox), .create(pending.key))
        XCTAssertTrue(mailbox.registerOwnedWindow(pending.key))
        XCTAssertEqual(mailbox.submit(.close(close(key: pending.key))), .accepted)
    }

    func testCloseReservationSurvivesDequeueUntilTerminalRetirement() async throws {
        let mailbox = runningMailbox(commands: 0)
        let key = NativeWindowKey()
        XCTAssertTrue(mailbox.registerOwnedWindow(key))
        let firstResults = NativeMailboxTestValues<Result<Win32NativeCloseDestruction, NativeWindowOwnerFailure>>()
        let first = close(key: key, results: firstResults)
        XCTAssertEqual(mailbox.submit(.close(first)), .accepted)
        let duplicateResults = NativeMailboxTestValues<Result<Win32NativeCloseDestruction, NativeWindowOwnerFailure>>()
        XCTAssertEqual(mailbox.submit(.close(close(key: key, results: duplicateResults))), .rejected(.closing))
        XCTAssertEqual(next(mailbox), .close(key))
        XCTAssertTrue(mailbox.registerClose(first))
        XCTAssertEqual(mailbox.submit(.close(close(key: key, results: duplicateResults))), .rejected(.closing))
        XCTAssertTrue(firstResults.all.isEmpty)
        XCTAssertEqual(duplicateResults.all, [.failure(.closing), .failure(.closing)])
        XCTAssertEqual(mailbox.snapshot.reservedCloses, 1)
        XCTAssertTrue(first.complete(.failure(.closed), beforeCompletion: { mailbox.retireClose(first) }))
        XCTAssertEqual(mailbox.snapshot.reservedCloses, 0)
        XCTAssertEqual(mailbox.submit(.close(close(key: key))), .accepted)
        mailbox.retireClose(first)
        XCTAssertEqual(mailbox.snapshot.reservedCloses, 1, "An old retirement cannot clear a newer reservation")
    }

    func testResubmittingTheSameCloseObjectDoesNotCancelItsOriginalAdmission() async throws {
        let mailbox = runningMailbox()
        let key = NativeWindowKey()
        XCTAssertTrue(mailbox.registerOwnedWindow(key))
        let results = NativeMailboxTestValues<Result<Win32NativeCloseDestruction, NativeWindowOwnerFailure>>()
        let request = close(key: key, results: results)
        XCTAssertEqual(mailbox.submit(.close(request)), .accepted)
        XCTAssertEqual(mailbox.submit(.close(request)), .rejected(.closing))
        XCTAssertTrue(results.all.isEmpty)
        XCTAssertFalse(request.isTerminal)
        XCTAssertEqual(mailbox.snapshot.queuedWork, 1)
        XCTAssertEqual(mailbox.snapshot.reservedCloses, 1)
    }

    func testRegisterCloseOnlyVerifiesAnExistingAdmission() async throws {
        let mailbox = runningMailbox()
        let key = NativeWindowKey()
        let request = close(key: key)
        XCTAssertFalse(mailbox.registerClose(request))
        XCTAssertTrue(mailbox.registerOwnedWindow(key))
        XCTAssertFalse(mailbox.registerClose(request))
        XCTAssertEqual(mailbox.snapshot.reservedCloses, 0)
        XCTAssertEqual(mailbox.submit(.close(request)), .accepted)
        XCTAssertTrue(mailbox.registerClose(request))
        XCTAssertFalse(mailbox.registerClose(close(key: key)))
        XCTAssertEqual(mailbox.snapshot.reservedCloses, 1)
    }

    func testRetiringOwnedWindowRejectsQueuedCloseBeforeCallbackAndShrinksSlots() async throws {
        let mailbox = runningMailbox()
        let key = NativeWindowKey()
        XCTAssertTrue(mailbox.registerOwnedWindow(key))
        let snapshots = NativeMailboxTestValues<Win32NativePumpMailbox.Snapshot>()
        let reentrant = NativeMailboxTestValues<NativeWindowSubmission>()
        let results = NativeMailboxTestValues<Result<Win32NativeCloseDestruction, NativeWindowOwnerFailure>>()
        let request = Win32NativeDestructionRequest(
            key: key,
            reply: NativeWindowReply { result in
                results.append(result)
                snapshots.append(mailbox.snapshot)
                reentrant.append(
                    mailbox.submit(.close(Win32NativeDestructionRequest(key: key, reply: NativeWindowReply { _ in }))))
            })
        let first = command()
        let last = command()
        XCTAssertEqual(mailbox.submit(.command(first)), .accepted)
        XCTAssertEqual(mailbox.submit(.close(request)), .accepted)
        XCTAssertEqual(mailbox.submit(.command(last)), .accepted)
        mailbox.retireOwnedWindow(key)
        XCTAssertEqual(results.all, [.failure(.staleWindow)])
        XCTAssertEqual(reentrant.all, [.rejected(.staleWindow)])
        XCTAssertEqual(snapshots.all.first?.reservedCloses, 0)
        XCTAssertEqual(snapshots.all.first?.ownedWindows, 0)
        XCTAssertEqual(snapshots.all.first?.storageCapacity, 3)
        XCTAssertEqual(next(mailbox), .command(first.requestID))
        XCTAssertEqual(next(mailbox), .command(last.requestID))
        XCTAssertNil(next(mailbox))
    }

    func testOwnedLifetimeChurnDoesNotKeepHistoricalCloseCapacity() async throws {
        let mailbox = runningMailbox(commands: 1)
        let pending = command()
        XCTAssertEqual(mailbox.submit(.command(pending)), .accepted)
        for _ in 0..<64 {
            let key = NativeWindowKey()
            XCTAssertTrue(mailbox.registerOwnedWindow(key))
            XCTAssertFalse(mailbox.registerOwnedWindow(key))
            XCTAssertEqual(mailbox.snapshot.storageCapacity, 7)
            mailbox.retireOwnedWindow(key)
            mailbox.retireOwnedWindow(key)
            XCTAssertEqual(mailbox.snapshot.storageCapacity, 2)
        }
        XCTAssertEqual(next(mailbox), .command(pending.requestID))
        XCTAssertNil(next(mailbox))
    }

    func testStartWaitersAreBoundedAndClearedBeforeStartCallbacks() async throws {
        let poster = NativeMailboxTestPoster()
        let mailbox = Win32NativePumpMailbox(limits: .init(startWaiters: 2), post: { poster.post($0) })
        let completed = NativeMailboxTestValues<String>()
        let counts = NativeMailboxTestValues<Int>()
        let overflow = NativeMailboxTestValues<NativeWindowOwnerFailure>()
        XCTAssertTrue(
            mailbox.requestStart(
                NativeWindowReply { result in
                    if case .success = result { completed.append("first") }
                    counts.append(mailbox.snapshot.startWaiters)
                    _ = mailbox.requestStart(
                        NativeWindowReply { result in if case .success = result { completed.append("reentrant") } })
                }))
        XCTAssertFalse(
            mailbox.requestStart(
                NativeWindowReply { result in if case .success = result { completed.append("second") } }))
        XCTAssertFalse(
            mailbox.requestStart(
                NativeWindowReply { result in if case .failure(let failure) = result { overflow.append(failure) } }))
        XCTAssertEqual(mailbox.snapshot.startWaiters, 2)
        XCTAssertEqual(overflow.all, [.capacityExceeded(resource: "nativeStartWaiters", limit: 2)])
        mailbox.didStart(controlHandle: 42)
        XCTAssertEqual(completed.all, ["first", "reentrant", "second"])
        XCTAssertEqual(counts.all, [0])
        XCTAssertEqual(mailbox.snapshot.startWaiters, 0)
        XCTAssertTrue(poster.handles.isEmpty)
    }

    func testStartFailureClearsWaitersAndLateDidStartCannotResurrectMailbox() async throws {
        let poster = NativeMailboxTestPoster()
        let mailbox = Win32NativePumpMailbox(post: { poster.post($0) })
        let failures = NativeMailboxTestValues<NativeWindowOwnerFailure>()
        for _ in 0..<2 {
            _ = mailbox.requestStart(
                NativeWindowReply { result in if case .failure(let failure) = result { failures.append(failure) } })
        }
        let failure = NativeWindowOwnerFailure.execution("controlled startup failure")
        mailbox.didFailToStart(failure)
        mailbox.didStart(controlHandle: 42)
        XCTAssertEqual(failures.all, [failure, failure])
        XCTAssertEqual(mailbox.snapshot.startWaiters, 0)
        XCTAssertEqual(mailbox.submit(.command(command())), .rejected(.ownerStopped))
        XCTAssertFalse(mailbox.registerOwnedWindow(NativeWindowKey()))
        XCTAssertTrue(poster.handles.isEmpty)
    }

    func testStopWaitersAreBoundedAndShareOneMarkerThroughActualJoin() async throws {
        let mailbox = runningMailbox()
        let results = NativeMailboxTestValues<Result<Win32NativePumpExit, NativeWindowOwnerFailure>>()
        let overflow = NativeMailboxTestValues<Result<Win32NativePumpExit, NativeWindowOwnerFailure>>()
        mailbox.requestStop(NativeWindowReply { results.append($0) })
        mailbox.requestStop(NativeWindowReply { results.append($0) })
        mailbox.requestStop(NativeWindowReply { overflow.append($0) })
        XCTAssertEqual(overflow.all, [.failure(.capacityExceeded(resource: "nativeStopWaiters", limit: 2))])
        XCTAssertEqual(mailbox.snapshot.queuedWork, 1)
        XCTAssertEqual(mailbox.snapshot.stopWaiters, 2)
        XCTAssertTrue(results.all.isEmpty)
        mailbox.consumeWake()
        XCTAssertEqual(next(mailbox), .stop)
        mailbox.willStop()
        mailbox.requestStop(NativeWindowReply { overflow.append($0) })
        XCTAssertEqual(overflow.all.count, 2)
        XCTAssertTrue(results.all.isEmpty, "Dequeue and willStop are not an actual owner join")
        XCTAssertEqual(mailbox.submit(.command(command())), .rejected(.ownerStopped))
        let actual = Win32NativePumpExit(exitCode: 7, joined: true)
        mailbox.didJoin(.success(actual))
        XCTAssertEqual(results.all, [.success(actual), .success(actual)])
        XCTAssertEqual(mailbox.snapshot.stopWaiters, 0)
        XCTAssertFalse(mailbox.snapshot.hasStopReservation)
        XCTAssertNil(next(mailbox))
        mailbox.requestStop(NativeWindowReply { results.append($0) })
        XCTAssertEqual(results.all, Array(repeating: .success(actual), count: 3))
    }

    func testStopRejectionRetiresItsMarkerBeforeCallbackReentry() async throws {
        let mailbox = runningMailbox()
        let first = NativeMailboxTestValues<Result<Win32NativePumpExit, NativeWindowOwnerFailure>>()
        let second = NativeMailboxTestValues<Result<Win32NativePumpExit, NativeWindowOwnerFailure>>()
        let snapshots = NativeMailboxTestValues<Win32NativePumpMailbox.Snapshot>()
        mailbox.requestStop(
            NativeWindowReply { result in
                first.append(result)
                snapshots.append(mailbox.snapshot)
                mailbox.requestStop(NativeWindowReply { second.append($0) })
            })
        mailbox.consumeWake()
        XCTAssertEqual(next(mailbox), .stop)
        let failure = NativeWindowOwnerFailure.execution("owned windows remain")
        mailbox.rejectStop(failure)
        XCTAssertEqual(first.all, [.failure(failure)])
        XCTAssertFalse(try XCTUnwrap(snapshots.all.first).hasStopReservation)
        XCTAssertEqual(snapshots.all.first?.stopWaiters, 0)
        XCTAssertEqual(mailbox.snapshot.queuedWork, 1)
        XCTAssertEqual(mailbox.snapshot.stopWaiters, 1)
        XCTAssertEqual(next(mailbox), .stop)
        XCTAssertNil(next(mailbox))
        mailbox.willStop()
        let actual = Win32NativePumpExit(exitCode: 0, joined: true)
        mailbox.didJoin(.success(actual))
        XCTAssertEqual(second.all, [.success(actual)])
        XCTAssertEqual(first.all.count, 1)
    }

    func testRejectingQueuedStopRemovesOnlyItsMarkerAndPreservesFIFO() async throws {
        let mailbox = runningMailbox()
        let first = command()
        let last = command()
        let results = NativeMailboxTestValues<Result<Win32NativePumpExit, NativeWindowOwnerFailure>>()
        XCTAssertEqual(mailbox.submit(.command(first)), .accepted)
        mailbox.requestStop(NativeWindowReply { results.append($0) })
        XCTAssertEqual(mailbox.submit(.command(last)), .accepted)
        mailbox.rejectStop(.closing)
        XCTAssertEqual(results.all, [.failure(.closing)])
        XCTAssertEqual(next(mailbox), .command(first.requestID))
        XCTAssertEqual(next(mailbox), .command(last.requestID))
        XCTAssertNil(next(mailbox))
        XCTAssertFalse(mailbox.snapshot.hasStopReservation)
    }

    func testDirectStopSubmissionCannotCreateAnUnownedMarker() async throws {
        let mailbox = runningMailbox()
        XCTAssertEqual(mailbox.submit(.stop), .rejected(.execution("Native stop admission requires requestStop")))
        XCTAssertFalse(mailbox.snapshot.hasStopReservation)
        XCTAssertFalse(mailbox.hasQueuedWork)
        XCTAssertNil(next(mailbox))
    }

    func testWakeFailureClearsAllQueuedReservationsBeforeAnyCallback() async throws {
        let poster = NativeMailboxTestPoster()
        let mailbox = runningMailbox(poster: poster)
        let key = NativeWindowKey()
        XCTAssertTrue(mailbox.registerOwnedWindow(key))
        let failure = postFailure
        let commands = NativeMailboxTestValues<Result<Int, NativeWindowOwnerFailure>>()
        let closes = NativeMailboxTestValues<Result<Win32NativeCloseDestruction, NativeWindowOwnerFailure>>()
        let stops = NativeMailboxTestValues<Result<Win32NativePumpExit, NativeWindowOwnerFailure>>()
        let snapshots = NativeMailboxTestValues<Win32NativePumpMailbox.Snapshot>()
        let nestedAdmission = NativeMailboxTestValues<NativeWindowSubmission>()
        let first = NativeMailboxTestCommand(
            reply: NativeWindowReply { result in
                commands.append(result)
                snapshots.append(mailbox.snapshot)
            })
        let second = command(results: commands)
        let request = close(key: key, results: closes)
        poster.onCall(1) {
            nestedAdmission.append(mailbox.submit(.command(second)))
            nestedAdmission.append(mailbox.submit(.close(request)))
            mailbox.requestStop(NativeWindowReply { stops.append($0) })
            return .failure(failure)
        }
        XCTAssertEqual(mailbox.submit(.command(first)), .rejected(failure))
        XCTAssertEqual(nestedAdmission.all, [.accepted, .accepted])
        XCTAssertEqual(commands.all, [.failure(failure), .failure(failure)])
        XCTAssertEqual(closes.all, [.failure(failure)])
        XCTAssertEqual(stops.all, [.failure(failure)])
        let cleared = try XCTUnwrap(snapshots.all.first)
        XCTAssertEqual(cleared.queuedWork, 0)
        XCTAssertEqual(cleared.queuedCommands, 0)
        XCTAssertEqual(cleared.reservedCloses, 0)
        XCTAssertEqual(cleared.stopWaiters, 0)
        XCTAssertFalse(cleared.hasStopReservation)
        XCTAssertEqual(mailbox.submit(.close(close(key: key))), .accepted)
        XCTAssertEqual(mailbox.submit(.command(command())), .accepted)
        XCTAssertEqual(poster.handles, [42, 42])
    }

    func testFailedStopWakeCanReenterWithOneFreshStopMarker() async throws {
        let poster = NativeMailboxTestPoster()
        let mailbox = runningMailbox(poster: poster)
        let failure = postFailure
        let old = NativeMailboxTestValues<Result<Win32NativePumpExit, NativeWindowOwnerFailure>>()
        let fresh = NativeMailboxTestValues<Result<Win32NativePumpExit, NativeWindowOwnerFailure>>()
        let snapshots = NativeMailboxTestValues<Win32NativePumpMailbox.Snapshot>()
        poster.onCall(1) { .failure(failure) }
        mailbox.requestStop(
            NativeWindowReply { result in
                old.append(result)
                snapshots.append(mailbox.snapshot)
                mailbox.requestStop(NativeWindowReply { fresh.append($0) })
            })
        XCTAssertEqual(old.all, [.failure(failure)])
        XCTAssertFalse(try XCTUnwrap(snapshots.all.first).hasStopReservation)
        XCTAssertEqual(snapshots.all.first?.queuedWork, 0)
        XCTAssertEqual(mailbox.snapshot.queuedWork, 1)
        XCTAssertEqual(mailbox.snapshot.stopWaiters, 1)
        XCTAssertEqual(poster.handles, [42, 42])
        XCTAssertEqual(next(mailbox), .stop)
        XCTAssertNil(next(mailbox))
        mailbox.willStop()
        let actual = Win32NativePumpExit(exitCode: 0, joined: true)
        mailbox.didJoin(.success(actual))
        XCTAssertEqual(fresh.all, [.success(actual)])
    }

    func testFailureOfConsumedWakeCannotRejectNewerQueuedWork() async throws {
        let poster = NativeMailboxTestPoster()
        let mailbox = runningMailbox(poster: poster)
        let failure = postFailure
        let oldResults = NativeMailboxTestValues<Result<Int, NativeWindowOwnerFailure>>()
        let newResults = NativeMailboxTestValues<Result<Int, NativeWindowOwnerFailure>>()
        let first = command(results: oldResults)
        let second = command(results: newResults)
        let transferred = NativeMailboxTestValues<NativeMailboxTestWork>()
        let admission = NativeMailboxTestValues<NativeWindowSubmission>()
        poster.onCall(1) {
            mailbox.consumeWake()
            if let work = mailbox.takeNext() { transferred.append(NativeMailboxTestWork(work)) }
            admission.append(mailbox.submit(.command(second)))
            return .failure(failure)
        }
        XCTAssertEqual(mailbox.submit(.command(first)), .accepted)
        XCTAssertEqual(transferred.all, [.command(first.requestID)])
        XCTAssertEqual(admission.all, [.accepted])
        XCTAssertTrue(oldResults.all.isEmpty)
        XCTAssertTrue(newResults.all.isEmpty)
        XCTAssertEqual(mailbox.snapshot.queuedWork, 1)
        XCTAssertEqual(next(mailbox), .command(second.requestID))
        XCTAssertNil(next(mailbox))
        XCTAssertTrue(first.reply.complete(.success(23)))
        XCTAssertTrue(second.reply.complete(.success(29)))
        XCTAssertEqual(oldResults.all, [.success(23)])
        XCTAssertEqual(newResults.all, [.success(29)])
        XCTAssertEqual(poster.handles, [42, 42])
    }

    func testOldStopPostFailureCannotRemoveReentrantNewStopEpoch() async throws {
        let poster = NativeMailboxTestPoster()
        let mailbox = runningMailbox(poster: poster)
        let failure = postFailure
        let rejection = NativeWindowOwnerFailure.execution("first stop rejected by owner")
        let first = NativeMailboxTestValues<Result<Win32NativePumpExit, NativeWindowOwnerFailure>>()
        let second = NativeMailboxTestValues<Result<Win32NativePumpExit, NativeWindowOwnerFailure>>()
        let transferred = NativeMailboxTestValues<NativeMailboxTestWork>()
        poster.onCall(1) {
            mailbox.consumeWake()
            if let work = mailbox.takeNext() { transferred.append(NativeMailboxTestWork(work)) }
            mailbox.rejectStop(rejection)
            return .failure(failure)
        }
        mailbox.requestStop(
            NativeWindowReply { result in
                first.append(result)
                mailbox.requestStop(NativeWindowReply { second.append($0) })
            })
        XCTAssertEqual(transferred.all, [.stop])
        XCTAssertEqual(first.all, [.failure(rejection)])
        XCTAssertTrue(second.all.isEmpty)
        XCTAssertEqual(mailbox.snapshot.queuedWork, 1)
        XCTAssertEqual(mailbox.snapshot.stopWaiters, 1)
        XCTAssertEqual(next(mailbox), .stop)
        XCTAssertNil(next(mailbox))
        mailbox.willStop()
        let actual = Win32NativePumpExit(exitCode: 0, joined: true)
        mailbox.didJoin(.success(actual))
        XCTAssertEqual(second.all, [.success(actual)])
        XCTAssertEqual(first.all.count, 1)
    }

    func testFailedDrainWakeRetiresWaitingCloseBeforeReentrantCloseAdmission() async throws {
        let poster = NativeMailboxTestPoster()
        let mailbox = runningMailbox(poster: poster)
        let key = NativeWindowKey()
        XCTAssertTrue(mailbox.registerOwnedWindow(key))
        let failure = postFailure
        let firstResults = NativeMailboxTestValues<Result<Win32NativeCloseDestruction, NativeWindowOwnerFailure>>()
        let secondResults = NativeMailboxTestValues<Result<Win32NativeCloseDestruction, NativeWindowOwnerFailure>>()
        let admissions = NativeMailboxTestValues<NativeWindowSubmission>()
        let counts = NativeMailboxTestValues<Int>()
        let second = close(key: key, results: secondResults)
        let first = Win32NativeDestructionRequest(
            key: key,
            reply: NativeWindowReply { result in
                firstResults.append(result)
                counts.append(mailbox.snapshot.reservedCloses)
                admissions.append(mailbox.submit(.close(second)))
            })
        XCTAssertEqual(mailbox.submit(.close(first)), .accepted)
        mailbox.consumeWake()
        XCTAssertEqual(next(mailbox), .close(key))
        XCTAssertTrue(mailbox.registerClose(first))
        poster.onCall(2) { .failure(failure) }
        if case .success = mailbox.signal() { XCTFail("The controlled drain post must fail") }
        XCTAssertEqual(firstResults.all, [.failure(failure)])
        XCTAssertEqual(counts.all, [0])
        XCTAssertEqual(admissions.all, [.accepted])
        XCTAssertTrue(secondResults.all.isEmpty)
        XCTAssertEqual(mailbox.snapshot.reservedCloses, 1)
        XCTAssertEqual(next(mailbox), .close(key))
        XCTAssertNil(next(mailbox))
        mailbox.retireClose(first)
        XCTAssertTrue(mailbox.registerClose(second))
    }

    func testFailedWakeKeepsCommittingCloseReservationAndActualResult() async throws {
        let poster = NativeMailboxTestPoster()
        let mailbox = runningMailbox(poster: poster)
        let key = NativeWindowKey()
        XCTAssertTrue(mailbox.registerOwnedWindow(key))
        let results = NativeMailboxTestValues<Result<Win32NativeCloseDestruction, NativeWindowOwnerFailure>>()
        let counts = NativeMailboxTestValues<Int>()
        let request = Win32NativeDestructionRequest(
            key: key,
            reply: NativeWindowReply { result in
                results.append(result)
                counts.append(mailbox.snapshot.reservedCloses)
            })
        XCTAssertEqual(mailbox.submit(.close(request)), .accepted)
        mailbox.consumeWake()
        XCTAssertEqual(next(mailbox), .close(key))
        XCTAssertTrue(mailbox.registerClose(request))
        XCTAssertTrue(request.claimDestruction())
        let failure = postFailure
        poster.onCall(2) { .failure(failure) }
        if case .success = mailbox.signal() { XCTFail("The controlled drain post must fail") }
        XCTAssertTrue(results.all.isEmpty)
        XCTAssertFalse(request.isTerminal)
        XCTAssertEqual(mailbox.snapshot.reservedCloses, 1)
        XCTAssertEqual(mailbox.submit(.close(close(key: key))), .rejected(.closing))
        let actual = Win32NativeCloseDestruction(
            nativeResult: .failed(5), didObserveNonClientDestruction: false, didUnwindNativeDispatch: true)
        XCTAssertTrue(request.complete(.success(actual), beforeCompletion: { mailbox.retireClose(request) }))
        XCTAssertEqual(results.all, [.success(actual)])
        XCTAssertEqual(counts.all, [0])
        XCTAssertEqual(mailbox.snapshot.reservedCloses, 0)
    }

    func testOwnerFailureDoesNotFabricateAnExecutingCommandReply() async throws {
        let mailbox = runningMailbox(commands: 1)
        let executingResults = NativeMailboxTestValues<Result<Int, NativeWindowOwnerFailure>>()
        let queuedResults = NativeMailboxTestValues<Result<Int, NativeWindowOwnerFailure>>()
        let executing = command(results: executingResults)
        XCTAssertEqual(mailbox.submit(.command(executing)), .accepted)
        XCTAssertEqual(next(mailbox), .command(executing.requestID))
        XCTAssertEqual(mailbox.submit(.command(command(results: queuedResults))), .accepted)
        let stops = NativeMailboxTestValues<Result<Win32NativePumpExit, NativeWindowOwnerFailure>>()
        mailbox.requestStop(NativeWindowReply { stops.append($0) })
        let failure = NativeWindowOwnerFailure.execution("controlled fatal owner failure")
        mailbox.failOwner(failure)
        XCTAssertTrue(executingResults.all.isEmpty)
        XCTAssertEqual(queuedResults.all, [.failure(failure)])
        XCTAssertEqual(stops.all, [.failure(failure)])
        XCTAssertEqual(mailbox.snapshot.queuedCommands, 0)
        XCTAssertFalse(mailbox.snapshot.hasStopReservation)
        XCTAssertEqual(mailbox.submit(.command(command())), .rejected(failure))
        XCTAssertTrue(executing.reply.complete(.success(31)))
        XCTAssertEqual(executingResults.all, [.success(31)])
        mailbox.didJoin(.success(Win32NativePumpExit(exitCode: 0, joined: true)))
        XCTAssertEqual(queuedResults.all.count, 1)
        XCTAssertEqual(stops.all.count, 1)
        XCTAssertEqual(executingResults.all, [.success(31)])
        let later = NativeMailboxTestValues<Result<Win32NativePumpExit, NativeWindowOwnerFailure>>()
        mailbox.requestStop(NativeWindowReply { later.append($0) })
        XCTAssertEqual(later.all, [.failure(failure)])
    }

    func testOwnerFailureRetiresWaitingCloseBeforeItsReply() async throws {
        let mailbox = runningMailbox()
        let key = NativeWindowKey()
        XCTAssertTrue(mailbox.registerOwnedWindow(key))
        let results = NativeMailboxTestValues<Result<Win32NativeCloseDestruction, NativeWindowOwnerFailure>>()
        let counts = NativeMailboxTestValues<Int>()
        let request = Win32NativeDestructionRequest(
            key: key,
            reply: NativeWindowReply { result in
                results.append(result)
                counts.append(mailbox.snapshot.reservedCloses)
            })
        XCTAssertEqual(mailbox.submit(.close(request)), .accepted)
        XCTAssertEqual(next(mailbox), .close(key))
        let failure = NativeWindowOwnerFailure.execution("controlled owner failure")
        mailbox.failOwner(failure)
        XCTAssertEqual(results.all, [.failure(failure)])
        XCTAssertEqual(counts.all, [0])
        XCTAssertEqual(mailbox.snapshot.reservedCloses, 0)
        XCTAssertFalse(request.claimDestruction())
        mailbox.failOwner(failure)
        XCTAssertEqual(results.all.count, 1)
    }

    func testFailedWakeAfterStopDequeueCannotFabricateItsJoinResult() async throws {
        let poster = NativeMailboxTestPoster()
        let mailbox = runningMailbox(poster: poster)
        let results = NativeMailboxTestValues<Result<Win32NativePumpExit, NativeWindowOwnerFailure>>()
        mailbox.requestStop(NativeWindowReply { results.append($0) })
        mailbox.consumeWake()
        XCTAssertEqual(next(mailbox), .stop)
        mailbox.willStop()
        let failure = postFailure
        poster.onCall(2) { .failure(failure) }
        if case .success = mailbox.signal() { XCTFail("The controlled post must fail") }
        mailbox.rejectStop(.closing)
        XCTAssertTrue(results.all.isEmpty)
        XCTAssertTrue(mailbox.snapshot.hasStopReservation)
        XCTAssertEqual(mailbox.snapshot.stopWaiters, 1)
        let actual = Win32NativePumpExit(exitCode: 9, joined: true)
        mailbox.didJoin(.success(actual))
        XCTAssertEqual(results.all, [.success(actual)])
    }

    func testProductionControlLimitsAllow32CommandsOfEachKindPerOwnedWindow() async throws {
        let poster = NativeMailboxTestPoster()
        let mailbox = Win32NativePumpMailbox(post: { poster.post($0) })
        XCTAssertTrue(mailbox.requestStart(NativeWindowReply { _ in }))
        mailbox.didStart(controlHandle: 42)
        let key = NativeWindowKey()
        XCTAssertTrue(mailbox.registerOwnedWindow(key))
        for nonce in UInt(1)...32 {
            XCTAssertEqual(mailbox.submit(.command(control(key: key, operation: .requestClose))), .accepted)
            XCTAssertEqual(mailbox.submit(.command(control(key: key, operation: .deferredCloseWake(nonce)))), .accepted)
        }
        let rejected = NativeMailboxTestValues<NativeMailboxTestControlResult>()
        XCTAssertEqual(
            mailbox.submit(.command(control(key: key, operation: .requestClose, results: rejected))),
            .rejected(.capacityExceeded(resource: "nativeCloseRequests", limit: 32)))
        XCTAssertEqual(
            mailbox.submit(.command(control(key: key, operation: .deferredCloseWake(33), results: rejected))),
            .rejected(.capacityExceeded(resource: "nativeDeferredCloseWakes", limit: 32)))
        XCTAssertEqual(
            rejected.all,
            [
                .failure(.capacityExceeded(resource: "nativeCloseRequests", limit: 32)),
                .failure(.capacityExceeded(resource: "nativeDeferredCloseWakes", limit: 32)),
            ])
        XCTAssertEqual(mailbox.snapshot.queuedCommands, 0)
        XCTAssertEqual(mailbox.snapshot.queuedCloseRequests, 32)
        XCTAssertEqual(mailbox.snapshot.queuedDeferredCloseWakes, 32)
        XCTAssertEqual(mailbox.snapshot.queuedWork, 64)
        XCTAssertEqual(mailbox.snapshot.storageCapacity, 194)
        XCTAssertEqual(poster.handles, [42])
    }

    func testFullOrdinaryQueueAdmitsBothControlBudgetsFinalCloseAndStopInFIFO() async throws {
        let mailbox = runningMailbox(commands: 1)
        let key = NativeWindowKey()
        XCTAssertTrue(mailbox.registerOwnedWindow(key))
        let ordinary = command()
        let closeRequest1 = control(key: key, operation: .requestClose)
        let wake1 = control(key: key, operation: .deferredCloseWake(10))
        let closeRequest2 = control(key: key, operation: .requestClose)
        let wake2 = control(key: key, operation: .deferredCloseWake(11))
        XCTAssertEqual(mailbox.submit(.command(ordinary)), .accepted)
        for item in [closeRequest1, wake1, closeRequest2, wake2] {
            XCTAssertEqual(mailbox.submit(.command(item)), .accepted)
        }
        XCTAssertEqual(mailbox.submit(.close(close(key: key))), .accepted)
        mailbox.requestStop(NativeWindowReply { _ in })
        XCTAssertEqual(mailbox.snapshot.queuedCommands, 1)
        XCTAssertEqual(mailbox.snapshot.queuedCloseRequests, 2)
        XCTAssertEqual(mailbox.snapshot.queuedDeferredCloseWakes, 2)
        XCTAssertEqual(mailbox.snapshot.reservedCloses, 1)
        XCTAssertEqual(mailbox.snapshot.queuedWork, 7)
        XCTAssertEqual(mailbox.snapshot.storageCapacity, 7)
        XCTAssertEqual(next(mailbox), .command(ordinary.requestID))
        for item in [closeRequest1, wake1, closeRequest2, wake2] {
            XCTAssertEqual(next(mailbox), .command(item.requestID))
        }
        XCTAssertEqual(next(mailbox), .close(key))
        XCTAssertEqual(next(mailbox), .stop)
        XCTAssertNil(next(mailbox))
        XCTAssertEqual(mailbox.snapshot.queuedCloseRequests, 0)
        XCTAssertEqual(mailbox.snapshot.queuedDeferredCloseWakes, 0)
        XCTAssertEqual(mailbox.snapshot.reservedCloses, 1, "The final close keeps its separate terminal reservation")
    }

    func testControlBudgetsAreIndependentForEachKindAndOwnedLifetime() async throws {
        let mailbox = runningMailbox(commands: 0, controlCommands: 1)
        let first = NativeWindowKey()
        let second = NativeWindowKey()
        XCTAssertTrue(mailbox.registerOwnedWindow(first))
        XCTAssertTrue(mailbox.registerOwnedWindow(second))
        XCTAssertEqual(mailbox.submit(.command(control(key: first, operation: .requestClose))), .accepted)
        XCTAssertEqual(
            mailbox.submit(.command(control(key: first, operation: .requestClose))),
            .rejected(.capacityExceeded(resource: "nativeCloseRequests", limit: 1)))
        XCTAssertEqual(mailbox.submit(.command(control(key: first, operation: .deferredCloseWake(1)))), .accepted)
        XCTAssertEqual(
            mailbox.submit(.command(control(key: first, operation: .deferredCloseWake(2)))),
            .rejected(.capacityExceeded(resource: "nativeDeferredCloseWakes", limit: 1)))
        XCTAssertEqual(mailbox.submit(.command(control(key: second, operation: .requestClose))), .accepted)
        XCTAssertEqual(mailbox.submit(.command(control(key: second, operation: .deferredCloseWake(3)))), .accepted)
        XCTAssertEqual(mailbox.snapshot.queuedCommands, 0)
        XCTAssertEqual(mailbox.snapshot.queuedCloseRequests, 2)
        XCTAssertEqual(mailbox.snapshot.queuedDeferredCloseWakes, 2)
        XCTAssertEqual(mailbox.snapshot.storageCapacity, 7)
    }

    func testOtherBuiltInOperationsAndCustomCommandsCannotUseControlReservations() async throws {
        let mailbox = runningMailbox(commands: 0, controlCommands: 1)
        let key = NativeWindowKey()
        XCTAssertTrue(mailbox.registerOwnedWindow(key))
        let failures = NativeMailboxTestValues<NativeMailboxTestControlResult>()
        XCTAssertEqual(
            mailbox.submit(.command(control(key: key, operation: .show, results: failures))),
            .rejected(.capacityExceeded(resource: "nativeCommandQueue", limit: 0)))
        let custom = NativeMailboxTestCommand(windowKey: key, reply: NativeWindowReply { _ in })
        XCTAssertEqual(
            mailbox.submit(.command(custom)), .rejected(.capacityExceeded(resource: "nativeCommandQueue", limit: 0)))
        XCTAssertEqual(failures.all, [.failure(.capacityExceeded(resource: "nativeCommandQueue", limit: 0))])
        XCTAssertEqual(mailbox.snapshot.queuedWork, 0)
        XCTAssertEqual(mailbox.snapshot.queuedCloseRequests, 0)
        XCTAssertEqual(mailbox.snapshot.queuedDeferredCloseWakes, 0)
        XCTAssertEqual(mailbox.submit(.command(control(key: key, operation: .requestClose))), .accepted)
        XCTAssertEqual(mailbox.submit(.command(control(key: key, operation: .deferredCloseWake(1)))), .accepted)
    }

    func testDistinctAndRepeatedDeferredNoncesKeepFIFOAndTheirOriginalReplies() async throws {
        let mailbox = runningMailbox(commands: 1, controlCommands: 3)
        let key = NativeWindowKey()
        XCTAssertTrue(mailbox.registerOwnedWindow(key))
        let firstResults = NativeMailboxTestValues<NativeMailboxTestControlResult>()
        let secondResults = NativeMailboxTestValues<NativeMailboxTestControlResult>()
        let thirdResults = NativeMailboxTestValues<NativeMailboxTestControlResult>()
        let first = control(key: key, operation: .deferredCloseWake(7), results: firstResults)
        let ordinary = command()
        let second = control(key: key, operation: .deferredCloseWake(8), results: secondResults)
        let third = control(key: key, operation: .deferredCloseWake(8), results: thirdResults)
        XCTAssertEqual(mailbox.submit(.command(first)), .accepted)
        XCTAssertEqual(mailbox.submit(.command(ordinary)), .accepted)
        XCTAssertEqual(mailbox.submit(.command(second)), .accepted)
        XCTAssertEqual(mailbox.submit(.command(third)), .accepted)
        XCTAssertEqual(mailbox.snapshot.queuedDeferredCloseWakes, 3)
        XCTAssertTrue(firstResults.all.isEmpty)
        XCTAssertTrue(secondResults.all.isEmpty)
        XCTAssertTrue(thirdResults.all.isEmpty)
        for (index, expected) in [first, second, third].enumerated() {
            if index == 1 { XCTAssertEqual(next(mailbox), .command(ordinary.requestID)) }
            let work = try XCTUnwrap(mailbox.takeNext())
            guard case .command(let command) = work else { return XCTFail("Expected the unchanged typed command") }
            let actual = try XCTUnwrap(command as? Win32NativeWindowOperationCommand)
            XCTAssertEqual(actual.requestID, expected.requestID)
            XCTAssertTrue(actual.reply === expected.reply, "Admission must not replace or combine reply cells")
            guard case .deferredCloseWake(let nonce) = actual.operation else { return XCTFail("Lost deferred wake") }
            XCTAssertEqual(nonce, index == 0 ? 7 : 8)
            actual.reply.complete(.success(.completed))
        }
        XCTAssertNil(next(mailbox))
        XCTAssertEqual(firstResults.all, [.completed])
        XCTAssertEqual(secondResults.all, [.completed])
        XCTAssertEqual(thirdResults.all, [.completed])
    }

    func testSameNonceRearmCanQueueWhileThePriorCommandStillOwnsItsReply() async throws {
        let mailbox = runningMailbox(commands: 0, controlCommands: 1)
        let key = NativeWindowKey()
        XCTAssertTrue(mailbox.registerOwnedWindow(key))
        let firstResults = NativeMailboxTestValues<NativeMailboxTestControlResult>()
        let secondResults = NativeMailboxTestValues<NativeMailboxTestControlResult>()
        let first = control(key: key, operation: .deferredCloseWake(13), results: firstResults)
        let rearm = control(key: key, operation: .deferredCloseWake(13), results: secondResults)
        XCTAssertEqual(mailbox.submit(.command(first)), .accepted)
        XCTAssertEqual(next(mailbox), .command(first.requestID))
        XCTAssertTrue(firstResults.all.isEmpty)
        XCTAssertEqual(mailbox.snapshot.queuedDeferredCloseWakes, 0)
        XCTAssertEqual(mailbox.submit(.command(rearm)), .accepted)
        XCTAssertEqual(mailbox.snapshot.queuedDeferredCloseWakes, 1)
        XCTAssertTrue(secondResults.all.isEmpty)
        XCTAssertTrue(first.reply.complete(.success(.completed)))
        XCTAssertEqual(next(mailbox), .command(rearm.requestID))
        XCTAssertTrue(rearm.reply.complete(.success(.completed)))
        XCTAssertEqual(firstResults.all, [.completed])
        XCTAssertEqual(secondResults.all, [.completed])
        XCTAssertEqual(mailbox.snapshot.queuedDeferredCloseWakes, 0)
    }

    func testUnknownControlLifetimesCannotReserveAnyQueueStorage() async throws {
        let mailbox = runningMailbox(commands: 0)
        let failures = NativeMailboxTestValues<NativeMailboxTestControlResult>()
        for nonce in UInt(1)...64 {
            let key = NativeWindowKey()
            XCTAssertEqual(
                mailbox.submit(.command(control(key: key, operation: .requestClose, results: failures))),
                .rejected(.staleWindow))
            XCTAssertEqual(
                mailbox.submit(.command(control(key: key, operation: .deferredCloseWake(nonce), results: failures))),
                .rejected(.staleWindow))
        }
        XCTAssertEqual(failures.all, Array(repeating: .failure(.staleWindow), count: 128))
        XCTAssertEqual(mailbox.snapshot.queuedCloseRequests, 0)
        XCTAssertEqual(mailbox.snapshot.queuedDeferredCloseWakes, 0)
        XCTAssertEqual(mailbox.snapshot.ownedWindows, 0)
        XCTAssertEqual(mailbox.snapshot.queuedWork, 0)
        XCTAssertEqual(mailbox.snapshot.storageCapacity, 1)
    }

    func testLifetimeRetirementClearsQueuedControlsBeforeCallbacksWithoutFailingExecutingWork() async throws {
        let mailbox = runningMailbox(commands: 1, controlCommands: 1)
        let retiredKey = NativeWindowKey()
        let liveKey = NativeWindowKey()
        XCTAssertTrue(mailbox.registerOwnedWindow(retiredKey))
        XCTAssertTrue(mailbox.registerOwnedWindow(liveKey))
        let executingResults = NativeMailboxTestValues<NativeMailboxTestControlResult>()
        let executing = control(key: retiredKey, operation: .requestClose, results: executingResults)
        XCTAssertEqual(mailbox.submit(.command(executing)), .accepted)
        XCTAssertEqual(next(mailbox), .command(executing.requestID))
        let ordinary = command()
        XCTAssertEqual(mailbox.submit(.command(ordinary)), .accepted)
        let results = NativeMailboxTestValues<NativeMailboxTestControlResult>()
        let snapshots = NativeMailboxTestValues<Win32NativePumpMailbox.Snapshot>()
        let admissions = NativeMailboxTestValues<NativeWindowSubmission>()
        let replacement = control(key: liveKey, operation: .requestClose)
        let stale = control(key: retiredKey, operation: .deferredCloseWake(19))
        let queued = Win32NativeWindowOperationCommand(
            windowKey: retiredKey, operation: .requestClose,
            reply: NativeWindowReply { result in
                results.append(NativeMailboxTestControlResult(result))
                snapshots.append(mailbox.snapshot)
                admissions.append(mailbox.submit(.command(stale)))
                admissions.append(mailbox.submit(.command(replacement)))
            })
        XCTAssertEqual(mailbox.submit(.command(queued)), .accepted)
        XCTAssertEqual(
            mailbox.submit(.command(control(key: retiredKey, operation: .deferredCloseWake(18), results: results))),
            .accepted)
        XCTAssertEqual(mailbox.submit(.close(close(key: retiredKey))), .accepted)
        mailbox.retireOwnedWindow(retiredKey)
        XCTAssertEqual(results.all, [.failure(.staleWindow), .failure(.staleWindow)])
        XCTAssertEqual(admissions.all, [.rejected(.staleWindow), .accepted])
        let cleared = try XCTUnwrap(snapshots.all.first)
        XCTAssertEqual(cleared.ownedWindows, 1)
        XCTAssertEqual(cleared.queuedCloseRequests, 0)
        XCTAssertEqual(cleared.queuedDeferredCloseWakes, 0)
        XCTAssertEqual(cleared.reservedCloses, 0)
        XCTAssertEqual(cleared.storageCapacity, 5)
        XCTAssertEqual(mailbox.submit(.command(executing)), .rejected(.staleWindow))
        XCTAssertTrue(executingResults.all.isEmpty)
        XCTAssertTrue(executing.reply.complete(.success(.completed)))
        XCTAssertEqual(executingResults.all, [.completed])
        XCTAssertEqual(next(mailbox), .command(ordinary.requestID))
        XCTAssertEqual(next(mailbox), .command(replacement.requestID))
        XCTAssertNil(next(mailbox))
    }

    func testControlWakeFailureClearsBothBudgetsBeforeReentrantAdmission() async throws {
        let poster = NativeMailboxTestPoster()
        let mailbox = runningMailbox(commands: 0, controlCommands: 1, poster: poster)
        let key = NativeWindowKey()
        XCTAssertTrue(mailbox.registerOwnedWindow(key))
        let failure = postFailure
        let firstResults = NativeMailboxTestValues<NativeMailboxTestControlResult>()
        let wakeResults = NativeMailboxTestValues<NativeMailboxTestControlResult>()
        let newResults = NativeMailboxTestValues<NativeMailboxTestControlResult>()
        let snapshots = NativeMailboxTestValues<Win32NativePumpMailbox.Snapshot>()
        let admissions = NativeMailboxTestValues<NativeWindowSubmission>()
        let wake = control(key: key, operation: .deferredCloseWake(3), results: wakeResults)
        let replacement = control(key: key, operation: .requestClose, results: newResults)
        let first = Win32NativeWindowOperationCommand(
            windowKey: key, operation: .requestClose,
            reply: NativeWindowReply { result in
                firstResults.append(NativeMailboxTestControlResult(result))
                snapshots.append(mailbox.snapshot)
                admissions.append(mailbox.submit(.command(replacement)))
            })
        poster.onCall(1) {
            admissions.append(mailbox.submit(.command(wake)))
            return .failure(failure)
        }
        XCTAssertEqual(mailbox.submit(.command(first)), .rejected(failure))
        XCTAssertEqual(firstResults.all, [.failure(failure)])
        XCTAssertEqual(wakeResults.all, [.failure(failure)])
        XCTAssertEqual(admissions.all, [.accepted, .accepted])
        let cleared = try XCTUnwrap(snapshots.all.first)
        XCTAssertEqual(cleared.queuedCloseRequests, 0)
        XCTAssertEqual(cleared.queuedDeferredCloseWakes, 0)
        XCTAssertEqual(cleared.queuedWork, 0)
        XCTAssertEqual(mailbox.snapshot.queuedCloseRequests, 1)
        XCTAssertEqual(mailbox.snapshot.queuedDeferredCloseWakes, 0)
        XCTAssertTrue(newResults.all.isEmpty)
        XCTAssertEqual(next(mailbox), .command(replacement.requestID))
        XCTAssertTrue(replacement.reply.complete(.success(.completed)))
        XCTAssertEqual(newResults.all, [.completed])
        XCTAssertEqual(poster.handles, [42, 42])
    }

    func testQueuedTypedCommandAliasesCannotCompleteTheOriginalOwnedReply() async throws {
        let mailbox = runningMailbox(commands: 0, controlCommands: 1)
        let key = NativeWindowKey()
        XCTAssertTrue(mailbox.registerOwnedWindow(key))
        let results = NativeMailboxTestValues<NativeMailboxTestControlResult>()
        let original = control(key: key, operation: .requestClose, results: results)
        XCTAssertEqual(mailbox.submit(.command(original)), .accepted)
        XCTAssertEqual(mailbox.submit(.command(original)), .rejected(.closing))
        let alias = Win32NativeWindowOperationCommand(
            windowKey: key, operation: .deferredCloseWake(21), reply: original.reply)
        XCTAssertNotEqual(alias.requestID, original.requestID)
        XCTAssertEqual(mailbox.submit(.command(alias)), .rejected(.closing))
        XCTAssertTrue(results.all.isEmpty)
        XCTAssertEqual(mailbox.snapshot.queuedWork, 1)
        XCTAssertEqual(mailbox.snapshot.queuedCloseRequests, 1)
        XCTAssertEqual(mailbox.snapshot.queuedDeferredCloseWakes, 0)
        XCTAssertEqual(next(mailbox), .command(original.requestID))
        XCTAssertTrue(original.reply.complete(.success(.completed)))
        XCTAssertEqual(results.all, [.completed])
    }

    func testExecutingTypedCommandAliasKeepsItsActualReplyDespiteOverflowAndOwnerFailure() async throws {
        let mailbox = runningMailbox(commands: 0, controlCommands: 1)
        let key = NativeWindowKey()
        XCTAssertTrue(mailbox.registerOwnedWindow(key))
        let executingResults = NativeMailboxTestValues<NativeMailboxTestControlResult>()
        let queuedResults = NativeMailboxTestValues<NativeMailboxTestControlResult>()
        let executing = control(key: key, operation: .requestClose, results: executingResults)
        XCTAssertEqual(mailbox.submit(.command(executing)), .accepted)
        XCTAssertEqual(next(mailbox), .command(executing.requestID))
        XCTAssertEqual(
            mailbox.submit(.command(control(key: key, operation: .requestClose, results: queuedResults))), .accepted)
        XCTAssertEqual(mailbox.submit(.command(executing)), .rejected(.closing))
        XCTAssertTrue(executingResults.all.isEmpty)
        let failure = NativeWindowOwnerFailure.execution("controlled owner failure with a control command executing")
        mailbox.failOwner(failure)
        XCTAssertEqual(mailbox.snapshot.queuedCloseRequests, 0)
        XCTAssertEqual(mailbox.snapshot.queuedDeferredCloseWakes, 0)
        XCTAssertEqual(queuedResults.all, [.failure(failure)])
        XCTAssertEqual(mailbox.submit(.command(executing)), .rejected(.closing))
        XCTAssertTrue(executingResults.all.isEmpty)
        XCTAssertTrue(executing.reply.complete(.success(.completed)))
        XCTAssertEqual(executingResults.all, [.completed])
        XCTAssertEqual(queuedResults.all.count, 1)
    }

    func testOldPostFailureCannotRejectAControlCommandInANewerWakeEpoch() async throws {
        let poster = NativeMailboxTestPoster()
        let mailbox = runningMailbox(commands: 0, controlCommands: 1, poster: poster)
        let key = NativeWindowKey()
        XCTAssertTrue(mailbox.registerOwnedWindow(key))
        let firstResults = NativeMailboxTestValues<NativeMailboxTestControlResult>()
        let secondResults = NativeMailboxTestValues<NativeMailboxTestControlResult>()
        let first = control(key: key, operation: .deferredCloseWake(25), results: firstResults)
        let second = control(key: key, operation: .deferredCloseWake(26), results: secondResults)
        let failure = postFailure
        let transfers = NativeMailboxTestValues<NativeMailboxTestWork>()
        let admissions = NativeMailboxTestValues<NativeWindowSubmission>()
        poster.onCall(1) {
            mailbox.consumeWake()
            if let work = mailbox.takeNext() { transfers.append(NativeMailboxTestWork(work)) }
            admissions.append(mailbox.submit(.command(second)))
            return .failure(failure)
        }
        XCTAssertEqual(mailbox.submit(.command(first)), .accepted)
        XCTAssertEqual(transfers.all, [.command(first.requestID)])
        XCTAssertEqual(admissions.all, [.accepted])
        XCTAssertEqual(mailbox.snapshot.queuedDeferredCloseWakes, 1)
        XCTAssertTrue(firstResults.all.isEmpty)
        XCTAssertTrue(secondResults.all.isEmpty)
        XCTAssertTrue(first.reply.complete(.success(.completed)))
        XCTAssertEqual(next(mailbox), .command(second.requestID))
        XCTAssertTrue(second.reply.complete(.success(.completed)))
        XCTAssertEqual(firstResults.all, [.completed])
        XCTAssertEqual(secondResults.all, [.completed])
        XCTAssertEqual(poster.handles, [42, 42])
    }

    private func checkDetachedWakeAlias(newRequestID: Bool, fillsControlBudget: Bool) throws {
        let poster = NativeMailboxTestPoster()
        let mailbox = runningMailbox(commands: 0, controlCommands: 1, poster: poster)
        let key = NativeWindowKey()
        XCTAssertTrue(mailbox.registerOwnedWindow(key))
        let failure = postFailure
        let laterResults = NativeMailboxTestValues<NativeMailboxTestControlResult>()
        let fillerResults = NativeMailboxTestValues<NativeMailboxTestControlResult>()
        let later = control(key: key, operation: .deferredCloseWake(41), results: laterResults)
        let alias =
            newRequestID
            ? Win32NativeWindowOperationCommand(windowKey: key, operation: .deferredCloseWake(41), reply: later.reply)
            : later
        let filler = control(key: key, operation: .deferredCloseWake(42), results: fillerResults)
        let admissions = NativeMailboxTestValues<NativeWindowSubmission>()
        let claims = NativeMailboxTestValues<Bool>()
        let firstResults = NativeMailboxTestValues<NativeMailboxTestControlResult>()
        let first = Win32NativeWindowOperationCommand(
            windowKey: key, operation: .requestClose,
            reply: NativeWindowReply { result in
                firstResults.append(NativeMailboxTestControlResult(result))
                claims.append(later.reply.isCompleted)
                if fillsControlBudget { admissions.append(mailbox.submit(.command(filler))) }
                admissions.append(mailbox.submit(.command(alias)))
            })
        poster.onCall(1) {
            admissions.append(mailbox.submit(.command(later)))
            return .failure(failure)
        }
        XCTAssertEqual(mailbox.submit(.command(first)), .rejected(failure))
        XCTAssertEqual(firstResults.all, [.failure(failure)])
        XCTAssertEqual(claims.all, [true], "Every batch result must be claimed before its first callback")
        XCTAssertEqual(laterResults.all, [.failure(failure)], "Overflow must not replace the original post failure")
        XCTAssertEqual(
            admissions.all,
            fillsControlBudget ? [.accepted, .accepted, .rejected(.closing)] : [.accepted, .rejected(.closing)])
        XCTAssertEqual(mailbox.snapshot.queuedDeferredCloseWakes, fillsControlBudget ? 1 : 0)
        XCTAssertEqual(mailbox.snapshot.queuedCloseRequests, 0)
        if fillsControlBudget {
            XCTAssertTrue(fillerResults.all.isEmpty)
            XCTAssertEqual(next(mailbox), .command(filler.requestID))
            XCTAssertTrue(filler.reply.complete(.success(.completed)))
            XCTAssertEqual(fillerResults.all, [.completed])
        }
        XCTAssertNil(next(mailbox), "A rejected alias must never leave a native side effect queued")
    }

    func testDetachedBatchExactAliasCannotWinLaterReplyWithFullControlBudget() async throws {
        try checkDetachedWakeAlias(newRequestID: false, fillsControlBudget: true)
    }

    func testDetachedBatchExactAliasCannotBeReadmittedWithFreeControlBudget() async throws {
        try checkDetachedWakeAlias(newRequestID: false, fillsControlBudget: false)
    }

    func testDetachedBatchSharedReplyWithNewIDCannotWinLaterReplyWithFullControlBudget() async throws {
        try checkDetachedWakeAlias(newRequestID: true, fillsControlBudget: true)
    }

    func testDetachedBatchSharedReplyWithNewIDCannotBeReadmittedWithFreeControlBudget() async throws {
        try checkDetachedWakeAlias(newRequestID: true, fillsControlBudget: false)
    }

    func testRetiredLifetimeBatchCannotReadmitLaterReplyThroughAnotherLiveKey() async throws {
        let mailbox = runningMailbox(commands: 0, controlCommands: 1)
        let oldKey = NativeWindowKey()
        let liveKey = NativeWindowKey()
        XCTAssertTrue(mailbox.registerOwnedWindow(oldKey))
        XCTAssertTrue(mailbox.registerOwnedWindow(liveKey))
        let laterResults = NativeMailboxTestValues<NativeMailboxTestControlResult>()
        let later = control(key: oldKey, operation: .deferredCloseWake(45), results: laterResults)
        let alias = Win32NativeWindowOperationCommand(
            windowKey: liveKey, operation: .deferredCloseWake(45), reply: later.reply)
        let admissions = NativeMailboxTestValues<NativeWindowSubmission>()
        let claims = NativeMailboxTestValues<Bool>()
        let first = Win32NativeWindowOperationCommand(
            windowKey: oldKey, operation: .requestClose,
            reply: NativeWindowReply { _ in
                claims.append(later.reply.isCompleted)
                admissions.append(mailbox.submit(.command(alias)))
            })
        XCTAssertEqual(mailbox.submit(.command(first)), .accepted)
        XCTAssertEqual(mailbox.submit(.command(later)), .accepted)
        mailbox.retireOwnedWindow(oldKey)
        XCTAssertEqual(claims.all, [true])
        XCTAssertEqual(admissions.all, [.rejected(.closing)])
        XCTAssertEqual(laterResults.all, [.failure(.staleWindow)])
        XCTAssertEqual(mailbox.snapshot.ownedWindows, 1)
        XCTAssertEqual(mailbox.snapshot.queuedWork, 0)
        XCTAssertEqual(mailbox.snapshot.queuedDeferredCloseWakes, 0)
        XCTAssertNil(next(mailbox))
    }

    func testGenericCommandBatchClaimsLaterReplyBeforeControlCallbackReentry() async throws {
        let poster = NativeMailboxTestPoster()
        let mailbox = runningMailbox(commands: 1, controlCommands: 1, poster: poster)
        let key = NativeWindowKey()
        XCTAssertTrue(mailbox.registerOwnedWindow(key))
        let failure = postFailure
        let results = NativeMailboxTestValues<Result<Int, NativeWindowOwnerFailure>>()
        let later = command(results: results)
        let filler = command()
        let admissions = NativeMailboxTestValues<NativeWindowSubmission>()
        let claims = NativeMailboxTestValues<Bool>()
        let first = Win32NativeWindowOperationCommand(
            windowKey: key, operation: .requestClose,
            reply: NativeWindowReply { _ in
                claims.append(later.reply.isCompleted)
                admissions.append(mailbox.submit(.command(filler)))
                admissions.append(mailbox.submit(.command(later)))
            })
        poster.onCall(1) {
            admissions.append(mailbox.submit(.command(later)))
            return .failure(failure)
        }
        XCTAssertEqual(mailbox.submit(.command(first)), .rejected(failure))
        XCTAssertEqual(claims.all, [true])
        XCTAssertEqual(admissions.all, [.accepted, .accepted, .rejected(.closing)])
        XCTAssertEqual(results.all, [.failure(failure)])
        XCTAssertEqual(next(mailbox), .command(filler.requestID))
        XCTAssertNil(next(mailbox))
    }

    func testCommandMetadataIsCapturedOnceOutsideMutexAndQueuedRejectUsesCoreReply() async throws {
        let mailbox = runningMailbox(commands: 1)
        let reads = NativeMailboxTestValues<String>()
        let snapshots = NativeMailboxTestValues<Int>()
        let overrides = NativeMailboxTestValues<NativeWindowOwnerFailure>()
        let results = NativeMailboxTestValues<Result<Int, NativeWindowOwnerFailure>>()
        let item = NativeMailboxTestInspectedCommand(
            reply: NativeWindowReply { results.append($0) },
            read: { name in
                reads.append(name)
                snapshots.append(mailbox.snapshot.queuedWork)
            },
            rejected: { overrides.append($0) })
        XCTAssertEqual(mailbox.submit(.command(item)), .accepted)
        XCTAssertEqual(reads.all, ["requestID", "commandReply"])
        XCTAssertEqual(snapshots.all, [0, 0])
        let failure = NativeWindowOwnerFailure.execution("controlled cached-capability rejection")
        mailbox.failOwner(failure)
        XCTAssertEqual(results.all, [.failure(failure)])
        XCTAssertTrue(overrides.all.isEmpty, "Custom reject is not a queued-failure callback")
        XCTAssertEqual(reads.all, ["requestID", "commandReply"], "Failure must not re-read arbitrary command metadata")
    }

    func testDuplicateCommandIDWithFreshReplyRejectsOnlyTheFreshObserver() async throws {
        let mailbox = runningMailbox(commands: 1)
        let originalResults = NativeMailboxTestValues<Result<Int, NativeWindowOwnerFailure>>()
        let rejectedResults = NativeMailboxTestValues<Result<Int, NativeWindowOwnerFailure>>()
        let original = command(results: originalResults)
        let fresh = NativeMailboxTestCommand(
            windowKey: original.windowKey, requestID: original.requestID,
            reply: NativeWindowReply { rejectedResults.append($0) })
        XCTAssertEqual(mailbox.submit(.command(original)), .accepted)
        XCTAssertEqual(mailbox.submit(.command(fresh)), .rejected(.closing))
        XCTAssertEqual(rejectedResults.all, [.failure(.closing)])
        XCTAssertTrue(originalResults.all.isEmpty)
        XCTAssertEqual(mailbox.snapshot.queuedCommands, 1)
        XCTAssertEqual(next(mailbox), .command(original.requestID))
        XCTAssertTrue(original.reply.complete(.success(47)))
        XCTAssertEqual(originalResults.all, [.success(47)])
    }

    func testSharedOwnedReplyTakesPrecedenceOverAnotherCommandsDuplicateID() async throws {
        let mailbox = runningMailbox(commands: 2)
        let firstResults = NativeMailboxTestValues<Result<Int, NativeWindowOwnerFailure>>()
        let secondResults = NativeMailboxTestValues<Result<Int, NativeWindowOwnerFailure>>()
        let first = command(results: firstResults)
        let second = command(results: secondResults)
        XCTAssertEqual(mailbox.submit(.command(first)), .accepted)
        XCTAssertEqual(mailbox.submit(.command(second)), .accepted)
        let alias = NativeMailboxTestCommand(requestID: first.requestID, reply: second.reply)
        XCTAssertEqual(mailbox.submit(.command(alias)), .rejected(.closing))
        XCTAssertTrue(firstResults.all.isEmpty)
        XCTAssertTrue(secondResults.all.isEmpty)
        XCTAssertEqual(mailbox.snapshot.queuedCommands, 2)
    }

    func testAlreadyClaimedControlReplyCannotQueueAnEffectBeforeDelivery() async throws {
        let mailbox = runningMailbox(commands: 0)
        let key = NativeWindowKey()
        XCTAssertTrue(mailbox.registerOwnedWindow(key))
        let results = NativeMailboxTestValues<NativeMailboxTestControlResult>()
        let item = control(key: key, operation: .deferredCloseWake(49), results: results)
        let delivery = try XCTUnwrap(item.reply.prepareCompletion(.failure(.postFailed(code: 49))))
        XCTAssertEqual(mailbox.submit(.command(item)), .rejected(.closing))
        XCTAssertTrue(results.all.isEmpty)
        XCTAssertEqual(mailbox.snapshot.queuedWork, 0)
        XCTAssertTrue(delivery.deliver())
        XCTAssertFalse(delivery.deliver())
        XCTAssertEqual(results.all, [.failure(.postFailed(code: 49))])
    }

    func testAlreadyClaimedCreationAndCloseRepliesCannotQueueNativeEffects() async throws {
        let mailbox = runningMailbox()
        let createdResults = NativeMailboxTestValues<Result<NativeWindowSurface, NativeWindowOwnerFailure>>()
        let create = creation(results: createdResults)
        let creationDelivery = try XCTUnwrap(create.reply.prepareCompletion(.failure(.unavailable)))
        XCTAssertEqual(mailbox.submit(.create(create)), .rejected(.closing))
        let key = NativeWindowKey()
        XCTAssertTrue(mailbox.registerOwnedWindow(key))
        let closeResults = NativeMailboxTestValues<Result<Win32NativeCloseDestruction, NativeWindowOwnerFailure>>()
        let request = close(key: key, results: closeResults)
        let closeDelivery = try XCTUnwrap(request.reply.prepareCompletion(.failure(.closed)))
        XCTAssertEqual(mailbox.submit(.close(request)), .rejected(.closing))
        XCTAssertEqual(mailbox.snapshot.queuedWork, 0)
        XCTAssertEqual(mailbox.snapshot.reservedCloses, 0)
        XCTAssertTrue(createdResults.all.isEmpty)
        XCTAssertTrue(closeResults.all.isEmpty)
        creationDelivery.deliver()
        closeDelivery.deliver()
        XCTAssertEqual(createdResults.all, [.failure(.unavailable)])
        XCTAssertEqual(closeResults.all, [.failure(.closed)])
    }

    func testRejectedStopBatchCannotReadmitItsLaterClaimedWaiterAsANewMarker() async throws {
        let mailbox = runningMailbox(stopWaiters: 2)
        let results = NativeMailboxTestValues<Result<Win32NativePumpExit, NativeWindowOwnerFailure>>()
        let later = NativeWindowReply<Win32NativePumpExit> { results.append($0) }
        let claims = NativeMailboxTestValues<Bool>()
        mailbox.requestStop(
            NativeWindowReply { _ in
                claims.append(later.isCompleted)
                mailbox.requestStop(later)
            })
        mailbox.requestStop(later)
        mailbox.consumeWake()
        XCTAssertEqual(next(mailbox), .stop)
        mailbox.rejectStop(.closing)
        XCTAssertEqual(claims.all, [true])
        XCTAssertEqual(results.all, [.failure(.closing)])
        XCTAssertEqual(mailbox.snapshot.stopWaiters, 0)
        XCTAssertFalse(mailbox.snapshot.hasStopReservation)
        XCTAssertNil(next(mailbox))
    }

    func testAlreadyClaimedStartReplyCannotLaunchAnOwner() async throws {
        let poster = NativeMailboxTestPoster()
        let mailbox = Win32NativePumpMailbox(post: { poster.post($0) })
        let results = NativeMailboxTestValues<NativeWindowOwnerFailure>()
        let reply = NativeWindowReply<Void> { result in
            if case .failure(let failure) = result { results.append(failure) }
        }
        let delivery = try XCTUnwrap(reply.prepareCompletion(.failure(.unavailable)))
        XCTAssertFalse(mailbox.requestStart(reply))
        XCTAssertEqual(mailbox.snapshot.startWaiters, 0)
        XCTAssertTrue(results.all.isEmpty)
        delivery.deliver()
        XCTAssertEqual(results.all, [.unavailable])
        XCTAssertTrue(poster.handles.isEmpty)
    }

    private func checkTerminalOwnerBatch(
        terminal: @MainActor (Win32NativePumpMailbox) -> Void,
        expected: NativeWindowOwnerFailure
    ) throws {
        let mailbox = runningMailbox(commands: 1)
        let results = NativeMailboxTestValues<Result<Int, NativeWindowOwnerFailure>>()
        let item = command(results: results)
        XCTAssertEqual(mailbox.submit(.command(item)), .accepted)
        let attemptedOverrides = NativeMailboxTestValues<Bool>()
        mailbox.requestStop(
            NativeWindowReply { _ in attemptedOverrides.append(item.reply.complete(.success(53))) })
        terminal(mailbox)
        XCTAssertEqual(attemptedOverrides.all, [false], "Earlier stop callbacks cannot win a later command's result")
        XCTAssertEqual(results.all, [.failure(expected)])
        XCTAssertEqual(mailbox.snapshot.queuedWork, 0)
    }

    func testOwnerFailureClaimsQueuedResultsBeforeStopCallbacks() async throws {
        let failure = NativeWindowOwnerFailure.execution("controlled owner failure")
        try checkTerminalOwnerBatch(terminal: { $0.failOwner(failure) }, expected: failure)
    }

    func testJoinClaimsQueuedResultsBeforeStopCallbacks() async throws {
        try checkTerminalOwnerBatch(
            terminal: { $0.didJoin(.success(Win32NativePumpExit(exitCode: 0, joined: true))) }, expected: .ownerStopped)
    }

    func testStartupFailureClaimsQueuedResultsBeforeStopCallbacks() async throws {
        let failure = NativeWindowOwnerFailure.execution("controlled failure after startup publication")
        try checkTerminalOwnerBatch(terminal: { $0.didFailToStart(failure) }, expected: failure)
    }

    func testDidStartClaimsEveryWaiterBeforeTheFirstCallback() async throws {
        let poster = NativeMailboxTestPoster()
        let mailbox = Win32NativePumpMailbox(post: { poster.post($0) })
        let events = NativeMailboxTestValues<String>()
        let later = NativeWindowReply<Void> { result in
            if case .success = result {
                events.append("started")
            } else {
                events.append("overwritten")
            }
        }
        let attempts = NativeMailboxTestValues<Bool>()
        XCTAssertTrue(
            mailbox.requestStart(NativeWindowReply { _ in attempts.append(later.complete(.failure(.unavailable))) }))
        XCTAssertFalse(mailbox.requestStart(later))
        mailbox.didStart(controlHandle: 42)
        XCTAssertEqual(attempts.all, [false])
        XCTAssertEqual(events.all, ["started"])
    }

    func testClosePhaseClaimRetiresReservationEvenWhenItsReplyWasAlreadyClaimed() async throws {
        let poster = NativeMailboxTestPoster()
        let mailbox = runningMailbox(poster: poster)
        let key = NativeWindowKey()
        XCTAssertTrue(mailbox.registerOwnedWindow(key))
        let results = NativeMailboxTestValues<Result<Win32NativeCloseDestruction, NativeWindowOwnerFailure>>()
        let request = close(key: key, results: results)
        XCTAssertEqual(mailbox.submit(.close(request)), .accepted)
        mailbox.consumeWake()
        XCTAssertEqual(next(mailbox), .close(key))
        XCTAssertTrue(mailbox.registerClose(request))
        let delivery = try XCTUnwrap(request.reply.prepareCompletion(.failure(.closed)))
        XCTAssertFalse(request.isTerminal)
        let failure = postFailure
        poster.onCall(2) { .failure(failure) }
        if case .success = mailbox.signal() { XCTFail("The controlled post must fail") }
        XCTAssertTrue(request.isTerminal)
        XCTAssertEqual(mailbox.snapshot.reservedCloses, 0)
        XCTAssertTrue(results.all.isEmpty)
        XCTAssertEqual(mailbox.submit(.close(close(key: key))), .accepted)
        delivery.deliver()
        XCTAssertEqual(results.all, [.failure(.closed)])
    }

    func testBatchPayloadReleaseCanReenterOnlyAfterAllOriginalRepliesAreClaimed() async throws {
        let poster = NativeMailboxTestPoster()
        let mailbox = runningMailbox(commands: 2, poster: poster)
        let events = NativeMailboxTestValues<String>()
        let admissions = NativeMailboxTestValues<NativeWindowSubmission>()
        let snapshots = NativeMailboxTestValues<Int>()
        let replacement = command()
        let failure = postFailure
        poster.onCall(1) {
            let probe = NativeMailboxTestReleaseProbe {
                events.append("released")
                snapshots.append(mailbox.snapshot.queuedWork)
                admissions.append(mailbox.submit(.command(replacement)))
            }
            let later = NativeMailboxTestInspectedCommand(
                reply: NativeWindowReply { _ in events.append("later.reply") }, probe: probe)
            admissions.append(mailbox.submit(.command(later)))
            return .failure(failure)
        }
        let first = NativeMailboxTestCommand(reply: NativeWindowReply { _ in events.append("first.reply") })
        XCTAssertEqual(mailbox.submit(.command(first)), .rejected(failure))
        XCTAssertEqual(events.all, ["first.reply", "later.reply", "released"])
        XCTAssertEqual(snapshots.all, [0])
        XCTAssertEqual(admissions.all, [.accepted, .accepted])
        XCTAssertEqual(next(mailbox), .command(replacement.requestID))
        XCTAssertNil(next(mailbox))
    }
}
