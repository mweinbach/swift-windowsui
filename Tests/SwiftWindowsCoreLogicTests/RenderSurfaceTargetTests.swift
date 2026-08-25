import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsRendererD3D11
@testable import WinSwiftUI

/// The portable render contract distinguishes a real native window from an
/// offscreen target instead of forcing headless callers to fabricate HWNDs.
@MainActor
final class RenderSurfaceTargetTests: XCTestCase {
    private let size = IntSize(width: 8, height: 6)

    func testExistingWindowInitializerPreservesItsNativeHandle() async throws {
        let handle = try XCTUnwrap(NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 7)))
        let descriptor = SurfaceDescriptor(windowHandle: handle, pixelSize: size, scaleFactor: 2)

        XCTAssertEqual(descriptor.target, .window(handle))
        XCTAssertEqual(descriptor.windowHandle, handle)
        XCTAssertEqual(descriptor.pixelSize, size)
        XCTAssertEqual(descriptor.scaleFactor, 2)
    }

    func testOffscreenSurfaceHasNoNativeWindowHandle() async {
        let descriptor = SurfaceDescriptor(offscreenPixelSize: size, scaleFactor: 1.5)

        XCTAssertEqual(descriptor.target, .offscreen)
        XCTAssertNil(descriptor.windowHandle)
        XCTAssertEqual(descriptor.pixelSize, size)
        XCTAssertEqual(descriptor.scaleFactor, 1.5)
    }

    func testExplicitSurfaceTargetAndHandleMutationStayConsistent() async throws {
        let handle = try XCTUnwrap(NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 9)))
        var descriptor = SurfaceDescriptor(target: .offscreen, pixelSize: size, scaleFactor: 1)

        descriptor.windowHandle = handle
        XCTAssertEqual(descriptor.target, .window(handle))
        XCTAssertEqual(descriptor.windowHandle, handle)

        descriptor.windowHandle = nil
        XCTAssertEqual(descriptor.target, .offscreen)
        XCTAssertNil(descriptor.windowHandle)
    }

    func testCPUSceneRendererAttachesToGenuineOffscreenSurface() async throws {
        let renderer = CPUBatchRenderer()
        let descriptor = SurfaceDescriptor(offscreenPixelSize: size)

        try renderer.attach(to: descriptor)
        try renderer.render(scene: GPUIScene(clearColor: Color(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)))

        let bitmap = try XCTUnwrap(renderer.lastRenderedBitmap)
        XCTAssertEqual(bitmap.width, size.width)
        XCTAssertEqual(bitmap.height, size.height)
        XCTAssertEqual(Array(bitmap.pixels.prefix(4)), [204, 102, 51, 255])
    }

    func testCPUReferenceRejectsNativeWindowSurfacesInsteadOfFakingPresentation() async throws {
        let handle = try XCTUnwrap(NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 13)))
        let surface = SurfaceDescriptor(windowHandle: handle, pixelSize: size, scaleFactor: 1)
        let renderer = CPUBatchRenderer()

        XCTAssertThrowsError(try renderer.attach(to: surface)) { error in
            guard let backendError = error as? CPUBatchRendererError,
                case .unsupportedSurface(let rejectedTarget) = backendError
            else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(rejectedTarget, .window(handle))
            XCTAssertTrue(backendError.description.contains("offscreen"))
            XCTAssertTrue(backendError.description.contains("presenting backend"))
        }
        XCTAssertNil(renderer.lastRenderedBitmap)
        XCTAssertThrowsError(try renderer.render(scene: GPUIScene(clearColor: .white)))
    }

    func testCPUFrameRendererAttachesToGenuineOffscreenSurface() async throws {
        let renderer = CPUBatchRenderer()

        try renderer.attach(to: SurfaceDescriptor(offscreenPixelSize: size, scaleFactor: 2))
        try renderer.render(frame: RenderFrame(clearColor: Color(red: 1, green: 0, blue: 0, alpha: 1)))

        let bitmap = try XCTUnwrap(renderer.lastRenderedBitmap)
        XCTAssertEqual(bitmap.width, size.width)
        XCTAssertEqual(bitmap.height, size.height)
        XCTAssertEqual(Array(bitmap.pixels.prefix(4)), [0, 0, 255, 255])
    }

    func testOffscreenCPURendererCanResizeDetachAndReattach() async throws {
        let renderer = CPUBatchRenderer()
        let resized = IntSize(width: 3, height: 4)

        try renderer.attach(to: SurfaceDescriptor(offscreenPixelSize: size))
        try renderer.resize(to: resized)
        try renderer.render(scene: GPUIScene(clearColor: .white))
        XCTAssertEqual(renderer.lastRenderedBitmap?.width, resized.width)
        XCTAssertEqual(renderer.lastRenderedBitmap?.height, resized.height)

        renderer.detach()
        XCTAssertNil(renderer.lastRenderedBitmap)

        try renderer.attach(to: SurfaceDescriptor(offscreenPixelSize: size))
        try renderer.render(scene: GPUIScene(clearColor: .black))
        XCTAssertEqual(renderer.lastRenderedBitmap?.width, size.width)
        XCTAssertEqual(renderer.lastRenderedBitmap?.height, size.height)
    }

    func testD3D11BatchPresenterRejectsOffscreenSurfaceBeforeCreatingADevice() async {
        let renderer = D3D11BatchRenderer()

        XCTAssertThrowsError(try renderer.attach(to: SurfaceDescriptor(offscreenPixelSize: size))) { error in
            guard let backendError = error as? BatchRendererError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(backendError.operation, "Resolve HWND")
            XCTAssertEqual(backendError.presentationFailureKind, .permanent)
            XCTAssertEqual(
                backendError.details,
                "Windowed D3D11 batch presentation requires a native window surface."
            )
        }
        XCTAssertFalse(renderer.isAttached)
    }

    func testD3D11FramePresenterRejectsOffscreenSurfaceBeforeCreatingADevice() async {
        let renderer = D3D11Renderer()

        XCTAssertThrowsError(try renderer.attach(to: SurfaceDescriptor(offscreenPixelSize: size))) { error in
            guard let backendError = error as? D3D11RendererError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(backendError.operation, "Resolve HWND")
            XCTAssertEqual(backendError.presentationFailureKind, .permanent)
            XCTAssertEqual(
                backendError.details,
                "Windowed D3D11 frame presentation requires a native window surface."
            )
        }
        XCTAssertFalse(renderer.isAttached)
    }

    func testSoftwareWindowPresenterRejectsOffscreenSurface() async {
        let renderer = SoftwareWindowRenderBackend()

        XCTAssertThrowsError(try renderer.attach(to: SurfaceDescriptor(offscreenPixelSize: size))) { error in
            guard case SoftwarePresentationError.missingWindowHandle = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(renderer.presentedFrameCount, 0)
        XCTAssertNil(renderer.lastRenderedBitmap)
    }
}
