import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
@preconcurrency import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Independent circle coordinates and interior pixels for Arc's retained
/// adapter. These tests do not use Arc.path(in:) to predict rendered geometry,
/// compare whole images, or claim native Arc, trim, or arbitrary transform parity.
@MainActor
final class ArcCoordinateTests: XCTestCase {
    private static let red = Color(red: 1, green: 0, blue: 0, alpha: 1)
    private static let green = Color(red: 0, green: 1, blue: 0, alpha: 1)
    private static let blue = Color(red: 0, green: 0, blue: 1, alpha: 1)
    private static let evenOdd = FillStyle(eoFill: true)
    private static let wide = IntSize(width: 80, height: 40)
    private static let paddedSize = IntSize(width: 100, height: 80)

    private enum PixelColor: Equatable {
        case clear, red, green, blue

        var bgra: [UInt8] {
            switch self {
            case .clear: return [0, 0, 0, 0]
            case .red: return [0, 0, 255, 255]
            case .green: return [0, 255, 0, 255]
            case .blue: return [255, 0, 0, 255]
            }
        }
    }

    private typealias Probe = (x: Int, y: Int, color: PixelColor)

    func testPublicPathUsesSuppliedRectAndPreservesAngles() async throws {
        let wide = Rect(x: 10, y: 20, width: 80, height: 40)
        let tall = Rect(x: 10, y: 20, width: 40, height: 80)
        let fixtures: [(Rect, Double, Double, Bool, Point, Point, Double, Double)] = [
            (wide, 0, 180, false, Point(x: 70, y: 40), Point(x: 50, y: 40), 0, .pi),
            (wide, 90, 270, true, Point(x: 50, y: 60), Point(x: 50, y: 40), .pi / 2, 3 * .pi / 2),
            (tall, 0, 180, true, Point(x: 50, y: 60), Point(x: 30, y: 60), 0, .pi),
            (tall, 90, 270, false, Point(x: 30, y: 80), Point(x: 30, y: 60), .pi / 2, 3 * .pi / 2),
        ]
        for (rect, start, end, clockwise, move, center, startRadians, endRadians) in fixtures {
            let path = arc(start: start, end: end, clockwise: clockwise).path(in: rect)
            assertArc(
                path.elements, move: move, center: center, radius: 20,
                start: startRadians, end: endRadians, clockwise: clockwise)
        }
    }

    func testWideArcStoresNormalizedMoveAndRadius() async throws {
        let result = snapshot(arc().fill(Self.red, style: Self.evenOdd).frame(width: 80, height: 40))
        let owner = try pathOwner(in: result.runtime.root)
        XCTAssertEqual(owner.resolvedFrame, Rect(x: 0, y: 0, width: 80, height: 40))
        assertPaint(owner, fill: Self.red)
        assertWrappersClear(in: result.runtime.root, owner: owner)
        assertArc(
            try XCTUnwrap(owner.backgroundPath),
            move: Point(x: 0.75, y: 0.5), center: Point(x: 0.5, y: 0.5), radius: 0.25)
        let fill = try fillCommand(in: result.frame, color: Self.red)
        assertArc(fill.path, move: Point(x: 60, y: 20), center: Point(x: 40, y: 20), radius: 20)
        let sceneFill = try residualFill(in: result.scene, color: Self.red)
        assertArc(sceneFill.elements, move: Point(x: 60, y: 20), center: Point(x: 40, y: 20), radius: 20)
        assertCoverage(result, probes: [(40, 30, .red), (40, 10, .clear), (10, 30, .clear)])
    }

    func testTallArcKeepsMoveOnCircularStart() async throws {
        let tall = IntSize(width: 40, height: 80)
        let result = snapshot(
            arc(start: 90, end: 270).fill(Self.red, style: Self.evenOdd).frame(width: 40, height: 80), size: tall)
        let owner = try pathOwner(in: result.runtime.root)
        XCTAssertEqual(owner.resolvedFrame, Rect(x: 0, y: 0, width: 40, height: 80))
        assertArc(
            try XCTUnwrap(owner.backgroundPath),
            move: Point(x: 0.5, y: 0.75), center: Point(x: 0.5, y: 0.5), radius: 0.25,
            start: .pi / 2, end: 3 * .pi / 2)
        let fill = try fillCommand(in: result.frame, color: Self.red)
        assertArc(
            fill.path, move: Point(x: 20, y: 60), center: Point(x: 20, y: 40), radius: 20,
            start: .pi / 2, end: 3 * .pi / 2)
        assertCoverage(result, probes: [(10, 40, .red), (30, 40, .clear), (10, 5, .clear)])

        // The 45-degree start on a radius-20 circle is independently
        // (20 + 20 / sqrt(2), 40 + 20 / sqrt(2)); it is not a unit-circle move.
        let diagonal = 2.0.squareRoot() / 2
        let angled = snapshot(
            arc(start: 45, end: 225).fill(Self.red, style: Self.evenOdd).frame(width: 40, height: 80), size: tall)
        let angledOwner = try pathOwner(in: angled.runtime.root)
        XCTAssertEqual(angledOwner.resolvedFrame, Rect(x: 0, y: 0, width: 40, height: 80))
        assertArc(
            try XCTUnwrap(angledOwner.backgroundPath),
            move: Point(x: 0.5 + 0.5 * diagonal, y: 0.5 + 0.25 * diagonal),
            center: Point(x: 0.5, y: 0.5), radius: 0.25, start: .pi / 4, end: 5 * .pi / 4)
        let angledFill = try fillCommand(in: angled.frame, color: Self.red)
        assertArc(
            angledFill.path, move: Point(x: 20 + 20 * diagonal, y: 40 + 20 * diagonal),
            center: Point(x: 20, y: 40), radius: 20, start: .pi / 4, end: 5 * .pi / 4)
        assertCoverage(angled, probes: [(10, 45, .red), (30, 35, .clear), (2, 5, .clear)])
    }

    func testLayoutOriginAndTranslationAreAppliedOnce() async throws {
        let fixtures: [(Double, Double, Point, Point, [Probe])] = [
            (0, 0, Point(x: 50, y: 40), Point(x: 70, y: 40), [(50, 50, .red), (50, 30, .clear), (20, 50, .clear)]),
            (7, 5, Point(x: 57, y: 45), Point(x: 77, y: 45), [(57, 55, .red), (57, 35, .clear), (27, 55, .clear)]),
        ]
        for (x, y, center, move, probes) in fixtures {
            let result = snapshot(
                padded(arc().fill(Self.red, style: Self.evenOdd).offset(x: x, y: y)), size: Self.paddedSize)
            let owner = try pathOwner(in: result.runtime.root)
            XCTAssertEqual(owner.resolvedFrame, Rect(x: 10, y: 20, width: 80, height: 40))
            assertPaint(owner, fill: Self.red)
            assertWrappersClear(in: result.runtime.root, owner: owner)
            assertArc(
                try XCTUnwrap(owner.backgroundPath),
                move: Point(x: 0.75, y: 0.5), center: Point(x: 0.5, y: 0.5), radius: 0.25)
            let fill = try fillCommand(in: result.frame, color: Self.red)
            assertArc(fill.path, move: move, center: center, radius: 20)
            let sceneFill = try residualFill(in: result.scene, color: Self.red)
            assertArc(sceneFill.elements, move: move, center: center, radius: 20)
            assertCoverage(result, probes: probes)
        }
    }

    func testFillCoverageMatchesAnalyticSemicircle() async throws {
        for evenOdd in [false, true] {
            let result = snapshot(
                padded(arc().fill(Self.red, style: FillStyle(eoFill: evenOdd))), size: Self.paddedSize)
            let owner = try pathOwner(in: result.runtime.root)
            XCTAssertEqual(owner.resolvedFrame, Rect(x: 10, y: 20, width: 80, height: 40))
            assertPaint(owner, fill: Self.red, evenOdd: evenOdd)
            assertWrappersClear(in: result.runtime.root, owner: owner)
            assertArc(
                try XCTUnwrap(owner.backgroundPath),
                move: Point(x: 0.75, y: 0.5), center: Point(x: 0.5, y: 0.5), radius: 0.25)
            let fill = try fillCommand(in: result.frame, color: Self.red, evenOdd: evenOdd)
            assertArc(fill.path, move: Point(x: 70, y: 40), center: Point(x: 50, y: 40), radius: 20)
            XCTAssertTrue(strokeCommands(in: result.frame).isEmpty)
            // Positive coverage prevents two equally blank images from
            // passing; these points are away from the chord and circular edge.
            assertCoverage(result, probes: [(50, 50, .red), (50, 30, .clear), (20, 50, .clear)])
        }
    }

    func testStrokeUsesInnerRectAndLeavesClosingChordClear() async throws {
        let style = stroke(width: 4)
        let result = snapshot(padded(arc().stroke(Self.blue, style: style)), size: Self.paddedSize)
        let owner = try pathOwner(in: result.runtime.root)
        XCTAssertEqual(owner.resolvedFrame, Rect(x: 10, y: 20, width: 80, height: 40))
        assertPaint(owner, fill: .clear, stroke: Self.blue, style: style, evenOdd: nil)
        assertWrappersClear(in: result.runtime.root, owner: owner)
        assertArc(
            try XCTUnwrap(owner.backgroundPath),
            move: Point(x: 13.0 / 18, y: 0.5), center: Point(x: 0.5, y: 0.5), radius: 2.0 / 9)
        XCTAssertTrue(fillCommands(in: result.frame).isEmpty)
        let command = try strokeCommand(in: result.frame, color: Self.blue, style: style)
        assertArc(command.path, move: Point(x: 66, y: 40), center: Point(x: 50, y: 40), radius: 16)
        assertCoverage(
            result, probes: [(50, 56, .blue), (50, 48, .clear), (49, 39, .clear), (77, 39, .clear)])
    }

    func testLiveStrokeWidthRenormalizesAtSameSize() async throws {
        let runtime = RetainedViewRuntime(clearColor: .clear, root: ViewNode())
        runtime.setRootSize(Self.wide)
        let host = ComponentHost(runtime: runtime)
        let context = ViewBuildContext(canvasSizeProvider: { Size(width: 80, height: 40) }, invalidateHandler: {})
        var width = 2.0
        host.setComponents {
            [
                self.arc(start: 90, end: 270).stroke(Self.blue, style: self.stroke(width: width))
                    .frame(width: 80, height: 40).makeComponent(context: context)
            ]
        }
        var retainedOwner: ViewNode?
        let stages: [(Double, Double, Double, Double, Int)] = [
            (2, 18, 9.0 / 38, 38, 22), (4, 16, 2.0 / 9, 36, 24), (2, 18, 9.0 / 38, 38, 22),
        ]
        for (index, stage) in stages.enumerated() {
            let (nextWidth, radius, normalizedRadius, startY, strokeX) = stage
            width = nextWidth
            if index > 0 {
                host.reload()
                XCTAssertTrue(runtime.hasPendingLayout)
            }
            let result = capture(runtime, size: Self.wide, time: Double(index))
            let owner = try pathOwner(in: runtime.root)
            if let retainedOwner { XCTAssertTrue(owner === retainedOwner) } else { retainedOwner = owner }
            XCTAssertEqual(owner.resolvedFrame, Rect(x: 0, y: 0, width: 80, height: 40))
            XCTAssertNotNil(owner.onLayoutWithNode)
            assertPaint(owner, fill: .clear, stroke: Self.blue, style: stroke(width: nextWidth), evenOdd: nil)
            assertWrappersClear(in: runtime.root, owner: owner)
            assertArc(
                try XCTUnwrap(owner.backgroundPath),
                move: Point(x: 0.5, y: 1), center: Point(x: 0.5, y: 0.5), radius: normalizedRadius,
                start: .pi / 2, end: 3 * .pi / 2)
            let command = try strokeCommand(in: result.frame, color: Self.blue, style: stroke(width: nextWidth))
            assertArc(
                command.path, move: Point(x: 40, y: startY), center: Point(x: 40, y: 20), radius: radius,
                start: .pi / 2, end: 3 * .pi / 2)
            assertCoverage(result, probes: [(strokeX, 20, .blue), (40, 20, .clear), (55, 20, .clear)])
        }

        let owner = try XCTUnwrap(retainedOwner)
        let authoredStyle = try XCTUnwrap(owner.borderStrokeStyle)
        XCTAssertEqual(authoredStyle, stroke(width: 2))
        XCTAssertFalse(runtime.hasPendingLayout)
        // Change only the live width. The installed callback and authored
        // style still come from the width-2 build, so capturing either is wrong.
        owner.borderWidth = 4
        XCTAssertTrue(runtime.hasPendingLayout)
        let liveChange = capture(runtime, size: Self.wide, time: 3)
        XCTAssertTrue(try pathOwner(in: runtime.root) === owner)
        assertPaint(owner, fill: .clear, stroke: Self.blue, style: authoredStyle, evenOdd: nil, width: 4)
        assertArc(
            try XCTUnwrap(owner.backgroundPath),
            move: Point(x: 0.5, y: 1), center: Point(x: 0.5, y: 0.5), radius: 2.0 / 9,
            start: .pi / 2, end: 3 * .pi / 2)
        let command = try strokeCommand(in: liveChange.frame, color: Self.blue, style: stroke(width: 4))
        assertArc(
            command.path, move: Point(x: 40, y: 36), center: Point(x: 40, y: 20), radius: 16,
            start: .pi / 2, end: 3 * .pi / 2)
        assertCoverage(liveChange, probes: [(24, 20, .blue), (40, 20, .clear), (55, 20, .clear)])
    }

    func testDisplayScaleChangesSceneCoordinatesExactlyOnce() async throws {
        let densities: [(Double, IntSize, Point, Point, Double)] = [
            (1, IntSize(width: 100, height: 80), Point(x: 50, y: 40), Point(x: 70, y: 40), 20),
            (1.25, IntSize(width: 125, height: 100), Point(x: 62.5, y: 50), Point(x: 87.5, y: 50), 25),
            (2, IntSize(width: 200, height: 160), Point(x: 100, y: 80), Point(x: 140, y: 80), 40),
        ]
        for (scale, pixelSize, center, move, radius) in densities {
            let result = snapshot(
                padded(arc().fill(Self.red, style: Self.evenOdd)), size: Self.paddedSize, displayScale: scale)
            let owner = try pathOwner(in: result.runtime.root)
            XCTAssertEqual(owner.resolvedFrame, Rect(x: 10, y: 20, width: 80, height: 40))
            assertPaint(owner, fill: Self.red)
            assertArc(
                try XCTUnwrap(owner.backgroundPath),
                move: Point(x: 0.75, y: 0.5), center: Point(x: 0.5, y: 0.5), radius: 0.25)
            let fill = try fillCommand(in: result.frame, color: Self.red)
            assertArc(fill.path, move: Point(x: 70, y: 40), center: Point(x: 50, y: 40), radius: 20)
            // Curved even-odd fill stays in the existing residual path lane;
            // inspecting it does not change promotion or its coordinate contract.
            let sceneFill = try residualFill(in: result.scene, color: Self.red)
            assertArc(sceneFill.elements, move: move, center: center, radius: radius)
            XCTAssertTrue(result.scene.validate().isEmpty)
            let bitmap = GPUIRawSceneRasterizer.rasterize(result.scene, size: pixelSize)
            XCTAssertEqual(bitmap.width, pixelSize.width)
            XCTAssertEqual(bitmap.height, pixelSize.height)
            assertPixels(
                bitmap,
                probes: [
                    (Int(50 * scale), Int(50 * scale), .red),
                    (Int(50 * scale), Int(30 * scale), .clear),
                    (Int(20 * scale), Int(50 * scale), .clear),
                ])
            if scale == 1 {
                assertPixels(
                    GPUIRawSceneRasterizer.rasterize(result.frame, size: Self.paddedSize),
                    probes: [(50, 50, .red), (50, 30, .clear), (20, 50, .clear)])
            }
        }
    }

    func testResizeClearsDegeneratePathAndRestoresCoverage() async throws {
        let runtime = RetainedViewRuntime(clearColor: .clear, root: ViewNode())
        var canvasSize = Self.wide
        runtime.setRootSize(canvasSize)
        let host = ComponentHost(runtime: runtime)
        let context = ViewBuildContext(
            canvasSizeProvider: { Size(width: Double(canvasSize.width), height: Double(canvasSize.height)) },
            invalidateHandler: {})
        let style = stroke(width: 4)
        host.setComponents {
            [
                AnyShape(self.arc()).stroke(Self.blue, style: style).fill(Self.green, style: Self.evenOdd)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).makeComponent(context: context)
            ]
        }
        let first = capture(runtime, size: canvasSize, time: 0)
        let owner = try pathOwner(in: runtime.root)
        XCTAssertEqual(owner.resolvedFrame, Rect(x: 0, y: 0, width: 80, height: 40))
        try assertCombinedGeometry(
            first, owner: owner, normalizedMove: Point(x: 13.0 / 18, y: 0.5),
            center: Point(x: 40, y: 20), move: Point(x: 56, y: 20))
        assertCoverage(first, probes: [(40, 28, .green), (40, 36, .blue), (40, 10, .clear)])

        canvasSize = IntSize(width: 40, height: 80)
        runtime.setRootSize(canvasSize)
        XCTAssertTrue(runtime.hasPendingLayout)
        let tall = capture(runtime, size: canvasSize, time: 1)
        XCTAssertTrue(try pathOwner(in: runtime.root) === owner)
        XCTAssertEqual(owner.resolvedFrame, Rect(x: 0, y: 0, width: 40, height: 80))
        try assertCombinedGeometry(
            tall, owner: owner, normalizedMove: Point(x: 1, y: 0.5),
            center: Point(x: 20, y: 40), move: Point(x: 36, y: 40))
        assertCoverage(tall, probes: [(20, 48, .green), (20, 56, .blue), (20, 30, .clear)])

        canvasSize = IntSize(width: 0, height: 40)
        runtime.setRootSize(canvasSize)
        XCTAssertTrue(runtime.hasPendingLayout)
        // A positive raster surface lets us check old occupied locations, but
        // only the explicit nonnil empty path proves the layout callback ran.
        let collapsed = capture(runtime, size: Self.paddedSize, time: 2)
        XCTAssertTrue(try pathOwner(in: runtime.root) === owner)
        XCTAssertEqual(owner.resolvedFrame, Rect(x: 0, y: 0, width: 0, height: 40))
        XCTAssertTrue(try XCTUnwrap(owner.backgroundPath).segments.isEmpty)
        assertPaint(owner, fill: Self.green, stroke: Self.blue, style: style)
        assertNoCoverage(collapsed)

        canvasSize = Self.wide
        runtime.setRootSize(canvasSize)
        let restored = capture(runtime, size: canvasSize, time: 3)
        XCTAssertTrue(try pathOwner(in: runtime.root) === owner)
        XCTAssertEqual(owner.resolvedFrame, Rect(x: 0, y: 0, width: 80, height: 40))
        try assertCombinedGeometry(
            restored, owner: owner, normalizedMove: Point(x: 13.0 / 18, y: 0.5),
            center: Point(x: 40, y: 20), move: Point(x: 56, y: 20))
        assertCoverage(restored, probes: [(40, 28, .green), (40, 36, .blue), (40, 10, .clear)])

        // This collapse has a positive outer viewport; an empty path must
        // suppress both stale Arc coverage and fallback rectangular painting.
        owner.borderWidth = 20
        XCTAssertTrue(runtime.hasPendingLayout)
        let innerCollapsed = capture(runtime, size: canvasSize, time: 4)
        XCTAssertTrue(try pathOwner(in: runtime.root) === owner)
        XCTAssertEqual(owner.resolvedFrame, Rect(x: 0, y: 0, width: 80, height: 40))
        XCTAssertTrue(try XCTUnwrap(owner.backgroundPath).segments.isEmpty)
        assertPaint(owner, fill: Self.green, stroke: Self.blue, style: style, width: 20)
        assertNoCoverage(innerCollapsed)

        owner.borderWidth = 4
        XCTAssertTrue(runtime.hasPendingLayout)
        let recovered = capture(runtime, size: canvasSize, time: 5)
        XCTAssertTrue(try pathOwner(in: runtime.root) === owner)
        try assertCombinedGeometry(
            recovered, owner: owner, normalizedMove: Point(x: 13.0 / 18, y: 0.5),
            center: Point(x: 40, y: 20), move: Point(x: 56, y: 20))
        assertCoverage(recovered, probes: [(40, 28, .green), (40, 36, .blue), (40, 10, .clear)])
    }

    func testMountedAngleAndDirectionChangeUpdatesVisibleHalf() async throws {
        let runtime = RetainedViewRuntime(clearColor: .clear, root: ViewNode())
        runtime.setRootSize(Self.wide)
        let host = ComponentHost(runtime: runtime)
        let context = ViewBuildContext(canvasSizeProvider: { Size(width: 80, height: 40) }, invalidateHandler: {})
        var start = 0.0
        var end = 180.0
        var clockwise = false
        host.setComponents {
            [
                AnyShape(self.arc(start: start, end: end, clockwise: clockwise))
                    .fill(Self.red, style: Self.evenOdd).frame(width: 80, height: 40)
                    .makeComponent(context: context)
            ]
        }
        var retainedOwner: ViewNode?
        let stages: [(Double, Double, Bool, Double, Double, Double, Double, Bool)] = [
            (0, 180, false, 0, .pi, 0.75, 60, true),
            (0, 180, true, 0, .pi, 0.75, 60, false),
            (180, 360, true, .pi, 2 * .pi, 0.25, 20, true),
            (180, 360, false, .pi, 2 * .pi, 0.25, 20, false),
            (0, 180, false, 0, .pi, 0.75, 60, true),
        ]
        for (index, stage) in stages.enumerated() {
            let (nextStart, nextEnd, nextClockwise, startRadians, endRadians, normalizedX, moveX, lowerHalf) = stage
            start = nextStart
            end = nextEnd
            clockwise = nextClockwise
            if index > 0 {
                host.reload()
                XCTAssertTrue(runtime.hasPendingLayout)
            }
            let result = capture(runtime, size: Self.wide, time: Double(index))
            let owner = try pathOwner(in: runtime.root)
            if let retainedOwner { XCTAssertTrue(owner === retainedOwner) } else { retainedOwner = owner }
            XCTAssertEqual(owner.resolvedFrame, Rect(x: 0, y: 0, width: 80, height: 40))
            assertPaint(owner, fill: Self.red)
            assertWrappersClear(in: runtime.root, owner: owner)
            assertArc(
                try XCTUnwrap(owner.backgroundPath),
                move: Point(x: normalizedX, y: 0.5), center: Point(x: 0.5, y: 0.5), radius: 0.25,
                start: startRadians, end: endRadians, clockwise: nextClockwise)
            let fill = try fillCommand(in: result.frame, color: Self.red)
            assertArc(
                fill.path, move: Point(x: moveX, y: 20), center: Point(x: 40, y: 20), radius: 20,
                start: startRadians, end: endRadians, clockwise: nextClockwise)
            let sceneFill = try residualFill(in: result.scene, color: Self.red)
            assertArc(
                sceneFill.elements, move: Point(x: moveX, y: 20), center: Point(x: 40, y: 20), radius: 20,
                start: startRadians, end: endRadians, clockwise: nextClockwise)
            assertCoverage(
                result,
                probes: [
                    (40, 30, lowerHalf ? .red : .clear), (40, 10, lowerHalf ? .clear : .red),
                    (10, 30, .clear),
                ])
        }
    }

    func testErasedInsetCombinedPaintKeepsIndependentCoverage() async throws {
        let style = stroke(width: 4)
        let size = IntSize(width: 100, height: 60)
        let positions: [(Double, Double, Point, Point, [Probe])] = [
            (0, 0, Point(x: 50, y: 30), Point(x: 66, y: 30), [(50, 38, .green), (50, 46, .blue), (50, 20, .clear)]),
            (7, 5, Point(x: 57, y: 35), Point(x: 73, y: 35), [(57, 43, .green), (57, 51, .blue), (57, 25, .clear)]),
        ]
        for erasedInset in [false, true] {
            for (x, y, center, move, probes) in positions {
                let content: AnyView
                if erasedInset {
                    content = AnyView(
                        AnyShape(InsetShape(arc(), amount: 10)).stroke(Self.blue, style: style)
                            .fill(Self.green, style: Self.evenOdd))
                } else {
                    content = AnyView(
                        arc().stroke(Self.blue, style: style).fill(Self.green, style: Self.evenOdd).padding(10))
                }
                let result = snapshot(content.frame(width: 100, height: 60).offset(x: x, y: y), size: size)
                let owner = try pathOwner(in: result.runtime.root)
                XCTAssertEqual(owner.resolvedFrame, Rect(x: 10, y: 10, width: 80, height: 40))
                try assertCombinedGeometry(
                    result, owner: owner, normalizedMove: Point(x: 13.0 / 18, y: 0.5), center: center, move: move)
                assertCoverage(result, probes: probes)
            }
        }
    }

    func testUnborderedUniformScaleUsesExistingPlacement() async throws {
        // scaleEffect's anchor overload is not implemented. Center the child
        // explicitly to test existing uniform placement without claiming it is.
        let result = snapshot(
            arc().fill(Self.red, style: Self.evenOdd).frame(width: 80, height: 40)
                .scaleEffect(2).frame(width: 160, height: 80, alignment: .center),
            size: IntSize(width: 160, height: 80))
        let owner = try pathOwner(in: result.runtime.root)
        XCTAssertEqual(owner.resolvedFrame, Rect(x: 0, y: 0, width: 80, height: 40))
        let transformedNodes = descendants(of: result.runtime.root).filter { $0.transform != .identity }
        XCTAssertEqual(transformedNodes.count, 1)
        let innerFrame = try XCTUnwrap(transformedNodes.first)
        XCTAssertFalse(innerFrame === owner)
        XCTAssertEqual(innerFrame.resolvedFrame, Rect(x: 40, y: 20, width: 80, height: 40))
        XCTAssertEqual(innerFrame.transform, .scale(x: 2, y: 2))
        assertPaint(owner, fill: Self.red)
        assertWrappersClear(in: result.runtime.root, owner: owner)
        assertArc(
            try XCTUnwrap(owner.backgroundPath),
            move: Point(x: 0.75, y: 0.5), center: Point(x: 0.5, y: 0.5), radius: 0.25)
        let sceneFill = try residualFill(in: result.scene, color: Self.red)
        assertArc(sceneFill.elements, move: Point(x: 120, y: 40), center: Point(x: 80, y: 40), radius: 40)
        let fill = try fillCommand(in: result.frame, color: Self.red)
        assertArc(fill.path, move: Point(x: 120, y: 40), center: Point(x: 80, y: 40), radius: 40)
        assertCoverage(result, probes: [(80, 60, .red), (80, 20, .clear), (10, 60, .clear)])
    }

    private func arc(start: Double = 0, end: Double = 180, clockwise: Bool = false) -> Arc {
        Arc(startAngle: .degrees(start), endAngle: .degrees(end), clockwise: clockwise)
    }

    private func stroke(width: Double) -> StrokeStyle {
        StrokeStyle(lineWidth: width, dashPattern: [], lineCap: .butt, lineJoin: .miter, miterLimit: 10)
    }

    private func padded<V: View>(_ view: V) -> some View {
        view.padding(EdgeInsets(top: 20, leading: 10, bottom: 20, trailing: 10)).frame(width: 100, height: 80)
    }

    private func snapshot<V: View>(
        _ view: V, size: IntSize = IntSize(width: 80, height: 40), displayScale: Double = 1
    ) -> WinSwiftUIRenderSnapshot {
        WinSwiftUIRendererSnapshotter.snapshot(of: view, size: size, displayScale: displayScale, clearColor: .clear)
    }

    private func capture(_ runtime: RetainedViewRuntime, size: IntSize, time: Double) -> WinSwiftUIRenderSnapshot {
        let scene = runtime.renderScene(at: time)
        let frame = runtime.renderFrame(at: time)
        return WinSwiftUIRenderSnapshot(runtime: runtime, frame: frame, scene: scene, size: size, displayScale: 1)
    }

    private func descendants(of root: ViewNode) -> [ViewNode] {
        [root] + root.children.flatMap { descendants(of: $0) }
    }

    private func pathOwner(in root: ViewNode, file: StaticString = #filePath, line: UInt = #line) throws -> ViewNode {
        let owners = descendants(of: root).filter { $0.backgroundPath != nil }
        XCTAssertEqual(
            owners.count, 1, "exactly one path owner, including a collapsed empty path", file: file, line: line)
        let owner = try XCTUnwrap(owners.first, file: file, line: line)
        XCTAssertTrue(owner.children.isEmpty, file: file, line: line)
        return owner
    }

    private func assertPaint(
        _ owner: ViewNode, fill: Color, stroke: Color = .clear, style: StrokeStyle? = nil,
        evenOdd: Bool? = true, width: Double? = nil, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(owner.backgroundColor, fill, file: file, line: line)
        XCTAssertNil(owner.backgroundGradient, file: file, line: line)
        XCTAssertEqual(owner.borderColor, stroke, file: file, line: line)
        XCTAssertNil(owner.borderGradient, file: file, line: line)
        XCTAssertEqual(owner.borderWidth, width ?? style?.lineWidth ?? 0, file: file, line: line)
        XCTAssertEqual(owner.borderStrokeStyle, style, file: file, line: line)
        XCTAssertEqual(owner.clipFillStyle, evenOdd.map { RetainedClipFillStyle(eoFill: $0) }, file: file, line: line)
    }

    private func assertWrappersClear(
        in root: ViewNode, owner: ViewNode, file: StaticString = #filePath, line: UInt = #line
    ) {
        for wrapper in descendants(of: root) where wrapper !== owner {
            XCTAssertTrue(wrapper.backgroundColor == nil || wrapper.backgroundColor == .clear, file: file, line: line)
            XCTAssertNil(wrapper.backgroundGradient, file: file, line: line)
            XCTAssertEqual(wrapper.borderColor, .clear, file: file, line: line)
            XCTAssertNil(wrapper.borderGradient, file: file, line: line)
            XCTAssertEqual(wrapper.borderWidth, 0, file: file, line: line)
            XCTAssertNil(wrapper.borderStrokeStyle, file: file, line: line)
            XCTAssertNil(wrapper.clipFillStyle, file: file, line: line)
        }
    }

    private func fillCommands(in frame: RenderFrame) -> [FillPathCommand] {
        frame.commands.compactMap {
            guard case .fillPath(let command) = $0 else { return nil }
            return command
        }
    }

    private func strokeCommands(in frame: RenderFrame) -> [StrokePathCommand] {
        frame.commands.compactMap {
            guard case .strokePath(let command) = $0 else { return nil }
            return command
        }
    }

    private func fillCommand(
        in frame: RenderFrame, color: Color, evenOdd: Bool = true,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> FillPathCommand {
        let commands = fillCommands(in: frame)
        XCTAssertEqual(commands.count, 1, file: file, line: line)
        let command = try XCTUnwrap(commands.first, file: file, line: line)
        XCTAssertEqual(command.color, color, file: file, line: line)
        XCTAssertEqual(command.fillRule, evenOdd ? .evenOdd : .nonZero, file: file, line: line)
        XCTAssertNil(command.gradient, file: file, line: line)
        return command
    }

    private func strokeCommand(
        in frame: RenderFrame, color: Color, style: StrokeStyle,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> StrokePathCommand {
        let commands = strokeCommands(in: frame)
        XCTAssertEqual(commands.count, 1, file: file, line: line)
        let command = try XCTUnwrap(commands.first, file: file, line: line)
        XCTAssertEqual(command.color, color, file: file, line: line)
        XCTAssertEqual(command.style, style, file: file, line: line)
        return command
    }

    private func residualFill(
        in scene: GPUIScene, color: Color, file: StaticString = #filePath, line: UInt = #line
    ) throws -> PathPrimitive {
        let fills = scene.layers.flatMap(\.paths).filter { $0.fillColor.alpha > 0 }
        XCTAssertEqual(fills.count, 1, "curved even-odd fill retains its residual path", file: file, line: line)
        let fill = try XCTUnwrap(fills.first, file: file, line: line)
        XCTAssertEqual(fill.fillColor, color, file: file, line: line)
        XCTAssertEqual(fill.fillRule, .evenOdd, file: file, line: line)
        XCTAssertNil(fill.fillGradient, file: file, line: line)
        return fill
    }

    private func assertCombinedGeometry(
        _ result: WinSwiftUIRenderSnapshot, owner: ViewNode, normalizedMove: Point, center: Point, move: Point,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let style = stroke(width: 4)
        assertPaint(owner, fill: Self.green, stroke: Self.blue, style: style, file: file, line: line)
        assertWrappersClear(in: result.runtime.root, owner: owner, file: file, line: line)
        assertArc(
            try XCTUnwrap(owner.backgroundPath, file: file, line: line),
            move: normalizedMove, center: Point(x: 0.5, y: 0.5), radius: 2.0 / 9, file: file, line: line)
        let fill = try fillCommand(in: result.frame, color: Self.green, file: file, line: line)
        assertArc(fill.path, move: move, center: center, radius: 16, file: file, line: line)
        let command = try strokeCommand(in: result.frame, color: Self.blue, style: style, file: file, line: line)
        assertArc(command.path, move: move, center: center, radius: 16, file: file, line: line)
        let sceneFill = try residualFill(in: result.scene, color: Self.green, file: file, line: line)
        assertArc(sceneFill.elements, move: move, center: center, radius: 16, file: file, line: line)
    }

    private func assertArc(
        _ path: RenderPath, move: Point, center: Point, radius: Double,
        start: Double = 0, end: Double = .pi, clockwise: Bool = false,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(
            path.segments.count, 2, "one move and one open arc, with no connector or close", file: file, line: line)
        guard path.segments.count == 2,
            case .moveTo(let actualMove) = path.segments[0],
            case .arc(let actualCenter, let actualRadius, let actualStart, let actualEnd, let actualClockwise) =
                path.segments[1]
        else {
            XCTFail("expected exactly a move followed by an open arc", file: file, line: line)
            return
        }
        assertGeometry(
            actualMove: actualMove, actualCenter: actualCenter, actualRadius: actualRadius,
            actualStart: actualStart, actualEnd: actualEnd, actualClockwise: actualClockwise,
            move: move, center: center, radius: radius, start: start, end: end, clockwise: clockwise,
            file: file, line: line)
    }

    private func assertArc(
        _ elements: [PathElement], move: Point, center: Point, radius: Double,
        start: Double = 0, end: Double = .pi, clockwise: Bool = false,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(
            elements.count, 2, "one move and one open arc, with no connector or close", file: file, line: line)
        guard elements.count == 2,
            case .moveTo(let actualMove) = elements[0],
            case .arc(let actualCenter, let actualRadius, let actualStart, let actualEnd, let actualClockwise) =
                elements[1]
        else {
            XCTFail("expected exactly a move followed by an open arc", file: file, line: line)
            return
        }
        assertGeometry(
            actualMove: actualMove, actualCenter: actualCenter, actualRadius: actualRadius,
            actualStart: actualStart, actualEnd: actualEnd, actualClockwise: actualClockwise,
            move: move, center: center, radius: radius, start: start, end: end, clockwise: clockwise,
            file: file, line: line)
    }

    private func assertGeometry(
        actualMove: Point, actualCenter: Point, actualRadius: Double,
        actualStart: Double, actualEnd: Double, actualClockwise: Bool,
        move: Point, center: Point, radius: Double, start: Double, end: Double, clockwise: Bool,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(
            [actualMove.x, actualMove.y, actualCenter.x, actualCenter.y, actualRadius, actualStart, actualEnd]
                .allSatisfy(\.isFinite), file: file, line: line)
        XCTAssertEqual(actualMove.x, move.x, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(actualMove.y, move.y, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(actualCenter.x, center.x, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(actualCenter.y, center.y, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(actualRadius, radius, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(actualStart, start, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(actualEnd, end, accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(actualClockwise, clockwise, file: file, line: line)
    }

    private func assertCoverage(
        _ result: WinSwiftUIRenderSnapshot, probes: [Probe], file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(result.displayScale, 1, "frame pixel probes use logical 1x surfaces", file: file, line: line)
        XCTAssertTrue(
            probes.contains { $0.color != .clear }, "require visible positive coverage", file: file, line: line)
        XCTAssertTrue(result.scene.validate().isEmpty, file: file, line: line)
        assertPixels(
            GPUIRawSceneRasterizer.rasterize(result.scene, size: result.size), probes: probes, file: file, line: line)
        assertPixels(
            GPUIRawSceneRasterizer.rasterize(result.frame, size: result.size), probes: probes, file: file, line: line)
    }

    private func assertNoCoverage(
        _ result: WinSwiftUIRenderSnapshot, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(result.frame.commands.isEmpty, "no stale path or fallback rectangle", file: file, line: line)
        XCTAssertEqual(result.scene.primitiveCount, 0, file: file, line: line)
        XCTAssertTrue(result.scene.validate().isEmpty, file: file, line: line)
        let probes: [Probe] = [(40, 28, .clear), (40, 36, .clear), (20, 48, .clear)]
        let positiveSize = Self.paddedSize
        assertPixels(
            GPUIRawSceneRasterizer.rasterize(result.scene, size: positiveSize), probes: probes, file: file, line: line)
        assertPixels(
            GPUIRawSceneRasterizer.rasterize(result.frame, size: positiveSize), probes: probes, file: file, line: line)
    }

    private func assertPixels(
        _ bitmap: BitmapSurface, probes: [Probe], file: StaticString = #filePath, line: UInt = #line
    ) {
        for (x, y, color) in probes {
            guard x >= 0, y >= 0, x < Int(bitmap.width), y < Int(bitmap.height) else {
                XCTFail("pixel (\(x), \(y)) is outside the raster", file: file, line: line)
                continue
            }
            let offset = y * Int(bitmap.bytesPerRow) + x * 4
            guard offset + 4 <= bitmap.pixels.count else {
                XCTFail("pixel (\(x), \(y)) is outside the byte buffer", file: file, line: line)
                continue
            }
            XCTAssertEqual(
                Array(bitmap.pixels[offset..<(offset + 4)]), color.bgra,
                "exact BGRA pixel at (\(x), \(y))", file: file, line: line)
        }
    }
}
