import SwiftWindowsCore
import SwiftWindowsGraphics

@preconcurrency import XCTest

@testable import SwiftWindowsPlatform

@testable import SwiftWindowsUI

@testable import WinSwiftUI

// WS-11: the frame clock and the pacing contract.
//
// Two defects met here. The host's clock was `GetTickCount64`, whose
// resolution is the system clock tick — documented 10–16 ms, typically
// 15.625 ms — and the pacing floor was exactly the vsync period, so a tick
// that arrived 15.6 ms after the last render was refused for being 1 ms early
// and every continuous animation ran at ~30 fps with alternating 15.6/31.2 ms
// spacing. Meanwhile `WM_PAINT` — the path almost every frame actually takes,
// since `requestFrame` invalidates rather than rendering — passed `0`, which
// disables the pacing gate entirely. The clock was coarse where it was
// enforced and absent where it mattered.

@MainActor
final class FrameClockPacingTests: XCTestCase {
    private func makeSurface(pixelSize: IntSize = IntSize(width: 320, height: 200)) -> SurfaceDescriptor {
        SurfaceDescriptor(
            windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
            pixelSize: pixelSize,
            scaleFactor: 1.0
        )
    }

    // MARK: - The clock

    func testFrameClockIsMonotonicAndFinerThanTheSystemTick() async {
        let first = Win32Window.currentTimestampSeconds()
        XCTAssertGreaterThan(first, 0, "The frame clock must be a real monotonic timestamp, not a zero placeholder.")

        var samples: [Double] = []
        // A tick-count clock quantizes to ~15.6 ms, so a tight loop reads the
        // same value many times over. QPC must resolve at least one change
        // across a loop far shorter than a system tick.
        for _ in 0..<20_000 {
            samples.append(Win32Window.currentTimestampSeconds())
        }

        for index in 1..<samples.count {
            XCTAssertGreaterThanOrEqual(samples[index], samples[index - 1], "The frame clock must never go backwards.")
        }

        let distinct = Set(samples.map { ($0 * 1_000_000).rounded() })
        XCTAssertGreaterThan(
            distinct.count,
            1,
            "A clock that cannot resolve anything inside one system tick cannot pace a 60 Hz display."
        )
    }

    // MARK: - The pacing floor

    func testPacingFloorSitsStrictlyBelowTheVsyncPeriod() async {
        for refreshRate in [60, 90, 120, 144] {
            let interval = WinSwiftUIWindowHost.pacingInterval(forRefreshRate: refreshRate)
            let vsyncPeriod = 1.0 / Double(refreshRate)
            XCTAssertLessThan(
                interval,
                vsyncPeriod,
                "A floor at the vsync period drops every tick that lands microseconds early."
            )
            XCTAssertGreaterThan(
                interval,
                vsyncPeriod / 2,
                "The floor must still refuse a second rebuild inside one vsync interval."
            )
        }
    }

    /// The headline number: a 15.625 ms-quantized tick sequence — what a real
    /// Windows frame timer produces on a 60 Hz display — must yield ~60
    /// rebuilt frames per simulated second, not the ~30 the old floor allowed.
    func testQuantizedTickSequenceRendersAtFullRateAtSixtyHertz() async {
        let node = ViewNode(
            frame: Rect(x: 0, y: 0, width: 100, height: 100),
            backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1)
        )
        let runtime = RetainedViewRuntime(root: node)
        runtime.minimumFrameInterval = WinSwiftUIWindowHost.pacingInterval(forRefreshRate: 60)

        let tickInterval = 1.0 / 64.0  // 15.625 ms, the documented system tick
        var renderedFrames = 0
        for tick in 0..<64 {
            // Every tick changes something, exactly as an animation does.
            node.backgroundColor = Color(red: Float(tick % 2), green: 0, blue: 1, alpha: 1)
            _ = runtime.renderScene(at: 1_000.0 + Double(tick) * tickInterval)
            if !runtime.isDirty {
                renderedFrames += 1
            }
        }

        XCTAssertGreaterThanOrEqual(
            renderedFrames,
            55,
            "A 60 Hz session driven by a 15.6 ms clock must render ~60 frames per second, not every other tick."
        )
    }

    func testPacingStillRefusesASecondRebuildInsideOneVsyncInterval() async {
        let node = ViewNode(
            frame: Rect(x: 0, y: 0, width: 100, height: 100),
            backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1)
        )
        let runtime = RetainedViewRuntime(root: node)
        runtime.minimumFrameInterval = WinSwiftUIWindowHost.pacingInterval(forRefreshRate: 60)

        _ = runtime.renderScene(at: 1_000.0)
        XCTAssertFalse(runtime.isDirty)

        node.backgroundColor = Color(red: 0, green: 0, blue: 1, alpha: 1)
        _ = runtime.renderScene(at: 1_000.0 + 0.002)
        XCTAssertTrue(runtime.isDirty, "Two rebuilds 2 ms apart is work nobody can see.")
    }

    // MARK: - Every entry point stamps a real timestamp

    func testPaintDrivenFramesCarryTheMonotonicFrameClock() async {
        let log = FrameTimestampLog()
        let host = WinSwiftUIWindowHost(
            configuration: WindowGroupConfiguration(
                title: "Test",
                size: IntSize(width: 320, height: 200),
                clearColor: .black,
                content: []
            ),
            renderer: FakeRenderBackend(),
            batchRenderer: FakeBatchRenderBackend(),
            surfaceDescriptorProvider: { [surface = makeSurface()] _ in surface },
            sceneRenderer: { runtime, timestamp in
                log.timestamps.append(timestamp)
                return runtime.renderScene(at: timestamp)
            },
            startupProbeConfiguration: nil
        )
        let clock = FakeRecoveryClock(4_242.5)
        host.frameClock = { clock.now }

        let window = Win32Window(title: "Test", clientSize: IntSize(width: 320, height: 200))
        host.windowDidCreate(window)

        XCTAssertFalse(log.timestamps.isEmpty, "The startup frame must reach the scene renderer.")
        XCTAssertEqual(
            log.timestamps.first ?? 0,
            4_242.5,
            accuracy: 0.0001,
            "WM_PAINT-driven frames used to pass 0, which disables pacing on the dominant frame path."
        )

        clock.now += 1
        host.window(window, didResizeTo: IntSize(width: 640, height: 480))
        host.windowNeedsDisplay(window)

        XCTAssertEqual(
            log.timestamps.last ?? 0,
            4_243.5,
            accuracy: 0.0001,
            "Every render entry point must stamp its frame from the same monotonic clock."
        )
        XCTAssertTrue(
            log.timestamps.allSatisfy { $0 > 0 },
            "A zero timestamp is the sentinel that turns the runtime's pacing gate off."
        )
    }

    private func makeAnimatingHost(
        clock: FakeRecoveryClock,
        frame: FakeRenderBackend,
        batch: FakeBatchRenderBackend?
    ) -> (WinSwiftUIWindowHost, Win32Window, ViewNode) {
        let host = WinSwiftUIWindowHost(
            configuration: WindowGroupConfiguration(
                title: "Animation clock", size: IntSize(width: 320, height: 200), clearColor: .black, content: []),
            renderer: frame,
            batchRenderer: batch,
            surfaceDescriptorProvider: { [surface = makeSurface()] _ in surface },
            startupProbeConfiguration: nil)
        host.frameClock = { clock.now }
        host.hostedRuntime.clock = { clock.now }
        let window = Win32Window(title: "Animation clock", clientSize: IntSize(width: 320, height: 200))
        window.testMonitorRefreshRateOverride = 60
        host.windowDidCreate(window)

        clock.now += 0.02
        let node = ViewNode(frame: Rect(x: 0, y: 0, width: 80, height: 40), backgroundColor: .white)
        host.hostedRuntime.root.addChild(node)
        node.animationStates[.opacity] = AnimationState(
            startValue: 1, endValue: 0, startTime: clock.now, duration: 1, easing: .linear)
        return (host, window, node)
    }

    func testPaintFramesAdvanceAndCompleteAnimationsOnBothPresentationPaths() async {
        for usesBatchRenderer in [false, true] {
            let frame = FakeRenderBackend()
            let batch = FakeBatchRenderBackend()
            let clock = FakeRecoveryClock(5_000)
            let (host, window, node) = makeAnimatingHost(
                clock: clock, frame: frame, batch: usesBatchRenderer ? batch : nil)

            clock.now += 0.5
            host.windowNeedsDisplay(window)
            XCTAssertEqual(
                node.opacity, 0.5, accuracy: 0.0001, "A paint must sample the animation at its own timestamp.")
            XCTAssertTrue(host.currentTimerState.isEnabled)
            let presentedBeforeCompletion = usesBatchRenderer ? batch.renderedScenes.count : frame.renderedFrames.count

            clock.now += 0.5
            host.windowNeedsDisplay(window)
            XCTAssertEqual(node.opacity, 0, accuracy: 0.0001)
            XCTAssertFalse(host.hostedRuntime.hasActiveAnimations)
            XCTAssertFalse(host.currentTimerState.isEnabled)
            XCTAssertEqual(
                usesBatchRenderer ? batch.renderedScenes.count : frame.renderedFrames.count,
                presentedBeforeCompletion + 1,
                "The final animation value must reach the presenter before its timer stops.")
        }
    }

    func testSelfPacingAdvancesAnimationsOnlyWhenAFrameIsAdmitted() async {
        let clock = FakeRecoveryClock(5_000)
        let batch = FakeBatchRenderBackend()
        let (host, window, node) = makeAnimatingHost(clock: clock, frame: FakeRenderBackend(), batch: batch)
        batch.presentPacing = PresentPacingStatus(mode: .selfPaced, displayFrameInterval: 1.0 / 60)
        let startedAt = clock.now
        var deferredRebuilds = 0
        host.hostedRuntime.scheduleDeferredRebuild(key: "admitted-frame", delay: 0.003) {
            deferredRebuilds += 1
        }
        host.windowNeedsDisplay(window)
        let initialPresents = batch.renderedScenes.count

        clock.now = startedAt + 0.006
        host.window(window, animationFrameAt: clock.now)
        clock.now = startedAt + 0.010
        host.windowNeedsDisplay(window)
        XCTAssertEqual(node.opacity, 1, accuracy: 0.0001)
        XCTAssertEqual(deferredRebuilds, 0, "A rejected timer wake must not run the next animation phase early.")
        XCTAssertEqual(batch.renderedScenes.count, initialPresents)

        clock.now = startedAt + 1.0 / 60
        host.windowNeedsDisplay(window)
        XCTAssertEqual(node.opacity, 1 - 1.0 / 60, accuracy: 0.0001)
        XCTAssertEqual(deferredRebuilds, 1)
        XCTAssertEqual(batch.renderedScenes.count, initialPresents + 1)
    }
}

/// Reference-type collector so the injected scene renderer does not capture a
/// mutable local.
@MainActor
private final class FrameTimestampLog {
    var timestamps: [Double] = []
}
