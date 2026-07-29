import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Phase 6 frame fallback policy — failure injection through the real host.
/// Expands the existing downgrade/recovery coverage with three policy locks:
///
/// 1. A mid-session batch failure downgrades to the frame backend and the
///    frame delivered there carries *real, readable* content (text bitmaps,
///    chrome fills) whose every command is paintable after
///    `FramePathDegradation` — nothing the frame backend receives is
///    silently dropped.
/// 2. Recovery success under `.standard` restores scene rendering and the
///    public `rendererHealthSnapshot` reflects each transition.
/// 3. Backoff and `.disabled` pinning keep their documented health-snapshot
///    shape across the cycle.
@MainActor
final class FrameFallbackPolicyTests: XCTestCase {

    /// Real content: a text label (rides NativeTextRenderer bitmaps on the
    /// frame path) plus a Canvas vector stroke (arrives as `strokePath`, the
    /// command class the frame backend can only paint after degradation).
    private struct FallbackProbeView: View {
        var body: some View {
            VStack(spacing: 8) {
                Text("Fallback Readable Content")
                    .padding(4)
                    .background(Color.blue)
                Canvas { context, size in
                    var path = Path()
                    path.move(to: CGPoint(x: 2, y: size.height - 2))
                    path.addLine(to: CGPoint(x: size.width / 2, y: 2))
                    path.addLine(to: CGPoint(x: size.width - 2, y: size.height - 2))
                    context.stroke(path, with: .color(.red), lineWidth: 2)
                }
                .frame(width: 96, height: 48)
            }
        }
    }

    private func makeSurface(pixelSize: IntSize = IntSize(width: 320, height: 200)) -> SurfaceDescriptor {
        SurfaceDescriptor(
            windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
            pixelSize: pixelSize,
            scaleFactor: 1.0
        )
    }

    private func makeHost(
        content: [AnyView] = [],
        recoveryPolicy: BatchBackendRecoveryPolicy = .standard,
        frameRenderer: FakeRenderBackend = FakeRenderBackend(),
        batchRenderer: FakeBatchRenderBackend = FakeBatchRenderBackend()
    ) -> (host: WinSwiftUIWindowHost, window: Win32Window) {
        let surface = makeSurface()
        let config = WindowGroupConfiguration(
            title: "Test",
            size: surface.pixelSize,
            clearColor: .black,
            content: content
        )
        let host = WinSwiftUIWindowHost(
            configuration: config,
            renderer: frameRenderer,
            batchRenderer: batchRenderer,
            surfaceDescriptorProvider: { _ in surface },
            recoveryPolicy: recoveryPolicy
        )
        let window = Win32Window(title: "Test", clientSize: surface.pixelSize)
        host.windowDidCreate(window)
        return (host, window)
    }

    private func pathCommandCount(in frame: RenderFrame) -> Int {
        frame.commands.reduce(0) { count, command in
            switch command {
            case .fillPath, .strokePath:
                return count + 1
            default:
                return count
            }
        }
    }

    private func drawBitmapCount(in frame: RenderFrame) -> Int {
        frame.commands.reduce(0) { count, command in
            guard case .drawBitmap = command else { return count }
            return count + 1
        }
    }

    private func fillRectCount(in frame: RenderFrame) -> Int {
        frame.commands.reduce(0) { count, command in
            guard case .fillRect = command else { return count }
            return count + 1
        }
    }

    /// Mid-session batch render failure: the host must downgrade and keep
    /// painting real content on the frame backend — text as bitmaps, chrome
    /// as fills, and vector canvas strokes degradable to bitmaps. This is the
    /// "readable degradation" policy lock for Supported content.
    func testMidSessionBatchFailureDowngradeDeliversReadableFrameContent() async {
        let frameRenderer = FakeRenderBackend()
        let batchRenderer = FakeBatchRenderBackend()
        let (host, window) = makeHost(
            content: [AnyView(FallbackProbeView())],
            frameRenderer: frameRenderer,
            batchRenderer: batchRenderer
        )
        XCTAssertEqual(batchRenderer.renderedScenes.count, 1, "Startup should render via the scene backend")

        batchRenderer.setRenderShouldFail(true)
        host.window(window, didResizeTo: IntSize(width: 640, height: 480))
        host.windowNeedsDisplay(window)

        XCTAssertFalse(host.isUsingBatchPresentationBackend, "Batch render failure must downgrade to frame")
        guard let downgradedFrame = frameRenderer.renderedFrames.last else {
            XCTFail("The downgrade-triggering frame must render through the frame backend")
            return
        }

        XCTAssertGreaterThan(
            fillRectCount(in: downgradedFrame), 0,
            "Frame content should include chrome/background fills")
        XCTAssertGreaterThan(
            drawBitmapCount(in: downgradedFrame), 0,
            "Frame content should include text bitmaps — text must stay readable after downgrade")
        XCTAssertGreaterThan(
            pathCommandCount(in: downgradedFrame), 0,
            "Probe view's canvas stroke should arrive as a vector path command")

        let degraded = FramePathDegradation.degradingPathsToBitmaps(in: downgradedFrame)
        XCTAssertEqual(
            pathCommandCount(in: degraded), 0,
            "D3D11Renderer degrades path commands to bitmaps before painting")
        XCTAssertEqual(
            drawBitmapCount(in: degraded),
            drawBitmapCount(in: downgradedFrame) + pathCommandCount(in: downgradedFrame),
            "Every delivered path command becomes a paintable bitmap")
        XCTAssertTrue(
            FramePathDegradation.unpaintableCommandsAfterDegradation(in: downgradedFrame).isEmpty,
            "Everything the host delivers to the frame backend must be paintable")
    }

    /// Recovery success: once the batch backend heals and the retry interval
    /// elapses, the host re-attaches it, scene rendering resumes, frame
    /// rendering stops, and the health snapshot reports the recovery.
    func testRecoverySuccessRestoresSceneRenderingAndStopsFrameRendering() async {
        let frameRenderer = FakeRenderBackend()
        let batchRenderer = FakeBatchRenderBackend()
        let (host, window) = makeHost(
            content: [AnyView(FallbackProbeView())],
            recoveryPolicy: BatchBackendRecoveryPolicy(
                isEnabled: true, initialRetryInterval: 5, maxRetryInterval: 60, backoffMultiplier: 2),
            frameRenderer: frameRenderer,
            batchRenderer: batchRenderer
        )
        let clock = FakeRecoveryClock(1_000.0)
        host.recoveryClock = { clock.now }

        batchRenderer.setRenderShouldFail(true)
        host.window(window, didResizeTo: IntSize(width: 640, height: 480))
        host.windowNeedsDisplay(window)
        XCTAssertEqual(host.rendererHealthSnapshot.activeBackend, .frame)
        let framesAtDowngrade = frameRenderer.renderedFrames.count
        let scenesAtDowngrade = batchRenderer.renderedScenes.count

        batchRenderer.setRenderShouldFail(false)
        clock.now += 6  // past the initial retry interval
        host.window(window, didResizeTo: IntSize(width: 320, height: 200))
        host.windowNeedsDisplay(window)

        XCTAssertTrue(host.isUsingBatchPresentationBackend, "Healed batch backend should be re-attached")
        XCTAssertGreaterThan(
            batchRenderer.renderedScenes.count, scenesAtDowngrade,
            "Scene rendering must resume after recovery")
        XCTAssertEqual(
            frameRenderer.renderedFrames.count, framesAtDowngrade,
            "Frame rendering must stop once the scene backend is restored")

        let snapshot = host.rendererHealthSnapshot
        XCTAssertEqual(snapshot.activeBackend, .scene)
        XCTAssertEqual(snapshot.lastBackendSelectionReason, .batchBackendRecovered)
        XCTAssertNil(snapshot.nextBatchRecoveryInSeconds)
        XCTAssertEqual(snapshot.activeBackendDisplayName, batchRenderer.backendDisplayName)
    }

    /// Health snapshot through the full policy cycle: default scene →
    /// downgrade with scheduled retry → failed attempt with doubled backoff →
    /// recovery with the countdown cleared.
    func testRendererHealthSnapshotTracksDowngradeBackoffAndRecoveryCycle() async {
        let frameRenderer = FakeRenderBackend()
        let batchRenderer = FakeBatchRenderBackend()
        let (host, window) = makeHost(
            recoveryPolicy: BatchBackendRecoveryPolicy(
                isEnabled: true, initialRetryInterval: 5, maxRetryInterval: 60, backoffMultiplier: 2),
            frameRenderer: frameRenderer,
            batchRenderer: batchRenderer
        )
        let clock = FakeRecoveryClock(500.0)
        host.recoveryClock = { clock.now }

        let startup = host.rendererHealthSnapshot
        XCTAssertEqual(startup.activeBackend, .scene)
        XCTAssertEqual(startup.lastBackendSelectionReason, .defaultScene)
        XCTAssertNil(startup.nextBatchRecoveryInSeconds)
        XCTAssertTrue(startup.recoveryPolicyEnabled)

        batchRenderer.setRenderShouldFail(true)
        host.window(window, didResizeTo: IntSize(width: 640, height: 480))
        host.windowNeedsDisplay(window)

        let downgraded = host.rendererHealthSnapshot
        XCTAssertEqual(downgraded.activeBackend, .frame)
        guard case .batchRenderFailure = downgraded.lastBackendSelectionReason else {
            XCTFail(
                "Downgrade reason should be batchRenderFailure, "
                    + "got \(String(describing: downgraded.lastBackendSelectionReason))")
            return
        }
        XCTAssertEqual(
            downgraded.nextBatchRecoveryInSeconds ?? -1, 5.0, accuracy: 0.001,
            "First recovery attempt is scheduled after the initial retry interval")
        XCTAssertEqual(downgraded.activeBackendDisplayName, frameRenderer.backendDisplayName)

        // Batch attach now fails too: the recovery attempt fires and the
        // backoff doubles (5s → 10s), staying on the frame backend.
        batchRenderer.setAttachShouldFail(true)
        clock.now += 6
        host.windowNeedsDisplay(window)

        let afterFailedAttempt = host.rendererHealthSnapshot
        XCTAssertEqual(afterFailedAttempt.activeBackend, .frame)
        XCTAssertEqual(
            afterFailedAttempt.nextBatchRecoveryInSeconds ?? -1, 10.0, accuracy: 0.001,
            "Failed recovery attempt must double the backoff")

        // Heal everything; the next attempt promotes back to scene.
        batchRenderer.setAttachShouldFail(false)
        batchRenderer.setRenderShouldFail(false)
        clock.now += 11
        host.window(window, didResizeTo: IntSize(width: 320, height: 200))
        host.windowNeedsDisplay(window)

        let recovered = host.rendererHealthSnapshot
        XCTAssertEqual(recovered.activeBackend, .scene)
        XCTAssertEqual(recovered.lastBackendSelectionReason, .batchBackendRecovered)
        XCTAssertNil(recovered.nextBatchRecoveryInSeconds)
    }

    /// `.disabled` keeps the one-way pin: no recovery is ever scheduled and a
    /// healed batch backend is never re-attached for the session.
    func testDisabledRecoveryPolicySnapshotShowsNoScheduledRecovery() async {
        let frameRenderer = FakeRenderBackend()
        let batchRenderer = FakeBatchRenderBackend()
        let (host, window) = makeHost(
            recoveryPolicy: .disabled,
            frameRenderer: frameRenderer,
            batchRenderer: batchRenderer
        )
        let clock = FakeRecoveryClock(10_000.0)
        host.recoveryClock = { clock.now }

        batchRenderer.setRenderShouldFail(true)
        host.window(window, didResizeTo: IntSize(width: 640, height: 480))
        host.windowNeedsDisplay(window)

        let downgraded = host.rendererHealthSnapshot
        XCTAssertEqual(downgraded.activeBackend, .frame)
        XCTAssertFalse(downgraded.recoveryPolicyEnabled)
        XCTAssertNil(
            downgraded.nextBatchRecoveryInSeconds,
            "Disabled policy must never schedule a recovery attempt")

        batchRenderer.setRenderShouldFail(false)
        clock.now += 3600
        let batchAttaches = batchRenderer.attachedSurfaces.count
        host.window(window, didResizeTo: IntSize(width: 320, height: 200))
        host.windowNeedsDisplay(window)

        XCTAssertEqual(batchRenderer.attachedSurfaces.count, batchAttaches)
        XCTAssertEqual(host.rendererHealthSnapshot.activeBackend, .frame)
        XCTAssertGreaterThan(
            frameRenderer.renderedFrames.count, 0,
            "Frame backend keeps presenting for the rest of the session")
    }

    /// A *startup* batch attach failure is a downgrade like any other. The
    /// policy table promises recovery after any downgrade, but the startup
    /// path was the one branch that scheduled none — and
    /// `nextBatchRecoveryAttemptAt` is set nowhere else, so a driver that was
    /// mid-upgrade when the window opened pinned the app to the frame backend
    /// for the whole session.
    func testStartupBatchAttachFailureSchedulesRecoveryAndPromotesBackToScene() async {
        let frameRenderer = FakeRenderBackend()
        let batchRenderer = FakeBatchRenderBackend(attachShouldFail: true)
        let surface = makeSurface()
        let host = WinSwiftUIWindowHost(
            configuration: WindowGroupConfiguration(
                title: "Test",
                size: surface.pixelSize,
                clearColor: .black,
                content: []
            ),
            renderer: frameRenderer,
            batchRenderer: batchRenderer,
            surfaceDescriptorProvider: { _ in surface },
            startupProbeConfiguration: nil,
            recoveryPolicy: BatchBackendRecoveryPolicy(
                isEnabled: true, initialRetryInterval: 5, maxRetryInterval: 60, backoffMultiplier: 2)
        )
        let clock = FakeRecoveryClock(2_000.0)
        host.recoveryClock = { clock.now }

        let window = Win32Window(title: "Test", clientSize: surface.pixelSize)
        host.windowDidCreate(window)

        let downgraded = host.rendererHealthSnapshot
        XCTAssertEqual(downgraded.activeBackend, .frame)
        guard case .batchAttachFailure = downgraded.lastBackendSelectionReason else {
            XCTFail(
                "Startup downgrade reason should be batchAttachFailure, "
                    + "got \(String(describing: downgraded.lastBackendSelectionReason))")
            return
        }
        XCTAssertEqual(
            downgraded.nextBatchRecoveryInSeconds ?? -1, 5.0, accuracy: 0.001,
            "The startup downgrade must schedule the same 5s first retry the policy table promises")

        // The driver finishes installing; the next due attempt promotes back.
        batchRenderer.setAttachShouldFail(false)
        clock.now += 6
        host.window(window, didResizeTo: IntSize(width: 640, height: 480))
        host.windowNeedsDisplay(window)

        let recovered = host.rendererHealthSnapshot
        XCTAssertEqual(recovered.activeBackend, .scene)
        XCTAssertEqual(recovered.lastBackendSelectionReason, .batchBackendRecovered)
        XCTAssertNil(recovered.nextBatchRecoveryInSeconds)
        XCTAssertGreaterThan(batchRenderer.renderedScenes.count, 0, "The promoted backend must actually present")
    }

    /// `.disabled` still means a one-way pin, including from startup.
    func testStartupBatchAttachFailureSchedulesNothingUnderTheDisabledPolicy() async {
        let surface = makeSurface()
        let batchRenderer = FakeBatchRenderBackend(attachShouldFail: true)
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
            recoveryPolicy: .disabled
        )
        let clock = FakeRecoveryClock(2_000.0)
        host.recoveryClock = { clock.now }

        host.windowDidCreate(Win32Window(title: "Test", clientSize: surface.pixelSize))

        XCTAssertEqual(host.rendererHealthSnapshot.activeBackend, .frame)
        XCTAssertNil(host.rendererHealthSnapshot.nextBatchRecoveryInSeconds)
    }
}
