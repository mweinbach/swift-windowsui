import WinSDK

/// A finite startup breadcrumb for an explicitly requested native journal.
/// It is not a journal record, clock, display observation or success verdict.
/// The ordinary application has no probe and performs no output-handle query.
@MainActor
final class NativeStartupPhaseProbe {
    enum Phase: UInt8, CaseIterable, Sendable {
        case mainEntered = 1
        case applicationInitialized = 2
        case backendResolved = 3
        case nativeTaskEntered = 4
        case ownerStarted = 5
        case primaryStartupReturned = 6
        case diagnosticsEntered = 7
        case nativeRunReturned = 8
        case retirementReturned = 9

        fileprivate var bytes: [UInt8] {
            Array("SWUI_STARTUP_PHASE \(rawValue)\n".utf8)
        }
    }

    typealias Sink = @MainActor ([UInt8]) -> Bool

    private var sink: Sink?
    private var lastPhase: UInt8 = 0
    private var isWriting = false

    private init(sink: @escaping Sink) { self.sink = sink }

    static func makeIfRequested(arguments: [String]) -> NativeStartupPhaseProbe? {
        makeIfRequested(arguments: arguments, makeSink: standardErrorSink)
    }

    /// Reuses only the existing pure argument parser. The real acquisition
    /// session, clock setup and configuration-error report stay at their
    /// original later boundary. No path or argument is retained in the probe.
    /// A valid request does not establish native eligibility or clock health.
    static func makeIfRequested(
        arguments: [String], makeSink: @MainActor () -> Sink?
    ) -> NativeStartupPhaseProbe? {
        do {
            guard try NativeDisplayAcquisitionConfiguration.parse(arguments: arguments) != nil else { return nil }
        } catch {
            return nil
        }
        guard let sink = makeSink() else { return nil }
        return NativeStartupPhaseProbe(sink: sink)
    }

    /// At most nine attempts of 21 ASCII bytes each. Gaps are legitimate:
    /// fallback, startup close and failure can bypass later boundaries.
    /// Reserve the phase before a synchronous sink can reenter. A failed or
    /// short write is never completed, retried or promoted to app failure.
    func record(_ phase: Phase) {
        guard !isWriting, phase.rawValue > lastPhase, let sink else { return }
        lastPhase = phase.rawValue
        isWriting = true
        let succeeded = sink(phase.bytes)
        isWriting = false
        if !succeeded || phase == .retirementReturned { self.sink = nil }
    }

    static func isCompleteWrite(succeeded: Bool, written: UInt32, expected: UInt32) -> Bool {
        succeeded && written == expected
    }

    /// Borrow the process's existing stderr handle. Do not open, replace,
    /// close, duplicate or flush it. The supervised run already redirects this
    /// handle to its owned raw output; this code creates no other destination.
    /// A small synchronous write can still block: the byte bound is not a
    /// duration guarantee, and missing markers cannot locate an earlier phase.
    private static func standardErrorSink() -> Sink? {
        guard let handle = GetStdHandle(DWORD(bitPattern: -12)), handle != INVALID_HANDLE_VALUE else { return nil }
        return { bytes in
            let expected = DWORD(bytes.count)
            var written: DWORD = 0
            let succeeded = bytes.withUnsafeBufferPointer { buffer in
                WriteFile(handle, buffer.baseAddress, expected, &written, nil)
            }
            return isCompleteWrite(succeeded: succeeded, written: written, expected: expected)
        }
    }
}
