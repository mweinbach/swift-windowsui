import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
final class MountedStateHostTimingTests: XCTestCase {
    func testCompletionQueuedStateBuildsOutsideFrameExcludeCompletionCost() async throws {
        let harness = MountedTimingHarness()
        defer { harness.close() }
        let phase = try XCTUnwrap(harness.clock.installedPhase)
        let reloadStartedAt = harness.clock.now

        // This is the binding captured during the installed owner's body,
        // not the uninstalled source value or a control's extra invalidation.
        phase.wrappedValue = 1

        XCTAssertEqual(phase.wrappedValue, 2)
        XCTAssertEqual(harness.host.executedReloadCount, 2)
        XCTAssertEqual(harness.host.scheduledReloadCount, 0)
        XCTAssertEqual(harness.clock.completionGuards, [true, true])
        XCTAssertEqual(harness.clock.events, completedBuildEvents)
        XCTAssertTrue(harness.clock.samples.isEmpty)
        XCTAssertEqual(harness.clock.now - reloadStartedAt, 0.058, accuracy: 0.000_000_001)

        harness.present()

        XCTAssertEqual(harness.clock.samples.count, 1)
        let sample = try XCTUnwrap(harness.clock.samples.last)
        assertTiming(sample, rebuild: 0.008, frame: 0.004, outsideFrame: 0.008, userVisible: 0.012)
        XCTAssertTrue(sample.rebuildPhaseTimingsAvailable, "The queued builds have separate phase snapshots.")
        XCTAssertEqual(harness.clock.events, completedBuildEvents + [.frame])
        try harness.assertFinalPhase()

        // Neither completion time nor a second copy of either build may
        // remain pending after the sample consumes the measured work.
        harness.present()
        XCTAssertEqual(harness.clock.samples.count, 2)
        let following = try XCTUnwrap(harness.clock.samples.last)
        assertTiming(following, rebuild: 0, frame: 0.004, outsideFrame: 0, userVisible: 0.004, rebuildCount: 0)
        XCTAssertFalse(following.rebuildPhaseTimingsAvailable)
        XCTAssertEqual(following.composeSeconds, 0)
        XCTAssertEqual(following.nodeConstructionSeconds, 0)
        XCTAssertEqual(following.reconcileSeconds, 0)
        XCTAssertEqual(harness.host.executedReloadCount, 2)
    }

    func testCompletionQueuedStateBuildsInsideFrameKeepCompletionOnlyInFrameCost() async throws {
        let harness = MountedTimingHarness()
        defer { harness.close() }
        let phase = try XCTUnwrap(harness.clock.installedPhase)
        XCTAssertEqual(phase.wrappedValue, 0)

        harness.model.phase = 1
        XCTAssertEqual(harness.host.scheduledReloadCount, 1)
        XCTAssertEqual(harness.host.executedReloadCount, 0)
        XCTAssertTrue(harness.clock.events.isEmpty)

        // Do not yield to the observed-object Task fallback: the admitted
        // frame must consume A, its completion, and the queued State build B.
        harness.present()

        XCTAssertEqual(phase.wrappedValue, 2)
        XCTAssertEqual(harness.host.executedReloadCount, 2)
        XCTAssertEqual(harness.host.completedObservedObjectReloadTaskCount, 1)
        XCTAssertEqual(harness.clock.completionGuards, [true, true])
        XCTAssertEqual(harness.clock.events, completedBuildEvents + [.frame])
        XCTAssertEqual(harness.clock.samples.count, 1)
        let sample = try XCTUnwrap(harness.clock.samples.last)
        assertTiming(sample, rebuild: 0.008, frame: 0.062, outsideFrame: 0, userVisible: 0.062)
        XCTAssertTrue(sample.rebuildPhaseTimingsAvailable)
        try harness.assertFinalPhase()
    }

    func testDisappearanceWorkInsideBuildIsChargedOnceWithoutCountingAnotherAttempt() async throws {
        let harness = MountedTimingHarness(includesDepartingChild: true)
        defer { harness.close() }
        XCTAssertEqual(harness.clock.departingAppearances, 1)
        let phase = try XCTUnwrap(harness.clock.installedPhase)
        let reloadStartedAt = harness.clock.now

        phase.wrappedValue = 1

        XCTAssertEqual(harness.host.executedReloadCount, 2)
        XCTAssertEqual(harness.clock.completionGuards, [true, true])
        XCTAssertEqual(
            harness.clock.events,
            [.body(1), .disappear(7)] + Array(completedBuildEvents.dropFirst()))
        XCTAssertTrue(harness.clock.samples.isEmpty)
        XCTAssertEqual(harness.clock.now - reloadStartedAt, 0.061, accuracy: 0.000_000_001)

        harness.present()

        XCTAssertEqual(harness.clock.samples.count, 1)
        let sample = try XCTUnwrap(harness.clock.samples.last)
        // A's 6 ms body includes a 3 ms disappearance callback during
        // adoption. B contributes 2 ms; the 50 ms completion stays excluded.
        assertTiming(sample, rebuild: 0.011, frame: 0.004, outsideFrame: 0.011, userVisible: 0.015)
        XCTAssertTrue(sample.rebuildPhaseTimingsAvailable)
        try harness.assertFinalPhase()
    }

    private var completedBuildEvents: [MountedTimingEvent] {
        [
            .body(1), .completionBegan(1), .completionEnded(1),
            .body(2), .completionBegan(2), .completionEnded(2),
        ]
    }

    private func assertTiming(
        _ sample: LiveFrameSample,
        rebuild: Double,
        frame: Double,
        outsideFrame: Double,
        userVisible: Double,
        rebuildCount: Int = 2,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(sample.rebuildSeconds, rebuild, accuracy: 0.000_000_001, file: file, line: line)
        XCTAssertEqual(sample.totalSeconds, frame, accuracy: 0.000_000_001, file: file, line: line)
        XCTAssertEqual(
            sample.outsideFrameRebuildSeconds, outsideFrame, accuracy: 0.000_000_001, file: file, line: line)
        XCTAssertEqual(
            sample.userVisibleCostSeconds, userVisible, accuracy: 0.000_000_001, file: file, line: line)
        XCTAssertEqual(sample.rebuildCount, rebuildCount, file: file, line: line)
    }
}

private enum MountedTimingEvent: Equatable {
    case body(Int)
    case completionBegan(Int)
    case completionEnded(Int)
    case disappear(Int)
    case frame
}

@MainActor
private final class MountedTimingModel: ObservableObject {
    @Published var phase = 0
}

/// Only authored body, cleanup, completion, and backend work advances this
/// clock. The tests check host accounting, not native or GPU performance.
@MainActor
private final class MountedTimingClock {
    var now: Double = 5_000
    var isRecording = false
    var installedPhase: Binding<Int>?
    var departingAppearances = 0
    var samples: [LiveFrameSample] = []
    var events: [MountedTimingEvent] = []
    var completionGuards: [Bool] = []
    private var latestPhase = 0
    private var didQueueFollowup = false

    func evaluate(_ phase: Int, binding: Binding<Int>) {
        installedPhase = binding
        latestPhase = phase
        guard isRecording else { return }
        events.append(.body(phase))
        switch phase {
        case 1: now += 0.006
        case 2: now += 0.002
        default: break
        }
    }

    func completeReload(isGuardHeld: Bool) {
        let phase = latestPhase
        completionGuards.append(isGuardHeld)
        events.append(.completionBegan(phase))
        if phase == 1, !didQueueFollowup {
            didQueueFollowup = true
            now += 0.050
            installedPhase?.wrappedValue = 2
        }
        events.append(.completionEnded(phase))
    }

    func disappear(value: Int) {
        guard isRecording else { return }
        events.append(.disappear(value))
        now += 0.003
    }

    func render() {
        guard isRecording else { return }
        events.append(.frame)
        now += 0.004
    }
}

@MainActor
private struct MountedTimingContent: View {
    @ObservedObject var model: MountedTimingModel
    @State private var phaseOverride = 0
    let clock: MountedTimingClock
    let includesDepartingChild: Bool

    var body: some View {
        let phase = phaseOverride > 0 ? phaseOverride : model.phase
        clock.evaluate(phase, binding: $phaseOverride)
        return VStack(alignment: .leading, spacing: 4) {
            Text("Phase \(phase)")
                .accessibilityIdentifier("mounted-timing.phase")
            if includesDepartingChild && phase == 0 {
                MountedTimingDepartingContent(clock: clock)
            }
        }
    }
}

@MainActor
private struct MountedTimingDepartingContent: View {
    @State private var value = 7
    let clock: MountedTimingClock

    var body: some View {
        Text("Departing \(value)")
            .onAppear { clock.departingAppearances += 1 }
            .onDisappear { clock.disappear(value: value) }
    }
}

@MainActor
private final class MountedTimingBackend: RenderBackend {
    let clock: MountedTimingClock

    init(clock: MountedTimingClock) { self.clock = clock }

    func attach(to surface: SurfaceDescriptor) throws {}
    func resize(to size: IntSize) throws {}
    func detach() {}
    func render(frame: RenderFrame) throws { clock.render() }
}

@MainActor
private struct MountedTimingHarness {
    let host: WinSwiftUIWindowHost
    let window: Win32Window
    let model: MountedTimingModel
    let clock: MountedTimingClock

    init(includesDepartingChild: Bool = false) {
        let clock = MountedTimingClock()
        let model = MountedTimingModel()
        let content = MountedTimingContent(
            model: model, clock: clock, includesDepartingChild: includesDepartingChild)
        let surface = SurfaceDescriptor(
            windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
            pixelSize: IntSize(width: 320, height: 200), scaleFactor: 1)
        let window = Win32Window(title: "Mounted State timing", clientSize: surface.pixelSize)
        window.testMonitorRefreshRateOverride = 60
        window.testScaleFactorOverride = 1
        let host = WinSwiftUIWindowHost(
            configuration: WindowGroupConfiguration(
                title: "Mounted State timing", size: surface.pixelSize, clearColor: .black,
                content: [AnyView(content)]),
            platformWindow: window,
            renderer: MountedTimingBackend(clock: clock),
            batchRenderer: nil,
            surfaceDescriptorProvider: { _ in surface },
            startupPresentationMode: .automatic,
            startupProbeConfiguration: nil)
        host.frameClock = { clock.now }
        host.hostedRuntime.clock = { clock.now }
        host.windowDidCreate(window)
        host.resetObservabilityCounters()

        // Initial construction and first appearance are unmeasured. Capture
        // only actual reload attempts and their following frame from here.
        clock.isRecording = true
        host.hostedRuntime.collectsPhaseTimings = true
        host.onFramePresented = { clock.samples.append($0) }
        host.onReloadContentCompleted = { [weak host] in
            clock.completeReload(isGuardHeld: host?.hostedRuntime.hasActiveRetainedBuild == true)
        }
        self.host = host
        self.window = window
        self.model = model
        self.clock = clock
    }

    func present() {
        // Scheduling delay is not measured work. Advance past pacing before
        // requesting a frame, and keep the synthetic clock still otherwise.
        clock.now += 0.1
        host.requestDiagnosticsFrame()
        host.windowNeedsDisplay(window)
    }

    func close() { host.windowWillClose(window) }

    func assertFinalPhase(file: StaticString = #filePath, line: UInt = #line) throws {
        let matches = descendants(in: host.hostedRuntime.root).filter {
            $0.accessibilityIdentifier == "mounted-timing.phase"
        }
        XCTAssertEqual(matches.count, 1, file: file, line: line)
        XCTAssertEqual(try XCTUnwrap(matches.first, file: file, line: line).text, "Phase 2", file: file, line: line)
    }

    private func descendants(in node: ViewNode) -> [ViewNode] {
        [node] + node.children.flatMap { descendants(in: $0) }
    }
}
