import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsRendererD3D11
import Testing

@MainActor
@Suite("Render Backend Factory Tests")
struct RenderBackendFactoryTests {
    @Test("CPU factory produces software backends")
    func cpuFactoryProducesBackends() async {
        let factory = CPURenderBackendFactory()

        #expect(factory.factoryName == "CPU Reference")

        let frameBackend = factory.makeRenderBackend()
        #expect(frameBackend.backendDisplayName == "CPU REFERENCE")

        let batchBackend = factory.makeBatchRenderBackend()
        #expect(batchBackend != nil)
        #expect(batchBackend?.backendDisplayName == "CPU REFERENCE")
    }

    @Test("CPU frame backend renders a simple frame")
    func cpuFrameBackendRenders() async throws {
        let factory = CPURenderBackendFactory()
        let backend = factory.makeRenderBackend()

        try backend.attach(
            to: SurfaceDescriptor(
                offscreenPixelSize: IntSize(width: 4, height: 4),
                scaleFactor: 1.0
            ))

        let frame = RenderFrame(clearColor: Color(red: 1, green: 0, blue: 0, alpha: 1))
        try backend.render(frame: frame)
    }

    @Test("CPU batch backend renders a simple scene")
    func cpuBatchBackendRenders() async throws {
        let factory = CPURenderBackendFactory()
        let backend = try #require(factory.makeBatchRenderBackend())

        try backend.attach(
            to: SurfaceDescriptor(
                offscreenPixelSize: IntSize(width: 4, height: 4),
                scaleFactor: 1.0
            ))

        var scene = GPUIScene(clearColor: Color(red: 0, green: 1, blue: 0, alpha: 1))
        scene.addQuad(
            QuadPrimitive(
                x: 1, y: 1, width: 2, height: 2,
                startR: 0, startG: 0, startB: 1, startA: 1,
                endR: 0, endG: 0, endB: 1, endA: 1
            ))

        try backend.render(scene: scene)
    }

    @Test("D3D11 factory produces GPU backends")
    func d3D11FactoryProducesBackends() async {
        let factory = D3D11RenderBackendFactory()

        #expect(factory.factoryName == "D3D11 GPU")

        let frameBackend = factory.makeRenderBackend()
        #expect(frameBackend.backendDisplayName == "2D RENDERER")

        let batchBackend = factory.makeBatchRenderBackend()
        #expect(batchBackend != nil)
        #expect(batchBackend?.backendDisplayName == "D3D11 BATCH")
    }
}
