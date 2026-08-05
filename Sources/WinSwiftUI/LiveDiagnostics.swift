import Foundation

import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsPlatform

// MARK: - Frame sample

/// One presented frame, as the host that presented it saw it.
///
/// Timings are wall-clock seconds from the host's frame clock, so they include
/// everything the main actor did for that frame — scene build, resource bind,
/// draw submission and present. That is deliberately the user-visible number
/// and not a GPU timer query: a frame the GPU finished in 2 ms that the UI
/// thread took 30 ms to hand it is a 30 ms frame to the person looking at the
/// window.
struct LiveFrameSample {
    var presentedAt: Double
    var totalSeconds: Double
    var sceneBuildSeconds: Double
    /// `bindResources` — atlas and image uploads.
    var bindSeconds: Double
    /// Backend-reported split of `render(scene:)`: work issued vs time spent
    /// waiting in `Present`.
    var backendSubmitSeconds: Double
    var backendPresentSeconds: Double
    /// `render(scene:)` — draw submission plus `Present`. Split out from the
    /// scene build because "the frame is slow" and "the paint is slow" are
    /// different bugs with different owners, and the whole-frame number alone
    /// cannot tell them apart.
    var submitAndPresentSeconds: Double
    var didRebuildScene: Bool
    var nodeReplayCount: Int
    var primitiveCount: Int
    var hadActiveAnimations: Bool
    var backend: PresentationBackendKind
    var atlasUploadedByteCount: UInt64
}

// MARK: - Configuration

/// How to run a live diagnostics session.
///
/// Parsed from the process arguments so the shipping executable carries the
/// mode — a diagnostics build that has to be produced specially is a
/// diagnostics build nobody runs when it matters.
public struct LiveDiagnosticsConfiguration: Equatable, Sendable {
    /// Wall-clock seconds the window stays open before it closes itself. A
    /// live run that does not close itself is a run that cannot be scripted.
    public var durationSeconds: Double
    /// Where the JSON report is written.
    public var outputPath: String
    /// Whether the session drives scripted input (hover sweep, scroll bursts,
    /// screen switches) through the host's normal input entry points.
    public var exercisesInput: Bool
    /// Whether to unpace presents for the run, so frame times measure the
    /// app's own cost rather than the compositor's vblank wait.
    public var disablesVSync: Bool

    public init(
        durationSeconds: Double = 10,
        outputPath: String = "artifacts/live-diagnostics.json",
        exercisesInput: Bool = true,
        disablesVSync: Bool = false
    ) {
        self.durationSeconds = max(0.5, durationSeconds)
        self.outputPath = outputPath
        self.exercisesInput = exercisesInput
        self.disablesVSync = disablesVSync
    }

    /// `--diagnostics [--diagnostics-seconds N] [--diagnostics-output PATH]
    /// [--diagnostics-no-input]`, or `SWIFT_WINDOWSUI_DIAGNOSTICS=1` with the
    /// matching `_SECONDS` / `_OUTPUT` variables.
    public static func fromCommandLine(
        _ arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> LiveDiagnosticsConfiguration? {
        let requestedByFlag = arguments.contains("--diagnostics")
        let requestedByEnvironment = environment["SWIFT_WINDOWSUI_DIAGNOSTICS"]?.lowercased()
        let isEnvironmentTruthy = ["1", "true", "yes", "on"].contains(requestedByEnvironment ?? "")
        guard requestedByFlag || isEnvironmentTruthy else {
            return nil
        }

        var configuration = LiveDiagnosticsConfiguration()

        if let seconds = value(of: "--diagnostics-seconds", in: arguments)
            ?? environment["SWIFT_WINDOWSUI_DIAGNOSTICS_SECONDS"],
            let parsed = Double(seconds)
        {
            configuration.durationSeconds = max(0.5, parsed)
        }

        if let path = value(of: "--diagnostics-output", in: arguments)
            ?? environment["SWIFT_WINDOWSUI_DIAGNOSTICS_OUTPUT"],
            !path.isEmpty
        {
            configuration.outputPath = path
        }

        if arguments.contains("--diagnostics-no-input") {
            configuration.exercisesInput = false
        }

        if arguments.contains("--diagnostics-no-vsync") {
            configuration.disablesVSync = true
        }

        return configuration
    }

    private static func value(of flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
            return nil
        }
        return arguments[index + 1]
    }
}

// MARK: - Session

/// Drives one live diagnostics run against a real window and writes what it
/// measured.
///
/// The whole point is that this runs against the window the user actually
/// sees. Every number here is unavailable to the offscreen snapshot path: the
/// snapshot renders through the CPU rasterizer at a scale it was told, with no
/// swap chain, no vsync, no message loop and no animation timer. It can prove
/// what a frame *contains* and nothing about what a session *does*.
@MainActor
final class LiveDiagnosticsSession {
    private let configuration: LiveDiagnosticsConfiguration
    private weak var host: WinSwiftUIWindowHost?
    private let clock: () -> Double
    private let report: (String) -> Void

    private var startedAt: Double?
    private var samples: [LiveFrameSample] = []
    private var isFinished = false
    /// Uploads recorded once the session considers the atlas warm, so a
    /// steady-state per-frame cost can be separated from the first-paint
    /// population of an empty atlas.
    private var warmupEndedAt: Double?
    private var atlasBytesAtWarmupEnd: UInt64 = 0
    private var scriptedStepIndex = 0
    private var didExhaustScript = false
    private var didDisableVSync = false

    /// Seconds of the run treated as warmup. The first frames populate the
    /// glyph atlas, compile nothing (shaders are already in the binary) but do
    /// build every cache in the stack; averaging them into the steady state
    /// would let a slow steady state hide behind a fast start, or the reverse.
    private static let warmupSeconds: Double = 1.5

    init(
        configuration: LiveDiagnosticsConfiguration,
        host: WinSwiftUIWindowHost,
        clock: @escaping () -> Double = { Date().timeIntervalSince1970 },
        report: @escaping (String) -> Void = { print("[WinSwiftUI] \($0)") }
    ) {
        self.configuration = configuration
        self.host = host
        self.clock = clock
        self.report = report
    }

    /// Installs the frame hook and starts the clock. The session drives itself
    /// from the host's own animation timer from here on.
    func start() {
        startedAt = clock()
        if configuration.disablesVSync {
            didDisableVSync = host?.setActiveBatchBackendVSync(false) ?? false
        }
        host?.onFramePresented = { [weak self] sample in
            self?.record(sample)
        }
        // The host runs its timer only while something is dirty or animating —
        // correct idle behaviour, and also why the session pumps a frame
        // request after every frame it records. What that makes the frame-rate
        // figure is a *sustained throughput* measurement of the real window,
        // not evidence that the app repaints continuously when nothing is
        // happening; the `animation` block reports the idle side separately.
        host?.requestDiagnosticsFrame()

        // Independent of the frame loop on purpose. If the presenter never
        // attaches, or a frame stalls, no sample is ever recorded and nothing
        // in `record` can fire — the run has to close the window anyway.
        host?.platformWindow.scheduleCloseWatchdog(
            afterSeconds: configuration.durationSeconds + Self.watchdogGraceSeconds)

        report(
            "Live diagnostics: \(String(format: "%.1f", configuration.durationSeconds))s run, "
                + "writing \(configuration.outputPath)."
        )
    }

    /// How long past the requested duration the watchdog waits before closing
    /// the window itself. Long enough that the orderly finish wins every
    /// normal run; short enough that a stalled run still ends.
    private static let watchdogGraceSeconds: Double = 5

    private func record(_ sample: LiveFrameSample) {
        guard !isFinished, let startedAt else {
            return
        }

        samples.append(sample)
        host?.requestDiagnosticsFrame()

        let elapsed = clock() - startedAt
        if warmupEndedAt == nil, elapsed >= Self.warmupSeconds {
            warmupEndedAt = elapsed
            atlasBytesAtWarmupEnd = sample.atlasUploadedByteCount
        }

        if configuration.exercisesInput {
            advanceScript(elapsed: elapsed)
        }

        if elapsed >= configuration.durationSeconds {
            finish()
        }
    }

    // MARK: - Scripted interaction

    /// One scripted interaction, and the elapsed time it fires at.
    private struct ScriptStep {
        var atSeconds: Double
        var name: String
        var action: @MainActor (WinSwiftUIWindowHost) -> Void
    }

    /// A hover sweep, two scroll bursts and two screen switches, on the
    /// window's real input entry points.
    ///
    /// These go through `WinSwiftUIWindowHost`'s `Win32Window` delegate
    /// methods — the same ones the wndproc calls — rather than through
    /// `RetainedViewRuntime` directly, so the measurement covers the
    /// coordinate conversion, the input-rate tracker and the frame-request
    /// policy, which is where a live session's cost actually lives.
    private lazy var script: [ScriptStep] = {
        var steps: [ScriptStep] = []

        // Hover sweep: 24 pointer moves across the window over 1.2s.
        for index in 0..<24 {
            let progress = Double(index) / 23.0
            steps.append(
                ScriptStep(atSeconds: 1.6 + progress * 1.2, name: "hover") { host in
                    let size = host.currentLogicalRootSize
                    let point = Point(
                        x: Double(size.width) * (0.08 + 0.84 * progress),
                        y: Double(size.height) * (0.20 + 0.55 * progress)
                    )
                    host.injectDiagnosticsPointerMove(to: point)
                }
            )
        }

        // Scroll bursts: notches down then up, each triggering momentum.
        for index in 0..<12 {
            let progress = Double(index) / 11.0
            steps.append(
                ScriptStep(atSeconds: 3.2 + progress * 1.6, name: "scroll-down") { host in
                    let size = host.currentLogicalRootSize
                    host.injectDiagnosticsScroll(
                        at: Point(x: Double(size.width) * 0.6, y: Double(size.height) * 0.6),
                        delta: -120
                    )
                }
            )
        }
        for index in 0..<12 {
            let progress = Double(index) / 11.0
            steps.append(
                ScriptStep(atSeconds: 5.2 + progress * 1.6, name: "scroll-up") { host in
                    let size = host.currentLogicalRootSize
                    host.injectDiagnosticsScroll(
                        at: Point(x: Double(size.width) * 0.6, y: Double(size.height) * 0.6),
                        delta: 120
                    )
                }
            )
        }

        // Screen switches: the sidebar sits in the left column, so a click at
        // a fixed fraction of it lands on a navigation row for any reasonable
        // window size. A miss costs the switch, not the run.
        let switchTargets: [(Double, Double, Double)] = [
            (7.2, 0.08, 0.28),
            (8.0, 0.08, 0.36),
            (8.8, 0.08, 0.20),
        ]
        for (at, xFraction, yFraction) in switchTargets {
            steps.append(
                ScriptStep(atSeconds: at, name: "screen-switch") { host in
                    let size = host.currentLogicalRootSize
                    let point = Point(
                        x: Double(size.width) * xFraction,
                        y: Double(size.height) * yFraction
                    )
                    host.injectDiagnosticsClick(at: point)
                }
            )
        }

        return steps.sorted { $0.atSeconds < $1.atSeconds }
    }()

    private var executedStepCounts: [String: Int] = [:]

    private func advanceScript(elapsed: Double) {
        guard let host, !didExhaustScript else {
            return
        }

        while scriptedStepIndex < script.count, script[scriptedStepIndex].atSeconds <= elapsed {
            let step = script[scriptedStepIndex]
            scriptedStepIndex += 1
            step.action(host)
            executedStepCounts[step.name, default: 0] += 1
        }

        if scriptedStepIndex >= script.count {
            didExhaustScript = true
        }
    }

    // MARK: - Completion

    /// Writes the report and asks the window to close. Idempotent: a frame
    /// delivered between the close request and `WM_DESTROY` must not write a
    /// second report or re-request the close.
    func finish() {
        guard !isFinished else {
            return
        }
        isFinished = true

        guard let host else {
            return
        }
        host.onFramePresented = nil

        do {
            let json = try buildReportJSON(host: host)
            try writeReport(json)
            report("Live diagnostics written to \(configuration.outputPath).")
        } catch {
            report("Live diagnostics could not write \(configuration.outputPath): \(error)")
        }

        host.platformWindow.requestClose()
    }

    private func writeReport(_ data: Data) throws {
        let url = URL(fileURLWithPath: configuration.outputPath)
        let directory = url.deletingLastPathComponent()
        if !directory.path.isEmpty {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Report

    private func buildReportJSON(host: WinSwiftUIWindowHost) throws -> Data {
        let health = host.rendererHealthSnapshot
        let window = host.platformWindow
        let pixelSize = window.currentClientSize()
        let logicalSize = host.currentLogicalRootSize
        let refreshRate = max(Int(window.monitorRefreshRate), 1)
        let elapsed = startedAt.map { clock() - $0 } ?? 0

        let steadyStateSamples = samples.filter { sample in
            guard let startedAt, warmupEndedAt != nil else { return false }
            return sample.presentedAt > 0 && (clock() - startedAt) > 0
                && sampleElapsed(sample) >= Self.warmupSeconds
        }
        let timedSamples = steadyStateSamples.isEmpty ? samples : steadyStateSamples

        var report: [String: Any] = [:]

        report["schema"] = "swift-windowsui.live-diagnostics/1"
        report["durationSecondsRequested"] = configuration.durationSeconds
        report["durationSecondsActual"] = elapsed
        report["exercisedInput"] = configuration.exercisesInput
        report["vsyncDisabledForRun"] = didDisableVSync
        report["vsyncDisableRequested"] = configuration.disablesVSync
        report["scriptedStepsExecuted"] = executedStepCounts

        report["backend"] = [
            "activeBackend": health.activeBackend.rawValue,
            "activeBackendDisplayName": health.activeBackendDisplayName ?? "<none>",
            "selectionReason": health.lastBackendSelectionReason?.probeCode ?? "<none>",
            "selectionDetail": health.lastBackendSelectionReason?.detail ?? "",
            "failureKind": health.lastPresentationFailureKind.map { String(describing: $0) } ?? "<none>",
            "isPresenterUnavailable": health.isPresenterUnavailable,
            "isPresentationOccluded": health.isPresentationOccluded,
            "recoveryPolicyEnabled": health.recoveryPolicyEnabled,
            "requestedFactory": health.backendResolution?.requestedFactoryName ?? "<none>",
            "resolvedFactory": health.backendResolution?.resolvedFactoryName ?? "<none>",
            "isDegradedPresentation": health.backendResolution?.isDegradedPresentation ?? false,
            "availability": health.backendResolution.map { String(describing: $0.availability) } ?? "<none>",
        ]

        if let diagnostics = host.activeBatchBackendDiagnostics {
            report["adapter"] = [
                "description": diagnostics.adapterDescription ?? "<unavailable>",
                "isSoftware": diagnostics.adapterIsSoftware as Any,
                "dedicatedVideoMemoryBytes": diagnostics.adapterDedicatedVideoMemoryBytes as Any,
                "featureLevel": diagnostics.featureLevel ?? "<unavailable>",
            ]
            let warmBytes =
                diagnostics.atlasUploadedByteCount >= atlasBytesAtWarmupEnd
                ? diagnostics.atlasUploadedByteCount - atlasBytesAtWarmupEnd : 0
            report["atlas"] = [
                "fullUploadCount": diagnostics.atlasFullUploadCount,
                "regionUploadCount": diagnostics.atlasRegionUploadCount,
                "skippedUploadCount": diagnostics.atlasSkippedUploadCount,
                "uploadedByteCountTotal": diagnostics.atlasUploadedByteCount,
                "uploadedByteCountAfterWarmup": warmBytes,
                "uploadedBytesPerFrameAfterWarmup": timedSamples.isEmpty
                    ? 0 : Double(warmBytes) / Double(timedSamples.count),
            ]
        } else {
            report["adapter"] = ["description": "<no batch backend attached>"]
        }

        report["display"] = [
            "reportedDpi": Int((window.scaleFactor * 96).rounded()),
            "rawScaleFactor": window.scaleFactor,
            "effectiveScaleFactor": window.effectiveScaleFactor,
            "runtimeDisplayScale": health.displayScale,
            "monitorRefreshRateHz": refreshRate,
            "windowPixelSize": ["width": Int(pixelSize.width), "height": Int(pixelSize.height)],
            "windowLogicalSize": ["width": Int(logicalSize.width), "height": Int(logicalSize.height)],
        ]

        let frameTimesMs = timedSamples.map { $0.totalSeconds * 1000 }.sorted()
        let sceneBuildMs = timedSamples.map { $0.sceneBuildSeconds * 1000 }.sorted()
        let bindMs = timedSamples.map { $0.bindSeconds * 1000 }.sorted()
        let submitMs = timedSamples.map { $0.submitAndPresentSeconds * 1000 }.sorted()
        let backendSubmitMs = timedSamples.map { $0.backendSubmitSeconds * 1000 }.sorted()
        let backendPresentMs = timedSamples.map { $0.backendPresentSeconds * 1000 }.sorted()
        let refreshIntervalMs = 1000.0 / Double(refreshRate)
        let droppedEstimate = frameTimesMs.filter { $0 > refreshIntervalMs * 1.5 }.count

        report["frames"] = [
            "presentedTotal": samples.count,
            "presentedAfterWarmup": timedSamples.count,
            "warmupSeconds": Self.warmupSeconds,
            "framesPerSecondOverRun": elapsed > 0 ? Double(samples.count) / elapsed : 0,
            "frameTimeMs": percentileSummary(frameTimesMs),
            "sceneBuildMs": percentileSummary(sceneBuildMs),
            "bindResourcesMs": percentileSummary(bindMs),
            "submitAndPresentMs": percentileSummary(submitMs),
            "backendSubmitMs": percentileSummary(backendSubmitMs),
            "backendPresentMs": percentileSummary(backendPresentMs),
            "refreshIntervalMs": refreshIntervalMs,
            "framesOverRefreshBudget": droppedEstimate,
            "framesOverRefreshBudgetFraction": frameTimesMs.isEmpty
                ? 0 : Double(droppedEstimate) / Double(frameTimesMs.count),
        ]

        let rebuilds = timedSamples.filter(\.didRebuildScene).count
        report["scene"] = [
            "runtimeSceneRebuildCount": host.hostedRuntime.sceneRebuildCount,
            "runtimeSceneCacheHitCount": host.hostedRuntime.sceneCacheHitCount,
            "framesThatRebuiltScene": rebuilds,
            "framesThatReplayedScene": timedSamples.count - rebuilds,
            "lastNodeReplayCount": samples.last?.nodeReplayCount ?? 0,
            "lastPrimitiveCount": samples.last?.primitiveCount ?? 0,
            "maxPrimitiveCount": samples.map(\.primitiveCount).max() ?? 0,
            "gpuPromotionRate": health.lastScenePaintMetrics.gpuPromotionRate,
            "pathsRasterizedOnCPU": health.lastScenePaintMetrics.pathsRasterizedOnCPU,
            "pathsPromotedToGPU": health.lastScenePaintMetrics.pathsPromotedToGPU,
        ]

        report["animation"] = [
            "hasActiveAnimationsAtEnd": health.hasActiveAnimations,
            "framesWithActiveAnimations": samples.filter(\.hadActiveAnimations).count,
            "timerEnabledAtEnd": host.currentTimerState.isEnabled,
            "timerIntervalMsAtEnd": host.currentTimerState.intervalMilliseconds,
            "timerUsesHighResolution": host.currentTimerState.usesHighResolution,
            "runtimeMinimumFrameIntervalSeconds": health.minimumFrameInterval as Any,
        ]

        return try JSONSerialization.data(
            withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    }

    private func sampleElapsed(_ sample: LiveFrameSample) -> Double {
        guard let firstSample = samples.first else { return 0 }
        return sample.presentedAt - firstSample.presentedAt
    }

    private func percentileSummary(_ sortedValues: [Double]) -> [String: Double] {
        guard !sortedValues.isEmpty else {
            return ["p50": 0, "p95": 0, "p99": 0, "max": 0, "mean": 0]
        }

        func percentile(_ fraction: Double) -> Double {
            let index = Int((Double(sortedValues.count - 1) * fraction).rounded())
            return sortedValues[min(max(index, 0), sortedValues.count - 1)]
        }

        return [
            "p50": percentile(0.50),
            "p95": percentile(0.95),
            "p99": percentile(0.99),
            "max": sortedValues[sortedValues.count - 1],
            "mean": sortedValues.reduce(0, +) / Double(sortedValues.count),
        ]
    }
}
