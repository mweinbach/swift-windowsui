import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsGraphics
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Color modifiers filter the composited subtree, in authored order. These
/// tests check observable pixels as well as the scene retained for the GPU.
@MainActor
final class SceneColorEffectPassTests: XCTestCase {
    private let source = Color(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)

    private func snapshot<V: View>(_ view: V, size: IntSize = IntSize(width: 32, height: 32))
        -> WinSwiftUIRenderSnapshot
    {
        WinSwiftUIRendererSnapshotter.snapshot(of: view, size: size, displayScale: 1, clearColor: .clear)
    }

    private func raster(_ scene: GPUIScene, size: IntSize = IntSize(width: 32, height: 32)) -> BitmapSurface {
        GPUIRawSceneRasterizer.rasterize(scene, size: size)
    }

    private func assertPixel(
        _ bitmap: BitmapSurface, x: Int = 16, y: Int = 16, color: Color,
        tolerance: Float = 3 / 255, file: StaticString = #filePath, line: UInt = #line
    ) {
        let pixels = bitmap.premultipliedAlpha()
        let offset = y * Int(pixels.bytesPerRow) + x * 4
        XCTAssertGreaterThanOrEqual(x, 0, file: file, line: line)
        XCTAssertGreaterThanOrEqual(y, 0, file: file, line: line)
        guard x >= 0, y >= 0, x < Int(pixels.width), y < Int(pixels.height) else {
            XCTFail("Pixel lies outside the test surface", file: file, line: line)
            return
        }
        XCTAssertEqual(
            Float(pixels.pixels[offset + 2]) / 255, color.red * color.alpha, accuracy: tolerance, file: file, line: line
        )
        XCTAssertEqual(
            Float(pixels.pixels[offset + 1]) / 255, color.green * color.alpha, accuracy: tolerance, file: file,
            line: line)
        XCTAssertEqual(
            Float(pixels.pixels[offset]) / 255, color.blue * color.alpha, accuracy: tolerance, file: file, line: line)
        XCTAssertEqual(Float(pixels.pixels[offset + 3]) / 255, color.alpha, accuracy: tolerance, file: file, line: line)
    }

    private func passScene(
        _ child: GPUIScene, size: IntSize = IntSize(width: 32, height: 32), effects: [SceneColorEffect] = []
    ) -> GPUIScene {
        var scene = GPUIScene(clearColor: .clear)
        let textureID = scene.registerImageRenderPass(child, size: size, colorEffects: effects)
        scene.addImage(ImagePrimitive(screenW: 32, screenH: 32, textureID: textureID))
        scene.finish()
        return scene
    }

    func testPublicContrastAndSaturationKeepTheirAuthoredZeroAndOneSemantics() async {
        let color = Color(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        let gray = Color(red: 0.3858, green: 0.3858, blue: 0.3858, alpha: 1)
        let cases: [(WinSwiftUIRenderSnapshot, Color)] = [
            (snapshot(color.contrast(1)), color),
            (snapshot(color.contrast(0)), Color(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)),
            (snapshot(color.contrast(-1)), Color(red: 0.8, green: 0.6, blue: 0.2, alpha: 1)),
            (snapshot(color.saturation(1)), color),
            (snapshot(color.saturation(0)), gray),
            (snapshot(color.hueRotation(.degrees(0))), color),
        ]
        for (result, expected) in cases {
            XCTAssertTrue(result.scene.validate().isEmpty)
            assertPixel(raster(result.scene), color: expected)
        }
        XCTAssertEqual(SceneColorEffects.applying([.hueRotation(0)], to: color), color)
    }

    func testPublicModifierOrderAndRepeatedOperationsReachThePixels() async {
        let brightnessFirst = snapshot(source.brightness(0.2).contrast(2))
        let contrastFirst = snapshot(source.contrast(2).brightness(0.2))
        assertPixel(raster(brightnessFirst.scene), color: Color(red: 0.3, green: 0.7, blue: 1, alpha: 1))
        assertPixel(raster(contrastFirst.scene), color: Color(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
        XCTAssertEqual(brightnessFirst.scene.imageRenderPasses.first?.colorEffects, [.brightness(0.2), .contrast(2)])
        XCTAssertEqual(contrastFirst.scene.imageRenderPasses.first?.colorEffects, [.contrast(2), .brightness(0.2)])

        let invertedTwice = snapshot(source.colorInvert().colorInvert())
        assertPixel(raster(invertedTwice.scene), color: source)
        let clampedBetweenOperations = snapshot(source.brightness(0.7).brightness(-0.6))
        assertPixel(raster(clampedBetweenOperations.scene), color: Color(red: 0.3, green: 0.4, blue: 0.4, alpha: 1))
    }

    func testParentEffectRunsAfterChildEffectsAndSourceOverComposition() async throws {
        let bottom = ViewNode(
            frame: Rect(x: 0, y: 0, width: 32, height: 32), backgroundColor: source,
            colorEffects: [.brightness(0.2)])
        let top = ViewNode(
            frame: Rect(x: 0, y: 0, width: 32, height: 32),
            backgroundColor: Color(red: 0.8, green: 0.2, blue: 0.1, alpha: 0.5))
        let parent = ViewNode(
            frame: Rect(x: 0, y: 0, width: 32, height: 32), colorEffects: [.contrast(2)], children: [bottom, top])
        let scene = ScenePainter.paint(root: parent, clearColor: .clear, surfaceSize: Size(width: 32, height: 32))
        let outerPass = try XCTUnwrap(scene.imageRenderPasses.first)
        XCTAssertEqual(outerPass.colorEffects, [.contrast(2)])
        XCTAssertEqual(outerPass.scene.imageRenderPasses.first?.colorEffects, [.brightness(0.2)])
        // Brightened bottom is (0.4, 0.6, 0.8); the half-alpha top produces
        // (0.6, 0.4, 0.45), then the parent's contrast gives (0.7, 0.3, 0.4).
        assertPixel(raster(scene), color: Color(red: 0.7, green: 0.3, blue: 0.4, alpha: 1), tolerance: 5 / 255)
    }

    func testIsolatedSourceRetainsQuadsGlyphsImagesAndCanvasPaths() async throws {
        let red = Color(red: 1, green: 0, blue: 0, alpha: 1)
        let cyan = Color(red: 0, green: 1, blue: 1, alpha: 1)
        let image = BitmapSurface(width: 1, height: 1, bytesPerRow: 4, pixels: Data([0, 0, 255, 255]))
        let root = ViewNode(
            frame: Rect(x: 0, y: 0, width: 64, height: 64), colorEffects: [.colorInvert],
            children: [
                ViewNode(frame: Rect(x: 8, y: 8, width: 12, height: 12), backgroundColor: red),
                ViewNode(
                    frame: Rect(x: 32, y: 8, width: 24, height: 16), text: "X",
                    textStyle: PixelTextStyle(color: red, alignment: .leading, verticalAlignment: .top)),
                ViewNode(frame: Rect(x: 8, y: 32, width: 12, height: 12), bitmapSurface: image),
                ViewNode(
                    frame: Rect(x: 32, y: 32, width: 16, height: 16),
                    canvasDraw: { context, _ in
                        var path = SwiftWindowsCore.Path()
                        path.moveTo(Point(x: 0, y: 16))
                        path.quadraticCurveTo(control: Point(x: 0, y: 0), end: Point(x: 8, y: 0))
                        path.quadraticCurveTo(control: Point(x: 16, y: 0), end: Point(x: 16, y: 16))
                        path.close()
                        // Separate contours retain a real path primitive;
                        // a single triangle or convex curve promotes to quads.
                        path.moveTo(Point(x: 0, y: 0))
                        path.lineTo(Point(x: 2, y: 0))
                        path.lineTo(Point(x: 0, y: 2))
                        path.close()
                        context.fill(path, with: .color(red))
                    }),
            ])
        let scene = ScenePainter.paint(root: root, clearColor: .clear, surfaceSize: Size(width: 64, height: 64))
        let pass = try XCTUnwrap(scene.imageRenderPasses.first)
        XCTAssertEqual(scene.imageRenderPasses.count, 1)
        XCTAssertTrue(
            scene.imageResources.isEmpty, "The effect source must remain a scene rather than a CPU-baked image")
        XCTAssertFalse(pass.scene.layers.flatMap(\.quads).isEmpty)
        XCTAssertGreaterThan(pass.scene.layers.reduce(0) { $0 + $1.glyphs.count + $1.pixelGlyphs.count }, 0)
        XCTAssertFalse(pass.scene.layers.flatMap(\.images).isEmpty)
        XCTAssertFalse(pass.scene.layers.flatMap(\.paths).isEmpty)
        XCTAssertEqual(pass.scene.imageResources.count, 1, "Only the authored bitmap is a CPU image resource")
        XCTAssertTrue(scene.validate().isEmpty)

        let pixels = raster(scene, size: IntSize(width: 64, height: 64))
        assertPixel(pixels, x: 14, y: 14, color: cyan)
        assertPixel(pixels, x: 14, y: 38, color: cyan)
        assertPixel(pixels, x: 40, y: 44, color: cyan)
        assertPixel(pixels, x: 2, y: 2, color: .clear)
        let glyphInk = (8..<24).flatMap { y in (32..<56).map { x in (x, y) } }.first { x, y in
            pixels.pixels[y * Int(pixels.bytesPerRow) + x * 4 + 3] > 250
        }
        let (glyphX, glyphY) = try XCTUnwrap(glyphInk, "The glyph fixture must paint opaque ink")
        assertPixel(pixels, x: glyphX, y: glyphY, color: cyan)
    }

    func testPublicTextEffectPreservesGlyphCoverage() async {
        let text = Text("EFFECT").font(.system(size: 24))
            .foregroundStyle(Color(red: 1, green: 0, blue: 0, alpha: 1))
            .frame(width: 144, height: 48)
        let imageSize = IntSize(width: 144, height: 48)
        let plain = raster(snapshot(text, size: imageSize).scene, size: imageSize)
        let filtered = raster(snapshot(text.contrast(0), size: imageSize).scene, size: imageSize)
        var opaqueInkPixels = 0
        var maxAlphaDifference = 0
        for y in 0..<Int(imageSize.height) {
            for x in 0..<Int(imageSize.width) {
                let offset = y * Int(filtered.bytesPerRow) + x * 4
                maxAlphaDifference = max(
                    maxAlphaDifference, abs(Int(plain.pixels[offset + 3]) - Int(filtered.pixels[offset + 3])))
                if filtered.pixels[offset + 3] > 250 {
                    opaqueInkPixels += 1
                    XCTAssertEqual(Int(filtered.pixels[offset]), 128, accuracy: 2)
                    XCTAssertEqual(Int(filtered.pixels[offset + 1]), 128, accuracy: 2)
                    XCTAssertEqual(Int(filtered.pixels[offset + 2]), 128, accuracy: 2)
                }
            }
        }
        XCTAssertGreaterThan(opaqueInkPixels, 20)
        XCTAssertLessThanOrEqual(maxAlphaDifference, 1, "A color operation must not fill transparent glyph edges")
    }

    func testPublicEffectsFilterTheCompletedDrawingGroup() async {
        let view = ZStack {
            source
            Color(red: 0.8, green: 0.2, blue: 0.1, alpha: 0.5)
        }
        .frame(width: 32, height: 32)
        .drawingGroup()
        .brightness(0.3)
        .contrast(2)
        let result = snapshot(view)
        XCTAssertTrue(result.scene.validate().isEmpty)
        assertPixel(raster(result.scene), color: Color(red: 1, green: 0.7, blue: 0.8, alpha: 1), tolerance: 5 / 255)
    }

    func testSceneReplayCarriesEffectResourcesAndMutationInvalidatesThem() async {
        let affected = ViewNode(
            frame: Rect(x: 0, y: 0, width: 32, height: 32), backgroundColor: source,
            colorEffects: [.brightness(0.2)])
        let sibling = ViewNode(
            frame: Rect(x: 40, y: 0, width: 16, height: 16),
            backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1))
        let runtime = RetainedViewRuntime(
            clearColor: .clear,
            root: ViewNode(frame: Rect(x: 0, y: 0, width: 64, height: 32), children: [sibling, affected]))
        let imageSize = IntSize(width: 64, height: 32)
        let first = runtime.renderScene()
        let brightened = Color(red: 0.4, green: 0.6, blue: 0.8, alpha: 1)
        assertPixel(raster(first, size: imageSize), color: brightened)

        // The newly filtered sibling allocates a source ID before the clean
        // affected node replays its old source, forcing resource-ID remapping.
        sibling.backgroundColor = Color(red: 0, green: 1, blue: 0, alpha: 1)
        sibling.colorEffects = [.colorInvert]
        let replay = runtime.renderScene()
        XCTAssertTrue(replay.validate().isEmpty)
        XCTAssertGreaterThan(runtime.lastSceneReplayCount, 0, "The fixture must exercise scene replay")
        XCTAssertTrue(replay.imageRenderPasses.contains { $0.colorEffects == [.brightness(0.2)] })
        let replayPixels = raster(replay, size: imageSize)
        assertPixel(replayPixels, color: brightened)
        assertPixel(replayPixels, x: 48, y: 8, color: Color(red: 1, green: 0, blue: 1, alpha: 1))

        affected.colorEffects = [.contrast(0)]
        let changed = runtime.renderScene()
        XCTAssertTrue(changed.imageRenderPasses.contains { $0.colorEffects == [.contrast(0)] })
        assertPixel(raster(changed, size: imageSize), color: Color(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        affected.colorEffects = []
        let removed = runtime.renderScene()
        XCTAssertEqual(removed.imageRenderPasses.map(\.colorEffects), [[.colorInvert]])
        assertPixel(raster(removed, size: imageSize), color: source)
    }

    func testTransparentTexelsAndColorMultiplyKeepPremultipliedAlphaValid() async {
        let bitmap = BitmapSurface(
            width: 2, height: 1, bytesPerRow: 8,
            pixels: Data([231, 143, 99, 0, 51, 102, 204, 128]), format: .bgra8Straight)
        let multiplier = Color(red: 0.25, green: 0.5, blue: 0.75, alpha: 0.5)
        let result = SceneColorEffects.applying([.colorMultiply(multiplier)], to: bitmap)
        XCTAssertEqual(result.format, .bgra8Premultiplied)
        assertPixel(result, x: 0, y: 0, color: .clear, tolerance: 0)
        assertPixel(result, x: 1, y: 0, color: Color(red: 0.2, green: 0.2, blue: 0.15, alpha: 128.0 / 255 / 2))
        let brightened = SceneColorEffects.applying([.brightness(1), .colorInvert], to: bitmap)
        assertPixel(brightened, x: 0, y: 0, color: .clear, tolerance: 0)

        let node = ViewNode(
            frame: Rect(x: 8, y: 8, width: 16, height: 16),
            backgroundColor: Color(red: 0.8, green: 0.4, blue: 0.2, alpha: 0.5),
            colorEffects: [.colorMultiply(multiplier)])
        let scene = ScenePainter.paint(root: node, clearColor: .clear, surfaceSize: Size(width: 32, height: 32))
        let pixels = raster(scene)
        assertPixel(pixels, color: Color(red: 0.2, green: 0.2, blue: 0.15, alpha: 0.25))
        assertPixel(pixels, x: 2, y: 2, color: .clear, tolerance: 0)

        // Pins this stack's stated mask contract, not a claim of measured
        // native SwiftUI luminance coefficients.
        let mask = SceneColorEffects.applying(
            [.luminanceToAlpha], to: Color(red: 0.8, green: 0.4, blue: 0.2, alpha: 0.5))
        XCTAssertEqual(mask.red, 0)
        XCTAssertEqual(mask.green, 0)
        XCTAssertEqual(mask.blue, 0)
        XCTAssertEqual(mask.alpha, 0.5 * (0.2126 * 0.8 + 0.7152 * 0.4 + 0.0722 * 0.2), accuracy: 0.0001)
    }

    func testFractionalScaleIsolationKeepsShadowAndOverflowCoverage() async throws {
        for scale in [1.25, 1.5] {
            let red = Color(red: 1, green: 0, blue: 0, alpha: 1)
            let affected = ViewNode(
                frame: Rect(x: 12, y: 12, width: 16, height: 16), backgroundColor: red,
                shadowColor: red, shadowOffset: Point(x: 4, y: 0), shadowSpread: 2,
                children: [ViewNode(frame: Rect(x: 18, y: 0, width: 8, height: 8), backgroundColor: red)])
            let root = ViewNode(frame: Rect(x: 0, y: 0, width: 64, height: 64), children: [affected])
            let imageSize = IntSize(width: Int32(64 * scale), height: Int32(64 * scale))
            let plainScene = ScenePainter.paint(
                root: root, clearColor: .clear, surfaceSize: Size(width: 64, height: 64), displayScale: scale)
            let plain = raster(plainScene, size: imageSize)
            affected.colorEffects = [.colorInvert]
            let filteredScene = ScenePainter.paint(
                root: root, clearColor: .clear, surfaceSize: Size(width: 64, height: 64), displayScale: scale)
            let composite = try XCTUnwrap(filteredScene.layers.first?.images.first)
            XCTAssertTrue(Int(composite.screenX).isMultiple(of: 2), "Keep the original horizontal derivative grid")
            XCTAssertTrue(Int(composite.screenY).isMultiple(of: 2), "Keep the original vertical derivative grid")
            let filtered = raster(filteredScene, size: imageSize)
            var maxAlphaDifference = 0
            for offset in stride(from: 3, to: plain.pixels.count, by: 4) {
                maxAlphaDifference = max(
                    maxAlphaDifference, abs(Int(plain.pixels[offset]) - Int(filtered.pixels[offset])))
            }
            XCTAssertLessThanOrEqual(
                maxAlphaDifference, 2, "Isolation must not clip shadows or overflowing children at \(scale)x")
            assertPixel(
                filtered, x: Int(34 * scale), y: Int(16 * scale), color: Color(red: 0, green: 1, blue: 1, alpha: 1))
            let shadowOffset = Int(25 * scale) * Int(filtered.bytesPerRow) + Int(30 * scale) * 4
            XCTAssertGreaterThan(plain.pixels[shadowOffset + 3], 0, "The fixture must include an exposed shadow")
            XCTAssertEqual(filtered.pixels[shadowOffset + 2], 0, "The exposed red shadow must invert with the subtree")
        }
    }

    func testImagePassPixelAndEffectBudgetsAreValidatedBeforeRendering() async {
        XCTAssertEqual(GPUISceneLimits.maxImageRenderPassPixels, 4_194_304)
        XCTAssertEqual(GPUISceneLimits.maxColorEffects, 256)
        let child = GPUIScene(clearColor: Color(red: 1, green: 0, blue: 0, alpha: 1))
        XCTAssertTrue(passScene(child, size: IntSize(width: 2048, height: 2048)).validate().isEmpty)
        let oversized = passScene(child, size: IntSize(width: 2049, height: 2048))
        XCTAssertFalse(oversized.validate().isEmpty)
        XCTAssertFalse(passScene(child, size: IntSize(width: 0, height: 32)).validate().isEmpty)
        XCTAssertFalse(passScene(child, size: IntSize(width: -1, height: 32)).validate().isEmpty)
        XCTAssertTrue(passScene(child, effects: Array(repeating: .brightness(0), count: 256)).validate().isEmpty)
        let tooManyEffects = passScene(child, effects: Array(repeating: .brightness(0), count: 257))
        XCTAssertFalse(tooManyEffects.validate().isEmpty)

        // Invalid scenes stay diagnosable and bounded: neither source is
        // allocated, nor is an unsupported effect silently replaced by red.
        for invalid in [oversized, tooManyEffects] {
            let pixels = raster(invalid)
            let sample = 16 * Int(pixels.bytesPerRow) + 16 * 4
            XCTAssertGreaterThan(pixels.pixels[sample], 0, "Rejected sources use the visible unsupported tile")
            XCTAssertEqual(pixels.pixels[sample + 1], 0)
        }
    }

    func testCumulativeSourcePixelLedgerRejectsBeforeAllocation() async {
        XCTAssertEqual(GPUISceneLimits.maxImageRenderPassTotalPixels, 16_777_216)
        let largestSource = IntSize(width: 2048, height: 2048)
        var budget = GPUISceneImageRenderPassBudget()
        for _ in 0..<4 {
            XCTAssertTrue(budget.consume(size: largestSource))
        }
        XCTAssertEqual(budget.remainingPixels, 0)
        let remainingPasses = budget.remainingPasses
        XCTAssertFalse(budget.consume(size: IntSize(width: 1, height: 1)))
        XCTAssertEqual(budget.remainingPasses, remainingPasses, "Rejection must not partly consume a source")

        // These are only extent calculations; no 2048-square bitmap exists.
        var smallBudget = GPUISceneImageRenderPassBudget(maxPasses: 2, maxPixels: 16)
        XCTAssertFalse(smallBudget.consume(size: IntSize(width: Int32.max, height: Int32.max)))
        XCTAssertEqual(smallBudget.remainingPixels, 16)
        XCTAssertEqual(smallBudget.remainingPasses, 2)
        XCTAssertTrue(smallBudget.consume(size: IntSize(width: 2, height: 2)))
        XCTAssertTrue(smallBudget.consume(size: IntSize(width: 2, height: 2)))
        XCTAssertFalse(smallBudget.consume(size: IntSize(width: 2, height: 2)))
        XCTAssertEqual(smallBudget.remainingPixels, 8, "The pass-count boundary remains independently enforced")
    }

    func testAggregateDeclaredExtentsCountEveryChildNamespace() async {
        let largestSource = IntSize(width: 2048, height: 2048)
        let leaf = GPUIScene(clearColor: source)

        func declaredSources(_ count: Int) -> GPUIScene {
            var scene = GPUIScene(clearColor: .clear)
            for _ in 0..<count {
                let textureID = scene.registerImageRenderPass(leaf, size: largestSource)
                scene.addImage(ImagePrimitive(screenW: 2, screenH: 2, textureID: textureID))
            }
            scene.finish()
            return scene
        }

        // The authored graphs contain only a few records. Validate their
        // declared extents without realizing any of the large sources.
        XCTAssertTrue(declaredSources(4).validate().isEmpty)
        let overBudget = declaredSources(5).validate()
        XCTAssertTrue(overBudget.contains { $0.description.contains("cumulative source pixels") })
        XCTAssertTrue(
            overBudget.contains { $0.description.contains(String(GPUISceneLimits.maxImageRenderPassTotalPixels)) })

        let sharedChild = declaredSources(2)
        var scoped = GPUIScene(clearColor: .clear)
        let firstID = scoped.registerImageRenderPass(sharedChild, size: IntSize(width: 2, height: 2))
        scoped.addImage(ImagePrimitive(screenW: 2, screenH: 2, textureID: firstID))
        scoped.finish()
        XCTAssertTrue(scoped.validate().isEmpty)
        let secondID = scoped.registerImageRenderPass(sharedChild, size: IntSize(width: 2, height: 2))
        scoped.addImage(ImagePrimitive(screenX: 2, screenW: 2, screenH: 2, textureID: secondID))
        scoped.finish()
        XCTAssertTrue(
            scoped.validate().contains { $0.description.contains("cumulative source pixels") },
            "Shared value storage does not merge the two child resource namespaces")
    }

    func testCPUSourcePixelExecutionBudgetDoesNotRechargeCachedImages() async {
        let tinySize = IntSize(width: 2, height: 2)
        let red = Color(red: 1, green: 0, blue: 0, alpha: 1)
        let magenta = Color(red: 1, green: 0, blue: 1, alpha: 1)
        let leaf = GPUIScene(clearColor: red)
        var scene = GPUIScene(clearColor: .clear)
        let firstID = scene.registerImageRenderPass(leaf, size: tinySize)
        let secondID = scene.registerImageRenderPass(leaf, size: tinySize)
        scene.addImage(ImagePrimitive(screenW: 2, screenH: 2, textureID: firstID))
        scene.addQuad(QuadPrimitive(x: 2, y: 0, width: 2, height: 2, startB: 1, endB: 1))
        scene.addImage(ImagePrimitive(screenX: 4, screenW: 2, screenH: 2, textureID: firstID))
        scene.addImage(ImagePrimitive(screenX: 8, screenW: 2, screenH: 2, textureID: secondID))
        scene.finish()
        XCTAssertTrue(scene.validate().isEmpty)

        let surface = IntSize(width: 10, height: 2)
        let initialBudget = GPUISceneImageRenderPassBudget(maxPixels: 4)
        let limited = GPUIRawSceneRasterizer.rasterize(scene, size: surface, imageRenderPassBudget: initialBudget)
        assertPixel(limited, x: 0, y: 0, color: red, tolerance: 0)
        assertPixel(limited, x: 4, y: 0, color: red, tolerance: 0)
        assertPixel(limited, x: 8, y: 0, color: magenta, tolerance: 0)
        XCTAssertEqual(
            GPUIRawSceneRasterizer.rasterize(scene, size: surface, imageRenderPassBudget: initialBudget), limited,
            "Every rasterization starts with its own value-scoped execution budget")
        assertPixel(raster(scene, size: surface), x: 8, y: 0, color: red, tolerance: 0)
    }

    func testCPUSourcePixelExecutionBudgetIsSharedAcrossNestedNamespaces() async {
        let tinySize = IntSize(width: 2, height: 2)
        let red = Color(red: 1, green: 0, blue: 0, alpha: 1)
        let child = passScene(GPUIScene(clearColor: red), size: tinySize)
        var scene = GPUIScene(clearColor: .clear)
        for x in [Float(0), Float(2)] {
            let textureID = scene.registerImageRenderPass(child, size: tinySize)
            scene.addImage(ImagePrimitive(screenX: x, screenW: 2, screenH: 2, textureID: textureID))
        }
        scene.finish()
        XCTAssertTrue(scene.validate().isEmpty)

        let surface = IntSize(width: 4, height: 2)
        let limited = GPUIRawSceneRasterizer.rasterize(
            scene, size: surface, imageRenderPassBudget: GPUISceneImageRenderPassBudget(maxPixels: 12))
        assertPixel(limited, x: 0, y: 0, color: red, tolerance: 0)
        assertPixel(limited, x: 2, y: 0, color: Color(red: 1, green: 0, blue: 1, alpha: 1), tolerance: 0)
        assertPixel(
            GPUIRawSceneRasterizer.rasterize(
                scene, size: surface, imageRenderPassBudget: GPUISceneImageRenderPassBudget(maxPixels: 16)),
            x: 2, y: 0, color: red, tolerance: 0)
    }

    func testImagePassNestingHasAnExplicitDepthBoundary() async {
        XCTAssertEqual(GPUISceneLimits.maxImageRenderPassDepth, 32)
        var scene = GPUIScene(clearColor: Color(red: 1, green: 0, blue: 0, alpha: 1))
        for _ in 0..<32 {
            scene = passScene(scene)
        }
        XCTAssertTrue(scene.validate().isEmpty, "Thirty-two nested passes fit the documented limit")
        assertPixel(raster(scene), color: Color(red: 1, green: 0, blue: 0, alpha: 1))
        let tooDeep = passScene(scene)
        XCTAssertFalse(tooDeep.validate().isEmpty)
        let pixels = raster(tooDeep)
        let sample = 16 * Int(pixels.bytesPerRow) + 16 * 4
        XCTAssertGreaterThan(pixels.pixels[sample], 0, "The CPU must stop at the same depth as validation")
    }

    func testBranchingImagePassGraphSharesOneTraversalBudget() async {
        XCTAssertEqual(GPUISceneLimits.maxImageRenderPassCount, 1024)
        let tinySize = IntSize(width: 2, height: 2)
        let red = Color(red: 1, green: 0, blue: 0, alpha: 1)

        func branchingScene(levels: Int) -> GPUIScene {
            var child = GPUIScene(clearColor: red)
            child.finish()
            for _ in 0..<levels {
                var parent = GPUIScene(clearColor: .clear)
                for _ in 0..<2 {
                    let textureID = parent.registerImageRenderPass(child, size: tinySize)
                    parent.addImage(ImagePrimitive(screenW: 2, screenH: 2, textureID: textureID))
                }
                parent.finish()
                child = parent
            }
            return child
        }

        let small = branchingScene(levels: 4)
        XCTAssertTrue(small.validate().isEmpty)
        let validPixels = raster(small, size: tinySize)
        assertPixel(validPixels, x: 0, y: 0, color: red, tolerance: 0)
        assertPixel(validPixels, x: 1, y: 1, color: red, tolerance: 0)

        // COW arrays keep the authored graph small while scoped source IDs
        // expand it to 8190 visits. A depth-only or per-branch budget misses
        // this case even though twelve levels are below the depth limit.
        let hostile = branchingScene(levels: 12)
        let defects = hostile.validate()
        XCTAssertTrue(
            defects.contains { $0.description.contains(String(GPUISceneLimits.maxImageRenderPassCount)) },
            "Validation must report the shared image-pass count limit: \(defects)")
        let rejectedPixels = raster(hostile, size: tinySize)
        XCTAssertEqual(rejectedPixels.width, 2)
        XCTAssertEqual(rejectedPixels.height, 2)
        assertPixel(
            rejectedPixels, x: 0, y: 0,
            color: Color(red: 1, green: 0, blue: 1, alpha: 1), tolerance: 0)
        XCTAssertEqual(
            raster(small, size: tinySize), validPixels,
            "A rejected graph must not consume the next frame's source budget")
    }
}
