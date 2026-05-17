import SwiftWindowsCore

import XCTest

@testable import SwiftWindowsRendererD3D11

final class D3D11RendererTests: XCTestCase {
    func testDirect2DFactoryCanBeCreated() async throws {
        try await MainActor.run {
            try D3D11Renderer.validateDirect2DInteropForTesting()
        }
    }

    func testShaderSourceCompiles() async throws {
        try await MainActor.run {
            try D3D11Renderer.validateShaderSourceForTesting()
        }
    }

    func testPixelAlignedBitmapRectUsesBitmapDimensions() {
        let rect = Rect(x: 10.25, y: 5.5, width: 18.8, height: 9.6)
        let bitmapSize = IntSize(width: 29, height: 15)

        let aligned = makePixelAlignedBitmapRect(from: rect, bitmapSize: bitmapSize, scaleFactor: 1.5)

        XCTAssertEqual(aligned, Rect(x: 15, y: 8, width: 29, height: 15))
    }

    func testLogicalBitmapRectUsesBitmapDimensionsAtScale() {
        let rect = Rect(x: 10.25, y: 5.5, width: 18.8, height: 9.6)
        let bitmapSize = IntSize(width: 29, height: 15)

        let aligned = makeLogicalBitmapRect(from: rect, bitmapSize: bitmapSize, scaleFactor: 1.5)

        XCTAssertEqual(aligned, Rect(x: 10, y: 16.0 / 3.0, width: 58.0 / 3.0, height: 10))
    }
}
