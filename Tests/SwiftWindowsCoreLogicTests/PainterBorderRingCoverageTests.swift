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

    func testContainerRingRasterizesIdenticallyToTheLeafRing() async {
        // Square corners: the ring is four axis-aligned edge rects that cover
        // exactly the pixels the leaf's full-rect fill leaves outside its inset
        // background, so the two are comparable byte for byte. (A rounded ring
        // walks arc segments instead, which is its own approximation.)
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

        XCTAssertEqual(
            rasterize(container).pixels, rasterize(leaf).pixels,
            "one border modifier, one ring: a container's ring must land exactly where the leaf's "
                + "full-rect fill leaves border colour visible")
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
