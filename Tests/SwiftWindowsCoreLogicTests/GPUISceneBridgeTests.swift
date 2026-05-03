import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import Testing

@Suite("GPUISceneBridge Tests")
struct GPUISceneBridgeTests {
    let surfaceSize = Size(width: 1920, height: 1080)

    // MARK: - Basic Conversion

    @Test("Empty frame produces scene with 1 empty layer")
    func emptyFrame() {
        let frame = RenderFrame(clearColor: .black, commands: [])
        let scene = GPUIScene(from: frame, surfaceSize: surfaceSize)

        #expect(scene.layers.count == 1)
        #expect(scene.layers[0].quads.isEmpty)
        #expect(scene.layers[0].images.isEmpty)
        #expect(scene.layers[0].glyphs.isEmpty)
        #expect(scene.layers[0].shadows.isEmpty)
    }

    @Test("Clear color propagates from frame to scene")
    func clearColorPropagation() {
        let color = Color(red: 0.2, green: 0.4, blue: 0.6, alpha: 1.0)
        let frame = RenderFrame(clearColor: color, commands: [])
        let scene = GPUIScene(from: frame, surfaceSize: surfaceSize)

        #expect(scene.clearColor == color)
    }

    // MARK: - Quad Conversion

    @Test("Three consecutive fillRect commands produce 1 layer with 3 quads")
    func consecutiveFillRects() {
        let commands: [RenderCommand] = [
            .fillRect(FillRectCommand(rect: Rect(x: 0, y: 0, width: 100, height: 50), color: .white)),
            .fillRect(FillRectCommand(rect: Rect(x: 10, y: 10, width: 80, height: 30), color: .black)),
            .fillRect(FillRectCommand(rect: Rect(x: 20, y: 20, width: 60, height: 10), color: .white)),
        ]
        let frame = RenderFrame(clearColor: .black, commands: commands)
        let scene = GPUIScene(from: frame, surfaceSize: surfaceSize)

        #expect(scene.layers.count == 1)
        #expect(scene.layers[0].quads.count == 3)
        #expect(scene.layers[0].images.isEmpty)

        // Verify first quad position
        let q0 = scene.layers[0].quads[0]
        #expect(q0.x == 0)
        #expect(q0.y == 0)
        #expect(q0.width == 100)
        #expect(q0.height == 50)
    }

    @Test("FillRect maps color to both start and end when no gradient")
    func solidColorQuad() {
        let color = Color(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.9)
        let commands: [RenderCommand] = [
            .fillRect(FillRectCommand(rect: Rect(x: 0, y: 0, width: 50, height: 50), color: color)),
        ]
        let frame = RenderFrame(clearColor: .black, commands: commands)
        let scene = GPUIScene(from: frame, surfaceSize: surfaceSize)

        let quad = scene.layers[0].quads[0]
        #expect(quad.startR == color.red)
        #expect(quad.startG == color.green)
        #expect(quad.startB == color.blue)
        #expect(quad.startA == color.alpha)
        #expect(quad.endR == color.red)
        #expect(quad.endG == color.green)
        #expect(quad.endB == color.blue)
        #expect(quad.endA == color.alpha)
    }

    @Test("FillRect maps corner radius")
    func cornerRadiusMapping() {
        let commands: [RenderCommand] = [
            .fillRect(FillRectCommand(
                rect: Rect(x: 0, y: 0, width: 100, height: 100),
                color: .white,
                cornerRadius: 12.5
            )),
        ]
        let frame = RenderFrame(clearColor: .black, commands: commands)
        let scene = GPUIScene(from: frame, surfaceSize: surfaceSize)

        #expect(scene.layers[0].quads[0].cornerRadius == 12.5)
    }

    // MARK: - Gradient Conversion

    @Test("Linear gradient sets start and end colors with correct axis")
    func linearGradientConversion() {
        let startColor = Color(red: 1, green: 0, blue: 0, alpha: 1)
        let endColor = Color(red: 0, green: 0, blue: 1, alpha: 1)

        let commands: [RenderCommand] = [
            .fillRect(FillRectCommand(
                rect: Rect(x: 0, y: 0, width: 200, height: 100),
                color: .white,
                gradient: LinearGradient(startColor: startColor, endColor: endColor, axis: .horizontal)
            )),
        ]
        let frame = RenderFrame(clearColor: .black, commands: commands)
        let scene = GPUIScene(from: frame, surfaceSize: surfaceSize)

        let quad = scene.layers[0].quads[0]
        #expect(quad.startR == startColor.red)
        #expect(quad.startG == startColor.green)
        #expect(quad.startB == startColor.blue)
        #expect(quad.startA == startColor.alpha)
        #expect(quad.endR == endColor.red)
        #expect(quad.endG == endColor.green)
        #expect(quad.endB == endColor.blue)
        #expect(quad.endA == endColor.alpha)
        #expect(quad.gradientAxis == 1) // horizontal
    }

    @Test("Vertical gradient axis maps to 0")
    func verticalGradientAxis() {
        let commands: [RenderCommand] = [
            .fillRect(FillRectCommand(
                rect: Rect(x: 0, y: 0, width: 100, height: 100),
                color: .white,
                gradient: LinearGradient(startColor: .white, endColor: .black, axis: .vertical)
            )),
        ]
        let frame = RenderFrame(clearColor: .black, commands: commands)
        let scene = GPUIScene(from: frame, surfaceSize: surfaceSize)

        #expect(scene.layers[0].quads[0].gradientAxis == 0)
    }

    // MARK: - Layer Splitting

    @Test("fillRect, drawBitmap, fillRect produces 3 layers")
    func layerSplitOnTypeChange() {
        let bitmap = BitmapSurface(width: 1, height: 1, bytesPerRow: 4, pixels: Data([255, 0, 0, 255]))
        let commands: [RenderCommand] = [
            .fillRect(FillRectCommand(rect: Rect(x: 0, y: 0, width: 100, height: 100), color: .white)),
            .drawBitmap(DrawBitmapCommand(rect: Rect(x: 50, y: 50, width: 64, height: 64), bitmap: bitmap)),
            .fillRect(FillRectCommand(rect: Rect(x: 200, y: 0, width: 100, height: 100), color: .black)),
        ]
        let frame = RenderFrame(clearColor: .black, commands: commands)
        let scene = GPUIScene(from: frame, surfaceSize: surfaceSize)

        #expect(scene.layers.count == 3)
        #expect(scene.layers[0].quads.count == 1)
        #expect(scene.layers[0].images.isEmpty)
        #expect(scene.layers[1].quads.isEmpty)
        #expect(scene.layers[1].images.count == 1)
        #expect(scene.layers[2].quads.count == 1)
        #expect(scene.layers[2].images.isEmpty)
        #expect(scene.imageResources.count == 1)
        #expect(scene.layers[1].images[0].textureID == 0)
    }

    @Test("Consecutive same-type commands stay in the same layer")
    func noSplitForSameType() {
        let bitmap = BitmapSurface(width: 1, height: 1, bytesPerRow: 4, pixels: Data([0, 0, 0, 255]))
        let commands: [RenderCommand] = [
            .drawBitmap(DrawBitmapCommand(rect: Rect(x: 0, y: 0, width: 32, height: 32), bitmap: bitmap)),
            .drawBitmap(DrawBitmapCommand(rect: Rect(x: 40, y: 0, width: 32, height: 32), bitmap: bitmap)),
        ]
        let frame = RenderFrame(clearColor: .black, commands: commands)
        let scene = GPUIScene(from: frame, surfaceSize: surfaceSize)

        #expect(scene.layers.count == 1)
        #expect(scene.layers[0].images.count == 2)
        #expect(scene.imageResources.count == 2)
        #expect(scene.layers[0].images[0].textureID == 0)
        #expect(scene.layers[0].images[1].textureID == 1)
    }

    @Test("shadowRect maps to clipped ShadowPrimitive")
    func shadowRectConversion() {
        let stackClip = Rect(x: 0, y: 0, width: 80, height: 70)
        let commandClip = Rect(x: 50, y: 30, width: 90, height: 80)
        let color = Color(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4)
        let commands: [RenderCommand] = [
            .pushClip(ClipCommand(shape: .rect(stackClip, cornerRadius: 0))),
            .shadowRect(ShadowRectCommand(
                rect: Rect(x: 12, y: 18, width: 120, height: 48),
                color: color,
                cornerRadius: 9,
                blurRadius: 14,
                offset: Point(x: 4, y: 7),
                clipRect: commandClip
            )),
            .popClip,
        ]
        let frame = RenderFrame(clearColor: .black, commands: commands)
        let scene = GPUIScene(from: frame, surfaceSize: surfaceSize)

        #expect(scene.layers.count == 1)
        #expect(scene.layers[0].shadows.count == 1)
        #expect(scene.layers[0].quads.isEmpty)

        let shadow = scene.layers[0].shadows[0]
        #expect(shadow.x == 12)
        #expect(shadow.y == 18)
        #expect(shadow.width == 120)
        #expect(shadow.height == 48)
        #expect(shadow.cornerRadius == 9)
        #expect(shadow.colorR == color.red)
        #expect(shadow.colorG == color.green)
        #expect(shadow.colorB == color.blue)
        #expect(shadow.colorA == color.alpha)
        #expect(shadow.blurRadius == 14)
        #expect(shadow.offsetX == 4)
        #expect(shadow.offsetY == 7)
        #expect(shadow.clipX == 50)
        #expect(shadow.clipY == 30)
        #expect(shadow.clipWidth == 30)
        #expect(shadow.clipHeight == 40)
    }

    @Test("shadowRect layer splitting preserves z order around fills")
    func shadowLayerSplitting() {
        let commands: [RenderCommand] = [
            .fillRect(FillRectCommand(rect: Rect(x: 0, y: 0, width: 30, height: 30), color: .white)),
            .shadowRect(ShadowRectCommand(rect: Rect(x: 8, y: 8, width: 40, height: 24), color: .black)),
            .shadowRect(ShadowRectCommand(rect: Rect(x: 12, y: 40, width: 40, height: 24), color: .black)),
            .fillRect(FillRectCommand(rect: Rect(x: 0, y: 70, width: 30, height: 30), color: .white)),
        ]
        let frame = RenderFrame(clearColor: .black, commands: commands)
        let scene = GPUIScene(from: frame, surfaceSize: surfaceSize)

        #expect(scene.layers.count == 3)
        #expect(scene.layers[0].quads.count == 1)
        #expect(scene.layers[0].shadows.isEmpty)
        #expect(scene.layers[1].quads.isEmpty)
        #expect(scene.layers[1].shadows.count == 2)
        #expect(scene.layers[2].quads.count == 1)
        #expect(scene.layers[2].shadows.isEmpty)
    }

    // MARK: - Clip Stack

    @Test("pushClip then fillRect applies correct clip bounds")
    func clipStackBasic() {
        let clipRect = Rect(x: 10, y: 20, width: 200, height: 300)
        let commands: [RenderCommand] = [
            .pushClip(ClipCommand(shape: .rect(clipRect, cornerRadius: 0))),
            .fillRect(FillRectCommand(rect: Rect(x: 0, y: 0, width: 400, height: 400), color: .white)),
            .popClip,
        ]
        let frame = RenderFrame(clearColor: .black, commands: commands)
        let scene = GPUIScene(from: frame, surfaceSize: surfaceSize)

        let quad = scene.layers[0].quads[0]
        #expect(quad.clipX == Float(clipRect.origin.x))
        #expect(quad.clipY == Float(clipRect.origin.y))
        #expect(quad.clipWidth == Float(clipRect.size.width))
        #expect(quad.clipHeight == Float(clipRect.size.height))
    }

    @Test("No clip uses full surface size as clip rect")
    func noClipUsesFullSurface() {
        let commands: [RenderCommand] = [
            .fillRect(FillRectCommand(rect: Rect(x: 0, y: 0, width: 100, height: 100), color: .white)),
        ]
        let frame = RenderFrame(clearColor: .black, commands: commands)
        let scene = GPUIScene(from: frame, surfaceSize: surfaceSize)

        let quad = scene.layers[0].quads[0]
        #expect(quad.clipX == 0)
        #expect(quad.clipY == 0)
        #expect(quad.clipWidth == Float(surfaceSize.width))
        #expect(quad.clipHeight == Float(surfaceSize.height))
    }

    @Test("popClip restores previous clip")
    func clipStackPopRestore() {
        let outerClip = Rect(x: 0, y: 0, width: 500, height: 500)
        let innerClip = Rect(x: 100, y: 100, width: 200, height: 200)
        let commands: [RenderCommand] = [
            .pushClip(ClipCommand(shape: .rect(outerClip, cornerRadius: 0))),
            .pushClip(ClipCommand(shape: .rect(innerClip, cornerRadius: 0))),
            .fillRect(FillRectCommand(rect: Rect(x: 0, y: 0, width: 400, height: 400), color: .white)),
            .popClip,
            .fillRect(FillRectCommand(rect: Rect(x: 0, y: 0, width: 400, height: 400), color: .black)),
            .popClip,
        ]
        let frame = RenderFrame(clearColor: .black, commands: commands)
        let scene = GPUIScene(from: frame, surfaceSize: surfaceSize)

        // First quad should have inner clip
        let q0 = scene.layers[0].quads[0]
        #expect(q0.clipX == Float(innerClip.origin.x))
        #expect(q0.clipY == Float(innerClip.origin.y))
        #expect(q0.clipWidth == Float(innerClip.size.width))
        #expect(q0.clipHeight == Float(innerClip.size.height))

        // Second quad should have outer clip (inner was popped)
        let q1 = scene.layers[0].quads[1]
        #expect(q1.clipX == Float(outerClip.origin.x))
        #expect(q1.clipY == Float(outerClip.origin.y))
        #expect(q1.clipWidth == Float(outerClip.size.width))
        #expect(q1.clipHeight == Float(outerClip.size.height))
    }

    @Test("Per-command clipRect intersects with stack clip")
    func commandClipIntersectsStack() {
        let stackClip = Rect(x: 0, y: 0, width: 200, height: 200)
        let commandClip = Rect(x: 50, y: 50, width: 300, height: 300)
        // Intersection should be (50, 50, 150, 150)
        let commands: [RenderCommand] = [
            .pushClip(ClipCommand(shape: .rect(stackClip, cornerRadius: 0))),
            .fillRect(FillRectCommand(
                rect: Rect(x: 0, y: 0, width: 400, height: 400),
                color: .white,
                clipRect: commandClip
            )),
            .popClip,
        ]
        let frame = RenderFrame(clearColor: .black, commands: commands)
        let scene = GPUIScene(from: frame, surfaceSize: surfaceSize)

        let quad = scene.layers[0].quads[0]
        #expect(quad.clipX == 50)
        #expect(quad.clipY == 50)
        #expect(quad.clipWidth == 150)
        #expect(quad.clipHeight == 150)
    }

    @Test("replace clip command updates bridge clip state")
    func replaceClipUpdatesBridgeClipState() {
        let outerClip = Rect(x: 0, y: 0, width: 100, height: 100)
        let replacementClip = Rect(x: 240, y: 220, width: 80, height: 70)
        let commands: [RenderCommand] = [
            .pushClip(ClipCommand(shape: .rect(outerClip, cornerRadius: 0))),
            .pushClip(ClipCommand(shape: .rect(replacementClip, cornerRadius: 0), operation: .replace)),
            .fillRect(FillRectCommand(rect: Rect(x: 0, y: 0, width: 400, height: 400), color: .white)),
            .popClip,
            .popClip,
        ]
        let frame = RenderFrame(clearColor: .black, commands: commands)
        let scene = GPUIScene(from: frame, surfaceSize: surfaceSize)

        let quad = scene.layers[0].quads[0]
        #expect(quad.clipX == Float(replacementClip.origin.x))
        #expect(quad.clipY == Float(replacementClip.origin.y))
        #expect(quad.clipWidth == Float(replacementClip.size.width))
        #expect(quad.clipHeight == Float(replacementClip.size.height))
    }

    // MARK: - Image Conversion

    @Test("drawBitmap produces ImagePrimitive with correct fields")
    func drawBitmapConversion() {
        let bitmap = BitmapSurface(width: 64, height: 64, bytesPerRow: 256, pixels: Data(repeating: 0, count: 256 * 64))
        let commands: [RenderCommand] = [
            .drawBitmap(DrawBitmapCommand(
                rect: Rect(x: 10, y: 20, width: 64, height: 64),
                bitmap: bitmap,
                opacity: 0.8
            )),
        ]
        let frame = RenderFrame(clearColor: .black, commands: commands)
        let scene = GPUIScene(from: frame, surfaceSize: surfaceSize)

        #expect(scene.layers[0].images.count == 1)
        let img = scene.layers[0].images[0]
        #expect(img.screenX == 10)
        #expect(img.screenY == 20)
        #expect(img.screenW == 64)
        #expect(img.screenH == 64)
        #expect(img.uvX == 0)
        #expect(img.uvY == 0)
        #expect(img.uvW == 1)
        #expect(img.uvH == 1)
        #expect(img.opacity == 0.8)
        #expect(img.textureID == 0)
        #expect(scene.imageResources.count == 1)
        #expect(scene.imageResource(for: img.textureID)?.bitmap == bitmap)
    }

    // MARK: - Skipped Commands

    @Test("drawText commands are skipped without crashing")
    func drawTextSkipped() {
        let commands: [RenderCommand] = [
            .fillRect(FillRectCommand(rect: Rect(x: 0, y: 0, width: 100, height: 100), color: .white)),
            .drawText(DrawTextCommand(text: "Hello", position: Point(x: 10, y: 10))),
            .fillRect(FillRectCommand(rect: Rect(x: 0, y: 100, width: 100, height: 100), color: .black)),
        ]
        let frame = RenderFrame(clearColor: .black, commands: commands)
        let scene = GPUIScene(from: frame, surfaceSize: surfaceSize)

        // drawText is skipped, so both fillRects stay in the same layer
        #expect(scene.layers[0].quads.count == 2)
        #expect(scene.layers[0].glyphs.isEmpty)
    }

    // MARK: - GPUIScene Structure

    @Test("GPUIScene default init creates one empty layer")
    func sceneDefaultInit() {
        let scene = GPUIScene()
        #expect(scene.layers.count == 1)
        #expect(scene.layers[0].isEmpty)
        #expect(scene.clearColor == .black)
    }

    @Test("pushLayer adds a new layer")
    func scenePushLayer() {
        var scene = GPUIScene()
        scene.pushLayer()
        #expect(scene.layers.count == 2)
    }
}
