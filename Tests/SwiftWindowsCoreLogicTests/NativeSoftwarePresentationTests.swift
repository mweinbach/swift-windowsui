import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import WinSwiftUI

/// Exercises the native backend with a local blitter fake. The opaque handle
/// is only a value handed to that fake; these tests never call GDI or create HWNDs.
@MainActor
final class NativeSoftwarePresentationTests: XCTestCase {
    private func surface(size: IntSize = IntSize(width: 8, height: 6)) -> SurfaceDescriptor {
        SurfaceDescriptor(
            windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 1))!,
            pixelSize: size, scaleFactor: 1)
    }

    func testSceneSubmissionCarriesTheRawRasterizerPixels() async throws {
        let presenter = RecordingNativeBitmapPresenter()
        let backend = NativeSoftwareWindowRenderBackend(presenter: presenter)
        let surface = surface()
        try backend.attach(to: surface, path: .scene)
        var scene = GPUIScene(clearColor: .black)
        scene.addQuad(
            QuadPrimitive(
                x: 1, y: 1, width: 5, height: 4,
                startR: 0, startG: 1, startB: 0, startA: 1,
                endR: 0, endG: 1, endB: 0, endA: 1))
        scene.addQuad(
            QuadPrimitive(
                x: 2, y: 2, width: 2, height: 2,
                startR: 1, startG: 0, startB: 0, startA: 1,
                endR: 1, endG: 0, endB: 0, endA: 1))

        try backend.render(scene: scene)

        XCTAssertEqual(presenter.bitmaps, [GPUIRawSceneRasterizer.rasterize(scene, size: surface.pixelSize)])
        XCTAssertEqual(presenter.sizes, [surface.pixelSize])
        let snapshot = backend.takeSnapshot()
        XCTAssertEqual(snapshot.lastFrameSubmission?.outcome, .submitted)
        XCTAssertEqual(snapshot.lastFrameSubmission?.gpuTimingStatus, .unsupported)
        XCTAssertNil(snapshot.lastFrameSubmission?.id, "A CPU blit must not invent a GPU device identity.")
        XCTAssertNil(snapshot.backendDiagnostics)
        XCTAssertTrue(backend.detach().isDetached)
    }

    func testFrameLoweringMatchesTheExistingCPUReferencePath() async throws {
        let presenter = RecordingNativeBitmapPresenter()
        let backend = NativeSoftwareWindowRenderBackend(presenter: presenter)
        let surface = surface()
        try backend.attach(to: surface, path: .frame)
        let frame = RenderFrame(
            clearColor: .black,
            commands: [
                .fillRect(
                    FillRectCommand(
                        rect: Rect(x: 1, y: 1, width: 4, height: 3),
                        color: Color(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)))
            ])
        let reference = CPUBatchRenderer()
        try reference.attach(to: SurfaceDescriptor(offscreenPixelSize: surface.pixelSize))

        try reference.render(frame: frame)
        try backend.render(frame: frame)

        XCTAssertEqual(presenter.bitmaps.last, reference.lastRenderedBitmap)
        XCTAssertEqual(backend.takeSnapshot().lastFrameSubmission?.outcome, .submitted)
        XCTAssertTrue(backend.detach().isDetached)
        reference.detach()
    }

    func testBlitFailureDoesNotKeepThePreviousSubmission() async throws {
        let presenter = RecordingNativeBitmapPresenter()
        let backend = NativeSoftwareWindowRenderBackend(presenter: presenter)
        try backend.attach(to: surface(), path: .scene)
        try backend.render(scene: GPUIScene(clearColor: .black))
        XCTAssertEqual(backend.takeSnapshot().lastFrameSubmission?.outcome, .submitted)
        presenter.failure = NativeSoftwareTestError(code: -7)

        XCTAssertThrowsError(try backend.render(scene: GPUIScene(clearColor: .white))) { error in
            XCTAssertEqual(error as? NativeSoftwareTestError, NativeSoftwareTestError(code: -7))
            XCTAssertEqual(PresentationFailureKind.classifying(error), .permanent)
        }

        XCTAssertEqual(presenter.bitmaps.count, 1)
        XCTAssertEqual(backend.takeSnapshot().lastFrameSubmission?.outcome, .failed)
        XCTAssertTrue(backend.detach().isDetached)
    }

    func testResizeChangesRasterAndBlitSize() async throws {
        let presenter = RecordingNativeBitmapPresenter()
        let backend = NativeSoftwareWindowRenderBackend(presenter: presenter)
        try backend.attach(to: surface(), path: .scene)
        let resized = surface(size: IntSize(width: 5, height: 3))

        try backend.resize(to: resized)
        try backend.render(scene: GPUIScene(clearColor: .black))

        XCTAssertEqual(presenter.bitmaps.last?.width, 5)
        XCTAssertEqual(presenter.bitmaps.last?.height, 3)
        XCTAssertEqual(presenter.sizes.last, resized.pixelSize)
        XCTAssertTrue(backend.detach().isDetached)
    }

    func testDetachClearsAttachmentAndDoesNotReportAnotherSubmission() async throws {
        let presenter = RecordingNativeBitmapPresenter()
        let backend = NativeSoftwareWindowRenderBackend(presenter: presenter)
        try backend.attach(to: surface(), path: .scene)
        try backend.render(scene: GPUIScene(clearColor: .black))

        XCTAssertTrue(backend.detach().isDetached)
        XCTAssertTrue(backend.detach().isDetached)
        let detached = backend.takeSnapshot()
        XCTAssertFalse(detached.isAttached)
        XCTAssertNil(detached.lastFrameSubmission)
        XCTAssertThrowsError(try backend.render(scene: GPUIScene(clearColor: .black)))
        XCTAssertEqual(backend.takeSnapshot().lastFrameSubmission?.outcome, .skipped)
        XCTAssertEqual(presenter.bitmaps.count, 1)
    }

    func testConfigurationReturnsOnlyActualRequestedSetterResults() async {
        let backend = NativeSoftwareWindowRenderBackend(presenter: RecordingNativeBitmapPresenter())
        let unsupported = backend.configure(
            NativePresentationConfiguration(
                presentsWithVSync: false, capturesPresentedFrames: true, gpuFrameTimingEnabled: true))
        XCTAssertEqual(unsupported.presentsWithVSyncAccepted, false)
        XCTAssertEqual(unsupported.capturesPresentedFramesAccepted, false)
        XCTAssertEqual(unsupported.gpuFrameTimingEnabledAccepted, false)

        let intervalOnly = backend.configure(NativePresentationConfiguration(displayFrameInterval: 1 / 60))

        XCTAssertNil(intervalOnly.presentsWithVSyncAccepted)
        XCTAssertNil(intervalOnly.capturesPresentedFramesAccepted)
        XCTAssertNil(intervalOnly.gpuFrameTimingEnabledAccepted)
        XCTAssertNil(backend.takeSnapshot().capturedPresentedFrame)
        XCTAssertTrue(backend.takeSnapshot().completedGPUFrameTimings.isEmpty)
    }

    func testOnlyTheWindowSoftwareFactoryOptsIntoNativePresentation() async throws {
        let native = try XCTUnwrap(SoftwareWindowRenderBackendFactory().makeNativePresentationFactory())
        XCTAssertEqual(native.capabilities, .softwareWindow)
        XCTAssertNil(CPURenderBackendFactory().makeNativePresentationFactory())
    }
}

private struct NativeSoftwareTestError: Error, Equatable, ClassifiedPresentationFailure {
    let code: Int32
    var presentationFailureKind: PresentationFailureKind { .permanent }
}

private final class RecordingNativeBitmapPresenter: NativeWindowBitmapPresenter {
    var bitmaps: [BitmapSurface] = []
    var sizes: [IntSize] = []
    var failure: NativeSoftwareTestError?

    func present(_ bitmap: BitmapSurface, to windowHandle: NativeWindowHandle, clientSize: IntSize) throws {
        if let failure { throw failure }
        bitmaps.append(bitmap)
        sizes.append(clientSize)
    }
}
