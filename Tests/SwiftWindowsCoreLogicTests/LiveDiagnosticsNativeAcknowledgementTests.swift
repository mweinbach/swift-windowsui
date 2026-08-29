import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import WinSwiftUI

/// No native owner, HWND, GPU query, or presentation is started here. Held
/// replies expose the ordering of the production diagnostics caller.
@MainActor
final class LiveDiagnosticsNativeAcknowledgementTests: XCTestCase {
    private enum Operation: Hashable {
        case vsync(Bool)
        case timing(Bool)
        case capture(Bool)
        case poll
        case teardown
    }

    @MainActor
    private final class Backend: BatchRenderBackend {
        private let base = FakeBatchRenderBackend()
        var backendDisplayName: String { "SYNTHETIC NATIVE REPLIES" }
        var timingEnabled = false
        var pendingIDs: [BackendFrameID] = []
        var completedResults: [GPUFrameTimingResult] = []
        var snapshots: [GPUFrameTimingDiagnostics] = []
        var synchronousConfigurationCalls = 0

        var gpuFrameTimingDiagnostics: GPUFrameTimingDiagnostics? {
            let snapshot = GPUFrameTimingDiagnostics(
                isEnabled: timingEnabled, isSupported: true, pendingCount: pendingIDs.count)
            snapshots.append(snapshot)
            return snapshot
        }

        func takeCompletedGPUFrameTimings() -> [GPUFrameTimingResult] {
            let results = completedResults
            completedResults.removeAll()
            let completedIDs = Set(results.map(\.frameID))
            pendingIDs.removeAll { completedIDs.contains($0) }
            return results
        }

        func setGPUFrameTimingEnabled(_ enabled: Bool) -> Bool {
            synchronousConfigurationCalls += 1
            return false
        }

        func setPresentsWithVSync(_ enabled: Bool) -> Bool {
            synchronousConfigurationCalls += 1
            return false
        }

        func setCapturesPresentedFrames(_ enabled: Bool) -> Bool {
            synchronousConfigurationCalls += 1
            return false
        }

        func attach(to surface: SurfaceDescriptor) throws { try base.attach(to: surface) }
        func resize(to size: IntSize) throws { try base.resize(to: size) }
        func bindResources(for scene: GPUIScene) { base.bindResources(for: scene) }
        func render(scene: GPUIScene) throws { try base.render(scene: scene) }
        func detach() { base.detach() }

        func acknowledgeTiming(_ enabled: Bool) {
            timingEnabled = enabled
            if !enabled {
                completedResults.append(
                    contentsOf: pendingIDs.map {
                        GPUFrameTimingResult(frameID: $0, status: .cancelled)
                    })
                pendingIDs.removeAll()
            }
        }
    }

    @MainActor
    private final class Replies {
        let backend: Backend
        var requested: [Operation] = []
        var held: Set<Operation> = []
        var requestedSignals: [Operation: XCTestExpectation] = [:]
        var defaultReplies: [Operation: Bool] = [:]
        private var pending: [Operation: CheckedContinuation<Bool, Never>] = [:]

        init(backend: Backend) { self.backend = backend }

        var commands: LiveDiagnosticsNativeCommands {
            LiveDiagnosticsNativeCommands(
                setVSync: { [self] _, enabled in await perform(.vsync(enabled)) },
                setGPUFrameTimingEnabled: { [self] _, enabled in await perform(.timing(enabled)) },
                setFrameCaptureEnabled: { [self] _, enabled in await perform(.capture(enabled)) },
                poll: { [self] _ in await perform(.poll) },
                waitForTeardown: { [self] _ in await perform(.teardown) })
        }

        private func perform(_ operation: Operation) async -> Bool {
            requested.append(operation)
            let accepted: Bool
            if held.contains(operation) {
                accepted = await withCheckedContinuation { continuation in
                    precondition(pending[operation] == nil, "A native command was duplicated while awaiting its reply")
                    pending[operation] = continuation
                    requestedSignals.removeValue(forKey: operation)?.fulfill()
                }
            } else {
                requestedSignals.removeValue(forKey: operation)?.fulfill()
                accepted = defaultReplies[operation] ?? true
            }
            if accepted, case .timing(let enabled) = operation {
                backend.acknowledgeTiming(enabled)
            }
            return accepted
        }

        func complete(_ operation: Operation, accepted: Bool) throws {
            let continuation = try XCTUnwrap(pending.removeValue(forKey: operation))
            held.remove(operation)
            continuation.resume(returning: accepted)
        }
    }

    @MainActor
    private final class Harness {
        let backend: Backend
        let replies: Replies
        let host: WinSwiftUIWindowHost
        let output: URL
        var now = 1_000.0
        var closeRequests = 0
        var messages: [String] = []
        var startedSignal: XCTestExpectation?
        var writtenSignal: XCTestExpectation?

        init() {
            let backend = Backend()
            self.backend = backend
            replies = Replies(backend: backend)
            output = FileManager.default.temporaryDirectory
                .appendingPathComponent("swift-windowsui-native-diagnostics-\(UUID().uuidString).json")
            let size = IntSize(width: 32, height: 32)
            let window = Win32Window(title: "Native diagnostics reply test", clientSize: size)
            window.testScaleFactorOverride = 1
            let surface = SurfaceDescriptor(
                windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
                pixelSize: size, scaleFactor: 1)
            host = WinSwiftUIWindowHost(
                configuration: WindowGroupConfiguration(
                    title: "Native diagnostics reply test", size: size, clearColor: .black, content: []),
                platformWindow: window, renderer: FakeRenderBackend(), batchRenderer: backend,
                surfaceDescriptorProvider: { _ in surface }, startupPresentationMode: .automatic,
                startupProbeConfiguration: nil)
            host.windowDidCreate(window)
        }

        func makeSession(
            disablesVSync: Bool = false, collectsTiming: Bool = true, capturesMotion: Bool = false
        ) -> LiveDiagnosticsSession {
            LiveDiagnosticsSession(
                configuration: LiveDiagnosticsConfiguration(
                    durationSeconds: 60, outputPath: output.path, exercisesInput: false,
                    disablesVSync: disablesVSync, capturesMotion: capturesMotion,
                    motionOutputDirectory: output.deletingPathExtension().path, motionFrameCount: 4,
                    collectsGPUFrameTimings: collectsTiming),
                host: host,
                clock: { [self] in now },
                requestClose: { [self] in closeRequests += 1 },
                nativeCommands: replies.commands,
                report: { [self] message in
                    messages.append(message)
                    if message.contains("s run, writing ") {
                        startedSignal?.fulfill()
                        startedSignal = nil
                    }
                    if message.hasPrefix("Live diagnostics written to ") {
                        writtenSignal?.fulfill()
                        writtenSignal = nil
                    }
                })
        }

        func sample(
            at timestamp: Double, id: BackendFrameID? = nil,
            bindSeconds: Double = 0.001, bindTimingsAvailable: Bool = true
        ) {
            now = timestamp
            let submission = BackendFrameSubmission(
                id: id, outcome: .submitted, gpuTimingStatus: timingStatus, adapterIsSoftware: false)
            host.onFramePresented?(
                LiveFrameSample(
                    presentedAt: timestamp, totalSeconds: 0.01, sceneBuildSeconds: 0.001,
                    bindSeconds: bindSeconds, bindTimingsAvailable: bindTimingsAvailable,
                    backendSubmitSeconds: 0.002, backendPresentSeconds: 0.003,
                    submitAndPresentSeconds: 0.005, didRebuildScene: false, nodeReplayCount: 0,
                    primitiveCount: 1, hadActiveAnimations: false, backend: .scene,
                    backendFrameSubmission: submission, gpuTimingAdapterIsSoftware: false,
                    atlasUploadedByteCount: 0, drawCallCount: 1, drawnInstanceCount: 1, visitedNodeCount: 0))
        }

        private var timingStatus: GPUFrameTimingStatus { backend.timingEnabled ? .pending : .disabled }

        func readReport() throws -> [String: Any] {
            let data = try Data(contentsOf: output)
            return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        }

        func removeReport() { try? FileManager.default.removeItem(at: output) }
    }

    private func object(_ parent: [String: Any], _ key: String) throws -> [String: Any] {
        try XCTUnwrap(parent[key] as? [String: Any], "Missing object \(key)")
    }

    private func hold(_ operation: Operation, in harness: Harness) -> XCTestExpectation {
        let signal = expectation(description: "Native command \(operation) requested")
        harness.replies.held.insert(operation)
        harness.replies.requestedSignals[operation] = signal
        return signal
    }

    private func start(_ session: LiveDiagnosticsSession, in harness: Harness) async {
        let signal = expectation(description: "Sampling started after native setup")
        harness.startedSignal = signal
        session.start()
        await fulfillment(of: [signal], timeout: 1)
    }

    private func finish(_ session: LiveDiagnosticsSession, in harness: Harness) async {
        let signal = expectation(description: "Report written after native shutdown")
        harness.writtenSignal = signal
        session.finish()
        await fulfillment(of: [signal], timeout: 1)
    }

    func testStartupReturnsBeforeCommandsAndUsesActualRepliesForSupportAndClock() async throws {
        let harness = Harness()
        defer { harness.removeReport() }
        let vsyncRequested = hold(.vsync(false), in: harness)
        let timingRequested = hold(.timing(true), in: harness)
        let started = expectation(description: "Sampling starts only after the timing reply")
        harness.startedSignal = started
        let session = harness.makeSession(disablesVSync: true)

        session.start()
        session.start()
        XCTAssertTrue(harness.replies.requested.isEmpty, "A synchronous callback must return before native waits")
        XCTAssertNil(harness.host.onFramePresented)
        XCTAssertFalse(harness.host.hostedRuntime.collectsPhaseTimings)
        await fulfillment(of: [vsyncRequested], timeout: 1)
        try harness.replies.complete(.vsync(false), accepted: false)
        await fulfillment(of: [timingRequested], timeout: 1)
        XCTAssertNil(harness.host.onFramePresented, "Queue admission is not completed setup")
        harness.now = 1_010
        try harness.replies.complete(.timing(true), accepted: true)
        await fulfillment(of: [started], timeout: 1)
        XCTAssertNotNil(harness.host.onFramePresented)
        XCTAssertTrue(harness.host.hostedRuntime.collectsPhaseTimings)
        harness.now = 1_012
        await finish(session, in: harness)

        let report = try harness.readReport()
        XCTAssertEqual(report["durationSecondsActual"] as? Double, 2)
        XCTAssertEqual(report["vsyncDisabledForRun"] as? Bool, false)
        XCTAssertEqual(try object(report, "gpu")["initiallySupported"] as? Bool, true)
        let native = try object(report, "nativePresentation")
        let acknowledgements = try object(native, "acknowledgements")
        XCTAssertEqual(acknowledgements["disableVSync"] as? Bool, false)
        XCTAssertEqual(acknowledgements["enableGPUFrameTimings"] as? Bool, true)
        XCTAssertEqual(native["completion"] as? String, "commandsRejected")
        let measurement = try object(report, "measurement")
        XCTAssertEqual(measurement["frameTimestamp"] as? String, "nativeOwnerRenderReturn")
        XCTAssertEqual(measurement["nativeCommandHandoffIncludedInFrameTime"] as? Bool, true)
        XCTAssertEqual(measurement["nativeReplyDeliveryDelayIncludedInFrameTime"] as? Bool, false)
        XCTAssertEqual(measurement["hardwareQualified"] as? Bool, false)
        XCTAssertEqual(harness.backend.synchronousConfigurationCalls, 0)
        XCTAssertEqual(harness.closeRequests, 1)
    }

    func testFinishWaitsForPollThenDisableAndDrainsActualCancellationResults() async throws {
        let harness = Harness()
        defer { harness.removeReport() }
        let session = harness.makeSession()
        await start(session, in: harness)
        let validID = BackendFrameID(deviceGeneration: 7, frameNumber: 11)
        let pendingID = BackendFrameID(deviceGeneration: 7, frameNumber: 12)
        harness.backend.pendingIDs = [validID, pendingID]
        harness.sample(at: 1_002, id: validID)
        harness.sample(at: 1_002.1, id: pendingID)
        XCTAssertEqual(harness.replies.requested, [.timing(true)], "Samples must not enqueue native query polls")
        let pollRequested = hold(.poll, in: harness)
        let disableRequested = hold(.timing(false), in: harness)
        let written = expectation(description: "Final report waits for collector shutdown")
        harness.writtenSignal = written

        session.finish()
        session.finish()
        XCTAssertNil(harness.host.onFramePresented)
        XCTAssertFalse(harness.host.hostedRuntime.collectsPhaseTimings)
        XCTAssertEqual(harness.closeRequests, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.output.path))
        await fulfillment(of: [pollRequested], timeout: 1)
        harness.backend.completedResults = [
            GPUFrameTimingResult(frameID: validID, status: .valid, elapsedSeconds: 0.005)
        ]
        try harness.replies.complete(.poll, accepted: true)
        await fulfillment(of: [disableRequested], timeout: 1)
        XCTAssertEqual(harness.backend.snapshots.last?.isEnabled, true)
        XCTAssertEqual(harness.backend.snapshots.last?.pendingCount, 1)
        XCTAssertEqual(harness.closeRequests, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.output.path))
        harness.now = 1_025
        try harness.replies.complete(.timing(false), accepted: true)
        await fulfillment(of: [written], timeout: 1)

        let report = try harness.readReport()
        let gpu = try object(report, "gpu")
        let collector = try object(gpu, "collectorLifetime")
        XCTAssertEqual(collector["isEnabledAtFinish"] as? Bool, true)
        XCTAssertEqual(collector["pendingAtFinish"] as? Int, 1)
        XCTAssertEqual(try object(gpu, "sessionJoin")["resultCount"] as? Int, 2)
        let statuses = try object(try object(gpu, "postWarmup"), "timingStatusCounts")
        XCTAssertEqual(statuses["valid"] as? Int, 1)
        XCTAssertEqual(statuses["cancelled"] as? Int, 1)
        XCTAssertEqual(report["durationSecondsActual"] as? Double ?? -1, 2.1, accuracy: 0.000001)
        XCTAssertEqual(harness.replies.requested, [.timing(true), .poll, .timing(false)])
        XCTAssertFalse(harness.backend.timingEnabled)
        XCTAssertEqual(harness.backend.synchronousConfigurationCalls, 0)
        XCTAssertEqual(harness.closeRequests, 1)
    }

    func testFinalCaptureDisableReceiptDrainsTimingsAfterTimingDisableWasRejected() async throws {
        let harness = Harness()
        defer { harness.removeReport() }
        let session = harness.makeSession(capturesMotion: true)
        await start(session, in: harness)
        let captureRequested = hold(.capture(true), in: harness)
        let timingDisableRequested = hold(.timing(false), in: harness)
        let captureDisableRequested = hold(.capture(false), in: harness)
        let finalID = BackendFrameID(deviceGeneration: 7, frameNumber: 21)
        harness.backend.pendingIDs = [finalID]
        harness.sample(at: 1_002, id: finalID)
        await fulfillment(of: [captureRequested], timeout: 1)
        let written = expectation(description: "Final configure timing payload is drained before reporting")
        harness.writtenSignal = written

        session.finish()
        try harness.replies.complete(.capture(true), accepted: true)
        await fulfillment(of: [timingDisableRequested], timeout: 1)
        try harness.replies.complete(.timing(false), accepted: false)
        await fulfillment(of: [captureDisableRequested], timeout: 1)
        XCTAssertTrue(harness.backend.timingEnabled, "A rejected disable must not fabricate collector shutdown")
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.output.path))
        XCTAssertEqual(harness.closeRequests, 0)

        // Model the payload the host consumes from the last configure receipt
        // before returning its acknowledgement to the diagnostics caller.
        harness.backend.completedResults = [
            GPUFrameTimingResult(frameID: finalID, status: .valid, elapsedSeconds: 0.004)
        ]
        try harness.replies.complete(.capture(false), accepted: true)
        await fulfillment(of: [written], timeout: 1)

        let report = try harness.readReport()
        let gpu = try object(report, "gpu")
        let joined = try object(gpu, "sessionJoin")
        XCTAssertEqual(joined["resultCount"] as? Int, 1)
        XCTAssertEqual(joined["matchedResultCount"] as? Int, 1)
        XCTAssertEqual(joined["duplicateResultIDCount"] as? Int, 0)
        let statuses = try object(try object(gpu, "postWarmup"), "timingStatusCounts")
        XCTAssertEqual(statuses["valid"] as? Int, 1)
        XCTAssertTrue(harness.host.takeCompletedGPUFrameTimings().isEmpty, "The final result must be consumed once")
        let native = try object(report, "nativePresentation")
        let acknowledgements = try object(native, "acknowledgements")
        XCTAssertEqual(acknowledgements["disableGPUFrameTimings"] as? Bool, false)
        XCTAssertEqual(acknowledgements["disableFrameCapture"] as? Bool, true)
        XCTAssertEqual(native["completion"] as? String, "commandsRejected")
        XCTAssertEqual(
            harness.replies.requested, [.timing(true), .capture(true), .poll, .timing(false), .capture(false)])
        XCTAssertTrue(harness.backend.timingEnabled)
        XCTAssertEqual(harness.backend.synchronousConfigurationCalls, 0)
        XCTAssertEqual(harness.closeRequests, 1)
    }

    func testFinishRetainsSessionAndWaitsForLateEnableWithoutRestartingSampling() async throws {
        let harness = Harness()
        defer { harness.removeReport() }
        let timingRequested = hold(.timing(true), in: harness)
        let written = expectation(description: "Late enable is disabled before reporting")
        harness.writtenSignal = written
        var session: LiveDiagnosticsSession? = harness.makeSession()
        weak var retainedSession = session
        session?.start()
        await fulfillment(of: [timingRequested], timeout: 1)
        session?.finish()
        session = nil
        XCTAssertNotNil(retainedSession, "An in-flight native request must retain its typed session")
        XCTAssertEqual(harness.closeRequests, 0)
        XCTAssertNil(harness.host.onFramePresented)

        try harness.replies.complete(.timing(true), accepted: true)
        await fulfillment(of: [written], timeout: 1)

        XCTAssertNil(harness.host.onFramePresented)
        XCTAssertFalse(harness.host.hostedRuntime.collectsPhaseTimings)
        XCTAssertFalse(harness.messages.contains { $0.contains("s run, writing ") })
        XCTAssertEqual(harness.replies.requested, [.timing(true), .poll, .timing(false)])
        XCTAssertFalse(harness.backend.timingEnabled)
        let report = try harness.readReport()
        XCTAssertEqual(try object(report, "nativePresentation")["samplingStarted"] as? Bool, false)
        XCTAssertEqual(try object(report, "frames")["presentedTotal"] as? Int, 0)
        XCTAssertEqual(try object(report, "measurement")["gpuExecutionMeasured"] as? Bool, false)
        XCTAssertEqual(harness.closeRequests, 1)
    }

    func testCloseDuringStartupWaitsForTeardownAndDoesNotSendShutdownConfiguration() async throws {
        let harness = Harness()
        defer { harness.removeReport() }
        let enableRequested = hold(.timing(true), in: harness)
        let teardownRequested = hold(.teardown, in: harness)
        let written = expectation(description: "Closed startup reports only after native teardown")
        harness.writtenSignal = written
        let session = harness.makeSession()
        session.start()
        await fulfillment(of: [enableRequested], timeout: 1)
        harness.host.windowWillClose(harness.host.platformWindow)
        let completion = try XCTUnwrap(session.finishAfterHostClosed(harness.host))
        XCTAssertNotNil(
            session.finishAfterHostClosed(harness.host), "Repeated close keeps the existing completion task")
        try harness.replies.complete(.timing(true), accepted: true)
        await fulfillment(of: [teardownRequested], timeout: 1)
        XCTAssertNil(harness.host.onFramePresented)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.output.path))
        XCTAssertEqual(harness.replies.requested, [.timing(true), .teardown])
        let cancelled = BackendFrameID(deviceGeneration: 9, frameNumber: 1)
        harness.backend.completedResults = [GPUFrameTimingResult(frameID: cancelled, status: .cancelled)]
        harness.backend.timingEnabled = false
        try harness.replies.complete(.teardown, accepted: true)
        await fulfillment(of: [written], timeout: 1)
        await completion.value

        let report = try harness.readReport()
        let native = try object(report, "nativePresentation")
        let acknowledgements = try object(native, "acknowledgements")
        XCTAssertEqual(native["completion"] as? String, "teardownInterrupted")
        XCTAssertEqual(native["samplingStarted"] as? Bool, false)
        XCTAssertEqual(acknowledgements["teardown"] as? Bool, true)
        XCTAssertNil(acknowledgements["disableGPUFrameTimings"])
        XCTAssertEqual(try object(try object(report, "gpu"), "sessionJoin")["resultCount"] as? Int, 1)
        XCTAssertEqual(harness.closeRequests, 0, "An already closed host must not receive another close request")
        XCTAssertEqual(harness.backend.synchronousConfigurationCalls, 0)
    }

    func testCloseDuringFinalPollWaitsForFailedTeardownWithoutInventingFinalDiagnostics() async throws {
        let harness = Harness()
        defer { harness.removeReport() }
        let session = harness.makeSession()
        await start(session, in: harness)
        let pollRequested = hold(.poll, in: harness)
        let teardownRequested = hold(.teardown, in: harness)
        let written = expectation(description: "Teardown failure is reported after its actual reply")
        harness.writtenSignal = written
        session.finish()
        await fulfillment(of: [pollRequested], timeout: 1)
        harness.host.windowWillClose(harness.host.platformWindow)
        try harness.replies.complete(.poll, accepted: false)
        await fulfillment(of: [teardownRequested], timeout: 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.output.path))
        try harness.replies.complete(.teardown, accepted: false)
        await fulfillment(of: [written], timeout: 1)

        let report = try harness.readReport()
        let native = try object(report, "nativePresentation")
        let acknowledgements = try object(native, "acknowledgements")
        XCTAssertEqual(acknowledgements["finalGPUFrameTimingPoll"] as? Bool, false)
        XCTAssertEqual(acknowledgements["teardown"] as? Bool, false)
        XCTAssertTrue(native["pendingTimingResultsAtFinish"] is NSNull)
        XCTAssertEqual(try object(try object(report, "gpu"), "sessionJoin")["resultCount"] as? Int, 0)
        XCTAssertEqual(try object(report, "measurement")["gpuExecutionMeasured"] as? Bool, false)
        XCTAssertEqual(harness.replies.requested, [.timing(true), .poll, .teardown])
        XCTAssertEqual(harness.closeRequests, 0)
    }

    func testFinishJoinsPendingReadbackEnableThenWaitsForItsActualDisableReply() async throws {
        let harness = Harness()
        defer { harness.removeReport() }
        let session = harness.makeSession(collectsTiming: false, capturesMotion: true)
        await start(session, in: harness)
        let captureRequested = hold(.capture(true), in: harness)
        let disableRequested = hold(.capture(false), in: harness)
        harness.sample(at: 1_002)
        await fulfillment(of: [captureRequested], timeout: 1)
        harness.sample(at: 1_002.1)
        harness.sample(at: 1_002.2)
        XCTAssertEqual(harness.replies.requested, [.capture(true)], "Pending enable must not be submitted per frame")
        let written = expectation(description: "Motion report waits for the disable reply")
        harness.writtenSignal = written
        session.finish()
        try harness.replies.complete(.capture(true), accepted: true)
        await fulfillment(of: [disableRequested], timeout: 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.output.path))
        XCTAssertFalse(harness.messages.contains { $0.contains("capturing 4 presented frames") })
        XCTAssertEqual(harness.closeRequests, 0)
        try harness.replies.complete(.capture(false), accepted: false)
        await fulfillment(of: [written], timeout: 1)

        let report = try harness.readReport()
        let native = try object(report, "nativePresentation")
        let acknowledgements = try object(native, "acknowledgements")
        XCTAssertEqual(acknowledgements["enableFrameCapture"] as? Bool, true)
        XCTAssertEqual(acknowledgements["disableFrameCapture"] as? Bool, false)
        XCTAssertEqual(try object(report, "motionCapture")["backendSupportedReadback"] as? Bool, false)
        XCTAssertNotNil(try object(report, "motionCapture")["failure"] as? String)
        XCTAssertEqual(harness.replies.requested, [.capture(true), .capture(false)])
        XCTAssertEqual(harness.backend.synchronousConfigurationCalls, 0)
        XCTAssertEqual(harness.closeRequests, 1)
    }

    func testRevokedReadbackEnableReportsInterruptionInsteadOfUnsupportedCapability() async throws {
        let harness = Harness()
        defer { harness.removeReport() }
        let session = harness.makeSession(collectsTiming: false, capturesMotion: true)
        await start(session, in: harness)
        let enableRequested = hold(.capture(true), in: harness)
        let teardownRequested = hold(.teardown, in: harness)
        harness.sample(at: 1_002)
        await fulfillment(of: [enableRequested], timeout: 1)
        harness.host.windowWillClose(harness.host.platformWindow)
        let written = expectation(description: "Interrupted readback reports after teardown")
        harness.writtenSignal = written
        let completion = try XCTUnwrap(session.finishAfterHostClosed(harness.host))
        try harness.replies.complete(.capture(true), accepted: false)
        await fulfillment(of: [teardownRequested], timeout: 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.output.path))
        try harness.replies.complete(.teardown, accepted: true)
        await fulfillment(of: [written], timeout: 1)
        await completion.value

        let report = try harness.readReport()
        let motion = try object(report, "motionCapture")
        XCTAssertEqual(motion["failure"] as? String, "window teardown interrupted presented-frame readback")
        XCTAssertEqual(motion["backendSupportedReadback"] as? Bool, false)
        XCTAssertFalse(harness.messages.contains { $0.contains("does not support presented-frame readback") })
        XCTAssertEqual(harness.replies.requested, [.capture(true), .teardown])
        XCTAssertEqual(harness.closeRequests, 0)
    }

    func testMissingNativeBindingIntervalsAreNullAndExcludedFromPercentiles() async throws {
        let harness = Harness()
        defer { harness.removeReport() }
        let session = harness.makeSession(collectsTiming: false)
        await start(session, in: harness)
        harness.sample(at: 1_002, bindSeconds: 0, bindTimingsAvailable: false)
        harness.sample(at: 1_002.1, bindSeconds: 0.004)
        await finish(session, in: harness)

        let report = try harness.readReport()
        let frames = try object(report, "frames")
        let bindings = try object(frames, "bindResourcesMs")
        XCTAssertEqual(frames["framesWithBindResourceTimings"] as? Int, 1)
        XCTAssertEqual(bindings["sampleCount"] as? Int, 1)
        XCTAssertEqual(bindings["mean"] as? Double, 4)
        let details = try XCTUnwrap(report["worstFrames"] as? [[String: Any]])
        XCTAssertEqual(details.filter { $0["bindResourcesMs"] is NSNull }.count, 1)
        XCTAssertEqual(details.compactMap { $0["bindResourcesMs"] as? Double }, [4])
        XCTAssertTrue(harness.replies.requested.isEmpty, "A diagnostics run with no native controls needs no polls")
    }

    func testLegacyCloseRemainsSynchronousAndClosedHostMatchingIsExact() async throws {
        let harness = Harness()
        let unrelated = Harness()
        defer {
            harness.removeReport()
            unrelated.removeReport()
        }
        let session = LiveDiagnosticsSession(
            configuration: LiveDiagnosticsConfiguration(
                durationSeconds: 60, outputPath: harness.output.path, exercisesInput: false,
                disablesVSync: true, collectsGPUFrameTimings: true),
            host: harness.host, clock: { harness.now },
            requestClose: { harness.closeRequests += 1 }, report: { _ in })
        session.start()
        XCTAssertNotNil(harness.host.onFramePresented)
        XCTAssertEqual(harness.backend.synchronousConfigurationCalls, 2)
        XCTAssertNil(session.finishAfterHostClosed(harness.host), "An open host must not finish the session")
        unrelated.host.windowWillClose(unrelated.host.platformWindow)
        XCTAssertNil(session.finishAfterHostClosed(unrelated.host), "Another closed window does not own this session")
        XCTAssertNotNil(harness.host.onFramePresented)
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.output.path))

        harness.host.windowWillClose(harness.host.platformWindow)
        XCTAssertNil(session.finishAfterHostClosed(harness.host))
        XCTAssertNil(harness.host.onFramePresented)
        XCTAssertEqual(harness.closeRequests, 1, "Legacy finalization keeps its existing immediate close callback")
        XCTAssertNil(try harness.readReport()["nativePresentation"])
        XCTAssertTrue(harness.replies.requested.isEmpty)
        session.finish()
        XCTAssertEqual(harness.closeRequests, 1)
    }
}
