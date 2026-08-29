import Foundation
import SwiftWindowsCore
import Synchronization
import WinSDK

/// Bounded copied work for the native owner. Ordinary work, separate built-in
/// close/wake budgets for each owned lifetime, final closes and one stop
/// marker share a single FIFO. Every accepted command keeps its own reply.
/// A dequeued ordinary command belongs to the native executor, not to this
/// mailbox: a later transport failure cannot replace its actual result.
final class Win32NativePumpMailbox: Sendable {
    struct Limits: Sendable {
        let commands: Int
        let controlCommands: Int
        let startWaiters: Int
        let stopWaiters: Int

        init(commands: Int = 128, controlCommands: Int = 32, startWaiters: Int = 32, stopWaiters: Int = 32) {
            precondition(commands >= 0 && controlCommands > 0 && startWaiters > 0 && stopWaiters > 0)
            self.commands = commands
            self.controlCommands = controlCommands
            self.startWaiters = startWaiters
            self.stopWaiters = stopWaiters
        }

        fileprivate func queueCapacity(ownedWindows: Int) -> Int {
            commands + (2 * controlCommands + 1) * ownedWindows + 1
        }
    }

    struct Snapshot: Equatable, Sendable {
        let queuedWork: Int
        let queuedCommands: Int
        let queuedCloseRequests: Int
        let queuedDeferredCloseWakes: Int
        let storageCapacity: Int
        let ownedWindows: Int
        let reservedCloses: Int
        let startWaiters: Int
        let stopWaiters: Int
        let hasStopReservation: Bool
    }

    private enum Phase: Sendable {
        case unstarted
        case starting
        case running(UInt)
        case stopping(UInt)
        case failed(NativeWindowOwnerFailure)
        case stopped(Result<Win32NativePumpExit, NativeWindowOwnerFailure>)
    }

    private struct QueuedWork: Sendable {
        let id: Foundation.UUID
        let work: Win32NativePumpWork
        let control: ControlKey?
        let ownedReply: OwnedReply?

        init(
            id: Foundation.UUID, work: Win32NativePumpWork, control: ControlKey? = nil,
            ownedReply: OwnedReply? = nil
        ) {
            self.id = id
            self.work = work
            self.control = control
            self.ownedReply = ownedReply
        }
    }

    private enum ControlKind: Hashable, Sendable {
        case closeRequest
        case deferredCloseWake

        var capacityResource: String {
            switch self {
            case .closeRequest: return "nativeCloseRequests"
            case .deferredCloseWake: return "nativeDeferredCloseWakes"
            }
        }
    }

    private struct ControlKey: Hashable, Sendable {
        let windowKey: NativeWindowKey
        let kind: ControlKind
    }

    /// Arbitrary command metadata is captured before locking. The capability
    /// itself is a final Core type constructed only from a real reply, so its
    /// claim/completed operations cannot call user code under this mutex.
    private struct OwnedReply: Sendable {
        let requestID: NativeWindowRequestID?
        let capability: NativeWindowCommandReply
    }

    /// Slots are reused immediately on dequeue. Its slot count is exactly
    /// the ordinary limit plus both control budgets and one final-close slot
    /// per current owned lifetime, plus one stop;
    /// neither a drained prefix nor previously owned windows accumulate.
    private struct WorkQueue: Sendable {
        private var slots: [QueuedWork?]
        private var head = 0
        private(set) var count = 0

        init(capacity: Int) {
            slots = Array(repeating: nil, count: capacity)
        }

        var capacity: Int { slots.count }
        var isEmpty: Bool { count == 0 }

        mutating func append(_ item: QueuedWork) {
            precondition(count < slots.count)
            slots[(head + count) % slots.count] = item
            count += 1
        }

        mutating func takeNext() -> QueuedWork? {
            guard count > 0 else { return nil }
            let item = slots[head]
            // The returned item retains its payload before the slot is
            // cleared, so no arbitrary payload deinitializer runs here.
            slots[head] = nil
            head = (head + 1) % slots.count
            count -= 1
            return item
        }

        mutating func remove(id: Foundation.UUID) -> QueuedWork? {
            var removed: QueuedWork?
            let originalCount = count
            for _ in 0..<originalCount {
                guard let item = takeNext() else { break }
                if item.id == id {
                    removed = item
                } else {
                    append(item)
                }
            }
            return removed
        }

        mutating func takeAll() -> [QueuedWork] {
            var items: [QueuedWork] = []
            items.reserveCapacity(count)
            while let item = takeNext() { items.append(item) }
            return items
        }

        mutating func takeControls(for key: NativeWindowKey) -> [QueuedWork] {
            var removed: [QueuedWork] = []
            let originalCount = count
            for _ in 0..<originalCount {
                guard let item = takeNext() else { break }
                if item.control?.windowKey == key {
                    removed.append(item)
                } else {
                    append(item)
                }
            }
            return removed
        }

        func ownsReply(_ identity: ObjectIdentifier) -> Bool {
            for offset in 0..<count {
                if slots[(head + offset) % slots.count]?.ownedReply?.capability.identity == identity { return true }
            }
            return false
        }

        func ownsRequest(_ requestID: NativeWindowRequestID) -> Bool {
            for offset in 0..<count {
                if slots[(head + offset) % slots.count]?.ownedReply?.requestID == requestID { return true }
            }
            return false
        }

        mutating func resize(capacity: Int) {
            guard capacity != slots.count else { return }
            precondition(capacity >= count)
            var replacement = WorkQueue(capacity: capacity)
            while let item = takeNext() { replacement.append(item) }
            self = replacement
        }
    }

    private struct CloseReservation: Sendable {
        let id: Foundation.UUID
        let request: Win32NativeDestructionRequest
    }

    private struct StopReservation: Sendable {
        enum Stage: Sendable {
            case queued
            case dequeued
            case committed
        }

        let id: Foundation.UUID
        var stage: Stage
        var replies: [NativeWindowReply<Win32NativePumpExit>]
    }

    private struct WakeRoute: Sendable {
        let handle: UInt
        let token: Foundation.UUID
    }

    /// A bounded detached batch, never a registry. Claims are committed while
    /// queue ownership is locked; all deliveries and retained payloads leave
    /// that lock together. Reentrant submission sees a completed real reply,
    /// even when its callback is later in this batch and has not run yet.
    private struct PreparedBatch: Sendable {
        var deliveries: [NativeWindowReplyDelivery] = []
        var work: [QueuedWork] = []
        var closes: [CloseReservation] = []
        var starts: [NativeWindowReply<Void>] = []
        var stop: StopReservation?
        var retiredReply: OwnedReply?

        mutating func append(_ delivery: NativeWindowReplyDelivery?) {
            if let delivery { deliveries.append(delivery) }
        }

        func deliver() {
            for delivery in deliveries { delivery.deliver() }
            withExtendedLifetime(self) {}
        }
    }

    private struct State: Sendable {
        var phase: Phase = .unstarted
        var queue: WorkQueue
        var queuedCommands = 0
        var controlCounts: [ControlKey: Int] = [:]
        // Only a reply identity is retained for the single last-dequeued
        // operation. No queued budget remains reserved and no failure path
        // completes it. N retires it at its next serial dequeue, or join.
        var executingReply: OwnedReply?
        var wakeToken: Foundation.UUID?
        var starts: [NativeWindowReply<Void>] = []
        var stop: StopReservation?
        var ownedWindows: Set<NativeWindowKey> = []
        var closes: [NativeWindowKey: CloseReservation] = [:]
        var loopFailure: NativeWindowOwnerFailure?

        init(commandLimit: Int) {
            queue = WorkQueue(capacity: commandLimit + 1)
        }

        mutating func reserveWake(handle: UInt) -> WakeRoute? {
            guard wakeToken == nil else { return nil }
            let token = Foundation.UUID()
            wakeToken = token
            return WakeRoute(handle: handle, token: token)
        }

        /// Callers must prepare every result before releasing this same lock.
        /// Final-close reservations retire only if their phase claim wins.
        mutating func takeQueued() -> [QueuedWork] {
            let items = queue.takeAll()
            queuedCommands = 0
            controlCounts = [:]
            return items
        }

        func ownsReply(_ identity: ObjectIdentifier) -> Bool {
            queue.ownsReply(identity) || executingReply?.capability.identity == identity
                || closes.values.contains { ObjectIdentifier($0.request.reply) == identity }
                || starts.contains { ObjectIdentifier($0) == identity }
                || (stop?.replies.contains { ObjectIdentifier($0) == identity } ?? false)
        }

        func ownsRequest(_ requestID: NativeWindowRequestID) -> Bool {
            queue.ownsRequest(requestID) || executingReply?.requestID == requestID
        }

        mutating func prepareFailure(_ item: QueuedWork, failure: NativeWindowOwnerFailure)
            -> NativeWindowReplyDelivery?
        {
            switch item.work {
            case .create(let creation): return creation.reply.prepareCompletion(.failure(failure))
            case .command:
                guard let reply = item.ownedReply else {
                    preconditionFailure("An admitted command must own its reply capability")
                }
                return reply.capability.prepareFailure(failure)
            case .close(let request): return prepareCloseFailure(request, failure: failure)
            case .stop: return nil
            }
        }

        mutating func prepareCloseFailure(
            _ request: Win32NativeDestructionRequest, failure: NativeWindowOwnerFailure
        ) -> NativeWindowReplyDelivery? {
            let prepared = request.prepareCompletion(.failure(failure))
            if prepared.didClaim, closes[request.key]?.request === request { closes.removeValue(forKey: request.key) }
            return prepared.delivery
        }

        mutating func prepareQueuedAndCloseFailures(
            _ failure: NativeWindowOwnerFailure, into batch: inout PreparedBatch
        ) {
            batch.work = takeQueued()
            for item in batch.work { batch.append(prepareFailure(item, failure: failure)) }
            batch.closes = Array(closes.values)
            for close in batch.closes { batch.append(prepareCloseFailure(close.request, failure: failure)) }
        }

        mutating func retireQueuedControl(_ key: ControlKey) {
            guard let count = controlCounts[key] else { return }
            if count == 1 {
                controlCounts.removeValue(forKey: key)
            } else {
                controlCounts[key] = count - 1
            }
        }

        func queuedControlCount(_ kind: ControlKind) -> Int {
            controlCounts.reduce(0) { count, entry in count + (entry.key.kind == kind ? entry.value : 0) }
        }
    }

    private let limits: Limits
    private let postWake: @Sendable (UInt) -> Result<Void, NativeWindowOwnerFailure>
    private let state: Mutex<State>

    /// The injected poster and smaller limits are internal test seams. The
    /// production pump uses these same paths with the public Win32 post API.
    init(
        limits: Limits = Limits(),
        post: @escaping @Sendable (UInt) -> Result<Void, NativeWindowOwnerFailure> = {
            handle in
            guard let hwnd = HWND(bitPattern: handle) else { return .failure(.unavailable) }
            if PostMessageW(hwnd, win32NativeWakeMessage, 0, 0) { return .success(()) }
            return .failure(.postFailed(code: GetLastError()))
        }
    ) {
        self.limits = limits
        postWake = post
        state = Mutex(State(commandLimit: limits.commands))
    }

    var snapshot: Snapshot {
        state.withLock { stored in
            Snapshot(
                queuedWork: stored.queue.count, queuedCommands: stored.queuedCommands,
                queuedCloseRequests: stored.queuedControlCount(.closeRequest),
                queuedDeferredCloseWakes: stored.queuedControlCount(.deferredCloseWake),
                storageCapacity: stored.queue.capacity, ownedWindows: stored.ownedWindows.count,
                reservedCloses: stored.closes.count, startWaiters: stored.starts.count,
                stopWaiters: stored.stop?.replies.count ?? 0, hasStopReservation: stored.stop != nil)
        }
    }

    func requestStart(_ reply: NativeWindowReply<Void>) -> Bool {
        let result: (launch: Bool, delivery: NativeWindowReplyDelivery?) = state.withLock { stored in
            guard !reply.isCompleted, !stored.ownsReply(ObjectIdentifier(reply)) else { return (false, nil) }
            switch stored.phase {
            case .unstarted:
                stored.phase = .starting
                stored.starts.append(reply)
                return (true, nil)
            case .starting:
                guard stored.starts.count < limits.startWaiters else {
                    return (
                        false,
                        reply.prepareCompletion(
                            .failure(.capacityExceeded(resource: "nativeStartWaiters", limit: limits.startWaiters)))
                    )
                }
                stored.starts.append(reply)
                return (false, nil)
            case .running:
                return (false, reply.prepareCompletion(.success(())))
            case .stopping, .stopped:
                return (false, reply.prepareCompletion(.failure(.ownerStopped)))
            case .failed(let failure):
                return (false, reply.prepareCompletion(.failure(failure)))
            }
        }
        result.delivery?.deliver()
        return result.launch
    }

    func didStart(controlHandle: UInt) {
        let batch = state.withLock { stored -> PreparedBatch in
            guard case .starting = stored.phase else { return PreparedBatch() }
            stored.phase = .running(controlHandle)
            var batch = PreparedBatch()
            batch.starts = stored.starts
            stored.starts = []
            for reply in batch.starts { batch.append(reply.prepareCompletion(.success(()))) }
            return batch
        }
        batch.deliver()
    }

    func didFailToStart(_ failure: NativeWindowOwnerFailure) {
        let batch = state.withLock { stored in
            var batch = PreparedBatch()
            batch.starts = stored.starts
            batch.stop = stored.stop
            stored.starts = []
            stored.stop = nil
            stored.wakeToken = nil
            stored.phase = .stopped(.failure(failure))
            stored.loopFailure = failure
            for reply in batch.starts { batch.append(reply.prepareCompletion(.failure(failure))) }
            for reply in batch.stop?.replies ?? [] { batch.append(reply.prepareCompletion(.failure(failure))) }
            stored.prepareQueuedAndCloseFailures(failure, into: &batch)
            return batch
        }
        batch.deliver()
    }

    /// Called by N when it takes actual ownership, before native creation
    /// can call out. Merely submitting .create does not reserve close space.
    @discardableResult
    func registerOwnedWindow(_ key: NativeWindowKey) -> Bool {
        state.withLock { stored in
            guard case .running = stored.phase, !stored.ownedWindows.contains(key) else { return false }
            stored.ownedWindows.insert(key)
            stored.queue.resize(capacity: limits.queueCapacity(ownedWindows: stored.ownedWindows.count))
            return true
        }
    }

    /// Only actual native release or safe creation rollback retires a key.
    /// Any close still waiting in the FIFO loses its reservation before its
    /// callback can attempt admission for this now-stale lifetime.
    func retireOwnedWindow(_ key: NativeWindowKey) {
        let batch = state.withLock { stored -> PreparedBatch in
            guard stored.ownedWindows.remove(key) != nil else { return PreparedBatch() }
            var batch = PreparedBatch()
            if let reservation = stored.closes[key] {
                batch.closes.append(reservation)
                if let item = stored.queue.remove(id: reservation.id) { batch.work.append(item) }
                batch.append(stored.prepareCloseFailure(reservation.request, failure: .staleWindow))
            }
            let controls = stored.queue.takeControls(for: key)
            batch.work.append(contentsOf: controls)
            for item in controls {
                if let key = item.control { stored.retireQueuedControl(key) }
                batch.append(stored.prepareFailure(item, failure: .staleWindow))
            }
            stored.queue.resize(capacity: limits.queueCapacity(ownedWindows: stored.ownedWindows.count))
            return batch
        }
        batch.deliver()
    }

    @discardableResult
    func submit(_ work: Win32NativePumpWork) -> NativeWindowSubmission {
        let id = Foundation.UUID()
        // All arbitrary protocol getters run before locking, exactly once.
        // Only the concrete module-owned operation value can use a control
        // budget; other commands still use the ordinary FIFO capacity.
        let ownedReply: OwnedReply?
        let control: ControlKey?
        switch work {
        case .create(let creation):
            ownedReply = OwnedReply(requestID: nil, capability: creation.reply.commandReply)
            control = nil
        case .command(let command):
            let requestID = command.requestID
            let capability = command.commandReply
            ownedReply = OwnedReply(requestID: requestID, capability: capability)
            if let native = command as? Win32NativeWindowOperationCommand {
                switch native.operation {
                case .requestClose: control = ControlKey(windowKey: native.windowKey, kind: .closeRequest)
                case .deferredCloseWake: control = ControlKey(windowKey: native.windowKey, kind: .deferredCloseWake)
                default: control = nil
                }
            } else {
                control = nil
            }
        case .close(let request):
            ownedReply = OwnedReply(requestID: nil, capability: request.reply.commandReply)
            control = nil
        case .stop:
            ownedReply = nil
            control = nil
        }
        let item = QueuedWork(id: id, work: work, control: control, ownedReply: ownedReply)
        defer { withExtendedLifetime(item) {} }
        let decision: (failure: NativeWindowOwnerFailure?, delivery: NativeWindowReplyDelivery?, route: WakeRoute?) =
            state.withLock {
                stored in
                let duplicateFailure: NativeWindowOwnerFailure
                if let control, !stored.ownedWindows.contains(control.windowKey) {
                    duplicateFailure = .staleWindow
                } else if case .close(let request) = work, !stored.ownedWindows.contains(request.key) {
                    duplicateFailure = .staleWindow
                } else {
                    duplicateFailure = .closing
                }
                if let ownedReply {
                    if ownedReply.capability.isCompleted || stored.ownsReply(ownedReply.capability.identity) {
                        // The same reply is not a fresh observer. This includes
                        // replies claimed by a detached batch whose callbacks
                        // have not yet reached this item. Never readmit effects.
                        return (duplicateFailure, nil, nil)
                    }
                    if let requestID = ownedReply.requestID, stored.ownsRequest(requestID) {
                        // A duplicate ID with a different reply does own a new
                        // observer; reject that observer without altering the
                        // original queued/executing reply.
                        return (duplicateFailure, stored.prepareFailure(item, failure: duplicateFailure), nil)
                    }
                }
                if case .close(let request) = work, request.isTerminal {
                    return (duplicateFailure, nil, nil)
                }
                guard case .running(let handle) = stored.phase else {
                    let failure: NativeWindowOwnerFailure
                    if case .failed(let ownerFailure) = stored.phase {
                        failure = ownerFailure
                    } else {
                        failure = .ownerStopped
                    }
                    return (failure, stored.prepareFailure(item, failure: failure), nil)
                }
                switch work {
                case .create, .command:
                    if let control {
                        guard stored.ownedWindows.contains(control.windowKey) else {
                            return (.staleWindow, stored.prepareFailure(item, failure: .staleWindow), nil)
                        }
                        guard (stored.controlCounts[control] ?? 0) < limits.controlCommands else {
                            let failure = NativeWindowOwnerFailure.capacityExceeded(
                                resource: control.kind.capacityResource, limit: limits.controlCommands)
                            return (failure, stored.prepareFailure(item, failure: failure), nil)
                        }
                        stored.controlCounts[control, default: 0] += 1
                    } else {
                        guard stored.queuedCommands < limits.commands else {
                            let failure = NativeWindowOwnerFailure.capacityExceeded(
                                resource: "nativeCommandQueue", limit: limits.commands)
                            return (failure, stored.prepareFailure(item, failure: failure), nil)
                        }
                        stored.queuedCommands += 1
                    }
                case .close(let request):
                    guard stored.ownedWindows.contains(request.key) else {
                        return (.staleWindow, stored.prepareFailure(item, failure: .staleWindow), nil)
                    }
                    if stored.closes[request.key] != nil {
                        return (.closing, stored.prepareFailure(item, failure: .closing), nil)
                    }
                    stored.closes[request.key] = CloseReservation(id: id, request: request)
                case .stop:
                    // Only requestStop may install a marker, together with its
                    // bounded waiters under this same lock.
                    return (.execution("Native stop admission requires requestStop"), nil, nil)
                }
                stored.queue.append(item)
                return (nil, nil, stored.reserveWake(handle: handle))
            }
        if let failure = decision.failure {
            decision.delivery?.deliver()
            return .rejected(failure)
        }
        guard let route = decision.route else { return .accepted }
        switch postWake(route.handle) {
        case .success:
            return .accepted
        case .failure(let failure):
            let rejected = failWake(token: route.token, failure: failure)
            return rejected.contains(id) ? .rejected(failure) : .accepted
        }
    }

    func signal() -> Result<Void, NativeWindowOwnerFailure> {
        let route: Result<WakeRoute, NativeWindowOwnerFailure> = state.withLock { stored in
            let handle: UInt
            switch stored.phase {
            case .running(let value), .stopping(let value): handle = value
            case .failed(let failure): return .failure(failure)
            default: return .failure(.ownerStopped)
            }
            if let token = stored.wakeToken { return .success(WakeRoute(handle: handle, token: token)) }
            let token = Foundation.UUID()
            stored.wakeToken = token
            return .success(WakeRoute(handle: handle, token: token))
        }
        switch route {
        case .failure(let failure):
            return .failure(failure)
        case .success(let destination):
            // A drain notification must still post when ordinary work owns
            // a wake. A failed old post may reject only its own wake epoch.
            let result = postWake(destination.handle)
            if case .failure(let failure) = result { _ = failWake(token: destination.token, failure: failure) }
            return result
        }
    }

    private func failWake(token: Foundation.UUID, failure: NativeWindowOwnerFailure) -> Set<Foundation.UUID> {
        let batch = state.withLock { stored -> PreparedBatch in
            guard stored.wakeToken == token else { return PreparedBatch() }
            stored.wakeToken = nil
            var batch = PreparedBatch()
            stored.prepareQueuedAndCloseFailures(failure, into: &batch)
            if let pending = stored.stop, case .queued = pending.stage {
                batch.stop = pending
                stored.stop = nil
                for reply in pending.replies { batch.append(reply.prepareCompletion(.failure(failure))) }
            }
            // A stop already consumed by N keeps its actual result path.
            // All queued/pending results above are claimed before unlocking.
            return batch
        }
        batch.deliver()
        return Set(batch.work.map(\.id))
    }

    func consumeWake() {
        state.withLock { $0.wakeToken = nil }
    }

    func takeNext() -> Win32NativePumpWork? {
        let taken = state.withLock { stored -> (Win32NativePumpWork?, OwnedReply?) in
            // N calls takeNext only after the preceding synchronous command
            // returned. Transfer this last pin outside the lock before ARC
            // can release any callback captures retained by its reply cell.
            let previousIdentity = stored.executingReply
            stored.executingReply = nil
            guard let item = stored.queue.takeNext() else { return (nil, previousIdentity) }
            switch item.work {
            case .create, .command:
                if let control = item.control {
                    stored.retireQueuedControl(control)
                } else {
                    stored.queuedCommands -= 1
                }
                stored.executingReply = item.ownedReply
            case .close:
                break
            case .stop:
                precondition(stored.stop?.id == item.id)
                stored.stop?.stage = .dequeued
            }
            return (item.work, previousIdentity)
        }
        withExtendedLifetime(taken.1) {}
        return taken.0
    }

    var hasQueuedWork: Bool { state.withLock { !$0.queue.isEmpty } }

    /// Native adoption verifies an admission; it never creates a second
    /// reservation or accepts a close for an unregistered lifetime.
    @discardableResult
    func registerClose(_ request: Win32NativeDestructionRequest) -> Bool {
        state.withLock { stored in
            stored.ownedWindows.contains(request.key) && stored.closes[request.key]?.request === request
        }
    }

    func retireClose(_ request: Win32NativeDestructionRequest) {
        let removed = state.withLock { stored -> (CloseReservation?, QueuedWork?) in
            guard stored.closes[request.key]?.request === request else { return (nil, nil) }
            let reservation = stored.closes.removeValue(forKey: request.key)
            let item = reservation.flatMap { stored.queue.remove(id: $0.id) }
            return (reservation, item)
        }
        withExtendedLifetime(removed) {}
    }

    func requestStop(_ reply: NativeWindowReply<Win32NativePumpExit>) {
        let decision: (delivery: NativeWindowReplyDelivery?, route: WakeRoute?) =
            state.withLock { stored in
                guard !reply.isCompleted, !stored.ownsReply(ObjectIdentifier(reply)) else { return (nil, nil) }
                let handle: UInt
                let alreadyStopping: Bool
                switch stored.phase {
                case .stopped(let result): return (reply.prepareCompletion(result), nil)
                case .failed(let failure): return (reply.prepareCompletion(.failure(failure)), nil)
                case .unstarted, .starting: return (reply.prepareCompletion(.failure(.unavailable)), nil)
                case .stopping(let value):
                    handle = value
                    alreadyStopping = true
                case .running(let value):
                    handle = value
                    alreadyStopping = false
                }
                if let stop = stored.stop {
                    guard stop.replies.count < limits.stopWaiters else {
                        return (
                            reply.prepareCompletion(
                                .failure(.capacityExceeded(resource: "nativeStopWaiters", limit: limits.stopWaiters))),
                            nil
                        )
                    }
                    stored.stop?.replies.append(reply)
                    return (nil, nil)
                }
                let id = Foundation.UUID()
                stored.stop = StopReservation(
                    id: id, stage: alreadyStopping ? .committed : .queued, replies: [reply])
                guard !alreadyStopping else { return (nil, nil) }
                stored.queue.append(QueuedWork(id: id, work: .stop))
                return (nil, stored.reserveWake(handle: handle))
            }
        decision.delivery?.deliver()
        if let route = decision.route, case .failure(let failure) = postWake(route.handle) {
            _ = failWake(token: route.token, failure: failure)
        }
    }

    func rejectStop(_ failure: NativeWindowOwnerFailure) {
        let batch = state.withLock { stored -> PreparedBatch in
            // After willStop, only the actual join or owner failure may
            // complete stop. A rejection cannot undo an issued quit.
            guard case .running = stored.phase, let stop = stored.stop else { return PreparedBatch() }
            var batch = PreparedBatch()
            batch.stop = stop
            stored.stop = nil
            if let item = stored.queue.remove(id: stop.id) { batch.work.append(item) }
            for reply in stop.replies { batch.append(reply.prepareCompletion(.failure(failure))) }
            return batch
        }
        batch.deliver()
    }

    func willStop() {
        state.withLock { stored in
            guard case .running(let handle) = stored.phase,
                let stop = stored.stop, case .dequeued = stop.stage
            else { return }
            stored.stop?.stage = .committed
            stored.phase = .stopping(handle)
        }
    }

    func noteLoopFailure(_ failure: NativeWindowOwnerFailure) {
        state.withLock { $0.loopFailure = failure }
    }

    /// Complete owned waiting work before process-fatal parking. Work that
    /// takeNext already transferred to N is absent and is never fabricated.
    func failOwner(_ failure: NativeWindowOwnerFailure) {
        let batch = state.withLock { stored in
            stored.phase = .failed(failure)
            stored.loopFailure = failure
            var batch = PreparedBatch()
            batch.starts = stored.starts
            batch.stop = stored.stop
            stored.starts = []
            stored.stop = nil
            stored.wakeToken = nil
            for reply in batch.starts { batch.append(reply.prepareCompletion(.failure(failure))) }
            for reply in batch.stop?.replies ?? [] { batch.append(reply.prepareCompletion(.failure(failure))) }
            stored.prepareQueuedAndCloseFailures(failure, into: &batch)
            return batch
        }
        batch.deliver()
    }

    func didJoin(_ joined: Result<Win32NativePumpExit, NativeWindowOwnerFailure>) {
        let batch = state.withLock { stored in
            let result =
                stored.loopFailure.map { Result<Win32NativePumpExit, NativeWindowOwnerFailure>.failure($0) } ?? joined
            stored.phase = .stopped(result)
            var batch = PreparedBatch()
            batch.starts = stored.starts
            batch.stop = stored.stop
            batch.retiredReply = stored.executingReply
            stored.starts = []
            stored.stop = nil
            for reply in batch.starts { batch.append(reply.prepareCompletion(.failure(.ownerStopped))) }
            for reply in batch.stop?.replies ?? [] { batch.append(reply.prepareCompletion(result)) }
            stored.prepareQueuedAndCloseFailures(.ownerStopped, into: &batch)
            stored.ownedWindows = []
            stored.queue.resize(capacity: limits.queueCapacity(ownedWindows: 0))
            stored.executingReply = nil
            stored.wakeToken = nil
            return batch
        }
        batch.deliver()
    }
}
