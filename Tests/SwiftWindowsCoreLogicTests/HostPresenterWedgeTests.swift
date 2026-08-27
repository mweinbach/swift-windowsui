import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

// WS-10: the host must never turn a failure into a wedge.
//
// Three wedges lived on these paths: a not-ready render branch that
// re-`InvalidateRect`ed itself from inside WM_PAINT (100 % CPU behind a blank
// window, forever), a double fallback failure that left the dead scene backend
// selected and retried it at frame rate while printing twice per frame, and a
// minimize that rebuilt the whole component tree at 0×0. These tests pin the
// bounded behaviour that replaced them; they run headlessly against fake
// backends and a fake wall clock, with no HWND anywhere.

@MainActor
final class HostPresenterWedgeTests: XCTestCase {
    private func makeConfiguration(size: IntSize = IntSize(width: 320, height: 200)) -> WindowGroupConfiguration {
        WindowGroupConfiguration(title: "Test", size: size, clearColor: .black, content: [])
    }

    private func makeSurface(pixelSize: IntSize = IntSize(width: 320, height: 200)) -> SurfaceDescriptor {
        SurfaceDescriptor(
            windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
            pixelSize: pixelSize,
            scaleFactor: 1.0
        )
    }

    // MARK: - No presenter: bounded retry, never a paint loop

    func testMissingSurfaceNeverSelfInvalidatesAcrossRepeatedPaints() async {
        let host = WinSwiftUIWindowHost(
            configuration: makeConfiguration(),
            renderer: FakeRenderBackend(),
            batchRenderer: FakeBatchRenderBackend(),
            surfaceDescriptorProvider: { _ in nil },
            startupProbeConfiguration: nil
        )
        let clock = FakeRecoveryClock(1000)
        host.recoveryClock = { clock.now }

        let window = Win32Window(title: "Test", clientSize: IntSize(width: 320, height: 200))
        host.windowDidCreate(window)

        let invalidatesAfterCreate = window.invalidateRequestCount
        let reportsAfterCreate = host.emittedReportCount

        for _ in 0..<100 {
            host.windowNeedsDisplay(window)
        }

        XCTAssertEqual(
            window.invalidateRequestCount,
            invalidatesAfterCreate,
            "The not-ready render branch must not invalidate: it runs inside WM_PAINT's BeginPaint/EndPaint pair."
        )
        XCTAssertEqual(
            host.emittedReportCount,
            reportsAfterCreate,
            "A paint request with no presenter and no due retry must not log."
        )
        XCTAssertFalse(host.isUsingScenePresentationBackend)
    }

    func testBoundedAttachRetriesEndInObservableTerminalState() async {
        let frameRenderer = FakeRenderBackend(attachShouldFail: true)
        let batchRenderer = FakeBatchRenderBackend(attachShouldFail: true)
        let host = WinSwiftUIWindowHost(
            configuration: makeConfiguration(),
            renderer: frameRenderer,
            batchRenderer: batchRenderer,
            surfaceDescriptorProvider: { [surface = makeSurface()] _ in surface },
            startupProbeConfiguration: nil
        )
        let clock = FakeRecoveryClock(1000)
        host.recoveryClock = { clock.now }

        let window = Win32Window(title: "Test", clientSize: IntSize(width: 320, height: 200))
        host.windowDidCreate(window)

        XCTAssertFalse(host.isPresenterUnavailable, "The first failure schedules a retry rather than giving up.")
        XCTAssertNotNil(
            host.rendererHealthSnapshot.nextPresenterAttachInSeconds,
            "A scheduled retry must be observable in the health snapshot."
        )
        XCTAssertTrue(host.currentTimerState.isEnabled, "The timer drives the retry while one is scheduled.")

        // Walk the whole retry budget. Each pass advances the fake clock past
        // the backoff and delivers one paint request.
        for _ in 0..<12 {
            clock.now += 30
            host.windowNeedsDisplay(window)
        }

        XCTAssertTrue(host.isPresenterUnavailable, "The retry budget is bounded; the host must stop trying.")
        XCTAssertFalse(host.isUsingScenePresentationBackend)
        XCTAssertFalse(host.currentTimerState.isEnabled, "The terminal state must stop requesting frames entirely.")

        let snapshot = host.rendererHealthSnapshot
        XCTAssertTrue(snapshot.isPresenterUnavailable)
        XCTAssertNil(snapshot.nextPresenterAttachInSeconds)
        XCTAssertEqual(snapshot.lastBackendSelectionReason?.probeCode, "presenter-unavailable")
        XCTAssertNotNil(snapshot.lastBackendSelectionReason?.detail)

        // The terminal state is terminal: further paints attach nothing and
        // log nothing.
        let reportsAtTerminal = host.emittedReportCount
        let attachAttempts = frameRenderer.attachedSurfaces.count + batchRenderer.attachedSurfaces.count
        for _ in 0..<50 {
            clock.now += 30
            host.windowNeedsDisplay(window)
        }
        XCTAssertEqual(host.emittedReportCount, reportsAtTerminal)
        XCTAssertEqual(frameRenderer.attachedSurfaces.count + batchRenderer.attachedSurfaces.count, attachAttempts)
    }

    func testAttachRetryRecoversWhenTheBackendHeals() async {
        let frameRenderer = FakeRenderBackend(attachShouldFail: true)
        let batchRenderer = FakeBatchRenderBackend(attachShouldFail: true)
        let host = WinSwiftUIWindowHost(
            configuration: makeConfiguration(),
            renderer: frameRenderer,
            batchRenderer: batchRenderer,
            surfaceDescriptorProvider: { [surface = makeSurface()] _ in surface },
            startupProbeConfiguration: nil
        )
        let clock = FakeRecoveryClock(1000)
        host.recoveryClock = { clock.now }

        let window = Win32Window(title: "Test", clientSize: IntSize(width: 320, height: 200))
        host.windowDidCreate(window)
        XCTAssertEqual(batchRenderer.renderedScenes.count, 0)

        batchRenderer.setAttachShouldFail(false)
        clock.now += 1
        host.window(window, animationFrameAt: clock.now)

        XCTAssertFalse(host.isPresenterUnavailable)
        XCTAssertTrue(host.isUsingScenePresentationBackend, "A healed batch backend is the preferred presenter again.")
        XCTAssertEqual(batchRenderer.attachedSurfaces.count, 1)
        XCTAssertEqual(batchRenderer.renderedScenes.count, 1, "The recovering frame must actually present.")
        XCTAssertNil(host.rendererHealthSnapshot.nextPresenterAttachInSeconds)
    }

    // MARK: - Double fallback failure

    func testDoubleFallbackFailurePinsFrameAndStopsDrivingFrames() async {
        let frameRenderer = FakeRenderBackend()
        let batchRenderer = FakeBatchRenderBackend()
        let host = WinSwiftUIWindowHost(
            configuration: makeConfiguration(),
            renderer: frameRenderer,
            batchRenderer: batchRenderer,
            surfaceDescriptorProvider: { [surface = makeSurface()] _ in surface },
            startupProbeConfiguration: nil
        )
        let clock = FakeRecoveryClock(1000)
        host.recoveryClock = { clock.now }

        let window = Win32Window(title: "Test", clientSize: IntSize(width: 320, height: 200))
        host.windowDidCreate(window)
        XCTAssertTrue(host.isUsingScenePresentationBackend)

        // The adapter goes away: the scene backend cannot present and the
        // frame backend cannot attach to take over.
        batchRenderer.setRenderShouldFail(true)
        frameRenderer.setAttachShouldFail(true)
        host.window(window, didResizeTo: IntSize(width: 640, height: 480))
        host.windowNeedsDisplay(window)

        XCTAssertFalse(
            host.isUsingScenePresentationBackend,
            "A failed fallback must not leave the dead scene backend selected."
        )
        XCTAssertEqual(
            host.currentTimerState.intervalMilliseconds,
            250,
            "With no presenter the timer drops to the coarse attach-retry cadence, not the frame cadence."
        )

        let reportsAfterFailure = host.emittedReportCount
        let sceneRendersAfterFailure = batchRenderer.renderedScenes.count
        let frameRendersAfterFailure = frameRenderer.renderedFrames.count
        let invalidatesAfterFailure = window.invalidateRequestCount

        // The clock does not move, so no retry is due: every one of these
        // paints must be a comparison and nothing else.
        for _ in 0..<100 {
            host.windowNeedsDisplay(window)
        }

        XCTAssertEqual(
            host.emittedReportCount,
            reportsAfterFailure,
            "Reporting must be O(1) in the number of failed frames, not O(frames)."
        )
        XCTAssertEqual(
            batchRenderer.renderedScenes.count,
            sceneRendersAfterFailure,
            "The dead scene path must not be rebuilt and re-attempted every paint."
        )
        XCTAssertEqual(frameRenderer.renderedFrames.count, frameRendersAfterFailure)
        XCTAssertEqual(
            window.invalidateRequestCount,
            invalidatesAfterFailure,
            "The not-ready branch must never re-invalidate from inside WM_PAINT."
        )

        // Nothing recovers: the bounded retry ends in the terminal state
        // rather than flapping for the rest of the session.
        batchRenderer.setAttachShouldFail(true)
        for _ in 0..<12 {
            clock.now += 30
            host.windowNeedsDisplay(window)
        }
        XCTAssertTrue(host.isPresenterUnavailable)
        XCTAssertFalse(host.currentTimerState.isEnabled, "The terminal state stops requesting frames.")
    }

    func testRepeatedFramePathRenderFailuresAreRateLimited() async {
        let frameRenderer = CountingFrameRenderBackend()
        let host = WinSwiftUIWindowHost(
            configuration: makeConfiguration(),
            renderer: frameRenderer,
            batchRenderer: nil,
            surfaceDescriptorProvider: { [surface = makeSurface()] _ in surface },
            startupProbeConfiguration: nil
        )

        let window = Win32Window(title: "Test", clientSize: IntSize(width: 320, height: 200))
        host.windowDidCreate(window)
        frameRenderer.renderShouldFail = true

        let baseline = host.emittedReportCount
        let attemptsBeforeLoop = frameRenderer.renderAttemptCount
        for index in 0..<60 {
            // A resize marks the frame pending, so every pass reaches the
            // renderer instead of short-circuiting on a clean runtime.
            host.window(window, didResizeTo: IntSize(width: 320 + Int32(index % 2), height: 200))
            host.windowNeedsDisplay(window)
        }

        XCTAssertGreaterThanOrEqual(
            frameRenderer.renderAttemptCount - attemptsBeforeLoop,
            60,
            "The frame path must actually have been attempted once per pass."
        )
        XCTAssertLessThanOrEqual(
            host.emittedReportCount - baseline,
            2,
            "A deterministic per-frame render failure must collapse into a rate-limited report."
        )
    }

    // MARK: - Host lifetime across close

    func testClosedHostOutlivesTheCloseCallbackAndIsReleasedAfterwards() async throws {
        let surface = makeSurface()
        let hooks = WindowCoordinatorHooks(
            startWindow: { host in host.windowDidCreate(host.platformWindow) },
            requestCloseWindow: { host in
                guard host.windowShouldClose(host.platformWindow) else { return }
                host.windowWillClose(host.platformWindow)
            },
            runMessageLoop: { 0 },
            terminateMessageLoop: {}
        )
        let configuration = WindowGroupConfiguration(
            title: "Test",
            size: IntSize(width: 320, height: 200),
            clearColor: .black,
            content: [],
            windowID: "doc"
        )
        let coordinator = WinSwiftUIWindowCoordinator(
            sceneConfigurations: [configuration],
            hooks: hooks,
            hostFactory: { configuration, _ in
                WinSwiftUIWindowHost(
                    configuration: configuration,
                    renderer: FakeRenderBackend(),
                    batchRenderer: nil,
                    surfaceDescriptorProvider: { _ in surface },
                    startupProbeConfiguration: nil
                )
            }
        )

        weak var probe: WinSwiftUIWindowHost?
        do {
            let host = try coordinator.bootPrimaryWindow()
            probe = host
            // This is what `WM_DESTROY` runs, inside the wndproc frame.
            host.windowWillClose(host.platformWindow)
        }

        XCTAssertEqual(coordinator.windowCount, 0, "Bookkeeping and the quit policy stay immediate.")
        XCTAssertNotNil(
            probe,
            "The host must not be deallocated by the callback that closed it: its runtime, UIA bridge and backends "
                + "would be torn down while Windows is still delivering messages to their window."
        )

        // Opening the next window drains the deferred release, so a session
        // that keeps opening and closing windows cannot accumulate hosts.
        coordinator.openWindow(payload: WindowActionPayload(id: "doc"))
        XCTAssertNil(probe, "The deferred release must actually happen.")
    }

    // MARK: - Minimize

    func testEmptyClientRectDoesNotResizeTheRootOrTheBackend() async {
        let batchRenderer = FakeBatchRenderBackend()
        let host = WinSwiftUIWindowHost(
            configuration: makeConfiguration(size: IntSize(width: 320, height: 200)),
            renderer: FakeRenderBackend(),
            batchRenderer: batchRenderer,
            surfaceDescriptorProvider: { [surface = makeSurface()] _ in surface },
            startupProbeConfiguration: nil
        )

        let window = Win32Window(title: "Test", clientSize: IntSize(width: 320, height: 200))
        host.windowDidCreate(window)

        let sizeBeforeMinimize = host.currentLogicalRootSize
        let resizesBeforeMinimize = batchRenderer.resizedSizes.count
        let invalidatesBeforeMinimize = window.invalidateRequestCount

        host.window(window, didResizeTo: IntSize(width: 0, height: 0))

        XCTAssertEqual(
            host.currentLogicalRootSize,
            sizeBeforeMinimize,
            "A minimized window must not resize the logical root to zero."
        )
        XCTAssertEqual(
            batchRenderer.resizedSizes.count,
            resizesBeforeMinimize,
            "A minimized window must not resize the swap chain to zero or ask for a frame."
        )
        XCTAssertEqual(window.invalidateRequestCount, invalidatesBeforeMinimize)
    }
}

/// Frame backend that counts render *attempts*, including the ones that throw.
/// The shared fake only records successes, and the rate-limiting assertion
/// needs to know the failing path was actually walked every pass.
@MainActor
private final class CountingFrameRenderBackend: RenderBackend {
    private(set) var renderAttemptCount = 0
    var renderShouldFail = false

    var backendDisplayName: String { "COUNTING FRAME" }
    var backendStatusDescription: String { "Counting Frame Backend" }

    func attach(to surface: SurfaceDescriptor) throws {}
    func resize(to size: IntSize) throws {}

    func render(frame: RenderFrame) throws {
        renderAttemptCount += 1
        if renderShouldFail {
            throw FakeRenderBackendError.renderFailure
        }
    }

    /// Owns no platform resources, so teardown really is nothing — stated
    /// rather than inherited, which is the point of `detach()` having no
    /// protocol-extension default.
    func detach() {}
}
