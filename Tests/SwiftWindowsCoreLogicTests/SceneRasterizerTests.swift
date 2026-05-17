import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsUI
@testable import WinSwiftUI
import Testing

@MainActor
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

    @Test("Visual helper: red quad renders red pixels")
    func visualRedQuad() {
        var scene = GPUIScene(clearColor: .black)
        scene.addQuad(QuadPrimitive(
            x: 10, y: 10, width: 20, height: 20,
            startR: 1, startG: 0, startB: 0, startA: 1,
            endR: 1, endG: 0, endB: 0, endA: 1
        ))
        let bitmap = GPUIRawSceneRasterizer.rasterize(scene, size: IntSize(width: 40, height: 40))

        assertPixel(bitmap, x: 15, y: 15, color: Color(red: 1, green: 0, blue: 0, alpha: 1))
        assertPixel(bitmap, x: 5, y: 5, color: Color(red: 0, green: 0, blue: 0, alpha: 1))
        assertRegionColor(bitmap, x: 10, y: 10, width: 20, height: 20,
                          color: Color(red: 1, green: 0, blue: 0, alpha: 1))
    }

    @Test("Visual helper: gradient quad renders blended colors")
    func visualGradientQuad() {
        var scene = GPUIScene(clearColor: .black)
        scene.addQuad(QuadPrimitive(
            x: 0, y: 0, width: 40, height: 10,
            startR: 1, startG: 0, startB: 0, startA: 1,
            endR: 0, endG: 0, endB: 1, endA: 1,
            gradientAxis: 1
        ))
        let bitmap = GPUIRawSceneRasterizer.rasterize(scene, size: IntSize(width: 40, height: 10))

        // Verify gradient direction: left is red-dominant, right is blue-dominant, center is mixed
        let left = bitmap.colorAt(x: 5, y: 5)!
        let right = bitmap.colorAt(x: 34, y: 5)!
        let center = bitmap.colorAt(x: 20, y: 5)!

        #expect(left.red > left.blue, "Left side should be red-dominant")
        #expect(right.blue > right.red, "Right side should be blue-dominant")
        #expect(abs(center.red - center.blue) <= 20 / 255, "Center should be roughly balanced red/blue")
    }

    @Test("Rasterizer fills triangle path primitive")
    func trianglePathFill() {
        var scene = GPUIScene(clearColor: .black)
        scene.addPath(PathPrimitive(
            elements: [
                .moveTo(Point(x: 10, y: 10)),
                .lineTo(Point(x: 30, y: 10)),
                .lineTo(Point(x: 20, y: 30)),
                .close,
            ],
            bounds: Rect(x: 10, y: 10, width: 20, height: 20),
            fillColor: Color(red: 0, green: 1, blue: 0, alpha: 1),
            clipBounds: nil
        ), toLayer: 0)

        let bitmap = GPUIRawSceneRasterizer.rasterize(scene, size: IntSize(width: 40, height: 40))
        assertPixel(bitmap, x: 20, y: 20, color: Color(red: 0, green: 1, blue: 0, alpha: 1))
        assertPixel(bitmap, x: 5, y: 5, color: .black)
    }

    @Test("Rasterizer strokes line path primitive")
    func linePathStroke() {
        var scene = GPUIScene(clearColor: .black)
        scene.addPath(PathPrimitive(
            elements: [
                .moveTo(Point(x: 10, y: 20)),
                .lineTo(Point(x: 30, y: 20)),
            ],
            bounds: Rect(x: 10, y: 19, width: 20, height: 2),
            strokeColor: Color(red: 1, green: 0, blue: 0, alpha: 1),
            lineWidth: 2,
            clipBounds: nil
        ), toLayer: 0)

        let bitmap = GPUIRawSceneRasterizer.rasterize(scene, size: IntSize(width: 40, height: 40))
        assertPixel(bitmap, x: 20, y: 20, color: Color(red: 1, green: 0, blue: 0, alpha: 1))
        assertPixel(bitmap, x: 5, y: 5, color: .black)
    }

    @Test("Custom shape view renders through RenderFrame bridge")
    @MainActor
    func customShapeViewRenderFrameBridge() async {
        struct RedTriangle: Shape {
            func path(in rect: Rect) -> Path {
                var p = Path()
                let midX = rect.origin.x + rect.size.width / 2
                let minX = rect.origin.x
                let minY = rect.origin.y
                let maxX = rect.origin.x + rect.size.width
                let maxY = rect.origin.y + rect.size.height
                p.moveTo(Point(x: midX, y: minY))
                p.lineTo(Point(x: maxX, y: maxY))
                p.lineTo(Point(x: minX, y: maxY))
                p.close()
                return p
            }
        }

        let size = IntSize(width: 40, height: 40)
        let runtime = RetainedViewRuntime(root: ViewNode())
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: Double(size.width), height: Double(size.height)) },
            invalidateHandler: {}
        )
        let view = RedTriangle().fill(SwiftWindowsCore.Color.red).frame(width: 40, height: 40)
        let node = view.makeComponent(context: context).makeNode(runtime: runtime)
        runtime.root.addChild(node)
        runtime.setRootSize(size)
        let frame = runtime.renderFrame()
        let scene = GPUIScene(from: frame, surfaceSize: Size(width: Double(size.width), height: Double(size.height)))
        let bitmap = GPUIRawSceneRasterizer.rasterize(scene, size: size)
        assertPixel(bitmap, x: 20, y: 30, color: SwiftWindowsCore.Color.red)
        assertPixel(bitmap, x: 5, y: 5, color: SwiftWindowsCore.Color.black)
    }

    @Test("ScenePainter renders custom shape path primitive")
    @MainActor
    func scenePainterCustomShapePath() async {
        struct GreenTriangle: Shape {
            func path(in rect: Rect) -> Path {
                var p = Path()
                let midX = rect.origin.x + rect.size.width / 2
                let minX = rect.origin.x
                let minY = rect.origin.y
                let maxX = rect.origin.x + rect.size.width
                let maxY = rect.origin.y + rect.size.height
                p.moveTo(Point(x: midX, y: minY))
                p.lineTo(Point(x: maxX, y: maxY))
                p.lineTo(Point(x: minX, y: maxY))
                p.close()
                return p
            }
        }

        let size = IntSize(width: 40, height: 40)
        let runtime = RetainedViewRuntime(root: ViewNode())
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: Double(size.width), height: Double(size.height)) },
            invalidateHandler: {}
        )
        let view = GreenTriangle().fill(Color(red: 0, green: 1, blue: 0, alpha: 1)).frame(width: 40, height: 40)
        let node = view.makeComponent(context: context).makeNode(runtime: runtime)
        runtime.root.addChild(node)
        runtime.setRootSize(size)
        _ = runtime.renderFrame()
        let bitmap = renderNodeToBitmap(runtime.root, size: size, clearColor: .black)
        assertPixel(bitmap, x: 20, y: 30, color: Color(red: 0, green: 1, blue: 0, alpha: 1))
        assertPixel(bitmap, x: 5, y: 5, color: Color.black)
    }

    @Test("Custom shape view stroke renders through RenderFrame bridge")
    @MainActor
    func customShapeViewStroke() async {
        struct BlueTriangle: Shape {
            func path(in rect: Rect) -> Path {
                var p = Path()
                let midX = rect.origin.x + rect.size.width / 2
                let minX = rect.origin.x
                let minY = rect.origin.y
                let maxX = rect.origin.x + rect.size.width
                let maxY = rect.origin.y + rect.size.height
                p.moveTo(Point(x: midX, y: minY))
                p.lineTo(Point(x: maxX, y: maxY))
                p.lineTo(Point(x: minX, y: maxY))
                p.close()
                return p
            }
        }

        let size = IntSize(width: 40, height: 40)
        let runtime = RetainedViewRuntime(root: ViewNode())
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: Double(size.width), height: Double(size.height)) },
            invalidateHandler: {}
        )
        let view = BlueTriangle().stroke(SwiftWindowsCore.Color.blue, lineWidth: 2).frame(width: 40, height: 40)
        let node = view.makeComponent(context: context).makeNode(runtime: runtime)
        runtime.root.addChild(node)
        runtime.setRootSize(size)
        let frame = runtime.renderFrame()
        let scene = GPUIScene(from: frame, surfaceSize: Size(width: Double(size.width), height: Double(size.height)))
        let bitmap = GPUIRawSceneRasterizer.rasterize(scene, size: size)
        // Stroke should paint the triangle edges blue
        assertPixel(bitmap, x: 20, y: 2, color: SwiftWindowsCore.Color.blue)
        // Interior should remain clear (black)
        assertPixel(bitmap, x: 20, y: 30, color: SwiftWindowsCore.Color.black)
    }
}
