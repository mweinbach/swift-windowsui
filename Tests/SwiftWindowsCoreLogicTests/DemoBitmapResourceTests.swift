import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsDemo
@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Named resources must load through the demo's actual SwiftPM bundle. The
/// aspect-fit geometry case requires the finite-proposal runtime join; it is
/// deliberately not skipped when that implementation is absent.
@MainActor
final class DemoBitmapResourceTests: XCTestCase {
    private let names = ["demo-bitmap-caps", "demo-bitmap-tile"]
    private let canvas = IntSize(width: 96, height: 96)

    private func bitmap(named name: String, bundle: Bundle) throws -> BitmapSurface {
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: name),
            "An existing working-directory path would bypass the explicit bundle lookup")
        let runtime = RetainedViewRuntime(root: ViewNode())
        let context = ViewBuildContext(canvasSizeProvider: { Size(width: 96, height: 96) }, invalidateHandler: {})
        let node = Image(name, bundle: bundle).makeComponent(context: context).makeNode(runtime: runtime)
        return try XCTUnwrap(node.bitmapSurface, "Missing named bitmap: \(name)")
    }

    private func snapshot(_ mode: DemoBitmapResizingSample.Mode) -> WinSwiftUIRenderSnapshot {
        WinSwiftUIRendererSnapshotter.snapshot(
            of: DemoBitmapResizingSample(mode), size: canvas, displayScale: 1, clearColor: .clear)
    }

    private func image(in result: WinSwiftUIRenderSnapshot) throws -> ImagePrimitive {
        let images = result.scene.layers.flatMap(\.images)
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(result.scene.imageResources.count, 1)
        XCTAssertTrue(result.scene.imageRenderPasses.isEmpty)
        XCTAssertTrue(result.scene.validate().isEmpty)
        return try XCTUnwrap(images.first)
    }

    private func assertPixel(
        _ bitmap: BitmapSurface, x: Int, y: Int, rgb: (UInt8, UInt8, UInt8),
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let color = try XCTUnwrap(bitmap.pixelColor(atX: x, y: y), file: file, line: line)
        XCTAssertEqual(color.red, Float(rgb.0) / 255, accuracy: 1 / 255, file: file, line: line)
        XCTAssertEqual(color.green, Float(rgb.1) / 255, accuracy: 1 / 255, file: file, line: line)
        XCTAssertEqual(color.blue, Float(rgb.2) / 255, accuracy: 1 / 255, file: file, line: line)
        XCTAssertEqual(color.alpha, 1, file: file, line: line)
    }

    func testGeneratedDemoBundleContainsBothPNGResources() async throws {
        let bundle = DemoBitmapResources.bundle
        let prefix = bundle.bundleURL.standardizedFileURL.path + "/"
        for name in names {
            let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "png"))
            XCTAssertTrue(url.standardizedFileURL.path.hasPrefix(prefix))
            XCTAssertEqual(url.lastPathComponent, "\(name).png")
            let data = try Data(contentsOf: url)
            XCTAssertEqual(Array(data.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
            XCTAssertLessThan(data.count, 1024)
        }
    }

    func testNamedImagesDecodeOwnedCornerAndTilePixels() async throws {
        let caps = try bitmap(named: names[0], bundle: DemoBitmapResources.bundle)
        XCTAssertEqual(caps.width, 24)
        XCTAssertEqual(caps.height, 16)
        try assertPixel(caps, x: 0, y: 0, rgb: (224, 93, 87))
        try assertPixel(caps, x: 23, y: 0, rgb: (245, 181, 82))
        try assertPixel(caps, x: 0, y: 15, rgb: (71, 174, 162))
        try assertPixel(caps, x: 23, y: 15, rgb: (100, 141, 219))
        try assertPixel(caps, x: 4, y: 4, rgb: (31, 47, 66))

        let tile = try bitmap(named: names[1], bundle: DemoBitmapResources.bundle)
        XCTAssertEqual(tile.width, 7)
        XCTAssertEqual(tile.height, 5)
        try assertPixel(tile, x: 0, y: 0, rgb: (71, 174, 162))
        try assertPixel(tile, x: 6, y: 4, rgb: (245, 181, 82))
    }

    func testCappedStretchSampleKeepsSourceAndFixedCorners() async throws {
        let result = snapshot(.cappedStretch)
        let primitive = try image(in: result)
        XCTAssertEqual(primitive.screenX, 0)
        XCTAssertEqual(primitive.screenY, 0)
        XCTAssertEqual(primitive.screenW, 96)
        XCTAssertEqual(primitive.screenH, 96)
        XCTAssertEqual(primitive.sampling.samplingKind, 1)
        XCTAssertEqual(primitive.sampling.destinationCapLeft, 4 / 96, accuracy: 0.000001)
        XCTAssertEqual(primitive.sampling.destinationCapTop, 4 / 96, accuracy: 0.000001)
        XCTAssertEqual(result.scene.imageResources.first?.bitmap.width, 24)
        XCTAssertEqual(result.scene.imageResources.first?.bitmap.height, 16)
        let pixels = GPUIRawSceneRasterizer.rasterize(result.scene, size: canvas)
        try assertPixel(pixels, x: 1, y: 1, rgb: (224, 93, 87))
        try assertPixel(pixels, x: 94, y: 1, rgb: (245, 181, 82))
        try assertPixel(pixels, x: 1, y: 94, rgb: (71, 174, 162))
        try assertPixel(pixels, x: 94, y: 94, rgb: (100, 141, 219))
    }

    func testTileSampleRepeatsAndCropsWithoutExpandingItsResource() async throws {
        let result = snapshot(.tile)
        let primitive = try image(in: result)
        XCTAssertEqual(primitive.screenW, 96)
        XCTAssertEqual(primitive.screenH, 96)
        XCTAssertEqual(primitive.sampling.samplingKind, 2)
        XCTAssertEqual(primitive.sampling.sourceCapLeft, 0)
        XCTAssertEqual(primitive.sampling.destinationCapTop, 0)
        XCTAssertEqual(primitive.sampling.centerRepeatX, 96 / 7, accuracy: 0.000001)
        XCTAssertEqual(primitive.sampling.centerRepeatY, 96 / 5, accuracy: 0.000001)
        let source = try XCTUnwrap(result.scene.imageResources.first?.bitmap)
        XCTAssertEqual(source.width, 7)
        XCTAssertEqual(source.height, 5)
        let pixels = GPUIRawSceneRasterizer.rasterize(result.scene, size: canvas)
        for y in 0..<96 {
            for x in 0..<96 {
                XCTAssertEqual(pixels.pixelColor(atX: x, y: y), source.pixelColor(atX: x % 7, y: y % 5))
            }
        }
    }

    func testCappedAspectFitUsesTheFiniteSquareProposal() async throws {
        let result = snapshot(.aspectFit)
        let primitive = try image(in: result)
        XCTAssertEqual(primitive.screenX, 0)
        XCTAssertEqual(primitive.screenY, 16)
        XCTAssertEqual(primitive.screenW, 96)
        XCTAssertEqual(primitive.screenH, 64)
        XCTAssertEqual(primitive.sampling.samplingKind, 2)
        XCTAssertEqual(primitive.sampling.sourceCapLeft, 4 / 24, accuracy: 0.000001)
        XCTAssertEqual(primitive.sampling.sourceCapTop, 4 / 16)
        XCTAssertEqual(primitive.sampling.destinationCapLeft, 4 / 96, accuracy: 0.000001)
        XCTAssertEqual(primitive.sampling.destinationCapTop, 4 / 64)
        XCTAssertEqual(primitive.sampling.centerRepeatX, 5.5)
        XCTAssertEqual(primitive.sampling.centerRepeatY, 7)
        XCTAssertEqual(result.scene.imageResources.first?.bitmap.width, 24)
        XCTAssertEqual(result.scene.imageResources.first?.bitmap.height, 16)
    }

    func testSamplesKeepTheirAccessibleNamesThroughFrames() async {
        let expected: [(DemoBitmapResizingSample.Mode, String)] = [
            (.cappedStretch, "Bitmap with fixed four point corners"),
            (.tile, "Repeating bitmap with partial edge tiles"),
            (.aspectFit, "Capped bitmap fitted inside a square"),
        ]
        for (mode, label) in expected {
            let result = snapshot(mode)
            var pending = [result.runtime.root]
            var labels: [String] = []
            while let node = pending.popLast() {
                if let label = node.accessibilityLabel { labels.append(label) }
                pending.append(contentsOf: node.children)
            }
            XCTAssertTrue(labels.contains(label))
        }
    }

    func testGallerySearchFindsBitmapExamples() async {
        for query in ["bitmap", "image tile", "cap insets", "aspect fit", "resizable resource"] {
            XCTAssertTrue(DemoGalleryCategory.visuals.matches(query: query), query)
        }
        XCTAssertFalse(DemoGalleryCategory.controls.matches(query: "bitmap"))
    }

    func testExplicitCopiedBundleResolvesBothNamedImages() async throws {
        let original = DemoBitmapResources.bundle
        let temporaryParent = FileManager.default.temporaryDirectory.standardizedFileURL
        let temporary = temporaryParent.appendingPathComponent("demo-bitmap-copy-\(Foundation.UUID().uuidString)")
            .standardizedFileURL
        guard temporary.deletingLastPathComponent() == temporaryParent else {
            return XCTFail("The copied bundle fixture must stay inside its owned temporary directory")
        }
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let copiedURL = temporary.appendingPathComponent(original.bundleURL.lastPathComponent)
        try FileManager.default.copyItem(at: original.bundleURL, to: copiedURL)
        let copied = try XCTUnwrap(Bundle(url: copiedURL))
        XCTAssertEqual(copied.bundleURL.standardizedFileURL, copiedURL.standardizedFileURL)
        for name in names {
            let url = try XCTUnwrap(copied.url(forResource: name, withExtension: "png"))
            XCTAssertTrue(url.standardizedFileURL.path.hasPrefix(copiedURL.standardizedFileURL.path + "/"))
            let source = try bitmap(named: name, bundle: original)
            let relocated = try bitmap(named: name, bundle: copied)
            XCTAssertEqual(relocated, source)
        }
        // This checks explicit Bundle lookup after copying. It is not a
        // relocated executable test and cannot qualify generated-accessor
        // lookup, Swift DLL deployment, or missing-bundle failure behavior.
    }
}
