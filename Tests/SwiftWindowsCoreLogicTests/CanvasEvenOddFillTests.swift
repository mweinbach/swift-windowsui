import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Canvas fill rules must survive recording, retained placement and the
/// readable frame fallback. Interior samples distinguish the requested rule
/// independently of any CPU/GPU comparison.
@MainActor
final class CanvasEvenOddFillTests: XCTestCase {
    private static let size = IntSize(width: 64, height: 64)
    private static let red = Color(red: 1, green: 0, blue: 0, alpha: 1)
    private static let green = Color(red: 0, green: 1, blue: 0, alpha: 1)
    private static let blue = Color(red: 0, green: 0, blue: 1, alpha: 1)

    private static func nestedPath(reversesInner: Bool = false, closesSubpaths: Bool = true) -> Path {
        var path = Path()
        path.moveTo(Point(x: 8, y: 8))
        path.lineTo(Point(x: 56, y: 8))
        path.lineTo(Point(x: 56, y: 56))
        path.lineTo(Point(x: 8, y: 56))
        if closesSubpaths { path.close() }

        path.moveTo(Point(x: 20, y: 20))
        if reversesInner {
            path.lineTo(Point(x: 20, y: 44))
            path.lineTo(Point(x: 44, y: 44))
            path.lineTo(Point(x: 44, y: 20))
        } else {
            path.lineTo(Point(x: 44, y: 20))
            path.lineTo(Point(x: 44, y: 44))
            path.lineTo(Point(x: 20, y: 44))
        }
        if closesSubpaths { path.close() }
        return path
    }

    private func snapshot<V: View>(
        _ view: V,
        size: IntSize = IntSize(width: 64, height: 64),
        displayScale: Double = 1
    ) -> WinSwiftUIRenderSnapshot {
        WinSwiftUIRendererSnapshotter.snapshot(
            of: view, size: size, displayScale: displayScale, clearColor: .clear)
    }

    private func filledSnapshot(
        path: Path,
        style: FillStyle? = nil,
        shading: WinSwiftUI.GraphicsContext.Shading = .color(.white),
        contextOpacity: Double = 1,
        viewOpacity: Double = 1,
        transform: CGAffineTransform = .identity,
        clip: Rect? = nil,
        size: IntSize = IntSize(width: 64, height: 64),
        displayScale: Double = 1
    ) -> WinSwiftUIRenderSnapshot {
        snapshot(
            Canvas { context, _ in
                context.opacity = contextOpacity
                context.transform = transform
                if let clip { context.clip(to: clip) }
                if let style {
                    context.fill(path, with: shading, style: style)
                } else {
                    context.fill(path, with: shading)
                }
            }
            .frame(width: Double(size.width), height: Double(size.height))
            .opacity(viewOpacity),
            size: size,
            displayScale: displayScale
        )
    }

    private func raster(_ snapshot: WinSwiftUIRenderSnapshot) -> BitmapSurface {
        GPUIRawSceneRasterizer.rasterize(
            snapshot.scene,
            size: IntSize(
                width: Int32(Double(snapshot.size.width) * snapshot.displayScale),
                height: Int32(Double(snapshot.size.height) * snapshot.displayScale))
        )
    }

    private func pixel(
        _ surface: BitmapSurface, x: Int, y: Int
    ) -> (red: Int, green: Int, blue: Int, alpha: Int) {
        let offset = y * Int(surface.bytesPerRow) + x * 4
        return (
            red: Int(surface.pixels[offset + 2]),
            green: Int(surface.pixels[offset + 1]),
            blue: Int(surface.pixels[offset]),
            alpha: Int(surface.pixels[offset + 3])
        )
    }

    private func fills(in frame: RenderFrame) -> [FillPathCommand] {
        frame.commands.compactMap { command in
            guard case .fillPath(let fill) = command else { return nil }
            return fill
        }
    }

    private func assertRingAndHole(
        _ surface: BitmapSurface, ringAlpha: Int, holeAlpha: Int,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(pixel(surface, x: 12, y: 32).alpha, ringAlpha, accuracy: 1, file: file, line: line)
        XCTAssertEqual(pixel(surface, x: 52, y: 32).alpha, ringAlpha, accuracy: 1, file: file, line: line)
        XCTAssertEqual(pixel(surface, x: 32, y: 12).alpha, ringAlpha, accuracy: 1, file: file, line: line)
        XCTAssertEqual(pixel(surface, x: 32, y: 52).alpha, ringAlpha, accuracy: 1, file: file, line: line)
        XCTAssertEqual(pixel(surface, x: 32, y: 32).alpha, holeAlpha, accuracy: 1, file: file, line: line)
        XCTAssertEqual(pixel(surface, x: 4, y: 32).alpha, 0, file: file, line: line)
    }

    func testDefaultAndExplicitNonZeroKeepSameWindingContoursSolid() async throws {
        let path = Self.nestedPath()
        let defaultFill = filledSnapshot(path: path)
        let nonZero = filledSnapshot(path: path, style: FillStyle(eoFill: false))
        let evenOdd = filledSnapshot(path: path, style: FillStyle(eoFill: true))
        let defaultPixels = raster(defaultFill)
        let nonZeroPixels = raster(nonZero)
        let evenOddPixels = raster(evenOdd)

        XCTAssertEqual(defaultPixels.pixels, nonZeroPixels.pixels)
        assertRingAndHole(defaultPixels, ringAlpha: 255, holeAlpha: 255)
        assertRingAndHole(evenOddPixels, ringAlpha: 255, holeAlpha: 0)
        XCTAssertEqual(try XCTUnwrap(defaultFill.scene.layers.flatMap(\.paths).first).fillRule, .nonZero)
        XCTAssertEqual(try XCTUnwrap(nonZero.scene.layers.flatMap(\.paths).first).fillRule, .nonZero)
        XCTAssertEqual(try XCTUnwrap(evenOdd.scene.layers.flatMap(\.paths).first).fillRule, .evenOdd)
        XCTAssertEqual(fills(in: defaultFill.frame).map(\.fillRule), [.nonZero])
        XCTAssertEqual(fills(in: evenOdd.frame).map(\.fillRule), [.evenOdd])
    }

    func testOppositeWindingContoursRemainHolesForBothRules() async {
        let path = Self.nestedPath(reversesInner: true)
        let nonZero = raster(filledSnapshot(path: path, style: FillStyle(eoFill: false)))
        let evenOdd = raster(filledSnapshot(path: path, style: FillStyle(eoFill: true)))

        assertRingAndHole(nonZero, ringAlpha: 255, holeAlpha: 0)
        assertRingAndHole(evenOdd, ringAlpha: 255, holeAlpha: 0)
        XCTAssertEqual(evenOdd.pixels, nonZero.pixels)
    }

    func testSelfIntersectingStarUsesParityAtItsDoubleWoundCenter() async {
        // One contour crosses itself: the center has winding two, while the
        // upper tip has winding one. Treating this as a simple polygon, or
        // only looking at the number of subpaths, loses that distinction.
        var path = Path()
        path.moveTo(Point(x: 32, y: 4))
        path.lineTo(Point(x: 48, y: 56))
        path.lineTo(Point(x: 4, y: 24))
        path.lineTo(Point(x: 60, y: 24))
        path.lineTo(Point(x: 16, y: 56))
        path.close()
        let nonZero = raster(filledSnapshot(path: path))
        let evenOdd = raster(filledSnapshot(path: path, style: FillStyle(eoFill: true)))

        XCTAssertEqual(pixel(nonZero, x: 32, y: 32).alpha, 255)
        XCTAssertEqual(pixel(evenOdd, x: 32, y: 32).alpha, 0)
        XCTAssertEqual(pixel(nonZero, x: 32, y: 12).alpha, 255)
        XCTAssertEqual(pixel(evenOdd, x: 32, y: 12).alpha, 255)
        XCTAssertEqual(pixel(nonZero, x: 4, y: 4).alpha, 0)
        XCTAssertEqual(pixel(evenOdd, x: 4, y: 4).alpha, 0)
    }

    func testEachOpenSubpathIsImplicitlyClosedUnderBothRules() async {
        let open = Self.nestedPath(closesSubpaths: false)
        let closed = Self.nestedPath()
        for evenOdd in [false, true] {
            let style = FillStyle(eoFill: evenOdd)
            let openPixels = raster(filledSnapshot(path: open, style: style))
            let closedPixels = raster(filledSnapshot(path: closed, style: style))
            XCTAssertEqual(openPixels.pixels, closedPixels.pixels, "eoFill: \(evenOdd)")
            assertRingAndHole(openPixels, ringAlpha: 255, holeAlpha: evenOdd ? 0 : 255)
        }
    }

    func testTranslucentPositionedGradientKeepsTheHoleAndPaintsTheRingOnce() async throws {
        let gradient = WinSwiftUI.Gradient(colors: [
            Color(red: 1, green: 0, blue: 0, alpha: 0.5),
            Color(red: 0, green: 0, blue: 1, alpha: 0.5),
        ])
        let shading = WinSwiftUI.GraphicsContext.Shading.linearGradient(
            gradient, startPoint: Point(x: 8, y: 32), endPoint: Point(x: 56, y: 32))
        let nonZero = filledSnapshot(path: Self.nestedPath(), shading: shading)
        let evenOdd = filledSnapshot(
            path: Self.nestedPath(), style: FillStyle(eoFill: true), shading: shading)
        let pixels = raster(evenOdd)
        let primitive = try XCTUnwrap(evenOdd.scene.layers.flatMap(\.paths).first)

        XCTAssertEqual(primitive.fillRule, .evenOdd)
        XCTAssertEqual(primitive.fillGradient?.stops.count, 2)
        assertRingAndHole(pixels, ringAlpha: 128, holeAlpha: 0)
        assertRingAndHole(raster(nonZero), ringAlpha: 128, holeAlpha: 128)
        // Raw retained bitmaps store straight alpha, so half opacity changes
        // alpha without halving these gradient color channels.
        XCTAssertEqual(pixel(pixels, x: 12, y: 32).red, 231, accuracy: 1)
        XCTAssertEqual(pixel(pixels, x: 12, y: 32).blue, 24, accuracy: 1)
        XCTAssertEqual(pixel(pixels, x: 52, y: 32).blue, 236, accuracy: 1)
        XCTAssertEqual(pixel(pixels, x: 52, y: 32).red, 19, accuracy: 1)
    }

    func testUnpositionedRuntimeGradientAlsoPreservesEvenOddCoverage() async throws {
        let path = Self.nestedPath()
        let gradient = SwiftWindowsGraphics.LinearGradient(
            startColor: Color(red: 1, green: 0, blue: 0, alpha: 0.5),
            endColor: Color(red: 0, green: 0, blue: 1, alpha: 0.5),
            axis: .horizontal)
        for evenOdd in [false, true] {
            let canvas = ViewNode(
                frame: Rect(x: 0, y: 0, width: 64, height: 64),
                canvasDraw: { context, _ in
                    context.fill(path, with: .gradient(gradient), style: FillStyle(eoFill: evenOdd))
                })
            let scene = ScenePainter.paint(
                root: canvas, clearColor: .clear, surfaceSize: Size(width: 64, height: 64))
            let primitive = try XCTUnwrap(scene.layers.flatMap(\.paths).first)
            let surface = GPUIRawSceneRasterizer.rasterize(scene, size: Self.size)

            XCTAssertEqual(primitive.fillRule, evenOdd ? .evenOdd : .nonZero)
            XCTAssertNotNil(primitive.fillGradient)
            assertRingAndHole(surface, ringAlpha: 128, holeAlpha: evenOdd ? 0 : 128)
            XCTAssertGreaterThan(pixel(surface, x: 12, y: 32).red, 220)
            XCTAssertGreaterThan(pixel(surface, x: 52, y: 32).blue, 220)
        }
    }

    func testContextAndViewOpacityMultiplyWithoutFillingTheHole() async throws {
        let shading = WinSwiftUI.GraphicsContext.Shading.color(
            Color(red: 1, green: 0, blue: 0, alpha: 0.8))
        for evenOdd in [false, true] {
            let result = filledSnapshot(
                path: Self.nestedPath(), style: FillStyle(eoFill: evenOdd), shading: shading,
                contextOpacity: 0.5, viewOpacity: 0.5)
            let primitive = try XCTUnwrap(result.scene.layers.flatMap(\.paths).first)
            XCTAssertEqual(primitive.fillColor.alpha, 0.2, accuracy: 0.0001)
            assertRingAndHole(raster(result), ringAlpha: 51, holeAlpha: evenOdd ? 0 : 51)
            XCTAssertEqual(try XCTUnwrap(fills(in: result.frame).first).color.alpha, 0.2, accuracy: 0.0001)
        }
    }

    func testAffineContextTransformPreservesTheHoleAndGradientDirection() async throws {
        let transform = CGAffineTransform(a: 1, b: 0.25, c: 0.5, d: 1, tx: 8, ty: 4)
        let gradient = WinSwiftUI.Gradient(colors: [Self.red, Self.blue])
        let shading = WinSwiftUI.GraphicsContext.Shading.linearGradient(
            gradient, startPoint: Point(x: 8, y: 32), endPoint: Point(x: 56, y: 32))
        let size = IntSize(width: 104, height: 88)
        let nonZero = filledSnapshot(
            path: Self.nestedPath(), shading: shading, transform: transform, size: size)
        let evenOdd = filledSnapshot(
            path: Self.nestedPath(), style: FillStyle(eoFill: true), shading: shading,
            transform: transform, size: size)
        let surface = raster(evenOdd)
        let primitive = try XCTUnwrap(evenOdd.scene.layers.flatMap(\.paths).first)

        // (32, 32), (12, 32), (52, 32) map to these exact interior points.
        XCTAssertEqual(primitive.fillRule, .evenOdd)
        XCTAssertEqual(pixel(surface, x: 56, y: 44).alpha, 0)
        XCTAssertEqual(pixel(raster(nonZero), x: 56, y: 44).alpha, 255)
        XCTAssertEqual(pixel(surface, x: 36, y: 39).alpha, 255)
        XCTAssertGreaterThan(pixel(surface, x: 36, y: 39).red, 220)
        XCTAssertEqual(pixel(surface, x: 76, y: 49).alpha, 255)
        XCTAssertGreaterThan(pixel(surface, x: 76, y: 49).blue, 220)
        XCTAssertEqual(pixel(surface, x: 8, y: 8).alpha, 0)
    }

    func testRetainedPlacementScaleAndDisplayScalePreserveTheCompoundRule() async throws {
        let path = Self.nestedPath()
        for evenOdd in [false, true] {
            let canvas = ViewNode(
                frame: Rect(x: 12, y: 8, width: 64, height: 64),
                canvasDraw: { context, _ in
                    context.fill(path, with: .color(.white), style: FillStyle(eoFill: evenOdd))
                },
                transform: Transform2D(scaleX: 1.5, scaleY: 1.5))
            let root = ViewNode(
                frame: Rect(x: 0, y: 0, width: 96, height: 96), children: [canvas])
            let scene = ScenePainter.paint(
                root: root, clearColor: .clear,
                surfaceSize: Size(width: 96, height: 96), displayScale: 1.5)
            let primitive = try XCTUnwrap(scene.layers.flatMap(\.paths).first)
            let surface = GPUIRawSceneRasterizer.rasterize(scene, size: IntSize(width: 144, height: 144))

            XCTAssertEqual(primitive.fillRule, evenOdd ? .evenOdd : .nonZero)
            XCTAssertEqual(primitive.bounds.minX, 12, accuracy: 0.0001)
            XCTAssertEqual(primitive.bounds.minY, 6, accuracy: 0.0001)
            XCTAssertEqual(primitive.bounds.width, 108, accuracy: 0.0001)
            XCTAssertEqual(primitive.bounds.height, 108, accuracy: 0.0001)
            XCTAssertEqual(pixel(surface, x: 21, y: 60).alpha, 255)
            XCTAssertEqual(pixel(surface, x: 66, y: 60).alpha, evenOdd ? 0 : 255)
            XCTAssertEqual(pixel(surface, x: 4, y: 60).alpha, 0)
        }
    }

    func testRectangularClipCutsTheRingWithoutClosingItsHole() async throws {
        let clip = Rect(x: 24, y: 0, width: 40, height: 64)
        let result = filledSnapshot(
            path: Self.nestedPath(), style: FillStyle(eoFill: true), clip: clip)
        let surface = raster(result)
        let fill = try XCTUnwrap(fills(in: result.frame).first)

        XCTAssertEqual(fill.fillRule, .evenOdd)
        XCTAssertEqual(fill.clipRect, clip)
        XCTAssertEqual(pixel(surface, x: 12, y: 32).alpha, 0)
        XCTAssertEqual(pixel(surface, x: 32, y: 12).alpha, 255)
        XCTAssertEqual(pixel(surface, x: 52, y: 32).alpha, 255)
        XCTAssertEqual(pixel(surface, x: 32, y: 32).alpha, 0)
        XCTAssertEqual(pixel(surface, x: 60, y: 32).alpha, 0)

        let degraded = FramePathDegradation.degradingPathsToBitmaps(in: result.frame)
        let fallback = GPUIRawSceneRasterizer.rasterize(degraded, size: Self.size)
        XCTAssertEqual(pixel(fallback, x: 12, y: 32).alpha, 0)
        XCTAssertEqual(pixel(fallback, x: 32, y: 12).alpha, 255)
        XCTAssertEqual(pixel(fallback, x: 52, y: 32).alpha, 255)
        XCTAssertEqual(pixel(fallback, x: 32, y: 32).alpha, 0)
    }

    func testCopiedContextsKeepInvocationOrderAndSourceOverAcrossRules() async {
        let path = Self.nestedPath()
        let result = snapshot(
            Canvas { context, _ in
                context.fill(Rect(x: 0, y: 0, width: 64, height: 64), with: .color(Self.red))
                var copy = context
                copy.fill(
                    path, with: .color(Color(red: 0, green: 0, blue: 1, alpha: 0.5)),
                    style: FillStyle(eoFill: true))
                context.fill(Rect(x: 24, y: 24, width: 16, height: 16), with: .color(Self.green))
                copy.fill(
                    Path(Rect(x: 28, y: 28, width: 8, height: 8)),
                    with: .color(Color(red: 1, green: 1, blue: 1, alpha: 0.5)))
            }
            .frame(width: 64, height: 64)
        )
        let degraded = FramePathDegradation.degradingPathsToBitmaps(in: result.frame)
        let surfaces = [
            raster(result),
            GPUIRawSceneRasterizer.rasterize(result.frame, size: Self.size),
            GPUIRawSceneRasterizer.rasterize(degraded, size: Self.size),
        ]

        XCTAssertEqual(fills(in: result.frame).map(\.fillRule), [.evenOdd, .nonZero])
        for surface in surfaces {
            let ring = pixel(surface, x: 12, y: 32)
            XCTAssertEqual(ring.red, 128, accuracy: 1)
            XCTAssertEqual(ring.green, 0)
            XCTAssertEqual(ring.blue, 128, accuracy: 1)
            XCTAssertEqual(ring.alpha, 255)
            let hole = pixel(surface, x: 22, y: 32)
            XCTAssertEqual(hole.red, 255)
            XCTAssertEqual(hole.blue, 0)
            XCTAssertEqual(hole.alpha, 255)
            let laterParent = pixel(surface, x: 26, y: 32)
            XCTAssertEqual(laterParent.green, 255)
            XCTAssertEqual(laterParent.red, 0)
            let laterCopy = pixel(surface, x: 32, y: 32)
            XCTAssertEqual(laterCopy.red, 128, accuracy: 1)
            XCTAssertEqual(laterCopy.green, 255)
            XCTAssertEqual(laterCopy.blue, 128, accuracy: 1)
            XCTAssertEqual(laterCopy.alpha, 255)
        }
    }

    func testRuntimeCopiesDoNotDuplicateFillsWhenAnIndependentStreamIsAppended() async {
        let path = Self.nestedPath()
        var context = CanvasGraphicsContext()
        context.fill(path, with: .color(Self.red))
        var copy = context.makeLayerContext()
        copy.fill(path, with: .color(Self.blue), style: FillStyle(eoFill: true))
        context.append(contentsOf: copy)
        var independent = CanvasGraphicsContext()
        independent.fill(Path(Rect(x: 28, y: 28, width: 8, height: 8)), with: .color(Self.green))
        context.append(contentsOf: independent)
        var commands: [RenderCommand] = []
        context.appendCommands(
            into: &commands, origin: .zero, clipRect: nil, opacity: 1, displayScale: 1)
        let frame = RenderFrame(clearColor: .clear, commands: commands)
        let surface = GPUIRawSceneRasterizer.rasterize(frame, size: Self.size)

        XCTAssertEqual(commands.count, 3)
        XCTAssertEqual(fills(in: frame).map(\.fillRule), [.nonZero, .evenOdd, .nonZero])
        XCTAssertEqual(pixel(surface, x: 12, y: 32).blue, 255)
        XCTAssertEqual(pixel(surface, x: 12, y: 32).red, 0)
        XCTAssertEqual(pixel(surface, x: 22, y: 32).red, 255)
        XCTAssertEqual(pixel(surface, x: 22, y: 32).blue, 0)
        XCTAssertEqual(pixel(surface, x: 32, y: 32).green, 255)
    }

    func testGradientFrameFallbackKeepsTheRuleWhileUsingItsFirstStop() async throws {
        let first = Color(red: 1, green: 0, blue: 0, alpha: 0.5)
        let gradient = WinSwiftUI.Gradient(colors: [first, Self.blue])
        for evenOdd in [false, true] {
            let result = filledSnapshot(
                path: Self.nestedPath(), style: FillStyle(eoFill: evenOdd),
                shading: .linearGradient(
                    gradient, startPoint: Point(x: 8, y: 32), endPoint: Point(x: 56, y: 32)))
            let fill = try XCTUnwrap(fills(in: result.frame).first)
            let degraded = FramePathDegradation.degradingPathsToBitmaps(in: result.frame)
            let surface = GPUIRawSceneRasterizer.rasterize(degraded, size: Self.size)

            XCTAssertEqual(fill.fillRule, evenOdd ? .evenOdd : .nonZero)
            XCTAssertEqual(fill.color, first)
            XCTAssertTrue(fills(in: degraded).isEmpty)
            assertRingAndHole(surface, ringAlpha: 128, holeAlpha: evenOdd ? 0 : 128)
            XCTAssertEqual(pixel(surface, x: 12, y: 32).red, 255)
            XCTAssertEqual(pixel(surface, x: 52, y: 32).red, 255)
            XCTAssertEqual(pixel(surface, x: 52, y: 32).blue, 0)
        }
    }

    func testSimpleRectangleRetainsDefaultPixelsWhenEvenOddIsRequested() async {
        let path = Path(Rect(x: 8, y: 8, width: 48, height: 48))
        let nonZero = filledSnapshot(path: path)
        let evenOdd = filledSnapshot(path: path, style: FillStyle(eoFill: true))

        XCTAssertEqual(raster(nonZero).pixels, raster(evenOdd).pixels)
        XCTAssertEqual(pixel(raster(evenOdd), x: 32, y: 32).alpha, 255)
        XCTAssertEqual(nonZero.scene.paintMetrics.pathsPromotedToGPU, 1)
        XCTAssertEqual(evenOdd.scene.paintMetrics.pathsPromotedToGPU, 1)
        XCTAssertEqual(evenOdd.scene.paintMetrics.pathsRasterizedOnCPU, 0)
    }
}
