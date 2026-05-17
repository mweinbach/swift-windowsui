import SwiftWindowsCore

import SwiftWindowsGraphics

import XCTest

@testable import SwiftWindowsRendererD3D11

final class D3D11BatchRendererTests: XCTestCase {
    private static func makeGlyphAtlasSnapshot() -> GlyphAtlasSnapshot {
        GlyphAtlasSnapshot(
            width: 1,
            height: 1,
            pixels: Data([255, 255, 255, 255]),
            dirtyRegion: GlyphAtlasRegion(x: 0, y: 0, width: 1, height: 1)
        )
    }

    private static func makeBitmapSurface(fill: UInt8) -> BitmapSurface {
        BitmapSurface(width: 1, height: 1, bytesPerRow: 4, pixels: Data([fill, fill, fill, 255]))
    }

    func testBatchShaderSourcesCompile() async throws {
        try await MainActor.run {
            try D3D11BatchRenderer.validateBatchShadersForTesting()
        }
    }

    func testBatchRenderBackendProtocolExists() async throws {
        await MainActor.run {
            let renderer = D3D11BatchRenderer()
            XCTAssertFalse(renderer.isAttached)
            XCTAssertEqual(renderer.backendDisplayName, "D3D11 BATCH")

            // Verify protocol conformance
            let _: any BatchRenderBackend = renderer
        }
    }

    func testGPUISceneConstruction() {
        var scene = GPUIScene(clearColor: .white)
        XCTAssertEqual(scene.layers.count, 1)
        XCTAssertEqual(scene.clearColor, .white)

        scene.pushLayer()
        XCTAssertEqual(scene.layers.count, 2)
    }

    func testGPUISceneWithQuads() {
        var scene = GPUIScene()
        scene.addQuad(
            QuadPrimitive(
                x: 10, y: 20, width: 100, height: 50,
                cornerRadius: 5,
                startR: 1, startG: 0, startB: 0, startA: 1,
                endR: 0, endG: 0, endB: 1, endA: 1,
                gradientAxis: 1
            )
        )
        scene.addQuad(
            QuadPrimitive(
                x: 200, y: 300, width: 80, height: 40,
                startR: 0, startG: 1, startB: 0, startA: 1,
                endR: 0, endG: 1, endB: 0, endA: 1
            )
        )

        XCTAssertEqual(scene.layers[0].quads.count, 2)
        XCTAssertEqual(scene.layers[0].quads[0].cornerRadius, 5)
        XCTAssertEqual(scene.layers[0].quads[1].x, 200)
    }

    func testGPUISceneWithShadows() {
        var scene = GPUIScene()
        scene.addShadow(
            ShadowPrimitive(
                x: 50, y: 50, width: 200, height: 100,
                cornerRadius: 8,
                colorR: 0, colorG: 0, colorB: 0, colorA: 0.3,
                blurRadius: 12,
                offsetX: 2, offsetY: 4
            )
        )

        XCTAssertEqual(scene.layers[0].shadows.count, 1)
        XCTAssertEqual(scene.layers[0].shadows[0].blurRadius, 12)
    }

    func testGPUISceneWithImages() {
        var scene = GPUIScene()
        scene.addImage(
            ImagePrimitive(
                screenX: 0, screenY: 0, screenW: 256, screenH: 256,
                uvX: 0, uvY: 0, uvW: 1, uvH: 1,
                opacity: 0.8,
                textureID: 0
            )
        )

        XCTAssertEqual(scene.layers[0].images.count, 1)
        XCTAssertEqual(scene.layers[0].images[0].opacity, 0.8, accuracy: 0.001)
    }

    func testGPUISceneWithGlyphs() {
        var scene = GPUIScene()
        scene.addGlyph(
            GlyphPrimitive(
                screenX: 10, screenY: 20, screenW: 8, screenH: 16,
                atlasU0: 0, atlasV0: 0, atlasU1: 0.1, atlasV1: 0.2,
                colorR: 1, colorG: 1, colorB: 1, colorA: 1
            )
        )

        XCTAssertEqual(scene.layers[0].glyphs.count, 1)
        XCTAssertEqual(scene.layers[0].glyphs[0].screenW, 8)
    }

    func testQuadPrimitiveStride() {
        // QuadPrimitive should be 112 bytes (28 floats * 4 bytes)
        XCTAssertEqual(MemoryLayout<QuadPrimitive>.stride, 112)
    }

    func testGlyphPrimitiveStride() {
        // GlyphPrimitive should be 64 bytes (16 floats * 4 bytes)
        XCTAssertEqual(MemoryLayout<GlyphPrimitive>.stride, 64)
    }

    func testShadowPrimitiveStride() {
        // ShadowPrimitive should be 64 bytes (16 floats * 4 bytes)
        XCTAssertEqual(MemoryLayout<ShadowPrimitive>.stride, 64)
    }

    func testImagePrimitiveStride() {
        // ImagePrimitive should be 64 bytes (16 fields * 4 bytes)
        XCTAssertEqual(MemoryLayout<ImagePrimitive>.stride, 64)
    }

    func testMultiLayerScene() {
        var scene = GPUIScene()
        scene.addQuad(
            QuadPrimitive(
                x: 0, y: 0, width: 800, height: 600,
                startR: 0.1, startG: 0.1, startB: 0.2, startA: 1,
                endR: 0.1, endG: 0.1, endB: 0.2, endA: 1
            )
        )

        let overlayLayer = scene.pushLayer()
        scene.addShadow(
            ShadowPrimitive(x: 100, y: 100, width: 200, height: 150),
            toLayer: overlayLayer
        )
        scene.addQuad(
            QuadPrimitive(
                x: 100, y: 100, width: 200, height: 150,
                cornerRadius: 10,
                startR: 1, startG: 1, startB: 1, startA: 1,
                endR: 1, endG: 1, endB: 1, endA: 1
            ),
            toLayer: overlayLayer
        )

        XCTAssertEqual(scene.layers.count, 2)
        XCTAssertEqual(scene.layers[0].quads.count, 1)
        XCTAssertEqual(scene.layers[1].shadows.count, 1)
        XCTAssertEqual(scene.layers[1].quads.count, 1)
    }

    func testRejectsUnresolvedImagePrimitivesBeforeRender() async throws {
        try await MainActor.run {
            var scene = GPUIScene()
            scene.addImage(
                ImagePrimitive(
                    screenX: 0, screenY: 0, screenW: 32, screenH: 32,
                    uvX: 0, uvY: 0, uvW: 1, uvH: 1,
                    opacity: 1,
                    clipX: 0, clipY: 0, clipWidth: 32, clipHeight: 32,
                    textureID: -1
                )
            )

            XCTAssertThrowsError(try D3D11BatchRenderer.makeRenderPlan(for: scene)) { error in
                guard let batchError = error as? BatchRendererError else {
                    return XCTFail("Expected BatchRendererError, got \(error)")
                }

                XCTAssertEqual(batchError.operation, "Resolve image resources")
                XCTAssertTrue(batchError.description.contains("-1"))
            }
        }
    }

    func testBatchTextPresentationSurvivesAtlasFreeCachedSceneReplay() async throws {
        try await MainActor.run {
            var firstScene = GPUIScene()
            firstScene.addGlyph(
                GlyphPrimitive(
                    screenX: 8, screenY: 12, screenW: 10, screenH: 14,
                    atlasU0: 0, atlasV0: 0, atlasU1: 1, atlasV1: 1,
                    colorR: 1, colorG: 1, colorB: 1, colorA: 1
                )
            )
            firstScene.glyphAtlas = Self.makeGlyphAtlasSnapshot()

            let firstPlan = try D3D11BatchRenderer.makeRenderPlan(for: firstScene)
            XCTAssertEqual(firstPlan.glyphAtlasSource, .snapshot)
            XCTAssertEqual(
                firstPlan.steps,
                [
                    .glyphs(layerIndex: 0, range: 0..<1, atlasSource: .snapshot)
                ])

            var cachedScene = firstScene
            cachedScene.glyphAtlas = nil
            let cachedPlan = try D3D11BatchRenderer.makeRenderPlan(
                for: cachedScene,
                cachedResources: firstPlan.resultingResources
            )

            XCTAssertEqual(cachedPlan.glyphAtlasSource, .cached)
            XCTAssertEqual(
                cachedPlan.steps,
                [
                    .glyphs(layerIndex: 0, range: 0..<1, atlasSource: .cached)
                ])
        }
    }

    func testRenderPlanPreservesPaintOperationOrderAcrossPrimitiveFamilies() async throws {
        try await MainActor.run {
            var scene = GPUIScene()
            scene.addQuad(QuadPrimitive(x: 0, y: 0, width: 24, height: 24))
            scene.addGlyph(
                GlyphPrimitive(
                    screenX: 4, screenY: 4, screenW: 8, screenH: 8,
                    atlasU0: 0, atlasV0: 0, atlasU1: 1, atlasV1: 1,
                    colorR: 1, colorG: 1, colorB: 1, colorA: 1
                )
            )
            scene.addQuad(QuadPrimitive(x: 48, y: 0, width: 24, height: 24))
            scene.glyphAtlas = Self.makeGlyphAtlasSnapshot()
            scene.finish()

            let plan = try D3D11BatchRenderer.makeRenderPlan(for: scene)

            XCTAssertEqual(
                plan.steps,
                [
                    .quads(layerIndex: 0, range: 0..<1),
                    .glyphs(layerIndex: 0, range: 0..<1, atlasSource: .snapshot),
                    .quads(layerIndex: 0, range: 1..<2),
                ])
        }
    }

    func testImageRenderPlanUsesBoundTextureRunsAndPreservesClipOpacity() async throws {
        try await MainActor.run {
            let renderer = D3D11BatchRenderer()
            renderer.bindImageResource(Self.makeBitmapSurface(fill: 255), for: 7)
            renderer.bindImageResource(Self.makeBitmapSurface(fill: 128), for: 9)

            var scene = GPUIScene()
            scene.addImage(
                ImagePrimitive(
                    screenX: 0, screenY: 0, screenW: 32, screenH: 32,
                    uvX: 0, uvY: 0, uvW: 1, uvH: 1,
                    opacity: 0.25,
                    clipX: 2, clipY: 4, clipWidth: 20, clipHeight: 18,
                    textureID: 7
                )
            )
            scene.addImage(
                ImagePrimitive(
                    screenX: 40, screenY: 0, screenW: 32, screenH: 32,
                    uvX: 0, uvY: 0, uvW: 1, uvH: 1,
                    opacity: 0.5,
                    clipX: 40, clipY: 0, clipWidth: 32, clipHeight: 32,
                    textureID: 7
                )
            )
            scene.addImage(
                ImagePrimitive(
                    screenX: 80, screenY: 0, screenW: 32, screenH: 32,
                    uvX: 0, uvY: 0, uvW: 1, uvH: 1,
                    opacity: 0.75,
                    clipX: 80, clipY: 0, clipWidth: 32, clipHeight: 32,
                    textureID: 9
                )
            )

            let plan = try D3D11BatchRenderer.makeRenderPlan(
                for: scene,
                cachedResources: renderer.cachedResourcesForTesting
            )

            XCTAssertEqual(
                plan.steps,
                [
                    .images(layerIndex: 0, range: 0..<2, textureID: 7),
                    .images(layerIndex: 0, range: 2..<3, textureID: 9),
                ])
            XCTAssertEqual(scene.layers[0].images[0].opacity, 0.25, accuracy: 0.001)
            XCTAssertEqual(scene.layers[0].images[0].clipX, 2, accuracy: 0.001)
            XCTAssertEqual(scene.layers[0].images[0].clipWidth, 20, accuracy: 0.001)
            XCTAssertEqual(scene.layers[0].images[1].opacity, 0.5, accuracy: 0.001)
            XCTAssertEqual(scene.layers[0].images[1].clipX, 40, accuracy: 0.001)
            XCTAssertEqual(scene.layers[0].images[2].opacity, 0.75, accuracy: 0.001)
            XCTAssertEqual(scene.layers[0].images[2].clipHeight, 32, accuracy: 0.001)
        }
    }

    func testBridgedImageResourcesBindBeforeRenderPlanValidation() async throws {
        try await MainActor.run {
            let bitmap = Self.makeBitmapSurface(fill: 200)
            let frame = RenderFrame(
                clearColor: .black,
                commands: [
                    .drawBitmap(
                        DrawBitmapCommand(
                            rect: Rect(x: 0, y: 0, width: 32, height: 32),
                            bitmap: bitmap,
                            opacity: 0.4
                        )),
                    .drawBitmap(
                        DrawBitmapCommand(
                            rect: Rect(x: 40, y: 0, width: 16, height: 16),
                            bitmap: bitmap,
                            opacity: 0.9,
                            clipRect: Rect(x: 40, y: 0, width: 8, height: 16)
                        )),
                ]
            )
            let scene = GPUIScene(from: frame, surfaceSize: Size(width: 128, height: 128))
            XCTAssertEqual(
                scene.imageResources,
                [
                    ImageResourceBinding(textureID: 0, bitmap: bitmap)
                ])

            let renderer = D3D11BatchRenderer()
            renderer.bindResources(for: scene)

            let plan = try D3D11BatchRenderer.makeRenderPlan(
                for: scene,
                cachedResources: renderer.cachedResourcesForTesting
            )

            XCTAssertEqual(
                plan.steps,
                [
                    .images(layerIndex: 0, range: 0..<2, textureID: 0)
                ])
            XCTAssertEqual(scene.layers[0].images[0].opacity, 0.4, accuracy: 0.001)
            XCTAssertEqual(scene.layers[0].images[1].opacity, 0.9, accuracy: 0.001)
            XCTAssertEqual(scene.layers[0].images[1].clipWidth, 8, accuracy: 0.001)
        }
    }

    func testGPUISceneWithPaths() {
        var scene = GPUIScene()
        scene.addPath(
            PathPrimitive(
                elements: [
                    .moveTo(Point(x: 10, y: 10)),
                    .lineTo(Point(x: 30, y: 10)),
                    .lineTo(Point(x: 20, y: 30)),
                    .close,
                ],
                bounds: Rect(x: 10, y: 10, width: 20, height: 20),
                fillColor: .red,
                clipBounds: nil
            ),
            toLayer: 0
        )

        XCTAssertEqual(scene.layers[0].paths.count, 1)
        XCTAssertEqual(scene.layers[0].paths[0].fillColor, .red)
    }

    func testRenderPlanIncludesPaths() async throws {
        try await MainActor.run {
            var scene = GPUIScene()
            scene.addPath(
                PathPrimitive(
                    elements: [
                        .moveTo(Point(x: 10, y: 10)),
                        .lineTo(Point(x: 30, y: 10)),
                        .lineTo(Point(x: 20, y: 30)),
                        .close,
                    ],
                    bounds: Rect(x: 10, y: 10, width: 20, height: 20),
                    fillColor: .red,
                    clipBounds: nil
                ),
                toLayer: 0
            )

            let plan = try D3D11BatchRenderer.makeRenderPlan(for: scene)
            XCTAssertEqual(
                plan.steps,
                [
                    .paths(layerIndex: 0, range: 0..<1)
                ])
        }
    }

    func testRasterizePathProducesNonEmptyBitmap() {
        let path = PathPrimitive(
            elements: [
                .moveTo(Point(x: 10, y: 10)),
                .lineTo(Point(x: 30, y: 10)),
                .lineTo(Point(x: 20, y: 30)),
                .close,
            ],
            bounds: Rect(x: 10, y: 10, width: 20, height: 20),
            fillColor: Color(red: 0, green: 1, blue: 0, alpha: 1),
            clipBounds: nil
        )

        guard let bitmap = GPUIRawSceneRasterizer.rasterizePath(path) else {
            XCTFail("Expected non-nil bitmap")
            return
        }

        XCTAssertEqual(bitmap.width, 20)
        XCTAssertEqual(bitmap.height, 20)

        // Center pixel inside the triangle should be green (BGRA: 0, 255, 0, 255)
        let centerOffset = (10 * 20 + 10) * 4
        XCTAssertEqual(bitmap.pixels[centerOffset], 0)  // B
        XCTAssertEqual(bitmap.pixels[centerOffset + 1], 255)  // G
        XCTAssertEqual(bitmap.pixels[centerOffset + 2], 0)  // R
        XCTAssertEqual(bitmap.pixels[centerOffset + 3], 255)  // A
    }

    func testRasterizePathWithStrokeProducesBitmap() {
        let path = PathPrimitive(
            elements: [
                .moveTo(Point(x: 10, y: 20)),
                .lineTo(Point(x: 30, y: 20)),
            ],
            bounds: Rect(x: 10, y: 19, width: 20, height: 2),
            strokeColor: Color(red: 1, green: 0, blue: 0, alpha: 1),
            lineWidth: 2,
            clipBounds: nil
        )

        guard let bitmap = GPUIRawSceneRasterizer.rasterizePath(path) else {
            XCTFail("Expected non-nil bitmap")
            return
        }

        // Midpoint should be red
        let midOffset = (1 * 20 + 10) * 4
        XCTAssertEqual(bitmap.pixels[midOffset], 0)  // B
        XCTAssertEqual(bitmap.pixels[midOffset + 1], 0)  // G
        XCTAssertEqual(bitmap.pixels[midOffset + 2], 255)  // R
        XCTAssertEqual(bitmap.pixels[midOffset + 3], 255)  // A
    }
}
