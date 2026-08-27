/// Identifies GPU work independently of the later frame that collects its
/// timing result. A device replacement must never reuse its generation.
public struct BackendFrameID: Hashable, Sendable {
    public var deviceGeneration: UInt64
    public var frameNumber: UInt64

    public init(deviceGeneration: UInt64, frameNumber: UInt64) {
        self.deviceGeneration = deviceGeneration
        self.frameNumber = frameNumber
    }
}

/// A successful native submission is not an acknowledgement of display
/// completion. Offscreen draws have no native presentation at all.
public enum BackendFrameSubmissionOutcome: String, Sendable {
    case submitted
    case offscreen
    case skipped
    case occluded
    case aborted
    case failed
}

public enum GPUFrameTimingStatus: String, Sendable {
    case disabled
    case unsupported
    case notIssued
    case pending
    case valid
    case ringFull
    case disjoint
    case invalidResult
    case aborted
    case deviceLost
    case failed
    case cancelled
}

/// Replaced at the beginning of every render attempt, including attempts
/// that return without drawing. An ID is present only for identified work.
public struct BackendFrameSubmission: Equatable, Sendable {
    public var id: BackendFrameID?
    public var outcome: BackendFrameSubmissionOutcome
    public var gpuTimingStatus: GPUFrameTimingStatus
    /// Cached classification of the device that issued this attempt. Nil
    /// when unavailable; a later device's diagnostics must not fill it in.
    public var adapterIsSoftware: Bool?

    public init(
        id: BackendFrameID? = nil,
        outcome: BackendFrameSubmissionOutcome,
        gpuTimingStatus: GPUFrameTimingStatus = .disabled,
        adapterIsSoftware: Bool? = nil
    ) {
        self.id = id
        self.outcome = outcome
        self.gpuTimingStatus = gpuTimingStatus
        self.adapterIsSoftware = adapterIsSoftware
    }
}

/// One terminal result for the issuing frame. Seconds are available only
/// for a valid interval; they are GPU elapsed time between commands, not
/// exclusive GPU utilization, CPU Present time or display completion.
public struct GPUFrameTimingResult: Equatable, Sendable {
    public var frameID: BackendFrameID
    public var status: GPUFrameTimingStatus
    public var elapsedSeconds: Double?
    public var failureCode: Int32?

    public init(
        frameID: BackendFrameID,
        status: GPUFrameTimingStatus,
        elapsedSeconds: Double? = nil,
        failureCode: Int32? = nil
    ) {
        self.frameID = frameID
        self.status = status
        self.elapsedSeconds = elapsedSeconds
        self.failureCode = failureCode
    }
}

/// Bounded collector health. Counts describe the collector lifetime, not a
/// warmup-filtered performance population. The latter joins issuing frames.
public struct GPUFrameTimingDiagnostics: Equatable, Sendable {
    public var isEnabled: Bool
    public var isSupported: Bool
    public var slotCapacity: Int
    public var resultCapacity: Int
    public var maximumGetDataCallsPerPoll: Int
    public var pendingCount: Int
    public var droppedResultCount: UInt64
    public var failureCode: Int32?

    public init(
        isEnabled: Bool,
        isSupported: Bool,
        slotCapacity: Int = 8,
        resultCapacity: Int = 16,
        maximumGetDataCallsPerPoll: Int = 24,
        pendingCount: Int = 0,
        droppedResultCount: UInt64 = 0,
        failureCode: Int32? = nil
    ) {
        self.isEnabled = isEnabled
        self.isSupported = isSupported
        self.slotCapacity = slotCapacity
        self.resultCapacity = resultCapacity
        self.maximumGetDataCallsPerPoll = maximumGetDataCallsPerPoll
        self.pendingCount = pendingCount
        self.droppedResultCount = droppedResultCount
        self.failureCode = failureCode
    }
}
