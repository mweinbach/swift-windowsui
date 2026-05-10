import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import Testing

@Suite("Raw Scene Rasterizer Tests")
struct SceneRasterizerTests {
    @Test("Rasterizer fills clear color")
    func clearColor() {
        let scene = GPUIScene(clearColor: Color(red: 0.25, green: 0.5, blue: 0.75, alpha: 1))
        let bitmap = GPUIRawSceneRasterizer.rasterize(scene, size: IntSize(width: 2, height: 2))

        #expect(bitmap.width == 2)
        #expect(bitmap.height == 2)
        #expect(bitmap.pixels[0] == 191)
        #expect(bitmap.pixels[1] == 128)
        #expect(bitmap.pixels[2] == 64)
        #expect(bitmap.pixels[3] == 255)
    }

    @Test("Rasterizer paints scene quads from paint records")
    func quadPaintRecords() {
        var scene = GPUIScene(clearColor: .black)
        scene.addQuad(QuadPrimitive(
            x: 1,
            y: 1,
            width: 2,
            height: 2,
            startR: 1,
            startG: 0,
            startB: 0,
            startA: 1,
            endR: 1,
            endG: 0,
            endB: 0,
            endA: 1
        ))

        let bitmap = GPUIRawSceneRasterizer.rasterize(scene, size: IntSize(width: 4, height: 4))
        let redPixelOffset = (1 * 4 + 1) * 4
        let blackPixelOffset = 0

        #expect(bitmap.pixels[redPixelOffset] == 0)
        #expect(bitmap.pixels[redPixelOffset + 1] == 0)
        #expect(bitmap.pixels[redPixelOffset + 2] == 255)
        #expect(bitmap.pixels[redPixelOffset + 3] == 255)
        #expect(bitmap.pixels[blackPixelOffset] == 0)
        #expect(bitmap.pixels[blackPixelOffset + 1] == 0)
        #expect(bitmap.pixels[blackPixelOffset + 2] == 0)
        #expect(bitmap.pixels[blackPixelOffset + 3] == 255)
    }
}
