import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI

/// The glyph atlas recovers from exhaustion by recycling every shelf, so an
/// atlas rect handed out before the recovery addresses a *different* glyph
/// after it. `ScenePainter` used to retry exactly once, which meant a second
/// exhaustion inside the same pass shipped — and cached — glyph quads pointing
/// at recycled cells: wrong characters, not blanks, on every subsequent
/// non-dirty frame.
///
/// These tests drive that through a deliberately small injected atlas, so the
/// exhaustion path is reachable without a four-thousand-glyph working set.
@MainActor
final class GlyphAtlasExhaustionSafetyTests: XCTestCase {

    /// 64 / 16 = 4 glyphs per shelf and 4 shelves, so exactly 16 glyphs live
    /// per atlas generation.
    private static let atlasSide: Int32 = 64
    private static let glyphSide: Int32 = 16
    private static let atlasCapacity = 16

    private let rowHeight = 32.0
    private let surfaceSize = Size(width: 200, height: 1600)

    // MARK: - Generation token

    func testAtlasGenerationChangesOnlyWhenShelvesAreRecycled() async {
        // 8×8 glyphs in a 32² atlas: 4 per shelf, 4 shelves, 16 before exhaustion.
        let atlas = GlyphAtlas(width: 32, height: 32)
        let cache = GlyphAtlasCache(atlas: atlas, maxEntries: 64)
        let pixels = Data(count: 8 * 8 * 4)

        XCTAssertEqual(atlas.generation, 0)

        for index in 0..<16 {
            _ = cache.insert(
                key: Self.syntheticKey(index),
                pixels: pixels, width: 8, height: 8, bearingX: 0, bearingY: 0, advance: 8)
        }
        XCTAssertEqual(atlas.generation, 0, "Allocations that fit must not invalidate outstanding rects")
        XCTAssertEqual(cache.atlasGeneration, atlas.generation)

        atlas.markClean()
        XCTAssertEqual(atlas.generation, 0, "Dirty-region bookkeeping is not a shelf recycle")

        _ = cache.insert(
            key: Self.syntheticKey(16),
            pixels: pixels, width: 8, height: 8, bearingX: 0, bearingY: 0, advance: 8)
        XCTAssertEqual(atlas.generation, 1, "Exhaustion recovery recycles every shelf and must be observable")
        XCTAssertEqual(cache.atlasGeneration, 1)
    }

    // MARK: - Painter

    /// A pass that recycles the atlas partway through must still emit UVs that
    /// address the glyph they claim to be — the retry exists to rebuild them.
    func testEmittedGlyphUVsResolveToTheRequestedGlyphAfterMidPassRecovery() async {
        installSmallAtlas()
        defer { restoreSharedAtlas() }

        // Warm the atlas to 10/16 so the measured pass runs out partway.
        _ = paintColumn(Array("ABCDEFGHIJ"))

        let measured = Array("KLMNOPQRST")
        let generationBefore = NativeGlyphAtlas.shared.atlasGeneration
        let scene = paintColumn(measured)

        XCTAssertGreaterThan(
            NativeGlyphAtlas.shared.atlasGeneration, generationBefore,
            "This test only means something if the atlas actually recycled during the pass")

        guard let snapshot = scene.glyphAtlas else {
            XCTFail("A scene carrying native glyphs must ship the atlas those glyphs address")
            return
        }
        let glyphs = scene.layers[0].glyphs.sorted { $0.screenY < $1.screenY }
        XCTAssertEqual(glyphs.count, measured.count, "Glyph count must match the text")

        for (index, glyph) in glyphs.enumerated() {
            XCTAssertEqual(
                Self.atlasTile(for: glyph, in: snapshot), Self.glyphPixels(for: measured[index]),
                "Glyph '\(measured[index])' resolves to a recycled atlas cell holding another glyph")
        }
    }

    /// Working set larger than the atlas: every attempt exhausts, so there is
    /// no arrangement of native glyphs that is safe to ship. The pass must fall
    /// through to the pixel font rather than emit UVs it cannot vouch for.
    func testWorkingSetLargerThanTheAtlasDegradesToPixelGlyphsInsteadOfStaleUVs() async {
        installSmallAtlas()
        defer { restoreSharedAtlas() }

        let characters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn")
        XCTAssertGreaterThan(characters.count, Self.atlasCapacity * 2)

        let scene = paintColumn(characters)

        // The combined invariant, which the single-retry painter violated: a
        // shipped native glyph must resolve to its own pixels, and when that
        // cannot be guaranteed no native glyph is shipped at all.
        if let snapshot = scene.glyphAtlas {
            let glyphs = scene.layers[0].glyphs.sorted { $0.screenY < $1.screenY }
            for (index, glyph) in glyphs.enumerated() {
                XCTAssertEqual(
                    Self.atlasTile(for: glyph, in: snapshot), Self.glyphPixels(for: characters[index]))
            }
        } else {
            XCTAssertTrue(
                scene.layers[0].glyphs.isEmpty,
                "Native glyph quads without an atlas snapshot address whatever the backend cached last")
        }

        XCTAssertTrue(scene.layers[0].glyphs.isEmpty, "An atlas that cannot hold the frame must not be drawn from")
        XCTAssertNil(scene.glyphAtlas)
        XCTAssertEqual(
            scene.layers[0].pixelGlyphs.count, characters.count,
            "Degrading must reach the pixel font, not drop the text")
        XCTAssertNotNil(scene.pixelGlyphAtlas)
    }

    /// Degradation is scoped to the frame that could not be satisfied: the next
    /// frame gets the atlas back.
    func testAtlasSuspensionDoesNotOutliveTheDegradedFrame() async {
        installSmallAtlas()
        defer { restoreSharedAtlas() }

        _ = paintColumn(Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn"))
        XCTAssertFalse(NativeGlyphAtlas.shared.isSuspended)

        let recovered = paintColumn(Array("XY"))
        XCTAssertEqual(recovered.layers[0].glyphs.count, 2, "A frame the atlas can serve must go back to native text")
        XCTAssertNotNil(recovered.glyphAtlas)
    }

    /// `beginFrame()` is the atlas LRU clock. Ticking it per attempt instead of
    /// per frame ages glyphs the frame is still using.
    func testLruClockAdvancesOncePerRenderedFrameNotOncePerAttempt() async {
        installSmallAtlas()
        defer { restoreSharedAtlas() }

        _ = paintColumn(Array("ABCDEFGHIJ"))

        let generationBefore = NativeGlyphAtlas.shared.atlasGeneration
        let clockBefore = NativeGlyphAtlas.shared.frameIndex
        _ = paintColumn(Array("KLMNOPQRST"))

        XCTAssertGreaterThan(
            NativeGlyphAtlas.shared.atlasGeneration, generationBefore,
            "This test only means something if the pass needed more than one attempt")
        XCTAssertEqual(NativeGlyphAtlas.shared.frameIndex, clockBefore + 1)

        let plainClockBefore = NativeGlyphAtlas.shared.frameIndex
        _ = ScenePainter.paint(
            root: ViewNode(frame: Rect(x: 0, y: 0, width: 40, height: 40), backgroundColor: .white),
            clearColor: .black,
            surfaceSize: surfaceSize
        )
        XCTAssertEqual(NativeGlyphAtlas.shared.frameIndex, plainClockBefore + 1)
    }

    // MARK: - Reclaimed space is not a recycle

    /// The steady state WS-18's free list created and nobody costed: a full
    /// atlas plus an LRU cache means every *new* glyph is served from space an
    /// eviction returned, and every such allocation used to bump the same
    /// generation token a full recycle bumps. `ScenePainter` treats that token
    /// as "throw the pass away", so a screen that introduces one glyph per
    /// frame — a clock, a counter, a filter box — paid a second full paint pass
    /// on every frame of it, forever.
    ///
    /// Reusing one freed span invalidates exactly that span, and the entry that
    /// owned it left the cache when it was freed. Nothing this pass emitted can
    /// be addressing it, so the pass is shippable.
    func testOneNewGlyphPerFrameAgainstAFullAtlasCostsNoRepaint() async {
        // 32² atlas, 16² glyphs: two shelves of two cells, so four glyphs fill
        // it exactly and a four-entry cache evicts from the fifth on.
        installSmallAtlas(side: 32, maxEntries: 4)
        defer { restoreSharedAtlas() }

        let warm = Array("ABCD")
        let warmScene = paintColumn(warm)
        XCTAssertEqual(warmScene.layers[0].glyphs.count, warm.count, "the fixture must fill the atlas natively")
        XCTAssertEqual(warmScene.paintMetrics.textDiagnostics.atlasRecoveries, 0, "nothing has run out yet")

        // Each frame keeps three glyphs and introduces a fourth: the newcomer
        // has to come out of the evicted glyph's cell every time.
        var repaints = 0
        for newcomer in Array("EFGHIJ") {
            let frame = Array("ABC") + [newcomer]
            let scene = paintColumn(frame)
            repaints += scene.paintMetrics.textDiagnostics.atlasRecoveries

            XCTAssertEqual(
                scene.layers[0].glyphs.count, frame.count,
                "a frame the atlas can serve by reclaiming must still be native text")
            guard let snapshot = scene.glyphAtlas else {
                XCTFail("a scene carrying native glyphs must ship the atlas those glyphs address")
                return
            }
            let glyphs = scene.layers[0].glyphs.sorted { $0.screenY < $1.screenY }
            for (index, glyph) in glyphs.enumerated() {
                XCTAssertEqual(
                    Self.atlasTile(for: glyph, in: snapshot), Self.glyphPixels(for: frame[index]),
                    "glyph '\(frame[index])' was shipped from a cell reclamation gave to another glyph")
            }
        }

        XCTAssertEqual(
            repaints, 0,
            "six one-new-glyph frames cost \(repaints) discarded passes; reclaiming a dead cell is not a recycle")
    }

    /// The next frame is the one that pays, and it pays once: a scene built
    /// over reclaimed space is not safe to replay paint records out of, so the
    /// following frame starts with replay off rather than discovering it
    /// halfway through a pass.
    func testAFrameAfterReclamationStartsWithReplayDisabled() async {
        installSmallAtlas(side: 32, maxEntries: 4)
        defer { restoreSharedAtlas() }

        _ = paintColumn(Array("ABCD"))
        XCTAssertFalse(
            NativeGlyphAtlas.shared.replayIsUnsafeThisFrame,
            "a frame that only used virgin space leaves the next one alone")

        _ = paintColumn(Array("ABCE"))
        _ = paintColumn(Array("ABCE"))
        XCTAssertTrue(
            NativeGlyphAtlas.shared.replayIsUnsafeThisFrame,
            "the frame after a reclaim must not replay last frame's glyph quads")

        // A frame that reclaims nothing hands replay back.
        _ = paintColumn(Array("ABCE"))
        XCTAssertFalse(
            NativeGlyphAtlas.shared.replayIsUnsafeThisFrame,
            "the carry is for cause; a settled working set must get replay back")
    }

    /// The narrowing has one hole it must not open. When the frame's own
    /// working set is bigger than the cache, eviction takes a glyph *this pass
    /// already drew*, and reusing that cell aliases a rect the pass emitted —
    /// which is the WS-14 hazard, arriving through the free list instead of
    /// through a recycle. The pass has to be thrown away exactly as before.
    func testReusingACellThisPassAlreadyDrewFromStillDiscardsThePass() async {
        installSmallAtlas(side: 32, maxEntries: 4)
        defer { restoreSharedAtlas() }

        let characters = Array("ABCDEF")
        let scene = paintColumn(characters)

        if let snapshot = scene.glyphAtlas {
            let glyphs = scene.layers[0].glyphs.sorted { $0.screenY < $1.screenY }
            for (index, glyph) in glyphs.enumerated() {
                XCTAssertEqual(
                    Self.atlasTile(for: glyph, in: snapshot), Self.glyphPixels(for: characters[index]),
                    "glyph '\(characters[index])' resolves to a cell the same pass gave to another glyph")
            }
        }
        XCTAssertTrue(
            scene.layers[0].glyphs.isEmpty,
            "a working set larger than the cache cannot be served natively without aliasing")
        XCTAssertEqual(
            scene.layers[0].pixelGlyphs.count, characters.count,
            "degrading must reach the pixel font, not drop the text")
        XCTAssertGreaterThan(
            scene.paintMetrics.textDiagnostics.atlasRecoveries, 0,
            "this test only means something if the painter actually discarded a pass")
    }

    // MARK: - Cached scenes

    /// The atlas is process-wide, a runtime's cached scene is not. A window
    /// that is clean — nothing dirty, nothing to repaint — used to ship that
    /// cached scene with the *current* shared atlas stapled onto it, so a
    /// recovery triggered by some other window left its glyph quads addressing
    /// cells that now hold someone else's pixels, forever: nothing about the
    /// clean window ever changes to make it repaint.
    func testACachedSceneIsNotShippedAgainstAnAtlasRecoveredUnderIt() async {
        installSmallAtlas()
        defer { restoreSharedAtlas() }

        let characters = Array("ABC")
        let runtime = RetainedViewRuntime(clearColor: .black, root: textColumn(characters))
        let first = runtime.renderScene()
        XCTAssertEqual(first.layers[0].glyphs.count, characters.count, "the fixture must draw native glyphs")

        // Another window's frame, with a working set the atlas cannot hold.
        let generationBefore = NativeGlyphAtlas.shared.atlasGeneration
        _ = paintColumn(Array("DEFGHIJKLMNOPQRSTUV"))
        XCTAssertGreaterThan(
            NativeGlyphAtlas.shared.atlasGeneration, generationBefore,
            "this test only means something if the atlas actually recycled")

        let second = runtime.renderScene()
        guard let snapshot = second.glyphAtlas else {
            XCTFail("a scene carrying native glyphs must ship the atlas those glyphs address")
            return
        }
        let glyphs = second.layers[0].glyphs.sorted { $0.screenY < $1.screenY }
        XCTAssertEqual(glyphs.count, characters.count, "the repaint must draw the same text")
        for (index, glyph) in glyphs.enumerated() {
            XCTAssertEqual(
                Self.atlasTile(for: glyph, in: snapshot), Self.glyphPixels(for: characters[index]),
                "glyph '\(characters[index])' was shipped from a cell the recovery gave to another glyph")
        }
    }

    /// The cache is only dropped for cause: an atlas that never recycled must
    /// leave the fast path alone.
    func testACachedSceneSurvivesWhenTheAtlasDoesNotRecycle() async {
        installSmallAtlas()
        defer { restoreSharedAtlas() }

        let runtime = RetainedViewRuntime(clearColor: .black, root: textColumn(Array("AB")))
        _ = runtime.renderScene()

        // The atlas LRU clock ticks once per paint pass, so it is the cheapest
        // observable difference between shipping the cache and repainting.
        let generationBefore = NativeGlyphAtlas.shared.atlasGeneration
        let clockBefore = NativeGlyphAtlas.shared.frameIndex
        let shipped = runtime.renderScene()

        XCTAssertEqual(NativeGlyphAtlas.shared.atlasGeneration, generationBefore)
        XCTAssertEqual(NativeGlyphAtlas.shared.frameIndex, clockBefore, "a cached ship must not run a paint pass")
        XCTAssertEqual(shipped.layers[0].glyphs.count, 2, "and it still ships its text")
        XCTAssertNotNil(shipped.glyphAtlas, "with the atlas those quads address")
    }

    // MARK: - Fixtures

    private func installSmallAtlas(side: Int32 = atlasSide, maxEntries: Int = 4096) {
        NativeGlyphAtlas.installForTesting(
            NativeGlyphAtlas(atlasWidth: side, atlasHeight: side, maxEntries: maxEntries))
        NativeTextRenderer.testingOverrides.layout = { text, style, _, _ in
            Self.syntheticLayout(for: text, style: style)
        }
        NativeTextRenderer.testingOverrides.rasterizeGlyphForLayout = { glyph, _, _ in
            Self.stubBitmap(for: glyph.character)
        }
    }

    private func restoreSharedAtlas() {
        NativeTextRenderer.resetTestingOverrides()
        NativeGlyphAtlas.restoreSharedForTesting()
    }

    private func paintColumn(_ characters: [Character]) -> GPUIScene {
        ScenePainter.paint(root: textColumn(characters), clearColor: .black, surfaceSize: surfaceSize)
    }

    /// One single-character text node per row, so a glyph primitive's `screenY`
    /// identifies which character requested it without relying on traversal
    /// order.
    private func textColumn(_ characters: [Character]) -> ViewNode {
        let children = characters.enumerated().map { index, character in
            ViewNode(
                frame: Rect(x: 0, y: Double(index) * rowHeight, width: 80, height: 24),
                text: String(character),
                textStyle: PixelTextStyle(
                    color: .white, alignment: .leading, verticalAlignment: .top, nativeFontSize: 18)
            )
        }
        return ViewNode(
            frame: Rect(x: 0, y: 0, width: 120, height: Double(characters.count) * rowHeight + 24),
            children: children
        )
    }

    private static func syntheticKey(_ index: Int) -> GlyphKey {
        GlyphKey(
            character: Character(Unicode.Scalar(0x4E00 + index)!),
            fontFamily: "F", fontSize: 12, weight: .regular)
    }

    private static func syntheticLayout(for text: String, style: PixelTextStyle) -> NativeTextLayoutResult {
        let characters = Array(text)
        let advance = Double(glyphSide)
        let glyphs = characters.enumerated().map { index, character in
            NativeTextGlyphLayout(
                character: character,
                origin: Point(x: Double(index) * advance, y: 0),
                advance: advance,
                glyphID: character.unicodeScalars.first?.value ?? UInt32(index + 1),
                fontFamily: style.fontFamily,
                weight: style.weight,
                fontSize: style.nativeFontPixelSize,
                sourceIndex: index
            )
        }
        let width = Double(max(characters.count, 1)) * advance
        let height = max(style.nativeFontPixelSize, 1)
        return NativeTextLayoutResult(
            lines: [NativeTextLineLayout(text: text, width: width, height: height, glyphs: glyphs)],
            contentSize: Size(width: width, height: height),
            measuredSize: Size(width: width, height: height)
        )
    }

    private static func stubBitmap(for character: Character) -> NativeGlyphBitmap {
        NativeGlyphBitmap(
            surface: BitmapSurface(
                width: glyphSide,
                height: glyphSide,
                bytesPerRow: glyphSide * 4,
                pixels: glyphPixels(for: character)
            ),
            bearingX: 0,
            bearingY: 0,
            advance: Float(glyphSide)
        )
    }

    /// Distinct, position-varying bytes per character, so a recycled cell can
    /// never accidentally compare equal to the glyph a primitive claims to be.
    private static func glyphPixels(for character: Character) -> Data {
        let seed = UInt8(truncatingIfNeeded: character.unicodeScalars.first?.value ?? 0)
        let count = Int(glyphSide) * Int(glyphSide) * 4
        var bytes = [UInt8](repeating: 0, count: count)
        for index in 0..<count {
            bytes[index] = seed &+ UInt8(truncatingIfNeeded: index &* 7)
        }
        return Data(bytes)
    }

    /// The atlas rectangle a shipped glyph quad actually samples from.
    private static func atlasTile(for glyph: GlyphPrimitive, in snapshot: GlyphAtlasSnapshot) -> Data? {
        let atlasWidth = Double(snapshot.width)
        let atlasHeight = Double(snapshot.height)
        let x0 = Int((Double(glyph.atlasU0) * atlasWidth).rounded())
        let y0 = Int((Double(glyph.atlasV0) * atlasHeight).rounded())
        let x1 = Int((Double(glyph.atlasU1) * atlasWidth).rounded())
        let y1 = Int((Double(glyph.atlasV1) * atlasHeight).rounded())
        guard x1 > x0, y1 > y0, x1 <= Int(snapshot.width), y1 <= Int(snapshot.height) else {
            return nil
        }

        let stride = Int(snapshot.width) * 4
        let rowBytes = (x1 - x0) * 4
        let base = snapshot.pixels.startIndex
        var tile = Data()
        tile.reserveCapacity(rowBytes * (y1 - y0))
        for row in y0..<y1 {
            let start = base + row * stride + x0 * 4
            tile.append(snapshot.pixels[start..<(start + rowBytes)])
        }
        return tile
    }
}
