import SwiftWindowsCore
import SwiftWindowsGraphics

@preconcurrency import XCTest

@testable import SwiftWindowsPlatform

@testable import SwiftWindowsUI

@testable import WinSwiftUI

// L8-PRESENT, second half: once the backend stops waiting on `Present`,
// something has to stop the frame loop from free-running. On this machine an
// unpaced ten-second run produced 17 791 frames — 1481 fps of work on a 60 Hz
// display, which is a battery bill and a fan, not a smoother window. The gate
// below is what makes "self-paced" mean paced.

@MainActor
final class SelfPacedFrameGateTests: XCTestCase {
    private static let surface = SurfaceDescriptor(
        windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
        pixelSize: IntSize(width: 320, height: 200),
        scaleFactor: 1.0
    )

    /// Reference-type collector so the injected scene renderer does not capture
    /// a mutable local.
    @MainActor
    private final class FrameLog {
        var count = 0
    }

    private func makeHost(
        batch: FakeBatchRenderBackend,
        clock: FakeRecoveryClock,
        log: FrameLog
    ) -> (WinSwiftUIWindowHost, Win32Window) {
        let host = WinSwiftUIWindowHost(
            configuration: WindowGroupConfiguration(
                title: "Test",
                size: IntSize(width: 320, height: 200),
                clearColor: .black,
                content: []
            ),
            renderer: FakeRenderBackend(),
            batchRenderer: batch,
            surfaceDescriptorProvider: { _ in Self.surface },
            sceneRenderer: { runtime, timestamp in
                log.count += 1
                return runtime.renderScene(at: timestamp)
            },
            startupProbeConfiguration: nil
        )
        host.frameClock = { clock.now }

        let window = Win32Window(title: "Test", clientSize: IntSize(width: 320, height: 200))
        window.testMonitorRefreshRateOverride = 60
        host.windowDidCreate(window)
        return (host, window)
    }

    /// Drives `count` paint requests, advancing the frame clock by
    /// `stepSeconds` between them, and returns how many reached the renderer.
    private func drive(
        host: WinSwiftUIWindowHost,
        window: Win32Window,
        clock: FakeRecoveryClock,
        log: FrameLog,
        count: Int,
        stepSeconds: Double
    ) -> Int {
        let before = log.count
        for _ in 0..<count {
            host.requestDiagnosticsFrame()
            host.windowNeedsDisplay(window)
            clock.now += stepSeconds
        }
        return log.count - before
    }

    func testADisplayPacedHostDoesNotGateFrames() async {
        let batch = FakeBatchRenderBackend()
        let clock = FakeRecoveryClock(5_000)
        let log = FrameLog()
        let (host, window) = makeHost(batch: batch, clock: clock, log: log)

        let rendered = drive(host: host, window: window, clock: clock, log: log, count: 30, stepSeconds: 0.001)

        XCTAssertEqual(
            rendered,
            30,
            "While the display paces presents, a second pacer would only fight it: the present is the gate."
        )
    }

    func testASelfPacedHostRefusesFramesThatArriveInsideTheDisplayPeriod() async {
        let batch = FakeBatchRenderBackend()
        let clock = FakeRecoveryClock(5_000)
        let log = FrameLog()
        let (host, window) = makeHost(batch: batch, clock: clock, log: log)

        batch.presentPacing = PresentPacingStatus(mode: .selfPaced, displayFrameInterval: 1.0 / 60.0)

        // Thirty paint requests one millisecond apart: the shape of a live
        // diagnostics run, which asks for the next frame the instant the last
        // one lands, and of any sustained pending-presentation loop.
        let rendered = drive(host: host, window: window, clock: clock, log: log, count: 30, stepSeconds: 0.001)

        let refreshRate = Int(host.currentTimerState.refreshRate)
        let ceiling = Int((0.030 * Double(refreshRate)).rounded(.up)) + 1
        XCTAssertLessThanOrEqual(
            rendered,
            ceiling,
            "Self-paced means paced: 30 ms of requests must not become 30 frames on a \(refreshRate) Hz display."
        )
        XCTAssertGreaterThanOrEqual(rendered, 1, "The gate paces frames; it must never stop them.")
    }

    func testASelfPacedHostStillRendersAtTheDisplayCadenceOverTime() async {
        let batch = FakeBatchRenderBackend()
        let clock = FakeRecoveryClock(5_000)
        let log = FrameLog()
        let (host, window) = makeHost(batch: batch, clock: clock, log: log)

        batch.presentPacing = PresentPacingStatus(mode: .selfPaced, displayFrameInterval: 1.0 / 60.0)

        // One simulated second of requests at 1 kHz. A gate that merely
        // throttled would under-deliver; the point is to hit the display's own
        // cadence, which is what turns 4 fps back into 60.
        let rendered = drive(host: host, window: window, clock: clock, log: log, count: 1_000, stepSeconds: 0.001)

        XCTAssertGreaterThanOrEqual(
            rendered,
            55,
            "A second of self-paced frames on a 60 Hz display is about 60 frames, not a slideshow."
        )
        XCTAssertLessThanOrEqual(
            rendered,
            70,
            "And not a thousand: frames the display cannot show cost battery and buy nothing."
        )
    }

    func testADeferredFrameArmsTheTimerForTheRemainderRatherThanSpinning() async {
        let batch = FakeBatchRenderBackend()
        let clock = FakeRecoveryClock(5_000)
        let log = FrameLog()
        let (host, window) = makeHost(batch: batch, clock: clock, log: log)

        batch.presentPacing = PresentPacingStatus(mode: .selfPaced, displayFrameInterval: 1.0 / 60.0)

        // The first request opens the schedule; the second lands 1 ms later and
        // has to be deferred rather than dropped.
        host.requestDiagnosticsFrame()
        host.windowNeedsDisplay(window)
        clock.now += 0.001
        let renderedBeforeSecond = log.count
        host.requestDiagnosticsFrame()
        host.windowNeedsDisplay(window)

        XCTAssertEqual(log.count, renderedBeforeSecond, "The second request is inside the display period.")
        XCTAssertTrue(host.currentTimerState.isEnabled, "A deferred frame is owed a wake-up, or it never happens.")
        XCTAssertGreaterThanOrEqual(
            host.currentTimerState.intervalMilliseconds,
            1,
            "A zero-millisecond timer is a spin with extra steps."
        )
        XCTAssertLessThanOrEqual(
            host.currentTimerState.intervalMilliseconds,
            expectedTimerInterval(for: host.currentTimerState.refreshRate),
            "The wake-up must land at the deadline, not a whole display period past it."
        )
    }

    /// Emulates the real frame loop under a 1 ms-accurate timer, which is what
    /// the resolution hold (`Win32Window.updateTimerResolutionHold`) buys: a
    /// paint request lands immediately (`InvalidateRect` → `WM_PAINT`), and
    /// when the gate defers it, the wake the host armed arrives exactly its
    /// interval later. Returns the frame-clock timestamps of rendered frames.
    private func driveOnArmedTimerCadence(
        host: WinSwiftUIWindowHost,
        window: Win32Window,
        clock: FakeRecoveryClock,
        log: FrameLog,
        seconds: Double
    ) -> [Double] {
        var renderedAt: [Double] = []
        let endAt = clock.now + seconds
        while clock.now < endAt {
            let before = log.count
            host.requestDiagnosticsFrame()
            host.windowNeedsDisplay(window)
            if log.count > before {
                renderedAt.append(clock.now)
            }

            // Sleep to the wake the host just armed, then deliver it.
            let interval = Double(max(host.currentTimerState.intervalMilliseconds, 1)) / 1000.0
            clock.now += interval
            let beforeTick = log.count
            host.window(window, animationFrameAt: clock.now)
            if log.count > beforeTick {
                renderedAt.append(clock.now)
            }
        }
        return renderedAt
    }

    /// The 62-on-60Hz overshoot, pinned. The gate used to schedule on the
    /// runtime's pacing floor (~14.4 ms) because the timers underneath it ran
    /// on the 15.6 ms system tick; once the host holds 1 ms resolution while
    /// animating, wakes land at their deadlines and the schedule must be the
    /// display period itself — ~60 delivered frames a second with a median
    /// gap on the period, not ~70 invented slots filled with replays.
    func testASelfPacedHostLocksToTheDisplayPeriodOnceWakesLandOnTime() async {
        let batch = FakeBatchRenderBackend()
        let clock = FakeRecoveryClock(5_000)
        let log = FrameLog()
        let (host, window) = makeHost(batch: batch, clock: clock, log: log)

        batch.presentPacing = PresentPacingStatus(mode: .selfPaced, displayFrameInterval: 1.0 / 60.0)

        let renderedAt = driveOnArmedTimerCadence(host: host, window: window, clock: clock, log: log, seconds: 2.0)

        let framesPerSecond = Double(renderedAt.count) / 2.0
        XCTAssertGreaterThanOrEqual(framesPerSecond, 57, "The schedule must still deliver the display's rate.")
        XCTAssertLessThanOrEqual(
            framesPerSecond,
            61.5,
            "62+ fps on a 60 Hz display is the gate presenting frames the display has no slot for."
        )

        let gaps = zip(renderedAt.dropFirst(), renderedAt).map { ($0 - $1) * 1000 }.sorted()
        let medianGap = gaps[gaps.count / 2]
        XCTAssertGreaterThanOrEqual(
            medianGap,
            15.9,
            "A median gap under the display period means the schedule is running ahead of the display."
        )
        XCTAssertLessThanOrEqual(medianGap, 17.5, "And a median gap far over it means dropped slots.")
    }

    func testTheHostTellsTheBackendWhatOneDisplayPeriodCosts() async {
        let batch = FakeBatchRenderBackend()
        let clock = FakeRecoveryClock(5_000)
        let log = FrameLog()
        let (host, window) = makeHost(batch: batch, clock: clock, log: log)

        XCTAssertEqual(
            batch.displayFrameIntervals.last ?? 0,
            1.0 / 60.0,
            accuracy: 1e-9,
            "A watchdog with no display period cannot tell a healthy present from a quarter-second one."
        )

        window.testMonitorRefreshRateOverride = 144
        host.windowDidChangeDisplay(window)

        XCTAssertEqual(
            batch.displayFrameIntervals.last ?? 0,
            1.0 / 144.0,
            accuracy: 1e-9,
            "A docked laptop changes what being on time means; the watchdog has to hear about it."
        )
    }

    func testHealthReportsTheModeTheActiveBackendIsIn() async {
        let batch = FakeBatchRenderBackend()
        let clock = FakeRecoveryClock(5_000)
        let log = FrameLog()
        let (host, _) = makeHost(batch: batch, clock: clock, log: log)

        XCTAssertEqual(host.rendererHealthSnapshot.presentPacing.mode, .displayPaced)

        batch.presentPacing = PresentPacingStatus(
            mode: .selfPaced,
            displayFrameInterval: 1.0 / 60.0,
            medianPresentSeconds: 0.2554,
            engagementCount: 1
        )

        let health = host.rendererHealthSnapshot
        XCTAssertEqual(
            health.presentPacing.mode,
            .selfPaced,
            "A 4 fps window whose own frame cost is 0.6 ms is only explicable if this field is readable."
        )
        XCTAssertEqual(health.presentPacing.engagementCount, 1)
        XCTAssertEqual(health.presentPacing.medianPresentSeconds, 0.2554, accuracy: 1e-9)
    }
}
