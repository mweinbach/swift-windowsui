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

    func testSnapLogicalTextSizeRoundsUpToWholePixels() {
        let snapped = snapLogicalTextSize(Size(width: 18.2, height: 9.1), scaleFactor: 1.5)

        XCTAssertEqual(snapped.width, 18.666666666666668, accuracy: 0.0001)
        XCTAssertEqual(snapped.height, 9.333333333333334, accuracy: 0.0001)
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
