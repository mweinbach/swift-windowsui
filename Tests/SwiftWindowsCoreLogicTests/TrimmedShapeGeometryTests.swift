import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Static trimming of construction-time retained geometry. These tests do not
/// qualify bounds-dependent/nested/inset geometry, clip/content shapes,
/// animatable fractions, arbitrary transforms, or native rendering parity.
@MainActor
final class TrimmedShapeGeometryTests: XCTestCase {
    private static let size = IntSize(width: 120, height: 40)
    private static let red = Color(red: 1, green: 0, blue: 0, alpha: 1)
    private static let green = Color(red: 0, green: 1, blue: 0, alpha: 1)
    private static let blue = Color(red: 0, green: 0, blue: 1, alpha: 1)

    private struct ObservedRectangle: Shape {
        let observed: (Rect) -> Void

        func path(in rect: Rect) -> Path {
            observed(rect)
            return Path(rect)
        }
    }

    private struct SymmetricCurve: Shape {
        func path(in rect: Rect) -> Path {
            Path(elements: [
                .moveTo(Point(x: rect.minX, y: rect.minY)),
                .cubicCurveTo(
                    control1: Point(x: rect.minX, y: rect.maxY),
                    control2: Point(x: rect.maxX, y: rect.maxY), end: Point(x: rect.maxX, y: rect.minY)),
            ])
        }
    }

    private struct UnboundedArc: Shape {
        func path(in rect: Rect) -> Path {
            Path(elements: [
                .moveTo(.zero),
                .arc(center: .zero, radius: 1e100, startAngle: 0, endAngle: 100, clockwise: false),
            ])
        }
    }

    func testPublicShapePathTrimsTheSuppliedRectangle() async throws {
        var rectangles: [Rect] = []
        let shape = ObservedRectangle { rectangles.append($0) }.trim(from: 0, to: 0.25)
        let rect = Rect(x: 10, y: 20, width: 120, height: 40)
        let path = shape.path(in: rect)
        XCTAssertEqual(rectangles, [rect])
        assertLines(RenderPath(path: path), [Point(x: 10, y: 20), Point(x: 90, y: 20)])
    }

    func testQuarterStrokeUsesResolvedNonSquareInnerPaintPerimeter() async throws {
        let style = stroke(width: 4)
        let result = snapshot(
            Rectangle().trim(from: 0, to: 0.25).stroke(Self.blue, style: style).frame(width: 120, height: 40))
        let owner = try pathOwner(result.runtime.root)
        XCTAssertEqual(owner.resolvedFrame, Rect(x: 0, y: 0, width: 120, height: 40))
        XCTAssertNotNil(owner.onLayoutWithNode)
        assertLines(try XCTUnwrap(owner.backgroundPath), [.zero, Point(x: 9.0 / 14, y: 0)])
        // Inner size 112x32: perimeter 288, one quarter 72, origin (4,4).
        assertLines(try strokeCommand(result.frame).path, [Point(x: 4, y: 4), Point(x: 76, y: 4)])
        XCTAssertEqual(try strokeCommand(result.frame).style, style)
        XCTAssertEqual(owner.borderStrokeStyle, style)
        assertPixels(result, probes: [(20, 3, Self.blue), (78, 3, .clear), (112, 3, .clear), (20, 35, .clear)])
    }

    func testTallRectangleQuarterCrossesTheCornerAtTheRightDistance() async throws {
        let size = IntSize(width: 40, height: 120)
        let result = snapshot(
            Rectangle().trim(from: 0, to: 0.25).stroke(Self.blue, style: stroke(width: 4)).frame(
                width: 40, height: 120),
            size: size)
        let owner = try pathOwner(result.runtime.root)
        assertLines(try XCTUnwrap(owner.backgroundPath), [.zero, Point(x: 1, y: 0), Point(x: 1, y: 5.0 / 14)])
        assertLines(try strokeCommand(result.frame).path, [Point(x: 4, y: 4), Point(x: 36, y: 4), Point(x: 36, y: 44)])
        assertPixels(result, probes: [(20, 3, Self.blue), (35, 30, Self.blue), (35, 60, .clear), (3, 30, .clear)])
    }

    func testPartialCurveKeepsBezierControlsAndVisibleOpenStroke() async throws {
        let result = snapshot(
            SymmetricCurve().trim(from: 0, to: 0.5).stroke(Self.blue, style: stroke(width: 4)).frame(
                width: 120, height: 40))
        let owner = try pathOwner(result.runtime.root)
        assertCubic(
            try XCTUnwrap(owner.backgroundPath), start: .zero,
            first: Point(x: 0, y: 0.5), second: Point(x: 0.25, y: 0.75), end: Point(x: 0.5, y: 0.75))
        assertCubic(
            try strokeCommand(result.frame).path, start: Point(x: 4, y: 4),
            first: Point(x: 4, y: 20), second: Point(x: 32, y: 28), end: Point(x: 60, y: 28))
        assertPixels(result, probes: [(58, 27, Self.blue), (64, 27, .clear), (80, 20, .clear)])
    }

    func testFullPartialAndEmptyFillsHaveDistinctPositiveCoverage() async throws {
        let full = snapshot(Rectangle().trim(from: 0, to: 1).fill(Self.red).frame(width: 120, height: 40))
        let partial = snapshot(Rectangle().trim(from: 0, to: 0.5).fill(Self.red).frame(width: 120, height: 40))
        let empty = snapshot(Rectangle().trim(from: 0.5, to: 0.5).fill(Self.red).frame(width: 120, height: 40))
        XCTAssertNil(try pathOwner(full.runtime.root).onLayoutWithNode)
        XCTAssertEqual(try pathOwner(full.runtime.root).backgroundPath?.segments.last, .close)
        assertLines(try fillCommand(partial.frame).path, [.zero, Point(x: 120, y: 0), Point(x: 120, y: 40)])
        assertPixels(full, probes: [(100, 5, Self.red), (10, 30, Self.red)])
        assertPixels(partial, probes: [(100, 5, Self.red), (10, 30, .clear)])
        try assertEmpty(empty)
    }

    func testLayoutAndReconciliationDoNotCallAuthoredPathAgain() async throws {
        let runtime = RetainedViewRuntime(clearColor: .clear, root: ViewNode())
        runtime.setRootSize(Self.size)
        let host = ComponentHost(runtime: runtime)
        let context = ViewBuildContext(canvasSizeProvider: { Size(width: 120, height: 40) }, invalidateHandler: {})
        var end = 0.25
        var rectangles: [Rect] = []
        host.setComponents {
            [
                ObservedRectangle { rectangles.append($0) }.trim(from: 0, to: end)
                    .stroke(Self.blue, style: self.stroke(width: 4)).frame(width: 120, height: 40)
                    .makeComponent(context: context)
            ]
        }
        XCTAssertEqual(rectangles, [Rect(x: 0, y: 0, width: 1, height: 1)])
        var result = capture(runtime, time: 0)
        let retained = try pathOwner(runtime.root)
        XCTAssertEqual(rectangles.count, 1)
        assertLines(try strokeCommand(result.frame).path, [Point(x: 4, y: 4), Point(x: 76, y: 4)])

        for (index, fraction) in [0.5, 1.0, 0.25, 0.0, 1.0].enumerated() {
            end = fraction
            host.reload()
            let callsAfterConstruction = rectangles.count
            XCTAssertEqual(callsAfterConstruction, index + 2)
            result = capture(runtime, time: Double(index + 1))
            let owner = try pathOwner(runtime.root)
            XCTAssertTrue(owner === retained, "the geometry receiver must update the reused leaf")
            XCTAssertEqual(rectangles.count, callsAfterConstruction, "layout must not call authored Shape.path")
            XCTAssertEqual(owner.borderWidth, 4)
            XCTAssertEqual(owner.borderColor, Self.blue)
            XCTAssertEqual(owner.borderStrokeStyle, stroke(width: 4))
            if fraction == 1 {
                XCTAssertNil(owner.onLayoutWithNode, "full range must remove the old trim receiver")
                XCTAssertEqual(owner.backgroundPath?.segments.count, 5)
                XCTAssertEqual(owner.backgroundPath?.segments.last, .close)
                assertPixels(result, probes: [(20, 3, Self.blue), (20, 35, Self.blue), (50, 20, .clear)])
            } else {
                XCTAssertNotNil(owner.onLayoutWithNode)
                if fraction == 0 {
                    try assertEmpty(result)
                } else if fraction == 0.5 {
                    assertLines(
                        try strokeCommand(result.frame).path,
                        [
                            Point(x: 4, y: 4), Point(x: 116, y: 4), Point(x: 116, y: 36),
                        ])
                } else {
                    assertLines(try strokeCommand(result.frame).path, [Point(x: 4, y: 4), Point(x: 76, y: 4)])
                }
            }
        }
        let count = rectangles.count
        _ = runtime.renderFrame(at: 99)
        XCTAssertEqual(rectangles.count, count)
    }

    func testLiveBorderWidthRecomputesGeometryWithoutResettingPaint() async throws {
        let result = snapshot(
            Rectangle().trim(from: 0, to: 0.25).stroke(Self.blue, style: stroke(width: 4)).frame(width: 120, height: 40)
        )
        let owner = try pathOwner(result.runtime.root)
        owner.borderWidth = 8
        owner.borderColor = Self.green
        XCTAssertTrue(result.runtime.hasPendingLayout)
        let updated = capture(result.runtime, time: 1)
        XCTAssertTrue(try pathOwner(updated.runtime.root) === owner)
        XCTAssertEqual(owner.borderWidth, 8)
        XCTAssertEqual(owner.borderColor, Self.green)
        XCTAssertEqual(owner.borderStrokeStyle, stroke(width: 4), "geometry must not rewrite authored style metadata")
        // Inner size 104x24, perimeter 256; quarter 64 plus x origin 8.
        assertLines(try strokeCommand(updated.frame).path, [Point(x: 8, y: 8), Point(x: 72, y: 8)])
        assertPixels(updated, probes: [(20, 7, Self.green), (80, 7, .clear), (20, 30, .clear)])
    }

    func testResizeAndCollapsedInnerRectKeepAnEmptyPathThenRestoreIt() async throws {
        let runtime = RetainedViewRuntime(clearColor: .clear, root: ViewNode())
        var size = Self.size
        runtime.setRootSize(size)
        let host = ComponentHost(runtime: runtime)
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: Double(size.width), height: Double(size.height)) }, invalidateHandler: {})
        host.setComponents {
            [
                Rectangle().trim(from: 0, to: 0.25).stroke(Self.blue, style: self.stroke(width: 4)).fill(Self.red)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).makeComponent(context: context)
            ]
        }
        let first = capture(runtime, time: 0)
        let retained = try pathOwner(runtime.root)
        assertLines(try strokeCommand(first.frame).path, [Point(x: 4, y: 4), Point(x: 76, y: 4)])
        size = IntSize(width: 6, height: 40)
        runtime.setRootSize(size)
        let collapsed = capture(runtime, size: size, time: 1)
        XCTAssertTrue(try pathOwner(runtime.root) === retained)
        XCTAssertEqual(retained.resolvedFrame, Rect(x: 0, y: 0, width: 6, height: 40))
        try assertEmpty(collapsed)
        size = IntSize(width: 40, height: 120)
        runtime.setRootSize(size)
        let tall = capture(runtime, size: size, time: 2)
        XCTAssertTrue(try pathOwner(runtime.root) === retained)
        assertLines(try strokeCommand(tall.frame).path, [Point(x: 4, y: 4), Point(x: 36, y: 4), Point(x: 36, y: 44)])
        size = Self.size
        runtime.setRootSize(size)
        let restored = capture(runtime, time: 3)
        XCTAssertTrue(try pathOwner(runtime.root) === retained)
        assertLines(try strokeCommand(restored.frame).path, [Point(x: 4, y: 4), Point(x: 76, y: 4)])
        XCTAssertEqual(retained.backgroundColor, Self.red)
        XCTAssertEqual(retained.borderColor, Self.blue)
        XCTAssertEqual(retained.borderStrokeStyle, stroke(width: 4))
        assertPixels(restored, probes: [(20, 3, Self.blue), (100, 3, .clear), (50, 20, .clear)])
    }

    func testPassiveErasurePreservesBundleAndOuterPaintUsesItsLiveInset() async throws {
        let gradient = LinearGradient(
            colors: [Self.red, Self.green], startPoint: .topLeading, endPoint: .bottomTrailing)
        let style = StrokeStyle(
            lineWidth: 4, dashPattern: [3, 2], dashOffset: 1.25, lineCap: .square, lineJoin: .bevel, miterLimit: 2.5)
        let inner = Rectangle().trim(from: 0, to: 0.5).stroke(Self.blue, style: style).fill(
            gradient, style: FillStyle(eoFill: true))
        let passive = snapshot(AnyShape(AnyShape(inner)).frame(width: 120, height: 40))
        let owner = try pathOwner(passive.runtime.root)
        XCTAssertEqual(owner.backgroundColor, Self.red)
        XCTAssertEqual(owner.backgroundGradient, .linear(.init(gradient)))
        XCTAssertEqual(owner.borderColor, Self.blue)
        XCTAssertNil(owner.borderGradient)
        XCTAssertEqual(owner.borderWidth, 4)
        XCTAssertEqual(owner.borderStrokeStyle, style)
        XCTAssertEqual(owner.clipFillStyle, RetainedClipFillStyle(eoFill: true))
        assertLines(
            try fillCommand(passive.frame).path, [Point(x: 4, y: 4), Point(x: 116, y: 4), Point(x: 116, y: 36)])
        assertWrappersClear(passive.runtime.root, owner: owner)

        let outer = snapshot(AnyShape(AnyShape(inner)).fill(Self.green).frame(width: 120, height: 40))
        let outerOwner = try pathOwner(outer.runtime.root)
        XCTAssertEqual(outerOwner.backgroundColor, Self.green)
        XCTAssertNil(outerOwner.backgroundGradient)
        XCTAssertEqual(outerOwner.borderColor, .clear)
        XCTAssertNil(outerOwner.borderGradient)
        XCTAssertEqual(outerOwner.borderWidth, 0)
        XCTAssertNil(outerOwner.borderStrokeStyle)
        XCTAssertNil(outerOwner.clipFillStyle)
        assertLines(try fillCommand(outer.frame).path, [.zero, Point(x: 120, y: 0), Point(x: 120, y: 40)])
        assertWrappersClear(outer.runtime.root, owner: outerOwner)
        assertPixels(outer, probes: [(100, 5, Self.green), (10, 30, .clear)])
    }

    func testLayoutOriginIsAppliedOnlyByPresentation() async throws {
        let size = IntSize(width: 140, height: 80)
        let result = snapshot(
            Rectangle().trim(from: 0, to: 0.25).stroke(Self.blue, style: stroke(width: 4))
                .padding(EdgeInsets(top: 20, leading: 10, bottom: 20, trailing: 10)).frame(width: 140, height: 80),
            size: size)
        let owner = try pathOwner(result.runtime.root)
        XCTAssertEqual(owner.resolvedFrame, Rect(x: 10, y: 20, width: 120, height: 40))
        assertLines(try XCTUnwrap(owner.backgroundPath), [.zero, Point(x: 9.0 / 14, y: 0)])
        assertLines(try strokeCommand(result.frame).path, [Point(x: 14, y: 24), Point(x: 86, y: 24)])
        assertPixels(result, probes: [(30, 23, Self.blue), (100, 23, .clear), (30, 43, .clear)])
    }

    func testDisplayScaleChangesPhysicalCoverageWithoutChangingTheTrimMetric() async throws {
        for scale in [1.0, 1.25, 2.0] {
            let result = snapshot(
                Rectangle().trim(from: 0, to: 0.25).stroke(Self.blue, style: stroke(width: 4)).frame(
                    width: 120, height: 40),
                displayScale: scale)
            assertLines(try strokeCommand(result.frame).path, [Point(x: 4, y: 4), Point(x: 76, y: 4)])
            let owner = try pathOwner(result.runtime.root)
            assertLines(try XCTUnwrap(owner.backgroundPath), [.zero, Point(x: 9.0 / 14, y: 0)])
            XCTAssertTrue(result.scene.validate().isEmpty)
            let pixelSize = IntSize(width: Int32(120 * scale), height: Int32(40 * scale))
            let bitmap = GPUIRawSceneRasterizer.rasterize(result.scene, size: pixelSize)
            assertPixel(bitmap, x: Int(20 * scale), y: Int(3 * scale), color: Self.blue)
            assertPixel(bitmap, x: Int(100 * scale), y: Int(3 * scale), color: .clear)
            assertPixel(bitmap, x: Int(20 * scale), y: Int(30 * scale), color: .clear)
        }
    }

    func testRejectedPartialInputCannotBecomeARectangularBackground() async throws {
        let invalidRange = snapshot(Rectangle().trim(from: 0.8, to: 0.2).fill(Self.red).frame(width: 120, height: 40))
        try assertEmpty(invalidRange)
        let excessiveArc = snapshot(UnboundedArc().trim(from: 0, to: 0.5).fill(Self.red).frame(width: 120, height: 40))
        try assertEmpty(excessiveArc)
    }

    private func stroke(width: Double) -> StrokeStyle {
        StrokeStyle(lineWidth: width, dashPattern: [], lineCap: .butt, lineJoin: .miter, miterLimit: 10)
    }

    private func snapshot<V: View>(_ view: V, size: IntSize = IntSize(width: 120, height: 40), displayScale: Double = 1)
        -> WinSwiftUIRenderSnapshot
    {
        WinSwiftUIRendererSnapshotter.snapshot(of: view, size: size, displayScale: displayScale, clearColor: .clear)
    }

    private func capture(_ runtime: RetainedViewRuntime, size: IntSize = IntSize(width: 120, height: 40), time: Double)
        -> WinSwiftUIRenderSnapshot
    {
        let scene = runtime.renderScene(at: time)
        let frame = runtime.renderFrame(at: time)
        return WinSwiftUIRenderSnapshot(runtime: runtime, frame: frame, scene: scene, size: size, displayScale: 1)
    }

    private func descendants(_ root: ViewNode) -> [ViewNode] {
        [root] + root.children.flatMap { descendants($0) }
    }

    private func pathOwner(_ root: ViewNode, file: StaticString = #filePath, line: UInt = #line) throws -> ViewNode {
        let owners = descendants(root).filter { $0.backgroundPath != nil }
        XCTAssertEqual(owners.count, 1, "empty geometry must keep a path owner", file: file, line: line)
        let owner = try XCTUnwrap(owners.first, file: file, line: line)
        XCTAssertTrue(owner.children.isEmpty, file: file, line: line)
        return owner
    }

    private func strokeCommand(_ frame: RenderFrame, file: StaticString = #filePath, line: UInt = #line) throws
        -> StrokePathCommand
    {
        let strokes = frame.commands.compactMap { command -> StrokePathCommand? in
            guard case .strokePath(let stroke) = command else { return nil }
            return stroke
        }
        XCTAssertEqual(strokes.count, 1, file: file, line: line)
        return try XCTUnwrap(strokes.first, file: file, line: line)
    }

    private func fillCommand(_ frame: RenderFrame, file: StaticString = #filePath, line: UInt = #line) throws
        -> FillPathCommand
    {
        let fills = frame.commands.compactMap { command -> FillPathCommand? in
            guard case .fillPath(let fill) = command else { return nil }
            return fill
        }
        XCTAssertEqual(fills.count, 1, file: file, line: line)
        return try XCTUnwrap(fills.first, file: file, line: line)
    }

    private func assertLines(
        _ path: RenderPath, _ points: [Point], file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(path.segments.count, points.count, file: file, line: line)
        for (index, pair) in zip(path.segments, points).enumerated() {
            let (segment, expected) = pair
            if index == 0, case .moveTo(let actual) = segment {
                assertPoint(actual, expected, file: file, line: line)
            } else if index > 0, case .lineTo(let actual) = segment {
                assertPoint(actual, expected, file: file, line: line)
            } else {
                XCTFail("Expected one move and open line segments, not \(segment)", file: file, line: line)
            }
        }
    }

    private func assertCubic(
        _ path: RenderPath, start: Point, first: Point, second: Point, end: Point,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(path.segments.count, 2, file: file, line: line)
        guard path.segments.count == 2, case .moveTo(let actualStart) = path.segments[0],
            case .cubicCurveTo(let actualFirst, let actualSecond, let actualEnd) = path.segments[1]
        else {
            XCTFail("Expected an open cubic, preserving its element type", file: file, line: line)
            return
        }
        assertPoint(actualStart, start, accuracy: 1e-5, file: file, line: line)
        assertPoint(actualFirst, first, accuracy: 1e-5, file: file, line: line)
        assertPoint(actualSecond, second, accuracy: 1e-5, file: file, line: line)
        assertPoint(actualEnd, end, accuracy: 1e-5, file: file, line: line)
    }

    private func assertPoint(
        _ actual: Point, _ expected: Point, accuracy: Double = 1e-9,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(actual.x.isFinite && actual.y.isFinite, file: file, line: line)
        XCTAssertEqual(actual.x, expected.x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: accuracy, file: file, line: line)
    }

    private func assertWrappersClear(
        _ root: ViewNode, owner: ViewNode, file: StaticString = #filePath, line: UInt = #line
    ) {
        for node in descendants(root) where node !== owner {
            XCTAssertTrue(node.backgroundColor == nil || node.backgroundColor == .clear, file: file, line: line)
            XCTAssertNil(node.backgroundGradient, file: file, line: line)
            XCTAssertEqual(node.borderColor, .clear, file: file, line: line)
            XCTAssertNil(node.borderGradient, file: file, line: line)
            XCTAssertEqual(node.borderWidth, 0, file: file, line: line)
            XCTAssertNil(node.borderStrokeStyle, file: file, line: line)
            XCTAssertNil(node.clipFillStyle, file: file, line: line)
        }
    }

    private func assertPixels(
        _ result: WinSwiftUIRenderSnapshot, probes: [(Int, Int, Color)], file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(result.displayScale, 1, file: file, line: line)
        XCTAssertTrue(
            probes.contains { $0.2.alpha > 0 }, "require independent positive coverage", file: file, line: line)
        XCTAssertTrue(result.scene.validate().isEmpty, file: file, line: line)
        for bitmap in [
            GPUIRawSceneRasterizer.rasterize(result.frame, size: result.size),
            GPUIRawSceneRasterizer.rasterize(result.scene, size: result.size),
        ] {
            for (x, y, color) in probes { assertPixel(bitmap, x: x, y: y, color: color, file: file, line: line) }
        }
    }

    private func assertEmpty(_ result: WinSwiftUIRenderSnapshot, file: StaticString = #filePath, line: UInt = #line)
        throws
    {
        let owner = try pathOwner(result.runtime.root, file: file, line: line)
        XCTAssertEqual(try XCTUnwrap(owner.backgroundPath, file: file, line: line).segments, [], file: file, line: line)
        XCTAssertTrue(result.scene.validate().isEmpty, file: file, line: line)
        for bitmap in [
            GPUIRawSceneRasterizer.rasterize(result.frame, size: result.size),
            GPUIRawSceneRasterizer.rasterize(result.scene, size: result.size),
        ] {
            XCTAssertTrue(
                bitmap.pixels.allSatisfy { $0 == 0 }, "no stale stroke or rectangle fallback", file: file, line: line)
        }
    }

    private func assertPixel(
        _ bitmap: BitmapSurface, x: Int, y: Int, color: Color, file: StaticString = #filePath, line: UInt = #line
    ) {
        guard x >= 0, y >= 0, x < Int(bitmap.width), y < Int(bitmap.height) else {
            XCTFail("Pixel probe outside the raster", file: file, line: line)
            return
        }
        let offset = y * Int(bitmap.bytesPerRow) + x * 4
        guard offset + 4 <= bitmap.pixels.count else {
            XCTFail("Pixel probe outside the byte buffer", file: file, line: line)
            return
        }
        let expected = [color.blue, color.green, color.red, color.alpha].map { UInt8(($0 * 255).rounded()) }
        XCTAssertEqual(
            Array(bitmap.pixels[offset..<(offset + 4)]), expected, "BGRA at (\(x),\(y))", file: file, line: line)
    }
}
