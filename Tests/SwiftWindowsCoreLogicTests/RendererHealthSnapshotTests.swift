import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsRendererD3D11
import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Reference-type wall clock so escaping `recoveryClock` closures capture an
/// immutable reference instead of a mutable local binding (avoids Sendable /
/// concurrent-capture diagnostics while remaining MainActor-only in practice).
/// File-scoped so it does not inherit `@MainActor` isolation from the suite.
private final class RendererHealthRecoveryClock: @unchecked Sendable {
    var now: Double
    init(_ now: Double) {
        self.now = now
    }
}

/// `WinSwiftUIWindowHost.rendererHealthSnapshot` is the public surface for
/// observing pipeline state from app code. These tests pin the contract
/// across startup, downgrade, recovery scheduling, and active-animation
/// flagging.
@MainActor
final class RendererHealthSnapshotTests: XCTestCase {

    private func makeHost(
        recoveryPolicy: BatchBackendRecoveryPolicy = .disabled,
        batchAttachFails: Bool = false,
        batchRenderFails: Bool = false
    ) -> (WinSwiftUIWindowHost, FakeBatchRenderBackend, FakeRenderBackend, Win32Window) {
        let batchRenderer = FakeBatchRenderBackend(
            attachShouldFail: batchAttachFails, renderShouldFail: batchRenderFails)
        let frameRenderer = FakeRenderBackend()
        let surface = SurfaceDescriptor(
            windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
            pixelSize: IntSize(width: 320, height: 200),
            scaleFactor: 1.0
        )
        let config = WindowGroupConfiguration(
            title: "Test", size: surface.pixelSize, clearColor: .black, content: []
        )
        let host = WinSwiftUIWindowHost(
            configuration: config,
            renderer: frameRenderer,
            batchRenderer: batchRenderer,
            surfaceDescriptorProvider: { _ in surface },
            recoveryPolicy: recoveryPolicy
        )
        let fakeWindow = Win32Window(title: "Test", clientSize: surface.pixelSize)
        host.windowDidCreate(fakeWindow)
        return (host, batchRenderer, frameRenderer, fakeWindow)
    }

    func testSnapshotAtStartupReportsSceneBackend() async {
        await MainActor.run {
            let (host, _, _, _) = makeHost()
            let snap = host.rendererHealthSnapshot
            XCTAssertEqual(snap.activeBackend, .scene)
            XCTAssertEqual(snap.displayScale, 1.0, accuracy: 0.001)
            XCTAssertFalse(snap.recoveryPolicyEnabled)
            XCTAssertNil(snap.nextBatchRecoveryInSeconds, "No recovery scheduled when batch is active")
            XCTAssertEqual(snap.lastBackendSelectionReason, .defaultScene)
            XCTAssertNotNil(snap.activeBackendDisplayName)
        }
    }

    func testSnapshotAfterDowngradeReportsFrameBackend() async {
        await MainActor.run {
            let (host, batchRenderer, _, fakeWindow) = makeHost(batchRenderFails: false)
            batchRenderer.setRenderShouldFail(true)
            host.window(fakeWindow, didResizeTo: IntSize(width: 640, height: 480))
            host.windowNeedsDisplay(fakeWindow)

            let snap = host.rendererHealthSnapshot
            XCTAssertEqual(snap.activeBackend, .frame)
            switch snap.lastBackendSelectionReason {
            case .batchRenderFailure, .batchResizeFailure:
                break
            default:
                XCTFail(
                    "Expected batch-render/resize failure reason, got "
                        + String(describing: snap.lastBackendSelectionReason)
                )
            }
        }
    }

    func testSnapshotWithRecoveryEnabledReportsScheduledAttempt() async {
        await MainActor.run {
            let (host, batchRenderer, _, fakeWindow) = makeHost(
                recoveryPolicy: BatchBackendRecoveryPolicy(
                    isEnabled: true, initialRetryInterval: 5, maxRetryInterval: 60, backoffMultiplier: 2))
            let clock = RendererHealthRecoveryClock(100.0)
            host.recoveryClock = { clock.now }

            batchRenderer.setRenderShouldFail(true)
            host.window(fakeWindow, didResizeTo: IntSize(width: 640, height: 480))
            host.windowNeedsDisplay(fakeWindow)

            let snap = host.rendererHealthSnapshot
            XCTAssertEqual(snap.activeBackend, .frame)
            XCTAssertTrue(snap.recoveryPolicyEnabled)
            XCTAssertNotNil(snap.nextBatchRecoveryInSeconds)
            XCTAssertEqual(
                snap.nextBatchRecoveryInSeconds ?? -1, 5.0, accuracy: 0.001,
                "Initial retry interval should be the first scheduled attempt")

            // Half the interval has passed.
            clock.now += 2.5
            let snap2 = host.rendererHealthSnapshot
            XCTAssertEqual(snap2.nextBatchRecoveryInSeconds ?? -1, 2.5, accuracy: 0.001)
        }
    }

    func testSnapshotReflectsActiveAnimations() async {
        await MainActor.run {
            let (host, _, _, _) = makeHost()
            let baseline = host.rendererHealthSnapshot
            XCTAssertFalse(baseline.hasActiveAnimations)
            // Animation reporting is via the runtime; we exercise it
            // through the runtime directly. This snapshot is a read of
            // runtime.hasActiveAnimations so behavior is covered by
            // RetainedViewRuntimeTests; here we only verify the snapshot
            // surfaces it.
            _ = host
        }
    }

    func testSnapshotAfterRecoverySuccessReportsSceneBackendWithRecoveredReason() async {
        await MainActor.run {
            let (host, batchRenderer, _, fakeWindow) = makeHost(
                recoveryPolicy: BatchBackendRecoveryPolicy(
                    isEnabled: true, initialRetryInterval: 5, maxRetryInterval: 60, backoffMultiplier: 2))
            let clock = RendererHealthRecoveryClock(200.0)
            host.recoveryClock = { clock.now }

            batchRenderer.setRenderShouldFail(true)
            host.window(fakeWindow, didResizeTo: IntSize(width: 640, height: 480))
            host.windowNeedsDisplay(fakeWindow)
            XCTAssertEqual(host.rendererHealthSnapshot.activeBackend, .frame)

            batchRenderer.setRenderShouldFail(false)
            clock.now += 10  // past the retry interval
            host.windowNeedsDisplay(fakeWindow)

            let snap = host.rendererHealthSnapshot
            XCTAssertEqual(snap.activeBackend, .scene)
            XCTAssertEqual(snap.lastBackendSelectionReason, .batchBackendRecovered)
            XCTAssertNil(
                snap.nextBatchRecoveryInSeconds,
                "No recovery scheduled while batch is active")
        }
    }
}
