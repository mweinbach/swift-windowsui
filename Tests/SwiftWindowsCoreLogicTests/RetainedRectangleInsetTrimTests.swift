import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Rectangle paths with ordered point insets, resolved before the outer trim.
/// These controls do not qualify other built-ins, nested trims, arbitrary
/// custom geometry, strokeBorder, content/clip shapes, or native fidelity.
@MainActor
final class RetainedRectangleInsetTrimTests: XCTestCase {
    private static let size = IntSize(width: 120, height: 40)
    private static let red = Color(red: 1, green: 0, blue: 0, alpha: 1)
    private static let green = Color(red: 0, green: 1, blue: 0, alpha: 1)
    private static let blue = Color(red: 0, green: 0, blue: 1, alpha: 1)

    private final class GeometryPayload {}

    private struct DescriptorShape: Shape, RetainedRectangleTrimGeometryProvider {
        let geometry: RetainedRectangleTrimGeometry
        var payload: GeometryPayload? = nil
        var onPath: () -> Void = {}

        var retainedRectangleTrimGeometry: RetainedRectangleTrimGeometry { geometry }

        func path(in rect: Rect) -> Path {
            onPath()
            return Path(rect)
        }
    }

    private struct ObservedRectangle: Shape {
        let observed: (Rect) -> Void

        func path(in rect: Rect) -> Path {
            observed(rect)
            return Path(rect)
        }
    }

    func testQuarterStrokeUsesPointInsetAndResolvedPaintBounds() async throws {
        let style = stroke(width: 4)
        let result = snapshot(
            Rectangle().inset(by: 10).trim(from: 0, to: 0.25).stroke(Self.blue, style: style)
                .frame(width: 120, height: 40))
        let owner = try pathOwner(result.runtime.root)
        XCTAssertEqual(owner.resolvedFrame, Rect(x: 0, y: 0, width: 120, height: 40))
        XCTAssertNotNil(owner.onLayoutWithNode)
        XCTAssertEqual(owner.borderStrokeStyle, style)
        // Paint112x32, point inset10 => rectangle92x12, perimeter208, quarter52.
        assertLines(
            try XCTUnwrap(owner.backgroundPath),
            [Point(x: 5.0 / 56, y: 5.0 / 16), Point(x: 31.0 / 56, y: 5.0 / 16)])
        assertLines(try strokeCommand(result.frame).path, [Point(x: 14, y: 14), Point(x: 66, y: 14)])
        assertPixels(result, [(30, 14, Self.blue), (62, 14, Self.blue), (70, 14, .clear), (30, 4, .clear)])
    }

    func testFullHalfAndEmptyInsetsHaveIndependentPositiveFillCoverage() async throws {
        let full = snapshot(Rectangle().inset(by: 10).trim().fill(Self.red).frame(width: 120, height: 40))
        let half = snapshot(
            Rectangle().inset(by: 10).trim(from: 0, to: 0.5).fill(Self.red).frame(width: 120, height: 40))
        let empty = snapshot(
            Rectangle().inset(by: 10).trim(from: 0.5, to: 0.5).fill(Self.red).frame(width: 120, height: 40))
        XCTAssertNotNil(try pathOwner(full.runtime.root).onLayoutWithNode)
        assertLines(
            try fillCommand(full.frame).path,
            [Point(x: 10, y: 10), Point(x: 110, y: 10), Point(x: 110, y: 30), Point(x: 10, y: 30)], closed: true)
        assertLines(
            try fillCommand(half.frame).path,
            [Point(x: 10, y: 10), Point(x: 110, y: 10), Point(x: 110, y: 30)])
        assertPixels(full, [(100, 15, Self.red), (20, 25, Self.red), (5, 15, .clear), (115, 15, .clear)])
        assertPixels(half, [(100, 15, Self.red), (20, 25, .clear), (5, 15, .clear)])
        try assertEmpty(empty)
    }

    func testNegativeInsetAndNegativeDerivedHeightPreserveRawRectangleEdges() async throws {
        let expanded = snapshot(
            Rectangle().inset(by: -2).trim(from: 0, to: 0.25).stroke(Self.blue, style: stroke(width: 4))
                .frame(width: 120, height: 40))
        // Paint112x32 expands to116x36; one quarter is76, with local origin(-2,-2).
        assertLines(try strokeCommand(expanded.frame).path, [Point(x: 2, y: 2), Point(x: 78, y: 2)])
        assertPixels(expanded, [(30, 2, Self.blue), (74, 2, Self.blue), (84, 2, .clear), (30, 14, .clear)])

        let reversed = snapshot(
            Rectangle().inset(by: 30).trim(from: 0, to: 0.25).stroke(Self.blue, style: stroke(width: 4))
                .frame(width: 120, height: 40))
        // Raw inset rectangle(30,30,52,-28): drawn perimeter160, one quarter40.
        // Clamping height to0 would instead stop at presented x60.
        assertLines(try strokeCommand(reversed.frame).path, [Point(x: 34, y: 34), Point(x: 74, y: 34)])
        assertPixels(reversed, [(40, 34, Self.blue), (70, 34, Self.blue), (80, 34, .clear), (40, 24, .clear)])
    }

    func testNestedInsetArithmeticKeepsOuterToInnerFloatingPointOrder() async throws {
        let large = 9_007_199_254_740_992.0
        let first = InsetShape(InsetShape(InsetShape(Rectangle(), amount: -large), amount: 1), amount: large)
        let reversed = InsetShape(InsetShape(InsetShape(Rectangle(), amount: large), amount: 1), amount: -large)
        let a = snapshot(
            first.trim(from: 0, to: 0.25).stroke(Self.blue, style: stroke(width: 4)).frame(width: 120, height: 40))
        let b = snapshot(
            reversed.trim(from: 0, to: 0.25).stroke(Self.blue, style: stroke(width: 4)).frame(width: 120, height: 40))
        // Binary64 [2^53,1,-2^53] => rect(0,0,110,30); its reversal =>(1,1,112,32).
        // The independently derived quarter lengths are70 and72 respectively.
        assertLines(try strokeCommand(a.frame).path, [Point(x: 4, y: 4), Point(x: 74, y: 4)])
        assertLines(try strokeCommand(b.frame).path, [Point(x: 5, y: 5), Point(x: 77, y: 5)])
        assertPixels(a, [(30, 4, Self.blue), (72, 4, Self.blue), (80, 4, .clear)])
        assertPixels(b, [(30, 5, Self.blue), (75, 5, Self.blue), (82, 5, .clear)])
    }

    func testAggregatingInsetOverloadAndExplicitNestingKeepTheirOwnArithmetic() async throws {
        let large = 9_007_199_254_740_992.0
        let combined = Rectangle().inset(by: large).inset(by: 1).inset(by: -large)
        let nested = InsetShape(InsetShape(InsetShape(Rectangle(), amount: large), amount: 1), amount: -large)
        XCTAssertEqual(resolvedRectangleTrimGeometry(for: combined).resolve(), .rectangle(insets: [0]))
        XCTAssertEqual(resolvedRectangleTrimGeometry(for: nested).resolve(), .rectangle(insets: [-large, 1, large]))
        let combinedResult = snapshot(
            combined.trim(from: 0, to: 0.25).stroke(Self.blue, style: stroke(width: 4)).frame(width: 120, height: 40))
        let nestedResult = snapshot(
            nested.trim(from: 0, to: 0.25).stroke(Self.blue, style: stroke(width: 4)).frame(width: 120, height: 40))
        assertLines(try strokeCommand(combinedResult.frame).path, [Point(x: 4, y: 4), Point(x: 76, y: 4)])
        assertLines(try strokeCommand(nestedResult.frame).path, [Point(x: 5, y: 5), Point(x: 77, y: 5)])
        let zeroFull = snapshot(combined.trim().fill(Self.red).frame(width: 120, height: 40))
        XCTAssertNotNil(try pathOwner(zeroFull.runtime.root).onLayoutWithNode)
        assertPixels(zeroFull, [(20, 10, Self.red), (110, 30, Self.red)])
    }

    func testDescriptorForestPreservesOrderCopiesAndAdmissionBoundaries() async throws {
        let limit = RetainedRectangleTrimGeometry.maximumInsetOperations
        XCTAssertEqual(limit, 65_536)
        var descriptor = RetainedRectangleTrimGeometry.rectangle
        var saved = RetainedRectangleTrimGeometry.unavailable
        let boundaries: Set<Int> = [3, 7, 8, limit - 1, limit]
        for value in 0..<limit {
            descriptor = descriptor.prependingInset(Double(value))
            let count = value + 1
            if count == 8 { saved = descriptor }
            if boundaries.contains(count) {
                guard case .rectangle(let insets) = descriptor.resolve() else {
                    return XCTFail("admitted descriptor rejected at \(count)")
                }
                XCTAssertEqual(insets.count, count)
                XCTAssertTrue(insets.enumerated().allSatisfy { $0.element == Double(count - 1 - $0.offset) })
            }
        }
        XCTAssertEqual(saved.resolve(), .rectangle(insets: [7, 6, 5, 4, 3, 2, 1, 0]))
        XCTAssertEqual(descriptor.prependingInset(0).resolve(), .rejected)
        guard case .rectangle(let unchanged) = descriptor.resolve() else { return XCTFail("copy was mutated") }
        XCTAssertEqual(unchanged.count, limit)
        XCTAssertEqual(unchanged.first, Double(limit - 1))
        XCTAssertEqual(unchanged.last, 0)
        let erased = AnyShape(AnyShape(DescriptorShape(geometry: saved)))
        XCTAssertEqual(resolvedRectangleTrimGeometry(for: erased).resolve(), saved.resolve())
    }

    func testRejectedDescriptorStaysRejectedThroughErasureWithoutCallingAuthoredPath() async throws {
        var descriptor = RetainedRectangleTrimGeometry.rectangle
        for _ in 0..<RetainedRectangleTrimGeometry.maximumInsetOperations {
            descriptor = descriptor.prependingInset(0)
        }
        var calls = 0
        let admitted = DescriptorShape(geometry: descriptor, onPath: { calls += 1 })
        let full = snapshot(AnyShape(admitted).trim().fill(Self.red).frame(width: 120, height: 40))
        XCTAssertEqual(calls, 0)
        assertPixels(full, [(20, 10, Self.red), (110, 30, Self.red)])
        let rejected = descriptor.prependingInset(0)
        XCTAssertEqual(rejected.prependingInset(-1).resolve(), .rejected)
        let shape = AnyShape(
            AnyShape(InsetShape(DescriptorShape(geometry: rejected, onPath: { calls += 1 }), amount: 0)))
        XCTAssertEqual(resolvedRectangleTrimGeometry(for: shape).resolve(), .rejected)
        for end in [0.25, 1.0] {
            try assertEmpty(snapshot(shape.trim(from: 0, to: end).fill(Self.red).frame(width: 120, height: 40)))
        }
        XCTAssertEqual(calls, 0, "recognized rejection must never call the authored fallback path")
    }

    func testNonfiniteInsetAndIntermediateOverflowCannotFallBackToARectangle() async throws {
        for amount in [Double.nan, .infinity, -.infinity, .greatestFiniteMagnitude] {
            let shape = AnyShape(AnyShape(Rectangle().inset(by: amount)))
            for end in [0.25, 1.0] {
                try assertEmpty(snapshot(shape.trim(from: 0, to: end).fill(Self.red).frame(width: 120, height: 40)))
            }
        }
        let huge = Double.greatestFiniteMagnitude
        let cancellation = InsetShape(InsetShape(Rectangle(), amount: -huge), amount: huge)
        try assertEmpty(snapshot(cancellation.trim().fill(Self.red).frame(width: 120, height: 40)))
        try assertEmpty(snapshot(cancellation.trim(from: 0, to: 0.25).fill(Self.red).frame(width: 120, height: 40)))
        for (from, to) in [(0.8, 0.2), (-0.1, 0.5), (0.0, 1.1), (Double.nan, 0.5), (0.0, Double.infinity)] {
            try assertEmpty(
                snapshot(
                    Rectangle().inset(by: 10).trim(from: from, to: to).fill(Self.red).frame(width: 120, height: 40)))
        }
    }

    func testResizeCollapsedPaintAndRecoveryReuseTheSameOwner() async throws {
        let runtime = RetainedViewRuntime(clearColor: .clear, root: ViewNode())
        var size = Self.size
        runtime.setRootSize(size)
        let host = ComponentHost(runtime: runtime)
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: Double(size.width), height: Double(size.height)) }, invalidateHandler: {})
        host.setComponents {
            [
                Rectangle().inset(by: 10).trim(from: 0, to: 0.25).stroke(Self.blue, style: self.stroke(width: 4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity).makeComponent(context: context)
            ]
        }
        let first = capture(runtime, time: 0)
        let owner = try pathOwner(runtime.root)
        assertLines(try strokeCommand(first.frame).path, [Point(x: 14, y: 14), Point(x: 66, y: 14)])
        size = IntSize(width: 160, height: 40)
        runtime.setRootSize(size)
        let wide = capture(runtime, size: size, time: 1)
        XCTAssertTrue(try pathOwner(runtime.root) === owner)
        assertLines(try strokeCommand(wide.frame).path, [Point(x: 14, y: 14), Point(x: 86, y: 14)])
        assertPixels(wide, [(30, 14, Self.blue), (82, 14, Self.blue), (92, 14, .clear)])
        size = IntSize(width: 6, height: 40)
        runtime.setRootSize(size)
        try assertEmpty(capture(runtime, size: size, time: 2))
        XCTAssertTrue(try pathOwner(runtime.root) === owner)
        size = IntSize(width: 40, height: 120)
        runtime.setRootSize(size)
        let tall = capture(runtime, size: size, time: 3)
        assertLines(
            try strokeCommand(tall.frame).path,
            [Point(x: 14, y: 14), Point(x: 26, y: 14), Point(x: 26, y: 54)])
        assertPixels(tall, [(20, 14, Self.blue), (26, 44, Self.blue), (26, 64, .clear)])
        size = Self.size
        runtime.setRootSize(size)
        let restored = capture(runtime, time: 4)
        XCTAssertTrue(try pathOwner(runtime.root) === owner)
        assertLines(try strokeCommand(restored.frame).path, [Point(x: 14, y: 14), Point(x: 66, y: 14)])
        assertPixels(restored, [(30, 14, Self.blue), (70, 14, .clear)])
    }

    func testLiveBorderMutationRecomputesGeometryWithoutRestoringPaint() async throws {
        let style = stroke(width: 4)
        let result = snapshot(
            Rectangle().inset(by: 10).trim(from: 0, to: 0.25).stroke(Self.blue, style: style)
                .fill(Self.red, style: FillStyle(eoFill: true)).frame(width: 120, height: 40))
        let owner = try pathOwner(result.runtime.root)
        owner.borderWidth = 8
        owner.borderColor = Self.green
        XCTAssertTrue(result.runtime.hasPendingLayout)
        let changed = capture(result.runtime, time: 1)
        XCTAssertTrue(try pathOwner(result.runtime.root) === owner)
        XCTAssertEqual(owner.borderWidth, 8)
        XCTAssertEqual(owner.borderColor, Self.green)
        XCTAssertEqual(owner.borderStrokeStyle, style)
        XCTAssertEqual(owner.backgroundColor, Self.red)
        XCTAssertEqual(owner.clipFillStyle, RetainedClipFillStyle(eoFill: true))
        // Paint104x24, inset84x4, perimeter176, quarter44, plus border origin8.
        assertLines(try strokeCommand(changed.frame).path, [Point(x: 18, y: 18), Point(x: 62, y: 18)])
        XCTAssertEqual(try strokeCommand(changed.frame).style, style)
        assertPixels(changed, [(30, 18, Self.green), (60, 18, Self.green), (70, 18, .clear), (30, 14, .clear)])
    }

    func testOriginAndDisplayScaleApplyOnlyAtPresentation() async throws {
        let size = IntSize(width: 140, height: 80)
        for scale in [1.0, 1.25, 2.0] {
            let result = snapshot(
                Rectangle().inset(by: 10).trim(from: 0, to: 0.25).stroke(Self.blue, style: stroke(width: 4))
                    .padding(EdgeInsets(top: 20, leading: 10, bottom: 20, trailing: 10)).frame(width: 140, height: 80),
                size: size, displayScale: scale)
            let owner = try pathOwner(result.runtime.root)
            XCTAssertEqual(owner.resolvedFrame, Rect(x: 10, y: 20, width: 120, height: 40))
            assertLines(
                try XCTUnwrap(owner.backgroundPath),
                [Point(x: 5.0 / 56, y: 5.0 / 16), Point(x: 31.0 / 56, y: 5.0 / 16)])
            assertLines(try strokeCommand(result.frame).path, [Point(x: 24, y: 34), Point(x: 76, y: 34)])
            XCTAssertTrue(result.scene.validate().isEmpty)
            let pixels = IntSize(width: Int32(140 * scale), height: Int32(80 * scale))
            let bitmap = GPUIRawSceneRasterizer.rasterize(result.scene, size: pixels)
            assertPixel(bitmap, x: Int(40 * scale), y: Int(34 * scale), color: Self.blue)
            assertPixel(bitmap, x: Int(82 * scale), y: Int(34 * scale), color: .clear)
            assertPixel(bitmap, x: Int(40 * scale), y: Int(24 * scale), color: .clear)
        }
    }

    func testErasureBeforeTrimKeepsPointInsetGeometry() async throws {
        let shape = AnyShape(AnyShape(Rectangle().inset(by: 10)))
        XCTAssertEqual(resolvedRectangleTrimGeometry(for: shape).resolve(), .rectangle(insets: [10]))
        let result = snapshot(
            shape.trim(from: 0, to: 0.25).stroke(Self.blue, style: stroke(width: 4)).frame(width: 120, height: 40))
        assertLines(try strokeCommand(result.frame).path, [Point(x: 14, y: 14), Point(x: 66, y: 14)])
        assertPixels(result, [(30, 14, Self.blue), (70, 14, .clear)])
    }

    func testErasureAroundTrimKeepsPassivePaintAndActiveOuterReplacement() async throws {
        let style = stroke(width: 4)
        let gradient = LinearGradient(
            colors: [Self.red, Self.green], startPoint: .topLeading, endPoint: .bottomTrailing)
        let inner = Rectangle().inset(by: 10).trim(from: 0, to: 0.5).stroke(Self.blue, style: style)
            .fill(gradient, style: FillStyle(eoFill: true))
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
            try fillCommand(passive.frame).path,
            [Point(x: 14, y: 14), Point(x: 106, y: 14), Point(x: 106, y: 26)])
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
        assertLines(
            try fillCommand(outer.frame).path,
            [Point(x: 10, y: 10), Point(x: 110, y: 10), Point(x: 110, y: 30)])
        assertWrappersClear(outer.runtime.root, owner: outerOwner)
        assertPixels(outer, [(100, 15, Self.green), (20, 25, .clear), (5, 15, .clear)])
    }

    func testFullPartialEmptyAndFullReconciliationKeepResolvedInset() async throws {
        let runtime = RetainedViewRuntime(clearColor: .clear, root: ViewNode())
        runtime.setRootSize(Self.size)
        let host = ComponentHost(runtime: runtime)
        let context = ViewBuildContext(canvasSizeProvider: { Size(width: 120, height: 40) }, invalidateHandler: {})
        var end = 1.0
        host.setComponents {
            [
                Rectangle().inset(by: 10).trim(from: 0, to: end).fill(Self.red).frame(width: 120, height: 40)
                    .makeComponent(context: context)
            ]
        }
        var result = capture(runtime, time: 0)
        let retained = try pathOwner(runtime.root)
        assertPixels(result, [(100, 15, Self.red), (20, 25, Self.red), (5, 15, .clear)])
        for (index, fraction) in [0.5, 0.0, 1.0].enumerated() {
            end = fraction
            host.reload()
            result = capture(runtime, time: Double(index + 1))
            let owner = try pathOwner(runtime.root)
            XCTAssertTrue(owner === retained)
            XCTAssertNotNil(owner.onLayoutWithNode, "full range must still resolve point insets")
            XCTAssertEqual(owner.backgroundColor, Self.red)
            if fraction == 0 {
                try assertEmpty(result)
            } else if fraction == 0.5 {
                assertLines(
                    try fillCommand(result.frame).path,
                    [Point(x: 10, y: 10), Point(x: 110, y: 10), Point(x: 110, y: 30)])
                assertPixels(result, [(100, 15, Self.red), (20, 25, .clear)])
            } else {
                assertLines(
                    try fillCommand(result.frame).path,
                    [Point(x: 10, y: 10), Point(x: 110, y: 10), Point(x: 110, y: 30), Point(x: 10, y: 30)], closed: true
                )
                assertPixels(result, [(100, 15, Self.red), (20, 25, Self.red), (5, 15, .clear)])
            }
        }
        _ = runtime.renderFrame(at: 99)
        XCTAssertTrue(try pathOwner(runtime.root) === retained)
        XCTAssertEqual(retained.backgroundPath?.segments.last, .close)
    }

    func testRecognizedGeometryReleasesAuthoredShapeAndContextBeforeLayout() async throws {
        weak var payload: GeometryPayload?
        var calls = 0
        let component = makeDescriptorComponent(onPath: { calls += 1 }, expose: { payload = $0 })
        XCTAssertNil(payload, "a component must retain only scalar geometry, not the original shape or context")
        XCTAssertEqual(calls, 0)
        let runtime = RetainedViewRuntime(clearColor: .clear, root: ViewNode())
        runtime.setRootSize(Self.size)
        let host = ComponentHost(runtime: runtime)
        host.setComponents { [component] }
        let first = capture(runtime, time: 0)
        assertLines(try strokeCommand(first.frame).path, [Point(x: 14, y: 14), Point(x: 66, y: 14)])
        runtime.setRootSize(IntSize(width: 160, height: 40))
        let wide = capture(runtime, size: IntSize(width: 160, height: 40), time: 1)
        assertLines(try strokeCommand(wide.frame).path, [Point(x: 14, y: 14), Point(x: 86, y: 14)])
        XCTAssertEqual(calls, 0)
        XCTAssertNil(payload)
    }

    func testPlainAndUnknownFullRangeKeepTheOldConstructionRoute() async throws {
        let plain = snapshot(Rectangle().trim().fill(Self.red).frame(width: 120, height: 40))
        XCTAssertNil(try pathOwner(plain.runtime.root).onLayoutWithNode)
        var rectangles: [Rect] = []
        let unknown = snapshot(
            ObservedRectangle { rectangles.append($0) }.trim().fill(Self.red).frame(width: 120, height: 40))
        XCTAssertEqual(rectangles, [Rect(x: 0, y: 0, width: 1, height: 1)])
        XCTAssertNil(try pathOwner(unknown.runtime.root).onLayoutWithNode)
        _ = unknown.runtime.renderFrame(at: 1)
        XCTAssertEqual(rectangles.count, 1)
        assertPixels(unknown, [(10, 10, Self.red), (110, 30, Self.red)])
    }

    func testUnknownInsetContentRemainsUnavailableWithoutNewAuthoredCalls() async throws {
        var rectangles: [Rect] = []
        let shape = InsetShape(ObservedRectangle { rectangles.append($0) }, amount: 10)
        XCTAssertEqual(resolvedRectangleTrimGeometry(for: shape).resolve(), .unavailable)
        XCTAssertEqual(resolvedRectangleTrimGeometry(for: AnyShape(shape)).resolve(), .unavailable)
        XCTAssertEqual(RetainedRectangleTrimGeometry.unavailable.prependingInset(.infinity).resolve(), .unavailable)
        XCTAssertTrue(rectangles.isEmpty)
        let result = snapshot(
            shape.trim(from: 0, to: 0.25).stroke(Self.blue, style: stroke(width: 4)).frame(width: 120, height: 40))
        XCTAssertEqual(rectangles, [Rect(x: 10, y: 10, width: -19, height: -19)])
        _ = result.runtime.renderFrame(at: 1)
        XCTAssertEqual(rectangles.count, 1)
        // Do not forward geometry through an inner trim while losing its fractions.
        XCTAssertEqual(resolvedRectangleTrimGeometry(for: Rectangle().trim(from: 0, to: 0.25)).resolve(), .unavailable)
        XCTAssertEqual(resolvedRectangleTrimGeometry(for: RoundedRectangle(cornerRadius: 10)).resolve(), .unavailable)
        XCTAssertEqual(
            resolvedRectangleTrimGeometry(for: Path(Rect(x: 10, y: 10, width: 20, height: 10))).resolve(), .unavailable)
    }

    func testFiniteFieldsWithOverflowingExtentsRejectWholeGeometry() async throws {
        let huge = Double.greatestFiniteMagnitude
        XCTAssertNil(RetainedRectangleTrimGeometry.path(in: Rect(x: huge, y: 0, width: huge, height: 1), insets: []))
        XCTAssertNil(RetainedRectangleTrimGeometry.path(in: Rect(x: 0, y: huge, width: 1, height: huge), insets: []))
        XCTAssertNil(
            RetainedRectangleTrimGeometry.path(in: Rect(x: 0, y: 0, width: 112, height: 32), insets: [huge, -huge]))
        XCTAssertNil(
            RetainedRectangleTrimGeometry.path(
                in: Rect(x: 0, y: 0, width: 112, height: 32),
                insets: Array(repeating: 0, count: RetainedRectangleTrimGeometry.maximumInsetOperations + 1)))
    }

    @inline(never)
    private func makeDescriptorComponent(onPath: @escaping () -> Void, expose: (GeometryPayload) -> Void) -> Component {
        let payload = GeometryPayload()
        expose(payload)
        let context = ViewBuildContext(
            canvasSizeProvider: { [payload] in withExtendedLifetime(payload) { Size(width: 120, height: 40) } },
            invalidateHandler: { [payload] in withExtendedLifetime(payload) {} })
        let shape = DescriptorShape(geometry: .rectangle.prependingInset(10), payload: payload, onPath: onPath)
        return AnyShape(AnyShape(shape)).trim(from: 0, to: 0.25).stroke(Self.blue, style: stroke(width: 4))
            .makeComponent(context: context)
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
        XCTAssertEqual(owners.count, 1, "empty geometry must keep its owner", file: file, line: line)
        let owner = try XCTUnwrap(owners.first, file: file, line: line)
        XCTAssertTrue(owner.children.isEmpty, file: file, line: line)
        return owner
    }

    private func strokeCommand(_ frame: RenderFrame, file: StaticString = #filePath, line: UInt = #line) throws
        -> StrokePathCommand
    {
        let paths = frame.commands.compactMap { command -> StrokePathCommand? in
            guard case .strokePath(let path) = command else { return nil }
            return path
        }
        XCTAssertEqual(paths.count, 1, file: file, line: line)
        return try XCTUnwrap(paths.first, file: file, line: line)
    }

    private func fillCommand(_ frame: RenderFrame, file: StaticString = #filePath, line: UInt = #line) throws
        -> FillPathCommand
    {
        let paths = frame.commands.compactMap { command -> FillPathCommand? in
            guard case .fillPath(let path) = command else { return nil }
            return path
        }
        XCTAssertEqual(paths.count, 1, file: file, line: line)
        return try XCTUnwrap(paths.first, file: file, line: line)
    }

    private func assertLines(
        _ path: RenderPath, _ points: [Point], closed: Bool = false, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(path.segments.count, points.count + (closed ? 1 : 0), file: file, line: line)
        for (index, pair) in zip(path.segments, points).enumerated() {
            let actual: Point
            switch pair.0 {
            case .moveTo(let point) where index == 0: actual = point
            case .lineTo(let point) where index > 0: actual = point
            default:
                XCTFail("Expected move then straight edges, not \(pair.0)", file: file, line: line)
                continue
            }
            XCTAssertTrue(actual.x.isFinite && actual.y.isFinite, file: file, line: line)
            XCTAssertEqual(actual.x, pair.1.x, accuracy: 1e-9, file: file, line: line)
            XCTAssertEqual(actual.y, pair.1.y, accuracy: 1e-9, file: file, line: line)
        }
        if closed { XCTAssertEqual(path.segments.last, .close, file: file, line: line) }
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
        _ result: WinSwiftUIRenderSnapshot, _ probes: [(Int, Int, Color)], file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(result.displayScale, 1, file: file, line: line)
        XCTAssertTrue(probes.contains { $0.2.alpha > 0 }, "positive coverage is required", file: file, line: line)
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
                bitmap.pixels.allSatisfy { $0 == 0 }, "no stale paint or rectangle fallback", file: file, line: line)
        }
    }

    private func assertPixel(
        _ bitmap: BitmapSurface, x: Int, y: Int, color: Color, file: StaticString = #filePath, line: UInt = #line
    ) {
        guard x >= 0, y >= 0, x < Int(bitmap.width), y < Int(bitmap.height) else {
            return XCTFail("Pixel outside the raster", file: file, line: line)
        }
        let offset = y * Int(bitmap.bytesPerRow) + x * 4
        guard offset + 4 <= bitmap.pixels.count else {
            return XCTFail("Pixel outside the buffer", file: file, line: line)
        }
        let expected = [color.blue, color.green, color.red, color.alpha].map { UInt8(($0 * 255).rounded()) }
        XCTAssertEqual(
            Array(bitmap.pixels[offset..<(offset + 4)]), expected, "BGRA at (\(x),\(y))", file: file, line: line)
    }
}
