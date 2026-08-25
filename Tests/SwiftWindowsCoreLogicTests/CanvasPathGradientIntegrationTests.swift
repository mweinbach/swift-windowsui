import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsUI
@testable import WinSwiftUI

/// Canvas gradients must survive the complete retained path pipeline instead
/// of being collapsed to their first stop before geometry reaches the scene.
@MainActor
final class CanvasPathGradientIntegrationTests: XCTestCase {
    private static let size = IntSize(width: 160, height: 120)
    private static let red = Color(red: 1, green: 0, blue: 0, alpha: 1)
    private static let green = Color(red: 0, green: 1, blue: 0, alpha: 1)
    private static let blue = Color(red: 0, green: 0, blue: 1, alpha: 1)

    private func snapshot<V: View>(
        _ view: V,
        displayScale: Double = 1,
        clearColor: Color = .black
    ) -> WinSwiftUIRenderSnapshot {
        WinSwiftUIRendererSnapshotter.snapshot(
            of: view,
            size: Self.size,
            displayScale: displayScale,
            clearColor: clearColor
        )
    }

    private func raster(
        _ scene: GPUIScene,
        displayScale: Double = 1
    ) -> BitmapSurface {
        GPUIRawSceneRasterizer.rasterize(
            scene,
            size: IntSize(
                width: Int32(Double(Self.size.width) * displayScale),
                height: Int32(Double(Self.size.height) * displayScale)
            )
        )
    }

    private func pixel(
        _ surface: BitmapSurface,
        x: Int,
        y: Int
    ) -> (red: Int, green: Int, blue: Int, alpha: Int) {
        let offset = y * Int(surface.bytesPerRow) + x * 4
        return (
            red: Int(surface.pixels[offset + 2]),
            green: Int(surface.pixels[offset + 1]),
            blue: Int(surface.pixels[offset]),
            alpha: Int(surface.pixels[offset + 3])
        )
    }

    private var threeStopGradient: WinSwiftUI.Gradient {
        WinSwiftUI.Gradient(
            stops: [
                WinSwiftUI.Gradient.Stop(color: Self.red, location: 0),
                WinSwiftUI.Gradient.Stop(color: Self.green, location: 0.25),
                WinSwiftUI.Gradient.Stop(color: Self.blue, location: 1),
            ])
    }

    func testAxisAlignedPathFillPreservesEveryGradientStopAndAvoidsSolidQuadPromotion() async throws {
        let gradient = threeStopGradient
        let result = snapshot(
            Canvas { context, _ in
                context.fill(
                    Path(Rect(x: 10, y: 20, width: 100, height: 60)),
                    with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(x: 10, y: 50),
                        endPoint: CGPoint(x: 110, y: 50)
                    )
                )
            }
            .frame(width: 160, height: 120)
        )

        let primitive = try XCTUnwrap(result.scene.layers.flatMap(\.paths).first)
        let retainedGradient = try XCTUnwrap(primitive.fillGradient)
        XCTAssertEqual(retainedGradient.axis, .horizontal)
        XCTAssertEqual(retainedGradient.stops.count, 3)
        XCTAssertEqual(retainedGradient.stops[1].position, 0.25, accuracy: 0.0001)
        XCTAssertEqual(result.scene.paintMetrics.pathsRasterizedOnCPU, 1)

        let surface = raster(result.scene)
        XCTAssertGreaterThan(pixel(surface, x: 12, y: 50).red, 225)
        XCTAssertGreaterThan(pixel(surface, x: 35, y: 50).green, 240)
        XCTAssertGreaterThan(pixel(surface, x: 106, y: 50).blue, 225)
    }

    func testReversedPathGradientRetainsAuthoredDirectionAndMiddleStop() async throws {
        let gradient = threeStopGradient
        let result = snapshot(
            Canvas { context, _ in
                context.fill(
                    Path(Rect(x: 10, y: 20, width: 100, height: 60)),
                    with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(x: 110, y: 50),
                        endPoint: CGPoint(x: 10, y: 50)
                    )
                )
            }
            .frame(width: 160, height: 120)
        )

        let primitive = try XCTUnwrap(result.scene.layers.flatMap(\.paths).first)
        let retainedGradient = try XCTUnwrap(primitive.fillGradient)
        XCTAssertEqual(retainedGradient.stops.map(\.color), [Self.blue, Self.green, Self.red])
        XCTAssertEqual(retainedGradient.stops[1].position, 0.75, accuracy: 0.0001)

        let surface = raster(result.scene)
        XCTAssertGreaterThan(pixel(surface, x: 14, y: 50).blue, 225)
        XCTAssertGreaterThan(pixel(surface, x: 85, y: 50).green, 240)
        XCTAssertGreaterThan(pixel(surface, x: 107, y: 50).red, 225)
    }

    func testTransparentFirstStopDoesNotDiscardVisiblePathGradient() async throws {
        let gradient = WinSwiftUI.Gradient(colors: [
            Color(red: 1, green: 0, blue: 0, alpha: 0),
            Self.blue,
        ])
        let result = snapshot(
            Canvas { context, _ in
                context.fill(
                    Path(Rect(x: 10, y: 20, width: 100, height: 60)),
                    with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(x: 10, y: 50),
                        endPoint: CGPoint(x: 110, y: 50)
                    )
                )
            }
            .frame(width: 160, height: 120)
        )

        let primitive = try XCTUnwrap(result.scene.layers.flatMap(\.paths).first)
        XCTAssertEqual(primitive.fillColor.alpha, 0)
        XCTAssertEqual(primitive.fillGradient?.stops.last?.color, Self.blue)
        XCTAssertGreaterThan(pixel(raster(result.scene), x: 105, y: 50).blue, 215)
    }

    func testContextAndViewOpacityMultiplyIntoEveryPathGradientStop() async throws {
        let gradient = WinSwiftUI.Gradient(colors: [Self.red, Self.blue])
        let result = snapshot(
            Canvas { context, _ in
                context.opacity = 0.5
                context.fill(
                    Path(Rect(x: 10, y: 20, width: 100, height: 60)),
                    with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(x: 10, y: 50),
                        endPoint: CGPoint(x: 110, y: 50)
                    )
                )
            }
            .frame(width: 160, height: 120)
            .opacity(0.5),
            clearColor: .clear
        )

        let primitive = try XCTUnwrap(result.scene.layers.flatMap(\.paths).first)
        let retainedGradient = try XCTUnwrap(primitive.fillGradient)
        XCTAssertEqual(retainedGradient.stops[0].color.alpha, 0.25, accuracy: 0.0001)
        XCTAssertEqual(retainedGradient.stops[1].color.alpha, 0.25, accuracy: 0.0001)
        XCTAssertEqual(pixel(raster(result.scene), x: 60, y: 50).alpha, 64, accuracy: 1)
    }

    func testGradientStrokeRetainsStopsStrokeStyleAndDashedGeometry() async throws {
        let gradient = WinSwiftUI.Gradient(colors: [Self.red, Self.green, Self.blue])
        let result = snapshot(
            Canvas { context, _ in
                var path = Path()
                path.moveTo(Point(x: 10, y: 40))
                path.lineTo(Point(x: 110, y: 40))
                context.stroke(
                    path,
                    with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(x: 10, y: 40),
                        endPoint: CGPoint(x: 110, y: 40)
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .bevel, miterLimit: 4)
                )
            }
            .frame(width: 160, height: 120)
        )

        let primitive = try XCTUnwrap(result.scene.layers.flatMap(\.paths).first)
        let retainedGradient = try XCTUnwrap(primitive.strokeGradient)
        XCTAssertEqual(retainedGradient.stops.count, 3)
        XCTAssertEqual(primitive.lineWidth, 8, accuracy: 0.0001)
        XCTAssertEqual(primitive.lineCap, .round)
        XCTAssertEqual(primitive.lineJoin, .bevel)

        let surface = raster(result.scene)
        XCTAssertGreaterThan(pixel(surface, x: 16, y: 40).red, 200)
        XCTAssertGreaterThan(pixel(surface, x: 60, y: 40).green, 235)
        XCTAssertGreaterThan(pixel(surface, x: 104, y: 40).blue, 200)
    }

    func testGradientRectStrokeAlsoUsesTheRetainedPathPipeline() async throws {
        let gradient = WinSwiftUI.Gradient(colors: [Self.red, Self.blue])
        let result = snapshot(
            Canvas { context, _ in
                context.stroke(
                    Rect(x: 20, y: 20, width: 80, height: 60),
                    with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(x: 60, y: 20),
                        endPoint: CGPoint(x: 60, y: 80)
                    ),
                    lineWidth: 6
                )
            }
            .frame(width: 160, height: 120)
        )

        let primitive = try XCTUnwrap(result.scene.layers.flatMap(\.paths).first)
        XCTAssertEqual(primitive.strokeGradient?.axis, .vertical)

        let surface = raster(result.scene)
        XCTAssertGreaterThan(pixel(surface, x: 60, y: 20).red, 225)
        XCTAssertGreaterThan(pixel(surface, x: 60, y: 79).blue, 225)
    }

    func testPathGradientGeometryAndStopLocationsScaleExactlyOnce() async throws {
        let gradient = threeStopGradient
        let scale = 1.5
        let result = snapshot(
            Canvas { context, _ in
                context.fill(
                    Path(Rect(x: 10, y: 20, width: 100, height: 60)),
                    with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(x: 10, y: 50),
                        endPoint: CGPoint(x: 110, y: 50)
                    )
                )
            }
            .frame(width: 160, height: 120),
            displayScale: scale
        )

        let primitive = try XCTUnwrap(result.scene.layers.flatMap(\.paths).first)
        XCTAssertEqual(primitive.bounds.origin.x, 15, accuracy: 0.0001)
        XCTAssertEqual(primitive.bounds.origin.y, 30, accuracy: 0.0001)
        XCTAssertEqual(primitive.bounds.size.width, 150, accuracy: 0.0001)
        XCTAssertEqual(primitive.bounds.size.height, 90, accuracy: 0.0001)

        let surface = raster(result.scene, displayScale: scale)
        XCTAssertGreaterThan(pixel(surface, x: 53, y: 75).green, 235)
        XCTAssertGreaterThan(pixel(surface, x: 158, y: 75).blue, 220)
    }

    func testInsetPathGradientEndpointsExtendTheirAuthoredEndpointColors() async throws {
        let gradient = WinSwiftUI.Gradient(colors: [Self.red, Self.blue])
        let result = snapshot(
            Canvas { context, _ in
                context.fill(
                    Path(Rect(x: 10, y: 20, width: 120, height: 60)),
                    with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(x: 40, y: 50),
                        endPoint: CGPoint(x: 90, y: 50)
                    )
                )
            }
            .frame(width: 160, height: 120)
        )

        XCTAssertNotNil(try XCTUnwrap(result.scene.layers.flatMap(\.paths).first).fillGradient)
        let surface = raster(result.scene)
        XCTAssertEqual(pixel(surface, x: 15, y: 50).red, 255)
        XCTAssertEqual(pixel(surface, x: 35, y: 50).blue, 0)
        XCTAssertEqual(pixel(surface, x: 100, y: 50).blue, 255)
        XCTAssertEqual(pixel(surface, x: 125, y: 50).red, 0)
    }

    func testTranslatedScaledRectGradientTransformsItsInsetAuthoredEndpoints() async {
        let gradient = WinSwiftUI.Gradient(colors: [Self.red, Self.blue])
        var transformedStart = Point.zero
        var transformedEnd = Point.zero
        var transformedMidline = Point.zero
        let result = snapshot(
            Canvas { context, _ in
                context.translateBy(x: 12, y: 20)
                context.scaleBy(x: 1.5, y: 1)
                let start = Point(x: 30, y: 20)
                let end = Point(x: 70, y: 20)
                transformedStart = context.transform.apply(start)
                transformedEnd = context.transform.apply(end)
                transformedMidline = context.transform.apply(Point(x: 50, y: 20))
                context.fill(
                    Rect(x: 10, y: 5, width: 90, height: 30),
                    with: .linearGradient(
                        gradient,
                        startPoint: start,
                        endPoint: end
                    )
                )
            }
            .frame(width: 160, height: 120)
        )

        let surface = raster(result.scene)
        let sampleY = Int(transformedMidline.y)
        XCTAssertEqual(pixel(surface, x: Int(transformedStart.x) - 5, y: sampleY).red, 255)
        XCTAssertEqual(pixel(surface, x: Int(transformedStart.x) - 5, y: sampleY).blue, 0)
        XCTAssertEqual(pixel(surface, x: Int(transformedEnd.x) + 5, y: sampleY).blue, 255)
        XCTAssertEqual(pixel(surface, x: Int(transformedEnd.x) + 5, y: sampleY).red, 0)
    }

    func testCanvasContextRotationTurnsTheAuthoredGradientVector() async {
        let gradient = WinSwiftUI.Gradient(colors: [Self.red, Self.blue])
        let result = snapshot(
            Canvas { context, _ in
                context.translateBy(x: 80, y: 20)
                context.rotate(by: .degrees(90))
                context.fill(
                    Path(Rect(x: 0, y: 0, width: 80, height: 30)),
                    with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(x: 0, y: 15),
                        endPoint: CGPoint(x: 80, y: 15)
                    )
                )
            }
            .frame(width: 160, height: 120)
        )

        let surface = raster(result.scene)
        XCTAssertGreaterThan(pixel(surface, x: 65, y: 24).red, 235)
        XCTAssertLessThan(pixel(surface, x: 65, y: 24).blue, 20)
        XCTAssertGreaterThan(pixel(surface, x: 65, y: 96).blue, 235)
        XCTAssertLessThan(pixel(surface, x: 65, y: 96).red, 20)
    }

    func testReversedGradientDirectionSurvivesCanvasContextRotation() async {
        let gradient = WinSwiftUI.Gradient(colors: [Self.red, Self.blue])
        let result = snapshot(
            Canvas { context, _ in
                context.translateBy(x: 80, y: 20)
                context.rotate(by: .degrees(90))
                context.fill(
                    Path(Rect(x: 0, y: 0, width: 80, height: 30)),
                    with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(x: 80, y: 15),
                        endPoint: CGPoint(x: 0, y: 15)
                    )
                )
            }
            .frame(width: 160, height: 120)
        )

        let surface = raster(result.scene)
        XCTAssertGreaterThan(pixel(surface, x: 65, y: 24).blue, 235)
        XCTAssertGreaterThan(pixel(surface, x: 65, y: 96).red, 235)
    }

    func testWideStrokeGradientUsesAuthoredEndpointsInsteadOfInflatedRasterBounds() async throws {
        let gradient = WinSwiftUI.Gradient(colors: [Self.red, Self.blue])
        let result = snapshot(
            Canvas { context, _ in
                var path = Path()
                path.moveTo(Point(x: 20, y: 60))
                path.lineTo(Point(x: 130, y: 60))
                context.stroke(
                    path,
                    with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(x: 45, y: 60),
                        endPoint: CGPoint(x: 95, y: 60)
                    ),
                    lineWidth: 40
                )
            }
            .frame(width: 160, height: 120)
        )

        let primitive = try XCTUnwrap(result.scene.layers.flatMap(\.paths).first)
        XCTAssertEqual(primitive.lineWidth, 40, accuracy: 0.0001)
        XCTAssertLessThan(primitive.bounds.minX, 20)
        XCTAssertGreaterThan(primitive.bounds.maxX, 130)

        let surface = raster(result.scene)
        XCTAssertEqual(pixel(surface, x: 30, y: 60).red, 255)
        XCTAssertEqual(pixel(surface, x: 30, y: 60).blue, 0)
        XCTAssertEqual(pixel(surface, x: 110, y: 60).red, 0)
        XCTAssertEqual(pixel(surface, x: 110, y: 60).blue, 255)
    }

    func testRotatedCanvasNodeTurnsGradientRampWithItsPath() async throws {
        let gradient = SwiftWindowsGraphics.LinearGradient(
            startColor: Self.red,
            endColor: Self.blue,
            axis: .horizontal
        )
        let canvas = ViewNode(
            frame: Rect(x: 30, y: 30, width: 100, height: 60),
            canvasDraw: { context, _ in
                context.fill(Path(Rect(x: 10, y: 10, width: 60, height: 30)), with: .gradient(gradient))
            },
            transform: Transform2D(rotation: .pi / 2)
        )
        let root = ViewNode(
            frame: Rect(x: 0, y: 0, width: 160, height: 120),
            children: [canvas]
        )
        let scene = ScenePainter.paint(
            root: root,
            clearColor: .black,
            surfaceSize: Size(width: 160, height: 120)
        )

        XCTAssertNotNil(try XCTUnwrap(scene.layers.flatMap(\.paths).first).fillGradient)
        let surface = raster(scene)
        XCTAssertGreaterThan(pixel(surface, x: 85, y: 24).red, 210)
        XCTAssertGreaterThan(pixel(surface, x: 85, y: 75).blue, 210)
    }

    func testFrameFallbackUsesFirstStopForGradientPathFillAndStroke() async {
        let gradient = WinSwiftUI.Gradient(colors: [Self.red, Self.blue])
        let result = snapshot(
            Canvas { context, _ in
                context.opacity = 0.5
                context.fill(
                    Path(Rect(x: 10, y: 10, width: 40, height: 30)),
                    with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(x: 10, y: 25),
                        endPoint: CGPoint(x: 50, y: 25)
                    )
                )
                var outline = Path()
                outline.moveTo(Point(x: 10, y: 70))
                outline.lineTo(Point(x: 80, y: 70))
                context.stroke(
                    outline,
                    with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(x: 10, y: 70),
                        endPoint: CGPoint(x: 80, y: 70)
                    ),
                    lineWidth: 4
                )
            }
            .frame(width: 160, height: 120)
        )

        let fills = result.frame.commands.compactMap { command -> FillPathCommand? in
            if case .fillPath(let fill) = command { return fill }
            return nil
        }
        let strokes = result.frame.commands.compactMap { command -> StrokePathCommand? in
            if case .strokePath(let stroke) = command { return stroke }
            return nil
        }

        XCTAssertEqual(fills.count, 1)
        XCTAssertEqual(strokes.count, 1)
        XCTAssertEqual(fills[0].color.red, 1, accuracy: 0.0001)
        XCTAssertEqual(fills[0].color.alpha, 0.5, accuracy: 0.0001)
        XCTAssertEqual(strokes[0].color.red, 1, accuracy: 0.0001)
        XCTAssertEqual(strokes[0].color.alpha, 0.5, accuracy: 0.0001)
        XCTAssertEqual(strokes[0].style.lineWidth, 4, accuracy: 0.0001)
    }
}
