import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@MainActor
final class ExactImageTexelSamplingTests: XCTestCase {
    private static let textureID: Int32 = 63_404

    func testAlignedHorizontalTexelsDoNotGainTransparentNeighborRGB() async {
        let source = bitmap(width: 100, height: 96, whiteTexels: [(4, 16, 32), (4, 17, 122)])
        let size = IntSize(width: 100, height: 100)
        let output = render(source, image: image(for: source, y: 4), size: size)

        // The normalized round trip for source x=3 is not exactly integral
        // at width 100. Even invisible RGB at alpha zero must stay unchanged.
        XCTAssertEqual(output.pixels, expectedCopy(source, x: 0, y: 4, size: size))
        XCTAssertEqual(pixel(output, x: 3, y: 20), [0, 0, 0, 0])
        XCTAssertEqual(pixel(output, x: 3, y: 21), [0, 0, 0, 0])
    }

    func testAlignedVerticalTexelsDoNotGainTransparentNeighborRGB() async {
        let source = bitmap(width: 96, height: 100, whiteTexels: [(16, 4, 32), (17, 4, 122)])
        let size = IntSize(width: 100, height: 100)
        let output = render(source, image: image(for: source, x: 4), size: size)

        XCTAssertEqual(output.pixels, expectedCopy(source, x: 4, y: 0, size: size))
        XCTAssertEqual(pixel(output, x: 20, y: 3), [0, 0, 0, 0])
        XCTAssertEqual(pixel(output, x: 21, y: 3), [0, 0, 0, 0])
    }

    func testNegativeIntegralPlacementCopiesOnlyVisibleSourceTexels() async {
        let source = bitmap(
            width: 100, height: 96,
            whiteTexels: [(0, 0, 255), (4, 16, 32), (4, 17, 122), (22, 15, 255)])
        let size = IntSize(width: 20, height: 20)
        let output = render(source, image: image(for: source, x: -2, y: -10), size: size)

        XCTAssertEqual(output.pixels, expectedCopy(source, x: -2, y: -10, size: size))
        XCTAssertEqual(pixel(output, x: 1, y: 6), [0, 0, 0, 0])
        XCTAssertEqual(pixel(output, x: 2, y: 6), [255, 255, 255, 32])
        XCTAssertEqual(pixel(output, x: 2, y: 7), [255, 255, 255, 122])
    }

    func testIntegralPlacementPreservesWorldClipAndOpacity() async {
        let source = bitmap(width: 100, height: 96, whiteTexels: [(4, 16, 32), (4, 17, 122)])
        var primitive = image(for: source, y: 4)
        primitive.clipX = 4
        primitive.clipY = 20
        primitive.clipWidth = 1
        primitive.clipHeight = 1
        primitive.opacity = 0.5
        let output = render(source, image: primitive, size: IntSize(width: 100, height: 100))
        let expected = bitmap(width: 100, height: 100, whiteTexels: [(4, 20, 16)])

        XCTAssertEqual(output.pixels, expected.pixels)
    }

    func testAlignedPremultipliedAndStraightWhiteTexelsMatch() async {
        let source = bitmap(width: 100, height: 96, whiteTexels: [(4, 16, 32), (4, 17, 122)])
        let size = IntSize(width: 100, height: 100)
        let primitive = image(for: source, y: 4)
        let straight = render(source, image: primitive, size: size)
        let premultiplied = render(source.premultipliedAlpha(), image: primitive, size: size)
        let expected = expectedCopy(source, x: 0, y: 4, size: size)

        XCTAssertEqual(straight.pixels, expected)
        XCTAssertEqual(premultiplied.pixels, expected)
        XCTAssertEqual(straight.format.alphaMode, .straight)
        XCTAssertEqual(premultiplied.format.alphaMode, .straight)
    }

    func testFractionalOriginsRetainLinearFiltering() async {
        let source = bitmap(width: 100, height: 1, whiteTexels: [(4, 0, 255)])
        let output = render(source, image: image(for: source, x: 0.25), size: IntSize(width: 101, height: 1))
        let expected = bitmap(width: 101, height: 1, whiteTexels: [(4, 0, 191), (5, 0, 64)])

        XCTAssertEqual(output.pixels, expected.pixels)
    }

    func testScaledDestinationsRetainLinearFiltering() async {
        let source = bitmap(width: 100, height: 1, whiteTexels: [(4, 0, 255)])
        var primitive = image(for: source)
        primitive.screenW = 200
        let output = render(source, image: primitive, size: IntSize(width: 200, height: 1))
        let expected = bitmap(
            width: 200, height: 1, whiteTexels: [(7, 0, 64), (8, 0, 191), (9, 0, 191), (10, 0, 64)])

        XCTAssertEqual(output.pixels, expected.pixels)
    }

    func testPartialUVsRetainLinearFiltering() async {
        let source = bitmap(width: 100, height: 1, whiteTexels: [(25, 0, 255)])
        var primitive = image(for: source)
        primitive.uvX = 0.25
        primitive.uvW = 0.5
        let output = render(source, image: primitive, size: IntSize(width: 100, height: 1))
        let expected = bitmap(width: 100, height: 1, whiteTexels: [(0, 0, 191), (1, 0, 191), (2, 0, 64)])

        XCTAssertEqual(output.pixels, expected.pixels)
    }

    func testAffineScalingRetainsLocalTextureFiltering() async {
        let source = bitmap(width: 100, height: 1, whiteTexels: [(4, 0, 255)])
        var primitive = image(for: source, x: 50)
        primitive.affineA = 2
        let output = render(source, image: primitive, size: IntSize(width: 200, height: 1))
        let expected = bitmap(
            width: 200, height: 1, whiteTexels: [(7, 0, 64), (8, 0, 191), (9, 0, 191), (10, 0, 64)])

        XCTAssertEqual(output.pixels, expected.pixels)
    }

    func testQuarterTurnKeepsTheRotatedSourceLocation() async {
        var texels: [(Int, Int, UInt8)] = []
        for y in 0..<8 {
            for x in 0..<8 { texels.append((x, y, 255)) }
        }
        let source = bitmap(width: 100, height: 100, whiteTexels: texels)
        var primitive = image(for: source)
        primitive.rotationRadians = .pi / 2
        let output = render(source, image: primitive, size: IntSize(width: 100, height: 100))

        XCTAssertEqual(pixel(output, x: 96, y: 4), [255, 255, 255, 255])
        XCTAssertEqual(pixel(output, x: 4, y: 4), [0, 0, 0, 0])
    }

    func testTileDescriptorKeepsItsRepeatedSourceMapping() async {
        let source = bitmap(width: 100, height: 1, whiteTexels: (0..<50).map { ($0, 0, 255) })
        var primitive = image(for: source)
        primitive.sampling = ImageSamplingDescriptor(centerRepeatX: 2, samplingKind: 2)
        let output = render(source, image: primitive, size: IntSize(width: 100, height: 1))
        let expected = bitmap(
            width: 100, height: 1,
            whiteTexels: (0..<100).filter { $0 < 25 || (50..<75).contains($0) }.map { ($0, 0, 255) })

        XCTAssertEqual(output.pixels, expected.pixels)
    }

    private func bitmap(width: Int, height: Int, whiteTexels: [(x: Int, y: Int, alpha: UInt8)]) -> BitmapSurface {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for texel in whiteTexels {
            let offset = (texel.y * width + texel.x) * 4
            pixels[offset] = 255
            pixels[offset + 1] = 255
            pixels[offset + 2] = 255
            pixels[offset + 3] = texel.alpha
        }
        return BitmapSurface(
            width: Int32(width), height: Int32(height), bytesPerRow: Int32(width * 4),
            pixels: Data(pixels), format: .bgra8Straight)
    }

    private func image(for source: BitmapSurface, x: Float = 0, y: Float = 0) -> ImagePrimitive {
        ImagePrimitive(
            screenX: x, screenY: y, screenW: Float(source.width), screenH: Float(source.height),
            textureID: Self.textureID)
    }

    private func render(_ source: BitmapSurface, image: ImagePrimitive, size: IntSize) -> BitmapSurface {
        var scene = GPUIScene(clearColor: .clear)
        scene.bindImageResource(source, for: Self.textureID)
        scene.addImage(image)
        return GPUIRawSceneRasterizer.rasterize(scene, size: size)
    }

    private func expectedCopy(_ source: BitmapSurface, x: Int, y: Int, size: IntSize) -> Data {
        let width = Int(size.width)
        let height = Int(size.height)
        var expected = [UInt8](repeating: 0, count: width * height * 4)
        for sourceY in 0..<Int(source.height) {
            for sourceX in 0..<Int(source.width) {
                let targetX = x + sourceX
                let targetY = y + sourceY
                guard targetX >= 0, targetX < width, targetY >= 0, targetY < height else { continue }
                let sourceOffset = sourceY * Int(source.bytesPerRow) + sourceX * 4
                let targetOffset = (targetY * width + targetX) * 4
                for channel in 0..<4 { expected[targetOffset + channel] = source.pixels[sourceOffset + channel] }
            }
        }
        return Data(expected)
    }

    private func pixel(_ bitmap: BitmapSurface, x: Int, y: Int) -> [UInt8] {
        let offset = y * Int(bitmap.bytesPerRow) + x * 4
        return Array(bitmap.pixels[offset..<(offset + 4)])
    }
}
