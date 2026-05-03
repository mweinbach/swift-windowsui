import XCTest
import SwiftWindowsCore
import SwiftWindowsGraphics
@testable import SwiftWindowsRendererD3D11

final class D3D11BatchRendererTests: XCTestCase {
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
            XCTAssertEqual(renderer.primitiveCapabilities, D3D11BatchRenderer.currentPrimitiveCapabilities)

            // Verify protocol conformance
            let _: any BatchRenderBackend = renderer
            let _: any RenderBackend = renderer
        }
    }

    func testBatchRendererReportsCurrentPrimitiveCoverage() async throws {
        await MainActor.run {
            let capabilities = D3D11BatchRenderer().primitiveCapabilities

            XCTAssertTrue(capabilities.shadows)
            XCTAssertTrue(capabilities.quads)
            XCTAssertFalse(capabilities.glyphs)
            XCTAssertTrue(capabilities.images)
            XCTAssertEqual(capabilities.supportedPrimitiveNames, ["shadows", "quads", "images"])
            XCTAssertEqual(capabilities.unsupportedPrimitiveNames, ["glyphs"])
        }
    }

    func testImagePrimitiveRunsPreserveTextureOrder() {
        let images = [
            ImagePrimitive(textureID: 2),
            ImagePrimitive(textureID: 2),
            ImagePrimitive(textureID: 5),
            ImagePrimitive(textureID: 2),
            ImagePrimitive(textureID: 2),
            ImagePrimitive(textureID: 9),
        ]

        XCTAssertEqual(
            imagePrimitiveRuns(images),
            [
                ImagePrimitiveRun(textureID: 2, range: 0..<2),
                ImagePrimitiveRun(textureID: 5, range: 2..<3),
                ImagePrimitiveRun(textureID: 2, range: 3..<5),
                ImagePrimitiveRun(textureID: 9, range: 5..<6),
            ]
        )
    }

    func testBatchPrimitiveCapabilitiesCountSupportedAndUnsupportedSceneWork() {
        var scene = GPUIScene()
        scene.addShadow(ShadowPrimitive(x: 0, y: 0, width: 24, height: 16))
        scene.addQuad(QuadPrimitive(x: 0, y: 0, width: 24, height: 16))
        scene.addGlyph(GlyphPrimitive(screenX: 2, screenY: 4, screenW: 8, screenH: 12))
        scene.addImage(ImagePrimitive(screenX: 4, screenY: 8, screenW: 16, screenH: 16))

        let capabilities = BatchPrimitiveCapabilities(
            shadows: true,
            quads: true,
            glyphs: false,
            images: false
        )
        let supported = capabilities.supportedPrimitiveCounts(in: scene)
        let unsupported = capabilities.unsupportedPrimitiveCounts(in: scene)

        XCTAssertEqual(supported, BatchPrimitiveCounts(shadows: 1, quads: 1))
        XCTAssertEqual(supported.total, 2)
        XCTAssertEqual(unsupported, BatchPrimitiveCounts(glyphs: 1, images: 1))
        XCTAssertEqual(unsupported.total, 2)
    }

    func testBatchRendererCanAcceptRenderFramesBeforeAttach() async throws {
        try await MainActor.run {
            let renderer = D3D11BatchRenderer()
            let frame = RenderFrame(
                clearColor: .black,
                commands: [
                    .fillRect(FillRectCommand(
                        rect: Rect(x: 0, y: 0, width: 10, height: 10),
                        color: .white
                    )),
                ]
            )

            try renderer.render(frame: frame)
            XCTAssertEqual(renderer.backendStatusDescription, "D3D11 BATCH READY")
        }
    }

    func testBatchFrameUniformsUseLogicalSurfaceSizeAndScale() {
        let uniforms = makeBatchFrameUniforms(
            pixelSize: IntSize(width: 900, height: 600),
            scaleFactor: 1.5
        )

        XCTAssertEqual(uniforms.surfaceWidth, 600)
        XCTAssertEqual(uniforms.surfaceHeight, 400)
        XCTAssertEqual(uniforms.scaleFactor, 1.5, accuracy: 0.001)
        XCTAssertEqual(uniforms.pad0, 0)
    }

    func testBatchFrameUniformsClampInvalidScaleToOne() {
        let uniforms = makeBatchFrameUniforms(
            pixelSize: IntSize(width: 320, height: 180),
            scaleFactor: 0
        )

        XCTAssertEqual(uniforms.surfaceWidth, 320)
        XCTAssertEqual(uniforms.surfaceHeight, 180)
        XCTAssertEqual(uniforms.scaleFactor, 1)
    }

    func testBatchFrameUniformStride() {
        // Four floats keep the D3D11 constant buffer aligned to 16 bytes.
        XCTAssertEqual(MemoryLayout<BatchFrameUniforms>.stride, 16)
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
        scene.layers[0].quads.append(
            QuadPrimitive(
                x: 10, y: 20, width: 100, height: 50,
                cornerRadius: 5,
                startR: 1, startG: 0, startB: 0, startA: 1,
                endR: 0, endG: 0, endB: 1, endA: 1,
                gradientAxis: 1
            )
        )
        scene.layers[0].quads.append(
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
        scene.layers[0].shadows.append(
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
        scene.layers[0].images.append(
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
        scene.layers[0].glyphs.append(
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
        // QuadPrimitive should be 80 bytes (20 floats * 4 bytes)
        XCTAssertEqual(MemoryLayout<QuadPrimitive>.stride, 80)
    }

    func testGlyphPrimitiveStride() {
        // GlyphPrimitive should be 48 bytes (12 floats * 4 bytes)
        XCTAssertEqual(MemoryLayout<GlyphPrimitive>.stride, 48)
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
        scene.layers[0].quads.append(
            QuadPrimitive(
                x: 0, y: 0, width: 800, height: 600,
                startR: 0.1, startG: 0.1, startB: 0.2, startA: 1,
                endR: 0.1, endG: 0.1, endB: 0.2, endA: 1
            )
        )

        scene.pushLayer()
        scene.layers[1].shadows.append(
            ShadowPrimitive(x: 100, y: 100, width: 200, height: 150)
        )
        scene.layers[1].quads.append(
            QuadPrimitive(
                x: 100, y: 100, width: 200, height: 150,
                cornerRadius: 10,
                startR: 1, startG: 1, startB: 1, startA: 1,
                endR: 1, endG: 1, endB: 1, endA: 1
            )
        )

        XCTAssertEqual(scene.layers.count, 2)
        XCTAssertEqual(scene.layers[0].quads.count, 1)
        XCTAssertEqual(scene.layers[1].shadows.count, 1)
        XCTAssertEqual(scene.layers[1].quads.count, 1)
    }
}
