import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI

/// `StrokeStyle` as a contract rather than a suggestion.
///
/// The information was always there — `CanvasGraphicsContext.stroke` takes a
/// `StrokeStyle`, `ViewNode.borderStrokeStyle` holds one, `StrokePathCommand`
/// carries one — and every lowering threw away everything but `lineWidth`,
/// because `PathPrimitive` had nowhere to put it. Both stroke rasterizers
/// then invented the rest: the CPU coverage path butt-capped and round-joined
/// everything, the painter's quad tessellator square-capped everything. So a
/// `Canvas` stroke asking for `StrokeStyle(lineCap: .round)` — which is what
/// the SF-symbol vector fallback asks for on every icon — got neither, and
/// which wrong answer it got depended on whether the path happened to promote.
///
/// These tests pin the threading at each lowering, and the agreement between
/// the two routes at the end.
@MainActor
final class StrokeStyleContractTests: XCTestCase {

    private let surfaceSize = Size(width: 200, height: 200)

    // MARK: - The primitive itself

    /// An unspecified path strokes like an unspecified `StrokeStyle`.
    func testPathPrimitiveStrokeDefaultsMatchStrokeStyleDefaults() async {
        let path = PathPrimitive(elements: [], bounds: .zero)
        let style = StrokeStyle()
        XCTAssertEqual(path.lineCap, style.lineCap)
        XCTAssertEqual(path.lineJoin, style.lineJoin)
        XCTAssertEqual(path.miterLimit, style.miterLimit)
        XCTAssertEqual(path.strokeStyle.lineCap, style.lineCap)
    }

    /// `scaled(by:)` multiplies lengths and leaves the ratio alone. A miter
    /// limit scaled with the width would bevel at a different angle on a
    /// HiDPI display than on a 1× one.
    func testMiterLimitIsInvariantUnderDisplayScale() async {
        let path = PathPrimitive(
            elements: [.moveTo(.zero), .lineTo(Point(x: 10, y: 0))],
            bounds: Rect(x: 0, y: 0, width: 10, height: 4),
            strokeColor: .white, lineWidth: 4, lineCap: .round, lineJoin: .bevel, miterLimit: 3)
        let scaled = path.scaled(by: 1.5)
        XCTAssertEqual(scaled.lineWidth, 6, accuracy: 0.0001)
        XCTAssertEqual(scaled.miterLimit, 3, accuracy: 0.0001)
        XCTAssertEqual(scaled.lineCap, .round)
        XCTAssertEqual(scaled.lineJoin, .bevel)
        XCTAssertEqual(path.translated(by: Point(x: 5, y: 5)).lineJoin, .bevel)
    }

    /// A limit below 1 would bevel a straight run and a non-finite one never
    /// bevels at all, so the sanitizer — not the stroker — decides what a
    /// representable limit is.
    func testSanitizerBoundsTheMiterLimit() async {
        func sanitizedLimit(_ limit: Double) -> Double? {
            GPUISceneSanitizer.sanitized(
                PathPrimitive(
                    elements: [.moveTo(.zero), .lineTo(Point(x: 8, y: 0))],
                    bounds: Rect(x: 0, y: 0, width: 8, height: 2),
                    strokeColor: .white, lineWidth: 2, miterLimit: limit)
            )?.miterLimit
        }
        XCTAssertEqual(sanitizedLimit(4), 4)
        XCTAssertEqual(sanitizedLimit(0), 1, "a limit below 1 would bevel a straight run")
        XCTAssertEqual(sanitizedLimit(-8), 1)
        XCTAssertEqual(sanitizedLimit(.nan), 10)
        XCTAssertEqual(sanitizedLimit(.infinity), 10)
    }

    // MARK: - The shared rules

    func testMiterPastItsLimitResolvesToBevel() async {
        // A 67° corner: 1 / cos(turn / 2) = 2.24.
        let dot = -0.6
        XCTAssertEqual(StrokeOutlineGeometry.miterRatio(directionDot: dot) ?? 0, 2.236, accuracy: 0.001)
        XCTAssertEqual(
            StrokeOutlineGeometry.resolvedJoin(.miter, directionDot: dot, miterLimit: 10), .miter)
        XCTAssertEqual(
            StrokeOutlineGeometry.resolvedJoin(.miter, directionDot: dot, miterLimit: 2), .bevel)
        // A reversal is an unbounded miter, so it bevels at every limit.
        XCTAssertNil(StrokeOutlineGeometry.miterRatio(directionDot: -1))
        XCTAssertEqual(
            StrokeOutlineGeometry.resolvedJoin(.miter, directionDot: -1, miterLimit: 1_000), .bevel)
        // Round and bevel never depend on the limit.
        XCTAssertEqual(
            StrokeOutlineGeometry.resolvedJoin(.round, directionDot: dot, miterLimit: 1), .round)
    }

    /// A flattened curve turns by a fraction of a degree per segment; a corner
    /// turns by tens of degrees. The visibility rule has to separate them, and
    /// it has to scale with the width, because the same turn shows a wider
    /// wedge on a thicker line.
    func testJoinVisibilityScalesWithHalfWidth() async {
        let smoothTurn = cos(0.1)  // ~5.7°, a flattened-curve step
        XCTAssertFalse(
            StrokeOutlineGeometry.joinIsVisible(halfWidth: 2, directionDot: smoothTurn, join: .round))
        XCTAssertFalse(
            StrokeOutlineGeometry.joinIsVisible(halfWidth: 2, directionDot: smoothTurn, join: .miter))
        let corner = 0.0  // a right angle
        XCTAssertTrue(StrokeOutlineGeometry.joinIsVisible(halfWidth: 2, directionDot: corner, join: .round))
        XCTAssertFalse(
            StrokeOutlineGeometry.joinIsVisible(halfWidth: 0.05, directionDot: corner, join: .round),
            "a hairline's right angle moves the boundary by 0.015 px")
    }

    /// `bounds` sizes the CPU coverage window and the GPU path texture, so an
    /// emitter has to know how far a cap or a miter reaches before anything is
    /// flattened.
    func testStrokeBoundsOutsetCoversCapsAndCorners() async {
        let straight: [PathElement] = [.moveTo(.zero), .lineTo(Point(x: 40, y: 0))]
        XCTAssertEqual(
            StrokeOutlineGeometry.boundsOutset(
                forElements: straight, lineWidth: 8, lineCap: .butt, lineJoin: .miter, miterLimit: 10),
            4, accuracy: 0.001, "a straight butt-capped run reaches exactly its half width")
        XCTAssertEqual(
            StrokeOutlineGeometry.boundsOutset(
                forElements: straight, lineWidth: 8, lineCap: .square, lineJoin: .miter, miterLimit: 10),
            4 * 2.0.squareRoot(), accuracy: 0.001, "a square cap's corner is √2 half widths out")

        let rightAngle: [PathElement] = [
            .moveTo(.zero), .lineTo(Point(x: 40, y: 0)), .lineTo(Point(x: 40, y: 40)),
        ]
        XCTAssertEqual(
            StrokeOutlineGeometry.boundsOutset(
                forElements: rightAngle, lineWidth: 8, lineCap: .butt, lineJoin: .miter, miterLimit: 10),
            4 * 2.0.squareRoot(), accuracy: 0.001)
        XCTAssertEqual(
            StrokeOutlineGeometry.boundsOutset(
                forElements: rightAngle, lineWidth: 8, lineCap: .butt, lineJoin: .round, miterLimit: 10),
            4, accuracy: 0.001, "a round join never leaves the half width")

        // A spike sharper than the bounds ratio bevels rather than sizing a
        // bitmap off an app-supplied limit — and a bevel never leaves the
        // half width, so the bounds it needs are a half width.
        let needle: [PathElement] = [
            .moveTo(.zero), .lineTo(Point(x: 100, y: 1)), .lineTo(Point(x: 0, y: 2)),
        ]
        XCTAssertEqual(
            StrokeOutlineGeometry.boundsOutset(
                forElements: needle, lineWidth: 8, lineCap: .butt, lineJoin: .miter, miterLimit: 1_000),
            4, accuracy: 0.001)

        // A corner inside the ratio still sizes its own miter exactly: a 60°
        // included angle is 1 / cos 60° = 2 half widths.
        let sixtyDegrees: [PathElement] = [
            .moveTo(.zero), .lineTo(Point(x: 100, y: 0)),
            .lineTo(Point(x: 100 - 50, y: 50 * 3.0.squareRoot())),
        ]
        XCTAssertEqual(
            StrokeOutlineGeometry.boundsOutset(
                forElements: sixtyDegrees, lineWidth: 8, lineCap: .butt, lineJoin: .miter, miterLimit: 10),
            8, accuracy: 0.01)
    }

    // MARK: - The lowerings

    /// A `Canvas` stroke that the tessellator refuses (a bevel join at a
    /// visible corner) lands as a `PathPrimitive`, where its whole style is
    /// observable.
    func testCanvasStrokeStyleReachesThePathPrimitive() async {
        let node = ViewNode(
            frame: Rect(x: 0, y: 0, width: 200, height: 200),
            canvasDraw: { context, _ in
                var path = Path()
                path.moveTo(Point(x: 20, y: 20))
                path.lineTo(Point(x: 100, y: 20))
                path.lineTo(Point(x: 100, y: 100))
                context.stroke(
                    path, with: .color(Color(red: 1, green: 0, blue: 0, alpha: 1)),
                    style: StrokeStyle(lineWidth: 10, lineCap: .square, lineJoin: .bevel, miterLimit: 3))
            })
        let scene = ScenePainter.paint(root: node, clearColor: .black, surfaceSize: surfaceSize)

        XCTAssertEqual(scene.layers[0].paths.count, 1, "a bevel join is not a rectangle")
        let path = scene.layers[0].paths[0]
        XCTAssertEqual(path.lineWidth, 10, accuracy: 0.001)
        XCTAssertEqual(path.lineCap, .square)
        XCTAssertEqual(path.lineJoin, .bevel)
        XCTAssertEqual(path.miterLimit, 3, accuracy: 0.001)
    }

    /// The same for a `Shape` outline, whose style lives on the node.
    func testShapeBorderStrokeStyleReachesThePathPrimitive() async {
        var bowtie = RenderPath()
        bowtie.move(to: Point(x: 0, y: 0))
        bowtie.addLine(to: Point(x: 1, y: 1))
        bowtie.addLine(to: Point(x: 1, y: 0))
        bowtie.addLine(to: Point(x: 0, y: 1))
        bowtie.close()

        let node = ViewNode(
            frame: Rect(x: 20, y: 20, width: 100, height: 100),
            borderColor: Color(red: 0, green: 1, blue: 0, alpha: 1),
            borderWidth: 6,
            borderStrokeStyle: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .bevel, miterLimit: 2),
            backgroundPath: bowtie)
        let scene = ScenePainter.paint(root: node, clearColor: .black, surfaceSize: surfaceSize)

        guard let path = scene.layers[0].paths.first(where: { $0.strokeColor.alpha > 0 }) else {
            return XCTFail("the shape outline must reach the scene")
        }
        XCTAssertEqual(path.lineCap, .round)
        XCTAssertEqual(path.lineJoin, .bevel)
        XCTAssertEqual(path.miterLimit, 2, accuracy: 0.001)
        // A stroke straddles its path, so the primitive's footprint has to be
        // wider than the path's own geometry or the outer half is cropped —
        // which is exactly what the shape-outline lowering used to do, by
        // handing the primitive the path's bounding rect unchanged.
        let xs: [Double] = path.elements.compactMap {
            if case .lineTo(let point) = $0 { return point.x }
            if case .moveTo(let point) = $0 { return point.x }
            return nil
        }
        guard let minX = xs.min(), let maxX = xs.max() else { return XCTFail("no geometry") }
        XCTAssertLessThanOrEqual(path.bounds.minX, minX - 2.9, "the outer half of the stroke must fit")
        XCTAssertGreaterThanOrEqual(path.bounds.maxX, maxX + 2.9)
    }

    /// The frame path lowers the same node to a `StrokePathCommand`; it used
    /// to rebuild the style from `borderWidth`, so the two paths drew
    /// different shapes from the same tree.
    func testFrameStrokeCommandCarriesTheNodeStyle() async {
        var diamond = RenderPath()
        diamond.move(to: Point(x: 0.5, y: 0))
        diamond.addLine(to: Point(x: 1, y: 0.5))
        diamond.addLine(to: Point(x: 0.5, y: 1))
        diamond.addLine(to: Point(x: 0, y: 0.5))
        diamond.close()

        let node = ViewNode(
            frame: Rect(x: 0, y: 0, width: 80, height: 80),
            borderColor: Color(red: 0, green: 0, blue: 1, alpha: 1),
            borderWidth: 4,
            borderStrokeStyle: StrokeStyle(lineWidth: 4, lineCap: .square, lineJoin: .round, miterLimit: 6),
            backgroundPath: diamond)
        let frame = RetainedViewRuntime(root: node).renderFrame()

        let strokes: [StrokePathCommand] = frame.commands.compactMap {
            if case .strokePath(let stroke) = $0 { return stroke }
            return nil
        }
        XCTAssertEqual(strokes.count, 1)
        XCTAssertEqual(strokes.first?.style.lineCap, .square)
        XCTAssertEqual(strokes.first?.style.lineJoin, .round)
        XCTAssertEqual(strokes.first?.style.miterLimit ?? 0, 6, accuracy: 0.001)
    }

    /// …and the scene bridge carries it the rest of the way, instead of
    /// keeping `lineWidth` and dropping the sentence it was part of.
    func testSceneBridgeCarriesStrokeStyle() async {
        var path = RenderPath()
        path.move(to: Point(x: 20, y: 20))
        path.addLine(to: Point(x: 120, y: 20))

        let frame = RenderFrame(
            clearColor: .black,
            commands: [
                .strokePath(
                    StrokePathCommand(
                        path: path,
                        color: Color(red: 1, green: 1, blue: 0, alpha: 1),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .bevel, miterLimit: 5)))
            ])
        let scene = GPUIScene(from: frame, surfaceSize: surfaceSize)

        XCTAssertEqual(scene.layers[0].paths.count, 1)
        let primitive = scene.layers[0].paths[0]
        XCTAssertEqual(primitive.lineCap, .round)
        XCTAssertEqual(primitive.lineJoin, .bevel)
        XCTAssertEqual(primitive.miterLimit, 5, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(
            primitive.bounds.size.height, 8, "a horizontal stroke's bounds must contain its width")
    }

    // MARK: - One shape, either route

    /// The whole point: a stroke the tessellator promotes and the same stroke
    /// rasterized as coverage are the *same shape*. Round caps and round joins
    /// are the case both routes can draw, so they are the case that can be
    /// compared — and the one where the tessellator's answer is a
    /// `cornerRadius` and the rasterizer's is a polygon.
    func testPromotedAndRasterizedRoundStrokesAgree() async {
        let polyline = PathPrimitive(
            elements: [
                .moveTo(Point(x: 24, y: 40)),
                .lineTo(Point(x: 76, y: 40)),
                .lineTo(Point(x: 104, y: 96)),
            ],
            bounds: Rect(x: 8, y: 20, width: 112, height: 96),
            strokeColor: Color(red: 1, green: 1, blue: 1, alpha: 1),
            lineWidth: 12,
            lineCap: .round,
            lineJoin: .round)

        guard let quads = PathToQuadTessellator.tessellate(polyline) else {
            return XCTFail("a round-capped, round-joined polyline must still promote")
        }
        let size = IntSize(width: 128, height: 128)
        var promoted = GPUIScene(clearColor: .black)
        for quad in quads { promoted.addQuad(quad, toLayer: 0) }
        promoted.finish()
        var rasterized = GPUIScene(clearColor: .black)
        rasterized.addPath(polyline, toLayer: 0)
        rasterized.finish()

        let a = GPUIRawSceneRasterizer.rasterize(promoted, size: size)
        let b = GPUIRawSceneRasterizer.rasterize(rasterized, size: size)
        var mismatched = 0
        for index in stride(from: 0, to: a.pixels.count, by: 4) {
            if abs(Int(a.pixels[index]) - Int(b.pixels[index])) > 24 { mismatched += 1 }
        }
        let total = a.pixels.count / 4
        XCTAssertLessThan(
            Double(mismatched) / Double(total), 0.02,
            "the two stroke routes must agree on everything but antialiasing: "
                + "\(mismatched) of \(total) pixels differ")
    }

    /// And when it cannot draw the style exactly, it says so instead of
    /// drawing something else: a sharp miter's *wedge* goes to the
    /// rasterizer, and the two bodies it joins do not.
    func testTessellatorRefusesAJoinItCannotDrawExactly() async {
        var sharp = PathPrimitive(
            elements: [
                .moveTo(Point(x: 20, y: 100)),
                .lineTo(Point(x: 60, y: 20)),
                .lineTo(Point(x: 100, y: 100)),
            ],
            bounds: Rect(x: 4, y: 0, width: 112, height: 112),
            strokeColor: .white,
            lineWidth: 12)
        let mixed = PathToQuadTessellator.tessellateMixed(sharp)
        XCTAssertEqual(mixed?.quads.count, 2, "a 53° miter is a kite, not a rectangle — but its bodies are")
        XCTAssertEqual(mixed?.residualPath?.elements.count, 3, "one wedge on the CPU, not the whole chart")

        sharp.lineJoin = .round
        let rounded = PathToQuadTessellator.tessellateMixed(sharp)
        XCTAssertNotNil(rounded, "a round join is a disc, which is a quad")
        XCTAssertNil(rounded?.residualPath)
    }

    /// The drawn miter and the declared `bounds` read the same limit, so a
    /// spike sharper than a raster can hold bevels instead of being drawn and
    /// then cropped flat by the buffer edge.
    func testSharpMiterBevelsRatherThanOverflowingItsBounds() async {
        // A ~15° included angle: 1 / cos(turn / 2) ≈ 7.7 half widths, well
        // past `maxMiterBoundsRatio` and well inside `StrokeStyle`'s default
        // `miterLimit` of 10.
        let dot = cos(.pi - 15.0 * .pi / 180)
        let ratio = StrokeOutlineGeometry.miterRatio(directionDot: dot) ?? 0
        XCTAssertGreaterThan(ratio, StrokeOutlineGeometry.maxMiterBoundsRatio)
        XCTAssertLessThan(ratio, 10)
        XCTAssertEqual(
            StrokeOutlineGeometry.resolvedJoin(.miter, directionDot: dot, miterLimit: 10), .bevel,
            "a miter the bounds cannot hold is drawn as the bevel it degrades to")
        XCTAssertEqual(StrokeOutlineGeometry.effectiveMiterLimit(10), StrokeOutlineGeometry.maxMiterBoundsRatio)
        XCTAssertEqual(StrokeOutlineGeometry.effectiveMiterLimit(2), 2, "a tighter app limit still wins")
        XCTAssertEqual(StrokeOutlineGeometry.effectiveMiterLimit(0), 1)

        // Both stroke routes read `resolvedJoin`, so agreeing with it is what
        // "both backends agree" means here. What the raster then has to show
        // is that the drawn tip stays inside the outset an emitter declared:
        // given deliberately generous bounds, an unclamped miter would still
        // paint ~7.7 half widths past the vertex and a bevel paints none.
        let needle: [PathElement] = [
            .moveTo(Point(x: 20, y: 60)),
            .lineTo(Point(x: 120, y: 46.8)),
            .lineTo(Point(x: 20, y: 33.6)),
        ]
        let outset = StrokeOutlineGeometry.boundsOutset(
            forElements: needle, lineWidth: 8, lineCap: .butt, lineJoin: .miter, miterLimit: 10)
        let slack = 40.0
        let bounds = Rect(
            x: 20 - slack, y: 33.6 - slack, width: 100 + 2 * slack, height: 26.4 + 2 * slack)
        let path = PathPrimitive(
            elements: needle,
            bounds: bounds,
            strokeColor: .white,
            lineWidth: 8,
            lineJoin: .miter,
            miterLimit: 10)
        guard let bitmap = GPUIRawSceneRasterizer.rasterizePath(path) else {
            return XCTFail("the needle rasterized to nothing")
        }
        let width = Int(bitmap.width)
        let height = Int(bitmap.height)
        var furthestInkX = 0
        for y in 0..<height {
            for x in stride(from: width - 1, through: furthestInkX, by: -1)
            where bitmap.pixels[(y * width + x) * 4 + 3] > 8 {
                furthestInkX = max(furthestInkX, x)
                break
            }
        }
        let tipX = 120 - bounds.origin.x
        XCTAssertLessThanOrEqual(
            Double(furthestInkX), tipX + outset + 1,
            "the drawn spike reached past the bounds its own emitter declared")
    }
}
