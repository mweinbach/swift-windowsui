import Foundation
import SwiftWindowsCore
import XCTest

@testable import SwiftWindowsGraphics
@testable import SwiftWindowsRendererD3D11

/// An image's affine matrix moves its geometry around the destination
/// center; texture coordinates stay in the original local rectangle.
@MainActor
final class AffineImagePlacementTests: XCTestCase {
    private static let textureID: Int32 = 62_301
    private static let surfaceSize = IntSize(width: 40, height: 40)

    func testIdentityAffinePreservesTheOriginalImagePixels() async throws {
        XCTAssertEqual(MemoryLayout<ImagePrimitive>.stride, 80)
        let original = image()
        XCTAssertEqual(original.affineA, 1)
        XCTAssertEqual(original.affineB, 0)
        XCTAssertEqual(original.affineC, 0)
        XCTAssertEqual(original.affineD, 1)
        var explicitIdentity = original
        explicitIdentity.affineA = 1
        explicitIdentity.affineB = 0
        explicitIdentity.affineC = 0
        explicitIdentity.affineD = 1

        let originalPixels = try assertParity(makeScene(containing: original))
        let explicitPixels = try assertParity(makeScene(containing: explicitIdentity))
        XCTAssertEqual(originalPixels.pixels, explicitPixels.pixels)

        // A texel-aligned identity draw must copy the fixture byte for byte,
        // including the rest of the opaque black target.
        let source = asymmetricBitmap()
        let width = Int(Self.surfaceSize.width)
        let height = Int(Self.surfaceSize.height)
        var expected = [UInt8](repeating: 0, count: width * height * 4)
        for offset in stride(from: 3, to: expected.count, by: 4) {
            expected[offset] = 255
        }
        for y in 0..<8 {
            for x in 0..<8 {
                for channel in 0..<4 {
                    expected[((y + 16) * width + x + 16) * 4 + channel] = source.pixels[(y * 8 + x) * 4 + channel]
                }
            }
        }
        XCTAssertEqual(originalPixels.pixels, Data(expected))
    }

    func testShearPreservesLocalUVsAndDoesNotFillItsBoundingBox() async throws {
        var primitive = image()
        primitive.affineC = 0.75
        let scene = makeScene(containing: primitive)
        XCTAssertEqual(scene.paintedBounds, Rect(x: 13, y: 16, width: 14, height: 8))
        let pixels = try assertParity(scene)

        assertPixel(pixels, x: 16, y: 18, red: 255, green: 0, blue: 0)
        assertPixel(pixels, x: 20, y: 18, red: 0, green: 255, blue: 0)
        assertPixel(pixels, x: 20, y: 22, red: 0, green: 0, blue: 255)
        assertPixel(pixels, x: 24, y: 22, red: 255, green: 255, blue: 0)
        // The first two samples are inside the AABB but outside the actual
        // parallelogram; the others are outside the transformed AABB itself.
        for (x, y) in [(13, 23), (26, 16), (12, 20), (27, 20), (20, 15), (20, 24)] {
            assertPixel(pixels, x: x, y: y, red: 0, green: 0, blue: 0)
        }
    }

    func testNonuniformScaleRunsBeforeRotation() async throws {
        var primitive = image()
        primitive.affineA = 2
        primitive.affineD = 0.5
        primitive.rotationRadians = .pi / 6
        let scene = makeScene(containing: primitive)
        let bounds = try XCTUnwrap(scene.paintedBounds)
        let angle = Double(primitive.rotationRadians)
        let extentX = 8 * cos(angle) + 2 * sin(angle)
        let extentY = 8 * sin(angle) + 2 * cos(angle)
        XCTAssertEqual(bounds.minX, 20 - extentX, accuracy: 0.0001)
        XCTAssertEqual(bounds.minY, 20 - extentY, accuracy: 0.0001)
        XCTAssertEqual(bounds.size.width, extentX * 2, accuracy: 0.0001)
        XCTAssertEqual(bounds.size.height, extentY * 2, accuracy: 0.0001)

        let pixels = try assertParity(scene)
        assertPixel(pixels, x: 17, y: 17, red: 255, green: 0, blue: 0)
        assertPixel(pixels, x: 23, y: 21, red: 0, green: 255, blue: 0)
        assertPixel(pixels, x: 16, y: 18, red: 0, green: 0, blue: 255)
        assertPixel(pixels, x: 23, y: 23, red: 255, green: 255, blue: 0)
        assertPixel(pixels, x: 11, y: 20, red: 0, green: 0, blue: 0)
        assertPixel(pixels, x: 28, y: 20, red: 0, green: 0, blue: 0)
    }

    func testSubpixelLocalRectKeepsItsFullUVExtentWhenScaledUp() async throws {
        let originalPixels = try assertParity(makeScene(containing: image()))
        var primitive = image()
        primitive.screenX = 19.75
        primitive.screenY = 19.625
        primitive.screenW = 0.5
        primitive.screenH = 0.75
        primitive.affineA = 16
        primitive.affineD = Float(32) / 3
        let expandedPixels = try assertParity(makeScene(containing: primitive))
        XCTAssertEqual(
            comparePixels(expandedPixels, originalPixels, tolerance: 1).matchRatio, 1,
            "A local rectangle below one pixel must still map the whole source texture onto its expanded footprint")
    }

    func testHorizontalAndVerticalReflectionsPreserveTextureOrientation() async throws {
        var horizontal = image()
        horizontal.affineA = -1
        let horizontalScene = makeScene(containing: horizontal)
        XCTAssertEqual(horizontalScene.paintedBounds, Rect(x: 16, y: 16, width: 8, height: 8))
        let horizontalPixels = try assertParity(horizontalScene)
        assertPixel(horizontalPixels, x: 17, y: 17, red: 0, green: 255, blue: 0)
        assertPixel(horizontalPixels, x: 22, y: 17, red: 255, green: 0, blue: 0)
        assertPixel(horizontalPixels, x: 17, y: 22, red: 255, green: 255, blue: 0)
        assertPixel(horizontalPixels, x: 22, y: 22, red: 0, green: 0, blue: 255)

        var vertical = image()
        vertical.affineD = -1
        let verticalScene = makeScene(containing: vertical)
        XCTAssertEqual(verticalScene.paintedBounds, Rect(x: 16, y: 16, width: 8, height: 8))
        let verticalPixels = try assertParity(verticalScene)
        assertPixel(verticalPixels, x: 17, y: 17, red: 0, green: 0, blue: 255)
        assertPixel(verticalPixels, x: 22, y: 17, red: 255, green: 255, blue: 0)
        assertPixel(verticalPixels, x: 17, y: 22, red: 255, green: 0, blue: 0)
        assertPixel(verticalPixels, x: 22, y: 22, red: 0, green: 255, blue: 0)
    }

    func testReflectionsKeepPhysicalTopAndLeftPixelEdgesInclusive() async throws {
        let source = BitmapSurface(width: 1, height: 1, bytesPerRow: 4, pixels: Data([0, 0, 255, 255]))
        let reflections: [(name: String, a: Float, d: Float)] = [
            ("horizontal", -1, 1),
            ("vertical", 1, -1),
            ("both axes", -1, -1),
        ]
        for reflection in reflections {
            var primitive = image()
            primitive.screenX = 10.5
            primitive.screenY = 11.5
            primitive.affineA = reflection.a
            primitive.affineD = reflection.d
            var scene = GPUIScene(clearColor: .black)
            scene.bindImageResource(source, for: Self.textureID)
            scene.addImage(primitive)
            scene.finish()
            XCTAssertEqual(scene.paintedBounds, Rect(x: 10.5, y: 11.5, width: 8, height: 8))

            let gpu = try assertParity(scene)
            let cpu = GPUIRawSceneRasterizer.rasterize(scene, size: Self.surfaceSize).premultipliedAlpha()
            XCTAssertEqual(gpu.pixels, cpu.pixels, "Exact boundary coverage for \(reflection.name) reflection")
            // These edges pass through pixel centers. Reflection must not
            // exchange the physical top/left and bottom/right fill rules.
            for pixels in [cpu, gpu] {
                assertPixel(pixels, x: 10, y: 11, red: 255, green: 0, blue: 0)
                assertPixel(pixels, x: 10, y: 15, red: 255, green: 0, blue: 0)
                assertPixel(pixels, x: 14, y: 11, red: 255, green: 0, blue: 0)
                assertPixel(pixels, x: 17, y: 18, red: 255, green: 0, blue: 0)
                assertPixel(pixels, x: 18, y: 15, red: 0, green: 0, blue: 0)
                assertPixel(pixels, x: 14, y: 19, red: 0, green: 0, blue: 0)
                assertPixel(pixels, x: 18, y: 19, red: 0, green: 0, blue: 0)
            }
        }
    }

    func testWorldClipAndSceneTranslationFollowTheAffineFootprint() async throws {
        var primitive = image()
        primitive.affineC = 0.75
        primitive.clipX = 18
        primitive.clipY = 18
        primitive.clipWidth = 6
        primitive.clipHeight = 5
        let scene = makeScene(containing: primitive)
        XCTAssertEqual(scene.paintedBounds, Rect(x: 18, y: 18, width: 6, height: 5))
        let pixels = try assertParity(scene)
        assertPixel(pixels, x: 20, y: 18, red: 0, green: 255, blue: 0)
        assertPixel(pixels, x: 20, y: 22, red: 0, green: 0, blue: 255)
        for (x, y) in [(17, 19), (20, 17), (24, 22), (20, 23)] {
            assertPixel(pixels, x: x, y: y, red: 0, green: 0, blue: 0)
        }

        let translated = scene.translatedPrimitives(by: Point(x: 5, y: -7))
        XCTAssertEqual(translated.paintedBounds, Rect(x: 23, y: 11, width: 6, height: 5))
        let moved = try XCTUnwrap(translated.layers.first?.images.first)
        XCTAssertEqual(moved.affineA, primitive.affineA)
        XCTAssertEqual(moved.affineB, primitive.affineB)
        XCTAssertEqual(moved.affineC, primitive.affineC)
        XCTAssertEqual(moved.affineD, primitive.affineD)
        let translatedPixels = try assertParity(translated)
        assertPixel(translatedPixels, x: 25, y: 11, red: 0, green: 255, blue: 0)
        assertPixel(translatedPixels, x: 25, y: 15, red: 0, green: 0, blue: 255)
        assertPixel(translatedPixels, x: 22, y: 12, red: 0, green: 0, blue: 0)
    }

    func testAffineRenderPassChargesSourcePixelsInsteadOfDestinationArea() async throws {
        let sourceSize = IntSize(width: 8, height: 8)
        var source = GPUIScene(clearColor: .clear)
        source.addQuad(quad(Color(red: 1, green: 0, blue: 0, alpha: 1), x: 0, y: 0))
        source.addQuad(quad(Color(red: 0, green: 1, blue: 0, alpha: 1), x: 4, y: 0))
        source.addQuad(quad(Color(red: 0, green: 0, blue: 1, alpha: 1), x: 0, y: 4))
        source.addQuad(quad(Color(red: 1, green: 1, blue: 0, alpha: 1), x: 4, y: 4))
        source.finish()

        var scene = GPUIScene(clearColor: .black)
        let textureID = scene.registerImageRenderPass(source, size: sourceSize, colorEffects: [.brightness(0.1)])
        var primitive = image()
        primitive.textureID = textureID
        primitive.affineA = 2
        primitive.affineC = 0.5
        primitive.affineD = 3
        scene.addImage(primitive)
        scene.finish()
        XCTAssertEqual(scene.paintedBounds, Rect(x: 10, y: 8, width: 20, height: 24))
        XCTAssertTrue(scene.validate().isEmpty)
        XCTAssertTrue(scene.imageResources.isEmpty)
        XCTAssertEqual(scene.imageRenderPasses.count, 1)
        XCTAssertEqual(scene.imageRenderPasses.first?.size, sourceSize)

        // There are 480 pixels in the destination AABB, but the pass still
        // owns only its original 64 source pixels and one filter chain.
        let budget = GPUISceneImageRenderPassBudget(maxPasses: 1, maxPixels: 64)
        let pixels = try assertParity(scene, budget: budget)
        assertPixel(pixels, x: 15, y: 13, red: 255, green: 26, blue: 26)
        assertPixel(pixels, x: 23, y: 13, red: 26, green: 255, blue: 26)
        assertPixel(pixels, x: 17, y: 25, red: 26, green: 26, blue: 255)
        assertPixel(pixels, x: 25, y: 25, red: 255, green: 255, blue: 26)
        let translated = scene.translatedPrimitives(by: Point(x: 1, y: 2))
        XCTAssertEqual(translated.imageRenderPasses, scene.imageRenderPasses)
        _ = try assertParity(translated, budget: budget)
    }

    func testMalformedMatricesAreRejectedAndCannotPaintThroughAHandBuiltLayer() async throws {
        let invalidMatrices: [(name: String, a: Float, b: Float, c: Float, d: Float)] = [
            ("nonfinite a", .nan, 0, 0, 1),
            ("nonfinite b", 1, .infinity, 0, 1),
            ("nonfinite c", 1, 0, -.infinity, 1),
            ("nonfinite d", 1, 0, 0, .nan),
            ("singular nonzero", 1, 2, 2, 4),
            ("singular zero", 0, 0, 0, 0),
            ("finite overlarge footprint", 1e20, 0, 0, 1),
        ]
        let empty = GPUIRawSceneRasterizer.rasterize(GPUIScene(clearColor: .black), size: Self.surfaceSize)
        for matrix in invalidMatrices {
            var primitive = image()
            primitive.affineA = matrix.a
            primitive.affineB = matrix.b
            primitive.affineC = matrix.c
            primitive.affineD = matrix.d
            let sanitized = makeScene(containing: primitive)
            XCTAssertTrue(sanitized.layers[0].images.isEmpty, matrix.name)
            XCTAssertTrue(sanitized.paintRecords.isEmpty, matrix.name)
            XCTAssertNil(sanitized.paintedBounds, matrix.name)
            XCTAssertTrue(sanitized.validate().isEmpty, matrix.name)

            var handBuilt = GPUIScene(clearColor: .black)
            handBuilt.bindImageResource(asymmetricBitmap(), for: Self.textureID)
            handBuilt.installHandBuiltLayer(
                GPUILayer(
                    images: [primitive],
                    paintOperations: [GPUIPaintOperation(kind: .image, startIndex: 0, count: 1)]),
                at: 0)
            XCTAssertTrue(
                handBuilt.validate().contains { defect in
                    if case .invalidImagePlacement(let layerIndex, let imageIndex, _) = defect.kind {
                        return layerIndex == 0 && imageIndex == 0
                    }
                    return false
                }, matrix.name)
            XCTAssertThrowsError(
                try D3D11BatchRenderer.makeRenderPlan(
                    for: handBuilt,
                    cachedResources: D3D11BatchRenderer.CachedResources(boundImageTextureIDs: [Self.textureID])),
                matrix.name
            ) { error in
                XCTAssertEqual((error as? BatchRendererError)?.operation, "Validate scene", matrix.name)
                XCTAssertEqual((error as? BatchRendererError)?.presentationFailureKind, .sceneContent, matrix.name)
            }
            let pixels = GPUIRawSceneRasterizer.rasterize(handBuilt, size: Self.surfaceSize)
            XCTAssertEqual(pixels.pixels, empty.pixels, matrix.name)
        }
    }

    func testNonfiniteRotationIsSanitizedAtAdmissionAndRejectedWhenHandBuilt() async throws {
        var validPrimitive = image()
        validPrimitive.affineC = 0.5
        let expected = GPUIRawSceneRasterizer.rasterize(
            makeScene(containing: validPrimitive), size: Self.surfaceSize)
        let empty = GPUIRawSceneRasterizer.rasterize(GPUIScene(clearColor: .black), size: Self.surfaceSize)
        let invalidAngles: [(name: String, value: Float)] = [
            ("NaN", .nan),
            ("positive infinity", .infinity),
            ("negative infinity", -.infinity),
        ]
        for angle in invalidAngles {
            var primitive = validPrimitive
            primitive.rotationRadians = angle.value
            let authored = makeScene(containing: primitive)
            let admitted = try XCTUnwrap(authored.layers[0].images.first, angle.name)
            XCTAssertEqual(admitted.rotationRadians, 0, angle.name)
            XCTAssertEqual(admitted.affineC, 0.5, angle.name)
            XCTAssertTrue(authored.validate().isEmpty, angle.name)
            XCTAssertEqual(authored.paintedBounds, Rect(x: 14, y: 16, width: 12, height: 8), angle.name)
            XCTAssertEqual(
                GPUIRawSceneRasterizer.rasterize(authored, size: Self.surfaceSize).pixels,
                expected.pixels, angle.name)

            var handBuilt = GPUIScene(clearColor: .black)
            handBuilt.bindImageResource(asymmetricBitmap(), for: Self.textureID)
            handBuilt.installHandBuiltLayer(
                GPUILayer(
                    images: [primitive],
                    paintOperations: [GPUIPaintOperation(kind: .image, startIndex: 0, count: 1)]),
                at: 0)
            XCTAssertTrue(
                handBuilt.validate().contains { defect in
                    if case .invalidImagePlacement(let layerIndex, let imageIndex, _) = defect.kind {
                        return layerIndex == 0 && imageIndex == 0
                    }
                    return false
                }, angle.name)
            XCTAssertThrowsError(
                try D3D11BatchRenderer.makeRenderPlan(
                    for: handBuilt,
                    cachedResources: D3D11BatchRenderer.CachedResources(boundImageTextureIDs: [Self.textureID])),
                angle.name
            ) { error in
                XCTAssertEqual((error as? BatchRendererError)?.operation, "Validate scene", angle.name)
                XCTAssertEqual((error as? BatchRendererError)?.presentationFailureKind, .sceneContent, angle.name)
            }
            XCTAssertEqual(
                GPUIRawSceneRasterizer.rasterize(handBuilt, size: Self.surfaceSize).pixels,
                empty.pixels, angle.name)
        }
    }

    private func assertParity(
        _ scene: GPUIScene, budget: GPUISceneImageRenderPassBudget? = nil,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> BitmapSurface {
        let renderer = try WARPBatchRenderer.shared(size: Self.surfaceSize)
        let previousBudget = renderer.imageRenderPassExecutionBudgetOverrideForTesting
        defer { renderer.imageRenderPassExecutionBudgetOverrideForTesting = previousBudget }
        renderer.imageRenderPassExecutionBudgetOverrideForTesting = budget
        renderer.bindResources(for: scene)
        try renderer.render(scene: scene)
        let actual = try renderer.readOffscreenPixels()
        let expected = GPUIRawSceneRasterizer.rasterize(
            scene, size: Self.surfaceSize,
            imageRenderPassBudget: budget ?? GPUISceneImageRenderPassBudget()
        ).premultipliedAlpha()
        XCTAssertEqual(actual.width, expected.width, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, file: file, line: line)
        let report = comparePixels(actual, expected, tolerance: 4)
        XCTAssertGreaterThanOrEqual(
            report.matchRatio, 0.995,
            "Affine CPU/WARP mismatch: max delta \(report.maxChannelDelta), first \(String(describing: report.firstFailure))",
            file: file, line: line)
        return actual
    }

    private func assertPixel(
        _ bitmap: BitmapSurface, x: Int, y: Int, red: Int, green: Int, blue: Int,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let offset = y * Int(bitmap.bytesPerRow) + x * 4
        XCTAssertEqual(Double(bitmap.pixels[offset]), Double(blue), accuracy: 3, file: file, line: line)
        XCTAssertEqual(Double(bitmap.pixels[offset + 1]), Double(green), accuracy: 3, file: file, line: line)
        XCTAssertEqual(Double(bitmap.pixels[offset + 2]), Double(red), accuracy: 3, file: file, line: line)
        XCTAssertEqual(bitmap.pixels[offset + 3], 255, file: file, line: line)
    }

    private func image() -> ImagePrimitive {
        ImagePrimitive(screenX: 16, screenY: 16, screenW: 8, screenH: 8, textureID: Self.textureID)
    }

    private func makeScene(containing primitive: ImagePrimitive) -> GPUIScene {
        var scene = GPUIScene(clearColor: .black)
        scene.bindImageResource(asymmetricBitmap(), for: Self.textureID)
        scene.addImage(primitive)
        scene.finish()
        return scene
    }

    private func quad(_ color: Color, x: Float, y: Float) -> QuadPrimitive {
        QuadPrimitive(
            x: x, y: y, width: 4, height: 4,
            startR: color.red, startG: color.green, startB: color.blue, startA: color.alpha,
            endR: color.red, endG: color.green, endB: color.blue, endA: color.alpha)
    }

    private func asymmetricBitmap() -> BitmapSurface {
        var pixels = [UInt8]()
        for y in 0..<8 {
            for x in 0..<8 {
                switch (x < 4, y < 4) {
                case (true, true): pixels.append(contentsOf: [0, 0, 255, 255])
                case (false, true): pixels.append(contentsOf: [0, 255, 0, 255])
                case (true, false): pixels.append(contentsOf: [255, 0, 0, 255])
                case (false, false): pixels.append(contentsOf: [0, 255, 255, 255])
                }
            }
        }
        return BitmapSurface(width: 8, height: 8, bytesPerRow: 32, pixels: Data(pixels))
    }
}
