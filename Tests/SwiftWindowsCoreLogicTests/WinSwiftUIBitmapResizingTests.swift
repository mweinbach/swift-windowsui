import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Windows sampling policy for admitted full-source bitmaps. These fixtures
/// do not qualify native SwiftUI cap, tile, or interpolation behavior.
@MainActor
final class WinSwiftUIBitmapResizingTests: XCTestCase {
    private static let size = IntSize(width: 24, height: 24)
    private static let caps = EdgeInsets(top: 1, leading: 1, bottom: 1, trailing: 1)
    private static let colors: [Color] = [
        Color(red: 1, green: 0, blue: 0, alpha: 1),
        Color(red: 0, green: 1, blue: 0, alpha: 1),
        Color(red: 0, green: 0, blue: 1, alpha: 1),
        Color(red: 0, green: 1, blue: 1, alpha: 1),
        Color(red: 1, green: 0, blue: 1, alpha: 1),
        Color(red: 1, green: 1, blue: 0, alpha: 1),
        Color(red: 1, green: 1, blue: 1, alpha: 1),
        Color(red: 0.5, green: 0.5, blue: 0.5, alpha: 1),
        Color(red: 0, green: 0, blue: 0, alpha: 1),
    ]

    private func bitmap(width: Int32, colors: [Color]) -> BitmapSurface {
        let pixels = colors.flatMap { color in
            [
                UInt8((color.blue * 255).rounded()),
                UInt8((color.green * 255).rounded()),
                UInt8((color.red * 255).rounded()),
                UInt8((color.alpha * 255).rounded()),
            ]
        }
        return BitmapSurface(
            width: width, height: Int32(colors.count) / width,
            bytesPerRow: width * 4, pixels: Data(pixels))
    }

    private func nineRegions(leadingWidth: Int = 1) -> BitmapSurface {
        var colors: [Color] = []
        for row in 0..<3 {
            let base: Int = row * 3
            let leading: [Color] = Array(repeating: Self.colors[base], count: leadingWidth)
            colors.append(contentsOf: leading)
            colors.append(Self.colors[base + 1])
            colors.append(Self.colors[base + 2])
        }
        return bitmap(width: Int32(leadingWidth + 2), colors: colors)
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

    private func primitive(in scene: GPUIScene) throws -> ImagePrimitive {
        let images = scene.layers.flatMap(\.images)
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(scene.imageResources.count, 1)
        XCTAssertTrue(scene.imageRenderPasses.isEmpty, "Resizing must not allocate a destination image")
        XCTAssertTrue(scene.validate().isEmpty)
        return try XCTUnwrap(images.first)
    }

    private func bitmaps(in frame: RenderFrame) -> [DrawBitmapCommand] {
        frame.commands.compactMap {
            guard case .drawBitmap(let command) = $0 else { return nil }
            return command
        }
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

    func testZeroCapTileRepeatsSourcePixelsAndCropsTheLastTile() async throws {
        let source = bitmap(width: 3, colors: Array(Self.colors.prefix(3)))
        let result = snapshot(Image(bitmap: source).resizable(resizingMode: .tile).frame(width: 8, height: 4))
        let node = try imageNode(in: result.runtime)
        XCTAssertTrue(node.imageUsesBitmapResizing)
        XCTAssertNil(node.imageSamplingFailure)
        XCTAssertNil(node.preferredSize)
        XCTAssertEqual(node.layoutFillAxes, .both)
        XCTAssertEqual(node.resolvedFrame.size, Size(width: 8, height: 4))
        XCTAssertEqual(node.bitmapSurface?.contentKey, source.contentKey)
        let image = try primitive(in: result.scene)
        XCTAssertEqual(image.sampling.samplingKind, 2)
        XCTAssertEqual(image.sampling.centerRepeatX, 8 / 3, accuracy: 0.000001)
        XCTAssertEqual(image.sampling.centerRepeatY, 4)
        XCTAssertEqual(result.scene.imageResources.first?.bitmap, source)
        XCTAssertEqual(result.scene.imageResources.first?.bitmap.contentKey, source.contentKey)
        let pixels = raster(result)
        for y in 0..<4 {
            for x in 0..<8 {
                try assertPixel(pixels, x: x, y: y, color: Self.colors[x % 3])
            }
        }
        XCTAssertEqual(visiblePixelCount(pixels), 32)
        try assertPixel(pixels, x: 8, y: 0, color: .clear)
    }

    func testTiledTransparentColoredTexelsDoNotProduceAColorFringe() async throws {
        let source = bitmap(
            width: 2, colors: [Self.colors[0], Color(red: 0, green: 1, blue: 0, alpha: 0)])
        let result = snapshot(
            Image(bitmap: source).resizable(resizingMode: .tile).frame(width: 6, height: 2),
            displayScale: 2)
        _ = try primitive(in: result.scene)
        XCTAssertEqual(result.scene.imageResources.first?.bitmap, source)
        let pixels = raster(result)
        for y in 0..<4 {
            for x in 0..<12 {
                // Four device pixels span each two-texel repeat. Both seam
                // taps wrap locally, and transparent green contributes no RGB.
                let alpha: Float = x % 4 < 2 ? 0.75 : 0.25
                try assertPixel(
                    pixels, x: x, y: y, color: Color(red: 1, green: 0, blue: 0, alpha: alpha))
            }
        }
        try assertPixel(pixels, x: 12, y: 0, color: .clear)
    }

    func testCappedStretchAndTilePreserveNineDistinctRegions() async throws {
        let source = nineRegions()
        for mode in [Image.ResizingMode.stretch, .tile] {
            let result = snapshot(
                Image(bitmap: source).resizable(capInsets: Self.caps, resizingMode: mode)
                    .frame(width: 8, height: 6))
            let node = try imageNode(in: result.runtime)
            XCTAssertEqual(node.resolvedFrame.size, Size(width: 8, height: 6))
            XCTAssertNil(node.preferredSize)
            XCTAssertEqual(node.layoutFillAxes, .both)
            XCTAssertNil(node.imageSamplingFailure)
            let image = try primitive(in: result.scene)
            let sampling = image.sampling
            XCTAssertEqual(sampling.samplingKind, mode == .stretch ? 1 : 2)
            XCTAssertEqual(sampling.sourceCapLeft, 1 / 3, accuracy: 0.000001)
            XCTAssertEqual(sampling.sourceCapTop, 1 / 3, accuracy: 0.000001)
            XCTAssertEqual(sampling.sourceCapRight, 1 / 3, accuracy: 0.000001)
            XCTAssertEqual(sampling.sourceCapBottom, 1 / 3, accuracy: 0.000001)
            XCTAssertEqual(sampling.destinationCapLeft, 1 / 8)
            XCTAssertEqual(sampling.destinationCapTop, 1 / 6, accuracy: 0.000001)
            if mode == .tile {
                XCTAssertEqual(sampling.centerRepeatX, 6)
                XCTAssertEqual(sampling.centerRepeatY, 4)
            }
            let commands = bitmaps(in: result.frame)
            XCTAssertEqual(commands.count, 1)
            XCTAssertEqual(commands.first?.sampling, sampling)
            XCTAssertEqual(commands.first?.bitmap.contentKey, source.contentKey)
            XCTAssertEqual(result.scene.imageResources.first?.bitmap, source)
            let pixels = raster(result)
            for y in 0..<6 {
                for x in 0..<8 {
                    let row = y == 0 ? 0 : (y == 5 ? 2 : 1)
                    let column = x == 0 ? 0 : (x == 7 ? 2 : 1)
                    try assertPixel(pixels, x: x, y: y, color: Self.colors[row * 3 + column])
                }
            }
            XCTAssertEqual(visiblePixelCount(pixels), 48)
        }
    }

    func testAsymmetricLeadingCapUsesTheLeftSourceRegion() async throws {
        let source = nineRegions(leadingWidth: 2)
        let caps = EdgeInsets(top: 1, leading: 2, bottom: 1, trailing: 1)
        let result = snapshot(
            Image(bitmap: source).resizable(capInsets: caps, resizingMode: .tile).frame(width: 8, height: 6))
        let image = try primitive(in: result.scene)
        XCTAssertEqual(image.sampling.sourceCapLeft, 0.5)
        XCTAssertEqual(image.sampling.sourceCapRight, 0.25)
        XCTAssertEqual(image.sampling.destinationCapLeft, 0.25)
        XCTAssertEqual(image.sampling.destinationCapRight, 0.125)
        XCTAssertEqual(image.sampling.centerRepeatX, 5)
        let pixels = raster(result)
        for y in 1..<5 {
            try assertPixel(pixels, x: 0, y: y, color: Self.colors[3])
            try assertPixel(pixels, x: 1, y: y, color: Self.colors[3])
            try assertPixel(pixels, x: 2, y: y, color: Self.colors[4])
            try assertPixel(pixels, x: 7, y: y, color: Self.colors[5])
        }
    }

    func testDisplayScalePreservesLogicalTileAndCapSizes() async throws {
        let singlePixel = bitmap(width: 1, colors: [Self.colors[1]])
        let regions = nineRegions()
        for scale in [1.0, 1.25, 1.5, 2.0] {
            let tiled = snapshot(
                Image(bitmap: singlePixel).resizable(resizingMode: .tile).frame(width: 8, height: 4),
                displayScale: scale)
            let tile = try primitive(in: tiled.scene)
            XCTAssertEqual(tile.screenW, Float(8 * scale))
            XCTAssertEqual(tile.screenH, Float(4 * scale))
            XCTAssertEqual(tile.sampling.centerRepeatX, 8)
            XCTAssertEqual(tile.sampling.centerRepeatY, 4)
            XCTAssertEqual(tiled.scene.imageResources.first?.bitmap.contentKey, singlePixel.contentKey)
            let tiledPixels = raster(tiled)
            XCTAssertEqual(visiblePixelCount(tiledPixels), Int(32 * scale * scale))
            try assertPixel(
                tiledPixels, x: Int(8 * scale) - 1, y: Int(4 * scale) - 1, color: Self.colors[1])

            let capped = snapshot(
                Image(bitmap: regions).resizable(capInsets: Self.caps, resizingMode: .tile)
                    .frame(width: 8, height: 8), displayScale: scale)
            let image = try primitive(in: capped.scene)
            XCTAssertEqual(image.screenW, Float(8 * scale))
            XCTAssertEqual(image.screenH, Float(8 * scale))
            XCTAssertEqual(image.sampling.destinationCapLeft, 1 / 8)
            XCTAssertEqual(image.sampling.destinationCapTop, 1 / 8)
            XCTAssertEqual(image.sampling.centerRepeatX, 6)
            XCTAssertEqual(image.sampling.centerRepeatY, 6)
            XCTAssertEqual(capped.scene.imageResources.first?.bitmap.contentKey, regions.contentKey)
            let pixels = raster(capped)
            let probes = [0, Int(4 * scale), Int(8 * scale) - 1]
            for row in 0..<3 {
                for column in 0..<3 {
                    try assertPixel(
                        pixels, x: probes[column], y: probes[row], color: Self.colors[row * 3 + column])
                }
            }
        }
    }

    func testCappedTileSceneAndFrameAgreeWithOpacityOffsetAndClip() async throws {
        let result = snapshot(
            Image(bitmap: nineRegions()).resizable(capInsets: Self.caps, resizingMode: .tile)
                .frame(width: 8, height: 6).offset(x: 2, y: 1)
                .frame(width: 8, height: 6, alignment: .topLeading).clipped().opacity(0.5))
        let image = try primitive(in: result.scene)
        let commands = bitmaps(in: result.frame)
        XCTAssertEqual(commands.count, 1)
        XCTAssertEqual(commands.first?.sampling, image.sampling)
        let expected = raster(result).premultipliedAlpha()
        let actual = GPUIRawSceneRasterizer.rasterize(result.frame, size: Self.size).premultipliedAlpha()
        XCTAssertEqual(actual.pixels, expected.pixels)
    }

    func testInvalidCapsSkipOnlyTheImageAndRecordTypedFailures() async throws {
        let invalid: [(EdgeInsets, Double, ImageSamplingFailure)] = [
            (EdgeInsets(top: 0, leading: .nan, bottom: 0, trailing: 0), 8, .nonfiniteCapInsets),
            (EdgeInsets(top: 0, leading: -1, bottom: 0, trailing: 0), 8, .negativeCapInsets),
            (EdgeInsets(top: 0, leading: 0.5, bottom: 0, trailing: 0), 8, .fractionalCapInsets),
            (EdgeInsets(top: 0, leading: 3, bottom: 0, trailing: 0), 8, .sourceCenterNotPositive),
            (Self.caps, 2, .destinationCenterNotPositive),
        ]
        for (caps, width, failure) in invalid {
            let result = snapshot(
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(Self.colors[2]).frame(width: 8, height: 6)
                    Image(bitmap: nineRegions()).resizable(capInsets: caps, resizingMode: .tile)
                        .frame(width: width, height: 6)
                })
            let node = try imageNode(in: result.runtime)
            XCTAssertTrue(node.imageUsesBitmapResizing)
            XCTAssertEqual(node.imageSamplingFailure, failure)
            XCTAssertTrue(result.scene.layers.flatMap(\.images).isEmpty)
            XCTAssertTrue(result.scene.imageRenderPasses.isEmpty)
            XCTAssertTrue(bitmaps(in: result.frame).isEmpty)
            XCTAssertTrue(result.scene.validate().isEmpty)
            let pixels = raster(result)
            try assertPixel(pixels, x: 0, y: 0, color: Self.colors[2])
            try assertPixel(pixels, x: 7, y: 5, color: Self.colors[2])
        }
    }

    func testReconciliationChangesSamplingWithoutReplacingTheBitmapNode() async throws {
        let runtime = RetainedViewRuntime(clearColor: .clear, root: ViewNode())
        runtime.setRootSize(Self.size)
        let host = ComponentHost(runtime: runtime)
        let context = ViewBuildContext(canvasSizeProvider: { Size(width: 24, height: 24) }, invalidateHandler: {})
        let source = nineRegions()
        var mode: Image.ResizingMode = .tile
        var caps = EdgeInsets.zero
        var isResizable = true
        host.setComponents {
            let image = Image(bitmap: source)
            let content = isResizable ? image.resizable(capInsets: caps, resizingMode: mode) : image
            return [content.frame(width: 8, height: 6).makeComponent(context: context)]
        }
        let initial = runtime.renderScene()
        let retained = try imageNode(in: runtime)
        XCTAssertEqual(try primitive(in: initial).sampling.samplingKind, 2)

        caps = Self.caps
        mode = .stretch
        host.reload()
        let capped = runtime.renderScene()
        XCTAssertTrue(try imageNode(in: runtime) === retained)
        XCTAssertEqual(try primitive(in: capped).sampling.samplingKind, 1)
        XCTAssertEqual(retained.bitmapSurface?.contentKey, source.contentKey)
        XCTAssertEqual(capped.imageResources.first?.bitmap.contentKey, source.contentKey)

        caps.leading = 0.5
        host.reload()
        let failed = runtime.renderScene()
        XCTAssertTrue(try imageNode(in: runtime) === retained)
        XCTAssertEqual(retained.imageSamplingFailure, .fractionalCapInsets)
        XCTAssertTrue(failed.layers.flatMap(\.images).isEmpty)

        caps = Self.caps
        mode = .tile
        host.reload()
        let recovered = runtime.renderScene()
        XCTAssertTrue(try imageNode(in: runtime) === retained)
        XCTAssertNil(retained.imageSamplingFailure)
        XCTAssertEqual(try primitive(in: recovered).sampling.samplingKind, 2)
        XCTAssertEqual(recovered.imageResources.first?.bitmap.contentKey, source.contentKey)
        try assertPixel(
            GPUIRawSceneRasterizer.rasterize(recovered, size: Self.size), x: 4, y: 3, color: Self.colors[4])

        isResizable = false
        host.reload()
        let intrinsic = runtime.renderScene()
        XCTAssertTrue(try imageNode(in: runtime) === retained)
        XCTAssertFalse(retained.imageUsesBitmapResizing)
        XCTAssertNil(retained.imageSamplingFailure)
        XCTAssertEqual(retained.preferredSize, Size(width: 3, height: 3))
        XCTAssertEqual(retained.resolvedFrame.size, Size(width: 3, height: 3))
        XCTAssertEqual(retained.layoutFillAxes, LayoutFillAxes())
        XCTAssertEqual(try primitive(in: intrinsic).sampling, .legacy)
    }

    func testTilePhaseBoundKeepsOnePrimitiveWithoutAllocatingTheDestination() async throws {
        let source = bitmap(width: 1, colors: [Self.colors[1]])
        let limit = Double(ImageSamplingPlan.maximumTilePhase)
        XCTAssertEqual(limit, 4096)
        // Inspect records only: no rasterization of this large destination.
        let accepted = snapshot(
            Image(bitmap: source).resizable(resizingMode: .tile).frame(width: limit, height: 4))
        let image = try primitive(in: accepted.scene)
        XCTAssertEqual(image.screenW, Float(limit))
        XCTAssertEqual(image.sampling.centerRepeatX, Float(limit))
        XCTAssertEqual(accepted.scene.imageResources.first?.bitmap.contentKey, source.contentKey)
        XCTAssertNil(try imageNode(in: accepted.runtime).imageSamplingFailure)

        let rejected = snapshot(
            Image(bitmap: source).resizable(resizingMode: .tile).frame(width: limit + 1, height: 4))
        XCTAssertEqual(try imageNode(in: rejected.runtime).imageSamplingFailure, .phaseLimitExceeded)
        XCTAssertTrue(rejected.scene.layers.flatMap(\.images).isEmpty)
        XCTAssertTrue(rejected.scene.imageRenderPasses.isEmpty)
        XCTAssertTrue(bitmaps(in: rejected.frame).isEmpty)

        let stretch = snapshot(Image(bitmap: source).resizable().frame(width: limit + 1, height: 4))
        XCTAssertEqual(try primitive(in: stretch.scene).sampling, .legacy)
        XCTAssertNil(try imageNode(in: stretch.runtime).imageSamplingFailure)
    }

    func testCappedImageSceneMatchesD3D11AtFractionalDisplayScales() async throws {
        let source = nineRegions()
        for scale in [1.0, 1.25, 1.5, 2.0] {
            for mode in [Image.ResizingMode.stretch, .tile] {
                let result = snapshot(
                    Image(bitmap: source).resizable(capInsets: Self.caps, resizingMode: mode)
                        .frame(width: 8, height: 8).opacity(0.5), displayScale: scale)
                let expected = raster(result).premultipliedAlpha()
                let actual = try WARPBatchRenderer.render(result.scene, size: pixelSize(result))
                let report = comparePixels(actual, expected, tolerance: 3)
                XCTAssertEqual(
                    report.matchRatio, 1,
                    "Capped image mismatch at scale \(scale), mode \(mode): \(String(describing: report.firstFailure))")
            }
        }
    }
}
