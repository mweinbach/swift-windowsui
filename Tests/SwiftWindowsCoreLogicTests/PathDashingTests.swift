import SwiftWindowsCore
import SwiftWindowsGraphics
import SwiftWindowsUI
import XCTest

/// Dashes are geometry by the time a `PathPrimitive` sees them.
///
/// `BorderSegments` has always resolved them for the one outline that is a
/// rounded rectangle. Every other stroke lowering — a `Shape` outline that
/// arrives as a `backgroundPath`, a `Canvas` `strokePath`, a frame-path
/// stroke command — had nowhere to send `dashPattern` and dropped it, so the
/// stroke shipped solid. `PathDashing` is the same walk over an arbitrary
/// outline.
@MainActor
final class PathDashingTests: XCTestCase {
    private let surfaceSize = Size(width: 200, height: 200)

    // MARK: - The walk

    func testAStraightRunBecomesEvenlySpacedOnRuns() async {
        let line: [PathElement] = [.moveTo(.zero), .lineTo(Point(x: 100, y: 0))]
        guard let dashed = PathDashing.dashed(line, pattern: [10, 10], offset: 0) else {
            return XCTFail("a [10, 10] pattern must resolve")
        }
        // 100 points at 10 on / 10 off is five dashes.
        let moves = dashed.filter { if case .moveTo = $0 { return true } else { return false } }
        XCTAssertEqual(moves.count, 5)
        XCTAssertEqual(dashed.count, 10, "one moveTo and one lineTo per dash")

        var spans: [(Double, Double)] = []
        var start: Double?
        for element in dashed {
            switch element {
            case .moveTo(let point): start = point.x
            case .lineTo(let point):
                if let from = start { spans.append((from, point.x)) }
                start = nil
            default: break
            }
        }
        XCTAssertEqual(spans.map(\.0), [0, 20, 40, 60, 80])
        for span in spans {
            XCTAssertEqual(span.1 - span.0, 10, accuracy: 0.0001)
        }
    }

    func testDashOffsetShiftsThePhase() async {
        let line: [PathElement] = [.moveTo(.zero), .lineTo(Point(x: 40, y: 0))]
        guard let dashed = PathDashing.dashed(line, pattern: [10, 10], offset: 5) else {
            return XCTFail("a [10, 10] pattern must resolve")
        }
        guard case .moveTo(let first) = dashed.first else { return XCTFail("no first dash") }
        XCTAssertEqual(first.x, 0, accuracy: 0.0001, "the first dash starts already half spent")
        guard case .lineTo(let end) = dashed[1] else { return XCTFail("no first dash end") }
        XCTAssertEqual(end.x, 5, accuracy: 0.0001)
    }

    func testAnOddPatternDoublesSoOnAndOffAlternateAsStrokeStyleSays() async {
        XCTAssertEqual(PathDashing.normalizedPattern([6]), [6, 6])
        XCTAssertEqual(PathDashing.normalizedPattern([4, 2]), [4, 2])
        XCTAssertEqual(PathDashing.normalizedPattern([]), [])
        XCTAssertEqual(PathDashing.normalizedPattern([0, -3]), [])
        XCTAssertNil(PathDashing.dashed([.moveTo(.zero), .lineTo(Point(x: 10, y: 0))], pattern: [], offset: 0))
    }

    func testADashSpanningAVertexKeepsTheCorner() async {
        let corner: [PathElement] = [
            .moveTo(.zero), .lineTo(Point(x: 10, y: 0)), .lineTo(Point(x: 10, y: 10)),
        ]
        guard let dashed = PathDashing.dashed(corner, pattern: [20, 5], offset: 0) else {
            return XCTFail("a [20, 5] pattern must resolve")
        }
        // One 20-long dash covering both 10-long legs: moveTo + two lineTo.
        XCTAssertEqual(dashed.count, 3)
        guard case .lineTo(let mid) = dashed[1], case .lineTo(let end) = dashed[2] else {
            return XCTFail("the corner vertex must survive")
        }
        XCTAssertEqual(mid.x, 10, accuracy: 0.0001)
        XCTAssertEqual(mid.y, 0, accuracy: 0.0001)
        XCTAssertEqual(end.y, 10, accuracy: 0.0001)
    }

    /// A curve has no closed-form arc length, so a dashed one is flattened
    /// first — and the walk still terminates on a pattern finer than the
    /// outline is long.
    func testAFinePatternOnACurveStaysBounded() async {
        let circle: [PathElement] = [
            .arc(center: Point(x: 50, y: 50), radius: 40, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
        ]
        guard let dashed = PathDashing.dashed(circle, pattern: [0.0001, 0.0001], offset: 0) else {
            return XCTFail("the pattern must resolve")
        }
        XCTAssertLessThanOrEqual(dashed.count, PathDashing.maxDashSteps * 2 + 4)
    }

    // MARK: - The lowerings

    /// A `Shape` outline that arrives as a `backgroundPath` is not a rounded
    /// rect, so `BorderSegments` never sees it. Its dashes used to vanish.
    func testAShapeOutlineDashesInsteadOfDrawingSolid() async {
        var square = RenderPath()
        square.move(to: Point(x: 0, y: 0))
        square.addLine(to: Point(x: 1, y: 0))
        square.addLine(to: Point(x: 1, y: 1))
        square.addLine(to: Point(x: 0, y: 1))
        square.close()

        func scene(dash: [Double]) -> GPUIScene {
            let node = ViewNode(
                frame: Rect(x: 20, y: 20, width: 100, height: 100),
                borderColor: Color(red: 0, green: 1, blue: 0, alpha: 1),
                borderWidth: 4,
                borderStrokeStyle: StrokeStyle(lineWidth: 4, dashPattern: dash),
                backgroundPath: square)
            return ScenePainter.paint(root: node, clearColor: .clear, surfaceSize: surfaceSize)
        }

        let solidInk = strokeInk(in: scene(dash: []))
        let dashedInk = strokeInk(in: scene(dash: [8, 8]))
        XCTAssertGreaterThan(solidInk, 0)
        XCTAssertGreaterThan(dashedInk, 0, "a dashed outline still draws something")
        XCTAssertLessThan(
            Double(dashedInk), Double(solidInk) * 0.75,
            "a 50 % duty cycle must remove roughly half the ink; it drew solid")
    }

    /// The same for a `Canvas` stroke, whose style arrives on the operation.
    func testACanvasStrokeDashesInsteadOfDrawingSolid() async {
        func scene(dash: [Double]) -> GPUIScene {
            let node = ViewNode(
                frame: Rect(x: 0, y: 0, width: 200, height: 200),
                canvasDraw: { context, _ in
                    var path = Path()
                    path.moveTo(Point(x: 20, y: 100))
                    path.lineTo(Point(x: 180, y: 100))
                    context.stroke(
                        path, with: .color(Color(red: 1, green: 0, blue: 0, alpha: 1)),
                        style: StrokeStyle(lineWidth: 6, dashPattern: dash))
                })
            return ScenePainter.paint(root: node, clearColor: .clear, surfaceSize: surfaceSize)
        }

        let solidInk = strokeInk(in: scene(dash: []))
        let dashedInk = strokeInk(in: scene(dash: [10, 10]))
        XCTAssertGreaterThan(solidInk, 0)
        XCTAssertGreaterThan(dashedInk, 0)
        XCTAssertLessThan(Double(dashedInk), Double(solidInk) * 0.75)
    }

    /// And the frame-path bridge, the legacy lowering, speaks it too.
    func testTheFrameBridgeResolvesDashes() async {
        var line = RenderPath()
        line.move(to: Point(x: 20, y: 20))
        line.addLine(to: Point(x: 180, y: 20))

        func paths(dash: [Double]) -> [PathPrimitive] {
            let frame = RenderFrame(
                clearColor: .black,
                commands: [
                    .strokePath(
                        StrokePathCommand(
                            path: line,
                            color: Color(red: 1, green: 1, blue: 1, alpha: 1),
                            style: StrokeStyle(lineWidth: 4, dashPattern: dash),
                            clipRect: nil))
                ])
            return GPUIScene(from: frame, surfaceSize: surfaceSize).layers[0].paths
        }

        XCTAssertEqual(paths(dash: []).first?.elements.count, 2)
        let dashed = paths(dash: [16, 16]).first?.elements ?? []
        XCTAssertEqual(dashed.count, 10, "160 points at 16 on / 16 off is five dashes")
    }

    // MARK: - Helpers

    /// Total stroke alpha the scene rasterizes, across the path primitives
    /// and any quads the tessellator promoted them into.
    private func strokeInk(in scene: GPUIScene) -> Int {
        var finished = scene
        finished.finish()
        let bitmap = GPUIRawSceneRasterizer.rasterize(
            finished, size: IntSize(width: Int32(surfaceSize.width), height: Int32(surfaceSize.height)))
        var total = 0
        for index in stride(from: 3, to: bitmap.pixels.count, by: 4) {
            total += Int(bitmap.pixels[index])
        }
        return total
    }
}
