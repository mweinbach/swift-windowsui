import Foundation
import SwiftWindowsCore
import SwiftWindowsGraphics
import XCTest

@testable import SwiftWindowsRendererD3D11
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

    private func gradientQuads(in scene: GPUIScene) -> [QuadPrimitive] {
        scene.layers.flatMap(\.quads).filter(\.usesDirectionalGradient)
    }

    func testAxisAlignedPathFillPromotesEveryGradientStopToGPUQuads() async throws {
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

        let quads = gradientQuads(in: result.scene)
        XCTAssertEqual(quads.count, 2)
        XCTAssertEqual(quads[0].gradientSegmentEnd, 0.25, accuracy: 0.0001)
        XCTAssertEqual(quads[0].endG, 1, accuracy: 0.0001)
        XCTAssertEqual(quads[1].endB, 1, accuracy: 0.0001)
        XCTAssertTrue(result.scene.layers.flatMap(\.paths).isEmpty)
        XCTAssertEqual(result.scene.paintMetrics.pathsPromotedToGPU, 1)
        XCTAssertEqual(result.scene.paintMetrics.quadInstancesFromPromotedPaths, 2)
        XCTAssertEqual(result.scene.paintMetrics.pathsRasterizedOnCPU, 0)
        XCTAssertEqual(MemoryLayout<QuadPrimitive>.stride, 144)

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

        let quads = gradientQuads(in: result.scene)
        XCTAssertEqual(quads.count, 2)
        XCTAssertEqual(quads[0].startB, 1, accuracy: 0.0001)
        XCTAssertEqual(quads[0].gradientSegmentEnd, 0.75, accuracy: 0.0001)
        XCTAssertEqual(quads[1].endR, 1, accuracy: 0.0001)

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

        let quad = try XCTUnwrap(gradientQuads(in: result.scene).first)
        XCTAssertEqual(quad.startA, 0, accuracy: 0.0001)
        XCTAssertEqual(quad.endB, 1, accuracy: 0.0001)
        XCTAssertEqual(result.scene.paintMetrics.pathsPromotedToGPU, 1)
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

        let quad = try XCTUnwrap(gradientQuads(in: result.scene).first)
        XCTAssertEqual(quad.startA, 0.25, accuracy: 0.0001)
        XCTAssertEqual(quad.endA, 0.25, accuracy: 0.0001)
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

        let quad = try XCTUnwrap(gradientQuads(in: result.scene).first)
        XCTAssertEqual(quad.x, 15, accuracy: 0.0001)
        XCTAssertEqual(quad.y, 30, accuracy: 0.0001)
        XCTAssertEqual(quad.width, 150, accuracy: 0.0001)
        XCTAssertEqual(quad.height, 90, accuracy: 0.0001)
        XCTAssertEqual(quad.effectParam3, 150, accuracy: 0.0001)

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

        let quad = try XCTUnwrap(gradientQuads(in: result.scene).first)
        XCTAssertEqual(quad.effectParam1, 30, accuracy: 0.0001)
        XCTAssertEqual(quad.effectParam3, 80, accuracy: 0.0001)
        let surface = raster(result.scene)
        XCTAssertEqual(pixel(surface, x: 15, y: 50).red, 255)
        XCTAssertEqual(pixel(surface, x: 35, y: 50).blue, 0)
        XCTAssertEqual(pixel(surface, x: 100, y: 50).blue, 255)
        XCTAssertEqual(pixel(surface, x: 125, y: 50).red, 0)
    }

    func testDiagonalMultistopGradientPromotesAndMatchesHardwarePixels() async throws {
        let gradient = threeStopGradient
        let result = snapshot(
            Canvas { context, _ in
                context.fill(
                    Path(Rect(x: 12, y: 12, width: 112, height: 88)),
                    with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(x: 28, y: 24),
                        endPoint: CGPoint(x: 108, y: 88)
                    )
                )
            }
            .frame(width: 160, height: 120)
        )

        let quads = gradientQuads(in: result.scene)
        XCTAssertEqual(quads.count, 2)
        XCTAssertEqual(result.scene.paintMetrics.pathsPromotedToGPU, 1)
        XCTAssertEqual(result.scene.paintMetrics.pathsRasterizedOnCPU, 0)
        XCTAssertEqual(quads[0].effectParam1, 16, accuracy: 0.0001)
        XCTAssertEqual(quads[0].effectParam2, 12, accuracy: 0.0001)
        XCTAssertEqual(quads[0].effectParam3, 96, accuracy: 0.0001)
        XCTAssertEqual(quads[0].effectParam4, 76, accuracy: 0.0001)

        let cpu = raster(result.scene)
        XCTAssertGreaterThan(pixel(cpu, x: 18, y: 18).red, 245)
        XCTAssertGreaterThan(pixel(cpu, x: 48, y: 40).green, 240)
        XCTAssertGreaterThan(pixel(cpu, x: 116, y: 94).blue, 245)

        let gpu = try WARPBatchRenderer.render(result.scene, size: Self.size)
        let report = comparePixels(gpu, cpu, tolerance: 4)
        XCTAssertGreaterThanOrEqual(
            report.matchRatio, 0.995,
            "Directional GPU gradient mismatch: ratio \(report.matchRatio), max delta \(report.maxChannelDelta)")
    }

    func testRoundedRectangleGradientUsesOneDirectionalQuadPerColorInterval() async throws {
        let gradient = threeStopGradient
        let result = snapshot(
            Canvas { context, _ in
                var path = Path()
                path.addRoundedRect(Rect(x: 12, y: 18, width: 100, height: 72), cornerRadius: 16)
                context.fill(
                    path,
                    with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(x: 12, y: 18),
                        endPoint: CGPoint(x: 112, y: 90)
                    )
                )
            }
            .frame(width: 160, height: 120)
        )

        let quads = gradientQuads(in: result.scene)
        XCTAssertEqual(quads.count, 2)
        XCTAssertTrue(quads.allSatisfy { abs($0.cornerRadius - 16) < 0.0001 })
        XCTAssertTrue(result.scene.layers.flatMap(\.paths).isEmpty)
        XCTAssertEqual(result.scene.paintMetrics.pathsPromotedToGPU, 1)

        let cpu = raster(result.scene)
        let gpu = try WARPBatchRenderer.render(result.scene, size: Self.size)
        let report = comparePixels(gpu, cpu, tolerance: 4)
        XCTAssertGreaterThanOrEqual(report.matchRatio, 0.995)
    }

    func testComplexGradientFillRetainsContinuousCachedPathCoverage() async throws {
        let gradient = threeStopGradient
        let result = snapshot(
            Canvas { context, _ in
                var path = Path()
                path.moveTo(Point(x: 20, y: 20))
                path.addLine(to: Point(x: 120, y: 38))
                path.addLine(to: Point(x: 52, y: 98))
                path.closeSubpath()
                context.fill(
                    path,
                    with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(x: 20, y: 20),
                        endPoint: CGPoint(x: 120, y: 98)
                    )
                )
            }
            .frame(width: 160, height: 120)
        )

        XCTAssertTrue(gradientQuads(in: result.scene).isEmpty)
        XCTAssertNotNil(try XCTUnwrap(result.scene.layers.flatMap(\.paths).first).fillGradient)
        XCTAssertEqual(result.scene.paintMetrics.pathsRasterizedOnCPU, 1)
    }

    func testPromotedHardStopCompositesEachTranslucentPixelOnlyOnce() async throws {
        let translucentRed = Color(red: 1, green: 0, blue: 0, alpha: 0.4)
        let translucentBlue = Color(red: 0, green: 0, blue: 1, alpha: 0.4)
        let gradient = WinSwiftUI.Gradient(
            stops: [
                WinSwiftUI.Gradient.Stop(color: translucentRed, location: 0),
                WinSwiftUI.Gradient.Stop(color: translucentRed, location: 0.5),
                WinSwiftUI.Gradient.Stop(color: translucentBlue, location: 0.5),
                WinSwiftUI.Gradient.Stop(color: translucentBlue, location: 1),
            ])
        let result = snapshot(
            Canvas { context, _ in
                context.fill(
                    Path(Rect(x: 0, y: 16, width: 101, height: 64)),
                    with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(x: 0, y: 48),
                        endPoint: CGPoint(x: 101, y: 48)
                    )
                )
            }
            .frame(width: 160, height: 120)
        )

        XCTAssertEqual(gradientQuads(in: result.scene).count, 2)
        let cpu = raster(result.scene)
        XCTAssertEqual(pixel(cpu, x: 49, y: 48).red, 102, accuracy: 1)
        XCTAssertEqual(pixel(cpu, x: 50, y: 48).red, 0, accuracy: 1)
        XCTAssertEqual(pixel(cpu, x: 50, y: 48).blue, 102, accuracy: 1)
        XCTAssertEqual(pixel(cpu, x: 51, y: 48).blue, 102, accuracy: 1)

        let gpu = try WARPBatchRenderer.render(result.scene, size: Self.size)
        let report = comparePixels(gpu, cpu, tolerance: 4)
        XCTAssertGreaterThanOrEqual(report.matchRatio, 0.995)
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

        let quad = try XCTUnwrap(gradientQuads(in: scene).first)
        XCTAssertEqual(quad.gradientAxis, 2)
        XCTAssertEqual(scene.paintMetrics.pathsPromotedToGPU, 1)
        XCTAssertEqual(scene.paintMetrics.pathsRasterizedOnCPU, 0)
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
