import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import WinSDK
import WinSDK.DirectX
import XCTest

@testable import SwiftWindowsPlatform
@testable import SwiftWindowsRendererD3D11
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Drives `WinSwiftUIWindowHost.recoveryClock` so the recovery backoff can
/// be stepped over without waiting.
private final class LifetimeRecoveryClock: @unchecked Sendable {
    var now: Double

    init(_ now: Double) {
        self.now = now
    }
}

/// Resource lifetime for the render backends: `detach()` releases what
/// `attach()` acquired, and the host calls it at every point where a window
/// or a presenter goes away.
///
/// Neither backend protocol used to have a teardown surface, so a closed
/// window leaked its entire D3D11 stack — device, context, factory, swap
/// chain (which also pins the destroyed HWND), pipeline objects, both glyph
/// atlases, every cached path texture and the blur ping-pong pair. The same
/// omission put two flip-model swap chains on one HWND during a presenter
/// switch, which DXGI treats as exclusive. These tests pin both halves:
/// the renderer really releases, and the host really calls it.
@MainActor
final class RenderBackendLifetimeTests: XCTestCase {

    // MARK: - Scenes

    private func makeQuadScene(size: IntSize) -> GPUIScene {
        var scene = GPUIScene(clearColor: Color(red: 0, green: 0, blue: 0, alpha: 1))
        scene.addQuad(
            QuadPrimitive(
                x: 4, y: 4, width: Float(size.width) - 8, height: Float(size.height) - 8,
                startR: 0.9, startG: 0.3, startB: 0.2, startA: 1,
                endR: 0.9, endG: 0.3, endB: 0.2, endA: 1
            )
        )
        return scene
    }

    /// A scene that reaches the renderer's device-owned caches: an image
    /// binding (the image texture map) and a path (CPU-rasterized, then
    /// cached as a GPU texture). Detach has to empty those too, not just
    /// the pipeline objects the frame path always touches.
    private func makeCacheFillingScene(size: IntSize, textureID: Int32) -> GPUIScene {
        var scene = makeQuadScene(size: size)

        let imageWidth = 4
        let imageHeight = 4
        var pixels = Data(count: imageWidth * imageHeight * 4)
        for index in 0..<(imageWidth * imageHeight) {
            pixels[index * 4 + 0] = 40
            pixels[index * 4 + 1] = 160
            pixels[index * 4 + 2] = 220
            pixels[index * 4 + 3] = 255
        }
        let bitmap = BitmapSurface(
            width: Int32(imageWidth),
            height: Int32(imageHeight),
            bytesPerRow: Int32(imageWidth * 4),
            pixels: pixels
        )
        scene.bindImageResource(bitmap, for: textureID)
        scene.addImage(
            ImagePrimitive(
                screenX: 2, screenY: 2, screenW: 12, screenH: 12,
                uvX: 0, uvY: 0, uvW: 1, uvH: 1,
                opacity: 1,
                textureID: textureID
            )
        )

        scene.addPath(
            PathPrimitive(
                elements: [
                    .moveTo(Point(x: 6, y: 6)),
                    .lineTo(Point(x: 30, y: 6)),
                    .lineTo(Point(x: 30, y: 30)),
                    .close,
                ],
                bounds: Rect(x: 6, y: 6, width: 24, height: 24),
                fillColor: Color(red: 0.1, green: 0.8, blue: 0.4, alpha: 1)
            ),
            toLayer: 0
        )

        return scene
    }

    // MARK: - D3D11 batch renderer teardown

    /// Every stored COM pointer, the image map, the path cache and the blur
    /// engine are gone after `detach()`, and the renderer reports itself
    /// unattached. `liveCOMObjectCountForTesting` counts the stored
    /// properties one by one, so a field added later that forgets to
    /// release itself fails here.
    func testDetachReleasesEveryCOMObjectTheRendererOwns() async throws {
        let size = IntSize(width: 64, height: 48)
        let renderer = try makeDetachableRenderer(size: size)
        defer { renderer.detach() }

        let scene = makeCacheFillingScene(size: size, textureID: 4001)
        renderer.bindResources(for: scene)
        try renderer.render(scene: scene)

        XCTAssertGreaterThan(
            renderer.liveCOMObjectCountForTesting, 0,
            "An attached, rendered frame must own COM objects, otherwise this test proves nothing")
        XCTAssertGreaterThan(renderer.pathCacheEntryCountForTesting, 0, "The path should have been cached")
        XCTAssertFalse(renderer.cachedResourcesForTesting.boundImageTextureIDs.isEmpty)

        renderer.detach()

        XCTAssertFalse(renderer.isAttached)
        XCTAssertEqual(
            renderer.liveCOMObjectCountForTesting, 0,
            "detach() must release every stored COM pointer, including the swap chain that pins the HWND")
        XCTAssertEqual(renderer.pathCacheEntryCountForTesting, 0, "Cached path textures belong to the released device")
        XCTAssertEqual(
            renderer.cachedResourcesForTesting, D3D11BatchRenderer.CachedResources(),
            "Atlas uploads and image bindings belong to the released device")
        XCTAssertFalse(renderer.blurEngineOwnsResourcesForTesting)
        XCTAssertEqual(renderer.deviceAddressForTesting, 0)
    }

    /// Detaching twice, and detaching something that was never attached,
    /// must be no-ops rather than double releases.
    func testDetachIsIdempotent() async throws {
        let fresh = D3D11BatchRenderer()
        fresh.detach()
        fresh.detach()
        XCTAssertFalse(fresh.isAttached)
        XCTAssertEqual(fresh.liveCOMObjectCountForTesting, 0)

        let size = IntSize(width: 32, height: 32)
        let renderer = try makeDetachableRenderer(size: size)
        defer { renderer.detach() }
        renderer.detach()
        renderer.detach()
        XCTAssertEqual(renderer.liveCOMObjectCountForTesting, 0)
    }

    /// The round trip the host performs on every backend recovery: attach,
    /// tear down, attach again. The second attach must produce a working
    /// renderer — a *new* device, not the released one — and the same
    /// pixels as the first.
    func testAttachDetachAttachRoundTripProducesTheSamePixels() async throws {
        let size = IntSize(width: 64, height: 48)
        let renderer = try makeDetachableRenderer(size: size)
        defer { renderer.detach() }

        let scene = makeQuadScene(size: size)
        try renderer.render(scene: scene)
        let first = try renderer.readOffscreenPixels()
        let firstDeviceAddress = renderer.deviceAddressForTesting
        XCTAssertNotEqual(firstDeviceAddress, 0)

        renderer.detach()
        XCTAssertEqual(renderer.deviceAddressForTesting, 0, "A detached renderer holds no device")

        try renderer.attachOffscreen(size: size, driver: .warpFirst)
        XCTAssertTrue(renderer.isAttached)
        XCTAssertNotEqual(renderer.deviceAddressForTesting, 0, "Re-attach must create a device rather than reuse one")

        try renderer.render(scene: scene)
        let second = try renderer.readOffscreenPixels()

        XCTAssertEqual(first.width, second.width)
        XCTAssertEqual(first.height, second.height)
        let report = comparePixels(second, first, tolerance: 0)
        XCTAssertEqual(
            report.matchRatio, 1.0,
            "A re-attached renderer must draw the same frame; max channel delta \(report.maxChannelDelta)")
    }

    /// Repeated open/close of a window is the case that used to exhaust
    /// video memory. Each cycle must end holding nothing, so the count is
    /// the same after the third cycle as after the first.
    func testRepeatedAttachDetachCyclesReturnToZeroLiveObjects() async throws {
        let size = IntSize(width: 48, height: 32)
        let renderer = try makeDetachableRenderer(size: size)
        defer { renderer.detach() }

        var attachedCounts: [Int] = []
        for cycle in 0..<3 {
            if cycle > 0 {
                try renderer.attachOffscreen(size: size, driver: .warpFirst)
            }
            let scene = makeCacheFillingScene(size: size, textureID: Int32(4100 + cycle))
            renderer.bindResources(for: scene)
            try renderer.render(scene: scene)
            attachedCounts.append(renderer.liveCOMObjectCountForTesting)

            renderer.detach()
            XCTAssertEqual(
                renderer.liveCOMObjectCountForTesting, 0,
                "Cycle \(cycle) left COM objects alive; a window-open/close loop would exhaust video memory")
        }

        XCTAssertEqual(
            Set(attachedCounts).count, 1,
            "Each cycle must rebuild the same set of resources, not accumulate: \(attachedCounts)")
    }

    // MARK: - Debug-layer live objects

    /// `liveCOMObjectCountForTesting` can only see pointers this renderer
    /// stored, so it cannot see an unbalanced `AddRef`, a `QueryInterface`
    /// or `GetBuffer` result released nowhere, or a device kept alive by
    /// something the renderer never knew about — precisely the class of leak
    /// this workstream exists for. The D3D11 debug layer can see all of it:
    /// every device child holds a reference on its device, so a device whose
    /// only surviving reference is the `ID3D11Debug` this test holds is a
    /// device with nothing left alive on it.
    ///
    /// Skips rather than fails when the debug layer is unavailable — it
    /// ships with the optional "Graphics Tools" Windows feature, which a
    /// developer machine need not have installed.
    func testDebugLayerReportsNoLiveObjectGrowthAcrossAttachDetachCycles() async throws {
        let size = IntSize(width: 48, height: 32)
        let renderer = D3D11BatchRenderer()
        renderer.createsDebugDeviceForTesting = true
        defer { renderer.detach() }

        var residuals: [ULONG] = []
        for cycle in 0..<3 {
            do {
                try renderer.attachOffscreen(size: size, driver: .warpFirst)
            } catch {
                throw XCTSkip(
                    "No D3D11 debug device on this machine (install the Graphics Tools feature to run "
                        + "this check): \(error)")
            }

            let device = try XCTUnwrap(renderer.deviceForTesting)
            guard let debug = queryDebugInterface(device) else {
                renderer.detach()
                throw XCTSkip("ID3D11Debug is not available on this device; the debug layer did not load")
            }

            let scene = makeCacheFillingScene(size: size, textureID: Int32(4200 + cycle))
            renderer.bindResources(for: scene)
            try renderer.render(scene: scene)

            renderer.detach()

            // Writes the surviving objects to the debug output. Nothing
            // reads it programmatically — it is what a developer looks at
            // once the reference count below says something leaked.
            _ = debug.pointee.lpVtbl.pointee.ReportLiveDeviceObjects(debug, D3D11_RLDO_DETAIL)
            residuals.append(referenceCount(of: debug))
            releaseUnknown(debug)
        }

        XCTAssertEqual(
            Set(residuals).count, 1,
            "Live device references must not grow across attach/detach cycles: \(residuals)")
        XCTAssertEqual(
            residuals.first, 1,
            "After detach the only reference left on the device should be this test's ID3D11Debug; "
                + "anything more is a child object the renderer never released (counts: \(residuals))")

        // The check has teeth only if an actual leak moves it, so leak one
        // on purpose and confirm the number rises.
        try renderer.attachOffscreen(size: size, driver: .warpFirst)
        let device = try XCTUnwrap(renderer.deviceForTesting)
        let debug = try XCTUnwrap(queryDebugInterface(device))
        var leakedTexture: UnsafeMutablePointer<ID3D11Texture2D>?
        var descriptor = D3D11_TEXTURE2D_DESC()
        descriptor.Width = 8
        descriptor.Height = 8
        descriptor.MipLevels = 1
        descriptor.ArraySize = 1
        descriptor.Format = DXGI_FORMAT_B8G8R8A8_UNORM
        descriptor.SampleDesc = DXGI_SAMPLE_DESC(Count: 1, Quality: 0)
        descriptor.Usage = D3D11_USAGE_DEFAULT
        descriptor.BindFlags = UINT(D3D11_BIND_SHADER_RESOURCE.rawValue)
        let textureHR = device.pointee.lpVtbl.pointee.CreateTexture2D(device, &descriptor, nil, &leakedTexture)
        XCTAssertGreaterThanOrEqual(textureHR, 0)
        let texture = try XCTUnwrap(leakedTexture)

        renderer.detach()
        XCTAssertGreaterThan(
            referenceCount(of: debug), residuals[0],
            "A surviving device child must show up as an extra device reference, otherwise the assertions "
                + "above cannot detect a leak either")

        releaseUnknown(texture)
        XCTAssertEqual(
            referenceCount(of: debug), residuals[0],
            "Releasing the leaked child must return the device to its clean count")
        releaseUnknown(debug)
    }

    /// `QueryInterface` for `ID3D11Debug`. The returned interface is the
    /// device object itself, so its reference count *is* the device's — the
    /// property the assertions above rely on.
    private func queryDebugInterface(
        _ device: UnsafeMutablePointer<ID3D11Device>
    ) -> UnsafeMutablePointer<ID3D11Debug>? {
        let unknown = UnsafeMutableRawPointer(device).assumingMemoryBound(to: IUnknown.self)
        var iid = IID_ID3D11Debug
        var raw: UnsafeMutableRawPointer?
        let hr = unknown.pointee.lpVtbl.pointee.QueryInterface(unknown, &iid, &raw)
        guard hr >= 0, let raw else { return nil }
        return raw.assumingMemoryBound(to: ID3D11Debug.self)
    }

    /// References currently held on `pointer`'s COM object, read without
    /// changing it: `Release` returns the count that survives it, so an
    /// `AddRef`/`Release` pair reports the count and leaves it alone.
    private func referenceCount<T>(of pointer: UnsafeMutablePointer<T>) -> ULONG {
        let unknown = UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: IUnknown.self)
        _ = unknown.pointee.lpVtbl.pointee.AddRef(unknown)
        return unknown.pointee.lpVtbl.pointee.Release(unknown)
    }

    private func releaseUnknown<T>(_ pointer: UnsafeMutablePointer<T>) {
        let unknown = UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: IUnknown.self)
        _ = unknown.pointee.lpVtbl.pointee.Release(unknown)
    }

    // MARK: - Deinit backstop

    /// A missed `detach()` used to be invisible in release: the deinit
    /// asserted, and `assert` compiles out. The backstop reports in every
    /// configuration now.
    ///
    /// This test deliberately drops an attached renderer, which really does
    /// leak one WARP device, its swap-chain-less offscreen target and the
    /// compiled pipeline — a nonisolated deinit cannot reach the main actor
    /// to release them, which is the whole reason the backstop can only
    /// report. One leaked device for the life of the test process is the
    /// price of proving the report fires.
    func testDeinitReportsAnUndetachedRendererRatherThanLeakingSilently() async throws {
        let before = RendererTeardownBackstop.undetachedTeardownCount
        RendererTeardownBackstop.suppressTrapForTesting = true
        defer { RendererTeardownBackstop.suppressTrapForTesting = false }

        // In a function, so the local is released when it returns rather
        // than at some point ARC chooses inside this one.
        func dropAttachedRenderer() throws {
            let renderer = try makeDetachableRenderer(size: IntSize(width: 16, height: 16))
            XCTAssertTrue(renderer.isAttached)
        }
        try dropAttachedRenderer()

        XCTAssertEqual(
            RendererTeardownBackstop.undetachedTeardownCount, before + 1,
            "Dropping an attached renderer must report the leak, not vanish")
    }

    /// A renderer that was detached first must say nothing — a backstop that
    /// cried wolf on the normal path would be turned off within a week.
    func testDeinitStaysQuietForADetachedRenderer() async throws {
        let before = RendererTeardownBackstop.undetachedTeardownCount

        func dropDetachedRenderer() throws {
            let renderer = try makeDetachableRenderer(size: IntSize(width: 16, height: 16))
            renderer.detach()
        }
        try dropDetachedRenderer()

        XCTAssertEqual(RendererTeardownBackstop.undetachedTeardownCount, before)
    }

    // MARK: - D3D11 frame renderer teardown

    /// The frame renderer needs a real HWND to attach, so only the
    /// unattached edge is reachable headlessly: `detach()` on a renderer
    /// that never attached must be a safe no-op.
    func testFrameRendererDetachWithoutAttachIsSafe() async throws {
        let renderer = D3D11Renderer()
        renderer.detach()
        renderer.detach()
        XCTAssertFalse(renderer.isAttached)
        XCTAssertFalse(renderer.isDirect2DEnabled)
    }

    // MARK: - CPU backend

    func testCPUBatchRendererDetachDropsItsRetainedFrame() async throws {
        let renderer = CPUBatchRenderer()
        let size = IntSize(width: 16, height: 16)
        try renderer.resize(to: size)
        try renderer.render(scene: makeQuadScene(size: size))
        XCTAssertNotNil(renderer.lastRenderedBitmap)

        renderer.detach()
        XCTAssertNil(renderer.lastRenderedBitmap, "A detached backend must not keep holding the last frame")
        XCTAssertThrowsError(
            try renderer.render(scene: makeQuadScene(size: size)),
            "A detached backend has no surface size, so rendering must fail rather than draw at a stale size")
    }

    // MARK: - Host call sites

    private func makeSurface(pixelSize: IntSize = IntSize(width: 320, height: 200)) -> SurfaceDescriptor {
        SurfaceDescriptor(
            windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
            pixelSize: pixelSize,
            scaleFactor: 1.0
        )
    }

    private func makeHost(
        recoveryPolicy: BatchBackendRecoveryPolicy = .disabled,
        frameRenderer: FakeRenderBackend = FakeRenderBackend(),
        batchRenderer: FakeBatchRenderBackend = FakeBatchRenderBackend(),
        clock: LifetimeRecoveryClock? = nil
    ) -> (host: WinSwiftUIWindowHost, window: Win32Window) {
        let surface = makeSurface()
        let configuration = WindowGroupConfiguration(
            title: "Lifetime",
            size: surface.pixelSize,
            clearColor: .black,
            content: []
        )
        let host = WinSwiftUIWindowHost(
            configuration: configuration,
            renderer: frameRenderer,
            batchRenderer: batchRenderer,
            surfaceDescriptorProvider: { _ in surface },
            recoveryPolicy: recoveryPolicy
        )
        if let clock {
            host.recoveryClock = { clock.now }
        }
        let window = Win32Window(title: "Lifetime", clientSize: surface.pixelSize)
        host.windowDidCreate(window)
        return (host, window)
    }

    /// Dirties the runtime and paints a frame, which is what actually
    /// exercises the downgrade and recovery paths.
    private func paintFrame(_ host: WinSwiftUIWindowHost, _ window: Win32Window, size: IntSize) {
        host.window(window, didResizeTo: size)
        host.windowNeedsDisplay(window)
    }

    /// Closing a window is the leak the whole workstream exists for: both
    /// backends must be told to let go while the HWND is still alive.
    func testWindowWillCloseDetachesBothBackends() async {
        let frameRenderer = FakeRenderBackend()
        let batchRenderer = FakeBatchRenderBackend()
        let (host, window) = makeHost(frameRenderer: frameRenderer, batchRenderer: batchRenderer)

        XCTAssertEqual(batchRenderer.detachCount, 0)
        host.windowWillClose(window)

        XCTAssertEqual(batchRenderer.detachCount, 1, "The scene backend owns the swap chain and must be detached")
        XCTAssertEqual(
            frameRenderer.detachCount, 1,
            "The frame backend is detached too — it may have attached earlier in the session")
    }

    /// A presenter switch must release the outgoing backend's swap chain
    /// before the incoming one asks DXGI for the HWND, because flip-model
    /// presentation is exclusive per window.
    func testMidSessionDowngradeDetachesBatchBeforeAttachingFrame() async {
        let frameRenderer = FakeRenderBackend()
        let batchRenderer = FakeBatchRenderBackend()
        let (host, window) = makeHost(frameRenderer: frameRenderer, batchRenderer: batchRenderer)

        batchRenderer.setRenderShouldFail(true)
        paintFrame(host, window, size: IntSize(width: 640, height: 480))

        XCTAssertEqual(batchRenderer.detachCount, 1, "The failing scene backend must be detached on downgrade")
        XCTAssertEqual(frameRenderer.attachedSurfaces.count, 1, "The frame backend takes over the surface")
        XCTAssertGreaterThan(
            frameRenderer.lastAttachOrder, batchRenderer.lastDetachOrder,
            "The batch swap chain must be released before the frame backend claims the same HWND")
    }

    /// A batch attach that throws at startup can still have created a swap
    /// chain before failing, so the downgrade path detaches it too.
    func testStartupBatchAttachFailureDetachesBatchBeforeAttachingFrame() async {
        let frameRenderer = FakeRenderBackend()
        let batchRenderer = FakeBatchRenderBackend(attachShouldFail: true)
        let (_, _) = makeHost(frameRenderer: frameRenderer, batchRenderer: batchRenderer)

        XCTAssertEqual(batchRenderer.detachCount, 1)
        XCTAssertEqual(frameRenderer.attachedSurfaces.count, 1)
        XCTAssertGreaterThan(frameRenderer.lastAttachOrder, batchRenderer.lastDetachOrder)
    }

    /// Recovery is the same switch in the other direction: the frame
    /// backend has to let go of the HWND before the batch backend re-claims
    /// it.
    func testBatchRecoveryDetachesFrameBackendBeforeReattachingBatch() async {
        let frameRenderer = FakeRenderBackend()
        let batchRenderer = FakeBatchRenderBackend()
        let clock = LifetimeRecoveryClock(100)
        let (host, window) = makeHost(
            recoveryPolicy: .standard,
            frameRenderer: frameRenderer,
            batchRenderer: batchRenderer,
            clock: clock
        )

        batchRenderer.setRenderShouldFail(true)
        paintFrame(host, window, size: IntSize(width: 640, height: 480))
        XCTAssertEqual(host.rendererHealthSnapshot.activeBackend, .frame)

        batchRenderer.setRenderShouldFail(false)
        let attachesBeforeRecovery = batchRenderer.attachedSurfaces.count
        clock.now += 30
        paintFrame(host, window, size: IntSize(width: 641, height: 481))

        XCTAssertEqual(
            host.rendererHealthSnapshot.activeBackend, .scene, "Recovery should have restored the scene path")
        XCTAssertEqual(batchRenderer.attachedSurfaces.count, attachesBeforeRecovery + 1)
        XCTAssertEqual(frameRenderer.detachCount, 1, "The frame backend must release the HWND before batch re-attaches")
        XCTAssertGreaterThan(
            batchRenderer.lastAttachOrder, frameRenderer.lastDetachOrder,
            "The frame swap chain must be released before the batch backend claims the same HWND")
    }

    /// If recovery fails after the frame backend was released, the window
    /// would freeze on its last presented frame. The frame backend has to
    /// come back.
    func testFailedBatchRecoveryRestoresTheFrameBackend() async {
        let frameRenderer = FakeRenderBackend()
        let batchRenderer = FakeBatchRenderBackend()
        let clock = LifetimeRecoveryClock(100)
        let (host, window) = makeHost(
            recoveryPolicy: .standard,
            frameRenderer: frameRenderer,
            batchRenderer: batchRenderer,
            clock: clock
        )

        batchRenderer.setRenderShouldFail(true)
        paintFrame(host, window, size: IntSize(width: 640, height: 480))
        let frameAttachesAfterDowngrade = frameRenderer.attachedSurfaces.count

        batchRenderer.setAttachShouldFail(true)
        clock.now += 30
        paintFrame(host, window, size: IntSize(width: 641, height: 481))

        XCTAssertEqual(host.rendererHealthSnapshot.activeBackend, .frame, "A failed recovery stays on the frame path")
        XCTAssertEqual(
            frameRenderer.attachedSurfaces.count, frameAttachesAfterDowngrade + 1,
            "The frame backend must be re-attached after a failed recovery released it")
        XCTAssertEqual(batchRenderer.detachCount, 2, "The half-attached batch backend is released again")
    }

    // MARK: - Helpers

    /// A `D3D11BatchRenderer` of this test's own, attached offscreen on
    /// WARP. The shared `WARPBatchRenderer` is deliberately not used: these
    /// tests destroy the device, and every other GPU suite depends on that
    /// cached instance staying alive.
    private func makeDetachableRenderer(size: IntSize) throws -> D3D11BatchRenderer {
        // Prove a device exists on this machine before spending a second on
        // shader compilation, and report the same skip every other GPU
        // suite reports when it does not.
        let probe = try makeWARPDevice()
        probe.release()

        let renderer = D3D11BatchRenderer()
        do {
            try renderer.attachOffscreen(size: size, driver: .warpFirst)
        } catch {
            throw XCTSkip("D3D11 batch renderer unavailable on this machine: \(error)")
        }
        return renderer
    }
}
