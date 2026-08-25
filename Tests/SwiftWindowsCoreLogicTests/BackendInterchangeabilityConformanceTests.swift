import SwiftWindowsCore
import SwiftWindowsGraphics
import WinSwiftUI
import XCTest

/// Exercises the public renderer seam without importing WinSDK, a Win32 host,
/// or a concrete GPU backend. A retained SwiftUI-shaped view produces one
/// scene; independently selected renderers then consume that identical scene
/// through genuinely handle-free surfaces.
@MainActor
final class BackendInterchangeabilityConformanceTests: XCTestCase {
    private let size = IntSize(width: 48, height: 48)

    private struct LegacyFrameOnlyFactory: RenderBackendFactory {
        var factoryName: String { "Legacy Frame Only" }

        func makeRenderBackend() -> any RenderBackend {
            CPUBatchRenderer()
        }

        func makeBatchRenderBackend() -> (any BatchRenderBackend)? {
            nil
        }
    }

    private struct RecordingOffscreenFactory: RenderBackendFactory {
        let backend: RecordingOffscreenBackend

        var factoryName: String { "Independent Offscreen Engine" }
        var capabilities: RenderBackendCapabilities { .cpuOffscreen }

        func makeRenderBackend() -> any RenderBackend {
            backend
        }

        func makeBatchRenderBackend() -> (any BatchRenderBackend)? {
            backend
        }
    }

    private struct InjectedRecordingApp: App {
        var body: Never { fatalError("This conformance probe never boots an application.") }

        static func renderBackendFactory() -> RenderBackendFactory {
            RecordingOffscreenFactory(backend: RecordingOffscreenBackend())
        }
    }

    private enum RecordingBackendError: Error {
        case unsupportedSurface
        case notAttached
    }

    private final class RecordingOffscreenBackend: BatchRenderBackend, RenderBackend {
        private(set) var attachedSurface: SurfaceDescriptor?
        private(set) var presentationRuns: [GPUIPresentationRun] = []
        private(set) var boundSceneCount = 0
        private(set) var renderedSceneCount = 0
        private(set) var renderedFrameCount = 0
        private(set) var detachCount = 0
        private(set) var lastRenderedBitmap: BitmapSurface?

        var backendDisplayName: String { "INDEPENDENT OFFSCREEN" }
        var presentationState: PresentationState { PresentationState() }
        var presentPacing: PresentPacingStatus { PresentPacingStatus() }

        func setDisplayFrameInterval(_ seconds: Double) {}

        func adoptRememberedSelfPacing() {}

        func attach(to surface: SurfaceDescriptor) throws {
            guard case .offscreen = surface.target else {
                throw RecordingBackendError.unsupportedSurface
            }
            attachedSurface = surface
        }

        func resize(to size: IntSize) throws {
            guard attachedSurface != nil else {
                throw RecordingBackendError.notAttached
            }
            attachedSurface?.pixelSize = size
        }

        func bindResources(for scene: GPUIScene) {
            boundSceneCount += 1
        }

        func render(scene: GPUIScene) throws {
            let surface = try requireSurface()
            presentationRuns = Array(scene.presentationOrder())
            lastRenderedBitmap = GPUIRawSceneRasterizer.rasterize(scene, size: surface.pixelSize)
            renderedSceneCount += 1
        }

        func render(frame: RenderFrame) throws {
            let surface = try requireSurface()
            let surfaceSize = Size(width: Double(surface.pixelSize.width), height: Double(surface.pixelSize.height))
            let scene = GPUIScene(from: frame, surfaceSize: surfaceSize)
            presentationRuns = Array(scene.presentationOrder())
            lastRenderedBitmap = GPUIRawSceneRasterizer.rasterize(scene, size: surface.pixelSize)
            renderedFrameCount += 1
        }

        func detach() {
            attachedSurface = nil
            presentationRuns.removeAll()
            lastRenderedBitmap = nil
            detachCount += 1
        }

        private func requireSurface() throws -> SurfaceDescriptor {
            guard let attachedSurface else {
                throw RecordingBackendError.notAttached
            }
            return attachedSurface
        }
    }

    private func retainedSnapshot() -> WinSwiftUIRenderSnapshot {
        WinSwiftUIRendererSnapshotter.snapshot(
            of: ZStack {
                Rectangle()
                    .fill(Color(red: 1, green: 0, blue: 0, alpha: 1))
                    .frame(width: 40, height: 40)
                Rectangle()
                    .fill(Color(red: 0, green: 1, blue: 0, alpha: 1))
                    .frame(width: 20, height: 20)
            }
            .frame(width: 48, height: 48),
            size: size,
            clearColor: .black
        )
    }

    private func solidQuad(_ color: Color) -> QuadPrimitive {
        QuadPrimitive(
            x: 0, y: 0, width: Float(size.width), height: Float(size.height),
            startR: color.red, startG: color.green, startB: color.blue, startA: color.alpha,
            endR: color.red, endG: color.green, endB: color.blue, endA: color.alpha
        )
    }

    func testPresentationTargetsRemainIndependentlyComposable() async {
        let both: RenderBackendPresentationTargets = [.window, .offscreen]

        XCTAssertTrue(both.contains(.window))
        XCTAssertTrue(both.contains(.offscreen))
        XCTAssertEqual(both.subtracting(.window), [.offscreen])
        XCTAssertFalse(RenderBackendPresentationTargets.window.contains(.offscreen))
    }

    func testLegacyFactoriesRemainCompatibleWithoutClaimingUnverifiedCapabilities() async {
        let factory: any RenderBackendFactory = LegacyFrameOnlyFactory()
        let capabilities = factory.capabilities

        XCTAssertEqual(capabilities, .conservative)
        XCTAssertTrue(capabilities.supportsFrameRendering)
        XCTAssertFalse(capabilities.supportsSceneRendering)
        XCTAssertFalse(capabilities.supportsWindowPresentation)
        XCTAssertFalse(capabilities.supportsOffscreenRendering)
        XCTAssertFalse(capabilities.supportsPresentedFrameCapture)
        XCTAssertFalse(capabilities.supportsVSyncControl)
        XCTAssertEqual(capabilities.executionModel, .unspecified)
    }

    func testCPUReferenceDeclaresOnlyItsGenuineOffscreenTargets() async {
        let capabilities = CPURenderBackendFactory().capabilities

        XCTAssertTrue(capabilities.supportsFrameRendering)
        XCTAssertTrue(capabilities.supportsSceneRendering)
        XCTAssertTrue(capabilities.supportsOffscreenRendering)
        XCTAssertFalse(capabilities.supportsWindowPresentation)
        XCTAssertFalse(capabilities.supportsPresentedFrameCapture)
        XCTAssertFalse(capabilities.supportsVSyncControl)
        XCTAssertEqual(capabilities.executionModel, .software)
        XCTAssertEqual(capabilities.supportedPresentationTargets, [.offscreen])
    }

    func testFacadeSoftwareFactoryDeclaresRealWindowPresentation() async {
        let capabilities = SoftwareWindowRenderBackendFactory().capabilities

        XCTAssertTrue(capabilities.supportsFrameRendering)
        XCTAssertTrue(capabilities.supportsSceneRendering)
        XCTAssertTrue(capabilities.supportsWindowPresentation)
        XCTAssertFalse(capabilities.supportsOffscreenRendering)
        XCTAssertFalse(capabilities.supportsPresentedFrameCapture)
        XCTAssertFalse(capabilities.supportsVSyncControl)
        XCTAssertEqual(capabilities.executionModel, .software)
        XCTAssertEqual(capabilities.supportedPresentationTargets, [.window])
    }

    func testGraphicsDeviceContractDoesNotMisidentifySoftwareAdaptersAsHardware() async {
        let capabilities = RenderBackendCapabilities.graphicsDeviceWindow

        XCTAssertEqual(capabilities.executionModel, .graphicsDevice)
        XCTAssertTrue(capabilities.supportsWindowPresentation)
        XCTAssertFalse(capabilities.supportsOffscreenRendering)
        XCTAssertTrue(capabilities.supportsPresentedFrameCapture)
        XCTAssertTrue(capabilities.supportsVSyncControl)
        XCTAssertTrue(RenderBackendAvailability.degraded(reason: "Software graphics adapter").canPresent)
    }

    func testCapabilitiesCanEvaluateARealHandleFreeSurfaceTarget() async {
        let surface = SurfaceDescriptor(offscreenPixelSize: size, scaleFactor: 1)

        XCTAssertNil(surface.windowHandle)
        XCTAssertTrue(CPURenderBackendFactory().capabilities.supports(surface.target))
        XCTAssertFalse(SoftwareWindowRenderBackendFactory().capabilities.supports(surface.target))
        XCTAssertFalse(RenderBackendCapabilities.graphicsDeviceWindow.supports(surface.target))
    }

    func testCustomAppFactoryCanSelectAnIndependentRendererWithoutGPUImports() async {
        let factory = InjectedRecordingApp.renderBackendFactory()

        XCTAssertEqual(factory.factoryName, "Independent Offscreen Engine")
        XCTAssertEqual(factory.capabilities, .cpuOffscreen)
        XCTAssertTrue(factory.makeRenderBackend() is RecordingOffscreenBackend)
        XCTAssertTrue(factory.makeBatchRenderBackend() is RecordingOffscreenBackend)
    }

    func testRetainedViewSceneCanSwapBetweenIndependentOffscreenEngines() async throws {
        let snapshot = retainedSnapshot()
        let surface = SurfaceDescriptor(offscreenPixelSize: snapshot.size, scaleFactor: snapshot.displayScale)
        let cpuFactory: any RenderBackendFactory = CPURenderBackendFactory()
        let cpu = try XCTUnwrap(cpuFactory.makeBatchRenderBackend() as? CPUBatchRenderer)
        let recorder = RecordingOffscreenBackend()
        let alternateFactory: any RenderBackendFactory = RecordingOffscreenFactory(backend: recorder)
        let alternate = try XCTUnwrap(alternateFactory.makeBatchRenderBackend())

        try cpu.attach(to: surface)
        cpu.bindResources(for: snapshot.scene)
        try cpu.render(scene: snapshot.scene)

        try alternate.attach(to: surface)
        alternate.bindResources(for: snapshot.scene)
        try alternate.render(scene: snapshot.scene)

        let expected = GPUIRawSceneRasterizer.rasterize(snapshot.scene, size: snapshot.size)
        let cpuBitmap = try XCTUnwrap(cpu.lastRenderedBitmap)
        let alternateBitmap = try XCTUnwrap(recorder.lastRenderedBitmap)

        XCTAssertEqual(cpuBitmap, expected)
        XCTAssertEqual(alternateBitmap, expected)
        XCTAssertEqual(cpuBitmap, alternateBitmap)
        XCTAssertEqual(recorder.presentationRuns, Array(snapshot.scene.presentationOrder()))
        XCTAssertFalse(recorder.presentationRuns.isEmpty)
        XCTAssertEqual(recorder.boundSceneCount, 1)
        XCTAssertEqual(recorder.renderedSceneCount, 1)
        XCTAssertEqual(alternateBitmap.pixelColor(atX: 24, y: 24)?.green, 1)
        XCTAssertNil(recorder.attachedSurface?.windowHandle)
    }

    func testEngineSwapPreservesLayerMajorPresentationInsteadOfReplayOrder() async throws {
        let red = Color(red: 1, green: 0, blue: 0, alpha: 1)
        let green = Color(red: 0, green: 1, blue: 0, alpha: 1)
        var scene = GPUIScene(clearColor: .black)

        // The replay log deliberately records the upper layer first. A backend
        // that replays insertion order would incorrectly leave green on top.
        scene.addQuad(solidQuad(red), toLayer: 1)
        scene.addQuad(solidQuad(green), toLayer: 0)

        let surface = SurfaceDescriptor(offscreenPixelSize: size)
        let cpu = CPUBatchRenderer()
        let alternate = RecordingOffscreenBackend()
        try cpu.attach(to: surface)
        try alternate.attach(to: surface)
        try cpu.render(scene: scene)
        try alternate.render(scene: scene)

        let cpuBitmap = try XCTUnwrap(cpu.lastRenderedBitmap)
        let alternateBitmap = try XCTUnwrap(alternate.lastRenderedBitmap)

        XCTAssertEqual(alternate.presentationRuns.map(\.layerIndex), [0, 1])
        XCTAssertEqual(cpuBitmap, alternateBitmap)
        XCTAssertEqual(cpuBitmap.pixelColor(atX: 24, y: 24)?.red, 1)
        XCTAssertEqual(cpuBitmap.pixelColor(atX: 24, y: 24)?.green, 0)
    }

    func testFrameAndSceneContractsProduceTheSamePixelsAcrossEngines() async throws {
        let frame = RenderFrame(
            clearColor: .black,
            commands: [
                .fillRect(
                    FillRectCommand(
                        rect: Rect(x: 4, y: 6, width: 20, height: 24),
                        color: Color(red: 0.2, green: 0.7, blue: 0.9, alpha: 1)
                    ))
            ]
        )
        let scene = GPUIScene(
            from: frame,
            surfaceSize: Size(width: Double(size.width), height: Double(size.height))
        )
        let surface = SurfaceDescriptor(offscreenPixelSize: size)
        let frameRenderer = CPUBatchRenderer()
        let sceneRenderer = RecordingOffscreenBackend()

        try frameRenderer.attach(to: surface)
        try sceneRenderer.attach(to: surface)
        try frameRenderer.render(frame: frame)
        try sceneRenderer.render(scene: scene)

        XCTAssertEqual(frameRenderer.lastRenderedBitmap, sceneRenderer.lastRenderedBitmap)
        XCTAssertEqual(sceneRenderer.presentationRuns, Array(scene.presentationOrder()))

        try sceneRenderer.render(frame: frame)
        XCTAssertEqual(frameRenderer.lastRenderedBitmap, sceneRenderer.lastRenderedBitmap)
        XCTAssertEqual(sceneRenderer.renderedFrameCount, 1)
    }

    func testSwappedOffscreenEnginesRemainIndependentAcrossResizeAndDetach() async throws {
        let initialSurface = SurfaceDescriptor(offscreenPixelSize: size)
        let resized = IntSize(width: 12, height: 18)
        let scene = GPUIScene(clearColor: Color(red: 0, green: 0, blue: 1, alpha: 1))
        let cpu = CPUBatchRenderer()
        let alternate = RecordingOffscreenBackend()

        try cpu.attach(to: initialSurface)
        try alternate.attach(to: initialSurface)
        try cpu.resize(to: resized)
        try alternate.resize(to: resized)
        try cpu.render(scene: scene)
        try alternate.render(scene: scene)

        XCTAssertEqual(cpu.lastRenderedBitmap, alternate.lastRenderedBitmap)
        XCTAssertEqual(alternate.lastRenderedBitmap?.width, resized.width)
        XCTAssertEqual(alternate.lastRenderedBitmap?.height, resized.height)

        alternate.detach()
        XCTAssertNil(alternate.lastRenderedBitmap)
        XCTAssertNil(alternate.attachedSurface)
        XCTAssertThrowsError(try alternate.render(scene: scene))
        XCTAssertNotNil(cpu.lastRenderedBitmap, "Detaching one engine must not disturb another engine.")

        try alternate.attach(to: initialSurface)
        try alternate.render(scene: scene)
        XCTAssertEqual(alternate.lastRenderedBitmap?.width, size.width)
        XCTAssertEqual(alternate.detachCount, 1)
    }

    func testCPUFactoriesCreateIndependentBackendInstances() async throws {
        let factory = CPURenderBackendFactory()
        let first = try XCTUnwrap(factory.makeBatchRenderBackend() as? CPUBatchRenderer)
        let second = try XCTUnwrap(factory.makeBatchRenderBackend() as? CPUBatchRenderer)
        let surface = SurfaceDescriptor(offscreenPixelSize: size)

        XCTAssertFalse(first === second)
        try first.attach(to: surface)
        try second.attach(to: surface)
        try first.render(scene: GPUIScene(clearColor: .white))
        try second.render(scene: GPUIScene(clearColor: .black))

        XCTAssertNotEqual(first.lastRenderedBitmap, second.lastRenderedBitmap)
        first.detach()
        XCTAssertNil(first.lastRenderedBitmap)
        XCTAssertNotNil(second.lastRenderedBitmap)
    }
}
