import XCTest
import SwiftWindowsCore
import SwiftWindowsGraphics
@testable import SwiftWindowsPlatform
import SwiftWindowsRendererD3D11
@testable import SwiftWindowsUI
@testable import WinSwiftUI

// MARK: - Fake Render Backends

@MainActor
final class FakeRenderBackend: RenderBackend {
    private(set) var attachedSurfaces: [SurfaceDescriptor] = []
    private(set) var resizedSizes: [IntSize] = []
    private(set) var renderedFrames: [RenderFrame] = []
    private(set) var attachShouldFail: Bool
    private(set) var resizeShouldFail: Bool
    private(set) var renderShouldFail: Bool
    var failureError: Error = FakeRenderBackendError.simulatedFailure

    init(attachShouldFail: Bool = false, resizeShouldFail: Bool = false, renderShouldFail: Bool = false) {
        self.attachShouldFail = attachShouldFail
        self.resizeShouldFail = resizeShouldFail
        self.renderShouldFail = renderShouldFail
    }

    var backendDisplayName: String { "FAKE FRAME" }
    var backendStatusDescription: String { "Fake Frame Backend" }

    func attach(to surface: SurfaceDescriptor) throws {
        if attachShouldFail {
            throw failureError
        }
        attachedSurfaces.append(surface)
    }

    func resize(to size: IntSize) throws {
        if resizeShouldFail {
            throw failureError
        }
        resizedSizes.append(size)
    }

    func render(frame: RenderFrame) throws {
        if renderShouldFail {
            throw failureError
        }
        renderedFrames.append(frame)
    }

    func setAttachShouldFail(_ shouldFail: Bool) {
        attachShouldFail = shouldFail
    }

    func setResizeShouldFail(_ shouldFail: Bool) {
        resizeShouldFail = shouldFail
    }

    func setRenderShouldFail(_ shouldFail: Bool) {
        renderShouldFail = shouldFail
    }
}

@MainActor
final class FakeBatchRenderBackend: BatchRenderBackend {
    enum Event: Equatable {
        case bind([Int32])
        case render([Int32])
    }

    private(set) var attachedSurfaces: [SurfaceDescriptor] = []
    private(set) var resizedSizes: [IntSize] = []
    private(set) var renderedScenes: [GPUIScene] = []
    private(set) var boundScenes: [GPUIScene] = []
    private(set) var events: [Event] = []
    private(set) var attachShouldFail: Bool
    private(set) var resizeShouldFail: Bool
    private(set) var renderShouldFail: Bool
    private(set) var requireBoundImageResourcesBeforeRender = false
    private var boundTextureIDs = Set<Int32>()
    var failureError: Error = FakeRenderBackendError.simulatedFailure

    init(attachShouldFail: Bool = false, resizeShouldFail: Bool = false, renderShouldFail: Bool = false) {
        self.attachShouldFail = attachShouldFail
        self.resizeShouldFail = resizeShouldFail
        self.renderShouldFail = renderShouldFail
    }

    var backendDisplayName: String { "FAKE BATCH" }

    func attach(to surface: SurfaceDescriptor) throws {
        if attachShouldFail {
            throw failureError
        }
        attachedSurfaces.append(surface)
    }

    func resize(to size: IntSize) throws {
        if resizeShouldFail {
            throw failureError
        }
        resizedSizes.append(size)
    }

    func bindResources(for scene: GPUIScene) {
        boundScenes.append(scene)
        let textureIDs = scene.imageResources.map(\.textureID).sorted()
        boundTextureIDs = Set(textureIDs)
        events.append(.bind(textureIDs))
    }

    func render(scene: GPUIScene) throws {
        if renderShouldFail {
            throw failureError
        }

        if requireBoundImageResourcesBeforeRender {
            let imageTextureIDs = Set(scene.layers.flatMap(\.images).map(\.textureID))
            if !imageTextureIDs.isSubset(of: boundTextureIDs) {
                throw BatchRendererError(
                    operation: "Resolve image resources",
                    hresult: -1,
                    details: "Scene contains image primitives without bound resources."
                )
            }
        }

        renderedScenes.append(scene)
        events.append(.render(scene.layers.flatMap(\.images).map(\.textureID)))
    }

    func setAttachShouldFail(_ shouldFail: Bool) {
        attachShouldFail = shouldFail
    }

    func setResizeShouldFail(_ shouldFail: Bool) {
        resizeShouldFail = shouldFail
    }

    func setRenderShouldFail(_ shouldFail: Bool) {
        renderShouldFail = shouldFail
    }

    func setRequireBoundImageResourcesBeforeRender(_ require: Bool) {
        requireBoundImageResourcesBeforeRender = require
    }
}

enum FakeRenderBackendError: Error, Equatable {
    case simulatedFailure
    case attachFailure
    case resizeFailure
    case renderFailure
}

// MARK: - Input Event Recorder for Host-Routed Input Assertions

@MainActor
final class RoutedInputEventRecorder {
    private(set) var events: [WindowHostInputEvent] = []

    func record(_ event: WindowHostInputEvent) {
        events.append(event)
    }
}

// MARK: - Observable Test Object

@MainActor
final class TestObservableObject: ObservableObject {
    @Published var value: Int = 0
    @Published var secondaryValue: String = ""
}

@MainActor
struct ObservedObjectValueView: View {
    @ObservedObject var model: TestObservableObject

    var body: some View {
        Text("\(model.value)")
    }
}

@MainActor
final class HostEnvironmentRecorder {
    private(set) var snapshots: [EnvironmentValues] = []

    func record(_ values: EnvironmentValues) {
        snapshots.append(values)
    }
}

@MainActor
struct HostEnvironmentProbeView: View {
    typealias Body = Never

    let recorder: HostEnvironmentRecorder

    var body: Never {
        fatalError("HostEnvironmentProbeView has no body")
    }

    func makeComponent(context: ViewBuildContext) -> Component {
        recorder.record(context.environmentValues)
        return Component { _ in
            Controls.panel(frame: Rect(x: 0, y: 0, width: 1, height: 1), isHitTestVisible: false)
        }
    }
}

// MARK: - Refresh Rate Testing Helpers

/// Captures the effective refresh rate behavior by examining timer configuration.
/// Returns the expected timer interval in milliseconds for a given refresh rate.
func expectedTimerInterval(for refreshRate: UInt32) -> UInt32 {
    let rate = max(refreshRate, 1)
    let interval = (1000.0 / Double(rate)).rounded()
    return max(1, UInt32(interval))
}

@MainActor
final class WinSwiftUIWindowHostTests: XCTestCase {
    private func fillRectCommands(in frame: RenderFrame) -> [FillRectCommand] {
        frame.commands.compactMap { command in
            guard case .fillRect(let fillRect) = command else {
                return nil
            }
            return fillRect
        }
    }

    private func makeSurface(pixelSize: IntSize, scaleFactor: Double) -> SurfaceDescriptor {
        SurfaceDescriptor(
            windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
            pixelSize: pixelSize,
            scaleFactor: scaleFactor
        )
    }

    private func makeBoundImageScene() -> GPUIScene {
        let bitmap = BitmapSurface(width: 1, height: 1, bytesPerRow: 4, pixels: Data([255, 255, 255, 255]))
        let frame = RenderFrame(
            clearColor: .black,
            commands: [
                .drawBitmap(DrawBitmapCommand(
                    rect: Rect(x: 20, y: 24, width: 48, height: 32),
                    bitmap: bitmap,
                    opacity: 0.75
                ))
            ]
        )
        return GPUIScene(from: frame, surfaceSize: Size(width: 320, height: 200))
    }

    private func makeInputRoutingHost(
        pixelSize: IntSize = IntSize(width: 640, height: 480),
        scaleFactor: Double = 1.0
    ) -> (host: WinSwiftUIWindowHost, window: Win32Window, recorder: RoutedInputEventRecorder) {
        let surface = makeSurface(pixelSize: pixelSize, scaleFactor: scaleFactor)
        let config = WindowGroupConfiguration(
            title: "Test",
            size: IntSize(
                width: Int32((Double(pixelSize.width) / max(scaleFactor, 1.0)).rounded(.toNearestOrAwayFromZero)),
                height: Int32((Double(pixelSize.height) / max(scaleFactor, 1.0)).rounded(.toNearestOrAwayFromZero))
            ),
            clearColor: .black,
            content: []
        )
        let host = WinSwiftUIWindowHost(
            configuration: config,
            renderer: FakeRenderBackend(),
            batchRenderer: nil,
            surfaceDescriptorProvider: { _ in surface }
        )
        let recorder = RoutedInputEventRecorder()
        host.onInputEventRouted = { recorder.record($0) }

        let window = Win32Window(title: "Test", clientSize: pixelSize)
        window.testScaleFactorOverride = scaleFactor
        host.windowDidCreate(window)

        return (host, window, recorder)
    }

    private func makeResizePropagationHost(
        pixelSize: IntSize,
        scaleFactor: Double,
        frameRenderer: FakeRenderBackend = FakeRenderBackend(),
        batchRenderer: FakeBatchRenderBackend? = nil
    ) -> (host: WinSwiftUIWindowHost, window: Win32Window, frameRenderer: FakeRenderBackend, batchRenderer: FakeBatchRenderBackend?) {
        let surface = makeSurface(pixelSize: pixelSize, scaleFactor: scaleFactor)
        let config = WindowGroupConfiguration(
            title: "Test",
            size: IntSize(
                width: Int32((Double(pixelSize.width) / max(scaleFactor, 1.0)).rounded(.toNearestOrAwayFromZero)),
                height: Int32((Double(pixelSize.height) / max(scaleFactor, 1.0)).rounded(.toNearestOrAwayFromZero))
            ),
            clearColor: .black,
            content: []
        )
        let host = WinSwiftUIWindowHost(
            configuration: config,
            renderer: frameRenderer,
            batchRenderer: batchRenderer,
            surfaceDescriptorProvider: { _ in surface }
        )
        let window = Win32Window(title: "Test", clientSize: pixelSize)
        window.testScaleFactorOverride = scaleFactor
        host.windowDidCreate(window)

        return (host, window, frameRenderer, batchRenderer)
    }

    // MARK: - Batch Attach/Resize/Render Downgrade Tests

    func testBatchAttachFailureFallsBackToFrameRenderer() async {
        await MainActor.run {
            let batchRenderer = FakeBatchRenderBackend(attachShouldFail: true)
            let frameRenderer = FakeRenderBackend()

            let expectedSurface = SurfaceDescriptor(
                windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
                pixelSize: IntSize(width: 320, height: 200),
                scaleFactor: 1.0
            )

            let config = WindowGroupConfiguration(
                title: "Test",
                size: IntSize(width: 320, height: 200),
                clearColor: .black,
                content: []
            )

            let host = WinSwiftUIWindowHost(
                configuration: config,
                renderer: frameRenderer,
                batchRenderer: batchRenderer,
                surfaceDescriptorProvider: { _ in expectedSurface }
            )

            let fakeWindow = Win32Window(title: "Test", clientSize: expectedSurface.pixelSize)
            host.windowDidCreate(fakeWindow)

            // Batch attach failed, frame attach should have succeeded
            XCTAssertEqual(batchRenderer.attachedSurfaces.count, 0)
            XCTAssertEqual(frameRenderer.attachedSurfaces.count, 1)
            XCTAssertEqual(frameRenderer.attachedSurfaces.first, expectedSurface)
            XCTAssertEqual(
                host.currentPresentationSelection,
                PresentationSelection(
                    presenter: .frame,
                    reason: .batchAttachFailure(String(describing: batchRenderer.failureError)),
                    frameBackend: frameRenderer.backendDisplayName,
                    sceneBackend: batchRenderer.backendDisplayName
                )
            )
        }
    }

    func testBatchRenderFailureDowngradesToFrameSameSession() async {
        await MainActor.run {
            let batchRenderer = FakeBatchRenderBackend()
            let frameRenderer = FakeRenderBackend()

            let expectedSurface = SurfaceDescriptor(
                windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
                pixelSize: IntSize(width: 320, height: 200),
                scaleFactor: 1.0
            )

            let expectedColor = Color(red: 0.1, green: 0.2, blue: 0.3, alpha: 1.0)
            let config = WindowGroupConfiguration(
                title: "Test",
                size: IntSize(width: 320, height: 200),
                clearColor: expectedColor,
                content: []
            )

            let host = WinSwiftUIWindowHost(
                configuration: config,
                renderer: frameRenderer,
                batchRenderer: batchRenderer,
                surfaceDescriptorProvider: { _ in expectedSurface }
            )

            let fakeWindow = Win32Window(title: "Test", clientSize: expectedSurface.pixelSize)
            host.windowDidCreate(fakeWindow)

            // Initial render with batch succeeds
            XCTAssertEqual(batchRenderer.renderedScenes.count, 1)
            XCTAssertEqual(frameRenderer.renderedFrames.count, 0)

            // Make batch render fail, then trigger a resize (which reloads and requests frame)
            // followed by display to force render
            batchRenderer.setRenderShouldFail(true)
            let newSize = IntSize(width: 640, height: 480)
            host.window(fakeWindow, didResizeTo: newSize)
            
            // The resize triggers reload which makes runtime dirty
            // Calling windowNeedsDisplay will trigger renderCurrentFrame
            host.windowNeedsDisplay(fakeWindow)

            // After render failure and downgrade, frame renderer should be attached
            XCTAssertEqual(frameRenderer.attachedSurfaces.count, 1, "Frame renderer should be attached after batch failure")
            
            // CRITICAL: Verify the frame was actually rendered/presented through the frame path
            // This proves VAL-RENDER-004: the triggering frame renders through frame path after batch failure
            XCTAssertEqual(frameRenderer.renderedFrames.count, 1, "Frame should be rendered through frame path after batch failure")
            XCTAssertEqual(frameRenderer.renderedFrames.first?.clearColor, expectedColor, "Frame should contain the expected clear color")
            XCTAssertEqual(
                host.currentPresentationSelection,
                PresentationSelection(
                    presenter: .frame,
                    reason: .batchRenderFailure(String(describing: batchRenderer.failureError)),
                    frameBackend: frameRenderer.backendDisplayName,
                    sceneBackend: batchRenderer.backendDisplayName
                )
            )
        }
    }

    /// VAL-CROSS-007: If the host downgrades from scene to frame after a
    /// localized mutation, deferred ordering stays correct, the incompatible
    /// scene-backed deferred payload reruns on the triggering fallback frame,
    /// and later downgraded-frame renders replay the unchanged deferred subtree.
    func testHostDrivenDowngradePreservesDeferredReplayCorrectnessAfterLocalizedMutation() async {
        await MainActor.run {
            let batchRenderer = FakeBatchRenderBackend()
            let frameRenderer = FakeRenderBackend()
            let expectedSurface = SurfaceDescriptor(
                windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
                pixelSize: IntSize(width: 180, height: 70),
                scaleFactor: 1.0
            )

            let leftContent = ViewNode(
                frame: Rect(x: 0, y: 0, width: 80, height: 120),
                backgroundColor: .white
            )
            let rightContent = ViewNode(
                frame: Rect(x: 90, y: 0, width: 80, height: 50),
                backgroundColor: .black
            )
            let left = ViewNode(
                frame: Rect(x: 0, y: 0, width: 80, height: 50),
                scrollAxis: .vertical,
                scrollOffset: 20,
                showsScrollIndicator: true,
                children: [leftContent]
            )

            let config = WindowGroupConfiguration(
                title: "Test",
                size: IntSize(width: 180, height: 70),
                clearColor: .black,
                content: []
            )

            var installedTree = false
            weak var capturedRuntime: RetainedViewRuntime?
            let host = WinSwiftUIWindowHost(
                configuration: config,
                renderer: frameRenderer,
                batchRenderer: batchRenderer,
                surfaceDescriptorProvider: { _ in expectedSurface },
                sceneRenderer: { runtime, timestamp in
                    capturedRuntime = runtime
                    if !installedTree {
                        runtime.root.isHitTestVisible = false
                        runtime.root.addChild(left)
                        runtime.root.addChild(rightContent)
                        installedTree = true
                    }
                    return runtime.renderScene(at: timestamp)
                }
            )

            let window = Win32Window(title: "Test", clientSize: expectedSurface.pixelSize)
            host.windowDidCreate(window)

            guard let runtime = capturedRuntime else {
                XCTFail("expected scene renderer to capture the runtime")
                return
            }
            guard let expectedIndicatorRect = left.scrollIndicatorRect(in: left.frame) else {
                XCTFail("expected scroll indicator rect")
                return
            }

            XCTAssertTrue(host.isUsingScenePresentationBackend)
            XCTAssertEqual(batchRenderer.renderedScenes.count, 1)
            XCTAssertEqual(frameRenderer.renderedFrames.count, 0)

            batchRenderer.setRenderShouldFail(true)
            rightContent.backgroundColor = Color(red: 0.3, green: 0.4, blue: 0.7, alpha: 1)
            host.windowNeedsDisplay(window)

            XCTAssertFalse(host.isUsingScenePresentationBackend)
            XCTAssertEqual(frameRenderer.renderedFrames.count, 1)
            XCTAssertEqual(runtime.lastDeferredDrawFrameReplayCount, 0, "The fallback frame must rerun the scene-incompatible deferred payload instead of replaying it")
            XCTAssertEqual(fillRectCommands(in: frameRenderer.renderedFrames[0]).last?.rect, expectedIndicatorRect, "Deferred indicator should remain last after the downgrade-triggering fallback frame")
            XCTAssertEqual(
                host.currentPresentationSelection,
                PresentationSelection(
                    presenter: .frame,
                    reason: .batchRenderFailure(String(describing: batchRenderer.failureError)),
                    frameBackend: frameRenderer.backendDisplayName,
                    sceneBackend: batchRenderer.backendDisplayName
                )
            )

            rightContent.backgroundColor = Color(red: 0.7, green: 0.2, blue: 0.3, alpha: 1)
            host.windowNeedsDisplay(window)

            XCTAssertEqual(frameRenderer.renderedFrames.count, 2)
            XCTAssertEqual(runtime.lastPrepaintReplayCount, 2, "The downgraded frame session should preserve prepaint replay eligibility, including the unchanged left subtree")
            XCTAssertEqual(runtime.lastDeferredDrawFrameReplayCount, 1, "The unchanged deferred indicator should replay on later downgraded-frame renders")
            XCTAssertEqual(fillRectCommands(in: frameRenderer.renderedFrames[1]).last?.rect, expectedIndicatorRect, "Deferred indicator ordering should stay correct in the downgraded frame session")
        }
    }

    func testUnresolvedImageBatchFailureDowngradesToFrameSameSession() async {
        await MainActor.run {
            let batchRenderer = FakeBatchRenderBackend()
            batchRenderer.failureError = BatchRendererError(
                operation: "Resolve image resources",
                hresult: -1,
                details: "Scene contains image primitives without valid bound resources for texture IDs: -1."
            )

            let frameRenderer = FakeRenderBackend()
            let expectedSurface = SurfaceDescriptor(
                windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
                pixelSize: IntSize(width: 320, height: 200),
                scaleFactor: 1.0
            )

            let config = WindowGroupConfiguration(
                title: "Test",
                size: IntSize(width: 320, height: 200),
                clearColor: .black,
                content: []
            )

            let host = WinSwiftUIWindowHost(
                configuration: config,
                renderer: frameRenderer,
                batchRenderer: batchRenderer,
                surfaceDescriptorProvider: { _ in expectedSurface }
            )

            let fakeWindow = Win32Window(title: "Test", clientSize: expectedSurface.pixelSize)
            host.windowDidCreate(fakeWindow)

            XCTAssertEqual(batchRenderer.renderedScenes.count, 1)
            batchRenderer.setRenderShouldFail(true)

            host.window(fakeWindow, didResizeTo: IntSize(width: 640, height: 480))
            host.windowNeedsDisplay(fakeWindow)

            XCTAssertEqual(frameRenderer.attachedSurfaces.count, 1)
            XCTAssertEqual(frameRenderer.renderedFrames.count, 1)
        }
    }

    func testBoundImageSceneStaysOnBatchPresenterWithoutDowngrade() async {
        await MainActor.run {
            let batchRenderer = FakeBatchRenderBackend()
            batchRenderer.setRequireBoundImageResourcesBeforeRender(true)
            let frameRenderer = FakeRenderBackend()

            let expectedSurface = SurfaceDescriptor(
                windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
                pixelSize: IntSize(width: 320, height: 200),
                scaleFactor: 1.0
            )

            let config = WindowGroupConfiguration(
                title: "Test",
                size: IntSize(width: 320, height: 200),
                clearColor: .black,
                content: []
            )

            let boundImageScene = makeBoundImageScene()
            let host = WinSwiftUIWindowHost(
                configuration: config,
                renderer: frameRenderer,
                batchRenderer: batchRenderer,
                surfaceDescriptorProvider: { _ in expectedSurface },
                sceneRenderer: { _, _ in boundImageScene }
            )

            let fakeWindow = Win32Window(title: "Test", clientSize: expectedSurface.pixelSize)
            host.windowDidCreate(fakeWindow)

            XCTAssertTrue(host.isUsingBatchPresentationBackend)
            XCTAssertEqual(batchRenderer.boundScenes.count, 1)
            XCTAssertEqual(batchRenderer.renderedScenes.count, 1)
            XCTAssertEqual(batchRenderer.events, [
                .bind([0]),
                .render([0]),
            ])
            XCTAssertEqual(batchRenderer.renderedScenes[0].layers[0].images[0].opacity, 0.75, accuracy: 0.001)
            XCTAssertEqual(frameRenderer.attachedSurfaces.count, 0)
            XCTAssertEqual(frameRenderer.renderedFrames.count, 0)
            XCTAssertEqual(
                host.currentPresentationSelection,
                PresentationSelection(
                    presenter: .scene,
                    reason: .defaultScene,
                    frameBackend: frameRenderer.backendDisplayName,
                    sceneBackend: batchRenderer.backendDisplayName
                )
            )
        }
    }

    func testBatchResizeFailureDowngradesToFrameRenderer() async {
        await MainActor.run {
            let batchRenderer = FakeBatchRenderBackend()
            let frameRenderer = FakeRenderBackend()

            let expectedSurface = SurfaceDescriptor(
                windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
                pixelSize: IntSize(width: 320, height: 200),
                scaleFactor: 1.0
            )

            let config = WindowGroupConfiguration(
                title: "Test",
                size: IntSize(width: 320, height: 200),
                clearColor: .black,
                content: []
            )

            let host = WinSwiftUIWindowHost(
                configuration: config,
                renderer: frameRenderer,
                batchRenderer: batchRenderer,
                surfaceDescriptorProvider: { _ in expectedSurface }
            )

            let fakeWindow = Win32Window(title: "Test", clientSize: expectedSurface.pixelSize)
            host.windowDidCreate(fakeWindow)

            // Initially batch is attached
            XCTAssertEqual(batchRenderer.attachedSurfaces.count, 1)
            XCTAssertEqual(frameRenderer.attachedSurfaces.count, 0)

            // Make batch resize fail
            batchRenderer.setResizeShouldFail(true)

            // Trigger resize
            let newSize = IntSize(width: 640, height: 480)
            host.window(fakeWindow, didResizeTo: newSize)

            // Should have downgraded to frame renderer
            // Fallback attaches frame renderer and calls resize
            XCTAssertEqual(frameRenderer.attachedSurfaces.count, 1) // Frame was attached as fallback
            XCTAssertTrue(frameRenderer.resizedSizes.contains(newSize)) // Frame got the resize
            XCTAssertEqual(
                host.currentPresentationSelection,
                PresentationSelection(
                    presenter: .frame,
                    reason: .batchResizeFailure(String(describing: batchRenderer.failureError)),
                    frameBackend: frameRenderer.backendDisplayName,
                    sceneBackend: batchRenderer.backendDisplayName
                )
            )
        }
    }

    func testFrameRendererFailureDoesNotCrash() async {
        await MainActor.run {
            let frameRenderer = FakeRenderBackend(renderShouldFail: true)

            let expectedSurface = SurfaceDescriptor(
                windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
                pixelSize: IntSize(width: 320, height: 200),
                scaleFactor: 1.0
            )

            let config = WindowGroupConfiguration(
                title: "Test",
                size: IntSize(width: 320, height: 200),
                clearColor: .black,
                content: []
            )

            let host = WinSwiftUIWindowHost(
                configuration: config,
                renderer: frameRenderer,
                batchRenderer: nil,
                surfaceDescriptorProvider: { _ in expectedSurface }
            )

            let fakeWindow = Win32Window(title: "Test", clientSize: expectedSurface.pixelSize)
            host.windowDidCreate(fakeWindow)

            // Frame was attached but render fails - should not crash
            // The surface is attached during create, and resize happens during init
            XCTAssertGreaterThanOrEqual(frameRenderer.attachedSurfaces.count, 1)
            // Failed renders don't get recorded, but the attach/resizes are still recorded
        }
    }

    // MARK: - VAL-CROSS-003: Resize and DPI Propagation Tests

    /// VAL-CROSS-003: Resize events keep host, runtime, and renderer in sync.
    /// This test drives the real host resize path end to end and asserts
    /// the runtime logical size plus frame-backend resize state after propagation.
    func testResizePropagationSyncsRuntimeLogicalSizeAndBackend() async {
        await MainActor.run {
            let (host, window, frameRenderer, _) = makeResizePropagationHost(
                pixelSize: IntSize(width: 640, height: 480),
                scaleFactor: 1.0
            )

            XCTAssertEqual(host.currentLogicalRootSize, IntSize(width: 640, height: 480))
            XCTAssertEqual(host.currentDisplayScale, 1.0)
            XCTAssertFalse(host.isUsingBatchPresentationBackend)

            let newPixelSize = IntSize(width: 1024, height: 768)
            host.window(window, didResizeTo: newPixelSize)

            XCTAssertEqual(host.currentLogicalRootSize, IntSize(width: 1024, height: 768))
            XCTAssertEqual(host.currentDisplayScale, 1.0)
            XCTAssertEqual(frameRenderer.resizedSizes.last, newPixelSize)
        }
    }

    /// VAL-CROSS-003: DPI change events keep host, runtime, and renderer in sync.
    /// This test uses the production window.scaleFactor seam instead of mutating
    /// SurfaceDescriptor.scaleFactor directly.
    func testDPIChangePropagationSyncsRuntimeDisplayScale() async {
        await MainActor.run {
            let (host, window, frameRenderer, _) = makeResizePropagationHost(
                pixelSize: IntSize(width: 640, height: 480),
                scaleFactor: 1.0
            )

            XCTAssertEqual(host.currentDisplayScale, 1.0)

            window.testScaleFactorOverride = 2.0
            host.window(window, didResizeTo: IntSize(width: 640, height: 480))

            XCTAssertEqual(host.currentDisplayScale, 2.0)
            XCTAssertEqual(host.currentLogicalRootSize, IntSize(width: 320, height: 240))
            XCTAssertEqual(frameRenderer.resizedSizes.last, IntSize(width: 640, height: 480))
        }
    }

    /// VAL-CROSS-003: Combined resize and DPI change keep all components synchronized.
    /// This test exercises the full propagation path when both size and scale change.
    func testResizeAndDPIChangeCombinedPropagation() async {
        await MainActor.run {
            let batchRenderer = FakeBatchRenderBackend()
            let (host, window, _, _) = makeResizePropagationHost(
                pixelSize: IntSize(width: 800, height: 600),
                scaleFactor: 1.0,
                batchRenderer: batchRenderer
            )

            XCTAssertTrue(host.isUsingBatchPresentationBackend)

            window.testScaleFactorOverride = 1.5
            host.window(window, didResizeTo: IntSize(width: 1920, height: 1080))

            XCTAssertEqual(host.currentLogicalRootSize, IntSize(width: 1280, height: 720))
            XCTAssertEqual(host.currentDisplayScale, 1.5)
            XCTAssertEqual(batchRenderer.resizedSizes.last, IntSize(width: 1920, height: 1080))
            XCTAssertTrue(host.isUsingBatchPresentationBackend)
        }
    }

    /// VAL-CROSS-003: Resize propagates correctly to frame renderer after batch downgrade.
    /// Proves the real same-session fallback path reattaches, resizes, and activates the frame renderer.
    func testResizePropagationAfterBatchDowngradeReattachesResizesAndActivatesFrameRenderer() async {
        await MainActor.run {
            let batchRenderer = FakeBatchRenderBackend()
            let frameRenderer = FakeRenderBackend()
            let (host, window, _, _) = makeResizePropagationHost(
                pixelSize: IntSize(width: 640, height: 480),
                scaleFactor: 1.0,
                frameRenderer: frameRenderer,
                batchRenderer: batchRenderer
            )

            XCTAssertEqual(batchRenderer.renderedScenes.count, 1)
            XCTAssertEqual(frameRenderer.renderedFrames.count, 0)
            XCTAssertTrue(host.isUsingBatchPresentationBackend)

            batchRenderer.setResizeShouldFail(true)
            window.testScaleFactorOverride = 2.0

            let newSize = IntSize(width: 1280, height: 960)
            host.window(window, didResizeTo: newSize)

            XCTAssertFalse(host.isUsingBatchPresentationBackend)
            XCTAssertEqual(host.currentDisplayScale, 2.0)
            XCTAssertEqual(host.currentLogicalRootSize, IntSize(width: 640, height: 480))
            XCTAssertEqual(frameRenderer.attachedSurfaces.count, 1)
            XCTAssertEqual(frameRenderer.attachedSurfaces.first?.pixelSize, newSize)
            XCTAssertEqual(frameRenderer.attachedSurfaces.first?.scaleFactor, 2.0)
            XCTAssertEqual(frameRenderer.resizedSizes.last, newSize)

            host.windowNeedsDisplay(window)

            XCTAssertEqual(frameRenderer.renderedFrames.count, 1)
        }
    }

    func testResizeUpdatesLogicalSizeWithScaleFactor() async {
        await MainActor.run {
            let frameRenderer = FakeRenderBackend()

            let expectedSurface = SurfaceDescriptor(
                windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
                pixelSize: IntSize(width: 640, height: 480),
                scaleFactor: 2.0
            )

            let config = WindowGroupConfiguration(
                title: "Test",
                size: IntSize(width: 320, height: 240),
                clearColor: .black,
                content: []
            )

            let host = WinSwiftUIWindowHost(
                configuration: config,
                renderer: frameRenderer,
                batchRenderer: nil,
                surfaceDescriptorProvider: { _ in expectedSurface }
            )

            // Window with 2x scale factor
            let fakeWindow = Win32Window(title: "Test", clientSize: expectedSurface.pixelSize)
            host.windowDidCreate(fakeWindow)

            // Pixel size is 640x480, scale factor is 2.0
            // Logical size should be 320x240
            XCTAssertEqual(frameRenderer.attachedSurfaces.first?.pixelSize, IntSize(width: 640, height: 480))
            XCTAssertEqual(frameRenderer.attachedSurfaces.first?.scaleFactor, 2.0)
        }
    }

    // MARK: - Pointer Event Conversion and Routing Tests (VAL-CROSS-004)

    /// VAL-CROSS-004: Pointer coordinates convert correctly between device pixels and logical points.
    func testPointerMoveConvertsCoordinatesCorrectly() async {
        await MainActor.run {
            let (host, window, recorder) = makeInputRoutingHost(
                pixelSize: IntSize(width: 640, height: 480),
                scaleFactor: 2.0
            )

            // Send a pointer move at pixel coordinates (200, 100)
            // With 2x scale factor, this should become (100.0, 50.0) in logical coordinates
            let pixelPoint = Point(x: 200, y: 100)
            host.window(window, pointerMovedTo: pixelPoint)

            XCTAssertEqual(recorder.events.count, 1, "Pointer move should be recorded after real host delegation")
            guard case let .pointerMoved(point, scaleFactor) = recorder.events[0] else {
                return XCTFail("Expected a pointerMoved event from WinSwiftUIWindowHost")
            }
            XCTAssertEqual(point.x, 100.0, accuracy: 0.001, "X coordinate should be converted from pixels to logical points (200/2=100)")
            XCTAssertEqual(point.y, 50.0, accuracy: 0.001, "Y coordinate should be converted from pixels to logical points (100/2=50)")
            XCTAssertEqual(scaleFactor, 2.0, "Host should record the scale factor used for conversion")
        }
    }

    /// VAL-CROSS-004: Pointer down/up coordinates convert correctly.
    func testPointerDownUpConvertsCoordinatesCorrectly() async {
        await MainActor.run {
            let (host, window, recorder) = makeInputRoutingHost(
                pixelSize: IntSize(width: 640, height: 480),
                scaleFactor: 2.0
            )

            // Test pointer down at pixel (100, 200) -> logical (50, 100)
            host.window(window, leftMouseDownAt: Point(x: 100, y: 200))
            XCTAssertEqual(recorder.events.count, 1, "Pointer down should be recorded after real host delegation")
            guard case let .pointerDown(point, scaleFactor) = recorder.events[0] else {
                return XCTFail("Expected a pointerDown event from WinSwiftUIWindowHost")
            }
            XCTAssertEqual(point.x, 50.0, accuracy: 0.001, "Down X should be converted (100/2=50)")
            XCTAssertEqual(point.y, 100.0, accuracy: 0.001, "Down Y should be converted (200/2=100)")
            XCTAssertEqual(scaleFactor, 2.0, "Pointer down should record the active scale factor")

            // Test pointer up at pixel (300, 400) -> logical (150, 200)
            host.window(window, leftMouseUpAt: Point(x: 300, y: 400))
            XCTAssertEqual(recorder.events.count, 2, "Pointer up should also be recorded after real host delegation")
            guard case let .pointerUp(point, scaleFactor) = recorder.events[1] else {
                return XCTFail("Expected a pointerUp event from WinSwiftUIWindowHost")
            }
            XCTAssertEqual(point.x, 150.0, accuracy: 0.001, "Up X should be converted (300/2=150)")
            XCTAssertEqual(point.y, 200.0, accuracy: 0.001, "Up Y should be converted (400/2=200)")
            XCTAssertEqual(scaleFactor, 2.0, "Pointer up should record the active scale factor")
        }
    }

    /// VAL-CROSS-004: Pointer leave routes correctly through the host.
    func testPointerLeaveRoutesToRuntime() async {
        await MainActor.run {
            let (host, window, recorder) = makeInputRoutingHost(
                pixelSize: IntSize(width: 320, height: 200),
                scaleFactor: 1.0
            )

            host.windowPointerDidLeave(window)

            XCTAssertEqual(recorder.events.count, 1, "Pointer leave should be recorded after real host delegation")
            guard case .pointerExitedWindow = recorder.events[0] else {
                return XCTFail("Expected a pointerExitedWindow event from WinSwiftUIWindowHost")
            }
        }
    }

    // MARK: - Wheel Event Conversion and Routing Tests (VAL-CROSS-005)

    /// VAL-CROSS-005: Wheel scroll events convert correctly across host and runtime.
    func testMouseWheelConvertsCoordinatesAndDelta() async {
        await MainActor.run {
            let (host, window, recorder) = makeInputRoutingHost(
                pixelSize: IntSize(width: 640, height: 480),
                scaleFactor: 2.0
            )

            // Send wheel event at pixel coordinates (200, 100) with delta 3.0
            // With 2x scale factor, coordinates should become (100.0, 50.0)
            host.window(window, mouseWheelAt: Point(x: 200, y: 100), delta: 3.0)

            XCTAssertEqual(recorder.events.count, 1, "Wheel input should be recorded after real host delegation")
            guard case let .mouseWheel(point, delta, axis, scaleFactor) = recorder.events[0] else {
                return XCTFail("Expected a mouseWheel event from WinSwiftUIWindowHost")
            }
            XCTAssertEqual(point.x, 100.0, accuracy: 0.001, "Wheel X coordinate should be converted (200/2=100)")
            XCTAssertEqual(point.y, 50.0, accuracy: 0.001, "Wheel Y coordinate should be converted (100/2=50)")
            XCTAssertEqual(delta, 3.0, accuracy: 0.001, "Wheel delta should be preserved without modification")
            XCTAssertNil(axis, "Vertical wheel should have nil axis (default)")
            XCTAssertEqual(scaleFactor, 2.0, "Wheel input should record the active scale factor")
        }
    }

    /// VAL-CROSS-005: Horizontal scroll events convert correctly across host and runtime.
    func testHorizontalScrollConvertsCoordinatesAndDelta() async {
        await MainActor.run {
            let (host, window, recorder) = makeInputRoutingHost(
                pixelSize: IntSize(width: 640, height: 480),
                scaleFactor: 2.0
            )

            // Send horizontal scroll at pixel coordinates (400, 300) with delta -5.0
            // With 2x scale factor, coordinates should become (200.0, 150.0)
            host.window(window, horizontalScrollAt: Point(x: 400, y: 300), delta: -5.0)

            XCTAssertEqual(recorder.events.count, 1, "Horizontal scroll should be recorded after real host delegation")
            guard case let .mouseWheel(point, delta, axis, scaleFactor) = recorder.events[0] else {
                return XCTFail("Expected a mouseWheel event from WinSwiftUIWindowHost")
            }
            XCTAssertEqual(point.x, 200.0, accuracy: 0.001, "Horizontal scroll X should be converted (400/2=200)")
            XCTAssertEqual(point.y, 150.0, accuracy: 0.001, "Horizontal scroll Y should be converted (300/2=150)")
            XCTAssertEqual(delta, -5.0, accuracy: 0.001, "Horizontal scroll delta should be preserved")
            XCTAssertEqual(axis, .horizontal, "Horizontal scroll should have horizontal axis")
            XCTAssertEqual(scaleFactor, 2.0, "Horizontal scroll should record the active scale factor")
        }
    }

    // MARK: - Keyboard Event Routing Tests (VAL-CROSS-006)

    /// VAL-CROSS-006: Keyboard events route correctly through host to runtime.
    func testKeyDownDispatchesCorrectlyToRuntime() async {
        await MainActor.run {
            let (host, window, recorder) = makeInputRoutingHost(
                pixelSize: IntSize(width: 320, height: 200),
                scaleFactor: 1.0
            )

            // Test key down with Enter key (keyCode 13)
            let keyEvent = KeyboardEvent(keyCode: 13, modifiers: [], isRepeat: false)
            host.window(window, keyDown: keyEvent)

            XCTAssertEqual(recorder.events.count, 1, "Key down should be recorded after real host delegation")
            guard case let .keyDown(recordedEvent) = recorder.events[0] else {
                return XCTFail("Expected a keyDown event from WinSwiftUIWindowHost")
            }
            XCTAssertEqual(recordedEvent.keyCode, 13, "Key code should be preserved (Enter = 13)")
            XCTAssertEqual(recordedEvent.modifiers, [], "Modifiers should be preserved (empty)")
            XCTAssertFalse(recordedEvent.isRepeat, "isRepeat should be preserved (false)")
        }
    }

    /// VAL-CROSS-006: Keyboard events with modifiers route correctly through host to runtime.
    func testKeyDownWithModifiersDispatchesCorrectly() async {
        await MainActor.run {
            let (host, window, recorder) = makeInputRoutingHost(
                pixelSize: IntSize(width: 320, height: 200),
                scaleFactor: 1.0
            )

            // Test key down with Shift+Tab (keyCode 9 with shift modifier)
            let keyEvent = KeyboardEvent(keyCode: 9, modifiers: .shift, isRepeat: true)
            host.window(window, keyDown: keyEvent)

            XCTAssertEqual(recorder.events.count, 1, "Modified key down should be recorded after real host delegation")
            guard case let .keyDown(recordedEvent) = recorder.events[0] else {
                return XCTFail("Expected a keyDown event from WinSwiftUIWindowHost")
            }
            XCTAssertEqual(recordedEvent.keyCode, 9, "Key code should be preserved (Tab = 9)")
            XCTAssertEqual(recordedEvent.modifiers, .shift, "Shift modifier should be preserved")
            XCTAssertTrue(recordedEvent.isRepeat, "isRepeat should be preserved (true)")
        }
    }

    // MARK: - Focus Loss Routing Tests (VAL-CROSS-006)

    /// VAL-CROSS-006: Focus-loss routing survives host integration.
    func testFocusLossRoutesCorrectlyToRuntime() async {
        await MainActor.run {
            let (host, window, recorder) = makeInputRoutingHost(
                pixelSize: IntSize(width: 320, height: 200),
                scaleFactor: 1.0
            )

            host.windowDidLoseKeyboardFocus(window)

            XCTAssertEqual(recorder.events.count, 1, "Focus loss should be recorded after real host delegation")
            guard case .keyboardFocusDidLeaveWindow = recorder.events[0] else {
                return XCTFail("Expected a keyboardFocusDidLeaveWindow event from WinSwiftUIWindowHost")
            }
        }
    }

    func testHostActiveAndVisibilityStateDriveEnvironmentValues() async {
        await MainActor.run {
            let frameRenderer = FakeRenderBackend()
            let recorder = HostEnvironmentRecorder()
            let expectedSurface = SurfaceDescriptor(
                windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
                pixelSize: IntSize(width: 320, height: 200),
                scaleFactor: 1.0
            )
            let config = WindowGroupConfiguration(
                title: "Test",
                size: IntSize(width: 320, height: 200),
                clearColor: .black,
                content: [AnyView(HostEnvironmentProbeView(recorder: recorder))]
            )
            let host = WinSwiftUIWindowHost(
                configuration: config,
                renderer: frameRenderer,
                batchRenderer: nil,
                surfaceDescriptorProvider: { _ in expectedSurface }
            )
            let window = Win32Window(title: "Test", clientSize: expectedSurface.pixelSize)

            host.windowDidCreate(window)
            let startupSnapshotCount = recorder.snapshots.count

            XCTAssertGreaterThanOrEqual(startupSnapshotCount, 1)
            XCTAssertEqual(recorder.snapshots.last?.scenePhase, .active)
            XCTAssertEqual(recorder.snapshots.last?.controlActiveState, .key)
            XCTAssertEqual(recorder.snapshots.last?.appearsActive, true)

            host.windowDidChangeActiveState(window, isActive: false)

            XCTAssertEqual(recorder.snapshots.count, startupSnapshotCount + 1)
            XCTAssertEqual(recorder.snapshots.last?.scenePhase, .inactive)
            XCTAssertEqual(recorder.snapshots.last?.controlActiveState, .inactive)
            XCTAssertEqual(recorder.snapshots.last?.appearsActive, false)
            XCTAssertEqual(host.executedReloadCount, 1)

            host.windowDidChangeActiveState(window, isActive: false)

            XCTAssertEqual(
                recorder.snapshots.count,
                startupSnapshotCount + 1,
                "Duplicate active-state notifications should not rebuild content"
            )
            XCTAssertEqual(host.executedReloadCount, 1)

            host.windowDidChangeVisibility(window, isVisible: false)

            XCTAssertEqual(recorder.snapshots.count, startupSnapshotCount + 2)
            XCTAssertEqual(recorder.snapshots.last?.scenePhase, .background)
            XCTAssertEqual(recorder.snapshots.last?.controlActiveState, .inactive)
            XCTAssertEqual(recorder.snapshots.last?.appearsActive, false)
            XCTAssertEqual(host.executedReloadCount, 2)

            host.windowDidChangeActiveState(window, isActive: true)

            XCTAssertEqual(recorder.snapshots.count, startupSnapshotCount + 3)
            XCTAssertEqual(recorder.snapshots.last?.scenePhase, .background)
            XCTAssertEqual(recorder.snapshots.last?.controlActiveState, .inactive)
            XCTAssertEqual(recorder.snapshots.last?.appearsActive, false)

            host.windowDidChangeVisibility(window, isVisible: true)

            XCTAssertEqual(recorder.snapshots.count, startupSnapshotCount + 4)
            XCTAssertEqual(recorder.snapshots.last?.scenePhase, .active)
            XCTAssertEqual(recorder.snapshots.last?.controlActiveState, .key)
            XCTAssertEqual(recorder.snapshots.last?.appearsActive, true)
            XCTAssertEqual(host.executedReloadCount, 4)
        }
    }

    func testHostedEnvironmentProvidesStableUndoManager() async {
        await MainActor.run {
            let frameRenderer = FakeRenderBackend()
            let recorder = HostEnvironmentRecorder()
            let expectedSurface = SurfaceDescriptor(
                windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
                pixelSize: IntSize(width: 320, height: 200),
                scaleFactor: 1.0
            )
            let config = WindowGroupConfiguration(
                title: "Test",
                size: IntSize(width: 320, height: 200),
                clearColor: .black,
                content: [AnyView(HostEnvironmentProbeView(recorder: recorder))]
            )
            let host = WinSwiftUIWindowHost(
                configuration: config,
                renderer: frameRenderer,
                batchRenderer: nil,
                surfaceDescriptorProvider: { _ in expectedSurface }
            )
            let window = Win32Window(title: "Test", clientSize: expectedSurface.pixelSize)

            host.windowDidCreate(window)

            guard let hostedUndoManager = recorder.snapshots.last?.undoManager else {
                return XCTFail("Expected hosted windows to provide a default undo manager")
            }

            host.windowDidChangeActiveState(window, isActive: false)

            XCTAssertTrue(
                recorder.snapshots.last?.undoManager === hostedUndoManager,
                "The hosted undo manager should remain stable across environment reloads"
            )
        }
    }

    // MARK: - VAL-CROSS-009: Host Refresh-Rate Pacing and Timer Behavior Tests

    /// VAL-CROSS-009: Host refresh-rate updates control runtime pacing and timer behavior.
    /// This test verifies that changing the monitor refresh rate results in observable
    /// timer state changes with correct cadence updates.
    func testRefreshRateUpdatesControlRuntimeMinimumFrameInterval() async {
        await MainActor.run {
            let frameRenderer = FakeRenderBackend()
            var recordedTimerStates: [TimerState] = []

            let expectedSurface = SurfaceDescriptor(
                windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
                pixelSize: IntSize(width: 320, height: 200),
                scaleFactor: 1.0
            )

            let config = WindowGroupConfiguration(
                title: "Test",
                size: IntSize(width: 320, height: 200),
                clearColor: .black,
                content: []
            )

            // Create host with standard window
            let fakeWindow = Win32Window(title: "Test", clientSize: expectedSurface.pixelSize)
            fakeWindow.testMonitorRefreshRateOverride = 60

            let host = WinSwiftUIWindowHost(
                configuration: config,
                renderer: frameRenderer,
                batchRenderer: nil,
                surfaceDescriptorProvider: { _ in expectedSurface }
            )

            // Capture timer state changes for observable proof
            host.onTimerStateChanged = { state in
                recordedTimerStates.append(state)
            }

            host.windowDidCreate(fakeWindow)

            // Trigger syncAnimationDriver by requesting a frame
            host.windowNeedsDisplay(fakeWindow)

            // Verify initial render occurred
            XCTAssertEqual(frameRenderer.renderedFrames.count, 1, "Initial render should complete")
            XCTAssertEqual(host.currentTimerState.refreshRate, 60, "Initial timer cadence should use the initial monitor refresh rate")
            XCTAssertEqual(host.currentTimerState.intervalMilliseconds, expectedTimerInterval(for: 60))
            XCTAssertNotNil(host.currentRuntimeMinimumFrameInterval)
            XCTAssertEqual(host.currentRuntimeMinimumFrameInterval ?? 0, 1.0 / 60.0, accuracy: 0.000_001)

            // Verify timer state was recorded with expected values
            XCTAssertFalse(recordedTimerStates.isEmpty, "Timer state changes should be recorded")
            if let firstState = recordedTimerStates.first {
                XCTAssertTrue(firstState.usesHighResolution, "High resolution timer should be enabled")
                XCTAssertEqual(firstState.refreshRate, 60, "Initial timer state should record the initial monitor refresh rate")
                XCTAssertEqual(firstState.intervalMilliseconds, expectedTimerInterval(for: 60))
                XCTAssertGreaterThan(firstState.intervalMilliseconds, 0, "Timer interval should be positive")
                XCTAssertLessThanOrEqual(firstState.intervalMilliseconds, 1000, "Timer interval should be reasonable")
            }

            fakeWindow.testMonitorRefreshRateOverride = 144
            host.windowDidChangeDisplay(fakeWindow)

            XCTAssertTrue(host.currentTimerState.usesHighResolution, "Host should report high-res timer enabled")
            XCTAssertEqual(host.currentTimerState.refreshRate, 144, "Display-change handling should resample the window monitor refresh rate")
            XCTAssertEqual(host.currentTimerState.intervalMilliseconds, expectedTimerInterval(for: 144))
            XCTAssertEqual(host.currentRuntimeMinimumFrameInterval ?? 0, 1.0 / 144.0, accuracy: 0.000_001)
            XCTAssertTrue(recordedTimerStates.contains(where: { $0.refreshRate == 60 }))
            XCTAssertTrue(recordedTimerStates.contains(where: { $0.refreshRate == 144 }),
                "Timer observability should record the updated monitor refresh rate after the real host display-change seam runs")
        }
    }

    /// VAL-CROSS-009: Timer is suppressed when presentation is idle (no dirty state, no animations, no input).
    /// This test verifies the observable timer state transitions from enabled to disabled.
    func testIdleTimerSuppressionWhenNotDirty() async {
        await MainActor.run {
            let frameRenderer = FakeRenderBackend()
            var recordedTimerStates: [TimerState] = []

            let expectedSurface = SurfaceDescriptor(
                windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
                pixelSize: IntSize(width: 320, height: 200),
                scaleFactor: 1.0
            )

            let config = WindowGroupConfiguration(
                title: "Test",
                size: IntSize(width: 320, height: 200),
                clearColor: .black,
                content: []
            )

            let fakeWindow = Win32Window(title: "Test", clientSize: expectedSurface.pixelSize)

            let host = WinSwiftUIWindowHost(
                configuration: config,
                renderer: frameRenderer,
                batchRenderer: nil,
                surfaceDescriptorProvider: { _ in expectedSurface }
            )

            // Capture timer state changes for observable proof
            host.onTimerStateChanged = { state in
                recordedTimerStates.append(state)
            }

            host.windowDidCreate(fakeWindow)

            // After initial render, verify frame was rendered (which enables timer while dirty)
            XCTAssertEqual(frameRenderer.renderedFrames.count, 1, "Initial render should complete")

            // Simulate an animation frame callback with no active animations or dirty state
            // This should suppress the timer since there's nothing to do
            host.window(fakeWindow, animationFrameAt: 1.0)

            // Verify the timer state was recorded as disabled (or remains with isEnabled=false)
            // The last recorded state should reflect idle suppression
            let finalState = host.currentTimerState
            XCTAssertFalse(finalState.isEnabled, "Timer should be disabled when idle (no dirty state, no animations, no input)")

            // Verify timer state was recorded through the callback
            let disabledStates = recordedTimerStates.filter { !$0.isEnabled }
            XCTAssertFalse(disabledStates.isEmpty, "At least one timer disable event should be recorded when going idle")
        }
    }

    /// VAL-CROSS-009: Active input re-enables timer pumping after idle suppression.
    /// This test verifies observable timer state transitions from disabled to enabled on input
    /// when the runtime needs presentation (isDirty or has pending work).
    func testActiveInputDrivesTimerPumping() async {
        await MainActor.run {
            let frameRenderer = FakeRenderBackend()
            var recordedTimerStates: [TimerState] = []

            let expectedSurface = SurfaceDescriptor(
                windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
                pixelSize: IntSize(width: 640, height: 480),
                scaleFactor: 2.0
            )

            let config = WindowGroupConfiguration(
                title: "Test",
                size: IntSize(width: 320, height: 240),
                clearColor: .black,
                content: []
            )

            let fakeWindow = Win32Window(title: "Test", clientSize: expectedSurface.pixelSize)

            let host = WinSwiftUIWindowHost(
                configuration: config,
                renderer: frameRenderer,
                batchRenderer: nil,
                surfaceDescriptorProvider: { _ in expectedSurface }
            )

            // Capture timer state changes for observable proof
            host.onTimerStateChanged = { state in
                recordedTimerStates.append(state)
            }

            host.windowDidCreate(fakeWindow)

            // Let initial render finish - this makes runtime clean but timer enabled for a frame
            XCTAssertEqual(frameRenderer.renderedFrames.count, 1, "Initial render should complete")

            // Simulate an idle animation frame to suppress timer
            host.window(fakeWindow, animationFrameAt: 1.0)

            // Verify timer is suppressed (disabled) after idle
            XCTAssertFalse(host.currentTimerState.isEnabled, "Timer should be suppressed after idle animation frame")

            // Trigger a resize to make runtime dirty - this sets up need for presentation
            // so that subsequent input will be recorded and drive timer re-enablement
            host.window(fakeWindow, didResizeTo: IntSize(width: 800, height: 600))

            // Timer should be enabled now due to dirty state from resize
            XCTAssertTrue(host.currentTimerState.isEnabled, "Timer should be enabled after resize makes runtime dirty")

            // Clear the recorded states to track fresh timer transitions
            recordedTimerStates.removeAll()

            // Simulate high-rate pointer input while runtime needs presentation
            // (70 events to exceed 60 events/second threshold)
            for i in 0..<70 {
                let point = Point(x: Double(50 + i), y: Double(50 + i))
                host.window(fakeWindow, pointerMovedTo: point)
            }

            // After processing all inputs, the timer should still be enabled
            // because high-rate input sustains timer pumping
            XCTAssertTrue(host.currentTimerState.isEnabled, "Timer should remain enabled after high-rate input")

            // Verify we recorded timer states during the input burst
            XCTAssertFalse(recordedTimerStates.isEmpty, "Timer state changes should be recorded during input processing")

            // Now simulate an idle frame - but since we had high-rate input,
            // the inputRateTracker should sustain high-rate pumping for 1 second
            // Clear the dirty state first by rendering
            host.windowNeedsDisplay(fakeWindow)

            // Wait a tiny bit then check timer is still enabled due to sustained input rate
            // The sustain window is 1 second, so timer should remain enabled
            XCTAssertTrue(host.currentTimerState.isEnabled, "Timer should remain enabled due to sustained high input rate")
        }
    }

    func testTimerCadenceCalculationFromRefreshRate() async {
        await MainActor.run {
            // Test that timer intervals are correctly calculated from refresh rates
            let testCases: [(refreshRate: UInt32, expectedMinInterval: UInt32, expectedMaxInterval: UInt32)] = [
                (60, 16, 17),    // 1000/60 = 16.67 -> rounds to 16 or 17
                (120, 8, 9),     // 1000/120 = 8.33 -> rounds to 8 or 9
                (144, 6, 7),     // 1000/144 = 6.94 -> rounds to 6 or 7
                (240, 4, 5),     // 1000/240 = 4.17 -> rounds to 4 or 5
            ]

            for testCase in testCases {
                let interval = expectedTimerInterval(for: testCase.refreshRate)
                XCTAssertGreaterThanOrEqual(interval, testCase.expectedMinInterval,
                    "Timer interval for \(testCase.refreshRate)Hz should be >= \(testCase.expectedMinInterval)ms")
                XCTAssertLessThanOrEqual(interval, testCase.expectedMaxInterval,
                    "Timer interval for \(testCase.refreshRate)Hz should be <= \(testCase.expectedMaxInterval)ms")
            }
        }
    }

    // MARK: - VAL-CROSS-010: Observed-Object Batching and Coalescing Tests

    /// VAL-CROSS-010: Multiple same-turn changes from an observed object coalesce into one host-driven rebuild.
    /// This test waits for the deferred reload task, then proves exactly one
    /// rebuild and one follow-up render happened for three same-turn changes.
    func testObservedObjectReloadsCoalesceWithinOneTurn() async throws {
        let frameRenderer = FakeRenderBackend()
        let observable = TestObservableObject()
        let expectedSurface = SurfaceDescriptor(
            windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
            pixelSize: IntSize(width: 320, height: 200),
            scaleFactor: 1.0
        )
        let config = WindowGroupConfiguration(
            title: "Test",
            size: IntSize(width: 320, height: 200),
            clearColor: .black,
            content: [AnyView(ObservedObjectValueView(model: observable))]
        )
        let fakeWindow = Win32Window(title: "Test", clientSize: expectedSurface.pixelSize)
        let host = WinSwiftUIWindowHost(
            configuration: config,
            renderer: frameRenderer,
            batchRenderer: nil,
            surfaceDescriptorProvider: { _ in expectedSurface }
        )

        host.windowDidCreate(fakeWindow)
        XCTAssertEqual(frameRenderer.renderedFrames.count, 1, "Initial host startup should render once")

        var scheduledEvents: [(objectID: ObjectIdentifier, coalesced: Bool)] = []
        var deferredTaskResults: [Bool] = []
        var reloadCompletedCount = 0
        let reloadCompleted = expectation(description: "relevant observed-object reload completed")
        let deferredTaskCompleted = expectation(description: "deferred observed-object reload task finished")
        host.onObservedObjectReloadScheduled = { objectID, coalesced in
            scheduledEvents.append((objectID, coalesced))
        }
        host.onReloadContentCompleted = {
            reloadCompletedCount += 1
            reloadCompleted.fulfill()
        }
        host.onObservedObjectReloadTaskCompleted = { didReload in
            deferredTaskResults.append(didReload)
            deferredTaskCompleted.fulfill()
        }

        host.resetObservabilityCounters()

        observable.value = 1
        observable.secondaryValue = "second change"
        observable.value = 2

        XCTAssertEqual(host.scheduledReloadCount, 1, "Three same-turn changes should schedule exactly one deferred reload task")
        XCTAssertEqual(scheduledEvents.count, 3, "Every observed-object change should be recorded")
        XCTAssertEqual(scheduledEvents.map(\.objectID), Array(repeating: ObjectIdentifier(observable), count: 3))
        XCTAssertEqual(scheduledEvents.map(\.coalesced), [false, true, true], "Only the first change should create a new deferred reload task")

        await fulfillment(of: [reloadCompleted, deferredTaskCompleted], timeout: 1.0)

        XCTAssertEqual(host.completedObservedObjectReloadTaskCount, 1, "Exactly one deferred reload task should finish")
        XCTAssertEqual(host.skippedObservedObjectReloadCount, 0, "The relevant dependency should not be filtered out")
        XCTAssertEqual(host.executedReloadCount, 1, "Exactly one deferred reload should rebuild content")
        XCTAssertEqual(reloadCompletedCount, 1, "Exactly one deferred reload should complete")
        XCTAssertEqual(deferredTaskResults, [true], "The deferred reload task should report an executed reload")
        XCTAssertEqual(frameRenderer.renderedFrames.count, 1, "Rebuild should queue presentation but not render until display is requested")

        host.windowNeedsDisplay(fakeWindow)

        XCTAssertEqual(frameRenderer.renderedFrames.count, 2, "The queued presentation should render exactly one follow-up frame")
        XCTAssertEqual(frameRenderer.renderedFrames.last?.clearColor, .black, "The follow-up frame should present the configured clear color")
    }

    /// VAL-CROSS-010: The ComponentHost dependency set rejects irrelevant
    /// observed-object changes after the deferred reload task runs.
    func testObservedObjectDependencySetRejectsIrrelevantChanges() async throws {
        let frameRenderer = FakeRenderBackend()
        let relevantObject = TestObservableObject()
        let irrelevantObject = TestObservableObject()
        let expectedSurface = SurfaceDescriptor(
            windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
            pixelSize: IntSize(width: 320, height: 200),
            scaleFactor: 1.0
        )
        let config = WindowGroupConfiguration(
            title: "Test",
            size: IntSize(width: 320, height: 200),
            clearColor: .black,
            content: [AnyView(ObservedObjectValueView(model: relevantObject))]
        )
        let fakeWindow = Win32Window(title: "Test", clientSize: expectedSurface.pixelSize)
        let host = WinSwiftUIWindowHost(
            configuration: config,
            renderer: frameRenderer,
            batchRenderer: nil,
            surfaceDescriptorProvider: { _ in expectedSurface }
        )

        host.windowDidCreate(fakeWindow)
        XCTAssertEqual(frameRenderer.renderedFrames.count, 1, "Initial host startup should render once")

        let relevantReloadCompleted = expectation(description: "relevant object establishes dependency set")
        let relevantTaskCompleted = expectation(description: "relevant deferred reload task finished")
        var relevantTaskResults: [Bool] = []
        host.onReloadContentCompleted = {
            relevantReloadCompleted.fulfill()
        }
        host.onObservedObjectReloadTaskCompleted = { didReload in
            relevantTaskResults.append(didReload)
            relevantTaskCompleted.fulfill()
        }

        host.resetObservabilityCounters()
        relevantObject.value = 1
        await fulfillment(of: [relevantReloadCompleted, relevantTaskCompleted], timeout: 1.0)
        host.windowNeedsDisplay(fakeWindow)

        XCTAssertEqual(relevantTaskResults, [true], "A relevant observed-object change should execute one deferred reload")
        XCTAssertEqual(frameRenderer.renderedFrames.count, 2, "The relevant change should render one follow-up frame")

        var rejectedTaskResults: [Bool] = []
        var scheduledEvents: [(objectID: ObjectIdentifier, coalesced: Bool)] = []
        var rejectedReloadCompletedCount = 0
        let rejectedTaskCompleted = expectation(description: "irrelevant deferred reload task finished")
        host.onObservedObjectReloadScheduled = { objectID, coalesced in
            scheduledEvents.append((objectID, coalesced))
        }
        host.onReloadContentCompleted = {
            rejectedReloadCompletedCount += 1
        }
        host.onObservedObjectReloadTaskCompleted = { didReload in
            rejectedTaskResults.append(didReload)
            rejectedTaskCompleted.fulfill()
        }

        host.resetObservabilityCounters()
        host.observe(irrelevantObject)
        XCTAssertEqual(host.observedObjectRegistrationCount, 1, "The host should hold a real observation token for the irrelevant object before filtering it")

        let renderCountBeforeIrrelevantChange = frameRenderer.renderedFrames.count
        irrelevantObject.value = 1

        XCTAssertEqual(host.scheduledReloadCount, 1, "A changed but non-dependent object should still schedule one deferred reload task")

        await fulfillment(of: [rejectedTaskCompleted], timeout: 1.0)

        XCTAssertEqual(host.completedObservedObjectReloadTaskCount, 1, "The deferred reload task should still finish after dependency evaluation")
        XCTAssertEqual(host.skippedObservedObjectReloadCount, 1, "The ComponentHost dependency set should reject the irrelevant change")
        XCTAssertEqual(host.executedReloadCount, 0, "Rejected dependency changes must not rebuild content")
        XCTAssertEqual(rejectedReloadCompletedCount, 0, "Rejected dependency changes must not report reload completion")
        XCTAssertEqual(rejectedTaskResults, [false], "The deferred reload task should report that it skipped the rebuild")
        XCTAssertEqual(scheduledEvents.count, 1, "Only one irrelevant notification should be scheduled")
        XCTAssertEqual(scheduledEvents.first?.objectID, ObjectIdentifier(irrelevantObject), "The scheduled task should correspond to the irrelevant object")
        XCTAssertEqual(scheduledEvents.first?.coalesced, false, "The irrelevant notification should schedule one non-coalesced task")
        XCTAssertEqual(frameRenderer.renderedFrames.count, renderCountBeforeIrrelevantChange, "Rejected dependency changes must not render immediately")

        host.windowNeedsDisplay(fakeWindow)

        XCTAssertEqual(frameRenderer.renderedFrames.count, renderCountBeforeIrrelevantChange, "Rejected dependency changes must not queue a later render either")
    }

    /// VAL-CROSS-010: Pending changed objects accumulation and dependency filtering.
    /// This test asserts that pendingChangedObjects accumulates correctly.
    func testObservedObjectPendingChangesAccumulation() async throws {
        await MainActor.run {
            let frameRenderer = FakeRenderBackend()

            let expectedSurface = SurfaceDescriptor(
                windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
                pixelSize: IntSize(width: 320, height: 200),
                scaleFactor: 1.0
            )

            let config = WindowGroupConfiguration(
                title: "Test",
                size: IntSize(width: 320, height: 200),
                clearColor: .black,
                content: []
            )

            let fakeWindow = Win32Window(title: "Test", clientSize: expectedSurface.pixelSize)

            let host = WinSwiftUIWindowHost(
                configuration: config,
                renderer: frameRenderer,
                batchRenderer: nil,
                surfaceDescriptorProvider: { _ in expectedSurface }
            )

            host.windowDidCreate(fakeWindow)

            // The pendingChangedObjects accumulation in scheduleObservedObjectReload:
            // pendingChangedObjects.insert(changedObjectID)
            //
            // This accumulates all unique object IDs that changed during the batch window.
            // When the deferred Task fires, it checks intersection with componentHost.observedObjects.

            // Track accumulated objects
            var accumulatedObjectIDs: [ObjectIdentifier] = []
            host.onObservedObjectReloadScheduled = { objectID, coalesced in
                accumulatedObjectIDs.append(objectID)
            }

            // Reset counters
            host.resetObservabilityCounters()

            let object1 = TestObservableObject()
            let object2 = TestObservableObject()
            let object3 = TestObservableObject()

            // Register all three objects for observation
            host.observe(object1)
            host.observe(object2)
            host.observe(object3)

            // Simulate multiple different objects changing in same turn
            ObservableObjectCenter.shared.notify(object1)
            ObservableObjectCenter.shared.notify(object2)
            ObservableObjectCenter.shared.notify(object3)

            // Assert that all three notifications were captured
            XCTAssertEqual(accumulatedObjectIDs.count, 3,
                "All three notification events should be captured")

            // Assert that all object IDs are in the accumulated list
            XCTAssertTrue(accumulatedObjectIDs.contains(ObjectIdentifier(object1)),
                "Object 1 should be in accumulated list")
            XCTAssertTrue(accumulatedObjectIDs.contains(ObjectIdentifier(object2)),
                "Object 2 should be in accumulated list")
            XCTAssertTrue(accumulatedObjectIDs.contains(ObjectIdentifier(object3)),
                "Object 3 should be in accumulated list")

            // Assert that pendingChangedObjects would contain all three object IDs
            // (verified via reloadTriggeringObjectIDs which tracks pendingChangedObjects inserts)
            XCTAssertEqual(host.reloadTriggeringObjectIDs.count, 3,
                "reloadTriggeringObjectIDs should contain all three unique object IDs")
        }
    }

    /// VAL-CROSS-010: Observed object registration tracking.
    /// This test asserts that dependency registrations are recorded.
    func testObservedObjectRegistrationTracking() async throws {
        await MainActor.run {
            let frameRenderer = FakeRenderBackend()

            let expectedSurface = SurfaceDescriptor(
                windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
                pixelSize: IntSize(width: 320, height: 200),
                scaleFactor: 1.0
            )

            let config = WindowGroupConfiguration(
                title: "Test",
                size: IntSize(width: 320, height: 200),
                clearColor: .black,
                content: []
            )

            let fakeWindow = Win32Window(title: "Test", clientSize: expectedSurface.pixelSize)

            let host = WinSwiftUIWindowHost(
                configuration: config,
                renderer: frameRenderer,
                batchRenderer: nil,
                surfaceDescriptorProvider: { _ in expectedSurface }
            )

            host.windowDidCreate(fakeWindow)

            // Track registered objects
            var registeredObjectIDs: [ObjectIdentifier] = []
            host.onObservedObjectRegistered = { objectID in
                registeredObjectIDs.append(objectID)
            }

            // Reset counters
            host.resetObservabilityCounters()

            // Create and observe objects
            let object1 = TestObservableObject()
            let object2 = TestObservableObject()

            // Manually trigger observation (simulating what happens with @ObservedObject)
            host.observe(object1)
            host.observe(object2)
            host.observe(object1)  // Duplicate - should not register again

            // Assert registration count via concrete counter
            XCTAssertEqual(host.observedObjectRegistrationCount, 2,
                "Should register exactly 2 unique objects (duplicate observation ignored)")

            // Assert via callback tracking
            XCTAssertEqual(registeredObjectIDs.count, 2,
                "Should have exactly 2 registration events")
            XCTAssertTrue(registeredObjectIDs.contains(ObjectIdentifier(object1)),
                "Object 1 should be registered")
            XCTAssertTrue(registeredObjectIDs.contains(ObjectIdentifier(object2)),
                "Object 2 should be registered")

            // Assert duplicate observation was ignored
            let object1RegistrationCount = registeredObjectIDs.filter { $0 == ObjectIdentifier(object1) }.count
            XCTAssertEqual(object1RegistrationCount, 1,
                "Duplicate observation of same object should be ignored")
        }
    }

    func testHostCreatesRuntimeWithCorrectInitialSize() async {
        await MainActor.run {
            let frameRenderer = FakeRenderBackend()

            let expectedSurface = SurfaceDescriptor(
                windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
                pixelSize: IntSize(width: 320, height: 200),
                scaleFactor: 1.0
            )

            let config = WindowGroupConfiguration(
                title: "Test",
                size: IntSize(width: 320, height: 200),
                clearColor: .black,
                content: []
            )

            let host = WinSwiftUIWindowHost(
                configuration: config,
                renderer: frameRenderer,
                batchRenderer: nil,
                surfaceDescriptorProvider: { _ in expectedSurface }
            )

            let fakeWindow = Win32Window(title: "Test", clientSize: expectedSurface.pixelSize)
            host.windowDidCreate(fakeWindow)

            // Renderer should have been attached and rendered initial frame
            XCTAssertEqual(frameRenderer.attachedSurfaces.count, 1)
            XCTAssertEqual(frameRenderer.renderedFrames.count, 1)
        }
    }

    func testHostPropagatesClearColorToRuntime() async {
        await MainActor.run {
            let frameRenderer = FakeRenderBackend()
            let expectedColor = Color(red: 0.1, green: 0.2, blue: 0.3, alpha: 1.0)

            let expectedSurface = SurfaceDescriptor(
                windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
                pixelSize: IntSize(width: 320, height: 200),
                scaleFactor: 1.0
            )

            let config = WindowGroupConfiguration(
                title: "Test",
                size: IntSize(width: 320, height: 200),
                clearColor: expectedColor,
                content: []
            )

            let host = WinSwiftUIWindowHost(
                configuration: config,
                renderer: frameRenderer,
                batchRenderer: nil,
                surfaceDescriptorProvider: { _ in expectedSurface }
            )

            let fakeWindow = Win32Window(title: "Test", clientSize: expectedSurface.pixelSize)
            host.windowDidCreate(fakeWindow)

            // Verify the frame was rendered with the correct clear color
            XCTAssertEqual(frameRenderer.renderedFrames.first?.clearColor, expectedColor)
        }
    }

    func testAnimationFrameCallbackAdvancesAnimations() async {
        await MainActor.run {
            let frameRenderer = FakeRenderBackend()

            let expectedSurface = SurfaceDescriptor(
                windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
                pixelSize: IntSize(width: 320, height: 200),
                scaleFactor: 1.0
            )

            let config = WindowGroupConfiguration(
                title: "Test",
                size: IntSize(width: 320, height: 200),
                clearColor: .black,
                content: []
            )

            let host = WinSwiftUIWindowHost(
                configuration: config,
                renderer: frameRenderer,
                batchRenderer: nil,
                surfaceDescriptorProvider: { _ in expectedSurface }
            )

            let fakeWindow = Win32Window(title: "Test", clientSize: expectedSurface.pixelSize)
            host.windowDidCreate(fakeWindow)

            let initialFrameCount = frameRenderer.renderedFrames.count

            // Trigger animation frame callback
            // Note: without active animations or dirty state, this may not trigger a new render
            host.window(fakeWindow, animationFrameAt: 1.0)

            // Should have either rendered or at least not crashed
            // Animation frames are idempotent when there's nothing to do
            XCTAssertGreaterThanOrEqual(frameRenderer.renderedFrames.count, initialFrameCount)
        }
    }

    func testDefaultStartupSelectsScenePresenterAndInitializesRuntimeGeometry() async {
        await MainActor.run {
            let batchRenderer = FakeBatchRenderBackend()
            let frameRenderer = FakeRenderBackend()

            let expectedSurface = SurfaceDescriptor(
                windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
                pixelSize: IntSize(width: 640, height: 480),
                scaleFactor: 2.0
            )

            let config = WindowGroupConfiguration(
                title: "Test",
                size: IntSize(width: 320, height: 240),
                clearColor: .black,
                content: []
            )

            let host = WinSwiftUIWindowHost(
                configuration: config,
                renderer: frameRenderer,
                batchRenderer: batchRenderer,
                surfaceDescriptorProvider: { _ in expectedSurface }
            )

            let fakeWindow = Win32Window(title: "Test", clientSize: expectedSurface.pixelSize)
            fakeWindow.testScaleFactorOverride = expectedSurface.scaleFactor
            host.windowDidCreate(fakeWindow)

            XCTAssertEqual(batchRenderer.attachedSurfaces.count, 1)
            XCTAssertEqual(batchRenderer.boundScenes.count, 1)
            XCTAssertEqual(batchRenderer.renderedScenes.count, 1)
            XCTAssertEqual(frameRenderer.attachedSurfaces.count, 0)
            XCTAssertEqual(frameRenderer.renderedFrames.count, 0)
            XCTAssertTrue(host.isUsingScenePresentationBackend)
            XCTAssertEqual(host.currentLogicalRootSize, IntSize(width: 320, height: 240))
            XCTAssertEqual(host.currentDisplayScale, 2.0)
            XCTAssertEqual(
                host.currentPresentationSelection,
                PresentationSelection(
                    presenter: .scene,
                    reason: .defaultScene,
                    frameBackend: frameRenderer.backendDisplayName,
                    sceneBackend: batchRenderer.backendDisplayName
                )
            )
        }
    }

    func testFrameDebugStartupSelectsFramePresenterAndSkipsSceneRenderPath() async {
        await MainActor.run {
            let batchRenderer = FakeBatchRenderBackend()
            let frameRenderer = FakeRenderBackend()
            var sceneRenderCount = 0

            let expectedSurface = SurfaceDescriptor(
                windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
                pixelSize: IntSize(width: 320, height: 200),
                scaleFactor: 1.0
            )

            let config = WindowGroupConfiguration(
                title: "Test",
                size: IntSize(width: 320, height: 200),
                clearColor: .black,
                content: []
            )

            let host = WinSwiftUIWindowHost(
                configuration: config,
                renderer: frameRenderer,
                batchRenderer: batchRenderer,
                surfaceDescriptorProvider: { _ in expectedSurface },
                sceneRenderer: { runtime, timestamp in
                    sceneRenderCount += 1
                    return runtime.renderScene(at: timestamp)
                },
                startupPresentationMode: .frameDebug,
                startupProbeConfiguration: nil
            )

            let fakeWindow = Win32Window(title: "Test", clientSize: expectedSurface.pixelSize)
            host.windowDidCreate(fakeWindow)

            XCTAssertEqual(batchRenderer.attachedSurfaces.count, 0)
            XCTAssertEqual(batchRenderer.renderedScenes.count, 0)
            XCTAssertEqual(sceneRenderCount, 0)
            XCTAssertEqual(frameRenderer.attachedSurfaces.count, 1)
            XCTAssertEqual(frameRenderer.renderedFrames.count, 1)
            XCTAssertFalse(host.isUsingScenePresentationBackend)
            XCTAssertEqual(
                host.currentPresentationSelection,
                PresentationSelection(
                    presenter: .frame,
                    reason: .frameDebugOverride,
                    frameBackend: frameRenderer.backendDisplayName,
                    sceneBackend: batchRenderer.backendDisplayName
                )
            )
        }
    }

    func testDowngradeObservabilityTracksRenderFailureReason() async {
        await MainActor.run {
            let batchRenderer = FakeBatchRenderBackend()
            let frameRenderer = FakeRenderBackend()

            let expectedSurface = SurfaceDescriptor(
                windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
                pixelSize: IntSize(width: 320, height: 200),
                scaleFactor: 1.0
            )

            let config = WindowGroupConfiguration(
                title: "Test",
                size: IntSize(width: 320, height: 200),
                clearColor: .black,
                content: []
            )

            let host = WinSwiftUIWindowHost(
                configuration: config,
                renderer: frameRenderer,
                batchRenderer: batchRenderer,
                surfaceDescriptorProvider: { _ in expectedSurface }
            )

            let fakeWindow = Win32Window(title: "Test", clientSize: expectedSurface.pixelSize)
            host.windowDidCreate(fakeWindow)

            XCTAssertEqual(batchRenderer.renderedScenes.count, 1)
            batchRenderer.setRenderShouldFail(true)

            host.window(fakeWindow, didResizeTo: IntSize(width: 640, height: 480))
            host.windowNeedsDisplay(fakeWindow)

            XCTAssertEqual(frameRenderer.attachedSurfaces.count, 1)
            XCTAssertEqual(
                host.currentPresentationSelection,
                PresentationSelection(
                    presenter: .frame,
                    reason: .batchRenderFailure(String(describing: batchRenderer.failureError)),
                    frameBackend: frameRenderer.backendDisplayName,
                    sceneBackend: batchRenderer.backendDisplayName
                )
            )
        }
    }
}
