import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI

/// Retained symbol namespaces must share the completed frame's atlas. Taking
/// an atlas snapshot after every symbol keeps successive full Data buffers
/// alive as later glyph writes trigger copy-on-write.
@MainActor
final class CanvasSymbolAtlasLifetimeTests: XCTestCase {
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

    private func symbol(_ character: Character, colorPass: Bool = false) -> CanvasSymbolSource? {
        CanvasSymbolSource(displayScale: 1) { _ in
            ViewNode(
                frame: Rect(x: 0, y: 0, width: 8, height: 8), text: String(character),
                textStyle: PixelTextStyle(
                    color: Color(red: 1, green: 1, blue: 1, alpha: 1),
                    alignment: .leading, verticalAlignment: .top, nativeFontSize: 18),
                preferredSize: Size(width: 8, height: 8),
                colorEffects: colorPass ? [.brightness(0)] : [])
        }
    }

    private func canvas(
        _ symbols: [CanvasSymbolSource], frame: Rect, runtime: RetainedViewRuntime
    ) -> ViewNode {
        UI.canvas(frame: frame) { context, _ in
            for (index, symbol) in symbols.enumerated() {
                context.draw(
                    symbol,
                    in: Rect(x: 4 + Double(index % 8) * 12, y: 4 + Double(index / 8) * 12, width: 8, height: 8))
            }
        }.makeNode(runtime: runtime)
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
        // Read only after the enclosing paint completed. An intermediate
        // snapshot in a symbol fixture would itself retain a partial buffer.
        let finalAtlas = try XCTUnwrap(NativeGlyphAtlas.shared.snapshotForCachedGlyphs(), file: file, line: line)
        let scenes = namespaces(in: scene)
        let glyphScenes = scenes.filter { !$0.layers.flatMap(\.glyphs).isEmpty }
        XCTAssertEqual(
            glyphScenes.reduce(0) { $0 + $1.layers.flatMap(\.glyphs).count }, glyphCount, file: file, line: line)
        let nativeNamespaces = scenes.filter { source in
            namespaces(in: source).contains { !$0.layers.flatMap(\.glyphs).isEmpty }
        }
        for source in nativeNamespaces {
            XCTAssertNotNil(
                source.glyphAtlas,
                "Every namespace with direct or descendant native glyphs needs the final binding",
                file: file, line: line)
        }
        for source in scenes.dropFirst() {
            for atlas in [source.glyphAtlas, source.pixelGlyphAtlas].compactMap({ $0 }) {
                XCTAssertEqual(
                    atlas.update, .unchanged,
                    "Descendant passes must borrow the enclosing atlas without requesting another upload",
                    file: file, line: line)
            }
        }
        let bindings = scenes.compactMap(\.glyphAtlas)
        XCTAssertGreaterThanOrEqual(bindings.count, nativeNamespaces.count, file: file, line: line)
        XCTAssertEqual(
            Set(bindings.map(\.contentVersion)), Set([finalAtlas.contentVersion]),
            "No source or ancestor may retain an intermediate atlas content version", file: file, line: line)
        let finalAddress = storageAddress(finalAtlas.pixels)
        XCTAssertNotEqual(finalAddress, 0, file: file, line: line)
        XCTAssertEqual(
            Set(bindings.map { storageAddress($0.pixels) }), Set([finalAddress]),
            "Every completed namespace must share one full atlas Data storage", file: file, line: line)
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

    func testManyDistinctTextSymbolsAndColorPassesShareOneFinalAtlasStorage() async throws {
        installAtlas()
        defer { restoreAtlas() }
        let characters = (0..<64).map { Character(Unicode.Scalar(0x410 + $0)!) }
        let symbols = try characters.enumerated().map { index, character in
            try XCTUnwrap(symbol(character, colorPass: index.isMultiple(of: 2)))
        }
        let size = IntSize(width: 100, height: 100)
        let runtime = RetainedViewRuntime(clearColor: .clear)
        runtime.setRootSize(size)
        runtime.root.addChild(canvas(symbols, frame: Rect(x: 0, y: 0, width: 100, height: 100), runtime: runtime))
        let scene = runtime.renderScene()
        XCTAssertEqual(NativeGlyphAtlas.shared.cachedGlyphCount, characters.count)
        XCTAssertEqual(scene.imageRenderPasses.count, characters.count)
        XCTAssertTrue(scene.layers.flatMap(\.glyphs).isEmpty, "The fixture's glyphs must be inside sources")
        XCTAssertTrue(
            namespaces(in: scene).contains { $0.imageRenderPasses.contains { $0.colorEffects == [.brightness(0)] } },
            "The fixture must exercise color-effect source namespaces as well as symbol namespaces")
        try assertFinalAtlasShared(by: scene, glyphCount: characters.count)
        let pixels = GPUIRawSceneRasterizer.rasterize(scene, size: size)
        for index in [0, 31, 63] {
            assertCoverage(
                pixels, x: 8 + (index % 8) * 12, y: 8 + (index / 8) * 12, character: characters[index])
        }
    }

    func testNewGlyphsAndCleanSourceReplayShareANewAtlasWithoutMutatingTheOldScene() async throws {
        installAtlas()
        defer { restoreAtlas() }
        let cleanCharacter = Character(Unicode.Scalar(0x410)!)
        let oldCharacter = Character(Unicode.Scalar(0x430)!)
        let newCharacter = Character(Unicode.Scalar(0x450)!)
        let cleanSource = try XCTUnwrap(symbol(cleanCharacter, colorPass: true))
        let oldSource = try XCTUnwrap(symbol(oldCharacter))
        let size = IntSize(width: 64, height: 32)
        let runtime = RetainedViewRuntime(clearColor: .clear)
        runtime.setRootSize(size)
        let changedCanvas = canvas([oldSource], frame: Rect(x: 0, y: 0, width: 16, height: 16), runtime: runtime)
        let cleanCanvas = canvas([cleanSource], frame: Rect(x: 16, y: 0, width: 16, height: 16), runtime: runtime)
        runtime.root.setChildren([changedCanvas, cleanCanvas])

        let oldScene = runtime.renderScene()
        let oldAtlas = try assertFinalAtlasShared(by: oldScene, glyphCount: 2)
        let oldAddress = storageAddress(oldAtlas.pixels)
        // An independent byte copy detects accidental mutation even if a
        // future implementation writes through an aliased unsafe pointer.
        let savedOldBytes = [UInt8](oldAtlas.pixels)
        let oldPixels = GPUIRawSceneRasterizer.rasterize(oldScene, size: size)
        assertCoverage(oldPixels, x: 8, y: 8, character: oldCharacter)
        assertCoverage(oldPixels, x: 24, y: 8, character: cleanCharacter)

        let newSource = try XCTUnwrap(symbol(newCharacter))
        changedCanvas.canvasDraw = { context, _ in
            context.draw(newSource, in: Rect(x: 4, y: 4, width: 8, height: 8))
        }
        let newScene = runtime.renderScene()
        XCTAssertGreaterThan(runtime.lastSceneReplayCount, 0, "The unchanged source-bearing Canvas must replay")
        let newAtlas = try assertFinalAtlasShared(by: newScene, glyphCount: 2)
        XCTAssertGreaterThan(newAtlas.contentVersion, oldAtlas.contentVersion)
        XCTAssertNotEqual(
            storageAddress(newAtlas.pixels), oldAddress, "A live old scene owns the previous atlas storage")
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
            "Keeping an earlier scene alive must preserve its glyph pixels and drawing output")
    }

    func testCleanRuntimeWithOnlyNestedGlyphsRebuildsAfterAtlasReset() async throws {
        installAtlas()
        defer { restoreAtlas() }
        let character = Character(Unicode.Scalar(0x440)!)
        let source = try XCTUnwrap(symbol(character, colorPass: true))
        let size = IntSize(width: 32, height: 32)
        let runtime = RetainedViewRuntime(clearColor: .clear)
        runtime.setRootSize(size)
        runtime.root.addChild(canvas([source], frame: Rect(x: 0, y: 0, width: 32, height: 32), runtime: runtime))
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
        // No node was dirtied. Nested native glyph use must participate in
        // the runtime's generation check before its clean-cache early return.
        let rebuilt = runtime.renderScene()
        XCTAssertEqual(runtime.sceneRebuildCount, rebuildsBefore + 1)
        XCTAssertEqual(NativeGlyphAtlas.shared.cachedGlyphCount, 1)
        try assertFinalAtlasShared(by: rebuilt, glyphCount: 1)
        XCTAssertEqual(GPUIRawSceneRasterizer.rasterize(rebuilt, size: size), expected)
        XCTAssertEqual(
            GPUIRawSceneRasterizer.rasterize(original, size: size), expected,
            "Resetting the shared atlas must not rewrite an already returned scene")
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
