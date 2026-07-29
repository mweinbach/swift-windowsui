import SwiftWindowsCore
import SwiftWindowsGraphics
import WinSDK

@preconcurrency import XCTest

@testable import SwiftWindowsPlatform

@testable import SwiftWindowsUI

@testable import WinSwiftUI

// The GPU-less startup path, end to end through the host seams.
//
// The availability probe used to substitute `CPURenderBackendFactory` when
// D3D11 reported it could not present. Its backends rasterize into
// `lastRenderedBitmap` and stop, so `attach` succeeded, `isRendererReady`
// stayed true, `isPresenterUnavailable` stayed false — and the window showed
// nothing. A blank window that reports healthy is the one outcome the
// presentation policy must make impossible, because it is indistinguishable
// from a hang.
//
// Two facts close it, and these tests pin both:
//
// 1. The substitute presents. `SoftwareWindowRenderBackend` blits every frame
//    it rasterizes into the window's client area, so a GPU-less machine gets a
//    real software-rendered window.
// 2. The substitute never silently succeeds. `render` either presents or
//    throws, and a fallback that reports it cannot present here is not
//    substituted at all — the bounded attach retry then reaches the observable
//    `.presenterUnavailable` terminal state instead.

@MainActor
private final class RecordingWindowBitmapPresenter: WindowBitmapPresenter {
    private(set) var presentedBitmaps: [BitmapSurface] = []
    private(set) var presentedClientSizes: [IntSize] = []
    var failure: Error?

    func present(_ bitmap: BitmapSurface, to windowHandle: NativeWindowHandle, clientSize: IntSize) throws {
        if let failure {
            throw failure
        }
        presentedBitmaps.append(bitmap)
        presentedClientSizes.append(clientSize)
    }
}

@MainActor
final class SoftwarePresentationTests: XCTestCase {
    private static let clearColor = Color(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0)

    private func makeConfiguration(
        size: IntSize = IntSize(width: 64, height: 48)
    ) -> WindowGroupConfiguration {
        WindowGroupConfiguration(
            title: "Software Presentation",
            size: size,
            clearColor: Self.clearColor,
            content: []
        )
    }

    private func makeSurface(pixelSize: IntSize = IntSize(width: 64, height: 48)) -> SurfaceDescriptor {
        SurfaceDescriptor(
            windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
            pixelSize: pixelSize,
            scaleFactor: 1.0
        )
    }

    private func makeHost(
        presenter: RecordingWindowBitmapPresenter,
        surface: SurfaceDescriptor
    ) -> (host: WinSwiftUIWindowHost, window: Win32Window) {
        let host = WinSwiftUIWindowHost(
            configuration: makeConfiguration(size: surface.pixelSize),
            renderer: SoftwareWindowRenderBackend(presenter: presenter),
            batchRenderer: SoftwareWindowRenderBackend(presenter: presenter),
            surfaceDescriptorProvider: { _ in surface },
            // A known scene keeps the pixel assertion about the presentation
            // path rather than about whatever the empty root paints.
            sceneRenderer: { _, _ in GPUIScene(clearColor: Self.clearColor) },
            startupProbeConfiguration: nil
        )
        let window = Win32Window(title: "Software Presentation", clientSize: surface.pixelSize)
        return (host, window)
    }

    // MARK: - The fallback presents for real

    /// The end-to-end claim: a host built on the fallback backend does not
    /// merely report a ready presenter — a frame reaches the window's
    /// presentation seam, sized to the client rect, carrying the scene's
    /// pixels.
    func testTheSoftwareFallbackActuallyPresentsAFrameThroughTheHost() async throws {
        let presenter = RecordingWindowBitmapPresenter()
        let surface = makeSurface()
        let (host, window) = makeHost(presenter: presenter, surface: surface)

        host.windowDidCreate(window)

        XCTAssertTrue(host.isUsingScenePresentationBackend)
        XCTAssertFalse(host.isPresenterUnavailable)
        XCTAssertGreaterThan(
            presenter.presentedBitmaps.count,
            0,
            "A healthy report from this host must mean a frame reached the window, not memory."
        )

        let presented = try XCTUnwrap(presenter.presentedBitmaps.last)
        XCTAssertEqual(presented.width, surface.pixelSize.width)
        XCTAssertEqual(presented.height, surface.pixelSize.height)
        XCTAssertEqual(presented.bytesPerRow, surface.pixelSize.width * 4)
        XCTAssertEqual(presenter.presentedClientSizes.last, surface.pixelSize)

        // The blitted buffer carries the scene's opaque clear colour in the
        // BGRA byte order GDI reads a 32-bit BI_RGB DIB in — not an empty
        // allocation.
        let bytes = [UInt8](presented.pixels)
        XCTAssertGreaterThanOrEqual(bytes.count, presented.describedByteCount)
        XCTAssertEqual(bytes[0], 204, "Blue channel of the 0.2/0.4/0.8 clear colour.")
        XCTAssertEqual(bytes[1], 102, "Green channel.")
        XCTAssertEqual(bytes[2], 51, "Red channel.")
    }

    /// Resizes keep reaching the window, at the new client size rather than
    /// the one the backend attached with.
    func testResizedFramesPresentAtTheNewClientSize() async throws {
        let presenter = RecordingWindowBitmapPresenter()
        let surface = makeSurface()
        let (host, window) = makeHost(presenter: presenter, surface: surface)
        host.windowDidCreate(window)

        let resized = IntSize(width: 96, height: 32)
        host.window(window, didResizeTo: resized)
        host.windowNeedsDisplay(window)

        let presented = try XCTUnwrap(presenter.presentedBitmaps.last)
        XCTAssertEqual(presented.width, resized.width)
        XCTAssertEqual(presented.height, resized.height)
        XCTAssertEqual(presenter.presentedClientSizes.last, resized)
    }

    // MARK: - Never a silent success

    /// The structural guarantee behind the substitution: there is no outcome
    /// where the software backend returns from `render` having drawn nothing.
    func testTheSoftwareBackendNeverReturnsFromRenderWithoutPresenting() async throws {
        let presenter = RecordingWindowBitmapPresenter()
        let backend = SoftwareWindowRenderBackend(presenter: presenter)
        let scene = GPUIScene(clearColor: Self.clearColor)

        try backend.attach(to: makeSurface(pixelSize: IntSize(width: 8, height: 8)))
        try backend.render(scene: scene)
        XCTAssertEqual(backend.presentedFrameCount, 1)

        presenter.failure = SoftwarePresentationError.blitFailed
        XCTAssertThrowsError(try backend.render(scene: scene), "A failed blit must not read as a rendered frame.")
        XCTAssertEqual(backend.presentedFrameCount, 1)

        presenter.failure = nil
        backend.detach()
        XCTAssertThrowsError(
            try backend.render(scene: scene),
            "A detached software backend has no window to blit into and must say so."
        )
        XCTAssertEqual(backend.presentedFrameCount, 1)
    }

    /// A blit that fails mid-session is a presentation failure like any other:
    /// it reaches the host's fallback policy and its health snapshot, instead
    /// of leaving a healthy-looking scene session in front of a blank window.
    func testABlitFailureIsSurfacedThroughHostHealthRatherThanReportedHealthy() async {
        let presenter = RecordingWindowBitmapPresenter()
        presenter.failure = SoftwarePresentationError.blitFailed
        let surface = makeSurface()
        let (host, window) = makeHost(presenter: presenter, surface: surface)
        let clock = FakeRecoveryClock(1000)
        host.recoveryClock = { clock.now }

        host.windowDidCreate(window)

        XCTAssertEqual(presenter.presentedBitmaps.count, 0)

        let snapshot = host.rendererHealthSnapshot
        XCTAssertEqual(
            snapshot.activeBackend,
            .frame,
            "A scene backend that cannot put pixels on screen must not stay selected and reported as working."
        )
        XCTAssertEqual(snapshot.lastBackendSelectionReason?.probeCode, "batch-render-failure")
        XCTAssertNotNil(snapshot.lastPresentationFailureKind)
        XCTAssertGreaterThan(host.emittedReportCount, 0, "The failure must be reported, not swallowed.")
    }

    func testSoftwareFactoryReportsItselfPresentableAndDistinctFromTheCPUReference() async {
        let factory = SoftwareWindowRenderBackendFactory()
        XCTAssertTrue(factory.probeAvailability().canPresent)
        XCTAssertNotNil(
            factory.probeAvailability().reason,
            "The software path is a reduced capability and says so, so health can surface it."
        )
        XCTAssertNotEqual(factory.factoryName, CPURenderBackendFactory().factoryName)
    }

    // MARK: - Health surfaces the resolution

    func testHealthSnapshotDistinguishesASubstitutedBackendFromAHealthyOne() async {
        let healthy = WinSwiftUIWindowHost(
            configuration: makeConfiguration(),
            renderer: FakeRenderBackend(),
            batchRenderer: FakeBatchRenderBackend(),
            surfaceDescriptorProvider: { [surface = makeSurface()] _ in surface },
            startupProbeConfiguration: nil,
            backendResolution: RenderBackendResolution(
                requestedFactoryName: "D3D11 GPU",
                resolvedFactoryName: "D3D11 GPU",
                availability: .available
            )
        )
        let substituted = WinSwiftUIWindowHost(
            configuration: makeConfiguration(),
            renderer: FakeRenderBackend(),
            batchRenderer: FakeBatchRenderBackend(),
            surfaceDescriptorProvider: { [surface = makeSurface()] _ in surface },
            startupProbeConfiguration: nil,
            backendResolution: RenderBackendResolution(
                requestedFactoryName: "D3D11 GPU",
                resolvedFactoryName: "CPU Software",
                availability: .unavailable(reason: "D3D11CreateDevice failed for both the hardware adapter and WARP.")
            )
        )

        XCTAssertEqual(healthy.rendererHealthSnapshot.backendResolution?.isDegradedPresentation, false)
        XCTAssertEqual(substituted.rendererHealthSnapshot.backendResolution?.isSubstituted, true)
        XCTAssertEqual(
            substituted.rendererHealthSnapshot.backendResolution?.availability.reason?.isEmpty,
            false,
            "The reason the machine could not present belongs in health, not only in a startup log line."
        )
        XCTAssertNotEqual(
            healthy.rendererHealthSnapshot.backendResolution,
            substituted.rendererHealthSnapshot.backendResolution
        )
    }

    /// The windowed-WARP case: D3D11 attaches on the software rasterizer and
    /// presents, so the session looks healthy in every other field. Only the
    /// resolution says the GPU is not doing the work.
    func testHealthSnapshotSurfacesTheWindowedWARPCase() async {
        let host = WinSwiftUIWindowHost(
            configuration: makeConfiguration(),
            renderer: FakeRenderBackend(),
            batchRenderer: FakeBatchRenderBackend(),
            surfaceDescriptorProvider: { [surface = makeSurface()] _ in surface },
            startupProbeConfiguration: nil,
            backendResolution: RenderBackendResolution(
                requestedFactoryName: "D3D11 GPU",
                resolvedFactoryName: "D3D11 GPU",
                availability: .degraded(
                    reason: "No D3D11 hardware adapter is usable; presentation would run on the WARP "
                        + "software rasterizer."
                )
            )
        )
        let window = Win32Window(title: "Software Presentation", clientSize: IntSize(width: 64, height: 48))
        host.windowDidCreate(window)

        let snapshot = host.rendererHealthSnapshot
        XCTAssertEqual(snapshot.activeBackend, .scene)
        XCTAssertFalse(snapshot.isPresenterUnavailable)
        XCTAssertEqual(snapshot.backendResolution?.isSubstituted, false)
        XCTAssertEqual(snapshot.backendResolution?.isDegradedPresentation, true)
        XCTAssertEqual(snapshot.backendResolution?.availability.reason?.contains("WARP"), true)
    }

    // MARK: - Real window

    /// The production blit against a real HWND. Skips where this environment
    /// cannot create a top-level window, matching the other real-window tests
    /// in the suite.
    func testGDIPresenterBlitsIntoARealWindow() async throws {
        let window = Win32Window(title: "GDI Blit", clientSize: IntSize(width: 64, height: 48))
        window.postsQuitMessageOnDestroy = false
        do {
            try window.create()
        } catch {
            throw XCTSkip("This environment cannot create a top-level window: \(error)")
        }
        defer {
            if let handle = window.nativeHandle?.rawPointer {
                DestroyWindow(unsafeBitCast(handle, to: HWND?.self))
            }
        }

        let handle = try XCTUnwrap(window.nativeHandle)
        let clientSize = window.currentClientSize()
        let backend = SoftwareWindowRenderBackend()
        try backend.attach(
            to: SurfaceDescriptor(windowHandle: handle, pixelSize: clientSize, scaleFactor: window.scaleFactor)
        )
        try backend.render(scene: GPUIScene(clearColor: Self.clearColor))

        XCTAssertEqual(
            backend.presentedFrameCount,
            1,
            "The production presenter must reach the window; anything else is the blank-window state again."
        )
    }
}
