import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// WS-02, host half: the recovery policy reads a *type*, not a string.
///
/// `PresentationSelectionReason.batchRenderFailure(String)` carried
/// `String(describing: error)` and nothing else, so the host applied one
/// permanent-downgrade-plus-retry rule to device loss, to a per-scene resource
/// failure and to a capability this machine will never have. These tests pin
/// the distinction now that backends classify themselves.
@MainActor
final class PresentationFailurePolicyTests: XCTestCase {

    /// A backend failure that classifies itself, standing in for the typed
    /// errors the D3D11 backends produce (WinSwiftUI is renderer-neutral and
    /// must not import the D3D11 module to test its own policy).
    private struct ClassifiedTestFailure: ClassifiedPresentationFailure {
        let presentationFailureKind: PresentationFailureKind
    }

    private func makeSurface(pixelSize: IntSize = IntSize(width: 320, height: 200)) -> SurfaceDescriptor {
        SurfaceDescriptor(
            windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
            pixelSize: pixelSize,
            scaleFactor: 1.0
        )
    }

    private func makeHost(
        recoveryPolicy: BatchBackendRecoveryPolicy = .standard,
        frameRenderer: FakeRenderBackend = FakeRenderBackend(),
        batchRenderer: FakeBatchRenderBackend = FakeBatchRenderBackend(),
        clock: @escaping @MainActor () -> Double = { 0 }
    ) -> (host: WinSwiftUIWindowHost, window: Win32Window) {
        let surface = makeSurface()
        let config = WindowGroupConfiguration(
            title: "Test",
            size: surface.pixelSize,
            clearColor: .black,
            content: [AnyView(Text("Presentation failure policy"))]
        )
        let host = WinSwiftUIWindowHost(
            configuration: config,
            renderer: frameRenderer,
            batchRenderer: batchRenderer,
            surfaceDescriptorProvider: { _ in surface },
            recoveryPolicy: recoveryPolicy
        )
        host.recoveryClock = clock
        let window = Win32Window(title: "Test", clientSize: surface.pixelSize)
        host.windowDidCreate(window)
        return (host, window)
    }

    /// A static tree stops asking for frames, so a test that wants the next
    /// `WM_PAINT` to actually render has to dirty something first.
    private func primeFrame(in host: WinSwiftUIWindowHost, window: Win32Window, width: Int32) {
        host.window(window, didResizeTo: IntSize(width: width, height: 200))
    }

    // MARK: - The failure kind reaches the host

    func testSceneContentFailureIsRecordedAndStillSchedulesRecovery() async {
        let batchRenderer = FakeBatchRenderBackend()
        batchRenderer.failureError = ClassifiedTestFailure(presentationFailureKind: .sceneContent)
        let (host, window) = makeHost(batchRenderer: batchRenderer)

        batchRenderer.setRenderShouldFail(true)
        primeFrame(in: host, window: window, width: 321)
        host.windowNeedsDisplay(window)

        let snapshot = host.rendererHealthSnapshot
        XCTAssertEqual(snapshot.activeBackend, .frame, "A failing scene render still downgrades")
        XCTAssertEqual(
            snapshot.lastPresentationFailureKind, .sceneContent,
            "The host must be able to tell what kind of failure it just handled")
        XCTAssertEqual(
            snapshot.nextBatchRecoveryInSeconds, 5.0,
            "A scene-content failure is not permanent, so recovery stays scheduled")
    }

    func testPermanentFailureSchedulesNoRecoveryAtAll() async {
        let batchRenderer = FakeBatchRenderBackend()
        batchRenderer.failureError = ClassifiedTestFailure(presentationFailureKind: .permanent)
        let (host, window) = makeHost(batchRenderer: batchRenderer)

        batchRenderer.setRenderShouldFail(true)
        primeFrame(in: host, window: window, width: 321)
        host.windowNeedsDisplay(window)

        let snapshot = host.rendererHealthSnapshot
        XCTAssertEqual(snapshot.activeBackend, .frame)
        XCTAssertEqual(snapshot.lastPresentationFailureKind, .permanent)
        XCTAssertNil(
            snapshot.nextBatchRecoveryInSeconds,
            "Retrying a capability this machine does not have costs a scene build and a visible "
                + "backend switch per attempt and can never succeed")
    }

    func testUnclassifiedFailureKeepsTheHistoricalTransientBehaviour() async {
        let batchRenderer = FakeBatchRenderBackend()
        let (host, window) = makeHost(batchRenderer: batchRenderer)

        batchRenderer.setRenderShouldFail(true)
        primeFrame(in: host, window: window, width: 321)
        host.windowNeedsDisplay(window)

        let snapshot = host.rendererHealthSnapshot
        XCTAssertEqual(snapshot.lastPresentationFailureKind, .transient)
        XCTAssertEqual(snapshot.nextBatchRecoveryInSeconds, 5.0)
    }

    func testRecoverySuccessClearsTheRecordedFailure() async {
        var now = 0.0
        let batchRenderer = FakeBatchRenderBackend()
        batchRenderer.failureError = ClassifiedTestFailure(presentationFailureKind: .transient)
        let (host, window) = makeHost(batchRenderer: batchRenderer, clock: { now })

        batchRenderer.setRenderShouldFail(true)
        primeFrame(in: host, window: window, width: 321)
        host.windowNeedsDisplay(window)
        XCTAssertEqual(host.rendererHealthSnapshot.lastPresentationFailureKind, .transient)

        batchRenderer.setRenderShouldFail(false)
        now = 10.0
        host.windowNeedsDisplay(window)

        let snapshot = host.rendererHealthSnapshot
        XCTAssertEqual(snapshot.activeBackend, .scene, "Recovery must restore the scene backend")
        XCTAssertNil(
            snapshot.lastPresentationFailureKind,
            "A healed pipeline has no outstanding failure to report")
    }

    // MARK: - Repaint debt after a device rebuild

    func testBackendThatRebuiltItsDeviceKeepsTheFrameLoopAlive() async {
        let batchRenderer = FakeBatchRenderBackend()
        let (host, window) = makeHost(batchRenderer: batchRenderer)

        // Control: a static tree stops asking for frames.
        for _ in 0..<6 {
            host.windowNeedsDisplay(window)
        }
        let quiescent = batchRenderer.renderedScenes.count
        for _ in 0..<4 {
            host.windowNeedsDisplay(window)
        }
        XCTAssertEqual(
            batchRenderer.renderedScenes.count, quiescent,
            "Nothing dirty, nothing animating: the host must stop rendering")

        // Treatment: the backend reports it rebuilt its device and skipped a
        // frame, so the pixels on screen are stale even though the tree is
        // clean. Every WM_PAINT from here on must keep producing frames
        // rather than settling back into quiescence after the first one.
        batchRenderer.presentationState = PresentationState(needsImmediateRepaint: true)
        primeFrame(in: host, window: window, width: 400)
        for _ in 0..<5 {
            host.windowNeedsDisplay(window)
        }
        XCTAssertEqual(
            batchRenderer.renderedScenes.count, quiescent + 5,
            "A backend owing the screen a repaint must keep the frame loop alive")
    }

    func testOcclusionIsObservableInTheHealthSnapshot() async {
        let batchRenderer = FakeBatchRenderBackend()
        let (host, _) = makeHost(batchRenderer: batchRenderer)

        XCTAssertFalse(host.rendererHealthSnapshot.isPresentationOccluded)
        batchRenderer.presentationState = PresentationState(isOccluded: true)
        XCTAssertTrue(
            host.rendererHealthSnapshot.isPresentationOccluded,
            "DXGI_STATUS_OCCLUDED is a positive HRESULT; without surfacing it the frame loop "
                + "spins on invisible work")
    }
}
