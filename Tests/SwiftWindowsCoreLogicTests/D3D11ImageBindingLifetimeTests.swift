import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsRendererD3D11

/// Scene texture IDs are frame-local; their content-keyed GPU textures are
/// reusable, but a removed scene binding must not retain pixels indefinitely.
@MainActor
final class D3D11ImageBindingLifetimeTests: XCTestCase {
    private static let surfaceSize = IntSize(width: 24, height: 24)

    func testSceneResourceRemovalPreservesIndependentManualBindings() async {
        let renderer = D3D11BatchRenderer()
        renderer.bindImageResource(makeBitmap(red: 10), for: 90)

        var firstScene = GPUIScene(clearColor: .black)
        firstScene.bindImageResource(makeBitmap(red: 20), for: 11)
        firstScene.bindImageResource(makeBitmap(red: 30), for: 12)
        renderer.bindResources(for: firstScene)

        XCTAssertEqual(renderer.cachedResourcesForTesting.boundImageTextureIDs, Set<Int32>([11, 12, 90]))

        var secondScene = GPUIScene(clearColor: .black)
        secondScene.bindImageResource(makeBitmap(red: 40), for: 11)
        renderer.bindResources(for: secondScene)

        XCTAssertEqual(renderer.cachedResourcesForTesting.boundImageTextureIDs, Set<Int32>([11, 90]))

        renderer.bindResources(for: GPUIScene(clearColor: .black))

        XCTAssertEqual(renderer.cachedResourcesForTesting.boundImageTextureIDs, Set<Int32>([90]))
    }

    func testSceneCannotRenderAnImageUsingAPreviousFramesMissingBinding() async throws {
        let renderer = try makeOwnedRenderer()
        defer { renderer.detach() }

        let firstScene = makeImageScene(bitmaps: [makeBitmap(red: 220)])
        renderer.bindResources(for: firstScene)
        try renderer.render(scene: firstScene)

        var missingBindingScene = GPUIScene(clearColor: .black)
        missingBindingScene.addImage(
            ImagePrimitive(screenX: 0, screenY: 0, screenW: 12, screenH: 12, opacity: 1, textureID: 0)
        )
        renderer.bindResources(for: missingBindingScene)

        XCTAssertFalse(renderer.cachedResourcesForTesting.boundImageTextureIDs.contains(0))
        XCTAssertThrowsError(try renderer.render(scene: missingBindingScene)) { error in
            guard let rendererError = error as? BatchRendererError else {
                return XCTFail("Expected a typed missing-resource error, got \(error)")
            }
            XCTAssertEqual(rendererError.operation, "Resolve image resources")
            XCTAssertEqual(rendererError.presentationFailureKind, .sceneContent)
        }
    }

    func testRemovedSceneImagesReleaseCachedTexturesOnTheNextFrame() async throws {
        let renderer = try makeOwnedRenderer()
        defer { renderer.detach() }

        let firstScene = makeImageScene(bitmaps: [makeBitmap(red: 80), makeBitmap(red: 160)])
        renderer.bindResources(for: firstScene)
        try renderer.render(scene: firstScene)

        XCTAssertEqual(renderer.imageTextureCacheCountForTesting, 2)
        XCTAssertEqual(renderer.imageTextureUploadsForTesting, 2)

        let emptyScene = GPUIScene(clearColor: .black)
        renderer.bindResources(for: emptyScene)

        XCTAssertTrue(renderer.cachedResourcesForTesting.boundImageTextureIDs.isEmpty)
        XCTAssertEqual(
            renderer.imageTextureCacheCountForTesting, 2,
            "Texture reclamation waits until every current-frame binding has been synchronized"
        )

        try renderer.render(scene: emptyScene)

        XCTAssertEqual(renderer.imageTextureCacheCountForTesting, 0)
        XCTAssertEqual(renderer.imageTextureUploadsForTesting, 2)
    }

    func testRemovingAnImagePreservesARenumberedSurvivorsExistingTexture() async throws {
        let renderer = try makeOwnedRenderer()
        defer { renderer.detach() }

        let removed = makeBitmap(red: 40)
        let surviving = makeBitmap(red: 200)
        let firstScene = makeImageScene(bitmaps: [removed, surviving])
        renderer.bindResources(for: firstScene)
        try renderer.render(scene: firstScene)

        let originalTexture = try XCTUnwrap(renderer.imageTextureIdentityForTesting(for: 1)).texture
        XCTAssertEqual(renderer.imageTextureUploadsForTesting, 2)

        let secondScene = makeImageScene(bitmaps: [surviving])
        renderer.bindResources(for: secondScene)
        try renderer.render(scene: secondScene)

        XCTAssertEqual(renderer.cachedResourcesForTesting.boundImageTextureIDs, Set<Int32>([0]))
        XCTAssertEqual(renderer.imageTextureCacheCountForTesting, 1)
        XCTAssertEqual(renderer.imageTextureUploadsForTesting, 2)
        XCTAssertEqual(renderer.imageTextureIdentityForTesting(for: 0)?.texture, originalTexture)
    }

    private func makeOwnedRenderer() throws -> D3D11BatchRenderer {
        let probe = try makeWARPDevice()
        probe.release()

        let renderer = D3D11BatchRenderer()
        do {
            try renderer.attachOffscreen(size: Self.surfaceSize, driver: .warpFirst)
        } catch {
            renderer.detach()
            throw XCTSkip("D3D11 batch renderer unavailable on this machine: \(error)")
        }
        return renderer
    }

    private func makeBitmap(red: UInt8) -> BitmapSurface {
        BitmapSurface(width: 1, height: 1, bytesPerRow: 4, pixels: Data([0, 0, red, 255]))
    }

    private func makeImageScene(bitmaps: [BitmapSurface]) -> GPUIScene {
        var scene = GPUIScene(clearColor: .black)
        for (index, bitmap) in bitmaps.enumerated() {
            let textureID = scene.registerImageResource(bitmap)
            scene.addImage(
                ImagePrimitive(
                    screenX: Float(index * 12), screenY: 0,
                    screenW: 12, screenH: 12,
                    opacity: 1,
                    textureID: textureID
                )
            )
        }
        scene.finish()
        return scene
    }
}
