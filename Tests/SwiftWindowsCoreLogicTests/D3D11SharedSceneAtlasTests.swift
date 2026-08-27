import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsRendererD3D11

/// Scene-backed images borrow an already uploaded atlas through every parent
/// namespace. This fixture needs four atlas bytes and only tiny render targets.
@MainActor
final class D3D11SharedSceneAtlasTests: XCTestCase {
    func testNestedImageSourcesBorrowOneSharedAtlasAcrossFrames() async throws {
        let size = IntSize(width: 12, height: 4)
        let atlas = GlyphAtlasSnapshot(
            width: 1, height: 1, pixels: Data([255, 255, 255, 255]),
            contentVersion: RenderContentVersion.next(), update: .full)
        let scene = makeNestedGlyphScene(atlas: atlas)
        XCTAssertTrue(scene.validate().isEmpty)
        XCTAssertFalse(scene.usesGlyphs, "The root must exercise atlas preload without a direct glyph draw")
        XCTAssertTrue(scene.imageResources.isEmpty)
        let intermediate = try XCTUnwrap(scene.imageRenderPasses.first?.scene)
        XCTAssertFalse(intermediate.usesGlyphs, "An image-only ancestor must preserve the borrowed atlas too")
        XCTAssertEqual(intermediate.imageRenderPasses.count, 3)
        XCTAssertTrue(intermediate.imageRenderPasses.allSatisfy { $0.scene.usesGlyphs })

        let plan = try D3D11BatchRenderer.makeRenderPlan(for: scene)
        XCTAssertNil(plan.glyphAtlasSource)
        XCTAssertTrue(plan.resultingResources.hasGlyphAtlas)
        XCTAssertEqual(plan.steps.count, 1)

        let renderer = try makeDedicatedRenderer(size: size)
        defer { renderer.detach() }
        renderer.bindResources(for: scene)
        try renderer.render(scene: scene)

        // The root retains the producer's forced-full update. Descendants
        // share its finalized pixels/version with unchanged update metadata,
        // so the middle namespace and all three leaf sources borrow it.
        XCTAssertEqual(renderer.atlasFullUploadsForTesting, 1)
        XCTAssertEqual(renderer.atlasRegionUploadsForTesting, 0)
        XCTAssertEqual(renderer.atlasUploadedByteCount, 4)
        XCTAssertGreaterThanOrEqual(renderer.atlasSkippedUploadsForTesting, 4)
        XCTAssertTrue(renderer.cachedResourcesForTesting.hasGlyphAtlas)
        XCTAssertEqual(renderer.imageTextureUploadsForTesting, 0)

        let cpu = GPUIRawSceneRasterizer.rasterize(scene, size: size).premultipliedAlpha()
        let first = try renderer.readOffscreenPixels()
        assertColorBands(cpu)
        assertColorBands(first)
        XCTAssertEqual(first.pixels, cpu.pixels)
        let warmedObjectCount = renderer.liveCOMObjectCountForTesting
        let skippedAfterFirstFrame = renderer.atlasSkippedUploadsForTesting

        var unchangedScene = scene
        unchangedScene.glyphAtlas?.update = .unchanged
        renderer.bindResources(for: unchangedScene)
        try renderer.render(scene: unchangedScene)
        let second = try renderer.readOffscreenPixels()
        XCTAssertEqual(second.pixels, first.pixels)
        XCTAssertEqual(renderer.atlasFullUploadsForTesting, 1)
        XCTAssertEqual(renderer.atlasRegionUploadsForTesting, 0)
        XCTAssertEqual(renderer.atlasUploadedByteCount, 4)
        XCTAssertGreaterThanOrEqual(renderer.atlasSkippedUploadsForTesting - skippedAfterFirstFrame, 5)
        XCTAssertEqual(renderer.liveCOMObjectCountForTesting, warmedObjectCount)
        XCTAssertTrue(renderer.cachedResourcesForTesting.hasGlyphAtlas)
        XCTAssertEqual(renderer.imageTextureUploadsForTesting, 0)
    }

    func testAChildWithAnotherAtlasVersionCannotChangeLaterSiblingGlyphs() async throws {
        let size = IntSize(width: 12, height: 4)
        let atlas = GlyphAtlasSnapshot(
            width: 1, height: 1, pixels: Data([255, 255, 255, 255]),
            contentVersion: RenderContentVersion.next(), update: .full)
        var scene = makeNestedGlyphScene(atlas: atlas)
        scene.imageRenderPasses[0].scene.imageRenderPasses[1].scene.glyphAtlas = GlyphAtlasSnapshot(
            width: 1, height: 1, pixels: Data([0, 0, 0, 0]),
            contentVersion: RenderContentVersion.next(), update: .unchanged)
        XCTAssertTrue(scene.validate().isEmpty)

        let renderer = try makeDedicatedRenderer(size: size)
        defer { renderer.detach() }
        renderer.bindResources(for: scene)
        try renderer.render(scene: scene)

        // The transparent second atlas needs its own four-byte upload. Its
        // child target paints nothing, but the third sibling must still see
        // the parent's opaque atlas after that temporary slot is released.
        XCTAssertEqual(renderer.atlasFullUploadsForTesting, 2)
        XCTAssertEqual(renderer.atlasRegionUploadsForTesting, 0)
        XCTAssertEqual(renderer.atlasUploadedByteCount, 8)
        XCTAssertGreaterThanOrEqual(renderer.atlasSkippedUploadsForTesting, 3)
        XCTAssertTrue(renderer.cachedResourcesForTesting.hasGlyphAtlas)
        let cpu = GPUIRawSceneRasterizer.rasterize(scene, size: size).premultipliedAlpha()
        let actual = try renderer.readOffscreenPixels()
        assertColorBands(cpu, greenIsVisible: false)
        assertColorBands(actual, greenIsVisible: false)
        XCTAssertEqual(actual.pixels, cpu.pixels)
        let warmedObjectCount = renderer.liveCOMObjectCountForTesting

        var restoredScene = makeNestedGlyphScene(atlas: atlas)
        restoredScene.glyphAtlas?.update = .unchanged
        renderer.bindResources(for: restoredScene)
        try renderer.render(scene: restoredScene)
        assertColorBands(try renderer.readOffscreenPixels())
        XCTAssertEqual(renderer.atlasFullUploadsForTesting, 2)
        XCTAssertEqual(renderer.atlasUploadedByteCount, 8)
        XCTAssertEqual(renderer.liveCOMObjectCountForTesting, warmedObjectCount)
    }

    private func makeNestedGlyphScene(atlas: GlyphAtlasSnapshot) -> GPUIScene {
        let glyphSize = IntSize(width: 4, height: 4)
        var childAtlas = atlas
        childAtlas.update = .unchanged
        var intermediate = GPUIScene(clearColor: .clear, glyphAtlas: childAtlas)
        for index in 0..<3 {
            var leaf = GPUIScene(clearColor: .clear, glyphAtlas: childAtlas)
            leaf.addGlyph(
                GlyphPrimitive(
                    screenW: 4, screenH: 4,
                    atlasU0: 0, atlasV0: 0, atlasU1: 1, atlasV1: 1,
                    colorR: index == 0 ? 1 : 0,
                    colorG: index == 1 ? 1 : 0,
                    colorB: index == 2 ? 1 : 0, colorA: 1))
            leaf.finish()
            let textureID = intermediate.registerImageRenderPass(leaf, size: glyphSize)
            intermediate.addImage(
                ImagePrimitive(screenX: Float(index * 4), screenW: 4, screenH: 4, textureID: textureID))
        }
        intermediate.finish()

        var scene = GPUIScene(clearColor: .black, glyphAtlas: atlas)
        let textureID = scene.registerImageRenderPass(
            intermediate, size: IntSize(width: 12, height: 4), colorEffects: [.brightness(0)])
        scene.addImage(ImagePrimitive(screenW: 12, screenH: 4, textureID: textureID))
        scene.finish()
        return scene
    }

    private func makeDedicatedRenderer(size: IntSize) throws -> D3D11BatchRenderer {
        let renderer = D3D11BatchRenderer()
        do {
            try renderer.attachOffscreen(size: size, driver: .warpFirst)
        } catch {
            renderer.detach()
            throw XCTSkip("D3D11 batch renderer unavailable on this machine: \(error)")
        }
        return renderer
    }

    private func assertColorBands(
        _ bitmap: BitmapSurface, greenIsVisible: Bool = true,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(bitmap.width, 12, file: file, line: line)
        XCTAssertEqual(bitmap.height, 4, file: file, line: line)
        for y in 0..<4 {
            for x in 0..<12 {
                let offset = y * Int(bitmap.bytesPerRow) + x * 4
                XCTAssertEqual(bitmap.pixels[offset], x >= 8 ? 255 : 0, file: file, line: line)
                XCTAssertEqual(
                    bitmap.pixels[offset + 1], greenIsVisible && (4..<8).contains(x) ? 255 : 0,
                    file: file, line: line)
                XCTAssertEqual(bitmap.pixels[offset + 2], x < 4 ? 255 : 0, file: file, line: line)
                XCTAssertEqual(bitmap.pixels[offset + 3], 255, file: file, line: line)
            }
        }
    }
}
