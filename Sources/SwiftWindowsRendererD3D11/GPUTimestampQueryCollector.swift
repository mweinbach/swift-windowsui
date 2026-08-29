import SwiftWindowsGraphics

enum GPUTimestampQueryKind: Equatable {
    case timestamp
    case disjoint
}

/// The collector owns handles; only the transport knows about COM or WinSDK.
/// Keeping HRESULTs intact makes S_FALSE distinguishable from ready data in
/// the deterministic tests as well as in the native implementation.
/// Transport and collector stay on the same renderer execution owner.
protocol GPUTimestampQueryTransport: AnyObject {
    var ownedQueryCount: Int { get }
    func createQuery(_ kind: GPUTimestampQueryKind) -> (hresult: Int32, handle: Int?)
    func releaseQuery(_ handle: Int)
    func beginQuery(_ handle: Int)
    func endQuery(_ handle: Int)
    func readTimestamp(_ handle: Int) -> (hresult: Int32, value: UInt64)
    func readDisjoint(_ handle: Int) -> (hresult: Int32, frequency: UInt64, isDisjoint: Bool)
}

/// Optional elapsed GPU intervals. No path waits for readiness, flushes the
/// context, grows the query pool, or reuses an unresolved query. A caller that
/// stops draining results can lose evidence, but cannot grow memory forever.
/// The collector is not Sendable and never leaves its renderer's owner.
final class D3D11GPUFrameTimingCollector {
    static let slotCapacity = 8
    static let resultCapacity = 16
    static let maximumGetDataCallsPerPoll = 24

    private struct Slot {
        let disjoint: Int
        let start: Int
        let end: Int
        var frameID: BackendFrameID?
        var isOpen = false
        var hasTerminalResult = false
    }

    private var transport: (any GPUTimestampQueryTransport)?
    private var deviceGeneration: UInt64 = 0
    private var isEnabled = false
    private var failureCode: Int32?
    private var failureStatus: GPUFrameTimingStatus?
    private var slots: [Slot] = []
    private var results: [GPUFrameTimingResult] = []
    private var droppedResultCount: UInt64 = 0

    var ownedQueryCount: Int { transport?.ownedQueryCount ?? 0 }

    var diagnostics: GPUFrameTimingDiagnostics {
        GPUFrameTimingDiagnostics(
            isEnabled: isEnabled,
            isSupported: transport != nil && failureStatus == nil && slots.count == Self.slotCapacity,
            slotCapacity: Self.slotCapacity,
            resultCapacity: Self.resultCapacity,
            maximumGetDataCallsPerPoll: Self.maximumGetDataCallsPerPoll,
            pendingCount: slots.filter { $0.frameID != nil }.count,
            droppedResultCount: droppedResultCount,
            failureCode: failureCode)
    }

    /// Status for an attempt that has not issued an interval yet.
    var currentStatus: GPUFrameTimingStatus {
        guard isEnabled else { return .disabled }
        if let failureStatus { return failureStatus }
        guard transport != nil, deviceGeneration != 0 else { return .unsupported }
        return .notIssued
    }

    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        isEnabled = enabled
        if enabled {
            allocateSlotsIfNeeded()
            return diagnostics.isSupported
        }
        invalidateSlots(status: .cancelled)
        // A failed generation remains failed across enable/disable toggles.
        return true
    }

    func attach(transport: any GPUTimestampQueryTransport, deviceGeneration: UInt64) {
        guard deviceGeneration != self.deviceGeneration || self.transport == nil else { return }
        detach()
        guard deviceGeneration != 0 else { return }
        self.transport = transport
        self.deviceGeneration = deviceGeneration
        allocateSlotsIfNeeded()
    }

    /// Called before the renderer releases its context. The request and the
    /// bounded outbox survive so the host can collect cancellation records
    /// after detach, without making another context call.
    func detach(status: GPUFrameTimingStatus = .cancelled) {
        invalidateSlots(status: status)
        transport = nil
        deviceGeneration = 0
        failureCode = nil
        failureStatus = nil
    }

    func beginFrame(_ frameID: BackendFrameID) -> GPUFrameTimingStatus {
        guard isEnabled else { return .disabled }
        if let failureStatus { return failureStatus }
        guard let transport, deviceGeneration != 0 else { return .unsupported }
        guard frameID.deviceGeneration == deviceGeneration else { return .notIssued }
        guard !slots.contains(where: \.isOpen) else { return .notIssued }
        guard !slots.contains(where: { $0.frameID == frameID }) else { return .notIssued }
        guard let index = slots.firstIndex(where: { $0.frameID == nil }) else { return .ringFull }

        slots[index].frameID = frameID
        slots[index].isOpen = true
        slots[index].hasTerminalResult = false
        transport.beginQuery(slots[index].disjoint)
        // Timestamp queries use End only; Begin is for the disjoint bracket.
        transport.endQuery(slots[index].start)
        return .pending
    }

    func endFrame(_ frameID: BackendFrameID) {
        guard let transport,
            let index = slots.firstIndex(where: { $0.frameID == frameID && $0.isOpen })
        else { return }
        transport.endQuery(slots[index].end)
        transport.endQuery(slots[index].disjoint)
        slots[index].isOpen = false
    }

    /// An aborted interval is terminal immediately, but its handles stay
    /// occupied until readiness or detach. Reusing them now would overwrite
    /// GPU work that may still be in flight.
    func abortFrame(
        _ frameID: BackendFrameID,
        status: GPUFrameTimingStatus = .aborted,
        failureCode: Int32? = nil
    ) {
        if status == .deviceLost {
            guard deviceGeneration != 0, frameID.deviceGeneration == deviceGeneration else { return }
            // A removed device cannot complete its bracket. Invalidate all
            // intervals without issuing End on that context, even for an
            // interval whose draw failed before the normal closing calls.
            invalidateSlots(status: status, failureCode: failureCode)
            transport = nil
            deviceGeneration = 0
            self.failureCode = nil
            failureStatus = nil
            return
        }
        endFrame(frameID)
        guard let index = slots.firstIndex(where: { $0.frameID == frameID }),
            !slots[index].hasTerminalResult
        else { return }
        appendResult(GPUFrameTimingResult(frameID: frameID, status: status, failureCode: failureCode))
        slots[index].hasTerminalResult = true
    }

    func takeCompletedResults() -> [GPUFrameTimingResult] {
        poll()
        let completed = results
        results.removeAll(keepingCapacity: true)
        return completed
    }

    private func allocateSlotsIfNeeded() {
        guard isEnabled, failureStatus == nil, slots.isEmpty, let transport else { return }
        var allocated: [Int] = []
        for _ in 0..<Self.slotCapacity {
            var handles: [Int] = []
            for kind in [GPUTimestampQueryKind.disjoint, .timestamp, .timestamp] {
                let created = transport.createQuery(kind)
                guard created.hresult == 0, let handle = created.handle else {
                    // Even a failing COM creation may write an out-parameter.
                    if let handle = created.handle { transport.releaseQuery(handle) }
                    for handle in allocated { transport.releaseQuery(handle) }
                    slots.removeAll(keepingCapacity: true)
                    let code = created.hresult == 0 ? Int32(bitPattern: 0x8000_4003) : created.hresult
                    failureCode = code
                    failureStatus = statusForFailure(code, duringAllocation: true)
                    return
                }
                handles.append(handle)
                allocated.append(handle)
            }
            slots.append(Slot(disjoint: handles[0], start: handles[1], end: handles[2]))
        }
    }

    private func poll() {
        guard isEnabled, failureStatus == nil, let transport else { return }
        // At most three GetData calls for each of eight slots. Never retry a
        // pending result inside this pass, including when other slots finish.
        for index in slots.indices {
            let slot = slots[index]
            guard let frameID = slot.frameID, !slot.isOpen else { continue }
            let disjoint = transport.readDisjoint(slot.disjoint)
            if failIfNeeded(disjoint.hresult) { return }
            guard disjoint.hresult == 0 else { continue }

            let start = transport.readTimestamp(slot.start)
            if failIfNeeded(start.hresult) { return }
            let end = transport.readTimestamp(slot.end)
            if failIfNeeded(end.hresult) { return }
            guard start.hresult == 0, end.hresult == 0 else { continue }

            if !slot.hasTerminalResult {
                let result: GPUFrameTimingResult
                if disjoint.isDisjoint {
                    result = GPUFrameTimingResult(frameID: frameID, status: .disjoint)
                } else if disjoint.frequency == 0 || end.value < start.value {
                    result = GPUFrameTimingResult(frameID: frameID, status: .invalidResult)
                } else {
                    // Subtract integer counters before converting: their
                    // absolute values can be too large for precise Doubles.
                    let seconds = Double(end.value - start.value) / Double(disjoint.frequency)
                    result = GPUFrameTimingResult(frameID: frameID, status: .valid, elapsedSeconds: seconds)
                }
                appendResult(result)
            }
            slots[index].frameID = nil
            slots[index].hasTerminalResult = false
        }
    }

    private func failIfNeeded(_ hresult: Int32) -> Bool {
        guard hresult != 0, hresult != 1 else { return false }
        let status = statusForFailure(hresult, duringAllocation: false)
        failureCode = hresult
        failureStatus = status
        invalidateSlots(status: status, failureCode: hresult)
        return true
    }

    private func statusForFailure(_ code: Int32, duringAllocation: Bool) -> GPUFrameTimingStatus {
        if DeviceLostPolicy.isDeviceLost(code) { return .deviceLost }
        if duringAllocation,
            code == Int32(bitPattern: 0x8000_4001) || code == Int32(bitPattern: 0x887A_0004)
        {
            return .unsupported
        }
        return .failed
    }

    private func invalidateSlots(status: GPUFrameTimingStatus, failureCode: Int32? = nil) {
        guard let transport else { return }
        for slot in slots {
            if slot.isOpen, status != .deviceLost {
                transport.endQuery(slot.end)
                transport.endQuery(slot.disjoint)
            }
            if let frameID = slot.frameID, !slot.hasTerminalResult {
                appendResult(GPUFrameTimingResult(frameID: frameID, status: status, failureCode: failureCode))
            }
            transport.releaseQuery(slot.disjoint)
            transport.releaseQuery(slot.start)
            transport.releaseQuery(slot.end)
        }
        slots.removeAll(keepingCapacity: true)
    }

    private func appendResult(_ result: GPUFrameTimingResult) {
        if results.count == Self.resultCapacity {
            results.removeFirst()
            droppedResultCount &+= 1
        }
        results.append(result)
    }
}
