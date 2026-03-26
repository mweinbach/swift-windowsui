import XCTest
import SwiftWindowsCore
import SwiftWindowsGraphics
import WinSDK
@testable import SwiftWindowsUI

final class TextSystemTests: XCTestCase {
    func testCapabilitiesFallBackToPixelFontWhenDWriteMissing() async {
        let loader = MockTextLibraryLoader(moduleAvailable: false, hasFactorySymbol: false, factoryCreationResult: nil)

        let capabilities = await MainActor.run {
            TextSystem.capabilities(loader: loader)
        }

        XCTAssertEqual(capabilities.backend, .pixelFont)
        XCTAssertFalse(capabilities.dwriteLibraryLoaded)
        XCTAssertFalse(capabilities.dwriteCreateFactoryAvailable)
        XCTAssertFalse(capabilities.dwriteFactoryCreationSucceeded)
    }

    func testCapabilitiesKeepPixelFontWhenFactoryCreationFails() async {
        let loader = MockTextLibraryLoader(
            moduleAvailable: true,
            hasFactorySymbol: true,
            factoryCreationResult: (HRESULT(bitPattern: 0x80004005), nil)
        )

        let capabilities = await MainActor.run {
            TextSystem.capabilities(loader: loader)
        }

        XCTAssertEqual(capabilities.backend, .pixelFont)
        XCTAssertTrue(capabilities.dwriteLibraryLoaded)
        XCTAssertTrue(capabilities.dwriteCreateFactoryAvailable)
        XCTAssertFalse(capabilities.dwriteFactoryCreationSucceeded)
    }

    func testCapabilitiesReportDirectWriteReadyWhenFactoryCreationSucceeds() async {
        let loader = MockTextLibraryLoader(
            moduleAvailable: true,
            hasFactorySymbol: true,
            factoryCreationResult: (0, UnsafeMutableRawPointer(bitPattern: 1))
        )

        let capabilities = await MainActor.run {
            TextSystem.capabilities(loader: loader)
        }

        XCTAssertEqual(capabilities.backend, .directWriteReady)
        XCTAssertTrue(capabilities.dwriteLibraryLoaded)
        XCTAssertTrue(capabilities.dwriteCreateFactoryAvailable)
        XCTAssertTrue(capabilities.dwriteFactoryCreationSucceeded)
    }

    func testDirectWriteRendererProducesBitmapCommandWhenAvailable() async throws {
        let capabilities = await MainActor.run {
            TextSystem.capabilities()
        }

        guard capabilities.dwriteFactoryCreationSucceeded else {
            throw XCTSkip("DirectWrite is not available on this environment")
        }

        let result = await MainActor.run { () -> (Size?, Bool) in
            let style = PixelTextStyle(color: .white, scale: 2, alignment: .leading, weight: .semibold)
            var commands: [RenderCommand] = []
            let measured = DirectWriteTextRenderer.measure("DirectWrite", style: style, scaleFactor: 1.0)
            let didAppend = DirectWriteTextRenderer.appendCommands(
                for: "DirectWrite",
                in: Rect(x: 0, y: 0, width: 180, height: 40),
                style: style,
                scaleFactor: 1.0,
                clipRect: nil,
                into: &commands
            )
            let hasBitmap = commands.contains { command in
                if case .drawBitmap = command {
                    return true
                }
                return false
            }
            return (measured, didAppend && hasBitmap)
        }

        XCTAssertNotNil(result.0)
        XCTAssertTrue(result.1)
    }

    func testDirectWriteLayoutProducesGlyphPlacementsWhenAvailable() async throws {
        let capabilities = await MainActor.run {
            TextSystem.capabilities()
        }

        guard capabilities.dwriteFactoryCreationSucceeded else {
            throw XCTSkip("DirectWrite is not available on this environment")
        }

        let result = await MainActor.run { () -> NativeTextLayoutResult? in
            let style = PixelTextStyle(
                color: .white,
                alignment: .leading,
                verticalAlignment: .top,
                nativeFontSize: 18
            )
            return NativeTextRenderer.layout("Hello", style: style, scaleFactor: 1.0, maxWidth: 200)
        }

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.lines.count, 1)
        XCTAssertEqual(result?.lines.first?.glyphs.count, 5)
        XCTAssertGreaterThan(result?.lines.first?.glyphs.last?.origin.x ?? 0, result?.lines.first?.glyphs.first?.origin.x ?? 0)
        XCTAssertNotNil(result?.lines.first?.glyphs.first?.glyphID)
        XCTAssertNotNil(result?.lines.first?.glyphs.first?.fontFace)
    }

    func testWindowTextSystemReusesLogicalLayoutAcrossScaleChanges() async throws {
        let capabilities = await MainActor.run {
            TextSystem.capabilities()
        }

        guard capabilities.dwriteFactoryCreationSucceeded else {
            throw XCTSkip("DirectWrite is not available on this environment")
        }

        let result = await MainActor.run { () -> (NativeTextLayoutResult?, NativeTextLayoutResult?, Int) in
            let system = WindowTextSystem()
            let style = PixelTextStyle(
                color: .white,
                alignment: .leading,
                verticalAlignment: .top,
                nativeFontSize: 18
            )
            let first = system.layout("Cache me", style: style, maxWidth: 240, scaleFactor: 1.0)
            let second = system.layout("Cache me", style: style, maxWidth: 240, scaleFactor: 2.0)
            return (first, second, system.cachedLayoutCount)
        }

        XCTAssertEqual(result.2, 1)
        XCTAssertEqual(result.0?.lines.first?.glyphs.map(\.origin.x), result.1?.lines.first?.glyphs.map(\.origin.x))
    }

    func testSnapLogicalTextSizeRoundsUpToWholePixels() {
        let snapped = snapLogicalTextSize(Size(width: 18.2, height: 9.1), scaleFactor: 1.5)

        XCTAssertEqual(snapped.width, 18.666666666666668, accuracy: 0.0001)
        XCTAssertEqual(snapped.height, 9.333333333333334, accuracy: 0.0001)
    }

    func testResolveTextLayoutTruncatesSingleLineToFit() {
        let style = PixelTextStyle(color: .white, lineBreakMode: .truncateTail)

        let layout = resolveTextLayout(
            for: "HELLO WORLD",
            style: style,
            maxContentWidth: 8
        ) { line in
            Double(line.count)
        }

        XCTAssertEqual(layout.lines, ["HELLO..."])
    }

    func testResolveTextLayoutWrapsAndAppliesLineLimit() {
        let style = PixelTextStyle(color: .white, lineBreakMode: .wrap, maximumNumberOfLines: 2)

        let layout = resolveTextLayout(
            for: "ALPHA BETA GAMMA DELTA",
            style: style,
            maxContentWidth: 10
        ) { line in
            Double(line.count)
        }

        XCTAssertEqual(layout.lines, ["ALPHA BETA", "GAMMA..."])
    }
}

private struct MockTextLibraryLoader: TextLibraryLoading {
    let moduleAvailable: Bool
    let hasFactorySymbol: Bool
    let factoryCreationResult: (HRESULT, UnsafeMutableRawPointer?)?

    func loadLibrary(named name: String) -> HMODULE? {
        moduleAvailable ? HMODULE(bitPattern: 1) : nil
    }

    func unloadLibrary(_ module: HMODULE) {}

    func loadSymbol(named name: String, from module: HMODULE) -> FARPROC? {
        hasFactorySymbol ? mockFarProc : nil
    }

    func createDWriteFactory(from module: HMODULE, iid: UnsafePointer<GUID>) -> (HRESULT, UnsafeMutableRawPointer?)? {
        factoryCreationResult
    }

    func releaseFactory(_ rawPointer: UnsafeMutableRawPointer) {}
}

private let mockFarProc: FARPROC = {
    0
}
