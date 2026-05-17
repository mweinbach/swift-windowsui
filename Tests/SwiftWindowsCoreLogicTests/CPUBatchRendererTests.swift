import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import Testing

@MainActor
@Suite("CPU Batch Renderer Tests")
struct CPUBatchRendererTests {
    @Test("Attach and resize record surface size")
    func attachAndResize() async throws {
        let renderer = CPUBatchRenderer()
        try renderer.attach(
            to: SurfaceDescriptor(
                windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 1)!)!,
                pixelSize: IntSize(width: 100, height: 200),
                scaleFactor: 1.0
            ))
        try renderer.resize(to: IntSize(width: 300, height: 400))

        #expect(renderer.backendDisplayName == "CPU REFERENCE")
    }

    @Test("Render stores a bitmap")
    func renderProducesBitmap() async throws {
        let renderer = CPUBatchRenderer()
        try renderer.attach(
            to: SurfaceDescriptor(
                windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 1)!)!,
                pixelSize: IntSize(width: 4, height: 4),
                scaleFactor: 1.0
            ))

        var scene = GPUIScene(clearColor: Color(red: 0.25, green: 0.5, blue: 0.75, alpha: 1))
        try renderer.render(scene: scene)

        let bitmap = try #require(renderer.lastRenderedBitmap)
        #expect(bitmap.width == 4)
        #expect(bitmap.height == 4)
        #expect(bitmap.pixels.count == 4 * 4 * 4)
    }

    @Test("Render with quads matches raw rasterizer output")
    func renderMatchesRawRasterizer() async throws {
        let size = IntSize(width: 8, height: 8)
        let renderer = CPUBatchRenderer()
        try renderer.attach(
            to: SurfaceDescriptor(
                windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 1)!)!,
                pixelSize: size,
                scaleFactor: 1.0
            ))

        var scene = GPUIScene(clearColor: .black)
        scene.addQuad(
            QuadPrimitive(
                x: 2, y: 2, width: 4, height: 4,
                startR: 0, startG: 1, startB: 0, startA: 1,
                endR: 0, endG: 1, endB: 0, endA: 1
            ))
        try renderer.render(scene: scene)

        let rendererBitmap = try #require(renderer.lastRenderedBitmap)
        let rawBitmap = GPUIRawSceneRasterizer.rasterize(scene, size: size)

        #expect(rendererBitmap == rawBitmap)
    }

    @Test("Render throws for zero-size surface")
    func renderThrowsForZeroSize() async {
        let renderer = CPUBatchRenderer()
        try? renderer.attach(
            to: SurfaceDescriptor(
                windowHandle: NativeWindowHandle(rawPointer: UnsafeMutableRawPointer(bitPattern: 1)!)!,
                pixelSize: IntSize(width: 0, height: 0),
                scaleFactor: 1.0
            ))

        let scene = GPUIScene(clearColor: .black)
        #expect(throws: CPUBatchRendererError.self) {
            try renderer.render(scene: scene)
        }
    }

    @Test("Bind resources is a no-op")
    func bindResourcesNoOp() async {
        let renderer = CPUBatchRenderer()
        renderer.bindResources(for: GPUIScene())
        // Should not crash or throw.
    }
}
