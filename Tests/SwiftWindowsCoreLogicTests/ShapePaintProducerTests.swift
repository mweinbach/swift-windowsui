import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

@MainActor
private final class ShapePaintHandlerLifetime {
    let onRelease: @MainActor () -> Void

    init(onRelease: @escaping @MainActor () -> Void) { self.onRelease = onRelease }

    isolated deinit { onRelease() }
}

/// Paint ownership regressions, not completion of trim or Arc geometry. Trim
/// fixtures use the full range; Arc assertions inspect real post-layout state
/// and emitted commands without treating blank matching images as evidence.
/// Generic path gradients keep their existing first-stop rendering fallback.
@MainActor
final class ShapePaintProducerTests: XCTestCase {
    private static let size = IntSize(width: 64, height: 64)
    private static let arcSize = IntSize(width: 16, height: 16)
    private static let red = Color(red: 1, green: 0, blue: 0, alpha: 1)
    private static let blue = Color(red: 0, green: 0, blue: 1, alpha: 1)
    private static let green = Color(red: 0, green: 1, blue: 0, alpha: 1)
    private static let halfRed = Color(red: 1, green: 0, blue: 0, alpha: 0.5)
    private static let evenOdd = FillStyle(eoFill: true)
    private static let nonZero = FillStyle(eoFill: false)
    private static let solidStroke = StrokeStyle(
        lineWidth: 4, dashPattern: [], lineCap: .round, lineJoin: .bevel, miterLimit: 3)
    private static let detailedStroke = StrokeStyle(
        lineWidth: 4, dashPattern: [3, 2], dashOffset: 1.25,
        lineCap: .square, lineJoin: .bevel, miterLimit: 2.5)

    private struct CompoundShape: InsettableShape {
        func path(in rect: Rect) -> Path {
            func point(_ x: Double, _ y: Double) -> Point {
                Point(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
            }
            var path = Path()
            for (lower, upper) in [(0.125, 0.875), (0.375, 0.625)] {
                path.moveTo(point(lower, lower))
                path.lineTo(point(upper, lower))
                path.lineTo(point(upper, upper))
                path.lineTo(point(lower, upper))
                path.close()
            }
            return path
        }
    }

    private struct AuthoredStyle: ShapeStyle {
        let retainedForegroundStyle: ForegroundStyle
    }

    private struct ExpectedPaint {
        var fill: Color = .clear
        var fillGradient: GradientType?
        var stroke: Color = .clear
        var strokeGradient: GradientType?
        var strokeStyle: StrokeStyle?
        var evenOdd: Bool?
    }

    private enum PaintMode: CaseIterable {
        case explicitEvenOdd, inheritedEvenOdd, explicitNonZero, gradient
        case combined, stroke, plainColor, inheritedDefault
    }

    private struct LayoutDelivery {
        let generation: Int
        let receiver: ObjectIdentifier
        let bounds: Rect
    }

    func testTrimmedExplicitAndInheritedFillReachPathOwner() async throws {
        // Keep the concrete type: erasing before calling fill would exercise
        // AnyShape's setters instead of the stored TrimmedShape paint.
        let trimmed = CompoundShape().trim(from: 0, to: 1)
        let linear = linearGradient()
        let gradientPaint = ExpectedPaint(
            fill: Self.red, fillGradient: .linear(.init(linear)), evenOdd: true)
        let cases: [(TrimmedShape<CompoundShape>, ForegroundStyle, ExpectedPaint)] = [
            (trimmed.fill(Self.red), .color(Self.blue), ExpectedPaint(fill: Self.red)),
            (
                trimmed.fill(Self.red, style: Self.nonZero), .color(Self.blue),
                ExpectedPaint(fill: Self.red, evenOdd: false)
            ),
            (
                trimmed.fill(Self.red, style: Self.evenOdd), .color(Self.blue),
                ExpectedPaint(fill: Self.red, evenOdd: true)
            ),
            (
                trimmed.fill(ForegroundStyle.color(Self.red), style: Self.evenOdd), .color(Self.blue),
                ExpectedPaint(fill: Self.red, evenOdd: true)
            ),
            (
                trimmed.fill(AuthoredStyle(retainedForegroundStyle: .color(Self.red)), style: Self.evenOdd),
                .color(Self.blue), ExpectedPaint(fill: Self.red, evenOdd: true)
            ),
            (trimmed.fill(linear, style: Self.evenOdd), .color(Self.blue), gradientPaint),
            (
                trimmed.fill(AuthoredStyle(retainedForegroundStyle: .linearGradient(linear)), style: Self.evenOdd),
                .color(Self.blue), gradientPaint
            ),
            (
                trimmed.fill(style: Self.evenOdd), .color(Self.blue),
                ExpectedPaint(fill: Self.blue, evenOdd: true)
            ),
            (trimmed.fill(style: Self.evenOdd), .linearGradient(linear), gradientPaint),
        ]
        for (shape, inherited, expected) in cases {
            let result = snapshot(shape.foregroundStyle(inherited).frame(width: 64, height: 64))
            try assertCompound(result, expected: expected)
        }
    }

    func testTrimmedExplicitAndInheritedStrokeReachPathOwner() async throws {
        let trimmed = CompoundShape().trim(from: 0, to: 1)
        let plainStroke = StrokeStyle(lineWidth: 4, dashPattern: [])
        let linear = linearGradient()
        let cases: [(TrimmedShape<CompoundShape>, ExpectedPaint)] = [
            (
                trimmed.stroke(Self.halfRed, lineWidth: 4),
                ExpectedPaint(stroke: Self.halfRed, strokeStyle: plainStroke)
            ),
            (
                trimmed.stroke(ForegroundStyle.color(Self.halfRed), style: Self.solidStroke),
                ExpectedPaint(stroke: Self.halfRed, strokeStyle: Self.solidStroke)
            ),
            (
                trimmed.stroke(AuthoredStyle(retainedForegroundStyle: .color(Self.halfRed)), style: Self.solidStroke),
                ExpectedPaint(stroke: Self.halfRed, strokeStyle: Self.solidStroke)
            ),
            (trimmed.stroke(lineWidth: 4), ExpectedPaint(stroke: Self.blue, strokeStyle: plainStroke)),
            (
                trimmed.stroke(style: Self.solidStroke),
                ExpectedPaint(stroke: Self.blue, strokeStyle: Self.solidStroke)
            ),
            (
                trimmed.stroke(Self.halfRed, style: Self.detailedStroke),
                ExpectedPaint(stroke: Self.halfRed, strokeStyle: Self.detailedStroke)
            ),
            (
                trimmed.stroke(style: Self.detailedStroke),
                ExpectedPaint(stroke: Self.blue, strokeStyle: Self.detailedStroke)
            ),
            (
                trimmed.stroke(linear, style: Self.solidStroke),
                ExpectedPaint(stroke: Self.red, strokeGradient: .linear(.init(linear)), strokeStyle: Self.solidStroke)
            ),
        ]
        for (shape, expected) in cases {
            let result = snapshot(shape.foregroundStyle(Self.blue).frame(width: 64, height: 64))
            try assertCompound(
                result, expected: expected, checkPixels: expected.strokeStyle?.dashPattern.isEmpty == true)
        }
        for width in [0.0, -4.0] {
            for shape in [
                trimmed.stroke(Self.red, lineWidth: width), trimmed.stroke(style: StrokeStyle(lineWidth: width)),
            ] {
                let result = snapshot(shape.foregroundStyle(Self.blue).frame(width: 64, height: 64))
                try assertCompound(result, expected: ExpectedPaint())
                XCTAssertTrue(raster(result).pixels.allSatisfy { $0 == 0 })
            }
        }
    }

    func testTrimmedCombinedPaintAndResetPreserveWholeState() async throws {
        let trimmed = CompoundShape().trim(from: 0, to: 1)
        // These concrete Windows setters preserve stroke when fill follows it;
        // they are not a claim about native SwiftUI's different return types.
        let combined = trimmed.stroke(Self.halfRed, style: Self.solidStroke).fill(Self.blue, style: Self.evenOdd)
        try assertCompound(
            snapshot(combined.frame(width: 64, height: 64)),
            expected: ExpectedPaint(fill: Self.blue, stroke: Self.halfRed, strokeStyle: Self.solidStroke, evenOdd: true)
        )
        try assertCompound(
            snapshot(
                trimmed.fill(Self.blue, style: Self.evenOdd).stroke(Self.halfRed, style: Self.solidStroke)
                    .frame(width: 64, height: 64)),
            expected: ExpectedPaint(stroke: Self.halfRed, strokeStyle: Self.solidStroke))
        try assertCompound(
            snapshot(combined.fill(Self.green).frame(width: 64, height: 64)),
            expected: ExpectedPaint(fill: Self.green, stroke: Self.halfRed, strokeStyle: Self.solidStroke))

        for (foreground, descriptor) in gradientStyles() {
            let painted = trimmed.stroke(foreground, style: Self.solidStroke).fill(foreground, style: Self.evenOdd)
            try assertCompound(
                snapshot(painted.foregroundStyle(Self.blue).frame(width: 64, height: 64)),
                expected: ExpectedPaint(
                    fill: Self.red, fillGradient: descriptor, stroke: Self.red,
                    strokeGradient: descriptor, strokeStyle: Self.solidStroke, evenOdd: true))
            let reset = painted.stroke(Self.halfRed, style: Self.solidStroke).fill(Self.green)
            try assertCompound(
                snapshot(reset.frame(width: 64, height: 64)),
                expected: ExpectedPaint(fill: Self.green, stroke: Self.halfRed, strokeStyle: Self.solidStroke))
        }
    }

    func testTrimmedMountedPaintAlternationReusesLeaf() async throws {
        try assertMountedAlternation(inset: 0) { self.trimmed(mode: $0) }
    }

    func testErasedInsetFillMatchesDirectOwnerAndCoverage() async throws {
        let inset = InsetShape(CompoundShape(), amount: 8)
        for eoFill in [false, true] {
            let style = FillStyle(eoFill: eoFill)
            for inherited in [false, true] {
                let direct = inherited ? inset.fill(style: style) : inset.fill(Self.red, style: style)
                let erased =
                    inherited ? AnyShape(inset).fill(style: style) : AnyShape(inset).fill(Self.red, style: style)
                let expected = ExpectedPaint(fill: inherited ? Self.blue : Self.red, evenOdd: eoFill)
                let first = snapshot(direct.foregroundStyle(Self.blue).frame(width: 64, height: 64))
                let second = snapshot(erased.foregroundStyle(Self.blue).frame(width: 64, height: 64))
                try assertCompound(first, expected: expected, inset: 8)
                try assertCompound(second, expected: expected, inset: 8)
                XCTAssertEqual(raster(first).pixels, raster(second).pixels)
            }
        }
        for result in [
            snapshot(inset.fill(Self.red).frame(width: 64, height: 64)),
            snapshot(AnyShape(inset).fill(Self.red).frame(width: 64, height: 64)),
        ] {
            try assertCompound(result, expected: ExpectedPaint(fill: Self.red), inset: 8)
        }
    }

    func testErasedInsetStrokeMatchesDirectOwner() async throws {
        let inset = InsetShape(CompoundShape(), amount: 8)
        let erased = AnyShape(inset)
        let cases: [(InsetShape<CompoundShape>, AnyShape, ExpectedPaint)] = [
            (
                inset.stroke(Self.halfRed, style: Self.solidStroke),
                erased.stroke(Self.halfRed, style: Self.solidStroke),
                ExpectedPaint(stroke: Self.halfRed, strokeStyle: Self.solidStroke)
            ),
            (
                inset.stroke(style: Self.solidStroke), erased.stroke(style: Self.solidStroke),
                ExpectedPaint(stroke: Self.blue, strokeStyle: Self.solidStroke)
            ),
            (
                inset.stroke(Self.halfRed, style: Self.solidStroke).fill(Self.blue, style: Self.evenOdd),
                erased.stroke(Self.halfRed, style: Self.solidStroke).fill(Self.blue, style: Self.evenOdd),
                ExpectedPaint(fill: Self.blue, stroke: Self.halfRed, strokeStyle: Self.solidStroke, evenOdd: true)
            ),
            (
                inset.stroke(Self.red, style: Self.detailedStroke), erased.stroke(Self.red, style: Self.detailedStroke),
                ExpectedPaint(stroke: Self.red, strokeStyle: Self.detailedStroke)
            ),
        ]
        for (direct, outer, expected) in cases {
            let first = snapshot(direct.foregroundStyle(Self.blue).frame(width: 64, height: 64))
            let second = snapshot(outer.foregroundStyle(Self.blue).frame(width: 64, height: 64))
            let solid = expected.strokeStyle?.dashPattern.isEmpty == true
            try assertCompound(first, expected: expected, inset: 8, checkPixels: solid)
            try assertCompound(second, expected: expected, inset: 8, checkPixels: solid)
            if solid { XCTAssertEqual(raster(first).pixels, raster(second).pixels) }
        }
    }

    func testErasedInsetRoundedMetadataAndNestedRoute() async throws {
        let rounded = RoundedRectangle(cornerRadius: 12)
        let inset = InsetShape(rounded, amount: 4)
        let cases: [(String, AnyShape, Double)] = [
            ("zero", AnyShape(InsetShape(rounded, amount: 0)), 12),
            ("four", AnyShape(inset), 8),
            ("repeated erasure", AnyShape(AnyShape(AnyShape(inset))), 8),
            ("outer zero", AnyShape(InsetShape(inset, amount: 0)), 8),
            ("clamped", AnyShape(InsetShape(rounded, amount: 20)), 0),
            ("negative", AnyShape(InsetShape(rounded, amount: -4)), 16),
            ("clamp before expansion", AnyShape(InsetShape(InsetShape(rounded, amount: 20), amount: -10)), 10),
            ("expansion before inset", AnyShape(InsetShape(InsetShape(rounded, amount: -4), amount: 6)), 10),
        ]
        for (name, shape, radius) in cases {
            guard case .roundedRectangle(let clipRadius) = shape.retainedClipShapeStyle else {
                XCTFail("lost rounded clip descriptor: \(name)")
                continue
            }
            XCTAssertEqual(clipRadius, radius, name)
            XCTAssertEqual(shape.retainedContentShapeStyle, .roundedRectangle(radius), name)
            let result = snapshot(shape.fill(Self.red).frame(width: 64, height: 64))
            let owner = try singleLeaf(in: result.runtime.root)
            assertPaint(owner, expected: ExpectedPaint(fill: Self.red))
            XCTAssertEqual(owner.cornerRadius, radius, name)
            XCTAssertNil(owner.cornerRadii, name)
            assertWrappersClear(in: result.runtime.root, owner: owner)
        }
        let direct = snapshot(inset.fill(Self.red).frame(width: 64, height: 64))
        let erased = snapshot(AnyShape(inset).fill(Self.red).frame(width: 64, height: 64))
        XCTAssertEqual(try singleLeaf(in: direct.runtime.root).cornerRadius, 8)
        XCTAssertEqual(raster(direct).pixels, raster(erased).pixels)
        let passive = snapshot(AnyShape(inset).frame(width: 64, height: 64))
        XCTAssertEqual(
            try singleLeaf(in: passive.runtime.root).cornerRadius, 12,
            "passive erasure must leave the underlying producer unchanged")

        let uneven = UnevenRoundedRectangle(
            topLeadingRadius: 12, bottomLeadingRadius: 6, bottomTrailingRadius: 10, topTrailingRadius: 8)
        let unevenResult = snapshot(AnyShape(InsetShape(uneven, amount: 4)).fill(Self.red).frame(width: 64, height: 64))
        let unevenOwner = try singleLeaf(in: unevenResult.runtime.root)
        XCTAssertEqual(unevenOwner.cornerRadius, 8)
        XCTAssertEqual(
            unevenOwner.cornerRadii,
            RetainedCornerRadii(topLeft: 12, topRight: 8, bottomRight: 10, bottomLeft: 6))
    }

    func testErasedInsetNestedErasureAndTransformsKeepPaintOnLeaf() async throws {
        for amount in [0.0, 8.0] {
            let inset = InsetShape(CompoundShape(), amount: amount)
            let cases: [(String, AnyShape, Int, Int)] = [
                ("erasure", AnyShape(AnyShape(AnyShape(inset))), 32, 20),
                ("rotation", AnyShape(inset.rotation(.degrees(45))), 32, 18),
                ("scale", AnyShape(inset.scale(0.75)), 32, 20),
                ("offset", AnyShape(inset.offset(x: 4, y: 0)), 36, 20),
                ("transform", AnyShape(inset.transform(.translation(x: 4, y: 0))), 36, 20),
            ]
            for (kind, shape, centerX, ringX) in cases {
                let result = snapshot(
                    shape.fill(Self.red, style: Self.evenOdd).foregroundStyle(Self.blue)
                        .frame(width: 64, height: 64))
                let owner = try assertCompound(
                    result, expected: ExpectedPaint(fill: Self.red, evenOdd: true), inset: amount, checkPixels: false)
                XCTAssertEqual(
                    descendants(of: result.runtime.root).filter { $0.transform != .identity }.count,
                    kind == "erasure" ? 0 : 1)
                let bitmap = raster(result)
                assertPixel(bitmap, x: ringX, y: 32, color: Self.red)
                assertPixel(bitmap, x: centerX, y: 32, color: .clear)
                assertPixel(bitmap, x: 2, y: 2, color: .clear)
                let oldEdge = amount == 0 ? 10 : 16
                if kind == "rotation" {
                    // At 45 degrees these original square corners are outside
                    // the diamond; a 90-degree symmetric fixture would not tell.
                    assertPixel(bitmap, x: oldEdge, y: oldEdge, color: .clear)
                    assertPixel(bitmap, x: 32, y: amount == 0 ? 4 : 8, color: Self.red)
                } else if kind == "scale" {
                    assertPixel(bitmap, x: oldEdge, y: 32, color: .clear)
                } else if kind == "offset" || kind == "transform" {
                    assertPixel(bitmap, x: oldEdge, y: 32, color: .clear)
                    assertPixel(bitmap, x: amount == 0 ? 58 : 52, y: 32, color: Self.red)
                }
                XCTAssertEqual(
                    owner.resolvedFrame, Rect(x: amount, y: amount, width: 64 - amount * 2, height: 64 - amount * 2))
            }
        }
    }

    func testErasedInsetMountedPaintAlternationClearsReusedOwner() async throws {
        // Zero returns a leaf and nonzero returns padding. Each reload series
        // keeps its own topology; identity across that boundary is not promised.
        for amount in [0.0, 8.0] {
            try assertMountedAlternation(inset: amount) {
                self.painted(AnyShape(InsetShape(CompoundShape(), amount: amount)), mode: $0)
            }
        }
    }

    func testErasedArcFillSurvivesEveryLayout() async throws {
        let inner = arc().stroke(Self.blue, style: Self.detailedStroke).fill(Self.green)
        let linear = linearGradient()
        let cases: [(AnyShape, ExpectedPaint)] = [
            (AnyShape(inner).fill(Self.red, style: Self.evenOdd), ExpectedPaint(fill: Self.red, evenOdd: true)),
            (AnyShape(inner).fill(style: Self.evenOdd), ExpectedPaint(fill: Self.blue, evenOdd: true)),
            (
                AnyShape(inner).fill(linear, style: Self.nonZero),
                ExpectedPaint(fill: Self.red, fillGradient: .linear(.init(linear)), evenOdd: false)
            ),
            (AnyShape(inner).fill(Self.red), ExpectedPaint(fill: Self.red)),
        ]
        for (shape, expected) in cases {
            let first = arcSnapshot(shape)
            let owner = try assertArc(first, expected: expected)
            for (index, size) in [IntSize(width: 20, height: 18), Self.arcSize].enumerated() {
                first.runtime.setRootSize(size)
                XCTAssertTrue(first.runtime.hasPendingLayout)
                let next = capture(first.runtime, size: size, time: Double(index + 1))
                XCTAssertTrue(try assertArc(next, expected: expected) === owner)
                XCTAssertEqual(owner.resolvedFrame.size, Size(width: Double(size.width), height: Double(size.height)))
            }
        }
    }

    func testErasedArcStrokeAndCombinedPaintSurviveLayout() async throws {
        let inner = arc().fill(Self.green, style: Self.evenOdd)
        let linear = linearGradient()
        let gradientStroke = AnyShape(inner).stroke(linear, style: Self.detailedStroke)
        let cases: [(AnyShape, ExpectedPaint)] = [
            (
                AnyShape(inner).stroke(Self.halfRed, style: Self.solidStroke),
                ExpectedPaint(stroke: Self.halfRed, strokeStyle: Self.solidStroke)
            ),
            (
                AnyShape(inner).stroke(style: Self.detailedStroke),
                ExpectedPaint(stroke: Self.blue, strokeStyle: Self.detailedStroke)
            ),
            (
                AnyShape(inner).stroke(Self.halfRed, style: Self.detailedStroke).fill(Self.blue, style: Self.evenOdd),
                ExpectedPaint(fill: Self.blue, stroke: Self.halfRed, strokeStyle: Self.detailedStroke, evenOdd: true)
            ),
            (
                gradientStroke,
                ExpectedPaint(
                    stroke: Self.red, strokeGradient: .linear(.init(linear)), strokeStyle: Self.detailedStroke)
            ),
            (
                gradientStroke.stroke(Self.halfRed, style: Self.solidStroke).fill(Self.red),
                ExpectedPaint(fill: Self.red, stroke: Self.halfRed, strokeStyle: Self.solidStroke)
            ),
        ]
        for (shape, expected) in cases {
            let first = arcSnapshot(shape)
            let owner = try assertArc(first, expected: expected)
            first.runtime.setRootSize(IntSize(width: 18, height: 20))
            let next = capture(first.runtime, size: IntSize(width: 18, height: 20), time: 1)
            XCTAssertTrue(try assertArc(next, expected: expected) === owner)
        }
    }

    func testErasedArcMountedReloadUpdatesLiveNodeAtSameSize() async throws {
        let runtime = RetainedViewRuntime(clearColor: .clear, root: ViewNode())
        runtime.setRootSize(Self.arcSize)
        let host = ComponentHost(runtime: runtime)
        let context = ViewBuildContext(canvasSizeProvider: { Size(width: 16, height: 16) }, invalidateHandler: {})
        var angle = 0.0
        var mode = PaintMode.explicitEvenOdd
        host.setComponents {
            [
                self.painted(AnyShape(self.arc(start: angle).fill(Self.green)), mode: mode)
                    .foregroundStyle(Self.blue).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .makeComponent(context: context)
            ]
        }
        let first = capture(runtime, size: Self.arcSize, time: 0)
        let owner = try assertArc(first, expected: expected(mode))
        var previousPath = try XCTUnwrap(owner.backgroundPath)
        for (index, nextMode) in [PaintMode.inheritedEvenOdd, .gradient, .combined, .stroke, .plainColor].enumerated() {
            angle = Double(index + 1) * 25
            mode = nextMode
            host.reload()
            XCTAssertTrue(runtime.hasPendingLayout, "replacing a geometry receiver must invalidate a same-size layout")
            let result = capture(runtime, size: Self.arcSize, time: Double(index + 1))
            XCTAssertTrue(try assertArc(result, expected: expected(mode)) === owner)
            XCTAssertEqual(owner.resolvedFrame.size, Size(width: 16, height: 16))
            let path = try XCTUnwrap(owner.backgroundPath)
            XCTAssertNotEqual(
                path, previousPath, "changed angles must reach the live node, without asserting native arc geometry")
            previousPath = path
        }
    }

    func testErasedArcResizePreservesOuterPaintAndLiveGeometry() async throws {
        let runtime = RetainedViewRuntime(clearColor: .clear, root: ViewNode())
        runtime.setRootSize(Self.arcSize)
        let host = ComponentHost(runtime: runtime)
        var canvasSize = Self.arcSize
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: Double(canvasSize.width), height: Double(canvasSize.height)) },
            invalidateHandler: {})
        var angle = 0.0
        let linear = linearGradient()
        let paint = ExpectedPaint(
            fill: Self.red, fillGradient: .linear(.init(linear)),
            stroke: Self.halfRed, strokeStyle: Self.detailedStroke, evenOdd: true)
        host.setComponents {
            [
                AnyShape(self.arc(start: angle).fill(Self.green))
                    .stroke(Self.halfRed, style: Self.detailedStroke).fill(linear, style: Self.evenOdd)
                    .foregroundStyle(Self.blue).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .makeComponent(context: context)
            ]
        }
        let owner = try assertArc(capture(runtime, size: Self.arcSize, time: 0), expected: paint)
        let initialPath = try XCTUnwrap(owner.backgroundPath)
        angle = 35
        host.reload()
        XCTAssertTrue(try assertArc(capture(runtime, size: Self.arcSize, time: 1), expected: paint) === owner)
        let reloadedPath = try XCTUnwrap(owner.backgroundPath)
        XCTAssertNotEqual(reloadedPath, initialPath)
        let resized = IntSize(width: 24, height: 20)
        canvasSize = resized
        runtime.setRootSize(resized)
        XCTAssertTrue(runtime.hasPendingLayout)
        XCTAssertTrue(try assertArc(capture(runtime, size: resized, time: 2), expected: paint) === owner)
        XCTAssertEqual(
            owner.resolvedFrame.size, Size(width: 24, height: 20), "resize the path owner, not only its wrapper")
        XCTAssertNotEqual(try XCTUnwrap(owner.backgroundPath), reloadedPath)
    }

    func testUnstyledErasureAndOuterPaintPrecedenceRemainSeparate() async throws {
        let linear = linearGradient()
        let inner = CompoundShape().trim(from: 0, to: 1)
            .stroke(Self.halfRed, style: Self.solidStroke).fill(linear, style: Self.evenOdd)
        let innerPaint = ExpectedPaint(
            fill: Self.red, fillGradient: .linear(.init(linear)),
            stroke: Self.halfRed, strokeStyle: Self.solidStroke, evenOdd: true)
        let direct = snapshot(inner.foregroundStyle(Self.blue).frame(width: 64, height: 64))
        let passive = snapshot(AnyShape(AnyShape(inner)).foregroundStyle(Self.blue).frame(width: 64, height: 64))
        try assertCompound(direct, expected: innerPaint)
        try assertCompound(passive, expected: innerPaint)
        XCTAssertEqual(raster(direct).pixels, raster(passive).pixels)

        let nestedInset = InsetShape(InsetShape(inner, amount: 8), amount: 0)
        try assertCompound(
            snapshot(AnyShape(AnyShape(nestedInset)).frame(width: 64, height: 64)), expected: innerPaint, inset: 8)
        try assertCompound(
            snapshot(AnyShape(AnyShape(nestedInset)).fill(Self.green).frame(width: 64, height: 64)),
            expected: ExpectedPaint(fill: Self.green), inset: 8)

        let innerArc = arc().stroke(Self.halfRed, style: Self.solidStroke).fill(linear, style: Self.evenOdd)
        try assertArc(arcSnapshot(AnyShape(AnyShape(innerArc))), expected: innerPaint)
        try assertArc(
            arcSnapshot(AnyShape(AnyShape(innerArc)).fill(Self.green)), expected: ExpectedPaint(fill: Self.green))

        let siblings = snapshot(
            HStack(spacing: 0) {
                AnyShape(InsetShape(CompoundShape(), amount: 8)).fill(Self.green)
                    .frame(width: 64, height: 64).clipShape(Rectangle(), style: Self.evenOdd)
                CompoundShape().fill(Self.blue, style: Self.nonZero).frame(width: 64, height: 64)
            }, size: IntSize(width: 128, height: 64))
        let owners = descendants(of: siblings.runtime.root).filter { $0.backgroundPath != nil }
        XCTAssertEqual(owners.count, 2)
        let first = try XCTUnwrap(owners.first)
        let second = try XCTUnwrap(owners.last)
        assertPaint(first, expected: ExpectedPaint(fill: Self.green))
        assertPaint(second, expected: ExpectedPaint(fill: Self.blue, evenOdd: false))
        XCTAssertEqual(
            descendants(of: siblings.runtime.root).filter {
                $0.backgroundPath == nil && $0.clipFillStyle?.eoFill == true
            }.count, 1, "local clip metadata must stay on its wrapper")
        let bitmap = raster(siblings)
        assertPixel(bitmap, x: 20, y: 32, color: Self.green)
        assertPixel(bitmap, x: 32, y: 32, color: Self.green)
        assertPixel(bitmap, x: 84, y: 32, color: Self.blue)
        assertPixel(bitmap, x: 96, y: 32, color: Self.blue)
        assertPixel(bitmap, x: 4, y: 32, color: .clear)
    }

    func testLayoutReceiverUsesRetainedNodeAndReconcilesRemoval() async throws {
        let untouched = ViewNode()
        XCTAssertFalse(untouched.hasAllocatedLifecycleHandlers)
        XCTAssertNil(untouched.onLayoutWithNode)
        untouched.onLayoutWithNode = nil
        XCTAssertFalse(untouched.hasAllocatedLifecycleHandlers)

        let runtime = RetainedViewRuntime(clearColor: .clear, root: ViewNode())
        runtime.setRootSize(Self.size)
        let host = ComponentHost(runtime: runtime)
        var generation = 1
        var constructed: [ObjectIdentifier] = []
        var deliveries: [LayoutDelivery] = []
        host.setComponents {
            [
                Component(key: "receiver") { _ in
                    let node = ViewNode()
                    node.layoutFillAxes = .both
                    constructed.append(ObjectIdentifier(node))
                    let capturedGeneration = generation
                    if capturedGeneration < 3 {
                        node.onLayoutWithNode = { receiver, bounds in
                            XCTAssertEqual(bounds, receiver.resolvedFrame)
                            deliveries.append(
                                LayoutDelivery(
                                    generation: capturedGeneration, receiver: ObjectIdentifier(receiver), bounds: bounds
                                ))
                        }
                    }
                    return node
                },
                Component(key: "plain sibling") { _ in ViewNode() },
            ]
        }
        _ = runtime.renderFrame(at: 0)
        let retained = try XCTUnwrap(runtime.root.children.first)
        let sibling = try XCTUnwrap(runtime.root.children.last)
        XCTAssertEqual(deliveries.map(\.generation), [1])
        XCTAssertEqual(deliveries.map(\.receiver), [ObjectIdentifier(retained)])
        XCTAssertEqual(deliveries.first?.bounds, Rect(x: 0, y: 0, width: 64, height: 64))
        XCTAssertFalse(sibling.hasAllocatedLifecycleHandlers)

        generation = 2
        host.reload()
        XCTAssertTrue(runtime.hasPendingLayout)
        _ = runtime.renderFrame(at: 1)
        XCTAssertTrue(runtime.root.children.first === retained)
        XCTAssertTrue(runtime.root.children.last === sibling)
        XCTAssertEqual(constructed.count, 2)
        XCTAssertNotEqual(try XCTUnwrap(constructed.last), ObjectIdentifier(retained))
        XCTAssertEqual(deliveries.map(\.generation), [1, 2])
        XCTAssertEqual(deliveries.map(\.receiver), [ObjectIdentifier(retained), ObjectIdentifier(retained)])
        XCTAssertFalse(sibling.hasAllocatedLifecycleHandlers)

        generation = 3
        host.reload()
        XCTAssertNil(retained.onLayoutWithNode)
        _ = runtime.renderFrame(at: 2)
        XCTAssertTrue(runtime.root.children.first === retained)
        XCTAssertEqual(deliveries.map(\.generation), [1, 2])
        XCTAssertFalse(sibling.hasAllocatedLifecycleHandlers)
    }

    func testLayoutReceiverInvalidatesSameSizeAndPreservesLegacyCallback() async throws {
        let node = ViewNode()
        let runtime = RetainedViewRuntime(clearColor: .clear, root: node)
        runtime.setRootSize(Self.size)
        var events: [String] = []
        node.onLayout = { _ in events.append("legacy") }
        _ = runtime.renderFrame(at: 0)
        XCTAssertFalse(runtime.hasPendingLayout)
        events.removeAll()

        node.onLayoutWithNode = { receiver, bounds in
            XCTAssertTrue(receiver === node)
            XCTAssertEqual(bounds, node.resolvedFrame)
            events.append("A")
        }
        XCTAssertTrue(runtime.hasPendingLayout)
        _ = runtime.renderFrame(at: 1)
        XCTAssertEqual(events, ["legacy", "A"])
        XCTAssertFalse(runtime.hasPendingLayout)
        _ = runtime.renderFrame(at: 2)
        XCTAssertEqual(events, ["legacy", "A"], "a clean cached layout delivers neither callback again")
        node.onLayoutWithNode = { _, _ in events.append("B") }
        XCTAssertTrue(runtime.hasPendingLayout)
        _ = runtime.renderFrame(at: 3)
        XCTAssertEqual(events, ["legacy", "A", "legacy", "B"])
        XCTAssertFalse(runtime.hasPendingLayout)
        node.onLayoutWithNode = nil
        XCTAssertTrue(runtime.hasPendingLayout)
        _ = runtime.renderFrame(at: 4)
        XCTAssertEqual(events, ["legacy", "A", "legacy", "B", "legacy"])
        XCTAssertFalse(runtime.hasPendingLayout)
        node.onLayoutWithNode = nil
        XCTAssertFalse(runtime.hasPendingLayout)
        _ = runtime.renderFrame(at: 5)
        XCTAssertEqual(events.count, 5)

        let cleanupNode = ViewNode()
        let cleanupRuntime = RetainedViewRuntime(clearColor: .clear, root: cleanupNode)
        cleanupRuntime.setRootSize(Self.size)
        var cleanupEvents: [String] = []
        func installCapturedHandler() {
            let payload = ShapePaintHandlerLifetime { [weak cleanupNode] in
                cleanupEvents.append("release")
                guard let cleanupNode else { return }
                // Cleanup must observe the published replacement, and its
                // reentrant replacement must survive the outer setter.
                cleanupNode.onLayoutWithNode?(cleanupNode, cleanupNode.resolvedFrame)
                cleanupNode.onLayoutWithNode = { _, _ in cleanupEvents.append("C") }
            }
            cleanupNode.onLayoutWithNode = { [payload] _, _ in
                withExtendedLifetime(payload) {}
                cleanupEvents.append("old")
            }
        }
        installCapturedHandler()
        _ = cleanupRuntime.renderFrame(at: 0)
        XCTAssertEqual(cleanupEvents, ["old"])
        cleanupEvents.removeAll()
        cleanupNode.onLayoutWithNode = { _, _ in cleanupEvents.append("B") }
        XCTAssertEqual(cleanupEvents, ["release", "B"], "old captures are released before setter return")
        XCTAssertTrue(cleanupRuntime.hasPendingLayout)
        _ = cleanupRuntime.renderFrame(at: 1)
        XCTAssertEqual(cleanupEvents, ["release", "B", "C"])
        XCTAssertFalse(cleanupRuntime.hasPendingLayout)
        _ = cleanupRuntime.renderFrame(at: 2)
        XCTAssertEqual(cleanupEvents, ["release", "B", "C"])
        cleanupNode.onLayoutWithNode = nil
    }

    private func linearGradient() -> WinSwiftUI.LinearGradient {
        WinSwiftUI.LinearGradient(colors: [Self.red, Self.blue], startPoint: .leading, endPoint: .trailing)
    }

    private func gradientStyles() -> [(ForegroundStyle, GradientType)] {
        let linear = linearGradient()
        let radial = WinSwiftUI.RadialGradient(
            colors: [Self.red, Self.blue], center: .center, startRadius: 0, endRadius: 32)
        let conic = WinSwiftUI.AngularGradient(
            colors: [Self.red, Self.blue], center: .center, startAngle: .zero, endAngle: .degrees(360))
        return [
            (.linearGradient(linear), .linear(.init(linear))),
            (.radialGradient(radial), .radial(.init(radial))),
            (.conicGradient(conic), .conic(.init(conic))),
        ]
    }

    private func expected(_ mode: PaintMode) -> ExpectedPaint {
        switch mode {
        case .explicitEvenOdd: return ExpectedPaint(fill: Self.red, evenOdd: true)
        case .inheritedEvenOdd: return ExpectedPaint(fill: Self.blue, evenOdd: true)
        case .explicitNonZero: return ExpectedPaint(fill: Self.red, evenOdd: false)
        case .gradient:
            return ExpectedPaint(fill: Self.red, fillGradient: .linear(.init(linearGradient())), evenOdd: true)
        case .combined:
            return ExpectedPaint(fill: Self.blue, stroke: Self.halfRed, strokeStyle: Self.solidStroke, evenOdd: true)
        case .stroke: return ExpectedPaint(stroke: Self.halfRed, strokeStyle: Self.solidStroke)
        case .plainColor: return ExpectedPaint(fill: Self.green)
        case .inheritedDefault: return ExpectedPaint(fill: Self.blue, evenOdd: false)
        }
    }

    private func trimmed(mode: PaintMode) -> TrimmedShape<CompoundShape> {
        let shape = CompoundShape().trim(from: 0, to: 1)
        switch mode {
        case .explicitEvenOdd: return shape.fill(Self.red, style: Self.evenOdd)
        case .inheritedEvenOdd: return shape.fill(style: Self.evenOdd)
        case .explicitNonZero: return shape.fill(Self.red, style: Self.nonZero)
        case .gradient: return shape.fill(linearGradient(), style: Self.evenOdd)
        case .combined: return shape.stroke(Self.halfRed, style: Self.solidStroke).fill(Self.blue, style: Self.evenOdd)
        case .stroke: return shape.stroke(Self.halfRed, style: Self.solidStroke)
        case .plainColor: return shape.fill(Self.green)
        case .inheritedDefault: return shape.fill(style: FillStyle())
        }
    }

    private func painted(_ shape: AnyShape, mode: PaintMode) -> AnyShape {
        switch mode {
        case .explicitEvenOdd: return shape.fill(Self.red, style: Self.evenOdd)
        case .inheritedEvenOdd: return shape.fill(style: Self.evenOdd)
        case .explicitNonZero: return shape.fill(Self.red, style: Self.nonZero)
        case .gradient: return shape.fill(linearGradient(), style: Self.evenOdd)
        case .combined: return shape.stroke(Self.halfRed, style: Self.solidStroke).fill(Self.blue, style: Self.evenOdd)
        case .stroke: return shape.stroke(Self.halfRed, style: Self.solidStroke)
        case .plainColor: return shape.fill(Self.green)
        case .inheritedDefault: return shape.fill(style: FillStyle())
        }
    }

    private func assertMountedAlternation<V: View>(
        inset: Double, build: @escaping @MainActor (PaintMode) -> V,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let runtime = RetainedViewRuntime(clearColor: .clear, root: ViewNode())
        runtime.setRootSize(Self.size)
        let host = ComponentHost(runtime: runtime)
        let context = ViewBuildContext(canvasSizeProvider: { Size(width: 64, height: 64) }, invalidateHandler: {})
        var mode = PaintMode.explicitEvenOdd
        host.setComponents {
            [build(mode).foregroundStyle(Self.blue).frame(width: 64, height: 64).makeComponent(context: context)]
        }
        let first = capture(runtime, size: Self.size, time: 0)
        let owner = try assertCompound(first, expected: expected(mode), inset: inset, file: file, line: line)
        let firstPixels = raster(first).pixels
        var previousPixels = firstPixels
        let modes = Array(PaintMode.allCases.dropFirst()) + [.explicitEvenOdd]
        for (index, nextMode) in modes.enumerated() {
            mode = nextMode
            host.reload()
            let result = capture(runtime, size: Self.size, time: Double(index + 1))
            XCTAssertTrue(
                try assertCompound(result, expected: expected(mode), inset: inset, file: file, line: line) === owner,
                "reuse the path leaf rather than merely its layout wrapper", file: file, line: line)
            let pixels = raster(result).pixels
            XCTAssertNotEqual(
                pixels, previousPixels, "each requested paint transition must repaint", file: file, line: line)
            previousPixels = pixels
        }
        XCTAssertEqual(
            previousPixels, firstPixels, "returning to the same bundle reproduces its coverage", file: file, line: line)
    }

    private func arc(start: Double = 0) -> Arc {
        Arc(startAngle: .degrees(start), endAngle: .degrees(start + 180), clockwise: false)
    }

    private func arcSnapshot(_ shape: AnyShape) -> WinSwiftUIRenderSnapshot {
        snapshot(shape.foregroundStyle(Self.blue).frame(maxWidth: .infinity, maxHeight: .infinity), size: Self.arcSize)
    }

    private func snapshot<V: View>(_ view: V, size: IntSize = IntSize(width: 64, height: 64))
        -> WinSwiftUIRenderSnapshot
    {
        WinSwiftUIRendererSnapshotter.snapshot(of: view, size: size, displayScale: 1, clearColor: .clear)
    }

    private func capture(_ runtime: RetainedViewRuntime, size: IntSize, time: Double) -> WinSwiftUIRenderSnapshot {
        let scene = runtime.renderScene(at: time)
        let frame = runtime.renderFrame(at: time)
        return WinSwiftUIRenderSnapshot(runtime: runtime, frame: frame, scene: scene, size: size, displayScale: 1)
    }

    private func descendants(of root: ViewNode) -> [ViewNode] {
        [root] + root.children.flatMap { descendants(of: $0) }
    }

    private func pathNode(in root: ViewNode, file: StaticString = #filePath, line: UInt = #line) throws -> ViewNode {
        let nodes = descendants(of: root).filter { $0.backgroundPath != nil }
        XCTAssertEqual(nodes.count, 1, file: file, line: line)
        return try XCTUnwrap(nodes.first, file: file, line: line)
    }

    private func singleLeaf(in root: ViewNode, file: StaticString = #filePath, line: UInt = #line) throws -> ViewNode {
        let nodes = descendants(of: root).filter { $0.children.isEmpty }
        XCTAssertEqual(nodes.count, 1, file: file, line: line)
        return try XCTUnwrap(nodes.first, file: file, line: line)
    }

    private func assertPaint(
        _ node: ViewNode, expected: ExpectedPaint, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(node.backgroundColor, expected.fill, file: file, line: line)
        XCTAssertEqual(node.backgroundGradient, expected.fillGradient, file: file, line: line)
        XCTAssertEqual(node.borderColor, expected.stroke, file: file, line: line)
        XCTAssertEqual(node.borderGradient, expected.strokeGradient, file: file, line: line)
        XCTAssertEqual(node.borderWidth, expected.strokeStyle?.lineWidth ?? 0, file: file, line: line)
        XCTAssertEqual(node.borderStrokeStyle, expected.strokeStyle, file: file, line: line)
        XCTAssertEqual(
            node.clipFillStyle, expected.evenOdd.map { RetainedClipFillStyle(eoFill: $0) }, file: file, line: line)
    }

    private func assertWrappersClear(
        in root: ViewNode, owner: ViewNode, file: StaticString = #filePath, line: UInt = #line
    ) {
        for node in descendants(of: root) where node !== owner {
            XCTAssertTrue(node.backgroundColor == nil || node.backgroundColor == .clear, file: file, line: line)
            XCTAssertNil(node.backgroundGradient, file: file, line: line)
            XCTAssertEqual(node.borderColor, .clear, file: file, line: line)
            XCTAssertNil(node.borderGradient, file: file, line: line)
            XCTAssertEqual(node.borderWidth, 0, file: file, line: line)
            XCTAssertNil(node.borderStrokeStyle, file: file, line: line)
            XCTAssertNil(node.clipFillStyle, file: file, line: line)
        }
    }

    private func assertCommands(
        _ frame: RenderFrame, expected: ExpectedPaint, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let fills: [FillPathCommand] = frame.commands.compactMap {
            guard case .fillPath(let command) = $0 else { return nil }
            return command
        }
        let strokes: [StrokePathCommand] = frame.commands.compactMap {
            guard case .strokePath(let command) = $0 else { return nil }
            return command
        }
        XCTAssertEqual(fills.count, expected.fill.alpha > 0 ? 1 : 0, file: file, line: line)
        if expected.fill.alpha > 0 {
            let fill = try XCTUnwrap(fills.first, file: file, line: line)
            XCTAssertEqual(fill.color, expected.fill, file: file, line: line)
            XCTAssertEqual(fill.fillRule, expected.evenOdd == true ? .evenOdd : .nonZero, file: file, line: line)
        }
        let hasStroke = expected.stroke.alpha > 0 && (expected.strokeStyle?.lineWidth ?? 0) > 0
        XCTAssertEqual(strokes.count, hasStroke ? 1 : 0, file: file, line: line)
        if hasStroke {
            let stroke = try XCTUnwrap(strokes.first, file: file, line: line)
            let style = try XCTUnwrap(expected.strokeStyle, file: file, line: line)
            XCTAssertEqual(stroke.color, expected.stroke, file: file, line: line)
            XCTAssertEqual(stroke.style.lineWidth, style.lineWidth, file: file, line: line)
            XCTAssertEqual(stroke.style.lineCap, style.lineCap, file: file, line: line)
            XCTAssertEqual(stroke.style.lineJoin, style.lineJoin, file: file, line: line)
            XCTAssertEqual(stroke.style.miterLimit, style.miterLimit, file: file, line: line)
            // Runtime's legacy command currently omits dash and phase. The
            // complete authored style is asserted on the leaf, not invented here.
        }
    }

    @discardableResult
    private func assertCompound(
        _ result: WinSwiftUIRenderSnapshot, expected: ExpectedPaint, inset: Double = 0, checkPixels: Bool = true,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> ViewNode {
        let owner = try pathNode(in: result.runtime.root, file: file, line: line)
        assertPaint(owner, expected: expected, file: file, line: line)
        assertWrappersClear(in: result.runtime.root, owner: owner, file: file, line: line)
        XCTAssertEqual(
            owner.resolvedFrame, Rect(x: inset, y: inset, width: 64 - inset * 2, height: 64 - inset * 2),
            file: file, line: line)
        try assertCommands(result.frame, expected: expected, file: file, line: line)
        XCTAssertTrue(result.scene.validate().isEmpty, file: file, line: line)
        if expected.fill.alpha > 0 {
            let fills = result.scene.layers.flatMap(\.paths).filter { $0.fillColor.alpha > 0 }
            XCTAssertEqual(fills.count, 1, "compound fill retains the CPU path lane", file: file, line: line)
            let fill = try XCTUnwrap(fills.first, file: file, line: line)
            XCTAssertEqual(fill.fillColor, expected.fill, file: file, line: line)
            XCTAssertEqual(fill.fillRule, expected.evenOdd == true ? .evenOdd : .nonZero, file: file, line: line)
            XCTAssertNil(
                fill.fillGradient, "generic shape gradients still emit their first stop", file: file, line: line)
        }
        if checkPixels {
            // These are independent geometry/coverage probes, not merely an
            // equality comparison between two implementations of the same bug.
            for bitmap in [raster(result), GPUIRawSceneRasterizer.rasterize(result.frame, size: result.size)] {
                assertPixel(bitmap, x: 20, y: 32, color: expected.fill, file: file, line: line)
                assertPixel(
                    bitmap, x: 32, y: 32,
                    color: expected.evenOdd == true ? .clear : expected.fill, file: file, line: line)
                assertPixel(bitmap, x: 4, y: 32, color: .clear, file: file, line: line)
                if expected.strokeStyle?.lineWidth == 4 {
                    XCTAssertEqual(
                        expected.strokeStyle?.dashPattern, [], "pixel oracle is only for a solid stroke", file: file,
                        line: line)
                    assertPixel(bitmap, x: inset == 0 ? 10 : 16, y: 32, color: expected.stroke, file: file, line: line)
                }
            }
        }
        return owner
    }

    @discardableResult
    private func assertArc(
        _ result: WinSwiftUIRenderSnapshot, expected: ExpectedPaint,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> ViewNode {
        let owner = try pathNode(in: result.runtime.root, file: file, line: line)
        assertPaint(owner, expected: expected, file: file, line: line)
        assertWrappersClear(in: result.runtime.root, owner: owner, file: file, line: line)
        try assertCommands(result.frame, expected: expected, file: file, line: line)
        let path = try XCTUnwrap(owner.backgroundPath, file: file, line: line)
        XCTAssertGreaterThan(path.segments.count, 1, file: file, line: line)
        for segment in path.segments {
            switch segment {
            case .moveTo(let point), .lineTo(let point):
                XCTAssertTrue(point.x.isFinite && point.y.isFinite, file: file, line: line)
            case .quadCurveTo(let control, let end):
                XCTAssertTrue([control.x, control.y, end.x, end.y].allSatisfy(\.isFinite), file: file, line: line)
            case .cubicCurveTo(let first, let second, let end):
                XCTAssertTrue(
                    [first.x, first.y, second.x, second.y, end.x, end.y].allSatisfy(\.isFinite), file: file, line: line)
            case .arc(let center, let radius, let start, let end, _):
                XCTAssertTrue([center.x, center.y, radius, start, end].allSatisfy(\.isFinite), file: file, line: line)
            case .close: break
            }
        }
        return owner
    }

    private func raster(_ result: WinSwiftUIRenderSnapshot) -> BitmapSurface {
        GPUIRawSceneRasterizer.rasterize(result.scene, size: result.size)
    }

    private func assertPixel(
        _ bitmap: BitmapSurface, x: Int, y: Int, color: Color,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        guard x >= 0, y >= 0, x < Int(bitmap.width), y < Int(bitmap.height) else {
            XCTFail("sample is outside the bitmap", file: file, line: line)
            return
        }
        let offset = y * Int(bitmap.bytesPerRow) + x * 4
        guard offset + 3 < bitmap.pixels.count else {
            XCTFail("sample is outside the pixel buffer", file: file, line: line)
            return
        }
        XCTAssertEqual(
            Int(bitmap.pixels[offset + 3]), Int((color.alpha * 255).rounded()), accuracy: 1, file: file, line: line)
        if color.alpha > 0 {
            XCTAssertEqual(
                Int(bitmap.pixels[offset + 2]), Int((color.red * 255).rounded()), accuracy: 1, file: file, line: line)
            XCTAssertEqual(
                Int(bitmap.pixels[offset + 1]), Int((color.green * 255).rounded()), accuracy: 1, file: file, line: line)
            XCTAssertEqual(
                Int(bitmap.pixels[offset]), Int((color.blue * 255).rounded()), accuracy: 1, file: file, line: line)
        }
    }
}
