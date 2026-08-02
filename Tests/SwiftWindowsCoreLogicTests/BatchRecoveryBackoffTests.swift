import SwiftWindowsCore
import SwiftWindowsGraphics

@preconcurrency import XCTest

@testable import SwiftWindowsPlatform

@testable import SwiftWindowsUI

@testable import WinSwiftUI

// WS-11: the recovery flap.
//
// `scheduleBatchBackendRecoveryIfNeeded` reset the backoff on *every*
// downgrade, and the recovery attempt only extended it when `attach` threw.
// But `createDeviceIfNeeded`, the factory and `createSwapChain` all early-out
// on a live device, so re-attaching a healthy backend whose *scene* fails
// succeeds trivially — and the app oscillated between two visibly different
// presenters every 5 seconds for the rest of the session, burning a full
// scene build and a failed present per cycle. The ladder now survives
// downgrades and is only retired by frames that actually reach the screen,
// and a `.sceneContent` failure is not retried against the scene that
// produced it.

@MainActor
final class BatchRecoveryBackoffTests: XCTestCase {
    private let policy = BatchBackendRecoveryPolicy(
        isEnabled: true, initialRetryInterval: 5, maxRetryInterval: 60, backoffMultiplier: 2)

    private func makeSurface(pixelSize: IntSize = IntSize(width: 320, height: 200)) -> SurfaceDescriptor {
        SurfaceDescriptor(
            windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
            pixelSize: pixelSize,
            scaleFactor: 1.0
        )
    }

    private func makeHost(
        batchRenderer: any BatchRenderBackend,
        clock: FakeRecoveryClock
    ) -> (host: WinSwiftUIWindowHost, window: Win32Window) {
        let surface = makeSurface()
        let host = WinSwiftUIWindowHost(
            configuration: WindowGroupConfiguration(
                title: "Test",
                size: surface.pixelSize,
                clearColor: .black,
                content: []
            ),
            renderer: FakeRenderBackend(),
            batchRenderer: batchRenderer,
            surfaceDescriptorProvider: { _ in surface },
            startupProbeConfiguration: nil,
            recoveryPolicy: policy
        )
        host.recoveryClock = { clock.now }
        host.frameClock = { clock.now }
        let window = Win32Window(title: "Test", clientSize: surface.pixelSize)
        host.windowDidCreate(window)
        return (host, window)
    }

    /// A backend whose `attach` always succeeds and whose `render` always
    /// fails is exactly the flap's shape. The countdown must climb the ladder
    /// instead of resetting to 5 s forever.
    func testRepeatedSceneRenderFailuresGrowTheBackoffAcrossDowngrades() async {
        let batchRenderer = FakeBatchRenderBackend()
        let clock = FakeRecoveryClock(1_000)
        let (host, window) = makeHost(batchRenderer: batchRenderer, clock: clock)

        batchRenderer.setRenderShouldFail(true)
        host.window(window, didResizeTo: IntSize(width: 640, height: 480))
        host.windowNeedsDisplay(window)

        XCTAssertEqual(host.rendererHealthSnapshot.activeBackend, .frame)
        XCTAssertEqual(
            host.rendererHealthSnapshot.nextBatchRecoveryInSeconds ?? -1,
            5,
            accuracy: 0.001,
            "The first downgrade of a healthy session still starts at the policy's initial interval."
        )

        var observedIntervals: [Double] = []
        for _ in 0..<4 {
            // Past the countdown: the attach succeeds trivially, the same
            // scene fails again, and we downgrade a second time.
            clock.now += 61
            host.window(window, didResizeTo: IntSize(width: 320, height: 200))
            host.windowNeedsDisplay(window)
            host.window(window, didResizeTo: IntSize(width: 640, height: 480))
            host.windowNeedsDisplay(window)
            observedIntervals.append(host.rendererHealthSnapshot.nextBatchRecoveryInSeconds ?? -1)
        }

        XCTAssertEqual(observedIntervals.count, 4)
        for (index, expected) in [10.0, 20.0, 40.0, 60.0].enumerated() {
            XCTAssertEqual(
                observedIntervals[index],
                expected,
                accuracy: 0.001,
                "Downgrade \(index + 2) must carry the ladder, not reset it: got \(observedIntervals)."
            )
        }
    }

    /// The other half of the policy: a scene backend that actually works pays
    /// off the ladder, so an unrelated failure hours later starts at 5 s again.
    func testASustainedHealthySceneRunRetiresTheBackoffLadder() async {
        let batchRenderer = FakeBatchRenderBackend()
        let clock = FakeRecoveryClock(1_000)
        let (host, window) = makeHost(batchRenderer: batchRenderer, clock: clock)

        batchRenderer.setRenderShouldFail(true)
        host.window(window, didResizeTo: IntSize(width: 640, height: 480))
        host.windowNeedsDisplay(window)
        XCTAssertEqual(host.rendererHealthSnapshot.activeBackend, .frame)

        // Heal and promote.
        batchRenderer.setRenderShouldFail(false)
        clock.now += 6
        host.window(window, didResizeTo: IntSize(width: 320, height: 200))
        host.windowNeedsDisplay(window)
        XCTAssertEqual(host.rendererHealthSnapshot.activeBackend, .scene)

        // Present a long run of healthy frames.
        for index in 0..<40 {
            clock.now += 0.02
            host.window(window, didResizeTo: IntSize(width: 320 + Int32(index % 2), height: 200))
            host.windowNeedsDisplay(window)
        }

        // A brand-new failure after a proven-good run is new information.
        batchRenderer.setRenderShouldFail(true)
        clock.now += 1
        host.window(window, didResizeTo: IntSize(width: 640, height: 480))
        host.windowNeedsDisplay(window)

        XCTAssertEqual(host.rendererHealthSnapshot.activeBackend, .frame)
        XCTAssertEqual(
            host.rendererHealthSnapshot.nextBatchRecoveryInSeconds ?? -1,
            5,
            accuracy: 0.001,
            "A downgrade after a sustained healthy run must restart the ladder."
        )
    }

    /// WS-02's typed failure, consumed. `.sceneContent` says *this scene*
    /// cannot be rendered, so promoting the backend before the tree changes
    /// submits the same scene and flips the app's appearance twice for
    /// nothing.
    func testSceneContentFailureIsNotRetriedAgainstTheSameScene() async {
        let batchRenderer = FakeBatchRenderBackend()
        let clock = FakeRecoveryClock(1_000)
        let (host, window) = makeHost(batchRenderer: batchRenderer, clock: clock)

        batchRenderer.failureError = SceneContentFailure()
        batchRenderer.setRenderShouldFail(true)
        host.window(window, didResizeTo: IntSize(width: 640, height: 480))
        host.windowNeedsDisplay(window)

        XCTAssertEqual(host.rendererHealthSnapshot.activeBackend, .frame)
        XCTAssertEqual(host.rendererHealthSnapshot.lastPresentationFailureKind, .sceneContent)

        let attachesAtDowngrade = batchRenderer.attachedSurfaces.count
        let scenesAtDowngrade = batchRenderer.renderedScenes.count

        // The content never changes; the countdown elapses repeatedly.
        for _ in 0..<6 {
            clock.now += 120
            host.windowNeedsDisplay(window)
        }

        XCTAssertEqual(
            batchRenderer.attachedSurfaces.count,
            attachesAtDowngrade,
            "A scene-content failure must not re-attach the backend while the scene is unchanged."
        )
        XCTAssertEqual(batchRenderer.renderedScenes.count, scenesAtDowngrade)
        XCTAssertEqual(host.rendererHealthSnapshot.activeBackend, .frame)
        XCTAssertEqual(
            host.rendererHealthSnapshot.nextBatchRecoveryInSeconds ?? -1,
            60,
            accuracy: 0.001,
            "Blocked attempts still walk the ladder, so the check itself is not per-frame work forever."
        )

        // Now the content changes and the backend heals: recovery resumes.
        batchRenderer.setRenderShouldFail(false)
        clock.now += 120
        host.window(window, didResizeTo: IntSize(width: 800, height: 600))
        host.windowNeedsDisplay(window)

        XCTAssertEqual(
            host.rendererHealthSnapshot.activeBackend,
            .scene,
            "A changed tree is a different scene; the policy must try again."
        )
    }

    /// A `.permanent` failure is still never scheduled, and the scene-content
    /// gate must not resurrect it.
    func testPermanentFailureSchedulesNothing() async {
        let batchRenderer = FakeBatchRenderBackend()
        let clock = FakeRecoveryClock(1_000)
        let (host, window) = makeHost(batchRenderer: batchRenderer, clock: clock)

        batchRenderer.failureError = PermanentPresentationFailure()
        batchRenderer.setRenderShouldFail(true)
        host.window(window, didResizeTo: IntSize(width: 640, height: 480))
        host.windowNeedsDisplay(window)

        XCTAssertEqual(host.rendererHealthSnapshot.activeBackend, .frame)
        XCTAssertEqual(host.rendererHealthSnapshot.lastPresentationFailureKind, .permanent)
        XCTAssertNil(host.rendererHealthSnapshot.nextBatchRecoveryInSeconds)
    }
}

/// A failure the backend classifies as "this scene, not this device".
private struct SceneContentFailure: ClassifiedPresentationFailure {
    var presentationFailureKind: PresentationFailureKind { .sceneContent }
}

private struct PermanentPresentationFailure: ClassifiedPresentationFailure {
    var presentationFailureKind: PresentationFailureKind { .permanent }
}
