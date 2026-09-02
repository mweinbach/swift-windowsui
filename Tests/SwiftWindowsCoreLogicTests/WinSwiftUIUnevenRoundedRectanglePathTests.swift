import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Public path geometry only. Continuous-corner fidelity, RTL path mirroring,
/// retained trim scaling and clipping keep their separate qualification gaps.
@MainActor
final class WinSwiftUIUnevenRoundedRectanglePathTests: XCTestCase {
    private static let red = Color(red: 1, green: 0, blue: 0, alpha: 1)
    private static let canvasSize = IntSize(width: 144, height: 104)

    func testFourUnequalRadiiProduceTheRequestedTranslatedArcs() async {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 6, bottomLeadingRadius: 10,
            bottomTrailingRadius: 18, topTrailingRadius: 14, style: .circular)
        let path = shape.path(in: Rect(x: 10, y: 20, width: 120, height: 80))

        XCTAssertEqual(
            path.elements,
            [
                .moveTo(Point(x: 16, y: 20)),
                .lineTo(Point(x: 116, y: 20)),
                .arc(
                    center: Point(x: 116, y: 34), radius: 14,
                    startAngle: -Double.pi / 2, endAngle: 0, clockwise: false),
                .lineTo(Point(x: 130, y: 82)),
                .arc(
                    center: Point(x: 112, y: 82), radius: 18,
                    startAngle: 0, endAngle: Double.pi / 2, clockwise: false),
                .lineTo(Point(x: 20, y: 100)),
                .arc(
                    center: Point(x: 20, y: 90), radius: 10,
                    startAngle: Double.pi / 2, endAngle: Double.pi, clockwise: false),
                .lineTo(Point(x: 10, y: 26)),
                .arc(
                    center: Point(x: 16, y: 26), radius: 6,
                    startAngle: Double.pi, endAngle: 3 * Double.pi / 2, clockwise: false),
                .close,
            ])
        XCTAssertTrue(path.contains(Point(x: 70, y: 60)))
        XCTAssertFalse(path.contains(Point(x: 9, y: 60)))
    }

    func testSquareCornersRemainInsideWhenOnlyTheOppositeCornerIsRounded() async {
        let path = UnevenRoundedRectangle(bottomTrailingRadius: 20, style: .circular)
            .path(in: Rect(x: 0, y: 0, width: 120, height: 80))

        for point in [Point(x: 1, y: 1), Point(x: 119, y: 1), Point(x: 1, y: 79)] {
            XCTAssertTrue(path.contains(point), "A zero-radius corner must stay square")
            XCTAssertTrue(path.contains(point, eoFill: true))
        }
        XCTAssertFalse(path.contains(Point(x: 119, y: 79)))
        XCTAssertFalse(path.contains(Point(x: 119, y: 79), eoFill: true))
        XCTAssertTrue(path.contains(Point(x: 100, y: 60)))
    }

    func testEachRadiusAffectsOnlyItsNamedLocalCorner() async {
        let cases: [(RectangleCornerRadii, Int)] = [
            (RectangleCornerRadii(topLeading: 12), 0),
            (RectangleCornerRadii(topTrailing: 12), 1),
            (RectangleCornerRadii(bottomTrailing: 12), 2),
            (RectangleCornerRadii(bottomLeading: 12), 3),
        ]
        let samples = [
            Point(x: 1, y: 1), Point(x: 79, y: 1),
            Point(x: 79, y: 39), Point(x: 1, y: 39),
        ]
        for (radii, roundedCorner) in cases {
            let path = UnevenRoundedRectangle(cornerRadii: radii, style: .circular)
                .path(in: Rect(x: 0, y: 0, width: 80, height: 40))
            for (index, point) in samples.enumerated() {
                XCTAssertEqual(path.contains(point), index != roundedCorner)
            }
        }
    }

    func testEqualRadiiKeepTheExistingUniformConstructorElements() async {
        let rectangles = [
            Rect(x: 10, y: -12, width: 120, height: 80),
            Rect(x: -20, y: 8, width: 64, height: 64),
        ]
        for rect in rectangles {
            for radius in [-4.0, 0, 3.25, 16, 40, 400, Double.infinity, Double.nan] {
                let path = uniformShape(radius).path(in: rect)
                let expected = Path(roundedRect: rect, cornerRadius: radius)
                XCTAssertEqual(path, expected)
                XCTAssertEqual(path.elements.count, 10)
            }
        }
    }

    func testOversizedRadiiClampIndependentlyToTheShorterHalfExtent() async {
        let path = UnevenRoundedRectangle(
            topLeadingRadius: 100, bottomLeadingRadius: 9,
            bottomTrailingRadius: .infinity, topTrailingRadius: 7, style: .circular
        )
        .path(in: Rect(x: 10, y: 20, width: 120, height: 40))

        // Arc order is top-right, bottom-right, bottom-left, then top-left.
        XCTAssertEqual(arcRadii(path), [7, 20, 9, 20])
        XCTAssertEqual(path.elements.first, .moveTo(Point(x: 30, y: 20)))
        XCTAssertEqual(path.elements.count, 10)
        assertAllCoordinatesFinite(path)
    }

    func testMutableNegativeAndNonfiniteRadiiUseTheExistingPathClamp() async {
        // Public fields can be changed after the initializer's zero clamp.
        var radii = RectangleCornerRadii()
        radii.topLeading = .nan
        radii.topTrailing = -3
        radii.bottomTrailing = .infinity
        radii.bottomLeading = -.infinity
        let path = UnevenRoundedRectangle(cornerRadii: radii, style: .circular)
            .path(in: Rect(x: 0, y: 0, width: 80, height: 40))

        // The uniform constructor's max(0, min(radius, halfExtent)) gives
        // zero for NaN/negative values and the extent cap for +infinity.
        XCTAssertEqual(arcRadii(path), [0, 20, 0, 0])
        XCTAssertTrue(path.contains(Point(x: 1, y: 1)))
        XCTAssertTrue(path.contains(Point(x: 79, y: 1)))
        XCTAssertTrue(path.contains(Point(x: 1, y: 39)))
        XCTAssertFalse(path.contains(Point(x: 79, y: 39)))
        assertAllCoordinatesFinite(path)
    }

    func testDegenerateBoundsPreserveTheExistingPathBuilderRepresentation() async {
        let rectangles = [
            Rect(x: 10, y: 20, width: 0, height: 80),
            Rect(x: 10, y: 20, width: 120, height: 0),
            Rect(x: 10, y: 20, width: 0, height: 0),
            Rect(x: 10, y: 20, width: -10, height: 30),
            Rect(x: 10, y: 20, width: 30, height: -10),
        ]
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 6, bottomLeadingRadius: 10,
            bottomTrailingRadius: 18, topTrailingRadius: 14, style: .circular)
        for rect in rectangles {
            let path = shape.path(in: rect)
            XCTAssertEqual(path, Path(roundedRect: rect, cornerRadius: 1))
            XCTAssertEqual(arcRadii(path), [0, 0, 0, 0])
            // Like the existing constructor, this records a closed, possibly
            // collapsed contour; it does not invent a new empty-path policy.
            XCTAssertEqual(path.elements.count, 10)
            XCTAssertEqual(path.elements.last, .close)
        }
    }

    func testNonfiniteBoundsPreserveUniformPathCoordinateBehavior() async {
        let rectangles = [
            Rect(x: .nan, y: 0, width: 120, height: 80),
            Rect(x: .infinity, y: -.infinity, width: 80, height: 40),
            Rect(x: 0, y: 0, width: .infinity, height: 40),
            Rect(x: 0, y: 0, width: .nan, height: 40),
            Rect(x: 0, y: 0, width: 40, height: .nan),
            Rect(x: 0, y: 0, width: -.infinity, height: 40),
            Rect(x: .greatestFiniteMagnitude, y: 0, width: .greatestFiniteMagnitude, height: 40),
        ]
        for rect in rectangles {
            let path = uniformShape(8).path(in: rect)
            assertEquivalentPathCoordinates(path, Path(roundedRect: rect, cornerRadius: 8))
            XCTAssertEqual(path.elements.count, 10)
        }
        // These assertions inspect values only. Invalid coordinates are not
        // sent to contains, trimming or either rasterizer in this test.
    }

    func testAnyShapePreservesTheFourCornerPublicPath() async {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 4, bottomLeadingRadius: 8,
            bottomTrailingRadius: 16, topTrailingRadius: 12, style: .circular)
        let rect = Rect(x: 15, y: 9, width: 120, height: 80)
        let path = AnyShape(AnyShape(shape)).path(in: rect)

        XCTAssertEqual(path, shape.path(in: rect))
        XCTAssertEqual(arcRadii(path), [12, 16, 8, 4])
        XCTAssertTrue(path.contains(Point(x: 18, y: 12)))
        XCTAssertFalse(path.contains(Point(x: 134, y: 88)))
    }

    func testExplicitPathTrimUsesTheUnequalCornerPerimeter() async throws {
        let rect = Rect(x: 10, y: 20, width: 120, height: 80)
        let path = UnevenRoundedRectangle(bottomTrailingRadius: 20, style: .circular).path(in: rect)
        let trimmed = path.trimmedPath(from: 0, to: 0.25)
        // Only one corner replaces two straight radii with a quarter circle.
        let perimeter = 2 * (120.0 + 80.0) - (2 - Double.pi / 2) * 20

        XCTAssertEqual(trimmed.elements.count, 2)
        XCTAssertEqual(trimmed.elements.first, .moveTo(Point(x: 10, y: 20)))
        guard case .lineTo(let end) = try XCTUnwrap(trimmed.elements.last) else {
            XCTFail("The first quarter ends on the top straight edge")
            return
        }
        XCTAssertEqual(end.x, 10 + perimeter / 4, accuracy: 1e-8)
        XCTAssertEqual(end.y, 20, accuracy: 1e-8)
        XCTAssertEqual(path.trimmedPath(from: 0, to: 1), path)
        XCTAssertTrue(path.trimmedPath(from: 0.5, to: 0.5).isEmpty)
    }

    func testCanvasPreservesThreeSquareCornersAndOneRoundedCorner() async throws {
        let result = canvasSnapshot(RectangleCornerRadii(bottomTrailing: 20))
        let surface = GPUIRawSceneRasterizer.rasterize(result.scene, size: Self.canvasSize)

        XCTAssertEqual(fillCommands(result).count, 1)
        for (x, y) in [(13, 13), (130, 13), (13, 90), (72, 52)] {
            try assertPixel(surface, x: x, y: y, painted: true)
        }
        try assertPixel(surface, x: 130, y: 90, painted: false)
        try assertPixel(surface, x: 4, y: 4, painted: false)
        // The retained Canvas recording must also carry the four actual radii.
        let command = try XCTUnwrap(fillCommands(result).first)
        XCTAssertEqual(renderArcRadii(command.path), [0, 20, 0, 0])
    }

    func testCanvasUsesFourUnequalRadiiAtActualResolvedBounds() async throws {
        let result = canvasSnapshot(
            RectangleCornerRadii(topLeading: 4, bottomLeading: 20, bottomTrailing: 28, topTrailing: 12))
        let surface = GPUIRawSceneRasterizer.rasterize(result.scene, size: Self.canvasSize)

        XCTAssertEqual(fillCommands(result).count, 1)
        let command = try XCTUnwrap(fillCommands(result).first)
        XCTAssertEqual(renderArcRadii(command.path), [12, 28, 20, 4])
        for (x, y) in [(14, 14), (126, 17), (20, 83), (119, 79), (72, 52)] {
            try assertPixel(surface, x: x, y: y, painted: true)
        }
        for (x, y) in [(12, 12), (130, 13), (126, 86), (14, 89), (4, 4)] {
            try assertPixel(surface, x: x, y: y, painted: false)
        }
    }

    func testContinuousStyleRetainsTheExistingCircularPathApproximation() async {
        let radii = RectangleCornerRadii(topLeading: 4, bottomLeading: 8, bottomTrailing: 16, topTrailing: 12)
        let rect = Rect(x: 10, y: 20, width: 120, height: 80)
        let continuous = UnevenRoundedRectangle(cornerRadii: radii, style: .continuous)
        let circular = UnevenRoundedRectangle(cornerRadii: radii, style: .circular)

        XCTAssertEqual(continuous.style, .continuous)
        XCTAssertEqual(continuous.path(in: rect), circular.path(in: rect))
        XCTAssertEqual(arcRadii(continuous.path(in: rect)), [12, 16, 8, 4])
    }

    private func uniformShape(_ radius: Double) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: radius, bottomLeadingRadius: radius,
            bottomTrailingRadius: radius, topTrailingRadius: radius, style: .circular)
    }

    private func arcRadii(_ path: Path) -> [Double] {
        path.elements.compactMap { element in
            guard case .arc(_, let radius, _, _, _) = element else { return nil }
            return radius
        }
    }

    private func renderArcRadii(_ path: RenderPath) -> [Double] {
        path.segments.compactMap { segment in
            guard case .arc(_, let radius, _, _, _) = segment else { return nil }
            return radius
        }
    }

    private func assertAllCoordinatesFinite(
        _ path: Path, file: StaticString = #filePath, line: UInt = #line
    ) {
        for element in path.elements {
            switch element {
            case .moveTo(let p), .lineTo(let p):
                XCTAssertTrue(p.x.isFinite && p.y.isFinite, file: file, line: line)
            case .arc(let center, let radius, let start, let end, _):
                XCTAssertTrue(
                    [center.x, center.y, radius, start, end].allSatisfy(\.isFinite), file: file, line: line)
            case .close: break
            default: XCTFail("The rounded path has only lines and circular arcs", file: file, line: line)
            }
        }
    }

    private func assertEquivalentPathCoordinates(
        _ actual: Path, _ expected: Path, file: StaticString = #filePath, line: UInt = #line
    ) {
        func scalar(_ actual: Double, _ expected: Double) {
            if expected.isNaN {
                XCTAssertTrue(actual.isNaN, file: file, line: line)
            } else {
                XCTAssertEqual(actual, expected, file: file, line: line)
            }
        }
        func point(_ actual: Point, _ expected: Point) {
            scalar(actual.x, expected.x)
            scalar(actual.y, expected.y)
        }
        XCTAssertEqual(actual.elements.count, expected.elements.count, file: file, line: line)
        for (a, b) in zip(actual.elements, expected.elements) {
            switch (a, b) {
            case (.moveTo(let a), .moveTo(let b)), (.lineTo(let a), .lineTo(let b)):
                point(a, b)
            case (
                .arc(let ac, let ar, let aStart, let aEnd, let aClockwise),
                .arc(let bc, let br, let bStart, let bEnd, let bClockwise)
            ):
                point(ac, bc)
                scalar(ar, br)
                scalar(aStart, bStart)
                scalar(aEnd, bEnd)
                XCTAssertEqual(aClockwise, bClockwise, file: file, line: line)
            case (.close, .close): break
            default: XCTFail("The constructors emitted different element cases", file: file, line: line)
            }
        }
    }

    private func canvasSnapshot(_ radii: RectangleCornerRadii) -> WinSwiftUIRenderSnapshot {
        let shape = UnevenRoundedRectangle(cornerRadii: radii, style: .circular)
        return WinSwiftUIRendererSnapshotter.snapshot(
            of: Canvas { context, size in
                let rect = Rect(x: 12, y: 12, width: size.width - 24, height: size.height - 24)
                context.fill(shape.path(in: rect), with: .color(Self.red))
            }
            .frame(width: 144, height: 104),
            size: Self.canvasSize, clearColor: .clear)
    }

    private func fillCommands(_ result: WinSwiftUIRenderSnapshot) -> [FillPathCommand] {
        result.frame.commands.compactMap { command in
            guard case .fillPath(let fill) = command else { return nil }
            return fill
        }
    }

    private func assertPixel(
        _ surface: BitmapSurface, x: Int, y: Int, painted: Bool,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let color = try XCTUnwrap(surface.colorAt(x: x, y: y), file: file, line: line)
        XCTAssertEqual(color.alpha, painted ? 1 : 0, accuracy: 1.0 / 255, file: file, line: line)
        if painted {
            XCTAssertEqual(color.red, 1, accuracy: 1.0 / 255, file: file, line: line)
            XCTAssertEqual(color.green, 0, accuracy: 1.0 / 255, file: file, line: line)
            XCTAssertEqual(color.blue, 0, accuracy: 1.0 / 255, file: file, line: line)
        }
    }
}
