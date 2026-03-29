import XCTest
import SwiftWindowsCore
import SwiftWindowsGraphics
@testable import SwiftWindowsUI
@testable import SwiftWindowsRendererD3D11

// MARK: - Integration Tests: Batch Renderer Wiring

final class IntegrationTests: XCTestCase {

    private static func flattenedGlyphs(in scene: GPUIScene) -> (native: [GlyphPrimitive], pixel: [GlyphPrimitive]) {
        (scene.layers.flatMap(\.glyphs), scene.layers.flatMap(\.pixelGlyphs))
    }

    // MARK: - GPUIScene Bridge Tests

    func testBridgeConvertsEmptyFrameToSceneWithOneLayer() {
        let frame = RenderFrame(clearColor: .white, commands: [])
        let scene = GPUIScene(from: frame, surfaceSize: Size(width: 800, height: 600))

        XCTAssertEqual(scene.clearColor, .white)
        XCTAssertEqual(scene.layers.count, 1)
        XCTAssertEqual(scene.primitiveCount, 0)
    }

    func testBridgeConvertsFillRectsToQuads() {
        let commands: [RenderCommand] = [
            .fillRect(FillRectCommand(
                rect: Rect(x: 10, y: 20, width: 100, height: 50),
                color: Color(red: 1, green: 0, blue: 0, alpha: 1)
            )),
            .fillRect(FillRectCommand(
                rect: Rect(x: 30, y: 40, width: 60, height: 80),
                color: Color(red: 0, green: 1, blue: 0, alpha: 1),
                cornerRadius: 8
            )),
        ]
        let frame = RenderFrame(clearColor: .black, commands: commands)
        let scene = GPUIScene(from: frame, surfaceSize: Size(width: 800, height: 600))

        // Both fillRect commands are the same primitive type, so they should
        // stay in the same layer.
        XCTAssertEqual(scene.layers.count, 1)
        XCTAssertEqual(scene.layers[0].quads.count, 2)

        let first = scene.layers[0].quads[0]
        XCTAssertEqual(first.x, 10)
        XCTAssertEqual(first.y, 20)
        XCTAssertEqual(first.width, 100)
        XCTAssertEqual(first.height, 50)
        XCTAssertEqual(first.startR, 1)

        let second = scene.layers[0].quads[1]
        XCTAssertEqual(second.cornerRadius, 8)
        XCTAssertEqual(second.startG, 1)
    }

    func testBridgePushesLayerOnPrimitiveTypeChange() {
        let commands: [RenderCommand] = [
            .fillRect(FillRectCommand(
                rect: Rect(x: 0, y: 0, width: 50, height: 50),
                color: .white
            )),
            .drawBitmap(DrawBitmapCommand(
                rect: Rect(x: 0, y: 0, width: 50, height: 50),
                bitmap: BitmapSurface(width: 1, height: 1, bytesPerRow: 4,
                                      pixels: Data([255, 255, 255, 255]))
            )),
            .fillRect(FillRectCommand(
                rect: Rect(x: 60, y: 0, width: 50, height: 50),
                color: .black
            )),
        ]
        let frame = RenderFrame(clearColor: .black, commands: commands)
        let scene = GPUIScene(from: frame, surfaceSize: Size(width: 200, height: 200))

        XCTAssertEqual(scene.layers.count, 1)
        XCTAssertEqual(scene.layers[0].quads.count, 2)
        XCTAssertEqual(scene.layers[0].images.count, 1)
        XCTAssertEqual(scene.layers[0].paintOperations, [
            GPUIPaintOperation(kind: .quad, startIndex: 0, count: 1),
            GPUIPaintOperation(kind: .image, startIndex: 0, count: 1),
            GPUIPaintOperation(kind: .quad, startIndex: 1, count: 1),
        ])
    }

    func testBridgePreservesClearColor() {
        let clearColor = Color(red: 0.2, green: 0.3, blue: 0.4, alpha: 1.0)
        let frame = RenderFrame(clearColor: clearColor, commands: [])
        let scene = GPUIScene(from: frame, surfaceSize: Size(width: 100, height: 100))

        XCTAssertEqual(scene.clearColor, clearColor)
    }

    func testBridgeHandlesClipCommands() {
        let commands: [RenderCommand] = [
            .pushClip(ClipCommand(
                shape: .rect(Rect(x: 10, y: 10, width: 80, height: 80), cornerRadius: 0)
            )),
            .fillRect(FillRectCommand(
                rect: Rect(x: 0, y: 0, width: 100, height: 100),
                color: .white
            )),
            .popClip,
        ]
        let frame = RenderFrame(clearColor: .black, commands: commands)
        let scene = GPUIScene(from: frame, surfaceSize: Size(width: 100, height: 100))

        XCTAssertEqual(scene.layers[0].quads.count, 1)
        // The quad should carry the clip rect from the pushClip command.
        let quad = scene.layers[0].quads[0]
        XCTAssertEqual(quad.clipX, 10)
        XCTAssertEqual(quad.clipY, 10)
        XCTAssertEqual(quad.clipWidth, 80)
        XCTAssertEqual(quad.clipHeight, 80)
    }

    // MARK: - renderScene() Tests

    func testRenderSceneProducesNonEmptyScene() async {
        await MainActor.run {
            let child = ViewNode(
                frame: Rect(x: 0, y: 0, width: 50, height: 30),
                backgroundColor: .white
            )
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 200, height: 200),
                children: [child]
            )
            let runtime = RetainedViewRuntime(root: root)
            let scene = runtime.renderScene()

            XCTAssertGreaterThan(scene.primitiveCount, 0)
            XCTAssertFalse(scene.layers.isEmpty)
        }
    }

    func testRenderSceneUsesRootFrameForSurfaceSize() async {
        await MainActor.run {
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 640, height: 480),
                backgroundColor: Color(red: 0.1, green: 0.2, blue: 0.3, alpha: 1.0)
            )
            let runtime = RetainedViewRuntime(
                clearColor: Color(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0),
                root: root
            )
            let scene = runtime.renderScene()

            // The scene's clear color should come from the runtime.
            XCTAssertEqual(scene.clearColor, Color(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0))
        }
    }

    func testRenderSceneEmitsGlyphsAndAtlasSnapshotForText() async {
        await MainActor.run {
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 240, height: 80),
                text: "HELLO",
                textStyle: PixelTextStyle(color: .white, alignment: .leading, verticalAlignment: .top)
            )
            let runtime = RetainedViewRuntime(root: root)
            let scene = runtime.renderScene()

            XCTAssertEqual(scene.layers.count, 1)
            XCTAssertGreaterThan(scene.layers[0].glyphs.count + scene.layers[0].pixelGlyphs.count, 0)
            XCTAssertTrue(
                scene.glyphAtlas != nil ||
                scene.pixelGlyphAtlas != nil ||
                NativeGlyphAtlas.shared.wasUsedInCurrentFrame
            )
        }
    }

    func testCachedRenderSceneDropsAtlasSnapshotsAfterInitialBuild() async {
        await MainActor.run {
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 240, height: 80),
                text: "HELLO",
                textStyle: PixelTextStyle(color: .white, alignment: .leading, verticalAlignment: .top)
            )
            let runtime = RetainedViewRuntime(root: root)

            let firstScene = runtime.renderScene()
            let cachedScene = runtime.renderScene()

            XCTAssertTrue(firstScene.glyphAtlas != nil || firstScene.pixelGlyphAtlas != nil)
            XCTAssertNil(cachedScene.glyphAtlas)
            XCTAssertNil(cachedScene.pixelGlyphAtlas)
        }
    }

    func testRebuiltSceneWithoutTextMutationOmitsAtlasPayloadButPreservesGlyphOutput() async {
        await MainActor.run {
            let textNode = ViewNode(
                frame: Rect(x: 10, y: 10, width: 180, height: 40),
                text: "HELLO",
                textStyle: PixelTextStyle(color: .white, alignment: .leading, verticalAlignment: .top)
            )
            let sibling = ViewNode(
                frame: Rect(x: 0, y: 60, width: 80, height: 20),
                backgroundColor: .white
            )
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 240, height: 120),
                children: [textNode, sibling]
            )
            let runtime = RetainedViewRuntime(root: root)

            let initialScene = runtime.renderScene()
            sibling.backgroundColor = Color(red: 0, green: 0, blue: 1, alpha: 1)
            let rebuiltScene = runtime.renderScene()
            let initialGlyphs = Self.flattenedGlyphs(in: initialScene)
            let rebuiltGlyphs = Self.flattenedGlyphs(in: rebuiltScene)

            XCTAssertFalse(initialGlyphs.native.isEmpty && initialGlyphs.pixel.isEmpty)
            XCTAssertNil(rebuiltScene.glyphAtlas)
            XCTAssertNil(rebuiltScene.pixelGlyphAtlas)
            XCTAssertEqual(initialGlyphs.native, rebuiltGlyphs.native)
            XCTAssertEqual(initialGlyphs.pixel, rebuiltGlyphs.pixel)
        }
    }

    func testRuntimeAtlasDisciplineStaysCompatibleWithBatchRendererReuse() async throws {
        try await MainActor.run {
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 240, height: 80),
                text: "\u{E700}",
                textStyle: PixelTextStyle(color: .white, alignment: .leading, verticalAlignment: .top)
            )
            let runtime = RetainedViewRuntime(root: root)

            let freshScene = runtime.renderScene()
            let cachedScene = runtime.renderScene()

            XCTAssertTrue(freshScene.glyphAtlas != nil || freshScene.pixelGlyphAtlas != nil)
            XCTAssertNil(cachedScene.glyphAtlas)
            XCTAssertNil(cachedScene.pixelGlyphAtlas)

            let freshPlan = try D3D11BatchRenderer.makeRenderPlan(for: freshScene)
            let cachedPlan = try D3D11BatchRenderer.makeRenderPlan(
                for: cachedScene,
                cachedResources: freshPlan.resultingResources
            )

            let cachedGlyphReplaySteps = cachedPlan.steps.filter {
                switch $0 {
                case .glyphs(_, _, .cached), .pixelGlyphs(_, _, .cached):
                    return true
                default:
                    return false
                }
            }
            XCTAssertFalse(cachedGlyphReplaySteps.isEmpty)
        }
    }

    func testTextMutationReattachesAtlasPayloadWithDirtyRegion() async {
        await MainActor.run {
            let textNode = ViewNode(
                frame: Rect(x: 0, y: 0, width: 240, height: 80),
                text: "HELLO",
                textStyle: PixelTextStyle(color: .white, alignment: .leading, verticalAlignment: .top)
            )
            let runtime = RetainedViewRuntime(root: textNode)

            _ = runtime.renderScene()
            textNode.text = "WORLD"
            let mutatedScene = runtime.renderScene()
            let mutatedGlyphs = Self.flattenedGlyphs(in: mutatedScene)

            XCTAssertFalse(mutatedGlyphs.native.isEmpty && mutatedGlyphs.pixel.isEmpty)
            XCTAssertTrue(
                mutatedScene.glyphAtlas?.dirtyRegion != nil ||
                mutatedScene.pixelGlyphAtlas?.dirtyRegion != nil
            )
        }
    }

    func testAtlasRecoveryBypassesCachedTextSceneReplayAndRerasterizesGlyphUVs() async {
        await MainActor.run {
            defer {
                NativeTextRenderer.resetTestingOverrides()
                NativeGlyphAtlas.shared.resetForTesting()
            }

            NativeGlyphAtlas.shared.resetForTesting()
            NativeTextRenderer.testingOverrides.layout = { text, style, _, _ in
                Self.syntheticNativeLayout(for: text, style: style)
            }
            NativeTextRenderer.testingOverrides.rasterizeGlyphForLayout = { glyph, _, _ in
                Self.stubNativeGlyphBitmap(fill: UInt8(glyph.character.unicodeScalars.first?.value ?? 255))
            }

            let unchangedNode = ViewNode(
                frame: Rect(x: 60, y: 0, width: 40, height: 32),
                text: "A",
                textStyle: PixelTextStyle(color: .white, alignment: .leading, verticalAlignment: .top, nativeFontSize: 18)
            )
            let mutableNode = ViewNode(
                frame: Rect(x: 0, y: 0, width: 40, height: 32),
                text: "X",
                textStyle: PixelTextStyle(color: .white, alignment: .leading, verticalAlignment: .top, nativeFontSize: 18)
            )
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 160, height: 40),
                children: [unchangedNode, mutableNode]
            )
            let runtime = RetainedViewRuntime(root: root)

            let initialScene = runtime.renderScene()
            let initialUnchangedGlyph = Self.findGlyph(in: initialScene, screenX: 60)

            XCTAssertEqual(initialUnchangedGlyph?.atlasU0, 0)
            XCTAssertEqual(initialUnchangedGlyph?.atlasU1, 0.5)

            mutableNode.text = "B"
            root.removeChild(unchangedNode)
            root.addChild(unchangedNode)

            let rebuiltScene = runtime.renderScene()
            let rebuiltMutableGlyph = Self.findGlyph(in: rebuiltScene, screenX: 0)
            let rebuiltUnchangedGlyph = Self.findGlyph(in: rebuiltScene, screenX: 60)

            XCTAssertEqual(runtime.lastSceneReplayCount, 0, "Atlas recovery should invalidate cached scene replay for text-bearing ranges")
            XCTAssertNotNil(rebuiltScene.glyphAtlas, "Recovered scene should reattach the rebuilt native glyph atlas")
            XCTAssertEqual(rebuiltMutableGlyph?.atlasU0, 0)
            XCTAssertEqual(rebuiltMutableGlyph?.atlasU1, 0.5)
            XCTAssertEqual(rebuiltUnchangedGlyph?.atlasU0, 0.5, "Unchanged text should be rerasterized into the rebuilt atlas instead of replaying stale UVs")
            XCTAssertEqual(rebuiltUnchangedGlyph?.atlasU1, 1.0)
        }
    }

    func testRenderSceneScalesPrimitivesIntoDevicePixels() async {
        await MainActor.run {
            let child = ViewNode(
                frame: Rect(x: 10, y: 12, width: 40, height: 24),
                backgroundColor: .white
            )
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 60, height: 48),
                children: [child]
            )
            let runtime = RetainedViewRuntime(root: root, displayScale: 2.0)
            let scene = runtime.renderScene()

            XCTAssertEqual(scene.layers.count, 1)
            XCTAssertEqual(scene.layers[0].quads.count, 1)
            XCTAssertEqual(scene.layers[0].quads[0].x, 20)
            XCTAssertEqual(scene.layers[0].quads[0].y, 24)
            XCTAssertEqual(scene.layers[0].quads[0].width, 80)
            XCTAssertEqual(scene.layers[0].quads[0].height, 48)
            XCTAssertEqual(scene.layers[0].quads[0].clipWidth, 120)
            XCTAssertEqual(scene.layers[0].quads[0].clipHeight, 96)
        }
    }

    private static func findGlyph(in scene: GPUIScene, screenX: Float) -> GlyphPrimitive? {
        flattenedGlyphs(in: scene).native.first { $0.screenX == screenX }
    }

    private static func syntheticNativeLayout(for text: String, style: PixelTextStyle) -> NativeTextLayoutResult {
        let characters = Array(text)
        let glyphs = characters.enumerated().map { index, character in
            NativeTextGlyphLayout(
                character: character,
                origin: Point(x: Double(index) * 9, y: 0),
                advance: 9,
                glyphID: UInt32(character.unicodeScalars.first?.value ?? UInt32(index + 1)),
                fontFamily: style.fontFamily,
                weight: style.weight,
                fontSize: style.nativeFontPixelSize,
                sourceIndex: index
            )
        }
        let width = Double(max(characters.count, 1)) * 9
        let height = max(style.nativeFontPixelSize, 1)
        return NativeTextLayoutResult(
            lines: [
                NativeTextLineLayout(
                    text: text,
                    width: width,
                    height: height,
                    glyphs: glyphs
                )
            ],
            contentSize: Size(width: width, height: height),
            measuredSize: Size(width: width, height: height)
        )
    }

    private static func stubNativeGlyphBitmap(fill: UInt8) -> NativeGlyphBitmap {
        let width = 1024
        let height = 2048
        return NativeGlyphBitmap(
            surface: BitmapSurface(
                width: Int32(width),
                height: Int32(height),
                bytesPerRow: Int32(width * 4),
                pixels: Data(repeating: fill, count: width * height * 4)
            ),
            bearingX: 0,
            bearingY: 0,
            advance: 1
        )
    }

    // MARK: - GPUIScene Layer Management Tests

    func testPushLayerIncreasesCount() {
        var scene = GPUIScene(clearColor: .black)
        XCTAssertEqual(scene.layers.count, 1)

        scene.pushLayer()
        XCTAssertEqual(scene.layers.count, 2)

        scene.pushLayer()
        XCTAssertEqual(scene.layers.count, 3)
    }

    func testPushLayerReturnsCorrectIndex() {
        var scene = GPUIScene(clearColor: .black)
        let idx = scene.pushLayer()
        XCTAssertEqual(idx, 1)
    }

    func testPrimitiveCountAcrossLayers() {
        var scene = GPUIScene(clearColor: .black)
        scene.addQuad(QuadPrimitive(
            x: 0, y: 0, width: 10, height: 10,
            startR: 1, startG: 1, startB: 1, startA: 1,
            endR: 1, endG: 1, endB: 1, endA: 1
        ))
        let overlayLayer = scene.pushLayer()
        scene.addShadow(ShadowPrimitive(
            x: 0, y: 0, width: 10, height: 10,
            colorR: 0, colorG: 0, colorB: 0, colorA: 0.5
        ), toLayer: overlayLayer)
        scene.addQuad(QuadPrimitive(
            x: 0, y: 0, width: 20, height: 20,
            startR: 0, startG: 0, startB: 1, startA: 1,
            endR: 0, endG: 0, endB: 1, endA: 1
        ), toLayer: overlayLayer)

        XCTAssertEqual(scene.primitiveCount, 3)
    }

    // MARK: - BatchRenderBackend Protocol Tests

    func testBatchRenderBackendProtocolCanBeReferenced() async {
        await MainActor.run {
            let backend: any BatchRenderBackend = D3D11BatchRenderer()
            XCTAssertEqual(backend.backendDisplayName, "D3D11 BATCH")
        }
    }

    func testBatchBackendFactoryDefaultsToNilUntilOptedIn() async {
        await MainActor.run {
            let backend = DefaultRenderBackendFactory.makeBatchBackend()
            XCTAssertNil(backend)
        }
    }

    // MARK: - GPUILayer Tests

    func testEmptyLayerHasZeroPrimitives() {
        let layer = GPUILayer()
        XCTAssertEqual(layer.primitiveCount, 0)
        XCTAssertTrue(layer.quads.isEmpty)
        XCTAssertTrue(layer.shadows.isEmpty)
        XCTAssertTrue(layer.glyphs.isEmpty)
        XCTAssertTrue(layer.images.isEmpty)
    }

    func testSceneDefaultsToSingleEmptyLayer() {
        let scene = GPUIScene()
        XCTAssertEqual(scene.layers.count, 1)
        XCTAssertEqual(scene.clearColor, .black)
        XCTAssertEqual(scene.primitiveCount, 0)
    }
}
