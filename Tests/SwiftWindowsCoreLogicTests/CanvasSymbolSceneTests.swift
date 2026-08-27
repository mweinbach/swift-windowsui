import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI

@MainActor
final class CanvasSymbolSceneTests: XCTestCase {
    private let blue = Color(red: 0, green: 0, blue: 1, alpha: 1)
    private let yellow = Color(red: 1, green: 1, blue: 0, alpha: 1)

    private func paintCanvas(
        size: IntSize = IntSize(width: 64, height: 64), displayScale: Double = 1,
        renderer: @escaping @MainActor (inout CanvasGraphicsContext, Size) -> Void
    ) -> GPUIScene {
        let runtime = RetainedViewRuntime(clearColor: .clear, displayScale: displayScale)
        runtime.setRootSize(size)
        let canvas = UI.canvas(
            frame: Rect(x: 0, y: 0, width: Double(size.width), height: Double(size.height)), renderer: renderer)
        runtime.root.addChild(canvas.makeNode(runtime: runtime))
        // These tests intentionally do not request renderFrame(): the legacy
        // fallback allocates bitmaps, while recording scene sources must not.
        return runtime.renderScene()
    }

    private func passes(in scene: GPUIScene) -> [GPUISceneImageRenderPass] {
        var pending = [scene]
        var result: [GPUISceneImageRenderPass] = []
        while let current = pending.popLast() {
            result.append(contentsOf: current.imageRenderPasses)
            pending.append(contentsOf: current.imageRenderPasses.map(\.scene))
        }
        return result
    }

    private func hasRejectedSource(_ scene: GPUIScene) -> Bool {
        scene.validate().contains {
            if case .invalidImageRenderPass = $0.kind { return true }
            return false
        }
    }

    func testSceneEqualityIncludesImageSourceContentEffectsAndExtents() async {
        func enclosing(_ source: GPUIScene) -> GPUIScene {
            var scene = GPUIScene(clearColor: .clear)
            let textureID = scene.registerImageRenderPass(source, size: IntSize(width: 4, height: 4))
            scene.addImage(ImagePrimitive(screenW: 4, screenH: 4, textureID: textureID))
            scene.finish()
            return scene
        }
        let original = enclosing(GPUIScene(clearColor: blue))
        XCTAssertEqual(original, enclosing(GPUIScene(clearColor: blue)))

        var contentChanged = original
        contentChanged.imageRenderPasses[0].scene.clearColor = yellow
        XCTAssertEqual(contentChanged.layers, original.layers)
        XCTAssertEqual(contentChanged.paintRecords, original.paintRecords)
        XCTAssertNotEqual(contentChanged, original, "Only the image source's pixels changed")

        var effectChanged = original
        effectChanged.imageRenderPasses[0].colorEffects = [.brightness(0.25)]
        XCTAssertNotEqual(effectChanged, original, "Image-source effects are part of the scene value")

        var extentChanged = original
        extentChanged.imageRenderPasses[0].size = IntSize(width: 2, height: 4)
        XCTAssertNotEqual(extentChanged, original)

        let nested = enclosing(original)
        var nestedChanged = nested
        nestedChanged.imageRenderPasses[0].scene.imageRenderPasses[0].colorEffects = [.colorInvert]
        XCTAssertNotEqual(nestedChanged, nested, "Equality must include nested source namespaces")
        XCTAssertEqual(nested, enclosing(original), "Changing a copy must not mutate the original source graph")
    }

    private func assertPixel(
        _ bitmap: BitmapSurface, x: Int, y: Int, color: Color,
        tolerance: Float = 3 / 255, file: StaticString = #filePath, line: UInt = #line
    ) {
        let pixels = bitmap.premultipliedAlpha()
        let offset = y * Int(pixels.bytesPerRow) + x * 4
        XCTAssertEqual(
            Float(pixels.pixels[offset + 2]) / 255, color.red * color.alpha,
            accuracy: tolerance, file: file, line: line)
        XCTAssertEqual(
            Float(pixels.pixels[offset + 1]) / 255, color.green * color.alpha,
            accuracy: tolerance, file: file, line: line)
        XCTAssertEqual(
            Float(pixels.pixels[offset]) / 255, color.blue * color.alpha,
            accuracy: tolerance, file: file, line: line)
        XCTAssertEqual(
            Float(pixels.pixels[offset + 3]) / 255, color.alpha,
            accuracy: tolerance, file: file, line: line)
    }

    func testRepeatedSourceUsesOnePassAndKeepsInterleavedDrawOrder() async throws {
        var sourcePaints = 0
        let symbol = try XCTUnwrap(
            CanvasSymbolSource(displayScale: 1) { _ in
                ViewNode(
                    frame: Rect(x: 0, y: 0, width: 16, height: 16), backgroundColor: blue,
                    canvasDraw: { _, _ in sourcePaints += 1 })
            })
        let scene = paintCanvas { context, _ in
            context.draw(symbol, in: Rect(x: 8, y: 8, width: 16, height: 16))
            context.fill(Rect(x: 16, y: 8, width: 16, height: 16), with: .color(self.yellow))
            context.draw(symbol, in: Rect(x: 24, y: 8, width: 16, height: 16))
        }
        XCTAssertEqual(sourcePaints, 1)
        XCTAssertEqual(
            symbol.runtime.sceneRebuildCount, 0, "Nested recording must not start another public scene render")
        XCTAssertEqual(scene.imageRenderPasses.count, 1)
        XCTAssertTrue(scene.imageResources.isEmpty)
        let images = scene.layers.flatMap(\.images)
        XCTAssertEqual(images.count, 2)
        XCTAssertEqual(images.first?.textureID, images.last?.textureID)
        XCTAssertEqual(scene.presentationOrder().map(\.kind), [.image, .quad, .image])
        let pixels = GPUIRawSceneRasterizer.rasterize(scene, size: IntSize(width: 64, height: 64))
        assertPixel(pixels, x: 12, y: 12, color: blue)
        assertPixel(pixels, x: 20, y: 12, color: yellow)
        assertPixel(pixels, x: 28, y: 12, color: blue)
    }

    func testLazilyRecursiveSymbolRecordingStopsAtTheDepthLimit() async throws {
        var sourcePaints = 0
        func source() -> CanvasSymbolSource? {
            CanvasSymbolSource(displayScale: 1) { runtime in
                UI.canvas(frame: Rect(x: 0, y: 0, width: 2, height: 2)) { context, _ in
                    sourcePaints += 1
                    if let child = source() {
                        context.draw(child, in: Rect(x: 0, y: 0, width: 2, height: 2))
                    }
                }.makeNode(runtime: runtime)
            }
        }
        let first = try XCTUnwrap(source())
        let rejectionsBefore = CanvasSymbolSource.rejectionCount
        let scene = paintCanvas { context, _ in
            context.draw(first, in: Rect(x: 8, y: 8, width: 2, height: 2))
        }
        XCTAssertEqual(sourcePaints, GPUISceneLimits.maxImageRenderPassDepth)
        XCTAssertGreaterThan(CanvasSymbolSource.rejectionCount, rejectionsBefore)
        XCTAssertTrue(hasRejectedSource(scene))
        XCTAssertLessThanOrEqual(passes(in: scene).count, GPUISceneLimits.maxImageRenderPassDepth + 1)
        let pixels = GPUIRawSceneRasterizer.rasterize(scene, size: IntSize(width: 64, height: 64))
        assertPixel(pixels, x: 8, y: 8, color: Color(red: 1, green: 0, blue: 1, alpha: 1))
    }

    func testBranchingSymbolsShareTheCountBudgetBeforeExpandingTheirSources() async throws {
        var sourcePaints = 0
        func source(level: Int) -> CanvasSymbolSource? {
            CanvasSymbolSource(displayScale: 1) { runtime in
                UI.canvas(frame: Rect(x: 0, y: 0, width: 2, height: 2)) { context, _ in
                    sourcePaints += 1
                    if level == 0 {
                        context.fill(Rect(x: 0, y: 0, width: 2, height: 2), with: .color(self.blue))
                    } else {
                        for _ in 0..<2 {
                            if let child = source(level: level - 1) {
                                context.draw(child, in: Rect(x: 0, y: 0, width: 2, height: 2))
                            }
                        }
                    }
                }.makeNode(runtime: runtime)
            }
        }
        // Twelve levels are below the depth limit, but would visit 4095
        // sources without a shared count reservation before recursive paint.
        let first = try XCTUnwrap(source(level: 11))
        let scene = paintCanvas { context, _ in
            context.draw(first, in: Rect(x: 8, y: 8, width: 2, height: 2))
        }
        XCTAssertEqual(sourcePaints, GPUISceneLimits.maxImageRenderPassCount)
        XCTAssertTrue(hasRejectedSource(scene))
        XCTAssertLessThanOrEqual(passes(in: scene).count, GPUISceneLimits.maxImageRenderPassCount * 2 + 1)
        let pixels = GPUIRawSceneRasterizer.rasterize(scene, size: IntSize(width: 64, height: 64))
        assertPixel(pixels, x: 8, y: 8, color: Color(red: 1, green: 0, blue: 1, alpha: 1))

        let small = try XCTUnwrap(source(level: 0))
        let recovered = paintCanvas { context, _ in
            context.draw(small, in: Rect(x: 8, y: 8, width: 2, height: 2))
        }
        XCTAssertTrue(recovered.validate().isEmpty, "The count budget belongs to one paint attempt")
        assertPixel(
            GPUIRawSceneRasterizer.rasterize(recovered, size: IntSize(width: 64, height: 64)),
            x: 8, y: 8, color: blue)
    }

    func testNegativeOverflowShadowAndColorEffectSurviveFractionalScaleCropping() async throws {
        func content(at origin: Point) -> ViewNode {
            ViewNode(
                frame: Rect(origin: origin, size: Size(width: 16, height: 16)),
                backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1),
                shadowColor: Color(red: 1, green: 0, blue: 0, alpha: 0.6),
                shadowOffset: Point(x: -4, y: -3), shadowSpread: 2,
                colorEffects: [.colorInvert],
                children: [
                    ViewNode(
                        frame: Rect(x: -8, y: 6, width: 4, height: 4),
                        backgroundColor: Color(red: 0, green: 1, blue: 0, alpha: 1))
                ])
        }
        for scale in [1.25, 1.5] {
            let symbol = try XCTUnwrap(CanvasSymbolSource(displayScale: scale) { _ in content(at: .zero) })
            XCTAssertEqual(symbol.size, Size(width: 16, height: 16))
            let scene = paintCanvas(displayScale: scale) { context, _ in
                context.draw(symbol, in: Rect(x: 16, y: 16, width: 16, height: 16))
            }
            let reference = ScenePainter.paint(
                root: ViewNode(
                    frame: Rect(x: 0, y: 0, width: 64, height: 64), children: [content(at: Point(x: 16, y: 16))]),
                clearColor: .clear, surfaceSize: Size(width: 64, height: 64), displayScale: scale)
            let size = IntSize(width: Int32(64 * scale), height: Int32(64 * scale))
            let expected = GPUIRawSceneRasterizer.rasterize(reference, size: size).premultipliedAlpha()
            let actual = GPUIRawSceneRasterizer.rasterize(scene, size: size).premultipliedAlpha()
            let image = try XCTUnwrap(scene.layers.flatMap(\.images).first)
            XCTAssertLessThan(image.screenX, Float(16 * scale))
            XCTAssertLessThan(image.screenY, Float(16 * scale))
            XCTAssertTrue(passes(in: scene).contains { $0.colorEffects == [.colorInvert] })
            XCTAssertTrue(scene.imageResources.isEmpty)
            XCTAssertTrue(scene.validate().isEmpty)
            let report = comparePixels(actual, expected, tolerance: 3)
            XCTAssertGreaterThanOrEqual(
                report.matchRatio, 0.995,
                "Symbol crop lost retained content at \(scale)x: max delta \(report.maxChannelDelta)")
            let cyan = Color(red: 0, green: 1, blue: 1, alpha: 1)
            let magenta = Color(red: 1, green: 0, blue: 1, alpha: 1)
            assertPixel(actual, x: Int(24 * scale), y: Int(24 * scale), color: cyan)
            assertPixel(actual, x: Int(10 * scale), y: Int(24 * scale), color: magenta)
            let shadowOffset = Int(13 * scale) * Int(expected.bytesPerRow) + Int(12 * scale) * 4 + 3
            XCTAssertGreaterThan(
                expected.pixels[shadowOffset], 0, "The reference must contain an exposed negative-offset shadow")
            XCTAssertEqual(Int(actual.pixels[shadowOffset]), Int(expected.pixels[shadowOffset]), accuracy: 2)
        }
    }

    func testSmallLayoutWithOversizePaintRecordsAnInvalidSourceWithoutAllocatingIt() async throws {
        var sourcePaints = 0
        let symbol = try XCTUnwrap(
            CanvasSymbolSource(displayScale: 1) { _ in
                ViewNode(
                    frame: Rect(x: 0, y: 0, width: 8, height: 8),
                    canvasDraw: { context, _ in
                        sourcePaints += 1
                        context.fill(Rect(x: -2048, y: 0, width: 4096, height: 2048), with: .color(self.blue))
                    })
            })
        let scene = paintCanvas { context, _ in
            context.draw(symbol, in: Rect(x: 8, y: 8, width: 8, height: 8))
        }
        XCTAssertEqual(symbol.size, Size(width: 8, height: 8))
        XCTAssertEqual(sourcePaints, 1)
        XCTAssertEqual(symbol.runtime.sceneRebuildCount, 0)
        XCTAssertEqual(scene.imageRenderPasses.count, 1)
        XCTAssertFalse(try XCTUnwrap(scene.imageRenderPasses.first).hasValidExtent)
        XCTAssertTrue(hasRejectedSource(scene))
        XCTAssertTrue(scene.imageResources.isEmpty)
        // No rasterization: a small layout does not make its oversized
        // painted crop a safe source texture allocation.
    }

    func testCumulativePixelBudgetRejectsTheFifthLargeDeclaredSourceWithoutRasterizing() async throws {
        XCTAssertEqual(GPUISceneLimits.maxImageRenderPassTotalPixels, 16_777_216)
        var sources: [CanvasSymbolSource] = []
        for _ in 0..<5 {
            sources.append(
                try XCTUnwrap(
                    CanvasSymbolSource(displayScale: 1) { _ in
                        ViewNode(frame: Rect(x: 0, y: 0, width: 2048, height: 2048), backgroundColor: blue)
                    }))
        }
        let scene = paintCanvas { context, _ in
            for (index, source) in sources.enumerated() {
                context.draw(source, in: Rect(x: Double(index) * 4, y: 0, width: 2, height: 2))
            }
        }
        XCTAssertEqual(scene.imageRenderPasses.count, 5)
        XCTAssertTrue(scene.imageRenderPasses.prefix(4).allSatisfy { $0.size == IntSize(width: 2048, height: 2048) })
        XCTAssertFalse(try XCTUnwrap(scene.imageRenderPasses.last).hasValidExtent)
        XCTAssertTrue(hasRejectedSource(scene))
        XCTAssertTrue(scene.imageResources.isEmpty)
        XCTAssertTrue(sources.allSatisfy { $0.runtime.sceneRebuildCount == 0 })
        // Scene recording and structural validation only. Rasterizing even
        // the accepted four sources would allocate the very budget under test.
    }

    func testNativeTextBeforeInsideAndAfterASymbolSharesOneAtlasFrame() async throws {
        NativeGlyphAtlas.installForTesting(NativeGlyphAtlas(atlasWidth: 128, atlasHeight: 128))
        NativeTextRenderer.testingOverrides.layout = { text, style, _, _ in
            Self.syntheticLayout(text, style: style)
        }
        NativeTextRenderer.testingOverrides.rasterizeGlyphForLayout = { glyph, _, _ in
            let coverage = Self.coverage(for: glyph.character)
            return NativeGlyphBitmap(
                surface: BitmapSurface(
                    width: 8, height: 8, bytesPerRow: 32, pixels: Data(repeating: coverage, count: 8 * 8 * 4)),
                bearingX: 0, bearingY: 0, advance: 8)
        }
        defer {
            NativeTextRenderer.resetTestingOverrides()
            NativeGlyphAtlas.restoreSharedForTesting()
        }
        let white = Color(red: 1, green: 1, blue: 1, alpha: 1)
        let style = PixelTextStyle(color: white, alignment: .leading, verticalAlignment: .top, nativeFontSize: 18)
        var intermediateSnapshot: GlyphAtlasSnapshot?
        let clockBeforePreparation = NativeGlyphAtlas.shared.frameIndex
        let symbol = try XCTUnwrap(
            CanvasSymbolSource(displayScale: 1) { _ in
                ViewNode(
                    frame: Rect(x: 0, y: 0, width: 8, height: 8), text: "B", textStyle: style,
                    canvasDraw: { _, _ in intermediateSnapshot = NativeGlyphAtlas.shared.currentSnapshot() },
                    preferredSize: Size(width: 8, height: 8))
            })
        XCTAssertEqual(NativeGlyphAtlas.shared.frameIndex, clockBeforePreparation)
        let scene = paintCanvas { context, _ in
            context.draw("A", in: Rect(x: 4, y: 4, width: 8, height: 8), style: style)
            context.draw(symbol, in: Rect(x: 20, y: 4, width: 8, height: 8))
            context.draw("C", in: Rect(x: 36, y: 4, width: 8, height: 8), style: style)
        }
        XCTAssertEqual(
            NativeGlyphAtlas.shared.frameIndex, clockBeforePreparation + 1,
            "A nested source must not call beginFrame and age/reset the enclosing text pass")
        XCTAssertNotNil(intermediateSnapshot)
        XCTAssertEqual(symbol.runtime.sceneRebuildCount, 0)
        let outerAtlas = try XCTUnwrap(scene.glyphAtlas)
        let liveAtlas = try XCTUnwrap(NativeGlyphAtlas.shared.currentSnapshot())
        XCTAssertEqual(outerAtlas.contentVersion, liveAtlas.contentVersion)
        XCTAssertEqual(outerAtlas.pixels, liveAtlas.pixels)
        let outerGlyphs = scene.layers.flatMap(\.glyphs).sorted { $0.screenX < $1.screenX }
        XCTAssertEqual(outerGlyphs.count, 2)
        let symbolScene = try XCTUnwrap(scene.imageRenderPasses.first).scene
        let innerAtlas = try XCTUnwrap(symbolScene.glyphAtlas)
        let innerGlyph = try XCTUnwrap(symbolScene.layers.flatMap(\.glyphs).first)
        assertAtlasCoverage(innerGlyph, atlas: innerAtlas, coverage: Self.coverage(for: "B"))
        if outerGlyphs.count == 2 {
            assertAtlasCoverage(outerGlyphs[0], atlas: outerAtlas, coverage: Self.coverage(for: "A"))
            assertAtlasCoverage(outerGlyphs[1], atlas: outerAtlas, coverage: Self.coverage(for: "C"))
        }
        XCTAssertTrue(scene.validate().isEmpty)
        let pixels = GPUIRawSceneRasterizer.rasterize(scene, size: IntSize(width: 64, height: 64))
        for (x, character) in [(8, Character("A")), (24, Character("B")), (40, Character("C"))] {
            assertPixel(
                pixels, x: x, y: 8,
                color: Color(red: 1, green: 1, blue: 1, alpha: Float(Self.coverage(for: character)) / 255))
        }
    }

    private static func coverage(for character: Character) -> UInt8 {
        switch character {
        case "A": return 64
        case "B": return 128
        default: return 192
        }
    }

    private static func syntheticLayout(_ text: String, style: PixelTextStyle) -> NativeTextLayoutResult {
        let glyphs = Array(text).enumerated().map { index, character in
            NativeTextGlyphLayout(
                character: character, origin: Point(x: Double(index) * 8, y: 0), advance: 8,
                glyphID: character.unicodeScalars.first?.value ?? UInt32(index + 1),
                fontFamily: style.fontFamily, weight: style.weight, fontSize: style.nativeFontPixelSize,
                sourceIndex: index)
        }
        let width = Double(max(text.count, 1)) * 8
        return NativeTextLayoutResult(
            lines: [NativeTextLineLayout(text: text, width: width, height: 8, glyphs: glyphs)],
            contentSize: Size(width: width, height: 8), measuredSize: Size(width: width, height: 8))
    }

    private func assertAtlasCoverage(_ glyph: GlyphPrimitive, atlas: GlyphAtlasSnapshot, coverage: UInt8) {
        let x = Int(((glyph.atlasU0 + glyph.atlasU1) / 2 * Float(atlas.width)).rounded(.down))
        let y = Int(((glyph.atlasV0 + glyph.atlasV1) / 2 * Float(atlas.height)).rounded(.down))
        guard x >= 0, y >= 0, x < Int(atlas.width), y < Int(atlas.height) else {
            XCTFail("A shipped glyph addresses pixels outside its atlas snapshot")
            return
        }
        XCTAssertEqual(atlas.pixels[(y * Int(atlas.width) + x) * 4 + 3], coverage)
    }
}
