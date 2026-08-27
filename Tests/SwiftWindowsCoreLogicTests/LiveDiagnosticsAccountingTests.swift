import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
private final class DiagnosticsAccountingModel: ObservableObject {
    @Published var revision = 0
}

@MainActor
private final class DiagnosticsAccountingClock {
    var now: Double = 5_000
    var rebuildSeconds: Double = 0
    var frameSeconds: Double = 0
    var samples: [LiveFrameSample] = []
    var onNextBodyEvaluation: (() -> Void)?

    func evaluate(_ revision: Int) -> Int {
        now += rebuildSeconds
        let callback = onNextBodyEvaluation
        onNextBodyEvaluation = nil
        callback?()
        return revision
    }
}

@MainActor
private struct DiagnosticsAccountingContent: View {
    @ObservedObject var model: DiagnosticsAccountingModel
    @State var stateRevision = 0
    let clock: DiagnosticsAccountingClock

    var body: some View {
        let revision = clock.evaluate(stateRevision + model.revision)
        return Rectangle()
            .fill(WinSwiftUI.Color.blue)
            .frame(width: Double(80 + revision), height: 24)
    }
}

/// A frame-path failure must leave rebuild accounting pending until an
/// actual successful presentation, without a real GPU or wall-clock wait.
@MainActor
private final class DiagnosticsAccountingFrameBackend: RenderBackend {
    let clock: DiagnosticsAccountingClock
    var shouldFail = false
    private(set) var renderedFrameCount = 0

    init(clock: DiagnosticsAccountingClock) {
        self.clock = clock
    }

    func attach(to surface: SurfaceDescriptor) throws {}
    func resize(to size: IntSize) throws {}
    func detach() {}

    func render(frame: RenderFrame) throws {
        clock.now += clock.frameSeconds
        if shouldFail {
            throw FakeRenderBackendError.renderFailure
        }
        renderedFrameCount += 1
    }
}

@MainActor
private struct DiagnosticsAccountingHarness {
    let host: WinSwiftUIWindowHost
    let window: Win32Window
    let content: DiagnosticsAccountingContent
    let model: DiagnosticsAccountingModel
    let clock: DiagnosticsAccountingClock
    let frameBackend: DiagnosticsAccountingFrameBackend

    func present() {
        // Admit another frame without charging scheduling delay as work.
        clock.now += 0.1
        host.requestDiagnosticsFrame()
        host.windowNeedsDisplay(window)
    }
}

@MainActor
final class LiveDiagnosticsAccountingTests: XCTestCase {
    private func makeHost(usesSceneBackend: Bool = true) -> DiagnosticsAccountingHarness {
        let clock = DiagnosticsAccountingClock()
        let model = DiagnosticsAccountingModel()
        let content = DiagnosticsAccountingContent(model: model, clock: clock)
        let frameBackend = DiagnosticsAccountingFrameBackend(clock: clock)
        let batchBackend: FakeBatchRenderBackend? = usesSceneBackend ? FakeBatchRenderBackend() : nil
        let surface = SurfaceDescriptor(
            windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
            pixelSize: IntSize(width: 320, height: 200), scaleFactor: 1)
        let window = Win32Window(title: "Diagnostic accounting", clientSize: surface.pixelSize)
        window.testMonitorRefreshRateOverride = 60
        let host = WinSwiftUIWindowHost(
            configuration: WindowGroupConfiguration(
                title: "Diagnostic accounting", size: surface.pixelSize, clearColor: .black,
                content: [AnyView(content)]),
            platformWindow: window,
            renderer: frameBackend,
            batchRenderer: batchBackend,
            surfaceDescriptorProvider: { _ in surface },
            sceneRenderer: { runtime, timestamp in
                let scene = runtime.renderScene(at: timestamp)
                clock.now += clock.frameSeconds
                return scene
            },
            startupPresentationMode: .automatic,
            startupProbeConfiguration: nil)
        host.frameClock = { clock.now }
        host.hostedRuntime.clock = { clock.now }
        host.windowDidCreate(window)
        host.resetObservabilityCounters()

        // Startup is outside the sampled interval. Only a body evaluation
        // during a subsequent real host reload advances the rebuild clock.
        clock.rebuildSeconds = 0.006
        clock.frameSeconds = 0.004
        host.hostedRuntime.collectsPhaseTimings = true
        host.onFramePresented = { clock.samples.append($0) }
        return DiagnosticsAccountingHarness(
            host: host, window: window, content: content, model: model,
            clock: clock, frameBackend: frameBackend)
    }

    private func assertTiming(
        _ sample: LiveFrameSample,
        rebuild: Double,
        total: Double,
        outsideFrame: Double,
        userVisible: Double,
        rebuildCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(sample.rebuildSeconds, rebuild, accuracy: 0.000_000_001, file: file, line: line)
        XCTAssertEqual(sample.totalSeconds, total, accuracy: 0.000_000_001, file: file, line: line)
        XCTAssertEqual(
            sample.outsideFrameRebuildSeconds, outsideFrame, accuracy: 0.000_000_001, file: file, line: line)
        XCTAssertEqual(
            sample.userVisibleCostSeconds, userVisible, accuracy: 0.000_000_001, file: file, line: line)
        XCTAssertEqual(sample.rebuildCount, rebuildCount, file: file, line: line)
    }

    func testDeferredObservedRebuildIsIncludedInFrameTimeWithoutBeingChargedTwice() async throws {
        let harness = makeHost()
        harness.model.revision = 1
        XCTAssertEqual(harness.host.scheduledReloadCount, 1)
        XCTAssertEqual(harness.host.executedReloadCount, 0)

        // No actor yield: the admitted frame, not the queued Task fallback,
        // must consume this observed-object rebuild.
        harness.present()

        XCTAssertEqual(harness.host.executedReloadCount, 1)
        XCTAssertEqual(harness.clock.samples.count, 1)
        let sample = try XCTUnwrap(harness.clock.samples.last)
        assertTiming(sample, rebuild: 0.006, total: 0.010, outsideFrame: 0, userVisible: 0.010, rebuildCount: 1)
        XCTAssertTrue(sample.rebuildPhaseTimingsAvailable)
    }

    func testSynchronousStateRebuildIsAddedOutsideTheFollowingFrameTime() async throws {
        let harness = makeHost()
        harness.content.$stateRevision.wrappedValue = 1
        XCTAssertEqual(harness.host.executedReloadCount, 1)
        XCTAssertTrue(harness.clock.samples.isEmpty)

        harness.present()

        let sample = try XCTUnwrap(harness.clock.samples.last)
        assertTiming(sample, rebuild: 0.006, total: 0.004, outsideFrame: 0.006, userVisible: 0.010, rebuildCount: 1)
    }

    func testMixedRebuildsAddOnlyTheOutsidePortionToTotalFrameTime() async throws {
        let harness = makeHost()
        harness.content.$stateRevision.wrappedValue = 1
        harness.model.revision = 1
        XCTAssertEqual(harness.host.executedReloadCount, 1)

        harness.present()

        XCTAssertEqual(harness.host.executedReloadCount, 2)
        let sample = try XCTUnwrap(harness.clock.samples.last)
        assertTiming(sample, rebuild: 0.012, total: 0.010, outsideFrame: 0.006, userVisible: 0.016, rebuildCount: 2)
    }

    func testPresentedFrameDrainsAllRebuildCountersBeforeTheNextSample() async throws {
        let harness = makeHost()
        harness.content.$stateRevision.wrappedValue = 1
        harness.model.revision = 1
        harness.present()
        XCTAssertEqual(harness.clock.samples.count, 1)

        harness.present()

        XCTAssertEqual(harness.clock.samples.count, 2)
        let sample = try XCTUnwrap(harness.clock.samples.last)
        assertTiming(sample, rebuild: 0, total: 0.004, outsideFrame: 0, userVisible: 0.004, rebuildCount: 0)
        XCTAssertFalse(sample.rebuildPhaseTimingsAvailable)
        XCTAssertEqual(sample.composeSeconds, 0)
        XCTAssertEqual(sample.nodeConstructionSeconds, 0)
        XCTAssertEqual(sample.reconcileSeconds, 0)
        XCTAssertEqual(harness.host.executedReloadCount, 2)
    }

    func testFailedFrameCarriesItsDeferredRebuildIntoTheNextSamplesOutsideCost() async throws {
        let harness = makeHost(usesSceneBackend: false)
        harness.frameBackend.shouldFail = true
        harness.model.revision = 1
        let presentationsBeforeFailure = harness.frameBackend.renderedFrameCount

        harness.present()

        XCTAssertEqual(harness.host.executedReloadCount, 1)
        XCTAssertTrue(harness.clock.samples.isEmpty)
        XCTAssertEqual(harness.frameBackend.renderedFrameCount, presentationsBeforeFailure)

        harness.frameBackend.shouldFail = false
        harness.present()

        XCTAssertEqual(harness.clock.samples.count, 1)
        XCTAssertEqual(harness.frameBackend.renderedFrameCount, presentationsBeforeFailure + 1)
        let sample = try XCTUnwrap(harness.clock.samples.last)
        assertTiming(sample, rebuild: 0.006, total: 0.004, outsideFrame: 0.006, userVisible: 0.010, rebuildCount: 1)

        harness.present()
        let followingSample = try XCTUnwrap(harness.clock.samples.last)
        assertTiming(followingSample, rebuild: 0, total: 0.004, outsideFrame: 0, userVisible: 0.004, rebuildCount: 0)
    }

    func testNestedStateRebuildCountsItsInclusiveWallIntervalOnlyOnce() async throws {
        let harness = makeHost()
        harness.clock.rebuildSeconds = 0.002
        harness.clock.onNextBodyEvaluation = {
            // The outer body spends 2ms before this callback, the nested
            // rebuild spends 2ms, then the outer body spends its final 2ms.
            // The one-shot callback is cleared before invocation.
            harness.content.$stateRevision.wrappedValue = 2
            harness.clock.now += 0.002
        }

        harness.content.$stateRevision.wrappedValue = 1

        XCTAssertEqual(harness.host.executedReloadCount, 2)
        XCTAssertTrue(harness.clock.samples.isEmpty)
        harness.present()

        let sample = try XCTUnwrap(harness.clock.samples.last)
        assertTiming(sample, rebuild: 0.006, total: 0.004, outsideFrame: 0.006, userVisible: 0.010, rebuildCount: 2)
        XCTAssertFalse(sample.rebuildPhaseTimingsAvailable, "Nested reload snapshots cannot attribute all phase work.")
    }
}
