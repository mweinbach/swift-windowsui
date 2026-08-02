import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI

/// A bordered container paints its border exactly once, as a ring, and leaves
/// the interior to the background.
///
/// A container used to emit a full-rect fill in the border colour *before* its
/// children and the ring again after, which blended a translucent border twice
/// (`.border(Color.white.opacity(0.10))` composited at 0.19 on a container and
/// 0.10 on a leaf). Dropping the pre-children fill also drops something else
/// that fill was doing: tinting the whole interior in the border colour under a
/// transparent or translucent background. These tests pin both halves in
/// pixels — the ring, and the interior the ring must not touch — for a
/// container with no background and one with a translucent background, and pin
/// that the ring lands exactly where the leaf case puts it.
@MainActor
final class PainterBorderRingCoverageTests: XCTestCase {

    private let size = Size(width: 40, height: 40)
    private let pixelSize = IntSize(width: 40, height: 40)
    private let white = Color(red: 1, green: 1, blue: 1, alpha: 1)

    private func rasterize(_ root: ViewNode) -> BitmapSurface {
        GPUIRawSceneRasterizer.rasterize(
            ScenePainter.paint(root: root, clearColor: .black, surfaceSize: size),
            size: pixelSize
        )
    }

    private func pixel(_ bitmap: BitmapSurface, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let bytes = [UInt8](bitmap.pixels)
        let offset = y * Int(bitmap.bytesPerRow) + x * 4
        return (bytes[offset + 2], bytes[offset + 1], bytes[offset], bytes[offset + 3])
    }

    func testBorderedContainerWithNoBackgroundLeavesItsInteriorUntouched() async {
        let container = ViewNode(
            frame: Rect(x: 0, y: 0, width: 40, height: 40),
            borderColor: white,
            borderWidth: 2,
            children: [ViewNode(frame: Rect(x: 4, y: 4, width: 32, height: 32))]
        )

        let bitmap = rasterize(container)

        let ring = pixel(bitmap, x: 20, y: 1)
        XCTAssertEqual(ring.r, 255, "the ring itself is opaque border colour")
        XCTAssertEqual(ring.g, 255)
        XCTAssertEqual(ring.b, 255)

        let interior = pixel(bitmap, x: 20, y: 20)
        XCTAssertEqual(
            interior.r, 0,
            "a container with a border and no background used to have its whole interior filled "
                + "with the border colour under the children")
        XCTAssertEqual(interior.g, 0)
        XCTAssertEqual(interior.b, 0)
    }

    func testBorderedContainerWithTranslucentBackgroundKeepsBorderColourOutOfTheInterior() async {
        let container = ViewNode(
            frame: Rect(x: 0, y: 0, width: 40, height: 40),
            backgroundColor: Color(red: 0, green: 0, blue: 1, alpha: 0.5),
            borderColor: white,
            borderWidth: 2,
            children: [ViewNode(frame: Rect(x: 4, y: 4, width: 32, height: 32))]
        )

        let bitmap = rasterize(container)

        let interior = pixel(bitmap, x: 20, y: 20)
        XCTAssertTrue(
            abs(Int(interior.b) - 128) <= 2,
            "the interior is the translucent background over the clear colour and nothing else, "
                + "got \(interior.b)")
        XCTAssertEqual(
            interior.r, 0,
            "a translucent background does not hide the pre-children fill, so any border colour "
                + "underneath it shows through as a tint")
        XCTAssertEqual(interior.g, 0)

        let ring = pixel(bitmap, x: 20, y: 1)
        XCTAssertEqual(ring.r, 255, "and the ring is still fully painted")
        XCTAssertEqual(ring.g, 255)
        XCTAssertEqual(ring.b, 255)
    }

    /// Square corners: the ring is four axis-aligned edge rects that cover
    /// exactly the pixels the leaf's full-rect fill leaves outside its inset
    /// background, so the two are comparable pixel for pixel. (A rounded ring
    /// walks arc segments instead, which is its own approximation.)
    ///
    /// One class of pixel is exempt, and it is a real difference rather than
    /// noise. The quad shader's `aa` is `fwidth(distance)`, which doubles to 2
    /// on the pixel where *both* axes of the box SDF move across the
    /// derivative quad — the far corner of any square rect — so that corner
    /// pixel is 75 % covered instead of 100 %. The leaf's border fill sits
    /// *under* its inset background, so the white shows through that 25 %; the
    /// container's ring is under nothing. `CrossBackendPixelParityTests` pins
    /// that both backends produce the 75 %, so this is the shipping corner,
    /// not a rasterizer artefact.
    func testContainerRingRasterizesIdenticallyToTheLeafRing() async {
        let background = Color(red: 0, green: 0.4, blue: 0.8, alpha: 1)
        let leaf = ViewNode(
            frame: Rect(x: 0, y: 0, width: 40, height: 40),
            backgroundColor: background,
            borderColor: white,
            borderWidth: 2
        )
        let container = ViewNode(
            frame: Rect(x: 0, y: 0, width: 40, height: 40),
            backgroundColor: background,
            borderColor: white,
            borderWidth: 2,
            children: [ViewNode(frame: Rect(x: 8, y: 8, width: 24, height: 24))]
        )

        let containerPixels = [UInt8](rasterize(container).pixels)
        let leafPixels = [UInt8](rasterize(leaf).pixels)

        var differing: [(x: Int, y: Int)] = []
        for y in 0..<40 {
            for x in 0..<40 {
                let offset = (y * 40 + x) * 4
                if Array(containerPixels[offset..<(offset + 4)]) != Array(leafPixels[offset..<(offset + 4)]) {
                    differing.append((x, y))
                }
            }
        }

        // The two rects whose far corner is antialiased: the ring's outer
        // rect (39, 39) and the background's inset rect (37, 37).
        let exemptCorners = [(x: 39, y: 39), (x: 37, y: 37)]
        for pixel in differing {
            let isCornerPixel = exemptCorners.contains { corner in
                abs(pixel.x - corner.x) <= 1 && abs(pixel.y - corner.y) <= 1
                    && (pixel.x == corner.x || pixel.y == corner.y)
            }
            XCTAssertTrue(
                isCornerPixel,
                "one border modifier, one ring: a container's ring must land exactly where the leaf's "
                    + "full-rect fill leaves border colour visible, but (\(pixel.x), \(pixel.y)) differs and "
                    + "is not one of the antialiased far-corner pixels")
        }
        XCTAssertLessThanOrEqual(
            differing.count, 6,
            "only the two rects' far-corner pixels may differ, got \(differing.count) differing pixels")
    }

    func testTranslucentContainerRingIsNotBlendedTwice() async {
        let container = ViewNode(
            frame: Rect(x: 0, y: 0, width: 40, height: 40),
            borderColor: Color(red: 1, green: 1, blue: 1, alpha: 0.1),
            borderWidth: 2,
            children: [ViewNode(frame: Rect(x: 4, y: 4, width: 32, height: 32))]
        )
        let leaf = ViewNode(
            frame: Rect(x: 0, y: 0, width: 40, height: 40),
            borderColor: Color(red: 1, green: 1, blue: 1, alpha: 0.1),
            borderWidth: 2
        )

        let containerRing = pixel(rasterize(container), x: 20, y: 1)
        let leafRing = pixel(rasterize(leaf), x: 20, y: 1)

        XCTAssertEqual(
            containerRing.r, leafRing.r,
            "0.10 alpha composited at 0.19 on a container while a leaf got 0.10")
        XCTAssertEqual(containerRing.g, leafRing.g)
        XCTAssertEqual(containerRing.b, leafRing.b)
    }
}
