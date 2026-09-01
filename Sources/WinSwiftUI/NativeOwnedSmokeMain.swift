import Dispatch
import Foundation
import SwiftWindowsGraphics
import SwiftWindowsPlatform
import WinSDK

/// Only the separate fixed-purpose executable calls this package entry point.
/// Ordinary App.main, public app flags and global defaults are unchanged.
@MainActor
package enum NativeOwnedSmokeMain {
    package static func run(
        renderBackendFactory: any RenderBackendFactory, expectedBackendNames: Set<String>
    ) -> Never {
        let started = DispatchTime.now()
        let watchdogDeadline = started + .seconds(45)
        // Start before fixture construction. The hard deadline does not touch
        // observation/actor locks or DLL teardown, and the fixture never
        // disarms it. ExitProcess itself terminates other threads before DLL
        // detach, so the independent caller must bound that final teardown.
        // A watchdog exit is always failure 124.
        Thread.detachNewThread {
            _ = DispatchSemaphore(value: 0).wait(timeout: watchdogDeadline)
            _ = TerminateProcess(GetCurrentProcess(), 124)
        }
        let observation = Win32NativeSmokeObservation(runID: Foundation.UUID())
        let shared = NativeOwnedSmokeSharedState(observation: observation, expectedBackendNames: expectedBackendNames)
        let session = NativeOwnedSmokeSession(shared: shared, renderBackendFactory: renderBackendFactory)
        let controller = NativeOwnedSmokeController(session: session, shared: shared, deadline: started + .seconds(42))
        observation.record(.fixtureStarted)
        let invocationIsValid =
            CommandLine.arguments.count == 1 && !expectedBackendNames.isEmpty && expectedBackendNames.count <= 3
        if !invocationIsValid {
            shared.fail(NativeOwnedSmokeFailure("fixed-fixture-invocation-invalid"))
        }

        Thread.detachNewThread {
            let code = controller.run()
            ExitProcess(DWORD(bitPattern: code))
        }
        if invocationIsValid { Task { @MainActor in await session.run() } }
        dispatchMain()
    }
}

private struct NativeOwnedSmokeResult: Encodable {
    let schema = "native-owned-smoke-v1"
    let sourceBaseline = "cdd5fd2c80bffc2b0ca0db7ddd064d5b022a9e04"
    let fixtureSourceOrigin = "f475f089cf261c7c8f6b6959dd25cde901cff004"
    let actualCompiledSourceAndPEMustBeBoundByCaller = true
    let actualNaturalExitMustStillBeVerifiedByCaller = true
    let directVtableOnlyNotCOMRouting = true
    let presentationIsSubmissionNotDisplayCompletion = true
    let output: String
    let intendedExitCode: Int32
    let runID: String
    let recordCount: Int
    let encodedTraceBytes: Int
    let observationInvalid: Bool
    let actualOwnerJoinObserved: Bool
    let unfinishedNativeOperationOutcome: String?
    let verdict: NativeOwnedSmokeVerdict
    let failures: [NativeOwnedSmokeFailure]
    let idleStart: NativeOwnedSmokeHostSnapshot?
    let idleEnd: NativeOwnedSmokeHostSnapshot?
    let eventKinds: [String: String]
}

/// One fixed controller, not a process supervisor or reusable executor. Its
/// waits consume a semaphore from passive records; there is no periodic poll
/// of the native queue/window or repeated idle-boundary sampling.
private final class NativeOwnedSmokeController: Sendable {
    private let session: NativeOwnedSmokeSession
    private let shared: NativeOwnedSmokeSharedState
    private let deadline: DispatchTime

    init(session: NativeOwnedSmokeSession, shared: NativeOwnedSmokeSharedState, deadline: DispatchTime) {
        self.session = session
        self.shared = shared
        self.deadline = deadline
    }

    func run() -> Int32 {
        var completedSequence = false
        do {
            _ = try waitUntil { observation, state in
                observation.count(.hostReady) == 1 && observation.count(.modelFirstAwait) == 1
                    && state.framePhaseMask & 1 != 0
            }
            Task { @MainActor [session] in await session.startWorkload() }
            _ = try waitUntil { observation, _ in observation.count(.ownedWorkloadSubmitted) == 1 }
            Task { @MainActor [session] in session.releaseFirst() }
            _ = try waitUntil { [session] observation, state in
                let queue = session.pump.smokeQueueSnapshot
                return state.replyMask == UInt64.max && observation.deliveredProbeCount == 64
                    && state.framePhaseMask & 2 != 0 && observation.count(.modelSecondAwait) == 1
                    && observation.last(.nativeTimerState)?.flags == 0 && queue.queuedWork == 0
                    && !queue.nativeTurnActive && !queue.nativeWorkInFlight
            }

            Task { @MainActor [session] in session.sampleIdleBoundary(ending: false) }
            let idleStart = try waitUntil { observation, _ in observation.count(.idleBegan) == 1 }
            guard idleStart.0.last(.idleBegan)?.flags == 1 else {
                throw NativeOwnedSmokeFailure("idle-start-was-not-settled")
            }
            // Exactly one external timed interval. A and N receive no work
            // from this wait; no forced frame/timing poll occurs inside it.
            _ = DispatchSemaphore(value: 0).wait(timeout: .now() + .seconds(3))
            Task { @MainActor [session] in session.sampleIdleBoundary(ending: true) }
            let idleEnd = try waitUntil { observation, _ in observation.count(.idleEnded) == 1 }
            guard idleEnd.0.last(.idleEnded)?.flags == 1 else {
                throw NativeOwnedSmokeFailure("idle-end-was-not-settled")
            }
            Task { @MainActor [session] in session.releaseSecond() }
            _ = try waitUntil { observation, state in
                state.framePhaseMask & 4 != 0 && observation.count(.modelFinished) == 1
            }

            try queryWhileClosing()
            _ = try waitUntil { observation, state in
                observation.count(.coordinatorReturned) == 1 && observation.count(.nativeThreadJoined) == 1
                    && state.ownerExitCode != nil
            }
            Task { @MainActor [session] in session.submitAfterOwnerStopped() }
            _ = try waitUntil { observation, _ in observation.count(.staleCommandRejected) == 1 }
            completedSequence = true
        } catch {
            if let failure = error as? NativeOwnedSmokeFailure {
                shared.fail(failure)
            } else {
                shared.fail(NativeOwnedSmokeFailure("fixture-control-failed", error: error))
            }
            // Releasing the independent gate cannot depend on A/N progress.
            // An early failure still exits nonzero with unknown unfinished
            // operations; it is never described as a graceful close.
            if let gate = shared.snapshot().gate { _ = gate.open() }
        }

        shared.releaseExternalResources()
        shared.observation.record(.externalResourcesReleased)
        shared.observation.record(.fixtureFinished, flags: completedSequence ? 1 : 0)
        do {
            let capture = shared.observation.capture()
            let state = shared.snapshot()
            let rows = try NativeOwnedSmokeValidation.decode(capture.trace)
            let verdict = NativeOwnedSmokeValidation.evaluate(rows, observation: capture.snapshot, state: state)
            let onlyFairnessMissing = verdict.predicates.allSatisfy {
                $0.value || $0.key == "backlogged-32-record-turn-and-continuation"
                    || $0.key == "actor-progress-between-backlogged-turns"
            }
            let code: Int32 =
                completedSequence && verdict.qualifyingPredicatesSatisfied
                ? 0
                : completedSequence && verdict.insufficientFairnessExercise && onlyFairnessMissing ? 2 : 1
            let joined = verdict.predicates["actual-owner-join-and-actor-stop-consumption"] == true
            let result = NativeOwnedSmokeResult(
                output: code == 0
                    ? "predicates-satisfied-awaiting-external-exit-receipt" : code == 2 ? "inconclusive" : "failed",
                intendedExitCode: code, runID: capture.snapshot.runID.uuidString,
                recordCount: capture.snapshot.recordCount, encodedTraceBytes: capture.trace.count,
                observationInvalid: capture.snapshot.isInvalid, actualOwnerJoinObserved: joined,
                unfinishedNativeOperationOutcome: joined ? nil : "unknown",
                verdict: verdict, failures: state.failures, idleStart: state.idleStart, idleEnd: state.idleEnd,
                eventKinds: Dictionary(
                    uniqueKeysWithValues: Win32NativeSmokeEventKind.allCases.map {
                        (String($0.rawValue), String(describing: $0))
                    }))
            try write(capture: capture, result: result)
            return code
        } catch {
            // An output error cannot turn a failed/missing artifact into a
            // success. No fallback output directory or overwrite is attempted.
            let line = "Native smoke output failed: \(String(describing: error).prefix(512))\n"
            FileHandle.standardError.write(Data(line.utf8))
            return 1
        }
    }

    private func queryWhileClosing() throws {
        guard let provider = shared.snapshot().provider else {
            throw NativeOwnedSmokeFailure("external-provider-unavailable")
        }
        let gate = try provider.armPublicationGate()
        guard shared.installGate(gate) else {
            throw NativeOwnedSmokeFailure("publication-gate-installed-more-than-once")
        }
        shared.observation.record(.publicationGateArmed)
        let workerFinished = DispatchSemaphore(value: 0)
        Thread.detachNewThread { [shared] in
            shared.observation.record(.externalQueryStarted)
            let result = provider.controlType()
            shared.recordExternalResult(result)
            shared.observation.record(
                .externalQueryCompleted, value: Int64(result.status),
                auxiliary: UInt64(UInt32(bitPattern: result.value)))
            workerFinished.signal()
        }
        let entered = gate.waitUntilEntered()
        let enteredThread = gate.enteredThreadID
        shared.observation.record(.publicationGateEntered, value: Int64(entered), auxiliary: UInt64(enteredThread))
        let workerThread = shared.observation.snapshot().last(.externalQueryStarted)?.threadID
        guard entered == 0, enteredThread != 0, enteredThread == workerThread else {
            _ = gate.open()
            throw NativeOwnedSmokeFailure("publication-gate-did-not-belong-to-owned-worker", code: Int64(entered))
        }
        Task { @MainActor [session] in session.requestClose() }
        let blocked = try waitUntil { observation, _ in
            observation.count(.uiARevoked) == 1 && observation.count(.nativeCloseAwaitingAttachments) > 0
        }
        guard blocked.0.count(.nativeWindowNonClientDestroyed) == 0 else {
            _ = gate.open()
            throw NativeOwnedSmokeFailure("window-destroyed-while-full-C-call-was-held")
        }
        // This record precedes the release call; the actual HRESULT is a
        // separate result. A released worker/N may finish before it is logged.
        shared.observation.record(.publicationGateReleaseRequested)
        let opened = gate.open()
        shared.observation.record(.publicationGateOpened, value: Int64(opened))
        guard opened == 0 else { throw NativeOwnedSmokeFailure("publication-gate-open-failed", code: Int64(opened)) }
        _ = try waitUntil { observation, _ in observation.count(.externalQueryCompleted) == 1 }
        guard workerFinished.wait(timeout: deadline) == .success else {
            throw NativeOwnedSmokeFailure("external-provider-worker-did-not-finish")
        }
        // This semaphore observes return from the C helper, not an OS thread
        // join. The qualified OS-thread join below belongs to the real N pump.
    }

    private func waitUntil(
        _ predicate: (Win32NativeSmokeObservationSnapshot, NativeOwnedSmokeSharedState.Snapshot) -> Bool
    ) throws -> (Win32NativeSmokeObservationSnapshot, NativeOwnedSmokeSharedState.Snapshot) {
        while true {
            guard DispatchTime.now() < deadline else {
                throw NativeOwnedSmokeFailure("fixed-fixture-deadline-expired")
            }
            let observation = shared.observation.snapshot()
            let state = shared.snapshot()
            if observation.isInvalid { throw NativeOwnedSmokeFailure("bounded-observation-invalid") }
            if let failure = state.failures.first { throw failure }
            if predicate(observation, state) { return (observation, state) }
            guard shared.observation.waitForActivity(until: deadline) else {
                throw NativeOwnedSmokeFailure("fixed-fixture-deadline-expired")
            }
        }
    }

    private func write(capture: Win32NativeSmokeCapture, result: NativeOwnedSmokeResult) throws {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let traceURL = directory.appendingPathComponent("trace.jsonl", isDirectory: false)
        let resultURL = directory.appendingPathComponent("result.json", isDirectory: false)
        guard !FileManager.default.fileExists(atPath: traceURL.path),
            !FileManager.default.fileExists(atPath: resultURL.path)
        else {
            throw NativeOwnedSmokeFailure("owned-output-already-exists")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let resultData = try encoder.encode(result)
        guard capture.trace.count <= 1_048_576, resultData.count <= 131_072 else {
            throw NativeOwnedSmokeFailure("fixed-output-byte-cap-exceeded")
        }
        try capture.trace.write(to: traceURL, options: .withoutOverwriting)
        try resultData.write(to: resultURL, options: .withoutOverwriting)
    }
}
