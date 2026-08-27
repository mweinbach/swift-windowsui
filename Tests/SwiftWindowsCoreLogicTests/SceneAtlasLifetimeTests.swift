import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI

/// Color-effect sources retain glyph UVs while recording, then share the
/// enclosing frame's completed atlas instead of retaining partial buffers.
@MainActor
final class SceneAtlasLifetimeTests: XCTestCase {
    private func installAtlas() {
        NativeGlyphAtlas.installForTesting(NativeGlyphAtlas(atlasWidth: 256, atlasHeight: 256))
        NativeTextRenderer.testingOverrides.layout = { text, style, _, _ in
            Self.syntheticLayout(text, style: style)
        }
        NativeTextRenderer.testingOverrides.rasterizeGlyphForLayout = { glyph, _, _ in
            let coverage = Self.coverage(for: glyph.character)
            return NativeGlyphBitmap(
                surface: BitmapSurface(
                    width: 8, height: 8, bytesPerRow: 32,
                    pixels: Data(repeating: coverage, count: 8 * 8 * 4)),
                bearingX: 0, bearingY: 0, advance: 8)
        }
    }

    private func restoreAtlas() {
        NativeTextRenderer.resetTestingOverrides()
        NativeGlyphAtlas.restoreSharedForTesting()
    }

    private func text(_ character: Character, x: Double = 4, y: Double = 4) -> ViewNode {
        ViewNode(
            frame: Rect(x: x, y: y, width: 8, height: 8), text: String(character),
            textStyle: PixelTextStyle(
                color: Color(red: 1, green: 1, blue: 1, alpha: 1),
                alignment: .leading, verticalAlignment: .top, nativeFontSize: 18),
            preferredSize: Size(width: 8, height: 8), colorEffects: [.brightness(0)])
    }

    private func namespaces(in scene: GPUIScene) -> [GPUIScene] {
        var pending = [scene]
        var result: [GPUIScene] = []
        while let current = pending.popLast() {
            result.append(current)
            pending.append(contentsOf: current.imageRenderPasses.map(\.scene))
        }
        return result
    }

    private func storageAddress(_ data: Data) -> UInt {
        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            guard let address = bytes.baseAddress else { return 0 }
            return UInt(bitPattern: address)
        }
    }

    @discardableResult
    private func assertFinalAtlasShared(
        by scene: GPUIScene, glyphCount: Int,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> GlyphAtlasSnapshot {
        // Taking snapshots inside the source fixture would itself retain
        // intermediate Data and obscure the lifetime this test protects.
        let finalAtlas = try XCTUnwrap(NativeGlyphAtlas.shared.snapshotForCachedGlyphs(), file: file, line: line)
        let scenes = namespaces(in: scene)
        XCTAssertEqual(
            scenes.reduce(0) { $0 + $1.layers.flatMap(\.glyphs).count }, glyphCount,
            file: file, line: line)
        let glyphNamespaces = scenes.filter { source in
            namespaces(in: source).contains { !$0.layers.flatMap(\.glyphs).isEmpty }
        }
        for source in glyphNamespaces {
            XCTAssertNotNil(
                source.glyphAtlas,
                "Every namespace with direct or descendant native glyphs needs the final binding",
                file: file, line: line)
        }
        let bindings = scenes.compactMap(\.glyphAtlas)
        XCTAssertGreaterThanOrEqual(bindings.count, glyphNamespaces.count, file: file, line: line)
        XCTAssertEqual(
            Set(bindings.map(\.contentVersion)), Set([finalAtlas.contentVersion]),
            "No source or ancestor may retain an intermediate atlas version", file: file, line: line)
        let finalAddress = storageAddress(finalAtlas.pixels)
        XCTAssertNotEqual(finalAddress, 0, file: file, line: line)
        XCTAssertEqual(
            Set(bindings.map { storageAddress($0.pixels) }), Set([finalAddress]),
            "All completed namespaces must share one full atlas Data storage", file: file, line: line)
        for descendant in scenes.dropFirst() {
            if let atlas = descendant.glyphAtlas {
                XCTAssertEqual(
                    atlas.update, .unchanged,
                    "The parent owns the upload; descendants must borrow its final atlas", file: file, line: line)
            }
        }
        XCTAssertTrue(scene.validate().isEmpty, file: file, line: line)
        return finalAtlas
    }

    private func assertCoverage(
        _ bitmap: BitmapSurface, x: Int, y: Int, character: Character,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let pixels = bitmap.premultipliedAlpha()
        let offset = y * Int(pixels.bytesPerRow) + x * 4
        let expected = Int(Self.coverage(for: character))
        for channel in 0..<4 {
            XCTAssertEqual(Int(pixels.pixels[offset + channel]), expected, accuracy: 2, file: file, line: line)
        }
    }

    func testManyDistinctTextColorPassesShareOneFinalAtlasStorageIncludingAncestors() async throws {
        installAtlas()
        defer { restoreAtlas() }
        let characters = (0..<64).map { Character(Unicode.Scalar(0x410 + $0)!) }
        let size = IntSize(width: 100, height: 100)
        let runtime = RetainedViewRuntime(clearColor: .clear)
        runtime.setRootSize(size)
        runtime.root.setChildren(
            characters.enumerated().map { index, character in
                text(character, x: 4 + Double(index % 8) * 12, y: 4 + Double(index / 8) * 12)
            })

        let scene = runtime.renderScene()
        XCTAssertEqual(NativeGlyphAtlas.shared.cachedGlyphCount, characters.count)
        XCTAssertEqual(scene.imageRenderPasses.count, characters.count)
        XCTAssertTrue(scene.imageRenderPasses.allSatisfy { $0.colorEffects == [.brightness(0)] })
        XCTAssertTrue(scene.layers.flatMap(\.glyphs).isEmpty, "All fixture glyphs must be inside color passes")
        XCTAssertNotNil(scene.glyphAtlas, "The enclosing renderer must be able to upload the shared atlas once")
        try assertFinalAtlasShared(by: scene, glyphCount: characters.count)
        let pixels = GPUIRawSceneRasterizer.rasterize(scene, size: size)
        for index in [0, 31, 63] {
            assertCoverage(pixels, x: 8 + (index % 8) * 12, y: 8 + (index / 8) * 12, character: characters[index])
        }
    }

    func testNewGlyphsAndCleanPassReplayShareANewAtlasWithoutMutatingTheOldScene() async throws {
        installAtlas()
        defer { restoreAtlas() }
        let cleanCharacter = Character(Unicode.Scalar(0x410)!)
        let oldCharacter = Character(Unicode.Scalar(0x430)!)
        let newCharacter = Character(Unicode.Scalar(0x450)!)
        let size = IntSize(width: 48, height: 24)
        let runtime = RetainedViewRuntime(clearColor: .clear)
        runtime.setRootSize(size)
        let changed = text(oldCharacter)
        let clean = text(cleanCharacter, x: 20)
        runtime.root.setChildren([changed, clean])

        let oldScene = runtime.renderScene()
        let oldAtlas = try assertFinalAtlasShared(by: oldScene, glyphCount: 2)
        let oldAddress = storageAddress(oldAtlas.pixels)
        let savedOldBytes = [UInt8](oldAtlas.pixels)
        let oldPixels = GPUIRawSceneRasterizer.rasterize(oldScene, size: size)
        assertCoverage(oldPixels, x: 8, y: 8, character: oldCharacter)
        assertCoverage(oldPixels, x: 24, y: 8, character: cleanCharacter)

        changed.text = String(newCharacter)
        let newScene = runtime.renderScene()
        XCTAssertGreaterThan(runtime.lastSceneReplayCount, 0, "The unchanged color pass must replay")
        let newAtlas = try assertFinalAtlasShared(by: newScene, glyphCount: 2)
        XCTAssertGreaterThan(newAtlas.contentVersion, oldAtlas.contentVersion)
        XCTAssertNotEqual(storageAddress(newAtlas.pixels), oldAddress)
        let newPixels = GPUIRawSceneRasterizer.rasterize(newScene, size: size)
        assertCoverage(newPixels, x: 8, y: 8, character: newCharacter)
        assertCoverage(newPixels, x: 24, y: 8, character: cleanCharacter)

        let oldBindings = namespaces(in: oldScene).compactMap(\.glyphAtlas)
        XCTAssertEqual(Set(oldBindings.map(\.contentVersion)), Set([oldAtlas.contentVersion]))
        XCTAssertEqual(Set(oldBindings.map { storageAddress($0.pixels) }), Set([oldAddress]))
        for atlas in oldBindings {
            XCTAssertEqual([UInt8](atlas.pixels), savedOldBytes)
        }
        XCTAssertEqual(
            GPUIRawSceneRasterizer.rasterize(oldScene, size: size), oldPixels,
            "An earlier scene must keep its atlas bytes and rendered pixels while later glyphs are added")
    }

    func testCleanRuntimeWithOnlyNestedGlyphsRebuildsAfterAtlasReset() async throws {
        installAtlas()
        defer { restoreAtlas() }
        let character = Character(Unicode.Scalar(0x440)!)
        let size = IntSize(width: 32, height: 32)
        let runtime = RetainedViewRuntime(clearColor: .clear)
        runtime.setRootSize(size)
        runtime.root.addChild(text(character))
        let original = runtime.renderScene()
        XCTAssertTrue(original.layers.flatMap(\.glyphs).isEmpty)
        try assertFinalAtlasShared(by: original, glyphCount: 1)
        let expected = GPUIRawSceneRasterizer.rasterize(original, size: size)
        assertCoverage(expected, x: 8, y: 8, character: character)
        let rebuildsBefore = runtime.sceneRebuildCount

        let cached = runtime.renderScene()
        XCTAssertEqual(runtime.sceneRebuildCount, rebuildsBefore)
        try assertFinalAtlasShared(by: cached, glyphCount: 1)
        XCTAssertEqual(GPUIRawSceneRasterizer.rasterize(cached, size: size), expected)

        let generationBefore = NativeGlyphAtlas.shared.atlasGeneration
        NativeGlyphAtlas.shared.resetForTesting()
        XCTAssertNotEqual(NativeGlyphAtlas.shared.atlasGeneration, generationBefore)
        XCTAssertEqual(NativeGlyphAtlas.shared.cachedGlyphCount, 0)
        // No node is dirtied. Descendant UVs must invalidate the clean
        // runtime cache before its early return can rebind them incorrectly.
        let rebuilt = runtime.renderScene()
        XCTAssertEqual(runtime.sceneRebuildCount, rebuildsBefore + 1)
        XCTAssertEqual(NativeGlyphAtlas.shared.cachedGlyphCount, 1)
        try assertFinalAtlasShared(by: rebuilt, glyphCount: 1)
        XCTAssertEqual(GPUIRawSceneRasterizer.rasterize(rebuilt, size: size), expected)
        XCTAssertEqual(GPUIRawSceneRasterizer.rasterize(original, size: size), expected)
    }

    func testScrollObserverReentryPreservesSafeSceneButDefersAfterAtlasReset() async throws {
        installAtlas()
        defer { restoreAtlas() }
        let character = Character(Unicode.Scalar(0x440)!)
        let size = IntSize(width: 80, height: 32)
        let runtime = RetainedViewRuntime(clearColor: .clear)
        runtime.setRootSize(size)
        let yellow = ViewNode(
            frame: Rect(x: 8, y: 4, width: 8, height: 8),
            backgroundColor: Color(red: 1, green: 1, blue: 0, alpha: 1))
        let scroller = ViewNode(
            frame: Rect(x: 56, y: 0, width: 16, height: 16), clipsToBounds: true, scrollAxis: .vertical,
            children: [ViewNode(frame: Rect(x: 0, y: 0, width: 16, height: 64))])
        runtime.root.setChildren([text(character), yellow, text(character, x: 12), scroller])
        var callbackCount = 0
        var safeReentry: GPUIScene?
        var deferredReentry: GPUIScene?
        scroller.observeScrollGeometry(
            of: { $0.contentOffset.y },
            action: { [weak runtime] _, _ in
                callbackCount += 1
                guard callbackCount == 1, let runtime else { return }
                let rebuildsBefore = runtime.sceneRebuildCount
                safeReentry = runtime.renderScene()
                XCTAssertEqual(runtime.sceneRebuildCount, rebuildsBefore)
                NativeGlyphAtlas.shared.resetForTesting()
                deferredReentry = runtime.renderScene()
                XCTAssertEqual(runtime.sceneRebuildCount, rebuildsBefore, "Observer delivery cannot re-enter layout")
            })

        let deferralsBefore = runtime.sceneAtlasDeferralCount
        let original = runtime.renderScene()
        XCTAssertEqual(callbackCount, 1)
        let safe = try XCTUnwrap(safeReentry)
        let deferred = try XCTUnwrap(deferredReentry)
        let expected = GPUIRawSceneRasterizer.rasterize(original, size: size)
        assertCoverage(expected, x: 6, y: 8, character: character)
        assertCoverage(expected, x: 18, y: 8, character: character)
        let yellowOffset = 8 * Int(expected.bytesPerRow) + 10 * 4
        XCTAssertEqual(Array(expected.pixels[yellowOffset..<(yellowOffset + 4)]), [0, 255, 255, 255])
        XCTAssertEqual(original.presentationOrder().prefix(3).map(\.kind), [.image, .quad, .image])
        XCTAssertEqual(Array(safe.presentationOrder()), Array(original.presentationOrder()))
        XCTAssertEqual(GPUIRawSceneRasterizer.rasterize(safe, size: size), expected)
        XCTAssertEqual(runtime.sceneAtlasDeferralCount, deferralsBefore + 1)
        XCTAssertTrue(Array(deferred.presentationOrder()).isEmpty)
        XCTAssertTrue(deferred.imageRenderPasses.isEmpty)
        XCTAssertNil(deferred.glyphAtlas)
        XCTAssertEqual(deferred.clearColor, .clear)
        XCTAssertTrue(GPUIRawSceneRasterizer.rasterize(deferred, size: size).pixels.allSatisfy { $0 == 0 })

        let rebuildsBefore = runtime.sceneRebuildCount
        let rebuilt = runtime.renderScene()
        XCTAssertEqual(runtime.sceneRebuildCount, rebuildsBefore + 1)
        XCTAssertEqual(runtime.sceneAtlasDeferralCount, deferralsBefore + 1)
        XCTAssertEqual(callbackCount, 1, "Recovering the atlas must not recursively deliver unchanged geometry")
        try assertFinalAtlasShared(by: rebuilt, glyphCount: 2)
        XCTAssertEqual(Array(rebuilt.presentationOrder()), Array(original.presentationOrder()))
        XCTAssertEqual(GPUIRawSceneRasterizer.rasterize(rebuilt, size: size), expected)
        XCTAssertEqual(GPUIRawSceneRasterizer.rasterize(original, size: size), expected)
    }

    func testAtlasRecycleDuringGroupOrBlurRecordingCannotCacheTheFailedAttempt() async throws {
        for usesBlur in [false, true] {
            installAtlas()
            defer { restoreAtlas() }
            let character = Character(Unicode.Scalar(0x440)!)
            let size = IntSize(width: 64, height: 40)
            var sourcePaints = 0
            var resets = 0
            let source = text(character)
            source.canvasDraw = { _, _ in sourcePaints += 1 }
            let resetter = ViewNode(
                frame: Rect(x: 20, y: 4, width: 1, height: 1),
                canvasDraw: { _, _ in
                    guard resets == 0 else { return }
                    resets += 1
                    // The text's UVs already exist in a color-pass source,
                    // but the enclosing CPU isolation has not baked them.
                    NativeGlyphAtlas.shared.resetForTesting()
                })
            let isolated = ViewNode(
                frame: Rect(x: 8, y: 8, width: 32, height: 16),
                contentBlurRadius: usesBlur ? 1 : 0,
                drawingGroup: usesBlur ? nil : RetainedDrawingGroup(), children: [source, resetter])
            func paint() -> GPUIScene {
                ScenePainter.paint(
                    root: isolated, clearColor: .clear,
                    surfaceSize: Size(width: Double(size.width), height: Double(size.height)))
            }

            let recovered = paint()
            XCTAssertEqual(resets, 1)
            XCTAssertGreaterThanOrEqual(
                sourcePaints, 2, "The retry must record text again instead of using its failed bitmap")
            XCTAssertGreaterThanOrEqual(recovered.paintMetrics.textDiagnostics.atlasRecoveries, 1)
            XCTAssertEqual(NativeGlyphAtlas.shared.cachedGlyphCount, 1)
            XCTAssertTrue(recovered.validate().isEmpty)
            let expected = GPUIRawSceneRasterizer.rasterize(recovered, size: size)
            assertCoverage(expected, x: 16, y: 16, character: character)

            // A recovery can inhibit caches for the next complete frame.
            // Two normal paints reach a stable generation without imposing
            // whether the successful retry itself was allowed to cache.
            let settling = paint()
            XCTAssertEqual(GPUIRawSceneRasterizer.rasterize(settling, size: size), expected)
            let stable = paint()
            XCTAssertEqual(GPUIRawSceneRasterizer.rasterize(stable, size: size), expected)
            let cachedBitmap = try XCTUnwrap(isolated.cachedCompositingGroupBitmap)
            let stableGeneration = NativeGlyphAtlas.shared.atlasGeneration
            XCTAssertEqual(isolated.cachedCompositingGroupAtlasGeneration, stableGeneration)
            let paintsBeforeReuse = sourcePaints
            let reused = paint()
            XCTAssertEqual(sourcePaints, paintsBeforeReuse, "A successful, stable bitmap should now be reusable")
            XCTAssertEqual(isolated.cachedCompositingGroupBitmap?.contentToken, cachedBitmap.contentToken)
            XCTAssertEqual(isolated.cachedCompositingGroupAtlasGeneration, stableGeneration)
            XCTAssertEqual(NativeGlyphAtlas.shared.atlasGeneration, stableGeneration)
            XCTAssertEqual(
                usesBlur ? reused.paintMetrics.contentBlurPassesReused : reused.paintMetrics.compositingGroupsReused,
                1)
            XCTAssertEqual(GPUIRawSceneRasterizer.rasterize(reused, size: size), expected)
        }
    }

    private static func coverage(for character: Character) -> UInt8 {
        UInt8(48 + (character.unicodeScalars.first?.value ?? 0) % 128)
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
}
