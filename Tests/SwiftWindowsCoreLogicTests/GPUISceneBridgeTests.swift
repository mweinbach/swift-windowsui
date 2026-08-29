import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import Testing

@Suite("GPUISceneBridge Tests")
struct GPUISceneBridgeTests {
    let surfaceSize = Size(width: 1920, height: 1080)

    // MARK: - VAL-SCENE-008: Frame-to-scene bridging preserves supported command mappings

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

    // MARK: - VAL-SCENE-008: fillRect to quad mapping

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
            .fillRect(FillRectCommand(rect: Rect(x: 0, y: 0, width: 50, height: 50), color: color))
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
            .fillRect(
                FillRectCommand(
                    rect: Rect(x: 0, y: 0, width: 100, height: 100),
                    color: .white,
                    cornerRadius: 12.5
                ))
        ]
        let frame = RenderFrame(clearColor: .black, commands: commands)
        let scene = GPUIScene(from: frame, surfaceSize: surfaceSize)

        #expect(scene.layers[0].quads[0].cornerRadius == 12.5)
    }

    // MARK: - VAL-SCENE-008: Linear gradient mapping

    @Test("Linear gradient sets start and end colors with correct axis")
    func linearGradientConversion() {
        let startColor = Color(red: 1, green: 0, blue: 0, alpha: 1)
        let endColor = Color(red: 0, green: 0, blue: 1, alpha: 1)

        let commands: [RenderCommand] = [
            .fillRect(
                FillRectCommand(
                    rect: Rect(x: 0, y: 0, width: 200, height: 100),
                    color: .white,
                    gradient: LinearGradient(startColor: startColor, endColor: endColor, axis: .horizontal)
                ))
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
        #expect(quad.gradientAxis == 1)  // horizontal
    }

    @Test("Vertical gradient axis maps to 0")
    func verticalGradientAxis() {
        let commands: [RenderCommand] = [
            .fillRect(
                FillRectCommand(
                    rect: Rect(x: 0, y: 0, width: 100, height: 100),
                    color: .white,
                    gradient: LinearGradient(startColor: .white, endColor: .black, axis: .vertical)
                ))
        ]
        let frame = RenderFrame(clearColor: .black, commands: commands)
        let scene = GPUIScene(from: frame, surfaceSize: surfaceSize)

        #expect(scene.layers[0].quads[0].gradientAxis == 0)
    }

    // MARK: - VAL-SCENE-008: drawBitmap to image mapping

    @Test("drawBitmap produces ImagePrimitive with correct fields")
    func drawBitmapConversion() {
        let bitmap = BitmapSurface(width: 64, height: 64, bytesPerRow: 256, pixels: Data(repeating: 0, count: 256 * 64))
        let commands: [RenderCommand] = [
            .drawBitmap(
                DrawBitmapCommand(
                    rect: Rect(x: 10, y: 20, width: 64, height: 64),
                    bitmap: bitmap,
                    opacity: 0.8
                ))
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
        #expect(img.sampling == .legacy)
        #expect(
            scene.imageResources == [
                ImageResourceBinding(textureID: 0, bitmap: bitmap)
            ])
    }

    @Test("Bitmap cap and tile descriptors survive bridge conversion and nested clips")
    func bitmapSamplingAndNestedClips() throws {
        let bitmap = BitmapSurface(width: 4, height: 3, bytesPerRow: 16, pixels: Data(repeating: 255, count: 48))
        let originalKey = bitmap.contentKey
        for mode: ImageSamplingMode in [.stretch, .tile] {
            let sampling = try ImageSamplingPlan.resolve(
                sourceSize: IntSize(width: 4, height: 3), destinationSize: Size(width: 8, height: 7),
                capInsets: EdgeInsets(top: 1, leading: 1, bottom: 0, trailing: 1), mode: mode
            ).get()
            let frame = RenderFrame(
                clearColor: .clear,
                commands: [
                    .pushClip(ClipCommand(shape: .rect(Rect(x: 0, y: 0, width: 10, height: 8), cornerRadius: 0))),
                    .pushClip(ClipCommand(shape: .rect(Rect(x: 2, y: 1, width: 4, height: 4), cornerRadius: 0))),
                    .drawBitmap(
                        DrawBitmapCommand(
                            rect: Rect(x: 1, y: 1, width: 8, height: 7), bitmap: bitmap, opacity: 0.75,
                            sampling: sampling)),
                    .popClip,
                    .popClip,
                ])
            let scene = GPUIScene(from: frame, surfaceSize: Size(width: 12, height: 12))
            let image = try #require(scene.layers.first?.images.first)
            #expect(image.sampling == sampling)
            #expect(image.screenX == 1 && image.screenY == 1 && image.screenW == 8 && image.screenH == 7)
            #expect(image.clipX == 2 && image.clipY == 1 && image.clipWidth == 4 && image.clipHeight == 4)
            #expect(image.opacity == 0.75)
            #expect(scene.imageResources.count == 1)
            #expect(scene.imageResources.first?.bitmap.contentKey == originalKey)
            #expect(scene.imageResources.first?.bitmap.pixels == bitmap.pixels)
            #expect(scene.validate().isEmpty)
            let size = IntSize(width: 12, height: 12)
            #expect(
                GPUIRawSceneRasterizer.rasterize(frame, size: size).pixels
                    == GPUIRawSceneRasterizer.rasterize(scene, size: size).pixels)
        }
    }

    @Test("Image replay preserves sampling while resolving a texture ID collision")
    func bitmapSamplingSurvivesReplayRebinding() throws {
        let bitmap = BitmapSurface(width: 4, height: 3, bytesPerRow: 16, pixels: Data(repeating: 255, count: 48))
        let sampling = try ImageSamplingPlan.resolve(
            sourceSize: IntSize(width: 4, height: 3), destinationSize: Size(width: 8, height: 7),
            capInsets: EdgeInsets(top: 1, leading: 1, bottom: 0, trailing: 1), mode: .tile
        ).get()
        let frame = RenderFrame(
            clearColor: .black,
            commands: [
                .drawBitmap(
                    DrawBitmapCommand(rect: Rect(x: 1, y: 1, width: 8, height: 7), bitmap: bitmap, sampling: sampling))
            ])
        let previous = GPUIScene(from: frame, surfaceSize: Size(width: 12, height: 12))
        let originalImage = try #require(previous.layers.first?.images.first)
        var scene = GPUIScene()
        let otherBitmap = BitmapSurface(width: 1, height: 1, bytesPerRow: 4, pixels: Data([0, 0, 255, 255]))
        scene.bindImageResource(otherBitmap, for: originalImage.textureID)
        #expect(scene.replay(0..<previous.paintRecordCount, from: previous) == .success)
        scene.finish()
        let replayed = try #require(scene.layers.first?.images.first)
        #expect(replayed.textureID != originalImage.textureID)
        #expect(replayed.sampling == sampling)
        #expect(scene.imageResources.count == 2)
        #expect(
            scene.imageResources.first(where: { $0.textureID == replayed.textureID })?.bitmap.contentKey
                == bitmap.contentKey)
        #expect(
            scene.imageResources.first(where: { $0.textureID == originalImage.textureID })?.bitmap.contentKey
                == otherBitmap.contentKey)
        #expect(scene.validate().isEmpty)
        let size = IntSize(width: 12, height: 12)
        #expect(
            GPUIRawSceneRasterizer.rasterize(scene, size: size).pixels
                == GPUIRawSceneRasterizer.rasterize(previous, size: size).pixels)
    }

    @Test("Invalid bitmap sampling is omitted without reordering later frame commands")
    func invalidBitmapSamplingDoesNotReorderFollowingCommands() throws {
        let bitmap = BitmapSurface(width: 1, height: 1, bytesPerRow: 4, pixels: Data([0, 0, 255, 255]))
        let sampling = try ImageSamplingPlan.resolve(
            sourceSize: IntSize(width: 1, height: 1), destinationSize: Size(width: 4, height: 4),
            capInsets: .zero, mode: .tile
        ).get()
        var invalid = sampling
        invalid.samplingKind = 42
        let frame = RenderFrame(
            clearColor: .black,
            commands: [
                .fillRect(FillRectCommand(rect: Rect(x: 0, y: 0, width: 8, height: 4), color: .white)),
                .drawBitmap(
                    DrawBitmapCommand(rect: Rect(x: 0, y: 0, width: 4, height: 4), bitmap: bitmap, sampling: invalid)),
                .drawBitmap(
                    DrawBitmapCommand(rect: Rect(x: 4, y: 0, width: 4, height: 4), bitmap: bitmap, sampling: sampling)),
                .fillRect(FillRectCommand(rect: Rect(x: 6, y: 0, width: 2, height: 4), color: .black)),
            ])
        let scene = GPUIScene(from: frame, surfaceSize: Size(width: 8, height: 4))
        #expect(scene.layers.first?.images.count == 1)
        #expect(scene.presentationOrder().map(\.kind) == [.quad, .image, .quad])
        let pixels = GPUIRawSceneRasterizer.rasterize(scene, size: IntSize(width: 8, height: 4))
        #expect(Array(pixels.pixels[0..<4]) == [255, 255, 255, 255])
        #expect(Array(pixels.pixels[16..<20]) == [0, 0, 255, 255])
        #expect(Array(pixels.pixels[24..<28]) == [0, 0, 0, 255])
    }

    @Test("Raw bitmap placement is checked before Double to Float narrowing")
    func bitmapPlacementChecksOriginalDoubleBeforeNarrowing() throws {
        let invalidBitmap = BitmapSurface(width: 1, height: 1, bytesPerRow: 4, pixels: Data([0, 255, 0, 255]))
        let validBitmap = BitmapSurface(width: 1, height: 1, bytesPerRow: 4, pixels: Data([0, 0, 255, 255]))
        let sampling = try ImageSamplingPlan.resolve(
            sourceSize: IntSize(width: 1, height: 1), destinationSize: Size(width: 4, height: 4),
            capInsets: .zero, mode: .tile
        ).get()
        let limit = Double(GPUISceneLimits.maxCoordinate)
        let invalidRect = Rect(x: 0, y: 0, width: limit + 0.01, height: 4)
        #expect(Float(invalidRect.size.width) == GPUISceneLimits.maxCoordinate)
        #expect(sampling.placementValidationFailure(rect: invalidRect) == .unrepresentableDescriptor)
        let frame = RenderFrame(
            clearColor: .black,
            commands: [
                .fillRect(FillRectCommand(rect: Rect(x: 0, y: 0, width: 8, height: 4), color: .white)),
                .drawBitmap(DrawBitmapCommand(rect: invalidRect, bitmap: invalidBitmap, sampling: sampling)),
                .drawBitmap(
                    DrawBitmapCommand(
                        rect: Rect(x: 4, y: 0, width: 4, height: 4), bitmap: validBitmap, sampling: sampling)),
            ])
        let scene = GPUIScene(from: frame, surfaceSize: Size(width: 8, height: 4))
        #expect(scene.layers.first?.images.count == 1)
        #expect(scene.imageResources.count == 1)
        #expect(scene.imageResources.first?.bitmap.contentKey == validBitmap.contentKey)
        #expect(scene.presentationOrder().map(\.kind) == [.quad, .image])
        let pixels = GPUIRawSceneRasterizer.rasterize(scene, size: IntSize(width: 8, height: 4))
        #expect(Array(pixels.pixels[0..<4]) == [255, 255, 255, 255])
        #expect(Array(pixels.pixels[16..<20]) == [0, 0, 255, 255])

        #expect(ImageSamplingDescriptor.legacy.placementValidationFailure(rect: invalidRect) == nil)
        let legacyFrame = RenderFrame(
            clearColor: .black,
            commands: [.drawBitmap(DrawBitmapCommand(rect: invalidRect, bitmap: validBitmap))])
        let legacyScene = GPUIScene(from: legacyFrame, surfaceSize: Size(width: 8, height: 4))
        let legacyImage = try #require(legacyScene.layers.first?.images.first)
        #expect(legacyImage.screenW == GPUISceneLimits.maxCoordinate)
        #expect(legacyImage.sampling == .legacy)
    }

    // MARK: - VAL-SCENE-008: Default clip when no clip is active

    @Test("No clip uses full surface size as clip rect")
    func noClipUsesFullSurface() {
        let commands: [RenderCommand] = [
            .fillRect(FillRectCommand(rect: Rect(x: 0, y: 0, width: 100, height: 100), color: .white))
        ]
        let frame = RenderFrame(clearColor: .black, commands: commands)
        let scene = GPUIScene(from: frame, surfaceSize: surfaceSize)

        let quad = scene.layers[0].quads[0]
        #expect(quad.clipX == 0)
        #expect(quad.clipY == 0)
        #expect(quad.clipWidth == Float(surfaceSize.width))
        #expect(quad.clipHeight == Float(surfaceSize.height))
    }

    // MARK: - VAL-SCENE-009: Clip-stack semantics - intersect (default)

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

        // First quad should have inner clip (intersection of both clips)
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
            .fillRect(
                FillRectCommand(
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

    // MARK: - VAL-SCENE-009: Replace clip operation

    @Test("Replace clip operation discards prior clip state")
    func replaceClipOperation() {
        let firstClip = Rect(x: 0, y: 0, width: 100, height: 100)
        let replaceClip = Rect(x: 50, y: 50, width: 200, height: 200)

        let commands: [RenderCommand] = [
            .pushClip(ClipCommand(shape: .rect(firstClip, cornerRadius: 0), operation: .intersect)),
            .pushClip(ClipCommand(shape: .rect(replaceClip, cornerRadius: 0), operation: .replace)),
            .fillRect(FillRectCommand(rect: Rect(x: 0, y: 0, width: 400, height: 400), color: .white)),
            .popClip,
            .popClip,
        ]
        let frame = RenderFrame(clearColor: .black, commands: commands)
        let scene = GPUIScene(from: frame, surfaceSize: surfaceSize)

        // The replace clip should be used exactly, not intersected with firstClip
        let q0 = scene.layers[0].quads[0]
        #expect(q0.clipX == Float(replaceClip.origin.x))
        #expect(q0.clipY == Float(replaceClip.origin.y))
        #expect(q0.clipWidth == Float(replaceClip.size.width))
        #expect(q0.clipHeight == Float(replaceClip.size.height))
    }

    // MARK: - VAL-SCENE-009: Safe empty-pop behavior

    @Test("popClip on empty stack is a safe no-op")
    func emptyPopClipIsNoOp() {
        let commands: [RenderCommand] = [
            .popClip,  // No matching pushClip
            .fillRect(FillRectCommand(rect: Rect(x: 0, y: 0, width: 100, height: 100), color: .white)),
        ]
        let frame = RenderFrame(clearColor: .black, commands: commands)
        let scene = GPUIScene(from: frame, surfaceSize: surfaceSize)

        // Should not crash and should produce the quad with full surface clip
        #expect(scene.layers[0].quads.count == 1)
        let quad = scene.layers[0].quads[0]
        #expect(quad.clipWidth == Float(surfaceSize.width))
        #expect(quad.clipHeight == Float(surfaceSize.height))
    }

    // MARK: - VAL-SCENE-009: Empty effective clip suppresses command

    @Test("Empty resulting clip suppresses fillRect command")
    func emptyClipSuppressesFillRect() {
        let nonOverlappingClip = Rect(x: 200, y: 200, width: 50, height: 50)
        let commands: [RenderCommand] = [
            .pushClip(ClipCommand(shape: .rect(nonOverlappingClip, cornerRadius: 0))),
            .fillRect(
                FillRectCommand(
                    rect: Rect(x: 0, y: 0, width: 100, height: 100),  // No overlap with clip at (200,200)
                    color: .white
                )),
            .popClip,
        ]
        let frame = RenderFrame(clearColor: .black, commands: commands)
        let scene = GPUIScene(from: frame, surfaceSize: surfaceSize)

        // The rect at (0,0,100,100) has no overlap with clip at (200,200,50,50)
        // so the effective clip is empty and the command should be suppressed
        #expect(scene.layers[0].quads.isEmpty)
    }

    @Test("Empty resulting clip suppresses drawBitmap command")
    func emptyClipSuppressesDrawBitmap() {
        let bitmap = BitmapSurface(width: 64, height: 64, bytesPerRow: 256, pixels: Data(repeating: 0, count: 256 * 64))
        let nonOverlappingClip = Rect(x: 200, y: 200, width: 50, height: 50)

        let commands: [RenderCommand] = [
            .pushClip(ClipCommand(shape: .rect(nonOverlappingClip, cornerRadius: 0))),
            .drawBitmap(
                DrawBitmapCommand(
                    rect: Rect(x: 0, y: 0, width: 64, height: 64),  // No overlap with clip
                    bitmap: bitmap
                )),
            .popClip,
        ]
        let frame = RenderFrame(clearColor: .black, commands: commands)
        let scene = GPUIScene(from: frame, surfaceSize: surfaceSize)

        // The bitmap rect has no overlap with clip, so command should be suppressed
        #expect(scene.layers[0].images.isEmpty)
    }

    // MARK: - VAL-SCENE-010: Unsupported draw commands skipped safely

    @Test("drawText commands are skipped without crashing")
    func drawTextSkipped() {
        let commands: [RenderCommand] = [
            .fillRect(FillRectCommand(rect: Rect(x: 0, y: 0, width: 100, height: 100), color: .white)),
            .drawText(DrawTextCommand(text: "Hello", position: Point(x: 10, y: 10))),
            .fillRect(FillRectCommand(rect: Rect(x: 0, y: 100, width: 100, height: 100), color: .black)),
        ]
        let frame = RenderFrame(clearColor: .black, commands: commands)
        let scene = GPUIScene(from: frame, surfaceSize: surfaceSize)

        // drawText is skipped, so both fillRects stay in one quad paint operation
        #expect(scene.layers[0].quads.count == 2)
        #expect(scene.layers[0].glyphs.isEmpty)
        #expect(
            scene.layers[0].paintOperations == [
                GPUIPaintOperation(kind: .quad, startIndex: 0, count: 2)
            ])
    }

    @Test("fillPath commands convert to path primitives")
    func fillPathConverted() {
        var path = RenderPath()
        path.move(to: Point(x: 0, y: 0))
        path.addLine(to: Point(x: 100, y: 0))
        path.addLine(to: Point(x: 50, y: 100))
        path.close()

        let commands: [RenderCommand] = [
            .fillRect(FillRectCommand(rect: Rect(x: 0, y: 0, width: 100, height: 100), color: .white)),
            .fillPath(FillPathCommand(path: path, color: Color(red: 1, green: 0, blue: 0, alpha: 1))),
            .fillRect(FillRectCommand(rect: Rect(x: 0, y: 100, width: 100, height: 100), color: .black)),
        ]
        let frame = RenderFrame(clearColor: .black, commands: commands)
        let scene = GPUIScene(from: frame, surfaceSize: surfaceSize)

        #expect(scene.layers[0].quads.count == 2)
        #expect(scene.layers[0].paths.count == 1)
        #expect(
            scene.layers[0].paintOperations == [
                GPUIPaintOperation(kind: .quad, startIndex: 0, count: 1),
                GPUIPaintOperation(kind: .path, startIndex: 0, count: 1),
                GPUIPaintOperation(kind: .quad, startIndex: 1, count: 1),
            ])
    }

    @Test("strokePath commands convert to path primitives")
    func strokePathConverted() {
        var path = RenderPath()
        path.move(to: Point(x: 0, y: 0))
        path.addLine(to: Point(x: 100, y: 100))

        let commands: [RenderCommand] = [
            .fillRect(FillRectCommand(rect: Rect(x: 0, y: 0, width: 100, height: 100), color: .white)),
            .strokePath(StrokePathCommand(path: path, color: Color(red: 0, green: 0, blue: 1, alpha: 1))),
            .fillRect(FillRectCommand(rect: Rect(x: 0, y: 100, width: 100, height: 100), color: .black)),
        ]
        let frame = RenderFrame(clearColor: .black, commands: commands)
        let scene = GPUIScene(from: frame, surfaceSize: surfaceSize)

        #expect(scene.layers[0].quads.count == 2)
        #expect(scene.layers[0].paths.count == 1)
    }

    @Test("applyBlur commands are skipped without crashing")
    func applyBlurSkipped() {
        let commands: [RenderCommand] = [
            .fillRect(FillRectCommand(rect: Rect(x: 0, y: 0, width: 100, height: 100), color: .white)),
            .applyBlur(BlurCommand(region: Rect(x: 10, y: 10, width: 80, height: 80), radius: 5)),
            .fillRect(FillRectCommand(rect: Rect(x: 0, y: 100, width: 100, height: 100), color: .black)),
        ]
        let frame = RenderFrame(clearColor: .black, commands: commands)
        let scene = GPUIScene(from: frame, surfaceSize: surfaceSize)

        // applyBlur is skipped without reordering neighbors
        #expect(scene.layers[0].quads.count == 2)
        #expect(
            scene.layers[0].paintOperations == [
                GPUIPaintOperation(kind: .quad, startIndex: 0, count: 2)
            ])
    }

    // MARK: - VAL-SCENE-011: Advanced gradients survive frame-to-scene lowering

    @Test("Radial gradient preserves authored center and radius")
    func radialGradientLowering() {
        let startColor = Color(red: 1, green: 0, blue: 0, alpha: 1)
        let endColor = Color(red: 0, green: 0, blue: 1, alpha: 1)
        let radialGradient = RadialGradient(
            center: Point(x: 50, y: 50),
            radius: 50,
            stops: [
                GradientStop(color: startColor, position: 0),
                GradientStop(color: endColor, position: 1),
            ]
        )

        let commands: [RenderCommand] = [
            .fillRect(
                FillRectCommand(
                    rect: Rect(x: 0, y: 0, width: 100, height: 100),
                    color: .white,
                    gradient: .radial(radialGradient)
                ))
        ]
        let frame = RenderFrame(clearColor: .black, commands: commands)
        let scene = GPUIScene(from: frame, surfaceSize: surfaceSize)

        let quad = scene.layers[0].quads[0]
        #expect(quad.usesRadialGradient)
        #expect(quad.startR == 1.0)
        #expect(quad.endB == 1.0)
        #expect(quad.effectParam1 == 50)
        #expect(quad.effectParam2 == 50)
        #expect(quad.effectParam3 == 0)
        #expect(quad.effectParam4 == 50)
    }

    @Test("Conic gradient preserves authored center and angular sweep")
    func conicGradientLowering() {
        let startColor = Color(red: 1, green: 0, blue: 0, alpha: 1)
        let endColor = Color(red: 0, green: 0, blue: 1, alpha: 1)
        let conicGradient = ConicGradient(
            center: Point(x: 50, y: 50),
            angle: 0,
            stops: [
                GradientStop(color: startColor, position: 0),
                GradientStop(color: endColor, position: 1),
            ]
        )

        let commands: [RenderCommand] = [
            .fillRect(
                FillRectCommand(
                    rect: Rect(x: 0, y: 0, width: 100, height: 100),
                    color: .white,
                    gradient: .conic(conicGradient)
                ))
        ]
        let frame = RenderFrame(clearColor: .black, commands: commands)
        let scene = GPUIScene(from: frame, surfaceSize: surfaceSize)

        let quad = scene.layers[0].quads[0]
        #expect(quad.usesConicGradient)
        #expect(quad.startR == 1.0)
        #expect(quad.endB == 1.0)
        #expect(quad.effectParam1 == 50)
        #expect(quad.effectParam2 == 50)
        #expect(abs(quad.effectParam4 - Float(2 * Double.pi)) < 0.0001)
    }

    @Test("Ellipse clip degrades to bounding rect fallback")
    func ellipseClipFallback() {
        let ellipseCenter = Point(x: 100, y: 100)
        let radiusX: Double = 50
        let radiusY: Double = 30

        let commands: [RenderCommand] = [
            .pushClip(ClipCommand(shape: .ellipse(center: ellipseCenter, radiusX: radiusX, radiusY: radiusY))),
            .fillRect(FillRectCommand(rect: Rect(x: 0, y: 0, width: 200, height: 200), color: .white)),
            .popClip,
        ]
        let frame = RenderFrame(clearColor: .black, commands: commands)
        let scene = GPUIScene(from: frame, surfaceSize: surfaceSize)

        // Ellipse clip should fallback to bounding rect (center - radius to center + radius)
        let quad = scene.layers[0].quads[0]
        #expect(quad.clipX == Float(ellipseCenter.x - radiusX))  // 50
        #expect(quad.clipY == Float(ellipseCenter.y - radiusY))  // 70
        #expect(quad.clipWidth == Float(radiusX * 2))  // 100
        #expect(quad.clipHeight == Float(radiusY * 2))  // 60
    }

    @Test("Path clip degrades to full surface fallback (no-op clip)")
    func pathClipFallback() {
        var path = RenderPath()
        path.move(to: Point(x: 0, y: 0))
        path.addLine(to: Point(x: 100, y: 0))
        path.addLine(to: Point(x: 100, y: 100))
        path.addLine(to: Point(x: 0, y: 100))
        path.close()

        let commands: [RenderCommand] = [
            .pushClip(ClipCommand(shape: .path(path))),
            .fillRect(FillRectCommand(rect: Rect(x: 0, y: 0, width: 100, height: 100), color: .white)),
            .popClip,
        ]
        let frame = RenderFrame(clearColor: .black, commands: commands)
        let scene = GPUIScene(from: frame, surfaceSize: surfaceSize)

        // Path clips fallback to full surface (no-op clip) - VAL-SCENE-011
        let quad = scene.layers[0].quads[0]
        #expect(quad.clipX == 0)
        #expect(quad.clipY == 0)
        #expect(quad.clipWidth == Float(surfaceSize.width))
        #expect(quad.clipHeight == Float(surfaceSize.height))
    }

    // MARK: - VAL-SCENE-011: Unsupported blend modes degrade to explicit fallback (ignored)

    @Test("Non-normal blend mode on fillRect is ignored (fallback to default compositing)")
    func fillRectBlendModeFallback() {
        let normalRect = FillRectCommand(
            rect: Rect(x: 0, y: 0, width: 100, height: 100),
            color: Color(red: 1, green: 0, blue: 0, alpha: 0.5),
            blendMode: .normal
        )
        let multiplyRect = FillRectCommand(
            rect: Rect(x: 0, y: 0, width: 100, height: 100),
            color: Color(red: 1, green: 0, blue: 0, alpha: 0.5),
            blendMode: .multiply
        )
        let screenRect = FillRectCommand(
            rect: Rect(x: 0, y: 0, width: 100, height: 100),
            color: Color(red: 1, green: 0, blue: 0, alpha: 0.5),
            blendMode: .screen
        )
        let additiveRect = FillRectCommand(
            rect: Rect(x: 0, y: 0, width: 100, height: 100),
            color: Color(red: 1, green: 0, blue: 0, alpha: 0.5),
            blendMode: .additive
        )
        let overlayRect = FillRectCommand(
            rect: Rect(x: 0, y: 0, width: 100, height: 100),
            color: Color(red: 1, green: 0, blue: 0, alpha: 0.5),
            blendMode: .overlay
        )

        let commands: [RenderCommand] = [
            .fillRect(normalRect),
            .fillRect(multiplyRect),
            .fillRect(screenRect),
            .fillRect(additiveRect),
            .fillRect(overlayRect),
        ]
        let frame = RenderFrame(clearColor: .black, commands: commands)
        let scene = GPUIScene(from: frame, surfaceSize: surfaceSize)

        // All 5 fillRects should be converted to quads regardless of blend mode
        #expect(scene.layers[0].quads.count == 5)
        #expect(
            scene.layers[0].paintOperations == [
                GPUIPaintOperation(kind: .quad, startIndex: 0, count: 5)
            ])

        // Verify all quads have the same color (blend mode doesn't affect color mapping)
        for i in 0..<5 {
            let quad = scene.layers[0].quads[i]
            #expect(quad.startR == 1.0)
            #expect(quad.startG == 0.0)
            #expect(quad.startB == 0.0)
            #expect(quad.startA == 0.5)
        }
    }

    @Test("Non-normal blend mode on drawBitmap is ignored (fallback to default compositing)")
    func drawBitmapBlendModeFallback() {
        let bitmap = BitmapSurface(width: 64, height: 64, bytesPerRow: 256, pixels: Data(repeating: 0, count: 256 * 64))
        let normalBitmap = DrawBitmapCommand(
            rect: Rect(x: 0, y: 0, width: 64, height: 64),
            bitmap: bitmap,
            opacity: 0.8,
            blendMode: .normal
        )
        let multiplyBitmap = DrawBitmapCommand(
            rect: Rect(x: 64, y: 0, width: 64, height: 64),
            bitmap: bitmap,
            opacity: 0.8,
            blendMode: .multiply
        )
        let screenBitmap = DrawBitmapCommand(
            rect: Rect(x: 128, y: 0, width: 64, height: 64),
            bitmap: bitmap,
            opacity: 0.8,
            blendMode: .screen
        )
        let additiveBitmap = DrawBitmapCommand(
            rect: Rect(x: 192, y: 0, width: 64, height: 64),
            bitmap: bitmap,
            opacity: 0.8,
            blendMode: .additive
        )

        let commands: [RenderCommand] = [
            .drawBitmap(normalBitmap),
            .drawBitmap(multiplyBitmap),
            .drawBitmap(screenBitmap),
            .drawBitmap(additiveBitmap),
        ]
        let frame = RenderFrame(clearColor: .black, commands: commands)
        let scene = GPUIScene(from: frame, surfaceSize: surfaceSize)

        // All 4 drawBitmaps should be converted to images regardless of blend mode
        #expect(scene.layers[0].images.count == 4)
        #expect(
            scene.layers[0].paintOperations == [
                GPUIPaintOperation(kind: .image, startIndex: 0, count: 4)
            ])

        // Verify all images have the same opacity (blend mode doesn't affect opacity mapping)
        for i in 0..<4 {
            let img = scene.layers[0].images[i]
            #expect(img.opacity == 0.8)
        }
    }

    @Test("Mixed blend modes with supported commands preserve paint order")
    func mixedBlendModesPreserveOrder() {
        let commands: [RenderCommand] = [
            .fillRect(
                FillRectCommand(rect: Rect(x: 0, y: 0, width: 50, height: 50), color: .white, blendMode: .normal)),
            .fillRect(
                FillRectCommand(rect: Rect(x: 50, y: 0, width: 50, height: 50), color: .black, blendMode: .multiply)),
            .fillRect(
                FillRectCommand(rect: Rect(x: 100, y: 0, width: 50, height: 50), color: .white, blendMode: .screen)),
            .fillRect(
                FillRectCommand(rect: Rect(x: 150, y: 0, width: 50, height: 50), color: .black, blendMode: .additive)),
            .fillRect(
                FillRectCommand(rect: Rect(x: 200, y: 0, width: 50, height: 50), color: .white, blendMode: .overlay)),
            .fillRect(
                FillRectCommand(rect: Rect(x: 250, y: 0, width: 50, height: 50), color: .black, blendMode: .normal)),
        ]
        let frame = RenderFrame(clearColor: .black, commands: commands)
        let scene = GPUIScene(from: frame, surfaceSize: surfaceSize)

        // All 6 fillRects should be converted to quads in order
        #expect(scene.layers[0].quads.count == 6)
        #expect(
            scene.layers[0].paintOperations == [
                GPUIPaintOperation(kind: .quad, startIndex: 0, count: 6)
            ])

        // Verify positions are preserved in order
        #expect(scene.layers[0].quads[0].x == 0)
        #expect(scene.layers[0].quads[1].x == 50)
        #expect(scene.layers[0].quads[2].x == 100)
        #expect(scene.layers[0].quads[3].x == 150)
        #expect(scene.layers[0].quads[4].x == 200)
        #expect(scene.layers[0].quads[5].x == 250)
    }

    @Test("fillRect, drawBitmap, fillRect preserves paint order through operations")
    func layerSplitOnTypeChange() {
        let bitmap = BitmapSurface(width: 1, height: 1, bytesPerRow: 4, pixels: Data([255, 0, 0, 255]))
        let commands: [RenderCommand] = [
            .fillRect(FillRectCommand(rect: Rect(x: 0, y: 0, width: 100, height: 100), color: .white)),
            .drawBitmap(DrawBitmapCommand(rect: Rect(x: 50, y: 50, width: 64, height: 64), bitmap: bitmap)),
            .fillRect(FillRectCommand(rect: Rect(x: 200, y: 0, width: 100, height: 100), color: .black)),
        ]
        let frame = RenderFrame(clearColor: .black, commands: commands)
        let scene = GPUIScene(from: frame, surfaceSize: surfaceSize)

        #expect(scene.layers.count == 1)
        #expect(scene.layers[0].quads.count == 2)
        #expect(scene.layers[0].images.count == 1)
        #expect(
            scene.layers[0].paintOperations == [
                GPUIPaintOperation(kind: .quad, startIndex: 0, count: 1),
                GPUIPaintOperation(kind: .image, startIndex: 0, count: 1),
                GPUIPaintOperation(kind: .quad, startIndex: 1, count: 1),
            ])
    }

    @Test("Consecutive same-type commands stay in one paint operation")
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
        #expect(scene.layers[0].images[0].textureID == 0)
        #expect(scene.layers[0].images[1].textureID == 0)
        #expect(
            scene.imageResources == [
                ImageResourceBinding(textureID: 0, bitmap: bitmap)
            ])
        #expect(
            scene.layers[0].paintOperations == [
                GPUIPaintOperation(kind: .image, startIndex: 0, count: 2)
            ])
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
