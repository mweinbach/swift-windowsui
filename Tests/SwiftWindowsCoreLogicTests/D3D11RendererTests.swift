import XCTest
import SwiftWindowsCore
import SwiftWindowsGraphics
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

    func testLogicalSurfaceSizeUsesScaleFactor() {
        let size = makeLogicalSurfaceSize(pixelSize: IntSize(width: 600, height: 450), scaleFactor: 1.5)

        XCTAssertEqual(size, Size(width: 400, height: 300))
    }

    func testResolvedFillRectUsesClipStackAndCommandClip() {
        var clipStack = RenderClipStack(surfaceSize: Size(width: 300, height: 300))
        clipStack.push(ClipCommand(shape: .rect(Rect(x: 20, y: 20, width: 120, height: 120), cornerRadius: 0)))

        let command = FillRectCommand(
            rect: Rect(x: 0, y: 0, width: 300, height: 300),
            color: .white,
            clipRect: Rect(x: 80, y: 60, width: 120, height: 120)
        )

        let resolvedCommand = resolved(fillRect: command, clipStack: clipStack)

        XCTAssertEqual(resolvedCommand.clipRect, Rect(x: 80, y: 60, width: 60, height: 80))
    }

    func testResolvedBitmapPreservesBlendMode() {
        var clipStack = RenderClipStack(surfaceSize: Size(width: 100, height: 100))
        clipStack.push(ClipCommand(shape: .rect(Rect(x: 10, y: 10, width: 40, height: 40), cornerRadius: 0)))

        let bitmap = BitmapSurface(width: 2, height: 2, bytesPerRow: 8, pixels: Data(repeating: 0, count: 16))
        let command = DrawBitmapCommand(
            rect: Rect(x: 0, y: 0, width: 20, height: 20),
            bitmap: bitmap,
            opacity: 0.5,
            blendMode: .additive
        )

        let resolvedCommand = resolved(bitmap: command, clipStack: clipStack)

        XCTAssertEqual(resolvedCommand.clipRect, Rect(x: 10, y: 10, width: 40, height: 40))
        XCTAssertEqual(resolvedCommand.blendMode, .additive)
    }
}
