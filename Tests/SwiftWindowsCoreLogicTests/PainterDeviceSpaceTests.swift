import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI

/// Device-space correctness and compositing-group integrity in the painter.
///
/// Two of these were user-visible on every HiDPI machine and every
/// `.drawingGroup()`: paths were the one primitive family never multiplied by
/// `displayScale` (so `Shape`, `Canvas` and vector-icon content rendered at
/// `1/scale`, anchored toward the window origin, while its container rendered
/// correctly), and the compositing-group sub-scene never carried a glyph atlas
/// (so every piece of text inside a `drawingGroup` silently disappeared —
/// `RasterTarget.drawGlyph` returns immediately on a nil atlas).
///
/// The rest pin the boundaries the painter had no concept of at all: the
/// offscreen buffer's size, the footprint culling decides against, and how many
/// times one border ring is blended.
@MainActor
final class PainterDeviceSpaceTests: XCTestCase {

    private let surfaceSize = Size(width: 800, height: 600)

    /// Unit-space rectangle path; `backgroundPath` is scaled to the node's fill
    /// rect, so this covers the node exactly.
    private func unitRectPath() -> RenderPath {
        var path = RenderPath()
        path.move(to: Point(x: 0, y: 0))
        path.addLine(to: Point(x: 1, y: 0))
        path.addLine(to: Point(x: 1, y: 1))
        path.addLine(to: Point(x: 0, y: 1))
        path.close()
        return path
    }

    /// Self-intersecting bowtie: the tessellator rejects it, so it stays a CPU
    /// `PathPrimitive` and its geometry is directly observable.
    private func unitBowtiePath() -> RenderPath {
        var path = RenderPath()
        path.move(to: Point(x: 0, y: 0))
        path.addLine(to: Point(x: 1, y: 1))
        path.addLine(to: Point(x: 0, y: 1))
        path.addLine(to: Point(x: 1, y: 0))
        path.close()
        return path
    }

    // MARK: - Paths in device space

    func testBackgroundPathQuadScalesWithDisplayScale() async {
        func quad(atScale scale: Double) -> QuadPrimitive {
            let node = ViewNode(
                frame: Rect(x: 10, y: 20, width: 100, height: 50),
                backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1),
                backgroundPath: unitRectPath()
            )
            let scene = ScenePainter.paint(
                root: node, clearColor: .black, surfaceSize: surfaceSize, displayScale: scale)
            XCTAssertEqual(scene.layers[0].quads.count, 1, "an axis-aligned shape promotes to one quad")
            return scene.layers[0].quads[0]
        }

        let logical = quad(atScale: 1)
        XCTAssertEqual(logical.x, 10, accuracy: 0.001)
        XCTAssertEqual(logical.y, 20, accuracy: 0.001)
        XCTAssertEqual(logical.width, 100, accuracy: 0.001)
        XCTAssertEqual(logical.height, 50, accuracy: 0.001)

        let device = quad(atScale: 2)
        XCTAssertEqual(device.x, 20, accuracy: 0.001, "shape origin must be in device pixels")
        XCTAssertEqual(device.y, 40, accuracy: 0.001)
        XCTAssertEqual(device.width, 200, accuracy: 0.001, "shape size must be in device pixels")
        XCTAssertEqual(device.height, 100, accuracy: 0.001)
    }

    func testCanvasFillPathScalesWithDisplayScale() async {
        func quad(atScale scale: Double) -> QuadPrimitive {
            let node = ViewNode(
                frame: Rect(x: 30, y: 40, width: 120, height: 120),
                canvasDraw: { context, _ in
                    var path = Path()
                    path.moveTo(Point(x: 10, y: 10))
                    path.lineTo(Point(x: 60, y: 10))
                    path.lineTo(Point(x: 60, y: 60))
                    path.lineTo(Point(x: 10, y: 60))
                    path.close()
                    context.fill(path, with: .color(Color(red: 0, green: 1, blue: 0, alpha: 1)))
                }
            )
            let scene = ScenePainter.paint(
                root: node, clearColor: .black, surfaceSize: surfaceSize, displayScale: scale)
            XCTAssertEqual(scene.layers[0].quads.count, 1)
            return scene.layers[0].quads[0]
        }

        let logical = quad(atScale: 1)
        XCTAssertEqual(logical.x, 40, accuracy: 0.001)
        XCTAssertEqual(logical.y, 50, accuracy: 0.001)
        XCTAssertEqual(logical.width, 50, accuracy: 0.001)

        let device = quad(atScale: 2)
        XCTAssertEqual(device.x, 80, accuracy: 0.001, "canvas geometry must be in device pixels")
        XCTAssertEqual(device.y, 100, accuracy: 0.001)
        XCTAssertEqual(device.width, 100, accuracy: 0.001)
        XCTAssertEqual(device.height, 100, accuracy: 0.001)
    }

    func testResidualCPUPathBoundsAndClipScaleWithDisplayScale() async {
        func path(atScale scale: Double) -> PathPrimitive {
            let node = ViewNode(
                frame: Rect(x: 0, y: 0, width: 40, height: 40),
                backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1),
                backgroundPath: unitBowtiePath()
            )
            let scene = ScenePainter.paint(
                root: node, clearColor: .black, surfaceSize: Size(width: 40, height: 40),
                displayScale: scale)
            XCTAssertEqual(scene.layers[0].paths.count, 1, "a bowtie stays a CPU path primitive")
            return scene.layers[0].paths[0]
        }

        let logical = path(atScale: 1)
        XCTAssertEqual(logical.bounds, Rect(x: 0, y: 0, width: 40, height: 40))
        XCTAssertEqual(logical.clipBounds, Rect(x: 0, y: 0, width: 40, height: 40))

        let device = path(atScale: 2)
        XCTAssertEqual(
            device.bounds, Rect(x: 0, y: 0, width: 80, height: 80),
            "CPU path bounds must be in device pixels — the rasterizer draws them 1:1")
        XCTAssertEqual(
            device.clipBounds, Rect(x: 0, y: 0, width: 80, height: 80),
            "a path's clip must be in the same space as its geometry")

        // The element stream moves with the bounds; otherwise the path would be
        // rasterized into a correctly-sized target at the wrong offset.
        let deviceExtent = device.elements.compactMap { element -> Point? in
            if case .lineTo(let point) = element { return point }
            return nil
        }
        XCTAssertEqual(deviceExtent.map(\.x).max() ?? 0, 80, accuracy: 0.001)
        XCTAssertEqual(deviceExtent.map(\.y).max() ?? 0, 80, accuracy: 0.001)
    }

    // MARK: - Compositing-group integrity

    func testCompositingGroupCarriesGlyphAtlasSoTextSurvives() async {
        NativeGlyphAtlas.shared.resetForTesting()

        let group = ViewNode(frame: Rect(x: 0, y: 0, width: 120, height: 40), isCompositingGroup: true)
        let label = ViewNode(
            frame: Rect(x: 0, y: 0, width: 120, height: 40),
            text: "TOTAL",
            textStyle: PixelTextStyle(color: .white, alignment: .leading, verticalAlignment: .top, nativeFontSize: 18)
        )
        group.addChild(label)

        let scene = ScenePainter.paint(
            root: group, clearColor: .black, surfaceSize: Size(width: 120, height: 40))

        XCTAssertEqual(scene.layers[0].images.count, 1, "a compositing group composites to one image")
        let binding = try? XCTUnwrap(scene.imageResources.first)
        guard let binding else { return }
        XCTAssertTrue(
            binding.bitmap.pixels.contains { $0 != 0 },
            "text inside a compositing group must reach the offscreen bitmap; a nil sub-scene "
                + "glyph atlas makes the CPU rasterizer drop every glyph silently")
    }

    func testCompositingGroupDoesNotConsumeTheFrameGlyphAtlasSnapshot() async {
        NativeGlyphAtlas.shared.resetForTesting()

        let root = ViewNode(frame: Rect(x: 0, y: 0, width: 200, height: 80))
        let group = ViewNode(frame: Rect(x: 0, y: 0, width: 120, height: 40), isCompositingGroup: true)
        group.addChild(
            ViewNode(
                frame: Rect(x: 0, y: 0, width: 120, height: 40),
                text: "GROUP",
                textStyle: PixelTextStyle(
                    color: .white, alignment: .leading, verticalAlignment: .top, nativeFontSize: 18)
            ))
        let outside = ViewNode(
            frame: Rect(x: 0, y: 40, width: 200, height: 40),
            text: "OUTSIDE",
            textStyle: PixelTextStyle(color: .white, alignment: .leading, verticalAlignment: .top, nativeFontSize: 18)
        )
        root.addChild(group)
        root.addChild(outside)

        let scene = ScenePainter.paint(
            root: root, clearColor: .black, surfaceSize: Size(width: 200, height: 80))

        let usesNativeGlyphs = !scene.layers[0].glyphs.isEmpty
        let usesPixelGlyphs = !scene.layers[0].pixelGlyphs.isEmpty
        XCTAssertTrue(usesNativeGlyphs || usesPixelGlyphs, "the text outside the group must still emit glyphs")
        if usesNativeGlyphs {
            let atlas = try? XCTUnwrap(scene.glyphAtlas)
            guard let atlas else { return }
            guard case .region = atlas.update else {
                XCTFail(
                    "the sub-scene must peek at the atlas, not consume the frame's dirty region — "
                        + "otherwise the outer scene ships UVs the backend never uploaded")
                return
            }
        }
    }

    func testCompositingGroupFallsBackToInlinePaintingOnNonFiniteFrame() async {
        let group = ViewNode(
            frame: Rect(x: 0, y: 0, width: .infinity, height: 40),
            isCompositingGroup: true
        )
        group.addChild(
            ViewNode(
                frame: Rect(x: 0, y: 0, width: 30, height: 30),
                backgroundColor: Color(red: 0, green: 1, blue: 0, alpha: 1)
            ))

        let scene = ScenePainter.paint(
            root: group, clearColor: .black, surfaceSize: Size(width: 200, height: 100))

        XCTAssertTrue(scene.layers[0].images.isEmpty, "an unsizable group must not allocate a buffer")
        XCTAssertEqual(
            scene.layers[0].quads.count, 1,
            "falling back means painting the children inline, not dropping them")
    }

    func testCompositingGroupBufferIsClampedToTheClip() async {
        // `.drawingGroup()` on tall scroll content used to allocate the content
        // size — 4000 × 20000 logical is ~320 MB per frame at scale 1.
        let group = ViewNode(
            frame: Rect(x: 0, y: 0, width: 4000, height: 20000),
            drawingGroup: RetainedDrawingGroup()
        )
        group.addChild(
            ViewNode(
                frame: Rect(x: 0, y: 0, width: 60, height: 60),
                backgroundColor: Color(red: 0, green: 0, blue: 1, alpha: 1)
            ))

        let scene = ScenePainter.paint(
            root: group, clearColor: .black, surfaceSize: Size(width: 200, height: 100))

        XCTAssertEqual(scene.layers[0].images.count, 1)
        let binding = try? XCTUnwrap(scene.imageResources.first)
        guard let binding else { return }
        XCTAssertLessThanOrEqual(binding.bitmap.width, 200, "buffer must not exceed the visible clip")
        XCTAssertLessThanOrEqual(binding.bitmap.height, 100)
        XCTAssertTrue(
            binding.bitmap.pixels.contains { $0 != 0 },
            "clamping to the clip must keep the visible content, not blank it")
    }

    // MARK: - Cull footprint

    func testShadowReachingIntoTheClipSurvivesTheNodeBeingOutsideIt() async {
        let parent = ViewNode(frame: Rect(x: 0, y: 0, width: 100, height: 100), clipsToBounds: true)
        // Frame starts one pixel past the clip's right edge; its 20 pt shadow
        // spread still reaches back inside.
        let child = ViewNode(
            frame: Rect(x: 101, y: 20, width: 40, height: 40),
            backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1),
            shadowColor: Color(red: 0, green: 0, blue: 0, alpha: 0.5),
            shadowSpread: 20
        )
        parent.addChild(child)

        let scene = ScenePainter.paint(
            root: parent, clearColor: .black, surfaceSize: Size(width: 200, height: 200))

        XCTAssertEqual(
            scene.layers[0].shadows.count, 1,
            "culling on the frame alone made shadows pop at every scroll boundary")
    }

    func testDegenerateParentStillPaintsItsChildren() async {
        let parent = ViewNode(frame: Rect(x: 10, y: 10, width: 0, height: 0))
        let child = ViewNode(
            frame: Rect(x: 0, y: 0, width: 40, height: 40),
            backgroundColor: Color(red: 1, green: 0, blue: 0, alpha: 1)
        )
        parent.addChild(child)

        let scene = ScenePainter.paint(
            root: parent, clearColor: .black, surfaceSize: Size(width: 200, height: 200))

        XCTAssertEqual(scene.layers[0].quads.count, 1, "a zero-size container must not erase its subtree")
        XCTAssertEqual(scene.layers[0].quads[0].x, 10, accuracy: 0.001)
        XCTAssertEqual(scene.layers[0].quads[0].width, 40, accuracy: 0.001)
    }

    func testDegenerateNodePaintsNoDecorationOfItsOwn() async {
        let node = ViewNode(
            frame: Rect(x: 10, y: 10, width: 0, height: 0),
            borderColor: Color(red: 1, green: 1, blue: 1, alpha: 1),
            borderWidth: 2,
            outlineColor: Color(red: 1, green: 0, blue: 0, alpha: 1),
            outlineWidth: 3,
            shadowColor: Color(red: 0, green: 0, blue: 0, alpha: 0.5),
            shadowSpread: 8
        )

        let scene = ScenePainter.paint(
            root: node, clearColor: .black, surfaceSize: Size(width: 200, height: 200))

        XCTAssertTrue(scene.layers[0].quads.isEmpty, "a zero-size node has no border or outline to draw")
        XCTAssertTrue(scene.layers[0].shadows.isEmpty, "and casts no shadow")
    }

    // MARK: - Border ring coverage

    func testTranslucentContainerBorderCoversEachRingPixelOnce() async {
        let container = ViewNode(
            frame: Rect(x: 0, y: 0, width: 40, height: 40),
            borderColor: Color(red: 1, green: 1, blue: 1, alpha: 0.1),
            borderWidth: 2
        )
        container.addChild(ViewNode(frame: Rect(x: 4, y: 4, width: 32, height: 32)))

        let scene = ScenePainter.paint(
            root: container, clearColor: .black, surfaceSize: Size(width: 40, height: 40))

        let quads = scene.layers[0].quads
        for quad in quads {
            XCTAssertEqual(
                quad.startA, 0.1, accuracy: 0.001,
                "the ring must carry the requested alpha, not a doubled one")
        }

        func coverage(ofX x: Double, y: Double) -> Int {
            quads.filter { quad in
                Double(quad.x) <= x && x < Double(quad.x + quad.width)
                    && Double(quad.y) <= y && y < Double(quad.y + quad.height)
            }.count
        }

        XCTAssertEqual(
            coverage(ofX: 20, y: 0.5), 1,
            "a container's border used to be drawn twice: a full-rect fill before children and "
                + "the ring after, so 0.10 alpha composited at 0.19")
        XCTAssertEqual(
            coverage(ofX: 20, y: 20), 0,
            "the pre-children full-rect fill tinted the whole container interior with the border colour")
    }

    func testLeafBorderStillPaintsWithoutAChildToCoverIt() async {
        let leaf = ViewNode(
            frame: Rect(x: 0, y: 0, width: 40, height: 40),
            borderColor: Color(red: 1, green: 1, blue: 1, alpha: 1),
            borderWidth: 2
        )

        let scene = ScenePainter.paint(
            root: leaf, clearColor: .black, surfaceSize: Size(width: 40, height: 40))

        XCTAssertEqual(scene.layers[0].quads.count, 1, "a leaf keeps the single full-rect border fill")
        XCTAssertEqual(scene.layers[0].quads[0].width, 40, accuracy: 0.001)
    }
}
