import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsPlatform

// MARK: - Frame sample

/// One frame returned by the backend, as timed by the host.
///
/// These are elapsed CPU seconds from the host's monotonic clock, including
/// scene build, resource binding, submission and the Present call. They do not
/// measure GPU execution, display completion, or input queueing latency.
struct LiveFrameSample {
    var presentedAt: Double
    var totalSeconds: Double
    /// Rebuild time accumulated since the previous sample. This includes
    /// deferred rebuilds inside `totalSeconds` as well as earlier rebuilds.
    var rebuildSeconds: Double = 0
    /// The subset accumulated before this frame started. Only this subset is
    /// added to `totalSeconds`; nested rebuild intervals are charged once.
    var outsideFrameRebuildSeconds: Double = 0
    var rebuildCount: Int = 0
    /// False when profiling was off or a nested reload made the last phase
    /// snapshots unsuitable for attributing the entire group of rebuilds.
    var rebuildPhaseTimingsAvailable = false
    /// `rebuildSeconds` split three ways: evaluating `View` bodies into a
    /// `Component` tree, turning that tree into `ViewNode`s, and reconciling
    /// them onto the retained tree.
    var composeSeconds: Double = 0
    var nodeConstructionSeconds: Double = 0
    var reconcileSeconds: Double = 0
    var sceneBuildSeconds: Double
    /// The split of `sceneBuildSeconds` on frames that repainted: laying the
    /// tree out versus painting it. Zero on a frame that hit the scene cache,
    /// where neither happened.
    var layoutSeconds: Double = 0
    var paintSeconds: Double = 0
    /// CPU resource binding. Upload work can instead occur during submission.
    var bindSeconds: Double
    /// Backend-reported split of `render(scene:)`: work issued vs time spent
    /// waiting in `Present`.
    var backendSubmitSeconds: Double
    var backendPresentSeconds: Double
    var backendTimingsAvailable = false
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
    /// Instanced draws this frame issued, and the primitives they covered.
    var drawCallCount: Int
    var drawnInstanceCount: Int
    /// View nodes the paint traversal entered. Meaningful only on frames that
    /// rebuilt: a cache-hit frame ships the scene an earlier frame built and
    /// carries that frame's metrics with it.
    var visitedNodeCount: Int

    /// CPU work charged to this sample without overlapping rebuild intervals.
    /// The legacy JSON name is retained; this is not input-to-present latency.
    var userVisibleCostSeconds: Double { outsideFrameRebuildSeconds + totalSeconds }
}

// MARK: - Configuration

/// How to run a live diagnostics session.
///
/// Parsed from the process arguments so the shipping executable carries the
/// mode — a diagnostics build that has to be produced specially is a
/// diagnostics build nobody runs when it matters.
public struct LiveDiagnosticsConfiguration: Equatable, Sendable {
    /// Elapsed monotonic seconds the window stays open before it closes itself. A
    /// live run that does not close itself is a run that cannot be scripted.
    public var durationSeconds: Double
    /// Where the JSON report is written.
    public var outputPath: String
    /// Whether the session drives synthetic retained input (hover sweep,
    /// scroll bursts and navigation attempts), bypassing native delivery.
    public var exercisesInput: Bool
    /// Whether to unpace presents for the run, so frame times measure the
    /// app's own cost rather than the compositor's vblank wait.
    public var disablesVSync: Bool
    /// Whether the run reads its own presented frames back and writes them as
    /// a numbered image sequence.
    ///
    /// Off by default and deliberately so: the readback is a full-surface
    /// GPU stall on every frame. A run with this on is measuring *pixels* —
    /// whether the motion a counter claims actually reached the screen — and
    /// its frame times are not comparable with a normal run's.
    public var capturesMotion: Bool
    /// Directory the frame sequence and its manifest are written to.
    public var motionOutputDirectory: String
    /// How many consecutive presented frames to keep. Frames are held in
    /// memory and written when the run ends, because encoding a PNG between
    /// two presents would stretch the very timeline being captured.
    public var motionFrameCount: Int

    public init(
        durationSeconds: Double = 10,
        outputPath: String = "artifacts/live-diagnostics.json",
        exercisesInput: Bool = true,
        disablesVSync: Bool = false,
        capturesMotion: Bool = false,
        motionOutputDirectory: String = "artifacts/motion",
        motionFrameCount: Int = 60
    ) {
        self.durationSeconds = max(0.5, durationSeconds)
        self.outputPath = outputPath
        self.exercisesInput = exercisesInput
        self.disablesVSync = disablesVSync
        self.capturesMotion = capturesMotion
        self.motionOutputDirectory = motionOutputDirectory
        self.motionFrameCount = max(4, motionFrameCount)
    }

    /// `--diagnostics [--diagnostics-seconds N] [--diagnostics-output PATH]
    /// [--diagnostics-no-input] [--diagnostics-no-vsync]
    /// [--diagnostics-capture-motion [--diagnostics-motion-frames N]
    /// [--diagnostics-motion-output DIR]]`, or
    /// `SWIFT_WINDOWSUI_DIAGNOSTICS=1` with the matching `_SECONDS` /
    /// `_OUTPUT` variables.
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

        if arguments.contains("--diagnostics-capture-motion") {
            configuration.capturesMotion = true
        }

        if let directory = value(of: "--diagnostics-motion-output", in: arguments), !directory.isEmpty {
            configuration.motionOutputDirectory = directory
        }

        if let frames = value(of: "--diagnostics-motion-frames", in: arguments), let parsed = Int(frames) {
            configuration.motionFrameCount = max(4, parsed)
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
    private let requestClose: @MainActor () -> Void
    private let report: (String) -> Void

    private var startedAt: Double?
    private var samples: [LiveFrameSample] = []
    private var isFinished = false
    /// Uploads recorded once the session considers the atlas warm, so a
    /// steady-state per-frame cost can be separated from the first-paint
    /// population of an empty atlas.
    private var warmupEndedAt: Double?
    private var atlasBytesAtWarmupEnd: UInt64?
    private var scriptedStepIndex = 0
    private var didExhaustScript = false
    private var didDisableVSync = false

    /// Motion capture state. `nil` unless the run asked for it.
    private var motionRecorder: MotionCaptureRecorder?
    private var motionScript = MotionCaptureScript()
    private var didEnableFrameCapture = false
    private var motionSummary: [String: Any]?
    private var motionFailureDetail: String?

    /// Seconds of the run treated as warmup. The first frames populate the
    /// glyph atlas, compile nothing (shaders are already in the binary) but do
    /// build every cache in the stack; averaging them into the steady state
    /// would let a slow steady state hide behind a fast start, or the reverse.
    private static let warmupSeconds: Double = 1.5

    /// An injected clock must share the origin of the host's frame timestamps.
    /// The close callback lets headless report tests avoid posting WM_QUIT.
    init(
        configuration: LiveDiagnosticsConfiguration,
        host: WinSwiftUIWindowHost,
        clock: @escaping () -> Double = { PlatformClock.now() },
        requestClose: (@MainActor () -> Void)? = nil,
        report: @escaping (String) -> Void = { print("[WinSwiftUI] \($0)") }
    ) {
        self.configuration = configuration
        self.host = host
        self.clock = clock
        self.requestClose = requestClose ?? { [weak host] in host?.platformWindow.requestClose() }
        self.report = report
    }

    /// Installs the frame hook and starts the clock. The session drives itself
    /// from the host's own animation timer from here on.
    func start() {
        startedAt = clock()
        // The layout/paint split is off in a shipping frame loop and on for
        // the run that is asking where the time goes.
        host?.hostedRuntime.collectsPhaseTimings = true
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

        let previousSample = samples.last
        samples.append(sample)
        host?.requestDiagnosticsFrame()

        let elapsed = clock() - startedAt
        if warmupEndedAt == nil, sampleElapsed(sample) >= Self.warmupSeconds {
            warmupEndedAt = sampleElapsed(sample)
            // The first eligible frame belongs to the measured population,
            // including its uploads. Its predecessor supplies the baseline;
            // without one, post-warmup bytes are unknown rather than zero.
            if let previousSample, previousSample.backendTimingsAvailable,
                previousSample.backend == sample.backend
            {
                atlasBytesAtWarmupEnd = previousSample.atlasUploadedByteCount
            }
        }

        if configuration.capturesMotion {
            // A capture run replaces the sustained hover/scroll stream with
            // its own script. The two cannot share a session: a pointer sweep
            // firing forty times a second repaints the window on every frame,
            // and every frame of the sequence would then differ everywhere
            // for reasons that have nothing to do with the animation the
            // capture is about.
            advanceMotionCapture(elapsed: elapsed, sample: sample)
        } else if configuration.exercisesInput {
            advanceScript(elapsed: elapsed)
        }

        if elapsed >= configuration.durationSeconds {
            finish()
        }
    }

    // MARK: - Motion capture

    /// Drives the motion sequence: waits out the warmup, turns the backend's
    /// self-readback on, then records every frame and steps the script by
    /// captured-frame index until the sequence is full.
    private func advanceMotionCapture(elapsed: Double, sample: LiveFrameSample) {
        guard let host else { return }

        guard elapsed >= Self.warmupSeconds else {
            // Nothing is captured during warmup. The first frames populate
            // the glyph atlas and the present-pacing watchdog has not yet
            // decided what is pacing this display, so their spacing is not
            // the spacing the animation will actually be shown at.
            return
        }

        if !didEnableFrameCapture {
            didEnableFrameCapture = true
            guard host.setActiveBatchBackendFrameCapture(true) else {
                motionFailureDetail =
                    "the active backend does not support presented-frame readback"
                report("Live diagnostics: \(motionFailureDetail!); motion capture skipped.")
                return
            }
            motionRecorder = MotionCaptureRecorder(frameLimit: configuration.motionFrameCount)
            report("Live diagnostics: capturing \(configuration.motionFrameCount) presented frames.")
            return
        }

        guard let recorder = motionRecorder else { return }

        if let surface = host.takeCapturedPresentedFrame() {
            recorder.record(
                surface,
                presentedAt: sample.presentedAt,
                step: motionScript.step.rawValue,
                hadActiveAnimations: sample.hadActiveAnimations
            )
        }

        if let action = motionScript.advance(capturedFrameCount: recorder.frames.count) {
            perform(action, in: host)
        }

        if recorder.isComplete {
            finish()
        }
    }

    private func perform(_ step: MotionCaptureScript.Step, in host: WinSwiftUIWindowHost) {
        let targets = MotionCaptureScript.targets(from: host.hostedRuntime.activatableControlCenters())
        switch step {
        case .baseline:
            break
        case .hoverFade:
            // A pointer that arrives and stays. The fade is the interaction
            // chrome's own tween, so this is the one step that starts an
            // animation without changing any state.
            guard let point = targets.navigation ?? targets.content else {
                motionFailureDetail = "no pressable control to hover"
                return
            }
            host.injectDiagnosticsPointerMove(to: point)
        case .screenSwitch:
            guard let point = targets.navigation else {
                motionFailureDetail = "no navigation control to switch screens with"
                return
            }
            host.injectDiagnosticsClick(at: point)
        case .controlActivate:
            guard let point = targets.content else {
                motionFailureDetail = "no content control to activate"
                return
            }
            // Hover first, then press, in two frames' worth of one call: a
            // press with the pointer never having arrived exercises a path no
            // user takes.
            host.injectDiagnosticsPointerMove(to: point)
            host.injectDiagnosticsClick(at: point)
        }
    }

    private func finishMotionCapture(host: WinSwiftUIWindowHost) {
        guard configuration.capturesMotion else { return }
        host.setActiveBatchBackendFrameCapture(false)
        guard let recorder = motionRecorder, !recorder.frames.isEmpty else {
            return
        }
        do {
            motionSummary = try recorder.write(to: configuration.motionOutputDirectory)
            report(
                "Live diagnostics: wrote \(recorder.frames.count) motion frames to "
                    + "\(configuration.motionOutputDirectory)."
            )
        } catch {
            motionFailureDetail = "writing the frame sequence failed: \(error)"
            report("Live diagnostics: \(motionFailureDetail!)")
        }
    }

    // MARK: - Scripted interaction

    /// One scripted interaction, and the elapsed time it fires at.
    private struct ScriptStep {
        var atSeconds: Double
        var name: String
        var action: @MainActor (WinSwiftUIWindowHost) -> Void
    }

    /// Hover steps per second in synthetic retained input stress. Each third
    /// step also sends a scroll request; six navigation attempts are added.
    /// Input is delivered after a sampled frame, not through the native queue.
    private static let sustainedStepsPerSecond: Double = 40

    private lazy var script: [ScriptStep] = {
        var steps: [ScriptStep] = []

        // The interaction phase runs from the end of warmup to the end of the
        // run, so `--diagnostics-seconds` buys more measurement rather than
        // more idling. The previous script stopped at a fixed 8.8 s and left
        // the tail of every run idle, which is why the whole-run percentiles
        // described a window sitting still.
        let phaseStart = Self.warmupSeconds + 0.1
        let phaseEnd = max(phaseStart + 1.0, configuration.durationSeconds - 0.2)
        let phaseSpan = phaseEnd - phaseStart
        let stepCount = max(8, Int(phaseSpan * Self.sustainedStepsPerSecond))

        // One interleaved stream rather than three separate bursts. A hover
        // that moves while a scroll glides while a screen fades is the state
        // the frame budget has to survive; measuring them one at a time
        // measures three easier problems.
        for index in 0..<stepCount {
            let progress = Double(index) / Double(max(stepCount - 1, 1))
            let at = phaseStart + progress * phaseSpan

            // Hover: a triangle wave across the content area, so every step
            // crosses rows and starts hover transitions instead of settling.
            let sweep = abs((progress * 6.0).truncatingRemainder(dividingBy: 2.0) - 1.0)
            steps.append(
                ScriptStep(atSeconds: at, name: "hover") { host in
                    let size = host.currentLogicalRootSize
                    host.injectDiagnosticsPointerMove(
                        to: Point(
                            x: Double(size.width) * (0.30 + 0.62 * sweep),
                            y: Double(size.height) * (0.20 + 0.62 * (1.0 - sweep))
                        )
                    )
                }
            )

            // The retained API takes lines, not raw Win32 wheel detents. This
            // is an intentionally large 120-line request, not a normal notch.
            if index % 3 == 0 {
                let goesDown = Int(at * 2.0) % 2 == 0
                steps.append(
                    ScriptStep(atSeconds: at, name: goesDown ? "scroll-down" : "scroll-up") { host in
                        let size = host.currentLogicalRootSize
                        host.injectDiagnosticsScroll(
                            at: Point(x: Double(size.width) * 0.6, y: Double(size.height) * 0.6),
                            delta: goesDown ? -120 : 120
                        )
                    }
                )
            }
        }

        // Screen switches spread through the phase: the sidebar sits in the
        // left column, so a click at a fixed fraction of it lands on a
        // navigation row for any reasonable window size. A miss costs the
        // switch, not the run.
        let switchFractions: [Double] = [0.28, 0.36, 0.20, 0.28, 0.36, 0.20]
        for (index, yFraction) in switchFractions.enumerated() {
            let at = phaseStart + phaseSpan * (Double(index) + 0.5) / Double(switchFractions.count)
            steps.append(
                ScriptStep(atSeconds: at, name: "screen-switch") { host in
                    let size = host.currentLogicalRootSize
                    host.injectDiagnosticsClick(
                        at: Point(x: Double(size.width) * 0.08, y: Double(size.height) * yFraction)
                    )
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
        host.hostedRuntime.collectsPhaseTimings = false
        finishMotionCapture(host: host)

        do {
            let json = try buildReportJSON(host: host)
            try writeReport(json)
            report("Live diagnostics written to \(configuration.outputPath).")
        } catch {
            report("Live diagnostics could not write \(configuration.outputPath): \(error)")
        }

        requestClose()
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

        let timedSamples = samples.filter { sampleElapsed($0) >= Self.warmupSeconds }

        var report: [String: Any] = [:]

        // Version 2 preserves populated metric names, but unavailable
        // statistics are null rather than misleading zero measurements.
        report["schema"] = "swift-windowsui.live-diagnostics/2"
        report["durationSecondsRequested"] = configuration.durationSeconds
        report["durationSecondsActual"] = elapsed
        report["exercisedInput"] = configuration.exercisesInput
        report["vsyncDisabledForRun"] = didDisableVSync
        report["vsyncDisableRequested"] = configuration.disablesVSync
        report["scriptedStepsExecuted"] = executedStepCounts
        report["sampling"] = [
            "population": "framesEndingAtOrAfterWarmup",
            "status": timedSamples.isEmpty ? "noPostWarmupSamples" : "samplesAvailable",
            "postWarmupSampleCount": timedSamples.count,
            "warmupExcludedSampleCount": samples.count - timedSamples.count,
            "postWarmupSampleSpanSeconds": nullable(
                timedSamples.first.flatMap { first in timedSamples.last.map { $0.presentedAt - first.presentedAt } }),
            "availableSamplesEstablishQualification": false,
        ]
        report["measurement"] = [
            "inputDelivery": configuration.capturesMotion
                ? "syntheticMotionScript" : (configuration.exercisesInput ? "syntheticRetainedRuntime" : "none"),
            "forcedFrameRequests": true,
            "clock": "monotonic",
            "frameTimestamp": "hostFrameReturn",
            "presentTiming": "cpuCallDuration",
            "resourceBindingTiming": "cpuBindingExcludingSubmissionUploads",
            "rebuildPhasePopulation": "framesWithCompleteNonNestedRebuildPhaseSnapshots",
            "userVisibleCostMeaning": "outsideFrameRebuildPlusCPUFrame",
            "backendHealthScope": "finalSnapshotNotFullRunHistory",
            "backendReturnCanSkipPresentationDuringRecovery": true,
            "inputToPresentMeasured": false,
            "gpuExecutionMeasured": false,
            "presentationDeadlinesMeasured": false,
            "coldStartupMeasured": false,
            "hardwareQualified": false,
        ]
        report["syntheticWorkload"] = [
            "enabled": configuration.exercisesInput && !configuration.capturesMotion,
            "hoverStepsPerSecond": Self.sustainedStepsPerSecond,
            "scrollDeltaUnit": "lines",
            "scrollDeltaMagnitude": 120,
            "navigationCounts": "attempts",
            "delivery": "afterFrameWithDueStepsDeliveredTogether",
        ]

        if configuration.capturesMotion {
            var motion: [String: Any] = ["requested": true]
            motion["backendSupportedReadback"] = motionFailureDetail == nil && motionSummary != nil
            if let motionSummary {
                for (key, value) in motionSummary {
                    motion[key] = value
                }
            }
            if let motionFailureDetail {
                motion["failure"] = motionFailureDetail
            }
            report["motionCapture"] = motion
        }

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

        // The field that explains a 4 fps window whose own frame cost is
        // 0.6 ms. Reported next to the backend block because that is the pair
        // a reader needs: which renderer is presenting, and what is pacing it.
        let pacing = health.presentPacing
        report["presentPacing"] = [
            "mode": pacing.mode.rawValue,
            "requiresSelfPacing": pacing.requiresSelfPacing,
            "displayFrameIntervalMs": pacing.displayFrameInterval * 1000,
            "lastPresentMs": pacing.lastPresentSeconds * 1000,
            "medianPresentMs": pacing.medianPresentSeconds * 1000,
            "watchdogEngagements": pacing.engagementCount,
            "recoveryProbes": pacing.probeCount,
            "probeIntervalSeconds": pacing.probeIntervalSeconds,
            "samplesInWindow": pacing.sampleCount,
        ]

        if let diagnostics = host.activeBatchBackendDiagnostics {
            report["adapter"] = [
                "description": diagnostics.adapterDescription ?? "<unavailable>",
                "isSoftware": diagnostics.adapterIsSoftware as Any,
                "dedicatedVideoMemoryBytes": diagnostics.adapterDedicatedVideoMemoryBytes as Any,
                "featureLevel": diagnostics.featureLevel ?? "<unavailable>",
            ]
            var warmBytes: UInt64?
            var uploadingFrames: Int?
            // Bytes-per-frame divides a handful of large uploads across
            // thousands of frames and reports a steady state that never
            // happened. The frame that pays 1 MB is the frame that hitches, so
            // count the frames that paid anything at all.
            if let baseline = atlasBytesAtWarmupEnd, !timedSamples.isEmpty {
                var previousBytes = baseline
                var uploadCount = 0
                var hasContinuousCounters = true
                for sample in timedSamples {
                    guard sample.backendTimingsAvailable, sample.atlasUploadedByteCount >= previousBytes else {
                        hasContinuousCounters = false
                        break
                    }
                    if sample.atlasUploadedByteCount > previousBytes {
                        uploadCount += 1
                    }
                    previousBytes = sample.atlasUploadedByteCount
                }
                if hasContinuousCounters {
                    warmBytes = previousBytes - baseline
                    uploadingFrames = uploadCount
                }
            }
            report["atlas"] = [
                "postWarmupCountersAvailable": warmBytes != nil,
                "framesThatUploadedAfterWarmup": nullable(uploadingFrames),
                "fullUploadCount": diagnostics.atlasFullUploadCount,
                "regionUploadCount": diagnostics.atlasRegionUploadCount,
                "skippedUploadCount": diagnostics.atlasSkippedUploadCount,
                "uploadedByteCountTotal": diagnostics.atlasUploadedByteCount,
                "uploadedByteCountAfterWarmup": nullable(warmBytes),
                "uploadedBytesPerFrameAfterWarmup": ratio(
                    warmBytes.map { Double($0) }, over: Double(timedSamples.count)),
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
        // Rebuild cost is charged to the frame that ships it, so it is
        // summarised over the frames that carried one — averaging it across
        // every frame divides one screen switch by a thousand idle repaints
        // and reports a cost nobody paid.
        let rebuildingSamples = timedSamples.filter { $0.rebuildCount > 0 }
        let rebuildPhaseSamples = rebuildingSamples.filter(\.rebuildPhaseTimingsAvailable)
        let backendTimingSamples = timedSamples.filter(\.backendTimingsAvailable)
        let rebuildMs = rebuildingSamples.map { $0.rebuildSeconds * 1000 }.sorted()
        let bindMs = timedSamples.map { $0.bindSeconds * 1000 }.sorted()
        let submitMs = timedSamples.map { $0.submitAndPresentSeconds * 1000 }.sorted()
        let backendSubmitMs = backendTimingSamples.map { $0.backendSubmitSeconds * 1000 }.sorted()
        let backendPresentMs = backendTimingSamples.map { $0.backendPresentSeconds * 1000 }.sorted()
        let refreshIntervalMs = 1000.0 / Double(refreshRate)
        let droppedEstimate = frameTimesMs.filter { $0 > refreshIntervalMs * 1.5 }.count
        // The spacing of presented frames, which the frame-time percentiles
        // cannot show: a 0.6 ms frame every 13 ms and one every 16.7 ms cost
        // the same and look completely different in motion. The median here
        // is the number the self-paced gate is judged by — it must sit on
        // the display period, not under it.
        let presentGapsMs = zip(timedSamples.dropFirst(), timedSamples)
            .map { ($0.presentedAt - $1.presentedAt) * 1000 }
            .filter { $0 > 0 }
            .sorted()

        report["frames"] = [
            "presentedTotal": samples.count,
            "presentedAfterWarmup": timedSamples.count,
            "warmupSeconds": Self.warmupSeconds,
            "framesPerSecondOverRun": ratio(Double(samples.count), over: elapsed),
            "frameTimeMs": percentileSummary(frameTimesMs),
            "sceneBuildMs": percentileSummary(sceneBuildMs),
            // What a screen switch actually costs, in the three parts that
            // have three different fixes: rebuilding the tree, laying it out,
            // painting it.
            "treeRebuildMs": percentileSummary(rebuildMs),
            "outsideFrameRebuildMs": percentileSummary(
                rebuildingSamples.map { $0.outsideFrameRebuildSeconds * 1000 }.sorted()),
            "userVisibleCostMs": percentileSummary(rebuildingSamples.map { $0.userVisibleCostSeconds * 1000 }.sorted()),
            "bodyEvaluationMs": percentileSummary(rebuildPhaseSamples.map { $0.composeSeconds * 1000 }.sorted()),
            "nodeConstructionMs": percentileSummary(
                rebuildPhaseSamples.map { $0.nodeConstructionSeconds * 1000 }.sorted()),
            "reconcileMs": percentileSummary(rebuildPhaseSamples.map { $0.reconcileSeconds * 1000 }.sorted()),
            "framesCarryingATreeRebuild": rebuildingSamples.count,
            "framesWithRebuildPhaseTimings": rebuildPhaseSamples.count,
            "treeRebuildsTotal": timedSamples.reduce(0) { $0 + $1.rebuildCount },
            "bindResourcesMs": percentileSummary(bindMs),
            "submitAndPresentMs": percentileSummary(submitMs),
            "backendSubmitMs": percentileSummary(backendSubmitMs),
            "backendPresentMs": percentileSummary(backendPresentMs),
            "presentGapMs": percentileSummary(presentGapsMs),
            "refreshIntervalMs": refreshIntervalMs,
            "frameBudgetThresholdRefreshIntervals": 1.5,
            "framesOverRefreshBudget": droppedEstimate,
            "framesOverRefreshBudgetFraction": ratio(Double(droppedEstimate), over: Double(frameTimesMs.count)),
            // The whole-run percentiles above average an animating frame
            // together with an idle repaint, and in a session that is mostly
            // idle the animating cost disappears into the tail. Animation
            // smoothness is a claim about exactly one of those populations, so
            // it gets measured as one.
            "whileAnimating": frameCostBlock(
                timedSamples.filter(\.hadActiveAnimations), refreshIntervalMs: refreshIntervalMs),
            "whileIdle": frameCostBlock(
                timedSamples.filter { !$0.hadActiveAnimations }, refreshIntervalMs: refreshIntervalMs),
        ]

        // The percentiles hide the frames that actually get seen as a stutter.
        // A p99 of 4 ms and a max of 52 ms are the same distribution to a
        // reader and completely different experiences to a user, and "when did
        // the 52 ms land" is the question that separates a cold-cache cost
        // paid once per screen from a hitch on every navigation.
        let slowestFirst = timedSamples.sorted { $0.totalSeconds > $1.totalSeconds }
        report["worstFrames"] =
            slowestFirst
            .prefix(8)
            .map(frameDetail)

        // Only the rebuild work before frame entry is additional CPU work.
        // Deferred rebuilds are already included in totalSeconds. This sum
        // excludes input queueing and is not an end-to-end latency measure.
        let costliestUpdates = rebuildingSamples.sorted {
            $0.userVisibleCostSeconds > $1.userVisibleCostSeconds
        }
        report["costliestUpdates"] = costliestUpdates.prefix(8).map(frameDetail)

        let rebuilds = timedSamples.filter(\.didRebuildScene).count
        let animatingSamples = timedSamples.filter(\.hadActiveAnimations)
        let animatingRebuilds = animatingSamples.filter(\.didRebuildScene).count
        let drawCalls = backendTimingSamples.map { Double($0.drawCallCount) }.sorted()
        let drawnInstances = backendTimingSamples.reduce(0) { $0 + $1.drawnInstanceCount }
        let totalDrawCalls = backendTimingSamples.reduce(0) { $0 + $1.drawCallCount }
        var scene: [String: Any] = [:]
        scene["runtimeSceneRebuildCount"] = host.hostedRuntime.sceneRebuildCount
        scene["runtimeSceneCacheHitCount"] = host.hostedRuntime.sceneCacheHitCount
        // Frames the host refused to present because they were byte-identical
        // to what was already on screen. Nonzero during animations whose
        // values advance more slowly than the timer ticks; every one of these
        // used to be a presented duplicate that pixel diffing counted.
        scene["skippedIdenticalPresents"] = host.skippedIdenticalPresentCount
        scene["framesThatRebuiltScene"] = rebuilds
        scene["framesThatReplayedScene"] = timedSamples.count - rebuilds
        // Replay is only interesting where it is hard: a frame with an
        // animation running has, by construction, something that changed. A
        // 99 % replay rate over an idle session says nothing about it.
        scene["animatingFramesThatRebuiltScene"] = animatingRebuilds
        scene["animatingFramesThatReplayedScene"] = animatingSamples.count - animatingRebuilds
        scene["animatingReplayRate"] = ratio(
            Double(animatingSamples.count - animatingRebuilds), over: Double(animatingSamples.count))
        // Subtree replay, on the frames where it is the only thing standing
        // between an animation and a full-tree repaint. Reported over the
        // rebuild frames alone: a whole-scene cache hit reports zero replayed
        // nodes by definition, and averaging those in reads as "replay is
        // dead" on a session that never needed it.
        let rebuildSamples = timedSamples.filter(\.didRebuildScene)
        scene["nodeReplaysPerRebuildFrame"] = percentileSummary(
            rebuildSamples.map { Double($0.nodeReplayCount) }.sorted())
        scene["rebuildFramesWithZeroNodeReplay"] = rebuildSamples.filter { $0.nodeReplayCount == 0 }.count
        // What a rebuilt frame actually redid. The replay count above counts
        // *ranges*, and one range can be a single row or the whole root, so it
        // cannot distinguish the cheapest frame from the most expensive one.
        // This can: the maximum is what a full-tree walk costs, and the median
        // is what an animating frame costs against it.
        scene["nodesVisitedPerRebuildFrame"] = percentileSummary(
            rebuildSamples.map { Double($0.visitedNodeCount) }.sorted())
        // Where a repaint's time goes. Over rebuild frames only, for the same
        // reason as the counts above: a cache-hit frame did neither.
        scene["layoutMsPerRebuildFrame"] = percentileSummary(
            rebuildSamples.map { $0.layoutSeconds * 1000 }.sorted())
        scene["paintMsPerRebuildFrame"] = percentileSummary(
            rebuildSamples.map { $0.paintSeconds * 1000 }.sorted())
        scene["maxNodesVisited"] = timedSamples.map(\.visitedNodeCount).max() ?? 0
        scene["lastPrimitiveCount"] = samples.last?.primitiveCount ?? 0
        scene["maxPrimitiveCount"] = samples.map(\.primitiveCount).max() ?? 0
        scene["drawCallsPerFrame"] = percentileSummary(drawCalls)
        scene["drawCoalescingRatio"] = ratio(Double(drawnInstances), over: Double(totalDrawCalls))
        scene["gpuPromotionRate"] = health.lastScenePaintMetrics.gpuPromotionRate
        scene["pathsRasterizedOnCPU"] = health.lastScenePaintMetrics.pathsRasterizedOnCPU
        scene["pathsPromotedToGPU"] = health.lastScenePaintMetrics.pathsPromotedToGPU
        report["scene"] = scene

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

    /// One frame, in every part a reader needs to attribute its cost.
    private func frameDetail(_ sample: LiveFrameSample) -> [String: Any] {
        [
            "atSeconds": sampleElapsed(sample),
            "frameTimeMs": sample.totalSeconds * 1000,
            // Total rebuild work can overlap the frame's own CPU interval.
            "treeRebuildMs": sample.rebuildSeconds * 1000,
            "outsideFrameRebuildMs": sample.outsideFrameRebuildSeconds * 1000,
            "treeRebuildCount": sample.rebuildCount,
            "rebuildPhaseTimingsAvailable": sample.rebuildPhaseTimingsAvailable,
            "bodyEvaluationMs": nullable(sample.rebuildPhaseTimingsAvailable ? sample.composeSeconds * 1000 : nil),
            "nodeConstructionMs": nullable(
                sample.rebuildPhaseTimingsAvailable ? sample.nodeConstructionSeconds * 1000 : nil),
            "reconcileMs": nullable(sample.rebuildPhaseTimingsAvailable ? sample.reconcileSeconds * 1000 : nil),
            "userVisibleCostMs": sample.userVisibleCostSeconds * 1000,
            "sceneBuildMs": sample.sceneBuildSeconds * 1000,
            "layoutMs": sample.layoutSeconds * 1000,
            "paintMs": sample.paintSeconds * 1000,
            "bindResourcesMs": sample.bindSeconds * 1000,
            "backendSubmitMs": nullable(sample.backendTimingsAvailable ? sample.backendSubmitSeconds * 1000 : nil),
            "backendPresentMs": nullable(sample.backendTimingsAvailable ? sample.backendPresentSeconds * 1000 : nil),
            "didRebuildScene": sample.didRebuildScene,
            "nodeReplayCount": sample.nodeReplayCount,
            "visitedNodeCount": sample.visitedNodeCount,
            "hadActiveAnimations": sample.hadActiveAnimations,
        ]
    }

    /// The cost of one population of frames: how many there were, what they
    /// cost end to end, what they spent building the scene, and how many blew
    /// the refresh budget. Same shape whichever population it describes, so
    /// the animating and idle blocks are directly comparable.
    private func frameCostBlock(
        _ population: [LiveFrameSample],
        refreshIntervalMs: Double
    ) -> [String: Any] {
        let totals = population.map { $0.totalSeconds * 1000 }.sorted()
        let backendTimingSamples = population.filter(\.backendTimingsAvailable)
        let overBudget = totals.filter { $0 > refreshIntervalMs }.count
        return [
            "frameCount": population.count,
            "frameTimeMs": percentileSummary(totals),
            "sceneBuildMs": percentileSummary(population.map { $0.sceneBuildSeconds * 1000 }.sorted()),
            "backendSubmitMs": percentileSummary(backendTimingSamples.map { $0.backendSubmitSeconds * 1000 }.sorted()),
            "backendPresentMs": percentileSummary(
                backendTimingSamples.map { $0.backendPresentSeconds * 1000 }.sorted()),
            "frameBudgetThresholdRefreshIntervals": 1,
            "framesOverRefreshBudget": overBudget,
            "framesOverRefreshBudgetFraction": ratio(Double(overBudget), over: Double(totals.count)),
        ]
    }

    private func sampleElapsed(_ sample: LiveFrameSample) -> Double {
        guard let startedAt else { return 0 }
        return sample.presentedAt - startedAt
    }

    private func percentileSummary(_ sortedValues: [Double]) -> [String: Any] {
        guard !sortedValues.isEmpty else {
            return [
                "sampleCount": 0, "hasSamples": false,
                "p50": NSNull(), "p95": NSNull(), "p99": NSNull(), "max": NSNull(), "mean": NSNull(),
            ]
        }

        func percentile(_ fraction: Double) -> Double {
            let index = Int((Double(sortedValues.count - 1) * fraction).rounded())
            return sortedValues[min(max(index, 0), sortedValues.count - 1)]
        }

        return [
            "sampleCount": sortedValues.count,
            "hasSamples": true,
            "p50": percentile(0.50),
            "p95": percentile(0.95),
            "p99": percentile(0.99),
            "max": sortedValues[sortedValues.count - 1],
            "mean": sortedValues.reduce(0, +) / Double(sortedValues.count),
        ]
    }

    private func nullable<T>(_ value: T?) -> Any {
        value.map { $0 as Any } ?? NSNull()
    }

    private func ratio(_ numerator: Double?, over denominator: Double) -> Any {
        guard let numerator, denominator > 0 else { return NSNull() }
        return numerator / denominator
    }
}
