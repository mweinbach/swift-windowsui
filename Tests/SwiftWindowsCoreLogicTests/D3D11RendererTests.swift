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

    func testBlendModeMappingUsesAvailableD3D11States() {
        XCTAssertEqual(d3d11BlendMode(for: .normal), .normal)
        XCTAssertEqual(d3d11BlendMode(for: .additive), .additive)
        XCTAssertEqual(d3d11BlendMode(for: .multiply), .multiply)
        XCTAssertEqual(d3d11BlendMode(for: .screen), .screen)
        XCTAssertEqual(d3d11BlendMode(for: .overlay), .normal)
    }

    func testPathBufferEncodesSegmentsAndPoints() {
        var path = RenderPath()
        path.move(to: Point(x: 10, y: 20))
        path.addLine(to: Point(x: 30, y: 40))
        path.addQuadCurve(to: Point(x: 70, y: 80), control: Point(x: 50, y: 60))
        path.addCubicCurve(
            to: Point(x: 130, y: 140),
            control1: Point(x: 90, y: 100),
            control2: Point(x: 110, y: 120)
        )
        path.close()

        let buffer = d2dPathBuffer(from: path)

        XCTAssertEqual(buffer.segmentTypes, [
            0,
            1,
            2,
            3,
            4,
        ])
        XCTAssertEqual(buffer.points, [
            10, 20,
            30, 40,
            50, 60, 70, 80,
            90, 100, 110, 120, 130, 140,
        ])
    }

    func testPathBufferAppliesAffineTransform() {
        var path = RenderPath()
        path.move(to: Point(x: 10, y: 20))
        path.addLine(to: Point(x: 30, y: 40))

        let transform = SwiftWindowsGraphics.AffineTransform(a: 2, b: 0, c: 0, d: 3, tx: 5, ty: 7)
        let buffer = d2dPathBuffer(from: path, transform: transform)

        XCTAssertEqual(buffer.points, [
            25, 67,
            65, 127,
        ])
    }

    func testStrokeStyleMappingUsesDirect2DConstants() {
        XCTAssertEqual(d2dLineCap(.butt), 0)
        XCTAssertEqual(d2dLineCap(.round), 1)
        XCTAssertEqual(d2dLineCap(.square), 2)

        XCTAssertEqual(d2dLineJoin(.miter), 0)
        XCTAssertEqual(d2dLineJoin(.round), 1)
        XCTAssertEqual(d2dLineJoin(.bevel), 2)
    }

    func testPathFillGradientFallsBackToFirstStopColor() {
        var path = RenderPath()
        path.move(to: Point(x: 0, y: 0))
        path.addLine(to: Point(x: 10, y: 0))

        let color = Color(red: 0.7, green: 0.2, blue: 0.1, alpha: 0.9)
        let command = FillPathCommand(
            path: path,
            color: .white,
            gradient: .linear(LinearGradient(startColor: color, endColor: .black))
        )

        XCTAssertEqual(solidPathFillColor(for: command), color)
    }

    func testDirectWriteLayoutRectUsesMaxWidthAndLargeHeight() {
        let command = DrawTextCommand(
            text: "Hello",
            position: Point(x: 12, y: 34),
            fontSize: 18,
            maxWidth: 240
        )

        XCTAssertEqual(directWriteLayoutRect(for: command), Rect(x: 12, y: 34, width: 240, height: 4096))
    }

    func testDirectWriteFontWeightMapping() {
        XCTAssertEqual(directWriteFontWeight(.thin), 100)
        XCTAssertEqual(directWriteFontWeight(.light), 300)
        XCTAssertEqual(directWriteFontWeight(.regular), 400)
        XCTAssertEqual(directWriteFontWeight(.medium), 500)
        XCTAssertEqual(directWriteFontWeight(.semibold), 600)
        XCTAssertEqual(directWriteFontWeight(.bold), 700)
        XCTAssertEqual(directWriteFontWeight(.heavy), 800)
        XCTAssertEqual(directWriteFontWeight(.black), 900)
    }
}
