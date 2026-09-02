import Foundation

#if canImport(SwiftUI)
    import SwiftUI
#else
    import WinSwiftUI
#endif

/// Encoded local inputs, not forced success/error flags. A replacement reader
/// can map these choices to its own local store without changing the chart.
public enum DemoDashboardDataSample: String, CaseIterable, Equatable, Sendable {
    case valid
    case empty
    case malformed

    public var label: String {
        switch self {
        case .valid: return "Valid"
        case .empty: return "Empty"
        case .malformed: return "Malformed"
        }
    }
}

public struct DemoDashboardDataPoint: Equatable, Sendable {
    public let label: String
    /// A normalized sample, before the dashboard's existing activity adjustment.
    public let fraction: Double
}

/// Only the bounded decoder constructs reports. There is no retained raw JSON,
/// history, cache, or unbounded stream of observations in the model.
public struct DemoDashboardReport: Equatable, Sendable {
    public let day: [DemoDashboardDataPoint]
    public let week: [DemoDashboardDataPoint]
    public let all: [DemoDashboardDataPoint]

    public var pointCount: Int { day.count + week.count + all.count }
    public var isEmpty: Bool { pointCount == 0 }
}

public enum DemoDashboardDataError: Error, Equatable, Sendable {
    case busy
    case readFailed
    case encodedDataTooLarge
    case malformedJSON
    case unsupportedVersion
    case tooManyPoints
    case invalidLabel
    case duplicateLabel
    case invalidFraction

    public var message: String {
        switch self {
        case .busy: return "The local reader is still busy."
        case .readFailed: return "The local data could not be read."
        case .encodedDataTooLarge: return "The report exceeds the 16 KiB input limit."
        case .malformedJSON: return "The local data is not a complete dashboard JSON report."
        case .unsupportedVersion: return "The dashboard report version is not supported."
        case .tooManyPoints: return "A report can contain at most 12 samples per range."
        case .invalidLabel: return "Sample labels must be short, nonempty single-line text."
        case .duplicateLabel: return "Sample labels must be unique within each range."
        case .invalidFraction: return "Sample fractions must be finite values from zero through one."
        }
    }
}

/// One actor admits one physical read/decode at a time, with no service queue.
/// The caller's task performs the work on this actor, not on the UI actor. A
/// cancelled read occupies its slot until its awaited reader actually returns.
public actor DemoDashboardDataService {
    public static let maximumEncodedBytes = 16_384
    public static let maximumPointsPerRange = 12
    public static let maximumLabelBytes = 24
    public static let maximumActiveReads = 1

    private let readBytes: @Sendable (DemoDashboardDataSample) async throws -> Data
    private var reading = false

    public init() {
        readBytes = { Self.encodedSample($0) }
    }

    /// An adapter must bound its own allocations and eventually return after
    /// cancellation. Returned bytes still pass the same size/schema checks.
    public init(readBytes: @escaping @Sendable (DemoDashboardDataSample) async throws -> Data) {
        self.readBytes = readBytes
    }

    public var isReading: Bool { reading }

    public func load(_ sample: DemoDashboardDataSample) async throws -> DemoDashboardReport {
        try Task.checkCancellation()
        guard !reading else { throw DemoDashboardDataError.busy }
        reading = true
        defer { reading = false }

        let bytes: Data
        do {
            bytes = try await readBytes(sample)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            // Do not retain or display arbitrary adapter errors or file paths.
            throw DemoDashboardDataError.readFailed
        }
        try Task.checkCancellation()
        let report = try Self.decode(bytes)
        try Task.checkCancellation()
        return report
    }

    /// Pure bounded decoding is also the extension point for validating a new
    /// local sample. Missing fields, bad JSON and wrong field types are errors.
    public nonisolated static func decode(_ bytes: Data) throws -> DemoDashboardReport {
        guard bytes.count <= maximumEncodedBytes else { throw DemoDashboardDataError.encodedDataTooLarge }
        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: bytes)
        } catch {
            throw DemoDashboardDataError.malformedJSON
        }
        guard payload.version == 1 else { throw DemoDashboardDataError.unsupportedVersion }
        return try DemoDashboardReport(
            day: validate(payload.day), week: validate(payload.week), all: validate(payload.all))
    }

    /// These bytes are read and decoded only when Refresh/Retry starts a load.
    /// Constructing a dashboard does not perform I/O or launch work.
    public nonisolated static func encodedSample(_ sample: DemoDashboardDataSample) -> Data {
        switch sample {
        case .valid:
            return Data(
                """
                {"version":1,"day":[
                  {"label":"1","fraction":0.35},{"label":"2","fraction":0.52},
                  {"label":"3","fraction":0.40},{"label":"4","fraction":0.68},
                  {"label":"5","fraction":0.56},{"label":"6","fraction":0.82},
                  {"label":"7","fraction":0.64},{"label":"8","fraction":0.94},
                  {"label":"9","fraction":0.72},{"label":"10","fraction":0.58}],
                 "week":[
                  {"label":"Mon","fraction":0.41},{"label":"Tue","fraction":0.56},
                  {"label":"Wed","fraction":0.49},{"label":"Thu","fraction":0.73},
                  {"label":"Fri","fraction":0.64},{"label":"Sat","fraction":0.88},
                  {"label":"Sun","fraction":0.70}],
                 "all":[
                  {"label":"Jan","fraction":0.28},{"label":"Feb","fraction":0.34},
                  {"label":"Mar","fraction":0.39},{"label":"Apr","fraction":0.44},
                  {"label":"May","fraction":0.50},{"label":"Jun","fraction":0.47},
                  {"label":"Jul","fraction":0.58},{"label":"Aug","fraction":0.63},
                  {"label":"Sep","fraction":0.69},{"label":"Oct","fraction":0.74},
                  {"label":"Nov","fraction":0.81},{"label":"Dec","fraction":0.92}]}
                """.utf8)
        case .empty:
            return Data(#"{"version":1,"day":[],"week":[],"all":[]}"#.utf8)
        case .malformed:
            return Data(#"{"version":1,"day":["#.utf8)
        }
    }

    private struct Payload: Decodable {
        let version: Int
        let day: [Point]
        let week: [Point]
        let all: [Point]
    }

    private struct Point: Decodable {
        let label: String
        let fraction: Double
    }

    private nonisolated static func validate(_ points: [Point]) throws -> [DemoDashboardDataPoint] {
        guard points.count <= maximumPointsPerRange else { throw DemoDashboardDataError.tooManyPoints }
        var labels: Set<String> = []
        return try points.map { point in
            guard !point.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                point.label.utf8.count <= maximumLabelBytes,
                !point.label.unicodeScalars.contains(where: {
                    CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0)
                })
            else { throw DemoDashboardDataError.invalidLabel }
            guard labels.insert(point.label).inserted else { throw DemoDashboardDataError.duplicateLabel }
            guard point.fraction.isFinite, (0...1).contains(point.fraction) else {
                throw DemoDashboardDataError.invalidFraction
            }
            return DemoDashboardDataPoint(label: point.label, fraction: point.fraction)
        }
    }
}

public enum DemoDashboardDataPhase: Equatable, Sendable {
    case preview, loading, ready, empty, failed, cancelled, closed
}

public enum DemoDashboardDataContent: Equatable, Sendable {
    /// The original authored chart, explicitly identified as a preview.
    case preview
    /// Includes genuinely empty reports; never replaced by preview data.
    case report(DemoDashboardReport)
    case released
}

public struct DemoDashboardDataSnapshot: Equatable, Sendable {
    public fileprivate(set) var selectedSample: DemoDashboardDataSample
    public fileprivate(set) var phase: DemoDashboardDataPhase
    public fileprivate(set) var content: DemoDashboardDataContent
    public fileprivate(set) var requestID: UUID?
    public fileprivate(set) var requestSample: DemoDashboardDataSample?
    public fileprivate(set) var error: DemoDashboardDataError?
}

/// Owned by the dashboard model, not a global loader or a rendering callback.
/// One job and at most one replacement intent exist. Refresh supersedes intent
/// immediately, but replacement work waits for the cancelled job to drain.
@MainActor
public final class DemoDashboardDataModel: ObservableObject {
    @Published private var changeSignal: UInt = 0
    private var current: DemoDashboardDataSnapshot
    private let service: DemoDashboardDataService
    private var desiredRequest: Request?
    private var job: Job?
    public private(set) var isClosed = false

    public init(service: DemoDashboardDataService = DemoDashboardDataService()) {
        self.service = service
        current = DemoDashboardDataSnapshot(
            selectedSample: .valid, phase: .preview, content: .preview,
            requestID: nil, requestSample: nil, error: nil)
    }

    isolated deinit { job?.task.cancel() }

    public var snapshot: DemoDashboardDataSnapshot { current }
    public var isReading: Bool { job != nil }
    public var isWaitingForPreviousRead: Bool {
        desiredRequest != nil && job != nil && job?.request !== desiredRequest
    }
    public var canCancel: Bool { !isClosed && desiredRequest != nil }
    public var canRetry: Bool { !isClosed && (current.phase == .failed || current.phase == .cancelled) }

    // Source tests await the actual model-owned task, rather than idle polling.
    var activeReadTask: Task<Void, Never>? { job?.task }
    var pendingRequestCount: Int { isWaitingForPreviousRead ? 1 : 0 }

    /// Selection alone neither starts a read nor disguises the displayed report
    /// as data from a different source. Refresh uses this next-input selection.
    @discardableResult
    public func select(_ sample: DemoDashboardDataSample) -> Bool {
        guard !isClosed, current.selectedSample != sample else { return false }
        current.selectedSample = sample
        notifyChange()
        return true
    }

    @discardableResult
    public func refresh() -> Bool {
        guard !isClosed else { return false }
        request(current.selectedSample)
        return true
    }

    /// Retry uses the failed/cancelled request's input, even if the next-input
    /// selection changed. Refresh is the explicit way to use the new selection.
    @discardableResult
    public func retry() -> Bool {
        guard canRetry, let sample = current.requestSample else { return false }
        request(sample)
        return true
    }

    @discardableResult
    public func cancel() -> Bool {
        guard canCancel else { return false }
        desiredRequest = nil
        current.phase = .cancelled
        current.error = nil
        // Commit revocation before cancellation handlers can reenter the model.
        job?.task.cancel()
        notifyChange()
        return true
    }

    /// Terminal ownership boundary. A tab change does not close this shared
    /// model; its owner can close it explicitly, or release it to cancel on deinit.
    public func close() {
        guard !isClosed else { return }
        isClosed = true
        desiredRequest = nil
        current.phase = .closed
        current.content = .released
        current.requestID = nil
        current.requestSample = nil
        current.error = nil
        job?.task.cancel()
        notifyChange()
    }

    private func request(_ sample: DemoDashboardDataSample) {
        let request = Request(sample: sample)
        desiredRequest = request
        current.requestID = request.id
        current.requestSample = sample
        current.phase = .loading
        current.error = nil
        // A cancelled job stays installed. No new task can overlap its read.
        job?.task.cancel()
        pump()
        notifyChange()
    }

    private func pump() {
        guard !isClosed, job == nil, let request = desiredRequest else { return }
        let service = service
        let task = Task { @MainActor [weak self] in
            let outcome: Outcome
            do {
                try Task.checkCancellation()
                guard self?.accepts(request) == true else { throw CancellationError() }
                let report = try await service.load(request.sample)
                try Task.checkCancellation()
                outcome = .report(report)
            } catch is CancellationError {
                outcome = .cancelled
            } catch let error as DemoDashboardDataError {
                outcome = .failed(error)
            } catch {
                outcome = .failed(.readFailed)
            }
            self?.finish(request, outcome: outcome)
        }
        job = Job(request: request, task: task)
    }

    private func accepts(_ request: Request) -> Bool {
        !isClosed && desiredRequest === request
    }

    private func finish(_ request: Request, outcome: Outcome) {
        guard job?.request === request else { return }
        job = nil
        if accepts(request) {
            desiredRequest = nil
            switch outcome {
            case .report(let report):
                current.content = .report(report)
                current.phase = report.isEmpty ? .empty : .ready
                current.error = nil
            case .failed(let error):
                current.phase = .failed
                current.error = error
            case .cancelled:
                current.phase = .cancelled
                current.error = nil
            }
        }
        pump()
        notifyChange()
    }

    // The snapshot/job authority is already committed when observers run.
    private func notifyChange() { changeSignal &+= 1 }

    private final class Request: Sendable {
        let id = UUID()
        let sample: DemoDashboardDataSample

        init(sample: DemoDashboardDataSample) { self.sample = sample }
    }

    private struct Job {
        let request: Request
        let task: Task<Void, Never>
    }

    private enum Outcome {
        case report(DemoDashboardReport)
        case failed(DemoDashboardDataError)
        case cancelled
    }
}
