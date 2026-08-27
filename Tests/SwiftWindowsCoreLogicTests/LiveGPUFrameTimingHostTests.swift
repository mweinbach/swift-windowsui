import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
private final class LiveGPUHostClock {
    var now: Double = 1_000
    var sceneSeconds: Double = 0
    var bindSeconds: Double = 0
    var renderSeconds: Double = 0
    var backendDiagnosticsSeconds: Double = 0
    var gpuPollSeconds: Double = 0
}

/// The fake has no GPU queries. Its queue and event log expose the exact
/// capability calls made by the host and diagnostics session.
@MainActor
private final class LiveGPUHostBatchBackend: BatchRenderBackend {
    enum Event: Equatable {
        case setEnabled(Bool)
        case takeCompleted(enabled: Bool)
        case snapshot(enabled: Bool, pending: Int)
        case detach
    }

    private let base = FakeBatchRenderBackend()
    let clock: LiveGPUHostClock
    var backendDisplayName: String { "SYNTHETIC GPU TIMING" }
    var adapterIsSoftware = false
    var isSupported = true
    private(set) var isEnabled = false
    private(set) var events: [Event] = []
    private(set) var queryPollCount = 0
    private(set) var backendDiagnosticsReadCount = 0
    private(set) var renderAttemptCount: UInt64 = 0
    private(set) var lastFrameSubmission: BackendFrameSubmission?
    private var pendingFrameIDs: [BackendFrameID] = []
    var completedResults: [GPUFrameTimingResult] = []
    var resultsOnDetach: [GPUFrameTimingResult] = []
    var nextSubmission: BackendFrameSubmission?
    var failNextRender = false
    var adapterIsSoftwareAfterNextRender: Bool?

    init(clock: LiveGPUHostClock) {
        self.clock = clock
    }

    var backendDiagnostics: BatchBackendDiagnostics? {
        backendDiagnosticsReadCount += 1
        clock.now += clock.backendDiagnosticsSeconds
        return BatchBackendDiagnostics(
            adapterDescription: "Synthetic adapter", adapterIsSoftware: adapterIsSoftware,
            lastSubmitSeconds: 0.0007, lastPresentSeconds: 0.0013)
    }

    var gpuFrameTimingDiagnostics: GPUFrameTimingDiagnostics? {
        events.append(.snapshot(enabled: isEnabled, pending: pendingFrameIDs.count))
        return GPUFrameTimingDiagnostics(
            isEnabled: isEnabled, isSupported: isSupported, pendingCount: pendingFrameIDs.count)
    }

    func setGPUFrameTimingEnabled(_ enabled: Bool) -> Bool {
        events.append(.setEnabled(enabled))
        guard isSupported else { return false }
        isEnabled = enabled
        if !enabled {
            completedResults.append(
                contentsOf: pendingFrameIDs.map {
                    GPUFrameTimingResult(frameID: $0, status: .cancelled)
                })
            pendingFrameIDs.removeAll()
        }
        return true
    }

    func takeCompletedGPUFrameTimings() -> [GPUFrameTimingResult] {
        events.append(.takeCompleted(enabled: isEnabled))
        if isEnabled {
            queryPollCount += 1
            clock.now += clock.gpuPollSeconds
        }
        let results = completedResults
        completedResults.removeAll()
        let completedIDs = Set(results.map(\.frameID))
        pendingFrameIDs.removeAll { completedIDs.contains($0) }
        return results
    }

    func attach(to surface: SurfaceDescriptor) throws { try base.attach(to: surface) }
    func resize(to size: IntSize) throws { try base.resize(to: size) }

    func bindResources(for scene: GPUIScene) {
        clock.now += clock.bindSeconds
        base.bindResources(for: scene)
    }

    func render(scene: GPUIScene) throws {
        renderAttemptCount += 1
        // Replace the snapshot before every attempt, even if it skips or
        // fails. The host must never associate the preceding ID with it.
        let submission =
            nextSubmission
            ?? BackendFrameSubmission(
                id: BackendFrameID(deviceGeneration: 1, frameNumber: renderAttemptCount),
                outcome: .submitted,
                gpuTimingStatus: isEnabled ? .pending : .disabled,
                adapterIsSoftware: adapterIsSoftware)
        nextSubmission = nil
        lastFrameSubmission = submission
        if isEnabled, submission.gpuTimingStatus == .pending, let id = submission.id {
            pendingFrameIDs.append(id)
        }
        clock.now += clock.renderSeconds
        if let replacement = adapterIsSoftwareAfterNextRender {
            adapterIsSoftware = replacement
            adapterIsSoftwareAfterNextRender = nil
        }
        if failNextRender {
            failNextRender = false
            throw FakeRenderBackendError.renderFailure
        }
        guard submission.outcome != .skipped else { return }
        try base.render(scene: scene)
    }

    func detach() {
        events.append(.detach)
        base.detach()
        completedResults.append(contentsOf: resultsOnDetach)
        resultsOnDetach.removeAll()
        pendingFrameIDs.removeAll()
        // A recovery path may replace these values immediately. The sample
        // still needs the original attempt's ID and adapter classification.
        lastFrameSubmission = BackendFrameSubmission(outcome: .aborted, gpuTimingStatus: .cancelled)
        adapterIsSoftware = true
    }
}

@MainActor
private struct LiveGPUHostHarness {
    let host: WinSwiftUIWindowHost
    let window: Win32Window
    let backend: LiveGPUHostBatchBackend
    let frameBackend: FakeRenderBackend
    let clock: LiveGPUHostClock

    func present(at timestamp: Double) {
        clock.now = timestamp
        host.requestDiagnosticsFrame()
        host.windowNeedsDisplay(window)
    }
}

@MainActor
final class LiveGPUFrameTimingHostTests: XCTestCase {
    private func makeHost() -> LiveGPUHostHarness {
        let clock = LiveGPUHostClock()
        let backend = LiveGPUHostBatchBackend(clock: clock)
        let frameBackend = FakeRenderBackend()
        let size = IntSize(width: 64, height: 48)
        let window = Win32Window(title: "GPU timing host test", clientSize: size)
        window.testScaleFactorOverride = 1
        window.testMonitorRefreshRateOverride = 60
        let surface = SurfaceDescriptor(
            windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
            pixelSize: size, scaleFactor: 1)
        let host = WinSwiftUIWindowHost(
            configuration: WindowGroupConfiguration(
                title: "GPU timing host test", size: size, clearColor: .black, content: []),
            platformWindow: window,
            renderer: frameBackend,
            batchRenderer: backend,
            surfaceDescriptorProvider: { _ in surface },
            sceneRenderer: { runtime, timestamp in
                let scene = runtime.renderScene(at: timestamp)
                clock.now += clock.sceneSeconds
                return scene
            },
            startupPresentationMode: .automatic,
            startupProbeConfiguration: nil,
            recoveryPolicy: .disabled)
        host.frameClock = { clock.now }
        host.recoveryClock = { clock.now }
        host.hostedRuntime.clock = { clock.now }
        host.windowDidCreate(window)
        clock.sceneSeconds = 0.001
        clock.bindSeconds = 0.001
        clock.renderSeconds = 0.002
        return LiveGPUHostHarness(
            host: host, window: window, backend: backend, frameBackend: frameBackend, clock: clock)
    }

    private func outputURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("swift-windowsui-gpu-host-\(UUID().uuidString).json")
    }

    private func object(_ parent: [String: Any], _ key: String) throws -> [String: Any] {
        try XCTUnwrap(parent[key] as? [String: Any], "Missing report object \(key)")
    }

    func testUnsupportedBackendDefaultsDoNotManufactureGPUCapabilitiesOrMeasurements() async {
        let backend: any BatchRenderBackend = FakeBatchRenderBackend()
        XCTAssertNil(backend.lastFrameSubmission)
        XCTAssertNil(backend.gpuFrameTimingDiagnostics)
        XCTAssertFalse(backend.setGPUFrameTimingEnabled(true))
        XCTAssertTrue(backend.takeCompletedGPUFrameTimings().isEmpty)
        XCTAssertFalse(backend.setGPUFrameTimingEnabled(false))
    }

    func testClosedHostRejectsCollectionRestartWhileAllowingFinalDrain() async {
        let harness = makeHost()
        XCTAssertTrue(harness.host.setGPUFrameTimingEnabled(true))
        let terminal = GPUFrameTimingResult(
            frameID: BackendFrameID(deviceGeneration: 3, frameNumber: 9), status: .cancelled)
        harness.backend.resultsOnDetach = [terminal]

        harness.host.windowWillClose(harness.window)
        let eventsAfterClose = harness.backend.events
        XCTAssertFalse(harness.host.setGPUFrameTimingEnabled(true))
        XCTAssertEqual(harness.backend.events, eventsAfterClose, "A closed host cannot restart its collector")
        XCTAssertTrue(harness.host.setGPUFrameTimingEnabled(false))
        XCTAssertEqual(harness.host.takeCompletedGPUFrameTimings(), [terminal])
        XCTAssertTrue(harness.host.takeCompletedGPUFrameTimings().isEmpty)

        let eventsAfterDrain = harness.backend.events
        harness.host.windowWillClose(harness.window)
        XCTAssertEqual(harness.backend.events, eventsAfterDrain)
    }

    func testGPUTimingFlagRequiresExplicitDiagnosticsOptIn() async throws {
        XCTAssertFalse(LiveDiagnosticsConfiguration().collectsGPUFrameTimings)
        let ordinary = try XCTUnwrap(
            LiveDiagnosticsConfiguration.fromCommandLine(["app", "--diagnostics"], environment: [:]))
        XCTAssertFalse(ordinary.collectsGPUFrameTimings)
        let requested = try XCTUnwrap(
            LiveDiagnosticsConfiguration.fromCommandLine(
                ["app", "--diagnostics", "--diagnostics-gpu-timing"], environment: [:]))
        XCTAssertTrue(requested.collectsGPUFrameTimings)
        XCTAssertNil(
            LiveDiagnosticsConfiguration.fromCommandLine(["app", "--diagnostics-gpu-timing"], environment: [:]),
            "The timing flag alone must not start a diagnostics session")
    }

    func testSessionWithoutTimingMakesNoGPUCollectionCalls() async throws {
        let harness = makeHost()
        let output = outputURL()
        defer { try? FileManager.default.removeItem(at: output) }
        var closeRequests = 0
        let session = LiveDiagnosticsSession(
            configuration: LiveDiagnosticsConfiguration(
                durationSeconds: 60, outputPath: output.path, exercisesInput: false),
            host: harness.host,
            clock: { harness.clock.now },
            requestClose: { closeRequests += 1 },
            report: { _ in })
        session.start()
        harness.present(at: 1_002)
        session.finish()

        XCTAssertTrue(harness.backend.events.isEmpty)
        XCTAssertEqual(harness.backend.queryPollCount, 0)
        XCTAssertFalse(harness.backend.isEnabled)
        XCTAssertEqual(closeRequests, 1)
        XCTAssertNil(harness.host.onFramePresented)
        XCTAssertNotNil(try JSONSerialization.jsonObject(with: Data(contentsOf: output)) as? [String: Any])

        session.finish()
        XCTAssertEqual(closeRequests, 1)
        XCTAssertTrue(harness.backend.events.isEmpty)
    }

    func testSessionGetterAndPollingCostsStayOutsideLegacyCPUFrameTimings() async throws {
        for requestsGPUTiming in [false, true] {
            let harness = makeHost()
            harness.clock.backendDiagnosticsSeconds = 0.050
            harness.clock.gpuPollSeconds = 0.075
            let output = outputURL()
            defer { try? FileManager.default.removeItem(at: output) }
            var closeRequests = 0
            let session = LiveDiagnosticsSession(
                configuration: LiveDiagnosticsConfiguration(
                    durationSeconds: 60, outputPath: output.path, exercisesInput: false,
                    collectsGPUFrameTimings: requestsGPUTiming),
                host: harness.host,
                clock: { harness.clock.now },
                requestClose: { closeRequests += 1 },
                report: { _ in })
            session.start()
            let recordInSession = try XCTUnwrap(harness.host.onFramePresented)
            var samples: [LiveFrameSample] = []
            harness.host.onFramePresented = { sample in
                samples.append(sample)
                // Keep the actual session callback, including its result
                // polling, instead of replacing it with a passive recorder.
                recordInSession(sample)
            }
            let getterReadsBeforeFrame = harness.backend.backendDiagnosticsReadCount
            let queryPollsBeforeFrame = harness.backend.queryPollCount

            harness.present(at: 1_002)

            XCTAssertEqual(samples.count, 1)
            let sample = try XCTUnwrap(samples.last)
            XCTAssertEqual(sample.totalSeconds, 0.004, accuracy: 0.000_000_001)
            XCTAssertEqual(sample.sceneBuildSeconds, 0.001, accuracy: 0.000_000_001)
            XCTAssertEqual(sample.bindSeconds, 0.001, accuracy: 0.000_000_001)
            XCTAssertEqual(sample.submitAndPresentSeconds, 0.002, accuracy: 0.000_000_001)
            XCTAssertEqual(sample.userVisibleCostSeconds, 0.004, accuracy: 0.000_000_001)
            XCTAssertEqual(sample.presentedAt, 1_002.004, accuracy: 0.000_000_001)
            XCTAssertEqual(
                harness.backend.backendDiagnosticsReadCount - getterReadsBeforeFrame, 1,
                "Only the existing post-timer backend diagnostics read is allowed")
            XCTAssertEqual(harness.backend.queryPollCount - queryPollsBeforeFrame, requestsGPUTiming ? 1 : 0)
            XCTAssertEqual(
                harness.clock.now, 1_002.004 + 0.050 + (requestsGPUTiming ? 0.075 : 0),
                accuracy: 0.000_000_001,
                "The injected diagnostics costs ran, but must not change the frame's recorded CPU interval")

            session.finish()
            XCTAssertEqual(closeRequests, 1)
            let completedReport = try XCTUnwrap(
                JSONSerialization.jsonObject(with: Data(contentsOf: output)) as? [String: Any])
            let measurement = try object(completedReport, "measurement")
            XCTAssertEqual(measurement["backendPhaseZeroMayMeanUncompleted"] as? Bool, true)
            if !requestsGPUTiming {
                XCTAssertTrue(harness.backend.events.isEmpty)
                XCTAssertEqual(harness.backend.queryPollCount, 0)
            }
        }
    }

    func testIssuingAdapterSnapshotSurvivesRenderChangesAndUnknownMetadataStaysUnknown() async throws {
        let harness = makeHost()
        var samples: [LiveFrameSample] = []
        harness.host.onFramePresented = { samples.append($0) }
        XCTAssertTrue(harness.host.setGPUFrameTimingEnabled(true))
        harness.backend.adapterIsSoftwareAfterNextRender = true

        harness.present(at: 1_001)

        let issued = try XCTUnwrap(samples.last)
        XCTAssertEqual(issued.backendFrameSubmission?.adapterIsSoftware, false)
        XCTAssertEqual(issued.gpuTimingAdapterIsSoftware, false)
        XCTAssertTrue(harness.backend.adapterIsSoftware, "The current adapter changed while the attempt was rendering")

        harness.backend.adapterIsSoftware = false
        harness.backend.adapterIsSoftwareAfterNextRender = true
        harness.backend.nextSubmission = BackendFrameSubmission(
            id: BackendFrameID(deviceGeneration: 2, frameNumber: 1),
            outcome: .submitted, gpuTimingStatus: .pending, adapterIsSoftware: nil)
        harness.present(at: 1_001.1)

        let coldDevice = try XCTUnwrap(samples.last)
        XCTAssertEqual(coldDevice.backendFrameSubmission?.id?.deviceGeneration, 2)
        XCTAssertNil(coldDevice.backendFrameSubmission?.adapterIsSoftware)
        XCTAssertNil(
            coldDevice.gpuTimingAdapterIsSoftware,
            "Unknown issuing-device metadata must not be filled from the current post-timer diagnostics getter")
        XCTAssertTrue(coldDevice.backendTimingsAvailable)
        XCTAssertTrue(harness.backend.adapterIsSoftware)
    }

    func testOptedInSessionPollsPerSampleAndFinishesWithSnapshotThenCancellationDrain() async throws {
        let harness = makeHost()
        let output = outputURL()
        defer { try? FileManager.default.removeItem(at: output) }
        let firstID = BackendFrameID(deviceGeneration: 5, frameNumber: 41)
        let pendingID = BackendFrameID(deviceGeneration: 5, frameNumber: 42)
        // An old collector result must be discarded before enabling this run.
        harness.backend.completedResults = [
            GPUFrameTimingResult(
                frameID: BackendFrameID(deviceGeneration: 4, frameNumber: 1), status: .valid, elapsedSeconds: 0.9)
        ]
        var closeRequests = 0
        let session = LiveDiagnosticsSession(
            configuration: LiveDiagnosticsConfiguration(
                durationSeconds: 60, outputPath: output.path, exercisesInput: false, collectsGPUFrameTimings: true),
            host: harness.host,
            clock: { harness.clock.now },
            requestClose: { closeRequests += 1 },
            report: { _ in })
        session.start()
        XCTAssertEqual(harness.backend.events, [.takeCompleted(enabled: false), .setEnabled(true)])

        harness.backend.nextSubmission = BackendFrameSubmission(
            id: firstID, outcome: .submitted, gpuTimingStatus: .pending, adapterIsSoftware: false)
        harness.present(at: 1_002)
        XCTAssertEqual(harness.backend.queryPollCount, 1)
        harness.backend.completedResults = [
            GPUFrameTimingResult(frameID: firstID, status: .valid, elapsedSeconds: 0.005)
        ]
        harness.backend.nextSubmission = BackendFrameSubmission(
            id: pendingID, outcome: .submitted, gpuTimingStatus: .pending, adapterIsSoftware: false)
        harness.present(at: 1_002.1)
        XCTAssertEqual(harness.backend.queryPollCount, 2)

        harness.clock.now = 1_003
        session.finish()

        XCTAssertEqual(
            harness.backend.events,
            [
                .takeCompleted(enabled: false), .setEnabled(true),
                .takeCompleted(enabled: true), .takeCompleted(enabled: true),
                .takeCompleted(enabled: true), .snapshot(enabled: true, pending: 1),
                .setEnabled(false), .takeCompleted(enabled: false),
            ])
        XCTAssertEqual(harness.backend.queryPollCount, 3, "Disabling drains cancellations without another query poll")
        XCTAssertFalse(harness.backend.isEnabled)
        XCTAssertEqual(closeRequests, 1)
        XCTAssertNil(harness.host.onFramePresented)

        let data = try Data(contentsOf: output)
        let report = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let gpu = try object(report, "gpu")
        let collector = try object(gpu, "collectorLifetime")
        XCTAssertEqual(collector["isEnabledAtFinish"] as? Bool, true)
        XCTAssertEqual(collector["pendingAtFinish"] as? Int, 1)
        let join = try object(gpu, "sessionJoin")
        XCTAssertEqual(join["resultCount"] as? Int, 2)
        XCTAssertEqual(join["matchedPostWarmupResultCount"] as? Int, 2)
        let postWarmup = try object(gpu, "postWarmup")
        let statuses = try object(postWarmup, "timingStatusCounts")
        XCTAssertEqual(statuses["valid"] as? Int, 1)
        XCTAssertEqual(statuses["cancelled"] as? Int, 1)

        let finishedEvents = harness.backend.events
        session.finish()
        XCTAssertEqual(closeRequests, 1)
        XCTAssertEqual(harness.backend.events, finishedEvents)
        XCTAssertEqual(try Data(contentsOf: output), data, "A second finish must not rewrite the report")
    }

    func testHostUsesFreshSubmissionMetadataAndKeepsCPUTimingIndependent() async throws {
        let harness = makeHost()
        var samples: [LiveFrameSample] = []
        harness.host.onFramePresented = { samples.append($0) }
        XCTAssertTrue(harness.host.setGPUFrameTimingEnabled(true))
        let issuedID = BackendFrameID(deviceGeneration: 7, frameNumber: 1)
        harness.backend.nextSubmission = BackendFrameSubmission(
            id: issuedID, outcome: .submitted, gpuTimingStatus: .pending, adapterIsSoftware: false)
        harness.present(at: 1_001)
        let issued = try XCTUnwrap(samples.last)
        XCTAssertEqual(issued.backendFrameSubmission?.id, issuedID)
        XCTAssertEqual(issued.gpuTimingAdapterIsSoftware, false)

        harness.backend.nextSubmission = BackendFrameSubmission(outcome: .skipped, gpuTimingStatus: .notIssued)
        harness.present(at: 1_001.1)
        XCTAssertEqual(samples.count, 2)
        let skipped = try XCTUnwrap(samples.last)
        XCTAssertEqual(skipped.backendFrameSubmission?.outcome, .skipped)
        XCTAssertEqual(skipped.backendFrameSubmission?.gpuTimingStatus, .notIssued)
        XCTAssertNil(skipped.backendFrameSubmission?.id, "A skipped attempt must not reuse the last successful ID")
        for sample in [issued, skipped] {
            XCTAssertEqual(sample.totalSeconds, 0.004, accuracy: 0.000_000_001)
            XCTAssertEqual(sample.sceneBuildSeconds, 0.001, accuracy: 0.000_000_001)
            XCTAssertEqual(sample.bindSeconds, 0.001, accuracy: 0.000_000_001)
            XCTAssertEqual(sample.submitAndPresentSeconds, 0.002, accuracy: 0.000_000_001)
            XCTAssertEqual(sample.userVisibleCostSeconds, 0.004, accuracy: 0.000_000_001)
        }

        harness.host.hostedRuntime.scheduleDeferredRebuild(key: "waiting-gpu-host-test", delay: 100) {}
        harness.present(at: 1_001.2)
        let samplesBeforeIdenticalFrame = samples.count
        let attemptsBeforeIdenticalFrame = harness.backend.renderAttemptCount
        harness.present(at: 1_001.3)
        XCTAssertEqual(harness.host.skippedIdenticalPresentCount, 1)
        XCTAssertEqual(samples.count, samplesBeforeIdenticalFrame)
        XCTAssertEqual(harness.backend.renderAttemptCount, attemptsBeforeIdenticalFrame)
    }

    func testFallbackKeepsIssuingMetadataAndDrainsResultsFromTheInactiveBatchBackend() async throws {
        let harness = makeHost()
        var samples: [LiveFrameSample] = []
        harness.host.onFramePresented = { samples.append($0) }
        XCTAssertTrue(harness.host.setGPUFrameTimingEnabled(true))
        let failedID = BackendFrameID(deviceGeneration: 9, frameNumber: 23)
        let failure = GPUFrameTimingResult(frameID: failedID, status: .deviceLost, failureCode: -1)
        harness.backend.nextSubmission = BackendFrameSubmission(
            id: failedID, outcome: .failed, gpuTimingStatus: .deviceLost, adapterIsSoftware: false)
        harness.backend.resultsOnDetach = [failure]
        harness.backend.failNextRender = true

        harness.present(at: 1_001)

        XCTAssertFalse(harness.host.isUsingScenePresentationBackend)
        let fallback = try XCTUnwrap(samples.last)
        XCTAssertEqual(fallback.backend, .frame)
        XCTAssertEqual(fallback.backendFrameSubmission?.id, failedID)
        XCTAssertEqual(fallback.backendFrameSubmission?.outcome, .failed)
        XCTAssertEqual(fallback.backendFrameSubmission?.gpuTimingStatus, .deviceLost)
        XCTAssertEqual(fallback.backendFrameSubmission?.adapterIsSoftware, false)
        XCTAssertEqual(fallback.gpuTimingAdapterIsSoftware, false)
        XCTAssertNil(harness.backend.lastFrameSubmission?.id, "Detach deliberately replaced the backend snapshot")
        XCTAssertTrue(harness.backend.adapterIsSoftware)

        let frameCount = harness.frameBackend.renderedFrames.count
        let batchAttempts = harness.backend.renderAttemptCount
        XCTAssertEqual(harness.host.takeCompletedGPUFrameTimings(), [failure])
        XCTAssertTrue(harness.host.takeCompletedGPUFrameTimings().isEmpty)
        XCTAssertEqual(harness.host.gpuFrameTimingDiagnostics?.isSupported, true)
        XCTAssertTrue(harness.host.setGPUFrameTimingEnabled(false))
        XCTAssertEqual(harness.frameBackend.renderedFrames.count, frameCount)
        XCTAssertEqual(harness.backend.renderAttemptCount, batchAttempts)

        harness.present(at: 1_001.1)
        let followingFrame = try XCTUnwrap(samples.last)
        XCTAssertNil(followingFrame.backendFrameSubmission)
        XCTAssertNil(followingFrame.gpuTimingAdapterIsSoftware)
    }
}
