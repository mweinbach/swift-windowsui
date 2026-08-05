import SwiftWindowsCore
import SwiftWindowsGraphics

@preconcurrency import XCTest

@testable import SwiftWindowsPlatform

@testable import SwiftWindowsUI

@testable import WinSwiftUI

// The duplicate-present gate. Pixel capture on the machine that motivated the
// pacing work showed ~40 % of the frames presented during a hover fade were
// byte-identical to the previous frame: the animation timer ticked, no
// animated value moved far enough to dirty the tree, and the frame loop
// shipped the cached scene anyway because `pendingPresentation` was standing.
// Each of those presents cost a bind, a submit, a present and (self-paced) a
// whole schedule slot, and changed nothing a user could see.
//
// The rule these tests pin: while an animation is active, a frame whose
// content revision already sits on screen is skipped — the animation's next
// tick supplies the frame that differs. An idle window keeps presenting on
// request, because its presents are driven by explicit demand (a diagnostics
// pump, the input-rate tracker) and refusing them would starve the loop that
// asked. A device rebuild presents unconditionally: the swap chain's pixels
// are gone even though the revision says nothing changed.

@MainActor
final class IdenticalPresentSkipTests: XCTestCase {
    private static let surface = SurfaceDescriptor(
        windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
        pixelSize: IntSize(width: 320, height: 200),
        scaleFactor: 1.0
    )

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

    /// One paint request through the same entry points the wndproc uses.
    private func pumpFrame(host: WinSwiftUIWindowHost, window: Win32Window) {
        host.requestDiagnosticsFrame()
        host.windowNeedsDisplay(window)
    }

    func testAnAnimatingFrameWithUnchangedContentIsNotPresented() async {
        let batch = FakeBatchRenderBackend()
        let clock = FakeRecoveryClock(5_000)
        let log = FrameLog()
        let (host, window) = makeHost(batch: batch, clock: clock, log: log)

        // An animation with nothing tweening per tick — a phase animator
        // waiting out its phase — is exactly the state that produced the
        // measured duplicates: `hasActiveAnimations` true, tree clean.
        clock.now += 0.020
        host.hostedRuntime.scheduleDeferredRebuild(key: "skip-test", delay: 10_000) {}
        pumpFrame(host: host, window: window)
        let presentsAfterRealChange = batch.renderedScenes.count
        XCTAssertGreaterThan(presentsAfterRealChange, 0)

        clock.now += 0.020
        pumpFrame(host: host, window: window)

        XCTAssertEqual(
            batch.renderedScenes.count,
            presentsAfterRealChange,
            "A frame that is byte-identical to the one on screen must not be presented while animating."
        )
        XCTAssertEqual(host.skippedIdenticalPresentCount, 1)
        XCTAssertTrue(
            host.currentTimerState.isEnabled,
            "The skip relies on the animation's next tick; the frame loop must stay armed."
        )
    }

    func testTheFrameAfterARealChangePresentsAgain() async {
        let batch = FakeBatchRenderBackend()
        let clock = FakeRecoveryClock(5_000)
        let log = FrameLog()
        let (host, window) = makeHost(batch: batch, clock: clock, log: log)

        clock.now += 0.020
        host.hostedRuntime.scheduleDeferredRebuild(key: "skip-test", delay: 10_000) {}
        pumpFrame(host: host, window: window)
        clock.now += 0.020
        pumpFrame(host: host, window: window)
        let presentsAfterSkip = batch.renderedScenes.count

        // The animation advances: something actually changes. (Scheduling a
        // deferred rebuild dirties the tree through the runtime's own
        // invalidation path, the same way an advancing tween does.)
        clock.now += 0.020
        host.hostedRuntime.scheduleDeferredRebuild(key: "skip-test-2", delay: 10_000) {}
        pumpFrame(host: host, window: window)

        XCTAssertEqual(
            batch.renderedScenes.count,
            presentsAfterSkip + 1,
            "The next content change must flow to the screen immediately; the skip drops duplicates, never changes."
        )
    }

    func testAnIdleWindowStillPresentsOnRequest() async {
        let batch = FakeBatchRenderBackend()
        let clock = FakeRecoveryClock(5_000)
        let log = FrameLog()
        let (host, window) = makeHost(batch: batch, clock: clock, log: log)

        let presentsAfterCreation = batch.renderedScenes.count

        // No animation is running, so no future tick would deliver a deferred
        // frame. Explicit requests (the diagnostics pump, the input-rate
        // tracker) must keep presenting, or the loop that asked starves.
        clock.now += 0.020
        pumpFrame(host: host, window: window)

        XCTAssertEqual(batch.renderedScenes.count, presentsAfterCreation + 1)
        XCTAssertEqual(host.skippedIdenticalPresentCount, 0)
    }

    func testADeviceRebuildPresentsEvenIdenticalContent() async {
        let batch = FakeBatchRenderBackend()
        let clock = FakeRecoveryClock(5_000)
        let log = FrameLog()
        let (host, window) = makeHost(batch: batch, clock: clock, log: log)

        clock.now += 0.020
        host.hostedRuntime.scheduleDeferredRebuild(key: "skip-test", delay: 10_000) {}
        pumpFrame(host: host, window: window)
        let presentsBefore = batch.renderedScenes.count

        // The backend rebuilt its device: the swap chain is new and blank,
        // and "the revision is already on screen" is no longer true.
        batch.presentationState = PresentationState(isOccluded: false, needsImmediateRepaint: true)
        clock.now += 0.020
        pumpFrame(host: host, window: window)

        XCTAssertEqual(
            batch.renderedScenes.count,
            presentsBefore + 1,
            "A rebuilt device owes the screen a frame whatever the revision bookkeeping says."
        )
        XCTAssertEqual(host.skippedIdenticalPresentCount, 0)
    }
}
