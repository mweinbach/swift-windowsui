import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Ordinary bitmap stretch only. Aspect, cap-inset, tiling, and symbol-image
/// behavior need separate conformance work, not altered expectations here.
@MainActor
final class WinSwiftUIBitmapStretchTests: XCTestCase {
    private static let size = IntSize(width: 24, height: 24)
    private static let green = Color(red: 0, green: 1, blue: 0, alpha: 1)

    private func bitmap(width: Int32 = 1, height: Int32 = 1) -> BitmapSurface {
        BitmapSurface(
            width: width, height: height, bytesPerRow: width * 4,
            pixels: Data((0..<(Int(width) * Int(height))).flatMap { _ in [UInt8(0), 255, 0, 255] }))
    }

    private func snapshot<Content: View>(_ content: Content, displayScale: Double = 1) -> WinSwiftUIRenderSnapshot {
        WinSwiftUIRendererSnapshotter.snapshot(
            of: content.frame(width: 24, height: 24, alignment: .topLeading),
            size: Self.size, displayScale: displayScale, clearColor: .clear)
    }

    private func pixelSize(_ result: WinSwiftUIRenderSnapshot) -> IntSize {
        IntSize(
            width: Int32(Double(result.size.width) * result.displayScale),
            height: Int32(Double(result.size.height) * result.displayScale))
    }

    private func raster(_ result: WinSwiftUIRenderSnapshot) -> BitmapSurface {
        GPUIRawSceneRasterizer.rasterize(result.scene, size: pixelSize(result))
    }

    private func imageNode(in runtime: RetainedViewRuntime) throws -> ViewNode {
        var pending = [runtime.root]
        while let node = pending.popLast() {
            if node.bitmapSurface != nil { return node }
            pending.append(contentsOf: node.children)
        }
        return try XCTUnwrap(nil, "The public Image must produce a retained bitmap node")
    }

    private func primitive(in result: WinSwiftUIRenderSnapshot) throws -> ImagePrimitive {
        let images = result.scene.layers.flatMap(\.images)
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(result.scene.imageResources.count, 1)
        XCTAssertTrue(result.scene.imageRenderPasses.isEmpty, "Stretch must not pre-rasterize an image-sized layer")
        XCTAssertTrue(result.scene.validate().isEmpty)
        return try XCTUnwrap(images.first)
    }

    private func assertPixel(
        _ surface: BitmapSurface, x: Int, y: Int, color: Color,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let pixel = try XCTUnwrap(surface.pixelColor(atX: x, y: y), file: file, line: line)
        XCTAssertEqual(pixel.red, color.red, accuracy: 1 / 255, file: file, line: line)
        XCTAssertEqual(pixel.green, color.green, accuracy: 1 / 255, file: file, line: line)
        XCTAssertEqual(pixel.blue, color.blue, accuracy: 1 / 255, file: file, line: line)
        XCTAssertEqual(pixel.alpha, color.alpha, accuracy: 1 / 255, file: file, line: line)
    }

    private func visiblePixelCount(_ surface: BitmapSurface) -> Int {
        (0..<Int(surface.height)).reduce(0) { total, y in
            total
                + (0..<Int(surface.width)).filter { x in
                    surface.pixels[y * Int(surface.bytesPerRow) + x * 4 + 3] > 0
                }.count
        }
    }

    func testOnePixelImageResourceFillsItsEightPixelFrame() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "swift-windowsui-bitmap-stretch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer {
            if directory.deletingLastPathComponent().standardizedFileURL
                == FileManager.default.temporaryDirectory.standardizedFileURL,
                directory.lastPathComponent.hasPrefix("swift-windowsui-bitmap-stretch-")
            {
                do { try FileManager.default.removeItem(at: directory) } catch {
                    XCTFail("Could not remove the owned bitmap resource fixture: \(error)")
                }
            } else {
                XCTFail("Refusing cleanup outside the owned bitmap resource fixture")
            }
        }
        let url = directory.appendingPathComponent("one-pixel.bmp")
        try bitmap().writeBMP(to: url)

        let result = snapshot(
            Image(ImageResource(name: url.path, bundle: .main)).resizable().frame(width: 8, height: 8))
        let node = try imageNode(in: result.runtime)
        XCTAssertEqual(node.resolvedFrame.size, Size(width: 8, height: 8))
        XCTAssertNil(node.preferredSize)
        XCTAssertEqual(node.layoutFillAxes, .both)
        XCTAssertEqual(node.bitmapSurface?.width, 1)
        XCTAssertEqual(node.bitmapSurface?.height, 1)
        let image = try primitive(in: result)
        XCTAssertEqual(image.screenW, 8)
        XCTAssertEqual(image.screenH, 8)
        let pixels = raster(result)
        XCTAssertEqual(visiblePixelCount(pixels), 64)
        try assertPixel(pixels, x: 0, y: 0, color: Self.green)
        try assertPixel(pixels, x: 7, y: 7, color: Self.green)
        try assertPixel(pixels, x: 8, y: 7, color: .clear)
    }

    func testOrdinaryStretchChangesBothAxesWithoutResamplingTheSource() async throws {
        let source = bitmap(width: 2, height: 1)
        let result = snapshot(Image(bitmap: source).resizable().frame(width: 6, height: 10))
        let node = try imageNode(in: result.runtime)
        XCTAssertEqual(node.resolvedFrame.size, Size(width: 6, height: 10))
        XCTAssertEqual(node.bitmapSurface, source)
        XCTAssertEqual(result.scene.imageResources.first?.bitmap, source)
        let image = try primitive(in: result)
        XCTAssertEqual(image.screenW, 6)
        XCTAssertEqual(image.screenH, 10)
        let pixels = raster(result)
        XCTAssertEqual(visiblePixelCount(pixels), 60)
        try assertPixel(pixels, x: 5, y: 9, color: Self.green)
        try assertPixel(pixels, x: 6, y: 9, color: .clear)
    }

    func testNonResizableBitmapKeepsIntrinsicSizeInsideALargerFrame() async throws {
        let result = snapshot(Image(bitmap: bitmap(width: 2, height: 2)).frame(width: 8, height: 8))
        let node = try imageNode(in: result.runtime)
        XCTAssertEqual(node.preferredSize, Size(width: 2, height: 2))
        XCTAssertEqual(node.resolvedFrame, Rect(x: 3, y: 3, width: 2, height: 2))
        XCTAssertEqual(node.layoutFillAxes, LayoutFillAxes())
        let image = try primitive(in: result)
        XCTAssertEqual(image.screenX, 3)
        XCTAssertEqual(image.screenY, 3)
        XCTAssertEqual(image.screenW, 2)
        XCTAssertEqual(image.screenH, 2)
        let pixels = raster(result)
        XCTAssertEqual(visiblePixelCount(pixels), 4)
        try assertPixel(pixels, x: 3, y: 3, color: Self.green)
        try assertPixel(pixels, x: 2, y: 3, color: .clear)
    }

    func testExplicitFrameCanShrinkAResizableBitmap() async throws {
        let source = bitmap(width: 12, height: 8)
        let result = snapshot(Image(bitmap: source).resizable().frame(width: 4, height: 2))
        let node = try imageNode(in: result.runtime)
        XCTAssertEqual(node.resolvedFrame.size, Size(width: 4, height: 2))
        XCTAssertEqual(node.bitmapSurface, source)
        let image = try primitive(in: result)
        XCTAssertEqual(image.screenW, 4)
        XCTAssertEqual(image.screenH, 2)
        let pixels = raster(result)
        XCTAssertEqual(visiblePixelCount(pixels), 8)
        try assertPixel(pixels, x: 3, y: 1, color: Self.green)
        try assertPixel(pixels, x: 4, y: 1, color: .clear)
    }

    func testLargerOuterFrameAlignsRatherThanReplacingTheStretchFrame() async throws {
        let result = snapshot(
            Image(bitmap: bitmap()).resizable().frame(width: 8, height: 8)
                .frame(width: 12, height: 12, alignment: .bottomTrailing))
        let image = try primitive(in: result)
        XCTAssertEqual(image.screenX, 4)
        XCTAssertEqual(image.screenY, 4)
        XCTAssertEqual(image.screenW, 8)
        XCTAssertEqual(image.screenH, 8)
        let pixels = raster(result)
        XCTAssertEqual(visiblePixelCount(pixels), 64)
        try assertPixel(pixels, x: 4, y: 4, color: Self.green)
        try assertPixel(pixels, x: 11, y: 11, color: Self.green)
        try assertPixel(pixels, x: 3, y: 4, color: .clear)
    }

    private func offsetImage() -> some View {
        Image(bitmap: bitmap()).resizable().frame(width: 8, height: 8)
            .offset(x: 4, y: 2).frame(width: 8, height: 8, alignment: .topLeading)
    }

    func testFrameDoesNotClipStretchButExplicitClippedDoes() async throws {
        let unclipped = snapshot(offsetImage())
        let clipped = snapshot(offsetImage().clipped())
        let original = try primitive(in: unclipped)
        let restricted = try primitive(in: clipped)
        XCTAssertEqual(original.screenX, restricted.screenX)
        XCTAssertEqual(original.screenY, restricted.screenY)
        XCTAssertEqual(original.screenW, restricted.screenW)
        XCTAssertEqual(original.screenH, restricted.screenH)
        let fullPixels = raster(unclipped)
        let clippedPixels = raster(clipped)
        XCTAssertEqual(visiblePixelCount(fullPixels), 64)
        XCTAssertEqual(visiblePixelCount(clippedPixels), 24)
        try assertPixel(fullPixels, x: 10, y: 4, color: Self.green)
        try assertPixel(clippedPixels, x: 10, y: 4, color: .clear)
        try assertPixel(clippedPixels, x: 6, y: 4, color: Self.green)
        try assertPixel(clippedPixels, x: 6, y: 9, color: .clear)
    }

    func testDisplayScaleChangesDestinationPixelsButNotSourceDimensions() async throws {
        let source = bitmap()
        for scale in [1.0, 2.0] {
            let result = snapshot(Image(bitmap: source).resizable().frame(width: 8, height: 6), displayScale: scale)
            XCTAssertEqual(try imageNode(in: result.runtime).resolvedFrame.size, Size(width: 8, height: 6))
            let image = try primitive(in: result)
            XCTAssertEqual(image.screenW, Float(8 * scale))
            XCTAssertEqual(image.screenH, Float(6 * scale))
            XCTAssertEqual(result.scene.imageResources.first?.bitmap, source)
            let pixels = raster(result)
            XCTAssertEqual(visiblePixelCount(pixels), Int(48 * scale * scale))
            try assertPixel(pixels, x: Int(8 * scale) - 1, y: Int(6 * scale) - 1, color: Self.green)
            try assertPixel(pixels, x: Int(8 * scale), y: 0, color: .clear)
        }
    }

    func testReconciliationCanEnableAndDisableStretchOnTheRetainedImage() async throws {
        let runtime = RetainedViewRuntime(clearColor: .clear, root: ViewNode())
        runtime.setRootSize(Self.size)
        let host = ComponentHost(runtime: runtime)
        let context = ViewBuildContext(canvasSizeProvider: { Size(width: 24, height: 24) }, invalidateHandler: {})
        let source = bitmap(width: 2, height: 2)
        var stretches = false
        host.setComponents {
            let image = Image(bitmap: source)
            return [(stretches ? image.resizable() : image).frame(width: 8, height: 8).makeComponent(context: context)]
        }
        _ = runtime.renderScene()
        let retained = try imageNode(in: runtime)
        XCTAssertEqual(retained.resolvedFrame.size, Size(width: 2, height: 2))

        stretches = true
        host.reload()
        let stretched = runtime.renderScene()
        XCTAssertTrue(try imageNode(in: runtime) === retained)
        XCTAssertNil(retained.preferredSize)
        XCTAssertEqual(retained.resolvedFrame.size, Size(width: 8, height: 8))
        XCTAssertEqual(retained.bitmapSurface, source)
        XCTAssertEqual(visiblePixelCount(GPUIRawSceneRasterizer.rasterize(stretched, size: Self.size)), 64)

        stretches = false
        host.reload()
        _ = runtime.renderScene()
        XCTAssertTrue(try imageNode(in: runtime) === retained)
        XCTAssertEqual(retained.layoutFillAxes, LayoutFillAxes())
        XCTAssertEqual(retained.preferredSize, Size(width: 2, height: 2))
        XCTAssertEqual(retained.resolvedFrame.size, Size(width: 2, height: 2))
    }

    func testSceneAndFrameRasterizersAgreeOnStretchedAndClippedPixels() async {
        for view in [AnyView(offsetImage()), AnyView(offsetImage().clipped())] {
            let result = snapshot(view)
            let framePixels = GPUIRawSceneRasterizer.rasterize(result.frame, size: Self.size)
            XCTAssertEqual(framePixels.premultipliedAlpha().pixels, raster(result).premultipliedAlpha().pixels)
        }
    }

    func testStretchAndClipSceneMatchesD3D11AtBothDisplayScales() async throws {
        for scale in [1.0, 2.0] {
            let result = snapshot(offsetImage().clipped().opacity(0.5), displayScale: scale)
            let expected = raster(result).premultipliedAlpha()
            let actual = try WARPBatchRenderer.render(result.scene, size: pixelSize(result))
            let report = comparePixels(actual, expected, tolerance: 3)
            XCTAssertEqual(
                report.matchRatio, 1,
                "Stretch/clip CPU-D3D11 mismatch at scale \(scale): \(String(describing: report.firstFailure))")
        }
    }
}
