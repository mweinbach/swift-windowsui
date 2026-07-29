import SwiftWindowsCore

import SwiftWindowsGraphics

import SwiftWindowsPlatform

import XCTest

@testable import SwiftWindowsUI

final class FoundationAppTests: XCTestCase {
    func testWindowLifecycleUsesInjectedRenderBackend() async {
        await MainActor.run {
            let expectedSurface = SurfaceDescriptor(
                windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 0x1))!,
                pixelSize: IntSize(width: 320, height: 200),
                scaleFactor: 1.5
            )
            let backend = RecordingRenderBackend()
            let app = FoundationApp(
                renderer: backend,
                surfaceDescriptorProvider: { _ in expectedSurface }
            )
            let window = Win32Window(title: "Test Window", clientSize: expectedSurface.pixelSize)

            app.windowDidCreate(window)
            app.window(window, didResizeTo: IntSize(width: 640, height: 480))
            app.windowNeedsDisplay(window)

            XCTAssertEqual(backend.attachedSurfaces, [expectedSurface])
            XCTAssertEqual(backend.resizedSizes, [IntSize(width: 640, height: 480)])
            XCTAssertEqual(backend.renderedFrames.count, 3)
            guard let frame = backend.renderedFrames.last else {
                XCTFail("Expected a rendered frame")
                return
            }

            XCTAssertEqual(frame.clearColor, Color(red: 0.07, green: 0.10, blue: 0.14, alpha: 1.0))
            XCTAssertFalse(frame.commands.isEmpty)
        }
    }
}
@MainActor
private final class RecordingRenderBackend: RenderBackend {
    private(set) var attachedSurfaces: [SurfaceDescriptor] = []
    private(set) var resizedSizes: [IntSize] = []
    private(set) var renderedFrames: [RenderFrame] = []

    func attach(to surface: SurfaceDescriptor) throws {
        attachedSurfaces.append(surface)
    }

    func resize(to size: IntSize) throws {
        resizedSizes.append(size)
    }

    func render(frame: RenderFrame) throws {
        renderedFrames.append(frame)
    }

    /// Owns no platform resources, so teardown really is nothing — stated
    /// rather than inherited, which is the point of `detach()` having no
    /// protocol-extension default.
    func detach() {}
}
