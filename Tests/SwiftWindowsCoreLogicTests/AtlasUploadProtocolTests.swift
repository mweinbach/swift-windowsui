import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsRendererD3D11
@testable import SwiftWindowsUI

/// The atlas and texture upload protocol: versioned snapshots, explicit
/// texture state, and no redundant uploads.
///
/// Before this protocol existed the dirty region carried three meanings in
/// one optional and the producer and the D3D11 consumer read the middle one
/// in opposite directions: a static text screen re-uploaded the whole
/// 2048×2048×4 = 16 MiB atlas on every frame, and the inverse bug in the
/// same block uploaded *only* a small region into a freshly created texture
/// whose other texels were undefined — a frame of garbage text whenever a
/// second window opened against a warm process-wide atlas.
///
/// Three layers are pinned here: the pure decision table, the producers
/// that version their pixels, and the real D3D11 upload counts on WARP.
final class AtlasUploadProtocolTests: XCTestCase {

    // MARK: - Fixtures

    private static let atlasSide: Int32 = 64

    private static func makeSnapshot(
        contentVersion: UInt64,
        update: AtlasUpdate,
        side: Int32 = atlasSide
    ) -> GlyphAtlasSnapshot {
        GlyphAtlasSnapshot(
            width: side,
            height: side,
            pixels: Data(count: Int(side) * Int(side) * 4),
            contentVersion: contentVersion,
            update: update
        )
    }

    private static func makeState(version: UInt64, side: Int32 = atlasSide) -> AtlasTextureState {
        AtlasTextureState(
            isInitialized: true,
            uploadedVersion: version,
            size: IntSize(width: side, height: side)
        )
    }

    // MARK: - Decision table

    func testAFreshTextureTakesTheFullUploadWhateverTheSnapshotClaims() {
        let unchanged = Self.makeSnapshot(contentVersion: 7, update: .unchanged)
        XCTAssertEqual(
            unchanged.uploadDecision(for: .uninitialized), .full,
            "an uninitialized texture holds nothing that 'unchanged' can be relative to")

        // The size matching is *not* enough: this is the exact shape of the
        // one-frame garbage flash — a brand-new texture of the right size
        // whose texels are undefined.
        let sizedButEmpty = AtlasTextureState(
            isInitialized: false,
            uploadedVersion: 7,
            size: IntSize(width: Self.atlasSide, height: Self.atlasSide)
        )
        XCTAssertEqual(unchanged.uploadDecision(for: sizedButEmpty), .full)

        let region = Self.makeSnapshot(
            contentVersion: 7, update: .region(GlyphAtlasRegion(x: 2, y: 2, width: 4, height: 4), since: 6))
        XCTAssertEqual(
            region.uploadDecision(for: .uninitialized), .full,
            "a partial region into a texture that was never filled must upload the whole atlas")
    }

    func testATextureAlreadyHoldingTheVersionSkips() {
        let unchanged = Self.makeSnapshot(contentVersion: 41, update: .unchanged)
        XCTAssertEqual(unchanged.uploadDecision(for: Self.makeState(version: 41)), .skip)

        // A region snapshot re-offered to a texture that already applied it
        // is also a skip — the version, not the update, is the authority.
        let region = Self.makeSnapshot(
            contentVersion: 41, update: .region(GlyphAtlasRegion(x: 0, y: 0, width: 8, height: 8), since: 40))
        XCTAssertEqual(region.uploadDecision(for: Self.makeState(version: 41)), .skip)
    }

    func testUnchangedIsAClaimAboutThePreviousSnapshotNotAboutEveryTexture() {
        // Two windows share one process-wide atlas. Window A consumed the
        // dirty region, so window B is offered "unchanged" for pixels it
        // never uploaded; it has to take the whole atlas.
        let unchanged = Self.makeSnapshot(contentVersion: 41, update: .unchanged)
        XCTAssertEqual(unchanged.uploadDecision(for: Self.makeState(version: 38)), .full)
    }

    func testARegionAppliesOnlyToTheVersionItWasComputedAgainst() {
        let rect = GlyphAtlasRegion(x: 8, y: 12, width: 16, height: 20)
        let snapshot = Self.makeSnapshot(contentVersion: 41, update: .region(rect, since: 40))

        XCTAssertEqual(
            snapshot.uploadDecision(for: Self.makeState(version: 40)), .region(rect),
            "a texture at the region's base version applies just the region")
        XCTAssertEqual(
            snapshot.uploadDecision(for: Self.makeState(version: 39)), .full,
            "a texture that missed earlier writes must not apply a region that does not contain them")
    }

    func testAResizedAtlasAlwaysUploadsInFull() {
        let snapshot = Self.makeSnapshot(contentVersion: 41, update: .unchanged)
        let differentSize = AtlasTextureState(
            isInitialized: true, uploadedVersion: 41, size: IntSize(width: 32, height: 32))
        XCTAssertEqual(snapshot.uploadDecision(for: differentSize), .full)
    }

    func testAFullUpdateUploadsEvenWhenTheVersionMatches() {
        // `.full` is the "I claim nothing" default; it must never be
        // short-circuited by a version comparison.
        let snapshot = Self.makeSnapshot(contentVersion: 41, update: .full)
        XCTAssertEqual(snapshot.uploadDecision(for: Self.makeState(version: 41)), .full)
    }

    func testAnOutOfBoundsRegionIsClampedOrDegradesToFull() {
        let overhang = Self.makeSnapshot(
            contentVersion: 41,
            update: .region(GlyphAtlasRegion(x: 60, y: 60, width: 100, height: 100), since: 40))
        XCTAssertEqual(
            overhang.uploadDecision(for: Self.makeState(version: 40)),
            .region(GlyphAtlasRegion(x: 60, y: 60, width: 4, height: 4)),
            "a region past the atlas edge is clamped, never handed to UpdateSubresource as-is")

        let outside = Self.makeSnapshot(
            contentVersion: 41,
            update: .region(GlyphAtlasRegion(x: 200, y: 200, width: 8, height: 8), since: 40))
        XCTAssertEqual(
            outside.uploadDecision(for: Self.makeState(version: 40)), .full,
            "a region that clamps to nothing degrades to a full upload, not to a skip")
    }

    func testContentVersionsAreUniqueAcrossProducers() {
        var seen = Set<UInt64>()
        for _ in 0..<64 {
            XCTAssertTrue(seen.insert(RenderContentVersion.next()).inserted)
        }
        XCTAssertFalse(seen.contains(0), "0 stays reserved for 'nothing uploaded yet'")
    }

    // MARK: - Producers

    @MainActor
    func testGlyphAtlasReportsUnchangedUntilSomethingIsWritten() {
        let atlas = GlyphAtlas(width: 64, height: 64)
        let initialVersion = atlas.contentVersion
        XCTAssertEqual(atlas.update, .unchanged)

        let glyph = Data(repeating: 255, count: 4 * 4 * 4)
        atlas.writePixels(glyph, at: 8, y: 8, width: 4, height: 4)
        XCTAssertNotEqual(atlas.contentVersion, initialVersion, "a write must produce a new content version")
        XCTAssertEqual(
            atlas.update, .region(GlyphAtlasRegion(x: 8, y: 8, width: 4, height: 4), since: initialVersion))

        // Consuming the frame's region rebases the next accumulation
        // window without rewinding the version.
        let afterWrite = atlas.contentVersion
        atlas.markClean()
        XCTAssertEqual(atlas.contentVersion, afterWrite)
        XCTAssertEqual(atlas.update, .unchanged)

        atlas.writePixels(glyph, at: 0, y: 0, width: 4, height: 4)
        XCTAssertEqual(
            atlas.update, .region(GlyphAtlasRegion(x: 0, y: 0, width: 4, height: 4), since: afterWrite))
    }

    @MainActor
    func testClearingTheAtlasDemandsAFullUpload() {
        let atlas = GlyphAtlas(width: 64, height: 64)
        atlas.writePixels(Data(repeating: 255, count: 16), at: 0, y: 0, width: 2, height: 2)
        atlas.markClean()
        let beforeClear = atlas.contentVersion

        atlas.clear()
        XCTAssertNotEqual(atlas.contentVersion, beforeClear)
        XCTAssertEqual(
            atlas.update, .full,
            "the shelves moved, so no region describes the difference")
    }

    @MainActor
    func testTwoAtlasesNeverClaimTheSameVersion() {
        // A version is compared by a consumer that does not know which
        // atlas produced it, so per-instance counters would let a small
        // test atlas and the shared one alias each other's textures.
        let first = GlyphAtlas(width: 32, height: 32)
        let second = GlyphAtlas(width: 32, height: 32)
        XCTAssertNotEqual(first.contentVersion, second.contentVersion)

        let glyph = Data(repeating: 255, count: 16)
        first.writePixels(glyph, at: 0, y: 0, width: 2, height: 2)
        second.writePixels(glyph, at: 0, y: 0, width: 2, height: 2)
        XCTAssertNotEqual(first.contentVersion, second.contentVersion)
    }

    @MainActor
    func testARepaintedStaticTextScreenShipsTheSameAtlasVersionTwice() {
        defer { NativeGlyphAtlas.shared.resetForTesting() }
        NativeGlyphAtlas.shared.resetForTesting()

        let node = ViewNode(
            frame: Rect(x: 0, y: 0, width: 200, height: 60),
            text: "STATIC",
            textStyle: PixelTextStyle(
                color: .white, alignment: .leading, verticalAlignment: .top, nativeFontSize: 18)
        )
        let root = ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 60), children: [node])
        let surface = Size(width: 200, height: 60)

        // Painted twice with no replay source, so both passes really walk
        // the text and really ask the atlas for every glyph. The second
        // pass finds all of them cached, writes nothing, and must therefore
        // ship the version the first pass already produced.
        let first = ScenePainter.paint(root: root, clearColor: .black, surfaceSize: surface)
        let second = ScenePainter.paint(root: root, clearColor: .black, surfaceSize: surface)

        XCTAssertTrue(
            second.glyphAtlas != nil || second.pixelGlyphAtlas != nil,
            "the repaint must still ship an atlas, or this test proves nothing")

        if let firstAtlas = first.glyphAtlas, let secondAtlas = second.glyphAtlas {
            XCTAssertEqual(
                firstAtlas.contentVersion, secondAtlas.contentVersion,
                "a repaint that rasterizes no new glyph must not invent a new atlas version")
            XCTAssertEqual(
                secondAtlas.update, .unchanged,
                "the second frame has nothing to upload — this is the 16 MiB/frame that used to ship")
            XCTAssertEqual(
                secondAtlas.uploadDecision(for: secondAtlas.uploadedState), .skip,
                "and a backend already holding it uploads nothing at all")
        }

        if let firstPixel = first.pixelGlyphAtlas, let secondPixel = second.pixelGlyphAtlas {
            XCTAssertEqual(firstPixel.contentVersion, secondPixel.contentVersion)
            XCTAssertEqual(
                secondPixel.update, .unchanged,
                "the pixel font atlas is built once and never written; it used to declare itself "
                    + "fully dirty on every frame")
        }
    }

    // MARK: - D3D11 upload counts

    @MainActor
    private func makeOwnedRenderer(size: IntSize) throws -> D3D11BatchRenderer {
        let probe = try makeWARPDevice()
        probe.release()

        let renderer = D3D11BatchRenderer()
        do {
            try renderer.attachOffscreen(size: size, driver: .warpFirst)
        } catch {
            throw XCTSkip("D3D11 batch renderer unavailable on this machine: \(error)")
        }
        return renderer
    }

    /// A scene drawing one glyph out of a `side`×`side` atlas.
    private static func makeGlyphScene(snapshot: GlyphAtlasSnapshot) -> GPUIScene {
        var scene = GPUIScene(clearColor: .black)
        scene.addGlyph(
            GlyphPrimitive(
                screenX: 4, screenY: 4, screenW: 8, screenH: 8,
                atlasU0: 0, atlasV0: 0, atlasU1: 0.25, atlasV1: 0.25,
                colorR: 1, colorG: 1, colorB: 1, colorA: 1
            )
        )
        scene.glyphAtlas = snapshot
        return scene
    }

    @MainActor
    func testUploadCountsFollowTheProtocolAcrossThreeFrames() async throws {
        let size = IntSize(width: 64, height: 48)
        let renderer = try makeOwnedRenderer(size: size)
        defer { renderer.detach() }

        let baseVersion = RenderContentVersion.next()
        let firstFrame = Self.makeGlyphScene(
            snapshot: Self.makeSnapshot(contentVersion: baseVersion, update: .unchanged))
        try renderer.render(scene: firstFrame)
        XCTAssertEqual(renderer.atlasFullUploadsForTesting, 1, "a fresh texture takes one full upload")
        XCTAssertEqual(renderer.atlasRegionUploadsForTesting, 0)
        XCTAssertEqual(renderer.atlasSkippedUploadsForTesting, 0)

        // Frame 2: the same version, nothing written. This is the frame
        // that used to cost 16 MiB for no visual change.
        try renderer.render(scene: firstFrame)
        XCTAssertEqual(renderer.atlasFullUploadsForTesting, 1)
        XCTAssertEqual(renderer.atlasRegionUploadsForTesting, 0)
        XCTAssertEqual(renderer.atlasSkippedUploadsForTesting, 1)

        // Frame 3: one glyph written, so a boxed upload of just that rect.
        let regionVersion = RenderContentVersion.next()
        let thirdFrame = Self.makeGlyphScene(
            snapshot: Self.makeSnapshot(
                contentVersion: regionVersion,
                update: .region(GlyphAtlasRegion(x: 4, y: 4, width: 8, height: 8), since: baseVersion)))
        try renderer.render(scene: thirdFrame)
        XCTAssertEqual(renderer.atlasFullUploadsForTesting, 1)
        XCTAssertEqual(renderer.atlasRegionUploadsForTesting, 1, "one boxed UpdateSubresource, not a whole atlas")
        XCTAssertEqual(renderer.atlasSkippedUploadsForTesting, 1)
    }

    /// The point of skipping is that the texture already holds the pixels.
    /// A skip that blanked the text would be a far worse bug than the
    /// redundant upload it replaces, so the frames are compared as pixels.
    @MainActor
    func testASkippedUploadStillDrawsTheSameGlyphs() async throws {
        let size = IntSize(width: 64, height: 48)
        let renderer = try makeOwnedRenderer(size: size)
        defer { renderer.detach() }

        // Opaque top-left 16×16 block: the glyph shader samples `.a`, so
        // this is what the quad's UVs read.
        var pixels = Data(count: Int(Self.atlasSide) * Int(Self.atlasSide) * 4)
        for y in 0..<16 {
            for x in 0..<16 {
                let offset = (y * Int(Self.atlasSide) + x) * 4
                pixels[offset] = 255
                pixels[offset + 1] = 255
                pixels[offset + 2] = 255
                pixels[offset + 3] = 255
            }
        }
        let snapshot = GlyphAtlasSnapshot(
            width: Self.atlasSide, height: Self.atlasSide, pixels: pixels,
            contentVersion: RenderContentVersion.next(), update: .unchanged)
        let scene = Self.makeGlyphScene(snapshot: snapshot)

        try renderer.render(scene: scene)
        let uploaded = try renderer.readOffscreenPixels()
        XCTAssertEqual(renderer.atlasFullUploadsForTesting, 1)

        try renderer.render(scene: scene)
        let skipped = try renderer.readOffscreenPixels()
        XCTAssertEqual(renderer.atlasSkippedUploadsForTesting, 1, "the second frame must take the skip branch")

        XCTAssertEqual(uploaded.pixels, skipped.pixels, "a skipped upload must present the same frame")
        // And the frame is not blank: the glyph really drew.
        let centre = (8 * Int(uploaded.bytesPerRow)) + 8 * 4
        XCTAssertGreaterThan(Int(uploaded.pixels[centre]), 200, "the glyph quad must be lit")
    }

    @MainActor
    func testAPartialRegionIntoAFreshTextureUploadsTheWholeAtlas() async throws {
        let size = IntSize(width: 64, height: 48)
        let renderer = try makeOwnedRenderer(size: size)
        defer { renderer.detach() }

        // The multi-window / device-reset case: the atlas is warm, so its
        // first snapshot for *this* renderer describes a small region, but
        // this renderer's texture does not exist yet.
        let scene = Self.makeGlyphScene(
            snapshot: Self.makeSnapshot(
                contentVersion: RenderContentVersion.next(),
                update: .region(GlyphAtlasRegion(x: 2, y: 2, width: 4, height: 4), since: 1)))
        try renderer.render(scene: scene)

        XCTAssertEqual(renderer.atlasFullUploadsForTesting, 1)
        XCTAssertEqual(
            renderer.atlasRegionUploadsForTesting, 0,
            "uploading only the dirty rect here leaves every other texel undefined")
    }

    @MainActor
    func testARebuiltAtlasOfADifferentSizeUploadsInFull() async throws {
        let size = IntSize(width: 64, height: 48)
        let renderer = try makeOwnedRenderer(size: size)
        defer { renderer.detach() }

        let version = RenderContentVersion.next()
        try renderer.render(
            scene: Self.makeGlyphScene(
                snapshot: Self.makeSnapshot(contentVersion: version, update: .full)))
        XCTAssertEqual(renderer.atlasFullUploadsForTesting, 1)

        // Same version, different dimensions: the texture is recreated, so
        // the version must not license a skip.
        try renderer.render(
            scene: Self.makeGlyphScene(
                snapshot: Self.makeSnapshot(contentVersion: version, update: .unchanged, side: 32)))
        XCTAssertEqual(renderer.atlasFullUploadsForTesting, 2)
        XCTAssertEqual(renderer.atlasSkippedUploadsForTesting, 0)
    }

    // MARK: - Image texture identity

    private static func makeImageFixture(size: Int, seed: Int) -> BitmapSurface {
        var pixels = Data()
        for y in 0..<size {
            for x in 0..<size {
                pixels.append(UInt8((x * 3 + seed) % 256))
                pixels.append(UInt8((y * 5 + seed) % 256))
                pixels.append(UInt8(seed % 256))
                pixels.append(255)
            }
        }
        return BitmapSurface(
            width: Int32(size), height: Int32(size), bytesPerRow: Int32(size * 4), pixels: pixels)
    }

    private static func makeImageScene(bitmaps: [BitmapSurface]) -> GPUIScene {
        var scene = GPUIScene(clearColor: .black)
        for bitmap in bitmaps {
            let textureID = scene.registerImageResource(bitmap)
            scene.addImage(
                ImagePrimitive(
                    screenX: 0, screenY: 0, screenW: 16, screenH: 16,
                    opacity: 1,
                    textureID: textureID
                )
            )
        }
        return scene
    }

    @MainActor
    func testRebindingTheSameBitmapKeepsTheSameTextureAndSRV() async throws {
        let size = IntSize(width: 64, height: 64)
        let renderer = try makeOwnedRenderer(size: size)
        defer { renderer.detach() }

        let bitmap = Self.makeImageFixture(size: 32, seed: 7)
        let scene = Self.makeImageScene(bitmaps: [bitmap])

        renderer.bindResources(for: scene)
        try renderer.render(scene: scene)
        let first = try XCTUnwrap(renderer.imageTextureIdentityForTesting(for: 0))
        XCTAssertEqual(renderer.imageTextureUploadsForTesting, 1)

        renderer.bindResources(for: scene)
        try renderer.render(scene: scene)
        let second = try XCTUnwrap(renderer.imageTextureIdentityForTesting(for: 0))

        XCTAssertEqual(first.texture, second.texture, "the same content must keep its texture")
        XCTAssertEqual(first.srv, second.srv, "and its shader resource view")
        XCTAssertEqual(renderer.imageTextureUploadsForTesting, 1, "no second upload")
    }

    @MainActor
    func testTheSameBitmapKeepsItsTextureWhenTheSurroundingImageSetChanges() async throws {
        let size = IntSize(width: 64, height: 64)
        let renderer = try makeOwnedRenderer(size: size)
        defer { renderer.detach() }

        let stable = Self.makeImageFixture(size: 32, seed: 7)
        let neighbour = Self.makeImageFixture(size: 16, seed: 99)

        // Frame 1 registers the stable bitmap first (ID 0); frame 2 puts a
        // new image ahead of it, so the stable one is renumbered to ID 1.
        // Texture IDs are positional in registration order, which is why
        // the GPU cache keys on content instead.
        let firstScene = Self.makeImageScene(bitmaps: [stable])
        renderer.bindResources(for: firstScene)
        try renderer.render(scene: firstScene)
        let uploadsAfterFirst = renderer.imageTextureUploadsForTesting
        let stableTexture = try XCTUnwrap(renderer.imageTextureIdentityForTesting(for: 0)).texture

        let secondScene = Self.makeImageScene(bitmaps: [neighbour, stable])
        renderer.bindResources(for: secondScene)
        try renderer.render(scene: secondScene)

        XCTAssertEqual(
            renderer.imageTextureIdentityForTesting(for: 1)?.texture, stableTexture,
            "renumbering must not re-upload an unchanged image")
        XCTAssertEqual(
            renderer.imageTextureUploadsForTesting, uploadsAfterFirst + 1,
            "only the genuinely new bitmap uploads")
    }

    @MainActor
    func testNewPixelsUnderABoundTextureIDStillUpload() async throws {
        let size = IntSize(width: 64, height: 64)
        let renderer = try makeOwnedRenderer(size: size)
        defer { renderer.detach() }

        let original = Self.makeImageFixture(size: 32, seed: 7)
        var scene = GPUIScene(clearColor: .black)
        scene.bindImageResource(original, for: 3)
        scene.addImage(
            ImagePrimitive(screenX: 0, screenY: 0, screenW: 16, screenH: 16, opacity: 1, textureID: 3))
        renderer.bindResources(for: scene)
        try renderer.render(scene: scene)
        XCTAssertEqual(renderer.imageTextureUploadsForTesting, 1)

        var mutated = original
        mutated.pixels[0] = ~mutated.pixels[0]
        var mutatedScene = GPUIScene(clearColor: .black)
        mutatedScene.bindImageResource(mutated, for: 3)
        mutatedScene.addImage(
            ImagePrimitive(screenX: 0, screenY: 0, screenW: 16, screenH: 16, opacity: 1, textureID: 3))
        renderer.bindResources(for: mutatedScene)
        try renderer.render(scene: mutatedScene)

        XCTAssertEqual(
            renderer.imageTextureUploadsForTesting, 2,
            "writing through `pixels` re-mints the content token, so the screen cannot go stale")
    }
}
