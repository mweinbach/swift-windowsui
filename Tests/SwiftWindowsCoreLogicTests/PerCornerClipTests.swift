import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI

/// Locks per-corner clip handling in ScenePainter end to end:
///   - a node's OWN quads are shaped by their own corner radii and are not
///     re-rounded by their own clip (SwiftUI semantics: the clip applies to
///     children, not to the view's own decoration),
///   - children resolve the exact uniform clip radius for the clip corners
///     they actually reach, so square corners of a mixed-radii parent stay
///     square in clipped output,
///   - the border overlay emits no arc geometry at square corners.

@MainActor
private func paintedQuads(
    root: ViewNode,
    clearColor: Color = .white,
    surfaceSize: Size = Size(width: 300, height: 120)
) -> [QuadPrimitive] {
    ScenePainter.paint(root: root, clearColor: clearColor, surfaceSize: surfaceSize).layers[0].quads
}

private func pixel(_ bitmap: BitmapSurface, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
    let offset = (y * Int(bitmap.bytesPerRow)) + x * 4
    // BGRA
    return (
        r: bitmap.pixels[offset + 2], g: bitmap.pixels[offset + 1],
        b: bitmap.pixels[offset], a: bitmap.pixels[offset + 3]
    )
}
final class PerCornerClipTests: XCTestCase {

    // MARK: - Self-clip

    func testOwnBackgroundIsNotReRoundedByOwnPerCornerClip() async {
        await MainActor.run {
            let node = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 40),
                backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1),
                cornerRadii: RetainedCornerRadii(topLeft: 12, topRight: 12),
                clipsToBounds: true
            )

            let quads = paintedQuads(root: node)
            XCTAssertEqual(quads.count, 1)
            XCTAssertEqual(
                quads[0].clipCornerRadius, 0, accuracy: 0.001,
                "a node's own clip must not re-round its own background quad")
            XCTAssertTrue(quads[0].usesPerCornerRadii)
            XCTAssertEqual(quads[0].cornerRadiusTopLeft, 12, accuracy: 0.001)
            XCTAssertEqual(quads[0].cornerRadiusTopRight, 12, accuracy: 0.001)
            XCTAssertEqual(quads[0].cornerRadiusBottomLeft, 0, accuracy: 0.001)
        }
    }

    func testUniformSelfClipRasterizesIdenticallyToUnclipped() async {
        await MainActor.run {
            // For a uniform corner radius the self-clip duplicated the quad's
            // own rounding; removing it must leave the rendered output
            // byte-identical.
            let clipped = ViewNode(
                frame: Rect(x: 10, y: 10, width: 80, height: 40),
                backgroundColor: Color(red: 0, green: 0, blue: 1, alpha: 1),
                cornerRadius: 10,
                clipsToBounds: true
            )
            let unclipped = ViewNode(
                frame: Rect(x: 10, y: 10, width: 80, height: 40),
                backgroundColor: Color(red: 0, green: 0, blue: 1, alpha: 1),
                cornerRadius: 10,
                clipsToBounds: false
            )
            let size = IntSize(width: 100, height: 60)
            let clippedPixels = GPUIRawSceneRasterizer.rasterize(
                ScenePainter.paint(root: clipped, clearColor: .white, surfaceSize: Size(width: 100, height: 60)),
                size: size
            ).pixels
            let unclippedPixels = GPUIRawSceneRasterizer.rasterize(
                ScenePainter.paint(root: unclipped, clearColor: .white, surfaceSize: Size(width: 100, height: 60)),
                size: size
            ).pixels
            XCTAssertEqual(clippedPixels, unclippedPixels)
        }
    }

    // MARK: - Per-corner child clip resolution

    func testChildClipRadiusResolvesPerCornerExactly() async {
        await MainActor.run {
            // Parent rounded on the left side only (joined-control shape).
            let parent = ViewNode(
                frame: Rect(x: 0, y: 0, width: 200, height: 40),
                cornerRadii: RetainedCornerRadii(topLeft: 10, bottomLeft: 10),
                clipsToBounds: true
            )
            parent.addChild(
                ViewNode(
                    frame: Rect(x: 0, y: 0, width: 100, height: 40),
                    backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1)
                ))
            parent.addChild(
                ViewNode(
                    frame: Rect(x: 100, y: 0, width: 100, height: 40),
                    backgroundColor: Color(red: 0, green: 1, blue: 0, alpha: 1)
                ))
            parent.addChild(
                ViewNode(
                    frame: Rect(x: 60, y: 12, width: 80, height: 16),
                    backgroundColor: Color(red: 0, green: 0, blue: 1, alpha: 1)
                ))

            let quads = paintedQuads(root: parent)
            XCTAssertEqual(quads.count, 3)
            XCTAssertEqual(
                quads[0].clipCornerRadius, 10, accuracy: 0.001,
                "left child reaches the rounded left corners and keeps that radius")
            XCTAssertEqual(
                quads[1].clipCornerRadius, 0, accuracy: 0.001,
                "right child reaches only square corners and must stay square")
            XCTAssertEqual(
                quads[2].clipCornerRadius, 0, accuracy: 0.001,
                "interior child reaches no clip corner and needs no clip rounding")
        }
    }

    func testUniformClipRadiusStillFlowsToChildren() async {
        await MainActor.run {
            let parent = ViewNode(
                frame: Rect(x: 0, y: 0, width: 200, height: 40),
                cornerRadius: 8,
                clipsToBounds: true
            )
            parent.addChild(
                ViewNode(
                    frame: Rect(x: 0, y: 0, width: 100, height: 40),
                    backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1)
                ))

            let quads = paintedQuads(root: parent)
            XCTAssertEqual(quads.count, 1)
            XCTAssertEqual(quads[0].clipCornerRadius, 8, accuracy: 0.001)
        }
    }

    // MARK: - Rasterized coverage

    func testSquareCornerStaysSquareWhenClippedByMixedRadiiParent() async {
        await MainActor.run {
            // Top-left / bottom-left rounded; the right child fills the
            // parent's square right corners.
            let parent = ViewNode(
                frame: Rect(x: 0, y: 0, width: 200, height: 40),
                cornerRadii: RetainedCornerRadii(topLeft: 12, bottomLeft: 12),
                clipsToBounds: true
            )
            parent.addChild(
                ViewNode(
                    frame: Rect(x: 100, y: 0, width: 100, height: 40),
                    backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1)
                ))
            parent.addChild(
                ViewNode(
                    frame: Rect(x: 0, y: 0, width: 100, height: 40),
                    backgroundColor: Color(red: 0, green: 1, blue: 0, alpha: 1)
                ))

            let scene = ScenePainter.paint(
                root: parent, clearColor: .white, surfaceSize: Size(width: 200, height: 40))
            let bitmap = GPUIRawSceneRasterizer.rasterize(scene, size: IntSize(width: 200, height: 40))

            let topRight = pixel(bitmap, x: 199, y: 2)
            XCTAssertEqual(topRight.r, 255, "square top-right corner must keep the child's red fill")
            XCTAssertEqual(topRight.g, 0)
            XCTAssertEqual(topRight.b, 0)
            let bottomRight = pixel(bitmap, x: 199, y: 37)
            XCTAssertEqual(bottomRight.r, 255, "square bottom-right corner must keep the child's red fill")
            XCTAssertEqual(bottomRight.g, 0)
            XCTAssertEqual(bottomRight.b, 0)

            let roundedTopLeft = pixel(bitmap, x: 1, y: 1)
            XCTAssertEqual(
                roundedTopLeft.r, 255,
                "rounded top-left corner of the parent must still clip the left child")
            XCTAssertEqual(roundedTopLeft.g, 255)
            XCTAssertEqual(roundedTopLeft.b, 255)
        }
    }

    // MARK: - Border overlay geometry

    func testPerCornerSolidBorderSegmentsSkipSquareCorners() async {
        await MainActor.run {
            let frame = Rect(x: 0, y: 0, width: 100, height: 40)
            let segments = BorderSegments.solidSegments(
                frame: frame,
                width: 2,
                cornerRadii: RetainedCornerRadii(topLeft: 8, bottomLeft: 8)
            )

            XCTAssertFalse(segments.isEmpty)
            // Strict corner interiors, excluding the 2px edge strips that
            // legitimately meet at a square corner. Rounded-corner arc
            // boxes would reach into these regions; square corners must
            // have none.
            let topRightZone = Rect(x: 92, y: 2, width: 5, height: 5)
            let bottomRightZone = Rect(x: 92, y: 33, width: 5, height: 5)
            for segment in segments {
                XCTAssertNil(
                    segment.rect.intersected(with: topRightZone),
                    "no overlay arc geometry at the square top-right corner: \(segment)")
                XCTAssertNil(
                    segment.rect.intersected(with: bottomRightZone),
                    "no overlay arc geometry at the square bottom-right corner: \(segment)")
            }
            let topLeftZone = Rect(x: 0, y: 0, width: 8, height: 8)
            XCTAssertTrue(
                segments.contains { $0.rect.intersected(with: topLeftZone) != nil },
                "rounded top-left corner must still get arc segments")
            // The top edge runs from the left corner zone all the way into
            // the square right corner.
            XCTAssertTrue(
                segments.contains {
                    $0.rect.origin.y == frame.minY && $0.rect.maxX == frame.maxX
                        && $0.rect.origin.x == frame.minX + 8
                },
                "top edge spans from the rounded left corner to the square right corner")
        }
    }

    func testPerCornerSolidSegmentsMatchUniformWhenAllRadiiEqual() async {
        await MainActor.run {
            let frame = Rect(x: 3, y: 5, width: 100, height: 40)
            let uniform = BorderSegments.solidSegments(frame: frame, width: 2, cornerRadius: 6)
            let perCorner = BorderSegments.solidSegments(
                frame: frame,
                width: 2,
                cornerRadii: RetainedCornerRadii(uniform: 6)
            )
            let sort: ([BorderSegment]) -> [BorderSegment] = { segments in
                segments.sorted {
                    ($0.rect.origin.x, $0.rect.origin.y, $0.rect.size.width, $0.rect.size.height, $0.cornerRadius)
                        < ($1.rect.origin.x, $1.rect.origin.y, $1.rect.size.width, $1.rect.size.height, $1.cornerRadius)
                }
            }
            let sortedPerCorner = sort(perCorner)
            let sortedUniform = sort(uniform)
            XCTAssertEqual(sortedPerCorner.count, sortedUniform.count)
            for (index, pair) in zip(sortedPerCorner, sortedUniform).enumerated() {
                // The uniform path accumulates lengths along the perimeter,
                // so component-wise equality only holds up to float noise.
                XCTAssertEqual(pair.0.rect.origin.x, pair.1.rect.origin.x, accuracy: 1e-9, "segment \(index)")
                XCTAssertEqual(pair.0.rect.origin.y, pair.1.rect.origin.y, accuracy: 1e-9, "segment \(index)")
                XCTAssertEqual(pair.0.rect.size.width, pair.1.rect.size.width, accuracy: 1e-9, "segment \(index)")
                XCTAssertEqual(pair.0.rect.size.height, pair.1.rect.size.height, accuracy: 1e-9, "segment \(index)")
                XCTAssertEqual(pair.0.cornerRadius, pair.1.cornerRadius, accuracy: 1e-9, "segment \(index)")
            }
        }
    }

    func testBorderOverlayEmitsNoArcAtSquareCornersEndToEnd() async {
        await MainActor.run {
            let node = ViewNode(
                frame: Rect(x: 0, y: 0, width: 100, height: 40),
                borderColor: Color(red: 0, green: 0, blue: 0, alpha: 1),
                borderWidth: 2,
                cornerRadii: RetainedCornerRadii(topLeft: 8, bottomLeft: 8),
                children: [
                    ViewNode(
                        frame: Rect(x: 0, y: 0, width: 100, height: 40),
                        backgroundColor: Color(red: 1, green: 1, blue: 1, alpha: 1)
                    )
                ]
            )

            // Segment quads (smaller than the full frame) drawn after the
            // child must keep arc geometry out of the square corners'
            // strict interiors (the 2px edge strips legitimately meet at
            // square corners).
            let quads = paintedQuads(root: node).filter { $0.width < 100 || $0.height < 40 }
            XCTAssertFalse(quads.isEmpty, "expected border overlay segments")
            let topRightZone = Rect(x: 92, y: 2, width: 5, height: 5)
            let bottomRightZone = Rect(x: 92, y: 33, width: 5, height: 5)
            for quad in quads {
                let rect = Rect(
                    x: Double(quad.x), y: Double(quad.y),
                    width: Double(quad.width), height: Double(quad.height))
                XCTAssertNil(rect.intersected(with: topRightZone), "overlay arc leaked into square corner: \(rect)")
                XCTAssertNil(rect.intersected(with: bottomRightZone), "overlay arc leaked into square corner: \(rect)")
            }
        }
    }

    // MARK: - Visual inspection render

    /// Renders a mixed-radii clipped card to a PNG in the temp directory so
    /// the change can be eyeballed: rounded top corners, square bottom
    /// corners, a clipped top strip following the rounding, and a border
    /// overlay with arcs only at the rounded corners.
    func testMixedRadiiClipRenderForInspection() async throws {
        let url = try await MainActor.run { () -> URL in
            let card = ViewNode(
                frame: Rect(x: 10, y: 10, width: 180, height: 60),
                backgroundColor: Color(red: 1, green: 1, blue: 1, alpha: 1),
                borderColor: Color(red: 0.1, green: 0.1, blue: 0.1, alpha: 1),
                borderWidth: 2,
                cornerRadii: RetainedCornerRadii(topLeft: 12, topRight: 12),
                clipsToBounds: true
            )
            card.addChild(
                ViewNode(
                    frame: Rect(x: 0, y: 0, width: 180, height: 20),
                    backgroundColor: Color(red: 0.2, green: 0.4, blue: 0.9, alpha: 1)
                ))
            card.addChild(
                ViewNode(
                    frame: Rect(x: 0, y: 40, width: 90, height: 20),
                    backgroundColor: Color(red: 0.2, green: 0.7, blue: 0.3, alpha: 1)
                ))
            card.addChild(
                ViewNode(
                    frame: Rect(x: 90, y: 40, width: 90, height: 20),
                    backgroundColor: Color(red: 0.9, green: 0.3, blue: 0.2, alpha: 1)
                ))

            let scene = ScenePainter.paint(
                root: card,
                clearColor: Color(red: 0.85, green: 0.85, blue: 0.85, alpha: 1),
                surfaceSize: Size(width: 200, height: 80))
            let bitmap = GPUIRawSceneRasterizer.rasterize(scene, size: IntSize(width: 200, height: 80))
            let url = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("per-corner-clip-inspection.png")
            try bitmap.writePNG(to: url)
            return url
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        print("inspection render written to \(url.path)")
    }
}
