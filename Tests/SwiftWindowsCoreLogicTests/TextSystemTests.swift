import XCTest
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
