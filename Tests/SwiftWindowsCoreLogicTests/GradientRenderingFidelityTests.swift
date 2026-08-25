import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Gradient locations are renderer data, not source-compatibility metadata:
/// every retained painter, frame bridge and D3D11 shader must show the same
/// authored colors at the same physical positions.
@MainActor
final class GradientRenderingFidelityTests: XCTestCase {
    private static let size = IntSize(width: 120, height: 80)
    private static let red = Color(red: 1, green: 0, blue: 0, alpha: 1)
    private static let green = Color(red: 0, green: 1, blue: 0, alpha: 1)
    private static let blue = Color(red: 0, green: 0, blue: 1, alpha: 1)

    private func scene(
        for gradient: SwiftWindowsGraphics.LinearGradient,
        frame: Rect = Rect(x: 0, y: 0, width: 120, height: 80),
        cornerRadius: Double = 0,
        clearColor: Color = .black
    ) -> GPUIScene {
        let root = ViewNode(
            frame: frame,
            backgroundColor: gradient.startColor,
            backgroundGradient: .linear(gradient),
            cornerRadius: cornerRadius
        )
        return ScenePainter.paint(
            root: root, clearColor: clearColor,
            surfaceSize: Size(width: Double(Self.size.width), height: Double(Self.size.height)))
    }

    private func pixel(_ surface: BitmapSurface, x: Int, y: Int = 40) -> (red: Int, green: Int, blue: Int, alpha: Int) {
        let offset = y * Int(surface.bytesPerRow) + x * 4
        return (
            red: Int(surface.pixels[offset + 2]),
            green: Int(surface.pixels[offset + 1]),
            blue: Int(surface.pixels[offset]),
            alpha: Int(surface.pixels[offset + 3])
        )
    }

    private func raster(_ scene: GPUIScene) -> BitmapSurface {
        GPUIRawSceneRasterizer.rasterize(scene, size: Self.size)
    }

    func testCanonicalTwoStopGradientKeepsOneUnchangedQuad() async {
        let gradient = SwiftWindowsGraphics.LinearGradient(
            startColor: Self.red, endColor: Self.blue, axis: .horizontal)
        let scene = scene(for: gradient)

        XCTAssertEqual(scene.layers[0].quads.count, 1)
        XCTAssertEqual(scene.layers[0].quads[0].gradientSegmentStart, 0)
        XCTAssertEqual(scene.layers[0].quads[0].gradientSegmentEnd, 0)
        XCTAssertEqual(scene.layers[0].quads[0].gradientSegmentMode, 0)
        XCTAssertEqual(MemoryLayout<QuadPrimitive>.stride, 144)

        // Existing control sheens intentionally let their base fill override
        // the first stop. Direction correction must not rewrite that legacy
        // primitive unless the SwiftUI bridge explicitly marked it reversed.
        let controlQuad = QuadPrimitive(
            x: 0, y: 0, width: 120, height: 80,
            startR: 0.35, startG: 0.45, startB: 0.55,
            endR: 0.35, endG: 0.45, endB: 0.55,
            gradientAxis: 1)
        XCTAssertEqual(controlQuad.segmented(for: gradient), [controlQuad])
    }

    func testIntermediateStopIsDrawnAtItsAuthoredLocation() async {
        let gradient = SwiftWindowsGraphics.LinearGradient(
            stops: [
                GradientStop(color: Self.red, position: 0),
                GradientStop(color: Self.green, position: 0.2),
                GradientStop(color: Self.blue, position: 1),
            ], axis: .horizontal)
        let scene = scene(for: gradient)
        let surface = raster(scene)

        XCTAssertEqual(scene.layers[0].quads.count, 2)
        let stop = pixel(surface, x: 24)
        XCTAssertGreaterThan(stop.green, 245)
        XCTAssertLessThan(stop.red, 12)
        XCTAssertLessThan(stop.blue, 12)
    }

    func testDisplacedStopsExtendTheirEndpointColors() async {
        let gradient = SwiftWindowsGraphics.LinearGradient(
            stops: [
                GradientStop(color: Self.red, position: 0.25),
                GradientStop(color: Self.blue, position: 0.75),
            ], axis: .horizontal)
        let scene = scene(for: gradient)
        let surface = raster(scene)

        XCTAssertEqual(scene.layers[0].quads.count, 3)
        XCTAssertEqual(pixel(surface, x: 10).red, 255)
        XCTAssertEqual(pixel(surface, x: 10).blue, 0)
        XCTAssertEqual(pixel(surface, x: 110).red, 0)
        XCTAssertEqual(pixel(surface, x: 110).blue, 255)
    }

    func testDuplicatePositionsCreateAHardTransitionWithoutSeams() async {
        let gradient = SwiftWindowsGraphics.LinearGradient(
            stops: [
                GradientStop(color: Self.red, position: 0),
                GradientStop(color: Self.red, position: 0.5),
                GradientStop(color: Self.blue, position: 0.5),
                GradientStop(color: Self.blue, position: 1),
            ], axis: .horizontal)
        let scene = scene(for: gradient)
        let surface = raster(scene)

        XCTAssertEqual(scene.layers[0].quads.count, 2)
        XCTAssertEqual(pixel(surface, x: 59).red, 255)
        XCTAssertEqual(pixel(surface, x: 59).blue, 0)
        XCTAssertEqual(pixel(surface, x: 60).red, 0)
        XCTAssertEqual(pixel(surface, x: 60).blue, 255)
    }

    func testTranslucentSegmentBoundaryIsCompositedExactlyOnce() async {
        let translucent = Color(red: 1, green: 0, blue: 0, alpha: 0.4)
        let gradient = SwiftWindowsGraphics.LinearGradient(
            stops: [
                GradientStop(color: translucent, position: 0),
                GradientStop(color: translucent, position: 0.5),
                GradientStop(color: translucent, position: 1),
            ], axis: .horizontal)
        // Pixel 50's center is exactly 50.5 / 101 == 0.5. An inclusive
        // boundary on both passes would blend 0.4 twice and jump to 0.64.
        let surface = raster(scene(for: gradient, frame: Rect(x: 0, y: 0, width: 101, height: 80)))

        XCTAssertEqual(pixel(surface, x: 49).red, 102, accuracy: 1)
        XCTAssertEqual(pixel(surface, x: 50).red, 102, accuracy: 1)
        XCTAssertEqual(pixel(surface, x: 51).red, 102, accuracy: 1)
    }

    func testTransparentFirstStopDoesNotSuppressTheWholeGradient() async {
        let gradient = SwiftWindowsGraphics.LinearGradient(
            startColor: Color(red: 1, green: 0, blue: 0, alpha: 0),
            endColor: Self.blue,
            axis: .horizontal)
        let scene = scene(for: gradient)
        let surface = raster(scene)

        XCTAssertEqual(scene.layers[0].quads.count, 1)
        XCTAssertGreaterThan(pixel(surface, x: 110).blue, 200)
    }

    func testReversedSwiftUIEndpointsReverseColorsAndStopPositions() async {
        let authored = WinSwiftUI.LinearGradient(
            gradient: WinSwiftUI.Gradient(
                stops: [
                    WinSwiftUI.Gradient.Stop(color: Self.red, location: 0),
                    WinSwiftUI.Gradient.Stop(color: Self.green, location: 0.2),
                    WinSwiftUI.Gradient.Stop(color: Self.blue, location: 1),
                ]),
            startPoint: .trailing,
            endPoint: .leading)
        let retained = SwiftWindowsGraphics.LinearGradient(authored)

        XCTAssertEqual(retained.stops.map(\.color), [Self.blue, Self.green, Self.red])
        XCTAssertEqual(retained.stops[1].position, 0.8, accuracy: 0.0001)

        let snapshot = WinSwiftUIRendererSnapshotter.snapshot(
            of: WinSwiftUI.Rectangle().fill(authored).frame(width: 120, height: 80),
            size: Self.size, displayScale: 1, clearColor: .black)
        let surface = raster(snapshot.scene)

        XCTAssertGreaterThan(pixel(surface, x: 4).blue, 240)
        XCTAssertGreaterThan(pixel(surface, x: 115).red, 180)
    }

    func testReversedCanonicalTwoStopShapeStaysOneGradientNotASolidFill() async {
        let authored = WinSwiftUI.LinearGradient(
            colors: [Self.red, Self.blue], startPoint: .trailing, endPoint: .leading)
        let snapshot = WinSwiftUIRendererSnapshotter.snapshot(
            of: WinSwiftUI.Rectangle().fill(authored).frame(width: 120, height: 80),
            size: Self.size, displayScale: 1, clearColor: .black)
        let quads = snapshot.scene.layers.flatMap(\.quads).filter { $0.width == 120 && $0.height == 80 }
        let surface = raster(snapshot.scene)

        XCTAssertEqual(quads.count, 1, "reversing endpoints must not add a second full-surface pass")
        XCTAssertGreaterThan(pixel(surface, x: 5).blue, 235)
        XCTAssertGreaterThan(pixel(surface, x: 115).red, 235)
    }

    func testCanvasShadingPreservesReversedEndpointsAndMiddleStop() async {
        let gradient = WinSwiftUI.Gradient(colors: [Self.red, Self.green, Self.blue])
        let view = WinSwiftUI.Canvas { context, _ in
            context.fill(
                Rect(x: 0, y: 0, width: 120, height: 80),
                with: .linearGradient(
                    gradient,
                    startPoint: CGPoint(x: 120, y: 40),
                    endPoint: CGPoint(x: 0, y: 40)))
        }
        .frame(width: 120, height: 80)
        let snapshot = WinSwiftUIRendererSnapshotter.snapshot(
            of: view, size: Self.size, displayScale: 1, clearColor: .black)
        let surface = raster(snapshot.scene)

        XCTAssertGreaterThan(pixel(surface, x: 5).blue, 225)
        XCTAssertGreaterThan(pixel(surface, x: 60).green, 245)
        XCTAssertGreaterThan(pixel(surface, x: 115).red, 225)
    }

    func testFrameBridgePreservesIntermediateStopsAndPaintOrder() async {
        let gradient = SwiftWindowsGraphics.LinearGradient(
            stops: [
                GradientStop(color: Self.red, position: 0),
                GradientStop(color: Self.green, position: 0.2),
                GradientStop(color: Self.blue, position: 1),
            ], axis: .horizontal)
        let frame = RenderFrame(
            clearColor: .black,
            commands: [
                .fillRect(
                    FillRectCommand(
                        rect: Rect(x: 0, y: 0, width: 120, height: 80),
                        color: Self.red,
                        gradient: gradient))
            ])
        let scene = GPUIScene(from: frame, surfaceSize: Size(width: 120, height: 80))
        let surface = raster(scene)

        XCTAssertEqual(scene.layers[0].quads.count, 2)
        XCTAssertEqual(scene.layers[0].paintOperations.count, 1)
        XCTAssertGreaterThan(pixel(surface, x: 24).green, 245)
    }

    func testNonfiniteOutOfRangeAndExcessiveStopsAreBounded() async {
        var stops = [
            GradientStop(color: Self.red, position: -.infinity),
            GradientStop(color: Self.red, position: -1),
            GradientStop(color: Self.blue, position: .nan),
        ]
        for index in 0..<256 {
            stops.append(GradientStop(color: Self.green, position: Float(index) / 255))
        }
        stops.append(GradientStop(color: Self.blue, position: 2))

        let gradient = SwiftWindowsGraphics.LinearGradient(stops: stops, axis: .horizontal)
        let segments = gradient.renderedSegments

        XCTAssertLessThanOrEqual(segments.count, SwiftWindowsGraphics.LinearGradient.maximumRenderedStops)
        XCTAssertEqual(segments.first?.start, 0)
        XCTAssertEqual(segments.last?.end, 1)
        XCTAssertTrue(segments.allSatisfy { $0.start.isFinite && $0.end.isFinite && $0.end > $0.start })
    }

    func testInteriorStopsReserveBudgetForBothEndpointExtensions() async {
        let maximum = SwiftWindowsGraphics.LinearGradient.maximumRenderedStops
        let stops = (0..<maximum).map { index in
            GradientStop(
                color: index.isMultiple(of: 2) ? Self.red : Self.blue,
                position: Float(index + 1) / Float(maximum + 1))
        }
        let gradient = SwiftWindowsGraphics.LinearGradient(stops: stops, axis: .horizontal)
        let segments = gradient.renderedSegments

        XCTAssertEqual(segments.count, maximum)
        XCTAssertEqual(segments.first?.start, 0)
        XCTAssertEqual(segments.last?.end, 1)
        XCTAssertEqual(segments.first?.startColor, Self.red)
        XCTAssertEqual(segments.last?.endColor, Self.blue)
        XCTAssertTrue(segments.allSatisfy { $0.end > $0.start })
        XCTAssertEqual(scene(for: gradient).layers[0].quads.count, maximum)
    }

    func testMultistopBackdropMaterialUsesOneBoundedBlurPass() async throws {
        let gradient = SwiftWindowsGraphics.LinearGradient(
            stops: [
                GradientStop(color: Self.red, position: 0),
                GradientStop(color: Self.green, position: 0.5),
                GradientStop(color: Self.blue, position: 1),
            ], axis: .horizontal)
        let root = ViewNode(
            frame: Rect(x: 8, y: 8, width: 104, height: 64),
            backgroundColor: Self.red,
            backgroundGradient: .linear(gradient),
            cornerRadius: 14,
            blurRadius: 8)
        let scene = ScenePainter.paint(
            root: root,
            clearColor: Color(red: 0.12, green: 0.15, blue: 0.19, alpha: 1),
            surfaceSize: Size(width: Double(Self.size.width), height: Double(Self.size.height)))

        XCTAssertEqual(scene.layers[0].quads.count, 1)
        guard let quad = scene.layers[0].quads.first else {
            return XCTFail("a multistop material must retain one blurred presentation primitive")
        }
        XCTAssertEqual(quad.blurRadius, 8)
        XCTAssertEqual(quad.gradientSegmentMode, 0)
        XCTAssertEqual(quad.startR, 1)
        XCTAssertEqual(quad.endB, 1)

        let report = comparePixels(
            try WARPBatchRenderer.render(scene, size: Self.size),
            raster(scene),
            tolerance: 4)
        XCTAssertGreaterThanOrEqual(report.matchRatio, 0.995)
    }

    func testRoundedTranslucentMultistopGradientMatchesRealD3D11Pixels() async throws {
        let gradient = SwiftWindowsGraphics.LinearGradient(
            stops: [
                GradientStop(color: Color(red: 0.95, green: 0.1, blue: 0.2, alpha: 0.75), position: 0),
                GradientStop(color: Color(red: 0.1, green: 0.9, blue: 0.2, alpha: 0.45), position: 0.33),
                GradientStop(color: Color(red: 0.2, green: 0.25, blue: 0.95, alpha: 0.85), position: 1),
            ], axis: .horizontal)
        let scene = scene(
            for: gradient,
            frame: Rect(x: 8, y: 8, width: 104, height: 64),
            cornerRadius: 18,
            clearColor: Color(red: 0.08, green: 0.1, blue: 0.14, alpha: 1))
        let cpu = raster(scene)
        let gpu = try WARPBatchRenderer.render(scene, size: Self.size)
        let report = comparePixels(gpu, cpu, tolerance: 4)

        XCTAssertGreaterThanOrEqual(
            report.matchRatio, 0.995,
            "GPU/CPU multistop gradient mismatch: ratio \(report.matchRatio), max delta \(report.maxChannelDelta)")
    }
}
